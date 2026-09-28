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

---

## FASE 3 — Il nucleo della comunità ✅

**Obiettivo**: dare subito un centro e un significato allo spazio iniziale. Sei fondatori (tre uomini, tre donne),
nessun re, nessun castello: un **nucleo della comunità** da cui nasce tutto. «Questa è la mia comunità» deve
capirsi al primo sguardo; il punto iniziale non deve sembrare uno spawn casuale; gli abitanti devono avere un luogo a
cui appartengono; la crescita futura deve essere immaginabile.

**Prima** (`docs/rebirth/phase2/p2_spawn.jpg`, `p2_close.jpg`): due capanne in un prato, due fuochi dipinti negli
sprite del deposito e del riparo, i fondatori addormentati (la partita cominciava a mezzanotte), nessun legame visibile
con il fiume, il bosco o i campi.

**Fatto**
- **Il nucleo** (`settlement/nucleus.gd`, classe `Nucleus`) posato dalla fondazione:
  - il **focolare comune** (`hearth`, edificio del mondo: si salva, si seleziona, i costruttori lo rispettano) al
    centro dell'insediamento: anello di pietre, braci, tronchi incrociati, treppiede con il paiolo, tre panche di
    tronco spaccato; fiamme, bagliore e fumo sono disegnati vivi;
  - la **piazzola comune**: un raggio di 9 m attorno al fuoco dove non si costruisce (`Placement`: «La piazzola del
    focolare resta libera: è il cuore della comunità»), disegnata come terra battuta dal primo giorno;
  - il **piccolo deposito** (`camp_store`, ora «Primo deposito») e il **riparo** dietro il fuoco, dal lato opposto
    all'acqua: la piazzola si apre verso il fiume;
  - il **punto d'acqua** (`water_point`) sulla riva più vicina: assi di legno posate di traverso sulla riva fino
    all'acqua aperta, secchi accanto, il sentiero che ci arriva dal fuoco (sgombro di alberi, per sempre);
  - il **gonfalone della comunità** su un palo al bordo della piazzola, nel colore del regno: con il fumo dice da
    qualunque altezza dov'è la comunità e che è del giocatore (non scende mai sotto i 30 px: dalla vista di tutta la
    valle si trova a colpo d'occhio insieme alla targa con il nome).
- **Gli abitanti appartengono al luogo** (`SettlementSim`):
  - la partita comincia **alle 8 del mattino** (`time.json → start_hour`), con i sei **seduti attorno al fuoco**;
  - **la sera** (dalle 19 per due ore) chi abita vicino si siede sulle panche o resta in piedi a scaldarsi, poi va a
    dormire. In una comunità piccola tutti hanno un posto sulle panche; in un paese solo una dozzina per sera
    (scelti ogni sera): il fuoco non diventa una folla;
  - **di giorno** chi non ha lavoro si ferma sulla piazzola, e ogni tanto qualcuno va al punto d'acqua, riempie i
    secchi in fondo alle assi e porta l'acqua al fuoco (secchio in mano, nuova posa seduta negli sprite);
  - nessun effetto sull'economia: ore di lavoro, produzione e simulazione aggregata sono identiche (i vent'anni di
    `test_economy` danno gli stessi numeri della Fase 2, con due edifici in più).
- **La crescita si immagina**: dalla piazzola partono i **primi sentieri** dei fondatori — verso il margine del bosco e
  verso la terra aperta dei campi — che sfumano quando il villaggio (30–90 abitanti) ha le sue vie; case, campi e
  taglialegna crescono attorno al nucleo e la piazzola resta vuota (schermate `p3_village`, `p3_community`).
- **Il focolare nel pannello**: selezionandolo si legge chi lo accese (i fondatori) e quanti ci sono attorno.
- **Resa**: la piazzola e la terra battuta attorno agli edifici sono ora macchie morbide (timbri di una texture
  sfumata) invece di poligoni piatti sovrapposti; il fumo è un pennacchio morbido. Gli sprite del deposito e del
  riparo non hanno più un loro fuoco (il fuoco è uno solo). La prima inquadratura è più vicina (0,22 m/px invece di
  0,35).
- **Salvataggi v8** (`SaveMigrator._v7_to_v8`): una comunità fondata prima del nucleo riceve il suo focolare su
  terreno libero davanti al deposito (il centro dell'insediamento si sposta lì) e il punto d'acqua sulla riva più
  vicina; nient'altro si muove; una seconda apertura non aggiunge nulla.
- **Atlanti**: `building_atlas`, `props_atlas` e `people_atlas` sono stati ridisegnati (focolare, panche, pontile,
  secchi, posa seduta, secchio in mano) e ora sono nel repository insieme al loro JSON: una copia con il PNG vecchio
  e il JSON nuovo disegnerebbe i pezzi sbagliati.

**Prove**
- Nuovo `tests/unit/test_nucleus.gd` (7 prove): la comunità nasce attorno al suo fuoco (focolare al centro, deposito
  e riparo fuori dalla piazzola e dal lato opposto all'acqua, punto d'acqua sulla riva entro 200 m, sentiero
  sgombro, i sei al fuoco ciascuno al suo posto, la cronaca racconta il fuoco); la piazzola resta libera (anche dopo
  sei mesi di villaggio costruito dal signore prudente); la sera i sei sono seduti al fuoco e di giorno qualcuno va a
  prendere l'acqua e la porta al fuoco; un paese non affolla il fuoco; il nucleo viaggia con il salvataggio; una
  comunità di un salvataggio v7 riceve il suo fuoco; anche la valle ritagliata dal continente ha il suo nucleo.
- **Esito** (suite completa sullo snapshot della Fase 3, 29 min): 230 prove, 10 308 asserzioni, **1 fallimento**, 2
  saltate (i salvataggi della Fase 18 assenti, vedi Fase 2). Il fallimento era vero:
  `test_river::test_the_village_keeps_its_feet_dry` vuole ogni edificio fuori dalla riva, e il punto d'acqua sta
  sulla riva per costruzione. La prova ora gli chiede la cosa giusta (i piedi sulla terra, `river_clearance ≥ 0` al
  centro) e resta severa per tutti gli altri edifici. Dopo lo snapshot sono stati corretti anche il pontile (di
  traverso alla riva fino all'acqua aperta, oltre la fascia di fango disegnata dal fiume) e il posto di chi attinge;
  riverificati `test_nucleus`, `test_domain`, `test_ui`, `test_river`: 0 fallimenti.
- I vent'anni del villaggio di `test_economy` danno esattamente i numeri della Fase 2 (33 abitanti, 17 nati, 4 morti,
  fiducia 77, tesoro 8 181), con due edifici in più (il focolare e il punto d'acqua): il nucleo non tocca l'economia.

**Schermate** (`docs/rebirth/phase3/`): `p3_start` (il primo istante, 0,22 m/px: i sei seduti attorno al fuoco, il
fumo, il gonfalone, i sentieri), `p3_evening` (le 20, 0,07 m/px: tutti sulle panche), `p3_water` (il punto d'acqua a
metà mattina: qualcuno riempie i secchi), `p3_medium` (1,1 m/px), `p3_far` (tutta la valle: il gonfalone e il nome),
`p3_village` (un villaggio di pochi mesi attorno alla piazzola), `p3_community` (cinque anni dopo, 38 abitanti).

**Limiti dichiarati**
- La resa resta quella degli sprite numpy attuali (Fase 12): da vicino il focolare è leggibile ma piccolo (è un fuoco
  vero di 2 m); le assi del pontile si allargano quando la riva è larga (lo sprite è stirato, non ripetuto).
- La notte non è disegnata: gli abitanti dormono al riparo (non si vedono), il fuoco e il fumo restano.
- Il fumo va sempre nella stessa direzione (non c'è ancora un vento del mondo).
- Il punto d'acqua è vita e paesaggio, non un servizio: il pozzo resta la cosa da costruire per l'acqua vicina alle
  case (guida, «Acqua vicina»).
- La serata al fuoco si vede solo con la valle sotto gli occhi (simulazione per abitante); quando si guarda la mappa
  del mondo i giorni si risolvono in forma chiusa, come prima.
- La migrazione v7→v8 è provata su un salvataggio v7 sintetico: i salvataggi reali delle versioni vecchie non sono nel
  pacchetto (vedi Fase 2).

---

## FASE 4 — Nuova logica di crescita urbana ✅

**Obiettivo**: eliminare la sensazione «Minecraft su un mondo piatto»: gli edifici non devono sembrare oggetti sparsi a
caso. Il giocatore decide **cosa** costruire e **l'area generale**; il gioco rifinisce posizione precisa, piccolo
spostamento, accesso, cortile, sentiero. Gerarchia: NUCLEO → ABITAZIONI → ATTIVITÀ → AREE AGRICOLE → PERIFERIA →
NATURA.

**Prima** (`docs/rebirth/phase3/p3_community.jpg`): il signore prudente e il giocatore mettevano ogni edificio nel
primo punto libero di anelli concentrici attorno a un centro; le case a distanze casuali, i campi a scacchiera
rigida o sparsi, nessun rapporto tra una porta e un sentiero.

**Fatto**
- **`settlement/siting.gd` (classe `Siting`)**: sceglie, attorno al punto indicato, il posto che un abitante avrebbe
  scelto. Ogni edificio ha un **ruolo** (casa, bottega, magazzino, servizio, campo, bosco, cava, miniera, militare) e
  il suo **anello** attorno al focolare, che si allarga con la popolazione (case: fino a 26 m + 3,2·√abitanti;
  botteghe e magazzini più in là; campi oltre le case; bosco, pietra e ferro dove sono). Il punteggio guarda:
  - la **distanza dal punto scelto dal giocatore** (0,12 per metro: l'area resta sua; raggio 14–40 m secondo il
    ruolo);
  - la **porta su una via**: strade, il sentiero dell'acqua, i primi sentieri dei fondatori, i sentieri battuti tra
    le porte; mai una via sotto il tetto;
  - i **vicini**: né addosso (almeno 1,5 m) né sparsi (bonus fino a 8 m), la **stessa linea di facciata** del vicino;
  - i **campi**: terra fertile, **uno accanto all'altro** (patchwork), lontani dalle porte, fuori dal borgo, e un poco
    fuori griglia (una scacchiera perfetta non è un paesaggio);
  - il **taglialegna** al margine del bosco (bosco attorno, cortile sgombro), la **cava** e la **miniera** sulle loro
    rocce, il **pozzo** tra le porte.
  Deterministico: lo stesso punto dà sempre lo stesso posto. Le regole del terreno restano quelle di
  `Placement.check`; il comando resta `PlaceBuildingCommand`.
- **Costruire** (`BuildController`): il fantasma dell'edificio si posa dove lo mette il villaggio; un cerchio
  tenue mostra l'area e una linea il punto scelto. **Alt** mette l'edificio esattamente sotto il puntatore. Il
  suggerimento dice «Il posto lo sceglie il villaggio · Alt: esattamente qui».
- **Il signore prudente e il villaggio di partenza** (`SettlementPlanner.site_for`) usano la stessa scelta: l'area del
  ruolo (`zone_of`), poi `Siting.refine` su tutto l'anello, allargato due volte prima di rinunciare (e solo allora la
  vecchia ricerca ad anelli).
- Accesso, cortile e sentiero vengono dagli strumenti già esistenti, ora con edifici al posto giusto: gli orti dietro
  le case, i sentieri battuti tra le porte (albero minimo), le strade del giocatore.
- **La terra abitata** (`SettlementLayer._draw_lived_ground`): attorno a ogni edificio abitato o di lavoro (non i
  campi) una macchia ampia e tenue di erba consumata; le macchie dei vicini si fondono, così il villaggio sta su una
  terra sua invece che ogni casa sul suo prato.
- **Costo**: una scelta costa 5–18 ms in un villaggio e ~23 ms in una città di 530 edifici (misurato); la rete dei
  sentieri tra le porte (300 ms a quella scala) ora è calcolata una volta per cambiamento e condivisa tra il disegno
  del terreno e la scelta del posto (`SettlementLayer.footpaths` in cache).
- Strumenti per le schermate: `--kd-seed=N` (la stessa campagna ogni volta: prima/dopo sullo stesso villaggio) e
  `--kd-build=casa,dx,dy` (il fantasma di un edificio tenuto sopra un punto).

**Prove**
- Nuovo `tests/unit/test_growth.gd` (4 prove): una casa cliccata nel prato si sposta verso le vie e verso il
  villaggio, resta nell'area, non tocca la piazzola, la scelta è sempre la stessa, la seconda casa si mette accanto
  alla prima; il giocatore tiene la sua area (casa, forno, campo); i campi fanno un patchwork su terra buona, oltre le
  case; **un villaggio di 30–50 abitanti cresciuto dal signore prudente** ha le case vicine (distanza mediana dal
  vicino tra 1,5 e 12 m), le porte sulle vie (almeno il 70%), i campi oltre le case, il taglialegna al margine del
  bosco, la piazzola libera.
- **Esito** (suite completa sullo snapshot della Fase 4, 29 min): 234 prove, 10 377 asserzioni, **1 fallimento**, 2
  saltate (i salvataggi della Fase 18). Il fallimento era vero e non l'ho nascosto:
  `test_stress::test_sixty_years_of_the_whole_world_and_a_village_that_grows` ha superato il suo limite di 400 s
  (420 s nella suite, **405 s da solo**; il progetto originale in questo ambiente impiega 358 s). Profilato (20 anni,
  stesso carico, fianco a fianco): 54,2 s l'originale, 60,8 s la Fase 4 — ma il villaggio della prova nella valle
  fertile cresce di più (163 abitanti e 128 edifici contro 125 e 104 a vent'anni; 336 contro 301 a sessanta), e il
  lavoro del giorno cresce con la gente; la scelta del posto aggiunge ~1,6 s in vent'anni. Corretto senza toccare la
  soglia né un risultato:
  - `Siting`: gli edifici e le vie vicini indicizzati su una griglia di 20 m (ogni candidato guarda solo ciò che ha
    attorno);
  - `SettlementLayer._crosses_river`: un segmento non può toccare un fiume più lontano della sua lunghezza (la rete
    dei sentieri: 47 → 14 ms a 143 edifici);
  - `PopulationSystem._deaths/_trust` e `SettlementSim._eat`: le regole lette una volta al giorno invece che per
    persona, il cibo preso dal deposito in una volta sola (contato unità per unità come prima: stesse somme).
  Dopo: **367 s** da solo, con gli **stessi identici esiti** (336 abitanti, 296 edifici, 160 personaggi, 305 righe di
  cronaca: il determinismo è intatto). Riverificate `test_economy`, `test_founders`, `test_settlement`, `test_balance`,
  `test_growth`, `test_nucleus`, `test_identity`, `test_river`, `test_visual`: 69 prove, 0 fallimenti; i vent'anni del
  villaggio di `test_economy` danno gli stessi numeri di prima dell'ottimizzazione.

**Schermate** (`docs/rebirth/phase4/`, stessa campagna `--kd-seed=4104`, stesso momento, stesso punto di vista):
`p4_before_village` (Fase 3: la vecchia ricerca ad anelli «organica») e `p4_after_village` (Fase 4); `p4_after_core`
(il cuore del villaggio da vicino: case con l'orto, porte sui sentieri, pozzo e gonfalone sulla piazzola, campi
oltre); `p4_build_ghost` (il giocatore indica un punto nel prato: il fantasma va 14 m più in là, in fila con la casa
vicina e con la porta sul sentiero; il cerchio è l'area, la linea il posto scelto).

**Confronto onesto con prima**: la ricerca della Fase 3 era già «organica» (anelli ruotati e spostati), quindi la
differenza non è da un caos a un ordine. Il villaggio della Fase 4 è **più raccolto** attorno alla piazzola, con le
case **in fila** lungo le vie e l'orto dietro, i campi **uno accanto all'altro** oltre le case invece che sparsi a
ventaglio, e la terra consumata che lega le case tra loro. È la differenza tra oggetti ben distribuiti e un luogo.

**Limiti dichiarati**
- **Orientamento**: gli sprite degli edifici sono disegnati di fronte (vista 3/4 da sud); un edificio non può
  voltarsi verso una via che corre da nord a sud. Il gioco rifinisce posizione, allineamento e porta, non la
  rotazione: servono gli sprite in più angolazioni della Fase 12.
- Le vie sono sentieri che nascono dalle porte e strade tracciate dal giocatore: non c'è ancora una rete di strade
  pianificata (lotti lungo una strada maestra); arriverà con i quartieri (Fase 5).
- Un edificio indicato in pieno prato, lontano da tutto, resta dove indicato: è la scelta del giocatore, e il
  villaggio ci farà arrivare un sentiero.
- I campi restano rettangoli di 26 × 30 m (con le loro strisce): niente siepi e alberi di confine per ora.
