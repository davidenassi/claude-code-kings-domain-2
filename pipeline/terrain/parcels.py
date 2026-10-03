"""Pasture parcels: a warped Voronoi patchwork over the valley floor.

Meadows of the valley are divided into irregular parcels of different grass (lush, fresh, dry, olive,
mown in stripes). The same partition is used by the vegetation planner to grow hedgerows along some of
the parcel boundaries, so the countryside reads as a lived-in landscape instead of a uniform carpet.

Cached at 2 m: nearest parcel id, second nearest id, distance to the boundary (m).
"""
from __future__ import annotations

import os

import numpy as np
from scipy.spatial import cKDTree

from kd import const as K
from terrain import noise as N
from terrain.heightmap import H, W, X0, Y0

STEP = 2.0
SPACING = 82.0
PATH = os.path.join(K.CACHE_DIR, "terrain", "parcels.npz")


def build(seed: int = 7):
    rng = np.random.default_rng(seed)
    sp = SPACING
    gx, gy = np.meshgrid(np.arange(X0 - sp, X0 + W + sp, sp), np.arange(Y0 - sp, Y0 + H + sp, sp))
    pts = np.c_[gx.ravel(), gy.ravel()] + rng.uniform(-0.48, 0.48, (gx.size, 2)) * sp
    pts = pts[rng.random(len(pts)) > 0.22]                       # some larger parcels
    # a few small parcels (paddocks) scattered around
    extra = np.c_[rng.uniform(X0, X0 + W, 260), rng.uniform(Y0, Y0 + H, 260)]
    pts = np.vstack([pts, extra])
    tree = cKDTree(pts)
    nx, ny = int(W / STEP), int(H / STEP)
    g = (X0 + STEP / 2, Y0 + STEP / 2, STEP, nx, ny)
    xs = (X0 + STEP / 2 + np.arange(nx) * STEP).astype(np.float32)
    ys = (Y0 + STEP / 2 + np.arange(ny) * STEP).astype(np.float32)
    X, Y = np.meshgrid(xs, ys)
    qx = X + N.fbm(g, 55.0, 801, 3) * 16.0
    qy = Y + N.fbm(g, 55.0, 802, 3) * 16.0
    q = np.c_[qx.ravel(), qy.ravel()]
    d, i = tree.query(q, k=2, workers=-1)
    p1, p2 = pts[i[:, 0]], pts[i[:, 1]]
    edge = (d[:, 1] ** 2 - d[:, 0] ** 2) / (2.0 * np.maximum(np.linalg.norm(p2 - p1, axis=1), 1e-3))
    out = {"id1": i[:, 0].reshape(ny, nx).astype(np.int32), "id2": i[:, 1].reshape(ny, nx).astype(np.int32),
           "edge": edge.reshape(ny, nx).astype(np.float32), "n": np.int32(len(pts))}
    np.savez(PATH, **out)
    return out


def load():
    if not os.path.exists(PATH):
        return build()
    z = np.load(PATH)
    return {k: z[k] for k in z.files}


def pair_hash(a, b):
    lo, hi = np.minimum(a, b).astype(np.int64), np.maximum(a, b).astype(np.int64)
    v = (lo * 73856093) ^ (hi * 19349663)
    return ((v % 10007) / 10007.0).astype(np.float32)


def id_hash(a, salt=0):
    v = (a.astype(np.int64) * 2654435761 + salt * 97531) % 4294967296
    return ((v % 100003) / 100003.0).astype(np.float32)
