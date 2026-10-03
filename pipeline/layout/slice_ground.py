"""Phase 1B painted ground of the vertical slice (32 px/m), projected with the terrain's exact oblique
projection and cut into overlay chunks drawn above the terrain.

Layers, in ground space: meadow (multi-scale grass, clover, flowers), trampled earth around buildings,
yards, mud, garden soil, fields (wheat with ears and shadows, ploughed furrows with clods, vegetable rows),
roads by class (path / rural with ruts / lane / urban cobbles of individual stones), the square (flagstones),
river banks (mud, gravel, pebbles). Lighting = the terrain's relative ground light. Transparent over water and
at the region border (noisy soft edge), so the terrain shows through.

Run after layout/slice.py:  python layout/slice_ground.py
Output: game/assets/slice_ground/ground_RR_CC.webp + game/data/valley/slice_ground.json
"""
from __future__ import annotations

import json
import math
import os
import sys

import numba as nb
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from kd import const as K  # noqa: E402
from terrain import noise as N  # noqa: E402

PPM = 32                      # ground texels per metre == Godot px per metre (zoom 1.0 is 1:1)
CACHE = os.path.join(K.CACHE_DIR, "terrain")
OUT = os.path.join(K.GAME_DIR, "assets", "slice_ground")
Y0 = int(-K.NORTH_PAD_M)


def srgb(c):
    return (np.asarray(c, np.float32) / 255.0) ** 2.2


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------------------------------------
@nb.njit(parallel=True, cache=True, fastmath=True)
def voronoi(xs, ys, cell, seed, jitter):
    """Jittered-grid Voronoi: distance to the cell edge (m) and a per-cell hash in [0, 1)."""
    h, w = xs.shape
    edge = np.empty((h, w), np.float32)
    cid = np.empty((h, w), np.float32)
    for j in nb.prange(h):
        for i in range(w):
            px = xs[j, i] / cell
            py = ys[j, i] / cell
            ix = math.floor(px)
            iy = math.floor(py)
            d1 = 1e9
            d2 = 1e9
            best = 0.0
            for oy in range(-1, 2):
                for ox in range(-1, 2):
                    cx = ix + ox
                    cy = iy + oy
                    hsh = math.sin(cx * 127.1 + cy * 311.7 + seed * 74.7) * 43758.5453
                    hsh = hsh - math.floor(hsh)
                    hs2 = math.sin(cx * 269.5 + cy * 183.3 + seed * 12.9) * 43758.5453
                    hs2 = hs2 - math.floor(hs2)
                    fx = cx + 0.5 + (hsh - 0.5) * jitter
                    fy = cy + 0.5 + (hs2 - 0.5) * jitter
                    d = math.sqrt((px - fx) ** 2 + (py - fy) ** 2)
                    if d < d1:
                        d2 = d1
                        d1 = d
                        best = hsh * 0.618 + hs2 * 0.382
                    elif d < d2:
                        d2 = d
            edge[j, i] = (d2 - d1) * 0.5 * cell
            cid[j, i] = best - math.floor(best)
    return edge, cid


def fbm(xs, ys, scale, seed, octaves=4):
    return N.fbm_at(xs.astype(np.float32), ys.astype(np.float32), scale, N.perm(seed), octaves, 2.0, 0.5)


def catmull(pts, step=0.5):
    p = np.asarray(pts, float)
    if len(p) < 3:
        n = max(2, int(np.linalg.norm(p[-1] - p[0]) / step))
        return np.linspace(p[0], p[-1], n)
    out = []
    for i in range(len(p) - 1):
        a, b, c, d = p[max(i - 1, 0)], p[i], p[i + 1], p[min(i + 2, len(p) - 1)]
        n = max(2, int(np.linalg.norm(c - b) / step))
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t ** 3))
    out.append(p[-1])
    return np.array(out)


# ------------------------------------------------------------------------------------------------
TILE = 2048          # px (64 m)
MARGIN = 320         # px (10 m) of context for distance fields and soft edges


def main():
    data = json.load(open(os.path.join(K.GAME_DIR, "data", "valley", "slice.json")))
    x0, y0, x1, y1 = data["region"]
    x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.ceil(x1), math.ceil(y1)
    W, Hh = (x1 - x0) * PPM, (y1 - y0) * PPM
    print("ground", W, "x", Hh, flush=True)
    maps = {
        "wet": np.load(os.path.join(CACHE, "wet.npy")),
        "dw": np.load(os.path.join(CACHE, "d_water.npy")),
        "gl": np.asarray(Image.open(os.path.join(K.GAME_DIR, "assets", "terrain", "groundlight.png")).convert("L"),
                         np.float32) / 255.0 * 1.5,
    }
    ground8 = np.zeros((Hh, W, 4), np.uint8)
    for ty in range(0, Hh, TILE):
        for tx in range(0, W, TILE):
            t = paint_tile(data, maps, (x0, y0, x1, y1), tx, ty, min(TILE, W - tx), min(TILE, Hh - ty))
            ground8[ty:ty + t.shape[0], tx:tx + t.shape[1]] = t
            print("tile", tx // TILE, ty // TILE, flush=True)
    Image.fromarray(ground8).resize((W // 8, Hh // 8), Image.LANCZOS).save(os.path.join(K.CACHE_DIR, "slice_ground_preview.png"))
    hv = np.load(os.path.join(CACHE, "hv.npy"))
    proj = project(ground8, hv, x0, y0, x1, y1)
    write_chunks(proj)


def paint_tile(data, maps, region, tx, ty, tw, th):
    gd = data["ground"]
    rx0, ry0, rx1, ry1 = region
    # tile + margin, in pixels of the region grid
    px0, py0 = tx - MARGIN, ty - MARGIN
    W, Hh = tw + 2 * MARGIN, th + 2 * MARGIN
    x0 = rx0 + px0 / PPM
    y0 = ry0 + py0 / PPM
    x1, y1 = rx1, ry1
    xs1 = x0 + (np.arange(W, dtype=np.float32) + 0.5) / PPM
    ys1 = y0 + (np.arange(Hh, dtype=np.float32) + 0.5) / PPM
    XS, YS = np.meshgrid(xs1, ys1)

    def raster_poly(polys, value=255):
        img = Image.new("L", (W, Hh), 0)
        d = ImageDraw.Draw(img)
        for poly in polys:
            d.polygon([((px - x0) * PPM, (py - y0) * PPM) for px, py in poly], fill=value)
        return np.asarray(img) > 0

    def rect_poly(c, size, yaw):
        """Rotated rectangle (yaw like the sprites: model x axis -> world (cos, -sin))."""
        t = math.radians(yaw)
        ax_ = np.array([math.cos(t), -math.sin(t)])
        ay_ = np.array([math.sin(t), math.cos(t)])
        c = np.array(c, float)
        hw, hd = size[0] / 2, size[1] / 2
        return [c - ax_ * hw - ay_ * hd, c + ax_ * hw - ay_ * hd, c + ax_ * hw + ay_ * hd, c - ax_ * hw + ay_ * hd]

    def dist_inside(mask):
        return ndimage.distance_transform_edt(mask) / PPM

    # terrain maps (1 m) sampled bilinearly
    def sample(grid, cell=1.0, ox=0.0, oy=float(Y0)):
        fx = (XS - ox) / cell - 0.5
        fy = (YS - oy) / cell - 0.5
        return ndimage.map_coordinates(grid, [fy.ravel(), fx.ravel()], order=1, mode="nearest").reshape(XS.shape)

    wet = sample(maps["wet"])
    dw = sample(maps["dw"])
    light = sample(maps["gl"], cell=2.0, ox=0.0, oy=float(Y0))

    # ---------------- meadow
    n_big = fbm(XS, YS, 26.0, 11, 4)
    n_mid = fbm(XS, YS, 6.0, 12, 4)
    n_small = fbm(XS, YS, 1.3, 13, 3)
    n_blade = fbm(XS * 1.0, YS * 0.35, 0.22, 14, 2)          # short strokes (grass blades)
    g_lit = srgb((126, 140, 64))
    g_mid = srgb((92, 112, 48))
    g_dark = srgb((58, 76, 32))
    g_dry = srgb((158, 146, 84))
    t = np.clip(0.5 + n_big * 0.9 + n_mid * 0.5, 0, 1)[..., None]
    col = g_dark * (1 - t) + g_mid * t
    col = col * (1 - np.clip(n_mid * 2.2 - 0.3, 0, 1)[..., None] * 0.5) + g_lit * np.clip(n_mid * 2.2 - 0.3, 0, 1)[..., None] * 0.5
    dry = np.clip((n_big - 0.18) * 3.0, 0, 1)[..., None] * 0.55
    col = col * (1 - dry) + g_dry * dry
    col *= (0.84 + 0.32 * np.clip(0.5 + n_blade * 1.5, 0, 1))[..., None]
    col *= (0.90 + 0.18 * np.clip(0.5 + n_small, 0, 1))[..., None]
    clumps = np.clip((fbm(XS, YS, 0.9, 16, 3) - 0.12) * 3.0, 0, 1)[..., None]
    col = col * (1 - clumps * 0.28)
    # clover and wild flowers: tiny specks in clusters
    rnd = np.random.default_rng(5 + tx * 7 + ty * 13).random(XS.shape).astype(np.float32)
    cluster = np.clip(fbm(XS, YS, 9.0, 15, 3) * 2.5, 0, 1)
    for c_, thr in (((226, 220, 200), 0.9992), ((232, 196, 72), 0.9990), ((170, 128, 200), 0.9994), ((214, 92, 110), 0.9996)):
        m = (rnd > thr - cluster * 0.004)
        m = ndimage.binary_dilation(m, iterations=1)
        col[m] = col[m] * 0.35 + srgb(c_) * 0.65

    alpha = np.ones(XS.shape, np.float32)

    def blend(target, mask_soft):
        nonlocal col
        m = np.clip(mask_soft, 0, 1)[..., None]
        col = col * (1 - m) + target * m

    # ---------------- river banks: wet mud, gravel and pebbles near the water
    bank = smooth(3.2, 0.6, dw + n_mid * 1.5) * (1 - wet)
    vb_e, vb_id = voronoi(XS, YS, 0.22, 3.0, 0.9)
    peb = srgb((168, 160, 146)) * (0.75 + 0.45 * vb_id[..., None])
    peb = peb * (0.55 + 0.45 * smooth(0.0, 0.03, vb_e)[..., None])
    mud = srgb((104, 88, 62)) * (0.85 + 0.25 * np.clip(0.5 + n_small, 0, 1)[..., None])
    bankc = mud * (1 - smooth(0.3, 0.6, 0.5 + n_mid)[..., None]) + peb * smooth(0.3, 0.6, 0.5 + n_mid)[..., None]
    blend(bankc, bank * 0.9)

    # ---------------- trampled earth, yards, mud, gardens
    def soft_shape(polys, edge=1.6, warp=1.4, seed=21):
        m = raster_poly(polys)
        din = dist_inside(m) - ndimage.distance_transform_edt(~m) / PPM
        din = din + fbm(XS, YS, 2.5, seed, 3) * warp
        return smooth(-edge * 0.5, edge * 0.5, din)

    earth = srgb((160, 126, 82)) * (0.78 + 0.34 * np.clip(0.5 + n_mid, 0, 1)[..., None])
    earth = earth * (0.86 + 0.24 * np.clip(0.5 + fbm(XS * 0.6, YS, 0.5, 17, 3) * 1.4, 0, 1)[..., None])
    damp = np.clip((fbm(XS, YS, 4.0, 18, 3) - 0.2) * 2.5, 0, 1)[..., None]
    earth = earth * (1 - damp * 0.22)
    se, sid = voronoi(XS, YS, 0.16, 19.0, 1.0)
    stones_ = (smooth(0.0, 0.012, se) * (sid > 0.86))[..., None]
    earth = earth * (1 - stones_ * 0.35) + srgb((150, 138, 118)) * stones_ * 0.35
    soft_tr = [rect_poly(r["center"], r["size"], r["yaw"]) for r in gd["trampled"] if r.get("soft")]
    hard_tr = [rect_poly(r["center"], r["size"], r["yaw"]) for r in gd["trampled"] if not r.get("soft")]
    tr = soft_shape(soft_tr, 6.0, 3.5, 22) * np.clip(0.35 + n_mid * 1.6, 0, 1) * 0.75
    tr = np.maximum(tr, soft_shape(hard_tr, 2.0, 1.6, 23) * 0.85)
    grass_tufts = np.clip((n_small - 0.1) * 3.0, 0, 1)
    blend(earth, tr * (1 - grass_tufts * 0.6))
    yards = [rect_poly(r["center"], r["size"], r["yaw"]) for r in gd["yards"]]
    yard_m = soft_shape(yards, 2.4, 1.8, 24)
    ye, yid = voronoi(XS, YS, 0.5, 9.0, 0.95)
    yardc = srgb((168, 136, 94)) * (0.84 + 0.24 * np.clip(0.5 + n_mid, 0, 1)[..., None])
    yardc = yardc * (0.92 + 0.12 * yid[..., None])
    blend(yardc, yard_m * (1 - grass_tufts * 0.4))
    mud_m = soft_shape([rect_poly(r["center"], r["size"], r["yaw"]) for r in gd["mud"]], 1.4, 1.0, 25)
    mudc = srgb((88, 66, 44)) * (0.8 + 0.3 * np.clip(0.5 + n_small, 0, 1)[..., None])
    puddle = np.clip((n_mid - 0.15) * 4, 0, 1)[..., None]
    mudc = mudc * (1 - puddle * 0.5) + srgb((70, 84, 92)) * puddle * 0.5
    blend(mudc, mud_m)
    gar = soft_shape([rect_poly(r["center"], np.array(r["size"]) + 1.0, r["yaw"]) for r in gd["gardens"]], 0.8, 0.5, 26)
    blend(srgb((98, 72, 46)) * (0.85 + 0.25 * np.clip(0.5 + n_small, 0, 1)[..., None]), gar)

    # ---------------- fields
    for f in gd["fields"]:
        poly = f["polygon"]
        m = raster_poly([poly])
        din = dist_inside(m)
        a_ = math.radians(f["dir"])
        u = XS * math.cos(a_) + YS * math.sin(a_)
        v = -XS * math.sin(a_) + YS * math.cos(a_)
        if f["crop"] == "wheat":
            rows = 0.5 + 0.5 * np.sin(v * 2 * math.pi / 0.42)
            ears = fbm(u * 0.25, v * 1.0, 0.18, 31, 3)                # little vertical ear strokes
            tone = np.clip(0.5 + fbm(XS, YS, 7.0, 32, 3) * 0.9, 0, 1)
            c = srgb((204, 170, 92)) * tone[..., None] + srgb((164, 130, 66)) * (1 - tone[..., None])
            c = c * (0.72 + 0.4 * np.clip(0.5 + ears * 1.6, 0, 1))[..., None] * (0.9 + 0.12 * rows)[..., None]
            hi = np.clip((ears - 0.25) * 3, 0, 1)[..., None]
            c = c * (1 - hi * 0.4) + srgb((232, 208, 140)) * hi * 0.4
        elif f["crop"] == "plowed":
            fur = 0.5 + 0.5 * np.sin(v * 2 * math.pi / 0.8 + fbm(XS, YS, 3.0, 33, 2) * 2.0)
            fur = fur ** 1.6                                             # narrow dark furrows, wide lit ridges
            cl_e, cl_id = voronoi(XS, YS, 0.12, 41.0, 1.0)
            c = srgb((70, 48, 30)) * (1 - fur[..., None]) + srgb((140, 104, 68)) * fur[..., None]
            c = c * (0.85 + 0.3 * cl_id[..., None]) * (0.8 + 0.2 * smooth(0, 0.02, cl_e)[..., None])
        else:   # vegetable rows: soil lines with green clumps
            r_ = 0.5 + 0.5 * np.sin(v * 2 * math.pi / 0.9)
            clump = smooth(0.35, 0.7, r_) * smooth(-0.2, 0.2, fbm(u * 1.5, v, 0.35, 34, 2) + 0.15)
            soil = srgb((96, 70, 46)) * (0.8 + 0.3 * np.clip(0.5 + n_small, 0, 1)[..., None])
            leaf = srgb((82, 124, 50)) * (0.7 + 0.5 * np.clip(0.5 + fbm(XS, YS, 0.25, 35, 2) * 1.3, 0, 1)[..., None])
            c = soil * (1 - clump[..., None]) + leaf * clump[..., None]
        # grassy headland, then the crop (soft irregular edge)
        e = smooth(0.4, 1.4 + fbm(XS, YS, 2.0, 36, 2) * 0.8, din)
        blend(c, e)

    # ---------------- roads
    def road_dist(points):
        pts = catmull(points, 0.6)
        img = Image.new("L", (W, Hh), 0)
        ImageDraw.Draw(img).line([((px - x0) * PPM, (py - y0) * PPM) for px, py in pts], fill=255, width=1)
        line = np.asarray(img) > 0
        dist = ndimage.distance_transform_edt(~line)
        return dist / PPM, pts

    road_paint = []
    for r in gd["roads"]:
        if r["kind"] == "bridge":
            continue
        d, _ = road_dist(r["points"])
        road_paint.append((r, d))
    ce, cid = voronoi(XS, YS, 0.27, 7.0, 0.85)           # cobbles
    pe, pid = voronoi(XS, YS, 0.09, 8.0, 1.0)            # pebbles
    for r, d in sorted(road_paint, key=lambda z: {"path": 0, "rural": 1, "lane": 2, "urban": 3}[z[0]["kind"]]):
        k = r["kind"]
        w = r["width"] * (1.0 + 0.12 * fbm(XS, YS, 9.0, 41, 2))
        edge_n = fbm(XS, YS, 1.1, 42, 3) * (0.5 if k != "urban" else 0.25)
        edge_n = edge_n + fbm(XS, YS, 0.3, 48, 2) * (0.35 if k != "urban" else 0.1)      # grass tufts on the edge
        core = smooth(w / 2 + 0.12, w / 2 - 0.18, d + edge_n)
        dirt = srgb((170, 136, 92)) * (0.85 + 0.25 * np.clip(0.5 + n_mid, 0, 1)[..., None])
        dirt = dirt * (0.9 + 0.15 * np.clip(0.5 + n_blade * 1.3, 0, 1)[..., None])
        if k in ("rural", "lane"):
            rut = smooth(0.4, 0.0, np.abs(d - w * 0.22)) * 0.6
            dirt = dirt * (1 - rut[..., None] * 0.34)
            pebbles = smooth(0.0, 0.015, pe) * (pid > 0.9) * 0.6
            dirt = dirt * (1 - pebbles[..., None]) + srgb((168, 156, 136)) * pebbles[..., None] * (0.8 + 0.3 * pid[..., None])
            mid_grass = smooth(0.7, 0.2, d) * np.clip(n_small * 2 + 0.1, 0, 1) * (k == "rural") * 0.0
            c = dirt
            blend(c, core * (1 - mid_grass))
            # grassy shoulders
            sh = smooth(w / 2 + 1.0, w / 2 + 0.2, d + edge_n) * (1 - core)
            blend(col * 0.82 + earth * 0.18, sh * 0.6)
        elif k == "path":
            c = dirt * 0.95
            blend(c, core * np.clip(0.7 + n_small, 0, 1))
        else:   # urban cobbles: individual stones, mortar, worn dirt in the joints
            stone = srgb((174, 154, 124)) * (0.72 + 0.42 * cid[..., None])
            stone = stone * (0.88 + 0.16 * np.clip(0.5 + n_small, 0, 1)[..., None])
            joint = smooth(0.0, 0.045, ce)
            hl = smooth(0.03, 0.09, ce) * 0.12
            c = srgb((92, 74, 54)) * (1 - joint[..., None]) + stone * joint[..., None] * (1.0 + hl[..., None])
            worn = np.clip((fbm(XS, YS, 3.5, 43, 3) - 0.15) * 2.5, 0, 1)[..., None] * 0.55
            c = c * (1 - worn) + dirt * worn
            blend(c, core)
            sh = smooth(w / 2 + 1.2, w / 2 + 0.1, d + edge_n) * (1 - core)
            blend(earth, sh * 0.7)

    # ---------------- the square: big irregular flagstones with cobbled margins
    for pz in gd["plazas"]:
        m = raster_poly([pz["polygon"]])
        din = dist_inside(m)
        # square frame (diagonal street grid): u along A = (0.707, -0.707), v along B = (0.707, 0.707)
        u = (XS - YS) * 0.7071
        v = (XS + YS) * 0.7071 + fbm(XS, YS, 6.0, 47, 2) * 0.35
        rh = 0.58
        row = np.floor(v / rh)
        h1 = np.modf(np.abs(np.sin(row * 12.9898) * 43758.5453))[0]
        cw = 0.62 + 0.55 * h1
        uu = u + h1 * 3.1
        colk = np.floor(uu / cw)
        fu = uu / cw - colk
        fv = v / rh - row
        fe = np.minimum(np.minimum(fu, 1 - fu) * cw, np.minimum(fv, 1 - fv) * rh)      # m to the joint
        fid = np.modf(np.abs(np.sin(row * 78.233 + colk * 12.9898) * 43758.5453))[0]
        flag = srgb((188, 166, 128)) * (0.70 + 0.40 * fid[..., None])
        flag = flag * (0.86 + 0.2 * np.clip(0.5 + n_mid * 1.3, 0, 1)[..., None])
        flag = flag * (0.92 + 0.1 * np.clip(0.5 + n_small * 1.5, 0, 1)[..., None])
        joint = smooth(0.0, 0.05, fe)
        c = srgb((100, 82, 60)) * (1 - joint[..., None]) + flag * joint[..., None]
        cob = srgb((170, 150, 120)) * (0.72 + 0.42 * cid[..., None])
        cobc = srgb((92, 74, 54)) * (1 - smooth(0.0, 0.045, ce)[..., None]) + cob * smooth(0.0, 0.045, ce)[..., None]
        margin = smooth(1.8, 1.0, din)[..., None]
        c = c * (1 - margin) + cobc * margin
        # packed earth over the stones where people and carts pass (as in the reference market)
        worn = smooth(-0.08, 0.14, fbm(XS, YS, 5.0, 44, 3) + fbm(XS, YS, 1.2, 49, 2) * 0.3)
        worn = np.maximum(worn, (fid < 0.12) * 0.9)                       # missing flags
        worn = (worn * (1 - margin[..., 0] * 0.6))[..., None]
        c = c * (1 - worn) + earth * worn
        e = smooth(0.0, 0.35, din + fbm(XS, YS, 1.5, 45, 2) * 0.3)
        blend(c, e)

    # ---------------- lighting, transparency (water, border)
    lit = (np.clip(light, 0.3, 1.25) ** 0.85)[..., None]
    col = col * lit
    alpha *= smooth(0.55, 0.05, wet + 0.0) * smooth(0.0, 0.6, dw + 0.25)
    border = np.minimum.reduce([XS - rx0, rx1 - XS, YS - ry0, ry1 - YS])
    alpha *= smooth(1.0, 14.0, border + fbm(XS, YS, 8.0, 46, 3) * 8.0)
    # tonemap like the terrain (lin -> sRGB) with a touch of the illustrated grade
    l = (col * np.array([0.2126, 0.7152, 0.0722])).sum(-1, keepdims=True)
    col = np.clip(l + (col - l) * 1.04, 0, None)
    srgb_col = np.clip(col, 0, 1) ** (1 / 2.2)
    ground = np.concatenate([srgb_col, alpha[..., None]], -1)
    g8 = (np.clip(ground, 0, 1) * 255 + 0.5).astype(np.uint8)
    return g8[MARGIN:MARGIN + th, MARGIN:MARGIN + tw]


@nb.njit(parallel=True, cache=True, fastmath=True)
def _raster(hv, gx0, gy0, nxg, nyg, P, sin_el, cos_el, v_off, out_h, tex, tex_x0, tex_y0, tppm):
    """Screen columns over the region: walk the ground from south to north, keep a horizon, sample `tex`."""
    th, tw = tex.shape[0], tex.shape[1]
    out = np.zeros((out_h, nxg * P, 4), np.uint8)
    for u in nb.prange(nxg * P):
        x = gx0 + (u + 0.5) / P
        i0 = int(math.floor(x - 0.5))
        fx = (x - 0.5) - i0
        horizon = float(out_h)
        prev_v = 0.0
        prev_y = 0.0
        jfirst = gy0 - Y0_ + nyg + 12
        for jj in range(nyg + 24):
            j = jfirst - jj
            if j < 1 or j >= hv.shape[0] - 1:
                continue
            z = hv[j, i0] * (1 - fx) + hv[j, i0 + 1] * fx
            y = Y0_ + j + 0.5
            v = (y * sin_el - z * cos_el) * P - v_off
            if jj > 0 and v < prev_v:
                top = v
                bot = min(prev_v, horizon)
                p0 = int(math.ceil(top - 0.5))
                p1 = int(math.floor(bot - 0.5))
                if p0 < 0:
                    p0 = 0
                if p1 > out_h - 1:
                    p1 = out_h - 1
                inv = 1.0 / (prev_v - v)
                for p in range(p0, p1 + 1):
                    c = p + 0.5
                    if c > bot:
                        continue
                    t = (prev_v - c) * inv
                    gy = prev_y - t
                    tx = (x - tex_x0) * tppm - 0.5
                    ty = (gy - tex_y0) * tppm - 0.5
                    ix = int(math.floor(tx))
                    iy = int(math.floor(ty))
                    if ix < 0 or iy < 0 or ix >= tw - 1 or iy >= th - 1:
                        continue
                    ax = tx - ix
                    ay = ty - iy
                    for ch in range(4):
                        a = tex[iy, ix, ch] * (1 - ax) + tex[iy, ix + 1, ch] * ax
                        b = tex[iy + 1, ix, ch] * (1 - ax) + tex[iy + 1, ix + 1, ch] * ax
                        out[p, u, ch] = np.uint8(min(255.0, a * (1 - ay) + b * ay + 0.5))
                if v < horizon:
                    horizon = v
            prev_v = v
            prev_y = y
    return out


Y0_ = int(-K.NORTH_PAD_M)


def project(tex, hv, x0, y0, x1, y1):
    P = PPM
    nxg, nyg = x1 - x0, y1 - y0
    sub = hv[y0 - Y0_:y1 - Y0_, x0:x1 + 1]
    vmin = ((y0 + 0.5) * K.SIN_EL - sub.max() * K.COS_EL) * P
    vmax = ((y1 + 0.5) * K.SIN_EL - sub.min() * K.COS_EL) * P
    v_off = math.floor(vmin) - 4
    out_h = int(math.ceil(vmax - v_off)) + 8
    out = _raster(hv.astype(np.float32), x0, y0, nxg, nyg, P, K.SIN_EL, K.COS_EL, float(v_off), out_h,
                  tex, float(x0), float(y0), float(PPM))
    print("projected", out.shape, flush=True)
    return {"img": out, "x_px": x0 * P, "y_px": v_off}


def write_chunks(proj, C=2048):
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.startswith("ground_"):
            os.remove(os.path.join(OUT, f))
    img = proj["img"]
    h, w = img.shape[:2]
    chunks = []
    for r in range(math.ceil(h / C)):
        for c in range(math.ceil(w / C)):
            part = img[r * C:(r + 1) * C, c * C:(c + 1) * C]
            if part[..., 3].max() == 0:
                continue
            name = f"ground_{r:02d}_{c:02d}.webp"
            Image.fromarray(part, "RGBA").save(os.path.join(OUT, name), quality=93, method=5)
            chunks.append({"file": name, "x": proj["x_px"] + c * C, "y": proj["y_px"] + r * C,
                           "w": int(part.shape[1]), "h": int(part.shape[0])})
    meta = {"px_per_m": PPM, "chunks": chunks}
    with open(os.path.join(K.GAME_DIR, "data", "valley", "slice_ground.json"), "w") as f:
        json.dump(meta, f, indent=1)
    Image.fromarray(img).resize((w // 6, h // 6), Image.LANCZOS).save(os.path.join(K.CACHE_DIR, "slice_ground_proj.png"))
    print("chunks", len(chunks), flush=True)


if __name__ == "__main__":
    main()
