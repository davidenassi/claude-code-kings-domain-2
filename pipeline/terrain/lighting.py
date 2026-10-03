"""Terrain lighting in ground space: normals, cast shadows (sun sweep), ambient occlusion, cavity."""
from __future__ import annotations

import math

import numba as nb
import numpy as np
from scipy import ndimage

from kd import const as K


def normals(h, cell=1.0):
    gy, gx = np.gradient(h, cell)
    nz = np.ones_like(h)
    l = np.sqrt(gx * gx + gy * gy + 1.0)
    # world: x east, y south; normal = (-dh/dx, -dh/dy, 1)
    return (-gx / l).astype(np.float32), (-gy / l).astype(np.float32), (nz / l).astype(np.float32)


@nb.njit(parallel=False, cache=True, fastmath=True)
def _shadow_sweep(h, dyx, drop):
    """Sun towards -x (west) and +y*dyx (south). Column sweep from west to east."""
    ny, nx = h.shape
    hs = np.empty_like(h)
    sh = np.zeros_like(h)
    for j in range(ny):
        hs[j, 0] = h[j, 0]
    for i in range(1, nx):
        for j in range(ny):
            yy = j + dyx
            j0 = int(math.floor(yy))
            f = yy - j0
            if j0 < 0:
                prev = hs[0, i - 1]
            elif j0 >= ny - 1:
                prev = hs[ny - 1, i - 1]
            else:
                prev = hs[j0, i - 1] * (1 - f) + hs[j0 + 1, i - 1] * f
            prev -= drop
            if prev > h[j, i]:
                hs[j, i] = prev
                sh[j, i] = prev - h[j, i]
            else:
                hs[j, i] = h[j, i]
    return sh


def cast_shadow(h, cell=1.0, elev_deg=None, softness=2.5):
    sx, sy, sz = K.sun_dir_world()
    hl = math.hypot(sx, sy)
    elev = math.degrees(math.atan2(sz, hl)) if elev_deg is None else elev_deg
    # one step = 1 cell in x towards the sun
    dyx = (sy / -sx)                       # rows to move (south) per column moved west
    step_len = math.hypot(1.0, dyx) * cell
    out = np.zeros_like(h)
    # several elevations -> smooth penumbra (no banding)
    des = np.linspace(-2.5, 2.5, 9)
    ws = np.exp(-(des / 1.6) ** 2)
    ws /= ws.sum()
    for de, w in zip(des, ws):
        drop = step_len * math.tan(math.radians(elev + de))
        depth = _shadow_sweep(h.astype(np.float32), np.float32(dyx), np.float32(drop))
        out += w * np.clip(depth / softness, 0.0, 1.0)
    out = ndimage.gaussian_filter(out, 0.8)
    return (1.0 - out).astype(np.float32)          # 1 = lit, 0 = shadow


def ambient_occlusion(h, cell=1.0):
    ao = np.ones_like(h)
    for sigma_m, strength, scale in ((2.0, 0.35, 1.2), (8.0, 0.30, 4.0), (30.0, 0.22, 14.0),
                                     (110.0, 0.18, 45.0)):
        b = ndimage.gaussian_filter(h, sigma_m / cell)
        occ = np.clip((b - h) / scale, 0.0, 1.0)
        ao -= strength * occ
    return np.clip(ao, 0.25, 1.0).astype(np.float32)


def cavity(h, cell=1.0):
    """>0 on convex crests, <0 in crevices (metres-ish)."""
    b1 = ndimage.gaussian_filter(h, 1.2 / cell)
    b2 = ndimage.gaussian_filter(h, 5.0 / cell)
    return (b1 - b2).astype(np.float32)
