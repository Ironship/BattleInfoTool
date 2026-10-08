"""DoTInfo recipients and outcomes through the shipped addon, including action targeting.

    python tests/test_dot_targets.py

Reuse test_bit.py's fake client and loader without running its scenarios. The actual Lua module
handles every event; this checks tracking decisions, not live-game API secrecy or visual layout.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
source = (ROOT / "tests/test_bit.py").read_text(encoding="utf-8")
namespace = {"__file__": str(ROOT / "tests/test_bit.py")}
exec(compile(source.split('print("-- every module on")', 1)[0], "test_bit_fixture", "exec"), namespace)
load = namespace["load"]


def fight(hard=True, soft=False):
    rt, game, addon, _ = load()
    rt.execute("""
        GameFontNormalSmall.GetFont = function() return 'Fonts\\\\FRIZQT__.TTF', 12, '' end
        SECRET = {}
        function issecretvalue(v) return v == SECRET end
        spellNames[172] = 'Corruption'
        spellDesc[172] = 'Corrupts the target, causing 400 Shadow damage over 12 sec.'
        mobA = { guid = 'Mob-A', identity = 'A', health = 500, max = 500 }
        mobB = { guid = 'Mob-B', identity = 'B', health = 500, max = 500 }
        function UnitIsUnit(a, b)
            local first, second = units[a], units[b]
            return first ~= nil and second ~= nil and first.identity ~= nil
                and first.identity == second.identity
        end
        units.nameplate1 = mobA
        units.nameplate2 = mobB
        plate = NewPlate()
    """)
    if hard:
        rt.execute("target = { hostile = true }; units.target = mobA")
    if soft:
        rt.execute("units.softenemy = " + ("mobB" if hard else "mobA"))
    game.Fire("ADDON_LOADED", "BattleInfoTool")
    game.Fire("PLAYER_LOGIN")
    return rt, game, addon.modules["DoTInfo"]


def send(game):
    game.Fire("UNIT_SPELLCAST_SENT", "player", "Mob-A", "Cast-1", 172)


def succeed(game):
    game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 172)


def total(module, unit="nameplate1"):
    return module.dotBreakdownForUnit(unit)[1]


# Hard targets retain precedence even when action targeting points at another mob.
rt, game, dot = fight(hard=True, soft=True)
send(game)
succeed(game)
assert total(dot, "target") == 400
assert total(dot, "softenemy") == 0
game.Advance(3)
game.Fire("UNIT_COMBAT", "target", "WOUND", "", 100, 32)
assert total(dot) == 300
print("ok hard-target cast and tick; hard target takes precedence")

# A soft-only cast is tracked under the mob's GUID, so nameplates and a later hard target share it.
rt, game, dot = fight(hard=False, soft=True)
send(game)
succeed(game)
assert total(dot, "softenemy") == total(dot) == 400
game.Advance(3)
game.Fire("UNIT_COMBAT", "softenemy", "WOUND", "", 100, 32)
assert total(dot) == 300
game.Advance(3)
game.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 100, 32)
assert total(dot) == 200
rt.execute("target = { hostile = true }; units.target = mobA")
game.Fire("PLAYER_TARGET_CHANGED")
assert total(dot, "target") == 200
print("ok soft-only cast, soft/nameplate ticks, then clicking the same mob")

# START and SUCCEEDED retain SENT's recipient if action targeting moves during the cast.
rt, game, dot = fight(hard=False, soft=True)
send(game)
rt.execute("units.softenemy = mobB")
game.Fire("UNIT_SPELLCAST_START", "player", "Cast-1", 172)
entries, damage = dot.dotBreakdownForUnit("nameplate1")
assert damage == 400 and entries[1].provisional
assert total(dot, "softenemy") == 0
succeed(game)
entries, damage = dot.dotBreakdownForUnit("nameplate1")
assert damage == 400 and not entries[1].provisional
assert total(dot, "softenemy") == 0
print("ok soft-target cast estimate and success keep the original recipient")

# Clients missing SENT still track the current readable soft target at success.
rt, game, dot = fight(hard=False, soft=True)
succeed(game)
assert total(dot) == 400
print("ok soft-target success without SENT")

# Waiting for a tick works with action targeting, including a duplicated nameplate event.
rt, game, dot = fight(hard=False, soft=True)
dot.db.waitFirstTick = "always"
send(game)
succeed(game)
assert total(dot) == 0
game.Advance(3)
game.Fire("UNIT_COMBAT", "softenemy", "WOUND", "", 100, 32)
game.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 100, 32)
assert total(dot) == 300
print("ok first-tick waiting and adjacent cross-token duplicate")

# Avoids before and after success on the actual soft recipient reject the cast.
for before_success in (True, False):
    rt, game, dot = fight(hard=False, soft=True)
    send(game)
    if not before_success:
        succeed(game)
    game.Advance(0.1)
    game.Fire("UNIT_COMBAT", "softenemy", "RESIST", "", 0, 32)
    if before_success:
        succeed(game)
    assert total(dot) == 0
print("ok soft-recipient avoid before and after cast success")

# Other units' hits must not replace a recipient's avoid that arrived before success.
for hard in (False, True):
    for other_unit in ("player", "nameplate2"):
        rt, game, dot = fight(hard=hard, soft=not hard)
        send(game)
        game.Advance(0.1)
        game.Fire("UNIT_COMBAT", "target" if hard else "softenemy", "RESIST", "", 0, 32)
        game.Fire("UNIT_COMBAT", other_unit, "WOUND", "", 100, 32)
        succeed(game)
        assert total(dot) == 0
print("ok player/other-nameplate hits cannot overwrite the recipient's pre-success avoid")

# A subsequent hit on that same recipient still resolves its pending result as before.
rt, game, dot = fight(hard=False, soft=True)
send(game)
game.Advance(0.1)
game.Fire("UNIT_COMBAT", "softenemy", "RESIST", "", 0, 32)
game.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 19, 1)
succeed(game)
assert total(dot) == 400
print("ok matching-recipient hit replaces its previous avoid")

# Switching the hard target during the cast must neither move nor erase its DoT.
for before_success in (True, False):
    rt, game, dot = fight()
    send(game)
    rt.execute("units.target = mobB")
    game.Fire("PLAYER_TARGET_CHANGED")
    if not before_success:
        succeed(game)
    game.Advance(0.1)
    game.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
    if before_success:
        succeed(game)
    assert total(dot) == 400
    assert total(dot, "target") == 0
print("ok avoid on unrelated current target cannot reject the original cast")

# Hits on B must not consume A's pending outcome; A's nameplate can report the actual avoid.
rt, game, dot = fight()
send(game)
rt.execute("units.target = mobB")
game.Fire("PLAYER_TARGET_CHANGED")
succeed(game)
game.Advance(0.1)
game.Fire("UNIT_COMBAT", "target", "WOUND", "", 100, 32)
assert total(dot) == 400
game.Fire("UNIT_COMBAT", "nameplate1", "RESIST", "", 0, 32)
assert total(dot) == 0
print("ok unrelated hit leaves the actual recipient's pending avoid intact")

# A rejected refresh keeps the earlier DoT rather than removing it.
rt, game, dot = fight(hard=False, soft=True)
send(game)
succeed(game)
game.Advance(3)
game.Fire("UNIT_COMBAT", "softenemy", "WOUND", "", 100, 32)
send(game)
succeed(game)
game.Advance(0.1)
game.Fire("UNIT_COMBAT", "nameplate1", "RESIST", "", 0, 32)
assert total(dot) == 300
print("ok avoided soft-target refresh preserves the earlier DoT")

# A secret soft GUID can use a real nameplate GUID when the game's identity answer is readable.
rt, game, dot = fight(hard=False, soft=True)
rt.execute("units.softenemy = { guid = SECRET, identity = 'A', health = 500, max = 500 }")
send(game)
succeed(game)
assert total(dot, "softenemy") == total(dot) == 400
game.Advance(3)
game.Fire("UNIT_COMBAT", "softenemy", "WOUND", "", 100, 32)
assert total(dot) == 300
rt.execute("target = { hostile = true }; units.target = mobA")
game.Fire("PLAYER_TARGET_CHANGED")
assert total(dot, "target") == 300
print("ok secret soft GUID uses a readable matching nameplate for casts, ticks and later clicking")

# A discovered GUID is stable even if the secret soft token moves before cast success.
rt, game, dot = fight(hard=False, soft=True)
rt.execute("units.softenemy = { guid = SECRET, identity = 'A', health = 500, max = 500 }")
send(game)
rt.execute("units.softenemy = { guid = SECRET, identity = 'B', health = 500, max = 500 }")
game.Fire("UNIT_SPELLCAST_START", "player", "Cast-1", 172)
succeed(game)
assert total(dot) == 400
assert total(dot, "softenemy") == 0
game.Advance(3)
game.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 100, 32)
assert total(dot) == 300
print("ok secret soft-target switch preserves the original mob's actual GUID")

# Secret or unavailable identity answers cannot justify associating a secret token with a plate.
for unavailable in (False, True):
    rt, game, dot = fight(hard=False, soft=True)
    rt.execute("units.softenemy = { guid = SECRET, identity = 'A', health = 500, max = 500 }")
    rt.execute("UnitIsUnit = nil" if unavailable else "UnitIsUnit = function() return SECRET end")
    send(game)
    succeed(game)
    assert total(dot) == 0
    assert not any("ERROR" in str(line) for line in dot.db.log.values())
print("ok unavailable/secret UnitIsUnit answers cannot create a GUID alias")

# No GUID aliases are invented for secret soft targets; absent targets remain untracked too.
for secret in (False, True):
    rt, game, dot = fight(hard=False, soft=secret)
    if secret:
        rt.execute("mobA.guid = SECRET")
    send(game)
    succeed(game)
    assert total(dot) == 0
    assert any("no target, not tracked" in str(line) for line in dot.db.log.values())
    assert not any("ERROR" in str(line) for line in dot.db.log.values())
print("ok missing and secret soft GUIDs remain safely untracked")

# A target appearing after SENT cannot identify the original, unknown recipient.
for secret_at_send in (False, True):
    rt, game, dot = fight(hard=False, soft=secret_at_send)
    if secret_at_send:
        rt.execute("mobA.guid = SECRET; UnitIsUnit = nil")
    send(game)
    rt.execute("units.softenemy = mobB")
    game.Fire("UNIT_SPELLCAST_START", "player", "Cast-1", 172)
    assert total(dot, "nameplate2") == 0
    succeed(game)
    assert total(dot, "nameplate2") == 0
print("ok unknown SENT recipient stays untracked when another soft target appears")

# A current-target-only secret alias cannot be carried across a hard-target change.
rt, game, dot = fight()
rt.execute("mobA.guid = SECRET; mobB.guid = SECRET")
send(game)
rt.execute("units.target = mobB")
game.Fire("PLAYER_TARGET_CHANGED")
succeed(game)
assert total(dot, "target") == 0
print("ok secret hard-target switch cannot move the original cast onto the new mob")

# Cancelled casts discard SENT even with cast-time estimates disabled or without START.
for ended in ("UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_STOP"):
    rt, game, dot = fight(hard=False, soft=True)
    dot.db.estimateDuringCast = False
    send(game)
    game.Fire(ended, "player", "Cast-1", 172)
    if ended == "UNIT_SPELLCAST_STOP":
        game.Advance(0.6)
        game.Tick(0.1)
    rt.execute("units.softenemy = mobB")
    game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", None, 172)
    assert total(dot) == 0 and total(dot, "nameplate2") == 400
print("ok failed/interrupted/stopped casts release their old recipient without needing START")

# A different cast's success never consumes the original SENT recipient.
rt, game, dot = fight(hard=False, soft=True)
send(game)
rt.execute("units.softenemy = mobB")
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 172)
assert total(dot) == 0 and total(dot, "nameplate2") == 400
succeed(game)
assert total(dot) == total(dot, "nameplate2") == 400
print("ok unrelated cast GUID cannot inherit or consume the original SENT recipient")

# STOP just before SUCCEEDED keeps the recipient until success, even after the soft token moves.
rt, game, dot = fight(hard=False, soft=True)
send(game)
game.Fire("UNIT_SPELLCAST_STOP", "player", "Cast-1", 172)
rt.execute("units.softenemy = mobB")
succeed(game)
assert total(dot) == 400 and total(dot, "nameplate2") == 0
print("ok success during STOP grace retains the original recipient")

# An expired SENT or a consumed non-DoT cast cannot poison a later missing-SENT fallback.
for non_dot in (False, True):
    rt, game, dot = fight(hard=False, soft=True)
    if non_dot:
        rt.execute("spellNames[686] = 'Shadow Bolt'; spellDesc[686] = 'Deals 100 Shadow damage.'")
        game.Fire("UNIT_SPELLCAST_SENT", "player", "Mob-A", "Cast-1", 686)
        game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 686)
    else:
        send(game)
        game.Advance(16)
        game.Tick(0.1)
    rt.execute("units.softenemy = mobB")
    game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", None, 172)
    assert total(dot) == 0 and total(dot, "nameplate2") == 400
print("ok expired SENT and completed non-DoT casts cannot leave a stale recipient")

# B's tick between A's token copies must not let A's single hit feed its second same-school DoT.
rt, game, dot = fight()
rt.execute("spellNames[18265] = 'Siphon Life'; spellDesc[18265] = 'Causes 400 Shadow damage over 12 sec.'")
send(game)
succeed(game)
game.Fire("UNIT_SPELLCAST_SENT", "player", "Mob-A", "Cast-2", 18265)
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 18265)
rt.execute("units.target = mobB; units.softenemy = mobA")
game.Fire("PLAYER_TARGET_CHANGED")
game.Fire("UNIT_SPELLCAST_SENT", "player", "Mob-B", "Cast-3", 172)
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 172)
game.Advance(3)
game.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 100, 32)
assert total(dot) == 700
game.Fire("UNIT_COMBAT", "target", "WOUND", "", 100, 32)
game.Fire("UNIT_COMBAT", "softenemy", "WOUND", "", 100, 32)
assert total(dot) == 700
game.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 100, 32)
assert total(dot) == 600  # Another genuine tick from the original token can feed the other DoT.
print("ok interleaved cross-token duplicates stay rejected while identical real ticks both count")
