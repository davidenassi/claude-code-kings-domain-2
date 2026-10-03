#!/usr/bin/env bash
# Usage: pipeline/capture.sh res://data/capture/<views>.json <output dir> [--noimport]
# Re-imports changed assets, then renders the listed views at 1920x1080 under a virtual display.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="$HERE/../game"
GODOT="$HERE/.tools/godot"
if [ "${3:-}" != "--noimport" ]; then
  "$HERE/.venv/bin/python" "$HERE/godot_import.py"
fi
timeout 1800 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$GAME" --resolution 1920x1080 \
  -- --capture="$1" --out="$2" 2>&1 | grep -vE "ALSA|^\s*$|at: |audio|V-Sync" || true
