"""Places the illustrated mountain sprites on the official map (data/world/mountains.json).

Run with Blender's bundled Python (numpy):
  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\5.2\\python\\bin\\python.exe" tools/worldgen/place_mountains.py
Reads the committed height/water rasters, so it can be re-run without regenerating the world.
Greedy placement from the highest ground down: each sprite gets a footprint width from the local height and a class
(hill / peak / snowpeak); sprites overlap into ranges but never pile on top of each other.
"""
import json
import math
import os
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
WORLD = os.path.join(ROOT, "data", "world")

MIN_HEIGHT = 650.0        # below this the painted relief is enough
HILL_MAX = 1150.0
PEAK_MAX = 1850.0
SPACING = 0.48            # minimum distance between sprites, in mean footprint widths
HILL_SPACING = 0.70      # hills are sparser: a few rounded mounds, not a carpet
VARIANTS = 4


def raster(meta, name, dtype):
    r = meta["rasters"][name]
    data = zlib.decompress(open(os.path.join(WORLD, r["file"]), "rb").read())
    return np.frombuffer(data, dtype).reshape(r["height"], r["width"])


def footprint_m(h):
    return float(np.clip(800.0 + h * 1.9, 1700.0, 7000.0))


def main():
    meta = json.load(open(os.path.join(WORLD, "world_meta.json"), encoding="utf-8"))
    cell = float(meta["cell_m"])
    h = raster(meta, "height", np.float32)
    water = raster(meta, "water", np.uint8)
    fine = (water != 0)[:h.shape[0] * 2, :h.shape[1] * 2]
    wet = fine[0::2, 0::2] | fine[1::2, 0::2] | fine[0::2, 1::2] | fine[1::2, 1::2]  # any water in the 64 m cell
    ys, xs = np.nonzero((h > MIN_HEIGHT) & ~wet)
    order = np.argsort(-h[ys, xs])
    placed = []
    grid = {}
    bucket = 3000.0
    rng_hash = lambda x, y: (int(x) * 73856093 ^ int(y) * 19349663) & 0x7FFFFFFF
    for idx in order:
        y, x = ys[idx], xs[idx]
        hv = float(h[y, x])
        wx, wy = (x + 0.5) * cell, (y + 0.5) * cell
        w = footprint_m(hv)
        bx, by = int(wx // bucket), int(wy // bucket)
        ok = True
        for gy in range(by - 3, by + 4):
            for gx in range(bx - 3, bx + 4):
                for (px, py, pw) in grid.get((gx, gy), ()):
                    # ranges read as rows of peaks: allow closer packing sideways than in depth
                    dx, dy = (px - wx), (py - wy) * 1.6
                    if math.hypot(dx, dy) < (SPACING if hv >= HILL_MAX else HILL_SPACING) * 0.5 * (pw + w):
                        ok = False
                        break
                if not ok:
                    break
            if not ok:
                break
        if not ok:
            continue
        cls = "hill" if hv < HILL_MAX else ("peak" if hv < PEAK_MAX else "snowpeak")
        variant = rng_hash(x, y) % VARIANTS
        placed.append([round(wx, 1), round(wy, 1), round(w, 1), cls, variant])
        grid.setdefault((bx, by), []).append((wx, wy, w))
    placed.sort(key=lambda p: p[1])
    counts = {c: sum(1 for p in placed if p[3] == c) for c in ("hill", "peak", "snowpeak")}
    with open(os.path.join(WORLD, "mountains.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"version": 1, "fields": ["x", "y", "width_m", "class", "variant"], "items": placed}, f,
                  separators=(",", ":"))
    print("mountains", len(placed), counts)


if __name__ == "__main__":
    main()

