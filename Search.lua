local ADDON, NS = ...

-- Runtime search index: array of
--   { id, name, lname, points, completed, crit }
-- Names/points/completed are re-read every login (they change across sessions
-- and are one cheap API call each). Criteria text is the expensive part, so it
-- is cached in SavedVariables keyed by client build.
NS.index = {}
NS.indexReady = false

local building = false
local byID = {} -- achievementID -> index entry, for cheap updates

local function BuildStamp()
    local version, build = GetBuildInfo()
    return version .. "-" .. build
end

local function CriteriaText(achID)
    local n = GetAchievementNumCriteria(achID)
    if n == 0 then return "" end
    local parts
    for i = 1, n do
        -- pcall: some criteria indexes error inside Blizzard code
        local ok, criteriaString = pcall(GetAchievementCriteriaInfo, achID, i)
        if ok and criteriaString and criteriaString ~= "" then
            parts = parts or {}
            parts[#parts + 1] = criteriaString:lower()
        end
    end
    return parts and table.concat(parts, "\n") or ""
end

function NS.StartIndexBuild(force)
    if building then return end
    building = true
    NS.indexReady = false
    NS.index = {}
    wipe(byID)

    local db = QuestGlassDB
    local stamp = BuildStamp()
    if force or type(db.cache) ~= "table" or db.cache.build ~= stamp then
        db.cache = { build = stamp, crit = {} }
    end
    local critCache = db.cache.crit

    local total, done = 0, 0
    local co = coroutine.create(function()
        local cats = GetCategoryList()
        for _, cat in ipairs(cats) do
            total = total + (GetCategoryNumAchievements(cat) or 0)
        end
        for _, cat in ipairs(cats) do
            local num = GetCategoryNumAchievements(cat) or 0
            for i = 1, num do
                local ok, id, name, points, completed, _, _, _, _, _, _, _,
                    isGuild, _, _, isStatistic = pcall(GetAchievementInfo, cat, i)
                if ok and id and name and not isGuild and not isStatistic and not byID[id] then
                    local crit = critCache[id]
                    if crit == nil then
                        crit = CriteriaText(id)
                        critCache[id] = crit
                    end
                    local entry = {
                        id = id,
                        name = name,
                        lname = name:lower(),
                        points = points or 0,
                        completed = completed and true or false,
                        crit = crit,
                    }
                    NS.index[#NS.index + 1] = entry
                    byID[id] = entry
                end
                done = done + 1
                if done % 40 == 0 then
                    coroutine.yield(done, total)
                end
            end
        end
    end)

    local runner = CreateFrame("Frame")
    runner:SetScript("OnUpdate", function(self)
        local ok, err = coroutine.resume(co)
        if not ok then
            self:SetScript("OnUpdate", nil)
            building = false
            geterrorhandler()(err)
            return
        end
        if coroutine.status(co) == "dead" then
            self:SetScript("OnUpdate", nil)
            building = false
            NS.indexReady = true
            if NS.OnIndexProgress then NS.OnIndexProgress(total, total) end
            if NS.OnIndexReady then NS.OnIndexReady() end
        else
            if NS.OnIndexProgress then NS.OnIndexProgress(done, total) end
        end
    end)
end

function NS.MarkAchievementEarned(achID)
    local entry = byID[achID]
    if entry then entry.completed = true end
end

-- True if every character of `needle` appears in `hay` in order.
local function Subsequence(hay, needle)
    local pos = 1
    for i = 1, #needle do
        pos = hay:find(needle:sub(i, i), pos, true)
        if not pos then return false end
        pos = pos + 1
    end
    return true
end

local function ScoreEntry(entry, tokens)
    local score = 0
    for _, tok in ipairs(tokens) do
        local pos = entry.lname:find(tok, 1, true)
        if pos then
            if pos == 1 then
                score = score + 100 -- name starts with token
            elseif entry.lname:sub(pos - 1, pos - 1) == " " then
                score = score + 80 -- token starts a word
            else
                score = score + 50 -- substring anywhere in name
            end
        elseif entry.crit ~= "" and entry.crit:find(tok, 1, true) then
            score = score + 30 -- matched a criterion name
        elseif #tok >= 3 and Subsequence(entry.lname, tok) then
            score = score + 8 -- loose fuzzy fallback
        else
            return nil -- every token must match somewhere
        end
    end
    return score
end

-- Returns a sorted array of { entry, score }, incomplete first.
function NS.Search(query)
    local results = {}
    query = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return results end

    local tokens = {}
    for tok in query:gmatch("%S+") do
        tokens[#tokens + 1] = tok
    end

    for _, entry in ipairs(NS.index) do
        local score = ScoreEntry(entry, tokens)
        if score then
            results[#results + 1] = { entry = entry, score = score }
        end
    end

    table.sort(results, function(a, b)
        if a.entry.completed ~= b.entry.completed then
            return not a.entry.completed
        end
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.entry.name < b.entry.name
    end)

    return results
end
