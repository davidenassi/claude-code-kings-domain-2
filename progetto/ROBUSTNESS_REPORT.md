# FASE 19 — PRESTAZIONI, BUG E ROBUSTEZZA

Obiettivo del brief: trasformare la build rifinita in una build robusta. Qui: gli stress test (19.1), le misure
(19.2), i bug classificati con quello che è stato corretto (19.3), la verifica dei salvataggi (19.4).
Regola seguita: niente ottimizzazioni «a sensazione» — prima si misura, poi si cambia, poi si rimisura, e si
controlla che il risultato della simulazione non cambi (dove non deve cambiare).

Strumenti nuovi di questa fase (tutti in `tests/`, nessuno fa parte del gioco):
- `tests/stress/stress_runner.tscn` — stress test misurati, headless: `-- --kd-stress=city,sites,war,pacts,long
  [--kd-people=1000,2000] [--kd-years=150]`. Rapporto in `tests/output/stress/stress_report.md`.
- `tests/stress/stress_worlds.gd` (`StressWorlds`) — costruisce i mondi di stress solo con le funzioni del gioco
  (il planner trova i posti, `PopulationSystem.welcome` accoglie, `Military` arruola, `DeclareWarCommand` dichiara,
  `Diplomacy.sign` firma dove `pact_blocker` lo permette). Gli stessi mondi si guardano col renderer:
  `--kd-scenario=stress_city [--kd-people=N]`, `--kd-scenario=stress_war`.
- `tests/tools/quickload_check.tscn` — F5/F9 giocati sulla vera scena di gioco.
- `--kd-benchmark` ora dice anche nodi, nodi orfani e dove capita il massimo delle draw call.
- `tests/test_runner.gd`: `--kd-test=a,b,c` (più file nello stesso processo, nell'ordine della suite).
- `tools/check.ps1`: ogni riga `ERROR:` del motore fa fallire il controllo, salvo gli errori provocati apposta dai
  test (elencati uno per uno).

---

## 19.3 — Bug

Gravità: **BLOCKER** (il gioco non parte o si perde la partita) · **CRITICAL** (dati sbagliati o persi,
simulazione che diverge) · **MAJOR** (un sistema funziona male in modo evidente) · **MINOR** (fastidio, caso
raro) · **COSMETIC** (solo aspetto). Nessun BLOCKER trovato.

| # | Gravità | Dove | Difetto | Stato |
|---|---|---|---|---|
| B5 | CRITICAL | simulazione | Cache statiche di strade e depositi restituivano i dati del mondo precedente dopo un caricamento o una nuova partita nello stesso avvio. | Corretto (commit del world art pass, c9453b2); chiave = mondo + versione. |
| B11 | MAJOR | salvataggi | Il salvataggio scriveva sopra il file vecchio: un gioco chiuso a metà scrittura, o un disco pieno, lasciava lo slot rotto e senza la copia precedente (salvataggio rapido e salvataggi a mano non hanno copie). | Corretto: si scrive `<slot>.kds.tmp` e si rinomina solo a file intero. Test `test_save::test_a_broken_save_is_refused_and_the_old_one_survives`. |
| B12 | MAJOR | guerra/diplomazia | L'IA vincente chiedeva nella pace tutte le province occupate, **compresa quella del villaggio del giocatore**; accettando, il villaggio passava all'IA e il giocatore restava senza nulla da governare, senza avviso e senza fine partita. | Corretto: la sede della corona del giocatore può essere assediata e occupata ma nessun trattato la cede (l'IA non la chiede, `MakePeaceCommand` la rifiuta, le offerte vecchie nei salvataggi la saltano); l'offerta di pace ora nomina le province richieste. Test `test_war::test_no_treaty_gives_away_the_seat_of_the_player`. |
| B13 | MAJOR | guerra | Un regno che perdeva l'ultima provincia lasciava in campo i suoi eserciti (che marciavano, assediavano e combattevano per una corona inesistente) e le sue guerre aperte. Trovato dal controllo di coerenza dello stress di guerra. | Corretto: le schiere si sciolgono nei campi della provincia in cui si trovano, le guerre si chiudono e ciò che era occupato torna ai proprietari. Test `test_war::test_the_hosts_of_a_fallen_realm_scatter_and_its_wars_end`. |
| B1 | MAJOR | salvataggi | F9 (caricamento rapido) metteva il mondo caricato sotto la mappa, l'HUD, le notizie e la minimappa della partita precedente. | Corretto: come il menu di pausa, la scena si ricostruisce; l'avviso «Partita caricata» attraversa la ricostruzione. Verificato con `quickload_check.tscn`. |
| B2 | MAJOR | economia/notizie | «Depositi pieni» ripetuto ogni giorno nella simulazione ora per ora, mai in quella per aggregato. | Corretto: una volta al mese per insediamento, da entrambe. Test `test_settlement::test_full_stores_are_told_once_a_month_not_every_day`. |
| B14 | MAJOR | prestazioni | La capienza dei depositi si ricalcolava scorrendo tutti gli edifici a ogni unità prodotta e a ogni scelta di lavoro: in una città di 350 edifici un terzo della giornata. | Corretto: cache per mondo + versione degli edifici. Città da 1000: giorno per aggregato 108 → 28 ms, giorno osservato 2024 → 747 ms. |
| B15 | MAJOR | simulazione | Il caso della simulazione ora per ora vale per un quarto d'ora: finita una passeggiata di pochi secondi, l'ozioso ripescava la stessa decisione e la stessa meta, fino a 10 volte per ora (camminava sul posto). 25 000 scelte al giorno in una città da 1000. | Corretto: finita la passeggiata, si ferma lì per 1,5–4 ore come previsto. Scelte degli oziosi 25 014 → 8 487 al giorno; giorno osservato 747 → 325 ms. |
| B16 | MAJOR | prestazioni | A ogni albero ricresciuto si buttavano le liste di alberi di **tutti** i boscaioli: in una città che ha tagliato i suoi boschi succede quasi ogni giorno (1340 liste ricostruite in un trimestre, 139 ms al giorno). | Corretto: l'albero torna solo nelle liste che lo raggiungono, al suo posto per distanza. Anno dopo della città da 1000: giorno medio 84,6 → 36,9 ms, picco 292 → 120 ms — stessi abitanti e stessi edifici. |
| B7 | MINOR | prestazioni | Avvicinando la telecamera a una città molto grande tutti gli abitanti ripianificavano nello stesso tick e tutti i boscaioli rifacevano insieme le loro liste di alberi (fotogramma da 110–135 ms a 1500 abitanti, alla soglia di osservazione di 22 m/px). Misurato: 750 scelte che di solito costano 5–7 ms, più 30 liste di alberi da 3,4 ms. | Corretto: il risveglio si distribuisce sulle prime 4 ore (anche quando la telecamera se ne va e torna nello stesso giorno), al primo tick osservato; al massimo 6 liste di alberi per ora. Picco 125,7 → 56,2 ms (il resto è il primo disegno di mille edifici entrando nella fascia ravvicinata, una volta sola). |
| B24 | MINOR | simulazione | Al risveglio degli abitanti le azioni in corso si annullavano ma gli alberi e le rocce che avevano prenotato restavano prenotati per sempre (nessuno li tagliava più ora per ora). | Corretto: al risveglio le prenotazioni si liberano. |
| B17 | MINOR | prestazioni | `_free_home` contava gli abitanti di ogni casa scorrendo tutti gli abitanti: l'arrivo di 25 persone in una città da 1000 costava 845 ms. | Corretto (conteggio unico): 110 ms. |
| B18 | MINOR | prestazioni | `assign_jobs` chiedeva a un array se conteneva qualcuno dentro un ciclo su tutti (5 ms al giorno a 1000 abitanti). | Corretto (insieme per id). |
| B19 | MINOR | salvataggi | Ogni salvataggio automatico apriva e analizzava tutti i salvataggi sullo scaffale per la rotazione (470 ms in una città da 2000). | Corretto: la rotazione legge solo i nomi; il menu tiene in cache le intestazioni per data di modifica (invalidate a ogni scrittura). 271 → 67 ms a 1000 abitanti. |
| B20 | MINOR | prestazioni | Gli abitanti: un'ombra con `draw_set_transform` + cerchio per persona (batch spezzati, ~3000 draw call) e nomi degli sprite formattati a ogni frame: 4,3–5,1 ms per frame con 1500 abitanti. | Corretto: ordinamento nativo, nomi e regioni precalcolati, ombre e puntini da una sola texture. 1,4–1,8 ms; città di stress 90,6 → 124,5 fps (da vicino 79 → 136). |
| B3 | MINOR | salvataggi | L'autosalvataggio aspettava il giorno esatto divisibile per 360: ad alta velocità poteva saltare un anno. | Corretto: al cambio d'anno. Test `test_menu::test_the_automatic_save_comes_every_year_even_when_the_day_is_skipped`. |
| B21 | MINOR | simulazione | Due statiche «di riserva» (`PopulationSystem._fallback_session`, `SettlementSim._current_world`) potevano prestare a una sessione i modificatori o le strade di un'altra, e tenevano in memoria la partita precedente. | Corretto: la sessione e il mondo si passano esplicitamente. |
| B4 | MINOR | strumenti | Screenshot e benchmark scrivevano autosalvataggi nella cartella del giocatore. | Corretto (+ `--kd-no-autosave`). Restano nell'elenco del menu 3 «Salvataggio automatico» di mondi di prova, creati dai miei benchmark: si possono cancellare dal menu. |
| B8 | MINOR | strumenti | `check.ps1` passava con righe `ERROR:` del motore prive di `res://` (es. «Invalid polygon data»). | Corretto. |
| B9 | COSMETIC | prestazioni | `MoveArmyCommand` cercava due volte lo stesso percorso (5–12 ms ciascuno). | Corretto. |
| B22 | COSMETIC | strumenti | Nel benchmark una stringa conteneva un a capo letterale (residuo di un vecchio script). | Corretto; nessun altro caso nel progetto (verificato con uno scanner). |
| B23 | — (non è un bug) | simulazione | Sospetto di inizio fase: `test_stress` nella suite finiva con un villaggio diverso (336 abitanti) e tre volte più lento che da solo (258). | **Verificato che non esiste**: con lo stesso codice, da solo e in suite danno lo stesso mondo (336 abitanti, 297 edifici, 148 personaggi, 600 righe; 207 s e 208 s). I «258» venivano da una versione precedente del codice (il planner del world art pass fa crescere il villaggio in un altro modo). Controprove: la stessa campagna, confrontata mese per mese per 3 anni, è identica eseguita da sola, dopo ogni metà della suite, dopo `test_events` e dopo l'intera suite; e identica fra codice di inizio fase e codice ottimizzato. |

Non sono bug del gioco, ma artefatti dei mondi di stress (annotati per chi li rilegge): una città costruita in un
giorno con 1000 celibi produce 471 notifiche di nozze nel primo anno; al giorno 0 la carta d'inizio elenca tutti
gli abitanti (nel gioco al giorno 0 sono sei); senza cibo di scorta la città di stress moriva di fame in un mese
(ora lo strumento le dà un anno di pane).

---

## 19.1 — Stress test

Tutti misurati su questa macchina, un processo alla volta. «Prima» = codice all'inizio della fase, «dopo» =
codice finale. Headless (`stress_runner`), quindi solo simulazione; il renderer è nella sezione 19.2.

**Grandi popolazioni e città grandi** — la città del giocatore portata a 1000 e 2000 abitanti in un momento
(349 e 698 edifici messi dal planner, un anno di pane di scorta).

| Città da 1000 | Prima | Dopo |
|---|---|---|
| Giorno per aggregato (città non guardata), media / peggiore | 93,8 / 339 ms | 43,2 / 224 ms |
| Stesso, un anno dopo (834 abitanti), media / peggiore | 84,6 / 292 ms | 36,9 / 120 ms |
| Giorno ora per ora (città guardata) | 1798 ms (74,9 ms per ora di gioco) | 233 ms (9,7 ms per ora) |
| Arrivo di 25 persone | 845 ms | 101–110 ms |
| Salvataggio automatico con rotazione | 149–271 ms | 64 ms |

Città da 2000 (dopo): giorno per aggregato 95,6 ms di media, giorno ora per ora 456 ms (19 ms per ora di
gioco), un anno dopo 1819 abitanti e 155 ms al giorno; salvataggio 1,2 MB di JSON, 210 KB compressi, scritto in
116 ms e riletto in 153 ms. Tutti i controlli di coerenza passati (province, eserciti, signori senza cicli, patti e
guerre, scorte non negative, ogni abitante in un insediamento).

Che cosa vuol dire in partita: alla velocità «Lenta» (4 s per giorno, 6 ore di gioco al secondo) una città da mille
guardata da vicino costava 450 ms di simulazione per ogni secondo reale (il gioco non teneva il passo); ora 58 ms.

**Molte costruzioni** — 120 cantieri aperti insieme in una città da 600: aperti in 8,2 s di planner, 20 giorni per
aggregato a 41 ms di media, tutti finiti in 22 giorni, coerenza passata.

**Molti eserciti, molte guerre** — ogni regno arruola 6 reggimenti (63 eserciti) e dichiara guerra, con il comando
del gioco, ai due regni più vicini (19 guerre, 2 contro il giocatore): un anno di guerra a 5,8 ms al giorno di
media (peggiore 57,5), 65 battaglie, 86 province passate di mano, 17 regni ancora vivi. Il percorso di un esercito
(Dijkstra su 395 province) costa 2–5 ms, 12 al peggio. **Qui è emerso B13** (eserciti di regni caduti).

**Diplomazia complessa** — tutti i patti che le regole permettono fra tutti i regni (84 non aggressione, 56
commercio, 59 alleanze, 16 tributi, 1 vassallaggio), poi due anni: 2,7 ms al giorno, nessun ciclo di signori,
nessuna guerra con un patto che la vieta, coerenza passata.

**Campagne lunghe** — 150 anni giocati dal pilota automatico (seme 1905), un decennio alla volta:

| Anno | Decennio | Villaggio | Personaggi | Famiglie | Cronaca | Eserciti | Memoria |
|---|---|---|---|---|---|---|---|
| 10 | 22,8 s | 73 ab., 60 edifici | 95 | 72 | 600 | 1 | 100 MB |
| 50 | 122,8 s | 314 ab., 250 edifici | 167 | 391 | 600 | 43 | 102 MB |
| 100 | 192,7 s | 457 ab., 428 edifici | 156 | 807 | 600 | 37 | 104 MB |
| 150 | 115,9 s | 571 ab., 562 edifici | 171 | 1207 | 600 | 52 | 105 MB |

La memoria resta piatta (98 → 105 MB), i personaggi delle corti restano limitati, la cronaca resta al suo tetto di
600 righe; il salvataggio del centocinquantesimo anno è di 817 KB di JSON (151 KB compressi) e torna in 46 ms.
Crescono solo le famiglie (anche quelle estinte restano nel registro, una decina l'anno): nessun costo visibile,
annotato. Il costo di un decennio segue la taglia del villaggio (dentro c'è anche il pilota, che a ogni mese
cerca posti per costruire: `find_spot` costa ~80 ms in un borgo di 700 edifici — è uno strumento, non il gioco).

---

## 19.2 — Misure

**Renderer** (`--kd-benchmark=40 --kd-bench-home`: 40 s di volo a spirale sopra la casa, da 40 a 0,2 m/px; 1080p,
questa macchina). «Inizio» = inizio della fase, stesso volo.

| Mondo | FPS medi | Da vicino (<1 m/px) | 1–5 m/px | Fotogramma peggiore | Draw call media / max | Nodi | Memoria statica / video |
|---|---|---|---|---|---|---|---|
| Cittadina di 40 anni (`d_town`, 287 ab.), inizio | 135,7 | 143,2 | 115,1 | 43,5 ms | 1238 / 2187 | 771 | 174 / 205 MB |
| Cittadina di 40 anni, fine | 139,6 | 143,5 | 131,3 | 34,7 ms | 1084 / 1616 | 771 | 172 / 208 MB |
| Città di stress (1500 ab., 520 edifici), inizio | 90,6–94,9 | 79,0–90,7 | 69,4–90,8 | 121–134 ms | 3639 / 8912 | 750 | 212 / 222 MB |
| Città di stress, fine | 128,7 | 138,4 | 113,5 | 56,2 ms | 3695 / 5917 | 753 | 202 / 221 MB |
| Continente (`d_town`, volo attraverso il continente), fine | 142,5 | 143,6 | 141,1 | 21,3 ms | 214 / 1338 | 756 | 171 / 214 MB |

Nessun nodo orfano in nessuna prova; il numero di nodi non cresce con la taglia della città (tutto è disegnato,
non istanziato). Il costo del livello degli abitanti, misurato dentro `_draw`: 4,3–5,1 → 1,4–1,8 ms per frame con
1500 abitanti.

**Simulazione** (profilo del gestore dei sistemi e strumentazione temporanea per voce, città da 1000):

| Voce | Prima | Dopo |
|---|---|---|
| Giorno per aggregato | 108 ms (taglio alberi 77, forni 19) | 28 ms nei primi giorni, 37 ms di media in un anno |
| Scelte dei boscaioli | 0,77 ms l'una | 0,03 ms |
| Scelte dei contadini | 0,46 ms l'una | 0,03 ms |
| Scelte degli oziosi al giorno | 25 014 | 8 487 |
| Giorno osservato | 2024 ms | 233 ms |
| `assign_jobs` | 5 ms al giorno | < 1 ms |

**Percorsi**: `Military.route` (Dijkstra con scansione lineare, 395 province) 2–5 ms di media, 12 ms al peggio;
`MoveArmyCommand` non lo calcola più due volte. Non serve un heap: il costo resta sotto un millisecondo per esercito
per giorno anche con 63 eserciti.

**IA**: `realm_ai` 20–25 ms per mese con 17–20 regni (una volta al mese); `war` 2,7 ms al giorno con 19 guerre
aperte; `diplomacy` 0,2–0,3 ms al giorno.

**Salvataggi**: città da 2000 → 1,2 MB di JSON, 210 KB compressi, scrittura 116 ms, lettura 153 ms; campagna di
150 anni → 151 KB, scrittura 47 ms, lettura 56 ms; l'intestazione per il menu costa 11–71 ms la prima volta e poi
niente (cache). Un salvataggio automatico con la rotazione: 21–67 ms (prima 84–470 ms).

**La suite di test** — effetto collaterale delle correzioni: da 46 a 16 minuti; `test_stress` (60 anni) da 975 s a
208 s, sotto il limite di 400 s.

---

## 19.4 — Salvataggi

| Verifica | Come | Esito |
|---|---|---|
| Nuovi salvataggi | `test_save` (andata e ritorno con stato e casualità), `test_settlement`, `test_war` (guerre e assedi dopo un caricamento), `stress_runner` (città da 1000/2000, guerra, diplomazia, 150 anni: stessi abitanti, edifici ed eserciti dopo il caricamento) | ✅ |
| Vecchi salvataggi | Due salvataggi scritti dalla build della Fase 18 (prima del world art pass) sono ora fixture del progetto (`tests/fixtures/saves/phase18_village30.kdsave`, `phase18_town.kdsave`): il menu ne legge l'intestazione, si aprono, vanno avanti 40 giorni, si riscrivono uguali. Le migrazioni v1 → v5 restano coperte da `test_kingdoms` e `test_founders`. | ✅ |
| Salvataggio rotto | File tronco a metà e file che non è un salvataggio: rifiutati, il menu non li elenca, nessun crash; la scrittura atomica lascia intatto lo slot se il gioco muore a metà (B11). | ✅ |
| Autosalvataggio | Ogni anno anche quando il giorno esatto viene saltato (B3); mai subito dopo un avvio o un caricamento; ne restano 3; la rotazione non rilegge più tutto lo scaffale (B19); screenshot e benchmark non scrivono (B4). | ✅ |
| Caricamento | Dal menu (`test_menu`), dal menu di pausa e con F9: la scena si ricostruisce attorno al mondo caricato (`quickload_check.tscn`: F5, 20 giorni, F9 → giorno del salvataggio, vecchia scena e vecchio HUD spariti, «Partita caricata» nelle notizie). | ✅ |
| Menu | Elenco con intestazioni (ora in cache per data di modifica), il più recente per «Continua», rotazione. | ✅ |
| Tutorial | La guida è salvata con la campagna (`test_menu::test_the_guide_is_saved_with_the_campaign`). | ✅ |
| Monarchia | La fixture della cittadina della Fase 18 è incoronata e resta incoronata dopo caricamento e riscrittura; `test_founders` copre incoronazione e migrazione v4 → v5. | ✅ |
| Sei fondatori | `test_settlement::test_start_settlement_six_founders_and_no_king`, `test_founders`. | ✅ |

