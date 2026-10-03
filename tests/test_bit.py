"""BattleInfoTool as a whole: every file of the .toc loaded in order in Lua 5.1 (lupa) against a fake
game, then driven: ADDON_LOADED, PLAYER_LOGIN, /bit and each tab, a module switched off,
an unrelated addon enabled (ignored), the range mark, StatsInfo's comparison and probe.

    python tests/test_bit.py

The fake frames accept any method (one they do not model does nothing and returns nothing) and
record what matters. It catches runtime errors and wrong decisions, not how anything looks.
Each module's own behaviour is tested by its own suite: tools/test_modules.py.
"""
import pathlib
import sys

from lupa.lua51 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent

FAKE = r"""
chat = {}
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
    loader = rt.eval("function(src, name, BIT) local f = assert(loadstring(src, '@' .. name)); return f('BattleInfoTool', BIT) end")
    toc = (ROOT / "BattleInfoTool.toc").read_text(encoding="utf-8").splitlines()
    files = [l.strip() for l in toc if l.strip() and not l.startswith("#")]
    for f in files:
        loader((ROOT / f.replace("\\", "/")).read_text(encoding="utf-8"), f, BIT)
    return rt, G, BIT, files


def chat(G):
    return [G.chat[i] for i in range(1, len(G.chat) + 1)]


# ---------------------------------------------------------------------------------------------
print("-- every module on")
rt, G, BIT, files = load()
check("the .toc lists the core and seven modules' files", len(files), 23)  # SpellCoefficients.lua since 0.8.0, StatsInfo's Weights.lua since 0.6.0
check("the tabs are in the order the files load", list(BIT.order.values()),
      ["SpellDamageInfo", "DoTInfo", "StatsInfo", "ResourceDing", "Range", "ShieldsInfo", "HunterRangeFinder"])
G.Fire("ADDON_LOADED", "BattleInfoTool")
G.Fire("PLAYER_LOGIN")
for name in ("SpellDamageInfo", "DoTInfo", "StatsInfo", "ResourceDing", "Range", "ShieldsInfo", "HunterRangeFinder"):
    check(f"{name} runs", BIT.state[name], "on")
check("each ported module keeps its SavedVariables apart",
      all(isinstance(G[n], object) and G[n] is not None for n in
          ("BattleInfoTool_SpellDamageInfoDB", "BattleInfoTool_DoTInfoDB", "BattleInfoTool_ResourceDingDB")), True)
check("the standalone addons' SavedVariables are left alone",
      [G[n] for n in ("SpellDamageInfoDB", "ResourceDingDB")], [None, None])
check("the DoTInfo runtime file is Modules/DoTInfo/Core.lua",
      "Modules\\DoTInfo\\Core.lua" in files, True)
check("DoTInfo's marker frames carry canonical names",
      (G.BattleInfoTool_DoTInfoSkull is not None, G.BattleInfoTool_DoTInfoRemaining is not None), (True, True))
did = BIT.modules["DoTInfo"]
check("DoTInfo's textures are in the module's folder",
      str(did.textureDir or ""), "Interface\\AddOns\\BattleInfoTool\\Modules\\DoTInfo\\Textures\\")
check("no global ResourceDing table inside BattleInfoTool", G.ResourceDing, None)
check("ResourceDing's combo point dots started", BIT.modules["ResourceDing"]._dotsRow() is not None, True)

# /bit and the tabs
G.SlashCmdList.BATTLEINFOTOOL("")
window = G.BattleInfoToolSettings
check("/bit opens the window", window is not None and window.shown, True)
for name in ("SpellDamageInfo", "DoTInfo", "StatsInfo", "ResourceDing", "Range", "ShieldsInfo", "HunterRangeFinder"):
    BIT.OpenSettings(name)
    page = BIT._pages[name]
    check(f"the {name} tab is built and shown", page is not None and page.shown, True)
    check(f"  its content was built, not the off note", page.offNote, None)
check("no tab failed to build", [m for m in chat(G) if "could not be built" in m], [])
G.SlashCmdList.BATTLEINFOTOOL("ding")
check("/bit ding opens ResourceDing's tab", BIT._pages["ResourceDing"].shown, True)

# the switch
page = BIT._pages["Range"]
page.switch.scripts.OnClick(page.switch)  # the box was checked; OnClick reads it after the click
page.switch.checked = False
page.switch.scripts.OnClick(page.switch)
check("unticking Enable saves the switch", G.BattleInfoToolDB.modules.Range.enabled, False)
check("  and offers a reload", page.reload.shown, True)
check("  the module keeps running until then", BIT.state["Range"], "on")

# ---------------------------------------------------------------------------------------------
print("-- DoTInfo's preview and a fight")
log = G.BattleInfoTool_DoTInfoDB.log


def since_last(text):
    """The log lines after the last one containing text."""
    lines = [log[i] for i in range(1, len(log) + 1)]
    last = max((i for i, l in enumerate(lines) if text in l), default=-1)
    return lines[last + 1:]


BIT.OpenSettings("DoTInfo")
check("the DoTInfo tab shown: the marker draws on its preview", "PREVIEW on" in (since_last("PREVIEW off") or [""])[-1] or
      any("PREVIEW on" in l for l in since_last("PREVIEW off")), True)
G.combat = True
G.Fire("PLAYER_REGEN_DISABLED")
G.combat = False
G.Fire("PLAYER_REGEN_ENABLED")
check("  a fight while the tab is open: afterwards the preview has the marker again",
      any("PREVIEW on" in l for l in since_last("PREVIEW off")), True)
G.BattleInfoToolSettings.Hide(G.BattleInfoToolSettings)
check("the window closed: the marker goes back to the target frame",
      any("PREVIEW off" in l for l in since_last("PREVIEW on")), True)
G.combat = True
G.Fire("PLAYER_REGEN_DISABLED")
G.combat = False
G.Fire("PLAYER_REGEN_ENABLED")
check("  a fight after closing it: the marker stays on the target frame, not on the closed window's preview",
      [l for l in since_last("PREVIEW off") if "PREVIEW on" in l], [])

# ---------------------------------------------------------------------------------------------
print("-- the range mark")
rng = BIT.modules["Range"]
icon = rng._icon()
G.target = rt.eval("{ hostile = true }")
G.inRange["Schattenblitz"] = True
G.Fire("PLAYER_TARGET_CHANGED")
check("a hostile target in range: the green checkmark", (icon.shown, icon.texture.texture),
      (True, "Interface\\RaidFrame\\ReadyCheck-Ready"))
check("  beside the target frame without a nameplate", G.Same(icon.parent, G.UIParent), True)
G.inRange["Schattenblitz"] = False
G.inRange["Verderbnis"] = False
G.Tick(0.2)
check("out of range with both spells: the red X", icon.texture.texture, "Interface\\RaidFrame\\ReadyCheck-NotReady")
G.inRange["Verderbnis"] = True
G.Tick(0.2)
check("in range when any one of the class's spells reaches", icon.texture.texture, "Interface\\RaidFrame\\ReadyCheck-Ready")
G.plate = rt.eval("NewPlate()")
G.Tick(0.2)
check("with a nameplate: on the plate", G.Same(icon.parent, G.plate), True)
G.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
# during the event the client still gives the target this plate: the icon must leave it all the same
check("the plate handed back: the icon leaves it at once", G.Same(icon.parent, G.UIParent), True)
G.plate = None  # and then the target has no plate
G.Tick(0.2)
check("  and stays off it", G.Same(icon.parent, G.UIParent), True)
G.target = rt.eval("{ hostile = false }")
G.Tick(0.2)
check("a friendly target: nothing", icon.shown, False)
G.target = None
G.Fire("PLAYER_TARGET_CHANGED")
check("no target: nothing, and the updater stops", (icon.shown, rng._driver().shown), (False, False))
G.target = rt.eval("{ hostile = true }")
G.inRange["Schattenblitz"], G.inRange["Verderbnis"] = None, None
G.Fire("PLAYER_TARGET_CHANGED")
check("no spell can say: nothing rather than a guess", icon.shown, False)
rng.settings.spell = "1752"
check("a spell set by id is measured by its name", list(rng.Spells().values()), ["Finsterer Stoß"])
rng.settings.spell = ""
G.playerClass = "DRUID"
G.GetShapeshiftFormID = rt.eval("function() return 1 end")
G.spellNames[1082] = "Klaue"
check("a druid in Cat Form measures by Claw", list(rng.Spells().values()), ["Klaue"])
G.playerClass = "WARRIOR"
for sid, name in ((772, "Verwunden"), (1715, "Kniesehne"), (7386, "Rüstung zerreißen"), (355, "Spott"),
                  (100, "Sturmangriff"), (78, "Heldenhafter Stoß"), (845, "Spalten"), (6603, "Angreifen")):
    G.spellNames[sid] = name
G.usable = rt.eval("{}")
G.C_Spell.IsSpellUsable = rt.eval("function(id) return usable[id] end")
check("a warrior measures by Rend, Hamstring, Sunder Armor, Taunt and Charge, not Heroic Strike or Cleave",
      list(rng.Spells().values()), ["Verwunden", "Kniesehne", "Rüstung zerreißen", "Spott", "Sturmangriff"])
G.target = rt.eval("{ hostile = true }")
G.inRange["Heldenhafter Stoß"] = True  # what the client told a warrior 30 yards away
G.inRange["Verwunden"], G.inRange["Kniesehne"], G.inRange["Sturmangriff"] = False, False, True
G.usable[100] = False  # in combat
G.Fire("PLAYER_TARGET_CHANGED")
check("  in Charge's range but in combat: the red X", icon.texture.texture, "Interface\RaidFrame\ReadyCheck-NotReady")
G.usable[100] = True
G.Tick(0.2)
check("  in Charge's range and it can be used: the checkmark", icon.texture.texture, "Interface\RaidFrame\ReadyCheck-Ready")
G.combat = True  # the game still calling it usable: in combat Charge does not count
G.Tick(0.2)
check("  in combat, even if the game calls Charge usable: the red X", icon.texture.texture, "Interface\RaidFrame\ReadyCheck-NotReady")
G.combat = False
G.C_Spell.GetSpellCooldown = rt.eval("function(id) if id == 100 then return { startTime = 50, duration = 15 } end end")
G.Tick(0.2)
check("  Charge cooling down: the red X", icon.texture.texture, "Interface\RaidFrame\ReadyCheck-NotReady")
G.C_Spell.GetSpellCooldown = rt.eval("function(id) return { startTime = 50, duration = 1.5 } end")
G.Tick(0.2)
check("  only the global cooldown: Charge counts", icon.texture.texture, "Interface\RaidFrame\ReadyCheck-Ready")
G.C_Spell.GetSpellCooldown = None
G.inRange["Sturmangriff"] = False
G.Tick(0.2)
check("  beyond Charge, Heroic Strike saying yes: the red X", icon.texture.texture, "Interface\RaidFrame\ReadyCheck-NotReady")
G.inRange["Verwunden"] = True
G.Tick(0.2)
check("  in melee range of Rend: the checkmark", icon.texture.texture, "Interface\RaidFrame\ReadyCheck-Ready")
before = len(chat(G))
G.SlashCmdList["BATTLEINFOTOOL"]("rangecheck")
lines = chat(G)[before:]
check("/bit rangecheck: a line for the mark and one per spell, the next-swing ones and Attack included",
      (len(lines), any("78 Heldenhafter Stoß" in l and "by name true" in l and "(measured)" not in l for l in lines),
       any("6603 Angreifen" in l for l in lines), any("772 Verwunden" in l and "(measured)" in l for l in lines)),
      (9, True, True, True))
G.playerClass = "HUNTER"
for sid, name in ((75, "Automatischer Schuss"), (3044, "Arkaner Schuss"), (2974, "Zurechtstutzen"),
                  (1495, "Mungobiss"), (2973, "Raptorstoß")):
    G.spellNames[sid] = name
check("a hunter measures by Wing Clip and Mongoose Bite in melee, not Raptor Strike", list(rng.Spells().values()),
      ["Automatischer Schuss", "Arkaner Schuss", "Zurechtstutzen", "Mungobiss"])
G.playerClass = "DRUID"
G.GetShapeshiftFormID = rt.eval("function() return 5 end")
for sid, name in ((6795, "Knurren"), (5211, "Hieb"), (6807, "Zermalmen")):
    G.spellNames[sid] = name
check("a druid in Bear Form measures by Growl and Bash, not Maul", list(rng.Spells().values()), ["Knurren", "Hieb"])
G.GetShapeshiftFormID = rt.eval("function() return 1 end")
G.playerClass = "DRUID"  # as the probe below expects

# ---------------------------------------------------------------------------------------------
print("-- action bar icons out of range")
dim = G.hooks["ActionButton_UpdateRangeIndicator"]
check("the action bar's range update is hooked", dim is not None)
rt.execute("""
  testButton = { action = 5, icon = {} }
  function testButton.icon:SetDesaturated(v) self.desat = v end
  function testButton.icon:SetVertexColor(r, g, b) self.rgb = string.format("%.2f %.2f %.2f", r, g, b) end
  function testButton:UpdateUsable() self.icon:SetVertexColor(1, 1, 1) end -- as Blizzard's, for a usable action
""")
button, icon = G.testButton, G.testButton.icon
G.usableActions[5] = True
dim(button, True, False)
check("out of range: the icon grey and dim", (icon.desat, icon.rgb), (True, "0.60 0.60 0.60"))
check("  its UpdateUsable is hooked", button.hooks["UpdateUsable"] is not None)
button.UpdateUsable(button)
check("  Blizzard's UpdateUsable puts the colour back...", icon.rgb, "1.00 1.00 1.00")
button.hooks["UpdateUsable"](button)
check("  ...and the hook dims it again", icon.rgb, "0.60 0.60 0.60")
dim(button, True, True)
check("back in range: grey no more, the colour back", (icon.desat, icon.rgb), (False, "1.00 1.00 1.00"))
G.usableActions[5], G.noManaActions[5] = False, True
dim(button, True, False)
check("out of range without the mana: Blizzard's blue, dimmed", icon.rgb, "0.30 0.30 0.60")
dim(button, False, False)
check("nothing to measure (no target): Blizzard's blue as it is", (icon.desat, icon.rgb), (False, "0.50 0.50 1.00"))
dim(button, True, False)
rng.settings.dimIcons = False
rng.RefreshDimming()
check("the setting turned off: a dimmed icon comes back at once", (icon.desat, icon.rgb), (False, "0.50 0.50 1.00"))
dim(button, True, False)
check("  and is left alone out of range", icon.desat, False)
rng.settings.dimIcons = True
rt.execute("SECRET = {} function issecretvalue(v) return v == SECRET end")
dim(button, True, G.SECRET)
check("a secret answer is left alone", icon.desat, False)
rt.execute("issecretvalue = nil")
check("the setting is on by default", rt.eval("BattleInfoToolDB.modules.Range.dimIcons"), True)

# ---------------------------------------------------------------------------------------------
print("-- StatsInfo")
si = BIT.modules["StatsInfo"]
si.settings.icons = False  # the lines in words first; the icons further down
si.settings.specs = False  # and the specs' ratings on their own below
G.itemStats["new-ring"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 3 }')
G.itemStats["ring-a"] = rt.eval('{ ITEM_MOD_STAMINA_SHORT = 5 }')
G.itemStats["ring-b"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 3 }')
for link in ("new-ring", "ring-a", "ring-b"):
    G.itemLoc[link] = "INVTYPE_FINGER"
G.worn[11], G.worn[12] = "ring-a", "ring-b"
c = si.Compare("new-ring")
check("a ring is compared with each ring worn", len(c), 2)
first = [(d.key, d.diff) for d in c[1].diffs.values()]
check("  against the first: +5 Agility, -2 Stamina, Agility first",
      first, [("ITEM_MOD_AGILITY_SHORT", 5), ("ITEM_MOD_STAMINA_SHORT", -2)])
check("  against the second: the same stats", len(c[2].diffs), 0)
lines = [l[1] for l in si.TooltipLines("new-ring").values()]
check("  tooltip lines use the client's stat names", "  +5 Beweglichkeit" in lines and "  -2 Ausdauer" in lines, True)
check("a ring that is worn gets no comparison at all (not 'against an empty slot')", si.Compare("ring-a"), None)
# Forever gives a ring's frost resistance twice, the second key without a name on this client
G.RESISTANCE4_NAME = "Frostwiderstand"
G.itemStats["frost-ring"] = rt.eval('{ RESISTANCE4_NAME = 1, ITEM_MOD_FROST_RESISTANCE_SHORT = 1 }')
G.itemLoc["frost-ring"] = "INVTYPE_FINGER"
G.worn[12] = None
frost = [l[1] for l in si.TooltipLines("frost-ring").values()]
check("a stat the client has no name for is left out, not shown as its key",
      ([l for l in frost if "ITEM_MOD" in l], "  +1 Frostwiderstand" in frost), ([], True))
G.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "Schaden pro Sekunde"
G.itemStats["knife"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 1.9 }')
G.itemStats["dagger"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 2.4, ITEM_MOD_AGILITY_SHORT = 1 }')
G.itemLoc["knife"], G.itemLoc["dagger"] = "INVTYPE_WEAPON", "INVTYPE_WEAPON"
G.worn[16], G.worn[17] = "knife", None
c = si.Compare("dagger")
check("a one-hand weapon from the bags: against the main hand only, not also an empty off hand",
      (len(c), list(c[1].against.values())), (1, ["knife"]))
dagger = [l[1] for l in si.TooltipLines("dagger").values()]
check("  damage per second to one decimal", "  +0.5 Schaden pro Sekunde" in dagger, True)
check("the knife worn: no lines", len(si.TooltipLines("knife")), 0)
G.itemStats["razor"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 1.94 }')
G.itemLoc["razor"] = "INVTYPE_WEAPON"
c = si.Compare("razor")
razor_diffs = [(d.key, d.diff) for d in c[1].diffs.values()]
check("SI-124: a +0.04 DPS diff rounds to +0.0, so it is left out", razor_diffs, [])
razor_lines = [l[1] for l in si.TooltipLines("razor").values()]
check("  and no '+0.0' line in the tooltip", any("0.0" in l for l in razor_lines), False)
G.itemStats["staff"] = rt.eval('{ ITEM_MOD_STRENGTH_SHORT = 10 }')
G.itemStats["sword"] = rt.eval('{ ITEM_MOD_STRENGTH_SHORT = 4 }')
G.itemStats["shield"] = rt.eval('{ ITEM_MOD_STAMINA_SHORT = 6 }')
G.itemLoc["staff"] = "INVTYPE_2HWEAPON"
G.worn[16], G.worn[17] = "sword", "shield"
c = si.Compare("staff")
check("a two-hander is compared with both hands together", len(c), 1)
check("  +6 Strength, -6 Stamina", [(d.key, d.diff) for d in c[1].diffs.values()],
      [("ITEM_MOD_STRENGTH_SHORT", 6), ("ITEM_MOD_STAMINA_SHORT", -6)])
# what a stat gives, with the numbers a Forever warlock's probe recorded
G.GetAttackPowerForStat = rt.eval("function(stat, n) if stat == 1 then return n end return 0 end")
G.GetManaRegen = rt.eval("function() return 7.750999927520752, 0.001000000047497451 end")
G.UnitStat = rt.eval("function(_, i) if i == 5 then return 31, 31, 0, 0 end return 20, 22, 2, 0 end")
check("Agility: 2 armor a point, and no attack power for a class that gets none",
      si.Worth("ITEM_MOD_AGILITY_SHORT", 5), "+10 armor")
check("Strength: the game's attack power", si.Worth("ITEM_MOD_STRENGTH_SHORT", 6), "+6 attack power")
check("  less of it", si.Worth("ITEM_MOD_STRENGTH_SHORT", -4), "-4 attack power")
check("Stamina: 10 health a point", si.Worth("ITEM_MOD_STAMINA_SHORT", -2), "-20 health")
check("Intellect: 15 mana a point", si.Worth("ITEM_MOD_INTELLECT_SHORT", 3), "+45 mana")
check("Spirit: the game's regeneration, a quarter of a point a second", si.Worth("ITEM_MOD_SPIRIT_SHORT", 4),
      "+5 mana per 5 sec. when not casting")
check("  3 points", si.Worth("ITEM_MOD_SPIRIT_SHORT", 3), "+3.8 mana per 5 sec. when not casting")
G.GetAttackPowerForStat = rt.eval("function(stat, n) return 2 * n end")
check("Agility for a class that gets attack power from it", si.Worth("ITEM_MOD_AGILITY_SHORT", 5), "+10 armor, +10 attack power")
G.UnitPowerMax = rt.eval("function() return 0 end")
check("no mana: nothing for Intellect or Spirit",
      (si.Worth("ITEM_MOD_INTELLECT_SHORT", 3), si.Worth("ITEM_MOD_SPIRIT_SHORT", 4)), (None, None))
G.UnitPowerMax = rt.eval("function() return 100 end")
check("armor itself: nothing more", si.Worth("RESISTANCE0_NAME", 20), None)
# Forever's items give crit and hit as rating; the game converts it at the character's level
rt.execute("""
  CR_CRIT_MELEE, CR_HIT_MELEE = 9, 6
  function GetCombatRatingBonusForCombatRatingValue(index, v)
    if index == 9 then return v / 7 elseif index == 6 then return v / 5 elseif index == 24 then return v / 4 end
  end
""")
check("crit rating: the crit it gives at this level", si.Worth("ITEM_MOD_CRIT_RATING_SHORT", 14), "+2.00% crit")
check("  less of it: a negative crit", si.Worth("ITEM_MOD_CRIT_RATING_SHORT", -7), "-1.00% crit")
check("hit rating", si.Worth("ITEM_MOD_HIT_RATING_SHORT", 10), "+2.00% hit")
check("expertise rating (Forever shows expertise in percent)", si.Worth("ITEM_MOD_EXPERTISE_RATING_SHORT", 2), "+0.50% expertise")
check("a rating the game has no answer for: nothing", si.Worth("ITEM_MOD_HASTE_RATING_SHORT", 10), None)
rt.execute("CR_CRIT_MELEE = nil")
check("  the rating index without the sheet's global: Forever's number", si.Worth("ITEM_MOD_CRIT_RATING_SHORT", 14), "+2.00% crit")
rt.execute("GetCombatRatingBonusForCombatRatingValue = nil")
check("  and without the function: nothing", si.Worth("ITEM_MOD_CRIT_RATING_SHORT", 14), None)
lines = [l[1] for l in si.TooltipLines("staff").values()]
check("in the tooltip: under each stat, what it gives, green up and red down", lines,
      ["Against ? + ?:", "  +6 Stärke", "      |cff4dff4d+12 attack power|r", "  -6 Ausdauer", "      |cffff5959-60 health|r"])
si.settings.worth = False
check("  switched off: the stats alone", [l[1] for l in si.TooltipLines("staff").values()],
      ["Against ? + ?:", "  +6 Stärke", "  -6 Ausdauer"])
si.settings.worth = True

# ---------------------------------------------------------------------------------------------
print("-- StatsInfo: how each spec rates an item")
W = si.SPECS
check("every class has its specs, the druid four (Restoration the healer)", (len(W.DRUID), [x.name for x in W.DRUID.values()]),
      (4, ["Bear", "Cat", "Balance", "Restoration"]))
check("  no healer anywhere but the druid's: no healer in the specs of the others, and no table of them", (si.UNRATED_SPECS,
      [x.name for c in ("PRIEST", "SHAMAN", "PALADIN") for x in W[c].values()]),
      (None, ["Shadow", "Smite", "Elemental", "Enhancement", "Protection", "Retribution"]))
check("  a tank has survival and threat, a damage spec damage",
      (W.DRUID[1].survival is not None, W.DRUID[1].threat is not None, W.DRUID[2].damage is not None), (True, True, True))
check("  a spec per talent tree or build: warrior, mage, hunter, rogue, warlock",
      [[x.name for x in W[c].values()] for c in ("WARRIOR", "MAGE", "HUNTER", "ROGUE", "WARLOCK")],
      [["Protection", "Arms", "Fury"], ["Arcane", "Fire", "Frost"], ["Beast Mastery", "Marksmanship", "Survival"],
       ["Sinister Strike", "Backstab", "Mutilate"], ["Affliction", "Demonology", "Destruction", "DS/Ruin"]])
check("  Forever's hit counts in both pools: an enhancement shaman's melee and spell hit together",
      W.SHAMAN[2].damage.weights.ITEM_MOD_HIT_RATING_SHORT, 2.8435)
G.playerClass = "DRUID"
G.itemStats["hide-a"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 5 }')
G.itemStats["hide-b"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 8, ITEM_MOD_STAMINA_SHORT = 2 }')
G.itemLoc["hide-a"], G.itemLoc["hide-b"] = "INVTYPE_CHEST", "INVTYPE_CHEST"
worn_a = rt.table_from(["hide-a"])
r = {x.spec.name: [(pt.kind, round(pt.percent, 2) if pt.percent is not None else None,
                    round(pt.points, 2) if pt.points is not None else None) for pt in x.parts.values()]
     for x in si.SpecRatings("hide-b", worn_a).values()}
check("a cat: 8 Agility against 5 is 60% more (Stamina is worth nothing to its damage)", r["Cat"], [("damage", 60.0, None)])
check("  a bear: survival 8 x 0.7397 + 2 x 2.4022 against 5 x 0.7397; threat 8 + 2 x -0.3952 against 5 (more "
      "health is less rage from each hit: Forever pays rage from a hit as damage x 10 / max health)",
      r["Bear"], [("survival", 189.9, None), ("threat", 44.19, None)])
check("  a balance druid: worth nothing either way, so 0%", r["Balance"], [("damage", 0, None)])
r = {x.spec.name: [round(pt.percent, 2) for pt in x.parts.values()] for x in si.SpecRatings("hide-b", rt.table_from([])).values()}
check("an empty slot: past the cap (>300% dmg spec)", r["Cat"], [300.0])
G.itemStats["club"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 }')
G.itemStats["twig"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 }')
G.itemLoc["club"], G.itemLoc["twig"] = "INVTYPE_2HWEAPON", "INVTYPE_2HWEAPON"
r = {x.spec.name: [pt.percent for pt in x.parts.values()] for x in si.SpecRatings("club", rt.table_from(["twig"])).values()}
check("in Cat and Bear Form the weapon's damage counts (game-measured: 1 DPS ~= 14 FAP), for damage/threat but not "
      "survival, nor for Balance", (r["Cat"], r["Bear"], r["Balance"]), ([100], [0, 100], [0]))
G.playerClass = "WARRIOR"
G.itemStats["axe"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10, ITEM_MOD_STRENGTH_SHORT = 5 }')
G.itemStats["blade"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8 }')
G.itemLoc["axe"], G.itemLoc["blade"] = "INVTYPE_2HWEAPON", "INVTYPE_2HWEAPON"
r = {x.spec.name: round(x.parts[1].percent, 2) for x in si.SpecRatings("axe", rt.table_from(["blade"])).values()
     if x.spec.role == "damage"}
check("a warrior's weapon: its damage per second at the sim's weight for the spec (Arms 5 Str + 6.552 x 10 "
      "against 6.552 x 8, Fury 2.999 a point: Bloodthirst does not use the weapon)",
      (r["Arms"], r["Fury"]), (34.54, 45.84))
G.playerClass = "HUNTER"
G.itemStats["bow"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5 }')
G.itemStats["bow-worn"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 4 }')
G.itemLoc["bow"], G.itemLoc["bow-worn"] = "INVTYPE_RANGED", "INVTYPE_RANGED"
r = si.SpecRatings("bow", rt.table_from(["bow-worn"]))
check("a hunter's bow: the sim's ranged weapon weight (Beast Mastery 5.553 x 5 vs 5.553 x 4 -> +25%)",
      round(r[1].parts[1].percent, 2), 25.0)
G.playerClass = "DEATHKNIGHT"
check("  a class without weights: no ratings", si.SpecRatings("bow", rt.table_from([])), None)
check("SDI-HEAL RED: +healing states what it gives", si.Worth("ITEM_MOD_SPELL_HEALING_DONE_SHORT", 20), "+20 healing")

# what the review found (2026-09-27); the slots it uses are put back after it
saved_worn = {slot: G.worn[slot] for slot in (5, 11, 12, 16, 17)}
# the client's names for the stats below (Forever's enUS GlobalStrings); a stat without one is left out
G.ITEM_MOD_ATTACK_POWER_SHORT = "Attack Power"
G.ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = "Shadow Damage"
G.ITEM_MOD_PHYSICAL_DAMAGE_DONE_SHORT = "Physical Damage"
def pts(ratings, name, i=1):
    for x in ratings.values():
        if x.spec.name == name:
            return round(x.parts[i].percent, 2)
G.playerClass = "ROGUE"
G.itemStats["gun"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 }')
G.itemLoc["gun"] = "INVTYPE_RANGEDRIGHT"
check("a rogue's gun: its damage per second is worth nothing (the sim gives a rogue no ranged weapon weight)",
      pts(si.SpecRatings("gun", rt.table_from([])), "Sinister Strike"), 0)
G.playerClass = "HUNTER"
G.itemStats["cloak-ap"] = rt.eval('{ ITEM_MOD_ATTACK_POWER_SHORT = 20 }')
G.itemStats["cloak-agi"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 5 }')
G.itemLoc["cloak-ap"], G.itemLoc["cloak-agi"] = "INVTYPE_CLOAK", "INVTYPE_CLOAK"
check("a hunter's +20 Attack Power counts as ranged attack power (20 x 0.4086 against 5 Agility)",
      pts(si.SpecRatings("cloak-ap", rt.table_from(["cloak-agi"])), "Beast Mastery"), 63.44)
G.playerClass = "WARRIOR"
G.itemStats["ring-str"] = rt.eval('{ ITEM_MOD_STRENGTH_SHORT = 5 }')
G.itemStats["ring-agi"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 7, ITEM_MOD_STAMINA_SHORT = 5 }')
G.itemLoc["ring-str"], G.itemLoc["ring-agi"] = "INVTYPE_FINGER", "INVTYPE_FINGER"
check("a worn ring worth less than a point to survival: capped, not +260000%",
      pts(si.SpecRatings("ring-agi", rt.table_from(["ring-str"])), "Protection", 1), 300)
G.itemStats["mh40"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 }')
G.itemStats["oh40"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 }')
G.itemStats["2h60"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 60 }')
G.itemLoc["mh40"], G.itemLoc["oh40"], G.itemLoc["2h60"] = "INVTYPE_WEAPON", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON"
G.worn[16], G.worn[17] = "mh40", "oh40"
c = si.Compare("2h60")
ratings = si.SpecRatings("2h60", c[1].against, c[1].slots, c[1].offHand)
check("a two-hander against 40 + 40 DPS in two hands: Arms counts no off hand (+50%), Fury its own (60 x 2.999 "
      "against 40 x 2.999 + 40 x 1.916)", (pts(ratings, "Arms"), pts(ratings, "Fury")),
      (50.0, -8.47))
G.itemStats["2h-worn"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 50, ITEM_MOD_STRENGTH_SHORT = 10 }')
G.itemStats["buckler"] = rt.eval('{ RESISTANCE0_NAME = 500, ITEM_MOD_STAMINA_SHORT = 5 }')
G.itemLoc["2h-worn"], G.itemLoc["buckler"] = "INVTYPE_2HWEAPON", "INVTYPE_SHIELD"
G.worn[16], G.worn[17] = "2h-worn", None
c = si.Compare("buckler")
check("a shield while a two-hander is worn: against the two-hander it takes off, not an empty slot",
      (len(c), list(c[1].against.values()), c[1].offHand), (1, ["2h-worn"], True))
G.worn[16] = None
G.C_Item.IsItemDataCachedByID = rt.eval("function() return false end")
check("an item the client has not loaded yet: no comparison (its stats would read as none)", si.Compare("buckler"), None)
G.C_Item.IsItemDataCachedByID = None
G.playerClass = "WARLOCK"
G.itemStats["shadow-ring"] = rt.eval('{ ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = 10 }')
G.itemLoc["shadow-ring"] = "INVTYPE_FINGER"
G.worn[11], G.worn[12] = None, None
check("a school's spell damage counts: +10 Shadow Damage for an affliction warlock, empty slot caps",
      pts(si.SpecRatings("shadow-ring", rt.table_from([])), "Affliction"), 300)
G.playerClass = "ROGUE"
G.itemStats["weapon-dmg"] = rt.eval('{ ITEM_MOD_PHYSICAL_DAMAGE_DONE_SHORT = 2 }')
G.itemLoc["weapon-dmg"] = "INVTYPE_HAND"
check("  and '+N Weapon Damage': empty slot caps",
      pts(si.SpecRatings("weapon-dmg", rt.table_from([])), "Sinister Strike"), 300)
for slot, link in saved_worn.items():
    G.worn[slot] = link

G.playerClass = "DRUID"
G.worn[5] = "hide-a"
si.settings.specs = True
lines = [l[1] for l in si.TooltipLines("hide-b").values()]
check("in words: the divider, a line per spec the item changes something for (not Balance), no line for the healer",
      lines[-3:], ["|TInterface\\Common\\UI-TooltipDivider-Transparent:8:200|t",
                   "  Bear: |cff4dff4d190% better for survival|r, |cff4dff4d44% better for threat gen.|r",
                   "  Cat: |cff4dff4d60% better dmg spec|r"])
si.settings.icons = True
lines = [l[1] for l in si.TooltipLines("hide-b").values()]
check("with icons: 'Against' without its colon, the stats on one line",
      lines[:2], ["Against ?", "|cff4dff4d+3 Beweglichkeit|r   |cff4dff4d+2 Ausdauer|r"])
check("  what they give on one line, summed, each behind its icon",
      "INV_Chest_Chain_05:12:12" in lines[2] and "Spell_Holy_SealOfSacrifice:12:12" in lines[2], True)
check("  the divider, a tank on its own line, then Cat, each icon with its name",
      (lines[3], lines[4].count("|TInterface\\Icons\\"), lines[5].count("|TInterface\\Icons\\"),
       "Bear: |cff4dff4d190% better for survival|r, |cff4dff4d44% better for threat gen.|r" in lines[4], "Cat: " in lines[5],
       len(lines)), ("|TInterface\\Common\\UI-TooltipDivider-Transparent:8:200|t", 1, 1, True, True, 6))
check("  what the stats give: each icon with a word for its stat", ("armor" in lines[2], "health" in lines[2] or "health" in lines[3]),
      (True, True))
check("  green where it goes up", "|cff4dff4d+6 armor|r" in lines[2], True)
G.worn[5] = "hide-b"
worse = [l[1] for l in si.TooltipLines("hide-a").values()]
check("  red where it goes down (the worse item)", any("|cffff5959-6 armor|r" in l for l in worse), True)
G.worn[5] = "hide-a"
check("  a spec the item changes nothing for is left out", any("Balance" in l for l in lines), False)
check("  no line for the healer: no Restoration, no grey dash",
      any("Restoration" in l or "HealingTouch" in l or "|cffb3b3b3-|r" in l for l in lines), False)
saved_rings = (G.worn[11], G.worn[12])
G.itemStats["shadow-ring-2"] = rt.eval('{ ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = 14 }')
G.itemLoc["shadow-ring-2"] = "INVTYPE_FINGER"
G.worn[11], G.worn[12] = "shadow-ring", None
G.playerClass = "WARLOCK"
wl = [l[1] for l in si.TooltipLines("shadow-ring-2").values()]
wl = wl[:wl.index("Against an empty slot")]  # the comparison with the worn ring (the other finger is empty)
check("a warlock: four builds, two to a line",
      [l.count("|TInterface\\Icons\\") for l in wl if ": " in l], [2, 2])
healers = {}
for cls, healer in (("PRIEST", "Holy"), ("SHAMAN", "Restoration"), ("PALADIN", "Holy"), ("DRUID", "Restoration")):
    G.playerClass = cls
    seen = False
    for mode in (True, False):
        si.settings.icons = mode
        seen = seen or any(healer + ":" in x[1] for x in si.TooltipLines("shadow-ring-2").values())
    healers[cls] = seen
si.settings.icons = True
check("  and no class without a healer spec shows one, nor druid's Restoration for a shadow ring "
      "(it has no healing stats), with icons or in words", healers,
      {"PRIEST": False, "SHAMAN": False, "PALADIN": False, "DRUID": False})
G.playerClass = "PRIEST"
pr = [l[1] for l in si.TooltipLines("shadow-ring-2").values()]
pr = pr[:pr.index("Against an empty slot")]
check("  a priest's shadow damage: Shadow and Smite on one line",
      [l.count("|TInterface\\Icons\\") for l in pr if ": " in l], [2])
G.worn[11], G.worn[12] = saved_rings
G.playerClass = "DRUID"
G.itemStats["sta-only"] = rt.eval('{ ITEM_MOD_STAMINA_SHORT = 4 }')
G.itemLoc["sta-only"] = "INVTYPE_CHEST"
G.worn[5] = None
lines = [l[1] for l in si.TooltipLines("sta-only").values()]
check("a Stamina item for a bear, nothing worn: empty slot caps both ways",
      any("Bear: |cff4dff4d>300% better for survival|r, |cffff5959<-300% worse for threat gen.|r" in l
          for l in lines), True)
check("  a spec it changes nothing for is left out (Balance), and so is Cat",
      (any("Balance" in l for l in lines), any("Cat:" in l for l in lines)), (False, False))
G.itemStats["str-only"] = rt.eval('{ ITEM_MOD_STRENGTH_SHORT = 3 }')
G.itemLoc["str-only"] = "INVTYPE_CHEST"
lines = [l[1] for l in si.TooltipLines("str-only").values()]
check("a tank's number that stays the same is left out: Strength, no survival for the bear",
      (any("better for threat" in l for l in lines), any("survival" in l for l in lines)), (True, False))
G.itemStats["spirit-only"] = rt.eval('{ ITEM_MOD_SPIRIT_SHORT = 2 }')
G.itemLoc["spirit-only"] = "INVTYPE_CHEST"
lines = [l[1] for l in si.TooltipLines("spirit-only").values()]
check("an item that changes nothing for any spec: no divider, no ratings",
      any("Divider" in l or "Bear" in l for l in lines), False)
G.worn[5] = "hide-a"
G.worn[5] = None
lines = [l[1] for l in si.TooltipLines("hide-b").values()]
check("  nothing to compare with: empty slot caps",
      any(">300%" in l for l in lines), True)
check("    each such spec on a line of its own (Bear, Cat)",
      [l.count("Icons") for l in lines if ": " in l and "Icons" in l],
      [1, 1])
G.worn[5] = "hide-a"
lines = [l[1] for l in si.TooltipLines("hide-b", True).values()]
check("the game showing its own comparison: the differences are not repeated, what they give is",
      (lines[0], "Beweglichkeit" in lines[1], "INV_Chest_Chain_05" in lines[1]), ("Against ?", False, True))
G.worn[5] = None
lines = [l[1] for l in si.TooltipLines("hide-b").values()]
check("  nor against an empty slot, where they are the item's own stats",
      (lines[0], "Beweglichkeit" in lines[1]), ("Against an empty slot", False))
G.worn[5] = "hide-a"
si.settings.icons = False
lines = [l[1] for l in si.TooltipLines("hide-b", True).values()]
check("  in words: each stat once, with what it gives, green up",
      lines[1].startswith("  |cff4dff4d+3 Beweglichkeit|r: |cff4dff4d+6 armor|r"), True)
check("  and a stat that gives nothing named is left to the game's comparison",
      any(l.startswith("  +2 Ausdauer") and ":" not in l for l in lines), False)
si.settings.icons = True
si.settings.specs = False
check("  the ratings switched off: no divider",
      any("Divider" in l for l in [x[1] for x in si.TooltipLines("hide-b").values()]), False)
si.settings.icons, si.settings.specs = False, False
G.worn[5] = None

# ---------------------------------------------------------------------------------------------
print("-- StatsInfo: what the 0.7.0 reviews found")
saved = {slot: G.worn[slot] for slot in (5, 7, 11, 12, 16, 17)}
saved_icons, saved_specs = si.settings.icons, si.settings.specs
si.settings.specs, si.settings.icons = True, False
for slot in saved: G.worn[slot] = None
def words(link, compares=False):
    return [x[1] for x in si.TooltipLines(link, compares).values()]

# the generator: a weight inside its own 90% interval is left out, the reference stat never is
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location("make_weights", str(ROOT / "tools" / "make_weights.py"))
mw = _ilu.module_from_spec(_spec); _spec.loader.exec_module(mw)
check("the generator drops a weight smaller than its interval (0.015 +- 0.066), keeps a larger one and the reference",
      (mw.significant({"X": [0.015, 0.066]}, "X", "Y"), mw.significant({"X": [0.2, 0.066]}, "X", "Y"),
       mw.significant({"X": [0.015, 0.066]}, "X", "X")), (0, 0.2, 0.015))
check("  and Weights.lua carries that out: a Protection warrior's survival has no Haste (0.011 +- 0.020), "
      "but its Stamina (11.27 Armor)", (W.WARRIOR[1].survival.weights.ITEM_MOD_HASTE_RATING_SHORT,
       W.WARRIOR[1].survival.weights.ITEM_MOD_STAMINA_SHORT), (None, 11.2681))

# the percentage's guards, each on its own
G.playerClass = "DRUID"
G.ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "Armor Penetration"
G.itemStats["pen5"] = rt.eval('{ ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = 5 }')
G.itemStats["pen6"] = rt.eval('{ ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = 6 }')
G.itemStats["agi2"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 2 }')
G.itemStats["agi20"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 20 }')
for k in ("pen5", "pen6", "agi2", "agi20"): G.itemLoc[k] = "INVTYPE_CHEST"
check("worn worth 0.70 to a cat, +20%: a percentage",
      pts(si.SpecRatings("pen6", rt.table_from(["pen5"])), "Cat"), 20.0)
check("worn worth 2, +900%: capped", pts(si.SpecRatings("agi20", rt.table_from(["agi2"])), "Cat"),
      300)

# an item worth nothing or less: capped percent, "195% worse" and "100% worse" are legal
G.itemStats["agi-ring"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 5 }')
G.itemStats["sta-ring"] = rt.eval('{ ITEM_MOD_STAMINA_SHORT = 12 }')
G.itemLoc["agi-ring"], G.itemLoc["sta-ring"] = "INVTYPE_FINGER", "INVTYPE_FINGER"
G.worn[11] = "agi-ring"
lines = words("sta-ring")
check("a Stamina ring against an Agility ring: Bear caps survival, threat and Cat read as percents",
      ("  Bear: |cff4dff4d>300% better for survival|r, |cffff5959195% worse for threat gen.|r"
       in lines, "  Cat: |cffff5959100% worse dmg spec|r" in lines), (True, True))
check("  no uncapped percent past the cap", [l for l in lines if "3000%" in l or "29817%" in l], [])
G.worn[11] = None

# worse as a percentage, the one decimal under 10, and the choice made after rounding
G.worn[5] = "hide-b"
check("a worse item as a percentage: 'Cat: 38% worse dmg spec', in red",
      "  Cat: |cffff595938% worse dmg spec|r" in words("hide-a"), True)
G.itemStats["agi251"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 251 }')
G.itemStats["agi276"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 276 }')
G.itemLoc["agi251"], G.itemLoc["agi276"] = "INVTYPE_CHEST", "INVTYPE_CHEST"
G.worn[5] = "agi251"
check("  +9.96% reads '10% better dmg spec', not '10.0% better'",
      "  Cat: |cff4dff4d10% better dmg spec|r" in words("agi276"), True)
G.worn[5] = None
G.playerClass = "WARRIOR"
G.worn[16], G.worn[17] = "mh40", "oh40"
lines = words("2h60")
check("  under 10%: one decimal ('Fury: 8.5% worse dmg spec'), from 10 up whole ('Arms: 50% better dmg spec')",
      ("  Fury: |cffff59598.5% worse dmg spec|r" in lines, "  Arms: |cff4dff4d50% better dmg spec|r" in lines), (True, True))
G.worn[16], G.worn[17] = None, None

# an item worth under a point, where the worn one is worth more: ~100% worse, a legal percent
G.playerClass = "WARRIOR"
G.itemStats["agi-1h"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 5, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 }')
G.itemStats["sta-shield"] = rt.eval('{ ITEM_MOD_STAMINA_SHORT = 5 }')
G.itemStats["str-2h"] = rt.eval('{ ITEM_MOD_STRENGTH_SHORT = 8, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 18 }')
G.itemLoc["agi-1h"], G.itemLoc["sta-shield"], G.itemLoc["str-2h"] = "INVTYPE_WEAPON", "INVTYPE_SHIELD", "INVTYPE_2HWEAPON"
G.worn[16], G.worn[17] = "agi-1h", "sta-shield"
lines = words("str-2h")
check("a two-hander worth 0.05 to Protection's survival against a sword and shield worth 73: ~100% worse",
      (any("Protection:" in l and "% worse for survival" in l for l in lines),
       any("like -" in l or "like +" in l for l in lines)), (True, False))
G.worn[16], G.worn[17] = None, None
G.playerClass = "DRUID"

# worn chest empty: cap, no "+8" currency
check("a cat's 8 Agility against an empty slot: '>300% better dmg spec', not '+8'",
      ("  Cat: |cff4dff4d>300% better dmg spec|r" in words("hide-b"),
       any("like +" in l for l in words("hide-b"))), (True, False))

# icon mode: the armor icon's total holds the item's own armor
G.RESISTANCE0_NAME = "Rüstung"
G.itemStats["chest-200"] = rt.eval('{ RESISTANCE0_NAME = 200, ITEM_MOD_AGILITY_SHORT = 10 }')
G.itemStats["chest-250"] = rt.eval('{ RESISTANCE0_NAME = 250, ITEM_MOD_AGILITY_SHORT = 14 }')
G.itemLoc["chest-200"], G.itemLoc["chest-250"] = "INVTYPE_CHEST", "INVTYPE_CHEST"
G.worn[5] = "chest-200"
si.settings.icons = True
lines = words("chest-250")
check("icon mode: the armor icon's total is the item's armor and Agility's together (+50 and +8 = +58)",
      (any("|cff4dff4d+58 armor|r" in l for l in lines), any("|cff4dff4d+8 armor|r" in l for l in lines)), (True, False))
G.RESISTANCE0_NAME = None
G.worn[5] = None

# icon mode keeps the class's spec order when a long rating comes between two short ones
if not G.ITEM_MOD_INTELLECT_SHORT: G.ITEM_MOD_INTELLECT_SHORT = "Intelligenz"
G.itemStats["agi-chest"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 10 }')
G.itemStats["str-int-chest"] = rt.eval('{ ITEM_MOD_STRENGTH_SHORT = 30, ITEM_MOD_INTELLECT_SHORT = 10 }')
G.itemLoc["agi-chest"], G.itemLoc["str-int-chest"] = "INVTYPE_CHEST", "INVTYPE_CHEST"
G.worn[5] = "agi-chest"
lines = words("str-int-chest")
order = [name for l in lines for name in ("Bear", "Cat", "Balance") if name + ":" in l]
check("icon mode: the specs in the class's order (Bear, Cat, Balance) though Cat is short and Balance long",
      order, ["Bear", "Cat", "Balance"])
G.worn[5] = None
si.settings.icons = False

# weapons: an off-hand weapon at the off-hand weight; a one-hand weapon into an empty main hand
G.playerClass = "ROGUE"
G.itemStats["oh-dagger"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 }')
G.itemLoc["oh-dagger"] = "INVTYPE_WEAPONOFFHAND"
c = si.Compare("oh-dagger")
check("an off-hand weapon: empty slot caps (Sinister Strike off-hand)",
      pts(si.SpecRatings("oh-dagger", c[1].against, c[1].slots, c[1].offHand), "Sinister Strike"), 300)
G.itemStats["dag40-a"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 }')
G.itemStats["dag40-b"] = rt.eval('{ ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40 }')
G.itemLoc["dag40-a"], G.itemLoc["dag40-b"] = "INVTYPE_WEAPON", "INVTYPE_WEAPON"
G.worn[17] = "dag40-a"
c = si.Compare("dag40-b")
check("a one-hand weapon with the main hand empty and a dagger in the off hand: against the empty main hand",
      (len(c), len(c[1].against), c[1].offHand), (1, 0, False))
check("  so an identical dagger caps against the empty main hand",
      pts(si.SpecRatings("dag40-b", c[1].against, c[1].slots, c[1].offHand), "Sinister Strike"), 300)
G.worn[17] = None

# no healer line in any class, on an item each class's specs rate
G.itemStats["mixed"] = rt.eval('{ ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_AGILITY_SHORT = 5, ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = 5 }')
G.itemLoc["mixed"] = "INVTYPE_CHEST"
seen = {}
for cls, healer in (("PRIEST", "Holy"), ("SHAMAN", "Restoration"), ("PALADIN", "Holy"), ("DRUID", "Restoration")):
    G.playerClass = cls
    for mode in (True, False):
        si.settings.icons = mode
        lines = words("mixed")
        seen[(cls, mode)] = (any("Divider" in l for l in lines), any(healer + ":" in l for l in lines))
check("no healer line for a strength/agility/shadow item, in any class (druid Restoration is rated only "
      "by healing stats), with icons and in words", set(seen.values()), {(True, False)})

# a capped percent is short, so pairs with the next one for damage specs too
si.settings.icons = True
G.playerClass = "WARLOCK"
lines = words("shadow-ring-2")
check("a warlock with both ring slots empty (two comparisons): short ratings pair up, two icons to a line",
      [l.count("|TInterface\\Icons\\") for l in lines if ": " in l], [2] * 4)

# the settings tab says once that healers are not rated, and when the cap replaces a percentage
def texts(f, out):
    if f.text: out.append(f.text)
    for ch in (f.children or {}).values(): texts(ch, out)
    return out
tab = " ".join(texts(BIT._pages["StatsInfo"], []))
check("the StatsInfo tab explains the healer heuristic and its exact weights, and when the cap replaces a percentage",
      ("at most triple" in tab, "1 x +Healing" in tab, "(approx.)" in tab, "Healers are not rated" in tab,
       "grey dash" in tab), (True, True, True, False, False))

for slot, link in saved.items(): G.worn[slot] = link
si.settings.icons, si.settings.specs = saved_icons, saved_specs
G.playerClass = "DRUID"

# ---------------------------------------------------------------------------------------------
print("-- StatsInfo: crit, spell crit and dodge from the game's own functions")
rt.execute("""
function GetCritChanceFromStat(stat, v) if stat == 2 then return v * 0.001 end return 0 end -- a fraction: 0.1% a point
function GetSpellCritChanceFromStat(stat, v) if stat == 4 then return v * 0.0006 end return 0 end
function GetDodgeChanceFromAttribute() return 24 * 0.0008 end -- what the 24 Agility below bring: 0.08% a point
function UnitHPPerStamina() return 10 end
function GetAttackPowerForStat(stat, n) if stat == 1 then return n end return 0 end -- a warlock's, as probed
function UnitStat(_, i)
    if i == 2 then return 24, 24, 0, 0 elseif i == 4 then return 33, 33, 0, 0 elseif i == 5 then return 31, 31, 0, 0 end
    return 20, 22, 2, 0
end
""")
check("Agility: armor, and the game's crit and dodge", si.Worth("ITEM_MOD_AGILITY_SHORT", 5),
      "+10 armor, +0.50% crit, +0.40% dodge")
check("  less of it", si.Worth("ITEM_MOD_AGILITY_SHORT", -5), "-10 armor, -0.50% crit, -0.40% dodge")
check("Intellect: mana and the game's spell crit", si.Worth("ITEM_MOD_INTELLECT_SHORT", 3), "+45 mana, +0.18% spell crit")
rt.execute("function UnitHPPerStamina() return 12 end")
check("Stamina: the game's health per point", si.Worth("ITEM_MOD_STAMINA_SHORT", -2), "-24 health")
rt.execute("function GetSpellCritChanceFromStat() return 0 end")
check("no spell crit from Intellect (a warrior's): no spell crit line", si.Worth("ITEM_MOD_INTELLECT_SHORT", 3), "+45 mana")
G.itemStats["agi-cloak"] = rt.eval('{ ITEM_MOD_AGILITY_SHORT = 5 }')
G.itemLoc["agi-cloak"] = "INVTYPE_CLOAK"
G.worn[15] = None
cloak = [l[1] for l in si.TooltipLines("agi-cloak").values()]
check("  and the item tooltip shows them (an empty slot: the stat and what it gives on one line)",
      "  |cff4dff4d+5 Beweglichkeit|r: |cff4dff4d+10 armor|r, |cff4dff4d+0.50% crit|r, |cff4dff4d+0.40% dodge|r" in cloak, True)
rt.execute("SECRET = {} function issecretvalue(v) return v == SECRET end function GetCritChanceFromStat() return SECRET end")
check("a secret answer (in combat): that line is left out", si.Worth("ITEM_MOD_AGILITY_SHORT", 5), "+10 armor, +0.40% dodge")
rt.execute("function UnitHPPerStamina() return SECRET end function GetUnitMaxHealthModifier() return SECRET end")
check("SI-249: secret stamina in combat shows no health, not a fallback", si.Worth("ITEM_MOD_STAMINA_SHORT", 2), None)
rt.execute("issecretvalue = nil GetCritChanceFromStat = nil GetDodgeChanceFromAttribute = nil UnitHPPerStamina = nil function UnitHPPerStamina() return 10.5 end")
check("SI-250: -1 stamina at 10.5 health each rounds away from zero", si.Worth("ITEM_MOD_STAMINA_SHORT", -1), "-11 health")
rt.execute("function UnitHPPerStamina() return 10 end")
check("a client without them (Classic Era): no crit or dodge, health 10 a point",
      (si.Worth("ITEM_MOD_AGILITY_SHORT", 5), si.Worth("ITEM_MOD_STAMINA_SHORT", 2)), ("+10 armor", "+20 health"))
rt.execute("""
function GetCritChanceFromStat(stat, v) if stat == 2 then return v * 0.001 end return 0 end
function GetSpellCritChanceFromStat(stat, v) if stat == 4 then return v * 0.0006 end return 0 end
function GetDodgeChanceFromAttribute() return 24 * 0.0008 end
function UnitHPPerStamina() return 10 end
""")
G.playerClass = "DRUID"  # as the probe below expects

G.SlashCmdList.BATTLEINFOTOOL("probe")
probes = G.BattleInfoToolDB.probes
check("/bit probe records one probe", len(probes), 1)
check("  with the class, the functions this client has and the worn items",
      (probes[1]["class"], probes[1]["functions"]["UnitStat"], probes[1]["items"][11]["link"]), ("DRUID", "function", "ring-a"))
check("  and says so", any("probe 1 recorded" in m for m in chat(G)), True)
# SI-751: the tab's counter must refresh on click, not only on OnShow
BIT.OpenSettings("StatsInfo")
pageSI = BIT._pages["StatsInfo"]
contentSI = pageSI.content
btnSI, cntSI = None, None
for i in range(1, len(contentSI.children) + 1):
    c = contentSI.children[i]
    if getattr(c, "kind", None) == "Button" and getattr(c, "text", None) == "Record the probe":
        btnSI = c
    if getattr(c, "kind", None) == "CreateFontString" and isinstance(getattr(c, "text", None), str) and "recorded so far" in c.text:
        cntSI = c
check("SI-751: probe button and counter found on the tab", (btnSI is not None, cntSI is not None), (True, True))
btnSI.scripts["OnClick"](btnSI)
check("SI-751: clicking Record updates the counter at once", cntSI.text, "2 recorded so far")
check("  with the game's crit, spell crit, dodge and health per point", (
    [round(x, 6) for x in probes[1]["values"]["GetCritChanceFromStat2_10"].values()],
    [round(x, 6) for x in probes[1]["values"]["GetSpellCritChanceFromStat4_10"].values()],
    list(probes[1]["values"]["UnitHPPerStamina"].values())), ([0.01], [0.006], [10]))

# ---------------------------------------------------------------------------------------------
print("-- the range mark's height from 0.1.0")
rt, G, BIT, _ = load(saved="BattleInfoToolDB = { modules = { Range = { offset = 2, size = 26 } } }")
G.Fire("ADDON_LOADED", "BattleInfoTool")
check("0.1.0's default height moves up over the debuff icons", BIT.modules["Range"].settings.offset, 22)
rt, G, BIT, _ = load(saved="BattleInfoToolDB = { modules = { Range = { offset = 10 } } }")
G.Fire("ADDON_LOADED", "BattleInfoTool")
check("a height the player chose stays", BIT.modules["Range"].settings.offset, 10)
rt, G, BIT, _ = load(saved="BattleInfoToolDB = { modules = { Range = { offset = 2, version = 2 } } }")
G.Fire("ADDON_LOADED", "BattleInfoTool")
check("2 chosen after the move stays too", BIT.modules["Range"].settings.offset, 2)

# ---------------------------------------------------------------------------------------------
print("-- DoTInfo's settings persist under their current names")
rt, G, BIT, _ = load(saved="BattleInfoToolDB = { modules = { DoTInfo = { enabled = false } } }")
G.Fire("ADDON_LOADED", "BattleInfoTool")
check("the switch saved under its current name comes along", BIT.state["DoTInfo"], "off")
rt, G, BIT, _ = load(saved="BattleInfoTool_DoTInfoDB = { fillTexture = 'dots', log = {} }")
G.Fire("ADDON_LOADED", "BattleInfoTool")
check("settings saved in BattleInfoTool_DoTInfoDB come along unchanged",
      G.BattleInfoTool_DoTInfoDB.fillTexture, "dots")
check("/dotinfo is DoTInfo's command", (G.SLASH_BITDOTINFO1, G.SlashCmdList.BITDOTINFO is not None), ("/dotinfo", True))
G.SlashCmdList.BITDOTINFO("help")
check("its messages say DoTInfo", any("DoTInfo" in m for m in chat(G)), True)
check("  and its help shows /dotinfo, never /did", (any("/dotinfo line" in m for m in chat(G)),
      any("/did" in m for m in chat(G))), (True, False))

# ---------------------------------------------------------------------------------------------
print("-- a module switched off")
rt, G, BIT, _ = load(saved="BattleInfoToolDB = { modules = { SpellDamageInfo = { enabled = false } } }")
G.Fire("ADDON_LOADED", "BattleInfoTool")
G.Fire("PLAYER_LOGIN")
check("SpellDamageInfo is off", BIT.state["SpellDamageInfo"], "off")
check("  its settings were never made", G.BattleInfoTool_SpellDamageInfoDB, None)
check("  the others run", [BIT.state[n] for n in ("DoTInfo", "StatsInfo", "ResourceDing", "Range")], ["on"] * 4)
G.SlashCmdList.SPELLDAMAGEINFO("")
check("  /sdi says it is switched off", any("SpellDamageInfo is switched off" in m for m in chat(G)), True)
BIT.OpenSettings("SpellDamageInfo")
check("  its tab says how to switch it on instead of building settings", BIT._pages["SpellDamageInfo"].offNote is not None, True)

# ---------------------------------------------------------------------------------------------
print("-- StatsInfo and Range switched off")
rt, G, BIT, _ = load(saved="BattleInfoToolDB = { modules = { StatsInfo = { enabled = false }, Range = { enabled = false } } }")
G.Fire("ADDON_LOADED", "BattleInfoTool")
G.Fire("PLAYER_LOGIN")
check("both are off", (BIT.state["StatsInfo"], BIT.state["Range"]), ("off", "off"))
check("  StatsInfo hooked no tooltip", G.GameTooltip.scripts.OnTooltipSetItem, None)
check("  Range made no icon and no updater", (BIT.modules["Range"]._icon(), BIT.modules["Range"]._driver()), (None, None))
check("  nor hooked the action bar", G.hooks["ActionButton_UpdateRangeIndicator"], None)

# ---------------------------------------------------------------------------------------------
print("-- a standalone addon enabled: ignored, BIT runs anyway")
rt, G, BIT, _ = load(standalone=("ResourceDing",))
G.Fire("ADDON_LOADED", "BattleInfoTool")
G.Fire("PLAYER_LOGIN")
check("ResourceDing stays on despite the standalone addon", BIT.state["ResourceDing"], "on")
check("DoTInfo stays on despite the standalone addon", BIT.state["DoTInfo"], "on")
check("  both made their settings here", (G.BattleInfoTool_ResourceDingDB is not None, G.BattleInfoTool_DoTInfoDB is not None), (True, True))
check("  ResourceDing's dots started", BIT.modules["ResourceDing"]._dotsRow() is not None, True)
check("  DoTInfo's nameplate updater running", BIT.modules["DoTInfo"].off, None)
check("SpellDamageInfo, enabled on other characters only, still runs", BIT.state["SpellDamageInfo"], "on")

# ---------------------------------------------------------------------------------------------
print("-- a standalone addon that loads anyway: ignored, BIT runs anyway")
rt, G, BIT, _ = load()
G.Fire("ADDON_LOADED", "BattleInfoTool")
G.loaded["ResourceDing"] = True  # enabled for this character after all, or loaded some other way
G.Fire("PLAYER_LOGIN")
check("no standalone warning at login", any("as its own addon" in m for m in chat(G)), False)

# ---------------------------------------------------------------------------------------------
print("-- DOT-2: combo cache must not survive a target change")
rt2, G2, BIT2, _ = load()
G2.Fire("ADDON_LOADED", "BattleInfoTool")
G2.Fire("PLAYER_LOGIN")
G2.spellNames[1079] = "Rip"
G2.spellDesc[1079] = "Finishing move that deals damage over time. 1 point : 243 damage over 12 sec. 2 points: 396 damage over 12 sec. 3 points: 549 damage over 12 sec. 4 points: 702 damage over 12 sec. 5 points: 855 damage over 12 sec."
G2.target = rt2.eval("{ hostile = true }")
rt2.execute("units['target'] = { guid = 'Mob-B-1' }")
G2.comboPoints = 5
G2.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
G2.Advance(1)
G2.Fire("PLAYER_TARGET_CHANGED")
G2.comboPoints = 0
G2.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-1", 1079)
G2.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1079)
log2 = [G2.BattleInfoTool_DoTInfoDB.log[i] for i in range(1, len(G2.BattleInfoTool_DoTInfoDB.log) + 1)]
check("a finisher on a fresh target must not reuse the points cached on the old one", any("5 combo points (cached)" in l for l in log2), False)

# ---------------------------------------------------------------------------------------------
print("-- DOT-1: a cast must land on the mob it was aimed at, not the current target")
rt1, G1, BIT1, _ = load()
G1.Fire("ADDON_LOADED", "BattleInfoTool")
G1.Fire("PLAYER_LOGIN")
G1.spellNames[172] = "Verderbnis"
G1.spellDesc[172] = "Corrupts the target, causing 40 Shadow damage over 12 sec."
G1.target = rt1.eval("{ hostile = true }")
rt1.execute("units['target'] = { guid = 'Mob-A-1' }")
G1.Fire("UNIT_SPELLCAST_START", "player", "Cast-9", 172)
G1.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-9", 172)
rt1.execute("units['target'] = { guid = 'Mob-B-2' }")
G1.Fire("PLAYER_TARGET_CHANGED")
G1.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 172)
brk, tot = BIT1.modules["DoTInfo"].dotBreakdownForUnit("target")
check("the DoT lands on the cast target, not the tabbed-to mob", int(tot), 0)

# ---------------------------------------------------------------------------------------------
print("-- DOT-3: a white hit must not become tick 1 of an unsure bleed")
rt3, G3, BIT3, _ = load()
G3.Fire("ADDON_LOADED", "BattleInfoTool")
G3.Fire("PLAYER_LOGIN")
G3.spellNames[1079] = "Rip"
G3.spellDesc[1079] = "Finishing move that deals damage over time. 1 point : 243 damage over 12 sec. 2 points: 396 damage over 12 sec. 3 points: 549 damage over 12 sec. 4 points: 702 damage over 12 sec. 5 points: 855 damage over 12 sec."
G3.target = rt3.eval("{ hostile = true }")
rt3.execute("units['target'] = { guid = 'Mob-A-1' }")
G3.comboPoints = 5
G3.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-3", 1079)
G3.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 1079)
G3.Advance(1.7)
G3.Fire("UNIT_COMBAT", "target", "WOUND", None, 31, 1)
brk3, tot3 = BIT3.modules["DoTInfo"].dotBreakdownForUnit("target")
check("a white hit is not tick 1 of an unsure bleed", int(tot3), 855)
# positive control: the real ticks right after must still be taken
G3.Advance(0.3)
G3.Fire("UNIT_COMBAT", "target", "WOUND", None, 142, 1)
G3.Advance(2)
G3.Fire("UNIT_COMBAT", "target", "WOUND", None, 142, 1)
brk3b, tot3b = BIT3.modules["DoTInfo"].dotBreakdownForUnit("target")
check("  but real ticks on the rhythm are still taken", int(tot3b) > 0, True)

# ---------------------------------------------------------------------------------------------
print("-- F2: a same-slot swap must prefer the learned size over the description")
rt4, G4, BIT4, _ = load()
G4.Fire("ADDON_LOADED", "BattleInfoTool")
G4.Fire("PLAYER_LOGIN")
G4.spellNames[1122] = "Rupture"
G4.spellDesc[1122] = "Finishing move that deals damage over time. 1 point: 25 damage over 8 secs. 2 points: 40 damage over 10 secs. 3 points: 55 damage over 12 secs. 4 points: 71 damage over 14 secs. 5 points: 87 damage over 16 secs."
G4.target = rt4.eval("{ hostile = true }")
rt4.execute("units['target'] = { guid = 'Mob-A-1' }")
G4.comboPoints = 5
G4.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-4", 1122)
G4.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-4", 1122)
G4.Advance(2)
G4.Fire("UNIT_COMBAT", "target", "WOUND", None, 30, 1)
G4.Advance(2)
G4.Fire("UNIT_COMBAT", "target", "WOUND", None, 30, 1)
# a fresh cast on the same mob: first real tick, then a white hit in its slot
G4.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-5", 1122)
G4.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", 1122)
G4.Advance(2)
G4.Fire("UNIT_COMBAT", "target", "WOUND", None, 30, 1)
G4.Advance(0.1)
G4.Fire("UNIT_COMBAT", "target", "WOUND", None, 12, 1)
log4 = [G4.BattleInfoTool_DoTInfoDB.log[i] for i in range(1, len(G4.BattleInfoTool_DoTInfoDB.log) + 1)]
check("the white hit does not swap out the real tick against the learned size", any("SWAP" in l for l in log4), False)

# ---------------------------------------------------------------------------------------------
print("-- L11-1: a finisher reads the display when the count itself is secret")
rt5, G5, BIT5, _ = load()
G5.Fire("ADDON_LOADED", "BattleInfoTool")
G5.Fire("PLAYER_LOGIN")
G5.spellNames[1079] = "Rip"
G5.spellDesc[1079] = "Finishing move that deals damage over time. 1 point : 243 damage over 12 sec. 2 points: 396 damage over 12 sec. 3 points: 549 damage over 12 sec. 4 points: 702 damage over 12 sec. 5 points: 855 damage over 12 sec."
G5.target = rt5.eval("{ hostile = true }")
rt5.execute("units['target'] = { guid = 'Mob-A-1' }")
rt5.execute("""
ComboFrame = FakeMock("frame")
function ComboFrame:IsShown() return true end
for i = 1, 5 do
  local p = FakeMock("point")
  function p:IsShown() return true end
  p.Highlight = FakeMock("hl")
  function p.Highlight:GetAlpha() return 1 end
  _G["ComboPoint" .. i] = p
end
_G["ComboPoint6"] = FakeMock("point6")
""")
rt5.execute("SECRET = {} function issecretvalue(v) return v == SECRET end function GetComboPoints(u, t) return SECRET end function UnitPower(u, pt) return SECRET end")
G5.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-6", 1079)
G5.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-6", 1079)
log5 = [G5.BattleInfoTool_DoTInfoDB.log[i] for i in range(1, len(G5.BattleInfoTool_DoTInfoDB.log) + 1)]
check("the finisher takes the 5 lit points from the display, not unknown", any("5 combo points" in l for l in log5), True)

# ---------------------------------------------------------------------------------------------
print("-- F3: two foreign hits must not relearn a known tick size")
rt6, G6, BIT6, _ = load()
G6.Fire("ADDON_LOADED", "BattleInfoTool")
G6.Fire("PLAYER_LOGIN")
G6.spellNames[172] = "Verderbnis"
G6.spellDesc[172] = "Corrupts the target, causing 400 Shadow damage over 12 sec."
G6.target = rt6.eval("{ hostile = true }")
rt6.execute("units['target'] = { guid = 'Mob-A-1' }")
G6.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-7", 172)
G6.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-7", 172)
G6.Advance(3)
G6.Fire("UNIT_COMBAT", "target", "WOUND", None, 100, 32)
G6.Advance(3)
G6.Fire("UNIT_COMBAT", "target", "WOUND", None, 100, 32)
# fresh cast on the same mob; two foreign hits on its rhythm
G6.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-8", 172)
G6.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-8", 172)
G6.Advance(3)
G6.Fire("UNIT_COMBAT", "target", "WOUND", None, 500, 32)
G6.Advance(3)
G6.Fire("UNIT_COMBAT", "target", "WOUND", None, 500, 32)
log6 = [G6.BattleInfoTool_DoTInfoDB.log[i] for i in range(1, len(G6.BattleInfoTool_DoTInfoDB.log) + 1)]
check("two foreign hits do not relearn the known size", any("RELEARN" in l for l in log6), False)
# the real size right after must still be taken
G6.Advance(3)
G6.Fire("UNIT_COMBAT", "target", "WOUND", None, 100, 32)
log6b = [G6.BattleInfoTool_DoTInfoDB.log[i] for i in range(1, len(G6.BattleInfoTool_DoTInfoDB.log) + 1)]
check("  and the real tick still lands afterwards", any("TICK Verderbnis 100" in l for l in log6b), True)

# ---------------------------------------------------------------------------------------------
print("-- UI-1: recycling a plate must not leave a second widget set behind")
rt7, G7, BIT7, _ = load()
G7.Fire("ADDON_LOADED", "BattleInfoTool")
G7.Fire("PLAYER_LOGIN")
G7.spellNames[172] = "Verderbnis"
G7.spellDesc[172] = "Corrupts the target, causing 40 Shadow damage over 12 sec."
G7.target = rt7.eval("{ hostile = true }")
rt7.execute("units['target'] = { guid = 'Mob-A-1', health = 500, max = 500 }")
rt7.execute("units['nameplate1'] = { guid = 'Mob-A-1', health = 500, max = 500 }")
G7.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-10", 172)
G7.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-10", 172)
G7.plate = rt7.eval("NewPlate()")
G7.Tick(0.2)
G7.Tick(0.2)
n1 = rt7.eval("#AllFrames")
rt7.execute("plate.UnitFrame.healthBar = FakeMock('plateBar2', plate)")
G7.Tick(0.2)
G7.Tick(0.2)
n2 = rt7.eval("#AllFrames")
check("recycling the health bar adds no second widget set (one frame for the bar itself at most)", int(n2) - int(n1) <= 1, True)

# ---------------------------------------------------------------------------------------------
print("-- UI-2: a dead mob's plate must hide the marker at once, not until expiry")
rt8, G8, BIT8, _ = load()
G8.Fire("ADDON_LOADED", "BattleInfoTool")
G8.Fire("PLAYER_LOGIN")
G8.spellNames[172] = "Verderbnis"
G8.spellDesc[172] = "Corrupts the target, causing 40 Shadow damage over 12 sec."
G8.target = rt8.eval("{ hostile = true }")
rt8.execute("units['target'] = { guid = 'Mob-A-1', health = 500, max = 500 }")
rt8.execute("units['nameplate1'] = { guid = 'Mob-A-1', health = 500, max = 500 }")
G8.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-11", 172)
G8.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-11", 172)
G8.plate = rt8.eval("NewPlate()")
G8.Tick(0.2)
G8.Tick(0.2)
rt8.execute("units['target'].dead = true units['target'].health = 0 units['nameplate1'].dead = true units['nameplate1'].health = 0 units['nameplate1'].max = 0")
G8.Tick(0.2)
G8.Tick(0.2)
shown_markers = rt8.eval("""(function()
  local n = 0
  for _, c in ipairs(plate.children) do
    if c.kind == "StatusBar" and c.shown then n = n + 1 end
  end
  return n
end)()""")
check("no marker left shown on the corpse plate", int(shown_markers), 0)

# ---------------------------------------------------------------------------------------------
print("-- F1: two same-school ticks in one frame must feed two DoTs, not one")
rt9, G9, BIT9, _ = load()
G9.Fire("ADDON_LOADED", "BattleInfoTool")
G9.Fire("PLAYER_LOGIN")
G9.spellNames[172] = "Corruption"
G9.spellDesc[172] = "Corrupts the target, causing 400 Shadow damage over 12 sec."
G9.spellNames[348] = "Siphon Life"
G9.spellDesc[348] = "Transfers 400 Shadow damage over 12 sec."
G9.target = rt9.eval("{ hostile = true }")
rt9.execute("units['target'] = { guid = 'Mob-A-1', health = 500, max = 500 }")
G9.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-20", 172)
G9.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-20", 172)
G9.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-21", 348)
G9.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-21", 348)
G9.Advance(3)
G9.Fire("UNIT_COMBAT", "target", "WOUND", None, 100, 32)
G9.Fire("UNIT_COMBAT", "target", "WOUND", None, 100, 32)
log9 = [G9.BattleInfoTool_DoTInfoDB.log[i] for i in range(1, len(G9.BattleInfoTool_DoTInfoDB.log) + 1)]
ticks9 = [l for l in log9 if "TICK " in l and " 100 " in l]
check("both DoTs eat (two ticks, one per DoT)", len(ticks9), 2)

# ---------------------------------------------------------------------------------------------
print("-- L-10: combo cache must not survive death + rez (same root as DOT-2)")
rt10, G10, BIT10, _ = load()
G10.Fire("ADDON_LOADED", "BattleInfoTool")
G10.Fire("PLAYER_LOGIN")
G10.spellNames[1079] = "Rip"
G10.spellDesc[1079] = "Finishing move that deals damage over time. 1 point : 243 damage over 12 sec. 2 points: 396 damage over 12 sec. 3 points: 549 damage over 12 sec. 4 points: 702 damage over 12 sec. 5 points: 855 damage over 12 sec."
G10.target = rt10.eval("{ hostile = true }")
rt10.execute("units['target'] = { guid = 'Mob-A-1' }")
G10.comboPoints = 5
G10.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
G10.Advance(0.5)
rt10.execute("units['target'].dead = true")
G10.Fire("PLAYER_TARGET_CHANGED")
rt10.execute("units['target'] = { guid = 'Mob-B-2' }")
G10.Fire("PLAYER_TARGET_CHANGED")
G10.Advance(1.9)
G10.comboPoints = 0
G10.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-30", 1079)
G10.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-30", 1079)
log10 = [G10.BattleInfoTool_DoTInfoDB.log[i] for i in range(1, len(G10.BattleInfoTool_DoTInfoDB.log) + 1)]
check("a finisher after death+rez on a fresh target must not reuse the old points", any("5 combo points (cached)" in l for l in log10), False)

# ---------------------------------------------------------------------------------------------
print("-- L07-2: widget count must not grow on repeated plate recycles (same root as UI-1)")
rt11, G11, BIT11, _ = load()
G11.Fire("ADDON_LOADED", "BattleInfoTool")
G11.Fire("PLAYER_LOGIN")
G11.spellNames[172] = "Verderbnis"
G11.spellDesc[172] = "Corrupts the target, causing 40 Shadow damage over 12 sec."
G11.target = rt11.eval("{ hostile = true }")
rt11.execute("units['target'] = { guid = 'Mob-A-1', health = 500, max = 500 }")
rt11.execute("units['nameplate1'] = { guid = 'Mob-A-1', health = 500, max = 500 }")
G11.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-31", 172)
G11.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-31", 172)
G11.plate = rt11.eval("NewPlate()")
G11.Tick(0.2)
G11.Tick(0.2)
m1 = rt11.eval("#AllFrames")
rt11.execute("plate.UnitFrame.healthBar = FakeMock('plateBar2', plate)")
G11.Tick(0.2)
G11.Tick(0.2)
m2 = rt11.eval("#AllFrames")
rt11.execute("plate.UnitFrame.healthBar = FakeMock('plateBar3', plate)")
G11.Tick(0.2)
G11.Tick(0.2)
m3 = rt11.eval("#AllFrames")
check("two recycles add no growing widget sets (second recycle adds only the bar mock itself)", int(m3) - int(m2) <= 1, True)

# ---------------------------------------------------------------------------------------------
print("-- UI-3: showMarkers=false must hide the kill icon too, not only the marker")
rtU3, GU3, BITU3, _ = load()
GU3.Fire("ADDON_LOADED", "BattleInfoTool")
GU3.Fire("PLAYER_LOGIN")
GU3.spellNames[172] = "Verderbnis"
GU3.spellDesc[172] = "Corrupts the target, causing 40 Shadow damage over 12 sec."
GU3.target = rtU3.eval("{ hostile = true }")
rtU3.execute("units['target'] = { guid = 'Mob-A-1', health = 500, max = 500 }")
rtU3.execute("units['nameplate1'] = { guid = 'Mob-A-1', health = 500, max = 500 }")
rtU3.execute("BattleInfoTool_DoTInfoDB.showMarkers = false")
rtU3.execute("BattleInfoTool_DoTInfoDB.nameplateMode = 'markerIcon'")
GU3.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-60", 172)
GU3.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-60", 172)
GU3.plate = rtU3.eval("NewPlate()")
GU3.Tick(0.2)
GU3.Tick(0.2)
visU3 = rtU3.eval("""(function()
  local marker, icon = 0, 0
  for _, c in ipairs(plate.children) do
    if c.kind == "StatusBar" and c.shown then marker = marker + 1 end
    if c.kind == "Frame" and c.shown and c ~= plate.UnitFrame then icon = icon + 1 end
  end
  return marker .. "/" .. icon
end)()""")
check("showMarkers=false hides the marker on the plate", str(visU3).split("/")[0], "0")
check("  and the kill icon too", str(visU3).split("/")[1], "0")

# ---------------------------------------------------------------------------------------------
print("-- F4: two partial-resist ticks must not relearn the known size down")
rtF4, GF4, BITF4, _ = load()
GF4.Fire("ADDON_LOADED", "BattleInfoTool")
GF4.Fire("PLAYER_LOGIN")
GF4.spellNames[172] = "Verderbnis"
GF4.spellDesc[172] = "Corrupts the target, causing 400 Shadow damage over 12 sec."
GF4.target = rtF4.eval("{ hostile = true }")
rtF4.execute("units['target'] = { guid = 'Mob-A-1' }")
GF4.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-50", 172)
GF4.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-50", 172)
GF4.Advance(3)
GF4.Fire("UNIT_COMBAT", "target", "WOUND", None, 100, 32)
GF4.Advance(3)
GF4.Fire("UNIT_COMBAT", "target", "WOUND", None, 100, 32)
# fresh cast on the same mob; two partial-resist ticks (60) on its rhythm
GF4.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-51", 172)
GF4.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-51", 172)
GF4.Advance(3)
GF4.Fire("UNIT_COMBAT", "target", "WOUND", None, 60, 32)
GF4.Advance(3)
GF4.Fire("UNIT_COMBAT", "target", "WOUND", None, 60, 32)
logF4 = [GF4.BattleInfoTool_DoTInfoDB.log[i] for i in range(1, len(GF4.BattleInfoTool_DoTInfoDB.log) + 1)]
check("two partial ticks do not relearn the known size down", any("RELEARN" in l for l in logF4), False)
# a full-size tick right after must still be taken
GF4.Advance(3)
GF4.Fire("UNIT_COMBAT", "target", "WOUND", None, 100, 32)
logF4b = [GF4.BattleInfoTool_DoTInfoDB.log[i] for i in range(1, len(GF4.BattleInfoTool_DoTInfoDB.log) + 1)]
check("  and a full tick still lands afterwards", any("TICK Verderbnis 100" in l for l in logF4b), True)

# ---------------------------------------------------------------------------------------------
print("-- UI-4: preview at 0 health must hide skull and marker, not draw a kill on a corpse")
rtU4, GU4, BITU4, _ = load()
GU4.Fire("ADDON_LOADED", "BattleInfoTool")
GU4.Fire("PLAYER_LOGIN")
didU4 = BITU4.modules["DoTInfo"]
rtU4.execute("previewHostU4 = { healthBar = FakeMock('phbU4'), portrait = FakeMock('ppU4'), layerFrame = FakeMock('plfU4') }")
rtU4.execute("previewDeadU4 = { health = 0, dots = { { name = 'Corruption', school = 32, damage = 45 } } }")
didU4.setPreviewState(rtU4.eval("previewDeadU4"))
didU4.setDisplayHost(rtU4.eval("previewHostU4"))
check("preview on a dead mock hides the kill icon", GU4.BattleInfoTool_DoTInfoSkull.shown, False)
check("  and the target marker too", GU4.BattleInfoTool_DoTInfoRemaining.shown, False)
rtU4.execute("plateU4 = NewPlate()")
rtU4.execute("plateHostU4 = { plate = plateU4, healthBar = plateU4.UnitFrame.healthBar }")
didU4.setPlatePreview(rtU4.eval("plateHostU4"), rtU4.eval("previewDeadU4"))
GU4.Tick(0.2)
GU4.Tick(0.2)
visU4 = rtU4.eval("""(function()
  local n = 0
  for _, c in ipairs(plateU4.children) do
    if c.shown and (c.kind == "StatusBar" or (c.kind == "Frame" and c ~= plateU4.UnitFrame)) then n = n + 1 end
  end
  return n
end)()""")
check("  and the nameplate preview stays empty", int(visU4), 0)

# ---------------------------------------------------------------------------------------------
print("-- UI-7: glow needs its outline: outline none + glow on must show no halo")
rtU7, GU7, BITU7, _ = load()
GU7.Fire("ADDON_LOADED", "BattleInfoTool")
GU7.Fire("PLAYER_LOGIN")
rtU7.execute("BattleInfoTool_DoTInfoDB.showGlow = true")
rtU7.execute("BattleInfoTool_DoTInfoDB.outlineStyle = 'none'")
GU7.Tick(0.2)
GU7.Tick(0.2)
glowU7 = rtU7.eval("""(function()
  local rem = BattleInfoTool_DoTInfoRemaining
  local found, shown = 0, 0
  for _, layer in ipairs(rem.children) do
    if layer.kind == "Frame" then
      local tex, s = 0, 0
      for _, c in ipairs(layer.children) do
        if c.kind == "CreateTexture" then tex = tex + 1 if c.shown then s = s + 1 end end
      end
      if tex == 8 then found, shown = tex, s end
    end
  end
  return found .. "/" .. shown
end)()""")
check("the outline layer is found (4 edges + 4 glows)", str(glowU7).split("/")[0], "8")
check("  and no halo shows without its outline", str(glowU7).split("/")[1], "0")

# ---------------------------------------------------------------------------------------------
print("-- DOT-6: absorbed ticks must not drop the DoT")
rtD6, GD6, BITD6, _ = load()
GD6.Fire("ADDON_LOADED", "BattleInfoTool")
GD6.Fire("PLAYER_LOGIN")
GD6.spellNames[172] = "Verderbnis"
GD6.spellDesc[172] = "Corrupts the target, causing 400 Shadow damage over 12 sec."
GD6.target = rtD6.eval("{ hostile = true }")
rtD6.execute("units['target'] = { guid = 'Mob-A-1' }")
GD6.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-60", 172)
GD6.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-60", 172)
GD6.Advance(3)
GD6.Fire("UNIT_COMBAT", "target", "WOUND", None, 100, 32)
GD6.Advance(3)
GD6.Fire("UNIT_COMBAT", "target", "WOUND", None, 100, 32)
GD6.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-61", 172)
GD6.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-61", 172)
GD6.Advance(3)
GD6.Fire("UNIT_COMBAT", "target", "ABSORB", None, 100, 32)
GD6.Advance(3)
GD6.Fire("UNIT_COMBAT", "target", "ABSORB", None, 100, 32)
GD6.Advance(1)
GD6.Tick(0.2)
brkD6, totD6 = BITD6.modules["DoTInfo"].dotBreakdownForUnit("target")
check("two absorbed ticks keep the DoT alive", int(totD6) > 0, True)

# ---------------------------------------------------------------------------------------------
print("-- DOT-5b: a cast with no target must leave a log line, not vanish silently")
rtD5, GD5, BITD5, _ = load()
GD5.Fire("ADDON_LOADED", "BattleInfoTool")
GD5.Fire("PLAYER_LOGIN")
GD5.spellNames[172] = "Verderbnis"
GD5.spellDesc[172] = "Corrupts the target, causing 400 Shadow damage over 12 sec."
GD5.target = None
GD5.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-70", 172)
GD5.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-70", 172)
logD5 = [GD5.BattleInfoTool_DoTInfoDB.log[i] for i in range(1, len(GD5.BattleInfoTool_DoTInfoDB.log) + 1)]
check("a cast with no target is logged, not silent", any("Cast-70" in l or "no target" in l for l in logD5), True)

# ---------------------------------------------------------------------------------------------
print("-- F5: a resisted cast is dropped (safe direction, locked - no prod change)")
rtF5, Gf5, BITf5, _ = load()
Gf5.Fire("ADDON_LOADED", "BattleInfoTool")
Gf5.Fire("PLAYER_LOGIN")
Gf5.spellNames[172] = "Corruption"
Gf5.spellDesc[172] = "Corrupts the target, causing 400 Shadow damage over 12 sec."
Gf5.target = rtF5.eval("{ hostile = true }")
rtF5.execute("units['target'] = { guid = 'Mob-A-1', health = 500, max = 500 }")
Gf5.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-40", 172)
Gf5.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-40", 172)
Gf5.Advance(0.1)
Gf5.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 1)
brkF5, totF5 = BITf5.modules["DoTInfo"].dotBreakdownForUnit("target")
check("a MISS right after the cast drops the fresh DoT", int(totF5), 0)
Gf5.Advance(1.0)
Gf5.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-41", 172)
Gf5.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-41", 172)
Gf5.Advance(3)
Gf5.Fire("UNIT_COMBAT", "target", "WOUND", None, 100, 32)
brkF5b, totF5b = BITf5.modules["DoTInfo"].dotBreakdownForUnit("target")
check("  and a real tick still lands on the next cast", int(totF5b) > 0, True)

# ---------------------------------------------------------------------------------------------
print("-- RD-1: a full target must not re-ding after tabbing away and back")
rtRD1, GRD1, BITRD1, _ = load()
GRD1.Fire("ADDON_LOADED", "BattleInfoTool")
GRD1.Fire("PLAYER_LOGIN")
GRD1.playerClass = "ROGUE"  # combo points on the target, as on Classic/Forever
GRD1.combat = True          # the combat-only default sounds in combat
rtRD1.execute("units['target'] = { guid = 'Mob-A-1' }")
GRD1.target = rtRD1.eval("{ hostile = true }")
GRD1.comboPoints = 5
GRD1.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
plays1 = len(GRD1.plays)
check("5/5 on the target plays one ding", plays1, 1)
# tab away to nothing: the points reset with the target
GRD1.comboPoints = 0
rtRD1.execute("units['target'] = nil")
GRD1.Fire("PLAYER_TARGET_CHANGED")
# tab back to the same mob, still on 5/5: nothing was earned, so no second ding
GRD1.comboPoints = 5
rtRD1.execute("units['target'] = { guid = 'Mob-A-1' }")
GRD1.Fire("PLAYER_TARGET_CHANGED")
plays2 = len(GRD1.plays)
check("back on the same full target: no second ding", plays2, 1)
# the finding's control: 4 -> 5 on the same target still dings exactly once
GRD1.comboPoints = 4
GRD1.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
GRD1.comboPoints = 5
GRD1.Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
plays3 = len(GRD1.plays)
check("  4 -> 5 on the same target dings exactly once", plays3 - plays2, 1)
# a secret GUID (Forever in combat) must never touch the per-target table:
# the client raises "cannot be indexed with secret keys" on every tick, so the
# test models the table with the same guard and fails if the code touches it.
# The sentinel is a secret STRING: that is what the client hands over. A table
# sentinel never reaches the leak -- usableGuid turns non-strings away before
# issecretvalue ever runs, so only a string proves the branch (8241 errors).
rtRDS, GRDS, BITRDS, _ = load(saved="""
SECRET_GUID = "SECRET-GUID-SENTINEL-8241"
function issecretvalue(v) return v == SECRET_GUID end
STRICT = setmetatable({}, {
  __index = function(t, k) if rawequal(k, SECRET_GUID) then error("attempted to index a table that cannot be indexed with secret keys") end return rawget(t, k) end,
  __newindex = function(t, k, v) if rawequal(k, SECRET_GUID) then error("attempted to index a table that cannot be indexed with secret keys") end rawset(t, k, v) end })
""")
GRDS.Fire("ADDON_LOADED", "BattleInfoTool")
GRDS.Fire("PLAYER_LOGIN")
GRDS.playerClass = "ROGUE"
GRDS.combat = True
rtRDS.execute("units['target'] = { guid = SECRET_GUID }")
GRDS.comboPoints = 5
rds = BITRDS.modules["ResourceDing"]
rds.wasFullBy = GRDS.STRICT
try:
    rds.CheckPower(False)
    raised = None
except Exception as e:
    raised = str(e)
check("RD-SECRET-GUID RED: a secret GUID never indexes the per-target table", raised, None)
check("  and the full bar still dings once", len(GRDS.plays), 1)
check("  and nothing was ever written into the latch", rtRDS.eval("next(STRICT) ~= nil"), False)
# without the detector the per-target latch must still work for a real GUID
# (the probe only refuses keys the client itself rejects, which lupa cannot model)
rtRDN, GRDN, BITRDN, _ = load()
GRDN.Fire("ADDON_LOADED", "BattleInfoTool")
GRDN.Fire("PLAYER_LOGIN")
GRDN.playerClass = "ROGUE"
GRDN.combat = True
rtRDN.execute("units['target'] = { guid = 'Mob-B-2' }")
GRDN.comboPoints = 5
rdn = BITRDN.modules["ResourceDing"]
rdn.CheckPower(False)
playsN1 = len(GRDN.plays)
rdn.CheckPower(False)
check("  with no issecretvalue: the same full target stays silent", (playsN1, len(GRDN.plays)), (1, 1))
rtRDN.execute("units['target'] = { guid = 'Mob-C-3' }")
rdn.CheckPower(False)
check("  and a new target re-dings (the latch is per-target, not plain)", len(GRDN.plays), 2)

# ---------------------------------------------------------------------------------------------
print("-- RD-3: one ComboFrame redraw looks at the display once, not once per hook")
# The Forever client draws the classic display: ComboFrame's OnEvent calls
# ComboFrame_Update (mirror 1.60.1/70009), and the addon hooks both -- one
# redraw reaches both hooks, and only one of them may do the look.
rtRD3, GRD3, BITRD3, _ = load(saved="""
ComboFrame = FakeMock("ComboFrame")
function ComboFrame:IsShown() return true end
ComboFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
ComboFrame:RegisterEvent("UNIT_POWER_FREQUENT")
function ComboFrame_Update(self) end
ComboFrame:SetScript("OnEvent", function(self, event, ...) ComboFrame_Update(self) end)
-- the half-second settle timers are kept, not run: they measure how many were scheduled
settleQueue = {}
C_Timer = { After = function(delay, fn)
        if delay > 0 then table.insert(settleQueue, fn) else fn() end
    end,
    NewTicker = function() return { Cancel = function() end } end }
""")
GRD3.Fire("ADDON_LOADED", "BattleInfoTool")
GRD3.Fire("PLAYER_LOGIN")
rd3 = BITRD3.modules["ResourceDing"]
queued0 = len(GRD3.settleQueue)
looks0 = int(rd3.looks or 0)
# one redraw: the frame's OnEvent runs and calls ComboFrame_Update; the hook on
# the function fires inside it, the frame's post-hook right after
GRD3.Fire("UNIT_POWER_FREQUENT", "player")
looks1 = int(rd3.looks or 0)
check("one redraw looks at the display once, not once per hook", looks1 - looks0, 1)
queued1 = len(GRD3.settleQueue)
check("  and schedules one settle look, not one per hook", queued1 - queued0, 1)
for i in range(queued0 + 1, queued1 + 1):
    GRD3.settleQueue[i]()
check("  the settle timer adds exactly one more look", int(rd3.looks or 0) - looks1, 1)

# ---------------------------------------------------------------------------------------------
print("-- L11-3: the nameplate poll stays within a per-second budget")
# The wave-11 finding: 40 nameplate slots polled every 0.1 s is 400 UnitExists/s for
# three plates -- the slots are asked one by one even though the marker only moves on
# DoT ticks (once a second or slower) and on health changes. Throttled to 0.2 s the
# poll must stay under 200 slots/s while the plates still draw.
rtL11, GL11, BITL11, _ = load()
GL11.Fire("ADDON_LOADED", "BattleInfoTool")
GL11.Fire("PLAYER_LOGIN")
GL11.spellNames[172] = "Verderbnis"
GL11.spellDesc[172] = "Corrupts the target, causing 40 Shadow damage over 12 sec."
rtL11.execute("""
units['target'] = { guid = 'Mob-A-1', health = 500, max = 500 }
platesL11 = {}
for i = 1, 3 do
  units['nameplate' .. i] = { guid = 'Mob-A-1', health = 500, max = 500 }
  platesL11[i] = NewPlate()
end
platesL11ByUnit = {}
for i = 1, 3 do platesL11ByUnit['nameplate' .. i] = platesL11[i] end
local realNP = C_NamePlate.GetNamePlateForUnit
C_NamePlate.GetNamePlateForUnit = function(u) return platesL11ByUnit[u] or realNP(u) end
platePolls = 0
local realUnitExists = UnitExists
function UnitExists(u)
  if type(u) == "string" and u:match("^nameplate") then platePolls = platePolls + 1 end
  return realUnitExists(u)
end
""")
GL11.target = rtL11.eval("{ hostile = true }")
GL11.Fire("UNIT_SPELLCAST_SENT", "player", "target", "Cast-L11", 172)
GL11.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-L11", 172)
for _ in range(10):
    GL11.Tick(0.1)
check("L11-3: one second polls the 40 nameplate slots at most 200 times (10Hz -> 5Hz)", int(GL11.platePolls) <= 200, True)
shownL11 = rtL11.eval("""(function()
  local n = 0
  for i = 1, 3 do
    for _, c in ipairs(platesL11[i].children) do
      if c.kind == "StatusBar" and c.shown then n = n + 1 end
    end
  end
  return n
end)()""")
check("L11-3: the three plate markers stay drawn under the throttle", int(shownL11) >= 3, True)
# and a dead mob is still hidden at once, on the throttled rhythm (two 0.2 s frames = 0.4 s)
rtL11.execute("units['nameplate1'].dead = true units['nameplate1'].health = 0 units['nameplate1'].max = 0")
GL11.Tick(0.2)
GL11.Tick(0.2)
deadL11 = rtL11.eval("""(function()
  local n = 0
  for _, c in ipairs(platesL11[1].children) do
    if c.kind == "StatusBar" and c.shown then n = n + 1 end
  end
  return n
end)()""")
check("L11-3: the corpse plate's marker hides within half a second", int(deadL11), 0)

# ---------------------------------------------------------------------------------------------
print("-- RD-4: the /rding probe reads a full bar as five lit points, not four")
rtRD4, GRD4, BITRD4, _ = load(saved="""
ComboFrame = FakeMock("ComboFrame")
function ComboFrame:IsShown() return true end
for i = 1, 12 do
  local p = FakeMock("point" .. i)
  p.shown = false
  p.Highlight = FakeMock("highlight" .. i)
  function p.Highlight:GetAlpha() return p.alpha or 0 end
  _G["ComboPoint" .. i] = p
end
""")
GRD4.Fire("ADDON_LOADED", "BattleInfoTool")
GRD4.Fire("PLAYER_LOGIN")
GRD4.playerClass = "ROGUE"   # combo points on the target, as on Classic/Forever
GRD4.comboPoints = 5
# a full bar the way the client draws it: ComboPoint2..ComboPoint6 lit, ComboPoint1 hidden
rtRD4.execute("""
for i = 2, 6 do
  local p = _G["ComboPoint" .. i]
  p.shown = true
  p.alpha = 1
end
""")
GRD4.SlashCmdList.RESOURCEDING("probe")
probeLines = chat(GRD4)
lit = sum(1 for l in probeLines if "ComboPoint" in l and "shown=true" in l and "alpha=1" in l)
check("the probe's per-point dump lists all five lit points", lit, 5)

# ---------------------------------------------------------------------------------------------
print("-- RD-10: a mana maximum that drops must not ding; a real climb still does")
rtRD10, GRD10, BITRD10, _ = load(saved="""
manaCurrent, manaMax = 300, 400
function UnitPower(u, pt) if pt == 4 then return comboPoints end return manaCurrent end
function UnitPowerMax(u, pt) if pt == 4 then return 5 end return manaMax end
""")
GRD10.Fire("ADDON_LOADED", "BattleInfoTool")
GRD10.Fire("PLAYER_LOGIN")


def dingCount():
    return len(GRD10.plays)


# a warlock's level is 80%: 300/400 is below it, silent, and the latch arms
GRD10.Fire("UNIT_POWER_UPDATE", "player")
check("below the warlock's mana level: silent", dingCount(), 0)
# a buff or a form ends: the maximum drops 400 -> 300 while mana stays 300,
# and the ratio crosses the level without a single point of mana gained
GRD10.manaMax = 300
GRD10.Fire("UNIT_MAXPOWER", "player")
check("the maximum dropping must not ding", dingCount(), 0)
# a real climb to the level afterwards still dings exactly once
GRD10.manaCurrent = 200
GRD10.Fire("UNIT_POWER_UPDATE", "player")
GRD10.manaCurrent = 300
GRD10.Fire("UNIT_POWER_UPDATE", "player")
check("the real climb still dings once", dingCount(), 1)

# ---------------------------------------------------------------------------------------------
print("-- RD-5: the dot sliders must move the shard diamonds too")
# Shards.lua sizes the diamonds and anchors the row from db.dotSize / db.dotOffset, and the
# settings sliders' setters only refresh the combo dots -- so on a warlock with shard
# diamonds up, dragging either slider leaves them at the old look until a bag or target
# event happens to redraw them (the diamonds lag behind the dots).
rtRD5, GRD5, BITRD5, _ = load(saved="""
C_Item.GetItemCount = function() return 2 end  -- two soul shards in the bags
""")
GRD5.Fire("ADDON_LOADED", "BattleInfoTool")
GRD5.Fire("PLAYER_LOGIN")
rd5 = BITRD5.modules["ResourceDing"]
rtRD5.execute("units['target'] = { guid = 'Mob-D-1' }")
GRD5.target = rtRD5.eval("{ hostile = true }")
GRD5.plate = rtRD5.eval("NewPlate()")
rd5.RefreshShards()
check("  a warlock's shard diamonds draw at the default size", rd5._diamonds[1].width, 14)
panel5 = rd5.CreateSettingsPanel(rtRD5.eval("FakeMock('settings')"))
# dragging Dot size to 20: the combo dots move, and so must the diamonds
panel5.dotSize.scripts.OnValueChanged(panel5.dotSize, 20)
check("  Dot size 20 resizes the shard diamonds at once", rd5._diamonds[1].width, 20)
# dragging the offset moves the row's anchor under the health bar the same way
panel5.dotOffset.scripts.OnValueChanged(panel5.dotOffset, 11)
rowPts5 = [rd5._shardRow().points[i] for i in range(1, len(rd5._shardRow().points) + 1)]
check("  the offset slider moves the diamonds right away", rowPts5[-1][5], -11)

# ---------------------------------------------------------------------------------------------
print("-- RD-6: every sound the panel offers must exist on the client's SoundKitConstants")
# Core.lua prunes a sound whose SOUNDKIT key the client does not have. The keys it uses for
# quest / level / coins do not exist on any supported client (mirrors live == forever, and
# classic_era's Vanilla): UI_QUEST_COMPLETE, LEVEL_UP and LOOT_MONEY_COINS are not in
# SoundKitConstants.lua, while UI_AUTO_QUEST_COMPLETE = 23404, LOOT_WINDOW_COIN_SOUND = 120
# and UI_ORDERHALL_TALENT_READY_TOAST = 73280 are. Off the real key set the panel must keep
# every working choice, not silently lose three of them.
rtRD6, GRD6, BITRD6, _ = load(saved="""
SOUNDKIT = {  -- the keys the Forever client really has (SoundKitConstants.lua 1.60.1/70009)
  AUCTION_WINDOW_OPEN = 5274, READY_CHECK = 8960, RAID_WARNING = 8959,
  UI_AUTO_QUEST_COMPLETE = 23404, LOOT_WINDOW_COIN_SOUND = 120,
  UI_ORDERHALL_TALENT_READY_TOAST = 73280,
}
""")
rd6 = BITRD6.modules["ResourceDing"]
check("  the prune keeps all six real sounds", list(rd6.SOUND_ORDER.values()),
      ["auction", "ready", "quest", "bell", "coins", "warning"])
check("  each keeps the client's sound id", tuple(rd6.SOUNDS[k].id for k in rd6.SOUND_ORDER.values()),
      (5274, 8960, 23404, 73280, 120, 8959))
# and on a client with no SOUNDKIT at all, the curated numeric fallbacks are the real ids
# (level stays for the Classic stubs, which name LEVEL_UP; Forever prunes it)
rtRD6b, GRD6b, BITRD6b, _ = load(saved="SOUNDKIT = nil")
rd6b = BITRD6b.modules["ResourceDing"]
check("  the no-SOUNDKIT fallbacks are the real sound ids",
      tuple(rd6b.SOUNDS[k].id for k in rd6b.SOUND_ORDER.values()),
      (5274, 8960, 23404, 888, 73280, 120, 8959))

# ---------------------------------------------------------------------------------------------
print("-- RD-7: a dead PlaySound must not take the event handler down")
# PlaySoundKey calls the global PlaySound bare. It runs from the events frame's OnEvent
# (via CheckPower/CheckShards), where an error kills the handler, and from the dropdown and
# the /rding test. A client without PlaySound or one that errors must cost the sound, not
# the addon.
rtRD7, GRD7, BITRD7, _ = load()
GRD7.RD7 = BITRD7.modules["ResourceDing"]
rd7 = BITRD7.modules["ResourceDing"]
GRD7.Fire("ADDON_LOADED", "BattleInfoTool")
GRD7.Fire("PLAYER_LOGIN")
GRD7.playerClass = "ROGUE"   # combo points on the target, as on Classic/Forever
before7 = len(GRD7.plays)
check("  a live PlaySound plays once and reports success",
      (rd7.PlaySoundKey("auction") == True, len(GRD7.plays) - before7), (True, 1))
rtRD7.execute("PlaySound = nil")
ok7, val7 = rtRD7.eval("(function() local ok, v = pcall(function() return RD7.PlaySoundKey('auction') end) return ok, v end)()")
check("  a missing PlaySound is a false, not an error", (ok7, val7), (True, False))
# an erroring PlaySound must be absorbed inside the event dispatch, handler included
rtRD7.execute("PlaySound = function() error('boom') end")
GRD7.combat = True
GRD7.comboPoints = 4
GRD7.Fire("UNIT_POWER_FREQUENT", "player")  # arms the latch
GRD7.comboPoints = 5
dispatch7 = rtRD7.eval("pcall(function() Fire('UNIT_POWER_FREQUENT', 'player') end)")
check("  an erroring PlaySound is absorbed, the handler survives", dispatch7, True)
check("  and nothing was played", len(GRD7.plays) - before7, 1)
# the same handler still dings once when the sound works again
rtRD7.execute("PlaySound = function(id, channel, ...) table.insert(plays, { id = id, channel = channel }) return true end")
GRD7.comboPoints = 4
GRD7.Fire("UNIT_POWER_FREQUENT", "player")
GRD7.comboPoints = 5
GRD7.Fire("UNIT_POWER_FREQUENT", "player")
check("  the same handler still dings once afterwards", len(GRD7.plays) - before7, 2)

# ---------------------------------------------------------------------------------------------
print("-- SDI-MACRO: a /cast macro slot shows its spell's number")
sdi = BIT.modules["SpellDamageInfo"]
rt.execute("""
function GetActionInfo(slot)
  if slot == 11 then return "macro", 172, "spell" end
  if slot == 12 then return "spell", 172 end
  return nil, nil
end
""")
check("SDI-MACRO: macro /cast slot resolves to its spell", sdi.SpellOnSlot(11), 172)
check("  and a plain spell slot still resolves", sdi.SpellOnSlot(12), 172)

# ---------------------------------------------------------------------------------------------
print("-- SDI-BLACKARROW: damage + mana drain over 30s is a DoT, not direct")
blackArrow = "Fires a Black Arrow into the target, slowing the target's movement speed by 70%, causing 150 Shadow damage and draining 150 mana over 30 sec."
raw = sdi.Parser.Parse(blackArrow, "en")
parsed = raw[0] if isinstance(raw, tuple) else raw
def _slot(t, k):
    if t is None:
        return None
    try:
        v = t[k]
    except Exception:
        return None
    # lupa None-proxy -> Python None; numbers stay numbers
    return v
direct = _slot(parsed, "direct")
dot = _slot(parsed, "dot")
check("SDI-BLACKARROW: no direct slot", direct, None)
check("  dot total 150 over 30s", _slot(dot, "total"), 150)
check("  dot duration 30s", _slot(dot, "duration"), 30)

# ---------------------------------------------------------------------------------------------
print("-- SDI-LIFETAP RED: Converts Health into Mana reads both numbers")
lifeTap = "Converts 58 Health into 58 Mana for you."
lifeRaw = sdi.Parser.ParseSpecial(lifeTap, "en")
check("SDI-LIFETAP RED: special reads health cost", _slot(lifeRaw, "healthCost"), 58)
check("  and mana gain", _slot(lifeRaw, "manaGain"), 58)
lifeRawDE = sdi.Parser.ParseSpecial("Wandelt 58 Gesundheit in 58 Mana um.", "de")
check("SDI-LIFETAP DE: German wording reads the same health cost", _slot(lifeRawDE, "healthCost"), 58)
check("  German wording reads the same mana gain", _slot(lifeRawDE, "manaGain"), 58)
lifeView = rt.eval('{ healthCost = 58, manaGain = 58 }')
lifeMain, lifeColor, lifeSide, lifeSideColor, lifeLayout = sdi.ButtonText(lifeView, None)
check("  button shows -HP and +mana", (lifeMain, lifeSide), ("-58 HP", "+58 mana"))
lifeTip = sdi.Format.TooltipLines(lifeView, sdi.L)
check("  tooltip shows cost and gain", (lifeTip[1][1], lifeTip[2][1]), ("-58 HP", "+58 mana"))

# ---------------------------------------------------------------------------------------------
print("-- SDI-LIFETAP-POS: both labels below the hotkey, HP above mana")
rtLP, GLP, BITLP, _ = load()
GLP.Fire("ADDON_LOADED", "BattleInfoTool")
GLP.Fire("PLAYER_LOGIN")
sdiLP = BITLP.modules["SpellDamageInfo"]
rtLP.execute('''
  lifeButton = FakeMock("button")
  lifeButton:SetSize(36, 36)
  lifeMainLabel = lifeButton:CreateFontString()
  lifeSideLabel = lifeButton:CreateFontString()
  for _, label in ipairs({ lifeMainLabel, lifeSideLabel }) do
    function label:SetFont(file, size, flags) self.fontSize = size; return true end
    function label:GetStringWidth() return #(self.text or "") * (self.fontSize or 12) * 0.55 end
  end
''')
life_texts = sdiLP.ButtonText(rtLP.eval('{ healthCost = 58, manaGain = 58 }'), None)
life_layout = life_texts[4] if len(life_texts) > 4 else None
for position in ("bottom", "center", "top"):
    sdiLP.SetSetting("position", position)
    for size in (50, 100, 200):
        sdiLP.SetSetting("size", size)
        sdiLP.DrawNumber(GLP.lifeButton, GLP.lifeMainLabel, GLP.lifeSideLabel,
                         *life_texts[:3], False, life_texts[3], life_layout)
        mp, sp = GLP.lifeMainLabel.points[1], GLP.lifeSideLabel.points[1]
        safe_stack = (mp[1] == "BOTTOMLEFT" and sp[1] == "BOTTOMLEFT"
                      and mp[3] == "BOTTOMLEFT" and sp[3] == "BOTTOMLEFT"
                      and mp[5] >= sp[5] + GLP.lifeSideLabel.fontSize + 1
                      and 36 - mp[5] - GLP.lifeMainLabel.fontSize >= 14)
        check(f"SDI-LIFETAP-POS: {position}/{size}% leaves hotkey clear and keeps HP above mana", safe_stack)
        check(f"  {position}/{size}% both labels fit width",
              GLP.lifeMainLabel.GetStringWidth(GLP.lifeMainLabel) <= 34
              and GLP.lifeSideLabel.GetStringWidth(GLP.lifeSideLabel) <= 34)
BITLP.OpenSettings("SpellDamageInfo")
life_mocks = sdiLP._optionsWindow().mocks
check("SDI-LIFETAP-POS: options preview includes the same two-line Life Tap",
      any(m.main.text == "-58 HP" and m.side.text == "+58 mana" for m in life_mocks.values()))

# ---------------------------------------------------------------------------------------------
print("-- SI-PCT-CAP RED: empty slot and over-cap read as >300%, no points")
rtC, GC, BITC, _ = load()
GC.Fire("ADDON_LOADED", "BattleInfoTool")
GC.Fire("PLAYER_LOGIN")
siC = BITC.modules["StatsInfo"]
GC.playerClass = "DRUID"
GC.itemStats["cap-hide"] = rtC.eval('{ ITEM_MOD_AGILITY_SHORT = 8 }')
GC.itemLoc["cap-hide"] = "INVTYPE_CHEST"
cap_r = siC.SpecRatings("cap-hide", rtC.table_from([]))
cap_cat = [x for x in cap_r.values() if x.spec.name == "Cat"][0].parts[1]
check("SI-PCT-CAP: empty slot is capped percent, not points",
      (_slot(cap_cat, "percent"), _slot(cap_cat, "capped"), _slot(cap_cat, "points")), (300.0, True, None))
cap_lines = [l[1] for l in siC.TooltipLines("cap-hide").values()]
check("  tooltip says >300% dmg spec", any(">300%" in l and "dmg" in l for l in cap_lines), True)
check("  no 'like +' currency anywhere", any("like +" in l for l in cap_lines), False)

# ---------------------------------------------------------------------------------------------
print("-- SDI-PORT: regenerating the module preserves all BIT fixes")
import importlib.util
port_spec = importlib.util.spec_from_file_location("bit_port", ROOT / "tools" / "port.py")
port_module = importlib.util.module_from_spec(port_spec)
port_spec.loader.exec_module(port_module)
port_drift = []
for generated_path, generated_data in port_module.port("SpellDamageInfo"):
    # The first line records the source commit, not runtime behaviour.
    generated_body = generated_data.decode("utf-8").splitlines()[1:]
    current_body = generated_path.read_text(encoding="utf-8").splitlines()[1:]
    if generated_body != current_body:
        port_drift.append(generated_path.name)
check("SDI-PORT: Life Tap, macros and Black Arrow survive regeneration", port_drift, [])

# ---------------------------------------------------------------------------------------------
print("-- ENCHANT: an item's enchant is part of its stats (GetItemStats leaves it out)")
# Forever's proof: the Embossed Leather Vest's GetItemStats reads { RESISTANCE0_NAME = 62,
# ITEM_MOD_STAMINA_SHORT = 2 } while its tooltip says "Enchanted: Stamina +1 and Armor +8" --
# the enchant (+8 Armor, +1 Stamina) never reaches GetItemStats, so comparisons and the spec
# ratings miss it. The enchant is read from the tooltip's enchant-marked line instead: the
# client's own words (the ITEM_ENCHANTMENT header, its names for the stats), nothing guessed.
rtE, GE, BITE, _ = load()
GE.Fire("ADDON_LOADED", "BattleInfoTool")
GE.Fire("PLAYER_LOGIN")
siE = BITE.modules["StatsInfo"]
siE.settings.specs, siE.settings.icons = False, False
GE.playerClass = "DRUID"
GE.RESISTANCE0_NAME = "Rüstung"
GE.ITEM_ENCHANTMENT = "Verzaubert:"
rtE.execute("""
tooltopsE, tooltopCallsE = {}, 0
function Tooltop(link, ...)
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
GE.C_TooltipInfo = rtE.eval("{}")
GE.C_TooltipInfo.GetHyperlink = GE.GetHyperlinkE
GE.itemStats["vest"] = rtE.eval("{ RESISTANCE0_NAME = 62, ITEM_MOD_STAMINA_SHORT = 2 }")
GE.itemStats["boots"] = rtE.eval("{ RESISTANCE0_NAME = 31 }")
GE.itemStats["vest-worn"] = rtE.eval("{ RESISTANCE0_NAME = 50, ITEM_MOD_STAMINA_SHORT = 1 }")
GE.itemLoc["vest"], GE.itemLoc["boots"], GE.itemLoc["vest-worn"] = "INVTYPE_CHEST", "INVTYPE_FEET", "INVTYPE_CHEST"
GE.Tooltop("vest", "62 Rüstung", "+2 Ausdauer", "Verzaubert: Ausdauer +1 und Rüstung +8")
GE.Tooltop("boots", "31 Rüstung", "Verzaubert: Ausdauer +1 und Rüstung +8")
check("ENCHANT-1: the tooltip's enchant joins GetItemStats (62 Rüstung +8, 2 Ausdauer +1)",
      dict(siE.ItemStats("vest")), {"ITEM_MOD_STAMINA_SHORT": 3, "RESISTANCE0_NAME": 70})
check("ENCHANT-2: 31 Rüstung alone reads 39 Rüstung and Ausdauer 1",
      dict(siE.ItemStats("boots")), {"ITEM_MOD_STAMINA_SHORT": 1, "RESISTANCE0_NAME": 39})
GE.worn[5] = "vest-worn"
c = siE.Compare("vest")
check("ENCHANT-3: the comparison counts the enchant (+8 Rüstung and +1 Ausdauer)",
      [(d.key, d.diff) for d in c[1].diffs.values()],
      [("ITEM_MOD_STAMINA_SHORT", 2), ("RESISTANCE0_NAME", 20)])
GE.itemStats["gloves"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 4 }")
GE.itemStats["gloves-ench"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["gloves"], GE.itemLoc["gloves-ench"] = "INVTYPE_HAND", "INVTYPE_HAND"
GE.Tooltop("gloves-ench", "Verzaubert: +3 Beweglichkeit")  # German, the number before the name
GE.worn[10] = "gloves"
c = siE.Compare("gloves-ench")
check("ENCHANT-4: +3 Beweglichkeit: the comparison reads 8 against 4",
      [(d.key, d.diff) for d in c[1].diffs.values()], [("ITEM_MOD_AGILITY_SHORT", 4)])
rE = {x.spec.name: round(x.parts[1].percent, 2) for x in siE.SpecRatings(
    "gloves-ench", rtE.table_from(["gloves"])).values()}
check("ENCHANT-5: the specs' ratings use the augmented stats too (8 vs 4: +100% cat)",
      rE["Cat"], 100.0)
# English: the client's names and header are read at the line's own words
GE.ITEM_MOD_AGILITY_SHORT = "Agility"
GE.ITEM_MOD_STAMINA_SHORT = "Stamina"
GE.RESISTANCE0_NAME = "Armor"
GE.ITEM_ENCHANTMENT = "Enchanted:"
GE.itemStats["gloves-en"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["gloves-en"] = "INVTYPE_HAND"
GE.Tooltop("gloves-en", "Enchanted: Agility +3")  # the name before the number
GE.itemStats["gloves-en2"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["gloves-en2"] = "INVTYPE_HAND"
GE.Tooltop("gloves-en2", "Enchanted: +3 Agility")  # the number before the name
check("ENCHANT-6: English 'Agility +3' reads the same",
      dict(siE.ItemStats("gloves-en")), {"ITEM_MOD_AGILITY_SHORT": 8})
check("ENCHANT-7: English '+3 Agility' reads the same",
      dict(siE.ItemStats("gloves-en2")), {"ITEM_MOD_AGILITY_SHORT": 8})
GE.itemStats["proc-gloves"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["proc-gloves"] = "INVTYPE_HAND"
GE.Tooltop("proc-gloves", "+5 Agility", "Equip: Increases your Agility by 12.", "Proc: Fiery")
check("ENCHANT-8: the ordinary stat, equip and proc lines are not read as an enchant",
      dict(siE.ItemStats("proc-gloves")), {"ITEM_MOD_AGILITY_SHORT": 5})
GE.itemStats["flame-gloves"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["flame-gloves"] = "INVTYPE_HAND"
GE.Tooltop("flame-gloves", "Enchanted: Fiery Weapon")  # a proc, not stats
GE.itemStats["numless"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["numless"] = "INVTYPE_HAND"
GE.Tooltop("numless", "Enchanted: Agility")  # a name without a number
check("ENCHANT-9: an enchant the words do not give adds nothing (Fiery Weapon)",
      dict(siE.ItemStats("flame-gloves")), {"ITEM_MOD_AGILITY_SHORT": 5})
check("ENCHANT-10: a stat name without a number adds nothing",
      dict(siE.ItemStats("numless")), {"ITEM_MOD_AGILITY_SHORT": 5})
GE.itemStats["mixed"] = rtE.eval("{}")
GE.itemLoc["mixed"] = "INVTYPE_HAND"
GE.Tooltop("mixed", "Enchanted: Stamina +1 and +8 Armor")  # both orders in one line
check("ENCHANT-11: a line mixing 'Stamina +1' and '+8 Armor' reads both",
      dict(siE.ItemStats("mixed")), {"ITEM_MOD_STAMINA_SHORT": 1, "RESISTANCE0_NAME": 8})
# secret and throwing clients: the enchant is left out, the addon survives
rtE.execute("SECRET_E = {} function issecretvalue(v) return v == SECRET_E end")
secret_lines = rtE.eval("{}")
row = rtE.eval("{}")
row.leftText = GE.SECRET_E
secret_lines[1] = row
secret_data = rtE.eval("{}")
secret_data.lines = secret_lines
GE.tooltopsE["secret-gloves"] = secret_data
GE.itemStats["secret-gloves"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["secret-gloves"] = "INVTYPE_HAND"
check("ENCHANT-12a: a secret enchant line is left out",
      dict(siE.ItemStats("secret-gloves")), {"ITEM_MOD_AGILITY_SHORT": 5})
GE.itemStats["throw-gloves"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["throw-gloves"] = "INVTYPE_HAND"
GE.C_TooltipInfo.GetHyperlink = rtE.eval("function() error('ENCHANT boom') end")
check("ENCHANT-12b: a throwing hyperlink tooltip costs the enchant, not the addon",
      dict(siE.ItemStats("throw-gloves")), {"ITEM_MOD_AGILITY_SHORT": 5})
GE.C_TooltipInfo.GetHyperlink = GE.GetHyperlinkE
# a GetItemStats that already counts the enchant must not be doubled: the baseline is the client's
# own answer for the whole link, and a key the enchant names is reconciled against the link without
# its enchant field (only that second numeric field is stripped, everything else kept)
GE.seenE = rtE.eval("{}")
GE.C_Item.GetItemStats = rtE.eval("function(link) table.insert(seenE, link) return itemStats[link] end")
full = "|cnIQ2:|Hitem:2300:15:::::::11:1484::::::::Player-4618-00A56360:|h[Embossed Leather Vest]|h|r"
stripped = full.replace("|Hitem:2300:15", "|Hitem:2300:", 1)  # only "15" taken out, the fields' colons kept
GE.itemStats[stripped] = rtE.eval("{ RESISTANCE0_NAME = 62, ITEM_MOD_STAMINA_SHORT = 2 }")
GE.itemLoc[full] = "INVTYPE_CHEST"
GE.Tooltop(full, "Enchanted: Stamina +1 and Armor +8")
check("ENCHANT-13: the whole link is the baseline, the enchant is reconciled against the clean link "
      "(no doubling)",
      (dict(siE.ItemStats(full)), str(GE.seenE[1]), str(GE.seenE[2])),
      ({"ITEM_MOD_STAMINA_SHORT": 3, "RESISTANCE0_NAME": 70}, full, stripped))
# the tooltip is scanned once per link; a tooltip that was not there is not kept as "no enchant"
GE.itemStats["memo-gloves"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["memo-gloves"] = "INVTYPE_HAND"
GE.Tooltop("memo-gloves", "Enchanted: Agility +1")
GE.tooltopCallsE = 0
siE.ItemStats("memo-gloves")
siE.ItemStats("memo-gloves")
check("ENCHANT-14: an enchant found is scanned once, not per call", int(GE.tooltopCallsE), 1)
GE.itemStats["plain-gloves"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["plain-gloves"] = "INVTYPE_HAND"
GE.Tooltop("plain-gloves", "+5 Agility")
GE.tooltopCallsE = 0
siE.ItemStats("plain-gloves")
siE.ItemStats("plain-gloves")
check("ENCHANT-15: a tooltip read as having no enchant is not scanned again either",
      int(GE.tooltopCallsE), 1)
GE.itemStats["ghost"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["ghost"] = "INVTYPE_HAND"  # no tooltip yet: the item's data has not arrived
GE.tooltopCallsE = 0
siE.ItemStats("ghost")
siE.ItemStats("ghost")
check("ENCHANT-16: no tooltip data yet: nothing is cached as 'no enchant'",
      int(GE.tooltopCallsE), 2)
GE.Tooltop("ghost", "Enchanted: Agility +3")
check("ENCHANT-17: the enchant is read once the data arrives",
      dict(siE.ItemStats("ghost")), {"ITEM_MOD_AGILITY_SHORT": 8})
# a client that marks the enchant line by its tooltip line type: the real enum's name and value
# (the client's generated TooltipInfoSharedDocumentation; on Classic: ItemEnchantmentPermanent = 15)
rtE.execute("Enum.TooltipDataLineType = { ItemEnchantmentPermanent = 15, ItemBinding = 20 }")


def typed_tooltop(link, text, typ):
    lines = rtE.eval("{}")
    row = rtE.eval("{}")
    row.leftText = text
    row.type = typ
    lines[1] = row
    data = rtE.eval("{}")
    data.lines = lines
    GE.tooltopsE[link] = data


typed_tooltop("typed", "Stamina +1 and Armor +8", 15)
GE.itemStats["typed"] = rtE.eval("{}")
GE.itemLoc["typed"] = "INVTYPE_HAND"
check("ENCHANT-18: a line the client marks as an enchant by its real line type "
      "(TooltipDataLineType.ItemEnchantmentPermanent) is read too",
      dict(siE.ItemStats("typed")), {"ITEM_MOD_STAMINA_SHORT": 1, "RESISTANCE0_NAME": 8})
typed_tooltop("typed-non", "Equip: Increases your Stamina by 12.", 20)
GE.itemStats["typed-non"] = rtE.eval("{}")
GE.itemLoc["typed-non"] = "INVTYPE_HAND"
check("ENCHANT-19: an ordinary line type (ItemBinding) is not an enchant",
      dict(siE.ItemStats("typed-non")), {})
# the worn item's enchant counts too (the boots the player wears)
GE.itemStats["boots-plain"] = rtE.eval("{ RESISTANCE0_NAME = 40 }")
GE.itemLoc["boots-plain"] = "INVTYPE_FEET"
GE.worn[8] = "boots"
c = siE.Compare("boots-plain")
check("ENCHANT-20: the worn item's enchant counts in the comparison (39 + 1 against 40)",
      [(d.key, d.diff) for d in c[1].diffs.values()],
      [("ITEM_MOD_STAMINA_SHORT", -1), ("RESISTANCE0_NAME", 1)])

# ---------------------------------------------------------------------------------------------
print("-- ENCHANT: what the correctness review found (2026-09-30)")
# (6) a nil or secret link must never reach the link rewrite or the enchant memo: the client
# raises on secret keys, so nothing is asked and nothing is cached
GE.siE2 = siE
GE.tooltopCallsE = 0
rtE.execute("okNil, valNil = pcall(function() return siE2.ItemStats(nil) end)")
check("ENCHANT-21: a nil link is safe (no memo key, no gsub, no tooltip scan)",
      (bool(GE.okNil), dict(GE.valNil), int(GE.tooltopCallsE)), (True, {}, 0))
rtE.execute("okSec, valSec = pcall(function() return siE2.ItemStats(SECRET_E) end)")
check("ENCHANT-22: a secret link is safe and never reads the tooltip",
      (bool(GE.okSec), dict(GE.valSec), int(GE.tooltopCallsE)), (True, {}, 0))
# a colour-wrapped enchant line ("|cAARRGGBB...|r", as the client colours a tooltip line)
GE.itemStats["colored"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["colored"] = "INVTYPE_HAND"
GE.Tooltop("colored", "|cff1eff00Enchanted: Agility +3|r")
check("ENCHANT-23: a colour-wrapped enchant line is read too",
      dict(siE.ItemStats("colored")), {"ITEM_MOD_AGILITY_SHORT": 8})
# (2) the ITEM_ENCHANTMENT header may be a format holding %s, not a bare prefix
GE.ITEM_ENCHANTMENT = "Enchanted: %s"
GE.itemStats["fmt-vest"] = rtE.eval("{ RESISTANCE0_NAME = 62, ITEM_MOD_STAMINA_SHORT = 2 }")
GE.itemLoc["fmt-vest"] = "INVTYPE_CHEST"
GE.Tooltop("fmt-vest", "Enchanted: Stamina +1 and Armor +8")
check("ENCHANT-24: a format header (ITEM_ENCHANTMENT with %s in it) reads the same",
      dict(siE.ItemStats("fmt-vest")), {"ITEM_MOD_STAMINA_SHORT": 3, "RESISTANCE0_NAME": 70})
GE.ITEM_ENCHANTMENT = "Enchanted:"
# (3) a proc, a percent or a duration reads no flat stat: only a clean number beside the name
for link, line in (("proc-stam", "Enchanted: Chance on hit: grants Stamina +5 for 10 seconds"),
                   ("pct-stam", "Enchanted: Stamina +5%"),
                   ("pct-gain", "Enchanted: +5% Stamina"),
                   ("dur-stam", "Enchanted: 5 Stamina for 10 seconds")):
    GE.itemStats[link] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
    GE.itemLoc[link] = "INVTYPE_HAND"
    GE.Tooltop(link, line)
check("ENCHANT-25: a proc ('Chance on hit: grants Stamina +5 for 10 seconds') is not a flat stat",
      dict(siE.ItemStats("proc-stam")), {"ITEM_MOD_AGILITY_SHORT": 5})
check("ENCHANT-26: 'Stamina +5%' is a percent, not +5 Stamina",
      dict(siE.ItemStats("pct-stam")), {"ITEM_MOD_AGILITY_SHORT": 5})
check("ENCHANT-27: '+5% Stamina' is a percent too",
      dict(siE.ItemStats("pct-gain")), {"ITEM_MOD_AGILITY_SHORT": 5})
check("ENCHANT-28: '5 Stamina for 10 seconds' is a duration, not +5 Stamina",
      dict(siE.ItemStats("dur-stam")), {"ITEM_MOD_AGILITY_SHORT": 5})
# (4) the client's own GetItemStats answer for the whole link is the baseline; the clean link
# reconciles only a key the enchant names, and never doubles or drops, even when the clean answer
# is missing or the tooltip has not arrived
full2 = "|cnIQ2:|Hitem:2301:17:::::::4:1484::::::::Player-1-00000001:|h[Enchanted Vest]|h|r"
stripped2 = full2.replace("|Hitem:2301:17", "|Hitem:2301:", 1)
GE.itemStats[full2] = rtE.eval("{ RESISTANCE0_NAME = 70, ITEM_MOD_STAMINA_SHORT = 3 }")  # counts the enchant, as some clients do
GE.itemStats[stripped2] = rtE.eval("{ RESISTANCE0_NAME = 62, ITEM_MOD_STAMINA_SHORT = 2 }")
GE.itemLoc[full2] = "INVTYPE_CHEST"
GE.Tooltop(full2, "Enchanted: Stamina +1 and Armor +8")
check("ENCHANT-29: a client that counts the enchant already: reconciled, not doubled (70/3, not 78/4)",
      dict(siE.ItemStats(full2)), {"ITEM_MOD_STAMINA_SHORT": 3, "RESISTANCE0_NAME": 70})
late = "|cnIQ2:|Hitem:2302:21:::::::4:1484::::::::Player-1-00000001:|h[Late Vest]|h|r"
lateStripped = late.replace("|Hitem:2302:21", "|Hitem:2302:", 1)
GE.itemStats[late] = rtE.eval("{ RESISTANCE0_NAME = 70, ITEM_MOD_STAMINA_SHORT = 3 }")
GE.itemStats[lateStripped] = rtE.eval("{ RESISTANCE0_NAME = 62, ITEM_MOD_STAMINA_SHORT = 2 }")
GE.itemLoc[late] = "INVTYPE_CHEST"  # no tooltip data yet
check("ENCHANT-30: a tooltip not there yet: the baseline keeps the client's own answer (70/3, not dropped to 62/2)",
      dict(siE.ItemStats(late)), {"ITEM_MOD_STAMINA_SHORT": 3, "RESISTANCE0_NAME": 70})
boom = "|cnIQ2:|Hitem:2303:25:::::::4:1484::::::::Player-1-00000001:|h[Boom Vest]|h|r"
boomStripped = boom.replace("|Hitem:2303:25", "|Hitem:2303:", 1)
GE.itemStats[boom] = rtE.eval("{ RESISTANCE0_NAME = 70, ITEM_MOD_STAMINA_SHORT = 3 }")
GE.itemLoc[boom] = "INVTYPE_CHEST"
GE.Tooltop(boom, "Enchanted: Stamina +1 and Armor +8")
GE.savedGetItemStats = GE.C_Item.GetItemStats
GE.boomStripped = boomStripped
GE.C_Item.GetItemStats = rtE.eval("function(link) if link == boomStripped then error('no clean answer') end return itemStats[link] end")
check("ENCHANT-31: no clean answer (it errors): the baseline stands, nothing doubled (70/3, not 78/4)",
      dict(siE.ItemStats(boom)), {"ITEM_MOD_STAMINA_SHORT": 3, "RESISTANCE0_NAME": 70})
GE.C_Item.GetItemStats = GE.savedGetItemStats
# (5) tooltip data with no lines at all is not built yet: not kept as "no enchant"
GE.itemStats["empty"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["empty"] = "INVTYPE_HAND"
rtE.execute("emptyData = {} emptyData.lines = {}")
GE.tooltopsE["empty"] = rtE.eval("emptyData")
GE.tooltopCallsE = 0
siE.ItemStats("empty")
siE.ItemStats("empty")
check("ENCHANT-32: empty tooltip data (no lines) is not kept as 'no enchant', it is scanned again",
      int(GE.tooltopCallsE), 2)
GE.Tooltop("empty", "Enchanted: Agility +3")
check("ENCHANT-33: its enchant is read once the data arrives",
      dict(siE.ItemStats("empty")), {"ITEM_MOD_AGILITY_SHORT": 8})

# ---------------------------------------------------------------------------------------------
print("-- ENCHANT: second review pass (2026-09-30): secret clean stats, prose, title-only tooltip")
# (1) a secret clean stat: the client hides a stat's value in combat by marking it secret
# (issecretvalue), and the value may still be a number. A secret clean answer is never
# arithmetic'd on or guessed from: the full link's own answer keeps the stat.
rtE.execute("SECRET_NUM = 1876543 function issecretvalue(v) return v == SECRET_E or v == SECRET_NUM end")
secFull = "|cnIQ2:|Hitem:2304:19:::::::4:1484::::::::Player-1-00000001:|h[Secret Vest]|h|r"
secStripped = secFull.replace("|Hitem:2304:19", "|Hitem:2304:", 1)
GE.itemStats[secFull] = rtE.eval("{ ITEM_MOD_STAMINA_SHORT = 3, RESISTANCE0_NAME = 70 }")
GE.itemStats[secStripped] = rtE.eval("{ ITEM_MOD_STAMINA_SHORT = SECRET_NUM, RESISTANCE0_NAME = 62 }")
GE.itemLoc[secFull] = "INVTYPE_CHEST"
GE.Tooltop(secFull, "Enchanted: Stamina +1 and Armor +8")
check("ENCHANT-34: a secret clean stat is never added to (the baseline's own 3 Stamina stays, "
      "no secret+1 and no guessed 1)",
      dict(siE.ItemStats(secFull)), {"ITEM_MOD_STAMINA_SHORT": 3, "RESISTANCE0_NAME": 70})

# (2) only clean stat components: prose around a known stat must not add a flat stat
for link, line in (("prose-hit", "Enchanted: Chance on hit: Stamina +5"),
                   ("prose-use", "Enchanted: Use: +5 Stamina")):
    GE.itemStats[link] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
    GE.itemLoc[link] = "INVTYPE_HAND"
    GE.Tooltop(link, line)
check("ENCHANT-35: a proc phrase ('Chance on hit: Stamina +5') is not a flat stat",
      dict(siE.ItemStats("prose-hit")), {"ITEM_MOD_AGILITY_SHORT": 5})
check("ENCHANT-36: 'Use: +5 Stamina' is not a flat stat",
      dict(siE.ItemStats("prose-use")), {"ITEM_MOD_AGILITY_SHORT": 5})
GE.ITEM_ENCHANTMENT = "Verzaubert:"
GE.ITEM_MOD_STAMINA_SHORT = "Ausdauer"
GE.itemStats["prose-de"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["prose-de"] = "INVTYPE_HAND"
GE.Tooltop("prose-de", "Verzaubert: Chance bei Treffer: Gewährt dir Ausdauer +5")
check("ENCHANT-37: a German proc line ('Chance bei Treffer: ... Ausdauer +5') is not a flat stat",
      dict(siE.ItemStats("prose-de")), {"ITEM_MOD_AGILITY_SHORT": 5})
GE.ITEM_ENCHANTMENT = "Enchanted:"
GE.ITEM_MOD_STAMINA_SHORT = "Stamina"

# (3) a title-only tooltip has not built its enchant line yet: it is never kept as
# "no enchant", the scan is re-run until the line is there
rtE.execute("Enum.TooltipDataLineType.ItemName = 1")


def title_tooltop(link, name):
    lines = rtE.eval("{}")
    row = rtE.eval("{}")
    row.leftText = name
    row.type = 1
    lines[1] = row
    data = rtE.eval("{}")
    data.lines = lines
    GE.tooltopsE[link] = data


title_tooltop("tardy", "Embossed Leather Vest")
GE.itemStats["tardy"] = rtE.eval("{ ITEM_MOD_AGILITY_SHORT = 5 }")
GE.itemLoc["tardy"] = "INVTYPE_HAND"
GE.tooltopCallsE = 0
siE.ItemStats("tardy")
siE.ItemStats("tardy")
check("ENCHANT-38: a title-only tooltip is scanned again, not kept as 'no enchant'",
      int(GE.tooltopCallsE), 2)
GE.Tooltop("tardy", "Enchanted: Agility +3")
check("ENCHANT-39: its enchant is read once the tooltip's lines arrive",
      dict(siE.ItemStats("tardy")), {"ITEM_MOD_AGILITY_SHORT": 8})
check("ENCHANT-40: an arrived tooltip is cached then (no scan without new data)",
      int(GE.tooltopCallsE), 3)

print("failed:", failures)
sys.exit(1 if failures else 0)
