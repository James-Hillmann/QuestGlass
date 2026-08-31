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
    elseif event == "ACHIEVEMENT_EARNED" then
        NS.MarkAchievementEarned(arg1)
        onCriteriaUpdate()
    elseif event == "CRITERIA_UPDATE" then
        onCriteriaUpdate()
    end
end)

SLASH_QUESTGLASS1 = "/qg"
SLASH_QUESTGLASS2 = "/questglass"
SlashCmdList.QUESTGLASS = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "rebuild" then
        print("|cff7fd5ffQuestGlass:|r rebuilding achievement index…")
        NS.StartIndexBuild(true)
    elseif msg == "" then
        NS.ToggleUI()
    else
        NS.OpenWithQuery(msg)
    end
end
