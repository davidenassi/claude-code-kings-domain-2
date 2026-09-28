# KING'S DOMAIN — CONSOLIDAMENTO DEI SISTEMI: RAPPORTO

Il brief chiedeva una **compressione**, non una semplificazione: meno statistiche che raccontano la stessa cosa,
meno menu allo stesso livello, meno micro-modificatori, stessa profondità. L'analisi di partenza, con le misure,
è in `SYSTEM_CONSOLIDATION_AUDIT.md`. Nessuna meccanica importante è stata tolta: dove due cose si potevano unire
si sono unite (MERGE), e i salvataggi vecchi si aprono tutti (migrazione v5 → v6).

---

## 1. Indicatori — un nome per ogni misura

| Prima | Dopo | Come |
|---|---|---|
| «Ordine» (misura della corona) + chiave «Stabilità» (`stability.base`) che in realtà spostava la fiducia della gente | **STABILITÀ**, un solo indicatore di tenuta interna: ordine pubblico, istituzioni, rischio di crisi | `KingdomState.order` → `stability`; modificatore `order.base` → `stability.base`; il vecchio `stability.base` → `trust.base`; sezione di bilanciamento `order` → `stability` (la vecchia sezione `stability`, soglie delle rivolte, → `revolt`); condizioni ed effetti degli eventi `order`/`max_order` → `stability`/`max_stability`. La «turbolenza» resta un fattore interno della Stabilità, visibile nel suo tooltip. |
| «Fiducia» in cima, «consenso» in Abitanti, Il mio regno, parole degli effetti ed eventi, «malcontento» altrove; nel codice `happiness` | **FIDUCIA**, ovunque | `SettlementState.happiness` → `trust` (`happiness_parts` → `trust_parts`); sezione `happiness` di `population.json` → `trust`; effetti e condizioni degli eventi `happiness`/`min_happiness`/`max_happiness` → `trust`/…; tutti i testi. Non esiste una «felicità» separata: le sue parti (cibo, fame, alloggi, servizi, lutti, corona, assedio, occupazione) sono la spiegazione della Fiducia nel tooltip. |
| Autorità: diventava il 60% della prima Legittimità | Resta **transitoria** | All'incoronazione fonda la prima Legittimità (60%) **e la prima Stabilità** (30%: una comunità che decide insieme nasce più salda). Dopo la corona non compare in nessun pannello. |
| Prestigio, Legittimità | invariati | Già unici e chiari. |

Il tooltip della Stabilità ora dice che cosa misura («la tenuta interna del regno: ordine pubblico, istituzioni che
funzionano, rischio di crisi»), le sue soglie (tasse sotto 30, rivolte sotto 18) e le parti con segno.

## 2. Famiglie → Ceti

**Le famiglie non sono più un sistema né una scheda a parte: vivono dentro i Ceti.**

- **Il ceto di una famiglia si deduce**, non si salva (`FamilySystem.estate_of`, `families_by_estate`): dal lavoro
  che riempie il suo registro — contadini → **Popolo**, mestieri e cantieri → **Mercanti e artigiani** (il ceto dei
  mercanti ha preso gli artigiani: le gilde erano già fra le sue richieste), gente d'arme → **Esercito**, famiglia
  stimata senza mestiere prevalente → Popolo. Dopo la corona: la **Casa reale** sta a sé; la **Nobiltà** è fatta
  delle famiglie più influenti — poche: una casata ogni 40 abitanti, sopra una soglia d'influenza — e di quelle
  **imparentate con la casa reale**. Il Clero per ora non ha famiglie (non c'è un mestiere religioso da cui
  dedurle): la scheda lo dice. Una famiglia di artigiani che prospera, o piena di soldati, cambia ceto da sola.
- **Influenza** (ex «reputazione»): quanto conta una famiglia (fondatrice, anni, membri, figli, lavoro).
- **Scala**: prima della corona la scheda mostra tutte le famiglie (sono poche); dopo, per ogni ceto le 3 più
  influenti e «e altre N». Nella campagna di 150 anni il registro contava 1207 famiglie: l'interfaccia non esplode.
- **La scheda Ceti**:
  - prima della corona: «LA COMUNITÀ» (abitanti, famiglie, radicate, gruppi di lavoro), poi le famiglie per gruppo
    (gente dei campi, botteghe e mestieri, gente d'arme) con albero, influenza, storia, cosa porterebbero come casa
    reale e **la scelta della casa reale**;
  - dopo: «I POTERI DEL REGNO» (favore, richieste, umore, rivali, dono della corona, **famiglie di spicco** di ogni
    ceto), la Casa reale sopra di loro con le famiglie imparentate, «LE FAMIGLIE DI SPICCO» (le schede: ceto,
    influenza, membri, storia, rapporto con la corona, richieste del ceto), «EFFETTO SULLA CORONA».
- **Menu di sinistra**: il tasto «Famiglie» non c'è più. Prima della corona: La mia comunità, Consuetudini,
  Costruzioni; con la corona compare **Corte**.
- **La mia comunità / Il mio regno**: prima della corona «VERSO LA CORONA» con le condizioni del Regno (erano nella
  scheda Famiglie) e il rimando ai Ceti per la scelta; dopo, «LA CASA REALE» (chi regna e da quando, l'erede, la
  famiglia d'origine, le famiglie imparentate). «Abitanti e famiglie» è diventato «Abitanti».
- **Corte**: solo le persone attorno al sovrano (il sovrano, la legittimità della casata, gli eredi). Via il
  riassunto dei poteri (doppione dei Ceti) e i misuratori di Stabilità e Prestigio (sono in cima allo schermo).
- **Religione**: la fede, il peso del clero sulla legittimità, la legge di fede, le fedi delle terre. Via il secondo
  misuratore del favore del clero e il secondo pulsante del dono: il clero è un ceto, sta nei Ceti.
- **Guida**: i tre passi che rimandavano alla scheda FAMIGLIE ora rimandano a CETI e LA MIA COMUNITÀ.

La famiglia reale è ora salvata (`KingdomState.royal_family`); nei salvataggi vecchi viene ritrovata dalla persona
che porta la corona o dal nome della casa (`CourtSystem.royal_family_of`).

## 3. Spiriti nazionali

- Al massimo **4** spiriti insieme (erano 6), **3** dalla terra all'inizio (erano 4). Origine (geografia, storia,
  decisioni) ed evoluzione invariate: cultura e religione restano fisse, gli spiriti dinamici.
- Nei salvataggi con più di 4 spiriti, una volta l'anno lascia il posto il più antico fra quelli conquistati (un'impresa
  sbiadisce nella storia prima della terra), con avviso e riga di cronaca, finché si torna a 4.
- Effetti percepibili: Montanari del ferro perdono il +3% di difesa (il ferro sale a +15%); Regno delle battaglie
  legittimità +2 → +4; Corona delle leggi controllo +0,03 → +0,06; Mosaico di popoli −0,04 → −0,06; Un'antica casata
  perde il +2 di fiducia.

## 4. Modificatori

Da **184 modificatori (16 minuscoli)** a **178, nessuno minuscolo** (sotto il 5% o i 3 punti). Oltre agli spiriti:
tratti del sovrano (Saggio: solo ricerca +12%; Diplomatico commercio +4% → +8%; Ambizioso legittimità +4 e fiducia −3;
Prudente stabilità +4; Sospettoso stabilità +5, legittimità −3), origini della casa reale (contadini: grano +8%;
artigiani: cantieri +8%), leggi (anzianità legittimità +3; strade maestre senza il −2 di fiducia, che già pagano col
favore del popolo). «La formula del regno» (22 voci con le fonti) è chiusa e si apre a richiesta: è il livello 3.

## 5. Cronaca

La cronaca registra la storia, non il traffico: **tutto** ciò che fa il regno del giocatore e tutto ciò che gli
altri gli fanno (le voci con due regni ora hanno anche l'«altro»: l'esercito nemico che assedia le nostre terre
entra, col suo nome); degli altri regni solo ciò che cambia il mondo — guerre, paci, conquiste, rivolte, morti e
successioni dei re, fondazioni. Marce, patti, assedi, occupazioni e rivendicazioni fra altri regni non entrano più.
Il filtro «solo le mie» della scheda Cronaca conta anche le voci in cui il giocatore è l'«altro».

Anche per il giocatore si tengono i fatti, non le routine: dei patti entrano i trattati che legano (alleanza,
vassallaggio, tributo), non i rinnovi quinquennali di non aggressione e commercio (restano nella Diplomazia); degli
eventi entrano le crisi e ciò che tocca la dinastia, il sovrano e il regno in crisi, non le fortune ordinarie di un
anno (raccolto, fiera, lupi); un evento che scrive già una sua riga d'autore non viene raddoppiato.

Misura, stessa campagna di 40 anni giocata dal pilota (seme 1905):

| | Righe | Del giocatore o che lo toccano | Composizione |
|---|---|---|---|
| Prima (due salvataggi di 40 anni) | 600 (al tetto) | 47 e 29 | marce 129–154, patti 69–119, assedi 116–129, occupazioni 86–88, rivendicazioni 22–41 |
| Dopo il primo filtro | 426 | 344 | patti 158, eventi 127 (rinnovi e fortune del giocatore) |
| Dopo | **178** | **96** | eventi 23, successioni e morti di re 40, inizi di regno 16, rivendicazioni 14, patti 14, paci 9, crisi 7, rivolte 6, guerre 5, conquiste 4, fondazione 16 |

In 40 anni la cronaca non arriva più al tetto: la storia intera ci sta, dalla fondazione in poi. La simulazione è
identica con e senza filtro (266 abitanti, stessi spiriti, stesse famiglie).

## 6. Mappa, economia, ricerca, eventi

- **Modalità mappa**: Politica, Terreno, Risorse, Popolazione nel menu; Culture, Religioni, Sviluppo, Diplomazia
  sotto «Altre mappe». Tasti F e M invariati.
- **Economia**: in cima «COSA MANCA» — cibo per pochi giorni (con «serve un forno» se il grano c'è ma non diventa
  pane), granai o magazzini pieni, nessun letto libero, braccia senza lavoro, mese in perdita, debito — ognuno con
  cosa fare, solo con dati già misurati. Il lavoro in una riga (il dettaglio per famiglie nei Ceti), i prezzi chiusi.
- **Ricerca**: invariata (8 tecnologie con effetti dall'8% al 60%); le «crisi in corso» sono passate in Il mio regno.
- **Eventi**: «Due famiglie in lite» ora è un dilemma vero (autorità +6 e fiducia −4, oppure fiducia +5 e autorità −5);
  rifiutare i coloni costa fiducia e favore del clero; rifiutare il ponte del re costa legittimità; frenare il
  banchetto costa alla nobiltà ma dà legittimità.

## 7. Individui e scala

Nessun cambiamento necessario: gli individui esistono solo negli insediamenti del giocatore (da 6 a ~600 abitanti in
150 anni, 1000–2000 misurati nella Fase 19); le province, anche conquistate, hanno popolazione aggregata; le corti
sono personaggi limitati (~150–175). Quello che esplodeva era l'elenco delle famiglie nell'interfaccia: vedi sezione 2.

## 8. Salvataggi

Versione **6**. `SaveMigrator._v5_to_v6`: `order` → `stability` in ogni regno, `happiness` → `trust` in ogni
insediamento, chiavi dei modificatori nelle crisi salvate (`stability.base` → `trust.base`, `order.base` →
`stability.base`). Le famiglie non cambiano formato (il ceto si deduce): nomi, membri, storia, dinastia e legami
restano. Verificato con i due salvataggi della Fase 18 (fixture): i valori di «order» e «happiness» si ritrovano
identici come Stabilità e Fiducia; e con un salvataggio v5 costruito apposta con una crisi.

## 9. File

Codice: `core/session/game_session.gd`, `kingdoms/{kingdom_state,objectives}.gd`,
`kingdoms/systems/{court_system,national_spirit_system}.gd`, `settlement/{settlement_state}.gd`,
`settlement/systems/{family_system,population_system}.gd`, `events/events.gd`, `economy/systems/economy_system.gd`,
`ai/realm_ai_system.gd`, `diplomacy/commands/{make_peace,propose_pact,break_pact,arrange_marriage}_command.gd`,
`military/commands/move_army_command.gd`, `war/war.gd`, `war/systems/war_system.gd`, `world/world_state.gd`,
`save/save_migrator.gd`. Interfaccia: `ui/kingdom/{estates,court,realm,religion,knowledge}_panel.gd`,
`ui/economy/economy_panel.gd`, `ui/map/map_mode_menu.gd`, `ui/chronicle/chronicle_panel.gd`,
`ui/events/event_card.gd`, `ui/settlement/{settlement_hud,people_panel}.gd`, `ui/shell/{nav_block,panel_host,top_bar}.gd`.
Dati: `data/defs/{events,factions,guide,house_origins,laws,map_modes,national_spirits,religions,technologies,traits}.json`,
`data/defs/balance/{crown,families,modifier_keys,population,war}.json`. Test: `tests/unit/{test_save,test_founders,
test_politics,test_ui,test_content,test_economy,test_events,test_war}.gd`, `tests/campaign/{campaign_pilot,campaign_runner}.gd`.

## 10. Test

Suite completa: **210 test, 10 083 asserzioni, 0 fallimenti** (erano 206: +4 nuovi, più quelli aggiornati).
`test_stress` (60 anni del mondo intero) 239 s su 400, con una cronaca di 289 righe.

| Richiesta del brief | Verificato da |
|---|---|
| Nuova partita: 6 fondatori, prime famiglie, Ceti | `test_founders` (fondatori; schede della comunità: le famiglie nei Ceti, nessuna misura della corona, condizioni in La mia comunità, Corte che dice di non esserci), schermata della scheda Ceti prima della corona |
| Fondazione della monarchia: casa reale, legittimità, corte | `test_founders` (la casa reale a sé, Corte con sovrano e legittimità, Ceti con i poteri e la casa reale sopra, Il mio regno con la casa reale), `test_politics` |
| Regno medio: più ceti, famiglie influenti | `test_founders::test_the_families_live_inside_the_estates` (ceto per lavoro, nobiltà per influenza e per nozze con la corona, famiglia reale ritrovata dopo un caricamento), schermata sulla cittadina di 40 anni (8 casate nobili per 287 abitanti) |
| Grande regno: niente sovraccarico | `test_founders::test_many_families_do_not_flood_the_estates_sheet` (60 famiglie in più: al massimo 3 schede per ceto, «e altre N») |
| Salvataggi | `test_save` (fixture della Fase 18 con «order»/«happiness» ritrovati come Stabilità/Fiducia; crisi con chiavi vecchie), tutti i test di andata e ritorno |
| Eventi | `test_content` (chiavi di effetti e condizioni rinominate), `test_events` (un regno dell'IA decide da solo e non scrive nella nostra cronaca; la crisi decisa dalla corte sì) |
| Cronaca | `test_politics::test_the_chronicle_keeps_the_history_not_the_traffic`, misura di 40 anni (sezione 5) |
| Interfaccia | `test_ui` (menu delle mappe, crisi in Il mio regno, Corte senza i poteri, Religione senza il doppio misuratore, schede che stanno nello schermo) |
| IA | `test_diplomacy`, `test_politics`, `test_war` e le campagne di `test_events` |

