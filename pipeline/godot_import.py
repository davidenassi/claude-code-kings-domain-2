"""Apply per-asset Godot import settings, then (re)import the project.

Data maps (material weights, water flow, height grids) must stay bit-exact: lossless, no alpha-border
fix. Big colour maps use VRAM compression to save video memory.
"""
from __future__ import annotations

import fnmatch
import glob
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.abspath(os.path.join(HERE, "..", "game"))
GODOT = os.path.join(HERE, ".tools", "godot")

RULES = [
    # (glob relative to game/, {param: value})
    ("assets/terrain/mat_*.png", {"compress/mode": "0", "process/fix_alpha_border": "false", "mipmaps/generate": "true"}),
    ("assets/terrain/water_*.png", {"compress/mode": "0", "process/fix_alpha_border": "false", "mipmaps/generate": "true"}),
    ("assets/terrain/heightgrid.png", {"compress/mode": "0", "process/fix_alpha_border": "false", "mipmaps/generate": "false"}),
    ("assets/terrain/watergrid.png", {"compress/mode": "0", "process/fix_alpha_border": "false", "mipmaps/generate": "false"}),
    ("assets/terrain/groundlight.png", {"compress/mode": "0", "process/fix_alpha_border": "false", "mipmaps/generate": "false"}),
    ("assets/terrain/color_*.webp", {"compress/mode": "2", "mipmaps/generate": "true"}),
    ("assets/slice_ground/ground_*.webp", {"compress/mode": "2", "mipmaps/generate": "true"}),
    ("assets/terrain/light_*.webp", {"compress/mode": "2", "mipmaps/generate": "true"}),
]


def run_import():
    subprocess.run([GODOT, "--headless", "--path", GAME, "--import"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, timeout=1800)


def apply_rules() -> list[str]:
    changed = []
    for pattern, params in RULES:
        for src in glob.glob(os.path.join(GAME, pattern)):
            imp = src + ".import"
            if not os.path.exists(imp):
                continue
            text = open(imp).read()
            new = text
            for k, v in params.items():
                rx = re.compile(r"^" + re.escape(k) + r"=.*$", re.M)
                if rx.search(new):
                    new = rx.sub(f"{k}={v}", new)
                else:
                    new = new.replace("[params]\n", f"[params]\n\n{k}={v}\n", 1)
            if new != text:
                open(imp, "w").write(new)
                changed.append(src)
    return changed


def main():
    run_import()                       # creates .import files for new assets
    changed = apply_rules()
    if changed:
        # force re-import of the files whose settings changed
        for src in changed:
            name = os.path.basename(src)
            for f in glob.glob(os.path.join(GAME, ".godot", "imported", name + "-*")):
                os.remove(f)
        run_import()
    print(f"import settings applied to {len(changed)} files")


if __name__ == "__main__":
    main()
