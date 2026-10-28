"""The Relics' pictures (DESIGN.md 8.25 "Icons", 8.17 "The icons", phase 27).

One picture per Relic (the "Icon" column of the 8.25 table), drawn on a 24x24 grid and saved as
sprites/relics/<id>.png on a clear background. The game draws a picture over the whole inside of the
Relic's frame (scripts/relics/relic_icon.gd: a square of 1.68 frame radii, every picture pixel shown
the same size, its side snapped to whole screen pixels when near), whatever the picture's size in
pixels. So every object is a
chunky silhouette first (parts at least 2 px thick, 3 to 5 colour areas), lit from the upper left,
with the kit's ink outline.

Each drawing is fitted to its frame (fit): put on the smallest square canvas (at least its own size
plus a clear 1-pixel border) whose frame safe area holds every pixel of it (kit.relic_frame.safe_mask:
the spearhead narrows to its tip, the shield to its point, the seal is round), moved by whole pixels
to where it fits. The smaller the canvas, the bigger the object shows, so each object fills as much of
its own frame as its shape allows; its pixels are never redrawn or resized here. check.py enforces
the safe area.

Drawn in 2D from simple masks (ellipses, polygons, brushed curves). A part is shaded from its own
shape: a height field from the distance to its edge gives a normal, lit by the kit's light, mapped
onto the part's ramp ("round"), or a flat fill with a lit top-left rim and a dark bottom-right rim
("flat"), or a glow brightest at its core ("glow"). A part drawn over another leaves a dark contour
on what lies under it. Deterministic: no randomness at all.

Previews: preview/relic_icons/ holds each picture zoomed, a labelled contact sheet of all of them,
and in_frames_*.png: every picture in its frame (kind shape, rarity edge, rot drip) at the sizes the
game shows (kit.relic_frame.PREVIEW_SIDES, 26 to 168 px), drawn like relic_icon.gd draws it.
"""
from __future__ import annotations

import math
import os
from typing import Callable, Sequence

import numpy as np
from PIL import Image, ImageDraw

from kit.canvas import rgba8
from kit.color import ramp
from kit.context import PREVIEW
from kit.palette import INK, M
from kit.relic_frame import PICTURE, PREVIEW_SIDES, compose, safe_mask

N = PICTURE
_YY, _XX = np.mgrid[0:N, 0:N].astype(float) + 0.5
# The kit's light: from the upper left and a little in front (x right, y down, z to the viewer).
_LIGHT = np.array([-0.55, -0.7, 0.6]) / np.linalg.norm([-0.55, -0.7, 0.6])

# --- Colours: shared materials first (kit/palette.py), a few of the Relics' own ---------------
WOOD = M["wood"].colors
DWOOD = M["wood_dark"].colors
DEAD = M["dead_wood"].colors
BONE = M["bone"].colors
IRON = M["iron"].colors
STEEL = M["steel"].colors
GLASS = M["blade"].colors
GOLD = M["gold"].colors
GOLDW = M["gold_worn"].colors
LEATHER = M["leather"].colors
LEATHERD = M["leather_dark"].colors
CANVAS = M["canvas"].colors
CREAM = M["cloth_cream"].colors
CHAR = M["cloth_charcoal"].colors
RED = M["cloth_red"].colors
STONE = M["stone"].colors
STONEW = M["stone_warm"].colors
MOSS = M["moss"].colors
GRASS = M["grass"].colors
ROTP = M["rot_purple"].colors
ASH = M["ash"].colors
DIRT = M["dirt"].colors
EMBER = M["glow_ember"].colors
AMBER = M["glow_amber"].colors
GROT = M["glow_rot"].colors
VIOLET = M["glow_violet"].colors
CYAN = M["glow_cyan"].colors
EYE = M["eye_white"].colors
PALE = M["bloat_pale"].colors
RUST = ramp("#8f4f2c")
BLOOD = ramp("#9c2431", step_l=0.09)
ICHOR = ramp("#3a2f48", step_l=0.075)
FEATHER = ramp("#3f3c55", step_l=0.085, grey_hue=275.0)
WAX = ramp("#ddcfa4", step_l=0.07)
MILK = ramp("#e2dbc4", step_l=0.06)
BRASS = ramp("#b38b3c")
WATER = ramp("#4c7f98", step_l=0.09)
FUR = ramp("#c2652e")
HIDE = ramp("#94704a")
MOTH = ramp("#9c917f", step_l=0.08)
THORN = ramp("#5b4248", step_l=0.08)
ROOT = ramp("#5f4a4c", step_l=0.085)
MANTLE = ramp("#3d3457", step_l=0.08)
LEECH = ramp("#5a3550", step_l=0.08)
PETAL = ramp("#d6dbea", step_l=0.06)
CLAY = ramp("#9a5e45")
JUG = ramp("#a88560")
HOOD = ramp("#463f56", step_l=0.085)
VEIL = ramp("#a9a3ad", step_l=0.075)
WOOL = ramp("#b8343a")


# --- Masks ------------------------------------------------------------------------------------
def ell(cx: float, cy: float, rx: float, ry: float, rot: float = 0.0) -> np.ndarray:
    """A filled ellipse (centre and radii in pixels, `rot` degrees clockwise)."""
    a = math.radians(rot)
    dx, dy = _XX - cx, _YY - cy
    u = (dx * math.cos(a) + dy * math.sin(a)) / rx
    v = (-dx * math.sin(a) + dy * math.cos(a)) / ry
    return u * u + v * v <= 1.0


def ring(cx: float, cy: float, rx: float, ry: float, t: float, rot: float = 0.0) -> np.ndarray:
    return ell(cx, cy, rx, ry, rot) & ~ell(cx, cy, rx - t, ry - t, rot)


def poly(*pts: tuple[float, float]) -> np.ndarray:
    """A filled polygon (pixel centres inside)."""
    inside = np.zeros((N, N), dtype=bool)
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        cross = (yi > _YY) != (yj > _YY)
        with np.errstate(divide="ignore", invalid="ignore"):
            at = (xj - xi) * (_YY - yi) / (yj - yi + 1e-12) + xi
        inside ^= cross & (_XX < at)
        j = i
    return inside


def rect(x0: int, y0: int, x1: int, y1: int) -> np.ndarray:
    """Pixels x0..x1, y0..y1 (inclusive)."""
    m = np.zeros((N, N), dtype=bool)
    m[max(0, y0):min(N, y1 + 1), max(0, x0):min(N, x1 + 1)] = True
    return m


def brush(pts: Sequence[tuple[float, float]], r0: float, r1: float | None = None) -> np.ndarray:
    """A stroke along a polyline, its radius going from r0 to r1 along its length (a tapered limb,
    a horn, a feather, a whip)."""
    r1 = r0 if r1 is None else r1
    lengths = [math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
    total = sum(lengths) or 1.0
    m = np.zeros((N, N), dtype=bool)
    run = 0.0
    for (a, b), seg in zip(zip(pts, pts[1:]), lengths):
        steps = max(1, int(seg * 4))
        for k in range(steps + 1):
            t = k / steps
            x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            r = r0 + (r1 - r0) * (run + seg * t) / total
            m |= (_XX - x) ** 2 + (_YY - y) ** 2 <= r * r
        run += seg
    return m


def line_mask(x0: int, y0: int, x1: int, y1: int) -> np.ndarray:
    """A 1-pixel Bresenham line."""
    m = np.zeros((N, N), dtype=bool)
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        if 0 <= x0 < N and 0 <= y0 < N:
            m[y0, x0] = True
        if x0 == x1 and y0 == y1:
            return m
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def _shift(m: np.ndarray, dx: int, dy: int) -> np.ndarray:
    """m moved by (dx, dy); what slides in from outside is False."""
    out = np.zeros_like(m)
    ys = slice(max(0, -dy), N - max(0, dy))
    yd = slice(max(0, dy), N - max(0, -dy))
    xs = slice(max(0, -dx), N - max(0, dx))
    xd = slice(max(0, dx), N - max(0, -dx))
    out[yd, xd] = m[ys, xs]
    return out


def grow(m: np.ndarray) -> np.ndarray:
    """m plus its 4 neighbours."""
    return m | _shift(m, 1, 0) | _shift(m, -1, 0) | _shift(m, 0, 1) | _shift(m, 0, -1)


def _depth(m: np.ndarray) -> np.ndarray:
    """Steps (4-neighbour) from each pixel of m to the nearest pixel outside it."""
    d = np.zeros((N, N))
    cur = m.copy()
    k = 0
    while cur.any():
        k += 1
        d[cur] = k
        cur = cur & _shift(cur, 1, 0) & _shift(cur, -1, 0) & _shift(cur, 0, 1) & _shift(cur, 0, -1)
    return d


# --- The painter ------------------------------------------------------------------------------
class Pic:
    """A picture built from parts, back to front; finish() outlines it."""

    def __init__(self) -> None:
        self.a = np.zeros((N, N, 4), dtype=np.uint8)
        self.dark = np.empty((N, N), dtype=object)  # each painted pixel's contour colour

    def solid(self) -> np.ndarray:
        return self.a[..., 3] > 0

    def part(self, m: np.ndarray, cols: Sequence[str], mode: str = "round", lo: float = 0.3,
             hi: float = 3.4, cap: float = 3.0, spec: bool = True, sep: bool = True, base: int = 2) -> np.ndarray:
        """Paints mask `m` in ramp `cols` (darkest first). round: lit like a rounded body; flat:
        base colour, lit top-left rim, dark bottom-right rim; glow: brightest at its core.
        sep: a dark contour on whatever lies under it, so parts read apart."""
        m = m.copy()
        if not m.any():
            return m
        top = len(cols) - 1
        if sep:
            under = grow(m) & ~m & self.solid()
            for y, x in zip(*np.nonzero(under)):
                c = self.dark[y, x]
                if c:
                    self.a[y, x] = rgba8(c)
        if mode == "round":
            h = np.sqrt(np.minimum(_depth(m), cap) / cap)
            gy, gx = np.gradient(h)
            n = np.dstack([-gx * 3.0, -gy * 3.0, np.ones((N, N))])
            n /= np.linalg.norm(n, axis=2, keepdims=True)
            lam = n @ _LIGHT
            t = np.clip(lam / 0.95, 0.0, 1.0)
            idx = np.rint(lo + (hi - lo) * t)
            if spec:
                idx[lam > 0.9] = top
        elif mode == "flat":
            idx = np.full((N, N), float(base))
            idx[m & ~(_shift(m, 1, 0) & _shift(m, 0, 1))] = base + 1
            idx[m & ~(_shift(m, -1, 0) & _shift(m, 0, -1))] = base - 1
        elif mode == "glow":
            d = _depth(m)
            idx = np.minimum(d, top + 1) - 1 + (base - 2)
        else:
            raise ValueError(mode)
        idx = np.clip(idx, 0, top).astype(int)
        for y, x in zip(*np.nonzero(m)):
            self.a[y, x] = rgba8(cols[idx[y, x]])
            self.dark[y, x] = cols[0]
        return m

    def paint(self, m: np.ndarray, color: str, dark: str | None = None) -> None:
        """Flat colour on mask `m` (details: holes, stripes, glints)."""
        for y, x in zip(*np.nonzero(m)):
            self.a[y, x] = rgba8(color)
            self.dark[y, x] = dark or self.dark[y, x] or color

    def px(self, pts: Sequence[tuple[int, int]], color: str) -> None:
        for x, y in pts:
            if 0 <= x < N and 0 <= y < N:
                self.a[y, x] = rgba8(color)
                if not self.dark[y, x]:
                    self.dark[y, x] = color

    def line(self, x0: int, y0: int, x1: int, y1: int, color: str) -> None:
        self.paint(line_mask(x0, y0, x1, y1), color)

    def cut(self, m: np.ndarray) -> None:
        """Clears mask `m` (a hole, a tear)."""
        self.a[m] = 0
        self.dark[m] = None

    def finish(self) -> np.ndarray:
        """The ink outline round the whole silhouette."""
        s = self.solid()
        out = grow(s) & ~s
        self.a[out] = rgba8(INK)
        return self.a


# --- The Relics: attack (spearhead frame) -------------------------------------------------------
def bitter_root(p: Pic) -> None:
    """A twisted black root: a gnarled taproot twisting down, rootlets reaching out."""
    cols = ROOT
    for pts in (((11, 10), (7, 9), (5, 11)), ((13, 12), (17, 12), (19, 15)), ((11, 15), (7, 17), (6, 20)),
                ((12, 18), (15, 20), (16, 21.5))):
        p.part(brush(pts, 1.1, 0.6), cols, mode="flat", base=2)
    p.part(brush([(12, 5), (13, 9.5), (11, 14), (12, 18), (11, 21.5)], 2.9, 0.7), cols, lo=0.6, hi=4)
    for y in (6, 9, 12, 15):
        p.line(10, y + 1, 14, y - 1, cols[1])
    p.px([(11, 4), (13, 4)], cols[4])


def black_ichor(p: Pic) -> None:
    """A round vial of black ichor, stoppered, a black drop running down its side."""
    p.part(ell(12, 14.5, 6.6, 6.6), GLASS, mode="flat", base=3)
    p.part(rect(10, 4, 13, 8), GLASS, mode="flat", base=3)
    p.part(rect(10, 2, 13, 4), WOOD, mode="flat")
    p.paint(ell(12, 15.5, 5.2, 5.0) & (_YY > 11), ICHOR[1])
    p.paint(ell(12, 11.8, 4.2, 1.0), ICHOR[3])
    p.paint(ell(13, 18, 2.4, 1.2), ICHOR[0])
    p.px([(8, 12), (8, 13), (9, 11)], GLASS[4])
    p.part(brush([(14, 6), (15, 7), (16.5, 8.5)], 0.7) | ell(17, 10, 1.4, 1.8), ICHOR, mode="flat", sep=False)
    p.px([(10, 15)], VIOLET[1])


def bloodletters_fang(p: Pic) -> None:
    """A long curved fang, blood dripping from its point."""
    p.part(brush([(13, 5.2), (15.6, 9), (15, 13.5), (11, 17), (8, 18.5)], 2.9, 0.6), BONE, lo=0.8, hi=4)
    p.paint(ell(13.2, 5.2, 3.0, 2.0) & brush([(13, 5.2), (15.6, 9)], 2.9), BONE[1])
    p.paint(brush([(12, 16), (9, 18), (8, 18.5)], 1.0), BLOOD[2])
    p.part(ell(8, 21, 1.4, 1.4), BLOOD, mode="flat", sep=False)


def bone_whistle(p: Pic) -> None:
    """A short bone whistle with a window and two finger holes, on a leather loop."""
    p.part(brush([(13, 2.5), (11, 4), (9, 7)], 0.6), LEATHERD, sep=False)
    p.part(brush([(13, 2.5), (15, 5), (14, 7)], 0.6), LEATHERD, sep=False)
    p.part(brush([(14, 7), (9, 19)], 2.8), BONE, lo=0.8, hi=4)
    p.part(ell(14.3, 7, 3.0, 2.0, -68), BONE, mode="flat")
    p.paint(rect(11, 9, 12, 10), INK)
    for x, y in ((11, 13), (10, 16)):
        p.paint(rect(x, y, x, y), BONE[0])
    p.paint(ell(8.8, 19.6, 2.0, 1.4, -68), BONE[1])


def bramble_coat(p: Pic) -> None:
    """A long coat wound with thorny brambles: collar, hanging sleeves, a flared hem."""
    p.part(poly((9, 5), (15, 5), (17.5, 8), (18.5, 21), (5.5, 21), (6.5, 8)), LEATHER, lo=0.6, hi=3.6)
    p.part(brush([(7.5, 8), (5, 14), (4.6, 18)], 1.7), LEATHER, lo=0.6, hi=3.6)
    p.part(brush([(16.5, 8), (19, 14), (19.4, 18)], 1.7), LEATHER, lo=0.4, hi=3.2)
    p.paint(poly((10, 5), (14, 5), (12, 11)), INK)
    p.line(12, 11, 12, 20, LEATHER[0])
    vine = (line_mask(5, 12, 9, 15) | line_mask(9, 15, 15, 12) | line_mask(15, 12, 19, 15)
            | line_mask(6, 18, 11, 20) | line_mask(11, 20, 17, 17))
    p.paint(vine, MOSS[1])
    p.px([(7, 13), (12, 13), (17, 13), (9, 19), (14, 18)], MOSS[3])
    p.px([(4, 11), (20, 15), (8, 15), (16, 12), (12, 15), (6, 21), (17, 21)], BONE[3])


def breakers_maul(p: Pic) -> None:
    """A heavy cracked stone maul on a short wooden haft."""
    p.part(brush([(12, 11), (12, 20.5)], 1.5), WOOD)
    p.paint(rect(11, 15, 13, 15) | rect(11, 18, 13, 18), LEATHER[1])
    p.part(poly((8, 5), (16, 5), (17, 7), (17, 11), (16, 12), (8, 12), (7, 11), (7, 7)), STONE, lo=0.5, hi=4,
           cap=2.5)
    p.line(10, 5, 12, 8, STONE[0])
    p.line(12, 8, 11, 10, STONE[0])
    p.line(11, 10, 13, 12, STONE[0])
    p.px([(13, 8), (12, 10)], STONE[4])


def brimming_cup(p: Pic) -> None:
    """A metal goblet filled to the brim with dark wine, a drop running over its lip."""
    p.part(rect(11, 15, 12, 19), BRASS)
    p.part(ell(12, 20.5, 5, 1.6), BRASS, mode="flat")
    p.part(poly((5.5, 7), (18.5, 7), (17, 12), (14, 15), (10, 15), (7, 12)), BRASS, lo=0.5, hi=4)
    p.part(ell(12, 7.2, 6.3, 1.9), BLOOD, mode="flat", base=2)
    p.px([(9, 7), (10, 6)], BLOOD[4])
    p.part(brush([(16.5, 8), (16.8, 11)], 0.7), BLOOD, mode="flat", sep=False)
    p.paint(rect(8, 10, 8, 11), BRASS[4])


def butchers_edge(p: Pic) -> None:
    """A butcher's cleaver: a broad square blade, a hanging hole, the haft out to the side."""
    p.part(rect(15, 11, 20, 13), WOOD)
    p.px([(17, 12), (19, 12)], GOLDW[3])
    blade = poly((4.5, 9), (15.5, 9), (15.5, 19.5), (13, 21), (4.5, 20))
    p.part(blade, STEEL, mode="flat", base=2)
    p.paint(blade & (_YY > 18.5), GLASS[4])
    p.paint(rect(5, 9, 15, 9), STEEL[1])
    p.paint(rect(5, 10, 14, 10), STEEL[3])
    p.paint(rect(7, 12, 8, 13), STEEL[0])
    p.px([(8, 13)], STEEL[1])


def ember_stone(p: Pic) -> None:
    """A rough stone glowing through the cracks in its dark crust."""
    m = poly((9, 4.5), (15, 5), (19, 9), (19.5, 15), (15, 20), (8, 20.5), (4.5, 15), (5, 9))
    p.part(m, ramp("#5a4440", step_l=0.08), lo=0.2, hi=3.2)
    seeds = [(8.5, 8.5), (15, 8.5), (12, 13), (7.5, 16), (16, 16)]
    d = np.sort(np.stack([np.hypot(_XX - x, _YY - y) for x, y in seeds]), axis=0)
    crack = m & ~grow(~m) & (d[1] - d[0] < 1.0)
    p.paint(crack, EMBER[2])
    p.paint(crack & ell(12, 12.5, 4.5, 4.5), AMBER[3])
    p.paint(ell(12, 12.5, 1.2, 1.2) & m, AMBER[3])
    p.px([(6, 18), (9, 20), (17, 18)], EMBER[1])


def first_light(p: Pic) -> None:
    """A tall slim candle on a brass dish, its flame bright as dawn."""
    p.part(ell(12, 19.5, 6.0, 1.8), BRASS, mode="flat")
    p.part(rect(10, 10, 13, 18), WAX, lo=1.0, hi=4)
    p.paint(rect(10, 10, 13, 10), WAX[4])
    p.part(brush([(12, 3.2), (12, 7.5)], 0.6, 2.0), AMBER, mode="glow")
    p.paint(ell(12, 7.5, 0.9, 1.4), AMBER[3])
    p.px([(12, 9)], INK)
    p.px([(8, 7), (16, 7), (9, 4), (15, 4)], GOLD[4])


def gravebound_ring(p: Pic) -> None:
    """A heavy iron ring round a finger bone."""
    p.part(ring(12, 12, 6.6, 3.0, 2.2) & (_YY < 12), IRON, mode="flat", base=2)
    p.part(brush([(12, 4), (12, 20.5)], 1.8), BONE, lo=0.8, hi=4)
    p.part(ell(12, 7.5, 2.6, 1.5) | ell(12, 16.5, 2.6, 1.5) | ell(12, 4, 2.2, 1.5), BONE, sep=False)
    p.part(ring(12, 12, 6.6, 3.0, 2.2) & (_YY >= 12), IRON, mode="flat", base=2)
    p.px([(7, 12), (8, 14)], IRON[4])
    p.px([(16, 14)], VIOLET[1])


def last_ember(p: Pic) -> None:
    """Iron tongs gripping a small dying coal."""
    p.part(brush([(7, 21.5), (11.5, 13), (9.5, 9), (10, 6.5)], 0.9), IRON, mode="flat", base=2)
    p.part(brush([(17, 21.5), (12.5, 13), (14.5, 9), (14, 6.5)], 0.9), IRON, mode="flat", base=2)
    p.part(ell(12, 13, 1.4, 1.4), IRON, mode="flat", base=3)
    p.part(ell(12, 5.5, 3.2, 2.6), ramp("#3d3033"), lo=0.3, hi=2.6, spec=False)
    p.px([(11, 5), (12, 6), (13, 6), (13, 4)], EMBER[2])
    p.px([(12, 5)], AMBER[3])


def pale_tithe(p: Pic) -> None:
    """A wide, bleached offering bowl on a low foot, a coin in it."""
    p.part(ell(12, 19.5, 3.5, 1.5), BONE, mode="flat")
    p.part(ell(12, 12, 8.5, 6.5) & (_YY >= 11), BONE, lo=0.6, hi=4)
    p.part(ell(12, 11.5, 8.5, 2.6), BONE, mode="flat", base=3)
    p.paint(ell(12, 11.8, 6.6, 1.6), BONE[1])
    p.paint(ell(13.5, 11.8, 1.6, 1.0), GOLD[3])
    p.px([(6, 14), (7, 15)], ROTP[2])


def plague_lancet(p: Pic) -> None:
    """A rusty lancet: a slim leaf-shaped blade on a long handle, held tip up."""
    p.part(brush([(8, 21), (11, 13)], 1.3), DWOOD)
    p.part(ell(11.2, 12.4, 2.6, 1.0, -70), IRON, mode="flat")
    p.part(poly((11, 11.5), (11.2, 7), (13.5, 2.5), (14, 7), (12.6, 11.8)), STEEL, mode="flat", base=2)
    p.px([(12, 6), (12, 8), (13, 5)], RUST[2])
    p.px([(12, 9), (13, 7)], RUST[1])


def rot_hunter(p: Pic) -> None:
    """A broad barbed arrowhead on a broken shaft, stained with rot."""
    p.part(brush([(12, 14), (12, 21)], 1.2), WOOD)
    p.part(rect(11, 14, 13, 15), LEATHERD, mode="flat")
    p.part(poly((12, 2.5), (18.5, 15.5), (12, 12.5), (5.5, 15.5)), IRON, mode="flat", base=2)
    p.line(12, 3, 12, 12, IRON[4])
    p.px([(9, 11), (10, 12), (15, 10), (14, 9), (13, 13)], GROT[1])
    p.px([(10, 11), (15, 11)], GROT[2])


def moth_wing(p: Pic) -> None:
    """A dusty grey moth, wings spread: two eye spots, feathery feelers."""
    for s in (-1, 1):
        fore = poly((12, 10), (12 + s * 6.5, 8.5), (12 + s * 8.5, 12.5), (12 + s * 2, 14.5))
        hind = ell(12 + s * 4, 16, 3.4, 3.0, s * 25)
        p.part(hind, MOTH, mode="flat", base=1)
        p.part(fore, MOTH, lo=0.8, hi=3.6)
        p.paint(ell(12 + s * 5, 11.5, 1.2, 1.2), LEATHERD[1])
        p.px([(round(12 + s * 5 - 0.5), 11)], CREAM[3])
    p.part(brush([(12, 8), (12, 18.5)], 1.2, 0.8), LEATHERD, lo=0.8, hi=4)
    p.part(brush([(12, 8), (10, 5)], 0.5) | brush([(12, 8), (14, 5)], 0.5), LEATHERD, mode="flat", base=3,
           sep=False)


def grudge_stone(p: Pic) -> None:
    """A flat river stone scratched with a crossed-out tally."""
    p.part(ell(12, 14, 8.2, 6.4), STONE, lo=0.6, hi=4)
    for x in (8, 10, 12, 14):
        p.line(x, 11, x, 16, STONE[0])
    p.line(7, 16, 15, 11, BONE[3])
    p.line(17, 12, 17, 16, STONE[0])


def grave_tag(p: Pic) -> None:
    """A paper toe tag on a looped string."""
    p.part(brush([(12, 3), (9.5, 6), (12, 10)], 0.6) | brush([(12, 3), (14.5, 6), (12, 10)], 0.6), CREAM,
           mode="flat", base=1, sep=False)
    p.part(poly((9, 9), (15, 9), (17.5, 11.5), (17.5, 21), (6.5, 21), (6.5, 11.5)), CANVAS, mode="flat", base=3)
    p.part(ell(12, 11.5, 1.6, 1.6), CANVAS, mode="flat", base=1)
    p.paint(ell(12, 11.5, 0.7, 0.7), INK)
    p.line(8, 15, 16, 15, CANVAS[1])
    p.line(8, 17, 14, 17, CANVAS[1])
    p.line(8, 19, 15, 19, CANVAS[1])


def knotted_lash(p: Pic) -> None:
    """A knotted leather lash curling up from its wrapped handle."""
    p.part(brush([(10, 14), (12, 9), (14, 6.5), (16.5, 8), (17, 11.5), (15.5, 14), (16, 17)], 1.1, 0.6), LEATHER)
    for x, y in ((11.6, 10.5), (14.3, 6.6), (16.9, 10.5), (15.6, 15.2)):
        p.part(ell(x, y, 1.6, 1.6), LEATHER, sep=False)
    p.part(brush([(5.5, 20.3), (10, 14)], 1.7), LEATHERD)
    p.line(6, 18, 8, 19, LEATHER[3])
    p.line(7, 16, 9, 17, LEATHER[3])


def kingsbane_nail(p: Pic) -> None:
    """A long rusted coffin nail, square head up, point down."""
    p.part(poly((10, 6), (14, 6), (13.6, 15), (12.6, 21.5), (11.4, 21.5), (10.4, 15)), RUST, lo=0.6, hi=4)
    p.part(rect(8, 3, 15, 5), IRON, mode="flat", base=2)
    p.px([(11, 9), (12, 12), (11, 16), (12, 18)], RUST[0])
    p.px([(13, 10), (10, 3)], GOLD[3])


def lone_lantern(p: Pic) -> None:
    """An iron lantern with one small flame behind its panes."""
    p.part(ring(12, 4, 2.4, 2.4, 1.2), IRON, mode="flat", base=2)
    p.part(poly((9, 6), (15, 6), (17, 9), (7, 9)), IRON, mode="flat", base=2)
    p.part(rect(7, 9, 16, 18), ICHOR, mode="flat", base=1)
    p.paint(rect(8, 10, 15, 17), ramp("#4a3a30")[2])
    p.part(brush([(12, 11.2), (12, 14.5)], 0.5, 1.5), AMBER, mode="glow", sep=False)
    p.paint(rect(11, 15, 13, 16), AMBER[1])
    for x in (7, 11, 12, 16):
        p.paint(rect(x, 9, x, 18), IRON[2] if x in (7, 16) else IRON[1])
    p.paint(rect(11, 11, 12, 14) & ~ell(12, 13, 1.5, 2.0), ramp("#4a3a30")[2])
    p.part(brush([(12, 11.2), (12, 14.5)], 0.5, 1.5), AMBER, mode="glow", sep=False)
    p.part(rect(6, 18, 17, 20), IRON, mode="flat", base=2)


def hunters_horn(p: Pic) -> None:
    """A curved hunting horn with a leather band and a brass mouthpiece."""
    p.part(brush([(11, 4), (9, 9), (10, 14), (14, 17.5), (18, 18)], 1.0, 3.6), BONE, lo=0.8, hi=4)
    p.part(ell(18.3, 17.8, 1.7, 3.6, 10), BONE, mode="flat", base=1)
    p.paint(ell(18.6, 17.8, 0.9, 2.4, 10), INK)
    p.paint(brush([(9.4, 11.5), (11.4, 11)], 1.0) & brush([(11, 4), (9, 9), (10, 14)], 2.4), LEATHERD[2])
    p.part(ell(11.2, 3.4, 1.4, 1.2), BRASS, mode="flat")


def hounds_tooth(p: Pic) -> None:
    """A hound's long tooth hanging from a cord."""
    p.part(brush([(12, 2.5), (8.5, 6.5), (11, 9)], 0.6) | brush([(12, 2.5), (15.5, 6.5), (13, 9)], 0.6), LEATHER,
           mode="flat", base=2, sep=False)
    p.part(ell(12, 9.5, 2.0, 1.4), GOLDW, mode="flat")
    p.part(brush([(12, 11), (12.5, 15), (11.5, 18.5), (10, 21)], 3.2, 0.5), BONE, lo=0.9, hi=4)
    p.paint(rect(10, 11, 14, 12) & brush([(12, 11), (12.5, 15)], 3.2), BONE[1])


def headsmans_hood(p: Pic) -> None:
    """A black pointed headsman's hood with two eye holes."""
    p.part(poly((12, 2.5), (16, 9), (18.5, 16), (20, 21), (4, 21), (5.5, 16), (8, 9)), HOOD, lo=0.6, hi=4)
    p.paint(ell(9.6, 12.5, 1.6, 1.1) | ell(14.4, 12.5, 1.6, 1.1), INK)
    p.px([(9, 12), (14, 12)], RED[1])
    p.line(8, 18, 6, 21, HOOD[0])
    p.line(16, 18, 18, 21, HOOD[0])


def gravediggers_spade(p: Pic) -> None:
    """A grave-digger's spade: T grip, long haft, a blade caked in grave dirt."""
    p.part(rect(9, 3, 14, 4), WOOD, mode="flat")
    p.part(rect(11, 4, 12, 12), WOOD)
    p.part(poly((7, 12), (17, 12), (17, 18), (12, 21.5), (7, 18)), IRON, mode="flat", base=2)
    p.paint(rect(8, 13, 16, 13), IRON[4])
    p.part(poly((7, 17), (9, 16), (11, 18), (14, 16.5), (17, 17.5), (12, 21.5)), DIRT, mode="flat", base=2,
           sep=False)
    p.px([(10, 19), (14, 18)], DIRT[4])


# --- Defence (heater shield frame) --------------------------------------------------------------
def shriving_bell(p: Pic) -> None:
    """A small brass hand bell on a wooden handle, its clapper below."""
    p.part(ell(12, 3.5, 1.8, 1.8) | rect(11, 4, 12, 8), WOOD)
    p.part(poly((9, 8), (15, 8), (16.5, 12), (18.5, 17), (5.5, 17), (7.5, 12)), BRASS, lo=0.5, hi=4)
    p.part(ell(12, 17, 7.5, 1.8), BRASS, mode="flat", base=2)
    p.part(ell(12, 19.5, 1.6, 1.6), IRON)


def crown_of_thorns(p: Pic) -> None:
    """A circlet of black thorny branches, thorns pointing out."""
    back = ring(12, 12, 9, 4.5, 2.5) & (_YY < 12)
    front = ring(12, 12, 9, 4.5, 2.5) & (_YY >= 12)
    spikes = np.zeros((N, N), dtype=bool)
    for x0, y0, x1, y1 in ((6, 9, 4, 5), (12, 7, 12, 3), (18, 9, 20, 5), (9, 8, 8, 5), (15, 8, 16, 5),
                           (5, 15, 3, 18), (19, 15, 21, 18), (12, 17, 12, 20), (8, 16, 7, 19), (16, 16, 17, 19)):
        spikes |= line_mask(x0, y0, x1, y1)
    p.part(spikes, THORN, mode="flat", base=3, sep=False)
    p.part(back, THORN, mode="flat", base=2)
    p.part(front, THORN, lo=0.8, hi=4)
    p.px([(4, 5), (12, 3), (20, 5), (8, 5), (16, 5), (3, 18), (21, 18), (12, 20)], BONE[3])
    p.px([(10, 15), (15, 14)], BLOOD[3])


def leech_hook(p: Pic) -> None:
    """A fish hook with a fat leech clinging to its shank."""
    p.part(ring(12, 3.5, 1.9, 1.9, 1.0), IRON, mode="flat", base=3)
    p.part(brush([(12, 5), (12, 17), (13, 20), (16, 20.5), (18, 18), (18, 14)], 1.1), STEEL, mode="flat", base=3)
    p.part(poly((18, 12.5), (20.5, 16), (18, 15.5)), STEEL, mode="flat", base=3, sep=False)
    leech = ell(11.5, 11.5, 2.9, 6.3, -25)
    p.part(leech, LEECH, lo=0.6, hi=4)
    for k in range(-2, 3):
        y = 11.5 + k * 2.3
        x = 11.5 - k * 2.3 * math.tan(math.radians(25))
        p.paint(line_mask(round(x - 3), round(y + 1), round(x + 3), round(y - 1)) & leech & ~grow(~leech), LEECH[1])
    p.paint(ell(14, 6.4, 1.0, 1.0), BLOOD[2])


def heartleaf(p: Pic) -> None:
    """A heart-shaped green leaf, point down, with its veins and stem."""
    m = ell(8.5, 9.5, 5.0, 5.0) | ell(15.5, 9.5, 5.0, 5.0) | poly((4, 11), (20, 11), (12, 21))
    p.part(m, GRASS, lo=0.6, hi=4)
    p.line(12, 6, 12, 19, GRASS[0])
    for x0, y0, x1, y1 in ((12, 10, 8, 8), (12, 10, 16, 8), (12, 14, 8, 12), (12, 14, 16, 12)):
        p.line(x0, y0, x1, y1, GRASS[1])
    p.part(brush([(12, 6), (13, 3)], 0.8), WOOD, sep=False)


def hollow_mantle(p: Pic) -> None:
    """An empty hooded cloak: a round hood over darkness, the cloak falling in folds."""
    p.part(poly((7, 8), (17, 8), (19.5, 20), (16, 21), (12, 20), (8, 21), (4.5, 20)), MANTLE, lo=0.6, hi=4)
    p.part(ell(12, 8.5, 6.5, 6.2), MANTLE, lo=0.8, hi=4)
    p.paint(ell(12, 9.5, 3.6, 4.0), INK)
    p.paint(ell(12, 10.5, 2.2, 2.6), ramp("#100a14")[2])
    for x0, x1 in ((8, 7), (12, 12), (16, 17)):
        p.line(x0, 15, x1, 20, MANTLE[0])


def hunger_charm(p: Pic) -> None:
    """A jawbone amulet: a lower jaw full of teeth on a cord."""
    p.part(brush([(4, 3), (6, 9)], 0.6) | brush([(20, 3), (18, 9)], 0.6), LEATHERD, mode="flat", base=3, sep=False)
    p.part(ring(12, 9, 8, 10, 3.2) & (_YY > 9), BONE, lo=0.7, hi=4)
    for x, y in ((7, 12), (9, 15), (12, 16), (15, 15), (17, 12)):
        p.part(ell(x + 0.5, y - 1.5, 0.9, 1.4), BONE, mode="flat", base=3)
    p.px([(10, 18), (14, 18)], ROTP[2])


def leaping_heart(p: Pic) -> None:
    """A red heart with two small feathered wings."""
    for s in (-1, 1):
        cx = 12 + s * 6.0
        p.part(ell(cx, 8.5, 3.9, 2.3, -s * 20) | ell(cx + s * 0.5, 11, 3.6, 2.0, -s * 15)
               | ell(cx, 13, 2.8, 1.6, -s * 10), PETAL, lo=0.8, hi=4)
    m = ell(9.5, 11, 3.6, 3.6) | ell(14.5, 11, 3.6, 3.6) | poly((6, 12.5), (18, 12.5), (12, 20))
    p.part(m, RED, lo=0.6, hi=4)


def mossbed(p: Pic) -> None:
    """A low mossy stone, moss draped over its top."""
    stone = ell(12, 14, 9, 6.5)
    p.part(stone, STONE, lo=0.5, hi=3.6)
    moss = stone & ((_YY < 12.5) | ell(8, 13, 2, 3) | ell(15, 13.5, 1.6, 2.6))
    p.part(moss, MOSS, lo=0.7, hi=4, sep=False)
    p.part(brush([(9, 7.5), (8, 4)], 0.6) | brush([(14, 7.5), (15.5, 5)], 0.6), GRASS, mode="flat", base=3,
           sep=False)


def rain_pouch(p: Pic) -> None:
    """A rain-soaked leather pouch tied shut, water running off it."""
    p.part(poly((9, 4), (15, 4), (14, 8), (10, 8)), LEATHER, mode="flat")
    p.part(ell(12, 14.5, 7, 6.5), LEATHER, lo=0.5, hi=3.6)
    p.part(rect(9, 8, 15, 9), CREAM, mode="flat", base=2)
    p.part(brush([(15, 9), (17, 12)], 0.6), CREAM, mode="flat", base=2, sep=False)
    p.px([(8, 12), (9, 11), (7, 15), (13, 12)], WATER[4])
    p.px([(10, 17), (15, 16)], WATER[3])
    p.part(ell(4.5, 18, 1.0, 1.5), WATER, mode="flat", base=3)
    p.part(ell(19.5, 15, 1.0, 1.5), WATER, mode="flat", base=3)


def second_wind(p: Pic) -> None:
    """A small leather bellows from the side: two boards on pleated leather, grips, a brass nozzle."""
    p.part(brush([(8, 12.5), (2.5, 12.5)], 1.3, 0.8), BRASS, mode="flat", base=2)
    p.part(brush([(18, 7), (21, 5)], 1.1) | brush([(18, 18), (20.5, 19.5)], 1.1), WOOD, mode="flat", base=2)
    p.part(poly((8, 11), (19, 6.5), (19, 18.5), (8, 14)), LEATHERD, mode="flat", base=2)
    for k in range(4):
        x = 11 + k * 2
        p.line(x, 9 - k, x, 15 + k, LEATHERD[4] if k % 2 else LEATHERD[1])
    p.part(brush([(7.5, 11.5), (19.5, 6)], 1.2), WOOD, lo=0.8, hi=4)
    p.part(brush([(7.5, 13.5), (19.5, 19)], 1.2), WOOD, lo=0.4, hi=3.2)
    p.px([(12, 9), (16, 7)], BRASS[3])


def still_water(p: Pic) -> None:
    """A stone bowl of still water, the light lying on it."""
    p.part(ell(12, 11, 9, 8.5) & (_YY > 10), STONE, lo=0.5, hi=3.6)
    p.part(ell(12, 11, 9, 3.6), STONE, mode="flat", base=3)
    p.paint(ell(12, 11.2, 7.0, 2.2), WATER[2])
    p.paint(ell(12, 12, 6.0, 1.4) & (_YY > 11.5), WATER[1])
    p.line(8, 10, 11, 10, WATER[4])
    p.px([(14, 11)], WATER[4])


def tallow_candle(p: Pic) -> None:
    """A short fat stub of tallow candle, melted down its sides, a small flame on top."""
    p.part(ell(12, 19.5, 6.5, 2.0), WAX, mode="flat", base=1)
    p.part(rect(7, 11, 16, 19), WAX, lo=0.8, hi=3.8)
    p.part(ell(12, 11, 4.6, 1.6), WAX, mode="flat", base=3, sep=False)
    p.part(brush([(8, 11), (8, 15)], 0.8) | brush([(14, 11), (14, 17)], 0.8), WAX, mode="flat", base=4, sep=False)
    p.px([(12, 9)], INK)
    p.part(brush([(12, 4.5), (12, 8)], 0.5, 1.4), AMBER, mode="glow")


def thick_hide(p: Pic) -> None:
    """A stretched patch of thick hide, stitched across."""
    m = poly((7, 4), (17, 4), (19, 7), (18, 12), (20, 17), (16, 20), (8, 20), (4, 17), (6, 12), (5, 7))
    p.part(m, HIDE, mode="flat")
    p.paint(m & ~grow(~m), HIDE[2])
    for y in (8, 11, 14, 17):
        p.px([(11, y), (13, y + 1)], CREAM[3])
        p.px([(12, y), (12, y + 1)], HIDE[0])
    p.px([(8, 8), (16, 12), (9, 16), (15, 7)], HIDE[3])


def widows_thimble(p: Pic) -> None:
    """A bone thimble, dimpled all over, a black widow's band round its rim."""
    body = ell(12, 7.5, 4.6, 3.8) | poly((7.4, 7.5), (16.6, 7.5), (17, 18), (7, 18))
    p.part(body, BONE, lo=0.6, hi=4)
    for y in range(5, 15, 2):
        for x in range(8 + (y // 2) % 2, 17, 2):
            if body[y, x] and body[y, x - 1] and body[y, x + 1] and body[y - 1, x]:
                p.px([(x, y)], BONE[1])
    p.part(rect(7, 15, 17, 16), CHAR, mode="flat", base=1)
    p.part(ell(12, 18.5, 5.6, 1.6), BONE, mode="flat", base=3, sep=False)


def sextons_hourglass(p: Pic) -> None:
    """A cracked hourglass of grey grave dust between two wooden plates."""
    glass = ell(12, 8, 4.6, 4.6) | ell(12, 16, 4.6, 4.6) | rect(11, 10, 12, 14)
    p.part(glass, GLASS, mode="flat", base=1)
    p.paint(glass & ~grow(~glass), ramp("#2d2a36")[2])
    p.paint(ell(12, 17.5, 3.6, 2.5) & glass, ASH[3])
    p.paint(ell(12, 8.5, 3.0, 1.5) & (_YY > 7.5) & glass, ASH[3])
    p.paint(rect(12, 11, 12, 15), ASH[2])
    p.line(8, 6, 10, 9, GLASS[4])
    p.line(10, 9, 9, 11, GLASS[4])
    p.part(rect(6, 2, 17, 4), WOOD, mode="flat")
    p.part(rect(6, 20, 17, 21), WOOD, mode="flat")
    p.part(rect(6, 4, 6, 20) | rect(17, 4, 17, 20), DWOOD, mode="flat", base=3)


def coffin_lid(p: Pic) -> None:
    """A small wooden coffin lid with a cross nailed on."""
    p.part(poly((9, 2.5), (15, 2.5), (18.5, 7), (16, 21.5), (8, 21.5), (5.5, 7)), WOOD, mode="flat")
    p.line(10, 4, 10, 20, WOOD[1])
    p.line(14, 4, 14, 20, WOOD[1])
    p.part(rect(11, 6, 12, 16) | rect(8, 9, 15, 10), DWOOD, mode="flat", base=3)
    p.px([(11, 6), (8, 9), (15, 9), (11, 16)], IRON[4])


# --- Support (round seal frame) ------------------------------------------------------------------
def ash_veil(p: Pic) -> None:
    """A torn grey veil hanging over nothing, its hem ragged."""
    m = ell(12, 8, 6, 5.5) | poly((6, 8), (18, 8), (19.5, 19), (17, 21), (15.5, 18), (13.5, 21.5), (11, 18),
                                  (8.5, 21), (6.5, 18.5), (4.5, 19.5))
    p.part(m, VEIL, lo=0.8, hi=4)
    for x0, x1 in ((9, 8), (12, 12), (15, 16)):
        p.line(x0, 11, x1, 18, VEIL[1])
    p.cut(ell(15.5, 14, 1.0, 1.4) | ell(9, 16, 0.8, 1.0))
    p.paint(ell(12, 8.5, 3.0, 2.0), VEIL[1])


def chain_of_silence(p: Pic) -> None:
    """A rusty chain looped through a padlock."""
    for i, (x, y) in enumerate(((4.5, 4), (5.5, 8), (8, 11.2), (16, 11.2), (18.5, 8), (19.5, 4))):
        p.part(ring(x, y, 2.4 if i % 2 == 0 else 1.6, 1.6 if i % 2 == 0 else 2.4, 1.0), RUST, mode="flat", base=3,
               sep=i > 0)
    p.part(ring(12, 12, 3.4, 4.0, 1.4) & (_YY < 13), IRON, mode="flat", base=3)
    p.part(rect(7, 13, 16, 20), IRON, lo=0.6, hi=4)
    p.paint(ell(12, 15.5, 1.2, 1.2) | rect(12, 16, 12, 18), INK)
    p.px([(8, 19), (15, 14)], RUST[2])


def fox_paw(p: Pic) -> None:
    """A fox's paw seen from below: orange fur, dark pads."""
    p.part(rect(9, 17, 15, 21) | ell(12, 13, 7, 6.5) | ell(5.8, 7.8, 2.4, 2.8) | ell(9.9, 5, 2.3, 2.8)
           | ell(14.1, 5, 2.3, 2.8) | ell(18.2, 7.8, 2.4, 2.8), FUR, lo=0.7, hi=4)
    pad = ramp("#4a2c38", step_l=0.07)
    p.part(ell(12, 13.8, 3.6, 3.0), pad, mode="flat", base=2)
    for x, y in ((6.3, 8.6), (10.1, 6.6), (13.9, 6.6), (17.7, 8.6)):
        p.part(ell(x, y, 1.2, 1.4), pad, mode="flat", base=2)


def gravebloom(p: Pic) -> None:
    """A pale flower growing from a grave mound."""
    p.part(ell(12, 21, 9.5, 5.5) & (_YY < 21.5), DIRT, lo=0.5, hi=3.6)
    p.px([(6, 17), (7, 16), (17, 16), (18, 17)], GRASS[3])
    p.part(brush([(12, 17), (12.5, 12), (12, 9)], 0.7), GRASS, mode="flat", base=2)
    p.part(ell(15, 13.5, 2.4, 1.2, -30), GRASS, mode="flat", base=2)
    m = np.zeros((N, N), dtype=bool)
    for k in range(5):
        a = -math.pi / 2 + k * math.tau / 5
        m |= ell(12 + math.cos(a) * 3.0, 7 + math.sin(a) * 3.0, 2.2, 2.2)
    p.part(m, PETAL, lo=0.8, hi=4)
    p.part(ell(12, 7, 1.4, 1.4), GOLD, mode="flat", base=3)


def hollow_drum(p: Pic) -> None:
    """A skin drum, laced round its wooden body, a stick resting on it."""
    p.part(ell(12, 17.5, 8, 3) | rect(4, 9, 19, 17), WOOD, lo=0.5, hi=3.6)
    p.part(ell(12, 9, 8, 3), PALE, mode="flat", base=3)
    for x in (5, 9, 13, 17):
        p.line(x, 11, x + 2, 17, CREAM[3])
        if x < 17:
            p.line(x + 2, 11, x, 17, CREAM[2])
    p.part(rect(4, 17, 19, 17) & ell(12, 17.5, 8, 3), DWOOD, mode="flat", base=2, sep=False)
    p.part(brush([(6, 3.8), (15, 8.5)], 0.9), WOOD, mode="flat", base=3)
    p.part(ell(5.5, 3.6, 1.3, 1.3), CREAM, mode="flat", base=3)


def keen_eye(p: Pic) -> None:
    """A glass eye: a white orb, a cyan iris, a bright glint."""
    p.part(ell(12, 12, 8.2, 8.2), EYE + [EYE[-1]], lo=0.0, hi=1.4, spec=False)
    p.paint(ell(12, 12, 8.2, 8.2) & ~ell(11, 11, 7.6, 7.6), BONE[1])
    p.part(ell(10.5, 11, 4.0, 4.0), CYAN, mode="flat", base=1)
    p.paint(ell(10.5, 11, 2.8, 2.8), CYAN[2])
    p.paint(ell(10.5, 11, 1.6, 1.6), INK)
    p.px([(9, 9), (9, 10)], EYE[1])
    p.px([(17, 14), (18, 12), (16, 16)], BLOOD[3])


def marrow_charm(p: Pic) -> None:
    """A marrow bone split in two, red marrow showing at the break."""
    p.part(brush([(5, 6), (10.5, 11)], 1.8) | ell(4, 6.5, 1.8, 1.8) | ell(5.5, 4.5, 1.8, 1.8), BONE, lo=0.8, hi=4)
    p.part(brush([(13.5, 13), (19, 18)], 1.8) | ell(20, 17.5, 1.8, 1.8) | ell(18.5, 19.5, 1.8, 1.8), BONE, lo=0.8,
           hi=4)
    p.paint(ell(10.6, 11.2, 1.0, 1.0) | ell(13.4, 12.8, 1.0, 1.0), BLOOD[2])
    p.px([(11, 10), (12, 13)], BONE[4])


def menders_needle(p: Pic) -> None:
    """A needle and red thread, the thread looping from its eye."""
    p.part(brush([(16, 6), (12, 9), (8, 14), (8, 18), (12, 19.5), (15, 16), (12, 13)], 0.9), RED, mode="flat",
           base=2)
    p.part(brush([(5, 20), (18, 4)], 1.1, 0.8) | ell(18, 4.2, 1.8, 1.8), STEEL, mode="flat", base=3)
    p.paint(ell(18, 4.2, 0.7, 0.7), INK)
    p.part(brush([(18.5, 4.5), (19.5, 8), (18, 11)], 0.8), RED, mode="flat", base=2, sep=False)


def oathbreakers_band(p: Pic) -> None:
    """A silver ring snapped open, its broken ends bent apart."""
    m = ring(12, 13, 7.5, 7.5, 3.0) & ~poly((12, 13), (14, 2), (22, 7))
    p.part(m, GLASS, lo=0.8, hi=4)
    p.part(poly((14.6, 4.2), (16.5, 2.5), (16.2, 6.4)), GLASS, mode="flat", base=3, sep=False)
    p.part(poly((18.8, 7.2), (21.0, 6.0), (19.7, 9.6)), GLASS, mode="flat", base=3, sep=False)
    p.px([(19, 3), (21, 3)], GLASS[4])
    p.px([(7, 16), (8, 18)], VIOLET[1])


def quick_boots(p: Pic) -> None:
    """A pair of worn leather boots, one behind the other."""
    for dx, dy, cols in ((4, -2, LEATHERD), (0, 0, LEATHER)):
        shaft = rect(5 + dx, 5 + dy, 10 + dx, 17 + dy)
        foot = ell(11 + dx, 18 + dy, 6, 2.6) & (_YY < 20.5 + dy)
        p.part(shaft | foot, cols, lo=0.6, hi=4)
        p.paint(rect(5 + dx, 5 + dy, 10 + dx, 6 + dy), cols[1])
        p.paint(rect(5 + dx, 20 + dy, 16 + dx, 20 + dy) & (shaft | foot), DWOOD[1])
    p.px([(7, 10), (8, 12), (7, 14)], CREAM[2])


def reapers_coin(p: Pic) -> None:
    """A thick gold coin stamped with a skull."""
    p.part(ell(12.8, 12.8, 8, 8), GOLDW, mode="flat", base=1)
    p.part(ell(12, 12, 8, 8), GOLD, mode="flat", base=2)
    p.paint(ring(12, 12, 6.2, 6.2, 1.0), GOLD[1])
    p.part(ell(12, 11, 3.6, 3.4) | rect(10, 13, 14, 15), BONE, mode="flat", base=3)
    p.paint(ell(10.5, 11, 1.0, 1.1) | ell(13.5, 11, 1.0, 1.1), INK)
    p.px([(11, 15), (13, 15)], GOLD[1])


def riposte_ring(p: Pic) -> None:
    """Two crossed blades through a gold ring."""
    for (x0, y0, x1, y1) in ((4, 20, 19, 4), (20, 20, 5, 4)):
        p.part(brush([(x0, y0), (x1, y1)], 1.0, 0.6), STEEL, mode="flat", base=3)
        p.part(ell(x0 + (2 if x0 < 12 else -2), y0 - 2, 2.0, 0.9, 45 if x0 < 12 else -45), GOLDW, mode="flat")
    p.part(ring(12, 12, 4.6, 4.6, 1.8), GOLD, lo=0.6, hi=4)


def rotten_crown(p: Pic) -> None:
    """A gold crown gone to rot: green ooze dripping from its band, a violet stone."""
    p.part(poly((4, 17), (4, 8), (8, 12), (12, 5), (16, 12), (20, 8), (20, 17)), GOLDW, lo=0.6, hi=4)
    for x, y in ((4, 7), (12, 4), (20, 7)):
        p.part(ell(x, y, 1.4, 1.4), GOLDW, mode="flat", base=3, sep=False)
    p.part(rect(4, 14, 20, 17), GOLDW, mode="flat", base=1)
    p.part(ell(12, 15.5, 1.6, 1.4), VIOLET, mode="flat", base=1, sep=False)
    p.part(brush([(7, 17), (7, 20)], 0.8) | ell(7, 20.5, 1.1, 1.1) | brush([(17, 17), (17, 19)], 0.8),
           GROT, mode="flat", base=1, sep=False)
    p.px([(9, 11), (15, 13), (6, 15)], ROTP[2])


def sour_milk(p: Pic) -> None:
    """A clay jug, curdled milk lumped over its mouth and running down."""
    p.part(ring(17, 12, 3.6, 4.2, 1.6) & (_XX > 17), JUG, mode="flat", base=2)
    p.part(ell(11.5, 14.5, 6.5, 6.5) | rect(8, 5, 15, 9), JUG, lo=0.5, hi=3.8)
    p.part(ell(9.5, 5, 2.6, 1.6) | ell(13.5, 4.5, 2.4, 1.8) | ell(11.5, 6, 3.6, 1.4), MILK, lo=0.6, hi=4)
    p.part(brush([(9, 6), (8.5, 10)], 0.8) | ell(8.5, 10.5, 1.0, 1.2), MILK, mode="flat", base=2, sep=False)
    p.px([(12, 4), (10, 6)], GROT[0])
    p.paint(rect(6, 13, 17, 13), JUG[1])


def thorned_gauntlet(p: Pic) -> None:
    """A spiked iron gauntlet, fingers up, spikes on its knuckles and cuff."""
    p.part(poly((7, 15), (17, 15), (19, 21), (5, 21)), IRON, mode="flat", base=2)
    p.part(brush([(6, 13), (5, 9), (6.5, 7)], 1.4), STEEL)
    hand = rect(7, 8, 17, 15) | ell(12, 15, 5.5, 2)
    for x in (8, 11, 14):
        hand |= rect(x, 3 + (1 if x == 8 else 0), x + 2, 8)
    hand |= rect(16, 5, 17, 8)
    p.part(hand, STEEL, lo=0.6, hi=4)
    for x in (10, 13, 16):
        p.line(x, 4, x, 8, STEEL[0])
    p.px([(9, 9), (12, 9), (15, 9)], GLASS[4])
    p.paint(rect(7, 10, 17, 10), STEEL[1])
    p.part(poly((19, 9), (21.5, 8), (19, 11)) | poly((4, 18), (2, 19.5), (4.5, 20)), GLASS, mode="flat", base=3,
           sep=False)


def wake_root(p: Pic) -> None:
    """A knot of root sprouting fresh green leaves."""
    p.part(brush([(9, 18), (7, 21)], 0.8) | brush([(15, 18), (17, 21)], 0.8) | brush([(12, 18), (12, 21.5)], 0.8),
           DEAD, mode="flat", base=2)
    p.part(ring(10, 14, 4, 4, 2), WOOD, lo=0.6, hi=4)
    p.part(ring(14, 14, 4, 4, 2) & ~(ell(10, 14, 4, 4) & (_YY < 14)), WOOD, lo=0.6, hi=4)
    p.part(brush([(12, 10), (12, 6)], 0.7), GRASS, mode="flat", base=3)
    p.part(ell(9, 5, 3.0, 1.6, -25) | ell(15, 4.5, 3.0, 1.6, 25), GRASS, lo=0.8, hi=4)


def pilgrims_staff(p: Pic) -> None:
    """A pilgrim's walking staff, a water gourd hanging from its crook."""
    p.part(brush([(7, 21.5), (14, 6), (15, 3), (17.5, 3), (18, 5.5)], 1.1), WOOD, mode="flat", base=2)
    p.part(brush([(14.5, 7.5), (17, 9)], 0.5), CREAM, mode="flat", base=2, sep=False)
    p.part(ell(17.5, 11.5, 1.9, 1.8) | ell(17.5, 16, 3.0, 3.2), CANVAS, lo=0.6, hi=4)
    p.part(rect(17, 9, 18, 10), DWOOD, mode="flat", base=2)


def whetstone(p: Pic) -> None:
    """A grey whetstone bar: its worn top face light, its long side mid, its end dark."""
    cols = ramp("#8a90a0", step_l=0.08)
    top = poly((3, 12), (15, 7), (21, 10), (9, 15))
    front = poly((9, 15), (21, 10), (21, 14), (9, 19))
    end = poly((3, 12), (9, 15), (9, 19), (3, 16))
    whole = top | front | end
    p.part(whole, cols, mode="flat", base=2)
    rim = grow(~whole)
    p.paint(top & ~rim, cols[3])
    p.paint(front & ~top & ~rim, cols[2])
    p.paint(end & ~top & ~front & ~rim, cols[1])
    p.line(6, 12, 15, 9, cols[4])


def crow_feather(p: Pic) -> None:
    """A black crow feather with a blue sheen."""
    p.part(brush([(5, 20), (9, 15), (14, 9), (18, 5.2)], 1.6, 2.4) & ~brush([(5, 20), (8, 16.5)], 2.0), FEATHER,
           lo=0.6, hi=4)
    p.line(5, 20, 18, 4, FEATHER[4])
    p.px([(11, 9), (13, 8), (15, 6), (10, 11)], CYAN[0])
    p.cut(ell(16.5, 10.5, 0.8, 0.8) | ell(9.5, 16.5, 0.8, 0.8))
    p.part(brush([(5, 20), (3.5, 21.5)], 0.6), BONE, mode="flat", base=2)


def bellringers_rope(p: Pic) -> None:
    """A thick bell rope with a striped woollen grip and a frayed end."""
    p.part(brush([(12, 3.2), (12, 18)], 1.4), CANVAS, mode="flat", base=2)
    for y in range(3, 18, 3):
        p.line(11, y + 1, 13, y, CANVAS[0])
    p.part(brush([(12, 7), (12, 14)], 2.8), WOOL, lo=0.6, hi=4)
    p.paint(brush([(12, 9.5), (12, 11.5)], 2.8) & brush([(12, 7), (12, 14)], 2.8), CREAM[3])
    for x0, x1 in ((11, 8), (12, 12), (13, 16), (11, 10), (13, 14)):
        p.line(x0, 18, x1, 21, CANVAS[3])


def kindling_bundle(p: Pic) -> None:
    """A bundle of kindling twigs tied with twine."""
    for i, (y0, y1, cols) in enumerate(((16, 7, WOOD), (18, 9, DEAD), (14, 6, DWOOD), (19, 11, WOOD),
                                        (17, 9, DEAD))):
        p.part(brush([(3.5 + i * 0.4, y0), (20.5 - i * 0.3, y1)], 1.0), cols, mode="flat", base=2 + (i % 2))
    p.part(brush([(16, 10), (18, 6.5)], 0.6), DEAD, mode="flat", base=3, sep=False)
    p.part(brush([(9.5, 10), (11.5, 18.5)], 1.2), CREAM, mode="flat", base=2)


def martyrs_ash(p: Pic) -> None:
    """A small clay urn, its lid lifted on a wisp of grey ash."""
    p.part(ell(12, 21, 3.4, 1.2) | rect(10, 18, 13, 20), CLAY, mode="flat")
    p.part(ell(12, 14, 6.2, 5.4), CLAY, lo=0.5, hi=3.8)
    p.part(rect(9, 8, 14, 9), CLAY, mode="flat", base=1)
    p.paint(rect(6, 13, 18, 14) & ell(12, 14, 6.2, 5.4), CREAM[2])
    p.part(ell(12, 6.5, 4.0, 1.3), CLAY, mode="flat", base=3)
    p.part(ell(12, 4.6, 1.2, 1.2), CLAY, mode="flat", base=3)
    p.part(ell(17, 3.5, 1.4, 1.1) | ell(19, 6, 1.1, 0.9), ASH, mode="flat", base=3, sep=False)


# id, kind (frame), rarity, rot-touched, drawing. The 8.25 table is the contract.
RELICS: list[tuple[str, str, str, bool, Callable[[Pic], None]]] = [
    ("bitter_root", "attack", "common", False, bitter_root),
    ("black_ichor", "attack", "rare", True, black_ichor),
    ("bloodletters_fang", "attack", "rare", True, bloodletters_fang),
    ("bone_whistle", "attack", "rare", False, bone_whistle),
    ("bramble_coat", "attack", "common", False, bramble_coat),
    ("breakers_maul", "attack", "common", False, breakers_maul),
    ("brimming_cup", "attack", "common", False, brimming_cup),
    ("butchers_edge", "attack", "rare", False, butchers_edge),
    ("ember_stone", "attack", "common", False, ember_stone),
    ("first_light", "attack", "common", False, first_light),
    ("gravebound_ring", "attack", "rare", True, gravebound_ring),
    ("last_ember", "attack", "common", False, last_ember),
    ("pale_tithe", "attack", "rare", True, pale_tithe),
    ("plague_bell", "attack", "common", False, plague_lancet),
    ("rot_hunter", "attack", "common", False, rot_hunter),
    ("moth_wing", "attack", "rare", False, moth_wing),
    ("grudge_stone", "attack", "rare", False, grudge_stone),
    ("grave_tag", "attack", "common", False, grave_tag),
    ("knotted_lash", "attack", "common", False, knotted_lash),
    ("kingsbane_nail", "attack", "rare", False, kingsbane_nail),
    ("lone_lantern", "attack", "rare", False, lone_lantern),
    ("hunters_horn", "attack", "common", False, hunters_horn),
    ("hounds_tooth", "attack", "common", False, hounds_tooth),
    ("headsmans_hood", "attack", "legendary", False, headsmans_hood),
    ("gravediggers_spade", "attack", "legendary", False, gravediggers_spade),
    ("cleansing_bell", "defence", "common", False, shriving_bell),
    ("crown_of_thorns", "defence", "legendary", True, crown_of_thorns),
    ("echo_charm", "defence", "common", False, leech_hook),
    ("heartleaf", "defence", "common", False, heartleaf),
    ("hollow_mantle", "defence", "rare", True, hollow_mantle),
    ("hunger_charm", "defence", "rare", True, hunger_charm),
    ("leaping_heart", "defence", "common", False, leaping_heart),
    ("mossbed", "defence", "common", False, mossbed),
    ("rain_pouch", "defence", "common", False, rain_pouch),
    ("second_wind", "defence", "rare", False, second_wind),
    ("still_water", "defence", "common", False, still_water),
    ("tallow_candle", "defence", "common", False, tallow_candle),
    ("thick_hide", "defence", "common", False, thick_hide),
    ("widows_thimble", "defence", "common", False, widows_thimble),
    ("sextons_hourglass", "defence", "common", False, sextons_hourglass),
    ("coffin_lid", "defence", "common", False, coffin_lid),
    ("ash_veil", "support", "rare", True, ash_veil),
    ("chain_of_silence", "support", "rare", True, chain_of_silence),
    ("fox_step", "support", "common", False, fox_paw),
    ("gravebloom", "support", "common", False, gravebloom),
    ("hollow_drum", "support", "rare", False, hollow_drum),
    ("keen_eye", "support", "common", False, keen_eye),
    ("marrow_charm", "support", "common", False, marrow_charm),
    ("menders_charm", "support", "common", False, menders_needle),
    ("oathbreakers_band", "support", "legendary", True, oathbreakers_band),
    ("quick_boots", "support", "common", False, quick_boots),
    ("reapers_coin", "support", "rare", False, reapers_coin),
    ("riposte_ring", "support", "common", False, riposte_ring),
    ("rotten_crown", "support", "legendary", True, rotten_crown),
    ("sour_milk", "support", "rare", True, sour_milk),
    ("thorned_gauntlet", "support", "common", False, thorned_gauntlet),
    ("wake_root", "support", "rare", False, wake_root),
    ("war_drum", "support", "rare", False, pilgrims_staff),
    ("whetstone", "support", "common", False, whetstone),
    ("crow_feather", "support", "common", False, crow_feather),
    ("bellringers_rope", "support", "legendary", False, bellringers_rope),
    ("kindling_bundle", "support", "common", False, kindling_bundle),
    ("martyrs_ash", "support", "common", False, martyrs_ash),
]
# Relics cut in 8.25: hidden in the book, never shown, so no picture.
CUT = ("iron_charm", "lucky_coin", "victors_wreath", "wardstone")


# fit(): the largest canvas a picture may get. A picture that its frame holds only small (a wide one
# in the narrow spearhead) gets more canvas round it; none needs near this many.
CANVAS_MAX = 40
_MASKS: dict[tuple[str, int], np.ndarray] = {}


def _mask(kind: str, n: int) -> np.ndarray:
    if (kind, n) not in _MASKS:
        _MASKS[kind, n] = safe_mask(kind, n=n)
    return _MASKS[kind, n]


def fit(a: np.ndarray, kind: str) -> np.ndarray:
    """The drawing `a` (24x24) on the smallest square canvas whose `kind` frame safe area holds all
    of it, placed by whole pixels nearest the canvas's middle. The game shows any canvas over the
    same square of the frame, so the smallest canvas shows the object biggest. Nothing fits (only
    with CANVAS_MAX too small): `a` as it is, which check.py then flags."""
    solid = a[..., 3] > 0
    if not solid.any():
        return a
    ys, xs = np.nonzero(solid)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    crop, shape = a[y0:y1, x0:x1], solid[y0:y1, x0:x1]
    h, w = shape.shape
    for n in range(max(h, w) + 2, CANVAS_MAX + 1):
        mask = _mask(kind, n)
        spots = sorted(((px, py) for py in range(1, n - h) for px in range(1, n - w)),
                       key=lambda q: (abs(2 * q[0] + w - n) + abs(2 * q[1] + h - n), abs(2 * q[1] + h - n), q[1], q[0]))
        for px, py in spots:
            if mask[py:py + h, px:px + w][shape].all():
                out = np.zeros((n, n, 4), dtype=np.uint8)
                out[py:py + h, px:px + w] = crop
                return out
    return a


def draw_plain(relic_id: str) -> np.ndarray:
    """The Relic's drawing on its 24x24 grid, before fit."""
    for rid, _kind, _rarity, _rot, draw in RELICS:
        if rid == relic_id:
            p = Pic()
            draw(p)
            return p.finish()
    raise KeyError(relic_id)


def make(relic_id: str) -> np.ndarray:
    """The Relic's picture: its drawing fitted to its frame."""
    for rid, kind, _rarity, _rot, _draw in RELICS:
        if rid == relic_id:
            return fit(draw_plain(rid), kind)
    raise KeyError(relic_id)


def _contact(pics: list[tuple[str, np.ndarray]], scale: int = 4, cols: int = 9) -> Image.Image:
    """Every drawing zoomed on the dark ground, named underneath."""
    cell_w, cell_h = N * scale + 16, N * scale + 22
    rows = (len(pics) + cols - 1) // cols
    out = Image.new("RGBA", (cols * cell_w, rows * cell_h), (24, 21, 28, 255))
    d = ImageDraw.Draw(out)
    for i, (rid, a) in enumerate(pics):
        x, y = (i % cols) * cell_w + 8, (i // cols) * cell_h + 4
        out.alpha_composite(Image.fromarray(a, "RGBA").resize((a.shape[1] * scale, a.shape[0] * scale), Image.NEAREST),
                            (x, y))
        d.text((x, y + N * scale + 4), rid[:16], fill=(200, 192, 176, 255))
    return out


def _in_frames(pics: list[tuple[str, str, str, bool, np.ndarray]], sides: Sequence[int], cols: int,
               zoom: int = 2) -> Image.Image:
    """Every picture in its frame at the game's sizes `sides`, named, `cols` Relics a row, the
    whole sheet zoomed `zoom` times (nearest) so single pixels can be judged."""
    gap = 6
    cell_w = sum(sides) + gap * len(sides)
    cell_h = max(sides) + 14
    rows = (len(pics) + cols - 1) // cols
    out = Image.new("RGBA", (cell_w * cols + gap, cell_h * rows + gap), (34, 31, 40, 255))
    d = ImageDraw.Draw(out)
    for i, (rid, kind, rarity, rot, a) in enumerate(pics):
        x0, y0 = (i % cols) * cell_w + gap, (i // cols) * cell_h + gap
        x = x0
        for side in sides:
            out.alpha_composite(compose(a, kind, rarity, rot, side), (x, y0 + max(sides) - side))
            x += side + gap
        d.text((x0, y0 + max(sides) + 1), rid[:22], fill=(200, 192, 176, 255))
    return out.resize((out.width * zoom, out.height * zoom), Image.NEAREST)


def build(ctx) -> None:
    pics, plain = [], []
    for rid, kind, rarity, rot, _draw in RELICS:
        drawn = draw_plain(rid)
        a = fit(drawn, kind)
        out = (a[..., 3] > 0) & ~_mask(kind, a.shape[0])
        if out.any():
            ys, xs = np.nonzero(out)
            print("relic_icons: %s pokes out of its %s frame at %s" % (rid, kind, list(zip(xs.tolist(), ys.tolist()))[:6]))
        ctx.save("sprites/relics/%s.png" % rid, a, scale=8)
        pics.append((rid, kind, rarity, rot, a))
        plain.append((rid, drawn))
    folder = os.path.join(PREVIEW, ctx.module)
    os.makedirs(folder, exist_ok=True)
    _contact(plain).save(os.path.join(folder, "contact.png"))
    # Small sizes (map chips, the book's list, the start screen) for every Relic, then the big ones.
    _in_frames(pics, PREVIEW_SIDES[:3], 7).save(os.path.join(folder, "in_frames_small.png"))
    for kind in ("attack", "defence", "support"):
        chosen = [p for p in pics if p[1] == kind]
        _in_frames(chosen, PREVIEW_SIDES[3:], 6, zoom=1).save(os.path.join(folder, "in_frames_%s.png" % kind))
