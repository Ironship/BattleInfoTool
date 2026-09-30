"""Runs each ported module's own test suite against the ported files, and DoTInfo's suite in place.

    python tools/test_modules.py [module ...]

ResourceDing and SpellDamageInfo: the addon's tests (and fixtures) are taken from its git HEAD into
a fresh temporary folder, the ported files from Modules/<name>/ are put beside them under their
original names, the SavedVariables name the port changed is changed in the tests the same way,
and every test runs there. The ported files, loaded without the BattleInfoTool core, behave as the
standalone addon does, so its tests must pass as they pass in its own repo.

DoTInfo: only its suite lives here, in tools/dot_fixtures/ under the module's own names, and runs
against Modules/DoTInfo/* directly (the module has no standalone repo any more). The fixtures load
the canonical files exactly as BattleInfoTool.toc lists them.
"""
import io
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECTS = ROOT.parent

SUITES = {
    "ResourceDing": {
        "repo": PROJECTS / "ResourceDing",
        "take": ["tests"],
        "rename": [("ResourceDingDB", "BattleInfoTool_ResourceDingDB")],
        "run": [["lua", "tests/classic.test.lua"], ["lua", "tests/opener.test.lua"], ["lua", "tests/dots.test.lua"], ["lua", "tests/caster.test.lua"]],
    },
    "SpellDamageInfo": {
        "repo": PROJECTS / "SpellDamageInfo",
        # the .toc: its smoke test loads the files the .toc lists, in that order
        "take": ["tests", "SpellDamageInfo.toc"],
        "rename": [("SpellDamageInfoDB", "BattleInfoTool_SpellDamageInfoDB")],
        # every test under Lua 5.1 (the game's), in the process locale and in "C"
        "run": [["python", "tests/check_lua51.py"]],
    },
    # DoTInfo: the migrated fixture suite in this repo; the runner needs no external addon repo.
    "DoTInfo": {
        "in_repo": ROOT / "tools" / "dot_fixtures",
        "run": [["python", t] for t in (
            "test_parse.py", "test_spellbook.py", "test_tracking.py", "test_display.py",
            "test_load.py", "test_locale.py")],
    },
}


def extract(repo, paths, into):
    r = subprocess.run(["git", "-C", str(repo), "archive", "HEAD", *paths], capture_output=True)
    if r.returncode:
        sys.exit(f"{repo.name}: git archive failed: {r.stderr.decode(errors='replace')}")
    with tarfile.open(fileobj=io.BytesIO(r.stdout)) as tar:
        tar.extractall(into)


def run_suite(name):
    spec = SUITES[name]
    if "in_repo" in spec:
        # DoTInfo: the fixtures live in this repo and read Modules/DoTInfo/* in place.
        work = None
        cwd = spec["in_repo"]
    else:
        work = pathlib.Path(tempfile.mkdtemp(prefix=f"bit_{name}_"))
        cwd = work
        extract(spec["repo"], spec["take"], work)
        into = work / spec.get("into", "")
        for f in (ROOT / "Modules" / name).iterdir():
            if f.is_file() and f.suffix == ".lua":
                shutil.copy(f, into / f.name)
        for path in (work / spec.get("tests", "tests")).rglob("*"):
            if path.is_file() and path.suffix in (".lua", ".py", ".mjs"):
                text = path.read_text(encoding="utf-8")
                for old, new in spec["rename"]:
                    text = text.replace(old, new)
                if name == "SpellDamageInfo" and path.name == "test_smoke.lua":
                    # BIT adds a sixth preview sample (Life Tap), tested by tests/test_bit.py.
                    old = 'T.eq(#mocks, 5, "five mock buttons")'
                    if text.count(old) != 1:
                        raise RuntimeError("SpellDamageInfo preview fixture changed; inspect before adapting")
                    text = text.replace(old, 'T.eq(#mocks, 6, "six mock buttons including Life Tap")')
                path.write_text(text, encoding="utf-8")
    try:
        failed = 0
        for cmd in spec["run"]:
            if cmd[0] == "python":
                cmd = [sys.executable] + cmd[1:]  # the interpreter this runs under, which has lupa
            r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")
            tail = (r.stdout.strip().splitlines() or [""])[-1]
            status = "ok  " if r.returncode == 0 else "FAIL"
            print(f"{status} {name}: {' '.join(cmd[1:])}  {tail}")
            if r.returncode:
                failed += 1
                print(r.stdout[-3000:], r.stderr[-2000:])
        return failed
    finally:
        if work:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    total = sum(run_suite(n) for n in (sys.argv[1:] or list(SUITES)))
    sys.exit(1 if total else 0)
