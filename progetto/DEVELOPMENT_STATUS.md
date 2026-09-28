# DEVELOPMENT STATUS

Ultimo aggiornamento: 27/09/2026 — **Fasi 15–19 completate e consolidamento dei sistemi**, prossima Fase 20 (ciclo finale 15 → 20).

## Riepilogo fasi
| Fase | Stato |
|---|---|
| 0 — Analisi | ✅ completata |
| 1 — Fondazione Godot | ✅ completata |
| 2 — Mondo (carta illustrata 2D) | ✅ completata, rivista per la nuova direzione artistica (note sotto) |
| 3 — Province e regni | ✅ completata (note sotto) |
| 4 — Insediamento | ✅ completata (note sotto) |
| 5 — Economia e popolazione | ✅ completata (note sotto) |
| 6 — Cultura, religione, spiriti | ✅ completata (note sotto) |
| 7 — Politica | ✅ completata (note sotto) |
| 8 — Diplomazia e IA | ✅ completata (note sotto) |
| 9 — Esercito | ✅ completata (note sotto) |
| 10 — Guerra | ✅ completata (note sotto) |
| 11 — Eventi e rigiocabilità | ✅ completata (note sotto) |
| 12 — UI | ✅ completata (note sotto) |
| 12.5 — Refactor dell'interfaccia | ✅ completata (note sotto) |
| 13 — Ottimizzazione e bilanciamento | ✅ completata (note sotto) |
| 14 — Rifinitura attorno alla partita | ✅ completata (note sotto) |
| 14B — Visual polish finale | ✅ completata, con lavoro dichiarato aperto (note sotto) |
| 15 — Sei fondatori, il Regno come conquista | ✅ completata (note sotto) |
| 16 — Bilanciamento e campagne complete | ✅ completata (note sotto) |
| 17 — Contenuti e varietà | ✅ completata (note sotto) |
| 18 — Grafica definitiva e HUD | ✅ completata, con lavoro dichiarato aperto (note sotto) |
| 19 — Prestazioni, bug, salvataggi | ✅ completata (note sotto, dettagli in `ROBUSTNESS_REPORT.md`) |
| Consolidamento dei sistemi | ✅ completato (note sotto, dettagli in `SYSTEM_CONSOLIDATION_REPORT.md`) |
| 20 — Audio, rifinitura, release candidate | ⏳ prossima |

Come rigenerare la mappa ufficiale (solo sviluppo):
`"C:\Program Files\Blender Foundation\Blender 5.2\5.2\python\bin\python.exe" tools/worldgen/generate_world.py`
Come rigenerare sprite e piazzamento (stesso interprete Python):
`tools/art/draw_vegetation.py`, `tools/art/draw_mountains.py`, `tools/worldgen/place_mountains.py`;
solo l'albedo lontano: `tools/worldgen/generate_world.py --stages albedo --use-cache`.
Come ricostruire l'eseguibile `KingsDomain.exe` (modelli di esportazione 4.7.2 Windows installati in
`%APPDATA%\Godot\export_templates\4.7.2.stable`, preset locale `export_presets.cfg` con il `.pck` incorporato):
`Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" "KingsDomain.exe"`.
L'eseguibile (~123 MB) e il lanciatore `Gioca a King's Domain.bat` restano fuori da git.

---

## FASE 0 — Analisi ✅
**Completato**
- Analisi completa di `Regno old.zip/Regno.html` (~25.200 righe, ~90 moduli): inventario, numeri di bilanciamento, dipendenze → `LEGACY_SYSTEM_AUDIT.md`.
- Mappa di design → `GAME_DESIGN_MAP.md`; architettura → `TECHNICAL_ARCHITECTURE.md`; piano → `DEVELOPMENT_PLAN.md`.
- Ambiente verificato: Godot 4.7.2 (console), Blender 5.2.1, Python 3.13 + numpy (incluso in Blender), Git 2.55, RTX 3060.
- Riferimenti visivi individuati sul Desktop: mockup "ChatGPT Image 14 set 2026" (HUD + mappa illustrata) e foglio componenti UI dell'8/9.

**Problemi / note**
- La cartella ufficiale era vuota: nessun `project.godot` preesistente. Il progetto è stato creato lì.
- `Desktop/kings_domain` è un vecchio tentativo 3D: non usato, non modificato.
- Decisioni di design prese di default (da confermare): vedi `GAME_DESIGN_MAP.md §17`.

---

## FASE 1 — Fondazione Godot ✅
**Completato**
- Progetto Godot 4.7 (`project.godot`, Forward+, 1920×1080 stretch `canvas_items`), struttura cartelle modulare, `.gitignore`, `.gitattributes`, `.gdignore` per `tools/` e `art_source/`, repository Git.
- Autoload minimi: `Defs` (definizioni), `EventBus` (segnali), `Session` (partita corrente).
- Core:
  - `GameCalendar` (anno 360 giorni, mesi, stagioni, data in italiano, conversioni data↔giorno);
  - `SimClock` (6 velocità da dati, tick per giorno, tetto per frame, velocità di osservazione);
  - `Scheduler` + `SimSystem` + `SimStep` (frequenze TICK/DAY/DAY_ROTATING/MONTH/YEAR, rotazione a bucket, profiling);
  - `KDRng` (stream nominati deterministici, serializzabili, `hash01` stabile);
  - `Modifier` / `ModifierStack` (fonti nominate, cache, scomposizione per tooltip, polarità da dati);
  - `Command` / `CommandResult` / `CommandProcessor` (validazione con motivo, storico);
  - `KDLog`, `InputSetup`, `BootArgs`.
- Data layer: `KDDef` + classi tipizzate `ResourceDef`, `TerrainTypeDef`, `CultureDef`, `ReligionDef`; JSON in `data/defs/`
  (risorse, terreni locali, 6 culture e 4 religioni con modificatori fissi bozza), `balance/time.json`, `balance/modifier_keys.json`.
- `WorldState` (radice serializzabile), `GameSession` (nuova partita / avanzamento per tempo reale o per giorni), `SystemRegistry`, `TimeSignalsSystem`.
- Salvataggi: `SaveSystem` (JSON compresso ZSTD in `user://saves/*.kds`, intestazione con `save_version`) + `SaveMigrator` (catena di migrazioni).
- Scena `main.tscn`: `WorldCamera` (zoom continuo in m/pixel verso il cursore, pan tastiera/trascinamento, limiti), `SimulationRunner` (velocità, F5/F9), `DebugOverlay` (F3, data, velocità, FPS, zoom, notifiche).
- Terreno segnaposto (solo Fase 1, da sostituire in Fase 2).
- Strumenti: `tools/check.ps1` (import headless + test + screenshot con camera/giorni/velocità da riga di comando), runner di test headless `tests/test_runner.tscn`.

**Verifiche eseguite**
- Import headless senza errori di script.
- 29 test, 411 asserzioni, 0 fallimenti: definizioni, calendario (rollover mesi/anni, inversa), orologio (pausa, velocità, tetto, osservazione), scheduler (frequenze su 2 anni, rotazione settimanale), RNG (determinismo, indipendenza stream, continuazione dopo serializzazione), modificatori, salvataggio (round-trip con continuazione RNG e simulazione, migratore).
- Screenshot: scena avviata a vista continentale (40 m/px) e dopo 400 giorni simulati a 2 m/px ("11 Aprile 1231", corretto).

**Parziale**
- Nessuno per gli obiettivi di fase.

**Da fare (spostato alle fasi successive)**
- Tema UI definitivo (Fase 12); i18n tramite chiavi (i testi sono per ora in italiano diretto nei dati).

---

## FASE 2 — Mondo (carta illustrata 2D) ✅
**Completato**
- `tools/worldgen/` (Python/numpy con l'interprete di Blender): genera la **mappa ufficiale fissa** (seme interno, mai mostrato):
  continente unico 112 × 72 km (≈55% terra) con golfi e penisole guidati da un layout d'autore (`layout.py`); 8 catene montuose
  con passi voluti; idrologia naturale (priority-flood, accumulo, 192 corsi d'acqua ≈970 km con meandri, 13 laghi con rive graduate);
  clima (venti occidentali, ombra pluviometrica, deserto a sud-est); 16 biomi; densità forestale; 395 province irregolari
  (semi Poisson pesati sull'abitabilità, crescita a costo con creste e alcuni grandi fiumi come frontiere, pulizia contiguità);
  culture che si espandono sul grafo delle province (le frontiere seguono spesso montagne e fiumi), religioni con minoranze,
  nomi per cultura, 632 giacimenti (ferro, pietra, oro, sale, argilla, cavalli), confini vettoriali levigati,
  albedo illustrato 3500×2250 per lo zoom lontano, anteprime di controllo.
- `data/world/`: raster compressi + `provinces.json`, `borders.json`, `rivers.json`, `world_meta.json` (committati).
- `tools/worldgen/detail_textures.py`: 11 texture di dettaglio tassellabili + rumore tassellabile.
- `WorldData` (Godot): caricamento in ~100 ms, query puntuali (altitudine bilineare, bioma, foresta, acqua, provincia), texture GPU; `ProvinceGeo`.
- Rendering: `WorldView` con **origine mobile** (precisione a 112 km), `WorldCamera` in coordinate mondo, `TerrainLayer` + `terrain.gdshader`
  (fusione biomi deformata, dettaglio a 3 scale, variazione regionale, rilievo illuminato da NO, roccia/neve per quota e pendenza,
  mare e laghi da distanza con segno con profondità/onde/schiuma, spiagge, albedo illustrato da lontano), `RiverLayer` (nastri vettoriali con larghezza minima a schermo).
- **Pipeline Blender** `art_source/blender/scripts/`: camera ortografica fissa 55°, sole da NO, ombra catturata, correzione impronta a terra
  (stretch 1/sin 55°), rifilatura, atlante con bleed; `build_vegetation.py` → 33 sprite (quercia, faggio, betulla, pino, abete, cipresso,
  ulivo, cespuglio, albero secco, rocce, massi) in `assets/environment/vegetation/`.
- `VegetationLayer`: MultiMesh a chunk in 3 fasce (alberi reali <2,6 m/px; "icone" dense di bosco a zoom strategico), specie per bioma da
  `data/defs/vegetation.json`, rocce su colline/montagne, costruzione progressiva e rilascio dei chunk lontani.
- `BiomeDef` + validazione incrociata biomi/terreni/texture in `Defs`.
- Benchmark `-- --kd-benchmark=N`.

**Verifiche eseguite**
- 39 test (+10 sulla mappa: dimensioni raster, id province, simmetria vicini, connettività via terra, centri nelle proprie province,
  mare ai bordi, montagne alte, culture/religioni/nomi validi e tutte presenti, fiumi nel mondo, texture) — 0 fallimenti.
- Screenshot a 62, 20, 15, 6, 4, 1,5, 1, 0,4 m/px: continente, catene innevate, laghi morbidi, fiumi, foreste illustrate, alberi singoli con ombra.
- Benchmark 25 s su RTX 3060, finestra 1600×900: lontano 83 fps, strategico 80, locale 72, ravvicinato 117; frame peggiore 79 ms durante la costruzione di chunk con camera teletrasportata.

**Revisione grafica (17/09/2026: "semplificare e alleggerire" + riferimento visivo del mockup)**
- Rimossi: pipeline Blender della vegetazione, texture di dettaglio del terreno, onde/schiuma animate. Blender resta solo per
  future silhouette di edifici/unità.
- Terreno: shader semplificato (colori di bioma sfumati con filtro a tenda — niente gradini a 64 m —, grana di carta, rilievo
  accennato, acqua piatta blu con fascia costiera chiara); palette dei biomi e albedo lontano ritarati su toni caldi dipinti
  (pianure verde-oliva, mare blu saturo).
- Vegetazione dipinta in 3/4 (`tools/art/draw_vegetation.py`, atlante 37 sprite): alberi singoli (<2,2 m/px), gruppi di
  alberi (2–9 m/px), gruppi come icone (7,5–40 m/px), dimensione minima a schermo per fascia.
- **Montagne illustrate**: `draw_mountains.py` (12 sprite: colline, picchi, picchi innevati), `place_mountains.py`
  (137 montagne sulla mappa ufficiale), `MountainLayer` (1 MultiMesh, 1 draw call).
- Verifiche: 40 test / 2045 asserzioni / 0 fallimenti (nuovo test: montagne su terra alta, ordinate per y, tutte con sprite);
  screenshot a 70, 20, 5, 4, 1,2 m/px; benchmark 25 s: **media 138 fps**, lontano 137, strategico 138, locale 130,
  ravvicinato 143; frame peggiore 34 ms.

**Parziale / note**
- Montagne: sprite ancora un po' "a cono" e neve leggermente lucida; da raffinare con varianti a cresta allungata.
- Zoom 3–5 m/px nelle aree montane: le montagne sfumano e resta un grigio-roccia uniforme; accettabile per ora.
- Pattern a rombi dell'illuminazione a zoom molto ravvicinato (interpolazione bilineare dell'altitudine a 64 m): da migliorare con campionamento bicubico.
- Gli alberi a zoom ravvicinato non sono ancora ordinati in profondità rispetto a edifici e unità (arriveranno in Fase 4).
- Classificazione dei confini "fiume/montagna" troppo prudente (quasi tutti "land"): da tarare in Fase 3.

---

## FASE 3 — Province e regni ✅
**Decisioni confermate:** D1–D6 (mondo misto, valle di frontiera latina/cattolica, 1 giorno ≈ 4 s a velocità 1, italiano,
ordini senza pausa forzata, inizio 1230).

**Completato**
- Stato: `ProvinceState`, `KingdomState` (rango derivato insediamento/signoria/regno), `WorldState` con province e domini,
  liste di province sincronizzate, `TransferProvinceCommand` + segnale `province_owner_changed`.
- Situazione iniziale da dati (`data/defs/start_setup.json`, `StartSetup`): **Dominio di Valverde** del giocatore
  (provincia latina/cattolica di foresta con fiume e pietra, 7 abitanti, sviluppo 0, nessun vicino organizzato entro
  2 passi); 6 regni formati (Waldmark, Velgrad, Sundara, Kallithea, Qasr Almas, Aurelia — da 8 a 14 province),
  10 signorie (2–4 province), resto terre libere con villaggi (popolazione aggregata da area, fertilità e boschi).
  Crescita simultanea sul grafo con costi geografici e culturali; deterministica.
- Salvataggi: save_version 2 con migrazione da v1.
- Rendering: `BorderLayer` (linee di provincia sfumate per zoom; confini di dominio con linea scura e fascia del
  colore di ciascun proprietario sul proprio lato; larghezza costante a schermo), velatura per modalità mappa nello
  shader del terreno, `SelectionLayer` (contorno dorato + evidenziazione) e hover.
- Modalità mappa (`data/defs/map_modes.json`): Politica, Terreno, Culture, Religioni, Risorse, Sviluppo, Popolazione;
  barra in alto, M per scorrere, F1/F2/F4/F6/F7/F8/F10.
- Etichette: nomi dei regni in maiuscole spaziate con stemma, signorie e dominio del giocatore, nomi delle province a
  zoom regionale; dissolvenze e niente sovrapposizioni.
- Stemmi procedurali (`CoatOfArms`, eredità "Araldica"): forma dello scudo per cultura, regola delle tinte, 8 partizioni,
  8 figure; il campo usa il colore del dominio.
- `ProvinceInspector`: proprietario e stemma, cultura, religione, popolazione e densità, sviluppo, fertilità, boschi,
  altitudine, paesaggio, acque, giacimenti, confini naturali e domini confinanti.
- Argomenti di avvio per verifiche: `--kd-camera=player,<m/px>`, `--kd-select=player|<id>`, `--kd-mapmode=<id>`.
- Tema provvisorio legno/oro/pergamena (`KDTheme`, `KDFonts`), in attesa della Fase 12.

**Verifiche eseguite**
- 53 test, 0 fallimenti. Nuovi (`test_kingdoms`): stato per ogni provincia, valle di partenza (requisiti + zona libera),
  mondo misto nei limiti, domini contigui con capitale, determinismo, nessuna provincia degenere, trasferimento
  (liste, segnale, rifiuto, classificazione dei confini), salvataggio/caricamento e migrazione v1, stemmi
  (determinismo, forme triangolabili), modalità mappa, orientamento dei confini e contorni, ispettore con dati reali.
- Screenshot: politica e culture a 62 m/px, dominio del giocatore selezionato a 22 e 5 m/px.
- Benchmark 25 s: media 138 fps (lontano 135, strategico 138, locale 129, ravvicinato 144), frame peggiore 43 ms.

**Parziale / note**
- La velatura politica non tinge gli alberi: dentro le foreste, a zoom ravvicinato, il dominio si riconosce dai confini.
- Font di sistema serif per nomi e interfaccia; font medievale e tema completo in Fase 12.
- Il rango "Regno" e le promozioni delle signorie arriveranno con istituzioni e legittimità (Fase 7).
- Popolazione delle province lontane per ora statica (stima): la simulazione aggregata arriva in Fase 5.

### Rifinitura visiva della Fase 3 (correzione del 17/09/2026)
Base mantenuta (mappa, province, regni, montagne, map mode, pipeline 2D); miglioramenti graduali verificati con
screenshot prima/dopo a 62, 20 e 5 m/px.
- **Foreste**: nuovo raster visivo `canopy.bin` (`tools/worldgen/canopy.py`) derivato da `forest.bin`: radure, zone fitte
  e rade, bordi irregolari, meno alberi su pendii ripidi e sulle rive. Lo usano sia gli alberi (vicino) sia l'albedo
  (lontano). Chiome più scure nel folto e più chiare ai margini; tono regionale dall'umidità (secco → oliva/ocra,
  umido → verde profondo). `forest.bin` resta il dato ecologico/statistico.
- **Terreno**: regole di colore condivise in `data/defs/map_style.json` fra shader e albedo precalcolato (stessi numeri =
  stesso mondo a ogni zoom): terre secche ocra, bassure umide più verdi, valli più scure e fredde e crinali più chiari
  e caldi (altitudine meno il suo mip sfocato). Foreste lontane con macchie di chiome nei colori degli sprite.
- **Confini**: gerarchia regno > signoria/dominio > provincia (spessori da `RANK_STYLE`); alone chiaro sotto la linea,
  linea nel colore scuro del proprietario (neutra fra due domini), fascia del colore con sfumatura morbida; linee di
  provincia sottili tinte dal proprietario e sfumate a zoom continentale; velatura politica più leggera (0,26).
  Provincia selezionata: contorno scuro + linea dorata + bagliore interno; hover chiaro.
- **Tipografia**: regni in capitali incise spaziate (Perpetua Titling/Castellar), dimensionate sul regno, orientate lungo
  il suo asse principale con un leggero arco e stemma grande; signorie e dominio del giocatore in capitali piccole
  (il dominio con alone dorato); province in serif con doppio contorno di carta. Font di sistema per ora (da sostituire
  con un font distribuibile in Fase 12).
- Hover disattivato negli screenshot automatici.
- Verifiche: 54 test, 0 fallimenti (nuovo: radure e coerenza di `canopy`); benchmark nelle stesse condizioni:
  versione precedente 129 fps medi → rifinita 134 fps medi (lontano 118 → 120, strategico 125 → 133).

**Note**
- Dentro i boschi, a zoom ravvicinato, il colore del dominio resta visibile solo sulle radure e sui confini (scelta voluta).
- Rigenerare dopo modifiche al terreno: `tools/worldgen/canopy.py`, poi `generate_world.py --stages albedo --use-cache`.

---

## FASE 4 — Insediamento ✅

**Completato**
- **Terreno locale reale**: `LocalFeatures` genera in modo deterministico ogni albero, cespuglio e roccia affiorante
  (gli stessi che disegna la mappa); `TerrainDeltas` salva ciò che cambia (alberi abbattuti con ceppo o terreno
  liberato per sempre, cariche di roccia consumate). I ceppi ricrescono dopo 240–480 giorni se nessuno costruisce lì.
- **Insediamento di partenza**: `SettlementSetup` sceglie il sito nella valle (terreno piano e asciutto, acqua entro
  ~200 m, pietra vicina, bosco rado), pianta **mastio** e **riparo**, libera la radura e crea **il re + 6 abitanti**
  con nome, sesso ed età, più le scorte iniziali (legname 150, pietra 90, grano 120, pane 160, oro 200).
- **Edifici** (`data/defs/buildings.json`): casa, pozzo, taglialegna, cava, fattoria, forno, granaio, magazzino, strada.
  Ognuno con impronta in metri, costo, ore-uomo, posti di lavoro, produzione.
- **Piazzamento** (`Placement`) con motivi in chiaro: acqua sotto l'edificio, fuori territorio, terreno troppo ripido,
  spazio occupato, rocce da cavare, nessuna roccia entro il raggio (cava), terra poco fertile (fattoria), materiali
  mancanti. Gli alberi non bloccano: i costruttori li abbattono per primi e il legname entra nelle scorte.
- **Cantieri**: consegna materiali dai depositi, lavoro a ore, edificio che cresce a vista (sprite svelato dal basso,
  impalcature, cumulo di materiali); `CancelSiteCommand` restituisce quanto consegnato.
- **Lavoro degli abitanti** (`SettlementSim`, 1 tick = 1 ora): assegnazione automatica per priorità con quota
  costruttori (Pochi/Giusti/Molti/Tutti), boscaioli che scelgono l'albero più vicino non prenotato, cavatori sulle
  rocce, contadini che seminano e raccolgono secondo la stagione, fornaio che converte grano in pane, trasporti,
  pasti giornalieri (fame che rallenta il lavoro), notte a casa.
- **Strade**: tracciate in due clic, costruite dai costruttori (ore secondo la lunghezza), alberi sul percorso
  abbattuti, chi cammina lungo una strada finita va più svelto.
- **Grafica**: sprite dipinti per edifici (`tools/art/draw_buildings.py`, 16 sprite: mastio con palizzata e stendardo,
  riparo, casa, taglialegna, cava, forno con forno a cupola, granaio su palafitte, magazzino, pozzo, fattoria in tre
  stagioni, cantieri) e per gli abitanti (`tools/art/draw_people.py`, 53 sprite: 7 mestieri × idle/camminata/lavoro/
  trasporto + carichi), ceppi nell'atlante della vegetazione.
- **Interfaccia**: barra delle scorte, menu di costruzione per categorie con costi, anteprima verde/rossa con il
  motivo del rifiuto, ispettore dell'edificio (avanzamento, materiali, lavoratori con +/−, alberi nel raggio,
  annulla cantiere), pannello degli abitanti con mestiere, età, fame e quota costruttori.
- **Salvataggi**: save_version 3 (insediamenti, edifici, persone, delta del terreno) con migrazione dalla 2.
- Argomenti di avvio: `--kd-scenario=village`, `--kd-hours=N`, `--kd-select=building:<id>`, `--kd-camera=settlement,<m/px>`.

**Verifiche eseguite**
- 60 test, 0 fallimenti. Nuovi (`test_settlement`): avvio con re + 6 abitanti e radura libera; motivi di rifiuto del
  piazzamento; **il taglialegna abbatte alberi visibili, il legname entra nelle scorte e una casa sorge sul terreno
  liberato**; salvataggio/caricamento conserva alberi abbattuti ed edifici e prosegue identico; **simulazione di 2 anni**
  (nessuna scorta negativa, tutti i cantieri finiti, fame sotto controllo, cibo nei depositi); strada (rifiuti,
  costruzione, alberi abbattuti, velocità di cammino).
- Screenshot: insediamento iniziale, cantieri in corso, villaggio al lavoro con strada, vista ravvicinata con ispettore.
- Prestazioni: a velocità massima **481 tick/s a 144 fps** con il villaggio a schermo; benchmark di volo 136 fps medi
  (frame peggiore 50 ms), come prima della fase.

**Parziale / note**
- Cammino in linea retta (nessun aggiramento di ostacoli): l'A* con grafo stradale arriva con le carovane (Fase 5).
- Nessun limite di capienza dei depositi e nessuna nascita/morte: sono della Fase 5; per ora il legname si accumula.
- I boscaioli spogliano il raggio di taglio e poi restano fermi: servirà la gestione forestale (Fase 5).
- La velatura politica sfuma sotto i 6 m/px per non tingere il villaggio.
- Il terreno non mostra ancora sentieri battuti né campi arati fuori dalla fattoria (decal di terreno, Fase 5).

---

## FASE 5 — Economia e popolazione ✅

**Completato**
- **Depositi con capienza**: ogni deposito tiene un gruppo di merci (mastio tutto 600, magazzino materiali 400,
  granaio cibo 400). Quando sono pieni i lavoratori si fermano e ciò che arriva in più va perduto, con avviso.
- **Catene complete**: nuove **miniera** (vene di ferro affioranti) e **fabbro** (ferro + legname → armi), oltre a
  grano → pane. Le vene di ferro sono affioramenti veri sulla mappa, come le rocce da cava.
- **Popolazione viva** (`PopulationSystem`): nascite (servono letto libero, consenso e mesi di cibo in dispensa),
  morti per vecchiaia, stenti e miseria, crescita dei bambini fino a 16 anni, **viandanti** che chiedono di restare
  quando il villaggio è prospero, e **consenso** calcolato ogni giorno da fatti reali (cibo, fame, alloggi, servizi,
  lutti recenti, debiti della corona) con la scomposizione visibile nel tooltip.
- **Tesoro della corona** (`EconomySystem`): l'oro non è più merce di magazzino. Ogni mese arrivano tasse e rendite
  delle province (ridotte dal **controllo amministrativo**: più province, più dispersione) e si pagano i salari dei
  lavoratori; il saldo può andare in debito e il debito pesa sul consenso.
- **Mercato regionale**: prezzi per regno da scarsità (scorte contro popolazione), pronti per commercio e IA.
- **Province degli altri regni**: popolazione aggregata che cresce ogni anno con fertilità e sviluppo (`ProvinceGrowthSystem`).
- **Due modi di simulare lo stesso villaggio**: dove guarda la camera gli abitanti vivono ora per ora; altrove la
  giornata si risolve in forma aggregata (`SettlementAggregate`) — stesse regole, stessi alberi abbattuti, stessi
  cantieri, ma ~7 volte più veloce. Quando la camera torna, gli abitanti riprendono da dove sono.
- **Etichetta dell'insediamento** derivata dalla popolazione reale (Insediamento → Villaggio → Borgo → Città) e
  barra con tesoro, consenso e capienza dei depositi.
- Salvataggi: save_version 4 (tesoro, consenso, prezzi) con migrazione dalla 3 che sposta l'oro dai magazzini al tesoro.

**Verifiche eseguite**
- 67 test, 0 fallimenti. Nuovi (`test_economy`): capienza dei depositi e perdite per traboccamento; tasse, salari,
  rendite e controllo amministrativo; prezzi che seguono la scarsità; **vent'anni di villaggio prospero** (cresce,
  nascite e morti, consenso alto, tesoro positivo, diventa "Villaggio"); **carestia** che fa crollare il villaggio;
  villaggio osservato e non osservato che producono gli stessi risultati; stessa partita salvata e ripresa identica.
- Prestazioni: 20 anni simulati in ~37 s (erano ~240 s prima della modalità aggregata); in gioco 480 tick/s a 143 fps
  con il villaggio a schermo; benchmark di volo ~124 fps medi.

**Parziale / note**
- Un solo insediamento esiste finora: i **trasporti a flussi fra insediamenti** e le carovane restano da fare quando
  nasceranno i secondi villaggi (fase successiva alla conquista/colonizzazione).
- Classi sociali, aliquote fiscali regolabili, migrazioni interne e commercio fra regni: arrivano con governo (Fase 7)
  e diplomazia (Fase 8); qui ci sono già salari, tasse e prezzi che li reggeranno.
- La successione non esiste ancora: se il re muore di vecchiaia il dominio resta senza sovrano fino alla Fase 7.
- I boscaioli continuano a spogliare il raggio di taglio: la gestione forestale (rotazione, piantumazione) è da fare.

---

## FASE 6 — Cultura, religione, spiriti nazionali ✅

**Completato**
- **La formula del regno**: `KingdomModifiers` costruisce per ogni dominio una `ModifierStack` con fonti nominate
  (cultura, religione, ogni spirito nazionale). I sistemi non scrivono più numeri a mano: chiedono il valore alla pila,
  quindi ogni effetto è ispezionabile e mostrato nell'interfaccia con la sua provenienza.
- **Effetti reali**: produzione di legname, pietra, ferro, grano (con chiavi extra per terre irrigue e terre aride),
  pane e armi; velocità dei cantieri; costo delle strade; gettito fiscale; rendita dei commerci; controllo
  amministrativo; crescita della popolazione; stabilità di base e tolleranza.
- **Spiriti nazionali** (`data/defs/national_spirits.json`, 14 spiriti): ogni regno ne riceve alla fondazione da 1 a 4
  **derivati dalla propria terra** (bosco, montagne, fiumi, coste, giacimenti, vicini) e poi **evolvono con ciò che il
  regno fa davvero**, grazie ai registri delle azioni (legname tagliato, grano raccolto, armi forgiate, metri di strada,
  giorni di carestia, anni di pace). Catene già in gioco: Popolo dei boschi → Signori del legname o Boschi diradati;
  Granaio della pianura → Terra dei mercati o Carestia ricordata; Montanari del ferro → Fucine del regno o Via del ferro;
  Signori dei guadi → Città dei ponti; Popolo di frontiera → Frontiera pacificata. Uno spirito abbandonato non ritorna.
- **Cultura e religione delle province** (`CultureSystem`): ogni provincia ha la sua e può cambiarla lentamente sotto una
  corona straniera; l'attrito genera **malcontento** che erode le rendite, e la tolleranza della religione lo smorza.
- **Pannello REGNO** (tasto R o pulsante nella barra): stemma, casata, cultura e religione con le loro descrizioni,
  spiriti nazionali con effetti e anno di nascita, e la formula completa del regno voce per voce, con il tooltip che
  dice da quale fonte arriva ogni pezzo.

**Verifiche eseguite**
- 73 test, 0 fallimenti. Nuovi (`test_identity`): ogni regno nasce con spiriti coerenti con la sua terra e **terre
  diverse danno spiriti diversi**; i modificatori arrivano ai numeri veri e la scomposizione nomina la fonte;
  **uno spirito evolve dopo le imprese che chiede**; i registri si riempiono lavorando; una provincia straniera si
  risente, rende meno e alla fine si assimila; identità e registri sopravvivono al salvataggio.
- Prestazioni: la pila di modificatori è in cache per versione dell'identità (4 s per anno simulato con 30 abitanti,
  come prima della fase).

**Parziale / note**
- Chiavi già definite ma non ancora usate da nessun sistema: ricerca, prestigio, costi di legge e riforma, leva e
  morale militare, credito. Arriveranno con governo (Fase 7), esercito (Fase 9) e guerra (Fase 10).
- Le minoranze dentro una provincia non sono ancora modellate: la provincia ha una cultura e una religione sole.
- Gli spiriti dei regni IA evolvono con le stesse regole, ma finché l'IA non agisce (Fase 8) i loro registri crescono poco.

---

## FASE 7 — Politica ✅

**Completato**
- **Il sovrano è una persona** (`CharacterState`, `characters/`): nome, casata, età, sesso, **tratti**
  (`data/defs/traits.json`, 12: avaro, generoso, crudele, giusto, pio, guerriero, tessitore di trame, malato… ognuno
  con i suoi modificatori, il suo effetto sulle fazioni e il suo peso sulla mortalità) e quattro **abilità**
  (governo, guerra, diplomazia, intrigo). Il re del dominio del giocatore è anche l'uomo che cammina sulla mappa:
  stesso nome, stessa età; se muore lì, muore anche sul trono, e l'erede prende il suo posto nel mastio.
- **Corte e dinastia** (`CourtSystem`, un passo al giorno): consorte e figli, nozze, nascite a corte, invecchiamento e
  morte con curva di mortalità dai 58 anni in su (`balance/crown.json`).
- **Successione secondo la legge in vigore**: primogenitura, elettiva (i grandi scelgono il più capace), anzianità;
  l'erede può anche essere **designato** dal sovrano. Un erede minorenne porta una **reggenza** (legittimità in meno,
  turbolenza in più); nessun erede apre una **crisi dinastica**: un ramo lontano viene chiamato al trono e il regno
  paga 25 punti di legittimità. Ogni passaggio finisce nella cronaca e negli avvisi.
- **I cinque poteri** (`data/defs/factions.json`: nobiltà, popolo, mercanti, esercito, clero) con un **favore** 0–100
  che si muove ogni giorno secondo i fatti: consenso degli abitanti, tratti del sovrano, salari non pagati, e le
  decisioni prese (ogni legge lascia una traccia duratura sul favore, non un salto che il giorno dopo si annulla).
- **Leggi ed editti** (`data/defs/laws.json`): quattro gruppi esclusivi (Successione, Fisco, Fede, Gilde e strade) e
  quattro editti a tempo (Granai aperti, Turni lunghi, Giorno di riposo, Coprifuoco). Ogni scelta costa oro, entra
  nella formula del regno come fonte nominata (`law:*`, `edict:*`) e ha **vincitori e perdenti**: il catasto rende
  di più ma indispone nobiltà e popolo, la franchigia riempie le piazze e svuota le casse. I comandi
  (`EnactLawCommand`, `IssueEdictCommand`, `DesignateHeirCommand`) rifiutano con una ragione leggibile (tesoro
  insufficiente, legittimità troppo bassa, reggenza, legge già in vigore).
- **Le misure della corona contano davvero**: legittimità, ordine, prestigio e turbolenza inseguono ogni giorno il
  loro bersaglio (erede adulto, età del sovrano, fazioni ostili, malcontento delle province). L'**ordine** decide
  quanta parte delle tasse viene davvero riscossa (fino a un quinto evaso in un regno in disordine) e, insieme alla
  legittimità, pesa sul consenso degli abitanti come voce visibile nel tooltip ("La corona").
- **Pannello REGNO ampliato**: IL SOVRANO (nome, casata, età, abilità, tratti con la loro descrizione, erede),
  le tre misure della corona a barre, i figli con il pulsante per designare l'erede, I POTERI DEL REGNO con il favore
  di ognuno, e LEGGI ED EDITTI con i pulsanti attivi: il tooltip dice effetti, costo, chi ci guadagna, chi ci perde
  e, se non si può fare, perché.

**Verifiche eseguite**
- 85 test, 4460 asserzioni, 0 fallimenti. Nuovi (`test_politics`): ogni regno nasce con un sovrano incoronato;
  successione con **erede adulto**, **erede minorenne** (reggenza) e **senza eredi** (crisi); la legge in vigore
  decide chi eredita; una legge ha vincitori e perdenti e si vede nei numeri; una legge viene rifiutata con la sua
  ragione; un editto dura trenta giorni e poi scade; le misure della corona seguono i fatti; **sessant'anni di regni
  senza errori con almeno due cambi di sovrano**; un regno in disordine riscuote meno; corte, leggi ed editti
  sopravvivono al salvataggio.
- Prestazioni: benchmark di volo **127,7 fps medi** (lontano 113, strategico 128, locale 112, vicino 140) —
  come prima della fase; il sistema della corte è un passo al giorno e non si sente.

**Parziale / note**
- Il **consiglio della corona** e le richieste esplicite delle fazioni (con scadenza e conseguenze) non ci sono
  ancora: il favore si muove, ma nessuno bussa alla porta. Arriva con gli eventi (Fase 11).
- I regni IA hanno sovrani, leggi e successioni come il giocatore, ma finché non decidono nulla (Fase 8) le loro
  leggi restano quelle di partenza.
- Trovato provando il villaggio lasciato a sé stesso per 900 giorni: senza nessuna decisione del signore il paese
  cresce oltre il cibo che produce e poi muore di fame fino all'ultimo abitante (prima della Fase 7 moriva del tutto,
  re compreso). È il comportamento del sistema, non un errore — con un signore che costruisce (test dei vent'anni)
  il villaggio prospera — ma manca una valvola: chi ha fame dovrebbe **emigrare** prima di morire. Da fare nel
  passaggio di bilanciamento (Fase 13) o con le migrazioni interne.

---

## FASE 8 — Diplomazia e IA ✅

**Completato**
- **Opinioni che vengono dai fatti** (`Diplomacy`, `RelationState`): ogni coppia di regni ha una relazione con
  un'opinione da −100 a +100 che ogni giorno insegue il suo bersaglio. Il bersaglio nasce da cultura e fede
  condivise o diverse, dal confine in comune, dall'ombra del vicino più forte, dai patti firmati, dal matrimonio
  fra le case, dalla guerra in corso e dai **ricordi** (guerra dichiarata, patto rotto, pace fatta, dono, chiamata
  alle armi accolta o tradita) che svaniscono negli anni. Il pannello mostra la scomposizione voce per voce.
- **Patti** (`data/defs/diplomacy.json`): non aggressione, patto commerciale, alleanza (chiede prima la non
  aggressione), tributo e vassallaggio (asimmetrici: il più debole paga ogni mese una quota delle sue entrate).
  Ogni patto entra nella formula del regno come fonte nominata (`pact:*`), ha una durata, un prezzo in oro e un
  prezzo politico se viene rotto (prestigio e un ricordo che dura trent'anni).
- **Guerra e pace**: la dichiarazione rompe i patti che la vietavano, **chiama gli alleati** (i vassalli devono
  venire, gli alleati decidono: chi non viene perde l'alleanza e si guadagna un rancore), costa prestigio e
  scuote l'ordine. La pace si chiede quando la **stanchezza** cresce (anni di guerra, casse vuote, disordine) e
  lascia dietro di sé una **tregua** di cinque anni che vieta una nuova dichiarazione. Le battaglie vere
  arrivano con gli eserciti (Fasi 9–10): qui la guerra è già un fatto politico ed economico.
- **Matrimoni dinastici**: un figlio di una casata sposa un figlio dell'altra, i due personaggi restano ognuno
  alla propria corte e le corone si stimano per una generazione.
- **IA dei regni** (`RealmAiSystem`, un turno al mese per ogni dominio non del giocatore): la **personalità**
  esce dai tratti del sovrano (aggressività, avidità, devozione, prudenza, commercio, autorità) più le sue
  abilità; ogni mese il regno valuta con un punteggio di utilità tutto ciò che potrebbe fare — sviluppare una
  provincia, promulgare una legge, emanare un editto, proporre un patto, chiedere un matrimonio, pretendere un
  tributo, dichiarare guerra, chiedere la pace, designare un erede — e fa **una** cosa sola, la più adatta a chi
  siede sul trono. Ogni scelta è scritta in parole leggibili (`RealmAiSystem.log_lines`), con il perché e
  l'esito (anche i rifiuti).
- **Il giocatore è trattato come tutti**: le proposte dell'IA arrivano come **ambasciate** che aspettano sul
  tavolo (`WorldState.offers`, trenta giorni) e si accettano o si respingono; le sue proposte passano dagli
  stessi comandi e ricevono la stessa risposta motivata.
- **Comandi**: `ProposePactCommand`, `AnswerOfferCommand`, `BreakPactCommand`, `DeclareWarCommand`,
  `MakePeaceCommand`, `ArrangeMarriageCommand`, `DevelopProvinceCommand` — tutti con la ragione leggibile
  quando non si può fare (tregua in corso, patto che lo vieta, oro insufficiente, reggenza, opinione troppo bassa).
- **Interfaccia**: pannello **DIPLOMAZIA** (tasto D o pulsante nella barra) con le ambasciate in attesa in cima e,
  per ogni corona, stemma, stato dei rapporti, opinione colorata con il tooltip che la spiega e i pulsanti per
  proporre, rompere, sposare, dichiarare o chiedere la pace. Nuova **modalità mappa Diplomazia** (F11): il mondo
  dipinto secondo come sta con noi (alleati, patti, tregua, guerra, vassalli).

**Verifiche eseguite**
- 96 test, 0 fallimenti. Nuovi (`test_diplomacy`): il mondo nasce con opinioni che vengono dai fatti e chi si
  somiglia si stima di più; ricordi e matrimoni pesano; un patto viene firmato o rifiutato **e dice sempre
  perché**; una guerra rompe i patti e chiama gli alleati; la pace lascia una tregua che tiene e poi scade; il
  tributo muove oro ogni mese; un matrimonio lega due case; l'IA governa e motiva; **sovrani diversi producono
  mondi diversi** (25 anni, stesso seme: corone guerriere 5 guerre, corone mercantili 0); **cinquant'anni con
  venti regni** senza errori, con re sempre incoronati, opinioni nei limiti e statistiche di guerre, patti e
  province sviluppate.
- Prestazioni: benchmark di volo **135,2 fps medi** (lontano 132, strategico 136, locale 122, vicino 143), meglio
  della fase precedente. La mappa politica (chi confina con chi) e il peso delle terre sono ora in cache per
  versione politica, i patti hanno un indice e la mortalità dei personaggi si calcola una volta sola: cinquant'anni
  di venti regni si simulano in ~84 s.

**Parziale / note**
- La guerra non ha ancora eserciti: nessuna provincia cambia padrone per conquista. Le paci sono bianche
  (status quo) finché non arrivano esercito (Fase 9) e guerra combattuta (Fase 10).
- L'IA non costruisce edifici: i regni dell'IA non hanno insediamenti simulati, investono nello **sviluppo**
  delle province. Quando nasceranno i loro villaggi, la stessa utilità deciderà anche i cantieri.
- Reputazione globale, rancori personali fra sovrani e trattati con condizioni (cessioni, riscatti) sono
  abbozzati nei ricordi ma non ancora un sistema a sé.

---

## FASE 9 — Esercito ✅

**Completato**
- **Reparti data-driven** (`data/defs/units.json`): lancieri, alabardieri, balestrieri e cavalieri, ognuno con
  quanti uomini servono, quante armi e quanto oro costa, quanti giorni di addestramento, la paga e il pane di
  ogni giorno, il passo di marcia e i requisiti per sbloccarlo (caserma, armi forgiate dal regno, favore della
  nobiltà per i cavalieri).
- **Si arruolano persone vere**: il comando prende gli abitanti adulti del villaggio, li toglie dal lavoro
  (`recruit`), consuma **armi vere** dai depositi e oro dal tesoro; finito l'addestramento gli stessi uomini
  lasciano il villaggio e diventano il reparto. Il paese perde quelle braccia: la produzione cala davvero. Il
  villaggio non può svuotarsi (restano sempre alcuni lavoratori) e il rifiuto lo dice in chiaro.
- **Nuovo edificio: la caserma** (legno e pietra) — senza di essa si leva solo la fanteria più semplice; con
  essa l'addestramento è più rapido.
- **Eserciti fisici sulla mappa** (`ArmyState`): stanno in una provincia, marciano su un percorso calcolato sul
  grafo delle province (costo in chilometri diviso per il terreno: pianure e coste svelte, boschi e colline
  lente, montagne lentissime, e fiumi e passi che costano giorni), e la posizione si interpola giorno per giorno
  così che si vedono camminare.
- **Rifornimenti, morale e diserzioni**: ogni esercito porta viveri per una dozzina di giorni, si rifornisce
  nelle terre del regno e presso i propri insediamenti, e quando resta senza pane perde uomini e cuore. La paga
  esce dal tesoro **ogni giorno**: se la corona non paga, il morale scende e gli uomini se ne vanno nella notte.
  Un uomo perso è una persona in meno nel mondo, non un numero.
- **Comandanti**: il miglior guerriero della corte cavalca con la schiera e la sua abilità in guerra si sente
  nel morale e nel passo.
- **Fog of war militare**: un esercito straniero si vede solo dalle proprie terre, dai propri insediamenti o
  dalle proprie schiere (`Military.can_see`). Quello che la corona non vede, la mappa non lo disegna.
- **Le leve dell'IA**: i regni senza villaggi simulati chiamano i loro uomini dalla **popolazione delle
  province** (la stessa popolazione aggregata che il gioco conta già ovunque), e quando la guerra finisce e le
  casse sono vuote li rimandano nei campi. L'IA leva truppe quando è in guerra o quando il vicino è più armato.
- **Disegno a tre distanze** (`ArmyLayer`): sotto 1,6 m/px si vedono i **soldati** uno per uno (nuove figure
  nell'atlante: lancieri, alabardieri, balestrieri con la balestra di traverso e cavalieri a cavallo con la
  lancia); fino a 45 m/px uno **stendardo** nei colori del regno, più grande quanto più grande è la schiera;
  oltre, nulla.
- **Interfaccia**: pannello **ESERCITO** (tasto E o pulsante nella barra) con la leva (costi, tempi e il motivo
  quando non si può arruolare), le schiere in campo con uomini, morale, viveri, comandante e destinazione, e i
  pulsanti *Muovi* (poi si indica la provincia sulla mappa) e *Sciogli*. Le schiere si possono anche cliccare
  direttamente sulla mappa.

**Verifiche eseguite**
- 108 test, 5052 asserzioni, 0 fallimenti. Nuovi (`test_military`): i reparti vengono dai dati; arruolare prende
  persone, armi e oro veri; la leva viene rifiutata con la sua ragione; il villaggio non si svuota; **un esercito
  marcia su terreno vero e arriva dove è stato mandato**; lontano da casa finisce i viveri, perde uomini e cuore;
  senza paga disertano; sciolto a casa **gli uomini tornano nel villaggio**; il regno vede solo ciò che può
  raggiungere; eserciti e soldati sopravvivono al salvataggio; un anno di soldati costa al tesoro; i regni dell'IA
  levano le loro compagnie dalle province e le rimandano ai campi.
- Prestazioni: benchmark di volo **133,8 fps medi** (lontano 126, strategico 135, locale 121, vicino 142), in linea
  con la fase precedente.

**Parziale / note**
- Non si combatte ancora: due eserciti nemici possono stare nella stessa provincia senza toccarsi. Battaglie,
  assedi e conquista sono la Fase 10, che userà attacco, difesa e morale già presenti nei dati.
- Le scuole d'arme, le code di reclutamento multiple e l'armeria come edificio separato non ci sono: la caserma
  fa da sblocco e da acceleratore, il fabbro fa le armi.
- Gli eserciti non si dividono né si uniscono, e non esiste ancora il rifornimento via carovane: portano viveri
  e si riempiono in terra amica.

---

## FASE 10 — Guerra ✅

**Completato**
- **Battaglie sulla mappa** (`WarSystem`, `BattleState`): due schiere di regni in guerra che si avvicinano a meno
  di 2,6 km si fermano e combattono dove si trovano. Lo scontro si risolve a **turni di reggimento** (tre al
  giorno, per pochi giorni): ogni reparto colpisce secondo attacco, morale e il reparto che si trova davanti —
  i cavalieri travolgono i balestrieri, le alabarde fermano i cavalli, i balestrieri sparano per primi. Il
  **terreno conta**: chi difende su colline, in bosco, in montagna o dietro un fiume incassa molto meno.
- **Perdite vere e ritirata**: i caduti sono uomini che spariscono dai reggimenti (e dal mondo, se erano
  abitanti veri), ogni caduto toglie morale, e quando il morale crolla sotto 22 il reparto **rompe le righe**:
  perdite extra, prestigio perso e marcia di ritirata verso la terra più vicina della propria corona. Chi vince
  guadagna prestigio, morale e punti nel conto della guerra.
- **Assedi** (`SiegeState`): una schiera sola in terra nemica si siede davanti alla provincia. L'assedio avanza
  ogni giorno secondo quanti uomini lo tengono e quanto la provincia è sviluppata e fortificata (mastio e
  caserma contano), e dentro le mura il **consenso crolla** (voce "Assedio" nel tooltip). Quando l'assedio
  arriva a compimento la provincia **cade**: viene occupata, non distrutta.
- **Occupazione e conquista senza reset**: una provincia occupata resta di chi la possiede per diritto, ma è
  tenuta da un altro: rende molto meno, il malcontento cresce ogni giorno, e il consenso degli abitanti ne
  risente ("Occupazione"). Con la pace, ciò che era **solo tenuto** torna alla sua corona; ciò che viene
  **ceduto al tavolo** cambia padrone per sempre — con dentro la sua gente, i suoi edifici, il suo sviluppo e
  un malcontento che ricorda di essere stata consegnata.
- **Paci con condizioni**: si può chiedere la pace bianca o pretendere le province che si tengono in campo.
  L'altra corona risponde guardando **quanto sta perdendo** (il conto della guerra: battaglie vinte, province
  occupate, uomini uccisi, anni passati) e **quanto è stanca**. Non si può chiedere al tavolo ciò che non si
  tiene in campo, e il rifiuto lo dice.
- **La terra paga la guerra**: dove passano gli eserciti nemici la **devastazione** cresce ogni giorno (e con
  essa calano rendite e crescita), e si riassorbe lentamente in pace.
- **L'IA fa la guerra**: marcia sulle province nemiche più vicine, assedia, e quando ha vinto abbastanza
  **chiede la pace pretendendo le province occupate**; quando sta perdendo o è stanca, accetta.
- **Sulla mappa**: un anello rosso dove si combatte, un arco arancione che cresce con l'assedio, e il pannello
  ESERCITO che dice per ogni schiera se è ferma, in marcia, **in battaglia** o **assedia** (con la percentuale).
  Nel pannello DIPLOMAZIA compare il pulsante "Pace con N province" quando se ne tengono.

**Verifiche eseguite**
- 117 test, 6196 asserzioni, 0 fallimenti. Nuovi (`test_war`): il terreno e gli accoppiamenti contano; **due
  schiere che si incontrano combattono, sanguinano e una rompe le righe e fugge**; una schiera sola in terra
  nemica assedia e **prende la provincia con la sua gente dentro**; la pace può essere pagata in terra e non
  azzera nulla; la pace bianca restituisce ciò che era solo occupato; **lo stesso seme combatte la stessa
  battaglia** (determinismo); assedi e conto della guerra sopravvivono al salvataggio; otto anni di guerra fra
  due regni senza errori né valori fuori scala; e infine il test di accettazione completo: **il villaggio del
  giocatore assediato cade con le case in piedi e la gente dentro**, e passa di corona con tutto quello che ha.
- Prestazioni: benchmark di volo **134,5 fps medi** (lontano 128, strategico 136, locale 122, vicino 142).

**Parziale / note**
- Le mura non sono ancora un edificio: la fortificazione di una provincia viene dal mastio e dalla caserma.
  Mura, porte, torri e macchine d'assedio (e l'assalto come scelta rischiosa) restano per la Fase 12.
- Non c'è ancora l'assalto immediato: un assedio si porta a termine con il tempo, non con il sangue in un
  giorno solo. I numeri (`assault_losses_*`) sono già nei dati.
- Le battaglie non hanno una schermata propria: si vedono sulla mappa (soldati da vicino, anello rosso da
  lontano) e si leggono nella cronaca. Una rappresentazione più ricca è lavoro di UI (Fase 12).

---

## FASE 11 — Eventi e rigiocabilità ✅

**Completato**
- **Eventi data-driven** (`data/defs/events.json`, 14 eventi): raccolto abbondante, inverno che non finisce,
  peste, banditi, nobile ribelle, monaco viaggiante, mercante straniero, eresia, incendio, pretendente al trono,
  segno nel cielo, rivolta contadina, stanchezza di guerra, dono di un vicino. Ognuno ha **condizioni vere**
  (stagione, abitanti, consenso, legittimità, ordine, guerra in corso e da quanti anni, province, malcontento),
  un peso, un tempo di riposo, e almeno due risposte. Una condizione che il gioco non sa leggere **non fa mai
  scattare** l'evento: niente magie nascoste.
- **Le risposte cambiano il mondo davvero**: oro dal tesoro, merci nei depositi, consenso, legittimità, ordine,
  prestigio, turbolenza, favore dei poteri, malcontento e devastazione delle province, punti di sapere,
  **morti veri** fra gli abitanti, opinione di un vicino, righe di cronaca e catene verso un altro evento.
- **Crisi che durano** (`KingdomState.crises`): quarantene, pesti, fiere, tolleranze di fatto. Sono fonti
  nominate nella formula del regno finché durano — si vedono nel pannello REGNO con i giorni che restano e
  spariscono da sole quando passano.
- **Il giocatore è interrogato, l'IA decide da sé**: un evento del dominio del giocatore diventa una **carta**
  al centro dello schermo con il testo e le risposte, ognuna con scritto cosa costa e cosa porta; se il re tace
  per quarantacinque giorni la corte decide per lui. Le corone dell'IA scelgono con la testa di chi regna
  (i pesi `ai` di ogni risposta incrociati con la personalità del sovrano).
- **Il sapere** (`data/defs/technologies.json`): quattro rami (la terra, le botteghe, la corona, le armi) e in
  ogni ramo **due strade di cui una sola** si può prendere. I punti crescono ogni mese con lo sviluppo delle
  province, gli edifici e la testa del sovrano (un re saggio vale un quarto in più). Ogni tecnologia entra nella
  formula del regno come fonte nominata e si adotta dal pannello REGNO.
- **La cronaca esiste davvero**: i venticinque punti del codice che scrivevano nel vuoto ora finiscono in
  `WorldState.chronicle`, che sopravvive al salvataggio e si legge nel nuovo pannello **CRONACA** (tasto C),
  con la data, il colore del tipo di fatto e il filtro "solo il mio regno".
- **Obiettivi di campagna** (`Objectives`): un villaggio vivo, un dominio, una dinastia, un tesoro, il sapere —
  cinque cose misurate su fatti veri e mostrate con il loro avanzamento nel pannello REGNO.

**Verifiche eseguite**
- 128 test, 0 fallimenti. Nuovi (`test_events`): gli eventi sono raccontati e lasciano sempre una scelta; le
  condizioni si leggono e non si indovinano; una risposta sposta grano, oro, legittimità, favore e malcontento
  veri; una crisi si sente nei numeri e poi passa; il re viene interrogato e l'IA risponde da sola; il silenzio
  è una risposta; il sapere si sceglie una volta sola per ramo; i punti crescono mese per mese; la cronaca
  ricorda e attraversa il salvataggio; gli obiettivi misurano cose vere; e il test di accettazione della fase:
  **cinque campagne da cento anni con semi diversi raccontano cinque storie diverse** (regni vivi, guerre,
  dinastie, confini, righe di cronaca).
- Prestazioni: benchmark di volo **133,6 fps medi**. La simulazione politica è stata alleggerita di **due terzi**
  (dieci anni di venti regni: 11,0 s → 4,1 s): opinioni, misure della corona, favore delle fazioni, morte dei
  personaggi e devastazione della terra si aggiornano una volta a settimana invece che ogni giorno (stesso
  risultato, un settimo del lavoro), i morti di vent'anni fa lasciano il registro della corte, e i patti si
  controllano solo dove ci sono. Le cinque campagne da un secolo passano da 1007 s a 175 s.

**Parziale / note**
- Gli eventi sono quattordici: pochi per un secolo di gioco. La struttura regge il porting del resto degli
  eventi di Regno, che è lavoro di dati, non di codice.
- Non c'è ancora un **finale di partita** vero (schermata di chiusura, punteggio, riepilogo della dinastia):
  ci sono gli obiettivi e la cronaca completa, che ne sono la materia prima.
- Le catene di eventi esistono (`effects.chain`) ma nei dati attuali nessun evento ne usa una: servono per le
  crisi lunghe della Fase 13.
- **L'IA combatte ma conquista poco**: dichiara guerre, leva compagnie, le raduna e le manda contro il vicino, e
  le battaglie di campo avvengono davvero (decine in quarant'anni), ma raramente porta un assedio fino in fondo
  prima che la guerra finisca. La conquista funziona (i test di Fase 10 la verificano dal comando alla cessione
  di pace), è la **condotta militare dell'IA** a essere ancora ingenua: manda un solo corpo per volta e non
  concentra. È lavoro di bilanciamento e di pianificazione militare, da fare nella Fase 13.
- Le prove che misurano un sistema solo (economia, esercito) ora spengono il tempo atmosferico degli eventi con
  `GameSession.set_system_enabled(&"events", false)`: gli eventi sono veri e cambiano i numeri, quindi un
  esperimento controllato deve poterli togliere.

---

## FASE 12 — UI ✅

**Completato**
- **Una sola cornice, una pagina per volta** (`PanelHost`, `KDSheet`): le schede del regno si aprono da una
  barra di linguette — **Regno · Corte · Governo · Economia · Sapere · Diplomazia · Esercito · Cronaca** — e
  non si sovrappongono mai fra loro né alla mappa. Ogni scheda ha la stessa larghezza, lo stesso scorrimento e
  lo stesso legno con il filo d'oro; ESC chiude, una lettera apre (R, Q, G, F, K, D, E, C; A per gli abitanti).
- **Le schede**: REGNO (stemma, casata, cultura e fede, obiettivi della campagna, spiriti, la formula completa
  del regno voce per voce), CORTE (sovrano con tratti e abilità, legittimità/ordine/prestigio a barre, i figli
  con il pulsante per designare l'erede, i cinque poteri), GOVERNO (leggi per gruppo ed editti, con il tooltip
  che dice effetti, costo, vincitori e perdenti), **ECONOMIA (nuova)**: tesoro, saldo del mese voce per voce
  (tasse, rendite, salari, paghe dell'esercito, quanto è stato davvero riscosso), depositi con la loro capienza,
  giorni di cibo, letti liberi, chi fa cosa nel villaggio e i prezzi del mercato; SAPERE (i quattro rami con la
  strada presa e quelle ancora aperte, più le crisi in corso con i giorni che restano); DIPLOMAZIA, ESERCITO e
  CRONACA come prima, ora dentro la stessa cornice.
- **Notifiche vere** (`NotificationStack`): erano nel riquadro di debug e sparivano con esso; ora sono cartigli
  di legno in alto a destra, colorati per tipo, al massimo sei, che sbiadiscono da soli e, se il fatto è
  successo in un posto della mappa, ci portano la camera con un clic.
- **La carta degli eventi** si è spostata in basso: non copre più la scheda aperta.
- **Un pezzo di codice che mancava a tutti**: `GameSession.set_system_enabled()` permette di spegnere un sistema
  (usato dalle prove che vogliono misurare una cosa sola).

**Verifiche eseguite**
- 134 test, 0 fallimenti. Nuovi (`test_ui`): ogni sistema del gioco ha la sua scheda e si apre; **una scheda per
  volta** e ESC la chiude; le schede mostrano i numeri veri del mondo (tesoro, nome del sovrano, misure della
  corona, obiettivi, formula); il GOVERNO offre ogni legge e ogni editto e **ogni pulsante chiuso dice perché**;
  il SAPERE mostra i rami e le crisi e da lì si adotta davvero una tecnologia; le notifiche non traboccano;
  **ogni scheda sta dentro lo schermo** a 1080p.
- Prestazioni: benchmark di volo **129,8 fps medi**.
- Screenshot verificati a **1920×1080** e **2560×1440**: nessun testo tagliato, nessuna sovrapposizione
  (il gioco usa `canvas_items` con viewport logico 1920×1080, quindi il disegno scala con la finestra).
- **Trovato e corretto un difetto vecchio**: il gioco andava in crash all'uscita (`0xC0000005`) da quando
  esistono gli screenshot automatici. La causa era una lambda collegata dall'autoload `Session` all'orologio
  della partita: alla chiusura il segnale puntava a un nodo già liberato. Ora il collegamento ha un nome e
  viene staccato in `Session.end()`, e sia il gioco sia i test escono con codice 0.

**Parziale / note**
- Il menù di costruzione in basso e la barra dei depositi in alto erano ancora quelli della Fase 4–5:
  **rifatti nella Fase 12.5**.
- Non c'è un menù iniziale né una schermata di caricamento/salvataggio: si entra direttamente in partita
  (arriveranno con il polish della Fase 14).
- Gli ispettori della provincia e dell'edificio restavano fuori dalla cornice a linguette: **riuniti nella
  zona contestuale della Fase 12.5**.

---

## FASE 12.5 — Refactor dell'interfaccia ✅

Non un reskin: l'HUD è stato **rifatto nella disposizione** e vestito con i nuovi asset dipinti.
Il piano, la tabella delle funzioni spostate e il resoconto stanno in `HUD_REFACTOR_PLAN.md`.

**Completato**
- **Gli asset entrano nel gioco.** I cinque fogli sono stati ritagliati (`tools/art/slice_ui.py`, taglio XY
  ricorsivo sull'alfa: 33+68+8+130+80 pezzi), scelti e ripuliti (`tools/art/build_ui_kit.py`: la cornice
  dipinta portava un titolo, una croce e una pergamena dentro — tutti cancellati, perché una cornice che
  ospita testo vivo non può avere parole dipinte). Ne escono `assets/ui/kit/` (18 cornici e pulsanti),
  `assets/ui/icons/` (36 icone) e `assets/ui/kit.json`. `ui/theme/kd_ui.gd` li trasforma in nove sezioni;
  `KDTheme` resta l'unico vestitore e, se un pezzo manca, ricade sui vecchi riquadri.
- **Cinque blocchi invece di un ammasso in alto.**
  **A** (`ui/shell/top_bar.gd`): risorse a sinistra, misure della corona a destra e — nuova in gioco —
  **data, stagione e velocità del tempo**, che prima esistevano solo nel riquadro di debug.
  **B** (`ui/shell/nav_block.gd`): colonna di sinistra con ciò che si governa e, in fondo, il menù delle mappe.
  **C** (`ui/shell/build_column.gd`): il menù costruzioni lascia la base dello schermo e diventa una colonna
  con categorie, costo di ogni edificio e **il motivo quando manca il materiale**; sotto, la zona contestuale.
  **D**: barra inferiore con le grandi sezioni. **E**: notifiche a destra, carta evento al centro.
- **Un solo posto per gli ispettori.** L'ispettore dell'edificio (era in basso al centro) e quello della
  provincia (era in alto a destra) vivono ora nella stessa zona contestuale della colonna C.
- **Il centro dello schermo è libero.** Le schede si aprono ancorate alla colonna sinistra e la barra delle
  linguette diventa una sola riga con il nome della scheda e la croce: la navigazione è nei blocchi B e D.
  Una scheda corta ora è corta (`KDSheet._fit()`), non più un rettangolo di legno mezzo vuoto.
- **Scheda CETI (nuova)**: i cinque poteri del regno escono dal fondo della scheda Corte e hanno la loro
  pagina — favore, umore, cosa chiedono, chi mal sopportano, quanto il loro malcontento costa a legittimità
  e ordine, con i numeri veri del bilanciamento. In Corte resta la riga di riepilogo.
- **Scheda ABITANTI (nuova cornice)**: la lista degli abitanti e la quota di costruttori erano un riquadro a
  comparsa appeso alla vecchia barra; ora sono una scheda come le altre.
- **La barra delle modalità mappa** non attraversa più lo schermo: è un menù a scomparsa in fondo alla colonna
  sinistra (`ui/map/map_mode_menu.gd`), con gli stessi tasti di prima (M e i tasti funzione).

**Verifiche eseguite**
- **139 test, 0 fallimenti**. Cinque nuovi in `test_ui`: ogni pulsante delle colonne apre davvero la sua
  scheda (dieci su dieci); la fascia superiore dice il giorno, l'oro e la legittimità e i sei pulsanti della
  velocità cambiano davvero l'orologio; la colonna delle costruzioni elenca gli edifici e dice cosa manca;
  la scheda Ceti porta i cinque poteri e chiama ostile chi sta sotto i trenta; **le due colonne più una
  scheda aperta lasciano libero il centro della mappa** a 1280, 1920 e 2560 px.
- Prestazioni: benchmark di volo **124,8 fps medi** (erano 129,8 in Fase 12: il prezzo dei blocchi nuovi
  sempre a schermo; il fotogramma peggiore resta al caricamento della mappa).
- Screenshot verificati: villaggio, scheda Corte, scheda Economia, scheda Governo, scheda Esercito,
  provincia selezionata, edificio selezionato (`tests/output/p125_*.png`).

**Parziale / note**
- Le notifiche restano a destra come chiedeva la bozza, ma **accanto** alla colonna delle costruzioni, non
  sotto: a destra ci sono due blocchi e coprirsi sarebbe stato peggio che spostarsi di 400 px.
- La barra delle risorse resta ancorata a sinistra invece che centrata: centrata si sovrapporrebbe alle
  misure della corona sugli schermi stretti (1280).
- Restano da fare, con il polish della Fase 14: menù iniziale, schermata di salvataggio, minimappa.

---

## FASE 13 — Ottimizzazione e bilanciamento ✅

Prima misurare, poi toccare. Il profilo di una giornata (`Scheduler.profile_report()`) ha detto dove andava
il tempo, e il villaggio lasciato a sé stesso ha detto dove andavano i numeri.

**Ottimizzazione (misurata, non supposta)**
- **Le liste degli abitanti sono in cache** (`WorldState.people_of`): era una scansione completa del dizionario
  delle persone, con ordinamento, chiamata decine di volte al giorno per ogni insediamento. Ora c'è
  `people_version` (lo alza chi nasce, muore o cambia insediamento) più un controllo sulla dimensione del
  dizionario: una chiamata dimenticata costa un ricalcolo, mai una risposta sbagliata.
- **Gli alberi intorno al taglialegna non si ricontano ogni mattina**: la lista dei candidati viveva un giorno
  solo e ogni giorno si riscorrevano più di mille celle della griglia. Adesso sopravvive — gli abbattuti si
  potano man mano — e si butta **solo** quando un ceppo ricresce. Da sola vale il 78% del giorno di un
  insediamento.
- **La ricrescita dei ceppi ha un promemoria** (`TerrainDeltas.next_regrow_day`): prima di quel giorno la
  scansione di migliaia di chiavi non parte nemmeno.
- **L'ora per ora si salta quando nessuno guarda**: `SettlementSim.tick()` passava su tutte le persone del
  mondo 24 volte al giorno anche a camera lontana; ora se nessun insediamento è osservato il ciclo non parte.
- **Il consenso non è più quadratico** (`service_coverage` raccoglie le botteghe una volta sola), **i cantieri
  non ricontano gli alberi** già abbattuti (`BuildingState.ground_cleared`), **il registro di corte** calcola
  `day % 7` una volta e mette il filtro più economico per primo.

| Prova | Prima | Dopo |
|---|---|---|
| dieci anni di villaggio (profilo) | 37,4 s | 11,5 s |
| `test_settlement::test_two_years_of_settlement_life` | 9,9 s | 1,0 s |
| `test_economy::test_twenty_years_of_a_prosperous_village` | 97,6 s | 39,0 s |
| suite completa | 739 s | 678 s **con due prove nuove e pesanti** (senza, ~566 s) |

**Bilanciamento: il pane** — qui c'era un difetto vero, non una lentezza. Un villaggio lasciato senza
decisioni moriva di fame fino all'ultimo uomo in un paio d'anni. Le cause, trovate misurando:
1. il grano contava per il suo valore crudo anche con il forno acceso accanto (un granaio pieno sembrava
   mezza dispensa) → `food_days()` ora conta il grano per quel che il forno ne farà;
2. i costruttori venivano prima dei contadini nella priorità dei mestieri, e con il quota "molti" un villaggio
   passava l'anno a tirare su case saltando la mietitura → **il pane prima della pietra**, e i cantieri non
   possono mai prendere le braccia che servono ai campi;
3. non esisteva nessun modo di andarsene → **la valvola dell'emigrazione**.

La valvola (`PopulationSystem._emigration`, guardata ogni giorno) misura il raccolto: se quel che c'è nei
depositi non porta il villaggio alla mietitura successiva, ogni giorno qualcuno prende la strada — prima i
senza lavoro, poi le braccia che si possono risparmiare, e i contadini e il fornaio per ultimi, perché un
posto che perde l'ultimo contadino perde anche il raccolto dell'anno dopo. Chi parte porta con sé i figli di
casa sua; se un altro insediamento del regno ha un letto libero e i depositi pieni ci vanno, altrimenti
lasciano il regno. Le partenze si fermano da sole appena quel che resta basta a chi è rimasto.

| Venti anni senza una sola decisione del signore | Prima | Dopo |
|---|---|---|
| abitanti alla fine | 1 (il re, risorto dalla corte) | **10** |
| morti di stenti | 157 | **0** |
| partenze | 3 | 108 |
| consenso | 0 | 63 |

Il villaggio prospero (con un signore che costruisce) passa da 17 morti in vent'anni a 1. La carestia vera
resta possibile: un insediamento **senza campi** muore comunque, e in fretta (`test_famine_makes_the_village_collapse`).

**Bilanciamento: la condotta militare dell'IA**
- **Le compagnie si radunano prima di marciare**: un corpo che vale meno della metà del più grosso va a
  unirsi a lui invece di partire da solo (era il difetto annotato in Fase 10: «manda un solo corpo per volta»).
- **Un assedio maturo non si svende**: con una piazza oltre la metà dell'opera, l'utilità della pace scende
  del 55%. Le mura valgono più dei termini.

**Verifiche eseguite**
- **143 test, 0 fallimenti, 6829 asserzioni.** Nuovi: la valvola dell'emigrazione (`test_economy`), il raduno
  delle compagnie e l'assedio che non si vende (`test_military`), e **`test_stress`**: sessant'anni del mondo
  intero con un villaggio che cresce davvero, più salvataggio e caricamento cronometrati.
- Stress: 60 anni in 86 s, 17 regni vivi, 14 abitanti nel villaggio del re, 159 personaggi a corte;
  **salvataggio 4 ms / 228 KB, caricamento 27 ms**.
- Cinque campagne di un secolo: 15-17 regni vivi, 14-26 guerre ciascuna, cinque storie diverse.

**Parziale / note**
- La prova dei cinque secoli resta la più cara della suite (352 s): è una prova di accettazione vera e non è
  stata alleggerita per far tornare i conti.
- Il costo di una giornata politica cresce ancora con i personaggi a corte (corte e diplomazia sono la metà
  del secolo simulato): è lavoro già distribuito su rotazione settimanale, ma un indice per bucket dei
  personaggi resta la prossima cosa da fare se servirà.

---

## FASE 14 — Rifinitura: quel che sta attorno alla partita ✅

Quel che c'è attorno alla partita, che fino a ieri non c'era: una porta d'ingresso, uno scaffale dei
salvataggi, un modo di fermarsi, il mondo intero in un angolo e i primi passi spiegati una volta sola.

**Completato**
- **Menù iniziale** (`scenes/menu.tscn`, `ui/menu/main_menu.gd`): il gioco non si apre più direttamente in
  partita. Titolo, **Continua** (con il nome del regno e la data dell'ultima campagna), **Nuova partita**,
  **Carica partita** con l'elenco dei salvataggi ed **Esci**. Ogni argomento `--kd-*` salta il menù ed entra
  in partita, quindi screenshot, prove e strumenti funzionano esattamente come prima; `--kd-menu` chiede la
  porta di proposito (serve a fotografarla).
- **Lo scaffale delle campagne** (`save/save_catalogue.gd`): legge l'intestazione di ogni file — giorno, data
  in parole, regno, sovrano, quando è stata scritta — senza costruire il mondo, e le ordina dalla più recente
  fino al millesimo di secondo (due salvataggi nello stesso respiro mantengono il loro ordine).
- **Salvataggio automatico**: una volta per anno di gioco, a rotazione di tre. Su una campagna di sessant'anni
  costa 4 ms: non si sente. Una finestra chiusa per sbaglio non costa più un regno.
- **Menù di pausa** (`ui/menu/pause_menu.gd`): ESC — quando nessuna scheda è aperta — ferma l'orologio e apre
  riprendi, salva, carica, torna al menù, esci. Alla ripresa la velocità torna quella di prima.
- **Minimappa** (`ui/map/minimap.gd`): il continente in basso a sinistra, coloured con la modalità mappa in
  uso, con il rettangolo di quel che la camera guarda; un clic ci porta la camera. Si ridisegna solo quando i
  confini cambiano o cambia la modalità: zero costo per fotogramma.
- **La guida dei primi passi** (`Guide`, `ui/guide/guide_panel.gd`, passi in `data/defs/guide.json`): un
  cartiglio con una cosa per volta — un tetto, i campi, il forno, la gente, la prima legge, la prima ricerca,
  la prima compagnia. **Ogni passo si chiude da solo quando lo stato del mondo dice che è stato fatto**:
  nessun obiettivo finto, nessuna mano sulla mano del giocatore, e la croce la chiude per sempre. Il passo
  raggiunto vive in `world.flags["guide_step"]`, quindi si salva con la campagna.

**Verifiche eseguite**
- **149 test, 0 fallimenti.** Nuovi (`test_menu`): lo scaffale elenca le campagne con quel che serve a
  sceglierle; una campagna torna dallo scaffale al giorno in cui era stata lasciata e riprende a camminare;
  i salvataggi automatici non si accumulano (e il più recente è davvero l'ultimo scritto); la minimappa
  disegna mare e terra; la guida segue quel che il regno fa davvero e si salva con la partita.
- Schermate verificate: menù iniziale, partita nuova con la guida al primo passo, menù di pausa sopra il
  mondo, minimappa con il rettangolo della camera (`tests/output/p14_*.png`).

**Parziale / note**
- **Suoni e musica non ci sono.** Non è una dimenticanza: non ho modo di ascoltare quel che produco, e un
  rumore sintetizzato alla cieca sarebbe peggio del silenzio. Restano da fare con materiale audio vero.
- Il menù non ha ancora la scelta del regno o del seme della campagna: «Nuova partita» comincia sempre dal
  Dominio di Valverde. È la prima cosa da aggiungere quando ci saranno più casate giocabili.
- La guida copre i primi passi, non la guerra né la diplomazia: chi arriva lì ha già capito come si gioca.

---

## FASE 14B — Visual polish finale ✅ (con lavoro dichiarato ancora aperto)

La Fase 14 aveva finito **quel che sta attorno alla partita**, non l'aspetto del gioco. Il controllo è in
`VISUAL_POLISH_AUDIT.md`, fatto guardando codice, asset e quattro schermate a zoom diversi: la carta lontana
sembrava un gioco pubblicato, la fascia media e quella locale un prototipo pulito, e due fogli di asset su
cinque non erano mai entrati in gioco. Questa sottofase chiude la distanza, senza rifare nulla che funzioni.

**Fatto**
- **Un tema per tutto il resto** (`KDTheme.project_theme()`, appeso alla radice da menù e HUD): tooltip nella
  cornice dipinta, barre di scorrimento in oro, caselle con le spunte del kit, popup, barre di avanzamento e
  separatori. Prima, tutto ciò che il codice non vestiva a mano restava **grigio Godot**: era la ragione
  principale per cui l'interfaccia sembrava due giochi incollati.
- **Le ombre**: edifici, abitanti e soldati proiettano un'ombra verso sud-est — la stessa direzione da cui il
  rilievo del terreno prende la luce — e attorno a ciò che è vissuto la terra è battuta. Un campo arato non
  proietta ombra né consuma l'erba: è già terreno (`_stands_up`).
- **Il bosco sembra un bosco**: ogni albero ha la sua misura (0.78–1.24) e metà sono specchiati; la banda dei
  singoli si ferma a 1.7 m/px e i grappoli dipinti prendono la fascia media. A 2 m/px non è più una
  punteggiatura regolare di puntini identici.
- **Montagne nitide**: l'atlante è stato ridisegnato a 384 px per impronta (era 200, stirato del 250% a zoom
  regionale) su una tavola 2048×1024.
- **Roccia con grana e luce**: l'alta quota era una velatura pallida uniforme; ora la roccia ha una grana
  propria e prende il doppio della luce del sole (`shaders/terrain.gdshader`).
- **La carta si popola**: ogni provincia porta lo spillo dipinto della sua taglia — villaggio, borgo, città,
  capitale — con il punto del colore di chi la tiene; gli insediamenti veri hanno spillo e targa col nome.
  Dodici pezzi nuovi dal **foglio 5**, che fino a ieri non era mai stato aperto.
- **Gonfaloni, battaglie e assedi**: un esercito lontano era la figura di un uomo tinta di colore; ora è il
  pennone dipinto dell'arma che pesa di più nella schiera, con il disco del regno. Battaglia e assedio hanno
  il loro segno dipinto, e l'anello dell'assedio si riempie mentre le mura cedono.
- **Schermate pulite**: `--kd-no-events`, `--kd-menu`, `--kd-pause` per fotografare il gioco senza una carta
  evento davanti all'obiettivo.

**Verifiche eseguite**
- Suite completa verde dopo gli interventi (rendering, shader, kit e tema).
- Schermate di confronto prima/dopo alle stesse inquadrature: `tests/output/p14b_*.png` (prima) e
  `p14b2_*`, `p14b3_*`, `p14b4_*`, `p14b5_*` (dopo).

**Secondo passaggio (fatto)**
- **Rive dei fiumi**: da vicino il fiume ha la sua riva di limo e ghiaia, un'increspatura lenta e un filo di
  luce sul lato illuminato; dalla carta alta resta la linea blu.
- **Grana del terreno vicino**: il prato non è più un verde piatto; la terra affiora dove l'erba si dirada.
- **Case diverse**: tre disegni per la casa sulla stessa impronta, scelti per sempre dall'id dell'edificio
  (`test_settlement::test_the_houses_of_a_village_are_not_all_the_same`). La prova ha anche trovato un hash
  fragile nella prima versione — `id × 7919 mod 3` dava la stessa casa a id distanziati di tre — sostituito
  con quello del progetto.
- **Un errore nascosto delle ombre**: centinaia di `triangulation failed` nel log a ogni fotografia. Le
  ellissi di mezzo metro a coordinate di 34 km perdevano i punti alla precisione dei float; ora sono cerchi
  scalati attorno a un'origine locale. Log pulito.

**Terzo passaggio (fatto)**
- **Barre di sezione dipinte** in tutte le schede (`KDSheet.section`), dal foglio 3; **riga ornamentale** con
  il giglio nel menù e nella pausa. Il foglio 3 era diverso da come l'avevo descritto: le finestre grandi
  sono bozze con titolo e contenuto dipinti, le parti vere erano in una striscia che è stata ritagliata a mano.
- **Un difetto grave, non grafico**: le prove del menù svuotavano `user://saves`, cioè i salvataggi veri di chi
  lancia la suite. Ora usano `user://tests/saves`. Su questa macchina la cartella dei salvataggi è stata
  trovata vuota: tutto ciò che c'era è stato cancellato dalle esecuzioni della suite dalla Fase 14 in poi.
- **Ordine dei salvataggi**: una prova instabile ha mostrato che due salvataggi nello stesso millisecondo non
  avevano un ordine — «Continua» poteva aprire il più vecchio. `SaveSystem.next_stamp()` rende l'ora del
  salvataggio strettamente crescente.
- `art_source/.gdignore`: Godot non importa più i 373 ritagli dei fogli sorgente.

**Resta aperto, dichiarato**
- **Tipografia**: serve un file di font medievale ridistribuibile. Non posso scaricarlo da qui e non voglio
  far passare per scelta tipografica un ripiego di sistema: `ui/theme/kd_fonts.gd` resta a `SystemFont`.
- **Suoni e musica**: non posso ascoltare quel che produco.
- **Varianti degli altri edifici**: per ora solo le case ne hanno; il meccanismo vale per tutti.
- **Stemmi dipinti**, e la barra di sottosezione del foglio 3 già ritagliata ma non ancora usata.

---


## FASE 15 — Sei fondatori, e il Regno come conquista ✅

La partita non comincia più con un re. Comincia con **sei persone**, tre uomini e tre donne, un fuoco comune e
una tettoia. Il Regno è una cosa che il giocatore costruisce: il piano completo, con le scelte dichiarate, è
in `FONDATORI_PLAN.md`.

```
6 FONDATORI → COMUNITÀ → FAMIGLIE → VILLAGGIO → SCELTA DELLA CASA REALE → PRIMO SOVRANO → REGNO → DINASTIA
```

**L'avvio**
- Sei fondatori, ciascuno con il cognome della propria famiglia (sei **famiglie fondatrici**, cognomi per
  cultura in `person_names.json`). Nessun re, nessuna dinastia, nessuna corte, nessun mastio: un **Fuoco
  comune** (`camp_store`, deposito da 450 per gruppo, non costruibile) e il riparo. Scorte modeste
  (`settlement.json::start_stock`). Il territorio si chiama «Comunità di …» ed è di rango `SETTLEMENT`.
- La cronaca si apre con l'arrivo dei sei (`founding_arrival`).

**Le famiglie** (`settlement/family_state.gd`, `settlement/systems/family_system.gd`, mensile, prima della
popolazione)
- Adulti liberi dello stesso insediamento si uniscono (i fondatori più in fretta), mai fra consanguinei; la
  moglie entra nella famiglia del marito, la famiglia d'origine resta registrata. **Si nasce da una coppia**:
  ogni figlio ha madre, padre, famiglia e cognome. Chi arriva da fuori porta la sua famiglia.
- Ogni famiglia ha un **registro** (giorni nei campi, in bottega, in armi, figli), una **reputazione**, un
  **albero essenziale** e un'**origine** che porterebbe alla corona (contadini, artigiani, gente d'arme, la più
  stimata — `house_origins.json`, con effetti moderati sui poteri e sulle rendite).

**Le misure della comunità**
- **Fiducia** (il consenso) e **Autorità**, la capacità di decidere insieme: nasce da fiducia, famiglie
  radicate, cibo sicuro, edifici, anni insieme e si muove piano ogni mese (`families.json::authority`). Nella
  fascia alta Legittimità, Ordine e Prestigio sono nascosti finché non c'è una corona; al loro posto Autorità
  e Famiglie, con il dettaglio nel suggerimento.
- Prima della corona niente leggi, editti, eredi o matrimoni di stato: i comandi rispondono «Non c'è ancora
  una corona». Il consenso non contiene più la voce «La corona» quando la corona non esiste.

**Le condizioni del Regno** (`CourtSystem.monarchy_conditions`, tutte in dati): un villaggio (30 abitanti),
stabile (fiducia ≥ 45, nessuno che salta i pasti), un'economia che regge (60 giorni di cibo, scorte che
arrivano al raccolto, cassa non in debito), due famiglie radicate (tre membri vivi), autorità ≥ 50, due anni
insieme. La scheda le mostra tutte, con il loro valore; il comando rifiuta con la prima che manca.

**La scelta e l'incoronazione**
- La scheda **FAMIGLIE** (la stessa che dopo sarà la Corte) mostra «NESSUN SOVRANO», le condizioni e una
  carta per ogni famiglia: albero, reputazione, attività, origine con i suoi effetti, e un pulsante «Scegli
  come Casa Reale: Re/Regina …» per ogni adulto eleggibile.
- `FoundMonarchyCommand` → `CourtSystem.found_monarchy`: leggi di default, poteri, **legittimità iniziale
  dall'autorità raggiunta**, spinta dell'origine, «Casa …» con stemma nuovo, il sovrano è **la persona
  scelta** (con consorte e figli nella corte), «Regno di …», rango `KINGDOM`, giorno dell'incoronazione.
- Il momento storico: una carta sopra la mappa con lo stemma, «Nasce il Regno di …», il primo sovrano e
  l'origine della casa, e il grido «Lunga vita al Re/alla Regina!»; il tempo si ferma finché non la si
  chiude. La colonna passa da LA COMUNITÀ (La mia comunità, Famiglie) a IL REGNO (Il mio regno, Corte).
- La cronaca registra arrivo, prime famiglie, primo figlio, prima casa, primo raccolto, il villaggio, la casa
  scelta, l'incoronazione e la nascita del Regno. Le voci `founding_*` **non vengono mai potate** e hanno il
  colore d'oro nella scheda Cronaca.

**Salvataggi**: versione 5. Famiglie, legami, autorità, origine e giorni della fondazione passano il
salvataggio; i salvataggi della versione 4 si caricano come regni già fondati; caricare una comunità non la
incorona (`found_courts` salta le comunità).

**Quel che la prova della crescita ha scoperto (e corretto)**
Far crescere sei persone fino a un villaggio ha messo a nudo quattro difetti che il vecchio avvio nascondeva
(il re non partiva mai, e c'erano 150 legna e 90 pietre):
1. **La gente partiva con 130 giorni di cibo in deposito**: la valvola dell'emigrazione misura se le scorte
   arrivano al raccolto, ma il giocatore vedeva solo «cibo 130 giorni». Ora c'è un'unica misura,
   `PopulationSystem.harvest_outlook`, usata dall'emigrazione, dalle condizioni del Regno e dalla fascia alta:
   il grano diventa giallo o rosso quando il cibo non arriva al raccolto, e il suggerimento dice quanti il
   granaio porta fino alla mietitura.
2. **Il consiglio sbagliato**: il limite non erano i campi ma il **deposito** — il fuoco comune tiene 450
   misure, meno di un anno di cibo per più di dieci persone, e il raccolto andava perso. La misura sa quanti
   giorni di cibo i depositi possono contenere e dice «servono granai» invece di «servono campi»; la guida ha
   un passo nuovo, «Un granaio per l'inverno».
3. **Nessuno costruiva più**: la regola della Fase 13 («i campi prima dei cantieri») non mandava un solo
   costruttore quando i posti nei campi superavano gli adulti, anche con 400 giorni di pane. Ora, con mezzo
   anno di cibo in deposito, un quarto degli adulti può lasciare i campi per i cantieri
   (`builders_from_fields_food_days`), richiamato dai mestieri che la priorità mette per ultimi.
4. **Una comunità può estinguersi**: senza il re che restava, un villaggio affamato si svuota del tutto. La
   fine è registrata, scritta in cronaca e raccontata da una carta che porta al menù (o lascia guardare la
   valle vuota); il consenso di un luogo vuoto non si ricalcola più da solo.

Nella valle di partenza la roccia affiorante più vicina è a ~565 m: una cava si apre a ~490 m, dentro il
territorio. Il giocatore può farlo; i pianificatori di prova ora cercano abbastanza lontano.

**Scenari di prova**: `--kd-scenario community_ready` (la comunità cresciuta fino alle condizioni del Regno,
con il «signore prudente» `SettlementPlanner.lord_month`) e `--kd-scenario coronation` (la stessa, incoronata a
interfaccia aperta).

**Guida** (v2): casa, campi, forno, granaio, prime famiglie, comunità che cresce, la casa per il Regno, la
prima legge davvero cambiata (`laws_changed`, non le leggi di default), sapere, armi.

**L'assimilazione non è più un tiro di dado**: con il malcontento al massimo la probabilità annua scendeva
all'1,5 % e una provincia straniera restava tale per sessant'anni una volta su tre; la prova passava per la
fortuna della sequenza casuale, e il nuovo corso del mondo l'ha tolta. Ora la pressione culturale si
**accumula** (`ProvinceState.assimilation` e `conversion`, salvate) e la provincia cambia lingua o fede
quando il conto arriva a 1: al peggio 50 anni per la lingua, 71 per la fede, prima con sviluppo e vicini della
stessa cultura (`assimilation_base` 0,04). Aperto: il conto non si azzera se la provincia passa a un altro
signore straniero.

**Quel che gli screenshot hanno scoperto (e corretto)**
- Le schede si misuravano prima che i contenitori avessero calcolato quel che vi era appena stato scritto: la
  scheda Famiglie, costruita al primo aggiornamento, restava alta due righe per un secondo. `KDSheet._fit` ora
  si ripete a fine frame, anche quando `PanelHost` apre una pagina.
- La carta della guida copriva l'angolo in basso delle schede: ora aspetta sotto finché una scheda è aperta.
- Le spunte delle condizioni uscivano viola (il carattere ✔ passava al font delle emoji): ora ✓ e ✗.
- Avviando la partita direttamente dalla scena principale, l'HUD non conosceva ancora lo stato della corona
  e scambiava l'incoronazione per un caricamento, senza carta. Ora lo impara al primo frame.

**Verifiche eseguite**
- Nuove prove in `tests/unit/test_founders.gd` (10): fondatori che si uniscono e figli con madre, padre e
  famiglia; la corona che aspetta le sue condizioni e rifiuta leggi e fondazione con la stessa ragione della
  scheda; una comunità governata con prudenza che raggiunge le condizioni, sceglie la casa e diventa Regno
  (casa, origine, sovrano = persona scelta, legittimità dall'autorità, cronaca, prima legge, tre anni dopo
  ancora un sovrano); fondazione attraverso il salvataggio (comunità e regno); salvataggi v4 caricati come
  regni; estinzione; voci della fondazione mai potate; la guida dai fondatori alla prima legge; schede della
  comunità e carta dell'incoronazione.
- Le prove che davano per scontato un re al giorno zero sono state adeguate: dove studiano la corte, le leggi
  o l'assimilazione incoronano il giocatore con `KDTestCase.crown_player`; dove descrivono l'avvio ora
  controllano i sei fondatori.
- Schermate: `tests/output/p15_start.png` (l'avvio: LA COMUNITÀ, Fiducia, Autorità, Famiglie),
  `p15_families.png` (NESSUN SOVRANO, le condizioni, le carte delle famiglie), `p15_coronation.png` (la
  nascita del Regno).
- Nella prova di crescita la comunità supera i 30 abitanti fra il terzo e il quarto anno e raggiunge tutte le
  condizioni dopo almeno due anni; il villaggio di vent'anni arriva a 34 abitanti.

**Completamento dopo la rilettura del brief** (secondo commit della fase)
Rileggendo il brief punto per punto sono emersi tre punti coperti solo in parte:
- **§15.1 — rocce vicino ai fondatori**: la roccia più vicina era a 565 m. La scelta del sito pesa ora la
  pietra raggiungibile a piedi (entro ~450 m): il fuoco nasce a ~120 m dalla roccia e ~60 m dall'acqua, con la
  stessa fertilità, e una cava sta a pochi passi. La partita si apre con la carta **«Sei persone e una
  valle»**: «Non possiedi ancora un Regno. Hai soltanto sei persone e un territorio da trasformare.», con i
  nomi dei sei; il tempo aspetta che la si chiuda, e non torna dopo un caricamento.
- **§15.2 — acqua e sentieri** entrano nella guida (ora 12 passi: casa, campi, acqua, forno, granaio,
  sentieri, famiglie, comunità, casa per il Regno, prima legge, sapere, armi).
- **§15.4 — niente corona prima della corona**: gli eventi hanno la condizione `crowned` (il nobile ribelle e
  il pretendente aspettano un regno; legittimità e ordine non esistono per una comunità) e i testi comuni
  usano `{corona}`/`{regno}`, che diventano «la comunità» prima dell'incoronazione (`Events.words`); un
  effetto di legittimità su una comunità muove la sua autorità. «Leggi e governo» si chiama
  **Consuetudini** e racconta come decide la comunità, senza mostrare leggi di successione; le leggi
  arrivano con la corona.
- Prove: `test_founders.gd` passa a 14 (sito, eventi, consuetudini, carta d'apertura). Schermate
  `p15_intro.png` e `p15_start.png` (Consuetudini).

**Resta aperto, dichiarato (per le fasi successive)**
- Nelle partite di prova quasi tutte le famiglie risultano «contadini»: all'inizio quasi tutti lavorano nei
  campi. Le origini vanno bilanciate con le campagne complete (Fase 16).
- I regni vicini propongono il vassallaggio anche a una comunità senza corona: è coerente (una comunità
  debole attira protettori), ma la diplomazia verso le comunità va rivista con il bilanciamento.

---

## FASE 16 — Bilanciamento e campagne complete ✅

Il brief chiede di provare **campagne intere**, non sistemi isolati. Per farlo c'è ora un banco di prova:
`tests/campaign/` — un giocatore automatico prudente (`CampaignPilot`) che gioca da sei fondatori a un regno,
senza trucchi (solo comandi che il giocatore potrebbe dare, rifiutati per le stesse ragioni), e un runner che
scrive una riga per anno (`tests/output/campaign/<etichetta>_<seme>.csv`) e un rapporto con i controlli del
brief: tappe della curva di crescita, crescita bloccata o esplosiva, misure inchiodate al massimo, scorte
inutili, tesoro, regni vivi, il più grande, guerre, anni senza guerre.

```
godot --headless --path . res://tests/campaign/campaign_runner.tscn -- --kd-years=100 --kd-seeds=1,2,3 --kd-label=base
```

Il pilota: nel villaggio il «signore prudente» del gioco (`SettlementPlanner.lord_month`); prima della corona
sceglie la famiglia con la reputazione migliore appena le condizioni sono vere; dopo, per il regno usa lo stesso
cervello delle corone dell'IA (`RealmAiSystem.take_turn`, `ResearchSystem.ai_adopt`); risponde agli eventi come
il sovrano che regna e non mette mai la propria corona sotto tributo o vassallaggio.

**Che cosa hanno trovato le campagne, e come è stato corretto**

Il primo giro era un disastro istruttivo: la comunità si estingueva nel secondo anno. Poi, una correzione per
volta:

1. *Il pilota metteva il granaio prima dei campi* e restava senza legna per la fattoria. Il signore prudente è ora
   una **lista di desideri in ordine** (campo, bosco, tetto, forno; poi forni, granai, campi, case, boschi e cave
   quando mancano i materiali) e costruisce il primo che si può davvero pagare e piazzare.
2. *Sei fondatori soli si dividevano*: la valvola del raccolto faceva partire gente anche da una comunità di sei.
   Sotto i 12 abitanti (`harvest_valve_min_people`) si resta e si raziona; parte solo chi salta davvero i pasti.
3. *Provviste iniziali*: con 155 giorni di cibo la comunità moriva di fame nel secondo anno, perché il primo
   raccolto, seminato in fretta, rende poco. Ora i sei arrivano con grano e pane per arrivare al secondo.
4. **Fame con il granaio pieno**: `food_days` contava tutto il grano come pane cotto. Un villaggio di cinquanta
   con un forno «vedeva» 230 giorni di cibo e ne aveva un centinaio: 57 morti in un anno. Ora il grano vale pane
   solo per quanto i forni, con i fornai che ci lavorano davvero, riescono a cuocere (`PopulationSystem._ovens`);
   il pilota costruisce un forno in più quando servono.
5. **Nessuno lavorava più alla cava**: tutti finivano nei campi. Con il granaio al sicuro un posto di lavoro vuoto
   richiama una persona da un campo che ne ha due.
6. **Le terre libere non si potevano prendere**: le province cambiavano padrone solo con la guerra, e 300 terre
   libere restavano tali per sempre. Nuovo `ClaimProvinceCommand` (**annessione pacifica** di una terra libera
   confinante: oro, legittimità minima, pace, due anni fra un'annessione e l'altra), usato anche dall'IA; nella
   scheda della provincia ci sono ora i pulsanti «Annetti al regno» e «Migliora le terre» (lo sviluppo non aveva
   un pulsante).
7. **Le province non rendevano nulla**: un abitante di provincia valeva 0,001 ori al mese, ottocento volte meno di
   uno del villaggio. I regni dell'IA, che vivono solo di rendite, erano senza un soldo e restavano fermi per
   decenni. Ora rende circa 0,02, e l'amministrazione se ne mangia una parte che cresce con la grandezza del regno
   (`administration_share`): il limite morbido dell'espansione.
8. **Commercio**: le eccedenze oltre una riserva si vendono al prezzo del mercato del regno (il cibo solo con un
   anno di scorte che arrivano al raccolto); pietra, legna e ferro che mancano si comprano, più cari. Le rocce
   vicine si esauriscono davvero, e senza questo un regno restava senza pietra per decenni.
9. **Il giocatore diventava vassallo di due regni insieme**, e i tributi gli svuotavano le casse. Una comunità
   senza corona non firma trattati; nessuno paga due signori (`Diplomacy.pact_blocker`).
10. **L'ordine crollava a 0 per quarant'anni**: con l'ordine sotto 55 l'IA proclamava il coprifuoco ogni mese, e
   ogni proclamazione si sommava alla memoria permanente dei ceti. Un editto ora dura una stagione e poi **riposa
   sei mesi**, e non lascia rancori permanenti come una legge.
11. **Misure inchiodate**: l'ordine di un regno piccolo stava a 100; ora la base è 90 e ogni provincia oltre la
   quinta toglie un poco. Il favore di un ceto sopra 75 cresce a metà velocità.
12. **L'oro si accumulava senza fine** (190.000 ori): una corona ricca fa più di una cosa al mese — sviluppa,
   annette, legifera.
13. *Il pilota non faceva ricerca*: ora adotta il sapere come le corone dell'IA.
14. **Il prestigio si ricalcolava da zero ogni settimana**: le imprese (battaglie, annessioni, eventi) sparivano il
   giorno dopo, e cresceva senza limite con gli edifici. Ora è terre + edifici + legittimità + **memoria delle
   imprese** (che sbiadisce del 5% l'anno), su una curva che si avvicina a 100 senza toccarlo
   (`CourtSystem.add_prestige`).
15. Il grano si vende anche da **granai pieni** (quindicimila misure marcivano per decenni); il ferro si compra solo
   se una bottega lo usa.
16. **Oro senza scopo**: dono della corona a un ceto (`GiftFactionCommand`, dalla scheda Ceti e dall'IA ricca),
   **manutenzione degli edifici** in oro (1,5% al mese del valore dei materiali), mercato meno profondo, e un esercito
   dell'IA che cresce con il regno (e che una corona ricca tiene anche in pace).
17. La prima suite completa sul codice della fase ha trovato sette regressioni: un villaggio piccolo moriva di fame
   perché l'esenzione dalla valvola del raccolto valeva fino a 12 abitanti (ora solo per i sei fondatori), e le prove
   di tributo e paghe davano per scontato un regno povero (ora misurano il meccanismo).

**Verifica finale** (tre campagne da 80 anni, semi 1–3, dopo i punti 1–15):
- corona al 4°–7° anno; 500 abitanti fra il 9° e il 12° anno, 1000 fra il 15° e il 18°, 5000 intorno al 55°;
  a fine campagna 4.600–8.700 abitanti in 20–37 province. Il periodo più lungo senza superare il proprio massimo
  è di 1–7 anni: la crescita non si blocca e non esplode (i salti annui del 200–600% sono annessioni di terre
  già popolate, non crescita incontrollata).
- **nessuna misura inchiodata al massimo** in nessun seme.
- mondo: 16–17 regni vivi su 17; il più grande (sempre un regno dell'IA, 38–43 province) tiene il 14–16% delle
  terre possedute; 31–72 guerre dichiarate; mai più di 10 anni senza una guerra nuova nel mondo.
- restava l'oro accumulato (130–200 mila): punto 16, verificato con una campagna da 40 anni (crescita e prove di
  economia intatte). Resta un tesoro abbondante nei regni maturi: il pilota usa una sola decisione principale al
  mese, e la spesa di un giocatore umano (eserciti, sviluppo di tutte le province) è più libera.

**Resta aperto, dichiarato**
- Le campagne sono lente (20–30 minuti per 80 anni con tre in parallelo): la Fase 19 (prestazioni) parte da qui.
- 10.000 abitanti non si raggiungono in 80 anni: il mondo intero ne ha circa 110.000, e un regno che ne tiene un
  decimo è già il più grande. «Decine di migliaia» richiedono un secolo e mezzo o la conquista.
- Ferro e armi restano quasi inutilizzati dal pilota (non costruisce miniere e fucine); per il giocatore servono a
  reclutare.

---

## FASE 17 — Contenuti, varietà e rigiocabilità ✅

Obiettivo del brief: una seconda, terza e quinta partita non devono raccontare la stessa storia.

**Eventi** (17.1): da 14 a **57**, in undici categorie (economia, famiglie, dinastia, sovrano, guerra, diplomazia,
fede, cultura, terra, crisi, popolazione), quasi tutti **condizionali**: 24 condizioni nuove leggono ciò che il regno
è davvero — anni di storia, famiglie della capitale, tratti ed età del sovrano, erede adulto/bambino/assente,
reggenza, patti in vigore, favore dei ceti sopra/sotto una soglia, edifici della capitale, fiume/montagna/bosco della
capitale, province di altra cultura, guerre combattute, spiriti, crisi in corso. Effetti nuovi: autorità della
comunità, arrivo di coloni (`PopulationSystem.welcome`), partenze (`send_away`). Le **catene** ora arrivano quando
arriva il loro tempo (gli usurai tornano un anno dopo il prestito, non lo stesso giorno) e un seguito non arriva mai
da solo. La carta dell'evento mostra la categoria.

**Sovrani** (17.3): da 12 a **22 tratti**, con le **opposizioni** (un sovrano non è più insieme avaro e generoso) e
l'**eredità** (un figlio prende un tratto da un genitore nel 40% dei casi: le casate hanno un carattere che dura).
I tratti muovono i pesi decisionali dell'IA: un cambio di sovrano cambia la politica del regno. Sei **eventi
personali** nascono dal carattere di chi regna (il banchetto dello scialacquatore, il duello dell'impulsivo, le notti
insonni del sospettoso, il libro del colto, il ponte del costruttore, il voto dello zelante).

**Spiriti nazionali** (17.2): da 15 a **32**. Uno spirito ora può migliorare, peggiorare, trasformarsi, ramificarsi,
tornare indietro (la frontiera pacificata torna frontiera con una guerra) e **scomparire** (`"to": ""`: i boschi
ricrescono, una carestia si dimentica dopo 25 anni, i debiti si pagano). Otto spiriti si **guadagnano con le
azioni** in qualunque momento (commercio, battaglie, leggi, sapere, terre annesse, sovrani della casata, patti, e il
regno indebitato), fino a sei spiriti per regno.

**Obiettivi** (17.4): da 5 a **11**, in dieci campi — capitale, territorio, dinastia, ricchezza, sapere, commercio,
guerra, diplomazia, cultura, stabilità (il più lungo periodo di anni con ordine e legittimità da 60 in su). La
conquista non è l'unica strada.

**Cronaca** (17.5): oltre a fondatori, famiglie, incoronazioni, successioni, guerre, battaglie, conquiste, patti e
spiriti, ora registra il **primo edificio importante** di ogni genere, le **tappe** della crescita del villaggio (50,
100, 200, 400 edifici), l'**inizio delle crisi**, le **rivolte** (ordine sotto 18) e la loro fine.

**Difetti trovati lungo la strada**: `last_war_day` era letto dagli spiriti ma mai scritto (gli «anni di pace»
contavano anche le guerre); le catene di eventi scattavano lo stesso giorno.


**Verifica della fase (campagne da 60 anni, semi 4–6) e dettagli corretti**
- *Rigiocabilità*: nelle tre campagne 30 dei circa 36 eventi vissuti erano comuni a tutte (in sessant'anni capita
  quasi tutto ciò che può capitare); i sovrani e i loro eventi personali invece cambiavano. Aggiunto il **destino
  della campagna** (`Events.weight_in_campaign`): ogni evento pesa fra un quarto e quasi il doppio del suo peso,
  deciso dal seme della partita — una valle di piene, una di briganti, una di fiere.
- *Mondo troppo pacifico*: dopo i tratti nuovi le guerre erano scese a 7–18 in 60 anni, con 39 anni senza una
  guerra in un seme: tutte le corone annettevano terre libere. Aggiunta la **fame di terra** (una corona senza terre
  libere ai confini sente di più la guerra) e un margine di forza richiesto più basso (1,15).
- **Nulla nel fiume**: la maschera dell'acqua ha celle da 32 m e un fiume largo dieci cadeva fra una cella e l'altra —
  un pozzo nel fiume, una strada che partiva dall'acqua, un granaio sulla riva. Nuovo `WorldData.river_clearance`
  (distanza dal bordo del fiume come è disegnato, riva compresa, su un indice a celle da 128 m): lo usano il
  piazzamento degli edifici (`Placement.touches_river`), le strade, gli alberi, i cespugli, le rocce e la scelta del
  sito dei fondatori (a 40 m dalla riva almeno; la ricerca del sito ora si affina ogni 16 m attorno ai candidati
  migliori, per non perdere la roccia). Prove in `tests/unit/test_river.gd`.
- **Notizie di corti straniere**: nozze, eredi, sovrani morti, reggenze, leggi, editti e spiriti dei regni dell'IA
  arrivavano al giocatore come notifiche. Ora vanno solo nella cronaca.

**Resta aperto (per le fasi seguenti)**
- Gli spiriti nazionali del giocatore tendono a somigliarsi fra una partita e l'altra: la valle di partenza è sempre
  la stessa (decisione D2) e il pilota gioca allo stesso modo; un giocatore umano li differenzia con le sue scelte.
- Eventi di crisi (complotto, rivolta fiscale, veterani senza paga, usurai) non sono mai capitati al pilota, che tiene
  il regno stabile: sono verificati dalle prove, non dalle campagne.
- Il ruscello più piccolo, da vicino, si vede come una linea sottile (Fase 18).

---

## FASE 18 — Grafica definitiva e HUD ✅ (con lavoro dichiarato aperto)

Divisa in otto passi, come chiesto: **18A** audit · **18B** mappa · **18C** insediamenti · **18D** abitanti ed
eserciti · **18E** layout della HUD · **18F** schede e tipografia · **18G** tooltip, icone, eventi, notifiche ·
**18H** coerenza e confronto. Audit con KEEP/IMPROVE/REPLACE/REMOVE in `VISUAL_POLISH_AUDIT.md` (sezione 18A,
diciassette schermate standard `p18a_*`); confronto prima/dopo con le stesse inquadrature in
`VISUAL_POLISH_REPORT.md` (`p18h_*`).

**18B — Mappa.** Bosco a zoom medio con radure, nuclei fitti e gruppi di chiome dello stesso tono (non più una
carta da parati); cespi tenuti lontani dagli edifici; tre stili di strada (sentiero, sterrata, via maestra) con
bordi irregolari; una provincia con un insediamento non ripete il suo nome con un secondo segnaposto.

**18C — Insediamenti.** Nuovo livello `SettlementMarks`: fra 2,2 e 40 m/px ogni edificio vero è un blocco
leggibile (tetti, campi di stagione con i solchi, mastio) sopra la terra battuta, così la crescita del luogo si vede
dall'alto. Mastio della casa reale alzato all'incoronazione; sentieri battuti fra le porte; orti recintati accanto
alle case; segnaposto sopra l'abitato e targa dipinta del nome sotto (prima la targa non compariva mai).

**18D — Abitanti ed eserciti.** Figure in scala (minimo leggibile, mai giganti), un punto colorato per mestiere
quando la figura sarebbe rumore; schiere in blocchi per reggimento con il pennone, in colonna o in linea; il
vessillo lontano porta il numero di uomini.

**18E — Layout.** Menu sinistro con Regno, Corte, Governo, Religione, Esercito, Diplomazia, Economia, Ricerca,
Mappa; barra bassa su una riga con Costruire, Abitanti, Ceti, Cronaca; nessuna scheda in due posti. Lista degli
edifici solo in modalità costruzione (tasto B), scostata dall'orologio; notifiche sul bordo destro che si spostano
quando la colonna è aperta; minimappa ritagliata.

**18F — Schede.** Nome e croce nella fascia dipinta della cornice (erano un secondo riquadro); nuova scheda
**Religione**; scheda Esercito coerente con le altre (barre di sezione, pennoni, altezza sul contenuto); legge in
vigore scritta in Governo; caselle dipinte al posto di `✓`/`✗`; in Economia il saldo mensile di ogni deposito.

**18G — Tooltip, eventi, notifiche.** Registro vero delle scorte (`SettlementState.flow/last_flow`, per merce e
motivo, salvato) e componenti delle misure (`KingdomState.measure_parts`): ogni numero della barra alta dice da dove
viene, in tooltip ricchi a due colonne (`KDTip`). Notifiche: al massimo quattro, con l'icona del tipo, le minori su
una riga. Carta evento con categoria nella fascia, emblema e conseguenze scritte e colorate. Lista edifici con
immagine, costo a icone, stato e tooltip. Via i glifi `✕ ❙❙ →`.

**18H — Coerenza.** Stessa lingua visiva per tutti i riquadri e gli stessi colori per i segni. Proporzioni 21:9 e
4:3 provate; 1440p e 4K **non apribili su questo monitor 1080p** (Godot limita la finestra allo schermo): la scala
per costruzione (`canvas_items`, base 1920×1080) le rende identiche alla 1080p, verificato solo per ragionamento e
con il test delle colonne fino a 2560 px.

**Prove.** Nuovo `tests/unit/test_visual.gd` (5 prove: orti, sentieri, bande di zoom, radure, notifiche);
`test_ui.gd` da 11 a 14 prove (menu senza doppioni sulle liste vere della HUD, Religione, costruzioni solo in
modalità costruzione, registro delle scorte e tooltip). `tools/check.ps1 -EngineArgs` passa opzioni al motore;
`--kd-panel=build` e `--kd-tip=<pastiglia>` servono alle foto.

**Revisione della HUD sul disegno di riferimento (25/09/2026).** Su richiesta, il layout è stato rifatto
seguendo posizioni e ingombri di un disegno di riferimento: fascia superiore continua con stemma, sette merci
(icone da 32 px, numero, variazione del mese) e le grandi misure con il loro nome; orologio compatto sotto la
sua estremità destra (data, velocità, mappa, menu); a sinistra quattro piastre grandi (Il mio regno,
Corte, Governo, Costruzioni); a destra, impilati, le Notizie (con «Vedi tutto» per la cronaca) e il pannello
Costruzioni quando serve; in basso una barra larga con Esercito, Ceti, Ricerca, Economia, Diplomazia,
Religione; in basso a sinistra la Mappa del mondo con il menu delle mappe. Abitanti e famiglie si aprono da Il
mio regno; il sapere si legge sul tooltip di Ricerca. Testo più grande (minimo 13, righe a 15), margini delle
cornici corretti, barre di scorrimento più visibili. Dettagli in `VISUAL_POLISH_REPORT.md`.

**Resta aperto (dichiarato)**
- Tipografia: font di sistema; un font medievale va scaricato e aspetta il permesso esplicito.
- Nessun edificio «speciale» costruibile esiste ancora: la categoria non è mostrata vuota.
- I ruscelli più sottili da vicino restano una linea.
- Rilevato dai nuovi tooltip, da guardare in Fase 19: nel primo anno del regno la corona può spendere in acquisti
  di materiali più di quanto incassa (saldo mensile negativo nello scenario `kingdom`).

---

## Passaggio artistico del mondo (dopo la Fase 18) ✅

Richiesto dal giocatore: «la simulazione può essere matematica, la rappresentazione no». Nessuna meccanica, nessun
salvataggio, nessuna posizione logica cambiata; tutto il nuovo disegno è deterministico (id o posizione).
Audit in `WORLD_ART_AUDIT.md`, prima/dopo e misure in `WORLD_ART_REPORT.md` (foto `wa0_*` → `wa9_*`).

- **Passo 1 — geometria**: ogni edificio leggermente spostato, ruotato e scalato (solo il disegno); campi a
  2–4 strisce con colture, prode, bordi irregolari, sei stati per mese; pianificatore del pilota a zone (piazza e
  case, distretto agricolo, laboratori in mezzo, taglialegna verso il bosco); strade e sentieri che curvano e si
  allargano col traffico; bosco con nuclei, vere radure e margini frastagliati (stesso numero di alberi entro l'8%).
- **Passo 2 — ambiente**: macchie ampie del prato; riva che cambia (ghiaia, fango, sabbia) con erba umida,
  canneti e sassi; margine sfruttato del bosco attorno agli insediamenti; piazza che cresce, sentiero al fiume;
  26 oggetti di scena per contesto e bancarelle sulla piazza dei borghi; cinque case, due cascine, varianti.
- **Passo 3 — profondità**: mipmap sugli atlanti del mondo; ombre che seguono gli edifici; tinta per persona.
- **Passo 4 — scala**: verificato su 6, 30, ~100, ~300 abitanti e a zoom medio.
- **Prestazioni**: FPS medi 112,8 → 123,0 sopra il villaggio, 119,5 → 140,3 sul continente; draw call massime
  2289 → 1960. Trovato e corretto un difetto vecchio: la HUD si ricalcolava a ogni segnale dell'insediamento, e
  una cittadina di trecento abitanti perdeva un fotogramma di 246 ms ogni giorno di gioco (ora 11,6 ms).
- **Prove**: `test_visual.gd` da 5 a 7 (determinismo del disegno dopo un caricamento, forma e alberi del bosco);
  suite completa verde, test di stress 344 s su 400.
- **Strumenti**: `--kd-save-to`/`--kd-load` (mondi di prova in `tests/output/world_saves/`),
  `--kd-camera=home,dx,dy,mpp`, `--kd-benchmark --kd-bench-home` con draw call, memoria, fotogramma peggiore e
  tempi dei sistemi, `--kd-hide-layers` per profilare.

**Resta aperto**: ponti e guadi (la meccanica non esiste), fotogrammi lenti al passaggio fra bande di zoom e sopra
una cittadina osservata da vicino (Fase 19).

---

## FASE 19 — Prestazioni, bug e robustezza ✅

Tutto il dettaglio (tabella dei bug, stress test, misure, salvataggi) in `ROBUSTNESS_REPORT.md`. Regola seguita:
prima si misura, poi si cambia, poi si rimisura; ogni ottimizzazione della simulazione è stata verificata con una
traccia mese per mese della stessa campagna (codice vecchio contro codice nuovo: identica).

- **19.1 Stress test** (`tests/stress/stress_runner.tscn`, mondi fatti solo con le funzioni del gioco): città da
  1000 e 2000 abitanti, 120 cantieri insieme, 63 eserciti e 19 guerre, tutti i patti possibili fra tutti i
  regni, 150 anni col pilota automatico. Dopo ogni prova un controllo di coerenza del mondo e un salvataggio.
- **19.2 Misure**: simulazione per sistema e per voce (strumentazione temporanea, poi tolta), renderer con
  `--kd-benchmark` (fps per fascia di zoom, fotogramma peggiore, draw call e dove, nodi, memoria).
  Città da 1000: giorno guardato da vicino 1798 → 233 ms, giorno per aggregato 94 → 43 ms, un anno dopo 85 → 37;
  città di stress da 1500 col renderer 91 → 124 fps (da vicino 79 → 136). Campagna di 150 anni: memoria piatta
  (98 → 105 MB), salvataggio finale 151 KB che torna in 46 ms.
- **19.3 Bug**: nessun BLOCKER; corretti tutti i CRITICAL e MAJOR trovati — cache della partita precedente dopo un
  caricamento (già nel world art pass), salvataggio non atomico, **la pace poteva cedere all'IA il villaggio del
  giocatore** (ora la sede della corona si può occupare ma nessun trattato la cede), **eserciti di regni caduti
  ancora in guerra**, F9 che lasciava in scena la partita vecchia, «Depositi pieni» ogni giorno, quattro difetti di
  prestazioni gravi (capienza dei depositi, oziosi che camminavano sul posto dieci volte l'ora, liste degli alberi
  buttate a ogni ricrescita, disegno degli abitanti); più i MINOR e COSMETIC elencati nel rapporto.
- **19.4 Salvataggi**: nuovi, vecchi (fixture della build della Fase 18), rotti, autosalvataggio, menu, pausa, F9,
  tutorial, monarchia, sei fondatori: tutto verificato con test o strumenti.
- **Prove nuove**: `test_save` (vecchia build, file rotto), `test_menu` (autosalvataggio col giorno saltato),
  `test_settlement` (depositi pieni una volta al mese), `test_war` (sede del giocatore nei trattati, regno caduto);
  `quickload_check.tscn`; `check.ps1` più severo sugli errori; `--kd-test=a,b` per i test in sequenza.
- **Scenari nuovi**: `--kd-scenario=stress_city [--kd-people=N]`, `--kd-scenario=stress_war`, `--kd-no-autosave`.

- **Verifica**: suite completa 206 test, 10 012 asserzioni, 0 fallimenti, in 16 minuti (prima 46); `test_stress`
  (60 anni) in 208 s, da solo e in suite con lo stesso identico mondo. Dopo le ultime tre correzioni della
  simulazione ora per ora (risveglio scaglionato anche quando la telecamera torna nello stesso giorno, prenotazioni
  liberate al risveglio, al massimo 6 liste di alberi per ora) rieseguiti `test_settlement`, `test_economy`,
  `test_founders`, `test_visual`: 37 test, 0 fallimenti.

**Resta aperto**: una schermata di sconfitta vera (oggi la sede della corona non si può perdere per trattato);
il primo disegno di mille edifici quando la telecamera entra nella fascia ravvicinata (56 ms una volta, solo in
città oltre ogni campagna vista); le famiglie estinte restano nel registro.

---

## Consolidamento dei sistemi (dopo la Fase 19) ✅

Richiesto dal giocatore: «non un gioco più semplice, un gioco più chiaro» — meno sistemi che raccontano la stessa
cosa, meno menu allo stesso livello, meno micro-modificatori, stessa profondità. Audit con le misure in
`SYSTEM_CONSOLIDATION_AUDIT.md` (KEEP / MERGE / SIMPLIFY / REMOVE / TRANSITIONAL), esito in
`SYSTEM_CONSOLIDATION_REPORT.md`. Nessuna meccanica importante tolta, i salvataggi vecchi si aprono tutti (v6).

- **Indicatori**: **Stabilità** è l'unico indicatore di tenuta interna (era «Ordine», e una chiave «Stabilità»
  spostava in realtà la fiducia della gente); **Fiducia** è l'unico nome del rapporto fra gente e governo (era anche
  «consenso» e, nel codice, `happiness`); l'**Autorità** della comunità è transitoria e all'incoronazione fonda
  la prima Legittimità e la prima Stabilità; Prestigio e Legittimità invariati.
- **Famiglie → Ceti**: le famiglie vivono nel loro ceto (dedotto dal lavoro; dopo la corona la casa reale a parte,
  la nobiltà fatta delle poche casate più influenti e delle imparentate con la corona); la scheda Ceti mostra prima
  la comunità con le famiglie e la scelta della casa reale, poi i cinque poteri con le famiglie di spicco. Niente
  più tasto «Famiglie»: la Corte compare con la corona e mostra solo il sovrano, la legittimità della casata, gli
  eredi. «Mercanti» diventa «Mercanti e artigiani». Condizioni del Regno e Casa reale in La mia comunità / Il mio
  regno; il clero nella Religione è solo il suo peso sulla legittimità, il resto nei Ceti.
- **Spiriti**: al massimo 4 insieme (erano 6), effetti percepibili. **Modificatori**: da 16 minuscoli a 0.
- **Cronaca**: la storia, non il traffico — ciò che tocca il giocatore (senza i rinnovi dei patti minori e le fortune
  ordinarie degli eventi), degli altri regni solo ciò che cambia il mondo. In 40 anni: prima 600 righe al tetto, 47
  del giocatore; ora 178, 96 del giocatore, e la storia intera ci sta.
- **Mappa**: quattro modalità principali, le altre in «Altre mappe». **Economia**: «Cosa manca» in cima, lavoro in
  una riga, prezzi chiusi. **Il mio regno**: le crisi in corso (erano nella Ricerca), la formula chiusa.
- **Eventi**: le scelte che valevano ±1 ora hanno conseguenze.
- **Prove**: `test_save` (migrazione v5 → v6 sulle fixture della Fase 18 e su una crisi), `test_founders` (ceti delle
  famiglie, schede della comunità e della corte), `test_politics` (cronaca), `test_ui` (menu mappe, crisi), altri
  test aggiornati ai nomi nuovi.

- **Verifica**: suite completa 210 test, 10 083 asserzioni, 0 fallimenti; `test_stress` (60 anni) in 239 s su 400,
  cronaca di 289 righe invece di 600 al tetto. Schermate controllate: Ceti prima e dopo la corona, Il mio regno,
  Economia, menu di sinistra senza «Famiglie».

