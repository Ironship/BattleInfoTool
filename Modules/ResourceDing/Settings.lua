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
  panel.dotSize = slider(panel, "Dot / diamond size", -326, 8, 24,
    function() return Addon.db.dotSize end,
    function(value)
      value = tonumber(value) or 14
      if value ~= value then value = 14 end
      if value < 8 then value = 8 elseif value > 24 then value = 24 end
      Addon.db.dotSize = value
      if Addon.RefreshDots then Addon.RefreshDots() end
      if Addon.RefreshShards then Addon.RefreshShards() end -- the diamonds size from dotSize too
    end)
  panel.dotOffset = slider(panel, "Dot offset from the health bar (- = above)", -370, -80, 30,
    function() return Addon.db.dotOffset end,
    function(value)
      value = tonumber(value) or 2
      if value ~= value then value = 2 end
      if value < -80 then value = -80 elseif value > 30 then value = 30 end
      Addon.db.dotOffset = value
      if Addon.RefreshDots then Addon.RefreshDots() end
    end)
  panel.shardOffset = slider(panel, "Shard offset from the health bar (- = above)", -414, -80, 30,
    function() return Addon.db.shardOffset end,
    function(value)
      value = tonumber(value) or 2
      if value ~= value then value = 2 end
      if value < -80 then value = -80 elseif value > 30 then value = 30 end
      Addon.db.shardOffset = value
      if Addon.RefreshShards then Addon.RefreshShards() end
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
    panel.shardOffset.Refresh()
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
  width = 640, height = 460,
  build = function(parent) Addon.CreateSettingsPanel(parent) end,
})
BIT.tabWords.ding = "ResourceDing"
