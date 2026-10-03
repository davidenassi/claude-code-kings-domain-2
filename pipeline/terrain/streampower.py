"""Stream-power landscape evolution (Braun & Willett 2013 style) with priority-flood drainage.

dh/dt = U - K * A^m * S   (n = 1, solved implicitly along the drainage stack) + hillslope diffusion.

Outlets (base level) are given by `fixed` (valley floor, river paths): mountains grow from the uplift
field and get dissected by a dendritic network of valleys that drain towards them.
"""
from __future__ import annotations

import heapq
import math

import numba as nb
import numpy as np

DX8 = np.array([1, 1, 0, -1, -1, -1, 0, 1], np.int64)
DY8 = np.array([0, 1, 1, 1, 0, -1, -1, -1], np.int64)
DD8 = np.array([1.0, 1.41421356, 1.0, 1.41421356, 1.0, 1.41421356, 1.0, 1.41421356])


@nb.njit(cache=True)
def priority_flood(h, fixed):
    """Returns (stack order from outlets upward, receiver index, receiver distance)."""
    ny, nx = h.shape
    n = nx * ny
    rec = np.full(n, -1, np.int64)
    rdist = np.ones(n, np.float64)
    done = np.zeros(n, np.bool_)
    stack = np.empty(n, np.int64)
    sp = 0
    heap = [(0.0, np.int64(0))]
    heap.pop()
    for j in range(ny):
        for i in range(nx):
            k = j * nx + i
            if fixed[j, i] or i == 0 or j == 0 or i == nx - 1 or j == ny - 1:
                if fixed[j, i]:
                    heapq.heappush(heap, (h[j, i], np.int64(k)))
                    done[k] = True
                    rec[k] = k
    while len(heap) > 0:
        hv, k = heapq.heappop(heap)
        stack[sp] = k
        sp += 1
        j = k // nx
        i = k - j * nx
        for d in range(8):
            ii = i + DX8[d]
            jj = j + DY8[d]
            if ii < 0 or jj < 0 or ii >= nx or jj >= ny:
                continue
            kk = jj * nx + ii
            if done[kk]:
                continue
            done[kk] = True
            rec[kk] = k
            rdist[kk] = DD8[d]
            # pits are filled implicitly: priority is max(own height, spill height)
            heapq.heappush(heap, (max(h[jj, ii], hv), np.int64(kk)))
    return stack[:sp], rec, rdist


@nb.njit(cache=True)
def accumulate(stack, rec, cell_area, n):
    A = np.full(n, cell_area)
    for t in range(len(stack) - 1, -1, -1):
        k = stack[t]
        r = rec[k]
        if r != k and r >= 0:
            A[r] += A[k]
    return A


@nb.njit(cache=True)
def implicit_erosion(hf, stack, rec, rdist, A, K, m, dt, dx, U, fixedf):
    for t in range(len(stack)):
        k = stack[t]
        r = rec[k]
        if r == k or fixedf[k]:
            continue
        hf[k] += U[k] * dt
        F = K[k] * dt * A[k] ** m / (rdist[k] * dx)
        hf[k] = (hf[k] + F * hf[r]) / (1.0 + F)
    return hf


@nb.njit(parallel=True, cache=True)
def diffuse(h, out, kd, fixed):
    ny, nx = h.shape
    for j in nb.prange(1, ny - 1):
        for i in range(1, nx - 1):
            if fixed[j, i]:
                out[j, i] = h[j, i]
                continue
            lap = h[j - 1, i] + h[j + 1, i] + h[j, i - 1] + h[j, i + 1] - 4 * h[j, i]
            out[j, i] = h[j, i] + kd * lap
    return out


def evolve(h0, uplift, fixed, dx, iters=160, K=2e-5, m=0.45, dt=2000.0, kd=0.02, kfield=None, log=None):
    h = h0.astype(np.float64).copy()
    ny, nx = h.shape
    n = nx * ny
    U = uplift.astype(np.float64).ravel()
    Kf = (np.full(n, K) if kfield is None else (K * kfield).astype(np.float64).ravel())
    fixedf = fixed.ravel().copy()
    tmp = h.copy()
    for it in range(iters):
        stack, rec, rdist = priority_flood(h, fixed)
        A = accumulate(stack, rec, dx * dx, n)
        hf = h.ravel()
        hf = implicit_erosion(hf, stack, rec, rdist, A, Kf, m, dt, dx, U, fixedf)
        h = hf.reshape(ny, nx)
        if kd > 0:
            tmp = diffuse(h, tmp, kd, fixed)
            h, tmp = tmp, h
        if log and it % 40 == 0:
            log(f"  stream power it {it}  max {h.max():.1f}")
    stack, rec, rdist = priority_flood(h, fixed)
    A = accumulate(stack, rec, dx * dx, n).reshape(ny, nx)
    return h.astype(np.float32), A.astype(np.float32)
