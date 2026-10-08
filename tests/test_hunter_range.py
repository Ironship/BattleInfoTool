"""Drive the shipped Hunter native dots rail through the real .toc and fake client.

    python tests/test_hunter_range.py

Checks range probes, acquisition, secrets, drag/reset, preview, class/module gates
and the native render state. These are offline checks, not live WoW verification.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
source = (ROOT / "tests/test_bit.py").read_text(encoding="utf-8")
fixture = {"__file__": str(ROOT / "tests/test_bit.py")}
exec(compile(source.split('print("-- every module on")', 1)[0], "fixture", "exec"), fixture)
fixture["FAKE"] = fixture["FAKE"].replace(
    "function methods.GetName(self) return self.name end",
    "function methods.GetName(self) return self.name end\n"
    "function methods.SetAlpha(self, a) self.alpha = a end\n"
    "function methods.SetVertexColor(self, r, g, b, a) self.color = {r, g, b, a} end\n"
    "function methods.SetColorTexture(self, r, g, b, a) self.color = {r, g, b, a} end")

EXTRA = """
SECRET = {}
function issecretvalue(value) return value == SECRET end
spellInfoById, knownSpells, spellRangeByName, itemRange, preloads = {}, {}, {}, {}, {}
C_Spell.GetSpellInfo = function(id) return spellInfoById[id] end
C_Item.IsItemInRange = function(id) return itemRange[id] end
C_Item.RequestLoadItemDataByID = function(id) table.insert(preloads, id) end
function IsSpellInRange(name) return spellRangeByName[name] end
function IsPlayerSpell(id) return knownSpells[id] == true end
function CheckInteractDistance() return checkDistance end
"""


def ready(class_="HUNTER", saved="", spells_changed_first=False):
    rt, G, BIT, files = fixture["load"](EXTRA + "\nplayerClass='" + class_ + "'\n" + saved)
    if spells_changed_first:
        G.Fire("SPELLS_CHANGED")
    G.Fire("ADDON_LOADED", "BattleInfoTool")
    G.Fire("ADDON_LOADED", "SomeOtherAddon")
    G.Fire("PLAYER_LOGIN")
    assert "Core\\Appearance.lua" in files and "Modules\\HunterRangeFinder\\HunterRangeFinder.lua" in files
    return rt, G, BIT, BIT.modules["HunterRangeFinder"]


def target(rt, G, hostile=True, dead=False):
    G.target = rt.table_from({"hostile": hostile})
    G.units["target"] = rt.table_from({"dead": True}) if dead else None


def clear(G):
    G.target = G.units["target"] = None


# Explicit None clears a probe. The retired helper silently ignored None, causing
# the supposed unknown-range scenarios to keep their previous known answers.
UNSET = object()


def ranges(G, auto=UNSET, wing=UNSET, dist=UNSET, **items):
    if auto is not UNSET:
        G.inRange[75] = auto
    if wing is not UNSET:
        G.inRange[2974] = wing
    if dist is not UNSET:
        G.checkDistance = dist
    for key, value in items.items():
        G.itemRange[int(key.removeprefix("item"))] = value


def polls(G, count=3):
    for _ in range(count):
        G.Tick(0.1)


def acquire(G):
    G.Fire("PLAYER_TARGET_CHANGED")
    polls(G)


def lit(hud):
    return sum(slot.shown and slot.markers[1].fill.color[4] > 0.25
               for slot in hud.slots.values())


def click(button):
    button.scripts.OnClick(button)


rt, G, BIT, hr = ready()
hud = hr._hud()
assert BIT.state.HunterRangeFinder == "on"
assert BIT.tabWords.hunter == "HunterRangeFinder" and BIT.commands.hunterprobe is not None
assert not hud.shown and not hr._driver().shown
assert dict(hr._loader().events) == {"SPELLS_CHANGED": True}
assert list(G.preloads.values()) == [16114, 17626, 10699, 17689, 4559, 10645, 1191,
                                   4388, 13289, 7734, 17202, 835, 2091, 18904]
assert BIT.Style.Resolve("HunterRangeFinder").shape == "dots"
assert hud.deadIcon.texture == "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
assert hud.meleeIcon.texture == "Interface\\Icons\\INV_Sword_04"
assert G.HunterRangeFinderDB is None and G.SlashCmdList.HUNTERRANGEFINDER is None

# Six near-to-far dots by default; each range rung lights one more.
target(rt, G)
ranges(G, auto=True, wing=False, item16114=False, item17626=True)
acquire(G)
assert hr.CurrentBand() == "Y10" and lit(hud) == 1 and not hud.slots[7].shown
for previous, probe, band, count in (
    (17626, 4559, "Y15", 2), (4559, 10645, "Y20", 3),
    (10645, 13289, "Y25", 4), (13289, 7734, "Y30", 5), (7734, 18904, "Y35", 6),
):
    ranges(G, **{f"item{previous}": False, f"item{probe}": True})
    polls(G)
    assert hr.CurrentBand() == band and lit(hud) == count, (band, hr.CurrentBand(), lit(hud))
    assert "approx." in hud.zone.text
ranges(G, item18904=False)
polls(G)
assert hr.CurrentBand() == "Y35" and lit(hud) == 6, "no seventh dot without extended range"
hr._settings().longRange = True
acquire(G)
assert hr.CurrentBand() == "MAX" and lit(hud) == 7
ranges(G, item18904=None)
polls(G)
assert hr.CurrentBand() == "MAX", "lower false probes still prove extended distance"
for item in (17626, 4559, 10645, 13289, 7734, 18904):
    G.itemRange[item] = None
polls(G)
assert hr.CurrentBand() == "Y35" and lit(hud) == 6, "unknown distance cannot prove the seventh dot"

# Melee, dead zone, unavailable probes and invalid targets cannot retain the old rail.
ranges(G, auto=False, wing=True)
polls(G)
assert hr.CurrentBand() == "MELEE" and hud.meleeIcon.shown and not hud.deadIcon.shown
assert not hud.rail.shown and hud.zone.text == "MELEE"
ranges(G, wing=None, item16114=True)
polls(G)
assert hr.CurrentBand() == "MELEE"
ranges(G, item16114=None, dist=True)
polls(G)
assert hr.CurrentBand() == "OOR", "trade interaction distance cannot prove melee reach"
ranges(G, wing=False, item16114=False, dist=False, item17626=True)
polls(G)
assert hr.CurrentBand() == "DEAD" and hud.deadIcon.shown and not hud.meleeIcon.shown
ranges(G, auto=None, wing=None, item16114=None, item17626=None)
polls(G)
assert hr.CurrentBand() == "OOR" and not hud.shown
ranges(G, auto=False, wing=False, item18904=False)
polls(G)
assert hr.CurrentBand() == "OOR" and not hud.shown
for hostile, dead in ((False, False), (True, True)):
    target(rt, G, hostile, dead)
    acquire(G)
    assert hr.CurrentBand() is None and not hud.shown
clear(G)
acquire(G)
assert hr.CurrentBand() is None and not hud.shown and not hr._driver().shown

# Name-first probes, 0/1 answers and the legacy item API remain supported.
rtN, GN, BITN, hrN = ready()
target(rtN, GN)
GN.spellInfoById[75] = rtN.table_from({"name": "Auto Shot"})
GN.spellInfoById[2974] = rtN.table_from({"name": "Wing Clip"})
GN.spellRangeByName["Auto Shot"] = True
GN.spellRangeByName["Wing Clip"] = False
ranges(GN, auto=False, wing=True, item16114=False, item17626=True)
assert hrN.CurrentBand() == "Y10", "readable ranked spell name takes precedence"
GN.spellRangeByName["Auto Shot"] = False
assert hrN.CurrentBand() == "DEAD"
GN.C_Item.IsItemInRange = None
rtN.execute("function IsItemInRange(id) return itemRange[id] end")
GN.spellRangeByName["Auto Shot"] = None
GN.spellRangeByName["Wing Clip"] = None
ranges(GN, auto=1, wing=0, item17626=1)
assert hrN.CurrentBand() == "Y10"

# Scatter's extended reach marks only the 15-20 yd slot, without a false latch
# from an out-of-range answer; a real observed extension remains until SPELLS_CHANGED.
rtS, GS, BITS, hrS = ready()
target(rtS, GS)
GS.knownSpells[19503] = True
GS.spellInfoById[19503] = rtS.table_from({"name": "Scatter Shot", "maxRange": 15})
ranges(GS, auto=True, item16114=False, item4559=False, item10645=True)
GS.inRange[19503] = False
acquire(GS)
slot = hrS._hud().slots[3].markers[1].fill
normal = tuple(slot.color[i] for i in range(1, 4))
bad = tuple(BITS.Style.Resolve("HunterRangeFinder").colors.bad[i] for i in range(1, 4))
assert normal != bad and lit(hrS._hud()) == 3
GS.inRange[19503] = True
polls(GS)
assert tuple(slot.color[i] for i in range(1, 4)) == bad
ranges(GS, item10645=False, item13289=True)
polls(GS)
assert hrS.CurrentBand() == "Y25" and lit(hrS._hud()) == 3
GS.inRange[19503] = False
polls(GS)
assert tuple(slot.color[i] for i in range(1, 4)) == bad and lit(hrS._hud()) == 4
GS.Fire("SPELLS_CHANGED")
polls(GS)
assert tuple(slot.color[i] for i in range(1, 4)) != bad
GS.spellInfoById[19503].maxRange = 21
GS.Fire("SPELLS_CHANGED")
polls(GS)
assert tuple(slot.color[i] for i in range(1, 4)) == bad

# A target switch clears immediately and needs two agreeing readings before showing.
rtA, GA, BITA, hrA = ready()
target(rtA, GA)
ranges(GA, auto=True, item16114=False, item13289=True)
GA.Fire("PLAYER_TARGET_CHANGED")
polls(GA, 1)
assert not hrA._hud().shown
polls(GA, 1)
assert hrA._hud().shown and lit(hrA._hud()) == 4
ranges(GA, item13289=False, item7734=True)
GA.Fire("PLAYER_TARGET_CHANGED")
assert not hrA._hud().shown
polls(GA, 1)
ranges(GA, item7734=False, item18904=True)
polls(GA, 1)
assert not hrA._hud().shown
polls(GA, 1)
assert hrA._hud().shown and lit(hrA._hud()) == 6

# Settings preview and live dragging use current rows/buttons, not retired chevrons.
rtP, GP, BITP, hrP = ready()
GP.SlashCmdList.BATTLEINFOTOOL("hunter")
content = BITP._pages.HunterRangeFinder.content
assert content.lockButton.widget is not None and hrP._previewScene() is not None
hrP._settings().longRange = True
click(content.lockButton.widget)
polls(GP)
assert not hrP._settings().locked and hrP._hud().shown and lit(hrP._hud()) == 7
before = (hrP._settings().x, hrP._settings().y)
hrP._hud().scripts.OnDragStop(hrP._hud())
assert (hrP._settings().x, hrP._settings().y) == before
hrP._hud().GetCenter = rtP.eval("function() return 400, 300 end")
hrP._hud().GetEffectiveScale = rtP.eval("function() return 1 end")
GP.UIParent.GetCenter = rtP.eval("function() return 512, 384 end")
GP.UIParent.GetEffectiveScale = rtP.eval("function() return 1 end")
hrP._hud().scripts.OnDragStop(hrP._hud())
assert (hrP._settings().x, hrP._settings().y) == (-112, -84)
click(content.resetPosition.widget)
assert (hrP._settings().x, hrP._settings().y) == (0.19970703125, -229.9999389648438)
BITP.Style.Set("HunterRangeFinder", "opacity", 0.5)
assert hrP._hud().slots[1].markers[1].fill.color[4] == 0.5
click(content.lockButton.widget)
assert hrP._settings().locked and not hrP._hud().shown
hrP._previewBand("MELEE")
assert hrP._previewScene().meleeIcon.shown and not hrP._previewScene().deadIcon.shown
hrP._previewBand("DEAD")
assert hrP._previewScene().deadIcon.shown and not hrP._previewScene().meleeIcon.shown
content.deadIcon.widget.checked = False
click(content.deadIcon.widget)
assert not hrP._settings().showDeadzoneIcon and not hrP._previewScene().deadIcon.shown

# The loader preserves the no-gameplay-resource contract for off and non-hunter runs.
for class_, saved, state in (
    ("HUNTER", "BattleInfoToolDB={modules={HunterRangeFinder={enabled=false}}}", "off"),
    ("WARLOCK", "", "on"),
):
    rtD, GD, BITD, hrD = ready(class_, saved)
    assert hrD._hud() is None and hrD._driver() is None and dict(hrD._loader().events) == {}
    assert BITD.state.HunterRangeFinder == state and len(GD.preloads) == 0
    BITD.OpenSettings("HunterRangeFinder")
    assert BITD._pages.HunterRangeFinder.shown
    if state == "off":
        assert BITD._pages.HunterRangeFinder.offNote is not None
    else:
        assert BITD._pages.HunterRangeFinder.content.hunterNote is not None

# Saved legacy geometry remains bounded, and screen-coordinate reset is exact.
rtV, GV, BITV, hrV = ready(saved="BattleInfoToolDB={modules={HunterRangeFinder={"
                          "scale=99, opacity='high', chevronHeight=0.01, chevronWidth=4, x='bad', y=6}}}")
values = hrV._settings()
assert (values.scale, values.opacity, values.chevronHeight, values.chevronWidth) == (3, 1, 0.5, 1.5)
assert (values.x, values.y) == (0.19970703125, 6)
rtL, GL, BITL, hrL = ready(saved="function GetSpellInfo(id) "
                          "if id==75 then return 'Auto Shot', nil, nil, nil, 8, 41 end end")
assert hrL._settings().longRange is True
target(rtL, GL)
ranges(GL, auto=True, item16114=False, item18904=False)
acquire(GL)
assert hrL.CurrentBand() == "MAX" and lit(hrL._hud()) == 7

rtE, GE, BITE, hrE = ready(spells_changed_first=True)
target(rtE, GE)
ranges(GE, auto=True, item16114=False, item4559=True)
acquire(GE)
assert hrE.CurrentBand() == "Y15"
GE.Fire("SPELLS_CHANGED")
assert hrE.CurrentBand() == "Y15"
ranges(GE, auto=GE.SECRET, item4559=None, item17626=False)
polls(GE)
assert hrE.CurrentBand() == "OOR"
rtE.execute("SECRET_NUM=1876543; function issecretvalue(v) return v==SECRET or v==SECRET_NUM end")
ranges(GE, auto=1876543, item18904=1876543)
probe = hrE.Probe()
assert "secret" in probe and "1876543" not in probe and "band=OOR" in probe
GE.SlashCmdList.BATTLEINFOTOOL("hunterprobe")
assert any("35 yd item" in text for text in GE.chat.values())

print("ok Hunter: shipped .toc/dots, every band, long range, melee/dead/unknown, target acquisition, name/legacy probes, preview/drag/reset, gates and secrets")
