"""Replay final-review regressions through the shipped TOC in Lua 5.1."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
namespace = {"__file__": str(ROOT / "tests/test_bit.py")}
source = (ROOT / "tests/test_bit.py").read_text(encoding="utf-8")
exec(compile(source.split('print("-- every module on")', 1)[0], "fixture", "exec"), namespace)
namespace["FAKE"] += '\nfunction GameFontNormalSmall:GetFont() return "Fonts\\\\FRIZQT__.TTF",12 end\n'
load = namespace["load"]

# Preparing an OFF module is a settings operation. Repeated toggles must neither
# build an unbounded collection of windows nor resurrect a hidden singleton.
names = ("SpellDamageInfo", "DoTInfo", "StatsInfo", "ResourceDing", "Range", "ShieldsInfo", "HunterRangeFinder")
saved = "BattleInfoToolDB={modules={" + ",".join(name + "={enabled=false}" for name in names) + "}}"
rt, G, BIT, _ = load(saved)
G.Fire("ADDON_LOADED", "BattleInfoTool")
G.Fire("PLAYER_LOGIN")
for name in names:
    BIT.OpenSettings(name)
    off = BIT._pages[name]
    off.switch.SetChecked(off.switch, True)
    off.switch.scripts.OnClick(off.switch)
    prepared = BIT._pages[name]
    assert not G.Same(off, prepared) and prepared.content is not None
    assert prepared.content.IsVisible(prepared.content)
    warm_count = len(G.AllFrames)
    for _ in range(5):
        prepared.switch.SetChecked(prepared.switch, False)
        prepared.switch.scripts.OnClick(prepared.switch)
        assert G.Same(BIT._pages[name], off) and not prepared.IsVisible(prepared)
        off.switch.SetChecked(off.switch, True)
        off.switch.scripts.OnClick(off.switch)
        assert G.Same(BIT._pages[name], prepared) and prepared.content.IsVisible(prepared.content)
    assert len(G.AllFrames) == warm_count, name
    assert not BIT.IsRunning(name), name
assert not any("could not" in str(text) for text in G.chat.values()), list(G.chat.values())

# Removing a subscriber must not truncate the callback array and lose listeners
# when the next subscriber is appended.
rt.execute("hits={a=0,b=0,c=0}")
stop_a = BIT.Style.Subscribe("Review", rt.eval("function() hits.a=hits.a+1 end"))
BIT.Style.Subscribe("Review", rt.eval("function() hits.b=hits.b+1 end"))
stop_a()
BIT.Style.Subscribe("Review", rt.eval("function() hits.c=hits.c+1 end"))
BIT.Style.Set("Review", "scale", 1.1)
assert (G.hits.a, G.hits.b, G.hits.c) == (0, 1, 1)

# Malformed saved settings must not flow to native geometry setters or checks.
rt, G, BIT, _ = load('''
playerClass="HUNTER"
BattleInfoToolDB={modules={Range={size=0/0,showIn="false"},
HunterRangeFinder={plateOffset=math.huge,attachToPlate="false"}}}
BattleInfoTool_ResourceDingDB={dots="false",dotOffset=0/0,shardOffset=math.huge}
''')
G.Fire("ADDON_LOADED", "BattleInfoTool")
G.Fire("PLAYER_LOGIN")
assert BIT.DB().modules.Range.size == 26 and BIT.DB().modules.Range.showIn is True
assert BIT.DB().modules.HunterRangeFinder.plateOffset == -8
assert BIT.DB().modules.HunterRangeFinder.attachToPlate is True
assert G.BattleInfoTool_ResourceDingDB.dots is True
assert G.BattleInfoTool_ResourceDingDB.dotOffset == G.BattleInfoTool_ResourceDingDB.shardOffset == 2

# Hunter preview and live lane share the same edge/offset. Range owns the target
# mark whenever the hunter rail is hidden, including out-of-range acquisition.
rt, G, BIT, _ = load('playerClass="HUNTER"')
rt.execute('''
spellAnswers, itemAnswers={}, {}
C_Spell.GetSpellInfo=function(id) return {name=tostring(id),maxRange=id==19503 and 15 or 35} end
C_Spell.GetSpellName=function(id) return tostring(id) end
C_Spell.IsSpellInRange=function(id) return spellAnswers[tonumber(id)] end
C_Item.IsItemInRange=function(id) return itemAnswers[id] end
function IsPlayerSpell() return true end
function CheckInteractDistance() return true end
target={hostile=true}; plate=NewPlate()
''')
G.Fire("ADDON_LOADED", "BattleInfoTool")
G.Fire("PLAYER_LOGIN")
hunter, ranged = BIT.modules.HunterRangeFinder, BIT.modules.Range
G.spellAnswers[75] = True
G.itemAnswers[17626] = True
assert hunter.CurrentBand() == "Y10", "trade distance cannot establish melee"
BIT.OpenSettings("HunterRangeFinder")
scene = hunter._previewScene()
assert (scene.points[1][1], scene.points[1][3], scene.points[1][5]) == ("TOP", "BOTTOM", 8)
G.spellAnswers[2974] = False
G.spellAnswers[75] = False
for item in (17626, 10699, 17689, 4559, 10645, 1191, 4388, 13289, 7734, 17202, 835, 2091, 18904):
    G.itemAnswers[item] = False
G.Fire("PLAYER_TARGET_CHANGED")
G.Tick(0.2)
G.Tick(0.2)
ranged.Update()
assert not hunter._hud().shown and ranged._icon().shown
assert ranged._icon().texture.texture.endswith("NotReady")
assert not BIT.Plate.HunterOwnsNameplate(G.plate)
G.spellAnswers[75] = True
G.itemAnswers[4559] = True
G.Tick(0.2)
G.Tick(0.2)
ranged.Update()
assert hunter._hud().shown and not ranged._icon().shown
assert BIT.Plate.HunterOwnsNameplate(G.plate)

# Unknown 15-yard evidence cannot establish talent-extended Scatter Shot. A
# definite false 15-yard probe plus Scatter in range can establish it.
G.itemAnswers[4559] = None
G.itemAnswers[10645] = True
G.spellAnswers[19503] = True
G.Fire("SPELLS_CHANGED")
G.Tick(0.2)
fill = hunter._hud().slots[3].markers[1].fill
fill.SetVertexColor = rt.eval("function(self,...) self.reviewColor={...} end")
G.Fire("SPELLS_CHANGED")
G.Tick(0.2)
assert hunter.CurrentBand() == "Y20"
style = BIT.Style.Resolve("HunterRangeFinder")
assert list(fill.reviewColor.values())[:3] == list(style.colors.distanceMid.values())[:3]
G.itemAnswers[4559] = False
G.Tick(0.2)
assert list(fill.reviewColor.values())[:3] == list(style.colors.bad.values())[:3]

# Frames supplied only by compact hooks (nested raid pool / arena UI) remain
# drawn on the following tick, then clear when the frame hides or changes unit.
rt, G, BIT, _ = load()
rt.execute('''
function CompactUnitFrame_UpdateAll() end
function UnitGetTotalAbsorbs(u) return units[u] and units[u].absorb end
compact=FakeMock("compact",UIParent); compact.unit="raid7"
compact.healthBar=FakeMock("healthBar",compact)
units.raid7={absorb=123,max=500}; units.arena1={absorb=77,max=600}
''')
G.Fire("ADDON_LOADED", "BattleInfoTool")
G.Fire("PLAYER_LOGIN")
shield = BIT.modules.ShieldsInfo
G.CompactUnitFrame_UpdateAll(G.compact)
overlay = shield._overlay(G.compact.healthBar)
assert overlay is not None and overlay.bar.shown
overlay.bar.SetValue = rt.eval("function(self,v) self.value=v end")
shield.Update()
assert overlay.bar.shown and overlay.bar.value == 123
G.compact.unit = "arena1"
shield.Update()
assert overlay.bar.shown and overlay.bar.value == 77
G.compact.Hide(G.compact)
shield.Update()
assert not overlay.bar.shown
G.compact.Show(G.compact)
G.compact.unit = "nameplate1"
G.CompactUnitFrame_UpdateAll(G.compact)
shield.Update()
assert not overlay.bar.shown, "nameplates must follow their own display switch"

# Reset defaults refreshes both live marker kinds, not just combo dots.
rd = BIT.modules.ResourceDing
rt.execute("dotRefreshes=0; shardRefreshes=0")
rd.RefreshDots = rt.eval("function() dotRefreshes=dotRefreshes+1 end")
rd.RefreshShards = rt.eval("function() shardRefreshes=shardRefreshes+1 end")
rd.RestoreDefaults()
assert G.dotRefreshes == 1 and G.shardRefreshes == 1

# Corrupt shared appearance must resolve to finite defaults, and explicit writes
# must refuse it instead of passing NaN colors or geometry to native setters.
rt, G, BIT, _ = load('''BattleInfoToolDB={appearance={global={scale=0/0,
colors={accent={0/0,1,1,1}}}}}''')
resolved = BIT.Style.Resolve("Range")
assert resolved.scale == BIT.Style.GetDefaults("Range").scale
assert list(resolved.colors.accent.values()) == list(BIT.Style.GetDefaults("Range").colors.accent.values())
assert BIT.Style.Set("Range", "fontSize", float("nan")) is None
# Together uses the same available resource maximum as live dots, independent
# of whether a target exists. A Retail Fire/Frost mage has no Arcane Charges.
rt, G, BIT, _ = load('''
playerClass="MAGE"
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE=1,1
function GetBuildInfo() return "12.0.1", "1", "",120001 end
availableCharges=0
function UnitPowerMax() return availableCharges end
target={hostile=true}; plate=NewPlate()
''')
G.Fire("ADDON_LOADED", "BattleInfoTool")
G.Fire("PLAYER_LOGIN")
BIT.OpenSettings("__together")
together = BIT._pages["__together"]
assert not BIT.modules.ResourceDing._dotsRow().shown and not together.rows.dots.shown
G.availableCharges = 4
G.target = None
together.refresh(together)
assert together.rows.dots.shown, "available resource preview must not require a target"

# Classic target-owned combo points keep their fallback maximum when the
# player power maximum is zero, including settings-only wake.
rt, G, BIT, _ = load('playerClass="ROGUE"; function UnitPowerMax() return 0 end')
G.Fire("ADDON_LOADED", "BattleInfoTool")
BIT.OpenSettings("__together")
assert BIT._pages["__together"].rows.dots.shown
print("ok final review: reusable OFF pages, subscribers, saved types, Hunter/Range lanes and probes, compact shield hooks, resource reset and available resources")
