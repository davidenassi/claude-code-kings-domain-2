"""Ground materials of the valley: weights + albedo (linear RGB) in ground space (1 m cells).

Palette tuned against the reference image: warm yellow-green grass, olive meadows, deep green
forest floor, warm grey-beige rock with cool shadows, bright snow, tan earth.
"""
from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from terrain import layout as L
from terrain import noise as N
from terrain import parcels as PC
from terrain.heightmap import X0, Y0, smoothstep


def srgb(c):
    return (np.asarray(c, np.float32) / 255.0) ** 2.2


PAL = {
    "grass": srgb((90, 94, 46)),
    "grass_lush": srgb((64, 80, 40)),
    "grass_dry": srgb((118, 106, 56)),
    "meadow": srgb((96, 96, 48)),
    "flowers": srgb((140, 128, 64)),
    "alpine": srgb((112, 106, 66)),
    "forest": srgb((44, 52, 34)),
    "forest_needles": srgb((60, 54, 38)),
    "dirt": srgb((128, 102, 68)),
    "mud": srgb((80, 68, 50)),
    "sand": srgb((168, 152, 116)),
    "gravel": srgb((128, 122, 112)),
    "bed": srgb((104, 92, 70)),
    "rock_warm": srgb((130, 120, 104)),
    "rock_cool": srgb((100, 102, 108)),
    "rock_dark": srgb((58, 56, 58)),
    "snow": srgb((232, 236, 244)),
    "snow_shadow": srgb((206, 216, 236)),
}


def poly_mask(polys, shape, cell=1.0):
    img = Image.new("L", (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(img)
    for poly in polys:
        d.polygon([((px - X0) / cell, (py - Y0) / cell) for px, py in poly], fill=255)
    return np.array(img, np.float32) / 255.0


def soft_poly(polys, shape, g, edge=40.0, cell=1.0, seed=0, warp=30.0):
    m = poly_mask(polys, shape, cell) > 0.5
    din = ndimage.distance_transform_edt(m) * cell - ndimage.distance_transform_edt(~m) * cell
    din = din + N.fbm(g, 90.0, 300 + seed, 4) * warp
    return smoothstep(-edge * 0.5, edge * 0.5, din).astype(np.float32)


def forest_density(t, slope, wet, d_water, g):
    """0..1 tree density. Also returns a conifer share map (0 deciduous .. 1 conifer)."""
    h, E, xs, ys = t["h"], t["E"], t["xs"], t["ys"]
    shape = h.shape
    n1 = N.fbm(g, 260.0, 401, 5) * 0.5 + 0.5
    n2 = N.fbm(g, 60.0, 402, 3) * 0.5 + 0.5
    # natural forests: foothills and lower mountain slopes, below the tree line
    treeline = 480.0 + N.fbm(g, 300.0, 403, 3) * 60.0
    mountain_f = smoothstep(0.03, 0.18, E) * smoothstep(treeline, treeline - 90.0, h)
    mountain_f *= smoothstep(0.85, 0.55, slope)                 # no trees on cliffs
    mountain_f *= 0.55 + 0.6 * n1
    # on the high slopes trees grow in stands (hollows, benches), leaving bare rock between them
    stands = N.fbm(g, 110.0, 412, 4) * 0.5 + 0.5
    high = smoothstep(230.0, 380.0, h)
    mountain_f *= 1.0 - high * (1.0 - smoothstep(0.45, 0.62, stands))
    patches = soft_poly(L.FOREST_PATCHES, shape, g, edge=70.0, seed=1, warp=60.0)
    # natural groves and copses all over the valley floor (many sizes), thinner towards the centre
    groves = N.fbm(g, 150.0, 409, 4) * 0.5 + 0.5
    copses = N.fbm(g, 45.0, 410, 3) * 0.5 + 0.5
    grove_f = smoothstep(0.555, 0.62, groves) * (0.6 + 0.6 * n2) + smoothstep(0.585, 0.64, copses) * 0.75
    clearings = smoothstep(0.56, 0.62, N.fbm(g, 70.0, 411, 3) * 0.5 + 0.5)
    floor_f = np.maximum(patches * (0.65 + 0.5 * n2) * (1 - 0.85 * clearings), grove_f * (E < 0.05))
    dens = np.maximum(mountain_f, floor_f)
    # river galleries: riparian trees along the banks
    gallery = smoothstep(26.0, 6.0, d_water) * smoothstep(1.0, 3.0, d_water) * (0.45 + 0.6 * n2)
    gallery *= (E < 0.2)
    dens = np.maximum(dens, gallery * 0.75)
    # keep settlement land open
    open_land = soft_poly(L.OPEN_LAND, shape, g, edge=60.0, seed=2, warp=40.0)
    cx, cy = L.TOWN_CORE["center"]
    town = smoothstep(L.TOWN_CORE["radius"] + 60.0, L.TOWN_CORE["radius"] - 30.0,
                      np.hypot(xs - cx, ys - cy) + N.fbm(g, 80.0, 404, 3) * 50.0)
    dens *= (1 - np.maximum(open_land, town))
    # copses and small woods remain scattered in the farmland (the countryside is not a bare lawn)
    dens = np.maximum(dens, grove_f * open_land * (1 - town) * 0.75 * (E < 0.05))
    dens *= (1 - wet)
    dens = np.clip(dens, 0.0, 1.0) * smoothstep(0.0, 2.0, d_water)
    # lowland forests are mixed (pine / fir stands among oaks and beeches), conifers dominate higher up
    mix_n = N.fbm(g, 400.0, 405, 3) * 0.6 + N.fbm(g, 90.0, 406, 2) * 0.35
    conifer = np.clip(0.38 + smoothstep(110.0, 200.0, h) * 0.6 + E * 0.6 + mix_n - gallery * 0.9, 0.0, 1.0)
    return dens.astype(np.float32), conifer.astype(np.float32), np.maximum(open_land, town)


def build(t, nrm, wet, depth, d_water, g):
    """Return (albedo_lin HxWx3, weights HxWx4 [rock, soil, snow, forest], forest maps)."""
    h, E, xs, ys = t["h"], t["E"], t["xs"], t["ys"]
    nx_, ny_, nz_ = nrm
    slope = np.arccos(np.clip(nz_, 0, 1))                     # radians
    n_big = N.fbm(g, 420.0, 501, 4)
    n_mid = N.fbm(g, 70.0, 502, 4)
    n_small = N.fbm(g, 14.0, 503, 3)
    acc = t.get("acc")

    # ---------------- vegetation / soil on gentle ground ----------------
    moist = smoothstep(80.0, 4.0, d_water)
    alb = np.empty(h.shape + (3,), np.float32)
    k_dry = np.clip(0.30 + n_big * 1.2 - moist * 0.6 + smoothstep(0.15, 0.4, slope) * 0.15, 0, 1)
    base = PAL["grass"][None, None] * (1 - k_dry[..., None]) + PAL["grass_dry"][None, None] * k_dry[..., None]
    k_lush = np.clip(moist * 0.8 + n_mid * 0.5, 0, 1)[..., None]
    base = base * (1 - k_lush * 0.6) + PAL["grass_lush"][None, None] * k_lush * 0.6
    k_meadow = np.clip((n_mid + 0.15) * 1.6, 0, 1)[..., None] * 0.5
    base = base * (1 - k_meadow) + PAL["meadow"][None, None] * k_meadow
    # mid-scale meadow mottling (patches of lusher / drier grass, clover, flowers) - painterly variation
    n_patch = N.fbm(g, 26.0, 506, 3) + N.fbm(g, 9.0, 507, 2) * 0.5
    k_p1 = np.clip(n_patch * 3.0, 0, 1)[..., None] * 0.45
    k_p2 = np.clip(-n_patch * 3.0, 0, 1)[..., None] * 0.35
    base = base * (1 - k_p1) + PAL["grass_lush"][None, None] * k_p1
    base = base * (1 - k_p2) + PAL["grass_dry"][None, None] * k_p2
    # pasture parcels: an irregular patchwork of meadows (different grass, some mown in stripes)
    P = PC.load()
    ny_, nx_ = h.shape
    up = lambda a: np.repeat(np.repeat(a, 2, 0), 2, 1)[:ny_, :nx_]  # noqa: E731
    id1, id2, edge = up(P["id1"]), up(P["id2"]), up(P["edge"])
    tones = np.array([srgb(c) for c in [(60, 80, 38), (98, 108, 48), (92, 98, 46), (130, 116, 60), (76, 86, 44),
                                         (112, 106, 54)]], np.float32)
    cum = np.cumsum([0.2, 0.22, 0.2, 0.14, 0.14, 0.1])
    n_ids = int(P["n"])
    tid = np.searchsorted(cum, PC.id_hash(np.arange(n_ids), 1) * cum[-1])
    tid = np.clip(tid, 0, len(tones) - 1)
    t1, t2 = tones[tid[id1]], tones[tid[id2]]
    wb = smoothstep(0.0, 4.0, edge)[..., None]
    pc = t1 * (0.5 + 0.5 * wb) + t2 * (0.5 - 0.5 * wb)
    ids = np.arange(n_ids)
    striped = (PC.id_hash(ids, 2) < 0.35)[id1]
    ang = (PC.id_hash(ids, 3) * np.pi)[id1]
    per = (5.0 + 4.0 * PC.id_hash(ids, 4))[id1]
    stripe = np.sin((xs * np.cos(ang) + ys * np.sin(ang)) * (2 * np.pi) / per)
    pc = pc * (1.0 + 0.08 * stripe * striped)[..., None]
    pc = pc * (1.0 + n_small * 0.08)[..., None]
    pc = pc * (0.80 + 0.20 * smoothstep(0.3, 1.4, edge))[..., None]       # darker grass lines on the borders
    floor = smoothstep(0.06, 0.015, E) * smoothstep(1.0, 0.35, moist) * smoothstep(0.30, 0.12, slope)
    kp = (floor * 0.68)[..., None]
    base = base * (1 - kp) + pc * kp
    del id1, id2, edge, t1, t2, pc, striped, ang, per, stripe
    flowers = np.clip((N.fbm(g, 6.0, 508, 2) - 0.25) * 4.0, 0, 1) * np.clip(n_big + 0.3, 0, 1) * (E < 0.3)
    base = base * (1 - flowers[..., None] * 0.25) + PAL["flowers"][None, None] * flowers[..., None] * 0.25
    # alpine meadow on mountains
    k_alp = (smoothstep(0.15, 0.5, E) * smoothstep(260.0, 420.0, h))[..., None]
    base = base * (1 - k_alp) + PAL["alpine"][None, None] * k_alp
    alb[:] = base

    # bare soil: dirt patches, mud near water, sand/gravel bars
    above = t["above_water"]
    k_mud = smoothstep(4.0, 0.5, d_water) * smoothstep(1.5, 0.3, above) * (1 - wet)
    k_sand = smoothstep(0.9, 0.15, above) * smoothstep(6.0, 0.0, d_water) * (1 - wet) \
        * np.clip(0.4 + n_mid * 1.5, 0, 1)
    k_dirt = np.clip((n_mid * 0.7 + n_small * 0.5 - 0.35) * 2.0, 0, 1) * 0.35 * (E < 0.2)
    k_scree = smoothstep(0.55, 0.8, slope) * smoothstep(300.0, 480.0, h) * np.clip(0.4 + n_big, 0, 1) * 0.7
    if acc is not None:
        gully = smoothstep(4e4, 4e5, acc) * smoothstep(0.1, 0.4, E) * smoothstep(250.0, 400.0, h)
        k_scree = np.maximum(k_scree, gully * 0.6)
    soil = np.clip(k_mud + k_sand + k_dirt + k_scree, 0, 1)
    soil_col = (PAL["mud"][None, None] * k_mud[..., None] + PAL["sand"][None, None] * k_sand[..., None]
                + PAL["dirt"][None, None] * k_dirt[..., None] + PAL["gravel"][None, None] * k_scree[..., None])
    soil_col = soil_col / np.maximum(k_mud + k_sand + k_dirt + k_scree, 1e-4)[..., None]
    alb = alb * (1 - soil[..., None]) + soil_col * soil[..., None]

    # forest floor
    dens, conifer, open_land = forest_density(t, slope, wet, d_water, g)
    k_for = smoothstep(0.1, 0.42, dens)
    fcol = PAL["forest"][None, None] * (1 - conifer[..., None] * 0.5) \
        + PAL["forest_needles"][None, None] * conifer[..., None] * 0.5
    alb = alb * (1 - k_for[..., None]) + fcol * k_for[..., None]

    # ---------------- rock ----------------
    # rock threshold falls with altitude: vegetated foothills, bare rock high up
    alt = smoothstep(220.0, 560.0, h + n_big * 80.0)
    rock_slope = 0.78 - 0.28 * alt + n_mid * 0.18
    rock_slope = rock_slope + t["cavity_neg"] * 0.06            # crests rockier, hollows greener
    k_rock = smoothstep(rock_slope - 0.18, rock_slope + 0.14, slope)
    k_rock = np.maximum(k_rock, smoothstep(0.35, 0.7, E) * smoothstep(560.0, 680.0, h + n_mid * 120.0))
    k_rock = np.maximum(k_rock, smoothstep(0.12, 0.35, -t["cavity_neg"]) * 0.0)
    warm = np.clip(0.5 + n_big * 1.2 + n_small * 0.4, 0, 1)[..., None]
    rcol = PAL["rock_warm"][None, None] * warm + PAL["rock_cool"][None, None] * (1 - warm)
    dark = np.clip(-n_small * 1.4, 0, 1)[..., None] * 0.6
    rcol = rcol * (1 - dark) + PAL["rock_dark"][None, None] * dark
    alb = alb * (1 - k_rock[..., None]) + rcol * k_rock[..., None]

    # ---------------- snow ----------------
    snowline = 415.0 + n_big * 60.0 + n_mid * 30.0
    k_snow = smoothstep(snowline, snowline + 60.0, h) * smoothstep(1.2, 0.8, slope)
    # snow lingers in gullies a bit lower
    k_snow = np.maximum(k_snow, smoothstep(snowline - 120.0, snowline, h) * smoothstep(0.6, 2.0, -t["cavity_neg"])
                        * smoothstep(1.1, 0.6, slope))
    k_snow = np.clip(k_snow * (0.85 + 0.3 * n_small), 0, 1)
    scol = PAL["snow"][None, None] * np.ones_like(alb)
    alb = alb * (1 - k_snow[..., None]) + scol * k_snow[..., None]

    # riverbed / lake bed under water
    k_bed = wet * smoothstep(0.0, 0.6, depth)
    alb = alb * (1 - k_bed[..., None]) + PAL["bed"][None, None] * k_bed[..., None]

    weights = np.stack([k_rock * (1 - k_snow), soil * (1 - k_rock) * (1 - k_snow), k_snow,
                        k_for * (1 - k_rock) * (1 - k_snow)], -1).astype(np.float32)
    return alb.astype(np.float32), weights, {"density": dens, "conifer": conifer, "open": open_land,
                                             "slope": slope.astype(np.float32)}
