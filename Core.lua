local ADDON, NS = ...

QuestGlassDB = QuestGlassDB or {}

-- Debounce helper: returns a function that fires `fn` at most once per `delay`
-- seconds, no matter how often it is called (CRITERIA_UPDATE spams hard).
function NS.Debounce(delay, fn)
    local pending = false
    return function()
        if pending then return end
        pending = true
        C_Timer.After(delay, function()
            pending = false
            fn()
        end)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

local onCriteriaUpdate = NS.Debounce(0.75, function()
    NS.InvalidateProgress()
    NS.StartProgressScan()
    if NS.RefreshOpenViews then NS.RefreshOpenViews() end
end)

-- Quest line / quest name data arrived: re-render open views
local onQuestData = NS.Debounce(0.5, function()
    if NS.RefreshOpenViews then NS.RefreshOpenViews() end
end)

-- Quest turned in or objectives progressed: advance the arrow
local onQuestAdvance = NS.Debounce(1, function()
    NS.Chains.RefreshWaypoint()
    if NS.RefreshOpenViews then NS.RefreshOpenViews() end
end)

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        QuestGlassDB.cache = QuestGlassDB.cache or {}
        QuestGlassDB.ui = QuestGlassDB.ui or {}
    elseif event == "PLAYER_LOGIN" then
        NS.StartIndexBuild(false)
        events:RegisterEvent("ACHIEVEMENT_EARNED")
        events:RegisterEvent("CRITERIA_UPDATE")
        events:RegisterEvent("QUESTLINE_UPDATE")
        events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
        events:RegisterEvent("QUEST_TURNED_IN")
        events:RegisterEvent("QUEST_WATCH_UPDATE")
        NS.RestoreSession() -- reopen where the user was before /reload
    elseif event == "ACHIEVEMENT_EARNED" then
        NS.MarkAchievementEarned(arg1)
        onCriteriaUpdate()
    elseif event == "CRITERIA_UPDATE" then
        onCriteriaUpdate()
    elseif event == "QUESTLINE_UPDATE" or event == "QUEST_DATA_LOAD_RESULT" then
        onQuestData()
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_WATCH_UPDATE" then
        onQuestAdvance()
    end
end)

SLASH_QUESTGLASS1 = "/qg"
SLASH_QUESTGLASS2 = "/questglass"
SlashCmdList.QUESTGLASS = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "rebuild" then
        print("|cff7fd5ffQuestGlass:|r rebuilding achievement index…")
        NS.StartIndexBuild(true)
    elseif msg == "way" then
        if NS.Chains.lastQuestLine then
            local text, err = NS.Chains.SetWaypoint(NS.Chains.lastQuestLine)
            print("|cff7fd5ffQuestGlass:|r " .. (text or ("no arrow: " .. err)))
        else
            print("|cff7fd5ffQuestGlass:|r nothing tracked yet — open an achievement and click a \194\187 storyline first.")
        end
    elseif msg:match("^automap%s+%d+$") then
        local achID = tonumber(msg:match("%d+"))
        local name = select(2, GetAchievementInfo(achID))
        if not name then
            print("|cff7fd5ffQuestGlass:|r unknown achievement id " .. achID)
            return
        end
        local map, unresolved = NS.Chains.EnsureMap(achID)
        local mapped = 0
        for questID, questLineID in pairs(map) do
            mapped = mapped + 1
            print(("  quest %d \226\134\146 questline %d"):format(questID, questLineID))
        end
        print(("|cff7fd5ffQuestGlass:|r %s: %d quest criteria mapped, %d unresolved%s")
            :format(name, mapped, unresolved,
                unresolved > 0 and " (try again standing in the achievement's zone, or add to Overrides.lua)" or ""))
    elseif msg == "" then
        NS.ToggleUI()
    else
        NS.OpenWithQuery(msg)
    end
end
