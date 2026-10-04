"""Phase 1B vertical slice: the Altavera river quarter on the Torrente Bianco.

A hand-composed district (not procedural filler): market square with fountain and stalls, parish church
with churchyard, a row of town houses, a residential lane with gardens, a water mill on the bank, a stone
bridge, a smithy, a military compound (barracks, stable, palisade, watchtower, training yard), and across
the river a farm with fields, orchard, pig pen and chicken coop.

Every building carries its "ecosystem" (yard, fences, woodpile, barrels, flowers, people, animals) declared
in the building's own frame and rotated with it.

Coordinates: world metres (x east, y south). The street grid is turned 45 degrees to the camera so every
building shows two facades (as in the illustrated references).
Yaw convention (sprites): the facade faces world direction (sin yaw, cos yaw): 0 south, 45 south-east,
-45 south-west, 135 north-east, -135 north-west.

Writes game/data/valley/slice.json and slice_sprites.json (sprites the layout needs).
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from kd import const as K  # noqa: E402

CACHE = os.path.join(K.CACHE_DIR, "terrain")
Y0 = int(-K.NORTH_PAD_M)
H = np.load(os.path.join(CACHE, "h_final.npy"))
WET = np.load(os.path.join(CACHE, "wet.npy"))
rng = np.random.default_rng(1909)

A = np.array([0.70710678, -0.70710678])     # grid axis u: north-east
B = np.array([0.70710678, 0.70710678])      # grid axis v: south-east
M = np.array([1490.0, 952.0])               # market square centre


def P(u, v):
    return M + u * A + v * B


def hz(x, y):
    """Bilinear terrain altitude."""
    fx, fy = x, y - Y0
    i, j = int(fx), int(fy)
    ax, ay = fx - i, fy - j
    a = H[j, i] * (1 - ax) + H[j, i + 1] * ax
    b = H[j + 1, i] * (1 - ax) + H[j + 1, i + 1] * ax
    return float(a * (1 - ay) + b * ay)


def wet(x, y):
    return WET[int(y - Y0), int(x)] > 0.5


def yaw_name(base, yaw):
    yaw = int(round(yaw))
    return f"{base}@{yaw:03d}" if yaw >= 0 else f"{base}@m{-yaw:03d}"


def local_to_world(lx, ly, yaw):
    """Offset in a model's frame (Blender: x right, y back) -> world metres (x east, y south)."""
    t = math.radians(yaw)
    bx = lx * math.cos(t) - ly * math.sin(t)
    by = lx * math.sin(t) + ly * math.cos(t)
    return np.array([bx, -by])


def norm180(yaw):
    """Props that look alike when turned by 180 degrees: keep yaw in [-90, 90)."""
    y = (yaw + 90) % 180 - 90
    return y


def quant(yaw, step):
    return int(round(yaw / step) * step)


SYMMETRIC = {"fence", "fence_wattle", "wall_low", "bench", "trough", "planks", "logs", "palisade", "weapon_rack",
             "weapons_table", "laundry", "beehives", "firewood", "garden_bed", "bales", "crates", "boat", "cart_hay",
             "cart_goods", "cart_logs", "cart_stone", "target", "dummy", "tools_rack", "wheelbarrow", "signpost"}
ROUND = {"barrel", "barrels", "sacks", "haystack", "flowers", "rosebush", "sunflowers", "stump", "reeds", "lilypads",
         "pottery", "rocks_bank", "well", "anvil_set", "coop", "lantern", "grave_cross", "grave_stone", "banner_pole",
         "fountain"}

objects = []          # buildings and props (y-sorted sprites)
people = []
animals = []
ground = {"roads": [], "plazas": [], "fields": [], "yards": [], "gardens": [], "trampled": [], "mud": []}
veg = []
sprites = set()


def put(base, x, y, yaw=0.0, z=None, kind="prop", **extra):
    if base in ROUND:
        yaw = 0
    elif base in SYMMETRIC:
        yaw = quant(norm180(yaw), 45 if base not in ("fence", "fence_wattle", "palisade", "wall_low") else 22.5)
    name = yaw_name(base, yaw)
    sprites.add(name)
    o = {"sprite": name, "x": round(float(x), 2), "y": round(float(y), 2), "kind": kind}
    if z is not None:
        o["z"] = round(float(z), 2)
    o.update(extra)
    objects.append(o)
    return o


def building(base, x, y, yaw, z=None, eco=(), **extra):
    """Place a building and its ecosystem: eco = [(prop, lx, ly, rel_yaw)] in the building frame."""
    o = put(base, x, y, yaw, z, kind="building", **extra)
    sprites.add(yaw_name(base, int(round(yaw))))
    o["sprite"] = yaw_name(base, int(round(yaw)))
    for item in eco:
        prop, lx, ly = item[0], item[1], item[2]
        rel = item[3] if len(item) > 3 else 0.0
        off = local_to_world(lx, ly, yaw)
        put(prop, x + off[0], y + off[1], yaw + rel)
    return o


def person(role, mode, **kw):
    d = {"role": role, "mode": mode}
    for k, v in kw.items():
        if isinstance(v, np.ndarray):
            v = [round(float(v[0]), 2), round(float(v[1]), 2)]
        elif isinstance(v, (list, tuple)) and v and isinstance(v[0], (list, tuple, np.ndarray)):
            v = [[round(float(p[0]), 2), round(float(p[1]), 2)] for p in v]
        d[k] = v
    people.append(d)


def animal(kind, mode, spot, radius=3.0, dirn="S", **kw):
    animals.append({"kind": kind, "mode": mode, "spot": [round(float(spot[0]), 2), round(float(spot[1]), 2)],
                    "radius": radius, "dir": dirn, **kw})


def fence_poly(poly, base="fence", gaps=()):
    """Fence segments (4 m) along a closed polygon; gaps = edge indices left open (gates)."""
    n = len(poly)
    for i in range(n):
        if i in gaps:
            continue
        a, b = np.array(poly[i], float), np.array(poly[(i + 1) % n], float)
        d = b - a
        L = float(np.linalg.norm(d))
        segs = max(1, int(round(L / 4.0)))
        yaw = math.degrees(math.atan2(-d[1], d[0]))       # Blender heading of the segment
        for s in range(segs):
            c = a + d * ((s + 0.5) / segs)
            put(base, c[0], c[1], yaw)


def tree(t, x, y, s=1.0):
    veg.append({"type": t, "x": round(float(x), 2), "y": round(float(y), 2), "scale": round(float(s), 2)})


# ================================================================================================
# 1. the river crossing: stone bridge (perpendicular to the current) and the main street
BR_C = np.array([1462.0, 1005.0])
BR_DIR = np.array([0.766, -0.643])            # across the river (diagonal: the arches face the camera)
BR_YAW = 40.0                                # bridge model along local X -> world (cos 40, -sin 40)
BR_LEN = 36.0
bank_z = (hz(*(BR_C + BR_DIR * 19)) + hz(*(BR_C - BR_DIR * 19))) / 2
put("bridge", BR_C[0], BR_C[1], BR_YAW, z=bank_z, kind="bridge")
objects[-1]["sprite"] = yaw_name("bridge", BR_YAW)
sprites.add(yaw_name("bridge", BR_YAW))
BR_N = BR_C + BR_DIR * (BR_LEN / 2)
BR_S = BR_C - BR_DIR * (BR_LEN / 2)

SQ_W = P(-16, 0)                              # middle of the square's south-west side
MAIN = [BR_N, BR_N + BR_DIR * 6, (BR_N + BR_DIR * 6 + SQ_W) / 2 + np.array([1.5, 0.5]), SQ_W + A * 2.0]
ground["roads"].append({"kind": "urban", "width": 5.6, "points": MAIN})
ground["roads"].append({"kind": "bridge", "width": 4.0, "points": [BR_S, BR_N]})

# ================================================================================================
# 2. market square: irregular paving, fountain, stalls, goods, carts
sq = []
for (u, v) in [(-16, -13), (-4, -14.5), (8, -13.5), (16, -12), (17, 0), (16, 13), (2, 14.5), (-14, 13), (-17, 2)]:
    sq.append(P(u + rng.uniform(-0.8, 0.8), v + rng.uniform(-0.8, 0.8)))
ground["plazas"].append({"kind": "square", "polygon": sq})
put("fountain", *P(0, 0))
stalls = [("stall_canvas", -8, -7, 45), ("stall_red", 1, -8.5, 45), ("stall_blue", 9, -6, -45), ("stall_green", 9, 5, -45),
          ("stall_canvas", -9, 6, 45), ("stall_red", -1, 8.5, 135)]
for base, u, v, yaw in stalls:
    q = P(u, v)
    building(base, q[0], q[1], yaw)
    # merchant behind the counter, two customers in front
    m = q + local_to_world(0.0, 0.45, yaw)
    person("merchant" if u % 2 else "woman", "work", spot=m, dir=None, face_yaw=yaw, anim="talk")
    c = q + local_to_world(rng.uniform(-0.8, 0.8), -2.0, yaw)
    person(rng.choice(["woman", "citizen", "farmer", "artisan"]), "idle", spot=c, face_yaw=yaw + 180, anim="talk")
for base, u, v, ry in [("crates", -12, -2, 20), ("sacks", -11, -0.5, 0), ("barrels", 12.5, -1, 0), ("pottery", 5, 11, 0),
                       ("cart_goods", 4, -11.5, 10), ("barrel", -5, 11.5, 0), ("crates", 13, 9, -30), ("sacks", -3, -11, 0)]:
    q = P(u, v)
    put(base, q[0], q[1], 45 + ry)
for k in range(12):
    q = P(rng.uniform(-12, 12), rng.uniform(-9, 9))
    person(str(rng.choice(["citizen", "woman", "woman", "artisan", "farmer", "merchant"])), "wander", spot=q, radius=7.0)
animal("chicken", "wander", P(-6, 12), 3.0)
animal("chicken", "wander", P(-4, 12.5), 3.0)

# ================================================================================================
# 3. north-west row of houses facing the square (facades towards the south-east)
row = [("house_town", -10.5, 49), ("house_tall", -1.5, 43), ("house_merchant", 8.5, 46)]
for base, u, yaw in row:
    q = P(u, -13 - 2.2 - (4.0 if base != "house_tall" else 4.4))
    eco = [("barrels", -3.8, -3.6, 0), ("flowers", 2.6, -3.9, 0)] if base == "house_town" else \
          [("crates", 3.4, -4.0, 0), ("rosebush", -3.0, -4.2, 0)] if base == "house_merchant" else \
          [("barrel", 2.6, -4.6, 0), ("flowers", -2.2, -4.4, 0)]
    building(base, q[0], q[1], yaw, eco=eco)
    # back gardens (north-west of the row)
    g = P(u, -13 - 2.2 - 8.0 - 5.5)
    ground["gardens"].append({"center": g, "size": [8.0, 6.0], "yaw": 45})
    put("garden_bed", g[0], g[1], 45)
    tree(str(rng.choice(["fruit_a", "fruit_b", "fruit_c"])), *(g + B * 4.5 + A * 2.0), 0.9)
person("woman", "work", spot=P(-10.5, -21.0), anim="work", face_yaw=45)

# ================================================================================================
# 4. the church facing the square, churchyard with graves, low wall, yews
CH = P(29.5, 1.5)
building("church", CH[0], CH[1], -45, eco=[("flowers", 3.5, -12.5, 0), ("rosebush", -6.5, -10.0, 0)])
yard = [P(18.5, -9), P(42, -9), P(42, 9.5), P(18.5, 9.5)]
for gi in range(10):
    gq = P(rng.uniform(22, 40), rng.uniform(-8.0, -6.0) if gi < 5 else rng.uniform(7.4, 8.8))
    put("grave_cross" if gi % 3 == 0 else "grave_stone", gq[0], gq[1], -45)
for a_, b_ in ((yard[0], yard[1]), (yard[2], yard[3])):
    d = np.array(b_) - np.array(a_)
    n = int(np.linalg.norm(d) / 4.0)
    for s in range(n):
        c = np.array(a_) + d * ((s + 0.5) / n)
        put("wall_low", c[0], c[1], math.degrees(math.atan2(-d[1], d[0])))
for q in (P(40, -7.5), P(40, 8), P(21, -7.8)):
    tree("spruce_b", q[0], q[1], 0.8)
ground["trampled"].append({"center": P(17.5, 1.5), "size": [6.0, 10.0], "yaw": -45})
person("woman", "idle", spot=P(30, -7), face_yaw=-45, anim="idle")
person("citizen", "idle", spot=P(16.5, 0.5), face_yaw=135, anim="talk")
person("woman", "idle", spot=P(16.8, 2.4), face_yaw=-45, anim="talk")

# ================================================================================================
# 5. residential lane going north-west from the square's west corner (towards the orchard)
LANE = [P(-16, -10), P(-19, -22), P(-18, -36), P(-21, -50)]
ground["roads"].append({"kind": "lane", "width": 3.6, "points": LANE})
lane_houses = [("house_cottage", -26.5, -27, 135 - 8, [("firewood", 0.0, 4.2, 0), ("barrel", 3.6, 3.2, 0)]),
               ("house_stone", -12.0, -29, -45 + 6, [("firewood", 3.8, 0.0, 90), ("flowers", -2.6, -4.0, 0)]),
               ("house_cabin", -26.0, -42, 135 + 4, [("logs", 0.0, 4.8, 0), ("stump", 3.2, 3.6, 0)]),
               ("house_timber", -11.5, -43, -45 - 5, [("wheelbarrow", 3.6, -3.6, 30), ("barrels", -4.6, -2.5, 0)])]
for base, u, v, yaw, eco in lane_houses:
    q = P(u, v)
    building(base, q[0], q[1], yaw, eco=eco)
# gardens and laundry between the lane houses and the river
for (u, v) in ((-34, -25), (-33, -39)):
    g = P(u, v)
    ground["gardens"].append({"center": g, "size": [7.0, 9.0], "yaw": 135})
    put("garden_bed", g[0], g[1], 135)
    put("fence_wattle", *(g + A * -4.0), -45)
q = P(-31, -32)
put("laundry", q[0], q[1], 45)
person("woman", "work", spot=P(-30.8, -33), anim="work", face_yaw=-45)
person("woodcutter", "work", spot=P(-11, -22.5), anim="work", face_yaw=-90)
person("builder", "walk", path=[P(-16, -8), P(-19, -22), P(-18, -36)])
for k in range(5):
    animal("chicken", "wander", P(-24 + k * 0.6, -33.5), 2.5)

# orchard on the bank west of the bridge
for i in range(4):
    for j in range(3):
        q = P(-40 + i * 6.0, -6 + j * 6.0) + rng.normal(0, 0.4, 2)
        if not wet(*q):
            tree(str(rng.choice(["fruit_a", "fruit_b", "fruit_c"])), q[0], q[1], rng.uniform(0.85, 1.0))
put("beehives", *P(-29, 7), 45)
put("haystack", *P(-28, -2))

# ================================================================================================
# 6. the water mill on the north bank, downstream of the bridge
MILL = np.array([1513.5, 1003.9])
mill_z = hz(*(MILL + np.array([0.0, -2.0])))
building("mill", MILL[0], MILL[1], -25, z=mill_z,
         eco=[("cart_goods", -6.5, 6.0, 90), ("sacks", -3.0, 5.2, 0), ("crates", 2.5, 5.0, 0)])
for f in range(8):
    sprites.add(yaw_name(f"mill_wheel_{f}", -25))
objects[-1]["wheel"] = [yaw_name(f"mill_wheel_{f}", -25) for f in range(8)]
ground["yards"].append({"center": MILL + local_to_world(0, 6.0, -25), "size": [16.0, 8.0], "yaw": -25})
mill_lane = [P(-14, 13), MILL + local_to_world(-2.0, 7.5, -25)]
ground["roads"].append({"kind": "rural", "width": 3.4, "points": [P(-13, 12), (P(-13, 12) + mill_lane[1]) / 2 + np.array([2, 1]), mill_lane[1]]})
deck = MILL + local_to_world(-2.0, -5.0, -25)
cart = MILL + local_to_world(-6.5, 6.0, -25)
person("farmer", "carry", path=[deck, MILL + local_to_world(-3.5, 4.0, -25), cart + np.array([1.0, 0.5])], speed=1.0)
person("builder", "carry", path=[cart + np.array([-0.5, 1.0]), MILL + local_to_world(-1.0, 4.5, -25), deck], speed=0.9,
       start=0.5)
person("artisan", "idle", spot=MILL + local_to_world(-4.0, -4.6, -25), face_yaw=180 - 25, anim="talk")
animal("horse", "idle", cart + local_to_world(3.4, 0.0, -25), 0.5, dirn="E")
put("reeds", *(MILL + local_to_world(7.5, -5.0, -25)))
put("rocks_bank", *(MILL + local_to_world(-9.5, -4.0, -25)), 0)
put("boat", *(MILL + local_to_world(-4.5, -8.6, -25)), -25)

# ================================================================================================
# 7. the smithy between the square and the mill
SM = P(5, 26)
building("smithy", SM[0], SM[1], -45, eco=[("tools_rack", -3.5, -3.6, 0), ("logs", -1.0, 4.5, 0)])
person("artisan", "work", spot=SM + local_to_world(5.6, -1.6, -45), anim="work", face_yaw=-45 + 90)
ground["trampled"].append({"center": SM + local_to_world(1.0, -3.5, -45), "size": [14.0, 6.0], "yaw": -45})

# ================================================================================================
# 8. military compound: barracks, stable, palisade, watchtower, training yard
YC = P(30, 26)
building("barracks", *P(46.5, 26), -45, eco=[("crates", 7.5, -2.5, 0), ("barrels", -8.0, -2.0, 0)])
building("stable", *P(31, 12.4), 45, eco=[("bales", 8.2, 1.0, 0)])
for k in range(3):
    q = P(22 + k * 8.0, 38.6)
    put("palisade", q[0], q[1], 45)
building("watchtower", *P(45.5, 39.5), -45)
fence_line = [P(18, 15.5), P(18, 37.5)]
d = fence_line[1] - fence_line[0]
for s in range(5):
    if s == 2:
        continue                               # the gate
    c = fence_line[0] + d * ((s + 0.5) / 5)
    put("fence", c[0], c[1], math.degrees(math.atan2(-d[1], d[0])))
put("banner_pole", *P(17.6, 24.0))
put("banner_pole", *P(17.6, 29.0))
for k, v in enumerate((20.5, 26.5, 32.5)):
    put("target", *P(41.0, v), -45)
for k, v in enumerate((19.0, 24.0, 29.0)):
    put("dummy", *P(33.0, v), -45)
put("weapon_rack", *P(23.0, 17.2), 45)
put("weapons_table", *P(27.0, 17.4), 45)
building("tent", *P(24.0, 33.5), -45)
put("crates", *P(28.5, 35.8), 45)
put("bales", *P(37.0, 15.0), 45)
ground["yards"].append({"center": YC, "size": [27.0, 24.0], "yaw": -45, "kind": "drill"})
# soldiers drilling in two ranks facing the dummies, a sergeant, archers' corner, guards at the gate
for r_ in range(2):
    for c_ in range(3):
        q = P(28.6 - r_ * 1.8, 19.5 + c_ * 4.8)
        person("soldier", "train", spot=q, face_yaw=135, anim="train", start=round((r_ * 3 + c_) / 6.0, 2))
person("guard", "idle", spot=P(31.5, 31.5), face_yaw=-45, anim="talk")
person("guard", "idle", spot=P(17.0, 26.0), face_yaw=-90 - 45, anim="idle")
person("guard", "idle", spot=P(17.0, 27.6), face_yaw=-90 - 45, anim="idle")
person("soldier", "walk", path=[P(20, 26.5), P(24, 26.5), P(26, 30), P(36, 32)], speed=1.1)
for k, (u, v) in enumerate(((26, 15.6), (29.5, 15.8), (34.5, 15.4))):
    animal("horse" if k != 1 else "horse_dark", "graze" if k != 1 else "idle", P(u, v), 0.5, dirn="SE")

# ================================================================================================
# 9. across the river: the farm, its fields, pig pen, chickens, orchard
FARM = BR_S + np.array([-30.0, 20.0])
building("house_farm", FARM[0], FARM[1], 45, eco=[("haystack", 6.5, 5.5, 0), ("cart_hay", -7.5, -2.5, 30),
                                                  ("coop", 4.5, -6.5, 0), ("firewood", -6.0, 3.5, 90)])
ground["yards"].append({"center": FARM + local_to_world(0, -4.0, 45), "size": [18.0, 10.0], "yaw": 45})
pen_c = FARM + local_to_world(-8.0, 7.5, 45)
pen = [pen_c + local_to_world(x_, y_, 45) for x_, y_ in ((-4, -3), (4, -3), (4, 3), (-4, 3))]
fence_poly(pen, gaps=(0,))
ground["mud"].append({"center": pen_c, "size": [8.0, 6.0], "yaw": 45})
put("trough", *(pen_c + local_to_world(0.0, 2.0, 45)), 45)
for k in range(3):
    animal("pig", "wander", pen_c + rng.normal(0, 0.8, 2), 2.2)
for k in range(6):
    animal("chicken", "wander", FARM + local_to_world(4.5, -8.5, 45) + rng.normal(0, 1.0, 2), 3.0)
person("woman", "work", spot=FARM + local_to_world(3.0, -9.0, 45), anim="work", face_yaw=0)
# fields (irregular, different crops) with workers, sheaves and a cart
F1 = [BR_S + np.array(p) for p in ((8, 14), (52, 6), (60, 40), (14, 52))]
F2 = [FARM + np.array(p) for p in ((-36, 18), (-6, 14), (-2, 46), (-34, 52))]
F3 = [FARM + np.array(p) for p in ((-40, -14), (-16, -18), (-14, 8), (-38, 12))]
ground["fields"].append({"crop": "wheat", "polygon": F1, "dir": 18.0})
ground["fields"].append({"crop": "plowed", "polygon": F2, "dir": 80.0})
ground["fields"].append({"crop": "veg", "polygon": F3, "dir": 5.0})
fence_poly(F1, gaps=(0, 2))
for k in range(4):
    q = BR_S + np.array([20.0 + k * 7.0, 22.0 + rng.uniform(-3, 6)])
    person("farmer", "work", spot=q, anim="work", face_yaw=rng.choice([-45, 45, 0]))
for q in (BR_S + np.array([44, 18]), BR_S + np.array([36, 34]), BR_S + np.array([24, 40])):
    put("haystack", q[0], q[1])
put("cart_hay", *(BR_S + np.array([10.0, 10.0])), 60)
animal("horse", "idle", BR_S + np.array([13.6, 8.6]), 0.4, dirn="E")
for k in range(3):
    animal("sheep", "graze", FARM + np.array([18.0 + k * 3, 30.0 + k]), 4.0)
animal("cow", "graze", FARM + np.array([26.0, 26.0]), 3.0)
for i in range(3):
    for j in range(3):
        q = FARM + np.array([-52 + i * 6.5, -2 + j * 6.5]) + rng.normal(0, 0.5, 2)
        tree(str(rng.choice(["fruit_a", "fruit_b", "fruit_c"])), q[0], q[1], rng.uniform(0.85, 1.0))
FROAD = [BR_S, BR_S + np.array([-6, 12]), FARM + local_to_world(2.0, -8.0, 45) + np.array([3, 0]), FARM + np.array([-26, 30]),
         FARM + np.array([-60, 46])]
ground["roads"].append({"kind": "rural", "width": 4.2, "points": FROAD})
ground["roads"].append({"kind": "path", "width": 2.0, "points": [BR_S + np.array([-2, 8]), BR_S + np.array([10, 18]),
                                                                  BR_S + np.array([24, 26]), BR_S + np.array([40, 30])]})

# ================================================================================================
# 10. traffic: people on the main street and the bridge, riverbank life
person("merchant", "carry", path=[BR_S + BR_DIR * -2, BR_N, MAIN[2], SQ_W + A * 3], speed=1.0)
person("farmer", "walk", path=[SQ_W + A * 2, MAIN[2], BR_N, BR_S, BR_S + np.array([-6, 12])], speed=1.15, start=0.3)
person("woman", "walk", path=[MAIN[2], BR_N, BR_S + np.array([0.0, 2.0])], speed=0.95, start=0.6)
person("citizen", "walk", path=[P(-13, 12), (P(-13, 12) + mill_lane[1]) / 2, mill_lane[1]], speed=1.0)
person("guard", "idle", spot=BR_N + np.array([2.2, -0.6]), face_yaw=-20, anim="idle")
put("lantern", *(BR_N + np.array([3.4, -1.2])))
put("signpost", *(BR_S + np.array([-3.5, 4.0])), 30)
put("rocks_bank", *(BR_C + np.array([-14.0, -4.0])), 0)
put("reeds", *(BR_C + np.array([-20.0, 7.0])))
put("reeds", *(BR_C + np.array([24.0, 12.0])))
put("lilypads", *(BR_C + np.array([-18.0, 2.0])))

# ================================================================================================
# trampled ground and greenery around every building (ecosystem rule)
for o in objects:
    if o["kind"] == "building" and not o["sprite"].startswith(("stall", "tent")):
        ground["trampled"].append({"center": [o["x"], o["y"]], "size": [14.0, 12.0], "yaw": 0, "soft": True})
for o in objects:
    if o["kind"] == "building" and o["sprite"].startswith("house"):
        for k in range(2):
            q = np.array([o["x"], o["y"]]) + rng.normal(0, 6.5, 2)
            veg.append({"type": str(rng.choice(["bush_a", "bush_c", "bush_d"])), "x": round(float(q[0]), 2),
                        "y": round(float(q[1]), 2), "scale": 0.8})

# ================================================================================================
# riverbanks (references B/C: boulders, reeds and bushes all along the water, not a bare edge)
# own rng, after every other random draw, so the rest of the layout does not move
brng = np.random.default_rng(77)


def near_bridge(q, m=5.0):
    d = q - BR_C
    return abs(d @ BR_DIR) < BR_LEN / 2 + 3.0 and abs(d @ np.array([-BR_DIR[1], BR_DIR[0]])) < m


def near_obj(q, m):
    return any((q[0] - o["x"]) ** 2 + (q[1] - o["y"]) ** 2 < m * m for o in objects)


for x in np.arange(BR_C[0] - 52.0, MILL[0] + 36.0, 3.2):
    col = [wet(x, y) for y in np.arange(BR_C[1] - 45.0, BR_C[1] + 45.0, 0.5)]
    ys = np.arange(BR_C[1] - 45.0, BR_C[1] + 45.0, 0.5)
    for i in range(1, len(col)):
        if col[i] == col[i - 1]:
            continue
        land = -1.0 if col[i] else 1.0                       # direction from the shore towards land (y)
        shore = np.array([x + brng.uniform(-1.2, 1.2), ys[i]])
        if near_bridge(shore) or np.linalg.norm(shore - MILL) < 14.0 or near_obj(shore, 2.5):
            continue
        r = brng.random()
        if r < 0.42:
            q = shore + np.array([0.0, land * brng.uniform(0.0, 1.2)])
            if brng.random() < 0.5:
                put("rocks_bank", q[0], q[1], 0)
            else:
                veg.append({"type": str(brng.choice(["rock_a", "rock_b", "rock_c", "rock_d"])), "x": round(float(q[0]), 2),
                            "y": round(float(q[1]), 2), "scale": round(float(brng.uniform(0.7, 1.1)), 2)})
        elif r < 0.64:
            q = shore + np.array([0.0, -land * brng.uniform(0.2, 0.9)])
            put("reeds", q[0], q[1])
        q = shore + np.array([brng.uniform(-1, 1), land * brng.uniform(2.5, 5.0)])
        if brng.random() < 0.45 and not near_obj(q, 3.0) and not near_bridge(q, 4.0):
            veg.append({"type": str(brng.choice(["bush_a", "bush_b", "bush_c", "bush_d"])), "x": round(float(q[0]), 2),
                        "y": round(float(q[1]), 2), "scale": round(float(brng.uniform(0.7, 1.0)), 2)})
        if brng.random() < 0.08 and not near_obj(q, 5.0) and not near_bridge(q, 6.0):
            veg.append({"type": str(brng.choice(["birch_a", "poplar_a", "oak_b"])), "x": round(float(q[0] + 1.5), 2),
                        "y": round(float(q[1] + land * 2.0), 2), "scale": 0.85})

# ================================================================================================
# district outline (for the countryside generator, vegetation masks and the ground painter)
pts = np.array([[o["x"], o["y"]] for o in objects] + [list(p) for f in ground["fields"] for p in f["polygon"]])
REGION = [float(pts[:, 0].min() - 26), float(pts[:, 1].min() - 26), float(pts[:, 0].max() + 26), float(pts[:, 1].max() + 26)]
EXITS = {"north": [float(v) for v in P(10, -30)], "west": [float(v) for v in FROAD[-1]],
         "east": [float(v) for v in P(48, 6)], "bridge_n": [float(v) for v in BR_N], "bridge_s": [float(v) for v in BR_S]}
ground["roads"].append({"kind": "rural", "width": 4.4, "points": [P(16, -12), P(14, -20), P(10, -30)]})
ground["roads"].append({"kind": "rural", "width": 4.0, "points": [P(16, 10), P(30, 11.0), P(40, 8), P(48, 6)]})


def clean(v):
    if isinstance(v, np.ndarray):
        return [round(float(x), 2) for x in v]
    if isinstance(v, (list, tuple)):
        return [clean(x) for x in v]
    if isinstance(v, dict):
        return {k: clean(x) for k, x in v.items()}
    if isinstance(v, (np.floating, float)):
        return round(float(v), 2)
    if isinstance(v, np.integer):
        return int(v)
    return v


out = {"name": "Altavera — quartiere del fiume", "region": REGION, "exits": EXITS, "grid_center": clean(M),
       "objects": objects, "people": clean(people), "animals": clean(animals), "ground": clean(ground), "veg": veg}
gd = os.path.join(K.GAME_DIR, "data", "valley")
with open(os.path.join(gd, "slice.json"), "w") as f:
    json.dump(out, f, indent=1)
with open(os.path.join(gd, "slice_sprites.json"), "w") as f:
    json.dump(sorted(sprites), f, indent=1)
print(f"objects {len(objects)}  people {len(people)}  animals {len(animals)}  veg {len(veg)}  sprites {len(sprites)}")
print("region", [round(v) for v in REGION])
print("sprites:", sorted(sprites))
