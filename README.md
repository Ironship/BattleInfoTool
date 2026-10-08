# Useful Plates and Tooltips

Useful combat information for World of Warcraft: Forever. It shows DoT marks, shields and range on nameplates, damage and healing numbers on action buttons, and item comparisons in tooltips. Every part can be switched off.

Version 0.9.46 · Forever client 1.60.x (interface 16001)

## Install

1. Copy the `UsefulPlatesAndTooltips` folder (the one with `UsefulPlatesAndTooltips.toc`) into your game's `Interface\AddOns\` folder.
2. Start the game, or type `/reload` if you are already in it.

The zip made by `tools/build_zip.py` has this folder at its top level, so you can extract it straight into `Interface\AddOns\`.

## Commands

`/upt` (or `/usefulplates`) opens the settings window. Type it again to hide the window, or press Esc.

| Command | Opens |
| --- | --- |
| `/upt` | The window, on the tab you used last (Together at first) |
| `/upt together` or `/upt all` | Together: every enabled mark on one nameplate |
| `/upt sdi` | Spells: SpellDamageInfo |
| `/upt did` or `/upt dot` | DoTs: DoTInfo |
| `/upt stats` | Stats: StatsInfo |
| `/upt ding` | Points: ResourceDing |
| `/upt range` | Range |
| `/upt shields` | Shields: ShieldsInfo |
| `/upt hunter` | Hunter: HunterRangeFinder |

Diagnostics: `/upt probe`, `/upt rangecheck`, `/upt hunterprobe`, `/upt bagprobe`.

Switching a part on or off takes effect after `/reload`. Other settings apply at once.

## Parts

### Together

Every enabled mark on one sample nameplate. It warns when the hunter rail, the combo point dots and the Soul Shard diamonds would overlap.

### SpellDamageInfo

Damage and healing numbers on your action buttons and in spell tooltips.

Bars built on LibActionButton (Bartender4, ElvUI and others) get no numbers. Blizzard's action bars do.

![damage prediction](https://i.imgur.com/ySumj4S.png) ![healing prediction](https://i.imgur.com/xvGpoTg.png)

### DoTInfo

Shows the damage your DoTs still have to deal as a marker on the target's health bar. If the target's health ends inside the marker, a skull on the portrait says the DoTs will kill it. Only your own DoTs are tracked.

![damage](https://i.imgur.com/QfaSkDy.png)

Tracked DoTs, checked against the Forever spellbook:

- **Druid:** Moonfire, Insect Swarm, Rake, Rip (finisher), Lacerate, Pounce, Entangling Roots
- **Warlock:** Bane of Agony (Forever's name for Curse of Agony), Corruption, Immolate, Siphon Life, Wrack
- **Priest:** Shadow Word: Pain, Devouring Plague, Holy Fire
- **Mage:** Pyroblast, Fireball, Frostfire Bolt
- **Shaman:** Flame Shock
- **Hunter:** Serpent Sting, Lacerate
- **Rogue:** Garrote, Rupture (finisher)
- **Warrior:** Rend

Rip and Rupture use your combo points. Procs from critical hits, such as Ignite and Deep Wounds, are not tracked yet.

### StatsInfo

In an item's tooltip: how it compares with what you wear, what each difference is worth to your character, and how each spec of your class rates the item. Ratings use ForeverSim weights. Tanks also get survival and threat.

Every healer (Restoration druid or shaman, Holy priest or paladin) gets a score marked `(approx.)`. It is a heuristic, because ForeverSim does not simulate healing. **Work in progress.**

Tooltips are one line. Hold Shift to see the full version. Upgrade arrows also appear on bag, loot, need/greed and merchant buttons.

![stats comparison](https://i.imgur.com/wXVwDG6.png) ![another look on item](https://i.imgur.com/RIdkm9d.png)

### ResourceDing

A sound when your combo points (or another finisher resource) are full, and dots under or above the target that show the points.

Casters get a sound when mana climbs to a set level: 100% by default, 80% for warlocks. Warlocks also get a sound for each Soul Shard that enters the bags, and purple diamonds under the target's nameplate show how many shards you carry.

![warlock shards](https://i.imgur.com/tVzNFEL.png) ![rogue combo points](https://i.imgur.com/1ITWdUb.png)

### Range

A green checkmark over your target while your measuring spell reaches it, and a red X while none does. Action buttons go grey when the target is out of range (on by default).

### ShieldsInfo

Remaining absorb shields, drawn on your health bar, your target's, party frames and nameplates.

![shields info](https://i.imgur.com/iqUSKt4.png) ![shield in party](https://i.imgur.com/NkpFqdh_d.png?maxwidth=520&shape=thumb&fidelity=high)

### HunterRangeFinder

For hunters only. A range rail sits above the target's nameplate, or at a spot you place on screen: six dots, and a seventh past 35 yd when Hawk Eye is detected or switched on. A sword marks melee range, and a skull marks the dead zone. The bands are approximate, not exact yard measurements.

![range indicator](https://i.imgur.com/L7bopvP.png) ![dead zone](https://i.imgur.com/Ur0rxKh.png) ![melee range](https://i.imgur.com/4CfMLky.png)

## Development

The main test loads the whole addon in Lua 5.1 through `lupa`. It needs Python 3:

```
pip install lupa
python tests/test_bit.py      # the whole addon against a fake game client
python tools/build_zip.py     # writes dist/UsefulPlatesAndTooltips-<version>.zip
```

## Credits and licence

GPL-3.0-or-later, see [LICENSE](LICENSE). Third-party parts keep their own notices:

- **DoTInfo** is based on [Does It Die](https://www.curseforge.com/wow/addons/does-it-die) by Joe Greive (MIT), through Ironship's German fork.
- **SpellDamageInfo** and **ResourceDing** come from the standalone addons of the same names by Ironship (MIT).
- **StatsInfo** is written after the idea of RatingBuster (Whitetooth, GPL), with none of its code or tables. Stat weights come from [ForeverSim](https://github.com/laurencestokes/foreversim), built on WoWSims and Elliot Wood's Forever sim.
- **ShieldsInfo** bundles the MIT notice of Shield Aura Forever (`Modules/ShieldsInfo/LICENSE-ShieldAuraForever.txt`).
