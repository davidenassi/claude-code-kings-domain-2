#!/usr/bin/env bash
# Creates the pipeline virtualenv and downloads Godot 4.7.2 (Linux, used for import/screenshots).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
python3.11 -m venv "$HERE/.venv" 2>/dev/null || python3 -m venv "$HERE/.venv"
"$HERE/.venv/bin/pip" install -q -r "$HERE/requirements.txt"
mkdir -p "$HERE/.tools"
if [ ! -x "$HERE/.tools/godot" ]; then
  curl -sSL -o "$HERE/.tools/godot.zip" \
    https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
  (cd "$HERE/.tools" && unzip -o -q godot.zip && mv Godot_v4.7.2-stable_linux.x86_64 godot && rm godot.zip)
fi
"$HERE/.tools/godot" --version
"$HERE/.venv/bin/python" -c "import bpy; print('Blender', bpy.app.version_string)"
