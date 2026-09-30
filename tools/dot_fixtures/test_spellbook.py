"""Runs every damage tooltip in the committed Forever spellbook snapshot through DoTInfo's real parser and
compares the results with a reviewed snapshot (tools/dot_fixtures/data/spellbook_expected.json).

    pip install lupa
    python tools/dot_fixtures/test_spellbook.py            # check; exit code 1 on any difference
    python tools/dot_fixtures/test_spellbook.py --update   # accept current results (review the diff first!)
    python tools/dot_fixtures/test_spellbook.py --list     # print what the addon does with every damage spell

Finishers are parsed at 5 combo points. The input snapshot is
 tools/dot_fixtures/data/forever_spellbook.json; the original external scraper is not required to run this suite.
"""
import json
import os
import re
import sys

from test_parse import track  # the addon's own parser, run in Lua

HERE = os.path.dirname(os.path.abspath(__file__))
SPELLBOOK = os.path.join(HERE, "data", "forever_spellbook.json")
EXPECTED = os.path.join(HERE, "data", "spellbook_expected.json")

DAMAGE = re.compile(r"damage|health from the target", re.I)


def results():
    spells = json.load(open(SPELLBOOK, encoding="utf-8"))
    out = {}
    for spell in spells:
        tooltip = spell["tooltip"]
        if not DAMAGE.search(tooltip):
            continue
        points = 5 if "Finishing move" in tooltip else None
        key = f"{spell['class']}/{spell['name']}"
        # Same name can appear twice in one class (e.g. a talent and the trained spell): keep both.
        while key in out:
            key += "'"
        out[key] = track(spell["name"], tooltip, points)
    return out


def main():
    current = results()
    if "--update" in sys.argv:
        with open(EXPECTED, "w", encoding="utf-8", newline="\n") as f:
            json.dump(current, f, indent=1, ensure_ascii=False, sort_keys=True)
        print(f"wrote {len(current)} expected results to {os.path.relpath(EXPECTED)}")
        return 0
    if "--list" in sys.argv:
        for key, result in sorted(current.items(), key=lambda kv: (kv[1] == "not tracked", kv[0])):
            print(f"{key:<36} {result}")
        return 0

    expected = json.load(open(EXPECTED, encoding="utf-8"))
    problems = []
    for key in sorted(set(current) | set(expected)):
        if current.get(key) != expected.get(key):
            problems.append(f"{key}\n    expected: {expected.get(key)}\n    now:      {current.get(key)}")
    tracked = sum(1 for r in current.values() if r[0].isdigit())
    ignored = sum(1 for r in current.values() if r.startswith("ignored"))
    print(f"{len(current)} damage spells: {tracked} tracked as DoTs, {ignored} ignored on purpose, "
          f"{len(current) - tracked - ignored} not DoTs")
    if problems:
        print(f"\n{len(problems)} DIFFERENT from the reviewed snapshot:\n" + "\n".join(problems))
        return 1
    print("all match the reviewed snapshot")
    return 0


if __name__ == "__main__":
    sys.exit(main())
