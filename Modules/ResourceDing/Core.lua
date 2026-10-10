-- UsefulPlatesAndTooltips ResourceDing: originally ported from ResourceDing/Core.lua at 540b462.
-- Frozen in BIT: edit this module directly; tools/port.py protects its local gameplay fixes.
local addonName, BIT = ...
-- Inside UsefulPlatesAndTooltips its own namespace; loaded on its own, the addon's table as before.
local Addon = BIT.Module and BIT.Module("ResourceDing") or BIT
if not BIT.Module then _G.ResourceDing = Addon end

local function powerType(name, fallback)
  return Enum and Enum.PowerType and Enum.PowerType[name] or fallback
end

-- Retail, Classic Era, Season of Discovery and WoW Forever run the same addon.
-- What differs is which of these resources the game actually has.
--
-- Forever is the awkward one. It is a Classic Era game -- vanilla content, the
-- Classic Era API -- built on the Retail client, and that client answers
-- WOW_PROJECT_ID the way Retail does. Asked the usual way, the addon would
-- think it was on Retail, offer Chi and Holy Power to classes that do not
-- exist there, and register a specialisation event the game may not have,
-- which is an error at load.
--
-- The one answer that client gives that is not Retail's is its version: Retail
-- is 12.x, Classic Era 1.15.x, Forever 1.60.x. Not the manifest: measured on
-- 2026-09-19 with /rding probe, the Forever client loads the _Mainline
-- manifest, not a _Camelot one, so the manifest says what Retail's says. That
-- is why ResourceDing_Mainline.toc lists 16001 beside 120100 -- the same
-- convention AtlasLoot ships for that game -- and why the flavour is read
-- from GetBuildInfo's version string, the first value it returns.
local function clientIsForever()
  if type(GetBuildInfo) ~= "function" then return false end
  local ok, version = pcall(GetBuildInfo)
  if not ok or type(version) ~= "string" then return false end
  local major, minor = version:match("^(%d+)%.(%d+)")
  return tonumber(major) == 1 and (tonumber(minor) or 0) >= 60
end

local function isClassic()
  if clientIsForever() then return true end
  if type(WOW_PROJECT_ID) ~= "number" or type(WOW_PROJECT_MAINLINE) ~= "number" then
    return false
  end
  return WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE
end
Addon.IsClassic = isClassic

Addon.RESOURCES = {
  ROGUE = { name = "Combo Points", power = powerType("ComboPoints", 4), comboPoints = true },
  DRUID = { name = "Combo Points", power = powerType("ComboPoints", 4), comboPoints = true },
  MONK = { name = "Chi", power = powerType("Chi", 12), spec = 269 }, -- Windwalker
  PALADIN = { name = "Holy Power", power = powerType("HolyPower", 9) },
  WARLOCK = { name = "Soul Shards", power = powerType("SoulShards", 7) },
  MAGE = { name = "Arcane Charges", power = powerType("ArcaneCharges", 16), spec = 62 }, -- Arcane
  EVOKER = { name = "Essence", power = powerType("Essence", 19) },
}

-- Vanilla has combo points and nothing else. Chi, Holy Power, Arcane Charges
-- and the Soul Shard bar were all added by later expansions, and Monk and
-- Evoker do not exist there at all. Leaving them listed would have the settings
-- panel announce a resource the player's class cannot have in that game.
if isClassic() then
  for class in pairs(Addon.RESOURCES) do
    if class ~= "ROGUE" and class ~= "DRUID" then Addon.RESOURCES[class] = nil end
  end
end

Addon.SOUNDS = {
  auction = { name = "Auction House", id = SOUNDKIT and SOUNDKIT.AUCTION_WINDOW_OPEN or 5274 },
  ready = { name = "Ready Check", id = SOUNDKIT and SOUNDKIT.READY_CHECK or 8960 },
  quest = { name = "Quest Complete", id = SOUNDKIT and (SOUNDKIT.UI_AUTO_QUEST_COMPLETE or SOUNDKIT.UI_QUEST_COMPLETE) or 23404 },
  level = { name = "Level Up", id = SOUNDKIT and SOUNDKIT.LEVEL_UP or 888 },
  bell = { name = "UI Bell", id = SOUNDKIT and SOUNDKIT.UI_ORDERHALL_TALENT_READY_TOAST or 73280 },
  coins = { name = "Loot Coins", id = SOUNDKIT and (SOUNDKIT.LOOT_WINDOW_COIN_SOUND or SOUNDKIT.LOOT_MONEY_COINS) or 120 },
  warning = { name = "Raid Warning", id = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959 },
}
Addon.SOUND_ORDER = { "auction", "ready", "quest", "level", "bell", "coins", "warning" }

-- A sound added in a later expansion does not exist on the Classic client, and
-- PlaySound on an id it does not know fails quietly. Offering it would give the
-- player a choice that appears to do nothing, so a sound this client cannot
-- name is dropped from the list instead of shipped broken. The numeric
-- fallbacks above are only for a client with no SOUNDKIT table at all.
if SOUNDKIT then
  -- RD-6: the quest/coins sounds were renamed on newer clients; accept either
  -- key so the Classic stubs (old keys) and Forever (new keys) both keep them.
  local KEYS = {
    auction = { "AUCTION_WINDOW_OPEN" }, ready = { "READY_CHECK" },
    quest = { "UI_AUTO_QUEST_COMPLETE", "UI_QUEST_COMPLETE" },
    level = { "LEVEL_UP" },
    bell = { "UI_ORDERHALL_TALENT_READY_TOAST" },
    coins = { "LOOT_WINDOW_COIN_SOUND", "LOOT_MONEY_COINS" }, warning = { "RAID_WARNING" },
  }
  local kept = {}
  for _, key in ipairs(Addon.SOUND_ORDER) do
    local has = false
    for _, k in ipairs(KEYS[key] or {}) do if SOUNDKIT[k] then has = true break end end
    if has then kept[#kept + 1] = key else Addon.SOUNDS[key] = nil end
  end
  if #kept > 0 then Addon.SOUND_ORDER = kept end
end

local defaults = {
  enabled = true,
  combatOnly = true,
  sound = "auction",
  dots = true,     -- combo points as dots under the target's nameplate (Dots.lua)
  dotSize = 14,
  dotOffset = 2,   -- vertical offset from the health bar (negative = above)
  shardOffset = 2, -- the warlock diamonds' own offset: dots and diamonds move independently
  shards = true,         -- a warlock's Soul Shard coming in plays the sound (Shards.lua)
  shardDiamonds = true,  -- and they show as purple diamonds under the target's nameplate
  mana = true,           -- a sound when mana climbs to manaPercent (Mana.lua); manaPercent is
  manaSound = "ready",   -- set per class when the settings load: 80 for a warlock, 100 for others
}
Addon.defaults = defaults

local function initializeDatabase()
  if type(UsefulPlatesAndTooltips_ResourceDingDB) ~= "table" then UsefulPlatesAndTooltips_ResourceDingDB = {} end
  for key, value in pairs(defaults) do
    local saved = UsefulPlatesAndTooltips_ResourceDingDB[key]
    if type(saved) ~= type(value) or (type(value) == "number"
      and (saved ~= saved or saved == math.huge or saved == -math.huge)) then
      UsefulPlatesAndTooltips_ResourceDingDB[key] = value
    end
  end
  if not Addon.SOUNDS[UsefulPlatesAndTooltips_ResourceDingDB.sound] then UsefulPlatesAndTooltips_ResourceDingDB.sound = defaults.sound end
  if type(UsefulPlatesAndTooltips_ResourceDingDB.dotOffset) ~= "number" then UsefulPlatesAndTooltips_ResourceDingDB.dotOffset = defaults.dotOffset
  elseif UsefulPlatesAndTooltips_ResourceDingDB.dotOffset < -80 then UsefulPlatesAndTooltips_ResourceDingDB.dotOffset = -80
  elseif UsefulPlatesAndTooltips_ResourceDingDB.dotOffset > 30 then UsefulPlatesAndTooltips_ResourceDingDB.dotOffset = 30 end
  if type(UsefulPlatesAndTooltips_ResourceDingDB.shardOffset) ~= "number" then UsefulPlatesAndTooltips_ResourceDingDB.shardOffset = defaults.shardOffset
  elseif UsefulPlatesAndTooltips_ResourceDingDB.shardOffset < -80 then UsefulPlatesAndTooltips_ResourceDingDB.shardOffset = -80
  elseif UsefulPlatesAndTooltips_ResourceDingDB.shardOffset > 30 then UsefulPlatesAndTooltips_ResourceDingDB.shardOffset = 30 end
  local dotSize = tonumber(UsefulPlatesAndTooltips_ResourceDingDB.dotSize)
  if dotSize ~= dotSize or not dotSize or dotSize < 8 then dotSize = 8
  elseif dotSize > 24 then dotSize = 24 end
  UsefulPlatesAndTooltips_ResourceDingDB.dotSize = math.floor(dotSize + 0.5)
  Addon.db = UsefulPlatesAndTooltips_ResourceDingDB
  -- The saved table is shared by every character on the account, but the mana level is per class:
  -- each class keeps its own entry, and manaPercent is this character's copy of it.
  local _, class = UnitClass("player")
  Addon.manaClass = class or "?"
  if type(Addon.db.manaLevels) ~= "table" then Addon.db.manaLevels = {} end
  if type(Addon.db.manaLevels[Addon.manaClass]) ~= "number" then
    Addon.db.manaLevels[Addon.manaClass] = Addon.DefaultManaPercent and Addon.DefaultManaPercent() or 100
  end
  Addon.db.manaPercent = Addon.db.manaLevels[Addon.manaClass]
  if not Addon.SOUNDS[Addon.db.manaSound] then Addon.db.manaSound = Addon.SOUND_ORDER[1] end
end
if BIT.RegisterWaker then BIT.RegisterWaker("ResourceDing", initializeDatabase) end

function Addon.GetResource()
  local _, class = UnitClass("player")
  local resource = class and Addon.RESOURCES[class] or nil
  local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
  local getInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo or GetSpecializationInfo
  if resource and resource.spec and not isClassic()
      and type(getSpec) == "function" and type(getInfo) == "function" then
    local spec = getSpec()
    if not spec or getInfo(spec) ~= resource.spec then return nil end
  end
  return resource
end

-- A number the client will let this addon use, 0 for no answer, or nil for a
-- number it will not.
--
-- Clients from 12.0 on hand insecure code "secret" values for some combat
-- data: a number a secure bar can show, but that a comparison or a sum in an
-- addon raises on. WoW Forever is such a client, and its combo points live on
-- the target, so GetComboPoints answers with one during a fight -- and a
-- comparison on it inside an event handler took the whole addon down until
-- the next reload (Core.lua:150, 2026-09-19). Asked before every use, so a
-- secret reads as "unknown": not a full bar, and not an empty one either.
local function known(value)
  if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
  return type(value) == "number" and value or 0
end
Addon.KnownNumber = known

-- A secret GUID must never index a plain table: the client raises
-- "cannot be indexed with secret keys" on any touch, read or write.
local function isSecret(value)
  return type(issecretvalue) == "function" and issecretvalue(value) or false
end

-- A target GUID safe to use as a table key, or nil. Real GUIDs are strings;
-- anything else (nil, a number) cannot index the per-target latch. A secret
-- string is caught by issecretvalue where the client has it; where it does
-- not, a touch of a throwaway table raises the same error the latch would,
-- safely inside a pcall. Nil falls back to the plain latch.
local function usableGuid(value)
  if type(value) ~= "string" then return nil end
  if type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, value)
    -- Explicit: "secret and nil or value" hands a secret string straight through
    -- (true and nil or value is value) and the client raises on the first touch
    -- of the per-target latch (8241 errors). Say what is meant instead.
    if ok and secret then return nil end
    if ok then return value end
  end
  local probe = {}
  local ok = pcall(function() probe[value] = true return probe[value] end)
  if not ok then return nil end
  return value
end

-- What the game's own combo point display is showing, for the client that
-- keeps the number itself secret.
--
-- Forever draws combo points with the classic ComboFrame -- ComboPoint1 to
-- ComboPoint5 -- by secure code that is allowed to read the count (/fstack on
-- the Forever client, 2026-09-19: ComboFrame, ComboPoint5.Highlight,
-- ComboFrame.xml:62). That code cannot keep its display secret: a widget's
-- alpha is plain state. What it does is worth being exact about, from
-- Blizzard's ComboFrame_Update: once one point is earned every point frame is
-- shown, and an earned point differs from an unearned one only by its
-- Highlight -- faded in over 0.4 s for a new point, set to alpha 0 when the
-- point is gone; the whole frame hides at zero. So a point counts as lit when
-- its Highlight is up, and the frame's own visibility only says "none".
--
-- Read as defensively as the number: should a client hand back a secret here
-- too, the answer is nil -- unknown -- as before, never an error.
local function plainValue(ok, value)
  if not ok then return nil end
  if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
  return value
end

local function displayedComboPoints()
  local frame = _G.ComboFrame
  if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return nil end
  local shown = plainValue(pcall(frame.IsShown, frame))
  if shown == nil then return nil end
  if not shown then return 0 end
  -- Every point frame there is, not the first five: with a maximum of five
  -- Blizzard draws ComboPoint2 to ComboPoint6 and leaves ComboPoint1 hidden
  -- (startComboPointIndex is 2 unless the maximum is 6 or 9), which is how a
  -- count of the first five read four at a full bar on 2026-09-19. A hidden
  -- frame is not lit whatever its alpha says.
  local count = 0
  for index = 1, 12 do
    local point = _G["ComboPoint" .. index]
    local highlight = type(point) == "table" and point.Highlight
    if type(highlight) ~= "table" or type(highlight.GetAlpha) ~= "function" then break end
    local visible = plainValue(pcall(point.IsShown, point))
    local alpha = plainValue(pcall(highlight.GetAlpha, highlight))
    if visible == nil or type(alpha) ~= "number" then return nil end
    if visible and alpha > 0.5 then count = count + 1 end
  end
  return count
end
Addon.DisplayedComboPoints = displayedComboPoints

-- A target switch invalidates fading highlights until Blizzard redraws them.
-- This flag is plain addon state; it never compares or caches secret GUIDs.
local comboDisplayReady = true

-- Whether the native combo updater can repaint at all. Blizzard's
-- ComboFrame_Update runs `if (not self.maxComboPoints) then return end`
-- (classic-era ComboFrame.lua lines 65-70) and ONLY that missing maximum makes
-- the body return before touching the display. This reads the same plain
-- frame field the native body checks, before any comparison or arithmetic on
-- display values; when it cannot be read, whether the body repainted is
-- unknown. Either way the display-only sound fallback fails closed. The dots
-- never pass through here: they forward the raw target count unchanged.
local function nativeCanRepaintCombo()
  local frame = _G.ComboFrame
  if type(frame) ~= "table" then return false end
  local ok, maximum = pcall(function() return frame.maxComboPoints end)
  return ok and maximum ~= nil
end

function Addon.GetResourceState()
  local resource = Addon.GetResource()
  if not resource then return nil, 0, 0 end
  local _, class = UnitClass("player")
  if class == "DRUID" and not isClassic() and type(GetShapeshiftFormID) == "function" then
    local ok, form = pcall(GetShapeshiftFormID)
    if not ok or isSecret(form) or form ~= 1 then return resource, 0, 0, 0, 0 end
  end
  local rawCurrent = UnitPower("player", resource.power)
  local rawMaximum = UnitPowerMax("player", resource.power)
  local maximum = known(rawMaximum) or 0
  -- Classic/Forever points belong to the selected target, even when the
  -- Retail-based client advertises a five-point player bar. UnitPower can
  -- retain A's points after selecting B; a nonzero maximum does not prove
  -- that its current value belongs to B. Retail still uses player-owned power.
  if resource.comboPoints and isClassic()
      and type(GetComboPoints) == "function" then
    rawCurrent = GetComboPoints("player", "target")
    if maximum <= 0 then maximum = MAX_COMBO_POINTS or 5 end
  end
  local current = known(rawCurrent)
  -- Whichever call answered, a secret is a secret. The native combo display
  -- can supply a readable count for sounds; HUD dots receive rawCurrent from
  -- the same target-specific read instead of copying fading UI highlights.
  -- The display is trusted only after a native redraw that really repainted:
  -- when the native body early-returns (its maximum is gone) the highlights
  -- are stale for whichever target the UI last drew.
  if current == nil and resource.comboPoints and isClassic() and comboDisplayReady
      and nativeCanRepaintCombo() then
    current = displayedComboPoints()
  end
  return resource, current, maximum, rawCurrent, rawMaximum
end

-- Plays the sound of that key. Falls through to whatever sound this client does have. The filter
-- above drops any SOUNDKIT entry the client is missing, and the default is not exempt from that --
-- without a floor, a client without the auction sound would error on every full bar instead of
-- playing something else.
function Addon.PlaySoundKey(key)
  local choice = Addon.SOUNDS[key or defaults.sound]
    or Addon.SOUNDS.auction
    or select(2, next(Addon.SOUNDS))
  if not choice or not choice.id then return false end
  -- A client without the PlaySound function, or one whose sound call errors, must
  -- cost this one sound, not the event handler that asked for it.
  local ok, played = pcall(PlaySound, choice.id, "Master", true)
  return ok and played
end

function Addon.PlaySelectedSound()
  return Addon.PlaySoundKey(Addon.db and Addon.db.sound or defaults.sound)
end

function Addon.CheckPower(silent)
  local resource, current, maximum, _, rawMaximum = Addon.GetResourceState()
  if isSecret(rawMaximum) then return end
  -- Classic's combo points belong to the target, and the latch follows the
  -- target with them: tabbing away and back to a bar that is still full is
  -- not a new fill, so it must not play the sound again (RD-1). For a
  -- resource that is the player's own, the latch stays the plain one.
  -- A secret GUID must never index the table: the client raises on any touch.
  local guid
  if resource and resource.comboPoints and isClassic() and type(UnitGUID) == "function" then
    guid = usableGuid(UnitGUID("target"))
  end
  local byTarget = Addon.wasFullBy or {}
  Addon.wasFullBy = byTarget
  -- A target never latched counts as not full; the plain latch covers a
  -- player-owned resource or an absent target.
  local wasFull = Addon.wasFull
  if guid then wasFull = byTarget[guid] == true end
  if not resource or maximum <= 0 then
    Addon.wasFull = false
    if not isClassic() then Addon.powerResource, Addon.powerMaximum = nil, nil end
    if guid then byTarget[guid] = false end
    return
  end
  -- Unknown this time: the client kept the number to itself. That says
  -- nothing about full or not, so the latch is left exactly as it was.
  if current == nil then return end

  if not isClassic() then
    -- A talent/spec changing the cap can make unchanged points look full.
    -- Take a silent baseline even if its MAXPOWER event arrives later.
    if Addon.powerResource ~= resource.power or Addon.powerMaximum ~= maximum then silent = true end
    Addon.powerResource, Addon.powerMaximum = resource.power, maximum
  end
  local isFull = current >= maximum
  -- Retail's shard-gain option already announces the last shard. Its full-bar
  -- sound remains available when gain sounds are switched off.
  local shardGainSound = not isClassic() and resource.power == powerType("SoulShards", 7)
    and Addon.db.shards and Addon.CheckShards ~= nil
  if not silent and isFull and not wasFull and Addon.db.enabled and not shardGainSound then
    if not Addon.db.combatOnly or UnitAffectingCombat("player") then
      Addon.PlaySelectedSound()
    else
      -- Full, but out of combat and the player asked for combat only. The sound
      -- is skipped -- and the state is deliberately left unlatched, so the ding
      -- still happens the moment combat starts.
      --
      -- Latching here is what made a rogue's opener silent. Ambush and Cheap
      -- Shot award their combo points in the same instant the fight begins, and
      -- UnitAffectingCombat is routinely still false when the event arrives. The
      -- addon saw a full bar, said nothing because combat had not registered
      -- yet, and recorded the bar as already announced. The fight then started
      -- with the points already there and no further rise to announce.
      return
    end
  end
  Addon.wasFull = isFull
  if guid then byTarget[guid] = isFull end
end

-- The dots and diamonds follow the Enable switch as the sounds do.
function Addon.RefreshMarks()
  if Addon.RefreshDots then Addon.RefreshDots() end
  if Addon.RefreshShards then Addon.RefreshShards() end
end

function Addon.RestoreDefaults()
  for key, value in pairs(defaults) do Addon.db[key] = value end
  Addon.db.manaPercent = Addon.DefaultManaPercent and Addon.DefaultManaPercent() or 100
  Addon.db.manaLevels[Addon.manaClass] = Addon.db.manaPercent
  if Addon.ResetMana then Addon.ResetMana() end
  Addon.ResetPowerState()
end

function Addon.ResetPowerState()
  Addon.CheckPower(true)
  if Addon.ResetShards then Addon.ResetShards() end
  Addon.RefreshMarks()
  if Addon.settingsPanel and Addon.settingsPanel.refresh then Addon.settingsPanel.refresh() end
end

local events = CreateFrame("Frame")

-- Registering an event the client does not have raises an error, and this runs
-- at load, before the addon has done anything -- so one absent name would take
-- the whole thing down rather than cost it a feature. PLAYER_SPECIALIZATION_CHANGED
-- is exactly that on Classic Era, which has no specialisations at all.
local function listenFor(event, unit)
  local method = unit and events.RegisterUnitEvent or events.RegisterEvent
  return (pcall(method, events, event, unit))
end

-- When to look at the display.
--
-- The events this addon listens to are not promised on the client that needs
-- the display: combo points on the target raise no UNIT_POWER event for the
-- player there. So the display's own redraws are the trigger. ComboFrame
-- handles PLAYER_TARGET_CHANGED and the power events itself, and its OnEvent
-- calls ComboFrame_Update for every redraw that changes the count -- the
-- mirrored Forever client draws it exactly that way, so a post-hook on that
-- one function sees every such redraw once. A newly earned point's Highlight
-- is still at alpha 0 then, fading in over 0.4 s, so the same look is taken
-- again half a second later. ComboPointShineFadeIn is what Blizzard calls
-- when that fade finishes, and where the client has it as a global, it is the
-- exact moment. The frame's own OnEvent is hooked too -- a client that
-- redraws without the global function still goes through it -- but that hook
-- only asks for the half-second look, and the look is scheduled once per
-- redraw whichever hook gets there first: the same redraw reaches both hooks,
-- and doing the work of both would read the power and redraw the dots twice
-- for a single point earned. All post-hooks: none of this taints the frame,
-- and a client without the frame -- Classic Era draws its own -- has no hooks
-- and reads the number as it always did.
local HIGHLIGHT_SETTLED = 0.5

local settleScheduled = false
-- The saved table can exist before the module is running: Enable prepares it
-- for the settings page, and /reload is what starts the sounds and the dots.
local function gameplayOn()
  return not BIT.IsRunning or BIT.IsRunning("ResourceDing")
end

local function lookAtDisplay()
  Addon.looks = (Addon.looks or 0) + 1
  if not gameplayOn() then return end
  if Addon.db then Addon.CheckPower(false) end
  -- the display has the count plainly now: the dots show it too
  if Addon.RefreshDots then Addon.RefreshDots() end
end

local function lookAgainLater()
  if not Addon.db or not gameplayOn() then return end
  if settleScheduled then return end
  settleScheduled = true
  if C_Timer and C_Timer.After then
    C_Timer.After(HIGHLIGHT_SETTLED, function()
      settleScheduled = false
      lookAtDisplay()
    end)
  end
end

Addon.hooks = {}
if type(ComboFrame) == "table" and type(ComboFrame.HookScript) == "function" then
  -- The frame's own OnEvent has already drawn the display when this runs. The
  -- immediate look is the ComboFrame_Update hook's, which fires inside that
  -- same dispatch; on a client without that global, do the look here instead.
  Addon.hooks.frame = (pcall(ComboFrame.HookScript, ComboFrame, "OnEvent", function()
    if not Addon.hooks.update and nativeCanRepaintCombo() then
      comboDisplayReady = true
      lookAtDisplay()
    end
    lookAgainLater()
  end))
end
if type(hooksecurefunc) == "function" then
  if type(ComboFrame_Update) == "function" then
    hooksecurefunc("ComboFrame_Update", function()
      if nativeCanRepaintCombo() then
        comboDisplayReady = true
        lookAtDisplay()
      end
      lookAgainLater()
    end)
    Addon.hooks.update = true
  end
  if type(ComboPointShineFadeIn) == "function" then
    hooksecurefunc("ComboPointShineFadeIn", lookAtDisplay)
    Addon.hooks.shine = true
  end
end
Addon.LookAtDisplay = lookAtDisplay

listenFor("ADDON_LOADED")
listenFor("PLAYER_ENTERING_WORLD")
listenFor("PLAYER_SPECIALIZATION_CHANGED")
listenFor("UPDATE_SHAPESHIFT_FORM")
listenFor("PLAYER_TARGET_CHANGED")
listenFor("COMBO_TARGET_CHANGED")
-- Entering combat is itself worth a check: the resource may have filled a
-- moment earlier, while the sound was still being held back.
listenFor("PLAYER_REGEN_DISABLED")
listenFor("UNIT_POWER_UPDATE", "player")
listenFor("UNIT_POWER_FREQUENT", "player")
listenFor("UNIT_MAXPOWER", "player")
-- Classic's combo points change without any UNIT_POWER event, because they are
-- not the player's power there. This is what fires instead.
listenFor("UNIT_COMBO_POINTS", "player")
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= addonName then return end
    -- switched off in UsefulPlatesAndTooltips: silent
    if BIT.ShouldRun and not BIT.ShouldRun("ResourceDing") then events:UnregisterAllEvents() return end
    initializeDatabase()
    -- inside UsefulPlatesAndTooltips the settings are built into its tab when that is first shown
    if not BIT.RegisterTab and Addon.CreateSettingsPanel then Addon.CreateSettingsPanel() end
    Addon.ResetPowerState()
    -- the dots, the shards and the mana level start once the settings are loaded (Dots.lua,
    -- Shards.lua, Mana.lua): switched off, none of them takes an event
    for _, start in ipairs(Addon.starters or {}) do start() end
  elseif not Addon.db then
    return
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 and arg1 ~= "player" then
    return
  elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" or event == "UNIT_MAXPOWER" then
    C_Timer.After(0, Addon.ResetPowerState)
  else
    if event == "PLAYER_TARGET_CHANGED" or event == "COMBO_TARGET_CHANGED" then
      if isClassic() then comboDisplayReady = false end
    end
    Addon.CheckPower(false)
  end
end)

SLASH_RESOURCEDING1 = "/rding"
SLASH_RESOURCEDING2 = "/resourceding"
SlashCmdList.RESOURCEDING = function(message)
  if BIT.IsRunning and not BIT.IsRunning("ResourceDing") then BIT.SayOff("ResourceDing") return end
  local command = strlower(strtrim(tostring(message or "")))
  if command == "test" then
    Addon.PlaySelectedSound()
  elseif command == "probe" then
    -- Everything the decision rests on, as the game hands it over right now,
    -- for a client that keeps some of it secret. Typed in a fight, at the
    -- count that should have dinged.
    local function show(v)
      if type(issecretvalue) == "function" and issecretvalue(v) then return "<secret>" end
      return tostring(v)
    end
    local function call(object, method)
      if type(object) ~= "table" or type(object[method]) ~= "function" then return "-" end
      local ok, v = pcall(object[method], object)
      return ok and show(v) or ("error: " .. tostring(v))
    end
    local resource = Addon.GetResource()
    print("|cff66ccffResourceDing probe:|r resource " .. tostring(resource and resource.name)
      .. "  classic=" .. tostring(isClassic()) .. "  combat=" .. show(UnitAffectingCombat("player")))
    if resource then
      print("  UnitPower " .. show(UnitPower("player", resource.power))
        .. "  UnitPowerMax " .. show(UnitPowerMax("player", resource.power)))
    end
    if type(GetComboPoints) == "function" then
      print("  GetComboPoints " .. show(GetComboPoints("player", "target"))
        .. "  MAX_COMBO_POINTS " .. tostring(MAX_COMBO_POINTS))
    end
    print("  ComboFrame " .. type(_G.ComboFrame) .. " shown=" .. call(_G.ComboFrame, "IsShown")
      .. "  ComboFrame_Update=" .. type(ComboFrame_Update) .. "  ShineFadeIn=" .. type(ComboPointShineFadeIn))
    -- Every point frame the display can draw, the same range
    -- displayedComboPoints reads: with a maximum of five the lit ones are
    -- ComboPoint2 to ComboPoint6, and a probe of the first five would show
    -- four at a full bar.
    for i = 1, 12 do
      local point = _G["ComboPoint" .. i]
      print(string.format("  ComboPoint%d shown=%s  Highlight alpha=%s", i, call(point, "IsShown"),
        call(type(point) == "table" and point.Highlight, "GetAlpha")))
    end
    local _, current, maximum = Addon.GetResourceState()
    print("  displayed=" .. tostring(displayedComboPoints()) .. "  state " .. tostring(current) .. "/" .. tostring(maximum)
      .. "  wasFull=" .. tostring(Addon.wasFull) .. "  looks=" .. tostring(Addon.looks or 0)
      .. "  hooks frame=" .. tostring(Addon.hooks and Addon.hooks.frame) .. " update=" .. tostring(Addon.hooks and Addon.hooks.update)
      .. " shine=" .. tostring(Addon.hooks and Addon.hooks.shine))
  elseif command == "on" then
    Addon.db.enabled = true
    Addon.ResetPowerState()
    Addon.RefreshMarks()
    print("|cff66ccffResourceDing:|r enabled")
  elseif command == "off" then
    Addon.db.enabled = false
    Addon.ResetPowerState()
    Addon.RefreshMarks()
    print("|cff66ccffResourceDing:|r disabled")
  elseif Addon.OpenSettings then
    Addon.OpenSettings()
  end
end
