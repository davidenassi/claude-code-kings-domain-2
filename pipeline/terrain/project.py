"""Oblique orthographic projection of the heightfield (camera yaw 0, elevation EL, looking north).

For every screen column the surface is walked from south (near) to north (far) keeping a horizon:
this is an exact visibility solution for an orthographic camera without yaw. Each screen pixel
receives the continuous ground coordinate (x, y) and altitude it shows.
"""
from __future__ import annotations

import math

import numba as nb
import numpy as np

from kd import const as K


@nb.njit(parallel=True, cache=True, fastmath=True)
def rasterize(hv, x0, y0, cell, P, sin_el, cos_el, v_off, out_h):
    ny, nx = hv.shape
    W = int((nx * cell) * P)
    gy = np.full((out_h, W), np.nan, np.float32)
    gz = np.full((out_h, W), np.nan, np.float32)
    for u in nb.prange(W):
        x = (u + 0.5) / P
        fi = (x - x0) / cell
        i0 = int(math.floor(fi))
        if i0 < 0:
            i0 = 0
            fx = 0.0
        elif i0 >= nx - 1:
            i0 = nx - 2
            fx = 1.0
        else:
            fx = fi - i0
        horizon = float(out_h)
        prev_v = 0.0
        prev_y = 0.0
        prev_z = 0.0
        for j in range(ny - 1, -1, -1):
            z = hv[j, i0] * (1 - fx) + hv[j, i0 + 1] * fx
            y = y0 + j * cell
            v = (y * sin_el - z * cos_el) * P - v_off
            if j < ny - 1 and v < prev_v:
                # pixels with centres in (v, prev_v] and above the horizon
                top = v
                bot = min(prev_v, horizon)
                p0 = int(math.ceil(top - 0.5))
                p1 = int(math.floor(bot - 0.5))
                if p0 < 0:
                    p0 = 0
                if p1 > out_h - 1:
                    p1 = out_h - 1
                inv = 1.0 / (prev_v - v)
                for p in range(p0, p1 + 1):
                    c = p + 0.5
                    if c > bot:
                        continue
                    t = (prev_v - c) * inv
                    gy[p, u] = prev_y - t * cell
                    gz[p, u] = prev_z + t * (z - prev_z)
                if v < horizon:
                    horizon = v
            prev_v = v
            prev_y = y
            prev_z = z
    return gy, gz


def screen_extent(hv, y0, cell, P):
    ny = hv.shape[0]
    ys = (y0 + np.arange(ny) * cell)[:, None]
    v = (ys * K.SIN_EL - hv * K.COS_EL) * P
    return float(v.min()), float(v.max())


def crop_rows(gy):
    """First and last pixel rows that are fully covered by terrain (no void)."""
    full = np.all(np.isfinite(gy), axis=1)
    rows = np.nonzero(full)[0]
    return int(rows[0]), int(rows[-1])


@nb.njit(parallel=True, cache=True, fastmath=True)
def bilinear(img, gx, gy, x0, y0, cell):
    """Sample a ground map (H, W, C) at continuous ground coordinates."""
    H, W, C = img.shape
    oh, ow = gx.shape
    out = np.zeros((oh, ow, C), np.float32)
    for p in nb.prange(oh):
        for q in range(ow):
            yy = gy[p, q]
            if yy != yy:
                continue
            fx = (gx[p, q] - x0) / cell
            fy = (yy - y0) / cell
            i = int(math.floor(fx))
            j = int(math.floor(fy))
            if i < 0:
                i = 0
                fx = 0.0
            if j < 0:
                j = 0
                fy = 0.0
            if i > W - 2:
                i = W - 2
                fx = W - 1.0
            if j > H - 2:
                j = H - 2
                fy = H - 1.0
            ax = fx - i
            ay = fy - j
            for c in range(C):
                out[p, q, c] = (img[j, i, c] * (1 - ax) * (1 - ay) + img[j, i + 1, c] * ax * (1 - ay)
                                + img[j + 1, i, c] * (1 - ax) * ay + img[j + 1, i + 1, c] * ax * ay)
    return out
