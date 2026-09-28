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
