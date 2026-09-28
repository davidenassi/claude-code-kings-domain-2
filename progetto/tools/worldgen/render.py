"""Illustrated far-zoom albedo and debug previews."""
import json
import os
import time
import zlib

import numpy as np

import layout as L
from grids import resize_bilinear, resize_nearest
from kdnoise import Perlin, fbm, smoothstep

from terrain import CELL, FINE, H, H32, W, W32, BIOME


def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)], dtype=np.float64) / 255.0


def palette_from_defs(biome_defs):
    pal = np.zeros((256, 3))
    for d in biome_defs:
        pal[d["index"]] = hex_rgb(d["color"])
    return pal


def hillshade(elev, cell, exaggeration, light=(-1.0, -1.0, 1.25)):
    gy, gx = np.gradient(elev.astype(np.float64), cell)
    nx, ny, nz = -gx * exaggeration, -gy * exaggeration, np.ones_like(gx)
    n = np.sqrt(nx * nx + ny * ny + nz * nz)
    lx, ly, lz = light
    ln = (lx * lx + ly * ly + lz * lz) ** 0.5
    dot = (nx * lx + ny * ly + nz * lz) / (n * ln)
    flat = lz / ln
    return dot / flat


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load_style():
    """Colour rules shared with the runtime shaders (data/defs/map_style.json)."""
    with open(os.path.join(ROOT, "data", "defs", "map_style.json"), encoding="utf-8") as f:
        return json.load(f)


def load_canopy(shape):
    """Visual tree cover written by canopy.py; falls back to None (forest density is used instead)."""
    path = os.path.join(ROOT, "data", "world", "canopy.bin")
    if not os.path.exists(path):
        return None
    a = np.frombuffer(zlib.decompress(open(path, "rb").read()), np.uint8)
    return a.reshape(shape) if a.size == shape[0] * shape[1] else None


def render_albedo(ctx, biome_defs):
    """RGB uint8 at 32 m/px: the painted look of the map at strategic/continental zoom."""
    t0 = time.time()
    pal = palette_from_defs(biome_defs)
    biome = ctx["biome64"]
    # soft biome colour transitions: blend palette colours, not indices
    rgb64 = pal[biome]
    for c in range(3):
        rgb64[..., c] = _blur_keep_water(rgb64[..., c], ctx["land64"])
    X32, Y32 = np.meshgrid((np.arange(W32) + 0.5) * FINE, (np.arange(H32) + 0.5) * FINE)
    Xk, Yk = X32 / 1000.0, Y32 / 1000.0
    pw = Perlin(L.WORLD_SEED + 50)
    # warped upsample so biome edges look painted, not pixelated
    wx = (X32 + 90.0 * fbm(pw, Xk / 0.8, Yk / 0.8, 3)) / CELL - 0.5
    wy = (Y32 + 90.0 * fbm(pw, Xk / 0.8 + 9.0, Yk / 0.8, 3)) / CELL - 0.5
    from grids import bilinear_sample
    rgb = np.zeros((H32, W32, 3))
    for c in range(3):
        rgb[..., c] = bilinear_sample(rgb64[..., c], wx, wy)

    elev32 = bilinear_sample(ctx["elev64"].astype(np.float64), X32 / CELL - 0.5, Y32 / CELL - 0.5)
    style = load_style()
    canopy64 = load_canopy(ctx["forest64"].shape)
    cover64 = canopy64 if canopy64 is not None else ctx["forest64"]
    forest32 = bilinear_sample(cover64.astype(np.float64) / 255.0, X32 / CELL - 0.5, Y32 / CELL - 0.5)
    moist32 = bilinear_sample(ctx["moisture64"].astype(np.float64), X32 / CELL - 0.5, Y32 / CELL - 0.5)
    if moist32.max() > 1.5:
        moist32 = moist32 / 255.0
    land = ctx["land32"]
    water = ctx["water32"]

    # regional character (same rule as the terrain shader): dry lands ochre, wet lowlands deeper green
    big = fbm(Perlin(L.WORLD_SEED + 55), Xk / 1.0, Yk / 1.0, 2)
    wet_t = smoothstep(style["moisture_dry"], style["moisture_wet"], moist32 + 0.06 * big)[..., None]
    dry_mul = 1.0 + (np.array(style["ground_dry"]) - 1.0) * style["ground_dry_amount"]
    wet_mul = 1.0 + (np.array(style["ground_wet"]) - 1.0) * style["ground_wet_amount"]
    rgb *= dry_mul * (1.0 - wet_t) + wet_mul * wet_t

    # forests: clumps of painted crowns (colours matched to the tree cluster sprites), toned by moisture like the sprites
    canopy = fbm(Perlin(L.WORLD_SEED + 51), Xk / 0.4, Yk / 0.4, 3)
    speck = fbm(Perlin(L.WORLD_SEED + 52), Xk / 0.14, Yk / 0.14, 2)
    clump = np.clip(0.5 + 0.8 * canopy + 0.2 * speck, 0.0, 1.0)[..., None]
    forest_col = np.array(style["forest_far_color"]) * (1.0 - clump) + np.array(style["forest_far_light"]) * clump
    tone = np.array(style["foliage_dry"]) * (1.0 - wet_t) + np.array(style["foliage_lush"]) * wet_t
    forest_col = forest_col * tone
    f = smoothstep(0.06, 0.42, forest32 + 0.12 * canopy)[..., None]
    rgb = rgb * (1.0 - 0.92 * f) + forest_col * 0.92 * f

    # relief: strong hillshade, more on mountains
    # hinted relief only: the map stays mainly flat and readable
    hs = hillshade(elev32, FINE, 1.8)
    hs = np.clip(hs, 0.45, 1.35)
    rgb *= (0.68 + 0.32 * hs)[..., None]
    # valleys darker and cooler, crests lighter and warmer (the shader uses the height mip 3.5, ~11 cells)
    from grids import box_blur
    blurred = resize_bilinear(box_blur(ctx["elev64"].astype(np.float64), 5, 2), H32, W32)
    local_h = np.clip((elev32 - blurred) / style["valley_depth_m"], -1.0, 1.0)[..., None]
    rgb *= 1.0 + style["valley_light"] * local_h
    tint = np.where(local_h < 0.0, np.array(style["valley_cool"]), np.array(style["crest_warm"]))
    rgb *= 1.0 + (tint - 1.0) * np.abs(local_h)
    # snowy peaks and bare rock tint
    rock = smoothstep(1100.0, 1700.0, elev32)[..., None]
    rgb = rgb * (1.0 - 0.35 * rock) + np.array([0.62, 0.58, 0.50]) * 0.35 * rock * (0.6 + 0.5 * hs[..., None])
    snow = smoothstep(1900.0, 2250.0, elev32 + 120.0 * canopy)[..., None]
    rgb = rgb * (1.0 - snow) + np.array([0.93, 0.95, 0.97]) * snow * np.clip(0.75 + 0.35 * hs[..., None], 0.6, 1.1)

    # paper grain
    grain = fbm(Perlin(L.WORLD_SEED + 53), Xk / 0.05, Yk / 0.05, 2)
    rgb *= (1.0 + 0.05 * grain)[..., None]

    # sea: depth tint and coastal shallows
    coast = ctx["coast32"].astype(np.float64)
    sea_d = np.clip((127.5 - coast) / 2.0, 0.0, 60.0)
    deep = np.array([0.11, 0.30, 0.50])
    shallow = np.array([0.27, 0.56, 0.70])
    tsea = smoothstep(0.0, 26.0, sea_d)[..., None]
    sea_rgb = shallow * (1.0 - tsea) + deep * tsea
    sea_rgb *= (1.0 + 0.04 * fbm(Perlin(L.WORLD_SEED + 54), Xk / 1.5, Yk / 1.5, 3))[..., None]
    foam = (smoothstep(3.0, 0.5, sea_d) * 0.35)[..., None]
    sea_rgb = sea_rgb * (1.0 - foam) + np.array([0.72, 0.86, 0.86]) * foam
    rgb = np.where(land[..., None], rgb, sea_rgb)

    # ink coastline
    land_edge = (coast >= 127.5) & (coast <= 130.0)
    rgb[land_edge] *= 0.62

    # lakes (with shallows from the signed distance) and rivers
    lake_mask = water == 2
    tl = smoothstep(0.0, 10.0, sea_d)[..., None]
    lake_rgb = np.array([0.30, 0.58, 0.68]) * (1.0 - tl) + np.array([0.16, 0.38, 0.56]) * tl
    rgb[lake_mask] = lake_rgb[lake_mask]
    river_rgb = np.array([0.24, 0.49, 0.66])
    rgb[water == 3] = river_rgb

    out = np.clip(rgb * 255.0, 0, 255).astype(np.uint8)
    print("  albedo rendered (%.1f s)" % (time.time() - t0), flush=True)
    return out


def _blur_keep_water(channel, land):
    from grids import box_blur
    return box_blur(channel, 1, 1)


def preview_elevation(ctx):
    e = ctx["elev64"].astype(np.float64)
    hs = np.clip(hillshade(e, CELL, 3.0), 0.3, 1.5)
    col = np.zeros((H, W, 3))
    t = np.clip(e / 2600.0, 0.0, 1.0)
    low = np.array([0.45, 0.62, 0.35])
    high = np.array([0.85, 0.80, 0.70])
    col = low * (1 - t[..., None]) + high * t[..., None]
    col *= hs[..., None] * 0.8
    col[e <= 0] = np.array([0.15, 0.3, 0.45])
    return np.clip(col * 255, 0, 255).astype(np.uint8)


def preview_scalar(a, lo, hi):
    t = np.clip((a.astype(np.float64) - lo) / (hi - lo), 0.0, 1.0)
    return (t * 255).astype(np.uint8)

