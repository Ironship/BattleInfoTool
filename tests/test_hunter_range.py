"""BattleInfoTool module HunterRangeFinder, the hunter's stacked range chevrons.

    python tests/test_hunter_range.py

The fake game and the loading machinery come from tests/test_bit.py (its FAKE chunk, taken out
with the AST so this suite never runs that one), but only the core and the module's own files are
loaded -- the module is not in the .toc yet (the parent adds it). The fake frames accept any
method and record what matters: Show/Hide/SetShown, SetTexture, SetSize, SetPoint, scripts and
events. SetAlpha is added next to them so the tests can see the chevrons and icons fade.

Every scenario runs against the real module through the fake client: ADDON_LOADED, target
changes, ranged polls, /bit commands and the settings tab. Nothing is fabricated live-game
verification; the module itself is never stubbed.
"""
import ast
import pathlib
import sys
import warnings

from lupa.lua51 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent

# The fake game, exactly as tests/test_bit.py defines it, taken from the source with the AST.
_SRC = (ROOT / "tests" / "test_bit.py").read_text(encoding="utf-8")
FAKE = None
with warnings.catch_warnings():  # test_bit.py's own string escapes warn under ast.parse
    warnings.simplefilter("ignore", SyntaxWarning)
    for _node in ast.parse(_SRC).body:
        if isinstance(_node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == "FAKE" for t in _node.targets
        ):
            if isinstance(_node.value, ast.Constant) and isinstance(_node.value.value, str):
                FAKE = _node.value.value
                break
assert isinstance(FAKE, str) and "function CreateFrame" in FAKE
# The fake records the alpha of every texture, so the tests can read the chevrons and icons.
FAKE = FAKE.replace(
    "function methods.GetName(self) return self.name end",
    "function methods.GetName(self) return self.name end\n"
    "function methods.SetAlpha(self, a) self.alpha = a end")

# The hunter-range part of the fake game: known spells and spell info, range answers by spell
# name and by spell id, items in range, a secret value, and the preload recorder.
EXTRA = r"""
SECRET = {}
function issecretvalue(v) return v == SECRET end
spellInfoById = {}      -- id -> { name = ..., minRange = ..., maxRange = ... }
knownSpells = {}        -- id -> true (IsPlayerSpell)
spellRangeByName = {}   -- name -> true / false / nil (the global IsSpellInRange answers)
itemRange = {}          -- id -> true / false / nil (C_Item.IsItemInRange answers)
checkDistance = nil     -- CheckInteractDistance("target", 2)
preloads = {}
C_Spell.GetSpellInfo = function(id) return spellInfoById[id] end
C_Item.IsItemInRange = function(id, unit) return itemRange[id] end
C_Item.RequestLoadItemDataByID = function(id) table.insert(preloads, id) end
function IsSpellInRange(name, unit) return spellRangeByName[name] end
function IsPlayerSpell(id) return knownSpells[id] == true end
function CheckInteractDistance(unit, index) return checkDistance end
"""

MODULE_FILES = (
    "Core/Init.lua",
    "Core/Settings.lua",
    "Modules/HunterRangeFinder/HunterRangeFinder.lua",
)

failures = 0


def check(label, actual, expected=True):
    global failures
    ok = actual == expected
    failures += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {label}" + ("" if ok else f"   (got {actual!r}, expected {expected!r})"))


def load(class_="HUNTER", saved=None):
    rt = LuaRuntime(unpack_returned_tuples=True)
    rt.execute(FAKE)
    rt.execute(EXTRA)
    G = rt.globals()
    G.playerClass = class_
    if saved:
        rt.execute(saved)
    BIT = rt.eval("{}")
    loader = rt.eval(
        "function(src, name, BIT) local f = assert(loadstring(src, '@' .. name)); return f('BattleInfoTool', BIT) end")
    for rel in MODULE_FILES:
        loader((ROOT / rel).read_text(encoding="utf-8"), rel, BIT)
    return rt, G, BIT


def ready(class_="HUNTER", saved=None, spells_changed_first=False):
    """A booted instance: the module loaded, ADDON_LOADED for BIT and for an unrelated addon."""
    rt, G, BIT = load(class_=class_, saved=saved)
    if spells_changed_first:
        G.Fire("SPELLS_CHANGED")
    G.Fire("ADDON_LOADED", "BattleInfoTool")
    G.Fire("ADDON_LOADED", "SomeOtherAddon")
    G.Fire("PLAYER_LOGIN")
    return rt, G, BIT


def module(BIT):
    return BIT.modules["HunterRangeFinder"]


def set_target(G, hostile=True, dead=False):
    G.target = {"hostile": hostile}
    if dead:
        G.units["target"] = {"dead": True}
    else:
        G.units["target"] = None


def clear_target(G):
    G.target = None
    G.units["target"] = None


# Set the range probes. None leaves the current answer; every other value replaces it.
# wing = spell 2974 (Wing Clip), auto = spell 75 (Auto Shot); item ids in **items.
def ranges(G, auto=None, wing=None, item16114=None, dist=None, **items):
    if auto is not None:
        G.inRange[75] = auto
    if wing is not None:
        G.inRange[2974] = wing
    if item16114 is not None:
        G.itemRange[16114] = item16114
    if dist is not None:
        G.checkDistance = dist
    for k, v in items.items():
        G.itemRange[int(str(k)[4:] if str(k).startswith("item") else k)] = v


def hunt(G, ticks=4, dt=0.1):
    """A new target: PLAYER_TARGET_CHANGED, then enough polls for the two consistent readings
    and the 0.16 s chevron animation to settle."""
    G.Fire("PLAYER_TARGET_CHANGED")
    for _ in range(ticks):
        G.Tick(dt)


def settled(G, ticks=3, dt=0.1):
    """More ticks, for a band change or an icon state to settle."""
    for _ in range(ticks):
        G.Tick(dt)


def lua_list(G, t):
    """The values of a Lua array table: lupa iterates tables by key."""
    return [t[i] for i in range(1, len(t) + 1)]


def chev(hud, i):
    return hud["chevrons"][i]


def open_tab(G, BIT):
    G.SlashCmdList.BATTLEINFOTOOL("hunter")
    return BIT._pages["HunterRangeFinder"]


# ---------------------------------------------------------------------------------------------
print("-- the module registers in the core")
rt, G, BIT = ready()
hr = module(BIT)
check("the module is in BIT.modules", BIT.modules["HunterRangeFinder"] is not None, True)
check("it registers a tab with the hunter-word", BIT.tabWords.hunter, "HunterRangeFinder")
tab = BIT.tabs["HunterRangeFinder"]
check("the tab is titled for the hunter", tab.title, "Hunter range")
check("the tab fits the compact window", (tab.width <= 760 and tab.height <= 430), True)
check("no standalone slash names or globals were made",
      (getattr(G, "SLASH_HUNTERRANGEFINDER1", None) is None
       and G.SlashCmdList.HUNTERRANGEFINDER is None
       and G.HunterRangeFinderDB is None), True)
check("/bit hunter opens the settings window",
      open_tab(G, BIT).shown, True)
check("/bit hunterprobe is registered for diagnostics",
      callable(G.SlashCmdList.BATTLEINFOTOOL) and BIT.commands.hunterprobe is not None, True)
check("the addon runs for a hunter", BIT.state["HunterRangeFinder"], "on")

# ---------------------------------------------------------------------------------------------
print("-- the HUD is built at ADDON_LOADED, hidden until there is a target")
hud = hr._hud()
driver = hr._driver()
loader = hr._loader()
check("a HUD frame exists", hud is not None and hud["frame"] is not None, True)
check("the HUD starts hidden", hud["frame"]["shown"], False)
check("the driver starts hidden (no permanent CPU without a target)", driver["shown"], False)
check("only SPELLS_CHANGED stays registered once ADDON_LOADED has run",
      dict(loader["events"]), {"SPELLS_CHANGED": True})
settings = hr._settings()
for key, value in (("x", -135), ("y", -34), ("scale", 1), ("opacity", 1),
                   ("chevronHeight", 1), ("chevronWidth", 1), ("locked", True),
                   ("animateDeadzone", False), ("animateMelee", False),
                   ("showDeadzoneIcon", True), ("showMeleeIcon", True),
                   ("smallBottomChevron", True)):
    check(f"default setting {key}", settings[key], value)
check("the ladder item data is preloaded",
      lua_list(G, G.preloads), [16114, 17626, 10699, 17689, 4559, 10645, 1191, 4388, 13289, 7734, 17202, 835, 2091, 18904])
check("the seven chevron textures come from the module folder",
      [chev(hud, i)["texture"] for i in range(1, 8)],
      ["Interface\\AddOns\\BattleInfoTool\\Modules\\HunterRangeFinder\\Textures\\" + n
       for n in ("Cyan", "Green", "Amber", "Amber", "Amber", "Coral", "CoralShort")])
check("the skull and the crossed swords are module textures too",
      (hud["skull"]["texture"].endswith("DeadzoneSkull"),
       hud["swords"]["texture"].endswith("CrossedSwords")), (True, True))
assets = sorted(p.name for p in (ROOT / "Modules" / "HunterRangeFinder" / "Textures").glob("*.tga"))
check("the seven supplied textures are in the module folder",
      assets, ["Amber.tga", "Coral.tga", "CoralShort.tga", "CrossedSwords.tga",
               "Cyan.tga", "DeadzoneSkull.tga", "Green.tga"])

# ---------------------------------------------------------------------------------------------
print("-- the band ladder, end to end: the stack counts and top chevron")
set_target(G)
# 8-10 yd: one chevron, the small red bottom chevron
ranges(G, auto=True, item16114=False, item17626=True)
hunt(G)
check("8-10 yd: one chevron", chev(hud, 7)["alpha"], 1.0)
check("8-10 yd: the six above are hidden", [chev(hud, i)["alpha"] for i in range(1, 7)],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
check("8-10 yd: the bottom chevron is the small coral one",
      chev(hud, 7)["texture"].endswith("\\CoralShort"), True)
check("8-10 yd: the HUD is up", hud["frame"]["shown"], True)
# 10-15 yd: two chevrons
ranges(G, item17626=False, item4559=True)
settled(G)
check("10-15 yd: two chevrons",
      [chev(hud, i)["alpha"] for i in range(1, 8)], [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0])
# 15-20 yd: three chevrons
ranges(G, item4559=False, item10645=True)
settled(G)
check("15-20 yd: three chevrons",
      [chev(hud, i)["alpha"] for i in range(1, 8)], [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0])
# 20-25 yd: four chevrons
ranges(G, item10645=False, item13289=True)
settled(G)
check("20-25 yd: four chevrons",
      [chev(hud, i)["alpha"] for i in range(1, 8)], [0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
# 25-30 yd: five chevrons
ranges(G, item13289=False, item7734=True)
settled(G)
check("25-30 yd: five chevrons",
      [chev(hud, i)["alpha"] for i in range(1, 8)], [0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0])
# 30-35 yd: six chevrons, green on top
ranges(G, item7734=False, item18904=True)
settled(G)
check("30-35 yd: six chevrons",
      [chev(hud, i)["alpha"] for i in range(1, 8)], [0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
check("30-35 yd: the top chevron is the green one", chev(hud, 2)["texture"].endswith("\\Green"), True)
# beyond 35 yd: the 35 yd probe answers false, Auto Shot in range -> the cyan top enters
ranges(G, item18904=False)
settled(G)
check("past 35 yd: all seven chevrons",
      [chev(hud, i)["alpha"] for i in range(1, 8)], [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
check("past 35 yd: the top chevron is the cyan one", chev(hud, 1)["texture"].endswith("\\Cyan"), True)
# the 35 yd probe unavailable: still six green chevrons, never an unproven cyan (the cyan
# texture stays put on the hidden top chevron; only its alpha proves it is not shown)
ranges(G, item18904=None)
settled(G)
check("35 yd probe missing: stays at six green, no guess past 35",
      ([chev(hud, i)["alpha"] for i in range(1, 8)],
       chev(hud, 2)["texture"].endswith("\\Green")), ([0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0], True))

# ---------------------------------------------------------------------------------------------
print("-- melee, the dead zone and out of range")
# Wing Clip in range, Auto Shot not: melee reach, crossed swords
ranges(G, auto=False, wing=True, item16114=None)
hunt(G)
check("melee: crossed swords show", (hud["frame"]["shown"], hud["swords"]["alpha"]), (True, 1.0))
check("melee: no skull, no chevrons", (hud["skull"]["alpha"], chev(hud, 7)["alpha"]), (0.0, 0.0))
# melee by the item probe when the spell cannot say
ranges(G, auto=False, wing=None, item16114=True)
settled(G)
check("melee: the item probe works too", (hud["swords"]["alpha"], hud["skull"]["alpha"]), (1.0, 0.0))
# melee by CheckInteractDistance when neither can say
ranges(G, auto=False, wing=None, item16114=None, dist=True)
hunt(G)
check("melee: CheckInteractDistance works too", (hud["swords"]["alpha"], hud["frame"]["shown"]), (1.0, True))
# the dead zone: Auto Shot out of range, the 8-10 yd items in range: red skull
G.Fire("PLAYER_TARGET_CHANGED")
ranges(G, auto=False, wing=False, item16114=False, dist=False, item17626=True)
settled(G)
check("dead zone: the skull shows and the frame stays up",
      (hud["skull"]["alpha"], hud["frame"]["shown"]), (1.0, True))
check("dead zone: no swords", hud["swords"]["alpha"], 0.0)
# out of range: everything unknown, a living hostile target: nothing at all is claimed
ranges(G, auto=None, wing=None, item16114=None, dist=None,
       item17626=None, item4559=None, item10645=None, item13289=None, item7734=None, item18904=None)
settled(G, ticks=3)
check("unknown ranges: OOR claims nothing, the frame hides", hud["frame"]["shown"], False)
settled(G, ticks=2)
check("  and stays hidden", hud["frame"]["shown"], False)
# Auto Shot out of range with nothing else: out of range, not the dead zone and not the cyan
ranges(G, auto=False, wing=False, item18904=False)
settled(G)
check("Auto Shot out: OOR, not cyan", hud["frame"]["shown"], False)

# ---------------------------------------------------------------------------------------------
print("-- target rules: no target, friendly, dead")
clear_target(G)
ranges(G, auto=True, item17626=True)
hunt(G)
check("no target: nothing", (hud["frame"]["shown"], hr.CurrentBand()), (False, None))
set_target(G, hostile=False)
hunt(G)
check("friendly target: nothing", (hud["frame"]["shown"], hr.CurrentBand()), (False, None))
set_target(G, dead=True)
hunt(G)
check("dead target: nothing", (hud["frame"]["shown"], hr.CurrentBand()), (False, None))
set_target(G)
hunt(G)
check("a living hostile target acquires again", hud["frame"]["shown"], True)

# ---------------------------------------------------------------------------------------------
print("-- the band logic itself (CurrentBand), every band")
rtB, GB, BITB = ready()
hrB = module(BITB)
set_target(GB)
ranges(GB, auto=True, item16114=False, item17626=True)
check("CurrentBand: 8-10", hrB.CurrentBand(), "Y10")
ranges(GB, item17626=False, item4559=True)
check("CurrentBand: 10-15", hrB.CurrentBand(), "Y15")
ranges(GB, item4559=False, item10645=True)
check("CurrentBand: 15-20", hrB.CurrentBand(), "Y20")
ranges(GB, item10645=False, item13289=True)
check("CurrentBand: 20-25", hrB.CurrentBand(), "Y25")
ranges(GB, item13289=False, item7734=True)
check("CurrentBand: 25-30", hrB.CurrentBand(), "Y30")
ranges(GB, item7734=False, item18904=True)
check("CurrentBand: 30-35", hrB.CurrentBand(), "Y35")
ranges(GB, item18904=False)
check("CurrentBand: past 35 (probe false)", hrB.CurrentBand(), "MAX")
ranges(GB, item18904=None)
check("CurrentBand: past 35 probe missing stays Y35", hrB.CurrentBand(), "Y35")
ranges(GB, auto=False, wing=True)
check("CurrentBand: melee", hrB.CurrentBand(), "MELEE")
ranges(GB, auto=False, wing=False, item17626=True)
check("CurrentBand: dead zone", hrB.CurrentBand(), "DEAD")
ranges(GB, auto=None, wing=None, item17626=None)
check("CurrentBand: unknown is out of range", hrB.CurrentBand(), "OOR")
clear_target(GB)
check("CurrentBand: no target", hrB.CurrentBand(), None)
set_target(GB, hostile=False)
check("CurrentBand: friendly target", hrB.CurrentBand(), None)
set_target(GB, dead=True)
check("CurrentBand: dead target", hrB.CurrentBand(), None)
set_target(GB)
ranges(GB, auto=True, wing=True, item17626=True)
check("CurrentBand: Wing Clip in range with Auto Shot in range is not melee", hrB.CurrentBand(), "Y10")
ranges(GB, auto=1, wing=0, item17626=1)
check("CurrentBand: 0/1 answers normalize to false/true", hrB.CurrentBand(), "Y10")

# ---------------------------------------------------------------------------------------------
print("-- spell names win over ids; the legacy IsItemInRange fallback")
rtN, GN, BITN = ready()
hrN = module(BITN)
set_target(GN)
GN.spellInfoById[75] = rtN.eval("{ name = 'Auto Shot' }")
GN.spellInfoById[2974] = rtN.eval("{ name = 'Wing Clip' }")
ranges(GN, auto=True, item16114=False, item17626=True)
GN.spellRangeByName["Wing Clip"] = False
GN.inRange[2974] = True  # by id it would say melee
check("the name answer wins over the id answer", hrN.CurrentBand(), "Y10")
GN.spellRangeByName["Auto Shot"] = False
GN.inRange[75] = True  # by id it would say in range
ranges(GN, item16114=False, item17626=True)
check("Auto Shot out of range by name, in range by id: the dead zone follows the name answer",
      hrN.CurrentBand(), "DEAD")
rtL, GL, BITL = ready()
hrL = module(BITL)
GL["C_Item"]["IsItemInRange"] = None
GL.itemRangeLegacy = {}
rtL.execute("function IsItemInRange(id, unit) return itemRangeLegacy[id] end")
set_target(GL)
ranges(GL, auto=True, item16114=False, item17626=True)
GL.itemRangeLegacy[17626] = True
check("legacy IsItemInRange answers when C_Item cannot", hrL.CurrentBand(), "Y10")

# ---------------------------------------------------------------------------------------------
print("-- Scatter Shot: the 15 yd rung vs the extended red chevron")
rtS, GS, BITS = ready()
hrS = module(BITS)
hudS = hrS._hud()
set_target(GS)
GS.spellInfoById[19503] = rtS.eval("{ name = 'Scatter Shot', minRange = 0, maxRange = 15 }")
GS.knownSpells[19503] = True
# a learned 15 yd Scatter Shot leaves the chevron amber and uses the 20 yd boundary
ranges(GS, auto=True, item16114=False, item10645=True)  # 15-20 yd band
hunt(GS)
check("15 yd Scatter Shot: the 25-30 yd chevron stays amber",
      chev(hudS, 5)["texture"].endswith("\\Amber"), True)
settled(GS)
ranges(GS, item10645=False, item13289=True)  # 20-25 yd band
settled(GS)
check("20-25 yd with a 15 yd Scatter Shot: four chevrons, amber top",
      (chev(hudS, 4)["alpha"], chev(hudS, 4)["texture"].endswith("\\Amber")), (1.0, True))
# Scatter Shot observed in range beyond the 15 yd rung: the chevron turns coral
GS.inRange[19503] = True
settled(GS)
check("Scatter Shot in range at 20-25: the red chevron stays on top",
      (chev(hudS, 5)["texture"].endswith("\\Coral"), chev(hudS, 5)["alpha"]), (True, 1.0))
check("  and only three chevrons show",
      [chev(hudS, i)["alpha"] for i in (3, 4)], [0.0, 0.0])
# Scatter Shot leaves range: the next (yellow) chevron enters; the red chevron itself stays
# red -- it marks the extended 15-20 yd band, which talents do not unlearn mid-combat
GS.inRange[19503] = False
settled(GS)
check("Scatter Shot out of range: the red chevron stays, the fourth row returns",
      (chev(hudS, 5)["texture"].endswith("\\Coral"), chev(hudS, 4)["alpha"]), (True, 1.0))
# a maximum range beyond 15 yd also turns the chevron red (no observation needed)
GS.spellInfoById[19503] = rtS.eval("{ name = 'Scatter Shot', minRange = 0, maxRange = 21 }")
GS.Fire("SPELLS_CHANGED")
settled(GS)
check("maxRange 21 without observation: red chevron",
      chev(hudS, 5)["texture"].endswith("\\Coral"), True)
# an unlearned Scatter Shot changes nothing
rtU, GU, BITU = ready()
hrU = module(BITU)
hudU = hrU._hud()
set_target(GU)
ranges(GU, auto=True, item16114=False, item10645=True)
hunt(GU)
check("no Scatter Shot learned: amber, three chevrons",
      (chev(hudU, 5)["texture"].endswith("\\Amber"), chev(hudU, 5)["alpha"]), (True, 1.0))

# ---------------------------------------------------------------------------------------------
print("-- acquisition: two consistent polls, and the previous target never lingers")
rtA, GA, BITA = ready()
hrA = module(BITA)
hudA = hrA._hud()
set_target(GA)
ranges(GA, auto=True, item16114=False, item13289=True)  # 20-25
GA.Fire("PLAYER_TARGET_CHANGED")
GA.Tick(0.1)
check("first poll only: still acquiring, nothing shown", hudA["frame"]["shown"], False)
GA.Tick(0.1)
check("second consistent poll: acquired", hudA["frame"]["shown"], True)
settled(GA)
check("20-25 after acquisition: four chevrons", chev(hudA, 4)["alpha"], 1.0)
# readings that disagree reset the count: Y30 then Y35 then Y35
ranges(GA, item13289=False, item7734=True)
GA.Fire("PLAYER_TARGET_CHANGED")
GA.Tick(0.1)
ranges(GA, item7734=False, item18904=True)
GA.Tick(0.1)
check("a differing reading still holds", hudA["frame"]["shown"], False)
GA.Tick(0.1)
check("two consistent readings of the new band acquire", hudA["frame"]["shown"], True)
settled(GA)
check("  as the new band", chev(hudA, 2)["alpha"], 1.0)
# the previous target's stack clears the moment the target changes
ranges(GA, auto=True, item18904=True)
settled(GA)
check("30-35 shown before the change", chev(hudA, 2)["alpha"], 1.0)
ranges(GA, item18904=False)
GA.Fire("PLAYER_TARGET_CHANGED")
check("the old stack clears at once", hudA["frame"]["shown"], False)
settled(GA, ticks=4)
check("  and the new target acquires fresh", chev(hudA, 1)["alpha"], 1.0)
# the driver polls only while a target exists
clear_target(GA)
GA.Fire("PLAYER_TARGET_CHANGED")
check("no target: the driver stops polling", hrA._driver()["shown"], False)
check("  and the frame is down", hudA["frame"]["shown"], False)

# ---------------------------------------------------------------------------------------------
print("-- preview, drag and the settings tab")
rtP, GP, BITP = ready()
hrP = module(BITP)
hudP = hrP._hud()
page = open_tab(GP, BITP)
content = page.content
check("the hunter's tab builds its widgets",
      (page.hunterNote is None, content.lockButton is not None), (True, True))
check("the tab is locked at first", GP.BattleInfoToolDB.modules.HunterRangeFinder.locked, True)
content.lockButton.scripts["OnClick"](content.lockButton)
check("unlock shows the full preview stack",
      (GP.BattleInfoToolDB.modules.HunterRangeFinder.locked, hudP["frame"]["shown"]), (False, True))
settled(GP)
check("  seven chevrons in preview",
      [chev(hudP, i)["alpha"] for i in range(1, 8)], [1.0] * 7)
# dragging without measurable frames changes nothing and does not error
before = (GP.BattleInfoToolDB.modules.HunterRangeFinder.x, GP.BattleInfoToolDB.modules.HunterRangeFinder.y)
hudP["frame"].scripts["OnDragStop"](hudP["frame"])
check("a drag without GetCenter numbers saves nothing and does not error",
      (GP.BattleInfoToolDB.modules.HunterRangeFinder.x, GP.BattleInfoToolDB.modules.HunterRangeFinder.y), before)
# a real drag saves the ordinary offsets
hudP["frame"]["GetCenter"] = lambda *a: (400, 300)
hudP["frame"]["GetEffectiveScale"] = lambda *a: 1
GP.UIParent["GetCenter"] = lambda *a: (512, 384)
GP.UIParent["GetEffectiveScale"] = lambda *a: 1
hudP["frame"].scripts["OnDragStop"](hudP["frame"])
check("a measured drag saves the offsets",
      (GP.BattleInfoToolDB.modules.HunterRangeFinder.x, GP.BattleInfoToolDB.modules.HunterRangeFinder.y),
      (-112, -84))
# the sliders write and apply the settings
content.sliders.scale.bar.scripts["OnValueChanged"](content.sliders.scale.bar, 2.0)
check("the size slider stores 2.0", GP.BattleInfoToolDB.modules.HunterRangeFinder.scale, 2.0)
content.sliders.opacity.bar.scripts["OnValueChanged"](content.sliders.opacity.bar, 0.25)
check("the opacity slider stores 0.25",
      GP.BattleInfoToolDB.modules.HunterRangeFinder.opacity, 0.25)
content.sliders.height.bar.scripts["OnValueChanged"](content.sliders.height.bar, 1.2)
check("the chevron height slider stores 1.2",
      GP.BattleInfoToolDB.modules.HunterRangeFinder.chevronHeight, 1.2)
check("  and re-sizes the chevrons", (chev(hudP, 2)["width"], chev(hudP, 2)["height"]), (68.0, 45.6))
content.sliders.width.bar.scripts["OnValueChanged"](content.sliders.width.bar, 1.5)
check("the chevron width slider stores 1.5 and widens the chevrons",
      (GP.BattleInfoToolDB.modules.HunterRangeFinder.chevronWidth, chev(hudP, 2)["width"]), (1.5, 102.0))
content.lockButton.scripts["OnClick"](content.lockButton)
check("locking ends the preview", (GP.BattleInfoToolDB.modules.HunterRangeFinder.locked,
                                  hudP["frame"]["shown"]), (True, False))
# the switch boxes are present and flip the saved flags: the fake box answers GetChecked before
# the click, so each box is toggled first, as the player's click would have
content.deadAnim["checked"] = True
content.deadAnim.scripts["OnClick"](content.deadAnim)
content.meleeAnim["checked"] = True
content.meleeAnim.scripts["OnClick"](content.meleeAnim)
content.deadIcon["checked"] = False  # the box was checked (the default on): the click unchecks it
content.deadIcon.scripts["OnClick"](content.deadIcon)
content.meleeIcon["checked"] = False
content.meleeIcon.scripts["OnClick"](content.meleeIcon)
content.smallBottom["checked"] = False
content.smallBottom.scripts["OnClick"](content.smallBottom)
check("the four animation/icon switches flip their flags",
      (GP.BattleInfoToolDB.modules.HunterRangeFinder.animateDeadzone,
       GP.BattleInfoToolDB.modules.HunterRangeFinder.animateMelee,
       GP.BattleInfoToolDB.modules.HunterRangeFinder.showDeadzoneIcon,
       GP.BattleInfoToolDB.modules.HunterRangeFinder.showMeleeIcon), (True, True, False, False))
check("the small bottom chevron switch flips and the texture follows",
      (GP.BattleInfoToolDB.modules.HunterRangeFinder.smallBottomChevron,
       chev(hudP, 7)["texture"].endswith("\\Coral")), (False, True))
# with the dead-zone animation switched on the skull fades in instead of appearing at once
settingsP = hrP._settings()
settingsP["showDeadzoneIcon"] = True
settingsP["animateDeadzone"] = True
set_target(GP)
ranges(GP, auto=False, wing=False, item16114=False, item17626=True)
hunt(GP, ticks=2)
check("animation on: the frame returns and the skull is mid-fade",
      (hudP["frame"]["shown"], 0.0 < hudP["skull"]["alpha"] < 1.0), (True, True))
settled(GP)
check("  and reaches full once settled", hudP["skull"]["alpha"], 1.0)

# ---------------------------------------------------------------------------------------------
print("-- saved values are validated")
rtV, GV, BITV = ready(saved="BattleInfoToolDB = { modules = { HunterRangeFinder = { scale = 99, opacity = 'high', "
                            "chevronHeight = 0.01, chevronWidth = 4, x = 'bewildered', y = 6 } } }")
hrV = module(BITV)
sV = hrV._settings()
check("saved garbage is clamped to the slider bounds",
      (sV["scale"], sV["opacity"], sV["chevronHeight"], sV["chevronWidth"]), (3.0, 1.0, 0.5, 1.5))
check("a saved ordinary number survives, a wrong one falls back",
      (sV["x"], sV["y"]), (-135, 6))

# ---------------------------------------------------------------------------------------------
print("-- disabled module, and non-hunter classes")
rtD, GD, BITD = ready(saved="BattleInfoToolDB = { modules = { HunterRangeFinder = { enabled = false } } }")
hrD = module(BITD)
check("switched off: no HUD, no driver", (hrD._hud(), hrD._driver()), (None, None))
check("switched off: the state is off", BITD.state["HunterRangeFinder"], "off")
check("switched off: no events stay registered", dict(hrD._loader()["events"]), {})
GD.SlashCmdList.BATTLEINFOTOOL("hunter")
pageD = BITD._pages["HunterRangeFinder"]
check("the tab still opens with the off note", pageD.offNote is not None, True)
check("  the off note explains",
      pageD.offNote.text,
      "Seven stacked chevrons tell a hunter where the target is, from 8-10 yd to past Auto Shot's maximum.\n\n"
      "Its settings are here while it runs.")
rtW, GW, BITW = ready(class_="WARLOCK")
hrW = module(BITW)
check("a non-hunter class: no HUD, no driver, no events", (hrW._hud(), hrW._driver()), (None, None))
check("a non-hunter class: no events stay registered", dict(hrW._loader()["events"]), {})
check("a non-hunter class: the module itself runs", BITW.state["HunterRangeFinder"], "on")
check("a non-hunter class: no item preloads", lua_list(GW, GW.preloads), [])
GW.SlashCmdList.BATTLEINFOTOOL("hunter")
pageW = BITW._pages["HunterRangeFinder"]
check("the tab explains the hunter-only module", pageW.content.hunterNote is not None, True)
check("  with the word hunter in it", "Hunter" in (pageW.content.hunterNote.text or ""), True)

# ---------------------------------------------------------------------------------------------
print("-- event order, secrets and the probe")
rtE, GE, BITE = ready(spells_changed_first=True)
hrE = module(BITE)
check("SPELLS_CHANGED before ADDON_LOADED does not break the boot", BITE.state["HunterRangeFinder"], "on")
set_target(GE)
ranges(GE, auto=True, item16114=False, item4559=True)
hunt(GE)
check("  a band still reads", chev(hrE._hud(), 6)["alpha"], 1.0)
GE.Fire("SPELLS_CHANGED")
check("SPELLS_CHANGED after boot clears the spell cache without error", hrE.CurrentBand(), "Y15")
# a range answer that is a secret is treated as unknown and never read
GE.inRange[75] = GE.SECRET
GE.itemRange[4559] = None
GE.itemRange[17626] = False
settled(GE)
check("a secret range answer is unknown, not mislabelled", hrE.CurrentBand(), "OOR")
# the probe never stringifies a raw secret
GE.inRange[75] = rtE.eval("1876543")
rtE.execute("SECRET_NUM = 1876543 function issecretvalue(v) return v == SECRET or v == SECRET_NUM end")
GE.itemRange[18904] = rtE.eval("1876543")
GE.SlashCmdList.BATTLEINFOTOOL("hunterprobe")
probe = hrE.Probe()
check("the probe reports the secret as secret, never the raw number",
      ("secret" in probe and "1876543" not in probe), True)
check("the probe names the band", "band=" in probe and "OOR" in probe, True)
check("/bit hunterprobe prints the readout",
      any("35 yd item" in m for m in [GE.chat[i] for i in range(1, len(GE.chat) + 1)]), True)
# a sane probe line for a known band
GE.inRange[75] = True
GE.itemRange[18904] = False
GE.itemRange[4559] = False
GE.itemRange[17626] = False
settled(GE)
probe2 = hrE.Probe()
check("a living target at MAX prints the cyan band", "MAX" in probe2, True)

print("failed:", failures)
sys.exit(1 if failures else 0)