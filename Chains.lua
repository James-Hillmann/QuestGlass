local ADDON, NS = ...

-- Quest-chain awareness: map achievement criteria to quest lines, compute
-- chain progress, and point the arrow (TomTom, or Blizzard's pin) at the
-- right place given actual progress.

local Chains = {}
NS.Chains = Chains

local QUEST_CRITERIA_TYPE = 27 -- CRITERIA_TYPE_COMPLETE_QUEST

local function BuildStamp()
    local version, build = GetBuildInfo()
    return version .. "-" .. build
end

-- SavedVariables cache: automap.map[achID][questID] = questLineID
local function AutomapDB()
    local db = QuestGlassDB
    if type(db.automap) ~= "table" or db.automap.build ~= BuildStamp() then
        db.automap = { build = BuildStamp(), map = {} }
    end
    return db.automap.map
end

-- Candidate maps for quest→questline lookups: the player's current map and
-- its ancestors (zone → continent).
local function CandidateMaps()
    local maps = {}
    local m = C_Map.GetBestMapForUnit("player")
    while m and m > 0 do
        maps[#maps + 1] = m
        local info = C_Map.GetMapInfo(m)
        m = info and info.parentMapID
        if m == 0 then m = nil end
    end
    return maps
end

-- questID → QuestLineInfo or nil. Tries a map-less call first (newer clients
-- accept it), then the candidate maps. Quest line data loads async, so a nil
-- here may resolve after QUESTLINE_UPDATE — callers re-render on that event.
function Chains.GetQuestLineForQuest(questID, mapID)
    local ok, info = pcall(C_QuestLine.GetQuestLineInfo, questID, mapID)
    if ok and info then return info end
    if not mapID then
        for _, m in ipairs(CandidateMaps()) do
            pcall(C_QuestLine.RequestQuestLinesForMap, m)
            ok, info = pcall(C_QuestLine.GetQuestLineInfo, questID, m)
            if ok and info then return info end
        end
    end
    return nil
end

-- Quest-typed criteria of an achievement: { {critIndex, questID}, ... }
function Chains.QuestCriteria(achID)
    local out = {}
    for i = 1, GetAchievementNumCriteria(achID) do
        local ok, _, ctype, _, _, _, _, _, assetID =
            pcall(GetAchievementCriteriaInfo, achID, i)
        if ok and ctype == QUEST_CRITERIA_TYPE and assetID and assetID > 0 then
            out[#out + 1] = { critIndex = i, questID = assetID }
        end
    end
    return out
end

-- Resolve quest lines for every quest criterion of achID. Results cached in
-- SavedVariables per build; Overrides.lua fills anything that self-resolution
-- misses. Returns (questID→questLineID map, unresolvedCount).
function Chains.EnsureMap(achID)
    local cache = AutomapDB()
    cache[achID] = cache[achID] or {}
    local map = cache[achID]
    local overrides = NS.Overrides[achID]
    local unresolved = 0
    for _, qc in ipairs(Chains.QuestCriteria(achID)) do
        if not map[qc.questID] then
            if overrides and overrides[qc.questID] then
                map[qc.questID] = overrides[qc.questID]
            else
                local info = Chains.GetQuestLineForQuest(qc.questID)
                if info and info.questLineID then
                    map[qc.questID] = info.questLineID
                end
            end
        end
        if not map[qc.questID] then unresolved = unresolved + 1 end
    end
    return map, unresolved
end

-- Quest title, warming the cache when it isn't loaded yet
-- (QUEST_DATA_LOAD_RESULT triggers a re-render via Core.lua).
function Chains.QuestName(questID)
    local name = C_QuestLog.GetTitleForQuestID(questID)
    if not name or name == "" then
        C_QuestLog.RequestLoadQuestByID(questID)
        return nil
    end
    return name
end

-- The heart of it: done / active / upcoming for a whole quest line.
function Chains.State(questLineID)
    local ok, quests = pcall(C_QuestLine.GetQuestLineQuests, questLineID)
    if not ok or not quests or #quests == 0 then return nil end
    local s = { questLineID = questLineID, total = #quests, done = 0,
                active = nil, actives = {}, upcoming = {} }
    for i, q in ipairs(quests) do
        if C_QuestLog.IsQuestFlaggedCompleted(q) then
            s.done = s.done + 1
        elseif C_QuestLog.IsOnQuest(q) then
            -- chains can hand out several quests at once; keep them all
            local a = { index = i, id = q, name = Chains.QuestName(q),
                        objectives = C_QuestLog.GetQuestObjectives(q) }
            s.actives[#s.actives + 1] = a
            s.active = s.active or a
        else
            s.upcoming[#s.upcoming + 1] =
                { index = i, id = q, name = Chains.QuestName(q) }
        end
    end
    return s
end

local lastTomTomUID
local lastMethod

-- Returns the method used ("TomTom" / "map pin") or nil.
local function PlaceWaypoint(mapID, x, y, title)
    if not (mapID and x and y and x > 0 and y > 0) then return nil end
    if TomTom and TomTom.AddWaypoint then
        if lastTomTomUID then
            pcall(TomTom.RemoveWaypoint, TomTom, lastTomTomUID)
        end
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, mapID, x, y,
            { title = title, from = "QuestGlass" })
        if ok and uid then
            lastTomTomUID = uid
            lastMethod = "TomTom"
            return "TomTom"
        end
    end
    if C_Map.CanSetUserWaypointOnMap(mapID) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        lastMethod = "map pin"
        return "map pin"
    end
    return nil
end

-- Remove just the arrow/pin (keep tracking the chain)
local function RemoveArrowOnly()
    if lastTomTomUID and TomTom then
        pcall(TomTom.RemoveWaypoint, TomTom, lastTomTomUID)
        lastTomTomUID = nil
    end
    if lastMethod == "map pin" and C_Map.ClearUserWaypoint then
        C_Map.ClearUserWaypoint()
    end
    lastMethod = nil
end

-- Distance in yards from the player to a point on a map, or nil if it
-- can't be computed (instances, different continents, missing APIs).
local function DistanceToPoint(mapID, x, y)
    if not (C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then
        return nil
    end
    local pm = C_Map.GetBestMapForUnit("player")
    if not (pm and mapID and x and y) then return nil end
    local ppos = C_Map.GetPlayerMapPosition(pm, "player")
    if not ppos then return nil end
    local okP, pCont, pWorld = pcall(C_Map.GetWorldPosFromMapPos, pm, ppos)
    local okT, tCont, tWorld = pcall(C_Map.GetWorldPosFromMapPos, mapID,
        CreateVector2D(x, y))
    if not (okP and okT and pWorld and tWorld and pCont == tCont) then
        return nil
    end
    local dx, dy = pWorld.x - tWorld.x, pWorld.y - tWorld.y
    return math.sqrt(dx * dx + dy * dy)
end

-- True if the arrow should be suppressed because the target is close by;
-- also removes any arrow we had up.
local function TooCloseForArrow(mapID, x, y)
    local minD = QuestGlassDB.options and QuestGlassDB.options.arrowMinDistance or 200
    if minD <= 0 then return nil end
    local dist = DistanceToPoint(mapID, x, y)
    if dist and dist <= minD then
        RemoveArrowOnly()
        return dist
    end
    return nil
end

-- Stop tracking: remove our arrow/pin and forget the chain.
function Chains.ClearWaypoint()
    if lastTomTomUID and TomTom then
        pcall(TomTom.RemoveWaypoint, TomTom, lastTomTomUID)
        lastTomTomUID = nil
    end
    if lastMethod == "map pin" then
        if C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
    end
    lastMethod = nil
    Chains.lastQuestLine = nil
    Chains.lastSignature = nil
end

-- Is this quest part of the given quest line?
function Chains.IsChainQuest(questLineID, questID)
    local ok, quests = pcall(C_QuestLine.GetQuestLineQuests, questLineID)
    if not ok or not quests then return false end
    for _, q in ipairs(quests) do
        if q == questID then return true end
    end
    return false
end

local function StateSignature(s)
    return ("%d:%d:%d"):format(s.questLineID,
        s.active and s.active.id or (s.upcoming[1] and s.upcoming[1].id or 0),
        s.done)
end

-- Point the arrow at the right spot for a chain given actual progress:
-- active quest → its next objective; not started → the next pickup.
-- Returns a status string, or nil + reason.
function Chains.SetWaypoint(questLineID)
    local s = Chains.State(questLineID)
    if not s then return nil, "quest line data not loaded yet" end
    Chains.lastQuestLine = questLineID
    Chains.lastSignature = StateSignature(s)

    if s.active then
        -- Put the quest in the objective tracker and select it
        if C_QuestLog.AddQuestWatch then
            pcall(C_QuestLog.AddQuestWatch, s.active.id)
        end
        local tracked = false
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            C_SuperTrack.SetSuperTrackedQuestID(s.active.id)
            tracked = true
        end
        -- Waypoint APIs vary by client build; feature-detect each in turn,
        -- searching the whole map hierarchy (sub-zone → zone → continent)
        local mapID, x, y
        if C_QuestLog.GetNextWaypoint then
            mapID, x, y = C_QuestLog.GetNextWaypoint(s.active.id)
        end
        local maps = CandidateMaps()
        if not mapID and C_QuestLog.GetNextWaypointForMap then
            for _, m in ipairs(maps) do
                local wx, wy = C_QuestLog.GetNextWaypointForMap(s.active.id, m)
                if wx then mapID, x, y = m, wx, wy break end
            end
        end
        if not mapID and C_QuestLog.GetQuestsOnMap then
            -- modern replacement for QuestPOIGetIconInfo (removed in 12.x)
            for _, m in ipairs(maps) do
                for _, q in ipairs(C_QuestLog.GetQuestsOnMap(m) or {}) do
                    if q.questID == s.active.id then
                        mapID, x, y = m, q.x, q.y
                        break
                    end
                end
                if mapID then break end
            end
        end
        local title = s.active.name or ("Quest " .. s.active.index)
        local near = TooCloseForArrow(mapID, x, y)
        if near then
            return ("%s is right there (%d yds) \226\128\148 no arrow needed")
                :format(title, near)
        end
        local method = PlaceWaypoint(mapID, x, y, title)
        if method then
            return ("arrow \226\134\146 %s via %s (quest %d/%d)")
                :format(title, method, s.active.index, s.total)
        elseif tracked then
            return ("tracking %s (quest %d/%d) \226\128\148 no map coords found for an arrow")
                :format(title, s.active.index, s.total)
        end
        return nil, "no waypoint data for the active quest (try opening the world map first)"
    end

    local nextUp = s.upcoming[1]
    if not nextUp then return nil, "chain already complete" end
    local mapID, x, y
    local info = Chains.GetQuestLineForQuest(nextUp.id)
    if info then
        if info.startMapID and info.startMapID > 0 then
            -- re-query on the start map so x/y are in that map's coordinates
            local onMap = Chains.GetQuestLineForQuest(nextUp.id, info.startMapID)
            if onMap and onMap.x then mapID, x, y = info.startMapID, onMap.x, onMap.y end
        end
        if not mapID and info.x and info.x > 0 then
            mapID, x, y = C_Map.GetBestMapForUnit("player"), info.x, info.y
        end
    end
    if not mapID and C_QuestLine.GetAvailableQuestLines then
        -- the markers the world map itself draws for questline starts
        for _, m in ipairs(CandidateMaps()) do
            pcall(C_QuestLine.RequestQuestLinesForMap, m)
            local ok, lines = pcall(C_QuestLine.GetAvailableQuestLines, m)
            if ok then
                for _, li in ipairs(lines or {}) do
                    if li.questLineID == questLineID and li.x and li.x > 0 then
                        mapID, x, y = m, li.x, li.y
                        break
                    end
                end
            end
            if mapID then break end
        end
    end
    local title = nextUp.name or "Next quest"
    local near = TooCloseForArrow(mapID, x, y)
    if near then
        return ("%s starts right there (%d yds) \226\128\148 no arrow needed")
            :format(title, near)
    end
    local method = PlaceWaypoint(mapID, x, y, title)
    if method then
        return ("arrow \226\134\146 pick up %s via %s (quest %d/%d)")
            :format(title, method, nextUp.index, s.total)
    end
    return nil, "couldn't locate the next quest giver (try again in the achievement's zone)"
end

-- Re-point the arrow after quest turn-in / progress (auto-advance).
-- Only acts when the tracked chain actually moved to a new step, so
-- unrelated quest spam (farming, world quests) never re-places the arrow.
function Chains.RefreshWaypoint()
    if not Chains.lastQuestLine then return end
    local s = Chains.State(Chains.lastQuestLine)
    if not s then return end
    if StateSignature(s) == Chains.lastSignature then return end
    local msg = Chains.SetWaypoint(Chains.lastQuestLine)
    if msg then
        print("|cff7fd5ffQuestGlass:|r " .. msg)
    end
end
