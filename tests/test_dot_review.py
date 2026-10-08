"""Shipped DoT settings and refresh cues: python tests/test_dot_review.py."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fixture = (ROOT / "tests/test_bit.py").read_text(encoding="utf-8")
namespace = {"__file__": str(ROOT / "tests/test_bit.py")}
exec(compile(fixture.split('print("-- every module on")', 1)[0], "fixture", "exec"), namespace)
load = namespace["load"]


def below(rt, frame, ancestor):
    while frame is not None:
        if rt.globals().Same(frame, ancestor):
            return True
        frame = frame.parent
    return False


def labels(rt, game, parent, text):
    return [frame for frame in game.AllFrames.values()
            if frame.text == text and below(rt, frame, parent)]


def click(frame):
    frame.scripts.OnClick(frame)


rt, game, addon, _ = load()
game.Fire("ADDON_LOADED", "UsefulPlatesAndTooltips")
game.Fire("PLAYER_LOGIN")
tab, dot = addon.tabs["DoTInfo"], addon.modules["DoTInfo"]

# OFF appearance uses an actual filled StatusBar rather than an invisible plain Frame.
scene = tab.buildPreview(game.UIParent)
assert scene.bar.kind == "StatusBar"
tab.previewRender(scene, addon.Style.Resolve("DoTInfo", tab.legacy))
assert scene.bar.GetHeight(scene.bar) >= 20

# A recreated content panel anchors its first tab locally and retires the old event listener.
first = game.CreateFrame("Frame", None, game.UIParent)
first.Hide(first)
tab.build(first)
first.Show(first)
second = game.CreateFrame("Frame", None, game.UIParent)
second.Hide(second)
tab.build(second)
second.Show(second)
kill = labels(rt, game, second, "Kill icon")[0].parent
assert kill.points[1][1] == "TOPLEFT", "recreated first tab was anchored after an old tab"
assert not first.shown and len(first.events) == 0
assert first.scripts.OnShow is None and first.scripts.OnHide is None and first.scripts.OnEvent is None
before = len(game.AllFrames)
tab.build(second)
assert len(game.AllFrames) == before, "building the same parent should reuse its controls"
assert labels(rt, game, second, "Show refresh marks")

# Make the sample lethal, then pick a different kill icon through the real dropdown.
damage_row = labels(rt, game, second, "DoT damage")[0].parent
damage = next(frame for frame in damage_row.children.values() if frame.kind == "Slider")
damage.scripts.OnValueChanged(damage, 80)
badge = second.statusBadge
old_icon = badge.icon.texture
icon_row = labels(rt, game, second, "Icon")[0].parent
icon_button = next(frame for frame in icon_row.children.values() if frame.kind == "Button")
click(icon_button)
chosen = next(entry for entry in dot.lists.icons.values() if entry.id != dot.db.skullIcon)
option = labels(rt, game, game.UIParent, chosen.label)[-1].parent
click(option)
assert dot.db.skullIcon == chosen.id and badge.icon.texture == chosen.path
assert badge.icon.texture != old_icon, "lethal badge kept its previous icon"

# Client aliases and refresh state use actual runtime casts and ticks, without an options sample.
rt, game, addon, _ = load()
rt.execute("""
    GameFontNormalSmall.GetFont = function() return 'Fonts\\\\FRIZQT__.TTF', 12, '' end
    spellNames[172] = 'Client Corruption'
    spellNames[589] = 'Client Pain'
    spellNames[980] = 'Client Agony'
    spellDesc[172] = 'Corrupts the target, causing 400 Shadow damage over 12 sec.'
    target = { hostile = true }
    units.target = { guid = 'Mob-A', health = 500, max = 500 }
    units.nameplate1 = units.target
    plate = NewPlate()
""")
game.Fire("ADDON_LOADED", "UsefulPlatesAndTooltips")
game.Fire("PLAYER_LOGIN")
dot = addon.modules["DoTInfo"]
assert all(dot.refreshNames[name] for name in ("Client Corruption", "Client Pain", "Client Agony"))
game.Fire("UNIT_SPELLCAST_SENT", "player", "Mob-A", "Cast-1", 172)
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 172)
entries, damage = dot.dotBreakdownForUnit("target")
assert damage == 400 and not entries[1].refreshDue
for _ in range(3):
    game.Advance(3)
    game.Fire("UNIT_COMBAT", "target", "WOUND", "", 100, 32)
entries, damage = dot.dotBreakdownForUnit("target")
assert damage == 100 and entries[1].refreshDue
game.Tick(0.2)
assert not any("ERROR" in str(line) for line in dot.db.log.values()), list(dot.db.log.values())

def cues(parent):
    return [frame for frame in game.AllFrames.values()
            if frame.kind == "CreateTexture" and frame.width == 3 and below(rt, frame, parent)]

assert any(mark.shown for mark in cues(game.UsefulPlatesAndTooltips_DoTInfoRemaining))
assert any(mark.shown for mark in cues(game.plate))
dot.db.refreshCue = False
assert not dot.dotBreakdownForUnit("target")[0][1].refreshDue
dot.refresh()
game.Tick(0.2)
assert not any(mark.shown for mark in cues(game.UsefulPlatesAndTooltips_DoTInfoRemaining))
assert not any(mark.shown for mark in cues(game.plate))
rt.execute("""
    SECRET = {}
    function issecretvalue(value) return value == SECRET end
    units.target.health = SECRET
    units.target.max = SECRET
    plate.UnitFrame.healthBar.GetFrameLevel = function() return SECRET end
    plate.UnitFrame.healthBar.GetFrameStrata = function() return SECRET end
""")
dot.refresh()
game.Tick(0.2)
assert not any("ERROR" in str(line) for line in dot.db.log.values()), list(dot.db.log.values())
print("ok DoT off sample, recreated settings, live verdict icon, client aliases and refresh window")
