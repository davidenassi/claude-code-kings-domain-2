"""Vectorised gradient noise helpers for the King's Domain world generator."""
import numpy as np


def fade(t):
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


class Perlin:
    """2D gradient noise, evaluated on numpy arrays. Output roughly in [-0.7, 0.7]."""

    def __init__(self, seed, period=None):
        rng = np.random.default_rng(seed)
        perm = rng.permutation(256).astype(np.int64)
        self.perm = np.concatenate([perm, perm])
        angles = rng.random(256) * 2.0 * np.pi
        self.gx = np.cos(angles)
        self.gy = np.sin(angles)
        self.period = period  # integer lattice period for tileable noise, or None

    def _grad(self, ix, iy, dx, dy):
        h = self.perm[self.perm[ix & 255] + (iy & 255)]
        return self.gx[h] * dx + self.gy[h] * dy

    def noise(self, x, y):
        x = np.asarray(x, dtype=np.float64)
        y = np.asarray(y, dtype=np.float64)
        x0 = np.floor(x)
        y0 = np.floor(y)
        xf = x - x0
        yf = y - y0
        ix = x0.astype(np.int64)
        iy = y0.astype(np.int64)
        ix1 = ix + 1
        iy1 = iy + 1
        if self.period:
            p = self.period
            ix, iy, ix1, iy1 = ix % p, iy % p, ix1 % p, iy1 % p
        n00 = self._grad(ix, iy, xf, yf)
        n10 = self._grad(ix1, iy, xf - 1.0, yf)
        n01 = self._grad(ix, iy1, xf, yf - 1.0)
        n11 = self._grad(ix1, iy1, xf - 1.0, yf - 1.0)
        u = fade(xf)
        v = fade(yf)
        a = n00 + (n10 - n00) * u
        b = n01 + (n11 - n01) * u
        return a + (b - a) * v


def fbm(perlin, x, y, octaves=5, lacunarity=2.0, gain=0.5, offset_step=17.31):
    """Fractal sum normalised to about [-1, 1]."""
    total = np.zeros(np.broadcast(x, y).shape, dtype=np.float64)
    amp = 1.0
    freq = 1.0
    norm = 0.0
    for o in range(octaves):
        total += perlin.noise(x * freq + o * offset_step, y * freq - o * offset_step) * amp
        norm += amp
        amp *= gain
        freq *= lacunarity
    return total / (norm * 0.7)


def ridged(perlin, x, y, octaves=5, lacunarity=2.1, gain=0.5):
    """Ridged multifractal in [0, 1]: sharp crests for mountain chains."""
    total = np.zeros(np.broadcast(x, y).shape, dtype=np.float64)
    amp = 1.0
    freq = 1.0
    norm = 0.0
    weight = np.ones_like(total)
    for o in range(octaves):
        n = 1.0 - np.abs(perlin.noise(x * freq + o * 7.7, y * freq + o * 3.3) / 0.7)
        n = np.clip(n, 0.0, 1.0) ** 2
        n *= weight
        weight = np.clip(n * 1.6, 0.0, 1.0)
        total += n * amp
        norm += amp
        amp *= gain
        freq *= lacunarity
    return total / norm


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

