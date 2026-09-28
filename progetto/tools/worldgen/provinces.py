"""Provinces of the official map: seeds, cost-based growth, cleanup, stats, borders, cultures, names, deposits."""
import heapq
import math
import os
import random
import time

import numpy as np

import layout as L
from grids import chaikin, distance_from, label_regions, simplify_rdp
from kdio import write_json, write_png, write_raster
from kdnoise import Perlin, fbm
from names import NameGenerator
from terrain import BIOME, CELL, H, W

TARGET_PROVINCES = 400
NONE = -1
C128 = 128.0


def log(msg, t0):
    print("%s (%.1f s)" % (msg, time.time() - t0), flush=True)


# ---------------------------------------------------------------------------
def build_work_grid(ctx, biome_defs):
    land64 = ctx["land64"]
    hp = H + (H % 2)
    wp = W + (W % 2)

    def pad(a, mode="edge"):
        return np.pad(a, ((0, hp - H), (0, wp - W)), mode=mode)

    land = pad(land64, "constant").reshape(hp // 2, 2, wp // 2, 2).any(axis=(1, 3))
    elev = pad(ctx["elev64"].astype(np.float64)).reshape(hp // 2, 2, wp // 2, 2).mean(axis=(1, 3))
    biome = pad(ctx["biome64"])[::2, ::2]
    lake = pad(ctx["lake64"], "constant")[::2, ::2]
    fert_table = np.zeros(256)
    for d in biome_defs:
        fert_table[d["index"]] = d["fertility"]
    fert = fert_table[biome]
    prox = pad(ctx["river_prox64"].astype(np.float64))[::2, ::2]
    gy, gx = np.gradient(elev, C128)
    slope = np.hypot(gx, gy)
    hab = np.clip(0.08 + 1.05 * fert ** 1.3 + 0.55 * prox - 0.35 * (elev > 1100) - 0.2 * (biome == BIOME["desert"]),
                  0.10, 1.40)
    # river ids rasterised at 128 m (widest river wins)
    river_id = np.zeros(land.shape, dtype=np.int32)
    river_w = np.zeros(land.shape)
    for r in ctx["rivers"]:
        for (x, y, wdt) in r["points"]:
            cx, cy = int(x / C128), int(y / C128)
            if 0 <= cx < land.shape[1] and 0 <= cy < land.shape[0] and wdt >= river_w[cy, cx]:
                river_w[cy, cx] = wdt
                river_id[cy, cx] = r["id"] + 1
    return {"land": land, "elev": elev, "biome": biome, "lake": lake, "fert": fert, "slope": slope,
            "hab": hab, "river_id": river_id, "river_w": river_w, "h": land.shape[0], "w": land.shape[1]}


# ---------------------------------------------------------------------------
def place_seeds(g, target):
    rng = np.random.default_rng(L.WORLD_SEED + 100)
    land_idx = np.flatnonzero(g["land"] & ~g["lake"])
    cand = rng.permutation(land_idx)[:45000]
    cy = (cand // g["w"]).astype(np.float64)
    cx = (cand % g["w"]).astype(np.float64)
    hab = g["hab"].ravel()[cand]

    def dart(r0):
        sx = np.empty(len(cand))
        sy = np.empty(len(cand))
        sr = np.empty(len(cand))
        n = 0
        for i in range(len(cand)):
            r = r0 / hab[i] ** 0.8
            if n:
                d2 = (sx[:n] - cx[i]) ** 2 + (sy[:n] - cy[i]) ** 2
                lim = 0.5 * (sr[:n] + r)
                if np.any(d2 < lim * lim):
                    continue
            sx[n], sy[n], sr[n] = cx[i], cy[i], r
            n += 1
        return list(zip(sx[:n].astype(int).tolist(), sy[:n].astype(int).tolist()))

    lo, hi = 5.0, 80.0
    best = None
    for _ in range(12):
        r0 = 0.5 * (lo + hi)
        seeds = dart(r0)
        if best is None or abs(len(seeds) - target) < abs(len(best) - target):
            best = seeds
        if len(seeds) > target:
            lo = r0
        else:
            hi = r0
        if abs(len(seeds) - target) <= 4:
            break
    return best


# ---------------------------------------------------------------------------
def grow(g, seeds):
    h, w = g["h"], g["w"]
    land = g["land"]
    rng = random.Random(L.WORLD_SEED + 101)
    # each major river decides once whether it is a political frontier
    border_river = {}
    for rid in np.unique(g["river_id"]).tolist():
        if rid == 0:
            continue
        maxw = g["river_w"][g["river_id"] == rid].max()
        border_river[rid] = maxw > 38.0 and rng.random() < 0.55
    X = (np.arange(w) + 0.5) * C128 / 1000.0
    Y = (np.arange(h) + 0.5) * C128 / 1000.0
    XX, YY = np.meshgrid(X, Y)
    noise = fbm(Perlin(L.WORLD_SEED + 102), XX / 2.5, YY / 2.5, 4)
    base = (1.0 + 5.0 * np.minimum(g["slope"] / 0.35, 1.0) + 3.0 * (g["elev"] > 1050) + 2.5 * (g["elev"] > 1500)
            + 0.35 * noise + 18.0 * g["lake"])
    base = np.where(land, np.maximum(base, 0.3), np.inf)
    base_f = base.ravel().tolist()
    river_f = g["river_id"].ravel().tolist()
    label = [-1] * (h * w)
    dist = [math.inf] * (h * w)
    heap = []
    for pid, (x, y) in enumerate(seeds):
        i = y * w + x
        label[i] = pid
        dist[i] = 0.0
        heapq.heappush(heap, (0.0, i, pid))
    nbr = [(1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0),
           (1, 1, 1.4142), (1, -1, 1.4142), (-1, 1, 1.4142), (-1, -1, 1.4142)]
    while heap:
        d, i, pid = heapq.heappop(heap)
        if d > dist[i] or label[i] != pid:
            continue
        x, y = i % w, i // w
        ri = river_f[i]
        for dx, dy, step in nbr:
            nx, ny = x + dx, y + dy
            if nx < 0 or ny < 0 or nx >= w or ny >= h:
                continue
            j = ny * w + nx
            bj = base_f[j]
            if bj == math.inf:
                continue
            c = step * bj
            rj = river_f[j]
            if rj and rj != ri:
                c += 14.0 if border_river.get(rj) else 0.8
            nd = d + c
            if nd < dist[j]:
                dist[j] = nd
                label[j] = pid
                heapq.heappush(heap, (nd, j, pid))
    return np.array(label, dtype=np.int32).reshape(h, w)


def pair_counts(ids):
    """Shared edge counts between different non-negative ids: dict (a, b) -> count, a < b."""
    a1 = ids[:, :-1].ravel()
    b1 = ids[:, 1:].ravel()
    a2 = ids[:-1, :].ravel()
    b2 = ids[1:, :].ravel()
    a = np.concatenate([a1, a2])
    b = np.concatenate([b1, b2])
    m = (a != b) & (a >= 0) & (b >= 0)
    lo = np.minimum(a[m], b[m]).astype(np.int64)
    hi = np.maximum(a[m], b[m]).astype(np.int64)
    keys, counts = np.unique(lo * 100000 + hi, return_counts=True)
    return {(int(k // 100000), int(k % 100000)): int(c) for k, c in zip(keys, counts)}


def merge_small(ids, min_fraction=0.30):
    for _ in range(10):
        vals, sizes = np.unique(ids[ids >= 0], return_counts=True)
        median = np.median(sizes)
        small = {int(v) for v, s in zip(vals, sizes) if s < min_fraction * median}
        if not small:
            break
        pc = pair_counts(ids)
        best = {}
        for (a, b), c in pc.items():
            for s, o in ((a, b), (b, a)):
                if s in small and o not in small:
                    if c > best.get(s, (0, -1))[0]:
                        best[s] = (c, o)
        if not best:
            break
        lut = np.arange(-1, ids.max() + 1)  # lut[id + 1] -> new id, so -1 stays -1
        for s, (_, o) in best.items():
            lut[s + 1] = o
        ids = lut[ids + 1]
    return ids


# ---------------------------------------------------------------------------
def fill_unlabeled(ids, land, max_iter=200):
    ids = ids.copy()
    for _ in range(max_iter):
        missing = land & (ids < 0)
        if not missing.any():
            break
        cand = ids.copy()
        for sl_dst, sl_src in (((slice(1, None), slice(None)), (slice(None, -1), slice(None))),
                               ((slice(None, -1), slice(None)), (slice(1, None), slice(None))),
                               ((slice(None), slice(1, None)), (slice(None), slice(None, -1))),
                               ((slice(None), slice(None, -1)), (slice(None), slice(1, None)))):
            take = (cand[sl_dst] < 0) & (ids[sl_src] >= 0)
            cand[sl_dst] = np.where(take, ids[sl_src], cand[sl_dst])
        ids = np.where(missing, cand, ids)
    return ids


def upsample(ctx, ids128):
    X, Y = ctx["X"], ctx["Y"]
    Xk, Yk = X / 1000.0, Y / 1000.0
    p = Perlin(L.WORLD_SEED + 103)
    wx = X + 85.0 * fbm(p, Xk / 0.9, Yk / 0.9, 3) + 28.0 * fbm(p, Xk / 0.25 + 3.0, Yk / 0.25, 2)
    wy = Y + 85.0 * fbm(p, Xk / 0.9 + 17.0, Yk / 0.9, 3) + 28.0 * fbm(p, Xk / 0.25, Yk / 0.25 + 5.0, 2)
    cx = np.clip((wx / C128).astype(np.int64), 0, ids128.shape[1] - 1)
    cy = np.clip((wy / C128).astype(np.int64), 0, ids128.shape[0] - 1)
    ids = ids128[cy, cx]
    land = ctx["land64"]
    ids = np.where(land, ids, -1)
    return fill_unlabeled(ids, land)


def enforce_contiguity(ids, land):
    for _ in range(6):
        labels, sizes, values = label_regions(ids, ignore=-1)
        largest = {}
        for lab in range(1, len(sizes)):
            v = values[lab]
            if v not in largest or sizes[lab] > sizes[largest[v]]:
                largest[v] = lab
        keep_lab = np.zeros(len(sizes), dtype=bool)
        for lab in largest.values():
            keep_lab[lab] = True
        fragment = (labels > 0) & ~keep_lab[labels]
        if not fragment.any():
            break
        ids = np.where(fragment, -1, ids)
        ids = fill_unlabeled(ids, land)
    return ids


def renumber(ids, ctx):
    X, Y = ctx["X"], ctx["Y"]
    vals = np.unique(ids[ids >= 0])
    lut = np.full(vals.max() + 2, -1, dtype=np.int64)
    flat = ids.ravel()
    m = flat >= 0
    cnt = np.bincount(flat[m], minlength=vals.max() + 1)
    sx = np.bincount(flat[m], weights=X.ravel()[m], minlength=vals.max() + 1)
    sy = np.bincount(flat[m], weights=Y.ravel()[m], minlength=vals.max() + 1)
    order = sorted(vals.tolist(), key=lambda v: (int((sy[v] / cnt[v]) // 6000.0), sx[v] / cnt[v]))
    for new, old in enumerate(order):
        lut[old + 1] = new
    return lut[ids + 1], len(order)


# ---------------------------------------------------------------------------
def describe(ctx, ids, n, biome_defs):
    X, Y = ctx["X"].ravel(), ctx["Y"].ravel()
    flat = ids.ravel()
    m = flat >= 0
    idx = flat[m]
    cells = np.bincount(idx, minlength=n).astype(np.float64)
    cx = np.bincount(idx, weights=X[m], minlength=n) / cells
    cy = np.bincount(idx, weights=Y[m], minlength=n) / cells
    elev = ctx["elev64"].ravel().astype(np.float64)
    e_mean = np.bincount(idx, weights=elev[m], minlength=n) / cells
    e_max = np.full(n, -1e9)
    np.maximum.at(e_max, idx, elev[m])
    forest = np.bincount(idx, weights=ctx["forest64"].ravel()[m] / 255.0, minlength=n) / cells
    fert_table = np.zeros(256)
    for d in biome_defs:
        fert_table[d["index"]] = d["fertility"]
    biome = ctx["biome64"].ravel()
    fert = np.bincount(idx, weights=fert_table[biome[m]], minlength=n) / cells
    bmix = np.bincount(idx * 16 + biome[m], minlength=n * 16).reshape(n, 16) / cells[:, None]
    moist = np.bincount(idx, weights=ctx["moisture64"].ravel()[m], minlength=n) / cells
    temp = np.bincount(idx, weights=ctx["temperature64"].ravel()[m], minlength=n) / cells

    land = ctx["land64"]
    sea_adj = np.zeros(land.shape, dtype=bool)
    sea = ~land
    sea_adj[1:, :] |= sea[:-1, :]
    sea_adj[:-1, :] |= sea[1:, :]
    sea_adj[:, 1:] |= sea[:, :-1]
    sea_adj[:, :-1] |= sea[:, 1:]
    coast_cells = np.bincount(idx, weights=(sea_adj & land).ravel()[m], minlength=n)
    river64 = (ctx["water32"][::2, ::2] == 3) | (ctx["water32"][1::2, 1::2] == 3)
    river_cells = np.bincount(idx, weights=river64.ravel()[m], minlength=n)
    lake64 = ctx["lake64"]
    lake_adj = lake64.copy()
    lake_adj[1:, :] |= lake64[:-1, :]
    lake_adj[:-1, :] |= lake64[1:, :]
    lake_adj[:, 1:] |= lake64[:, :-1]
    lake_adj[:, :-1] |= lake64[:, 1:]
    lake_cells = np.bincount(idx, weights=lake_adj.ravel()[m], minlength=n)

    # label point: land cell farthest from the province edge
    edge = np.zeros(ids.shape, dtype=bool)
    edge[1:, :] |= ids[1:, :] != ids[:-1, :]
    edge[:-1, :] |= ids[:-1, :] != ids[1:, :]
    edge[:, 1:] |= ids[:, 1:] != ids[:, :-1]
    edge[:, :-1] |= ids[:, :-1] != ids[:, 1:]
    dist = distance_from(edge | ~land, 60, within=land).ravel()
    lake_flat = lake64.ravel()
    score = np.where(lake_flat, -1.0, dist)
    order = np.lexsort((-score[m], idx))
    sorted_ids = idx[order]
    first = np.flatnonzero(np.concatenate(([True], sorted_ids[1:] != sorted_ids[:-1])))
    positions = np.flatnonzero(m)[order[first]]
    center_x = X[positions]
    center_y = Y[positions]
    inner = score[positions]

    names_by_index = {d["index"]: d["id"] for d in biome_defs}
    provinces = []
    for p in range(n):
        mix = bmix[p]
        share = lambda *names: float(sum(mix[BIOME[k]] for k in names))
        top = np.argsort(-mix)[:3]
        terrain = classify_terrain(share, forest[p], e_mean[p], coast_cells[p] / cells[p])
        provinces.append({
            "id": p,
            "cells": int(cells[p]),
            "area_km2": round(cells[p] * CELL * CELL / 1e6, 2),
            "centroid": [round(cx[p], 1), round(cy[p], 1)],
            "center": [round(float(center_x[p]), 1), round(float(center_y[p]), 1)],
            "inner_radius_m": round(float(inner[p]) * CELL, 1),
            "elevation_mean": round(float(e_mean[p]), 1),
            "elevation_max": round(float(e_max[p]), 1),
            "forest": round(float(forest[p]), 3),
            "fertility": round(float(fert[p]), 3),
            "moisture": round(float(moist[p]), 3),
            "temperature": round(float(temp[p]), 3),
            "coastal": bool(coast_cells[p] >= 4),
            "river": bool(river_cells[p] >= 3),
            "lake": bool(lake_cells[p] >= 3),
            "terrain": terrain,
            "biomes": {names_by_index[int(b)]: round(float(mix[b]), 3) for b in top if mix[b] > 0.02},
        })
    return provinces


def classify_terrain(share, forest, elev_mean, coast_frac):
    if share("mountain", "snow") > 0.40:
        return "mountains"
    if share("hills", "mountain", "snow") > 0.38 or elev_mean > 560:
        return "hills"
    if share("marsh") > 0.22:
        return "marsh"
    if share("desert") > 0.40:
        return "desert"
    if share("steppe") > 0.40:
        return "steppe"
    if forest > 0.50:
        return "forest"
    if coast_frac > 0.06:
        return "coast"
    return "plains"


# ---------------------------------------------------------------------------
def neighbors_and_borders(ctx, ids, provinces):
    t0 = time.time()
    land = ctx["land64"]
    elev = ctx["elev64"]
    river64 = (ctx["water32"][::2, ::2] == 3) | (ctx["water32"][1::2, 1::2] == 3) | (ctx["water32"][::2, 1::2] == 3)
    h, w = ids.shape
    edges = {}  # (a, b) -> list of segments ((x0, y0), (x1, y1)) in corner coords
    stats = {}  # (a, b) -> [count, river, mountain, min_elev]

    def add(a_arr, b_arr, e_a, e_b, r_a, r_b, ys, xs, vertical):
        for a, b, ea, eb, ra, rb, y, x in zip(a_arr.tolist(), b_arr.tolist(), e_a.tolist(), e_b.tolist(),
                                              r_a.tolist(), r_b.tolist(), ys.tolist(), xs.tolist()):
            key = (a, b) if a < b else (b, a)
            s = stats.get(key)
            if s is None:
                s = [0, 0, 0, 1e9]
                stats[key] = s
                edges[key] = []
            s[0] += 1
            if ra or rb:
                s[1] += 1
            me = 0.5 * (ea + eb)
            if me > 950.0:
                s[2] += 1
            s[3] = min(s[3], me)
            if vertical:   # between (x, y) and (x+1, y): segment at x+1 from y to y+1
                edges[key].append(((x + 1, y), (x + 1, y + 1)))
            else:          # between (x, y) and (x, y+1): segment at y+1 from x to x+1
                edges[key].append(((x, y + 1), (x + 1, y + 1)))

    a = ids[:, :-1]
    b = ids[:, 1:]
    sel = (a != b) & (a >= 0) & (b >= 0)
    ys, xs = np.nonzero(sel)
    add(a[sel], b[sel], elev[:, :-1][sel], elev[:, 1:][sel], river64[:, :-1][sel], river64[:, 1:][sel], ys, xs, True)
    a = ids[:-1, :]
    b = ids[1:, :]
    sel = (a != b) & (a >= 0) & (b >= 0)
    ys, xs = np.nonzero(sel)
    add(a[sel], b[sel], elev[:-1, :][sel], elev[1:, :][sel], river64[:-1, :][sel], river64[1:, :][sel], ys, xs, False)

    for p in provinces:
        p["neighbors"] = []
    borders = []
    for (pa, pb), (count, riv, mnt, min_e) in sorted(stats.items()):
        btype = "land"
        if riv >= 0.35 * count:
            btype = "river"
        elif mnt >= 0.5 * count:
            btype = "pass" if min_e < 1000.0 else "mountain"
        length = count * CELL
        provinces[pa]["neighbors"].append({"id": pb, "length_m": round(length), "type": btype})
        provinces[pb]["neighbors"].append({"id": pa, "length_m": round(length), "type": btype})
        for chain in link_segments(edges[(pa, pb)]):
            pts = [(x * CELL, y * CELL) for (x, y) in chain]
            closed = len(chain) > 2 and chain[0] == chain[-1]
            if len(pts) >= 3:
                pts = chaikin(pts, iterations=2, closed=False)
            pts = simplify_rdp(pts, 5.0)
            flat = []
            for (x, y) in pts:
                flat.extend([round(x, 1), round(y, 1)])
            borders.append({"a": pa, "b": pb, "type": btype, "closed": closed, "pts": flat})
    log("  neighbours and %d border chains" % len(borders), t0)
    return borders


def link_segments(segments):
    adj = {}
    for p, q in segments:
        adj.setdefault(p, []).append(q)
        adj.setdefault(q, []).append(p)
    used = set()
    chains = []

    def walk(start, nxt):
        chain = [start, nxt]
        used.add((start, nxt))
        used.add((nxt, start))
        prev, cur = start, nxt
        while len(adj[cur]) == 2:
            a, b = adj[cur]
            n2 = b if a == prev else a
            if (cur, n2) in used:
                break
            used.add((cur, n2))
            used.add((n2, cur))
            chain.append(n2)
            prev, cur = cur, n2
        return chain

    for p, ns in adj.items():
        if len(ns) != 2:
            for q in ns:
                if (p, q) not in used:
                    chains.append(walk(p, q))
    for p, ns in adj.items():
        for q in ns:
            if (p, q) not in used:
                chains.append(walk(p, q))
    return chains


# ---------------------------------------------------------------------------
def assign_cultures(provinces):
    """Cultures spread over the province graph from their heartlands. Crossing mountains, big rivers
    and passes is expensive, so cultural frontiers tend to (but do not always) follow geography."""
    rng = random.Random(L.WORLD_SEED + 104)
    edge_noise = {}
    heap = []
    best = [math.inf] * len(provinces)
    owner = [None] * len(provinces)
    for (cul, rel, cu, cv, wgt) in L.CULTURE_CENTERS:
        cx, cy = cu * L.WORLD_W_M, cv * L.WORLD_H_M
        src = min(provinces, key=lambda pr: (pr["centroid"][0] - cx) ** 2 + (pr["centroid"][1] - cy) ** 2)
        heapq.heappush(heap, (0.0, src["id"], cul, rel, wgt))
    while heap:
        d, pid, cul, rel, wgt = heapq.heappop(heap)
        if d >= best[pid]:
            continue
        best[pid] = d
        owner[pid] = (cul, rel)
        pa = provinces[pid]
        for nb in pa["neighbors"]:
            q = nb["id"]
            pb = provinces[q]
            km = math.hypot(pa["centroid"][0] - pb["centroid"][0], pa["centroid"][1] - pb["centroid"][1]) / 1000.0
            key = (min(pid, q), max(pid, q))
            if key not in edge_noise:
                edge_noise[key] = rng.uniform(0.75, 1.3)
            barrier = {"mountain": 4.0, "pass": 2.0, "river": 2.2, "land": 1.0}[nb["type"]]
            if pa["terrain"] in ("mountains",) or pb["terrain"] in ("mountains",):
                barrier += 1.0
            nd = d + km * barrier * edge_noise[key] / wgt
            if nd < best[q]:
                heapq.heappush(heap, (nd, q, cul, rel, wgt))
    for pr in provinces:
        cul, rel = owner[pr["id"]]
        pr["culture"] = cul
        pr["religion"] = rel
    # smooth isolated cultures (keep a few enclaves)
    for pr in provinces:
        ns = [provinces[n["id"]]["culture"] for n in pr["neighbors"]]
        if ns and pr["culture"] not in ns and rng.random() > 0.15:
            pr["culture"] = max(set(ns), key=ns.count)
            rels = [provinces[n["id"]]["religion"] for n in pr["neighbors"] if provinces[n["id"]]["culture"] == pr["culture"]]
            if rels:
                pr["religion"] = max(set(rels), key=rels.count)
    for pr in provinces:
        x, y = pr["centroid"]
        u, v = x / L.WORLD_W_M, y / L.WORLD_H_M
        for (pu, pv, radius, rel) in L.RELIGION_POCKETS:
            if math.hypot((u - pu) * 1.556, v - pv) < radius and rng.random() < 0.75:
                pr["religion"] = rel


def assign_names(provinces):
    gen = NameGenerator(L.WORLD_SEED + 106)
    for pr in provinces:
        pr["name"] = gen.make(pr["culture"])


def place_deposits(ctx, ids, provinces):
    rng = random.Random(L.WORLD_SEED + 107)
    elev = ctx["elev64"]
    slope = ctx["slope64"]
    biome = ctx["biome64"]
    X, Y = ctx["X"], ctx["Y"]
    flat = ids.ravel()
    order = np.argsort(flat, kind="stable")
    sorted_ids = flat[order]
    starts = np.searchsorted(sorted_ids, np.arange(len(provinces)))
    ends = np.searchsorted(sorted_ids, np.arange(len(provinces)), side="right")
    e = elev.ravel()
    s = slope.ravel()
    b = biome.ravel()
    xs = X.ravel()
    ys = Y.ravel()
    water = ctx["lake64"].ravel()
    total = 0
    for pr in provinces:
        cells = order[starts[pr["id"]]:ends[pr["id"]]]
        cells = cells[~water[cells]]
        deps = []
        hilly = pr["biomes"].get("hills", 0.0) + pr["biomes"].get("mountain", 0.0)

        def pick(mask_cells, kind, richness):
            if len(mask_cells) == 0:
                return
            c = int(mask_cells[rng.randrange(len(mask_cells))])
            deps.append({"type": kind, "x": round(float(xs[c]), 1), "y": round(float(ys[c]), 1),
                         "richness": round(richness, 2)})

        rough = cells[(e[cells] > 180) & (e[cells] < 1400) & (s[cells] > 0.06)]
        if rng.random() < 0.12 + 0.75 * min(1.0, hilly * 1.6):
            for _ in range(1 + (rng.random() < 0.35)):
                pick(rough if len(rough) else cells, "iron", rng.uniform(0.6, 1.4))
        if rng.random() < 0.40 + 0.5 * min(1.0, hilly * 2.0):
            stony = cells[(s[cells] > 0.04)]
            for _ in range(1 + int(rng.random() < 0.5) + int(rng.random() < 0.3)):
                pick(stony if len(stony) else cells, "stone", rng.uniform(0.7, 1.5))
        if pr["biomes"].get("mountain", 0.0) > 0.25 and rng.random() < 0.18:
            pick(cells[e[cells] > 900], "gold", rng.uniform(0.5, 1.2))
        if pr["coastal"] and pr["temperature"] > 0.55 and rng.random() < 0.25:
            pick(cells, "salt", rng.uniform(0.6, 1.2))
        if pr["river"] and rng.random() < 0.40:
            pick(cells[(b[cells] == BIOME["floodplain"]) | (b[cells] == BIOME["grassland"])], "clay", rng.uniform(0.6, 1.3))
        pasture = pr["biomes"].get("steppe", 0.0) + pr["biomes"].get("grassland", 0.0)
        if pasture > 0.45 and rng.random() < 0.55:
            pick(cells[(b[cells] == BIOME["steppe"]) | (b[cells] == BIOME["grassland"])], "horses", rng.uniform(0.6, 1.4))
        pr["deposits"] = deps
        total += len(deps)
    return total


# ---------------------------------------------------------------------------
def validate(provinces):
    n = len(provinces)
    seen = {0}
    stack = [0]
    while stack:
        p = stack.pop()
        for nb in provinces[p]["neighbors"]:
            if nb["id"] not in seen:
                seen.add(nb["id"])
                stack.append(nb["id"])
    areas = sorted(p["area_km2"] for p in provinces)
    report = {
        "count": n,
        "connected": len(seen) == n,
        "area_min_km2": areas[0],
        "area_median_km2": areas[n // 2],
        "area_max_km2": areas[-1],
        "without_neighbors": sum(1 for p in provinces if not p["neighbors"]),
    }
    return report


def stage_provinces(ctx, out_dir, meta, biome_defs):
    t0 = time.time()
    print("[provinces]", flush=True)
    g = build_work_grid(ctx, biome_defs)
    seeds = place_seeds(g, TARGET_PROVINCES)
    log("  %d seeds" % len(seeds), t0)
    t1 = time.time()
    ids128 = grow(g, seeds)
    ids128 = merge_small(ids128)
    log("  growth", t1)
    t2 = time.time()
    ids64 = upsample(ctx, ids128)
    ids64 = enforce_contiguity(ids64, ctx["land64"])
    ids64, n = renumber(ids64, ctx)
    log("  64 m province raster: %d provinces" % n, t2)
    provinces = describe(ctx, ids64, n, biome_defs)
    borders = neighbors_and_borders(ctx, ids64, provinces)
    assign_cultures(provinces)
    assign_names(provinces)
    n_dep = place_deposits(ctx, ids64, provinces)
    report = validate(provinces)
    print("  report: %s, deposits %d" % (report, n_dep), flush=True)

    raster = np.where(ids64 >= 0, ids64, 65535).astype(np.uint16)
    meta.setdefault("rasters", {})["province"] = dict(write_raster(os.path.join(out_dir, "province.bin"), raster),
                                                        cell_m=CELL, format="RG8", none=65535)
    meta["province_count"] = n
    meta["province_report"] = report
    write_json(os.path.join(out_dir, "provinces.json"), {"version": 1, "count": n, "provinces": provinces})
    write_json(os.path.join(out_dir, "borders.json"), {"version": 1, "borders": borders}, compact=True)
    ctx["province64"] = ids64
    ctx["provinces"] = provinces
    _preview(ctx, ids64, provinces)
    print("[provinces] done in %.1f s" % (time.time() - t0), flush=True)


def _preview(ctx, ids, provinces):
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "out_preview")
    os.makedirs(out, exist_ok=True)
    rng = np.random.default_rng(3)
    cols = rng.integers(60, 230, size=(len(provinces) + 1, 3)).astype(np.uint8)
    img = cols[np.where(ids >= 0, ids, len(provinces))]
    img[ids < 0] = (35, 70, 100)
    edge = np.zeros(ids.shape, dtype=bool)
    edge[:, 1:] |= ids[:, 1:] != ids[:, :-1]
    edge[1:, :] |= ids[1:, :] != ids[:-1, :]
    img[edge & (ids >= 0)] = (30, 25, 20)
    write_png(os.path.join(out, "provinces.png"), img)
    culture_cols = {"germanic": (111, 127, 154), "latin": (176, 138, 63), "slavic": (95, 154, 106),
                    "hellenic": (63, 143, 176), "arab": (201, 165, 90), "asian": (176, 80, 63)}
    lut = np.array([culture_cols[p["culture"]] for p in provinces] + [(35, 70, 100)], dtype=np.uint8)
    cimg = lut[np.where(ids >= 0, ids, len(provinces))]
    cimg[edge & (ids >= 0)] = (30, 25, 20)
    write_png(os.path.join(out, "cultures.png"), cimg)
    rel_cols = {"catholic": (216, 201, 160), "orthodox": (201, 162, 74), "muslim": (62, 138, 94), "hindu": (208, 122, 58)}
    lut = np.array([rel_cols[p["religion"]] for p in provinces] + [(35, 70, 100)], dtype=np.uint8)
    rimg = lut[np.where(ids >= 0, ids, len(provinces))]
    rimg[edge & (ids >= 0)] = (30, 25, 20)
    write_png(os.path.join(out, "religions.png"), rimg)

