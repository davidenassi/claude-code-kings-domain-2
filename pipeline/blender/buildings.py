"""King's Domain building library (Blender 4.5 procedural models -> project-camera sprites).

Run:  python blender/buildings.py [--only house_a,castle] [--samples 48]
Output: game/assets/sprites/buildings/<name>.png, <name>_sh.png, buildings.json (anchor, footprint)
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Vector
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bkit as B  # noqa: E402
import kdrender as R  # noqa: E402

OUT = os.path.join(R.K.GAME_DIR, "assets", "sprites", "buildings")

PLASTERS = [(226, 214, 186), (214, 196, 158), (230, 222, 204), (206, 184, 146), (222, 206, 176)]


def chimney(x, y, z_base, z_top, kind="grey"):
    objs = [B.box(0.75, 0.75, z_top - z_base, (x, y, z_base), B.stone_mat("dark"), name="chimney")]
    objs.append(B.box(0.95, 0.95, 0.16, (x, y, z_top - 0.1), B.flat_mat("cap", (70, 66, 62)), name="chimney_cap"))
    return objs


def house(rng, w=7.0, d=5.5, floors=1, fh=2.9, roof="tile_red", pitch=40, ridge_x=True, walls="timber",
          plaster=None, jetty=0.0, chimneys=1, shutters=None, door_x=None, pattern="cross", stone_ground=False,
          lean_to=False, dormers=0):
    """Generic medieval house. Returns (objects, footprint (w, d))."""
    objs = []
    plaster = plaster or rng.choice(PLASTERS)
    pm = B.plaster_mat(plaster)
    tm = B.timber_mat()
    objs.append(B.box(w + 0.3, d + 0.3, 0.4, (0, 0, -0.05), B.stone_mat("grey"), name="plinth"))
    z = 0.35
    door_x = (rng.uniform(-w * 0.25, w * 0.25) if door_x is None else door_x)
    for fl in range(floors):
        ww = w
        dd = d + (2 * jetty if fl > 0 else 0.0)
        if fl == 0 and (stone_ground or walls == "stone"):
            objs.append(B.box(ww, dd, fh, (0, 0, z), B.stone_mat("warm"), name="wall"))
        elif walls == "wood":
            objs.append(B.box(ww, dd, fh, (0, 0, z), B.wood_mat("logs", (112, 82, 56), plank=0.3, vertical=False),
                              name="wall"))
        else:
            objs.append(B.box(ww, dd, fh, (0, 0, z), pm, name="wall"))
            if walls == "timber":
                objs += B.timber_frame(ww, dd, z, fh, tm, rng, pattern=pattern if fl % 2 == 0 else "brace")
        if fl > 0 and jetty > 0:
            objs.append(B.box(ww + 0.1, dd + 0.1, 0.22, (0, 0, z - 0.1), tm, name="jetty_beam"))
        wz = z + 0.9
        avoid = (door_x,) if fl == 0 else ()
        objs += B.place_windows(ww, dd, wz, rng, faces="SEW" if not ridge_x else "SE", spacing=2.3,
                                shutters=shutters, avoid=avoid, wh=(0.7, 0.95 if fl == 0 else 0.9))
        z += fh
    # door
    objs += B.door(door_x, -d / 2 - 0.02, "S", w=1.05, h=2.05)
    # roof
    rw, rd = w, d + 2 * jetty * (1 if floors > 1 else 0)
    rmat = B.roof_mat(roof)
    roof_o, zr = B.gable_roof(rw, rd, z, pitch, rmat, overhang=0.5, thick=0.22 if roof == "thatch" else 0.16,
                              ridge_x=ridge_x)
    objs.append(roof_o)
    rise = zr - z
    span = rd if ridge_x else rw
    gm = pm if walls != "stone" else B.stone_mat("warm")
    if walls == "wood":
        gm = B.wood_mat("gable_planks", (104, 76, 52), plank=0.25)
    for sgn in (-1, 1):
        g = B.gable_tri(span, z, rise - 0.05, gm)
        if ridge_x:
            g.rotation_euler = (0, 0, math.pi / 2)
            g.location = (sgn * rw / 2, 0, 0)
        else:
            g.location = (0, sgn * rd / 2, 0)
        objs.append(g)
        if walls == "timber" and not ridge_x and sgn == -1:
            # timber in the visible front gable
            objs.append(B.beam((0, -rd / 2 - 0.06, z), (0, -rd / 2 - 0.06, zr - 0.2), 0.16, tm))
            objs.append(B.beam((-span / 2 + 0.3, -rd / 2 - 0.06, z + 0.1), (0, -rd / 2 - 0.06, zr - 0.3), 0.14, tm))
            objs.append(B.beam((span / 2 - 0.3, -rd / 2 - 0.06, z + 0.1), (0, -rd / 2 - 0.06, zr - 0.3), 0.14, tm))
            objs += B.window(0, -rd / 2 - 0.02, z + rise * 0.25, "S", w=0.6, h=0.7, shutters=shutters)
    # chimneys
    for k in range(chimneys):
        slot = (k - (chimneys - 1) / 2) * 0.55 + rng.uniform(-0.08, 0.08)
        cx = slot * rw if ridge_x else rng.uniform(-0.15, 0.15) * rw
        cy = rd * 0.12 if ridge_x else (slot * 0.8 if chimneys > 1 else rng.uniform(-0.25, 0.25)) * rd
        objs += chimney(cx, cy, z, zr + 1.0)
    # dormers (rich houses)
    for k in range(dormers):
        dx = (k - (dormers - 1) / 2) * (rw / max(dormers, 1)) * 0.7
        t = math.tan(math.radians(pitch))
        y0 = -rd / 2 * 0.45
        zz = z + t * (rd / 2 - abs(y0)) - 0.2
        objs.append(B.box(1.3, 1.6, 1.4, (dx, y0 - 0.2, zz), pm, name="dormer"))
        objs += B.window(dx, y0 - 1.01, zz + 0.25, "S", w=0.6, h=0.8)
        dr, _ = B.gable_roof(1.3, 1.9, zz + 1.4, 45, rmat, overhang=0.2, thick=0.1, ridge_x=False)
        dr.location = (dx, y0 - 0.25, 0)
        objs.append(dr)
    # lean-to shed on the east side
    if lean_to:
        sw = 2.4
        objs.append(B.box(sw, d * 0.8, 2.1, (w / 2 + sw / 2, 0, 0), B.wood_mat("shed", (110, 82, 56), plank=0.2),
                          name="shed"))
        sr, _ = B.gable_roof(sw * 2, d * 0.8, 2.1, 22, rmat, overhang=0.3, thick=0.12, ridge_x=False)
        sr.location = (w / 2, 0, 0)
        objs.append(sr)
    return objs, (w + (2.4 if lean_to else 0), d + 2 * jetty)


# ------------------------------------------------------------------------------------------------
CATALOG = {}


def entry(name, seed, footprint_hint=None):
    def deco(fn):
        CATALOG[name] = (fn, seed)
        return fn
    return deco


@entry("house_a", 101)
def _(rng):
    return house(rng, w=6.5, d=5.2, roof="thatch", pitch=46, walls="timber", plaster=(226, 214, 186))


@entry("house_b", 102)
def _(rng):
    return house(rng, w=7.0, d=5.4, roof="tile_red", walls="timber", ridge_x=False, plaster=(214, 196, 158),
                 shutters=(76, 96, 70))


@entry("house_c", 103)
def _(rng):
    return house(rng, w=6.0, d=5.0, roof="shingle", walls="wood", pitch=42, lean_to=True)


@entry("house_d", 104)
def _(rng):
    return house(rng, w=7.5, d=5.6, roof="tile_brown", walls="plaster", plaster=(206, 184, 146), stone_ground=True,
                 shutters=(120, 58, 40))


@entry("house_e", 105)
def _(rng):
    return house(rng, w=5.6, d=4.8, roof="thatch", pitch=46, walls="stone", chimneys=1)


@entry("house_rich_a", 111)
def _(rng):
    return house(rng, w=9.0, d=7.0, floors=2, fh=2.8, roof="tile_red", walls="timber", jetty=0.45,
                 stone_ground=True, chimneys=2, shutters=(60, 84, 110), dormers=2)


@entry("house_rich_b", 112)
def _(rng):
    return house(rng, w=7.6, d=8.0, floors=2, fh=2.8, roof="tile_orange", walls="timber", ridge_x=False,
                 jetty=0.4, plaster=(230, 222, 204), chimneys=1, shutters=(104, 54, 40), pattern="brace")


@entry("house_rich_c", 113)
def _(rng):
    return house(rng, w=10.0, d=7.2, floors=3, fh=2.7, roof="slate", walls="plaster", plaster=(218, 204, 172),
                 stone_ground=True, chimneys=2, shutters=(64, 92, 72), dormers=3)


# ------------------------------------------------------------------------------------------------
# props used by several buildings
def barrel(x, y, z=0.0, r=0.38, h=0.95):
    m = B.wood_mat("barrel", (118, 82, 50), plank=0.12)
    o = [B.cyl(r, h, (x, y, z), m, verts=14, name="barrel")]
    band = B.flat_mat("iron", (60, 58, 56), rough=0.5, noise=0.05)
    for zz in (0.15, h - 0.2):
        o.append(B.cyl(r + 0.02, 0.06, (x, y, z + zz), band, verts=14))
    return o


def crate(x, y, z=0.0, s=0.7, rot=0.0):
    return [B.box(s, s, s * 0.85, (x, y, z), B.wood_mat("crate", (146, 110, 70), plank=0.14, vertical=False),
                  rot=(0, 0, rot), name="crate")]


def sack(x, y, z=0.0):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.3, location=(x, y, z + 0.38), segments=12, ring_count=8)
    o = bpy.context.object
    o.scale = (0.85, 0.7, 1.35)
    bpy.ops.object.shade_smooth()
    o.data.materials.append(B.flat_mat("sack", (158, 136, 100), noise=0.18, bump=0.3, nscale=10.0))
    return [o]


def log_pile(x, y, n=9, length=4.0, r=0.22, rot=0.0):
    m = B.flat_mat("log_bark", (96, 70, 48), noise=0.25, bump=0.3, nscale=6.0)
    objs = []
    rows = [4, 3, 2, 1]
    k = 0
    for row, per in enumerate(rows):
        for i in range(per):
            if k >= n:
                break
            off = (i - (per - 1) / 2) * r * 2.05
            o = B.cyl(r, length, (0, 0, 0), m, verts=12)
            # cylinder axis -> horizontal along `rot`; rows stacked across it
            o.rotation_euler = (0, math.pi / 2, rot)
            o.location = (x - math.sin(rot) * off, y + math.cos(rot) * off, r + row * r * 1.75)
            objs.append(o)
            k += 1
    return objs


def plank_stack(x, y, z=0.0, l=3.0, layers=6, rot=0.0):
    m = B.wood_mat("planks", (182, 144, 96), plank=0.25, vertical=False)
    return [B.box(l, 1.2, 0.06 * layers * 2, (x, y, z), m, rot=(0, 0, rot), name="planks")]


def hay_bale(x, y, z=0.0, rot=0.0):
    return [B.box(1.0, 0.55, 0.5, (x, y, z), B.thatch_mat("hay", (176, 150, 84)), rot=(0, 0, rot), name="bale")]


def haystack(x, y, h=2.6, r=1.5):
    m = B.thatch_mat("haystack", (170, 142, 78))
    o = B.cyl(r, h * 0.55, (x, y, 0), m, verts=18, r2=r * 0.9)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r * 0.95, location=(x, y, h * 0.55), segments=18, ring_count=10)
    top = bpy.context.object
    top.scale = (1, 1, 0.9)
    top.data.materials.append(m)
    for ob in (o, top):
        B.bpy.context.view_layer.objects.active = ob
    return [o, top]


def fence_line(a, b, mat=None, post=1.6, h=1.0):
    """Wooden post-and-rail fence from a to b (x, y)."""
    m = mat or B.flat_mat("fence_wood", (112, 86, 58), noise=0.2, nscale=8.0)
    a = Vector((a[0], a[1], 0))
    b = Vector((b[0], b[1], 0))
    L = (b - a).length
    n = max(1, int(L / post))
    objs = []
    for i in range(n + 1):
        p = a + (b - a) * (i / n)
        objs.append(B.box(0.12, 0.12, h, p, m, name="post"))
    for z in (h * 0.45, h * 0.85):
        objs.append(B.beam(a + Vector((0, 0, z)), b + Vector((0, 0, z)), 0.07, m))
    return objs


def cart(x, y, rot=0.0, load=None):
    m = B.wood_mat("cart", (128, 94, 60), plank=0.15, vertical=False)
    objs = [B.box(2.2, 1.2, 0.35, (x, y, 0.6), m, rot=(0, 0, rot), name="cart_bed")]
    wheel = B.flat_mat("wheel", (84, 62, 42), noise=0.1)
    for s_ in (-1, 1):
        w = B.cyl(0.5, 0.1, (0, 0, 0), wheel, verts=16, rot=(math.pi / 2, 0, rot))
        w.location = (x - math.sin(rot) * 0.68 * s_, y + math.cos(rot) * 0.68 * s_, 0.5)
        objs.append(w)
    objs.append(B.beam((x + math.cos(rot) * 1.1, y + math.sin(rot) * 1.1, 0.7),
                       (x + math.cos(rot) * 2.6, y + math.sin(rot) * 2.6, 0.35), 0.09, m))
    if load == "hay":
        objs.append(B.box(1.9, 1.0, 0.7, (x, y, 0.95), B.thatch_mat("hay", (176, 150, 84)), rot=(0, 0, rot)))
    elif load == "stone":
        objs.append(B.box(1.6, 0.9, 0.45, (x, y, 0.95), B.stone_mat("warm"), rot=(0, 0, rot)))
    elif load == "ore":
        objs.append(B.box(1.6, 0.9, 0.4, (x, y, 0.95), B.flat_mat("ore", (70, 62, 58), noise=0.4, nscale=12.0),
                          rot=(0, 0, rot)))
    return objs


def rock_mat(name="crag", c0=(78, 74, 68), c1=(138, 128, 112), moss=0.35):
    if name in B._M:
        return B._M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.9
    tc = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.6
    noise.inputs["Detail"].default_value = 10.0
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*B.lin(c0), 1)
    ramp.color_ramp.elements[1].color = (*B.lin(c1), 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sep.inputs["Vector"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.6
    mr.inputs["From Max"].default_value = 0.9
    mr.inputs["To Max"].default_value = moss
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(mr.outputs["Result"], mix.inputs["Factor"])
    nt.links.new(ramp.outputs["Color"], mix.inputs["A"])
    mix.inputs["B"].default_value = (*B.lin((70, 86, 40)), 1)
    nt.links.new(mix.outputs["Result"], p.inputs["Base Color"])
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 1.2
    nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
    bm = nt.nodes.new("ShaderNodeBump")
    bm.inputs["Strength"].default_value = 0.6
    bm.inputs["Distance"].default_value = 0.3
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    nt.links.new(noise.outputs["Fac"], add.inputs[0])
    nt.links.new(vor.outputs["Distance"], add.inputs[1])
    nt.links.new(add.outputs[0], bm.inputs["Height"])
    nt.links.new(bm.outputs["Normal"], p.inputs["Normal"])
    B._M[name] = m
    return m


def rockmass(loc, scale, seed, mat=None, subdiv=4):
    """Craggy rock mass: a cluster of displaced boulders (no single smooth blob)."""
    import random as _r
    rr = _r.Random(seed)
    objs = []
    mat = mat or rock_mat()
    n = 6
    for k in range(n):
        ox = rr.uniform(-0.55, 0.55) * scale[0]
        oy = rr.uniform(-0.4, 0.4) * scale[1]
        sz = rr.uniform(0.45, 0.75)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=1.0,
                                              location=(loc[0] + ox, loc[1] + oy, loc[2]))
        o = bpy.context.object
        o.scale = (scale[0] * sz * 0.6, scale[1] * sz * 0.8, scale[2] * rr.uniform(0.6, 1.0))
        o.rotation_euler = (0, 0, rr.uniform(0, 6.28))
        tex = bpy.data.textures.new(f"vor{seed}_{k}", "VORONOI")
        tex.noise_scale = 0.45
        m1 = o.modifiers.new("d1", "DISPLACE")
        m1.texture = tex
        m1.strength = -0.3
        m1.mid_level = 0.0
        m1.texture_coords = "OBJECT"
        tex2 = bpy.data.textures.new(f"cl{seed}_{k}", "CLOUDS")
        tex2.noise_scale = 0.25
        m2 = o.modifiers.new("d2", "DISPLACE")
        m2.texture = tex2
        m2.strength = 0.18
        m2.texture_coords = "OBJECT"
        o.data.materials.append(mat)
        objs.append(o)
    return objs


# ------------------------------------------------------------------------------------------------
@entry("farm", 121)
def _(rng):
    objs, _ = house(rng, w=8.0, d=6.0, roof="thatch", pitch=44, walls="timber", plaster=(222, 206, 176),
                    shutters=(96, 74, 50))
    for o in objs:
        o.location.x -= 4.5
    barn_m = B.wood_mat("barn", (118, 86, 58), plank=0.24)
    bx, by = 5.5, 1.5
    objs.append(B.box(7.0, 6.5, 3.6, (bx, by, 0), barn_m, name="barn"))
    br, zr = B.gable_roof(7.0, 6.5, 3.6, 44, B.roof_mat("shingle"), overhang=0.4, ridge_x=False)
    br.location = (bx, by, 0)
    objs.append(br)
    for sgn in (-1, 1):
        g = B.gable_tri(7.0, 3.6, zr - 3.65, barn_m)
        g.location = (bx, by + sgn * 3.25, 0)
        objs.append(g)
    objs.append(B.box(2.6, 0.12, 2.8, (bx, by - 3.3, 0), B.wood_mat("barn_door", (88, 62, 42), plank=0.2)))
    objs += fence_line((-9.5, -6.5), (9.5, -6.5))
    objs += fence_line((9.5, -6.5), (9.5, 6.0))
    objs += fence_line((-9.5, -6.5), (-9.5, 4.5))
    objs += haystack(8.0, -3.8)
    objs += cart(1.0, -4.5, rot=0.3, load="hay")
    objs += hay_bale(-2.0, -4.8, rot=0.2) + hay_bale(-1.2, -5.4, rot=-0.3)
    objs += barrel(-8.3, -2.5) + barrel(-7.6, -2.9)
    return objs, (19.0, 13.0)


@entry("granary", 131)
def _(rng):
    objs = []
    stone = B.stone_mat("grey")
    for x in (-3.2, -1.1, 1.1, 3.2):
        for y in (-2.3, 0, 2.3):
            objs.append(B.cyl(0.25, 0.7, (x, y, 0), stone, verts=10))
            objs.append(B.cyl(0.45, 0.14, (x, y, 0.7), stone, verts=12))
    wm = B.wood_mat("granary", (132, 96, 62), plank=0.22)
    objs.append(B.box(7.6, 5.6, 0.25, (0, 0, 0.84), B.timber_mat()))
    objs.append(B.box(7.4, 5.4, 3.4, (0, 0, 1.08), wm, name="granary"))
    objs += B.timber_frame(7.4, 5.4, 1.08, 3.4, B.timber_mat(), rng, pattern="plain", spacing=1.85, size=0.2)
    rf, zr = B.gable_roof(7.4, 5.4, 4.48, 42, B.roof_mat("tile_brown"), overhang=0.55)
    objs.append(rf)
    for sgn in (-1, 1):
        g = B.gable_tri(5.4, 4.48, zr - 4.53, wm)
        g.rotation_euler = (0, 0, math.pi / 2)
        g.location = (sgn * 3.7, 0, 0)
        objs.append(g)
    objs.append(B.box(1.8, 0.12, 2.2, (0, -2.75, 1.1), B.wood_mat("door_wood", (92, 60, 38), plank=0.16)))
    objs.append(B.box(1.6, 1.3, 0.12, (0, -3.4, 0.5), B.timber_mat()))      # loading ramp
    objs.append(B.beam((0, -2.8, 1.08), (0, -4.0, 0.0), 0.5, B.wood_mat("ramp", (120, 92, 60), plank=0.2)))
    for i, (x, y) in enumerate([(-1.8, -3.6), (-2.4, -3.3), (-1.4, -4.1), (1.8, -3.5), (2.3, -3.9)]):
        objs += sack(x, y)
    return objs, (8.6, 7.5)


@entry("sawmill", 141)
def _(rng):
    objs = []
    tm = B.timber_mat()
    W, D, H = 10.0, 6.0, 3.6
    for x in (-W / 2, -W / 6, W / 6, W / 2):
        for y in (-D / 2, D / 2):
            objs.append(B.box(0.25, 0.25, H, (x, y, 0), tm))
    objs.append(B.box(W, 0.2, 0.3, (0, -D / 2, H - 0.3), tm))
    objs.append(B.box(W, 0.2, 0.3, (0, D / 2, H - 0.3), tm))
    objs.append(B.box(W * 0.33, 0.12, H, (W / 3, D / 2, 0), B.wood_mat("saw_wall", (126, 94, 62), plank=0.22)))
    rf, zr = B.gable_roof(W, D, H, 30, B.roof_mat("shingle"), overhang=0.6)
    objs.append(rf)
    # saw frame (vertical frame saw) and the log on the bench
    objs.append(B.box(6.0, 0.9, 0.8, (0, 0, 0), tm, name="bench"))
    objs.append(B.cyl(0.32, 5.5, (0, 0, 0), B.flat_mat("log_bark", (96, 70, 48), noise=0.25, bump=0.3, nscale=6.0),
                      verts=12, rot=(0, math.pi / 2, 0)))
    objs[-1].location = (0, 0, 1.15)
    objs.append(B.box(0.18, 0.18, 2.8, (-0.4, -0.5, 0), tm))
    objs.append(B.box(0.18, 0.18, 2.8, (-0.4, 0.5, 0), tm))
    objs.append(B.box(0.2, 1.2, 0.2, (-0.4, 0, 2.7), tm))
    objs += log_pile(-9.0, 0.5, n=10, length=4.5, r=0.26, rot=0.0)
    objs += plank_stack(8.2, -1.5, l=3.2, layers=5) + plank_stack(8.2, 0.4, l=3.2, layers=3)
    objs += cart(4.0, -4.6, rot=-0.2)
    objs.append(B.box(3.0, 2.0, 0.05, (-3.0, -4.2, 0), B.flat_mat("chips", (176, 146, 100), noise=0.3, nscale=20.0)))
    return objs, (22.0, 10.0)


@entry("quarry", 151)
def _(rng):
    objs = []
    # natural rock mass behind, with stepped cut faces towards the camera
    objs += rockmass((0, 5.0, 0.0), (13.0, 5.5, 7.0), 1)
    cut = B.stone_mat("warm")
    steps = [(0, -0.6, 2.2, 14.0), (0, 0.9, 4.2, 11.0), (0, 2.2, 6.0, 8.0)]
    for x, y, h, w in steps:
        objs.append(B.box(w, 2.4, h, (x, y, 0), B.brick_mat("cutstone", (150, 140, 120), (138, 128, 110),
                                                              (118, 110, 96), 1.6, 0.8, bump=0.5, noise_amt=0.2,
                                                              mortar_size=0.008), name="cutface"))
    for i in range(7):
        x = -6 + i * 1.6 + rng.uniform(-0.3, 0.3)
        y = -3.6 + rng.uniform(-0.6, 0.6)
        objs.append(B.box(1.2, 0.8, 0.7, (x, y, 0), cut, rot=(0, 0, rng.uniform(-0.3, 0.3)), name="block"))
        if i % 2 == 0:
            objs.append(B.box(1.1, 0.75, 0.65, (x + 0.1, y, 0.7), cut, rot=(0, 0, rng.uniform(-0.3, 0.3))))
    # treadwheel crane
    tm = B.timber_mat()
    cx, cy = 5.5, -2.0
    objs.append(B.beam((cx - 1.2, cy, 0), (cx, cy, 6.0), 0.25, tm))
    objs.append(B.beam((cx + 1.2, cy, 0), (cx, cy, 6.0), 0.25, tm))
    objs.append(B.beam((cx, cy, 6.0), (cx - 3.5, cy - 1.0, 5.2), 0.2, tm))
    wheel = B.cyl(1.7, 1.1, (0, 0, 0), B.wood_mat("wheel_w", (120, 88, 58), plank=0.2), verts=24,
                  rot=(math.pi / 2, 0, 0))
    wheel.location = (cx + 1.6, cy, 1.8)
    objs.append(wheel)
    objs.append(B.box(0.04, 0.04, 2.2, (cx - 3.5, cy - 1.0, 3.0), B.flat_mat("rope", (160, 140, 100))))
    objs.append(B.box(1.0, 0.7, 0.6, (cx - 3.5, cy - 1.0, 2.4), cut))
    objs += cart(-3.0, -6.0, rot=0.15, load="stone")
    return objs, (24.0, 14.0)


@entry("mine", 161)
def _(rng):
    objs = []
    objs += rockmass((0, 4.0, 0.0), (10.0, 6.0, 6.5), 2, rock_mat("mine_crag", (70, 66, 62), (122, 114, 102)))
    tm = B.timber_mat()
    # dark portal cut into the rock, timber frame
    objs.append(B.box(3.0, 3.0, 3.0, (0, -1.6, 0), B.dark_mat(), name="adit"))
    for x in (-1.6, 1.6):
        objs.append(B.box(0.35, 0.35, 3.3, (x, -3.2, 0), tm))
    objs.append(B.box(4.0, 0.4, 0.4, (0, -3.2, 3.2), tm))
    objs.append(B.box(4.4, 1.6, 0.25, (0, -2.6, 3.55), B.roof_mat("shingle")))
    # rails + cart with ore
    iron = B.flat_mat("rail", (70, 66, 62), rough=0.4, noise=0.05)
    for x in (-0.45, 0.45):
        objs.append(B.box(0.08, 7.0, 0.1, (x, -6.5, 0.1), iron))
    for i in range(10):
        objs.append(B.box(1.4, 0.18, 0.1, (0, -3.2 - i * 0.7, 0.02), tm))
    objs.append(B.box(1.2, 1.6, 0.8, (0, -6.0, 0.4), B.wood_mat("minecart", (100, 74, 50), plank=0.15,
                                                                   vertical=False), name="minecart"))
    objs.append(B.box(1.0, 1.4, 0.35, (0, -6.0, 1.15), B.flat_mat("ore", (70, 62, 58), noise=0.4, nscale=12.0)))
    # ore heap and a small hut
    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=1.8, radius2=0.2, depth=1.4, location=(3.6, -5.0, 0.7))
    heap = bpy.context.object
    heap.data.materials.append(B.flat_mat("ore_heap", (84, 74, 66), noise=0.45, bump=0.8, nscale=8.0))
    objs.append(heap)
    hut, _ = house(rng, w=3.6, d=3.0, roof="shingle", walls="wood", pitch=35, chimneys=0)
    for o in hut:
        o.location.x -= 5.5
        o.location.y -= 4.0
    objs += hut
    objs.append(B.box(0.12, 0.12, 2.4, (2.0, -3.3, 0), tm))
    objs.append(B.box(0.3, 0.3, 0.4, (2.0, -3.3, 2.4), B.flat_mat("lantern", (240, 190, 90),
                                                                  emission=((255, 180, 80), 4.0))))
    return objs, (18.0, 14.0)


def windmill_parts(rng, with_sails=True, sail_angle=0.0, sails_only=False):
    objs = []
    tower_m = B.brick_mat("mill_stone", (204, 194, 172), (186, 176, 156), (150, 142, 128), 0.6, 0.32, bump=0.5,
                          squash=0.8, noise_amt=0.12, mortar_size=0.02)
    hub = Vector((0, -2.95, 9.6))
    if not sails_only:
        objs.append(B.cyl(3.1, 9.0, (0, 0, 0), tower_m, verts=24, r2=2.4, name="tower"))
        objs.append(B.cyl(3.25, 0.5, (0, 0, 0), B.stone_mat("grey"), verts=24, name="base"))
        objs.append(B.cyl(2.6, 0.35, (0, 0, 8.9), B.timber_mat(), verts=24))
        objs.append(B.cone_roof(2.5, 3.6, 9.2, B.roof_mat("shingle"), verts=24, overhang=0.3))
        objs += B.door(0, -3.05, "S", w=1.2, h=2.2)
        objs += B.window(0, -2.85, 4.8, "S", w=0.6, h=0.9)
        objs += B.window(2.75, -0.6, 3.2, "E", w=0.6, h=0.8)
        objs.append(B.box(1.6, 1.0, 0.12, (0, -3.4, 2.6), B.timber_mat()))  # small balcony
    if with_sails:
        tm = B.flat_mat("sail_frame", (96, 72, 50), noise=0.1)
        cloth = B.flat_mat("sail_cloth", (196, 182, 156), noise=0.18, nscale=4.0)
        hb = B.cyl(0.45, 0.8, (0, 0, 0), tm, verts=12, rot=(math.pi / 2, 0, 0))
        hb.location = hub
        objs.append(hb)
        for k in range(4):
            a = sail_angle + k * math.pi / 2
            dirv = Vector((math.cos(a), 0, math.sin(a)))
            perp = Vector((-math.sin(a), 0, math.cos(a)))
            start = hub + Vector((0, -0.4, 0))
            end = start + dirv * 8.0
            objs.append(B.beam(start, end, 0.18, tm))
            # lattice + cloth panel on one side of the stock
            c0 = start + dirv * 1.6
            for i in range(6):
                p0 = c0 + dirv * (i * 1.2) + Vector((0, -0.12, 0))
                objs.append(B.beam(p0, p0 + perp * 1.5, 0.08, tm))
            for f_ in (0.05, 0.75, 1.45):
                q0 = c0 + perp * f_ + Vector((0, -0.12, 0))
                objs.append(B.beam(q0, q0 + dirv * 6.2, 0.06, tm))
            panel = B.box(6.3, 0.03, 1.4, (0, 0, 0), cloth, name="cloth")
            mid = c0 + dirv * 3.15 + perp * 0.75 + Vector((0, 0.02, 0))
            panel.location = mid - Vector((0, 0, 0.7))
            panel.rotation_euler = (0, -a, 0)
            # box base is at z: shift so the panel centre sits on mid
            panel.location = mid
            bpy.context.view_layer.update()
            panel.location -= (panel.matrix_world.to_3x3() @ Vector((0, 0, 0.7)))
            objs.append(panel)
    return objs


@entry("windmill", 171)
def _(rng):
    return windmill_parts(rng), (7.0, 7.0)


@entry("windmill_base", 172)
def _(rng):
    return windmill_parts(rng, with_sails=False), (7.0, 7.0)


for _k in range(8):
    CATALOG[f"windmill_sails_{_k}"] = (
        (lambda rng, k=_k: (windmill_parts(rng, with_sails=True, sail_angle=k * (math.pi / 2) / 8, sails_only=True),
                            (7.0, 7.0))), 173 + _k)


@entry("market", 181)
def _(rng):
    objs = []
    tm = B.timber_mat()
    awn_cols = [((160, 50, 40), (214, 200, 170)), ((50, 76, 128), (206, 180, 92)), ((66, 104, 58), (214, 200, 170)),
                ((158, 112, 50), (118, 46, 40)), ((128, 56, 96), (210, 194, 164))]
    goods = [(196, 60, 40), (220, 170, 50), (110, 150, 60), (170, 110, 60), (200, 190, 150), (150, 70, 120)]
    spots = [(-6.5, 3.0, 0.0), (-2.2, 3.4, 0.0), (2.2, 3.4, 0.0), (6.5, 3.0, 0.0), (-6.8, -2.8, 0.0),
             (6.8, -2.8, 0.0)]
    for i, (x, y, rot) in enumerate(spots):
        c1, c2 = awn_cols[i % len(awn_cols)]
        stripe = B.stripe_mat(f"awning{i}", c1, c2)
        for px in (-1.4, 1.4):
            for py in (-0.9, 0.9):
                objs.append(B.box(0.12, 0.12, 2.3, (x + px, y + py, 0), tm))
        objs.append(B.box(3.0, 1.6, 0.12, (x, y, 0.85), B.wood_mat("table", (140, 104, 66), plank=0.2, vertical=False)))
        aw = B.box(3.4, 2.4, 0.06, (x, y - 0.2, 2.25), stripe, rot=(0.28, 0, 0), name="awning")
        objs.append(aw)
        for k in range(5):
            gx = x - 1.1 + k * 0.55
            gc = goods[(i + k) % len(goods)]
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, location=(gx, y - 0.2, 1.1), segments=10, ring_count=6)
            gb = bpy.context.object
            gb.scale = (1.2, 1.0, 0.6)
            gb.data.materials.append(B.flat_mat(f"goods{gc[0]}", gc, noise=0.3, nscale=30.0))
            objs.append(gb)
        objs += crate(x + 1.9, y - 0.6, rot=0.3)
        if i % 2 == 0:
            objs += barrel(x - 1.9, y - 0.5)
    # central well
    st = B.stone_mat("grey")
    objs.append(B.cyl(1.2, 0.9, (0, 0, 0), st, verts=20, name="well"))
    objs.append(B.cyl(0.95, 0.92, (0, 0, 0.02), B.dark_mat(), verts=20))
    for x in (-1.0, 1.0):
        objs.append(B.box(0.15, 0.15, 2.4, (x, 0, 0.8), tm))
    wr, _ = B.gable_roof(2.6, 1.6, 3.1, 40, B.roof_mat("shingle"), overhang=0.2, thick=0.1)
    objs.append(wr)
    objs += sack(-3.5, -1.0) + sack(-3.0, -1.4) + crate(3.6, -1.2) + crate(3.8, -0.4, z=0.0, rot=0.5)
    objs += barrel(4.4, -1.5)
    return objs, (17.0, 10.0)


@entry("blacksmith", 191)
def _(rng):
    objs, _ = house(rng, w=6.5, d=5.4, roof="tile_brown", walls="stone", pitch=38, chimneys=0, door_x=1.4)
    for o in objs:
        o.location.x += 2.2
    # open forge shed on the west
    tm = B.timber_mat()
    for x in (-5.2, -1.2):
        for y in (-2.4, 2.4):
            objs.append(B.box(0.22, 0.22, 2.8, (x, y, 0), tm))
    sr, _ = B.gable_roof(4.6, 5.4, 2.8, 26, B.roof_mat("shingle"), overhang=0.4)
    sr.location = (-3.2, 0, 0)
    objs.append(sr)
    st = B.stone_mat("dark")
    objs.append(B.box(2.0, 1.6, 1.0, (-3.4, 1.2, 0), st, name="forge"))
    objs.append(B.box(1.4, 1.0, 0.12, (-3.4, 1.0, 1.0), B.flat_mat("coals", (255, 120, 40), noise=0.4, nscale=12.0,
                                                                   emission=((255, 110, 30), 12.0))))
    objs.append(B.box(1.0, 1.0, 4.6, (-3.4, 1.8, 0), st, name="forge_chimney"))
    objs.append(B.box(0.7, 0.35, 0.55, (-3.0, -0.8, 0.45), B.flat_mat("anvil", (54, 54, 58), rough=0.35, noise=0.05)))
    objs.append(B.cyl(0.3, 0.45, (-3.0, -0.8, 0), B.flat_mat("stump", (110, 84, 56), noise=0.2), verts=10))
    objs.append(B.box(1.4, 0.6, 0.55, (-5.4, -1.6, 0), B.wood_mat("trough", (104, 78, 52), plank=0.15)))
    objs.append(B.box(1.2, 0.45, 0.05, (-5.4, -1.6, 0.52), B.flat_mat("water", (40, 70, 90), rough=0.1, noise=0.0)))
    objs += barrel(-6.1, 0.8)
    rack = B.flat_mat("iron", (60, 58, 56), rough=0.5, noise=0.05)
    for i in range(4):
        objs.append(B.box(0.05, 0.05, 1.3, (-1.6 + i * 0.25, -2.6, 0.2), rack, rot=(0.15, 0, 0)))
    return objs, (12.0, 6.5)


@entry("barracks", 201)
def _(rng):
    objs, _ = house(rng, w=15.0, d=7.0, floors=2, fh=2.9, roof="tile_red", walls="timber", stone_ground=True,
                    chimneys=2, shutters=(70, 60, 50), pattern="brace", door_x=0.0)
    for o in objs:
        o.location.y += 3.5
    # training yard in front
    tm = B.timber_mat()
    straw = B.thatch_mat("dummy", (180, 154, 92))
    for x in (-5.0, -2.0, 2.5):
        objs.append(B.box(0.15, 0.15, 1.9, (x, -3.5, 0), tm))
        objs.append(B.box(0.8, 0.1, 0.12, (x, -3.5, 1.4), tm))
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.35, location=(x, -3.5, 1.2), segments=10, ring_count=6)
        sb = bpy.context.object
        sb.scale = (1, 1, 1.4)
        sb.data.materials.append(straw)
        objs.append(sb)
    rack = B.flat_mat("iron", (60, 58, 56), rough=0.5, noise=0.05)
    objs.append(B.box(2.6, 0.2, 0.15, (5.5, -2.0, 1.2), tm))
    for i in range(7):
        objs.append(B.box(0.05, 0.05, 2.4, (4.5 + i * 0.32, -2.1, 0.0), rack, rot=(0.12, 0, 0)))
    # banners
    for x, col in ((-7.9, (150, 34, 34)), (7.9, (40, 62, 120))):
        objs.append(B.box(0.12, 0.12, 6.2, (x, -0.2, 0), tm))
        objs.append(B.box(1.1, 0.04, 2.0, (x + 0.6, -0.25, 3.9), B.flat_mat(f"banner{col[0]}", col, noise=0.1)))
    objs += fence_line((-8.5, -6.5), (8.5, -6.5))
    objs += fence_line((-8.5, -6.5), (-8.5, -0.5)) + fence_line((8.5, -6.5), (8.5, -0.5))
    objs += barrel(-6.8, -1.2) + crate(6.9, -5.6, rot=0.2)
    return objs, (17.0, 14.0)


@entry("stable", 211)
def _(rng):
    objs = []
    wm = B.wood_mat("stable", (122, 90, 60), plank=0.24)
    W, D, H = 14.0, 6.0, 3.0
    objs.append(B.box(W + 0.3, D + 0.3, 0.3, (0, 0, 0), B.stone_mat("grey")))
    objs.append(B.box(W, D, H, (0, 0, 0.25), wm, name="stable"))
    objs += B.timber_frame(W, D, 0.25, H, B.timber_mat(), rng, pattern="plain", spacing=2.8, size=0.2)
    rf, zr = B.gable_roof(W, D, H + 0.25, 36, B.roof_mat("shingle"), overhang=0.6)
    objs.append(rf)
    for sgn in (-1, 1):
        g = B.gable_tri(D, H + 0.25, zr - H - 0.3, wm)
        g.rotation_euler = (0, 0, math.pi / 2)
        g.location = (sgn * W / 2, 0, 0)
        objs.append(g)
    dm = B.wood_mat("stall_door", (96, 66, 44), plank=0.16)
    for i in range(5):
        x = -W / 2 + 1.4 + i * 2.8
        objs.append(B.box(1.3, 0.1, 1.3, (x, -D / 2 - 0.05, 0.3), dm))
        objs.append(B.box(1.3, 0.1, 0.9, (x, -D / 2 - 0.02, 1.6), B.dark_mat()))
    objs.append(B.box(1.4, 0.1, 1.2, (0, -D / 2 - 0.05, zr - 2.3), dm))      # hay loft door
    objs += fence_line((W / 2 + 0.5, -D / 2 - 1.0), (W / 2 + 9.0, -D / 2 - 1.0))
    objs += fence_line((W / 2 + 9.0, -D / 2 - 1.0), (W / 2 + 9.0, D / 2))
    objs += fence_line((W / 2 + 0.5, D / 2), (W / 2 + 9.0, D / 2))
    objs.append(B.box(1.8, 0.6, 0.5, (W / 2 + 3.0, -1.0, 0), B.wood_mat("trough", (104, 78, 52), plank=0.15)))
    objs += hay_bale(-W / 2 - 1.2, -2.0, rot=0.1) + hay_bale(-W / 2 - 1.3, -1.3, rot=-0.1)
    objs += hay_bale(-W / 2 - 1.2, -1.7, z=0.5, rot=0.4)
    return objs, (24.0, 8.0)


@entry("tower", 221)
def _(rng):
    st = B.stone_mat("grey")
    objs = [B.cyl(3.0, 13.0, (0, 0, 0), st, verts=24, r2=2.7, name="tower")]
    objs.append(B.cyl(3.15, 0.6, (0, 0, 12.6), st, verts=24))
    objs += B.ring_crenellations(3.15, 13.2, st, n=14)
    objs.append(B.cyl(2.2, 2.4, (0, 0, 13.2), B.wood_mat("tower_top", (110, 82, 56), plank=0.2), verts=16))
    objs.append(B.cone_roof(2.2, 3.8, 15.6, B.roof_mat("slate"), verts=16, overhang=0.6))
    objs += B.door(0, -3.0, "S", w=1.1, h=2.2)
    for z in (5.0, 9.0):
        objs.append(B.box(0.25, 0.3, 0.9, (0, -2.9, z), B.dark_mat()))
    objs.append(B.box(0.25, 0.3, 0.9, (2.75, -0.8, 7.0), B.dark_mat(), rot=(0, 0, 1.2)))
    return objs, (6.5, 6.5)


def wall_segment(length=12.0, yaw=0.0, h=7.0, t=2.2):
    st = B.stone_mat("grey")
    objs = [B.box(length, t, h, (0, 0, 0), st, name="wall")]
    objs.append(B.box(length, t + 0.3, 0.5, (0, 0, -0.1), B.stone_mat("dark")))
    objs += B.crenellations(length, h, -t / 2 + 0.3, 0.6, st, merlon=1.0, gap=0.7, h=1.1)
    objs += B.crenellations(length, h, t / 2 - 0.3, 0.6, st, merlon=1.0, gap=0.7, h=0.8)
    for o in objs:
        o.location = Vector((math.cos(yaw) * o.location.x - math.sin(yaw) * o.location.y,
                             math.sin(yaw) * o.location.x + math.cos(yaw) * o.location.y, o.location.z))
        o.rotation_euler.z += yaw
    return objs


for _k, _yaw in enumerate((0.0, 45.0, 90.0, 135.0)):
    def _mk(rng, yaw=_yaw):
        return wall_segment(yaw=math.radians(yaw)), (12.0, 2.2)
    CATALOG[f"wall_{int(_yaw):03d}"] = (_mk, 230 + _k)


@entry("wall_tower", 241)
def _(rng):
    st = B.stone_mat("grey")
    objs = [B.cyl(3.2, 10.0, (0, 0, 0), st, verts=24, r2=3.0, name="wtower")]
    objs += B.ring_crenellations(3.1, 10.0, st, n=14)
    objs.append(B.cone_roof(2.6, 4.6, 10.3, B.roof_mat("slate"), verts=20, overhang=0.4))
    objs.append(B.cyl(2.6, 0.4, (0, 0, 9.9), B.timber_mat(), verts=20))
    for z in (4.0, 7.0):
        objs.append(B.box(0.25, 0.3, 0.9, (0, -3.1, z), B.dark_mat()))
    return objs, (6.4, 6.4)


@entry("gatehouse", 251)
def _(rng):
    st = B.stone_mat("grey")
    objs = []
    for x in (-4.2, 4.2):
        objs.append(B.cyl(2.8, 11.0, (x, 0, 0), st, verts=22, name="gtower"))
        objs += [o for o in B.ring_crenellations(2.8, 11.0, st, n=12)]
        for o in objs[-12:]:
            o.location.x += x
        objs.append(B.cone_roof(2.3, 4.2, 11.3, B.roof_mat("slate"), verts=18, overhang=0.4))
        objs[-1].location.x += x
    objs.append(B.box(6.0, 5.0, 9.0, (0, 0.6, 0), st, name="gate_block"))
    objs += B.crenellations(6.0, 9.0, -1.9, 0.6, st, merlon=0.9, gap=0.6, h=1.0)
    objs.append(B.box(3.0, 0.6, 4.2, (0, -1.95, 0), B.dark_mat(), name="gate_hole"))
    objs.append(B.box(2.8, 0.2, 3.4, (0, -2.1, 0.8), B.flat_mat("portcullis", (60, 54, 48), noise=0.1)))
    for x in (-1.6, 1.6):
        objs.append(B.box(0.4, 0.4, 0.4, (x, -2.4, 6.5), B.dark_mat()))
    b = B.box(1.0, 0.05, 2.2, (2.2, -2.0, 5.2), B.flat_mat("banner_blue", (40, 62, 120), noise=0.1))
    objs.append(b)
    return objs, (14.0, 7.0)


@entry("townhall", 261)
def _(rng):
    W, D = 14.0, 9.0
    objs = []
    st = B.stone_mat("warm")
    # ground floor: arcade
    objs.append(B.box(W + 0.3, D + 0.3, 0.4, (0, 0, -0.05), B.stone_mat("grey")))
    objs.append(B.box(W, D - 2.4, 3.6, (0, 1.2, 0.35), st, name="hall_core"))
    for i in range(6):
        x = -W / 2 + 0.5 + i * (W - 1.0) / 5
        objs.append(B.box(0.7, 0.7, 3.6, (x, -D / 2 + 0.35, 0.35), st, name="pier"))
    objs.append(B.box(W, 0.8, 0.6, (0, -D / 2 + 0.4, 3.35), st))
    objs += B.door(0, -D / 2 + 2.38, "S", w=1.6, h=2.6)
    for x in (-4.5, 4.5):
        objs += B.window(x, -D / 2 + 2.38, 1.2, "S", w=1.0, h=1.4)
    # timber upper floors
    pm = B.plaster_mat((228, 216, 188))
    tm = B.timber_mat()
    z = 3.95
    for fl in range(2):
        objs.append(B.box(W, D + 0.4, 3.0, (0, 0, z), pm, name="upper"))
        objs += B.timber_frame(W, D + 0.4, z, 3.0, tm, rng, pattern="cross" if fl == 0 else "brace", spacing=1.4)
        objs += B.place_windows(W, D + 0.4, z + 0.85, rng, faces="SE", spacing=2.3, shutters=(130, 40, 36),
                                wh=(0.8, 1.2))
        z += 3.0
    rf, zr = B.gable_roof(W, D + 0.4, z, 50, B.roof_mat("tile_red"), overhang=0.6)
    objs.append(rf)
    for sgn in (-1, 1):
        g = B.gable_tri(D + 0.4, z, zr - z - 0.05, pm)
        g.rotation_euler = (0, 0, math.pi / 2)
        g.location = (sgn * W / 2, 0, 0)
        objs.append(g)
    for k in range(3):
        dx = (k - 1) * 4.0
        y0 = -(D + 0.4) / 4
        zz = z + math.tan(math.radians(50)) * ((D + 0.4) / 2 - abs(y0)) - 0.4
        objs.append(B.box(1.4, 1.8, 1.6, (dx, y0 - 0.2, zz), pm))
        objs += B.window(dx, y0 - 1.11, zz + 0.3, "S", w=0.6, h=0.9)
        dr, _ = B.gable_roof(1.4, 2.1, zz + 1.6, 45, B.roof_mat("tile_red"), overhang=0.2, thick=0.1, ridge_x=False)
        dr.location = (dx, y0 - 0.25, 0)
        objs.append(dr)
    # bell tower on the east end
    bx = W / 2 - 1.8
    objs.append(B.box(3.2, 3.2, 8.0, (bx, 0.5, zr - 4.0), st, name="belltower"))
    objs.append(B.box(3.4, 3.4, 0.3, (bx, 0.5, zr + 4.0), tm))
    for x in (-1.3, 1.3):
        for y in (-1.3, 1.3):
            objs.append(B.box(0.3, 0.3, 2.4, (bx + x, 0.5 + y, zr + 4.3), tm))
    objs.append(B.cyl(0.6, 0.9, (bx, 0.5, zr + 4.9), B.flat_mat("bell", (170, 130, 60), rough=0.3, noise=0.05),
                      verts=12, r2=0.3))
    hr, hz = B.hip_roof(3.4, 3.4, zr + 6.7, 62, B.roof_mat("slate"), overhang=0.35)
    hr.location = (bx, 0.5, 0)
    objs.append(hr)
    objs.append(B.cyl(0.9, 0.08, (bx, -1.15, zr + 1.6), B.flat_mat("clock", (232, 220, 190), noise=0.0),
                      verts=20, rot=(math.pi / 2, 0, 0)))
    objs.append(B.box(0.12, 0.12, 2.0, (bx, 0.5, hz), B.flat_mat("iron", (60, 58, 56), rough=0.5, noise=0.05)))
    objs.append(B.box(0.9, 0.04, 0.6, (bx + 0.5, 0.5, hz + 1.3), B.flat_mat("banner_red", (150, 34, 34), noise=0.1)))
    return objs, (W + 1.0, D + 1.0)


@entry("castle", 271)
def _(rng):
    st = B.stone_mat("grey")
    slate = B.roof_mat("slate")
    objs = []
    # curtain wall: irregular pentagon ~ 46 x 36 m around the origin
    pts = [(-21, -15), (19, -16), (23, 6), (4, 19), (-20, 12)]
    for i in range(len(pts)):
        a = Vector((*pts[i], 0))
        b = Vector((*pts[(i + 1) % len(pts)], 0))
        d = b - a
        L = d.length
        yaw = math.atan2(d.y, d.x)
        mid = (a + b) / 2
        seg = [B.box(L, 2.4, 8.0, (0, 0, 0), st, name="curtain")]
        seg += B.crenellations(L - 4, 8.0, -0.9, 0.6, st, merlon=1.0, gap=0.7, h=1.1)
        for o in seg:
            x, y = o.location.x, o.location.y
            o.location = (mid.x + math.cos(yaw) * x - math.sin(yaw) * y,
                          mid.y + math.sin(yaw) * x + math.cos(yaw) * y, o.location.z)
            o.rotation_euler.z += yaw
        objs += seg
    for (x, y) in pts:
        objs.append(B.cyl(3.4, 11.0, (x, y, 0), st, verts=22, r2=3.1, name="ctower"))
        cr = B.ring_crenellations(3.2, 11.0, st, n=14)
        for o in cr:
            o.location.x += x
            o.location.y += y
        objs += cr
        objs.append(B.cyl(2.7, 1.4, (x, y, 11.0), B.timber_mat(), verts=18))
        c = B.cone_roof(2.7, 5.6, 12.4, slate, verts=20, overhang=0.5)
        c.location = (x, y, 0)
        objs.append(c)
    # gatehouse on the south wall
    gx, gy = -1.0, -15.5
    objs.append(B.box(8.0, 6.0, 11.0, (gx, gy, 0), st, name="gate"))
    objs += [o for o in B.crenellations(8.0, 11.0, gy - 2.7, 0.6, st, merlon=1.0, gap=0.6, h=1.1)]
    for o in objs[-5:]:
        o.location.x += gx
    objs.append(B.box(3.4, 0.6, 4.6, (gx, gy - 3.0, 0), B.dark_mat()))
    objs.append(B.box(3.0, 0.2, 3.6, (gx, gy - 3.2, 1.0), B.flat_mat("portcullis", (60, 54, 48), noise=0.1)))
    hr, _ = B.hip_roof(8.0, 6.0, 11.0, 48, slate, overhang=0.4)
    hr.location = (gx, gy, 0)
    objs.append(hr)
    # keep (donjon) with corner turrets
    kx, ky = 3.0, 4.0
    objs.append(B.box(12.0, 12.0, 21.0, (kx, ky, 0), st, name="keep"))
    objs.append(B.box(12.6, 12.6, 0.8, (kx, ky, 20.6), st))
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            tx, ty = kx + sx_ * 6.0, ky + sy_ * 6.0
            objs.append(B.cyl(1.6, 6.0, (tx, ty, 17.5), st, verts=16))
            c = B.cone_roof(1.6, 4.4, 23.5, slate, verts=16, overhang=0.3)
            c.location = (tx, ty, 0)
            objs.append(c)
    kr, kz = B.hip_roof(10.5, 10.5, 21.4, 58, slate, overhang=0.3)
    kr.location = (kx, ky, 0)
    objs.append(kr)
    for z in (6.0, 11.0, 15.5):
        for x in (-3.0, 0.0, 3.0):
            objs += B.window(kx + x, ky - 6.02, z, "S", w=0.6, h=1.4)
    for z in (8.0, 14.0):
        objs += B.window(kx + 6.02, ky, z, "E", w=0.6, h=1.4)
    objs.append(B.box(0.12, 0.12, 3.0, (kx, ky, kz), B.flat_mat("iron", (60, 58, 56), rough=0.5, noise=0.05)))
    objs.append(B.box(1.6, 0.04, 1.0, (kx + 0.85, ky, kz + 1.9), B.flat_mat("banner_blue", (40, 62, 120), noise=0.1)))
    # great hall along the west wall
    hall, _ = house(rng, w=14.0, d=7.0, floors=2, fh=3.2, roof="slate", walls="stone", chimneys=1, door_x=2.0)
    for o in hall:
        o.location.x -= 9.5
        o.location.y += 3.0
    objs += hall
    # courtyard ground (packed earth) and a well
    objs.append(B.box(38.0, 28.0, 0.06, (0, 1.0, 0), B.flat_mat("yard", (150, 128, 96), noise=0.3, nscale=3.0)))
    objs.append(B.cyl(1.0, 0.8, (-4.0, -6.0, 0), st, verts=16))
    objs += barrel(6.0, -9.0) + barrel(6.8, -9.4) + crate(10.0, -10.0) + cart(-12.0, -9.0, rot=0.2, load="hay")
    rotate_all(objs, math.pi / 2)
    return objs, (40.0, 50.0)


def rotate_all(objs, yaw):
    c, s_ = math.cos(yaw), math.sin(yaw)
    for o in objs:
        x, y = o.location.x, o.location.y
        o.location = (c * x - s_ * y, s_ * x + c * y, o.location.z)
        o.rotation_euler.z += yaw


def bridge_stone(length=48.0, width=6.0, arches=3, yaw=0.0, deck_z=6.0):
    st = B.stone_mat("warm")
    objs = []
    span = length / arches
    for i in range(arches + 1):
        x = -length / 2 + i * span
        objs.append(B.box(2.2, width, deck_z, (x, 0, -0.2), st, name="pier"))
        objs.append(B.box(2.9, width + 0.7, 0.7, (x, 0, -0.2), B.stone_mat("dark")))
    for i in range(arches):
        x0 = -length / 2 + i * span
        # arch spandrel: deck slab + arch ring approximated by segments
        n = 10
        for k in range(n):
            a0 = math.pi * k / n
            a1 = math.pi * (k + 1) / n
            r = span / 2 - 1.1
            cx = x0 + span / 2
            rz = min(r * 0.45, deck_z - 1.2)
            p0 = Vector((cx - math.cos(a0) * r, 0, deck_z - 1.0 - rz + math.sin(a0) * rz))
            p1 = Vector((cx - math.cos(a1) * r, 0, deck_z - 1.0 - rz + math.sin(a1) * rz))
            seg = B.beam(p0, p1, 0.8, st)
            seg.scale.x = width / 0.8
            objs.append(seg)
        objs.append(B.box(span, width, 1.6, (x0 + span / 2, 0, deck_z - 1.6), st))
    objs.append(B.box(length + 4.0, width, 0.3, (0, 0, deck_z), B.brick_mat("cobble", (130, 120, 104), (110, 102, 90),
                                                                             (70, 66, 60), 0.3, 0.25, bump=0.9)))
    for y in (-width / 2 + 0.25, width / 2 - 0.25):
        objs.append(B.box(length + 4.0, 0.5, 1.0, (0, y, deck_z + 0.3), st, name="parapet"))
    for o in objs:
        o.location = Vector((math.cos(yaw) * o.location.x - math.sin(yaw) * o.location.y,
                             math.sin(yaw) * o.location.x + math.cos(yaw) * o.location.y, o.location.z))
        o.rotation_euler.z += yaw
    return objs


def bridge_wood(length=24.0, width=4.0, yaw=0.0, deck_z=2.6):
    tm = B.timber_mat()
    wm = B.wood_mat("deck", (132, 100, 66), plank=0.3, vertical=True)
    objs = []
    n = int(length / 4)
    for i in range(n + 1):
        x = -length / 2 + i * length / n
        for y in (-width / 2 + 0.3, width / 2 - 0.3):
            objs.append(B.box(0.35, 0.35, deck_z + 0.2, (x, y, -0.2), tm))
        objs.append(B.beam((x, -width / 2 + 0.3, 0.2), (x, width / 2 - 0.3, deck_z - 0.3), 0.18, tm))
    objs.append(B.box(length + 2.0, width, 0.25, (0, 0, deck_z), wm, name="deck"))
    for y in (-width / 2 + 0.1, width / 2 - 0.1):
        objs.append(B.box(length + 2.0, 0.14, 0.14, (0, y, deck_z + 1.0), tm))
        for i in range(n * 2 + 1):
            objs.append(B.box(0.12, 0.12, 1.0, (-length / 2 + i * length / (n * 2), y, deck_z), tm))
    for o in objs:
        o.location = Vector((math.cos(yaw) * o.location.x - math.sin(yaw) * o.location.y,
                             math.sin(yaw) * o.location.x + math.cos(yaw) * o.location.y, o.location.z))
        o.rotation_euler.z += yaw
    return objs


# demo bridges: exact crossings of the Fiume Argento and the Torrente Bianco (origin = water surface
# at the river centre line; yaw in Blender coordinates)
@entry("bridge_argento", 281)
def _(rng):
    return bridge_stone(length=56.0, width=6.0, arches=4, yaw=math.atan2(-0.827, 0.562), deck_z=3.2), (56.0, 6.0)


@entry("bridge_bianco", 282)
def _(rng):
    return bridge_wood(length=32.0, width=4.2, yaw=math.atan2(-0.921, -0.39), deck_z=2.1), (32.0, 4.2)


# market stalls and well as separate sprites (citizens can walk between them with correct depth)
AWNINGS = [((160, 50, 40), (214, 200, 170)), ((50, 76, 128), (206, 180, 92)), ((66, 104, 58), (214, 200, 170)),
           ((158, 112, 50), (118, 46, 40)), ((128, 56, 96), (210, 194, 164))]
GOODS = [(196, 60, 40), (220, 170, 50), (110, 150, 60), (170, 110, 60), (200, 190, 150), (150, 70, 120)]


def stall(i):
    tm = B.timber_mat()
    c1, c2 = AWNINGS[i % len(AWNINGS)]
    stripe = B.stripe_mat(f"awning{i}", c1, c2)
    objs = []
    for px in (-1.4, 1.4):
        for py in (-0.9, 0.9):
            objs.append(B.box(0.12, 0.12, 2.3, (px, py, 0), tm))
    objs.append(B.box(3.0, 1.6, 0.12, (0, 0, 0.85), B.wood_mat("table", (140, 104, 66), plank=0.2, vertical=False)))
    objs.append(B.box(3.4, 2.4, 0.06, (0, -0.2, 2.25), stripe, rot=(0.28, 0, 0), name="awning"))
    for k in range(5):
        gc = GOODS[(i + k) % len(GOODS)]
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, location=(-1.1 + k * 0.55, -0.2, 1.1), segments=10,
                                             ring_count=6)
        gb = bpy.context.object
        gb.scale = (1.2, 1.0, 0.6)
        gb.data.materials.append(B.flat_mat(f"goods{gc[0]}", gc, noise=0.3, nscale=30.0))
        objs.append(gb)
    objs += crate(1.9, -0.6, rot=0.3)
    if i % 2 == 0:
        objs += barrel(-1.9, -0.5)
    return objs


for _i in range(5):
    CATALOG[f"stall_{'abcde'[_i]}"] = ((lambda rng, i=_i: (stall(i), (4.0, 2.4))), 290 + _i)


@entry("well", 296)
def _(rng):
    tm = B.timber_mat()
    st = B.stone_mat("grey")
    objs = [B.cyl(1.2, 0.9, (0, 0, 0), st, verts=20, name="well"), B.cyl(0.95, 0.92, (0, 0, 0.02), B.dark_mat(), verts=20)]
    for x in (-1.0, 1.0):
        objs.append(B.box(0.15, 0.15, 2.4, (x, 0, 0.8), tm))
    wr, _ = B.gable_roof(2.6, 1.6, 3.1, 40, B.roof_mat("shingle"), overhang=0.2, thick=0.1)
    objs.append(wr)
    objs.append(B.cyl(0.25, 0.4, (0.6, -0.9, 0), B.wood_mat("bucket", (120, 88, 56), plank=0.1), verts=10))
    return objs, (2.6, 2.6)


# fence segments (4 m) at 8 headings for field borders
for _k in range(8):
    _deg = _k * 22.5
    CATALOG[f"fence_{int(round(_deg * 10)):04d}"] = (
        (lambda rng, deg=_deg: (fence_line((-2.0 * math.cos(math.radians(deg)), -2.0 * math.sin(math.radians(deg))),
                                           (2.0 * math.cos(math.radians(deg)), 2.0 * math.sin(math.radians(deg))),
                                           post=2.0), (4.0, 0.2))), 300 + _k)


# small props
@entry("prop_barrels", 311)
def _(rng):
    return barrel(0, 0) + barrel(0.8, 0.2) + barrel(0.35, 0.75), (1.6, 1.4)


@entry("prop_crates", 312)
def _(rng):
    return crate(0, 0) + crate(0.75, 0.1, rot=0.3) + crate(0.3, 0.05, z=0.6, rot=0.15), (1.6, 1.0)


@entry("prop_cart_hay", 313)
def _(rng):
    return cart(0, 0, rot=0.4, load="hay"), (3.4, 1.6)


@entry("prop_cart", 314)
def _(rng):
    return cart(0, 0, rot=-0.3), (3.4, 1.6)


@entry("prop_logs", 315)
def _(rng):
    return log_pile(0, 0, n=9, length=3.5, r=0.22), (3.5, 2.0)


@entry("prop_haystack", 316)
def _(rng):
    return haystack(0, 0), (3.0, 3.0)


@entry("prop_bales", 317)
def _(rng):
    return hay_bale(0, 0) + hay_bale(0.9, 0.4, rot=0.5) + hay_bale(0.4, 0.1, z=0.5, rot=0.2), (2.0, 1.4)


@entry("prop_sacks", 318)
def _(rng):
    return sack(0, 0) + sack(0.5, 0.3) + sack(-0.3, 0.45), (1.4, 1.2)


@entry("prop_scarecrow", 319)
def _(rng):
    tm = B.timber_mat()
    objs = [B.box(0.1, 0.1, 2.2, (0, 0, 0), tm), B.box(1.6, 0.08, 0.08, (0, 0, 1.6), tm)]
    objs.append(B.box(0.6, 0.3, 0.8, (0, 0, 1.0), B.flat_mat("rags", (120, 90, 70), noise=0.3, nscale=10)))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, location=(0, 0, 2.0), segments=10, ring_count=6)
    objs.append(bpy.context.object)
    objs[-1].data.materials.append(B.thatch_mat("hay", (176, 150, 84)))
    objs.append(B.cyl(0.35, 0.25, (0, 0, 2.12), B.thatch_mat("hat", (150, 118, 64)), verts=12, r2=0.12))
    return objs, (1.6, 0.4)


# rotated house variants (facade towards east / west) for north-south streets
def _rotated(base, yaw):
    def fn(rng):
        f, _seed = CATALOG[base]
        objs, fp = f(rng)
        rotate_all(objs, yaw)
        return objs, (fp[1], fp[0])
    return fn


for _b in ("house_a", "house_b", "house_c", "house_d", "house_e", "house_rich_a", "house_rich_b", "house_rich_c"):
    CATALOG[_b + "_e"] = (_rotated(_b, math.pi / 2), CATALOG[_b][1])
    CATALOG[_b + "_w"] = (_rotated(_b, -math.pi / 2), CATALOG[_b][1])


@entry("gatehouse_ns", 252)
def _(rng):
    f, _seed = CATALOG["gatehouse"]
    objs, fp = f(rng)
    rotate_all(objs, math.pi / 2)
    return objs, (fp[1], fp[0])


def grade(rgb):
    l = (rgb * np.array([0.299, 0.587, 0.114])).sum(-1, keepdims=True)
    return np.clip(l + (rgb - l) * 1.05, 0, None)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--meta-only", action="store_true", help="only record chimney positions in buildings.json")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    os.makedirs(OUT, exist_ok=True)
    meta_path = os.path.join(OUT, "buildings.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    only = [x for x in args.only.split(",") if x]
    names = [n for n in CATALOG if not only or any(n == o or n.startswith(o) for o in only)]
    R.reset_scene()
    for name in names:
        fn, seed = CATALOG[name]
        R.clear_objects()
        B._M.clear()
        for m in list(bpy.data.materials):
            if m.name != "ground_mat":
                bpy.data.materials.remove(m)
        rng = random.Random(seed)
        objs, fp = fn(rng)
        bpy.context.view_layer.update()
        chims = []
        for o in objs:
            if o.name.startswith("chimney_cap"):
                p_ = o.matrix_world.translation
                sx_, sy_ = R.screen_xy(p_ + Vector((0, 0, 0.3)))
                chims.append([round(sx_ * R.K.SPRITE_PX_PER_M, 1), round(-sy_ * R.K.SPRITE_PX_PER_M, 1)])
        if args.dry:
            print("built", name, len(objs), "objects", R.object_extent(objs), chims, flush=True)
            continue
        if args.meta_only:
            if name in meta:
                meta[name]["chimneys"] = chims
                json.dump(meta, open(meta_path, "w"), indent=1)
            continue
        res = R.render_object(objs, name, samples=args.samples, shadow_samples=16)
        body, sh, anchor = R.finish(res, grade=grade)
        body, sh, anchor = R.trim(body, sh, anchor)
        Image.fromarray(body, "RGBA").save(os.path.join(OUT, f"{name}.png"), optimize=True)
        Image.fromarray(sh, "L").save(os.path.join(OUT, f"{name}_sh.png"), optimize=True)
        meta[name] = {"anchor": [round(anchor[0], 2), round(anchor[1], 2)], "size": [body.shape[1], body.shape[0]],
                      "footprint": [round(fp[0], 2), round(fp[1], 2)], "chimneys": chims}
        json.dump(meta, open(meta_path, "w"), indent=1)
        print("rendered", name, body.shape, flush=True)


if __name__ == "__main__":
    main()
