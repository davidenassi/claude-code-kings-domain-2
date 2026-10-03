"""Fast deterministic 2D noise (numba): gradient noise, fBm, ridged multifractal, domain warp.

All functions take world coordinates in metres plus a `scale` (feature size in metres), so the same
call produces the same landscape at any grid resolution.
"""
from __future__ import annotations

import math

import numba as nb
import numpy as np

_PERM_CACHE: dict[int, np.ndarray] = {}


def perm(seed: int) -> np.ndarray:
    if seed not in _PERM_CACHE:
        rng = np.random.default_rng(seed)
        p = rng.permutation(256).astype(np.int32)
        _PERM_CACHE[seed] = np.concatenate([p, p])
    return _PERM_CACHE[seed]


@nb.njit(cache=True, fastmath=True)
def _fade(t):
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


_GX = np.cos(np.arange(16) * (2 * np.pi / 16) + 0.19).astype(np.float64)
_GY = np.sin(np.arange(16) * (2 * np.pi / 16) + 0.19).astype(np.float64)


@nb.njit(cache=True, fastmath=True)
def _grad(h, x, y):
    # 16 evenly spaced gradient directions (isotropic, no grid-aligned artifacts)
    k = h & 15
    return (_GX[k] * x + _GY[k] * y) * 1.41421356


@nb.njit(cache=True, fastmath=True)
def perlin(x, y, p):
    xi = int(math.floor(x))
    yi = int(math.floor(y))
    xf = x - xi
    yf = y - yi
    xi &= 255
    yi &= 255
    u = _fade(xf)
    v = _fade(yf)
    aa = p[p[xi] + yi]
    ab = p[p[xi] + yi + 1]
    ba = p[p[xi + 1] + yi]
    bb = p[p[xi + 1] + yi + 1]
    x1 = _grad(aa, xf, yf) + u * (_grad(ba, xf - 1.0, yf) - _grad(aa, xf, yf))
    x2 = _grad(ab, xf, yf - 1.0) + u * (_grad(bb, xf - 1.0, yf - 1.0) - _grad(ab, xf, yf - 1.0))
    return (x1 + v * (x2 - x1)) * 0.7071


@nb.njit(cache=True, fastmath=True)
def fbm_pt(x, y, p, octaves, lac, gain):
    a = 1.0
    f = 1.0
    s = 0.0
    n = 0.0
    for o in range(octaves):
        s += a * perlin(x * f + o * 17.31, y * f - o * 9.73, p)
        n += a
        a *= gain
        f *= lac
    return s / n


@nb.njit(cache=True, fastmath=True)
def ridged_pt(x, y, p, octaves, lac, gain, sharp):
    """Ridged multifractal in [0,1]: sharp crests, weighted by previous octave (erosion-like)."""
    a = 1.0
    f = 1.0
    s = 0.0
    n = 0.0
    w = 1.0
    for o in range(octaves):
        v = 1.0 - abs(perlin(x * f + o * 31.7, y * f + o * 11.3, p))
        v = v ** sharp
        v *= w
        w = min(1.0, max(0.0, v * 1.6))
        s += a * v
        n += a
        a *= gain
        f *= lac
    return s / n


@nb.njit(parallel=True, cache=True, fastmath=True)
def fbm_grid(x0, y0, step, nx, ny, scale, p, octaves, lac, gain):
    out = np.empty((ny, nx), np.float32)
    inv = 1.0 / scale
    for j in nb.prange(ny):
        y = (y0 + j * step) * inv
        for i in range(nx):
            out[j, i] = fbm_pt((x0 + i * step) * inv, y, p, octaves, lac, gain)
    return out


@nb.njit(parallel=True, cache=True, fastmath=True)
def ridged_grid(x0, y0, step, nx, ny, scale, p, octaves, lac, gain, sharp, warp_amp, warp_scale, pw):
    out = np.empty((ny, nx), np.float32)
    inv = 1.0 / scale
    winv = 1.0 / warp_scale
    for j in nb.prange(ny):
        for i in range(nx):
            wx = x0 + i * step
            wy = y0 + j * step
            dx = fbm_pt(wx * winv, wy * winv, pw, 4, 2.0, 0.5) * warp_amp
            dy = fbm_pt(wx * winv + 5.2, wy * winv + 1.3, pw, 4, 2.0, 0.5) * warp_amp
            out[j, i] = ridged_pt((wx + dx) * inv, (wy + dy) * inv, p, octaves, lac, gain, sharp)
    return out


@nb.njit(parallel=True, cache=True, fastmath=True)
def fbm_at(xs, ys, scale, p, octaves, lac, gain):
    """fBm evaluated at arbitrary point arrays (same shape)."""
    flat_x = xs.ravel()
    flat_y = ys.ravel()
    out = np.empty(flat_x.shape[0], np.float32)
    inv = 1.0 / scale
    for k in nb.prange(flat_x.shape[0]):
        out[k] = fbm_pt(flat_x[k] * inv, flat_y[k] * inv, p, octaves, lac, gain)
    return out.reshape(xs.shape)


def fbm(grid, scale, seed, octaves=5, lac=2.0, gain=0.5):
    x0, y0, step, nx, ny = grid
    return fbm_grid(x0, y0, step, nx, ny, scale, perm(seed), octaves, lac, gain)


def ridged(grid, scale, seed, octaves=7, lac=2.0, gain=0.5, sharp=2.0, warp_amp=0.0, warp_scale=1000.0):
    x0, y0, step, nx, ny = grid
    return ridged_grid(x0, y0, step, nx, ny, scale, perm(seed), octaves, lac, gain, sharp,
                       warp_amp, warp_scale, perm(seed + 977))
