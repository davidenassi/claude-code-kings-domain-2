#!/usr/bin/env bash
# King's Domain — avvio del gioco (Linux / macOS).
#
#   ./avvia_gioco.sh              avvia la Valle
#   ./avvia_gioco.sh galleria     avvia la galleria degli asset
#   ./avvia_gioco.sh benchmark    misura gli FPS sulle viste della Fase 1B (risultato in user://benchmark.json)
#
# Cerca Godot 4.7.2 da solo (variabile GODOT, file godot_path.txt, PATH, cartelle comuni). Se non lo trova,
# chiede il percorso e lo ricorda in godot_path.txt. Alla prima apertura prepara le risorse (alcuni minuti).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="$HERE/game"
WANT="4.7"

say() { printf '%s\n' "$*"; }

find_godot() {
    local c
    if [ -n "${GODOT:-}" ] && [ -x "${GODOT}" ]; then echo "$GODOT"; return; fi
    if [ -f "$HERE/godot_path.txt" ]; then
        c="$(head -n 1 "$HERE/godot_path.txt")"
        if [ -x "$c" ]; then echo "$c"; return; fi
    fi
    for c in godot4 godot Godot; do
        if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return; fi
    done
    for c in \
        "$HERE/pipeline/.tools/godot" \
        "/Applications/Godot.app/Contents/MacOS/Godot" \
        "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
        "$HOME/bin/godot" "$HOME/.local/bin/godot" "/usr/local/bin/godot" "/opt/godot/godot"; do
        if [ -x "$c" ]; then echo "$c"; return; fi
    done
    # zip scaricato e lasciato in Download / Scrivania / nella cartella del gioco
    for d in "$HERE" "$HOME/Downloads" "$HOME/Scaricati" "$HOME/Desktop" "$HOME/Scrivania"; do
        [ -d "$d" ] || continue
        c="$(find "$d" -maxdepth 3 \( -name 'Godot_v4*_linux.x86_64' -o -name 'Godot_v4*_linux.arm64' \) \
              -type f 2>/dev/null | sort -r | head -n 1)"
        if [ -n "$c" ]; then chmod +x "$c" 2>/dev/null; echo "$c"; return; fi
        c="$(find "$d" -maxdepth 3 -path '*Godot*.app/Contents/MacOS/Godot' -type f 2>/dev/null | sort -r | head -n 1)"
        if [ -n "$c" ]; then echo "$c"; return; fi
    done
    if command -v flatpak >/dev/null 2>&1 && flatpak info org.godotengine.Godot >/dev/null 2>&1; then
        echo "flatpak run org.godotengine.Godot"; return
    fi
}

GODOT_CMD="$(find_godot)"
if [ -z "$GODOT_CMD" ]; then
    say ""
    say "  Non trovo Godot $WANT.2 su questo computer."
    say "  1. Scaricalo da https://godotengine.org/download/archive/  (versione 4.7.2, standard, non .NET)"
    say "  2. Estrai lo zip"
    say "  3. Scrivi o trascina qui il percorso dell'eseguibile di Godot e premi Invio"
    say ""
    printf '  Percorso di Godot: '
    read -r GODOT_CMD
    GODOT_CMD="${GODOT_CMD%\"}"; GODOT_CMD="${GODOT_CMD#\"}"; GODOT_CMD="${GODOT_CMD%\'}"; GODOT_CMD="${GODOT_CMD#\'}"
    GODOT_CMD="${GODOT_CMD% }"
    case "$GODOT_CMD" in *.app) GODOT_CMD="$GODOT_CMD/Contents/MacOS/Godot" ;; esac
    if [ ! -x "$GODOT_CMD" ]; then say "  File non trovato o non eseguibile: $GODOT_CMD"; exit 1; fi
    printf '%s\n' "$GODOT_CMD" > "$HERE/godot_path.txt"
    say "  Percorso salvato in godot_path.txt"
fi

# comando come array: percorsi con spazi e "flatpak run ..." funzionano entrambi
if [ "$GODOT_CMD" = "flatpak run org.godotengine.Godot" ]; then G=(flatpak run org.godotengine.Godot); else G=("$GODOT_CMD"); fi

# versione
VER="$("${G[@]}" --version 2>/dev/null | tail -n 1)"
case "$VER" in
    "$WANT".*) ;;
    "") say "Attenzione: non riesco a leggere la versione di Godot (serve $WANT.2)." ;;
    *) say "Attenzione: Godot $VER — il progetto è fatto per Godot $WANT.2. Potrebbe non funzionare." ;;
esac

# risorse: alla prima apertura (o dopo un aggiornamento dei file) Godot le importa
STAMP="$GAME/.godot/kd_import.stamp"
need_import=1
if [ -f "$STAMP" ] && [ -d "$GAME/.godot/imported" ]; then
    if [ -z "$(find "$GAME" -path "$GAME/.godot" -prune -o -type f -newer "$STAMP" -print -quit 2>/dev/null)" ]; then
        need_import=0
    fi
fi
if [ "$need_import" = 1 ]; then
    if [ -d "$GAME/.godot/imported" ]; then
        say "Aggiornamento delle risorse..."
    else
        say "Prima apertura: preparazione delle risorse (texture, sprite, terreno). Può richiedere alcuni minuti..."
    fi
    if ! "${G[@]}" --headless --path "$GAME" --import >"$HERE/import_log.txt" 2>&1; then
        say "Errore durante l'importazione. Dettagli in import_log.txt"
        exit 1
    fi
    touch "$STAMP"
fi

case "${1:-}" in
    galleria) shift; set -- res://gallery/gallery.tscn "$@" ;;
    benchmark) shift; set -- "$@" -- --benchmark --views=res://data/capture/slice_views.json ;;
esac

say "Avvio di King's Domain..."
say "Comandi: rotellina = zoom · WASD / frecce = spostamento · tasto destro trascinato = spostamento · F3 = prestazioni"
exec "${G[@]}" --path "$GAME" "$@"
