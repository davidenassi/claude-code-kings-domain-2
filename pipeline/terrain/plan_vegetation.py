"""Place the valley's vegetation and export it for Godot.

* packs tree/rock sprites into two atlases with identical layout (bodies RGBA, shadows L)
* places instances from the terrain forest-density map (species by altitude, moisture, slope)
* writes MultiMesh2D buffers per horizontal strip (rows of 32 m) -> instant loading in Godot
  buffer layout per instance (16 float32): transform 2D (8) + colour (4) + custom = atlas rect (4)

Run after build_terrain.py and blender/vegetation.py:
    python -m terrain.plan_vegetation
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from kd import const as K  # noqa: E402
from terrain import heightmap as HM  # noqa: E402
from terrain import layout as L  # noqa: E402
from terrain import noise as N  # noqa: E402
from terrain import parcels as PC  # noqa: E402

CACHE = os.path.join(K.CACHE_DIR, "terrain")
SPR = os.path.join(K.GAME_DIR, "assets", "sprites", "trees")
OUT = os.path.join(K.GAME_DIR, "assets", "vegetation")
STRIP_M = 32.0
PAD = 4


def pack_atlas(names, meta, width=4096):
    """Shelf packer. Returns {name: (x, y, w, h)}, atlas size."""
    items = sorted(names, key=lambda n: -meta[n]["size"][1])
    x = y = PAD
    row_h = 0
    rects = {}
    for n in items:
        w, h = meta[n]["size"]
        if x + w + PAD > width:
            x = PAD
            y += row_h + PAD
            row_h = 0
        rects[n] = (x, y, w, h)
        x += w + PAD
        row_h = max(row_h, h)
    height = 1 << int(math.ceil(math.log2(y + row_h + PAD)))
    return rects, (width, height)


def grade_foliage(img, conifer=False):
    """Painterly grade for vegetation: lift dark foliage, cooler teal greens (reference palette)."""
    a = np.asarray(img).astype(np.float32) / 255.0
    rgb = a[..., :3]
    lum = (rgb * np.array([0.3, 0.59, 0.11])).sum(-1, keepdims=True)
    green = np.clip((rgb[..., 1:2] - np.maximum(rgb[..., 0:1], rgb[..., 2:3])) * 6.0, 0, 1)
    lifted = rgb ** (1.0 if conifer else 1.08)
    teal = lifted * np.array([0.92, 1.0, 1.0]) + np.array([0.0, 0.0, 0.055]) * green
    l2 = (teal * np.array([0.3, 0.59, 0.11])).sum(-1, keepdims=True)
    teal = l2 + (teal - l2) * 0.86
    out = rgb * (1 - green) + teal * green
    a[..., :3] = np.clip(out, 0, 1)
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA")


BSPR = os.path.join(K.GAME_DIR, "assets", "sprites", "buildings")


def grade_rock(img):
    """Rocks read as light, warm-grey stone with lit tops (reference), not as dark mossy lumps."""
    a = np.asarray(img).astype(np.float32) / 255.0
    rgb = a[..., :3]
    lum = (rgb * np.array([0.3, 0.59, 0.11])).sum(-1, keepdims=True)
    rgb = lum + (rgb - lum) * 0.45
    rgb = np.clip(rgb * np.array([0.97, 0.955, 0.99]), 0, 1) ** 1.02
    a[..., :3] = np.clip(rgb, 0, 1)
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA")


def build_atlases():
    meta = json.load(open(os.path.join(SPR, "trees.json")))
    src = {n: SPR for n in meta}
    # small objects of the settlement (fences, props) share the atlas -> drawn by the same MultiMeshes
    bpath = os.path.join(BSPR, "buildings.json")
    if os.path.exists(bpath):
        bmeta = json.load(open(bpath))
        for n, m in bmeta.items():
            if (n.startswith("fence_") or n.startswith("prop_")) and os.path.exists(os.path.join(BSPR, n + ".png")):
                meta[n] = {"size": m["size"], "anchor": m["anchor"]}
                src[n] = BSPR
    names = sorted(meta)
    rects, (aw, ah) = pack_atlas(names, meta)
    body = Image.new("RGBA", (aw, ah), (0, 0, 0, 0))
    shadow = Image.new("L", (aw, ah), 0)
    for n in names:
        x, y, w, h = rects[n]
        img = Image.open(os.path.join(src[n], f"{n}.png")).convert("RGBA")
        if src[n] == SPR and n.startswith("rock_"):
            img = grade_rock(img)
        elif src[n] == SPR:
            img = grade_foliage(img, conifer=n.split("_")[0] in ("fir", "spruce", "pine"))
        body.paste(img, (x, y))
        shadow.paste(Image.open(os.path.join(src[n], f"{n}_sh.png")).convert("L"), (x, y))
    os.makedirs(OUT, exist_ok=True)
    body.save(os.path.join(OUT, "trees_atlas.png"), optimize=True)
    # shadow atlas as RGBA black + alpha (simple to draw in Godot)
    sh = np.zeros((ah, aw, 4), np.uint8)
    sh[..., 3] = np.asarray(shadow)
    Image.fromarray(sh, "RGBA").save(os.path.join(OUT, "trees_shadow_atlas.png"), optimize=True)
    info = {n: {"rect": rects[n], "anchor": meta[n]["anchor"]} for n in names}
    return info, (aw, ah)


def sample(grid, x, y):
    """Nearest sample of a 1 m ground map at world coords."""
    i = np.clip(np.round(x - HM.X0 - 0.5).astype(int), 0, grid.shape[1] - 1)
    j = np.clip(np.round(y - HM.Y0 - 0.5).astype(int), 0, grid.shape[0] - 1)
    return grid[j, i]


def layout_mask(shape):
    """1 where the demo settlement uses the ground (fields, roads, buildings, plazas)."""
    from PIL import ImageDraw
    path = os.path.join(K.GAME_DIR, "data", "valley", "demo_town.json")
    img = Image.new("L", (shape[1], shape[0]), 0)
    if not os.path.exists(path):
        return np.zeros(shape, bool)
    t = json.load(open(path))
    d = ImageDraw.Draw(img)
    T = lambda x, y: (x - HM.X0, y - HM.Y0)  # noqa: E731
    for f in t["fields"]:
        d.polygon([T(*p) for p in f["polygon"]], fill=255)
    for p in t["plazas"]:
        d.polygon([T(*q) for q in p["polygon"]], fill=255)
    for r in t["roads"]:
        d.line([T(*q) for q in r["points"]], fill=255, width=int(r["width"] + 5))
    for b in t["buildings"]:
        w, dd = 12, 12
        if b["type"] == "castle":
            w, dd = 48, 56
        elif b["type"] in ("farm", "stable", "sawmill", "quarry", "mine", "barracks"):
            w, dd = 28, 20
        d.rectangle([T(b["x"] - w / 2, b["y"] - dd / 2), T(b["x"] + w / 2, b["y"] + dd / 2)], fill=255)
    return np.asarray(img) > 0


def main():
    info, (aw, ah) = build_atlases()
    dens = np.load(os.path.join(CACHE, "forest_density.npy"))
    conif = np.load(os.path.join(CACHE, "forest_conifer.npy"))
    slope = np.load(os.path.join(CACHE, "slope.npy"))
    wet = np.load(os.path.join(CACHE, "wet.npy"))
    d_water = np.load(os.path.join(CACHE, "d_water.npy"))
    shadow = np.load(os.path.join(CACHE, "shadow.npy"))
    open_land = np.load(os.path.join(CACHE, "open_land.npy"))
    hz = np.load(os.path.join(CACHE, "h_final.npy"))
    rng = np.random.default_rng(42)
    lmask = layout_mask(dens.shape)

    # ---- candidates: jittered grid
    sp = 3.3
    gx, gy = np.meshgrid(np.arange(HM.X0 + sp / 2, HM.X0 + HM.W, sp), np.arange(HM.Y0 + sp / 2, HM.Y0 + HM.H, sp))
    x = (gx + rng.uniform(-0.45, 0.45, gx.shape) * sp).ravel()
    y = (gy + rng.uniform(-0.45, 0.45, gy.shape) * sp).ravel()
    d = sample(dens, x, y)
    p_accept = np.clip((d - 0.12) / 0.6, 0, 1) * 0.62
    keep = rng.random(len(x)) < p_accept
    keep &= sample(wet, x, y) < 0.5
    keep &= sample(slope, x, y) < 0.9
    x, y, d = x[keep], y[keep], d[keep]
    c = sample(conif, x, y)
    h = sample(hz, x, y)
    dw = sample(d_water, x, y)
    n = len(x)

    # ---- species
    r = rng.random(n)
    is_con = rng.random(n) < c
    species = np.empty(n, dtype=object)
    con_pool = ["fir_a", "fir_b", "fir_c", "fir_d", "spruce_a", "spruce_b", "pine_a", "pine_b"]
    con_w = np.array([0.18, 0.18, 0.12, 0.12, 0.13, 0.12, 0.08, 0.07])
    dec_pool = ["oak_a", "oak_b", "oak_c", "beech_a", "beech_b", "birch_a", "birch_b"]
    dec_w = np.array([0.18, 0.18, 0.12, 0.17, 0.15, 0.1, 0.1])
    species[is_con] = rng.choice(con_pool, is_con.sum(), p=con_w / con_w.sum())
    species[~is_con] = rng.choice(dec_pool, (~is_con).sum(), p=dec_w / dec_w.sum())
    riverside = (dw < 14) & (~is_con)
    species[riverside] = rng.choice(["poplar_a", "poplar_b", "birch_a", "bush_b", "bush_a", "oak_b"],
                                    riverside.sum(), p=[0.24, 0.2, 0.16, 0.15, 0.13, 0.12])
    edge = (d < 0.32) & (r < 0.45)
    species[edge] = rng.choice(["bush_a", "bush_b", "bush_c", "bush_d"], edge.sum())
    scale = rng.uniform(0.78, 1.12, n)
    high = np.clip((h - 430.0) / 160.0, 0, 1)
    scale *= 1.0 - 0.35 * high

    # ---- scattered meadow trees, orchards-like groups and bushes on open land (not in the town core)
    m = 900_000
    mx = rng.uniform(HM.X0, HM.X0 + HM.W, m)
    my = rng.uniform(0, HM.H + HM.Y0, m)
    cx, cy = L.TOWN_CORE["center"]
    ok = (sample(wet, mx, my) < 0.5) & (sample(slope, mx, my) < 0.5) & (sample(dens, mx, my) < 0.1)
    ok &= np.hypot(mx - cx, my - cy) > L.TOWN_CORE["radius"] - 90
    cluster = N.fbm_at(mx.astype(np.float32), my.astype(np.float32), 90.0, N.perm(77), 3, 2.0, 0.5)
    hedge = np.abs(N.fbm_at(mx.astype(np.float32), my.astype(np.float32), 220.0, N.perm(78), 3, 2.0, 0.5))
    prob = np.clip(cluster * 3.0 - 0.1, 0, 1) * 0.03 + np.clip(0.035 - hedge, 0, 1) * 0.6 + 0.002
    prob *= np.where(sample(open_land, mx, my) > 0.5, 0.45, 1.0)
    ok &= rng.random(m) < prob
    mx, my = mx[ok], my[ok]
    ms = rng.choice(["oak_a", "oak_b", "beech_a", "bush_a", "bush_c", "bush_d", "birch_b", "fruit_a"],
                    len(mx), p=[0.16, 0.14, 0.1, 0.2, 0.16, 0.12, 0.06, 0.06])

    # ---- rocks: mountains (steep, high), river gorges and a few in meadows
    k = 120_000
    rx = rng.uniform(HM.X0, HM.X0 + HM.W, k)
    ry = rng.uniform(HM.Y0, HM.Y0 + HM.H, k)
    rs_ = sample(slope, rx, ry)
    rh = sample(hz, rx, ry)
    rdw = sample(d_water, rx, ry)
    prob = np.clip((rs_ - 0.35) * 0.5, 0, 0.12) + np.where((rdw > 0.5) & (rdw < 6) & (rh > 125), 0.05, 0.0) + 0.002
    ok = (rng.random(k) < prob) & (sample(wet, rx, ry) < 0.5) & (rs_ < 1.0)
    ok &= np.hypot(rx - cx, ry - cy) > L.TOWN_CORE["radius"] + 40
    rx, ry = rx[ok], ry[ok]
    rsp = rng.choice(["rock_a", "rock_b", "rock_c", "rock_d", "rock_e", "rock_f"], len(rx),
                     p=[0.22, 0.2, 0.12, 0.26, 0.06, 0.14])

    # boulders in shallow river water and along rocky shores (rapids, gorges)
    dpath = os.path.join(CACHE, "depth.npy")
    if os.path.exists(dpath):
        depth = np.load(dpath)
        k = 160_000
        bx = rng.uniform(HM.X0, HM.X0 + HM.W, k)
        by = rng.uniform(HM.Y0, HM.Y0 + HM.H, k)
        dd = sample(depth, bx, by)
        bw = sample(wet, bx, by) > 0.5
        bh = sample(hz, bx, by)
        lake = HM.Water.lake_rnorm(bx, by) < 1.05
        ok = bw & (dd > 0.05) & (dd < 0.8) & ~lake & (rng.random(k) < np.where(bh > 125, 0.5, 0.12))
        bx, by = bx[ok], by[ok]
        rx = np.concatenate([rx, bx])
        ry = np.concatenate([ry, by])
        rsp = np.concatenate([rsp, rng.choice(["rock_a", "rock_d", "rock_f", "rock_b"], len(bx), p=[0.3, 0.35, 0.2, 0.15])])
        print("river boulders", len(bx))
        # rocky banks: clusters of stones along the river edges (more on the outer, steeper banks)
        k = 3_000_000
        bx = rng.uniform(HM.X0, HM.X0 + HM.W, k)
        by = rng.uniform(HM.Y0, HM.Y0 + HM.H, k)
        bdw = sample(d_water, bx, by)
        lake = HM.Water.lake_rnorm(bx, by) < 1.1
        clus = N.fbm_at(bx.astype(np.float32), by.astype(np.float32), 30.0, N.perm(81), 2, 2.0, 0.5)
        pb = np.where((bdw > 0.3) & (bdw < 2.8), 0.12, 0.0) * np.clip(clus * 3.0 + 0.3, 0, 1)
        pb *= np.where(lake, 0.35, 1.0) * (1.0 + np.clip(sample(slope, bx, by) * 3.0, 0, 2))
        ok = (rng.random(k) < pb) & (sample(wet, bx, by) < 0.5) & (sample(hz, bx, by) < 400)
        ok &= np.hypot(bx - 1861, by - 962) > 30
        ok &= np.hypot(bx - 1458, by - 1004) > 22
        bx, by = bx[ok], by[ok]
        rx = np.concatenate([rx, bx])
        ry = np.concatenate([ry, by])
        rsp = np.concatenate([rsp, rng.choice(["rock_a", "rock_b", "rock_d", "rock_f", "rock_c"], len(bx),
                                              p=[0.25, 0.2, 0.3, 0.15, 0.1])])
        print("bank rocks", len(bx))
        # boulders framing the waterfalls and cascades (steep wet channels)
        from scipy import ndimage as ndi
        steep_wet = (wet > 0.5) & (slope > 0.42)
        near_fall = ndi.binary_dilation(steep_wet, iterations=7) & (wet < 0.5)
        fy, fx = np.nonzero(near_fall)
        pick = rng.random(len(fx)) < 0.05
        fx = fx[pick] + HM.X0 + rng.uniform(0, 1, pick.sum())
        fy = fy[pick] + HM.Y0 + rng.uniform(0, 1, pick.sum())
        rx = np.concatenate([rx, fx])
        ry = np.concatenate([ry, fy])
        rsp = np.concatenate([rsp, rng.choice(["rock_a", "rock_b", "rock_c", "rock_d", "rock_e", "rock_f"], len(fx))])
        print("waterfall rocks", len(fx))

    # ---- hedgerows along a share of the pasture parcel boundaries (bocage countryside)
    P = PC.load()
    k = 1_600_000
    hx = rng.uniform(HM.X0, HM.X0 + HM.W, k)
    hy = rng.uniform(HM.Y0, HM.Y0 + HM.H, k)
    pj = np.clip(((hy - HM.Y0) / PC.STEP).astype(int), 0, P["edge"].shape[0] - 1)
    pi = np.clip(((hx - HM.X0) / PC.STEP).astype(int), 0, P["edge"].shape[1] - 1)
    e = P["edge"][pj, pi]
    ph = PC.pair_hash(P["id1"][pj, pi], P["id2"][pj, pi])
    gaps = N.fbm_at(hx.astype(np.float32), hy.astype(np.float32), 22.0, N.perm(79), 2, 2.0, 0.5)
    ok = (e < 1.1) & (ph < 0.4) & (gaps > -0.22)
    ok &= (sample(dens, hx, hy) < 0.2) & (sample(slope, hx, hy) < 0.3) & (sample(wet, hx, hy) < 0.5)
    ok &= (sample(hz, hx, hy) < 175.0) & (np.hypot(hx - 1660, hy - 858) > 150)
    hx, hy = hx[ok], hy[ok]
    hs = rng.choice(["bush_a", "bush_b", "bush_c", "bush_d", "oak_b", "oak_a", "beech_a", "birch_a", "poplar_a"],
                    len(hx), p=[0.2, 0.17, 0.17, 0.14, 0.1, 0.07, 0.06, 0.05, 0.04])
    print("hedgerow plants", len(hx))

    # ---- the Rocca (castle hill): wooded, rocky flanks below the castle
    k = 40_000
    qx = rng.uniform(1520, 1740, k)
    qy = rng.uniform(900, 1080, k)
    qs = sample(slope, qx, qy)
    on_hill = np.hypot(qx - 1630, (qy - 980) * 1.1) < 100
    off_castle = (np.abs(qx - 1652) > 24) | (np.abs(qy - 962) > 27)
    dry = (sample(wet, qx, qy) < 0.5) & (sample(d_water, qx, qy) > 2.0)
    t_ok = on_hill & off_castle & dry & (qs > 0.12) & (qs < 1.0) & (rng.random(k) < np.where(qs > 0.25, 0.09, 0.04))
    r_ok = on_hill & off_castle & dry & (qs > 0.38) & (rng.random(k) < 0.07)
    tx_, ty_ = qx[t_ok], qy[t_ok]
    ts_ = rng.choice(["oak_a", "oak_b", "beech_a", "pine_a", "pine_b", "bush_a", "bush_c", "bush_d", "birch_a"],
                     len(tx_), p=[0.14, 0.14, 0.12, 0.14, 0.1, 0.12, 0.1, 0.08, 0.06])
    rx2, ry2 = qx[r_ok], qy[r_ok]
    rs2 = rng.choice(["rock_a", "rock_b", "rock_c", "rock_d", "rock_e", "rock_f"], len(rx2))
    print("rocca trees", len(tx_), "rocks", len(rx2))

    X = np.concatenate([x, mx, rx, hx, tx_, rx2])
    Y = np.concatenate([y, my, ry, hy, ty_, ry2])
    S = np.concatenate([species, ms, rsp, hs, ts_, rs2])
    SC = np.concatenate([scale, rng.uniform(0.8, 1.1, len(mx)), rng.uniform(0.7, 1.3, len(rx)),
                         rng.uniform(0.75, 1.05, len(hx)), rng.uniform(0.8, 1.1, len(tx_)),
                         rng.uniform(1.0, 1.8, len(rx2))])
    keep = ~sample(lmask, X, Y)
    X, Y, S, SC = X[keep], Y[keep], S[keep], SC[keep]
    # hand-placed vegetation of the settlement (orchards, hedges, garden and roadside trees)
    tpath = os.path.join(K.GAME_DIR, "data", "valley", "demo_town.json")
    if os.path.exists(tpath):
        dv = json.load(open(tpath)).get("veg", [])
        if dv:
            X = np.concatenate([X, [v["x"] for v in dv]])
            Y = np.concatenate([Y, [v["y"] for v in dv]])
            S = np.concatenate([S, np.array([v["type"] for v in dv], dtype=object)])
            SC = np.concatenate([SC, [v.get("scale", 1.0) for v in dv]])
            print("settlement vegetation", len(dv))
    Z = sample(hz, X, Y)
    if os.path.exists(dpath):
        Z = Z + sample(np.load(dpath), X, Y) * 0.85     # boulders in streams sit at the water surface
    SH = sample(shadow, X, Y)
    print(f"instances: forest {n}, meadow {len(mx)}, rocks {len(rx)}, total {len(X)}")

    # ---- buffers per strip
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.startswith("strip_"):
            os.remove(os.path.join(OUT, f))
    ppm = K.PX_PER_M
    gpx_x = X * ppm
    gpx_y = Y * K.SIN_EL * ppm                       # ground position (sort key)
    alt = -Z * K.COS_EL * ppm
    strip = np.floor((Y - HM.Y0) / STRIP_M).astype(int)
    tint_v = rng.uniform(0.9, 1.08, len(X))
    light = 0.58 + 0.42 * SH                         # inside mountain shadows trees are darker
    strips_meta = []
    for s_id in np.unique(strip):
        idx = np.nonzero(strip == s_id)[0]
        idx = idx[np.argsort(Y[idx])]
        y0 = HM.Y0 + s_id * STRIP_M
        node_y = y0 * K.SIN_EL * ppm
        buf = np.zeros((len(idx), 16), np.float32)
        for row, i in enumerate(idx):
            nm = S[i]
            rx_, ry_, rw, rh_ = info[nm]["rect"]
            ax, ay = info[nm]["anchor"]
            sc = SC[i]
            w, hh = rw * sc, rh_ * sc
            ox = gpx_x[i] - ax * sc
            oy = gpx_y[i] + alt[i] - ay * sc - node_y
            buf[row, 0:8] = (w, 0, 0, ox, 0, hh, 0, oy)
            t = tint_v[i] * light[i]
            buf[row, 8:12] = (t, t, t * 0.98, 1.0)
            buf[row, 12:16] = (rx_ / aw, ry_ / ah, rw / aw, rh_ / ah)
        fn = f"strip_{s_id:03d}.bin"
        buf.tofile(os.path.join(OUT, fn))
        strips_meta.append({"file": fn, "count": int(len(idx)), "node_y": float(node_y),
                            "y0_m": float(y0)})
    meta = {"atlas": "trees_atlas.png", "shadow_atlas": "trees_shadow_atlas.png", "atlas_size": [aw, ah],
            "strip_m": STRIP_M, "strips": strips_meta, "sprites": info, "total": int(len(X))}
    with open(os.path.join(K.GAME_DIR, "data", "valley", "vegetation.json"), "w") as f:
        json.dump(meta, f, indent=1)
    print("strips", len(strips_meta))


if __name__ == "__main__":
    main()
