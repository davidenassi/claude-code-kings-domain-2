"""Tileable detail textures for the terrain shader (512x512).

Detail textures are *multipliers* centred on 0.5 (= x1.0): the terrain keeps its baked colour from far
away (mipmaps converge to 0.5) and gains blades of grass, needles, pebbles, cracks when zoomed in.
Water textures: ripple normal map (RG) and foam noise.
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from kd import const as K  # noqa: E402

OUT = os.path.join(K.GAME_DIR, "assets", "textures", "detail")
S = 512
rng = np.random.default_rng(7)


def spectral_noise(size, beta, seed, lo=1.0):
    """Tileable noise with power spectrum 1/f^beta (FFT filtered white noise), normalised to std 1."""
    r = np.random.default_rng(seed)
    w = r.standard_normal((size, size))
    f = np.fft.fft2(w)
    ky = np.fft.fftfreq(size)[:, None] * size
    kx = np.fft.fftfreq(size)[None, :] * size
    k = np.sqrt(kx * kx + ky * ky)
    k[0, 0] = 1.0
    filt = 1.0 / np.maximum(k, lo) ** beta
    filt[0, 0] = 0.0
    n = np.real(np.fft.ifft2(f * filt))
    return (n - n.mean()) / n.std()


def wrap_draw(draw_fn, img):
    """Call draw_fn(dx, dy) for the 9 tile offsets so strokes wrap seamlessly."""
    for dx in (-S, 0, S):
        for dy in (-S, 0, S):
            draw_fn(dx, dy)


def to_mult(lum, tint=(1.0, 1.0, 1.0), tint_amount=None):
    """lum ~ N(0,1)-ish -> RGB multiplier image centred on 128."""
    rgb = np.stack([lum * t for t in tint], -1)
    if tint_amount is not None:
        rgb = rgb + tint_amount
    out = np.clip(0.5 + rgb, 0, 1)
    out = out - out.reshape(-1, 3).mean(0) + 0.5           # mean exactly neutral
    return Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def strokes(count, length, width, colour_fn, angle_mu=-np.pi / 2, angle_sd=0.35, seed=0, bg=None):
    r = np.random.default_rng(seed)
    img = Image.new("RGB", (S, S), bg or (128, 128, 128))
    d = ImageDraw.Draw(img)
    for _ in range(count):
        x, y = r.uniform(0, S, 2)
        a = r.normal(angle_mu, angle_sd)
        L = r.uniform(*length)
        x2, y2 = x + np.cos(a) * L, y + np.sin(a) * L
        c = colour_fn(r)
        wd = int(r.integers(width[0], width[1] + 1))

        def f(dx, dy):
            d.line([(x + dx, y + dy), (x2 + dx, y2 + dy)], fill=c, width=wd)
        wrap_draw(f, img)
    return img


def grass():
    base = spectral_noise(S, 1.1, 1, lo=24.0) * 0.08 + spectral_noise(S, 0.5, 2, lo=24.0) * 0.05
    bg = to_mult(base, (1.0, 1.0, 1.0))

    def col(r):
        v = r.normal(0, 1)
        g = int(np.clip(128 + v * 26 + 6, 70, 200))
        return (int(np.clip(g + r.normal(4, 8), 60, 210)), g, int(np.clip(g - 18 + r.normal(0, 6), 50, 200)))
    blades = strokes(9000, (5, 13), (1, 2), col, seed=11)
    dark = strokes(2500, (3, 7), (2, 3), lambda r: (88, 92, 84), seed=12)
    img = Image.blend(bg, blades, 0.65)
    img = Image.blend(img, dark, 0.18)
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    a = np.asarray(img).astype(np.float32) / 255.0
    a = a - a.reshape(-1, 3).mean(0) + 0.5
    # flowers: sparse small warm dots (fade with mipmaps)
    r = np.random.default_rng(13)
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    for _ in range(140):
        x, y = r.uniform(0, S, 2)
        c = [(172, 160, 110), (176, 150, 150), (165, 165, 140)][r.integers(0, 3)]
        d.ellipse([x - 1.2, y - 1.0, x + 1.2, y + 1.0], fill=c)
    return im


def forest_floor():
    base = spectral_noise(S, 1.3, 21, lo=16.0) * 0.14
    bg = to_mult(base, (1.0, 0.95, 0.85))

    def col(r):
        v = r.normal(0, 1)
        g = int(np.clip(118 + v * 30, 40, 200))
        return (g + 10, g, g - 12)
    needles = strokes(7000, (3, 8), (1, 1), col, angle_sd=1.6, seed=22)
    leaves = Image.new("RGB", (S, S), (128, 128, 128))
    d = ImageDraw.Draw(leaves)
    r = np.random.default_rng(23)
    for _ in range(900):
        x, y = r.uniform(0, S, 2)
        c = int(r.normal(120, 22))
        rr = r.uniform(1.5, 3.5)
        d.ellipse([x - rr, y - rr * 0.6, x + rr, y + rr * 0.6], fill=(c + 18, c + 4, c - 14))
    img = Image.blend(Image.blend(bg, needles, 0.55), leaves, 0.3).filter(ImageFilter.GaussianBlur(0.5))
    a = np.asarray(img).astype(np.float32) / 255.0
    a = a - a.reshape(-1, 3).mean(0) + 0.5
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


def soil():
    base = spectral_noise(S, 1.2, 31, lo=16.0) * 0.10
    img = to_mult(base, (1.0, 0.97, 0.92))
    d = ImageDraw.Draw(img)
    r = np.random.default_rng(32)
    for _ in range(1600):
        x, y = r.uniform(0, S, 2)
        rr = r.uniform(0.8, 3.2)
        c = int(r.normal(135, 18))
        sh = int(c * 0.72)

        def f(dx, dy, x=x, y=y, rr=rr, c=c, sh=sh):
            d.ellipse([x + dx - rr + 0.8, y + dy - rr * 0.7 + 1.0, x + dx + rr + 0.8, y + dy + rr * 0.7 + 1.0],
                      fill=(sh, sh, sh))
            d.ellipse([x + dx - rr, y + dy - rr * 0.7, x + dx + rr, y + dy + rr * 0.7], fill=(c, c - 3, c - 8))
        wrap_draw(f, img)
    img = img.filter(ImageFilter.GaussianBlur(0.5))
    a = np.asarray(img).astype(np.float32) / 255.0
    return Image.fromarray((np.clip(a - a.reshape(-1, 3).mean(0) + 0.5, 0, 1) * 255).astype(np.uint8))


def voronoi_edges(size, n, seed):
    r = np.random.default_rng(seed)
    pts = r.uniform(0, size, (n, 2))
    pts = np.concatenate([pts + [dx, dy] for dx in (-size, 0, size) for dy in (-size, 0, size)])
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    from scipy.spatial import cKDTree
    t = cKDTree(pts)
    d, _ = t.query(np.c_[xx.ravel(), yy.ravel()], k=2)
    return (d[:, 1] - d[:, 0]).reshape(size, size)


def facets(size, n, seed, light=(-0.85, -0.5)):
    """Tileable faceted plates: every Voronoi cell is a tilted plane lit from `light` -> chunky rock facets.
    Returns (facet shade ~N(0,1), distance to the cell edge)."""
    r = np.random.default_rng(seed)
    pts = r.uniform(0, size, (n, 2))
    tilt = r.normal(0, 1, (n, 2))
    allp = np.concatenate([pts + [dx, dy] for dx in (-size, 0, size) for dy in (-size, 0, size)])
    allt = np.concatenate([tilt] * 9)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    from scipy.spatial import cKDTree
    d, i = cKDTree(allp).query(np.c_[xx.ravel(), yy.ravel()], k=2)
    shade = (allt[i[:, 0], 0] * light[0] + allt[i[:, 0], 1] * light[1]).reshape(size, size)
    edge = (d[:, 1] - d[:, 0]).reshape(size, size)
    return shade / max(shade.std(), 1e-6), edge


def rock():
    big, e1 = facets(S, 26, 43)
    small, e2 = facets(S, 140, 44)
    # bevel: the lit / shaded rim of each plate (light from the west-south-west)
    rim = np.clip(1.0 - e1 / 5.0, 0, 1)
    lum = big * 0.06 + small * 0.035
    lum -= np.exp(-e1 / 1.6) * 0.20 + np.exp(-e2 / 1.1) * 0.06            # cracks between the slabs
    lum += rim * 0.03
    lum += spectral_noise(S, 2.2, 45, lo=4.0) * 0.05 + spectral_noise(S, 1.2, 47, lo=12.0) * 0.02
    lichen = np.clip(spectral_noise(S, 1.8, 46) - 1.4, 0, 1) * 0.2
    tint = np.stack([lichen * 0.25, lichen * 0.3, -lichen * 0.15], -1)
    return to_mult(lum, (1.0, 1.0, 1.02), tint)


def snow():
    n = spectral_noise(S, 1.6, 51) * 0.05 + spectral_noise(S, 0.6, 52) * 0.015
    return to_mult(n, (0.98, 0.99, 1.0))


def water_normal():
    h = spectral_noise(S, 2.6, 61, lo=2.0) + 0.25 * spectral_noise(S, 2.0, 62, lo=6.0)
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    s = 1.0 / (np.abs(np.concatenate([gx.ravel(), gy.ravel()])).std() * 3.0)
    rgb = np.stack([0.5 + gx * s * 0.5, 0.5 + gy * s * 0.5, 0.5 + h * 0.12], -1)
    return Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))


def foam():
    a = spectral_noise(S, 1.2, 71)
    e = voronoi_edges(S, 120, 72)
    cells = np.exp(-e / 3.0)
    v = np.clip(0.5 + a * 0.18 + cells * 0.5 - 0.2, 0, 1)
    return Image.fromarray((v * 255).astype(np.uint8), "L")


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in (("grass", grass), ("forest", forest_floor), ("soil", soil), ("rock", rock),
                     ("snow", snow), ("water_normal", water_normal), ("foam", foam)):
        im = fn()
        im.save(os.path.join(OUT, f"{name}.png"), optimize=True)
        print(name, im.size, im.mode)


if __name__ == "__main__":
    main()
