"""Drive the shipped Retail DoT runtime; these mocks do not verify in-game secrecy/rendering."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fixture = (ROOT / "tests/test_bit.py").read_text(encoding="utf-8")
context = {"__file__": str(ROOT / "tests/test_bit.py")}
exec(compile(fixture.split('print("-- every module on")', 1)[0], "bit_fixture", "exec"), context)


def fight(extra="", without_sdi=False):
    rt = context["LuaRuntime"](unpack_returned_tuples=True)
    rt.execute(context["FAKE"])
    rt.execute("""
        function GetBuildInfo() return '12.1.0', '69933', '', 120100 end
        function GetLocale() return 'enUS' end
        comboMax = 7
        local legacyPowerMax = UnitPowerMax
        function UnitPowerMax(unit, power)
            if unit == 'player' and power == Enum.PowerType.ComboPoints then return comboMax end
            return legacyPowerMax(unit, power)
        end
        GameFontNormalSmall.GetFont = function() return 'Fonts\\\\FRIZQT__.TTF', 12, '' end
        SECRET = {}
        function issecretvalue(v) return rawequal(v, SECRET) end
        mobA = { guid = SECRET, identity = 'A', name = 'Mob A', health = SECRET, max = SECRET }
        mobB = { guid = SECRET, identity = 'B', name = 'Mob B', health = SECRET, max = SECRET }
        units.target, units.nameplate1, units.nameplate2 = mobA, mobA, mobB
        target = { hostile = true }
        function UnitName(unit) return units[unit] and units[unit].name end
        function UnitCanAttack(_, unit) return units[unit] ~= nil and unit ~= 'player' end
        identityUnknown = false
        function UnitIsUnit(a, b)
            if identityUnknown then return SECRET end
            return units[a] ~= nil and units[b] ~= nil and units[a].identity == units[b].identity
        end
        spellNames[172], spellDesc[172] = 'Corruption', 'Causes 1,200 Shadow damage over 12 sec.'
        spellNames[980], spellDesc[980] = 'Agony', 'Causes 600 Shadow damage over 12 sec.'
        plateA, plateB = NewPlate(), NewPlate()
        function C_NamePlate.GetNamePlateForUnit(unit)
            if units[unit] == mobA then return plateA end
            if units[unit] == mobB then return plateB end
        end
    """ + extra)
    addon = rt.eval("{}")
    loader = rt.eval("function(src, name, addon) return assert(loadstring(src, '@' .. name))('UsefulPlatesAndTooltips', addon) end")
    for name in (ROOT / "UsefulPlatesAndTooltips_Mainline.toc").read_text(encoding="utf-8").splitlines():
        if name.strip() and not name.startswith("#"):
            name = name.strip().replace("\\", "/")
            if without_sdi and name.startswith("Modules/SpellDamageInfo/"):
                continue
            loader((ROOT / name).read_text(encoding="utf-8"), name, addon)
    game = rt.globals()
    game.Fire("ADDON_LOADED", "UsefulPlatesAndTooltips")
    game.Fire("PLAYER_ENTERING_WORLD")
    return rt, game, addon.modules["DoTInfo"]


def cast(game, spell=172, name="Mob A", guid="Cast-1"):
    game.Fire("UNIT_SPELLCAST_SENT", "player", name, guid, spell)
    game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, spell)


def total(dot, unit="nameplate1"):
    return dot.dotBreakdownForUnit(unit)[1]


rt, game, dot = fight()
dot.db.waitFirstTick = "always"
cast(game)
assert total(dot) == 1200
game.Advance(3)
game.Tick(0.1)
assert total(dot) == 900
game.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 800000, 32)
game.Fire("UNIT_COMBAT", "nameplate1", "IMMUNE", "", 0, 32)
assert total(dot) == 900 and len(dot.db.ticks) == 0
game.Advance(9)
game.Tick(0.1)
assert total(dot) == 0
print("ok tooltip estimate decays/expires without ticks; unrelated hits/avoids cannot change or teach it")

rt, game, dot = fight()
game.Fire("UNIT_SPELLCAST_SENT", "player", game.SECRET, "Cast-1", 172)
rt.execute("units.target = mobB")
game.Fire("PLAYER_TARGET_CHANGED")
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 172)
assert total(dot) == 1200 and total(dot, "target") == 0
rt.execute("units.target = mobA")
game.Fire("PLAYER_TARGET_CHANGED")
assert total(dot, "target") == 1200
print("ok secret GUID recipient survives switching away and back through the original nameplate")

rt, game, dot = fight("mobA.guid = 'Readable-A'")
cast(game)
rt.execute("mobA.guid = SECRET")
assert total(dot, "target") == total(dot) == 1200
rt.execute("mobA.guid = 'Readable-A'")
assert total(dot, "target") == total(dot) == 1200
print("ok a nameplate key stays stable when the GUID changes secrecy")

for new_guid in ("SECRET", "'Readable-A'"):
    rt, game, dot = fight("units.nameplate1 = nil")
    cast(game, name=game.SECRET)
    assert total(dot, "target") == 1200
    rt.execute("mobA.guid = " + new_guid + "; units.nameplate1 = mobA")
    game.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    assert total(dot, "target") == total(dot) == 1200
print("ok a late nameplate retains the original estimate whether its GUID is readable or secret")

for succeed_before_switch in (True, False):
    rt, game, dot = fight("units.nameplate1 = nil; mobA.guid = 'Readable-A'")
    game.Fire("UNIT_SPELLCAST_SENT", "player", "Mob A", "Cast-1", 172)
    if succeed_before_switch:
        game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 172)
    rt.execute("units.target = mobB")
    game.Fire("PLAYER_TARGET_CHANGED")
    if not succeed_before_switch:
        game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 172)
    assert total(dot, "target") == 0
    rt.execute("units.target = mobA")
    game.Fire("PLAYER_TARGET_CHANGED")
    assert total(dot, "target") == 1200
rt, game, dot = fight("mobA.guid = 'Readable-A'")
game.Fire("UNIT_SPELLCAST_SENT", "player", "Mob A", "Cast-1", 172)
rt.execute("units.nameplate1 = nil")
game.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
rt.execute("units.target, units.nameplate1 = mobB, mobB")
game.Fire("PLAYER_TARGET_CHANGED")
game.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 172)
assert total(dot) == 0
rt.execute("units.target = mobA")
game.Fire("PLAYER_TARGET_CHANGED")
assert total(dot, "target") == 1200
print("ok readable GUID recipients survive selection changes and nameplate removal without contaminating reused plates")

rt, game, dot = fight()
game.Fire("UNIT_SPELLCAST_SENT", "player", game.SECRET, "Cast-1", 172)
rt.execute("units.nameplate1 = nil")
game.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
rt.execute("units.target, units.nameplate1 = mobB, mobB")
game.Fire("PLAYER_TARGET_CHANGED")
game.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 172)
assert total(dot) == total(dot, "target") == 0
print("ok a recycled nameplate cannot inherit a removed mob's pending cast")

rt, game, dot = fight("units.nameplate1 = nil; identityUnknown = true")
game.Fire("UNIT_SPELLCAST_SENT", "player", game.SECRET, "Cast-1", 172)
rt.execute("units.target = mobB")
game.Fire("PLAYER_TARGET_CHANGED")
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 172)
assert total(dot, "target") == 0
print("ok an unreadable identity without a stable plate cannot move a cast onto another target")

rt, game, dot = fight()
rt.execute("units.mouseover = mobB")
cast(game, name="Mob B")
assert total(dot) == 0 and total(dot, "nameplate2") == 1200
rt, game, dot = fight("mobB.name = 'Mob A'; units.mouseover = mobB")
cast(game)
assert total(dot) == total(dot, "nameplate2") == 0
print("ok readable mouseover recipient is respected; two same-name NPC recipients remain untracked")

rt, game, dot = fight("units.focus = mobB")
cast(game, name=game.SECRET)
assert total(dot) == total(dot, "nameplate2") == 0
rt, game, dot = fight("units.mouseover = mobA")
cast(game, name=game.SECRET)
assert total(dot) == 1200
print("ok a hidden SENT name with a different focus/mouseover recipient is safely rejected")

rt, game, dot = fight()
cast(game)
game.Fire("UNIT_SPELLCAST_SENT", "player", game.SECRET, "Cast-2", 980)
game.Fire("PLAYER_ENTERING_WORLD")
assert total(dot) == 0
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 980)
assert total(dot) == 0
cast(game, guid="Cast-3")
assert total(dot) == 1200
print("ok loading clears old estimates and pending recipients; fresh casts work after reseeding")

rt, game, dot = fight()
game.Fire("UNIT_SPELLCAST_SENT", "player", "Mob A", "Cast-1", 172)
game.Fire("UNIT_SPELLCAST_START", "player", "Cast-1", 172)
assert total(dot) == 1200
game.Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-1", 172)
assert total(dot) == 0
cast(game, guid="Cast-2")
assert total(dot) == 1200
game.Advance(3)
cast(game, guid="Cast-3")
assert abs(total(dot) - 1560) < 0.001
game.Advance(12)
entries, remaining = dot.dotBreakdownForUnit("nameplate1")
assert abs(remaining - 360) < 0.001 and entries[1].refreshDue
cast(game, guid="Cast-4")
assert abs(total(dot) - 1560) < 0.001
game.Advance(14)
cast(game, guid="Cast-5")
assert abs(total(dot) - 1360) < 0.001
print("ok interrupted preview is removed; Pandemic carries remaining duration up to 30 percent")

rt, game, dot = fight("""
    playerClass, comboPoints = 'ROGUE', 7
    spellNames[1943] = 'Rupture'
    spellDesc[1943] = 'Finishing move that causes 700 Bleed damage over 14 sec.'
""")
game.Fire("UNIT_SPELLCAST_SENT", "player", "Mob A", "Cast-1", 1943)
rt.execute("comboPoints = 0; spellDesc[1943] = 'Finishing move that causes 100 Bleed damage over 2 sec.'")
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1943)
assert total(dot) == 700
print("ok finisher reads the tooltip before spending its player-owned combo points")

rt, game, dot = fight("""
    playerClass, comboPoints = 'ROGUE', 7
    spellNames[1943] = 'Rupture'
    spellDesc[1943] = 'Finishing move that causes Bleed damage. 1 point: 100 over 4 sec. 7 points: 700 over 28 sec.'
    spellDesc[172] = 'Causes 1,234.5 Shadow damage over 12.5 sec.'
""")
cast(game, spell=1943)
assert total(dot) == 700
cast(game, guid="Cast-2")
assert abs(total(dot) - 1934.5) < 0.001
print("ok Retail per-point finisher lines and decimal damage are read without losing their leading digits")

rt, game, dot = fight("""
    function GetLocale() return 'deDE' end
    spellDesc[172] = 'Verursacht 12 Sek. lang 1.200 Schattenschaden.'
    spellNames[5740], spellDesc[5740] = 'Rain of Fire', 'Causes 9999 Fire damage over 8 sec.'
""")
cast(game)
assert total(dot) == 1200
cast(game, spell=5740, guid="Cast-2")
assert total(dot) == 1200
game.Fire("UNIT_SPELLCAST_SENT", "player", game.SECRET, game.SECRET, game.SECRET)
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", game.SECRET, game.SECRET)
assert total(dot) == 1200
print("ok German grouped numbers, unsupported ground effects and secret spell IDs fail safely")

# Actual rogue tooltip forms, including Retail decimal values, work without loading SpellDamageInfo.
rogue_descriptions = (
    ("enUS", 703, "Garrote the enemy, causing 1,200.5 Bleed damage over 18.5 sec. Awards 1 combo point.", 1200.5, 18.5),
    ("enUS", 1943, "Finishing move that causes 700.5 Bleed damage over 28.5 sec. Lasts longer per combo point.", 700.5, 28.5),
    ("deDE", 703, "Erdrosselt den Gegner und fügt ihm im Verlauf von 18 Sek. 1.200 Blutungsschaden zu. Gewährt 1 Combopunkt.", 1200, 18),
    ("deDE", 703, "Erdrosselt den Gegner und fügt ihm im Verlauf von 18,5 Sek. 1.200,5 Blutungsschaden zu. Gewährt 1 Combopunkt.", 1200.5, 18.5),
    ("deDE", 703, "Fügt ihm 1.200,5 Blutungsschaden im Verlauf von 18,5 Sek. zu.", 1200.5, 18.5),
    ("deDE", 1943, "Finishing-Move, der dem Ziel im Verlauf von 28,5 Sek. 700,5 Blutungsschaden zufügt.", 700.5, 28.5),
)
for locale, spell, description, damage, duration in rogue_descriptions:
    rt, game, dot = fight("playerClass, comboPoints = 'ROGUE', 7", without_sdi=True)
    game.GetLocale = rt.eval("function() return '" + locale + "' end")
    game.spellNames[spell], game.spellDesc[spell] = "Garrote" if spell == 703 else "Rupture", description
    game.Fire("UNIT_SPELLCAST_SENT", "player", "Mob A", "Cast-1", spell)
    rt.execute("comboPoints = 0")
    game.spellDesc[spell] = "Unreadable after spending combo points"
    game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", spell)
    assert abs(total(dot) - damage) < 0.001, (locale, spell, description, total(dot))
    game.Advance(duration / 2)
    game.Tick(0.1)
    assert abs(total(dot) - damage / 2) < 0.001, (locale, spell, total(dot))
print("ok EN/DE Garrote and current-total Rupture preserve decimal amounts/durations and the SENT snapshot without SDI")

finisher_rows = (
    ("enUS", "Finishing move. 1 point: 100 over 4 sec. 6 points: 600.5 Bleed damage over 24.5 sec. 7 points: 700.5 over 28.5 sec."),
    ("deDE", "Finishing-Move. 1 Punkt: 100 über 4 Sek. 6 Punkte: 600,5 Blutungsschaden über 24,5 Sek. 7 Punkte: 700,5 im Verlauf von 28,5 Sek."),
    ("deDE", "Finishing-Move. 1 Punkt: 100 Schaden über 4 Sek. 6 Punkte: 600 Schaden im Verlauf von 24 Sek. 7 Punkte: 700 Schaden über 28 Sek."),
)
for locale, description in finisher_rows:
    for points in (6, 7):
        rt, game, dot = fight("playerClass, comboPoints = 'ROGUE', " + str(points), without_sdi=True)
        game.GetLocale = rt.eval("function() return '" + locale + "' end")
        game.spellNames[1943], game.spellDesc[1943] = "Rupture", description
        cast(game, spell=1943)
        decimal = ",5" in description or ".5" in description
        expected = points * 100 + (0.5 if decimal else 0)
        assert abs(total(dot) - expected) < 0.001, (locale, points, total(dot))
print("ok exact 6/7 CP EN/DE rows are selected, including known-valid integer German rows")

for locale, description in (
    ("enUS", "Finishing move. 1 point: 100 damage over 4 sec. 7 points: 700 damage over 28 sec."),
    ("deDE", "Finishing-Move. 1 Punkt: 100 Schaden über 4 Sek. 7 Punkte: 700 Schaden über 28 Sek."),
    ("enUS", "Finishing move. 1 point: 100 damage over 4 sec. 5 points: 500 damage over 20 sec."),
):
    rt, game, dot = fight("playerClass, comboPoints = 'ROGUE', " + ("7" if "5 points" in description else "6"))
    game.GetLocale = rt.eval("function() return '" + locale + "' end")
    game.spellNames[1943], game.spellDesc[1943] = "Rupture", description
    cast(game, spell=1943)
    assert total(dot) == 0
print("ok absent intermediate/high CP rows are rejected rather than clamped or read as the final generic damage clause")

for points, maximum in (
    ("SECRET", "7"), ("0", "7"), ("6.5", "7"), ("math.huge", "7"), ("0/0", "7"),
    ("7", "5"), ("7", "SECRET"), ("7", "0"), ("7", "6.5"), ("7", "math.huge"), ("7", "0/0"),
):
    rt, game, dot = fight("""
        playerClass, comboPoints = 'ROGUE', 7
        spellNames[1943] = 'Rupture'
        spellDesc[1943] = 'Finishing move. 1 point: 100 damage over 4 sec. 7 points: 700 damage over 28 sec.'
    """)
    game.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")  # An earlier valid reading must not rescue an unknown SENT.
    rt.execute("comboPoints, comboMax = " + points + ", " + maximum)
    cast(game, spell=1943)
    assert total(dot) == 0, (points, maximum, total(dot))
    rt.execute("comboPoints, comboMax = 7, 7")
    cast(game, spell=1943, guid="Cast-2")
    assert total(dot) == 700
print("ok unknown/zero/fractional/nonfinite CP and unreadable/invalid dynamic caps cannot reuse stale rows; fresh valid CP recovers")

for getter in ("UnitPower", "UnitPowerMax"):
    rt, game, dot = fight("""
        playerClass, comboPoints, comboMax = 'ROGUE', 6, 6
        spellNames[1943] = 'Rupture'
        spellDesc[1943] = '1 point: 100 damage over 4 sec. 6 points: 600 damage over 24 sec.'
    """)
    rt.execute("""
        savedGetter = """ + getter + """
        """ + getter + """ = function(unit, power)
            if power == Enum.PowerType.ComboPoints then error('power unavailable') end
            return savedGetter(unit, power)
        end
    """)
    cast(game, spell=1943)
    assert total(dot) == 0
    rt.execute(getter + " = savedGetter")
    game.Fire("UNIT_SPELLCAST_SENT", "player", "Mob A", "Cast-2", 1943)
    game.Fire("UNIT_SPELLCAST_START", "player", "Cast-2", 1943)
    assert total(dot) == 0  # Spell metadata identifies a finisher even without the English prefix.
    game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 1943)
    assert total(dot) == 600
print("ok throwing power getters recover at the actual six-point cap; metadata keeps a finisher out of casting previews")

rt, game, dot = fight("""
    playerClass, comboPoints = 'ROGUE', 7
    spellNames[703], spellDesc[703] = 'Garrote', 'Causes 100 Bleed damage over 18 sec.'
    spellNames[999703], spellDesc[999703] = 'Garrote', 'Causes 1,200 Bleed damage over 18 sec.'
    activeOverride = 999703
    C_Spell.GetOverrideSpell = function(id) return id == 703 and activeOverride or id end
    C_Spell.GetBaseSpell = function(id) return id == 999703 and 703 or id end
""")
game.Fire("UNIT_SPELLCAST_SENT", "player", "Mob A", "Cast-1", 703)
rt.execute("activeOverride = 703")
game.Fire("UNIT_SPELLCAST_START", "player", "Cast-1", 703)
assert total(dot) == 1200
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 703)
assert total(dot) == 1200
rt, game, dot = fight("""
    spellNames[999703], spellDesc[999703] = 'Garrote', 'Causes 1,200 Bleed damage over 18 sec.'
    C_Spell.GetBaseSpell = function(id) return id == 999703 and 703 or id end
""")
cast(game, spell=999703)
assert total(dot) == 1200
print("ok active override description survives START/SUCCEEDED changes and an override event ID maps to its supported base")

for failure in ("return SECRET", "error('not readable')"):
    rt, game, dot = fight("""
        spellNames[703], spellDesc[703] = 'Garrote', 'Causes 100 Bleed damage over 18 sec.'
        spellNames[999703], spellDesc[999703] = 'Garrote', 'Causes 1,200 Bleed damage over 18 sec.'
    """)
    rt.execute("C_Spell.GetOverrideSpell = function() " + failure + " end")
    cast(game, spell=703)
    assert total(dot) == 0
    rt.execute("C_Spell.GetOverrideSpell = function(id) return id == 703 and 999703 or id end")
    cast(game, spell=703, guid="Cast-2")
    assert total(dot) == 1200
    game.spellNames[2823], game.spellDesc[2823] = "Deadly Poison", "Coats a weapon. Causes 99 Nature damage over 12 sec."
    cast(game, spell=2823, guid="Cast-3")
    assert total(dot) == 1200
print("ok protected/throwing override getters recover safely; applying a poison weapon buff does not create a target DoT")

for failure in ("return SECRET", "error('base unavailable')"):
    rt, game, dot = fight("spellNames[999703], spellDesc[999703] = 'Garrote', 'Causes 1,200 Bleed damage over 18 sec.'")
    rt.execute("C_Spell.GetBaseSpell = function() " + failure + " end")
    cast(game, spell=999703)
    assert total(dot) == 0
    rt.execute("C_Spell.GetBaseSpell = function(id) return id == 999703 and 703 or id end")
    cast(game, spell=999703, guid="Cast-2")
    assert total(dot) == 1200
print("ok protected/throwing base-spell lookups reject unknown event IDs and recover on the next cast")
