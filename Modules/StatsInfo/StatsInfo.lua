-- BattleInfoTool module StatsInfo: in an item's tooltip, what it changes against what you wear.
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.
--
-- Written from scratch after the idea of RatingBuster (Whitetooth, GPL), none of whose code or
-- tables are used. The stats are the game's own: C_Item.GetItemStats, with the client's names for
-- them, so nothing here depends on the language of the tooltip.
--
-- Under each stat, what it gives the character (M.Worth). Only what the game shows to hold: see
-- there. /bit probe records what this client reports (the functions it has, the character's stats
-- and chances, and the equipped items' stats and tooltip lines) into the saved variables; the
-- breakdown was built from five of them.

local _, BIT = ...
local M = BIT.Module("StatsInfo")

local DEFAULTS = {
  compare = true, -- the differences against the equipped item
  worth = true,   -- under each difference, what it gives the character
  specs = true,   -- how each spec of the class rates the item (Weights.lua)
  icons = true,   -- icons and one line each, instead of words
  bagMarkers = true,   -- the small green/red arrows over the game's own bag buttons
  questMarkers = true, -- the one badge over a quest's reward buttons (an upgrade, or the coin)
  bagSpecIcons = true, -- on an up arrow, the beneficiary spec's icon (+N for the rest)
}

-- Inventory slots an item of an equip location goes into. Two slots: compared with each.
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
  INVTYPE_SHIELD = { 17 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
  INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
  INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}
-- A two-hander replaces both hands: compared with the two together.
local BOTH_HANDS = { INVTYPE_2HWEAPON = true }

-- The stats shown first, in this order; any other stat an item has comes after them.
local FIRST = {
  "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_INTELLECT_SHORT",
  "ITEM_MOD_SPIRIT_SHORT", "RESISTANCE0_NAME", "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT",
}
local RANK = {}
for i, key in ipairs(FIRST) do RANK[key] = i end

local settings

local function isSecret(v) return type(issecretvalue) == "function" and issecretvalue(v) or false end

local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d, e, f, g
end

-- One tooltip build asks itemStats for the same link many times (Compare once, SpecRatings
-- once per spec's measure, the tank gate again) and the character's own answers once per
-- stat line. The memo below holds those answers from the outermost call of one build to its
-- end (memoized wraps the public entries), so a build pays for each link once: no stats are
-- kept between builds, so nothing goes stale when the client's data arrives, and outside a
-- build (a direct call, /bit probe) nothing is cached at all -- exactly the old behavior.
-- The tables handed out are shared within the build and read-only to their takers.
local statsMemo, charMemo = {}, {}
local memoDepth = 0
local NO_VALUE = {}

local function memoOpen()
  if memoDepth == 0 then
    for k in pairs(statsMemo) do statsMemo[k] = nil end
    for k in pairs(charMemo) do charMemo[k] = nil end
  end
  memoDepth = memoDepth + 1
end

local function memoClose()
  memoDepth = memoDepth - 1
  if memoDepth <= 0 then
    memoDepth = 0
    for k in pairs(statsMemo) do statsMemo[k] = nil end
    for k in pairs(charMemo) do charMemo[k] = nil end
  end
end

-- The entries that are one build: TooltipLines is the hover itself; Compare and SpecRatings
-- are its parts (BagMarkers and QuestMarkers call them directly too, where each call is one
-- build of its own). Each of them returns exactly one value, and it comes back unchanged:
-- pcall keeps an error from leaking the open build (it is always closed again on the way
-- out) and the error goes up unchanged.
local function memoized(fn)
  return function(...)
    memoOpen()
    local ok, a = pcall(fn, ...)
    memoClose()
    if not ok then error(a, 0) end
    return a
  end
end

-- What the character is, asked at most once per build: its class behind the specs, and the
-- worth lines' per-point answers (they do not depend on n). Fresh again at every build; a
-- direct M.Worth call outside a build asks live, as it always did.
local function charFact(key, compute)
  if memoDepth > 0 then
    local hit = charMemo[key]
    if hit ~= nil then
      if hit == NO_VALUE then return nil end
      return hit
    end
  end
  local v = compute()
  if memoDepth > 0 then
    if v == nil then charMemo[key] = NO_VALUE else charMemo[key] = v end
  end
  return v
end

-- The class behind M.SPECS, or nil; one read per build.
local function charClass()
  return charFact("class", function()
    local _, class = ask(UnitClass, "player")
    return class
  end)
end

-- The name the client gives a stat key ("Beweglichkeit"), or nil when it has none.
local function statName(key)
  local name = _G[key]
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

-- withoutEnchant and tooltipEnchant are defined after RATINGS, in the ENCHANT block below.
local withoutEnchant, tooltipEnchant

-- An item's stats, key -> number, or {}. A key the client has no name for is left out: the same
-- stat also comes under a key it names (Forever gives a ring's frost resistance both as
-- RESISTANCE4_NAME and as ITEM_MOD_FROST_RESISTANCE_SHORT, the second unnamed).
-- C_Item.GetItemStats may leave an item's enchant out (the probe proved it: the Embossed Leather
-- Vest reads 62 Armor and 2 Stamina while its tooltip says "Enchanted: Stamina +1 and Armor +8"),
-- so a key the parsed tooltip enchant names is reconciled against the client's own answer for the
-- link without its enchant field; the answer for the whole link stays the baseline, and a missing
-- clean answer or enchant never drops or doubles a stat. A secret clean stat (the client hides a
-- value in combat, marking it with issecretvalue) is never added to or guessed from: the baseline
-- keeps the stat.
local function itemStats(link)
  -- A nil or secret link (in combat) must never reach the link rewrite or the enchant memo: the
  -- client raises on secret keys, so nothing is asked and nothing is cached.
  if type(link) ~= "string" or isSecret(link) then return {} end
  -- Within one tooltip build the answer is asked for the same link a dozen times and more: it
  -- is computed once per build and handed out read-only for the rest of it (see memoOpen).
  if memoDepth > 0 then
    local hit = statsMemo[link]
    if hit then return hit end
  end
  -- Baseline: the client's own GetItemStats answer for the whole link. Some clients count an
  -- enchant in it, some leave it out, and that answer is never dropped or added to blindly.
  -- Where both a trusted parse of the enchant and a stats answer for the link without its
  -- enchant field exist, a key the enchant names reads base + enchant; every other key keeps the
  -- baseline. Without the clean answer (an error, a nil) nothing is invented or doubled: the
  -- baseline stands, a missing enchant beats a wrong stat.
  local out = {}
  local stats = ask(C_Item and C_Item.GetItemStats, link)
  if type(stats) ~= "table" then stats = ask(GetItemStats, link) end
  if type(stats) == "table" then
    for k, v in pairs(stats) do
      -- NaN (NaN ~= 0 in Lua) and infinities must never reach the weights arithmetic
      if type(k) == "string" and statName(k) and not isSecret(v) and type(v) == "number"
          and v ~= 0 and v == v and v ~= math.huge and v ~= -math.huge then out[k] = v end
    end
  end
  local plain = withoutEnchant(link)
  local clean = ask(C_Item and C_Item.GetItemStats, plain)
  if type(clean) ~= "table" then clean = ask(GetItemStats, plain) end
  if type(clean) == "table" then
    for k, v in pairs(tooltipEnchant(link)) do
      if type(k) == "string" and statName(k) and type(v) == "number" and v ~= 0
          and v == v and v ~= math.huge and v ~= -math.huge then
        local base = clean[k]
        -- A secret clean stat (the client hides the value in combat, marking it with
        -- issecretvalue -- the value may still be a number) is never arithmetic'd on or
        -- guessed from: the full link's own answer keeps the stat.
        if not isSecret(base) then
          if type(base) ~= "number" then base = 0 end
          out[k] = base + v
        end
      end
    end
  end
  if memoDepth > 0 then statsMemo[link] = out end
  return out
end
M.ItemStats = memoized(itemStats)

local function equipLoc(link)
  local _, _, _, loc = ask(C_Item and C_Item.GetItemInfoInstant, link)
  if loc == nil then _, _, _, loc = ask(GetItemInfoInstant, link) end
  return type(loc) == "string" and loc or nil
end

local function equipped(slot)
  local link = ask(GetInventoryItemLink, "player", slot)
  -- A secret link is not a link: it reads as a string (type() cannot tell), but Compare
  -- equates it with the new link below and that comparison raises on a combat-secret value
  -- (the bag handlers went down to it). Wearing "unknown" is wearing nothing comparable.
  if type(link) ~= "string" or isSecret(link) then return nil end
  return link
end

-- Whether the client's answers for link can be trusted yet. The new link has this guard in
-- Compare; a worn link needs it too: an heirloom whose stats are not cached yet reads as {},
-- and its block would print the new item's full stats under the worn item's name (a duplicated
-- recommendation). Uncached worn stats skip the block; the tooltip is rebuilt on arrival.
local function itemCached(link)
  local id = ask(C_Item and C_Item.GetItemInfoInstant, link)
  if not id or not (C_Item and C_Item.IsItemDataCachedByID) then return true end -- cannot tell: old behavior
  return ask(C_Item.IsItemDataCachedByID, id) ~= false
end

-- What wearing link instead of what is in its slot changes: a list of { key, diff }, sorted,
-- and what it is compared with; nil when there is nothing to compare with, or when link is
-- worn (in either of two slots). Rings and trinkets: one comparison with each worn. A one-hand
-- weapon: with the main hand, an empty one too (it goes there, and a weapon in the off hand stays;
-- set against the off hand, an identical dagger was rated as its main-hand worth over its off-hand one).
function M.Compare(link)
  local loc = equipLoc(link)
  if not loc then return nil end
  -- Not before the client has the item: its stats would read as none, every stat lost. The tooltip is
  -- built again when the data arrives.
  local id = ask(C_Item and C_Item.GetItemInfoInstant, link)
  if id and C_Item and C_Item.IsItemDataCachedByID and ask(C_Item.IsItemDataCachedByID, id) == false then return nil end
  local slots = BOTH_HANDS[loc] and { 16, 17 } or SLOTS[loc] or {}
  for _, slot in ipairs(slots) do
    if equipped(slot) == link then return nil end -- the item worn
  end
  local new = itemStats(link)
  local comparisons = {}
  -- target: the slot the item would go into, when it is not the one compared with (a shield against the
  -- two-hander it would take off)
  local function compareWith(slots, target)
    local old, names, wornSlots = {}, {}, {}
    for _, slot in ipairs(slots) do
      local worn = equipped(slot)
      if worn then
        local wornStats = itemStats(worn)
        if next(wornStats) == nil and not itemCached(worn) then
          return -- stats still loading: no invented block; the tooltip rebuilds on arrival
        end
        names[#names + 1] = worn
        wornSlots[#wornSlots + 1] = slot
        for k, v in pairs(wornStats) do old[k] = (old[k] or 0) + v end
      end
    end
    local diffs = {}
    local keys = {}
    for k in pairs(new) do keys[k] = true end
    for k in pairs(old) do keys[k] = true end
    for k in pairs(keys) do
      local d = (new[k] or 0) - (old[k] or 0)
      -- SI-124: a diff that renders as +0.0 (e.g. +0.04 DPS) is noise, not a line.
      if d ~= 0 and math.abs(d) >= 0.05 then diffs[#diffs + 1] = { key = k, diff = d } end
    end
    -- A named comparison with no worn stats behind it would print the new item's full
    -- numbers under the worn item's name (a duplicated recommendation): the worn data was
    -- unavailable (uncached heirloom, an answer the parser does not name). The block is
    -- skipped; the empty-slot block carries the same numbers honestly. An all-empty
    -- comparison ("the same stats") stays: it is true either way.
    if #names > 0 and next(old) == nil and #diffs > 0 then return end
    table.sort(diffs, function(a, b)
      local ra, rb = RANK[a.key] or 100, RANK[b.key] or 100
      if ra ~= rb then return ra < rb end
      return (statName(a.key) or a.key) < (statName(b.key) or b.key)
    end)
    -- againstSlots: the slots compared with, an empty one included; wornSlots lists only the
    -- ones carrying an item (it indexes against, SpecRatings needs it so). The tooltip names
    -- the block's slot from againstSlots: a ring's two blocks otherwise read as one repeated.
    comparisons[#comparisons + 1] = { against = names, slots = wornSlots, againstSlots = slots,
      diffs = diffs, offHand = (target or (#slots == 1 and slots[1])) == 17 }
  end
  local mainHand = equipped(16)
  if BOTH_HANDS[loc] then
    compareWith({ 16, 17 })
  elseif loc == "INVTYPE_WEAPON" then
    compareWith({ 16 }) -- it goes into the main hand
  elseif #slots == 1 and slots[1] == 17 and mainHand and equipLoc(mainHand) == "INVTYPE_2HWEAPON" then
    compareWith({ 16 }, 17) -- an off-hand item takes the two-hander off
  else
    for _, slot in ipairs(slots) do compareWith({ slot }) end
  end
  return #comparisons > 0 and comparisons or nil
end
M.Compare = memoized(M.Compare)

-- A stat's change as text: whole numbers as they are, others to one decimal (1.9 damage per second).
local function signed(v)
  local text = (v == math.floor(v)) and string.format("%d", v) or string.format("%.1f", v)
  return (v > 0 and "+" or "") .. text
end

---------------------------------------------------------------------------------------------
-- What a stat gives
---------------------------------------------------------------------------------------------

-- What the game itself says, worked out as Forever's own character sheet does it
-- (Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua): GetCritChanceFromStat and
-- GetSpellCritChanceFromStat give the crit that a number of points of Agility or Intellect bring,
-- GetDodgeChanceFromAttribute the dodge the character's whole Agility brings, GetAttackPowerForStat
-- the attack power and UnitHPPerStamina the health a point of Stamina gives. Forever's client holds
-- the per-class, per-level ratios behind them (PlayerExpectedStat.db2); Classic Era and Retail have
-- no FromStat functions, and there those lines are left out. Armor is 2 per Agility and mana
-- regeneration a quarter of Spirit, as five probes on Forever showed; mana is MANA_PER_INTELLECT
-- (15). In combat the answers can be secret: then the line is left out.

local function num(v) return type(v) == "number" and not isSecret(v) and v or nil end

-- The character's live numbers behind the tank caps and the worth lines' shield check
-- (defense skill, level, dodge, parry, block chance): they move only with gear, buffs, form
-- or level, yet every hover read them all again. They are kept for a short TTL and dropped
-- on the events that can change them (the loader below listens), so a hover storm reads each
-- of them at most once per change. An answer that is secret or missing is never kept (it may
-- become visible later): it is asked again the next time.
local TANK_TTL = 1.0
local tankMemo = {}
local function tankForget()
  for k in pairs(tankMemo) do tankMemo[k] = nil end
end

local function tankRead(key, compute)
  local t = ask(GetTime)
  local hit = tankMemo[key]
  if hit and type(t) == "number" and t >= hit.t and (t - hit.t) <= TANK_TTL then return hit.v end
  local v = compute()
  if type(v) == "number" and not isSecret(v) and v == v and v ~= math.huge and v ~= -math.huge then
    if type(t) == "number" then tankMemo[key] = { t = t, v = v } end
  else
    tankMemo[key] = nil
  end
  return v
end

-- The character's level, as tankMissChance and the uncrittable target read it.
local function tankLevel()
  return tankRead("lvl", function() return num(ask(UnitLevel, "player")) end)
end

local function usesMana()
  return charFact("mana", function()
    local max = num(ask(UnitPowerMax, "player", 0))
    return max ~= nil and max > 0
  end)
end

-- Mana a second, out of casting, per point of Spirit, to the thousandth the game gives it in
-- (7.751 and 0.001 for 31 Spirit: 0.25, not the 0.2499... the subtraction leaves).
local function regenPerSpirit()
  return charFact("regen", function()
    local _, spirit = ask(UnitStat, "player", 5)
    spirit = num(spirit)
    local base, casting = ask(GetManaRegen)
    base, casting = num(base), num(casting) or 0
    if not (spirit and base and spirit > 0) then return nil end
    return math.floor((base - casting) / spirit * 1000 + 0.5) / 1000
  end)
end

local function attackPower(stat, n)
  local v = num(ask(GetAttackPowerForStat, stat, math.abs(n)))
  if not v or v == 0 then return nil end
  return n < 0 and -v or v
end

-- A "...FromStat" answer (a fraction) for n points, as a percentage with n's sign.
local function chanceFromStat(fn, stat, n)
  local v = num(ask(fn, stat, math.abs(n)))
  if not v then return nil end
  v = v * 100
  return n < 0 and -v or v
end

-- Dodge a point of Agility gives: the dodge the character's Agility brings, over that Agility.
local function dodgePerAgility()
  return charFact("dodgePerAgi", function()
    local total = num(ask(GetDodgeChanceFromAttribute))
    local _, agi = ask(UnitStat, "player", 2)
    agi = num(agi)
    if not (total and agi and agi > 0) then return nil end
    return total * 100 / agi
  end)
end

local function constant(name, fallback)
  local v = _G[name]
  return type(v) == "number" and v or fallback
end

local function percent(v) return string.format("%+.2f%%", v) end
local function worthShowing(v) return v and math.abs(v) >= 0.005 end

-- An item's rating and what it is: its kind, and the game's rating index (a global of the character sheet,
-- with its number on Forever as a fallback). Forever's items give crit and hit as points of rating, one
-- rating for melee, ranged and spells alike; the percentage it makes depends on the level.
local RATINGS = {
  ITEM_MOD_CRIT_RATING_SHORT = { "crit", "CR_CRIT_MELEE", 9 }, ITEM_MOD_CRIT_MELEE_RATING_SHORT = { "crit", "CR_CRIT_MELEE", 9 },
  ITEM_MOD_CRIT_RANGED_RATING_SHORT = { "crit", "CR_CRIT_RANGED", 10 },
  ITEM_MOD_CRIT_SPELL_RATING_SHORT = { "spellcrit", "CR_CRIT_SPELL", 11 },
  ITEM_MOD_HIT_RATING_SHORT = { "hit", "CR_HIT_MELEE", 6 }, ITEM_MOD_HIT_MELEE_RATING_SHORT = { "hit", "CR_HIT_MELEE", 6 },
  ITEM_MOD_HIT_RANGED_RATING_SHORT = { "hit", "CR_HIT_RANGED", 7 }, ITEM_MOD_HIT_SPELL_RATING_SHORT = { "hit", "CR_HIT_SPELL", 8 },
  ITEM_MOD_HASTE_RATING_SHORT = { "haste", "CR_HASTE_MELEE", 18 },
  ITEM_MOD_EXPERTISE_RATING_SHORT = { "expertise", "CR_EXPERTISE", 24 },
  ITEM_MOD_DODGE_RATING_SHORT = { "dodge", "CR_DODGE", 3 }, ITEM_MOD_PARRY_RATING_SHORT = { "parry", "CR_PARRY", 4 },
  ITEM_MOD_BLOCK_RATING_SHORT = { "block", "CR_BLOCK", 5 },
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = { "defense", "CR_DEFENSE_SKILL", 2 },
}

---------------------------------------------------------------------------------------------
-- The tooltip's enchant line (ENCHANT): C_Item.GetItemStats may leave an item's enchant out, so
-- the enchant's stats are read from the client's own words (the localized ITEM_ENCHANTMENT
-- header, or the enchant line type when the client has one) -- nothing guessed. The client's own
-- GetItemStats answer for the whole link is the baseline: a key the enchant names is reconciled
-- against the answer for the link without its enchant field (base + enchant), every other key
-- keeps the baseline, and without the clean answer nothing is invented or doubled. Only a line
-- the client marks as an enchant counts: the localized ITEM_ENCHANTMENT header (which may be a
-- format with a %s in it), or the enchant tooltip line type (Enum.TooltipDataLineType.
-- ItemEnchantmentPermanent) when the client has one; the ordinary stat, equip and proc lines are
-- never read. Only the stats this module knows are taken, and an enchant the words do not give
-- cleanly (a proc phrase, a percent, a duration, a name with no number, any prose around the
-- stat) adds nothing: a missing enchant beats a wrong stat. A phrase naming a bundle of stats
-- at once ("+4 All Stats", "Alle Werte +4") is taken as the keys it is made of (ENCHANT_BUNDLES
-- below). A tooltip that was not there (no
-- data, no lines, or only the bare title) is never cached as "no enchant", and neither is a
-- tooltip with a secret line: the scan is re-run when the lines may have arrived.
---------------------------------------------------------------------------------------------

withoutEnchant = function(link)
  -- The link without its enchant field (the second number after "item:"), everything else kept:
  -- the base for GetItemStats. A link without the field is returned as it is.
  if type(link) ~= "string" then return link end
  return (link:gsub("item:(%d+):(%d+)", "item:%1:", 1))
end

-- The keys an enchant can give, by their client names; the longer name first, so "Attack Power"
-- is matched whole and "Power" never inside it. A key the client has no name for cannot be read
-- back out of a tooltip line.
local ENCHANT_KEYS = {
  "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
  "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT", "RESISTANCE0_NAME",
  "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT",
  "ITEM_MOD_SPELL_HEALING_DONE_SHORT", "ITEM_MOD_SPELL_POWER_SHORT",
  "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT",
  "ITEM_MOD_PHYSICAL_DAMAGE_DONE_SHORT", "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT",
  "ITEM_MOD_DEFENSE_SKILL_SHORT", "ITEM_MOD_BLOCK_VALUE_SHORT",
  "ITEM_MOD_HEALTH_SHORT", "ITEM_MOD_MANA_SHORT",
  "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_POWER_REGEN0_SHORT",
  "ITEM_MOD_FERAL_ATTACK_POWER_SHORT",
  "RESISTANCE1_NAME", "RESISTANCE2_NAME", "RESISTANCE3_NAME",
  "RESISTANCE4_NAME", "RESISTANCE5_NAME", "RESISTANCE6_NAME",
  "ITEM_MOD_HOLY_RESISTANCE_SHORT", "ITEM_MOD_FIRE_RESISTANCE_SHORT",
  "ITEM_MOD_NATURE_RESISTANCE_SHORT", "ITEM_MOD_FROST_RESISTANCE_SHORT",
  "ITEM_MOD_SHADOW_RESISTANCE_SHORT", "ITEM_MOD_ARCANE_RESISTANCE_SHORT",
}
for key in pairs(RATINGS) do ENCHANT_KEYS[#ENCHANT_KEYS + 1] = key end

-- A bundle of stats an enchant names as one phrase ("+4 All Stats", "Alle Werte +4"): no key
-- and no client name of its own names the bundle (no GlobalString holds it), so the enchant's
-- own words are read in the locales it is written in and expanded into the keys it is made
-- of; a phrase behind one connector ("+4 to All Stats", "+4 auf alle Werte") is the same
-- component. The marker keys never reach the stats: parseEnchantText expands them and a
-- leaked one names no stat. Anything else stays prose and adds nothing.
local ENCHANT_BUNDLES = {
  { marker = "\1all", -- the five primary stats
    keys = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
      "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT" },
    phrases = { "All Stats", "Alle Werte", "Wszystkie statystyki", "Все характеристики",
      "Toutes les caractéristiques", "Todas las estadísticas", "Tutte le statistiche" } },
  { marker = "\1res", -- every school of resistance, but never Armor
    keys = { "RESISTANCE1_NAME", "RESISTANCE2_NAME", "RESISTANCE3_NAME",
      "RESISTANCE4_NAME", "RESISTANCE5_NAME", "RESISTANCE6_NAME" },
    phrases = { "All Resistances", "Alle Widerstandsarten", "Wszystkie odporności",
      "Все сопротивления", "Toutes les résistances", "Todas las resistencias",
      "Tutte le resistenze" } },
}
-- The words a phrase may stand behind ("to All Stats", "auf alle Werte"), and the phrase
-- itself: one connector between the number and the phrase, in the languages above.
local BUNDLE_BRIDGES = { "", "to ", "to the ", "auf ", "zu ", "um ", "de ", "para ", "per " }
local bundleKeys = {}
for _, b in ipairs(ENCHANT_BUNDLES) do
  bundleKeys[b.marker] = b.keys
  b.names = {}
  for _, phrase in ipairs(b.phrases) do
    for _, form in ipairs({ phrase, (phrase:gsub("^%a", string.lower)), (phrase:lower()) }) do
      for _, bridge in ipairs(BUNDLE_BRIDGES) do
        b.names[#b.names + 1] = bridge .. form
      end
    end
  end
end

-- The names an enchant can be written with, longest first. They are the client's own global
-- strings (fixed per locale) with the bundles' static phrases on top: the ~400-entry list is
-- built and sorted once and then reused -- it was rebuilt and re-sorted on every parse, which
-- on an uncacheable tooltip meant every hover. The snapshot is thrown away and rebuilt only
-- when one of the global strings behind it actually changes (the test suites rebind them to
-- model another locale).
local enchantNamesCache, enchantNamesSig = nil, nil

local function enchantNames()
  if enchantNamesCache then
    local same = true
    for i = 1, #ENCHANT_KEYS do
      local key = ENCHANT_KEYS[i]
      if enchantNamesSig[key] ~= _G[key] then
        same = false
        break
      end
    end
    if same then return enchantNamesCache end
  end
  local byName = {}
  for _, key in ipairs(ENCHANT_KEYS) do
    local name = statName(key)
    if name and not byName[name] then byName[name] = { name = name, key = key } end
  end
  for _, b in ipairs(ENCHANT_BUNDLES) do
    for _, name in ipairs(b.names) do
      if not byName[name] then byName[name] = { name = name, key = b.marker } end
    end
  end
  local names = {}
  for _, n in pairs(byName) do names[#names + 1] = n end
  table.sort(names, function(a, b) return #a.name > #b.name end)
  enchantNamesCache = names
  enchantNamesSig = {}
  for i = 1, #ENCHANT_KEYS do
    local key = ENCHANT_KEYS[i]
    enchantNamesSig[key] = _G[key]
  end
  return names
end

-- The line type the client marks an enchant line with, when it exposes one: the client's own
-- enum name for it (the generated TooltipInfoSharedDocumentation; on Classic: ItemEnchantmentPermanent).
local function enchantLineType()
  local t = Enum and Enum.TooltipDataLineType
  if type(t) ~= "table" then return nil end
  local v = t.ItemEnchantmentPermanent
  return type(v) == "number" and v or nil
end

-- The line type the client marks a tooltip's title (the item's name line) with, when it
-- exposes one: a tooltip whose only line is the title has not built its lines yet.
local function nameLineType()
  local t = Enum and Enum.TooltipDataLineType
  if type(t) ~= "table" then return nil end
  local v = t.ItemName
  return type(v) == "number" and v or nil
end

-- The enchant's words of a tooltip line (after the header), or nil when the line is not marked
-- as an enchant.
local function enchantTextOf(line)
  -- The client wraps a tooltip line in colour codes (|cAARRGGBB ... |r) when it is coloured:
  -- they are taken off first, so the header is found inside them.
  local text = type(line) == "table" and line.leftText or nil
  if type(text) ~= "string" or isSecret(text) then return nil end
  text = (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  local header = _G.ITEM_ENCHANTMENT
  if type(header) == "string" and header ~= "" then
    -- The header may be a format with a %s in it ("Enchanted: %s"): the words before the %s are
    -- the prefix the line starts with.
    local prefix = header:gsub("%%s", "")
    if prefix ~= "" and text:sub(1, #prefix) == prefix then return text:sub(#prefix + 1) end
  end
  local t = enchantLineType()
  if t and line.type == t then return text end
  return nil
end

-- A signed number straight after a position ("+1 ..."), or the one straight before it
-- ("... +1"), the two ways an enchant names its stats; as text, or nil.
local function numberAt(text, at)
  local t = text:match("^%s*(%+?%-?%d+%.?%d*)", at)
  return t and t ~= "" and t or nil
end

-- The words between two stat components of an enchant: a comma or the word "and"
-- ("und" in German), with the spaces around it; nil when other words stand there.
local function separatorAt(text, at)
  local rest = text:sub(at)
  local sep = rest:match("^%s*,%s*") or rest:match("^%s+and%s+") or rest:match("^%s+und%s+")
  return sep and #sep or nil
end

-- One stat component at position at: a known stat name with a signed number on one side
-- of it ("Stamina +1", "+8 Armor", "Stamina+1"), the name at a word's boundary; the key,
-- the number and the position after the component, or nothing when the words there are
-- not a component (a name without a number, a number with no name beside it, prose).
local function componentAt(text, names, at)
  local start, name, key
  for _, n in ipairs(names) do
    local s = text:find(n.name, at, true)
    if s and (not start or s < start) then start, name, key = s, n.name, n.key end
  end
  if start and not text:sub(at, start - 1):match("%S") then
    local before, afterC = text:sub(start - 1, start - 1), text:sub(start + #name, start + #name)
    if not (before:match("%w") or afterC:match("%w")) then
      local n = numberAt(text, start + #name)
      if n then
        local _, numEnd = text:find("^%s*(%+?%-?%d+%.?%d*)", start + #name)
        return key, tonumber(n), numEnd + 1
      end
    end
  end
  local n = numberAt(text, at)
  if n then
    local _, numEnd = text:find("^%s*(%+?%-?%d+%.?%d*)", at)
    local s2, name2, key2
    for _, n2 in ipairs(names) do
      local s = text:find(n2.name, numEnd + 1, true)
      if s and (not s2 or s < s2) then s2, name2, key2 = s, n2.name, n2.key end
    end
    if s2 and not text:sub(numEnd + 1, s2 - 1):match("%S") then
      local before = text:sub(s2 - 1, s2 - 1)
      local afterC = text:sub(s2 + #name2, s2 + #name2)
      if not (before:match("%w") or afterC:match("%w")) then
        return key2, tonumber(n), s2 + #name2
      end
    end
  end
  return nil
end

-- The stats of an enchant's words: only clean stat components count -- a name with its
-- number on one side ("Stamina +1", "+8 Armor", "Stamina+1"), a component joined to the
-- next by a comma or "and"/"und". Any other word (a proc phrase like "Chance on hit: ..."
-- or "Use: ...", a percent, a duration, a name without a number) makes the whole line
-- prose, and the enchant adds nothing: only the stats this module knows are taken, and a
-- missing enchant beats a wrong stat.
local function parseEnchantText(text)
  local out = {}
  local names = enchantNames()
  local pos, len = 1, #text
  local first = true
  while pos <= len do
    if text:sub(pos):match("^%s*$") then break end -- trailing whitespace ends the words
    if not first then
      local sep = separatorAt(text, pos)
      if not sep then return {} end
      pos = pos + sep
    end
    local key, n, nextPos = componentAt(text, names, pos)
    if not key then return {} end
    local bundle = bundleKeys[key]
    if bundle then
      for _, real in ipairs(bundle) do out[real] = (out[real] or 0) + n end
    else
      out[key] = (out[key] or 0) + n
    end
    pos = nextPos
    first = false
  end
  return out
end

-- The enchant stats read for link, cached once the tooltip data was there: an enchant is fixed in
-- the link, so a read tooltip's answer stands. A tooltip that has not built its lines (the item's
-- data has not arrived: no data, no lines at all, or only the bare title) is scanned again when it
-- may have arrived -- never kept as "no enchant". Neither is a tooltip holding a secret line (a
-- value the client hides may be the enchant line): the scan is re-run then too. The memo holds at
-- most ENCHANT_MEMO_MAX links (a session hovering the whole bank would otherwise grow it without
-- limit): when it is full the next new link wipes it and the reads start over.
local ENCHANT_MEMO_MAX = 256
local enchantMemo, enchantMemoCount = {}, 0
tooltipEnchant = function(link)
  -- A nil or secret link must never index the memo: the client raises on secret keys.
  if type(link) ~= "string" or isSecret(link) then return {} end
  local known = enchantMemo[link]
  if known ~= nil then return known end
  local out = {}
  local data = ask(C_TooltipInfo and C_TooltipInfo.GetHyperlink, link)
  -- The read tooltip's answer is kept only when it is complete and nothing is hidden: at
  -- least one line beyond the bare title (the item's name line, the only line of a tooltip
  -- whose data has not arrived), and no secret line. A title-only tooltip and a tooltip
  -- with a secret line are scanned again, and an enchant they do not show is not invented.
  if type(data) == "table" and type(data.lines) == "table" and #data.lines > 0 then
    local cacheable, hidden, titleType = false, false, nameLineType()
    for _, line in ipairs(data.lines) do
      if type(line) == "table" and isSecret(line.leftText) then
        hidden = true -- the hidden line may be the enchant: not a final answer
      elseif not (titleType and line.type == titleType) then
        cacheable = true -- a line beyond the title: the tooltip was built
        local text = enchantTextOf(line)
        if text then
          for key, n in pairs(parseEnchantText(text)) do out[key] = (out[key] or 0) + n end
        end
      end
    end
    -- a hidden line anywhere sticks: the scan is re-run when nothing is hidden any more
    if cacheable and not hidden then
      if enchantMemoCount >= ENCHANT_MEMO_MAX then
        for k in pairs(enchantMemo) do enchantMemo[k] = nil end
        enchantMemoCount = 0
      end
      enchantMemo[link] = out
      enchantMemoCount = enchantMemoCount + 1
    end
  end
  return out
end

-- Strength gives block value (0.05 per point, RatingBuster Classic / StatLogic VanillaLogic
-- ADD_BLOCK_VALUE_MOD_STR value 0.05) but only while actually blocking: a shield-capable
-- class (warrior, paladin, shaman) with nonzero block chance. A 2H or empty off-hand
-- blocks nothing, so the line stays out. Class and chance both guarded (ask + pcall);
-- a secret class (in combat) fails silent: no line.
local function usesShield()
  return charFact("shield", function()
    local class = charClass()
    if not class or isSecret(class) then return false end
    if class ~= "WARRIOR" and class ~= "PALADIN" and class ~= "SHAMAN" then return false end
    local bv = tankRead("block", function() return num(ask(GetBlockChance)) end)
    return (bv or 0) > 0
  end)
end

-- Feral Attack Power is attack power 1:1 (RatingBuster Classic / StatLogic VanillaLogic
-- ADD_AP_MOD_FERAL_ATTACK_POWER value 1 for Cat/Bear/Dire Bear) but only in form: outside
-- Cat/Bear it would lie, so nothing is shown. The form is asked the guarded way Range asks
-- it (GetShapeshiftFormID: Cat 1, Bear 5, Dire Bear 8, see Range.lua DRUID_FORM_SPELLS and
-- SpellDamageInfo CAT_FORM); a secret or unknown form fails silent: no line.
local function inFeralForm()
  return charFact("form", function()
    local form = ask(GetShapeshiftFormID)
    if form == nil or isSecret(form) then return false end
    return form == 1 or form == 5 or form == 8
  end)
end

-- One part of a worth line, appended where it belongs (no closure per call: WorthParts runs
-- per stat of every hover).
local function addPart(parts, kind, value) parts[#parts + 1] = { kind = kind, value = value } end

-- What n points of the stat under key give this character: { { kind, value } }, in the order shown.
function M.WorthParts(key, n)
  local parts = {}
  if key == "ITEM_MOD_STRENGTH_SHORT" then
    local ap = attackPower(1, n)
    if ap then addPart(parts, "ap", ap) end
    if usesShield() then addPart(parts, "blockvalue", n * 0.05) end
  elseif key == "ITEM_MOD_AGILITY_SHORT" then
    addPart(parts, "armor", constant("ARMOR_PER_AGILITY", 2) * n)
    local ap = attackPower(2, n)
    if ap then addPart(parts, "ap", ap) end
    local crit = chanceFromStat(GetCritChanceFromStat, 2, n)
    if worthShowing(crit) then addPart(parts, "crit", crit) end
    local dodge = dodgePerAgility()
    if dodge and worthShowing(dodge * n) then addPart(parts, "dodge", dodge * n) end
  elseif key == "ITEM_MOD_STAMINA_SHORT" then
    -- SI-249: in combat the answers can be secret; then the line is left out.
    -- A fallback 10*modifier would invent health (e.g. +20) the game hid.
    local rawPer, rawMod = ask(UnitHPPerStamina, "player"), ask(GetUnitMaxHealthModifier, "player")
    if isSecret(rawPer) or isSecret(rawMod) then return parts end
    local per = num(rawPer)
    if not per then per = 10 * (num(rawMod) or 1) end
    -- SI-250: round half away from zero, so -10.5 is -11, not -10.
    local v = per * n
    addPart(parts, "health", v >= 0 and math.floor(v + 0.5) or math.ceil(v - 0.5))
  elseif key == "ITEM_MOD_INTELLECT_SHORT" then
    if usesMana() then
      addPart(parts, "mana", constant("MANA_PER_INTELLECT", 15) * n)
      local spellCrit = chanceFromStat(GetSpellCritChanceFromStat, 4, n)
      if worthShowing(spellCrit) then addPart(parts, "spellcrit", spellCrit) end
    end
  elseif key == "ITEM_MOD_SPIRIT_SHORT" then
    local per = usesMana() and regenPerSpirit()
    if per and per > 0 then addPart(parts, "regen", math.floor(per * n * 50 + 0.5) / 10) end
  elseif key == "ITEM_MOD_HEALTH_SHORT" then
    -- flat health on the item (an enchant or a gem gives it), not through Stamina
    addPart(parts, "health", n)
  elseif key == "ITEM_MOD_MANA_SHORT" then
    addPart(parts, "mana", n)
  elseif key == "ITEM_MOD_BLOCK_VALUE_SHORT" then
    addPart(parts, "blockvalue", n)
  elseif key == "ITEM_MOD_SPELL_HEALING_DONE_SHORT" then
    addPart(parts, "healing", n)
  elseif key == "ITEM_MOD_SPELL_POWER_SHORT" or key == "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" then
    addPart(parts, "spellpower", n)
  elseif key == "ITEM_MOD_DEFENSE_SKILL_SHORT" then
    -- Flat +Defense skill: no such key in the client's GlobalStrings (only
    -- ITEM_MOD_DEFENSE_SKILL_RATING_SHORT exists) and none seen in GetItemStats data;
    -- kept defensively. Honest raw skill ("+X defense", kind "defense" with its existing
    -- word and ShieldWall icon), not the 0.04% avoidance RatingBuster converts it to.
    addPart(parts, "defense", n)
  elseif key == "ITEM_MOD_FERAL_ATTACK_POWER_SHORT" then
    -- 1:1 attack power, but only in Cat/Bear form (see inFeralForm above).
    if inFeralForm() then addPart(parts, "ap", n) end
  elseif RATINGS[key] then
    -- the game's own conversion at this level, as its character sheet does it
    local kind, name, number = RATINGS[key][1], RATINGS[key][2], RATINGS[key][3]
    local index = type(_G[name]) == "number" and _G[name] or number
    local v = num(ask(GetCombatRatingBonusForCombatRatingValue, index, math.abs(n)))
    if v and v ~= 0 then addPart(parts, kind, n < 0 and -v or v) end
  end
  return parts
end

local WORTH_WORDS = {
  armor = "armor", ap = "attack power", crit = "crit", dodge = "dodge", health = "health", mana = "mana",
  spellcrit = "spell crit", regen = "mana per 5 sec. when not casting", hit = "hit", haste = "haste",
  expertise = "expertise", parry = "parry", block = "block", blockvalue = "block value", defense = "defense",
  healing = "healing", spellpower = "spell power",
}
local PERCENT_KINDS = { crit = true, dodge = true, spellcrit = true, hit = true, haste = true, expertise = true,
  parry = true, block = true }
-- The word beside each icon on the icon line, short.
local WORTH_SHORT = {
  armor = "armor", ap = "AP", crit = "crit", dodge = "dodge", health = "health", mana = "mana",
  spellcrit = "spell crit", regen = "mana/5s", hit = "hit", haste = "haste", expertise = "expertise",
  parry = "parry", block = "block", blockvalue = "block value", defense = "defense", healing = "healing",
  spellpower = "spell power",
}
local function worthValue(kind, value) return PERCENT_KINDS[kind] and percent(value) or signed(value) end

-- Up green, down red: the colour of a value by its sign.
local UP, DOWN = "|cff4dff4d", "|cffff5959"
local function bySign(v, text)
  if v > 0 then return UP .. text .. "|r" elseif v < 0 then return DOWN .. text .. "|r" end
  return text
end

-- What n points of the stat under key give this character, as text, or nil; each value coloured by
-- whether it goes up or down when coloured is set.
function M.Worth(key, n, coloured)
  local out = {}
  for _, p in ipairs(M.WorthParts(key, n)) do
    local text = worthValue(p.kind, p.value) .. " " .. WORTH_WORDS[p.kind]
    out[#out + 1] = coloured and bySign(p.value, text) or text
  end
  return #out > 0 and table.concat(out, ", ") or nil
end

---------------------------------------------------------------------------------------------
-- How each spec of the class rates an item (Weights.lua: ForeverSim's stat weights)
---------------------------------------------------------------------------------------------

-- A percentage always: old and new are both worths to the spec's measure.
-- Past MAX_PERCENT either way it caps: a ring worth 0.15 against
-- nothing is ">300%", not "+29817%". An empty slot (old 0, new something) is
-- the same cap, not infinity; nothing against nothing is 0 and stays hidden.
local MAX_PERCENT = 300
local RANGED_LOCS = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

-- An item's worth to one of a spec's measures, in points of the measure's reference stat; offHand: it is
-- (or would be) in the off hand. A weapon's damage per second has the sim's own weight for where it is:
-- main hand, off hand or ranged slot (0 where the spec does not fight with it: a caster, the paw of Cat
-- and Bear Form, an Arms warrior's off hand).
local function worthTo(measure, link, offHand)
  local stats = itemStats(link)
  local total = 0
  for key, amount in pairs(stats) do
    local w = measure.weights[key]
    if w then total = total + w * amount end
  end
  local dps = stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
  if dps then
    local w
    if RANGED_LOCS[equipLoc(link) or ""] then w = measure.ranged elseif offHand then w = measure.offHand
    else w = measure.mainHand end
    if w and w ~= 0 then total = total + w * dps end
  end
  return total
end

-- For each spec of the player's class, the item against what it is compared with: { { spec, parts } },
-- a part per measure (damage; survival and threat for a tank; healing for a healer): { kind, percent } always.
-- Past MAX_PERCENT either way it caps at ">300%"/"<-300%" (capped = true): a ring worth 0.15
-- against nothing reads ">300%", not "+29817%". An empty slot (old 0, new something) is the same
-- cap, not infinity; nothing against nothing is 0 and stays hidden via changesNothing.
-- slots: the slot of each item in against; offHand: the item would go into the off hand.
-- The measures a spec is rated on; constant lists (they used to be built per spec on every
-- hover): a tank's two, a healer's one, a damage spec's one.
local TANK_MEASURES = { "survival", "threat" }
local HEAL_MEASURES = { "healing" }
local DAMAGE_MEASURES = { "damage" }

function M.SpecRatings(link, against, slots, offHand)
  local class = charClass()
  local specs = type(class) == "string" and M.SPECS and M.SPECS[class]
  if not specs then return nil end
  local out = {}
  for _, spec in ipairs(specs) do
    local row = { spec = spec, parts = {} }
    local measures
    if spec.role == "tank" then measures = TANK_MEASURES
    elseif spec.role == "healing" then measures = HEAL_MEASURES
    else measures = DAMAGE_MEASURES end
    for _, kind in ipairs(measures) do
      local measure = spec[kind]
      local new, old = worthTo(measure, link, offHand), 0
      for i, worn in ipairs(against or {}) do old = old + worthTo(measure, worn, slots and slots[i] == 17) end
      local part = { kind = kind, reference = measure.reference }
      if measure.approximate then part.approx = true end
      if math.abs(old) > 0.05 then
        local p = (new - old) / math.abs(old) * 100
        if p > MAX_PERCENT then part.percent, part.capped = MAX_PERCENT, true
        elseif p < -MAX_PERCENT then part.percent, part.capped = -MAX_PERCENT, true
        else part.percent = p end
      elseif new > 0.05 then
        part.percent, part.capped = MAX_PERCENT, true -- empty slot / worn worth nothing: past the cap
      elseif new < -0.05 then
        part.percent, part.capped = -MAX_PERCENT, true
      else
        part.percent = 0
      end
      row.parts[#row.parts + 1] = part
    end
    out[#out + 1] = row
  end
  return out
end
M.SpecRatings = memoized(M.SpecRatings)

local function coloured(v, text)
  local colour = v > 0.05 and "|cff4dff4d" or v < -0.05 and "|cffff5959" or "|cffb3b3b3"
  return colour .. text .. "|r"
end

-- What a tank's two numbers are for, and a damage spec's one: terse, so it cannot read
-- as the character's own damage going up ("+52% damage"). "60% better dmg spec".
-- A healer's part is a score of the heuristic model (Weights.lua), not an actual healing gain,
-- and ratingText marks it "(approx.)".
local MEASURE_WORDS = { damage = "dmg spec", survival = "for survival", threat = "for threat gen.",
  healing = "healer score" }

-- A number to one decimal under 10, whole from 10 up, and no ".0" on a whole number: "+8 Agility", as
-- the stat line says it, and 9.96 is "10", not "10.0".
local function shortNumber(n, sign)
  local fmt = (math.abs(n) < 10) and "%.1f" or "%.0f"
  return (string.format(sign and ("%+" .. fmt:sub(2)) or fmt, n):gsub("%.0$", ""))
end

-- A rating in words, always a percentage: "25% better dmg spec", "12% worse for survival".
-- Past the cap it reads ">300% ..."/"<-300% ...": a ring worth 0.15 against nothing,
-- an empty slot, or a change past MAX_PERCENT. No points currency ("like +8 Agility").
-- A heuristic part (the healer's) is marked "(approx.)": an approximate item score, not a
-- measured gain.
local function ratingText(part)
  local v = part.percent or 0
  local what = MEASURE_WORDS[part.kind]
  local word = (v > 0 and "better" or "worse") .. (what and (" " .. what) or "")
  local approx = part.approx and " (approx.)" or ""
  if part.capped then
    return coloured(v, (v > 0 and ">" or "<-") .. MAX_PERCENT .. "% " .. word .. approx)
  end
  return coloured(v, shortNumber(math.abs(v)) .. "% " .. word .. approx)
end

local ICONS = {
  armor = "Interface\\Icons\\INV_Chest_Chain_05", ap = "Interface\\Icons\\Ability_Warrior_BattleShout",
  crit = "Interface\\Icons\\Ability_CriticalStrike", dodge = "Interface\\Icons\\Ability_Rogue_Feint",
  health = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", mana = "Interface\\Icons\\INV_Potion_76",
  spellcrit = "Interface\\Icons\\Spell_Fire_FlameBolt", regen = "Interface\\Icons\\INV_Drink_07",
  hit = "Interface\\Icons\\Ability_Hunter_SniperShot", haste = "Interface\\Icons\\Spell_Nature_Bloodlust",
  expertise = "Interface\\Icons\\Ability_Warrior_Revenge", parry = "Interface\\Icons\\Ability_Parry",
  block = "Interface\\Icons\\Ability_Defend", blockvalue = "Interface\\Icons\\INV_Shield_05",
  defense = "Interface\\Icons\\Ability_Warrior_ShieldWall",
  healing = "Interface\\Icons\\Spell_Holy_Heal", spellpower = "Interface\\Icons\\Spell_Nature_Lightning",
}
M.ICONS = ICONS
local DIVIDER = "|TInterface\\Common\\UI-TooltipDivider-Transparent:8:200|t"

-- An icon in a line of text, its baked-in border trimmed.
local function icon(path, size)
  size = size or 14
  return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", path, size, size)
end
M.IconText = icon

-- A rating that changes nothing: what ratingText shows as 0%.
local function changesNothing(part) return math.abs(part.percent or 0) < 0.05 end

-- The ratings with something to say: a spec the item changes nothing for is left out, and so is a
-- tank's number that stays the same. { { spec, parts } }, possibly empty.
local function worthSaying(ratings)
  local out = {}
  for _, r in ipairs(ratings) do
    local parts = {}
    for _, part in ipairs(r.parts) do
      if not changesNothing(part) then parts[#parts + 1] = part end
    end
    if #parts > 0 then out[#out + 1] = { spec = r.spec, parts = parts } end
  end
  return out
end

-- The divider and the specs' ratings, if any of them changes. A spec that changes nothing has no line,
-- and a healer is among the specs since druid Restoration was rated (its line is marked "(approx.)").
local function specLines(lines, ratings)
  ratings = worthSaying(ratings)
  if #ratings == 0 then return end
  lines[#lines + 1] = { DIVIDER, 1, 1, 1 } -- the specs' ratings apart from the stats
  if settings and settings.icons then
    local parts = {}
    for _, r in ipairs(ratings) do
      -- one icon per spec (two icons side by side were drawn over each other in game)
      local measures = {}
      for _, part in ipairs(r.parts) do
        measures[#measures + 1] = ratingText(part)
      end
      parts[#parts + 1] = { text = icon(r.spec.icon) .. " " .. r.spec.name .. ": " .. table.concat(measures, ", "),
        long = #r.parts > 1 }
    end
    -- a long rating on a line of its own (a tank's two numbers, "better (like +8 Agility)"), the other
    -- specs two to a line
    local row = {}
    for _, part in ipairs(parts) do
      if part.long then
        -- a short one waiting for its pair goes first, so the specs keep the class's order
        if #row > 0 then lines[#lines + 1] = { row[1], 1, 1, 1 }; row = {} end
        lines[#lines + 1] = { part.text, 1, 1, 1 }
      else
        row[#row + 1] = part.text
        if #row == 2 then lines[#lines + 1] = { table.concat(row, "     "), 1, 1, 1 }; row = {} end
      end
    end
    if #row > 0 then lines[#lines + 1] = { row[1], 1, 1, 1 } end
  else
    for _, r in ipairs(ratings) do
      local words = {}
      for _, part in ipairs(r.parts) do words[#words + 1] = ratingText(part) end
      lines[#lines + 1] = { "  " .. r.spec.name .. ": " .. table.concat(words, ", "), 0.8, 0.8, 0.8 }
    end
  end
end

local function itemName(link)
  return (type(link) == "string" and link:match("%[(.-)%]")) or "?"
end

-- The slot words a comparison block names ("Finger slot 1"): a ring or a trinket compares
-- with each worn slot and gets one block per slot, and without the slot's name the two
-- blocks read as one repeated ("Against Woven Belt", "Against Woven Belt") and look like a
-- bug in the tooltip. Only these two locations have two blocks to tell apart.
local SLOT_WORDS = {
  [11] = "Finger slot 1", [12] = "Finger slot 2",
  [13] = "Trinket slot 1", [14] = "Trinket slot 2",
}

-- The block's slot as it follows the item's name ("Against Woven Belt (Finger slot 1)"),
-- or "" where the words would say nothing (a chest has one slot; a two-hander's block
-- already joins the two hands with " + "). An empty block names its slot when the tooltip
-- is nothing but empty slots -- two bare "an empty slot" blocks read as one repeated again
-- -- but not beside a named one, where "Against an empty slot" is clear as it stands.
local function slotLabel(c, allEmpty)
  local slots = c.againstSlots
  if type(slots) ~= "table" or #slots ~= 1 then return "" end
  local word = SLOT_WORDS[slots[1]]
  if not word then return "" end
  if #c.against == 0 and not allEmpty then return "" end
  return " (" .. word .. ")"
end

-- Whether the game's inspect window is open on someone else's character: the tooltip being
-- built then carries THEIR item, and every comparison in it is against OUR gear. The
-- inspect UI is not one shape on every client (Forever's Blizzard_InspectUI raises
-- InspectFrame, older builds name the doll InspectPaperDollFrame, newer APIs hang the frame
-- off C_InspectUI), so each shape is asked for its own IsShown; anything absent, or not a
-- frame that answers, reads false and nothing is assumed to exist.
local function frameShown(frame)
  return type(frame) == "table" and type(frame.IsShown) == "function" and ask(frame.IsShown, frame) == true
end

local function inspecting()
  local ok, shown = pcall(function()
    if frameShown(InspectFrame) or frameShown(InspectPaperDollFrame) then return true end
    local cui = C_InspectUI
    return type(cui) == "table" and frameShown(cui.InspectFrame)
  end)
  return ok and shown == true
end

-- The spec and measure the item is most worth to: the largest percentage of the ratings'
-- parts that change anything. nil when it changes nothing for every spec.
local function bestPart(ratings)
  local best
  for _, r in ipairs(ratings) do
    for _, part in ipairs(r.parts) do
      if not changesNothing(part) and (not best or (part.percent or 0) > (best.percent or 0)) then
        best = part
      end
    end
  end
  return best
end

-- The small stream arrows BagMarkers paints on a bag button's corner, in a line of text.
-- UI-MicroStream-Green ships pointing down (a download chevron), so the up arrow's |T
-- escape mirrors it vertically (the top and bottom texels swapped) and its tip points up;
-- UI-MicroStream-Red is used as shipped, tip down. The texels are normalized (0..1), so the
-- whole file draws whatever its size is.
local ARROW_UP = "|TInterface\\Buttons\\UI-MicroStream-Green:12:12:0:0:1:1:0:1:1:0|t"
local ARROW_DOWN = "|TInterface\\Buttons\\UI-MicroStream-Red:12:12:0:0:1:1:0:1:0:1|t"

-- The at-a-glance line for a tooltip carrying someone else's item: which way it goes against
-- our own gear, and the best spec's number behind it ("Better than your gear (best spec:
-- 25% better dmg spec)").
local function gearLine(part)
  local v = part.percent or 0
  local arrow, word = ARROW_UP, "Better than your gear"
  if v < 0 then arrow, word = ARROW_DOWN, "Worse than your gear" end
  return arrow .. " " .. coloured(v, word) .. " (best spec: " .. ratingText(part) .. ")"
end

---------------------------------------------------------------------------------------------
-- Tank caps (independent of WorthParts): whether the character is uncrittable (440 defense
-- skill vs a boss +3) and how far its avoidance is from 102.4% (miss+dodge+parry+block).
-- Shown when it matters: the player has a tank spec in M.SPECS, or the item itself carries
-- defensive stats. Every number comes from the client's live APIs behind ask/pcall with an
-- isSecret guard; when no API answers, the line is left out entirely (fail silent, nothing
-- guessed). English throughout, colours as the rest (UP green when capped, DOWN red below).
---------------------------------------------------------------------------------------------

local UNCRITTABLE_DEFENSE = 440
local AVOIDANCE_CAP = 102.4

-- Item keys that make the item itself tank-relevant (defense/dodge/parry/block families,
-- including flat defense skill and block value as block family).
local TANK_STATS = {
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = true,
  ITEM_MOD_DEFENSE_SKILL_SHORT = true,
  ITEM_MOD_DODGE_RATING_SHORT = true,
  ITEM_MOD_PARRY_RATING_SHORT = true,
  ITEM_MOD_BLOCK_RATING_SHORT = true,
  ITEM_MOD_BLOCK_VALUE_SHORT = true,
}

-- Whether the player's class has a tank spec in M.SPECS (Druid Bear, Paladin Protection,
-- Warrior Protection). Guarded like SpecRatings (ask + pcall); a secret class fails silent.
local function hasTankSpec()
  local class = charClass()
  if type(class) ~= "string" or isSecret(class) then return false end
  local specs = M.SPECS and M.SPECS[class]
  if type(specs) ~= "table" then return false end
  for _, s in ipairs(specs) do
    if type(s) == "table" and s.role == "tank" then return true end
  end
  return false
end

local function itemHasTankStats(link)
  local stats = itemStats(link)
  if type(stats) ~= "table" then return false end
  for k, v in pairs(stats) do
    if TANK_STATS[k] and type(v) == "number" and not isSecret(v) and v ~= 0 then return true end
  end
  return false
end

-- The character's current defense skill, or nil when no API answers (fail silent).
-- Forever exposes it as UnitDefenseSkill, Classic Era as UnitDefense (base +
-- modifier); each tried behind ask/pcall with an isSecret guard. GetDefense()
-- does not exist as a callable API and is never invented here.
local UnitDefenseFn = UnitDefenseSkill or UnitDefense
local function tankDefenseSkill()
  return tankRead("def", function()
    local a, b = ask(UnitDefenseFn, "player")
    if isSecret(a) or isSecret(b) then return nil end
    if type(a) == "number" and type(b) == "number" then return a + b end
    if type(a) == "number" then return a end
    return nil
  end)
end

-- Miss chance vs a boss +3 from defense skill and level: 5% base plus 0.04% per point of
-- (defense - boss weapon skill), boss skill = (level+3)*5. Needs both defense and a sane
-- UnitLevel("player"); otherwise nil (the caller then shows dodge+parry+block only).
local function tankMissChance(defense)
  if type(defense) ~= "number" or defense ~= defense then return nil end
  local lvl = tankLevel()
  if not lvl or lvl <= 0 then return nil end
  local miss = 5 + (defense - (lvl + 3) * 5) * 0.04
  if miss ~= miss or miss == math.huge or miss == -math.huge then return nil end
  if miss < 0 then miss = 0 end
  return miss
end

local function wholeText(v)
  if v == math.floor(v) then return string.format("%d", v) end
  return string.format("%.1f", v)
end

-- The tank lines for link: {} when nothing can be said honestly. Gate: a tank-spec player
-- sees them on any item; anyone else only on a defensive item. Each line needs its own API:
-- Uncrittable needs defense skill; Avoidance needs dodge+parry+block (all three, live
-- GetDodgeChance/GetParryChance/GetBlockChance) plus optionally miss (defense+level).
local function tankExtraLines(link)
  if type(link) ~= "string" or isSecret(link) then return {} end
  if not hasTankSpec() and not itemHasTankStats(link) then return {} end
  local out = {}
  local def = tankDefenseSkill()
  if type(def) == "number" and def == def and def ~= math.huge and def ~= -math.huge then
    -- Uncrittable target scales with level (boss +3: level*5 + 140, i.e. 440 at 60);
    -- without a sane level the fixed 440 stands in as the level-60 reference.
    local lvl = tankLevel()
    local target = (lvl and lvl > 0) and (lvl * 5 + 140) or UNCRITTABLE_DEFENSE
    local need = target - def
    if need < 0 then need = 0 end
    local text = "Uncrittable: " .. wholeText(def) .. "/" .. wholeText(target) .. " (need " .. wholeText(need) .. ")"
    out[#out + 1] = { ((def >= target) and UP or DOWN) .. text .. "|r", 1, 1, 1 }
  end
  local dodge = tankRead("dodge", function() return num(ask(GetDodgeChance)) end)
  local parry = tankRead("parry", function() return num(ask(GetParryChance)) end)
  local block = tankRead("block", function() return num(ask(GetBlockChance)) end)
  if dodge and parry and block then
    local miss = (def ~= nil) and tankMissChance(def) or nil
    local total, text
    if miss then
      total = miss + dodge + parry + block
      text = string.format("Avoidance: %.2f%% / 102.4%% (miss+dodge+parry+block)", total)
    else
      total = dodge + parry + block
      text = string.format("Avoidance: %.2f%% / 102.4%% (dodge+parry+block, no miss)", total)
    end
    out[#out + 1] = { ((total + 1e-9 >= AVOIDANCE_CAP) and UP or DOWN) .. text .. "|r", 1, 1, 1 }
  end
  return out
end

-- The names of the items a comparison is against, joined as the heading names them
-- ("Worn Band + Old Loop"): one helper, no closure per comparison block.
local function namesJoined(links)
  local t = {}
  for i, l in ipairs(links) do t[i] = itemName(l) end
  return table.concat(t, " + ")
end

-- The tooltip lines for link: { text, r, g, b }. gameCompares: the game shows its own comparison beside
-- this tooltip ("If you replace this item, the following stat changes will occur"), so the differences
-- are not repeated. Each block names the slot it is against ("Against Woven Belt (Finger slot 1)"):
-- a ring or trinket gets one block per slot and the same worn item can stand in both. When the
-- tooltip carries someone else's item (the inspect window open) the heading says the comparison is
-- with YOUR gear and the block ends with the up/down arrow and the best spec's number.
function M.TooltipLines(link, gameCompares)
  local lines = {}
  if not (settings and settings.compare) then return lines end
  local comps = M.Compare(link) or {}
  -- Nothing of ours in any slot: the empty blocks then name their slots as well.
  local allEmpty = true
  for _, c in ipairs(comps) do
    if #c.against > 0 then allEmpty = false end
  end
  local foreign = inspecting()
  for _, c in ipairs(comps) do
    local against = #c.against > 0 and namesJoined(c.against) or "an empty slot"
    against = against .. slotLabel(c, allEmpty)
    local head = (foreign and "Compared with your gear: " or "Against ") .. against
    -- The differences, unless the tooltip has them already: the game's own comparison, or an empty slot,
    -- where they are the item's own stats.
    local showDiffs = #c.against > 0 and not gameCompares
    if settings.icons then
      lines[#lines + 1] = { head, 0.4, 0.73, 1 }
      if showDiffs and #c.diffs == 0 then lines[#lines + 1] = { "the same stats", 0.7, 0.7, 0.7 } end
      -- the differences, three to a line, and below them what they give, summed, with icons
      local row, sums, order = {}, {}, {}
      for i, d in ipairs(c.diffs) do
        row[#row + 1] = coloured(d.diff, signed(d.diff) .. " " .. (statName(d.key) or d.key))
        if #row == 3 or i == #c.diffs then
          if showDiffs then lines[#lines + 1] = { table.concat(row, "   "), 1, 1, 1 } end
          row = {}
        end
        if settings.worth then
          local parts = M.WorthParts(d.key, d.diff)
          -- the item's own armor too, so the armor icon's total agrees with the Armor line (+50 Armor and
          -- +4 Agility's +8 armor are +58, not +8)
          if d.key == "RESISTANCE0_NAME" then parts = { { kind = "armor", value = d.diff } } end
          for _, p in ipairs(parts) do
            if not sums[p.kind] then order[#order + 1] = p.kind end
            sums[p.kind] = (sums[p.kind] or 0) + p.value
          end
        end
      end
      local worth = {}
      for _, kind in ipairs(order) do
        if sums[kind] ~= 0 and (not PERCENT_KINDS[kind] or worthShowing(sums[kind])) then
          worth[#worth + 1] = icon(ICONS[kind], 12) .. " " .. bySign(sums[kind], worthValue(kind, sums[kind]) .. " " .. WORTH_SHORT[kind])
        end
        if #worth == 3 then -- three to a line
          lines[#lines + 1] = { table.concat(worth, "   "), 0.7, 0.7, 0.7 }
          worth = {}
        end
      end
      if #worth > 0 then lines[#lines + 1] = { table.concat(worth, "   "), 0.7, 0.7, 0.7 } end
    else
      lines[#lines + 1] = { foreign and head or (head .. ":"), 0.4, 0.73, 1 }
      if showDiffs and #c.diffs == 0 then
        lines[#lines + 1] = { "  the same stats", 0.7, 0.7, 0.7 }
      end
      for _, d in ipairs(c.diffs) do
        local up = d.diff > 0
        local worth = settings.worth and M.Worth(d.key, d.diff, true)
        local stat = signed(d.diff) .. " " .. (statName(d.key) or d.key)
        if showDiffs then
          lines[#lines + 1] = { "  " .. stat, up and 0.3 or 1, up and 1 or 0.35, up and 0.3 or 0.35 }
          if worth then lines[#lines + 1] = { "      " .. worth, 0.7, 0.7, 0.7 } end
        elseif worth then -- the stat only to say what its worth is of
          lines[#lines + 1] = { "  " .. bySign(d.diff, stat) .. ": " .. worth, 0.7, 0.7, 0.7 }
        end
      end
    end
    -- The specs' ratings, and for someone else's item the up/down line in front of them:
    -- the arrow and the best spec's number. The ratings are measured for the arrow even
    -- when the specs' own lines are switched off.
    local ratings = (settings.specs or foreign) and M.SpecRatings(link, c.against, c.slots, c.offHand)
    if ratings then
      if foreign then
        local best = bestPart(ratings)
        if best then lines[#lines + 1] = { gearLine(best), 1, 1, 1 } end
      end
      if settings.specs then specLines(lines, ratings) end
    end
  end
  -- Tank caps: one independent section after the comparisons (once per tooltip, not per
  -- worn slot), only when the gate holds and an API answers. A pcall keeps a throwing
  -- client from costing the tooltip; on error nothing is added.
  do
    local ok, extra = pcall(tankExtraLines, link)
    if ok and type(extra) == "table" and #extra > 0 then
      -- No stacked dividers: specLines may have closed with its own.
      if #lines > 0 and lines[#lines][1] ~= DIVIDER then lines[#lines + 1] = { DIVIDER, 1, 1, 1 } end
      for _, l in ipairs(extra) do lines[#lines + 1] = l end
    end
  end
  return lines
end
M.TooltipLines = memoized(M.TooltipLines)

-- What add() last put on a tooltip (weak-keyed: pooled tooltips die with their frame): the
-- client can fire the hook twice for the same tooltip without clearing it (a comparison
-- refresh), which would add the whole block a second time and compute it a second time.
local addedTo = setmetatable({}, { __mode = "k" })

local function hookTooltips()
  local function add(tooltip)
    if not (tooltip == GameTooltip or tooltip == ItemRefTooltip) then return end
    local _, link = ask(tooltip.GetItem, tooltip)
    if type(link) ~= "string" or isSecret(link) then return end
    -- One build per tooltip and link within a frame: skipped when the tooltip still holds
    -- the lines just added (NumLines has not gone back down), taken again after a clear --
    -- a tooltip rebuilt in the same frame is a new build and gets its lines again. Without
    -- GetTime or NumLines (a minimal client) nothing is skipped: the old behavior.
    local t = ask(GetTime)
    local rec = addedTo[tooltip]
    if type(t) == "number" and rec and rec.link == link and rec.t == t then
      local n = ask(tooltip.NumLines, tooltip)
      if n == nil or (rec.lines and n >= rec.lines) then return end
    end
    -- the game compares by itself when the setting says so, or while Shift is held
    local gameCompares = TooltipUtil and ask(TooltipUtil.ShouldDoItemComparison, tooltip) == true
    -- A throwing client anywhere in the comparison must not cost the tooltip.
    local ok, out = pcall(M.TooltipLines, link, gameCompares)
    if not ok or type(out) ~= "table" then return end
    for _, line in ipairs(out) do tooltip:AddLine(line[1], line[2], line[3], line[4]) end
    if type(t) == "number" then
      addedTo[tooltip] = { link = link, t = t, lines = ask(tooltip.NumLines, tooltip) }
    end
  end
  if type(TooltipDataProcessor) == "table" and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
    and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, add)
  elseif GameTooltip and type(GameTooltip.HookScript) == "function" then
    GameTooltip:HookScript("OnTooltipSetItem", add)
  end
end

---------------------------------------------------------------------------------------------
-- /bit probe: what this client reports, for the breakdown
---------------------------------------------------------------------------------------------

-- Functions the breakdown could be built on; the probe records which of them exist.
local PROBED_FUNCTIONS = {
  "GetCritChance", "GetRangedCritChance", "GetSpellCritChance", "GetDodgeChance", "GetParryChance",
  "GetBlockChance", "GetShieldBlock", "GetHitModifier", "GetSpellHitModifier", "GetCritChanceFromAgility",
  "GetSpellCritChanceFromIntellect", "GetAttackPowerForStat", "GetUnitHealthModifier",
  "GetUnitMaxHealthModifier", "GetManaRegen", "GetPowerRegen", "GetCombatRating", "GetCombatRatingBonus",
  "GetCombatRatingBonusForCombatRatingValue", "GetSpellBonusDamage", "GetSpellBonusHealing", "UnitStat", "UnitArmor", "UnitAttackPower",
  "UnitRangedAttackPower", "UnitDefense", "UnitDefenseSkill", "UnitResistance", "UnitClass", "UnitLevel", "GetShapeshiftFormID",
  "GetItemStats", "GetInventoryItemLink",
  "GetCritChanceFromStat", "GetSpellCritChanceFromStat", "GetDodgeChanceFromAttribute", "UnitHPPerStamina",
  "GetManaRegenFromSpirit", "GetRangedAttackPowerForStat",
}

local function plain(v)
  if isSecret(v) then return "<secret>" end
  if type(v) == "number" or type(v) == "string" or type(v) == "boolean" then return v end
  return v == nil and "<nil>" or ("<" .. type(v) .. ">")
end

local function record(fn, ...)
  if type(fn) ~= "function" then return "<no function>" end
  local out = { pcall(fn, ...) }
  if not out[1] then return "<error: " .. tostring(out[2]) .. ">" end
  local values = {}
  for i = 2, #out do values[#values + 1] = plain(out[i]) end
  return values
end

function M.Probe()
  local p = {}
  local build, buildNumber = ask(GetBuildInfo)
  p.build = tostring(build) .. "." .. tostring(buildNumber)
  p.locale = ask(GetLocale)
  p.level = plain(ask(UnitLevel, "player"))
  local _, class = ask(UnitClass, "player")
  p.class = class
  local _, race = ask(UnitRace, "player")
  p.race = race
  p.inCombat = plain(ask(InCombatLockdown))
  p.form = plain(ask(GetShapeshiftFormID))
  p.functions = {}
  for _, name in ipairs(PROBED_FUNCTIONS) do p.functions[name] = type(_G[name]) end
  p.functions["C_Item.GetItemStats"] = type(C_Item and C_Item.GetItemStats)
  p.functions["C_PaperDollInfo"] = type(C_PaperDollInfo)
  p.functions["C_TooltipInfo.GetInventoryItem"] = type(C_TooltipInfo and C_TooltipInfo.GetInventoryItem)

  local v = {}
  for i = 1, 5 do v["UnitStat" .. i] = record(UnitStat, "player", i) end
  v.UnitHealthMax = record(UnitHealthMax, "player")
  v.UnitPowerMax0 = record(UnitPowerMax, "player", 0)
  v.UnitArmor = record(UnitArmor, "player")
  v.UnitAttackPower = record(UnitAttackPower, "player")
  v.UnitRangedAttackPower = record(UnitRangedAttackPower, "player")
  v.UnitDefense = record(UnitDefense, "player")
  v.GetCritChance = record(GetCritChance)
  v.GetRangedCritChance = record(GetRangedCritChance)
  for school = 1, 7 do v["GetSpellCritChance" .. school] = record(GetSpellCritChance, school) end
  v.GetDodgeChance = record(GetDodgeChance)
  v.GetParryChance = record(GetParryChance)
  v.GetBlockChance = record(GetBlockChance)
  v.GetHitModifier = record(GetHitModifier)
  v.GetSpellHitModifier = record(GetSpellHitModifier)
  v.GetCritChanceFromAgility = record(GetCritChanceFromAgility, "player")
  v.GetSpellCritChanceFromIntellect = record(GetSpellCritChanceFromIntellect, "player")
  for stat = 1, 2 do v["GetAttackPowerForStat" .. stat .. "_10"] = record(GetAttackPowerForStat, stat, 10) end
  v.GetCritChanceFromStat2_10 = record(GetCritChanceFromStat, 2, 10)
  v.GetSpellCritChanceFromStat4_10 = record(GetSpellCritChanceFromStat, 4, 10)
  v.GetDodgeChanceFromAttribute = record(GetDodgeChanceFromAttribute)
  v.UnitHPPerStamina = record(UnitHPPerStamina, "player")
  v.GetUnitHealthModifier = record(GetUnitHealthModifier, "player")
  v.GetManaRegen = record(GetManaRegen)
  v.GetSpellBonusDamage2 = record(GetSpellBonusDamage, 2)
  v.GetSpellBonusHealing = record(GetSpellBonusHealing)
  p.values = v

  p.items = {}
  for slot = 1, 19 do
    local link = equipped(slot)
    if link then
      local item = { link = link, stats = {} }
      for k, n in pairs(itemStats(link)) do item.stats[k] = n end
      local data = ask(C_TooltipInfo and C_TooltipInfo.GetInventoryItem, "player", slot)
      if type(data) == "table" and type(data.lines) == "table" then
        item.lines = {}
        for _, line in ipairs(data.lines) do
          local left = line.leftText
          if type(left) == "string" and not isSecret(left) then item.lines[#item.lines + 1] = left end
        end
      end
      p.items[slot] = item
    end
  end

  local db = BIT.DB()
  if type(db.probes) ~= "table" then db.probes = {} end
  db.probes[#db.probes + 1] = p
  local count = 0
  for _ in pairs(p.items) do count = count + 1 end
  BIT.Say(string.format("probe %d recorded (%s level %s, %d equipped items). It is saved at logout or /reload.",
    #db.probes, tostring(class), tostring(p.level), count))
  return p
end

BIT.RegisterCommand("probe", function() M.Probe() end)

---------------------------------------------------------------------------------------------
-- Start, and the settings tab
---------------------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
  if event == "ADDON_LOADED" then
    if name ~= BIT.name then return end
    self:UnregisterEvent("ADDON_LOADED")
    if not BIT.ShouldRun("StatsInfo") then self:UnregisterAllEvents() return end
    settings = BIT.Settings("StatsInfo", DEFAULTS)
    M.settings = settings
    BIT.DB().statsLearned = nil -- what 0.4.x measured in play; the game's own numbers replace it
  elseif event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    -- The tank caps' numbers move with gear, buffs, form and level: on those events the
    -- short-lived cache (tankRead above) is dropped and the next hover reads them live again.
    self:RegisterUnitEvent("UNIT_AURA", "player")
    self:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    self:RegisterEvent("PLAYER_LEVEL_UP")
    hookTooltips()
  else
    tankForget()
  end
end)

-- A settings-only sample: an explicit mock item tooltip with this module's own lines on it,
-- not the live GameTooltip and not the character's gear. The preview is static on purpose
-- (the policy DoTInfo's buildDoTPreview follows): every number below is hardcoded, no live
-- API is ever read for it, and it measures nothing and hooks nothing.

-- The sample item and its numbers, fixed: an item against an empty slot, so the worth line
-- carries the whole story ("Against an empty slot: +30 health +45 mana").
local SAMPLE = {
  title = "Embossed Leather Vest (sample)",
  itemLines = {
    { "Item Level 28", 0.5, 0.5, 0.5 },
    { "120 Armor", 1, 1, 1 },
    { "+3 Stamina", 1, 1, 1 },
    { "+3 Intellect", 1, 1, 1 },
  },
  against = "an empty slot",
  stats = {
    { stat = "+3 Stamina", worth = "+30 health", kind = "health" },
    { stat = "+3 Intellect", worth = "+45 mana", kind = "mana" },
  },
  specs = {
    { icon = "Interface\\Icons\\Spell_Shadow_DeathCoil", name = "Affliction", rating = ">300% better dmg spec" },
    { icon = "Interface\\Icons\\Spell_Shadow_RainOfFire", name = "Destruction", rating = "25% better dmg spec" },
  },
}

-- The mock tooltip's lines under the current settings: TooltipLines' own shapes, on the
-- hardcoded numbers above. { text, r, g, b }; the divider and the icon escapes are the ones
-- the real lines carry.
local function sampleLines(iconSize)
  local s = settings or DEFAULTS
  local out = {}
  local function add(text, r, g, b) out[#out + 1] = { text = text, r = r, g = g, b = b } end
  add(SAMPLE.title, 1, 1, 1)
  for _, l in ipairs(SAMPLE.itemLines) do add(l[1], l[2], l[3], l[4]) end
  if s.compare then
    add(DIVIDER, 1, 1, 1)
    if s.icons then
      add("Against " .. SAMPLE.against, 0.4, 0.73, 1)
      if s.worth then
        local row = {}
        for _, d in ipairs(SAMPLE.stats) do
          row[#row + 1] = icon(ICONS[d.kind], iconSize) .. " " .. UP .. d.worth .. "|r"
        end
        add(table.concat(row, "   "), 0.7, 0.7, 0.7)
      end
    else
      add("Against " .. SAMPLE.against .. ":", 0.4, 0.73, 1)
      for _, d in ipairs(SAMPLE.stats) do
        if s.worth then
          add("  " .. UP .. d.stat .. "|r: " .. UP .. d.worth .. "|r", 0.7, 0.7, 0.7)
        else
          add("  " .. UP .. d.stat .. "|r", 1, 1, 1)
        end
      end
    end
  end
  if s.specs then
    add(DIVIDER, 1, 1, 1)
    for _, r in ipairs(SAMPLE.specs) do
      if s.icons then
        add(icon(r.icon, iconSize) .. " " .. r.name .. ": " .. r.rating, 1, 1, 1)
      else
        add("  " .. r.name .. ": " .. r.rating, 0.8, 0.8, 0.8)
      end
    end
  end
  return out
end

-- The mock tooltip inside scene: a dark tooltip card, and under it a bag button mock with
-- the green up arrow and the beneficiary spec's icon. The arrow is the game's own small
-- stream arrow -- Interface\Buttons\UI-MicroStream-Green, the same file BagMarkers paints in
-- a real bag button's corner -- not the old WHITE8X8 pieces (commit 221cdee moved the bag
-- and quest badges to the Blizzard arrows; the mock follows). scene.tipLines and the bag's
-- corner badge are re-laid-out by renderMockTooltip on every change.
local TIP_LINES = 12 -- the sample never needs more; the pool is padded with blanks
local function buildMockTooltip(scene)
  local tip = CreateFrame("Frame", nil, scene, "BackdropTemplate")
  BIT.UI.Backdrop(tip, 0.09, 0.98)
  scene.tip = tip
  scene.tipLines = {}
  for i = 1, TIP_LINES do
    local line = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line:SetJustifyH("LEFT")
    scene.tipLines[i] = line
  end
  local bag = CreateFrame("Frame", nil, scene)
  bag:SetSize(32, 32)
  scene.bag = bag
  local face = bag:CreateTexture(nil, "BACKGROUND")
  face:SetAllPoints()
  face:SetTexture("Interface\\Icons\\INV_Chest_Leather_01")
  face:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  scene.bagFace = face
  -- The corner badge exactly as BagMarkers' paintContents builds it: one MARKER x MARKER box
  -- in the button's TOPRIGHT corner with the arrow in it, and the beneficiary icon and the
  -- +N cue inside the corner below. UI-MicroStream-Green ships pointing DOWN (a download
  -- chevron), so the UP arrow mirrors the texture vertically with SetTexCoord (top and
  -- bottom swapped). The file carries the Blizzard green itself: the vertex colour stays
  -- white, never the tooltip's tint. The spec icon is shown too, so the arrow sits one
  -- icon-width left of it (ARROW_SHIFT in BagMarkers).
  local badge = CreateFrame("Frame", nil, bag)
  badge:EnableMouse(false)
  badge:SetSize(24, 24)
  scene.bagBadge = badge
  local arrow = badge:CreateTexture(nil, "OVERLAY")
  arrow:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
  arrow:SetTexCoord(0, 1, 1, 0) -- mirrored vertically: tip up
  arrow:SetVertexColor(1, 1, 1, 1)
  arrow:SetSize(24, 24)
  scene.arrow = arrow
  local specIcon = badge:CreateTexture(nil, "OVERLAY")
  specIcon:SetSize(12, 12)
  specIcon:SetTexture(SAMPLE.specs[1].icon)
  scene.bagSpecIcon = specIcon
  local plusN = badge:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  plusN:SetText("+1")
  scene.bagPlusN = plusN
  scene.caption = scene:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  scene.caption:SetJustifyH("LEFT")
  scene.caption:SetText("on a bag button: green up for Affliction and one more spec -- "
    .. "the game's own stream arrow")
end

-- The mock tooltip redrawn at a style: font size, scale and opacity all show here, whether
-- they come from the shared appearance editor (UI.Appearance) or from the TRY IT sliders.
-- Pure layout over the hardcoded sample: no live API, no settings writes.
--   font size  every font in the mock, and the heights the rows and the title are measured at
--   scale      the card's width, the rows' line boxes, the bag button mock and its badge
--   opacity    the rows, the caption, the title and the whole bag button mock
--
-- The card keeps one fixed height at every font and scale: the rows wrap inside it and the
-- ones that do not fit are dropped, so the scene can never stretch over the pane and push the
-- TRY IT sliders and the buttons below it around. The style is clamped here as well -- the
-- shared appearance editor's own bounds (fontSize 6..48, scale 0.1..10) are wider than what
-- the sample can draw legibly, and a stored 48px font must not run off the card either.
local SCENE_HEIGHT = 280
local MIN_FONT, MAX_FONT = 6, 24
local MIN_SCALE, MAX_SCALE = 0.5, 2
-- The bag button mock's corner badge, the geometry BagMarkers paints in a real button's
-- corner: a MARKER x MARKER box at the button's TOPRIGHT holding the arrow, with the
-- ICON x ICON beneficiary icon inside the corner and the +N cue under it. All of it is
-- scaled with the button mock, so the Scale slider zooms the badge as it zooms the button.
local MARKER = 24
local ICON = 12
local MARKER_DX, MARKER_DY = -2, -2
local ICON_DX, ICON_DY = -2, -12
local PLUSN_DX, PLUSN_DY = -2, -16
local ARROW_SHIFT = -14 -- the arrow moves left of the icon when the icon is shown

local function clamp(v, lo, hi)
  if type(v) ~= "number" then return lo end
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

local function renderMockTooltip(scene, style)
  style = type(style) == "table" and style or {}
  local fs = clamp(tonumber(style.fontSize) or 12, MIN_FONT, MAX_FONT)
  local scale = clamp(tonumber(style.scale) or 1, MIN_SCALE, MAX_SCALE)
  local opacity = clamp(tonumber(style.opacity) or 1, 0, 1)
  local font = type(style.font) == "string" and style.font or "Fonts\\FRIZQT__.TTF"
  local outline = (style.outline == "NONE" or type(style.outline) ~= "string") and "" or style.outline
  local width = tonumber(ask(scene.GetWidth, scene)) or 336
  scene:SetHeight(SCENE_HEIGHT)
  -- One row's own wrapped height (the client measures the text at its constrained width),
  -- or the font's line height where the client cannot say.
  local function measure(slot, fallback)
    local h = tonumber(ask(slot.GetStringHeight, slot))
    if h and h > 0 then return h end
    return fallback
  end
  -- Every font in the mock is drawn at the clamped font size; every painted part of it is
  -- drawn at the clamped opacity, so the three TRY IT fields are all visible here:
  -- font size moves the text and the heights measured for it, scale moves the card's width,
  -- the rows' line boxes, the button mock and its badge, opacity fades the whole scene.
  if scene.title then
    if BIT.Style and BIT.Style.ApplyText then
      pcall(BIT.Style.ApplyText, scene.title, style, "text")
    end
    scene.title:SetFont(font, fs, outline) -- the clamped size, not the raw style's
    scene.title:ClearAllPoints()
    scene.title:SetPoint("TOPLEFT", 12, -4)
    scene.title:SetPoint("RIGHT", scene, "RIGHT", -12, 0) -- wrapped into the card
    scene.title:SetHeight(fs + 8)
  end
  local titleDepth = scene.title and (measure(scene.title, fs + 8) + 8) or (fs + 16)
  -- The foot of the card first -- the bag button mock and the caption -- so the rows above
  -- can never run into them or past the card.
  local bagSize = clamp(math.floor(32 * scale + 0.5), 16, 48)
  local k = bagSize / 32 -- the button mock's zoom: the corner badge follows the scale
  local badgeSize = math.max(10, math.floor(MARKER * k + 0.5))
  local badgeIcon = math.max(6, math.floor(ICON * k + 0.5))
  local captionFont = clamp(fs - 2, 9, 14)
  local caption = scene.caption
  caption:ClearAllPoints()
  caption:SetPoint("BOTTOMLEFT", scene, "BOTTOMLEFT", 12, 6)
  caption:SetPoint("BOTTOMRIGHT", scene, "BOTTOMRIGHT", -12, 6)
  caption:SetFont(font, captionFont, outline)
  caption:SetTextColor(0.7, 0.7, 0.7, opacity)
  local captionH = measure(caption, captionFont + 2)
  local bagTop = SCENE_HEIGHT - 6 - captionH - 4 - bagSize
  scene.bag:ClearAllPoints()
  scene.bag:SetPoint("TOPLEFT", 12, -bagTop)
  scene.bag:SetSize(bagSize, bagSize)
  scene.bag:SetAlpha(opacity) -- the badge fades with the lines above it
  -- The corner badge, at the button's own zoom: the arrow one icon-width left of the icon,
  -- exactly where BagMarkers puts it on a real button.
  scene.bagBadge:ClearAllPoints()
  scene.bagBadge:SetPoint("TOPRIGHT", scene.bag, "TOPRIGHT", MARKER_DX * k, MARKER_DY * k)
  scene.bagBadge:SetSize(badgeSize, badgeSize)
  scene.arrow:ClearAllPoints()
  scene.arrow:SetPoint("TOPRIGHT", scene.bagBadge, "TOPRIGHT", ARROW_SHIFT * k, 0)
  scene.arrow:SetSize(badgeSize, badgeSize)
  scene.bagSpecIcon:ClearAllPoints()
  scene.bagSpecIcon:SetPoint("TOPRIGHT", scene.bagBadge, "TOPRIGHT", ICON_DX * k, ICON_DY * k)
  scene.bagSpecIcon:SetSize(badgeIcon, badgeIcon)
  scene.bagPlusN:ClearAllPoints()
  scene.bagPlusN:SetPoint("TOPRIGHT", scene.bagBadge, "TOPRIGHT", PLUSN_DX * k, PLUSN_DY * k)
  scene.bagPlusN:SetFont(font, math.max(7, math.floor(10 * k + 0.5)), outline)
  local iconSize = clamp(math.floor(12 * scale + 0.5), 8, 24)
  local lines = sampleLines(iconSize)
  local tip = scene.tip
  tip:ClearAllPoints()
  tip:SetPoint("TOPLEFT", 12, -titleDepth)
  -- The card's width follows the scale (a narrower card at 0.5x wraps the rows into more
  -- lines, a wider one at 2x spreads them out again).
  local cardW = clamp(math.floor(300 * scale + 0.5), 120, math.max(120, width - 24))
  tip:SetWidth(cardW)
  -- The line box a row is laid out in: the row's own wrapped height, never shorter than the
  -- scaled one, so the rows spread apart when the scale grows.
  local rowBox = (fs + 4) * scale
  -- The rows fill the tip from its top and stop above the bag button mock; what does not
  -- fit is dropped instead of spilling over the card and the controls below it.
  local room = bagTop - 2 - titleDepth
  local y = 6
  for i, slot in ipairs(scene.tipLines) do
    local entry = lines[i]
    slot:ClearAllPoints()
    if entry then
      slot:SetText(entry.text)
      slot:SetFont(font, fs, outline)
      slot:SetTextColor(entry.r, entry.g, entry.b, opacity)
      slot:SetPoint("TOPLEFT", tip, "TOPLEFT", 8, -y)
      slot:SetPoint("RIGHT", tip, "RIGHT", -8, 0)
      local h = math.max(measure(slot, fs + 4), rowBox)
      if y + h <= room then
        slot:Show()
        y = y + h
      else
        slot:SetText("")
        slot:Hide()
      end
    else
      slot:SetText("")
      slot:Hide()
    end
  end
  tip:SetHeight(math.max(10, math.min(y + 2, math.max(10, room))))
end

local function buildStatsPreview(parent)
  local scene = CreateFrame("Frame", nil, parent)
  scene:SetSize(560, SCENE_HEIGHT)
  scene.title = scene:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  scene.title:SetText("StatsInfo sample (not your gear)")
  buildMockTooltip(scene)
  return scene
end

local function renderStatsPreview(scene, style)
  renderMockTooltip(scene, style)
end

-- The style the preview draws in: the shared appearance editor's (UI.Appearance) own
-- fields, so changing font size, scale or opacity there -- or in the TRY IT sliders below
-- the preview -- moves the preview.
local function resolvedStyle()
  if BIT.Style and BIT.Style.Resolve then
    local ok, s = pcall(BIT.Style.Resolve, "StatsInfo")
    if ok and type(s) == "table" then return s end
  end
  return {}
end

local previewScene -- the built mock tooltip; redrawn on every settings or style change
local tryItSliders = {} -- the TRY IT slider rows, re-seated on the stored style after a render
local function renderPreview()
  if not previewScene then return end
  renderMockTooltip(previewScene, resolvedStyle())
  -- The thumbs and their value labels always show what the style holds -- including a write
  -- this file never made (the shared appearance editor, a preset, a reset), so a slider can
  -- never look as if it were still on the value it was built at.
  for _, holder in ipairs(tryItSliders) do
    if type(holder.Refresh) == "function" then pcall(holder.Refresh, holder) end
  end
end

local function styleGet(key, fallback)
  return function()
    local v = tonumber(resolvedStyle()[key])
    return v or fallback
  end
end

local function styleSet(key)
  return function(v)
    if BIT.Style and BIT.Style.Set then pcall(BIT.Style.Set, "StatsInfo", key, v) end
    renderPreview()
  end
end

-- Every style write re-renders the preview, whoever made it: these sliders above, or the
-- shared appearance editor, a preset or a reset elsewhere. The same contract the other
-- modules' previews follow (HunterRangeFinder, ShieldsInfo and ResourceDing subscribe too).
if BIT.Style and BIT.Style.Subscribe then
  pcall(BIT.Style.Subscribe, "StatsInfo", function() renderPreview() end)
end

BIT.RegisterTab("StatsInfo", {
  buildPreview = buildStatsPreview,
  previewRender = renderStatsPreview,
  capabilities = { roles = { "text" }, shapes = false,
    geometry = false, border = false, font = true, scale = true, opacity = true },
  title = "StatsInfo",
  summary = "In an item's tooltip: what its stats change against the item you wear in that slot.",
  -- the preview pane at the left, the four short sections at its right
  width = 760, height = 520,
  build = function(parent)
    local UI = BIT.UI

    -- Left: the live preview. A static sample item (the preview never reads the live API)
    -- with this module's own lines on it; it follows the boxes at the right and the TRY IT
    -- sliders below it.
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetPoint("TOPLEFT", 8, -8)
    pane:SetWidth(336)
    pane.title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pane.title:SetText("Live preview (sample item, not your gear)")
    previewScene = pane
    buildMockTooltip(pane)

    -- TRY IT: the appearance the preview is drawn in -- the same three fields the shared
    -- appearance editor writes, so either one moves the preview. Each row is registered in
    -- tryItSliders so renderPreview re-seats its thumb on the stored value after any write.
    local tryIt = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tryIt:SetText("TRY IT: font, scale, opacity")
    tryIt:SetTextColor(0.85, 0.7, 0.3)
    local fontSlider = UI.Slider(pane, "Font size (px)", 6, 24, 1,
      styleGet("fontSize", 12), styleSet("fontSize"), nil,
      "The size the preview's text is drawn in. The same field the shared appearance editor changes.")
    local scaleSlider = UI.Slider(pane, "Scale", 0.5, 2, 0.05,
      styleGet("scale", 1), styleSet("scale"), function(v) return string.format("%.2fx", v) end,
      "Scales the preview's card, rows, icons and bag button. The same field the shared appearance editor changes.")
    local opacitySlider = UI.Slider(pane, "Opacity", 0, 1, 0.05,
      styleGet("opacity", 1), styleSet("opacity"), "%d%%",
      "How see-through the preview's lines and bag button are. The same field the shared appearance editor changes.")
    tryItSliders = { fontSlider, scaleSlider, opacitySlider }
    tryIt:SetPoint("TOPLEFT", pane, "BOTTOMLEFT", 0, -10)
    fontSlider:SetPoint("TOPLEFT", tryIt, "BOTTOMLEFT", -4, -4)
    scaleSlider:SetPoint("TOPLEFT", fontSlider, "BOTTOMLEFT", 0, -2)
    opacitySlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -2)

    -- Right: the settings in four short sections instead of one wall of text. Each block
    -- is anchored to the one above it, so a wrapped block never runs into the next.
    local area = CreateFrame("Frame", nil, parent)
    area:SetPoint("TOPLEFT", pane, "TOPRIGHT", 14, 0)
    area:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, 0)
    area:SetHeight(430)

    local tabs = {}
    local active -- the tab whose content is on screen; re-asserted whenever the tab is shown
    -- Only the active tab's content is ever shown. Every flip is its own pcall and Show/Hide,
    -- not SetShown: the underline is a texture and SetShown is not a method every widget has
    -- (see BagMarkers' own guard), so one raising call used to stop the loop half way -- the
    -- clicked tab's content never came up and the leftovers stayed visible together.
    local function setVisible(widget, on)
      if not widget then return end
      pcall(on and widget.Show or widget.Hide, widget)
    end
    local function selectTab(tab)
      if not tab or not tab.content then return end
      active = tab
      for _, other in ipairs(tabs) do
        local on = other == tab
        setVisible(other.content, on)
        setVisible(other.button and other.button.underline, on)
        local caption = other.button and other.button.caption
        if caption then
          pcall(caption.SetTextColor, caption,
            on and 1 or 0.6, on and 0.82 or 0.6, on and 0 or 0.6)
        end
      end
    end
    local function addTab(name)
      local tab = {}
      tab.content = CreateFrame("Frame", nil, area)
      tab.content:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -32)
      tab.content:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
      tab.content:Hide()
      local button = CreateFrame("Button", nil, area)
      -- "caption", not "text": the settings and the suites read a frame's .text as the
      -- string it shows, so a font string must not live under that name
      button.caption = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      button.caption:SetText(name)
      button:SetSize(button.caption:GetStringWidth() + 20, 26)
      button.caption:SetPoint("CENTER")
      button.underline = button:CreateTexture(nil, "ARTWORK")
      button.underline:SetColorTexture(1, 0.82, 0, 1)
      button.underline:SetHeight(2)
      button.underline:SetPoint("BOTTOMLEFT", 6, 0)
      button.underline:SetPoint("BOTTOMRIGHT", -6, 0)
      local previous = tabs[#tabs]
      if previous then
        button:SetPoint("LEFT", previous.button, "RIGHT", 2, 0)
      else
        button:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -2)
      end
      button:SetScript("OnClick", function() selectTab(tab) end)
      tab.button = button
      function tab:place(widget, gap)
        widget:ClearAllPoints()
        if self.last then
          widget:SetPoint("TOPLEFT", self.last, "BOTTOMLEFT", 0, -(gap or 6))
        else
          widget:SetPoint("TOPLEFT", self.content, "TOPLEFT", 4, 0)
        end
        self.last = widget
        return widget
      end
      function tab:heading(text)
        local label = self.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetJustifyH("LEFT")
        label:SetText(text)
        label:SetTextColor(0.85, 0.7, 0.3)
        self:place(label, 0)
        label:SetPoint("RIGHT", self.content, "RIGHT", -4, 0)
        return label
      end
      function tab:body(text, muted)
        local block = self.content:CreateFontString(nil, "OVERLAY",
          muted and "GameFontDisableSmall" or "GameFontHighlightSmall")
        block:SetJustifyH("LEFT")
        block:SetText(text)
        self:place(block, 8)
        block:SetPoint("RIGHT", self.content, "RIGHT", -4, 0)
        return block
      end
      table.insert(tabs, tab)
      return tab
    end

    -- Display: the boxes, each with what it does on hover. The beneficiary-icon box greys
    -- out with the arrows off: it has nothing to sit on then.
    local display = addTab("Display")
    local checkRows = {}
    local updateBagIconState
    local function toggle(key, v)
      settings[key] = v
      if key == "bagMarkers" then
        if v then M.EnableBagMarkers() else M.DisableBagMarkers() end
        if updateBagIconState then updateBagIconState() end
      elseif key == "questMarkers" then
        if v then M.EnableQuestMarkers() else M.DisableQuestMarkers() end
      elseif key == "bagSpecIcons" then
        M.RefreshBags(true)
      end
      renderPreview()
    end
    local function box(key, label, tooltip)
      local check = UI.Check(display.content, label,
        function() return (settings or DEFAULTS)[key] end,
        function(v) toggle(key, v) end, tooltip)
      display:place(check)
      checkRows[#checkRows + 1] = check
      return check
    end
    box("compare", "Show what the item changes against the equipped one",
      "The differences against the item you wear in that slot, in the item's tooltip.")
    box("worth", "Under each stat, what it gives you",
      "Health, mana, armor, attack power, crit, hit and the rest, under each difference. "
        .. "The Legend tab has the icons.")
    box("specs", "How each spec of your class rates the item",
      "The Ratings tab explains the numbers.")
    box("icons", "Icons instead of words",
      "Icons and one line each, instead of words.")
    box("bagMarkers", "Arrows on bag items",
      "Green up for an upgrade, red down only when every path is worse. The Bag arrows tab explains them.")
    local bagSpecIcons = box("bagSpecIcons", "The beneficiary spec icon on an up arrow",
      "+N for the rest of the specs it is an upgrade for, ~ for the approximate healer score. "
        .. "Needs the arrows on.")
    box("questMarkers", "Quest reward arrows",
      "One badge over a quest's rewards: a green up arrow on the first upgrade, or a coin on "
        .. "the choice that sells for the most when nothing is an upgrade.")
    updateBagIconState = function()
      local on = (settings or DEFAULTS).bagMarkers
      bagSpecIcons:SetAlpha(on and 1 or 0.35)
      bagSpecIcons:EnableMouse(on)
    end
    display:body("Hover a box for what it does. The preview at the left follows these boxes at once.")
    -- Reset: the seven settings above, back to their defaults. The appearance is not touched.
    local reset = UI.Button(display.content, "Reset to defaults", 150, function()
      for k, v in pairs(DEFAULTS) do settings[k] = v end
      if settings.bagMarkers then M.EnableBagMarkers() else M.DisableBagMarkers() end
      if settings.questMarkers then M.EnableQuestMarkers() else M.DisableQuestMarkers() end
      M.RefreshBags(true)
      for _, c in ipairs(checkRows) do c:Refresh() end
      updateBagIconState()
      renderPreview()
    end)
    display:place(reset, 12)

    -- Legend: the icons, and what the worth line says in words.
    local legend = addTab("Legend")
    legend:heading("What the icons stand for")
    local words = {}
    for _, kind in ipairs({ "armor", "ap", "crit", "hit", "haste", "expertise", "dodge", "parry", "block", "blockvalue", "defense",
      "health", "mana", "spellcrit", "regen", "healing", "spellpower" }) do
      words[#words + 1] = icon(ICONS[kind], 12) .. " " .. WORTH_WORDS[kind]
    end
    legend:body(table.concat(words, "    "))
    legend:body("Under each difference: what the stats give this character -- the game's own numbers, "
      .. "worked out as its character sheet works them out. Green is up, red is down.")
    legend:body("Armor is 2 per Agility and mana regeneration a quarter of Spirit, as measured on Forever. "
      .. "In combat the game may hide these numbers; then the line is left out.")

    -- Ratings: how the spec numbers come about, and what they do not claim.
    local ratings = addTab("Ratings")
    ratings:heading("How each spec rates the item")
    ratings:body("Each spec of your class rates the item against what you wear: \"25% better dmg spec\" "
      .. "means its stats are worth a quarter more to that spec.")
    ratings:body("A tank has two numbers: for survival (less damage taken) and for threat gen. (holding aggro).")
    ratings:body("With nothing worth comparing, or a change past the cap: \">300% ...\", at most triple.")
    ratings:body("A healer spec (druid Restoration) is rated by this addon's own starter heuristic, and its "
      .. "line is marked \"(approx.)\": an approximate item score, not a measured healing gain.")
    ratings:body("Its weights are design choices of this addon (tools/data/healer_weights.json): "
      .. "1 x +Healing, 1 x Spell Power, 0.5 x Intellect, 0.5 x Spirit and 2 x MP5. "
      .. "Every other stat counts for nothing to it.")
    ratings:body("The other ratings use ForeverSim's stat weights, measured on a level 60 build of each spec "
      .. "with its own talents, gear and buffs: below 60 they are an estimate.", true)
    ratings:body("A weapon's damage per second counts as the simulator weighs it for the spec: main hand, "
      .. "off hand and ranged slot apart.", true)
    ratings:body("Not counted: what a hunter's pet gets from your stats, weapon skill, and Spirit for the "
      .. "specs the simulator does not weigh it for.", true)

    -- Bag arrows: the two arrows, and when neither shows.
    local bags = addTab("Bag arrows")
    bags:heading("Arrows on bag items")
    bags:body("On the game's own bags and the Baganator bag grid: green up when at least one spec's score "
      .. "is outright better and none of it worse.")
    bags:body("Red down only when every replacement path is strictly worse for every spec. "
      .. "Mixed, equal or unknown: no arrow.")
    bags:body("Always against what you wear in that slot, never a BiS verdict.")
    bags:body("Stats the simulator does not model are compared conservatively by the raw differences, "
      .. "with no spec icon; the healer's approximate score gets a ~ icon.")
    bags:body("While the client hides stats (in combat) or the item's data has not arrived, no arrow is shown.")

    selectTab(tabs[1])

    -- The probe row (a direct child of the tab's content): what /bit probe records.
    local count -- SI-751: declared before the button so its OnClick sees the local
    local button = UI.Button(parent, "Record the probe", 170, function()
      M.Probe()
      -- SI-751: the counter must refresh on click, not only on OnShow.
      local probes = BIT.DB().probes
      count:SetText(string.format("%d recorded so far", type(probes) == "table" and #probes or 0))
    end)
    button:SetPoint("TOPLEFT", opacitySlider, "BOTTOMLEFT", 0, -12)
    count = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("LEFT", button, "RIGHT", 10, 0)
    parent:SetScript("OnShow", function()
      -- re-asserted here too: whatever re-showed a content in between, one tab at a time
      selectTab(active or tabs[1])
      local probes = BIT.DB().probes
      count:SetText(string.format("%d recorded so far", type(probes) == "table" and #probes or 0))
      for _, c in ipairs(checkRows) do c:Refresh() end
      updateBagIconState()
      renderPreview()
    end)
    -- drawn once here too: the preview is already there the moment the tab is built
    updateBagIconState()
    renderPreview()
  end,
})
BIT.tabWords.stats = "StatsInfo"
