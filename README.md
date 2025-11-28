![Logo](logo.png)

✔✔✔✔✔ Wilga — Pascal canvas helper

Biblioteka Wilga to prosty helper do rysowania na HTML5 Canvas przy użyciu pas2js (Object Pascal → JavaScript).
Nie wymaga instalacji ani dodatkowych pakietów.

✔ Wymagania Wilga
1. pas2js

Potrzebujesz kompilatora pas2js, aby skompilować pliki .pas do .js.

2. Plik rtl.js

To runtime pas2js.
Musi znajdować się w tym samym folderze, co:

index.html

wygenerowany program.js (np. main.js)

W pliku HTML musi być:

<script src="rtl.js"></script>

3. Plik index.html

Również musi być w folderze projektu.
Odpowiada za ładowanie:

rtl.js

Twojego skompilowanego pliku .js

elementu <canvas> do rysowania

✔✔ Przykładowy index.html znajduje się w repozytorium.

4. Pliki Wilgi

Wilga składa się z kilku modułów:

wilga.pas – główny moduł biblioteki

wilga_extras.pas – funkcje dodatkowe

wilga_config.inc – konfiguracja

wilga-render-worker.js

wilga_*.pas – pozostałe moduły Wilgi.

Wszystkie pliki razem tworzą jedną bibliotekę i nie wymagają instalacji.
Wystarczy umieścić je w projekcie lub dodać ich folder do ścieżek kompilatora pas2js.
