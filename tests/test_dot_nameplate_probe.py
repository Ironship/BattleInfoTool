"""The nameplate probe records raw geometry/settings without touching the marker."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fixture = ROOT / "tests/test_bit.py"
context = {"__file__": str(fixture)}
exec(compile(fixture.read_text(encoding="utf-8").split(
    'print("-- every module on")', 1)[0], str(fixture), "exec"), context)
rt = context["LuaRuntime"](unpack_returned_tuples=True)
rt.execute(context["FAKE"] + r'''
    function GetBuildInfo() return '12.1.0', '69933', '', 120100 end
    function IsInInstance() return false, 'none' end
    function methods.GetRect(self) return 10, 20, 300, 40 end
    function methods.GetEffectiveScale() return 0.7 end
    function methods.GetScale() return 1 end
    function methods.IsIgnoringParentScale() return false end
    C_AddOns.GetAddOnMetadata = function(_, key) assert(key == 'Version'); return 'probe-test' end
    C_CVar = { GetCVar = function(name) return name == 'nameplateSize' and '5' or '1' end }
    target = { hostile = true }
    units.target = { guid = 'Creature-Probe', name = 'Dummy', health = 800, max = 1000 }
    units.nameplate1 = units.target
    function UnitName(unit) return units[unit] and units[unit].name end
    function UnitIsUnit(a, b) return units[a] ~= nil and rawequal(units[a], units[b]) end
    function UnitCanAttack(_, unit) return units[unit] == units.target end
    plate = NewPlate()
    bar = plate.UnitFrame.healthBar
    bar.selectedBorder = FakeMock('selectedBorder', bar)
    bar.selectedBorder.GetRect = function() return 9, 19, 302, 42 end
    spellNames[172] = 'Corruption'
    spellDesc[172] = 'Deals 400 Shadow damage over 12 sec.'
    GameFontNormalSmall.GetFont = function() return 'Fonts\\FRIZQT__.TTF', 12, '' end
''')
addon = rt.eval("{}")
loader = rt.eval("function(src, name, addon) return assert(loadstring(src, '@' .. name))"
                 "('UsefulPlatesAndTooltips', addon) end")
for name in (ROOT / "UsefulPlatesAndTooltips_Mainline.toc").read_text(encoding="utf-8").splitlines():
    if name.strip() and not name.startswith("#"):
        name = name.strip().replace("\\", "/")
        loader((ROOT / name).read_text(encoding="utf-8"), name, addon)
game = rt.globals()
game.Fire("ADDON_LOADED", "UsefulPlatesAndTooltips")
game.Fire("PLAYER_ENTERING_WORLD")
dot = addon.modules.DoTInfo
dot.db.nameplateMode = "marker"
dot.db.waitFirstTick = "never"
game.Fire("UNIT_SPELLCAST_SENT", "player", "Dummy", "Probe-Cast", 172)
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Probe-Cast", 172)
game.Tick(0.2)
marker = next(frame for frame in game.AllFrames.values()
              if frame.kind == "StatusBar"
              and sum(child.kind == "StatusBar" for child in frame.children.values()) == 8)
anchors = marker.points
size = marker.GetWidth(marker), marker.GetHeight(marker)


def probe():
    dot.probeNameplates()
    assert game.Same(marker.points, anchors)
    assert (marker.GetWidth(marker), marker.GetHeight(marker)) == size
    return "\n".join(str(line) for line in dot.db.log.values())


log = probe()
assert "geometryProbe=2 version=probe-test" in log
assert "nameplateSize=5" in log
assert "barRect=rect(10,20,300,40) scale=0.7 local=1 ignoreParent=false" in log
assert "selectedBorderRect=rect(9,19,302,42)" in log
for name in ("markerRect", "spanRect", "segmentBarRect", "segmentEndRect", "segmentTextureRect"):
    assert name + "=rect(10,20,300,40)" in log, name

# Any of the four coordinates may be hidden, including bottom/height. Never stringify it.
rt.execute("""
    SECRET = setmetatable({}, { __tostring = function() error('secret conversion') end })
    function issecretvalue(value) return rawequal(value, SECRET) end
""")
for index in range(1, 5):
    values = ["10", "20", "300", "40"]
    values[index - 1] = "SECRET"
    rt.execute("bar.GetRect = function() return " + ", ".join(values) + " end")
    log = probe()
    assert "barRect=rect(" + ",".join("secret" if x == "SECRET" else x for x in values) + ")" in log
rt.execute("bar.GetRect = function() error('rect unavailable') end")
assert "barRect=rect(error: " in probe()
rt.execute("bar.GetRect = false; C_CVar.GetCVar = false; GetCVar = false")
log = probe()
assert "barRect=rect(missing)" in log and "nameplateSize=missing" in log
assert not any("ERROR in nameplate" in str(line) for line in dot.db.log.values())
print("ok nameplate probe records geometry/settings and tolerates hidden or unavailable readings")
