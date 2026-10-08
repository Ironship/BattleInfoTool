"""Exercise new modules through the shipped TOC, not a hand-written loader."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
source = (ROOT / "tests/test_bit.py").read_text(encoding="utf-8")
namespace = {"__file__": str(ROOT / "tests/test_bit.py")}
exec(compile(source.split('print("-- every module on")', 1)[0], "test_bit_fixture", "exec"), namespace)
load = namespace["load"]

rt, G, BIT, files = load()
for name in ("ShieldsInfo", "HunterRangeFinder"):
    assert BIT.modules[name] is not None, f"The shipped TOC does not load {name}"
    assert BIT.tabs[name] is not None, f"The shipped addon has no {name} settings tab"
G.Fire("ADDON_LOADED", "UsefulPlatesAndTooltips")
for name in ("ShieldsInfo", "HunterRangeFinder"):
    assert BIT.state[name] == "on", f"{name} did not start through the normal addon lifecycle"
    BIT.OpenSettings(name)
    assert BIT._pages[name] is not None and BIT._pages[name].shown
    assert BIT._pages[name].offNote is None
assert not any("could not be built" in str(v) for v in G.chat.values())
print("ok integrated modules: shipped TOC, startup, settings tabs")

# The actual archive must carry every texture used by the shipped modules and the
# external texture licence, not only the Lua files enumerated in the TOC.
import re
import subprocess
import sys
import zipfile

subprocess.run([sys.executable, str(ROOT / "tools/build_zip.py")], check=True, cwd=ROOT)
version = re.search(r"^## Version:\s*(\S+)", (ROOT / "UsefulPlatesAndTooltips.toc").read_text(encoding="utf-8"), re.M).group(1)
with zipfile.ZipFile(ROOT / "dist" / f"UsefulPlatesAndTooltips-{version}.zip") as archive:
    assert archive.testzip() is None
    names = archive.namelist()
    assert len(names) == len(set(names)), "Duplicate payload entries"
    for module in ("DoTInfo", "ShieldsInfo", "HunterRangeFinder"):
        textures = list((ROOT / "Modules" / module / "Textures").glob("*.tga"))
        assert textures, f"No testable assets found for {module}"
        for texture in textures:
            relative = texture.relative_to(ROOT).as_posix()
            member = "UsefulPlatesAndTooltips/" + relative
            assert member in names, f"The package omits runtime texture {relative}"
            assert archive.read(member) == texture.read_bytes()
    licence = "Modules/ShieldsInfo/LICENSE-ShieldAuraForever.txt"
    assert archive.read("UsefulPlatesAndTooltips/" + licence) == (ROOT / licence).read_bytes()
    for path in names:
        assert archive.read(path) == (ROOT / path.removeprefix("UsefulPlatesAndTooltips/")).read_bytes()
print("ok integrated package: all runtime textures, licence, exact source payload")
