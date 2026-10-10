"""Exercise live bar resize/scale/visibility and host replacement; not a WoW rendering test."""
from pathlib import Path
from math import isclose

ROOT = Path(__file__).resolve().parent.parent
fixture = ROOT / "tests/test_bit.py"
context = {"__file__": str(fixture)}
exec(compile(fixture.read_text(encoding="utf-8").split(
    'print("-- every module on")', 1)[0], str(fixture), "exec"), context)

GEOMETRY = r'''
function methods.GetChildren(self) return unpack(self.children) end
function methods.SetScale(self, scale) self.scale = scale end
function methods.GetScale(self) return self.scale or 1 end
function methods.GetEffectiveScale(self)
    return self:GetScale() * (self.parent and self.parent:GetEffectiveScale() or 1)
end
function methods.ClearAllPoints(self) self.allPoints = nil; self.points = {} end
function methods.SetSize(self, width, height)
    self.width, self.height = width, height
    self.sizeWrites = (self.sizeWrites or 0) + 1
end
function methods.SetAllPoints(self, other)
    self.allPoints = other or self.parent
    self.points = { { 'TOPLEFT', self.allPoints, 'TOPLEFT' },
        { 'BOTTOMRIGHT', self.allPoints, 'BOTTOMRIGHT' } }
end
function methods.GetWidth(self)
    if self.allPoints then
        return self.allPoints:GetWidth() * self.allPoints:GetEffectiveScale() / self:GetEffectiveScale()
    end
    return self.width or 100
end
function methods.GetHeight(self)
    if self.allPoints then
        return self.allPoints:GetHeight() * self.allPoints:GetEffectiveScale() / self:GetEffectiveScale()
    end
    return self.height or 20
end
function methods.GetSize(self) return self:GetWidth(), self:GetHeight() end
function methods.SetValue(self, value) self.value = value end
function methods.SetMinMaxValues(self, low, high) self.minimum, self.maximum = low, high end
function GetLocale() return 'enUS' end
GameFontNormalSmall.GetFont = function() return 'Fonts\\FRIZQT__.TTF', 12, '' end
target = { hostile = true }
units.target = { guid = 'Creature-Resize', name = 'Dummy', health = 800, max = 1000 }
units.nameplate1 = units.target
function UnitName(unit) return units[unit] and units[unit].name end
function UnitIsUnit(a, b) return units[a] ~= nil and rawequal(units[a], units[b]) end
function UnitCanAttack(_, unit) return units[unit] == units.target end
plate = NewPlate()
plate.UnitFrame = FakeMock('UnitFrame', plate)
holder = FakeMock('HealthBarsContainer', plate.UnitFrame)
bar = FakeMock('plateHealth', holder)
holder.healthBar = bar
plate.UnitFrame.HealthBarsContainer = holder
plate.UnitFrame.healthBar = bar
bar:SetSize(170, 20)
bar:SetScale(1.25)
-- Treat the native bar as an opaque geometry reference, not an addon frame parent.
local frameFactory = CreateFrame
function CreateFrame(kind, name, parent, template)
    assert(parent ~= bar, 'addon widgets must stay outside the native health bar hierarchy')
    return frameFactory(kind, name, parent, template)
end
spellNames[172], spellDesc[172] = 'Corruption', 'Deals 400 Shadow damage over 12 sec.'
'''


for retail in (False, True):
    rt = context["LuaRuntime"](unpack_returned_tuples=True)
    rt.execute(context["FAKE"] + GEOMETRY)
    if retail:
        rt.execute("function GetBuildInfo() return '12.1.0', '69933', '', 120100 end")
    addon = rt.eval("{}")
    loader = rt.eval("function(src, name, addon) return assert(loadstring(src, '@' .. name))"
                     "('UsefulPlatesAndTooltips', addon) end")
    toc = "UsefulPlatesAndTooltips_Mainline.toc" if retail else "UsefulPlatesAndTooltips.toc"
    for name in (ROOT / toc).read_text(encoding="utf-8").splitlines():
        if name.strip() and not name.startswith("#"):
            name = name.strip().replace("\\", "/")
            loader((ROOT / name).read_text(encoding="utf-8"), name, addon)
    game, dot = rt.globals(), addon.modules.DoTInfo
    game.Fire("ADDON_LOADED", "UsefulPlatesAndTooltips")
    game.Fire("PLAYER_ENTERING_WORLD")
    dot.db.waitFirstTick = "never"
    dot.db.nameplateMode = "markerIcon"
    game.Fire("UNIT_SPELLCAST_SENT", "player", "Dummy", "Cast-Resize", 172)
    game.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Resize", 172)
    game.Tick(0.2)
    def on_plate(frame):
        while frame is not None:
            if game.Same(frame, game.plate):
                return True
            frame = frame.parent
        return False

    marker = next(frame for frame in game.AllFrames.values()
                  if frame.kind == "StatusBar"
                  and on_plate(frame)
                  and sum(child.kind == "StatusBar" for child in frame.children.values()) == 8)
    assert game.Same(marker.parent, game.plate)

    def fits_bar(reference=None):
        reference = reference if reference is not None else game.bar
        return (isclose(marker.GetWidth(marker) * marker.GetEffectiveScale(marker),
                        reference.GetWidth(reference) * reference.GetEffectiveScale(reference))
                and isclose(marker.GetHeight(marker) * marker.GetEffectiveScale(marker),
                            reference.GetHeight(reference) * reference.GetEffectiveScale(reference)))

    assert fits_bar()
    assert marker.value > 0
    value, count = marker.value, len(game.AllFrames)
    rt.execute("bar:SetSize(320, 44); bar:SetScale(1.8)")
    game.Tick(0.2)
    assert fits_bar()
    assert marker.value == value and len(game.AllFrames) == count
    assert len(marker.points) == 1 and marker.points[1][1] == "TOPLEFT"
    writes = marker.sizeWrites
    for _ in range(10):
        game.Tick(0.2)
    assert marker.sizeWrites == writes and len(game.AllFrames) == count
    rt.execute("plate:SetScale(1.5); bar:SetScale(2.1)")
    game.Tick(0.2)
    assert fits_bar() and marker.value == value
    game.plate.Hide(game.plate)
    assert not marker.IsVisible(marker)
    game.plate.Show(game.plate)
    assert marker.IsVisible(marker)
    # A live plate can retain its outer frame and replace the health bar during a style/layout change.
    rt.execute("""
        oldBar = bar
        bar = FakeMock('replacementHealth', holder)
        bar:SetSize(240, 28)
        bar:SetScale(0.9)
        holder.healthBar = bar
        plate.UnitFrame.healthBar = oldBar -- a stale compatibility alias must not win
        oldBar:Hide()
    """)
    count = len(game.AllFrames)
    game.Tick(0.2)
    assert len(game.AllFrames) == count and fits_bar()
    assert game.Same(marker.parent, game.plate)
    assert marker.IsVisible(marker) and marker.value == value
    rt.execute("""
        SECRET = setmetatable({}, { __mul = function() error('secret geometry math') end,
            __div = function() error('secret geometry math') end })
        function issecretvalue(value) return rawequal(value, SECRET) end
        readableSize = bar.GetSize
        readableScale = bar.GetEffectiveScale
        bar.GetSize = function() return SECRET, SECRET end
    """)
    game.Tick(0.2)
    assert game.Same(marker.allPoints, game.bar) and len(marker.points) == 2
    assert marker.value == value and marker.IsVisible(marker)
    rt.execute("bar.GetSize = readableSize; bar.GetEffectiveScale = function() return SECRET end")
    game.Tick(0.2)
    assert len(marker.points) == 2 and marker.value == value
    rt.execute("bar.GetEffectiveScale = function() error('unavailable scale') end")
    game.Tick(0.2)
    assert len(marker.points) == 2 and marker.value == value
    rt.execute("bar.GetEffectiveScale = readableScale; bar:SetSize(300, 36)")
    game.Tick(0.2)
    assert len(marker.points) == 1 and fits_bar() and marker.value == value
    # Actual reported path: Platynator reparents Blizzard's frame to a hidden host.
    rt.execute("""
        Platynator = {}
        hiddenHost = FakeMock('hiddenHost')
        hiddenHost:Hide()
        plate.UnitFrame:SetParent(hiddenHost)
        unusedDisplay = FakeMock('unusedPlatyDisplay', plate)
        unusedDisplay.widgets = { { details = { kind = 'health' }, statusBar = bar } }
        unusedDisplay:Hide()
        display = FakeMock('activePlatyDisplay', plate)
        display:SetScale(1.8)
        customBar = FakeMock('customHealthBar', display)
        customBar:SetSize(360, 40)
        customBar:SetScale(0.9)
        customAbsorb = FakeMock('customAbsorb', display)
        display.widgets = {
            { details = { kind = 'cast' }, statusBar = customAbsorb },
            { details = { kind = 'health' }, statusBar = customBar,
                statusBarAbsorb = customAbsorb, statusBarCutaway = customAbsorb },
        }
    """)
    count = len(game.AllFrames)
    game.Tick(0.2)
    assert not game.bar.IsVisible(game.bar)
    assert marker.IsVisible(marker) and fits_bar(game.customBar)
    assert game.Same(marker.points[1][2], game.customBar), "marker still anchored to hidden Blizzard bar"
    assert marker.value == value and len(game.AllFrames) == count
    rt.execute("customBar:SetSize(460, 52); display:SetScale(2.3)")
    game.Tick(0.2)
    assert fits_bar(game.customBar) and marker.value == value
    # A new style can replace the whole display; preallocated hidden displays must never win.
    rt.execute("""
        display:Hide()
        replacementDisplay = FakeMock('replacementPlatyDisplay', plate)
        replacementBar = FakeMock('replacementPlatyBar', replacementDisplay)
        replacementBar:SetSize(310, 34)
        replacementBar:SetScale(1.3)
        replacementDisplay.widgets = { { details = { kind = 'health' }, statusBar = replacementBar } }
    """)
    count = len(game.AllFrames)
    game.Tick(0.2)
    assert fits_bar(game.replacementBar) and game.Same(marker.points[1][2], game.replacementBar)
    assert marker.value == value and len(game.AllFrames) == count
    rt.execute("replacementDisplay:Hide()")
    game.Tick(0.2)
    assert not marker.IsShown(marker), "missing custom bar must not draw on the hidden native bar"
    rt.execute("replacementDisplay:Show()")
    game.Tick(0.2)
    assert marker.IsVisible(marker) and fits_bar(game.replacementBar)
    print(f"ok {'Retail' if retail else 'Forever'} overlay selects the visible Platynator health bar, follows size/style changes and skips hidden frames")
    assert not any("ERROR" in str(line) for line in dot.db.log.values())
    print(f"ok {'Retail' if retail else 'Forever'} overlay geometry follows bar resize/scale and reuses widgets on replacement")
