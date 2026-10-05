-- BattleInfoTool module ResourceDing: ported by tools/port.py from ResourceDing/Settings.lua at 540b462.
-- Change it there, or in tools/port.py; an edit made here is lost at the next port.
local _, BIT = ...
local Addon = BIT.Module("ResourceDing")

local WHITE = "Interface\\Buttons\\WHITE8X8"
local PANE_WIDTH = 290
local ROW_HEIGHT = 26
local SETTINGS_LAYOUT = { label = 170, control = 200 }
local PREVIEW_LAYOUT = { label = 96, control = 140 }
local DISABLED_ALPHA = 0.35
local DIAMOND = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3"
local MAX_POINTS = 5

local controls = {}
local tabs, activeTab = {}, nil
local settingsArea
local previewState = { points = 5 }
local previewScene
local applySetting, updateLivePreview, refreshControls

local function clampNumber(value, low, high, fallback)
  value = tonumber(value)
  if value == nil or value ~= value then value = fallback end
  if value < low then value = low elseif value > high then value = high end
  return value
end

local function setBackdrop(frame, shade, alpha)
  if type(frame.SetBackdrop) ~= "function" then return end
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  frame:SetBackdropColor(shade, shade, shade, alpha or 1)
  frame:SetBackdropBorderColor(0.28, 0.28, 0.3, 1)
end

local function soundEntries()
  local entries = {}
  for _, key in ipairs(Addon.SOUND_ORDER) do
    entries[#entries + 1] = { key = key, name = Addon.SOUNDS[key].name }
  end
  return entries
end

-- A choice of sound for the setting setting (a key of Addon.SOUNDS); picking one plays it.
local function createDropdown(parent, name, setting)
  setting = setting or "sound"
  local function selectSound(key)
    Addon.db[setting] = key
    Addon.PlaySoundKey(key)
  end
  local modern = select(2, pcall(CreateFrame, "DropdownButton", name, parent,
    "WowStyle1DropdownTemplate"))
  if type(modern) == "table" and modern.SetupMenu then
    modern:SetWidth(230)
    modern:SetupMenu(function(_, rootDescription)
      for _, entry in ipairs(soundEntries()) do
        rootDescription:CreateRadio(entry.name,
          function() return Addon.db[setting] == entry.key end,
          function() selectSound(entry.key) end)
      end
    end)
    return modern, function()
      local sound = Addon.SOUNDS[Addon.db[setting]] or Addon.SOUNDS.auction
      if modern.SetText then modern:SetText(sound.name) end
      if modern.GenerateMenu then modern:GenerateMenu() end
    end
  end

  local legacy = CreateFrame("Frame", name .. "Legacy", parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(legacy, 220)
  UIDropDownMenu_Initialize(legacy, function(_, level)
    for _, entry in ipairs(soundEntries()) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = entry.name
      info.value = entry.key
      info.checked = Addon.db[setting] == entry.key
      info.func = function()
        selectSound(entry.key)
        UIDropDownMenu_SetText(legacy, Addon.SOUNDS[entry.key].name)
      end
      UIDropDownMenu_AddButton(info, level or 1)
    end
  end)
  return legacy, function()
    local sound = Addon.SOUNDS[Addon.db[setting]] or Addon.SOUNDS.auction
    UIDropDownMenu_SetText(legacy, sound.name)
  end
end

local function makeRow(parent, labelText, opts)
  opts = opts or {}
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
    local enabled = not self.enabledIf or self.enabledIf(Addon.db)
    self:SetAlpha(enabled and 1 or DISABLED_ALPHA)
    widget:EnableMouse(enabled)
    if widget.EnableMouseWheel then widget:EnableMouseWheel(enabled) end
  end
  table.insert(controls, row)
  return row
end

local function checkboxRow(parent, labelText, get, set, opts)
  local row = makeRow(parent, labelText, opts)
  local box = CreateFrame("CheckButton", nil, row)
  box:SetSize(24, 24)
  box:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
  box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  box:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
  end)
  function row:Refresh()
    box:SetChecked(get() and true or false)
    self:ApplyEnabled(box)
  end
  row.widget = box
  box.Refresh = function() row:Refresh() end
  return row, box
end

local function sliderRow(parent, labelText, min, max, step, get, set, opts)
  opts = opts or {}
  local row = makeRow(parent, labelText, opts)
  local slider = CreateFrame("Slider", nil, row)
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(row.layout.control - 44, 18)
  slider:SetPoint("LEFT", row, "LEFT", row.layout.label + 2, 0)
  slider:SetMinMaxValues(min, max)
  slider:SetValueStep(step)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(0.3, 0.3, 0.32, 1)
  track:SetHeight(4)
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
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
  slider:SetScript("OnMouseWheel", function(self, delta)
    local current = self:GetValue()
    if type(current) ~= "number" then current = get() end
    self:SetValue(current + delta * step)
  end)
  function row:Refresh()
    updating = true
    local value = get()
    slider:SetValue(value)
    valueText:SetText(math.floor(value / step + 0.5) * step .. suffix)
    updating = false
    self:ApplyEnabled(slider)
  end
  row.widget = slider
  slider.Refresh = function() row:Refresh() end
  return row, slider
end

local function checkbox(parent, key, labelText, opts)
  return checkboxRow(parent, labelText,
    function() return Addon.db[key] end,
    function(value) applySetting(key, value) end, opts)
end

local function slider(parent, key, labelText, min, max, step, opts)
  return sliderRow(parent, labelText, min, max, step,
    function() return Addon.db[key] end,
    function(value) applySetting(key, value) end, opts)
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
  row.widget = button
  return row, button
end

local function soundRow(parent, labelText, setting, frameName, opts)
  local row = makeRow(parent, labelText, opts)
  local dropdown, updateText = createDropdown(row, frameName, setting)
  dropdown:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
  function row:Refresh()
    updateText()
    self:ApplyEnabled(dropdown)
  end
  row.widget = dropdown
  return row, dropdown
end

local function noteRow(parent, text, height)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(SETTINGS_LAYOUT.label + SETTINGS_LAYOUT.control + 50, height or 40)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.text:SetPoint("TOPLEFT", 6, 0)
  row.text:SetPoint("TOPRIGHT", -6, 0)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(true)
  row.text:SetText(text)
  function row:Refresh() end
  table.insert(controls, row)
  return row
end

-- One change path for every control and for "Reset this tab": the same side effects the
-- flat panel had (dots and diamonds follow at once), then the preview and the twin
-- controls (a setting appears both in its tab and in the preview's TRY IT block).
function applySetting(key, value, quiet)
  local db = Addon.db
  if not db then return end
  if key == "enabled" then
    db.enabled = value
    Addon.ResetPowerState()
    Addon.RefreshMarks()
  elseif key == "combatOnly" then
    db.combatOnly = value
    Addon.ResetPowerState()
  elseif key == "sound" or key == "manaSound" then
    db[key] = value
    if not quiet then Addon.PlaySoundKey(value) end
  elseif key == "dots" then
    db.dots = value
    if Addon.RefreshDots then Addon.RefreshDots() end
  elseif key == "shards" then
    db.shards = value
  elseif key == "shardDiamonds" then
    db.shardDiamonds = value
    if Addon.RefreshShards then Addon.RefreshShards() end
  elseif key == "mana" then
    db.mana = value
    if Addon.ResetMana then Addon.ResetMana() end
  elseif key == "dotSize" then
    db.dotSize = clampNumber(value, 8, 24, 14)
    if Addon.RefreshDots then Addon.RefreshDots() end
    if Addon.RefreshShards then Addon.RefreshShards() end -- the diamonds size from dotSize too
  elseif key == "dotOffset" then
    db.dotOffset = clampNumber(value, -80, 30, 2)
    if Addon.RefreshDots then Addon.RefreshDots() end
  elseif key == "shardOffset" then
    db.shardOffset = clampNumber(value, -80, 30, 2)
    if Addon.RefreshShards then Addon.RefreshShards() end
  elseif key == "manaPercent" then
    db.manaPercent = value
    db.manaLevels[Addon.manaClass] = value -- this class's level only
    if Addon.ResetMana then Addon.ResetMana() end
  end
  if not quiet then
    refreshControls()
    updateLivePreview()
  end
end

local function defaultFor(key)
  if key == "manaPercent" then
    return Addon.DefaultManaPercent and Addon.DefaultManaPercent() or 100
  end
  return Addon.defaults and Addon.defaults[key]
end

---------------------------------------------------------------------------
-- Live preview: a mock enemy health bar with the dots and diamonds the live
-- HUD draws (Dots.lua / Shards.lua layout, sizes and clamps), over fixed data.
---------------------------------------------------------------------------

function updateLivePreview()
  local scene = previewScene
  if not scene or not Addon.db then return end
  scene.updates = (scene.updates or 0) + 1
  local db = Addon.db
  local size = clampNumber(db.dotSize, 8, 24, 14)
  local dotOffset = clampNumber(db.dotOffset, -80, 30, 2)
  local shardOffset = clampNumber(db.shardOffset, -80, 30, 2)
  local points = math.floor(tonumber(previewState.points) or MAX_POINTS)
  if points < 0 then points = 0 elseif points > MAX_POINTS then points = MAX_POINTS end

  local style
  if BIT.Style and type(BIT.Style.Resolve) == "function" then
    local ok, resolved = pcall(BIT.Style.Resolve, "ResourceDing")
    if ok and type(resolved) == "table" then style = resolved end
  end

  local showDots = db.enabled and db.dots
  scene.dotsRow:SetShown(showDots)
  scene.dotsRow:ClearAllPoints()
  scene.dotsRow:SetPoint("TOP", scene.healthBar, "BOTTOM", 0, -dotOffset)
  local gap = math.max(2, math.floor(size / 4))
  scene.dotsRow:SetSize(MAX_POINTS * size + (MAX_POINTS - 1) * gap, size)
  for i = 1, MAX_POINTS do
    local dot = scene.dots[i]
    if not dot then
      dot = Addon.MakeCircleDot(scene.dotsRow, size)
      scene.dots[i] = dot
    end
    dot:SetShown(showDots)
    if dot.overlay then dot.overlay:SetShown(showDots) end
    if showDots then
      dot:SetSize(size, size)
      dot:ClearAllPoints()
      dot:SetPoint("LEFT", scene.dotsRow, "LEFT", (i - 1) * (size + gap), 0)
      Addon.LayoutCircleChrome(dot)
      dot:SetMinMaxValues(i - 1, i)
      dot:SetValue(points)
      if dot.overlay then
        dot.overlay:SetMinMaxValues(MAX_POINTS - 1, MAX_POINTS)
        dot.overlay:SetValue(points)
      end
      Addon.PaintCircleDot(dot, style, i, MAX_POINTS, points >= MAX_POINTS)
    end
  end

  local showDiamonds = db.enabled and db.shardDiamonds and points > 0
  scene.shardsRow:SetShown(showDiamonds)
  scene.shardsRow:ClearAllPoints()
  scene.shardsRow:SetPoint("TOP", scene.healthBar, "BOTTOM", 0, -shardOffset)
  scene.shardsRow:SetSize(math.max(2, points * (size - 2) + 2), size)
  for i = 1, MAX_POINTS do
    local diamond = scene.diamonds[i]
    if showDiamonds and i <= points then
      if not diamond then
        diamond = scene.shardsRow:CreateTexture(nil, "ARTWORK")
        diamond:SetTexture(DIAMOND)
        scene.diamonds[i] = diamond
      end
      diamond:SetSize(size, size)
      diamond:ClearAllPoints()
      diamond:SetPoint("LEFT", scene.shardsRow, "LEFT", (i - 1) * (size - 2), 0)
      diamond:Show()
    elseif diamond then
      diamond:Hide()
    end
  end

  local caption = points .. " of " .. MAX_POINTS .. " combo points"
  if points >= MAX_POINTS then caption = caption .. " (full)" end
  if db.enabled and db.shardDiamonds then caption = caption .. "  |  " .. points .. " soul shards" end
  scene.caption:SetText(caption)
end

local function buildLivePreview(pane)
  local title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -12)
  title:SetText("Live preview")
  local titleRule = pane:CreateTexture(nil, "ARTWORK")
  titleRule:SetColorTexture(0.28, 0.28, 0.3, 1)
  titleRule:SetHeight(1)
  titleRule:SetPoint("TOPLEFT", 8, -34)
  titleRule:SetPoint("TOPRIGHT", -8, -34)

  local scene = CreateFrame("Frame", nil, pane, "BackdropTemplate")
  scene:SetSize(PANE_WIDTH - 24, 180)
  scene:SetPoint("TOP", pane, "TOP", 0, -44)
  setBackdrop(scene, 0.02, 1)
  local ground = scene:CreateTexture(nil, "BACKGROUND", nil, -8)
  ground:SetPoint("TOPLEFT", 1, -1)
  ground:SetPoint("BOTTOMRIGHT", -1, 1)
  ground:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
  ground:SetTexCoord(0, 0.26, 0, 0.18)
  ground:SetVertexColor(0.75, 0.8, 0.75)

  local name = scene:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  name:SetPoint("TOP", scene, "TOP", 0, -8)
  name:SetText("Murloc Raider")
  name:SetTextColor(1, 0.2, 0.2)

  local healthBar = CreateFrame("StatusBar", nil, scene)
  healthBar:SetSize(200, 20)
  healthBar:SetPoint("TOP", scene, "TOP", 0, -46)
  healthBar:SetMinMaxValues(0, 100)
  healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  healthBar:SetStatusBarColor(0.1, 0.8, 0.1)
  healthBar:SetValue(62)
  local healthBack = healthBar:CreateTexture(nil, "BACKGROUND")
  healthBack:SetAllPoints()
  healthBack:SetColorTexture(0.25, 0.08, 0.08, 1)
  local healthPercent = healthBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  healthPercent:SetPoint("LEFT", healthBar, "LEFT", 3, 0)
  healthPercent:SetText("62%")
  local healthValue = healthBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  healthValue:SetPoint("RIGHT", healthBar, "RIGHT", -3, 0)
  healthValue:SetText("88")

  scene.healthBar = healthBar
  scene.dotsRow = CreateFrame("Frame", nil, scene)
  scene.shardsRow = CreateFrame("Frame", nil, scene)
  scene.dots, scene.diamonds = {}, {}
  scene.caption = scene:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  scene.caption:SetPoint("BOTTOM", scene, "BOTTOM", 0, 6)
  scene.caption:SetWidth(PANE_WIDTH - 40)
  scene.caption:SetJustifyH("CENTER")
  previewScene = scene

  local tryIt = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tryIt:SetPoint("TOPLEFT", scene, "BOTTOMLEFT", 0, -14)
  tryIt:SetText("TRY IT")
  tryIt:SetTextColor(0.85, 0.7, 0.3)
  local tryRule = pane:CreateTexture(nil, "ARTWORK")
  tryRule:SetColorTexture(0.28, 0.28, 0.3, 1)
  tryRule:SetHeight(1)
  tryRule:SetPoint("LEFT", tryIt, "RIGHT", 8, 0)
  tryRule:SetPoint("RIGHT", pane, "RIGHT", -12, 0)

  local points = sliderRow(pane, "Combo points", 0, MAX_POINTS, 1,
    function() return previewState.points end,
    function(value) previewState.points = value; updateLivePreview() end,
    { layout = PREVIEW_LAYOUT, tooltip = "How many of the mock target's five points are lit. "
        .. "The Soul Shard diamonds show the same number." })
  points:SetPoint("TOPLEFT", tryIt, "BOTTOMLEFT", -6, -6)
  local size = sliderRow(pane, "Size", 8, 24, 1,
    function() return Addon.db.dotSize end,
    function(value) applySetting("dotSize", value) end,
    { layout = PREVIEW_LAYOUT, tooltip = "Dot and diamond size, the same setting as the Dots tab." })
  size:SetPoint("TOPLEFT", points, "BOTTOMLEFT", 0, 0)
  local offset = sliderRow(pane, "Offset", -80, 30, 1,
    function() return Addon.db.dotOffset end,
    function(value) applySetting("dotOffset", value) end,
    { layout = PREVIEW_LAYOUT, tooltip = "The dots' offset from the health bar, the same setting as the Dots tab." })
  offset:SetPoint("TOPLEFT", size, "BOTTOMLEFT", 0, 0)
  local diamonds = checkboxRow(pane, "Shard diamonds",
    function() return Addon.db.shardDiamonds end,
    function(value) applySetting("shardDiamonds", value) end,
    { layout = PREVIEW_LAYOUT, tooltip = "Purple diamonds under the target, the same setting as the Shards tab." })
  diamonds:SetPoint("TOPLEFT", offset, "BOTTOMLEFT", 0, 0)

  local hint = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 12, 8)
  hint:SetWidth(PANE_WIDTH - 24)
  hint:SetJustifyH("LEFT")
  hint:SetText("Hear a single cue when your class finisher resource reaches maximum. "
    .. "The preview is a silent sample drawn with the live dots and diamonds, not your target.")
  updateLivePreview()
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function selectTab(tab)
  activeTab = tab
  for _, other in ipairs(tabs) do
    local selected = other == tab
    other.content:SetShown(selected)
    other.button.text:SetTextColor(selected and 1 or 0.6, selected and 0.82 or 0.6, selected and 0 or 0.6)
    other.button.underline:SetShown(selected)
  end
end

-- A tab whose methods add rows top to bottom and remember the setting keys, for "Reset this tab".
local function addTab(name)
  local tab = { keys = {}, widgets = {}, y = 0 }
  tab.content = CreateFrame("Frame", nil, settingsArea)
  tab.content:SetPoint("TOPLEFT", settingsArea, "TOPLEFT", 8, -40)
  tab.content:SetPoint("BOTTOMRIGHT", settingsArea, "BOTTOMRIGHT", -8, 40)
  tab.content:Hide()

  local button = CreateFrame("Button", nil, settingsArea)
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
    button:SetPoint("TOPLEFT", settingsArea, "TOPLEFT", 8, -8)
  end
  button:SetScript("OnClick", function() selectTab(tab) end)
  tab.button = button

  local function place(row, key)
    row:SetPoint("TOPLEFT", tab.content, "TOPLEFT", 0, -tab.y)
    tab.y = tab.y + (type(row.GetHeight) == "function" and row:GetHeight() or ROW_HEIGHT)
    if type(key) == "string" then
      table.insert(tab.keys, key)
      if row.widget then tab.widgets[key] = row.widget end
    end
    return row
  end

  function tab:checkbox(key, labelText, opts)
    return place(checkbox(self.content, key, labelText, opts), key)
  end
  function tab:slider(key, labelText, min, max, step, opts)
    return place(slider(self.content, key, labelText, min, max, step, opts), key)
  end
  function tab:sound(key, labelText, frameName, opts)
    return place(soundRow(self.content, labelText, key, frameName, opts), key)
  end
  function tab:action(labelText, buttonText, onClick, opts)
    return place((actionRow(self.content, labelText, buttonText, onClick, opts)))
  end
  function tab:note(text)
    return place(noteRow(self.content, text))
  end
  function tab:gap() self.y = self.y + 8 end

  table.insert(tabs, tab)
  return tab
end

local function resetTab(tab)
  if not tab then return end
  for _, key in ipairs(tab.keys) do
    applySetting(key, defaultFor(key), true)
  end
  refreshControls()
  updateLivePreview()
end

---------------------------------------------------------------------------
-- The tab's content
---------------------------------------------------------------------------

local function buildTabs()
  local widgets = {}

  local dots = addTab("Dots")
  dots:checkbox("dots", "Show the points as dots under the target's nameplate",
    { tooltip = "Combo points as circles below your target's health bar, on its nameplate." })
  dots:slider("dotSize", "Dot / diamond size", 8, 24, 1,
    { tooltip = "How big the circles and the shard diamonds are." })
  dots:slider("dotOffset", "Dot offset (- = above)", -80, 30, 1,
    { tooltip = "How far the dots sit from the health bar; negative puts them above it." })
  dots:gap()

  local shards = addTab("Shards")
  shards:checkbox("shards", "Sound when a shard comes in",
    { tooltip = "A Soul Shard arriving in your bags plays the sound (Classic warlocks)." })
  shards:checkbox("shardDiamonds", "Purple diamonds under the target",
    { tooltip = "Each Soul Shard as a purple diamond below the target's health bar." })
  shards:slider("shardOffset", "Shard offset (- = above)", -80, 30, 1,
    { tooltip = "How far the diamonds sit from the health bar; they move independently of the dots." })
  shards:gap()

  local mana = addTab("Mana")
  mana:checkbox("mana", "Sound when mana reaches the level",
    { tooltip = "One cue when your mana climbs back to the level." })
  mana:slider("manaPercent", "Mana level, %", 50, 100, 5, { suffix = "%", enabledIf = function(db) return db.mana end })
  mana:sound("manaSound", "Sound at the level", "BattleInfoTool_ResourceDingManaSoundDropdown",
    { enabledIf = function(db) return db.mana end })
  mana:gap()

  local sound = addTab("Sound")
  sound:checkbox("enabled", "Sounds, dots and diamonds",
    { tooltip = "The whole module: the finisher sound and the marks under the target." })
  sound:checkbox("combatOnly", "Only play while in combat",
    { tooltip = "A full bar out of combat stays quiet; it dings the moment combat starts." })
  sound:sound("sound", "Sound", "BattleInfoTool_ResourceDingSoundDropdown")
  sound:action("Hear it", "Test sound", Addon.PlaySelectedSound)

  local names, seen = {}, {}
  for _, resource in pairs(Addon.RESOURCES) do
    if not seen[resource.name] then
      seen[resource.name] = true
      names[#names + 1] = resource.name
    end
  end
  table.sort(names)
  sound:note("Supported: " .. table.concat(names, ", ")
    .. ". Classes without one of these get no finisher sound.")
  sound:gap()

  for _, tab in ipairs(tabs) do
    for key, widget in pairs(tab.widgets) do widgets[key] = widget end
  end
  return widgets
end

function refreshControls()
  for _, row in ipairs(controls) do row:Refresh() end
end

-- Built into its tab of the BattleInfoTool window: the live preview on the left,
-- the settings as tabs on the right, each with "Reset this tab".
function Addon.CreateSettingsPanel(parent)
  if Addon.settingsPanel then return Addon.settingsPanel end
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetAllPoints()
  panel.name = "ResourceDing"
  Addon.settingsPanel = panel

  local resourceText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  resourceText:SetPoint("TOPLEFT", 16, -10)
  resourceText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -10)
  resourceText:SetJustifyH("LEFT")
  panel.resourceText = resourceText

  local pane = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  pane:SetPoint("TOPLEFT", 10, -36)
  pane:SetPoint("BOTTOMLEFT", 10, 10)
  pane:SetWidth(PANE_WIDTH)
  setBackdrop(pane, 0.09)

  local area = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  area:SetPoint("TOPLEFT", pane, "TOPRIGHT", 10, 0)
  area:SetPoint("BOTTOMRIGHT", -10, 10)
  setBackdrop(area, 0.09)
  panel.settingsArea = area

  local divider = area:CreateTexture(nil, "ARTWORK")
  divider:SetColorTexture(0.28, 0.28, 0.3, 1)
  divider:SetHeight(1)
  divider:SetPoint("TOPLEFT", 8, -34)
  divider:SetPoint("TOPRIGHT", -8, -34)

  buildLivePreview(pane)
  settingsArea = area
  local widgets = buildTabs()
  panel.enabled = widgets.enabled
  panel.combatOnly = widgets.combatOnly
  panel.dropdown = widgets.sound
  panel.dots = widgets.dots
  panel.dotSize = widgets.dotSize
  panel.dotOffset = widgets.dotOffset
  panel.shards = widgets.shards
  panel.shardDiamonds = widgets.shardDiamonds
  panel.shardOffset = widgets.shardOffset
  panel.mana = widgets.mana
  panel.manaPercent = widgets.manaPercent
  panel.manaDropdown = widgets.manaSound
  panel.tabs = tabs

  panel.resetButton = pushButton(area, "Reset this tab", 120, function() resetTab(activeTab) end)
  panel.resetButton:SetPoint("BOTTOMRIGHT", -10, 10)

  panel.refresh = function()
    if not Addon.db then return end
    local resource, current, maximum = Addon.GetResourceState()
    if resource and maximum > 0 and current == nil then
      -- The game is keeping the count to itself just now: Forever, in combat.
      resourceText:SetText(string.format("Detected: %s (count hidden by the game)", resource.name))
    elseif resource and maximum > 0 then
      resourceText:SetText(string.format("Detected: %s (%d / %d)", resource.name, current, maximum))
    elseif resource then
      resourceText:SetText("Detected: " .. resource.name .. " (inactive for this spec/form)")
    else
      resourceText:SetText("No finisher resource for this class")
    end
    refreshControls()
    updateLivePreview()
  end

  -- The settings framework drives a canvas panel through these; without OnRefresh
  -- the panel keeps whatever it showed when it was built, so the detected resource
  -- and the checkboxes go stale as soon as the player changes spec.
  panel.OnRefresh = panel.refresh
  panel.OnCommit = function() end
  panel.OnDefault = function()
    if Addon.RestoreDefaults then Addon.RestoreDefaults() end
    panel.refresh()
  end
  panel:SetScript("OnShow", panel.refresh)

  selectTab(tabs[1])
  panel.refresh()
  return panel
end

function Addon.OpenSettings() BIT.OpenSettings("ResourceDing") end

-- BIT-only settings sample: fixed dots, silent, independent of target, gear and
-- sound. This file is port-generated, but the port is fail-closed on the secret-
-- GUID latch (rd_replay_secret_guid_fix refuses upstream without it), so the seam
-- is edited directly here; a future port unblock must carry it into the recipe.
local PREVIEW_DOT_SIZE = 14
local PREVIEW_GAP = 4
local PREVIEW_X = 118
local PREVIEW_WIDTH = 560
local PREVIEW_TITLE_X = 12
local PREVIEW_TITLE_TOP = -4
local PREVIEW_TITLE_WIDTH = 536
local PREVIEW_LABEL_X = 12
local PREVIEW_LABEL_WIDTH = 536
local PREVIEW_ROW_GAP = 10
local PREVIEW_BOTTOM = 8
-- Fixed data only: a partial row and a full row. Plain numbers by construction, so the
-- shared DotColor path paints them with no game reads and no audio.
local PREVIEW_ROWS = {
  { label = "3 of 5", count = 3, total = 5 },
  { label = "5 of 5 (full)", count = 5, total = 5 },
}

-- Measured caption height: the native wrapped height when the client offers it,
-- else one honest line at the applied font size. Pure: no game reads.
local function previewTextHeight(fs, style)
  if fs ~= nil and type(fs.GetStringHeight) == "function" then
    local ok, h = pcall(fs.GetStringHeight, fs)
    if ok and type(h) == "number" and h > 0 then return h end
  end
  if style ~= nil and type(style.fontSize) == "number" then return style.fontSize end
  return 12
end

local function previewFixWidth(fs, width)
  if fs == nil then return end
  if type(fs.SetWidth) == "function" then fs:SetWidth(width) end
  if type(fs.SetWordWrap) == "function" then fs:SetWordWrap(true) end
  if type(fs.SetJustifyH) == "function" then fs:SetJustifyH("LEFT") end
end

-- Honest bounds: the title reserves its actual wrapped height, each row's label
-- reserves its own, the circles paint below their caption (never under it), and the
-- scene/scroll height grows while the settings window stays put. Dots keep their
-- fixed 14px size and 1px chrome edges inside the scene at every font size.
local function layoutResourceDingPreview(scene, style)
  if scene == nil or scene.title == nil or scene.rows == nil then return end
  local y = PREVIEW_TITLE_TOP
  scene.title:ClearAllPoints()
  scene.title:SetPoint("TOPLEFT", PREVIEW_TITLE_X, y)
  y = y - previewTextHeight(scene.title, style) - 8
  for r, row in ipairs(scene.rows) do
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", PREVIEW_LABEL_X, y)
    local dotsTop = y - previewTextHeight(row.label, style) - 4
    for i, dot in ipairs(row.dots) do
      dot:ClearAllPoints()
      dot:SetPoint("TOPLEFT", scene, "TOPLEFT",
        PREVIEW_X + (i - 1) * (PREVIEW_DOT_SIZE + PREVIEW_GAP), dotsTop)
    end
    y = dotsTop - PREVIEW_DOT_SIZE - 2 - PREVIEW_ROW_GAP
  end
  local needed = -y + PREVIEW_BOTTOM
  if needed < 1 then needed = 1 end
  scene:SetSize(PREVIEW_WIDTH, needed)
end

local function buildResourceDingPreview(parent)
  local scene = CreateFrame("Frame", nil, parent)
  scene:SetSize(PREVIEW_WIDTH, 96)
  scene.title = scene:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  previewFixWidth(scene.title, PREVIEW_TITLE_WIDTH)
  scene.title:SetPoint("TOPLEFT", PREVIEW_TITLE_X, PREVIEW_TITLE_TOP)
  scene.title:SetText("ResourceDing sample (silent, not your target)")
  scene.rows = {}
  for r, spec in ipairs(PREVIEW_ROWS) do
    local label = scene:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewFixWidth(label, PREVIEW_LABEL_WIDTH)
    label:SetPoint("TOPLEFT", PREVIEW_LABEL_X, -30 - (r - 1) * 30)
    label:SetText(spec.label)
    local row = { label = label, dots = {} }
    for i = 1, spec.total do
      -- The same native circles as the live HUD (Dots.lua), fixed values, never the target.
      local dot = Addon.MakeCircleDot(scene, PREVIEW_DOT_SIZE)
      dot:SetPoint("TOPLEFT", scene, "TOPLEFT", PREVIEW_X + (i - 1) * (PREVIEW_DOT_SIZE + PREVIEW_GAP), -32 - (r - 1) * 30)
      dot:SetMinMaxValues(i - 1, i)
      dot:SetValue(spec.count)
      if dot.overlay then
        dot.overlay:SetMinMaxValues(spec.total - 1, spec.total)
        dot.overlay:SetValue(spec.count)
      end
      row.dots[i] = dot
    end
    scene.rows[r] = row
  end
  return scene
end

local function renderResourceDingPreview(scene, style)
  -- Shared palette only; silent, no game reads, no saved writes. Geometry reflows
  -- honestly with the font (captions measured, scene grown); colours never move it.
  BIT.Style.ApplyText(scene.title, style, "text")
  for r, row in ipairs(scene.rows) do
    local spec = PREVIEW_ROWS[r]
    BIT.Style.ApplyText(row.label, style, "text")
    local full = spec.count >= spec.total
    for i, dot in ipairs(row.dots) do
      dot:SetMinMaxValues(i - 1, i)
      dot:SetValue(spec.count)
      if dot.overlay then
        dot.overlay:SetMinMaxValues(spec.total - 1, spec.total)
        dot.overlay:SetValue(spec.count)
      end
      Addon.PaintCircleDot(dot, style, i, spec.total, full)
    end
  end
  layoutResourceDingPreview(scene, style)
end

BIT.RegisterTab("ResourceDing", {
  buildPreview = buildResourceDingPreview,
  previewRender = renderResourceDingPreview,
  capabilities = { roles = Addon.DotStyleRoles or { "text" }, shapes = false,
    geometry = false, border = false, font = true, scale = false, opacity = true },
  title = "ResourceDing",
  summary = "A sound when your combo points are full, and the points as dots under the target; for "
    .. "casters a sound when mana climbs to a level, and for warlocks one on each Soul Shard.",
  width = 760, height = 470,
  build = function(parent) Addon.CreateSettingsPanel(parent) end,
})
BIT.tabWords.ding = "ResourceDing"
