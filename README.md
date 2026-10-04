# BattleInfoTool

**SpellDamageInfo**: Numbers of the damage and healing from each spell on action bar

![damage prediction](https://i.imgur.com/ySumj4S.png) ![healing prediction](https://i.imgur.com/xvGpoTg.png)

**DoTInfo**: marks on the target's health bar the damage of DoTs still have to deal, with a kill icon when target should die with current dots - great for mana management and visible indicator that dots are still on target.

DoTInfo presets style both the target frame and nameplates. **Juicy** uses matching striped segments, a different color per DoT, and dividers on both bars. Nameplate colors and fill can still be adjusted separately in `/bit` > DoTInfo > Nameplates.

![damage](https://i.imgur.com/QfaSkDy.png)

\[Based on DoesITDie addon \[MIT\] but with many my own changes, bug fixes and ideas [https://www.curseforge.com/wow/addons/does-it-die](https://www.curseforge.com/wow/addons/does-it-die)\]

Current supported DoTs

**Warlock**: Curse of Agony, Corruption, Immolate

**Priest**: Shadow Word: Pain, Devouring Plague

**Druid**: Moonfire, Rake, Rip, Insect Swarm

**Mage**: Ignite (z critów), Pyroblast

**Shaman**: Flame Shock

**Hunter**: Serpent Sting

**Rogue**: Rupture, Garrote

**Warrior**: Rend, Deep Wounds

**StatsInfo**: in an item's tooltip, how it compares to what you wear — scored per spec (Arms/Fury, Fire/Frost/Arcane…) with ForeverSim weights (built on WoWSims); tanks get survival + threat. Resto druids get a marked `(approx.)` heuristic score; other healers aren't rated yet **\[Work in progress\]**.

![stats comparison](https://i.imgur.com/wXVwDG6.png) ![another look on item](https://i.imgur.com/RIdkm9d.png)

**ResourceDing**: a sound when combo points (or another finisher resource) are full, and the points as dots under or above the target; for casters a sound when mana climbs to a max, and for warlocks one on each Soul Shard (and visible on target numbers of shards which Warlock has in bags).

![warlock shards](https://i.imgur.com/tVzNFEL.png)

![rogue combo points](https://i.imgur.com/1ITWdUb.png)

**Range**: a green checkmark over target while it is in range of class's main attacks, a red X while it is not. Action bar icons go grey while the target is out of their range (a setting, on by default).

**ShieldsInfo**: remaining absorption over the player, target, party frames and accessible nameplates.

![shields info](https://i.imgur.com/iqUSKt4.png) ![shield in party](https://i.imgur.com/NkpFqdh_d.png?maxwidth=520&shape=thumb&fidelity=high)

**HunterRange**: seven range chevrons for hunters, with crossed swords in melee and a skull in the dead zone. Bands are approximate, not exact yard measurements. Works only for hunter.

![range indicator](https://i.imgur.com/L7bopvP.png) ![dead zone](https://i.imgur.com/Ur0rxKh.png) ![meelee range](https://i.imgur.com/4CfMLky.png)

DoTInfo is based on a standalone DoT addon by Joe Greive (MIT), through Ironship's German fork of it (which on beggining added german support, during cast time dots info and few bug fixes but later grew into several helpers which are now part of this Addon. And this addon is under heavy development.
