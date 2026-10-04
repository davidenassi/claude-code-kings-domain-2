# King's Domain — rinascita

Gioco 2.5D medieval-fantasy: costruisci il cuore del tuo regno in **una grande valle** (city builder) e usa
quella forza per affrontare **un mondo molto più grande** (campagne e conquista).

> Il progetto è stato ricreato da zero. I file `1_documenti.txt` … `5_strumenti.txt` e `LEGGIMI.md` sono il
> vecchio King's Domain, conservati solo come riferimento concettuale.

## Stato

| Fase | Contenuto | Stato |
|---|---|---|
| Premessa tecnica | [`KINGSDOMAIN_TECHNICAL_FOUNDATION.md`](KINGSDOMAIN_TECHNICAL_FOUNDATION.md) | ✅ |
| **Fase 1** — grafica della Valle | [`PHASE_1_GRAPHICS_REPORT.md`](PHASE_1_GRAPHICS_REPORT.md), screenshot in `screenshots/phase1/` | ✅ |
| **Fase 1B** — vertical slice grafico (quartiere sul fiume) | [`PHASE_1B_VISUAL_VERTICAL_SLICE_REPORT.md`](PHASE_1B_VISUAL_VERTICAL_SLICE_REPORT.md), screenshot e confronti in `screenshots/phase1b/` | ✅ in attesa di approvazione |
| Fase 2 — interfaccia e city builder | — | non iniziata |
| Fase 3 — il mondo oltre la valle | — | non iniziata |
| Fase 4 — simulazione, eserciti, economia | — | non iniziata |

## Aprire il gioco

1. Godot **4.7.2** (renderer Compatibility).
2. Aprire la cartella `game/` come progetto, avviare la scena principale (`valley/valley.tscn`).

Comandi della Valle: rotellina = zoom verso il cursore · WASD / frecce = spostamento · tasto destro o centrale
trascinato = spostamento · **F3** = prestazioni.

Galleria della libreria grafica: scena `gallery/gallery.tscn`.

Benchmark su una GPU reale: `godot --path game -- --benchmark` (scrive `user://benchmark.json`).

## Rigenerare gli asset

Tutto è prodotto dalla pipeline in `pipeline/` (Python 3.11 + Blender 4.5 come modulo `bpy` + numpy/numba):
vedi la sezione 2 di `PHASE_1_GRAPHICS_REPORT.md`. `pipeline/setup_env.sh` prepara l'ambiente.

## Struttura

```
game/       progetto Godot (valle, galleria, strumenti, dati, asset generati)
pipeline/   generatori: terreno, Blender (vegetazione, edifici, cittadini), layout, texture, strumenti
docs/       materiale di riferimento (docs/reference: le 4 immagini di riferimento della Fase 1B)
screenshots/phase1/   screenshot ufficiali della Fase 1
screenshots/phase1b/  screenshot, confronti e iterazione 1 della Fase 1B
```
