-- BattleInfoTool module Range: a red X over the target while it is out of range, a green
-- checkmark while it is in range.
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
--
-- In range means: one of the spells the range is measured by reaches the target. By default
-- those are the class's main attacks (below); the settings take a spell of the player's own
-- instead. C_Spell.IsSpellInRange answers true, false, or nil when it cannot say (a spell not
-- known, a friendly target for a harmful spell); it is not one of the calls the client keeps
-- secret in combat. Where it is anyway, or every spell answers nil, nothing is shown.
--
-- The icon sits above the target's nameplate, parented to it so it moves and scales with it
-- (the DoTInfo module parents its nameplate widgets the same way on this client). Without a nameplate (nameplates off, the target off
-- screen), it sits beside the target frame, or nowhere if the settings say so.
--
-- The action bar already turns a button's key binding red while the target is out of that
-- action's range; with dimIcons on (the default) the button's icon also goes grey and dim.

local _, BIT = ...
local M = BIT.Module("Range")

local ICON = {
  ["in"] = "Interface\\RaidFrame\\ReadyCheck-Ready",
  out = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}
local UPDATE_INTERVAL = 0.1

local DEFAULTS = {
  showIn = true,      -- the green checkmark
  showOut = true,     -- the red X
  besideFrame = true, -- without a nameplate: beside the target frame
  size = 26,
  offset = 22,        -- above the nameplate's health bar: over the row of debuff icons there
  spell = "",         -- a spell name or id to measure by; empty: the class's main attacks
  dimIcons = true,    -- action bar icons grey and dim while the target is out of their range
}

-- The class's main attacks, by first-rank spell id (every one of them is in Forever's spellbook
-- of that class). Asked by name, so the client answers for the rank the player knows.
-- None of them may be an ability that only changes the next swing (Heroic Strike, Cleave, Raptor
-- Strike, Maul all carry that flag): a warrior 30 yards from the target was told Heroic Strike was in
-- range, while Rend, as close a reach, answered no. The other three were not tried in game; the flag
-- keeps them out.
local CLASS_SPELLS = {
  WARRIOR = { 772, 1715, 7386, 355, 100 }, -- Rend, Hamstring, Sunder Armor, Taunt; Charge while it can be used
  PALADIN = { 679, 20271 },       -- Holy Strike, Judgement
  HUNTER = { 75, 3044, 2974, 1495 }, -- Auto Shot, Arcane Shot; Wing Clip, Mongoose Bite inside Auto Shot's minimum range
  ROGUE = { 1752 },               -- Sinister Strike
  PRIEST = { 585, 589 },          -- Smite, Shadow Word: Pain
  SHAMAN = { 403, 8042 },         -- Lightning Bolt, Earth Shock
  MAGE = { 133, 116 },            -- Fireball, Frostbolt
  WARLOCK = { 686, 172 },         -- Shadow Bolt, Corruption
  DRUID = { 5176, 8921 },         -- Wrath, Moonfire
}
-- A druid in Cat Form (1) measures by Claw, in Bear or Dire Bear Form (5, 8) by Growl and Bash.
local DRUID_FORM_SPELLS = { [1] = { 1082 }, [5] = { 6795, 5211 }, [8] = { 6795, 5211 } }
-- Spells that count only while they can be used: Charge, out of combat in Battle Stance.
local WHEN_USABLE = { [100] = true }

local settings

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) or false end

-- A plain answer of a function, or nil: an error or a secret is "cannot say".
local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or isSecret(v) then return nil end
  return v
end

local function spellName(id)
  local name = ask(C_Spell and C_Spell.GetSpellName, id)
  if type(name) == "string" then return name end
  local info = ask(C_Spell and C_Spell.GetSpellInfo, id)
  if type(info) == "table" and type(info.name) == "string" then return info.name end
  return nil
end

-- The class's spell ids for now (a druid's by form).
local function classSpellIds()
  local _, class = UnitClass("player")
  local ids = CLASS_SPELLS[class or ""] or {}
  if class == "DRUID" then
    local form = ask(GetShapeshiftFormID)
    ids = DRUID_FORM_SPELLS[form or 0] or ids
  end
  return ids
end

-- The spells the range is measured by now: { name, id, whenUsable }.
local function measures()
  local custom = settings and settings.spell or ""
  if type(custom) ~= "string" then custom = "" end
  custom = custom:match("^%s*(.-)%s*$") or ""
  if custom ~= "" then
    local id = tonumber(custom)
    return { { name = id and (spellName(id) or custom) or custom, id = id } }
  end
  local list = {}
  for _, id in ipairs(classSpellIds()) do
    local name = spellName(id)
    if name then list[#list + 1] = { name = name, id = id, whenUsable = WHEN_USABLE[id] } end
  end
  return list
end

-- Their names.
function M.Spells()
  local names = {}
  for _, spell in ipairs(measures()) do names[#names + 1] = spell.name end
  return names
end

-- Can the spell be used now? Only a plain yes is a yes.
-- Charge also needs the player out of combat and the spell off cooldown: the game's own text says
-- "Cannot be used in combat", and what IsSpellUsable answers in combat or on cooldown was never read.
-- A cooldown of a second and a half or less is the global one and does not count.
local function usable(spell)
  if ask(UnitAffectingCombat, "player") == true then return false end
  if spell.id then
    local cd = ask(C_Spell and C_Spell.GetSpellCooldown, spell.id)
    local start, duration
    if type(cd) == "table" then start, duration = cd.startTime, cd.duration
    else start, duration = ask(GetSpellCooldown, spell.id) end
    if type(duration) == "number" and not isSecret(duration) and type(start) == "number" and not isSecret(start)
      and start > 0 and duration > 1.5 then
      return false
    end
  end
  local v = ask(C_Spell and C_Spell.IsSpellUsable, spell.id or spell.name)
  if v == nil and type(IsUsableSpell) == "function" then v = ask(IsUsableSpell, spell.name) end
  return v == true or v == 1
end

-- What the client says of one spell and the target: true, false or nil.
local function spellInRange(name)
  local inRange = ask(C_Spell and C_Spell.IsSpellInRange, name, "target")
  if inRange == nil and type(IsSpellInRange) == "function" then
    local v = ask(IsSpellInRange, name, "target") -- 1, 0 or nil on older clients
    if v == 1 or v == true then inRange = true elseif v == 0 or v == false then inRange = false end
  end
  return inRange
end

-- "in", "out" or nil (no target to measure, or no spell could say).
function M.Check()
  if not ask(UnitExists, "target") then return nil end
  if ask(UnitIsDeadOrGhost, "target") == true then return nil end
  -- a friendly target: the harmful spells cannot measure it; a secret answer is taken as hostile
  if ask(UnitCanAttack, "player", "target") == false then return nil end
  local sawOut = false
  for _, spell in ipairs(measures()) do
    if not spell.whenUsable or usable(spell) then
      local inRange = spellInRange(spell.name)
      if inRange == true then return "in" end
      if inRange == false then sawOut = true end
    end
  end
  return sawOut and "out" or nil
end

-- /bit rangecheck: what the client answers for each spell the class could be measured by, so a
-- wrong mark can be traced to the spell that gave it. Also asked: the next-swing abilities left
-- out, the other druid forms' spells, and Attack (6603), which every class has from level 1 and
-- which would measure melee for all of them if the game answered it honestly.
local CHECKED_TOO = { WARRIOR = { 78, 845 }, HUNTER = { 2973 }, DRUID = { 1082, 6795, 5211, 6807 } }
local CHECKED_FOR_ALL = { 6603 }
function M.Report()
  local say = BIT.Say
  local _, class = UnitClass("player")
  local ids, seen = {}, {}
  for _, list in ipairs({ classSpellIds(), CLASS_SPELLS[class or ""] or {}, CHECKED_TOO[class or ""] or {}, CHECKED_FOR_ALL }) do
    for _, id in ipairs(list) do
      if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
  end
  local measured = {}
  for _, spell in ipairs(measures()) do if spell.id then measured[spell.id] = true end end
  say(("range check, %s, target %s: the mark says %s"):format(tostring(class),
    tostring(ask(UnitName, "target")), tostring(M.Check())))
  for _, id in ipairs(ids) do
    local name = spellName(id)
    local info = ask(C_Spell and C_Spell.GetSpellInfo, id)
    local minR = type(info) == "table" and info.minRange or nil
    local maxR = type(info) == "table" and info.maxRange or nil
    local known = ask(IsPlayerSpell, id)
    if known == nil then known = ask(IsSpellKnown, id) end
    say(("  %d %s: known %s, range %s-%s, in range by name %s, by id %s, old call %s, usable %s%s"):format(
      id, tostring(name), tostring(known), tostring(minR), tostring(maxR),
      tostring(name and ask(C_Spell and C_Spell.IsSpellInRange, name, "target")),
      tostring(ask(C_Spell and C_Spell.IsSpellInRange, id, "target")),
      tostring(name and type(IsSpellInRange) == "function" and ask(IsSpellInRange, name, "target")),
      tostring(usable({ id = id, name = name or "" })), measured[id] and " (measured)" or ""))
  end
end
BIT.RegisterCommand("rangecheck", function() M.Report() end)

---------------------------------------------------------------------------------------------
-- The icon
---------------------------------------------------------------------------------------------

local icon, driver

-- The target's nameplate, if there is one the addon may use.
local function targetPlate()
  local plate = ask(C_NamePlate and C_NamePlate.GetNamePlateForUnit, "target")
  if type(plate) ~= "table" then return nil end
  if type(plate.IsForbidden) == "function" and plate:IsForbidden() then return nil end
  return plate
end

local function place(plate)
  icon:ClearAllPoints()
  if plate then
    local unitFrame = type(plate.UnitFrame) == "table" and plate.UnitFrame or nil
    local bar = unitFrame and (unitFrame.healthBar or (type(unitFrame.HealthBarsContainer) == "table"
      and unitFrame.HealthBarsContainer.healthBar)) or nil
    if type(bar) ~= "table" then bar = nil end
    icon:SetParent(plate)
    icon:SetPoint("BOTTOM", bar or plate, "TOP", 0, settings.offset)
  else
    local frame = _G.TargetFrame
    if not (settings.besideFrame and type(frame) == "table") then return false end
    icon:SetParent(UIParent)
    icon:SetPoint("LEFT", frame, "RIGHT", 2, 8)
  end
  icon:SetFrameStrata("HIGH")
  return true
end

local function update()
  if not icon then return end
  local state = M.Check()
  local want = (state == "in" and settings.showIn) or (state == "out" and settings.showOut)
  if not want then icon:Hide() return end
  if not place(targetPlate()) then icon:Hide() return end
  icon:SetSize(settings.size, settings.size)
  icon.texture:SetTexture(ICON[state])
  icon:Show()
  M.shown = state
end
M.Update = update

local function start()
  icon = CreateFrame("Frame", nil, UIParent)
  icon:Hide()
  icon.texture = icon:CreateTexture(nil, "OVERLAY")
  icon.texture:SetAllPoints()

  driver = CreateFrame("Frame")
  local since = 0
  driver:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < UPDATE_INTERVAL then return end
    since = 0
    update()
  end)
  driver:RegisterEvent("PLAYER_TARGET_CHANGED")
  driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  driver:SetScript("OnEvent", function(_, event, unit)
    -- the plate the icon sits on is being handed to another unit: never leave the icon on it. Other
    -- plates come and go without concern.
    if event == "NAME_PLATE_UNIT_REMOVED" and icon:GetParent() ~= UIParent
      and ask(C_NamePlate and C_NamePlate.GetNamePlateForUnit, unit) == icon:GetParent() then
      icon:Hide()
      icon:SetParent(UIParent)
      return -- update() would put it back while the client still gives the target this plate
    end
    -- the OnUpdate runs only while there is a target
    driver:SetShown(ask(UnitExists, "target") == true)
    update()
  end)
  driver:SetShown(ask(UnitExists, "target") == true)
end

---------------------------------------------------------------------------------------------
-- Action bar icons out of range
---------------------------------------------------------------------------------------------

-- Blizzard's action bar tells each button, in ActionButton_UpdateRangeIndicator (the pet bar
-- shares it), whether the target is in its action's range, and turns the key binding red when it
-- is not. The icon is coloured by the button's UpdateUsable: white, blue without the mana, grey when
-- it cannot be used. Out of range the icon is shown grey and at DIM of that colour; back in range
-- the colour comes back. UpdateUsable is hooked on each button too, as it resets the colour while
-- the target may still be out of range.
local DIM = 0.6
local seen = {}   -- every action button the range update has reached
local dimmed = {} -- the ones dimmed now

local function dimIcon(button)
  local icon = button.icon
  if type(icon) ~= "table" or type(button.action) ~= "number" then return end
  -- Usability colors: C_ActionBar.IsUsableAction on newer clients, the classic
  -- global IsUsableAction where it does not exist (Forever). Without either,
  -- fall back to plain white: range dimming below still applies.
  local usable, noMana
  if C_ActionBar and type(C_ActionBar.IsUsableAction) == "function" then
    local ok, u, m = pcall(C_ActionBar.IsUsableAction, button.action)
    if ok and not isSecret(u) and not isSecret(m) then usable, noMana = u, m end
  elseif type(IsUsableAction) == "function" then
    local ok, u, m = pcall(IsUsableAction, button.action)
    if ok and not isSecret(u) and not isSecret(m) then usable, noMana = u, m end
  end
  local r, g, b = 1, 1, 1
  if usable == false then
    if noMana then r, g, b = 0.5, 0.5, 1 else r, g, b = 0.4, 0.4, 0.4 end
  end
  if settings.dimIcons and button.bitOutOfRange then
    icon:SetDesaturated(true)
    icon:SetVertexColor(r * DIM, g * DIM, b * DIM)
    dimmed[button] = true
  elseif dimmed[button] then
    dimmed[button] = nil
    -- An action locked by a level link stays grey, as Blizzard shows it.
    local locked = C_LevelLink and C_LevelLink.IsActionLocked and ask(C_LevelLink.IsActionLocked, button.action)
    icon:SetDesaturated(locked == true)
    icon:SetVertexColor(r, g, b)
  end
end

local function startDimming()
  -- The range indicator hook needs Blizzard's per-button call; usability colors
  -- resolve per API inside dimIcon (C_ActionBar where present, classic global
  -- IsUsableAction otherwise), so a missing usability API never blocks dimming.
  if type(ActionButton_UpdateRangeIndicator) ~= "function" then
    return
  end
  hooksecurefunc("ActionButton_UpdateRangeIndicator", function(button, checksRange, inRange)
    if type(button) ~= "table" or isSecret(checksRange) or isSecret(inRange) then return end
    -- Normalize: Blizzard passes booleans, but 1/0 must read the same (0 is truthy in Lua).
    checksRange = (checksRange == true or checksRange == 1)
    inRange = (inRange == true or inRange == 1)
    button.bitOutOfRange = (checksRange and not inRange) and true or false
    if not seen[button] then
      seen[button] = true
      if type(button.UpdateUsable) == "function" then hooksecurefunc(button, "UpdateUsable", dimIcon) end
    end
    dimIcon(button)
  end)
end

-- After the setting changes: dim or restore every button now.
function M.RefreshDimming()
  for button in pairs(seen) do dimIcon(button) end
end

---------------------------------------------------------------------------------------------
-- Start, and the settings tab
---------------------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name ~= BIT.name then return end
  self:UnregisterAllEvents()
  if not BIT.ShouldRun("Range") then return end
  -- 0.1.0 saved its default height, 2 above the bar, among the target's debuff icons: that one
  -- moves up; a height the player chose is kept. Looked at before the defaults fill the table.
  local saved = BIT.DB().modules.Range
  local oldDefault = type(saved) == "table" and saved.version == nil and saved.offset == 2
  settings = BIT.Settings("Range", DEFAULTS)
  if oldDefault then settings.offset = DEFAULTS.offset end
  settings.version = 2
  M.settings = settings
  start()
  startDimming()
end)

-- A settings-only sample. These are fictitious frames, not live nameplates or
-- TargetFrame, and no measurement/runtime is started (also available while OFF).
local function buildRangePreview(parent)
  local scene = CreateFrame("Frame", nil, parent)
  scene:SetSize(560, 180)
  scene.title = scene:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  scene.title:SetPoint("TOPLEFT", 12, -4)
  scene.title:SetText("Range sample (not your target)")
  scene.cases = {}
  for i, kind in ipairs({ "nameplate", "targetFrame" }) do
    local sample = { kind = kind }
    local y = i == 1 and -50 or -120
    sample.frame = CreateFrame("Frame", nil, scene)
    sample.frame:SetSize(180, 20)
    sample.frame:SetPoint("TOPLEFT", 12, y)
    sample.health = CreateFrame("StatusBar", nil, sample.frame)
    sample.health:SetAllPoints(sample.frame)
    sample.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    sample.health:SetStatusBarColor(0.15, 0.25, 0.35, 1)
    sample.health:SetMinMaxValues(0, 100)
    sample.health:SetValue(i == 1 and 72 or 46)
    sample.icon = scene:CreateTexture(nil, "OVERLAY")
    sample.icon:SetTexture(i == 1 and ICON["in"] or ICON.out)
    sample.icon:SetSize(26, 26)
    if i == 1 then
      sample.icon:SetPoint("BOTTOM", sample.frame, "TOP", 0, 4)
    else
      sample.icon:SetPoint("LEFT", sample.frame, "RIGHT", 2, 8)
    end
    sample.label = scene:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sample.label:SetPoint("TOPLEFT", 240, y)
    sample.label:SetText(i == 1 and "In range - above nameplate" or "Out of range - beside target frame")
    scene.cases[i] = sample
  end
  return scene
end

local function renderRangePreview(scene, style)
  -- Allocate the painted marker bounds, not just the mock frame. Native WoW Y
  -- is positive upwards; large nameplate markers need headroom above the bar.
  local size = 26 * style.scale
  local titleHeight, labelHeight = style.fontSize * 3 + 8, style.fontSize * 4 + 8
  scene.title:ClearAllPoints()
  scene.title:SetPoint("TOPLEFT", scene, "TOPLEFT", 12, -4)
  scene.title:SetPoint("TOPRIGHT", scene, "TOPRIGHT", -12, -4)
  scene.title:SetHeight(titleHeight)
  scene.title:SetJustifyH("LEFT")
  BIT.Style.ApplyText(scene.title, style, "text")
  local cursor = 4 + titleHeight + 12
  for i, sample in ipairs(scene.cases) do
    local clusterHeight = i == 1 and size + 24 or math.max(size, 20)
    local barOffset = i == 1 and size + 4 or (clusterHeight - 20) / 2
    sample.frame:ClearAllPoints()
    sample.frame:SetPoint("TOPLEFT", scene, "TOPLEFT", 12, -(cursor + barOffset))
    sample.icon:ClearAllPoints()
    if i == 1 then
      -- The in-range icon is centered above a fixed 180px mock bar. Once the
      -- icon outgrows the bar (size > 180 at large scale), a centered anchor
      -- would paint left of the scene (native frames do not clip), so shift
      -- it right exactly enough to keep its left edge on the mock bar.
      sample.icon:SetPoint("BOTTOM", sample.frame, "TOP", math.max(0, (size - 180) / 2), 4)
    else
      sample.icon:SetPoint("LEFT", sample.frame, "RIGHT", 2, 0)
    end
    sample.icon:SetSize(size, size)
    sample.icon:SetAlpha(style.opacity)
    local labelY = -(cursor + clusterHeight + 8)
    sample.label:ClearAllPoints()
    sample.label:SetPoint("TOPLEFT", scene, "TOPLEFT", 12, labelY)
    sample.label:SetPoint("TOPRIGHT", scene, "TOPRIGHT", -12, labelY)
    sample.label:SetHeight(labelHeight)
    sample.label:SetJustifyH("LEFT")
    BIT.Style.ApplyText(sample.label, style, i == 1 and "good" or "bad")
    BIT.Style.ApplyBar(sample.health, style, "muted")
    cursor = cursor + clusterHeight + 8 + labelHeight + 16
  end
  scene:SetHeight(cursor + 4)
end

---------------------------------------------------------------------------------------------
-- The settings tab: a live preview on the left, the settings in tabs on the right
---------------------------------------------------------------------------------------------

local WHITE = "Interface\\Buttons\\WHITE8X8"
local WINDOW_WIDTH, WINDOW_HEIGHT = 760, 470
local PREVIEW_TOP = 40 -- the presets' row above the two columns
local PREVIEW_WIDTH = 290
local ROW_HEIGHT = 26
local SETTINGS_LAYOUT = { label = 186, control = 170 }
local PREVIEW_LAYOUT = { label = 180, control = 40 }
local DISABLED_ALPHA = 0.35

-- One click each: the two marks and the dimming. The size, the height and the measuring spell
-- are the player's own and stay as they are.
local PRESETS = {
  { id = "minimal", label = "Minimal", values = { showIn = false, showOut = true, dimIcons = false } },
  { id = "classic", label = "Classic", values = { showIn = true, showOut = true, dimIcons = true } },
  { id = "bare", label = "Bare", values = { showIn = false, showOut = false, dimIcons = false } },
}

local window -- the tab's content frame: the preview and the settings are built into it
local controls = {} -- every settings and preview row, refreshed after each change
local tabs, activeTab = {}, nil
local preview = { out = false } -- the TRY IT switch: the preview's own state, never a setting

local function setBackdrop(frame, shade, alpha)
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  frame:SetBackdropColor(shade, shade, shade, alpha or 1)
  frame:SetBackdropBorderColor(0.28, 0.28, 0.3, 1)
end

local function refreshControls()
  for _, control in ipairs(controls) do control:Refresh() end
end

-- The preview draws what update() draws on the target: the mark above the health bar at the set
-- height and size, and the action bar button grey and dim while the simulated target is out of
-- range. The sample always wears the real mark, as the game wears it over the target: showIn and
-- showOut hide only the live mark (update), never this one, so the icon is here to look at and
-- tune whatever those settings hide on the target. The line under the sample names the mark and
-- says when its setting keeps it off the real target.
local function updatePreview()
  if not window or not window.previewIcon then return end
  local state = preview.out and "out" or "in"
  local on = (state == "in" and settings.showIn) or (state == "out" and settings.showOut)
  local mark = window.previewIcon
  mark:ClearAllPoints()
  mark:SetPoint("BOTTOM", window.previewBar, "TOP", 0, settings.offset)
  mark:SetSize(settings.size, settings.size)
  mark.texture:SetTexture(ICON[state])
  mark:Show()
  window.previewState:SetText((state == "in" and "In range - the green checkmark" or "Out of range - the red X")
    .. (on and "" or " (off on your target)"))
  local dim = settings.dimIcons and state == "out"
  window.previewButtonIcon:SetDesaturated(dim)
  local tone = dim and 0.6 or 1
  window.previewButtonIcon:SetVertexColor(tone, tone, tone)
  window.previewButtonNote:SetText(dim and "Grey and dim out of range"
    or (state == "out" and "Left alone - the dimming is off" or "Its own colours in range"))
end

local function changed()
  -- The rows follow the settings again after a preset or a reset (a stale ticked box over a
  -- hidden mark reads as a broken preview).
  refreshControls()
  updatePreview()
  -- Slider drags must not re-probe the spell list each step: the poll (0.1s)
  -- re-runs update() and the dimming follows the next range indicator call.
  M.RefreshDimming()
  if window and window.spellsLine then
    local names = table.concat(M.Spells(), ", ")
    window.spellsLine:SetText("Measured by: " .. (names ~= "" and names or "no spell of this class"))
  end
end

local function set(key) return function(v) settings[key] = v; changed() end end
local function get(key) return function() return settings[key] end end

---------------------------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------------------------

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
  row.label:SetWordWrap(false)
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
    local enabled = not self.enabledIf or self.enabledIf(settings)
    self:SetAlpha(enabled and 1 or DISABLED_ALPHA)
    widget:EnableMouse(enabled)
    if widget.EnableMouseWheel then widget:EnableMouseWheel(enabled) end
  end
  table.insert(controls, row)
  return row
end

-- get/set work on the settings or on the preview's own state.
local function checkboxRow(parent, labelText, get, set, opts)
  opts = opts or {}
  local row = makeRow(parent, labelText, opts)
  local box = CreateFrame("CheckButton", nil, row)
  box:SetSize(24, 24)
  box:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
  box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  function row:Refresh()
    box:SetChecked(get() and true or false)
    self:ApplyEnabled(box)
  end
  return row
end

local function checkbox(parent, key, labelText, opts)
  return checkboxRow(parent, labelText, get(key), set(key), opts)
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
  return sliderRow(parent, labelText, min, max, step, get(key), set(key), opts)
end

-- A one-line text setting: a spell name or id.
local function editRow(parent, key, labelText, opts)
  opts = opts or {}
  local row = makeRow(parent, labelText, opts)
  local getText, setText = get(key), set(key)
  local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
  box:SetSize(row.layout.control, 20)
  box:SetPoint("LEFT", row, "LEFT", row.layout.label + 2, 0)
  box:SetAutoFocus(false)
  box:SetScript("OnEnterPressed", function(self) setText(self:GetText() or ""); self:ClearFocus() end)
  box:SetScript("OnEditFocusLost", function(self) setText(self:GetText() or "") end)
  box:SetScript("OnEscapePressed", function(self) self:SetText(getText() or ""); self:ClearFocus() end)
  function row:Refresh()
    box:SetText(getText() or "")
    self:ApplyEnabled(box)
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

---------------------------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------------------------

local function selectTab(tab)
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
  function tab:edit(key, ...) return place(editRow(self.content, key, ...), key) end
  function tab:gap() self.y = self.y + 8 end

  table.insert(tabs, tab)
  return tab
end

local function resetTab(tab)
  for _, key in ipairs(tab.keys) do settings[key] = DEFAULTS[key] end
  changed()
end

local function applyPreset(preset)
  for key, value in pairs(preset.values) do settings[key] = value end
  changed()
  BIT.Say(preset.label .. " preset applied.")
end

---------------------------------------------------------------------------------------------
-- The live preview: a mock nameplate and a mock action bar button
---------------------------------------------------------------------------------------------

local function buildLivePreview(pane)
  local SIDE = 12
  local CARD_WIDTH = PREVIEW_WIDTH - 2 * SIDE -- 266

  local title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", SIDE, -12)
  title:SetText("Live preview")
  local titleRule = pane:CreateTexture(nil, "ARTWORK")
  titleRule:SetColorTexture(0.28, 0.28, 0.3, 1)
  titleRule:SetHeight(1)
  titleRule:SetPoint("TOPLEFT", 8, -34)
  titleRule:SetPoint("TOPRIGHT", -8, -34)

  -- A mock nameplate of an enemy: the mark goes above its health bar, where the real one goes.
  local scene = CreateFrame("Frame", nil, pane, "BackdropTemplate")
  scene:SetSize(CARD_WIDTH, 184)
  scene:SetPoint("TOP", pane, "TOP", 0, -44)
  setBackdrop(scene, 0.07)
  local ground = scene:CreateTexture(nil, "BACKGROUND")
  ground:SetPoint("TOPLEFT", 1, -1)
  ground:SetPoint("BOTTOMRIGHT", -1, 1)
  ground:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
  ground:SetTexCoord(0, 0.26, 0, 0.18) -- about 1:1 texels on the card
  ground:SetVertexColor(0.75, 0.8, 0.75)

  local plate = CreateFrame("Frame", nil, scene)
  plate:SetSize(190, 36)
  plate:SetPoint("BOTTOM", scene, "BOTTOM", 0, 12)
  local bar = CreateFrame("StatusBar", nil, plate)
  bar:SetSize(133, 13)
  bar:SetPoint("BOTTOMLEFT", plate, "BOTTOMLEFT", 12, 6)
  bar:SetMinMaxValues(0, 100)
  bar:SetValue(72)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(0.85, 0.1, 0.1) -- hostile
  local back = plate:CreateTexture(nil, "BACKGROUND")
  back:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 3)
  back:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 6, -6)
  back:SetColorTexture(0.1, 0.02, 0.02, 1)
  local name = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 5)
  name:SetText("Murloc Raider")
  name:SetTextColor(1, 0.13, 0.13) -- hostile
  local level = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  level:SetPoint("LEFT", bar, "RIGHT", 6, 0)
  level:SetText("12")
  level:SetTextColor(1, 0.82, 0)

  -- The mark, painted above the mock nameplate as the real one is above the real one.
  local mark = CreateFrame("Frame", nil, scene)
  mark:SetFrameLevel(plate:GetFrameLevel() + 10)
  mark.texture = mark:CreateTexture(nil, "OVERLAY")
  mark.texture:SetAllPoints()
  mark.texture:SetTexture(ICON["in"])
  window.previewBar, window.previewIcon = bar, mark

  window.previewState = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  window.previewState:SetPoint("TOPLEFT", scene, "BOTTOMLEFT", 0, -6)
  window.previewState:SetPoint("TOPRIGHT", scene, "BOTTOMRIGHT", 0, -6)
  window.previewState:SetJustifyH("LEFT")

  local function header(text, anchor, gap)
    local label = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
    label:SetText(text)
    label:SetTextColor(0.85, 0.7, 0.3)
    local rule = pane:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(0.28, 0.28, 0.3, 1)
    rule:SetHeight(1)
    rule:SetPoint("LEFT", label, "RIGHT", 8, 0)
    rule:SetPoint("RIGHT", pane, "RIGHT", -SIDE, 0)
    return label
  end

  -- Try it: the preview's own state, not a setting.
  local tryIt = header("TRY IT", window.previewState, 12)
  local toggle = checkboxRow(pane, "Simulate: out of range",
    function() return preview.out end,
    function(v) preview.out = v; changed() end,
    { layout = PREVIEW_LAYOUT,
      tooltip = "The preview only: the red X while it is checked, the green checkmark while it is not." })
  toggle:SetPoint("TOPLEFT", tryIt, "BOTTOMLEFT", -6, -4)

  -- The action bar button the module dims.
  local barCard = CreateFrame("Frame", nil, pane, "BackdropTemplate")
  barCard:SetSize(CARD_WIDTH, 56)
  barCard:SetPoint("TOPLEFT", toggle, "BOTTOMLEFT", -6, -10)
  setBackdrop(barCard, 0.07)
  local button = CreateFrame("Frame", nil, barCard, "BackdropTemplate")
  button:SetSize(36, 36)
  button:SetPoint("LEFT", barCard, "LEFT", 12, 0)
  button:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
  button:SetBackdropBorderColor(0, 0, 0, 1)
  local buttonIcon = button:CreateTexture(nil, "BACKGROUND")
  buttonIcon:SetPoint("TOPLEFT", 1, -1)
  buttonIcon:SetPoint("BOTTOMRIGHT", -1, 1)
  buttonIcon:SetTexture("Interface\\Icons\\Spell_Fire_Immolation")
  buttonIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local hotkey = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
  hotkey:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
  hotkey:SetText("1")
  window.previewButtonIcon = buttonIcon
  window.previewButtonNote = barCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  window.previewButtonNote:SetPoint("LEFT", button, "RIGHT", 10, 0)
  window.previewButtonNote:SetPoint("RIGHT", barCard, "RIGHT", -8, 0)
  window.previewButtonNote:SetJustifyH("LEFT")

  local hint = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", SIDE, 12)
  hint:SetWidth(CARD_WIDTH)
  hint:SetJustifyH("LEFT")
  hint:SetText("A sample only: the mark and the dimming happen on your own target and bars.")
end

local function buildTabs()
  local iconTab = addTab("Icon")
  iconTab:checkbox("showIn", "Checkmark in range",
    { tooltip = "The green checkmark over your target while one of the measuring spells reaches it." })
  iconTab:checkbox("showOut", "Red X out of range",
    { tooltip = "The red X over your target while none of the measuring spells reaches it." })
  iconTab:checkbox("besideFrame", "Beside the target frame",
    { tooltip = "Without a nameplate (nameplates off, the target off screen) the mark sits beside "
      .. "the target frame instead." })
  iconTab:gap()
  local shown = function(s) return s.showIn or s.showOut end
  iconTab:slider("size", "Size", 12, 64, 2,
    { enabledIf = shown, tooltip = "The mark's size in pixels." })
  iconTab:slider("offset", "Height above the bar", -20, 80, 1,
    { enabledIf = shown, tooltip = "Pixels above the nameplate's health bar: over the row of "
      .. "debuff icons there." })

  local barTab = addTab("Action bar")
  barTab:checkbox("dimIcons", "Grey out action bar icons",
    { tooltip = "While the target is out of an action's range its icon goes grey and dim, on top "
      .. "of the game's red key binding." })

  local spellTab = addTab("Spell")
  spellTab:edit("spell", "Measure by this spell",
    { tooltip = "A spell name or id of your own to measure the range by; empty: your class's "
      .. "main attacks." })
  spellTab:gap()
  window.spellsLine = spellTab.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  window.spellsLine:SetPoint("TOPLEFT", spellTab.content, "TOPLEFT", 0, -spellTab.y)
end

-- The presets, the preview and the settings in the tab's content frame: the presets
-- right-aligned above the two columns, the live preview on the left, the tabs on the right.
local function buildContent(top, anchor)
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
  buildLivePreview(pane)

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
    refreshControls()
    updatePreview()
  end)
  selectTab(tabs[1])
  changed()
end

BIT.RegisterTab("Range", {
  buildPreview = buildRangePreview,
  previewRender = renderRangePreview,
  capabilities = { roles = { "good", "bad", "muted", "text" }, shapes = false,
    geometry = false, border = false, font = true, scale = true, opacity = true },
  title = "Range",
  summary = "A red X over your target while it is out of range, a green checkmark while it is in range.",
  width = WINDOW_WIDTH, height = WINDOW_HEIGHT,
  build = function(parent)
    window = parent
    local anchor = CreateFrame("Frame", nil, parent)
    anchor:SetSize(1, 22)
    anchor:SetPoint("TOPRIGHT", -10, -8)
    buildContent(PREVIEW_TOP, anchor)
  end,
})
BIT.tabWords.range = "Range"

-- For the tests.
M._icon = function() return icon end
M._driver = function() return driver end
M.CLASS_SPELLS = CLASS_SPELLS
