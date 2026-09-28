# KING'S DOMAIN — TECHNICAL ARCHITECTURE

Motore: **Godot 4.7.2** (GDScript tipizzato). Grafica 2D semplice (vedi §11). Asset: script Python/numpy, **Blender 5.2** solo per silhouette essenziali
(Python eseguito con l'interprete incluso in Blender). Versionamento: **Git**.
Documento di riferimento per ogni scelta tecnica; aggiornarlo quando una scelta cambia.

---

## 1. Principi tecnici

1. **Un mondo, un orologio, due spazi** (Rebirth, Fase 1 — sostituisce «un sistema di coordinate»). La simulazione è
   una sola; le posizioni vivono in due spazi in metri: la **valle della patria** (insediamenti, edifici, abitanti,
   alberi, rocce: `DomainState`/`DomainData`) e il **continente** (province, regni, eserciti, battaglie: `WorldData`).
   La corrispondenza è una regola sola (`DomainState.to_global/to_local`, `WorldState.settlement_global_pos`).
   Due mappe (`scenes/local/local_view.tscn`, `scenes/global/global_view.tscn`) con camera, livelli e interazioni
   propri; nessuno zoom porta dall'una all'altra. Dettagli in `KINGSDOMAIN_REBIRTH_AUDIT.md` §3.
2. **Simulazione separata dalla presentazione.** Lo stato di gioco è fatto di oggetti dati (`RefCounted`/`Resource`)
   senza nodi; i nodi Godot *leggono* lo stato e lo disegnano. La simulazione gira headless nei test.
3. **La telecamera non cambia l'esito.** Ciò che è lontano viene simulato in forma più economica ma con lo stesso
   modello (niente "effetto osservatore"): gli individui e i soldati visibili sono la rappresentazione di uno stato
   calcolato indipendentemente dalla vista.
4. **Dati fuori dal codice.** Definizioni e bilanciamento in `res://data/defs/*.json`, caricati in classi `Resource`
   tipizzate e validate. La mappa ufficiale in `res://data/world/`.
5. **Comandi unici per giocatore e IA.** Ogni modifica intenzionale allo stato passa da un `Command` con
   `validate()` (che restituisce il *motivo* del rifiuto, come i `perche()` di Regno) ed `execute()`.
6. **Salvataggi versionati e migrabili** fin dal primo giorno.
7. **Ogni fase termina con verifiche automatiche** (test headless + screenshot di controllo).

### 1.1 Le patrie generate (Rebirth, Fase 2)
- `data/domains/homelands.json` descrive la geografia **disegnata** di ogni patria (dimensioni, passi, fiumi, lago,
  colline, boschi, depositi, nomi); `tools/domaingen/generate_domains.py` (Python 3 + numpy, seme fisso) la
  costruisce in `data/domains/<id>/`: `height.bin` (float32, 8 m), `biome/canopy/moisture/temperature.bin`
  (uint8, 8 m), `water/coast.bin` (uint8, 4 m) e `domain_meta.json` (fiumi, lago, passi, depositi, sito di fondazione,
  cime illustrate del bordo, nomi). `--check` rigenera in una cartella temporanea e confronta al byte.
- `DomainData._load_homeland()` li carica con la stessa interfaccia di `WorldData`: la valle è **una provincia**
  (ogni campo asciutto appartiene alla provincia di casa), gli alberi seguono il `canopy` disegnato
  (`WorldData.designed_woods`: niente radure e margini aggiunti dal rumore del continente) e il terreno ha la roccia
  dove il pendio è ripido (`slope_rock` nello shader).
- Sulla mappa del mondo la patria sta **dentro** la sua provincia (`DomainState.for_homeland`: scala ridotta, centro
  sotto il nome del regno).
- `start_setup.json → player.homeland` sceglie la patria della nuova partita; `GameSession.create_new({"homeland":
  "none"})` ritaglia invece la valle dal continente (come i salvataggi della mappa unica).

### 1.2 Il nucleo della comunità (Rebirth, Fase 3)
- `Nucleus.lay_out()` (chiamato da `SettlementSetup`) posa quattro **edifici del mondo** non costruibili: il deposito
  (`camp_store`, sempre il primo edificio dell'insediamento: le scorte di partenza sono lì), il riparo, il
  **focolare** (`hearth`, esattamente in `SettlementState.center`) e il **punto d'acqua** (`water_point`, sulla riva
  più vicina entro `nucleus.water_reach_m`; assente se non c'è acqua). Deposito e riparo stanno dietro il fuoco, dal
  lato opposto all'acqua, su terreno che `Placement.check` accetta.
- Regola di piazzamento: nessun edificio (strade escluse) tocca il cerchio di `nucleus.square_radius_m` attorno al
  focolare del proprio insediamento.
- Comportamento (`SettlementSim`, solo con la simulazione per abitante): serata al fuoco (`_plan_evening`, posti da
  `Nucleus.seat`, azioni `sit`/`warm`), acqua (`at_water` → `draw_water` → `water_back` con l'azione `carry_water`),
  gli ozi del giorno che finiscono all'ora di fine lavoro (`_until_evening`). Nessuna risorsa «acqua» entra nelle
  scorte.
- Disegno: `NucleusLayer` (due nodi della scena locale: sotto le persone il fuoco, le panche e il pontile; sopra
  tutto il fumo e il gonfalone), `SettlementLayer` (piazzola, sentiero dell'acqua, primi sentieri), `PeopleLayer`
  (posa seduta, secchio). `NucleusLayer.soft_blob()` è la macchia sfumata con cui si timbrano terra battuta, fumo e
  bagliore.
- Salvataggi: versione 8; `SaveMigrator._v7_to_v8` aggiunge focolare e punto d'acqua alle comunità che ne erano prive.

### 1.3 La crescita organica (Rebirth, Fase 4)
- `Siting.refine(world, settlement, def, cursor, radius)` sceglie il posto di un edificio attorno a un punto: griglia
  di candidati (2 m, più rada per i raggi grandi; i campi un poco fuori griglia), scarto rapido (sovrapposizioni,
  piazzola, acqua), punteggio per **ruolo** (`Siting.role`: casa, bottega, magazzino, servizio, campo, bosco,
  pietra, miniera, militare) e **anello** attorno al focolare (`Siting.ring`, più largo con la popolazione), poi
  `Placement.check` sui migliori 16. Deterministico. Non cambia le regole né i comandi: il posto scelto va a
  `PlaceBuildingCommand` come prima.
- Le **vie** (`Siting.ways_of`): strade, sentiero dell'acqua, primi sentieri, sentieri battuti tra le porte
  (`SettlementLayer.footpaths`, ora in cache per `buildings_version`).
- Chi la usa: `BuildController` (il fantasma; Alt = posto esatto) e `SettlementPlanner.site_for` (villaggio di
  partenza e signore prudente; la ricerca ad anelli resta solo come ripiego).

---

## 2. Struttura del progetto

```
KING'S DOMAIN/                     ← PROJECT_ROOT (res://)
├─ project.godot
├─ README.md, GAME_DESIGN_MAP.md, LEGACY_SYSTEM_AUDIT.md, TECHNICAL_ARCHITECTURE.md,
│  DEVELOPMENT_PLAN.md, DEVELOPMENT_STATUS.md
├─ core/            clock, rng, event bus, scheduler, commands, modifiers, utilità, log
├─ world/           WorldState, dati del terreno, chunk locali, delta, query spaziali
├─ map/             rendering della mappa: terreno, acqua, confini, map modes, LOD, camera
├─ provinces/       ProvinceState, sistema province, adiacenze, controllo
├─ kingdoms/        KingdomState, misure della corona, identità del regno
├─ settlements/     insediamenti, crescita, layout
├─ buildings/       definizioni runtime, piazzamento, cantieri, rendering edifici
├─ population/      archivio popolazione, nascite/morti, lavoro, agenti visivi
├─ economy/         scorte, produzione, trasporti a flussi, mercati, tesoro
├─ characters/      personaggi, tratti
├─ dynasty/         dinastie, famiglie, successione
├─ government/      forma dello Stato, leggi, editti, riforme, corte, consiglieri
├─ factions/        fazioni interne
├─ culture/         culture (fisse)
├─ religion/        religioni (fisse)
├─ national_spirits/ spiriti nazionali dinamici
├─ diplomacy/       relazioni, patti, guerre
├─ military/        unità, reggimenti, eserciti, logistica, battaglie, assedi
├─ ai/              valutatore strategico, planner, utility scoring
├─ events/          eventi sistemici, crisi
├─ technology/      tecnologie e specializzazioni
├─ chronicle/       cronaca e obiettivi di campagna
├─ ui/              HUD e pannelli (componenti riutilizzabili, tema)
├─ save/            serializzazione, migrazioni
├─ scenes/          scene principali (Main, Boot)
├─ shaders/         shader 2D (terreno, acqua, confini, sprite)
├─ assets/          asset importati da Godot
│  ├─ environment/  alberi, rocce, montagne, texture di dettaglio del terreno
│  ├─ buildings/    sprite ed atlanti edifici
│  ├─ units/        soldati, cavalli, macchine
│  ├─ ui/           cornici, icone, font
│  └─ fonts/
├─ data/
│  ├─ defs/         JSON di definizione (edifici, unità, culture, religioni, spiriti, tratti, leggi, eventi…)
│  └─ world/        mappa ufficiale generata (raster binari, JSON province/confini/fiumi, setup iniziale)
├─ art_source/      (.gdignore) sorgenti non importate
│  └─ blender/      file .blend e scripts/ per il rendering degli sprite
├─ tools/           (.gdignore) script da terminale: worldgen Python, controllo progetto, screenshot
└─ tests/           test headless (runner + unit + integrazione)
```

Le cartelle con `.gdignore` non vengono importate da Godot.

---

## 3. Scala del mondo e coordinate

| Grandezza | Valore iniziale | Note |
|---|---|---|
| Unità mondo | **1 unità = 1 metro** | coordinate 2D Godot, y verso il basso = sud |
| Dimensione mondo | ~112 km × 72 km | geografia "compressa": gli edifici hanno scala reale, le distanze regionali no |
| Province | ~400, ≈ 3 km di diametro medio | una provincia contiene villaggi, campi, boschi, un castello |
| Raster macro | 64 m/cella (≈1750 × 1125) | altitudine, bioma, umidità, foresta |
| Raster province | 64 m/cella (1750 × 1125) | id provincia a 16 bit (confini visivi vettoriali levigati) |
| Raster acqua/costa | 32 m/cella (3500 × 2250) | tipo d'acqua + distanza con segno da mare e laghi |
| Griglia locale | 2 m/cella, chunk da 128 × 128 celle (256 m) | occupazione, alberi, rocce, campi, strade: **materializzata su richiesta** |
| Zoom camera | da ~50 m/pixel (continente) a ~0,05 m/pixel (soldati) | `Camera2D.zoom` da ~0,02 a ~20 |

Precisione: con float a 32 bit l'errore a 112 km è < 1 cm, sufficiente per il rendering 2D.
Tutti i valori sono in `data/world/world_meta.json` e `data/defs/balance/*.json`: nessun numero magico nel codice.

---

## 4. La mappa ufficiale (dati statici)

La mappa **non si genera in partita**. Uno strumento di sviluppo (`tools/worldgen/`) la costruisce una volta con
algoritmi deterministici; l'output viene revisionato, eventualmente ritoccato, e **committato** come mappa ufficiale.

### 4.1 File
| File | Formato | Contenuto |
|---|---|---|
| `world_meta.json` | JSON | dimensioni, risoluzioni, elenco raster, versione mappa, conteggi |
| `height.bin` | uint16 LE (zlib) | altitudine in decimetri, 64 m |
| `biome.bin` | uint8 (zlib) | indice bioma, 64 m |
| `moisture.bin`, `temperature.bin` | uint8 (zlib) | clima, 64 m |
| `forest.bin` | uint8 (zlib) | densità forestale 0–255, 64 m |
| `water.bin` | uint8 (zlib) | 0 terra · 1 mare · 2 lago · 3 fiume, 32 m |
| `province.bin` | uint16 LE (zlib) | id provincia (0xFFFF = acqua/nessuna), 32 m |
| `provinces.json` | JSON | per provincia: nome, centro, area, bioma, terreno, fertilità, risorse, cultura, religione, vicini (con tipo di confine: terra/fiume/guado/passo/montagna), costa |
| `rivers.json` | JSON | polilinee con larghezza per vertice e portata |
| `borders.json` | JSON | segmenti di confine fra coppie di province (polilinee levigate) |
| `deposits.json` | JSON | affioramenti di pietra, vene di ferro, argille, risorse speciali con posizione |
| `start_setup.json` | JSON | regni iniziali, capitali, province, insediamenti iniziali, luogo di partenza del giocatore |
| `albedo_far.png` | PNG | colore illustrato del continente per lo zoom lontano |

Caricamento: `FileAccess.get_file_as_bytes()` → `PackedByteArray.decompress()` → `Image.create_from_data()` → `ImageTexture`.

### 4.2 Generatore (`tools/worldgen/generate_world.py`)
Eseguito con il Python di Blender (numpy incluso):
```
"C:\Program Files\Blender Foundation\Blender 5.2\5.2\python\bin\python.exe" tools/worldgen/generate_world.py --out data/world
```
Passi: sagoma del continente (rumore con distorsione di dominio + vincolo "un solo corpo") → catene montuose
(curve guida + rumore a creste, con **passi** intenzionali) → altitudine → riempimento delle depressioni
(priority-flood) → direzione di flusso e accumulo → **fiumi naturali** e laghi → clima (latitudine, distanza dal mare,
venti, ombra pluviometrica) → biomi → foreste → depositi → semi delle province (Poisson pesato sull'abitabilità) →
crescita a costo (creste e grandi fiumi più cari **in modo non uniforme**, così solo alcuni confini seguono la geografia)
→ adiacenze e tipi di confine → culture/religioni per macro-regioni con frontiere miste → nomi → regni iniziali →
immagine `albedo_far.png` → report e anteprime (`tools/worldgen/out_preview/`).

### 4.3 Verifiche automatiche della mappa
- una sola componente di terra connessa (nessuna isola);
- ogni provincia raggiungibile via terra da ogni altra;
- nessuna provincia minuscola o enorme oltre soglia; forme non degeneri;
- ogni catena montuosa lunga ha almeno un passo;
- ogni regione culturale ha province valide; il luogo di partenza soddisfa i requisiti (bosco, roccia, acqua, terra fertile).

---

## 5. Stato dinamico del mondo

### 5.1 `WorldState` (radice serializzabile)
```
WorldState
 ├ meta: save_version, game_version, world_version, campaign_id
 ├ calendar: day (int), speed
 ├ rng: stati dei generatori per sistema
 ├ terrain_deltas: TerrainDeltaStore (per chunk)
 ├ provinces: Array[ProvinceState]
 ├ kingdoms: Array[KingdomState]
 ├ settlements: Array[SettlementState]
 ├ buildings: BuildingStore (id → BuildingState, indice spaziale)
 ├ population: PopulationStore
 ├ characters: CharacterStore + dynasties
 ├ diplomacy: DiplomacyState
 ├ military: armies, regiments, battles, sieges
 ├ events: stato eventi, cooldown, catene attive
 ├ chronicle: ChronicleLog
 └ player: kingdom_id, preferenze di partita
```

### 5.2 Terreno locale: base deterministica + delta
- La griglia a 2 m non è mai memorizzata per intero. Un `LocalChunk` (256 m) si **materializza** su richiesta dai raster
  macro + hash deterministici (posizione di alberi, rocce, cespugli), poi applica i **delta salvati**.
- `TerrainDeltaStore` per chunk: alberi abbattuti (bitset per id albero), cariche residue di rocce/vene, aree disboscate
  (poligoni/cerchi, usate dalla crescita automatica), campi, strade, ponti, pavimentazioni, devastazione, crateri/rovine.
- I chunk materializzati vengono rilasciati quando non servono (lontani dalla camera e senza cantieri/lavori attivi);
  i delta restano. **Tutte le trasformazioni sono permanenti e salvate.**

### 5.3 Indici spaziali
- Griglia uniforme di bucket (512 m) per edifici, insediamenti, eserciti, agenti: query per raggio e per rettangolo di vista.
- Raster province per `province_at(pos)` O(1).
- Grafo delle province (adiacenze con costo) per rotte strategiche; grafo stradale per trasporti e marce;
  navigazione locale (A* su griglia chunk) solo per agenti visivi e piazzamento.

---

## 6. Tempo e simulazione

### 6.1 Orologio
- Unità di simulazione: **giorno**. Anno di 360 giorni (12 mesi × 30). Inizio: 1 marzo 1230 (configurabile).
- Velocità (dati): pausa, 1 (≈4 s/giorno), 2 (≈1,5 s), 3 (≈0,5 s), 4 (≈0,15 s), 5 (≈0,05 s).
- **Velocità di osservazione**: quando la camera è a zoom ravvicinato su una battaglia o un assedio attivo, il gioco
  può limitare automaticamente la velocità (opzione) — esiste un solo orologio, quindi rallenta tutto il mondo.
- Frazioni di giorno ("ore") per battaglie, marce e cantieri che richiedono passi più fini.

### 6.2 Scheduler
`SimulationRunner` (nodo) accumula tempo reale e chiama `Simulation.advance_day()`; dentro ogni giorno lo `Scheduler`
esegue i sistemi registrati con frequenze diverse e **distribuzione su più giorni** (bucket per id):

| Frequenza | Sistemi |
|---|---|
| sotto-giorno (ore) | battaglie attive, movimento eserciti, cantieri, trasporti in corso |
| giornaliera | produzione e consumo insediamenti, scorte, cibo, salute, misure della corona, eserciti (rifornimenti, morale) |
| settimanale (a rotazione) | IA dei regni (1/7 dei regni al giorno), mercati regionali, fazioni, migrazioni |
| mensile | demografia (nascite, morti, invecchiamento), crescita insediamenti, spiriti nazionali, tecnologie, diplomazia (decadimenti) |
| annuale | successioni pianificate, statistiche di cronaca, obiettivi di campagna |

Gli agenti visivi (abitanti che camminano, soldati animati) si aggiornano **a frame** ma solo vicino alla camera,
con pool di oggetti e tick differenziati.

### 6.3 Determinismo e caso
- Ogni sistema ha il proprio `RandomNumberGenerator` con seme derivato da `campaign_seed` (mai mostrato al giocatore)
  e stato salvato. Stessa partita caricata → stessi esiti.
- Nuova partita → nuovo `campaign_seed` casuale: **mappa fissa, storia non fissa**.

### 6.4 Cosa non si ricalcola (Fase 13)
Il costo di una giornata è stato misurato con `Scheduler.profile_report()` prima di toccare qualunque cosa.
Quel che ne è uscito, e come è stato tolto:

| Costava | Perché | Adesso |
|---|---|---|
| `WorldState.people_of()` | scandiva **tutto** il dizionario delle persone e lo ordinava, decine di volte al giorno per insediamento | lista in cache per insediamento, invalidata da `people_version` (chi nasce, muore o cambia insediamento lo alza) più un controllo sulla dimensione del dizionario, così una chiamata dimenticata costa un ricalcolo, mai una risposta sbagliata |
| gli alberi intorno al taglialegna | la lista dei candidati viveva un giorno solo: ogni mattina si riscorreva la griglia delle feature (oltre mille celle per taglialegna) | la lista sopravvive ai giorni — gli abbattuti si potano man mano e si saltano — e si butta **solo** quando un ceppo ricresce |
| la ricrescita dei ceppi | ogni giorno si scorrevano tutti i ceppi del mondo spezzando la chiave "gx:gy" | `TerrainDeltas.next_regrow_day`: prima di quel giorno la scansione si salta del tutto |
| l'ora degli abitanti | `SettlementSim.tick()` passava su tutte le persone del mondo 24 volte al giorno anche senza nessuno a guardare | se nessun insediamento è osservato il ciclo non parte: la giornata la risolve `SettlementAggregate` |
| il consenso | `service_coverage()` confrontava ogni casa con ogni edificio (quadratico) | le botteghe di servizio si raccolgono una volta sola |
| i cantieri | ogni giorno ricontavano gli alberi sul terreno già sgombrato | `BuildingState.ground_cleared` (non salvato: si ricalcola al caricamento) |
| il registro di corte | `day % 7` dentro il ciclo su tutti i personaggi | calcolato una volta, e il filtro più economico per primo |

Risultato misurato: dieci anni di villaggio **37,4 s → 11,5 s**; `test_settlement` 9,9 s → 1,0 s; l'intera
suite da 739 s a poco più di 500 s. Nessun comportamento è cambiato: le prove di determinismo (stesso
salvataggio → stesso esito) sono le stesse di prima.

---

## 7. Dati di definizione (`res://data/defs/`)

JSON leggibili e bilanciabili, caricati da `Defs` in classi `Resource` tipizzate con validazione (id unici, riferimenti
esistenti, range). Errori di dati = errori di test.

| File | Classe | Contenuto |
|---|---|---|
| `resources.json` | `ResourceDef` | risorse, prezzi base, peso, deperibilità |
| `terrain_types.json`, `biomes.json` | `TerrainDef`, `BiomeDef` | camminabilità, edificabilità, costi, rese, colori |
| `buildings.json` | `BuildingDef` | impronta, costi, tempi, posti, input/output, raggi, requisiti, livelli, effetti politici |
| `units.json` | `UnitDef` | statistiche, contrasti, costi, requisiti di sblocco |
| `formations.json`, `orders.json` | `FormationDef` | bonus tattici |
| `cultures.json` | `CultureDef` | `{id, name, description, modifiers[]}` |
| `religions.json` | `ReligionDef` | `{id, name, description, modifiers[]}` |
| `national_spirits.json` | `NationalSpiritDef` | modificatori, condizioni di comparsa, evoluzioni, rami, scomparsa |
| `traits.json` | `TraitDef` | modificatori + pesi decisionali IA + reazioni fazioni |
| `factions.json` | `FactionDef` | peso, rivalità, interessi, richieste, crisi, doni |
| `laws.json`, `edicts.json`, `government.json` | `LawDef`… | effetti, costi, vincitori/perdenti, requisiti |
| `technologies.json` | `TechDef` | rami, specializzazioni esclusive, effetti |
| `events.json` | `EventDef` | condizioni, peso, cooldown, opzioni, effetti, catene |
| `balance/*.json` | — | tempo, popolazione, economia, guerra, IA, difficoltà |

Formato dei modificatori:
```json
{ "key": "production.wood", "op": "mul", "value": 1.10 }
{ "key": "legitimacy.daily", "op": "add", "value": 0.02 }
```

---

## 8. Modificatori e identità del regno

`ModifierStack` per regno (e per provincia/insediamento), con **fonti nominate**:
`culture`, `religion`, `geography`, `national_spirit:<id>`, `ruler_trait:<id>`, `government`, `law:<id>`, `edict:<id>`,
`technology:<id>`, `building:<id>`, `event:<id>` (temporanei, con scadenza).
- Valore effettivo = `(base + Σadd) × Πmul`, calcolato in cache e invalidato quando una fonte cambia.
- Ogni valore mostrato in UI ha un **tooltip di scomposizione** per fonte: la formula
  `cultura + religione + geografia + spiriti + sovrano + governo + leggi + economia + eventi` è visibile al giocatore.

---

## 9. Sistemi di simulazione (moduli principali)

| Sistema | Responsabilità | Legge | Scrive |
|---|---|---|---|
| `SettlementEconomySystem` | produzione/consumo per insediamento, scorte, posti di lavoro | edifici, popolazione, terreno | scorte, delta terreno |
| `TransportSystem` | flussi di merci fra insediamenti e depositi lungo strade | grafo stradale, scorte | scorte, carovane visive |
| `ConstructionSystem` | cantieri, consegne materiali, avanzamento | comandi, scorte, lavoratori | edifici |
| `FamilySystem` | unioni, famiglie, registro dei mestieri, autorità e tappe della comunità (mensile, prima della popolazione) | persone, edifici, raccolti | coppie, famiglie, autorità, cronaca |
| `PopulationSystem` | nascite, morti, età, salute, alloggi, classi | cibo, felicità, leggi | popolazione |
| `LaborSystem` | assegnazione lavoratori per priorità e distanza | posti, abitanti | assegnazioni |
| `MarketSystem` | prezzi regionali, commercio | scorte, trattati | prezzi, tesoro |
| `TreasurySystem` | tasse, salari, mantenimenti, debiti | classi, leggi | oro |
| `CrownSystem` | prestigio, legittimità, stabilità, fiducia | fazioni, corte, guerre | misure |
| `FactionSystem` | favore, influenza, richieste, crisi, doni | classi, gesti politici | favore, eventi |
| `GovernmentSystem` | leggi, editti, riforme, forma dello Stato | comandi | modificatori |
| `DynastySystem` | nascite a corte, morti, successione, pretendenti | personaggi, leggi di successione | sovrano, crisi |
| `NationalSpiritSystem` | registri di azioni, evoluzione spiriti | eventi del bus, condizioni | spiriti |
| `DiplomacySystem` | opinioni, patti, guerre, tregue, reputazione | azioni | relazioni |
| `MilitarySystem` | reclutamento, reggimenti, eserciti, rifornimenti, marce | comandi, strade | eserciti |
| `BattleSystem` | battaglie sul posto (modello a reggimenti) | eserciti, terreno | perdite, morale, esiti |
| `SiegeSystem` | assedi, mura, assalti | eserciti, fortificazioni | danni, conquiste |
| `ConquestSystem` | cambio di proprietà senza reset, devastazione | esiti | province, cronaca |
| `VisibilitySystem` | fog of war militare | province, eserciti, torri, alleati | visibilità per regno |
| `EventSystem` | eventi sistemici e crisi data-driven | tutto lo stato | effetti via comandi |
| `TechnologySystem` | ricerca e specializzazioni | tesoro, istituzioni | modificatori, sblocchi |
| `ChronicleSystem` | cronaca e obiettivi | bus eventi | registro |
| `AISystem` | decisioni dei regni non giocanti | valutazione | comandi |


### 9.0 Il pane e chi resta (Fase 13)
Il cibo è la regola che decide quanto può essere grande un villaggio, e i numeri sono stati tarati sulla
simulazione vera, non a occhio:

- **Quanto rende un campo**: una fattoria con tre contadini porta a casa circa 500 misure di grano l'anno.
  Il forno ne fa pane (quattro misure di grano → sei pani), e un uomo mangia un quarto di razione al giorno.
  Una fattoria e un forno, quindi, tengono in piedi sei o sette persone: non di più.
- **Il grano vale quel che il forno ne fa**: `PopulationSystem.food_days()` conta il grano al valore che avrà
  una volta cotto, se nell'insediamento c'è un forno in piedi e con qualcuno dentro. Un granaio pieno accanto
  a un forno acceso non è mezza dispensa, è una dispensa.
- **Il pane prima della pietra**: la priorità dei mestieri (`job_priority`) mette i campi e il forno davanti ai
  cantieri, e i costruttori non possono mai essere più delle braccia che avanzano dopo il cibo. Un villaggio
  che passa l'anno a tirare su case e salta la mietitura non si riprende più.
- **La valvola dell'emigrazione** (`PopulationSystem._emigration`, guardata ogni giorno): la misura è il
  raccolto. Se quel che c'è nei depositi non porta il villaggio alla mietitura successiva, ogni giorno
  qualcuno prende la strada — prima i senza lavoro, poi le braccia che si possono risparmiare, e i contadini
  e il fornaio per ultimi, perché un posto che perde l'ultimo contadino perde anche il raccolto dell'anno dopo
  e allora non lo salva più nulla. Chi parte porta con sé i figli di casa sua. Se un altro insediamento del
  regno ha un letto libero e i depositi pieni ci vanno; altrimenti lasciano il regno. Le partenze si fermano
  da sole appena quel che resta basta a chi è rimasto.
- **Conseguenza**: un villaggio lasciato a sé stesso non muore più di fame. Cresce con i viandanti finché i
  campi bastano, poi respira — venti anni senza una sola decisione del signore si chiudono con il villaggio
  ancora vivo e **nessun morto di stenti** (`test_economy::test_a_village_left_to_itself_empties_instead_of_starving`).
  La carestia vera resta possibile: un insediamento senza campi muore comunque, e in fretta.

Comunicazione fra sistemi: lettura diretta dello stato + **`EventBus`** (segnali tipizzati: `province_owner_changed`,
`building_completed`, `war_declared`, `battle_ended`, `ruler_died`, `law_enacted`, …) per reazioni disaccoppiate
(fazioni, spiriti, cronaca, memoria IA — esattamente il modello a Bus di Regno).

### 9.1 Economia e popolazione: individui + flussi
- **Individui**: ogni abitante degli insediamenti del giocatore è un record nel `PopulationStore` (array compatti:
  età, sesso, casa, lavoro, salute, umore, classe, famiglia, nome). I regni IA partono con popolazione per **coorti**
  (età × sesso × classe) che viene convertita in individui in modo statisticamente coerente quando l'insediamento
  passa al giocatore.
- **Produzione analitica**: la resa di un posto di lavoro dipende dal tempo di ciclo + tempo di percorrenza reale
  (distanza casa-lavoro-risorsa-deposito sulla rete di percorsi): il layout conta come in Regno, ma senza simulare
  ogni sacco.
- **Agenti visivi**: vicino alla camera il `PopulationPresenter` genera agenti (pool) che rappresentano i lavori in corso:
  escono di casa, percorrono strade, abbattono l'albero *vero* che il sistema ha consumato, portano il carico al deposito.
  Lontano, nessun agente: stessa economia.

### 9.2 Battaglie: modello a reggimenti
- Il modello autoritativo è a **reggimento** (posizione, fronte, formazione, uomini, morale, fatica, contatto, fianchi,
  carica), eredità diretta delle regole di Regno ma con costo O(reggimenti²) e quindi sempre simulabile.
- I soldati individuali visibili sono la sua **rappresentazione** (slot di formazione, animazioni, cadute che seguono
  le perdite calcolate): la camera non cambia l'esito.
- Le battaglie avvengono nella posizione reale; il terreno sotto ogni reggimento (fiume, guado, ponte, collina, bosco,
  palude, mura) entra nei calcoli.

---

## 10. IA

```
KingdomAI.think(kingdom):
  assessment = StrategicEvaluator.evaluate(kingdom)       # geografia, economia, militare, vicini, minacce, opportunità
  personality = PersonalityProfile.from(ruler, culture, religion, spirits, factions)
  goal = GoalSelector.update(kingdom, assessment, personality)   # scopi di Regno, durata 40–300 giorni
  proposals = []
  for planner in [EconomicPlanner, ConstructionPlanner, MilitaryPlanner, DiplomaticPlanner, PoliticalPlanner]:
      proposals += planner.propose(kingdom, assessment, goal)
  for p in proposals: p.score = UtilityScorer.score(p, assessment, personality, goal)
  execute best non-conflicting proposals within budget  →  Commands
```
- `PersonalityProfile`: pesi (aggressività, prudenza, commercio, sviluppo, lealtà, rischio, fede, accentramento…)
  derivati dai **tratti del sovrano** (dati), corretti da spiriti nazionali e fazioni forti.
- Memoria (rancore/stima) e opinioni da Regno, per coppia di regni.
- Ogni proposta registra la **motivazione** (per debug e per messaggi al giocatore: "Il re X arma i passi perché…").
- Costo: regni pensati a rotazione, valutazione con cache mensile dei dati pesanti.

---

## 11. Rendering — carta medievale illustrata, rendering leggero

**Direzione (revisioni del 17/09/2026):** aspetto di carta medievale illustrata e dipinta (riferimento: mockup del 14/09,
vedi GAME_DESIGN_MAP §1), implementata nel modo più semplice possibile. Prevalentemente 2D, profondità 2.5D solo
suggerita con sprite prerenderizzati, ombre incorporate, silhouette e layering. Ordine di priorità: 1) fluidità
2) leggibilità 3) stabilità 4) coerenza 5) bellezza. A parità di effetto si sceglie la soluzione 2D meno costosa.

Tutto è `Node2D`/`CanvasItem`. Nessuna camera 3D, nessun volume pre-renderizzato pesante.

Regole pratiche:
- **Terreno**: colori naturali "dipinti" sfumati con grana di carta + rilievo appena accennato + acqua a tinta con
  variazione di profondità e fascia costiera chiara; niente texture tassellate pesanti, niente acqua animata.
- **Montagne**: sprite prerenderizzati (`tools/art/draw_mountains.py`: piccolo campo di altezze procedurale visto in 3/4,
  ombreggiatura e neve incorporate; classi collina / picco / picco innevato, 4 varianti ciascuna) posati sulle catene da
  `tools/worldgen/place_mountains.py` (`data/world/mountains.json`, piazzamento goloso dalle quote più alte, larghezza
  dall'altitudine) e disegnati da `MountainLayer`: un unico MultiMesh ordinato per y (1 draw call). Visibili da 5–8 m/px in su;
  più vicino resta il rilievo accennato del terreno. Sopra 1050 m niente gruppi di alberi agli zoom medi/lontani.
- **Vegetazione**: sprite dipinti in vista 3/4 leggera; da lontano masse nell'albedo, a zoom medio sprite di *gruppi*
  di alberi, da vicino alberi singoli. Ogni fascia ha una dimensione minima a schermo (`icon_px`): gli sprite vengono
  ingranditi attorno al piede per non diventare puntini.
- **Edifici**: silhouette chiare viste dall'alto con un accenno di facciata, pochi colori coerenti, stati essenziali
  (cantiere, completo, danneggiato).
- **Abitanti e soldati**: figure piccole e leggibili, colori per mestiere/unità; animazioni minime e a pochi frame:
  idle, camminata, lavoro generico, trasporto, fuga, combattimento base. La simulazione resta profonda, la resa semplice.
- **Unità militari**: distinguibili da forma + colore di bandiera; formazioni come blocchi a zoom medio.

### 11.1 Livelli di scena (`WorldView`)
```
WorldView (Node2D)
 ├ TerrainLayer        un quadrilatero grande quanto la vista + shader del terreno (1 draw call)
 ├ WaterLayer          fiumi (mesh da polilinee) + shader acqua animata; mare e laghi nello shader del terreno
 ├ GroundDecalLayer    strade, campi, terra battuta, piazze (per chunk)
 ├ MountainLayer       MultiMesh unico ordinato per y: montagne e colline illustrate
 ├ SettlementLayer     edifici e strade (sprite dall'atlante, ordinati per y, cantieri che crescono)
 ├ PeopleLayer         abitanti vicino alla camera (pochi frame, posizione interpolata)
 ├ BuildController     anteprima di piazzamento (verde/rosso + motivo)
 ├ VegetationLayer     MultiMesh a chunk: alberi singoli da vicino, gruppi di alberi a zoom medio/mappa
 ├ EntityLayer (y-sort) edifici, agenti, soldati (per chunk, con culling)          [Fase 4]
 ├ BorderLayer         linee di provincia (statiche) + confini di dominio (ricostruiti al cambio di proprietà)
 ├ SelectionLayer      contorno della provincia sotto il mouse e di quella selezionata
 └ StrategicIconLayer  simboli di insediamenti, stendardi degli eserciti, battaglie  [Fasi 4/9]
MapHud (CanvasLayer, spazio schermo)
 └ MapLabels           nomi di regni (con stemma), signorie e province, dissolvenza per zoom, niente sovrapposizioni
SettlementHud (CanvasLayer, l'interfaccia: vedi §13)
 ├ TopBar              risorse, misure della corona, data e velocità del tempo
 ├ RealmColumn         colonna sinistra + MapModeMenu (modalità mappa, M per scorrere, tasti F da dati)
 ├ BuildColumn         costruzioni e zona contestuale (ispettore edificio, ProvinceInspector)
 ├ MainBar             barra inferiore delle grandi sezioni
 ├ PanelHost           le schede del regno, una per volta, ancorate a sinistra
 ├ Notifications       cartigli a destra
 └ EventCard           la carta dell'evento al centro
```
La velatura delle modalità mappa è nello shader del terreno: raster delle province (RG8) + tabella colori 1024×1
(x = id provincia) costruita da `MapModes` e caricata da `MapModeController`; mescolanza bilineare fra le 4 celle
vicine per bordi morbidi, la linea netta la disegna `BorderLayer`.

### 11.1b Stato politico (Fase 3)
- `ProvinceState` (proprietario, controllore, popolazione aggregata, sviluppo, devastazione) e `KingdomState`
  (rango derivato: insediamento/signoria/regno, casata, cultura, religione, colore, capitale, stemma) in `WorldState`,
  salvati (save_version 2; la migrazione da v1 ricostruisce la situazione iniziale).
- `StartSetup` legge `data/defs/start_setup.json`: valle di partenza del giocatore scelta per requisiti vicino a un
  punto d'ancora (con rilassamento controllato), zona libera di 2 passi attorno, regni e signorie che crescono insieme
  sul grafo delle province (Dijkstra con costi per fiumi/passi/montagne e differenze di cultura/religione). Deterministico.
- Ogni cambio di proprietà passa da `TransferProvinceCommand` → `WorldState.set_province_owner` → segnale
  `province_owner_changed` → bordi, velatura ed etichette si aggiornano.
- `WorldData.borders`: polilinee dei confini semplificate (RDP 45 m) e arrotondate (Chaikin), con il lato di ciascuna provincia.
- `CoatOfArms`: stemmi procedurali deterministici dalla casata (forma per cultura, regola delle tinte, partizioni, figure).

### 11.1c Coerenza fra zoom vicino e lontano
- `data/defs/map_style.json`: unica fonte dei colori regionali (umidità secca/umida, valli/crinali, toni del fogliame,
  colori delle foreste lontane), letta sia dallo shader del terreno e della vegetazione (uniform con lo stesso nome,
  `TerrainLayer.apply_style`) sia da `tools/worldgen/render.py` per l'albedo lontano.
- `data/world/canopy.bin` (64 m): copertura arborea visiva (radure, densità variabile, bordi irregolari), letta da
  `VegetationLayer` (`WorldData.canopy_smooth`), dallo shader (sottobosco) e dall'albedo. `forest.bin` resta il dato
  ecologico per statistiche di provincia e fertilità.

### 11.1d Insediamenti (Fase 4)
- `LocalFeatures`: alberi/cespugli dalla griglia sfalsata della fascia "close" (stessa regola del renderer) e rocce
  affioranti attorno ai giacimenti; ogni elemento ha una chiave stabile (`gx:gy`, `prov:dep:i`).
- `TerrainDeltas` (in `WorldState`, salvato): alberi abbattuti (giorno, o "liberato per sempre" sotto gli edifici) e
  cariche di roccia consumate; segnale `terrain_changed(pos)` → `VegetationLayer` ricostruisce solo i chunk toccati
  (max 2 per frame) partendo da una cache delle feature del chunk.
- Stato: `SettlementState` (scorte, quota costruttori, prenotazioni), `BuildingState` (cantiere/attivo, materiali
  consegnati, ore di lavoro, lavoratori richiesti, campi; le strade sono edifici "a linea" con due estremi),
  `PersonState` (mestiere, casa, posto di lavoro, fame, azione corrente con inizio/fine in ore e carico in mano).
- `SettlementSim`: 1 tick = 1 ora. Ogni persona ha un'azione con `pending` (l'effetto applicato alla fine: l'albero
  cade, la merce arriva, il cantiere cresce) e poi pianifica la successiva secondo il mestiere. Il renderer interpola
  la posizione con `tick_alpha()`. La camminata è astratta (`walk_m_per_hour`), più veloce sulle strade finite.
- `Placement` decide se si può costruire e **perché no**; i comandi (`PlaceBuildingCommand`, `PlaceRoadCommand`,
  `CancelSiteCommand`, `SetWorkersCommand`, `SetBuilderQuotaCommand`) sono l'unico modo di cambiare lo stato.
- `SettlementPlanner` trova posizioni valide con le stesse regole del giocatore (servirà al `ConstructionPlanner` dell'IA).

### 11.1e Economia e popolazione (Fase 5)
- `PopulationSystem` (giorno): crescita dei bambini, nascite, morti (vecchiaia, stenti, miseria), viandanti,
  consenso con la sua scomposizione; `EconomySystem` (mese): tasse, salari, rendite di provincia con controllo
  amministrativo, prezzi di mercato; `ProvinceGrowthSystem` (anno): popolazione aggregata delle altre province.
- **Doppio regime di simulazione**: `SettlementSim` (ora per ora) per gli insediamenti osservati dalla camera,
  `SettlementAggregate` (giorno per giorno, forma chiusa) per gli altri. Le regole e gli effetti fisici coincidono:
  gli alberi cadono davvero, i cantieri crescono davvero. `SettlementSim.set_observed()` è chiamato dal renderer.
- Capienza dei depositi per gruppo di merci (`SettlementState.capacity/used/space_for`); l'oro è tesoro della corona
  (`KingdomState.treasury`), non merce di magazzino.

### 11.1f Identità del regno (Fase 6)
- `KingdomModifiers.stack(session, kingdom)` → `ModifierStack` con fonti `culture:*`, `religion:*`, `spirit:*`
  (cache invalidata da `KingdomState.identity_version`). Ogni sistema legge i propri numeri da qui:
  `KingdomModifiers.value(...)` e `settlement_value(...)`, con chiavi extra dalla terra (`SettlementSim.field_keys`).
- `SettlementSim.produce()` è l'unico punto in cui una merce entra nelle scorte: applica i modificatori e scrive il
  registro del regno (`KingdomState.records`) che alimenta gli spiriti.
- `NationalSpiritSystem` (mese): misura i **fatti** del regno (geografia delle province + registri) e applica le regole
  dei dati: assegnazione iniziale, evoluzioni, spiriti abbandonati (`spirits_past`) che non tornano.
- `CultureSystem` (anno): attrito culturale/religioso → malcontento della provincia (che riduce le rendite) e
  assimilazione lenta verso la cultura della corona.

### 11.1g La corona (Fase 7)
- `CharacterState` (`characters/`) è la persona che conta politicamente: casata, tratti (`TraitDef`), abilità,
  consorte, figli, e un eventuale `person` — il `PersonState` che cammina sulla mappa quando il personaggio è il re
  del dominio del giocatore. `WorldState.characters` li conserva, `WorldState.ruler_of(kingdom)` dà il sovrano vivo.
- `CourtSystem` (giorno, ordine 28) è il solo posto che crea, invecchia, uccide e incorona: `found_courts()` alla
  fondazione della partita (anche per i salvataggi precedenti), `heir_of()` applica la legge di successione e
  `succeed()` incorona o apre la crisi dinastica. Le misure della corona (legittimità, stabilità — «ordine» fino al
  consolidamento —, prestigio, turbolenza) inseguono il loro bersaglio ogni giorno, con i parametri in
  `balance/crown.json`.
- Leggi ed editti stanno in `KingdomState.laws` / `edicts` (l'editto tiene il giorno in cui scade) e entrano nella
  `ModifierStack` del regno come fonti `law:<gruppo>` e `edict:<id>`, accanto a `ruler` (tratti + abilità del
  sovrano). `Laws` legge `data/defs/laws.json`; `CrownEffects.apply_political()` è il prezzo politico di una
  decisione (favore delle fazioni + turbolenza), condiviso da leggi, editti e in futuro eventi.
- Dove le misure toccano il gioco: `EconomySystem` riscuote le tasse in proporzione alla stabilità;
  `PopulationSystem` aggiunge alla fiducia la voce "La corona" (legittimità e stabilità).

### 11.1h Fra le corone (Fase 8)
- `RelationState` (una per coppia, chiave "min:max" in `WorldState.relations`) tiene opinione, patti con la loro
  scadenza, chi paga in un patto asimmetrico, guerra, tregua, matrimonio e i ricordi datati.
- `Diplomacy` è la regola: `opinion_target()` costruisce il bersaglio dell'opinione dai fatti e
  `opinion_breakdown()` lo dice in parole; `power()` pesa un regno (terre in cache su `political_version`, oro e
  prestigio live); `sign()`, `break_pact()`, `start_war()`, `end_war()` scrivono lo stato e toccano
  `identity_version` perché i patti sono fonti nominate della `ModifierStack`.
- `DiplomacySystem` (giorno, ordine 26): insegue le opinioni, fa scadere patti, tregue e ambasciate, paga i
  tributi il primo del mese, dimentica i ricordi vecchi una volta l'anno.
- `DiplomacyAi.judge_pact()` / `judge_marriage()` rispondono **sì o no con una frase**: le usano sia l'IA sia i
  comandi del giocatore, così la risposta è la stessa da qualunque parte arrivi la proposta.
- `RealmAiSystem` (mese, ordine 34): personalità dai tratti del sovrano, elenco di opzioni con utilità, una sola
  azione al mese, registro leggibile in `session.runtime["ai_log"]` e contatori nei `records` del regno
  (`wars_declared`, `pacts_signed`, `provinces_developed`, `laws_enacted`) usati dai test e dalle statistiche.
- Le proposte dell'IA al giocatore diventano voci in `WorldState.offers` (trenta giorni) e si chiudono con
  `AnswerOfferCommand`.

### 11.1i L'esercito (Fase 9)
- `UnitDef` (`data/defs/units.json`) descrive un reparto; `ArmyState` è la schiera sulla mappa: provincia,
  posizione in metri, reggimenti `{unit, men, max_men, morale, people}`, viveri, percorso, comandante.
  I `people` sono gli **id delle persone vere** che marciano: un caduto o un disertore sparisce dal mondo.
  Le leve dei regni aggregati hanno `people` vuoto e i loro uomini escono e rientrano nella popolazione della
  provincia (`Military.raise_from_province` / `dissolve_into_province`).
- `Military` è la regola: `day_march_km()` (passo del reparto più lento × ore × terreno × comandante × morale),
  `route()` (Dijkstra sul grafo delle province con il prezzo di fiumi e passi), `can_resupply()`, `can_see()` e
  `visible_armies()` per la nebbia di guerra, `strength()` per il peso militare di un regno.
- `MilitarySystem` (giorno, ordine 27): addestramento nei villaggi, marcia del giorno (che scrive `step_from`
  e `step_to` per l'interpolazione del renderer), pane, paga, morale e diserzioni.
- Comandi: `RecruitUnitCommand`, `MoveArmyCommand`, `DisbandArmyCommand`.
- `ArmyLayer` disegna i soldati (atlante delle persone: i mestieri militari hanno le stesse animazioni degli
  altri) sotto 1,6 m/px e lo stendardo tinto del colore del regno fino a 45 m/px; `MapInteraction.army_under()`
  li seleziona e `order_army()` fa del clic successivo la destinazione.

### 11.1j La guerra (Fase 10)
- `WarSystem` (giorno, ordine 29) fa quattro cose in fila: fa incontrare le schiere nemiche vicine
  (`BattleState`), risolve i turni di battaglia, porta avanti gli assedi (`SiegeState`) e passa sulla terra
  (devastazione dove passano gli eserciti, malcontento dove si occupa).
- `War` è la regola pura e testabile: `terrain_defense()`, `matchup()`, `side_damage()`, `apply_losses()`
  (che toglie uomini veri dai reggimenti e morale a chi resta), `score_for()` / `add_score()` per il conto
  della guerra tenuto nella `RelationState` della coppia, `occupy()`, `liberate()` e `cede()`.
- La differenza fra **occupare** e **conquistare** è quella fra `ProvinceState.controller` e `owner`: la pace
  bianca rimette a posto il controller, la pace con condizioni cambia l'owner con `WorldState.set_province_owner`
  e porta con sé l'insediamento, senza toccare edifici, persone o sviluppo.
- `MakePeaceCommand` porta le condizioni (`cede`) e `judge()` risponde con una frase; le proposte al giocatore
  passano da `WorldState.offers` e `AnswerOfferCommand` come tutte le altre.
- Il costo della guerra per chi la subisce entra nel consenso da `PopulationSystem` (voci "Assedio" e
  "Occupazione"), non da `WarSystem`: il consenso ha un solo padrone.

### 11.1k Eventi, sapere e cronaca (Fase 11)
- `Events` è la regola: `facts()` raccoglie ciò che le condizioni possono leggere, `matches()` le verifica
  (una chiave sconosciuta rende l'evento impossibile), `pick()` sceglie a peso fra i candidati e `apply()`
  traduce gli effetti in cambiamenti veri dello stato (tesoro, depositi, consenso, favore, malcontento, morti,
  crisi, spiriti, opinione dei vicini, cronaca).
- `EventSystem` (mese, ordine 38) tira i dadi per ogni regno, mette gli eventi del giocatore in
  `WorldState.pending_events` (risposti con `ChooseEventOptionCommand`, o decisi dalla corte alla scadenza) e
  fa decidere l'IA con `Events.ai_choice()`. Fa anche scadere le crisi.
- Le crisi sono voci `{id, name, until, modifiers}` in `KingdomState.crises` e diventano fonti `crisis:*` della
  `ModifierStack`; le tecnologie sono `KingdomState.technologies` e diventano fonti `tech:*`.
- `ResearchSystem` (mese, ordine 36) accumula `KingdomState.research` da sviluppo, edifici e abilità del
  sovrano; `AdoptTechnologyCommand` spende i punti e chiude il ramo (`Technologies.branch_taken`).
- La cronaca: `EventBus.chronicle_written` è ascoltato da `GameSession._write_chronicle`, che riempie
  `WorldState.chronicle` (limite in `balance/events.json`) — salvata con il mondo e letta dal pannello CRONACA.
- `Objectives.progress()` misura i cinque obiettivi di campagna su stato reale (abitanti, province, sovrani
  incoronati, tesoro, rami di sapere).

### 11.1l L'interfaccia (Fase 12)
- `KDSheet` è la cornice comune di ogni scheda: legno, larghezza fissa, una colonna che scorre e gli aiuti che
  tutte usano (`section`, `parchment`, `line`, `meter`, `command_button`). Un pulsante costruito con
  `command_button` chiede al comando il suo `validate()` e si disabilita mostrando la ragione: nessuna scheda
  decide da sola cosa è permesso.
- `PanelHost` tiene le linguette e mostra **una sola pagina per volta**; le lettere e ESC passano da
  `handle_key()`. Le pagine sono `RealmPanel`, `CourtPanel`, `GovernmentPanel`, `EconomyPanel`,
  `KnowledgePanel`, `DiplomacyPanel`, `ArmyPanel`, `ChroniclePanel`.
- `NotificationStack` ascolta `EventBus.notification` e tiene al massimo sei cartigli, invecchiandoli nel suo
  `_process` (niente tween che sopravvivano al nodo).
- Regola imparata a caro prezzo: **un autoload non collega mai una lambda a un oggetto della partita**. Il
  collegamento prende un nome e `Session.end()` lo stacca, altrimenti alla chiusura il segnale punta a un nodo
  liberato e il processo muore con 0xC0000005.

### 11.1m Sei fondatori e la corona come conquista (Fase 15)
- Il giocatore parte con `KingdomState.monarchy_founded = false`, rango `SETTLEMENT`, nessun sovrano, casa vuota.
  Tutti i sistemi della corona lo rispettano: `CourtSystem.found_courts` e `run` saltano le comunità, i comandi
  di legge, editto, erede e matrimonio rifiutano, `PopulationSystem._trust` non conta «La corona».
- `FamilyState` (in `WorldState.families`) e i legami in `PersonState` (`family`, `born_family`, `spouse`,
  `mother`, `father`). `FamilySystem` unisce le coppie, registra il lavoro delle famiglie, calcola l'autorità
  (`authority_parts`, lenta verso il bersaglio) e scrive le tappe della comunità in cronaca.
- `CourtSystem.monarchy_conditions(session, k)` → righe `{label, ok, value}`; `monarchy_blocker` è la prima che
  manca e la ragione del `FoundMonarchyCommand`. `found_monarchy` trasforma la comunità in regno e fa della
  persona scelta il primo `CharacterState` (consorte e figli compresi); `origin_of` legge il registro della
  famiglia e `house_origins.json` dà favore e modificatori (sorgente `house_origin` in `KingdomModifiers`).
- `PopulationSystem.harvest_outlook(session, s)` è la sola misura di «arriva al raccolto?»: la usano
  l'emigrazione, la condizione economica del Regno, la fascia alta e i pianificatori (`SettlementPlanner.lord_month`).
- Interfaccia: `CourtPanel` ha due modi (famiglie / corte) e si ricostruisce al cambio; `SettlementHud._sync_crown`
  rinomina colonna e pagine e mostra `CoronationCard` al passaggio 0 → 1 (e la fine, se la comunità si estingue).
- Le voci di cronaca `founding_*` non vengono mai potate (`GameSession.is_founding_entry`).

### 11.1n Campagne intere e bilanciamento (Fase 16)
- `tests/campaign/`: `CampaignPilot` (un giocatore prudente fatto solo di comandi del giocatore) e
  `campaign_runner.tscn`, che gioca N anni per seme e scrive CSV e rapporto in `tests/output/campaign/` (con
  `.gdignore`, altrimenti Godot importa i CSV come traduzioni).
- Economia: `PopulationSystem.food_days` conta il grano come pane solo per quanto i forni con i loro fornai cuociono
  (`_ovens`); `EconomySystem` aggiunge vendita delle eccedenze (`sell_surplus`), acquisto dei materiali che mancano
  (`buy_shortage`), quota dell'amministrazione sulle rendite (`administration_share`) e manutenzione degli edifici
  (`buildings_upkeep`); `last_balance` porta `trade`, `imports`, `administration`, `upkeep`.
- Terre: `ClaimProvinceCommand` (annessione pacifica di terre libere confinanti), usato dall'IA (`_best_free_land`) e
  dai pulsanti dell'ispettore di provincia; `GiftFactionCommand` (dono a un ceto).
- Patti: `Diplomacy.pact_blocker` (niente trattati senza corona, un solo signore per regno), `lord_of`.
- Misure: `CourtSystem.add_prestige` è l'unico ingresso delle imprese (memoria `prestige_deeds`, che sbiadisce);
  `prestige_value` satura verso 100. Editti con riposo (`edict_ended:<id>`), senza memoria permanente.
- `SettlementPlanner.lord_month`: lista di desideri in ordine; `find_spot` controlla i materiali una volta sola
  (`affordable`).

### 11.1o Contenuti (Fase 17)
- Eventi: `Events.facts` legge anche anni, famiglie, tratti ed età del sovrano, erede, reggenza, patti, favore dei
  ceti, edifici e geografia della capitale, province straniere, guerre combattute, spiriti, crisi; `matches` rifiuta
  ogni condizione sconosciuta. Catene ritardate (`chain_days` / `after_days` → `chain_due:<id>` nei registri,
  scaricate da `EventSystem._fire_due_chains`); gli eventi `chain_only` non sono mai candidati da soli. `Events.words`
  adatta i testi a comunità e regno.
- Tratti: `TraitDef.opposite`; `CourtSystem.pick_traits` (opposizioni ed eredità) è l'unico punto dove si scelgono.
- Spiriti: `NationalSpiritDef.earned` (guadagnati in qualunque momento, fino a `MAX_SPIRITS` = 4), evoluzione verso
  `""` = scomparsa (`_fade`, cronaca `spirit_lost`), fatto `held_years` per spirito.
- `Objectives.progress` restituisce anche `category`; `CourtSystem._stability_year` e `_revolt_watch` alimentano
  l'obiettivo di stabilità e la cronaca delle rivolte; `SettlementSim._remember_building` le grandi opere.
- Guerre: `Diplomacy.start_war` / `end_war` scrivono `last_war_day` e `wars_fought`.

### 11.1p La resa definitiva (Fase 18)
- **Insediamenti da lontano** (`map/settlement/settlement_marks.gd`, nodo `SettlementMarks` dopo `SettlementLayer`):
  fra 2,2 e 40 m/px ogni edificio vero è un blocco (tetto, campo nella sua stagione con i solchi, mastio in pietra)
  mai più piccolo di 3,2 px, sopra la terra battuta attorno alle porte e con le sue strade. Si ridisegna quando lo
  zoom cambia dell'8%, quando cambiano gli edifici o la stagione. `SettlementLayer` disegna gli sprite solo sotto
  2,7 m/px; la simulazione dettagliata resta legata a `OBSERVED_MPP = 22` come prima (nessun effetto sul gioco).
- **Vita attorno alle case** (`SettlementLayer`): sentieri battuti fra le porte (`footpaths`, albero ricoprente
  minimo, mai oltre 140 m né attraverso il fiume), tre stili di strada per grandezza del luogo (`road_level`),
  orti recintati accanto alle case (`yards`: mai su edifici, strade, acqua o riva). Solo disegno.
- **Bosco** (`VegetationLayer`): nelle bande a cespi la densità segue un rumore a bassa frequenza
  (`value_noise`, celle di 470 m: radure e nuclei fitti) e la tinta un secondo rumore (gruppi di chiome dello
  stesso tono); i cespi si tengono a `clear_m` dagli edifici (34 m a zoom medio, 90 m a zoom carta). Lo shader
  allarga la variazione di tinta (0,76–1,18). Gli alberi veri (banda vicina) non cambiano.
- **Nomi sulla carta** (`MapLabels`): segnaposto sopra l'abitato e targa dipinta sotto (`built_radius`, il raggio
  che contiene nove edifici su dieci); il segnaposto si ritira quando il luogo è grande abbastanza da leggersi;
  una provincia con un insediamento non ha un secondo segnaposto con lo stesso nome.
- **Figure** (`PeopleLayer`, `ArmyLayer`): minimo 12–14 px sullo schermo ma mai più di 2,6–3,2 volte la misura
  vera; sotto i 7 px un abitante è un punto del colore del suo lavoro. La schiera è in blocchi per reggimento
  (colonna in marcia, linea a riposo) con il pennone del reggimento; il vessillo lontano porta il numero di uomini.

### 11.1q Il mondo come paesaggio (world art pass)
Regola: **la simulazione resta matematica, il disegno no**. Nessuna posizione logica, impronta, percorso o
salvataggio è cambiato; tutto ciò che segue è solo disegno, deterministico (hash di id o posizione).
- **Edifici**: `SettlementLayer.visual_of(b)` → spostamento ≤ 4% della misura, rotazione ±2,5°, scala ±5% (il
  mastio e le fattorie quasi fermi); usato dagli sprite, dalle ombre, dalla terra battuta e dai blocchi di
  `SettlementMarks`. Cinque case, due cascine, varianti di magazzino, granaio, fucina, caserma
  (`tools/art/draw_buildings.py`).
- **Campi** (`map/settlement/field_painter.gd`): la fattoria logica resta 26×30 m; sotto la cascina il campo è
  disegnato in 2–4 **strisce** (larghezze, colture e direzione dei solchi diverse, prode erbose, bordi che
  vagano, un maggese ogni tanto, l'insieme ruotato di pochi gradi); sei stati per mese (arato, seminato, in
  crescita, in maturazione, maturo, stoppie). Da vicino con i solchi, a media distanza a tinte piatte.
- **Villaggio**: `SettlementPlanner.zone_of` (pianificatore del pilota e degli scenari, non del giocatore): case
  attorno alla piazza, campi riuniti in un distretto sul lato libero e asciutto (`fields_direction`), depositi e
  laboratori in mezzo, taglialegna verso il bosco; `find_spot` non usa più 16 raggi fissi (angolo aureo e scarto
  deterministico). Piazza centrale che cresce con la gente (`_draw_square`), sentiero al fiume
  (`river_path`), sentieri che diventano **strade** secondo quante porte servono (albero ricoprente con il
  «traffico» di ogni ramo), strade e sentieri che curvano (`_draw_track(..., bend)`), terra battuta irregolare.
- **Oggetti di scena** (`map/settlement/settlement_props.gd`, atlante `assets/buildings/props_atlas.*` da
  `tools/art/draw_props.py`, 26 sprite): per tipo di edificio (legna e ceppi dal taglialegna, fieno e carro in
  cascina, casse e sacchi ai depositi, carbone alla fucina, barili alle case, bancarelle sulla piazza dei borghi
  da 120 abitanti). Nessuna collisione; sotto 1,9 m/px.
- **Bosco** (`LocalFeatures`): la probabilità di ogni cella segue `glade_factor` (nuclei e radure, 470 m),
  `margin_noise` (margini frastagliati) e `grove_chance` (boschetti fuori dal bosco); il numero di alberi resta
  quello di prima entro l'8% (prova). La banda media usa le stesse funzioni e un **margine sfruttato** attorno
  agli insediamenti (`margin_m`); la banda «carta» si spegne a 22 m/px (oltre, l'albedo dipinto).
- **Terreno**: nel quad (`terrain.gdshader`, sotto 12 m/px) macchie ampie e deformate di prato più scuro, prato
  secco e terra ricca. **Fiumi** (`river.gdshader`): riva che cambia lungo il corso (ghiaia larga, fango, sabbia)
  e una frangia di erba umida (`damp_widen`, solo disegno); canneti e sassi sulle rive
  (`map/water/river_bank_props.gd`, a chunk da 512 m, sotto 1,8 m/px).
- **Abitanti**: una leggera tinta per persona (`PeopleLayer.clothes_of`).
- **Filtraggio**: mipmap sugli atlanti che cambiano scala (edifici, vegetazione, montagne, persone, oggetti).
- **Costo del disegno**: i campi di tutta la mappa sono una mesh (`FieldPainter.build_mesh`); ciò che sta a terra
  lo disegna il figlio `Ground` di `SettlementLayer`, ridisegnato solo al cambio di edifici, mese o gente (a passi
  di venti); i blocchi di `SettlementMarks` senza trasformazioni; i cespi guardano gli edifici per secchi da 128 m;
  `VegetationLayer.BUILD_BUDGET_MS` limita i blocchi di bosco costruiti in un fotogramma; `RiverBankProps` ha un
  indice dei segmenti per blocco da 512 m, costruito all'avvio.
- **HUD**: `SettlementHud` segna `_dirty` a ogni `settlement_changed`/`day_passed` e si aggiorna una volta per
  fotogramma (prima: centinaia di ricalcoli per giorno di gioco in una cittadina).
- **Prove visive**: `--kd-save-to` / `--kd-load` (mondi di prova in `tests/output/world_saves/`),
  `--kd-camera=home,dx,dy,mpp`, `--kd-benchmark=N --kd-bench-home` (volo sul villaggio, con draw call, memoria,
  fotogramma peggiore e tempi dei sistemi), `--kd-hide-layers=A,B` per profilare un livello alla volta.

### 11.1r Consolidamento dei sistemi (dopo la Fase 19)
Analisi in `SYSTEM_CONSOLIDATION_AUDIT.md`, esito in `SYSTEM_CONSOLIDATION_REPORT.md`. Regola: una meccanica resta
separata solo se crea decisioni diverse; i doppioni si uniscono, non si tolgono.
- **Un nome per misura.** Regno: `KingdomState.stability` (**Stabilità**, era `order`), `legitimacy`, `prestige`,
  `turbulence` (fattore interno della Stabilità); prima della corona `authority` (transitoria: all'incoronazione
  fonda il 60% della prima Legittimità e il 30% della prima Stabilità, `families.json` → `monarchy`). Insediamento:
  `SettlementState.trust` (**Fiducia**, era `happiness`) con `trust_parts`. Modificatori: `stability.base` (era
  `order.base`), `trust.base` (era `stability.base`, che spostava la fiducia), `stability.tolerance`. Bilanciamento:
  `crown.json` → `stability` (era `order`) e `revolt` (era `stability`: anni stabili e rivolte); `population.json` →
  `trust`. Eventi: effetti `stability`, `trust`; condizioni `max_stability`, `min_trust`, `max_trust`.
- **Famiglie ⊂ Ceti.** `FamilySystem.estate_of(world, k, f)` deduce il ceto (mai salvato): origine del lavoro →
  `families.json` → `estates.origin_estate`; dopo la corona `FamilySystem.ROYAL` per la casa reale
  (`KingdomState.royal_family`, ritrovata da `CourtSystem.royal_family_of` nei salvataggi vecchi) e `nobility` per
  `noble_ids` (le più influenti sopra `noble_influence`, una casata ogni `noble_people_per_house` abitanti, più le
  imparentate con la corona: `kin_of`). `families_by_estate` conta i membri una volta e decide la nobiltà una volta.
  `FamilySystem.influence` (era `reputation`). La scheda Ceti (`EstatesPanel`) ha due modi, comunità e poteri; la
  scelta della casa reale sta nelle schede di famiglia della comunità.
- **Cronaca** (`GameSession._write_chronicle`): le voci hanno `kingdom` e, se c'è, `other`; si registra tutto ciò che
  tocca il giocatore e, degli altri, solo `WORLD_KINDS` (guerre, paci, conquiste, rivolte, morti e successioni dei re)
  e le fondazioni.
- **Spiriti**: `NationalSpiritSystem.MAX_SPIRITS` = 4, `MAX_INITIAL` = 3; `_make_room` riporta a 4 i salvataggi vecchi,
  uno all'anno.
- **Mappe**: `map_modes.json` → `tier` (`primary`/`secondary`); `MapModeMenu` mette le secondarie in «Altre mappe».
- **Economia**: `EconomyPanel.needs_of(world, k, s)` («COSA MANCA») legge solo dati già misurati.

### 11.2 Shader del terreno (volutamente semplice)
Ingressi: altitudine, bioma, foresta, acqua/costa, palette dei biomi, una sola texture di rumore tassellabile, `albedo_far`
(in Fase 3: id provincia e colori politici; più avanti: visibilità).
Fasi: colore di bioma sfumato → leggera tinta del sottobosco → rilievo accennato (parametro `relief`, luce da nord-ovest)
→ roccia/neve in quota → acqua piatta con profondità e sottile linea di riva → albedo illustrato da lontano.

### 11.3 Livelli di dettaglio (dati in `balance/lod.json`)
| Zoom (m/pixel) | Terreno | Vegetazione | Edifici | Persone/soldati | Eserciti |
|---|---|---|---|---|---|
| > 40 | albedo illustrato + montagne | masse nel colore | simboli capitali/città | — | stendardo con numero |
| 7,5–40 | biomi/albedo + montagne | gruppi di alberi come icone | simboli insediamenti | — | stendardo + blocco |
| 2–9 | biomi + rilievo accennato (+ montagne sopra 5) | gruppi di alberi | sprite edifici | — | blocchi di formazione |
| < 2,2 | biomi + rilievo accennato | alberi singoli | sprite edifici | — | blocchi di formazione |
| < 1 | come sopra | alberi singoli (nessuna animazione) | sprite edifici | abitanti (pochi frame) | soldati (pochi frame) |

Dissolvenze incrociate fra livelli; isteresi per evitare lampeggi.

### 11.4 Prestazioni
Culling per chunk sul rettangolo di vista; pool per agenti e soldati; MultiMesh per vegetazione, montagne e soldati;
atlanti di sprite; aggiornamenti distribuiti; simulazione lontana astratta; profiling a ogni fase (obiettivo 60 fps su
RTX 3060 a 1080p con la mappa intera e 20 regni attivi).

Regole emerse dalle misure della Fase 19 (città di stress da 1000–2000 abitanti, vedi `ROBUSTNESS_REPORT.md`):
- **Niente conteggi sull'intero insediamento dentro un ciclo per unità.** `SettlementState.capacity` è in cache
  per mondo + `buildings_version` (+ numero di edifici); `_free_home` conta i letti occupati una volta sola;
  `assign_jobs` usa un insieme per id. Ogni cambio di stato di un edificio passa da `world.buildings_changed()`.
- **Le liste di lavoro si aggiornano, non si buttano.** Gli alberi che ricrescono entrano nelle liste dei boscaioli
  che li raggiungono (`SettlementSim._add_regrown`), nello stesso ordine di una lista ricostruita.
- **Il caso della simulazione ora per ora vale un quarto d'ora** (`_rand` usa `int(t * 4)`): un'azione più breve
  seguita da una nuova scelta nello stesso quarto d'ora ripesca gli stessi numeri. Dopo una passeggiata oziosa si
  sta fermi; chi aggiunge azioni brevi deve tenerne conto.
- **Il passaggio da «per aggregato» a «ora per ora»** (telecamera sotto 22 m/px) sveglia gli abitanti un quarto
  per ora nelle prime 4 ore (`WAKE_SPREAD_HOURS`), al primo tick osservato.
- **Disegno per persona senza cambi di trasformazione né di texture alternati**: `PeopleLayer` disegna prima
  tutte le ombre (una texture), poi tutte le figure (l'atlante), con ordinamento nativo `[y, id, indice]`.
- **La rotazione degli autosalvataggi legge solo i nomi dei file**; le intestazioni per il menu sono in cache per
  data di modifica e dimenticate a ogni scrittura (`SaveCatalogue.forget_header`).
- Ogni ottimizzazione della simulazione si verifica con una traccia mese per mese della stessa campagna, codice
  vecchio contro codice nuovo: deve restare identica (fatto per tutte quelle della Fase 19 tranne B7 e B15, che
  cambiano di proposito solo la simulazione ora per ora).

---

## 12. Pipeline degli asset (uso leggero di Blender)

- Stile unico e semplice, coerente con i mockup: colori caldi e puliti, contorni sottili, niente fotorealismo, niente volume spinto.
- **Script 2D** (`tools/art/*.py`, Python/numpy) per gli elementi semplici: vegetazione e rocce (`draw_vegetation.py`),
  montagne (`draw_mountains.py`), icone, marcatori. È la via preferita quando basta.
- **Blender solo dove serve una silhouette pulita** (edifici, unità): modelli essenziali, vista quasi dall'alto,
  illuminazione piatta (niente ray tracing/ombre complesse), render piccoli, pochi frame di animazione, poi atlante.
  Gli script Blender stanno in `art_source/blender/scripts/` e vengono scritti quando si arriva agli edifici (Fase 4).
- Uscite: `assets/<categoria>/*.png` + `*.json` (regioni, pivot al piede, dimensione in metri). Atlanti piccoli.
- Stati degli edifici: cantiere, completo, danneggiato. Nessuna variante di angolo.

---

## 13. Interfaccia

Dalla **Fase 12.5** l'interfaccia è divisa in cinque blocchi ancorati ai bordi; il centro dello schermo
appartiene alla mappa. Il montatore è `ui/settlement/settlement_hud.gd`, che non disegna più nulla di suo.

| Blocco | File | Contenuto |
|---|---|---|
| **A** fascia superiore | `ui/shell/top_bar.gd` | una fascia continua (70 px) da bordo a bordo: stemma del regno, sette merci (oro, cibo, legno, pietra, ferro, abitanti, uomini in armi) con icona da 32 px, numero e variazione del mese chiuso, poi a destra le grandi misure con il loro nome (prestigio, legittimità, ordine, fiducia; prima della corona fiducia, autorità, famiglie); tooltip ricchi. Sotto la sua estremità destra l'**orologio**: data, pausa e velocità, mappa, menu |
| **B** colonna sinistra | `ui/shell/nav_block.gd` | quattro grandi piastre con icona e freccia (`SettlementHud.LEFT_ENTRIES`): **Il mio regno** (la principale), Corte, Governo, Costruzioni (apre il pannello a destra). Prima della corona: La mia comunità, Consuetudini, Costruzioni — la Corte compare con la corona (consolidamento: il tasto «Famiglie» non c'è più, le famiglie sono nei Ceti) |
| **C** colonna destra | `ui/shell/news_panel.gd`, `ui/shell/build_column.gd` | impilati sotto l'orologio: le **Notizie** (ultime quattro, con icona, colore e «quanto tempo fa», «Vedi tutto» apre la cronaca, si ripiegano), il pannello **Costruzioni** solo quando serve (menu «Tutte le categorie», schede con immagine, descrizione, costo a icone, ore di lavoro e martello, lista che scorre), gli ispettori |
| **D** barra inferiore | `ui/shell/nav_block.gd` | una fascia da bordo a bordo con sei grandi pulsanti (`SettlementHud.BOTTOM_ENTRIES`): Esercito, Ceti, Ricerca, Economia, Diplomazia, Religione. Nessuna scheda sta in due posti: la Cronaca si apre dalle Notizie (C), Abitanti e famiglie da Il mio regno (P) |
| **E** il resto | `ui/events/event_card.gd`, `ui/map/minimap.gd`, `ui/guide/guide_panel.gd` | carta evento al centro; in basso a sinistra la **Mappa del mondo** con il menu delle mappe e sopra la guida; suggerimento di posa che segue il mouse |

- **Revisione della HUD (Fase 18, sul disegno di riferimento del giocatore)**: posizioni e ingombri seguono il
  disegno — fascia in alto, poche piastre grandi a sinistra, colonna operativa a destra, barra larga in basso,
  centro libero. Testo minimo 14 px (`SettlementHud._label`), righe delle schede a 15, valori della fascia a
  23 con ombra (`TopBar._shadow`), font di sistema con hinting leggero; marchi disegnati per freccia, menu e
  pausa (`KDTheme.chevron_texture/menu_texture`), nessun glifo di font. La prima voce della colonna sinistra usa
  la targa con i gigli (`KDTheme.primary_button_styles`); la guida (`GuidePanel`) nasce ripiegata; le notizie
  sono una riga (icona, titolo, tempo) che si apre con un clic.
- **Le schede** (`ui/shell/panel_host.gd` + `ui/shell/kd_sheet.gd`) si aprono al centro-sinistra, accanto alla colonna sinistra,
  una per volta; con `compact = true` la barra dell'host porta solo il nome della scheda aperta e la croce,
  perché la navigazione vive nei blocchi B e D. Una scheda corta è corta: `KDSheet._fit()` misura il contenuto
  e alza la cornice solo fino a `HEIGHT`.
- **La pelle dipinta** (`ui/theme/kd_ui.gd`): `assets/ui/kit.json` elenca cornici, pulsanti nei quattro stati e
  36 icone ritagliate dai fogli; `KDUi.style()` ne fa `StyleBoxTexture` a nove sezioni (gli angoli non si
  stirano), `KDUi.icon()` le texture. `ui/theme/kd_theme.gd` resta l'unico punto da cui passa il vestito:
  `wood_panel()` (cornice con la fascia del titolo), `card_panel()` (la stessa senza fascia: cartigli e
  ispettori), `dark_panel()` (pastiglie e gruppi), `button_styles()`, `close_button()`. Se un pezzo manca,
  ogni funzione ricade sui vecchi `StyleBoxFlat`: l'interfaccia non resta mai bianca.
- **La pipeline degli asset**: `tools/art/slice_ui.py` ritaglia i fogli (taglio XY ricorsivo sull'alfa),
  `tools/art/ui_contact_sheet.py` monta i provini per riconoscere i pezzi, `tools/art/build_ui_kit.py` sceglie
  i pezzi, pulisce la fascia del titolo dipinta e scrive `assets/ui/kit/` + `assets/ui/icons/` + `kit.json`.
- **Robustezza**: tutti i blocchi sono ancorati ai bordi con `MarginContainer` e `MOUSE_FILTER_IGNORE`, quindi
  nessuno ruba i clic alla mappa; il viewport logico è 1920×1080 con `canvas_items`/`expand`, quindi il disegno
  scala con la finestra e cresce sugli schermi di altra proporzione.
- Componenti riutilizzabili: `KDSheet.section/parchment/line/meter/command_button`, `NavBlock`, `TopBar`,
  `BuildColumn`, `NotificationStack`, `EventCard`, `ArmsView`.
- La mappa resta protagonista: nessuna barra fissa al centro, nessun pannello che copre più di una colonna.


### 13.2 Leggere i numeri (Fase 18)
- **Registro delle scorte**: `SettlementState.add/take(res, n, why)` scrivono in `flow` il movimento del mese per
  merce e per motivo (`work`, `food`, `build`, `trade`, `army`, `event`, `other`); `TimeSignalsSystem` all'inizio
  del mese lo sposta in `last_flow`. Si salvano entrambi (un salvataggio vecchio parte con registri vuoti).
- **Perché le misure stanno dove stanno**: `CourtSystem._measures` scrive in `KingdomState.measure_parts` le
  componenti di legittimità, ordine e prestigio e il valore verso cui tendono (non si salva, si ricalcola).
- **Tooltip ricchi**: `KDTip` (una `PanelContainer` il cui tooltip è BBCode disegnato in `RichTextLabel`) e
  `KDTipButton`; gli aiuti `head/sub/note/rows/signed` scrivono tutti i tooltip allo stesso modo (verde ciò che
  aiuta, rosso ciò che nuoce). La barra alta li riscrive una volta al secondo (`TopBar.write_tooltips`).
- **Schede**: in modalità compatta il nome e la croce della scheda stanno nella fascia dipinta della cornice
  (`PanelHost._place_head`, controllo `top_level` sopra la scheda). `KDSheet.section_in` e `check_line` (spunte
  dipinte del kit) servono anche alle schede che non sono `KDSheet`.
- **Carta evento**: categoria nella fascia, emblema della categoria in un medaglione, conseguenze scritte sotto
  ogni risposta (`EventCard.effects_bbcode`).
- **Prove visive**: `--kd-panel=build` apre la lista degli edifici, `--kd-tip=<pastiglia>` disegna aperto il
  tooltip di una pastiglia; `tools/check.ps1 -EngineArgs "--resolution 2560x1440"` passa opzioni al motore.

### 13.1 Prima e attorno alla partita (Fase 14)
- **`scenes/menu.tscn`** è la scena d'avvio: titolo, «Continua» con il nome del regno e la data dell'ultima
  partita, «Nuova partita», l'elenco dei salvataggi e l'uscita. Ogni argomento `--kd-*` salta il menù ed entra
  in partita, così screenshot, prove e strumenti funzionano come prima; `--kd-menu` chiede la porta.
- **`SaveCatalogue`** (`save/save_catalogue.gd`) è lo scaffale: legge l'intestazione dei file — giorno, data in
  parole, nome del regno e del sovrano — senza costruire il mondo, li ordina dal più recente (fino al
  millesimo di secondo) e tiene gli automatici a tre.
- **Salvataggio automatico**: `SimulationRunner` scrive una volta per anno di gioco. Costa 4 ms su una
  campagna di sessant'anni.
- **`PauseMenu`**: ESC quando nessuna scheda è aperta ferma l'orologio e apre riprendi / salva / carica /
  torna al menù / esci. La velocità di prima viene restituita alla ripresa.
- **`Minimap`** (`ui/map/minimap.gd`): il continente disegnato piccolo con i colori della modalità mappa in
  uso e il rettangolo di quel che la camera guarda; un clic ci porta la camera. L'immagine si ridisegna solo
  quando i confini cambiano o cambia la modalità, quindi non costa nulla per fotogramma.
- **La guida** (`Guide` + `ui/guide/guide_panel.gd`, passi in `data/defs/guide.json`): i primi passi di un
  regno, uno per volta, in un cartiglio in basso a sinistra. Ogni passo si chiude **da solo** quando lo stato
  del mondo dice che è stato fatto (una casa in piedi, dieci abitanti, una legge in vigore, una compagnia
  armata): nessun obiettivo finto e nessuna mano sulla mano del giocatore. Il passo raggiunto sta in
  `world.flags["guide_step"]`, quindi si salva con la campagna, e la croce la chiude per sempre.

---

## 14. Salvataggi (`res://save/`)

- File in `user://saves/<nome>.kds` = JSON compresso (`FileAccess.open_compressed`, ZSTD).
- Intestazione: `save_version` (int), `game_version`, `world_version`, data reale, anno di gioco, regno, anteprima.
- Contenuto: `WorldState` completo (i raster statici NON si salvano: si salvano solo i delta del terreno, codificati base64 per chunk).
- `SaveMigrator`: catena di funzioni `migrate_vN_to_vN+1(dict)`; un salvataggio vecchio viene **migrato**, mai rifiutato
  se esiste una migrazione. Test di round-trip e di migrazione per ogni versione.
- Autosalvataggio periodico (dati).
- Versione corrente **5** (Fase 15): famiglie e legami; `_v4_to_v5` segna ogni regno come monarchia già
  fondata e aggiunge un elenco di famiglie vuoto. L'autosalvataggio non scrive nulla al giorno 0.
- **Scrittura atomica** (Fase 19): `SaveSystem.save_to_file` scrive `<slot>.kds.tmp` e lo rinomina sul file
  vero solo quando è intero. Un gioco chiuso a metà salvataggio, o un disco pieno, lasciano lo slot com'era;
  l'elenco del menu ignora i `.tmp` (non finiscono in `.kds`). Un file tronco o che non è un salvataggio viene
  rifiutato (`load_from_file` → `null`, il menu non lo elenca).
- **Autosalvataggio** (Fase 19): `SimulationRunner._autosave_if_due` salva quando l'anno di gioco è cambiato
  dall'ultima volta che ha guardato, non in un giorno esatto (ad alta velocità più giorni passano in un frame e
  quel giorno poteva essere saltato). La partita appena iniziata o caricata non si risalva subito. Screenshot,
  benchmark e `--kd-no-autosave` non scrivono mai nella cartella del giocatore.
- **Caricamento rapido (F9)** (Fase 19): come il menu di pausa, adotta la sessione caricata e ricostruisce la
  scena (`reload_current_scene`); l'avviso «Partita caricata» attraversa la ricostruzione in
  `Session.pending_notices` e lo dice il nuovo HUD. Verificato da `tests/tools/quickload_check.tscn`.
- **Compatibilità**: `tests/fixtures/saves/phase18_*.kdsave` sono salvataggi scritti dalla build della Fase 18
  (prima del world art pass); `test_save` li apre, li legge dal menu, li fa andare avanti e li riscrive.
- Versione corrente **6** (consolidamento): `_v5_to_v6` porta `order` → `stability` nei regni, `happiness` → `trust`
  negli insediamenti e rinomina le chiavi dei modificatori nelle crisi salvate (`SaveMigrator.renamed_modifier_key`).

---

## 15. Test e verifiche

- Runner headless: `godot --headless --path "<ROOT>" -s res://tests/test_runner.gd` → codice d'uscita ≠ 0 se fallisce.
- Suite: validazione dati · caricamento mappa · invarianti del mondo (connettività, province) · orologio e scheduler ·
  modificatori · comandi (motivi di rifiuto) · salvataggio round-trip e migrazioni · simulazione di N anni senza errori
  e con invarianti (scorte ≥ 0, popolazione coerente, province con proprietario valido) · battaglie deterministiche ·
  IA che non si blocca.
- `tools/check.ps1`: import del progetto (`--headless --import`), controllo errori nel log, test, screenshot.
  Dalla Fase 19 ogni riga `ERROR:` del motore fa fallire il controllo (prima passavano quelle senza `res://`
  sulla stessa riga, come «Invalid polygon data»), tranne gli errori che i test provocano apposta per vedere
  che un input sbagliato viene rifiutato: sono elencati uno per uno in `$ExpectedTestErrors`.
- Filtro dei test: `-TestFilter test_events,test_stress` (pezzi del nome del FILE separati da virgole) esegue
  quei file nello stesso processo e nell'ordine della suite: serve a vedere se un test ne disturba un altro.
- **Stress test** (Fase 19): `tests/stress/stress_runner.tscn -- --kd-stress=city,sites,war,pacts
  [--kd-people=1000,2000]` costruisce con `StressWorlds` (solo funzioni del gioco: il planner trova i posti,
  `PopulationSystem.welcome` accoglie le persone, `Military` arruola, i comandi dichiarano guerra, `Diplomacy`
  firma dove le regole lo permettono) mondi oltre una campagna normale e misura giorno per aggregato, giorno ora
  per ora, mese del signore, percorsi, salvataggio e caricamento, catalogo dei salvataggi; poi controlla la
  coerenza del mondo. Rapporto in `tests/output/stress/stress_report.md`. Gli stessi mondi si guardano col
  renderer: `--kd-scenario=stress_city [--kd-people=N]` e `--kd-scenario=stress_war`, con `--kd-benchmark`.
- Screenshot di controllo: `godot --path "<ROOT>" -- --kd-screenshot=<file> --kd-camera=x,y,zoom --kd-frames=N`
  per verificare visivamente mappa e zoom senza aprire l'editor.

---

## 16. Convenzioni di codice

- GDScript **tipizzato** (`var x: int`, funzioni con tipi di ritorno), `class_name` per le classi di dominio.
- Identificatori in inglese; testi dell'interfaccia in italiano tramite chiavi di traduzione (`tr()`), file in `ui/i18n/`.
- Nessun numero di bilanciamento nel codice: sempre da `Defs`/`balance`.
- Un file = una responsabilità; niente "manager" onnivori; niente funzione IA gigante.
- Autoload minimi: `Defs` (definizioni), `EventBus` (segnali), `Session` (partita corrente). Tutto il resto è istanziato.
- Log con categorie (`KDLog.info("economy", …)`), livelli configurabili.

