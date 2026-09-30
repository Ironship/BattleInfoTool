-- BattleInfoTool module DoTInfo: options window. Based on the standalone DoT addon's options
-- at e4faef4 by Joe Greive (MIT); it lives only here now and is edited directly.
-- DoTInfo options window (/dotinfo).
--
-- Left: a live preview. The addon's real marker and kill icon are attached to a mock target frame here (see
-- ns.setDisplayHost in Core.lua) and fed plain numbers from the preview sliders, so the preview runs the
-- same drawing code as combat. Right: tabbed settings. Top: presets.
--
-- Controls are built from basic widgets (CheckButton, Slider, Button) rather than Blizzard templates, so they
-- don't depend on templates behaving the same in Forever. Settings are written straight to ns.db.

local ADDON_NAME, BIT = ...
-- BattleInfoTool's own namespace for the module, shared by its four files.
local ns = BIT.Module("DoTInfo")

local WHITE = "Interface\\Buttons\\WHITE8X8"
local WINDOW_WIDTH, WINDOW_HEIGHT = 760, 548 -- tall enough for the longest tab (Nameplates, 15 rows)
local HEADER_HEIGHT = 52 -- title bar: title, presets, close button
local PREVIEW_WIDTH = 290
local ROW_HEIGHT = 26
local SETTINGS_LAYOUT = { label = 170, control = 200 }
local PREVIEW_LAYOUT = { label = 92, control = 140 }
local DISABLED_ALPHA = 0.35
local SIMULATION_STEP = 0.5 -- seconds

-- Presets only set appearance; accuracy and troubleshooting settings are left alone.
local PRESETS = {
    { id = "minimal", label = "Minimal", values = {
        showSkull = true, skullIcon = "cross", skullSize = 40, skullPulse = false,
        showMarkers = true, fillTexture = "flat", fillColor = "purple", fillOpacity = 35, dotColors = "single",
        outlineStyle = "solid", outlineThickness = 1, outlineColor = "purple", outlineOpacity = 100,
        smoothMotion = true, flashOnApply = false, pulseOutline = false,
        showSpark = false, showGlow = false, showShine = false, scrollStripes = false, showLabel = false,
    } },
    { id = "classic", label = "Classic", values = {
        showSkull = true, skullIcon = "skull", skullSize = 48, skullPulse = true,
        showMarkers = true, fillTexture = "smooth", fillColor = "red", fillOpacity = 60, dotColors = "single",
        outlineStyle = "dashed", dashLength = 4, outlineThickness = 2, outlineColor = "gold", outlineOpacity = 100,
        smoothMotion = true, flashOnApply = true, pulseOutline = false,
        showSpark = true, showGlow = false, showShine = false, scrollStripes = false, showLabel = false,
    } },
    { id = "juicy", label = "Juicy", values = {
        showSkull = true, skullIcon = "shades", skullSize = 64, skullPulse = true,
        showMarkers = true, fillTexture = "stripes", fillColor = "red", fillOpacity = 100, dotColors = "each",
        segmentDividers = true, outlineStyle = "dashed", dashLength = 4, outlineThickness = 1, outlineColor = "red",
        outlineOpacity = 85, smoothMotion = true, flashOnApply = true, pulseOutline = true,
        showSpark = true, showGlow = true, glowSize = 7, showShine = true, shineInterval = 3, scrollStripes = true,
        showLabel = false,
    } },
    { id = "debug", label = "Debug", values = {
        showSkull = true, skullIcon = "cross", skullPulse = false,
        showMarkers = true, fillTexture = "flat", fillOpacity = 60, dotColors = "school", segmentDividers = true,
        outlineStyle = "solid", outlineThickness = 1, outlineColor = "white", outlineOpacity = 100,
        smoothMotion = false, flashOnApply = true, pulseOutline = false,
        showSpark = false, showGlow = false, showShine = false, scrollStripes = false,
        showLabel = true, labelPosition = "left", labelSize = 10, labelColor = "white",
    } },
}

local window
local controls = {} -- every settings/preview row, refreshed after each change
local tabs, activeTab = {}, nil
local menu -- shared dropdown list
local simulation

-- Preview numbers, in % of the mock target's max health.
local preview = {
    health = 60,
    dots = {
        { name = "Corruption", school = 32, damage = 27, tick = 4 },
        { name = "Immolate", school = 4, damage = 18, tick = 5 },
    },
}

local function db() return ns.db end

local function findEntry(list, id)
    for _, entry in ipairs(list) do
        if entry.id == id then return entry end
    end
end

local function setBackdrop(frame, shade, alpha)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(shade, shade, shade, alpha or 1)
    frame:SetBackdropBorderColor(0.28, 0.28, 0.3, 1)
end

---------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------

local function previewTotal()
    local total = 0
    for _, dot in ipairs(preview.dots) do total = total + dot.damage end
    return total
end

-- Splits a total over the two sample DoTs (60/40).
local function setPreviewDamage(total)
    preview.dots[1].damage = total * 0.6
    preview.dots[2].damage = total * 0.4
end

local function refreshControls()
    for _, control in ipairs(controls) do control:Refresh() end
end

local function inCombat()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

-- The preview only takes over the display out of combat: in combat the real target comes first, even with the
-- window open (settings changes still apply to it live).
local function syncDisplayHost()
    -- Visible, not just shown: when the window is built into another addon's settings (BattleInfoTool), its
    -- own frame stays "shown" while the settings around it are closed, and the end of a fight then put the
    -- marker back on the preview's mock target frame, drawn where the closed window had been.
    if not window or not window:IsVisible() then return end
    local paused = inCombat() and true or false
    window.combatNote:SetShown(paused)
    window.mock:SetAlpha(paused and 0.3 or 1)
    window.mockPlate:SetAlpha(paused and 0.3 or 1)
    window.simulateButton:SetEnabled(not paused)
    window.flashButton:SetEnabled(not paused)
    if paused ~= window.previewPaused then
        window.previewPaused = paused
        if paused and simulation then
            simulation:Cancel()
            simulation = nil
            window.simulateButton:SetText("Simulate fight")
        end
        ns.setDisplayHost((not paused) and window.host or nil)
        ns.setPlatePreview((not paused) and window.plateHost or nil, preview)
    end
end

-- The verdict badge under the preview scene: one look per outcome.
local VERDICT_STYLES = {
    none = { icon = "Interface\\Common\\Indicator-Gray",
        bg = { 0.11, 0.11, 0.12 }, edge = { 0.32, 0.32, 0.34 }, text = { 0.72, 0.72, 0.72 } },
    survives = { icon = "Interface\\Common\\Indicator-Yellow",
        bg = { 0.19, 0.14, 0.04 }, edge = { 0.85, 0.62, 0.12 }, text = { 1, 0.82, 0.35 } },
    lethal = { icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", -- when the chosen kill icon has no path
        bg = { 0.05, 0.19, 0.07 }, edge = { 0.30, 0.85, 0.35 }, text = { 0.55, 1, 0.55 } },
    dead = { icon = "Interface\\RaidFrame\\ReadyCheck-Ready",
        bg = { 0.10, 0.13, 0.10 }, edge = { 0.35, 0.50, 0.35 }, text = { 0.70, 0.85, 0.70 } },
}
local PREVIEW_MAX_HEALTH = 142 -- the mock murloc's health, for the number on its bar

-- The kill icon picked in the settings, so the badge shows the same icon the portrait gets.
local function chosenKillIcon()
    local entry = ns.findById and ns.lists and ns.findById(ns.lists.icons, db().skullIcon)
    return entry and entry.path or VERDICT_STYLES.lethal.icon
end

local function setVerdict(kind, text, detail)
    local style = VERDICT_STYLES[kind]
    local badge = window.statusBadge
    badge:SetBackdropColor(style.bg[1], style.bg[2], style.bg[3], 0.95)
    badge:SetBackdropBorderColor(style.edge[1], style.edge[2], style.edge[3], 0.9)
    badge.accent:SetColorTexture(style.edge[1], style.edge[2], style.edge[3], 1)
    badge.icon:SetTexture(kind == "lethal" and chosenKillIcon() or style.icon)
    window.status:SetText(text)
    window.status:SetTextColor(style.text[1], style.text[2], style.text[3])
    window.statusDetail:SetText(detail or "")
end

local function updatePreview()
    if not window then return end
    window.healthBar:SetValue(preview.health)
    window.plateHealthBar:SetValue(preview.health)
    local total, health = previewTotal(), preview.health
    local function pct(value) return math.floor(value + 0.5) .. "%" end
    -- The numbers the game's own target frame shows on its bar: percent left, health right.
    window.healthPercent:SetText(pct(health))
    window.healthValue:SetText(tostring(math.floor(PREVIEW_MAX_HEALTH * health / 100 + 0.5)))
    if health <= 0 then
        setVerdict("dead", "Target died", "")
    elseif total <= 0 then
        setVerdict("none", "No DoTs on the target", "")
    elseif total >= health then
        setVerdict("lethal", "DoTs kill it", pct(total) .. " vs " .. pct(health))
    else
        setVerdict("survives", "Survives by " .. pct(health - total), pct(total) .. " vs " .. pct(health))
    end
    ns.refresh()
end

local function stopSimulation()
    if simulation then
        simulation:Cancel()
        simulation = nil
    end
    if window then window.simulateButton:SetText("Simulate fight") end
end

-- A scripted fight: a DoT lands, ticks, a second DoT lands and makes it lethal, ticks until the target dies.
local function startSimulation()
    stopSimulation()
    preview.health = 80
    setPreviewDamage(0)
    local step = 0
    simulation = C_Timer.NewTicker(SIMULATION_STEP, function()
        step = step + 1
        if step == 1 then
            preview.dots[1].damage = 32
            ns.playFlash()
        elseif step == 5 then
            preview.dots[2].damage = 50
            ns.playFlash()
        else
            local dealt = 0
            for _, dot in ipairs(preview.dots) do
                local tick = math.min(dot.damage, dot.tick)
                dot.damage = dot.damage - tick
                dealt = dealt + tick
            end
            preview.health = math.max(0, preview.health - dealt)
        end
        updatePreview()
        refreshControls()
        if preview.health <= 0 or (step > 5 and previewTotal() <= 0) then stopSimulation() end
    end)
    window.simulateButton:SetText("Stop")
    updatePreview()
    refreshControls()
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

local function changed()
    ns.refresh()
    refreshControls()
end

local function makeRow(parent, labelText, opts)
    local layout = opts.layout or SETTINGS_LAYOUT
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(layout.label + layout.control + 50, ROW_HEIGHT)
    row.layout = layout
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", 6, 0)
    row.label:SetWidth(layout.label - 8)
    row.label:SetJustifyH("LEFT")
    row.label:SetText(labelText)
    row.enabledIf = opts.enabledIf
    if opts.tooltip then
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(opts.tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    function row:ApplyEnabled(widget)
        local enabled = not self.enabledIf or self.enabledIf(db())
        self:SetAlpha(enabled and 1 or DISABLED_ALPHA)
        widget:EnableMouse(enabled)
        if widget.EnableMouseWheel then widget:EnableMouseWheel(enabled) end
    end
    table.insert(controls, row)
    return row
end

local function checkbox(parent, key, labelText, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local box = CreateFrame("CheckButton", nil, row)
    box:SetSize(24, 24)
    box:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
    box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box:SetScript("OnClick", function(self)
        db()[key] = self:GetChecked() and true or false
        changed()
    end)
    function row:Refresh()
        box:SetChecked(db()[key] and true or false)
        self:ApplyEnabled(box)
    end
    return row
end

-- get/set work on any value (settings or preview numbers).
local function sliderRow(parent, labelText, min, max, step, get, set, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(row.layout.control - 44, 18)
    slider:SetPoint("LEFT", row, "LEFT", row.layout.label + 2, 0)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.3, 0.3, 0.32, 1)
    track:SetHeight(4)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:GetThumbTexture():SetSize(18, 24)
    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    local suffix = opts.suffix or ""
    local updating = false
    slider:SetScript("OnValueChanged", function(_, value)
        if updating then return end
        value = math.floor(value / step + 0.5) * step
        valueText:SetText(value .. suffix)
        set(value)
    end)
    slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)
    function row:Refresh()
        updating = true
        local value = get()
        slider:SetValue(value)
        valueText:SetText(math.floor(value / step + 0.5) * step .. suffix)
        updating = false
        self:ApplyEnabled(slider)
    end
    return row
end

local function slider(parent, key, labelText, min, max, step, opts)
    return sliderRow(parent, labelText, min, max, step,
        function() return db()[key] end,
        function(value)
            db()[key] = value
            changed()
        end, opts)
end

local function closeMenu()
    if menu then menu:Hide() end
end

-- Shared dropdown list under `owner`; entries may carry an rgb swatch.
local function openMenu(owner, list, current, pick)
    if not menu then
        menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:EnableMouse(true)
        setBackdrop(menu, 0.08, 0.98)
        menu.buttons = {}
        -- Close on a click anywhere else (event may not exist on every client; clicking the owner toggles too).
        pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
        menu:SetScript("OnEvent", function(self)
            if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
        end)
    end
    if menu:IsShown() and menu.owner == owner then return menu:Hide() end
    menu.owner = owner
    for i, entry in ipairs(list) do
        local button = menu.buttons[i]
        if not button then
            button = CreateFrame("Button", nil, menu)
            button:SetHeight(20)
            local highlight = button:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.1)
            button.swatch = button:CreateTexture(nil, "ARTWORK")
            button.swatch:SetSize(12, 12)
            button.swatch:SetPoint("LEFT", 8, 0)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.text:SetJustifyH("LEFT")
            menu.buttons[i] = button
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -4 - (i - 1) * 20)
        button:SetPoint("RIGHT", menu, "RIGHT", -1, 0)
        button.swatch:SetShown(entry.rgb ~= nil)
        if entry.rgb then button.swatch:SetColorTexture(entry.rgb[1], entry.rgb[2], entry.rgb[3], 1) end
        button.text:ClearAllPoints()
        button.text:SetPoint("LEFT", entry.rgb and 26 or 8, 0)
        button.text:SetText(entry.id == current and ("|cffffd100" .. entry.label .. "|r") or entry.label)
        button:SetScript("OnClick", function()
            menu:Hide()
            pick(entry.id)
        end)
        button:Show()
    end
    for i = #list + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu:SetSize(owner:GetWidth(), #list * 20 + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

local function choice(parent, key, labelText, list, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local button = CreateFrame("Button", nil, row, "BackdropTemplate")
    button:SetSize(row.layout.control, 22)
    button:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
    setBackdrop(button, 0.13)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
    local swatch = button:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(12, 12)
    swatch:SetPoint("LEFT", 8, 0)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetPoint("RIGHT", -20, 0)
    local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetText("v")
    button:SetScript("OnClick", function(self)
        openMenu(self, list, db()[key], function(id)
            db()[key] = id
            changed()
        end)
    end)
    function row:Refresh()
        local entry = findEntry(list, db()[key])
        text:SetText(entry and entry.label or tostring(db()[key]))
        swatch:SetShown(entry ~= nil and entry.rgb ~= nil)
        if entry and entry.rgb then swatch:SetColorTexture(entry.rgb[1], entry.rgb[2], entry.rgb[3], 1) end
        text:ClearAllPoints()
        text:SetPoint("LEFT", (entry and entry.rgb) and 26 or 8, 0)
        text:SetPoint("RIGHT", -20, 0)
        self:ApplyEnabled(button)
    end
    return row
end

local function pushButton(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function actionRow(parent, labelText, buttonText, onClick, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local button = pushButton(row, buttonText, 90, onClick)
    button:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
    function row:Refresh() self:ApplyEnabled(button) end
    return row
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function selectTab(tab)
    closeMenu()
    activeTab = tab
    for _, other in ipairs(tabs) do
        local selected = other == tab
        other.content:SetShown(selected)
        other.button.text:SetTextColor(selected and 1 or 0.6, selected and 0.82 or 0.6, selected and 0 or 0.6)
        other.button.underline:SetShown(selected)
        if other.footer then other.footer:SetShown(selected) end
    end
end

-- A tab whose methods add rows top to bottom and remember the setting keys, for "Reset this tab".
local function addTab(name)
    local area = window.settingsArea
    local tab = { keys = {}, y = 0 }
    tab.content = CreateFrame("Frame", nil, area)
    tab.content:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -40)
    tab.content:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -8, 40)
    tab.content:Hide()

    local button = CreateFrame("Button", nil, area)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.text:SetText(name)
    button:SetSize(button.text:GetStringWidth() + 20, 26)
    button.text:SetPoint("CENTER")
    button.underline = button:CreateTexture(nil, "ARTWORK")
    button.underline:SetColorTexture(1, 0.82, 0, 1)
    button.underline:SetHeight(2)
    button.underline:SetPoint("BOTTOMLEFT", 6, 0)
    button.underline:SetPoint("BOTTOMRIGHT", -6, 0)
    local previous = tabs[#tabs]
    if previous then
        button:SetPoint("LEFT", previous.button, "RIGHT", 2, 0)
    else
        button:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -8)
    end
    button:SetScript("OnClick", function() selectTab(tab) end)
    tab.button = button

    local function place(row, key)
        row:SetPoint("TOPLEFT", tab.content, "TOPLEFT", 0, -tab.y)
        tab.y = tab.y + ROW_HEIGHT
        if key then table.insert(tab.keys, key) end
        return row
    end
    function tab:checkbox(key, ...) return place(checkbox(self.content, key, ...), key) end
    function tab:slider(key, ...) return place(slider(self.content, key, ...), key) end
    function tab:choice(key, ...) return place(choice(self.content, key, ...), key) end
    function tab:action(...) return place(actionRow(self.content, ...)) end
    function tab:gap() self.y = self.y + 8 end

    table.insert(tabs, tab)
    return tab
end

local function resetTab(tab)
    for _, key in ipairs(tab.keys) do db()[key] = ns.DEFAULTS[key] end
    changed()
end

local function applyPreset(preset)
    for key, value in pairs(preset.values) do db()[key] = value end
    changed()
    ns.print(preset.label .. " preset applied.")
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function isDashed(settings) return settings.outlineStyle == "dashed" end
local function hasOutline(settings) return settings.outlineStyle ~= "none" end
local function singleColor(settings) return settings.dotColors == "single" end
local function perDot(settings) return settings.dotColors ~= "single" end
local function showsLabel(settings) return settings.showLabel end

local function buildTabs()
    local lists = ns.lists

    local icon = addTab("Kill icon")
    icon:checkbox("showSkull", "Show icon on portrait",
        { tooltip = "Shows an icon over the target's portrait when your DoTs on it will kill it." })
    icon:choice("skullIcon", "Icon", lists.icons)
    icon:slider("skullSize", "Size", 20, 64, 2)
    icon:checkbox("skullPulse", "Pulse", { tooltip = "Gently pulses the icon while it's showing." })
    icon:slider("skullOffsetX", "Horizontal offset", -60, 60, 1,
        { tooltip = "Pixels right (+) or left (-) of the portrait's center." })
    icon:slider("skullOffsetY", "Vertical offset", -60, 60, 1,
        { tooltip = "Pixels up (+) or down (-) from the portrait's center." })

    local marker = addTab("Marker")
    marker:checkbox("showMarkers", "Show damage marker", { tooltip = "Marks the damage your DoTs still have to "
        .. "deal on the target's health bar. If the health ends inside it, the target dies." })
    marker:choice("dotColors", "DoT colors", lists.dotColors, { tooltip = "One color, or one segment per DoT "
        .. "colored by spell school or with a different color each." })
    marker:choice("fillTexture", "Fill style", lists.fills)
    marker:choice("fillColor", "Fill color", lists.colors, { enabledIf = singleColor,
        tooltip = "Used when DoT colors is set to one color." })
    marker:slider("fillOpacity", "Fill opacity", 0, 100, 5, { suffix = "%" })
    marker:checkbox("segmentDividers", "Dividers between DoTs", { enabledIf = perDot })
    marker:gap()
    marker:choice("outlineStyle", "Outline", lists.outlines)
    marker:choice("dashLength", "Dash length", lists.dashLengths, { enabledIf = isDashed })
    marker:slider("outlineThickness", "Outline thickness", 1, 8, 1, { enabledIf = hasOutline })
    marker:choice("outlineColor", "Outline color", lists.colors, { enabledIf = hasOutline })
    marker:slider("outlineOpacity", "Outline opacity", 10, 100, 5, { suffix = "%", enabledIf = hasOutline })

    local effects = addTab("Effects")
    effects:checkbox("smoothMotion", "Smooth motion",
        { tooltip = "The marker grows in when it appears and glides to new values instead of jumping." })
    effects:checkbox("flashOnApply", "Flash on new DoT")
    effects:checkbox("showSpark", "Spark", { tooltip = "A bright flare on the marker's edge when a DoT lands." })
    effects:checkbox("pulseOutline", "Pulse outline", { enabledIf = hasOutline })
    effects:gap()
    effects:checkbox("showGlow", "Glow", { enabledIf = hasOutline, tooltip = "Soft halo in the outline color." })
    effects:slider("glowSize", "Glow size", 2, 16, 1,
        { enabledIf = function(s) return hasOutline(s) and s.showGlow end })
    effects:checkbox("showShine", "Shine sweep")
    effects:slider("shineInterval", "Shine every", 2, 10, 1,
        { suffix = "s", enabledIf = function(s) return s.showShine end })
    effects:checkbox("scrollStripes", "Scroll stripes", { tooltip = "Animates the diagonal stripes fill.",
        enabledIf = function(s) return s.fillTexture == "stripes" and singleColor(s) end })

    local text = addTab("Text")
    text:checkbox("showLabel", "Show damage text",
        { tooltip = "Remaining DoT damage next to the health bar (a per-DoT breakdown with DoT colors)." })
    text:choice("labelPosition", "Position", lists.labelPositions, { enabledIf = showsLabel })
    text:slider("labelSize", "Size", 8, 20, 1, { enabledIf = showsLabel })
    text:choice("labelColor", "Color", lists.colors, { enabledIf = showsLabel })

    -- Nameplates have their own look: enemy plates are red, so the target marker's colors may not show on them.
    local platesOn = function(s) return s.nameplateMode ~= "off" end
    local plateIcon = function(s) return s.nameplateMode == "markerIcon" end
    local plateSingle = function(s) return platesOn(s) and s.plateDotColors == "single" end
    local plateOutline = function(s) return platesOn(s) and s.plateOutlineStyle ~= "none" end
    local plates = addTab("Nameplates")
    plates:choice("nameplateMode", "Show on nameplates", lists.nameplateModes, { tooltip = "Draws a marker "
        .. "(and optionally the kill icon) on every enemy nameplate with your DoTs on it, in its own look below." })
    plates:choice("plateIcon", "Kill icon", lists.icons, { enabledIf = plateIcon })
    plates:slider("nameplateIconSize", "Kill icon size", 12, 32, 1, { enabledIf = plateIcon })
    plates:choice("nameplateIconPosition", "Kill icon position", lists.nameplateIconPositions,
        { enabledIf = plateIcon })
    plates:slider("plateIconOffsetX", "Icon horizontal offset", -40, 40, 1,
        { enabledIf = plateIcon, tooltip = "Pixels right (+) or left (-) of the chosen position." })
    plates:slider("plateIconOffsetY", "Icon vertical offset", -40, 40, 1,
        { enabledIf = plateIcon, tooltip = "Pixels up (+) or down (-) from the chosen position." })
    plates:gap()
    plates:choice("plateDotColors", "DoT colors", lists.dotColors, { enabledIf = platesOn })
    plates:choice("plateFillTexture", "Fill style", lists.fills, { enabledIf = platesOn })
    plates:choice("plateFillColor", "Fill color", lists.colors, { enabledIf = plateSingle })
    plates:slider("plateFillOpacity", "Fill opacity", 0, 100, 5, { suffix = "%", enabledIf = platesOn })
    plates:choice("plateOutlineStyle", "Outline", lists.outlines, { enabledIf = platesOn })
    plates:choice("plateDashLength", "Dash length", lists.dashLengths,
        { enabledIf = function(s) return platesOn(s) and s.plateOutlineStyle == "dashed" end })
    plates:slider("plateOutlineThickness", "Outline thickness", 1, 3, 1, { enabledIf = plateOutline })
    plates:choice("plateOutlineColor", "Outline color", lists.colors, { enabledIf = plateOutline })
    plates:slider("plateOutlineOpacity", "Outline opacity", 10, 100, 5, { suffix = "%", enabledIf = plateOutline })
    plates.footer = pushButton(window.settingsArea, "Copy from Marker tab", 160, function()
        local db = ns.db
        db.plateFillTexture, db.plateFillColor, db.plateFillOpacity = db.fillTexture, db.fillColor, db.fillOpacity
        db.plateDotColors, db.plateIcon = db.dotColors, db.skullIcon
        db.plateOutlineStyle, db.plateDashLength = db.outlineStyle, db.dashLength
        db.plateOutlineThickness = math.min(db.outlineThickness, 3)
        db.plateOutlineColor, db.plateOutlineOpacity = db.outlineColor, db.outlineOpacity
        changed()
    end)
    plates.footer:SetPoint("BOTTOMLEFT", 10, 10)
    plates.footer:Hide()

    local behavior = addTab("Behavior")
    behavior:choice("waitFirstTick", "Wait for first tick", lists.waitModes, { tooltip = "Whether a new DoT "
        .. "counts before its first tick lands. \"When unsure\" waits for finishers with unknown combo points "
        .. "and spells the addon hasn't seen tick yet." })
    behavior:checkbox("estimateDuringCast", "Estimate during casting", { tooltip = "Shows a DoT with a cast time "
        .. "while you're still casting it. Once the cast lands the normal estimate takes over; an interrupted or "
        .. "failed cast removes it." })
    behavior:checkbox("debug", "Echo trace log to chat",
        { tooltip = "Prints each DoT cast, matched tick and estimate to chat." })
    behavior:action("Learned tick sizes", "Reset", function() ns.resetLearnedTicks() end,
        { tooltip = "Forget the tick sizes learned from earlier casts." })
end

local function buildPreview(pane)
    -- y in px from the pane's top (pane: PREVIEW_WIDTH x ~486); every block on the same 12 px side margins.
    local SIDE = 12
    local CARD_WIDTH = PREVIEW_WIDTH - 2 * SIDE -- 266
    local RULE = { 0.28, 0.28, 0.3 }

    -- Forever ships its own bronze ("-c60") versions of the modern HUD art: those first, else the plain atlas
    -- (Retail). false when neither exists, so the caller keeps a plain fallback.
    local function setAtlas(texture, name)
        if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
        for _, candidate in ipairs({ name .. "-c60", name }) do
            if C_Texture.GetAtlasInfo(candidate) then
                texture:SetAtlas(candidate)
                return true
            end
        end
        return false
    end
    local function fontOr(name, fallback) return _G[name] and name or fallback end
    -- Vertical gradient (bottom colour, top colour); a flat colour where the client has no gradient API.
    local function gradient(texture, bottom, top)
        texture:SetTexture(WHITE)
        if CreateColor and pcall(texture.SetGradient, texture, "VERTICAL",
            CreateColor(bottom[1], bottom[2], bottom[3], bottom[4]), CreateColor(top[1], top[2], top[3], top[4])) then
            return
        end
        texture:SetVertexColor(bottom[1], bottom[2], bottom[3], (bottom[4] + top[4]) / 2)
    end
    -- Section header: small gold caps and a hairline to the right margin.
    local function header(text, anchor, gap)
        local label = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
        label:SetText(text)
        label:SetTextColor(0.85, 0.7, 0.3)
        local rule = pane:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(RULE[1], RULE[2], RULE[3], 1)
        rule:SetHeight(1)
        rule:SetPoint("LEFT", label, "RIGHT", 8, 0)
        rule:SetPoint("RIGHT", pane, "RIGHT", -SIDE, 0)
        return label
    end

    -- Title row, level with the tab row on the right (its divider is also 34 px down).
    local title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", SIDE, -12)
    title:SetText("Live preview")
    local titleRule = pane:CreateTexture(nil, "ARTWORK")
    titleRule:SetColorTexture(RULE[1], RULE[2], RULE[3], 1)
    titleRule:SetHeight(1)
    titleRule:SetPoint("TOPLEFT", 8, -34)
    titleRule:SetPoint("TOPRIGHT", -8, -34)

    -- Scene (44..234): a patch of dusky world behind the mock frames, so they read as the game's own HUD.
    local scene = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    scene:SetSize(CARD_WIDTH, 190)
    scene:SetPoint("TOP", pane, "TOP", 0, -44)
    scene:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
    scene:SetBackdropBorderColor(0, 0, 0, 1)
    local ground = scene:CreateTexture(nil, "BACKGROUND", nil, -8)
    ground:SetPoint("TOPLEFT", 1, -1)
    ground:SetPoint("BOTTOMRIGHT", -1, 1)
    ground:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
    ground:SetTexCoord(0, 0.26, 0, 0.18) -- about 1:1 texels on a 266 x 190 patch
    ground:SetVertexColor(0.75, 0.8, 0.75)
    local sky = scene:CreateTexture(nil, "BACKGROUND", nil, -7)
    sky:SetAllPoints(ground)
    gradient(sky, { 0.055, 0.08, 0.04, 0.25 }, { 0.07, 0.1, 0.15, 0.6 })
    local topShade = scene:CreateTexture(nil, "BACKGROUND", nil, -6)
    topShade:SetPoint("TOPLEFT", ground, "TOPLEFT")
    topShade:SetPoint("TOPRIGHT", ground, "TOPRIGHT")
    topShade:SetHeight(26)
    gradient(topShade, { 0, 0, 0, 0 }, { 0, 0, 0, 0.6 })
    local bottomShade = scene:CreateTexture(nil, "BACKGROUND", nil, -6)
    bottomShade:SetPoint("BOTTOMLEFT", ground, "BOTTOMLEFT")
    bottomShade:SetPoint("BOTTOMRIGHT", ground, "BOTTOMRIGHT")
    bottomShade:SetHeight(30)
    gradient(bottomShade, { 0, 0, 0, 0.65 }, { 0, 0, 0, 0 })

    -- Mock target frame: Forever's own target frame (TargetFrameTemplate, 232 x 100) rebuilt from its atlases at
    -- Blizzard's offsets, so the marker and kill icon land where they will in combat.
    local mock = CreateFrame("Frame", nil, scene)
    mock:SetSize(232, 100)
    mock:SetPoint("TOP", scene, "TOP", 0, -4)

    local portrait = mock:CreateTexture(nil, "BACKGROUND", nil, 1)
    portrait:SetSize(58, 58)
    portrait:SetPoint("TOPRIGHT", mock, "TOPRIGHT", -26, -19)
    portrait:SetTexture("Interface\\Icons\\Achievement_Reputation_MurlocOracle")
    portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- the icon's own border would show at the circle's edge
    local mask = mock:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(portrait)
    portrait:AddMaskTexture(mask)

    local frameArt = mock:CreateTexture(nil, "BACKGROUND", nil, 2)
    frameArt:SetSize(192, 67)
    frameArt:SetPoint("TOPLEFT", mock, "TOPLEFT", 20, -16)
    local hasFrameArt = setAtlas(frameArt, "UI-HUD-UnitFrame-Target-PortraitOn")
    if not hasFrameArt then
        frameArt:ClearAllPoints()
        frameArt:SetPoint("TOPLEFT", mock, "TOPLEFT", 18, -22)
        frameArt:SetSize(134, 42)
        frameArt:SetColorTexture(0, 0, 0, 0.55)
    end

    local nameBand = mock:CreateTexture(nil, "BORDER")
    nameBand:SetSize(135, 18)
    nameBand:SetPoint("TOPLEFT", mock, "TOPLEFT", 22, -25)
    if setAtlas(nameBand, "UI-HUD-UnitFrame-Target-PortraitOn-Type") then
        nameBand:SetVertexColor(1, 0, 0) -- hostile, as UnitSelectionColor colours it
    else
        nameBand:Hide()
    end

    local name = mock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetSize(117, 12)
    name:SetPoint("TOPLEFT", mock, "TOPLEFT", 24, -26)
    name:SetJustifyH("LEFT")
    name:SetText("Murloc Raider")

    local levelCircle = mock:CreateTexture(nil, "OVERLAY")
    levelCircle:SetSize(39, 39)
    levelCircle:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", -13, 7)
    local level = mock:CreateFontString(nil, "OVERLAY", fontOr("WhiteLargeNumberFont", "GameFontNormal"))
    level:SetDrawLayer("OVERLAY", 2)
    level:SetPoint("CENTER", levelCircle, "CENTER", 0, -0.5)
    level:SetText("12")
    level:SetTextColor(1, 0.82, 0) -- same-level ("fair") difficulty colour
    if not setAtlas(levelCircle, "UI-HUD-UnitFrame-SmallCircle") then
        levelCircle:Hide()
        level:Hide()
    end

    -- Health bar: 126 x 20 in the frame art's upper slot (the lower, power slot stays empty: a murloc raider
    -- has no mana). The marker is SetAllPoints'd onto this bar.
    local healthBar = CreateFrame("StatusBar", nil, mock)
    healthBar:SetSize(126, 20)
    healthBar:SetPoint("TOPLEFT", mock, "TOPLEFT", 22, -39)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    if setAtlas(healthBar:GetStatusBarTexture(), "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health") then
        healthBar:SetStatusBarColor(1, 1, 1)
    else
        healthBar:SetStatusBarColor(0.1, 0.8, 0.1)
    end
    if not hasFrameArt then
        local healthBack = healthBar:CreateTexture(nil, "BACKGROUND")
        healthBack:SetAllPoints()
        healthBack:SetColorTexture(0.25, 0.08, 0.08, 1)
    end
    -- The numbers the game's own frame prints on the bar: percent on the left, health on the right.
    local barText = fontOr("TextStatusBarText", "GameFontHighlightSmall")
    window.healthPercent = healthBar:CreateFontString(nil, "OVERLAY", barText)
    window.healthPercent:SetPoint("LEFT", healthBar, "LEFT", 3, 0)
    window.healthValue = healthBar:CreateFontString(nil, "OVERLAY", barText)
    window.healthValue:SetPoint("RIGHT", healthBar, "RIGHT", -3, 0)

    window.healthBar = healthBar
    window.host = { healthBar = healthBar, portrait = portrait, layerFrame = window }
    window.mock = mock

    -- Mock enemy nameplate: Forever's default ("Thin") plate, 190 wide: a 133 x 13 bar, the level badge right
    -- of it, the name centred above. Drawn on by the real nameplate code (Nameplates.lua).
    local mockPlate = CreateFrame("Frame", nil, scene)
    mockPlate:SetSize(190, 36)
    mockPlate:SetPoint("BOTTOM", scene, "BOTTOM", 0, 22)
    local plateBar = CreateFrame("StatusBar", nil, mockPlate)
    plateBar:SetSize(133, 13)
    plateBar:SetPoint("BOTTOMLEFT", mockPlate, "BOTTOMLEFT", 12, 6)
    plateBar:SetMinMaxValues(0, 100)
    plateBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    if setAtlas(plateBar:GetStatusBarTexture(), "UI-HUD-CoolDownManager-Bar") then
        plateBar:SetStatusBarColor(1, 0, 0) -- hostile
    else
        plateBar:SetStatusBarColor(0.85, 0.1, 0.1)
    end
    local plateBack = mockPlate:CreateTexture(nil, "BACKGROUND")
    plateBack:SetPoint("TOPLEFT", plateBar, "TOPLEFT", -2, 3)
    plateBack:SetPoint("BOTTOMRIGHT", plateBar, "BOTTOMRIGHT", 6, -6)
    if not setAtlas(plateBack, "UI-HUD-CoolDownManager-Bar-BG") then
        plateBack:ClearAllPoints()
        plateBack:SetAllPoints(plateBar)
        plateBack:SetColorTexture(0.1, 0.02, 0.02, 1)
    end
    -- It is your target's plate: the target border (Forever: yellow art, vertex white).
    local plateSelected = plateBar:CreateTexture(nil, "OVERLAY")
    plateSelected:SetPoint("TOPLEFT", plateBack, "TOPLEFT", -3, 2)
    plateSelected:SetPoint("BOTTOMRIGHT", plateBack, "BOTTOMRIGHT", 0, 2)
    if setAtlas(plateSelected, "UI-HUD-CoolDownManager-Selected-yellow") then
        plateSelected:SetVertexColor(1, 1, 1, 0.9)
    else
        plateSelected:Hide()
    end
    local plateLevel = mockPlate:CreateTexture(nil, "ARTWORK")
    plateLevel:SetSize(28, 16)
    plateLevel:SetPoint("LEFT", plateBar, "RIGHT", 5, 0)
    local plateLevelText = mockPlate:CreateFontString(nil, "OVERLAY", fontOr("SystemFont_NamePlateLevel", "GameFontNormalSmall"))
    plateLevelText:SetPoint("CENTER", plateLevel, "CENTER")
    plateLevelText:SetText("12")
    plateLevelText:SetTextColor(1, 0.82, 0)
    if not setAtlas(plateLevel, "UI-HUD-Nameplates-LevelIndicator") then
        plateLevel:Hide()
        plateLevelText:Hide()
    end
    local plateName = mockPlate:CreateFontString(nil, "OVERLAY",
        fontOr("SystemFont_NamePlate_Outlined", "GameFontHighlightSmallOutline"))
    plateName:SetPoint("BOTTOMLEFT", plateBar, "TOPLEFT", 0, 6) -- clear of the target border, which rises 5 above the bar
    plateName:SetPoint("RIGHT", plateLevel, "RIGHT")
    plateName:SetJustifyH("CENTER")
    plateName:SetText("Murloc Raider")
    plateName:SetTextColor(1, 0.13, 0.13) -- hostile
    window.mockPlate = mockPlate
    window.plateHealthBar = plateBar
    window.plateHost = { plate = mockPlate, healthBar = plateBar }

    -- Shown over the mock frames while combat has the display back on the real target. On its own layer above
    -- the scene: a font string on the pane would draw under it.
    local noteLayer = CreateFrame("Frame", nil, scene)
    noteLayer:SetAllPoints(scene)
    noteLayer:SetFrameLevel(mock:GetFrameLevel() + 10)
    window.combatNote = noteLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    window.combatNote:SetPoint("CENTER", scene, "CENTER")
    window.combatNote:SetWidth(CARD_WIDTH - 24)
    window.combatNote:SetText("In combat: the marker and kill icon are showing on your target. "
        .. "The preview resumes after combat.")
    window.combatNote:Hide()

    -- Verdict badge (242..272), right under the scene it describes: accent stripe, icon, verdict, numbers.
    local badge = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    badge:SetSize(CARD_WIDTH, 30)
    badge:SetPoint("TOP", scene, "BOTTOM", 0, -8)
    badge:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    badge.accent = badge:CreateTexture(nil, "ARTWORK")
    badge.accent:SetPoint("TOPLEFT", 1, -1)
    badge.accent:SetPoint("BOTTOMLEFT", 1, 1)
    badge.accent:SetWidth(3)
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetSize(18, 18)
    badge.icon:SetPoint("LEFT", badge, "LEFT", 12, 0)
    window.statusDetail = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.statusDetail:SetPoint("RIGHT", badge, "RIGHT", -10, 0)
    window.statusDetail:SetJustifyH("RIGHT")
    window.statusDetail:SetTextColor(0.75, 0.75, 0.75)
    window.status = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    window.status:SetPoint("LEFT", badge.icon, "RIGHT", 8, 0)
    window.status:SetPoint("RIGHT", window.statusDetail, "LEFT", -8, 0)
    window.status:SetJustifyH("LEFT")
    window.status:SetWordWrap(false)
    window.statusBadge = badge

    -- Try it: the preview's own numbers (not settings).
    local tryIt = header("TRY IT", badge, 16)
    local health = sliderRow(pane, "Target health", 0, 100, 1,
        function() return preview.health end,
        function(value)
            stopSimulation()
            preview.health = value
            updatePreview()
        end, { layout = PREVIEW_LAYOUT, suffix = "%" })
    health:SetPoint("TOPLEFT", tryIt, "BOTTOMLEFT", -6, -6) -- rows start 6 px in, so their labels sit on the margin
    local damage = sliderRow(pane, "DoT damage", 0, 100, 1,
        function() return math.floor(previewTotal() + 0.5) end,
        function(value)
            stopSimulation()
            setPreviewDamage(value)
            updatePreview()
        end, { layout = PREVIEW_LAYOUT, suffix = "%",
            tooltip = "Remaining damage of two sample DoTs, in % of the target's max health." })
    damage:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, 0)

    window.simulateButton = pushButton(pane, "Simulate fight", 162, function()
        if simulation then stopSimulation() else startSimulation() end
    end)
    window.simulateButton:SetPoint("TOPLEFT", damage, "BOTTOMLEFT", 6, -10)
    window.flashButton = pushButton(pane, "Flash", 96, function() ns.playFlash() end)
    window.flashButton:SetPoint("LEFT", window.simulateButton, "RIGHT", 8, 0)

    local hint = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", SIDE, 12)
    hint:SetWidth(CARD_WIDTH)
    hint:SetJustifyH("LEFT")
    hint:SetText("While this window is open, the marker and kill icon are drawn here instead of on your target.")
    local hintRule = pane:CreateTexture(nil, "ARTWORK")
    hintRule:SetColorTexture(RULE[1], RULE[2], RULE[3], 1)
    hintRule:SetHeight(1)
    hintRule:SetPoint("BOTTOMLEFT", hint, "TOPLEFT", 0, 8)
    hintRule:SetPoint("RIGHT", pane, "RIGHT", -SIDE, 0)
end

-- The presets, the preview and the settings, in window: the addon's own window, below its title bar
-- with the presets beside anchor (its close button), or inside BattleInfoTool the tab it is built into.
local function buildContent(top, anchor)
    -- Presets, right-aligned in the title bar.
    local presetLabel = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    local previous
    for i = #PRESETS, 1, -1 do
        local preset = PRESETS[i]
        local button = pushButton(window, preset.label, 72, function() applyPreset(preset) end)
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -4, 0)
        else
            button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
        end
        previous = button
    end
    presetLabel:SetPoint("RIGHT", previous, "LEFT", -8, 0)
    presetLabel:SetText("Presets")

    local pane = CreateFrame("Frame", nil, window, "BackdropTemplate")
    pane:SetPoint("TOPLEFT", 10, -top)
    pane:SetPoint("BOTTOMLEFT", 10, 10)
    pane:SetWidth(PREVIEW_WIDTH)
    setBackdrop(pane, 0.09)
    buildPreview(pane)

    local area = CreateFrame("Frame", nil, window, "BackdropTemplate")
    area:SetPoint("TOPLEFT", pane, "TOPRIGHT", 10, 0)
    area:SetPoint("BOTTOMRIGHT", -10, 10)
    setBackdrop(area, 0.09)
    window.settingsArea = area

    local divider = area:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.28, 0.28, 0.3, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 8, -34)
    divider:SetPoint("TOPRIGHT", -8, -34)

    buildTabs()
    local reset = pushButton(area, "Reset this tab", 120, function() resetTab(activeTab) end)
    reset:SetPoint("BOTTOMRIGHT", -10, 10)

    window:SetScript("OnShow", function()
        ns.setPreviewState(preview)
        window.previewPaused = nil
        syncDisplayHost()
        refreshControls()
        updatePreview()
    end)
    window:SetScript("OnHide", function()
        stopSimulation()
        closeMenu()
        ns.setPreviewState(nil)
        ns.setDisplayHost(nil)
        ns.setPlatePreview(nil)
    end)
    -- Combat hands the display back to the real target, and after combat back to the preview.
    window:RegisterEvent("PLAYER_REGEN_DISABLED")
    window:RegisterEvent("PLAYER_REGEN_ENABLED")
    window:SetScript("OnEvent", function() syncDisplayHost() end)
    selectTab(tabs[1])
end

local function createWindow()
    window = CreateFrame("Frame", "BattleInfoTool_DoTInfoOptions", UIParent, "BackdropTemplate")
    window:Hide() -- new frames start shown; ns.openOptions shows it (running OnShow)
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    setBackdrop(window, 0.06, 0.97)
    table.insert(UISpecialFrames, "BattleInfoTool_DoTInfoOptions") -- Escape closes it

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -18)
    title:SetText("DoTInfo")

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -12)

    buildContent(HEADER_HEIGHT, close)
end

function ns.openOptions()
    if not ns.db then return end
    if BIT.OpenSettings then BIT.OpenSettings("DoTInfo") return end
    if not window then createWindow() end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end

-- Options > AddOns > DoTInfo: a short page with a button that opens the window.
function ns.registerOptions()
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DoTInfo")
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    text:SetText("Settings have their own window with a live preview. You can also type /dotinfo.")
    local open = pushButton(panel, "Open DoTInfo options", 200, function()
        if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
        if not (window and window:IsShown()) then ns.openOptions() end
    end)
    open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
    local category = Settings.RegisterCanvasLayoutCategory(panel, "DoTInfo")
    Settings.RegisterAddOnCategory(category)
end

-- Inside BattleInfoTool: the window's content in its tab, with the presets at the tab's top right.
if BIT.RegisterTab then
    BIT.RegisterTab("DoTInfo", {
        title = "DoTInfo",
        summary = "Marks on the target's health bar the damage your DoTs still have to deal, with a kill icon "
            .. "when they will finish it.",
        width = WINDOW_WIDTH, height = WINDOW_HEIGHT - HEADER_HEIGHT + 44,
        build = function(parent)
            window = parent
            local anchor = CreateFrame("Frame", nil, parent)
            anchor:SetSize(1, 22)
            anchor:SetPoint("TOPRIGHT", -10, -8)
            buildContent(40, anchor)
        end,
    })
    BIT.tabWords.dot, BIT.tabWords.did = "DoTInfo", "DoTInfo"
end
