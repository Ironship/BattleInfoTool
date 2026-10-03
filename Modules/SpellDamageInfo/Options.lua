-- BattleInfoTool module SpellDamageInfo: ported by tools/port.py from SpellDamageInfo/Options.lua at 8269edd.
-- Change it there, or in tools/port.py; an edit made here is lost at the next port.
-- SpellDamageInfo: the settings window (/sdi) and its page in Options > AddOns.
-- Options window adapted from a standalone DoT addon by Joe Greive (MIT).
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
-- Portions Copyright (c) 2026 Joe Greive, used under the MIT licence; his notice is in LICENSE.
--
-- Left: a live preview, three mock action buttons (frames of our own, never real action
-- buttons) whose numbers are drawn by Core.lua's own ns.ButtonText and ns.DrawNumber, so the
-- preview shows exactly what the bars show. Right: the settings. Every change goes through
-- ns.SetSetting, which refreshes the real buttons.
--
-- The controls are built from basic widgets (CheckButton, Slider, Button) rather than Blizzard
-- templates, so they do not depend on templates behaving the same on every client. Nothing here
-- touches a secure frame or calls a protected function, so the window works in combat too.

local _, BIT = ...
-- Inside BattleInfoTool its own namespace; loaded on its own, the addon's table as before.
local ns = BIT.Module and BIT.Module("SpellDamageInfo") or BIT
local L, Estimate = ns.L, ns.Estimate

local WHITE = "Interface\\Buttons\\WHITE8X8"
local WINDOW_WIDTH, WINDOW_HEIGHT = 660, 384
local HEADER_HEIGHT = 46
local PREVIEW_WIDTH = 250
local ROW_HEIGHT = 28
local LAYOUT = { label = 186, control = 150 }
local DISABLED_ALPHA = 0.35
local MOCK_SIZE = 36     -- a Blizzard action button, so the number gets the size it gets on the bar
local MOCK_SCALE = 1.5   -- the preview magnifies the whole button, number and all
local SIZE_STEP = 5

-- The preview's sample spells, as the parser would read them, with 50 spell power in every
-- school: Immolate r8 (direct and over time, 2 sec cast, the client's shares for spell 25309), a
-- pet's Screech (damage and a reduction next to it) and Curse of Weakness (a reduction alone);
-- under them, with a 2.6 sec weapon that hits for 120 on average, Heroic Strike (a weapon hit plus
-- 157) and Forever's Rockbiter Weapon (554 attack power, shown as what it adds to each hit).
local SAMPLE_POWER = { [2] = 50, [3] = 50, [4] = 50, [5] = 50, [6] = 50, [7] = 50 }
local SAMPLE_WEAPON = { melee = 120, meleeSpeed = 2.6 }
local PER_ROW = 3
local SAMPLES = {
  { name = "OPT_SAMPLE_1", icon = "Interface\\Icons\\Spell_Fire_Immolation", hotkey = "1", castTime = 2,
    spellID = 25309,
    parsed = { school = "fire", direct = { min = 279, max = 279 }, dot = { total = 510, duration = 15 } } },
  { name = "OPT_SAMPLE_2", icon = "Interface\\Icons\\Ability_Hunter_Pet_Bat", hotkey = "2", castTime = 0,
    parsed = { direct = { min = 26, max = 46 } },
    reduction = { amount = 100, percent = false, stat = "attackpower" } },
  { name = "OPT_SAMPLE_3", icon = "Interface\\Icons\\Spell_Shadow_CurseOfMannoroth", hotkey = "3",
    reduction = { amount = 3, percent = false, stat = "damage" } },
  { name = "OPT_SAMPLE_4", icon = "Interface\\Icons\\Ability_Rogue_Ambush", hotkey = "4",
    weapon = { kind = "next", bonus = 157 } },
  { name = "OPT_SAMPLE_5", icon = "Interface\\Icons\\Spell_Nature_RockBiter", hotkey = "5",
    weapon = { kind = "ap", amount = 554 } },
  { name = "OPT_SAMPLE_6", icon = "Interface\\Icons\\Spell_Shadow_BurningSpirit", hotkey = "Mou...",
    view = { healthCost = 58, manaGain = 58 } },
}

local window
local controls = {} -- every settings row, refreshed after each change
local menu -- the shared choice list

local function db() return ns.GetSettings() end

local function say(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffSpellDamageInfo|r: " .. msg) end
end

local function inCombat()
  if type(InCombatLockdown) ~= "function" then return false end
  local ok, v = pcall(InCombatLockdown)
  return ok and v == true
end

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

---------------------------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------------------------

-- What the real bar would draw for a sample, under the current settings. On Retail the bars add
-- neither the estimate nor the weapon arithmetic (the descriptions hold the stats), so neither does this.
local function sampleText(sample)
  local view
  local retail = ns.IsRetail and ns.IsRetail()
  if sample.view then
    view = sample.view
  elseif sample.weapon then
    local w = db().weapon and not retail and ns.WeaponView(sample.weapon, SAMPLE_WEAPON) or nil
    view = w and { weapon = w } or nil
  elseif sample.parsed then
    local bonus = db().estimate and not retail and Estimate.DamageBonus(sample.parsed.school, SAMPLE_POWER) or nil
    local coef = sample.spellID and ns.SpellCoefficientsFor and ns.SpellCoefficientsFor(sample.spellID) or nil
    view = Estimate.Apply(sample.parsed, sample.castTime, bonus, nil, coef)
  end
  return ns.ButtonText(view, sample.reduction)
end

local function updatePreview()
  if not window then return end
  for _, mock in ipairs(window.mocks) do
    local mainText, mainColor, sideText, sideColor, layout = sampleText(mock.sample)
    ns.DrawNumber(mock, mock.main, mock.side, mainText, mainColor, sideText, false, sideColor, layout)
  end
  window.offNote:SetShown(db().button == "off")
end

local function refreshControls()
  for _, row in ipairs(controls) do row:Refresh() end
end

local function changed()
  refreshControls()
  updatePreview()
end

local function set(key, value)
  if key == "interfaceLang" then
    ns.SetSetting(key, value)
    ns.SetInterfaceAndRefreshL(value)
    say(L.OPT_LANG_CHANGED)
  else
    ns.SetSetting(key, value)
  end
  changed()
end

local function mockButton(pane, sample, x, y)
  local mock = CreateFrame("Frame", nil, pane, "BackdropTemplate")
  mock:SetSize(MOCK_SIZE, MOCK_SIZE)
  mock:SetScale(MOCK_SCALE)
  -- offsets are in the mock's own (scaled) units
  mock:SetPoint("TOPLEFT", pane, "TOPLEFT", x / MOCK_SCALE, -y / MOCK_SCALE)
  mock:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
  mock:SetBackdropBorderColor(0, 0, 0, 1)
  local icon = mock:CreateTexture(nil, "BACKGROUND")
  icon:SetPoint("TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", -1, 1)
  icon:SetTexture(sample.icon)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  -- the hotkey, where Blizzard puts it, so the number's place can be judged against it
  local hotkey = mock:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
  hotkey:SetPoint("TOPRIGHT", mock, "TOPRIGHT", -2, -2)
  hotkey:SetText(sample.hotkey)
  mock.main = ns.NewLabel(mock)
  mock.side = ns.NewLabel(mock)
  mock.sample = sample

  local caption = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  caption:SetPoint("TOP", mock, "BOTTOM", 0, -6)
  caption:SetWidth(76)
  caption:SetText(L[sample.name])
  return mock
end

local function buildPreview(pane)
  local title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -12)
  title:SetText(L.OPT_PREVIEW)

  window.mocks = {}
  local span = MOCK_SIZE * MOCK_SCALE
  local gap = (PREVIEW_WIDTH - PER_ROW * span) / (PER_ROW + 1)
  for i, sample in ipairs(SAMPLES) do
    local row, col = math.floor((i - 1) / PER_ROW), (i - 1) % PER_ROW
    local inRow = math.min(PER_ROW, #SAMPLES - row * PER_ROW)
    -- a shorter row is centred under the one above it
    local shift = (PER_ROW - inRow) * (span + gap) / 2
    window.mocks[i] = mockButton(pane, sample, gap + shift + col * (span + gap), 44 + row * (span + 56))
  end

  window.offNote = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  window.offNote:SetPoint("TOP", pane, "TOP", 0, -44 - span - 36)
  window.offNote:SetText(L.OPT_PREVIEW_OFF)
  window.offNote:Hide()

  local hint = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 12, 12)
  hint:SetWidth(PREVIEW_WIDTH - 24)
  hint:SetJustifyH("LEFT")
  hint:SetText(L.OPT_PREVIEW_HINT)
end

---------------------------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------------------------

local function makeRow(parent, labelText, opts)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(LAYOUT.label + LAYOUT.control + 20, ROW_HEIGHT)
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.label:SetPoint("LEFT", 6, 0)
  row.label:SetWidth(LAYOUT.label - 8)
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
  controls[#controls + 1] = row
  return row
end

local function checkbox(parent, key, labelText, opts)
  local row = makeRow(parent, labelText, opts)
  local box = CreateFrame("CheckButton", nil, row)
  box:SetSize(24, 24)
  box:SetPoint("LEFT", row, "LEFT", LAYOUT.label, 0)
  box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  box:SetScript("OnClick", function(self) set(key, self:GetChecked() and true or false) end)
  function row:Refresh()
    box:SetChecked(db()[key] and true or false)
    self:ApplyEnabled(box)
  end
  row.widget = box
  return row
end

local function slider(parent, key, labelText, min, max, step, opts)
  local row = makeRow(parent, labelText, opts)
  local bar = CreateFrame("Slider", nil, row)
  bar:SetOrientation("HORIZONTAL")
  bar:SetSize(LAYOUT.control - 44, 18)
  bar:SetPoint("LEFT", row, "LEFT", LAYOUT.label + 2, 0)
  bar:SetMinMaxValues(min, max)
  bar:SetValueStep(step)
  bar:SetObeyStepOnDrag(true)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(0.3, 0.3, 0.32, 1)
  track:SetHeight(4)
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  bar:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  bar:GetThumbTexture():SetSize(18, 24)
  local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  valueText:SetPoint("LEFT", bar, "RIGHT", 8, 0)
  local suffix = opts.suffix or ""
  local updating = false
  bar:SetScript("OnValueChanged", function(_, value)
    if updating then return end
    value = math.floor(value / step + 0.5) * step
    valueText:SetText(value .. suffix)
    set(key, value)
  end)
  bar:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)
  function row:Refresh()
    updating = true
    local value = db()[key]
    bar:SetValue(value)
    valueText:SetText(value .. suffix) -- /sdi size takes any whole number, so show it as it is
    updating = false
    self:ApplyEnabled(bar)
  end
  row.widget = bar
  return row
end

local function closeMenu()
  if menu then menu:Hide() end
end

-- The shared choice list under `owner`.
local function openMenu(owner, list, current, pick)
  if not menu then
    menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:EnableMouse(true)
    setBackdrop(menu, 0.08, 0.98)
    menu.buttons = {}
    -- close on a click anywhere else (the event may not exist on every client; clicking the
    -- owner again closes it too)
    pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
    menu:SetScript("OnEvent", function(self)
      if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
    end)
  end
  if menu:IsShown() and menu.owner == owner then return menu:Hide() end
  menu.owner = owner
  -- above the window, which is raised when opened over Blizzard's options in combat
  menu:SetFrameStrata((window and window:GetFrameStrata() == "FULLSCREEN_DIALOG") and "TOOLTIP" or "FULLSCREEN_DIALOG")
  for i, entry in ipairs(list) do
    local button = menu.buttons[i]
    if not button then
      button = CreateFrame("Button", nil, menu)
      button:SetHeight(20)
      local highlight = button:CreateTexture(nil, "HIGHLIGHT")
      highlight:SetAllPoints()
      highlight:SetColorTexture(1, 1, 1, 0.1)
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      button.text:SetPoint("LEFT", 8, 0)
      button.text:SetJustifyH("LEFT")
      menu.buttons[i] = button
    end
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -4 - (i - 1) * 20)
    button:SetPoint("RIGHT", menu, "RIGHT", -1, 0)
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
  local row = makeRow(parent, labelText, opts)
  local button = CreateFrame("Button", nil, row, "BackdropTemplate")
  button:SetSize(LAYOUT.control, 22)
  button:SetPoint("LEFT", row, "LEFT", LAYOUT.label, 0)
  setBackdrop(button, 0.13)
  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.06)
  local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetJustifyH("LEFT")
  text:SetPoint("LEFT", 8, 0)
  text:SetPoint("RIGHT", -20, 0)
  local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  arrow:SetPoint("RIGHT", -8, 0)
  arrow:SetText("v")
  button:SetScript("OnClick", function(self)
    openMenu(self, list, db()[key], function(id) set(key, id) end)
  end)
  function row:Refresh()
    local entry = findEntry(list, db()[key])
    text:SetText(entry and entry.label or tostring(db()[key]))
    self:ApplyEnabled(button)
  end
  row.widget, row.text = button, text
  return row
end

local function pushButton(parent, text, width, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, 22)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end

---------------------------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------------------------

local function numbersShown(settings) return settings.button ~= "off" end

local function buildSettings(area)
  local rows, y = {}, 0
  local function place(key, row)
    row:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -12 - y)
    y = y + ROW_HEIGHT
    rows[key] = row
  end
  place("button", choice(area, "button", L.OPT_BUTTON, {
    { id = "total", label = L.OPT_BUTTON_TOTAL },
    { id = "direct", label = L.OPT_BUTTON_DIRECT },
    { id = "off", label = L.OPT_BUTTON_OFF },
  }, { tooltip = L.OPT_BUTTON_TIP }))
  place("size", slider(area, "size", L.OPT_SIZE, ns.SIZE_MIN, ns.SIZE_MAX, SIZE_STEP,
    { suffix = "%", tooltip = L.OPT_SIZE_TIP, enabledIf = numbersShown }))
  place("position", choice(area, "position", L.OPT_POSITION, {
    { id = "bottom", label = L.OPT_POS_BOTTOM },
    { id = "center", label = L.OPT_POS_CENTER },
    { id = "top", label = L.OPT_POS_TOP },
  }, { tooltip = L.OPT_POSITION_TIP, enabledIf = numbersShown }))
  y = y + 8
  -- On Retail the descriptions already hold the player's stats, so both estimates stand down.
  local notRetail = function() return not ns.IsRetail() end
  local retailNote = ns.IsRetail() and (" " .. L.OPT_RETAIL) or ""
  place("estimate", checkbox(area, "estimate", L.OPT_ESTIMATE,
    { tooltip = L.OPT_ESTIMATE_TIP .. retailNote, enabledIf = notRetail }))
  place("tooltip", checkbox(area, "tooltip", L.OPT_TOOLTIP, { tooltip = L.OPT_TOOLTIP_TIP }))
  place("reduction", checkbox(area, "reduction", L.OPT_REDUCTION, { tooltip = L.OPT_REDUCTION_TIP }))
  place("weapon", checkbox(area, "weapon", L.OPT_WEAPON, { tooltip = L.OPT_WEAPON_TIP .. retailNote, enabledIf = notRetail }))
  y = y + 8
  place("interfaceLang", choice(area, "interfaceLang", L.OPT_LANGUAGE, {
    { id = "auto", label = L.LANG_AUTO },
    { id = "en", label = L.LANG_EN },
    { id = "de", label = L.LANG_DE },
  }, { tooltip = L.OPT_LANGUAGE_TIP }))
  return rows
end

-- The preview and the settings, in window: the addon's own window, below its title bar, or
-- inside BattleInfoTool the tab it is built into.
local function buildContent(top)
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
  window.rows = buildSettings(area)

  window.reset = pushButton(area, L.OPT_RESET, 170, function()
    ns.ResetSettings()
    changed()
    say(L.OPT_RESET_DONE)
  end)
  window.reset:SetPoint("BOTTOMRIGHT", -10, 10)

  window:SetScript("OnShow", changed)
  window:SetScript("OnHide", closeMenu)
end

local function createWindow()
  window = CreateFrame("Frame", "SpellDamageInfoOptions", UIParent, "BackdropTemplate")
  window:Hide() -- new frames start shown; ns.OpenOptions shows it, which runs OnShow
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
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "SpellDamageInfoOptions") end -- Escape closes it

  local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("SpellDamageInfo")

  local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -8)

  buildContent(HEADER_HEIGHT)
end

function ns.OpenOptions()
  if BIT.OpenSettings then BIT.OpenSettings("SpellDamageInfo") return end
  if not window then createWindow() end
  if window:IsShown() then
    window:Hide()
  else
    window:SetFrameStrata("DIALOG")
    window:Show()
  end
end

-- /sdi changed something while the window is open.
function ns.OptionsChanged()
  if window and window:IsShown() then changed() end
end

-- Options > AddOns > SpellDamageInfo: a short page with a button that opens the window.
-- Returns which registration was used: "settings", "interface" or nil.
function ns.RegisterOptions()
  local panel = CreateFrame("Frame")
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("SpellDamageInfo")
  local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  text:SetText(L.OPT_PANEL_TEXT)
  local open = pushButton(panel, L.OPT_OPEN, 240, function()
    -- Closing Blizzard's options first: out of combat only, so nothing of the game's panel
    -- handling runs from here in combat. There the window opens above it instead.
    local host = (SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and SettingsPanel)
      or (InterfaceOptionsFrame and InterfaceOptionsFrame.IsShown and InterfaceOptionsFrame:IsShown() and InterfaceOptionsFrame)
    if host and not inCombat() and type(HideUIPanel) == "function" then
      pcall(HideUIPanel, host)
      host = host:IsShown() and host or nil
    end
    if not (window and window:IsShown()) then ns.OpenOptions() end
    if host then window:SetFrameStrata("FULLSCREEN_DIALOG") end
  end)
  open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
  ns._optionsPanel, ns._optionsOpenButton = panel, open

  if type(Settings) == "table" and type(Settings.RegisterCanvasLayoutCategory) == "function"
    and type(Settings.RegisterAddOnCategory) == "function" then
    local category = Settings.RegisterCanvasLayoutCategory(panel, "SpellDamageInfo")
    Settings.RegisterAddOnCategory(category)
    return "settings"
  elseif type(InterfaceOptions_AddCategory) == "function" then
    panel.name = "SpellDamageInfo"
    InterfaceOptions_AddCategory(panel)
    return "interface"
  end
  return nil
end

local loader = CreateFrame("Frame")
if not BIT.RegisterTab then loader:RegisterEvent("PLAYER_LOGIN") end
loader:SetScript("OnEvent", function()
  local ok, err = pcall(ns.RegisterOptions)
  if not ok then say("Options > AddOns page not added (" .. tostring(err) .. "); /sdi still opens the settings.") end
end)

-- BIT Minimal OFF-scene sample: static Immolate numbers (279 direct, 510
-- over 15 sec) as plain text, never live Estimate/DrawNumber output and
-- never real action buttons. This seam is a BIT-only edit replayed by
-- tools/port.py from tools/sdi_bit_edits.json on every regeneration;
-- tools/port.py itself is untouched.
local function buildSDIPreview(parent)
  local scene = CreateFrame("Frame", nil, parent)
  scene:SetSize(560, 120)
  scene.title = scene:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  scene.title:SetPoint("TOPLEFT", 12, -4)
  scene.title:SetText("SpellDamageInfo sample (not your buttons)")
  scene.main = scene:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  scene.main:SetPoint("TOPLEFT", 12, -30)
  scene.main:SetText("279")
  scene.main:SetHeight(14)
  scene.side = scene:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  scene.side:SetPoint("TOPLEFT", 12, -52)
  scene.side:SetText("510 over 15 sec")
  scene.side:SetHeight(14)
  return scene
end

local function renderSDIPreview(scene, style)
  BIT.Style.ApplyText(scene.title, style, "text")
  BIT.Style.ApplyText(scene.main, style, "text")
  BIT.Style.ApplyText(scene.side, style, "text")
  -- Native-Y min/max reflow: the two rows derive their depths and the scene
  -- its height from the shared font size; the window is never resized.
  local fontSize = style.fontSize or 12
  local mainDepth = 4 + fontSize + 8
  local sideDepth = mainDepth + fontSize + 4
  scene.main:ClearAllPoints()
  scene.main:SetPoint("TOPLEFT", 12, -mainDepth)
  scene.side:ClearAllPoints()
  scene.side:SetPoint("TOPLEFT", 12, -sideDepth)
  scene:SetSize(560, sideDepth + fontSize + 16)
end

if BIT.RegisterTab then
  BIT.RegisterTab("SpellDamageInfo", {
    title = "SpellDamageInfo",
    summary = "The damage and healing from each spell's description on your action buttons and in its tooltip.",
    width = WINDOW_WIDTH, height = WINDOW_HEIGHT - HEADER_HEIGHT + 10,
    build = function(parent)
      window = parent
      buildContent(10)
      changed()
    end,
    buildPreview = buildSDIPreview,
    previewRender = renderSDIPreview,
    capabilities = { roles = { "text" }, shapes = false,
      geometry = false, border = false, font = true, scale = false, opacity = true },
  })
  BIT.tabWords.sdi = "SpellDamageInfo"
end

-- For the tests.
ns._optionsWindow = function() return window end
ns._optionsMenu = function() return menu end
