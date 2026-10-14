"""Plain 2D pixel drawing for things that are not 3D models: ground tiles, effects, HUD icons.

Colours are '#rrggbb' strings from the palette ramps; alpha is 0..255 (effects may fade, sprites
used as fighters or props must stay fully opaque or fully clear).
"""
from __future__ import annotations

import math
from typing import Sequence

import numpy as np

from .color import hex_to_rgb, rgb_to_oklab


def rgba8(color: str, a: int = 255) -> np.ndarray:
    r, g, b = hex_to_rgb(color)
    return np.array([round(r * 255), round(g * 255), round(b * 255), a], dtype=np.uint8)


class Canvas:
    def __init__(self, W: int, H: int) -> None:
        self.W = W
        self.H = H
        self.a = np.zeros((H, W, 4), dtype=np.uint8)

    def px(self, x: int, y: int, color: str, a: int = 255) -> None:
        if 0 <= x < self.W and 0 <= y < self.H:
            self.a[y, x] = rgba8(color, a)

    def get(self, x: int, y: int) -> np.ndarray:
        return self.a[y, x]

    def clear(self, x: int, y: int) -> None:
        if 0 <= x < self.W and 0 <= y < self.H:
            self.a[y, x] = 0

    def rect(self, x0: int, y0: int, x1: int, y1: int, color: str, a: int = 255) -> None:
        """Filled rectangle, corners inclusive."""
        for y in range(max(0, y0), min(self.H, y1 + 1)):
            for x in range(max(0, x0), min(self.W, x1 + 1)):
                self.a[y, x] = rgba8(color, a)

    def line(self, x0: int, y0: int, x1: int, y1: int, color: str, a: int = 255) -> None:
        """Bresenham line (pixel-perfect: no doubled corners)."""
        dx = abs(x1 - x0)
        dy = -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.px(x0, y0, color, a)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def ellipse(self, cx: float, cy: float, rx: float, ry: float, color: str, a: int = 255,
                fill: bool = True) -> None:
        for y in range(self.H):
            for x in range(self.W):
                u = (x + 0.5 - cx) / max(rx, 1e-6)
                v = (y + 0.5 - cy) / max(ry, 1e-6)
                d = u * u + v * v
                if fill and d <= 1.0:
                    self.a[y, x] = rgba8(color, a)
                elif not fill and 0.72 <= d <= 1.0:
                    self.a[y, x] = rgba8(color, a)

    def poly(self, pts: Sequence[tuple[float, float]], color: str, a: int = 255) -> None:
        """Filled polygon (pixel centres inside)."""
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        for y in range(max(0, int(min(ys))), min(self.H, int(math.ceil(max(ys))) + 1)):
            for x in range(max(0, int(min(xs))), min(self.W, int(math.ceil(max(xs))) + 1)):
                if _inside(x + 0.5, y + 0.5, pts):
                    self.a[y, x] = rgba8(color, a)

    def ascii(self, rows: Sequence[str], legend: dict[str, str | tuple[str, int]], x: int = 0,
              y: int = 0) -> None:
        """Pastes a hand-drawn picture: each character maps to a colour (or (colour, alpha));
        '.' and ' ' stay clear."""
        for r, row in enumerate(rows):
            for c, ch in enumerate(row):
                if ch in ". " or ch not in legend:
                    continue
                v = legend[ch]
                if isinstance(v, tuple):
                    self.px(x + c, y + r, v[0], v[1])
                else:
                    self.px(x + c, y + r, v)

    def outline(self, color: str, diagonal: bool = False, a: int = 255) -> None:
        """1-pixel outline outside every opaque pixel."""
        solid = self.a[..., 3] > 0
        out = np.zeros_like(solid)
        offs = [(0, -1), (-1, 0), (1, 0), (0, 1)]
        if diagonal:
            offs += [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        for dx, dy in offs:
            shifted = np.zeros_like(solid)
            ys = slice(max(0, dy), self.H + min(0, dy))
            yd = slice(max(0, -dy), self.H + min(0, -dy))
            xs = slice(max(0, dx), self.W + min(0, dx))
            xd = slice(max(0, -dx), self.W + min(0, -dx))
            shifted[yd, xd] = solid[ys, xs]
            out |= shifted
        out &= ~solid
        self.a[out] = rgba8(color, a)

    def paste(self, img: np.ndarray, x: int, y: int) -> None:
        """Alpha-over paste of an RGBA array (opaque pixels win)."""
        h, w = img.shape[:2]
        for yy in range(h):
            for xx in range(w):
                if img[yy, xx, 3] > 0 and 0 <= x + xx < self.W and 0 <= y + yy < self.H:
                    self.a[y + yy, x + xx] = img[yy, xx]


def _inside(x: float, y: float, pts: Sequence[tuple[float, float]]) -> bool:
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def nearest(colors: Sequence[str], rgb: np.ndarray) -> np.ndarray:
    """Index of the nearest palette colour (OKLab distance) for each pixel of rgb (..., 3) 0..255."""
    pal = np.array([rgb_to_oklab(hex_to_rgb(c)) for c in colors])
    flat = rgb.reshape(-1, 3) / 255.0
    lab = np.array([rgb_to_oklab(tuple(p)) for p in flat])
    d = ((lab[:, None, :] - pal[None, :, :]) ** 2).sum(-1)
    return d.argmin(-1).reshape(rgb.shape[:-1])
