"""Stats option parity, honest compact summaries, safe keys and quest refreshes."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fixture = (ROOT / "tests/test_bit.py").read_text(encoding="utf-8")
namespace = {"__file__": str(ROOT / "tests/test_bit.py")}
exec(compile(fixture.split('print("-- every module on")', 1)[0], "fixture", "exec"), namespace)
rt, G, BIT, _ = namespace["load"]()
G.Fire("ADDON_LOADED", "UsefulPlatesAndTooltips")
G.Fire("PLAYER_LOGIN")
si = BIT.modules["StatsInfo"]
G.ReviewStats = si
G.ITEM_MOD_INTELLECT_SHORT = "Intellect"
rt.execute("""
itemStats['candidate'] = {ITEM_MOD_INTELLECT_SHORT = 12}
itemStats['worn'] = {ITEM_MOD_INTELLECT_SHORT = 10}
itemLoc['candidate'], itemLoc['worn'] = 'INVTYPE_CHEST', 'INVTYPE_CHEST'
worn[5] = 'worn'
""")


def lines(link):
    return [row[1] for row in si.TooltipLines(link).values()]


# Specs and raw comparison controls are separate settings, in either tooltip density.
si.settings.compare = False
si.settings.specs = True
si.settings.detail = "full"
full = lines("candidate")
assert any("Affliction" in text for text in full), full
assert not any("Against" in text or "Intellect" in text for text in full), full
si.settings.detail = "compact"
compact = lines("candidate")
assert len(compact) == 1 and "Affliction" in compact[0], compact
assert "300%" not in compact[0], compact
si.settings.specs = False
assert lines("candidate") == []

# A combat-hidden worn link is an unknown baseline, not an empty equipment slot.
si.settings.compare = True
si.settings.specs = True
rt.execute("""
worn[5] = 'hidden-worn'
function issecretvalue(value) return value == 'hidden-worn' end
""")
assert si.Compare("candidate") is None and lines("candidate") == []
assert si.BagVerdictState("candidate") == "dead"
G.itemLoc["candidate"] = "INVTYPE_SHIELD"
G.worn[16] = "hidden-worn"
assert si.Compare("candidate") is None, "unknown main hand cannot prove the shield replacement path"
G.worn[16] = None
G.worn[5] = "worn"
G.issecretvalue = None

# A bare second finger offers an upgrade by filling it, not an invented +300% baseline.
si.settings.compare = True
si.settings.specs = True
G.itemLoc["candidate"] = "INVTYPE_FINGER"
G.worn[11] = "worn"
G.worn[12] = None
empty = lines("candidate")
assert len(empty) == 1 and "Fills an empty slot" in empty[0], empty
assert "300%" not in empty[0] and "Affliction" in empty[0], empty

# A tank tradeoff, or a losing tank with a neutral spec, must not become a false arrow.
rt.execute("""
reviewSavedSpecs = ReviewStats.SPECS.WARLOCK
local tank = {name='Test tank', icon='Interface\\\\Icons\\\\Ability_Defend', role='tank',
  survival={reference='Stamina', weights={ITEM_MOD_STAMINA_SHORT=1}},
  threat={reference='Intellect', weights={ITEM_MOD_INTELLECT_SHORT=1}}}
local neutral = {name='Neutral spec', icon='Interface\\\\Icons\\\\Ability_Defend', role='damage',
  damage={reference='Strength', weights={ITEM_MOD_STRENGTH_SHORT=1}}}
ReviewStats.SPECS.WARLOCK = {tank, neutral}
itemStats['tradeoff'] = {ITEM_MOD_STAMINA_SHORT=12, ITEM_MOD_INTELLECT_SHORT=8}
itemStats['tank-worn'] = {ITEM_MOD_STAMINA_SHORT=10, ITEM_MOD_INTELLECT_SHORT=10}
itemLoc['tradeoff'], itemLoc['tank-worn'] = 'INVTYPE_CHEST', 'INVTYPE_CHEST'
worn[5] = 'tank-worn'
""")
tradeoff = lines("tradeoff")
assert len(tradeoff) == 1 and "No clear upgrade" in tradeoff[0], tradeoff
assert "MicroStream" not in tradeoff[0], tradeoff
state, verdict = si.BagVerdictState("tradeoff")
assert state == "ok" and verdict.verdict == "none"
si.settings.detail = "full"
G.InspectFrame = G.FakeMock("inspect")
full_tradeoff = lines("tradeoff")
assert any("No clear upgrade for this slot" in text for text in full_tradeoff), full_tradeoff
assert not any("Better than your gear" in text or "Worse than your gear" in text for text in full_tradeoff)
G.InspectFrame = None
si.settings.detail = "compact"
G.itemStats["tradeoff"].ITEM_MOD_STAMINA_SHORT = 8
assert "No clear upgrade" in lines("tradeoff")[0]
rt.execute("ReviewStats.SPECS.WARLOCK[2] = nil")
down = lines("tradeoff")
assert "Worse than your gear" in down[0] and "Test tank" in down[0], down
rt.execute("ReviewStats.SPECS.WARLOCK = reviewSavedSpecs; worn[5] = 'worn'")

# The preview honors the same independent toggles and the same compact empty-slot wording.
BIT.OpenSettings("StatsInfo")
content = BIT._pages["StatsInfo"].content
scene = next(child for child in content.children.values() if child.tipLines is not None)
content.scripts.OnShow(content)
assert any("Fills an empty slot" in row.text for row in scene.tipLines.values() if row.shown)
si.settings.compare = False
si.settings.detail = "full"
content.scripts.OnShow(content)
preview = [row.text for row in scene.tipLines.values() if row.shown]
assert any("Affliction" in text for text in preview), preview
assert not any("Against" in text for text in preview), preview

# Lua 5.1 cannot create engine secret values. A marked string and trapping table model
# the relevant boundary: asking _G or SPECS for that key must raise unless rejected first.
rt.execute("""
SECRET_KEY, SECRET_CLASS = '__hiddenStat', '__hiddenClass'
function issecretvalue(value) return value == SECRET_KEY or value == SECRET_CLASS end
setmetatable(_G, {__index = function(_, key)
  if key == SECRET_KEY then error('cannot be indexed with secret keys') end
end})
setmetatable(ReviewStats.SPECS, {__index = function(_, key)
  if key == SECRET_CLASS then error('cannot be indexed with secret keys') end
end})
itemStats['secret-stat'] = {[SECRET_KEY] = 8, ITEM_MOD_INTELLECT_SHORT = 2}
itemLoc['secret-stat'] = 'INVTYPE_CHEST'
""")
G.playerClass = G.SECRET_CLASS
assert si.BagVerdictState("candidate") == "dead"
G.playerClass = "WARLOCK"
stats = si.ItemStats("secret-stat")
assert stats.ITEM_MOD_INTELLECT_SHORT == 2 and stats[G.SECRET_KEY] is None
assert si.BagVerdictState("secret-stat") == "dead"
G.issecretvalue = None

# The reward badge must value the whole stack and refresh when item data arrives.
rt.execute("""
QuestInfoFrame = FakeMock('quest')
QuestInfoFrame.rewardsFrame = FakeMock('rewards', QuestInfoFrame)
rewardButtons = {FakeMock('reward1'), FakeMock('reward2')}
function QuestInfo_GetRewardButton(_, index) return rewardButtons[index] end
function GetNumQuestChoices() return 2 end
function GetNumQuestRewards() return 0 end
function GetQuestItemInfo(kind, index)
  return 'item:'..index, nil, index == 2 and 5 or 1, 1, false
end
function C_Item.GetItemInfo(link)
  return 'reward', link, 1, 1, 1, nil, nil, 1, '', nil, link == 'item:1' and 10000 or 3000
end
ReviewStats.BagVerdictState = function() return 'ok', {verdict = 'none'} end
ReviewStats.UpdateQuestRewards()
""")
assert si._questOverlays[2].mode == "coin", "five 30s items must beat one 1g item"
rt.execute("""
SECRET_COUNT = {}
function issecretvalue(value) return value == SECRET_COUNT end
function GetQuestItemInfo(kind, index)
  return 'item:'..index, nil, index == 1 and SECRET_COUNT or 5, 1, false
end
function C_Item.GetItemInfo(link)
  return 'reward', link, 1, 1, 1, nil, nil, 1, '', nil, link == 'item:1' and 100000 or 3000
end
ReviewStats.UpdateQuestRewards()
""")
assert si._questOverlays[2].mode == "coin", "a hidden stack amount is not assumed to be one"
G.issecretvalue = None
rt.execute("""
function GetQuestItemInfo(kind, index) return 'item:'..index, nil, 1, 1, true end
ReviewStats.BagVerdictState = function(link)
  return 'ok', {verdict = link == 'item:1' and 'up' or 'none'}
end
""")
G.Fire("GET_ITEM_INFO_RECEIVED", 1, True)
assert si._questOverlays[1].mode == "upgrade" and si._questOverlays[2].mode is None
rt.execute("ReviewStats.BagVerdictState = function() return 'ok', {verdict = 'none'} end")
G.Fire("ITEM_DATA_LOAD_RESULT", 1, True)
assert si._questOverlays[1].mode == "coin", "item arrival must reevaluate the reward badge"

# A native bag's already-computed verdict is invalidated even when its link is unchanged.
rt.execute("""
nativeFrame, nativeButton = FakeMock('bag'), FakeMock('bagButton')
function nativeButton:GetSlotAndBagID() return 1, 0 end
function nativeFrame:EnumerateValidItems() return ipairs({nativeButton}) end
function ContainerFrameUtil_EnumerateContainerFrames() return ipairs({nativeFrame}) end
C_Container = {GetContainerItemInfo = function() return {hyperlink='item:1', stackCount=1} end}
reviewBagVerdict = 'up'
ReviewStats.BagVerdictState = function() return 'ok', {verdict = reviewBagVerdict} end
ReviewStats.RefreshBags()
""")
marker = si._bagMarkerFor(G.nativeButton)
assert marker.shown and marker.arrow.texture.endswith("Green")
G.reviewBagVerdict = "down"
G.Fire("GET_ITEM_INFO_RECEIVED", 1, True)
assert marker.shown and marker.arrow.texture.endswith("Red"), "arrival must invalidate the native slot memo"

# Native buyback retains each button's old vendor link and displays twelve slots.
rtM, GM, BITM, _ = namespace["load"]("function MerchantFrame_Update() end")
GM.Fire("ADDON_LOADED", "UsefulPlatesAndTooltips")
GM.Fire("PLAYER_LOGIN")
GM.ReviewMerchantStats = BITM.modules.StatsInfo
rtM.execute("""
MERCHANT_ITEMS_PER_PAGE, BUYBACK_ITEMS_PER_PAGE = 10, 12
MerchantFrame = {selectedTab=1, page=1}
for i=1,12 do
  local button=FakeMock('merchant')
  button.link='vendor:'..i
  _G['MerchantItem'..i..'ItemButton']=button
end
function GetBuybackItemLink(i) return 'sold:'..i end
merchantLinks={}
ReviewMerchantStats.BagVerdict=function(link)
  table.insert(merchantLinks,link)
end
MerchantFrame_Update()
""")
assert list(GM.merchantLinks.values()) == [f"vendor:{i}" for i in range(1, 11)]
rtM.execute("MerchantFrame.selectedTab=2; merchantLinks={}; MerchantFrame_Update()")
assert list(GM.merchantLinks.values()) == [f"sold:{i}" for i in range(1, 13)]
GM.BUYBACK_ITEMS_PER_PAGE = None
rtM.execute("merchantLinks={}; MerchantFrame_Update()")
assert list(GM.merchantLinks.values())[-2:] == ["sold:11", "sold:12"]

print("ok Stats review: independent options, compact/full tradeoffs, hidden baselines/spec/keys, preview parity, quest stacks, data arrivals, bag memo and buyback slots")
