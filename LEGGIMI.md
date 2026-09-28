# King's Domain — pacchetto per l'ispezione

**King's Domain** è un gioco strategico-gestionale medievale in 2D, fatto con **Godot 4.7.2** e GDScript tipizzato.
Si parte da una comunità di sei fondatori sulla riva di un fiume e si arriva a un regno su un continente unico,
con province, famiglie, ceti, corte, leggi, ricerca, diplomazia, guerre, eventi e una cronaca. Interfaccia e testi
sono in italiano.

Il pacchetto contiene **tutto il testo del progetto**: codice, scene, shader, dati, test, strumenti e documenti.
Contiene anche le **schermate del gioco attuale** e gli **atlanti degli sprite**. Sono esclusi solo i file pesanti
che non si leggono (vedi in fondo).

## Come usarlo con un'AI

- **Se l'AI accetta uno zip o una cartella:** dai `ISPEZIONE_AI.zip`. La cartella `progetto/` riproduce il
  progetto con i percorsi originali.
- **Se l'AI accetta solo file singoli:** i file `1_…txt`–`5_…txt` contengono gli stessi file uno dopo l'altro, ognuno
  preceduto da una riga `FILE: percorso`. Conviene partire da `1_documenti.txt` e aggiungere solo le parti che
  servono.
- **Per la grafica e l'interfaccia:** le foto in `foto/` (1600×900, la finestra predefinita del gioco).

## Da dove partire

1. `README.md`, poi `GAME_DESIGN_MAP.md` (che cos'è il gioco), `TECHNICAL_ARCHITECTURE.md` (come è costruito),
   `DEVELOPMENT_STATUS.md` (tutte le fasi fatte, con le decisioni).
2. Le ultime passate: `SYSTEM_CONSOLIDATION_REPORT.md` (compressione dei sistemi), `WORLD_ART_REPORT.md` (grafica
   del mondo), `ROBUSTNESS_REPORT.md` (prestazioni e bug).
3. Il codice parte da `scenes/menu.tscn` → `scenes/main.tscn` (`scenes/main.gd`). Gli autoload sono
   `core/defs/defs.gd` (definizioni dai JSON), `core/event_bus.gd` (segnali), `core/session/session.gd` (partita).

## Le cartelle

| Cartella | Contenuto |
|---|---|
| `core/` | avvio, sessione di gioco, scheduler e orologio della simulazione, comandi, modificatori, input |
| `world/`, `provinces/` | stato del mondo, dati statici della mappa, terreno locale, crescita delle province |
| `settlement/` | insediamenti, edifici, abitanti, famiglie, piazzamento, pianificatore del villaggio |
| `economy/`, `research/` | economia della corona e ricerca |
| `kingdoms/` | regni, corte, leggi, ceti (fazioni), spiriti nazionali, fondazione della monarchia |
| `culture/`, `religion/` | culture e religioni (valori fissi) |
| `diplomacy/`, `war/`, `military/` | patti, guerre, eserciti e battaglie |
| `events/` | eventi con scelte, crisi, cronaca |
| `ai/` | l'intelligenza dei regni non giocanti |
| `save/` | salvataggi e migrazione delle versioni (oggi versione 6) |
| `map/` | tutto ciò che si disegna sulla mappa: terreno, acqua, vegetazione, confini, insediamenti, eserciti, camera |
| `shaders/` | terreno, fiumi, vegetazione, confini |
| `ui/` | interfaccia: barra alta, colonne, schede (Regno, Ceti, Corte, Governo, Economia…), menu, notizie |
| `data/defs/` | definizioni di gioco in JSON (edifici, leggi, eventi, tecnologie, unità, bilanciamento…) |
| `data/world/` | la mappa ufficiale (qui solo i JSON; i grandi in forma di esempio) |
| `tests/` | 210 test automatici (`tests/unit/`), campagne lunghe e test di carico |
| `tools/` | `check.ps1` (import, test, schermate), generatore della mappa e degli sprite (Python) |

## Problemi già noti (audit del 27/09/2026, ancora da correggere)

Trovati guardando il gioco attuale, non ancora corretti:

1. **Riquadro di debug visibile a chi gioca:** FPS, zoom e coordinate compaiono in basso a sinistra e coprono la
   minimappa e il tasto Esercito (foto 01).
2. **Oro al mese diverso fra barra ed Economia:** la barra alta dice +192, la scheda Economia +40,4. La barra non
   toglie le paghe dell'esercito (foto 21).
3. **"Famiglie" ancora come indicatore nella barra alta** prima della corona, mentre le famiglie ora vivono dentro i
   Ceti (foto 01, 14).
4. **Titoli di notifica vuoti:** "Fatto" (passo della guida) e "Passata" (fine di una crisi).
5. **ESC:** con un edificio o una provincia selezionati sembra aprire la pausa invece di deselezionare (da provare).
6. **Testo piccolo:** la finestra predefinita 1600×900 rimpicciolisce all'83% un'interfaccia pensata per 1920×1080.
7. **Scheda Esercito:** troppo larga, copre l'orologio e le notizie, e i pulsanti "Arruola" finiscono sotto. La
   schiera elenca "4 lancieri" diciotto volte (foto 25).
8. **Ricerca:** ci sono solo 8 tecnologie. Nella cittadina di prova sono già tutte prese e restano 72.301 punti
   inutilizzabili (foto 22).
9. **Consuetudini** (prima della corona): solo un testo, nessuna scelta (foto 16).
10. **Menu principale e pausa:** il titolo tocca la cornice (foto 12, 13).
11. **Eserciti quasi invisibili** da vicino (foto 29, 30).
12. **Grafica del mondo:**
    - campi tutti della stessa misura, ognuno con la sua casetta;
    - alberi sparsi in modo uniforme sul prato e bosco "a moquette" da vicino;
    - fiume della stessa larghezza ovunque, con rive lisce;
    - villaggio senza un centro chiaro;
    - nomi delle province poco leggibili nello zoom strategico

    (foto 02–08).
13. **Da verificare:** nella lista degli abitanti compaiono per primi gli anziani, fra cui una cavatrice di 78 anni
    (foto 28). La cronaca della cittadina di prova è piena di rinnovi di patti minori, ma quel mondo è stato salvato
    prima del consolidamento (foto 26).

Nessun errore nel registro: 31 schermate e 7 partite fatte girare a velocità massima (menu, pausa, nuova partita,
incoronazione, guerra, cittadina vicina e lontana).

## Note sui mondi delle foto

Le foto usano mondi salvati di prova (`tests/output/world_saves/`, non inclusi perché binari):

- **`d_town`:** cittadina di 287 abitanti nel 1274, regno di Valverde, 15 province;
- **`c_village100`:** villaggio di 91 abitanti nel 1241;
- **`community_ready`:** una comunità cresciuta fino alle condizioni per la corona.

Sono stati creati con versioni precedenti del gioco e aperti con la migrazione dei salvataggi.

## Contenuto di questo pacchetto

Generato il 27/09/2026 20:15 da `tools/make_inspection_pack.ps1`. Ultimo commit: `638eba1 2026-09-27 Windows executable: export notes and ignore the built game` (più 5 file modificati o nuovi non ancora nel commit).

| File | Dimensione |
|---|---|
| `1_documenti.txt` | 371 KB |
| `2_codice_simulazione.txt` | 551 KB |
| `3_codice_mappa_interfaccia.txt` | 436 KB |
| `4_dati_e_test.txt` | 428 KB |
| `5_strumenti.txt` | 270 KB |
| `progetto/` | 295 file |
| `foto/` | 32 schermate JPG |
| `grafica/` | atlanti di edifici, oggetti di scena, vegetazione, persone |

### Le foto

| Foto | Cosa mostra |
|---|---|
| `foto/01_avvio_reale.jpg` | Nuova partita come la vede chi gioca, senza opzioni di prova (in basso a sinistra il riquadro di debug) |
| `foto/02_comunita_iniziale.jpg` | I sei fondatori il primo giorno, 0,35 m/px |
| `foto/03_villaggio_100.jpg` | Villaggio di 91 abitanti (1241), 0,6 m/px |
| `foto/04_villaggio_vicino.jpg` | Lo stesso villaggio da vicino, 0,2 m/px: case, campi, sentieri, abitanti |
| `foto/05_campi.jpg` | Cittadina di 287 abitanti (1274): i campi a ovest del fiume, 0,7 m/px |
| `foto/06_foresta.jpg` | Bosco vicino alla cittadina, 0,8 m/px |
| `foto/07_fiume.jpg` | Il fiume che attraversa la cittadina, 0,35 m/px |
| `foto/08_zoom_strategico.jpg` | Zoom strategico, 12 m/px: province, confini, nomi, eserciti |
| `foto/09_mappa_terreno.jpg` | Modalità mappa Terreno, 12 m/px |
| `foto/10_mappa_risorse.jpg` | Modalità mappa Risorse, 12 m/px |
| `foto/11_continente.jpg` | Il continente, 60 m/px |
| `foto/12_menu_principale.jpg` | Menu principale |
| `foto/13_menu_pausa.jpg` | Menu di pausa in partita |
| `foto/14_scheda_comunita.jpg` | La mia comunità prima della corona, con le condizioni del Regno |
| `foto/15_ceti_prima_della_corona.jpg` | Ceti prima della corona: famiglie per lavoro e scelta della casa reale |
| `foto/16_consuetudini.jpg` | Consuetudini (il Governo prima della corona) |
| `foto/17_scheda_regno.jpg` | Il mio regno: casa reale, crisi, obiettivi |
| `foto/18_ceti_dopo_la_corona.jpg` | Ceti dopo la corona: i cinque poteri con le famiglie di spicco |
| `foto/19_corte.jpg` | Corte: sovrano, legittimità, casata |
| `foto/20_governo.jpg` | Governo: leggi ed editti |
| `foto/21_economia.jpg` | Economia: cosa manca, tesoro, depositi, lavoro |
| `foto/22_ricerca.jpg` | Ricerca |
| `foto/23_diplomazia.jpg` | Diplomazia |
| `foto/24_religione.jpg` | Religione |
| `foto/25_esercito_scheda.jpg` | Scheda Esercito: leva e schiere |
| `foto/26_cronaca.jpg` | Cronaca |
| `foto/27_costruzioni.jpg` | Colonna Costruzioni aperta sulla cittadina |
| `foto/28_abitanti.jpg` | Abitanti: mani ai cantieri e nome per nome |
| `foto/29_esercito_in_campo.jpg` | La prima schiera in campo, 0,3 m/px |
| `foto/30_scenario_guerra.jpg` | Scenario di guerra: la schiera davanti al villaggio, 0,4 m/px |
| `foto/31_evento.jpg` | Carta evento (Un maestro d'armi) sopra il villaggio da vicino, 0,13 m/px |
| `foto/32_dopo_40_giorni.jpg` | Nuova partita dopo 40 giorni |

### JSON grandi ridotti a un esempio

Stessa struttura, solo i primi elementi di ogni lista:

- data/world/borders.json (647 KB) -> data/world/borders.ESEMPIO.json
- data/world/provinces.json (470 KB) -> data/world/provinces.ESEMPIO.json
- data/world/rivers.json (1275 KB) -> data/world/rivers.ESEMPIO.json

### Esclusi

- **Non inclusi:**
  - la cache di Godot (`.godot/`);
  - l'eseguibile `KingsDomain.exe`;
  - le foto storiche e i mondi di prova (`tests/output/`, circa 460 MB);
  - i registri (`logs/`);
  - i file `.uid` e `.import` di Godot.
- **File binari o immagini** (mappa in griglie binarie, texture, fonti grafiche):

  - `art_source/.gdignore` (0 KB)
  - `art_source/ui/sheet1_hud.png` (1704 KB)
  - `art_source/ui/sheet2_icons.png` (1493 KB)
  - `art_source/ui/sheet3_windows.png` (1740 KB)
  - `art_source/ui/sheet4_buttons.png` (2008 KB)
  - `art_source/ui/sheet5_heraldry.png` (1629 KB)
  - `art_source/ui/sheet6_layout_sketch.png` (1437 KB)
  - `assets/buildings/building_atlas.png` (543 KB) - copia in `grafica/`
  - `assets/buildings/props_atlas.png` (28 KB) - copia in `grafica/`
  - `assets/environment/mountains/mountain_atlas.png` (952 KB)
  - `assets/environment/terrain/noise_tile.png` (645 KB)
  - `assets/environment/vegetation/vegetation_atlas.png` (234 KB) - copia in `grafica/`
  - `assets/people/people_atlas.png` (27 KB) - copia in `grafica/`
  - `assets/ui/icons/icon_alert.png` (30 KB)
  - `assets/ui/icons/icon_bakery.png` (49 KB)
  - `assets/ui/icons/icon_beds.png` (32 KB)
  - `assets/ui/icons/icon_book.png` (38 KB)
  - `assets/ui/icons/icon_bread.png` (31 KB)
  - `assets/ui/icons/icon_build.png` (24 KB)
  - `assets/ui/icons/icon_camp.png` (41 KB)
  - `assets/ui/icons/icon_chronicle.png` (45 KB)
  - `assets/ui/icons/icon_clergy.png` (35 KB)
  - `assets/ui/icons/icon_consent.png` (39 KB)
  - `assets/ui/icons/icon_crown.png` (34 KB)
  - `assets/ui/icons/icon_culture.png` (37 KB)
  - `assets/ui/icons/icon_development.png` (33 KB)
  - `assets/ui/icons/icon_diplomacy.png` (25 KB)
  - `assets/ui/icons/icon_fire.png` (36 KB)
  - `assets/ui/icons/icon_gold.png` (30 KB)
  - `assets/ui/icons/icon_grain.png` (29 KB)
  - `assets/ui/icons/icon_growth.png` (24 KB)
  - `assets/ui/icons/icon_house_arms.png` (40 KB)
  - `assets/ui/icons/icon_intrigue.png` (10 KB)
  - `assets/ui/icons/icon_iron.png` (23 KB)
  - `assets/ui/icons/icon_justice.png` (34 KB)
  - `assets/ui/icons/icon_law.png` (39 KB)
  - `assets/ui/icons/icon_lily.png` (30 KB)
  - `assets/ui/icons/icon_mine.png` (61 KB)
  - `assets/ui/icons/icon_people.png` (27 KB)
  - `assets/ui/icons/icon_road.png` (35 KB)
  - `assets/ui/icons/icon_shield.png` (33 KB)
  - `assets/ui/icons/icon_smith.png` (38 KB)
  - `assets/ui/icons/icon_stone.png` (32 KB)
  - `assets/ui/icons/icon_storehouse.png` (14 KB)
  - `assets/ui/icons/icon_trade.png` (59 KB)
  - `assets/ui/icons/icon_treasury.png` (35 KB)
  - `assets/ui/icons/icon_village.png` (13 KB)
  - `assets/ui/icons/icon_war.png` (32 KB)
  - `assets/ui/icons/icon_wood.png` (34 KB)
  - `assets/ui/kit/button.png` (15 KB)
  - `assets/ui/kit/button_blue.png` (13 KB)
  - `assets/ui/kit/button_disabled.png` (15 KB)
  - `assets/ui/kit/button_green.png` (13 KB)
  - `assets/ui/kit/button_hover.png` (17 KB)
  - `assets/ui/kit/button_pressed.png` (18 KB)
  - `assets/ui/kit/button_red.png` (12 KB)
  - `assets/ui/kit/check_off.png` (6 KB)
  - `assets/ui/kit/check_on.png` (6 KB)
  - `assets/ui/kit/close.png` (7 KB)
  - `assets/ui/kit/close_hover.png` (8 KB)
  - `assets/ui/kit/close_pressed.png` (8 KB)
  - `assets/ui/kit/icon_gonfalon_bow.png` (22 KB)
  - `assets/ui/kit/icon_gonfalon_foot.png` (20 KB)
  - `assets/ui/kit/icon_gonfalon_horse.png` (21 KB)
  - `assets/ui/kit/icon_mark_battle.png` (25 KB)
  - `assets/ui/kit/icon_mark_siege.png` (25 KB)
  - `assets/ui/kit/icon_pin_capital.png` (25 KB)
  - `assets/ui/kit/icon_pin_city.png` (23 KB)
  - `assets/ui/kit/icon_pin_town.png` (22 KB)
  - `assets/ui/kit/icon_pin_village.png` (21 KB)
  - `assets/ui/kit/icon_ring_enemy.png` (13 KB)
  - `assets/ui/kit/icon_ring_friend.png` (14 KB)
  - `assets/ui/kit/panel.png` (209 KB)
  - `assets/ui/kit/panel_dark.png` (15 KB)
  - `assets/ui/kit/panel_gold.png` (18 KB)
  - `assets/ui/kit/pill.png` (9 KB)
  - `assets/ui/kit/plate.png` (34 KB)
  - `assets/ui/kit/rule_ornate.png` (21 KB)
  - `assets/ui/kit/section_bar.png` (9 KB)
  - `assets/ui/kit/slot.png` (8 KB)
  - `assets/ui/kit/subsection_bar.png` (9 KB)
  - `assets/ui/kit/window.png` (217 KB)
  - `data/world/albedo_far.png` (9375 KB)
  - `data/world/biome.bin` (76 KB)
  - `data/world/canopy.bin` (710 KB)
  - `data/world/coast.bin` (367 KB)
  - `data/world/forest.bin` (638 KB)
  - `data/world/height.bin` (5336 KB)
  - `data/world/moisture.bin` (374 KB)
  - `data/world/province.bin` (44 KB)
  - `data/world/temperature.bin` (292 KB)
  - `data/world/water.bin` (73 KB)
  - `icon.svg` (1 KB)
  - `tests/fixtures/saves/phase18_town.kdsave` (80 KB)
  - `tests/fixtures/saves/phase18_village30.kdsave` (30 KB)
  - `tools/.gdignore` (0 KB)
  - `tools/inspection/LEGGIMI.md` (6 KB)
