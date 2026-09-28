"""Painterly building sprites for the settlements (same light 3/4 illustrated style as trees and mountains).

Run with Blender's bundled Python (numpy):
  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\5.2\\python\\bin\\python.exe" tools/art/draw_buildings.py
Output: assets/buildings/building_atlas.png + .json

Projection: the ground footprint keeps its real size in metres (it matches the map and the placement preview);
height rises towards the top of the screen by ZK per metre. Light from the upper left, soft shadow to the lower right.
Each sprite: pivot = centre of the footprint on the ground, size_m = sprite size in metres.
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
from draw_vegetation import Canvas, hexc, broadleaf, PALETTES  # noqa: E402
import random  # noqa: E402

PPM = 8.0
ZK = 0.72          # screen metres per metre of height
MARGIN = 2.0
OUT_DIR = os.path.join(ROOT, "assets", "buildings")


def poly_mask(c, pts):
    """Anti-aliased-ish polygon coverage (even-odd, supersampled canvas)."""
    x, y = c.x, c.y
    inside = np.zeros(x.shape, dtype=bool)
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        if y1 == y2:
            continue
        cond = ((y1 > y) != (y2 > y))
        xint = (x2 - x1) * (y - y1) / (y2 - y1) + x1
        inside ^= cond & (x < xint)
    return inside.astype(float)


def soft_rect(c, x0, y0, x1, y1, feather):
    dx = np.minimum(c.x - x0, x1 - c.x)
    dy = np.minimum(c.y - y0, y1 - c.y)
    return np.clip(np.minimum(dx, dy) / feather, 0.0, 1.0)


def shade(base, k):
    return np.clip(base * k, 0, 1)


class B:
    """Helper bound to a canvas and a footprint (x0,y0)-(x1,y1) in canvas metres."""

    def __init__(self, fw, fd, top_extra):
        self.fw, self.fd = fw, fd
        self.top = top_extra
        self.c = Canvas(fw + MARGIN * 2 + 2, fd + top_extra + MARGIN * 2 + 1.5, PPM)
        self.x0 = MARGIN + 1
        self.y0 = MARGIN + top_extra
        self.x1 = self.x0 + fw
        self.y1 = self.y0 + fd
        self.seed = 0

    def pivot(self):
        return ((self.x0 + self.x1) * 0.5 * PPM, (self.y0 + self.y1) * 0.5 * PPM)

    def mottle(self, scale, amt=0.08):
        self.seed += 1
        return 1.0 + amt * self.c.mottle(scale, self.seed)

    def ground(self, color="#8C7650", grow=1.0, alpha=0.85):
        c = self.c
        cover = soft_rect(c, self.x0 - grow, self.y0 - grow, self.x1 + grow, self.y1 + grow, 1.2) * alpha
        col = hexc(color)[None, None, :] * self.mottle(1.5, 0.12)[..., None]
        c.over(cover, col)

    def shadow(self, x0, y0, x1, y1, h, strength=0.35):
        c = self.c
        off = h * 0.35
        cover = soft_rect(c, x0 + off * 0.6, y0 + off * 0.2, x1 + off, y1 + off * 0.45, 1.0 + h * 0.08) * strength
        c.over(cover, np.array([0.12, 0.10, 0.06]))

    def wall(self, x0, x1, yf, h, color, planks=True, dark=1.0):
        c = self.c
        top = yf - h * ZK
        cover = poly_mask(c, [(x0, yf), (x1, yf), (x1, top), (x0, top)])
        base = hexc(color) * dark
        k = self.mottle(0.6, 0.07)
        if planks:
            k = k * (0.92 + 0.08 * np.sign(np.sin(c.x * math.pi / 0.45)))
        grad = 0.82 + 0.18 * np.clip((yf - c.y) / max(h * ZK, 0.1), 0, 1)
        c.over(cover, base[None, None, :] * (k * grad)[..., None])
        # dark line at the base and under the eaves
        c.over(poly_mask(c, [(x0, yf), (x1, yf), (x1, yf - 0.18), (x0, yf - 0.18)]) * 0.5, np.array([0.12, 0.09, 0.06]))

    def door(self, cx, yf, w=1.1, h=2.0, color="#3A2A1C"):
        top = yf - h * ZK
        self.c.over(poly_mask(self.c, [(cx - w / 2, yf), (cx + w / 2, yf), (cx + w / 2, top), (cx - w / 2, top)]), hexc(color))

    def window(self, cx, yc, w=0.8, h=0.7):
        self.c.over(poly_mask(self.c, [(cx - w / 2, yc + h / 2), (cx + w / 2, yc + h / 2), (cx + w / 2, yc - h / 2), (cx - w / 2, yc - h / 2)]),
                    np.array([0.16, 0.12, 0.08]))

    def roof(self, x0, x1, yb, yf, h, rise, color, kind="thatch", oh=0.6):
        """Gable roof along x: back slope (lit) above the ridge, front slope (shaded) below."""
        c = self.c
        ymid = (yb + yf) * 0.5
        ridge = ymid - (h + rise) * ZK
        eave_f = yf - h * ZK + oh * 0.5
        eave_b = yb - h * ZK - oh * 0.3
        base = hexc(color)
        tex = self._roof_tex(kind)
        back = poly_mask(c, [(x0 - oh, eave_b), (x1 + oh, eave_b), (x1 + oh, ridge), (x0 - oh, ridge)])
        c.over(back, (base * 1.18)[None, None, :] * tex[..., None])
        front = poly_mask(c, [(x0 - oh, ridge), (x1 + oh, ridge), (x1 + oh, eave_f), (x0 - oh, eave_f)])
        g = np.clip((c.y - ridge) / max(eave_f - ridge, 0.1), 0, 1)
        c.over(front, base[None, None, :] * (tex * (0.95 - 0.2 * g))[..., None])
        c.over(poly_mask(c, [(x0 - oh, ridge - 0.12), (x1 + oh, ridge - 0.12), (x1 + oh, ridge + 0.12), (x0 - oh, ridge + 0.12)]) * 0.7,
               shade(base, 0.6))
        c.over(poly_mask(c, [(x0 - oh, eave_f - 0.15), (x1 + oh, eave_f - 0.15), (x1 + oh, eave_f + 0.1), (x0 - oh, eave_f + 0.1)]) * 0.6,
               shade(base, 0.55))

    def roof_front_gable(self, x0, x1, yb, yf, h, rise, color, wall_color, kind="thatch", oh=0.5):
        """Gable facing the viewer: ridge along y, lit left slope, shaded right slope, triangular gable wall in front."""
        c = self.c
        xm = (x0 + x1) * 0.5
        eave_f = yf - h * ZK
        eave_b = yb - h * ZK
        ridge_f = yf - (h + rise) * ZK
        ridge_b = yb - (h + rise) * ZK
        base = hexc(color)
        tex = self._roof_tex(kind)
        # gable wall
        gable = poly_mask(c, [(x0, eave_f), (x1, eave_f), (xm, ridge_f)])
        c.over(gable, hexc(wall_color)[None, None, :] * (0.95 * self.mottle(0.6, 0.06))[..., None])
        left = poly_mask(c, [(x0 - oh, eave_b), (xm, ridge_b - 0.2), (xm, ridge_f - 0.2), (x0 - oh, eave_f + oh * 0.4)])
        c.over(left, (base * 1.15)[None, None, :] * tex[..., None])
        right = poly_mask(c, [(xm, ridge_b - 0.2), (x1 + oh, eave_b), (x1 + oh, eave_f + oh * 0.4), (xm, ridge_f - 0.2)])
        c.over(right, (base * 0.72)[None, None, :] * tex[..., None])
        # bargeboards along the front edges of the roof
        for (ax, ay, bx, by) in [(x0 - oh, eave_f + oh * 0.4, xm, ridge_f - 0.2), (xm, ridge_f - 0.2, x1 + oh, eave_f + oh * 0.4)]:
            nx, ny = -(by - ay), (bx - ax)
            ln = math.hypot(nx, ny)
            nx, ny = nx / ln * 0.14, ny / ln * 0.14
            c.over(poly_mask(c, [(ax - nx, ay - ny), (bx - nx, by - ny), (bx + nx, by + ny), (ax + nx, ay + ny)]) * 0.85,
                   shade(base, 0.5))

    def _roof_tex(self, kind):
        c = self.c
        if kind == "thatch":
            return (0.9 + 0.1 * np.sin(c.y * 14.0 + 3.0 * c.mottle(0.25, 7))) * self.mottle(0.8, 0.1)
        if kind == "shingle":
            row = np.floor(c.y / 0.45)
            return (0.88 + 0.12 * np.sign(np.sin((c.x + row * 0.35) * math.pi / 0.55))) * (0.93 + 0.07 * (row % 2)) * self.mottle(1.0, 0.06)
        return self.mottle(0.7, 0.08)

    def chimney(self, cx, yb, yf, h, rise, color="#8A8272", smoke=True):
        """A stone chimney through the roof near the ridge, with a thread of smoke."""
        c = self.c
        ymid = (yb + yf) * 0.5
        top = ymid - (h + rise + 0.9) * ZK
        base = ymid - (h + rise * 0.55) * ZK
        c.over(poly_mask(c, [(cx - 0.32, base), (cx + 0.32, base), (cx + 0.32, top), (cx - 0.32, top)]),
               hexc(color)[None, None, :] * self.mottle(0.3, 0.12)[..., None])
        c.over(poly_mask(c, [(cx + 0.12, base), (cx + 0.32, base), (cx + 0.32, top), (cx + 0.12, top)]) * 0.35, np.array([0.1, 0.08, 0.06]))
        if smoke:
            for i, (ox, oy, r) in enumerate([(0.1, 0.7, 0.35), (0.45, 1.5, 0.5), (0.9, 2.4, 0.65)]):
                dd = np.sqrt((c.x - (cx + ox)) ** 2 + (c.y - (top - oy)) ** 2)
                c.over(np.clip((r - dd) / 0.45, 0, 1) * (0.28 - i * 0.07), np.array([0.86, 0.85, 0.83]))

    def lean_to(self, x0, x1, yb, yf, h, color_wall, color_roof):
        """A low annex against the right wall: a shed roof sloping away from the house."""
        c = self.c
        self.wall(x0, x1, yf, h, color_wall, dark=0.9)
        top_b = yb - (h + 0.8) * ZK
        top_f = yf - h * ZK
        c.over(poly_mask(c, [(x0 - 0.1, top_b), (x1 + 0.3, top_b + 0.4), (x1 + 0.3, top_f + 0.3), (x0 - 0.1, top_f)]),
               hexc(color_roof)[None, None, :] * self._roof_tex("shingle")[..., None] * 0.9)

    def logs(self, x0, x1, yf, rows=3, r=0.35):
        c = self.c
        for j in range(rows):
            n = int((x1 - x0) / (2 * r)) - j
            for i in range(n):
                cx = x0 + r + i * 2 * r + j * r
                cy = yf - r - j * r * 1.7
                d = np.sqrt((c.x - cx) ** 2 + ((c.y - cy) / 0.9) ** 2)
                cover = np.clip((r - d) / c.aa, 0, 1)
                ring = 0.85 + 0.15 * np.sin(d * 28.0)
                col = hexc("#B58A55")[None, None, :] * ring[..., None] * np.where(d > r * 0.8, 0.6, 1.0)[..., None]
                c.over(cover, col)

    def stones(self, cx, cy, n, size, seed):
        rng = random.Random(seed)
        c = self.c
        for _ in range(n):
            px = cx + rng.uniform(-size, size)
            py = cy + rng.uniform(-size * 0.5, size * 0.5)
            r = rng.uniform(0.3, 0.6)
            d = np.sqrt(((c.x - px) / 1.2) ** 2 + (c.y - py) ** 2)
            cover = np.clip((r - d) / c.aa, 0, 1)
            lit = np.clip(0.6 - 0.8 * (c.x - px) - 0.8 * (c.y - py), 0.3, 1.0)
            c.over(cover, hexc("#A39C8E")[None, None, :] * (0.7 + 0.4 * lit)[..., None])

    def palisade(self, x0, x1, y_line, h, front=True):
        c = self.c
        step = 0.42
        x = x0
        while x < x1 - 0.01:
            k = 0.85 + 0.15 * math.sin(x * 7.3)
            top = y_line - h * ZK * (0.94 + 0.06 * math.sin(x * 5.1))
            pts = [(x, y_line), (x + step, y_line), (x + step, top), (x + step * 0.5, top - 0.35), (x, top)]
            col = hexc("#7A5634") * k
            c.over(poly_mask(c, pts), col * (1.0 if front else 0.8))
            c.over(poly_mask(c, [(x + step - 0.06, y_line), (x + step, y_line), (x + step, top), (x + step - 0.06, top)]) * 0.5,
                   np.array([0.2, 0.14, 0.08]))
            x += step


# ---------------------------------------------------------------------------------------------------

def house(fw=8.0, fd=8.0, h=2.6, rise=3.0, wall="#8A6A45", roof_col="#B89A5A", kind="thatch", extra=None, front_gable=True):
    b = B(fw, fd, (h + rise) * ZK + 1.5)
    b.ground("#8E7A55", 0.8)
    inset = 0.8
    x0, x1, yb, yf = b.x0 + inset, b.x1 - inset, b.y0 + inset + 1.0, b.y1 - inset
    b.shadow(x0, yb, x1, yf, h + rise)
    b.wall(x0, x1, yf, h, wall)
    b.door((x0 + x1) * 0.5, yf)
    b.window(x0 + (x1 - x0) * 0.2, yf - h * ZK * 0.55)
    b.window(x1 - (x1 - x0) * 0.2, yf - h * ZK * 0.55)
    if front_gable:
        b.roof_front_gable(x0, x1, yb, yf, h, rise, roof_col, wall, kind)
    else:
        b.roof(x0, x1, yb, yf, h, rise, roof_col, kind)
    if extra:
        extra(b, x0, x1, yb, yf)
    return b


def house_annex():
    """A longer house with a lean-to on the right and a chimney: the family that grew."""
    def extra(b, x0, x1, yb, yf):
        b.chimney(x0 + (x1 - x0) * 0.3, yb, yf, 2.5, 2.6)
    b = B(8.0, 8.0, (2.5 + 2.6) * ZK + 2.6)
    b.ground("#8E7A55", 0.8)
    inset = 0.6
    x0, x1, yb, yf = b.x0 + inset, b.x1 - 2.6, b.y0 + inset + 1.0, b.y1 - inset
    b.shadow(x0, yb, b.x1 - 0.4, yf, 5.0)
    b.lean_to(x1, b.x1 - 0.4, yb + 1.0, yf, 1.6, "#7E6243", "#8E7A48")
    b.wall(x0, x1, yf, 2.5, "#9A7A52")
    b.door((x0 + x1) * 0.5, yf)
    b.window(x0 + 0.9, yf - 2.5 * ZK * 0.55)
    b.roof(x0, x1, yb, yf, 2.5, 2.6, "#A8894E", "thatch")
    extra(b, x0, x1, yb, yf)
    return b


def house_stone():
    """Stone walls and a slate roof, a chimney: the house of someone who has done well."""
    def extra(b, x0, x1, yb, yf):
        b.chimney(x1 - 1.4, yb, yf, 2.7, 3.0, "#7E7A70")
    return house(h=2.7, rise=3.0, wall="#9C958A", roof_col="#5E6670", kind="shingle", extra=extra, front_gable=True)


def church():
    """The church of a borough (Rebirth, Phase 5): a stone nave with a slate roof, a bell tower at the front, a round
    window over the door. Footprint 16 x 10 m, the tower on the left."""
    fw, fd = 16.0, 10.0
    b = B(fw, fd, 15.5 * ZK + 3.0)
    b.ground("#8B8067", 0.8, 0.8)
    c = b.c
    # the nave: long walls along x, gable roof
    nx0, nx1, yb, yf = b.x0 + 4.4, b.x1 - 0.6, b.y0 + 1.6, b.y1 - 1.2
    b.shadow(b.x0 + 0.6, yb, nx1, yf, 9.0, 0.32)
    b.wall(nx0, nx1, yf, 4.6, "#A39C8E", planks=False)
    for wx in np.linspace(nx0 + 1.6, nx1 - 1.6, 4):
        # tall narrow windows with round heads
        b.window(wx, yf - 4.6 * ZK * 0.55, 0.55, 1.3)
    b.roof(nx0, nx1, yb, yf, 4.6, 3.4, "#5C6168", "shingle", 0.4)
    # the tower at the front left, taller, with its pointed roof and the bell opening
    tx0, tx1, ty1 = b.x0 + 0.8, b.x0 + 4.8, b.y1 - 0.6
    b.wall(tx0, tx1, ty1, 10.5, "#9A9384", planks=False)
    b.window((tx0 + tx1) * 0.5, ty1 - 10.5 * ZK * 0.82, 1.0, 1.1)   # the bell chamber
    b.window((tx0 + tx1) * 0.5, ty1 - 10.5 * ZK * 0.45, 0.45, 1.0)
    b.door((tx0 + tx1) * 0.5, ty1, 1.5, 2.6, "#4A3524")
    top = ty1 - 10.5 * ZK
    spire = poly_mask(c, [(tx0 - 0.3, top + 0.2), (tx1 + 0.3, top + 0.2), ((tx0 + tx1) * 0.5, top - 4.6)])
    shade_sp = np.clip(1.15 - 0.6 * (c.x - tx0) / max(tx1 - tx0, 0.1), 0.6, 1.15)
    c.over(spire, hexc("#565B62")[None, None, :] * shade_sp[..., None])
    # the cross on the spire
    cx = (tx0 + tx1) * 0.5
    c.over(poly_mask(c, [(cx - 0.06, top - 4.5), (cx + 0.06, top - 4.5), (cx + 0.06, top - 5.6), (cx - 0.06, top - 5.6)]), hexc("#3A2E24"))
    c.over(poly_mask(c, [(cx - 0.35, top - 5.15), (cx + 0.35, top - 5.15), (cx + 0.35, top - 5.27), (cx - 0.35, top - 5.27)]), hexc("#3A2E24"))
    return b


def keep():
    fw = fd = 14.0
    b = B(fw, fd, 13.0 * ZK + 3.0)
    b.ground("#7F6B4B", 1.0, 0.85)
    x0, x1, y0, y1 = b.x0 + 0.5, b.x1 - 0.5, b.y0 + 0.5, b.y1 - 0.5
    b.shadow(x0, y0, x1, y1, 6.0, 0.3)
    # back palisade, tower, side palisades, front palisade with gate
    b.palisade(x0, x1, y0 + 0.4, 2.6, front=False)
    tx0, tx1, ty0, ty1 = b.x0 + 4.5, b.x0 + 9.5, b.y0 + 3.0, b.y0 + 8.0
    b.shadow(tx0, ty0, tx1, ty1, 11.0, 0.3)
    b.wall(tx0, tx1, ty1, 8.5, "#7E5D3B")
    b.window((tx0 + tx1) * 0.5, ty1 - 8.5 * ZK * 0.75, 0.6, 0.9)
    b.window((tx0 + tx1) * 0.5, ty1 - 8.5 * ZK * 0.4, 0.6, 0.9)
    b.roof(tx0 - 0.3, tx1 + 0.3, ty0, ty1, 8.5, 2.6, "#6E5536", "shingle", 0.5)
    # banner pole
    c = b.c
    px = (tx0 + tx1) * 0.5
    ptop = (ty0 + ty1) * 0.5 - (8.5 + 2.6) * ZK - 2.6
    c.over(poly_mask(c, [(px - 0.06, ptop + 2.4), (px + 0.06, ptop + 2.4), (px + 0.06, ptop), (px - 0.06, ptop)]), np.array([0.25, 0.18, 0.1]))
    c.over(poly_mask(c, [(px + 0.06, ptop + 0.05), (px + 1.6, ptop + 0.35), (px + 0.06, ptop + 0.95)]), hexc("#2F4F9E"))
    # small house inside
    b.wall(b.x0 + 9.8, b.x0 + 13.0, b.y0 + 11.0, 2.2, "#8A6A45")
    b.roof(b.x0 + 9.8, b.x0 + 13.0, b.y0 + 8.4, b.y0 + 11.0, 2.2, 1.6, "#B89A5A", "thatch", 0.3)
    for x in (x0, x1 - 0.42):
        b.palisade(x, x + 0.42, y1, 2.6)
    b.palisade(x0, (x0 + x1) * 0.5 - 1.3, y1, 2.6)
    b.palisade((x0 + x1) * 0.5 + 1.3, x1, y1, 2.6)
    b.door((x0 + x1) * 0.5, y1, 2.4, 2.4, "#4A3524")
    return b


def shelter():
    fw, fd = 10.0, 8.0
    b = B(fw, fd, 3.2 * ZK + 2.0)
    b.ground("#8C7A56", 0.6)
    c = b.c
    x0, x1, y0, y1 = b.x0 + 0.8, b.x1 - 0.8, b.y0 + 1.2, b.y1 - 1.2
    b.shadow(x0, y0, x1, y1, 3.0)
    # posts
    for px in np.linspace(x0, x1, 4):
        c.over(poly_mask(c, [(px - 0.1, y1), (px + 0.1, y1), (px + 0.1, y1 - 2.0 * ZK), (px - 0.1, y1 - 2.0 * ZK)]), np.array([0.3, 0.22, 0.13]))
    # lean-to roof of branches: high at the back, low at the front
    back = y0 - 3.2 * ZK
    front = y1 - 2.0 * ZK
    tex = (0.85 + 0.15 * np.sin(c.x * 9.0 + 4.0 * c.mottle(0.3, 3))) * b.mottle(0.7, 0.12)
    c.over(poly_mask(c, [(x0 - 0.5, back), (x1 + 0.5, back), (x1 + 0.5, front), (x0 - 0.5, front)]),
           hexc("#7D7040")[None, None, :] * tex[..., None])
    c.over(poly_mask(c, [(x0 - 0.5, front - 0.2), (x1 + 0.5, front - 0.2), (x1 + 0.5, front + 0.15), (x0 - 0.5, front + 0.15)]) * 0.7,
           np.array([0.28, 0.24, 0.12]))
    # bedding under the roof: rolled blankets (the fire is the common one, on the square: Rebirth, Phase 3)
    for i, bx in enumerate(np.linspace(x0 + 1.0, x1 - 1.0, 3)):
        d = np.sqrt((c.x - bx) ** 2 + ((c.y - (y1 - 0.45)) / 0.55) ** 2)
        c.over(np.clip((0.42 - d) / c.aa, 0, 1), hexc("#8A6E58") * (0.9 + 0.06 * i))
    return b


def camp_store(fw=8.0, fd=6.0):
    """What six people carry into an empty valley: a low lean-to over the sacks, the first stack of wood."""
    b = B(fw, fd, 2.2 * ZK + 1.6)
    b.ground("#86744F", 0.55)
    c = b.c
    x0, x1, y0, y1 = b.x0 + 3.2, b.x1 - 0.4, b.y0 + 1.0, b.y1 - 1.4
    b.shadow(x0, y0, x1, y1, 2.0)
    # a small lean-to on the right, over the stores
    for px in np.linspace(x0, x1, 3):
        c.over(poly_mask(c, [(px - 0.09, y1), (px + 0.09, y1), (px + 0.09, y1 - 1.5 * ZK), (px - 0.09, y1 - 1.5 * ZK)]),
               np.array([0.3, 0.22, 0.13]))
    back = y0 - 2.2 * ZK
    front = y1 - 1.5 * ZK
    tex = (0.85 + 0.15 * np.sin(c.x * 9.0 + 4.0 * c.mottle(0.3, 3))) * b.mottle(0.7, 0.12)
    c.over(poly_mask(c, [(x0 - 0.4, back), (x1 + 0.4, back), (x1 + 0.4, front), (x0 - 0.4, front)]),
           hexc("#7A6C3E")[None, None, :] * tex[..., None])
    # sacks of grain under it
    for i, sx in enumerate(np.linspace(x0 + 0.5, x1 - 0.6, 3)):
        d = np.sqrt((c.x - sx) ** 2 + ((c.y - (y1 - 0.3)) / 0.8) ** 2)
        c.over(np.clip((0.42 - d) / c.aa, 0, 1), hexc("#C2A26B") * (0.92 + 0.05 * i))
    # the first stack of wood on the left (the fire is the common one, on the square: Rebirth, Phase 3)
    b.logs(b.x0 + 0.3, b.x0 + 2.8, b.y1 - 0.5, 2, 0.3)
    return b


def woodcutter():
    def extra(b, x0, x1, yb, yf):
        b.logs(b.x0 - 0.2, b.x0 + 3.6, b.y1 + 0.6, 3)
        c = b.c
        cx, cy = b.x1 - 0.8, b.y1 + 0.4
        d = np.sqrt((c.x - cx) ** 2 + ((c.y - cy) / 0.6) ** 2)
        c.over(np.clip((0.45 - d) / c.aa, 0, 1), hexc("#9C774A"))
    return house(7.0, 6.0, 2.3, 2.2, "#7E6040", "#8F7A48", "shingle", extra)


def quarry():
    def extra(b, x0, x1, yb, yf):
        b.stones(b.x0 + 1.2, b.y1 + 0.3, 9, 1.4, 11)
        b.stones(b.x1 - 1.0, b.y1 + 0.1, 5, 0.8, 12)
    return house(6.5, 5.5, 2.2, 1.8, "#8D8474", "#77705E", "shingle", extra)


def bakery():
    def extra(b, x0, x1, yb, yf):
        c = b.c
        cx, cy = b.x1 - 0.6, b.y1 - 0.6
        d = np.sqrt((c.x - cx) ** 2 + ((c.y - cy) / 0.8) ** 2)
        dome = np.clip((1.5 - d) / c.aa, 0, 1) * (c.y < cy + 0.5)
        lit = np.clip(0.65 - 0.5 * (c.x - cx) - 0.5 * (c.y - cy), 0.3, 1)
        c.over(dome, hexc("#B7765A")[None, None, :] * (0.7 + 0.45 * lit)[..., None])
        c.over(np.clip((0.45 - np.sqrt((c.x - cx) ** 2 + ((c.y - cy - 0.3) / 0.6) ** 2)) / c.aa, 0, 1), np.array([0.1, 0.07, 0.05]))
        # chimney smoke
        for i, (ox, oy, r) in enumerate([(0.0, 3.8, 0.5), (0.4, 4.9, 0.7), (0.9, 6.2, 0.9)]):
            dd = np.sqrt((c.x - (x0 + 1.2 + ox)) ** 2 + (c.y - (yb - oy)) ** 2)
            c.over(np.clip((r - dd) / 0.5, 0, 1) * (0.35 - i * 0.08), np.array([0.85, 0.84, 0.82]))
    return house(7.0, 7.0, 2.6, 2.4, "#9A7C58", "#9C5B3E", "shingle", extra)


def mine():
    def extra(b, x0, x1, yb, yf):
        # timbered adit mouth into the slope and a heap of spoil
        c = b.c
        mx, my = (x0 + x1) * 0.5, yb - 0.2
        c.over(poly_mask(c, [(mx - 1.0, my + 0.9), (mx - 1.0, my - 0.2), (mx + 1.0, my - 0.2), (mx + 1.0, my + 0.9)]), hexc("#4A3A2A"))
        c.over(poly_mask(c, [(mx - 1.2, my + 1.0), (mx - 1.2, my - 0.35), (mx - 0.95, my - 0.35), (mx - 0.95, my + 1.0)]), hexc("#7A5A38"))
        c.over(poly_mask(c, [(mx + 0.95, my + 1.0), (mx + 0.95, my - 0.35), (mx + 1.2, my - 0.35), (mx + 1.2, my + 1.0)]), hexc("#7A5A38"))
        c.over(poly_mask(c, [(mx - 1.35, my - 0.35), (mx + 1.35, my - 0.35), (mx + 1.35, my - 0.6), (mx - 1.35, my - 0.6)]), hexc("#6B4E30"))
        b.stones(b.x1 - 1.4, b.y1 + 0.2, 8, 1.2, 33)
    return house(7.0, 6.5, 2.3, 2.0, "#7A6A5A", "#6A6258", "shingle", extra)


def smith(wall="#7E6448", roof="#5E5852"):
    def extra(b, x0, x1, yb, yf):
        c = b.c
        # chimney with smoke and an anvil in the yard
        cx = x1 - 1.2
        top = yb - 1.6
        c.over(poly_mask(c, [(cx - 0.4, yb + 0.6), (cx + 0.4, yb + 0.6), (cx + 0.4, top), (cx - 0.4, top)]), hexc("#8A7A6A"))
        for i, (ox, oy, r) in enumerate([(0.1, 1.0, 0.45), (0.5, 2.0, 0.65), (1.0, 3.1, 0.85)]):
            dd = np.sqrt((c.x - (cx + ox)) ** 2 + (c.y - (top - oy)) ** 2)
            c.over(np.clip((r - dd) / 0.5, 0, 1) * (0.32 - i * 0.07), np.array([0.55, 0.54, 0.52]))
        ax, ay = b.x0 + 1.4, b.y1 + 0.2
        c.over(poly_mask(c, [(ax - 0.5, ay), (ax + 0.5, ay), (ax + 0.5, ay - 0.3), (ax - 0.5, ay - 0.3)]), hexc("#4C4A48"))
        c.over(poly_mask(c, [(ax - 0.2, ay - 0.3), (ax + 0.2, ay - 0.3), (ax + 0.2, ay - 0.6), (ax - 0.2, ay - 0.6)]), hexc("#5C5A56"))
    return house(7.5, 7.0, 2.5, 2.2, wall, roof, "shingle", extra)


def granary(roof="#C2A661", wall="#94744C"):
    b = B(10.0, 10.0, 6.0 * ZK + 2.5)
    b.ground("#8E7A55", 0.6)
    c = b.c
    x0, x1, yb, yf = b.x0 + 1.2, b.x1 - 1.2, b.y0 + 2.0, b.y1 - 1.5
    b.shadow(x0, yb, x1, yf, 6.0)
    stilt = 1.2
    for px in np.linspace(x0 + 0.3, x1 - 0.3, 4):
        c.over(poly_mask(c, [(px - 0.14, yf), (px + 0.14, yf), (px + 0.14, yf - stilt * ZK), (px - 0.14, yf - stilt * ZK)]), np.array([0.3, 0.22, 0.14]))
    b.wall(x0, x1, yf - stilt * ZK, 2.6, wall)
    b.door((x0 + x1) * 0.5, yf - stilt * ZK, 1.2, 1.8)
    b.roof(x0, x1, yb - stilt * ZK, yf - stilt * ZK, 2.6, 3.0, roof, "thatch", 0.8)
    return b


def storehouse():
    def extra(b, x0, x1, yb, yf):
        b.logs(b.x0 - 0.3, b.x0 + 4.2, b.y1 + 0.5, 2, 0.32)
        b.stones(b.x1 - 1.5, b.y1 + 0.2, 6, 1.0, 21)
    return house(12.0, 10.0, 3.2, 3.2, "#7C5E3E", "#6F5A3A", "shingle", extra, front_gable=False)


def barracks(wall="#7E6A4A", roof="#6E5536"):
    """A long low hall with a training yard: spear rack against the wall and a couple of shields."""
    def extra(b, x0, x1, yb, yf):
        c = b.c
        for i in range(5):
            sx = x0 + 0.9 + i * 0.5
            line_x = [(sx - 0.05, yf + 1.5), (sx + 0.05, yf + 1.5), (sx + 0.05, yf - 0.4), (sx - 0.05, yf - 0.4)]
            c.over(poly_mask(c, line_x), np.array([0.42, 0.3, 0.18]))
            c.over(poly_mask(c, [(sx, yf - 0.75), (sx + 0.08, yf - 0.42), (sx - 0.08, yf - 0.42)]), hexc("#B9BCC2"))
        for (sx, col) in ((x1 - 1.6, "#8A7148"), (x1 - 0.9, "#6E7B52")):
            c.over(poly_mask(c, [(sx - 0.28, yf - 1.5), (sx + 0.28, yf - 1.5), (sx + 0.28, yf - 0.75),
                                 (sx, yf - 0.5), (sx - 0.28, yf - 0.75)]), hexc(col))
    return house(14.0, 10.0, 3.0, 2.8, wall, roof, "shingle", extra, front_gable=False)


def well():
    b = B(4.0, 4.0, 3.2 * ZK + 1.5)
    b.ground("#8B8067", 0.3, 0.7)
    c = b.c
    cx, cy = (b.x0 + b.x1) * 0.5, (b.y0 + b.y1) * 0.5 + 0.4
    b.shadow(cx - 1.4, cy - 1.0, cx + 1.4, cy + 1.2, 2.0)
    ring = np.sqrt((c.x - cx) ** 2 + ((c.y - cy) / 0.65) ** 2)
    wall_cov = np.clip((1.4 - ring) / c.aa, 0, 1)
    c.over(wall_cov, hexc("#9D968A")[None, None, :] * b.mottle(0.3, 0.12)[..., None])
    c.over(np.clip((0.95 - ring) / c.aa, 0, 1), np.array([0.12, 0.16, 0.2]))
    for px in (cx - 1.2, cx + 1.2):
        c.over(poly_mask(c, [(px - 0.1, cy), (px + 0.1, cy), (px + 0.1, cy - 2.6 * ZK), (px - 0.1, cy - 2.6 * ZK)]), np.array([0.3, 0.22, 0.13]))
    b.roof(cx - 1.4, cx + 1.4, cy - 0.8, cy + 0.2, 2.6, 0.9, "#6E5536", "shingle", 0.3)
    return b


def farm(stage, mirror=False, roof="#B89A5A", wall="#8A6A45"):
    fw, fd = 26.0, 30.0
    b = B(fw, fd, 5.0 * ZK + 2.0)
    c = b.c
    # fields: rows along x below the farmstead strip
    fy0 = b.y0 + 9.0
    if stage == "none":
        # only the farmstead: the game draws the field itself, in strips, by the season (world art pass)
        return farmstead(b, fy0, mirror, roof, wall)
    soil = hexc("#7A5E3C")
    field = soft_rect(c, b.x0, fy0, b.x1, b.y1, 0.6)
    rows = 0.5 + 0.5 * np.sin(c.y * math.pi / 0.9)
    tex = b.mottle(2.0, 0.12)
    if stage == "bare":
        col = soil[None, None, :] * ((0.85 + 0.15 * rows) * tex)[..., None]
    elif stage == "green":
        green = hexc("#7FA24A")
        col = (soil[None, None, :] * (1 - rows[..., None] * 0.9) + green[None, None, :] * rows[..., None] * 0.9) * tex[..., None]
    else:
        gold = hexc("#D6B354")
        col = (soil[None, None, :] * (1 - rows[..., None] * 0.95) + gold[None, None, :] * rows[..., None] * 0.95) * tex[..., None]
    c.over(field, col)
    # fence along the field edge
    for x in np.arange(b.x0, b.x1 + 0.01, 2.0):
        c.over(poly_mask(c, [(x - 0.07, fy0), (x + 0.07, fy0), (x + 0.07, fy0 - 1.0 * ZK), (x - 0.07, fy0 - 1.0 * ZK)]), np.array([0.32, 0.24, 0.15]))
    c.over(poly_mask(c, [(b.x0, fy0 - 0.75 * ZK - 0.05), (b.x1, fy0 - 0.75 * ZK - 0.05), (b.x1, fy0 - 0.75 * ZK + 0.07), (b.x0, fy0 - 0.75 * ZK + 0.07)]),
           np.array([0.38, 0.28, 0.17]))
    # farmstead: yard, house, haystack
    c.over(soft_rect(c, b.x0, b.y0, b.x1, fy0 - 0.3, 0.8) * 0.85, hexc("#8E7A55")[None, None, :] * b.mottle(1.2, 0.1)[..., None])
    hx0, hx1, hyb, hyf = b.x0 + 2.0, b.x0 + 10.0, b.y0 + 1.5, b.y0 + 7.5
    b.shadow(hx0, hyb, hx1, hyf, 5.0)
    b.wall(hx0, hx1, hyf, 2.5, "#8A6A45")
    b.door((hx0 + hx1) * 0.5, hyf)
    b.window(hx0 + 1.5, hyf - 2.5 * ZK * 0.55)
    b.roof_front_gable(hx0, hx1, hyb, hyf, 2.5, 2.6, "#B89A5A", "#8A6A45", "thatch")
    sx, sy = b.x1 - 5.0, b.y0 + 5.5
    d = np.sqrt((c.x - sx) ** 2 + ((c.y - sy) / 0.75) ** 2)
    hay = np.clip((2.0 - d) / c.aa, 0, 1) * (c.y < sy + 1.0)
    lit = np.clip(0.7 - 0.35 * (c.x - sx) - 0.35 * (c.y - sy), 0.3, 1)
    c.over(hay, hexc("#CFAE5E")[None, None, :] * (0.65 + 0.45 * lit)[..., None])
    return b


def farmstead(b, fy0, mirror, roof, wall):
    c = b.c
    c.over(soft_rect(c, b.x0 + 0.5, b.y0 + 0.3, b.x1 - 0.5, fy0 - 0.6, 1.4) * 0.8,
           hexc("#8E7A55")[None, None, :] * b.mottle(1.2, 0.1)[..., None])
    if mirror:
        hx0, hx1 = b.x1 - 11.0, b.x1 - 2.5
        sx = b.x0 + 5.0
    else:
        hx0, hx1 = b.x0 + 2.0, b.x0 + 10.0
        sx = b.x1 - 5.0
    hyb, hyf = b.y0 + 1.5, b.y0 + 7.5
    b.shadow(hx0, hyb, hx1, hyf, 5.0)
    b.wall(hx0, hx1, hyf, 2.5, wall)
    b.door((hx0 + hx1) * 0.5, hyf)
    b.window(hx0 + 1.5, hyf - 2.5 * ZK * 0.55)
    if mirror:
        b.roof(hx0, hx1, hyb, hyf, 2.5, 2.6, roof, "thatch")
        b.chimney(hx0 + 2.0, hyb, hyf, 2.5, 2.6)
    else:
        b.roof_front_gable(hx0, hx1, hyb, hyf, 2.5, 2.6, roof, wall, "thatch")
    sy = b.y0 + 5.5
    d = np.sqrt((c.x - sx) ** 2 + ((c.y - sy) / 0.75) ** 2)
    hay = np.clip((2.0 - d) / c.aa, 0, 1) * (c.y < sy + 1.0)
    lit = np.clip(0.7 - 0.35 * (c.x - sx) - 0.35 * (c.y - sy), 0.3, 1)
    c.over(hay, hexc("#CFAE5E")[None, None, :] * (0.65 + 0.45 * lit)[..., None])
    # a short fence closing the yard towards the fields
    for x in np.arange(b.x0 + 1.0, b.x1 - 0.9, 2.0):
        c.over(poly_mask(c, [(x - 0.07, fy0 - 0.8), (x + 0.07, fy0 - 0.8), (x + 0.07, fy0 - 0.8 - 1.0 * ZK), (x - 0.07, fy0 - 0.8 - 1.0 * ZK)]),
               np.array([0.32, 0.24, 0.15]))
    return b


def site(fw, fd):
    """Construction ground: levelled earth, corner stakes, string line, a few planks."""
    b = B(fw, fd, 1.5)
    b.ground("#9A8158", 0.4, 0.9)
    c = b.c
    for (x, y) in [(b.x0, b.y0), (b.x1, b.y0), (b.x0, b.y1), (b.x1, b.y1)]:
        c.over(poly_mask(c, [(x - 0.1, y), (x + 0.1, y), (x + 0.1, y - 0.9), (x - 0.1, y - 0.9)]), np.array([0.35, 0.26, 0.16]))
    for (xa, ya, xb, yb) in [(b.x0, b.y0 - 0.7, b.x1, b.y0 - 0.7), (b.x0, b.y1 - 0.7, b.x1, b.y1 - 0.7)]:
        c.over(poly_mask(c, [(xa, ya - 0.03), (xb, yb - 0.03), (xb, yb + 0.03), (xa, ya + 0.03)]) * 0.8, np.array([0.9, 0.86, 0.75]))
    for (x0, x1, y1) in [(b.x0 + 0.8, b.x0 + 2.4, b.y1 - 0.5), (b.x1 - 2.4, b.x1 - 0.6, b.y0 + 1.2)]:
        c.over(poly_mask(c, [(x0, y1), (x1, y1), (x1, y1 - 0.25), (x0, y1 - 0.25)]), np.array([0.62, 0.47, 0.3]))
    return b


SPRITES = {
    "keep": keep, "shelter": shelter, "camp_store": camp_store, "house": house, "woodcutter": woodcutter,
    "church": church,
    "quarry": quarry, "bakery": bakery,
    # the same house three ways, on the same 8x8 footprint: a village of identical clones reads as a prototype
    "house_1": lambda: house(wall="#A08560", roof_col="#8E4E36", kind="shingle", front_gable=False),
    "house_2": lambda: house(h=2.4, rise=2.6, wall="#6F553A", roof_col="#9C8446", kind="thatch"),
    # world art pass: five houses in all — the one that grew an annex, and the one in stone
    "house_3": house_annex,
    "house_4": house_stone,
    # the farmstead alone (the field is drawn by the game), two ways
    "farmstead": lambda: farm("none"),
    "farmstead_1": lambda: farm("none", True, "#9C5B3E", "#8E7050"),
    "storehouse_1": lambda: house(12.0, 10.0, 3.2, 3.0, "#8E7250", "#9C8446", "thatch", None, front_gable=False),
    "granary_1": lambda: granary("#B89A5A", "#7E6040"),
    "smith_1": lambda: smith("#8F7A62", "#6E4E3A"),
    "barracks_1": lambda: barracks("#8C7A5C", "#5E6670"),
    "mine": mine, "smith": smith, "granary": granary, "storehouse": storehouse, "well": well, "barracks": barracks,
    "farm_bare": lambda: farm("bare"), "farm_green": lambda: farm("green"), "farm_ripe": lambda: farm("ripe"),
    "site_s": lambda: site(4.0, 4.0), "site_m": lambda: site(8.0, 8.0), "site_l": lambda: site(12.0, 10.0),
    "site_xl": lambda: site(26.0, 30.0),
}


def ink_outline(img, strength=0.55):
    """Thin dark contour around opaque shapes (drawn behind them): keeps silhouettes readable on busy ground."""
    a = img[..., 3]
    solid = (a > 0.9).astype(float)
    grown = np.maximum.reduce([np.roll(np.roll(solid, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1)])
    ring = np.clip(grown - solid, 0, 1) * strength
    out = img.copy()
    ink = np.array([0.16, 0.11, 0.07])
    new_a = a + ring * (1 - a)
    out[..., :3] = np.where(new_a[..., None] > 1e-4, (img[..., :3] * a[..., None] + ink * (ring * (1 - a))[..., None]) / np.maximum(new_a, 1e-4)[..., None], img[..., :3])
    out[..., 3] = new_a
    return out


def trim(img, pivot, margin=1):
    ys, xs = np.nonzero(img[..., 3] > 0.01)
    x0, x1 = max(xs.min() - margin, 0), min(xs.max() + margin + 1, img.shape[1])
    y0, y1 = max(ys.min() - margin, 0), min(ys.max() + margin + 1, img.shape[0])
    return img[y0:y1, x0:x1], (pivot[0] - x0, pivot[1] - y0)


def main():
    sprites = []
    for name, fn in SPRITES.items():
        b = fn()
        res = b.c.result()
        if not name.startswith("site") and not name.startswith("farm_"):
            res = ink_outline(res)
        img, piv = trim(res, b.pivot())
        sprites.append({"id": name, "img": img, "pivot": piv})
    sprites.sort(key=lambda s: -s["img"].shape[0])
    width = 1024
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
    a = atlas[..., 3]
    rgb = atlas[..., :3]
    for _ in range(3):
        m = a < 0.01
        acc = np.zeros_like(rgb)
        cnt = np.zeros(a.shape)
        for ax in (0, 1):
            for sgn in (1, -1):
                sa = np.roll(a, sgn, axis=ax) >= 0.01
                acc += np.roll(rgb, sgn, axis=ax) * sa[..., None]
                cnt += sa
        fill = m & (cnt > 0)
        rgb[fill] = acc[fill] / cnt[fill][:, None]
        a = np.where(fill, 0.011, a)
    out = np.clip(np.concatenate([rgb, atlas[..., 3:4]], axis=-1) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    os.makedirs(OUT_DIR, exist_ok=True)
    write_png(os.path.join(OUT_DIR, "building_atlas.png"), out)
    with open(os.path.join(OUT_DIR, "building_atlas.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump({"version": 1, "atlas": "building_atlas.png", "width": width, "height": height, "ppm": PPM,
                   "sprites": entries}, f, indent=1)
    prev = os.path.join(HERE, "out_preview")
    os.makedirs(prev, exist_ok=True)
    bg = hexc("#8FA257")
    comp = atlas[..., :3] * atlas[..., 3:4] + bg * (1.0 - atlas[..., 3:4])
    write_png(os.path.join(prev, "buildings.png"), (comp * 255).astype(np.uint8))
    print("building atlas", width, height, len(entries))


if __name__ == "__main__":
    main()

