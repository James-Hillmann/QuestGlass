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
                active = nil, upcoming = {} }
    for i, q in ipairs(quests) do
        if C_QuestLog.IsQuestFlaggedCompleted(q) then
            s.done = s.done + 1
        elseif C_QuestLog.IsOnQuest(q) and not s.active then
            s.active = { index = i, id = q, name = Chains.QuestName(q),
                         objectives = C_QuestLog.GetQuestObjectives(q) }
        else
            s.upcoming[#s.upcoming + 1] =
                { index = i, id = q, name = Chains.QuestName(q) }
        end
    end
    return s
end

local lastTomTomUID

local function PlaceWaypoint(mapID, x, y, title)
    if not (mapID and x and y and x > 0 and y > 0) then return false end
    if TomTom and TomTom.AddWaypoint then
        if lastTomTomUID then
            pcall(TomTom.RemoveWaypoint, TomTom, lastTomTomUID)
        end
        lastTomTomUID = TomTom:AddWaypoint(mapID, x, y,
            { title = title, from = "QuestGlass" })
        return true
    end
    if C_Map.CanSetUserWaypointOnMap(mapID) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        return true
    end
    return false
end

-- Point the arrow at the right spot for a chain given actual progress:
-- active quest → its next objective; not started → the next pickup.
-- Returns a status string, or nil + reason.
function Chains.SetWaypoint(questLineID)
    local s = Chains.State(questLineID)
    if not s then return nil, "quest line data not loaded yet" end
    Chains.lastQuestLine = questLineID

    if s.active then
        -- Waypoint APIs vary by client build; feature-detect each in turn
        local mapID, x, y
        if C_QuestLog.GetNextWaypoint then
            mapID, x, y = C_QuestLog.GetNextWaypoint(s.active.id)
        end
        local pm = C_Map.GetBestMapForUnit("player")
        if not mapID and pm and C_QuestLog.GetNextWaypointForMap then
            local wx, wy = C_QuestLog.GetNextWaypointForMap(s.active.id, pm)
            if wx then mapID, x, y = pm, wx, wy end
        end
        if not mapID and pm and C_QuestLog.GetQuestsOnMap then
            -- modern replacement for QuestPOIGetIconInfo (removed in 12.x)
            for _, q in ipairs(C_QuestLog.GetQuestsOnMap(pm) or {}) do
                if q.questID == s.active.id then
                    mapID, x, y = pm, q.x, q.y
                    break
                end
            end
        end
        if not mapID and pm and QuestPOIGetIconInfo then
            local _, px, py = QuestPOIGetIconInfo(s.active.id)
            if px then mapID, x, y = pm, px, py end
        end
        local title = s.active.name or ("Quest " .. s.active.index)
        if PlaceWaypoint(mapID, x, y, title) then
            return ("arrow \226\134\146 %s (quest %d/%d)")
                :format(title, s.active.index, s.total)
        end
        -- last resort: let Blizzard's own tracker navigate to the quest
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            C_SuperTrack.SetSuperTrackedQuestID(s.active.id)
            return ("super-tracking %s (quest %d/%d)")
                :format(title, s.active.index, s.total)
        end
        return nil, "no waypoint data for the active quest (try opening the world map first)"
    end

    local nextUp = s.upcoming[1]
    if not nextUp then return nil, "chain already complete" end
    local info = Chains.GetQuestLineForQuest(nextUp.id)
    if info then
        local mapID, x, y
        if info.startMapID and info.startMapID > 0 then
            mapID = info.startMapID
            -- re-query on the start map so x/y are in that map's coordinates
            local onMap = Chains.GetQuestLineForQuest(nextUp.id, mapID)
            if onMap then x, y = onMap.x, onMap.y end
        else
            mapID, x, y = C_Map.GetBestMapForUnit("player"), info.x, info.y
        end
        local title = nextUp.name or "Next quest"
        if PlaceWaypoint(mapID, x, y, title) then
            return ("arrow \226\134\146 pick up %s (quest %d/%d)")
                :format(title, nextUp.index, s.total)
        end
    end
    return nil, "couldn't locate the next quest giver (try again in the achievement's zone)"
end

-- Re-point the arrow after quest turn-in / progress (auto-advance).
function Chains.RefreshWaypoint()
    if not Chains.lastQuestLine then return end
    local msg = Chains.SetWaypoint(Chains.lastQuestLine)
    if msg then
        print("|cff7fd5ffQuestGlass:|r " .. msg)
    end
end
