"""King's Domain official world generator.

Run with Blender's bundled Python (numpy included):
  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\5.2\\python\\bin\\python.exe" tools/worldgen/generate_world.py
Options:
  --stages terrain,provinces,albedo   (default: all)
  --out data/world
The output is the OFFICIAL map and must be committed. The seed is fixed in layout.py.
"""
import argparse
import json
import os
import pickle
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))

import layout as L  # noqa: E402
import terrain as T  # noqa: E402
from kdio import write_json, write_png, write_raster  # noqa: E402

GENERATOR_VERSION = 1
CACHE = os.path.join(HERE, "cache")
PREVIEW = os.path.join(HERE, "out_preview")


def load_biome_defs():
    with open(os.path.join(ROOT, "data", "defs", "biomes.json"), encoding="utf-8") as f:
        return json.load(f)["items"]


def save_cache(name, ctx, keys):
    os.makedirs(CACHE, exist_ok=True)
    with open(os.path.join(CACHE, name + ".pkl"), "wb") as f:
        pickle.dump({k: ctx[k] for k in keys if k in ctx}, f, protocol=pickle.HIGHEST_PROTOCOL)


def load_cache(name, ctx):
    path = os.path.join(CACHE, name + ".pkl")
    if not os.path.exists(path):
        return False
    with open(path, "rb") as f:
        ctx.update(pickle.load(f))
    return True


TERRAIN_KEYS = ["potential64", "land32", "land64", "land_dist64", "sea_dist64", "inland_km", "offshore_km",
                "elev64", "range_mask64", "filled128", "acc128", "lake128", "land128", "lakes", "rivers", "lake64", "lake_f64",
                "water32", "coast32", "river_dist64", "river_prox64", "moisture64", "temperature64", "slope64", "biome64", "forest64"]


def stage_terrain(ctx, biome_defs):
    t0 = time.time()
    print("[terrain]", flush=True)
    T.build_continent(ctx)
    T.build_elevation(ctx)
    T.build_hydrology(ctx)
    T.build_water32(ctx)
    T.build_climate(ctx)
    T.build_biomes(ctx, biome_defs)
    save_cache("terrain", ctx, TERRAIN_KEYS)
    print("[terrain] done in %.1f s" % (time.time() - t0), flush=True)


def ensure_mesh(ctx):
    if "X" not in ctx:
        ctx["X"], ctx["Y"] = T.world_mesh(T.CELL, T.W, T.H)


def write_terrain_outputs(ctx, out_dir, meta):
    os.makedirs(out_dir, exist_ok=True)
    rasters = meta.setdefault("rasters", {})
    rasters["height"] = dict(write_raster(os.path.join(out_dir, "height.bin"), ctx["elev64"].astype(np.float32)),
                             cell_m=T.CELL, format="RF", unit="m")
    rasters["biome"] = dict(write_raster(os.path.join(out_dir, "biome.bin"), ctx["biome64"]), cell_m=T.CELL, format="R8")
    rasters["forest"] = dict(write_raster(os.path.join(out_dir, "forest.bin"), ctx["forest64"]), cell_m=T.CELL, format="R8")
    rasters["moisture"] = dict(write_raster(os.path.join(out_dir, "moisture.bin"),
                                            np.clip(ctx["moisture64"] * 255, 0, 255).astype(np.uint8)), cell_m=T.CELL, format="R8")
    rasters["temperature"] = dict(write_raster(os.path.join(out_dir, "temperature.bin"),
                                               np.clip(ctx["temperature64"] * 255, 0, 255).astype(np.uint8)), cell_m=T.CELL, format="R8")
    rasters["water"] = dict(write_raster(os.path.join(out_dir, "water.bin"), ctx["water32"]), cell_m=T.FINE, format="R8",
                            values={"land": 0, "sea": 1, "lake": 2, "river": 3})
    rasters["coast"] = dict(write_raster(os.path.join(out_dir, "coast.bin"), ctx["coast32"]), cell_m=T.FINE, format="R8",
                            encoding="127.5 + 2*cells to coast (land positive)")
    rivers = []
    for r in ctx["rivers"]:
        flat = []
        for (x, y, wdt) in r["points"]:
            flat.extend([round(x, 1), round(y, 1), round(wdt, 1)])
        rivers.append({"id": r["id"], "length_m": round(r["length_m"]), "max_width_m": round(r["max_width"], 1), "xyw": flat})
    write_json(os.path.join(out_dir, "rivers.json"), {"version": 1, "rivers": rivers}, compact=True)
    lakes = [{"cells128": lk["cells"], "level_m": round(lk["level"], 1),
              "x": round((lk["cx"] + 0.5) * 128.0), "y": round((lk["cy"] + 0.5) * 128.0)} for lk in ctx["lakes"]]
    meta["lakes"] = lakes
    meta["river_count"] = len(rivers)
    meta["river_total_km"] = round(sum(r["length_m"] for r in rivers) / 1000.0, 1)
    meta["land_fraction"] = round(float(ctx["land32"].mean()), 4)


def write_previews(ctx):
    import render as R
    os.makedirs(PREVIEW, exist_ok=True)
    write_png(os.path.join(PREVIEW, "elevation.png"), R.preview_elevation(ctx))
    write_png(os.path.join(PREVIEW, "moisture.png"), R.preview_scalar(ctx["moisture64"], 0.0, 1.0))
    write_png(os.path.join(PREVIEW, "temperature.png"), R.preview_scalar(ctx["temperature64"], 0.0, 1.0))
    pal = R.palette_from_defs(load_biome_defs())
    write_png(os.path.join(PREVIEW, "biomes.png"), (pal[ctx["biome64"]] * 255).astype(np.uint8))
    write_png(os.path.join(PREVIEW, "forest.png"), ctx["forest64"])
    w = ctx["water32"][::2, ::2]
    img = np.zeros(w.shape + (3,), dtype=np.uint8)
    img[w == 0] = (200, 190, 160)
    img[w == 1] = (40, 80, 110)
    img[w == 2] = (60, 120, 170)
    img[w == 3] = (30, 90, 200)
    write_png(os.path.join(PREVIEW, "water.png"), img)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stages", default="terrain,provinces,albedo")
    ap.add_argument("--out", default=os.path.join(ROOT, "data", "world"))
    ap.add_argument("--use-cache", action="store_true", help="reuse cached terrain instead of regenerating")
    args = ap.parse_args()
    stages = [s.strip() for s in args.stages.split(",") if s.strip()]
    biome_defs = load_biome_defs()
    ctx = {}
    t0 = time.time()
    meta_path = os.path.join(args.out, "world_meta.json")
    meta = {}
    if os.path.exists(meta_path):
        with open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)
    meta.update({
        "world_version": 1,
        "generator_version": GENERATOR_VERSION,
        "world_width_m": L.WORLD_W_M,
        "world_height_m": L.WORLD_H_M,
        "cell_m": T.CELL,
        "fine_cell_m": T.FINE,
        "grid_width": T.W,
        "grid_height": T.H,
        "fine_grid_width": T.W32,
        "fine_grid_height": T.H32,
    })

    if "terrain" in stages and not args.use_cache:
        stage_terrain(ctx, biome_defs)
    elif not load_cache("terrain", ctx):
        stage_terrain(ctx, biome_defs)
    ensure_mesh(ctx)
    if "terrain" in stages:
        write_terrain_outputs(ctx, args.out, meta)
        write_previews(ctx)

    if "provinces" in stages:
        import provinces as P
        P.stage_provinces(ctx, args.out, meta, biome_defs)

    if "albedo" in stages:
        import render as R
        img = R.render_albedo(ctx, biome_defs)
        write_png(os.path.join(args.out, "albedo_far.png"), img)
        write_png(os.path.join(PREVIEW, "albedo_small.png"), img[::4, ::4])

    os.makedirs(args.out, exist_ok=True)
    write_json(meta_path, meta)
    print("world generated in %.1f s -> %s" % (time.time() - t0, args.out), flush=True)


if __name__ == "__main__":
    main()

