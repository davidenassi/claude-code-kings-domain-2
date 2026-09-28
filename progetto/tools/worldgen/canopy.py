"""Visual tree cover of the official map (data/world/canopy.bin), derived from the forest density raster.

Run with Blender's bundled Python (numpy), after the terrain stage:
  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\5.2\\python\\bin\\python.exe" tools/worldgen/canopy.py

forest.bin stays the ecological/statistical density (province stats, fertility). canopy.bin is where trees actually
stand: the same forests with clearings, thicker and more open stands, ragged edges, thinner cover on steep slopes and
at the water's edge. Both the runtime tree placement and the far albedo read it, so near and far zoom show the same woods.
"""
import json
import os
import sys
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))
WORLD = os.path.join(ROOT, "data", "world")

from kdio import write_png, write_raster  # noqa: E402
from kdnoise import Perlin, fbm, smoothstep  # noqa: E402
from grids import box_blur  # noqa: E402

SEED = 91731


def raster(meta, name, dtype):
    r = meta["rasters"][name]
    data = zlib.decompress(open(os.path.join(WORLD, r["file"]), "rb").read())
    return np.frombuffer(data, dtype).reshape(r["height"], r["width"])


def build_canopy(forest, height, water_fine, cell):
    h, w = forest.shape
    ys, xs = np.mgrid[0:h, 0:w]
    xk = (xs + 0.5) * cell / 1000.0
    yk = (ys + 0.5) * cell / 1000.0
    f = forest.astype(np.float64) / 255.0

    # thick and open stands (2-3 km patches)
    stands = fbm(Perlin(SEED), xk / 2.6, yk / 2.6, 3)
    f *= np.clip(0.80 + 0.42 * stands, 0.45, 1.25)
    # ragged edges: push the forest boundary in and out (strongest where density is intermediate)
    edge = fbm(Perlin(SEED + 1), xk / 0.55, yk / 0.55, 3)
    f += 0.55 * edge * np.clip(f * (1.0 - f) * 4.0, 0.0, 1.0)
    # clearings: scattered glades of 200-600 m inside the woods
    glade = fbm(Perlin(SEED + 2), xk / 0.7, yk / 0.7, 2)
    glade_small = fbm(Perlin(SEED + 3), xk / 0.28, yk / 0.28, 2)
    clearing = np.maximum(smoothstep(0.34, 0.48, glade), smoothstep(0.52, 0.62, glade_small) * 0.7)
    f *= 1.0 - 0.92 * clearing * smoothstep(0.25, 0.5, f)
    # steep slopes carry fewer trees
    gy, gx = np.gradient(height.astype(np.float64), cell)
    slope = np.sqrt(gx * gx + gy * gy)
    f *= 1.0 - 0.45 * smoothstep(0.22, 0.55, slope)
    # open ground at the water's edge (shores, lake banks)
    wet = water_fine[:h * 2, :w * 2] != 0
    wet64 = (wet[0::2, 0::2] | wet[1::2, 0::2] | wet[0::2, 1::2] | wet[1::2, 1::2]).astype(np.float64)
    near_water = box_blur(wet64, 1, 1)
    f *= 1.0 - 0.55 * np.clip(near_water * 2.0, 0.0, 1.0)
    f = np.where(wet64 > 0.5, 0.0, f)
    f = np.where(f < 0.06, 0.0, f)
    return np.clip(f * 255.0 + 0.5, 0, 255).astype(np.uint8)


def main():
    meta_path = os.path.join(WORLD, "world_meta.json")
    meta = json.load(open(meta_path, encoding="utf-8"))
    cell = float(meta["cell_m"])
    forest = raster(meta, "forest", np.uint8)
    height = raster(meta, "height", np.float32)
    water = raster(meta, "water", np.uint8)
    canopy = build_canopy(forest, height, water, cell)
    info = write_raster(os.path.join(WORLD, "canopy.bin"), canopy)
    meta["rasters"]["canopy"] = dict(info, cell_m=cell, format="R8")
    with open(meta_path, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=1)
    prev = os.path.join(HERE, "out_preview")
    os.makedirs(prev, exist_ok=True)
    write_png(os.path.join(prev, "canopy.png"), canopy)
    land = height > 0
    print("canopy: mean forest %.3f -> canopy %.3f (land)" % (forest[land].mean() / 255.0, canopy[land].mean() / 255.0))


if __name__ == "__main__":
    main()

