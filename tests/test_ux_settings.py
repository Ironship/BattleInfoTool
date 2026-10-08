"""Drive the shipped settings and world-marker wiring, including wrapped preview text."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fixture = (ROOT / "tests/test_bit.py").read_text(encoding="utf-8")
namespace = {"__file__": str(ROOT / "tests/test_bit.py")}
exec(compile(fixture.split('print("-- every module on")', 1)[0], "fixture", "exec"), namespace)
rt, G, BIT, _ = namespace["load"]()
G.Fire("ADDON_LOADED", "BattleInfoTool")
G.Fire("PLAYER_LOGIN")

BIT.OpenSettings("HunterRangeFinder")
editor = BIT._pages["HunterRangeFinder"].content.hunterEditor
closed = editor.parent.GetHeight(editor.parent)
editor.SetAdvanced(editor, True)
assert editor.parent.GetHeight(editor.parent) >= editor.GetHeight(editor)
editor.SetAdvanced(editor, False)
assert editor.parent.GetHeight(editor.parent) == closed
BIT.OpenSettings("ShieldsInfo")
effects = next(tab for tab in BIT.modules["ShieldsInfo"]._tabs.values() if tab.editor is not None)
effects.editor.SetAdvanced(effects.editor, True)
assert effects.inner.GetHeight(effects.inner) >= 34 + effects.editor.GetHeight(effects.editor)

BIT.OpenSettings("__together")
page = BIT._pages["__together"]
rd = BIT.modules["ResourceDing"]
rd.db.dots = False
rd.db.shardDiamonds = False
page.refresh(page)
assert not page.rows.dots.shown and not page.rows.shards.shown and not page.rows.hunter.shown
assert BIT.Plate.ClashText() == "Nameplate lanes are clear."
G.playerClass = "ROGUE"
rd.db.dots = True
rd.db.dotSize = 24
page.refresh(page)
assert page.rows.dots.shown and not page.rows.shards.shown
assert page.rows.dots.height == 24
assert all(mark.kind == "CreateTexture" for mark in page.rows.dots.marks.values())
G.playerClass = "HUNTER"
page.refresh(page)
assert page.rows.hunter.shown and not page.rows.dots.shown
G.playerClass = "WARLOCK"

# Together: the caption names the shield's thin top edge (or the bar it fills) whenever the shield shows.
BIT.DB().modules.ShieldsInfo.nameplates = True
page.refresh(page)
assert "thin top edge" in page.caption.text or "fills the bar" in page.caption.text, page.caption.text
BIT.DB().modules.ShieldsInfo.nameplates = False
page.refresh(page)
assert "Shields off" in page.caption.text, page.caption.text
assert "thin top edge" not in page.caption.text and "fills the bar" not in page.caption.text, page.caption.text
BIT.DB().modules.ShieldsInfo.nameplates = True
page.refresh(page)

# Shields: each frame button is as wide as its name, and the four with their gaps fit the card.
frame_buttons = BIT.modules["ShieldsInfo"]._frameButtons
widths = {key: frame_buttons[key].width for key in ("player", "target", "party", "nameplate")}
assert widths["nameplate"] >= 9 * 6 + 18, widths  # "Nameplate": 9 letters at the test font's 6 px, plus padding
assert sum(widths.values()) + 3 * 3 <= 290 - 2 * 12, widths  # PREVIEW_WIDTH - 2 * SIDE

# Juicy: the shield aura art is laid out for a horizontal status bar (256 wide, 64 tall), uncompressed 32-bit TGA.
for name in ("shield_aura.tga", "shield_aura_mirrored.tga"):
    tga = (ROOT / "Modules" / "ShieldsInfo" / "Textures" / name).read_bytes()
    assert (tga[2], tga[16]) == (2, 32), (name, list(tga[:18]))
    width, height = tga[12] + 256 * tga[13], tga[14] + 256 * tga[15]
    assert (width, height) == (256, 64), (name, width, height)


# Mirrored is the same art flipped left-right on the bar, pixel by pixel (a double flip once made it equal to Juicy).
def tga_rows(name):
    raw = (ROOT / "Modules" / "ShieldsInfo" / "Textures" / name).read_bytes()
    width, height = raw[12] + 256 * raw[13], raw[14] + 256 * raw[15]
    return width, [raw[18 + r * width * 4: 18 + (r + 1) * width * 4] for r in range(height)]


width, juicy_rows = tga_rows("shield_aura.tga")
_, mirrored_rows = tga_rows("shield_aura_mirrored.tga")
flipped = [b"".join(row[x * 4:(x + 1) * 4] for x in reversed(range(width))) for row in juicy_rows]
assert mirrored_rows == flipped, "shield_aura_mirrored.tga is not the left-right mirror of shield_aura.tga"

# Spells: every caption of the preview is narrower than its column, so neighbouring names cannot run together.
BIT.OpenSettings("SpellDamageInfo")
spell_window = BIT.modules["SpellDamageInfo"]._optionsWindow()
column = (250 + 36 * 1.5) / 5  # (PREVIEW_WIDTH + span) / (PER_ROW + 1)
for i in range(1, 11):
    assert spell_window.mocks[i].caption.width < column, (i, spell_window.mocks[i].caption.width)
# Drain Life has its own icon (spell_shadow_lifedrain02); Health Funnel keeps spell_shadow_lifedrain.
assert spell_window.mocks[7].sample.icon == "Interface\\Icons\\Spell_Shadow_LifeDrain02", spell_window.mocks[7].sample.icon
assert spell_window.mocks[8].sample.icon == "Interface\\Icons\\Spell_Shadow_LifeDrain", spell_window.mocks[8].sample.icon

BIT.OpenSettings("StatsInfo")
content = BIT._pages["StatsInfo"].content
scene = next(child for child in content.children.values() if child.tipLines is not None)
si = BIT.modules["StatsInfo"]
si.settings.detail = "compact"
content.scripts.OnShow(content)
compact = [line.text for line in scene.tipLines.values() if line.shown]
assert any("Affliction" in text for text in compact)
assert not any("Against" in text for text in compact)
si.settings.detail = "full"
# Model real wrapped text instead of accepting every font API as a no-op.
rt.execute("""
function ReviewMeasure(self) return 40 end
""")
for line in scene.tipLines.values():
    line.GetStringHeight = G.ReviewMeasure
BIT.Style.Set("StatsInfo", "fontSize", 24)
BIT.Style.Set("StatsInfo", "scale", 2)
content.scripts.OnShow(content)
full = [line.text for line in scene.tipLines.values() if line.shown]
assert len(full) > len(compact)
assert any("Destruction" in text for text in full)
assert any("Against" in text for text in full)
assert scene.title.text == "Preview: sample item"
assert scene.height > 280 and content.height >= scene.height + 220
G.ReviewScroll = BIT._pages["StatsInfo"].scroll
rt.execute("""
function ReviewScroll:GetHeight() return 400 end
function ReviewScroll:GetVerticalScroll() return self.offset or 0 end
function ReviewScroll:SetVerticalScroll(value) self.offset = value end
ReviewScroll.offset = 1000
""")
si.settings.detail = "compact"
rt.execute("function IsShiftKeyDown() return true end")
G.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
assert len([line for line in scene.tipLines.values() if line.shown]) == len(full)
rt.execute("function IsShiftKeyDown() return false end")
G.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
assert len([line for line in scene.tipLines.values() if line.shown]) == len(compact)
# Native frames fire this automatically when compact shrinks the content.
content.scripts.OnSizeChanged(content)
assert G.ReviewScroll.offset <= max(0, content.height - 400)

# A bonus bar is a main combat bar, while pet bars obey the skip in both directions.
rt.execute("""
BonusActionButton1 = CreateFrame('Button', 'BonusActionButton1')
PetActionButton1 = CreateFrame('Button', 'PetActionButton1')
function PetActionButton1:GetID() return 1 end
""")
sdi = BIT.modules["SpellDamageInfo"]
def has_button(buttons, name):
    return any(button.name == name for button in buttons.values())
sdi.SetSetting("skipUtilityBars", False)
assert has_button(sdi._buttons, "BonusActionButton1")
assert has_button(sdi._petButtons, "PetActionButton1")
sdi.SetSetting("skipUtilityBars", True)
assert has_button(sdi._buttons, "BonusActionButton1")
assert not has_button(sdi._petButtons, "PetActionButton1")
G.Fire("PET_BAR_UPDATE")
assert not has_button(sdi._petButtons, "PetActionButton1")
sdi.SetSetting("skipUtilityBars", False)
assert has_button(sdi._petButtons, "PetActionButton1")

G.ReviewBIT = BIT
rt.execute("""
MerchantItem1ItemButton = FakeMock('merchant')
MerchantItem1ItemButton.link = 'item:123'
reviewVerdict = nil
reviewPaints = {}
local si = ReviewBIT.modules.StatsInfo
si.BagVerdict = function() return reviewVerdict and {verdict = reviewVerdict} end
si.PaintVerdictMarker = function(marker, verdict)
  table.insert(reviewPaints, verdict and verdict.verdict or 'none')
end
si.EnableWorldMarkers()
""")
assert G.reviewPaints[len(G.reviewPaints)] == "none"
G.reviewVerdict = "up"
G.Fire("GET_ITEM_INFO_RECEIVED", 123, True)
assert G.reviewPaints[len(G.reviewPaints)] == "up"
G.reviewVerdict = "down"
G.Fire("PLAYER_EQUIPMENT_CHANGED", 5)
assert G.reviewPaints[len(G.reviewPaints)] == "down"
G.combat = True
before = len(G.reviewPaints)
G.Fire("ITEM_DATA_LOAD_RESULT", 123, True)
assert len(G.reviewPaints) == before
G.combat = False
G.Fire("PLAYER_REGEN_ENABLED")
assert len(G.reviewPaints) > before
print("ok UX: Advanced scroll, texture rows, class/settings lanes, complete compact/full preview, world-marker invalidation, "
      "Spells caption columns and Drain Life icon, Shields frame buttons, Juicy aura art, Together shield caption")
