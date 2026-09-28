"""Small painted props for the settlements and the river banks (world art pass): woodpiles, logs, stumps, crates,
barrels, sacks, hay, a cart, a coal heap, a fence panel, market stalls, reeds, bank stones.

Same light 3/4 style as the buildings and the trees: light from the upper left, soft shadow to the lower right.
They are only drawn (no collision, no gameplay), close to the ground.

Run with Blender's bundled Python (numpy):
  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\5.2\\python\\bin\\python.exe" tools/art/draw_props.py
Output: assets/buildings/props_atlas.png + .json (same format as the building atlas: rect, pivot, size_m)
"""
import json
import math
import os
import random
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "worldgen"))
sys.path.insert(0, HERE)
from kdio import write_png  # noqa: E402
from draw_vegetation import Canvas, hexc, ground_shadow  # noqa: E402
from draw_buildings import poly_mask, ink_outline, trim  # noqa: E402

PPM = 16.0         # props are small: twice the resolution of the buildings
ZK = 0.72
OUT_DIR = os.path.join(ROOT, "assets", "buildings")


class P:
    """A canvas around a ground point (gx, gy) in metres."""

    def __init__(self, w, h, gy_from_top):
        self.c = Canvas(w, h, PPM)
        self.gx = w * 0.5
        self.gy = gy_from_top

    def pivot(self):
        return (self.gx * PPM, self.gy * PPM)


def ellipse(c, cx, cy, rx, ry):
    d = np.sqrt(((c.x - cx) / rx) ** 2 + ((c.y - cy) / ry) ** 2)
    return np.clip((1.0 - d) * min(rx, ry) / c.aa, 0.0, 1.0), d


def lit_color(c, base, cx, cy, r, k=0.5):
    lit = np.clip(0.6 - k * (c.x - cx) / r - k * (c.y - cy) / r, 0.25, 1.1)
    return hexc(base)[None, None, :] * lit[..., None]


def log_end(c, cx, cy, r, bark="#6B4A2C", wood="#C09060"):
    cover, d = ellipse(c, cx, cy, r, r * 0.92)
    ring = 0.86 + 0.14 * np.sin(d * 18.0)
    col = np.where((d > 0.78)[..., None], hexc(bark)[None, None, :], hexc(wood)[None, None, :] * ring[..., None])
    c.over(cover, col)


def woodpile(variant):
    rng = random.Random(10 + variant)
    p = P(3.6, 3.0, 2.4)
    c = p.c
    ground_shadow(c, p.gx, p.gy, 1.5, 0.28)
    rows = 3 if variant == 0 else 4
    r = 0.24
    for j in range(rows):
        n = 6 - j if variant == 0 else 7 - j
        for i in range(n):
            cx = p.gx - (n - 1) * r + i * 2 * r + rng.uniform(-0.03, 0.03)
            cy = p.gy - r - j * r * 1.75
            log_end(c, cx, cy, r * rng.uniform(0.9, 1.05))
    return p


def logs(variant):
    """Trunks lying on the ground, seen along their length."""
    rng = random.Random(20 + variant)
    p = P(5.0, 2.2, 1.7)
    c = p.c
    ground_shadow(c, p.gx, p.gy, 2.0, 0.25)
    for k in range(2 if variant == 0 else 3):
        y = p.gy - 0.25 - k * 0.32
        x0 = p.gx - 2.0 + rng.uniform(-0.2, 0.3) + k * 0.2
        x1 = p.gx + 1.8 + rng.uniform(-0.3, 0.2) - k * 0.2
        body = poly_mask(c, [(x0, y + 0.2), (x1, y + 0.2), (x1, y - 0.2), (x0, y - 0.2)])
        shade = np.clip(0.95 - 1.6 * (c.y - (y - 0.2)), 0.55, 1.05)
        c.over(body, hexc("#6E4E30")[None, None, :] * shade[..., None])
        log_end(c, x1, y, 0.2)
    return p


def stump(variant):
    p = P(1.6, 1.5, 1.1)
    c = p.c
    ground_shadow(c, p.gx, p.gy, 0.6, 0.25)
    body = poly_mask(c, [(p.gx - 0.35, p.gy), (p.gx + 0.35, p.gy), (p.gx + 0.32, p.gy - 0.35), (p.gx - 0.32, p.gy - 0.35)])
    c.over(body, lit_color(c, "#6A4A2E", p.gx, p.gy - 0.2, 0.4))
    log_end(c, p.gx, p.gy - 0.35, 0.33, "#5A3E26", "#B98C5C")
    if variant == 1:  # an axe in the stump
        c.over(poly_mask(c, [(p.gx + 0.05, p.gy - 0.4), (p.gx + 0.55, p.gy - 0.95), (p.gx + 0.6, p.gy - 0.9), (p.gx + 0.1, p.gy - 0.35)]), hexc("#7A5A36"))
        c.over(poly_mask(c, [(p.gx + 0.45, p.gy - 0.9), (p.gx + 0.7, p.gy - 1.0), (p.gx + 0.72, p.gy - 0.8), (p.gx + 0.55, p.gy - 0.78)]), hexc("#9A9A9A"))
    return p


def crate(c, cx, gy, s, tone=1.0):
    top = gy - s * ZK
    front = poly_mask(c, [(cx - s / 2, gy), (cx + s / 2, gy), (cx + s / 2, top), (cx - s / 2, top)])
    c.over(front, hexc("#9A7448")[None, None, :] * (0.85 * tone))
    lid = poly_mask(c, [(cx - s / 2, top), (cx + s / 2, top), (cx + s / 2 - 0.15, top - s * 0.35), (cx - s / 2 + 0.15, top - s * 0.35)])
    c.over(lid, hexc("#B58D5C")[None, None, :] * tone)
    for x in (cx - s / 2 + 0.06, cx + s / 2 - 0.06):
        c.over(poly_mask(c, [(x - 0.04, gy), (x + 0.04, gy), (x + 0.04, top), (x - 0.04, top)]), hexc("#5E4428"))
    c.over(poly_mask(c, [(cx - s / 2, gy - s * ZK * 0.5 - 0.03), (cx + s / 2, gy - s * ZK * 0.5 - 0.03),
                         (cx + s / 2, gy - s * ZK * 0.5 + 0.03), (cx - s / 2, gy - s * ZK * 0.5 + 0.03)]), hexc("#5E4428"))


def crates(variant):
    p = P(3.0, 2.6, 2.0)
    c = p.c
    ground_shadow(c, p.gx, p.gy, 1.2, 0.28)
    crate(c, p.gx - 0.45, p.gy, 0.8)
    crate(c, p.gx + 0.45, p.gy - 0.05, 0.75, 0.92)
    if variant == 1:
        crate(c, p.gx, p.gy - 0.62, 0.7, 1.05)
    return p


def barrel(c, cx, gy, r=0.32, h=0.8):
    top = gy - h * ZK
    body = poly_mask(c, [(cx - r, gy), (cx + r, gy), (cx + r * 1.05, gy - h * ZK * 0.5), (cx + r, top), (cx - r, top), (cx - r * 1.05, gy - h * ZK * 0.5)])
    shade = np.clip(1.1 - 0.9 * (c.x - (cx - r)) / (2 * r), 0.55, 1.1)
    c.over(body, hexc("#7C5634")[None, None, :] * shade[..., None])
    for yy in (gy - 0.1, top + 0.12):
        c.over(poly_mask(c, [(cx - r, yy - 0.03), (cx + r, yy - 0.03), (cx + r, yy + 0.03), (cx - r, yy + 0.03)]), hexc("#3A2E24"))
    cover, _ = ellipse(c, cx, top, r, r * 0.45)
    c.over(cover, hexc("#9A7048"))


def barrels(variant):
    p = P(2.2, 2.0, 1.6)
    c = p.c
    ground_shadow(c, p.gx, p.gy, 0.9, 0.28)
    barrel(c, p.gx - 0.3, p.gy)
    if variant == 1:
        barrel(c, p.gx + 0.38, p.gy + 0.05, 0.3, 0.75)
    return p


def sacks(variant):
    rng = random.Random(40 + variant)
    p = P(2.6, 1.8, 1.4)
    c = p.c
    ground_shadow(c, p.gx, p.gy, 1.0, 0.25)
    for k in range(3 if variant == 0 else 4):
        cx = p.gx - 0.6 + k * 0.42 + rng.uniform(-0.05, 0.05)
        cy = p.gy - 0.3 - (0.28 if k == 3 else 0.0)
        cover, _ = ellipse(c, cx, cy, 0.28, 0.33)
        c.over(cover, lit_color(c, "#C8B48A", cx, cy, 0.3, 0.6))
        c.over(poly_mask(c, [(cx - 0.06, cy - 0.28), (cx + 0.06, cy - 0.28), (cx + 0.04, cy - 0.4), (cx - 0.04, cy - 0.4)]), hexc("#8E7A55"))
    return p


def hay(variant):
    p = P(3.0, 3.0, 2.3)
    c = p.c
    ground_shadow(c, p.gx, p.gy, 1.3, 0.28)
    if variant == 0:  # a haystack
        cy = p.gy - 0.55
        cover, d = ellipse(c, p.gx, cy, 1.1, 1.0)
        cover = cover * (c.y < p.gy)
        streak = 0.9 + 0.1 * np.sin(c.x * 18.0 + c.y * 6.0)
        c.over(cover, lit_color(c, "#D2B25E", p.gx, cy, 1.0, 0.45) * streak[..., None])
    else:  # square bales
        for (ox, oy) in ((-0.55, 0.0), (0.55, 0.0), (0.0, -0.5)):
            x0, x1 = p.gx + ox - 0.5, p.gx + ox + 0.5
            yb = p.gy + oy
            front = poly_mask(c, [(x0, yb), (x1, yb), (x1, yb - 0.5), (x0, yb - 0.5)])
            c.over(front, hexc("#BFA052"))
            top = poly_mask(c, [(x0, yb - 0.5), (x1, yb - 0.5), (x1 - 0.1, yb - 0.75), (x0 + 0.1, yb - 0.75)])
            c.over(top, hexc("#DCC06C"))
    return p


def cart(variant):
    p = P(4.2, 3.0, 2.4)
    c = p.c
    ground_shadow(c, p.gx, p.gy, 1.8, 0.3)
    bx0, bx1, by = p.gx - 1.3, p.gx + 1.1, p.gy - 0.55
    c.over(poly_mask(c, [(bx0, by), (bx1, by), (bx1 + 0.1, by - 0.55), (bx0 - 0.1, by - 0.55)]), hexc("#8A6440"))
    c.over(poly_mask(c, [(bx0 - 0.1, by - 0.55), (bx1 + 0.1, by - 0.55), (bx1 - 0.1, by - 0.85), (bx0 + 0.1, by - 0.85)]), hexc("#A67E52"))
    # the shafts to the left, the wheel in front
    c.over(poly_mask(c, [(bx0 - 1.0, by - 0.25), (bx0, by - 0.3), (bx0, by - 0.2), (bx0 - 1.0, by - 0.15)]), hexc("#6E4E30"))
    cover, d = ellipse(c, p.gx - 0.1, p.gy - 0.45, 0.45, 0.45)
    ring = (d > 0.72) | (np.abs(np.sin(np.arctan2(c.y - (p.gy - 0.45), c.x - (p.gx - 0.1)) * 3.0)) < 0.18)
    c.over(cover * ring, hexc("#4E3822"))
    if variant == 1:  # loaded with hay
        cov, _ = ellipse(c, p.gx - 0.1, by - 1.0, 1.2, 0.45)
        c.over(cov * (c.y < by - 0.7), lit_color(c, "#D2B25E", p.gx, by - 1.0, 1.0))
    return p


def coal(variant):
    rng = random.Random(60 + variant)
    p = P(2.8, 2.0, 1.6)
    c = p.c
    ground_shadow(c, p.gx, p.gy, 1.1, 0.25)
    cover, d = ellipse(c, p.gx, p.gy - 0.3, 1.1, 0.55)
    cover = cover * (c.y < p.gy)
    grain = 0.8 + 0.2 * np.sin(c.x * 40.0 + np.sin(c.y * 33.0) * 3.0)
    c.over(cover, np.array([0.16, 0.15, 0.14])[None, None, :] * grain[..., None] * (1.0 + 0.4 * (1 - d))[..., None])
    for _ in range(3):
        x = p.gx + rng.uniform(-0.8, 0.8)
        cov, _ = ellipse(c, x, p.gy - 0.05, 0.18, 0.12)
        c.over(cov, np.array([0.2, 0.19, 0.18]))
    return p


def fence(variant):
    """A panel of wattle fence, 4 m long, along x."""
    p = P(4.6, 1.6, 1.2)
    c = p.c
    for i in range(5):
        x = p.gx - 2.0 + i
        c.over(poly_mask(c, [(x - 0.05, p.gy), (x + 0.05, p.gy), (x + 0.05, p.gy - 0.95), (x - 0.05, p.gy - 0.95)]), hexc("#5E4428"))
    for y in (p.gy - 0.3, p.gy - 0.6) if variant == 0 else (p.gy - 0.25, p.gy - 0.5, p.gy - 0.75):
        c.over(poly_mask(c, [(p.gx - 2.0, y - 0.04), (p.gx + 2.0, y - 0.04), (p.gx + 2.0, y + 0.04), (p.gx - 2.0, y + 0.04)]), hexc("#7A5A36"))
    return p


def stall(variant):
    """A market stall: a table and a striped awning."""
    p = P(4.0, 3.6, 3.0)
    c = p.c
    ground_shadow(c, p.gx, p.gy, 1.6, 0.3)
    x0, x1 = p.gx - 1.4, p.gx + 1.4
    c.over(poly_mask(c, [(x0, p.gy), (x1, p.gy), (x1, p.gy - 0.65), (x0, p.gy - 0.65)]), hexc("#8A6440"))
    c.over(poly_mask(c, [(x0, p.gy - 0.65), (x1, p.gy - 0.65), (x1 - 0.1, p.gy - 0.95), (x0 + 0.1, p.gy - 0.95)]), hexc("#A67E52"))
    for x in (x0 + 0.05, x1 - 0.05):
        c.over(poly_mask(c, [(x - 0.05, p.gy - 0.6), (x + 0.05, p.gy - 0.6), (x + 0.05, p.gy - 2.1), (x - 0.05, p.gy - 2.1)]), hexc("#5E4428"))
    a, b = ("#B5463A", "#E8DCC0") if variant == 0 else ("#3E6A8A", "#E8DCC0")
    aw = poly_mask(c, [(x0 - 0.2, p.gy - 1.9), (x1 + 0.2, p.gy - 1.9), (x1 + 0.1, p.gy - 2.5), (x0 - 0.1, p.gy - 2.5)])
    stripes = (np.floor((c.x - x0) / 0.35) % 2).astype(bool)
    col = np.where(stripes[..., None], hexc(a)[None, None, :], hexc(b)[None, None, :])
    c.over(aw, col * np.clip(1.05 - 0.6 * (c.y - (p.gy - 2.5)), 0.7, 1.05)[..., None])
    # wares on the table
    for k, colr in enumerate(["#C8B48A", "#9A6B3E", "#7FA24A", "#D6B354"]):
        cov, _ = ellipse(c, x0 + 0.45 + k * 0.62, p.gy - 1.02, 0.22, 0.14)
        c.over(cov, hexc(colr))
    return p


def reeds(variant):
    rng = random.Random(80 + variant)
    p = P(2.4, 2.8, 2.3)
    c = p.c
    for k in range(14 if variant == 0 else 9):
        x = p.gx + rng.uniform(-0.9, 0.9)
        h = rng.uniform(1.0, 1.9)
        lean = rng.uniform(-0.25, 0.25)
        w = 0.035
        base = hexc("#6E8A3E") if rng.random() < 0.6 else hexc("#8F9C4E")
        c.over(poly_mask(c, [(x - w, p.gy), (x + w, p.gy), (x + lean + w * 0.5, p.gy - h), (x + lean - w * 0.5, p.gy - h)]), base)
        if rng.random() < 0.45:  # a bulrush head
            cov, _ = ellipse(c, x + lean * 0.85, p.gy - h * 0.85, 0.05, 0.14)
            c.over(cov, hexc("#5A3E26"))
    return p


def bank_stone(variant):
    rng = random.Random(90 + variant)
    p = P(1.8, 1.4, 1.1)
    c = p.c
    for k in range(1 if variant == 0 else 3):
        cx = p.gx + (rng.uniform(-0.4, 0.4) if k else 0.0)
        r = 0.42 if k == 0 else rng.uniform(0.18, 0.28)
        cy = p.gy - r * 0.55
        cover, _ = ellipse(c, cx, cy, r, r * 0.62)
        c.over(cover, lit_color(c, "#9A9486", cx, cy, r, 0.6))
    return p


# --- the nucleus of the community (Rebirth, Phase 3) -----------------------------------------------------------

def hearth():
    """The common fire of the founders: a ring of stones round ash and embers, split logs crossed in it and a
    tripod with the pot hanging over it. The flames, the glow and the smoke are drawn live by the game."""
    rng = random.Random(100)
    p = P(3.8, 3.6, 2.5)
    c = p.c
    cx, cy = p.gx, p.gy
    ground_shadow(c, cx, cy + 0.1, 1.5, 0.22)
    # scorched earth round the ring
    cov, d = ellipse(c, cx, cy, 1.45, 0.95)
    c.over(cov * np.clip(1.15 - d, 0, 1) * 0.55, hexc("#4E4234"))
    stones = []
    n = 13
    for i in range(n):
        a = i / n * math.tau + rng.uniform(-0.08, 0.08)
        stones.append((math.sin(a), cx + math.cos(a) * 1.0, cy + math.sin(a) * 0.62, rng.uniform(0.17, 0.25), rng.uniform(0.85, 1.1)))

    def stone(sx, sy, r, tone):
        cov, _ = ellipse(c, sx, sy, r, r * 0.72)
        c.over(cov, lit_color(c, "#A8A292", sx + r * 0.25, sy + r * 0.15, r, 0.5) * tone)
        cov2, _ = ellipse(c, sx - r * 0.25, sy - r * 0.3, r * 0.45, r * 0.25)
        c.over(cov2 * 0.45, hexc("#CFC9BA"))

    # the stones behind the fire first
    for s in stones:
        if s[0] < 0:
            stone(*s[1:])
    # ash and embers
    cov, d = ellipse(c, cx, cy, 0.82, 0.5)
    ember = np.clip(1.0 - d * 1.15, 0, 1) ** 1.5
    ash = hexc("#5A5048")[None, None, :] * (0.75 + 0.35 * c.mottle(0.12, 7)[..., None])
    glow = hexc("#D0601E")[None, None, :]
    c.over(cov, ash * (1 - ember[..., None] * 0.8) + glow * (ember[..., None] * 0.8))
    # charred logs crossed in the fire
    for k, (ang, ln) in enumerate([(0.45, 0.62), (-0.5, 0.6), (0.05, 0.5)]):
        ca, sa = math.cos(ang), math.sin(ang) * 0.6
        x0, y0 = cx - ln * ca, cy - ln * sa - 0.05
        x1, y1 = cx + ln * ca, cy + ln * sa - 0.05
        c.over(poly_mask(c, [(x0, y0 + 0.08), (x1, y1 + 0.08), (x1, y1 - 0.08), (x0, y0 - 0.08)]), hexc("#2E231A"))
        c.over(poly_mask(c, [(x0, y0 - 0.02), (x1, y1 - 0.02), (x1, y1 - 0.07), (x0, y0 - 0.07)]) * 0.8, hexc("#6A4A30"))
        # the burning ends glow
        cov, _ = ellipse(c, (x0 + x1) * 0.5, (y0 + y1) * 0.5 - 0.02, 0.12, 0.07)
        c.over(cov * 0.8, hexc("#E08A2E"))
    # the tripod: three poles meeting over the fire, the pot on a chain
    apex = (cx + 0.02, cy - 1.75 * ZK - 0.2)
    legs = [(cx - 1.25, cy - 0.35), (cx + 1.2, cy - 0.3), (cx + 0.1, cy + 0.75)]
    for lx, ly in legs[:2]:
        c.over(poly_mask(c, [(lx - 0.05, ly), (lx + 0.05, ly), (apex[0] + 0.03, apex[1]), (apex[0] - 0.03, apex[1])]), hexc("#4A3524"))
    pot_y = cy - 0.62 * ZK
    c.over(poly_mask(c, [(apex[0] - 0.015, apex[1]), (apex[0] + 0.015, apex[1]), (apex[0] + 0.015, pot_y - 0.3), (apex[0] - 0.015, pot_y - 0.3)]),
           hexc("#2A2622"))
    body, _ = ellipse(c, apex[0], pot_y - 0.08, 0.3, 0.24)
    c.over(body, lit_color(c, "#3C3A38", apex[0], pot_y - 0.12, 0.3, 0.7))
    rim, _ = ellipse(c, apex[0], pot_y - 0.26, 0.3, 0.08)
    c.over(rim, hexc("#1E1C1A"))
    lx, ly = legs[2]
    c.over(poly_mask(c, [(lx - 0.055, ly), (lx + 0.055, ly), (apex[0] + 0.03, apex[1]), (apex[0] - 0.03, apex[1])]), hexc("#5A4230"))
    # and the stones in front
    for s in stones:
        if s[0] >= 0:
            stone(*s[1:])
    return p


def log_bench(variant):
    """A split trunk lying east-west to sit on, round the fire."""
    p = P(2.8, 1.3, 0.95)
    c = p.c
    ground_shadow(c, p.gx, p.gy, 1.2, 0.24)
    y = p.gy - 0.2
    x0, x1 = p.gx - 1.1, p.gx + 1.1
    body = poly_mask(c, [(x0, y + 0.2), (x1, y + 0.2), (x1, y - 0.14), (x0, y - 0.14)])
    shade = np.clip(1.05 - 1.4 * (c.y - (y - 0.14)), 0.55, 1.05)
    c.over(body, hexc("#6E4E30")[None, None, :] * (shade * (0.92 + 0.08 * np.sin(c.x * 23.0)))[..., None])
    top = poly_mask(c, [(x0 + 0.04, y - 0.14), (x1 - 0.04, y - 0.14), (x1 - 0.1, y - 0.3), (x0 + 0.1, y - 0.3)])
    c.over(top, hexc("#BC9262")[None, None, :] * (0.94 + 0.06 * np.sin(c.x * 41.0))[..., None])
    log_end(c, x1, y + 0.02, 0.19)
    return p


def landing():
    """The water point: planks on stakes from the bank over the water, seen FROM ABOVE and lying along +x (the game
    turns it toward the water). Pivot: the land end of the planks, in the middle."""
    rng = random.Random(130)
    p = P(3.6, 1.9, 0.95)
    p.gx = 0.25
    c = p.c
    x0, x1 = 0.25, 3.25
    y0, y1 = 0.2, 1.7
    # its shadow on the water and the stakes under the far end
    c.over(poly_mask(c, [(x0 + 0.5, y1), (x1 + 0.25, y1), (x1 + 0.25, y1 + 0.18), (x0 + 0.5, y1 + 0.18)]) * 0.35, hexc("#10202A"))
    for sy in (y0 + 0.08, y1 - 0.08):
        cov, _ = ellipse(c, x1 - 0.12, sy, 0.1, 0.1)
        c.over(cov, hexc("#3A2A1A"))
    # the two stringers, then the planks across them
    for sy in (y0 + 0.2, y1 - 0.2):
        c.over(poly_mask(c, [(x0, sy - 0.07), (x1, sy - 0.07), (x1, sy + 0.07), (x0, sy + 0.07)]), hexc("#4E3822"))
    x = x0 + 0.05
    k = 0
    while x < x1 - 0.2:
        w = rng.uniform(0.24, 0.3)
        tone = rng.uniform(0.86, 1.08)
        j0, j1 = rng.uniform(-0.06, 0.02), rng.uniform(-0.02, 0.06)
        plank = poly_mask(c, [(x, y0 + j0), (x + w, y0 + j0), (x + w, y1 + j1), (x, y1 + j1)])
        grain = 0.94 + 0.06 * np.sin(c.y * 31.0 + k * 2.1)
        c.over(plank, hexc("#9A7A52")[None, None, :] * (tone * grain * (1.0 + 0.05 * c.mottle(0.2, 20 + k)))[..., None])
        c.over(poly_mask(c, [(x + w - 0.035, y0 + j0), (x + w, y0 + j0), (x + w, y1 + j1), (x + w - 0.035, y1 + j1)]), hexc("#3E2C1C"))
        x += w + 0.035
        k += 1
    # the stake heads at the far end, over the planks
    for sy in (y0 + 0.08, y1 - 0.08):
        cov, _ = ellipse(c, x1 - 0.12, sy, 0.08, 0.08)
        c.over(cov, hexc("#7A5A3A"))
    p.gy = (y0 + y1) * 0.5
    return p


def buckets(variant):
    """Wooden buckets by the water, one of them full."""
    p = P(1.8, 1.3, 1.0)
    c = p.c
    ground_shadow(c, p.gx, p.gy, 0.7, 0.22)
    for k, dx in enumerate((-0.3, 0.32) if variant == 0 else (0.0,)):
        bx = p.gx + dx
        gy = p.gy - (0.04 if k else 0.0)
        top = gy - 0.46 * ZK
        body = poly_mask(c, [(bx - 0.2, gy), (bx + 0.2, gy), (bx + 0.25, top), (bx - 0.25, top)])
        shade = np.clip(1.1 - 0.9 * (c.x - (bx - 0.25)) / 0.5, 0.55, 1.1)
        c.over(body, hexc("#7C5634")[None, None, :] * shade[..., None])
        for yy in (gy - 0.07, top + 0.07):
            c.over(poly_mask(c, [(bx - 0.25, yy - 0.025), (bx + 0.25, yy - 0.025), (bx + 0.25, yy + 0.025), (bx - 0.25, yy + 0.025)]), hexc("#34281E"))
        cov, _ = ellipse(c, bx, top, 0.25, 0.1)
        c.over(cov, hexc("#3E6E8C") if k == 0 else hexc("#4A3522"))
    return p


PROPS = {
    "hearth_0": hearth,
    "bench_0": lambda: log_bench(0),
    "landing_0": landing,
    "buckets_0": lambda: buckets(0), "buckets_1": lambda: buckets(1),
    "woodpile_0": lambda: woodpile(0), "woodpile_1": lambda: woodpile(1),
    "logs_0": lambda: logs(0), "logs_1": lambda: logs(1),
    "stump_0": lambda: stump(0), "stump_1": lambda: stump(1),
    "crates_0": lambda: crates(0), "crates_1": lambda: crates(1),
    "barrels_0": lambda: barrels(0), "barrels_1": lambda: barrels(1),
    "sacks_0": lambda: sacks(0), "sacks_1": lambda: sacks(1),
    "hay_0": lambda: hay(0), "hay_1": lambda: hay(1),
    "cart_0": lambda: cart(0), "cart_1": lambda: cart(1),
    "coal_0": lambda: coal(0), "coal_1": lambda: coal(1),
    "fence_0": lambda: fence(0), "fence_1": lambda: fence(1),
    "stall_0": lambda: stall(0), "stall_1": lambda: stall(1),
    "reeds_0": lambda: reeds(0), "reeds_1": lambda: reeds(1),
    "stone_0": lambda: bank_stone(0), "stone_1": lambda: bank_stone(1),
}


def main():
    sprites = []
    for name, fn in PROPS.items():
        p = fn()
        res = p.c.result()
        if not name.startswith("reeds"):
            res = ink_outline(res, 0.4)
        img, piv = trim(res, p.pivot())
        sprites.append({"id": name, "img": img, "pivot": piv})
    sprites.sort(key=lambda s: -s["img"].shape[0])
    width = 512
    x = y = shelf = 0
    for s in sprites:
        h, w, _ = s["img"].shape
        if x + w + 4 > width:
            x, y, shelf = 0, y + shelf + 4, 0
        s["pos"] = (x + 2, y + 2)
        x += w + 4
        shelf = max(shelf, h)
    height = 1 << (y + shelf + 4 - 1).bit_length()
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
    write_png(os.path.join(OUT_DIR, "props_atlas.png"), out)
    with open(os.path.join(OUT_DIR, "props_atlas.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"version": 1, "atlas": "props_atlas.png", "width": width, "height": height, "ppm": PPM,
                   "sprites": entries}, f, indent=1)
    prev = os.path.join(HERE, "out_preview")
    os.makedirs(prev, exist_ok=True)
    bg = hexc("#8FA257")
    comp = atlas[..., :3] * atlas[..., 3:4] + bg * (1.0 - atlas[..., 3:4])
    write_png(os.path.join(prev, "props.png"), (comp * 255).astype(np.uint8))
    print("props atlas", width, height, len(entries))


if __name__ == "__main__":
    main()

