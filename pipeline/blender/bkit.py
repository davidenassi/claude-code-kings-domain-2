"""Architecture kit for King's Domain buildings (Blender 4.5, procedural, metres).

Convention: building origin = ground centre, main facade faces SOUTH (-Y in Blender), i.e. the camera.
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

import kdrender as R


def lin(c):
    return R.srgb_to_lin(c)


# ------------------------------------------------------------------------------------------------
# materials
_M: dict[str, bpy.types.Material] = {}


def _wall_vector(nt, scale=1.0):
    """Vector (x + y, z) in object space: one continuous 2D mapping around a box."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    nt.links.new(sep.outputs["X"], add.inputs[0])
    nt.links.new(sep.outputs["Y"], add.inputs[1])
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(add.outputs["Value"], comb.inputs["X"])
    nt.links.new(sep.outputs["Z"], comb.inputs["Y"])
    return comb.outputs["Vector"], tc


def _noise_mul(nt, col_socket, base_out, scale=2.0, amount=0.25, coord=None):
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 5.0
    if coord is not None:
        nt.links.new(coord, noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (1 - amount, 1 - amount, 1 - amount, 1)
    ramp.color_ramp.elements[1].color = (1 + amount * 0.6, 1 + amount * 0.6, 1 + amount * 0.6, 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(base_out, mix.inputs["A"])
    nt.links.new(ramp.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], col_socket)
    return noise


def brick_mat(name, c1, c2, mortar, bw, rh, uv=False, bump=0.6, offset=0.5, squash=1.0, noise_amt=0.18,
              rough=0.85, mortar_size=0.015):
    """Bricks / stones / tiles: Brick texture on wall-mapping (or UV for roofs)."""
    if name in _M:
        return _M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = rough
    p.inputs["Specular IOR Level"].default_value = 0.2
    if uv:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        vec = tc.outputs["UV"]
    else:
        vec, tc = _wall_vector(nt)
    br = nt.nodes.new("ShaderNodeTexBrick")
    br.offset = offset
    br.squash = squash
    br.squash_frequency = 2
    br.inputs["Color1"].default_value = (*lin(c1), 1)
    br.inputs["Color2"].default_value = (*lin(c2), 1)
    br.inputs["Mortar"].default_value = (*lin(mortar), 1)
    br.inputs["Scale"].default_value = 1.0
    br.inputs["Mortar Size"].default_value = mortar_size
    br.inputs["Mortar Smooth"].default_value = 0.3
    br.inputs["Bias"].default_value = 0.0
    br.inputs["Brick Width"].default_value = bw
    br.inputs["Row Height"].default_value = rh
    nt.links.new(vec, br.inputs["Vector"])
    _noise_mul(nt, p.inputs["Base Color"], br.outputs["Color"], scale=1.5, amount=noise_amt)
    if bump > 0:
        b = nt.nodes.new("ShaderNodeBump")
        b.inputs["Strength"].default_value = bump
        b.inputs["Distance"].default_value = 0.03
        nt.links.new(br.outputs["Fac"], b.inputs["Height"])
        nt.links.new(b.outputs["Normal"], p.inputs["Normal"])
    _M[name] = m
    return m


def flat_mat(name, col, rough=0.85, noise=0.12, bump=0.15, nscale=3.0, emission=None):
    if name in _M:
        return _M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = rough
    p.inputs["Specular IOR Level"].default_value = 0.2
    rgb = nt.nodes.new("ShaderNodeRGB")
    rgb.outputs[0].default_value = (*lin(col), 1)
    if noise > 0:
        n = _noise_mul(nt, p.inputs["Base Color"], rgb.outputs[0], scale=nscale, amount=noise)
        if bump > 0:
            b = nt.nodes.new("ShaderNodeBump")
            b.inputs["Strength"].default_value = bump
            nt.links.new(n.outputs["Fac"], b.inputs["Height"])
            nt.links.new(b.outputs["Normal"], p.inputs["Normal"])
    else:
        nt.links.new(rgb.outputs[0], p.inputs["Base Color"])
    if emission:
        p.inputs["Emission Color"].default_value = (*lin(emission[0]), 1)
        p.inputs["Emission Strength"].default_value = emission[1]
    _M[name] = m
    return m


def wood_mat(name, col, plank=0.22, vertical=True):
    if name in _M:
        return _M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.9
    vec, tc = _wall_vector(nt)
    br = nt.nodes.new("ShaderNodeTexBrick")
    br.offset = 0.0
    br.inputs["Color1"].default_value = (*lin(col), 1)
    c2 = tuple(max(0, int(v * 0.82)) for v in col)
    br.inputs["Color2"].default_value = (*lin(c2), 1)
    br.inputs["Mortar"].default_value = (*lin(tuple(int(v * 0.45) for v in col)), 1)
    br.inputs["Mortar Size"].default_value = 0.01
    if vertical:
        br.inputs["Brick Width"].default_value = plank
        br.inputs["Row Height"].default_value = 3.0
    else:
        br.inputs["Brick Width"].default_value = 3.0
        br.inputs["Row Height"].default_value = plank
    nt.links.new(vec, br.inputs["Vector"])
    _noise_mul(nt, p.inputs["Base Color"], br.outputs["Color"], scale=4.0, amount=0.2)
    b = nt.nodes.new("ShaderNodeBump")
    b.inputs["Strength"].default_value = 0.5
    b.inputs["Distance"].default_value = 0.02
    nt.links.new(br.outputs["Fac"], b.inputs["Height"])
    nt.links.new(b.outputs["Normal"], p.inputs["Normal"])
    _M[name] = m
    return m


def stripe_mat(name, c1, c2, width=0.35):
    """Striped cloth (awnings, banners): crisp bands along the object's X axis."""
    if name in _M:
        return _M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.9
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 1.0 / (2.0 * width)
    nt.links.new(sep.outputs["X"], mul.inputs[0])
    fr = nt.nodes.new("ShaderNodeMath")
    fr.operation = "FRACT"
    nt.links.new(mul.outputs[0], fr.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = (*lin(c1), 1)
    ramp.color_ramp.elements[1].position = 0.5
    ramp.color_ramp.elements[1].color = (*lin(c2), 1)
    nt.links.new(fr.outputs[0], ramp.inputs["Fac"])
    _noise_mul(nt, p.inputs["Base Color"], ramp.outputs["Color"], scale=3.0, amount=0.12)
    _M[name] = m
    return m


def thatch_mat(name="thatch", col=(150, 118, 64)):
    if name in _M:
        return _M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 1.0
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 18.0
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 6.0
    nt.links.new(tc.outputs["UV"], wave.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*lin(tuple(int(v * 0.62) for v in col)), 1)
    ramp.color_ramp.elements[1].color = (*lin(col), 1)
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    _noise_mul(nt, p.inputs["Base Color"], ramp.outputs["Color"], scale=2.0, amount=0.25)
    b = nt.nodes.new("ShaderNodeBump")
    b.inputs["Strength"].default_value = 0.8
    nt.links.new(wave.outputs["Fac"], b.inputs["Height"])
    nt.links.new(b.outputs["Normal"], p.inputs["Normal"])
    _M[name] = m
    return m


ROOF_COLORS = {
    "tile_red": ((114, 56, 42), (94, 48, 38)),
    "tile_brown": ((104, 64, 48), (84, 54, 42)),
    "tile_orange": ((126, 72, 48), (106, 60, 42)),
    "slate": ((62, 72, 98), (50, 58, 82)),
    "slate_grey": ((80, 82, 88), (66, 68, 74)),
    "shingle": ((98, 80, 62), (80, 66, 52)),
}


def tile_mat(name, c1, c2, row=0.21, width=0.26, depth=0.9, rough=0.7):
    """Overlapping roof tiles: rows with a dark lap line, staggered joints, per-tile colour."""
    if name in _M:
        return _M[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = rough
    p.inputs["Specular IOR Level"].default_value = 0.25
    tc = nt.nodes.new("ShaderNodeTexCoord")
    br = nt.nodes.new("ShaderNodeTexBrick")
    br.offset = 0.5
    br.inputs["Color1"].default_value = (*lin(c1), 1)
    br.inputs["Color2"].default_value = (*lin(c2), 1)
    br.inputs["Mortar"].default_value = (*lin(tuple(int(v * 0.55) for v in c2)), 1)
    br.inputs["Mortar Size"].default_value = 0.012
    br.inputs["Mortar Smooth"].default_value = 0.6
    br.inputs["Brick Width"].default_value = width
    br.inputs["Row Height"].default_value = row
    nt.links.new(tc.outputs["UV"], br.inputs["Vector"])
    # lap shading: saw tooth along the slope (v), dark just below each row edge
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["UV"], sep.inputs["Vector"])
    div = nt.nodes.new("ShaderNodeMath")
    div.operation = "DIVIDE"
    div.inputs[1].default_value = row
    nt.links.new(sep.outputs["Y"], div.inputs[0])
    fr = nt.nodes.new("ShaderNodeMath")
    fr.operation = "FRACT"
    nt.links.new(div.outputs[0], fr.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (1.08, 1.08, 1.08, 1)
    ramp.color_ramp.elements[1].position = 0.92
    ramp.color_ramp.elements[1].color = (0.82, 0.82, 0.82, 1)
    e = ramp.color_ramp.elements.new(1.0)
    e.color = (0.45, 0.45, 0.45, 1)
    nt.links.new(fr.outputs[0], ramp.inputs["Fac"])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(br.outputs["Color"], mul.inputs["A"])
    nt.links.new(ramp.outputs["Color"], mul.inputs["B"])
    _noise_mul(nt, p.inputs["Base Color"], mul.outputs["Result"], scale=0.8, amount=0.16)
    b = nt.nodes.new("ShaderNodeBump")
    b.inputs["Strength"].default_value = depth
    b.inputs["Distance"].default_value = 0.04
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "SUBTRACT"
    nt.links.new(fr.outputs[0], add.inputs[0])
    nt.links.new(br.outputs["Fac"], add.inputs[1])
    nt.links.new(add.outputs[0], b.inputs["Height"])
    nt.links.new(b.outputs["Normal"], p.inputs["Normal"])
    _M[name] = m
    return m


def roof_mat(kind):
    if kind == "thatch":
        return thatch_mat()
    c1, c2 = ROOF_COLORS[kind]
    if kind.startswith("slate"):
        return tile_mat("roof_" + kind, c1, c2, row=0.17, width=0.3, depth=0.6, rough=0.55)
    if kind == "shingle":
        return tile_mat("roof_" + kind, c1, c2, row=0.2, width=0.2, depth=0.8, rough=0.9)
    return tile_mat("roof_" + kind, c1, c2)


def plaster_mat(col):
    return flat_mat(f"plaster_{col[0]}_{col[1]}_{col[2]}", col, rough=0.95, noise=0.14, bump=0.12, nscale=2.0)


def stone_mat(kind="grey"):
    cols = {"grey": ((150, 144, 132), (124, 120, 112), (92, 88, 82)),
            "warm": ((168, 152, 126), (140, 126, 104), (100, 92, 80)),
            "dark": ((112, 108, 104), (92, 90, 88), (64, 62, 60))}[kind]
    return brick_mat("stone_" + kind, cols[0], cols[1], cols[2], 0.55, 0.3, bump=0.8, squash=0.7,
                     noise_amt=0.2, mortar_size=0.03)


def timber_mat():
    return flat_mat("timber", (62, 42, 30), rough=0.9, noise=0.2, bump=0.2, nscale=8.0)


def dark_mat():
    return flat_mat("window_dark", (22, 20, 22), rough=0.4, noise=0.0)


# ------------------------------------------------------------------------------------------------
# primitives
def obj_from_bm(bm, name, mat=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if mat:
        o.data.materials.append(mat)
    return o


def box(sx, sy, sz, loc=(0, 0, 0), mat=None, rot=(0, 0, 0), name="box", bevel=0.0):
    """Axis box with its base at loc.z (not centred vertically)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z = (v.co.z + 0.5) * sz
    o = obj_from_bm(bm, name, mat)
    o.location = loc
    o.rotation_euler = rot
    if bevel > 0:
        m = o.modifiers.new("bev", "BEVEL")
        m.width = bevel
        m.segments = 2
    return o


def cyl(r, h, loc=(0, 0, 0), mat=None, verts=16, r2=None, rot=(0, 0, 0), name="cyl"):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=h,
                                    location=(loc[0], loc[1], loc[2] + h / 2), rotation=rot)
    o = bpy.context.object
    o.name = name
    if mat:
        o.data.materials.append(mat)
    return o


def beam(a, b, size, mat):
    """Square beam from point a to b."""
    a = Vector(a)
    b = Vector(b)
    d = b - a
    o = box(size, size, d.length, loc=(0, 0, 0), mat=mat, name="beam")
    o.location = a
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    return o


def gable_roof(w, d, z0, pitch_deg, mat, overhang=0.45, thick=0.16, ridge_x=True, name="roof", loc=(0, 0)):
    """Two-slope roof over a w (x) by d (y) footprint, eaves at z0. UV in metres (u along ridge)."""
    if not ridge_x:
        w, d = d, w
    hw = w / 2 + overhang
    hd = d / 2 + overhang
    rise = math.tan(math.radians(pitch_deg)) * (d / 2)
    drop = math.tan(math.radians(pitch_deg)) * overhang
    zr = z0 + rise
    ze = z0 - drop
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    slope_len = math.hypot(hd, zr - ze)
    for side in (-1, 1):
        vs = [bm.verts.new((-hw, side * hd, ze)), bm.verts.new((hw, side * hd, ze)),
              bm.verts.new((hw, 0, zr)), bm.verts.new((-hw, 0, zr))]
        f = bm.faces.new(vs if side == 1 else vs[::-1])
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (co.x + hw, (zr - co.z) / (zr - ze) * slope_len)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    o = obj_from_bm(bm, name, mat)
    sol = o.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = thick
    sol.offset = -1
    if not ridge_x:
        o.rotation_euler = (0, 0, math.pi / 2)
    o.location = (loc[0], loc[1], 0)
    return o, zr


def gable_tri(width, z0, rise, mat, thick=0.25, name="gable"):
    """Triangular gable infill in the XZ plane centred on x=0 (rotate/place it afterwards)."""
    bm = bmesh.new()
    pts = [(-width / 2, z0), (width / 2, z0), (0, z0 + rise)]
    a = [bm.verts.new((x, -thick / 2, z)) for x, z in pts]
    b = [bm.verts.new((x, thick / 2, z)) for x, z in pts]
    bm.faces.new(a[::-1])
    bm.faces.new(b)
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((a[i], a[j], b[j], b[i]))
    return obj_from_bm(bm, name, mat)


def hip_roof(w, d, z0, pitch_deg, mat, overhang=0.45, thick=0.16, name="hiproof"):
    hw = w / 2 + overhang
    hd = d / 2 + overhang
    t = math.tan(math.radians(pitch_deg))
    rise = t * min(w, d) / 2
    drop = t * overhang
    ze = z0 - drop
    zr = z0 + rise
    inset = min(hw, hd)
    rx = max(hw - inset, 0.0)
    ry = max(hd - inset, 0.0)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    e = [bm.verts.new((-hw, -hd, ze)), bm.verts.new((hw, -hd, ze)), bm.verts.new((hw, hd, ze)),
         bm.verts.new((-hw, hd, ze))]
    if rx >= ry:
        r1 = bm.verts.new((-rx, 0, zr))
        r2 = bm.verts.new((rx, 0, zr))
        faces = [(e[0], e[1], r2, r1), (e[1], e[2], r2), (e[2], e[3], r1, r2), (e[3], e[0], r1)]
    else:
        r1 = bm.verts.new((0, -ry, zr))
        r2 = bm.verts.new((0, ry, zr))
        faces = [(e[0], e[1], r1), (e[1], e[2], r2, r1), (e[2], e[3], r2), (e[3], e[0], r1, r2)]
    for fv in faces:
        f = bm.faces.new(fv)
        f.normal_update()
        n = f.normal
        hdir = Vector((n.x, n.y, 0)).normalized() if n.xy.length > 1e-6 else Vector((0, -1, 0))
        udir = Vector((-hdir.y, hdir.x, 0))
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (co.dot(udir), -(co.dot(hdir)) * 1.0 / math.cos(math.radians(pitch_deg)))
    o = obj_from_bm(bm, name, mat)
    sol = o.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = thick
    sol.offset = -1
    return o, zr


def cone_roof(r, h, z0, mat, verts=20, overhang=0.35, name="cone"):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    rr = r + overhang
    ring = [bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z0)) for a in
            [i * 2 * math.pi / verts for i in range(verts)]]
    apex = bm.verts.new((0, 0, z0 + h))
    slant = math.hypot(rr, h)
    for i in range(verts):
        f = bm.faces.new((ring[i], ring[(i + 1) % verts], apex))
        for loop in f.loops:
            co = loop.vert.co
            ang = math.atan2(co.y, co.x)
            if loop.vert is apex:
                ang = (i + 0.5) * 2 * math.pi / verts - math.pi
            u = (i + (1 if loop.vert is ring[(i + 1) % verts] else 0.5 if loop.vert is apex else 0)) * \
                (2 * math.pi * rr / verts)
            loop[uv].uv = (u, (z0 + h - co.z) / h * slant)
    o = obj_from_bm(bm, name, mat)
    sol = o.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = 0.12
    sol.offset = -1
    bpy.context.view_layer.objects.active = o
    return o


def crenellations(length, z, y, thick, mat, merlon=0.8, gap=0.6, h=0.9, x0=None, axis="x"):
    objs = []
    n = max(1, int(length / (merlon + gap)))
    span = n * (merlon + gap) - gap
    start = -span / 2 if x0 is None else x0
    for i in range(n):
        c = start + i * (merlon + gap) + merlon / 2
        if axis == "x":
            objs.append(box(merlon, thick, h, (c, y, z), mat, name="merlon"))
        else:
            objs.append(box(thick, merlon, h, (y, c, z), mat, name="merlon"))
    return objs


def ring_crenellations(r, z, mat, n=12, h=0.9, thick=0.5):
    objs = []
    for i in range(n):
        a = i * 2 * math.pi / n
        o = box(r * 2 * math.pi / n * 0.55, thick, h, (math.cos(a) * (r - thick / 2), math.sin(a) * (r - thick / 2), z),
                mat, rot=(0, 0, a + math.pi / 2), name="merlon")
        objs.append(o)
    return objs


# ------------------------------------------------------------------------------------------------
# openings
def window(x, y, z, facing, w=0.75, h=1.0, shutters=None, frame=None, arched=False):
    """facing: 'S','N','E','W'. (x, y) on the wall surface, z = sill height."""
    objs = []
    fr = frame or timber_mat()
    rot = {"S": 0, "N": math.pi, "E": math.pi / 2, "W": -math.pi / 2}[facing]
    out = Vector({"S": (0, -1, 0), "N": (0, 1, 0), "E": (1, 0, 0), "W": (-1, 0, 0)}[facing])
    side = Vector((math.cos(rot), math.sin(rot), 0))
    c = Vector((x, y, z))
    g = box(w, 0.12, h, c + out * 0.0, dark_mat(), rot=(0, 0, rot), name="glass")
    objs.append(g)
    # frame
    objs.append(box(w + 0.16, 0.1, 0.1, c + out * 0.05 - Vector((0, 0, 0.08)), fr, rot=(0, 0, rot)))
    objs.append(box(w + 0.16, 0.1, 0.09, c + out * 0.05 + Vector((0, 0, h)), fr, rot=(0, 0, rot)))
    objs.append(box(0.08, 0.1, h, c + out * 0.05 + side * (w / 2 + 0.04), fr, rot=(0, 0, rot)))
    objs.append(box(0.08, 0.1, h, c + out * 0.05 - side * (w / 2 + 0.04), fr, rot=(0, 0, rot)))
    objs.append(box(0.06, 0.08, h, c + out * 0.04, fr, rot=(0, 0, rot)))           # mullion
    if shutters:
        sm = wood_mat(f"shutter_{shutters[0]}_{shutters[1]}_{shutters[2]}", shutters, plank=0.12)
        for sgn in (-1, 1):
            p = c + out * 0.14 + side * sgn * (w / 2 + 0.26)
            objs.append(box(w * 0.5, 0.05, h * 0.98, p, sm, rot=(0, 0, rot + sgn * 0.25)))
    return objs


def door(x, y, facing, w=1.1, h=2.0, mat=None, arched=True):
    objs = []
    rot = {"S": 0, "N": math.pi, "E": math.pi / 2, "W": -math.pi / 2}[facing]
    out = Vector({"S": (0, -1, 0), "N": (0, 1, 0), "E": (1, 0, 0), "W": (-1, 0, 0)}[facing])
    side = Vector((math.cos(rot), math.sin(rot), 0))
    m = mat or wood_mat("door_wood", (92, 60, 38), plank=0.16)
    c = Vector((x, y, 0.0))
    objs.append(box(w, 0.14, h, c + out * 0.02, m, rot=(0, 0, rot), name="door"))
    fr = timber_mat()
    objs.append(box(w + 0.24, 0.12, 0.14, c + out * 0.06 + Vector((0, 0, h)), fr, rot=(0, 0, rot)))
    for s_ in (-1, 1):
        objs.append(box(0.12, 0.12, h, c + out * 0.06 + side * s_ * (w / 2 + 0.06), fr, rot=(0, 0, rot)))
    # step
    objs.append(box(w + 0.5, 0.5, 0.14, c + out * 0.35, stone_mat("grey"), rot=(0, 0, rot), name="step"))
    return objs


# ------------------------------------------------------------------------------------------------
def timber_frame(w, d, z0, h, mat, rng, pattern="cross", spacing=1.25, size=0.16, faces="SNEW",
                 windows=None):
    """Timber framing on the four walls of a w x d box from z0 to z0+h (beams slightly proud)."""
    objs = []
    off = 0.05
    for f in faces:
        if f in "SN":
            L = w
            y = (-d / 2 - off) if f == "S" else (d / 2 + off)

            def P(u, z):
                return (u, y, z)
        else:
            L = d
            x = (w / 2 + off) if f == "E" else (-w / 2 - off)

            def P(u, z, x=x):
                return (x, u, z)
        n = max(2, int(round(L / spacing)))
        us = [-L / 2 + L * i / n for i in range(n + 1)]
        objs.append(beam(P(-L / 2, z0 + size / 2), P(L / 2, z0 + size / 2), size, mat))
        objs.append(beam(P(-L / 2, z0 + h - size / 2), P(L / 2, z0 + h - size / 2), size, mat))
        objs.append(beam(P(-L / 2, z0 + h * 0.45), P(L / 2, z0 + h * 0.45), size * 0.8, mat))
        for i, u in enumerate(us):
            objs.append(beam(P(u, z0), P(u, z0 + h), size, mat))
            if i < n and (i % 2 == (0 if pattern == "cross" else 1)) and pattern != "plain":
                u2 = us[i + 1]
                if pattern == "cross":
                    objs.append(beam(P(u, z0 + 0.1), P(u2, z0 + h * 0.45), size * 0.75, mat))
                    objs.append(beam(P(u2, z0 + 0.1), P(u, z0 + h * 0.45), size * 0.75, mat))
                else:
                    objs.append(beam(P(u, z0 + h * 0.45), P(u2, z0 + h - 0.1), size * 0.75, mat))
    return objs


def place_windows(w, d, z, rng, faces="SE", spacing=2.2, shutters=None, avoid=(), wh=(0.7, 1.0)):
    objs = []
    for f in faces:
        L = w if f in "SN" else d
        n = max(1, int(L / spacing))
        for i in range(n):
            u = -L / 2 + L * (i + 0.5) / n
            if any(abs(u - a) < 0.9 for a in avoid) and f == "S":
                continue
            if f == "S":
                x, y = u, -d / 2 - 0.01
            elif f == "N":
                x, y = u, d / 2 + 0.01
            elif f == "E":
                x, y = w / 2 + 0.01, u
            else:
                x, y = -w / 2 - 0.01, u
            objs += window(x, y, z, f, w=wh[0], h=wh[1], shutters=shutters)
    return objs
