"""Small inhabitant figures for the settlements: few frames, readable silhouettes, colour and tool by job.

Run with Blender's bundled Python (numpy):
  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\5.2\\python\\bin\\python.exe" tools/art/draw_people.py
Output: assets/people/people_atlas.png + .json

Sprites: "<job>_<anim>_<frame>" with anim idle(1) / walk(2) / work(2) / carry(2), facing right (the map flips them),
plus loads "load_<resource>" drawn on the shoulder. Pivot = feet.
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "worldgen"))
sys.path.insert(0, HERE)
from kdio import write_png  # noqa: E402
from draw_vegetation import Canvas, hexc  # noqa: E402
from draw_buildings import poly_mask, ink_outline  # noqa: E402

PPM = 22.0
OUT_DIR = os.path.join(ROOT, "assets", "people")
W, H = 2.4, 2.6
FEET = (1.1, 2.35)

JOBS = {
    "idle": {"tunic": "#9C8A6A", "tool": None, "hat": None},
    "king": {"tunic": "#8E2A2A", "tool": None, "hat": "crown"},
    "builder": {"tunic": "#A0643A", "tool": "hammer", "hat": None},
    "woodcutter": {"tunic": "#4F6B3A", "tool": "axe", "hat": None},
    "quarrier": {"tunic": "#6F7478", "tool": "pick", "hat": None},
    "farmer": {"tunic": "#B8984A", "tool": "hoe", "hat": "straw"},
    "baker": {"tunic": "#D6CEBA", "tool": None, "hat": "cap"},
    # soldiers: the weapon is always in hand, so idle and walk already read as "army"
    "lancieri": {"tunic": "#6E7B52", "tool": None, "hat": "helm", "weapon": "spear"},
    "alabardieri": {"tunic": "#5E6472", "tool": None, "hat": "helm", "weapon": "halberd"},
    "balestrieri": {"tunic": "#7A5A3A", "tool": None, "hat": "cap", "weapon": "crossbow"},
    "cavalieri": {"tunic": "#8E2A2A", "tool": None, "hat": "helm", "weapon": "lance", "mount": True},
}
LOADS = {"wood": "#8A6240", "stone": "#9C9A92", "grain": "#D8C28A", "bread": "#C68A48"}


def line(c, ax, ay, bx, by, w, color):
    nx, ny = -(by - ay), (bx - ax)
    ln = math.hypot(nx, ny) or 1.0
    nx, ny = nx / ln * w * 0.5, ny / ln * w * 0.5
    c.over(poly_mask(c, [(ax - nx, ay - ny), (bx - nx, by - ny), (bx + nx, by + ny), (ax + nx, ay + ny)]), hexc(color) if isinstance(color, str) else color)


def disc(c, cx, cy, r, color, sy=1.0):
    d = np.sqrt((c.x - cx) ** 2 + ((c.y - cy) / sy) ** 2)
    c.over(np.clip((r - d) / c.aa, 0, 1), hexc(color) if isinstance(color, str) else color)


def horse(c, fx, fy):
    """A plain warhorse under the rider: body, neck, head and four legs, same flat painterly language."""
    body_y = fy - 0.75
    disc(c, fx + 0.05, body_y, 0.62, "#6B4B32", 0.52)
    for (hx, back) in ((fx - 0.45, True), (fx - 0.3, False), (fx + 0.45, True), (fx + 0.6, False)):
        line(c, hx, body_y + 0.1, hx + (0.06 if back else -0.06), fy, 0.13, "#5A3E28" if back else "#6B4B32")
    line(c, fx + 0.45, body_y - 0.1, fx + 0.88, body_y - 0.66, 0.26, "#7A5738")     # neck
    disc(c, fx + 0.95, body_y - 0.74, 0.2, "#7A5738", 0.75)                         # head
    line(c, fx + 0.52, body_y - 0.28, fx + 0.82, body_y - 0.74, 0.1, "#3E2A1A")     # mane
    line(c, fx - 0.2, body_y - 0.3, fx + 0.25, body_y - 0.34, 0.09, "#4A3320")      # saddle
    line(c, fx - 0.55, body_y - 0.1, fx - 0.85, body_y + 0.35, 0.12, "#3E2A1A")     # tail
    return body_y - 0.15   # where the rider sits


MOUNT_LIFT = 1.0   # a rider needs more canvas above the ground than a man on foot


def feet_of(job):
    """Where the ground is in the sprite of this job (the pivot)."""
    return (FEET[0], FEET[1] + (MOUNT_LIFT if JOBS[job].get("mount") else 0.0))


def figure(job, anim, frame):
    spec = JOBS[job]
    mounted = bool(spec.get("mount"))
    c = Canvas(W, H + (MOUNT_LIFT if mounted else 0.0), PPM)
    fx, fy = feet_of(job)
    if mounted:
        fy = horse(c, fx, fy)
    # shadow
    d = np.sqrt(((c.x - fx - 0.15) / 0.55) ** 2 + ((c.y - fy) / 0.16) ** 2)
    c.over(np.clip(1.0 - d, 0, 1) * 0.35, np.array([0.1, 0.08, 0.05]))
    step = 0.0
    if anim in ("walk", "carry"):
        step = 0.22 if frame == 0 else -0.22
    hip_y = fy - 0.85
    if spec.get("mount"):
        # in the saddle: one thigh forward, a boot in the stirrup
        line(c, fx - 0.02, hip_y + 0.05, fx + 0.3, hip_y + 0.28, 0.17, "#4A3A2A")
        line(c, fx + 0.3, hip_y + 0.28, fx + 0.26, hip_y + 0.62, 0.13, "#3E3024")
    else:
        line(c, fx - 0.08, hip_y, fx - 0.1 + step, fy, 0.16, "#4A3A2A")
        line(c, fx + 0.08, hip_y, fx + 0.1 - step, fy, 0.16, "#3E3024")
    # body (tunic)
    tunic = hexc(spec["tunic"])
    body = poly_mask(c, [(fx - 0.26, hip_y + 0.12), (fx + 0.26, hip_y + 0.12), (fx + 0.19, hip_y - 0.62), (fx - 0.19, hip_y - 0.62)])
    lit = np.clip(0.75 - 0.9 * (c.x - fx), 0.55, 1.1)
    c.over(body, tunic[None, None, :] * lit[..., None])
    if job == "king":
        cape = poly_mask(c, [(fx - 0.34, hip_y + 0.2), (fx - 0.1, hip_y + 0.18), (fx - 0.12, hip_y - 0.62), (fx - 0.24, hip_y - 0.6)])
        c.over(cape, hexc("#5A1C3C"))
    line(c, fx - 0.22, hip_y - 0.05, fx + 0.22, hip_y - 0.05, 0.07, "#3A2A1A")   # belt
    shoulder = (fx + 0.05, hip_y - 0.55)
    head = (fx + 0.02, hip_y - 0.82)
    # arms and tool
    tool = spec["tool"]
    if anim == "work" and tool:
        up = frame == 0
        hand = (fx + 0.45, hip_y - 0.95) if up else (fx + 0.55, hip_y - 0.25)
        line(c, shoulder[0], shoulder[1], hand[0], hand[1], 0.12, spec["tunic"])
        tip = (hand[0] - 0.25, hand[1] - 0.45) if up else (hand[0] + 0.45, hand[1] + 0.25)
        line(c, hand[0], hand[1], tip[0], tip[1], 0.07, "#6B4A2A")
        head_col = "#8A8C90"
        if tool == "axe":
            disc(c, tip[0], tip[1], 0.13, head_col, 0.8)
        elif tool == "pick":
            line(c, tip[0] - 0.18, tip[1] + 0.08, tip[0] + 0.18, tip[1] - 0.08, 0.07, head_col)
        elif tool == "hammer":
            line(c, tip[0] - 0.1, tip[1] - 0.06, tip[0] + 0.1, tip[1] + 0.06, 0.14, head_col)
        elif tool == "hoe":
            line(c, tip[0], tip[1], tip[0] + 0.12, tip[1] + 0.18, 0.08, head_col)
    elif anim == "carry":
        line(c, shoulder[0], shoulder[1], fx + 0.22, hip_y - 0.9, 0.12, spec["tunic"])
    else:
        swing = step * 0.6
        line(c, shoulder[0], shoulder[1], fx + 0.12 + swing, hip_y - 0.05, 0.12, spec["tunic"])
    # head
    disc(c, head[0], head[1], 0.17, "#E2B48C")
    disc(c, head[0] - 0.05, head[1] - 0.07, 0.14, "#5A3E24")
    disc(c, head[0] + 0.04, head[1] + 0.02, 0.12, "#E2B48C")
    weapon = spec.get("weapon")
    if weapon:
        hand = (fx + 0.3, hip_y - 0.2)
        line(c, shoulder[0], shoulder[1], hand[0], hand[1], 0.12, spec["tunic"])
        if weapon == "lance":
            top = (hand[0] + 1.05, hand[1] - 0.95)
            bottom = (hand[0] - 0.45, hand[1] + 0.2)
            line(c, bottom[0], bottom[1], top[0], top[1], 0.07, "#6B4A2A")
            c.over(poly_mask(c, [(top[0] + 0.24, top[1] - 0.2), (top[0] - 0.02, top[1] + 0.06), (top[0] + 0.06, top[1] - 0.16)]), hexc("#B9BCC2"))
        elif weapon in ("spear", "halberd"):
            tilt = 0.25
            top = (hand[0] + tilt * 0.45, hand[1] - 1.5)
            bottom = (hand[0] - tilt * 0.2, hand[1] + 0.65)
            line(c, bottom[0], bottom[1], top[0], top[1], 0.07, "#6B4A2A")
            c.over(poly_mask(c, [(top[0], top[1] - 0.3), (top[0] + 0.09, top[1] - 0.02), (top[0] - 0.09, top[1] - 0.02)]), hexc("#B9BCC2"))
            if weapon == "halberd":
                line(c, top[0] - 0.04, top[1] + 0.06, top[0] - 0.3, top[1] + 0.22, 0.08, "#B9BCC2")
        else:   # crossbow held across the chest
            line(c, hand[0] - 0.35, hand[1] - 0.15, hand[0] + 0.35, hand[1] + 0.05, 0.09, "#6B4A2A")
            line(c, hand[0] + 0.1, hand[1] - 0.3, hand[0] + 0.1, hand[1] + 0.22, 0.06, "#8A8C90")
        shield = poly_mask(c, [(fx - 0.42, hip_y - 0.5), (fx - 0.12, hip_y - 0.5), (fx - 0.12, hip_y + 0.05),
                               (fx - 0.27, hip_y + 0.22), (fx - 0.42, hip_y + 0.05)])
        c.over(shield * (0.0 if weapon == "crossbow" else 1.0), hexc("#8A7148"))
    hat = spec["hat"]
    if hat == "crown":
        c.over(poly_mask(c, [(head[0] - 0.16, head[1] - 0.1), (head[0] + 0.16, head[1] - 0.1), (head[0] + 0.17, head[1] - 0.32),
                             (head[0] + 0.08, head[1] - 0.22), (head[0], head[1] - 0.34), (head[0] - 0.08, head[1] - 0.22),
                             (head[0] - 0.17, head[1] - 0.32)]), hexc("#E3B447"))
    elif hat == "straw":
        disc(c, head[0], head[1] - 0.12, 0.3, "#D9BE6C", 0.35)
        disc(c, head[0], head[1] - 0.18, 0.13, "#CDAE58")
    elif hat == "cap":
        disc(c, head[0], head[1] - 0.12, 0.17, "#EFEBE0", 0.7)
    elif hat == "helm":
        disc(c, head[0], head[1] - 0.06, 0.2, "#A9AEB4", 0.85)
        line(c, head[0] - 0.19, head[1] - 0.02, head[0] + 0.19, head[1] - 0.02, 0.06, "#7E848B")
    return ink_outline(c.result(), 0.45)


def banner(frame):
    """The pennant that stands for an army on the map: drawn white, tinted with the realm colour in game."""
    c = Canvas(1.6, 2.6, PPM)
    px, ground = 0.55, 2.45
    d = np.sqrt(((c.x - px - 0.1) / 0.4) ** 2 + ((c.y - ground) / 0.12) ** 2)
    c.over(np.clip(1.0 - d, 0, 1) * 0.3, np.array([0.1, 0.08, 0.05]))
    line(c, px, ground, px, 0.15, 0.09, "#6B4A2A")
    wave = 0.12 if frame == 0 else -0.12
    c.over(poly_mask(c, [(px + 0.04, 0.2), (px + 0.95, 0.42 + wave), (px + 0.95, 1.02 + wave), (px + 0.04, 1.1)]),
           np.array([1.0, 1.0, 1.0]))
    c.over(poly_mask(c, [(px + 0.04, 1.02), (px + 0.95, 0.96 + wave), (px + 0.95, 1.06 + wave), (px + 0.04, 1.12)]),
           hexc("#C9A24A"))
    return ink_outline(c.result(), 0.5), (px * PPM, ground * PPM)


def load(res):
    c = Canvas(1.4, 1.0, PPM)
    col = hexc(LOADS[res])
    if res == "wood":
        for i in range(3):
            line(c, 0.15, 0.55 - i * 0.14, 1.2, 0.4 - i * 0.14, 0.14, col * (0.85 + 0.1 * i))
    elif res == "stone":
        disc(c, 0.6, 0.55, 0.3, col, 0.8)
    elif res == "grain":
        disc(c, 0.65, 0.5, 0.32, col, 0.9)
        line(c, 0.55, 0.2, 0.75, 0.2, 0.08, "#8A7040")
    else:
        disc(c, 0.65, 0.58, 0.3, "#8A6A40", 0.55)
        disc(c, 0.6, 0.45, 0.12, col)
        disc(c, 0.78, 0.47, 0.11, col)
    return ink_outline(c.result(), 0.45), (0.65 * PPM, 0.9 * PPM)


def trim(img, pivot, margin=1):
    ys, xs = np.nonzero(img[..., 3] > 0.01)
    x0, x1 = max(xs.min() - margin, 0), min(xs.max() + margin + 1, img.shape[1])
    y0, y1 = max(ys.min() - margin, 0), min(ys.max() + margin + 1, img.shape[0])
    return img[y0:y1, x0:x1], (pivot[0] - x0, pivot[1] - y0)


def main():
    sprites = []
    for job in JOBS:
        for anim, frames in (("idle", 1), ("walk", 2), ("work", 2), ("carry", 2)):
            for f in range(frames):
                feet = feet_of(job)
                img, piv = trim(figure(job, anim, f), (feet[0] * PPM, feet[1] * PPM))
                sprites.append({"id": "%s_%s_%d" % (job, anim, f), "img": img, "pivot": piv})
    for res in LOADS:
        img, piv = load(res)
        img, piv = trim(img, piv)
        sprites.append({"id": "load_" + res, "img": img, "pivot": piv})
    for f in range(2):
        img, piv = banner(f)
        img, piv = trim(img, piv)
        sprites.append({"id": "banner_%d" % f, "img": img, "pivot": piv})
    width = 512
    x = y = shelf = 0
    for s in sprites:
        h, w, _ = s["img"].shape
        if x + w + 2 > width:
            x, y, shelf = 0, y + shelf + 2, 0
        s["pos"] = (x, y)
        x += w + 2
        shelf = max(shelf, h)
    height = 1 << (y + shelf + 2 - 1).bit_length()
    atlas = np.zeros((height, width, 4))
    entries = {}
    for s in sprites:
        h, w, _ = s["img"].shape
        px, py = s["pos"]
        atlas[py:py + h, px:px + w] = s["img"]
        entries[s["id"]] = {"rect": [px, py, w, h], "pivot": [round(s["pivot"][0], 2), round(s["pivot"][1], 2)],
                            "size_m": [round(w / PPM, 3), round(h / PPM, 3)]}
    out = np.clip(atlas * 255.0 + 0.5, 0, 255).astype(np.uint8)
    os.makedirs(OUT_DIR, exist_ok=True)
    write_png(os.path.join(OUT_DIR, "people_atlas.png"), out)
    with open(os.path.join(OUT_DIR, "people_atlas.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"version": 1, "atlas": "people_atlas.png", "width": width, "height": height, "ppm": PPM,
                   "sprites": entries}, f, indent=1)
    prev = os.path.join(HERE, "out_preview")
    bg = hexc("#8FA257")
    comp = atlas[..., :3] * atlas[..., 3:4] + bg * (1.0 - atlas[..., 3:4])
    write_png(os.path.join(prev, "people_x3.png"), (np.kron(comp, np.ones((3, 3, 1))) * 255).astype(np.uint8))
    print("people atlas", width, height, len(entries))


if __name__ == "__main__":
    main()

