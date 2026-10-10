"""Build both variants, verify their payloads, and load the actual Retail ZIP in Lua 5.1."""
import hashlib
from pathlib import Path
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parent.parent
PREFIX = "UsefulPlatesAndTooltips/"
RETAIL_MODULES = {"DoTInfo", "ResourceDing", "ShieldsInfo", "SpellDamageInfo"}

RETAIL_CLIENT = r'''
  function GetBuildInfo() return "12.1.0", "69933", "Oct 8 2026", 120100 end
  WOW_PROJECT_MAINLINE, WOW_PROJECT_ID = 1, 1
  function GetLocale() return "enUS" end
  function GetSpecialization() return 1 end
  function GetSpecializationInfo() return 265, "Affliction" end
  function methods.SetValue(self, value) self.value = value end
  function methods.SetMinMaxValues(self, low, high) self.minimum, self.maximum = low, high end
  function methods.SetAllPoints(self, other) self.allPoints = other end
  function methods.AddLine(self, text)
    self.lines = self.lines or {}
    local line = mock("tooltipLine", self)
    line:SetText(text)
    self.lines[#self.lines + 1] = line
  end
  function methods.NumLines(self) return #(self.lines or {}) end
  function methods.GetLeftLine(self, index) return (self.lines or {})[index] end
  target = { hostile = true }
  units.target = { guid = "Creature-Retail-1", name = "Training Dummy", health = 1000, max = 1000, absorb = 200 }
  units.nameplate1 = units.target
  units.player = { health = 1000, max = 1000, absorb = 100 }
  function UnitName(unit) return units[unit] and units[unit].name end
  function UnitIsUnit(a, b) return units[a] ~= nil and rawequal(units[a], units[b]) end
  function UnitCanAttack(_, unit) return units[unit] == units.target end
  function UnitGetTotalAbsorbs(unit) return units[unit] and units[unit].absorb end
  function UnitPower(_, power) return power == 4 and comboPoints or 3 end
  function UnitPowerMax(_, power) return power == 0 and 1000 or 5 end
  PlayerFrame = mock("PlayerFrame")
  PlayerFrame.PlayerFrameContent = { PlayerFrameContentMain = {
    HealthBarsContainer = { HealthBar = mock("playerHealth") } } }
  plate = mock("NamePlate")
  plate.UnitFrame = { unit = "nameplate1", healthBar = mock("plateHealth", plate) }
  plates = { plate }
  C_NamePlate.GetNamePlates = function() return plates end
  ActionButton1 = CreateFrame("Button", "ActionButton1", UIParent)
  ActionButton1:SetSize(36, 36)
  ActionButton1.action = 1
  function GetActionInfo(slot) if slot == 1 then return "spell", 172 end end
  spellNames[172] = "Corruption"
  spellDesc[172] = "Deals 300 Shadow damage over 12 sec."
  C_Spell.GetSpellInfo = function() return { castTime = 0 } end
'''


def toc_files(text):
    return [line.strip().replace("\\", "/") for line in text.splitlines()
            if line.strip() and not line.startswith("#")]


def build_and_check(retail):
    command = [sys.executable, str(ROOT / "tools/build_zip.py")]
    if retail:
        command.append("--retail")
    subprocess.run(command, check=True, cwd=ROOT)
    toc_name = "UsefulPlatesAndTooltips_Mainline.toc" if retail else "UsefulPlatesAndTooltips.toc"
    text = (ROOT / toc_name).read_text(encoding="utf-8")
    version = re.search(r"^## Version:\s*(\S+)", text, re.M).group(1)
    expected = {toc_name, "LICENSE", *toc_files(text)}
    modules = [ROOT / "Modules" / name for name in RETAIL_MODULES] if retail else [ROOT / "Modules"]
    for directory in modules:
        for pattern in ("*.tga", "LICENSE*.txt"):
            expected.update(path.relative_to(ROOT).as_posix() for path in directory.rglob(pattern))
    if retail:
        expected.add("RETAIL.md")
    path = ROOT / "dist" / f"UsefulPlatesAndTooltips-{version}.zip"
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        names = archive.namelist()
        assert len(names) == len(set(names)), "Duplicate package members"
        assert set(names) == {PREFIX + name for name in expected}, "Unexpected package members"
        for name in expected:
            shipped = archive.read(PREFIX + name)
            source = (ROOT / name).read_bytes()
            assert hashlib.sha256(shipped).digest() == hashlib.sha256(source).digest(), name
            assert shipped == source, name
        if retail:
            assert "## Interface: 120100" in text
            assert "16001" not in text
            assert re.fullmatch(r"\d+\.\d+\.\d+-retail", version)
            assert PREFIX + "UsefulPlatesAndTooltips.toc" not in names
            assert {name.split("/")[1] for name in expected if name.startswith("Modules/")} == RETAIL_MODULES
            files = toc_files(text)
            assert files.index("Modules/DoTInfo/Retail.lua") < files.index("Modules/DoTInfo/RogueAuras.lua") < files.index("Modules/DoTInfo/Core.lua")
            default_files = toc_files((ROOT / "UsefulPlatesAndTooltips.toc").read_text(encoding="utf-8"))
            assert [name for name in files if name.startswith("Modules/SpellDamageInfo/")] == [
                name for name in default_files if name.startswith("Modules/SpellDamageInfo/")]
            assert "UsefulPlatesAndTooltips_SpellDamageInfoDB" in text
        else:
            assert PREFIX + "UsefulPlatesAndTooltips_Mainline.toc" not in names
            assert PREFIX + "Modules/DoTInfo/Retail.lua" not in names
            assert PREFIX + "Modules/DoTInfo/RogueAuras.lua" not in names
            assert PREFIX + "RETAIL.md" not in names
    print(f"ok {'Retail' if retail else 'Forever'} package: {len(expected)} source-identical files, "
          f"SHA256 {hashlib.sha256(path.read_bytes()).hexdigest()}")
    return path


def load_retail_archive(path, saved=None, player_class="WARLOCK"):
    # Reuse the shared fake client without changing its default Forever TOC loader.
    fixture = (ROOT / "tests/test_bit.py").read_text(encoding="utf-8").split('print("-- every module on")', 1)[0]
    namespace = {"__file__": str(ROOT / "tests/test_bit.py")}
    exec(compile(fixture, "test_bit_fixture", "exec"), namespace)
    rt = namespace["LuaRuntime"](unpack_returned_tuples=True)
    rt.execute(namespace["FAKE"] + RETAIL_CLIENT)
    if saved:
        rt.execute(saved)
    globals_ = rt.globals()
    globals_.playerClass = player_class
    addon = rt.eval("{}")
    loader = rt.eval("function(src, name, addon) local f = assert(loadstring(src, '@' .. name)); "
                     "return f('UsefulPlatesAndTooltips', addon) end")
    with zipfile.ZipFile(path) as archive:
        text = archive.read(PREFIX + "UsefulPlatesAndTooltips_Mainline.toc").decode("utf-8")
        for name in toc_files(text):
            loader(archive.read(PREFIX + name).decode("utf-8"), name, addon)
    assert set(addon.modules.keys()) == RETAIL_MODULES
    assert set(addon.tabs.keys()) == RETAIL_MODULES
    globals_.Fire("ADDON_LOADED", "UsefulPlatesAndTooltips")
    globals_.Fire("PLAYER_LOGIN")
    return rt, globals_, addon


def check_retail_lifecycle(path):
    rt, globals_, addon = load_retail_archive(path)
    for name in sorted(RETAIL_MODULES):
        assert addon.state[name] == "on", name
        addon.OpenSettings(name)
        assert addon._pages[name].shown, name
        assert addon._pages[name].offNote is None, name
    addon.OpenSettings("__together")
    assert not any("could not be built" in str(message) for message in globals_.chat.values())
    assert globals_.UsefulPlatesAndTooltips_SpellDamageInfoDB is not None
    assert globals_.UsefulPlatesAndTooltips_DoTInfoDB is not None
    assert globals_.UsefulPlatesAndTooltips_ResourceDingDB is not None

    resource = addon.modules.ResourceDing
    rows = addon.Plate.Rows()
    assert rows.shards.on and not rows.dots.on, "Retail warlock preview must show its live diamonds"
    resource.db.shardDiamonds = False
    resource.RefreshMarks()
    rows = addon.Plate.Rows()
    assert rows.dots.on and not rows.shards.on, "Disabling diamonds must restore the resource circles"
    resource.db.shardDiamonds = True
    resource.RefreshMarks()
    together = addon._pages["__together"]
    together.refresh(together)
    assert "Range off" not in together.caption.text and "Hunter off" not in together.caption.text

    sdi = addon.modules.SpellDamageInfo
    label = sdi._labels[globals_.ActionButton1]
    assert label is not None and label.shown and label.text == "300"
    sdi.SetSetting("position", "top")
    assert label.points[1][1] == "TOPLEFT", "The shipped SDI must apply its action-button placement"
    assert sdi.AddTooltipLines(globals_.GameTooltip, 172) > 0
    assert any("300" in str(line.text) for line in globals_.GameTooltip.lines.values())

    globals_.Fire("PLAYER_ENTERING_WORLD")
    globals_.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    globals_.Fire("UNIT_SPELLCAST_SENT", "player", "Training Dummy", "Cast-Retail-1", 172)
    globals_.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Retail-1", 172)
    globals_.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "target")
    assert addon.modules.DoTInfo.HasMarker("target")
    assert addon.modules.DoTInfo.HasMarker("nameplate1")
    shields = addon.modules.ShieldsInfo
    target_bar = globals_.TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
    for bar in (target_bar, globals_.plate.UnitFrame.healthBar):
        overlay = shields._overlay(bar)
        assert overlay is not None and overlay.bar.shown and overlay.edge
        assert overlay.bar.height == addon.Plate.SHIELD_EDGE
        assert globals_.Same(overlay.bar.parent, bar), "The shield edge must stay on its actual health bar"

    rt.execute('''
      hidden = setmetatable({}, {
        __index = function() error("indexed secret") end,
        __lt = function() error("compared secret") end,
        __le = function() error("compared secret") end,
        __add = function() error("added secret") end,
        __concat = function() error("formatted secret") end,
        __tostring = function() error("formatted secret") end,
      })
      function issecretvalue(value) return rawequal(value, hidden) end
      units.target.max, units.target.absorb = hidden, hidden
      spellDesc[998] = hidden
    ''')
    globals_.Fire("UNIT_ABSORB_AMOUNT_CHANGED", "target")
    for bar in (target_bar, globals_.plate.UnitFrame.healthBar):
        overlay = shields._overlay(bar)
        assert overlay.bar.shown
        assert globals_.Same(overlay.bar.value, globals_.hidden)
        assert globals_.Same(overlay.bar.maximum, globals_.hidden)
    assert sdi.Compute(998) is None and sdi.AddTooltipLines(globals_.GameTooltip, 998) == 0
    rt.execute('function GetActionInfo() return "spell", hidden end')
    globals_.Fire("ACTIONBAR_SLOT_CHANGED", 1)
    assert not label.shown, "A hidden action spell ID must not retain a damage label"
    rt.execute('playerClass = "DRUID"; function GetShapeshiftFormID() return hidden end')
    rows = addon.Plate.Rows()
    assert not rows.dots.on, "An unreadable druid form must not show inactive combo dots"
    together.refresh(together)
    print("ok Retail ZIP integration: four modules, settings, placement, Together parity and masked readings")

    disabled = ", ".join(f'{name} = {{ enabled = false }}' for name in sorted(RETAIL_MODULES))
    _, off_globals, off_addon = load_retail_archive(path, "UsefulPlatesAndTooltipsDB = { modules = { " + disabled + " } }")
    for name in RETAIL_MODULES:
        assert off_addon.state[name] == "off", name
        off_addon.OpenSettings(name)
        assert off_addon._pages[name].offNote is not None, name
    assert off_globals.UsefulPlatesAndTooltips_SpellDamageInfoDB is None
    assert off_globals.UsefulPlatesAndTooltips_DoTInfoDB is None
    assert off_globals.UsefulPlatesAndTooltips_ResourceDingDB is None
    assert len(off_addon.modules.SpellDamageInfo._buttons) == 0
    assert off_addon.modules.ShieldsInfo._driver() is None
    print("ok Retail ZIP module switches: all four remain silent when switched off")

    _, rogue_globals, rogue_addon = load_retail_archive(path, player_class="ROGUE")
    assert rogue_globals.C_XMLUtil is None, "The package fixture deliberately lacks the native aura template API"
    for event, args in (("PLAYER_ENTERING_WORLD", ()), ("NAME_PLATE_UNIT_ADDED", ("nameplate1",)),
                        ("PLAYER_TARGET_CHANGED", ()), ("UNIT_AURA", ("target",))):
        rogue_globals.Fire(event, *args)
    rogue_addon.modules.DoTInfo.Retail.StartRogueAuras()
    rogue_addon.modules.DoTInfo.Retail.UpdateRogueAuras()
    assert not any(frame.kind == "AuraContainer" for frame in rogue_globals.AllFrames.values())
    for name in RETAIL_MODULES:
        assert rogue_addon.state[name] == "on", name
        rogue_addon.OpenSettings(name)
        assert rogue_addon._pages[name].offNote is None, name
    assert not any("could not be built" in str(message) for message in rogue_globals.chat.values())
    print("ok Retail rogue startup: missing native aura API leaves all four modules and settings available")


if __name__ == "__main__":
    build_and_check(False)
    check_retail_lifecycle(build_and_check(True))
