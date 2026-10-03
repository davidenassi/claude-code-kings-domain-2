"""Hand-designed layout of the King's Domain valley ("Valle di Altavera").

World metres: x east [0, 3072], y south [-640 (north padding), 2560].
The camera looks north: high snowy peaks along the north edge form the backdrop, rocky ranges close the
west, a terraced plateau with cliffs closes the east, low wooded hills close the south (they must stay low
so they never hide the valley floor behind them).

Water:
  * Fiume Argento   — main river, enters from a gorge in the north-east with two cascades, meanders
                      south-west through the valley, feeds Lago Specchio, leaves through a southern gorge.
  * Torrente Bianco — tributary from the north-west: crosses a hanging valley and drops ~37 m in a
                      south-facing waterfall (visible from the camera), joins the Argento at the confluence.
  * Rio Ponente     — small brook from the west range into the lake.
  * Lago Specchio   — lake in the south-centre of the valley.
The confluence wedge between Torrente Bianco and Fiume Argento hosts the castle hill (Rocca).
"""
from __future__ import annotations

import numpy as np

# (x, y, water_level, width, depth)
RIVERS = {
    "argento": [
        (2905, -660, 330, 9, 1.5),
        (2880, -380, 270, 11, 1.5),
        (2850, -110, 214, 13, 1.8),
        (2815, 110, 186, 15, 2.0),
        (2795, 205, 178, 16, 2.0),
        (2786, 222, 160, 16, 2.0),   # cascade 1 (18 m)
        (2772, 262, 156, 17, 2.0),
        (2745, 345, 146, 18, 2.2),
        (2735, 362, 128, 18, 2.2),   # cascade 2 (18 m)
        (2700, 420, 124, 22, 2.5),
        (2580, 548, 117, 28, 3.0),
        (2420, 650, 113.5, 33, 3.0),
        (2240, 745, 111.2, 37, 3.4),
        (2075, 818, 109.6, 40, 3.5),
        (1925, 905, 108.6, 42, 3.6),
        (1790, 1015, 107.6, 45, 3.8),
        (1690, 1118, 107.0, 50, 4.0),  # confluence
        (1612, 1225, 106.0, 55, 4.0),
        (1540, 1350, 104.6, 58, 4.0),
        (1470, 1470, 103.4, 60, 4.0),
        (1400, 1575, 102.8, 70, 4.0),  # enters the lake
    ],
    "argento_out": [
        (1290, 1835, 102.8, 46, 3.0),
        (1355, 1960, 101.8, 40, 3.0),
        (1450, 2100, 100.2, 36, 3.0),
        (1530, 2250, 97.5, 30, 3.0),
        (1572, 2400, 93.5, 26, 3.0),
        (1600, 2640, 89.0, 26, 3.0),
    ],
    "bianco": [
        (760, -660, 372, 6, 1.0),
        (788, -400, 310, 7, 1.2),
        (800, -140, 248, 8, 1.2),
        (812, 90, 196, 9, 1.4),
        (826, 245, 183, 10, 1.5),
        (836, 318, 180, 10, 1.6),    # lip of the hanging valley
        (840, 338, 143, 11, 1.6),    # waterfall (37 m)
        (846, 372, 136, 14, 2.4),    # plunge pool
        (895, 505, 129, 14, 2.0),
        (995, 668, 122, 16, 2.2),
        (1125, 805, 116, 18, 2.4),
        (1285, 915, 111.5, 20, 2.5),
        (1445, 995, 108.8, 22, 2.6),
        (1585, 1062, 107.5, 24, 2.6),
        (1690, 1118, 107.0, 26, 2.6),
    ],
    "ponente": [
        (40, 1290, 196, 5, 1.0),
        (250, 1415, 142, 6, 1.2),
        (470, 1525, 114, 8, 1.4),
        (690, 1615, 105.5, 10, 1.6),
        (870, 1688, 103.4, 12, 1.8),
        (975, 1712, 102.8, 14, 2.0),
    ],
}

LAKE = {
    "center": (1165.0, 1705.0),
    "radii": (330.0, 205.0),
    "rotation_deg": -14.0,
    "level": 102.8,
    "max_depth": 11.0,
}

# points where rivers meet (meander offsets fade out here)
JUNCTIONS = [(1690, 1118), (1400, 1575), (1290, 1835), (975, 1712)]

# east plateau (dissected mesa with cliff edges): polygon + top altitude
MESA = {"polygon": [(2700, 980), (3100, 900), (3100, 1900), (2790, 1860), (2720, 1600), (2665, 1330)],
        "top": 268.0, "cliff": 22.0}

# polygon (x, y) of the flat valley floor: mountains start outside it
FLOOR_POLYGON = [
    (420, 720), (520, 620), (610, 480), (650, 300), (740, 170), (900, 140), (1020, 220),
    (1060, 400), (1160, 490), (1480, 520), (1880, 515), (2240, 560),
    (2520, 520), (2640, 640), (2610, 900), (2560, 1280), (2610, 1680), (2520, 2040), (2220, 2170),
    (1920, 2190), (1660, 2140), (1300, 2160), (900, 2140), (520, 2060), (330, 1760), (370, 1400),
    (340, 1040),
]

# coarse amplitude grid for the mountains (metres above the floor), rows = y, cols = x
AMP_X = [0, 768, 1536, 2304, 3072]
AMP_Y = [-640, 0, 640, 1280, 1920, 2560]
AMP = [
    [840, 900, 930, 900, 820],
    [700, 760, 800, 760, 680],
    [520, 440, 400, 420, 400],
    [540, 200, 150, 250, 360],
    [420, 160, 150, 200, 330],
    [200, 150, 140, 150, 200],
]

# features: (x, y, radius_m, height_m, kind)
KNOLLS = [
    (1625, 985, 55, 26.0, "castle"),      # Rocca: rocky knoll for the castle
    (1300, 862, 70, 9.0, "soft"),         # windmill rise west of the Torrente Bianco
    (2290, 1260, 140, 26.0, "soft"),      # wooded hill east of the river
    (700, 1010, 120, 30.0, "rocky"),      # rocky hill near the west range
    (980, 1230, 55, 9.0, "rocky"),        # small outcrop in the western plain
    (2050, 1640, 110, 16.0, "soft"),      # low rise south-east
    (520, 1880, 140, 34.0, "soft"),
]

# hanging valley in the north-west (terrace above the waterfall)
TERRACE_NW = {"x0": 600, "x1": 1080, "y_edge": 352, "height": 44.0, "cliff_width": 6.0}

TOWN_CENTER = (1625.0, 985.0)


def catmull_rom(points: np.ndarray, samples_per_seg: int = 40) -> np.ndarray:
    """Centripetal Catmull-Rom through all points (with duplicated end points)."""
    pts = np.vstack([points[0] * 2 - points[1], points, points[-1] * 2 - points[-2]])
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]

        def tj(ti, a, b):
            return ti + max(np.linalg.norm(b - a), 1e-6) ** 0.5

        t0 = 0.0
        t1 = tj(t0, p0, p1)
        t2 = tj(t1, p1, p2)
        t3 = tj(t2, p2, p3)
        ts = np.linspace(t1, t2, samples_per_seg, endpoint=False)[:, None]
        a1 = (t1 - ts) / (t1 - t0) * p0 + (ts - t0) / (t1 - t0) * p1
        a2 = (t2 - ts) / (t2 - t1) * p1 + (ts - t1) / (t2 - t1) * p2
        a3 = (t3 - ts) / (t3 - t2) * p2 + (ts - t2) / (t3 - t2) * p3
        b1 = (t2 - ts) / (t2 - t0) * a1 + (ts - t0) / (t2 - t0) * a2
        b2 = (t3 - ts) / (t3 - t1) * a2 + (ts - t1) / (t3 - t1) * a3
        out.append((t2 - ts) / (t2 - t1) * b1 + (ts - t1) / (t2 - t1) * b2)
    out.append(points[-1:])
    return np.vstack(out)


def densify_river(name: str, step: float = 2.0, wobble_seed: int = 0):
    """Return dense samples: x, y, level, width, depth, tangent (tx, ty), arc length s."""
    cps = np.array(RIVERS[name], dtype=np.float64)
    xy = catmull_rom(cps[:, :2], 60)
    # arc length resample
    seg = np.linalg.norm(np.diff(xy, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    n = max(2, int(s[-1] / step))
    s_new = np.linspace(0, s[-1], n)
    x = np.interp(s_new, s, xy[:, 0])
    y = np.interp(s_new, s, xy[:, 1])
    # control point arc positions: nearest dense sample to each control point
    cp_s = []
    for cx, cy in cps[:, :2]:
        k = np.argmin((x - cx) ** 2 + (y - cy) ** 2)
        cp_s.append(s_new[k])
    cp_s = np.maximum.accumulate(np.array(cp_s))
    level = np.interp(s_new, cp_s, cps[:, 2])
    width = np.interp(s_new, cp_s, cps[:, 3])
    depth = np.interp(s_new, cp_s, cps[:, 4])
    # organic width variation
    rng = np.random.default_rng(wobble_seed + len(name))
    freq = rng.uniform(0, 2 * np.pi, 3)
    wv = (0.12 * np.sin(s_new / 37.0 + freq[0]) + 0.08 * np.sin(s_new / 13.0 + freq[1])
          + 0.05 * np.sin(s_new / 5.3 + freq[2]))
    width = width * (1.0 + wv)
    # meanders: lateral offset along the normal, tapered at junctions so confluences stay aligned
    tx = np.gradient(x)
    ty = np.gradient(y)
    tl = np.maximum(np.hypot(tx, ty), 1e-6)
    nxv, nyv = -ty / tl, tx / tl
    ph = rng.uniform(0, 2 * np.pi, 4)
    wig = (np.sin(s_new / 61.0 + ph[0]) * 0.55 + np.sin(s_new / 23.0 + ph[1]) * 0.3
           + np.sin(s_new / 9.0 + ph[2]) * 0.15)
    mountain = (y < 420) | (x < 330)
    amp = 3.0 + 0.30 * width + 16.0 * mountain
    taper = np.minimum(1.0, np.minimum(s_new, s_new[-1] - s_new) / 90.0)
    for jx, jy in JUNCTIONS:
        taper = taper * np.clip(np.hypot(x - jx, y - jy) / 120.0, 0.0, 1.0)
    off = wig * amp * taper
    x = x + nxv * off
    y = y + nyv * off
    tx = np.gradient(x)
    ty = np.gradient(y)
    tl = np.maximum(np.hypot(tx, ty), 1e-6)
    return {
        "x": x, "y": y, "level": level, "width": width, "depth": depth,
        "tx": tx / tl, "ty": ty / tl, "s": s_new,
    }


def lake_radius(theta: np.ndarray) -> np.ndarray:
    """Irregular lake outline radius scale for angle theta (unit ellipse * this)."""
    return (1.0 + 0.10 * np.sin(3 * theta + 0.7) + 0.06 * np.sin(5 * theta + 2.1)
            + 0.04 * np.sin(9 * theta + 0.3) + 0.025 * np.sin(17 * theta + 1.9))


# ------------------------------------------------------------------------------------------------
# Land use planned around the demonstration settlement (kept free of forest).
# polygons in world metres; the town core is a circle.
TOWN_CORE = {"center": (1600.0, 930.0), "radius": 250.0}
OPEN_LAND = [
    # farmland west of the Torrente Bianco
    [(960, 860), (1180, 820), (1420, 930), (1520, 1060), (1500, 1300), (1300, 1420), (1080, 1380),
     (930, 1180)],
    # farmland east of the Fiume Argento
    [(1820, 1080), (1990, 930), (2200, 850), (2420, 930), (2440, 1120), (2230, 1330), (1960, 1360)],
    # meadows north of the town, up to the foothills
    [(1250, 640), (1560, 600), (1900, 640), (2080, 780), (1880, 900), (1500, 820), (1300, 760)],
    # pastures south of the confluence, towards the lake
    [(1480, 1250), (1700, 1200), (1820, 1420), (1640, 1520), (1500, 1450)],
]
# planned forests on the valley floor (in addition to the natural mountain forests)
FOREST_PATCHES = [
    [(560, 700), (900, 600), (1050, 780), (900, 950), (700, 1050), (520, 950)],      # Bosco Nero (NW)
    [(2450, 700), (2620, 650), (2640, 1000), (2520, 1150), (2420, 950)],             # east foothill wood
    [(1900, 1500), (2250, 1420), (2450, 1600), (2300, 1900), (1950, 1850)],          # southern wood
    [(600, 1250), (880, 1300), (900, 1500), (650, 1580), (480, 1450)],               # western wood
    [(2200, 1150), (2380, 1150), (2400, 1350), (2250, 1400), (2150, 1300)],          # hill wood
]


# ------------------------------------------------------------------------------------------------
# Mountain massifs: explicit summits (x, y, height above floor, radius) and ridges between them.
PEAKS = {
    # north range (backdrop)
    "N1": (150, 40, 600, 640),
    "N2": (500, -260, 800, 760),
    "N3": (930, -430, 880, 820),
    "N4": (1290, -120, 720, 660),
    "N5": (1660, -400, 960, 880),    # Corona: highest summit
    "N6": (2060, -90, 700, 640),
    "N7": (2420, -360, 860, 780),
    "N8": (2640, 60, 520, 520),
    "N9": (3060, -220, 780, 720),
    # spurs reaching towards the valley
    "N4s": (1360, 300, 300, 420),
    "N6s": (2150, 330, 270, 400),
    "N2s": (430, 330, 330, 430),
    # west range
    "W1": (110, 640, 540, 560),
    "W2": (170, 1080, 500, 520),
    "W3": (70, 1500, 470, 500),
    "W4": (160, 1930, 400, 470),
    # east (north and south of the plateau)
    "E1": (3000, 620, 520, 520),
    "E2": (2960, 2080, 360, 460),
    # south hills (kept low: they are in front of the camera)
    "S1": (380, 2470, 210, 420),
    "S2": (880, 2520, 170, 380),
    "S3": (1260, 2440, 140, 320),
    "S4": (1900, 2470, 160, 380),
    "S5": (2380, 2430, 200, 420),
    "S6": (2880, 2340, 240, 440),
}
RIDGES = [
    ("N1", "N2", 0.62), ("N2", "N3", 0.70), ("N3", "N4", 0.64), ("N4", "N5", 0.66), ("N5", "N6", 0.64),
    ("N6", "N7", 0.66), ("N7", "N8", 0.58), ("N7", "N9", 0.55), ("N4", "N4s", 0.8), ("N6", "N6s", 0.8),
    ("N2", "N2s", 0.75), ("N1", "W1", 0.7), ("W1", "W2", 0.68), ("W2", "W3", 0.68), ("W3", "W4", 0.7),
    ("W4", "S1", 0.6), ("S1", "S2", 0.7), ("S2", "S3", 0.7), ("S4", "S5", 0.7), ("S5", "S6", 0.7),
    ("N9", "E1", 0.62), ("E2", "S6", 0.7),
]

# terrain flattened for construction: (cx, cy, rx, ry, altitude, falloff m)
FLATTEN = [
    (1652.0, 962.0, 22.0, 26.0, 136.0, 7.0),      # castle plateau on the Rocca
]
