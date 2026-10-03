"""Painted cumulus sprites for the map edges (far view, as in the reference valley image).

Each cloud: a cluster of soft puffs + fbm erosion -> density; light from the upper left (gradient of the
blurred density) -> white tops, blue-grey undersides. RGBA, premultiplication-safe edges.
Output: game/assets/fx/cloud_<k>.png
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from kd import const as K  # noqa: E402
from terrain import noise as N  # noqa: E402

OUT = os.path.join(K.GAME_DIR, "assets", "fx")
W, H = 1024, 640


def cloud(seed):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    dens = np.zeros((H, W), np.float32)
    n = rng.integers(9, 15)
    for k in range(n):
        cx = rng.uniform(0.18, 0.82) * W
        cy = rng.uniform(0.35, 0.7) * H - (0.12 * H if k < n // 2 else 0)
        r = rng.uniform(0.09, 0.2) * W
        dens += np.exp(-(((xx - cx) / r) ** 2 + ((yy - cy) / (r * 0.8)) ** 2))
    g = (0.0, 0.0, 1.0, W, H)
    nz = N.fbm_at(xx.ravel() / 90.0 + seed * 7, yy.ravel() / 90.0, 1.0, N.perm(seed), 5, 2.0, 0.55).reshape(H, W)
    fine = N.fbm_at(xx.ravel() / 22.0, yy.ravel() / 22.0 + seed, 1.0, N.perm(seed + 1), 3, 2.0, 0.5).reshape(H, W)
    d = dens * (0.75 + 0.6 * nz) + fine * 0.12 - 0.42
    a = np.clip(d * 2.6, 0, 1) ** 1.2
    # light: from the upper left
    blur = ndimage.gaussian_filter(np.clip(d, 0, None), 9.0)
    gy, gx = np.gradient(blur)
    lit = np.clip(0.62 - (gx * -0.7 + gy * -0.9) * 22.0, 0, 1)
    lit = lit * 0.7 + 0.3 * np.clip(1.0 - (yy / H - 0.35) * 0.9, 0, 1)
    lit = np.clip(lit + fine * 0.12, 0, 1)
    hi = np.array([1.0, 0.99, 0.96])
    sh = np.array([0.62, 0.68, 0.80])
    rgb = sh[None, None] * (1 - lit[..., None]) + hi[None, None] * lit[..., None]
    a = ndimage.gaussian_filter(a, 1.2)
    edge = np.minimum.reduce([xx / 90.0, (W - 1 - xx) / 90.0, yy / 70.0, (H - 1 - yy) / 70.0])
    a = a * np.clip(edge, 0, 1)
    img = np.concatenate([rgb, a[..., None]], -1)
    return Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def main():
    os.makedirs(OUT, exist_ok=True)
    for k in range(6):
        cloud(100 + k).save(os.path.join(OUT, f"cloud_{k}.png"), optimize=True)
        print("cloud", k)


if __name__ == "__main__":
    main()
