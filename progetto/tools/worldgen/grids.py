"""Grid utilities: run-based connected components, distance fields, resampling, polylines."""
import numpy as np


# ---------------------------------------------------------------------------
# connected components (4-connectivity) with run-length union-find: fast in pure python
# ---------------------------------------------------------------------------

def label_components(mask):
    """Returns (labels int32 array, sizes list). Label 0 = background, components 1..n."""
    mask = np.asarray(mask, dtype=bool)
    h, w = mask.shape
    parent = []
    runs = []  # (y, x0, x1, run_id)

    def find(a):
        root = a
        while parent[root] != root:
            root = parent[root]
        while parent[a] != root:
            parent[a], a = root, parent[a]
        return root

    prev = []
    for y in range(h):
        row = mask[y]
        padded = np.concatenate(([False], row, [False])).astype(np.int8)
        d = np.diff(padded)
        starts = np.flatnonzero(d == 1)
        ends = np.flatnonzero(d == -1)
        cur = []
        for x0, x1 in zip(starts.tolist(), ends.tolist()):
            rid = len(parent)
            parent.append(rid)
            runs.append((y, x0, x1, rid))
            cur.append((x0, x1, rid))
        # union with previous row
        i = j = 0
        while i < len(prev) and j < len(cur):
            a0, a1, aid = prev[i]
            b0, b1, bid = cur[j]
            if a0 < b1 and b0 < a1:
                ra, rb = find(aid), find(bid)
                if ra != rb:
                    parent[rb] = ra
            if a1 < b1:
                i += 1
            else:
                j += 1
        prev = cur

    labels = np.zeros((h, w), dtype=np.int32)
    root_to_label = {}
    sizes = [0]
    for (y, x0, x1, rid) in runs:
        r = find(rid)
        lab = root_to_label.get(r)
        if lab is None:
            lab = len(sizes)
            root_to_label[r] = lab
            sizes.append(0)
        labels[y, x0:x1] = lab
        sizes[lab] += x1 - x0
    return labels, sizes


def label_regions(ids, ignore=-1):
    """Connected components of equal integer values (4-connectivity). Returns (labels, sizes, values)
    where values[label] is the id of that component. Cells equal to `ignore` get label 0."""
    ids = np.asarray(ids)
    h, w = ids.shape
    parent = []
    runs = []
    run_value = []

    def find(a):
        root = a
        while parent[root] != root:
            root = parent[root]
        while parent[a] != root:
            parent[a], a = root, parent[a]
        return root

    prev = []
    for y in range(h):
        row = ids[y]
        change = np.flatnonzero(np.diff(row)) + 1
        starts = np.concatenate(([0], change))
        ends = np.concatenate((change, [w]))
        vals = row[starts]
        cur = []
        for x0, x1, v in zip(starts.tolist(), ends.tolist(), vals.tolist()):
            if v == ignore:
                continue
            rid = len(parent)
            parent.append(rid)
            run_value.append(v)
            runs.append((y, x0, x1, rid))
            cur.append((x0, x1, rid, v))
        i = j = 0
        while i < len(prev) and j < len(cur):
            a0, a1, aid, av = prev[i]
            b0, b1, bid, bv = cur[j]
            if a0 < b1 and b0 < a1 and av == bv:
                ra, rb = find(aid), find(bid)
                if ra != rb:
                    parent[rb] = ra
            if a1 < b1:
                i += 1
            else:
                j += 1
        prev = cur

    labels = np.zeros((h, w), dtype=np.int32)
    root_to_label = {}
    sizes = [0]
    values = [ignore]
    for (y, x0, x1, rid) in runs:
        r = find(rid)
        lab = root_to_label.get(r)
        if lab is None:
            lab = len(sizes)
            root_to_label[r] = lab
            sizes.append(0)
            values.append(run_value[rid])
        labels[y, x0:x1] = lab
        sizes[lab] += x1 - x0
    return labels, sizes, values


def keep_largest(mask):
    labels, sizes = label_components(mask)
    if len(sizes) <= 1:
        return mask.copy()
    biggest = int(np.argmax(sizes[1:])) + 1
    return labels == biggest


# ---------------------------------------------------------------------------
# morphology and distance (capped, octagonal approximation)
# ---------------------------------------------------------------------------

def dilate4(m):
    out = m.copy()
    out[1:, :] |= m[:-1, :]
    out[:-1, :] |= m[1:, :]
    out[:, 1:] |= m[:, :-1]
    out[:, :-1] |= m[:, 1:]
    return out


def dilate8(m):
    out = dilate4(m)
    out[1:, 1:] |= m[:-1, :-1]
    out[1:, :-1] |= m[:-1, 1:]
    out[:-1, 1:] |= m[1:, :-1]
    out[:-1, :-1] |= m[1:, 1:]
    return out


def distance_from(source_mask, cap, within=None):
    """Cell distance from source cells (0 at sources), capped. `within` restricts propagation."""
    dist = np.full(source_mask.shape, cap, dtype=np.float32)
    visited = source_mask.copy()
    dist[visited] = 0.0
    frontier = visited.copy()
    for k in range(1, int(cap)):
        grown = dilate8(frontier) if k % 2 == 0 else dilate4(frontier)
        new = grown & ~visited
        if within is not None:
            new &= within
        if not new.any():
            break
        dist[new] = k
        visited |= new
        frontier = new
    return dist


def box_blur(a, radius, passes=1):
    """Separable box blur via cumulative sums (edges clamped)."""
    out = a.astype(np.float64)
    for _ in range(passes):
        for axis in (0, 1):
            pad = [(0, 0), (0, 0)]
            pad[axis] = (radius + 1, radius)
            p = np.pad(out, pad, mode="edge")
            c = np.cumsum(p, axis=axis)
            n = out.shape[axis]
            if axis == 0:
                out = (c[2 * radius + 1:2 * radius + 1 + n, :] - c[0:n, :]) / (2 * radius + 1)
            else:
                out = (c[:, 2 * radius + 1:2 * radius + 1 + n] - c[:, 0:n]) / (2 * radius + 1)
    return out


# ---------------------------------------------------------------------------
# resampling
# ---------------------------------------------------------------------------

def bilinear_sample(grid, xs, ys):
    """Sample grid (h,w) at float cell coordinates xs, ys (cell centres at integer + 0.5 handled by caller)."""
    h, w = grid.shape
    x = np.clip(xs, 0.0, w - 1.001)
    y = np.clip(ys, 0.0, h - 1.001)
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    fx = x - x0
    fy = y - y0
    g00 = grid[y0, x0]
    g10 = grid[y0, x0 + 1]
    g01 = grid[y0 + 1, x0]
    g11 = grid[y0 + 1, x0 + 1]
    return (g00 * (1 - fx) + g10 * fx) * (1 - fy) + (g01 * (1 - fx) + g11 * fx) * fy


def resize_bilinear(grid, new_h, new_w):
    h, w = grid.shape
    ys = (np.arange(new_h) + 0.5) * (h / new_h) - 0.5
    xs = (np.arange(new_w) + 0.5) * (w / new_w) - 0.5
    X, Y = np.meshgrid(xs, ys)
    return bilinear_sample(grid.astype(np.float64), X, Y)


def resize_nearest(grid, new_h, new_w):
    h, w = grid.shape
    ys = np.minimum(((np.arange(new_h) + 0.5) * (h / new_h)).astype(np.int64), h - 1)
    xs = np.minimum(((np.arange(new_w) + 0.5) * (w / new_w)).astype(np.int64), w - 1)
    return grid[ys[:, None], xs[None, :]]


# ---------------------------------------------------------------------------
# polylines
# ---------------------------------------------------------------------------

def distance_to_polyline(px, py, points):
    """Euclidean distance from arrays (px, py) to a polyline [(x, y), ...] in the same units.
    Also returns the fractional position t along the whole polyline (0..1) of the closest point."""
    best = np.full(px.shape, np.inf)
    best_t = np.zeros(px.shape)
    lengths = []
    total = 0.0
    for i in range(len(points) - 1):
        ax, ay = points[i]
        bx, by = points[i + 1]
        seg = ((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5
        lengths.append((total, seg))
        total += seg
    for i in range(len(points) - 1):
        ax, ay = points[i]
        bx, by = points[i + 1]
        dx, dy = bx - ax, by - ay
        l2 = dx * dx + dy * dy
        t = np.clip(((px - ax) * dx + (py - ay) * dy) / l2, 0.0, 1.0)
        qx = ax + t * dx
        qy = ay + t * dy
        d = np.hypot(px - qx, py - qy)
        closer = d < best
        best = np.where(closer, d, best)
        start, seg = lengths[i]
        best_t = np.where(closer, (start + t * seg) / max(total, 1e-9), best_t)
    return best, best_t


def chaikin(points, iterations=2, closed=False):
    pts = [tuple(p) for p in points]
    for _ in range(iterations):
        if len(pts) < 3:
            return pts
        out = [] if closed else [pts[0]]
        n = len(pts)
        rng = range(n) if closed else range(n - 1)
        for i in rng:
            p = pts[i]
            q = pts[(i + 1) % n]
            out.append(tuple(0.75 * a + 0.25 * b for a, b in zip(p, q)))
            out.append(tuple(0.25 * a + 0.75 * b for a, b in zip(p, q)))
        if not closed:
            out.append(pts[-1])
        pts = out
    return pts


def simplify_rdp(points, epsilon):
    """Ramer-Douglas-Peucker on (x, y, ...) tuples using x, y."""
    if len(points) < 3:
        return list(points)
    pts = np.asarray([(p[0], p[1]) for p in points], dtype=np.float64)
    keep = np.zeros(len(points), dtype=bool)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        if b <= a + 1:
            continue
        ax, ay = pts[a]
        bx, by = pts[b]
        seg = pts[a + 1:b]
        dx, dy = bx - ax, by - ay
        norm = (dx * dx + dy * dy) ** 0.5
        if norm < 1e-9:
            d = np.hypot(seg[:, 0] - ax, seg[:, 1] - ay)
        else:
            d = np.abs(dy * seg[:, 0] - dx * seg[:, 1] + bx * ay - by * ax) / norm
        i = int(np.argmax(d))
        if d[i] > epsilon:
            idx = a + 1 + i
            keep[idx] = True
            stack.append((a, idx))
            stack.append((idx, b))
    return [p for p, k in zip(points, keep) if k]

