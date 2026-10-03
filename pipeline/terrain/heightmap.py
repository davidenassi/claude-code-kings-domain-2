"""Valley heightmap synthesis: floor field + mountains + features + erosion + hydrology carving."""
from __future__ import annotations

import time

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.spatial import cKDTree

from kd import const as K
from terrain import erosion, layout as L
from terrain import noise as N

X0 = 0.0
Y0 = -K.NORTH_PAD_M
W = K.VALLEY_W_M
H = K.VALLEY_H_M + K.NORTH_PAD_M


def grid(step: float):
    return (X0 + step * 0.5, Y0 + step * 0.5, step, int(W / step), int(H / step))


def coords(step: float):
    x0, y0, s, nx, ny = grid(step)
    xs = x0 + np.arange(nx, dtype=np.float32) * s
    ys = y0 + np.arange(ny, dtype=np.float32) * s
    return np.meshgrid(xs, ys)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def log(*a):
    print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)


# ------------------------------------------------------------------------------------------------
# water geometry
# ------------------------------------------------------------------------------------------------
class Water:
    def __init__(self):
        self.rivers = {name: L.densify_river(name, 1.0) for name in L.RIVERS}
        cols = {k: [] for k in ("x", "y", "level", "width", "depth", "tx", "ty", "slope", "rid")}
        for rid, (name, r) in enumerate(self.rivers.items()):
            slope = -np.gradient(r["level"], r["s"])          # positive downhill
            for k in ("x", "y", "level", "width", "depth", "tx", "ty"):
                cols[k].append(r[k])
            cols["slope"].append(slope)
            cols["rid"].append(np.full(len(r["x"]), rid))
        self.s = {k: np.concatenate(v).astype(np.float64) for k, v in cols.items()}
        self.tree = cKDTree(np.c_[self.s["x"], self.s["y"]])

    def query(self, xs, ys, max_d=400.0):
        pts = np.c_[xs.ravel(), ys.ravel()]
        d, idx = self.tree.query(pts, distance_upper_bound=max_d, workers=-1)
        far = ~np.isfinite(d)
        idx[far] = 0
        d[far] = max_d
        return d.reshape(xs.shape).astype(np.float32), idx.reshape(xs.shape), far.reshape(xs.shape)

    @staticmethod
    def lake_rnorm(xs, ys):
        cx, cy = L.LAKE["center"]
        rx, ry = L.LAKE["radii"]
        a = np.radians(L.LAKE["rotation_deg"])
        dx = xs - cx
        dy = ys - cy
        u = (dx * np.cos(a) + dy * np.sin(a)) / rx
        v = (-dx * np.sin(a) + dy * np.cos(a)) / ry
        th = np.arctan2(v, u)
        return np.hypot(u, v) / L.lake_radius(th)


# ------------------------------------------------------------------------------------------------
def floor_polygon_sdf(step):
    """Signed distance (m) to the valley floor polygon, positive OUTSIDE."""
    x0, y0, s, nx, ny = grid(step)
    img = Image.new("L", (nx, ny), 0)
    pts = [((px - X0) / s, (py - Y0) / s) for px, py in L.FLOOR_POLYGON]
    ImageDraw.Draw(img).polygon(pts, fill=255)
    inside = np.array(img) > 127
    d_out = ndimage.distance_transform_edt(~inside) * s
    d_in = ndimage.distance_transform_edt(inside) * s
    return (d_out - d_in).astype(np.float32)


def harmonic_level_field(water: Water, step=16.0, iters=3000):
    """Smooth field equal to the valley-river water levels on the rivers (harmonic interpolation)."""
    x0, y0, s, nx, ny = grid(step)
    f = np.full((ny, nx), np.nan, np.float32)
    fixed = np.zeros((ny, nx), bool)
    s_ = water.s
    names = list(water.rivers.keys())
    for k in range(len(s_["x"])):
        name = names[int(s_["rid"][k])]
        yv = s_["y"][k]
        # only the valley-floor stretches constrain the floor (not the mountain/hanging stretches)
        if name == "argento" and yv < 380:
            continue
        if name == "bianco" and yv < 360:
            continue
        if name == "ponente" and s_["x"][k] < 300:
            continue
        i = int((s_["x"][k] - x0) / s + 0.5)
        j = int((yv - y0) / s + 0.5)
        if 0 <= i < nx and 0 <= j < ny:
            f[j, i] = s_["level"][k]
            fixed[j, i] = True
    xs, ys = coords(step)
    lake = Water.lake_rnorm(xs, ys) < 1.0
    f[lake] = L.LAKE["level"]
    fixed |= lake
    g = np.where(fixed, f, np.nanmean(f)).astype(np.float32)
    for it in range(iters):
        p = np.pad(g, 1, mode="edge")
        avg = 0.25 * (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:])
        g = np.where(fixed, f, avg)
    return g


def upsample(a, factor, order=3):
    return ndimage.zoom(a, factor, order=order, mode="nearest", grid_mode=True).astype(np.float32)


def amp_field(xs, ys):
    from scipy.interpolate import RegularGridInterpolator
    rgi = RegularGridInterpolator((np.array(L.AMP_Y, float), np.array(L.AMP_X, float)),
                                  np.array(L.AMP, float), bounds_error=False, fill_value=None)
    return rgi(np.c_[ys.ravel(), xs.ravel()]).reshape(xs.shape).astype(np.float32)


# ------------------------------------------------------------------------------------------------
MOUNTAIN_SCALE = 0.78


def massifs(xs, ys, g):
    """Explicit peak/ridge network with concave (steep top, gentle foot) profiles."""
    wx = xs + N.fbm(g, 520.0, 211, 4) * 220.0 + N.fbm(g, 130.0, 212, 3) * 50.0
    wy = ys + N.fbm(g, 520.0, 213, 4) * 220.0 + N.fbm(g, 130.0, 214, 3) * 50.0
    M = np.zeros_like(xs)
    def cone(d, h, r):
        t = np.clip(1.0 - d / r, 0.0, 1.0)
        return h * (t ** 1.55 * 0.82 + t ** 4.0 * 0.18)
    for name, (px, py, ph, pr) in L.PEAKS.items():
        M = np.maximum(M, cone(np.hypot(wx - px, wy - py), ph, pr))
    for a, b, sag in L.RIDGES:
        ax, ay, ah, ar = L.PEAKS[a]
        bx, by, bh, br = L.PEAKS[b]
        vx, vy = bx - ax, by - ay
        ll = vx * vx + vy * vy
        t = np.clip(((wx - ax) * vx + (wy - ay) * vy) / ll, 0.0, 1.0)
        d = np.hypot(wx - (ax + t * vx), wy - (ay + t * vy))
        hh = (ah * (1 - t) + bh * t) * (1.0 - (1.0 - sag) * np.sin(np.pi * t) ** 0.8)
        rr = (ar * (1 - t) + br * t) * (1.0 - 0.25 * np.sin(np.pi * t))
        M = np.maximum(M, cone(d, hh, rr))
    # faceted, jagged rock: ridged multifractal modulated by the massif envelope
    R1 = N.ridged(g, 300.0, 221, octaves=7, sharp=2.3, warp_amp=110.0, warp_scale=380.0)
    R2 = N.ridged(g, 95.0, 222, octaves=4, sharp=2.0, warp_amp=30.0, warp_scale=120.0)
    env = smoothstep(0.0, 1.0, M / 200.0)
    M = M * MOUNTAIN_SCALE
    M = M * (0.72 + 0.34 * R1) + (R2 - 0.45) * 22.0 * env
    return np.maximum(M, 0).astype(np.float32)


def synth_base(step, water):
    log("synth base", step)
    g = grid(step)
    xs, ys = coords(step)
    sdf = floor_polygon_sdf(step)
    warp = N.fbm(g, 420.0, 11, 4) * 260.0 + N.fbm(g, 150.0, 12, 3) * 120.0 + N.fbm(g, 50.0, 13, 2) * 25.0

    # --- floor: harmonic river level + rise away from water + rolling undulations
    lev = upsample(harmonic_level_field(water), 16.0 / step, order=1)[: xs.shape[0], : xs.shape[1]]
    d_riv, idx, far = water.query(xs, ys, 600.0)
    half = (water.s["width"][idx] * 0.5).astype(np.float32)
    d_bank = np.maximum(d_riv - half, 0)
    lake_r = Water.lake_rnorm(xs, ys)
    d_lake = np.maximum((lake_r - 1.0) * 260.0, 0)
    d_w = np.minimum(d_bank, d_lake)
    und = (N.fbm(g, 520.0, 20, 3) * 12.0 + N.fbm(g, 170.0, 21, 4) * 4.0
           + N.fbm(g, 45.0, 22, 3) * 0.9) * smoothstep(5, 120, d_w)
    floor = lev + 1.1 + 15.0 * (1 - np.exp(-d_w / 360.0)) + und

    # --- NW hanging valley (terrace above the waterfall)
    t = L.TERRACE_NW
    xc = 0.5 * (t["x0"] + t["x1"])
    edge = (t["y_edge"] - 0.0013 * (xs - xc) ** 2 + N.fbm(g, 70.0, 31, 3) * 55.0
            + N.fbm(g, 20.0, 32, 2) * 10.0)
    winx = smoothstep(t["x0"] - 200, t["x0"] + 80, xs) * (1 - smoothstep(t["x1"] - 80, t["x1"] + 200, xs))
    cliff = smoothstep(edge + t["cliff_width"], edge - t["cliff_width"], ys)
    floor = floor + t["height"] * (0.8 + 0.4 * (N.fbm(g, 120.0, 33, 3) + 0.5)) * cliff * winx

    # --- mountains: warped ridged noise shaped by the envelope (stream power erodes it later)
    A = amp_field(xs, ys) * (1.0 + N.fbm(g, 600.0, 41, 3) * 0.22)
    R = N.ridged(g, 1100.0, 42, octaves=6, sharp=2.2, warp_amp=300.0, warp_scale=1400.0)
    Rs = N.fbm(g, 520.0, 43, 6) * 0.5 + 0.5                         # rounded hills (south)
    south = smoothstep(1700.0, 2200.0, ys)
    R = R * (1 - south) + Rs * south
    M = massifs(xs, ys, g)
    # keep the valley floor polygon free of mountain feet (soft)
    floor_keep = smoothstep(-160.0, 120.0, sdf + warp * 0.5)
    M = M * (0.15 + 0.85 * floor_keep)
    E = smoothstep(4.0, 160.0, M).astype(np.float32)

    # --- knolls / hills
    for kx, ky, kr, kh, kind in L.KNOLLS:
        d = np.hypot(xs - kx, ys - ky)
        if kind == "castle":
            # Rocca: gentle mound + three rocky lobes, flat bailey on the main lobe, cliffs to the SE
            n = N.fbm(g, 40.0, 51, 4)
            mound = smoothstep(kr * 3.0, 0.0, d + n * 30.0) ** 1.6 * 0.30
            core = np.zeros_like(d)
            for ox, oy, rr, hh in ((0, 0, kr, 1.0), (40, 30, kr * 0.62, 0.72), (-38, -22, kr * 0.55, 0.55)):
                dl = np.hypot(xs - kx - ox, ys - ky - oy) + n * rr * 0.35
                lobe = smoothstep(rr, rr * 0.45, dl) ** 0.75 * hh
                core = np.maximum(core, lobe)
            rock = (N.ridged(g, 22.0, 56, octaves=3, sharp=2.0) - 0.5) * 0.18
            M = M + kh * (mound + 0.70 * np.clip(core + rock * (core > 0.05), 0, 1.1))
        elif kind == "rocky":
            n = N.fbm(g, 35.0, 52, 3)
            prof = smoothstep(kr, 0.0, d + n * kr * 0.25) ** 1.4
            M = M + kh * prof * (0.85 + 0.3 * N.fbm(g, 25.0, 53, 3))
        else:
            prof = smoothstep(kr, 0.0, d) ** 1.6
            M = M + kh * prof * (1.0 + N.fbm(g, 80.0, 54, 2) * 0.3)

    h = floor + M
    erod = np.clip(smoothstep(0.02, 0.3, E), 0, 1).astype(np.float32)
    # terrace cliff and rocky knolls are erodible (natural cliff faces)
    erod = np.maximum(erod, 0.6 * (cliff * (1 - cliff) * 4.0 * winx))
    return h.astype(np.float32), E, erod, floor.astype(np.float32)


def apply_mesa(h, E, floor, xs, ys, g, step):
    mz = L.MESA
    img = Image.new("L", (xs.shape[1], xs.shape[0]), 0)
    ImageDraw.Draw(img).polygon([((px - X0) / step, (py - Y0) / step) for px, py in mz["polygon"]], fill=255)
    inside = np.array(img) > 127
    din = ndimage.distance_transform_edt(inside) * step - ndimage.distance_transform_edt(~inside) * step
    din = din + N.fbm(g, 160.0, 44, 4) * 70.0 + N.fbm(g, 30.0, 47, 3) * 10.0
    w = smoothstep(0.0, mz["cliff"], din)
    top = mz["top"] + N.fbm(g, 300.0, 45, 4) * 18.0 + N.fbm(g, 60.0, 46, 3) * 4.0
    # second rock band below the rim: two-step cliff
    w2 = smoothstep(-70.0, -70.0 + mz["cliff"], din)
    shelf = floor + (top - floor) * 0.55
    hm = np.maximum(h, shelf * w2 + h * (1 - w2))
    hm = hm * (1 - w) + np.maximum(top, h) * w
    return hm.astype(np.float32), np.maximum(E, w2).astype(np.float32)


def carve(h, xs, ys, water: Water, E, g, fine=False):
    """Carve riverbeds, banks, canyons and the lake. Returns h, water_z (nan = dry), info dict.

    Every river is processed separately and the results are combined, so confluences have no seams.
    """
    n_edge = N.fbm(g, 18.0, 61, 3) * 0.22 + N.fbm(g, 5.0, 62, 2) * 0.08
    k = np.maximum(0.22 + 0.9 * E + 0.2 * N.fbm(g, 60.0, 63, 3), 0.1)
    bed_noise = N.fbm(g, 9.0, 64, 3) * 0.45
    inf = np.float32(1e9)
    wall_min = np.full(h.shape, inf, np.float32)
    bed_min = np.full(h.shape, inf, np.float32)
    bank_lev = np.full(h.shape, -inf, np.float32)
    best_r = np.full(h.shape, inf, np.float32)
    water_z = np.full(h.shape, np.nan, np.float32)
    pts = np.c_[xs.ravel(), ys.ravel()]
    for name, r_ in water.rivers.items():
        tree = cKDTree(np.c_[r_["x"], r_["y"]])
        d, idx = tree.query(pts, distance_upper_bound=420.0, workers=-1)
        far = ~np.isfinite(d)
        idx[far] = 0
        d = np.where(far, 420.0, d).reshape(h.shape).astype(np.float32)
        idx = idx.reshape(h.shape)
        far = far.reshape(h.shape)
        lev = r_["level"][idx].astype(np.float32)
        half_e = (r_["width"][idx] * 0.5).astype(np.float32) * (1.0 + n_edge)
        dep = r_["depth"][idx].astype(np.float32)
        r = d / np.maximum(half_e, 0.5)
        dd = np.maximum(d - half_e, 0)
        wall = lev + 0.35 + dd * k + dd ** 1.7 * 0.01
        wall_min = np.where(far | (dd > 18.0), wall_min, np.minimum(wall_min, wall))
        inch = (~far) & (r < 1.0)
        bed = lev - dep * np.clip(1 - r * r, 0, 1) ** 0.55 - 0.25 + bed_noise * np.clip(1 - r, 0, 1)
        bed_min = np.where(inch, np.minimum(bed_min, bed), bed_min)
        take = inch & (r < best_r)
        water_z = np.where(take, lev, water_z)
        best_r = np.where(take, r, best_r)
        bank = (~far) & (r >= 1.0) & (d < half_e + 5.0)
        bank_lev = np.where(bank, np.maximum(bank_lev, lev + 0.18 + (d - half_e) * 0.08), bank_lev)
    in_any = bed_min < inf
    h = np.minimum(h, wall_min)
    h = np.where(in_any, np.minimum(h, bed_min), h)
    h = np.where((~in_any) & (bank_lev > -inf), np.maximum(h, bank_lev), h)

    # lake
    lr = Water.lake_rnorm(xs, ys) * (1.0 + N.fbm(g, 25.0, 65, 3) * 0.05)
    lake = lr < 1.0
    lake_bed = L.LAKE["level"] - 0.4 - L.LAKE["max_depth"] * np.clip((1 - lr) / 0.55, 0, 1) ** 0.8
    lake_bed += N.fbm(g, 14.0, 66, 3) * 0.6
    shore = (lr >= 1.0) & (lr < 1.06) & (~in_any)
    h = np.where(lake, np.minimum(h, lake_bed), h)
    h = np.where(shore, np.maximum(np.minimum(h, L.LAKE["level"] + 0.2 + (lr - 1.0) * 40.0),
                                   L.LAKE["level"] + 0.15), h)
    water_z = np.where(lake, L.LAKE["level"], water_z)

    info = {"lake_r": lr}
    return h.astype(np.float32), water_z, info


SP_ITERS = 45


def build(seed=1, quick=False):
    from terrain import streampower as SP
    water = Water()
    # ---------------- 8 m: base + stream power ----------------
    h8, E8, er8, floor8 = synth_base(8.0, water)
    xs8, ys8 = coords(8.0)
    g8 = grid(8.0)
    d, idx, far = water.query(xs8, ys8, 40.0)
    riv = (~far) & (d < 9.0)
    h8 = np.where(riv, np.minimum(h8, water.s["level"][idx] + 0.5), h8).astype(np.float32)
    fixed = (E8 < 0.015) | riv
    jit = (N.fbm(g8, 16.0, 99, 2) * 2.0).astype(np.float32)
    A8 = amp_field(xs8, ys8)
    U = (E8 * A8 * 1.5e-7).astype(np.float32)
    log("stream power 8m")
    h8, acc8 = SP.evolve(np.where(fixed, h8, h8 + jit), U, fixed, 8.0, iters=SP_ITERS,
                         K=1.5e-5, dt=3000.0, kd=0.02, log=log)
    h8, E8 = apply_mesa(h8, E8, floor8, xs8, ys8, g8, 8.0)
    er8 = np.maximum(er8, smoothstep(0.02, 0.3, E8)).astype(np.float32)

    # ---------------- 4 m: large gullies ----------------
    log("erosion 4m")
    xs4, ys4 = coords(4.0)
    h4 = upsample(h8, 2.0)[: xs4.shape[0], : xs4.shape[1]]
    er4 = upsample(er8, 2.0, 1)[: xs4.shape[0], : xs4.shape[1]]
    hc = (h4 / 4.0).astype(np.float32)
    hc = erosion.droplet_erosion(hc, er4, 150_000 if quick else 400_000, seed + 7, radius=3.0,
                                 lifetime=64, capacity=5.0, erode_speed=0.35, deposit_speed=0.2,
                                 max_erode=0.5)
    h8 = hc * 4.0  # (now 4 m data)

    # ---------------- 2 m: detail + droplet erosion ----------------
    log("upsample 2m")
    g2 = grid(2.0)
    xs2, ys2 = coords(2.0)
    h2 = upsample(h8, 2.0)[: xs2.shape[0], : xs2.shape[1]]
    E2 = upsample(E8, 4.0, 1)[: xs2.shape[0], : xs2.shape[1]]
    er2 = upsample(er8, 4.0, 1)[: xs2.shape[0], : xs2.shape[1]]
    detail = N.ridged(g2, 120.0, 71, octaves=5, sharp=2.0, warp_amp=40.0, warp_scale=200.0)
    h2 += (detail - 0.5) * 14.0 * E2 ** 1.5
    # crags: sharp rocky ridges at two scales on the mountains
    rockm = smoothstep(0.12, 0.5, E2)
    crag1 = N.ridged(g2, 70.0, 75, octaves=4, sharp=2.6, warp_amp=25.0, warp_scale=90.0)
    crag2 = N.ridged(g2, 18.0, 76, octaves=3, sharp=2.2)
    h2 += ((crag1 - 0.45) * 26.0 + (crag2 - 0.45) * 6.0) * rockm
    # rock benches: soft terraces with warped strata -> ledges that break long gullies
    tw = N.fbm(g2, 160.0, 72, 3) * 14.0 + N.fbm(g2, 40.0, 73, 2) * 4.0
    step_t = 21.0
    tt = (h2 + tw) / step_t
    fr = tt - np.floor(tt)
    sc = fr ** 3 / (fr ** 3 + (1 - fr) ** 3)
    terr = (np.floor(tt) + sc) * step_t - tw
    gy2, gx2 = np.gradient(h2, 2.0)
    steep2 = smoothstep(0.5, 1.1, np.hypot(gx2, gy2))
    bench = np.clip(N.fbm(g2, 300.0, 74, 3) * 0.8 + 0.55, 0, 1) * smoothstep(0.15, 0.6, E2) * steep2 * 0.5
    h2 = h2 * (1 - bench) + terr * bench
    log("erosion 2m")
    hc = (h2 / 2.0).astype(np.float32)
    hc = erosion.droplet_erosion(hc, er2, 200_000 if quick else 450_000, seed + 1, radius=3.0,
                                 lifetime=48, capacity=3.0, erode_speed=0.25, deposit_speed=0.3,
                                 max_erode=0.3)
    h2 = hc * 2.0
    h2 = erosion.thermal_erosion(h2 / 2.0, er2, talus=1.6, rate=0.1, iters=4) * 2.0

    # ---------------- 1 m: fine detail + hydrology carving ----------------
    log("upsample 1m")
    g1 = grid(1.0)
    xs1, ys1 = coords(1.0)
    h1 = upsample(h2, 2.0)[: xs1.shape[0], : xs1.shape[1]]
    E1 = upsample(E2, 2.0, 1)[: xs1.shape[0], : xs1.shape[1]]
    fine = N.ridged(g1, 9.0, 81, octaves=3, sharp=2.0)
    h1 += (fine - 0.5) * 2.2 * smoothstep(0.1, 0.45, E1)
    h1 += N.fbm(g1, 8.0, 82, 3) * 0.3
    log("carve 1m")
    h1, water_z, info = carve(h1, xs1, ys1, water, E1, g1, fine=True)
    acc1 = upsample(acc8, 8.0, 1)[: xs1.shape[0], : xs1.shape[1]]
    return {"h": h1, "water_z": water_z, "E": E1, "water": water, "info": info, "grid": g1,
            "xs": xs1, "ys": ys1, "acc": acc1}
