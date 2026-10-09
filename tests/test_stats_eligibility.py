"""Class eligibility must gate every StatsInfo recommendation, including native badges."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fixture = (ROOT / "tests/test_bit.py").read_text(encoding="utf-8")
namespace = {"__file__": str(ROOT / "tests/test_bit.py")}
exec(compile(fixture.split('print("-- every module on")', 1)[0], "fixture", "exec"), namespace)
rt, G, BIT, _ = namespace["load"]()
G.Fire("ADDON_LOADED", "UsefulPlatesAndTooltips")
G.Fire("PLAYER_LOGIN")
si = BIT.modules.StatsInfo
G.EligibilityStats = si
rt.execute("""
playerClass = 'ROGUE'
ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 'Damage per second'
ITEM_MOD_SPIRIT_SHORT = 'Spirit'
items, nativeAllowed, activationUsable, canUseCalls = {}, {}, {}, {}
function addEligibilityItem(id, name, loc, class, subclass, stats, allowed)
  local link = 'item:'..id
  items[link] = {id=id, name=name, loc=loc, class=class, subclass=subclass}
  itemStats[link], itemLoc[link] = stats, loc
  nativeAllowed[id], activationUsable[link] = allowed, true
  return link
end
mainDagger = addEligibilityItem(91001, 'Blade of Cunning', 'INVTYPE_WEAPON', 'Weapon', 'Daggers',
  {ITEM_MOD_DAMAGE_PER_SECOND_SHORT=6.7, ITEM_MOD_AGILITY_SHORT=2}, true)
offDagger = addEligibilityItem(91002, 'Small Hand Blade', 'INVTYPE_WEAPON', 'Weapon', 'Daggers',
  {ITEM_MOD_DAMAGE_PER_SECOND_SHORT=6, ITEM_MOD_AGILITY_SHORT=1}, true)
staff = addEligibilityItem(91003, 'Foamspittle Staff', 'INVTYPE_2HWEAPON', 'Weapon', 'Staves',
  {ITEM_MOD_DAMAGE_PER_SECOND_SHORT=11.4, ITEM_MOD_SPIRIT_SHORT=5}, false)
dagger = addEligibilityItem(91004, 'Usable Dagger', 'INVTYPE_WEAPON', 'Weapon', 'Daggers',
  {ITEM_MOD_DAMAGE_PER_SECOND_SHORT=10, ITEM_MOD_AGILITY_SHORT=3}, true)
twoSword = addEligibilityItem(91005, 'Two-handed Sword', 'INVTYPE_2HWEAPON', 'Weapon', 'Two-Handed Swords',
  {ITEM_MOD_DAMAGE_PER_SECOND_SHORT=20, ITEM_MOD_AGILITY_SHORT=20}, false)
twoMace = addEligibilityItem(91006, 'Two-handed Mace', 'INVTYPE_2HWEAPON', 'Weapon', 'Two-Handed Maces',
  {ITEM_MOD_DAMAGE_PER_SECOND_SHORT=20, ITEM_MOD_AGILITY_SHORT=20}, false)
shield = addEligibilityItem(91007, 'Shield', 'INVTYPE_SHIELD', 'Armor', 'Shields',
  {ITEM_MOD_AGILITY_SHORT=20}, false)
wand = addEligibilityItem(91008, 'Wand', 'INVTYPE_RANGEDRIGHT', 'Weapon', 'Wands',
  {ITEM_MOD_AGILITY_SHORT=20}, false)
plate = addEligibilityItem(91009, 'Plate Chest', 'INVTYPE_CHEST', 'Armor', 'Plate',
  {ITEM_MOD_AGILITY_SHORT=20}, false)
oldBelt = addEligibilityItem(91010, 'Worn Belt', 'INVTYPE_WAIST', 'Armor', 'Leather',
  {ITEM_MOD_AGILITY_SHORT=1}, true)
belt = addEligibilityItem(91011, 'Ordinary Belt', 'INVTYPE_WAIST', 'Armor', 'Leather',
  {ITEM_MOD_AGILITY_SHORT=3}, true)
torch = addEligibilityItem(91012, "Grayson's Torch", 'INVTYPE_HOLDABLE', 'Armor', 'Miscellaneous',
  {ITEM_MOD_SPIRIT_SHORT=4}, true)
worn[16], worn[17], worn[6] = mainDagger, offDagger, oldBelt
activationUsable[belt] = false -- no activated use, yet perfectly legal equipment
function nativeItemInfoInstant(link)
  local item = items[link]
  if item then return item.id, item.class, item.subclass, item.loc end
end
C_Item.GetItemInfoInstant = nativeItemInfoInstant
function C_Item.GetItemInfo(link)
  local item = items[link]
  if item then return item.name, link, 2, 12, 1, item.class, item.subclass, 1, item.loc, nil, 100 end
end
function C_Item.IsEquippableItem(link) return items[link] ~= nil end
function C_Item.IsUsableItem(link) return activationUsable[link] end
function nativeCanUseItem(itemID)
  assert(type(itemID) == 'number', 'CanUseItem requires an item ID, not an item link')
  if issecretvalue and issecretvalue(itemID) then error('secret item ID passed to native API') end
  canUseCalls[#canUseCalls+1] = itemID
  if nativeAllowed[itemID] == 'error' then error('item capability not available') end
  return nativeAllowed[itemID]
end
C_PlayerInfo = {CanUseItem = nativeCanUseItem}
shiftDown = false
function IsShiftKeyDown() return shiftDown end
function GameTooltip:GetItem() return 'item', self.link end
function GameTooltip:AddLine(text) self.added[#self.added+1] = text end
function GameTooltip:NumLines() return #self.added end
""")


def lines(link, game_compares=False):
    return [row[1] for row in si.TooltipLines(link, game_compares).values()]


def assert_blocked(link):
    assert si.Compare(link) is None, f"illegal equipment still compared: {link}"
    assert si.SpecRatings(link) is None, f"illegal equipment still rated: {link}"
    assert si.BagVerdictState(link) == "dead", f"illegal equipment gets a badge: {link}"
    for detail, shift, inspect in (("compact", False, False), ("full", False, False),
                                   ("compact", True, False), ("full", False, True)):
        si.settings.detail = detail
        G.shiftDown = shift
        G.InspectFrame = G.FakeMock("inspect") if inspect else None
        for game_compares in (False, True):
            text = lines(link, game_compares)
            assert len(text) == 1 and "Cannot use this item" in text[0], (detail, shift, inspect, text)
            assert not any(word in text[0] for word in ("better", "worse", "Combat:", "Subtlety:", "Assassination:")), text
    G.shiftDown, G.InspectFrame = False, None
    si.settings.detail = "compact"


# The photographed dual-dagger/staff baseline formerly recommended an impossible upgrade.
si.settings.detail = "compact"
staff_lines = lines(G.staff)
assert len(staff_lines) == 1 and "Cannot use this item" in staff_lines[0], (
    f"rogue staff recommendation is still false: {staff_lines}"
)
for blocked in (G.staff, G.twoSword, G.twoMace, G.shield, G.wand, G.plate):
    assert si.CanEquipItem(blocked) is False
    assert_blocked(blocked)

# Equipment warnings do not spill onto ordinary quest items or other non-equipment.
rt.execute("questItem = addEligibilityItem(91013, 'Quest Item', '', 'Quest', '', {}, false)")
assert si.Compare(G.questItem) is None and lines(G.questItem) == []

# Positive control: legal weapons and equipment with no activated use retain their rating.
for allowed in (G.dagger, G.belt):
    assert si.CanEquipItem(allowed) is True
    assert si.Compare(allowed) is not None and si.SpecRatings(allowed) is not None
    state, verdict = si.BagVerdictState(allowed)
    assert state == "ok" and verdict.verdict == "up", (allowed, state, verdict)
    assert "Better than your gear" in lines(allowed)[0], lines(allowed)

# Held-in-off-hand items are not globally prohibited for rogues: use the client answer.
assert si.CanEquipItem(G.torch) is True
assert si.Compare(G.torch) is not None and si.SpecRatings(G.torch) is not None
assert not any("Cannot use this item" in text for text in lines(G.torch))
G.nativeAllowed[91012] = False
assert_blocked(G.torch)

# The live hover follows the same guard; Blizzard's shopping comparison is not rated again.
for detail, shift in (("compact", False), ("full", False), ("compact", True)):
    si.settings.detail = detail
    G.shiftDown = shift
    G.GameTooltip.link = G.staff
    G.GameTooltip.added = rt.table()
    G.Advance(0.01)
    G.GameTooltip.scripts.OnTooltipSetItem(G.GameTooltip)
    text = list(G.GameTooltip.added.values())
    assert len(text) == 1 and "Cannot use this item" in text[0], text
si.settings.detail, G.shiftDown = "compact", False

# No reliable native answer means unknown, never an optimistic comparison or a false refusal.
for native_answer in (None, "error", "unexpected non-boolean"):
    G.nativeAllowed[91003] = native_answer
    assert si.CanEquipItem(G.staff) is None
    assert si.Compare(G.staff) is None and si.SpecRatings(G.staff) is None
    assert si.BagVerdictState(G.staff) == "dead" and lines(G.staff) == []

# Lua 5.1 cannot mint engine secrets: marking primitive booleans/IDs checks the boundary
# before a secret answer can become a condition or an item ID can reach the native API.
for secret_boolean in (True, False):
    G.nativeAllowed[91003] = secret_boolean
    G.secretBoolean = secret_boolean
    rt.execute("function issecretvalue(value) return type(value)=='boolean' and value==secretBoolean end")
    assert si.CanEquipItem(G.staff) is None and lines(G.staff) == []
G.issecretvalue = None
G.nativeAllowed[91003] = True
G.canUseCalls = rt.table()
rt.execute("function issecretvalue(value) return type(value)=='number' and value==91003 end")
assert si.CanEquipItem(G.staff) is None and lines(G.staff) == []
assert len(G.canUseCalls) == 0, "secret item ID reached CanUseItem"
G.issecretvalue = None

# A denial before the item cache is ready cannot establish a class restriction.
G.nativeAllowed[91003] = False
G.canUseCalls = rt.table()
rt.execute("function C_Item.IsItemDataCachedByID(id) return id ~= 91003 end")
assert si.CanEquipItem(G.staff) is None and lines(G.staff) == []
assert si.Compare(G.staff) is None and si.SpecRatings(G.staff) is None
assert len(G.canUseCalls) == 0, "uncached item was classified with CanUseItem"
G.C_Item.IsItemDataCachedByID = None

# A readable item ID may come from the legacy global; absent APIs preserve old clients.
G.GetItemInfoInstant = G.nativeItemInfoInstant
G.C_Item.GetItemInfoInstant = None
G.nativeAllowed[91003] = False
assert_blocked(G.staff)
G.C_Item.GetItemInfoInstant = G.nativeItemInfoInstant
G.GetItemInfoInstant = None
saved_player_info = G.C_PlayerInfo
G.C_PlayerInfo.CanUseItem = None
assert si.CanEquipItem(G.staff) is True and si.Compare(G.staff) is not None
G.C_PlayerInfo.CanUseItem = G.nativeCanUseItem
G.C_PlayerInfo = None
assert si.CanEquipItem(G.staff) is True and si.Compare(G.staff) is not None
assert "Better than your gear" in lines(G.staff)[0], lines(G.staff)
G.C_PlayerInfo = saved_player_info

# The capability must be read anew on later builds (training/item arrival/class state).
for allowed in (True, False, True, False):
    G.nativeAllowed[91003] = allowed
    assert si.CanEquipItem(G.staff) is allowed
    if allowed:
        assert si.Compare(G.staff) is not None and "Better than your gear" in lines(G.staff)[0]
    else:
        assert_blocked(G.staff)

# Native bag, world loot and quest overlays must all suppress the same illegal upgrade.
rt.execute("""
nativeFrame, nativeButton = FakeMock('bag'), FakeMock('bagButton')
nativeBagLink = dagger
function nativeButton:GetSlotAndBagID() return 1, 0 end
function nativeFrame:EnumerateValidItems() return ipairs({nativeButton}) end
function ContainerFrameUtil_EnumerateContainerFrames() return ipairs({nativeFrame}) end
C_Container = {GetContainerItemInfo=function() return {hyperlink=nativeBagLink, stackCount=1} end}
EligibilityStats.RefreshBags()
LootButton1 = FakeMock('loot')
LootButton1.slot = 1
worldLink = dagger
function GetLootSlotLink() return worldLink end
""")
bag_marker = si._bagMarkerFor(G.nativeButton)
assert bag_marker.shown
G.Fire("LOOT_OPENED")
world_marker = next(child for child in G.LootButton1.children.values() if child.kind == "Frame")
assert world_marker.shown
G.nativeBagLink, G.worldLink = G.staff, G.staff
si.RefreshBags()
G.Fire("LOOT_OPENED")
assert not bag_marker.shown and not world_marker.shown, "illegal staff still has a native arrow"
rt.execute("""
QuestInfoFrame = FakeMock('quest')
QuestInfoFrame.rewardsFrame = FakeMock('rewards', QuestInfoFrame)
rewardButtons = {FakeMock('reward1'), FakeMock('reward2')}
function QuestInfo_GetRewardButton(_, index) return rewardButtons[index] end
function GetNumQuestChoices() return 2 end
function GetNumQuestRewards() return 0 end
function GetQuestItemInfo(_, index) return index==1 and staff or dagger, nil, 1, 2, true end
EligibilityStats.UpdateQuestRewards()
""")
staff_reward = si._questOverlays[1]
assert staff_reward is None or staff_reward.mode is None, "quest recommends the forbidden staff"
assert si._questOverlays[2].mode == "upgrade", "quest lost the legal dagger upgrade"

print("ok Stats eligibility: rogue staff, weapon/armor restrictions, allowed dagger/belt, every tooltip density, native hover, unknown/secret answers, legacy fallback, fresh capability and bag/loot/quest markers")
