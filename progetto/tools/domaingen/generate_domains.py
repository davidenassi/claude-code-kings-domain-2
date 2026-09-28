"""King's Domain — homeland generator (Rebirth, Phase 2).

Builds the finite, high-resolution valleys of data/domains/homelands.json into data/domains/<id>/:
  domain_meta.json   sizes, raster table (same schema as data/world/world_meta.json), rivers, lakes, passes,
                     deposits, the founding site, the names of the land
  height.bin         float32, 8 m cells       biome.bin, canopy.bin, forest.bin, moisture.bin, temperature.bin: uint8, 8 m
  water.bin          uint8, 4 m (0 land, 2 lake, 3 river)      coast.bin: uint8, 4 m (127.5 + metres to the lake shore / 16)
Deterministic (fixed seed per homeland): the output is official data, like the continent.

Run: python3 tools/domaingen/generate_domains.py [--only valverde] [--preview]
"""
import argparse
import json
import math
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "worldgen"))

from kdnoise import Perlin, fbm, ridged, smoothstep  # noqa: E402
from kdio import write_json, write_png, write_raster  # noqa: E402
from grids import box_blur  # noqa: E402

GENERATOR_VERSION = 1
CELL = 8.0    # height, biome, canopy, moisture, temperature
FINE = 4.0    # water, coast
BIOME = {"lake": 1, "grassland": 3, "floodplain": 4, "deciduous": 5, "mixed": 6, "taiga": 7, "hills": 8,
         "mountain": 9, "snow": 10, "marsh": 11}


# --- geometry helpers ---------------------------------------------------------------------------------

def catmull_rom(points, samples_per_seg=24):
    pts = [np.array(p, dtype=np.float64) for p in points]
    pts = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for s in range(samples_per_seg):
            t = s / samples_per_seg
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-2])
    return np.array(out)


def resample(poly, step):
    seg = np.linalg.norm(np.diff(poly, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    n = max(int(s[-1] / step), 2)
    t = np.linspace(0.0, s[-1], n + 1)
    return np.stack([np.interp(t, s, poly[:, 0]), np.interp(t, s, poly[:, 1])], axis=1), s[-1]


def meander(poly, amp, seed):
    """Pushes a smooth course sideways with a slow noise: a river bends, it does not follow a spline."""
    if amp <= 0:
        return poly
    p = Perlin(seed)
    d = np.gradient(poly, axis=0)
    d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-6)
    normal = np.stack([-d[:, 1], d[:, 0]], axis=1)
    s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(poly, axis=0), axis=1))])
    off = (p.noise(s / 420.0, 0.37) * 1.3 + p.noise(s / 140.0, 5.1) * 0.45) * amp
    # the ends stay where the passes are
    fade = np.clip(s / 300.0, 0, 1) * np.clip((s[-1] - s) / 300.0, 0, 1)
    return poly + normal * (off * fade)[:, None]


def dist_to_polyline(xs, ys, poly, reach):
    """Distance field to a polyline and the arc position of the nearest point, only within `reach` metres."""
    shape = xs.shape
    best = np.full(shape, np.inf)
    along = np.zeros(shape)
    s0 = 0.0
    for i in range(len(poly) - 1):
        a = poly[i]
        b = poly[i + 1]
        ab = b - a
        L2 = float(ab @ ab)
        L = math.sqrt(L2)
        x0, x1 = min(a[0], b[0]) - reach, max(a[0], b[0]) + reach
        y0, y1 = min(a[1], b[1]) - reach, max(a[1], b[1]) + reach
        m = (xs >= x0) & (xs <= x1) & (ys >= y0) & (ys <= y1)
        if m.any():
            px = xs[m] - a[0]
            py = ys[m] - a[1]
            t = np.clip((px * ab[0] + py * ab[1]) / max(L2, 1e-9), 0.0, 1.0)
            d = np.hypot(px - ab[0] * t, py - ab[1] * t)
            cur = best[m]
            better = d < cur
            cur[better] = d[better]
            best[m] = cur
            al = along[m]
            al[better] = s0 + t[better] * L
            along[m] = al
        s0 += L
    return best, along


def grid(size, cell):
    w = int(round(size[0] / cell))
    h = int(round(size[1] / cell))
    xs = (np.arange(w) + 0.5) * cell
    ys = (np.arange(h) + 0.5) * cell
    X, Y = np.meshgrid(xs, ys)
    return X, Y, w, h


def ellipse_mask(X, Y, lake, noise, amp):
    c = np.array(lake["center"], dtype=np.float64)
    rx, ry = lake["radii"]
    a = math.radians(lake.get("angle_deg", 0.0))
    dx = X - c[0]
    dy = Y - c[1]
    u = (dx * math.cos(a) + dy * math.sin(a)) / rx
    v = (-dx * math.sin(a) + dy * math.cos(a)) / ry
    r = np.sqrt(u * u + v * v)
    wobble = noise.noise(X / 260.0 + 3.1, Y / 260.0 - 1.7) * amp / max(rx, ry)
    return r - 1.0 - wobble   # < 0 inside


# --- the valley ------------------------------------------------------------------------------------------

def build(defn, preview=False):
    t0 = time.time()
    size = defn["size"]
    seed = int(defn["seed"])
    floor_m = float(defn["floor_m"])
    X, Y, W, H = grid(size, CELL)
    P = [Perlin(seed + k) for k in range(12)]

    # the shape of the valley: a rounded floor (a superellipse whose edge wanders) ringed by mountains.
    # mr < 0 on the floor, 0 at its edge, ~1 on the crest of the rim (distance measured in units of `rise_m`)
    rim = defn["rim"]
    cx, cy = size[0] * 0.5, size[1] * 0.5
    ax = size[0] * 0.5 * float(rim.get("floor_x", 0.74))
    ay = size[1] * 0.5 * float(rim.get("floor_y", 0.68))
    u = np.abs(X - cx) / ax
    v = np.abs(Y - cy) / ay
    pexp = 2.6
    r = (u ** pexp + v ** pexp) ** (1.0 / pexp)
    r = r - 0.11 * fbm(P[0], X / 2300.0, Y / 2300.0, octaves=3) - 0.03 * fbm(P[5], X / 700.0, Y / 700.0, octaves=2)
    rise = float(rim["rise_m"])
    mr = (r - 1.0) * min(ax, ay) / rise
    m = np.clip(mr, 0.0, 1.4)

    # the courses of the rivers (the gorges of the river passes follow them)
    courses = {}
    for rv in defn.get("rivers", []):
        course = catmull_rom(rv["points"], 30)
        course, _ = resample(course, 8.0)
        course = meander(course, rv.get("meander_m", 0.0), seed + 100 + rv["id"])
        courses[rv["id"]] = resample(course, 10.0)

    # the passes: gaps in the rim, a floor that climbs gently to the saddle
    pass_f = np.zeros_like(X)
    pass_floor = np.zeros_like(X)
    for ps in defn["passes"]:
        e = np.array(ps["edge"], dtype=np.float64)
        i = np.array(ps["inner"], dtype=np.float64)
        dirv = (e - i) / np.linalg.norm(e - i)
        poly = None
        if ps.get("kind") == "river":
            # a river pass is the river's own gorge: the stretch of the course between the pass and the edge
            for cid, (course, _) in courses.items():
                de = np.linalg.norm(course - e, axis=1)
                if de.min() < 400.0:
                    di = np.linalg.norm(course - i, axis=1)
                    a0, a1 = int(np.argmin(di)), int(np.argmin(de))
                    part = course[min(a0, a1):max(a0, a1) + 1]
                    if a0 > a1:
                        part = part[::-1]
                    if len(part) >= 2:
                        poly = np.vstack([part, part[-1] + dirv * 200.0])
                    break
        if poly is None:
            # the way through bends: a pass follows the weak line of the mountain, not a ruler
            side = np.array([-dirv[1], dirv[0]])
            bend = side * ps["width_m"] * (0.8 if sum(ord(ch) for ch in ps["id"]) % 2 == 0 else -0.8)
            poly = catmull_rom([i, i + (e - i) * 0.45 + bend, e + dirv * 200.0], 20)
        poly, L = resample(poly, 20.0)
        d, al = dist_to_polyline(X, Y, poly, ps["width_m"] * 2.5)
        # the gap narrows towards the saddle, as a real pass does
        wide = ps["width_m"] * (0.62 - 0.30 * np.clip(al / L, 0, 1))
        f = np.exp(-(d / wide) ** 2)
        climb = np.clip(al / L, 0, 1) ** 1.6
        target = floor_m + (ps["saddle_m"] - floor_m) * climb
        better = f > pass_f
        pass_f = np.where(better, f, pass_f)
        pass_floor = np.where(better, target, pass_floor)

    peak_lo, peak_hi = rim["peak_m"]
    crest = ridged(P[1], X / 1700.0, Y / 1700.0, octaves=5)
    spurs = ridged(P[2], X / 620.0, Y / 620.0, octaves=4)
    peaks = peak_lo + (peak_hi - peak_lo) * np.clip(crest * 1.25, 0, 1)
    up = smoothstep(0.0, 1.0, np.clip(m, 0, 1)) ** 1.25
    mountain = (peaks - floor_m) * up + (spurs - 0.35) * 380.0 * smoothstep(0.15, 0.9, m)
    # foothills where the rim begins: rolling ground, not a wall
    foot = smoothstep(-0.55, 0.05, mr) * (1.0 - smoothstep(0.05, 0.6, mr))
    mountain += foot * (45.0 + 85.0 * (fbm(P[3], X / 900.0, Y / 900.0, octaves=4) * 0.5 + 0.5))

    # the floor of the valley: gentle swells and the designed hills
    floor = floor_m + 18.0 * fbm(P[4], X / 1800.0, Y / 1800.0, octaves=4) + 6.0 * fbm(P[5], X / 350.0, Y / 350.0, octaves=3)
    for hl in defn.get("hills", []):
        c = hl["center"]
        rr = np.hypot(X - c[0], Y - c[1]) / hl["radius_m"]
        shape = np.exp(-(rr ** 2) * 2.2) * (0.75 + 0.5 * (fbm(P[6], X / 500.0, Y / 500.0, octaves=3) * 0.5 + 0.5))
        floor += shape * hl["height_m"]
    # the passes cut the rim down to their saddles
    height = floor + mountain * (1.0 - 0.96 * pass_f) + pass_f * np.maximum(pass_floor - floor_m, 0.0) * smoothstep(0.0, 0.6, m)

    # rivers: courses, widths, and the floor they wear into the valley
    rivers = []
    river_d = np.full_like(X, np.inf)
    river_level_near = np.full_like(X, np.inf)
    for rv in defn.get("rivers", []):
        course, length = courses[rv["id"]]
        w0, w1 = rv["width"]
        s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(course, axis=0), axis=1))])
        widths = w0 + (w1 - w0) * (s / max(length, 1.0))
        d, al = dist_to_polyline(X, Y, course, 500.0)
        # the water runs down: from the height where it enters to a little below the floor where it leaves
        start_h = float(floor_m + 30.0) if rv["id"] == 0 else float(floor_m + 45.0)
        end_h = float(floor_m - 25.0) if rv["id"] == 0 else float(floor_m - 8.0)
        level = start_h + (end_h - start_h) * np.clip(al / max(length, 1.0), 0, 1)
        closer = d < river_d
        river_d = np.where(closer, d, river_d)
        river_level_near = np.where(closer, level, river_level_near)
        rivers.append({"id": rv["id"], "name": rv["name"], "points": course, "widths": widths, "length": length})
    # the valley floor slopes gently down to the water; the channel sits below its banks
    band = 320.0
    pull = np.exp(-(river_d / band) ** 2)
    in_valley = (mr < 0.35) | (pass_f > 0.3)
    finite = np.isfinite(river_d)
    lvl = np.where(finite, river_level_near, height)
    target = lvl + np.clip(np.where(finite, river_d, band) / band, 0, 1) ** 1.4 * (height - lvl)
    height = np.where(in_valley & finite, height * (1 - pull) + np.minimum(height, target) * pull, height)
    height = np.where(river_d < 30.0, np.minimum(height, lvl - 2.0), height)

    # the lake: a hollow with a flat surface
    lakes_meta = []
    lake_sdf8 = np.full_like(X, 10.0)
    for lk in defn.get("lakes", []):
        sdf = ellipse_mask(X, Y, lk, P[7], 70.0)
        level = float(np.percentile(height[sdf < 0.3], 20)) - 4.0 if (sdf < 0.3).any() else floor_m
        inside = sdf < 0
        bank = smoothstep(0.0, 0.7, sdf)
        height = np.where(sdf < 0.7, np.minimum(height, level + 2.0 + bank * np.maximum(height - level - 2.0, 0.0)), height)
        height = np.where(inside, level - lk.get("depth_m", 10.0) * np.clip(-sdf / 0.5, 0, 1), height)
        lake_sdf8 = np.minimum(lake_sdf8, sdf)
        lakes_meta.append({"name": lk["name"], "center": lk["center"], "radii": lk["radii"],
                           "angle_deg": lk.get("angle_deg", 0.0), "level_m": round(level, 1)})

    height = box_blur(height, 1, 1)   # no stair of cells in the relief
    slope = np.hypot(*np.gradient(height, CELL))

    # --- water at 4 m -----------------------------------------------------------------------------------
    XF, YF, WF, HF = grid(size, FINE)
    water = np.zeros((HF, WF), dtype=np.uint8)
    lake_f = np.full((HF, WF), 10.0)
    for lk in defn.get("lakes", []):
        lake_f = np.minimum(lake_f, ellipse_mask(XF, YF, lk, P[7], 70.0))
    water[lake_f < 0] = 2
    for rv in rivers:
        d, al = dist_to_polyline(XF, YF, rv["points"], 40.0)
        s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(rv["points"], axis=0), axis=1))])
        half = np.interp(al, s, rv["widths"]) * 0.5
        water[(d < half) & (water == 0)] = 3
    # the shore of the lake in metres (land positive), coded as the continent codes its coast: 127.5 + m/16
    rx = max(lk["radii"][0] for lk in defn.get("lakes", [{"radii": [1, 1]}]))
    shore_m = lake_f * rx   # approximate metres from the shore (the lake's own scale)
    coast = np.clip(127.5 + shore_m / 16.0, 0, 255).astype(np.uint8)

    # --- climate, woods and biomes at 8 m ---------------------------------------------------------------
    water_d = np.minimum(river_d, np.maximum(lake_sdf8 * 400.0, 0.0))
    moisture = np.clip(0.52 + 0.30 * np.exp(-water_d / 350.0) + 0.10 * fbm(P[8], X / 2000.0, Y / 2000.0, octaves=3)
                       + 0.08 * smoothstep(0.2, 1.0, m), 0.0, 1.0)
    temperature = np.clip(0.62 - (height - floor_m) / 3800.0, 0.0, 1.0)

    # the woods as masses: a warped noise field makes irregular stands, pulled up around the designed cores
    # and on the slopes below the tree line; glades open inside them, the banks and the passes stay open
    wx = fbm(P[9], X / 1600.0 + 4.0, Y / 1600.0, octaves=3) * 420.0
    wy = fbm(P[9], X / 1600.0, Y / 1600.0 + 9.0, octaves=3) * 420.0
    field = fbm(P[10], (X + wx) / 1250.0, (Y + wy) / 1250.0, octaves=5) * 0.5 + 0.5
    cores = np.zeros_like(X)
    for fo in defn.get("forests", []):
        c = fo["center"]
        rr = np.hypot(X + wx * 0.8 - c[0], Y + wy * 0.8 - c[1]) / fo["radius_m"]
        cores = np.maximum(cores, fo["density"] * np.exp(-rr ** 2 * 1.4))
    slopes = smoothstep(-0.35, 0.25, mr) * (1.0 - smoothstep(1150.0, 1450.0, height))
    wood = field * 0.9 + cores * 0.5 + slopes * 0.22 * (0.6 + 0.8 * field)
    canopy = smoothstep(0.50, 0.62, wood)
    # scattered groves and single stands on the open floor
    groves = smoothstep(0.70, 0.86, fbm(P[11], X / 260.0, Y / 260.0, octaves=3) * 0.5 + 0.5) * 0.55
    canopy = np.maximum(canopy, groves * (1.0 - smoothstep(-0.2, 0.2, mr)))
    glades = smoothstep(0.66, 0.82, fbm(P[11], (X - wy) / 520.0, (Y + wx) / 520.0, octaves=3) * 0.5 + 0.5)
    canopy *= 1.0 - 0.9 * glades
    canopy *= 1.0 - 0.85 * np.exp(-(river_d / 70.0) ** 2)             # the banks are open, reeds and meadows
    canopy *= 1.0 - 0.8 * smoothstep(0.35, 0.8, pass_f)               # the way through a pass is cleared
    canopy *= 1.0 - smoothstep(1250.0, 1550.0, height + fbm(P[4], X / 300.0, Y / 300.0, octaves=2) * 120.0)  # the tree line
    canopy *= 1.0 - 0.85 * smoothstep(0.75, 1.3, slope)              # no wood holds on a cliff
    canopy = np.where(lake_sdf8 < 0.08, 0.0, canopy)

    biome = np.full(X.shape, BIOME["grassland"], dtype=np.uint8)
    jitter = fbm(P[7], X / 330.0, Y / 330.0, octaves=3) * 90.0
    biome[canopy > 0.5] = BIOME["deciduous"]
    biome[(canopy > 0.5) & (height + jitter > floor_m + 200.0)] = BIOME["mixed"]
    biome[(height + jitter > floor_m + 95.0) & (canopy <= 0.5) & (mr > -0.4)] = BIOME["hills"]
    biome[(height + jitter * 2.0 > 820.0) & (canopy > 0.3)] = BIOME["taiga"]
    biome[(river_d < 170.0) & (height < floor_m + 25.0) & (canopy <= 0.45)] = BIOME["floodplain"]
    wet = (lake_sdf8 > 0) & (lake_sdf8 < 0.18) & (moisture > 0.7)
    biome[wet & (canopy < 0.4)] = BIOME["marsh"]
    n_alp = fbm(P[3], X / 400.0, Y / 400.0, octaves=3) * 120.0
    biome[height + n_alp > 1500.0] = BIOME["mountain"]
    biome[height + n_alp > 2080.0] = BIOME["snow"]
    biome[lake_sdf8 < 0] = BIOME["lake"]

    # --- the founding site: dry, flat, near water but out of the floodplain, where the woods open ------------
    ss = defn["site_search"]
    near = np.hypot(X - ss["center"][0], Y - ss["center"][1]) < ss["radius_m"]
    ok = near & (river_d > 90.0) & (river_d < 170.0) & (lake_sdf8 > 0.2) & (slope < 0.06) & (mr < -0.2)
    # the edge of a wood: open ground under the fire, trees a short walk away (for the first timber)
    wood_near = box_blur(canopy, 30)
    score = -slope * 30.0 - canopy * 2.0 + wood_near * 3.0 - np.abs(river_d - 130.0) / 120.0 \
        - np.hypot(X - ss["center"][0], Y - ss["center"][1]) / 1500.0
    score = np.where(ok, score, -np.inf)
    iy, ix = np.unravel_index(int(np.argmax(score)), score.shape)
    site = [round(float(X[iy, ix])), round(float(Y[iy, ix]))]
    # the ground of the first fire is open (the wood around it stays as the land made it)
    ring = np.hypot(X - site[0], Y - site[1])
    canopy *= smoothstep(60.0, 120.0, ring)
    biome[(ring < 110.0) & (biome == BIOME["deciduous"])] = BIOME["grassland"]

    # --- the deposits: stone within a short walk of the fire (always), more on the hills; iron in the foothills --
    deposits = []

    def dry_spot(x, y, min_river=40.0):
        best = None
        for r in range(0, 400, 16):
            for k in range(16):
                a = k / 16.0 * math.tau
                px, py = x + math.cos(a) * r, y + math.sin(a) * r
                ci, cj = int(py / CELL), int(px / CELL)
                if 0 <= ci < H and 0 <= cj < W and lake_sdf8[ci, cj] > 0.1 and river_d[ci, cj] > min_river and mr[ci, cj] < 0.5:
                    best = (px, py)
                    break
            if best:
                break
        return best or (x, y)

    a = math.atan2(site[1] - rivers[0]["points"][len(rivers[0]["points"]) // 2][1], site[0] - rivers[0]["points"][len(rivers[0]["points"]) // 2][0])
    sx, sy = dry_spot(site[0] + math.cos(a) * 190.0, site[1] + math.sin(a) * 190.0, 70.0)
    deposits.append({"type": "stone", "x": round(sx), "y": round(sy), "richness": 1.0})
    for p in defn.get("stone", []):
        x, y = dry_spot(*p)
        deposits.append({"type": "stone", "x": round(x), "y": round(y), "richness": 0.9})
    for p in defn.get("iron", []):
        x, y = dry_spot(*p)
        deposits.append({"type": "iron", "x": round(x), "y": round(y), "richness": 0.8})

    # the illustrated peaks of the rim (the same sprites as the continent's ranges, at the valley's scale)
    mountains = place_mountains(height, mr, water, CELL, (pass_f < 0.2) & (river_d > 160.0))

    report = {
        "floor_share": float((mr < 0).mean()),
        "rim_share": float((mr > 0.5).mean()),
        "max_height": float(height.max()),
        "lake_cells_4m": int((water == 2).sum()),
        "river_cells_4m": int((water == 3).sum()),
        "forest_share": float((canopy > 0.45).mean()),
        "site": site,
        "seconds": round(time.time() - t0, 1),
    }
    return {
        "height": height.astype(np.float32), "biome": biome, "canopy": np.clip(canopy * 255, 0, 255).astype(np.uint8),
        "moisture": np.clip(moisture * 255, 0, 255).astype(np.uint8),
        "temperature": np.clip(temperature * 255, 0, 255).astype(np.uint8),
        "water": water, "coast": coast, "rivers": rivers, "lakes": lakes_meta, "deposits": deposits, "site": site,
        "grid": (W, H), "fine": (WF, HF), "report": report, "rim_m": mr, "mountains": mountains,
    }


def place_mountains(height, mr, water, cell, allowed):
    """Greedy placement from the highest ground down (as tools/worldgen/place_mountains.py for the continent), only
    on the rim and never over a pass or a river gorge: [x, y, width_m, class, variant] sorted by y."""
    wet = water[0::2, 0::2] > 0
    ys, xs = np.nonzero((height > 650.0) & (mr > 0.15) & allowed & ~wet[: height.shape[0], : height.shape[1]])
    order = np.argsort(-height[ys, xs])
    placed = []
    buckets = {}
    bucket = 800.0
    for idx in order:
        y, x = ys[idx], xs[idx]
        hv = float(height[y, x])
        wx, wy = (x + 0.5) * cell, (y + 0.5) * cell
        w = float(np.clip(330.0 + hv * 0.5, 650.0, 1650.0))
        bx, by = int(wx // bucket), int(wy // bucket)
        ok = True
        for gy in range(by - 3, by + 4):
            for gx in range(bx - 3, bx + 4):
                for (px, py, pw) in buckets.get((gx, gy), ()):
                    if math.hypot(px - wx, (py - wy) * 1.6) < 0.62 * 0.5 * (pw + w):
                        ok = False
                        break
                if not ok:
                    break
            if not ok:
                break
        if not ok:
            continue
        cls = "hill" if hv < 1100.0 else ("peak" if hv < 1900.0 else "snowpeak")
        placed.append([round(wx, 1), round(wy, 1), round(w, 1), cls, (int(x) * 73856093 ^ int(y) * 19349663) % 4])
        buckets.setdefault((bx, by), []).append((wx, wy, w))
    placed.sort(key=lambda p: p[1])
    return placed


def write(defn, out, dest, preview=False):
    os.makedirs(dest, exist_ok=True)
    W, H = out["grid"]
    WF, HF = out["fine"]
    rasters = {}
    for name in ["height", "biome", "canopy", "moisture", "temperature"]:
        info = write_raster(os.path.join(dest, name + ".bin"), out[name])
        info.update(cell_m=CELL, format="RF" if name == "height" else "R8")
        rasters[name] = info
    rasters["forest"] = dict(rasters["canopy"])   # the ecological density of a valley is where its trees stand
    for name in ["water", "coast"]:
        info = write_raster(os.path.join(dest, name + ".bin"), out[name])
        info.update(cell_m=FINE, format="R8")
        rasters[name] = info
    rivers = []
    for r in out["rivers"]:
        flat = []
        for (x, y), w in zip(r["points"], r["widths"]):
            flat.extend([round(float(x), 1), round(float(y), 1), round(float(w), 1)])
        rivers.append({"id": r["id"], "name": r["name"], "length_m": round(r["length"]), "max_width_m": round(float(max(r["widths"])), 1), "xyw": flat})
    meta = {
        "homeland_version": 1,
        "generator_version": GENERATOR_VERSION,
        "id": defn["id"],
        "name": defn["name"],
        "template": defn["template"],
        "world_width_m": float(defn["size"][0]),
        "world_height_m": float(defn["size"][1]),
        "cell_m": CELL, "fine_cell_m": FINE,
        "grid_width": W, "grid_height": H, "fine_grid_width": WF, "fine_grid_height": HF,
        "rasters": rasters,
        "rivers": rivers,
        "lakes": out["lakes"],
        "passes": defn["passes"],
        "deposits": out["deposits"],
        "founding_site": out["site"],
        "mountains": out["mountains"],
        "names": defn.get("names", {}),
        "report": {k: v for k, v in out["report"].items() if k != "seconds"},   # the data never depends on the clock
    }
    write_json(os.path.join(dest, "domain_meta.json"), meta)
    if preview:
        prev = os.path.join(HERE, "out_preview")
        os.makedirs(prev, exist_ok=True)
        h = out["height"]
        shade = np.clip((h - h.min()) / (h.max() - h.min()) * 255, 0, 255).astype(np.uint8)
        pal = {1: (60, 110, 160), 3: (162, 167, 92), 4: (147, 168, 87), 5: (90, 130, 60), 6: (80, 118, 70), 7: (70, 100, 70),
               8: (173, 166, 104), 9: (163, 156, 124), 10: (220, 220, 215), 11: (118, 133, 89)}
        img = np.zeros(h.shape + (3,), dtype=np.uint8)
        for k, c in pal.items():
            img[out["biome"] == k] = c
        gy, gx = np.gradient(h)
        lit = np.clip(1.0 + (-gx - gy) * 0.02, 0.5, 1.4)
        img = np.clip(img * lit[..., None], 0, 255).astype(np.uint8)
        wtr = out["water"][::2, ::2]
        img[wtr[: img.shape[0], : img.shape[1]] > 0] = (50, 100, 170)
        sx, sy = out["site"]
        img[int(sy / CELL) - 3:int(sy / CELL) + 3, int(sx / CELL) - 3:int(sx / CELL) + 3] = (255, 40, 40)
        for d in out["deposits"]:
            c = (230, 230, 230) if d["type"] == "stone" else (120, 60, 40)
            img[int(d["y"] / CELL) - 2:int(d["y"] / CELL) + 2, int(d["x"] / CELL) - 2:int(d["x"] / CELL) + 2] = c
        write_png(os.path.join(prev, defn["id"] + "_map.png"), img)
        write_png(os.path.join(prev, defn["id"] + "_height.png"), shade)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--check", action="store_true", help="regenerate in a temporary folder and compare with the committed data")
    args = ap.parse_args()
    with open(os.path.join(ROOT, "data", "domains", "homelands.json"), encoding="utf-8") as f:
        homelands = json.load(f)["homelands"]
    for defn in homelands:
        if args.only and defn["id"] != args.only:
            continue
        dest = os.path.join(ROOT, "data", "domains", defn["id"])
        if args.check:
            import filecmp
            import tempfile
            tmp = tempfile.mkdtemp()
            write(defn, build(defn), tmp)
            diffs = [f for f in sorted(os.listdir(tmp)) if not os.path.exists(os.path.join(dest, f))
                     or not filecmp.cmp(os.path.join(tmp, f), os.path.join(dest, f), shallow=False)]
            print("homeland %s: %s" % (defn["id"], "identical to the committed data" if not diffs else "DIFFERS: " + ", ".join(diffs)))
            if diffs:
                sys.exit(1)
            continue
        if not args.force and os.path.exists(os.path.join(dest, "domain_meta.json")) and os.path.exists(os.path.join(dest, "height.bin")) and not args.preview:
            print("homeland %s: present" % defn["id"])
            continue
        out = build(defn, args.preview)
        write(defn, out, dest, args.preview)
        print("homeland %s: %s" % (defn["id"], json.dumps(out["report"])), flush=True)


if __name__ == "__main__":
    main()
