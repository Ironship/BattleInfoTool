"""BattleInfoTool module ShieldsInfo, tested against the same fake game tests/test_bit.py uses.

    python tests/test_shieldsinfo.py

The fake comes from tests/test_bit.py (AST-extracted, so this suite always runs against the
same environment the whole-addon suite uses). The module is loaded under the real core
(Core/Init.lua + Core/Settings.lua) exactly as the .toc would load it, so BIT.Module,
BIT.Settings, BIT.RegisterTab and BIT.tabWords behave as in the whole-addon suite.

The test-only additions (EXT) run in the same Lua chunk as the FAKE, so they can reach the
chunk-local mock()/methods. They record every native setter call ShieldsInfo makes and never
interpret the values, mirroring the client contract that raw secret values simply flow into
SetValue/SetMinMaxValues/SetFormattedText unchanged.
"""
import ast
import pathlib
import sys

from lupa.lua51 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODULE = ROOT / "Modules" / "ShieldsInfo" / "ShieldsInfo.lua"
CORE_FILES = ["Core\\Init.lua", "Core\\Settings.lua"]

AURA = r"Interface\AddOns\BattleInfoTool\Modules\ShieldsInfo\Textures\shield_aura.tga"
AURA_MIRROR = r"Interface\AddOns\BattleInfoTool\Modules\ShieldsInfo\Textures\shield_aura_mirrored.tga"


def fake_prefix():
    """The FAKE environment string from tests/test_bit.py, extracted with AST."""
    src = (pathlib.Path(__file__).parent / "test_bit.py").read_text(encoding="utf-8")
    tree = ast.parse(src)
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == "FAKE" for t in node.targets
        ):
            return ast.literal_eval(node.value)
    raise SystemExit("tests/test_bit.py no longer holds FAKE = ...; adapt test_shieldsinfo.py")


FAKE = fake_prefix()

# Test-only game extensions. Runs in the same chunk as the FAKE (the FAKE's mock()/methods
# are chunk-local). The recorded calls table lets the tests check that raw values -- secret
# numbers and object sentinels included -- reach the native setters unchanged.
EXT = r"""
-- native StatusBar / FontString setters, recorded verbatim
calls = {}
function methods.SetValue(self, v) self.value = v table.insert(calls, { self, "SetValue", v }) end
function methods.SetMinMaxValues(self, lo, hi)
    self.minValue, self.maxValue = lo, hi
    table.insert(calls, { self, "SetMinMaxValues", lo, hi })
end
function methods.GetMinMaxValues(self) return self.minValue or 0, self.maxValue or 1 end
function methods.SetFormattedText(self, fmt, ...)
    self.formatted = { fmt, ... }
    table.insert(calls, { self, "SetFormattedText", fmt, ... })
end
function methods.SetOrientation(self, o) self.orientation = o end
function methods.GetOrientation(self) return self.orientation or "HORIZONTAL" end
function methods.SetReverseFill(self, v) self.reverseFill = v and true or false end
function methods.SetStatusBarTexture(self, t) self.statusTexture = t end
function methods.SetStatusBarColor(self, r, g, b, a) self.statusColor = { r, g, b, a } end
function methods.SetAlpha(self, a) self.alpha = a end
function methods.SetFont(self, font, size, flags) self.font = { font, size, flags } end
function methods.SetTextColor(self, ...) self.textColor = { ... } end
function methods.SetShadowOffset(self, x, y) self.shadow = { x, y } end
function methods.EnableMouse(self, v) self.mouseEnabled = v and true or false end
function methods.SetMovable(self, v) self.movable = v and true or false end
function methods.SetClampedToScreen(self, v) end
function methods.RegisterForDrag(self, ...) self.drag = { ... } end
function methods.SetToplevel(self, v) end
function methods.StartMoving(self) self.moving = true end
function methods.StopMovingOrSizing(self) self.moving = false end
function methods.SetAllPoints(self, other) self.allPoints = other end
-- HUD geometry, client-shaped: a frame anchored CENTER to a frame with a recorded centre
-- carries its own centre in the anchor's units (anchor centre + SetPoint offsets);
-- GetCenter reports that centre in the frame's own scaled units (divided by the
-- effective/parent scale ratio, the client's Region:GetCenter contract), and
-- GetEffectiveScale walks the parent chain. UIParent's centre here is the drag geometry
-- the tests below drag against: 400,320.
UIParent.center = { 400, 320 }
function methods.GetEffectiveScale(self)
    if self.effScale then return self.effScale end
    local p = self.parent
    while p do
        if p.effScale then return p.effScale end
        p = p.parent
    end
    return 1
end
function methods.GetCenter(self)
    if self.center == nil then return nil end
    local s = self:GetEffectiveScale()
    local ps = self.parent ~= nil and self.parent:GetEffectiveScale() or s
    if s <= 0 or ps <= 0 then return nil end
    if s == ps then return self.center[1], self.center[2] end
    return self.center[1] * ps / s, self.center[2] * ps / s
end
function methods.SetPoint(self, point, relativeTo, relativePoint, x, y)
    table.insert(self.points, { point, relativeTo, relativePoint, x, y })
    if point == "CENTER" and relativePoint == "CENTER"
        and type(x) == "number" and type(y) == "number" then
        local ux, uy = 0, 0
        if type(relativeTo) == "table" and relativeTo.center then
            ux, uy = relativeTo.center[1], relativeTo.center[2]
        end
        self.center = { ux + x, uy + y }
    end
end
-- absorb readings: units[u].absorb is the client's answer (nil = none / cannot say)
function UnitGetTotalAbsorbs(u)
    local un = units[u]
    if un == nil then return nil end
    return un.absorb
end
C_NamePlate.GetNamePlates = function() return plates end
function callsOn(bar, name)
    local out = {}
    for i = 1, #calls do
        local r = calls[i]
        if rawequal(r[1], bar) and r[2] == name then
            out[#out + 1] = { select(3, unpack(r)) }
        end
    end
    return out
end
-- unit frames the module may attach to (the FAKE already has the Forever target frame; a
-- test that wants a legacy-only layout tears the modern path down itself)
PlayerFrame = mock("PlayerFrame")
PlayerFrame.PlayerFrameContent = mock("content", PlayerFrame)
PlayerFrame.PlayerFrameContent.PlayerFrameContentMain = mock("main", PlayerFrame.PlayerFrameContent)
PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBar = mock("healthbar",
    PlayerFrame.PlayerFrameContent.PlayerFrameContentMain)
PlayerFrame.healthbar = mock("legacybar", PlayerFrame)
TargetFrame.healthbar = mock("legacybar", TargetFrame)
for i = 1, 4 do
    local f = mock("PartyMemberFrame" .. i)
    f.healthBar = mock("healthBar", f)
    _G["PartyMemberFrame" .. i] = f
end
PartyFrame = mock("PartyFrame")
PartyFrame.PartyMemberFramePool = { activeObjects = {} }
function NewCompact(unit)
    local f = mock("compact")
    f.unit = unit
    f.healthBar = mock("healthBar", f)
    return f
end
"""

failures = 0


def check(label, actual, expected=True):
    global failures
    ok = actual == expected
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {label}" + ("" if ok else f"   (got {actual!r}, expected {expected!r})"))


def boot(saved=None, extra=""):
    """A fresh runtime: the FAKE plus the module under the real core. The module file is
    loaded only when it exists, so the first version of this suite fails on registration
    checks instead of crashing."""
    rt = LuaRuntime(unpack_returned_tuples=True)
    rt.execute(FAKE + EXT)
    G = rt.globals()
    if saved:
        rt.execute(saved)
    if extra:
        rt.execute(extra)
    BIT = rt.eval("{}")
    loader = rt.eval("function(src, name, BIT) local f = assert(loadstring(src, '@' .. name)); return f('BattleInfoTool', BIT) end")
    for f in CORE_FILES:
        loader((ROOT / f.replace("\\", "/")).read_text(encoding="utf-8"), f, BIT)
    if MODULE.exists():
        loader(MODULE.read_text(encoding="utf-8"), "Modules/ShieldsInfo/ShieldsInfo.lua", BIT)
    return rt, G, BIT


def start(G, BIT):
    """The module's own start, as the whole-addon suite drives it."""
    G.Fire("ADDON_LOADED", "BattleInfoTool")
    G.Fire("PLAYER_LOGIN")


def on_bar(G, bar, name):
    """The recorded calls of one name on one StatusBar, without the frame/name slots."""
    t = G.callsOn(bar, name)
    return [[t[i][j] for j in range(1, len(t[i]) + 1)] for i in range(1, len(t) + 1)]


def settings(G):
    return G.BattleInfoToolDB.modules.ShieldsInfo


# ---------------------------------------------------------------------------------------------
print("-- registration and the on/off switch")
rt, G, BIT = boot()
M = BIT.modules["ShieldsInfo"]
check("ShieldsInfo registered its module and tab",
      (M is not None, BIT.tabs["ShieldsInfo"] is not None and BIT.tabs["ShieldsInfo"].title,
       BIT.tabWords.shields),
      (True, "Shields", "ShieldsInfo"))
check("the tab fits the settings window",
      (BIT.tabs["ShieldsInfo"].width, BIT.tabs["ShieldsInfo"].height) <= (760, 430), True)
check("no BattleInfoTool_ShieldsInfoDB SavedVariables of its own", G.BattleInfoTool_ShieldsInfoDB, None)
check("the module makes no global of its own", G.ShieldsInfo, None)

start(G, BIT)
check("runs after ADDON_LOADED", BIT.state["ShieldsInfo"], "on")
check("its settings live in BIT.Settings only", G.Same(BIT.Settings("ShieldsInfo"), settings(G)), True)
check("defaults: unit indicators on, the HUD off",
      (settings(G).player, settings(G).target, settings(G).party, settings(G).nameplates,
       settings(G).hud, settings(G).numbers), (True, True, True, True, False, True))
check("a heartbeat driver exists and an update is exposed",
      (M._driver() is not None, type(M.Update).__name__ != "NoneType"), (True, True))

rt3, G3, BIT3 = boot()
M3 = BIT3.modules["ShieldsInfo"]
G3.Fire("ADDON_LOADED", "SomeOtherAddon")
check("another addon's ADDON_LOADED is ignored", BIT3.state["ShieldsInfo"], None)
check("  and does not create a driver", M3._driver(), None)
start(G3, BIT3)
check("  BattleInfoTool's own ADDON_LOADED starts it", BIT3.state["ShieldsInfo"], "on")

rt2, G2, BIT2 = boot(saved="BattleInfoToolDB = { modules = { ShieldsInfo = { enabled = false } } }")
M2 = BIT2.modules["ShieldsInfo"]
G2.Fire("ADDON_LOADED", "BattleInfoTool")
G2.Fire("PLAYER_LOGIN")
check("switched off: nothing runs, no HUD, no polling",
      (BIT2.state["ShieldsInfo"], M2._driver(), M2._hud(), M2._overlayCount()), ("off", None, None, 0))
G2.units["player"] = rt2.eval("{ absorb = 1200, health = 800, max = 1000 }")
G2.units["target"] = rt2.eval("{ absorb = 400, health = 800, max = 1000 }")
G2.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
G2.Tick(1)
check("  ticking and events draw nothing while off", M2._overlayCount(), 0)

# ---------------------------------------------------------------------------------------------
print("-- the player frame")
rt, G, BIT = boot()
start(G, BIT)
M = BIT.modules["ShieldsInfo"]
modern = G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBar
G.units["player"] = rt.eval("{ absorb = 1200, health = 800, max = 1000 }")
G.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
o = M._overlay(modern)
check("an overlay sits on the modern player health bar",
      o is not None and G.Same(o.bar.parent, modern), True)
check("  it is its own frame, and the bar's geometry is untouched",
      (not G.Same(o.bar, modern), modern.width, modern.height), (True, None, None))
check("  it reads raw absorb and the raw health pool",
      on_bar(G, o.bar, "SetMinMaxValues"), [[0, 1000]])
check("  and shows the remaining absorb", on_bar(G, o.bar, "SetValue"), [[1200]])
check("  with the module's own shield texture", o.bar.statusTexture, AURA)

o2 = M._overlay(G.PlayerFrame.healthbar)
check("the legacy .healthbar of the player frame is untouched", o2, None)

G.units["player"].absorb = 0
G.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("a plain zero is no shield: the overlay hides", M._overlay(modern).bar.shown, False)

G.units["player"].absorb = 300
G.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("a new shield shows again", M._overlay(modern).bar.shown, True)
check("  and the bar drains with the real remaining absorb",
      on_bar(G, M._overlay(modern).bar, "SetValue")[-1], [300])

settings(G).player = False
M.Update()
check("the player toggle hides its overlay", M._overlay(modern).bar.shown, False)
settings(G).player = True
M.Update()
check("  and turning it back on shows it again", M._overlay(modern).bar.shown, True)

rtL, GL, BITL = boot(extra="PlayerFrame.PlayerFrameContent = nil")
start(GL, BITL)
ML = BITL.modules["ShieldsInfo"]
GL.units["player"] = rtL.eval("{ absorb = 77, health = 800, max = 1000 }")
GL.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
oL = ML._overlay(GL.PlayerFrame.healthbar)
check("without the modern path: the overlay uses the legacy healthbar",
      oL is not None and GL.Same(oL.bar.parent, GL.PlayerFrame.healthbar), True)

rtS, GS, BITS = boot()
rtS.execute("SECRET_TABLE = {} function issecretvalue(v) return v == SECRET_TABLE or v == 1876543 end")
start(GS, BITS)
MS = BITS.modules["ShieldsInfo"]
GS.units["player"] = rtS.eval("{ absorb = 1876543, health = 800, max = 1000 }")
GS.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
oS = MS._overlay(GS.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBar)
check("a secret absorb number reaches SetValue unchanged",
      (on_bar(GS, oS.bar, "SetValue")[-1][0] == 1876543, oS.bar.shown), (True, True))
GS.units["player"].absorb = GS.SECRET_TABLE
GS.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("a secret object sentinel reaches SetValue unchanged", GS.Same(oS.bar.value, GS.SECRET_TABLE), True)
check("  and the overlay still shows", oS.bar.shown, True)

GS.units["player"].absorb = None
GS.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("nil absorbs clear the stale overlay", oS.bar.shown, False)

GS.UnitGetTotalAbsorbs = rtS.eval("function() error('cannot say') end")
GS.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("an erroring API hides instead of guessing", oS.bar.shown, False)
check("  and draws no second overlay", MS._overlayCount(), 1)
GS.UnitGetTotalAbsorbs = None
GS.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("a missing API shows nothing", oS.bar.shown, False)

# ---------------------------------------------------------------------------------------------
print("-- the target frame")
rt, G, BIT = boot()
start(G, BIT)
M = BIT.modules["ShieldsInfo"]
tmodern = G.TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
G.units["target"] = rt.eval("{ absorb = 900, health = 800, max = 1000 }")
G.Fire("PLAYER_TARGET_CHANGED")
to = M._overlay(tmodern)
check("an overlay sits on the Forever target health bar",
      to is not None and G.Same(to.bar.parent, tmodern), True)
check("  with the target's remaining absorb", on_bar(G, to.bar, "SetValue")[-1], [900])
check("the legacy .healthbar of the target frame is untouched", M._overlay(G.TargetFrame.healthbar), None)

G.units["target"].absorb = None
G.Fire("PLAYER_TARGET_CHANGED")
check("no target shield: hidden", to.bar.shown, False)

settings(G).target = False
G.units["target"].absorb = 900
G.units["player"] = rt.eval("{ absorb = 250, health = 800, max = 1000 }")
M.Update()
check("the target toggle keeps it hidden", to.bar.shown, False)
check("  while the player overlay still shows its own shield",
      (M._overlay(G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBar) is not None,
       M._overlay(G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBar).bar.shown),
      (True, True))

rtL, GL, BITL = boot(extra="TargetFrame.TargetFrameContent = nil")
start(GL, BITL)
ML = BITL.modules["ShieldsInfo"]
GL.units["target"] = rtL.eval("{ absorb = 55, health = 800, max = 1000 }")
GL.Fire("PLAYER_TARGET_CHANGED")
oTL = ML._overlay(GL.TargetFrame.healthbar)
check("without the modern path: the target overlay uses the legacy healthbar",
      oTL is not None and GL.Same(oTL.bar.parent, GL.TargetFrame.healthbar), True)

# ---------------------------------------------------------------------------------------------
print("-- party: classic frames, the compact pool, and the compact hooks")
rt, G, BIT = boot()
start(G, BIT)
M = BIT.modules["ShieldsInfo"]
for i in range(1, 5):
    G.units["party%d" % i] = rt.eval("{ absorb = %d, health = 800, max = 1000 }" % (i * 100))
G.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "party1")
bars = [G["PartyMemberFrame%d" % i].healthBar for i in range(1, 5)]
check("party1..4: an overlay on each classic party frame",
      all(M._overlay(b) is not None and G.Same(M._overlay(b).bar.parent, b) for b in bars), True)
check("  each shows its own unit's remaining absorb",
      [on_bar(G, M._overlay(b).bar, "SetValue")[-1][0] for b in bars], [100, 200, 300, 400])
G.units["party2"].absorb = None
G.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "party2")
check("a party member without a shield shows nothing", M._overlay(bars[1]).bar.shown, False)
G.units["party2"].absorb = 200
G.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "party2")
check("  and it returns with the next event", M._overlay(bars[1]).bar.shown, True)

rtP, GP, BITP = boot()
start(GP, BITP)
MP = BITP.modules["ShieldsInfo"]
rtP.execute("poolA = NewCompact('party1') poolB = NewCompact('party3') "
            "PartyFrame.PartyMemberFramePool.activeObjects = { poolA, poolB }")
GP.units["party1"] = rtP.eval("{ absorb = 340, health = 800, max = 1000 }")
GP.units["party3"] = rtP.eval("{ absorb = 520, health = 800, max = 1000 }")
GP.Tick(0.5)
oA = MP._overlay(GP.poolA.healthBar)
oB = MP._overlay(GP.poolB.healthBar)
check("the compact pool of PartyFrame gets its overlays",
      (oA is not None and oA.bar.shown, oB is not None and oB.bar.shown), (True, True))
check("  each reads the unit the frame carries",
      [on_bar(GP, o.bar, "SetValue")[-1][0] for o in (oA, oB)], [340, 520])

rtC, GC, BITC = boot(extra="function CompactUnitFrame_UpdateAll(f) end "
                           "function CompactUnitFrame_UpdateHealPrediction(f) end")
MC = BITC.modules["ShieldsInfo"]
start(GC, BITC)
check("the compact hooks are wired at PLAYER_LOGIN", MC._hooksAttached(), (True, True))
cf = GC.NewCompact("party2")
GC.units["party2"] = rtC.eval("{ absorb = 640, health = 800, max = 1000 }")
GC.CompactUnitFrame_UpdateAll(cf)
oCF = MC._overlay(cf.healthBar)
check("CompactUnitFrame_UpdateAll refreshes the frame's overlay",
      (oCF is not None, oCF is not None and oCF.bar.shown,
       oCF is not None and on_bar(GC, oCF.bar, "SetValue")[-1]), (True, True, [640]))
GC.units["party2"].absorb = 300
GC.CompactUnitFrame_UpdateHealPrediction(cf)
check("  and so does its heal prediction update",
      on_bar(GC, MC._overlay(cf.healthBar).bar, "SetValue")[-1], [300])

rtL, GL, BITL = boot()
ML = BITL.modules["ShieldsInfo"]
start(GL, BITL)
check("no compact hooks yet: none wired", ML._hooksAttached(), (False, False))
GL.CompactUnitFrame_UpdateAll = rtL.eval("function(f) end")
GL.CompactUnitFrame_UpdateHealPrediction = rtL.eval("function(f) end")
GL.Tick(0.5)
check("the tick finds late-arriving hooks and wires them", ML._hooksAttached(), (True, True))
lf = GL.NewCompact("party3")
GL.units["party3"] = rtL.eval("{ absorb = 777, health = 800, max = 1000 }")
GL.CompactUnitFrame_UpdateAll(lf)
check("the late hook updates the compact frame",
      ML._overlay(lf.healthBar) is not None and ML._overlay(lf.healthBar).bar.shown, True)
GL.units["party3"].absorb = None
GL.units["party4"] = rtL.eval("{ absorb = 888, health = 800, max = 1000 }")
lf.unit = "party4"  # Blizzard reassigns the frame in place when the roster changes
GL.CompactUnitFrame_UpdateAll(lf)  # ... and updates it, as the client does
check("a frame reassigned to another party slot shows that unit",
      on_bar(GL, ML._overlay(lf.healthBar).bar, "SetValue")[-1], [888])
settings(GL).party = False
GL.CompactUnitFrame_UpdateAll(lf)
check("the party toggle hides compact overlays", ML._overlay(lf.healthBar).bar.shown, False)
settings(GL).party = True
GL.CompactUnitFrame_UpdateAll(lf)
check("  and back on shows them again", ML._overlay(lf.healthBar).bar.shown, True)

# the tick re-reads every pool frame's unit, so even a reassignment the hooks never saw
# corrects itself on the next beat
GP.poolA.unit = "party2"
GP.units["party2"] = rtP.eval("{ absorb = 640, health = 800, max = 1000 }")
GP.Tick(0.5)
check("the tick re-reads a pool frame's unit after a roster change",
      on_bar(GP, oA.bar, "SetValue")[-1], [640])
GP.poolB.unit = "party1"
GP.units["party1"].absorb = 999
GP.Tick(0.5)
check("  and follows it to the next assignment",
      on_bar(GP, oB.bar, "SetValue")[-1], [999])

# ---------------------------------------------------------------------------------------------
print("-- nameplates")
rt, G, BIT = boot()
start(G, BIT)
M = BIT.modules["ShieldsInfo"]
rt.execute("np1 = NewPlate() np1.UnitFrame.unit = 'nameplate1' "
           "np2 = NewPlate() np2.UnitFrame.unit = 'nameplate2' "
           "np3 = NewPlate() np3.UnitFrame.unit = 'nameplate3' "
           "np3.UnitFrame.healthBar = nil "
           "np3.UnitFrame.HealthBarsContainer = { healthBar = FakeMock('plateBar', np3) } "
           "plates = { np1, np2, np3 }")
G.units["nameplate1"] = rt.eval("{ absorb = 111, health = 800, max = 1000 }")
G.units["nameplate2"] = rt.eval("{ absorb = 222, health = 800, max = 1000 }")
G.units["nameplate3"] = rt.eval("{ absorb = 333, health = 800, max = 1000 }")
G.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
o1 = M._overlay(G.np1.UnitFrame.healthBar)
o2 = M._overlay(G.np2.UnitFrame.healthBar)
o3 = M._overlay(G.np3.UnitFrame.HealthBarsContainer.healthBar)
check("every accessible nameplate gets an overlay",
      (o1 is not None and o1.bar.shown, o2 is not None and o2.bar.shown,
       o3 is not None and o3.bar.shown), (True, True, True))
check("  each with its plate's unit",
      [on_bar(G, o.bar, "SetValue")[-1][0] for o in (o1, o2, o3)], [111, 222, 333])
check("  a plate without .healthBar but with HealthBarsContainer works",
      G.Same(o3.bar.parent, G.np3.UnitFrame.HealthBarsContainer.healthBar), True)

# the client hands the plate back: the overlay must leave at once, even while the client
# still answers the unit with this plate
G.plate = G.np1
G.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
check("a handed-back plate clears its overlay immediately", o1.bar.shown, False)
G.plate = None
rt.execute("plates = { np2, np3 }")
G.Tick(0.5)
check("  and it stays off while the plate is gone", o1.bar.shown, False)

# the client reuses the same plate object for another unit
rt.execute("plates = { np1, np2, np3 } np1.UnitFrame.unit = 'nameplate7'")
G.units["nameplate7"] = rt.eval("{ absorb = 777, health = 800, max = 1000 }")
G.Fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
check("a recycled plate shows the new unit's absorb",
      (o1.bar.shown, on_bar(G, o1.bar, "SetValue")[-1]), (True, [777]))
rt.execute("np1.UnitFrame.unit = 'nameplate8'")
G.units["nameplate8"] = rt.eval("{ absorb = nil, health = 800, max = 1000 }")
G.Fire("NAME_PLATE_UNIT_ADDED", "nameplate8")
check("  and without a shield on the new unit it stays hidden", o1.bar.shown, False)

settings(G).nameplates = False
G.Tick(0.5)
check("the nameplates toggle clears the remaining plates",
      (o2.bar.shown, o3.bar.shown), (False, False))
settings(G).nameplates = True
G.Tick(0.5)
check("  and back on they show again",
      (o2.bar.shown, on_bar(G, o2.bar, "SetValue")[-1]), (True, [222]))

rtF, GF, BITF = boot()
start(GF, BITF)
MF = BITF.modules["ShieldsInfo"]
rtF.execute("guard = NewPlate() guard.UnitFrame.unit = 'nameplateX' "
            "guard.IsForbidden = function() return true end "
            "plates = { guard }")
GF.units["nameplateX"] = rtF.eval("{ absorb = 555, health = 800, max = 1000 }")
GF.Tick(0.5)
check("a protected plate is skipped without an overlay or an error",
      (MF._overlayCount(), MF._overlay(GF.guard.UnitFrame.healthBar)), (0, None))

# ---------------------------------------------------------------------------------------------
print("-- the HUD")


def hud_state(G, M):
    h, b, t = M._hud(), M._hudBar(), M._hudText()
    if h is None or b is None or t is None:
        return None
    return (h.shown, b.shown, t.shown)


rt, G, BIT = boot()
start(G, BIT)
M = BIT.modules["ShieldsInfo"]
hud, hudBar, hudText = M._hud(), M._hudBar(), M._hudText()
check("the HUD exists but is off by default",
      (hud is not None, hudBar is not None, hudText is not None, hud_state(G, M)), (True, True, True, (False, False, False)))
G.units["player"] = rt.eval("{ absorb = 500, health = 800, max = 1000 }")
G.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("  and draws nothing while off", hud_state(G, M), (False, False, False))

settings(G).hud = True
M.Update()
check("a fresh shield calibrates the HUD maximum",
      (hud_state(G, M), on_bar(G, hudBar, "SetMinMaxValues")[-1]), ((True, True, True), [0, 500]))
check("  the remaining absorb fills the aura", on_bar(G, hudBar, "SetValue")[-1], [500])
check("  and the plain number is set from the raw value",
      on_bar(G, hudText, "SetFormattedText")[-1], ["%.0f", 500])

G.units["player"].absorb = 300
G.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("draining keeps the calibrated maximum, only the value moves",
      (on_bar(G, hudBar, "SetMinMaxValues")[-1], on_bar(G, hudBar, "SetValue")[-1]), ([0, 500], [300]))
G.units["player"].absorb = 800
G.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("a bigger shield recalibrates the maximum", on_bar(G, hudBar, "SetMinMaxValues")[-1], [0, 800])
G.units["player"].absorb = 0
G.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("depletion clears the maximum", on_bar(G, hudBar, "SetMinMaxValues")[-1], [0, 1])
G.units["player"].absorb = 400
G.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("  so the next fresh shield calibrates again", on_bar(G, hudBar, "SetMinMaxValues")[-1], [0, 400])

rtH, GH, BITH = boot()
rtH.execute("SECRET_TABLE = {} function issecretvalue(v) return v == SECRET_TABLE or v == 12345 end")
start(GH, BITH)
MH = BITH.modules["ShieldsInfo"]
settings(GH).hud = True
hudBarH, hudTextH = MH._hudBar(), MH._hudText()
GH.units["player"] = rtH.eval("{ absorb = 12345, health = 800, max = 1000 }")
MH.Update()
check("a combat-only secret shield can become the native maximum",
      (GH.Same(on_bar(GH, hudBarH, "SetMinMaxValues")[-1][1], 12345), hudBarH.shown), (True, True))
GH.units["player"].absorb = 9999
GH.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("  the secret value flows to SetValue unchanged, the max untouched",
      (GH.Same(on_bar(GH, hudBarH, "SetValue")[-1][0], 9999),
       on_bar(GH, hudBarH, "SetMinMaxValues")[-1]), (True, [0, 12345]))
check("  and the number is formatted by the native call",
      GH.Same(on_bar(GH, hudTextH, "SetFormattedText")[-1][1], 9999), True)
GH.units["player"].absorb = GH.SECRET_TABLE
GH.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("  an object sentinel flows through too",
      GH.Same(on_bar(GH, hudBarH, "SetValue")[-1][0], GH.SECRET_TABLE), True)

GH.units["player"].absorb = None
GH.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("a nil reading clears the HUD and its number", hud_state(GH, MH), (False, False, False))
GH.UnitGetTotalAbsorbs = rtH.eval("function() error('no') end")
GH.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("  an erroring API clears it too", hud_state(GH, MH), (False, False, False))
GH.UnitGetTotalAbsorbs = None
GH.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("  and a missing API shows nothing", hud_state(GH, MH), (False, False, False))
GH.UnitGetTotalAbsorbs = rtH.eval("function(u) local un = units[u] if un == nil then return nil end return un.absorb end")
GH.units["player"].absorb = 700
GH.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("  the HUD returns with the API", hud_state(GH, MH), (True, True, True))

settings(GH).numbers = False
GH.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("numbers off hides the text but keeps the aura",
      (MH._hud().shown, MH._hudBar().shown, MH._hudText().shown), (True, True, False))
settings(GH).numbers = True
GH.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("  and back on the number returns", MH._hudText().shown, True)

settings(GH).preview = True
GH.units["player"].absorb = 300
GH.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("preview shows the fixed sample regardless of live absorb, max untouched",
      (on_bar(GH, hudBarH, "SetMinMaxValues")[-1], on_bar(GH, hudBarH, "SetValue")[-1],
       on_bar(GH, hudTextH, "SetFormattedText")[-1]), ([0, 12345], [72], ["%.0f", 72]))
settings(GH).preview = False
GH.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("  back to live data: draining, the seeded maximum untouched",
      (on_bar(GH, hudBarH, "SetMinMaxValues")[-1], on_bar(GH, hudBarH, "SetValue")[-1]),
      ([0, 12345], [300]))
settings(GH).hud = False
settings(GH).preview = True
GH.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("the HUD switch wins over preview", hud_state(GH, MH), (False, False, False))
settings(GH).hud = True
settings(GH).preview = False

rtV, GV, BITV = boot()
rtV.execute("SECRET_TABLE = {} function issecretvalue(v) return v == SECRET_TABLE or v == 12345 end")
start(GV, BITV)
MV = BITV.modules["ShieldsInfo"]
settings(GV).hud = True
GV.units["player"] = rtV.eval("{ absorb = 12345, health = 800, max = 1000 }")
MV.Update()
rtV.execute("function ScanSecret(t) for k, v in pairs(t) do "
            "if rawequal(v, SECRET_TABLE) then return true end "
            "if type(v) == 'table' and ScanSecret(v) then return true end end return false end")
check("no secret reading is ever stored in the saved settings",
      GV.ScanSecret(GV.BattleInfoToolDB), False)

settings(G).scale = 1.5
settings(G).mirror = True
settings(G).locked = False
M._applyLayout()
check("scale resizes the HUD and its aura",
      (hud.width, hud.height, hudBar.width, hudBar.height), (96, 237, 51, 198))
check("mirror uses the left-side curve", hudBar.statusTexture, AURA_MIRROR)
check("unlock makes it draggable", hud.mouseEnabled, True)
settings(G).locked = True
M._applyLayout()
check("  lock removes the drag", hud.mouseEnabled, False)
check("the HUD position comes from the settings",
      any(len(p) >= 5 and p[1] == "CENTER" and p[3] == "CENTER" and p[4] == settings(G).x and p[5] == settings(G).y
          for p in [hud.points[i] for i in range(1, len(hud.points) + 1)]), True)

# ---------------------------------------------------------------------------------------------
print("-- the settings tab")
rt, G, BIT = boot()
start(G, BIT)
M = BIT.modules["ShieldsInfo"]
BIT.OpenSettings("ShieldsInfo")
page = BIT._pages["ShieldsInfo"]
check("the Shields tab opens in the settings window", page is not None and page.shown, True)
c = M._checks
check("the tab built every toggle",
      c is not None and all(c[k] is not None for k in
                           ("player", "target", "party", "nameplates", "hud", "numbers",
                            "mirror", "preview", "unlocked", "scale")), True)
modern = G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBar
G.units["player"] = rt.eval("{ absorb = 640, health = 800, max = 1000 }")
G.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("  with the player shield shown", M._overlay(modern).bar.shown, True)
c["player"].checked = False
c["player"].scripts.OnClick(c["player"])
check("clicking the player toggle hides it and saves",
      (M._overlay(modern).bar.shown, settings(G).player), (False, False))
c["player"].checked = True
c["player"].scripts.OnClick(c["player"])
check("  and back on shows it again",
      (M._overlay(modern).bar.shown, settings(G).player), (True, True))
c["hud"].checked = True
c["hud"].scripts.OnClick(c["hud"])
check("the HUD toggle turns the HUD on", (settings(G).hud, M._hud().shown), (True, True))
c["preview"].checked = True
c["preview"].scripts.OnClick(c["preview"])
check("the preview toggle shows the sample",
      (settings(G).preview, on_bar(G, M._hudBar(), "SetValue")[-1]), (True, [72]))
c["numbers"].checked = False
c["numbers"].scripts.OnClick(c["numbers"])
check("the numbers toggle hides the HUD number",
      (settings(G).numbers, M._hudText().shown), (False, False))
c["unlocked"].checked = True
c["unlocked"].scripts.OnClick(c["unlocked"])
check("the unlocked toggle makes the HUD draggable",
      (settings(G).locked, M._hud().mouseEnabled), (False, True))
c["mirror"].checked = True
c["mirror"].scripts.OnClick(c["mirror"])
check("the mirror toggle flips the curve",
      (settings(G).mirror, M._hudBar().statusTexture), (True, AURA_MIRROR))
scale = M._checks["scale"].bar
scale.scripts.OnValueChanged(scale, 2.0)
check("the scale slider resizes the HUD",
      (settings(G).scale, M._hud().width, M._hudBar().height), (2, 128, 264))
c["preview"].checked = False
c["preview"].scripts.OnClick(c["preview"])
G.units["player"].absorb = 640
G.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("  the overlays stay live while the tab is open", M._overlay(modern).bar.shown, True)

print("-- the number under the HUD")
rtU, GU, BITU = boot()
rtU.execute("C_StringUtil = { TruncateWhenZero = function(v) table.insert(calls, { 'Truncate', v }) return 'T' end }")
start(GU, BITU)
MU = BITU.modules["ShieldsInfo"]
settings(GU).hud = True
GU.units["player"] = rtU.eval("{ absorb = 4321, health = 800, max = 1000 }")
MU.Update()
tlast = None
i = 1
while GU.calls[i] is not None:
    r = GU.calls[i]
    if len(r) >= 2 and r[1] == "Truncate":
        tlast = r[2]
    i += 1
check("with C_StringUtil the raw value reaches TruncateWhenZero",
      (GU.Same(tlast, 4321), MU._hudText().text), (True, "T"))

print("-- frames that arrive or are replaced later")
rtR, GR, BITR = boot()
start(GR, BITR)
MR = BITR.modules["ShieldsInfo"]
GR.units["player"] = rtR.eval("{ absorb = 555, health = 800, max = 1000 }")
GR.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
oldBar = GR.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBar
check("an overlay on the first bar object", MR._overlay(oldBar) is not None, True)
rtR.execute("PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBar = FakeMock('healthbar')")
newBar = GR.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBar
GR.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("a replaced health bar gets its own overlay and value",
      (MR._overlay(newBar) is not None, on_bar(GR, MR._overlay(newBar).bar, "SetValue")[-1]),
      (True, [555]))
GR.units["player"].absorb = 111
GR.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("  and keeps receiving updates", on_bar(GR, MR._overlay(newBar).bar, "SetValue")[-1], [111])
rtR.execute("PlayerFrame = nil")
GR.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "player")
check("a vanished unit frame does not stop or crash the module", MR._overlayCount(), 2)

# ---------------------------------------------------------------------------------------------
print("-- the HUD remembers where it is dragged, and the position survives a reload")


def center_point(G, hud):
    """The HUD's latest CENTER-to-CENTER anchor as SetPoint recorded it."""
    for i in range(len(hud.points), 0, -1):
        p = hud.points[i]
        if len(p) >= 5 and p[1] == "CENTER" and p[3] == "CENTER":
            return (p[4], p[5])
    return None


def drag_stop(G, hud):
    """The client's end-of-drag on the HUD, after the frame has been moved."""
    hud.scripts.OnDragStop(hud)


rt, G, BIT = boot()
start(G, BIT)
M = BIT.modules["ShieldsInfo"]
hud = M._hud()
settings(G).hud = True
settings(G).locked = False
hud.center = rt.eval("{ 500, 300 }")  # the client moved the frame: centre 500,300 of 400,320
drag_stop(G, hud)
check("a drag stop saves the HUD's offset from the screen centre",
      (settings(G).x, settings(G).y), (100, -20))
check("  the re-applied layout carries exactly the saved offset",
      center_point(G, hud), (100, -20))
check("  and the HUD's centre is the position the drag ended at",
      hud.GetCenter(hud), (500.0, 300.0))

rt2, G2, BIT2 = boot(
    saved="BattleInfoToolDB = { modules = { ShieldsInfo = { x = 100, y = -20 } } }")
start(G2, BIT2)
M2 = BIT2.modules["ShieldsInfo"]
hud2 = M2._hud()
check("a fresh session re-anchors the HUD at the saved offsets",
      (center_point(G2, hud2), hud2.GetCenter(hud2)), ((100, -20), (500.0, 300.0)))

rtL, GL, BITL = boot()
start(GL, BITL)
ML = BITL.modules["ShieldsInfo"]
hudL = ML._hud()
hudL.scripts.OnDragStart(hudL)
check("a locked HUD refuses to start a drag", hudL.moving, None)
settings(GL).locked = False
hudL.scripts.OnDragStart(hudL)
check("  and an unlocked HUD starts moving", hudL.moving, True)

rtG, GG, BITG = boot()
start(GG, BITG)
MG = BITG.modules["ShieldsInfo"]
hudG = MG._hud()
settings(GG).hud = True
settings(GG).locked = False
hudG.center = rtG.eval("{ 500, 300 }")
drag_stop(GG, hudG)
check("the drag saved before the guarded cases",
      (settings(GG).x, settings(GG).y), (100, -20))
hudG.center = None
drag_stop(GG, hudG)
check("unreadable geometry keeps the saved position",
      (settings(GG).x, settings(GG).y), (100, -20))
hudG.center = rtG.eval("{ 600, 200 }")
hudG.GetCenter = rtG.eval("function() error('protected: no geometry during a reset') end")
drag_stop(GG, hudG)
check("an erroring GetCenter keeps the saved position",
      (settings(GG).x, settings(GG).y), (100, -20))
hudG.GetCenter = None
hudG.center = rtG.eval("{ 0/0, 0/0 }")
drag_stop(GG, hudG)
check("a NaN centre keeps the saved position",
      (settings(GG).x, settings(GG).y), (100, -20))

rtS, GS, BITS = boot()
start(GS, BITS)
MS = BITS.modules["ShieldsInfo"]
hudS = MS._hud()
settings(GS).hud = True
settings(GS).locked = False
GS.UIParent.effScale = 0.75
hudS.effScale = 1.5
hudS.center = rtS.eval("{ 500, 300 }")
drag_stop(GS, hudS)
check("a drag under another effective scale saves the same parent-unit offset",
      (settings(GS).x, settings(GS).y), (100, -20))
check("  and the scaled readback agrees: the drag and the layout are the same position",
      (hudS.GetCenter(hudS), center_point(GS, hudS)), ((250.0, 150.0), (100, -20)))
hudS.effScale = None
GS.UIParent.effScale = 0
hudS.center = rtS.eval("{ 700, 400 }")
drag_stop(GS, hudS)
check("a zero parent scale keeps the saved position",
      (settings(GS).x, settings(GS).y), (100, -20))

rtC, GC, BITC = boot(
    saved="BattleInfoToolDB = { modules = { ShieldsInfo = { x = 'bogus!', y = 'junk' } } }")
start(GC, BITC)
MC = BITC.modules["ShieldsInfo"]
hudC = MC._hud()
check("corrupt saved offsets are not fed to SetPoint (defaults apply)",
      center_point(GC, hudC), (95, 20))
check("  and the corrupt values stay untouched in the saved settings",
      (settings(GC).x, settings(GC).y), ("bogus!", "junk"))
settings(GC).x = 42.75
settings(GC).y = "-31"
MC._applyLayout()
check("valid numeric offsets, a numeric string included, are preserved",
      center_point(GC, hudC), (42.75, -31))
settings(GC).x = rtC.eval("0/0")
MC._applyLayout()
check("a NaN offset falls back to the default", center_point(GC, hudC), (95, -31))
settings(GC).x = rtC.eval("math.huge")
MC._applyLayout()
check("an infinite offset falls back to the default", center_point(GC, hudC), (95, -31))
settings(GC).x = 42.75
settings(GC).y = rtC.eval("-math.huge")
MC._applyLayout()
check("an infinite y offset falls back to its own default", center_point(GC, hudC), (42.75, 20))

if __name__ == "__main__":
    print(f"\nfailures: {failures}")
    sys.exit(1 if failures else 0)