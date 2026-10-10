# Useful Plates and Tooltips — Retail

Wersja testowa zawiera **DoTInfo, ResourceDing, ShieldsInfo i SpellDamageInfo**, ich ustawienia oraz wspólny wygląd. Nie ładuje pozostałych modułów. Manifest Mainline jest przeznaczony dla Retail 12.1.0 (`Interface: 120100`). Build 12.1.0.69933 został potwierdzony 8 października 2026 w [serwisie wersji Blizzarda](https://us.version.battle.net/v2/products/wow/versions).

## Instalacja

1. Zbuduj paczkę: `python tools/build_zip.py --retail`.
2. Wypakuj folder `UsefulPlatesAndTooltips` z `dist/UsefulPlatesAndTooltips-0.9.52-retail.zip` do `_retail_/Interface/AddOns/`. Przy zastępowaniu starszej paczki usuń jej folder po wykonaniu kopii; nie nakładaj ZIP na stare pliki.
3. Włącz addon w grze. `/upt` otwiera ustawienia; `/reload` stosuje zmianę włączenia modułu. Włącz wyświetlanie wrogich nameplate klawiszem `V`.

ZIP Retail ma własny `UsefulPlatesAndTooltips_Mainline.toc`; nie zawiera manifestu Forever ani pozostałych modułów. Zwykłe `python tools/build_zip.py` nadal buduje dotychczasową paczkę Forever.

## Zakres prototypu

Pasek szacowanych obrażeń DoTInfo rozpoznaje bezpośrednio rzucane czary: Corruption i Agony (warlock), Shadow Word: Pain i Vampiric Touch (priest), Moonfire, Sunfire, Rake i Rip (druid), Garrote i Rupture (rogue), Flame Shock (shaman) oraz Rend (warrior). Czary muszą występować w wybranej specjalizacji, a ich opis musi dać się odczytać. Parser obejmuje angielskie i niemieckie opisy. Unstable Affliction, Shadow Word: Madness, Barbed Shot, efekty obszarowe, proce, kanały i dodatkowi odbiorcy Sunfire są poza tym modelem liczbowym.

Odnowienie zachowuje przewidywany pozostały czas do 30% bazowego czasu DoT (Pandemic); złoty kolor oznacza wejście w to okno. Gdy odbiorca rzutu jest ukryty, addon zakłada wybrany cel przy braku konkurencyjnego focus/mouseover; pomija niejednoznaczne przypisania. Poprawność tego założenia dla własnych makr trzeba sprawdzić w grze.

Rogue otrzymuje również **ikony rzeczywiście aktywnych krwawień i trucizn**, z natywnym czasem pozostałym i liczbą stosów: Garrote, Rupture, Deadly Poison, Amplifying Poison, Kingsbane, Deathmark, Internal Bleeding i Mutilated Flesh/Doomblade. Amplifying Poison pokazuje stosy, nie osobny DoT. Ikony własnych efektów pojawiają się nad paskiem celu i na wrogich nameplate; używają wspólnych ustawień `showMarkers` oraz `nameplateMode`. Blizzard obsługuje stan aur, timery i stosy. Gdy natywny kontener aur jest niedostępny, ikony pozostają wyłączone bez blokowania pozostałych modułów.

Liczbowy pasek rogue nadal szacuje wyłącznie własne rzucenia Garrote/Rupture i nie zgaduje obrażeń ukrytych proców trucizn. W bieżącym Retail Crimson Tempest kopiuje istniejące Garrote/Rupture: te kopie może pokazać natywny kontener, ale addon nie dodaje osobnego szacowanego DoT Crimson Tempest.

Overlay DoT pozostaje dzieckiem całej ramki nameplate. Rozmiar jest dopasowywany osobno do rzeczywistego paska zdrowia i przeliczany pomiędzy ich skalami. Gdy wymiary lub skala są ukryte, pozostają natywne kotwice bez zgadywania rozmiaru. Od 0.9.50-retail wspólny wybór paska rozpoznaje również aktywny widget zdrowia Platynatora; ten addon ukrywa oryginalny pasek Blizzarda. DoTInfo, ikony rogue, ResourceDing i ShieldsInfo używają widocznego paska zamiast ukrytej ramki, również po zmianie stylu lub rozmiaru. Ten sam wybór paska i przeliczenie skali są używane w paczce Forever; jej testy obejmują również Platynatora, ale wygląd w tym kliencie wymaga sprawdzenia w grze. Integracja odpowiada lokalnej wersji Platynatora `499-1-g4e9cab2`; jego wewnętrzny układ widgetów może zmienić się w przyszłości.

`/dotinfo plates` zapisuje pozycje i skale ramki, wybranego paska, znacznika i segmentu oraz aktualne ustawienia gry. Uruchom komendę przy widocznym przeciwniku z DoT, następnie `/reload`, aby zapisać pomiar w logu DoTInfo. API może odmówić odczytu pozycji regionów nameplate; wtedy log zachowuje informację o odmowie zamiast wykonywać arytmetykę na tych danych.

ResourceDing obejmuje combo points rogue/druida, Soul Shards warlocka, Holy Power paladyna, Chi Windwalker monk, Arcane Charges Arcane mage i Essence evokera. Widoczność i dźwięki zależą od aktywnego zasobu, formy oraz specjalizacji.

ShieldsInfo pokazuje pozostały absorb na dostępnych ramkach gracza, celu, grupy oraz nameplate. Tajne wartości HP i absorb są przekazywane bezpośrednio do natywnych pasków; addon nie odczytuje ich jako liczb ani nie podaje własnych wartości tekstowych. Przy aktywnym znaczniku DoT tarcza zajmuje wąski górny brzeg paska. Dostępność ramki i zgoda klienta na jej rozszerzenie mogą ograniczyć wyświetlanie.

SpellDamageInfo dodaje liczby obrażeń/leczenia do natywnych pasków akcji Blizzarda i linie do tooltipów na podstawie dostępnego opisu czaru. Nakładki na przyciski Bartender4 i ElvUI nie są obsługiwane; linie tooltipów mogą nadal działać. Retail korzysta z kwot z opisu bez dodatkowego doliczania SP/AP według starych wzorów, a finishery uwzględniają bieżący limit combo points zwracany przez API. To szacunki bez gwarancji rzeczywistego trafienia, crita, odporności celu czy pełnego wpływu talentów. Opis lub akcja oznaczona jako tajna może uniemożliwić wyświetlenie liczby. Dokładność dla każdej klasy i specjalizacji wymaga sprawdzenia w grze.

Model odnowień i identyfikatory czarów sprawdzono względem [danych SimulationCraft dla Midnight](https://github.com/simulationcraft/simc/blob/midnight/engine/dbc/generated/sc_spell_data.inc). Ekran ładowania czyści przewidywane obrażenia DoT; ich wartości nie są odtwarzane z ukrytych aur. Natywne ikony rogue pokazują bieżące efekty niezależnie od tego szacunku.

Healthstone i Crimson Vial (Blutrote Phiole) pokazują na action barze liczbę HP odpowiadającą procentowi leczenia z opisu (EN/DE). Dla Crimson Vial jest to całe leczenie przez 4 sekundy, a nie pojedynczy tick. Liczba aktualizuje się po zmianie maksymalnego zdrowia. Gdy gra ukrywa maksymalne HP, przycisk pokazuje procent, np. `20% HP`, zamiast nieaktualnej liczby.

## Co sprawdzić w grze

- **ResourceDing:** dźwięk po osiągnięciu maksimum zasobu, jego ponowne zdobycie po wydaniu, zmiana specjalizacji, formy druida i celu. Zasoby zależą od klasy oraz specjalizacji; mana lub zasób mogą być niedostępne dla kodu w walce.
- **DoTInfo:** nałożyć DoT, odnowić go, przełączyć cel i powtórzyć na dwóch przeciwnikach. Sprawdzić też rzucanie na soft target i mouseover. Przy ukrytym odbiorcy addon powinien pominąć niepewne przypisanie.
- **Ikony rogue:** nałożyć Garrote/Rupture i truciznę, także przez autoatak; sprawdzić czas, stosy i wygaśnięcie przy celu oraz kilku nameplate. Sprawdzić ukrywanie ikon przez `showMarkers` i `nameplateMode`.
- **ShieldsInfo:** tarcza na graczu i celu, wyczerpanie absorb, grupa/raid oraz tarcza i DoT na wspólnym nameplate. Sprawdzić przy ukrytym HP w walce.
- **SpellDamageInfo:** zwykłe czary i finishery, tooltip po zmianie talentów/zasobu, makra i zmiana strony paska akcji, wejście/wyjście z walki. Ukryte dane powinny pomijać liczbę, bez błędów Lua.
- **Wygląd:** zgodność znacznika przy ramce celu i nameplate, kilka przeciwników, wejście/wyjście z walki, `/reload`, brak błędów Lua.

Pasek i czaszka DoTInfo przewidują obrażenia na podstawie własnego rzucenia czaru i jego opisu; nie odczytują obrażeń z ukrytych aur ani rzeczywistych ticków. Talenty, odnowienia, haste, modyfikatory obrażeń i ograniczenia tajnych wartości API mogą zmienić wynik. Czaszka jest szacunkiem pozostałych obrażeń względem HP. Natywne ikony rogue działają niezależnie od tego modelu. Wersja 0.9.47-retail powodowała znikanie overlay na nameplate po zmianie rodzica ramki; 0.9.48-retail przywraca wcześniejszego rodzica i dopasowuje geometrię osobno. Położenie i wysokość overlay 0.9.50-retail zostały potwierdzone w grze z Platynatorem. Testy offline sprawdzają kod i zawartość ZIP; nie potwierdzają wszystkich klas, modułów ani wyglądu w Forever.
