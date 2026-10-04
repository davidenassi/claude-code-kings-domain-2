"""Phase 1B animals: horse, pig, chicken, cow, sheep — simple procedural bodies with idle / walk / graze
animations in 5 directions (mirrored to 8 in Godot).

Run:  python blender/animals.py [--only horse] [--samples 12]
Output: game/assets/sprites/animals/<kind>.png (atlas) + animals.json
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kdrender as R  # noqa: E402
import kit2 as K2  # noqa: E402
import people2 as P2  # noqa: E402

OUT = os.path.join(R.K.GAME_DIR, "assets", "sprites", "animals")
DIRS = P2.DIRS
SPECIES = {
    #          cell (px)      anchor     anims
    "horse": ((128, 112), (64, 92), {"idle": 4, "walk": 8, "graze": 4}),
    "horse_dark": ((128, 112), (64, 92), {"idle": 4, "walk": 8, "graze": 4}),
    "cow": ((112, 96), (56, 80), {"idle": 4, "walk": 8, "graze": 4}),
    "pig": ((72, 56), (36, 44), {"idle": 4, "walk": 8, "graze": 4}),
    "sheep": ((72, 60), (36, 48), {"idle": 4, "walk": 8, "graze": 4}),
    "chicken": ((40, 40), (20, 32), {"idle": 4, "walk": 6, "graze": 4}),
}


def mat(col, rough=0.75, noise=0.1, scale=10):
    return K2.flat(col, rough=rough, noise=noise, scale=scale, ao=0.6)


def ellipsoid(r, scale, m, segs=14):
    o = K2.sphere(r, (0, 0, -50), m, scale=scale, segs=segs)
    # bake the scale so matrix_world can be set freely
    for v in o.data.vertices:
        v.co.x *= scale[0]
        v.co.y *= scale[1]
        v.co.z *= scale[2]
    o.scale = (1, 1, 1)
    return o


class Beast:
    def __init__(self, kind):
        self.kind = kind
        self.parts = {}
        k = kind
        if k.startswith("horse"):
            body_c = (120, 74, 44) if k == "horse" else (52, 40, 34)
            mane_c = (40, 28, 22) if k == "horse" else (24, 20, 18)
            # proportions of a riding horse: withers ~1.55 m, legs as long as the body is deep
            self.dim = dict(h=1.5, leg=0.95, legr=0.06, neck=0.85, head=0.58, sx=0.19, sy=0.6, tail=0.6, thigh=0.42)
            body, mane, hoof = mat(body_c), mat(mane_c), mat((40, 34, 30))
            self.parts["body"] = ellipsoid(0.36, (1.0, 2.25, 1.0), body)
            self.parts["chest"] = ellipsoid(0.3, (1.05, 0.9, 1.15), body)
            self.parts["haunch"] = ellipsoid(0.33, (1.08, 1.0, 1.12), body)
            self.parts["neck"] = P2.capsule(0.15, 0.85, body, scale=(0.85, 1.45, 1.0))
            self.parts["head"] = P2.capsule(0.1, 0.58, body, scale=(0.85, 1.35, 1.0))
            self.parts["mane"] = P2.capsule(0.05, 0.8, mane, scale=(0.7, 1.7, 1.0))
            for name in ("FL", "FR", "BL", "BR"):
                self.parts["thigh" + name] = P2.capsule(0.12 if name[0] == "B" else 0.1, 0.42, body,
                                                        scale=(0.8, 1.25, 1.0))
            self.parts["tail"] = P2.capsule(0.07, 0.65, mane)
            self.parts["ear"] = K2.cyl(0.04, 0.14, (0, 0, -50), body, verts=6, r2=0.0)
            if k == "horse_dark":
                self.parts["saddle"] = ellipsoid(0.3, (1.15, 0.9, 0.35), mat((150, 30, 32)))
            legm, hoofm = body, hoof
        elif k == "cow":
            self.dim = dict(h=1.05, leg=0.6, legr=0.08, sx=0.22, sy=0.6, neck=0.35, head=0.42, tail=0.6)
            body = K2.flat((236, 228, 214), rough=0.8, noise=0.0)
            spot = mat((92, 62, 44))
            self.parts["body"] = ellipsoid(0.45, (1.0, 1.85, 1.0), body)
            self.parts["spot"] = ellipsoid(0.3, (1.05, 1.2, 0.9), spot)
            self.parts["neck"] = P2.capsule(0.2, 0.4, body)
            self.parts["head"] = P2.capsule(0.15, 0.45, spot, scale=(0.9, 1.2, 1.0))
            self.parts["ear"] = K2.box(0.3, 0.05, 0.06, (0, -50, 0), K2.flat((200, 190, 170)))
            self.parts["tail"] = P2.capsule(0.03, 0.6, spot)
            legm, hoofm = body, mat((60, 50, 44))
        elif k == "pig":
            self.dim = dict(h=0.42, leg=0.25, legr=0.05, sx=0.13, sy=0.3, neck=0.1, head=0.22, tail=0.15)
            body = mat((232, 176, 160), noise=0.06)
            self.parts["body"] = ellipsoid(0.27, (1.0, 1.65, 0.95), body)
            self.parts["head"] = ellipsoid(0.17, (1.0, 1.0, 0.95), body)
            self.parts["snout"] = K2.cyl(0.07, 0.08, (0, 0, -50), mat((210, 140, 130)), verts=10)
            self.parts["ear"] = K2.box(0.22, 0.03, 0.08, (0, -50, 0), body)
            self.parts["tail"] = K2.sphere(0.04, (0, 0, -50), body, segs=6)
            legm, hoofm = body, mat((120, 80, 70))
        elif k == "sheep":
            self.dim = dict(h=0.55, leg=0.38, legr=0.04, sx=0.12, sy=0.28, neck=0.12, head=0.25, tail=0.1)
            wool = K2.roof("thatch_old")
            wool = K2.flat((232, 226, 210), rough=1.0, noise=0.25, scale=30)
            face = mat((40, 36, 34))
            self.parts["body"] = ellipsoid(0.32, (1.0, 1.4, 0.95), wool)
            self.parts["head"] = ellipsoid(0.12, (0.8, 1.3, 0.9), face)
            self.parts["ear"] = K2.box(0.26, 0.03, 0.05, (0, -50, 0), face)
            self.parts["tail"] = K2.sphere(0.06, (0, 0, -50), wool, segs=6)
            legm, hoofm = face, face
        else:  # chicken
            self.dim = dict(h=0.28, leg=0.14, legr=0.015, sx=0.04, sy=0.0, neck=0.1, head=0.08, tail=0.1)
            import random
            col = random.Random(7).choice([(232, 226, 214), (176, 104, 54)])
            self.col = col
            body = mat(col, noise=0.15)
            self.parts["body"] = ellipsoid(0.12, (0.85, 1.25, 0.95), body)
            self.parts["head"] = K2.sphere(0.06, (0, 0, -50), body, segs=8)
            self.parts["comb"] = K2.box(0.02, 0.06, 0.05, (0, -50, 0), mat((206, 40, 36)))
            self.parts["beak"] = K2.cyl(0.02, 0.05, (0, 0, -50), mat((226, 170, 60)), verts=5, r2=0.0)
            self.parts["tail"] = ellipsoid(0.07, (0.4, 1.0, 1.2), body)
            legm, hoofm = mat((220, 170, 70)), mat((220, 170, 70))
        for name in ("FL", "FR", "BL", "BR"):
            if k == "chicken" and name.startswith("B"):
                continue
            self.parts["leg" + name] = P2.capsule(self.dim["legr"], self.dim["leg"], legm)
            self.parts["hoof" + name] = K2.cyl(self.dim["legr"] * 1.1, 0.06, (0, 0, -50), hoofm, verts=8)

    def pose(self, anim, t, yaw_deg):
        k = self.kind
        d = self.dim
        ph = 2 * math.pi * t
        W = Matrix.Rotation(math.radians(yaw_deg), 4, "Z")
        h = d["h"]
        bob = 0.0
        swing = {"FL": 0.0, "FR": 0.0, "BL": 0.0, "BR": 0.0}
        head_pitch = 0.0
        if anim == "walk":
            s_ = math.sin(ph)
            amp = 0.42
            swing = {"FL": amp * s_, "BR": amp * s_, "FR": -amp * s_, "BL": -amp * s_}
            bob = 0.02 * abs(math.cos(ph)) * h
            head_pitch = 0.05 * math.sin(2 * ph)
        elif anim == "graze":
            head_pitch = 0.9 + 0.12 * math.sin(ph)
            if k == "chicken":
                head_pitch = 1.1 * max(0.0, math.sin(ph))
        else:
            head_pitch = 0.08 * math.sin(ph)
        place = {}
        body_z = h * 0.78 + bob
        if k == "chicken":
            body_z = d["leg"] + 0.08 + bob
        body = W @ Matrix.Translation((0, 0, body_z))
        place["body"] = body
        if "spot" in self.parts:
            place["spot"] = body @ Matrix.Translation((0.06, 0.12, 0.08))
        if "saddle" in self.parts:
            place["saddle"] = body @ Matrix.Translation((0, 0.05, 0.36))
        fwd = -1.0          # model front towards -Y (south) at yaw 0
        if k.startswith("horse"):
            place["chest"] = body @ Matrix.Translation((0, fwd * 0.5, 0.02))
            place["haunch"] = body @ Matrix.Translation((0, -fwd * 0.52, 0.04))
            # neck frame: +Z runs from the withers forwards and up (rotation about X tips +Z towards -Y = front);
            # capsules hang from their joint down -Z, so each is placed at the far end of its segment
            th = 0.62 + 1.25 * head_pitch
            neck = body @ Matrix.Translation((0, fwd * 0.62, 0.2)) @ Matrix.Rotation(th, 4, "X")
            L = d["neck"]
            place["neck"] = neck @ Matrix.Translation((0, 0, L))
            place["mane"] = neck @ Matrix.Translation((0, 0.11, L * 0.98))
            al = -0.62 + 0.45 * head_pitch                  # head points forward-down (grazing: nose to the grass)
            head = neck @ Matrix.Translation((0, 0, L)) @ Matrix.Rotation(al - th, 4, "X")
            place["head"] = head
            place["ear"] = neck @ Matrix.Translation((0.05, 0.06, L + 0.12))
            place["tail"] = body @ Matrix.Translation((0, -fwd * 0.95, 0.22)) @ Matrix.Rotation(-0.35 + 0.08 * math.sin(ph), 4, "X")
        elif k == "cow":
            th = 1.0 + 1.0 * head_pitch
            neck = body @ Matrix.Translation((0, fwd * 0.7, 0.1)) @ Matrix.Rotation(th, 4, "X")
            place["neck"] = neck @ Matrix.Translation((0, 0, 0.4))
            head = neck @ Matrix.Translation((0, 0, 0.4)) @ Matrix.Rotation(-0.5 + 0.4 * head_pitch - th, 4, "X")
            place["head"] = head
            place["ear"] = neck @ Matrix.Translation((0, 0, 0.45))
            place["tail"] = body @ Matrix.Translation((0, -fwd * 0.8, 0.25)) @ Matrix.Rotation(-0.15, 4, "X")
        elif k in ("pig", "sheep"):
            hy = 0.42 if k == "pig" else 0.44
            hz = 0.02 if k == "pig" else 0.18
            head = body @ Matrix.Translation((0, fwd * hy, hz - 0.25 * head_pitch)) @ Matrix.Rotation(-0.4 * head_pitch, 4, "X")
            place["head"] = head
            if "snout" in self.parts:
                place["snout"] = head @ Matrix.Translation((0, fwd * 0.16, -0.02)) @ Matrix.Rotation(math.pi / 2, 4, "X")
            place["ear"] = head @ Matrix.Translation((0, 0.02, 0.1))
            place["tail"] = body @ Matrix.Translation((0, -fwd * 0.44, 0.08))
        else:  # chicken
            head = body @ Matrix.Translation((0, fwd * 0.1, 0.12)) @ Matrix.Rotation(-head_pitch, 4, "X") @ Matrix.Translation((0, fwd * 0.05, 0.05))
            place["head"] = head
            place["comb"] = head @ Matrix.Translation((0, 0, 0.06))
            place["beak"] = head @ Matrix.Translation((0, fwd * 0.07, 0)) @ Matrix.Rotation(math.pi / 2, 4, "X")
            place["tail"] = body @ Matrix.Translation((0, -fwd * 0.13, 0.08)) @ Matrix.Rotation(0.5, 4, "X")
        for name in ("FL", "FR", "BL", "BR"):
            if "leg" + name not in self.parts:
                continue
            sx = d["sx"] * (1 if name.endswith("L") else -1)
            sy = d["sy"] * (fwd if name.startswith("F") else -fwd)
            top = W @ Matrix.Translation((sx, sy, d["leg"] + bob * 0.5)) @ Matrix.Rotation(swing[name], 4, "X")
            place["leg" + name] = top
            if "thigh" + name in self.parts:
                place["thigh" + name] = top @ Matrix.Translation((0, 0, 0.12))
            foot = (top @ Matrix.Translation((0, 0, -d["leg"]))).to_translation()
            place["hoof" + name] = Matrix.Translation((foot.x, foot.y, max(foot.z - 0.03, 0.0))) @ W
        for name, o in self.parts.items():
            if name in place:
                o.matrix_world = place[name]
                o.hide_render = False
            else:
                o.hide_render = True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--samples", type=int, default=12)
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    os.makedirs(OUT, exist_ok=True)
    meta_path = os.path.join(OUT, "animals.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    kinds = [k for k in SPECIES if not args.only or k in args.only.split(",")]
    for kind in kinds:
        cell, anchor, anims = SPECIES[kind]
        R.reset_scene()
        R.illustrated_light()
        R.outlines(True, thickness=1.2, alpha=0.6)
        bpy.context.scene.cycles.use_adaptive_sampling = False
        K2.reset_cache()
        P2.setup_camera(cell, anchor)
        beast = Beast(kind)
        rows, layout = [], {}
        for anim, nf in anims.items():
            for d, yaw in DIRS.items():
                frames = []
                for f in range(nf):
                    beast.pose(anim, f / nf, yaw)
                    bpy.context.view_layer.update()
                    frames.append(P2.to_cell(P2.render_frame(kind, args.samples), cell))
                layout[f"{anim}_{d}"] = len(rows)
                rows.append(frames)
        maxf = max(anims.values())
        atlas = np.zeros((len(rows) * cell[1], maxf * cell[0], 4), np.uint8)
        for ri, frames in enumerate(rows):
            for fi, c in enumerate(frames):
                atlas[ri * cell[1]:ri * cell[1] + c.shape[0], fi * cell[0]:fi * cell[0] + c.shape[1]] = c
        Image.fromarray(atlas, "RGBA").save(os.path.join(OUT, f"{kind}.png"), optimize=True)
        meta[kind] = {"cell": list(cell), "anchor": list(anchor), "rows": layout, "frames": anims}
        json.dump(meta, open(meta_path, "w"), indent=1)
        print("rendered", kind, atlas.shape, flush=True)


if __name__ == "__main__":
    main()
