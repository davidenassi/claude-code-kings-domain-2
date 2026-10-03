"""King's Domain architecture kit v2 (Phase 1B): illustrated, detailed, material-rich.

Differences from kit v1:
* every material darkens with ambient occlusion (crisp contact shadows of illustrated art);
* roofs are BUILT row by row (thatch bundles, wooden shingles, clay tiles, slates) with irregular lower
  edges and a per-element colour attribute "rnd" -> each shingle / tile has its own tone;
* stone walls are individual stones (Voronoi cells with their own colour and mortar joints);
* plaster gets dirt near the ground, timber has grain, planks vary plank by plank.

Convention: object origin = ground centre, main facade faces SOUTH (-Y in Blender) at yaw 0.
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Vector

import kdrender as R

_M: dict[str, bpy.types.Material] = {}


def lin(c):
    return tuple((v / 255.0) ** 2.2 for v in c)


def reset_cache():
    _M.clear()


# ------------------------------------------------------------------------------------------------
# node helpers
class G:
    """Tiny node-graph builder."""

    def __init__(self, name):
        self.m = bpy.data.materials.new(name)
        self.m.use_nodes = True
        self.nt = self.m.node_tree
        self.p = self.nt.nodes["Principled BSDF"]
        self.p.inputs["Roughness"].default_value = 0.88
        self.p.inputs["Specular IOR Level"].default_value = 0.18

    def n(self, kind, **props):
        node = self.nt.nodes.new(kind)
        for k, v in props.items():
            setattr(node, k, v)
        return node

    def link(self, a, b):
        self.nt.links.new(a, b)

    def rgb(self, c):
        node = self.n("ShaderNodeRGB")
        node.outputs[0].default_value = (*lin(c), 1)
        return node.outputs[0]

    def val(self, v):
        node = self.n("ShaderNodeValue")
        node.outputs[0].default_value = v
        return node.outputs[0]

    def math(self, op, a, b=None, clamp=False):
        node = self.n("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, x in enumerate((a, b)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                node.inputs[i].default_value = x
            else:
                self.link(x, node.inputs[i])
        return node.outputs[0]

    def mix(self, a, b, fac, blend="MIX"):
        node = self.n("ShaderNodeMix", data_type="RGBA", blend_type=blend)
        for sock, x in ((node.inputs["Factor"], fac), (node.inputs["A"], a), (node.inputs["B"], b)):
            if isinstance(x, (int, float)):
                sock.default_value = x
            elif isinstance(x, tuple):
                sock.default_value = (*lin(x), 1)
            else:
                self.link(x, sock)
        return node.outputs["Result"]

    def ramp(self, fac, stops, interp="LINEAR"):
        """stops: [(pos, (r,g,b) srgb or float grey multiplier)]"""
        node = self.n("ShaderNodeValToRGB")
        cr = node.color_ramp
        cr.interpolation = interp
        while len(cr.elements) < len(stops):
            cr.elements.new(0.5)
        for el, (pos, col) in zip(cr.elements, stops):
            el.position = pos
            if isinstance(col, (int, float)):
                el.color = (col, col, col, 1)
            else:
                el.color = (*lin(col), 1)
        self.link(fac, node.inputs["Fac"])
        return node.outputs["Color"]

    def noise(self, vec=None, scale=2.0, detail=4.0, rough=0.55):
        node = self.n("ShaderNodeTexNoise")
        node.inputs["Scale"].default_value = scale
        node.inputs["Detail"].default_value = detail
        node.inputs["Roughness"].default_value = rough
        if vec is not None:
            self.link(vec, node.inputs["Vector"])
        return node.outputs["Fac"]

    def coords(self, kind="Object"):
        tc = self.n("ShaderNodeTexCoord")
        return tc.outputs[kind]

    def position(self):
        return self.n("ShaderNodeNewGeometry").outputs["Position"]

    def attr(self, name, out="Fac"):
        node = self.n("ShaderNodeAttribute", attribute_name=name, attribute_type="GEOMETRY")
        return node.outputs[out]

    def sep(self, vec):
        node = self.n("ShaderNodeSeparateXYZ")
        self.link(vec, node.inputs["Vector"])
        return node.outputs["X"], node.outputs["Y"], node.outputs["Z"]

    def comb(self, x, y, z=0.0):
        node = self.n("ShaderNodeCombineXYZ")
        for i, v in enumerate((x, y, z)):
            if isinstance(v, (int, float)):
                node.inputs[i].default_value = v
            else:
                self.link(v, node.inputs[i])
        return node.outputs["Vector"]

    def wall_vec(self, su=1.0, sv=1.0):
        """(x + y, z) in object space: continuous mapping around axis-aligned boxes."""
        x, y, z = self.sep(self.coords("Object"))
        u = self.math("ADD", x, y)
        return self.comb(self.math("MULTIPLY", u, su), self.math("MULTIPLY", z, sv))

    def bump(self, height, strength=0.4, distance=0.03, normal=None):
        b = self.n("ShaderNodeBump")
        b.inputs["Strength"].default_value = strength
        b.inputs["Distance"].default_value = distance
        self.link(height, b.inputs["Height"])
        if normal is not None:
            self.link(normal, b.inputs["Normal"])
        return b.outputs["Normal"]

    def finish(self, color, ao_dark=0.42, ao_dist=0.55, normal=None, rough=None, emission=None):
        """Colour x ambient occlusion -> BSDF."""
        ao = self.n("ShaderNodeAmbientOcclusion", samples=4)
        ao.inputs["Distance"].default_value = ao_dist
        if normal is not None:
            self.link(normal, ao.inputs["Normal"])
        fac = self.ramp(ao.outputs["AO"], [(0.0, ao_dark), (1.0, 1.0)])
        col = self.mix(color, fac, 1.0, "MULTIPLY")
        self.link(col, self.p.inputs["Base Color"])
        if normal is not None:
            self.link(normal, self.p.inputs["Normal"])
        if rough is not None:
            self.p.inputs["Roughness"].default_value = rough
        if emission:
            self.p.inputs["Emission Color"].default_value = (*lin(emission[0]), 1)
            self.p.inputs["Emission Strength"].default_value = emission[1]
        return self.m


def cached(fn):
    def wrap(*a, **k):
        key = fn.__name__ + repr(a) + repr(sorted(k.items()))
        if key not in _M:
            _M[key] = fn(*a, **k)
        return _M[key]
    return wrap


# ------------------------------------------------------------------------------------------------
# materials
@cached
def plaster(col=(226, 214, 186), dirt=(132, 112, 84)):
    g = G("plaster")
    big = g.noise(g.coords("Object"), 1.3, 3)
    fine = g.noise(g.coords("Object"), 9.0, 4)
    base = g.mix(col, g.ramp(big, [(0.25, 0.80), (0.5, 0.97), (0.75, 1.08)]), 1.0, "MULTIPLY")
    stain = g.noise(g.coords("Object"), 3.2, 4)
    base = g.mix(base, (196, 178, 140), g.math("MULTIPLY", g.math("SUBTRACT", stain, 0.55, clamp=True), 2.2, clamp=True))
    base = g.mix(base, g.ramp(fine, [(0.35, 0.94), (0.65, 1.04)]), 1.0, "MULTIPLY")
    # dirt and damp near the ground (world height), streaks running down
    _, _, z = g.sep(g.position())
    dz = g.math("SUBTRACT", 1.0, g.math("DIVIDE", z, 1.3), clamp=True)
    dz = g.math("POWER", dz, 1.6)
    streak = g.noise(g.comb(g.math("MULTIPLY", g.sep(g.coords("Object"))[0], 6.0), z), 2.0, 3)
    dfac = g.math("MULTIPLY", g.math("ADD", dz, g.math("MULTIPLY", streak, 0.25)), 0.55, clamp=True)
    base = g.mix(base, dirt, dfac)
    return g.finish(base, normal=g.bump(fine, 0.12, 0.02), rough=0.95)


@cached
def stone(c1=(172, 160, 140), c2=(128, 122, 114), mortar=(92, 84, 72), sw=0.46, sh=0.30, rough_k=1.0):
    """Individual stones: Voronoi cells (own colour), recessed mortar joints, bulging faces."""
    g = G("stone")
    vec = g.wall_vec(1.0 / sw, 1.0 / sh)
    vo = g.n("ShaderNodeTexVoronoi", feature="F1")
    vo.inputs["Randomness"].default_value = 0.85
    g.link(vec, vo.inputs["Vector"])
    vd = g.n("ShaderNodeTexVoronoi", feature="DISTANCE_TO_EDGE")
    vd.inputs["Randomness"].default_value = 0.85
    g.link(vec, vd.inputs["Vector"])
    cell = g.sep(vo.outputs["Color"])[0]
    stonec = g.ramp(cell, [(0.0, c2), (0.55, c1), (1.0, tuple(min(255, int(v * 1.08)) for v in c1))])
    grain = g.noise(g.coords("Object"), 9.0, 3)
    stonec = g.mix(stonec, g.ramp(grain, [(0.3, 0.94), (0.7, 1.04)]), 1.0, "MULTIPLY")
    # each stone: lit top edge, darker lower part (rounded faces) -> readable individual stones
    edge = g.math("MULTIPLY", vd.outputs["Distance"], 4.2, clamp=True)        # 0 at the joint
    mort = g.ramp(edge, [(0.0, 0.0), (0.22, 0.0), (0.55, 1.0)])
    col = g.mix(mortar, stonec, g.sep(mort)[0])
    h = g.math("ADD", g.math("POWER", edge, 0.6), g.math("MULTIPLY", grain, 0.12))
    return g.finish(col, ao_dark=0.38, normal=g.bump(h, 0.75 * rough_k, 0.06), rough=0.9)


@cached
def paving(c1=(176, 166, 148), c2=(132, 124, 114), joint=(96, 86, 72), cell=0.42):
    """Horizontal stone paving (x, y mapping): irregular flags, own colour each, dark joints."""
    g = G("paving")
    x, y, z = g.sep(g.coords("Object"))
    vec = g.comb(g.math("DIVIDE", x, cell), g.math("DIVIDE", y, cell))
    vo = g.n("ShaderNodeTexVoronoi", feature="F1")
    g.link(vec, vo.inputs["Vector"])
    vd = g.n("ShaderNodeTexVoronoi", feature="DISTANCE_TO_EDGE")
    g.link(vec, vd.inputs["Vector"])
    cell_c = g.sep(vo.outputs["Color"])[0]
    c = g.ramp(cell_c, [(0.0, c2), (1.0, c1)])
    edge = g.math("MULTIPLY", vd.outputs["Distance"], 5.0, clamp=True)
    m = g.ramp(edge, [(0.0, 0.0), (0.2, 0.0), (0.45, 1.0)])
    c = g.mix(joint, c, g.sep(m)[0])
    return g.finish(c, ao_dark=0.4, normal=g.bump(edge, 0.5, 0.04), rough=0.9)


@cached
def timber(col=(78, 52, 34)):
    g = G("timber")
    x, y, z = g.sep(g.coords("Object"))
    grain = g.noise(g.comb(g.math("MULTIPLY", x, 3.0), g.math("MULTIPLY", y, 3.0), g.math("MULTIPLY", z, 0.4)), 6, 4)
    c = g.mix(col, g.ramp(grain, [(0.3, 0.75), (0.7, 1.15)]), 1.0, "MULTIPLY")
    return g.finish(c, normal=g.bump(grain, 0.2, 0.01), rough=0.85)


@cached
def planks(col=(128, 96, 64), plank=0.24, vertical=True, weather=0.3):
    """Boards with a tone per board, dark joints, grain."""
    g = G("planks")
    br = g.n("ShaderNodeTexBrick", offset=0.0)
    br.inputs["Color1"].default_value = (*lin(col), 1)
    br.inputs["Color2"].default_value = (*lin(tuple(int(v * 0.74) for v in col)), 1)
    br.inputs["Mortar"].default_value = (*lin(tuple(int(v * 0.35) for v in col)), 1)
    br.inputs["Mortar Size"].default_value = 0.012
    br.inputs["Bias"].default_value = 0.0
    br.inputs["Brick Width"].default_value = plank if vertical else 4.0
    br.inputs["Row Height"].default_value = 4.0 if vertical else plank
    g.link(g.wall_vec(), br.inputs["Vector"])
    x, y, z = g.sep(g.coords("Object"))
    gv = g.comb(g.math("MULTIPLY", g.math("ADD", x, y), 8.0 if vertical else 0.6), g.math("MULTIPLY", z, 0.6 if vertical else 8.0))
    grain = g.noise(gv, 3.0, 5)
    c = g.mix(br.outputs["Color"], g.ramp(grain, [(0.3, 0.8), (0.7, 1.12)]), 1.0, "MULTIPLY")
    c = g.mix(c, (118, 112, 104), weather * 0.6)
    return g.finish(c, normal=g.bump(br.outputs["Fac"], 0.6, 0.02), rough=0.9)


@cached
def roof(kind="thatch"):
    """Roof elements (built geometry) read the per-element attribute 'rnd' and the UV (u along the ridge,
    v up the slope)."""
    pal = {
        "thatch": ((104, 70, 32), (190, 144, 70), (236, 194, 112)),
        "thatch_old": ((82, 62, 38), (154, 118, 70), (194, 158, 104)),
        "shingle": ((62, 52, 44), (98, 82, 66), (128, 110, 90)),
        "tile": ((112, 52, 36), (150, 72, 48), (176, 98, 68)),
        "tile_dark": ((96, 50, 40), (128, 68, 50), (152, 90, 66)),
        "slate": ((62, 66, 80), (92, 98, 114), (120, 126, 140)),
    }[kind]
    g = G("roof_" + kind)
    rnd = g.attr("rnd")
    uv = g.coords("UV")
    u, v, _ = g.sep(uv)
    if kind.startswith("thatch"):
        # straw: fine strands along the slope + clumps
        strands = g.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="X")
        strands.inputs["Scale"].default_value = 26.0
        strands.inputs["Distortion"].default_value = 9.0
        strands.inputs["Detail"].default_value = 4.0
        g.link(g.comb(u, g.math("MULTIPLY", v, 0.15)), strands.inputs["Vector"])
        patches = g.noise(g.comb(u, g.math("MULTIPLY", v, 1.6)), 0.9, 3)
        tone = g.math("ADD", g.math("MULTIPLY", strands.outputs["Fac"], 0.42),
                      g.math("ADD", g.math("MULTIPLY", rnd, 0.22), g.math("MULTIPLY", patches, 0.5)))
        tone = g.math("SUBTRACT", tone, 0.08)
        c = g.ramp(tone, [(0.0, pal[0]), (0.5, pal[1]), (1.0, pal[2])])
        moss = g.noise(uv, 2.2, 3)
        c = g.mix(c, (110, 100, 56), g.math("MULTIPLY", g.math("SUBTRACT", moss, 0.68, clamp=True), 1.2, clamp=True))
        nrm = g.bump(strands.outputs["Fac"], 0.9, 0.04)
        return g.finish(c, ao_dark=0.32, ao_dist=0.7, normal=nrm, rough=1.0)
    grain = g.noise(g.comb(g.math("MULTIPLY", u, 2.0), g.math("MULTIPLY", v, 12.0)), 5.0, 4)
    tone = g.math("ADD", g.math("MULTIPLY", rnd, 0.75), g.math("MULTIPLY", grain, 0.25))
    c = g.ramp(tone, [(0.0, pal[0]), (0.5, pal[1]), (1.0, pal[2])])
    if kind.startswith("tile") or kind == "shingle":
        moss = g.noise(uv, 1.6, 3)
        c = g.mix(c, (98, 100, 60), g.math("MULTIPLY", g.math("SUBTRACT", moss, 0.64, clamp=True), 1.4, clamp=True))
    return g.finish(c, ao_dark=0.3, ao_dist=0.6, normal=g.bump(grain, 0.25, 0.01),
                    rough=0.6 if kind == "slate" else 0.85)


@cached
def flat(col, rough=0.85, noise=0.12, scale=4.0, metal=0.0, emission=None, ao=0.45):
    g = G("flat")
    c = g.rgb(col)
    if noise > 0:
        c = g.mix(c, g.ramp(g.noise(g.coords("Object"), scale, 4), [(0.3, 1 - noise), (0.7, 1 + noise * 0.7)]), 1.0,
                  "MULTIPLY")
    g.p.inputs["Metallic"].default_value = metal
    return g.finish(c, ao_dark=ao, rough=rough, emission=emission)


@cached
def cloth(c1, c2=None, stripe=0.32, axis="X"):
    g = G("cloth")
    x, y, z = g.sep(g.coords("Object"))
    if c2 is not None:
        t = g.math("FRACT", g.math("DIVIDE", {"X": x, "Y": y, "Z": z}[axis], 2 * stripe))
        c = g.ramp(t, [(0.0, c1), (0.5, c2)], interp="CONSTANT")
    else:
        c = g.rgb(c1)
    weave = g.noise(g.coords("Object"), 30.0, 2)
    c = g.mix(c, g.ramp(g.noise(g.coords("Object"), 2.5, 3), [(0.3, 0.88), (0.7, 1.06)]), 1.0, "MULTIPLY")
    return g.finish(c, normal=g.bump(weave, 0.08, 0.01), rough=0.95)


def dark_glass():
    return flat((30, 34, 44), rough=0.3, noise=0.05, ao=0.7)


def iron():
    return flat((58, 58, 62), rough=0.45, noise=0.1, metal=0.7)


def straw():
    return roof("thatch")


# ------------------------------------------------------------------------------------------------
# geometry primitives
def link_obj(bm, name, mat=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if mat is not None:
        o.data.materials.append(mat)
    for poly in me.polygons:
        poly.use_smooth = False
    return o


def box(sx, sy, sz, loc=(0, 0, 0), mat=None, rot=(0, 0, 0), name="box", bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z = (v.co.z + 0.5) * sz
    o = link_obj(bm, name, mat)
    o.location = loc
    o.rotation_euler = rot
    if bevel > 0:
        m = o.modifiers.new("bev", "BEVEL")
        m.width = bevel
        m.segments = 1
        m.limit_method = "ANGLE"
    return o


def cyl(r, h, loc=(0, 0, 0), mat=None, verts=16, r2=None, rot=(0, 0, 0), name="cyl", smooth=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=verts, radius1=r,
                          radius2=r if r2 is None else r2, depth=h)
    for v in bm.verts:
        v.co.z += h / 2
    o = link_obj(bm, name, mat)
    o.location = loc
    o.rotation_euler = rot
    if smooth:
        for poly in o.data.polygons:
            poly.use_smooth = abs(poly.normal.z) < 0.9
    return o


def sphere(r, loc=(0, 0, 0), mat=None, scale=(1, 1, 1), segs=10, name="sph"):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(4, segs // 2 + 1), radius=r)
    o = link_obj(bm, name, mat)
    o.location = loc
    o.scale = scale
    for poly in o.data.polygons:
        poly.use_smooth = True
    return o


def beam(a, b, size, mat, size2=None):
    a = Vector(a)
    b = Vector(b)
    d = b - a
    o = box(size, size2 or size, d.length, mat=mat, name="beam")
    o.location = a
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    return o


def prism(pts2d, z0, z1, mat, name="prism"):
    """Vertical prism from a 2D polygon (x, y)."""
    bm = bmesh.new()
    lo = [bm.verts.new((x, y, z0)) for x, y in pts2d]
    hi = [bm.verts.new((x, y, z1)) for x, y in pts2d]
    bm.faces.new(lo[::-1])
    bm.faces.new(hi)
    n = len(pts2d)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    return link_obj(bm, name, mat)


def gable_wall(width, z0, rise, mat, thick=0.3, y=0.0, x=0.0, axis="x", name="gable"):
    """Triangular gable infill; axis 'x' = in the XZ plane at y, 'y' = in the YZ plane at x."""
    bm = bmesh.new()
    pts = [(-width / 2, z0), (width / 2, z0), (0, z0 + rise)]
    if axis == "x":
        a = [bm.verts.new((u, y - thick / 2, z)) for u, z in pts]
        b = [bm.verts.new((u, y + thick / 2, z)) for u, z in pts]
    else:
        a = [bm.verts.new((x - thick / 2, u, z)) for u, z in pts]
        b = [bm.verts.new((x + thick / 2, u, z)) for u, z in pts]
    bm.faces.new(a[::-1])
    bm.faces.new(b)
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return link_obj(bm, name, mat)


# ------------------------------------------------------------------------------------------------
# roofs built row by row
ROOF_SPEC = {
    #            row height, element width (u), lift, jag, thickness, gap
    "thatch":   (0.30, 0.12, 0.035, 0.09, 0.12, 0.0),
    "thatch_old": (0.30, 0.12, 0.035, 0.09, 0.12, 0.0),
    "shingle":  (0.26, 0.24, 0.035, 0.035, 0.045, 0.012),
    "tile":     (0.24, 0.21, 0.04, 0.012, 0.05, 0.004),
    "tile_dark": (0.24, 0.21, 0.04, 0.012, 0.05, 0.004),
    "slate":    (0.2, 0.26, 0.025, 0.02, 0.03, 0.006),
}


def _slope_rows(bm, rnd_layer, uv_layer, length, slope_len, kind, rng, origin, ax_u, ax_s, nrm, u_jitter=True):
    """Rows of roof elements on one plane: origin = eave corner (u=0, s=0); ax_u along the ridge,
    ax_s up the slope, nrm outward. Elements overlap the row above, lower edges lifted and jagged."""
    rh, ew, lift, jag, th, gap = ROOF_SPEC[kind]
    nrows = max(1, int(math.ceil(slope_len / rh)))
    thatch = kind.startswith("thatch")
    for r in range(nrows):
        s0 = r * rh
        s1 = min(slope_len + 0.02, s0 + rh * 1.7)
        # element boundaries along u
        us = [0.0]
        off = (0.5 * ew if r % 2 else 0.0)
        u = off if off > 0 else ew * rng.uniform(0.6, 1.0)
        while u < length - 0.05:
            us.append(u)
            u += ew * (rng.uniform(0.7, 1.35) if (u_jitter and kind == "shingle") else rng.uniform(0.96, 1.04))
        us.append(length)
        if thatch:
            # one continuous bundle course per row, its lower edge wavy (smooth noise every 0.12 m)
            nseg = max(2, int(length / 0.12))
            us = [length * i / nseg for i in range(nseg + 1)]
            ph = rng.uniform(0, 6.28)
            jag_at = [jag * (0.55 + 0.45 * math.sin(uu * 3.1 + ph) * math.sin(uu * 1.3 + ph * 2) + 0.35 * rng.random())
                      for uu in us]
            row_val = rng.random()
        for i in range(len(us) - 1):
            ua, ub = us[i] + gap * 0.5, us[i + 1] - gap * 0.5
            if ub - ua < 0.02:
                continue
            if thatch:
                ja, jb = jag_at[i], jag_at[i + 1]
                lf = lift
            else:
                ja = jb = jag * rng.random()
                lf = lift * (0.8 + 0.4 * rng.random())
            # four corners (u, s, n): lower edge lifted along the normal, hanging below s0 by jag
            thk = th * (2.6 if (thatch and r == 0) else 1.0)
            pts = [(ua, s0 - ja, lf + thk), (ub, s0 - jb, lf + thk), (ub, s1, th * 0.3), (ua, s1, th * 0.3)]
            top = [origin + ax_u * pu + ax_s * ps + nrm * pn for pu, ps, pn in pts]
            bot = [p - nrm * thk for p in top]
            vt = [bm.verts.new(p) for p in top]
            vb = [bm.verts.new(p) for p in bot]
            faces = [bm.faces.new(vt), bm.faces.new(vb[::-1])]
            for k in range(4):
                kk = (k + 1) % 4
                faces.append(bm.faces.new((vb[k], vb[kk], vt[kk], vt[k])))
            val = (row_val * 0.6 + rng.random() * 0.4) if thatch else rng.random()
            for f in faces:
                f[rnd_layer] = val
                for loop in f.loops:
                    co = loop.vert.co - origin
                    loop[uv_layer].uv = (co.dot(ax_u), co.dot(ax_s))


def gable_roof(w, d, z0, pitch, kind, rng, overhang=0.5, gable_over=0.35, ridge_x=True, name="roof"):
    """Gable roof over a w x d footprint (ridge along x if ridge_x), eaves at z0. Returns (objs, ridge_z)."""
    if not ridge_x:
        w, d = d, w
    t = math.tan(math.radians(pitch))
    hd = d / 2 + overhang
    rise = t * (d / 2)
    zr = z0 + rise
    ze = z0 - t * overhang
    slope_len = math.hypot(hd, zr - ze)
    L = w + 2 * gable_over
    bm = bmesh.new()
    rl = bm.faces.layers.float.new("rnd")
    uvl = bm.loops.layers.uv.new("UVMap")
    for side in (-1, 1):
        a = Vector((0, side * hd, ze))
        b = Vector((0, 0, zr))
        ax_s = (b - a).normalized()
        ax_u = Vector((1, 0, 0))
        nrm = ax_u.cross(ax_s).normalized()
        if nrm.z < 0:
            nrm = -nrm
        origin = Vector((-L / 2, side * hd, ze))
        _slope_rows(bm, rl, uvl, L, slope_len, kind, rng, origin, ax_u, ax_s, nrm)
    o = link_obj(bm, name, roof(kind))
    objs = [o]
    # ridge
    if kind.startswith("thatch"):
        rr = cyl(0.26, L + 0.1, (0, 0, zr + 0.02), roof(kind), verts=10, rot=(0, math.pi / 2, 0), name="ridge")
        rr.location = (-L / 2 - 0.05, 0, zr + 0.06)
        rr.scale = (1.0, 1.0, 1.0)
        objs.append(rr)
        # thick rounded verge (gable edges) on thatch
        for sx in (-1, 1):
            for side in (-1, 1):
                objs.append(beam((sx * L / 2, side * hd, ze + 0.05), (sx * L / 2, 0, zr + 0.05), 0.28,
                                 roof(kind), size2=0.22))
    elif kind.startswith("tile"):
        objs.append(cyl(0.13, L, (-L / 2, 0, zr + 0.04), roof(kind), verts=8, rot=(0, math.pi / 2, 0), name="ridge"))
    else:
        objs.append(box(L, 0.36, 0.1, (0, 0, zr - 0.02), timber(), name="ridge"))
    if not kind.startswith("thatch"):
        # barge boards on the gable edges
        for sx in (-1, 1):
            for side in (-1, 1):
                objs.append(beam((sx * (L / 2 + 0.02), side * hd, ze - 0.05), (sx * (L / 2 + 0.02), 0, zr + 0.02),
                                 0.08, timber(), size2=0.22))
    if not ridge_x:
        for ob in objs:
            loc = Vector(ob.location)
            ob.location = (-loc.y, loc.x, loc.z)
            ob.rotation_euler.z += math.pi / 2
    return objs, zr


def hip_roof(w, d, z0, pitch, kind, rng, overhang=0.5, name="hiproof"):
    """Hip roof: four planes built with rows, clipped to triangles/trapezoids by element culling."""
    t = math.tan(math.radians(pitch))
    hw, hd = w / 2 + overhang, d / 2 + overhang
    ze = z0 - t * overhang
    rise = t * min(w, d) / 2
    zr = z0 + rise
    ridge_half = max(0.0, (w - d) / 2)
    bm = bmesh.new()
    rl = bm.faces.layers.float.new("rnd")
    uvl = bm.loops.layers.uv.new("UVMap")
    rh, ew, lift, jag, th, gap = ROOF_SPEC[kind]
    # long sides (trapezoids) and short sides (triangles): rows shrink towards the top
    planes = []
    for side in (-1, 1):
        planes.append(("long", side))
        planes.append(("short", side))
    for kindp, side in planes:
        if kindp == "long":
            a = Vector((0, side * hd, ze))
            b = Vector((0, 0, zr))
            run_hi = ridge_half
            run_lo = hw
            ax_u = Vector((1, 0, 0))
        else:
            a = Vector((side * hw, 0, ze))
            b = Vector((side * ridge_half, 0, zr))
            run_hi = 0.0
            run_lo = hd
            ax_u = Vector((0, 1, 0))
        ax_s = (b - a).normalized()
        nrm = ax_u.cross(ax_s).normalized()
        if nrm.z < 0:
            nrm = -nrm
        slope_len = (b - a).length
        nrows = max(1, int(math.ceil(slope_len / rh)))
        for r in range(nrows):
            s0 = r * rh
            f = s0 / slope_len
            half = run_lo + (run_hi - run_lo) * min(1.0, f)
            if half < 0.08:
                continue
            o = a + ax_s * 0 - ax_u * half
            sub = bmesh.new()
            sub.free()
            # one row as a strip
            us = [0.0]
            u = ew * rng.uniform(0.5, 1.0)
            while u < 2 * half - 0.05:
                us.append(u)
                u += ew * rng.uniform(0.7, 1.3)
            us.append(2 * half)
            s1 = min(slope_len + 0.02, s0 + rh * 1.7)
            f1 = s1 / slope_len
            half1 = run_lo + (run_hi - run_lo) * min(1.0, f1)
            for i in range(len(us) - 1):
                ua, ub = us[i] + gap / 2, us[i + 1] - gap / 2
                ja = jag * rng.random() * (2 if kind.startswith("thatch") else 1)
                lf = lift * (0.8 + 0.4 * rng.random())
                # top edge narrows with the hip
                def top_u(uu):
                    return (uu - half) * (half1 / half) + half
                pts = [(ua, s0 - ja, lf + th), (ub, s0 - ja, lf + th), (top_u(ub), s1, th * 0.3),
                       (top_u(ua), s1, th * 0.3)]
                topv = [o + ax_u * pu + ax_s * ps + nrm * pn for pu, ps, pn in pts]
                botv = [p - nrm * th for p in topv]
                vt = [bm.verts.new(p) for p in topv]
                vb = [bm.verts.new(p) for p in botv]
                faces = [bm.faces.new(vt), bm.faces.new(vb[::-1])]
                for k in range(4):
                    kk = (k + 1) % 4
                    faces.append(bm.faces.new((vb[k], vb[kk], vt[kk], vt[k])))
                val = rng.random()
                for fc in faces:
                    fc[rl] = val
                    for loop in fc.loops:
                        co = loop.vert.co - o
                        loop[uvl].uv = (co.dot(ax_u), co.dot(ax_s))
    ob = link_obj(bm, name, roof(kind))
    objs = [ob]
    if ridge_half > 0.01:
        if kind.startswith("thatch"):
            objs.append(cyl(0.24, 2 * ridge_half + 0.4, (-ridge_half - 0.2, 0, zr + 0.04), roof(kind), verts=10,
                            rot=(0, math.pi / 2, 0), name="ridge"))
        elif kind.startswith("tile"):
            objs.append(cyl(0.12, 2 * ridge_half + 0.2, (-ridge_half - 0.1, 0, zr + 0.03), roof(kind), verts=8,
                            rot=(0, math.pi / 2, 0), name="ridge"))
    return objs, zr


def lean_to(w, d, z_high, z_low, kind, rng, y_wall, side=-1, name="leanto"):
    """Single-slope roof attached to a wall at y_wall, falling towards `side` (−1 south, +1 north)."""
    bm = bmesh.new()
    rl = bm.faces.layers.float.new("rnd")
    uvl = bm.loops.layers.uv.new("UVMap")
    a = Vector((-w / 2, y_wall + side * d, z_low))
    b = Vector((-w / 2, y_wall, z_high))
    ax_s = (b - a).normalized()
    ax_u = Vector((1, 0, 0))
    nrm = ax_u.cross(ax_s).normalized()
    if nrm.z < 0:
        nrm = -nrm
    _slope_rows(bm, rl, uvl, w, (b - a).length, kind, rng, a, ax_u, ax_s, nrm)
    return link_obj(bm, name, roof(kind))


def cone_roof(r, h, z0, kind, rng, overhang=0.35, segs=24, name="cone"):
    """Conical roof made of rings of elements (towers)."""
    rr = r + overhang
    slope_len = math.hypot(rr, h)
    rh, ew, lift, jag, th, gap = ROOF_SPEC[kind]
    nrows = max(1, int(math.ceil(slope_len / rh)))
    bm = bmesh.new()
    rl = bm.faces.layers.float.new("rnd")
    uvl = bm.loops.layers.uv.new("UVMap")
    for ri in range(nrows):
        s0 = ri * rh
        s1 = min(slope_len, s0 + rh * 1.7)
        r0 = rr * (1 - s0 / slope_len)
        r1 = rr * (1 - s1 / slope_len)
        z_0 = z0 + h * s0 / slope_len
        z_1 = z0 + h * s1 / slope_len
        n = max(6, int(2 * math.pi * r0 / ew))
        for k in range(n):
            a0 = 2 * math.pi * k / n
            a1 = 2 * math.pi * (k + 1) / n
            lf = lift * (0.8 + 0.4 * rng.random())
            ja = jag * rng.random()
            pts = []
            for (rad, zz, aa, out) in ((r0 + lf, z_0 - ja, a0, 1), (r0 + lf, z_0 - ja, a1, 1), (r1, z_1, a1, 0),
                                       (r1, z_1, a0, 0)):
                pts.append(Vector((math.cos(aa) * rad, math.sin(aa) * rad, zz)))
            vt = [bm.verts.new(p) for p in pts]
            vb = [bm.verts.new(p - Vector((math.cos((a0 + a1) / 2), math.sin((a0 + a1) / 2), 0)) * th) for p in pts]
            faces = [bm.faces.new(vt), bm.faces.new(vb[::-1])]
            for q in range(4):
                qq = (q + 1) % 4
                faces.append(bm.faces.new((vb[q], vb[qq], vt[qq], vt[q])))
            val = rng.random()
            for fc in faces:
                fc[rl] = val
                for loop in fc.loops:
                    p = loop.vert.co
                    loop[uvl].uv = (math.atan2(p.y, p.x) * rr, s0 + (p.z - z_0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = link_obj(bm, name, roof(kind))
    tip = cyl(0.12, 0.6, (0, 0, z0 + h - 0.15), timber(), verts=8)
    return [o, tip]


# ------------------------------------------------------------------------------------------------
# walls, openings, details
def wall_box(w, d, z0, h, mat, name="wall"):
    return box(w, d, h, (0, 0, z0), mat, name=name)


def timber_frame(w, d, z0, h, rng, pattern="cross", spacing=1.2, size=0.17, faces="SNEW", openings=()):
    """Half-timbering on a w x d storey (beams proud of the wall). openings: [(face, u, half_width)]."""
    tm = timber()
    objs = []
    off = 0.06
    for f in faces:
        if f in "SN":
            L = w
            yy = (-d / 2 - off) if f == "S" else (d / 2 + off)

            def P(u, z, yy=yy):
                return (u, yy, z)
        else:
            L = d
            xx = (w / 2 + off) if f == "E" else (-w / 2 - off)

            def P(u, z, xx=xx):
                return (xx, u, z)
        n = max(2, int(round(L / spacing)))
        us = [-L / 2 + L * i / n for i in range(n + 1)]
        objs.append(beam(P(-L / 2 - 0.05, z0 + size / 2), P(L / 2 + 0.05, z0 + size / 2), size, tm))
        objs.append(beam(P(-L / 2 - 0.05, z0 + h - size / 2), P(L / 2 + 0.05, z0 + h - size / 2), size, tm))
        mid = z0 + h * 0.5
        objs.append(beam(P(-L / 2, mid), P(L / 2, mid), size * 0.8, tm))
        blocked = [(u, hw) for (ff, u, hw) in openings if ff == f]
        for i, u in enumerate(us):
            if any(abs(u - bu) < bh for bu, bh in blocked):
                continue
            objs.append(beam(P(u, z0), P(u, z0 + h), size, tm))
            if i < n and pattern != "plain":
                u2 = us[i + 1]
                if any(abs((u + u2) / 2 - bu) < bh + 0.3 for bu, bh in blocked):
                    continue
                if pattern == "cross" and i % 2 == 0:
                    objs.append(beam(P(u, mid), P(u2, z0 + h - 0.08), size * 0.7, tm))
                    objs.append(beam(P(u2, mid), P(u, z0 + h - 0.08), size * 0.7, tm))
                elif pattern == "brace":
                    if i % 2 == 0:
                        objs.append(beam(P(u, z0 + 0.1), P(u2, mid), size * 0.7, tm))
                    else:
                        objs.append(beam(P(u2, z0 + 0.1), P(u, mid), size * 0.7, tm))
                elif pattern == "chevron" and i % 2 == 1:
                    objs.append(beam(P(u, mid), P((u + u2) / 2, z0 + h - 0.1), size * 0.7, tm))
                    objs.append(beam(P(u2, mid), P((u + u2) / 2, z0 + h - 0.1), size * 0.7, tm))
    return objs


FACE = {"S": (0, -1), "N": (0, 1), "E": (1, 0), "W": (-1, 0)}


def _place(face, u, w, d):
    """Point on the wall surface of a w x d box for face and coordinate u along it."""
    nx, ny = FACE[face]
    if face in "SN":
        return Vector((u, ny * d / 2, 0)), Vector((nx, ny, 0)), Vector((1, 0, 0))
    return Vector((nx * w / 2, u, 0)), Vector((nx, ny, 0)), Vector((0, 1, 0))


def window(face, u, z, w, d, ww=0.75, wh=1.0, shutters=None, flowers=None, arched=False, frame_mat=None):
    """Window on a w x d box: dark recess, frame, mullion and transom, sill, optional shutters / flower box."""
    base, out, side = _place(face, u, w, d)
    rot = math.atan2(out.x, -out.y)
    fm = frame_mat or timber()
    objs = []
    c = base + Vector((0, 0, z))
    objs.append(box(ww, 0.14, wh, c + out * 0.0, dark_glass(), rot=(0, 0, rot), name="glass"))
    objs.append(box(ww + 0.18, 0.12, 0.1, c + out * 0.06 - Vector((0, 0, 0.1)), fm, rot=(0, 0, rot)))
    objs.append(box(ww + 0.14, 0.12, 0.1, c + out * 0.06 + Vector((0, 0, wh)), fm, rot=(0, 0, rot)))
    for s_ in (-1, 1):
        objs.append(box(0.09, 0.12, wh, c + out * 0.06 + side * s_ * (ww / 2 + 0.045), fm, rot=(0, 0, rot)))
    objs.append(box(0.05, 0.1, wh, c + out * 0.05, fm, rot=(0, 0, rot)))
    objs.append(box(ww, 0.1, 0.05, c + out * 0.05 + Vector((0, 0, wh * 0.55)), fm, rot=(0, 0, rot)))
    objs.append(box(ww + 0.3, 0.22, 0.07, c + out * 0.12 - Vector((0, 0, 0.14)), fm, rot=(0, 0, rot), name="sill"))
    if shutters:
        sm = planks(shutters, 0.12, True, 0.15)
        for s_ in (-1, 1):
            p = c + out * 0.12 + side * s_ * (ww / 2 + 0.24)
            objs.append(box(ww * 0.48, 0.06, wh * 0.98, p, sm, rot=(0, 0, rot + s_ * 0.18)))
    if flowers:
        objs.append(box(ww + 0.2, 0.26, 0.22, c + out * 0.22 - Vector((0, 0, 0.36)), planks((110, 76, 48), 0.1, False),
                        rot=(0, 0, rot), name="flowerbox"))
        rng = random.Random(int(u * 100 + z * 10))
        for k in range(7):
            q = c + out * (0.24 + rng.uniform(-0.05, 0.08)) + side * rng.uniform(-ww / 2, ww / 2) - Vector((0, 0, 0.12))
            objs.append(sphere(rng.uniform(0.07, 0.11), q, flat((60, 96, 40), noise=0.2), segs=6))
            objs.append(sphere(rng.uniform(0.05, 0.07), q + Vector((0, 0, 0.08)) + out * 0.04,
                               flat(rng.choice(flowers), noise=0.1), segs=6))
    return objs


def door(face, u, w, d, dw=1.05, dh=2.05, mat=None, stone_frame=False, canopy=None, step=True):
    base, out, side = _place(face, u, w, d)
    rot = math.atan2(out.x, -out.y)
    m = mat or planks((104, 70, 42), 0.16, True, 0.1)
    objs = [box(dw, 0.12, dh, base + out * 0.03, m, rot=(0, 0, rot), name="door")]
    fm = stone() if stone_frame else timber()
    fs = 0.2 if stone_frame else 0.13
    objs.append(box(dw + 2 * fs, 0.18, fs, base + out * 0.06 + Vector((0, 0, dh)), fm, rot=(0, 0, rot)))
    for s_ in (-1, 1):
        objs.append(box(fs, 0.18, dh, base + out * 0.06 + side * s_ * (dw / 2 + fs / 2), fm, rot=(0, 0, rot)))
    # iron straps
    for zz in (0.45, 1.5):
        objs.append(box(dw * 0.8, 0.02, 0.05, base + out * 0.1 + Vector((0, 0, zz)), iron(), rot=(0, 0, rot)))
    if step:
        objs.append(box(dw + 0.6, 0.55, 0.16, base + out * 0.3, stone((150, 144, 132), (118, 112, 104)),
                        rot=(0, 0, rot), name="step"))
    if canopy:
        rng = random.Random(int(u * 31))
        cw = dw + 0.9
        c = lean_to(cw, 0.95, dh + 0.75, dh + 0.25, canopy, rng, 0.0, side=-1)
        c.rotation_euler = (0, 0, rot)
        c.location = base + out * 0.02
        objs.append(c)
        for s_ in (-1, 1):
            objs.append(beam(base + out * 0.8 + side * s_ * (cw / 2 - 0.1), base + out * 0.8 + side * s_ * (cw / 2 - 0.1)
                             + Vector((0, 0, dh + 0.3)), 0.1, timber()))
    return objs


def chimney(x, y, z_base, z_top, name="chimney"):
    st = stone((158, 150, 138), (118, 112, 106), (84, 78, 70), 0.3, 0.2)
    objs = [box(0.8, 0.8, z_top - z_base, (x, y, z_base), st, name=name, bevel=0.03)]
    objs.append(box(0.98, 0.98, 0.14, (x, y, z_top - 0.08), stone((128, 122, 116), (100, 96, 92)), name="chimney_cap"))
    objs.append(box(0.5, 0.5, 0.05, (x, y, z_top + 0.03), flat((26, 22, 20), noise=0.0), name="flue"))
    return objs


def woodpile(length, height, depth=0.55, loc=(0, 0, 0), rot=0.0, rng=None):
    rng = rng or random.Random(3)
    objs = []
    wm = flat((118, 84, 52), noise=0.2, scale=8)
    endm = flat((176, 138, 92), noise=0.15, scale=12)
    r = 0.09
    rows = max(1, int(height / (2 * r)))
    cx, cy, cz = loc
    c, s_ = math.cos(rot), math.sin(rot)
    for j in range(rows):
        n = int(length / (2 * r))
        for i in range(n - (j % 2)):
            u = -length / 2 + r + i * 2 * r + (r if j % 2 else 0) + rng.uniform(-0.02, 0.02)
            z = cz + r + j * 2 * r * 0.92
            lg = cyl(r * rng.uniform(0.85, 1.1), depth * rng.uniform(0.9, 1.05), (0, 0, 0), wm, verts=8,
                     rot=(math.pi / 2, 0, rot))
            lg.location = (cx + c * u - s_ * (-depth / 2), cy + s_ * u + c * (-depth / 2), z)
            lg.data.materials.append(endm)
            objs.append(lg)
    objs.append(box(length + 0.1, depth + 0.06, 0.04, (cx, cy, cz), planks((96, 72, 50), 0.2, False),
                    rot=(0, 0, rot)))
    return objs


def barrel(x, y, z=0.0, r=0.32, h=0.85, mat=None, rng=None):
    rng = rng or random.Random(int(x * 10 + y * 7))
    wm = mat or planks((132, 92, 56), 0.12, True, 0.1)
    o = cyl(r, h, (x, y, z), wm, verts=14)
    # bulge
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for v in bm.verts:
        t = v.co.z / h
        k = 1.0 + 0.12 * math.sin(math.pi * t)
        v.co.x *= k
        v.co.y *= k
    bm.to_mesh(o.data)
    bm.free()
    objs = [o]
    for zz in (0.12, h - 0.12, h * 0.5):
        objs.append(cyl(r * (1.13 if zz == h * 0.5 else 1.05), 0.05, (x, y, z + zz - 0.025), iron(), verts=14))
    objs.append(cyl(r * 0.9, 0.02, (x, y, z + h - 0.01), flat((92, 64, 40)), verts=14))
    return objs


def crate(x, y, z=0.0, s=0.7, rot=0.0, col=(150, 112, 70)):
    m = planks(col, 0.14, False, 0.15)
    objs = [box(s, s, s, (x, y, z), m, rot=(0, 0, rot), bevel=0.02)]
    tm = timber((96, 68, 44))
    c, s_ = math.cos(rot), math.sin(rot)
    for sx in (-1, 1):
        for sy in (-1, 1):
            px = x + c * (sx * s / 2) - s_ * (sy * s / 2)
            py = y + s_ * (sx * s / 2) + c * (sy * s / 2)
            objs.append(box(0.07, 0.07, s, (px, py, z), tm, rot=(0, 0, rot)))
    return objs


def sack(x, y, z=0.0, s=1.0, col=(170, 148, 108), rot=0.0):
    o = sphere(0.28 * s, (x, y, z + 0.24 * s), cloth(col), scale=(1.05, 0.85, 0.95), segs=10)
    # slumped burlap: flatten the bottom, pinch the top
    for v in o.data.vertices:
        if v.co.z < -0.12 * s:
            v.co.z = -0.12 * s + (v.co.z + 0.12 * s) * 0.3
        if v.co.z > 0.16 * s:
            v.co.x *= 0.75
            v.co.y *= 0.75
    o.rotation_euler = (0.1, 0.05, rot)
    tie = cyl(0.07 * s, 0.12 * s, (x, y, z + 0.52 * s), cloth(tuple(int(v * 0.8) for v in col)), verts=8)
    return [o, tie]
