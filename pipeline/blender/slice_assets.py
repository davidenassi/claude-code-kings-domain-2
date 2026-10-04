"""Phase 1B asset library: houses (8 real variants), landmark buildings and props, rendered at any yaw.

Sprites are named  <type>@<yaw>  (yaw in degrees, facade towards the camera at 0, towards the east at 90).
The slice layout lists the (type, yaw) pairs it uses; this script renders exactly those (and skips the ones
already rendered, unless --force).

Run:  python blender/slice_assets.py --only house_cottage@045,church@-030 [--samples 40] [--force]
      python blender/slice_assets.py --from-layout        (everything game/data/valley/slice_sprites.json asks)
Output: game/assets/sprites/slice/<name>.png, <name>_sh.png, slice.json (anchor, size, footprint, chimneys,
        emitters)
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
import kit2 as K2  # noqa: E402

import slice_landmarks as LM  # noqa: E402
import slice_props as PR  # noqa: E402

OUT = os.path.join(R.K.GAME_DIR, "assets", "sprites", "slice")
CATALOG = {}


def entry(name, seed=1):
    def deco(fn):
        CATALOG[name] = (fn, seed)
        return fn
    return deco


FLOWERS = [(206, 64, 60), (236, 196, 72), (226, 128, 176), (240, 236, 220), (150, 110, 210)]
SHUTTERS = [(64, 96, 70), (52, 84, 120), (120, 52, 44), (96, 72, 48), (70, 108, 112)]


# ------------------------------------------------------------------------------------------------
# house generator v2
def house(rng, w=7.0, d=5.6, storeys=("plaster",), fh=3.1, plinth=0.6, roof="thatch", pitch=42, overhang=0.5,
          hip=False, ridge_x=True, jetty=0.0, frame="cross", plaster=(228, 216, 190), wood=(128, 94, 62),
          door_face="S", door_u=None, canopy=None, chimneys=(("E", 0.0),), shutters=None, flowers=0.5,
          lean_to=None, woodpile=None, barrels=(), porch=False, gable_mat=None, gable_over=0.4):
    objs = []
    st = K2.stone((168, 156, 136), (124, 118, 110), (90, 82, 70))
    if plinth > 0:
        objs.append(K2.box(w + 0.16, d + 0.16, plinth, (0, 0, 0), st, name="plinth", bevel=0.03))
    z = plinth
    door_u = (rng.uniform(-w * 0.25, w * 0.25) if door_face in "SN" else 0.0) if door_u is None else door_u
    for k, kind in enumerate(storeys):
        jw = jetty * (1 if k > 0 else 0)
        ww, dd = w + (0 if ridge_x else 2 * jw), d + (2 * jw if ridge_x else 0)
        if kind == "stone":
            mat = st
        elif kind == "planks":
            mat = K2.planks(wood, 0.24, True, 0.25)
        elif kind == "logs":
            mat = K2.planks(wood, 0.26, False, 0.2)
        else:
            mat = K2.plaster(plaster)
        objs.append(K2.box(ww, dd, fh, (0, 0, z), mat, name="storey"))
        if jw > 0:
            # jetty joists under the overhang
            n = int(ww / 0.6)
            for i in range(n):
                x = -ww / 2 + (i + 0.5) * ww / n
                for sy in (-1, 1):
                    objs.append(K2.box(0.14, jw + 0.2, 0.16, (x, sy * (d / 2 + jw / 2), z - 0.1), K2.timber()))
        openings = []
        if k == 0:
            openings.append((door_face, door_u, 0.8))
        if kind == "timber":
            objs += K2.timber_frame(ww, dd, z, fh, rng, pattern=frame if k % 2 == 0 else ("brace" if frame == "cross" else "cross"),
                                    openings=openings)
        # windows on every face (rhythm by length)
        for f in "SNEW":
            L = ww if f in "SN" else dd
            n = max(1, int(L / 2.3))
            for i in range(n):
                u = -L / 2 + L * (i + 0.5) / n
                if k == 0 and f == door_face and abs(u - door_u) < 1.1:
                    continue
                if n == 1 and f in "EW" and k == 0 and rng.random() < 0.4:
                    continue
                fl = FLOWERS if (rng.random() < flowers and f in "SW") else None
                objs += K2.window(f, u, z + fh * 0.36, ww, dd, ww=0.72, wh=0.95 if k == 0 else 0.85,
                                  shutters=shutters, flowers=fl,
                                  frame_mat=K2.stone() if kind == "stone" else None)
        if k == 0:
            dm = K2.planks((98, 64, 38) if kind != "stone" else (84, 58, 36), 0.15, True, 0.1)
            objs += K2.door(door_face, door_u, ww, dd, mat=dm, stone_frame=(kind == "stone"), canopy=canopy)
        z += fh
    # roof
    rw, rd = w + (0 if ridge_x else 2 * jetty * (len(storeys) > 1)), d + (2 * jetty * (len(storeys) > 1) if ridge_x else 0)
    if hip:
        robjs, zr = K2.hip_roof(rw if ridge_x else rd, rd if ridge_x else rw, z, pitch, roof, rng, overhang=overhang)
        if not ridge_x:
            for ob in robjs:
                loc = Vector(ob.location)
                ob.location = (-loc.y, loc.x, loc.z)
                ob.rotation_euler.z += math.pi / 2
    else:
        robjs, zr = K2.gable_roof(rw, rd, z, pitch, roof, rng, overhang=overhang, gable_over=gable_over, ridge_x=ridge_x)
        # gable infill
        gm = gable_mat or (K2.planks(wood, 0.22, True, 0.3) if storeys[-1] in ("planks", "logs") else
                           K2.plaster(plaster) if storeys[-1] != "stone" else K2.stone((168, 156, 136), (124, 118, 110)))
        span = rd if ridge_x else rw
        rise = math.tan(math.radians(pitch)) * span / 2
        for sgn in (-1, 1):
            if ridge_x:
                objs.append(K2.gable_wall(span, z, rise, gm, thick=0.3, x=sgn * rw / 2 - sgn * 0.12, axis="y"))
            else:
                objs.append(K2.gable_wall(span, z, rise, gm, thick=0.3, y=sgn * rd / 2 - sgn * 0.12, axis="x"))
        if storeys[-1] == "timber":
            tm = K2.timber()
            for sgn in (-1, 1):
                if ridge_x:
                    xx = sgn * (rw / 2 + 0.04)
                    objs.append(K2.beam((xx, 0, z), (xx, 0, z + rise - 0.2), 0.16, tm))
                    for sy in (-1, 1):
                        objs.append(K2.beam((xx, sy * span / 4, z), (xx, sy * span / 4, z + rise * 0.48), 0.14, tm))
                else:
                    yy = sgn * (rd / 2 + 0.04)
                    objs.append(K2.beam((0, yy, z), (0, yy, z + rise - 0.2), 0.16, tm))
                    for sx in (-1, 1):
                        objs.append(K2.beam((sx * span / 4, yy, z), (sx * span / 4, yy, z + rise * 0.48), 0.14, tm))
    objs += robjs
    # chimneys
    for face, off in chimneys:
        if face == "E":
            cx, cy = rw / 2 - 0.7, off
        elif face == "W":
            cx, cy = -rw / 2 + 0.7, off
        elif face == "N":
            cx, cy = off, rd / 2 - 0.9
        else:
            cx, cy = off, 0.0
        objs += K2.chimney(cx, cy, z - 0.5, zr + rng.uniform(0.5, 0.9))
    # lean-to shed on one side
    if lean_to:
        side, kind = lean_to
        lw, ld = (d * 0.8, 2.2)
        lz = z - 0.35
        if side in "EW":
            sx = 1 if side == "E" else -1
            shed = K2.box(ld, lw, lz * 0.85, (sx * (w / 2 + ld / 2), 0, 0), K2.planks(wood, 0.24, True, 0.4))
            objs.append(shed)
            lt = K2.lean_to(lw + 0.4, ld + 0.4, lz, lz * 0.62, kind, rng, 0.0, side=-1)
            lt.rotation_euler = (0, 0, sx * math.pi / 2)
            lt.location = (sx * w / 2, 0, 0)
            objs.append(lt)
    if porch:
        pz = plinth + fh - 0.1
        lt = K2.lean_to(w * 0.75, 1.9, pz + 0.3, pz - 0.35, "shingle", rng, -d / 2, side=-1)
        objs.append(lt)
        for sx in (-1, 1):
            objs.append(K2.beam((sx * (w * 0.75 / 2 - 0.15), -d / 2 - 1.75, 0), (sx * (w * 0.75 / 2 - 0.15), -d / 2 - 1.75, pz - 0.3),
                                0.16, K2.timber()))
        objs.append(K2.box(w * 0.75, 1.8, 0.18, (0, -d / 2 - 0.9, 0), K2.planks((120, 90, 60), 0.2, False, 0.3)))
    if woodpile:
        side, length = woodpile
        if side == "W":
            objs += K2.woodpile(length, 1.2, 0.5, (-w / 2 - 0.45, 0, 0), math.pi / 2, rng)
        elif side == "E":
            objs += K2.woodpile(length, 1.2, 0.5, (w / 2 + 0.45, 0, 0), math.pi / 2, rng)
        else:
            objs += K2.woodpile(length, 1.1, 0.5, (0, d / 2 + 0.45, 0), 0.0, rng)
    for bx, by in barrels:
        objs += K2.barrel(bx, by, 0.0, rng=rng)
    return objs


HOUSES = {
    # 1: thatched cottage, half-timbered, flower boxes, stone chimney at the gable, woodpile
    "house_cottage": dict(w=7.2, d=5.4, storeys=("timber",), roof="thatch", pitch=46, overhang=0.5,
                          frame="cross", plaster=(232, 222, 198), chimneys=(("E", 0.0),), shutters=None,
                          flowers=0.8, woodpile=("W", 3.6), barrels=((2.6, -3.1),)),
    # 2: long farmhouse, thatch hip roof, stone ground floor, shed on the side, door canopy
    "house_farm": dict(w=9.4, d=5.8, storeys=("stone",), roof="thatch_old", pitch=46, hip=True, overhang=0.75,
                       chimneys=(("C", 1.6),), lean_to=("E", "shingle"), canopy="shingle", flowers=0.3,
                       barrels=((-3.4, -3.3), (-2.8, -3.5))),
    # 3: town house: stone ground floor, jettied timber upper floor, red tiles, two chimneys
    "house_town": dict(w=7.8, d=6.2, storeys=("stone", "timber"), roof="tile", pitch=42, jetty=0.45,
                       frame="brace", plaster=(226, 210, 176), chimneys=(("W", 0.0), ("E", 0.0)),
                       shutters=(64, 96, 70), flowers=0.6),
    # 4: stone house with slate roof and blue shutters
    "house_stone": dict(w=7.0, d=6.0, storeys=("stone",), fh=3.1, roof="slate", pitch=44, overhang=0.45,
                        chimneys=(("E", 0.0),), shutters=(52, 84, 120), flowers=0.4, woodpile=("E", 2.8)),
    # 5: woodsman's cabin: log walls, shingles, porch, woodpile
    "house_cabin": dict(w=6.6, d=5.2, storeys=("logs",), plinth=0.4, roof="shingle", pitch=40, overhang=0.6,
                        wood=(122, 86, 54), chimneys=(("W", 0.0),), porch=True, woodpile=("E", 3.0), flowers=0.0),
    # 6: merchant house: two plastered storeys (ochre), tile hip roof, door canopy, shutters
    "house_merchant": dict(w=8.6, d=7.0, storeys=("plaster", "timber"), roof="tile_dark", pitch=42, hip=True,
                           plaster=(214, 194, 156), frame="chevron", chimneys=(("N", -1.5),), canopy="tile",
                           shutters=(120, 52, 44), flowers=0.7, barrels=((3.6, -4.0),)),
    # 7: tall narrow town house, gable to the street, three storeys
    "house_tall": dict(w=5.4, d=7.6, storeys=("stone", "timber", "timber"), fh=2.6, roof="tile", pitch=54,
                       ridge_x=False, jetty=0.35, plaster=(236, 226, 206), frame="cross",
                       chimneys=(("N", 1.2),), shutters=(70, 108, 112), flowers=0.6, gable_over=0.3),
    # 8: shingled timber house with stone end wall, shed and barrels
    "house_timber": dict(w=8.0, d=5.8, storeys=("timber",), fh=3.0, roof="shingle", pitch=44, overhang=0.6,
                         plaster=(214, 200, 168), frame="brace", chimneys=(("W", 0.0),), shutters=(96, 72, 48),
                         lean_to=("W", "shingle"), flowers=0.4, barrels=((3.2, -3.2),)),
}
for _i, (_n, _spec) in enumerate(HOUSES.items()):
    def _mk(rng, spec=_spec):
        return house(rng, **spec), (spec["w"], spec["d"])
    CATALOG[_n] = (_mk, 500 + _i)


CATALOG.update(LM.ENTRIES)
CATALOG.update(PR.ENTRIES)


def make_catchers(specs, root):
    """Shadow-catcher planes (z, x0, x1, y0, y1) in model coordinates, rotated with the model."""
    out = []
    for z, x0, x1, y0, y1 in specs:
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=((x0 + x1) / 2, (y0 + y1) / 2, z))
        g = bpy.context.object
        g.scale = (x1 - x0, y1 - y0, 1)
        g.name = "catcher"
        g.is_shadow_catcher = True
        g.data.materials.append(bpy.data.materials["ground_mat"])
        if root is not None:
            g.parent = root
        R.to_no_ink(g)
        out.append(g)
    bpy.context.view_layer.update()
    return out


def make_holdouts(specs, root):
    """Under-water / under-ground cut: a camera-only holdout plane just below every catcher, so the parts of
    piles, piers, abutments and wheel blades under the river surface or the bank are transparent in the
    sprite (the game's water and terrain show there instead of geometry drawn on top of them)."""
    out = []
    for z, x0, x1, y0, y1 in specs:
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=((x0 + x1) / 2, (y0 + y1) / 2, z - 0.012))
        h = bpy.context.object
        h.scale = (x1 - x0, y1 - y0, 1)
        h.name = "water_cut"
        h.is_holdout = True
        for k in ("visible_shadow", "visible_diffuse", "visible_glossy", "visible_transmission",
                  "visible_volume_scatter"):
            setattr(h, k, False)
        if root is not None:
            h.parent = root
        R.to_no_ink(h)
        out.append(h)
    bpy.context.view_layer.update()
    return out


# ------------------------------------------------------------------------------------------------
def parse_name(name):
    if "@" in name:
        base, y = name.split("@")
        return base, int(y)
    return name, 0


def sprite_name(base, yaw):
    return f"{base}@{yaw:03d}" if yaw >= 0 else f"{base}@m{-yaw:03d}"


def parse_sprite(name):
    base, y = name.split("@")
    return base, (-int(y[1:]) if y.startswith("m") else int(y))


def render_one(name, samples, meta):
    base, yaw = parse_sprite(name) if "@" in name else (name, 0)
    fn, seed = CATALOG[base]
    R.clear_objects()
    K2.reset_cache()
    for m in list(bpy.data.materials):
        if m.name != "ground_mat":
            bpy.data.materials.remove(m)
    rng = random.Random(seed)
    out = fn(rng)
    objs, fp = out[0], out[1]
    extra = out[2] if len(out) > 2 else {}
    if not yaw and extra.get("catchers"):
        root = bpy.data.objects.new("yaw_root", None)
        bpy.context.scene.collection.objects.link(root)
        for o in objs:
            if o.parent is None:
                o.parent = root
    else:
        root = R.apply_yaw(objs, yaw)
    catchers = None
    holdouts = []
    ground = bpy.data.objects["ground"]
    ground.hide_render = False
    if extra.get("catchers"):
        catchers = make_catchers(extra["catchers"], root)
        holdouts = make_holdouts(extra["catchers"], root)
        ground.hide_render = True
    bpy.context.view_layer.update()
    chims = []
    for o in objs:
        if o.name.startswith("chimney_cap") or o.name.startswith("emit_smoke"):
            p_ = o.matrix_world.translation + Vector((0, 0, 0.3))
            sx_, sy_ = R.screen_xy(p_)
            chims.append([round(sx_ * R.K.SPRITE_PX_PER_M, 1), round(-sy_ * R.K.SPRITE_PX_PER_M, 1)])
    res = R.render_object([o for o in objs if o.type == "MESH" and not o.hide_render], name.replace("@", "_"),
                          samples=samples, shadow_samples=16, catchers=catchers)
    if catchers:
        for c in catchers + holdouts:
            bpy.data.objects.remove(c, do_unlink=True)
        ground.hide_render = False
    # world-space offsets (metres, x east / y south) of attached points, rotated with the model
    yr = math.radians(yaw)

    def world_off(p):
        x, y = p[0], p[1]
        bx, by = x * math.cos(yr) - y * math.sin(yr), x * math.sin(yr) + y * math.cos(yr)
        return [round(bx, 3), round(-by, 3), round(p[2], 3)]
    extra = dict(extra)
    extra.pop("catchers", None)
    if "attach" in extra:
        extra["attach"] = {k: world_off(v) for k, v in extra["attach"].items()}
    if "sort_point" in extra:
        extra["sort_point"] = world_off(extra["sort_point"])
    body, sh, anchor = R.finish(res, grade=R.grade_illustrated, crisp=0.5)
    body, sh, anchor = R.trim(body, sh, anchor)
    Image.fromarray(body, "RGBA").save(os.path.join(OUT, f"{name}.png"), optimize=True)
    Image.fromarray(sh, "L").save(os.path.join(OUT, f"{name}_sh.png"), optimize=True)
    meta[name] = {"anchor": [round(anchor[0], 2), round(anchor[1], 2)], "size": [body.shape[1], body.shape[0]],
                  "footprint": [round(fp[0], 2), round(fp[1], 2)], "yaw": yaw, "chimneys": chims, **extra}
    print("rendered", name, body.shape, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--samples", type=int, default=40)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--from-layout", action="store_true")
    ap.add_argument("--no-ink", action="store_true")
    args = ap.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
    os.makedirs(OUT, exist_ok=True)
    meta_path = os.path.join(OUT, "slice.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    names = [x for x in args.only.split(",") if x]
    if args.from_layout:
        names += json.load(open(os.path.join(R.K.GAME_DIR, "data", "valley", "slice_sprites.json")))
    R.reset_scene()
    R.illustrated_light()
    R.outlines(not args.no_ink)
    for name in names:
        base = name.split("@")[0]
        if base not in CATALOG:
            print("unknown", name, flush=True)
            continue
        if not args.force and name in meta and os.path.exists(os.path.join(OUT, f"{name}.png")):
            continue
        render_one(name, args.samples, meta)
        json.dump(meta, open(meta_path, "w"), indent=1)


if __name__ == "__main__":
    main()
