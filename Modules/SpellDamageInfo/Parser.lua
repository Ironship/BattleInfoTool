-- BattleInfoTool module SpellDamageInfo: ported by tools/port.py from SpellDamageInfo/Parser.lua at 8269edd.
-- Change it there, or in tools/port.py; an edit made here is lost at the next port.
-- SpellDamageInfo: reads a spell's damage and healing out of its description text.
-- Copyright (c) 2026 Ironship. MIT licence, see LICENSE.
--
-- Parse(text, lang) returns a table or nil:
--   direct = { min = n, max = n }         instant damage
--   dot    = { total = n, duration = s }  damage over time (total over the whole duration)
--   heal   = { min = n, max = n }         instant healing
--   hot    = { total = n, duration = s }  healing over time
--   school = "shadow" | "fire" | "nature" | "frost" | "arcane" | "holy" | "frostfire" | "physical" | "volcanic" | nil
--   transfer = true       "Transfers X health from the target to the caster" (Drain Life): one
--                         amount at both ends, damage in dot/direct and the same healing in
--                         hot/heal
--   petHeal = true        "Gives X health to the caster's pet" (Health Funnel): the pet is given
--                         health the caster pays, so the amount is a cost in healthCost
--   healthCost = n        health the caster pays (the pet transfer above; Life Tap's own pair is
--                         read by ParseSpecial)
--   hp5 = n               "increases health regeneration by X health per Y sec" (Demon Skin),
--                         the regeneration per 5 sec
-- It returns nil (plus a short reason) for any wording it does not understand, and never guesses.
-- ParseReduction(text, lang) reads how much a debuff lowers the enemy's damage or attack power.
-- English and German wordings are understood; lang is "en", "de" or nil (detect from the text).
-- Pure Lua 5.1, no game API, so it can be tested outside the game.

local _, BIT = ...
-- Inside BattleInfoTool its own namespace; loaded on its own, the addon's table as before.
local ns = BIT and BIT.Module and BIT.Module("SpellDamageInfo") or BIT or {}

local Parser = {}
ns.Parser = Parser

local find, sub, gsub, match, gmatch = string.find, string.sub, string.gsub, string.match, string.gmatch
local tonumber, floor = tonumber, math.floor

-- Lower case by hand: string.lower and the %a/%d classes follow the process's C locale, and
-- under a code-page locale they would treat the bytes of UTF-8 letters as letters too.
local function asciiLower(c) return string.char(c:byte() + 32) end
-- Capital umlauts (UTF-8) to lower case.
local UMLAUT_LOWER = { ["\195\132"] = "\195\164", ["\195\150"] = "\195\182", ["\195\156"] = "\195\188" }

local SCHOOL_EN = {
  shadow = "shadow", fire = "fire", nature = "nature", frost = "frost", arcane = "arcane",
  holy = "holy", frostfire = "frostfire", physical = "physical", bleed = "physical", volcanic = "volcanic",
}
local SCHOOL_DE = {
  schatten = "shadow", feuer = "fire", natur = "nature", frost = "frost", arkan = "arcane",
  heilig = "holy", frostfeuer = "frostfire", vulkan = "volcanic", blutungs = "physical", [""] = "physical",
}

-- Words that may sit between an amount and its damage word.
local FILLERS_EN = { "additional ", "extra " }
local FILLERS_DE = {
  "punkt(e) ", "punkt(en) ", "punkte ", "punkt ",
  "zus\195\164tzlichen ", "zus\195\164tzliche ", "zus\195\164tzlich ",
  "insgesamt ", "k\195\182rperlichen ", "weitere ",
}

-- A number as it looks after normalisation (thousand separators removed, "." as decimal point).
local NUM = "[0-9]+%.?[0-9]*"

local function detectLanguage(t)
  if find(t, "sek%.") or find(t, "schaden") or find(t, "punkt%(e%)") or find(t, "heilt ")
    or find(t, " und ") or find(t, "gesundheit") or find(t, "stellt ") or find(t, "wieder her") then
    return "de"
  end
  return "en"
end

-- Wowhead-style formulas such as "[11 * (((1)))]" or "[26 * 8 * (1)]". The game prints the
-- result, so evaluate plain arithmetic (numbers, + - * / and brackets) and nothing else.
local function evalArithmetic(expr)
  local pos = 1
  local parseSum
  local function skip() pos = (find(expr, "[^ ]", pos)) or (#expr + 1) end
  local function parseAtom()
    skip()
    local c = sub(expr, pos, pos)
    if c == "(" then
      pos = pos + 1
      local v = parseSum()
      skip()
      if v == nil or sub(expr, pos, pos) ~= ")" then return nil end
      pos = pos + 1
      return v
    elseif c == "-" then
      pos = pos + 1
      local v = parseAtom()
      return v and -v
    end
    local s, e = find(expr, "^[0-9]+%.?[0-9]*", pos)
    if not s then return nil end
    pos = e + 1
    return tonumber(sub(expr, s, e))
  end
  local function parseProduct()
    local v = parseAtom()
    while v do
      skip()
      local c = sub(expr, pos, pos)
      if c ~= "*" and c ~= "/" then break end
      pos = pos + 1
      local r = parseAtom()
      if not r then return nil end
      if c == "*" then v = v * r elseif r == 0 then return nil else v = v / r end
    end
    return v
  end
  parseSum = function()
    local v = parseProduct()
    while v do
      skip()
      local c = sub(expr, pos, pos)
      if c ~= "+" and c ~= "-" then break end
      pos = pos + 1
      local r = parseProduct()
      if not r then return nil end
      if c == "+" then v = v + r else v = v - r end
    end
    return v
  end
  local v = parseSum()
  skip()
  if v == nil or pos <= #expr then return nil end
  return v
end

local function formatNumber(v)
  if v == floor(v) then return tostring(floor(v)) end
  return (gsub(string.format("%.2f", v), "0+$", ""))
end

local function replaceFormulas(t)
  local n
  repeat
    t, n = gsub(t, "%[([0-9 %.%+%-%*/%(%)]+)%]", function(expr)
      local v = evalArithmetic(expr)
      if v then return formatNumber(v) end
    end)
  until n == 0
  -- Whatever is still in brackets holds words (optional glyph or talent text); it is not
  -- part of the spell's own numbers.
  local prev
  repeat
    prev = t
    t = gsub(t, "%b[]", " ")
  until t == prev
  return t
end

local function normaliseNumbers(t, lang)
  local prev
  if lang == "de" then
    repeat prev = t; t = gsub(t, "([0-9])%.([0-9][0-9][0-9])", "%1%2") until t == prev
    t = gsub(t, "([0-9]),([0-9])", "%1.%2")
  else
    repeat prev = t; t = gsub(t, "([0-9]),([0-9][0-9][0-9])", "%1%2") until t == prev
  end
  return t
end

local UNIT_SECONDS = { sec = 1, sek = 1, min = 60, hour = 3600, stunde = 3600 }

-- "12 sec", "8 secs", "1 min", "30 minutes", "1 hour" / "12 Sek.", "8 Sekunden", "1 Min.", "1 Stunde"
local function unitSeconds(word)
  if not word then return nil end
  if sub(word, 1, 3) == "sec" or sub(word, 1, 3) == "sek" then return 1 end
  if sub(word, 1, 3) == "min" then return 60 end
  if sub(word, 1, 4) == "hour" or sub(word, 1, 6) == "stunde" then return 3600 end
  return nil
end

-- Take "lasts N sec" / "Hält N Sek. lang an" out of the text: it is the duration of the whole
-- effect, used by "every N sec" amounts anywhere in the description.
local function extractLasts(t, lang)
  local values = {}
  local function take(num, unit)
    local u = unitSeconds(unit)
    if u then values[#values + 1] = tonumber(num) * u end
    return " "
  end
  if lang == "de" then
    t = gsub(t, "h\195\164lt (" .. NUM .. ") ([a-z]+)%.? lang an", take)
  else
    t = gsub(t, "lasts for (" .. NUM .. ") ([a-z]+)", take)
    t = gsub(t, "lasts (" .. NUM .. ") ([a-z]+)", take)
  end
  local lasts
  for _, v in ipairs(values) do
    if lasts and lasts ~= v then return t, nil, true end
    lasts = v
  end
  return t, lasts, false
end

local function splitSentences(t, lang)
  if lang == "de" then
    -- "12 Sek. lang" and "1 Min. Kann" do not end a sentence.
    t = gsub(t, "([0-9]) sek%.", "%1 sek")
    t = gsub(t, "([0-9]) min%.", "%1 min")
  end
  local out = {}
  for s in gmatch(t .. " ", "(.-)%. ") do out[#out + 1] = s end
  local rest = match(t .. " ", ".*%. (.*)$")
  if rest and find(rest, "[^ ]") then out[#out + 1] = rest end
  if #out == 0 then out[1] = t end
  return out
end

local function splitClauses(s, lang)
  if lang == "de" then
    s = gsub(s, " und ", "\1")
    s = gsub(s, " sowie ", "\1")
  else
    s = gsub(s, ", and ", "\1")
    s = gsub(s, " and ", "\1")
  end
  local out = {}
  for c in gmatch(s .. "\1", "([^\1]*)\1") do out[#out + 1] = " " .. c .. " " end
  return out
end

-- Remove the "every N sec" part of a clause and return its interval in seconds.
local function takeInterval(c, lang)
  local interval
  local function num(n, unit)
    local u = unitSeconds(unit)
    if u and not interval then interval = tonumber(n) * u end
    return " # "
  end
  local function one() if not interval then interval = 1 end return " # " end
  if lang == "de" then
    c = gsub(c, "alle (" .. NUM .. ") ([a-z]+)", num)
    c = gsub(c, "pro sekunde", one)
    c = gsub(c, "in jeder sekunde", one)
    c = gsub(c, "jede sekunde", one)
  else
    c = gsub(c, "every (" .. NUM .. ") ([a-z]+)", num)
    c = gsub(c, "every second", one)
    c = gsub(c, "each second", one)
    c = gsub(c, "per second", one)
  end
  return c, interval
end

-- Remove the durations of a clause ("over 12 sec", "12 Sek. lang", "after 1 min") and list them.
local function takeDurations(c)
  local list = {}
  c = gsub(c, "(" .. NUM .. ") ?([a-z]+)", function(n, unit)
    local u = unitSeconds(unit)
    if not u then return nil end
    list[#list + 1] = tonumber(n) * u
    return " # "
  end)
  return c, list
end

local function stripFillers(s, fillers)
  local again = true
  while again do
    again = false
    s = gsub(s, "^ +", "")
    for _, f in ipairs(fillers) do
      if sub(s, 1, #f) == f then
        s = sub(s, #f + 1)
        again = true
      end
    end
  end
  return s
end

local HEAL_WORDS_EN = { "^ *heals ", " heals ", " healing ", " heal " }
-- "der es um 172 Gesundheit heilt, wenn ...": a comma may follow
local HEAL_WORDS_DE = { " heilt[ ,]", " geheilt[ ,]", " heilen[ ,]" }

local function isHealClause(c, lang)
  local words = (lang == "de") and HEAL_WORDS_DE or HEAL_WORDS_EN
  for _, w in ipairs(words) do
    if find(c, w) then return true end
  end
  return false
end

local function hasDamageWord(c, lang)
  if lang == "de" then return find(c, "schaden") ~= nil end
  return find(c, "damage") ~= nil
end

-- What the words right after an amount say it is: damage of a school, a health drain,
-- health given, or nothing we understand.
local function classifyAfter(after, lang, sentence)
  if lang == "de" then
    local s = stripFillers(after, FILLERS_DE)
    -- the word ends there: "3 Schadensfähigkeiten" is a count of abilities
    local prefix = match(s, "^([a-z]*)schaden$") or match(s, "^([a-z]*)schaden[^a-z]")
    if prefix and SCHOOL_DE[prefix] then return "damage", SCHOOL_DE[prefix] end
    if sub(s, 1, 10) == "gesundheit" then
      if find(sentence, "\195\188bertr\195\164gt") then return "drain", nil end
      -- "Gibt dem Begleiter ...", Forever's "Gewährt dem Begleiter ... 12 Gesundheit" (not
      -- Sentry Totem's "über 100 Gesundheit verfügt ... und Sicht ... gewährt")
      if find(sentence, "gibt ") or find(sentence, "gew\195\164hrt dem begleiter") then
        -- Health Funnel, "Gibt dem Begleiter des Zaubernden ... Gesundheit": the caster's own
        if find(sentence, "begleiter", 1, true) then return "petheal", nil end
        return "giveheal", nil
      end
    end
  else
    local s = stripFillers(after, FILLERS_EN)
    if sub(s, 1, 6) == "damage" then return "damage", "physical" end
    local word = match(s, "^([a-z]+) damage")
    if word and SCHOOL_EN[word] then return "damage", SCHOOL_EN[word] end
    if sub(s, 1, 6) == "health" then
      if find(sentence, "transfers ") then return "drain", nil end
      if find(sentence, "gives ") then
        -- Health Funnel, "Gives X health to the caster's pet": the caster's own
        if (find(sentence, " pet", 1, true) or find(sentence, "pet ", 1, true) or find(sentence, "pet'", 1, true) or find(sentence, "pets", 1, true)) then return "petheal", nil end
        return "giveheal", nil
      end
    end
  end
  return nil
end

local function healAmountOK(before, after, lang)
  if lang == "de" then
    if find(before, " um $") or find(before, " weitere $") then return true end
    local s = stripFillers(after, FILLERS_DE)
    return sub(s, 1, 7) == "schaden" or sub(s, 1, 10) == "gesundheit"
      or find(after, "^ *punkt") ~= nil
  end
  -- A count, not an amount: "Heals 3 total targets."
  local word = match(after, "^ *([a-z]+)")
  if word == "total" or word == "target" or word == "targets" or word == "times" or word == "charges" then
    return false
  end
  if find(before, " for $") or find(before, " of $") or find(before, " another $") or find(before, "heals $") then
    return true
  end
  local s = stripFillers(after, FILLERS_EN)
  return sub(s, 1, 6) == "damage" or sub(s, 1, 6) == "health"
end

-- Find the amounts in one clause. Each is { kind = "damage"|"heal"|"drain"|"petheal", min, max, school }.
local function findAmounts(c, lang, healMode, sentence)
  local amounts = {}
  local rangeWord = (lang == "de") and "bis" or "to"
  local pos = 1
  while true do
    local s, e = find(c, NUM, pos)
    if not s then break end
    local prevChar = sub(c, s - 1, s - 1)
    local valueMin = tonumber(sub(c, s, e))
    local valueMax = valueMin
    local stop = e
    -- "9 to 12" / "9 bis 12"
    local rs, re = find(c, "^ +" .. rangeWord .. " +" .. NUM, e + 1)
    if rs then
      local second = match(sub(c, rs, re), "(" .. NUM .. ")$")
      valueMax = tonumber(second)
      stop = re
    end
    pos = stop + 1
    if not match(prevChar, "[a-z0-9%-]") and valueMin and valueMax then
      local before = sub(c, 1, s - 1)
      local after = sub(c, stop + 1)
      if healMode then
        if healAmountOK(before, after, lang) then
          amounts[#amounts + 1] = { kind = "heal", min = valueMin, max = valueMax }
        end
      else
        local kind, school = classifyAfter(after, lang, sentence)
        if kind == "damage" or kind == "drain" or kind == "petheal" then
          amounts[#amounts + 1] = { kind = kind, min = valueMin, max = valueMax, school = school }
        elseif kind == "giveheal" then
          amounts[#amounts + 1] = { kind = "heal", min = valueMin, max = valueMax }
        end
      end
    end
  end
  return amounts
end

-- German sometimes puts a DoT's duration in the clause before its amount:
-- "lässt es 9 Sek. lang bluten und fügt damit 15 Punkt(e) Schaden zu".
local DE_DOT_VERBS = { "blut", "vergift", "brenn" }

local function hasDotVerb(c)
  for _, v in ipairs(DE_DOT_VERBS) do
    if find(c, v) then return true end
  end
  return false
end

-- Clauses whose amounts are not the spell's damage or healing: self-damage, absorbs, and
-- amounts per unit of something else ("for each mana destroyed, the target takes 0.5 Shadow
-- damage" / "Für jeden ... Manapunkt ... 0,5 Punkt(e) Schattenschaden").
local function ignoredClause(c, lang)
  if lang == "de" then
    return find(c, " selbst ") or find(c, "absorb") or find(c, "f\195\188r jede")
      or find(c, "erlittenen schadens")
  end
  return find(c, "himself") or find(c, "herself") or find(c, "yourself") or find(c, "absorb")
    or find(c, "for each ") or find(c, "damage taken per hit")
end

-- Plain lower-case text with numbers in one format ("1.132" / "1,132" -> "1132", "7,1" -> "7.1"),
-- and the language.
local function prepare(text, lang)
  local t = gsub(text, "[\r\n\t]+", " ")
  t = gsub(t, "\194\160", " ") -- no-break space
  t = gsub(t, "|c[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]", "")
  t = gsub(t, "|r", "")
  t = replaceFormulas(t)
  t = gsub(t, "[A-Z]", asciiLower)
  t = gsub(t, "\195[\132\150\156]", UMLAUT_LOWER)
  if lang ~= "de" and lang ~= "en" then lang = detectLanguage(t) end
  return normaliseNumbers(t, lang), lang
end

function Parser.Parse(text, lang)
  if type(text) ~= "string" or text == "" then return nil, "empty" end
  local t
  t, lang = prepare(text, lang)
  t = gsub(t, NUM .. " ?%%", " pct ")

  -- Per-combo-point tables and weapon-based attacks have no single number.
  if find(t, "[^0-9]1 points? *:") or find(" " .. t, "[^0-9]1 punkte? *:") then return nil, "finisher" end
  if find(t, "weapon damage") or find(t, "waffenschaden") then return nil, "weapon" end

  local lasts, lastsAmbiguous
  t, lasts, lastsAmbiguous = extractLasts(t, lang)

  -- "increases health regeneration by X health per Y sec" (Demon Skin / Demon Armor): the figure
  -- the buff is named by, health per 5 sec. German: "erhöht die Gesundheitsregeneration um X
  -- Gesundheit pro Y Sek." Its clause reads as no amount of its own (health, but nothing
  -- transfers or is given), so the figure is read here on its own.
  local hp5
  do
    local a, iv = match(t, "health regeneration by (" .. NUM .. ") health per (" .. NUM .. ") sec")
    if not a and lang == "de" then
      a, iv = match(t, "gesundheitsregeneration um (" .. NUM .. ") gesundheit pro (" .. NUM .. ") sek")
    end
    if a then
      iv = tonumber(iv)
      if iv and iv > 0 then hp5 = tonumber(a) * 5 / iv end
    end
  end

  local result = {}
  local found = false
  local function put(slot, value)
    if result[slot] then return false end
    result[slot] = value
    found = true
    return true
  end

  for _, sentence in ipairs(splitSentences(t, lang)) do
    local clauses = {}
    local prevHeal = false
    for i, raw in ipairs(splitClauses(sentence, lang)) do
      local c, interval = takeInterval(raw, lang)
      local durations
      c, durations = takeDurations(c)
      local heal = isHealClause(c, lang) or (prevHeal and not hasDamageWord(c, lang))
      prevHeal = heal
      local amounts = {}
      if not ignoredClause(c, lang) then amounts = findAmounts(c, lang, heal, sentence) end
      clauses[i] = { text = c, raw = raw, interval = interval, durations = durations, amounts = amounts }
    end
    if lang == "de" then
      for i = 1, #clauses - 1 do
        local a, b = clauses[i], clauses[i + 1]
        if #a.amounts == 0 and #a.durations == 1 and not a.interval and hasDotVerb(a.raw)
          and #b.amounts > 0 and #b.durations == 0 and not b.interval then
          b.durations = { a.durations[1] }
        end
      end
    end
    -- SDI-BLACKARROW: "causing 150 Shadow damage and draining 150 mana over 30 sec":
    -- splitClauses puts the damage and the duration in separate clauses, and the
    -- mana-drain clause holds no damage amount of its own. The "over 30 sec"
    -- belongs to both, so share it with the damage clause ahead of the drain.
    -- German ("verursacht 150 Schattenschaden und zieht 30 Sek. lang 150 Mana ab")
    -- splits the same way; its drain verb is "zieht", not "draining".
    for i = 1, #clauses - 1 do
      local a, b = clauses[i], clauses[i + 1]
      if #a.amounts > 0 and #a.durations == 0 and not a.interval
        and #b.amounts == 0 and #b.durations == 1 and not b.interval
        and (find(b.raw, "drain", 1, true) or find(b.raw, "zieh", 1, true))
        and find(b.raw, "mana", 1, true) then
        a.durations = { b.durations[1] }
      end
    end
    for _, cl in ipairs(clauses) do
      if #cl.amounts > 0 then
        local periodic, duration, ticks
        if cl.interval then
          duration = (#cl.durations == 1 and cl.durations[1]) or (#cl.durations == 0 and lasts) or nil
          if not duration then
            return nil, lastsAmbiguous and "lasts-ambiguous" or "interval-without-duration"
          end
          ticks = floor(duration / cl.interval + 0.5)
          if ticks < 1 then return nil, "interval" end
          periodic = true
        elseif #cl.durations == 1 then
          if #cl.amounts > 1 then return nil, "two-amounts-one-duration" end
          duration = cl.durations[1]
          ticks = 1
          periodic = true
        elseif #cl.durations > 1 then
          return nil, "several-durations"
        end
        for _, a in ipairs(cl.amounts) do
          if a.kind == "petheal" then
            -- Health Funnel: the health the pet is given is health the caster pays, so it is
            -- the caster's cost (Life Tap's own shape), never a heal
            if periodic and a.min ~= a.max then return nil, "periodic-range" end
            result.petHeal = true
            if not result.healthCost then
              result.healthCost = periodic and (a.min * ticks) or ((a.min + a.max) / 2)
              found = true
            end
          else
            local isHeal = (a.kind == "heal")
            if periodic then
              if a.min ~= a.max then return nil, "periodic-range" end
              local slot = isHeal and "hot" or "dot"
              if not put(slot, { total = a.min * ticks, duration = duration }) then return nil, "second-" .. slot end
            else
              local slot = isHeal and "heal" or "direct"
              if not put(slot, { min = a.min, max = a.max }) then return nil, "second-" .. slot end
            end
            if a.kind == "drain" then
              -- Drain Life: a transfer has both ends - the same amount damages the target and
              -- heals the caster, so the healing sits beside the damage as well
              result.transfer = true
              local slot = periodic and "hot" or "heal"
              if not result[slot] then
                result[slot] = periodic and { total = a.min * ticks, duration = duration }
                  or { min = a.min, max = a.max }
              end
            end
            if not isHeal and result.school == nil and a.kind == "damage" then result.school = a.school end
          end
        end
      end
    end
  end

  if hp5 then result.hp5 = hp5 end
  if not found and not hp5 then return nil, "no-amount" end
  return result
end

-- A consumable's healing or mana out of its use text ("Use: Restores 70 to 90
-- health." / "Benutzen: Stellt 70 bis 90 Gesundheit wieder her."):
-- { heal = { min, max } } for an instant amount ("Restores"/"Stellt" health as
-- well as "Heals"/"Heilt" health or damage outside over time),
-- { hot = { total, duration } } for a stated total over time: a bandage
-- ("Heals 66 damage over 6 sec." / "Heilt 66 Schaden über 6 Sek.") or food
-- ("Restores 243 health over 21 sec." / "Stellt 243 Gesundheit über 21 Sek.
-- wieder her."), the stated total averaged over a range exactly like a
-- potion's (70-90 -> 80),
-- { mana = { min, max } } for an instant mana amount ("Restores 140 to 175
-- mana." / "Stellt 140 bis 175 Mana wieder her."),
-- or nil (plus a short reason). Only stated amounts; a mana amount over time
-- may tick, so it stays unread ("over-time") and is never guessed.
-- Damage wordings are never read here: Parse above keeps reading those
-- exactly as before.
function Parser.ParseItemHeal(text, lang)
  if type(text) ~= "string" or text == "" then return nil, "empty" end
  local t
  t, lang = prepare(text, lang)
  local lo, hi
  local mlo, mhi
  local dur, minutes
  if lang == "de" then
    mlo, mhi = match(t, "stellt (" .. NUM .. ") bis (" .. NUM .. ") mana wieder her")
    if not mlo then mlo = match(t, "stellt (" .. NUM .. ") mana wieder her") end
    if not mlo then mlo, mhi = match(t, "stellt sofort (" .. NUM .. ") bis (" .. NUM .. ") mana wieder her") end
    if not mlo then mlo = match(t, "stellt sofort (" .. NUM .. ") mana wieder her") end
    lo, hi = match(t, "stellt (" .. NUM .. ") bis (" .. NUM .. ") gesundheit wieder her")
    if not lo then lo = match(t, "stellt (" .. NUM .. ") gesundheit wieder her") end
    if not lo then lo, hi = match(t, "stellt sofort (" .. NUM .. ") bis (" .. NUM .. ") gesundheit wieder her") end
    if not lo then lo = match(t, "stellt sofort (" .. NUM .. ") gesundheit wieder her") end
    if not lo then lo, hi = match(t, "stellt (" .. NUM .. ") bis (" .. NUM .. ") leben wieder her") end
    if not lo then lo = match(t, "stellt (" .. NUM .. ") leben wieder her") end
    if not lo then lo, hi = match(t, "stellt sofort (" .. NUM .. ") bis (" .. NUM .. ") leben wieder her") end
    if not lo then lo = match(t, "stellt sofort (" .. NUM .. ") leben wieder her") end
    -- Food: "stellt 243 Gesundheit über 21 Sek. wieder her" (or "Leben"): the
    -- duration sits between the amount and "wieder her", so the patterns above
    -- do not see the amount.
    if not lo then lo, hi = match(t, "stellt (" .. NUM .. ") bis (" .. NUM .. ") gesundheit \195\188ber") end
    if not lo then lo = match(t, "stellt (" .. NUM .. ") gesundheit \195\188ber") end
    if not lo then lo, hi = match(t, "stellt (" .. NUM .. ") bis (" .. NUM .. ") leben \195\188ber") end
    if not lo then lo = match(t, "stellt (" .. NUM .. ") leben \195\188ber") end
    if not lo then
      lo, hi = match(t, "heilt (" .. NUM .. ") bis (" .. NUM .. ") schaden")
      if not lo then lo, hi = match(t, "heilt (" .. NUM .. ") bis (" .. NUM .. ") gesundheit") end
      if not lo then lo = match(t, "heilt (" .. NUM .. ") schaden") end
      if not lo then lo = match(t, "heilt (" .. NUM .. ") gesundheit") end
    end
    -- "über 6 Sek." (minutes count as 60 seconds, as in Parse above)
    dur = match(t, "\195\188ber (" .. NUM .. ") sek")
    minutes = false
    if not dur then dur = match(t, "\195\188ber (" .. NUM .. ") min"); minutes = dur ~= nil end
  else
    mlo, mhi = match(t, "restores (" .. NUM .. ") to (" .. NUM .. ") mana")
    if not mlo then mlo = match(t, "restores (" .. NUM .. ") mana") end
    lo, hi = match(t, "restores (" .. NUM .. ") to (" .. NUM .. ") health")
    if not lo then lo = match(t, "restores (" .. NUM .. ") health") end
    if not lo then lo, hi = match(t, "restores (" .. NUM .. ") to (" .. NUM .. ") life") end
    if not lo then lo = match(t, "restores (" .. NUM .. ") life") end
    if not lo then
      lo, hi = match(t, "heals (" .. NUM .. ") to (" .. NUM .. ") damage")
      if not lo then lo, hi = match(t, "heals (" .. NUM .. ") to (" .. NUM .. ") health") end
      if not lo then lo = match(t, "heals (" .. NUM .. ") damage") end
      if not lo then lo = match(t, "heals (" .. NUM .. ") health") end
    end
    dur = match(t, "over (" .. NUM .. ") sec")
    minutes = false
    if not dur then dur = match(t, "over (" .. NUM .. ") min"); minutes = dur ~= nil end
  end
  dur = tonumber(dur)
  if dur and minutes then dur = dur * 60 end
  if dur then
    -- Over time: a stated health total is the healing it says - a bandage's
    -- ("Heals 66 damage over 6 sec." / "Heilt 66 Schaden über 6 Sek.") or
    -- food's ("Restores 243 health over 21 sec." / "stellt 243 Gesundheit über
    -- 21 Sek. wieder her"), Heals/Heilt as well as Restores/Stellt. A mana
    -- amount over time may tick, so it stays unread.
    if lo then
      lo, hi = tonumber(lo), tonumber(hi or lo)
      if lo and hi then return { hot = { total = (lo + hi) / 2, duration = dur } } end
    end
    return nil, "over-time"
  end
  -- An instant amount with a stray duration marker but no stated duration
  -- ("every 2 sec") may tick, so it stays unread too.
  if lo or mlo then
    if find(t, "over ") or find(t, "\195\188ber ") then return nil, "over-time" end
    if find(t, " sec") or find(t, " sek") or find(t, " min") then return nil, "over-time" end
  end
  local result
  if lo then
    lo, hi = tonumber(lo), tonumber(hi or lo)
    if not lo or not hi then return nil, "no-amount" end
    result = { heal = { min = lo, max = hi } }
  end
  if mlo then
    mlo, mhi = tonumber(mlo), tonumber(mhi or mlo)
    if mlo and mhi then
      result = result or {}
      result.mana = { min = mlo, max = mhi }
    end
  end
  if not result then return nil, "no-amount" end
  return result
end

---------------------------------------------------------------------------------------------
-- Debuffs that lower the enemy's damage or attack power
---------------------------------------------------------------------------------------------

local REDUCE_VERBS = {
  en = { "reduc", "lower", "decreas" },
  de = { "verringer", "reduzier", "senk", "vermindert" },
}
-- The enemy has to be named somewhere in the sentence.
local ENEMY_WORDS = {
  en = { "target", "enem" },
  de = { "ziel", "feind", "gegner" },
}
-- Damage the caster or the party takes, or the caster's own damage: not an enemy debuff.
local SELF_WORDS = {
  en = { "take", "your ", "yourself" },
  de = { "erlitten", " euer", " eure" },
}

local function hasAny(s, words)
  for _, w in ipairs(words) do
    if find(s, w, 1, true) then return true end
  end
  return false
end

-- One clause: "Damage caused by the target is reduced by 3", "reduces the melee attack power
-- of all enemies within 10 yards by 45" / "der vom Ziel verursachte Schaden wird ... um 3
-- reduziert", "verringert ... die Nahkampfangriffskraft ... um 45".
-- sentenceVerb: the sentence's verb lowers what this clause names. German puts it at the end,
-- after everything it lowers: "was seine Nahkampfangriffskraft um 43 und die Wirksamkeit
-- jeglicher Heilung um 20% verringert".
local function reductionInClause(c, lang, sentenceVerb)
  if not (sentenceVerb or hasAny(c, REDUCE_VERBS[lang])) or hasAny(c, SELF_WORDS[lang]) then return nil end
  -- "increasing melee attack power by 20 but reducing armor by 140": the attack power goes up
  if find(c, (lang == "de") and "erh\195\182h" or "increas", 1, true) then return nil end
  local ap = (lang == "de") and find(c, "angriffskraft", 1, true) or find(c, "attack power", 1, true)
  -- German: the word "Schaden" itself, not a school's damage such as "Frostfeuerschaden"
  local dmg = (lang == "de") and find(" " .. c, " schaden", 1, true) or find(c, "damage", 1, true)
  if not ap and not dmg then return nil end
  local by = (lang == "de") and "um " or "by "
  local s, e, num
  local from = 1
  repeat -- the first "by N" / "um N" that starts a word ("nearby 3" does not)
    s, e, num = find(c, by .. "(" .. NUM .. ")", from)
    if not s then return nil end
    from = e + 1
    local prev = sub(c, s - 1, s - 1)
  until prev == "" or prev == " "
  local rest = sub(c, e + 1)
  local percent = find(rest, "^ ?%%") ~= nil
  if not percent then
    local word = match(rest, "^ ?([a-z]+)")
    -- "by 3 sec" is a duration; "by 10 yards" a distance
    if unitSeconds(word) or word == "yard" or word == "yards" or word == "meter" or word == "metern" then return nil end
  end
  local amount = tonumber(num)
  if not amount or amount <= 0 then return nil end
  return { amount = amount, percent = percent, stat = ap and "attackpower" or "damage" }
end

-- ParseReduction(text, lang) returns { amount = n, percent = true|false, stat = "damage" |
-- "attackpower" } for a spell that lowers the enemy's damage or attack power, or nil.
function Parser.ParseReduction(text, lang)
  if type(text) ~= "string" or text == "" then return nil end
  local t
  t, lang = prepare(text, lang)
  local found
  for _, sentence in ipairs(splitSentences(t, lang)) do
    if hasAny(sentence, ENEMY_WORDS[lang]) then
      local verb = lang == "de" and hasAny(sentence, REDUCE_VERBS.de)
      for _, clause in ipairs(splitClauses(sentence, lang)) do
        -- a comma separates what the spell does to whom: "..., die Bewegungsgeschwindigkeit um
        -- 50% verringert"
        for c in gmatch(clause, "[^,]+") do
          local r = reductionInClause(c, lang, verb)
          if r then
            if found and (found.amount ~= r.amount or found.percent ~= r.percent) then return nil end
            found = found or r
          end
        end
      end
    end
  end
  return found
end

---------------------------------------------------------------------------------------------
-- Abilities whose damage comes from the weapon, and spells that raise attack power
---------------------------------------------------------------------------------------------
-- ParseWeapon(text, lang) returns a table or nil:
--   { kind = "next", bonus = n, ranged = bool }       the next swing, or a shot, is a weapon
--                                                      hit plus n: Heroic Strike, Maul, Aimed Shot
--   { kind = "weapon", pct = p, bonus = n, bonusMax = m }
--                                                      p% of a weapon hit plus n (to m):
--                                                      Overpower, Backstab, Shred, Sinister Strike
--   { kind = "both", pct = p, bonus = n }              p% of each weapon's hit plus n with each:
--                                                      Mutilate
--   { kind = "appct", pct = p, bonus = n }             p% of attack power plus n: Bloodthirst
--   { kind = "dps", times = n, school = s }            n times the main hand's damage per second:
--                                                      Hammer of the Righteous
--   { kind = "perhit", min = n, max = m, school = s, bySpeed = bool }
--                                                      what every hit gains while the seal or the
--                                                      imbue lasts: Seal of Righteousness,
--                                                      Flametongue Weapon; bySpeed where the text
--                                                      says slower weapons do more per swing
--   { kind = "ap", amount = n, ranged = bool, plusAgility = bool }
--                                                      attack power the spell adds: Battle Shout,
--                                                      Rockbiter Weapon, Bear Form, Aspect of the Hawk
--   { kind = "stat", stat = "str" | "agi", amount = n } strength or agility the spell adds, which
--                                                      turns into attack power: Strength of Earth
--   { kind = "extra", attacks = n, amount = a }        n extra attacks, each with a more attack
--                                                      power: Windfury Weapon and Totem
-- Parse() leaves the weapon attacks alone (it has no weapon to add the number to). Of the chance
-- effects, Windfury and Seal of Command are read here as what one trigger is worth (a weapon
-- view with school = "holy" for Seal of Command); every other sentence with a chance in it gives
-- nil, as does a sentence that lowers attack power, which is ParseReduction's. A seal's last
-- sentence is its Judgement ("Unleashing this Seal's energy ...") and is read by ParseJudgement,
-- never here. The wordings are the ones in the fixtures, which hold Classic's English and German
-- from Wowhead and Forever's own English, for every rank of every class.

local function num(v) return v and tonumber(v) or nil end

local AE, OE, UE = "\195\164", "\195\182", "\195\188" -- ä ö ü

local JUDGE = { en = "unleashing this seal's energy", de = "entfesselung der energie dieses siegels" }

-- A seal without its Judgement sentence, so neither the seal's own number nor its attack power
-- is taken from what the Judgement does.
local function withoutJudgement(t, lang)
  local s = find(t, JUDGE[lang] or JUDGE.en, 1, true)
  if s then return sub(t, 1, s - 1) end
  return t
end

-- Windfury's attack power is sometimes a bracket of arithmetic: "with (122 * 1) extra".
local function amountOf(expr) return expr and evalArithmetic((gsub(expr, " +$", ""))) or nil end

local function weaponEN(t)
  local p, a, b = match(t, "(" .. NUM .. ")%% weapon damage plus an additional (" .. NUM .. ") with each weapon")
  if p then return { kind = "both", pct = num(p), bonus = num(a) } end
  -- Chance effects, what one trigger is worth: Windfury's extra attacks, Seal of Command's hit
  a, b = match(t, "(" .. NUM .. ") extra attacks? with ([0-9%(%) %*%.]+) extra melee attack power")
  if a then return { kind = "extra", attacks = num(a), amount = amountOf(b) } end
  b, p = match(t, "chance to deal additional ([a-z]+) damage equal to (" .. NUM .. ")%% of normal weapon damage")
  if p then return { kind = "weapon", pct = num(p), bonus = 0, school = SCHOOL_EN[b] } end
  if find(t, "chance", 1, true) or find(t, "with each weapon", 1, true) then return nil end
  local lo, hi, school = match(t, "each melee attack an additional (" .. NUM .. ") to (" .. NUM .. ") ([a-z]+) damage")
  -- "Each hit causes 6 to 22 additional ..."; later Flametongue Totem ranks: "Each main hand hit causes  9 to 31 ..."
  if not lo then lo, hi, school = match(t, "each [a-z ]-hit causes +(" .. NUM .. ") to (" .. NUM .. ") additional ([a-z]+) damage") end
  if lo then
    return { kind = "perhit", min = num(lo), max = num(hi), school = SCHOOL_EN[school],
      bySpeed = find(t, "slower weapons cause more", 1, true) and true or nil }
  end
  a, school = match(t, "melee attacks to deal an additional (" .. NUM .. ") ([a-z]+) damage")
  if a then return { kind = "perhit", min = num(a), max = num(a), school = SCHOOL_EN[school] } end
  p, a = match(t, "damage equal to (" .. NUM .. ")%% of your attack power plus (" .. NUM .. ")")
  if not p then p = match(t, "damage equal to (" .. NUM .. ")%% of your attack power") end
  if p then return { kind = "appct", pct = num(p), bonus = num(a) or 0 } end
  a = match(t, "equal to (" .. NUM .. ") times the damage per second of your main hand weapon")
  if not a then a = match(t, "causing (" .. NUM .. ") times your main hand damage per second") end
  if a then return { kind = "dps", times = num(a), school = find(t, "holy", 1, true) and "holy" or "physical" } end
  p, a, b = match(t, "(" .. NUM .. ")%% weapon damage plus an additional (" .. NUM .. ") to (" .. NUM .. ")")
  if p then return { kind = "weapon", pct = num(p), bonus = num(a), bonusMax = num(b) } end
  p, a = match(t, "(" .. NUM .. ")%% weapon damage plus (" .. NUM .. ")")
  if p then return { kind = "weapon", pct = num(p), bonus = num(a) } end
  -- druid attacks: "225% damage plus 180", Forever's Claw "110% normal damage plus 115"
  p, a = match(t, "(" .. NUM .. ")%% normal damage plus (" .. NUM .. ")")
  if not p then p, a = match(t, "(" .. NUM .. ")%% damage plus (" .. NUM .. ")") end
  if p then return { kind = "weapon", pct = num(p), bonus = num(a) } end
  p = match(t, " for (" .. NUM .. ")%% normal damage")
  if p then return { kind = "weapon", pct = num(p), bonus = 0 } end
  a = match(t, "weapon damage plus (" .. NUM .. ")")
  if a then return { kind = "weapon", pct = 100, bonus = num(a) } end
  a = match(t, "causes (" .. NUM .. ") damage in addition to your normal weapon damage")
  if a then return { kind = "weapon", pct = 100, bonus = num(a) } end
  if find(t, "causing weapon damage", 1, true) then return { kind = "weapon", pct = 100, bonus = 0 } end
  -- Classic's Claw: the claw's own damage on top of the form's normal hit
  a = match(t, "^claw the enemy, causing (" .. NUM .. ") additional damage")
  if a then return { kind = "weapon", pct = 100, bonus = num(a) } end
  a = match(t, "increases melee damage by (" .. NUM .. ")")
  if a then return { kind = "next", bonus = num(a) } end
  a = match(t, "next attack by (" .. NUM .. ")")
  if a then return { kind = "next", bonus = num(a) } end
  a = match(t, "increases ranged damage by (" .. NUM .. ")")
  if a then return { kind = "next", bonus = num(a), ranged = true } end
  -- Seal of the Crusader: "granting 306 melee attack power. The Paladin also attacks 40% faster,
  -- but deals less damage with each attack": the attack power, counted per faster hit
  a, p = match(t, "granting (" .. NUM .. ") melee attack power%. +the paladin also attacks (" .. NUM .. ")%% faster")
  if a then return { kind = "ap", amount = num(a), faster = num(p) } end
  a = match(t, "increases the strength of [^%.]- by (" .. NUM .. ")")
  if a then return { kind = "stat", stat = "str", amount = num(a) } end
  a = match(t, "increases the agility of [^%.]- by (" .. NUM .. ")")
  if a then return { kind = "stat", stat = "agi", amount = num(a) } end
  return nil
end

local function weaponDE(t)
  local p, a = match(t, "(" .. NUM .. ")%% waffenschaden sowie mit jeder waffe zus" .. AE .. "tzlich (" .. NUM .. ")")
  if p then return { kind = "both", pct = num(p), bonus = num(a) } end
  -- "2 zusätzliche Angriffe mit 333 Punkt(en) zusätzlicher Nahkampfangriffskraft", "die Chance,
  -- zusätzlich zum erzielten Waffenschaden, Heiligschaden in Höhe von 70% des normalen
  -- Waffenschadens zuzufügen"
  local b
  a, b = match(t, "(" .. NUM .. ") zus" .. AE .. "tzliche[n]? angriffe? mit ([0-9%(%) %*%.]+)[^%.]-zus" .. AE
    .. "tzlicher nahkampfangriffskraft")
  if a then return { kind = "extra", attacks = num(a), amount = amountOf(b) } end
  b, p = match(t, "chance, zus" .. AE .. "tzlich zum erzielten waffenschaden, ([a-z]*)schaden in h" .. OE .. "he von ("
    .. NUM .. ")%% des normalen waffenschadens")
  if p then return { kind = "weapon", pct = num(p), bonus = 0, school = SCHOOL_DE[b] } end
  -- Forever's rank 1: "eine Chance, zusätzlichen Heiligschaden in Höhe von 70% des normalen
  -- Waffenschadens zu verursachen"
  b, p = match(t, "chance, zus" .. AE .. "tzlichen ([a-z]*)schaden in h" .. OE .. "he von (" .. NUM
    .. ")%% des normalen waffenschadens")
  if p then return { kind = "weapon", pct = num(p), bonus = 0, school = SCHOOL_DE[b] } end
  if find(t, "chance", 1, true) or find(t, "mit jeder waffe", 1, true) then return nil end
  local school, lo, hi = match(t, "jedem nahkampfangriff zus" .. AE .. "tzlichen ([a-z]*)schaden in h" .. OE .. "he von ("
    .. NUM .. ") %- (" .. NUM .. ")")
  if not lo then
    lo, hi, school = match(t, "jeder treffer f" .. UE .. "gt zus" .. AE .. "tzlich (" .. NUM .. ") bis (" .. NUM
      .. ") punkt%(e%) ([a-z]*)schaden")
  end
  -- Forever's own German: "Jeder Treffer fügt 3 bis 14 zusätzlichen Feuerschaden zu", and for the later
  -- Flametongue Totem ranks "Jeder Treffer der Haupthand fügt 9 bis 31 ..."
  if not lo then
    lo, hi, school = match(t, "jeder treffer [a-z ]-f" .. UE .. "gt (" .. NUM .. ") bis (" .. NUM .. ") zus" .. AE
      .. "tzlichen ([a-z]*)schaden")
  end
  if lo then
    return { kind = "perhit", min = num(lo), max = num(hi), school = SCHOOL_DE[school],
      bySpeed = find(t, "langsamere waffen verursachen mehr", 1, true) and true or nil }
  end
  -- Forever's Seal of Fury: "wodurch jeder Nahkampfangriff zusätzlich 14 Heiligschaden verursacht"
  a, school = match(t, "jeder nahkampfangriff zus" .. AE .. "tzlich (" .. NUM .. ") ([a-z]*)schaden")
  if a then return { kind = "perhit", min = num(a), max = num(a), school = SCHOOL_DE[school] } end
  p = match(t, "schaden, der (" .. NUM .. ")%% eurer angriffskraft entspricht")
  if p then return { kind = "appct", pct = num(p), bonus = 0 } end
  p, a = match(t, "(" .. NUM .. ")%% eurer angriffskraft plus (" .. NUM .. ")")
  if p then return { kind = "appct", pct = num(p), bonus = num(a) } end
  a = match(t, "pro sekunde den (" .. NUM .. ")%-fachen schaden eurer waffenhandwaffe")
    -- Forever's: "pro Sekunde Heiligschaden in Höhe des 3-fachen Schadens Eurer Waffenhandwaffe"
    or match(t, "pro sekunde [a-z]*schaden in h" .. OE .. "he des (" .. NUM .. ")%-fachen schadens eurer waffenhandwaffe")
  if a then return { kind = "dps", times = num(a), school = find(t, "heiligschaden", 1, true) and "holy" or "physical" } end
  p, a = match(t, "(" .. NUM .. ")%% [^%.]-schaden plus (" .. NUM .. ")")
  if p then return { kind = "weapon", pct = num(p), bonus = num(a) } end
  p = match(t, "(" .. NUM .. ")%% des normalen schadens")
  if p then return { kind = "weapon", pct = num(p), bonus = 0 } end
  -- Forever's Holy Strike: "29% Waffenschaden sowie zusätzlich 4 bis 6 als Heiligschaden"
  p, a, b = match(t, "(" .. NUM .. ")%% waffenschaden sowie zus" .. AE .. "tzlich (" .. NUM .. ") bis (" .. NUM .. ") als")
  if p then return { kind = "weapon", pct = num(p), bonus = num(a), bonusMax = num(b) } end
  -- Forever's Mongoose Bite: "in Höhe des Nahkampfwaffenschadens plus 15"
  a = match(t, "waffenschadens? plus (" .. NUM .. ")")
  if a then return { kind = "weapon", pct = 100, bonus = num(a) } end
  a = match(t, "waffenschaden sowie (" .. NUM .. ") zus" .. AE .. "tzlichen schaden")
  if a then return { kind = "weapon", pct = 100, bonus = num(a) } end
  a = match(t, "zus" .. AE .. "tzlich zu eurem normalen waffenschaden noch (" .. NUM .. ")")
  if a then return { kind = "weapon", pct = 100, bonus = num(a) } end
  if find(t, "verursacht waffenschaden bei jedem feind", 1, true) then
    return { kind = "weapon", pct = 100, bonus = 0 }
  end
  a = match(t, "mit klauen beharken und ihm so zus" .. AE .. "tzlich (" .. NUM .. ")")
  if a then return { kind = "weapon", pct = 100, bonus = num(a) } end
  a = match(t, "den nahkampfschaden um (" .. NUM .. ")")
  if a then return { kind = "next", bonus = num(a) } end
  a = match(t, "den n" .. AE .. "chsten angriffsschaden[^%.]- um (" .. NUM .. ")")
  if a then return { kind = "next", bonus = num(a) } end
  a = match(t, "den distanzschaden um (" .. NUM .. ")")
  if a then return { kind = "next", bonus = num(a), ranged = true } end
  -- "verleiht 306 Nahkampfangriffskraft. Außerdem greift der Paladin um 40% schneller an"
  a, p = match(t, "verleiht (" .. NUM .. ") nahkampfangriffskraft%. +au\195\159erdem greift der paladin um (" .. NUM
    .. ")%% schneller an")
  if a then return { kind = "ap", amount = num(a), faster = num(p) } end
  a = match(t, "erh" .. OE .. "ht die st" .. AE .. "rke [^%.]- um (" .. NUM .. ")")
  if a then return { kind = "stat", stat = "str", amount = num(a) } end
  a = match(t, "erh" .. OE .. "ht die beweglichkeit [^%.]- um (" .. NUM .. ")")
  if a then return { kind = "stat", stat = "agi", amount = num(a) } end
  return nil
end

-- One sentence that raises attack power: "increasing the melee attack power of all party
-- members within 20 yards by 185" / "wodurch sich die Nahkampfangriffskraft der Gruppe
-- innerhalb eines Radius von 20 Metern um 185 erhöht". The number is the first "by"/"um" after
-- the words attack power, so the 20 yards before it are passed over.
local function attackPowerIn(sentence, lang)
  if lang == "de" then
    if not find(sentence, "angriffskraft", 1, true) or not find(sentence, "erh" .. OE .. "h", 1, true) then return nil end
    if hasAny(sentence, REDUCE_VERBS.de) or find(sentence, "chance", 1, true) or find(sentence, "weniger schaden", 1, true) then
      return nil
    end
    local a = match(sentence, "angriffskraft[^%.]- um (" .. NUM .. ")")
    if not a then return nil end
    return { kind = "ap", amount = num(a), ranged = find(sentence, "distanzangriffskraft", 1, true) ~= nil,
      plusAgility = find(sentence, "um " .. a .. " plus beweglichkeit", 1, true) ~= nil }
  end
  local s = find(sentence, "attack power", 1, true)
  if not s then return nil end
  local before = sub(sentence, 1, s)
  if not find(before, "increas", 1, true) then return nil end
  if hasAny(sentence, REDUCE_VERBS.en) or find(sentence, "chance", 1, true) or find(sentence, "less damage", 1, true) then
    return nil
  end
  local a = match(sentence, "attack power[^%.]- by (" .. NUM .. ")")
  if not a then return nil end
  return { kind = "ap", amount = num(a), ranged = find(sentence, "ranged attack power", 1, true) ~= nil,
    plusAgility = find(sentence, "by " .. a .. " plus agility", 1, true) ~= nil }
end

function Parser.ParseWeapon(text, lang)
  if type(text) ~= "string" or text == "" then return nil end
  local t
  t, lang = prepare(text, lang)
  t = withoutJudgement(gsub(t, "^ +", ""), lang)
  local w
  if lang == "de" then w = weaponDE(t) else w = weaponEN(t) end
  if w then
    if (w.bonus and w.bonus < 0) or (w.pct and w.pct <= 0) then return nil end
    if w.kind == "extra" and not (w.amount and w.attacks > 0) then return nil end
    return w
  end
  for _, sentence in ipairs(splitSentences(t, lang)) do
    local ap = attackPowerIn(sentence, lang)
    if ap and ap.amount > 0 then return ap end
  end
  return nil
end

---------------------------------------------------------------------------------------------
-- Seals and Judgement
---------------------------------------------------------------------------------------------

-- ParseJudgement(text, lang): a seal's Judgement damage, from its last sentence, as
-- { direct = { min, max }, school }, or nil (a seal whose Judgement does no damage, or any other
-- spell). "Unleashing this Seal's energy will cause 170 to 187 Holy damage to an enemy." /
-- "Die Entfesselung der Energie dieses Siegels fügt einem Feind 170 bis 187 Heiligschaden zu."
-- Seal of Command's "169 to 186 Holy damage, 339 to 373 if the target is stunned" gives the
-- first range, the one that applies to a target that is not stunned.
function Parser.ParseJudgement(text, lang)
  if type(text) ~= "string" or text == "" then return nil end
  local t
  t, lang = prepare(text, lang)
  local s = find(t, JUDGE[lang] or JUDGE.en, 1, true)
  if not s then return nil end
  local part = sub(t, s)
  local lo, hi, school
  if lang == "de" then
    -- "Heiligschaden in Höhe von 169 bis 186, oder 339 bis 373 Heiligschaden, sollte das Ziel
    -- betäubt ... sein": the "in Höhe von" range first, or the stunned one would be taken
    school, lo, hi = match(part, "([a-z]*)schaden in h" .. OE .. "he von (" .. NUM .. ") bis (" .. NUM .. ")")
    if not lo then lo, hi, school = match(part, "(" .. NUM .. ") bis (" .. NUM .. ") ([a-z]*)schaden") end
    school = school and SCHOOL_DE[school]
  else
    lo, hi, school = match(part, "(" .. NUM .. ") to (" .. NUM .. ") ([a-z]+) damage")
    school = school and SCHOOL_EN[school]
  end
  if not lo then return nil end
  return { direct = { min = num(lo), max = num(hi) }, school = school }
end

-- Is this Judgement itself? Its description names no damage of its own and points at the seals:
-- "Unleashes the energy of a Seal spell upon an enemy." / "Entfesselt die Energie eines
-- Siegelzaubers über einem Feind."
function Parser.IsJudgement(text, lang)
  if type(text) ~= "string" or text == "" then return false end
  local t
  t, lang = prepare(text, lang)
  if lang == "de" then return find(t, "die energie eines siegelzaubers", 1, true) ~= nil end
  return find(t, "the energy of a seal spell", 1, true) ~= nil
end

-- Is this a seal? Every seal ends with what its Judgement does, damage or not.
function Parser.IsSeal(text, lang)
  if type(text) ~= "string" or text == "" then return false end
  local t
  t, lang = prepare(text, lang)
  return find(t, JUDGE[lang] or JUDGE.en, 1, true) ~= nil
end

-- How long a seal lasts, in seconds, or nil: "for 30 sec" / "Lasts 30 sec" / "30 Sek. lang".
function Parser.SealDuration(text, lang)
  if type(text) ~= "string" or text == "" then return nil end
  local t
  t, lang = prepare(withoutJudgement(text, lang), lang)
  local n
  if lang == "de" then
    n = match(t, "(" .. NUM .. ") sek%.? lang")
  else
    n = match(t, "for (" .. NUM .. ") sec") or match(t, "lasts (" .. NUM .. ") sec")
  end
  return num(n)
end

---------------------------------------------------------------------------------------------
-- Wordings Parse() does not take apart
---------------------------------------------------------------------------------------------
-- ParseSpecial(text, lang), used when Parse() finds nothing or cannot say what it finds, returns
-- Parse()'s shape
-- (direct, dot, heal, hot, school) with, where it applies:
--   absorb = n           a shield: Power Word: Shield, Ice Barrier, the wards
--   healMaxHealth = true Lay on Hands: the paladin's own maximum health
--   perAttack = true     a totem's attack (Searing Totem), perBlock = true (Holy Shield),
--   perStrike = true     damage to whatever strikes the party (Retribution Aura),
--   every = s            a totem's pulse (Healing Stream Totem), perRage = n (Execute)
-- Each pattern is one family's own wording, from the fixtures, in both languages.

local function D(lo, hi) return { min = num(lo), max = num(hi or lo) } end

local function specialEN(t)
  local lo, hi, school, hlo, hhi = match(t, "causing (" .. NUM .. ") to (" .. NUM .. ") ([a-z]+) damage to an enemy, or ("
    .. NUM .. ") to (" .. NUM .. ") healing to an ally")
  if lo then return { direct = D(lo, hi), heal = D(hlo, hhi), school = SCHOOL_EN[school] } end
  local n, h, iv, dur
  n, school, h, iv, dur = match(t, "causing (" .. NUM .. ") ([a-z]+) damage to an enemy, or (" .. NUM
    .. ") healing to an ally, instantly and every (" .. NUM .. ") sec for (" .. NUM .. ") sec")
  if n then
    local hits = 1 + floor(num(dur) / num(iv) + 0.5)
    return { direct = D(num(n) * hits), heal = D(num(h) * hits), school = SCHOOL_EN[school], hits = hits }
  end
  lo, hi, n, dur = match(t, "heals a friendly target for (" .. NUM .. ") to (" .. NUM .. "), an additional ("
    .. NUM .. ") over (" .. NUM .. ") sec")
  if lo then return { heal = D(lo, hi), hot = { total = num(n), duration = num(dur) } } end
  -- Forever's Consecration: "doing 24 Holy damage over 8 sec to enemies who enter the area The
  -- first 4 enemies who enter the area will take an additional 56 damage over 8 sec". Its German
  -- gives the two amounts the other way round; both say the first 4 take 24 + 56, which is shown.
  local extra, first
  n, school, dur, first, extra = match(t, "doing (" .. NUM .. ") ([a-z]+) damage over (" .. NUM .. ") sec to enemies who enter "
    .. "the area%.? +the first (" .. NUM .. ") enemies who enter the area will take an additional (" .. NUM .. ") damage")
  if n then
    return { dot = { total = num(n) + num(extra), duration = num(dur) }, school = SCHOOL_EN[school], first = num(first) }
  end
  n, school, dur = match(t, "doing (" .. NUM .. ") ([a-z]+) damage over (" .. NUM .. ") sec")
  if n then return { dot = { total = num(n), duration = num(dur) }, school = SCHOOL_EN[school] } end
  -- Tranquility: "Regenerates all nearby party members within 20 yards for 87 every 2 sec for 10 sec"
  local every
  n, every, dur = match(t, "regenerates [^%.]- for (" .. NUM .. ") every (" .. NUM .. ") sec[a-z]* for (" .. NUM .. ") sec")
  if n then return { hot = { total = num(n) * floor(num(dur) / num(every) + 0.5), duration = num(dur) } } end
  n, dur = match(t, "restore (" .. NUM .. ") health over (" .. NUM .. ") sec")
  if n then return { hot = { total = num(n), duration = num(dur) } } end
  local per
  n, per = match(t, "causing (" .. NUM .. ") damage and converting each extra point of rage into (" .. NUM .. ") additional damage")
  if n then return { direct = D(n), school = "physical", perRage = num(per) } end
  n, dur = match(t, "bleed for (" .. NUM .. ") damage over (" .. NUM .. ") sec")
  if n then return { dot = { total = num(n), duration = num(dur) }, school = "physical" } end
  lo, hi, school = match(t, "repeatedly attacks an enemy [^%.]- for (" .. NUM .. ") to (" .. NUM .. ") ([a-z]+) damage")
  if lo then return { direct = D(lo, hi), school = SCHOOL_EN[school], perAttack = true } end
  n, iv = match(t, "heals group members [^%.]- for (" .. NUM .. ") every (" .. NUM .. ") seconds?")
  if n then return { heal = D(n), every = num(iv) } end
  local f
  lo, hi, f, school = match(t, "drains (" .. NUM .. ") to (" .. NUM .. ") mana [^%.]-%. for each mana drained in this way, the target takes ("
    .. NUM .. ") ([a-z]+) damage")
  if lo then return { direct = D(num(lo) * num(f), num(hi) * num(f)), school = SCHOOL_EN[school] } end
  n, school = match(t, "causes (" .. NUM .. ") ([a-z]+) damage to any creature that strikes a party member")
  if n then return { direct = D(n), school = SCHOOL_EN[school], perStrike = true } end
  n, school = match(t, "deals (" .. NUM .. ") ([a-z]+) damage for each attack blocked")
  if n then return { direct = D(n), school = SCHOOL_EN[school], perBlock = true } end
  if find(t, "for an amount equal to the paladin's maximum health", 1, true) then return { healMaxHealth = true } end
  -- Seal of Light, per trigger: "giving each melee attack a chance to heal the Paladin for 94"
  n = match(t, "giving each melee attack a chance to heal the paladin for (" .. NUM .. ")")
  if n then return { heal = D(n) } end
  n = match(t, "absorbing (" .. NUM .. ") damage") or match(t, "absorbs (" .. NUM .. ") [a-z]* ?damage")
  if n then return { absorb = num(n) } end
  -- Life Tap: "Converts 58 Health into 58 Mana for you."
  local hc, mg = match(t, "converts (" .. NUM .. ") health into (" .. NUM .. ") mana")
  if hc then return { healthCost = num(hc), manaGain = num(mg) } end
  return nil
end

local function specialDE(t)
  -- Aderlass: the same cost/gain pair as English Life Tap.
  local hc, mg = match(t, "wandelt (" .. NUM .. ") gesundheit in (" .. NUM .. ") mana um")
  if hc then return { healthCost = num(hc), manaGain = num(mg) } end
  local lo, hi, school, hlo, hhi = match(t, "verursacht (" .. NUM .. ") bis (" .. NUM .. ") ([a-z]*)schaden bei feinden oder heilt ("
    .. NUM .. ") bis (" .. NUM .. ") bei verb" .. UE .. "ndeten")
  if lo then return { direct = D(lo, hi), heal = D(hlo, hhi), school = SCHOOL_DE[school] } end
  -- Penance: "die einem Gegner 240 Heiligschaden zufügt oder ein verbündetes Ziel sofort sowie
  -- 2 Sek. lang alle 1 Sek. um 572 Gesundheit heilt"
  local dmg, h, dur2, iv2
  -- Forever's Holy Shock: "die Gegnern 129 bis 139 Heiligschaden zufügt oder Verbündete um 110
  -- bis 118 Gesundheit heilt"
  lo, hi, school, hlo, hhi = match(t, "(" .. NUM .. ") bis (" .. NUM .. ") ([a-z]*)schaden zuf" .. UE .. "gt oder verb" .. UE
    .. "ndete um (" .. NUM .. ") bis (" .. NUM .. ") gesundheit heilt")
  if lo then return { direct = D(lo, hi), heal = D(hlo, hhi), school = SCHOOL_DE[school] } end
  dmg, school, dur2, iv2, h = match(t, "(" .. NUM .. ") ([a-z]*)schaden zuf" .. UE .. "gt oder ein verb" .. UE
    .. "ndetes ziel sofort sowie (" .. NUM .. ") sek%.? lang alle (" .. NUM .. ") sek%.? um (" .. NUM .. ") gesundheit heilt")
  if dmg then
    local hits = 1 + floor(num(dur2) / num(iv2) + 0.5)
    return { direct = D(num(dmg) * hits), heal = D(num(h) * hits), school = SCHOOL_DE[school], hits = hits }
  end
  -- Tranquility: "Regeneriert 10 Sek. lang alle 2 Sek. 87 Gesundheit", Wowhead's "Regeneriert bei
  -- allen Gruppenmitgliedern in der Nähe 10 Sek. lang alle 2 Sek. 98 Gesundheit"
  local dur0, every0, n0 = match(t, "regeneriert [^%.]-(" .. NUM .. ") sek%.? lang alle (" .. NUM .. ") sek%.? (" .. NUM
    .. ") gesundheit")
  if n0 then return { hot = { total = num(n0) * floor(num(dur0) / num(every0) + 0.5), duration = num(dur0) } } end
  local n, dur = match(t, "um im verlauf von (" .. NUM .. ") sek%.? (" .. NUM .. ") gesundheit wiederherzustellen")
  if n then return { hot = { total = num(dur), duration = num(n) } } end
  local per
  n, per = match(t, "verursacht (" .. NUM .. ") punkt%(e%) schaden und jeder zus" .. AE .. "tzliche wutpunkt wird in (" .. NUM .. ")")
  if n then return { direct = D(n), school = "physical", perRage = num(per) } end
  local iv
  iv, lo, hi, school = match(t, "alle (" .. NUM .. ") sekunden einen feind [^%.]- angreift und (" .. NUM .. ") bis (" .. NUM
    .. ") punkt%(e%) ([a-z]*)schaden")
  if lo then return { direct = D(lo, hi), school = SCHOOL_DE[school], perAttack = true } end
  iv, n = match(t, "alle (" .. NUM .. ") sekunden um (" .. NUM .. ") punkt%(e%) heilt")
  if n then return { heal = D(n), every = num(iv) } end
  local f
  lo, hi, f, school = match(t, "entzieht dem ziel (" .. NUM .. ") bis (" .. NUM .. ") punkte mana%. f" .. UE
    .. "r jeden [^%.]- erleidet das ziel (" .. NUM .. ") punkte ([a-z]*)schaden")
  if lo then return { direct = D(num(lo) * num(f), num(hi) * num(f)), school = SCHOOL_DE[school] } end
  n, school = match(t, "verursacht (" .. NUM .. ") punkt%(e%) ([a-z]*)schaden f" .. UE .. "r jede kreatur, die ein gruppenmitglied schl" .. AE .. "gt")
  -- Forever's: "Fügt jeder Kreatur, die ein Gruppenmitglied innerhalb von 30 Metern angreifen, 7
  -- Heiligschaden zu"
  if not n then
    n, school = match(t, "f" .. UE .. "gt jeder kreatur, die ein gruppenmitglied [^,]-, (" .. NUM .. ") ([a-z]*)schaden zu")
  end
  if n then return { direct = D(n), school = SCHOOL_DE[school], perStrike = true } end
  -- Forever's Consecration: "Gegner, die das Gebiet betreten, erleiden im Verlauf von 8 Sek. 56
  -- Heiligschaden"
  -- Heiligschaden. Die ersten 4 Gegner, die das Gebiet betreten, erleiden im Verlauf von 8 Sek.
  -- zusätzlich 24 Schaden": the first 4 take both, as in English
  local first, extra
  dur, n, school, first, extra = match(t, "erleiden im verlauf von (" .. NUM .. ") sek%.? (" .. NUM .. ") ([a-z]*)schaden%. +die "
    .. "ersten (" .. NUM .. ") gegner, die das gebiet betreten, erleiden im verlauf von " .. NUM .. " sek%.? zus" .. AE
    .. "tzlich (" .. NUM .. ") schaden")
  if n then
    return { dot = { total = num(n) + num(extra), duration = num(dur) }, school = SCHOOL_DE[school], first = num(first) }
  end
  dur, n, school = match(t, "erleiden im verlauf von (" .. NUM .. ") sek%.? (" .. NUM .. ") ([a-z]*)schaden")
  if n then return { dot = { total = num(n), duration = num(dur) }, school = SCHOOL_DE[school] } end
  -- Lacerate: "was im Verlauf von 15 Sek. 149 Blutungsschaden ... verursacht"
  dur, n = match(t, "im verlauf von (" .. NUM .. ") sek%.? (" .. NUM .. ") blutungsschaden")
  if n then return { dot = { total = num(n), duration = num(dur) }, school = "physical" } end
  n, school = match(t, "mit jedem geblockten angriff (" .. NUM .. ") ([a-z]*)schaden")
  -- Forever's: "verursacht, während der Effekt aktiv ist, mit jedem Blocken 110 Heiligschaden"
  if not n then n, school = match(t, "mit jedem blocken (" .. NUM .. ") ([a-z]*)schaden") end
  if n then return { direct = D(n), school = SCHOOL_DE[school], perBlock = true } end
  -- Forever's: "um einen Betrag, der der maximalen Gesundheit des Paladins entspricht"
  if find(t, "bis zur maximalen gesundheit des paladins", 1, true)
    or find(t, "der maximalen gesundheit des paladins entspricht", 1, true) then
    return { healMaxHealth = true }
  end
  -- "das jedem Nahkampfangriff eine Chance verleiht, den Paladin um 94 Punkt(e) zu heilen"
  n = match(t, "jedem nahkampfangriff eine chance verleiht, den paladin um (" .. NUM .. ") punkt%(e%) zu heilen")
  if n then return { heal = D(n) } end
  -- Forever's: "Absorbiert 162 Feuerschaden", "absorbiert 431 Schaden", "einen Schild, der 155
  -- Schaden absorbiert"
  n = match(t, "absorbiert dabei (" .. NUM .. ") punkt") or match(t, "absorbiert (" .. NUM .. ") punkt")
    or match(t, "absorbiert (" .. NUM .. ") [a-z]*schaden") or match(t, "der (" .. NUM .. ") schaden absorbiert")
  if n then return { absorb = num(n) } end
  return nil
end

function Parser.ParseSpecial(text, lang)
  if type(text) ~= "string" or text == "" then return nil end
  local t
  t, lang = prepare(text, lang)
  t = withoutJudgement(t, lang)
  if lang == "de" then return specialDE(t) end
  return specialEN(t)
end

---------------------------------------------------------------------------------------------
-- Finishers
---------------------------------------------------------------------------------------------
-- ParseFinisher(text, lang): a finisher's per-combo-point table as { points = { [1] = ...,
-- [5] = ... }, top = the highest point listed }, each entry { min, max } (Eviscerate, Ferocious
-- Bite) or { total, duration } (Rupture, Rip); nil for anything else, including per-point tables
-- of seconds or armour (Kidney Shot, Slice and Dice, Expose Armor). The numbers are the
-- description's own; the attack power the text says it adds is not in them.
function Parser.ParseFinisher(text, lang)
  if type(text) ~= "string" or text == "" then return nil end
  local t
  t, lang = prepare(text, lang)
  t = " " .. t .. " "
  local marker = (lang == "de") and "punkte?" or "points?"
  local marks, init = {}, 1
  while true do
    local s, e, n = find(t, "[^0-9]([1-5]) " .. marker .. " *:", init)
    if not s then break end
    marks[#marks + 1] = { s = s, e = e, n = tonumber(n) }
    init = e + 1
  end
  if #marks < 2 then return nil end
  local points, top, kind = {}, nil, nil
  for i, m in ipairs(marks) do
    local seg = sub(t, m.e + 1, marks[i + 1] and (marks[i + 1].s) or #t)
    local lo, hi = match(seg, "^ *(" .. NUM .. ")%-(" .. NUM .. ") ")
    local total, dur
    if lang == "de" then
      if lo and not find(seg, "schaden", 1, true) then lo = nil end
      -- "25 Schaden über 8 Sekunden", Forever's "44 Schaden über 12 Sek."
      total, dur = match(seg, "^ *(" .. NUM .. ") schaden " .. UE .. "ber (" .. NUM .. ") sek")
      if not total then total, dur = match(seg, "^ *(" .. NUM .. ") schaden im verlauf von (" .. NUM .. ") sek") end
    else
      if lo and not find(seg, "damage", 1, true) then lo = nil end
      total, dur = match(seg, "^ *(" .. NUM .. ") damage over (" .. NUM .. ") sec")
    end
    if lo then
      if kind and kind ~= "direct" then return nil end
      kind = "direct"
      points[m.n] = { min = num(lo), max = num(hi) }
    elseif total then
      if kind and kind ~= "dot" then return nil end
      kind = "dot"
      points[m.n] = { total = num(total), duration = num(dur) }
    else
      return nil
    end
    if not top or m.n > top then top = m.n end
  end
  return { points = points, top = top, kind = kind }
end

---------------------------------------------------------------------------------------------
-- Chance effects
---------------------------------------------------------------------------------------------
-- ProcChance(text, lang): the chance per hit of an effect that triggers on a hit, in percent, or
-- true where the text names no figure, or nil. The number shown for such a spell is what one
-- trigger does, and the tooltip says so. "Each hit has a 20% chance", "Each main hand hit has a
-- 20% chance", "Each strike has a 20% chance", "Each hit has a chance", "giving each melee
-- attack a chance", "granting each attack a chance", "Gives the Paladin a chance" / "Bei jedem
-- Treffer besteht eine Chance von 20%", "Bei jedem Schlag besteht eine Chance von 20%", "Bei
-- jedem Treffer besteht eine Chance,", "jedem Nahkampfangriff eine Chance verleiht", "gewährt
-- jedem Angriff die Chance", "gewährt ihm die Chance". A seal's Judgement is not looked at.
function Parser.ProcChance(text, lang)
  if type(text) ~= "string" or text == "" then return nil end
  local t
  t, lang = prepare(text, lang)
  t = withoutJudgement(t, lang)
  if lang == "de" then
    local p = match(t, "bei jedem [a-z]+ besteht eine chance von (" .. NUM .. ")%%")
    if p then return num(p) end
    if find(t, "bei jedem [a-z]+ besteht eine chance,") or find(t, "jedem nahkampfangriff eine chance", 1, true)
      or find(t, "jedem angriff die chance", 1, true) or find(t, "gew" .. AE .. "hrt ihm die chance", 1, true)
      or find(t, "gew" .. AE .. "hrt dem paladin eine chance", 1, true) then
      return true
    end
    return nil
  end
  local p = match(t, "each [a-z ]-hit has a (" .. NUM .. ")%% chance") or match(t, "each strike has a (" .. NUM .. ")%% chance")
  if p then return num(p) end
  if find(t, "each [a-z ]-hit has a chance") or find(t, "each melee attack a chance", 1, true)
    or find(t, "each attack a chance", 1, true) or find(t, "gives the paladin a chance", 1, true) then
    return true
  end
  return nil
end

---------------------------------------------------------------------------------------------
-- Everything one description gives, and which of it the addon shows
---------------------------------------------------------------------------------------------

-- ParseSpecial wins over Parse only where it knows something Parse's shape cannot say: a
-- shield, the paladin's own health, a totem's attack or pulse, damage per block, per strike or
-- per extra rage, several hits; or where it reads a part Parse missed (Forever's German Holy
-- Shock, whose damage Parse does not find beside the heal). Where both read the same numbers
-- (Rend, Blizzard), Parse stays. Life Tap's health cost is its own flag.
local SPECIAL_FLAGS = { "absorb", "healMaxHealth", "perAttack", "perBlock", "perStrike", "every", "perRage", "hits", "first", "healthCost" }
local SLOTS = { "direct", "dot", "heal", "hot" }

local function specialWins(s, parsed)
  for _, k in ipairs(SPECIAL_FLAGS) do
    if s[k] then return true end
  end
  for _, k in ipairs(SLOTS) do
    if s[k] and not parsed[k] then return true end
  end
  return false
end

-- A German client still shows some texts in English: Forever's does for spells Forever changed
-- ("Converts 52 Health into 52 Mana for you."). TextLanguage(text, lang) gives "en" for a text
-- with English words and not one German word, and lang otherwise.
-- Not "Sek.": the English texts of a German client have it too.
local GERMAN_WORDS = { " und ", " der ", " die ", " das ", " den ", " dem ", " des ", " ein", " um ", " mit ", " von ",
  " zu ", "schaden", " ihr ", " euch", " euer", " eure" }
local ENGLISH_WORDS = { " the ", " a ", " you", " for ", " and ", " of ", " to ", " with ", " from ", " into ", " is ",
  " by ", "damage", " sec" }

function Parser.TextLanguage(text, lang)
  if lang ~= "de" or type(text) ~= "string" then return lang end
  local t = " " .. gsub(gsub(text, "[\r\n]+", " "), "[A-Z]", asciiLower) .. " "
  if hasAny(t, ENGLISH_WORDS) and not hasAny(t, GERMAN_WORDS) then return "en" end
  return lang
end

-- The English text of a German client still has the client's German numbers and units:
-- "Cannibalize 1.290 of your own Health over 15 Sek.", "suffer 175 bis 189 Holy damage". They are
-- put the English way, so the English readers take them as they are meant.
local function englishNumbers(text)
  local t, prev = text, nil
  repeat prev = t; t = gsub(t, "([0-9])%.([0-9][0-9][0-9])", "%1%2") until t == prev
  t = gsub(t, "([0-9]),([0-9])", "%1.%2")
  t = gsub(t, "([0-9]) bis ([0-9])", "%1 to %2")
  t = gsub(t, "([0-9]) [Ss]ek%.", "%1 sec")
  t = gsub(t, "([0-9]) [Mm]in%.", "%1 min")
  return t
end

-- Read(text, lang, noWeapon) runs every reader once and decides, in one place, what the addon
-- shows for the spell (show):
--   "weapon"     the weapon or attack power view (not with noWeapon: Retail's descriptions
--                already hold the player's stats, and Parse reads their finished numbers)
--   "judgement"  Judgement itself: the active seal's Judgement
--   nil          a seal with nothing per hit (its Judgement belongs on Judgement's button), or
--                nothing read at all
--   "special", "parsed", "finisher"  as their readers say; a seal shows its special (Seal of
--                Light's heal per trigger), never the Judgement's numbers
-- The reduction is shown beside any of these, or alone. proc is ProcChance's answer: the number
-- shown is what one trigger does.
function Parser.Read(text, lang, noWeapon)
  local textLang = Parser.TextLanguage(text, lang)
  if lang == "de" and textLang == "en" then text = englishNumbers(text) end
  lang = textLang
  local e = {
    parsed = Parser.Parse(text, lang) or false,
    reduction = Parser.ParseReduction(text, lang) or false,
    weapon = Parser.ParseWeapon(text, lang) or false,
    special = Parser.ParseSpecial(text, lang) or false,
    finisher = Parser.ParseFinisher(text, lang) or false,
    judgement = Parser.ParseJudgement(text, lang) or false,
    isSeal = Parser.IsSeal(text, lang),
    isJudgement = Parser.IsJudgement(text, lang),
    sealDuration = Parser.SealDuration(text, lang),
    proc = Parser.ProcChance(text, lang) or false,
    lang = lang,
  }
  if e.weapon and not noWeapon then
    e.show = "weapon"
  elseif e.isJudgement then
    e.show = "judgement"
  elseif e.isSeal then
    e.show = e.special and "special" or nil
  elseif e.special and (not e.parsed or specialWins(e.special, e.parsed)) then
    e.show = "special"
  elseif e.parsed then
    e.show = "parsed"
  elseif e.finisher then
    e.show = "finisher"
  end
  return e
end

-- Exposed for the tests.
Parser._evalArithmetic = evalArithmetic
Parser._englishNumbers = englishNumbers

return Parser
