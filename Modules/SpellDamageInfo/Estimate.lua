-- BattleInfoTool module SpellDamageInfo: ported by tools/port.py from SpellDamageInfo/Estimate.lua at 8269edd.
-- Change it there, or in tools/port.py; an edit made here is lost at the next port.
-- SpellDamageInfo: the optional spell-power estimate (the client's own shares, Classic's rules
-- where it has none) and the button value.
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
-- Pure Lua 5.1, no game API.

local _, BIT = ...
-- Inside BattleInfoTool its own namespace; loaded on its own, the addon's table as before.
local ns = BIT and BIT.Module and BIT.Module("SpellDamageInfo") or BIT or {}

local Estimate = {}
ns.Estimate = Estimate

-- Index of each school for GetSpellBonusDamage(school).
local SCHOOL_INDEX = { holy = 2, fire = 3, nature = 4, frost = 5, shadow = 6, arcane = 7 }
Estimate.SCHOOL_INDEX = SCHOOL_INDEX

-- The spell-power bonus that applies to a school, from a table of GetSpellBonusDamage values
-- by index. Frostfire takes the higher of Frost and Fire. Physical damage (attack power) and
-- unknown schools get none.
function Estimate.DamageBonus(school, bonusByIndex)
  if not school or not bonusByIndex then return nil end
  if school == "frostfire" then
    local fire, frost = bonusByIndex[3], bonusByIndex[5]
    if fire and frost then return (fire > frost) and fire or frost end
    return fire or frost
  end
  local index = SCHOOL_INDEX[school]
  return index and bonusByIndex[index] or nil
end

-- Classic's rules, for a spell SpellCoefficients does not have.
--   direct: cast time / 3.5, cast times under 1.5 sec (instants) count as 1.5, capped at 3.5 sec
--   over time: duration / 15, capped at 1
--   both in one spell: the two are split so the over-time part gets
--   b / (a + b) of the whole, i.e. direct a*a/(a+b), over time b*b/(a+b)
-- castTime and duration are in seconds. Returns the direct and over-time coefficients (or nil).
function Estimate.Coefficients(castTime, hasDirect, dotDuration)
  local a, b
  if hasDirect then
    local ct = castTime or 0
    if ct < 1.5 then ct = 1.5 end
    if ct > 3.5 then ct = 3.5 end
    a = ct / 3.5
  end
  if dotDuration and dotDuration > 0 then
    b = dotDuration / 15
    if b > 1 then b = 1 end
  end
  if a and b then
    return a * a / (a + b), b * b / (a + b)
  end
  return a, b
end

local function copyRange(r, add)
  return { min = r.min + add, max = r.max + add, added = add }
end

local function copyPeriodic(p, add)
  return { total = p.total + add, duration = p.duration, added = add }
end

-- The client's shares for a reading's two parts, from a SpellCoefficients entry (direct and over
-- time, keys dKey and oKey). A reading with one part takes the entry's one part whichever it is:
-- the text and the tables need not agree on which it is (Arcane Missiles reads as damage over time
-- and is a missile every second).
local function tableShares(coef, directPart, periodicPart, dKey, oKey)
  if type(coef) ~= "table" then return nil, nil end
  local d, o = coef[dKey], coef[oKey]
  if directPart and not periodicPart and d == nil and o ~= nil then return o, nil end
  if periodicPart and not directPart and o == nil and d ~= nil then return nil, d end
  return d, o
end

-- Numbers to show for a parsed description. castTime (seconds) may be nil when unknown; then
-- a part that needs it gets no estimate. damageBonus / healBonus nil or 0 means no estimate.
-- coef: the spell's entry in SpellCoefficients for the running client, or nil. With an entry the
-- shares are the entry's, and a part it has none for (damage an area trigger or a second spell
-- does, which the tables do not link) gets no estimate; without one, the rules above.
function Estimate.Apply(parsed, castTime, damageBonus, healBonus, coef)
  if not parsed then return nil end
  local view = { school = parsed.school, estimated = false }

  local function pair(directPart, periodicPart, bonus, directKey, periodicKey, dKey, oKey)
    local usable = type(bonus) == "number" and bonus > 0
    local cDirect, cPeriodic
    if type(coef) == "table" then
      cDirect, cPeriodic = tableShares(coef, directPart, periodicPart, dKey, oKey)
    elseif directPart and castTime == nil then
      usable = false
    elseif usable then
      cDirect, cPeriodic = Estimate.Coefficients(castTime, directPart ~= nil, periodicPart and periodicPart.duration)
    end
    if directPart then
      local add = (usable and cDirect) and bonus * cDirect or 0
      view[directKey] = copyRange(directPart, add)
      if add > 0 then view.estimated = true end
    end
    if periodicPart then
      local add = (usable and cPeriodic) and bonus * cPeriodic or 0
      view[periodicKey] = copyPeriodic(periodicPart, add)
      if add > 0 then view.estimated = true end
    end
  end

  pair(parsed.direct, parsed.dot, damageBonus, "direct", "dot", "d", "o")
  pair(parsed.heal, parsed.hot, healBonus, "heal", "hot", "h", "ho")
  return view
end

-- The number for an action button. mode: "total" (average direct + everything over time),
-- "direct" (average direct only) or "off". Damage wins over healing when a spell has both.
-- Returns value, "damage" | "heal"; or nil.
function Estimate.ButtonValue(view, mode)
  if not view or mode == "off" then return nil end
  local function avg(r) return (r.min + r.max) / 2 end
  if mode == "direct" then
    if view.direct then return avg(view.direct), "damage" end
    if view.heal then return avg(view.heal), "heal" end
    return nil
  end
  if view.direct or view.dot then
    local v = 0
    if view.direct then v = v + avg(view.direct) end
    if view.dot then v = v + view.dot.total end
    return v, "damage"
  end
  if view.heal or view.hot then
    local v = 0
    if view.heal then v = v + avg(view.heal) end
    if view.hot then v = v + view.hot.total end
    return v, "heal"
  end
  -- A mana consumable's stated amount (average over a range, like healing).
  -- Damage and healing win over mana; a consumable view may still carry
  -- both amounts at once, and a spell may pair a health cost with a mana
  -- gain (Life Tap, read beside ButtonValue rather than through it).
  if view.mana then
    local m = view.mana
    if m.min and m.max then return (m.min + m.max) / 2, "mana" end
  end
  return nil
end

return Estimate
