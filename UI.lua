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
local selectedQuestLine -- quest line the user clicked in the detail view

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
                row.critData = nil
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
                row.critData = c
                row.icon:Hide()
                row.name:SetPoint("LEFT", 4, 0)
                local prefix = (c.questLineID and not c.completed)
                    and "|cffffd100\194\187|r " or "" -- » (▶ isn't in the font)
                row.name:SetText(prefix .. c.text)
                if c.completed then
                    row.name:SetTextColor(0.6, 1.0, 0.6)
                    row.right:SetText(CHECK)
                else
                    if c.questLineID and c.questLineID == selectedQuestLine then
                        row.name:SetTextColor(1, 0.82, 0) -- tracked storyline
                    else
                        row.name:SetTextColor(0.95, 0.95, 0.95)
                    end
                    if c.state then
                        local pos = c.state.active and c.state.active.index
                            or math.min(c.state.done + 1, c.state.total)
                        row.right:SetFormattedText("quest %d/%d", pos, c.state.total)
                    else
                        row.right:SetText(c.progress or "")
                    end
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
    local qlMap = NS.Chains.EnsureMap(achID)
    local n = GetAchievementNumCriteria(achID)
    for i = 1, n do
        local ok, text, ctype, completed, quantity, reqQuantity, _, _, assetID,
            quantityString = pcall(GetAchievementCriteriaInfo, achID, i)
        if ok and text and text ~= "" then
            local progress
            if not completed and reqQuantity and reqQuantity > 1 then
                progress = (quantityString and quantityString ~= "")
                    and quantityString
                    or (quantity .. "/" .. reqQuantity)
            end
            local c = {
                critIndex = i,
                text = text,
                completed = completed and true or false,
                progress = progress,
            }
            if ctype == 27 and assetID and assetID > 0 then -- quest criterion
                c.questID = assetID
                c.questLineID = qlMap[assetID]
                if c.questLineID and not c.completed then
                    c.state = NS.Chains.State(c.questLineID)
                end
            end
            detailCriteria[#detailCriteria + 1] = c
        end
    end
    -- Incomplete criteria first, original order within each group
    table.sort(detailCriteria, function(a, b)
        if a.completed ~= b.completed then return not a.completed end
        return false
    end)
end

-- Storyline summary for the selected criterion, shown under the progress bar
local function RenderChainInfo(c)
    local s = c and (c.state or NS.Chains.State(c.questLineID))
    if not s then
        detail.chainText:SetText("")
        detail.pane:SetHeight(96)
        return
    end
    local lines = {
        ("|cffffd100Storyline:|r %d/%d quests complete"):format(s.done, s.total),
    }
    if s.active then
        local obj
        for _, o in ipairs(s.active.objectives or {}) do
            if not o.finished then obj = o.text break end
        end
        lines[#lines + 1] = ("|cff33ff66Now:|r %s%s"):format(
            s.active.name or "(loading\226\128\166)", obj and (" \226\128\148 " .. obj) or "")
    elseif s.upcoming[1] then
        lines[#lines + 1] = ("|cff33ff66Next:|r pick up %s"):format(
            s.upcoming[1].name or "(loading\226\128\166)")
    else
        lines[#lines + 1] = "|cff33ff66All quests turned in.|r"
    end
    local upNames = {}
    local first = s.active and 1 or 2
    for i = first, math.min(first + 1, #s.upcoming) do
        upNames[#upNames + 1] = s.upcoming[i].name or "(loading\226\128\166)"
    end
    if #upNames > 0 then
        lines[#lines + 1] = "|cff999999Then:|r " .. table.concat(upNames, ", ")
    end
    detail.chainText:SetText(table.concat(lines, "\n"))
    detail.pane:SetHeight(152)
end

-- Click on a ▶ criterion: track that storyline and point the arrow
local function SelectChain(c)
    selectedQuestLine = c.questLineID
    local text, err = NS.Chains.SetWaypoint(c.questLineID)
    print("|cff7fd5ffQuestGlass:|r " .. (text or ("no arrow: " .. (err or "unknown"))))
    RenderChainInfo(c)
    RefreshList()
end

local function RenderDetail()
    if not detailAchID then return end
    local _, name, points, completed, _, _, _, description, _, icon =
        GetAchievementInfo(detailAchID)
    if not name then return end

    detail.icon:SetTexture(icon)
    detail.pinBtn:SetText(NS.IsPinned(detailAchID) and "Unpin" or "Pin")
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

    -- keep the storyline panel in sync with the (possibly rebuilt) criteria
    local selected
    if selectedQuestLine then
        for _, c in ipairs(detailCriteria) do
            if c.questLineID == selectedQuestLine then selected = c break end
        end
    end
    RenderChainInfo(selected)

    statusText:SetText("")
    RefreshList()
end

local function ShowDetail(achID)
    if achID ~= detailAchID then selectedQuestLine = nil end
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

    -- The pinned tracker strip holds the user's place now, so the big
    -- window can close easily again (see ROADMAP: P3 design note)
    tinsert(UISpecialFrames, "QuestGlassFrame")

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

    detail.pinBtn = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
    detail.pinBtn:SetSize(60, 20)
    detail.pinBtn:SetPoint("TOPRIGHT", 0, 0)
    detail.pinBtn:SetScript("OnClick", function(self)
        if not detailAchID then return end
        NS.TogglePin(detailAchID)
        self:SetText(NS.IsPinned(detailAchID) and "Unpin" or "Pin")
    end)

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
    detail.bar:SetPoint("TOPLEFT", 0, -70)
    detail.bar:SetPoint("TOPRIGHT", 0, -70)
    detail.bar:SetHeight(16)
    detail.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    detail.bar:SetStatusBarColor(0.2, 0.7, 0.2)
    local barBG = detail.bar:CreateTexture(nil, "BACKGROUND")
    barBG:SetAllPoints()
    barBG:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    detail.barText = detail.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail.barText:SetPoint("CENTER")

    -- Storyline summary for the tracked criterion (below the bar)
    detail.chainText = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail.chainText:SetPoint("TOPLEFT", 0, -92)
    detail.chainText:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
    detail.chainText:SetJustifyH("LEFT")
    detail.chainText:SetSpacing(3)

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
            if self.achID then
                ShowDetail(self.achID)
            elseif self.critData and self.critData.questLineID
                and not self.critData.completed then
                SelectChain(self.critData)
            end
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

    -- When detail is open, the list hangs off the header pane's bottom edge,
    -- so a growing pane (storyline panel) pushes it down automatically.
    local function LayoutList()
        listAnchor:ClearAllPoints()
        if currentView == "detail" then
            listAnchor:SetPoint("TOPLEFT", detail.pane, "BOTTOMLEFT", 0, -8)
            listAnchor:SetPoint("TOPRIGHT", detail.pane, "BOTTOMRIGHT", 0, -8)
        else
            listAnchor:SetPoint("TOPLEFT", 18, -88)
            listAnchor:SetPoint("TOPRIGHT", -18, -88)
        end
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

-- Open straight to an achievement's detail view (used by the tracker strip)
function NS.OpenAchievement(achID)
    if not frame then CreateMainFrame() end
    frame:Show()
    ShowDetail(achID)
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
