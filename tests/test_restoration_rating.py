"""UsefulPlatesAndTooltips StatsInfo: the druid Restoration (healer) item rating - intended behaviour.

The healer's rating is a transparent starter heuristic, UsefulPlatesAndTooltips's own design choice and
NOT a simulator result (ForeverSim does not simulate healing): a weighted score of
1 x +Healing (ITEM_MOD_SPELL_HEALING_DONE_SHORT), 1 x Spell Power (ITEM_MOD_SPELL_POWER_SHORT,
the same bonus), 0.5 x Intellect, 0.5 x Spirit and 2 x MP5 (ITEM_MOD_MANA_REGENERATION_SHORT).
Damage-only spell stats (ITEM_MOD_SPELL_DAMAGE_DONE_SHORT), school spell damage, the physical
stats and a weapon's damage per second do not improve this score. A line it makes is marked
"(approx.)": an approximate healer ITEM score, not an actual healing gain. The model's data and
provenance live in tools/data/healer_weights.json, generated into Weights.lua by
tools/make_weights.py.

    python tests/test_restoration_rating.py

The fake game and the loader are tests/test_bit.py's own, so the real modules load from the
.toc exactly as they do there.
"""
import pathlib
import sys

from lupa.lua51 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent

FAKE = r"""chat = {}
local allFrames = {}
local methods = {}
local function mock(kind, parent)
    local o = { kind = kind, parent = parent, scripts = {}, events = {}, shown = true, level = 1, strata = "MEDIUM",
        points = {}, children = {} }
    if type(parent) == "table" and parent.children then table.insert(parent.children, o) end
    table.insert(allFrames, o)
    return setmetatable(o, { __index = function(t, k)
        if methods[k] then return methods[k] end
        if type(k) == "string" and k:match("^%u") then return function() end end
    end })
end
FakeMock, AllFrames = mock, allFrames
function methods.SetScript(self, name, fn) self.scripts[name] = fn end
function methods.GetScript(self, name) return self.scripts[name] end
function methods.HookScript(self, name, fn) local old = self.scripts[name]
    self.scripts[name] = function(...) if old then old(...) end fn(...) end end
function methods.RegisterEvent(self, e) self.events[e] = true end
function methods.RegisterUnitEvent(self, e) self.events[e] = true end
function methods.UnregisterEvent(self, e) self.events[e] = nil end
function methods.UnregisterAllEvents(self) self.events = {} end
function methods.IsEventRegistered(self, e) return self.events[e] == true end
function methods.IsShown(self) return self.shown end
function methods.IsVisible(self) local f = self
    while f do if f.shown == false then return false end f = f.parent end return true end
-- As in the game: a frame coming into view or going out of it runs OnShow / OnHide, and so does
-- every shown frame inside it.
local function reach(f, script)
    if f.scripts[script] then f.scripts[script](f) end
    for _, c in ipairs(f.children) do if c.shown then reach(c, script) end end
end
function methods.Show(self) local was = self:IsVisible(); self.shown = true
    if not was and self:IsVisible() then reach(self, "OnShow") end end
function methods.Hide(self) local was = self:IsVisible(); self.shown = false
    if was then reach(self, "OnHide") end end
function methods.SetShown(self, v) if v then self:Show() else self:Hide() end end
function methods.SetParent(self, p)
    local old = self.parent
    if type(old) == "table" and old.children then
        for i, c in ipairs(old.children) do if c == self then table.remove(old.children, i) break end end
    end
    self.parent = p
    if type(p) == "table" and p.children then table.insert(p.children, self) end
end
function methods.GetParent(self) return self.parent end
function methods.SetPoint(self, ...) table.insert(self.points, { ... }) end
function methods.ClearAllPoints(self) self.points = {} end
function methods.SetText(self, t) self.text = t end
function methods.GetText(self) return self.text end
function methods.SetTexture(self, t) self.texture = t end
function methods.GetTexture(self) return self.texture end
function methods.SetChecked(self, v) self.checked = v and true or false end
function methods.GetChecked(self) return self.checked end
function methods.SetSize(self, w, h) self.width, self.height = w, h end
function methods.SetWidth(self, w) self.width = w end
function methods.SetHeight(self, h) self.height = h end
function methods.GetWidth(self) return self.width or 100 end
function methods.GetHeight(self) return self.height or 20 end
function methods.GetStringWidth(self) return #(self.text or "") * 6 end
function methods.SetFrameLevel(self, v) self.level = v end
function methods.GetFrameLevel(self) return self.level end
function methods.SetFrameStrata(self, v) self.strata = v end
function methods.GetFrameStrata(self) return self.strata end
function methods.GetName(self) return self.name end
for _, m in ipairs({ "CreateTexture", "CreateFontString", "CreateAnimationGroup", "CreateAnimation", "CreateMaskTexture" }) do
    methods[m] = function(self) return mock(m, self) end
end
function methods.GetStatusBarTexture(self) self._bar = self._bar or mock("bar", self); return self._bar end
function methods.GetThumbTexture(self) self._thumb = self._thumb or mock("thumb", self); return self._thumb end
function methods.GetMinMaxValues(self) return 0, 100 end

function CreateFrame(kind, name, parent, template)
    local f = mock(kind, parent)
    f.name, f.template = name, template
    -- templates that give a check button its label
    if type(template) == "string" and template:find("CheckButton") then f.Text = mock("text", f) end
    if name then _G[name] = f end
    return f
end
UIParent = mock("UIParent")
GameTooltip = mock("GameTooltip")
ItemRefTooltip = mock("ItemRefTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(chat, m) end }
function print(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
    table.insert(chat, table.concat(t, " ")) end
UISpecialFrames = {}
SlashCmdList = {}
SOUNDKIT = { AUCTION_WINDOW_OPEN = 5274, READY_CHECK = 8960 }
Enum = { PowerType = { ComboPoints = 4 }, TooltipDataType = { Spell = 1, Item = 0, PetAction = 2 } }
now = 1000
function GetTime() return now end
function Advance(dt) now = now + (dt or 0) end
plays = {}
function PlaySound(id, channel, ...) table.insert(plays, { id = id, channel = channel }) return true end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
GameFontNormalSmall = {}
spellDesc = {}
comboPoints = 0
units = {}
plates = {}
function GetBuildInfo() return "1.60.1", "70009", "Sep 23 2026", 16001 end
function GetLocale() return "deDE" end
function GetCVar() return nil end
function UnitName() return "Tester" end
playerClass = "WARLOCK"
function UnitClass() return "Hexenmeister", playerClass, 9 end
function UnitRace() return "Mensch", "Human" end
function UnitLevel() return 20 end
combat = false
function UnitAffectingCombat() return combat end
function InCombatLockdown() return combat end
function UnitPower(unit, powerType) if powerType == 4 then return comboPoints end if units[unit] and units[unit].power ~= nil then return units[unit].power end return 0 end
function UnitPowerMax(unit, powerType) if powerType == 4 then return 5 end return 100 end
function UnitHealth(u) if units[u] then return units[u].health end end
function UnitHealthMax(u) if units[u] and units[u].max then return units[u].max end return 500 end
function GetComboPoints(u, t) return comboPoints end
function UnitStat(_, i) return 20, 22, 2, 0 end
function UnitArmor() return 100, 120 end
function GetShapeshiftFormID() return nil end
function strlower(s) return string.lower(s) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
-- A hook on a global the game has wraps it, as the client does, so a call from
-- Blizzard's code (or a test's model of it) runs the original and then the hook;
-- hooks[name] still names the hook itself, for a test that drives it by hand.
-- A hook on a global that does not exist, and a hook on a method, is recorded only.
hooks = {}
function hooksecurefunc(a, b, c)
    if type(a) == "string" then
        local original = _G[a]
        if type(original) == "function" then
            hooks[a] = b
            _G[a] = function(...) original(...) return b(...) end
        else
            hooks[a] = b
        end
    else
        a.hooks = a.hooks or {}
        a.hooks[b] = c
    end
end
function ActionButton_UpdateRangeIndicator() end
usableActions, noManaActions = {}, {}
C_ActionBar = { IsUsableAction = function(a) return usableActions[a] == true, noManaActions[a] == true end }
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
Settings = { RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end,
    RegisterAddOnCategory = function() end }

-- The standalone addons this character has enabled, by name.
standalone = {}
C_AddOns = {
    IsAddOnLoaded = function(name) return loaded[name] == true end,
    -- As the client answers: for this character when asked by its GUID; asked by anything else (a
    -- name, which Forever does not take, or nothing), for the account, where an addon enabled on
    -- another character is "some characters" (1).
    GetAddOnEnableState = function(name, character)
        if character == PLAYER_GUID then return standalone[name] and 2 or 0 end
        return (standalone[name] or otherCharacters[name]) and 1 or 0
    end,
    IsAddOnLoadable = function(name, character)
        if character == PLAYER_GUID then return standalone[name] == true, standalone[name] and "" or "DISABLED" end
        return (standalone[name] or otherCharacters[name]) == true, ""
    end,
}
PLAYER_GUID = "Player-1-00000001"
function UnitGUID(unit) if unit == "player" then return PLAYER_GUID end if units[unit] and units[unit].guid then return units[unit].guid end end
otherCharacters = { SpellDamageInfo = true, ResourceDing = true }
loaded = {}

-- Spells, targets and nameplates for the range mark.
spellNames = { [686] = "Schattenblitz", [172] = "Verderbnis", [1752] = "Finsterer Stoß" }
inRange = {} -- name -> true/false/nil
C_Spell = {
    GetSpellName = function(id) return spellNames[id] end,
    IsSpellInRange = function(name, unit) return inRange[name] end,
    GetSpellDescription = function(id) return spellDesc[id] end,
    GetSpellInfo = function() return nil end,
}
target = nil -- { hostile = bool }
function UnitExists(u) if u == "target" then return target ~= nil end if units[u] then return true end return false end
function UnitIsDeadOrGhost(u) local un = u and units[u] if un and un.dead then return true end if u == "target" and units["target"] and units["target"].dead then return true end return false end
function UnitCanAttack(_, u) return u == "target" and target ~= nil and target.hostile end
plate = nil
C_NamePlate = { GetNamePlateForUnit = function(u) if u == "target" or u == "nameplate1" then return plate end end }
-- The target frame as Forever builds it: the DoTInfo module looks for its portrait and health bar there.
TargetFrame = mock("TargetFrame")
TargetFrame.TargetFrameContainer = mock("container", TargetFrame)
TargetFrame.TargetFrameContainer.Portrait = mock("portrait", TargetFrame.TargetFrameContainer)
TargetFrame.TargetFrameContent = mock("content", TargetFrame)
TargetFrame.TargetFrameContent.TargetFrameContentMain = mock("main", TargetFrame.TargetFrameContent)
TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer = mock("bars", TargetFrame.TargetFrameContent.TargetFrameContentMain)
TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar = mock("healthbar",
    TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer)

-- Items for StatsInfo: links -> stats, equip location; the worn items by slot.
itemStats, itemLoc, worn = {}, {}, {}
C_Item = {
    GetItemStats = function(link) return itemStats[link] end,
    GetItemInfoInstant = function(link) return 1, "Armor", "Cloth", itemLoc[link] end,
}
function GetInventoryItemLink(_, slot) return worn[slot] end
_G.ITEM_MOD_AGILITY_SHORT = "Beweglichkeit"
_G.ITEM_MOD_STAMINA_SHORT = "Ausdauer"
_G.ITEM_MOD_STRENGTH_SHORT = "Stärke"

function Same(a, b) return rawequal(a, b) end
function NewPlate()
    local p = mock("plate")
    p.UnitFrame = { healthBar = mock("plateBar", p) }
    return p
end

function Fire(event, ...)
    for _, f in ipairs(allFrames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end
function Tick(seconds)
    for _, f in ipairs(allFrames) do
        if f.scripts.OnUpdate and f:IsVisible() then f.scripts.OnUpdate(f, seconds) end
    end
end
"""

failures = 0


def check(label, actual, expected=True):
    global failures
    ok = actual == expected
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {label}" + ("" if ok else f"   (got {actual!r}, expected {expected!r})"))


def load(saved=None, standalone=()):
    rt = LuaRuntime(unpack_returned_tuples=True)
    rt.execute(FAKE)
    G = rt.globals()
    for name in standalone:
        G.standalone[name] = True
    if saved:
        rt.execute(saved)
    BIT = rt.eval("{}")
    loader = rt.eval("function(src, name, BIT) local f = assert(loadstring(src, '@' .. name)); return f('UsefulPlatesAndTooltips', BIT) end")
    toc = (ROOT / "UsefulPlatesAndTooltips.toc").read_text(encoding="utf-8").splitlines()
    files = [l.strip() for l in toc if l.strip() and not l.startswith("#")]
    for f in files:
        loader((ROOT / f.replace("\\", "/")).read_text(encoding="utf-8"), f, BIT)
    return rt, G, BIT, files


# ---------------------------------------------------------------------------------------------
print("-- Restoration: the weights carry the druid's healer spec")
rt, G, BIT, files = load()
G.Fire("ADDON_LOADED", "UsefulPlatesAndTooltips")
G.Fire("PLAYER_LOGIN")
si = BIT.modules["StatsInfo"]
si.settings.detail = "full"
W = si.SPECS

resto_spec = None
for x in W.DRUID.values():
    if x.name == "Restoration":
        resto_spec = x
check("a druid Restoration spec, after the existing three, with role healing",
      (resto_spec is not None, resto_spec.role if resto_spec else None,
       [x.name for x in W.DRUID.values()]),
      (True, "healing", ["Feral (Bear)", "Feral (Cat)", "Balance", "Restoration"]))
hing = resto_spec.healing if resto_spec else None
check("its healing measure: the reference stat and the approximate marker",
      (hing.reference if hing else None, hing.approximate if hing else None), ("Healing", True))
check("a weapon's damage per second is worth nothing to a healer (no weapon), in any hand",
      (hing.mainHand if hing else None, hing.offHand if hing else None, hing.ranged if hing else None),
      (0, 0, 0))
check("the heuristic weights: +Healing, Spell Power, Intellect, Spirit, MP5",
      {k: v for k, v in (hing.weights if hing else {}).items()},
      {"ITEM_MOD_SPELL_HEALING_DONE_SHORT": 1.0, "ITEM_MOD_SPELL_POWER_SHORT": 1.0,
       "ITEM_MOD_INTELLECT_SHORT": 0.5, "ITEM_MOD_SPIRIT_SHORT": 0.5,
       "ITEM_MOD_MANA_REGENERATION_SHORT": 2.0})
check("the other healing classes carry a healer spec too, at the end of their list",
      ([x.role for c in ("PRIEST", "SHAMAN", "PALADIN") for x in W[c].values()],
       W.DRUID[1].role, W.DRUID[2].role, W.DRUID[3].role),
      (["damage", "damage", "healing", "damage", "damage", "healing", "tank", "damage", "healing"],
       "tank", "damage", "damage"))
def healer_measure(spec):
    m = spec.healing if spec else None
    return (m and m.reference, m and m.approximate, m and dict(m.weights.items()))
check("each healer's measure is the same heuristic (reference, approx. marker and weights)",
      (healer_measure(W.PRIEST[3]), healer_measure(W.PALADIN[3]), healer_measure(W.SHAMAN[3])),
      (healer_measure(W.DRUID[4]),) * 3)
check("  with each talent tree's own icon (Holy priest, Holy paladin, Restoration shaman)",
      (W.PRIEST[3].icon, W.PALADIN[3].icon, W.SHAMAN[3].icon),
      ("Interface\\Icons\\Spell_Holy_HolyNova", "Interface\\Icons\\Spell_Holy_HolyBolt",
       "Interface\\Icons\\Spell_Nature_HealingWaveGreater"))
check("the source distinguishes the simulator's weights from the heuristic",
      (si.WEIGHTS_SOURCE and si.WEIGHTS_SOURCE.find("ForeverSim") >= 0,
       si.WEIGHTS_SOURCE and si.WEIGHTS_SOURCE.find("heuristic") >= 0,
       si.WEIGHTS_SOURCE and si.WEIGHTS_SOURCE.find("not simulated") >= 0), (True, True, True))

# ---------------------------------------------------------------------------------------------
print("-- Restoration: the spec rates a healing item as a percentage (approx.)")
def healing_row(ratings):
    for x in ratings.values():
        if x.spec.name == "Restoration":
            return x
    return None

G.playerClass = "DRUID"
G.ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Healing"
G.ITEM_MOD_SPELL_POWER_SHORT = "Spell Power"
G.ITEM_MOD_INTELLECT_SHORT = "Intellect"
G.ITEM_MOD_SPIRIT_SHORT = "Spirit"
G.ITEM_MOD_MANA_REGENERATION_SHORT = "MP5"
G.ITEM_MOD_STRENGTH_SHORT = "Strength"
G.ITEM_MOD_AGILITY_SHORT = "Agility"
G.ITEM_MOD_STAMINA_SHORT = "Stamina"
G.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "Damage per Second"
G.ITEM_MOD_NATURE_DAMAGE_DONE_SHORT = "Nature Damage"
G.ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "Spell Damage"
G.itemStats["mend+10"] = rt.eval('{ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 10 }')
G.itemStats["mend+12"] = rt.eval('{ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 12 }')
G.itemLoc["mend+10"], G.itemLoc["mend+12"] = "INVTYPE_CHEST", "INVTYPE_CHEST"
r = healing_row(si.SpecRatings("mend+12", rt.table_from(["mend+10"])))
check("a healing item against a healing item: one healing part, a percent, marked approx",
      (r.parts[1].kind, round(r.parts[1].percent, 2), r.parts[1].reference, r.parts[1].approx),
      ("healing", 20.0, "Healing", True))
check("the other three druid specs keep their own measures (tank two, damage one)",
      (len(healing_row(si.SpecRatings("mend+12", rt.table_from(["mend+10"]))).parts),
       [x.spec.name for x in si.SpecRatings("mend+12", rt.table_from(["mend+10"])).values()]),
      (1, ["Feral (Bear)", "Feral (Cat)", "Balance", "Restoration"]))

# ---------------------------------------------------------------------------------------------
print("-- Restoration: each heuristic stat improves the score on its own")
for key, worn, new, expected in (
        ("ITEM_MOD_SPELL_HEALING_DONE_SHORT", 10, 12, 20.0),
        ("ITEM_MOD_INTELLECT_SHORT", 10, 12, 20.0),
        ("ITEM_MOD_SPIRIT_SHORT", 10, 12, 20.0),
        ("ITEM_MOD_MANA_REGENERATION_SHORT", 2, 4, 100.0),
        ("ITEM_MOD_SPELL_POWER_SHORT", 10, 15, 50.0)):
    G.itemStats["w"] = rt.eval("{" + key + " = " + str(worn) + "}")
    G.itemStats["n"] = rt.eval("{" + key + " = " + str(new) + "}")
    G.itemLoc["w"], G.itemLoc["n"] = "INVTYPE_CHEST", "INVTYPE_CHEST"
    r = healing_row(si.SpecRatings("n", rt.table_from(["w"])))
    check(f"  {key}: {new} against {worn} at its weight",
          None if r is None else round(r.parts[1].percent, 2), expected)

# ---------------------------------------------------------------------------------------------
print("-- Restoration: what does NOT improve the healer score")
def resto_percent(r):
    x = healing_row(r)
    return None if x is None else round(x.parts[1].percent, 2)

# damage-only spell stats and school spell damage: worth nothing
G.itemStats["sch"] = rt.eval('{ ITEM_MOD_NATURE_DAMAGE_DONE_SHORT = 20 }')
G.itemStats["spd"] = rt.eval('{ ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 20 }')
G.itemLoc["sch"], G.itemLoc["spd"] = "INVTYPE_CHEST", "INVTYPE_CHEST"
check("a school's spell damage and generic spell damage alone: score 0 against 0, so no change",
      (resto_percent(si.SpecRatings("sch", rt.table_from([]))),
       resto_percent(si.SpecRatings("spd", rt.table_from([])))), (0, 0))
# the +N Spell Damage and Healing line: assumed to come under the Healing key, its damage key ignored
G.itemStats["sdmix"] = rt.eval('{ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 10, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 10 }')
G.itemLoc["sdmix"] = "INVTYPE_CHEST"
check("a +10 SD and H item against +10 Healing: counted once, through the healing key (no doubling)",
      resto_percent(si.SpecRatings("sdmix", rt.table_from(["mend+10"]))), 0.0)
# spell power is the same bonus as healing: 10 of one against 10 of the other
G.itemStats["sp10"] = rt.eval('{ ITEM_MOD_SPELL_POWER_SHORT = 10 }')
G.itemLoc["sp10"] = "INVTYPE_CHEST"
check("Spell Power is the same bonus as +Healing (10 SP against 10 Healing: no change)",
      resto_percent(si.SpecRatings("sp10", rt.table_from(["mend+10"]))), 0.0)
# the physical stats and a weapon's damage per second: worth nothing
G.itemStats["phys"] = rt.eval('{ ITEM_MOD_STRENGTH_SHORT = 50, ITEM_MOD_AGILITY_SHORT = 50, ITEM_MOD_STAMINA_SHORT = 50 }')
G.itemStats["dpsstaff"] = rt.eval('{ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 10, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 }')
G.itemLoc["phys"], G.itemLoc["dpsstaff"] = "INVTYPE_CHEST", "INVTYPE_CHEST"
check("physical stats alone: score 0 against 0, no change (and armor/weapon DPS never enter)",
      (resto_percent(si.SpecRatings("phys", rt.table_from([]))),
       resto_percent(si.SpecRatings("dpsstaff", rt.table_from(["mend+10"])))), (0, 0))

# ---------------------------------------------------------------------------------------------
print("-- Restoration: the tooltip line, marked approximate, in words and with icons")
si.settings.specs = True
si.settings.icons = False
G.worn[5] = "mend+10"
lines = [l[1] for l in si.TooltipLines("mend+12").values()]
check("in words: a line per spec; Restoration reads a better healer score, marked (approx.)",
      (any("  Restoration: |cff4dff4d20% better healer score (approx.)|r" in l for l in lines),
       any("  Feral (Cat):" in l for l in lines)), (True, False))
si.settings.icons = True
lines = [l[1] for l in si.TooltipLines("mend+12").values()]
check("with icons: one icon per spec line, Restoration's own (Spell_Nature_HealingTouch) and the marker",
      (any("Spell_Nature_HealingTouch" in l and "Restoration: " in l and "(approx.)" in l for l in lines),
       "20% better healer score" in " ".join(lines)), (True, True))

# negative: a physical swap that loses Spirit is worse for the healer even when Feral (Cat) improves
G.itemStats["str-club"] = rt.eval('{ ITEM_MOD_STRENGTH_SHORT = 30, ITEM_MOD_AGILITY_SHORT = 10 }')
G.itemLoc["str-club"] = "INVTYPE_CHEST"
si.settings.icons = False
lines = [l[1] for l in si.TooltipLines("str-club").values()]
check("a physical swap losing Spirit: 'worse healer score (approx.)' in red, Feral (Cat) still improves",
      (any("Restoration: |cffff5959100% worse healer score (approx.)|r" in l for l in lines),
       any("Feral (Cat): |cff4dff4d>300% better dmg spec|r" in l for l in lines)), (True, True))

# capped: an empty slot of a +Healing item caps like the other specs, with the marker
G.worn[5] = None
lines = [l[1] for l in si.TooltipLines("mend+12").values()]
check("an empty slot: '>300% better healer score (approx.)', the cap like the rest",
      any("Restoration: |cff4dff4d>300% better healer score (approx.)|r" in l for l in lines), True)

# no effect: an item the healer scores the same for is left out, as for the other specs
G.itemStats["sch-ring"] = rt.eval('{ ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = 20 }')
G.itemLoc["sch-ring"] = "INVTYPE_FINGER"
G.worn[11] = None
lines = [l[1] for l in si.TooltipLines("sch-ring").values()]
check("no effect (shadow damage, score 0 against 0): no Restoration line, no ratings at all",
      (any("Restoration" in l for l in lines), any("Divider" in l or "Rating" in l for l in lines)),
      (False, False))
G.worn[5], G.worn[11] = None, None

# ---------------------------------------------------------------------------------------------
print("-- Restoration: an enchant on the item joins the healer's score (the tooltip's words)")
rt.execute("""
tooltopsE, tooltopCallsE = {}, 0
function TooltopE(link, ...)
  local lines = { ... }
  local t = {}
  for i = 1, #lines do t[i] = { leftText = lines[i] } end
  tooltopsE[link] = { lines = t }
end
function GetHyperlinkE(link)
  tooltopCallsE = tooltopCallsE + 1
  return tooltopsE[link]
end
""")
G.C_TooltipInfo = rt.eval("{}")
G.C_TooltipInfo.GetHyperlink = G.GetHyperlinkE
G.ITEM_ENCHANTMENT = "Enchanted:"
full = "|cnIQ2:|Hitem:2400:17:::::::4:1484::::::::Player-1-00000001:|h[Healer Vest]|h|r"
stripped = full.replace("|Hitem:2400:17", "|Hitem:2400:", 1)
G.itemStats[full] = rt.eval("{ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 5 }")  # the client leaves the enchant out
G.itemStats[stripped] = rt.eval("{}")
G.itemLoc[full] = "INVTYPE_CHEST"
G.TooltopE(full, "Enchanted: Intellect +4")
G.itemStats["w-mend5"] = rt.eval('{ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 5 }')
G.itemLoc["w-mend5"] = "INVTYPE_CHEST"
G.worn[5] = "w-mend5"
lines = [l[1] for l in si.TooltipLines(full).values()]
check("the enchant's Intellect +4 is part of the healer's score (5 + 2 against 5: +40%)",
      (any("Restoration: |cff4dff4d40% better healer score (approx.)|r" in l for l in lines),
       any("Intellect" in l for l in lines)), (True, True))

# ---------------------------------------------------------------------------------------------
print("-- Restoration: the user's weapon (+6 Intellect, +12 Spirit) is a better healer weapon")
G.itemStats["staff-new"] = rt.eval('{ ITEM_MOD_INTELLECT_SHORT = 6, ITEM_MOD_SPIRIT_SHORT = 12, '
                                   'ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 }')
G.itemStats["staff-worn"] = rt.eval('{ ITEM_MOD_INTELLECT_SHORT = 4, ITEM_MOD_SPIRIT_SHORT = 6 }')
G.itemLoc["staff-new"], G.itemLoc["staff-worn"] = "INVTYPE_2HWEAPON", "INVTYPE_2HWEAPON"
G.worn[16], G.worn[17] = "staff-worn", None
si.settings.icons = False
c = si.Compare("staff-new")
r = healing_row(si.SpecRatings("staff-new", c[1].against, c[1].slots, c[1].offHand))
check("the two-hander compares with the worn one: 9 points against 5, its DPS counts for nothing",
      (round(r.parts[1].percent, 2), r.parts[1].approx), (80.0, True))
lines = [l[1] for l in si.TooltipLines("staff-new").values()]
check("and the tooltip says so, '(approx.)' and all",
      any("Restoration: |cff4dff4d80% better healer score (approx.)|r" in l for l in lines), True)

# ---------------------------------------------------------------------------------------------
print("-- Restoration: paired slots and the empty-slot cap, and secret stats stay out")
G.itemStats["ring-heal8"] = rt.eval('{ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 8 }')
G.itemStats["ring-heal10"] = rt.eval('{ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 10 }')
G.itemLoc["ring-heal8"], G.itemLoc["ring-heal10"] = "INVTYPE_FINGER", "INVTYPE_FINGER"
G.worn[11], G.worn[12] = "ring-heal8", None
lines = [l[1] for l in si.TooltipLines("ring-heal10").values()]
check("rings: against the worn one +25%, the other finger empty caps, both marked",
      (any("Restoration: |cff4dff4d25% better healer score (approx.)|r" in l for l in lines),
       any("Restoration: |cff4dff4d>300% better healer score (approx.)|r" in l for l in lines)),
      (True, True))
G.worn[5] = None
G.worn[11], G.worn[12] = None, None
rt.execute("SECRET_R = {} function issecretvalue(v) return v == SECRET_R end")
G.itemStats["secret-mend"] = rt.eval("{ ITEM_MOD_SPELL_HEALING_DONE_SHORT = SECRET_R }")
G.itemLoc["secret-mend"] = "INVTYPE_CHEST"
r = healing_row(si.SpecRatings("secret-mend", rt.table_from([])))
check("a secret (combat-hidden) healing stat is never arithmetic'd: score 0, no bogus cap",
      (round(r.parts[1].percent, 2), r.parts[1].capped), (0, None))
lines = [l[1] for l in si.TooltipLines("secret-mend").values()]
check("  and it shows no healer line at all",
      any("Restoration" in l for l in lines), False)
rt.execute("issecretvalue = nil")

# ---------------------------------------------------------------------------------------------
print("-- Restoration: the settings tab explains the healer exception and the model")
def texts(f, out):
    if f.text:
        out.append(f.text)
    for ch in (f.children or {}).values():
        texts(ch, out)
    return out

BIT.OpenSettings("StatsInfo")  # the page builds the first time it is shown
tab = " ".join(texts(BIT._pages["StatsInfo"], []))
check("the tab explains the heuristic, its exact weights and the (approx.) marker, and no longer "
      "says healers are not rated",
      ("1 x +Healing" in tab, "1 x Spell Power" in tab, "0.5 x Intellect" in tab,
       "0.5 x Spirit" in tab, "2 x MP5" in tab, "(approx.)" in tab,
       "Healers are not rated" in tab), (True, True, True, True, True, True, False))

# ---------------------------------------------------------------------------------------------
print("-- Restoration: the generator's data, provenance and byte-for-byte regeneration")
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location("make_weights", str(ROOT / "tools" / "make_weights.py"))
mw = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(mw)
import json as _json
hd = _json.load(open(ROOT / "tools" / "data" / "healer_weights.json", encoding="utf-8"))
check("the healer data's provenance: a starter heuristic, not a simulated result, with the model",
      (hd["source"], hd["approximate"], "weighted score = 1 * +Healing + 1 * Spell Power + 0.5 * Intellect"
       " + 0.5 * Spirit + 2 * MP5" in hd["model"]),
      ("UsefulPlatesAndTooltips starter heuristic, not simulated", True, True))
check("the generator's source bookkeeping keeps the healer specs from any sim run",
      (mw.HEALER_RUNS, "druid_restoration" in mw.HEALER_RUNS),
      ({"druid_restoration", "priest_holy", "paladin_holy", "shaman_restoration"}, True))
before = (ROOT / "Modules" / "StatsInfo" / "Weights.lua").read_bytes()
import tempfile
with tempfile.TemporaryDirectory() as generated:
    mw.OUT = pathlib.Path(generated) / "Weights.lua"
    mw.main()
    after = mw.OUT.read_bytes()
check("regenerating Weights.lua reproduces the file byte for byte (no drift)",
      after == before, True)
text = after.decode("utf-8")
check("  and the generated file never loses a healer or relabels it ForeverSim",
      tuple(x in text for x in ("druid/restoration", "priest/holy", "paladin/holy", "shaman/restoration"))
      + ("UsefulPlatesAndTooltips starter heuristic, not simulated" in text,
       after.count(b"approximate = true")), (True, True, True, True, True, 4))
check("the sim specs' numbers did not move (spot values across classes)",
      (W.DRUID[1].survival.weights.ITEM_MOD_STAMINA_SHORT,
       W.DRUID[2].damage.weights.ITEM_MOD_CRIT_RATING_SHORT,
       W.ROGUE[1].damage.mainHand,
       W.MAGE[1].damage.weights.ITEM_MOD_SPELL_POWER_SHORT), (2.4022, 0.8401, 11.021, 1.0))

# one-hand weapon into the main hand: compared with the worn one, DPS still nothing
G.itemStats["mace12"] = rt.eval('{ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 12, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30 }')
G.itemLoc["mace12"] = "INVTYPE_WEAPON"
G.worn[16], G.worn[17] = "mend+10", None
c = si.Compare("mace12")
r = healing_row(si.SpecRatings("mace12", c[1].against, c[1].slots, c[1].offHand))
check("a one-hand weapon into the main hand: +20% against the worn one, its DPS counts for nothing",
      (round(r.parts[1].percent, 2), c[1].offHand), (20.0, False))
G.worn[16], G.worn[17] = None, None

print("failed:", failures)
sys.exit(1 if failures else 0)
