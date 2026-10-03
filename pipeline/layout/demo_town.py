"""Demonstration settlement of the Valle di Altavera (Phase 1 graphics test, not final gameplay).

* Altavera: a compact walled town north of the Rocca - irregular wall ring (8 sides, 3 gates, towers),
  winding streets, a ring lane, a market square, houses packed along the streets and inside the blocks,
  castle on the Rocca, two bridges.
* Eleven hamlets spread over the valley floor, each with a farm, houses, an orchard, haystacks and
  a patchwork of fields; quarry, mine, sawmill and windmill.
* Country roads routed over the terrain with A* (slope, water, forest and bank costs) and merged into
  a network; rivers are crossed only at the bridges.
* Hedgerows, orchards and roadside trees (exported as vegetation instances, drawn by the MultiMesh layer).

Every placement is validated against the terrain (water, slope, overlaps, roads).
Writes game/data/valley/demo_town.json and a plan image in the scratch/cache folder.
"""
from __future__ import annotations

import heapq
import json
import math
import os
import sys

import numba as nb
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from kd import const as K  # noqa: E402
from terrain import noise as N  # noqa: E402

CACHE = os.path.join(K.CACHE_DIR, "terrain")
Y0 = int(-K.NORTH_PAD_M)
rng = np.random.default_rng(2026)

H = np.load(os.path.join(CACHE, "h_final.npy"))
SLOPE = np.load(os.path.join(CACHE, "slope.npy"))
WET = np.load(os.path.join(CACHE, "wet.npy"))
DW = np.load(os.path.join(CACHE, "d_water.npy"))
FD = np.load(os.path.join(CACHE, "forest_density.npy"))
NY, NX = H.shape


def at(grid, x, y):
    return grid[int(np.clip(y - Y0, 0, grid.shape[0] - 1)), int(np.clip(x, 0, grid.shape[1] - 1))]


def slope_deg(x, y):
    return math.degrees(at(SLOPE, x, y))


# footprints (w, d) in metres, used for spacing / overlap tests
FOOT = {
    "house_a": (7, 6), "house_b": (8, 6), "house_c": (9, 5.5), "house_d": (8.5, 6.5), "house_e": (6.5, 5.5),
    "house_rich_a": (10, 8), "house_rich_b": (8.5, 9), "house_rich_c": (11, 8), "farm": (19, 13),
    "granary": (8.6, 7.5), "sawmill": (22, 10), "quarry": (24, 14), "mine": (18, 14), "windmill": (7, 7),
    "blacksmith": (12, 6.5), "barracks": (17, 14), "stable": (24, 8), "tower": (6.5, 6.5),
    "townhall": (15, 10), "castle": (40, 50), "well": (3, 3), "wall_tower": (6.4, 6.4), "gatehouse": (14, 7),
    "gatehouse_ns": (7, 14), "church": (14, 24),
    "stall_a": (4, 2.4), "stall_b": (4, 2.4), "stall_c": (4, 2.4), "stall_d": (4, 2.4), "stall_e": (4, 2.4),
}
RICH = ["house_rich_a", "house_rich_b", "house_rich_c"]
SIMPLE = ["house_a", "house_b", "house_c", "house_d", "house_e"]
for _b in RICH + SIMPLE:
    w_, d_ = FOOT[_b]
    FOOT[_b + "_e"] = (d_, w_)
    FOOT[_b + "_w"] = (d_, w_)

buildings, roads, plazas, fields, props, veg, yards, citizens = [], [], [], [], [], [], [], []


# ------------------------------------------------------------------------------------------------
# spatial index of occupied rectangles
class Occ:
    def __init__(self, cell=16.0):
        self.c = cell
        self.g: dict = {}

    def _cells(self, x0, y0, x1, y1):
        c = self.c
        for i in range(int(x0 // c), int(x1 // c) + 1):
            for j in range(int(y0 // c), int(y1 // c) + 1):
                yield (i, j)

    def add(self, cx, cy, hw, hd):
        r = (cx, cy, hw, hd)
        for k in self._cells(cx - hw, cy - hd, cx + hw, cy + hd):
            self.g.setdefault(k, []).append(r)

    def free(self, cx, cy, w, d, margin=1.5):
        hw, hd = w / 2 + margin, d / 2 + margin
        for k in self._cells(cx - hw, cy - hd, cx + hw, cy + hd):
            for ox, oy, ohw, ohd in self.g.get(k, ()):
                if abs(cx - ox) < ohw + hw and abs(cy - oy) < ohd + hd:
                    return False
        return True


OCC = Occ()
ROADD = None            # distance to the nearest road edge (1 m raster), built once the roads exist


def road_clear(x, y, need):
    if ROADD is None:
        return True
    return at(ROADD, x, y) >= need


def site_ok(cx, cy, w, d, max_slope=9.0, water_gap=4.0, road_gap=0.5, max_forest=1.0):
    for fx in (-0.5, 0, 0.5):
        for fy in (-0.5, 0, 0.5):
            x, y = cx + fx * w, cy + fy * d
            if at(WET, x, y) > 0.5 or at(DW, x, y) < water_gap or slope_deg(x, y) > max_slope:
                return False
            if not road_clear(x, y, road_gap) or at(FD, x, y) > max_forest:
                return False
    return True


def place(btype, x, y, layer="objects", force=False, yard=True, margin=1.2, z=None, **kw):
    w, d = FOOT.get(btype, (6, 6))
    if not force and (not OCC.free(x, y, w, d, margin) or not site_ok(x, y, w, d, **kw)):
        return False
    b = {"type": btype, "x": round(float(x), 2), "y": round(float(y), 2), "layer": layer}
    if z is not None:
        b["z"] = z
    buildings.append(b)
    OCC.add(x, y, w / 2, d / 2)
    if yard and layer == "objects":
        yards.append({"x": round(float(x), 2), "y": round(float(y) + 0.6, 2), "w": round(w + 3, 1),
                      "d": round(d + 3, 1)})
    return True


def add_road(kind, pts, width):
    roads.append({"kind": kind, "width": width, "points": [[round(float(a), 2), round(float(b), 2)] for a, b in pts]})


def tree(t, x, y, s=1.0):
    veg.append({"type": t, "x": round(float(x), 2), "y": round(float(y), 2), "scale": round(float(s), 2)})


# ------------------------------------------------------------------------------------------------
# geometry helpers
def point_in_poly(x, y, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1 + 1e-9) + x1:
            inside = not inside
    return inside


def seg_dist(px, py, a, b):
    ax, ay = a
    bx, by = b
    abx, aby = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * abx + (py - ay) * aby) / max(abx * abx + aby * aby, 1e-9)))
    return math.hypot(ax + abx * t - px, ay + aby * t - py)


def poly_edge_dist(x, y, poly):
    return min(seg_dist(x, y, poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly)))


def inset(poly, d):
    """Inset a convex polygon (any orientation) by d metres."""
    P = np.array(poly, float)
    area = 0.5 * np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1])
    s = 1.0 if area > 0 else -1.0
    lines = []
    n = len(P)
    for i in range(n):
        a, b = P[i], P[(i + 1) % n]
        t = (b - a) / np.linalg.norm(b - a)
        nrm = np.array([-t[1], t[0]]) * s                       # inward normal
        lines.append((a + nrm * d, t))
    out = []
    for i in range(n):
        (p1, t1), (p2, t2) = lines[i - 1], lines[i]
        A = np.array([t1, -t2]).T
        u = np.linalg.solve(A, p2 - p1)
        out.append(p1 + t1 * u[0])
    return [tuple(map(float, q)) for q in out]


def simplify(pts, tol):
    pts = np.asarray(pts, float)
    if len(pts) < 3:
        return pts
    a, b = pts[0], pts[-1]
    ab = b - a
    L = np.linalg.norm(ab)
    if L < 1e-9:
        d = np.linalg.norm(pts - a, axis=1)
    else:
        d = np.abs(ab[0] * (pts[:, 1] - a[1]) - ab[1] * (pts[:, 0] - a[0])) / L
    i = int(np.argmax(d))
    if d[i] > tol:
        return np.vstack([simplify(pts[:i + 1], tol)[:-1], simplify(pts[i:], tol)])
    return np.array([a, b])


def catmull(pts, step):
    p = np.asarray(pts, float)
    if len(p) < 3:
        return p
    dense = []
    for i in range(len(p) - 1):
        a, b, c, d = p[max(i - 1, 0)], p[i], p[i + 1], p[min(i + 2, len(p) - 1)]
        n = max(2, int(np.linalg.norm(c - b) / 1.0))
        for k in range(n):
            t = k / n
            dense.append(0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t
                                + (-a + 3 * b - 3 * c + d) * t ** 3))
    dense.append(p[-1])
    dense = np.array(dense)
    out = [dense[0]]
    acc = 0.0
    for i in range(1, len(dense)):
        acc += np.linalg.norm(dense[i] - dense[i - 1])
        if acc >= step:
            out.append(dense[i])
            acc = 0.0
    if np.linalg.norm(out[-1] - dense[-1]) > 0.5:
        out.append(dense[-1])
    return np.array(out)


def polyline_len(pts):
    p = np.asarray(pts, float)
    return float(np.sum(np.linalg.norm(np.diff(p, axis=0), axis=1)))


# ------------------------------------------------------------------------------------------------
# road router: A* on a 4 m cost grid
CELL = 4
ny4, nx4 = NY // CELL, NX // CELL


def pool(a, op):
    v = a[:ny4 * CELL, :nx4 * CELL].reshape(ny4, CELL, nx4, CELL)
    return op(v, axis=(1, 3))


wet4 = pool(WET, np.max)
sl4 = np.degrees(pool(SLOPE, np.mean))
fd4 = pool(FD, np.mean)
dw4 = pool(DW, np.min)
g4 = (CELL / 2, Y0 + CELL / 2, float(CELL), nx4, ny4)
wob = N.fbm(g4, 160.0, 991, 3) * 0.5 + 0.5
COST = (1.0 + (sl4 / 6.5) ** 2 + 1.6 * fd4 + 2.5 * (dw4 < 10) + 0.6 * wob).astype(np.float64)
COST[sl4 > 24] += 80.0
COST[wet4 > 0.2] = 1e30
NET = np.zeros((ny4, nx4), bool)


@nb.njit(cache=True)
def astar(cost, net, sy, sx, gy, gx, road_cost, hmin):
    ny, nx = cost.shape
    n = ny * nx
    g = np.full(n, 1e30)
    prev = np.full(n, -1, np.int64)
    closed = np.zeros(n, np.uint8)
    s = sy * nx + sx
    t = gy * nx + gx
    g[s] = 0.0
    heap = [(hmin * math.hypot(sy - gy, sx - gx), s)]
    dys = (-1, -1, -1, 0, 0, 1, 1, 1)
    dxs = (-1, 0, 1, -1, 1, -1, 0, 1)
    while len(heap) > 0:
        f, u = heapq.heappop(heap)
        if closed[u]:
            continue
        closed[u] = 1
        if u == t:
            break
        uy = u // nx
        ux = u % nx
        cu = road_cost if (net[uy, ux] and cost[uy, ux] < 1e20) else cost[uy, ux]
        for k in range(8):
            vy = uy + dys[k]
            vx = ux + dxs[k]
            if vy < 0 or vx < 0 or vy >= ny or vx >= nx:
                continue
            v = vy * nx + vx
            if closed[v]:
                continue
            cv = road_cost if (net[vy, vx] and cost[vy, vx] < 1e20) else cost[vy, vx]
            if cv >= 1e20:
                continue
            step = 1.4142135 if (dys[k] != 0 and dxs[k] != 0) else 1.0
            ng = g[u] + 0.5 * (cu + cv) * step
            if ng < g[v]:
                g[v] = ng
                prev[v] = u
                heapq.heappush(heap, (ng + hmin * math.hypot(vy - gy, vx - gx), v))
    if prev[t] == -1:
        return np.empty((0, 2), np.int64)
    cnt = 0
    u = t
    while u != -1:
        cnt += 1
        u = prev[u]
    out = np.empty((cnt, 2), np.int64)
    u = t
    i = cnt - 1
    while u != -1:
        out[i, 0] = u // nx
        out[i, 1] = u % nx
        u = prev[u]
        i -= 1
    return out


def to_cell(p):
    return (int(np.clip((p[1] - Y0) // CELL, 0, ny4 - 1)), int(np.clip(p[0] // CELL, 0, nx4 - 1)))


def cell_xy(c):
    return (c[1] * CELL + CELL / 2, c[0] * CELL + Y0 + CELL / 2)


def path_ok(pts):
    for a, b in zip(pts[:-1], pts[1:]):
        n = max(1, int(np.linalg.norm(b - a) / 1.5))
        for t in np.linspace(0, 1, n + 1):
            q = a + (b - a) * t
            if at(WET, q[0], q[1]) > 0.3:
                return False
    return True


def mark_net(pts, rad=1):
    for a, b in zip(pts[:-1], pts[1:]):
        n = max(1, int(np.linalg.norm(b - a) / 2.0))
        for t in np.linspace(0, 1, n + 1):
            cy, cx = to_cell(a + (b - a) * t)
            NET[max(cy - rad, 0):cy + rad + 1, max(cx - rad, 0):cx + rad + 1] = True


def route(a, b, kind, width, cut=False, pre=None, post=None, name=""):
    """Route a road from a to b. With cut=True the road stops where it first meets the network."""
    sc, gc = to_cell(a), to_cell(b)
    path = astar(COST, NET, sc[0], sc[1], gc[0], gc[1], 0.3, 0.3)
    if len(path) == 0:
        print(f"  !! no route for {name} {a} -> {b}")
        return None
    pts = np.array([cell_xy(c) for c in path], float)
    was_cut = False
    if cut:
        for i in range(len(pts)):
            if i * CELL > 24 and NET[path[i][0], path[i][1]]:
                pts = pts[:i + 1]
                was_cut = True
                break
    pts[0] = a
    if not was_cut:
        pts[-1] = b
    if pre is not None:
        pts = np.vstack([[pre], pts])
    if post is not None:
        pts = np.vstack([pts, [post]])
    for tol in (3.0, 1.8, 1.0, 0.5):
        sm = catmull(simplify(pts, tol), 6.0)
        if path_ok(sm):
            break
    else:
        sm = pts
    mark_net(sm)
    add_road(kind, sm, width)
    return sm


# ------------------------------------------------------------------------------------------------
# Altavera: walls, gates, square, castle, bridges
PLAZA_C = (1648.0, 862.0)
WALL = [(1600, 925), (1545, 870), (1545, 820), (1580, 785), (1720, 785), (1775, 840), (1775, 880), (1725, 930)]
GATES = {"N": ((1650, 785), "gatehouse", (0, -1)), "W": ((1545, 846), "gatehouse_ns", (-1, 0)),
         "E": ((1775, 860), "gatehouse_ns", (1, 0))}
BA = ((1846.0, 939.0), (1877.0, 985.0))          # stone bridge over the Fiume Argento (N end, S end)
BB = ((1464.0, 990.0), (1452.0, 1019.0))         # wooden bridge over the Torrente Bianco


def stub(end, other, d=14.0):
    e, o = np.array(end), np.array(other)
    u = (e - o) / np.linalg.norm(e - o)
    return tuple(e + u * d)


plazas.append({"kind": "cobble", "polygon": [[1628, 851], [1667, 848], [1670, 872], [1630, 876]]})
OCC.add(1648, 862, 25, 16)
plazas.append({"kind": "earth", "polygon": [list(q) for q in inset(WALL, 1.5)]})
place("townhall", 1662, 836, force=True)
place("church", 1689, 826, force=True)
place("castle", 1652, 962, force=True, yard=False)
place("well", 1646, 864, force=True, yard=False)
STALLS = [(1634, 855), (1641, 854.5), (1655, 854), (1662, 854.5), (1635, 869.5), (1642, 870), (1656, 869.5),
          (1663, 869)]
for i, (sx, sy) in enumerate(STALLS):
    buildings.append({"type": "stall_" + "abcde"[i % 5], "x": sx, "y": sy, "layer": "objects"})
for px_, py_, pt_ in [(1637.5, 857.5, "prop_barrels"), (1658.5, 857, "prop_crates"), (1638.5, 872.5, "prop_sacks"),
                      (1659.5, 872, "prop_barrels"), (1666.5, 862, "prop_cart"), (1631, 863, "prop_crates")]:
    props.append({"type": pt_, "x": px_, "y": py_})
buildings.append({"type": "bridge_argento", "x": 1861.4, "y": 962.1, "z": 108.11, "layer": "bridge"})
buildings.append({"type": "bridge_bianco", "x": 1458.3, "y": 1004.4, "z": 108.67, "layer": "bridge"})
OCC.add(1861, 962, 22, 26)
OCC.add(1458, 1004, 9, 16)

# wall ring (open towards the Rocca between the last and the first vertex)
WALL_KIND = {}
for i in range(len(WALL) - 1):
    (x0, y0), (x1, y1) = WALL[i], WALL[i + 1]
    dx, dy = x1 - x0, y1 - y0
    if abs(dy) < 1:
        t = "wall_000"
    elif abs(dx) < 1:
        t = "wall_090"
    elif dx * dy < 0:
        t = "wall_045"
    else:
        t = "wall_135"
    L = math.hypot(dx, dy)
    n = int(math.ceil(L / 11.6))
    for k in range(n):
        f = (k + 0.5) / n
        x, y = x0 + dx * f, y0 + dy * f
        if any(math.hypot(x - g[0][0], y - g[0][1]) < 9.0 for g in GATES.values()):
            continue
        buildings.append({"type": t, "x": round(x, 2), "y": round(y, 2), "layer": "objects"})
    nx_, ny_ = -dy / L, dx / L
    for k in range(int(L // 6) + 1):
        f = k / max(int(L // 6), 1)
        OCC.add(x0 + dx * f, y0 + dy * f, 3.5, 3.5)
for (gx, gy), gt, _ in GATES.values():
    place(gt, gx, gy, force=True, yard=False)
for tx, ty in WALL:
    place("wall_tower", tx, ty, force=True, yard=False)
# intermediate towers on the long north side
for tx in (1615, 1688):
    place("wall_tower", tx, 785, force=True, yard=False)


def gate_pt(key, d):
    (gx, gy), _, (ux, uy) = GATES[key]
    return (gx + ux * d, gy + uy * d)


# streets inside the walls
RING = inset(WALL, 13.0)
ring_pts = []
for i in range(len(RING)):
    a, b = np.array(RING[i]), np.array(RING[(i + 1) % len(RING)])
    ring_pts += [tuple(a), tuple(a + (b - a) * 0.5 + rng.normal(0, 1.2, 2))]
ring_pts.append(ring_pts[0])
TOWN_STREETS = [
    ("main", [gate_pt("W", -2), (1578, 845), (1603, 851), (1626, 858)], 5.0),
    ("main", [(1670, 858), (1695, 852), (1721, 857), (1745, 861), gate_pt("E", -2)], 5.0),
    ("main", [gate_pt("N", -2), (1647, 812), (1641, 830), (1637, 849)], 4.8),
    ("main", [(1660, 876), (1678, 896), (1696, 914), (1711, 940), (1700, 958), (1680, 964)], 4.2),
    ("lane", ring_pts, 3.4),
    ("lane", [(1592, 849), (1590, 826), (1594, 799)], 3.0),
    ("lane", [(1712, 855), (1709, 828), (1713, 799)], 3.0),
    ("lane", [(1600, 852), (1604, 880), (1611, 905)], 3.0),
    ("lane", [(1724, 858), (1717, 884), (1708, 905)], 3.0),
    ("lane", [(1628, 876), (1626, 896), (1631, 912)], 3.0),
]
town_roads = []
for kind, pts, w in TOWN_STREETS:
    sm = catmull(pts, 4.0) if len(pts) > 2 else np.array(pts, float)
    add_road(kind, sm, w)
    town_roads.append((kind, roads[-1]["points"], w))

# block the town interior for the country-road router (roads enter through the gates)
town_mask = Image.new("L", (nx4, ny4), 0)
ImageDraw.Draw(town_mask).polygon([(x / CELL, (y - Y0) / CELL) for x, y in WALL], fill=255)
TOWN4 = np.asarray(town_mask) > 0
COST[TOWN4] = 1e30


def in_town(x, y, margin=0.0):
    return point_in_poly(x, y, WALL) and poly_edge_dist(x, y, WALL) >= margin


# ------------------------------------------------------------------------------------------------
# hamlet sites (desired position -> best open, flat, dry site nearby)
def find_site(x, y, r=150.0):
    best, best_s = None, -1e9
    for dx in np.arange(-r, r + 1, 10.0):
        for dy in np.arange(-r, r + 1, 10.0):
            if dx * dx + dy * dy > r * r:
                continue
            cx, cy = x + dx, y + dy
            c = to_cell((cx, cy))
            y0_, y1_ = max(c[0] - 8, 0), c[0] + 9
            x0_, x1_ = max(c[1] - 8, 0), c[1] + 9
            if wet4[y0_:y1_, x0_:x1_].max() > 0.2 or dw4[c] < 30:
                continue
            sl = sl4[y0_:y1_, x0_:x1_].mean()
            fo = fd4[y0_:y1_, x0_:x1_].mean()
            if sl > 6.0 or fo > 0.25:
                continue
            s = -sl * 1.5 - fo * 30.0 - math.hypot(dx, dy) / 25.0
            if s > best_s:
                best, best_s = (float(cx), float(cy)), s
    return best


HAMLET_WISH = {
    "Borgo Cava": (1420, 625), "Prato Alto": (1190, 560), "Ca' del Lupo": (2030, 690),
    "Oltreponte": (2230, 1080), "Selvaria": (2470, 1400), "Rivafonda": (1700, 1330),
    "Riva del Lago": (1580, 1650), "Campolungo": (1880, 1960), "Bianchetto": (1250, 1200),
    "Ponente": (730, 1240), "Specchio": (1060, 1420), "Valbruna": (620, 900), "Castagneto": (2450, 760),
    "Lupara": (1960, 1600),
}
HAMLETS = {}
for nm, (x, y) in HAMLET_WISH.items():
    s = find_site(x, y)
    if s is None:
        s = find_site(x, y, 260.0)
    if s is None:
        print("  !! no site for hamlet", nm)
        continue
    HAMLETS[nm] = s
print("hamlets:", {k: (round(v[0]), round(v[1])) for k, v in HAMLETS.items()})

# ------------------------------------------------------------------------------------------------
# country roads (order matters: trunks first, then branches that merge into them)
gN, gW, gE = gate_pt("N", 12), gate_pt("W", 12), gate_pt("E", 12)
baN, baS = stub(BA[0], BA[1]), stub(BA[1], BA[0])
bbN, bbS = stub(BB[0], BB[1]), stub(BB[1], BB[0])
for g in ("N", "W", "E"):
    add_road("main", [gate_pt(g, 2), gate_pt(g, 12.5)], 5.0)
route(gE, baN, "main", 5.2, post=BA[0], name="E gate -> Argento bridge")
route(gW, bbN, "main", 5.2, post=BB[0], name="W gate -> Bianco bridge")
H_ = HAMLETS
LINKS = [
    # (from, to, kind, width, cut, pre)
    (BA[1], H_.get("Oltreponte"), "main", 5.0, False, "bridge"),
    (BB[1], H_.get("Bianchetto"), "main", 5.0, False, "bridge_b"),
    (gN, H_.get("Borgo Cava"), "main", 4.8, False, None),
    (H_.get("Rivafonda"), baS, "lane", 4.0, True, None),
    (H_.get("Riva del Lago"), H_.get("Rivafonda"), "lane", 3.8, True, None),
    (H_.get("Campolungo"), H_.get("Riva del Lago"), "lane", 3.6, True, None),
    (H_.get("Selvaria"), H_.get("Oltreponte"), "lane", 3.8, True, None),
    (H_.get("Ponente"), H_.get("Bianchetto"), "lane", 3.8, True, None),
    (H_.get("Specchio"), H_.get("Bianchetto"), "lane", 3.6, True, None),
    (H_.get("Prato Alto"), gN, "lane", 3.8, True, None),
    (H_.get("Ca' del Lupo"), gN, "lane", 3.8, True, None),
    (H_.get("Valbruna"), H_.get("Ponente"), "lane", 3.6, True, None),
    (H_.get("Castagneto"), H_.get("Oltreponte"), "lane", 3.6, True, None),
    (H_.get("Lupara"), H_.get("Rivafonda"), "lane", 3.6, True, None),
]
for a, b, kind, w, cut, pre in LINKS:
    if a is None or b is None:
        continue
    if pre == "bridge":
        route(baS, b, kind, w, pre=BA[1], name="Argento bridge -> Oltreponte")
    elif pre == "bridge_b":
        route(bbS, b, kind, w, pre=BB[1], name="Bianco bridge -> Bianchetto")
    else:
        route(a, b, kind, w, cut=cut, name=f"{a} -> {b}")

# ------------------------------------------------------------------------------------------------
# key buildings in and around the town
place("barracks", 1738, 812, force=True)
place("blacksmith", 1567, 868, force=True)
place("granary", 1574, 808, force=True)


def place_near(btype, x, y, r=60.0, tries=400, **kw):
    for k in range(tries):
        rr = r * math.sqrt(k / tries)
        a = rng.uniform(0, 2 * math.pi)
        cx, cy = x + math.cos(a) * rr, y + math.sin(a) * rr
        if place(btype, cx, cy, **kw):
            return (cx, cy)
    print("  !! could not place", btype, "near", (x, y))
    return None


def connect(p, kind="path", width=2.8, name=""):
    """Short road from a site to the nearest part of the network."""
    if p is None:
        return
    c = to_cell(p)
    ys, xs = np.nonzero(NET & ~TOWN4)
    if len(ys) == 0:
        return
    d = (ys - c[0]) ** 2 + (xs - c[1]) ** 2
    k = int(np.argmin(d))
    tgt = cell_xy((ys[k], xs[k]))
    if math.hypot(tgt[0] - p[0], tgt[1] - p[1]) < 8:
        return
    route(p, tgt, kind, width, name=name)


# raster of the road edges, now that the trunk network exists
def build_roadd():
    img = Image.new("L", (NX, NY), 0)
    d = ImageDraw.Draw(img)
    for r in roads:
        d.line([(x, y - Y0) for x, y in r["points"]], fill=255, width=max(1, int(round(r["width"]))))
    m = np.asarray(img) > 0
    return ndimage.distance_transform_edt(~m).astype(np.float32)


ROADD = build_roadd()

stable = place_near("stable", 1812, 880, 40)
tower = place_near("tower", 1826, 922, 25)
mill = place_near("windmill", 1440, 790, 80, water_gap=20)
connect(mill, name="windmill")
saw = place_near("sawmill", 1190, 690, 90, water_gap=8)
connect(saw, "lane", 3.4, name="sawmill")
quarry = place_near("quarry", 1478, 545, 60, max_slope=16)
connect(quarry, "lane", 3.4, name="quarry")
mine = place_near("mine", 1932, 520, 60, max_slope=16)
connect(mine, "lane", 3.4, name="mine")
ROADD = build_roadd()

# ------------------------------------------------------------------------------------------------
# houses: continuous frontages along the streets, then infill of the blocks
def pick_house(rich):
    return (RICH if rich else SIMPLE)[rng.integers(3 if rich else 5)]


def frontage(pts, road_w, side, pred, gap=(0.0, 0.7), rich_r=70.0, max_n=999, garden=0.0, setback=0.6):
    p = np.array(pts, float)
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    keep = seg > 1e-6
    if not keep.all():
        p = np.vstack([p[0], p[1:][keep]])
        seg = seg[keep]
    if len(seg) == 0:
        return 0
    cum = np.concatenate([[0], np.cumsum(seg)])
    s, n = 2.0, 0
    while s < cum[-1] - 2 and n < max_n:
        k = int(np.clip(np.searchsorted(cum, s) - 1, 0, len(seg) - 1))
        t = (s - cum[k]) / seg[k]
        pt = p[k] + (p[k + 1] - p[k]) * t
        dvec = (p[k + 1] - p[k]) / seg[k]
        nrm = np.array([-dvec[1], dvec[0]]) * side
        ns_street = abs(dvec[1]) > abs(dvec[0]) * 1.2
        rich = math.hypot(pt[0] - PLAZA_C[0], pt[1] - PLAZA_C[1]) < rich_r and rng.random() < 0.7
        base = pick_house(rich)
        bt = base + ("_e" if nrm[0] < 0 else "_w") if ns_street else base
        w, d = FOOT[bt]
        along = d if ns_street else w
        depth = w if ns_street else d
        c = pt + nrm * (road_w / 2 + depth / 2 + setback) + dvec * (along / 2)
        if pred(c[0], c[1]) and place(bt, float(c[0]), float(c[1]), margin=0.25, road_gap=0.3):
            n += 1
            if garden and rng.random() < garden:
                gd = rng.uniform(7.0, 12.0)
                g0 = c + nrm * (depth / 2 + 1.0)
                gc = g0 + nrm * gd / 2
                corners = [g0 - dvec * along / 2, g0 + dvec * along / 2, g0 + dvec * along / 2 + nrm * gd,
                           g0 - dvec * along / 2 + nrm * gd]
                if pred(gc[0], gc[1]) and OCC.free(gc[0], gc[1], gd, gd, 0.2) and road_clear(gc[0], gc[1], gd / 2):
                    poly = [[round(float(q[0]), 2), round(float(q[1]), 2)] for q in corners]
                    if side < 0:
                        poly = poly[::-1]
                    fields.append({"crop": "green" if rng.random() < 0.7 else "plowed", "polygon": poly,
                                   "dir": round(math.degrees(math.atan2(dvec[1], dvec[0])), 1),
                                   "fence": bool(rng.random() < 0.7)})
                    OCC.add(gc[0], gc[1], gd / 2, gd / 2)
            if rng.random() < 0.3:
                pr = rng.choice(["prop_barrels", "prop_crates", "prop_sacks", "prop_logs"])
                q = c - nrm * (depth / 2 + 0.9) + dvec * rng.uniform(-along / 2, along / 2)
                if road_clear(q[0], q[1], 0.0):
                    props.append({"type": str(pr), "x": round(float(q[0]), 2), "y": round(float(q[1]), 2)})
            s += along + rng.uniform(*gap)
        else:
            s += 1.5
    return n


def town_pred(x, y):
    return in_town(x, y, 7.0)


n_front = 0
for kind, p, w in town_roads:
    for side in (1, -1):
        n_front += frontage(p, w, side, town_pred, rich_r=70.0 if kind == "main" else 40.0)
# infill: jittered candidates inside the ring, leaving a few courtyards with trees
n_fill = 0
cand = []
for st, off in ((7.5, 0.0), (5.0, 2.5), (4.0, 1.3)):
    xs_, ys_ = np.meshgrid(np.arange(1548 + off, 1775, st), np.arange(788 + off, 930, st))
    cc = np.c_[xs_.ravel(), ys_.ravel()] + rng.uniform(-2.0, 2.0, (xs_.size, 2))
    rng.shuffle(cc)
    cand += list(cc)
for cx, cy in cand:
    if not in_town(cx, cy, 8.0):
        continue
    if N.fbm_at(np.array([cx], np.float32), np.array([cy], np.float32), 38.0, N.perm(5), 2, 2.0, 0.5)[0] > 0.33:
        if OCC.free(cx, cy, 3, 3, 0.5) and road_clear(cx, cy, 2.5) and rng.random() < 0.25:
            tree(str(rng.choice(["fruit_a", "fruit_b", "oak_b", "birch_b", "fruit_c"])), cx, cy,
                 rng.uniform(0.7, 0.9))
            OCC.add(cx, cy, 1.5, 1.5)
        continue
    base = SIMPLE[rng.integers(5)]
    bt = base + str(rng.choice(["", "", "_e", "_w"]))
    if place(bt, cx, cy, margin=0.3, road_gap=0.5):
        n_fill += 1
print(f"town houses: frontage {n_front}, infill {n_fill}")

# suburbs outside the gates
for r in list(roads):
    if r["kind"] != "main":
        continue
    for side in (1, -1):
        frontage(r["points"], r["width"], side,
                 lambda x, y: (not in_town(x, y)) and min(math.hypot(x - gN[0], y - gN[1]),
                                                          math.hypot(x - gW[0], y - gW[1]),
                                                          math.hypot(x - gE[0], y - gE[1])) < 95,
                 gap=(1.5, 7.0), max_n=6, garden=0.45, setback=1.5)


# ------------------------------------------------------------------------------------------------
# hamlets: farm, houses around a green, orchard, props
def hamlet(nm, cx, cy):
    placed = []
    f = place_near("farm", cx, cy, 30, margin=2.0, water_gap=12)
    if f:
        placed.append(f)
    nh = int(rng.integers(5, 10))
    k = 0
    for t in range(240):
        if k >= nh:
            break
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(14, 46)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r * 0.85
        bt = SIMPLE[rng.integers(5)] + str(rng.choice(["", "", "_e", "_w"]))
        if place(bt, x, y, margin=2.0, water_gap=10, road_gap=1.0, max_forest=0.4):
            placed.append((x, y))
            k += 1
            if rng.random() < 0.5:
                q = (x + rng.uniform(-6, 6), y + rng.uniform(4, 7))
                if road_clear(q[0], q[1], 1.0) and OCC.free(q[0], q[1], 2, 2, 0.3):
                    props.append({"type": str(rng.choice(["prop_haystack", "prop_logs", "prop_cart", "prop_barrels",
                                                           "prop_bales"])), "x": round(q[0], 2), "y": round(q[1], 2)})
    if rng.random() < 0.6:
        place_near("well", cx, cy, 14, yard=False, road_gap=1.0)
    # orchard
    for t in range(60):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(45, 80)
        ox, oy = cx + math.cos(a) * r, cy + math.sin(a) * r
        nx_, ny_ = int(rng.integers(3, 6)), int(rng.integers(3, 5))
        sp = rng.uniform(6.0, 7.5)
        w, d = nx_ * sp, ny_ * sp
        if OCC.free(ox, oy, w, d, 2.0) and site_ok(ox, oy, w, d, max_slope=8, water_gap=8, road_gap=2.0,
                                                    max_forest=0.3):
            ang = rng.uniform(-0.3, 0.3)
            for i in range(nx_):
                for j in range(ny_):
                    lx, ly = (i - (nx_ - 1) / 2) * sp, (j - (ny_ - 1) / 2) * sp
                    tx = ox + lx * math.cos(ang) - ly * math.sin(ang) + rng.normal(0, 0.5)
                    ty = oy + lx * math.sin(ang) + ly * math.cos(ang) + rng.normal(0, 0.5)
                    tree(str(rng.choice(["fruit_a", "fruit_b", "fruit_c"])), tx, ty, rng.uniform(0.8, 1.0))
            OCC.add(ox, oy, w / 2, d / 2)
            break
    # garden trees between the houses
    for (x, y) in placed:
        for _ in range(int(rng.integers(0, 3))):
            a = rng.uniform(0, 2 * math.pi)
            tx, ty = x + math.cos(a) * rng.uniform(8, 13), y + math.sin(a) * rng.uniform(7, 11)
            if OCC.free(tx, ty, 3, 3, 0.2) and road_clear(tx, ty, 2.5) and at(WET, tx, ty) < 0.5:
                tree(str(rng.choice(["fruit_a", "oak_b", "bush_a", "bush_c", "birch_b", "beech_b"])), tx, ty,
                     rng.uniform(0.8, 1.05))
    return placed


for nm, (cx, cy) in HAMLETS.items():
    hamlet(nm, cx, cy)


# ------------------------------------------------------------------------------------------------
# field patchworks: around the hamlets and in the open land near the town
CROPS = ["wheat", "wheat", "wheat", "barley", "barley", "plowed", "plowed", "green", "green", "hay", "hay", "barley",
         "wheat", "plowed", "meadow"]


def shrink(poly, gap):
    c = poly.mean(0)
    return c + (poly - c) * (1 - gap / max(np.linalg.norm(poly - c, axis=1).mean(), 1.0))


def cell_ok(poly, region, avoid_c=None, avoid_r=0.0):
    c = poly.mean(0)
    area = abs(np.cross(poly[2] - poly[0], poly[3] - poly[1])) / 2
    longest = max(np.linalg.norm(poly[(i + 1) % 4] - poly[i]) for i in range(4))
    if area / max(longest, 1e-6) < 12.0:          # no thin slivers
        return False
    if not point_in_poly(c[0], c[1], region) or sum(point_in_poly(x, y, region) for x, y in poly) < 3:
        return False
    if avoid_c is not None and math.hypot(c[0] - avoid_c[0], c[1] - avoid_c[1]) < avoid_r:
        return False
    samples = list(poly) + [c] + [(poly[i] + poly[(i + 1) % 4]) / 2 for i in range(4)] \
        + [(poly[i] * 0.6 + c * 0.4) for i in range(4)]
    for x, y in samples:
        c4 = to_cell((x, y))
        if at(WET, x, y) > 0.5 or at(DW, x, y) < 5 or sl4[c4] > 8.5 or at(FD, x, y) > 0.45:
            return False
        if not road_clear(x, y, 1.5):
            return False
    w = np.ptp(poly[:, 0])
    d = np.ptp(poly[:, 1])
    return OCC.free(c[0], c[1], w * 0.75, d * 0.75, margin=1.0)


def patchwork(region, ang, sx=(34, 80), sy=(22, 50), avoid_c=None, avoid_r=0.0, gap=(1.4, 3.0)):
    reg = np.array(region, float)
    a_ = math.radians(ang)
    ux = np.array([math.cos(a_), math.sin(a_)])
    uy = np.array([-math.sin(a_), math.cos(a_)])
    c0 = reg.mean(0)
    loc = (reg - c0) @ np.c_[ux, uy]
    lo, hi = loc.min(0) - 20, loc.max(0) + 20
    xs = [lo[0]]
    while xs[-1] < hi[0]:
        xs.append(xs[-1] + rng.uniform(*sx))
    ys = [lo[1]]
    while ys[-1] < hi[1]:
        ys.append(ys[-1] + rng.uniform(*sy))
    G = np.zeros((len(ys), len(xs), 2))
    for j, yv in enumerate(ys):
        for i, xv in enumerate(xs):
            jit = rng.normal(0, 4.0, 2)
            G[j, i] = c0 + ux * (xv + jit[0]) + uy * (yv + jit[1])
    n = 0
    for j in range(len(ys) - 1):
        for i in range(len(xs) - 1):
            poly = np.array([G[j, i], G[j, i + 1], G[j + 1, i + 1], G[j + 1, i]])
            # occasionally split a cell in two strips
            polys = [poly]
            if rng.random() < 0.3:
                m0, m1 = (poly[0] + poly[3]) / 2, (poly[1] + poly[2]) / 2
                polys = [np.array([poly[0], poly[1], m1, m0]), np.array([m0, m1, poly[2], poly[3]])]
            for pp in polys:
                pp = shrink(pp, rng.uniform(*gap))
                if not cell_ok(pp, region, avoid_c, avoid_r):
                    continue
                crop = CROPS[rng.integers(len(CROPS))]
                if crop == "meadow":
                    continue
                e = pp[1] - pp[0]
                dirn = math.degrees(math.atan2(e[1], e[0])) + (90 if rng.random() < 0.3 else 0)
                fields.append({"crop": crop, "polygon": [[round(float(x), 2), round(float(y), 2)] for x, y in pp],
                               "dir": round(dirn, 1), "fence": bool(crop == "hay" or rng.random() < 0.1)})
                cc = pp.mean(0)
                OCC.add(cc[0], cc[1], np.ptp(pp[:, 0]) * 0.38, np.ptp(pp[:, 1]) * 0.38)
                n += 1
    return n


def blob(cx, cy, r, k=9):
    out = []
    ph = rng.uniform(0, 2 * math.pi)
    for i in range(k):
        a = 2 * math.pi * i / k
        rr = r * (0.75 + 0.35 * math.sin(3 * a + ph) * rng.uniform(0.5, 1.0) + rng.uniform(-0.08, 0.08))
        out.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.9))
    return out


n_fields = 0
for nm, (cx, cy) in HAMLETS.items():
    n_fields += patchwork(blob(cx, cy, rng.uniform(240, 330)), rng.uniform(-40, 40), sx=(30, 72), sy=(20, 46),
                          avoid_c=(cx, cy), avoid_r=40)
# open fields around the town
n_fields += patchwork([(1380, 640), (1900, 650), (1960, 760), (1800, 775), (1520, 775), (1400, 720)], 2.0)
n_fields += patchwork([(1200, 760), (1430, 800), (1520, 900), (1420, 950), (1250, 880)], 18.0)
n_fields += patchwork([(1890, 1000), (2080, 930), (2160, 1000), (2060, 1120), (1900, 1100)], 24.0)
print("fields", n_fields)


# small agricultural details in the fields
for f in fields:
    p = np.array(f["polygon"])
    area = abs(np.cross(p[2] - p[0], p[3] - p[1])) / 2
    if area < 600:
        continue
    c = p.mean(0)
    r_ = rng.random()
    if f["crop"] in ("wheat", "barley") and r_ < 0.25:
        props.append({"type": "prop_scarecrow", "x": round(float(c[0]), 2), "y": round(float(c[1]), 2)})
    elif f["crop"] == "hay":
        for k in range(int(rng.integers(3, 7))):
            q = c + rng.normal(0, 7, 2)
            if point_in_poly(q[0], q[1], p):
                props.append({"type": str(rng.choice(["prop_haystack", "prop_bales"])), "x": round(float(q[0]), 2),
                              "y": round(float(q[1]), 2)})
    elif f["crop"] in ("wheat", "barley") and r_ < 0.45:
        q = p[0] + (p[1] - p[0]) * 0.2 + (p[3] - p[0]) * 0.15
        props.append({"type": "prop_cart_hay", "x": round(float(q[0]), 2), "y": round(float(q[1]), 2)})

# hedgerows along field edges (bushes with a few trees), lines of trees along the country roads
for f in fields:
    if rng.random() > 0.5:
        continue
    p = np.array(f["polygon"])
    c = p.mean(0)
    for e in rng.choice(4, int(rng.integers(1, 3)), replace=False):
        a, b = p[e], p[(e + 1) % 4]
        L = np.linalg.norm(b - a)
        out = (a + b) / 2 - c
        out = out / max(np.linalg.norm(out), 1e-6)
        s = rng.uniform(0, 3)
        while s < L:
            q = a + (b - a) * (s / L) + out * rng.uniform(0.8, 1.8)
            if road_clear(q[0], q[1], 1.2) and at(WET, q[0], q[1]) < 0.5 and OCC.free(q[0], q[1], 1, 1, 0.0):
                if rng.random() < 0.22:
                    tree(str(rng.choice(["oak_b", "oak_a", "beech_a", "poplar_a", "birch_a"])), q[0], q[1],
                         rng.uniform(0.75, 1.0))
                else:
                    tree(str(rng.choice(["bush_a", "bush_b", "bush_c", "bush_d"])), q[0], q[1], rng.uniform(0.75, 1.1))
            s += rng.uniform(2.6, 4.8)
for r in roads:
    if r["kind"] == "path" or polyline_len(r["points"]) < 120:
        continue
    p = np.array(r["points"])
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    s = rng.uniform(5, 30)
    while s < cum[-1]:
        k = int(np.clip(np.searchsorted(cum, s) - 1, 0, len(seg) - 1))
        if seg[k] < 1e-6:
            s += 10
            continue
        q = p[k] + (p[k + 1] - p[k]) * ((s - cum[k]) / seg[k])
        dv = (p[k + 1] - p[k]) / seg[k]
        side = 1 if rng.random() < 0.5 else -1
        t = q + np.array([-dv[1], dv[0]]) * side * (r["width"] / 2 + rng.uniform(2.0, 3.5))
        if (not in_town(t[0], t[1], -6)) and road_clear(t[0], t[1], 1.5) and at(WET, t[0], t[1]) < 0.5 \
                and OCC.free(t[0], t[1], 2, 2, 0.3):
            tree(str(rng.choice(["oak_a", "oak_b", "poplar_a", "poplar_b", "beech_a", "bush_a", "bush_c"])), t[0], t[1],
                 rng.uniform(0.8, 1.05))
        s += rng.uniform(9, 38)

# ------------------------------------------------------------------------------------------------
# citizens (visual demonstration: walking along roads, working at buildings and in fields)
roles_town = ["citizen", "citizen", "citizen", "merchant", "farmer", "builder", "soldier"]
roles_country = ["farmer", "farmer", "merchant", "woodcutter", "citizen", "builder", "miner", "soldier"]
for i, r in enumerate(roads):
    L = polyline_len(r["points"])
    inside = in_town(*r["points"][len(r["points"]) // 2])
    spacing = 22.0 if inside else {"main": 75.0, "lane": 110.0, "path": 150.0}[r["kind"]]
    n = int(np.clip(L / spacing, 1, 26))
    for k in range(n):
        pool_ = roles_town if inside else roles_country
        role = str(pool_[int(rng.integers(len(pool_)))])
        pts = r["points"][::-1] if k % 2 else r["points"]
        citizens.append({"role": role, "mode": "carry" if rng.random() < 0.3 else "walk", "path": pts,
                         "start": round(float(rng.random()), 3), "speed": round(float(rng.uniform(1.0, 1.45)), 2)})
for k in range(30):
    x = rng.uniform(1630, 1668)
    y = rng.uniform(851, 875)
    citizens.append({"role": str(rng.choice(["citizen", "citizen", "merchant", "farmer", "builder"])),
                     "mode": "wander", "spot": [round(x, 2), round(y, 2)], "radius": 13.0,
                     "speed": round(float(rng.uniform(0.8, 1.2)), 2)})
for sx, sy in STALLS:
    citizens.append({"role": "merchant", "mode": "work", "spot": [sx, sy - 1.6], "dir": "S"})
WORK = {"barracks": ("soldier", 5, (0, -6), 6.0), "blacksmith": ("builder", 1, (-3.0, -1.0), 0.5),
        "sawmill": ("woodcutter", 4, (-6, -4), 5.0), "quarry": ("miner", 4, (-2, -7), 6.0),
        "mine": ("miner", 3, (1, -7), 3.0), "farm": ("farmer", 2, (2, -8), 4.0), "granary": ("farmer", 1, (0, -5), 1.0),
        "windmill": ("farmer", 1, (2, -5), 1.0), "stable": ("citizen", 1, (9, -3), 2.0)}
for b in buildings:
    if b["type"] in WORK:
        role, n, (ox, oy), spread = WORK[b["type"]]
        for k in range(n):
            citizens.append({"role": role, "mode": "work", "spot": [round(b["x"] + ox + rng.uniform(-spread, spread), 2),
                                                                      round(b["y"] + oy + rng.uniform(-1, 1), 2)],
                             "dir": str(rng.choice(["S", "SE", "E", "SW", "W"]))})
for nm, (cx, cy) in HAMLETS.items():
    for k in range(3):
        citizens.append({"role": str(rng.choice(["citizen", "farmer", "farmer"])), "mode": "wander",
                         "spot": [round(cx, 2), round(cy, 2)], "radius": 16.0, "speed": 1.0})
for key in GATES:
    for d in (-1, 1):
        (gx, gy), _, (ux, uy) = GATES[key]
        citizens.append({"role": "soldier", "mode": "idle",
                         "spot": [round(gx + ux * 9 - uy * 3 * d, 2), round(gy + uy * 9 + ux * 3 * d, 2)], "dir": "S"})
for gx, gy in [(1840, 934), (1470, 986), (1682, 968)]:
    citizens.append({"role": "soldier", "mode": "idle", "spot": [gx, gy], "dir": "S"})
for f in fields:
    if f["crop"] in ("wheat", "green", "plowed", "barley", "hay") and rng.random() < 0.45:
        p = np.array(f["polygon"])
        c = p.mean(0)
        for k in range(int(rng.integers(1, 4))):
            q = c + rng.normal(0, 5, 2)
            citizens.append({"role": "farmer", "mode": "work", "spot": [round(float(q[0]), 2), round(float(q[1]), 2)],
                             "dir": str(rng.choice(["S", "SE", "E", "W", "SW"]))})

# fences around the fenced fields and the props: drawn by the instanced vegetation layer (MultiMesh strips),
# not as individual nodes -> a few draw calls instead of hundreds
for f in fields:
    if not f["fence"]:
        continue
    poly = f["polygon"]
    for i in range(len(poly)):
        a, b = np.array(poly[i], float), np.array(poly[(i + 1) % len(poly)], float)
        dv = b - a
        L = float(np.linalg.norm(dv))
        if L < 2.0:
            continue
        ang = math.degrees(math.atan2(-dv[1], dv[0])) % 180.0    # heading in Blender coordinates (y north)
        k = int(round(ang / 22.5)) % 8
        segs = max(1, int(round(L / 4.0)))
        for s_ in range(segs):
            c = a + dv * ((s_ + 0.5) / segs)
            veg.append({"type": "fence_%04d" % int(round(k * 225)), "x": round(float(c[0]), 2),
                        "y": round(float(c[1]), 2), "scale": round(min(1.0, L / segs / 4.0) * 1.0, 2)})
for p_ in props:
    veg.append({"type": p_["type"], "x": p_["x"], "y": p_["y"], "scale": 1.0})
n_props = len(props)
props = []

out = {"name": "Altavera", "roads": roads, "plazas": plazas, "fields": fields, "buildings": buildings,
       "props": props, "trees": [], "veg": veg, "yards": yards, "citizens": citizens,
       "hamlets": {k: [round(v[0], 1), round(v[1], 1)] for k, v in HAMLETS.items()},
       "walls": [list(q) for q in WALL]}
path = os.path.join(K.GAME_DIR, "data", "valley", "demo_town.json")
with open(path, "w") as f:
    json.dump(out, f, separators=(",", ":"))
nh = sum(b["type"].startswith("house") for b in buildings)
print(f"buildings {len(buildings)} (houses {nh})  roads {len(roads)}  fields {len(fields)}  props {n_props}  "
      f"veg {len(veg)}  citizens {len(citizens)}")

# ------------------------------------------------------------------------------------------------
# plan images for checking: whole valley floor and the town
for tag, (x0, x1, y0, y1, sc) in {"valley": (300, 2800, 300, 2300, 0.5), "town": (1480, 1900, 740, 1000, 3.0)}.items():
    img = Image.new("RGB", (int((x1 - x0) * sc), int((y1 - y0) * sc)), (120, 140, 80))
    step = max(1, int(1 / sc))
    sub = FD[int(y0 - Y0):int(y1 - Y0):step, x0:x1:step]
    fimg = Image.fromarray((np.clip(sub * 2.5, 0, 1) * 255).astype(np.uint8)).resize(img.size)
    img.paste((50, 90, 50), mask=fimg)
    sub_w = WET[int(y0 - Y0):int(y1 - Y0):step, x0:x1:step]
    water = Image.fromarray((sub_w * 255).astype(np.uint8)).resize(img.size)
    img.paste((60, 100, 170), mask=water)
    d = ImageDraw.Draw(img)
    T = lambda x, y: ((x - x0) * sc, (y - y0) * sc)  # noqa: E731
    colmap = {"wheat": (210, 180, 70), "barley": (200, 190, 120), "plowed": (130, 90, 60), "green": (80, 140, 60),
              "hay": (170, 170, 90), "flax": (130, 140, 190)}
    for f in fields:
        d.polygon([T(*p) for p in f["polygon"]], fill=colmap[f["crop"]])
    for p in plazas:
        d.polygon([T(*q) for q in p["polygon"]], fill=(170, 160, 140))
    for r in roads:
        d.line([T(*q) for q in r["points"]], fill=(230, 210, 160), width=max(1, int(r["width"] * sc)))
    for b in buildings:
        w, dd = FOOT.get(b["type"], (6, 6))
        if b["type"].startswith("wall_0") or b["type"].startswith("wall_1"):
            w, dd = 8, 8
        if b["type"].startswith("bridge"):
            continue
        col = (150, 60, 40) if b["type"].startswith("house") else (90, 90, 110)
        d.rectangle([T(b["x"] - w / 2, b["y"] - dd / 2), T(b["x"] + w / 2, b["y"] + dd / 2)], fill=col)
    for t in veg:
        x, y = T(t["x"], t["y"])
        d.ellipse([x - 1.5 * sc, y - 1.5 * sc, x + 1.5 * sc, y + 1.5 * sc], fill=(20, 60, 20))
    img.save(os.path.join(K.CACHE_DIR, f"plan_{tag}.png"))
