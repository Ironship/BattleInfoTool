"""Builds dist/BattleInfoTool-<version>.zip: one top folder, the .toc, the files it lists, the
all module textures and their bundled third-party licences.

    python tools/build_zip.py

Then opens the zip again and checks every file against the source.
"""
import re
import sys
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
toc = (root / "BattleInfoTool.toc").read_text(encoding="utf-8")
version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
files = ["BattleInfoTool.toc"] + [l.strip().replace("\\", "/") for l in toc.splitlines()
                                  if l.strip() and not l.startswith("#")]
files += sorted(p.relative_to(root).as_posix() for p in (root / "Modules").rglob("*.tga"))
files += sorted(p.relative_to(root).as_posix() for p in (root / "Modules").rglob("LICENSE*.txt"))
files.append("LICENSE")

dist = root / "dist"
dist.mkdir(exist_ok=True)
out = dist / f"BattleInfoTool-{version}.zip"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name in files:
        z.write(root / name, f"BattleInfoTool/{name}")

with zipfile.ZipFile(out) as z:
    bad = z.testzip()
    if bad:
        sys.exit(f"corrupt member: {bad}")
    names = sorted(z.namelist())
    if names != sorted(f"BattleInfoTool/{n}" for n in files):
        sys.exit(f"unexpected members: {names}")
    for name in files:
        if z.read(f"BattleInfoTool/{name}") != (root / name).read_bytes():
            sys.exit(f"content differs: {name}")
print(f"{out.name}: {out.stat().st_size} bytes, {len(files)} files, verified")
