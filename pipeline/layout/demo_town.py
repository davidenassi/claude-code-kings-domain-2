"""Demonstration settlement of the Valle di Altavera (Phase 1 graphics test, not final gameplay).

Hand-placed landmarks (plaza, town hall, castle, bridges, wall line, mills, mine) + procedural
houses along organic streets + subdivided irregular fields. Every placement is validated against the
terrain (water, slope, overlaps). Writes game/data/valley/demo_town.json and a plan image.
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from kd import const as K  # noqa: E402

CACHE = os.path.join(K.CACHE_DIR, "terrain")
Y0 = -K.NORTH_PAD_M
rng = np.random.default_rng(2026)

H = np.load(os.path.join(CACHE, "h_final.npy"))
SLOPE = np.load(os.path.join(CACHE, "slope.npy"))
WET = np.load(os.path.join(CACHE, "wet.npy"))
DW = np.load(os.path.join(CACHE, "d_water.npy"))


def at(grid, x, y):
    return grid[int(np.clip(round(y - Y0), 0, grid.shape[0] - 1)), int(np.clip(round(x), 0, grid.shape[1] - 1))]


# footprints (w, d) in metres, used for spacing / overlap tests
FOOT = {
    "house_a": (7, 6), "house_b": (8, 6), "house_c": (9, 5.5), "house_d": (8.5, 6.5), "house_e": (6.5, 5.5),
    "house_rich_a": (10, 8), "house_rich_b": (8.5, 9), "house_rich_c": (11, 8), "farm": (19, 13),
    "granary": (8.6, 7.5), "sawmill": (22, 10), "quarry": (24, 14), "mine": (18, 14), "windmill": (7, 7),
    "blacksmith": (12, 6.5), "barracks": (17, 14), "stable": (24, 8), "tower": (6.5, 6.5),
    "townhall": (15, 10), "castle": (40, 50), "well": (3, 3), "wall_tower": (6.4, 6.4), "gatehouse": (14, 7),
    "stall_a": (4, 2.4), "stall_b": (4, 2.4), "stall_c": (4, 2.4), "stall_d": (4, 2.4), "stall_e": (4, 2.4),
}

buildings = []
occupied = []          # (cx, cy, hw, hd)
roads = []
plazas = []
fields = []
props = []
trees = []
yards = []
citizens = []


def free(cx, cy, w, d, margin=1.5):
    for ox, oy, hw, hd in occupied:
        if abs(cx - ox) < hw + w / 2 + margin and abs(cy - oy) < hd + d / 2 + margin:
            return False
    return True


def site_ok(cx, cy, w, d, max_slope=10.0, water_gap=4.0):
    for fx in (-0.5, 0, 0.5):
        for fy in (-0.5, 0, 0.5):
            x, y = cx + fx * w, cy + fy * d
            if at(WET, x, y) > 0.5 or at(DW, x, y) < water_gap:
                return False
            if math.degrees(at(SLOPE, x, y)) > max_slope:
                return False
    return True


def road_dist(x, y):
    best = 1e9
    for r in roads:
        p = np.array(r["points"], float)
        for a, b in zip(p[:-1], p[1:]):
            ab = b - a
            t = np.clip(np.dot([x, y] - a, ab) / max(np.dot(ab, ab), 1e-9), 0, 1)
            dd = np.hypot(*(a + t * ab - [x, y])) - r["width"] / 2
            best = min(best, dd)
    return best


def place(btype, x, y, layer="objects", force=False, yard=True, z=None, **extra):
    w, d = FOOT.get(btype, (6, 6))
    if not force and (not free(x, y, w, d) or not site_ok(x, y, w, d)):
        return False
    b = {"type": btype, "x": round(x, 2), "y": round(y, 2), "layer": layer}
    if z is not None:
        b["z"] = z
    b.update(extra)
    buildings.append(b)
    occupied.append((x, y, w / 2, d / 2))
    if yard and layer == "objects":
        yards.append({"x": round(x, 2), "y": round(y + 0.6, 2), "w": round(w + 3, 1), "d": round(d + 3, 1)})
    return True


def road(kind, pts, width):
    roads.append({"kind": kind, "width": width, "points": [[float(a), float(b)] for a, b in pts]})


# ------------------------------------------------------------------------------------------------
# landmarks: compact walled core north of the Rocca, castle on the Rocca, two bridges
PLAZA_C = (1647.0, 868.0)
WALL_N, WALL_W, WALL_E, WALL_S = 790.0, 1505.0, 1795.0, 935.0
plazas.append({"kind": "cobble", "polygon": [[1626, 851], [1668, 848], [1671, 886], [1624, 889]]})
occupied.append((1647, 868, 24, 21))
place("townhall", 1647, 836, force=True)
place("castle", 1652, 962, force=True, yard=False)
place("well", 1650, 870, force=True, yard=False)
for i, (sx, sy) in enumerate([(1632, 860), (1640, 878), (1660, 858), (1663, 876), (1631, 883)]):
    buildings.append({"type": "stall_" + "abcde"[i], "x": sx, "y": sy, "layer": "objects"})
buildings.append({"type": "bridge_argento", "x": 1861.4, "y": 962.1, "z": 108.11, "layer": "bridge"})
buildings.append({"type": "bridge_bianco", "x": 1458.3, "y": 1004.4, "z": 108.67, "layer": "bridge"})
occupied.append((1861, 962, 22, 26))
occupied.append((1458, 1004, 9, 16))

# streets inside the walls
road("main", [(1508, 880), (1532, 873), (1560, 878), (1590, 869), (1626, 870)], 5.5)
road("main", [(1670, 868), (1700, 876), (1728, 871), (1760, 883), (1792, 888)], 5.5)
road("main", [(1641, 851), (1645, 822), (1650, 792)], 5.0)
road("main", [(1662, 887), (1684, 905), (1703, 926), (1712, 948), (1678, 963)], 4.5)
road("lane", [(1512, 832), (1540, 822), (1575, 830), (1612, 819), (1645, 822), (1680, 815), (1718, 826),
              (1752, 820), (1790, 834)], 4.0)
road("lane", [(1560, 876), (1572, 902), (1600, 922), (1612, 935)], 3.5)
road("lane", [(1752, 880), (1760, 905), (1748, 928)], 3.5)
road("lane", [(1590, 824), (1596, 850), (1600, 872)], 3.5)
road("lane", [(1712, 822), (1716, 846), (1710, 872)], 3.5)
# roads outside: to the bridges, the north gate road to quarry and mine, paths to the mills
road("main", [(1792, 888), (1815, 905), (1834, 925), (1846, 939)], 5.5)
road("main", [(1877, 985), (1905, 1012), (1950, 1045), (2010, 1075), (2090, 1100), (2180, 1120), (2280, 1135)], 5.0)
road("main", [(1508, 880), (1490, 905), (1478, 940), (1468, 970), (1464, 990)], 5.0)
road("main", [(1452, 1019), (1438, 1050), (1410, 1085), (1360, 1110), (1290, 1130), (1200, 1150)], 5.0)
road("main", [(1650, 792), (1648, 760), (1640, 720), (1615, 670), (1570, 615), (1520, 575), (1490, 558)], 5.0)
road("lane", [(1640, 720), (1700, 690), (1780, 640), (1860, 590), (1925, 545)], 4.0)
road("path", [(1490, 905), (1440, 890), (1380, 876), (1310, 866)], 3.0)
road("path", [(1310, 866), (1250, 850), (1180, 820), (1110, 790)], 3.0)
road("path", [(1950, 1045), (1975, 1100), (2010, 1160), (2050, 1200)], 3.0)
road("path", [(2090, 1100), (2110, 1040), (2150, 990)], 2.6)
road("path", [(1360, 1110), (1370, 1170), (1395, 1230)], 2.6)
road("path", [(1615, 670), (1560, 690), (1520, 680)], 2.6)
road("path", [(1780, 640), (1840, 670), (1880, 690)], 2.6)

# ground worn by the town inside the walls
plazas.append({"kind": "earth", "polygon": [[WALL_W + 2, WALL_N + 2], [WALL_E - 2, WALL_N + 2], [WALL_E - 2, WALL_S - 6],
                                            [WALL_W + 2, WALL_S - 4]]})

# town walls: north, west, east sides with gates and towers
def wall_run(x0, y0, x1, y1, gate=None):
    L = math.hypot(x1 - x0, y1 - y0)
    n = int(round(L / 12.0))
    t = "wall_000" if abs(y1 - y0) < 1 else "wall_090"
    for k in range(n):
        f = (k + 0.5) / n
        x, y = x0 + (x1 - x0) * f, y0 + (y1 - y0) * f
        if gate and math.hypot(x - gate[0], y - gate[1]) < 9.5:
            continue
        buildings.append({"type": t, "x": round(x, 2), "y": round(y, 2), "layer": "objects"})
    occupied.append(((x0 + x1) / 2, (y0 + y1) / 2, abs(x1 - x0) / 2 + 2, abs(y1 - y0) / 2 + 2))


wall_run(WALL_W, WALL_N, WALL_E, WALL_N, gate=(1650, WALL_N))
wall_run(WALL_W, WALL_N, WALL_W, WALL_S, gate=(WALL_W, 880))
wall_run(WALL_E, WALL_N, WALL_E, WALL_S - 10, gate=(WALL_E, 888))
place("gatehouse", 1650, WALL_N, force=True, yard=False)
place("gatehouse_ns", WALL_W, 880, force=True, yard=False)
place("gatehouse_ns", WALL_E, 888, force=True, yard=False)
for tx, ty in [(WALL_W, WALL_N), (WALL_E, WALL_N), (1578, WALL_N), (1722, WALL_N), (WALL_W, WALL_S),
               (WALL_E, WALL_S - 10), (WALL_W, 835), (WALL_E, 840)]:
    place("wall_tower", tx, ty, force=True, yard=False)

# key buildings (inside and around the walls)
place("barracks", 1752, 808, force=True)
place("blacksmith", 1545, 902, force=True)
place("granary", 1530, 808, force=True)
place("stable", 1835, 880)
place("tower", 1824, 952)
place("windmill", 1302, 856)
place("sawmill", 1098, 765)
place("quarry", 1478, 540, force=True)
place("mine", 1932, 520, force=True)
for fx, fy in [(1975, 1090), (2075, 1180), (1330, 1160), (1520, 680), (1880, 690)]:
    place("farm", fx, fy)

# ------------------------------------------------------------------------------------------------
# continuous street frontages
RICH = ["house_rich_a", "house_rich_b", "house_rich_c"]
SIMPLE = ["house_a", "house_b", "house_c", "house_d", "house_e"]
for _b in RICH + SIMPLE:
    w_, d_ = FOOT[_b]
    FOOT[_b + "_e"] = (d_, w_)
    FOOT[_b + "_w"] = (d_, w_)


def inside_walls(x, y):
    return WALL_W + 3 < x < WALL_E - 3 and WALL_N + 3 < y < WALL_S


def frontage(pts, road_w, side, rich_r=75.0, gap=(0.3, 1.2), pred=inside_walls, max_n=999):
    """Houses packed along one side of a street polyline (side = +1 left / -1 right of the direction)."""
    p = np.array(pts, float)
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    s = 3.0
    n = 0
    while s < cum[-1] - 3 and n < max_n:
        k = min(np.searchsorted(cum, s) - 1, len(seg) - 1)
        k = max(k, 0)
        t = (s - cum[k]) / seg[k]
        pt = p[k] + (p[k + 1] - p[k]) * t
        dvec = (p[k + 1] - p[k]) / seg[k]
        nrm = np.array([-dvec[1], dvec[0]]) * side
        ns_street = abs(dvec[1]) > abs(dvec[0])
        rich = math.hypot(pt[0] - PLAZA_C[0], pt[1] - PLAZA_C[1]) < rich_r and rng.random() < 0.75
        base = (RICH if rich else SIMPLE)[rng.integers(3 if rich else 5)]
        if ns_street:
            bt = base + ("_e" if nrm[0] < 0 else "_w")      # facade towards the street
        else:
            bt = base
        w, d = FOOT[bt]
        along = d if ns_street else w
        depth = w if ns_street else d
        c = pt + nrm * (road_w / 2 + depth / 2 + 0.8) + dvec * (along / 2)
        if pred(c[0], c[1]) and road_dist(c[0], c[1]) > min(w, d) / 2 - 0.2 and place(bt, float(c[0]), float(c[1])):
            n += 1
            # back garden behind the house, aligned with it
            if rng.random() < 0.45:
                gd = rng.uniform(6.0, 10.0)
                g0 = c + nrm * (depth / 2 + 1.2)
                corners = [g0 - dvec * along / 2, g0 + dvec * along / 2, g0 + dvec * along / 2 + nrm * gd,
                           g0 - dvec * along / 2 + nrm * gd]
                gc = g0 + nrm * gd / 2
                if pred(gc[0], gc[1]) and free(gc[0], gc[1], along, gd, margin=0.3) and road_dist(gc[0], gc[1]) > gd / 2:
                    poly = [[round(float(q[0]), 2), round(float(q[1]), 2)] for q in corners]
                    if side < 0:
                        poly = poly[::-1]
                    fields.append({"crop": "green" if rng.random() < 0.75 else "plowed", "polygon": poly,
                                   "dir": round(math.degrees(math.atan2(dvec[1], dvec[0])), 1),
                                   "fence": bool(rng.random() < 0.6)})
                    occupied.append((gc[0], gc[1], along / 2, gd / 2))
            elif rng.random() < 0.5:
                q = c + nrm * (depth / 2 + rng.uniform(3.0, 6.0)) + dvec * rng.uniform(-along / 2, along / 2)
                trees.append({"type": str(rng.choice(["fruit_a", "fruit_b", "fruit_c", "birch_b", "oak_b"])),
                              "x": round(float(q[0]), 2), "y": round(float(q[1]), 2),
                              "scale": round(float(rng.uniform(0.75, 0.95)), 2)})
            s += along + rng.uniform(*gap)
            if rng.random() < 0.35:
                pr = rng.choice(["prop_barrels", "prop_crates", "prop_sacks", "prop_logs"])
                q = c - nrm * (depth / 2 + 1.0) + dvec * rng.uniform(-along / 2, along / 2)
                props.append({"type": str(pr), "x": round(float(q[0]), 2), "y": round(float(q[1]), 2)})
        else:
            s += 2.0


street_order = sorted([r for r in roads if r["kind"] in ("main", "lane")], key=lambda r: {"main": 0, "lane": 1}[r["kind"]])
for r in street_order:
    for side in (1, -1):
        frontage(r["points"], r["width"], side)
# suburbs just outside the gates
for r in roads:
    if r["kind"] == "main":
        for side in (1, -1):
            frontage(r["points"], r["width"], side, gap=(3.0, 9.0), max_n=3,
                     pred=lambda x, y: (not inside_walls(x, y)) and min(math.hypot(x - 1650, y - 770),
                                                                        math.hypot(x - 1490, y - 880),
                                                                        math.hypot(x - 1820, y - 900)) < 55)
# hamlets around the farms
for b in list(buildings):
    if b["type"] == "farm":
        for k in range(int(rng.integers(2, 5))):
            ang = rng.uniform(0, 2 * math.pi)
            dist = rng.uniform(18, 30)
            bt = SIMPLE[rng.integers(len(SIMPLE))]
            place(bt, b["x"] + math.cos(ang) * dist, b["y"] + math.sin(ang) * dist * 0.8)

def shrink(poly, gap):
    c = poly.mean(0)
    return c + (poly - c) * (1 - gap / max(np.linalg.norm(poly - c, axis=1).mean(), 1.0))


FARM_REGIONS = [
    ([(1110, 1035), (1440, 1030), (1500, 1300), (1310, 1420), (1090, 1380), (1070, 1150)], 28.0),
    ([(1130, 745), (1290, 785), (1425, 845), (1405, 900), (1300, 895), (1170, 852)], 15.0),
    ([(1400, 575), (1900, 560), (1975, 690), (1890, 745), (1420, 748)], 0.0),
    ([(1895, 1000), (2100, 925), (2350, 955), (2425, 1120), (2255, 1300), (1960, 1330), (1880, 1100)], 18.0),
    ([(1495, 1260), (1700, 1210), (1800, 1400), (1640, 1500), (1515, 1440)], -30.0),
]
CROPS = ["wheat", "wheat", "wheat", "barley", "barley", "plowed", "plowed", "green", "green", "hay", "flax",
         "wheat", "plowed", "meadow"]


def point_in_poly(x, y, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1 + 1e-9) + x1:
            inside = not inside
    return inside


def cell_ok(poly, region):
    c = poly.mean(0)
    if not point_in_poly(c[0], c[1], region) or sum(point_in_poly(x, y, region) for x, y in poly) < 3:
        return False
    samples = list(poly) + [c] + [(poly[i] + poly[(i + 1) % 4]) / 2 for i in range(4)]
    for x, y in samples:
        if at(WET, x, y) > 0.5 or at(DW, x, y) < 4 or math.degrees(at(SLOPE, x, y)) > 12:
            return False
        if road_dist(x, y) < 2.5:
            return False
    w = np.ptp(poly[:, 0])
    d = np.ptp(poly[:, 1])
    if not free(c[0], c[1], w * 0.8, d * 0.8, margin=1.0):
        return False
    return True


for region, ang in FARM_REGIONS:
    reg = np.array(region, float)
    a_ = math.radians(ang)
    ux = np.array([math.cos(a_), math.sin(a_)])
    uy = np.array([-math.sin(a_), math.cos(a_)])
    c0 = reg.mean(0)
    loc = (reg - c0) @ np.c_[ux, uy]
    lo, hi = loc.min(0) - 20, loc.max(0) + 20
    xs_ = [lo[0]]
    while xs_[-1] < hi[0]:
        xs_.append(xs_[-1] + rng.uniform(38, 85))
    ys_ = [lo[1]]
    while ys_[-1] < hi[1]:
        ys_.append(ys_[-1] + rng.uniform(26, 55))
    G = np.zeros((len(ys_), len(xs_), 2))
    for j, yv in enumerate(ys_):
        for i, xv in enumerate(xs_):
            jit = rng.normal(0, 5.0, 2)
            G[j, i] = c0 + ux * (xv + jit[0]) + uy * (yv + jit[1])
    for j in range(len(ys_) - 1):
        for i in range(len(xs_) - 1):
            poly = np.array([G[j, i], G[j, i + 1], G[j + 1, i + 1], G[j + 1, i]])
            poly = shrink(poly, rng.uniform(1.6, 3.2))
            if not cell_ok(poly, region):
                continue
            crop = CROPS[rng.integers(len(CROPS))]
            if crop == "meadow":
                continue
            e = poly[1] - poly[0]
            dirn = math.degrees(math.atan2(e[1], e[0])) + (90 if rng.random() < 0.3 else 0)
            fields.append({"crop": crop, "polygon": [[round(float(x), 2), round(float(y), 2)] for x, y in poly],
                           "dir": round(dirn, 1), "fence": bool(crop == "hay" or rng.random() < 0.12)})
            cc = poly.mean(0)
            occupied.append((cc[0], cc[1], np.ptp(poly[:, 0]) * 0.4, np.ptp(poly[:, 1]) * 0.4))


# small agricultural details in the fields
for f in fields:
    p = np.array(f["polygon"])
    area = abs(np.cross(p[2] - p[0], p[3] - p[1])) / 2
    if area < 600:
        continue
    c = p.mean(0)
    r_ = rng.random()
    if f["crop"] in ("wheat", "barley") and r_ < 0.35:
        props.append({"type": "prop_scarecrow", "x": round(float(c[0]), 2), "y": round(float(c[1]), 2)})
    elif f["crop"] == "hay":
        for k in range(int(rng.integers(2, 5))):
            q = c + rng.normal(0, 6, 2)
            props.append({"type": str(rng.choice(["prop_haystack", "prop_bales"])), "x": round(float(q[0]), 2),
                          "y": round(float(q[1]), 2)})
    elif f["crop"] in ("wheat", "barley") and r_ < 0.6:
        q = p[0] + (p[1] - p[0]) * 0.2 + (p[3] - p[0]) * 0.15
        props.append({"type": "prop_cart_hay", "x": round(float(q[0]), 2), "y": round(float(q[1]), 2)})


# orchard and garden trees around houses, a few hedgerow bushes along field edges
for b in list(buildings):
    if b["type"].startswith("house") or b["type"] == "farm":
        for k in range(int(rng.integers(0, 3))):
            ang = rng.uniform(0, 2 * math.pi)
            dist = rng.uniform(7, 13)
            tx, ty = b["x"] + math.cos(ang) * dist, b["y"] + math.sin(ang) * dist * 0.8 + 3
            if free(tx, ty, 3, 3, margin=0.2) and road_dist(tx, ty) > 3 and at(WET, tx, ty) < 0.5:
                trees.append({"type": str(rng.choice(["fruit_a", "fruit_b", "fruit_c", "oak_b", "bush_a", "bush_c",
                                                      "birch_b"])), "x": round(tx, 2), "y": round(ty, 2),
                              "scale": round(float(rng.uniform(0.8, 1.05)), 2)})
for f in fields:
    if rng.random() < 0.5:
        p = np.array(f["polygon"])
        a, b = p[0], p[3]
        for t in np.linspace(0.1, 0.9, int(np.linalg.norm(b - a) / 9)):
            q = a + (b - a) * t + rng.normal(0, 0.8, 2)
            trees.append({"type": str(rng.choice(["bush_a", "bush_b", "bush_c", "bush_d", "oak_b"])),
                          "x": round(float(q[0]), 2), "y": round(float(q[1]), 2),
                          "scale": round(float(rng.uniform(0.7, 1.0)), 2)})

# ------------------------------------------------------------------------------------------------
# citizens (visual demonstration: walking along roads, working at buildings and in fields)
def walk_path(r, rev=False):
    pts = r["points"][::-1] if rev else r["points"]
    return [[round(x, 2), round(y, 2)] for x, y in pts]


roles_walk = ["citizen", "citizen", "merchant", "farmer", "builder", "soldier", "woodcutter", "miner"]
for i, r in enumerate(roads):
    n = {"main": 7, "lane": 4, "path": 2}[r["kind"]]
    for k in range(n):
        role = roles_walk[(i * 3 + k) % len(roles_walk)]
        if r["points"][0][1] < 760 and role == "citizen":
            role = "miner"
        citizens.append({"role": role, "mode": "carry" if rng.random() < 0.25 else "walk",
                         "path": walk_path(r, rev=bool(k % 2)), "start": round(float(rng.random()), 3),
                         "speed": round(float(rng.uniform(1.0, 1.45)), 2)})
# plaza crowd
for k in range(26):
    x = rng.uniform(1628, 1668)
    y = rng.uniform(853, 886)
    citizens.append({"role": str(rng.choice(["citizen", "citizen", "merchant", "farmer", "builder"])),
                     "mode": "wander", "spot": [round(x, 2), round(y, 2)], "radius": 14.0,
                     "speed": round(float(rng.uniform(0.8, 1.2)), 2)})
for sx, sy in [(1632, 860), (1640, 878), (1660, 858), (1663, 876), (1631, 883)]:
    citizens.append({"role": "merchant", "mode": "work", "spot": [sx, sy - 1.6], "dir": "S"})
# workers at their buildings
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
# guards at the gates and on the bridges
for gx, gy in [(1645, 798), (1655, 798), (1514, 876), (1786, 884), (1682, 968), (1840, 934), (1470, 986)]:
    citizens.append({"role": "soldier", "mode": "idle", "spot": [gx, gy], "dir": "S"})
# farmers in the fields
for f in fields:
    if f["crop"] in ("wheat", "green", "plowed", "barley") and rng.random() < 0.6:
        p = np.array(f["polygon"])
        c = p.mean(0)
        for k in range(int(rng.integers(1, 4))):
            q = c + rng.normal(0, 6, 2)
            citizens.append({"role": "farmer", "mode": "work", "spot": [round(float(q[0]), 2), round(float(q[1]), 2)],
                             "dir": str(rng.choice(["S", "SE", "E", "W", "SW"]))})
# woodcutters at the forest edge near the sawmill
for k in range(4):
    citizens.append({"role": "woodcutter", "mode": "work", "spot": [round(1040 + k * 9.0, 2), round(735 + rng.uniform(-3, 3), 2)],
                     "dir": str(rng.choice(["E", "W", "S"]))})

out = {"name": "Altavera", "roads": roads, "plazas": plazas, "fields": fields, "buildings": buildings,
       "props": props, "trees": trees, "yards": yards, "citizens": citizens}
path = os.path.join(K.GAME_DIR, "data", "valley", "demo_town.json")
with open(path, "w") as f:
    json.dump(out, f, indent=0)
print(f"buildings {len(buildings)}  roads {len(roads)}  fields {len(fields)}  props {len(props)}  "
      f"trees {len(trees)}  citizens {len(citizens)}")

# plan image for checking
x0, x1, y0, y1 = 1050, 2320, 480, 1400
sc = 1.2
img = Image.new("RGB", (int((x1 - x0) * sc), int((y1 - y0) * sc)), (120, 140, 80))
sub_w = WET[int(y0 - Y0):int(y1 - Y0), x0:x1]
water = Image.fromarray((sub_w * 255).astype(np.uint8)).resize(img.size)
img.paste((60, 100, 170), mask=water)
d = ImageDraw.Draw(img)
T = lambda x, y: ((x - x0) * sc, (y - y0) * sc)  # noqa: E731
colmap = {"wheat": (210, 180, 70), "barley": (200, 190, 120), "plowed": (130, 90, 60), "green": (80, 140, 60),
          "hay": (170, 170, 90), "flax": (130, 140, 190)}
for f in fields:
    d.polygon([T(*p) for p in f["polygon"]], fill=colmap[f["crop"]], outline=(60, 50, 30) if f["fence"] else None)
for p in plazas:
    d.polygon([T(*q) for q in p["polygon"]], fill=(170, 160, 140))
for r in roads:
    d.line([T(*q) for q in r["points"]], fill=(200, 180, 130), width=max(1, int(r["width"] * sc)))
for b in buildings:
    w, dd = FOOT.get(b["type"], (6, 6))
    if b["type"].startswith("wall_0") or b["type"].startswith("wall_1"):
        w, dd = 12, 2.2
    if b["type"].startswith("bridge"):
        continue
    col = (150, 60, 40) if b["type"].startswith("house") else (90, 90, 110)
    d.rectangle([T(b["x"] - w / 2, b["y"] - dd / 2), T(b["x"] + w / 2, b["y"] + dd / 2)], fill=col)
for t in trees:
    x, y = T(t["x"], t["y"])
    d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(30, 70, 30))
for c in citizens:
    q = c.get("spot") or c["path"][0]
    x, y = T(*q)
    d.point((x, y), fill=(255, 255, 255))
img.save("/tmp/claude-0/-home-user-claude-code-kings-domain-2/55f0861c-818d-5374-baf7-a8443f8b41b4/scratchpad/town_layout.png")
