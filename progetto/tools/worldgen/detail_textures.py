"""Tileable noise texture used by the terrain shader for soft colour variation and edge warping.

Run: "<blender python>" tools/worldgen/detail_textures.py
Writes assets/environment/terrain/noise_tile.png (512x512 RGB, three independent channels).
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE))

from kdio import write_png  # noqa: E402
from kdnoise import Perlin  # noqa: E402

SIZE = 512


def tile_fbm(seed, period, octaves=5, gain=0.5):
    ys, xs = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64)
    total = np.zeros((SIZE, SIZE))
    amp, norm, p = 1.0, 0.0, period
    for o in range(octaves):
        total += Perlin(seed + o * 101, period=p).noise(xs / SIZE * p, ys / SIZE * p) * amp
        norm += amp
        amp *= gain
        p *= 2
    return total / (norm * 0.7)


def to_u8(a):
    a = a - a.mean()
    a = a / (np.abs(a).max() + 1e-9)
    return np.clip(128.0 + 100.0 * a, 0, 255).astype(np.uint8)


def main():
    out = os.path.join(ROOT, "assets", "environment", "terrain")
    os.makedirs(out, exist_ok=True)
    rgb = np.stack([to_u8(tile_fbm(501, 4)), to_u8(tile_fbm(502, 4)), to_u8(tile_fbm(503, 8, 4))], axis=-1)
    write_png(os.path.join(out, "noise_tile.png"), rgb)
    print("noise_tile")


if __name__ == "__main__":
    main()

