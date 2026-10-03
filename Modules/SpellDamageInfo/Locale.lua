-- BattleInfoTool module SpellDamageInfo: ported by tools/port.py from SpellDamageInfo/Locale.lua at 8269edd.
-- Change it there, or in tools/port.py; an edit made here is lost at the next port.
-- SpellDamageInfo: English and German strings, and number formatting.
-- Copyright (c) 2026 Ironship. GPL-3.0-or-later, see LICENSE.

local _, BIT = ...
-- Inside BattleInfoTool its own namespace; loaded on its own, the addon's table as before.
local ns = BIT and BIT.Module and BIT.Module("SpellDamageInfo") or BIT or {}

local Locales = {}
ns.Locales = Locales

Locales.en = {
  lang = "en",
  thousands = ",",
  decimal = ".",
  DAMAGE = "Damage",
  DOT = "Damage over time",
  HEAL = "Healing",
  HOT = "Healing over time",
  OVER = "%s in %s sec",
  ESTIMATE = "incl. +%s from spell power, estimate",
  REDUCE_DAMAGE = "Enemy damage: %s",
  REDUCE_AP = "Enemy attack power: %s",
  AP_SHORT = "AP", -- after a reduction of attack power on the button: "-48 AP"
  REDUCE_AP_HIT = "Enemy attack power: %s, about -%s damage per hit from your target (it attacks every %s sec)",
  PET = "pet",
  ON = "on",
  OFF = "off",
  HELP = {
    "SpellDamageInfo: damage and healing from each spell's description.",
    "/sdi - open the settings window (also in Options > AddOns)",
    "/sdi help - this list",
    "/sdi estimate [on|off] - add an estimate for your spell power",
    "/sdi button total|direct|off - number on the action buttons",
    "/sdi tooltip [on|off] - lines in the spell tooltip",
    "/sdi reduction [on|off] - show by how much a debuff lowers the enemy's damage (red)",
    "/sdi size 50-200 - size of the button numbers in percent (100 = default)",
    "/sdi position bottom|center|top - where the number sits on the button",
    "/sdi lang auto|en|de - addon interface language",
    "/sdi weapon [on|off] - potential damage of weapon abilities and attack power buffs (blue)",
    "/sdi misses [clear] - spells on your bars that give no number",
    "/sdi dump [all] - write your spellbook's descriptions (all: every class's) to the saved variables, for testing",
    "/sdi status - show the settings",
  },
  STATUS = "estimate: %s, button: %s, tooltip: %s, reduction: %s, weapon: %s, size: %d%%, position: %s, language: %s",
  BAR_ADDON = "A bar addon built on LibActionButton (Bartender4, ElvUI and others) is loaded: its buttons get no numbers, only Blizzard's action bars do. The tooltip lines still work.",
  BAD_ARG = "Unknown option. Type /sdi help for the commands.",
  WEAPON_LINE = "Potential damage: about %s (%s, estimate)",
  WEAPON_HIT = "weapon hit %s",
  WEAPON_HIT_RANGED = "ranged hit %s",
  WEAPON_PCT = "%s%% of %s",
  WEAPON_PLUS = "%s + %s",
  AP_LINE = "Attack power +%s%s: about +%s damage per hit (%s %s sec), estimate",
  AP_FASTER = "weapon %s%% faster,",
  AP_PLUS_AGILITY = " plus Agility",
  AP_WEAPON = "weapon",
  AP_RANGED = "ranged weapon",
  MISSES_NONE = "No spells without a number recorded.",
  MISSES_HEAD = "%d spells on your bars give no number:",
  MISSES_CLEARED = "List of spells without a number cleared.",
  PERHIT_LINE = "Each hit: +%s damage, about +%s on average",
  PERHIT_SPEED_LINE = "Each hit: +%s damage, slower weapons more; about +%s with your weapon (%s sec), estimate",
  STAT_LINE = "%s +%s (%s attack power): about +%s damage per hit (%s %s sec), estimate",
  STAT_STR = "Strength",
  STAT_AGI = "Agility",
  WEAPON_AP = "%s%% of attack power %s",
  WEAPON_DPS = "%s x weapon damage per second %s",
  WEAPON_BOTH = "%s%% of both weapon hits %s and %s, plus %s with each",
  WEAPON_EXTRA = "%s extra attacks: weapon hit %s + %s attack power",
  WEAPON_EXTRA_ONE = "%s extra attack: weapon hit %s + %s attack power",
  PROC_CHANCE = "Per trigger: %s%% chance on each hit",
  PROC = "Per trigger: a chance on each hit",
  ABSORB_LINE = "Absorbs: %s",
  PER_ATTACK = " per attack",
  PER_STRIKE = " to whatever strikes the party",
  PER_BLOCK = " per block",
  EVERY = " every %s sec",
  HITS = " in %d hits",
  FIRST = " for the first %d enemies",
  HEAL_MAX = " (your maximum health)",
  PER_RAGE = "Plus %s for each extra point of rage",
  FINISHER_CURRENT_NOTE = "At the current %d combo points, attack power not included; the others: %s",
  FINISHER_STATIC_NOTE = "Combo points not readable: static preview, attack power not included; %s",
  FINISHER_NONE_NOTE = "No combo points on the selected target yet: preview, attack power not included; %s",
  FROM_SEAL = "From %s",
  JUDGEMENT_LINE = "Judgement: %s damage",
  NO_SEAL = "No seal active: Judgement's damage comes from the seal.",
  DUMP_DONE = "%d spells written to the saved variables (%d not loaded yet: the same command again in a moment). They are saved at logout or /reload.",
  DUMP_WORKING = "Reading every class's spells; the client loads them over a few seconds...",
  DUMP_ALL_DONE = "%d spells written to the saved variables, %d did not load. They are saved at logout or /reload.",
  OPT_RETAIL = "Retail's descriptions already include your stats.",
  LANG_AUTO = "Auto (game)",
  LANG_EN = "English",
  LANG_DE = "Deutsch",
  -- options window
  OPT_LANGUAGE = "Language",
  OPT_LANGUAGE_TIP = "Addon interface language: Auto follows the game language, or choose English or German.",
  OPT_PREVIEW = "Live preview",
  OPT_PREVIEW_HINT = "Sample spells with 50 spell power and a 2.6 sec weapon hitting for 120, drawn by the same code as the numbers on your action bars.",
  OPT_PREVIEW_OFF = "No numbers on the buttons.",
  OPT_SAMPLE_1 = "Immolate",
  OPT_SAMPLE_2 = "Screech",
  OPT_SAMPLE_3 = "Curse of Weakness",
  OPT_SAMPLE_4 = "Heroic Strike",
  OPT_SAMPLE_5 = "Rockbiter Weapon",
  OPT_SAMPLE_6 = "Life Tap",
  OPT_BUTTON = "Number on buttons",
  OPT_BUTTON_TIP = "What the number on your action buttons shows: all the damage or healing (direct and over time), the direct part only, or nothing.",
  OPT_BUTTON_TOTAL = "Total",
  OPT_BUTTON_DIRECT = "Direct only",
  OPT_BUTTON_OFF = "Off",
  OPT_SIZE = "Number size",
  OPT_SIZE_TIP = "Size of the button numbers in percent of the default. A number too wide for its button is made smaller until it fits.",
  OPT_POSITION = "Number position",
  OPT_POSITION_TIP = "Where the number sits on the button. A reduction next to a damage number takes the opposite corner.",
  OPT_POS_BOTTOM = "Bottom",
  OPT_POS_CENTER = "Center",
  OPT_POS_TOP = "Top",
  OPT_ESTIMATE = "Spell power estimate",
  OPT_ESTIMATE_TIP = "Adds your spell power at the share the game's spell data gives each spell (the Classic coefficient rules where it has none); the tooltip says how much of the number is estimated. Pet spells never get it.",
  OPT_TOOLTIP = "Lines in the spell tooltip",
  OPT_TOOLTIP_TIP = "Adds the damage and healing to the spell's tooltip.",
  OPT_REDUCTION = "Enemy damage reductions in red",
  OPT_REDUCTION_TIP = "Shows in red, on the button and in the tooltip, by how much a debuff such as Curse of Weakness lowers the enemy's damage or attack power.",
  OPT_WEAPON = "Weapon abilities and attack power",
  OPT_WEAPON_TIP = "Shows in blue what an ability that hits with your weapon, or a spell that raises attack power, is worth per hit: estimated from your weapon's average hit and speed, read out of combat.",
  OPT_RESET = "Reset to defaults",
  OPT_RESET_DONE = "Settings reset to defaults.",
  OPT_LANG_CHANGED = "Addon interface language changed. Type /reload to update the settings window's labels.",
  OPT_OPEN = "Open SpellDamageInfo settings",
  OPT_PANEL_TEXT = "The settings have their own window with a live preview. You can also type /sdi.",
}

Locales.de = {
  lang = "de",
  thousands = ".",
  decimal = ",",
  DAMAGE = "Schaden",
  DOT = "Schaden \195\188ber Zeit",
  HEAL = "Heilung",
  HOT = "Heilung \195\188ber Zeit",
  OVER = "%s in %s Sek.",
  ESTIMATE = "inkl. +%s durch Zaubermacht, gesch\195\164tzt",
  REDUCE_DAMAGE = "Schaden des Gegners: %s",
  REDUCE_AP = "Angriffskraft des Gegners: %s",
  AP_SHORT = "AK",
  REDUCE_AP_HIT = "Angriffskraft des Gegners: %s, etwa -%s Schaden pro Treffer Eures Ziels (es greift alle %s Sek. an)",
  PET = "Begleiter",
  ON = "an",
  OFF = "aus",
  HELP = {
    "SpellDamageInfo: Schaden und Heilung aus der Zauberbeschreibung.",
    "/sdi - Einstellungsfenster \195\182ffnen (auch unter Optionen > AddOns)",
    "/sdi help - diese Liste",
    "/sdi estimate [on|off] - Sch\195\164tzung f\195\188r Eure Zaubermacht dazurechnen",
    "/sdi button total|direct|off - Zahl auf den Aktionstasten",
    "/sdi tooltip [on|off] - Zeilen im Zauber-Tooltip",
    "/sdi reduction [on|off] - zeigen, um wie viel ein Schw\195\164chungszauber den Schaden des Gegners senkt (rot)",
    "/sdi size 50-200 - Gr\195\182\195\159e der Zahlen auf den Tasten in Prozent (100 = Standard)",
    "/sdi position bottom|center|top - wo die Zahl auf der Taste steht",
    "/sdi lang auto|en|de - Sprache der Addon-Oberfl\195\164che",
    "/sdi weapon [on|off] - m\195\182glicher Schaden von Waffenf\195\164higkeiten und Angriffskraft-Buffs (blau)",
    "/sdi misses [clear] - Zauber auf Euren Leisten, die keine Zahl ergeben",
    "/sdi dump [all] - die Beschreibungen Eures Zauberbuchs (all: aller Klassen) zum Testen in die gespeicherten Variablen schreiben",
    "/sdi status - Einstellungen anzeigen",
  },
  STATUS = "Sch\195\164tzung: %s, Tasten: %s, Tooltip: %s, Schw\195\164chung: %s, Waffe: %s, Gr\195\182\195\159e: %d%%, Position: %s, Sprache: %s",
  BAR_ADDON = "Ein Leisten-Addon mit LibActionButton (Bartender4, ElvUI und andere) ist geladen: seine Tasten bekommen keine Zahlen, nur Blizzards Aktionsleisten. Die Tooltip-Zeilen funktionieren weiter.",
  BAD_ARG = "Unbekannte Option. /sdi help zeigt die Befehle.",
  WEAPON_LINE = "M\195\182glicher Schaden: etwa %s (%s, gesch\195\164tzt)",
  WEAPON_HIT = "Waffentreffer %s",
  WEAPON_HIT_RANGED = "Distanztreffer %s",
  WEAPON_PCT = "%s %% von %s",
  WEAPON_PLUS = "%s + %s",
  AP_LINE = "Angriffskraft +%s%s: etwa +%s Schaden pro Treffer (%s %s Sek.), gesch\195\164tzt",
  AP_FASTER = "Waffe %s %% schneller,",
  AP_PLUS_AGILITY = " plus Beweglichkeit",
  AP_WEAPON = "Waffe",
  AP_RANGED = "Distanzwaffe",
  MISSES_NONE = "Keine Zauber ohne Zahl erfasst.",
  MISSES_HEAD = "%d Zauber auf Euren Leisten ergeben keine Zahl:",
  MISSES_CLEARED = "Liste der Zauber ohne Zahl geleert.",
  PERHIT_LINE = "Jeder Treffer: +%s Schaden, im Schnitt etwa +%s",
  PERHIT_SPEED_LINE = "Jeder Treffer: +%s Schaden, langsamere Waffen mehr; etwa +%s mit Eurer Waffe (%s Sek.), gesch\195\164tzt",
  STAT_LINE = "%s +%s (%s Angriffskraft): etwa +%s Schaden pro Treffer (%s %s Sek.), gesch\195\164tzt",
  STAT_STR = "St\195\164rke",
  STAT_AGI = "Beweglichkeit",
  WEAPON_AP = "%s %% der Angriffskraft %s",
  WEAPON_DPS = "%s x Waffenschaden pro Sekunde %s",
  WEAPON_BOTH = "%s %% beider Waffentreffer %s und %s, plus je %s",
  WEAPON_EXTRA = "%s zus\195\164tzliche Angriffe: Waffentreffer %s + %s Angriffskraft",
  WEAPON_EXTRA_ONE = "%s zus\195\164tzlicher Angriff: Waffentreffer %s + %s Angriffskraft",
  PROC_CHANCE = "Pro Ausl\195\182sung: %s %% Chance bei jedem Treffer",
  PROC = "Pro Ausl\195\182sung: eine Chance bei jedem Treffer",
  ABSORB_LINE = "Absorbiert: %s",
  PER_ATTACK = " pro Angriff",
  PER_STRIKE = " f\195\188r jeden, der die Gruppe trifft",
  PER_BLOCK = " pro Block",
  EVERY = " alle %s Sek.",
  HITS = " in %d Treffern",
  FIRST = " f\195\188r die ersten %d Gegner",
  HEAL_MAX = " (Eure maximale Gesundheit)",
  PER_RAGE = "Plus %s f\195\188r jeden zus\195\164tzlichen Wutpunkt",
  FINISHER_CURRENT_NOTE = "Bei den aktuellen %d Combopunkten, ohne Angriffskraft; die \195\188brigen: %s",
  FINISHER_STATIC_NOTE = "Combopunkte nicht ablesbar: statische Vorschau, ohne Angriffskraft; %s",
  FINISHER_NONE_NOTE = "Noch keine Combopunkte am Ziel: Vorschau, ohne Angriffskraft; %s",
  FROM_SEAL = "Aus %s",
  JUDGEMENT_LINE = "Richturteil: %s Schaden",
  NO_SEAL = "Kein Siegel aktiv: der Schaden des Richturteils kommt vom Siegel.",
  DUMP_DONE = "%d Zauber in die gespeicherten Variablen geschrieben (%d noch nicht geladen: gleich noch einmal derselbe Befehl). Gespeichert wird beim Ausloggen oder mit /reload.",
  DUMP_WORKING = "Lese die Zauber aller Klassen; der Client l\195\164dt sie im Lauf einiger Sekunden ...",
  DUMP_ALL_DONE = "%d Zauber in die gespeicherten Variablen geschrieben, %d nicht geladen. Gespeichert wird beim Ausloggen oder mit /reload.",
  OPT_RETAIL = "Die Beschreibungen in Retail enthalten Eure Werte bereits.",
  LANG_AUTO = "Auto (Spiel)",
  LANG_EN = "English",
  LANG_DE = "Deutsch",
  -- options window
  OPT_LANGUAGE = "Sprache",
  OPT_LANGUAGE_TIP = "Sprache der Addon-Oberfl\195\164che: Auto folgt der Spielsprache, oder w\195\164hlt English oder Deutsch.",
  OPT_PREVIEW = "Vorschau",
  OPT_PREVIEW_HINT = "Beispielzauber mit 50 Zaubermacht und einer 2,6-Sek.-Waffe mit 120 Schaden pro Treffer, gezeichnet vom selben Code wie die Zahlen auf Euren Aktionsleisten.",
  OPT_PREVIEW_OFF = "Keine Zahlen auf den Tasten.",
  OPT_SAMPLE_1 = "Feuerbrand",
  OPT_SAMPLE_2 = "Kreischen",
  OPT_SAMPLE_6 = "Aderlass",
  OPT_SAMPLE_3 = "Fluch der Schw\195\164che",
  OPT_SAMPLE_4 = "Heldenhafter Sto\195\159",
  OPT_SAMPLE_5 = "Waffe des Felsbei\195\159ers",
  OPT_BUTTON = "Zahl auf den Tasten",
  OPT_BUTTON_TIP = "Was die Zahl auf den Aktionstasten zeigt: den ganzen Schaden oder die ganze Heilung (direkt und \195\188ber Zeit), nur den direkten Teil oder nichts.",
  OPT_BUTTON_TOTAL = "Gesamt",
  OPT_BUTTON_DIRECT = "Nur direkt",
  OPT_BUTTON_OFF = "Aus",
  OPT_SIZE = "Gr\195\182\195\159e der Zahl",
  OPT_SIZE_TIP = "Gr\195\182\195\159e der Zahlen in Prozent der Standardgr\195\182\195\159e. Eine Zahl, die zu breit f\195\188r ihre Taste ist, wird verkleinert, bis sie passt.",
  OPT_POSITION = "Position der Zahl",
  OPT_POSITION_TIP = "Wo die Zahl auf der Taste steht. Eine Schw\195\164chung neben einer Schadenszahl nimmt die gegen\195\188berliegende Ecke.",
  OPT_POS_BOTTOM = "Unten",
  OPT_POS_CENTER = "Mitte",
  OPT_POS_TOP = "Oben",
  OPT_ESTIMATE = "Zaubermacht sch\195\164tzen",
  OPT_ESTIMATE_TIP = "Rechnet Eure Zaubermacht mit dem Anteil dazu, den die Spieldaten jedem Zauber geben (nach den Classic-Koeffizienten, wo sie keinen nennen); der Tooltip sagt, wie viel davon gesch\195\164tzt ist. Begleiterzauber bekommen keine Sch\195\164tzung.",
  OPT_TOOLTIP = "Zeilen im Zauber-Tooltip",
  OPT_TOOLTIP_TIP = "F\195\188gt dem Zauber-Tooltip Schaden und Heilung hinzu.",
  OPT_REDUCTION = "Schw\195\164chung des Gegners in Rot",
  OPT_REDUCTION_TIP = "Zeigt in Rot, auf der Taste und im Tooltip, um wie viel ein Schw\195\164chungszauber wie Fluch der Schw\195\164che den Schaden oder die Angriffskraft des Gegners senkt.",
  OPT_WEAPON = "Waffenf\195\164higkeiten und Angriffskraft",
  OPT_WEAPON_TIP = "Zeigt in Blau, was eine F\195\164higkeit mit Eurer Waffe oder ein Zauber, der die Angriffskraft erh\195\182ht, pro Treffer ausmacht: gesch\195\164tzt aus dem durchschnittlichen Treffer und dem Tempo Eurer Waffe, au\195\159erhalb des Kampfes gelesen.",
  OPT_RESET = "Standard wiederherstellen",
  OPT_RESET_DONE = "Einstellungen auf Standard zur\195\188ckgesetzt.",
  OPT_LANG_CHANGED = "Sprache der Addon-Oberfl\195\164che ge\195\164ndert. Gebt /reload ein, um die Beschriftungen des Einstellungsfensters zu aktualisieren.",
  OPT_OPEN = "SpellDamageInfo-Einstellungen \195\182ffnen",
  OPT_PANEL_TEXT = "Die Einstellungen haben ein eigenes Fenster mit Vorschau. Ihr k\195\182nnt auch /sdi eingeben.",
}

-- Interface language: what the addon's own UI shows (labels, chat lines, number formatting).
-- Stored in SavedVariables; "auto" means follow GetLocale(). Not decided until ADDON_LOADED.
local interfaceLang = nil
ns.InterfaceLang = function() return interfaceLang end

-- Description language: what the parser reads. Decided at login from textLocale CVar if it is
-- "deDE", else from GetLocale(), and cannot be changed (the player would only see spell descriptions
-- in one language anyway). Core.lua passes it to Parser.Parse and Parser.ParseReduction.
local descriptionLang = nil
ns.DescriptionLang = function() return descriptionLang end

-- Locale table that code captured at file load uses (e.g. "local L = ns.L" in Core.lua).
-- When the interface language changes, this table's contents are replaced to apply the switch
-- live wherever code reads L.KEY when it runs, "local L = ns.L" included, since that is this
-- same table. Only text already set into a widget waits for the window to be rebuilt (/reload).
local L = {}
ns.L = L

-- Returns the locale string ("deDE", "enUS", etc.) for the description language.
local function getDescriptionLocale()
  local locale = nil
  if type(C_CVar) == "table" and type(C_CVar.GetCVar) == "function" then
    local ok, result = pcall(C_CVar.GetCVar, "textLocale")
    if ok and result == "deDE" then locale = "deDE" end
  end
  if not locale and type(GetCVar) == "function" then
    local ok, result = pcall(GetCVar, "textLocale")
    if ok and result == "deDE" then locale = "deDE" end
  end
  if not locale and type(GetLocale) == "function" then
    locale = GetLocale()
  end
  return locale or "enUS"
end

-- Decide the description language at addon load, and set up ns.L with the interface strings.
function ns.DecideLangsAtLoad()
  local descLocale = getDescriptionLocale()
  descriptionLang = (descLocale == "deDE") and "de" or "en"
end

-- Set the interface language and refresh ns.L. "auto" -> follow GetLocale().
function ns.SetInterfaceAndRefreshL(lang)
  interfaceLang = lang or "auto"
  local locale = (interfaceLang == "auto") and ((type(GetLocale) == "function") and GetLocale() or "enUS") or "en"
  if interfaceLang == "de" or interfaceLang == "auto" and locale == "deDE" then
    for k, v in pairs(Locales.de) do L[k] = v end
  else
    for k, v in pairs(Locales.en) do L[k] = v end
  end
end

-- Init: called at ADDON_LOADED to set up the interface language from SavedVariables.
function ns.InitInterfaceL(savedLang)
  ns.SetInterfaceAndRefreshL(savedLang or "auto")
end

local Format = {}
ns.Format = Format

local floor = math.floor

local function round(v) return floor(v + 0.5) end

-- 1305 -> "1,305" (en) / "1.305" (de)
function Format.Thousands(v, L)
  local s = tostring(round(v))
  local neg = s:sub(1, 1) == "-"
  if neg then s = s:sub(2) end
  local out = s
  while true do
    local changed
    out, changed = out:gsub("^(%d+)(%d%d%d)", "%1" .. L.thousands .. "%2")
    if changed == 0 then break end
  end
  return (neg and "-" or "") .. out
end

-- Durations: 15 -> "15", 7.1 -> "7.1" / "7,1"
function Format.Seconds(v, L)
  if v == floor(v) then return tostring(floor(v)) end
  local s = string.format("%.1f", v)
  return (s:gsub("%.", L.decimal))
end

-- Short text for an action button: up to 9999 as it is, then "12k".
function Format.Short(v)
  v = round(v)
  if v < 10000 then return tostring(v) end
  return tostring(floor(v / 1000 + 0.5)) .. "k"
end

local function rangeText(r, L)
  local lo, hi = round(r.min), round(r.max)
  if lo == hi then return Format.Thousands(lo, L) end
  return Format.Thousands(lo, L) .. "-" .. Format.Thousands(hi, L)
end

local function suffix(added, L)
  if added and added >= 0.5 then
    return " (" .. string.format(L.ESTIMATE, Format.Thousands(added, L)) .. ")"
  end
  return ""
end

local DAMAGE_COLOR = { 1, 0.82, 0.3 }
-- Potential damage from the weapon and attack power: its own colour, because it is an estimate
-- from the weapon's numbers rather than a figure the spell itself states.
local WEAPON_COLOR = { 0.45, 0.85, 1 }
local HEAL_COLOR = { 0.4, 1, 0.4 }
local REDUCTION_COLOR = { 1, 0.25, 0.25 }
-- What a shield absorbs is neither damage nor healing, so it takes neither of their colours.
local ABSORB_COLOR = { 0.8, 0.7, 1 }
-- Notes under a number.
local NOTE_COLOR = { 0.7, 0.7, 0.7 }

-- The amount of a reduction from Parser.ParseReduction: "-3", "-146", "-10%", "-7.5%".
-- L (optional) gives the decimal mark.
local function reductionAmount(r, L)
  if r.percent then
    local s
    if r.amount == floor(r.amount) then s = tostring(floor(r.amount)) else s = string.format("%.1f", r.amount) end
    if L then s = (s:gsub("%.", L.decimal)) end
    return "-" .. s .. "%"
  end
  return "-" .. Format.Short(r.amount)
end
Format.ReductionAmount = reductionAmount

-- A reduction as button text: the amount, and for attack power its short name, so "-48 AP" is not
-- read as 48 damage ("-3", "-10%" for damage). perHit: what a lower attack power takes off each of the
-- target's hits (Core's ns.ReductionPerHit), shown instead: "-7". L (optional) gives the decimal mark
-- and the name.
function Format.ReductionText(r, L, perHit)
  if perHit then return "-" .. Format.Short(perHit) end
  local s = reductionAmount(r, L)
  if r.stat == "attackpower" then s = s .. " " .. ((L and L.AP_SHORT) or "AP") end
  return s
end

-- The tooltip line for a reduction: { text, r, g, b }. perHit and speed: what a lower attack power
-- takes off each hit of the target, which attacks every speed seconds.
function Format.ReductionLine(r, L, perHit, speed)
  local template = (r.stat == "attackpower") and L.REDUCE_AP or L.REDUCE_DAMAGE
  local amount = r.percent and reductionAmount(r, L) or ("-" .. Format.Thousands(r.amount, L))
  if r.stat == "attackpower" and perHit and speed and L.REDUCE_AP_HIT then
    local text = string.format(L.REDUCE_AP_HIT, amount, Format.Thousands(perHit, L), Format.Seconds(speed, L))
    return { text, REDUCTION_COLOR[1], REDUCTION_COLOR[2], REDUCTION_COLOR[3] }
  end
  return { string.format(template, amount), REDUCTION_COLOR[1], REDUCTION_COLOR[2], REDUCTION_COLOR[3] }
end

-- The tooltip line for a weapon view from ns.WeaponView: { text, r, g, b }.
--   "Potential damage: about 412 (225% of weapon hit 103 + 180, estimate)"
--   "Attack power +554: about +103 damage per hit (weapon 2.6 sec), estimate"
--   "Each hit: +22-75 damage, about +49 on average"
--   "Each hit: +22-75 damage, slower weapons more; about +49 with your weapon (2.6 sec), estimate"
function Format.WeaponLine(w, L)
  local c = WEAPON_COLOR
  if w.perhit then
    if w.speed then
      local text = string.format(L.PERHIT_SPEED_LINE, rangeText(w, L), Format.Thousands(w.gain, L), Format.Seconds(w.speed, L))
      return { text, c[1], c[2], c[3] }
    end
    return { string.format(L.PERHIT_LINE, rangeText(w, L), Format.Thousands(w.gain, L)), c[1], c[2], c[3] }
  end
  if w.stat then
    local text = string.format(L.STAT_LINE, (w.stat == "str") and L.STAT_STR or L.STAT_AGI, Format.Thousands(w.amount, L),
      Format.Thousands(w.amount * w.factor, L), Format.Thousands(w.gain, L), L.AP_WEAPON, Format.Seconds(w.speed, L))
    return { text, c[1], c[2], c[3] }
  end
  if w.gain then
    local weapon = w.ranged and L.AP_RANGED or L.AP_WEAPON
    if w.faster then weapon = string.format(L.AP_FASTER, Format.Thousands(w.faster, L)) end
    local text = string.format(L.AP_LINE, Format.Thousands(w.amount, L), w.plusAgility and L.AP_PLUS_AGILITY or "",
      Format.Thousands(w.gain, L), weapon, Format.Seconds(w.speed, L))
    return { text, c[1], c[2], c[3] }
  end
  local body
  if w.appct then
    body = string.format(L.WEAPON_AP, Format.Thousands(w.pct, L), Format.Thousands(w.ap, L))
    if w.bonus > 0 then body = string.format(L.WEAPON_PLUS, body, Format.Thousands(w.bonus, L)) end
  elseif w.dps then
    body = string.format(L.WEAPON_DPS, Format.Thousands(w.times, L), Format.Seconds(w.dps, L))
  elseif w.both then
    body = string.format(L.WEAPON_BOTH, Format.Thousands(w.pct, L), Format.Thousands(w.hit, L),
      w.off and Format.Thousands(w.off, L) or "-", Format.Thousands(w.bonus, L))
  elseif w.extra then
    body = string.format((w.attacks == 1) and L.WEAPON_EXTRA_ONE or L.WEAPON_EXTRA, Format.Thousands(w.attacks, L),
      Format.Thousands(w.hit, L), Format.Thousands(w.amount, L))
  else
    body = string.format(w.ranged and L.WEAPON_HIT_RANGED or L.WEAPON_HIT, Format.Thousands(w.hit, L))
    if w.pct ~= 100 then body = string.format(L.WEAPON_PCT, Format.Thousands(w.pct, L), body) end
    if w.bonusMax then
      body = string.format(L.WEAPON_PLUS, body, Format.Thousands(w.bonus, L) .. "-" .. Format.Thousands(w.bonusMax, L))
    elseif w.bonus > 0 then
      body = string.format(L.WEAPON_PLUS, body, Format.Thousands(w.bonus, L))
    end
  end
  return { string.format(L.WEAPON_LINE, Format.Thousands(w.value, L), body), c[1], c[2], c[3] }
end

-- A seal's Judgement, for the seal's own tooltip: { text, r, g, b }.
function Format.JudgementLine(j, L)
  return { string.format(L.JUDGEMENT_LINE, rangeText(j.direct, L)), DAMAGE_COLOR[1], DAMAGE_COLOR[2], DAMAGE_COLOR[3] }
end

-- A chance effect's note: the number is what one trigger does.
local function procLine(proc, L)
  local text = (proc == true) and L.PROC or string.format(L.PROC_CHANCE, Format.Thousands(proc, L))
  return { text, NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3] }
end

-- Tooltip lines for a view: a list of { text, r, g, b }.
function Format.TooltipLines(view, L)
  local lines = {}
  if not view then return lines end
  if view.weapon then
    lines[1] = Format.WeaponLine(view.weapon, L)
    if view.proc then lines[2] = procLine(view.proc, L) end
    return lines
  end
  if view.absorb then
    lines[1] = { string.format(L.ABSORB_LINE, Format.Thousands(view.absorb, L)), ABSORB_COLOR[1], ABSORB_COLOR[2], ABSORB_COLOR[3] }
    return lines
  end
  if view.healthCost then
    lines[1] = { "-" .. Format.Thousands(view.healthCost, L) .. " HP", HEAL_COLOR[1], HEAL_COLOR[2], HEAL_COLOR[3] }
    if view.manaGain and view.manaGain >= 0.5 then
      lines[2] = { "+" .. Format.Thousands(view.manaGain, L) .. " mana", WEAPON_COLOR[1], WEAPON_COLOR[2], WEAPON_COLOR[3] }
    end
    return lines
  end
  -- what the number is for, after the first figure: per totem attack, per block, per pulse, in
  -- how many hits, or the paladin's own health
  local note = ""
  if view.perAttack then note = L.PER_ATTACK
  elseif view.perBlock then note = L.PER_BLOCK
  elseif view.perStrike then note = L.PER_STRIKE
  elseif view.every then note = string.format(L.EVERY, Format.Seconds(view.every, L))
  elseif view.hits then note = string.format(L.HITS, view.hits)
  elseif view.first then note = string.format(L.FIRST, view.first)
  elseif view.healMax then note = L.HEAL_MAX end
  local function add(label, body, added, color)
    lines[#lines + 1] = { label .. ": " .. body .. note .. suffix(added, L), color[1], color[2], color[3] }
  end
  local function periodic(p)
    return string.format(L.OVER, Format.Thousands(p.total, L), Format.Seconds(p.duration, L))
  end
  if view.direct then add(L.DAMAGE, rangeText(view.direct, L), view.direct.added, DAMAGE_COLOR) end
  if view.dot then add(L.DOT, periodic(view.dot), view.dot.added, DAMAGE_COLOR) end
  if view.heal then add(L.HEAL, rangeText(view.heal, L), view.heal.added, HEAL_COLOR) end
  if view.hot then add(L.HOT, periodic(view.hot), view.hot.added, HEAL_COLOR) end
  if view.perRage then
    lines[#lines + 1] = { string.format(L.PER_RAGE, Format.Thousands(view.perRage, L)), DAMAGE_COLOR[1], DAMAGE_COLOR[2], DAMAGE_COLOR[3] }
  end
  local f = view.finisher
  if f then
    local at = view.finisherAt
    if at and at.known and at.n and at.n >= 1 and at.n <= f.top then
      -- the numbers above are for the count the selected target has right now; the note names
      -- that count and lists the other rows, each with its own points
      local others = {}
      for i = 1, f.top do
        local p = f.points[i]
        if p and i ~= at.n then
          others[#others + 1] = tostring(i) .. ": " .. (p.total and Format.Thousands(p.total, L) or rangeText(p, L))
        end
      end
      lines[#lines + 1] = { string.format(L.FINISHER_CURRENT_NOTE, at.n, table.concat(others, " / ")),
        NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3] }
    else
      -- zero combo points (or no selected target), or a count the client cannot say: the whole
      -- parsed table as an explicit preview, never a precise amount pretending to be current
      local others = {}
      for i = 1, f.top do
        local p = f.points[i]
        if p then
          others[#others + 1] = tostring(i) .. ": " .. (p.total and Format.Thousands(p.total, L) or rangeText(p, L))
        end
      end
      local note = (at and at.known and at.n == 0) and L.FINISHER_NONE_NOTE or L.FINISHER_STATIC_NOTE
      lines[#lines + 1] = { string.format(note, table.concat(others, " / ")),
        NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3] }
    end
  end
  if view.fromSeal then
    lines[#lines + 1] = { string.format(L.FROM_SEAL, view.fromSeal), NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3] }
  end
  if view.proc then lines[#lines + 1] = procLine(view.proc, L) end
  return lines
end

Format.DAMAGE_COLOR = DAMAGE_COLOR
Format.HEAL_COLOR = HEAL_COLOR
Format.REDUCTION_COLOR = REDUCTION_COLOR
Format.WEAPON_COLOR = WEAPON_COLOR
Format.ABSORB_COLOR = ABSORB_COLOR
Format.NOTE_COLOR = NOTE_COLOR
