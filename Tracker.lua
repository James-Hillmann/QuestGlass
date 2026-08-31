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

-- Storyline status for a pinned achievement. Prefers the storyline the
-- arrow is currently tracking (Chains.lastQuestLine); falls back to the
-- first incomplete mapped criterion. Returns nil, or a table:
--   { ql, text (one-liner), state, tracked (arrow points here) }
local function ChainInfo(achID)
    local qlMap = NS.Chains.EnsureMap(achID)
    local first, tracked
    for i = 1, GetAchievementNumCriteria(achID) do
        local ok, text, ctype, completed, _, _, _, _, assetID =
            pcall(GetAchievementCriteriaInfo, achID, i)
        if ok and not completed and ctype == 27 and assetID and qlMap[assetID] then
            local ql = qlMap[assetID]
            first = first or { ql = ql, text = text }
            if ql == NS.Chains.lastQuestLine then
                tracked = { ql = ql, text = text }
                break
            end
        end
    end
    local pick = tracked or first
    if not pick then return nil end

    local s = NS.Chains.State(pick.ql)
    local line = "\194\187 " .. pick.text
    if s and s.active then
        local obj
        for _, o in ipairs(s.active.objectives or {}) do
            if not o.finished then obj = o.text break end
        end
        line = ("\194\187 %s%s"):format(s.active.name or pick.text,
            obj and (" \226\128\148 " .. obj) or "")
    elseif s and s.upcoming[1] then
        line = ("\194\187 pick up %s"):format(s.upcoming[1].name or pick.text)
    end
    return { ql = pick.ql, text = line, state = s, tracked = tracked ~= nil }
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

        -- gold accent marking the pin the arrow is tracking
        row.accent = row:CreateTexture(nil, "ARTWORK")
        row.accent:SetWidth(3)
        row.accent:SetPoint("TOPLEFT", -6, -2)
        row.accent:SetPoint("BOTTOMLEFT", -6, 2)
        row.accent:SetColorTexture(1, 0.82, 0, 0.9)
        row.accent:Hide()

        -- storyline (per-quest) progress bar — moves much faster than the
        -- achievement bar above it
        row.chainBar = CreateFrame("StatusBar", nil, row)
        row.chainBar:SetPoint("TOPLEFT", 38, -48)
        row.chainBar:SetPoint("TOPRIGHT", -4, -48)
        row.chainBar:SetHeight(9)
        row.chainBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        row.chainBar:SetStatusBarColor(0.25, 0.55, 1)
        local cbBG = row.chainBar:CreateTexture(nil, "BACKGROUND")
        cbBG:SetAllPoints()
        cbBG:SetColorTexture(0.1, 0.1, 0.1, 0.9)
        row.chainBarText = row.chainBar:CreateFontString(nil, "OVERLAY")
        row.chainBarText:SetFont(select(1, GameFontHighlightSmall:GetFont()), 9, "OUTLINE")
        row.chainBarText:SetPoint("CENTER")
        row.chainBar:Hide()

        -- remaining quests in the tracked storyline
        row.quests = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.quests:SetPoint("TOPLEFT", 38, -62)
        row.quests:SetPoint("RIGHT", -4, 0)
        row.quests:SetJustifyH("LEFT")
        row.quests:SetSpacing(2)
        row.quests:Hide()

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
    strip:Show()

    local yOff = 0
    for i = 1, MAX_PINS do
        local row = rows[i]
        local achID = pins[i]
        if not achID then
            row:Hide()
        else
            local _, name, _, completed, _, _, _, _, _, icon = GetAchievementInfo(achID)
            row.achID = achID
            row:Show()
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", PAD, -PAD - yOff)
            row:SetPoint("TOPRIGHT", -PAD, -PAD - yOff)
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText(name or ("Achievement " .. achID))
            local done, total = CriteriaProgress(achID)
            row.bar:SetMinMaxValues(0, total)
            row.bar:SetValue(completed and total or done)
            row.barText:SetFormattedText("%d / %d", completed and total or done, total)

            local rowH = ROW_H
            local info = not completed and ChainInfo(achID) or nil
            row.questLineID = info and info.ql or nil

            if completed then
                row.name:SetTextColor(0.6, 1, 0.6)
                row.chain:SetText("Complete!")
            else
                row.name:SetTextColor(1, 0.82, 0)
                row.chain:SetText(info and info.text
                    or ("%d / %d criteria"):format(done, total))
            end

            local s = info and info.tracked and info.state
            if s then
                -- expanded: the arrow tracks this storyline
                row.accent:Show()
                row.chainBar:SetMinMaxValues(0, s.total)
                row.chainBar:SetValue(s.done)
                row.chainBarText:SetFormattedText("%d / %d quests", s.done, s.total)
                row.chainBar:Show()

                local lines, shown = {}, 0
                if s.active then
                    lines[#lines + 1] = ("|cff33ff66\194\187 %s|r")
                        :format(s.active.name or "(loading\226\128\166)")
                    shown = shown + 1
                end
                for _, u in ipairs(s.upcoming) do
                    if shown >= 4 then
                        local left = (s.active and 1 or 0) + #s.upcoming - shown
                        if left > 0 then
                            lines[#lines + 1] = ("|cff666666   +%d more|r"):format(left)
                        end
                        break
                    end
                    lines[#lines + 1] = ("|cff999999   %s|r")
                        :format(u.name or "(loading\226\128\166)")
                    shown = shown + 1
                end
                row.quests:SetText(table.concat(lines, "\n"))
                row.quests:Show()
                rowH = 64 + math.max(12, row.quests:GetStringHeight()) + 4
            else
                row.accent:Hide()
                row.chainBar:Hide()
                row.quests:Hide()
            end

            row:SetHeight(rowH)
            yOff = yOff + rowH
        end
    end
    strip:SetHeight(yOff + PAD * 2)
end
