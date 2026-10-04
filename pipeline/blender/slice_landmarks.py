"""Phase 1B landmark buildings: church, water mill (+ animated wheel), stone bridge, market stalls and
fountain, barracks and training yard pieces, watchtower, stable, smithy.

Every builder returns (objects, footprint (w, d)[, extra metadata]). Local frame: origin = ground centre,
facade towards -Y (south) at yaw 0.
"""
from __future__ import annotations

import math
import os
import random
import tempfile

import bmesh
import bpy
from mathutils import Vector
from PIL import Image, ImageDraw

import kit2 as K2

ENTRIES = {}


def reg(name, seed=1, **extra):
    def deco(fn):
        ENTRIES[name] = (fn, seed)
        return fn
    return deco


# ------------------------------------------------------------------------------------------------
# heraldry: red banner with a white lion rampant (procedural drawing -> image texture)
def _banner_image(kind="lion"):
    path = os.path.join(tempfile.gettempdir(), f"kd_banner_{kind}.png")
    if os.path.exists(path):
        return path
    W, H = 160, 320
    im = Image.new("RGB", (W, H), (150, 28, 30))
    d = ImageDraw.Draw(im)
    gold = (214, 172, 74)
    d.rectangle([4, 4, W - 5, H - 5], outline=gold, width=5)
    # swallow-tail bottom drawn by the mesh; lion rampant (stylised silhouette)
    white = (236, 230, 216)
    cx, cy = 80, 150
    d.ellipse([cx - 26, cy - 40, cx + 22, cy + 38], fill=white)                    # body
    d.ellipse([cx - 6, cy - 86, cx + 34, cy - 46], fill=white)                     # head + mane
    d.polygon([(cx + 30, cy - 70), (cx + 46, cy - 62), (cx + 32, cy - 56)], fill=white)   # snout
    d.polygon([(cx + 10, cy - 40), (cx + 50, cy - 60), (cx + 56, cy - 50), (cx + 18, cy - 24)], fill=white)  # paw
    d.polygon([(cx + 6, cy - 14), (cx + 52, cy - 20), (cx + 54, cy - 10), (cx + 10, cy + 2)], fill=white)    # paw
    d.polygon([(cx - 14, cy + 30), (cx - 2, cy + 30), (cx + 18, cy + 92), (cx + 6, cy + 96)], fill=white)   # leg
    d.polygon([(cx + 6, cy + 24), (cx + 18, cy + 24), (cx + 42, cy + 80), (cx + 30, cy + 86)], fill=white)  # leg
    d.line([(cx - 22, cy + 20), (cx - 50, cy - 10), (cx - 46, cy - 60), (cx - 30, cy - 70)], fill=white, width=7)
    d.ellipse([cx - 40, cy - 80, cx - 22, cy - 62], fill=white)                    # tail tuft
    d.ellipse([cx + 14, cy - 76, cx + 20, cy - 70], fill=(150, 28, 30))            # eye
    im.save(path)
    return path


def banner_mat(kind="lion"):
    key = "banner_" + kind
    if key in K2._M:
        return K2._M[key]
    g = K2.G(key)
    tex = g.n("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(_banner_image(kind))
    tex.interpolation = "Cubic"
    g.link(g.coords("UV"), tex.inputs["Vector"])
    m = g.finish(tex.outputs["Color"], ao_dark=0.6, rough=0.95)
    K2._M[key] = m
    return m


def banner(x, y, z_top, w=0.8, h=1.6, face="S", wave=0.06, kind="lion"):
    """Hanging banner (swallow-tailed) on the facade, UV-mapped to the heraldry image."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    nu, nv = 6, 10
    verts = []
    for j in range(nv + 1):
        row = []
        for i in range(nu + 1):
            u = i / nu
            v = j / nv
            px = (u - 0.5) * w
            pz = z_top - v * h
            if v == 1.0:
                pz += 0.25 * h * (1 - abs(u - 0.5) * 2)          # swallow tail notch
            off = wave * math.sin(u * 3.0 + v * 2.0)
            if face == "S":
                p = (x + px, y - 0.05 - off, pz)
            elif face == "N":
                p = (x - px, y + 0.05 + off, pz)
            elif face == "E":
                p = (x + 0.05 + off, y + px, pz)
            else:
                p = (x - 0.05 - off, y - px, pz)
            row.append(bm.verts.new(p))
        verts.append(row)
    for j in range(nv):
        for i in range(nu):
            f = bm.faces.new((verts[j + 1][i], verts[j + 1][i + 1], verts[j][i + 1], verts[j][i]))
            for loop, (uu, vv) in zip(f.loops, ((i, j + 1), (i + 1, j + 1), (i + 1, j), (i, j))):
                loop[uvl].uv = (uu / nu, 1 - vv / nv)
    o = K2.link_obj(bm, "banner", banner_mat(kind))
    rod = K2.cyl(0.04, w + 0.3, (0, 0, 0), K2.timber(), verts=6, rot=(0, math.pi / 2, 0))
    if face in "SN":
        rod.location = (x - (w + 0.3) / 2, y + (-0.12 if face == "S" else 0.12), z_top + 0.05)
    else:
        rod.rotation_euler = (math.pi / 2, 0, 0)
        rod.location = (x + (0.12 if face == "E" else -0.12), y - (w + 0.3) / 2, z_top + 0.05)
    return [o, rod]


def pointed_window(face, u, z, w, d, ww=0.8, wh=2.4, mat=None, frame=None):
    """Gothic lancet: dark glass prism with a pointed top + stone frame."""
    base, out, side = K2._place(face, u, w, d)
    rot = math.atan2(out.x, -out.y)
    pts = []
    for k in range(9):
        t = k / 8
        a = math.pi * t
        pts.append((-ww / 2 * math.cos(a), wh + ww * 0.55 * math.sin(a) * (1 - 0.0)))
    poly = [(-ww / 2, 0)] + [(px, pz - (ww * 0.55 * 0) if False else pz) for px, pz in pts] + [(ww / 2, 0)]
    bm = bmesh.new()
    th = 0.16
    a = [bm.verts.new((px, -th / 2, pz)) for px, pz in poly]
    b = [bm.verts.new((px, th / 2, pz)) for px, pz in poly]
    bm.faces.new(a[::-1])
    bm.faces.new(b)
    for i in range(len(poly)):
        j = (i + 1) % len(poly)
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    g = K2.link_obj(bm, "lancet", K2.dark_glass())
    g.location = base + Vector((0, 0, z)) + out * 0.04
    g.rotation_euler = (0, 0, rot)
    objs = [g]
    fm = frame or K2.stone((182, 170, 150), (150, 140, 124), (110, 100, 86), 0.3, 0.25)
    objs.append(K2.box(ww + 0.4, 0.22, 0.18, base + out * 0.08 + Vector((0, 0, z - 0.18)), fm, rot=(0, 0, rot)))
    for s_ in (-1, 1):
        objs.append(K2.box(0.18, 0.2, wh, base + out * 0.08 + side * s_ * (ww / 2 + 0.09) + Vector((0, 0, z)), fm,
                           rot=(0, 0, rot)))
    objs.append(K2.box(0.06, 0.08, wh + ww * 0.4, base + out * 0.1 + Vector((0, 0, z)), K2.iron(), rot=(0, 0, rot)))
    return objs


# ------------------------------------------------------------------------------------------------
@reg("church", 701)
def church(rng):
    W, D, Hw = 9.0, 17.0, 7.6
    st = K2.stone((186, 172, 148), (140, 132, 120), (104, 96, 84), 0.5, 0.32)
    dk = K2.stone((150, 140, 126), (118, 112, 104), (84, 78, 70), 0.5, 0.32)
    objs = [K2.box(W + 0.6, D + 0.6, 0.6, (0, 0, -0.1), dk, name="plinth")]
    objs.append(K2.box(W, D, Hw, (0, 0, 0.4), st, name="nave"))
    robjs, zr = K2.gable_roof(W, D, Hw + 0.4, 52, "slate", rng, overhang=0.45, gable_over=0.25, ridge_x=False)
    objs += robjs
    rise = math.tan(math.radians(52)) * W / 2
    for sy in (-1, 1):
        objs.append(K2.gable_wall(W, Hw + 0.4, rise, st, thick=0.4, y=sy * (D / 2 - 0.15), axis="x"))
    # buttresses and lancets along the sides
    for k, y in enumerate((-5.6, -1.9, 1.9, 5.6)):
        for sx in (-1, 1):
            objs.append(K2.box(0.9, 1.0, 5.6, (sx * (W / 2 + 0.4), y, 0.4), dk))
            objs.append(K2.box(0.7, 0.8, 1.2, (sx * (W / 2 + 0.3), y, 6.0), dk))
    for y in (-3.75, 0.0, 3.75):
        for f in "EW":
            objs += pointed_window(f, y, 2.6, W, D, ww=0.9, wh=2.6)
    # facade: portal, rose window, steps
    objs += pointed_window("S", 0.0, 0.4, W, D, ww=1.9, wh=2.6,
                           frame=K2.stone((196, 184, 162), (160, 150, 132), (120, 110, 96), 0.3, 0.25))
    objs.append(K2.box(1.8, 0.2, 2.5, (0, -D / 2 - 0.12, 0.4), K2.planks((96, 62, 36), 0.18, True, 0.1)))
    rose = K2.cyl(1.0, 0.25, (0, -D / 2 - 0.05, 0), K2.dark_glass(), verts=24, rot=(math.pi / 2, 0, 0))
    rose.location = (0, -D / 2 - 0.05, 5.6)
    objs.append(rose)
    ring = K2.cyl(1.22, 0.2, (0, 0, 0), K2.stone((196, 184, 162), (160, 150, 132)), verts=24, rot=(math.pi / 2, 0, 0))
    ring.location = (0, -D / 2 + 0.02, 5.6)
    objs.append(ring)
    for k in range(3):
        objs.append(K2.box(3.6 - k * 0.5, 0.6, 0.2, (0, -D / 2 - 1.4 + k * 0.45, 0.2 * k), K2.paving()))
    # apse
    objs.append(K2.cyl(3.4, 6.2, (0, D / 2, 0.4), st, verts=28, name="apse"))
    objs += K2.cone_roof(3.4, 3.2, 6.6, "slate", rng, overhang=0.35)
    for ob in objs[-2:]:
        ob.location = (ob.location[0], ob.location[1] + D / 2, ob.location[2])
    # bell tower at the south-west corner, pyramid spire
    tx, ty, T, TH = -W / 2 - 1.3, -D / 2 + 2.6, 4.6, 17.5
    objs.append(K2.box(T, T, TH, (tx, ty, -0.1), dk, name="tower"))
    for z in (TH - 4.6, TH - 0.2):
        objs.append(K2.box(T + 0.36, T + 0.36, 0.35, (tx, ty, z), st))
    for f in "SWEN":
        objs += pointed_window(f, 0.0, TH - 3.9, T, T, ww=0.9, wh=1.9)
        for ob in objs[-5:]:
            ob.location = (ob.location[0] + tx, ob.location[1] + ty, ob.location[2])
    objs += pointed_window("S", 0.0, 6.0, T, T, ww=0.5, wh=1.2)
    for ob in objs[-5:]:
        ob.location = (ob.location[0] + tx, ob.location[1] + ty, ob.location[2])
    sp = K2.cone_roof(T / 2 * 1.38, 8.0, TH + 0.15, "slate", rng, overhang=0.1, segs=4)
    for ob in sp:
        ob.location = (ob.location[0] + tx, ob.location[1] + ty, ob.location[2])
    objs += sp
    objs.append(K2.box(0.14, 0.14, 1.8, (tx, ty, TH + 8.0), K2.iron()))
    objs.append(K2.box(0.9, 0.14, 0.14, (tx, ty, TH + 9.2), K2.iron()))
    return objs, (14.0, 22.0)


# ------------------------------------------------------------------------------------------------
WATER_Z = -1.55          # river surface below the bank top (mill and bridge sit on the bank)


def water_plane(x0, x1, y0, y1, z=WATER_Z + 0.02):
    """Holdout-free stand-in: nothing (the river is drawn by the terrain); kept for piles' depth reference."""
    return []


def mill_body(rng):
    w, d = 9.0, 7.0
    objs = []
    st = K2.stone((172, 160, 140), (126, 120, 112), (90, 82, 70))
    objs.append(K2.box(w + 0.2, d + 0.2, 0.4, (0, 0, -0.1), st))
    objs.append(K2.box(w, d, 2.9, (0, 0, 0.3), st, name="mill_ground"))
    objs.append(K2.box(w, d, 2.6, (0, 0, 3.2), K2.plaster((226, 214, 188))))
    objs += K2.timber_frame(w, d, 3.2, 2.6, rng, pattern="brace")
    robjs, zr = K2.gable_roof(w, d, 5.8, 44, "shingle", rng, overhang=0.55, gable_over=0.4)
    objs += robjs
    rise = math.tan(math.radians(44)) * d / 2
    for sx in (-1, 1):
        objs.append(K2.gable_wall(d, 5.8, rise, K2.planks((124, 92, 60), 0.24, True, 0.3), thick=0.3,
                                  x=sx * (w / 2 - 0.12), axis="y"))
    for f, us in (("S", (-2.8, 0.2)), ("N", (-2.0, 2.0)), ("W", (0.0,)), ("E", (-1.5, 1.5))):
        for u in us:
            objs += K2.window(f, u, 1.3, w, d, ww=0.7, wh=0.9, frame_mat=st)
            objs += K2.window(f, u, 3.9, w, d, ww=0.7, wh=0.85)
    objs += K2.door("S", -1.3, w, d, dw=1.5, dh=2.3, stone_frame=True, step=False)
    objs += K2.door("W", 1.6, w, d, dw=1.2, dh=2.1, stone_frame=True)
    objs += K2.chimney(w / 2 - 0.9, 1.6, 4.9, zr + 0.8)
    # hoist beam over the upper door with a rope and a sack
    objs.append(K2.box(0.2, 1.4, 0.2, (-1.3, -d / 2 - 0.6, 5.5), K2.timber()))
    objs += K2.sack(-1.3, -d / 2 - 1.15, 4.2, 0.9)
    objs.append(K2.cyl(0.02, 1.2, (-1.3, -d / 2 - 1.15, 4.6), K2.flat((150, 130, 96)), verts=4))
    # deck on piles over the water (south-west part of the south side)
    deck_x0, deck_x1 = -w / 2 - 1.6, 1.4
    dy0, dy1 = -d / 2, -d / 2 - 3.4
    pm = K2.planks((132, 98, 64), 0.26, False, 0.35)
    objs.append(K2.box(deck_x1 - deck_x0, dy0 - dy1, 0.22, ((deck_x0 + deck_x1) / 2, (dy0 + dy1) / 2, -0.12), pm,
                       name="deck"))
    for x in (deck_x0 + 0.2, (deck_x0 + deck_x1) / 2, deck_x1 - 0.2):
        for y in (dy1 + 0.2, (dy0 + dy1) / 2):
            objs.append(K2.cyl(0.16, 3.0, (x, y, WATER_Z - 0.6), K2.timber((92, 66, 44)), verts=8))
    # railing
    tm = K2.timber((104, 76, 50))
    for x in (deck_x0 + 0.2, deck_x0 + 2.2, deck_x0 + 4.2, deck_x1 - 0.2):
        objs.append(K2.box(0.14, 0.14, 1.05, (x, dy1 + 0.15, 0.0), tm))
    objs.append(K2.box(deck_x1 - deck_x0, 0.1, 0.1, ((deck_x0 + deck_x1) / 2, dy1 + 0.15, 0.95), tm))
    objs.append(K2.box(deck_x1 - deck_x0, 0.08, 0.08, ((deck_x0 + deck_x1) / 2, dy1 + 0.15, 0.5), tm))
    objs.append(K2.box(0.1, dy0 - dy1, 0.1, (deck_x0 + 0.15, (dy0 + dy1) / 2, 0.95), tm))
    # goods on the deck: barrels, sacks, crates
    for bx, by in ((-4.6, -4.4), (-4.0, -5.1), (-3.3, -4.5), (-1.8, -6.2)):
        objs += K2.barrel(bx, by, 0.0, rng=rng)
    for k, (sx, sy) in enumerate(((-0.6, -4.3), (-0.1, -4.6), (-0.4, -5.0), (0.3, -4.2), (-0.25, -4.5))):
        objs += K2.sack(sx, sy, 0.0 if k < 4 else 0.38, 1.0, rot=rng.uniform(0, 3))
    objs += K2.crate(-2.4, -6.3, 0.0, 0.7, 0.2)
    objs += K2.crate(-2.4, -6.3, 0.7, 0.6, 0.6)
    # flume bringing water to the top of the wheel (from upstream / west along the wall)
    fz = 2.0
    fm = K2.planks((112, 82, 54), 0.2, False, 0.35)
    fx0, fx1, fy = deck_x1 + 0.4, 4.2, -d / 2 - 1.15
    objs.append(K2.box(fx1 - fx0, 0.9, 0.1, ((fx0 + fx1) / 2, fy, fz), fm))
    for sy in (-1, 1):
        objs.append(K2.box(fx1 - fx0, 0.08, 0.4, ((fx0 + fx1) / 2, fy + sy * 0.45, fz), fm))
    objs.append(K2.box(fx1 - fx0, 0.75, 0.04, ((fx0 + fx1) / 2, fy, fz + 0.2),
                       K2.flat((70, 130, 150), rough=0.15, noise=0.05, ao=0.8)))
    for x in (fx0 + 0.3, (fx0 + fx1) / 2):
        objs.append(K2.box(0.14, 0.14, fz - WATER_Z + 0.4, (x, fy, WATER_Z - 0.4), K2.timber((92, 66, 44))))
    return objs, (w, d)


WHEEL_C = (3.2, -3.5 - 1.15, -0.55)      # wheel centre in mill coordinates (x, y, z)
WHEEL_R = 2.3


def mill_wheel(rng, frame=0, nframes=8):
    """Overshot wheel in the XZ plane (axle along Y), rotated by frame."""
    cx, cy, cz = WHEEL_C
    ang0 = frame / nframes * (2 * math.pi / 8)
    objs = []
    wood = K2.planks((118, 86, 56), 0.18, False, 0.35)
    dark = K2.timber((86, 60, 40))
    W = 1.0
    for side in (-1, 1):
        rim = K2.cyl(WHEEL_R, 0.14, (0, 0, 0), dark, verts=32, rot=(math.pi / 2, 0, 0), smooth=False)
        rim.location = (cx, cy + side * W / 2 - (-0.07 if side > 0 else 0.07) * 0, cz)
        # hollow it: a slightly smaller dark disc behind is enough at sprite scale; spokes carry the look
        objs.append(rim)
    # make rims into rings (solid discs read as walls): replace by ring segments
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    objs = []
    nseg = 32
    for side in (-1, 1):
        for k in range(nseg):
            a0 = ang0 + 2 * math.pi * k / nseg
            a1 = ang0 + 2 * math.pi * (k + 1) / nseg
            p0 = (cx + math.cos(a0) * WHEEL_R, cy + side * W / 2, cz + math.sin(a0) * WHEEL_R)
            p1 = (cx + math.cos(a1) * WHEEL_R, cy + side * W / 2, cz + math.sin(a1) * WHEEL_R)
            objs.append(K2.beam(p0, p1, 0.16, dark, size2=0.12))
    for k in range(8):
        a = ang0 + 2 * math.pi * k / 8
        for side in (-1, 1):
            objs.append(K2.beam((cx, cy + side * W / 2, cz), (cx + math.cos(a) * WHEEL_R, cy + side * W / 2,
                                                               cz + math.sin(a) * WHEEL_R), 0.12, dark))
    for k in range(16):
        a = ang0 + 2 * math.pi * k / 16
        px, pz = cx + math.cos(a) * (WHEEL_R - 0.25), cz + math.sin(a) * (WHEEL_R - 0.25)
        pad = K2.box(0.5, W, 0.06, (px, cy, pz - 0.03), wood)
        pad.rotation_euler = (0, -a, 0)
        objs.append(pad)
    hub = K2.cyl(0.32, W + 0.5, (cx, cy - (W + 0.5) / 2, cz), dark, verts=12, rot=(-math.pi / 2, 0, 0))
    hub.location = (cx, cy - (W + 0.5) / 2, cz)
    objs.append(hub)
    axle = K2.cyl(0.12, 1.4, (cx, cy + W / 2, cz), K2.iron(), verts=8, rot=(-math.pi / 2, 0, 0))
    objs.append(axle)
    # bearing post on the river side
    objs.append(K2.box(0.3, 0.3, cz - WATER_Z + 0.4, (cx, cy - W / 2 - 0.45, WATER_Z - 0.4), K2.timber((92, 66, 44))))
    return objs


@reg("mill", 711)
def _mill(rng):
    objs, fp = mill_body(rng)
    return objs, fp, {"catchers": [(0.0, -60, 60, -3.6, 60), (WATER_Z, -60, 60, -60, -3.6)],
                      "attach": {"wheel": list(WHEEL_C)}}


for _f in range(8):
    def _mkw(rng, f=_f):
        return mill_wheel(rng, f), (2.0, 2.0), {"catchers": [(0.0, -60, 60, -3.6, 60), (WATER_Z, -60, 60, -60, -3.6)],
                                                 "sort_point": list(WHEEL_C)}
    ENTRIES[f"mill_wheel_{_f}"] = (_mkw, 712)


# ------------------------------------------------------------------------------------------------
@reg("bridge", 721)
def bridge(rng, L=36.0, Wd=4.8):
    """Stone bridge along X with two arches and a central pier, humped deck, parapets with coping."""
    st = K2.stone((176, 164, 144), (130, 124, 116), (92, 86, 76), 0.55, 0.34)
    big = K2.stone((168, 156, 136), (124, 118, 110), (86, 80, 70), 0.75, 0.42)
    bm = bmesh.new()
    zb = WATER_Z - 1.0
    prof = []
    n = 24
    for i in range(n + 1):
        x = -L / 2 + L * i / n
        hump = 1.45 * (1 - (2 * x / L) ** 2)
        prof.append((x, hump))
    pts = [(x, z) for x, z in prof] + [(L / 2, zb), (-L / 2, zb)]
    front = [bm.verts.new((x, -Wd / 2, z)) for x, z in pts]
    back = [bm.verts.new((x, Wd / 2, z)) for x, z in pts]
    bm.faces.new(front[::-1])
    bm.faces.new(back)
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    body = K2.link_obj(bm, "bridge_body", big)
    objs = [body]
    # arch voids (boolean) + ring stones
    span, rr, cz = 8.0, 5.0, WATER_Z - 3.05          # segmental arches: crown 0.4 m above the bank
    for ax in (-5.4, 5.4):
        cut = K2.cyl(rr, Wd + 2.0, (0, 0, 0), None, verts=48, rot=(math.pi / 2, 0, 0), smooth=False)
        cut.location = (ax, Wd / 2 + 1.0, cz)
        mod = body.modifiers.new("arch", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cut
        mod.solver = "EXACT"
        cut.hide_render = True
        cut.hide_viewport = True
        for side in (-1, 1):
            for k in range(13):
                a0 = math.pi * k / 13
                a1 = math.pi * (k + 1) / 13
                p0 = (ax + math.cos(a0) * (rr + 0.2), side * (Wd / 2 + 0.06), cz + math.sin(a0) * (rr + 0.2))
                p1 = (ax + math.cos(a1) * (rr + 0.2), side * (Wd / 2 + 0.06), cz + math.sin(a1) * (rr + 0.2))
                if p0[2] < WATER_Z - 0.3 and p1[2] < WATER_Z - 0.3:
                    continue
                objs.append(K2.beam(p0, p1, 0.5, st, size2=0.2))
    # cutwaters on the central pier
    for side in (-1, 1):
        bm = bmesh.new()
        tri = [(-1.0, side * Wd / 2), (1.0, side * Wd / 2), (0.0, side * (Wd / 2 + 1.5))]
        lo = [bm.verts.new((x, y, zb)) for x, y in tri]
        hi = [bm.verts.new((x, y, WATER_Z + 0.9)) for x, y in tri]
        apex = bm.verts.new((0.0, side * Wd / 2, WATER_Z + 1.8))
        bm.faces.new(lo[::-1] if side > 0 else lo)
        for i in range(3):
            j = (i + 1) % 3
            bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
        bm.faces.new((hi[0], hi[1], apex))
        bm.faces.new((hi[1], hi[2], apex))
        bm.faces.new((hi[2], hi[0], apex))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        objs.append(K2.link_obj(bm, "cutwater", st))
    # parapets with coping stones, following the hump
    for side in (-1, 1):
        for i in range(n):
            x0, z0 = prof[i]
            x1, z1 = prof[i + 1]
            seg = K2.beam((x0, side * (Wd / 2 - 0.22), z0 - 0.02), (x1, side * (Wd / 2 - 0.22), z1 - 0.02), 0.44, st,
                          size2=0.44)
            objs.append(seg)
            wall = K2.box(L / n + 0.02, 0.44, 0.85, ((x0 + x1) / 2, side * (Wd / 2 - 0.22), (z0 + z1) / 2), st)
            wall.rotation_euler = (0, -math.atan2(z1 - z0, x1 - x0), 0)
            objs.append(wall)
            cop = K2.box(L / n + 0.04, 0.56, 0.16, ((x0 + x1) / 2, side * (Wd / 2 - 0.22), (z0 + z1) / 2 + 0.85),
                         K2.stone((190, 180, 160), (156, 148, 134), (120, 112, 100), 0.6, 0.2))
            cop.rotation_euler = (0, -math.atan2(z1 - z0, x1 - x0), 0)
            objs.append(cop)
    # paving of the deck
    for i in range(n):
        x0, z0 = prof[i]
        x1, z1 = prof[i + 1]
        pv = K2.box(L / n + 0.02, Wd - 0.88, 0.08, ((x0 + x1) / 2, 0, (z0 + z1) / 2 - 0.04), K2.paving())
        pv.rotation_euler = (0, -math.atan2(z1 - z0, x1 - x0), 0)
        objs.append(pv)
    # end posts
    for sx in (-1, 1):
        for side in (-1, 1):
            objs.append(K2.box(0.7, 0.7, 1.2, (sx * (L / 2 - 0.35), side * (Wd / 2 - 0.22), -0.05), st, bevel=0.04))
    return objs, (L, Wd), {"catchers": [(WATER_Z, -L / 2 + 2.5, L / 2 - 2.5, -40, 40), (0.0, -80, -L / 2 + 2.5, -40, 40),
                                        (0.0, L / 2 - 2.5, 80, -40, 40)]}


# ------------------------------------------------------------------------------------------------
# market
VEG = [((96, 150, 60), 0.12), ((206, 82, 44), 0.08), ((222, 160, 48), 0.09), ((176, 46, 40), 0.08),
       ((120, 70, 120), 0.09), ((232, 210, 120), 0.1)]


def goods(x0, y0, z, w, d, rng, kinds=("veg",), density=1.0):
    objs = []
    for kind in kinds:
        if kind == "veg":
            n = int(14 * density * w * d / 1.0)
            col, r = VEG[rng.randrange(len(VEG))]
            for i in range(n):
                if rng.random() < 0.25:
                    col, r = VEG[rng.randrange(len(VEG))]
                objs.append(K2.sphere(r * rng.uniform(0.8, 1.2), (x0 + rng.uniform(-w / 2, w / 2), y0 + rng.uniform(-d / 2, d / 2),
                                                                 z + r * 0.8), K2.flat(col, noise=0.15), segs=8))
        elif kind == "bread":
            for i in range(int(8 * density)):
                b = K2.sphere(0.12, (x0 + rng.uniform(-w / 2, w / 2), y0 + rng.uniform(-d / 2, d / 2), z + 0.07),
                              K2.flat((186, 128, 62), noise=0.2), scale=(1.5, 1.0, 0.6), segs=8)
                b.rotation_euler = (0, 0, rng.uniform(0, 3))
                objs.append(b)
        elif kind == "pots":
            for i in range(int(6 * density)):
                r = rng.uniform(0.1, 0.17)
                objs.append(K2.cyl(r, r * 2.4, (x0 + rng.uniform(-w / 2, w / 2), y0 + rng.uniform(-d / 2, d / 2), z),
                                   K2.flat(rng.choice([(168, 96, 62), (140, 112, 84), (180, 150, 112)]), noise=0.15),
                                   verts=10, r2=r * 0.55))
        elif kind == "cloth":
            for i in range(int(5 * density)):
                c = K2.cyl(0.11, w * 0.8, (0, 0, 0), K2.cloth(rng.choice([(150, 40, 40), (52, 84, 150), (200, 170, 90),
                                                                         (70, 120, 70), (220, 214, 196)])),
                           verts=10, rot=(0, math.pi / 2, 0))
                c.location = (x0 - w * 0.4, y0 - d / 2 + 0.15 + i * (d / 5), z + 0.11)
                objs.append(c)
    return objs


def stall(rng, kind="canvas", c1=(222, 210, 180), c2=None, goods_kinds=("veg",)):
    w, d, h = 3.2, 2.0, 2.3
    objs = []
    tm = K2.timber((112, 80, 52))
    for sx in (-1, 1):
        for sy in (-1, 1):
            objs.append(K2.box(0.12, 0.12, h + (0.35 if sy > 0 else 0.0), (sx * (w / 2 - 0.1), sy * (d / 2 - 0.1), 0), tm))
    # table
    objs.append(K2.box(w - 0.1, d * 0.62, 0.08, (0, -d * 0.12, 0.85), K2.planks((140, 104, 66), 0.22, False, 0.3)))
    for sx in (-1, 1):
        objs.append(K2.box(0.08, d * 0.55, 0.85, (sx * (w / 2 - 0.35), -d * 0.12, 0), tm))
    objs += goods(0, -d * 0.12, 0.93, w - 0.4, d * 0.5, rng, goods_kinds)
    # roof cloth
    if kind == "canvas":
        bm = bmesh.new()
        pts = [(-w / 2 - 0.25, -d / 2 - 0.4, h - 0.15), (w / 2 + 0.25, -d / 2 - 0.4, h - 0.15),
               (w / 2 + 0.25, 0, h + 0.75), (-w / 2 - 0.25, 0, h + 0.75),
               (w / 2 + 0.25, d / 2 + 0.3, h - 0.05), (-w / 2 - 0.25, d / 2 + 0.3, h - 0.05)]
        v = [bm.verts.new(p) for p in pts]
        bm.faces.new((v[0], v[1], v[2], v[3]))
        bm.faces.new((v[3], v[2], v[4], v[5]))
        o = K2.link_obj(bm, "canvas", K2.cloth(c1))
        sol = o.modifiers.new("s", "SOLIDIFY")
        sol.thickness = 0.04
        sub = o.modifiers.new("sub", "SUBSURF")
        sub.levels = 2
        objs.append(o)
        objs.append(K2.box(0.08, d + 0.6, 0.08, (0, 0, h + 0.72), tm))
    else:
        # sloped striped awning + valance
        bm = bmesh.new()
        v = [bm.verts.new(p) for p in [(-w / 2 - 0.2, -d / 2 - 0.55, h - 0.25), (w / 2 + 0.2, -d / 2 - 0.55, h - 0.25),
                                        (w / 2 + 0.2, d / 2 + 0.1, h + 0.45), (-w / 2 - 0.2, d / 2 + 0.1, h + 0.45)]]
        bm.faces.new(v)
        o = K2.link_obj(bm, "awning", K2.cloth(c1, c2, 0.3, "X"))
        sol = o.modifiers.new("s", "SOLIDIFY")
        sol.thickness = 0.04
        objs.append(o)
        val = K2.box(w + 0.4, 0.04, 0.32, (0, -d / 2 - 0.57, h - 0.56), K2.cloth(c1, c2, 0.3, "X"))
        objs.append(val)
    # crates, baskets and sacks around
    objs += K2.crate(w / 2 + 0.3, -d / 2 - 0.1, 0.0, 0.6, rng.uniform(-0.3, 0.3))
    objs += K2.crate(-w / 2 - 0.25, d / 2 - 0.3, 0.0, 0.55, rng.uniform(-0.3, 0.3))
    objs += goods(w / 2 + 0.3, -d / 2 - 0.1, 0.6, 0.45, 0.45, rng, ("veg",), 0.6)
    for k in range(2):
        bx, by = -w / 2 + 0.4 + k * 0.6, -d / 2 - 0.55
        objs.append(K2.cyl(0.24, 0.3, (bx, by, 0), K2.planks((168, 128, 80), 0.06, True, 0.2), verts=12, r2=0.3))
        objs += goods(bx, by, 0.26, 0.3, 0.3, rng, ("veg",), 0.5)
    objs += K2.sack(w / 2 + 0.2, d / 2 - 0.1, 0.0, 0.9, (200, 182, 140))
    # display in front of the awning: a low trestle with baskets of produce, visible from above
    objs.append(K2.box(w - 0.6, 0.7, 0.06, (0, -d / 2 - 1.05, 0.55), K2.planks((146, 108, 70), 0.2, False, 0.3)))
    for sx in (-1, 1):
        objs.append(K2.box(0.08, 0.6, 0.55, (sx * (w / 2 - 0.5), -d / 2 - 1.05, 0), K2.timber((112, 80, 52))))
    for k in range(4):
        bx = -w / 2 + 0.75 + k * (w - 1.5) / 3
        objs.append(K2.cyl(0.24, 0.2, (bx, -d / 2 - 1.05, 0.61), K2.planks((176, 134, 84), 0.05, True, 0.2), verts=12,
                           r2=0.3))
        objs += goods(bx, -d / 2 - 1.05, 0.79, 0.34, 0.34, rng, (goods_kinds[k % len(goods_kinds)],), 0.6)
    return objs


@reg("stall_canvas", 731)
def _s1(rng):
    return stall(rng, "canvas", (226, 214, 184), None, ("veg",)), (3.6, 2.6)


@reg("stall_red", 732)
def _s2(rng):
    return stall(rng, "awning", (176, 40, 38), (232, 222, 196), ("bread", "pots")), (3.6, 2.6)


@reg("stall_blue", 733)
def _s3(rng):
    return stall(rng, "awning", (52, 84, 150), (232, 226, 206), ("cloth",)), (3.6, 2.6)


@reg("stall_green", 734)
def _s4(rng):
    return stall(rng, "awning", (70, 120, 70), (226, 214, 180), ("veg", "veg")), (3.6, 2.6)


@reg("fountain", 741)
def fountain(rng):
    st = K2.stone((190, 180, 160), (150, 142, 128), (110, 104, 92), 0.4, 0.28)
    objs = []
    n = 8
    R0 = 2.0
    for k in range(n):
        a0 = 2 * math.pi * k / n
        a1 = 2 * math.pi * (k + 1) / n
        p0 = (math.cos(a0) * R0, math.sin(a0) * R0, 0)
        p1 = (math.cos(a1) * R0, math.sin(a1) * R0, 0)
        seg = K2.beam(p0, p1, 0.4, st, size2=0.7)
        seg.location = (p0[0], p0[1], 0.35)
        objs.append(K2.box(math.dist(p0, p1) + 0.05, 0.42, 0.75, ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, 0), st,
                           rot=(0, 0, (a0 + a1) / 2 + math.pi / 2)))
        bpy.data.objects.remove(seg, do_unlink=True)
    objs.append(K2.cyl(R0 - 0.1, 0.55, (0, 0, 0.05), K2.flat((64, 128, 140), rough=0.12, noise=0.08, ao=0.75), verts=24))
    objs.append(K2.cyl(0.55, 0.4, (0, 0, 0), st, verts=12))
    objs.append(K2.cyl(0.32, 1.8, (0, 0, 0.4), st, verts=12))
    objs.append(K2.cyl(0.85, 0.18, (0, 0, 2.2), st, verts=16))
    objs.append(K2.cyl(0.22, 0.9, (0, 0, 2.38), st, verts=10))
    # small statue on top
    objs.append(K2.cyl(0.16, 0.9, (0, 0, 3.28), K2.stone((200, 192, 176), (170, 162, 148)), verts=10, r2=0.1))
    objs.append(K2.sphere(0.13, (0, 0, 4.3), K2.stone((200, 192, 176), (170, 162, 148)), segs=8))
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        objs.append(K2.box(0.08, 0.5, 0.06, (math.cos(a) * 0.5, math.sin(a) * 0.5, 2.05), K2.iron(),
                           rot=(0, 0, a + math.pi / 2)))
    return objs, (4.4, 4.4)


# ------------------------------------------------------------------------------------------------
# military
LIVERY = (150, 30, 32)


@reg("barracks", 751)
def barracks(rng):
    w, d = 14.0, 7.6
    st = K2.stone((170, 158, 138), (126, 120, 112), (90, 82, 70))
    objs = [K2.box(w + 0.2, d + 0.2, 0.4, (0, 0, -0.1), st)]
    objs.append(K2.box(w, d, 3.2, (0, 0, 0.3), st))
    objs.append(K2.box(w, d, 2.8, (0, 0, 3.5), K2.plaster((222, 208, 180))))
    objs += K2.timber_frame(w, d, 3.5, 2.8, rng, pattern="cross")
    robjs, zr = K2.gable_roof(w, d, 6.3, 42, "tile_dark", rng, overhang=0.55, gable_over=0.4)
    objs += robjs
    rise = math.tan(math.radians(42)) * d / 2
    for sx in (-1, 1):
        objs.append(K2.gable_wall(d, 6.3, rise, K2.plaster((222, 208, 180)), thick=0.3, x=sx * (w / 2 - 0.12), axis="y"))
    for f in "SN":
        for u in (-5.2, -2.6, 2.6, 5.2):
            objs += K2.window(f, u, 1.5, w, d, ww=0.7, wh=0.9, frame_mat=st, shutters=(110, 40, 36))
            objs += K2.window(f, u, 4.3, w, d, ww=0.7, wh=0.85, shutters=(110, 40, 36))
    for f in "EW":
        objs += K2.window(f, 0, 4.3, w, d, ww=0.7, wh=0.85)
    objs += K2.door("S", 0.0, w, d, dw=1.8, dh=2.6, stone_frame=True)
    for x in (-1.6, 1.6, -6.6, 6.6):
        objs += banner(x, -d / 2, 6.0, 0.9, 2.0, "S")
    objs += K2.chimney(-w / 2 + 1.2, 1.2, 5.6, zr + 0.8)
    objs += K2.chimney(w / 2 - 1.2, 1.2, 5.6, zr + 0.8)
    # weapon rack against the wall + shields hanging
    objs += weapon_rack_objs(-4.2, -d / 2 - 0.55, rng)
    for k, x in enumerate((3.4, 4.4, 5.4)):
        sh = K2.cyl(0.38, 0.06, (0, 0, 0), K2.flat(LIVERY if k % 2 == 0 else (230, 224, 210), noise=0.1), verts=16,
                    rot=(math.pi / 2, 0, 0))
        sh.location = (x, -d / 2 - 0.05, 2.0)
        objs.append(sh)
        objs.append(K2.box(0.08, 0.04, 0.5, (x, -d / 2 - 0.1, 1.75), K2.flat((236, 230, 214))))
    return objs, (w, d)


def weapon_rack_objs(x, y, rng, n=7, yaw=0.0):
    objs = []
    tm = K2.timber((104, 74, 48))
    c, s_ = math.cos(yaw), math.sin(yaw)
    L = 2.4
    for sx in (-1, 1):
        objs.append(K2.box(0.12, 0.12, 1.5, (x + c * sx * L / 2, y + s_ * sx * L / 2, 0), tm))
    objs.append(K2.box(L + 0.2, 0.12, 0.1, (x, y, 1.3), tm, rot=(0, 0, yaw)))
    objs.append(K2.box(L + 0.2, 0.3, 0.08, (x, y, 0.15), tm, rot=(0, 0, yaw)))
    for k in range(n):
        u = -L / 2 + 0.2 + k * (L - 0.4) / (n - 1)
        bx, by = x + c * u, y + s_ * u
        objs.append(K2.beam((bx, by + 0.05, 0.15), (bx + 0.05, by - 0.12, 2.6), 0.045, tm))
        objs.append(K2.cyl(0.04, 0.28, (bx + 0.05, by - 0.12, 2.55), K2.iron(), verts=4, r2=0.0))
    return objs


@reg("palisade", 752)
def palisade(rng, L=8.0):
    objs = []
    lm = K2.planks((120, 88, 58), 0.3, True, 0.35)
    tm = K2.timber((98, 70, 46))
    x = -L / 2 + 0.15
    while x < L / 2:
        r = rng.uniform(0.14, 0.18)
        h = rng.uniform(3.0, 3.5)
        objs.append(K2.cyl(r, h, (x, 0, 0), lm, verts=8))
        objs.append(K2.cyl(r, 0.45, (x, 0, h), lm, verts=8, r2=0.02))
        x += 2 * r + rng.uniform(0.0, 0.03)
    for z in (0.9, 2.3):
        objs.append(K2.box(L, 0.14, 0.2, (0, 0.24, z), tm))
    for xx in (-L / 2 + 0.6, 0.0, L / 2 - 0.6):
        objs.append(K2.beam((xx, 0.3, 2.6), (xx, 1.7, 0.0), 0.16, tm))
    return objs, (L, 0.6)


@reg("watchtower", 753)
def watchtower(rng):
    st = K2.stone((168, 156, 136), (124, 118, 110), (88, 80, 70))
    objs = [K2.box(3.8, 3.8, 4.2, (0, 0, -0.1), st, bevel=0.03)]
    objs += K2.door("S", 0.0, 3.8, 3.8, dw=1.0, dh=2.0, stone_frame=True)
    tm = K2.timber((104, 76, 50))
    for sx in (-1, 1):
        for sy in (-1, 1):
            objs.append(K2.box(0.24, 0.24, 4.0, (sx * 1.9, sy * 1.9, 4.1), tm))
    objs.append(K2.box(4.8, 4.8, 0.25, (0, 0, 4.1), K2.planks((126, 94, 62), 0.25, False, 0.3)))
    for f, (dx, dy) in (("S", (0, -2.3)), ("N", (0, 2.3)), ("E", (2.3, 0)), ("W", (-2.3, 0))):
        ww, dd = (4.6, 0.1) if f in "SN" else (0.1, 4.6)
        objs.append(K2.box(ww, dd, 1.1, (dx, dy, 4.35), K2.planks((118, 86, 56), 0.22, True, 0.3)))
    rr, zr = K2.hip_roof(4.4, 4.4, 8.1, 46, "shingle", rng, overhang=0.5)
    objs += rr
    objs.append(K2.cyl(0.06, 3.0, (0, 0, zr - 0.2), tm, verts=6))
    objs += banner(0.45, 0.0, zr + 2.6, 0.8, 1.3, "S")
    objs += banner(0.0, -1.95, 3.6, 0.9, 2.0, "S")
    # ladder to the door and a brazier on the platform
    objs.append(K2.cyl(0.25, 0.4, (1.4, -1.4, 4.35), K2.iron(), verts=10, r2=0.35))
    objs.append(K2.sphere(0.2, (1.4, -1.4, 4.8), K2.flat((255, 150, 60), noise=0.2, emission=((255, 140, 50), 6.0)),
                          segs=6, scale=(1, 1, 0.6)))
    return objs, (4.8, 4.8)


@reg("stable", 754)
def stable(rng):
    w, d = 12.0, 5.0
    objs = []
    tm = K2.timber((104, 76, 50))
    pm = K2.planks((126, 92, 60), 0.26, True, 0.35)
    objs.append(K2.box(w, 0.2, 2.5, (0, d / 2, 0), pm))
    for sx in (-1, 1):
        objs.append(K2.box(0.2, d, 2.5, (sx * w / 2, 0, 0), pm))
    for k in range(5):
        x = -w / 2 + k * w / 4
        objs.append(K2.box(0.22, 0.22, 2.6, (x, -d / 2 + 0.1, 0), tm))
        if 0 < k < 4:
            objs.append(K2.box(0.1, d - 0.6, 1.3, (x, 0.2, 0), pm))
    objs.append(K2.box(w, 0.2, 0.25, (0, -d / 2 + 0.1, 2.5), tm))
    rr, zr = K2.gable_roof(w, d, 2.6, 28, "thatch_old", rng, overhang=0.6, gable_over=0.35)
    objs += rr
    rise = math.tan(math.radians(28)) * d / 2
    for sx in (-1, 1):
        objs.append(K2.gable_wall(d, 2.5, rise + 0.1, pm, thick=0.2, x=sx * w / 2, axis="y"))
    # inside: hay, mangers, saddles on the rail, buckets
    for k in range(4):
        x = -w / 2 + 1.5 + k * w / 4
        objs.append(K2.box(1.9, 1.2, 0.8, (x, d / 2 - 0.8, 0), K2.straw("X"), bevel=0.06))
        objs.append(K2.box(1.5, 0.45, 0.55, (x, -d / 2 + 0.7, 0), K2.planks((110, 80, 52), 0.2, False, 0.3)))
    objs.append(K2.box(w - 1, 0.1, 0.1, (0, -d / 2 + 0.25, 1.15), tm))
    for k in range(3):
        objs.append(K2.sphere(0.32, (-3.0 + k * 2.6, -d / 2 + 0.25, 1.28), K2.flat((92, 52, 30), noise=0.1),
                              scale=(1.2, 0.6, 0.5), segs=8))
        objs.append(K2.box(0.5, 0.06, 0.4, (-3.0 + k * 2.6, -d / 2 + 0.2, 0.95), K2.cloth((150, 30, 32))))
    for k in range(3):
        objs.append(K2.box(1.0, 0.6, 0.5, (w / 2 + 1.0, -1.2 + k * 0.7, 0), K2.straw("X"), bevel=0.05))
    objs.append(K2.box(1.0, 0.6, 0.5, (w / 2 + 1.0, -0.85, 0.5), K2.straw("X"), bevel=0.05))
    objs += K2.barrel(-w / 2 - 0.7, -d / 2 + 0.4, 0.0, 0.3, 0.7)
    objs += LMbanner(-w / 2 + 0.3, -d / 2 - 0.05, 2.45)
    return objs, (w + 2, d + 1)


def LMbanner(x, y, z):
    return banner(x, y, z, 0.7, 1.4, "S")


@reg("tent", 755)
def tent(rng):
    objs = []
    R0, H = 2.4, 3.6
    bm = bmesh.new()
    nseg = 16
    ring = [bm.verts.new((math.cos(2 * math.pi * k / nseg) * R0, math.sin(2 * math.pi * k / nseg) * R0, 1.7))
            for k in range(nseg)]
    apex = bm.verts.new((0, 0, H))
    for k in range(nseg):
        bm.faces.new((ring[k], ring[(k + 1) % nseg], apex))
    roof_o = K2.link_obj(bm, "tent_roof", K2.cloth((172, 36, 36), (236, 228, 210), 0.35, "X"))
    objs.append(roof_o)
    wall = K2.cyl(R0 - 0.1, 1.75, (0, 0, 0), K2.cloth((230, 222, 204)), verts=nseg)
    objs.append(wall)
    # valance (scalloped band)
    for k in range(nseg):
        a = 2 * math.pi * (k + 0.5) / nseg
        objs.append(K2.box(0.95, 0.04, 0.35, (math.cos(a) * (R0 + 0.02), math.sin(a) * (R0 + 0.02), 1.4),
                           K2.cloth((172, 36, 36) if k % 2 else (236, 228, 210)), rot=(0, 0, a + math.pi / 2)))
    # open flap
    objs.append(K2.box(1.0, 0.06, 1.6, (0, -R0 + 0.05, 0), K2.flat((36, 28, 24), noise=0.0)))
    objs.append(K2.cyl(0.05, 1.6, (0, 0, H - 0.1), K2.timber(), verts=6))
    objs += banner(0.35, 0.0, H + 1.4, 0.7, 1.1, "S")
    objs += banner(0.0, -R0 - 0.05, 1.3, 0.7, 1.0, "S", wave=0.02)
    return objs, (5.0, 5.0)


@reg("target", 756)
def target(rng):
    objs = []
    tm = K2.timber((110, 80, 52))
    objs.append(K2.beam((-0.6, 0.35, 0), (0, 0.1, 1.9), 0.09, tm))
    objs.append(K2.beam((0.6, 0.35, 0), (0, 0.1, 1.9), 0.09, tm))
    objs.append(K2.beam((0, 0.9, 0), (0, 0.15, 1.6), 0.09, tm))
    t = K2.cyl(0.62, 0.22, (0, 0, 0), K2.straw("Z"), verts=24, rot=(math.pi / 2 + 0.15, 0, 0))
    t.location = (0, 0.05, 1.15)
    objs.append(t)
    for k, (r, col) in enumerate(((0.5, (232, 224, 204)), (0.36, (176, 40, 36)), (0.22, (232, 224, 204)), (0.1, (176, 40, 36)))):
        ring = K2.cyl(r, 0.02, (0, 0, 0), K2.flat(col, noise=0.08), verts=24, rot=(math.pi / 2 + 0.15, 0, 0))
        ring.location = (0, -0.07 - k * 0.006, 1.15 - 0.016 * k)
        objs.append(ring)
    for k in range(3):
        a = K2.beam((0.15 * k - 0.1, -0.1, 1.2 + 0.08 * k), (0.15 * k - 0.1, -0.7, 1.25 + 0.08 * k), 0.025, tm)
        objs.append(a)
    return objs, (1.4, 1.0)


@reg("dummy", 757)
def dummy(rng):
    objs = []
    tm = K2.timber((104, 76, 50))
    objs.append(K2.box(0.16, 0.16, 1.9, (0, 0, 0), tm))
    objs.append(K2.box(1.3, 0.12, 0.12, (0, 0, 1.45), tm))
    objs.append(K2.sphere(0.32, (0, 0, 1.15), K2.cloth((196, 172, 120)), scale=(1.0, 0.8, 1.4), segs=10))
    objs.append(K2.sphere(0.2, (0, 0, 1.75), K2.cloth((196, 172, 120)), segs=8))
    objs.append(K2.cyl(0.21, 0.16, (0, 0, 1.82), K2.iron(), verts=10, r2=0.12))
    sh = K2.cyl(0.36, 0.05, (0, 0, 0), K2.flat(LIVERY, noise=0.1), verts=14, rot=(math.pi / 2, 0, 0))
    sh.location = (-0.5, -0.25, 1.1)
    objs.append(sh)
    objs.append(K2.box(0.4, 0.4, 0.12, (0, 0, 0), tm))
    return objs, (1.4, 0.8)


@reg("weapon_rack", 758)
def _wr(rng):
    objs = weapon_rack_objs(0, 0, rng)
    for k, x in enumerate((-0.8, 0.0, 0.8)):
        sh = K2.cyl(0.34, 0.05, (0, 0, 0), K2.flat(LIVERY if k != 1 else (230, 224, 210), noise=0.1), verts=14,
                    rot=(math.pi / 2 + 0.25, 0, 0))
        sh.location = (x, -0.28, 0.55)
        objs.append(sh)
    return objs, (2.8, 0.8)


@reg("banner_pole", 759)
def _bp(rng):
    objs = [K2.cyl(0.07, 5.6, (0, 0, 0), K2.timber(), verts=8)]
    objs.append(K2.sphere(0.12, (0, 0, 5.7), K2.flat((214, 172, 74), metal=0.6), segs=8))
    objs += banner(0.5, 0.0, 5.4, 0.9, 1.9, "S", wave=0.1)
    return objs, (1.0, 0.6)


@reg("weapons_table", 760)
def _wt(rng):
    objs = []
    tm = K2.timber((110, 80, 52))
    objs.append(K2.box(2.2, 0.9, 0.08, (0, 0, 0.82), K2.planks((136, 100, 64), 0.22, False, 0.3)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            objs.append(K2.box(0.08, 0.08, 0.82, (sx * 0.95, sy * 0.35, 0), tm))
    for k in range(3):
        objs.append(K2.box(0.9, 0.06, 0.03, (-0.4 + k * 0.4, -0.1 + 0.12 * k, 0.9), K2.iron(), rot=(0, 0, 0.3 * k)))
    for k in range(2):
        objs.append(K2.sphere(0.16, (0.7 - k * 0.35, 0.2, 0.98), K2.iron(), scale=(1, 1, 0.8), segs=8))
    objs += K2.barrel(1.5, 0.3, 0.0)
    return objs, (2.6, 1.2)


# ------------------------------------------------------------------------------------------------
@reg("smithy", 771)
def smithy(rng):
    w, d = 7.2, 6.0
    st = K2.stone((160, 150, 134), (120, 114, 106), (84, 78, 68))
    objs = [K2.box(w + 0.16, d + 0.16, 0.4, (0, 0, -0.1), st)]
    objs.append(K2.box(w, d, 3.2, (0, 0, 0.3), st))
    robjs, zr = K2.gable_roof(w, d, 3.5, 40, "shingle", rng, overhang=0.5)
    objs += robjs
    rise = math.tan(math.radians(40)) * d / 2
    for sx in (-1, 1):
        objs.append(K2.gable_wall(d, 3.5, rise, K2.planks((112, 82, 54), 0.24, True, 0.4), thick=0.3,
                                  x=sx * (w / 2 - 0.12), axis="y"))
    objs += K2.window("S", 1.8, 1.4, w, d, ww=0.8, wh=0.9, frame_mat=st)
    objs += K2.window("W", 0.0, 1.4, w, d, ww=0.8, wh=0.9, frame_mat=st)
    objs += K2.door("S", -0.6, w, d, dw=1.3, dh=2.2, stone_frame=True)
    # open forge shed on the east side
    fx = w / 2 + 2.0
    tm = K2.timber((98, 70, 46))
    for sy in (-1, 1):
        objs.append(K2.box(0.2, 0.2, 2.8, (w / 2 + 3.6, sy * (d / 2 - 0.4), 0), tm))
    lt = K2.lean_to(d + 0.4, 4.4, 3.4, 2.7, "shingle", rng, 0.0, side=-1)
    lt.rotation_euler = (0, 0, math.pi / 2)
    lt.location = (w / 2, 0, 0)
    objs.append(lt)
    # forge hearth with glowing coals and a hood + chimney
    objs.append(K2.box(1.8, 1.6, 0.9, (fx, 1.2, 0), st, bevel=0.03))
    objs.append(K2.box(1.3, 1.1, 0.12, (fx, 1.2, 0.9), K2.flat((255, 120, 40), noise=0.35, scale=9,
                                                                  emission=((255, 110, 40), 9.0))))
    objs.append(K2.box(1.9, 1.7, 0.8, (fx, 1.2, 2.0), st))
    objs += K2.chimney(fx, 1.6, 2.6, zr + 1.0)
    for o in objs[-3:]:
        if o.name.startswith("chimney_cap"):
            o.name = "emit_smoke_forge"
    objs.append(K2.sphere(0.45, (fx - 1.3, 1.6, 1.0), K2.flat((92, 60, 36), noise=0.1), scale=(1.2, 0.6, 0.4), segs=8))
    # anvil on a stump, quench trough, coal pile, grindstone
    objs.append(K2.cyl(0.32, 0.6, (fx, -1.1, 0), K2.timber((104, 76, 50)), verts=10))
    objs.append(K2.box(0.7, 0.26, 0.26, (fx, -1.1, 0.6), K2.iron(), bevel=0.03))
    objs.append(K2.cyl(0.12, 0.3, (fx + 0.38, -1.1, 0.68), K2.iron(), verts=6, r2=0.0, rot=(0, math.pi / 2, 0)))
    objs.append(K2.box(1.4, 0.6, 0.55, (fx + 1.2, 0.2, 0), K2.planks((110, 80, 52), 0.2, False, 0.4)))
    objs.append(K2.box(1.25, 0.45, 0.04, (fx + 1.2, 0.2, 0.5), K2.flat((50, 70, 80), rough=0.15, noise=0.05, ao=0.8)))
    objs.append(K2.sphere(0.6, (fx + 1.1, 2.4, 0), K2.flat((36, 34, 34), noise=0.25, scale=12), scale=(1.2, 0.9, 0.55),
                          segs=8))
    gs = K2.cyl(0.42, 0.14, (0, 0, 0), K2.stone((170, 164, 150), (140, 136, 126)), verts=16, rot=(math.pi / 2, 0, 0))
    gs.location = (w / 2 + 0.6, -d / 2 - 0.9, 0.62)
    objs.append(gs)
    for sx in (-1, 1):
        objs.append(K2.box(0.1, 0.3, 0.6, (w / 2 + 0.6 + sx * 0.2, -d / 2 - 0.9, 0), K2.timber()))
    # tool rack on the wall, horseshoes, iron bars
    objs.append(K2.box(1.6, 0.08, 0.1, (fx - 0.2, d / 2 - 0.5, 1.9), K2.timber()))
    for k in range(5):
        objs.append(K2.box(0.05, 0.05, 0.7, (fx - 0.9 + k * 0.35, d / 2 - 0.55, 1.2), K2.iron()))
    for k in range(4):
        objs.append(K2.box(1.6, 0.06, 0.06, (fx + 2.3, -1.9 + k * 0.1, 0.05 + 0.06 * (k % 2)), K2.iron(), rot=(0, 0, 0.2)))
    objs += K2.barrel(-w / 2 - 0.6, -d / 2 + 0.6, 0.0)
    objs += K2.crate(-w / 2 - 0.6, -d / 2 - 0.4, 0.0, 0.65, 0.3)
    objs.append(K2.box(1.0, 0.06, 0.6, (-1.9, -d / 2 - 0.1, 2.3), K2.planks((140, 104, 64), 0.12, False, 0.2),
                       name="signboard"))
    return objs, (w + 4.4, d)
