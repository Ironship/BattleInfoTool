"""Focused regression suite for the RD-SECRET-GUID fix in Modules/ResourceDing/Core.lua:
a secret STRING GUID (what the WoW Forever client hands over in combat) must never index
the per-target latch table -- the client raises "cannot be indexed with secret keys" on
every touch -- and must not cost the ding.

Loads only Modules/ResourceDing/Core.lua, standalone (no BattleInfoTool core), against a
compact fake game -- the same arrangement tools/test_modules.py uses for the addon's own
suites, and how the file behaves on its own per its header. The latch table the tests
install is a strict one: it records every read and write key and raises on the secret
sentinel, so a leaked secret GUID fails loudly instead of silently corrupting the latch.

    python tests/test_resource_ding_secret_guid.py
"""
import pathlib
import sys

from lupa.lua51 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent

FAKE = r"""
-- A compact fake game for the ResourceDing standalone module (Core.lua loaded alone).
plays = {}
units = {}
comboPoints = 0
maxes = { [4] = 5 }     -- UnitPowerMax by power type (4 = combo points)
powers = {}             -- UnitPower by power type, anything but combo points
combat = false
playerClass = "ROGUE"
buildInfo = { "1.60.1", "70009", "Sep 23 2026", 16001 }  -- WoW Forever, by default
WOW_PROJECT_ID = 10002
WOW_PROJECT_MAINLINE = 10002
MAX_COMBO_POINTS = 5
Enum = { PowerType = { ComboPoints = 4 } }
SOUNDKIT = { AUCTION_WINDOW_OPEN = 5274, READY_CHECK = 8960 }
SlashCmdList = {}
C_Timer = { After = function(_, fn) fn() end }

function GetBuildInfo() return unpack(buildInfo) end
function UnitClass() return "Rogue", playerClass, 4 end
function UnitGUID(unit)
    if unit == "player" then return "Player-1-00000001" end
    if units[unit] and units[unit].guid then return units[unit].guid end
end
function UnitPower(_, powerType)
    if powerType == 4 then return comboPoints end
    return powers[powerType] or 0
end
function UnitPowerMax(_, powerType) return maxes[powerType] or 0 end
function GetComboPoints(_, _) return comboPoints end
function UnitAffectingCombat() return combat end
function PlaySound(id, channel, ...) table.insert(plays, { id = id, channel = channel }) return true end
function strlower(s) return string.lower(s) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function print(...) end

-- A frame the module registers its events on; nothing runs until a test fires one.
local allFrames = {}
function CreateFrame(kind, name, parent)
    local f = setmetatable({
        kind = kind, name = name, parent = parent, scripts = {}, events = {},
        SetScript = function(self, script, fn) self.scripts[script] = fn end,
        RegisterEvent = function(self, event) self.events[event] = true end,
        RegisterUnitEvent = function(self, event) self.events[event] = true end,
        UnregisterAllEvents = function(self) self.events = {} end,
    }, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
    table.insert(allFrames, f)
    return f
end
function Fire(event, ...)
    for _, f in ipairs(allFrames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end
"""

failures = 0


def check(label, actual, expected=True):
    global failures
    ok = actual == expected
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {label}" + ("" if ok else f"   (got {actual!r}, expected {expected!r})"))


def load(prelude=None, setup=None):
    rt = LuaRuntime(unpack_returned_tuples=True)
    rt.execute(FAKE)
    if setup:  # runs AFTER the fake globals, BEFORE the module loads (load-time decisions see it)
        rt.execute(setup)
    if prelude:
        rt.execute(prelude)
    G = rt.globals()
    addon = rt.eval("{}")
    loader = rt.eval(
        "function(src, name, BIT) local f = assert(loadstring(src, '@' .. name)); return f(name, BIT) end")
    loader((ROOT / "Modules/ResourceDing/Core.lua").read_text(encoding="utf-8"), "ResourceDing", addon)
    G.Fire("ADDON_LOADED", "ResourceDing")
    return rt, G, addon


def target(rt, guid):
    rt.execute("units['target'] = { guid = %r }" % guid)


def touches(rt, name="TOUCHES"):
    return [rt.eval(f"{name}[{i}]") for i in range(1, len(rt.globals()[name]) + 1)]


# ---------------------------------------------------------------------------------------------
# The bar, the latch, the ding -- ordinary per-target behaviour, pinned before the secret cases.

rt, G, rds = load()
G.combat = True
target(rt, "Mob-Zero-1")
G.comboPoints = 0
rds.CheckPower(False)
check("RD-SG-01 a 0/5 bar never dings", len(G.plays), 0)
check("RD-SG-02 ... and latches the real target as not full",
      rt.eval("ResourceDing.wasFullBy['Mob-Zero-1']"), False)
G.comboPoints = 5
rds.CheckPower(False)
check("RD-SG-03 5/5 dings exactly once", len(G.plays), 1)
check("RD-SG-04 ... and the latch reads full", rt.eval("ResourceDing.wasFull"), True)
rds.CheckPower(False)
check("RD-SG-05 the same full bar does not re-ding", len(G.plays), 1)
G.comboPoints = 0
rds.CheckPower(False)
check("RD-SG-06 a drop clears the latch", rt.eval("ResourceDing.wasFull"), False)
G.comboPoints = 5
rds.CheckPower(False)
check("RD-SG-07 a new fill dings again", len(G.plays), 2)
check("RD-SG-08 the ding uses the configured sound", rt.eval("plays[2].id"), 5274)

# per-target: tabbing between two full targets dings each once, and a re-latched target stays quiet
rtB, GB, rdsB = load()
GB.combat = True
GB.comboPoints = 5
target(rtB, "Mob-A-1")
rdsB.CheckPower(False)
target(rtB, "Mob-B-2")
rdsB.CheckPower(False)
target(rtB, "Mob-A-1")
rdsB.CheckPower(False)
check("RD-SG-09 each full target dings once (1+1)", len(GB.plays), 2)
check("RD-SG-10 a full target tabbed back to stays silent",
      rtB.eval("ResourceDing.wasFullBy['Mob-A-1']"), True)

# a silent reset (CheckPower(true), as ResetPowerState uses) must not play anything
rtC, GC, rdsC = load()
GC.combat = True
GC.comboPoints = 5
target(rtC, "Mob-Silent-1")
rdsC.CheckPower(False)
rdsC.ResetPowerState()
check("RD-SG-11 a silent reset plays nothing", len(GC.plays), 1)
rdsC.CheckPower(False)
check("RD-SG-12 ... and the latch is kept (no re-ding)", len(GC.plays), 1)

# an unknown count (the client kept the number to itself) says nothing about full or not
rtD, GD, rdsD = load(prelude="""
SECRET_CP = {}
function issecretvalue(v) return v == SECRET_CP end
""")
GD.combat = True
target(rtD, "Mob-Unknown-1")
GD.comboPoints = GD.SECRET_CP
rdsD.CheckPower(False)
check("RD-SG-13 a secret count is unknown, not full", len(GD.plays), 0)
rtD.execute("ResourceDing.wasFull = true")
rdsD.CheckPower(False)
check("RD-SG-14 ... and leaves the latch exactly as it was", rtD.eval("ResourceDing.wasFull"), True)

# a maximum of zero is not a full bar (player-owned resource, Retail client)
rtE, GE, rdsE = load(setup="buildInfo = { '12.0.2', '120100', 'Sep 2026', 120100 }")  # not Forever, not Classic
GE.playerClass = "WARLOCK"
GE.combat = True
GE.maxes = rtE.eval("{ [7] = 0 }")
GE.powers = rtE.eval("{ [7] = 0 }")
rdsE.CheckPower(False)
check("RD-SG-15 a maximum of zero never dings", len(GE.plays), 0)
check("RD-SG-16 ... and the latch reads not full", rtE.eval("ResourceDing.wasFull"), False)

# player-owned resources keep the plain latch: full dings, a drop resets it, full dings again
rtF, GF, rdsF = load(setup="buildInfo = { '12.0.2', '120100', 'Sep 2026', 120100 }")
GF.playerClass = "WARLOCK"
GF.combat = True
GF.maxes = rtF.eval("{ [7] = 100 }")
GF.powers = rtF.eval("{ [7] = 0 }")
rdsF.CheckPower(False)
GF.powers = rtF.eval("{ [7] = 100 }")
rdsF.CheckPower(False)
check("RD-SG-17 a player-owned bar dings at full", len(GF.plays), 1)
GF.powers = rtF.eval("{ [7] = 0 }")
rdsF.CheckPower(False)
GF.powers = rtF.eval("{ [7] = 100 }")
rdsF.CheckPower(False)
check("RD-SG-18 ... and again after a drop (plain latch resets)", len(GF.plays), 2)

# combat-only: out of combat the ding is held back WITHOUT latching (the rogue opener)
rtG, GG, rdsG = load()
GG.comboPoints = 5
target(rtG, "Mob-Opener-1")
GG.combat = False
rdsG.CheckPower(False)
check("RD-SG-19 combat-only holds the ding out of combat", len(GG.plays), 0)
check("RD-SG-20 ... without latching the bar", rtG.eval("ResourceDing.wasFull"), False)
GG.combat = True
rdsG.CheckPower(False)
check("RD-SG-21 ... so combat with the bar still full dings", len(GG.plays), 1)
rtH, GH, rdsH = load()
rtH.execute("ResourceDing.db.combatOnly = false")
GH.comboPoints = 5
target(rtH, "Mob-Off-1")
GH.combat = False
rdsH.CheckPower(False)
check("RD-SG-22 with combatOnly off the ding plays out of combat", len(GH.plays), 1)

# Class behaviour: on Classic/Forever the cat druid's points sit on the target, and when the
# client reports no maximum the count comes from GetComboPoints, up to MAX_COMBO_POINTS.
rtI, GI, rdsI = load()
GI.playerClass = "DRUID"
GI.combat = True
GI.maxes = rtI.eval("{ [4] = 0 }")
GI.comboPoints = 5
target(rtI, "Mob-Druid-1")
rdsI.CheckPower(False)
check("RD-SG-23 classic target combo points count with a zero maximum", len(GI.plays), 1)
check("RD-SG-24 ... and read as full", rtI.eval("ResourceDing.wasFull"), True)

# ---------------------------------------------------------------------------------------------
# The regression: a secret STRING GUID (the forever client's own shape, the 8241 errors).

rtJ, GJ, rdsJ = load(prelude="""
SECRET = "SECRET-GUID-SENTINEL-8241"
function issecretvalue(v) return v == SECRET end
TOUCHES = {}
STRICT = setmetatable({}, {
  __index = function(t, k)
    table.insert(TOUCHES, "read:" .. tostring(k))
    if rawequal(k, SECRET) then error("attempted to index a table that cannot be indexed with secret keys") end
    return rawget(t, k)
  end,
  __newindex = function(t, k, v)
    table.insert(TOUCHES, "write:" .. tostring(k))
    if rawequal(k, SECRET) then error("attempted to index a table that cannot be indexed with secret keys") end
    rawset(t, k, v)
  end })
""")
GJ.combat = True
rtJ.execute("units['target'] = { guid = SECRET }")
rtJ.execute("ResourceDing.wasFullBy = STRICT")
GJ.comboPoints = 5
try:
    rdsJ.CheckPower(False)
    raised = None
except Exception as e:
    raised = str(e)
check("RD-SG-25 a secret string GUID never indexes the latch", raised, None)
check("RD-SG-26 ... and the full bar still dings once", len(GJ.plays), 1)
check("RD-SG-27 ... with the configured sound", rtJ.eval("plays[1] and plays[1].id"), 5274)
check("RD-SG-28 no secret key reached the latch, read or write", touches(rtJ), [])
check("RD-SG-29 the latch still holds plain state", rtJ.eval("ResourceDing.wasFull"), True)

# detector absent: the probe stands in, a real GUID latches per target
rtK, GK, rdsK = load()
GK.combat = True
GK.comboPoints = 5
target(rtK, "Mob-Real-1")
rdsK.CheckPower(False)
rdsK.CheckPower(False)
check("RD-SG-30 without the detector a real GUID dings once", len(GK.plays), 1)
target(rtK, "Mob-Real-2")
rdsK.CheckPower(False)
check("RD-SG-31 ... and a new target dings again", len(GK.plays), 2)

# detector throws (pcall inside usableGuid): the probe stands in, no error to the caller
rtL, GL, rdsL = load(prelude="""
function issecretvalue(v) if type(v) == "string" then error("boom") end return false end
""")
GL.combat = True
GL.comboPoints = 5
target(rtL, "Mob-Throw-1")
rdsL.CheckPower(False)
check("RD-SG-32 a throwing detector falls back to the probe", len(GL.plays), 1)
rdsL.CheckPower(False)
check("RD-SG-33 ... and the per-target latch still holds", len(GL.plays), 1)

print("failed:", failures)
sys.exit(1 if failures else 0)