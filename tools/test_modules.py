"""Runs each ported module's own test suite against the ported files, and DoTInfo's suite in place.

    python tools/test_modules.py [module ...]

ResourceDing and SpellDamageInfo: the addon's tests (and fixtures) are taken from its git HEAD into
a fresh temporary folder, the ported files from Modules/<name>/ are put beside them under their
original names, the SavedVariables name the port changed is changed in the tests the same way,
and every test runs there. The ported files, loaded without the UsefulPlatesAndTooltips core, behave as the
standalone addon does, so its tests must pass as they pass in its own repo.

DoTInfo: only its suite lives here, in tools/dot_fixtures/ under the module's own names, and runs
against Modules/DoTInfo/* directly (the module has no standalone repo any more). The fixtures load
the canonical files exactly as UsefulPlatesAndTooltips.toc lists them.
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
        "rename": [("ResourceDingDB", "UsefulPlatesAndTooltips_ResourceDingDB")],
        "run": [["lua", "tests/classic.test.lua"], ["lua", "tests/opener.test.lua"], ["lua", "tests/dots.test.lua"], ["lua", "tests/caster.test.lua"]],
    },
    "SpellDamageInfo": {
        "repo": PROJECTS / "SpellDamageInfo",
        # the .toc: its smoke test loads the files the .toc lists, in that order
        "take": ["tests", "SpellDamageInfo.toc"],
        "rename": [("SpellDamageInfoDB", "UsefulPlatesAndTooltips_SpellDamageInfoDB")],
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


def adapt_sdi_fixture(text, filename):
    """Keep upstream's independently calculated expectations aligned with BIT's SDI contracts."""
    replacements = []
    if filename == "test_smoke.lua":
        replacements = [
            ('T.eq(#mocks, 5, "five mock buttons")', 'T.eq(#mocks, 10, "ten preview samples")', 1),
            ('function issecretvalue(v) return rawequal(v, SECRET) end',
             'function issecretvalue(v) return rawequal(v, SECRET) end\nfunction GetComboPoints() return 5 end', 1),
            ('T.eq(shown(ActionButton7), "1530", "Health Funnel heal 153 x 10")',
             'T.eq(shown(ActionButton7), "-1530 HP", "Health Funnel costs 153 x 10 health")', 1),
            ('T.check(label(ActionButton7) and label(ActionButton7).color[2] == 1, "heals are green")',
             'T.check(label(ActionButton7) and label(ActionButton7).color[1] == ns.Format.REDUCTION_COLOR[1], "pet transfer costs are red")', 1),
            ('"Bei 5 Combopunkten, ohne Angriffskraft; 1-4: 224-332 / 394-502 / 564-672 / 734-842"',
             '"Bei den aktuellen 5 Combopunkten, ohne Angriffskraft; die übrigen: 1: 224-332 / 2: 394-502 / 3: 564-672 / 4: 734-842"', 1),
        ]
    elif filename == "test_parser.lua":
        replacements = [
            ('return { dot = O(n(a) * n(l) / n(i), l) }',
             'return { dot = O(n(a) * n(l) / n(i), l), hot = O(n(a) * n(l) / n(i), l), transfer = true }', 2),
            ('return { dot = O(n(a) * n(l), l) }',
             'return { dot = O(n(a) * n(l), l), hot = O(n(a) * n(l), l), transfer = true }', 2),
            ('return { hot = O(n(a) * n(d), d) }',
             'return { healthCost = n(a) * n(d), petHeal = true }', 2),
            ('{ dot = O(255, 5) }', '{ dot = O(255, 5), hot = O(255, 5), transfer = true }', 1),
            ('local got = ns.Parser.ParseSpecial(case[2], case[1])',
             'local got = ns.Parser.ParseItemHeal(case[2], case[1])', 1),
            ('"Use: Restores 700 to 900 mana.", { heal = D(700, 900) }',
             '"Use: Restores 700 to 900 mana.", { mana = D(700, 900) }', 1),
            ('ipairs({ "direct", "heal" })', 'ipairs({ "direct", "heal", "mana" })', 1),
            ('return got.school == want.school',
             'for _, key in ipairs({ "healthCost", "petHeal", "transfer" }) do\n'
             '    if got[key] ~= want[key] then return false end\n'
             '  end\n  return got.school == want.school', 1),
        ]
    for old, new, expected in replacements:
        if text.count(old) != expected:
            raise RuntimeError(f"SpellDamageInfo {filename} fixture changed; inspect before adapting: {old}")
        text = text.replace(old, new)
    if filename == "test_smoke.lua":
        # Legacy pet tests explicitly exercise skip=false, including after reloading their DB.
        text = text.replace('fire("ADDON_LOADED", "SpellDamageInfo")',
                            'fire("ADDON_LOADED", "SpellDamageInfo")\nns.SetSetting("skipUtilityBars", false)')
    return text


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
                if name == "SpellDamageInfo":
                    text = adapt_sdi_fixture(text, path.name)
                elif name == "ResourceDing" and path.name == "classic.test.lua":
                    # The native updater requires its maximum, and Classic reads the target.
                    replacements = [
                        ('ComboFrame = {\n', 'ComboFrame = {\n      maxComboPoints = 5,\n'),
                        ('UnitPower = function() return secret() end',
                         'UnitPower = function() return secret() end\ncomboNow = secret()'),
                    ]
                    for old, new in replacements:
                        if text.count(old) != 1:
                            raise RuntimeError("ResourceDing Classic fixture changed; inspect before adapting")
                        text = text.replace(old, new)
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
