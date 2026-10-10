-- UsefulPlatesAndTooltips module ResourceDing: ported by tools/port.py from ResourceDing/Mana.lua at 540b462.
-- Change it there, or in tools/port.py; an edit made here is lost at the next port.
-- A sound when mana climbs to a level: a caster drinking need not watch the bar. 100% by default,
-- 80% for a warlock, who takes the rest with Life Tap.
--
-- Only while the client shows the mana: on WoW Forever the player's power can be secret in a
-- fight, and a level that cannot be read is not guessed. A reading the client withholds also
-- forgets the last one, so mana that climbed unseen does not ding late when it shows again.

local _, BIT = ...
-- Inside UsefulPlatesAndTooltips its own namespace; loaded on its own, the addon's table as before.
local Addon = BIT.Module and BIT.Module("ResourceDing") or BIT

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local QUIET_AFTER_WORLD = 3

local below -- was mana below the level at the last reading? nil: no reading to go by
local lastMaximum -- the maximum the last reading saw; a drop here is not a climb
local quietUntil = 0

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) or false end

local function plainNumber(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or isSecret(v) or type(v) ~= "number" then return nil end
  return v
end

-- The level for a class when it has none saved: 80 for a warlock, 100 for anyone else.
function Addon.DefaultManaPercent()
  local _, class = UnitClass("player")
  return class == "WARLOCK" and 80 or 100
end

function Addon.CheckMana()
  if not (Addon.db and Addon.db.mana) then return end
  local current, maximum = plainNumber(UnitPower, "player", MANA), plainNumber(UnitPowerMax, "player", MANA)
  if current == nil or maximum == nil or maximum <= 0 then
    below, lastMaximum = nil, nil
    return
  end
  -- The sound is for mana that climbed to the level. When the maximum falls --
  -- a buff or a form ending -- the same mana crosses the threshold without a
  -- point gained; that is no climb and must not ding. The reading forgets the
  -- latch too, so a bar left at the level by the change stays quiet until it
  -- dips and climbs again.
  if lastMaximum and maximum < lastMaximum then below = nil end
  lastMaximum = maximum
  local reached = current * 100 >= maximum * Addon.db.manaPercent
  -- /rding off silences this too; the reading is still taken, so nothing sounds late after /rding on
  if below == true and reached and Addon.db.enabled and GetTime() >= quietUntil then Addon.PlaySoundKey(Addon.db.manaSound) end
  below = not reached
end

-- A new level in the settings: the next reading only takes note, it does not ding.
function Addon.ResetMana() below, lastMaximum = nil, nil end

local function start()
  local events = CreateFrame("Frame")
  for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "UPDATE_SHAPESHIFT_FORM" }) do
    pcall(events.RegisterEvent, events, event)
  end
  for _, event in ipairs({ "UNIT_POWER_UPDATE", "UNIT_MAXPOWER" }) do
    pcall(events.RegisterUnitEvent, events, event, "player")
  end
  events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end
    if event == "PLAYER_ENTERING_WORLD" then
      quietUntil = GetTime() + QUIET_AFTER_WORLD
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then Addon.ResetMana() end
    Addon.CheckMana()
  end)
  Addon.CheckMana()
end

Addon.starters = Addon.starters or {}
table.insert(Addon.starters, start)
