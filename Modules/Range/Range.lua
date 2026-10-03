-- BattleInfoTool module Range: a red X over the target while it is out of range, a green
-- checkmark while it is in range.
-- Copyright (c) 2026 Ironship. MIT licence, see LICENSE.
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
  custom = custom:match("^%s*(.-)%s*$")
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
  local ok, usable, noMana = pcall(C_ActionBar.IsUsableAction, button.action)
  if not ok or isSecret(usable) or isSecret(noMana) then return end
  local r, g, b = 1, 1, 1
  if not usable then
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
  if type(ActionButton_UpdateRangeIndicator) ~= "function" or not (C_ActionBar and C_ActionBar.IsUsableAction) then
    return
  end
  hooksecurefunc("ActionButton_UpdateRangeIndicator", function(button, checksRange, inRange)
    if type(button) ~= "table" or isSecret(checksRange) or isSecret(inRange) then return end
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

BIT.RegisterTab("Range", {
  buildPreview = buildRangePreview,
  previewRender = renderRangePreview,
  capabilities = { roles = { "good", "bad", "muted", "text" }, shapes = false,
    geometry = false, border = false, font = true, scale = true, opacity = true },
  title = "Range",
  summary = "A red X over your target while it is out of range, a green checkmark while it is in range.",
  width = 640, height = 330,
  build = function(parent)
    local UI = BIT.UI
    local rows = {}
    local function changed()
      for _, r in ipairs(rows) do if r.Refresh then r:Refresh() end end
      parent.spellsLine:SetText("Measured by: " .. (table.concat(M.Spells(), ", ") ~= "" and table.concat(M.Spells(), ", ")
        or "no spell of this class"))
      update()
      M.RefreshDimming()
    end
    local function set(key) return function(v) settings[key] = v; changed() end end
    local function get(key) return function() return settings[key] end end

    local y = -10
    local function add(row, height)
      row:SetPoint("TOPLEFT", 12, y)
      rows[#rows + 1] = row
      y = y - (height or 30)
      return row
    end
    add(UI.Check(parent, "Green checkmark while the target is in range", get("showIn"), set("showIn")))
    add(UI.Check(parent, "Red X while the target is out of range", get("showOut"), set("showOut")))
    add(UI.Check(parent, "Beside the target frame when the target has no nameplate", get("besideFrame"), set("besideFrame")))
    add(UI.Check(parent, "Grey out action bar icons while the target is out of their range", get("dimIcons"), set("dimIcons")))
    add(UI.Slider(parent, "Size", 12, 64, 2, get("size"), set("size")), 46)
    add(UI.Slider(parent, "Height above the nameplate's health bar", -20, 80, 1, get("offset"), set("offset")), 50)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 12, y)
    label:SetText("Measure by this spell (a name or id; empty: your class's main attacks)")
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(220, 20)
    box:SetPoint("TOPLEFT", 18, y - 20)
    box:SetAutoFocus(false)
    box:SetText(settings.spell or "")
    box:SetScript("OnEnterPressed", function(self) settings.spell = self:GetText() or ""; self:ClearFocus(); changed() end)
    box:SetScript("OnEditFocusLost", function(self) settings.spell = self:GetText() or ""; changed() end)
    box:SetScript("OnEscapePressed", function(self) self:SetText(settings.spell or ""); self:ClearFocus() end)
    parent.spellsLine = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    parent.spellsLine:SetPoint("TOPLEFT", 12, y - 48)

    -- what the two icons look like at this size
    local sample = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sample:SetPoint("TOPRIGHT", -80, -14)
    sample:SetText("Looks like:")
    local inIcon = parent:CreateTexture(nil, "OVERLAY")
    inIcon:SetTexture(ICON["in"])
    inIcon:SetPoint("TOPRIGHT", -44, -8)
    local outIcon = parent:CreateTexture(nil, "OVERLAY")
    outIcon:SetTexture(ICON.out)
    outIcon:SetPoint("TOPRIGHT", -10, -8)
    rows[#rows + 1] = { Refresh = function()
      inIcon:SetSize(settings.size, settings.size)
      outIcon:SetSize(settings.size, settings.size)
    end }
    changed()
  end,
})
BIT.tabWords.range = "Range"

-- For the tests.
M._icon = function() return icon end
M._driver = function() return driver end
M.CLASS_SPELLS = CLASS_SPELLS
