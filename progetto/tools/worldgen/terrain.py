"""Continent, elevation, hydrology, climate and biomes of the official map."""
import time

import numpy as np

import layout as L
from grids import (bilinear_sample, box_blur, dilate4, distance_from, distance_to_polyline,
                   keep_largest, label_components, resize_bilinear, resize_nearest, chaikin)
from hydro import accumulation, find_lakes, flow_directions, priority_flood, trace_rivers
from kdnoise import Perlin, fbm, ridged, smoothstep

CELL = 64.0
W = int(L.WORLD_W_M / CELL)   # 1750
H = int(L.WORLD_H_M / CELL)   # 1125
FINE = 32.0
W32, H32 = W * 2, H * 2
COARSE = 128.0


def log(msg, t0=None):
    if t0 is None:
        print(msg, flush=True)
    else:
        print("%s (%.1f s)" % (msg, time.time() - t0), flush=True)


def world_mesh(cell, w, h):
    xs = (np.arange(w) + 0.5) * cell
    ys = (np.arange(h) + 0.5) * cell
    return np.meshgrid(xs, ys)


def _blob(Xk, Yk, blob):
    u0, v0, ru, rv, rot, weight = blob
    cx = u0 * L.WORLD_W_M / 1000.0
    cy = v0 * L.WORLD_H_M / 1000.0
    rx = ru * L.WORLD_W_M / 1000.0
    ry = rv * L.WORLD_H_M / 1000.0
    a = np.radians(rot)
    dx = Xk - cx
    dy = Yk - cy
    px = dx * np.cos(a) + dy * np.sin(a)
    py = -dx * np.sin(a) + dy * np.cos(a)
    d2 = (px / rx) ** 2 + (py / ry) ** 2
    return weight * (1.0 - d2)


# ---------------------------------------------------------------------------
def build_continent(ctx):
    t0 = time.time()
    seed = L.WORLD_SEED
    X, Y = world_mesh(CELL, W, H)
    Xk, Yk = X / 1000.0, Y / 1000.0
    pw1, pw2, pn1, pn2 = Perlin(seed + 1), Perlin(seed + 2), Perlin(seed + 3), Perlin(seed + 4)
    warp_x = Xk + 5.0 * fbm(pw1, Xk / 22.0, Yk / 22.0, 4) + 1.4 * fbm(pw2, Xk / 5.0 + 11.0, Yk / 5.0, 3)
    warp_y = Yk + 5.0 * fbm(pw2, Xk / 22.0 + 40.0, Yk / 22.0 + 40.0, 4) + 1.4 * fbm(pw1, Xk / 5.0, Yk / 5.0 + 23.0, 3)
    pot = np.full(X.shape, -1.0)
    for b in L.LAND_BLOBS:
        pot = np.maximum(pot, _blob(warp_x, warp_y, b))
    for b in L.SEA_BLOBS:
        pot -= 1.9 * np.maximum(0.0, _blob(warp_x, warp_y, b))
    pot += 0.34 * fbm(pn1, Xk / 9.0, Yk / 9.0, 5)
    pot += 0.12 * fbm(pn2, Xk / 2.6, Yk / 2.6, 3)
    edge_km = np.minimum(np.minimum(Xk, L.WORLD_W_M / 1000.0 - Xk), np.minimum(Yk, L.WORLD_H_M / 1000.0 - Yk))
    pot -= 1.8 * (1.0 - smoothstep(0.0, 8.0, edge_km))
    ctx["potential64"] = pot.astype(np.float32)
    log("  potential field", t0)

    # land at 32 m from the smooth potential, one body, no enclosed seas
    t1 = time.time()
    pot32 = resize_bilinear(pot, H32, W32)
    land32 = pot32 > 0.0
    land32 = keep_largest(land32)
    sea_labels, sizes = label_components(~land32)
    border_labels = set(np.unique(np.concatenate([sea_labels[0, :], sea_labels[-1, :], sea_labels[:, 0], sea_labels[:, -1]])).tolist())
    enclosed = (sea_labels > 0) & ~np.isin(sea_labels, list(border_labels))
    land32 |= enclosed
    ctx["land32"] = land32
    # a 64 m cell is land if any of its four 32 m children is land
    l4 = land32.reshape(H, 2, W, 2)
    ctx["land64"] = l4.any(axis=(1, 3))
    log("  land masks 32/64 m (%.1f%% land)" % (100.0 * land32.mean()), t1)

    t2 = time.time()
    land64 = ctx["land64"]
    ctx["land_dist64"] = distance_from(~land64, 96, within=land64)
    ctx["sea_dist64"] = distance_from(land64, 96, within=~land64)
    # coarse distance (512 m) for continental effects
    land512 = resize_nearest(land64.astype(np.uint8), H // 8, W // 8).astype(bool)
    d512 = distance_from(~land512, 120, within=land512)
    ctx["inland_km"] = np.clip(resize_bilinear(d512, H, W) * 0.512, 0.0, 60.0).astype(np.float32)
    s512 = distance_from(land512, 120, within=~land512)
    ctx["offshore_km"] = np.clip(resize_bilinear(s512, H, W) * 0.512, 0.0, 60.0).astype(np.float32)
    log("  coast distances", t2)
    ctx["X"], ctx["Y"] = X, Y


# ---------------------------------------------------------------------------
def build_elevation(ctx):
    t0 = time.time()
    seed = L.WORLD_SEED
    X, Y = ctx["X"], ctx["Y"]
    Xk, Yk = X / 1000.0, Y / 1000.0
    land = ctx["land64"]
    ph, pu, pr = Perlin(seed + 10), Perlin(seed + 11), Perlin(seed + 12)

    U, V = X / L.WORLD_W_M, Y / L.WORLD_H_M
    highland = np.zeros(X.shape)
    for (u0, v0, ru, rv, s) in L.HIGHLANDS:
        highland = np.maximum(highland, s * np.exp(-(((U - u0) / ru) ** 2 + ((V - v0) / rv) ** 2)))
    highland = np.clip(highland + 0.25 * fbm(ph, Xk / 20.0 + 5.0, Yk / 20.0, 3), 0.0, 1.0)
    hills = fbm(ph, Xk / 6.0, Yk / 6.0, 5) * 0.5 + 0.5
    hills = smoothstep(0.40, 0.95, hills) ** 1.4 * (60.0 + 520.0 * highland)
    undulation = (10.0 + 18.0 * highland) * fbm(pu, Xk / 1.6, Yk / 1.6, 3)
    inland = 130.0 * smoothstep(0.0, 24.0, ctx["inland_km"])
    coastal_low = 0.35 + 0.65 * smoothstep(0.0, 14.0, ctx["land_dist64"])
    basins = np.zeros(X.shape)
    bwx = Xk + 1.6 * fbm(pu, Xk / 3.0 + 13.0, Yk / 3.0, 4)
    bwy = Yk + 1.6 * fbm(pu, Xk / 3.0, Yk / 3.0 + 29.0, 4)
    for (u0, v0, ru, rv, rot, depth) in L.LAKE_BASINS:
        g = _blob(bwx, bwy, (u0, v0, ru, rv, rot, 1.0))
        basins = np.maximum(basins, depth * smoothstep(-0.8, 0.6, g))

    mountains = np.zeros(X.shape)
    range_mask = np.zeros(X.shape)
    rn = ridged(pr, Xk / 4.2, Yk / 4.2, 5)
    for rg in L.RANGES:
        pts = [(u * L.WORLD_W_M, v * L.WORLD_H_M) for (u, v) in rg["points"]]
        width_m = rg["width"] * L.WORLD_W_M
        d, t = distance_to_polyline(X, Y, pts)
        # irregular edges: the range is wider in some places
        wobble = 1.0 + 0.35 * fbm(pu, Xk / 9.0 + len(pts), Yk / 9.0, 3)
        wm = width_m * wobble
        crest = smoothstep(wm, 0.0, d)
        foot = smoothstep(wm * 2.5, wm * 0.5, d)
        taper = smoothstep(0.0, 0.10, t) * smoothstep(1.0, 0.90, t)
        m = rg["peak"] * taper * (2700.0 * crest ** 1.3 * (0.40 + 0.60 * rn) + 480.0 * foot * (0.55 + 0.45 * rn))
        for (pu_, pv_, strength) in rg["passes"]:
            dp = np.hypot(X - pu_ * L.WORLD_W_M, Y - pv_ * L.WORLD_H_M)
            g = np.exp(-(dp / (width_m * 1.1)) ** 2)
            m *= 1.0 - strength * 0.82 * g
        mountains = np.maximum(mountains, m)
        range_mask = np.maximum(range_mask, crest * taper * rg["peak"])
    elev = 12.0 + inland + (hills + undulation) * coastal_low + mountains
    # explicit lake basins: the floor sinks below the surrounding plain so hydrology fills a lake
    elev = np.where(basins > 0.5, np.minimum(elev, (inland + 40.0) - basins * 1.2), elev)
    elev = np.maximum(elev, 2.0)
    sea_depth = -(3.0 + 45.0 * smoothstep(0.0, 30.0, ctx["sea_dist64"]) + 60.0 * smoothstep(0.0, 25.0, ctx["offshore_km"]))
    elev = np.where(land, elev, sea_depth)
    ctx["elev64"] = elev.astype(np.float32)
    ctx["range_mask64"] = range_mask.astype(np.float32)
    log("  elevation (max %.0f m)" % elev.max(), t0)


# ---------------------------------------------------------------------------
def build_hydrology(ctx):
    t0 = time.time()
    elev = ctx["elev64"]
    land64 = ctx["land64"]
    # coarse 128 m grid (every other cell)
    h128 = elev[::2, ::2].astype(np.float64)
    land128 = land64[::2, ::2] & (h128 > 0.5)
    land128 = keep_largest(land128)
    # a little noise so flow paths on plains meander instead of running along grid axes
    Xc = (np.arange(h128.shape[1]) + 0.5) * COARSE / 1000.0
    Yc = (np.arange(h128.shape[0]) + 0.5) * COARSE / 1000.0
    XC, YC = np.meshgrid(Xc, Yc)
    pn = Perlin(L.WORLD_SEED + 15)
    h_flow = h128 + 9.0 * fbm(pn, XC / 1.3, YC / 1.3, 3) + 4.0 * fbm(pn, XC / 0.4 + 7.0, YC / 0.4, 2)
    filled = priority_flood(h_flow, land128)
    log("  priority flood", t0)
    t1 = time.time()
    dirs = flow_directions(filled, land128)
    acc = accumulation(filled, land128, dirs)
    log("  flow + accumulation", t1)
    t2 = time.time()
    lake128, lakes = find_lakes(h_flow, filled, land128, min_cells=70, min_depth=9.0, max_lakes=14)
    rivers_cells = trace_rivers(acc, dirs, land128, lake128, threshold_cells=380)
    log("  %d lakes, %d river paths" % (len(lakes), len(rivers_cells)), t2)
    ctx["filled128"] = filled
    ctx["acc128"] = acc
    ctx["lake128"] = lake128
    ctx["land128"] = land128
    ctx["lakes"] = lakes

    # river polylines in metres with meanders and widths
    pm = Perlin(L.WORLD_SEED + 20)
    rivers = []
    for rid, path in enumerate(rivers_cells):
        pts = []
        for (cx, cy, a) in path:
            x = (cx + 0.5) * COARSE
            y = (cy + 0.5) * COARSE
            width = float(np.clip(6.0 + 9.0 * np.sqrt(a / 420.0), 6.0, 125.0))
            pts.append((x, y, width))
        # thin the grid staircase, keep the ends
        if len(pts) > 6:
            pts = [pts[0]] + pts[1:-1][::2] + [pts[-1]]
        pts = chaikin(pts, iterations=1)
        # meander: displace vertices perpendicular to the smoothed flow direction; the displacement
        # fades at source and mouth so rivers still start and end where hydrology says
        jittered = [pts[0]]
        s = 0.0
        n_pts = len(pts)
        for i in range(1, n_pts - 1):
            x0, y0, _ = pts[max(i - 3, 0)]
            x1, y1, w1 = pts[i]
            x2, y2, _ = pts[min(i + 3, n_pts - 1)]
            s += ((pts[i][0] - pts[i - 1][0]) ** 2 + (pts[i][1] - pts[i - 1][1]) ** 2) ** 0.5
            tx, ty = x2 - x0, y2 - y0
            n = (tx * tx + ty * ty) ** 0.5 or 1.0
            nx, ny = -ty / n, tx / n
            fade_ends = min(1.0, i / 6.0, (n_pts - 1 - i) / 6.0)
            off = (150.0 * float(pm.noise(np.array(s / 1500.0), np.array(rid * 3.7)))
                   + 45.0 * float(pm.noise(np.array(s / 380.0 + 50.0), np.array(rid * 1.3))))
            off *= fade_ends * min(1.0, 0.45 + w1 / 60.0)
            jittered.append((x1 + nx * off, y1 + ny * off, w1))
        jittered.append(pts[-1])
        smooth = chaikin(jittered, iterations=3)
        rivers.append({"id": rid, "points": smooth, "length_m": _poly_len(smooth),
                       "max_width": max(p[2] for p in smooth)})
    ctx["rivers"] = rivers
    log("  river polylines (%.0f km total)" % (sum(r["length_m"] for r in rivers) / 1000.0), t2)

    # carve valleys into the 64 m elevation and flatten lakes
    t3 = time.time()
    carve = np.zeros(elev.shape, dtype=np.float32)
    for r in rivers:
        for (x, y, wdt) in _resample(r["points"], 40.0):
            radius = wdt * 0.5 + 180.0
            depth = 3.0 + wdt * 0.10
            cx, cy = x / CELL - 0.5, y / CELL - 0.5
            rc = int(radius / CELL) + 1
            x0, x1 = max(int(cx) - rc, 0), min(int(cx) + rc + 2, W)
            y0, y1 = max(int(cy) - rc, 0), min(int(cy) + rc + 2, H)
            if x0 >= x1 or y0 >= y1:
                continue
            gx = np.arange(x0, x1)
            gy = np.arange(y0, y1)
            dd = np.hypot((gx[None, :] - cx) * CELL, (gy[:, None] - cy) * CELL)
            val = depth * np.clip(1.0 - dd / radius, 0.0, 1.0) ** 1.5
            carve[y0:y1, x0:x1] = np.maximum(carve[y0:y1, x0:x1], val)
    elev = np.where(land64, np.maximum(elev - carve, 1.0), elev)
    # smooth, organic lake shapes from a blurred coarse mask plus noise (no 128 m staircase)
    Xk, Yk = ctx["X"] / 1000.0, ctx["Y"] / 1000.0
    lake_soft = box_blur(lake128.astype(np.float64), 1, 2)
    lake_f64 = resize_bilinear(lake_soft, H, W) + 0.10 * fbm(Perlin(L.WORLD_SEED + 16), Xk / 0.45, Yk / 0.45, 3)
    ctx["lake_f64"] = lake_f64.astype(np.float32)
    lake64 = (lake_f64 > 0.5) & land64
    level128 = np.where(lake128, filled, 0.0)
    level64 = resize_nearest(level128, H, W)
    # propagate lake levels a few cells outward so shores can be graded toward the water
    lvl = np.where(lake64, level64, 0.0)
    for _ in range(8):
        grown = lvl.copy()
        grown[1:, :] = np.maximum(grown[1:, :], lvl[:-1, :])
        grown[:-1, :] = np.maximum(grown[:-1, :], lvl[1:, :])
        grown[:, 1:] = np.maximum(grown[:, 1:], lvl[:, :-1])
        grown[:, :-1] = np.maximum(grown[:, :-1], lvl[:, 1:])
        lvl = grown
    shore_d = distance_from(lake64, 8)
    shore = (~lake64) & land64 & (shore_d < 8) & (lvl > 0)
    elev = np.where(shore, np.minimum(elev, lvl + 1.0 + shore_d * 7.0), elev)
    elev = np.where(lake64, np.maximum(lvl - 2.5, 0.5), elev)
    ctx["elev64"] = elev.astype(np.float32)
    ctx["lake64"] = lake64
    log("  valleys carved, lakes flattened", t3)


def _poly_len(pts):
    total = 0.0
    for i in range(len(pts) - 1):
        total += ((pts[i + 1][0] - pts[i][0]) ** 2 + (pts[i + 1][1] - pts[i][1]) ** 2) ** 0.5
    return total


def _resample(pts, step):
    out = []
    for i in range(len(pts) - 1):
        x0, y0, w0 = pts[i]
        x1, y1, w1 = pts[i + 1]
        seg = ((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5
        n = max(1, int(seg / step))
        for k in range(n):
            t = k / n
            out.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, w0 + (w1 - w0) * t))
    out.append(pts[-1])
    return out


# ---------------------------------------------------------------------------
def build_water32(ctx):
    t0 = time.time()
    land32 = ctx["land32"]
    water = np.where(land32, 0, 1).astype(np.uint8)
    lake32 = (resize_bilinear(ctx["lake_f64"].astype(np.float64), H32, W32) > 0.5) & land32
    water[lake32] = 2
    river32 = np.zeros(land32.shape, dtype=bool)
    for r in ctx["rivers"]:
        for (x, y, wdt) in _resample(r["points"], 12.0):
            half = max(wdt * 0.5, 10.0)
            cx, cy = x / FINE - 0.5, y / FINE - 0.5
            rc = int(half / FINE) + 1
            x0, x1 = max(int(cx) - rc, 0), min(int(cx) + rc + 2, W32)
            y0, y1 = max(int(cy) - rc, 0), min(int(cy) + rc + 2, H32)
            if x0 >= x1 or y0 >= y1:
                continue
            gx = np.arange(x0, x1)
            gy = np.arange(y0, y1)
            dd = np.hypot((gx[None, :] - cx) * FINE, (gy[:, None] - cy) * FINE)
            river32[y0:y1, x0:x1] |= dd <= half
    water[river32 & land32 & (water == 0)] = 3
    ctx["water32"] = water
    # signed distance to standing water (sea and lakes) at 32 m, positive on dry land, for crisp shores
    dry = land32 & ~lake32
    ld = distance_from(~dry, 60, within=dry)
    sd = distance_from(dry, 60, within=~dry)
    ctx["coast32"] = np.clip(np.where(dry, 127.5 + ld * 2.0, 127.5 - sd * 2.0), 0, 255).astype(np.uint8)
    ctx["river_dist64"] = distance_from(river32[::2, ::2] | ctx["lake64"], 40)
    # smooth proximity (0..1) to rivers and lakes: gaussian-like, no octagonal artefacts
    prox = box_blur((river32[::2, ::2] | ctx["lake64"]).astype(np.float64), 5, 3)
    ctx["river_prox64"] = np.clip(prox * 6.0, 0.0, 1.0).astype(np.float32)
    log("  water raster 32 m", t0)


# ---------------------------------------------------------------------------
def build_climate(ctx):
    t0 = time.time()
    elev = ctx["elev64"]
    land = ctx["land64"]
    X, Y = ctx["X"], ctx["Y"]
    Xk, Yk = X / 1000.0, Y / 1000.0
    U, V = X / L.WORLD_W_M, Y / L.WORLD_H_M
    pc = Perlin(L.WORLD_SEED + 30)

    # westerly winds: moisture picked up at sea, dropped when climbing, rain shadow behind ranges
    e = elev[::2, ::2]
    lnd = land[::2, ::2]
    h, w = e.shape
    air = np.ones(h)
    precip = np.zeros((h, w))
    prev = np.zeros(h)
    for x in range(w):
        col = e[:, x]
        is_land = lnd[:, x]
        rise = np.maximum(col - prev, 0.0)
        air = np.where(is_land, air * np.exp(-rise / 700.0) * 0.9982, np.minimum(1.0, air + 0.06))
        precip[:, x] = np.where(is_land, air * (0.55 + np.minimum(0.45, rise / 160.0)), 0.0)
        prev = np.where(is_land, np.maximum(col, prev * 0.985), 0.0)
    precip = box_blur(precip, 3, 2)
    precip64 = resize_bilinear(precip, H, W)
    coastal = np.exp(-ctx["inland_km"] / 28.0)
    moisture = 0.18 + 0.30 * coastal + 0.52 * np.clip(precip64 / 0.9, 0.0, 1.0)
    for (u0, v0, ru, rv, s) in L.ARID_CENTERS:
        g = np.exp(-(((U - u0) / ru) ** 2 + ((V - v0) / rv) ** 2))
        moisture *= 1.0 - s * g
    for (u0, v0, ru, rv, s) in L.WET_CENTERS:
        g = np.exp(-(((U - u0) / ru) ** 2 + ((V - v0) / rv) ** 2))
        moisture += s * g
    moisture += 0.16 * np.exp(-ctx["river_dist64"] / 6.0)
    moisture += 0.07 * fbm(pc, Xk / 6.0, Yk / 6.0, 4)
    moisture = np.clip(moisture, 0.0, 1.0)

    temperature = 0.26 + 0.64 * V - np.maximum(elev, 0.0) / 2800.0 + 0.04 * fbm(pc, Xk / 10.0 + 70.0, Yk / 10.0, 3)
    temperature = np.clip(temperature, 0.0, 1.0)
    ctx["moisture64"] = np.where(land, moisture, 1.0).astype(np.float32)
    ctx["temperature64"] = temperature.astype(np.float32)
    log("  climate", t0)


# ---------------------------------------------------------------------------
BIOME = {"ocean": 0, "lake": 1, "beach": 2, "grassland": 3, "floodplain": 4, "deciduous": 5, "mixed": 6,
         "taiga": 7, "hills": 8, "mountain": 9, "snow": 10, "marsh": 11, "steppe": 12, "desert": 13,
         "mediterranean": 14, "tundra": 15}


def build_biomes(ctx, biome_defs):
    t0 = time.time()
    elev = ctx["elev64"].astype(np.float64)
    land = ctx["land64"]
    lake = ctx["lake64"]
    m = ctx["moisture64"].astype(np.float64)
    t = ctx["temperature64"].astype(np.float64)
    X, Y = ctx["X"], ctx["Y"]
    Xk, Yk = X / 1000.0, Y / 1000.0
    gy, gx = np.gradient(elev, CELL)
    slope = np.hypot(gx, gy)
    ctx["slope64"] = slope.astype(np.float32)
    pb = Perlin(L.WORLD_SEED + 40)
    patch = fbm(pb, Xk / 3.2, Yk / 3.2, 4)
    fine = fbm(Perlin(L.WORLD_SEED + 41), Xk / 0.9, Yk / 0.9, 3)
    mp = m + 0.16 * patch
    river_d = ctx["river_dist64"]

    b = np.full(elev.shape, BIOME["grassland"], dtype=np.uint8)

    def put(mask, name):
        b[mask & (b == BIOME["grassland"]) & ~assigned[0]] = BIOME[name]
        assigned[0] |= mask

    assigned = [np.zeros(elev.shape, dtype=bool)]
    prox = ctx["river_prox64"] * (1.0 + 0.45 * fine + 0.35 * patch)
    rd = np.where(prox > 0.02, 8.0 * (1.0 - np.clip(prox, 0.0, 1.0)), 99.0)  # organic river-distance proxy
    put(~land, "ocean")
    put(lake, "lake")
    put(land & (elev > 1850 + 250 * t), "snow")
    put(land & ((elev > 1150 + 120 * patch) | ((slope > 0.42) & (elev > 650))), "mountain")
    put(land & (ctx["land_dist64"] <= 1) & (elev < 30) & (slope < 0.08) & (fine > -0.1), "beach")
    put(land & (t < 0.22) & (mp < 0.50), "tundra")
    put(land & (t < 0.27), "taiga")
    put(land & (m < 0.20) & (t > 0.55), "desert")
    put(land & (m < 0.24), "steppe")
    put(land & (m < 0.36) & (t > 0.55), "steppe")
    put(land & (rd <= 2.5) & (elev < 60) & (m > 0.60) & (slope < 0.03) & (patch > 0.10), "marsh")
    put(land & (rd <= 6.0) & (elev < 420) & (slope < 0.06) & (m >= 0.34) & (patch < 0.30), "floodplain")
    put(land & (t > 0.72) & (m < 0.60) & (mp < 0.62), "mediterranean")
    put(land & (mp > 0.60) & (t < 0.38), "taiga")
    put(land & ((elev > 560) | (slope > 0.17)) & (mp < 0.58), "hills")
    put(land & (mp > 0.57) & (t < 0.50), "mixed")
    put(land & (mp > 0.53), "deciduous")
    put(land & (mp > 0.46) & (patch > 0.08), "deciduous")
    ctx["biome64"] = b

    # forest density from biome base values, patchy
    base = np.zeros(256, dtype=np.float64)
    for d in biome_defs:
        base[d["index"]] = d["forest"]
    dens = base[b]
    dens *= np.clip(0.55 + 0.45 * (patch + 0.6) + 0.25 * fine, 0.0, 1.15)
    dens = np.where(b == BIOME["mountain"], dens * np.clip((1500.0 - elev) / 600.0, 0.0, 1.0), dens)
    dens = box_blur(dens, 1, 1)
    ctx["forest64"] = np.clip(dens * 255.0, 0, 255).astype(np.uint8)
    counts = np.bincount(b.ravel(), minlength=16)
    log("  biomes " + ", ".join("%s %.1f%%" % (k, 100.0 * counts[v] / land.sum()) for k, v in BIOME.items() if v > 1), t0)

