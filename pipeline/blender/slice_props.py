"""Phase 1B props: the small things that make a settlement alive (carts, barrels, crates, sacks, hay,
firewood, fences, low walls, garden beds, flowers, benches, troughs, wells, graves, lanterns, boats, reeds,
lily pads, stumps, beehives, laundry, chicken coop...).
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Vector

import kit2 as K2

ENTRIES = {}


def reg(name, seed=1):
    def deco(fn):
        ENTRIES[name] = (fn, seed)
        return fn
    return deco


def wheel(x, y, z, r=0.5, axis_y=True, mat=None):
    """Cart wheel: rim + spokes + hub, plane XZ (axle along Y)."""
    m = mat or K2.timber((96, 68, 44))
    objs = []
    n = 14
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        objs.append(K2.beam((x + math.cos(a0) * r, y, z + math.sin(a0) * r), (x + math.cos(a1) * r, y, z + math.sin(a1) * r),
                            0.08, m, size2=0.06))
    for k in range(6):
        a = math.pi * k / 3
        objs.append(K2.beam((x, y, z), (x + math.cos(a) * r, y, z + math.sin(a) * r), 0.045, m))
    objs.append(K2.cyl(0.1, 0.16, (x, y - 0.08, z), K2.iron(), verts=8, rot=(-math.pi / 2, 0, 0)))
    return objs


def cart(rng, load="hay"):
    objs = []
    wm = K2.planks((132, 96, 60), 0.2, False, 0.35)
    tm = K2.timber((100, 72, 46))
    L, W = 2.6, 1.4
    objs.append(K2.box(L, W, 0.1, (0, 0, 0.62), wm))
    for sy in (-1, 1):
        objs.append(K2.box(L, 0.08, 0.42, (0, sy * W / 2, 0.68), wm))
    objs.append(K2.box(0.08, W, 0.42, (-L / 2, 0, 0.68), wm))
    for sy in (-1, 1):
        objs += wheel(0.2, sy * (W / 2 + 0.12), 0.52, 0.52)
    objs.append(K2.box(L + 0.2, 0.08, 0.08, (0.1, 0, 0.5), tm))
    for sy in (-1, 1):
        objs.append(K2.beam((L / 2, sy * 0.35, 0.62), (L / 2 + 1.8, sy * 0.4, 0.15), 0.07, tm))
    if load == "hay":
        # heaped hay: overlapping lumps (irregular silhouette), loose straw fibres
        for k, (hx, hy, hz, sx, sy, sz) in enumerate(((0.0, 0.0, 1.05, 1.35, 0.82, 0.5), (-0.55, 0.12, 1.35, 0.75, 0.6, 0.4),
                                                       (0.5, -0.1, 1.3, 0.8, 0.62, 0.42), (0.05, 0.2, 1.55, 0.6, 0.45, 0.3))):
            objs.append(K2.shaggy(K2.sphere(1.0, (hx + rng.uniform(-0.05, 0.05), hy, hz), K2.straw("X"),
                                            scale=(sx, sy, sz), segs=18), 0.14, 0.18))
    elif load == "goods":
        objs += K2.barrel(-0.7, -0.3, 0.72, 0.28, 0.7)
        objs += K2.barrel(-0.7, 0.32, 0.72, 0.28, 0.7)
        objs += K2.crate(0.25, 0.0, 0.72, 0.62, 0.2)
        objs += K2.sack(0.85, -0.3, 0.72, 0.9)
        objs += K2.sack(0.85, 0.3, 0.72, 0.9, (176, 150, 110))
    elif load == "logs":
        for k in range(5):
            lg = K2.cyl(0.16, L + 0.4, (0, 0, 0), K2.flat((120, 86, 54), noise=0.2, scale=8), verts=8,
                        rot=(0, math.pi / 2, 0))
            lg.location = (-L / 2 - 0.2, -0.4 + (k % 3) * 0.38 + (0.19 if k >= 3 else 0), 0.86 + (0.3 if k >= 3 else 0))
            objs.append(lg)
    elif load == "stone":
        for k in range(5):
            objs.append(K2.box(0.55, 0.45, 0.35, (-0.8 + (k % 3) * 0.6, -0.25 + (k // 3) * 0.5, 0.72),
                               K2.stone((182, 172, 152), (150, 142, 128)), bevel=0.03, rot=(0, 0, rng.uniform(-0.2, 0.2))))
    return objs


@reg("cart_hay", 801)
def _c1(rng):
    return cart(rng, "hay"), (4.4, 1.8)


@reg("cart_goods", 802)
def _c2(rng):
    return cart(rng, "goods"), (4.4, 1.8)


@reg("cart_logs", 803)
def _c3(rng):
    return cart(rng, "logs"), (4.4, 1.8)


@reg("cart_stone", 804)
def _c4(rng):
    return cart(rng, "stone"), (4.4, 1.8)


@reg("wheelbarrow", 805)
def _wb(rng):
    objs = [K2.box(0.9, 0.6, 0.35, (0, 0, 0.35), K2.planks((128, 94, 60), 0.15, False, 0.3))]
    objs += wheel(0.55, 0, 0.25, 0.25)
    tm = K2.timber()
    for sy in (-1, 1):
        objs.append(K2.beam((0.45, sy * 0.22, 0.35), (-0.9, sy * 0.3, 0.55), 0.05, tm))
        objs.append(K2.beam((-0.3, sy * 0.25, 0.35), (-0.35, sy * 0.25, 0.0), 0.05, tm))
    objs.append(K2.sphere(0.32, (0, 0, 0.65), K2.flat((60, 52, 44), noise=0.3), scale=(1.2, 0.8, 0.45), segs=8))
    return objs, (1.6, 0.8)


@reg("barrels", 806)
def _barrels(rng):
    objs = []
    for (x, y, z) in ((0, 0, 0), (0.68, 0.1, 0), (0.3, 0.62, 0), (-0.55, 0.45, 0), (0.35, 0.3, 0.86)):
        objs += K2.barrel(x, y, z, rng=rng)
    return objs, (1.8, 1.6)


@reg("barrel", 807)
def _barrel(rng):
    return K2.barrel(0, 0, 0, rng=rng), (0.7, 0.7)


@reg("crates", 808)
def _crates(rng):
    objs = K2.crate(0, 0, 0, 0.75, 0.1) + K2.crate(0.8, 0.1, 0, 0.7, -0.15) + K2.crate(0.4, 0.05, 0.75, 0.62, 0.35)
    objs += K2.crate(-0.2, 0.75, 0, 0.6, 0.4)
    return objs, (1.8, 1.4)


@reg("sacks", 809)
def _sacks(rng):
    objs = []
    for k, (x, y, z) in enumerate(((0, 0, 0), (0.5, 0.1, 0), (0.25, 0.45, 0), (-0.4, 0.3, 0), (0.25, 0.15, 0.42))):
        objs += K2.sack(x, y, z, rng.uniform(0.9, 1.1), rng.choice([(200, 182, 140), (186, 164, 120), (210, 196, 160)]),
                        rng.uniform(0, 3))
    return objs, (1.4, 1.2)


@reg("haystack", 810)
def _haystack(rng):
    objs = [K2.shaggy(K2.cyl(1.4, 1.4, (0, 0, 0), K2.straw("Z"), verts=24, r2=1.25), 0.12, 0.2)]
    objs.append(K2.shaggy(K2.sphere(1.3, (0, 0, 1.35), K2.straw("Z"), scale=(1.0, 1.0, 0.95), segs=20), 0.12, 0.2))
    objs.append(K2.cyl(0.06, 0.8, (0, 0, 2.4), K2.timber(), verts=6))
    return objs, (2.8, 2.8)


@reg("bales", 811)
def _bales(rng):
    objs = []
    for (x, y, z, r) in ((0, 0, 0, 0.1), (1.05, 0.1, 0, -0.1), (0.5, 0.05, 0.5, 0.05), (0.2, 0.75, 0, 0.6)):
        objs.append(K2.box(1.0, 0.6, 0.5, (x, y, z), K2.straw("X"), rot=(0, 0, r), bevel=0.1))
        for k in (-0.25, 0.25):
            objs.append(K2.box(0.03, 0.62, 0.52, (x + k * math.cos(r), y + k * math.sin(r), z - 0.005),
                               K2.flat((64, 46, 28)), rot=(0, 0, r)))
    return objs, (2.2, 1.6)


@reg("firewood", 812)
def _fw(rng):
    objs = K2.woodpile(2.4, 1.1, 0.5, (0, 0, 0), 0.0, rng)
    for k in range(3):
        lg = K2.cyl(0.11, 0.55, (0, 0, 0), K2.flat((150, 112, 72), noise=0.2), verts=8, rot=(0, math.pi / 2, rng.uniform(0, 3)))
        lg.location = (-1.6 + k * 0.3, -0.7, 0.1)
        objs.append(lg)
    stump = K2.cyl(0.3, 0.45, (1.7, -0.6, 0), K2.flat((118, 86, 56), noise=0.2), verts=10)
    objs.append(stump)
    objs.append(K2.beam((1.7, -0.6, 0.45), (2.0, -0.95, 0.9), 0.04, K2.timber()))
    objs.append(K2.box(0.18, 0.04, 0.12, (2.0, -0.95, 0.85), K2.iron()))
    return objs, (3.4, 1.4)


@reg("logs", 813)
def _logs(rng):
    objs = []
    for k in range(6):
        row = 0 if k < 3 else (1 if k < 5 else 2)
        i = k if k < 3 else (k - 3 if k < 5 else 0)
        lg = K2.cyl(0.25, 4.0, (0, 0, 0), K2.flat((114, 82, 52), noise=0.2, scale=6), verts=10, rot=(0, math.pi / 2, 0))
        lg.location = (-2.0, -0.5 + i * 0.5 + row * 0.25, 0.25 + row * 0.43)
        objs.append(lg)
        for sx in (-2.0, 2.0):
            end = K2.cyl(0.23, 0.02, (0, 0, 0), K2.flat((182, 146, 100), noise=0.15), verts=10, rot=(0, math.pi / 2, 0))
            end.location = (sx - (0.01 if sx < 0 else -0.01) - (0.0 if sx < 0 else 0.02), lg.location[1], lg.location[2])
            objs.append(end)
    return objs, (4.2, 1.6)


@reg("planks", 814)
def _planks(rng):
    objs = []
    for k in range(8):
        objs.append(K2.box(3.2, 0.3, 0.05, (0, -0.3 + (k % 3) * 0.32, 0.12 + 0.06 * k), K2.planks((168, 128, 84), 0.3, False, 0.1),
                           rot=(0, 0, rng.uniform(-0.04, 0.04))))
    for x in (-1.2, 0.0, 1.2):
        objs.append(K2.box(0.12, 1.0, 0.12, (x, 0, 0), K2.timber()))
    return objs, (3.4, 1.2)


@reg("fence", 815)
def _fence(rng, L=4.0):
    """Post-and-rail fence segment along X (thick posts, two split rails)."""
    objs = []
    tm = K2.timber((112, 82, 52))
    rm = K2.planks((128, 96, 64), 0.2, False, 0.4)
    for x in (-L / 2, 0.0, L / 2):
        objs.append(K2.box(0.16, 0.16, 1.15 + rng.uniform(-0.05, 0.05), (x, 0, 0), tm, rot=(0, 0, rng.uniform(-0.2, 0.2))))
    for z in (0.45, 0.88):
        r = K2.box(L + 0.2, 0.09, 0.13, (0, 0.02, z + rng.uniform(-0.03, 0.03)), rm)
        r.rotation_euler = (0, rng.uniform(-0.015, 0.015), 0)
        objs.append(r)
    return objs, (L, 0.3)


@reg("fence_wattle", 816)
def _wattle(rng, L=4.0):
    objs = []
    tm = K2.timber((112, 82, 52))
    for k in range(9):
        objs.append(K2.box(0.06, 0.06, 1.0, (-L / 2 + k * L / 8, 0, 0), tm))
    wm = K2.planks((140, 110, 72), 0.06, False, 0.3)
    for z in range(9):
        objs.append(K2.box(L, 0.06, 0.09, (0, 0.02 * (1 if z % 2 else -1), 0.08 + z * 0.1), wm))
    return objs, (L, 0.2)


@reg("wall_low", 817)
def _wall(rng, L=4.0):
    st = K2.stone((176, 166, 146), (134, 128, 118), (96, 88, 76), 0.4, 0.26)
    objs = [K2.box(L, 0.55, 0.85, (0, 0, 0), st, bevel=0.05)]
    for k in range(int(L / 0.6)):
        objs.append(K2.box(0.58, 0.62, 0.14, (-L / 2 + 0.3 + k * 0.6, 0, 0.85), K2.stone((170, 160, 140), (140, 132, 120)),
                           bevel=0.03, rot=(0, 0, rng.uniform(-0.04, 0.04))))
    objs.append(K2.sphere(0.4, (L / 2 - 0.4, -0.2, 0.9), K2.flat((70, 108, 48), noise=0.25), scale=(1.2, 0.8, 0.6), segs=8))
    return objs, (L, 0.6)


def cabbage(x, y, s=1.0, col=(98, 150, 70)):
    o = K2.sphere(0.2 * s, (x, y, 0.12 * s), K2.flat(col, noise=0.25, scale=10), scale=(1, 1, 0.75), segs=8)
    return [o]


@reg("garden_bed", 818)
def _garden(rng):
    """Vegetable plot: raised earth beds with rows of cabbages, leeks, carrots + a low wattle border."""
    objs = []
    W, D = 5.0, 3.6
    soil = K2.flat((96, 70, 46), noise=0.25, scale=6, rough=1.0)
    for k in range(4):
        y = -D / 2 + 0.45 + k * 0.9
        objs.append(K2.box(W - 0.6, 0.6, 0.18, (0, y, 0), soil, bevel=0.05))
        kind = k % 3
        for i in range(9):
            x = -W / 2 + 0.6 + i * (W - 1.2) / 8 + rng.uniform(-0.05, 0.05)
            if kind == 0:
                objs += cabbage(x, y, rng.uniform(0.9, 1.15))
                for o in objs[-1:]:
                    o.location = (o.location[0], o.location[1], o.location[2] + 0.17)
            elif kind == 1:
                for j in (-0.12, 0.12):
                    objs.append(K2.cyl(0.04, 0.4, (x, y + j, 0.18), K2.flat((120, 170, 80), noise=0.2), verts=5, r2=0.01))
            else:
                objs.append(K2.sphere(0.11, (x, y, 0.3), K2.flat((80, 140, 56), noise=0.3), scale=(1, 1, 1.4), segs=6))
    for sx in (-1, 1):
        objs.append(K2.box(0.06, D, 0.45, (sx * W / 2, 0, 0), K2.planks((140, 110, 72), 0.06, False, 0.3)))
    objs.append(K2.box(W, 0.06, 0.45, (0, -D / 2, 0), K2.planks((140, 110, 72), 0.06, False, 0.3)))
    return objs, (W, D)


@reg("flowers", 819)
def _flowers(rng):
    objs = []
    for k in range(9):
        x, y = rng.uniform(-0.9, 0.9), rng.uniform(-0.5, 0.5)
        objs.append(K2.sphere(rng.uniform(0.25, 0.38), (x, y, 0.2), K2.flat((64, 104, 44), noise=0.3, scale=8),
                              scale=(1, 1, 0.8), segs=8))
        col = rng.choice([(222, 92, 140), (236, 196, 72), (220, 70, 60), (240, 236, 224), (170, 120, 220)])
        for j in range(5):
            objs.append(K2.sphere(0.07, (x + rng.uniform(-0.25, 0.25), y + rng.uniform(-0.25, 0.25), 0.42 + rng.uniform(0, 0.1)),
                                  K2.flat(col, noise=0.1), segs=5))
    return objs, (2.0, 1.2)


@reg("rosebush", 820)
def _rose(rng):
    objs = []
    for k in range(5):
        objs.append(K2.sphere(rng.uniform(0.4, 0.55), (rng.uniform(-0.5, 0.5), rng.uniform(-0.3, 0.3), 0.5 + rng.uniform(0, 0.3)),
                              K2.flat((60, 100, 46), noise=0.3, scale=8), segs=8))
    col = rng.choice([(226, 112, 160), (232, 140, 176)])
    for k in range(26):
        a = rng.uniform(0, 6.28)
        r = rng.uniform(0.2, 0.7)
        objs.append(K2.sphere(0.08, (math.cos(a) * r, math.sin(a) * r * 0.7, 0.55 + rng.uniform(0, 0.55)), K2.flat(col, noise=0.1),
                              segs=5))
    return objs, (1.6, 1.2)


@reg("sunflowers", 821)
def _sun(rng):
    objs = []
    for k in range(7):
        x, y = rng.uniform(-0.8, 0.8), rng.uniform(-0.4, 0.4)
        h = rng.uniform(1.5, 2.1)
        objs.append(K2.cyl(0.03, h, (x, y, 0), K2.flat((80, 120, 50)), verts=5))
        for j in range(3):
            objs.append(K2.sphere(0.13, (x + rng.uniform(-0.1, 0.1), y, h * (0.3 + 0.2 * j)), K2.flat((70, 112, 46), noise=0.2),
                                  scale=(1.4, 0.6, 0.5), segs=6))
        f = K2.cyl(0.22, 0.05, (x, y - 0.05, h), K2.flat((240, 196, 40), noise=0.1), verts=12, rot=(1.2, 0, 0))
        objs.append(f)
        c = K2.cyl(0.1, 0.07, (x, y - 0.08, h), K2.flat((90, 60, 30), noise=0.2), verts=10, rot=(1.2, 0, 0))
        objs.append(c)
    return objs, (1.8, 1.0)


@reg("bench", 822)
def _bench(rng):
    objs = [K2.box(1.8, 0.4, 0.08, (0, 0, 0.45), K2.planks((136, 100, 64), 0.4, False, 0.3))]
    for sx in (-0.7, 0.7):
        objs.append(K2.box(0.08, 0.35, 0.45, (sx, 0, 0), K2.timber()))
    return objs, (1.8, 0.5)


@reg("trough", 823)
def _trough(rng):
    objs = [K2.box(2.0, 0.7, 0.55, (0, 0, 0), K2.planks((118, 86, 56), 0.2, False, 0.4))]
    objs.append(K2.box(1.85, 0.55, 0.04, (0, 0, 0.48), K2.flat((60, 96, 110), rough=0.1, noise=0.05, ao=0.8)))
    return objs, (2.0, 0.8)


@reg("well", 824)
def _well(rng):
    st = K2.stone((172, 162, 144), (132, 126, 116), (92, 86, 76), 0.36, 0.24)
    objs = [K2.cyl(0.95, 0.85, (0, 0, 0), st, verts=18)]
    objs.append(K2.cyl(0.72, 0.02, (0, 0, 0.84), K2.flat((20, 26, 30), noise=0.0), verts=18))
    tm = K2.timber()
    for sx in (-1, 1):
        objs.append(K2.box(0.14, 0.14, 2.1, (sx * 0.85, 0, 0), tm))
    objs.append(K2.cyl(0.1, 1.9, (-0.95, 0, 1.6), tm, verts=8, rot=(0, math.pi / 2, 0)))
    rng2 = random.Random(5)
    roof = K2.gable_roof(1.7, 1.4, 2.0, 40, "shingle", rng2, overhang=0.2, gable_over=0.15)[0]
    objs += roof
    objs += K2.barrel(0.0, -0.3, 0.85, 0.16, 0.3)
    return objs, (2.2, 2.0)


@reg("grave_cross", 825)
def _gc(rng):
    st = K2.rock((184, 178, 164), (140, 136, 126), (128, 134, 84))
    objs = [K2.box(0.14, 0.12, 1.0, (0, 0, 0), st, bevel=0.02), K2.box(0.55, 0.12, 0.12, (0, 0, 0.7), st, bevel=0.02)]
    # low grave mound: turned earth with grass growing over it
    objs.append(K2.sphere(1.0, (0, 0.75, -0.02), K2.flat((104, 98, 62), noise=0.35, scale=9), scale=(0.36, 0.78, 0.14), segs=12))
    return objs, (0.8, 1.8)


@reg("grave_stone", 826)
def _gs(rng):
    st = K2.rock((176, 170, 158), (132, 128, 120), (124, 130, 82))
    o = K2.box(0.6, 0.16, 0.75, (0, 0, 0), st, bevel=0.05)
    o.rotation_euler = (rng.uniform(-0.08, 0.08), rng.uniform(-0.06, 0.06), 0)
    objs = [o, K2.sphere(0.3, (0, 0, 0.75), st, scale=(1, 0.27, 0.6), segs=10)]
    objs.append(K2.sphere(1.0, (0, 0.7, -0.02), K2.flat((104, 98, 62), noise=0.35, scale=9), scale=(0.34, 0.72, 0.12), segs=12))
    objs.append(K2.sphere(0.12, (0.2, 0.3, 0.06), K2.flat((222, 210, 120), noise=0.2), segs=5))
    return objs, (0.8, 1.6)


@reg("lantern", 827)
def _lantern(rng):
    objs = [K2.box(0.14, 0.14, 2.6, (0, 0, 0), K2.timber()), K2.box(0.6, 0.08, 0.08, (0.25, 0, 2.5), K2.timber())]
    objs.append(K2.box(0.24, 0.24, 0.32, (0.5, 0, 2.1), K2.flat((255, 200, 110), emission=((255, 180, 90), 3.0))))
    objs.append(K2.cyl(0.18, 0.14, (0.5, 0, 2.42), K2.iron(), verts=4, r2=0.02))
    return objs, (0.8, 0.4)


@reg("signpost", 828)
def _sign(rng):
    objs = [K2.box(0.12, 0.12, 2.2, (0, 0, 0), K2.timber())]
    for k, a in enumerate((0.4, -0.5)):
        b = K2.box(0.9, 0.05, 0.2, (0.35 * math.cos(a), 0.35 * math.sin(a), 1.7 - 0.3 * k), K2.planks((150, 112, 72), 0.2, False, 0.2))
        b.rotation_euler = (0, 0, a)
        objs.append(b)
    return objs, (1.0, 0.6)


@reg("boat", 829)
def _boat(rng):
    bm = bmesh.new()
    L, W, H = 3.6, 1.2, 0.5
    prof = []
    n = 10
    for i in range(n + 1):
        t = i / n
        x = -L / 2 + L * t
        hw = W / 2 * math.sin(math.pi * min(1, max(0.0, t * 1.15 - 0.05))) ** 0.6
        prof.append((x, hw))
    top = [bm.verts.new((x, -hw, H)) for x, hw in prof] + [bm.verts.new((x, hw, H)) for x, hw in reversed(prof)]
    bot = [bm.verts.new((x, -hw * 0.6, 0.02)) for x, hw in prof] + [bm.verts.new((x, hw * 0.6, 0.02)) for x, hw in reversed(prof)]
    m = len(top)
    for i in range(m):
        j = (i + 1) % m
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bm.faces.new(bot[::-1])
    o = K2.link_obj(bm, "hull", K2.planks((120, 86, 54), 0.12, False, 0.4))
    sol = o.modifiers.new("s", "SOLIDIFY")
    sol.thickness = 0.05
    objs = [o]
    for x in (-0.6, 0.5):
        objs.append(K2.box(0.25, W * 0.85, 0.05, (x, 0, H - 0.12), K2.planks((140, 104, 66), 0.12, False, 0.3)))
    objs.append(K2.beam((0.2, 0.2, H), (1.6, 0.9, 0.2), 0.04, K2.timber()))
    objs.append(K2.beam((0.0, -0.3, H), (-0.8, -1.2, 0.25), 0.04, K2.timber()))
    return objs, (3.6, 1.2)


@reg("reeds", 830)
def _reeds(rng):
    objs = []
    for k in range(40):
        x, y = rng.gauss(0, 0.6), rng.gauss(0, 0.35)
        h = rng.uniform(0.8, 1.6)
        b = K2.cyl(0.025, h, (x, y, 0), K2.flat(rng.choice([(96, 130, 60), (120, 150, 70), (130, 140, 70)]), noise=0.2), verts=4,
                   r2=0.005)
        b.rotation_euler = (rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 0)
        objs.append(b)
        if rng.random() < 0.25:
            objs.append(K2.cyl(0.045, 0.22, (x, y, h * 0.75), K2.flat((96, 62, 36), noise=0.1), verts=6))
    return objs, (1.6, 1.0)


@reg("lilypads", 831)
def _lily(rng):
    objs = []
    for k in range(12):
        x, y = rng.gauss(0, 0.8), rng.gauss(0, 0.5)
        r = rng.uniform(0.14, 0.26)
        objs.append(K2.cyl(r, 0.02, (x, y, 0.0), K2.flat((84, 130, 60), noise=0.2), verts=10))
        if rng.random() < 0.3:
            objs.append(K2.sphere(0.06, (x, y, 0.06), K2.flat((240, 220, 230), noise=0.1), segs=5))
    return objs, (1.6, 1.0)


@reg("stump", 832)
def _stump(rng):
    objs = [K2.cyl(0.38, 0.5, (0, 0, 0), K2.flat((104, 76, 50), noise=0.25, scale=6), verts=10)]
    objs.append(K2.cyl(0.36, 0.02, (0, 0, 0.5), K2.flat((176, 140, 96), noise=0.15), verts=10))
    for k in range(4):
        a = k * 1.6
        objs.append(K2.beam((0, 0, 0.12), (math.cos(a) * 0.7, math.sin(a) * 0.7, 0.0), 0.12, K2.flat((98, 72, 48), noise=0.2)))
    return objs, (1.0, 1.0)


@reg("beehives", 833)
def _bee(rng):
    objs = []
    for k in range(3):
        x = -1.0 + k * 1.0
        objs.append(K2.box(0.7, 0.6, 0.35, (x, 0, 0), K2.timber()))
        objs.append(K2.cyl(0.32, 0.65, (x, 0, 0.35), K2.straw("X"), verts=12, r2=0.12))
    return objs, (3.0, 0.8)


@reg("laundry", 834)
def _laundry(rng):
    objs = []
    for x in (-1.6, 1.6):
        objs.append(K2.box(0.1, 0.1, 2.0, (x, 0, 0), K2.timber()))
    objs.append(K2.box(3.2, 0.02, 0.02, (0, 0, 1.9), K2.flat((200, 190, 160))))
    for k, col in enumerate([(232, 228, 214), (120, 150, 190), (196, 70, 60), (232, 228, 214), (200, 170, 100)]):
        objs.append(K2.box(rng.uniform(0.4, 0.6), 0.03, rng.uniform(0.5, 0.8), (-1.2 + k * 0.6, 0, 1.15), K2.cloth(col)))
    return objs, (3.4, 0.4)


@reg("coop", 835)
def _coop(rng):
    objs = [K2.box(1.6, 1.2, 1.0, (0, 0, 0.4), K2.planks((130, 96, 62), 0.18, True, 0.4))]
    for sx in (-1, 1):
        for sy in (-1, 1):
            objs.append(K2.box(0.1, 0.1, 0.45, (sx * 0.7, sy * 0.5, 0), K2.timber()))
    objs += K2.gable_roof(1.6, 1.2, 1.4, 38, "shingle", random.Random(3), overhang=0.2, gable_over=0.1)[0]
    objs.append(K2.beam((0.3, -0.6, 0.45), (0.3, -1.3, 0.0), 0.2, K2.planks((140, 104, 66), 0.1, False, 0.2), size2=0.04))
    return objs, (1.8, 1.6)


@reg("pottery", 836)
def _pot(rng):
    objs = []
    for k in range(5):
        r = rng.uniform(0.12, 0.22)
        objs.append(K2.cyl(r, r * 2.4, (rng.uniform(-0.5, 0.5), rng.uniform(-0.3, 0.3), 0),
                           K2.flat(rng.choice([(176, 104, 66), (150, 118, 86), (190, 160, 120)]), noise=0.15), verts=12, r2=r * 0.55))
    for k in range(2):
        objs.append(K2.cyl(0.26, 0.3, (rng.uniform(-0.4, 0.4), 0.5, 0), K2.planks((168, 128, 80), 0.06, True, 0.2), verts=12,
                           r2=0.32))
    return objs, (1.2, 1.0)


@reg("rocks_bank", 837)
def _rb(rng):
    objs = []
    st = K2.rock()
    for k in range(6):
        r = rng.uniform(0.45, 1.05)
        o = K2.sphere(r, (rng.uniform(-1.4, 1.4), rng.uniform(-0.6, 0.6), r * 0.35), st,
                      scale=(rng.uniform(1.0, 1.4), rng.uniform(0.8, 1.1), rng.uniform(0.6, 0.9)), segs=7)
        for poly in o.data.polygons:
            poly.use_smooth = False
        o.rotation_euler = (rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), rng.uniform(0, 3))
        objs.append(o)
    for k in range(4):
        objs.append(K2.sphere(0.25, (rng.uniform(-1.5, 1.5), rng.uniform(-0.6, 0.6), 0.25), K2.flat((80, 116, 50), noise=0.3),
                              scale=(1.2, 1.0, 0.8), segs=6))
    return objs, (3.2, 1.6)


@reg("anvil_set", 838)
def _anvil(rng):
    objs = [K2.cyl(0.3, 0.6, (0, 0, 0), K2.timber((104, 76, 50)), verts=10)]
    objs.append(K2.box(0.7, 0.26, 0.26, (0, 0, 0.6), K2.iron(), bevel=0.03))
    return objs, (0.8, 0.6)


@reg("tools_rack", 839)
def _tools(rng):
    objs = [K2.box(0.1, 0.1, 1.6, (-0.7, 0, 0), K2.timber()), K2.box(0.1, 0.1, 1.6, (0.7, 0, 0), K2.timber()),
            K2.box(1.5, 0.08, 0.1, (0, 0, 1.4), K2.timber())]
    for k in range(5):
        x = -0.55 + k * 0.28
        objs.append(K2.beam((x, 0.05, 1.4), (x + 0.1, -0.2, 0.05), 0.035, K2.timber((150, 116, 76))))
        objs.append(K2.box(0.2, 0.03, 0.14, (x + 0.1, -0.22, 0.02), K2.iron()))
    return objs, (1.6, 0.5)
