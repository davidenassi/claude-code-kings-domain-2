# KING'S DOMAIN — REBIRTH · FASE 0: AUDIT COMPLETO E NUOVA ARCHITETTURA

Data: 28/09/2026 · Base analizzata: pacchetto d'ispezione del 27/09/2026 (commit `638eba1` + 5 file) ricostruito
in `progetto/`. Motore: **Godot 4.7.2** (binario ufficiale `4.7.2.stable.official.ed1daf0bf`).

Il master plan chiede di abbandonare la filosofia **«una sola mappa continua che contiene tutto»** e di passare a
**due scale distinte**: una **MAPPA LOCALE DEL DOMINIO** (dettaglio: costruisco, osservo, vivo) e una **MAPPA GLOBALE
STRATEGICA** (astrazione: esploro, comprendo, espando), con una sola simulazione condivisa.
Questo documento dice che cosa del progetto attuale si tiene, che cosa si trasforma e che cosa si sostituisce, dove
il codice presuppone la mappa unica, com'è fatta la nuova architettura e quali sono i rischi.

---

## 0. Come è stato fatto l'audit (e cosa non si poteva verificare)

| Passo | Esito |
|---|---|
| Ricostruzione del progetto dai cinque file di testo (`1_…txt`–`5_…txt`, riga `FILE:` + numero di righe) | 295 file, stessi percorsi dell'originale, in `progetto/` |
| Dati binari della mappa esclusi dal pacchetto (`height.bin`, `biome.bin`, …, `albedo_far.png`, `canopy.bin`) | **rigenerati** con `tools/worldgen/generate_world.py` + `canopy.py` + `detail_textures.py` (Python 3 + numpy). Le dimensioni compresse di **tutti** i raster coincidono al byte con quelle scritte nel `world_meta.json` originale (es. `height.bin` 5 463 769, `canopy.bin` 726 584): il generatore è deterministico e la mappa è quella ufficiale |
| Atlanti degli sprite (edifici, oggetti, vegetazione, montagne, persone) | rigenerati con `tools/art/draw_*.py`; i JSON prodotti sono identici a quelli del pacchetto |
| Kit dipinto dell'interfaccia (`assets/ui/kit/*.png`, `assets/ui/icons/*.png`) | **non ricostruibile**: nasce da `art_source/ui/sheet*.png`, esclusi dal pacchetto. L'interfaccia ricade sui `StyleBoxFlat` (previsto dal codice: `KDTheme`), quindi le schermate di questo ambiente hanno cornici più semplici di quelle del giocatore |
| Salvataggi di prova (`tests/fixtures/saves/phase18_*.kdsave`) e mondi delle foto (`tests/output/world_saves/`) | esclusi dal pacchetto: i test che li aprono lo segnalano (vedi §0.1) |
| Import del progetto in Godot 4.7.2 headless | nessun errore di script |
| Suite di test headless (`tests/test_runner.tscn`) | vedi §0.1 |
| Schermate | Xvfb + OpenGL software (llvmpipe, `--rendering-driver opengl3`): funzionano, ma a 5–10 fps. Le misure di prestazione vanno ripetute su una GPU vera (RTX 3060 del progetto) |

Strumenti non disponibili in questo ambiente: **Blender** (la pipeline 3D → prerender resta possibile sulla macchina
del progetto, non qui), la GPU. Entrambi sono dichiarati dove contano (Fase 12).

### 0.1 Base di partenza misurata

- Codice: **23 834 righe** di GDScript nel gioco, **6 149** nei test; 21 file JSON di definizione + 10 di bilanciamento.
- **210 test** automatici in 26 file (`tests/unit/`), più campagne lunghe e test di carico.
- Mondo: 112 × 72 km, **395 province**, 192 fiumi (973 km), 13 laghi, 6 regni formati + 10 signorie + terre libere.
- 15 edifici, 8 tecnologie (4 rami × 2 strade), 13 modalità mappa.
- Risultato della suite sulla base ricostruita: riportato in `KINGSDOMAIN_REBIRTH_REPORT.md` (Fase 0, sezione «Base»).

Schermate BEFORE (stesso punto di partenza della nuova partita, 2 marzo 1230): `tests/output/before/`
- `b01_spawn.png` (0,35 m/px), `b07_zoom_close.png` (0,12), `b08_zoom_medium.png` (2), `b09_zoom_far_local.png` (8),
  `b10_global_strategic.png` (14), `b10b_continent.png` (62).

Cosa mostrano, in breve: il «dominio» è un punto dentro un continente già tutto visibile; da vicino un prato verde
uniforme con alberi seminati in modo regolare; fiume a larghezza costante con rive lisce; due capanne e sei figure
nel vuoto; a 8 m/px il bosco è una moquette di cespi; zoomando indietro si arriva senza soluzione di continuità al
continente con tutti i regni già noti. È esattamente la diagnosi del master plan.

---

## 1. Le assunzioni della «mappa unica» nel codice

Ogni voce è un punto che **si rompe** o che **va deciso** quando le scale diventano due.

| # | Assunzione | Dove | Conseguenza per il Rebirth |
|---|---|---|---|
| A1 | Principio architetturale «un mondo, un orologio, **un sistema di coordinate**» | `TECHNICAL_ARCHITECTURE.md` §1.1, `GAME_DESIGN_MAP.md` §1 pilastro 1 («Nessun cambio di scena») e §4 («Zoom continuo») | Va riscritto: **un mondo e un orologio, due spazi di coordinate** (globale e locale) con una regola di corrispondenza |
| A2 | Una sola camera per tutto, da 0,04 a 80 m/px, limitata al continente | `map/camera/world_camera.gd:12-17`, `scenes/main.gd` (`camera.world_bounds = Rect2(Vector2.ZERO, WorldConstants.world_size())`) | Due camere con limiti propri; la locale non può mai superare la scala della valle |
| A3 | Una sola scena con **tutti** i livelli (terreno, fiumi, montagne, vegetazione, edifici, persone, eserciti, confini, selezione, costruzione) sotto un solo `WorldView` | `scenes/main.tscn` | Due viste separate, ognuna con i suoi livelli |
| A4 | Insediamento, edifici e persone vivono in **metri del continente** | `SettlementState.center`, `BuildingState.pos/a/b`, `PersonState.seg_from/seg_to`; scelti da `SettlementSetup.choose_site` sul raster globale | Spazio locale proprio del dominio; conversione verso la mappa globale solo dove serve |
| A5 | Il «dettaglio locale» (alberi, rocce, pendenze, acqua) è **derivato dai raster del continente a 64/32 m** | `world/local/local_features.gd:78` (`cell_feature` legge `canopy`, `biome`, `water` del mondo), `Placement` (`height_at` a 64 m) | La qualità della valle è limitata dalla risoluzione del continente: **impossibile** una valle disegnata con rive, radure e affioramenti veri. Serve un dato locale ad alta risoluzione (`DomainData`) |
| A6 | Il regime della simulazione (ora per ora / aggregato) cambia con lo **zoom della camera** | `map/settlement/settlement_layer.gd:16,86` (`OBSERVED_MPP = 22` → `SettlementSim.set_observed`) | Il regime segue la **vista attiva** (locale = osservato, globale = aggregato), non lo zoom |
| A7 | Gli insediamenti restano visibili fino a 40 m/px come blocchi, la vegetazione come icone fino a 22 m/px | `map/settlement/settlement_marks.gd`, `data/defs/vegetation.json` (bande `mid`/`map`) | Sulla mappa globale: **nessuna casa, nessun campo**, solo il simbolo della città; sulla locale: niente bande «da carta» |
| A8 | Un clic seleziona un edificio sotto 14 m/px, altrimenti una provincia | `map/map_interaction.gd:9,78,126` | Interazione locale (edifici, costruzione) e globale (province, eserciti) separate |
| A9 | Eserciti e insediamento confrontano posizioni nello **stesso spazio** | `military/military.gd:172,195` (rifornimento e visibilità), `military/systems/military_system.gd:91,97` (la schiera nasce a `s.center + (140, 90)`), `military/commands/disband_army_command.gd:31,49` | Serve la posizione **globale** dell'insediamento (`Domain.global_pos_of`) |
| A10 | Le notifiche portano una `world_pos` senza dire in quale spazio | `core/event_bus.gd:17` (`notification(..., world_pos)`), 74 chiamate a `EventBus.notify` | La notifica deve sapere se il luogo è nella valle o nel mondo (per «portami là») |
| A11 | Minimappa del **continente** mentre si costruisce il villaggio | `ui/map/minimap.gd` | Minimappa della valle in locale, del continente in globale |
| A12 | Nomi dei regni, stemmi e confini disegnati mentre si guarda il villaggio | `map/labels/map_labels.gd`, `map/borders/*` | Solo sulla mappa globale |
| A13 | Uno shader del terreno fa sia la strada del villaggio sia l'albedo del continente | `shaders/terrain.gdshader` (`far_start`/`far_end` 9–26 m/px) | Globale: albedo illustrato. Locale: un terreno proprio ad alta risoluzione (Fase 12) |
| A14 | **Tutti i regni si conoscono dal primo giorno** | `diplomacy/diplomacy.gd:45` (`found_relations` su ogni coppia), minimappa e mappa politica complete | Fase 8: livelli di conoscenza (SCONOSCIUTO → VOCI → CONOSCIUTO → CONTATTO → ESPLORATO) |
| A15 | La posizione di partenza è **una sola** (valle di frontiera fissa, decisione D2) | `data/defs/start_setup.json` → `player`, `kingdoms/start_setup.gd:pick_player_province` | Fase 11: più regni giocabili, ognuno con la propria patria |
| A16 | Strumenti e prove parlano in metri del continente | `core/boot/boot_args.gd` (`--kd-camera=x,y,mpp`, `home,dx,dy,mpp`), benchmark di `main.gd` (volo da 60 a 0,25 m/px) | Argomenti di camera per vista (`--kd-view=local|global`) |
| A17 | Il nome e lo stemma della comunità sono etichette del **continente** (segnaposto sopra l'abitato fino a 40 m/px) | `map/labels/map_labels.gd` (`built_radius`) | In globale la capitale è un simbolo; in locale il nome è del luogo |
| A18 | `WorldConstants.world_size()` usato come «il mondo» anche per la camera del villaggio | `world/world_constants.gd`, `scenes/main.gd` | Vale solo per lo spazio globale |

Buona notizia emersa dall'analisi — **una sola eccezione alla mappa unica è già vera**: nessun regno dell'IA ha un
insediamento fisico. `WorldState.settlements` contiene soltanto gli insediamenti creati da `SettlementSetup`, cioè
quello del giocatore (verificato: nessun altro punto del codice crea un `SettlementState`). I regni dell'IA vivono
già come **province aggregate** (popolazione, sviluppo, leve che escono dalla popolazione). Quindi la separazione
«dettaglio del giocatore» / «astrazione del mondo» esiste già nella simulazione: manca nello **spazio**, nella
**presentazione** e nell'**interazione**.

---

## 2. Classificazione sistema per sistema

Legenda: **KEEP** tenere com'è · **REFACTOR** tenere la logica, cambiare dove vive o come è collegato ·
**REPLACE** rifare · **REMOVE** togliere · **MIGRATE** portare i dati/salvataggi nel nuovo formato.
La colonna «Fase» indica quando il lavoro avviene nel master plan.

### 2.1 Nucleo

| Sistema | File | Verdetto | Motivo | Fase |
|---|---|---|---|---|
| Autoload `Defs`, dati JSON tipizzati | `core/defs/*`, `data/defs/*` | **KEEP** | Solido, validato, testato | — |
| `EventBus` | `core/event_bus.gd` | **REFACTOR** | La notifica deve portare lo spazio del luogo (A10) | 1 |
| Calendario, orologio, scheduler, sistemi | `core/time/*`, `core/simulation/*` | **KEEP** | Un orologio solo resta giusto per due mappe | — |
| RNG a flussi, modificatori, comandi | `core/kd_rng.gd`, `core/modifiers/*`, `core/commands/*` | **KEEP** | Indipendenti dalla mappa | — |
| `GameSession` / `Session` | `core/session/*` | **REFACTOR** (leggero) | La sessione non ha nodi: le due mappe la condividono già. Va aggiunto il dominio (fondazione, caricamento) | 1 |
| Argomenti di avvio | `core/boot/boot_args.gd` | **REFACTOR** | Camera per vista (A16) | 1 |
| Input | `core/input/input_setup.gd` | **REFACTOR** | Nuova azione «cambia mappa» | 1 |

### 2.2 Stato del mondo e dati statici

| Sistema | File | Verdetto | Motivo | Fase |
|---|---|---|---|---|
| `WorldState` (radice salvata) | `world/world_state.gd` | **REFACTOR** | Resta la radice unica (coerenza del salvataggio), con due sotto-parti: il **mondo globale** (province, regni, relazioni, eserciti, guerre, cronaca) e il **dominio locale** (`DomainState`: descrittore della patria, insediamenti, edifici, persone, famiglie, delta del terreno) | 1 |
| `WorldData` (continente) | `world/data/world_data.gd` | **KEEP** come dati della mappa globale; **REFACTOR** per diventare la base di `DomainData` (stessa interfaccia di interrogazione) | 1 |
| `WorldConstants` | `world/world_constants.gd` | **REFACTOR** | Solo spazio globale | 1 |
| Alberi e affioramenti | `world/local/local_features.gd` | **REFACTOR** (Fase 1: legge i dati del dominio) → **REPLACE** delle regole (Fasi 2, 7, 12: masse forestali, affioramenti ovunque ci sia roccia) | 1, 2, 7, 12 |
| Delta del terreno | `world/local/terrain_deltas.gd` | **KEEP** (passa sotto il dominio) | 1 |
| Crescita delle province | `world/systems/province_growth_system.gd` | **KEEP** | Già globale e aggregata | — |
| Geografia delle province | `provinces/*` | **KEEP** | Globale | — |
| Generatore del continente | `tools/worldgen/*` | **KEEP** | La mappa globale resta questa (Fase 9 ne rifà la resa, non i dati) | 9 |
| Generatore delle patrie | — | **NUOVO** (`tools/domaingen/` o generatore in gioco deterministico) | Serve una valle finita ad alta risoluzione con confini naturali | 2, 11 |

### 2.3 Insediamento, popolazione, economia (la simulazione locale)

| Sistema | File | Verdetto | Motivo | Fase |
|---|---|---|---|---|
| Simulazione ora per ora | `settlement/settlement_sim.gd` | **REFACTOR** | La logica (azioni, alberi veri, cantieri, forno, mietitura) è il cuore del gioco locale e resta. Cambia la fonte dei dati del terreno (dominio) | 1 |
| Simulazione aggregata | `settlement/settlement_aggregate.gd` | **KEEP** + REFACTOR dati | Diventa il regime usato quando si guarda la mappa globale | 1 |
| Piazzamento | `settlement/placement.gd` | **REFACTOR** (Fase 1: dati del dominio) → **REPLACE** della logica di scelta (Fase 4: il giocatore sceglie *cosa* e *area*, il gioco rifinisce posizione, orientamento, accesso) | 1, 4 |
| Pianificatore | `settlement/settlement_planner.gd` | **REFACTOR** | Le sue zone (piazza, distretto agricolo, taglialegna verso il bosco) sono la base della crescita organica | 4 |
| Fondazione dei sei | `settlement/settlement_setup.gd` | **REFACTOR** | Sei fondatori 3+3 già giusti; nasce il **nucleo della comunità** (focolare, rifugio, deposito, punto d'acqua, piazzola) | 3 |
| Popolazione, famiglie | `settlement/systems/*`, `settlement/*_state.gd` | **KEEP** | Indipendenti dalla mappa | — |
| Economia della corona | `economy/*` | **KEEP** + REFACTOR (commercio che compensa risorse scarse) | 10 |
| Quartieri / aggregazione urbana | — | **NUOVO** | 2 000 case non possono essere 2 000 edifici | 5 |

### 2.4 Politica, mondo, guerra (la simulazione globale)

| Sistema | File | Verdetto | Motivo | Fase |
|---|---|---|---|---|
| Situazione iniziale | `kingdoms/start_setup.gd`, `data/defs/start_setup.json` | **REFACTOR** | La patria del giocatore diventa una scelta fra regni giocabili | 11 |
| Corte, leggi, editti, spiriti, cultura, obiettivi, stemmi | `kingdoms/*` | **KEEP** | Già consolidati (4 spiriti al massimo, misure uniche) | 13 (solo presentazione) |
| Fondazione della monarchia | `kingdoms/commands/found_monarchy_command.gd`, `CourtSystem.monarchy_conditions` | **KEEP** + legame fisico con il castello | 6 |
| Diplomazia | `diplomacy/*` | **REFACTOR** | Nessun regno noto al primo giorno (A14) | 8 |
| Eserciti | `military/*` | **REFACTOR** | Entità globali; la leva nasce nella patria e appare sulla mappa globale alla posizione della capitale (A9) | 1, 10 |
| Guerre, battaglie, assedi | `war/*` | **KEEP** le regole; **REFACTOR** del luogo | Campagne sulla mappa globale, assedio della capitale nella valle | 10 |
| IA dei regni | `ai/realm_ai_system.gd` | **KEEP** | Lavora già su province, tesoro, patti: nessuna dipendenza dalla scala locale | — |
| Eventi, cronaca | `events/*`, `GameSession._write_chronicle` | **KEEP** | — | — |
| Ricerca | `research/*` | **KEEP** (contenuto povero: 8 tecnologie, problema noto #8) | 13 |
| Province come possedimenti | `kingdoms/commands/develop_province_command.gd`, `claim_province_command.gd` | **REFACTOR** → gestione macro (agricoltura, miniera, fortezza, strada, guarnigione, tasse, autonomia) | 10 |

### 2.5 Rendering

| Livello | File | Verdetto | Mappa | Fase |
|---|---|---|---|---|
| `WorldView` (origine mobile) | `map/world_view.gd` | **KEEP** (uno per vista) | entrambe | 1 |
| Camera | `map/camera/world_camera.gd` | **KEEP** la classe, limiti per vista | entrambe | 1 |
| Terreno + shader | `map/terrain/terrain_layer.gd`, `shaders/terrain.gdshader` | **REFACTOR** (accetta qualunque fonte di dati) → **REPLACE** del terreno locale (terra, fango, calpestato, roccia, rilievi) | entrambe | 1, 12 |
| Fiumi + shader | `map/water/river_layer.gd`, `shaders/river.gdshader` | **KEEP** in globale; locale **REPLACE** (rive vere, larghezza variabile, vegetazione, ponti) | entrambe | 1, 12 |
| Oggetti di riva | `map/water/river_bank_props.gd` | **REFACTOR** → solo locale | locale | 1 |
| Montagne | `map/terrain/mountain_layer.gd` | **KEEP** in globale; locale **NUOVO** (i monti che chiudono la valle) | entrambe | 2, 12 |
| Vegetazione | `map/vegetation/vegetation_layer.gd`, `shaders/vegetation.gdshader` | **REFACTOR** (dati e bande per vista) → **REPLACE** della resa locale (foreste come masse: nucleo, margine, radure) | entrambe | 1, 12 |
| Edifici, blocchi da lontano, oggetti, campi | `map/settlement/settlement_layer.gd`, `settlement_marks.gd`, `settlement_props.gd`, `field_painter.gd` | **REFACTOR** → solo locale; **REPLACE** della grafica | locale | 1, 12 |
| Abitanti | `map/settlement/people_layer.gd` | **REFACTOR** → solo locale; **REPLACE** della grafica | locale | 1, 12 |
| Costruzione | `map/settlement/build_controller.gd` | **REFACTOR** → solo locale; **REPLACE** della logica (area generale) | locale | 1, 4 |
| Confini, selezione | `map/borders/*` | **KEEP** → solo globale | globale | 1 |
| Nomi e stemmi | `map/labels/map_labels.gd` | **KEEP** → solo globale; gerarchia tipografica rifatta | globale | 1, 9 |
| Modalità mappa | `map/political/*` | **KEEP** → solo globale | globale | 1 |
| Eserciti | `map/military/army_layer.gd` | **REFACTOR** (stendardi in globale; soldati nella valle quando l'esercito è nella patria) | entrambe | 1, 10 |
| Interazione | `map/map_interaction.gd` | **REPLACE** con interazione locale + globale | entrambe | 1 |
| Nebbia ai margini della valle | — | **NUOVO** | locale | 1 (margine), 8 (nebbia vera) |

### 2.6 Interfaccia

| Sistema | File | Verdetto | Motivo | Fase |
|---|---|---|---|---|
| Montatore della HUD | `ui/settlement/settlement_hud.gd` | **REFACTOR** | Sa quale mappa è attiva: in globale niente costruzioni, ispettore di provincia; in locale ispettore dell'edificio | 1 |
| Minimappa | `ui/map/minimap.gd` | **REFACTOR** | Valle in locale, continente in globale (A11); il titolo «Mappa del mondo» diventa il passaggio alla mappa globale | 1 |
| Ispettore di provincia | `ui/map/province_inspector.gd` | **KEEP** → solo globale | — | 1 |
| Riquadro di debug visibile a chi gioca | `ui/debug/debug_overlay.gd` | **REFACTOR** → nascosto di default (F3) | Problema noto #1 | 1 |
| Barra alta: «Famiglie» fra le misure prima della corona | `ui/shell/top_bar.gd` | **REMOVE** l'indicatore | Problema noto #3, e Fase 13 (le famiglie sono nei Ceti) | 13 |
| Oro al mese diverso fra barra ed Economia | `ui/shell/top_bar.gd` | **REFACTOR** (bug) | Problema noto #2 | 13 |
| Schede (Regno, Ceti, Corte, Governo, Economia, Ricerca, Diplomazia, Esercito, Religione, Cronaca) | `ui/kingdom/*`, `ui/*` | **KEEP** i contenuti → **REPLACE** della presentazione (card, icone, barre, progressive disclosure) | Fase 13, dopo le mappe | 13 |
| Menu, pausa, catalogo dei salvataggi | `ui/menu/*`, `save/save_catalogue.gd` | **KEEP** (+ scelta del regno in Fase 11) | — | 11 |

### 2.7 Salvataggi, test, strumenti

| Sistema | File | Verdetto | Motivo | Fase |
|---|---|---|---|---|
| Salvataggio | `save/save_system.gd` | **KEEP** (formato JSON ZSTD, scrittura atomica) | — | — |
| Migrazione | `save/save_migrator.gd` | **MIGRATE**: versione 7 con il dominio | Vedi §3.7 | 1 |
| Suite di test | `tests/*` | **KEEP** + **REFACTOR** dei test che usano coordinate del continente per l'insediamento | 1 |
| Scenari di prova in `main.gd` (village, war, kingdom_grown, stress…) | `scenes/main.gd` | **REFACTOR**: spostati in un file loro (`scenes/scenarios.gd`), la scena principale torna a fare solo la scena | 1 |
| `tools/check.ps1` | — | **KEEP** + nuovo `tools/check.sh` (Linux/CI) | 0 |

### 2.8 Da togliere

- **REMOVE** il volo del benchmark «dal continente alla strada» come unico percorso: due benchmark, uno per vista.
- **REMOVE** dalla mappa locale: `BorderLayer`, `SelectionLayer`, `MapLabels` dei regni, `MapModeController`,
  `MountainLayer` del continente, bande di vegetazione «da carta».
- **REMOVE** dalla mappa globale: `SettlementLayer`, `SettlementMarks`, `SettlementProps`, `PeopleLayer`,
  `BuildController`, `RiverBankProps`, banda «close» degli alberi.
- **REMOVE** (Fase 13) le statistiche doppie residue in cima allo schermo (Famiglie) — le misure sono già state
  compresse a Prestigio, Legittimità, Stabilità, Fiducia (+ Autorità prima della corona) dal consolidamento: il
  master plan su questo punto è già quasi rispettato.

---

## 3. La nuova architettura

### 3.1 Principio

> **Un mondo, un orologio, due spazi.** La simulazione è una sola (`GameSession`, senza nodi, headless);
> le mappe sono due *rappresentazioni* della stessa storia, con dati, camera, livelli e interazioni propri.

```
GAME STATE  (GameSession → WorldState, un solo salvataggio)
├── GLOBAL WORLD            spazio: metri del continente (0..112 000 × 0..72 000)
│   ├── dati statici:  WorldData  (raster 64/32 m, 395 province, confini, fiumi, montagne)
│   ├── province[]     proprietario, controllo, popolazione aggregata, sviluppo, devastazione
│   ├── regni[]        rango, casa, capitale (id di provincia), misure, leggi, spiriti, tesoro
│   ├── relazioni{}    opinioni, patti, guerre, tregue, ricordi      (+ conoscenza, Fase 8)
│   ├── eserciti[], battaglie[], assedi[]    posizioni in metri del continente
│   └── cronaca, eventi, offerte
└── LOCAL DOMAIN            spazio: metri della valle (0..L × 0..H)
    ├── descrittore:   DomainState {sorgente, provincia di casa, rettangolo, ancora globale, seme}
    ├── dati statici:  DomainData (stessa interfaccia di WorldData, risoluzione propria)
    ├── insediamenti[] (oggi uno: la comunità del giocatore)
    ├── edifici{}, persone{}, famiglie{}
    └── delta del terreno (alberi abbattuti, rocce cavate)
```

Nel codice `WorldState` resta **la radice unica**: province, regni, eserciti accanto a insediamenti, edifici e
persone — nessun sistema viene riscritto per leggere da due radici. La separazione è di **spazio e di dati**:
- `WorldState.domain: DomainState` descrive la patria; tutte le posizioni di insediamenti, edifici e persone sono
  **locali** a quel dominio.
- `DomainData.of(world)` dà i dati del terreno locale (alberi, acqua, pendenze, depositi) nello spazio locale.
- `WorldData.get_instance()` resta il continente, e lo usano solo i sistemi globali.

### 3.2 I due spazi e la loro corrispondenza

| | Spazio globale | Spazio locale |
|---|---|---|
| Unità | metro | metro |
| Estensione | continente 112 × 72 km | patria finita, ~8 × 6 km (vedi §3.4) |
| Chi ci vive | province, regni, eserciti, battaglie, assedi | insediamenti, edifici, persone, alberi, rocce, campi |
| Dati del terreno | `WorldData` (64/32 m) | `DomainData` (Fase 1: 64/32 m ritagliati; Fase 2: ~4 m) |
| Camera | 6 – 80 m/px | 0,05 – ~5 m/px (tutta la valle, mai il continente) |

Corrispondenza (una sola regola, in `DomainState`):
- `to_global(p_locale)` → punto del continente. Il dominio sta **dentro la provincia di casa**: la capitale sulla
  mappa globale è `anchor_global`.
- Tutto ciò che il mondo globale chiede alla patria (dove nasce una schiera, dove si rifornisce, quanto vede la
  capitale, dove disegnare il simbolo della città) passa da `DomainState.global_pos_of(settlement)`.
- Un esercito globale che entra nella **provincia di casa** può essere mostrato nella valle (Fase 10) con
  `to_local`: la valle è la provincia di casa vista da vicino.

### 3.3 Regimi di simulazione

| Vista attiva | Insediamento del giocatore | Resto del mondo |
|---|---|---|
| Mappa locale | **ora per ora** (`SettlementSim`), persone visibili | aggregato (come oggi) |
| Mappa globale | **aggregato** (`SettlementAggregate`, stesse regole fisiche) | aggregato |

Il principio «la camera non cambia l'esito» resta vero (le due forme sono già tenute uguali dai test). Cambia solo
**chi** decide il regime: la vista attiva, non lo zoom (A6).

### 3.4 La scala della patria

- Un borgo medievale di mille abitanti occupa ~0,3–0,5 km²; una capitale di diecimila 1,5–3 km² con le mura; i
  campi che la nutrono ne occupano molte volte tanto. Una valle di **~8 × 6 km (≈ 50 km²)** tiene una capitale grande
  con il suo contado, i boschi, le cave e i margini selvaggi, e resta **finita** a colpo d'occhio.
- Con 1920 px di larghezza l'intera valle si vede a ~4,5 m/px: è lo «ZOOM LONTANO LOCALE» della reference A.
  Lo «ZOOM MEDIO» (reference B) è ~1–2 m/px, lo «ZOOM VICINO» (C, D) 0,08–0,3 m/px.
- Misure scelte: dominio **8 064 × 6 144 m** (multipli di 192 m = mcm fra la griglia degli alberi, 12 m, e le celle
  dei raster, 64 m: il ritaglio della Fase 1 è allineato esattamente e gli alberi restano gli stessi).
- La città **non cresce all'infinito**: il limite fisico è la valle; oltre, la crescita diventa densità (quartieri,
  Fase 5) e province possedute sulla mappa globale (Fase 10).

### 3.5 Scene

```
scenes/menu.tscn                         (invariato: porta del gioco)
scenes/main.tscn   Main (Node)           guscio della partita: sessione, orologio, HUD, passaggio fra le mappe
 ├── SimulationRunner
 ├── LocalView    (scenes/local/local_view.tscn)     mappa locale del dominio
 │    ├── WorldView → Terrain, Rivers, RiverBankProps, Vegetation, Settlement, Marks, Props, People,
 │    │               DomainEdge (margini), BuildController
 │    ├── WorldCamera (limiti della valle)
 │    └── LocalInteraction (edifici, costruzione)
 ├── GlobalView   (scenes/global/global_view.tscn)   mappa strategica
 │    ├── WorldView → Terrain(albedo), Rivers, Mountains, Vegetation(bande lontane), Borders, Selection, Armies
 │    ├── WorldCamera (limiti del continente, mai sotto la scala delle case)
 │    ├── MapModeController, GlobalInteraction (province, eserciti, ordini)
 │    └── MapHud (nomi, stemmi, simbolo della capitale)
 ├── SettlementHud (una HUD, sa quale mappa è attiva)
 └── DebugOverlay (F3, nascosto di default)
```

- Le due viste sono **scene distinte** (si possono aprire da sole nei test) e **mai attive insieme**: quella
  spenta è nascosta e con `PROCESS_MODE_DISABLED`. La vista globale si costruisce la prima volta che si apre
  (carica i raster del continente), poi resta pronta: il passaggio è istantaneo.
- Passaggio: **Tab**, il pulsante «Mappa del mondo» della minimappa, il pulsante «Torna al dominio» e un doppio clic
  sulla capitale nella mappa globale. **Nessuno zoom** porta da una mappa all'altra.

### 3.6 Interazioni

| | Locale | Globale |
|---|---|---|
| Clic sinistro | edificio (ispettore), luogo di costruzione | provincia (ispettore), esercito |
| Costruzioni | sì | no (il pulsante riporta al dominio) |
| Ordini agli eserciti | no (Fase 10: difesa della patria) | sì |
| Modalità mappa | no (Fase 7: velo delle risorse della valle) | sì |
| Notifica «portami là» | se il luogo è nella valle | se il luogo è nel mondo; cambia mappa se serve |

### 3.7 Salvataggi (versione 7)

- `world.domain` (nuovo): `{source, home_province, rect, origin_global, anchor_global, seed, homeland}`.
- Le posizioni di insediamenti, edifici, persone e le chiavi degli alberi abbattuti sono **locali** al dominio.
- **Migrazione v6 → v7 (esatta)**: un salvataggio della mappa unica ha l'insediamento in metri del continente.
  La migrazione crea un dominio di tipo **ritaglio** (`source = "continent_crop"`) centrato sull'insediamento
  (origine allineata a 192 m) e trasla edifici, persone, strade e chiavi degli alberi (`gx:gy` → `gx−ox:gy−oy`).
  Poiché nel ritaglio gli alberi si calcolano con lo stesso hash del continente (scarto di griglia), sono
  **gli stessi alberi**: nessun albero riappare, nessun ceppo si perde. I vecchi salvataggi continuano a vivere
  nella loro valle ritagliata dal continente.
- Le **nuove partite** (dalla Fase 2) useranno una patria generata (`source = "homeland"`). Un vecchio salvataggio
  **non** può essere spostato in una patria nuova: la sua geografia è un'altra (edifici in un lago, campi su un
  monte). Questo limite è dichiarato e voluto.

### 3.8 Che cosa **non** cambia

- Nessun sistema di regole (economia, famiglie, corte, diplomazia, guerra, IA, eventi) viene riscritto per la
  separazione: leggono lo stesso `WorldState`.
- Il determinismo (stesso salvataggio → stesso esito) resta la prova di ogni passo.

---

## 4. Rischi tecnici principali

| # | Rischio | Probabilità | Impatto | Mitigazione |
|---|---|---|---|---|
| R1 | Codice che mescola spazi (posizione locale confrontata con una globale) dopo la separazione: bug silenziosi (una schiera «lontana» dalla sua capitale) | alta | medio | Tutti i punti trovati in §1 (A9, A10) passano da `DomainState`; test dedicati che mettono il dominio lontano dall'origine del continente |
| R2 | Migrazione dei salvataggi v6 con alberi e strade | media | alto | Ritaglio allineato a 192 m + scarto di griglia negli hash (§3.7); test di andata e ritorno su un mondo avanzato |
| R3 | Dati locali ad alta risoluzione (Fase 2): memoria e tempo di generazione | media | medio | Valle 8 × 6 km a 4 m = 2016 × 1536 celle (3 M valori per raster, ~12 MB in float): accettabile. Generazione deterministica da seme, cache |
| R4 | Due viste in memoria insieme | bassa | basso | La globale si crea alla prima apertura; livelli pesanti (vegetazione a chunk) già a caricamento pigro |
| R5 | Test esistenti che assumono coordinate del continente per l'insediamento | alta | basso | Aggiornati nella Fase 1 con la stessa semantica (fixture di ritaglio) |
| R6 | La grafica di riferimento (A–E) è di un livello che la pipeline attuale (sprite Python/numpy) non raggiunge | **alta** | **alto** | Vedi §5; Fase 12 inizia con `GRAPHICS_FEASIBILITY.md` |
| R7 | Screenshot e misure di prestazione in questo ambiente (rendering software) | certa | medio | Le schermate servono per confronto visivo; FPS, draw call e VRAM vanno rimisurati su GPU |
| R8 | Kit dipinto dell'interfaccia assente nel pacchetto | certa | basso | Il codice ha già il ripiego; la Fase 13 rifà comunque l'interfaccia |

---

## 5. Il target grafico: che cosa è realistico (anticipo della Fase 12)

Le immagini di riferimento (foresta densa vista dall'alto; mappa strategica dipinta con montagne innevate, deserti,
fiumi e foreste come masse; villaggio illustrato con fiume, ponte in pietra, mulino, campi, mura) hanno tre qualità
che il gioco attuale non ha:

1. **Densità e massa**: la foresta è un tappeto continuo di chiome che si toccano, con ombre proprie e radure nette;
   oggi è un prato con alberi separati.
2. **Materiali**: terreno con terra, erba, roccia e calpestato che si mescolano; acqua con riva, sassi, canneti,
   schiuma; tetti con tegole e coppi. Oggi sono tinte piatte.
3. **Illuminazione coerente**: ombre lunghe dallo stesso sole su alberi, edifici, rilievi.

Valutazione preliminare (da confermare in `GRAPHICS_FEASIBILITY.md`):
- **Godot 4.7 non è il limite.** Un gioco 2D con sprite prerenderizzati, `MultiMesh`, atlanti con mipmap, shader
  del terreno con splatting di 4–6 materiali e un'ombra per sprite regge decine di migliaia di elementi a 60 fps su
  una RTX 3060. La nuova architettura aiuta: la valle è 50 km², non 8 000.
- **Il limite sono gli asset.** Gli sprite di oggi sono disegnati da script numpy (forme geometriche con sfumature):
  non arriveranno mai alla qualità della reference C. Servono sprite **prerenderizzati da modelli 3D** (Blender →
  render in vista 3/4 con luce fissa → atlante) o disegnati a mano. Blender non è disponibile in questo ambiente:
  lo è sulla macchina del progetto (Blender 5.2). Questo va deciso prima della Fase 12 e **non** verrà sostituito in
  silenzio con sprite numpy «un po' migliori».
- **Terreno e foreste** possono salire molto già con shader e generazione (texture procedurali di materiali,
  masse di chiome a strati con ombra propria, margini e radure): è la parte che si può fare qui.

---

## 6. Piano delle fasi sul codice reale

| Fase | Lavoro concreto | Prova di fine fase |
|---|---|---|
| **1** | `DomainState` + `DomainData` (ritaglio del continente, stessi alberi); due viste; camere con limiti; passaggio Tab/pulsanti; HUD consapevole della vista; regime di simulazione dalla vista; eserciti e notifiche con lo spazio giusto; salvataggio v7 + migrazione v6; debug nascosto | Suite verde; test nuovi (separazione, limiti, conversioni, migrazione); schermate locale/globale; nessun zoom che passa dall'una all'altra |
| **2** | Generatore della patria (valle finita ~8 × 6 km a ~4 m: fiume, lago, boschi, colline, affioramenti, monti di confine, 2–3 passaggi); rendering dei monti di confine; Valverde come prima patria | «Sono dentro una vera regione»: schermate lontano/medio/vicino |
| **3** | Nucleo della comunità (focolare, rifugio, deposito, punto d'acqua, piazzola) come luogo riconoscibile | Schermata del primo giorno |
| 4–6 | Crescita organica, quartieri, castello e capitale | Villaggio 30–50, borgo, capitale |
| 7–8 | Leggibilità delle risorse (pietra e ferro minimi garantiti), nebbia e conoscenza | Prove sulle risorse garantite; mondo che si scopre |
| 9–11 | Mappa globale illustrata, conquista e commercio, regni giocabili con patrie proprie | — |
| 12 | Graphics rebirth (dopo `GRAPHICS_FEASIBILITY.md`) | BEFORE/AFTER |
| 13–14 | Interfaccia semplificata, prestazioni, migrazione, rapporto finale | `KINGSDOMAIN_REBIRTH_FINAL_REPORT.md` |

Il diario di ogni fase (cosa è stato fatto, prove, schermate, problemi) è in `KINGSDOMAIN_REBIRTH_REPORT.md`.
