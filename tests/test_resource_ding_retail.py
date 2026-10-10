"""Retail ResourceDing gameplay regressions using the shared fake WoW/frame fixture.

Run: python tests/test_resource_ding_retail.py
The fake models decisions and native SetValue inputs, not live rendering or audio.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
fixture = (ROOT / "tests/test_bit.py").read_text(encoding="utf-8")
namespace = {"__file__": str(ROOT / "tests/test_bit.py")}
exec(compile(fixture.split('print("-- every module on")', 1)[0], "bit_fixture", "exec"), namespace)

RETAIL = r"""
WOW_PROJECT_MAINLINE, WOW_PROJECT_ID = 1, 1
function GetBuildInfo() return "12.0.2", "120100", "", 120100 end
powers, maxes = { [0] = 50 }, { [0] = 100 }
specID, form = 62, 1
function GetSpecialization() return 1 end
function GetSpecializationInfo() return specID end
function GetShapeshiftFormID() return form end
function UnitPower(_, power) return powers[power] or 0 end
function UnitPowerMax(_, power) return maxes[power] or 0 end
function GetComboPoints() error("Retail resources must not read target combo points") end
function UnitGUID(unit)
  if unit == "target" then error("Retail resource latch must not read target GUIDs") end
  return PLAYER_GUID
end
SECRET = setmetatable({}, {
  __lt = function() error("compared a secret") end,
  __le = function() error("compared a secret") end,
  __add = function() error("did sums with a secret") end,
  __sub = function() error("did sums with a secret") end,
  __mul = function() error("did sums with a secret") end,
  __div = function() error("did sums with a secret") end,
  __concat = function() error("concatenated a secret") end,
})
function issecretvalue(v) return rawequal(v, SECRET) end
local rawType = type
function type(v) if rawequal(v, SECRET) then return "number" end return rawType(v) end
local makeFrame = CreateFrame
function CreateFrame(kind, ...)
  local f = makeFrame(kind, ...)
  if kind == "StatusBar" then
    function f:SetValue(v) self.value = v end
    function f:SetMinMaxValues(a, b) self.min, self.max = a, b end
  end
  return f
end
target = { hostile = true }
plate = NewPlate()
pendingTimers = {}
C_Timer.After = function(delay, fn) table.insert(pendingTimers, { at = GetTime() + delay, fn = fn }) end
function FlushTimers()
  for i = #pendingTimers, 1, -1 do
    if pendingTimers[i].at <= GetTime() then
      local timer = table.remove(pendingTimers, i)
      timer.fn()
    end
  end
end
bagReads = 0
C_Item.GetItemCount = function() bagReads = bagReads + 1 return 99 end
"""


def load(class_name="ROGUE", power=4, maximum=5, current=0, setup=""):
    rt = namespace["LuaRuntime"](unpack_returned_tuples=True)
    rt.execute(namespace["FAKE"])
    rt.execute(RETAIL)
    g = rt.globals()
    g.playerClass = class_name
    g.powers[power], g.maxes[power] = current, maximum
    g.combat = True
    if setup:
        rt.execute(setup)
    addon = rt.eval("{}")
    loader = rt.eval("function(src, name, addon) return assert(loadstring(src, '@' .. name))('ResourceDing', addon) end")
    for name in ("Core.lua", "Dots.lua", "Shards.lua", "Mana.lua"):
        loader((ROOT / "Modules/ResourceDing" / name).read_text(encoding="utf-8"), name, addon)
    g.Fire("ADDON_LOADED", "ResourceDing")
    return rt, g, addon


def fire(g, event, *args):
    g.Fire(event, *args)
    g.FlushTimers()


def dings(g, sound=5274):
    return sum(play.id == sound for play in g.plays.values())


def diamonds(addon):
    return sum(bool(diamond.shown) for diamond in addon._diamonds.values())


class RetailResourceDingTests(unittest.TestCase):
    def test_shared_plate_health_bar_anchors_circles_and_shards_to_platynator(self):
        for class_name, power in (("ROGUE", 4), ("WARLOCK", 7)):
            with self.subTest(class_name=class_name):
                rt, g, addon = load(class_name, power, 5, 3)
                loader = rt.eval("function(src, addon) return assert(loadstring(src))('ResourceDing', addon) end")
                loader((ROOT / "Core/PlateLayout.lua").read_text(encoding="utf-8"), addon)
                rt.execute("""
                  Platynator = {}
                  plate.UnitFrame.healthBar:Hide()
                  display = CreateFrame('Frame', nil, plate)
                  healthWidget = CreateFrame('Frame', nil, display)
                  healthWidget.details = { kind = 'health' }
                  visibleHealthBar = CreateFrame('StatusBar', nil, healthWidget)
                  healthWidget.statusBar = visibleHealthBar
                  display.widgets = { healthWidget }
                  function plate:GetChildren() return unpack(self.children) end
                """)
                addon.RefreshMarks()
                row = addon._shardRow() if class_name == "WARLOCK" else addon._dotsRow()
                self.assertTrue(row.shown)
                self.assertTrue(g.Same(row.points[1][2], g.visibleHealthBar))
                rt.execute("healthWidget.statusBar = CreateFrame('StatusBar', nil, healthWidget)")
                addon.RefreshMarks()
                self.assertTrue(g.Same(row.points[1][2], g.healthWidget.statusBar))

    def test_supported_resources_fill_once_and_follow_player_across_targets(self):
        cases = (("ROGUE", 4, 7, 0), ("DRUID", 4, 5, 0), ("MONK", 12, 6, 269),
                 ("PALADIN", 9, 5, 0), ("WARLOCK", 7, 5, 0),
                 ("MAGE", 16, 4, 62), ("EVOKER", 19, 6, 0))
        for class_name, power, maximum, spec in cases:
            with self.subTest(class_name=class_name):
                rt, g, addon = load(class_name, power, maximum, maximum, f"specID = {spec}")
                addon.db.shards = False  # test the full-resource cue for warlocks too
                self.assertEqual(dings(g), 0, "login with a full resource must be silent")
                g.powers[power] = maximum - 1
                fire(g, "UNIT_POWER_FREQUENT", "player")
                g.powers[power] = maximum
                fire(g, "UNIT_POWER_FREQUENT", "player")
                self.assertEqual(dings(g), 1)
                for target in ("Mob-B", "Mob-A", None):
                    g.target = rt.eval("{ hostile = true }") if target else None
                    fire(g, "PLAYER_TARGET_CHANGED")
                fire(g, "UNIT_POWER_UPDATE", "player")
                self.assertEqual(dings(g), 1, "target switches never refill a player-owned resource")
                self.assertEqual(len(addon.wasFullBy), 0)

    def test_dynamic_maximum_is_not_a_fill_and_layout_uses_new_cap(self):
        rt, g, addon = load(current=4)
        g.maxes[4] = 4
        fire(g, "UNIT_POWER_UPDATE", "player")  # arrives before MAXPOWER
        self.assertEqual(dings(g), 0)
        fire(g, "UNIT_MAXPOWER", "player")
        g.powers[4] = 3
        fire(g, "UNIT_POWER_UPDATE", "player")
        g.powers[4] = 4
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 1)
        g.maxes[4] = 7
        fire(g, "UNIT_MAXPOWER", "player")
        self.assertTrue(addon._dots[7].shown)
        self.assertFalse(bool(addon._dots[8]))
        g.powers[4] = 7
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 2)
        g.SlashCmdList.RESOURCEDING("off")
        g.SlashCmdList.RESOURCEDING("on")
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 2)

    def test_specialization_and_form_switches_take_a_silent_baseline(self):
        for class_name, power, maximum, active, inactive in (
            ("MAGE", 16, 4, 62, 63), ("MONK", 12, 6, 269, 270)
        ):
            with self.subTest(class_name=class_name):
                rt, g, addon = load(class_name, power, maximum, maximum, f"specID = {active}")
                g.specID = inactive
                fire(g, "PLAYER_SPECIALIZATION_CHANGED", "player")
                self.assertFalse(addon._dotsRow().shown, "an inactive resource stays hidden even with a nonzero cap")
                g.specID = active
                fire(g, "PLAYER_SPECIALIZATION_CHANGED", "player")
                fire(g, "UNIT_POWER_UPDATE", "player")
                self.assertTrue(addon._dotsRow().shown)
                self.assertEqual(dings(g), 0)
                g.powers[power] = maximum - 1
                fire(g, "UNIT_POWER_UPDATE", "player")
                g.powers[power] = maximum
                fire(g, "UNIT_POWER_UPDATE", "player")
                self.assertEqual(dings(g), 1)
        rt, g, addon = load("DRUID", 4, 5, 5)
        g.form = 0
        fire(g, "UPDATE_SHAPESHIFT_FORM")
        self.assertFalse(addon._dotsRow().shown)
        g.form = 1
        fire(g, "UPDATE_SHAPESHIFT_FORM")
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertTrue(addon._dotsRow().shown)
        self.assertEqual(dings(g), 0)

    def test_opener_full_resource_waits_for_combat(self):
        rt, g, addon = load("PALADIN", 9, 5, 0)
        g.combat, g.powers[9] = False, 5
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 0)
        g.combat = True
        fire(g, "PLAYER_REGEN_DISABLED")
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 1)

    def test_unreadable_druid_form_hides_dots_and_recovers_without_a_late_ding(self):
        rt, g, addon = load("DRUID", 4, 5, 4)
        g.powers[4] = 5
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 1)
        for unreadable in ("form = SECRET", "GetShapeshiftFormID = function() error('form unavailable') end"):
            with self.subTest(unreadable=unreadable):
                rt.execute(unreadable)
                fire(g, "UNIT_POWER_UPDATE", "player")
                fire(g, "UPDATE_SHAPESHIFT_FORM")
                self.assertFalse(addon._dotsRow().shown, "an unreadable form must not leave stale dots")
                self.assertEqual(dings(g), 1)
                rt.execute("form = 1; GetShapeshiftFormID = function() return form end")
                fire(g, "UNIT_POWER_UPDATE", "player")
                self.assertTrue(addon._dotsRow().shown)
                self.assertEqual(dings(g), 1, "recovery takes a silent baseline")
        g.powers[4] = 4
        fire(g, "UNIT_POWER_UPDATE", "player")
        g.powers[4] = 5
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 2, "the next observed fill still dings")

    def test_modern_specialization_namespace_works_without_legacy_globals(self):
        rt, g, addon = load("MAGE", 16, 4, 4, """
          C_SpecializationInfo = {
            GetSpecialization = GetSpecialization,
            GetSpecializationInfo = GetSpecializationInfo,
          }
          GetSpecialization, GetSpecializationInfo = nil, nil
        """)
        self.assertTrue(addon._dotsRow().shown)
        g.specID = 63
        fire(g, "PLAYER_SPECIALIZATION_CHANGED", "player")
        self.assertFalse(addon._dotsRow().shown)
        g.specID = 62
        fire(g, "PLAYER_SPECIALIZATION_CHANGED", "player")
        self.assertTrue(addon._dotsRow().shown)
        self.assertEqual(dings(g), 0)
        # The modern API wins even when an old alias still exists.
        rt.execute("GetSpecializationInfo = function() error('legacy alias must not be used') end")
        addon.GetResourceState()

    def test_secret_resource_and_maximum_never_reset_a_full_latch(self):
        rt, g, addon = load(current=4)
        g.powers[4] = 5
        fire(g, "UNIT_POWER_UPDATE", "player")
        g.powers[4] = g.SECRET
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertTrue(g.Same(addon._dots[1].value, g.SECRET), "only the native bars receive secret power")
        g.maxes[4] = g.SECRET
        fire(g, "UNIT_POWER_UPDATE", "player")
        g.powers[4], g.maxes[4] = 5, 5
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 1)

    def test_retail_shards_use_power_whole_gains_and_one_sound_at_full(self):
        rt, g, addon = load("WARLOCK", 7, 5, 3)
        self.assertEqual(diamonds(addon), 3)
        self.assertFalse(addon._dotsRow().shown, "diamonds and circles share one nameplate lane")
        self.assertEqual(g.bagReads, 0)
        self.assertEqual(dings(g), 0)
        g.Advance(5)
        g.powers[7] = 3.8
        fire(g, "UNIT_POWER_UPDATE", "player", "SOUL_SHARDS")
        self.assertEqual((dings(g), diamonds(addon)), (0, 3))
        g.powers[7] = 4
        fire(g, "UNIT_POWER_UPDATE", "player", "SOUL_SHARDS")
        fire(g, "UNIT_POWER_FREQUENT", "player", "SOUL_SHARDS")
        self.assertEqual((dings(g), diamonds(addon)), (1, 4))
        g.powers[7] = 5
        fire(g, "UNIT_POWER_UPDATE", "player", "SOUL_SHARDS")
        self.assertEqual(dings(g), 2, "the last shard has one cue, not gain plus full")
        fire(g, "PLAYER_TARGET_CHANGED")
        fire(g, "BAG_UPDATE_DELAYED")
        fire(g, "UNIT_POWER_FREQUENT", "player", "SOUL_SHARDS")
        self.assertEqual(dings(g), 2)
        self.assertEqual(g.bagReads, 0)
        addon.db.shards, addon.db.shardDiamonds = False, False
        addon.RefreshMarks()
        self.assertTrue(addon._dotsRow().shown)
        self.assertFalse(addon._shardRow().shown)
        g.powers[7] = 4
        fire(g, "UNIT_POWER_UPDATE", "player", "SOUL_SHARDS")
        g.powers[7] = 5
        fire(g, "UNIT_POWER_UPDATE", "player", "SOUL_SHARDS")
        self.assertEqual(dings(g), 3, "gain sounds off retains the full-bar cue")

    def test_retail_shards_resume_after_secret_load_spec_and_combat_without_late_gain(self):
        rt, g, addon = load("WARLOCK", 7, 5, 3)
        g.Advance(5)
        g.powers[7] = g.SECRET
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertFalse(addon._shardRow().shown)
        g.powers[7] = 5
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 0, "an unseen gain does not sound late")
        g.powers[7] = 3
        fire(g, "UNIT_POWER_UPDATE", "player")
        fire(g, "PLAYER_ENTERING_WORLD")
        g.powers[7] = 4
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 0)
        g.Advance(5)
        g.powers[7] = 5
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 1)
        fire(g, "PLAYER_SPECIALIZATION_CHANGED", "player")
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 1)
        g.combat, g.powers[7] = False, 3
        fire(g, "UNIT_POWER_UPDATE", "player")
        g.powers[7] = 4
        fire(g, "UNIT_POWER_UPDATE", "player")
        g.combat = True
        fire(g, "PLAYER_REGEN_DISABLED")
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 1)
        g.powers[7] = 5
        fire(g, "UNIT_POWER_UPDATE", "player")
        self.assertEqual(dings(g), 2)

    def test_mana_secret_and_inactive_intervals_do_not_announce_old_gains(self):
        rt, g, addon = load("WARLOCK", 7, 5, 3)
        g.Advance(5)
        g.powers[0] = g.SECRET
        fire(g, "UNIT_POWER_UPDATE", "player", "MANA")
        g.powers[0] = 90
        fire(g, "UNIT_POWER_UPDATE", "player", "MANA")
        self.assertEqual(dings(g, 8960), 0)
        g.powers[0] = 50
        fire(g, "UNIT_POWER_UPDATE", "player", "MANA")
        g.maxes[0] = 0
        fire(g, "UNIT_MAXPOWER", "player", "MANA")
        g.powers[0], g.maxes[0] = 90, 100
        fire(g, "UNIT_POWER_UPDATE", "player", "MANA")
        self.assertEqual(dings(g, 8960), 0)
        g.powers[0] = 50
        fire(g, "UNIT_POWER_UPDATE", "player", "MANA")
        g.powers[0] = 90
        fire(g, "PLAYER_SPECIALIZATION_CHANGED", "player")
        self.assertEqual(dings(g, 8960), 0)
        g.powers[0] = 50
        fire(g, "UNIT_POWER_UPDATE", "player", "MANA")
        g.powers[0] = 80
        fire(g, "UNIT_POWER_UPDATE", "player", "MANA")
        self.assertEqual(dings(g, 8960), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
