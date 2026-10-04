"""Phase 1B citizens: readable silhouettes per role, livery, tools, and the animations
idle / walk / carry / work / talk / train (soldiers).

Rendered in 5 directions (S, SE, E, NE, N); SW, W, NW are mirrored in Godot.
Run:  python blender/people2.py [--only farmer,soldier] [--samples 12]
Output: game/assets/sprites/people/<role>.png (atlas) + people.json
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kdrender as R  # noqa: E402
import kit2 as K2  # noqa: E402
import slice_landmarks as LM  # noqa: E402

OUT = os.path.join(R.K.GAME_DIR, "assets", "sprites", "people")
DIRS = {"S": 0.0, "SE": 45.0, "E": 90.0, "NE": 135.0, "N": 180.0}
BASE_ANIMS = {"idle": 4, "walk": 8, "carry": 8, "work": 8, "talk": 8}
CELL = (72, 92)              # final cell (px) at 32 px/m
ANCHOR = (36, 82)
PPM = 64
SCALE = 1.18                 # figures are drawn slightly larger than life (readability, as in the references)

LIVERY = (150, 30, 32)
ROLES = {
    "farmer": dict(shirt=(214, 204, 176), vest=(118, 92, 60), pants=(84, 92, 120), hat="straw", hair=(96, 66, 40),
                   tool="hoe", carry="sack", skin=(214, 168, 132)),
    "woodcutter": dict(shirt=(62, 96, 58), pants=(88, 70, 50), hat="cap_red", hair=(70, 46, 30), tool="axe",
                       carry="logs", skin=(204, 156, 120), beard=True),
    "builder": dict(shirt=(176, 150, 112), pants=(96, 80, 60), apron=(186, 170, 136), hat="cap_brown",
                    hair=(120, 84, 50), tool="hammer", carry="plank", skin=(214, 168, 132)),
    "artisan": dict(shirt=(196, 186, 162), pants=(70, 64, 60), apron=(92, 62, 40), hat="none", hair=(54, 40, 30),
                    tool="hammer", carry="crate", skin=(206, 160, 126), beard=True),
    "merchant": dict(shirt=(40, 104, 108), robe=(40, 104, 108), pants=(70, 50, 44), hat="felt", hair=(60, 44, 34),
                     tool="none", carry="crate", skin=(220, 176, 140), belt=(176, 140, 60)),
    "guard": dict(shirt=(150, 150, 156), tabard=LIVERY, pants=(70, 64, 60), hat="kettle", hair=(70, 50, 36),
                  tool="spear", carry="shield", skin=(206, 160, 126), mail=True),
    "soldier": dict(shirt=(150, 150, 156), tabard=LIVERY, pants=(86, 66, 52), hat="helmet", hair=(70, 50, 36),
                    tool="spear", carry="shield", skin=(206, 160, 126), mail=True, train=True),
    "citizen": dict(shirt=(70, 92, 140), pants=(110, 90, 70), hat="none", hair=(110, 70, 40), tool="basket",
                    carry="basket", skin=(220, 176, 140)),
    "woman": dict(shirt=(226, 216, 196), dress=(126, 70, 60), apron=(222, 210, 184), hat="kerchief", pants=(126, 70, 60),
                  hair=(110, 70, 40), tool="basket", carry="basket", skin=(226, 182, 148)),
}


def mat(col, rough=0.8, noise=0.1):
    return K2.flat(col, rough=rough, noise=noise, scale=14.0, ao=0.6)


def capsule(rad, length, m, scale=(1, 1, 1), segs=14):
    """Capsule hanging from its joint (origin) down to -length."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=segs, ring_count=10, location=(0, 0, -50))
    o = bpy.context.object
    bpy.ops.object.shade_smooth()
    rz = rad * scale[2]
    for v in o.data.vertices:
        z = v.co.z
        v.co.x *= rad * scale[0]
        v.co.y *= rad * scale[1]
        v.co.z = (-rz + z * rz) if z >= 0 else (-(length - rz) + z * rz)
    o.data.update()
    o.data.materials.append(m)
    return o


def uv_quad(w, h, m, back=False):
    """Vertical quad (XZ plane) hanging from its top edge, UV 0..1 (heraldry on tabards)."""
    import bmesh
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    pts = [(-w / 2, 0, -h), (w / 2, 0, -h), (w / 2, 0, 0), (-w / 2, 0, 0)]
    if back:
        pts = pts[::-1]
    vs = [bm.verts.new(p) for p in pts]
    f = bm.faces.new(vs)
    for loop in f.loops:
        co = loop.vert.co
        loop[uvl].uv = (co.x / w + 0.5, 1.0 + co.z / h * 0.85)
    o = K2.link_obj(bm, "quad", m)
    sol = o.modifiers.new("s", "SOLIDIFY")
    sol.thickness = 0.02
    return o


def cone_part(r1, r2, depth, m, squash_y=0.8):
    bpy.ops.mesh.primitive_cone_add(vertices=18, radius1=r1, radius2=r2, depth=depth, location=(0, 0, -50))
    o = bpy.context.object
    for v in o.data.vertices:
        v.co.z -= depth / 2
        v.co.y *= squash_y
    bpy.ops.object.shade_smooth()
    o.data.materials.append(m)
    return o


class Person:
    def __init__(self, role):
        r = ROLES[role]
        self.role = role
        self.r = r
        self.parts = {}
        skin = mat(r["skin"], 0.6, 0.03)
        shirt = mat(r["shirt"], noise=0.12)
        pants = mat(r["pants"])
        boots = mat((58, 42, 30))
        hair = mat(r["hair"])

        def part(name, o):
            o.name = name
            self.parts[name] = o
            return o
        torso_m = mat((150, 150, 156), 0.35, 0.05) if r.get("mail") else shirt
        part("torso", capsule(0.18, 0.52, torso_m, scale=(1.25, 0.82, 1.0)))
        part("pelvis", capsule(0.16, 0.2, pants, scale=(1.1, 0.8, 1.0)))
        if r.get("vest"):
            part("vest", capsule(0.185, 0.4, mat(r["vest"]), scale=(1.27, 0.86, 1.0)))
        if r.get("tabard"):
            part("tabard", uv_quad(0.42, 0.78, LM.banner_mat("lion")))
            part("tabard_b", uv_quad(0.42, 0.78, mat(r["tabard"]), back=True))
        if r.get("dress"):
            part("skirt", cone_part(0.34, 0.17, 0.78, mat(r["dress"], noise=0.15)))
        elif r.get("robe"):
            part("skirt", cone_part(0.3, 0.17, 0.72, mat(r["robe"], noise=0.15)))
        else:
            part("skirt", cone_part(0.24, 0.17, 0.3, shirt))
        if r.get("apron"):
            part("apron", K2.box(0.3, 0.04, 0.62 if r.get("dress") else 0.52, (0, -50, 0), mat(r["apron"])))
        if r.get("belt"):
            bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.2, depth=0.07, location=(0, 0, -50))
            b = bpy.context.object
            for v in b.data.vertices:
                v.co.y *= 0.82
            b.data.materials.append(mat(r["belt"], 0.4))
            part("belt", b)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.145, segments=16, ring_count=12, location=(0, 0, -50))
        hd = bpy.context.object
        bpy.ops.object.shade_smooth()
        hd.data.materials.append(skin)
        part("head", hd)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.152, segments=16, ring_count=12, location=(0, 0, -50))
        hr = bpy.context.object
        for v in hr.data.vertices:
            if v.co.z < -0.02 and v.co.y < 0:
                v.co.z = -0.02 + (v.co.z + 0.02) * 0.15
        bpy.ops.object.shade_smooth()
        hr.data.materials.append(hair)
        part("hair", hr)
        if r.get("beard"):
            part("beard", K2.sphere(0.09, (0, 0, -50), hair, scale=(1.0, 0.7, 0.9), segs=8))
        self._hat(r["hat"])
        sleeve = shirt if not r.get("mail") else torso_m
        for side in ("L", "R"):
            part("uarm" + side, capsule(0.068, 0.29, sleeve))
            part("farm" + side, capsule(0.06, 0.27, sleeve if (r.get("robe") or r.get("mail")) else skin))
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.062, segments=10, ring_count=8, location=(0, 0, -50))
            hnd = bpy.context.object
            hnd.data.materials.append(skin)
            part("hand" + side, hnd)
            part("thigh" + side, capsule(0.09, 0.43, pants))
            part("shin" + side, capsule(0.074, 0.43, pants if not r.get("dress") else mat((180, 170, 150))))
            ft = K2.box(0.13, 0.26, 0.1, (0, -50, 0), boots)
            for v in ft.data.vertices:
                v.co.y -= 0.06
            part("foot" + side, ft)
        self.tool = self._tool(r["tool"])
        self.load = self._load(r["carry"])

    def _hat(self, kind):
        straw = K2.straw("X")
        if kind == "straw":
            self.parts["hat"] = K2.cyl(0.29, 0.035, (0, 0, -50), straw, verts=22)
            self.parts["hat2"] = K2.cyl(0.15, 0.13, (0, 0, -50), straw, verts=16, r2=0.1)
        elif kind == "cap_red":
            o = K2.sphere(0.15, (0, 0, -50), mat((168, 44, 36)), segs=12)
            for v in o.data.vertices:
                v.co.z = max(v.co.z, -0.01)
            self.parts["hat"] = o
        elif kind == "cap_brown":
            o = K2.sphere(0.155, (0, 0, -50), mat((110, 82, 54)), segs=12)
            for v in o.data.vertices:
                v.co.z = max(v.co.z, -0.01)
            self.parts["hat"] = o
        elif kind == "felt":
            self.parts["hat"] = K2.cyl(0.24, 0.03, (0, 0, -50), mat((40, 46, 70)), verts=18)
            self.parts["hat2"] = K2.cyl(0.15, 0.16, (0, 0, -50), mat((40, 46, 70)), verts=16, r2=0.13)
            self.parts["feather"] = K2.box(0.03, 0.03, 0.22, (0, -50, 0), mat((200, 60, 50)))
        elif kind in ("helmet", "kettle"):
            o = K2.sphere(0.155, (0, 0, -50), K2.flat((176, 178, 184), rough=0.25, noise=0.04, metal=0.5), segs=14)
            for v in o.data.vertices:
                v.co.z = max(v.co.z, -0.03)
            self.parts["hat"] = o
            if kind == "kettle":
                self.parts["hat2"] = K2.cyl(0.25, 0.025, (0, 0, -50), K2.flat((176, 178, 184), rough=0.25, metal=0.5), verts=18)
            else:
                self.parts["hat2"] = K2.box(0.03, 0.07, 0.13, (0, -50, 0), K2.flat((176, 178, 184), metal=0.5))
        elif kind == "kerchief":
            o = K2.sphere(0.158, (0, 0, -50), mat((228, 220, 200)), segs=12)
            for v in o.data.vertices:
                v.co.z = max(v.co.z, -0.04)
            self.parts["hat"] = o

    def _tool(self, kind):
        wood = mat((122, 92, 60))
        iron = K2.flat((96, 98, 104), rough=0.35, noise=0.05, metal=0.4)
        objs = {}
        if kind == "none":
            self.tool_kind = "none"
            return objs
        if kind == "basket":
            self.tool_kind = "basket"
            objs["basket"] = K2.cyl(0.17, 0.2, (0, 0, -50), K2.planks((176, 134, 84), 0.05, True, 0.2), verts=14, r2=0.21)
            return objs
        L = {"hoe": 1.45, "axe": 0.95, "hammer": 0.48, "spear": 2.2}[kind]
        objs["handle"] = K2.cyl(0.024, L, (0, 0, -50), wood, verts=8)
        if kind == "hoe":
            objs["head"] = K2.box(0.24, 0.025, 0.14, (0, -50, 0), iron)
        elif kind == "axe":
            objs["head"] = K2.box(0.06, 0.2, 0.16, (0, -50, 0), iron)
        elif kind == "hammer":
            objs["head"] = K2.box(0.09, 0.16, 0.09, (0, -50, 0), iron)
        elif kind == "spear":
            objs["head"] = K2.cyl(0.045, 0.26, (0, 0, -50), iron, verts=6, r2=0.002)
            objs["shield"] = K2.cyl(0.3, 0.05, (0, 0, -50), K2.flat(LIVERY, noise=0.08), verts=20)
        self.tool_len = L
        self.tool_kind = kind
        return objs

    def _load(self, kind):
        if kind == "sack":
            o = K2.sphere(0.22, (0, 0, -50), K2.cloth((200, 182, 140)), scale=(1.3, 0.9, 1.0), segs=12)
        elif kind == "logs":
            o = K2.cyl(0.1, 1.1, (0, 0, -50), mat((114, 82, 52)), verts=10)
        elif kind == "plank":
            o = K2.box(0.14, 1.7, 0.05, (0, -50, 0), mat((186, 148, 100)))
        elif kind == "crate":
            o = K2.box(0.44, 0.36, 0.36, (0, -50, 0), K2.planks((150, 112, 70), 0.1, False, 0.1))
        elif kind == "shield":
            o = K2.cyl(0.3, 0.05, (0, 0, -50), K2.flat(LIVERY, noise=0.08), verts=20)
        else:
            o = K2.cyl(0.19, 0.22, (0, 0, -50), K2.planks((176, 134, 84), 0.05, True, 0.2), verts=14, r2=0.23)
        o.hide_render = True
        return o

    # --------------------------------------------------------------------------------------------
    def pose(self, anim, t, yaw_deg):
        ph = 2 * math.pi * t
        P = {"lean": 0.0, "bob": 0.0, "shL": 0.05, "shR": 0.05, "elL": -0.18, "elR": -0.18, "abL": 0.1, "abR": 0.1,
             "hipL": 0.0, "hipR": 0.0, "knL": 0.0, "knR": 0.0, "head": 0.0, "nod": 0.0, "twist": 0.0}
        if anim in ("walk", "carry"):
            s_ = math.sin(ph)
            P["hipL"], P["hipR"] = 0.45 * s_, -0.45 * s_
            P["knL"] = 0.75 * max(0.0, math.sin(ph + 1.9))
            P["knR"] = 0.75 * max(0.0, math.sin(ph + 1.9 + math.pi))
            P["bob"] = 0.028 * abs(math.cos(ph))
            P["shL"], P["shR"] = -0.42 * s_, 0.42 * s_
            P["elL"] = P["elR"] = -0.4
            P["lean"] = 0.07
        if anim == "idle":
            P["bob"] = 0.006 * math.sin(ph)
            P["head"] = 0.12 * math.sin(ph)
            if self.tool_kind == "spear":
                P["shR"], P["elR"] = -0.35, -0.9
        if anim == "talk":
            g = math.sin(ph)
            P["shR"] = -0.9 - 0.45 * max(0.0, g)
            P["elR"] = -1.1 + 0.35 * g
            P["abR"] = 0.35
            P["shL"] = -0.25 - 0.3 * max(0.0, -g)
            P["elL"] = -0.9
            P["head"] = 0.18 * math.sin(ph * 0.5)
            P["nod"] = 0.08 * math.sin(ph * 2)
            P["twist"] = 0.1 * math.sin(ph)
        if anim == "carry":
            if self.r["carry"] in ("sack", "logs", "plank"):
                P["shR"], P["elR"], P["abR"] = -2.7, -1.9, 0.28
            else:
                P["shL"] = P["shR"] = -0.72
                P["elL"] = P["elR"] = -1.3
                P["abL"] = P["abR"] = 0.24
        if anim == "work":
            k = self.tool_kind
            if k in ("axe", "hammer"):
                up = -0.5 - 2.4 * math.sin(math.pi * t) ** 0.6
                P["shL"] = P["shR"] = up
                P["elL"] = P["elR"] = -0.3
                P["lean"] = 0.18 + 0.25 * (1 - math.sin(math.pi * t))
                if k == "hammer":
                    P["shL"], P["elL"] = -0.7, -1.2
            elif k == "hoe":
                sw = math.sin(ph)
                P["shL"] = P["shR"] = -0.9 + 0.5 * sw
                P["elL"] = P["elR"] = -0.5
                P["lean"] = 0.32 + 0.12 * sw
            elif k == "spear":
                P["shR"], P["elR"] = -0.35, -0.9
                P["head"] = 0.3 * math.sin(ph)
            elif k == "basket":
                # gathering / picking: bend down and reach
                d = 0.5 - 0.5 * math.cos(ph)
                P["lean"] = 0.15 + 0.45 * d
                P["shR"] = -0.8 - 0.6 * d
                P["elR"] = -0.4
                P["shL"], P["elL"] = -0.6, -1.2
                P["knL"] = P["knR"] = 0.25 * d
                P["hipL"] = P["hipR"] = -0.25 * d
            else:
                P["shR"] = -1.1 - 0.4 * math.sin(ph)
                P["elR"] = -1.2
                P["shL"], P["elL"] = -0.5, -1.4
                P["head"] = 0.15 * math.sin(ph)
        if anim == "train":
            # spear drill: guard, thrust, recover (with a step)
            th = max(0.0, math.sin(ph)) ** 0.7
            P["shR"] = -1.25 - 0.25 * th
            P["elR"] = -1.5 + 1.4 * th
            P["shL"] = -0.9 - 0.2 * th
            P["elL"] = -1.3 + 0.5 * th
            P["hipL"], P["hipR"] = -0.45 * (0.6 + 0.4 * th), 0.35
            P["knL"], P["knR"] = 0.3 + 0.2 * th, 0.15
            P["lean"] = 0.1 + 0.22 * th
            P["twist"] = -0.25 + 0.35 * th
        self._apply(P, math.radians(yaw_deg), anim)

    def _apply(self, P, yaw, anim):
        S = Matrix.Scale(SCALE, 4)
        W = S @ Matrix.Rotation(yaw, 4, "Z")
        pelvis = W @ Matrix.Translation((0, 0, 0.95 + P["bob"]))
        spine = pelvis @ Matrix.Rotation(P["lean"], 4, "X") @ Matrix.Rotation(P["twist"], 4, "Z")
        place = {"pelvis": pelvis @ Matrix.Translation((0, 0, 0.12)),
                 "skirt": spine @ Matrix.Translation((0, 0, 0.18)),
                 "torso": spine @ Matrix.Translation((0, 0, 0.58)),
                 "vest": spine @ Matrix.Translation((0, 0, 0.56)),
                 "tabard": spine @ Matrix.Translation((0, -0.165, 0.56)),
                 "tabard_b": spine @ Matrix.Translation((0, 0.165, 0.56)),
                 "apron": spine @ Matrix.Translation((0, -0.17, -0.4 if self.r.get("dress") else -0.28)),
                 "belt": spine @ Matrix.Translation((0, 0, 0.13))}
        neck = spine @ Matrix.Translation((0, 0, 0.62)) @ Matrix.Rotation(P["head"], 4, "Z") @ Matrix.Rotation(P["nod"], 4, "X")
        place["head"] = neck @ Matrix.Translation((0, 0, 0.12))
        place["hair"] = neck @ Matrix.Translation((0, 0.014, 0.135))
        place["beard"] = neck @ Matrix.Translation((0, -0.1, 0.06))
        place["hat"] = neck @ Matrix.Translation((0, 0.0, 0.2))
        place["hat2"] = neck @ Matrix.Translation((0, 0.0, 0.215))
        place["feather"] = neck @ Matrix.Translation((0.1, 0.05, 0.25)) @ Matrix.Rotation(-0.6, 4, "Y")
        if self.r["hat"] == "helmet":
            place["hat2"] = neck @ Matrix.Translation((0, -0.13, 0.06))
        if self.r["hat"] == "kettle":
            place["hat2"] = neck @ Matrix.Translation((0, 0, 0.17))
        if self.r["hat"] == "straw":
            place["hat"] = neck @ Matrix.Translation((0, 0, 0.21))
        hands = {}
        for side, sx in (("L", 1), ("R", -1)):
            sh = spine @ Matrix.Translation((sx * 0.21, 0, 0.52)) @ Matrix.Rotation(P["sh" + side], 4, "X") \
                @ Matrix.Rotation(-sx * P["ab" + side], 4, "Y")
            place["uarm" + side] = sh
            el = sh @ Matrix.Translation((0, 0, -0.29)) @ Matrix.Rotation(P["el" + side], 4, "X")
            place["farm" + side] = el
            hands[side] = el @ Matrix.Translation((0, 0, -0.29))
            place["hand" + side] = hands[side]
            hip = pelvis @ Matrix.Translation((sx * 0.1, 0, 0.02)) @ Matrix.Rotation(P["hip" + side], 4, "X")
            place["thigh" + side] = hip
            kn = hip @ Matrix.Translation((0, 0, -0.45)) @ Matrix.Rotation(P["kn" + side], 4, "X")
            place["shin" + side] = kn
            ank = kn @ Matrix.Translation((0, 0, -0.45))
            loc = ank.to_translation()
            place["foot" + side] = Matrix.Translation((loc.x, loc.y, max(loc.z - 0.09 * SCALE, 0.0))) @ W
        for name, o in self.parts.items():
            if name in place:
                o.matrix_world = place[name]
                o.hide_render = False
            else:
                o.hide_render = True
        for o in self.tool.values():
            o.hide_render = True
        self.load.hide_render = True
        k = self.tool_kind
        if anim == "carry":
            kind = self.r["carry"]
            if kind in ("sack", "logs", "plank"):
                m = spine @ Matrix.Translation((-0.18, 0.0, 0.8))
                if kind == "logs":
                    m = m @ Matrix.Rotation(math.pi / 2, 4, "X")
                self.load.matrix_world = m
            else:
                mid = (hands["L"].to_translation() + hands["R"].to_translation()) / 2
                self.load.matrix_world = Matrix.Translation(mid + Vector((0, 0, -0.06))) @ W
            self.load.hide_render = False
        elif k == "basket":
            if anim in ("idle", "walk", "talk", "work"):
                self.tool["basket"].matrix_world = hands["L"] @ Matrix.Translation((0, 0, -0.18)) @ Matrix.Rotation(-P["shL"], 4, "X")
                self.tool["basket"].hide_render = False
        elif self.tool:
            if anim in ("work", "train") or k == "spear":
                grip = hands["R"] @ Matrix.Rotation(math.pi / 2 if k != "spear" else -0.15, 4, "X")
                if k == "hoe":
                    grip = hands["R"] @ Matrix.Rotation(math.pi / 2 + 0.6, 4, "X")
                if k == "spear" and anim == "train":
                    grip = hands["R"] @ Matrix.Rotation(math.pi / 2 + 0.25, 4, "X")
                h = self.tool["handle"]
                h.matrix_world = grip @ Matrix.Translation((0, 0, -self.tool_len * 0.3))
                h.hide_render = False
                if "head" in self.tool:
                    self.tool["head"].matrix_world = grip @ Matrix.Translation((0, 0, self.tool_len * 0.7))
                    self.tool["head"].hide_render = False
                if "shield" in self.tool:
                    self.tool["shield"].matrix_world = hands["L"] @ Matrix.Rotation(math.pi / 2, 4, "X") \
                        @ Matrix.Translation((0, 0, -0.08))
                    self.tool["shield"].hide_render = False


# ------------------------------------------------------------------------------------------------
def render_frame(tag, samples):
    sc = bpy.context.scene
    sc.cycles.samples = samples
    p = os.path.join(R.TMP, f"p2_{tag}.exr")
    sc.render.filepath = p
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(p, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1].copy()


def setup_camera(cell=CELL, anchor=ANCHOR):
    w_m, h_m = cell[0] / 32.0, cell[1] / 32.0
    x0 = -anchor[0] / 32.0
    y_top = anchor[1] / 32.0
    R.frame_camera((x0, x0 + w_m, y_top - h_m, y_top), PPM)
    bpy.data.objects["ground"].hide_render = True


def to_cell(img, cell=CELL):
    a = img[..., 3:4]
    rgb = img[..., :3] / np.maximum(a, 1e-4)
    prem = R.downsample(np.concatenate([rgb * a, a], -1), 2)
    a2 = prem[..., 3:4]
    rgb2 = prem[..., :3] / np.maximum(a2, 1e-4)
    rgb2 = R.grade_illustrated(rgb2)
    rgb2 = R.sharpen(rgb2, a2, 0.35)
    srgb = R.tonemap(rgb2)
    out = (np.clip(np.concatenate([srgb, a2], -1), 0, 1) * 255 + 0.5).astype(np.uint8)
    return out[:cell[1], :cell[0]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--samples", type=int, default=12)
    ap.add_argument("--test", action="store_true")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    os.makedirs(OUT, exist_ok=True)
    meta_path = os.path.join(OUT, "people.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    roles = [r for r in ROLES if not args.only or r in args.only.split(",")]
    for role in roles:
        R.reset_scene()
        R.illustrated_light()
        R.outlines(True, thickness=1.2, alpha=0.6)
        bpy.context.scene.cycles.use_adaptive_sampling = False
        K2.reset_cache()
        setup_camera()
        person = Person(role)
        anims = dict(BASE_ANIMS)
        if ROLES[role].get("train"):
            anims["train"] = 8
        rows, layout = [], {}
        for anim, nf in anims.items():
            for d, yaw in DIRS.items():
                if args.test and d not in ("S", "SE"):
                    continue
                frames = []
                for f in range(nf):
                    person.pose(anim, f / nf, yaw)
                    bpy.context.view_layer.update()
                    frames.append(to_cell(render_frame(role, args.samples)))
                layout[f"{anim}_{d}"] = len(rows)
                rows.append(frames)
            print(role, anim, "done", flush=True)
        maxf = max(anims.values())
        atlas = np.zeros((len(rows) * CELL[1], maxf * CELL[0], 4), np.uint8)
        for ri, frames in enumerate(rows):
            for fi, cell in enumerate(frames):
                atlas[ri * CELL[1]:ri * CELL[1] + cell.shape[0], fi * CELL[0]:fi * CELL[0] + cell.shape[1]] = cell
        Image.fromarray(atlas, "RGBA").save(os.path.join(OUT, f"{role}.png"), optimize=True)
        meta[role] = {"cell": list(CELL), "anchor": list(ANCHOR), "rows": layout, "frames": anims}
        json.dump(meta, open(meta_path, "w"), indent=1)
        print("rendered", role, atlas.shape, flush=True)


if __name__ == "__main__":
    main()
