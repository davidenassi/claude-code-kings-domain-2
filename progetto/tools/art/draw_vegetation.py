"""Painterly vegetation sprites for the illustrated map (light 3/4 view, depth only suggested).

Run with Blender's bundled Python (numpy):
  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\5.2\\python\\bin\\python.exe" tools/art/draw_vegetation.py
Output: assets/environment/vegetation/vegetation_atlas.png + .json

Style (art reference: illustrated medieval map mockup): conifers as stacked jagged layers, broadleaf trees as clumpy
round crowns, light from the upper left, soft brush mottling, a small soft shadow on the ground to the right.
Kinds: "tree" (single, close zoom), "cluster" (group of trees, mid/far zoom), "rock", "bush".
"""
import json
import math
import os
import random
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "worldgen"))
from kdio import write_png  # noqa: E402
from kdnoise import Perlin  # noqa: E402

PPM = 8.0          # final pixels per metre (single trees)
SS = 3             # supersampling
OUT_DIR = os.path.join(ROOT, "assets", "environment", "vegetation")
NOISE = Perlin(4242)


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


class Canvas:
    """Metric canvas: x to the right, y DOWN (screen), ground contact of objects at a given y."""

    def __init__(self, w_m, h_m, ppm=PPM):
        self.ppm = ppm
        self.w = int(math.ceil(w_m * ppm)) * SS
        self.h = int(math.ceil(h_m * ppm)) * SS
        self.rgb = np.zeros((self.h, self.w, 3))
        self.a = np.zeros((self.h, self.w))
        ys, xs = np.mgrid[0:self.h, 0:self.w]
        self.x = (xs + 0.5) / (ppm * SS)
        self.y = (ys + 0.5) / (ppm * SS)
        self.aa = 1.2 / (ppm * SS)

    def over(self, cover, color):
        a = np.clip(cover, 0.0, 1.0)
        col = color if np.ndim(color) == 3 else np.broadcast_to(color, self.rgb.shape)
        out_a = a + self.a * (1.0 - a)
        num = col * a[..., None] + self.rgb * (self.a * (1.0 - a))[..., None]
        self.rgb = np.where(out_a[..., None] > 1e-6, num / np.maximum(out_a, 1e-6)[..., None], 0.0)
        self.a = out_a

    def mottle(self, scale, seed):
        return NOISE.noise(self.x / scale + seed * 13.1, self.y / scale - seed * 7.7) / 0.7

    def result(self):
        h, w = self.h // SS, self.w // SS
        pre = (self.rgb * self.a[..., None]).reshape(h, SS, w, SS, 3).mean(axis=(1, 3))
        a = self.a.reshape(h, SS, w, SS).mean(axis=(1, 3))
        rgb = np.where(a[..., None] > 1e-4, pre / np.maximum(a, 1e-4)[..., None], 0.0)
        return np.concatenate([rgb, a[..., None]], axis=-1)


def ground_shadow(c, bx, by, radius, strength=0.30):
    dx = (c.x - (bx + radius * 0.55)) / (radius * 1.15)
    dy = (c.y - (by + radius * 0.05)) / (radius * 0.42)
    d = np.sqrt(dx * dx + dy * dy)
    c.over(np.clip(1.0 - d, 0.0, 1.0) ** 0.8 * strength, np.array([0.10, 0.12, 0.06]))


def trunk(c, bx, by, height, width, color=(0.33, 0.24, 0.16)):
    inside = (np.abs(c.x - bx) < width * 0.5) & (c.y < by) & (c.y > by - height)
    shade = np.where(c.x < bx, 1.1, 0.8)
    col = np.array(color)[None, None, :] * shade[..., None]
    c.over(inside.astype(float), col)


def conifer(c, bx, by, height, width, base, light, rng):
    """Stacked jagged layers, lighter on the left and on each layer's upper edge."""
    ground_shadow(c, bx, by, width * 0.55)
    trunk(c, bx, by, height * 0.18, max(width * 0.10, 0.25))
    layers = rng.choice([3, 4, 4, 5])
    top = by - height
    bottom = by - height * 0.12
    seed = rng.random() * 100
    for i in range(layers):
        t0 = i / layers
        t1 = (i + 1.35) / layers
        yt = top + (bottom - top) * t0 * 0.92
        yb = min(top + (bottom - top) * t1, bottom)
        half = width * 0.5 * (0.35 + 0.65 * (i + 1) / layers)
        rel = np.clip((c.y - yt) / max(yb - yt, 1e-3), 0.0, 1.0)
        jag = 0.12 * width * np.abs(np.sin((c.y - yt) * 9.0 + seed + i)) + 0.06 * width * c.mottle(0.5, seed + i)
        edge = half * rel + jag * rel - np.abs(c.x - bx)
        cover = np.clip(edge / c.aa, 0.0, 1.0) * ((c.y >= yt) & (c.y <= yb))
        side = np.clip(0.5 - (c.x - bx) / (half * 2.0 + 1e-3), 0.0, 1.0)
        upper = 1.0 - rel
        m = c.mottle(0.35, seed + i * 3)
        k = np.clip(0.25 + 0.55 * side + 0.25 * upper + 0.12 * m, 0.0, 1.0)
        col = base[None, None, :] * (1.0 - k[..., None]) + light[None, None, :] * k[..., None]
        c.over(cover, col)


def broadleaf(c, bx, by, height, crown_r, base, light, rng):
    """Clumpy round crown on a short trunk."""
    ground_shadow(c, bx, by, crown_r * 0.9)
    trunk(c, bx, by, height * 0.45, max(crown_r * 0.18, 0.3))
    cy = by - height + crown_r
    seed = rng.random() * 100
    blobs = [(0.0, 0.0, 1.0)]
    for _ in range(rng.randint(3, 5)):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.35, 0.6)
        blobs.append((math.cos(a) * d, math.sin(a) * d * 0.8, rng.uniform(0.5, 0.72)))
    blobs.sort(key=lambda b: b[1])
    for (ox, oy, rs) in blobs:
        r = crown_r * rs
        px, py = bx + ox * crown_r, cy + oy * crown_r
        nx = (c.x - px) / r
        ny = (c.y - py) / r
        d = np.sqrt(nx * nx + ny * ny) * (1.0 + 0.10 * c.mottle(0.45, seed))
        cover = np.clip((1.0 - d) * r / c.aa, 0.0, 1.0)
        lit = np.clip(0.55 - 0.45 * nx - 0.55 * ny + 0.15 * c.mottle(0.3, seed + ox), 0.0, 1.0)
        col = base[None, None, :] * (1.0 - lit[..., None]) + light[None, None, :] * lit[..., None]
        c.over(cover, col)


def rock(c, bx, by, size, rng):
    ground_shadow(c, bx, by, size * 0.7, 0.25)
    seed = rng.random() * 100
    cy = by - size * 0.35
    nx = (c.x - bx) / (size * 0.6)
    ny = (c.y - cy) / (size * 0.42)
    ang = np.arctan2(ny, nx)
    r = 1.0 + 0.15 * np.sin(ang * 3 + seed) + 0.08 * np.sin(ang * 7 + seed * 2)
    d = np.sqrt(nx * nx + ny * ny) / r
    cover = np.clip((1.0 - d) * size * 0.4 / c.aa, 0.0, 1.0) * (c.y < by)
    lit = np.clip(0.55 - 0.5 * nx - 0.5 * ny + 0.1 * c.mottle(0.3, seed), 0.0, 1.0)
    col = hexc("#6F6A60")[None, None, :] * (1 - lit[..., None]) + hexc("#C9C2B2")[None, None, :] * lit[..., None]
    c.over(cover, col)


# ---------------------------------------------------------------------------------------------
PALETTES = {
    "pine": (hexc("#1F3A26"), hexc("#5E8A4A")),
    "spruce": (hexc("#1B3322"), hexc("#4C7443")),
    "oak": (hexc("#304F20"), hexc("#86A84E")),
    "beech": (hexc("#3B5C22"), hexc("#97B558")),
    "birch": (hexc("#4A6B2A"), hexc("#AFC56A")),
    "autumn": (hexc("#6B5A22"), hexc("#D1B155")),
    "olive": (hexc("#55603A"), hexc("#B6BE86")),
    "cypress": (hexc("#1E3624"), hexc("#557B45")),
    "bush": (hexc("#3F5F2A"), hexc("#94B45A")),
}


def draw_species(c, species, bx, by, rng, scale=1.0):
    base, light = PALETTES[species]
    jitter = rng.uniform(0.9, 1.08)
    base, light = base * jitter, light * jitter
    if species in ("pine", "spruce"):
        h = rng.uniform(10, 14) * scale
        conifer(c, bx, by, h, h * (0.42 if species == "pine" else 0.36), base, light, rng)
    elif species == "cypress":
        h = rng.uniform(9, 11) * scale
        conifer(c, bx, by, h, h * 0.22, base, light, rng)
    elif species == "bush":
        broadleaf(c, bx, by, 2.4 * scale, 1.3 * scale, base, light, rng)
    else:
        r = {"oak": 3.6, "beech": 3.1, "birch": 2.4, "autumn": 3.2, "olive": 2.6}[species] * rng.uniform(0.9, 1.1) * scale
        broadleaf(c, bx, by, r * 2.7, r, base, light, rng)


SINGLES = [("pine", 3), ("spruce", 2), ("oak", 3), ("beech", 2), ("birch", 2), ("autumn", 1), ("olive", 2),
           ("cypress", 1), ("bush", 2)]
CLUSTERS = {
    "cl_conifer": [("pine", 5), ("spruce", 4), ("birch", 1)],
    "cl_broadleaf": [("oak", 5), ("beech", 3), ("birch", 2)],
    "cl_mixed": [("pine", 3), ("oak", 3), ("spruce", 2), ("beech", 2)],
    "cl_mediterranean": [("olive", 4), ("cypress", 2), ("pine", 2), ("bush", 2)],
    "cl_scrub": [("bush", 5), ("oak", 2), ("birch", 1)],
}


def weighted(rng, table):
    total = sum(w for _, w in table)
    r = rng.uniform(0, total)
    for sp, w in table:
        r -= w
        if r <= 0:
            return sp
    return table[-1][0]


def make_single(species, variant):
    rng = random.Random("%s-%d" % (species, variant))
    c = Canvas(12, 16)
    bx, by = 5.0, 14.5
    draw_species(c, species, bx, by, rng)
    return c.result(), (bx * PPM, by * PPM), PPM


def make_cluster(kind, variant):
    rng = random.Random("%s-%d" % (kind, variant))
    ppm = PPM * 0.5
    c = Canvas(30, 24, ppm)
    cx, gy = 14.0, 17.0
    n = rng.randint(11, 16)
    pts = []
    for _ in range(n):
        a = rng.uniform(0, math.tau)
        d = math.sqrt(rng.random())
        pts.append((cx + math.cos(a) * d * 8.0, gy + math.sin(a) * d * 3.6))
    pts.sort(key=lambda p: p[1])
    for (px, py) in pts:
        draw_species(c, weighted(rng, CLUSTERS[kind]), px, py, rng, scale=rng.uniform(0.85, 1.1))
    return c.result(), (cx * ppm, gy * ppm), ppm


def make_rock(variant, big):
    rng = random.Random("rock-%d-%d" % (variant, big))
    c = Canvas(8, 6)
    rock(c, 3.5, 5.0, 4.0 if big else 2.2, rng)
    return c.result(), (3.5 * PPM, 5.0 * PPM), PPM


def make_stump(variant):
    rng = random.Random("stump-%d" % variant)
    c = Canvas(3, 2.4)
    bx, by = 1.4, 1.9
    ground_shadow(c, bx, by, 0.8, 0.25)
    r = rng.uniform(0.42, 0.55)
    h = rng.uniform(0.35, 0.55)
    # side of the stump
    side = (np.abs(c.x - bx) < r) & (c.y < by) & (c.y > by - h)
    c.over(side.astype(float), np.array([0.36, 0.25, 0.16]) * np.where(c.x < bx, 1.1, 0.8)[..., None])
    # cut face
    d = np.sqrt(((c.x - bx) / r) ** 2 + ((c.y - (by - h)) / (r * 0.45)) ** 2)
    rings = 0.85 + 0.15 * np.sin(d * 18.0)
    c.over(np.clip((1.0 - d) * r / c.aa, 0, 1), hexc("#C9A36E")[None, None, :] * rings[..., None])
    return c.result(), (bx * PPM, by * PPM), PPM


def trim(img, pivot, margin=1):
    ys, xs = np.nonzero(img[..., 3] > 0.01)
    x0, x1 = max(xs.min() - margin, 0), min(xs.max() + margin + 1, img.shape[1])
    y0, y1 = max(ys.min() - margin, 0), min(ys.max() + margin + 1, img.shape[0])
    return img[y0:y1, x0:x1], (pivot[0] - x0, pivot[1] - y0)


def main():
    sprites = []
    for sp, variants in SINGLES:
        for v in range(variants):
            img, piv, ppm = make_single(sp, v)
            kind = "bush" if sp == "bush" else "tree"
            sprites.append({"species": sp, "variant": v, "kind": kind, "img": img, "pivot": piv, "ppm": ppm})
    for kind in CLUSTERS:
        for v in range(3):
            img, piv, ppm = make_cluster(kind, v)
            sprites.append({"species": kind, "variant": v, "kind": "cluster", "img": img, "pivot": piv, "ppm": ppm})
    for v in range(2):
        img, piv, ppm = make_stump(v)
        sprites.append({"species": "stump", "variant": v, "kind": "stump", "img": img, "pivot": piv, "ppm": ppm})
    for v in range(2):
        for big in (0, 1):
            img, piv, ppm = make_rock(v, big)
            sprites.append({"species": "boulder" if big else "rock", "variant": v, "kind": "rock", "img": img, "pivot": piv, "ppm": ppm})
    for s in sprites:
        s["img"], s["pivot"] = trim(s["img"], s["pivot"])
    sprites.sort(key=lambda s: -s["img"].shape[0])
    width = 1024
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
        entries.append({"species": s["species"], "variant": s["variant"], "kind": s["kind"],
                        "rect": [px, py, w, h], "pivot": [round(s["pivot"][0], 2), round(s["pivot"][1], 2)],
                        "size_m": [round(w / s["ppm"], 3), round(h / s["ppm"], 3)]})
    # colour bleed into transparent texels (clean mipmaps)
    a = atlas[..., 3]
    rgb = atlas[..., :3]
    for _ in range(3):
        m = a < 0.01
        acc = np.zeros_like(rgb)
        cnt = np.zeros(a.shape)
        for ax in (0, 1):
            for s in (1, -1):
                sa = np.roll(a, s, axis=ax) >= 0.01
                acc += np.roll(rgb, s, axis=ax) * sa[..., None]
                cnt += sa
        fill = m & (cnt > 0)
        rgb[fill] = acc[fill] / cnt[fill][:, None]
        a = np.where(fill, 0.011, a)
    out = np.clip(np.concatenate([rgb, atlas[..., 3:4]], axis=-1) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    os.makedirs(OUT_DIR, exist_ok=True)
    write_png(os.path.join(OUT_DIR, "vegetation_atlas.png"), out)
    with open(os.path.join(OUT_DIR, "vegetation_atlas.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"version": 3, "atlas": "vegetation_atlas.png", "width": width, "height": height,
                   "style": "painterly_3q", "sprites": entries}, f, indent=1)
    prev_dir = os.path.join(HERE, "out_preview")
    os.makedirs(prev_dir, exist_ok=True)
    bg = hexc("#9DB065")
    comp = atlas[..., :3] * atlas[..., 3:4] + bg * (1.0 - atlas[..., 3:4])
    write_png(os.path.join(prev_dir, "vegetation_x2.png"), (np.kron(comp, np.ones((2, 2, 1))) * 255).astype(np.uint8))
    print("atlas", width, height, len(entries))


if __name__ == "__main__":
    main()

