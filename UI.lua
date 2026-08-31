local ADDON, NS = ...

local FRAME_W, FRAME_H = 480, 620
local ROW_H = 28
local NUM_ROWS = 18

local frame            -- main window
local searchBox
local statusText
local listRows = {}    -- reusable row buttons (shared by both views)
local scrollOffset = 0

local currentResults = {}   -- from NS.Search
local currentView = "search" -- "search" | "detail"
local detailAchID
local detailCriteria = {}   -- built when a detail view opens

-- Detail widgets
local detail = {}

local RunSearch -- forward declaration (defined under "Search plumbing")

local function AchProgress(achID)
    local n = GetAchievementNumCriteria(achID)
    if n == 0 then return nil end
    local done = 0
    for i = 1, n do
        local ok, _, _, completed = pcall(GetAchievementCriteriaInfo, achID, i)
        if ok and completed then done = done + 1 end
    end
    return done, n
end

------------------------------------------------------------------------
-- Rows (shared virtual list)
------------------------------------------------------------------------

-- ✓ as text isn't in WoW's default font; use the green ready-check atlas
local CHECK = "|A:UI-LFG-ReadyMark:12:12|a"

local function VisibleCount()
    return currentView == "search" and #currentResults or #detailCriteria
end

-- Rows that actually fit in the list area (the detail header shrinks it)
local function MaxVisibleRows()
    local h = detail.listAnchor and detail.listAnchor:GetHeight() or 0
    if h <= 0 then h = FRAME_H - 130 end
    return math.min(NUM_ROWS, math.max(1, math.floor((h - 8) / ROW_H)))
end

local function RefreshList()
    local count = VisibleCount()
    local visible = MaxVisibleRows()
    local maxOffset = math.max(0, count - visible)
    if scrollOffset > maxOffset then scrollOffset = maxOffset end

    for i = 1, NUM_ROWS do
        local row = listRows[i]
        local idx = scrollOffset + i
        if i > visible or idx > count then
            row:Hide()
        else
            row:Show()
            if currentView == "search" then
                local r = currentResults[idx]
                local e = r.entry
                row.achID = e.id
                row.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.icon:Show()
                row.name:SetPoint("LEFT", 34, 0)
                row.name:SetText(e.name)
                if e.completed then
                    row.name:SetTextColor(0.6, 1.0, 0.6)
                    row.right:SetText(CHECK)
                else
                    row.name:SetTextColor(1, 0.9, 0.5)
                    local p = NS.ProgressPct(e.id)
                    if p then
                        -- floor, and never show 100% on an incomplete achievement
                        -- (hidden criteria can make all visible ones read done)
                        local pct = math.min(99, math.floor(p * 100))
                        local color
                        if pct >= 80 then color = "ff33ff66"      -- almost done: green
                        elseif pct >= 50 then color = "ffffd100"  -- halfway: gold
                        elseif pct > 0 then color = "ffdddddd"    -- started: white
                        else color = "ff707070" end               -- untouched: dim
                        row.right:SetFormattedText("|c%s%d%%|r", color, pct)
                    else
                        row.right:SetText("")
                    end
                end
            else
                local c = detailCriteria[idx]
                row.achID = nil
                row.icon:Hide()
                row.name:SetPoint("LEFT", 4, 0)
                row.name:SetText(c.text)
                if c.completed then
                    row.name:SetTextColor(0.6, 1.0, 0.6)
                    row.right:SetText(CHECK)
                else
                    row.name:SetTextColor(0.95, 0.95, 0.95)
                    row.right:SetText(c.progress or "")
                end
            end
        end
    end

    if currentView == "search" then
        if not NS.indexReady then
            -- status handled by OnIndexProgress
        elseif searchBox:GetText() == "" then
            if count == 0 then
                statusText:SetText("Type to search " .. #NS.index .. " achievements")
            elseif count > visible then
                statusText:SetFormattedText(
                    "Closest to completion \194\183 %d\226\128\147%d of %d in progress",
                    scrollOffset + 1, math.min(scrollOffset + visible, count), count)
            else
                statusText:SetFormattedText("Closest to completion \194\183 %d in progress", count)
            end
        elseif count > visible then
            statusText:SetFormattedText("%d\226\128\147%d of %d results \194\183 scroll for more",
                scrollOffset + 1, math.min(scrollOffset + visible, count), count)
        else
            statusText:SetFormattedText("%d result%s", count, count == 1 and "" or "s")
        end
    else
        if count > visible then
            statusText:SetFormattedText("%d\226\128\147%d of %d criteria \194\183 scroll for more",
                scrollOffset + 1, math.min(scrollOffset + visible, count), count)
        else
            statusText:SetText("")
        end
    end
end

local function OnMouseWheel(_, delta)
    local maxOffset = math.max(0, VisibleCount() - MaxVisibleRows())
    scrollOffset = math.min(maxOffset, math.max(0, scrollOffset - delta * 3))
    RefreshList()
end

------------------------------------------------------------------------
-- Detail view
------------------------------------------------------------------------

local function BuildDetailCriteria(achID)
    wipe(detailCriteria)
    local n = GetAchievementNumCriteria(achID)
    for i = 1, n do
        local ok, text, _, completed, quantity, reqQuantity, _, _, _,
            quantityString = pcall(GetAchievementCriteriaInfo, achID, i)
        if ok and text and text ~= "" then
            local progress
            if not completed and reqQuantity and reqQuantity > 1 then
                progress = (quantityString and quantityString ~= "")
                    and quantityString
                    or (quantity .. "/" .. reqQuantity)
            end
            detailCriteria[#detailCriteria + 1] = {
                text = text,
                completed = completed and true or false,
                progress = progress,
            }
        end
    end
    -- Incomplete criteria first, original order within each group
    table.sort(detailCriteria, function(a, b)
        if a.completed ~= b.completed then return not a.completed end
        return false
    end)
end

local function RenderDetail()
    if not detailAchID then return end
    local _, name, points, completed, _, _, _, description, _, icon =
        GetAchievementInfo(detailAchID)
    if not name then return end

    detail.icon:SetTexture(icon)
    detail.name:SetText(name)
    detail.name:SetTextColor(completed and 0.6 or 1, completed and 1 or 0.82, completed and 0.6 or 0)
    detail.desc:SetText(description or "")
    detail.points:SetFormattedText("%d points", points or 0)

    BuildDetailCriteria(detailAchID)
    local done, total = AchProgress(detailAchID)
    if done then
        detail.bar:SetMinMaxValues(0, total)
        detail.bar:SetValue(done)
        if done >= total and not completed then
            -- all visible criteria done but not awarded (hidden requirements)
            detail.barText:SetFormattedText("%d / %d \194\183 not yet awarded", done, total)
        else
            detail.barText:SetFormattedText("%d / %d", done, total)
        end
    else
        detail.bar:SetMinMaxValues(0, 1)
        detail.bar:SetValue(completed and 1 or 0)
        detail.barText:SetText(completed and "Complete" or "Incomplete")
    end

    statusText:SetText("")
    RefreshList()
end

local function ShowDetail(achID)
    currentView = "detail"
    detailAchID = achID
    scrollOffset = 0
    QuestGlassDB.ui.view = "detail"
    QuestGlassDB.ui.detailID = achID
    detail.pane:Show()
    RenderDetail()
end

local function ShowSearch(skipFocus)
    currentView = "search"
    detailAchID = nil
    scrollOffset = 0
    QuestGlassDB.ui.view = "search"
    QuestGlassDB.ui.detailID = nil
    detail.pane:Hide()
    RunSearch()
    RefreshList()
    if not skipFocus then searchBox:SetFocus() end
end

------------------------------------------------------------------------
-- Search plumbing
------------------------------------------------------------------------

function RunSearch()
    if not NS.indexReady then return end
    local query = searchBox:GetText()
    if query:gsub("%s+", "") == "" then
        currentResults = NS.nearlyDone or {}
    else
        currentResults = NS.Search(query)
    end
    scrollOffset = 0
    RefreshList()
end

local queueSearch
local function OnSearchChanged(self)
    QuestGlassDB.ui.query = self:GetText()
    if not queueSearch then
        queueSearch = NS.Debounce(0.15, function()
            if frame and frame:IsShown() and currentView == "search" then
                RunSearch()
            end
        end)
    end
    queueSearch()
end

------------------------------------------------------------------------
-- Frame construction
------------------------------------------------------------------------

local function CreateMainFrame()
    frame = CreateFrame("Frame", "QuestGlassFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 10, right = 10, top = 10, bottom = 10 },
    })
    frame:Hide() -- frames are shown by default; ToggleUI decides visibility
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    -- Remember open/closed across /reload (SavedVariables)
    frame:SetScript("OnShow", function() QuestGlassDB.ui.open = true end)
    frame:SetScript("OnHide", function() QuestGlassDB.ui.open = false end)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        QuestGlassDB.ui.pos = { point, relPoint, x, y }
    end)

    local pos = QuestGlassDB.ui.pos
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("CENTER")
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("QuestGlass")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Search box
    searchBox = CreateFrame("EditBox", "QuestGlassSearchBox", frame, "SearchBoxTemplate")
    searchBox:SetSize(FRAME_W - 60, 24)
    searchBox:SetPoint("TOP", 0, -44)
    searchBox:SetAutoFocus(false)
    searchBox:HookScript("OnTextChanged", OnSearchChanged)
    -- ESC only drops focus; the window stays until the X (or /qg) closes it
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if currentView == "search" and currentResults[1] then
            ShowDetail(currentResults[1].entry.id)
        end
    end)

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetPoint("TOP", searchBox, "BOTTOM", 0, -4)

    -- Detail pane (header area above the shared list)
    local pane = CreateFrame("Frame", nil, frame)
    pane:SetPoint("TOPLEFT", 18, -78)
    pane:SetPoint("TOPRIGHT", -18, -78)
    pane:SetHeight(96)
    pane:Hide()
    detail.pane = pane

    local back = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
    back:SetSize(60, 20)
    back:SetPoint("TOPLEFT", 0, 0)
    back:SetText("< Back")
    back:SetScript("OnClick", function() ShowSearch(false) end)

    detail.icon = pane:CreateTexture(nil, "ARTWORK")
    detail.icon:SetSize(36, 36)
    detail.icon:SetPoint("TOPLEFT", 0, -26)

    detail.name = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detail.name:SetPoint("TOPLEFT", detail.icon, "TOPRIGHT", 8, -1)
    detail.name:SetPoint("RIGHT", pane, "RIGHT", -60, 0)
    detail.name:SetJustifyH("LEFT")

    detail.points = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detail.points:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, -27)

    detail.desc = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail.desc:SetPoint("TOPLEFT", detail.icon, "TOPRIGHT", 8, -18)
    detail.desc:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
    detail.desc:SetJustifyH("LEFT")
    detail.desc:SetHeight(28)

    detail.bar = CreateFrame("StatusBar", nil, pane)
    detail.bar:SetPoint("BOTTOMLEFT", 0, 0)
    detail.bar:SetPoint("BOTTOMRIGHT", 0, 0)
    detail.bar:SetHeight(16)
    detail.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    detail.bar:SetStatusBarColor(0.2, 0.7, 0.2)
    local barBG = detail.bar:CreateTexture(nil, "BACKGROUND")
    barBG:SetAllPoints()
    barBG:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    detail.barText = detail.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail.barText:SetPoint("CENTER")

    -- Shared list rows
    local listTop = -110 -- overridden per view via anchor frame
    local listAnchor = CreateFrame("Frame", nil, frame)
    listAnchor:SetPoint("TOPLEFT", 18, listTop)
    listAnchor:SetPoint("TOPRIGHT", -18, listTop)
    listAnchor:SetPoint("BOTTOM", 0, 16)
    listAnchor:EnableMouseWheel(true)
    listAnchor:SetScript("OnMouseWheel", OnMouseWheel)
    listAnchor:SetClipsChildren(true)
    detail.listAnchor = listAnchor

    for i = 1, NUM_ROWS do
        local row = CreateFrame("Button", nil, listAnchor)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H - 4)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H - 4)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", OnMouseWheel)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the default icon border

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", 34, 0)
        row.name:SetPoint("RIGHT", -48, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.right:SetPoint("RIGHT", -4, 0)

        row:SetScript("OnClick", function(self)
            if self.achID then ShowDetail(self.achID) end
        end)
        row:SetScript("OnEnter", function(self)
            if self.achID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetAchievementByID(self.achID)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        listRows[i] = row
    end

    -- When detail is open, push the list down below the header pane
    local function LayoutList()
        local top = (currentView == "detail") and -186 or -88
        listAnchor:ClearAllPoints()
        listAnchor:SetPoint("TOPLEFT", 18, top)
        listAnchor:SetPoint("TOPRIGHT", -18, top)
        listAnchor:SetPoint("BOTTOM", 0, 16)
    end
    hooksecurefunc(detail.pane, "Show", LayoutList)
    hooksecurefunc(detail.pane, "Hide", LayoutList)
    LayoutList()
end

------------------------------------------------------------------------
-- Public entry points (used by Core.lua / Search.lua)
------------------------------------------------------------------------

function NS.ToggleUI()
    if not frame then CreateMainFrame() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        ShowSearch()
    end
end

function NS.OpenWithQuery(query)
    if not frame then CreateMainFrame() end
    frame:Show()
    currentView = "search"
    detail.pane:Hide()
    searchBox:SetText(query)
    RunSearch()
end

-- Reopen the window exactly as it was before a /reload or logout
function NS.RestoreSession()
    local ui = QuestGlassDB.ui
    if not ui.open then return end
    if not frame then CreateMainFrame() end
    frame:Show()
    if ui.query and ui.query ~= "" then
        searchBox:SetText(ui.query)
    end
    if ui.view == "detail" and ui.detailID then
        ShowDetail(ui.detailID)
    else
        ShowSearch(true) -- don't steal keyboard focus on login
    end
end

function NS.OnNearlyDoneReady()
    if frame and frame:IsShown() and currentView == "search"
        and searchBox:GetText() == "" then
        RunSearch()
    end
end

function NS.OnIndexProgress(done, total)
    if frame and frame:IsShown() and statusText and total and total > 0 then
        statusText:SetFormattedText("Indexing achievements\226\128\166 %d%%",
            math.floor(done / total * 100))
    end
end

function NS.OnIndexReady()
    if frame and frame:IsShown() and currentView == "search" then
        RunSearch()
        RefreshList()
    end
end

function NS.RefreshOpenViews()
    if not frame or not frame:IsShown() then return end
    if currentView == "detail" then
        RenderDetail()
    else
        RefreshList()
    end
end
