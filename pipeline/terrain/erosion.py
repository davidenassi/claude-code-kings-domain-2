"""Hydraulic (droplet) and thermal erosion, numba accelerated.

Heights are processed in *cell units* (metres / cell size) so the same parameters behave the same on
coarse and fine grids. `erodibility` (0..1) protects the valley floor and riverbeds.
"""
from __future__ import annotations

import math

import numba as nb
import numpy as np


@nb.njit(cache=True)
def _brush(radius):
    r = int(math.ceil(radius))
    offs = []
    ws = []
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            d = math.sqrt(dx * dx + dy * dy)
            if d < radius:
                offs.append((dx, dy))
                ws.append(1.0 - d / radius)
    s = 0.0
    for w in ws:
        s += w
    n = len(offs)
    ox = np.empty(n, np.int32)
    oy = np.empty(n, np.int32)
    ow = np.empty(n, np.float32)
    for k in range(n):
        ox[k] = offs[k][0]
        oy[k] = offs[k][1]
        ow[k] = ws[k] / s
    return ox, oy, ow


@nb.njit(cache=True, fastmath=True)
def _height_grad(h, px, py):
    ny, nx = h.shape
    x = int(px)
    y = int(py)
    fx = px - x
    fy = py - y
    h00 = h[y, x]
    h10 = h[y, x + 1]
    h01 = h[y + 1, x]
    h11 = h[y + 1, x + 1]
    gx = (h10 - h00) * (1 - fy) + (h11 - h01) * fy
    gy = (h01 - h00) * (1 - fx) + (h11 - h10) * fx
    hh = h00 * (1 - fx) * (1 - fy) + h10 * fx * (1 - fy) + h01 * (1 - fx) * fy + h11 * fx * fy
    return hh, gx, gy


@nb.njit(cache=True, fastmath=True)
def droplet_erosion(h, erod, n_drops, seed, radius=3.0, inertia=0.05, capacity=4.0, min_cap=0.01,
                    erode_speed=0.3, deposit_speed=0.3, evaporate=0.015, gravity=4.0, lifetime=48,
                    max_erode=1.0):
    np.random.seed(seed)
    ny, nx = h.shape
    ox, oy, ow = _brush(radius)
    nb_ = ox.shape[0]
    for d in range(n_drops):
        px = np.random.random() * (nx - 2)
        py = np.random.random() * (ny - 2)
        dx = 0.0
        dy = 0.0
        speed = 1.0
        water = 1.0
        sed = 0.0
        for life in range(lifetime):
            ix = int(px)
            iy = int(py)
            cx = px - ix
            cy = py - iy
            hh, gx, gy = _height_grad(h, px, py)
            dx = dx * inertia - gx * (1 - inertia)
            dy = dy * inertia - gy * (1 - inertia)
            l = math.sqrt(dx * dx + dy * dy)
            if l < 1e-9:
                break
            dx /= l
            dy /= l
            npx = px + dx
            npy = py + dy
            if npx < 1 or npy < 1 or npx >= nx - 2 or npy >= ny - 2:
                break
            nh, _, _ = _height_grad(h, npx, npy)
            dh = nh - hh
            cap = max(-dh * speed * water * capacity, min_cap)
            e = erod[iy, ix]
            if sed > cap or dh > 0:
                if dh > 0:
                    dep = min(dh, sed)
                else:
                    dep = (sed - cap) * deposit_speed
                sed -= dep
                h[iy, ix] += dep * (1 - cx) * (1 - cy)
                h[iy, ix + 1] += dep * cx * (1 - cy)
                h[iy + 1, ix] += dep * (1 - cx) * cy
                h[iy + 1, ix + 1] += dep * cx * cy
            else:
                amt = min((cap - sed) * erode_speed, -dh) * e
                amt = min(amt, max_erode)
                for k in range(nb_):
                    xx = ix + ox[k]
                    yy = iy + oy[k]
                    if xx < 0 or yy < 0 or xx >= nx or yy >= ny:
                        continue
                    we = amt * ow[k]
                    h[yy, xx] -= we
                    sed += we
            speed = math.sqrt(max(0.0, speed * speed + dh * gravity))
            water *= (1 - evaporate)
            px = npx
            py = npy
    return h


@nb.njit(parallel=True, cache=True, fastmath=True)
def _thermal_step(h, out, talus, rate, erod):
    ny, nx = h.shape
    for y in nb.prange(1, ny - 1):
        for x in range(1, nx - 1):
            c = h[y, x]
            acc = 0.0
            # receive from higher neighbours, give to lower ones (symmetric, mass conserving)
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    if dx == 0 and dy == 0:
                        continue
                    dist = 1.41421356 if (dx != 0 and dy != 0) else 1.0
                    n = h[y + dy, x + dx]
                    diff = (c - n) / dist
                    if diff > talus:
                        acc -= (diff - talus) * rate * erod[y, x]
                    elif -diff > talus:
                        acc += (-diff - talus) * rate * erod[y + dy, x + dx]
            out[y, x] = c + acc
    return out


def thermal_erosion(h, erod, talus=1.2, rate=0.06, iters=20):
    out = h.copy()
    for _ in range(iters):
        out = _thermal_step(h, out, np.float32(talus), np.float32(rate), erod)
        h, out = out, h
    return h
