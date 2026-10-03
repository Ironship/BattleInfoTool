# BattleInfoTool

A World of Warcraft addon for WoW: Forever that puts several combat helpers in one place. Each is a part of its own, with a tab in the settings window (`/bit`) and an Enable switch at the top of it:

- **SpellDamageInfo**: the damage and healing from each spell's description on your action buttons and in the tooltip.
- **DoTInfo**: marks on the target's health bar the damage your DoTs still have to deal, with a kill icon when they will finish it. `/dotinfo`.
- **StatsInfo**: in an item's tooltip, how it compares to what you wear — scored per spec (Arms/Fury, Fire/Frost/Arcane…) with [ForeverSim](https://www.lozstokes.co.uk/foreversim/forever/) weights (built on [WoWSims](https://github.com/wowsims)); tanks get survival + threat. Resto druids get a marked `(approx.)` heuristic score; other healers aren't rated. In bags (Blizzard + Baganator) a small arrow flags it at a glance: green up = upgrade, red down = worse.
- **ResourceDing**: a sound when your combo points (or another finisher resource) are full, and the points as dots above or below the target's health bar (offset -80..30, dot size); for casters a sound when mana climbs to a level, and for warlocks one on each Soul Shard plus purple diamonds under the target. `/rding off` silences all of them.
- **Range**: a green checkmark over your target while it is in range of your class's main attacks, a red X while it is not. Action bar icons go grey while the target is out of their range (a setting, on by default). `/bit rangecheck` lists what the game answers for each spell.

A part switched off does not run at all; the switch takes effect after a reload.

- **ShieldsInfo**: remaining absorption as a bar overlay on your player, target and party frames and on accessible nameplates, with adjustable opacity. No floating HUD. `/bit shields`.
- **HunterRangeFinder**: a range rail that rides above the target's nameplate (or floats at a saved screen spot): six dots, a seventh with Hawk Eye (auto-detected from Auto Shot's reach), crossed swords in melee and a skull in the dead zone. Fully inside BattleInfoTool — no separate addon required. `/bit hunter` opens the settings; `/bit hunterprobe` prints diagnostic range answers. Bands are approximate, not exact yard measurements. Other classes create no hunter HUD.

**Install:** unzip `BattleInfoTool-<version>.zip` into `Interface\AddOns` of the `_classic_beta_` folder, then restart the game.

SpellDamageInfo and ResourceDing are copied in from their own repositories by `tools/port.py`, which lists every change they need here; DoTInfo lives only here and is edited directly in `Modules/DoTInfo/*`. Its tests live in `tools/dot_fixtures/` and are run by `tools/test_modules.py`, which also runs each ported module's own tests against the copies; `tests/test_bit.py` tests the addon as a whole. DoTInfo is based on a standalone DoT addon by Joe Greive (MIT), through Ironship's German fork of it. Licence: GNU GPL-3.0-or-later (see `LICENSE`).
