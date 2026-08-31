local ADDON, NS = ...

-- Options panel (Interface Options -> AddOns -> QuestGlass).
-- Stored in QuestGlassDB.options (defaults set in Core.lua).

local function Opts()
    return QuestGlassDB.options
end

function NS.ApplyOptions()
    local o = Opts()
    if QuestGlassFrame then QuestGlassFrame:SetScale(o.windowScale) end
    if QuestGlassTracker then QuestGlassTracker:SetScale(o.stripScale) end
end

local panel = CreateFrame("Frame")
panel.name = "QuestGlass"

local function MakeLabel(text, x, y, template)
    local fs = panel:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function MakeCheck(label, y, key)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", 16, y)
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)
    cb:SetScript("OnClick", function(self)
        Opts()[key] = self:GetChecked() and true or false
        NS.ApplyOptions()
        if NS.RefreshTracker then NS.RefreshTracker() end
    end)
    cb.Refresh = function(self) self:SetChecked(Opts()[key]) end
    return cb
end

local function MakeSlider(label, y, key, minV, maxV, step)
    local title = MakeLabel(label, 20, y, "GameFontHighlight")
    local value = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    value:SetPoint("LEFT", title, "RIGHT", 8, 0)

    local s = CreateFrame("Slider", nil, panel)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(220, 16)
    s:SetPoint("TOPLEFT", 20, y - 18)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    s:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = s:GetThumbTexture()
    thumb:SetSize(10, 16)
    thumb:SetVertexColor(0.8, 0.8, 0.8)
    local fmt = step < 1 and "%.2f" or "%d"
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step -- snap to step
        if self.updating then return end
        Opts()[key] = v
        value:SetFormattedText(fmt, v)
        NS.ApplyOptions()
    end)
    s.Refresh = function(self)
        self.updating = true
        self:SetValue(Opts()[key])
        self.updating = false
        value:SetFormattedText(fmt, Opts()[key])
    end
    return s
end

local controls = {}

local title = MakeLabel("QuestGlass", 16, -16)
MakeLabel("Changes apply immediately and are saved per account.", 16, -36, "GameFontDisableSmall")

controls[#controls + 1] = MakeSlider("Window scale", -70, "windowScale", 0.6, 1.6, 0.05)
controls[#controls + 1] = MakeSlider("Tracker strip scale", -120, "stripScale", 0.6, 1.6, 0.05)
controls[#controls + 1] = MakeSlider("Skip the arrow when the target is within (yards, 0 = always show)",
    -170, "arrowMinDistance", 0, 500, 25)
controls[#controls + 1] = MakeCheck("Lock tracker strip (disable dragging)", -220, "stripLocked")
controls[#controls + 1] = MakeCheck("Hide tracker strip in combat", -250, "stripCombatHide")

MakeLabel("Tip: bind a key to toggle QuestGlass under Options \194\187 Keybindings \194\187 AddOns.",
    16, -300, "GameFontDisableSmall")

panel:SetScript("OnShow", function()
    for _, c in ipairs(controls) do c:Refresh() end
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, "QuestGlass")
    category.ID = "QuestGlass"
    Settings.RegisterAddOnCategory(category)
    function NS.OpenOptions() Settings.OpenToCategory("QuestGlass") end
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
    function NS.OpenOptions() InterfaceOptionsFrame_OpenToCategory(panel) end
else
    function NS.OpenOptions()
        print("|cff7fd5ffQuestGlass:|r options panel unavailable in this client build")
    end
end
