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
