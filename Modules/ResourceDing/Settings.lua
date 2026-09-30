-- BattleInfoTool module ResourceDing: ported by tools/port.py from ResourceDing/Settings.lua at 540b462.
-- Change it there, or in tools/port.py; an edit made here is lost at the next port.
local _, BIT = ...
local Addon = BIT.Module("ResourceDing")

local function checkbox(parent, name, label, y, getter, setter, x)
  local control = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  control:SetPoint("TOPLEFT", x or 16, y)
  local text = control.Text or control.text or _G[name .. "Text"]
  if text then text:SetText(label) end
  control:SetChecked(getter())
  control:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
  return control
end

-- A slider with its label above and its value to the right, built from a plain Slider so it does
-- not depend on a template every client has.
local function slider(parent, label, y, min, max, getter, setter, x, step)
  local text = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT", x or 16, y)
  text:SetText(label)
  local bar = CreateFrame("Slider", nil, parent)
  bar:SetOrientation("HORIZONTAL")
  bar:SetSize(200, 16)
  bar:SetPoint("TOPLEFT", (x or 16) + 2, y - 20)
  bar:SetMinMaxValues(min, max)
  bar:SetValueStep(step or 1)
  if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
  bar:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(0.2, 0.2, 0.22, 1)
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  track:SetHeight(6)
  local value = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  value:SetPoint("LEFT", bar, "RIGHT", 10, 0)
  bar:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / (step or 1) + 0.5) * (step or 1)
    value:SetText(tostring(v))
    if bar.refreshing then return end
    setter(v)
  end)
  bar.Refresh = function()
    bar.refreshing = true
    bar:SetValue(getter())
    value:SetText(tostring(getter()))
    bar.refreshing = false
  end
  return bar
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

-- Built into its tab of the BattleInfoTool window.
function Addon.CreateSettingsPanel(parent)
  if Addon.settingsPanel then return Addon.settingsPanel end
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetAllPoints()
  panel.name = "ResourceDing"
  Addon.settingsPanel = panel
  -- The right-hand column (Soul Shards, then mana) starts at this x, from y = -102 down. A line in
  -- the left column below that must end before it, or the column's controls cover its words.
  local RIGHT = 370

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("ResourceDing")

  local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  subtitle:SetPoint("TOPLEFT", 16, -44)
  subtitle:SetPoint("TOPRIGHT", -16, -44)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetText("Hear a single cue when your class finisher resource reaches maximum.")

  local resourceText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  resourceText:SetPoint("TOPLEFT", 16, -72)
  resourceText:SetTextColor(0.35, 0.68, 1)
  panel.resourceText = resourceText

  panel.enabled = checkbox(panel, "BattleInfoTool_ResourceDingEnabledCheck", "Sounds, dots and diamonds", -102,
    function() return Addon.db.enabled end,
    function(value) Addon.db.enabled = value; Addon.ResetPowerState(); Addon.RefreshMarks() end)

  panel.combatOnly = checkbox(panel, "BattleInfoTool_ResourceDingCombatCheck", "Only play while in combat", -134,
    function() return Addon.db.combatOnly end,
    function(value) Addon.db.combatOnly = value; Addon.ResetPowerState() end)

  local soundLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  soundLabel:SetPoint("TOPLEFT", 16, -178)
  soundLabel:SetText("Sound")

  local dropdown, updateSoundText = createDropdown(panel, "BattleInfoTool_ResourceDingSoundDropdown")
  dropdown:SetPoint("TOPLEFT", 8, -196)
  panel.dropdown = dropdown
  updateSoundText()

  local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  test:SetSize(90, 26)
  test:SetPoint("TOPLEFT", 254, -203)
  test:SetText("Test sound")
  test:SetScript("OnClick", Addon.PlaySelectedSound)

  local supported = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  supported:SetPoint("TOPLEFT", 16, -252)
  supported:SetPoint("TOPRIGHT", panel, "TOPLEFT", RIGHT - 16, -252) -- wraps short of the mana column
  supported:SetJustifyH("LEFT")
  supported:SetWordWrap(true)
  -- Built from the table the addon actually uses, which Core prunes on Classic
  -- to the two classes that game has. Spelling the full Retail list out here
  -- defeated that pruning: Classic players were told about Chi, Holy Power,
  -- Soul Shards, Arcane Charges and Essence, none of which exist for them.
  local names, seen = {}, {}
  for _, resource in pairs(Addon.RESOURCES) do
    if not seen[resource.name] then
      seen[resource.name] = true
      names[#names + 1] = resource.name
    end
  end
  table.sort(names)
  supported:SetText("Supported: " .. table.concat(names, ", ")
    .. ". Classes without one of these get no finisher sound.")

  -- The dots under the target's nameplate (Dots.lua).
  panel.dots = checkbox(panel, "BattleInfoTool_ResourceDingDotsCheck", "Show the points as dots under the target's nameplate", -290,
    function() return Addon.db.dots end,
    function(value) Addon.db.dots = value; if Addon.RefreshDots then Addon.RefreshDots() end end)
  panel.dotSize = slider(panel, "Dot size", -326, 8, 24,
    function() return Addon.db.dotSize end,
    function(value)
      Addon.db.dotSize = value
      if Addon.RefreshDots then Addon.RefreshDots() end
      if Addon.RefreshShards then Addon.RefreshShards() end -- the diamonds size from dotSize too
    end)
  panel.dotOffset = slider(panel, "Distance below the health bar", -370, 0, 30,
    function() return Addon.db.dotOffset end,
    function(value)
      Addon.db.dotOffset = value
      if Addon.RefreshDots then Addon.RefreshDots() end
      if Addon.RefreshShards then Addon.RefreshShards() end -- and anchor from dotOffset
    end)

  -- Right-hand column: a warlock's Soul Shards (Shards.lua) and the mana level (Mana.lua).
  local shardsHead = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  shardsHead:SetPoint("TOPLEFT", RIGHT, -102)
  shardsHead:SetText("Soul Shards (warlock)")
  panel.shards = checkbox(panel, "BattleInfoTool_ResourceDingShardsCheck", "Sound when a shard comes in", -120,
    function() return Addon.db.shards end,
    function(value) Addon.db.shards = value end, RIGHT)
  panel.shardDiamonds = checkbox(panel, "BattleInfoTool_ResourceDingShardDiamondsCheck", "Purple diamonds under the target", -148,
    function() return Addon.db.shardDiamonds end,
    function(value) Addon.db.shardDiamonds = value; if Addon.RefreshShards then Addon.RefreshShards() end end, RIGHT)

  local manaHead = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  manaHead:SetPoint("TOPLEFT", RIGHT, -196)
  manaHead:SetText("Mana")
  panel.mana = checkbox(panel, "BattleInfoTool_ResourceDingManaCheck", "Sound when mana reaches the level", -214,
    function() return Addon.db.mana end,
    function(value) Addon.db.mana = value; if Addon.ResetMana then Addon.ResetMana() end end, RIGHT)
  panel.manaPercent = slider(panel, "Mana level, %", -248, 50, 100,
    function() return Addon.db.manaPercent end,
    function(value)
      Addon.db.manaPercent = value
      Addon.db.manaLevels[Addon.manaClass] = value -- this class's level only
      if Addon.ResetMana then Addon.ResetMana() end
    end, RIGHT, 5)
  local manaDropdown, updateManaSoundText = createDropdown(panel, "BattleInfoTool_ResourceDingManaSoundDropdown", "manaSound")
  manaDropdown:SetPoint("TOPLEFT", RIGHT - 8, -300)
  panel.manaDropdown = manaDropdown

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
    panel.enabled:SetChecked(Addon.db.enabled)
    panel.combatOnly:SetChecked(Addon.db.combatOnly)
    panel.dots:SetChecked(Addon.db.dots)
    panel.dotSize.Refresh()
    panel.dotOffset.Refresh()
    panel.shards:SetChecked(Addon.db.shards)
    panel.shardDiamonds:SetChecked(Addon.db.shardDiamonds)
    panel.mana:SetChecked(Addon.db.mana)
    panel.manaPercent.Refresh()
    updateManaSoundText()
    updateSoundText()
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

  panel.refresh()
  return panel
end

function Addon.OpenSettings() BIT.OpenSettings("ResourceDing") end

BIT.RegisterTab("ResourceDing", {
  title = "ResourceDing",
  summary = "A sound when your combo points are full, and the points as dots under the target; for "
    .. "casters a sound when mana climbs to a level, and for warlocks one on each Soul Shard.",
  width = 640, height = 410,
  build = function(parent) Addon.CreateSettingsPanel(parent) end,
})
BIT.tabWords.ding = "ResourceDing"
