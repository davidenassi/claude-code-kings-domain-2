# KING'S DOMAIN — REBIRTH · DIARIO DELLE FASI

Il diario del Rebirth, fase per fase: che cosa è stato fatto, come è stato verificato, che cosa resta aperto.
Il piano è in `KINGSDOMAIN_REBIRTH_AUDIT.md`; il rapporto finale sarà `KINGSDOMAIN_REBIRTH_FINAL_REPORT.md` (Fase 14).

Ambiente di verifica: Godot 4.7.2 ufficiale (Linux, headless per i test; Xvfb + OpenGL software per le schermate).
Le schermate sono in `docs/rebirth/` (JPG); gli FPS di questo ambiente (rendering software, 5–10 fps) **non** sono
misure di prestazione: quelle vanno prese su una GPU vera (Fase 14).

---

## FASE 0 — Audit completo e nuova architettura ✅

**Fatto**
- Progetto ricostruito dal pacchetto d'ispezione in `progetto/` (295 file, stessi percorsi).
- Dati esclusi dal pacchetto **rigenerati** con gli strumenti del progetto: mappa ufficiale (raster, province, confini,
  fiumi, albedo), canopy, texture di rumore, atlanti di edifici, oggetti, vegetazione, montagne e persone.
  I raster coincidono **al byte** con le dimensioni scritte nel `world_meta.json` originale; i JSON degli atlanti sono
  identici. Script unico: `tools/setup_generated.sh` (con verifica finale).
- `tools/check.sh`: import + test + schermata per Linux/CI (stesse regole di `tools/check.ps1`).
- `KINGSDOMAIN_REBIRTH_AUDIT.md`: 18 assunzioni della mappa unica con file e riga, ogni sistema classificato
  KEEP / REFACTOR / REPLACE / REMOVE / MIGRATE, la nuova architettura (GAME STATE → GLOBAL WORLD + LOCAL DOMAIN), la
  scala della patria, i salvataggi v7, i rischi e il piano sul codice reale.

**Base di partenza (misurata qui, codice non toccato)**
- Suite completa: **210 test, 10 017 asserzioni, 0 fallimenti**, 30 min 6 s (headless, CPU di questo ambiente).
- Unici messaggi d'errore del motore: le texture del kit dipinto dell'interfaccia che il pacchetto non contiene
  (`assets/ui/kit/*.png`, `assets/ui/icons/*.png`), attesi.
- Schermate BEFORE: `docs/rebirth/before/` — `b01_spawn` (0,35 m/px), `b07_zoom_close` (0,12), `b08_zoom_medium` (2),
  `b09_zoom_far_local` (8), `b10_global_strategic` (14), `b10b_continent` (62).

**Scoperta utile**: nessun regno dell'IA ha un insediamento fisico; solo il giocatore ne ha uno. La separazione
«dettaglio del giocatore / astrazione del mondo» esiste già nella simulazione: manca nello spazio, nella resa e
nell'interazione. È ciò che rende la Fase 1 fattibile senza riscrivere i sistemi di regole.

---

## FASE 1 — Separazione mappa locale / mappa globale ✅

**Fatto**
- **Due spazi, una simulazione.** `WorldState.domain` (`world/domain/domain_state.gd`) descrive la valle della patria:
  insediamenti, edifici, persone, alberi, rocce e delta del terreno vivono nei **metri della valle**; province, regni,
  eserciti e battaglie nei metri del continente. Una sola regola di corrispondenza (`DomainState.to_global/to_local`,
  `WorldState.settlement_global_pos`), usata dove il mondo globale tocca la patria: la schiera nasce fuori dalla
  capitale sulla mappa del mondo, si rifornisce e vede dalla capitale, si scioglie tornando a casa.
- **Il terreno della valle** (`world/domain/domain_data.gd`, sottoclasse di `WorldData`: stesse interrogazioni).
  In questa fase è un **ritaglio** del continente di 8 064 × 6 144 m allineato a 192 m (mcm fra la griglia degli alberi
  e le celle dei raster): gli alberi e le rocce sono **gli stessi** del continente (provato albero per albero).
  `LocalFeatures`, `Placement`, `SettlementSim`, `SettlementAggregate`, il pianificatore, la corte e l'ispettore
  degli edifici leggono il terreno della valle; il continente lo leggono solo i sistemi globali.
- **Due scene**: `scenes/local/local_view.tscn` (terreno, acqua, rive, boschi, edifici, oggetti, persone, eserciti
  nella valle, nebbie del bordo, costruzione, clic sugli edifici) e `scenes/global/global_view.tscn` (terreno
  dipinto, fiumi, montagne, boschi lontani, eserciti, confini, selezione, modalità mappa, nomi e stemmi, clic su
  province ed eserciti). `scenes/main.tscn` è solo il guscio: sessione, orologio, HUD, passaggio fra le mappe.
  Gli scenari di prova sono in `scenes/scenarios.gd`.
- **Camere con limiti propri**: la valle va da 0,05 m/px (persone) a tutta la valle (~6 m/px su 1920 px) e la
  vista non esce mai dalla valle oltre il bordo di nebbia; il mondo va da 6 m/px (mai le case) a 80 m/px.
  Rotella oltre il limite della valle → «Questa è tutta la valle. Oltre le nebbie: la mappa del mondo (Tab)».
- **Passaggi**: Tab; pulsante «Mondo» dell'orologio; pulsante della minimappa («Mappa del mondo» / «Torna al
  dominio»); doppio clic sulla patria nella mappa del mondo; «Costruzioni» dal mondo riporta alla valle; «Muovi»
  di una schiera porta al mondo; «Vai sul posto» delle notizie va sulla mappa giusta (`EventBus.notification` porta
  ora lo spazio del luogo).
- **Regime della simulazione dalla mappa**, non dallo zoom: valle sul tavolo → ora per ora; mondo → per giorni.
- **Minimappa** della mappa sul tavolo (la valle con i suoi edifici, o il continente con le modalità mappa).
- **Bordo della valle**: nebbie e nuvole (`shaders/domain_edge.gdshader`) oltre e sul bordo; nulla oltre la valle
  viene disegnato come mappa.
- **Salvataggi v7** con migrazione esatta dei v6 (§3.7 dell'audit), provata su un mondo con edifici, strade,
  persone in movimento, ceppi e rocce cavate: dopo la migrazione il mondo è identico al millimetro.
- Robustezza: il kit dipinto mancante ora ricade davvero sugli stili disegnati (prima: riquadri trasparenti);
  il riquadro di debug è nascosto di default (F3, problema noto n. 1).

**Prove**
- Nuovo `tests/unit/test_domain.gd` (7 prove, 90 asserzioni): la valle e il suo insediamento; corrispondenza fra i
  metri; stessi alberi e rocce del continente; la schiera sulla mappa del mondo; la valle nel salvataggio;
  migrazione v6 → v7 esatta; la scena con due mappe (una sola camera attiva, limiti, nessuno zoom che le unisce,
  regime della simulazione, HUD collegata a entrambe).
- Test esistenti aggiornati dove leggevano il continente per guardare il villaggio (stessa semantica, terreno della
  valle); ascoltatori delle notifiche con il nuovo argomento; `test_visual` controlla l'icona dipinta solo se il kit
  c'è.
- Suite completa: **217 test, 10 109 asserzioni, 0 fallimenti** (con la correzione di `test_visual` inclusa in
  questo commit; senza, 1 fallimento dovuto solo al kit mancante in questo ambiente).

**Schermate** (`docs/rebirth/phase1/`): `p1_local_spawn` (0,35 m/px), `p1_local_medium` (2), `p1_local_far` (tutta
la valle con le nebbie), `p1_global` (la patria sulla mappa del mondo, 14 m/px), `p1_global_far` (il continente).

**Limiti dichiarati di questa fase**
- La valle è ancora un ritaglio quadrato del continente: la **patria vera**, finita e chiusa da confini naturali, è
  la Fase 2.
- Gli eserciti nella valle sono solo disegnati alla loro posizione (la difesa della patria è la Fase 10).
- Le nebbie del bordo sono una resa semplice; l'esplorazione vera è la Fase 8.

---

## FASE 2 — La patria di Valverde (vertical slice) ✅

**Obiettivo**: la prima impressione deve essere «sono dentro una vera regione in cui posso fondare qualcosa», non «sono
un punto dentro un continente». Un solo regno (Valverde), nessuna replica sugli altri.

**Fatto**
- **Generatore delle patrie** `tools/domaingen/generate_domains.py` (Python 3 + numpy, deterministico: `--check`
  rigenera e confronta al byte) dalla geografia disegnata in `data/domains/homelands.json`.
- **Valverde** (`data/domains/valverde/`, 8 064 × 6 144 m, rilievo, boschi e biomi a 8 m, acque a 4 m):
  - un **fondovalle** arrotondato e ondulato (~44% della patria) con colline, prati, piana fluviale;
  - un **anello di montagne** (fino a 2 570 m, neve sulle cime, roccia sui pendii ripidi) che chiude la valle;
  - **quattro vie d'uscita**: la *Gola del Chiaro* e la *Stretta di Valle* (il fiume entra ed esce nelle sue gole),
    il *Passo del Lupo* (a nord, 880 m) e il *Varco delle Querce* (a est) — oltre, le nebbie dell'ignoto;
  - il fiume **Chiaro** che attraversa la valle con le sue anse, il **Lago di Valverde** con il suo emissario, un rio
    che scende dai monti;
  - **boschi come masse** (Bosco Nero, Selva di Ponente, Bosco del Focolare…): nuclei fitti, margini irregolari,
    radure; i pendii boscosi fino al limite degli alberi; rive e passi aperti;
  - **risorse garantite**: acqua a meno di 200 m dal fuoco, un bosco accanto, pietra a pochi passi (sempre), altre
    sei cave sulle colline, **ferro** in due punti ai piedi dei monti; terra fertile dal lato dei campi;
  - il **sito di fondazione** scelto dal generatore: piano, asciutto, a 90–170 m dal fiume, al margine di un bosco;
  - le **cime illustrate** del bordo (83 sprite, gli stessi dei monti del continente, alla scala della valle) e i
    **nomi**: catene, passi, fiume, rii, lago, boschi, il villaggio.
- **Nel gioco**: `DomainData` carica la patria (45 ms); la nuova partita nasce a Valverde; la valle è un'unica
  provincia; gli alberi seguono il bosco disegnato (e nei boschi fitti le chiome si toccano); la roccia compare dove
  il pendio è ripido; `LocalLabels` scrive i nomi della valle; sulla mappa del mondo la patria sta dentro la sua
  provincia, con la capitale sotto il nome del regno.
- **Pianificazione**: il villaggio di partenza e il signore prudente mettono il taglialegna al margine del bosco e i
  campi dal lato aperto (in una valle con boschi veri un taglialegna nel prato non ha nulla da tagliare).
- **Correzione trovata dal cambio di geografia**: le prime pagine della cronaca (prima casa, primo raccolto, il
  villaggio, la fine) erano scritte una volta al mese dal `FamilySystem`, così «il villaggio è nato» poteva arrivare
  dopo che la comunità poteva già scegliere la corona. Ora le scrive `CommunityMilestonesSystem` alla fine di ogni
  giorno, dopo nascite e arrivi.

**Prove**
- Nuovo `tests/unit/test_homeland.gd` (6 prove): la partita nasce nella patria; la valle è chiusa dai monti tranne
  ai passi (il bordo è alto ovunque, ogni punto basso è un passo) e il fondovalle è ampio; il fiume passa per le sue
  gole e il lago ha acqua; acqua, legna, pietra, ferro e terra fertile a portata dei fondatori, e una casa e una cava
  ci stanno; i boschi sono masse (fitti dentro, aperti fuori); la patria viaggia con il salvataggio.
- `test_domain` (Fase 1) usa il ritaglio del continente dove prova proprio quello (`{"homeland": "none"}`).
- Test esistenti adattati al paesaggio nuovo, con la stessa intenzione: il taglialegna delle prove va al margine del
  bosco; `test_economy::test_twenty_years_of_a_prosperous_village` conta i bambini nei vent'anni e non solo
  nell'ultimo giorno (nel fondovalle fertile il villaggio che il signore tiene a trenta anime riempie i letti al terzo
  anno e poi invecchia: un bambino nasce solo se c'è un letto libero).
- **Esito** (suite completa sullo snapshot della Fase 2, 30 min 36 s): 223 prove, 10 128 asserzioni, 2 fallimenti,
  entrambi corretti e riverificati a parte:
  `test_visual::test_the_woods_have_a_shape_and_keep_their_trees` (la prova dei boschi del continente ora gira sul
  ritaglio, `{"homeland": "none"}`) e `test_identity::test_work_fills_the_registers_that_feed_the_spirits` (il
  taglialegna della prova stava accanto al deposito, in campo aperto: ora al margine del bosco, come nelle altre
  prove). Riverificate dopo le correzioni: `test_homeland`, `test_domain`, `test_visual`, `test_military`,
  `test_identity`, `test_save` — 0 fallimenti.
- **Problema scoperto e non più nascosto**: `test_save::test_saves_of_an_older_build_still_load_and_play_on` apre due
  salvataggi della Fase 18 che non sono nel pacchetto (Audit §0.1) e finora «passava» con un errore di script.
  Ora il test runner ha lo stato `SKIP` con il motivo (`KDTestCase.skip`), e la riga finale conta le prove saltate:
  `TESTS: … failures, 2 skipped`. La migrazione dei salvataggi v5 resta coperta dalle altre prove di `test_save` e
  `test_founders`, ma non su quei due mondi reali.

**Schermate** (`docs/rebirth/phase2/`): `p2_far` (tutta la valle, ~6 m/px: monti, passi, lago, fiume, boschi, nomi,
nebbie), `p2_medium` (1,6 m/px), `p2_near` (0,6), `p2_spawn` (0,35, il primo giorno), `p2_close` (0,12),
`p2_global` (la patria sulla mappa del mondo), `p2_valverde_generator_map` (la mappa del generatore).

**Confronto con prima** (`docs/rebirth/before/`): prima, a 8 m/px, un quadrato di bosco uniforme dentro un continente
senza fine; ora, alla stessa distanza, una valle chiusa e nominata con i suoi monti, le sue acque e le sue uscite.

**Limiti dichiarati**
- La resa è ancora quella degli asset attuali (sprite numpy, terreno a tinte): è il livello da cui partirà la Fase 12.
  Da vicino i boschi sono alberi singoli un po' radi ai margini; i monti del bordo sono gli sprite del continente.
- Una sola patria (Valverde); le altre arrivano con la Fase 11.
- I passi sono geografia e nomi; attraversarli (esploratori, mercanti, eserciti) è la Fase 8.
- La densità delle chiome dipende dal disegno del canopy: il generatore non produce ancora sottobosco, sentieri
  di caccia o alberi isolati «monumentali».
