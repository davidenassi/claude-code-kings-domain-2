# King's Domain

Un gioco medievale di fondazione e crescita che evolve in un grand strategy (Godot 4.7): da **sei fondatori** a una grande
potenza. **Rebirth (dal 28/09/2026): due mappe, una simulazione** — la **mappa locale del dominio** (la valle della patria:
costruisci, osservi, vivi) e la **mappa globale strategica** (il continente: esplori, comprendi, espandi).
Piano e stato in [KINGSDOMAIN_REBIRTH_AUDIT.md](KINGSDOMAIN_REBIRTH_AUDIT.md) e [KINGSDOMAIN_REBIRTH_REPORT.md](KINGSDOMAIN_REBIRTH_REPORT.md).

## Documenti
- [GAME_DESIGN_MAP.md](GAME_DESIGN_MAP.md) — cosa è il gioco e come i sistemi si toccano
- [LEGACY_SYSTEM_AUDIT.md](LEGACY_SYSTEM_AUDIT.md) — cosa viene da *Regno*, cosa cambia, cosa sparisce
- [TECHNICAL_ARCHITECTURE.md](TECHNICAL_ARCHITECTURE.md) — come è costruito
- [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) — le fasi
- [DEVELOPMENT_STATUS.md](DEVELOPMENT_STATUS.md) — a che punto siamo

## Avvio
Aprire la cartella con Godot 4.7.2 oppure da terminale:
```
"C:\Users\ciabe\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\ciabe\OneDrive\Desktop\KING'S DOMAIN"
```

Comandi: rotella = zoom verso il cursore · WASD/frecce o tasto destro/centrale trascinato = spostamento ·
**Tab = valle ⇄ mappa del mondo** (anche il pulsante «Mondo» dell'orologio, quello della minimappa, o doppio clic sulla
patria nella mappa del mondo) · Spazio = pausa · 1–5 = velocità · F5/F9 = salvataggio/caricamento rapido ·
F3 = pannello di debug.

Linux / CI: `tools/setup_generated.sh` rigenera mappa e atlanti (identici all'originale), `tools/check.sh` fa import e test.

## Verifica automatica
```
powershell -ExecutionPolicy Bypass -File tools\check.ps1
powershell -ExecutionPolicy Bypass -File tools\check.ps1 -SkipImport -Screenshot -Camera "56000,36000,40"
```
Import headless, test (`tests/`), screenshot in `tests/output/`, log in `logs/`.

