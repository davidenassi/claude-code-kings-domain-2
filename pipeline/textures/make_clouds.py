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
    """Cumulus: a dome-shaped volume (height field = sqrt of the blob density) lit from the upper left,
    cauliflower puffs along the top, a flatter, shaded base and wispy eroded edges."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    dens = np.zeros((H, W), np.float32)
    base_y = rng.uniform(0.62, 0.7) * H
    # body: a few large blobs sitting on the base line
    for k in range(rng.integers(4, 7)):
        cx = rng.uniform(0.22, 0.78) * W
        r = rng.uniform(0.11, 0.2) * W
        cy = base_y - r * rng.uniform(0.35, 0.8)
        dens += np.exp(-(((xx - cx) / r) ** 2 + ((yy - cy) / (r * 0.85)) ** 2))
    # cauliflower: many small puffs on the upper part of the body
    for k in range(rng.integers(26, 40)):
        cx = rng.uniform(0.18, 0.82) * W
        prof = np.exp(-((cx - W / 2) / (0.3 * W)) ** 2)
        r = rng.uniform(0.035, 0.08) * W
        cy = base_y - (0.12 + 0.36 * prof * rng.uniform(0.6, 1.1)) * H - r * 0.3
        dens += 0.75 * np.exp(-(((xx - cx) / r) ** 2 + ((yy - cy) / r) ** 2))
    # flat-ish base: fade the density under the base line
    dens *= np.clip(1.0 - (yy - base_y) / (0.08 * H), 0, 1) ** 1.5
    nz = N.fbm_at(xx.ravel() / 70.0 + seed * 7, yy.ravel() / 70.0, 1.0, N.perm(seed), 5, 2.0, 0.55).reshape(H, W)
    fine = N.fbm_at(xx.ravel() / 18.0, yy.ravel() / 18.0 + seed, 1.0, N.perm(seed + 1), 3, 2.0, 0.5).reshape(H, W)
    d = dens * (0.85 + 0.45 * nz) + fine * 0.08 - 0.38
    a = np.clip(d * 3.2, 0, 1) ** 1.1
    # dome height field -> normals -> light from the upper left (sun of the valley), soft wrap
    hgt = ndimage.gaussian_filter(np.sqrt(np.clip(dens - 0.3, 0, None)), 12.0) * 220.0     # smooth volume
    gy, gx = np.gradient(hgt)
    nrm = np.stack([-gx, -gy, np.ones_like(gx)], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    L = np.array([-0.55, -0.62, 0.56])
    L /= np.linalg.norm(L)
    lam = np.clip((nrm @ L) * 0.6 + 0.58, 0, 1)
    core = ndimage.gaussian_filter(np.clip(d, 0, None), 22.0)
    occl = np.clip(1.0 - core * 0.55, 0.62, 1.0)                 # thick cores and the base a little darker
    under = np.clip((yy - (base_y - 0.16 * H)) / (0.18 * H), 0, 1)  # undersides in the cloud's own shadow
    lit = np.clip(lam * occl * (1.0 - 0.32 * under) + fine * 0.05, 0, 1)
    hi = np.array([1.0, 0.99, 0.96])
    mid = np.array([0.87, 0.89, 0.93])
    sh = np.array([0.62, 0.67, 0.76])
    t = lit[..., None]
    rgb = np.where(t > 0.5, mid * (1 - (t - 0.5) * 2) + hi * ((t - 0.5) * 2), sh * (1 - t * 2) + mid * (t * 2))
    a = ndimage.gaussian_filter(a, 2.2)
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
