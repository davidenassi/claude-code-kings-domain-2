"""Hydrology on a coarse height grid: depression filling, flow, lakes, river polylines."""
import heapq

import numpy as np

from grids import label_components

# D8 neighbour offsets
D8 = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
D8_DIST = [1.0, 1.0, 1.0, 1.0, 2 ** 0.5, 2 ** 0.5, 2 ** 0.5, 2 ** 0.5]


def priority_flood(height, land):
    """Fill depressions so every land cell drains to the sea. Returns filled heights (float64).
    Uses an epsilon gradient so flats still drain."""
    h, w = height.shape
    filled = height.astype(np.float64).copy()
    done = ~land.copy()  # sea cells are outlets
    heap = []
    eps = 1e-3
    # seeds: land cells touching sea or the grid edge
    border = np.zeros_like(land)
    border[0, :] = border[-1, :] = True
    border[:, 0] = border[:, -1] = True
    sea = ~land
    touch = np.zeros_like(land)
    touch[1:, :] |= sea[:-1, :]
    touch[:-1, :] |= sea[1:, :]
    touch[:, 1:] |= sea[:, :-1]
    touch[:, :-1] |= sea[:, 1:]
    seeds = land & (touch | border)
    ys, xs = np.nonzero(seeds)
    for y, x in zip(ys.tolist(), xs.tolist()):
        heapq.heappush(heap, (filled[y, x], y, x))
        done[y, x] = True
    flat = filled.ravel()
    done_flat = done.ravel()
    while heap:
        z, y, x = heapq.heappop(heap)
        for dx, dy in D8[:4]:
            nx, ny = x + dx, y + dy
            if nx < 0 or ny < 0 or nx >= w or ny >= h:
                continue
            i = ny * w + nx
            if done_flat[i]:
                continue
            done_flat[i] = True
            nz = flat[i]
            if nz <= z:
                nz = z + eps
                flat[i] = nz
            heapq.heappush(heap, (nz, ny, nx))
    return filled


def flow_directions(filled, land):
    """Index (0..7) of the steepest D8 descent, -1 for sea/outlets."""
    h, w = filled.shape
    best_drop = np.full((h, w), 0.0)
    direction = np.full((h, w), -1, dtype=np.int8)
    pad = np.pad(filled, 1, mode="edge")
    padland = np.pad(land, 1, mode="constant", constant_values=False)
    for k, (dx, dy) in enumerate(D8):
        neigh = pad[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
        nland = padland[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
        # draining into the sea counts as a big drop
        drop = np.where(nland, (filled - neigh) / D8_DIST[k], 1e6)
        better = (drop > best_drop) & land
        best_drop = np.where(better, drop, best_drop)
        direction = np.where(better, k, direction).astype(np.int8)
    return direction


def accumulation(filled, land, direction):
    """Number of upstream cells (including itself) for every land cell."""
    h, w = filled.shape
    acc = np.where(land, 1.0, 0.0).ravel()
    order = np.argsort(-filled.ravel(), kind="stable")
    land_flat = land.ravel()
    dir_flat = direction.ravel()
    dxs = [d[0] for d in D8]
    dys = [d[1] for d in D8]
    for i in order.tolist():
        if not land_flat[i]:
            continue
        k = dir_flat[i]
        if k < 0:
            continue
        x = i % w + dxs[k]
        y = i // w + dys[k]
        if 0 <= x < w and 0 <= y < h:
            acc[y * w + x] += acc[i]
    return acc.reshape(h, w)


def find_lakes(height, filled, land, min_cells, min_depth, max_lakes=1000):
    """Depressions deeper than min_depth and larger than min_cells become lakes (largest first, capped).
    A lake covers every cell of its depression that is actually under the water level."""
    depth = filled - height
    candidate = land & (depth > min_depth)
    labels, sizes = label_components(candidate)
    order = sorted(range(1, len(sizes)), key=lambda lab: -sizes[lab])
    lake = np.zeros_like(land)
    lakes = []
    submerged = land & (depth > 0.5)
    sub_labels, _ = label_components(submerged)
    for lab in order:
        if sizes[lab] < min_cells or len(lakes) >= max_lakes:
            break
        core = labels == lab
        # grow to the whole submerged depression containing the deep core
        sub_ids = np.unique(sub_labels[core])
        sub_ids = sub_ids[sub_ids > 0]
        m = np.isin(sub_labels, sub_ids)
        lake |= m
        ys, xs = np.nonzero(m)
        lakes.append({"cells": int(m.sum()), "level": float(filled[m].max()),
                      "cx": float(xs.mean()), "cy": float(ys.mean())})
    return lake, lakes


def trace_rivers(acc, direction, land, lake, threshold_cells):
    """Returns list of rivers, each a list of (x, y, acc) cell coordinates from source to mouth.
    Tributaries stop at the junction cell (included), so the network has no duplicated segments."""
    h, w = acc.shape
    is_river = land & (acc >= threshold_cells) & ~lake
    visited = np.zeros((h, w), dtype=bool)
    dxs = [d[0] for d in D8]
    dys = [d[1] for d in D8]
    # a source is a river cell with no river cell flowing into it
    has_upstream = np.zeros((h, w), dtype=bool)
    ys, xs = np.nonzero(is_river)
    for y, x in zip(ys.tolist(), xs.tolist()):
        k = direction[y, x]
        if k < 0:
            continue
        nx, ny = x + dxs[k], y + dys[k]
        if 0 <= nx < w and 0 <= ny < h:
            has_upstream[ny, nx] = True
    sources = [(x, y) for y, x in zip(ys.tolist(), xs.tolist()) if not has_upstream[y, x]]

    # longest source->mouth paths first, so main stems stay continuous through junctions
    def steps_to_mouth(sx, sy):
        n = 0
        x, y = sx, sy
        while n < h + w:
            k = direction[y, x]
            if k < 0 or not land[y, x] or lake[y, x]:
                break
            x, y = x + dxs[k], y + dys[k]
            if not (0 <= x < w and 0 <= y < h):
                break
            n += 1
        return n

    sources.sort(key=lambda p: -steps_to_mouth(p[0], p[1]))
    rivers = []
    for sx, sy in sources:
        path = []
        x, y = sx, sy
        while True:
            if visited[y, x]:
                path.append((x, y, float(acc[y, x])))
                break
            visited[y, x] = True
            path.append((x, y, float(acc[y, x])))
            if not land[y, x] or lake[y, x]:
                break
            k = direction[y, x]
            if k < 0:
                break
            nx, ny = x + dxs[k], y + dys[k]
            if not (0 <= nx < w and 0 <= ny < h):
                break
            x, y = nx, ny
            if not land[y, x]:
                path.append((x, y, float(acc[path[-1][1], path[-1][0]])))
                break
        if len(path) >= 4:
            rivers.append(path)
    # sort by total length (longest first) for stable ids
    rivers.sort(key=lambda r: -len(r))
    return rivers

