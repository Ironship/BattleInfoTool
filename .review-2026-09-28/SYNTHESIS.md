# BattleInfoTool quality review — synteza przyrostowa (HEAD c6f6a11 / SDI 56f3e46)

Metoda: fale po 3, model cheap-smart (deepseek-v4-flash). Opus 5.5 niedostepny — 403 oauth_org_not_allowed w sesji Claude.
Wiarygodne tylko lupa.lua51 na python3.12 (pelna sciezka Python312). lua.exe to 5.4.6 — niewiarygodny.
Mirror API: Temp/forever-ui (Ketho/wow-ui-source-forever bd2470a, 1.60.1/70009).
Baseline: tests/test_bit.py failed:0, tools/test_modules.py ok. Repo nieedytowane; klony w scratch.
Ledger: .review-2026-09-28/findings.jsonl (58) + findings-wave5.jsonl (5) + findings-wave6.jsonl (3) + findings-wave7.jsonl (7) + findings-wave8.jsonl (3) + findings-wave9.jsonl (18) + findings-wave10.jsonl (12) + findings-wave11.jsonl (19). Total 125 fizycznie.

## Zweryfikowane pod lupa (sceptyk repro+impact)

HIGH:
- F2-SKEP DoesItDie.lua:653 SWAP z opisu. referenceTickSize przy normalTicks<=1 bierze share z opisu, ignoruje learned. A: falszywa czaszka ~6s. B: brak czaszki. Zatruty learned przezywa smierc celu. Fix: referenceTickSize najpierw db.ticks[tickKey], albo >=2 realne ticki przed zapisem learned ze swapu.

MAJOR (silnik trackingu):
- DOT-1-SKEP :501 DoT na biezacy cel, nie cel rzutu. :1808 niszczy castInProgress z :557, :501 bierze unitKey(target), :1831 ignoruje unitTarget z payloadu mimo SynchronousEvent. S1c: cel umiera przed SUCCEEDED -> porzucony bez sladu. Czeste w PvE multi-target; falszywa czaszka obustronnie; tez upstream f0f6911 :496. Fix: uzyc unitTarget z SUCCEEDED.
- DOT-2-SKEP2 :442 cache combo przezywa zmiane celu. 5 CP na A, tab na B, Rip <3s -> 980 zamiast 196; comboAtSend=0 nie hamuje; >3s wygasa. Regex :482 plural OK. Fix: zerowac lastComboPoints/lastComboAt w TARGET_CHANGED albo cache z GUID celu.
- DOT-3-SKEP :603 white-hit kradnie tick 1. Nie znika po nauczeniu (tol 30%). MC 6-20%/cast swiezy, 15% przy learned, cat ~90% castow z bialym; dryf SV 70%. Marker +38% w S1. Fix: nie przyjmowac 1. ticka bleedu z unsure bez 2 potwierdzonych.

MEDIUM:
- F1-SKEP :709 dedupe key:amount:school:GetTime() zjada drugi tick (Corruption+Siphon po 100). DROP never-ticked, ESTIMATE 1600->300. Kierunek bezpieczny. Fix: bez GetTime() w sygnaturze albo spellID w sygnaturze.
- F3-SKEP :671 relearn ufa 2 obcym hitom. learned 100 -> 500, ESTIMATE +233%, falszywa czaszka ~6s. Fix: >=3 spojne hity albo kotwica rytmu od appliedAt.
- F5-SKEP :696 full-resist w oknie 0.4s cofa swiezy DoT. ESTIMATE 600->300, expiry wczesniej. Kierunek bezpieczny.
- UI-1-SKEP Nameplates.lua:273 wyciek widgetow. Recykling z nowym healthBar -> drugi komplet (23 regiony), stary shown; 4 recyklingi = 92 regiony; zero Destroy. Fix: hideWidgets starego + Destroy przy zmianie bara.
- UI-2-SKEP Nameplates.lua:286 marker na martwej plate. (0,0)+750 na iconBar, wszystko shown; live ten sam trup -> hideAll :1636. Wisi do expiry (do 30s, typowo 6-18s). Fix: guard UnitIsDead/UnitHealth<=0 w updatePlate.

LOW:
- F4-SKEP :596 partial resist. Brak flagi RESIST, tylko amount; 2x60 relearnuje 100->60. Bezpieczny.
- UI-3-SKEP :266 niespojne bramkowanie. marker+showMarkers=false -> pusto; markerIcon+showMarkers=false -> ikona zostaje. Fix: marker iff mode!=off AND showMarkers; ikona iff markerIcon AND showMarkers.
- UI-4-SKEP :1624 preview czaszka na trupie. {health=0,dots=45} -> skull TRUE; live FALSE. Fix: if total<=0 or health<=0 then hideAll.
- DOT-4-SKEP :25 VERIFIED minor. Repro 1:1: tick1 @+3.4 przyjety (okno 0.45), ticki 6/9/12/15/18 odrzucone (dist 0.4>0.25), ESTIMATE 50 vs 25, phantom +1 tick do EXPIRE. Pas (0.25,~0.45]; delay 0.45 w float 5.1 odpada. K1 na czas 6/6 OK. Stala latencja +0.4 na wszystkich 6/6 OK. Twoje SV: 0/57 w pasie, brak haste - rzadki spike.
- DOT-5-SKEP :769 VERIFIED minor (downgrade z medium). Ticki 3.5/6.5 odrzucone -> DROP never-ticked w 6.6, marker 40->30->0 mimo 20 dmg do 112.0. Kontrola 3.0/6.0 OK; 0.4s pozno akceptowane. :502 unitKey=nil -> 0 linii (lamie :180). 2s DoT-y DROPuja w 4.4s.
- DOT-6-SKEP :700 VERIFIED minor, 2 sciezki: ABSORB odrzucany cicho (brak HIT-trace), 2 absorby -> DROP; WOUND 0 z learned -> odrzucony, 2 zera -> RELEARN uczy 0 (marker 0 przy zywym); bez learned pierwsze zero uczy 0. Overcount remaining o wchloniete sloty. 120/120 kontroli (91 forka + 29).
- UI-7-SKEP :1299 glow bez outline. showGlow bez guarda na outlineStyle; osiagalne stara DB i biezacym UI. Fix: gate showGlow and outlineStyle~=none.
- DOT-2-SKEP (fala 4, sceptic-incomplete) SUPERSEDED przez DOT-2-SKEP2 (fala 6, verified) — nie liczyc podwojnie w rankingu.

## Obalone / obserwacje (nie fixowac jako bledy)

- SENT-READ-OK :1814 — payload SENT 4-elementowy, select(4,...) zgodne z FrameXML. Podejrzenie martwego reada obalone (artefakt 3-arg harnessa). DOT-2 stoi na legalnym 0 + fallback.
- SI-98 guard C_Item OK; SI-481 showDiffs OK; porzadek specow / armor +58 / .0 trim OK.
- RG-OK reload w walce + slider OK; RG-122 fallback martwy na Forever (C_Spell tabelka); RG-196 guard przez przypadek; RG-55 Dire Bear martwe.
- RD-2 UNIT_MAXPOWER nie wystepuje; RD-8 suppressIfMusic to forceNoDuplicates.
- SI-550-REF2 ShouldDoItemComparison istnieje — tlumienie duplikatu celowe.
- DRIFT-OK port SDI 1:1, 0 driftu logiki; SDI-STANCE/SDI-GETSPELLINFO obserwacje.
- UI-5 downgrade do low/needs-ingame: UI scale/Edit Mode nie niszczy regionow; realna luka to brak retry attach (tylko 2 wywolania 1731/1798).

## Needs-ingame (nie rozstrzygac offline)

- UI-6 nameplate40 vs 150; UI-5 czy Forever niszczy regiony; UI-8 strata-secret (low).

## Blokery testowe (warunek wejscia dla fixow)

- TEST-COVERAGE major: 9/9 mutacji silnika DoT niezlapanych przy 3/3 kontrolach. Brak UNIT_COMBAT/UNIT_SPELLCAST/UNIT_POWER_FREQUENT, czas zamrozony, db.ticks nie seedowane, PlaySound brak, trupy const false.
- TEST-FIXTURE major: fake SENT 3-arg vs 4-arg klienta. DOT-1/F1/F3/F4/F5 niezalezne; DOT-2 potwierdzony z 4-arg.
- Do testow przed fixami: sterowalny GetTime, eventy 4-arg SENT, seed db.ticks, stub PlaySound, trupie plate.

## Routing fixow

- DoesItDie/Nameplates + SDI: fixy w repo standalone + re-port przez tools/port.py. Reczna edycja kopii w BIT zniknie.
- SDI-BLACKARROW low: fix w standalone + re-port.

## Kolejka (fale po 3)

- Fala 8 (gotowa): DOT-4/5/6 verified minor (DOT-5 downgrade z medium).
- Fala 9 (gotowa): SI-249/250/124/751 verified (SI-236 refuted); RD-1/3/4/5/6/10 verified, RD-7 partial; SDI-MACRO/BLACKARROW verified, DRIFT-CORE verified, RG-363 verified, RG-123 vestigial, UI-8 needs-ingame.
- Fala 10 (final, gotowy, deleg_52295614): krytyk kompletnosci (10 obszarow, 17 luk L-01..L-17) + ranking 30 fixow z routingiem + plan test-gapow P0/P1/P2 zweryfikowany w scratch (8/9 mutacji lapie, RG po fixie Range.usable).
- Fala 11 (gotowa, deleg_a73033a8, 19 wpisow): domkniecie luk high/medium krytyka — L11-1 provider CP (high), L06-1/2/3 login, L07-1/2 reload, L-10 wskrzeszenie (nowy trigger DOT-2), L-09b/c pet low, L-08/L-10-stan/L-13 obalone lub OK.

Kolejnosc napraw: TEST-COVERAGE + TEST-FIXTURE (blokery wejscia), DOT-2 (+ L-10-wskrzeszenie, ten sam root), DOT-1, DOT-3+F2 razem (SV ma 4 ticki = gracz w galezi unsure), L11-1 provider CP, F3, UI-1, UI-2, UI-3/UI-4/UI-7.

## Decyzje WONTFIX (fala 12): DOT-4 i DOT-5 rozstrzygniete

Repro na HEAD ac5accd (klony scratch bit-dot45/bit-dot45-fix, lupa 5.1; repo nieedytowane; suita HEAD 230/230).

- **DOT-4 WONTFIX** (pas transjentu (0.25, 0.45] na ticku 1). Zmierzone: 1/6 tickow przyjetych, ESTIMATE +1 tick (25/150) od 6.2 do konca; 50 vs 25 @15.2; phantom +25 do 18.85; EXPIRE 18.4+0.45; unlearned identycznie. Czestotliwosc 0/57 (offseTy <=0.1s). Kazdy kandydat fixu zmierzonego ma regresje: (a) okna >=0.5: float 0.5000000000000002 lamie granice wiec realnie 0.55+, podwaja pas obcych hitow dla anchored (obrona 0.25 przed white-hitami - komentarz zrodlowy); (b) snap kotwicy do siatki nominalnej: lamie U1 (stala latencja +0.4 -> wszystkie ticki odrzucone, DROP); (c) tryRelearn 0.75+re-anchor: naprawia oba, kontrole i 230/230 zielone bez zmian, ALE wskrzesza dispelled DoT z cudzych hitow same-school ~size w pasie (0.45,0.75] (RELEARN, ghost marker) - nowy wektor err-high nielapany przez suite.
- **DOT-5 WONTFIX** (uniform >0.45 s). Zmierzone: DROP 'never ticked' @6.7, marker 0 od 6.7 (dot zyje do 18.5, 100 dmg); kierunek err-low; wariant :502 cichy juz naprawiony (DOT-5b). 0.5s = 5x poza obserwowanym <=0.1s; okno 0.45->0.5 nie dziala na granicy float (trzeba 0.55+). Fix tryRelearn 0.75 dziala, ale z ta sama regresja ghost (DOT-4-WF c).
- **Wniosek**: oba to zweryfikowane mechanizmy o czestotliwosci ~0, severity minor; nie istnieje fix bez wymiany na inna (zmierzona albo udokumentowana) regresje; suite nie certyfikuje bezpieczenstwa (kandydat przechodzi 230/230 przy widocznej regresji ghost). **DOT-4/5 zdejmuje z kolejki napraw; DOT-6 zostaje.** Gdyby kiedys wracac: ciasniejszy window pierwszego ticka (0.45->0.25) jest najmniej zly (K2 dowodzi bezpieczenstwa odrzucenia poznego ticka1: 5/6 przyjete, estymaty wyborne) - ale i on lamie U1. Uwaga techniczna: main chunk DoesItDie.lua stoi na limicie 200 lokalnych Lua 5.1 - kazdy fix musi podmieniac lokalne, nie dodawac.

## Nowe z fali 11 (domkniecie luk krytyka)

HIGH:
- L11-1 DoesItDie.lua:346 brak wspolnego providera CP. W walce RD widzi display 5/5, a DoTInfo 'secret, counted=0' -> Rip 243 zamiast 855 (3.55x za nisko). DoTInfo nie slucha UNIT_COMBO_POINTS. Fix: BIT.ComboPoints() + fallback do display RD.

MEDIUM:
- L06-1 Core/Init.lua:116 'both' tylko ostrzega — modul dalej dziala (duble calej sesji). Fix: realnie wylaczyc modul w PLAYER_LOGIN.
- L06-2 hooki RD i slashe przed ShouldRun zostaja po wylaczeniu; 'switched off' przy state nil klamie.
- L06-3 attach bez retry: brak TargetFrame przy starcie = skull na UIParent do reloadu.
- L07-1 reload gubi zywe DoT i castInProgress; ticki po reloadzie ignorowane. db.ticks trzyma (PASS).
- L07-2 wyciek 2->4->6 widgetow na recykl (pomiar, zgodne z UI-1).
- L-10-wskrzeszenie :1806 cache CP przezywa smierc — nowy trigger DOT-2, falszywa czaszka w oknie 3s. Scalic z fixem DOT-2.
- L11-2 namespace BIT bez API; TARGET_CHANGED x5, PEW x3, UNIT_POWER_* x3. -> ROZSTRZYGNIETY: WONTFIX (fala 12b, nizej).
- L11-3 420 UnitExists/s z 40-slot pollu (3 platy); 4 OnUpdate; 5x ComboFrame_Update = 20 odczytow. -> ROZSTRZYGNIETY: naprawiony (9090a5f, fala 12b, nizej); czesc RD zaspokojona przez RD-3.

## Decyzje (fala 12b): L11-2 WONTFIX, L11-3 naprawione (HEAD 9090a5f)

Pomiary na HEAD (lupa 5.1, harness z licznikami API: 1s symulacji, 3 platy z DoT, ticks 0.1s):
- Poll nameplate: UnitExists(nameplate1..40) = 400 (40 slotow x 10Hz), GetNamePlateForUnit = 30, UnitHealth/UnitHealthMax(nameplate*) = 30/30, +10/10 odczytow celu. Aktywne framy OnUpdate: 2 (driver target DoesItDie 0.1s + driver Nameplates 0.1s), 10 odpalen/s kazdy.
- RD po RD-3: 5x ComboFrame_Update w odstępach 0.6s -> 10 lookow (5 bezposrednich + 5 settle) -> 20 odczytow RD (UnitPower+UnitPowerMax na look) — zgodne z pomiarem fali 11; 5 redrawow co 0.2s -> 7 lookow (dedupe settle dziala). Liczba faktycznych odczytow na redraw juz po RD-3 = 2x mniej niz przed.
- Census sluchaczy: 13/41 eventow z >1 sluchaczem; PLAYER_TARGET_CHANGED x6 = 6 roznych prac (SDI rejestr castow, DoTInfo latch CP/guid, RD Core latch, RD Dots RefreshDots, RD Shards RefreshShards, Range ikona) — zero zduplikowanej roboty.

L11-2 WONTFIX: wielokrotni sluchacze to wzorzec per-modul, zaden event nie ma dwoch sluchaczy robiacych to samo; koszt dispatchu to ~6 mikro-wywolan na zmiane celu (event rzadki — mierzalny zysk ~0). Wspolny provider eventow wymagalby przekierowania 4 portowanych modulow (SDI/RD/DoTInfo/StatsInfo) przez BIT: dryf portu (port.py) + zmiana kolejnosci dispatchu (kolejnosc rejestracji = kolejnosc wywolan; moze zmienic zachowanie latch na TARGET_CHANGED) przy braku wymiernej korzysci. Start niespojny (file-scope vs PLAYER_LOGIN) nieobserwowalny: moduly startujace w file-scope tylko tworza framy i rejestruja eventy (bez dostepu do SavedVariables przed ADDON_LOADED), cala logika bramkowana przez BIT.ShouldRun; suita przechodzi bez zmian. Wartosciowa czesc znaleziska (wspolne API stanu, np. BIT.ComboPoints) juz w kolejce jako L11-1.

L11-3 NAPRAWIONE (9090a5f, RED+GREEN; korekta 113a535: UPDATE_INTERVAL 0.1 -> 0.2, nie 0.25 — 0.25 łamało rytm test_load standalone, który rysuje w jednej ramce 0.2 s po SUCCEEDED): UPDATE_INTERVAL 0.1 -> 0.2 w Modules/DoTInfo/Nameplates.lua (edycja bezpośrednia — port DoTInfo zamrożony). RED: "1s symulacji, 3 platy: poll <= 200 slotów/s" — na HEAD 400 -> FAIL (kontrole zielone: markery rysują się, trup chowa markery w 0.4s). GREEN po fixie: 200/s (5 Hz), GetNamePlateForUnit/UnitHealth w normie. Koszt: latencja markera <= 0.2s; tick DoT <= 1/s, więc 5Hz wystarcza; suita 0/0 zielona (także UI-1/UI-2/UI-4 na nowym rytmie).

## Decyzje (fala 13): DRIFT WONTFIX/OK, RD-5/6/7 done, L11-2 WONTFIX, L11-3 done (HEAD 113a535)

Ledger: `.review-2026-09-28/findings-wave13.jsonl` (8 wpisów: DRIFT-CORE-WF, DRIFT-OPTIONS-WF, DRIFT-OK, RD-5, RD-6, RD-7, L11-2-WF, L11-3).

- **DRIFT-CORE WONTFIX** — kolizja `SlashCmdList[SPELLDAMAGEINFO]` istnieje tylko przy współistnieniu ze standalone. Po decyzji użytkownika (standalone zbędne, niewspierane) scenariusz nieobsługiwany; w samym BIT jeden writer. Bez zmian kodu.
- **DRIFT-OPTIONS WONTFIX** — niespójność shima (`BIT.Module and ... or BIT` vs guardowana forma) bez scenariusza crasha; Init.lua zawsze pierwszy z .toc. Kosmetyka, bez akcji.
- **DRIFT-OK / obserwacja** — port SDI 1:1 bajt-w-bajt po shim (c6f6a11 vs 56f3e46); delty HEAD (SDI-MACRO/BLACKARROW, cleanup) to zamierzone fixy lokalne w BIT pod nową politykę.
- **RD-5 done (1ba3555)** — settery dotSize/dotOffset wołają też RefreshShards; RED 2 FAIL -> GREEN.
- **RD-6 done (1ba3555 + compat 113a535)** — quest/coins akceptują stary lub nowy klucz SOUNDKIT, level przywrócony, bell fallback 73280, prune po aliasach. classic.test.lua zielony. Uwaga: klucze Classic-stubów (UI_QUEST_COMPLETE/LEVEL_UP/LOOT_MONEY_COINS) muszą zostać obsłużone, inaczej regresja suity standalone.
- **RD-7 done (1ba3555)** — PlaySoundKey w pcall; brak/err zwraca false zamiast zabijać handler OnEvent.
- **L11-2 WONTFIX** — jak w fali 12b (6 różnych prac na TARGET_CHANGED, zysk ~0, dryf portu).
- **L11-3 done (9090a5f + 113a535)** — throttle 10Hz -> 5Hz (0.2 s). 0.25 łamało test_load (rysowanie w ramce 0.2 s) — stąd korekta.

Uwaga o portach: RD i SDI nie są zamrożone (w przeciwieństwie do DoTInfo), więc ponowny `tools/port.py` skasowałby lokalne fixy (RD-1/3/4/5/6/7/10, SDI-MACRO/BLACKARROW). Przed kolejnym portem zapisać je jako patch albo zablokować w port.py. DoTInfo edytować tylko wprost w Modules/DoTInfo (port zablokowany).

LOW:
- L-09b RD nie mierzy many peta (cecha upstream, nie regresja).
- L-09c RG marka 'out' gdy pet dobija + dim pet bar nie dziala.
- L-08-CP-forma mechanizm tak, impact zero na Forever (Classic).
- L-13 edge 0.05: linia szara, czytana jako 0.1%.

OBALONE / OK:
- L-09a pet DoT nie istnieje w contentcie 1.6; L-09d SDI pet pelne pokrycie; L-08 RG marker nie zastyga; L-10 smierc bez martwych markerow; L-13 shortNumber 0/36k; L-13 fallback 1:1.
