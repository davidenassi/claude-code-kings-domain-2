"""Illustrated mountain sprites for the medieval map (prerendered, shading and snow embedded).

Run with Blender's bundled Python (numpy):
  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\5.2\\python\\bin\\python.exe" tools/art/draw_mountains.py
Output: assets/environment/mountains/mountain_atlas.png + .json

Each sprite is a small procedural heightfield seen from a light 3/4 view (painter's algorithm, nearer rows drawn
last), lit from the upper left. The footprint is normalised: the sprite pivot is the footprint centre and sizes are
in footprint widths, so the map layer scales each instance to its width in metres.
Classes: "hill" (green rounded mound), "peak" (rock with a snowy tip), "snowpeak" (high, snow-covered).
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "worldgen"))
from kdio import write_png  # noqa: E402
from kdnoise import Perlin, fbm  # noqa: E402

N = 220            # heightfield cells across the footprint
PX = 384           # final sprite pixels per footprint width (a mountain fills the screen at regional zoom:
                   # at 200 px the peaks came out soft and pixellated once stretched to their real width)
SS = 2             # supersampling
TILT = 0.55        # ground depth compression of the 3/4 view
OUT_DIR = os.path.join(ROOT, "assets", "environment", "mountains")
VARIANTS = 4

CLASSES = {
    #            relief height, ridges, peakiness, snowline (fraction of max height)
    "hill":     dict(height=0.22, ridge=0.25, power=1.25, snow=9.0, summits=(2, 3)),
    "peak":     dict(height=0.60, ridge=0.9, power=1.5, snow=0.78, summits=(1, 3)),
    "snowpeak": dict(height=0.85, ridge=1.0, power=1.6, snow=0.40, summits=(1, 2)),
}


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def heightfield(cls, variant):
    cfg = CLASSES[cls]
    rng = np.random.default_rng(abs(hash_str("%s-%d" % (cls, variant))))
    per = Perlin(int(rng.integers(1 << 30)))
    s = np.linspace(-1.0, 1.0, N)
    u, v = np.meshgrid(s, s)
    wu = u + 0.18 * fbm(per, u * 1.3 + 3.1, v * 1.3, octaves=3)
    wv = v + 0.18 * fbm(per, u * 1.3 - 5.7, v * 1.3 + 1.9, octaves=3)
    h = np.zeros_like(u)
    k = int(rng.integers(cfg["summits"][0], cfg["summits"][1] + 1))
    for i in range(k):
        if i == 0:
            cx, cy, rad, amp = rng.uniform(-0.1, 0.1), rng.uniform(-0.05, 0.1), 0.92, 1.0
        else:
            cx, cy = rng.uniform(-0.5, 0.5), rng.uniform(-0.3, 0.35)
            rad, amp = rng.uniform(0.45, 0.65), rng.uniform(0.5, 0.8)
        dx, dy = (wu - cx) / rad, (wv - cy) / (rad * 0.85)
        r = np.sqrt(dx * dx + dy * dy)
        cone = np.clip(1.0 - r, 0.0, 1.0) ** cfg["power"]
        ang = np.arctan2(dy, dx)
        ridges = 1.0 - np.abs(np.sin(ang * rng.uniform(2.5, 3.5) + 2.2 * fbm(per, dx * 1.5 + i, dy * 1.5, octaves=3)))
        cone *= 1.0 - cfg["ridge"] * 0.5 * (1.0 - ridges) * np.clip(r * 1.6, 0.0, 1.0)
        h = np.maximum(h, cone * amp)
    h += 0.035 * fbm(per, u * 3.0, v * 3.0, octaves=2) * np.clip(h * 4.0, 0.0, 1.0)
    h = np.clip(h, 0.0, None)
    return h / max(h.max(), 1e-6), per



def box(a, r):
    out = a.copy()
    for ax in (0, 1):
        acc = np.zeros_like(out)
        for k in range(-r, r + 1):
            acc += np.roll(out, k, axis=ax)
        out = acc / (2 * r + 1)
    return out


def hash_str(s):
    v = 2166136261
    for ch in s.encode():
        v = ((v ^ ch) * 16777619) & 0xFFFFFFFF
    return v


def shade(cls, h, per):
    cfg = CLASSES[cls]
    rel_h = cfg["height"]
    cell = 2.0 / N
    gy, gx = np.gradient(h * rel_h, cell)
    n = np.dstack([-gx * 1.4, -gy * 1.4, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    light = np.array([-0.62, -0.42, 0.66])
    light /= np.linalg.norm(light)
    lam = np.clip((n * light).sum(axis=2), 0.0, 1.0)
    lit = np.clip((lam - 0.35) / 0.5, 0.0, 1.0)
    s = np.linspace(-1.0, 1.0, N)
    u, v = np.meshgrid(s, s)
    brush = fbm(per, u * 3.5 + 11.0, v * 3.5, octaves=2)
    # cavities (concave) darker: painted crevices along valleys
    lap = (np.roll(h, 1, 0) + np.roll(h, -1, 0) + np.roll(h, 1, 1) + np.roll(h, -1, 1) - 4.0 * h) / (cell * cell)
    cav = np.clip(box(lap, 2) * 0.003, -0.18, 0.18)
    if cls == "hill":
        dark, mid, light_c = hexc("#46552E"), hexc("#7D8A48"), hexc("#B9B872")
    else:
        dark, mid, light_c = hexc("#4A4540"), hexc("#8A7F6E"), hexc("#D3C7AE")
    t = np.clip(lit + 0.10 * brush + cav, 0.0, 1.0)
    col = np.where((t < 0.5)[..., None], dark + (mid - dark) * (t / 0.5)[..., None],
                   mid + (light_c - mid) * ((t - 0.5) / 0.5)[..., None])
    if cls != "hill":
        # grassy / wooded lower slopes blend into the terrain
        low = np.clip((0.30 - h) / 0.25, 0.0, 1.0) ** 1.2
        green = hexc("#5F6F3A") + (hexc("#A3A865") - hexc("#5F6F3A")) * t[..., None]
        col = col + (green - col) * (low * 0.85)[..., None]
        slope = 1.0 - n[..., 2]
        snow_t = h + 0.08 * brush + 0.12 * lit - cfg["snow"]
        snow = np.clip(snow_t / 0.06, 0.0, 1.0) * np.clip(1.0 - (slope - 0.55) / 0.25, 0.0, 1.0)
        snow_col = hexc("#9FAEC4") + (hexc("#F7F5EE") - hexc("#9FAEC4")) * np.clip(lit * 1.2 + 0.1 * brush, 0, 1)[..., None]
        col = col + (snow_col - col) * snow[..., None]
    return np.clip(col, 0.0, 1.0)


def render(cls, variant):
    h, per = heightfield(cls, variant)
    col = shade(cls, h, per)
    rel_h = CLASSES[cls]["height"]
    res = PX * SS
    # screen coordinates in footprint widths: x = (u+1)/2, y_ground = (v+1)/2*TILT, lift = h*rel_h/2
    top = -rel_h * 0.5 - 0.02
    bottom = TILT + 0.02
    rows = int(math.ceil((bottom - top) * res))
    img = np.zeros((rows, res, 3))
    hit = np.zeros((rows, res))
    xs = ((np.arange(res) + 0.5) / res * N - 0.5)
    ci = np.clip(np.round(xs).astype(int), 0, N - 1)
    py = (np.arange(rows) + 0.5) / res + top
    for j in range(N):
        g = (j + 0.5) / N * TILT
        hj = h[j, ci]
        sy = g - hj * rel_h * 0.5
        m = (py[:, None] >= sy[None, :]) & (py[:, None] <= g + 1.5 / N) & (hj[None, :] > 0.004)
        img = np.where(m[..., None], col[j, ci][None, :, :], img)
        hit = np.where(m, hj[None, :], hit)
    alpha = np.clip(hit / 0.10, 0.0, 1.0) ** 1.5
    # downsample (premultiplied)
    rgb = (img * alpha[..., None]).reshape(rows // SS, SS, PX, SS, 3).mean(axis=(1, 3)) if rows % SS == 0 else None
    if rgb is None:
        rows -= rows % SS
        img, alpha = img[:rows], alpha[:rows]
        rgb = (img * alpha[..., None]).reshape(rows // SS, SS, PX, SS, 3).mean(axis=(1, 3))
    a = alpha.reshape(rows // SS, SS, PX, SS).mean(axis=(1, 3))
    rgb = np.where(a[..., None] > 1e-4, rgb / np.maximum(a, 1e-4)[..., None], 0.0)
    pivot = (PX * 0.5, (TILT * 0.5 - top) * PX)
    return np.concatenate([rgb, a[..., None]], axis=-1), pivot


def trim(img, pivot, margin=1):
    ys, xs = np.nonzero(img[..., 3] > 0.01)
    x0, x1 = max(xs.min() - margin, 0), min(xs.max() + margin + 1, img.shape[1])
    y0, y1 = max(ys.min() - margin, 0), min(ys.max() + margin + 1, img.shape[0])
    return img[y0:y1, x0:x1], (pivot[0] - x0, pivot[1] - y0)


def main():
    sprites = []
    for cls in CLASSES:
        for v in range(VARIANTS):
            img, piv = render(cls, v)
            img, piv = trim(img, piv)
            sprites.append({"class": cls, "variant": v, "img": img, "pivot": piv})
    sprites.sort(key=lambda s: -s["img"].shape[0])
    width = 2048
    x = y = shelf = 0
    for s in sprites:
        h, w, _ = s["img"].shape
        if x + w + 2 > width:
            x, y, shelf = 0, y + shelf + 2, 0
        s["pos"] = (x, y)
        x += w + 2
        shelf = max(shelf, h)
    height = 1 << (y + shelf + 2 - 1).bit_length()
    atlas = np.zeros((height, width, 4))
    entries = []
    for s in sprites:
        h, w, _ = s["img"].shape
        px, py = s["pos"]
        atlas[py:py + h, px:px + w] = s["img"]
        entries.append({"class": s["class"], "variant": s["variant"], "rect": [px, py, w, h],
                        "pivot": [round(s["pivot"][0], 2), round(s["pivot"][1], 2)],
                        "size_rel": [round(w / PX, 4), round(h / PX, 4)]})
    a = atlas[..., 3]
    rgb = atlas[..., :3]
    for _ in range(3):
        m = a < 0.01
        acc = np.zeros_like(rgb)
        cnt = np.zeros(a.shape)
        for ax in (0, 1):
            for sgn in (1, -1):
                sa = np.roll(a, sgn, axis=ax) >= 0.01
                acc += np.roll(rgb, sgn, axis=ax) * sa[..., None]
                cnt += sa
        fill = m & (cnt > 0)
        rgb[fill] = acc[fill] / cnt[fill][:, None]
        a = np.where(fill, 0.011, a)
    out = np.clip(np.concatenate([rgb, atlas[..., 3:4]], axis=-1) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    os.makedirs(OUT_DIR, exist_ok=True)
    write_png(os.path.join(OUT_DIR, "mountain_atlas.png"), out)
    with open(os.path.join(OUT_DIR, "mountain_atlas.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"version": 1, "atlas": "mountain_atlas.png", "width": width, "height": height,
                   "pixels_per_footprint": PX, "sprites": entries}, f, indent=1)
    prev_dir = os.path.join(HERE, "out_preview")
    os.makedirs(prev_dir, exist_ok=True)
    bg = hexc("#9DB065")
    comp = atlas[..., :3] * atlas[..., 3:4] + bg * (1.0 - atlas[..., 3:4])
    write_png(os.path.join(prev_dir, "mountains.png"), (comp * 255).astype(np.uint8))
    print("atlas", width, height, len(entries))


if __name__ == "__main__":
    main()

