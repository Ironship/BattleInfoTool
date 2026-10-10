"""Build one installable ZIP and check every member against the source.

    python tools/build_zip.py           # existing WoW Forever package
    python tools/build_zip.py --retail  # four Retail modules, Mainline TOC

Each package has one UsefulPlatesAndTooltips folder and its own TOC.
"""
import argparse
import re
import sys
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--retail", action="store_true", help="build the Retail DoTInfo, ResourceDing, ShieldsInfo and SpellDamageInfo package")
args = parser.parse_args()
toc_name = "UsefulPlatesAndTooltips_Mainline.toc" if args.retail else "UsefulPlatesAndTooltips.toc"
toc = (root / toc_name).read_text(encoding="utf-8")
version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
files = [toc_name] + [l.strip().replace("\\", "/") for l in toc.splitlines()
                                  if l.strip() and not l.startswith("#")]
asset_roots = [root / "Modules" / module for module in ("DoTInfo", "ResourceDing", "ShieldsInfo", "SpellDamageInfo")] if args.retail else [root / "Modules"]
files += sorted(p.relative_to(root).as_posix() for directory in asset_roots for p in directory.rglob("*.tga"))
files += sorted(p.relative_to(root).as_posix() for directory in asset_roots for p in directory.rglob("LICENSE*.txt"))
files.append("LICENSE")
if args.retail:
    files.append("RETAIL.md")

dist = root / "dist"
dist.mkdir(exist_ok=True)
out = dist / f"UsefulPlatesAndTooltips-{version}.zip"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name in files:
        z.write(root / name, f"UsefulPlatesAndTooltips/{name}")

with zipfile.ZipFile(out) as z:
    bad = z.testzip()
    if bad:
        sys.exit(f"corrupt member: {bad}")
    names = sorted(z.namelist())
    if names != sorted(f"UsefulPlatesAndTooltips/{n}" for n in files):
        sys.exit(f"unexpected members: {names}")
    for name in files:
        if z.read(f"UsefulPlatesAndTooltips/{name}") != (root / name).read_bytes():
            sys.exit(f"content differs: {name}")
print(f"{out.name}: {out.stat().st_size} bytes, {len(files)} files, verified")
