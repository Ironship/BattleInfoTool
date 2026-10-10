"""Retail action-button and tooltip paths using the shared Lua 5.1 fake game.

Run: python tests/test_spell_damage_retail.py
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
function GetLocale() return "enUS" end
comboPoints, comboMax = 6, 7
function UnitPower(_, power) return power == 4 and comboPoints or 0 end
function UnitPowerMax(_, power) return power == 4 and comboMax or 100 end
function GetComboPoints() error("Retail must read player combo power") end
function GetSpellBonusDamage() return 100000 end
function GetSpellBonusHealing() return 100000 end
function UnitAttackPower() return 100000, 0, 0 end
function UnitAttackSpeed() return 2 end
function UnitDamage() return 100000, 100000 end
SECRET = setmetatable({}, {
  __lt = function() error("compared a secret") end,
  __le = function() error("compared a secret") end,
  __add = function() error("did sums with a secret") end,
  __sub = function() error("did sums with a secret") end,
  __mul = function() error("did sums with a secret") end,
  __div = function() error("did sums with a secret") end,
  __concat = function() error("concatenated a secret") end,
  __index = function() error("indexed a secret") end,
})
function issecretvalue(v) return rawequal(v, SECRET) end
local rawType = type
function type(v) if rawequal(v, SECRET) then return "number" end return rawType(v) end
actions, overrides = {}, {}
function GetActionInfo(slot)
  local action = actions[slot]
  if action then return unpack(action) end
end
C_Spell.GetOverrideSpell = function(id) return overrides[id] or id end
C_Spell.GetSpellInfo = function() return { castTime = 3500 } end
GetSpellDescription, GetSpellInfo = nil, nil
function NewAction(prefix, index, slot)
  local button = CreateFrame("Button", prefix .. index, UIParent)
  button:SetSize(36, 36)
  button.action = slot
  return button
end
tipPost = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) tipPost[kind] = fn end }
GameTooltip.rows = {}
function GameTooltip:NumLines() return #self.rows end
function GameTooltip:GetLeftLine(index) return self.rows[index] end
function GameTooltip:AddLine(text)
  local row = self:CreateFontString()
  row:SetText(text)
  table.insert(self.rows, row)
end
function GameTooltip:ClearLines()
  self.rows = {}
  local onClear = self:GetScript("OnTooltipCleared")
  if onClear then onClear(self) end
end
function GameTooltip:GetSpell() return "Finisher", self.spellID end
function OpenSpellTooltip(id)
  GameTooltip:ClearLines()
  GameTooltip.spellID = id
  GameTooltip:AddLine("Blizzard spell title")
  GameTooltip:Show()
  tipPost[Enum.TooltipDataType.Spell](GameTooltip, { id = id })
end
"""


def load(setup=""):
    rt = namespace["LuaRuntime"](unpack_returned_tuples=True)
    rt.execute(namespace["FAKE"])
    rt.execute(RETAIL)
    if setup:
        rt.execute(setup)
    addon = rt.eval("{}")
    loader = rt.eval("function(src, name, addon) return assert(loadstring(src, '@' .. name))('SpellDamageInfo', addon) end")
    for name in ("Locale.lua", "SpellIDs.lua", "SpellCoefficients.lua", "Parser.lua", "Estimate.lua", "Core.lua"):
        loader((ROOT / "Modules/SpellDamageInfo" / name).read_text(encoding="utf-8"), name, addon)
    g = rt.globals()
    g.Fire("ADDON_LOADED", "SpellDamageInfo")
    g.Fire("PLAYER_LOGIN")
    return rt, g, addon


def finisher_rows(single=False, language="en", top=7):
    if language == "de":
        return "Finishing-Move. " + " ".join(f"{n} Punkte: {n * 100}-{n * 100 + 10} Schaden." for n in range(1, top + 1))
    if single:
        return "Finishing move. " + " ".join(f"{n} points: {n * 100} damage." for n in range(1, top + 1))
    return "Finishing move. " + " ".join(f"{n} points: {n * 100}-{n * 100 + 10} damage." for n in range(1, top + 1))


def label(addon, button):
    fs = addon._labels[button]
    return fs.text if fs and fs.shown else None


def tip_text(g):
    return [row.text for row in g.GameTooltip.rows.values() if row.text]


class RetailSpellDamageTests(unittest.TestCase):
    def test_scaled_retail_descriptions_never_add_classic_spell_or_weapon_stats(self):
        rt, g, addon = load("""
          NewAction('ActionButton', 1, 1)
          NewAction('MultiBar7Button', 1, 2)
          NewAction('MultiBar6Button', 1, 3)
          actions[1], actions[2], actions[3] = { 'spell', 100 }, { 'spell', 101 }, { 'spell', 102 }
          spellDesc[100] = 'Causes 400 Fire damage.'
          spellDesc[101] = 'Deals 850 Physical damage.'
          spellDesc[102] = 'Heals the target for 600.'
        """)
        for spell, amount, button, field in ((100, 400, g.ActionButton1, "direct"),
                                             (101, 850, g.MultiBar7Button1, "direct"),
                                             (102, 600, g.MultiBar6Button1, "heal")):
            with self.subTest(spell=spell):
                view = addon.Compute(spell)
                self.assertEqual(view[field].min, amount)
                self.assertEqual(view[field].added, 0)
                self.assertFalse(view.estimated)
                self.assertEqual(label(addon, button), str(amount))
        self.assertIsNone(addon.SpellCoefficientsFor(100))
        g.target = rt.eval("{ hostile = true }")
        addon.ReadTargetSpeed()
        self.assertIsNone(addon.ReductionPerHit(rt.eval("{ stat = 'attackpower', amount = 140 }")))

    def test_six_and_seven_point_finishers_update_buttons_and_owned_tooltip_rows(self):
        rt, g, addon = load("NewAction('ActionButton', 1, 1); actions[1] = { 'spell', 200 }")
        g.spellDesc[200] = finisher_rows()
        g.Fire("SPELL_TEXT_UPDATE", 200)
        self.assertEqual(label(addon, g.ActionButton1), "605")
        g.OpenSpellTooltip(200)
        rows = len(g.GameTooltip.rows)
        self.assertEqual(g.GameTooltip.rows[1].text, "Blizzard spell title")
        self.assertIn("current 6 combo points", g.GameTooltip.rows[rows].text)
        self.assertNotIn("attack power not included", g.GameTooltip.rows[rows].text)
        g.comboPoints = 7
        g.Fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
        self.assertEqual(label(addon, g.ActionButton1), "705")
        self.assertEqual(len(g.GameTooltip.rows), rows)
        self.assertIn("current 7 combo points", g.GameTooltip.rows[rows].text)
        g.Fire("PLAYER_TARGET_CHANGED")
        self.assertEqual(label(addon, g.ActionButton1), "705")
        self.assertEqual(len(g.GameTooltip.rows), rows)
        g.comboPoints = 0
        g.Fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
        self.assertIsNone(label(addon, g.ActionButton1))
        self.assertIn("No combo points yet", tip_text(g)[-1])
        g.comboPoints = 6
        g.Fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
        self.assertEqual(label(addon, g.ActionButton1), "605")
        self.assertEqual(len(g.GameTooltip.rows), rows)

    def test_single_amount_and_german_extended_rows_are_read_without_extrapolation(self):
        rt, g, addon = load()
        g.spellDesc[201] = finisher_rows(single=True)
        view = addon.Compute(201)
        self.assertEqual(view.direct.min, 600)
        g.GetLocale = rt.eval("function() return 'deDE' end")
        addon.DecideLangsAtLoad()
        g.spellDesc[202] = finisher_rows(language="de")
        view = addon.Compute(202)
        self.assertEqual(view.direct.min, 600)
        lines = addon.Format.TooltipLines(view, addon.Locales.de)
        self.assertIn("6 Combopunkten", lines[len(lines)][1])
        self.assertNotIn("ohne Angriffskraft", lines[len(lines)][1])
        g.spellDesc[203] = finisher_rows(top=5)
        view = addon.Compute(203)
        self.assertFalse(view.finisherAt.known)
        self.assertIsNone(view.direct)
        self.assertEqual(addon.ButtonText(view, None)[0], "?")
        self.assertIsNone(addon.Parser.ParseFinisher("1 point: 100 damage. 999999999999 points: 200 damage.", "en"))
        self.assertIsNone(addon.Parser.ParseFinisher("1 point: 100 damage every second. 2 points: 200 damage every second.", "en"))

    def test_secret_power_cap_action_and_tooltip_payloads_never_show_a_precise_finisher(self):
        rt, g, addon = load("NewAction('ActionButton', 1, 1); actions[1] = { 'spell', 200 }")
        g.spellDesc[200] = finisher_rows()
        g.Fire("SPELL_TEXT_UPDATE", 200)
        g.OpenSpellTooltip(200)
        for name in ("comboPoints", "comboMax"):
            with self.subTest(name=name):
                previous = g[name]
                g[name] = g.SECRET
                g.Fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
                self.assertEqual(label(addon, g.ActionButton1), "?")
                self.assertIn("not readable", tip_text(g)[-1])
                g[name] = previous
                g.Fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
                self.assertEqual(label(addon, g.ActionButton1), "605")
        for value in (8, -1, 6.5, float("inf"), float("nan")):
            g.comboPoints = value
            g.Fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
            self.assertEqual(label(addon, g.ActionButton1), "?")
        g.comboPoints = 6
        g.comboMax = 5
        g.Fire("UNIT_MAXPOWER", "player", "COMBO_POINTS")
        self.assertEqual(label(addon, g.ActionButton1), "?")
        g.comboMax = 7
        g.Fire("UNIT_MAXPOWER", "player", "COMBO_POINTS")
        self.assertEqual(label(addon, g.ActionButton1), "605")
        g.ActionButton1.action = g.SECRET
        addon.Refresh()
        self.assertIsNone(label(addon, g.ActionButton1))
        g.tipPost[g.Enum.TooltipDataType.Spell](g.GameTooltip, rt.eval("{ id = SECRET }"))
        self.assertIsNone(addon.Compute(g.SECRET))
        g.spellDesc[204] = g.SECRET
        self.assertIsNone(addon.Compute(204))

    def test_spell_overrides_and_spec_trait_changes_replace_cached_amounts(self):
        rt, g, addon = load("""
          NewAction('ActionButton', 1, 1)
          actions[1] = { 'macro', 300, 'spell' }
          spellDesc[300], spellDesc[301] = 'Causes 100 Fire damage.', 'Causes 250 Fire damage.'
          overrides[300] = 301
        """)
        self.assertEqual(label(addon, g.ActionButton1), "250")
        g.spellDesc[301] = "Causes 350 Fire damage."
        g.Fire("TRAIT_CONFIG_UPDATED", 10)
        self.assertEqual(label(addon, g.ActionButton1), "350")
        g.overrides[300] = None
        g.Fire("PLAYER_SPECIALIZATION_CHANGED", "player")
        self.assertEqual(label(addon, g.ActionButton1), "100")
        g.overrides[300] = g.SECRET
        addon.Refresh()
        self.assertIsNone(label(addon, g.ActionButton1))
        g.overrides[300] = 301
        addon.Refresh()
        self.assertEqual(label(addon, g.ActionButton1), "350")
        rt.execute("C_Spell.GetOverrideSpell = function() error('override unavailable') end")
        addon.Refresh()
        self.assertIsNone(label(addon, g.ActionButton1))
        rt.execute("C_Spell.GetOverrideSpell = function(id) return overrides[id] or id end")
        addon.Refresh()
        self.assertEqual(label(addon, g.ActionButton1), "350")

    def test_late_vehicle_bar_buttons_are_collected_with_their_own_action(self):
        rt, g, addon = load("spellDesc[400] = 'Causes 900 Fire damage.'; actions[77] = { 'spell', 400 }")
        rt.execute("NewAction('OverrideActionBarButton', 1, 77)")
        g.Fire("UPDATE_OVERRIDE_ACTIONBAR")
        self.assertEqual(label(addon, g.OverrideActionBarButton1), "900")
        self.assertEqual(len(addon._buttons), 1)
        g.Fire("UPDATE_VEHICLE_ACTIONBAR")
        self.assertEqual(len(addon._buttons), 1)
        g.actions[77] = rt.eval("{ 'item', 401 }")
        g.C_Item.GetItemSpell = rt.eval("function() return 'Potion', 402 end")
        g.spellDesc[402] = "Restores 500 health."
        g.Fire("ACTIONBAR_SLOT_CHANGED", 77)
        self.assertEqual(label(addon, g.OverrideActionBarButton1), "500")

    def test_healthstone_percent_uses_live_max_hp_and_refreshes_item_and_macro(self):
        rt, g, addon = load("""
          function GetLocale() return 'deDE' end
          NewAction('ActionButton', 1, 1)
          NewAction('MultiBar7Button', 1, 2)
          actions[1], actions[2] = { 'item', 5512 }, { 'macro', 5512, 'item' }
          maximumHealth = 172
          function UnitHealthMax() return maximumHealth end
          C_Item.GetItemSpell = function() return 'Healthstone', 6262 end
          spellDesc[6262] = 'Unrecognized spell description.'
          C_TooltipInfo = {GetHyperlink=function()
            return {lines={{leftText='Gesundheitsstein'},
              {leftText='Benutzen: Stellt sofort 25% Gesundheit wieder her.'}}}
          end}
        """)
        for button in (g.ActionButton1, g.MultiBar7Button1):
            self.assertEqual(label(addon, button), "43")
        self.assertEqual(addon.ComputeItem(5512).heal.min, 43)
        g.maximumHealth = 200
        g.Fire("UNIT_MAXHEALTH", "player")
        self.assertEqual(label(addon, g.ActionButton1), "50")
        g.maximumHealth = 400
        g.Fire("PLAYER_EQUIPMENT_CHANGED", 5)
        self.assertEqual(label(addon, g.MultiBar7Button1), "100")
        for maximum in (g.SECRET, None, 0, -1, float("inf"), float("nan")):
            g.maximumHealth = maximum
            g.Fire("UNIT_MAXHEALTH", "player")
            self.assertEqual(label(addon, g.ActionButton1), "25% HP")
        rt.execute("function UnitHealthMax() error('HP unavailable') end")
        addon.Refresh()
        self.assertEqual(label(addon, g.ActionButton1), "25% HP")
        rt.execute("function UnitHealthMax() return 1000 end")
        g.spellDesc[6262] = "Instantly restores 25% health. (1 Min Cooldown)"
        addon.Refresh()
        self.assertEqual(label(addon, g.ActionButton1), "250")

    def test_crimson_vial_shows_total_percent_healing_on_spell_and_macro(self):
        rt, g, addon = load("""
          function GetLocale() return 'deDE' end
          NewAction('ActionButton', 1, 1)
          NewAction('MultiBar7Button', 1, 2)
          actions[1], actions[2] = { 'spell', 185311 }, { 'macro', 185311, 'spell' }
          maximumHealth = 1000
          function UnitHealthMax() return maximumHealth end
          spellDesc[185311] = 'Trinkt ein alchemistisches Gemisch, das Euch im Verlauf von 4 Sek. um 20% Eurer maximalen Gesundheit heilt.'
        """)
        for button in (g.ActionButton1, g.MultiBar7Button1):
            self.assertEqual(label(addon, button), "200")
        view = addon.Compute(185311)
        self.assertEqual(view.hot.total, 200)
        self.assertEqual(view.hot.duration, 4)
        g.maximumHealth = 2000
        g.Fire("UNIT_MAXHEALTH", "player")
        self.assertEqual(label(addon, g.ActionButton1), "400")
        for maximum in (g.SECRET, None, 0, -1, float("inf"), float("nan")):
            g.maximumHealth = maximum
            g.Fire("UNIT_MAXHEALTH", "player")
            self.assertEqual(label(addon, g.ActionButton1), "20% HP")
        rt.execute("function UnitHealthMax() error('HP unavailable') end")
        addon.Refresh()
        self.assertEqual(label(addon, g.ActionButton1), "20% HP")
        rt.execute("function UnitHealthMax() return 1000 end")
        g.spellDesc[185311] = 'Drink an alchemical concoction that heals you for 20% of your maximum health over 4 sec.'
        g.Fire("SPELLS_CHANGED")
        self.assertEqual(label(addon, g.MultiBar7Button1), "200")
        addon.SetSetting("button", "direct")
        self.assertIsNone(label(addon, g.ActionButton1))
        g.maximumHealth = g.SECRET
        addon.Refresh()
        self.assertIsNone(label(addon, g.ActionButton1))
        addon.SetSetting("button", "off")
        self.assertIsNone(label(addon, g.ActionButton1))
        for text in ("Heals you for 20% of your missing health over 4 sec.",
                     "Heals your pet for 20% of your maximum health over 4 sec.",
                     "Heals you for 20% of your maximum health every 4 sec.",
                     "Heals you for 120% of your maximum health over 4 sec."):
            g.spellDesc[185311] = text
            g.Fire("SPELLS_CHANGED")
            self.assertIsNone(addon.Compute(185311), text)

    def test_recuperate_restoration_wording_shows_total_healing(self):
        rt, g, addon = load("""
          function GetLocale() return 'deDE' end
          NewAction('ActionButton', 1, 1)
          NewAction('MultiBar7Button', 1, 2)
          actions[1], actions[2] = { 'spell', 1231411 }, { 'macro', 1231411, 'spell' }
          maximumHealth = 1000
          function UnitHealthMax() return maximumHealth end
          spellDesc[1231411] = 'Gönnt Euch ein Päuschen, macht Euch was zu Essen und langt ordentlich zu. Stellt im Verlauf von 10 Sek. 50% Eurer maximalen Gesundheit wieder her.'
        """)
        for button in (g.ActionButton1, g.MultiBar7Button1):
            self.assertEqual(label(addon, button), "500")
        self.assertEqual(addon.Compute(1231411).hot.duration, 10)
        self.assertEqual(addon.Compute(1231411).hot.total, 500)
        g.maximumHealth = 2000
        g.Fire("UNIT_MAXHEALTH", "player")
        self.assertEqual(label(addon, g.ActionButton1), "1000")
        g.maximumHealth = g.SECRET
        g.Fire("UNIT_MAXHEALTH", "player")
        self.assertEqual(label(addon, g.MultiBar7Button1), "50% HP")
        g.maximumHealth = 1000
        for text in ("Restores 50% of your maximum health over 10 sec.",
                     "Restores 50% of maximum health over 10 sec."):
            g.spellDesc[1231411] = text
            g.Fire("SPELLS_CHANGED")
            self.assertEqual(label(addon, g.ActionButton1), "500")
        for text in ("Restores 50% of your missing health over 10 sec.",
                     "Restores 50% of maximum mana over 10 sec.",
                     "Restores 50% of maximum health every 10 sec.",
                     "Stellt im Verlauf von 10 Sek. 50% Eurer fehlenden Gesundheit wieder her."):
            g.spellDesc[1231411] = text
            g.Fire("SPELLS_CHANGED")
            self.assertIsNone(addon.Compute(1231411), text)

    def test_instant_heal_percent_parser_rejects_other_percentages(self):
        _, _, addon = load()
        for text, lang in (("Use: Instantly restores 25% health.", "en"),
                           ("Instantly restores 25% of total health.", "en"),
                           ("Instantly restores 25% of your maximum health.", "en"),
                           ("Benutzen: Stellt sofort 25% Gesundheit wieder her.", "de")):
            self.assertEqual(addon.Parser.ParseItemHeal(text, lang).healPercent, 25)
        for text in ("Restores 25% health over 10 sec.", "Instantly restores 25% mana.",
                     "Instantly restores 25% of missing health.", "Instantly restores 125% health.",
                     "Instantly restores 0% health.", "Increases healing by 25%."):
            parsed = addon.Parser.ParseItemHeal(text, "en")
            self.assertIsNone(parsed[0] if isinstance(parsed, tuple) else parsed, text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
