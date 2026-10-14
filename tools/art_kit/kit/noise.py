"""Deterministic value noise (2D and 3D), optionally periodic so textures tile seamlessly.

No global random state: every call takes a seed, so the same inputs always give the same pixels.
"""
from __future__ import annotations

import numpy as np


def _hash(ix: np.ndarray, iy: np.ndarray, iz: np.ndarray, seed: int) -> np.ndarray:
    h = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263
         + iz.astype(np.int64) * 2147483647 + np.int64(seed) * 144665) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFF).astype(np.float64) / 65535.0


def _fade(t: np.ndarray) -> np.ndarray:
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def value3(p: np.ndarray, seed: int = 0) -> np.ndarray:
    """3D value noise in [-1, 1] for points p (N, 3)."""
    f = np.floor(p)
    t = _fade(p - f)
    i = f.astype(np.int64)
    out = np.zeros(p.shape[0])
    for dx in (0, 1):
        wx = t[:, 0] if dx else 1.0 - t[:, 0]
        for dy in (0, 1):
            wy = t[:, 1] if dy else 1.0 - t[:, 1]
            for dz in (0, 1):
                wz = t[:, 2] if dz else 1.0 - t[:, 2]
                out += wx * wy * wz * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out * 2.0 - 1.0


def fbm3(p: np.ndarray, seed: int = 0, octaves: int = 3, lacunarity: float = 2.0,
         gain: float = 0.5) -> np.ndarray:
    total = np.zeros(p.shape[0])
    amp = 1.0
    norm = 0.0
    q = p.copy()
    for o in range(octaves):
        total += amp * value3(q, seed + o * 101)
        norm += amp
        amp *= gain
        q = q * lacunarity
    return total / norm


def value2(x: np.ndarray, y: np.ndarray, seed: int = 0, period: int | None = None) -> np.ndarray:
    """2D value noise in [0, 1]. With `period` (lattice cells) it tiles with that period."""
    fx = np.floor(x)
    fy = np.floor(y)
    tx = _fade(x - fx)
    ty = _fade(y - fy)
    ix = fx.astype(np.int64)
    iy = fy.astype(np.int64)

    def h(ax: np.ndarray, ay: np.ndarray) -> np.ndarray:
        if period:
            ax = np.mod(ax, period)
            ay = np.mod(ay, period)
        return _hash(ax, ay, np.zeros_like(ax), seed)

    a = h(ix, iy)
    b = h(ix + 1, iy)
    c = h(ix, iy + 1)
    d = h(ix + 1, iy + 1)
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def fbm2(x: np.ndarray, y: np.ndarray, seed: int = 0, octaves: int = 4, period: int | None = None,
         gain: float = 0.5) -> np.ndarray:
    """Fractal 2D noise in about [0, 1]. With `period` each octave tiles (period doubles)."""
    total = np.zeros_like(np.asarray(x, dtype=np.float64))
    amp = 1.0
    norm = 0.0
    freq = 1.0
    for o in range(octaves):
        p = period * int(freq) if period else None
        total = total + amp * value2(x * freq, y * freq, seed + o * 57, p)
        norm += amp
        amp *= gain
        freq *= 2.0
    return total / norm


def tile_grid(size: int, cells: int) -> tuple[np.ndarray, np.ndarray]:
    """Pixel-centre coordinates of a size x size tile in lattice units (cells per tile), for
    periodic noise: pass period=cells."""
    c = (np.arange(size) + 0.5) * (cells / size)
    return np.meshgrid(c, c)


def worley_tile(size: int, cells: int, seed: int = 0, jitter: float = 0.8) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Periodic Voronoi on a size x size tile with cells x cells feature points.

    Returns (f1, f2, cell_id): distance to the nearest and second-nearest point (in pixels) and
    the nearest point's id. f2 - f1 is small along cell borders (mortar lines, cracks).
    """
    rng = np.random.default_rng(seed)
    pts = (np.stack(np.meshgrid(np.arange(cells), np.arange(cells)), -1).reshape(-1, 2)
           + 0.5 + (rng.random((cells * cells, 2)) - 0.5) * jitter) * (size / cells)
    ids = np.arange(cells * cells)
    # Copies in the 8 neighbouring tiles make it seamless.
    all_pts = []
    all_ids = []
    for ox in (-1, 0, 1):
        for oy in (-1, 0, 1):
            all_pts.append(pts + np.array([ox * size, oy * size]))
            all_ids.append(ids)
    P = np.concatenate(all_pts)
    I = np.concatenate(all_ids)
    yy, xx = np.mgrid[0:size, 0:size] + 0.5
    d = np.sqrt((xx[..., None] - P[:, 0]) ** 2 + (yy[..., None] - P[:, 1]) ** 2)
    order = np.argsort(d, axis=-1)
    f1 = np.take_along_axis(d, order[..., :1], -1)[..., 0]
    f2 = np.take_along_axis(d, order[..., 1:2], -1)[..., 0]
    cid = I[order[..., 0]]
    return f1, f2, cid
