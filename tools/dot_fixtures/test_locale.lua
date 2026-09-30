-- Feeds every English and German description in tools/data/locale_cases.lua through the addon's real parser
-- (parseDot and the name-keyed tables, cut out of Modules/DoTInfo/Core.lua, with Locale.lua loaded first) and
-- checks total, school, duration, tick interval, ignore list and tick shape against values read from the text by
-- tools/make_locale_cases.py. Also checks that every English description parses exactly as the v0.5.0 parser
-- (tools/data/upstream_parser_v0.5.0.lua) did.
--
--     lua tools/test_locale.lua                      (any Lua 5.1+; WoW runs 5.1: python tools/test_locale.py)
--     lua tools/test_locale.lua path/to/Core.lua   (another copy of the addon, e.g. the unmodified one)

local root = TEST_ROOT or ((arg and arg[0] or ""):match("^(.*)[/\\]tools[/\\][^/\\]*$") or ".")
local source = TEST_SOURCE or (arg and arg[1]) or (root .. "/Modules/DoTInfo/Core.lua")
local loadString = loadstring or load

local function readFile(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return (text:gsub("\r\n", "\n"))
end

local function run(code, name, ...)
    return assert(loadString(code, "@" .. name))(...)
end

-- The addon: Locale.lua, then the parser chunks of Core.lua (same cut as tools/test_parse.py).
local ns = {}
ns.Module = function(name) return ns end
run(readFile(root .. "/Modules/DoTInfo/Locale.lua"), "Locale.lua", "BattleInfoTool", ns)
local src = readFile(source)
local function chunk(startMarker, endMarker)
    local first = assert(src:find(startMarker, 1, true), startMarker)
    local last = assert(src:find(endMarker, first, true), endMarker)
    return src:sub(first, last - 1)
end
local addon = run(table.concat({
    "local ns = ...",
    "local function isSecret(v) return false end",
    chunk("local DEFAULT_TICK_INTERVAL", "local TICK_MATCH_WINDOW"),
    chunk("-- Tick intervals that differ", "-- User options"),
    chunk("local function schoolFromWords", "---------------------------------------------------------------------------\n-- DoT tracking"),
    "return { parseDot = parseDot, intervals = KNOWN_TICK_INTERVALS, shapes = TICK_SHAPES,",
    "    schools = SCHOOL_BY_NAME, ignored = IGNORED_SPELLS, defaultInterval = DEFAULT_TICK_INTERVAL,",
    "    nameTables = NAME_TABLES }",
}, "\n"), "Core.lua", ns)
local upstreamParse = run(readFile(root .. "/tools/dot_fixtures/data/upstream_parser_v0.5.0.lua"), "upstream_parser_v0.5.0.lua")
local cases = run(readFile(root .. "/tools/dot_fixtures/data/locale_cases.lua"), "locale_cases.lua")

local passed, failed, shown = 0, 0, 0
local failedByLang = { en = 0, de = 0 }
local function check(case, what, actual, expected)
    if actual == expected then
        passed = passed + 1
        return
    end
    failed = failed + 1
    failedByLang[case.lang] = failedByLang[case.lang] + 1
    shown = shown + 1
    if shown <= 40 then
        print(string.format("FAIL  %s %s %s (%d): %s = %s, expected %s", case.lang, case.source, case.name, case.id,
            what, tostring(actual), tostring(expected)))
    end
end

-- What the addon would track for this cast: onPlayerCast's use of parseDot and the name tables.
local function track(case, comboPoints)
    local total, school, duration, stated = addon.parseDot(case.desc, comboPoints)
    if not total then return nil end
    return {
        total = total,
        school = addon.schools[case.name] or school,
        duration = duration,
        interval = stated or addon.intervals[case.name] or addon.defaultInterval,
    }
end

local function checkReading(case, label, got, want)
    if not want then
        check(case, label .. " parsed", got and "a DoT" or "nothing", "nothing")
    elseif not got then
        check(case, label .. " parsed", "nothing", "a DoT")
    else
        for _, field in ipairs({ "total", "school", "duration", "interval" }) do
            check(case, label .. " " .. field, got[field], want[field])
        end
    end
end

local counts = { en = 0, de = 0 }
for _, case in ipairs(cases) do
    counts[case.lang] = counts[case.lang] + 1
    if case.fin then
        for points = 1, 5 do
            local want = case.fin[points]
            local got = track(case, points)
            check(case, points .. " points parsed", got ~= nil, true)
            if got then
                check(case, points .. " points total", got.total, want[1])
                check(case, points .. " points duration", got.duration, want[2])
                check(case, points .. " points school", got.school, 1)
                check(case, points .. " points interval", got.interval, case.interval)
            end
        end
    else
        checkReading(case, "", track(case), case.expect)
    end
    check(case, "ignored", addon.ignored[case.name] == true, case.ignored)
    check(case, "tick shape", addon.shapes[case.name] ~= nil, case.shaped)
    if case.lang == "de" then
        check(case, "finisher", ns.locale.isFinisher(case.desc), case.finisher)
        check(case, "combo points awarded", ns.locale.comboPointsAwarded(case.desc) or false, case.awarded)
    else
        -- English must read exactly as before, for every combo point count.
        for points = 0, 5 do
            local before = { upstreamParse(case.desc, points > 0 and points or nil) }
            local now = { addon.parseDot(case.desc, points > 0 and points or nil) }
            for i = 1, 4 do
                check(case, "same as v0.5.0 (" .. points .. " points, value " .. i .. ")", now[i], before[i])
            end
        end
    end
end

-- Names the client reports for the spell IDs (here: made-up French ones) join the tables too, and never replace
-- an entry that is already there.
if addon.nameTables then
    local french = { [5570] = "Essaim d'insectes", [980] = "Malédiction d'agonie", [1943] = "Rupture", [10] = "Blizzard" }
    local added = ns.locale.addClientNames(addon.nameTables, function(id) return french[id] end)
    local case = { lang = "en", source = "stub", name = "client names", id = 0 }
    check(case, "Essaim d'insectes interval", addon.intervals["Essaim d'insectes"], 2)
    check(case, "Malédiction d'agonie shape", addon.shapes["Malédiction d'agonie"] ~= nil, true)
    check(case, "names added", #added, 2)
else
    failed, failedByLang.de = failed + 1, failedByLang.de + 1
    print("FAIL  no NAME_TABLES in " .. source)
end

-- German buffs and debuffs whose duration stands before direct damage aren't DoTs (Classic Era deDE, Wowhead;
-- Seal of Fury is Forever's own German text, build 1.60.1.70009). Their English text isn't read either.
for _, case in ipairs({
    { lang = "de", source = "forever-client", name = "Siegel des Furors", id = 20163,
      desc = "Erfüllt den Paladin 30 Sek. lang mit göttlichem Furor, wodurch jeder Nahkampfangriff zusätzlich 14 Heiligschaden verursacht. Während ein Schild ausgerüstet ist, gewährt jeder Angriff außerdem einen Absorptionsschild in Höhe von 50% des verursachten Heiligschadens. Es kann immer nur jeweils ein Siegel auf dem Paladin aktiv sein.\r\n\r\nDie Entfesselung der Energie dieses Siegels fügt einem Gegner 51 bis 57 Heiligschaden zu und verspottet das Ziel, damit es Euch 4 Sek. lang angreift." },
    { lang = "de", source = "wowhead", name = "Donnerknall", id = 11581,
      desc = "Dröhnt in der Nähe befindliche Feinde mit Donner zu, erhöht die Zeit zwischen ihren Angriffen 30 Sek. lang um 10% und fügt ihnen 103 Schaden zu. Wirkt auf maximal 4 Ziele." },
    { lang = "de", source = "wowhead", name = "Heiliger Schild", id = 20928,
      desc = "Erhöht die Blockchance 10 Sek. lang um 30% und verursacht, solange aktiv, mit jedem geblockten Angriff 130 Heiligschaden. Durch 'Heiliger Schild' verursachter Schaden verursacht 20% zusätzliche Bedrohung. Jedes Blocken verbraucht eine Aufladung. 4 Aufladungen." },
}) do
    checkReading(case, "", track(case), nil)
end

-- Forever's German client leaves Lacerate ranks 1-3 in English with the German unit ("Sek."). They read as the
-- English client's text does.
for _, case in ipairs({
    { lang = "de", source = "forever-client", name = "Aufschlitzen", id = 24118,
      desc = "Wounds the target causing them to bleed for 119 damage over 21 Sek..", english = 119 },
    { lang = "de", source = "forever-client", name = "Aufschlitzen", id = 24119,
      desc = "Wounds the target causing them to bleed for 196 damage over 21 Sek..", english = 196 },
    { lang = "de", source = "forever-client", name = "Aufschlitzen", id = 24120,
      desc = "Wounds the target causing them to bleed for 280 damage over 21 Sek..", english = 280 },
}) do
    local english = { name = "Lacerate",
        desc = "Wounds the target causing them to bleed for " .. case.english .. " damage over 21 sec." }
    local want = track(english)
    check(case, "English total", want and want.total, case.english)
    checkReading(case, "", track(case), want)
end

-- Forever's client answers GetLocale() with enUS while its spell text is German: unread German text is still
-- logged (once), unread English text isn't.
do
    local realGetLocale = GetLocale
    GetLocale = function() return "enUS" end
    local case = { lang = "en", source = "forever-client", name = "Seal of Fury", id = 20163 }
    check(case, "English unread not logged", ns.locale.shouldLogUnread(20163, "Fills the Paladin with divine fury for 30 sec, causing melee attacks to deal an additional 14 Holy damage. While a shield is equipped, each attack also grants an absorb shield equal to 50% of the Holy damage dealt.  Only one Seal can be active on the Paladin at any one time.\r\n\r\nUnleashing this Seal's energy causes 51 to 57 Holy damage to an enemy and taunts the target to attack you for 4 sec."), false)
    case = { lang = "de", source = "forever-client", name = "Siegel des Furors", id = 20163 }
    local german = "Erfüllt den Paladin 30 Sek. lang mit göttlichem Furor, wodurch jeder Nahkampfangriff zusätzlich 14 Heiligschaden verursacht. Während ein Schild ausgerüstet ist, gewährt jeder Angriff außerdem einen Absorptionsschild in Höhe von 50% des verursachten Heiligschadens. Es kann immer nur jeweils ein Siegel auf dem Paladin aktiv sein.\r\n\r\nDie Entfesselung der Energie dieses Siegels fügt einem Gegner 51 bis 57 Heiligschaden zu und verspottet das Ziel, damit es Euch 4 Sek. lang angreift."
    check(case, "unread logged under enUS", ns.locale.shouldLogUnread(20163, german), true)
    check(case, "unread logged once", ns.locale.shouldLogUnread(20163, german), false)
    GetLocale = realGetLocale
end

if shown > 40 then print(string.format("... and %d more failures", shown - 40)) end
print(string.format("%d English and %d German descriptions from %s", counts.en, counts.de, source))
print(string.format("%d checks passed, %d failed (English %d, German %d)", passed, failed, failedByLang.en, failedByLang.de))
if TEST_NO_EXIT then return failed end
os.exit(failed == 0 and 0 or 1)
