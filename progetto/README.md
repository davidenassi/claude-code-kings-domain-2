# King's Domain

Un gioco strategico/gestionale medievale in 2D semplice e leggibile (Godot 4.7): da **un re e sei abitanti** a una potenza continentale,
su **un solo mondo continuo**.

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
Spazio = pausa · 1–5 = velocità · F5/F9 = salvataggio/caricamento rapido · F3 = pannello di debug.

## Verifica automatica
```
powershell -ExecutionPolicy Bypass -File tools\check.ps1
powershell -ExecutionPolicy Bypass -File tools\check.ps1 -SkipImport -Screenshot -Camera "56000,36000,40"
```
Import headless, test (`tests/`), screenshot in `tests/output/`, log in `logs/`.

