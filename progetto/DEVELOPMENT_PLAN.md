# KING'S DOMAIN — DEVELOPMENT PLAN

Sviluppo per fasi. **Il progetto resta eseguibile alla fine di ogni fase.**
Regola di ogni fase (vale sempre):
1. avviare il progetto; 2. controllare gli errori Godot; 3. correggere; 4. testare le funzioni nuove;
5. verificare che le precedenti funzionino ancora (test di regressione); 6. aggiornare `DEVELOPMENT_STATUS.md`
(completato / parziale / da fare / problemi / prossima fase); 7. commit Git.

Una funzione è "completa" solo se **funziona nel gioco** e ha una verifica (test automatico o screenshot).
Nessun sistema finto: placeholder grafici sì, placeholder di logica no.

---

## FASE 0 — Analisi ✅
- Analisi di Regno.html, inventario dei sistemi, separazione tenere/trasformare/eliminare, dipendenze.
- Ispezione della cartella ufficiale e degli strumenti (Godot 4.7.2, Blender 5.2 + numpy, Git).
- Documenti: `LEGACY_SYSTEM_AUDIT.md`, `GAME_DESIGN_MAP.md`, `TECHNICAL_ARCHITECTURE.md`, `DEVELOPMENT_PLAN.md`.

## FASE 1 — Fondazione Godot
**Obiettivo:** progetto pulito, eseguibile, testabile da terminale.
- `project.godot`, struttura cartelle, `.gitignore`, `.gdignore`, repository Git.
- Autoload: `Defs`, `EventBus`, `Session`.
- Core: `KDLog`, `GameCalendar` (giorni, mesi, stagioni, date), `SimClock` (velocità, accumulo), `Scheduler`
  (frequenze e rotazione), `KDRng` (generatori per sistema, stato serializzabile), `ModifierStack`, `Command` base + `CommandResult`.
- Data layer: caricatore JSON → `Resource` tipizzate con validazione; primi file (`resources`, `terrain_types`, `balance/time`).
- `WorldState` minimo + `GameSession` (nuova partita / avanzamento giorni).
- Salvataggio: `SaveSystem` + `SaveMigrator` con `save_version = 1`, round-trip.
- Scena `Main`: camera 2D con pan/zoom continuo, overlay di debug (data, velocità, zoom), controlli velocità.
- Strumenti: `tools/check.ps1` (import + test + screenshot), runner di test headless, argomenti di screenshot.
**Accettazione:** import senza errori; test verdi (calendario, scheduler, rng, modificatori, dati, save round-trip);
screenshot della scena; il gioco si avvia, la data avanza, pausa/velocità funzionano.

> **Direzione grafica (17/09/2026):** in tutte le fasi la resa visiva segue TECHNICAL_ARCHITECTURE §11: 2D semplice,
> leggero e leggibile; animazioni a pochi frame; a parità di effetto si sceglie la soluzione meno costosa.

## FASE 2 — Mondo (2D semplice)
**Obiettivo:** la grande mappa ufficiale visibile e navigabile con zoom continuo.
- Generatore `tools/worldgen` (Python/numpy): continente unico, montagne con passi, fiumi naturali, laghi, clima,
  biomi, foreste, depositi, anteprime e report di verifica. Output committato in `data/world/`.
- Loader dei raster e `WorldData` con query (altitudine, bioma, acqua, foresta per posizione).
- `TerrainLayer` + shader semplice (biomi sfumati, rilievo accennato, acqua piatta, albedo illustrato da lontano).
- Fiumi vettoriali.
- Vegetazione: sprite 2D piatti, alberi singoli da vicino e masse di bosco a zoom mappa (MultiMesh a chunk).
- Camera: limiti, zoom verso il cursore, inerzia; isteresi LOD.
**Accettazione:** test di invarianti della mappa (un continente, connettività, fiumi al mare/laghi); screenshot a 5 livelli
di zoom coerenti e senza artefatti gravi; ≥60 fps a vista continentale e locale.

## FASE 3 — Province e regni
- Generazione province irregolari (~400) con confini misti geografici/politici, adiacenze e tipi di confine.
- `ProvinceState`, `KingdomState`, setup iniziale dei regni da `start_setup.json`.
- Confini vettoriali di provincia e di regno (ricalcolati al cambio di proprietà), velatura politica.
- Selezione/hover di provincia, ispettore provincia.
- Map mode: politico, terreno, culture, religioni, risorse, sviluppo, popolazione (fondamenta).
- Nomi di regni e province con dissolvenza per zoom; stemmi procedurali (eredità Araldica).
**Accettazione:** test (ogni cella di terra ha una provincia, adiacenze simmetriche, nessuna provincia degenere,
cambio di proprietario aggiorna confini); screenshot map mode; click su provincia mostra dati corretti.

## FASE 4 — Insediamento
- Luogo di partenza: re + 6 abitanti + mastio di legno + riparo + scorte iniziali.
- Chunk locali materializzati (alberi, rocce, terreno a 2 m) con delta salvati.
- Piazzamento edifici con anteprima, verifiche (terreno, pendenza, ostacoli, accesso, territorio, materiali) e motivi di rifiuto.
- Cantieri con consegna materiali e costruttori; primi edifici: casa, taglialegna, cava, fattoria/campi, granaio, magazzino, pozzo, forno, strada.
- Lavoratori: assegnazione automatica, priorità, quota costruttori; abbattimento reale degli alberi e rimozione rocce.
- Agenti visivi degli abitanti vicino alla camera.
**Accettazione:** partendo da 7 persone si costruisce un taglialegna che abbatte alberi *visibili*, il legno entra nelle scorte,
si costruisce una casa su terreno liberato; salvataggio e caricamento conservano alberi abbattuti ed edifici; test di simulazione di 2 anni.

## FASE 5 — Economia e popolazione
- Catene complete (grano→pane, ferro+legno→armi), depositi e capacità, trasporti a flussi, strade che cambiano i tempi.
- Nascite, morti, invecchiamento, viandanti, felicità/consenso, alloggi, servizi, salute.
- Classi sociali; salari; tesoro; tasse; mercato regionale con prezzi.
- Crescita organica: il villaggio si espande; progressione emergente (insediamento → villaggio → borgo).
- Popolazione a coorti per i regni IA; rendite di provincia; controllo amministrativo.
**Accettazione:** simulazione headless di 20 anni: popolazione cresce in condizioni buone e crolla con carestia; bilanci coerenti;
lo stesso salvataggio caricato produce gli stessi esiti.

## FASE 6 — Cultura, religione, spiriti nazionali
- Definizioni fisse di 6 culture e 4 religioni (modificatori da dati), assegnate a province e regni.
- `ModifierStack` per regno con fonti nominate e tooltip di scomposizione.
- Spiriti nazionali iniziali derivati dalla geografia; registri di azioni; evoluzioni/rami/scomparse.
**Accettazione:** test che due regni con geografia diversa ottengano spiriti diversi; test di evoluzione di uno spirito
dopo le azioni richieste; UI mostra la formula dello stato del regno.

## FASE 7 — Politica
- Personaggi, tratti, dinastie, consorti, eredi, educazione, morte, successione, crisi dinastiche, pretendenti.
- Misure della corona (prestigio, legittimità, ordine, fiducia) con le formule di Regno estese.
- Fazioni (nobiltà, popolo, mercanti, esercito, clero): favore, influenza, richieste, crisi, doni.
- Governo: forma dello Stato e riforme, leggi, editti, corte e consiglieri, istituzioni fisiche.
**Accettazione:** test di successione (erede adulto/minorenne/assente); test di leggi con vincitori e perdenti;
partita headless di 60 anni con almeno due cambi di sovrano senza errori.

## FASE 8 — Diplomazia e IA
- Relazioni, opinioni, reputazione, patti, alleanze, rivalità, matrimoni, tributi, vassallaggi, guerre e paci.
- IA: valutatore strategico, personalità dal sovrano, scopi, planner, utility scoring, memoria (rancore/stima), motivazioni leggibili.
**Accettazione:** simulazione di 50 anni con 20 regni: regni con sovrani diversi producono comportamenti diversi misurabili
(statistiche di guerre, edifici, commercio); nessun blocco; log delle motivazioni.

## FASE 9 — Esercito
- Reclutamento da persone reali, scuole, code, leva, armeria, paghe e diserzioni.
- Unità data-driven (incluse alabardieri, balestrieri, cavalieri, capitano) con nuovi requisiti di sblocco.
- Eserciti sulla mappa: movimento su strade/terreno, rifornimenti, comandanti, LOD visivo (stendardo → blocchi → soldati).
- Fog of war militare.
**Accettazione:** un esercito reclutato marcia fisicamente su una rotta, consuma rifornimenti, è visibile ai livelli di zoom
corretti; i nemici fuori vista non sono mostrati.

## FASE 10 — Guerra
- Battaglie sulla mappa (modello a reggimenti + rappresentazione a soldati), terreno reale, ritirate.
- Assedi con mura/porte/torri/macchine; blocco e assalto; danni persistenti.
- Conquista senza reset, devastazione, occupazione, pace con condizioni, stanchezza di guerra, conseguenze economiche e politiche.
**Accettazione:** scenario di test: due eserciti si incontrano in una provincia collinare con un fiume → combattimento calcolato,
perdite, morale, ritirata dello sconfitto, assedio della città, conquista con edifici e popolazione conservati; stesso esito a ogni esecuzione con stesso seme.

## FASE 11 — Eventi e rigiocabilità
- `EventSystem` data-driven (condizioni, peso, cooldown, opzioni, effetti, catene); porting degli eventi di Regno.
- Crisi di lungo periodo condizionali; tecnologie con specializzazioni esclusive; cronaca completa e finale; obiettivi di campagna.
**Accettazione:** 5 campagne headless da 100 anni con semi diversi producono storie diverse (confini, dinastie, spiriti).

## FASE 12 — UI
- HUD definitivo (tema legno/oro/pergamena), sezione **Regno** in evidenza, pannelli Corte, Governo, Leggi, Editti,
  Diplomazia, Esercito, Economia, Tecnologia, Cronaca, ispettori, tooltip con scomposizione modificatori, notifiche e scelte.
**Accettazione:** ogni sistema giocabile è raggiungibile da UI; screenshot a 1080p e 1440p; nessun testo tagliato.

## FASE 13 — Ottimizzazione
- Profiling, LOD, caching, pooling, aggiornamenti distribuiti, salvataggi grandi, test di stress (anno 150, 20+ regni, migliaia di edifici).
**Accettazione:** obiettivi di fps e tempi di salvataggio/caricamento raggiunti e misurati.

## FASE 14 — Polish
- Asset completi e coerenti ma semplici, animazioni essenziali a pochi frame, audio placeholder/finale, feedback visivi
  leggeri, bilanciamento, bug fixing.

---

## Ordine consigliato di lavoro all'interno delle prime fasi
1. Fase 1 completa (fondazione e strumenti di verifica: servono a tutto il resto).
2. Generatore del mondo e rendering (Fase 2) — la mappa è la protagonista e la base dati di tutto.
3. Province e regni (Fase 3) prima dell'insediamento, perché il luogo di partenza è una provincia vera.
4. Insediamento ed economia (Fasi 4–5) — il cuore dell'identità "vedo un regno nascere".

