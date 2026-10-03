"""King's Domain citizens: procedural humanoids, role outfits/tools, animation frames -> atlases.

Roles: farmer, woodcutter, miner, builder, merchant, soldier, citizen
Animations: idle (4 frames), walk (8), carry (8), work (8)
Directions rendered: S, SE, E, NE, N (SW, W, NW are mirrored in Godot)

Run:  python blender/citizens.py [--only farmer] [--samples 16]
Output: game/assets/sprites/citizens/<role>.png (atlas) + citizens.json
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bkit as B  # noqa: E402
import kdrender as R  # noqa: E402

OUT = os.path.join(R.K.GAME_DIR, "assets", "sprites", "citizens")
DIRS = {"S": 0.0, "SE": 45.0, "E": 90.0, "NE": 135.0, "N": 180.0}
ANIMS = {"idle": 4, "walk": 8, "carry": 8, "work": 8}
CELL = (56, 72)              # final cell size (px) at 32 px/m
PPM = 64                     # render density (2x supersampling)

ROLES = {
    "farmer": dict(tunic=(132, 116, 70), pants=(96, 78, 56), hat="straw", hair=(96, 66, 40), tool="hoe",
                   carry="sack", skin=(214, 168, 132)),
    "woodcutter": dict(tunic=(62, 92, 56), pants=(84, 66, 48), hat="cap_red", hair=(70, 46, 30), tool="axe",
                       carry="logs", skin=(204, 156, 120)),
    "miner": dict(tunic=(92, 88, 84), pants=(66, 60, 56), hat="hood_brown", hair=(50, 40, 34), tool="pick",
                  carry="ore", skin=(196, 150, 116)),
    "builder": dict(tunic=(150, 120, 80), pants=(90, 74, 56), apron=(176, 160, 128), hat="none", hair=(120, 84, 50),
                    tool="hammer", carry="plank", skin=(214, 168, 132)),
    "merchant": dict(tunic=(128, 42, 40), pants=(70, 50, 44), robe=True, hat="hat_blue", hair=(60, 44, 34),
                     tool="none", carry="crate", skin=(220, 176, 140), belt=(150, 120, 50)),
    "soldier": dict(tunic=(44, 64, 128), pants=(70, 66, 62), mail=True, hat="helmet", hair=(70, 50, 36),
                    tool="spear", carry="shield", skin=(206, 160, 126)),
    "citizen": dict(tunic=(160, 140, 110), pants=(110, 90, 70), dress=(150, 80, 60), hat="kerchief",
                    hair=(110, 70, 40), tool="broom", carry="basket", skin=(220, 176, 140)),
}


def M(name, col, rough=0.8, noise=0.08):
    return B.flat_mat(name, col, rough=rough, noise=noise, bump=0.05, nscale=12.0)


class Person:
    """A set of body-part objects posed by forward kinematics every frame."""

    def __init__(self, role):
        r = ROLES[role]
        self.role = role
        self.r = r
        skin = M("skin_" + role, r["skin"], rough=0.6, noise=0.03)
        cloth = M("tunic_" + role, r["tunic"], noise=0.15)
        pants = M("pants_" + role, r["pants"])
        boots = M("boots", (56, 42, 32))
        hair = M("hair_" + role, r["hair"])
        self.parts = {}

        def part(name, obj):
            obj.name = name
            self.parts[name] = obj
            return obj

        def capsule(name, rad, length, mat, scale=(1, 1, 1)):
            """Capsule hanging from its joint (origin) down to -length."""
            bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=14, ring_count=10, location=(0, 0, -50))
            o = bpy.context.object
            bpy.ops.object.shade_smooth()
            rz = rad * scale[2]
            for v in o.data.vertices:
                z = v.co.z
                v.co.x *= rad * scale[0]
                v.co.y *= rad * scale[1]
                v.co.z = (-rz + z * rz) if z >= 0 else (-(length - rz) + z * rz)
            o.data.update()
            o.data.materials.append(mat)
            return part(name, o)

        torso_mat = cloth
        if r.get("mail"):
            torso_mat = B.brick_mat("mail", (150, 150, 156), (130, 130, 136), (70, 70, 74), 0.04, 0.03, bump=0.4,
                                    noise_amt=0.05, rough=0.4)
        capsule("torso", 0.17, 0.5, cloth, scale=(1.22, 0.85, 1.0))
        capsule("pelvis", 0.15, 0.2, pants, scale=(1.1, 0.8, 1.0))
        if r.get("mail"):
            capsule("mail", 0.168, 0.36, torso_mat, scale=(1.15, 0.82, 1.0))
        # tunic skirt / robe / dress
        skirt_len = 0.62 if (r.get("robe") or r.get("dress")) else 0.34
        skirt_mat = M("dress_" + role, r["dress"]) if r.get("dress") else cloth
        bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=0.25 if skirt_len > 0.5 else 0.22, radius2=0.16,
                                        depth=skirt_len, location=(0, 0, -50))
        sk = bpy.context.object
        for v in sk.data.vertices:
            v.co.z -= skirt_len / 2
            v.co.y *= 0.8
        bpy.ops.object.shade_smooth()
        sk.data.materials.append(skirt_mat)
        part("skirt", sk)
        if r.get("apron"):
            part("apron", B.box(0.26, 0.04, 0.5, (0, -50, 0), M("apron", r["apron"])))
        if r.get("belt"):
            bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.19, depth=0.06, location=(0, 0, -50))
            bl = bpy.context.object
            for v in bl.data.vertices:
                v.co.y *= 0.82
            bl.data.materials.append(M("belt", r["belt"], rough=0.4))
            part("belt", bl)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.13, segments=16, ring_count=12, location=(0, 0, -50))
        hd = bpy.context.object
        bpy.ops.object.shade_smooth()
        hd.data.materials.append(skin)
        part("head", hd)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.137, segments=16, ring_count=12, location=(0, 0, -50))
        hr = bpy.context.object
        for v in hr.data.vertices:
            if v.co.z < -0.02 and v.co.y < 0:
                v.co.z = -0.02 + (v.co.z + 0.02) * 0.2
        bpy.ops.object.shade_smooth()
        hr.data.materials.append(hair)
        part("hair", hr)
        self._hat(r["hat"])
        for side in ("L", "R"):
            capsule("uarm" + side, 0.066, 0.28, cloth)
            capsule("farm" + side, 0.058, 0.26, cloth if r.get("robe") or r.get("mail") else skin)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, segments=10, ring_count=8, location=(0, 0, -50))
            hnd = bpy.context.object
            hnd.data.materials.append(skin)
            part("hand" + side, hnd)
            capsule("thigh" + side, 0.085, 0.42, pants)
            capsule("shin" + side, 0.07, 0.42, pants)
            ft = B.box(0.12, 0.24, 0.09, (0, -50, 0), boots)
            for v in ft.data.vertices:
                v.co.y -= 0.06
            part("foot" + side, ft)
        self.tool = self._tool(r["tool"])
        self.load = self._load(r["carry"])

    # --------------------------------------------------------------------------------------------
    def _hat(self, kind):
        if kind == "straw":
            o = B.cyl(0.24, 0.03, (0, 0, -50), B.thatch_mat("straw_hat", (196, 170, 104)), verts=20)
            c = B.cyl(0.13, 0.12, (0, 0, -50), B.thatch_mat("straw_hat", (196, 170, 104)), verts=16, r2=0.08)
            self.parts["hat"] = o
            self.parts["hat2"] = c
        elif kind == "cap_red":
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.13, segments=14, ring_count=8, location=(0, 0, -50))
            o = bpy.context.object
            for v in o.data.vertices:
                v.co.z = max(v.co.z, -0.01)
            o.data.materials.append(M("cap_red", (150, 44, 36)))
            self.parts["hat"] = o
        elif kind == "hood_brown":
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, segments=14, ring_count=10, location=(0, 0, -50))
            o = bpy.context.object
            for v in o.data.vertices:
                if v.co.y < -0.05 and v.co.z < 0.05:
                    v.co.y = -0.05
            o.data.materials.append(M("hood", (92, 70, 50)))
            self.parts["hat"] = o
            self.parts["lamp"] = B.box(0.05, 0.05, 0.05, (0, -50, 0), B.flat_mat("lampglow", (255, 210, 120),
                                                                                emission=((255, 200, 110), 6.0)))
        elif kind == "hat_blue":
            o = B.cyl(0.2, 0.03, (0, 0, -50), M("hat_blue", (40, 60, 110)), verts=18)
            c = B.cyl(0.13, 0.13, (0, 0, -50), M("hat_blue", (40, 60, 110)), verts=16, r2=0.12)
            self.parts["hat"] = o
            self.parts["hat2"] = c
        elif kind == "helmet":
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.135, segments=16, ring_count=10, location=(0, 0, -50))
            o = bpy.context.object
            for v in o.data.vertices:
                v.co.z = max(v.co.z, -0.02)
            bpy.ops.object.shade_smooth()
            o.data.materials.append(B.flat_mat("steel", (170, 172, 178), rough=0.25, noise=0.03))
            self.parts["hat"] = o
            self.parts["hat2"] = B.box(0.025, 0.06, 0.12, (0, -50, 0), B.flat_mat("steel", (170, 172, 178)))
        elif kind == "kerchief":
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.128, segments=14, ring_count=8, location=(0, 0, -50))
            o = bpy.context.object
            for v in o.data.vertices:
                v.co.z = max(v.co.z, 0.0)
            o.data.materials.append(M("kerchief", (220, 210, 186)))
            self.parts["hat"] = o

    def _tool(self, kind):
        wood = M("handle", (120, 90, 58))
        iron = B.flat_mat("tool_iron", (90, 92, 96), rough=0.35, noise=0.05)
        objs = {}
        if kind == "none":
            return objs
        L = {"hoe": 1.4, "axe": 0.95, "pick": 0.95, "hammer": 0.45, "spear": 2.1, "broom": 1.3}[kind]
        h = B.cyl(0.022, L, (0, 0, -50), wood, verts=8)
        for v in h.data.vertices:
            v.co.z -= 0.0
        objs["handle"] = h
        if kind == "hoe":
            objs["head"] = B.box(0.22, 0.02, 0.12, (0, -50, 0), iron)
        elif kind == "axe":
            objs["head"] = B.box(0.05, 0.18, 0.14, (0, -50, 0), iron)
        elif kind == "pick":
            objs["head"] = B.box(0.05, 0.42, 0.05, (0, -50, 0), iron)
        elif kind == "hammer":
            objs["head"] = B.box(0.08, 0.14, 0.08, (0, -50, 0), iron)
        elif kind == "spear":
            objs["head"] = B.cyl(0.04, 0.22, (0, 0, -50), iron, verts=6, r2=0.002)
            sh = B.cyl(0.28, 0.05, (0, 0, -50), B.flat_mat("shield", (46, 66, 132), noise=0.1), verts=20)
            objs["shield"] = sh
        elif kind == "broom":
            objs["head"] = B.cyl(0.08, 0.3, (0, 0, -50), B.thatch_mat("broom", (170, 140, 80)), verts=10, r2=0.03)
        self.tool_len = L
        self.tool_kind = kind
        return objs

    def _load(self, kind):
        if kind == "sack":
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, location=(0, 0, -50), segments=12, ring_count=8)
            o = bpy.context.object
            o.scale = (1.3, 0.9, 1.0)
            o.data.materials.append(B.flat_mat("sack", (196, 176, 136), noise=0.15, nscale=10.0))
        elif kind == "logs":
            o = B.cyl(0.09, 1.1, (0, 0, -50), M("log", (110, 80, 52)), verts=10)
        elif kind == "ore":
            o = B.box(0.36, 0.28, 0.26, (0, -50, 0), M("basket_ore", (80, 70, 64)))
        elif kind == "plank":
            o = B.box(0.12, 1.6, 0.05, (0, -50, 0), M("plank", (182, 144, 96)))
        elif kind == "crate":
            o = B.box(0.42, 0.34, 0.34, (0, -50, 0), B.wood_mat("crate", (146, 110, 70), plank=0.1, vertical=False))
        elif kind == "shield":
            o = B.cyl(0.28, 0.05, (0, 0, -50), B.flat_mat("shield", (46, 66, 132), noise=0.1), verts=20)
        else:  # basket
            o = B.cyl(0.18, 0.2, (0, 0, -50), B.thatch_mat("basket", (160, 120, 70)), verts=14, r2=0.22)
        o.hide_render = True
        return o

    # --------------------------------------------------------------------------------------------
    def pose(self, anim, t, yaw_deg):
        """Set every part transform for animation `anim` at phase t in [0,1)."""
        ph = 2 * math.pi * t
        P = {"lean": 0.0, "bob": 0.0, "twist": 0.0,
             "shL": 0.0, "shR": 0.0, "elL": -0.15, "elR": -0.15, "abL": 0.08, "abR": 0.08,
             "hipL": 0.0, "hipR": 0.0, "knL": 0.0, "knR": 0.0, "head": 0.0}
        walking = anim in ("walk", "carry")
        if walking:
            s_ = math.sin(ph)
            P["hipL"] = 0.42 * s_
            P["hipR"] = -0.42 * s_
            P["knL"] = 0.7 * max(0.0, math.sin(ph + 1.9))
            P["knR"] = 0.7 * max(0.0, math.sin(ph + 1.9 + math.pi))
            P["bob"] = 0.025 * abs(math.cos(ph))
            P["shL"] = -0.38 * s_
            P["shR"] = 0.38 * s_
            P["elL"] = -0.35
            P["elR"] = -0.35
            P["lean"] = 0.06
        if anim == "idle":
            P["bob"] = 0.006 * math.sin(ph)
            P["shL"] = 0.04 * math.sin(ph)
            P["shR"] = -0.04 * math.sin(ph)
            P["head"] = 0.08 * math.sin(ph)
        if anim == "carry":
            if self.r["carry"] in ("sack", "logs", "plank"):
                P["shR"] = -2.6
                P["elR"] = -1.9
                P["abR"] = 0.25
            else:   # held in front with both arms
                P["shL"] = P["shR"] = -0.7
                P["elL"] = P["elR"] = -1.3
                P["abL"] = P["abR"] = 0.22
        if anim == "work":
            k = self.r["tool"]
            if k in ("axe", "pick", "hammer"):
                # raise over the head, strike down
                a = 0.5 - 0.5 * math.cos(ph)
                up = -2.9 + 2.4 * (1 - a) if t < 0.65 else -0.5 - 2.4 * (1 - (t - 0.65) / 0.35)
                up = -0.5 - 2.4 * math.sin(math.pi * t) ** 0.6
                P["shL"] = P["shR"] = up
                P["elL"] = P["elR"] = -0.3
                P["abL"] = P["abR"] = 0.05
                P["lean"] = 0.18 + 0.25 * (1 - math.sin(math.pi * t))
                if k == "hammer":
                    P["shL"] = -0.6
                    P["elL"] = -1.2
            elif k in ("hoe", "broom"):
                sw = math.sin(ph)
                P["shL"] = P["shR"] = -0.9 + 0.45 * sw
                P["elL"] = P["elR"] = -0.5
                P["lean"] = 0.3 + 0.1 * sw
                P["abL"] = P["abR"] = 0.15
            elif k == "spear":
                th = max(0.0, math.sin(ph))
                P["shR"] = -1.2 - 0.3 * th
                P["elR"] = -1.4 + 1.3 * th
                P["shL"] = -0.8
                P["elL"] = -1.2
                P["hipL"] = -0.35
                P["hipR"] = 0.3
                P["knL"] = 0.25
                P["lean"] = 0.12 + 0.12 * th
            else:   # merchant: gesturing / weighing goods
                P["shR"] = -1.1 - 0.4 * math.sin(ph)
                P["elR"] = -1.2
                P["shL"] = -0.5
                P["elL"] = -1.4
                P["head"] = 0.15 * math.sin(ph)
        self._apply(P, math.radians(yaw_deg), anim)

    def _apply(self, P, yaw, anim):
        W = Matrix.Rotation(yaw, 4, "Z")
        pelvis = W @ Matrix.Translation((0, 0, 0.94 + P["bob"]))
        spine = pelvis @ Matrix.Rotation(P["lean"], 4, "X")
        place = {}
        place["pelvis"] = pelvis @ Matrix.Translation((0, 0, 0.12))
        place["skirt"] = spine @ Matrix.Translation((0, 0, 0.18))
        place["torso"] = spine @ Matrix.Translation((0, 0, 0.56))
        place["mail"] = spine @ Matrix.Translation((0, 0, 0.5))
        place["apron"] = spine @ Matrix.Translation((0, -0.15, -0.28))
        place["belt"] = spine @ Matrix.Translation((0, 0, 0.12))
        neck = spine @ Matrix.Translation((0, 0, 0.6)) @ Matrix.Rotation(P["head"], 4, "Z")
        place["head"] = neck @ Matrix.Translation((0, 0, 0.11))
        place["hair"] = neck @ Matrix.Translation((0, 0.012, 0.125))
        place["hat"] = neck @ Matrix.Translation((0, 0.0, 0.19))
        place["hat2"] = neck @ Matrix.Translation((0, 0.0, 0.2))
        if self.r["hat"] == "helmet":
            place["hat2"] = neck @ Matrix.Translation((0, -0.12, 0.06))
        if self.r["hat"] == "hood_brown":
            place["hat"] = neck @ Matrix.Translation((0, 0.02, 0.13))
            place["lamp"] = neck @ Matrix.Translation((0, -0.13, 0.2))
        hands = {}
        for side, sx in (("L", 1), ("R", -1)):
            sh = spine @ Matrix.Translation((sx * 0.2, 0, 0.5)) @ Matrix.Rotation(P["sh" + side], 4, "X") \
                @ Matrix.Rotation(-sx * P["ab" + side], 4, "Y")
            place["uarm" + side] = sh
            el = sh @ Matrix.Translation((0, 0, -0.28)) @ Matrix.Rotation(P["el" + side], 4, "X")
            place["farm" + side] = el
            hands[side] = el @ Matrix.Translation((0, 0, -0.28))
            place["hand" + side] = hands[side]
            hip = pelvis @ Matrix.Translation((sx * 0.1, 0, 0.02)) @ Matrix.Rotation(P["hip" + side], 4, "X")
            place["thigh" + side] = hip
            kn = hip @ Matrix.Translation((0, 0, -0.44)) @ Matrix.Rotation(P["kn" + side], 4, "X")
            place["shin" + side] = kn
            ank = kn @ Matrix.Translation((0, 0, -0.44))
            # keep the foot flat on the ground plane orientation
            loc = ank.to_translation()
            place["foot" + side] = Matrix.Translation((loc.x, loc.y, max(loc.z - 0.08, 0.0))) @ W
        for name, o in self.parts.items():
            if name in place:
                o.matrix_world = place[name]
                o.hide_render = False
            else:
                o.hide_render = True
        # tool & load
        for o in self.tool.values():
            o.hide_render = True
        self.load.hide_render = True
        if anim == "carry":
            kind = self.r["carry"]
            if kind in ("sack", "logs", "plank"):
                m = spine @ Matrix.Translation((-0.17, 0.0, 0.78))
                if kind == "logs":
                    m = m @ Matrix.Rotation(math.pi / 2, 4, "X") @ Matrix.Translation((0, 0, 0.0))
                if kind == "plank":
                    m = m @ Matrix.Translation((0, 0, 0.0))
                self.load.matrix_world = m
            else:
                mid = (hands["L"].to_translation() + hands["R"].to_translation()) / 2
                self.load.matrix_world = Matrix.Translation(mid + Vector((0, 0, -0.05))) @ W
            self.load.hide_render = False
        elif self.tool:
            k = self.tool_kind
            if anim == "work" or k == "spear":
                grip = hands["R"] @ Matrix.Rotation(math.pi / 2 if k not in ("spear",) else -0.15, 4, "X")
                if k in ("hoe", "broom"):
                    grip = hands["R"] @ Matrix.Rotation(math.pi / 2 + 0.6, 4, "X")
                h = self.tool["handle"]
                # handle extends forward from the hand (origin at the cylinder base)
                h.matrix_world = grip @ Matrix.Translation((0, 0, self.tool_len * 0.25))
                h.hide_render = False
                tip = grip @ Matrix.Translation((0, 0, self.tool_len * 0.75))
                if "head" in self.tool:
                    self.tool["head"].matrix_world = tip
                    self.tool["head"].hide_render = False
                if "shield" in self.tool:
                    self.tool["shield"].matrix_world = hands["L"] @ Matrix.Rotation(math.pi / 2, 4, "X") \
                        @ Matrix.Translation((0, 0, -0.08))
                    self.tool["shield"].hide_render = False


# ------------------------------------------------------------------------------------------------
def render_frame(path_tag, samples):
    sc = bpy.context.scene
    sc.cycles.samples = samples
    p = os.path.join(R.TMP, f"cit_{path_tag}.exr")
    sc.render.filepath = p
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(p, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1].copy()


def setup_camera():
    # fixed frame: CELL at 32 px/m, anchor (feet) at (CELL.x/2, CELL.y - 8)
    sc = bpy.context.scene
    w_m = CELL[0] / 32.0
    h_m = CELL[1] / 32.0
    ax, ay = CELL[0] / 2, CELL[1] - 8
    x0 = -ax / 32.0
    y_top = ay / 32.0
    rect = (x0, x0 + w_m, y_top - h_m, y_top)
    R.frame_camera(rect, PPM)
    bpy.data.objects["ground"].hide_render = True
    return (ax, ay)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--samples", type=int, default=16)
    ap.add_argument("--test", action="store_true", help="only the S and E directions")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    os.makedirs(OUT, exist_ok=True)
    meta_path = os.path.join(OUT, "citizens.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    roles = [r for r in ROLES if not args.only or r in args.only.split(",")]
    for role in roles:
        R.reset_scene()
        bpy.context.scene.cycles.use_adaptive_sampling = False
        B._M.clear()
        anchor = setup_camera()
        person = Person(role)
        rows = []
        layout = {}
        for anim, nf in ANIMS.items():
            for d, yaw in DIRS.items():
                if args.test and d not in ("S", "E"):
                    continue
                frames = []
                for f in range(nf):
                    person.pose(anim, f / nf, yaw)
                    bpy.context.view_layer.update()
                    img = render_frame(f"{role}", args.samples)
                    a = img[..., 3:4]
                    rgb = img[..., :3] / np.maximum(a, 1e-4)
                    prem = np.concatenate([rgb * a, a], -1)
                    prem = R.downsample(prem, 2)
                    a2 = prem[..., 3:4]
                    srgb = R.tonemap(prem[..., :3] / np.maximum(a2, 1e-4))
                    cell = (np.clip(np.concatenate([srgb, a2], -1), 0, 1) * 255 + 0.5).astype(np.uint8)
                    cell = cell[:CELL[1], :CELL[0]]
                    frames.append(cell)
                layout[f"{anim}_{d}"] = len(rows)
                rows.append(frames)
            print(role, anim, "done", flush=True)
        maxf = max(ANIMS.values())
        atlas = np.zeros((len(rows) * CELL[1], maxf * CELL[0], 4), np.uint8)
        for r_i, frames in enumerate(rows):
            for f_i, cell in enumerate(frames):
                atlas[r_i * CELL[1]:r_i * CELL[1] + cell.shape[0], f_i * CELL[0]:f_i * CELL[0] + cell.shape[1]] = cell
        Image.fromarray(atlas, "RGBA").save(os.path.join(OUT, f"{role}.png"), optimize=True)
        meta[role] = {"cell": list(CELL), "anchor": list(anchor), "rows": layout,
                      "frames": {k: v for k, v in ANIMS.items()}}
        json.dump(meta, open(meta_path, "w"), indent=1)
        print("rendered", role, atlas.shape, flush=True)


if __name__ == "__main__":
    main()
