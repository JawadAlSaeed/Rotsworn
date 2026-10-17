"""What the "?" pictures are made of (card #199; the scenes are in event_art.py): the `Painter` for the
flat back of a picture, and the materials of the 3D things in front of it.

"""
from __future__ import annotations

import math

import numpy as np

from kit.canvas import Canvas
from kit.color import from_oklch, hex_to_rgb, mix, ramp, rgb_to_oklab, to_oklch
from kit.noise import fbm2
from kit.palette import INK, M, Material
from kit.render import line3d, stamp
from kit.sdf import (Box, Capsule, Cylinder, Ellipsoid, Intersect, Moved, Prism, RoundCone, SmoothUnion, Sphere,
                     Subtract, Torus, Union, rot)

from assets.env_props import (BARK, BARK_PALE, GroundCut, HOLE, STONE, _face, _world, dead_tree_model, finish_prop,
                              flatten_thin, ink_outline, lch_mat, mat, render_fit, branch, roots, Scaled)
from assets.env_zone import CANVAS, DARK_STONE, IRON, LEATHER, SKIN, _hooded

SW = 128
SH = 64
BAYER8 = np.array([
    [0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26], [12, 44, 4, 36, 14, 46, 6, 38],
    [60, 28, 52, 20, 62, 30, 54, 22], [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21]]) / 64.0


def _bayer() -> np.ndarray:
    return np.tile(BAYER8, (SH // 8 + 1, SW // 8 + 1))[:SH, :SW]


B = _bayer()
YY, XX = np.mgrid[0:SH, 0:SW].astype(np.float64)


def rgb(hex_: str) -> np.ndarray:
    return np.array(hex_to_rgb(hex_), dtype=np.float64)


def ramp_rgb(colors: list[str]) -> np.ndarray:
    return np.array([hex_to_rgb(c) for c in colors], dtype=np.float64)


def make_ramp(base: str, below: int = 2, above: int = 2, **kw) -> list[str]:
    return ramp(base, below=below, above=above, **kw)


def lch_ramp(stops: list[tuple[float, float, float]]) -> list[str]:
    return [from_oklch(L, C, h) for L, C, h in stops]


def _hash_noise(n: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    return rng.random(n)


def fbm1(x: np.ndarray, seed: int, octaves: int = 3) -> np.ndarray:
    """1D fractal noise in about [0, 1] (the ridge lines)."""
    return fbm2(x, np.zeros_like(x) + 0.37, seed=seed, octaves=octaves)


# --- The back: a painter that works in ramps ----------------------------------------------------


class Painter:
    """A 128x64 float RGB picture and the ramps it was made of (see the module doc)."""

    def __init__(self, seed: int) -> None:
        self.img = np.zeros((SH, SW, 3))
        self.seed = seed
        self.rng = np.random.default_rng(seed)
        self.palette: list[str] = []

    def use(self, colors: list[str]) -> np.ndarray:
        self.palette.extend(colors)
        return ramp_rgb(colors)

    def paint(self, mask: np.ndarray, colors: list[str], tone: np.ndarray, d: float = 0.32) -> None:
        """Fills `mask` from a ramp: `tone` 0..1 picks the colour, a light ordered dither cuts the
        bands (d = how wide the dithered strip between two colours is)."""
        r = self.use(colors)
        n = len(r)
        level = np.clip(tone, 0.0, 1.0) * (n - 1)
        idx = np.clip(np.floor(level + 0.5 + (B - 0.5) * d), 0, n - 1).astype(int)
        self.img[mask] = r[idx][mask]

    def sky(self, colors: list[str], horizon: int, stars: int = 0, clouds: float = 0.07) -> None:
        t = 1.0 - YY / max(horizon, 1)  # 1 at the top, 0 at the horizon
        t = t + (fbm2(XX / 38.0, YY / 7.0, seed=self.seed + 3, octaves=3) - 0.5) * clouds * 2.0
        self.paint(YY <= horizon + 2, colors, 1.0 - t)
        for _ in range(stars):
            x, y = int(self.rng.integers(2, SW - 2)), int(self.rng.integers(1, max(2, horizon - 8)))
            self.img[y, x] = rgb(colors[-1]) * 0.8 + rgb(colors[-2]) * 0.2

    def disk(self, cx: float, cy: float, r: float, colors: list[str], halo: float = 0.0) -> None:
        d = np.hypot(XX + 0.5 - cx, YY + 0.5 - cy)
        if halo > 0:
            a = np.clip(1.0 - (d - r) / halo, 0.0, 1.0) ** 2 * 0.55
            self.tint(a, colors[-1])
        k = d <= r
        shade = np.clip((XX + 0.5 - cx) * 0.4 / r + (YY + 0.5 - cy) * 0.5 / r + 0.5, 0.0, 1.0)
        self.paint(k, colors, 1.0 - shade * 0.9)

    def ridge(self, colors: list[str], base: float, amp: float, freq: float, seed: int, tone: float,
              fade: float = 0.0, flat: float = 0.0, y_to: float = SH) -> np.ndarray:
        """A silhouette of hills: ground from a wavy line downward. tone = the colour at the top
        edge, getting darker `fade` per ten pixels down. Returns the crest y per column."""
        crest = base - amp * ((fbm1(np.arange(SW) / freq, seed) - 0.5) * 2.4 + 0.45 - flat)
        mask = YY >= crest[None, :]
        mask &= YY <= y_to
        depth = np.clip(YY - crest[None, :], 0.0, None)
        self.paint(mask, colors, tone - fade * depth / 10.0)
        return crest

    def line(self, x0: int, y0: int, x1: int, y1: int, colour: np.ndarray) -> None:
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(n + 1):
            x = round(x0 + (x1 - x0) * i / n)
            y = round(y0 + (y1 - y0) * i / n)
            if 0 <= x < SW and 0 <= y < SH:
                self.img[y, x] = colour

    def dead_tree(self, x: int, base: int, height: int, colour: np.ndarray, seed: int, lean: float = 0.0,
                  twigs: int = 4) -> None:
        """A bare tree as a 1 to 2 pixel silhouette: a trunk and a few forking limbs."""
        rng = np.random.default_rng(seed)
        top_x = x + lean * height
        pts = [(x + (top_x - x) * t / 6.0 + math.sin(t * 1.3 + seed) * 0.8, base - height * t / 6.0) for t in range(7)]
        for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
            self.line(round(ax), round(ay), round(bx), round(by), colour)
            if height > 22:
                self.line(round(ax) + 1, round(ay), round(bx) + 1, round(by), colour)
        if height > 30:
            for yy in range(round(base - 2), round(base - height * 0.25), -1):
                self.img[yy, round(x) + 2 if yy % 2 else round(x) - 1] = colour
        for k in range(twigs):
            t = 2 + k * (4 / max(twigs, 1))
            px, py = pts[min(5, int(t))]
            side = -1 if rng.random() < 0.5 else 1
            length = height * (0.25 + 0.2 * rng.random())
            ex, ey = px + side * length, py - length * (0.35 + 0.5 * rng.random())
            self.line(round(px), round(py), round(ex), round(ey), colour)
            fx, fy = (px + ex) / 2.0, (py + ey) / 2.0
            self.line(round(fx), round(fy), round(fx + side * length * 0.4), round(fy - length * 0.35), colour)
            self.line(round(ex), round(ey), round(ex + side * length * 0.25), round(ey - length * 0.3), colour)

    def ground(self, colors: list[str], y0: int, tone: float = 0.5, spread: float = 0.26, seed: int = 0,
               grain: float = 0.085) -> None:
        """Open ground from y0 down: noise stretched along x near the horizon (so it recedes), a
        little darker toward the viewer."""
        yy = np.clip(YY - y0 + 1.0, 1.0, None)
        scale = 3.0 + yy * 1.2
        n = fbm2(XX / scale, yy / (scale * 0.42), seed=self.seed + seed, octaves=3)
        t = tone + (n - 0.5) * spread * 2.0 - 0.1 * np.clip((YY - y0) / (SH - y0), 0.0, 1.0)
        t += (fbm2(XX / 2.2, YY / 1.6, seed=self.seed + seed + 9, octaves=2) - 0.5) * grain * 2.0
        self.paint(YY >= y0, colors, t)

    def tint(self, amount: np.ndarray, colour: str, levels: int = 3, strength: float = 0.55) -> None:
        """Mixes toward `colour` where `amount` (0..1) is, in `levels` dithered steps."""
        a = np.floor(np.clip(amount, 0.0, 1.0) * levels + B * 0.9) / levels
        a = np.clip(a, 0.0, 1.0) * strength
        self.palette.append(colour)
        self.img = self.img * (1.0 - a[..., None]) + rgb(colour)[None, None, :] * a[..., None]

    def mist(self, y_mid: float, thick: float, colour: str, strength: float = 0.5, seed: int = 0) -> None:
        d = np.abs(YY - y_mid) / thick
        n = fbm2(XX / 14.0, YY / 3.0, seed=self.seed + 40 + seed, octaves=3)
        a = np.clip(1.0 - d, 0.0, 1.0) ** 1.4 * (0.45 + n) * strength
        self.tint(a * 1.6, colour, levels=3, strength=0.5)

    def glow(self, cx: float, cy: float, rx: float, ry: float, colour: str, strength: float = 0.8,
             levels: int = 4, power: float = 1.6) -> None:
        d = np.hypot((XX + 0.5 - cx) / rx, (YY + 0.5 - cy) / ry)
        self.tint(np.clip(1.0 - d, 0.0, 1.0) ** power * strength, colour, levels=levels, strength=0.75)

    def vignette(self, strength: float = 0.5, colour: str = INK) -> None:
        d = np.hypot((XX + 0.5 - SW / 2) / (SW * 0.62), (YY + 0.5 - SH / 2) / (SH * 0.78))
        self.tint(np.clip((d - 0.55) / 0.55, 0.0, 1.0) * strength * 1.8, colour, levels=4, strength=0.85)

    def shadow(self, cx: float, cy: float, rx: float, ry: float, strength: float = 0.7) -> None:
        d = np.hypot((XX + 0.5 - cx) / rx, (YY + 0.5 - cy) / ry)
        k = np.clip(1.0 - d, 0.0, 1.0)
        self.tint(np.minimum(k * 2.2, 1.0) * strength, INK, levels=3, strength=0.8)

    def pebbles(self, n: int, y0: int, y1: int, light: str, dark: str, seed: int = 0, x0: int = 0,
                x1: int = SW) -> None:
        """Little stones lying on the ground: a lit top and a dark foot, bigger toward the viewer."""
        rng = np.random.default_rng(self.seed * 7 + seed)
        self.palette.extend([light, dark])
        for _ in range(n):
            y = int(rng.integers(y0, y1))
            x = int(rng.integers(x0, x1))
            w = 1 + int((y - y0) / max(1, y1 - y0) * 2.5 + rng.random())
            self.pixels([(x + k, y) for k in range(w)], light)
            self.pixels([(x + k + 1, y + 1) for k in range(w)], dark)

    def tufts(self, n: int, y0: int, y1: int, colour: str, seed: int = 0, x0: int = 0, x1: int = SW) -> None:
        """Dead grass: three or five thin blades standing in a fan."""
        rng = np.random.default_rng(self.seed * 11 + seed)
        self.palette.append(colour)
        for _ in range(n):
            y = int(rng.integers(y0, y1))
            x = int(rng.integers(x0, x1))
            h = 2 + int((y - y0) / max(1, y1 - y0) * 3.0)
            pts = [(x, y), (x, y - 1)] + [(x - 1, y - k) for k in range(2, h)] + [(x + 1, y - k) for k in range(2, h - 1)]
            if h > 3:
                pts += [(x - 2, y - h + 1), (x + 2, y - h + 2), (x, y - h)]
            self.pixels(pts, colour)

    def motes(self, n: int, x0: int, x1: int, y0: int, y1: int, colour: str, seed: int = 0, halo: bool = True) -> None:
        """Specks of light drifting (spores, flakes of gold): single pixels, a few with a faint halo."""
        rng = np.random.default_rng(self.seed * 13 + seed)
        self.palette.append(colour)
        for k in range(n):
            x, y = int(rng.integers(x0, x1)), int(rng.integers(y0, y1))
            if 0 <= x < SW and 0 <= y < SH:
                self.img[y, x] = rgb(colour)
                if halo and k % 3 == 0:
                    self.glow(x + 0.5, y + 0.5, 3.0, 3.0, colour, strength=0.5, levels=2, power=1.0)

    def reflect(self, sprite: np.ndarray, cx: int, base_y: int, depth: int, strength: float = 0.55,
                tint: str = "#1d2a3a") -> None:
        """A sprite's mirror image in still water below `base_y` (rows alternate so the ripples cut
        it), darkened toward `tint`."""
        h, w = sprite.shape[:2]
        x0 = cx - w // 2
        for k in range(depth):
            src = h - 2 - k
            y = base_y + 1 + k
            if src < 0 or y >= SH or (k % 3 == 2):
                continue
            wob = int(round(math.sin(k * 1.3 + cx) * (0.5 + k / 14.0)))
            for xx in range(w):
                if sprite[src, xx, 3] > 0 and 0 <= x0 + xx + wob < SW:
                    base = sprite[src, xx, :3] / 255.0
                    fade = min(1.0, strength * (1.0 - k / (depth * 1.15)))
                    self.img[y, x0 + xx + wob] = self.img[y, x0 + xx + wob] * (1 - fade) + (
                        base * 0.55 + rgb(tint) * 0.45) * fade
        self.palette.append(tint)

    def wisp(self, x: float, y: float, length: int, colour: str, seed: int = 0, drift: float = 1.0,
             alpha: float = 0.8) -> None:
        """A curl of smoke or whisper rising from (x, y): a wavering line that thins out upward."""
        c = rgb(colour)
        self.palette.append(colour)
        for k in range(length):
            fade = (1.0 - k / length) * alpha
            if fade < 0.28:
                break
            xx = int(round(x + math.sin(k * 0.4 + seed) * 2.4 * drift + k * 0.15 * drift))
            yy = int(round(y - k))
            if 0 <= xx < SW and 0 <= yy < SH:
                self.img[yy, xx] = self.img[yy, xx] * (1.0 - fade) + c * fade

    def thick_line(self, x0: float, y0: float, x1: float, y1: float, w0: float, w1: float,
                   colour: np.ndarray) -> None:
        """A line of changing width (a limb that tapers): discs along the way."""
        n = int(max(abs(x1 - x0), abs(y1 - y0), 1) * 1.5)
        for i in range(n + 1):
            t = i / n
            cx, cy = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            r = (w0 + (w1 - w0) * t) / 2.0
            ys, xs = np.nonzero(np.hypot(XX + 0.5 - cx, YY + 0.5 - cy) <= max(r, 0.5))
            self.img[ys, xs] = colour

    def big_tree(self, x: float, base: float, height: float, width: float, colour: np.ndarray, seed: int,
                 lean: float = 0.0, limbs: int = 4) -> None:
        """A big bare tree: a tapering trunk with a few thick limbs that fork into twigs."""
        rng = np.random.default_rng(seed)
        top_x = x + lean * height
        self.thick_line(x, base, top_x, base - height, width, width * 0.35, colour)
        for k in range(limbs):
            t = 0.35 + 0.6 * k / max(limbs - 1, 1)
            px, py = x + (top_x - x) * t, base - height * t
            side = -1.0 if k % 2 == 0 else 1.0
            ln = height * (0.32 + 0.22 * rng.random())
            ex, ey = px + side * ln, py - ln * (0.25 + 0.5 * rng.random())
            self.thick_line(px, py, ex, ey, width * 0.4, 1.0, colour)
            for j in range(2):
                f = 0.5 + 0.4 * j
                fx, fy = px + (ex - px) * f, py + (ey - py) * f
                gx, gy = fx + side * ln * 0.35, fy - ln * (0.2 + 0.3 * rng.random())
                self.thick_line(fx, fy, gx, gy, 1.5, 1.0, colour)
                self.line(round(gx), round(gy), round(gx + side * 3), round(gy - 3 - 3 * rng.random()), colour)
        self.line(round(top_x), round(base - height), round(top_x + 2), round(base - height - 5), colour)

    def pixels(self, pts: list[tuple[int, int]], colour: str | np.ndarray) -> None:
        c = rgb(colour) if isinstance(colour, str) else colour
        if isinstance(colour, str):
            self.palette.append(colour)
        for x, y in pts:
            if 0 <= x < SW and 0 <= y < SH:
                self.img[y, x] = c

    def eyes(self, x: int, y: int, colour: str, gap: int = 3) -> None:
        """A pair of glowing eyes in the dark (two pixels with a faint halo)."""
        self.palette.append(colour)
        for dx in (0, gap):
            if 0 <= x + dx < SW and 0 <= y < SH:
                self.img[y, x + dx] = rgb(colour)
        self.glow(x + gap / 2.0 + 0.5, y + 0.5, gap + 2.5, 2.5, colour, strength=0.5, levels=2, power=1.0)

    def water(self, colors: list[str], y0: int, tone: float = 0.4, seed: int = 0,
              rip: float = 0.12) -> None:
        """Still dark water from y0 down: long flat ripples that stretch toward the horizon."""
        yy = np.clip(YY - y0 + 1.0, 1.0, None)
        n = fbm2(XX / (10.0 + yy * 1.5), yy * 1.7, seed=self.seed + 60 + seed, octaves=3)
        t = tone + (n - 0.5) * rip * 2.0 - 0.08 * np.clip((YY - y0) / (SH - y0), 0.0, 1.0)
        self.paint(YY >= y0, colors, t, d=0.25)

    def paste(self, sprite: np.ndarray, cx: int, base_y: int, flip: bool = False) -> None:
        """A rendered prop (RGBA, fully opaque or clear) with its feet at `base_y`, centred on cx."""
        if flip:
            sprite = sprite[:, ::-1]
        h, w = sprite.shape[:2]
        x0, y0 = cx - w // 2, base_y - (h - 2)
        for yy in range(h):
            for xx in range(w):
                if sprite[yy, xx, 3] > 0 and 0 <= x0 + xx < SW and 0 <= y0 + yy < SH:
                    self.img[y0 + yy, x0 + xx] = sprite[yy, xx, :3] / 255.0
                    self.pasted.add((x0 + xx, y0 + yy))
        for c in {tuple(int(v) for v in p) for p in sprite[sprite[..., 3] > 0][:, :3]}:
            self.palette.append("#%02x%02x%02x" % c)

    def rgba(self) -> np.ndarray:
        """The finished picture: every pixel snapped to the nearest colour the scene was made from."""
        pal = sorted(set(p.lower() for p in self.palette))
        lab = np.array([rgb_to_oklab(hex_to_rgb(c)) for c in pal])
        rgb8 = np.clip(np.round(self.img * 255.0), 0, 255) / 255.0
        flat = rgb8.reshape(-1, 3)
        uniq, inverse = np.unique(flat, axis=0, return_inverse=True)
        ul = np.array([rgb_to_oklab(tuple(u)) for u in uniq])
        d = ((ul[:, None, :] - lab[None, :, :]) ** 2).sum(-1)
        best = d.argmin(-1)
        cols = np.array([hex_to_rgb(pal[i]) for i in best])
        snapped = cols[inverse.reshape(-1)].reshape(SH, SW, 3)
        out = np.zeros((SH, SW, 4), dtype=np.uint8)
        out[..., :3] = np.round(snapped * 255.0)
        out[..., 3] = 255
        return out


def new_painter(seed: int) -> Painter:
    p = Painter(seed)
    p.pasted = set()
    return p


# --- Materials ----------------------------------------------------------------------------------

DEAD_GRASS = make_ramp("#625f3d", below=2, above=2, shadow_chroma=0.8)
MUD = make_ramp("#4b4331", below=2, above=2)
ROAD = lch_ramp([(0.27, 0.02, 60.0), (0.33, 0.026, 62.0), (0.395, 0.03, 66.0), (0.46, 0.03, 70.0),
                 (0.52, 0.03, 74.0)])
DIRT = lch_ramp([(0.25, 0.024, 50.0), (0.31, 0.03, 56.0), (0.37, 0.034, 60.0), (0.43, 0.034, 64.0),
                 (0.49, 0.03, 70.0)])
NIGHT = lch_ramp([(0.2, 0.03, 300.0), (0.26, 0.036, 296.0), (0.33, 0.04, 290.0), (0.4, 0.04, 282.0),
                  (0.47, 0.04, 270.0)])
DUSK = lch_ramp([(0.24, 0.035, 320.0), (0.31, 0.045, 335.0), (0.4, 0.05, 350.0), (0.5, 0.055, 20.0),
                 (0.6, 0.06, 55.0)])
OLIVE_SKY = lch_ramp([(0.23, 0.03, 150.0), (0.3, 0.04, 140.0), (0.38, 0.045, 128.0), (0.46, 0.05, 115.0),
                      (0.54, 0.05, 105.0)])
ASH_SKY = lch_ramp([(0.24, 0.015, 40.0), (0.31, 0.02, 40.0), (0.39, 0.026, 45.0), (0.47, 0.03, 52.0),
                    (0.55, 0.035, 60.0)])
SILHOUETTE = lch_ramp([(0.19, 0.02, 300.0), (0.23, 0.022, 300.0), (0.28, 0.026, 295.0), (0.33, 0.03, 290.0),
                       (0.38, 0.034, 285.0)])
VOID = lch_ramp([(0.17, 0.03, 305.0), (0.2, 0.04, 310.0), (0.24, 0.05, 315.0), (0.29, 0.05, 320.0)])
PURPLE_GLOW = "#9a6fd0"
CYAN_GLOW = "#5fd6d0"
AMBER_GLOW = "#e8a24a"
ROT_GLOW = "#a9d44f"
EMBER_GLOW = "#e0662c"

BONE = mat("ev_bone", "#cfc4a0", below=2, above=1, wrap=0.35)
WOOD = mat("ev_wood", "#5e4634", below=2, above=1, wrap=0.3)
WOOD_ROT = mat("ev_wood_rot", "#4a3b30", below=2, above=1, wrap=0.3)
GOLD = mat("ev_gold", "#c4a04a", below=2, above=1, spec=0.6, spec_power=8.0, wrap=0.3)
GOLD_DULL = mat("ev_gold_dull", "#8f7536", below=2, above=1, spec=0.4, spec_power=8.0, wrap=0.3)
RUST = mat("ev_rust", "#5a3528", below=2, above=0, wrap=0.3, outline=INK)
BLACK_GLASS = lch_mat("ev_glass", [(0.17, 0.03, 300.0), (0.21, 0.04, 300.0), (0.27, 0.05, 296.0),
                                   (0.34, 0.06, 285.0)], wrap=0.15, outline=INK)
CLOTH_BLACK = mat("ev_cloth_black", "#3b3446", below=1, above=2, wrap=0.45, outline=INK)
CLOTH_GREY = mat("ev_cloth_grey", "#6e6a66", below=2, above=1, wrap=0.45)
CLOTH_BROWN = mat("ev_cloth_brown", "#6a4a32", below=2, above=1, wrap=0.45)
STRAW = mat("ev_straw", "#a58b4c", below=2, above=1, wrap=0.45)
FLESH_ROT = mat("ev_flesh_rot", "#8a6f6a", below=2, above=1, wrap=0.4)
PETAL = mat("ev_petal", "#7a3f8f", below=2, above=2, wrap=0.4, shadow_chroma=0.95, outline="#2a1233")
PETAL_PALE = mat("ev_petal_pale", "#b08ac4", below=2, above=1, wrap=0.4, outline="#2a1233")
FRUIT = Material("ev_fruit", ["#6b2a55", "#9b3a72", "#d06a98", "#f0a8c2"], emissive=True, glow_index=1,
                 outline=ink_outline("#4a1a3c", 0.2))
SEAL_RED = mat("ev_wax", "#8f2c22", below=2, above=1, wrap=0.4, spec=0.4, spec_power=10.0, outline=INK)
WATER_GLINT = Material("ev_glint", M["glow_cyan"].colors, emissive=True, glow_index=2,
                       outline=ink_outline("#2f6f73", 0.22))
WATER_DARK = lch_mat("ev_water", [(0.16, 0.025, 250.0), (0.2, 0.03, 245.0), (0.25, 0.034, 240.0),
                                  (0.31, 0.036, 235.0)], wrap=0.1, outline=INK)
EMBER = Material("ev_ember", M["glow_ember"].colors, emissive=True, glow_index=2,
                 outline=ink_outline("#c26a2a", 0.25))
AMBER = Material("ev_amber", M["glow_amber"].colors, emissive=True, glow_index=2,
                 outline=ink_outline("#c26a2a", 0.25))
VIOLET = Material("ev_violet", M["glow_violet"].colors, emissive=True, glow_index=2,
                  outline=ink_outline("#5f4385", 0.25))
SAND_STONE = lch_mat("ev_pale_stone", [(0.3, 0.018, 300.0), (0.38, 0.016, 320.0), (0.46, 0.016, 70.0),
                                       (0.54, 0.018, 85.0), (0.62, 0.02, 85.0)], wrap=0.25, ao=0.3,
                     outline_L=0.17)
CAGE_IRON = mat("ev_cage", "#3d3f4a", below=2, above=1, spec=0.5, spec_power=10.0, wrap=0.2, outline=INK)
CREAM = mat("ev_cream", "#cdbd98", below=2, above=1, wrap=0.4)
TARP = mat("ev_tarp", "#5d6a48", below=2, above=1, wrap=0.45)
SOIL_FRESH = mat("ev_soil", "#4d3a2b", below=2, above=1, wrap=0.4)
MOSS = mat("ev_moss", "#56683a", below=2, above=1, wrap=0.5, shadow_chroma=0.75, shadow_shift=6.0)
ROT_STEM = mat("ev_rot_stem", "#4d3a52", below=2, above=1, wrap=0.4)
ROT_LEAF = mat("ev_rot_leaf", "#4f5a2e", below=2, above=1, wrap=0.45)
DOOR_IRON = mat("ev_door_iron", "#33343e", below=2, above=1, spec=0.5, spec_power=9.0, wrap=0.2, outline=INK)
KING_GOLD = mat("ev_king_gold", "#b8943f", below=2, above=1, spec=0.7, spec_power=9.0, wrap=0.3)
MASK_GOLD = mat("ev_mask_gold", "#b8923e", below=3, above=2, spec=0.9, spec_power=12.0, wrap=0.12)
MOSS_G = make_ramp("#3f4f2c", below=2, above=2, shadow_chroma=0.8)
MASK_GOLD_DARK = mat("ev_mask_dark", "#7a6130", below=1, above=0, wrap=0.3)
PETAL_DARK = mat("ev_petal_dark", "#4f2a66", below=2, above=1, wrap=0.4, outline="#240f2c")
SKIN_PALE = mat("ev_skin_pale", "#cdb59c", below=2, above=1, wrap=0.45, ao=0.5)
CHARRED = mat("ev_charred", "#2c2623", below=1, above=2, wrap=0.35, outline=INK)
ASHEN = mat("ev_ashen", "#8a8580", below=2, above=1, wrap=0.4)
BLOOD_DARK = mat("ev_blood", "#6e1f22", below=1, above=1, wrap=0.4, outline=INK)
BLOOD_RAMP = make_ramp("#7a1f22", below=2, above=1)
ROBE_PALE = mat("ev_robe_pale", "#a89a78", below=2, above=1, wrap=0.45)
HOLLOW_BARK = mat("ev_hollow_bark", "#4d4036", below=2, above=2, wrap=0.3)
LEATHER_D = mat("ev_leather_d", "#4e3a2c", below=2, above=1, wrap=0.35)
ASH_DARK = lch_ramp([(0.16, 0.02, 40.0), (0.2, 0.024, 40.0), (0.25, 0.028, 40.0), (0.3, 0.03, 45.0), (0.35, 0.03, 48.0)])
ASH_GROUND = lch_ramp([(0.24, 0.012, 50.0), (0.3, 0.014, 55.0), (0.37, 0.016, 60.0), (0.45, 0.018, 65.0), (0.52, 0.02, 70.0)])
PILGRIM_ROBE = mat("ev_pilgrim_robe", "#76664e", below=2, above=2, wrap=0.5)
HOOD_DARK = mat("ev_hood", "#4a3f36", below=2, above=1, wrap=0.45)
SASH = mat("ev_sash", "#b9a77c", below=1, above=1, wrap=0.45)
PETAL_LIGHT = mat("ev_petal_light", "#8e4fa6", below=2, above=1, wrap=0.4, outline="#2a1233")
WAGON_WOOD = mat("ev_wagon", "#80613f", below=2, above=2, wrap=0.3)
