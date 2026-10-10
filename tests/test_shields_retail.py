"""Exercise shipped ShieldsInfo with Retail frames; native secrecy/rendering still needs game testing."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fixture = ROOT / "tests/test_shieldsinfo.py"
context = {"__file__": str(fixture)}
exec(compile(fixture.read_text(encoding="utf-8").split(
    'print("-- registration and the on/off switch")', 1)[0], str(fixture), "exec"), context)

RETAIL = """
function GetBuildInfo() return '12.1.0', '69933', '', 120100 end
function GetLocale() return 'enUS' end
local function forbidden() error('secret value was interpreted') end
local hidden = { __add = forbidden, __sub = forbidden, __mul = forbidden,
    __div = forbidden, __lt = forbidden, __le = forbidden, __tostring = forbidden }
SECRET_ABSORB, SECRET_MAX = setmetatable({}, hidden), setmetatable({}, hidden)
SECRET_UNIT = 'secret-displayed-unit'
function issecretvalue(v)
    return rawequal(v, SECRET_ABSORB) or rawequal(v, SECRET_MAX) or rawequal(v, SECRET_UNIT)
end
PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer = {
    HealthBar = FakeMock('retailPlayerBar', PlayerFrame)
}
party = NewCompact('party1')
party.healthBar = nil
party.HealthBarContainer = { HealthBar = FakeMock('retailPartyBar', party) }
PartyFrame.PartyMemberFramePool.activeObjects = { [party] = true }
for i = 1, 4 do _G['PartyMemberFrame' .. i] = nil end
np = NewPlate()
np.UnitFrame.unit = 'nameplate1'
np.UnitFrame.healthBar = nil
np.UnitFrame.HealthBarsContainer = { healthBar = FakeMock('retailPlateBar', np) }
plates = { np }
units.player = { absorb = SECRET_ABSORB, max = SECRET_MAX }
units.target = { absorb = SECRET_ABSORB, max = SECRET_MAX, guid = 'Mob-A', name = 'Mob A' }
units.party1 = { absorb = SECRET_ABSORB, max = SECRET_MAX }
units.nameplate1 = units.target
target = { hostile = true }
plate = np
"""


def boot(extra="", with_dot=False):
    rt, game, addon = context["boot"](extra=RETAIL + extra)
    if with_dot:
        loader = rt.eval("function(src, name, addon) return assert(loadstring(src, '@' .. name))"
                         "('UsefulPlatesAndTooltips', addon) end")
        for name in ("Locale.lua", "Retail.lua", "Core.lua", "Options.lua", "Nameplates.lua"):
            path = ROOT / "Modules/DoTInfo" / name
            loader(path.read_text(encoding="utf-8"), str(path), addon)
    context["start"](game, addon)
    game.Fire("PLAYER_ENTERING_WORLD")
    return rt, game, addon, addon.modules["ShieldsInfo"]


def same(game, a, b):
    return game.Same(a, b)


rt, game, addon, module = boot()
bars = [game.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar,
        game.TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar,
        game.party.HealthBarContainer.HealthBar, game.np.UnitFrame.HealthBarsContainer.healthBar]
for bar in bars:
    overlay = module._overlay(bar)
    assert overlay is not None and overlay.bar.shown
    assert same(game, overlay.bar.parent, bar)
    assert same(game, overlay.bar.value, game.SECRET_ABSORB)
    assert same(game, overlay.bar.maxValue, game.SECRET_MAX)
assert module._overlayCount() == 4
print("ok Retail player/target/nested-party/nameplate bars pass hidden absorb and health unchanged to native setters")

rt, game, addon, module = boot("""
party.HealthBarContainer = nil
party.healthbar = FakeMock('nativePartyAlias', party)
""")
assert module._overlay(game.party.healthbar).bar.shown
print("ok Retail's lowercase party healthbar alias is supported")

rt, game, addon, module = boot("""
party.displayedUnit = 'partypet1'
units.partypet1 = { absorb = 350, max = 1500 }
""")
overlay = module._overlay(game.party.HealthBarContainer.HealthBar)
assert overlay.bar.value == 350 and overlay.bar.maxValue == 1500
rt.execute("party.displayedUnit = SECRET_UNIT")
game.Tick(0.3)
assert not overlay.bar.shown
rt.execute("party.displayedUnit = nil")
game.Tick(0.3)
assert overlay.bar.shown and same(game, overlay.bar.value, game.SECRET_ABSORB)
print("ok readable displayed vehicle unit is used; a hidden displayed unit hides instead of reading another unit")

rt, game, addon, module = boot("""
function CompactUnitFrame_UpdateAll(frame) end
""")
rt.execute("party.displayedUnit = 'partypet1'; units.partypet1 = { absorb = 450, max = 2000 }")
game.CompactUnitFrame_UpdateAll(game.party)
overlay = module._overlay(game.party.HealthBarContainer.HealthBar)
assert overlay.bar.value == 450 and overlay.bar.maxValue == 2000
rt.execute("party.displayedUnit = SECRET_UNIT")
game.CompactUnitFrame_UpdateAll(game.party)
assert not overlay.bar.shown
print("ok compact update hooks use the same safe displayed-unit mapping as the heartbeat")

rt, game, addon, module = boot()
old_player = game.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
old_target = game.TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
old_party = game.party.HealthBarContainer.HealthBar
rt.execute("""
PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar = FakeMock('replacementPlayer')
TargetFrame = nil
party.HealthBarContainer.HealthBar = FakeMock('replacementParty', party)
""")
game.Tick(0.3)
assert not module._overlay(old_player).bar.shown
assert not module._overlay(old_target).bar.shown
assert not module._overlay(old_party).bar.shown
assert module._overlay(game.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar).bar.shown
assert module._overlay(game.party.HealthBarContainer.HealthBar).bar.shown
print("ok replaced player/party bars and a vanished target hide their old overlays")

rt, game, addon, module = boot()
bar = game.np.UnitFrame.HealthBarsContainer.healthBar
overlay = module._overlay(bar)
game.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert not overlay.bar.shown
rt.execute("""
np.UnitFrame.unit = 'nameplate2'
units.nameplate2 = { absorb = 700, max = 1400 }
""")
game.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
assert overlay.bar.shown and overlay.bar.value == 700 and overlay.bar.maxValue == 1400
rt.execute("plates = {}; plate = nil")
game.Tick(0.3)
assert not overlay.bar.shown
print("ok a recycled nameplate receives its new unit's shield; a vanished plate hides the old overlay")

rt, game, addon, module = boot("""
Platynator = {}
np.UnitFrame.HealthBarsContainer.healthBar:Hide()
display = FakeMock('platynatorDisplay', np)
healthWidget = FakeMock('platynatorHealthWidget', display)
healthWidget.details = { kind = 'health' }
healthWidget.statusBar = FakeMock('platynatorHealthBar', healthWidget)
display.widgets = { healthWidget }
function np:GetChildren() return unpack(self.children) end
""")
visible_bar = game.healthWidget.statusBar
overlay = module._overlay(visible_bar)
assert overlay is not None and overlay.bar.shown
assert same(game, overlay.bar.parent, visible_bar)
assert same(game, overlay.bar.value, game.SECRET_ABSORB)
assert module._overlay(game.np.UnitFrame.HealthBarsContainer.healthBar) is None
game.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert not overlay.bar.shown
rt.execute("healthWidget.statusBar = FakeMock('replacementPlatynatorHealthBar', healthWidget)")
game.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
assert module._overlay(game.healthWidget.statusBar).bar.shown
assert not overlay.bar.shown
print("ok Platynator shields use the visible bar; removal and bar replacement hide the old overlay")

rt, game, addon, module = boot("""
function UnitName(unit) return units[unit] and units[unit].name end
function UnitIsUnit(a, b) return units[a] ~= nil and rawequal(units[a], units[b]) end
spellNames[172], spellDesc[172] = 'Corruption', 'Causes 1200 Shadow damage over 12 sec.'
GameFontNormalSmall.GetFont = function() return 'Fonts\\\\FRIZQT__.TTF', 12, '' end
""", with_dot=True)
target_bar = game.TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
plate_bar = game.np.UnitFrame.HealthBarsContainer.healthBar
game.Fire("UNIT_SPELLCAST_SENT", "player", "Mob A", "Cast-1", 172)
game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 172)
game.Tick(0.3)
for bar in (target_bar, plate_bar):
    overlay = module._overlay(bar)
    assert overlay.bar.shown and overlay.edge
    assert overlay.bar.height == addon.Plate.SHIELD_EDGE
    assert same(game, overlay.bar.value, game.SECRET_ABSORB)
    assert same(game, overlay.bar.maxValue, game.SECRET_MAX)
addon.modules["DoTInfo"].db.showMarkers = False
game.Tick(0.3)
assert not module._overlay(target_bar).edge and not module._overlay(plate_bar).edge
player_bar = game.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
assert not module._overlay(player_bar).edge
print("ok live DoTInfo predictions yield a shield edge on target/nameplate; hiding DoT markers restores full fill")
