# BattleInfoTool — raport końcowy review (HEAD c6f6a11 / SDI 56f3e46)

Metoda: fale po 3, deepseek-v4-flash (Opus 5.5 niedostępny — 403 oauth_org_not_allowed). Wiarygodne tylko lupa.lua51 / python3.12. Mirror: Temp/forever-ui (1.60.1/70009). Repo nieedytowane.
Ledger: 125 wpisów w 8 plikach. Baseline: tests/test_bit.py failed:0, tools/test_modules.py ok.

## Blokery wejścia (najpierw)
- TEST-COVERAGE (major): 9/9 mutacji silnika DoT niezłapanych — brak UNIT_COMBAT/UNIT_SPELLCAST/UNIT_POWER_FREQUENT, czas zamrożony, db.ticks nie seedowane, PlaySound brak, trupy const false.
- TEST-FIXTURE (major): fake SENT 3-arg vs 4-arg klienta. Plan P0/P1/P2 zweryfikowany w scratch (8/9 łapie, RG po fixie Range.usable).

## Ranking fixów (verified, skrót)
- [high/verified] F2-SKEP Modules/DoTInfo/DoesItDie.lua:653 — F2 sceptyk: VERIFIED, kazdy cast
- [high/verified] L11-1 Modules/DoTInfo/DoesItDie.lua:346 — L11-1 brak wspolnego providera CP
- [major/confirmed] DOT-1-CONF Modules/DoTInfo/DoesItDie.lua:501 — DOT-1 CONFIRMED pod lupa.lua51
- [major/verified] DOT-1-SKEP Modules/DoTInfo/DoesItDie.lua:501 — DOT-1 sceptyk: VERIFIED pod lupa
- [major/confirmed] DOT-2-CONF Modules/DoTInfo/DoesItDie.lua:442 — DOT-2 CONFIRMED pod lupa.lua51
- [major/verified] DOT-2-SKEP2 Modules/DoTInfo/DoesItDie.lua:442 — DOT-2 powtorka: VERIFIED twardym kontraktem
- [major/confirmed] DOT-3-CONF Modules/DoTInfo/DoesItDie.lua:603 — DOT-3 CONFIRMED pod lupa.lua51
- [major/verified] DOT-3-SKEP Modules/DoTInfo/DoesItDie.lua:603 — DOT-3 sceptyk: VERIFIED, wplyw wiekszy
- [medium/verified] F1-SKEP Modules/DoTInfo/DoesItDie.lua:709 — F1 sceptyk: VERIFIED
- [medium/verified] F3-SKEP Modules/DoTInfo/DoesItDie.lua:671 — F3 sceptyk: VERIFIED
- [medium/verified] F5-SKEP Modules/DoTInfo/DoesItDie.lua:696 — F5 sceptyk: VERIFIED
- [medium/verified] L-10-wskrzeszenie Modules/DoTInfo/DoesItDie.lua:1806 — L-10 cache CP przezywa smierc
- [medium/verified] L06-1 Core/Init.lua:116 — L06-1 'both' tylko ostrzega
- [medium/verified] L06-2 Modules/ResourceDing/Core.lua:331 — L06-2 slash/hooki przed ShouldRun
- [medium/verified] L06-3 Modules/DoTInfo/DoesItDie.lua:1465 — L06-3 attach bez retry
- [medium/verified] L07-1 Modules/DoTInfo/DoesItDie.lua: — L07-1 reload gubi zywe DoT
- [medium/verified] L07-2 Modules/DoTInfo/Nameplates.lua:273 — L07-2 wyciek potwierdzony liczbowo
- [medium/verified] L11-2 : — L11-2 namespace bez API + duplikacja
- [medium/verified] L11-3 Modules/DoTInfo/Nameplates.lua: — L11-3 40-slot poll + podwojna praca RD
- [medium/verified] UI-1-SKEP Modules/DoTInfo/Nameplates.lua:273 — UI-1 sceptyk: VERIFIED wykonaniem kodu
- [medium/verified] UI-2-SKEP Modules/DoTInfo/Nameplates.lua:286 — UI-2 sceptyk: VERIFIED
- [minor/verified] DOT-4-SKEP Modules/DoTInfo/DoesItDie.lua:25 — DOT-4 sceptyk: VERIFIED, wyzwalacz rzadki
- [minor/verified] DOT-5-SKEP Modules/DoTInfo/DoesItDie.lua:769 — DOT-5 sceptyk: VERIFIED, downgrade medium->minor
- [minor/verified] DOT-6-SKEP Modules/DoTInfo/DoesItDie.lua:700 — DOT-6 sceptyk: VERIFIED z rozbiciem na 2 sciezki
- [minor/verified] RD-1-SKEP Modules/ResourceDing/Core.lua:382 — RD-1: VERIFIED, re-ding po powrocie na cel
- [minor/verified] RD-10-SKEP Modules/ResourceDing/Mana.lua:40 — RD-10: VERIFIED, falszywy ding przy spadku max
- [minor/verified] RD-3-SKEP Modules/ResourceDing/Core.lua:331 — RD-3: VERIFIED z korekta (2x, nie 4x)
- [minor/verified] RD-4-SKEP Modules/ResourceDing/Core.lua:419 — RD-4: VERIFIED, probe 4 zamiast 5
- [minor/verified] RD-5-SKEP Modules/ResourceDing/Settings.lua:181 — RD-5: VERIFIED, slidery nie ruszaja rombow
- [minor/verified] RD-6-SKEP Modules/ResourceDing/Core.lua:84 — RD-6: VERIFIED, brak 3 opcji dzwieku na Forever
- [minor/verified] SDI-BLACKARROW-SKEP Modules/SpellDamageInfo/Parser.lua:201 — SDI-BLACKARROW: VERIFIED, fix w standalone
- [minor/verified] SDI-MACRO-SKEP Modules/SpellDamageInfo/Core.lua:753 — SDI-MACRO: VERIFIED, makro /cast bez liczby
- [minor/verified] SI-124-SKEP Modules/StatsInfo/StatsInfo.lua:124 — SI-124: VERIFIED, '+0.0' przy malej roznicy DPS
- [minor/verified] SI-249-SKEP Modules/StatsInfo/StatsInfo.lua:249 — SI-249: VERIFIED, zmyslone +10 health w combat
- [minor/verified] SI-751-SKEP Modules/StatsInfo/StatsInfo.lua:751 — SI-751: VERIFIED, licznik probe nie odswieza
- [low/verified] DRIFT-CORE-SKEP Modules/SpellDamageInfo/Core.lua:1269 — DRIFT-CORE: VERIFIED, kolizja /sdi
- [low/verified] F4-SKEP Modules/DoTInfo/DoesItDie.lua:596 — F4 sceptyk: VERIFIED
- [low/verified-mechanism] L-08-CP-forma Modules/DoTInfo/DoesItDie.lua:361 — L-08 cache CP forma/stealth: mechanizm tak, impact nie
- [low/verified-gap] L-09b Modules/ResourceDing/Mana.lua: — L-09b brak dzwieku many peta
- [low/verified-gap] L-09c Modules/Range/Range.lua: — L-09c RG pet range klamie + dim nie dziala

## Obalone (nie fixować)
- [info/refuted] L-13-SI-shortNumber Modules/StatsInfo/StatsInfo.lua: — L-13 brak regresji shortNumber
- [info/refuted] L-08-RG-forma Modules/Range/Range.lua:257 — L-08 RG marker nie zastyga
- [info/refuted-suspicion] SENT-READ-OK Modules/DoTInfo/DoesItDie.lua:1814 — Sciezka read SENT zyje; podejrzenie 4.arg/3-elem OBALONE
- [info/refuted] SI-236-REF Modules/StatsInfo/StatsInfo.lua:236 — SI-236: OBALONE - staty tozsamosciowe celowo bez worth
- [info/refuted] SI-98-REF Modules/StatsInfo/StatsInfo.lua:98 — C_Item.GetItemInfoInstant link vs itemID - OBALONE
- [info/refuted] SI-481-REF Modules/StatsInfo/StatsInfo.lua:481 — showDiffs wylacza spec ratings - OBALONE
- [info/refuted] SI-ORD-REF Modules/StatsInfo/StatsInfo.lua: — Kolejnosc specow / armor total / .0 trim - OBALONE
- [info/refuted] RG-OK Core/Settings.lua:171 — Reload w walce / slider thumb - OK na zywym kliencie
- [info/refuted] RD-2 Modules/ResourceDing/Core.lua:379 — UNIT_MAXPOWER full->0 nie wystepuje
- [info/refuted] RD-8 Modules/ResourceDing/Core.lua:233 — suppressIfMusic - OBALONE
- [info/refuted] SI-550-REF2 Modules/StatsInfo/StatsInfo.lua:550 — SI-550 OBALONE: ShouldDoItemComparison istnieje

## Needs-ingame
- [low/needs-ingame] UI-5-SKEP Modules/DoTInfo/DoesItDie.lua:1465 — UI-5: downgrade medium->low, trigger przeformulowany
- [low/needs-ingame] UI-8-SKEP Modules/DoTInfo/Nameplates.lua:148 — UI-8: niepotwierdzony, bezpieczna sciezka w kodzie
- [low/needs-ingame] UI-6 Modules/DoTInfo/Nameplates.lua:19 — nameplate40 vs 150
- [low/needs-ingame] SI-550 Modules/StatsInfo/StatsInfo.lua:550 — gameCompares zalezy od TooltipUtil.ShouldDoItemComparison

## Routing
- DoesItDie/Nameplates + SDI (MACRO, BLACKARROW, DRIFT-CORE): fix w repo standalone + re-port tools/port.py. Edycja kopii w BIT zniknie.
- StatsInfo / ResourceDing / Core-Init-Range: fix w BIT.

## Kolejność napraw
TEST-COVERAGE + TEST-FIXTURE → DOT-2 (+L-10 wskrzeszenie) → DOT-1 → DOT-3+F2 → L11-1 provider CP → F3 → UI-1 → UI-2 → UI-3/4/7 → minore SI/RD/SDI.