"""Build the King's Domain valley terrain and export it for Godot.

Usage:  python -m terrain.build_terrain [--quick] [--reuse]
Outputs:
  game/assets/terrain/color_RR_CC.webp   lit terrain colour (sRGB)            per 1024² chunk
  game/assets/terrain/light_RR_CC.png    lighting factor / 2 (for overlays)   per chunk
  game/assets/terrain/mat_RR_CC.png      detail weights R rock G soil B snow A forest floor
  game/assets/terrain/water_RR_CC.png    R depth  G,B screen flow  A foam
  game/assets/terrain/heightgrid.png     terrain altitude every 2 m (R high byte, G low byte, B water)
  game/data/valley/terrain.json          layout + mapping
  pipeline/.cache/terrain/*.npy          ground maps reused by the vegetation planner
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from kd import const as K  # noqa: E402
from terrain import heightmap as HM  # noqa: E402
from terrain import layout as L  # noqa: E402
from terrain import lighting as LT  # noqa: E402
from terrain import materials as MT  # noqa: E402
from terrain import noise as N  # noqa: E402
from terrain import project as PJ  # noqa: E402
from terrain.heightmap import smoothstep  # noqa: E402

CACHE = os.path.join(K.CACHE_DIR, "terrain")
OUT = os.path.join(K.GAME_DIR, "assets", "terrain")
log = HM.log


def tonemap(lin):
    x = np.maximum(lin, 0.0)
    knee = 0.78
    over = np.maximum(x - knee, 0.0)
    x = np.where(x > knee, knee + over / (1.0 + over / (1.0 - knee + 0.02)), x)
    return np.clip(x, 0.0, 1.0) ** (1 / 2.2)


def saturate(rgb, amount):
    l = (rgb * np.array([0.299, 0.587, 0.114], np.float32)).sum(-1, keepdims=True)
    return np.clip(l + (rgb - l) * amount, 0, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--reuse", action="store_true", help="reuse cached heightmap")
    ap.add_argument("--preview", action="store_true", help="only write the preview image")
    args = ap.parse_args()
    os.makedirs(CACHE, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    t0 = time.time()

    # ------------------------------------------------------------------ heightmap
    hpath = os.path.join(CACHE, "height.npz")
    water = HM.Water()
    g = HM.grid(1.0)
    xs, ys = HM.coords(1.0)
    if args.reuse and os.path.exists(hpath):
        z = np.load(hpath)
        h, water_z, E, acc = z["h"], z["water_z"], z["E"], z["acc"]
        log("reused heightmap")
    else:
        r = HM.build(quick=args.quick)
        h, water_z, E, acc = r["h"], r["water_z"], r["E"], r["acc"]
        np.savez(hpath, h=h, water_z=water_z, E=E, acc=acc)
    hpath_final = os.path.join(CACHE, "height_final.npy")
    # building platforms (castle plateau...)
    for cx, cy, rx, ry, alt, fall in L.FLATTEN:
        dn = np.sqrt(((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2)
        wgt = np.clip(1.0 - (dn - 1.0) * min(rx, ry) / fall, 0.0, 1.0)
        wgt = wgt * wgt * (3 - 2 * wgt)
        h = (h * (1 - wgt) + alt * wgt).astype(np.float32)
    wet = (np.isfinite(water_z) & (water_z > h)).astype(np.float32)
    depth = np.where(wet > 0, water_z - h, 0.0).astype(np.float32)
    wl = np.where(wet > 0, water_z, h)
    # remove isolated wet specks
    wet = ndimage.binary_opening(wet > 0, iterations=1).astype(np.float32)
    depth *= wet

    # nearest water info for every cell
    d_idx, idx, far = water.query(xs, ys, 600.0)
    lev = np.where(far, h - 50.0, water.s["level"][idx]).astype(np.float32)
    lake_r = HM.Water.lake_rnorm(xs, ys)
    near_lake = lake_r < 1.4
    lev = np.where(near_lake & (np.abs(h - L.LAKE["level"]) < np.abs(h - lev)), L.LAKE["level"], lev)
    above = (h - lev).astype(np.float32)
    d_water = (ndimage.distance_transform_edt(wet < 0.5)).astype(np.float32)

    # ------------------------------------------------------------------ lighting (ground space)
    log("lighting")
    hv = np.where(wet > 0, np.maximum(wl, h), h).astype(np.float32)
    nrm = LT.normals(h)
    cav = LT.cavity(h)
    shadow = LT.cast_shadow(hv)
    ao = LT.ambient_occlusion(hv)
    sx, sy, sz = K.sun_dir_world()
    # macro normals (large landforms) - the mountains read as big lit / shaded faces
    nrm_m = LT.normals(ndimage.gaussian_filter(h, 9.0))
    # ground-space lighting inputs, sampled per screen pixel later
    light_in = np.stack([nrm[0], nrm[1], nrm[2], shadow, ao, cav, nrm_m[0], nrm_m[1], nrm_m[2]],
                        -1).astype(np.float32)
    # relative light of the ground (for decals drawn over the terrain: fields, roads, squares)
    diff1 = np.clip((nrm[0] * sx + nrm[1] * sy + nrm[2] * sz + 0.10) / 1.10, 0, 1)
    flat = 1.78 * np.clip((sz + 0.10) / 1.10, 0, 1) + 0.56
    rel = (1.78 * diff1 * shadow + 0.56 * (0.55 + 0.45 * nrm[2]) * ao) / flat
    ground_light = (np.clip(rel[::2, ::2] / 1.5, 0, 1) * 255 + 0.5).astype(np.uint8)
    del diff1, rel, nrm_m

    # ------------------------------------------------------------------ materials
    log("materials")
    t = {"h": h, "E": E, "xs": xs, "ys": ys, "acc": acc, "above_water": above, "cavity_neg": cav}
    alb, weights, forest = MT.build(t, nrm, wet, depth, d_water, g)
    np.save(os.path.join(CACHE, "forest_density.npy"), forest["density"])
    np.save(os.path.join(CACHE, "forest_conifer.npy"), forest["conifer"])
    np.save(os.path.join(CACHE, "open_land.npy"), forest["open"])
    np.save(os.path.join(CACHE, "slope.npy"), forest["slope"])
    np.save(os.path.join(CACHE, "wet.npy"), wet)
    np.save(os.path.join(CACHE, "depth.npy"), depth)
    np.save(os.path.join(CACHE, "d_water.npy"), d_water)
    np.save(os.path.join(CACHE, "shadow.npy"), shadow)

    # ------------------------------------------------------------------ water data (ground)
    log("water data")
    s = water.s
    tx = s["tx"][idx].astype(np.float32)
    ty = s["ty"][idx].astype(np.float32)
    slope_w = np.clip(s["slope"][idx], 0, 5).astype(np.float32)
    in_lake = (lake_r < 1.02) & (wet > 0)
    # 0.5 calm river .. 2 rapids; >= 3.5 only on real falls (steep drops)
    speed = 0.5 + np.clip(slope_w * 14.0, 0, 1.5) + np.where(slope_w > 0.35, 2.0, 0.0)
    speed = np.where(in_lake, 0.08, speed).astype(np.float32)
    fx = tx
    fy = ty * K.SIN_EL + np.clip(slope_w, 0, 3) * K.COS_EL
    fl = np.maximum(np.hypot(fx, fy), 1e-4)
    fx, fy = fx / fl, fy / fl
    mag = np.clip(speed / 4.0, 0, 1)
    shore = smooth = np.clip(1.0 - depth / 0.7, 0, 1) * wet
    foam = np.clip(shore * 0.5 + np.clip((slope_w - 0.01) * 8.0, 0, 0.7) * wet, 0, 1)
    waterfall = (slope_w > 0.25) & (wet > 0)
    foam = np.where(waterfall, 0.8, foam)
    # foam and spray spreading around the foot of falls and cascades
    spray = ndimage.gaussian_filter(waterfall.astype(np.float32), 5.0) * 4.0
    foam = np.maximum(foam, np.clip(spray, 0, 1) * wet)
    water_ground = np.stack([np.sqrt(np.clip(depth / 16.0, 0, 1)) * wet, 0.5 + 0.5 * fx * mag,
                             0.5 + 0.5 * fy * mag, foam], -1).astype(np.float32)

    # ------------------------------------------------------------------ projection
    log("projection")
    P = K.TERRAIN_PX_PER_M
    vmin, vmax = PJ.screen_extent(hv, HM.Y0 + 0.5, 1.0, P)
    v_off = math.floor(vmin) - 2
    out_h = int(math.ceil(vmax - v_off)) + 4
    gy, gz = PJ.rasterize(hv, HM.X0 + 0.5, HM.Y0 + 0.5, 1.0, P, K.SIN_EL, K.COS_EL, float(v_off), out_h)
    r0, r1 = PJ.crop_rows(gy)
    log(f"raster {gy.shape}, crop rows {r0}..{r1}")
    gy = gy[r0:r1 + 1]
    gz = gz[r0:r1 + 1]
    v_off = v_off + r0
    Hs, Ws = gy.shape
    gx = np.broadcast_to(((np.arange(Ws) + 0.5) / P).astype(np.float32)[None, :], gy.shape).copy()

    def sample(img):
        if img.ndim == 2:
            img = img[..., None]
        return PJ.bilinear(np.ascontiguousarray(img, np.float32), gx, gy, HM.X0 + 0.5, HM.Y0 + 0.5, 1.0)

    alb_s = sample(alb)
    w_s = sample(weights)
    li = sample(light_in)
    wat_s = sample(water_ground)
    del light_in

    # per-pixel fine detail (sharper than the 1 m ground maps)
    log("fine detail")
    p = N.perm
    rock, soil, snow, forest_w = w_s[..., 0], w_s[..., 1], w_s[..., 2], w_s[..., 3]
    veg = np.clip(1 - rock - snow, 0, 1)
    # detail noise in "unfolded" coordinates: on steep faces turned to the camera the texture keeps
    # its density instead of stretching vertically
    gv = (gy - gz * (K.COS_EL / K.SIN_EL)).astype(np.float32)
    f1 = N.fbm_at(gx, gv, 1.1, p(601), 3, 2.0, 0.5)
    f2 = N.fbm_at(gx, gv, 3.5, p(602), 3, 2.0, 0.5)
    f3 = N.fbm_at(gx, gv, 22.0, p(603), 3, 2.0, 0.5)

    # detail normals: bump height (rock: crags 1-6 m, soil/grass: tiny undulations)
    e = 0.35
    def bump(x, y):
        r1 = N.fbm_at(x, y, 5.0, p(611), 3, 2.1, 0.55)
        r2 = N.fbm_at(x, y, 1.6, p(612), 2, 2.0, 0.5)
        # crags: ridged noise -> sharp crests and cracks on rock faces
        r1 = r1 * 0.6 + (0.5 - np.abs(N.fbm_at(x, y, 7.5, p(613), 3, 2.0, 0.5))) * 0.9
        return r1, r2
    r1x, r2x = bump(gx + e, gv)
    r1y, r2y = bump(gx, gv + e)
    r10, r20 = bump(gx, gv)
    amp_r = rock * 3.4 + snow * 0.6 + veg * 0.25
    amp_f = rock * 0.30 + veg * 0.12 + snow * 0.15
    ddx = ((r1x - r10) * amp_r + (r2x - r20) * amp_f) / e
    ddy = ((r1y - r10) * amp_r + (r2y - r20) * amp_f) / e
    del r1x, r2x, r1y, r2y, r10, r20
    nx_ = li[..., 0] - ddx * li[..., 2]
    ny_ = li[..., 1] - ddy * li[..., 2]
    nz_ = li[..., 2]
    nl = np.sqrt(nx_ * nx_ + ny_ * ny_ + nz_ * nz_)
    nx_ /= nl
    ny_ /= nl
    nz_ /= nl
    ndl = nx_ * sx + ny_ * sy + nz_ * sz
    diffuse = np.clip((ndl + 0.10) / 1.10, 0, 1)
    # rock and snow: half of the light from the large landform, with more contrast (painterly facets)
    ndl_m = li[..., 6] * sx + li[..., 7] * sy + li[..., 8] * sz
    diff_m = np.clip((ndl_m + 0.10) / 1.10, 0, 1)
    km = np.clip(rock + snow, 0, 1) * 0.42
    diffuse = diffuse * (1 - km) + diff_m * km
    diffuse = np.clip(diffuse + (diffuse - 0.55) * 0.25 * np.clip(rock + snow, 0, 1), 0, 1)
    del ndl_m, diff_m, km
    shadow_s, ao_s, cav_s = li[..., 3], li[..., 4], li[..., 5]
    skyf = 0.55 + 0.45 * nz_
    sun_c = np.array(K.SUN_COLOR, np.float32)
    sky_c = np.array(K.SKY_COLOR, np.float32)
    I_SUN, I_SKY = 1.78, 0.56
    light_s = (sun_c * (I_SUN * diffuse * shadow_s)[..., None] + sky_c * (I_SKY * skyf * ao_s)[..., None])
    light_s *= np.clip(1.0 + cav_s * (0.10 + 0.08 * rock), 0.70, 1.25)[..., None]
    del nx_, ny_, nz_, nl, ndl, diffuse, skyf, li

    mod = 1.0 + veg * (0.09 * f1 + 0.07 * f2) + forest_w * 0.10 * f1
    strata = np.sin((gz + f3 * 9.0) * (2 * math.pi / 11.0)) * 0.5 + 0.5
    # rock: structure at the scale of slabs and benches, little per-texel noise (no "gravel" speckle)
    streak = N.fbm_at(gx * 0.9, gv * 0.10, 2.5, p(604), 3, 2.0, 0.5)    # water stains down the faces
    mod += rock * (0.10 * (strata - 0.5) + 0.04 * f1 + 0.12 * f2 + 0.10 * streak)
    del streak
    mod += snow * 0.03 * f2
    col = alb_s * mod[..., None] * light_s
    srgb = saturate(tonemap(col), 1.0)

    # ------------------------------------------------------------------ export
    color8 = (srgb * 255 + 0.5).astype(np.uint8)
    Image.fromarray(color8).resize((Ws // 4, Hs // 4), Image.LANCZOS).save(
        os.path.join(CACHE, "projected_preview.png"))
    Image.fromarray(color8).save(os.path.join(CACHE, "projected_full.png"))
    if args.preview:
        log("preview only")
        return
    log("export chunks")
    C = K.TERRAIN_CHUNK_PX
    rows = math.ceil(Hs / C)
    cols = math.ceil(Ws / C)
    for f in os.listdir(OUT):
        if f.split("_")[0] in ("color", "light", "mat", "water"):
            os.remove(os.path.join(OUT, f))
    light8 = (np.clip(light_s / 2.0, 0, 1) ** (1 / 2.2) * 255 + 0.5).astype(np.uint8)
    mat8 = (np.clip(w_s, 0, 1) * 255 + 0.5).astype(np.uint8)
    wat8 = (np.clip(wat_s, 0, 1) * 255 + 0.5).astype(np.uint8)
    wat8[..., 1:3] = np.where(wat8[..., :1] == 0, 128, wat8[..., 1:3])
    PAD = 4
    chunks = []

    def cut(a, y0, y1, x0, x1):
        """Slice with PAD overlap; outside the image the edge pixels are replicated."""
        Hh, Ww = a.shape[:2]
        ys0, ys1 = max(y0 - PAD, 0), min(y1 + PAD, Hh)
        xs0, xs1 = max(x0 - PAD, 0), min(x1 + PAD, Ww)
        part = a[ys0:ys1, xs0:xs1]
        pw = [(ys0 - (y0 - PAD), (y1 + PAD) - ys1), (xs0 - (x0 - PAD), (x1 + PAD) - xs1)]
        if a.ndim == 3:
            pw.append((0, 0))
        return np.pad(part, pw, mode="edge")

    for rr in range(rows):
        for cc in range(cols):
            y0, y1 = rr * C, min((rr + 1) * C, Hs)
            x0, x1 = cc * C, min((cc + 1) * C, Ws)
            tag = f"{rr:02d}_{cc:02d}"
            Image.fromarray(cut(color8, y0, y1, x0, x1)).save(os.path.join(OUT, f"color_{tag}.webp"),
                                                              quality=92, method=6)
            Image.fromarray(cut(light8, y0, y1, x0, x1)).save(os.path.join(OUT, f"light_{tag}.webp"),
                                                              quality=90, method=6)
            Image.fromarray(cut(mat8, y0, y1, x0, x1), "RGBA").save(os.path.join(OUT, f"mat_{tag}.png"),
                                                                     optimize=True)
            wpart = cut(wat8, y0, y1, x0, x1)
            has_water = bool(wpart[..., 0].max() > 0)
            if has_water:
                Image.fromarray(wpart, "RGBA").save(os.path.join(OUT, f"water_{tag}.png"), optimize=True)
            chunks.append({"row": rr, "col": cc, "tag": tag, "x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0,
                           "water": has_water})
    # height grid every 2 m (terrain altitude, water flag)
    h2 = h[::2, ::2]
    w2 = wet[::2, ::2]
    q = np.clip(np.round(h2 * 32.0), 0, 65535).astype(np.uint16)
    hg = np.stack([(q >> 8).astype(np.uint8), (q & 255).astype(np.uint8),
                   (w2 > 0.5).astype(np.uint8) * 255], -1)
    Image.fromarray(hg, "RGB").save(os.path.join(OUT, "heightgrid.png"), optimize=True)
    Image.fromarray(ground_light, "L").save(os.path.join(OUT, "groundlight.png"), optimize=True)
    wl2 = np.where(wet > 0, wl, 0)[::2, ::2]
    qw = np.clip(np.round(wl2 * 32.0), 0, 65535).astype(np.uint16)
    Image.fromarray(np.stack([(qw >> 8).astype(np.uint8), (qw & 255).astype(np.uint8),
                              np.zeros_like(qw, np.uint8)], -1), "RGB").save(
        os.path.join(OUT, "watergrid.png"), optimize=True)

    meta = {
        "px_per_m": P,
        "chunk_px": C,
        "pad_px": PAD,
        "width_px": Ws,
        "height_px": Hs,
        "v_offset_px": v_off,
        "rows": rows,
        "cols": cols,
        "chunks": chunks,
        "world": {"x0": HM.X0, "y0": HM.Y0, "w": HM.W, "h": HM.H},
        "heightgrid": {"file": "heightgrid.png", "water_file": "watergrid.png", "light_file": "groundlight.png",
                       "cell_m": 2.0,
                       "x0": HM.X0 + 0.5, "y0": HM.Y0 + 0.5, "nx": int(h2.shape[1]),
                       "ny": int(h2.shape[0]), "scale": 1.0 / 32.0},
    }
    os.makedirs(os.path.join(K.GAME_DIR, "data", "valley"), exist_ok=True)
    with open(os.path.join(K.GAME_DIR, "data", "valley", "terrain.json"), "w") as f:
        json.dump(meta, f, indent=1)
    np.save(os.path.join(CACHE, "hv.npy"), hv)
    np.save(os.path.join(CACHE, "h_final.npy"), h)
    log(f"done in {time.time() - t0:.0f}s  ({Ws}x{Hs}px, {rows}x{cols} chunks)")


if __name__ == "__main__":
    main()
