#!/usr/bin/env bash
# Regenerates the official map rasters and the sprite atlases from the project's own deterministic tools
# (Python 3 + numpy). The output is byte-for-byte the official data: the compressed sizes written in
# data/world/world_meta.json are checked at the end.
# Usage: tools/setup_generated.sh [--force]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PY="${KD_PYTHON:-python3}"
FORCE="${1:-}"

need() { [ "$FORCE" = "--force" ] || [ ! -s "$1" ]; }

if need data/world/height.bin || need data/world/provinces.json || need data/world/albedo_far.png; then
  echo "== world (terrain, provinces, albedo) =="
  cp data/world/world_meta.json /tmp/kd_world_meta.orig.json
  "$PY" tools/worldgen/generate_world.py
fi
if need data/world/canopy.bin; then
  echo "== canopy =="
  "$PY" tools/worldgen/canopy.py
fi
if need assets/environment/terrain/noise_tile.png; then
  echo "== noise tile =="
  "$PY" tools/worldgen/detail_textures.py
fi
for s in vegetation mountains buildings props people; do
  case $s in
    vegetation) out=assets/environment/vegetation/vegetation_atlas.png ;;
    mountains) out=assets/environment/mountains/mountain_atlas.png ;;
    buildings) out=assets/buildings/building_atlas.png ;;
    props) out=assets/buildings/props_atlas.png ;;
    people) out=assets/people/people_atlas.png ;;
  esac
  if need "$out"; then
    echo "== atlas: $s =="
    "$PY" "tools/art/draw_$s.py"
  fi
done
# the homelands of the Rebirth (local domain maps), when their generator exists
if [ -f tools/domaingen/generate_domains.py ]; then
  echo "== homelands =="
  "$PY" tools/domaingen/generate_domains.py $([ "$FORCE" = "--force" ] && echo --force)
fi

"$PY" - <<'EOF'
import json, os
meta = json.load(open("data/world/world_meta.json"))
bad = []
for name, r in meta["rasters"].items():
    path = os.path.join("data/world", r["file"])
    size = os.path.getsize(path) if os.path.exists(path) else -1
    if size != r["compressed_bytes"]:
        bad.append("%s: %d bytes, meta says %d" % (r["file"], size, r["compressed_bytes"]))
print("rasters: " + ("OK, identical to the official map" if not bad else "MISMATCH\n  " + "\n  ".join(bad)))
EOF
