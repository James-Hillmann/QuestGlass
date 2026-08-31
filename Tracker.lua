local ADDON, NS = ...

-- P3: compact always-visible strip for 1-3 pinned achievements:
-- name, progress bar, live storyline line. Left-click a row opens the
-- detail view; right-click re-points the arrow for that storyline.

local MAX_PINS = 3
local ROW_H = 52
local PAD = 8
local STRIP_W = 300

local strip
local rows = {}

local function Pins()
    QuestGlassDB.pins = QuestGlassDB.pins or {}
    return QuestGlassDB.pins
end

function NS.IsPinned(achID)
    for _, id in ipairs(Pins()) do
        if id == achID then return true end
    end
    return false
end

-- Returns true (pinned), false (unpinned), nil (refused: full)
function NS.TogglePin(achID)
    local pins = Pins()
    for i, id in ipairs(pins) do
        if id == achID then
            table.remove(pins, i)
            NS.RefreshTracker()
            return false
        end
    end
    if #pins >= MAX_PINS then
        print(("|cff7fd5ffQuestGlass:|r max %d pins \226\128\148 unpin one first."):format(MAX_PINS))
        return nil
    end
    pins[#pins + 1] = achID
    NS.RefreshTracker()
    return true
end

function NS.UnpinIfEarned(achID)
    local pins = Pins()
    for i, id in ipairs(pins) do
        if id == achID then
            local name = select(2, GetAchievementInfo(achID))
            print(("|cff7fd5ffQuestGlass:|r %s completed \226\128\148 unpinned. GG!"):format(name or achID))
            table.remove(pins, i)
            NS.RefreshTracker()
            return
        end
    end
end

local function CriteriaProgress(achID)
    local n = GetAchievementNumCriteria(achID)
    if n == 0 then return 0, 1 end
    local done = 0
    for i = 1, n do
        local ok, _, _, completed = pcall(GetAchievementCriteriaInfo, achID, i)
        if ok and completed then done = done + 1 end
    end
    return done, n
end

-- One-line storyline status: the first incomplete mapped criterion's chain.
-- Returns text, questLineID (for right-click arrow).
local function ChainLine(achID)
    local qlMap = NS.Chains.EnsureMap(achID)
    for i = 1, GetAchievementNumCriteria(achID) do
        local ok, text, ctype, completed, _, _, _, _, assetID =
            pcall(GetAchievementCriteriaInfo, achID, i)
        if ok and not completed and ctype == 27 and assetID and qlMap[assetID] then
            local ql = qlMap[assetID]
            local s = NS.Chains.State(ql)
            if s and s.active then
                local obj
                for _, o in ipairs(s.active.objectives or {}) do
                    if not o.finished then obj = o.text break end
                end
                return ("\194\187 %s%s"):format(s.active.name or text,
                    obj and (" \226\128\148 " .. obj) or ""), ql
            elseif s and s.upcoming[1] then
                return ("\194\187 pick up %s"):format(s.upcoming[1].name or text), ql
            end
            return "\194\187 " .. text, ql
        end
    end
    return nil, nil
end

local function CreateStrip()
    strip = CreateFrame("Frame", "QuestGlassTracker", UIParent, "BackdropTemplate")
    strip:SetSize(STRIP_W, ROW_H)
    strip:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    strip:SetBackdropColor(0.04, 0.04, 0.07, 0.88)
    strip:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
    strip:SetFrameStrata("MEDIUM")
    strip:SetMovable(true)
    strip:EnableMouse(true)
    strip:SetClampedToScreen(true)
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", strip.StartMoving)
    strip:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        QuestGlassDB.ui.stripPos = { point, relPoint, x, y }
    end)

    local pos = QuestGlassDB.ui.stripPos
    if pos then
        strip:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        strip:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
    end

    for i = 1, MAX_PINS do
        local row = CreateFrame("Button", nil, strip)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", -PAD, -PAD - (i - 1) * ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        -- rows cover the strip, so forward drags to it
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function() strip:StartMoving() end)
        row:SetScript("OnDragStop", function()
            strip:StopMovingOrSizing()
            local point, _, relPoint, x, y = strip:GetPoint()
            QuestGlassDB.ui.stripPos = { point, relPoint, x, y }
        end)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(30, 30)
        row.icon:SetPoint("TOPLEFT", 0, -6)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local iconBorder = row:CreateTexture(nil, "BORDER")
        iconBorder:SetPoint("TOPLEFT", row.icon, -1, 1)
        iconBorder:SetPoint("BOTTOMRIGHT", row.icon, 1, -1)
        iconBorder:SetColorTexture(0, 0, 0, 0.8)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("TOPLEFT", 38, -4)
        row.name:SetPoint("RIGHT", -18, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.bar = CreateFrame("StatusBar", nil, row)
        row.bar:SetPoint("TOPLEFT", 38, -19)
        row.bar:SetPoint("TOPRIGHT", -4, -19)
        row.bar:SetHeight(9)
        row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        row.bar:SetStatusBarColor(0.15, 0.75, 0.25)
        local barBG = row.bar:CreateTexture(nil, "BACKGROUND")
        barBG:SetAllPoints()
        barBG:SetColorTexture(0.1, 0.1, 0.1, 0.9)
        row.barText = row.bar:CreateFontString(nil, "OVERLAY")
        row.barText:SetFont(select(1, GameFontHighlightSmall:GetFont()), 9, "OUTLINE")
        row.barText:SetPoint("CENTER")

        row.chain = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.chain:SetPoint("TOPLEFT", 38, -33)
        row.chain:SetPoint("RIGHT", -4, 0)
        row.chain:SetJustifyH("LEFT")
        row.chain:SetWordWrap(false)
        row.chain:SetTextColor(0.75, 0.75, 0.75)

        row.unpin = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        row.unpin:SetSize(18, 18)
        row.unpin:SetPoint("TOPRIGHT", 2, -1)
        row.unpin:SetAlpha(0.55)
        row.unpin:HookScript("OnEnter", function(self) self:SetAlpha(1) end)
        row.unpin:HookScript("OnLeave", function(self) self:SetAlpha(0.55) end)
        row.unpin:SetScript("OnClick", function()
            if row.achID then NS.TogglePin(row.achID) end
        end)

        row:SetScript("OnClick", function(self, button)
            if not self.achID then return end
            if button == "RightButton" then
                if self.questLineID then
                    local text, err = NS.Chains.SetWaypoint(self.questLineID)
                    print("|cff7fd5ffQuestGlass:|r " .. (text or ("no arrow: " .. (err or "?"))))
                end
            else
                NS.OpenAchievement(self.achID)
            end
        end)
        row:SetScript("OnEnter", function(self)
            if self.achID then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetAchievementByID(self.achID)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click: open \194\183 Right-click: arrow \194\183 Drag: move", 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        rows[i] = row
    end
end

function NS.RefreshTracker()
    local pins = Pins()
    if #pins == 0 then
        if strip then strip:Hide() end
        return
    end
    if not strip then CreateStrip() end
    strip:SetHeight(#pins * ROW_H + PAD * 2)
    strip:Show()

    for i = 1, MAX_PINS do
        local row = rows[i]
        local achID = pins[i]
        if not achID then
            row:Hide()
        else
            local _, name, _, completed, _, _, _, _, _, icon = GetAchievementInfo(achID)
            row.achID = achID
            row:Show()
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText(name or ("Achievement " .. achID))
            local done, total = CriteriaProgress(achID)
            row.bar:SetMinMaxValues(0, total)
            row.bar:SetValue(completed and total or done)
            row.barText:SetFormattedText("%d / %d", completed and total or done, total)
            if completed then
                row.name:SetTextColor(0.6, 1, 0.6)
                row.chain:SetText("Complete!")
                row.questLineID = nil
            else
                row.name:SetTextColor(1, 0.82, 0)
                local line, ql = ChainLine(achID)
                row.chain:SetText(line or ("%d / %d criteria"):format(done, total))
                row.questLineID = ql
            end
        end
    end
end
