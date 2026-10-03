"""Procedural vegetation and rocks for King's Domain, rendered with the project camera.

Run:  python blender/vegetation.py [--only fir,oak] [--preview]
Output: game/assets/sprites/trees/<name>.png (body), <name>_sh.png (shadow) + trees.json (anchors)
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
import kdrender as R  # noqa: E402

OUT = os.path.join(R.K.GAME_DIR, "assets", "sprites", "trees")


def lin(c):
    return R.srgb_to_lin(c)


# ------------------------------------------------------------------------------------------------
# materials
def foliage_mat(name, col, col2=None, leaf_scale=9.0, bump=0.55, hue_noise=0.35):
    """Foliage: colour noise between col and col2 + leafy voronoi bump."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.8
    p.inputs["Specular IOR Level"].default_value = 0.15
    coord = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.9
    noise.inputs["Detail"].default_value = 3.0
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.5 - hue_noise * 0.5
    ramp.color_ramp.elements[1].position = 0.5 + hue_noise * 0.5
    ramp.color_ramp.elements[0].color = (*col, 1)
    ramp.color_ramp.elements[1].color = (*(col2 or col), 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    # leaf cells: darker gaps between leaf clusters
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = leaf_scale
    nt.links.new(coord.outputs["Object"], vor.inputs["Vector"])
    gap = nt.nodes.new("ShaderNodeMapRange")
    gap.inputs["From Min"].default_value = 0.0
    gap.inputs["From Max"].default_value = 0.12
    gap.inputs["To Min"].default_value = 0.55
    gap.inputs["To Max"].default_value = 1.0
    nt.links.new(vor.outputs["Distance"], gap.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(ramp.outputs["Color"], mul.inputs["A"])
    comb = nt.nodes.new("ShaderNodeCombineColor")
    for k in ("Red", "Green", "Blue"):
        nt.links.new(gap.outputs["Result"], comb.inputs[k])
    nt.links.new(comb.outputs["Color"], mul.inputs["B"])
    nt.links.new(mul.outputs["Result"], p.inputs["Base Color"])
    b = nt.nodes.new("ShaderNodeBump")
    b.inputs["Strength"].default_value = bump
    b.inputs["Distance"].default_value = 0.1
    nt.links.new(vor.outputs["Distance"], b.inputs["Height"])
    nt.links.new(b.outputs["Normal"], p.inputs["Normal"])
    return m


def bark_mat(name, col, white=False):
    m = R.material(name, col, rough=0.9, spec=0.1, noise=(6.0, 0.5), bump=(14.0, 0.6))
    if white:
        # birch: white bark with dark horizontal marks
        nt = m.node_tree
        p = nt.nodes["Principled BSDF"]
        wave = nt.nodes.new("ShaderNodeTexWave")
        wave.wave_type = "BANDS"
        wave.bands_direction = "Z"
        wave.inputs["Scale"].default_value = 3.0
        wave.inputs["Distortion"].default_value = 8.0
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.8
        ramp.color_ramp.elements[0].color = (*col, 1)
        ramp.color_ramp.elements[1].color = (0.03, 0.03, 0.03, 1)
        nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], p.inputs["Base Color"])
    return m


def displace(obj, strength, size, kind="CLOUDS", seed=0, mid=0.5):
    tex = bpy.data.textures.new(f"tex_{obj.name}", kind)
    if kind == "CLOUDS":
        tex.noise_scale = size
        tex.noise_depth = 2
    else:
        tex.noise_scale = size
    mod = obj.modifiers.new("disp", "DISPLACE")
    mod.texture = tex
    mod.strength = strength
    mod.mid_level = mid
    mod.texture_coords = "GLOBAL" if seed == 0 else "OBJECT"
    return mod


def add_cyl(r0, r1, h, loc, rot=(0, 0, 0), verts=10, mat=None):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r0, radius2=r1, depth=h, location=loc, rotation=rot)
    o = bpy.context.object
    if mat:
        o.data.materials.append(mat)
    return o


def add_clump(loc, scale, mat, rng, subdiv=3, disp=0.35, dsize=0.6):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=1.0, location=loc)
    o = bpy.context.object
    o.scale = scale
    o.rotation_euler = (rng.uniform(0, 6.28), rng.uniform(0, 6.28), rng.uniform(0, 6.28))
    bpy.ops.object.shade_smooth()
    o.data.materials.append(mat)
    displace(o, disp, dsize)
    return o


def branch_between(a: Vector, b: Vector, r0, r1, mat):
    d = b - a
    L = d.length
    mid = (a + b) * 0.5
    o = add_cyl(r0, r1, L, mid, verts=8, mat=mat)
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    return o


# ------------------------------------------------------------------------------------------------
# tufts: small leaf / needle clusters instanced by the thousand over crown emitters
_TUFTS = {}


def tuft_mesh(kind):
    if kind in _TUFTS:
        return _TUFTS[kind]
    if kind == "leaf":
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=(0, 0, -50))
        o = bpy.context.object
        o.scale = (1.0, 1.0, 0.5)
        displace(o, 0.25, 0.4)
    else:  # needle cluster: flat, elongated along +Y (aligned with the emitter normal by particles)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=(0, 0, -50))
        o = bpy.context.object
        o.scale = (0.42, 1.0, 0.2)
        displace(o, 0.12, 0.3)
    bpy.ops.object.shade_smooth()
    o.name = "tuft_" + kind
    o.hide_render = True
    _TUFTS[kind] = o
    return o


def tuft_mat(name, col, col2, leaf_scale=6.0):
    """Per-instance random colour between col and col2 (Object Info > Random) + soft leaf bump."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.75
    p.inputs["Specular IOR Level"].default_value = 0.2
    info = nt.nodes.new("ShaderNodeObjectInfo")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*col, 1)
    ramp.color_ramp.elements[1].color = (*col2, 1)
    nt.links.new(info.outputs["Random"], ramp.inputs["Fac"])
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = leaf_scale
    b = nt.nodes.new("ShaderNodeBump")
    b.inputs["Strength"].default_value = 0.35
    b.inputs["Distance"].default_value = 0.05
    nt.links.new(vor.outputs["Distance"], b.inputs["Height"])
    nt.links.new(b.outputs["Normal"], p.inputs["Normal"])
    nt.links.new(ramp.outputs["Color"], p.inputs["Base Color"])
    return m


def scatter(emitter, kind, count, size, size_rand, mat, seed, normal_align=1.0, render_emitter=True):
    t = tuft_mesh(kind)
    tm = t.data.materials
    if len(tm) == 0 or tm[0] != mat:
        # each species gets its own tuft copy with its material
        t = t.copy()
        t.data = t.data.copy()
        bpy.context.scene.collection.objects.link(t)
        t.data.materials.clear()
        t.data.materials.append(mat)
        t.hide_render = True
    mod = emitter.modifiers.new("tufts", "PARTICLE_SYSTEM")
    ps = mod.particle_system
    ps.seed = seed
    st = ps.settings
    st.type = "EMITTER"
    st.count = int(count)
    st.frame_start = 1
    st.frame_end = 1
    st.lifetime = 5000
    st.emit_from = "FACE"
    st.distribution = "RAND"
    st.use_emit_random = True
    st.physics_type = "NO"
    st.render_type = "OBJECT"
    st.instance_object = t
    st.particle_size = size
    st.size_random = size_rand
    st.use_rotations = True
    st.rotation_mode = "NOR"
    st.rotation_factor_random = 1.0 - normal_align
    st.phase_factor_random = 2.0
    emitter.show_instancer_for_render = render_emitter
    emitter.show_instancer_for_viewport = render_emitter
    st.display_method = "NONE"
    return mod


def lobe(loc, scale, mat, rng, disp=0.35):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=loc)
    o = bpy.context.object
    o.scale = scale
    o.rotation_euler = (rng.uniform(0, 6.28), rng.uniform(0, 6.28), rng.uniform(0, 6.28))
    bpy.ops.object.shade_smooth()
    o.data.materials.append(mat)
    displace(o, disp, 0.9)
    return o


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    for o in objs:
        for m in list(o.modifiers):
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    return o


def surface_area(o):
    return sum(p.area for p in o.data.polygons) * (o.scale.x * o.scale.y + o.scale.y * o.scale.z + o.scale.x * o.scale.z) / 3.0


# ------------------------------------------------------------------------------------------------
# species
def fir(rng, H=12.0, Rb=2.6, tiers=11, col=(30, 54, 40), col2=(58, 92, 62), name="fir", droop=0.55,
        narrow=1.0):
    objs = []
    bark = bark_mat(name + "_bark", lin((70, 52, 38)))
    core = R.material(name + "_core", lin((20, 34, 26)), rough=1.0, spec=0.0)
    tm = tuft_mat(name + "_tuft", lin(col), lin(col2), leaf_scale=14.0)
    objs.append(add_cyl(0.26 * H / 12, 0.05, H * 0.98, (0, 0, H * 0.49), mat=bark))
    base = H * rng.uniform(0.08, 0.13)
    for i in range(tiers):
        t = i / (tiers - 1)
        z = base + (H - base) * (t ** 0.92) * 0.93
        r = (Rb * (1.0 - t) ** 0.95 + 0.3) * narrow * rng.uniform(0.9, 1.1)
        th = (H - base) / tiers * rng.uniform(1.25, 1.55)
        n = 12
        bpy.ops.mesh.primitive_cone_add(vertices=n, radius1=r, radius2=0.06, depth=th,
                                        location=(rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06), z + th * 0.35))
        o = bpy.context.object
        for v in o.data.vertices:
            if v.co.z < -th * 0.4:
                ang = math.atan2(v.co.y, v.co.x)
                k = int(round((ang + math.pi) / (2 * math.pi) * n)) % 2
                f = rng.uniform(1.0, 1.2) if k == 0 else rng.uniform(0.65, 0.8)
                v.co.x *= f
                v.co.y *= f
                v.co.z -= droop * r * 0.3 * (f - 0.6)
        o.rotation_euler = (rng.uniform(-0.04, 0.04), rng.uniform(-0.04, 0.04), rng.uniform(0, 6.28))
        sub = o.modifiers.new("sub", "SUBSURF")
        sub.levels = 1
        sub.render_levels = 1
        bpy.ops.object.shade_smooth()
        o.data.materials.append(core)
        area = math.pi * r * math.hypot(r, th)
        scatter(o, "needle", area * 40, 0.34 * (0.7 + 0.3 * r / Rb), 0.45, tm, seed=i * 7 + 1, normal_align=0.75)
        objs.append(o)
    return objs


def broadleaf(rng, H=10.0, W=7.5, crown_h=6.0, n=9, col=(52, 78, 34), col2=(104, 126, 52), name="oak",
              trunk_col=(78, 62, 46), white=False, lobe_r=(1.6, 2.4), tuft=0.36, density=60.0,
              crown_base=None, core_col=(26, 38, 20)):
    objs = []
    bark = bark_mat(name + "_bark", lin(trunk_col), white=white)
    core = R.material(name + "_core", lin(core_col), rough=1.0, spec=0.0)
    tm = tuft_mat(name + "_tuft", lin(col), lin(col2), leaf_scale=9.0)
    cb = crown_base if crown_base is not None else H - crown_h
    tr = 0.2 * H / 10
    objs.append(add_cyl(tr, tr * 0.6, cb + crown_h * 0.35, (0, 0, (cb + crown_h * 0.35) / 2), mat=bark))
    centre = Vector((0, 0, cb + crown_h * 0.5))
    for k in range(rng.randint(3, 5)):
        a = rng.uniform(0, 6.28)
        tip = centre + Vector((math.cos(a) * W * 0.28, math.sin(a) * W * 0.28, rng.uniform(-0.3, 1.2)))
        objs.append(branch_between(Vector((0, 0, cb * 0.8)), tip, tr * 0.5, tr * 0.18, bark))
    lobes = []
    for k in range(n):
        u = rng.uniform(0, 6.28)
        v = math.acos(rng.uniform(-0.5, 1.0))
        s_ = rng.uniform(0.35, 0.75)
        p = centre + Vector((math.sin(v) * math.cos(u) * W * 0.5 * s_, math.sin(v) * math.sin(u) * W * 0.5 * s_,
                             math.cos(v) * crown_h * 0.5 * s_))
        rc = rng.uniform(*lobe_r)
        lobes.append(lobe(p, (rc, rc, rc * rng.uniform(0.75, 0.95)), core, rng, disp=rc * 0.25))
    crown = join(lobes, name + "_crown")
    scatter(crown, "leaf", surface_area(crown) * density / 10.0, tuft, 0.5, tm, seed=rng.randint(1, 999),
            normal_align=0.5)
    objs.append(crown)
    return objs


def pine(rng, H=15.0, name="pine"):
    objs = []
    bark = bark_mat(name + "_bark", lin((124, 74, 44)))
    core = R.material(name + "_core", lin((20, 34, 26)), rough=1.0, spec=0.0)
    tm = tuft_mat(name + "_tuft", lin((32, 56, 42)), lin((66, 96, 64)), leaf_scale=14.0)
    lean = Vector((rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), 1)).normalized()
    top = lean * H * 0.78
    objs.append(branch_between(Vector((0, 0, 0)), top + lean * 1.2, 0.3, 0.08, bark))
    lobes = []
    for k in range(rng.randint(9, 12)):
        a = rng.uniform(0, 6.28)
        rr = rng.uniform(0.5, 2.8)
        p = top + Vector((math.cos(a) * rr, math.sin(a) * rr, rng.uniform(-3.4, 1.4)))
        objs.append(branch_between(top * rng.uniform(0.8, 0.95), p, 0.1, 0.05, bark))
        rc = rng.uniform(1.0, 1.6)
        lobes.append(lobe(p, (rc * 1.35, rc * 1.35, rc * 0.6), core, rng, disp=0.35))
    crown = join(lobes, name + "_crown")
    scatter(crown, "needle", surface_area(crown) * 3.2, 0.45, 0.5, tm, seed=rng.randint(1, 999), normal_align=0.6)
    objs.append(crown)
    return objs


def poplar(rng, H=16.0, name="poplar"):
    return broadleaf(rng, H=H, W=3.8, crown_h=H * 0.8, n=12, col=(52, 80, 36), col2=(100, 124, 52), name=name,
                     lobe_r=(1.0, 1.5), tuft=0.3, crown_base=H * 0.14)


def birch(rng, H=11.0, name="birch"):
    return broadleaf(rng, H=H, W=4.8, crown_h=H * 0.6, n=8, col=(84, 110, 44), col2=(140, 150, 64), name=name,
                     trunk_col=(206, 204, 196), white=True, lobe_r=(1.0, 1.6), tuft=0.28,
                     core_col=(40, 56, 26))


def fruit(rng, name="fruit"):
    objs = broadleaf(rng, H=5.5, W=5.0, crown_h=3.6, n=6, col=(60, 90, 38), col2=(104, 124, 52), name=name,
                     trunk_col=(84, 66, 50), lobe_r=(1.0, 1.4), tuft=0.3)
    fm = R.material(name + "_fr", lin((176, 46, 30)) if rng.random() < 0.6 else lin((204, 160, 42)), rough=0.5)
    for k in range(30):
        u = rng.uniform(0, 6.28)
        v = math.acos(rng.uniform(-0.2, 1.0))
        p = Vector((math.sin(v) * math.cos(u) * 2.3, math.sin(v) * math.sin(u) * 2.3, 3.7 + math.cos(v) * 1.6))
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.13, location=p, segments=8, ring_count=6)
        bpy.context.object.data.materials.append(fm)
        objs.append(bpy.context.object)
    return objs


def bush(rng, name="bush", col=(50, 76, 34), col2=(96, 112, 48), size=1.0):
    core = R.material(name + "_core", lin((28, 40, 20)), rough=1.0, spec=0.0)
    tm = tuft_mat(name + "_tuft", lin(col), lin(col2), leaf_scale=10.0)
    lobes = []
    for k in range(rng.randint(3, 5)):
        rc = rng.uniform(0.55, 0.95) * size
        p = (rng.uniform(-0.7, 0.7) * size, rng.uniform(-0.7, 0.7) * size, rc * 0.5)
        lobes.append(lobe(p, (rc, rc, rc * 0.8), core, rng, disp=0.12 * size))
    crown = join(lobes, name + "_crown")
    scatter(crown, "leaf", surface_area(crown) * 4.0, 0.3 * size, 0.5, tm, seed=rng.randint(1, 999),
            normal_align=0.5)
    return [crown]


def dead_tree(rng, H=9.0, name="snag"):
    bark = bark_mat(name + "_bark", lin((92, 84, 74)))
    objs = [branch_between(Vector((0, 0, 0)), Vector((0.2, 0.1, H)), 0.25, 0.06, bark)]
    for k in range(5):
        z = rng.uniform(H * 0.35, H * 0.85)
        a = rng.uniform(0, 6.28)
        objs.append(branch_between(Vector((0, 0, z)), Vector((math.cos(a) * 1.8, math.sin(a) * 1.8, z + 1.2)),
                                   0.08, 0.03, bark))
    return objs


def rock(rng, size=2.0, name="rock", flat=0.7, moss=0.35):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=5, radius=1.0, location=(0, 0, size * 0.35))
    o = bpy.context.object
    o.scale = (size * rng.uniform(0.9, 1.3), size * rng.uniform(0.8, 1.1), size * flat)
    o.rotation_euler = (0, 0, rng.uniform(0, 6.28))
    bpy.ops.object.shade_smooth()
    tex = bpy.data.textures.new(f"vor_{name}", "VORONOI")
    tex.noise_scale = 0.9
    tex.distance_metric = "DISTANCE"
    m1 = o.modifiers.new("d1", "DISPLACE")
    m1.texture = tex
    m1.strength = -0.45
    m1.mid_level = 0.0
    displace(o, 0.25, 0.4)
    m = bpy.data.materials.new(name + "_m")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.9
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 3.0
    noise.inputs["Detail"].default_value = 8.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*lin((70, 68, 64)), 1)
    ramp.color_ramp.elements[1].color = (*lin((128, 120, 106)), 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    # moss on upward faces
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sep.inputs["Vector"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.55
    mr.inputs["From Max"].default_value = 0.85
    mr.inputs["To Max"].default_value = moss
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(mr.outputs["Result"], mix.inputs["Factor"])
    nt.links.new(ramp.outputs["Color"], mix.inputs["A"])
    mix.inputs["B"].default_value = (*lin((70, 86, 40)), 1)
    nt.links.new(mix.outputs["Result"], p.inputs["Base Color"])
    b = nt.nodes.new("ShaderNodeBump")
    b.inputs["Strength"].default_value = 0.5
    nt.links.new(noise.outputs["Fac"], b.inputs["Height"])
    nt.links.new(b.outputs["Normal"], p.inputs["Normal"])
    o.data.materials.append(m)
    return [o]


# ------------------------------------------------------------------------------------------------
CATALOG = {
    # name: (builder, kwargs, seed)
    "fir_a": (fir, dict(H=13.0, Rb=3.1, tiers=12), 1),
    "fir_b": (fir, dict(H=10.5, Rb=2.8, tiers=10), 2),
    "fir_c": (fir, dict(H=15.0, Rb=3.4, tiers=13, col=(28, 50, 40), col2=(52, 84, 60)), 3),
    "fir_d": (fir, dict(H=8.5, Rb=2.5, tiers=9), 4),
    "spruce_a": (fir, dict(H=14.0, Rb=2.3, tiers=14, col=(32, 54, 48), col2=(48, 74, 64), droop=0.9, narrow=0.85), 5),
    "spruce_b": (fir, dict(H=11.0, Rb=2.0, tiers=12, col=(32, 54, 48), col2=(48, 74, 64), droop=0.9, narrow=0.85), 6),
    "pine_a": (pine, dict(H=15.0), 7),
    "pine_b": (pine, dict(H=12.5), 8),
    "oak_a": (broadleaf, dict(H=10.5, W=8.0, crown_h=6.2, n=10), 9),
    "oak_b": (broadleaf, dict(H=9.0, W=7.0, crown_h=5.5, n=8), 10),
    "oak_c": (broadleaf, dict(H=12.0, W=9.0, crown_h=7.0, n=12, col=(46, 72, 32), col2=(92, 114, 46)), 11),
    "beech_a": (broadleaf, dict(H=11.0, W=7.0, crown_h=7.0, n=10, col=(62, 90, 38), col2=(118, 132, 54)), 12),
    "beech_b": (broadleaf, dict(H=9.5, W=6.0, crown_h=6.0, n=8, col=(62, 90, 38), col2=(118, 132, 54)), 13),
    "birch_a": (birch, dict(H=11.0), 14),
    "birch_b": (birch, dict(H=9.0), 15),
    "poplar_a": (poplar, dict(H=16.0), 16),
    "poplar_b": (poplar, dict(H=13.0), 17),
    "fruit_a": (fruit, dict(), 18),
    "fruit_b": (fruit, dict(), 19),
    "fruit_c": (fruit, dict(), 20),
    "bush_a": (bush, dict(), 21),
    "bush_b": (bush, dict(size=1.3), 22),
    "bush_c": (bush, dict(col=(70, 90, 40), col2=(110, 118, 52)), 23),
    "bush_d": (bush, dict(size=0.8, col=(52, 74, 40), col2=(80, 100, 48)), 24),
    "snag_a": (dead_tree, dict(), 25),
    "rock_a": (rock, dict(size=1.2), 26),
    "rock_b": (rock, dict(size=2.0, flat=0.6), 27),
    "rock_c": (rock, dict(size=3.2, flat=0.55, moss=0.5), 28),
    "rock_d": (rock, dict(size=0.7, flat=0.8), 29),
    "rock_e": (rock, dict(size=4.5, flat=0.5, moss=0.45), 30),
    "rock_f": (rock, dict(size=1.6, flat=0.9, moss=0.2), 31),
}


def build_one(name):
    fn, kw, seed = CATALOG[name]
    rng = random.Random(seed)
    R.clear_objects()
    _TUFTS.clear()
    kw = dict(kw)
    kw.setdefault("name", name)
    objs = fn(rng, **kw)
    bpy.context.view_layer.update()
    return objs


def grade(rgb):
    # gentle painterly grade: lift saturation a touch, keep darks slightly cool
    l = (rgb * np.array([0.299, 0.587, 0.114])).sum(-1, keepdims=True)
    return np.clip(l + (rgb - l) * 1.06, 0, None)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--samples", type=int, default=48)
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    os.makedirs(OUT, exist_ok=True)
    meta_path = os.path.join(OUT, "trees.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    names = [n for n in CATALOG if not args.only or n.split("_")[0] in args.only.split(",") or n in args.only.split(",")]
    R.reset_scene()
    for name in names:
        objs = build_one(name)
        res = R.render_object(objs, name, samples=args.samples, shadow_samples=16)
        body, sh, anchor = R.finish(res, grade=grade)
        body, sh, anchor = R.trim(body, sh, anchor)
        Image.fromarray(body, "RGBA").save(os.path.join(OUT, f"{name}.png"), optimize=True)
        Image.fromarray(sh, "L").save(os.path.join(OUT, f"{name}_sh.png"), optimize=True)
        meta[name] = {"anchor": [round(anchor[0], 2), round(anchor[1], 2)], "size": [body.shape[1], body.shape[0]]}
        print("rendered", name, body.shape, anchor, flush=True)
        json.dump(meta, open(meta_path, "w"), indent=1)


if __name__ == "__main__":
    main()
