"""The run map (DESIGN.md 8, card #111): an old paper map that unrolls, with each stop painted on.

The game draws all of these at MAP_SCALE with nearest filtering, so one art pixel is MAP_SCALE
screen pixels everywhere on the map (data/presentation/map_visuals.tres holds the same numbers).
Stops are small painted pictures with a sepia ink outline, the way an old map shows a town or a
camp; the paths between them are ink dots the game draws itself.

- ui/map_paper.png: the whole sheet, taller than the screen (the game scrolls it). Worn
  parchment, darker and burnt at its torn left and right edges (top and bottom stay under the
  rollers), folds, a few tea rings, and faint doodles kept to the margins (hills, trees, a compass
  rose by the start, waves) so they never sit under a stop or a name.
- ui/map_roller.png: one rolled-up end of the paper lying across it, a little wider than the
  sheet. One sits at the top and one at the bottom of the part on screen; while the map unrolls
  they move apart from the middle.
- ui/map_shop.png: a little shop with a striped awning and a coin sign.
- ui/map_rest.png: a campfire in a ring of stones.
- ui/map_zone_<zone id>.png: each zone as its place: Rotten Hollow two dead trees with a glowing
  hollow, Sunken Bog a murky pool with reeds and a toadstool, Ashen Ruins broken columns.
- ui/map_lair_hollow_king.png (bigger): the boss's lair, a crag with a cave mouth, red eyes inside
  and a crown on the peak.
- ui/map_flag.png: the party's banner (Alder blue, Brin red, Cass gold) planted where the party
  is.
- ui/map_ring.png, ui/map_ring_big.png: a quick red ink circle around the stop picked (the big
  one for the lair).
"""
from __future__ import annotations

import math

import numpy as np

from kit.canvas import Canvas, rgba8
from kit.color import ramp
from kit.noise import fbm2
from kit.palette import M

MAP_SCALE = 3
PAPER_W = 440
PAPER_H = 520
ROLLER_W = PAPER_W + 10
ROLLER_H = 16
TEA_RINGS = ((372.0, 52.0, 17.0), (64.0, 236.0, 12.0), (390.0, 330.0, 14.0), (300.0, 470.0, 10.0))
FOLDS_Y = (130.0, 260.0, 390.0)
ICON = 24
LAIR = 32
RING = 30
RING_BIG = 40

PAPER = ramp("#c9b386", below=3, above=2, step_l=0.06)  # darkest first; PAPER[3] is the base
SEPIA = ramp("#4b3527", below=1, above=2, step_l=0.08)  # map ink, darkest first
INK_OUT = SEPIA[0]
FAINT = PAPER[1]  # doodles: old ink faded into the paper
RED_INK = ramp("#8f2c22", below=1, above=1)

WOOD = M["wood"].colors
DARKWOOD = M["wood_dark"].colors
DEAD = M["dead_wood"].colors
RED = M["cloth_red"].colors
CREAM = M["cloth_cream"].colors
BLUE = M["cloth_blue"].colors
GOLD = M["gold"].colors
STONE = M["stone"].colors
WARM = M["stone_warm"].colors
ASH = M["ash"].colors
MOSS = M["moss"].colors
GRASS = M["grass"].colors
WATER = M["bog_water"].colors
MUD = M["bog_mud"].colors
BONE = M["bone"].colors
ROT = M["glow_rot"].colors
EMBER = M["glow_ember"].colors
AMBER = M["glow_amber"].colors
PURPLE = M["rot_purple"].colors
ROBE = M["king_robe"].colors

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


# --- the paper -------------------------------------------------------------------------------

def _side_distance(w: int, h: int, seed: int, inset: float, wobble: float) -> np.ndarray:
    """Distance in from the torn left and right edges (top and bottom stay under the rollers)."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    d = np.minimum(x, w - x) - inset
    tear = fbm2(x / 7.0, y / 7.0, seed=seed, octaves=3)
    return d - tear * wobble


def make_paper() -> np.ndarray:
    w, h = PAPER_W, PAPER_H
    y, x = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    d = _side_distance(w, h, 11, 2.0, 6.0)
    # Tone: big soft blotches, a little grain, darker toward the torn sides, a few tea rings.
    t = 0.58 + 0.42 * (fbm2(x / 46.0, y / 46.0, seed=3, octaves=3) - 0.5) * 2.0 * 0.45
    t += (fbm2(x / 5.0, y / 5.0, seed=8, octaves=2) - 0.5) * 0.12
    edge = np.clip(1.0 - d / 26.0, 0.0, 1.0)
    t -= 0.42 * edge ** 2
    for cx, cy, r in TEA_RINGS:
        ring_d = np.abs(np.hypot(x - cx, y - cy) - r)
        t -= 0.16 * np.clip(1.0 - ring_d / 1.6, 0.0, 1.0)
        t -= 0.05 * (np.hypot(x - cx, y - cy) < r)
    # Folds: a dark crease with a lit lip beside it, one down the middle and a few across.
    folds = [(x, w * 0.5)] + [(y, fy) for fy in FOLDS_Y]
    for axis, at in folds:
        t -= 0.13 * (np.abs(axis - at) < 0.8)
        t += 0.08 * (np.abs(axis - at - 1.0) < 0.8)
    # Ordered dither into the paper ramp (indices 1 to 5; 0 is the burnt rim).
    level = t * 5.0 + (BAYER4[(y.astype(int)) % 4, (x.astype(int)) % 4] - 0.5) * 0.55
    idx = np.clip(np.floor(level), 1, 5).astype(int)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    cols = np.array([rgba8(c) for c in PAPER])
    out[...] = cols[idx]
    out[d < 1.6] = rgba8(PAPER[0])
    out[d < 0.0] = 0
    c = Canvas(w, h)
    c.a = out
    _doodles(c)
    return c.a


def _faint(c: Canvas, x: int, y: int) -> None:
    if 0 <= x < c.W and 0 <= y < c.H and c.a[y, x, 3] > 0:
        c.px(x, y, FAINT)


def _hills(c: Canvas, ox: int, oy: int) -> None:
    for hx, hy, s in ((22, 30, 6), (34, 26, 8), (50, 32, 5), (28, 44, 5), (44, 46, 7), (62, 22, 5)):
        hx += ox
        hy += oy
        for i in range(s + 1):
            _faint(c, hx - s + i, hy - i)
            _faint(c, hx + s - i, hy - i)
        for i in range(1, s - 1, 2):
            _faint(c, hx + s - i - 1, hy - i + 2)


def _trees(c: Canvas, ox: int, oy: int) -> None:
    for tx, ty in ((20, 8), (30, 14), (42, 6), (26, 28), (40, 24), (54, 16), (34, 40), (48, 36)):
        tx += ox
        ty += oy
        for i in range(3):
            _faint(c, tx - i, ty - 3 + i)
            _faint(c, tx + i, ty - 3 + i)
        _faint(c, tx, ty)
        _faint(c, tx, ty + 1)


def _waves(c: Canvas, oy: int) -> None:
    for wy in (0, 12, 24):
        wx = 414 + ((wy + oy) // 6) % 7
        for i in range(10):
            _faint(c, wx + i, oy + wy + (0 if i % 4 in (1, 2) else 1))


def _doodles(c: Canvas) -> None:
    """Old faded marks in the margins only (the stops and names take the middle), spread down
    the whole sheet so every part of it has something when scrolled to."""
    _hills(c, 0, 20)
    _trees(c, 0, 150)
    _hills(c, 0, 260)
    _trees(c, 0, 380)
    for oy in (60, 190, 300, 420):
        _waves(c, oy)
    _trees(c, 404, 110)
    _hills(c, 360, 240)
    # Compass rose, bottom left (by the start).
    cx, cy = 38, PAPER_H - 46
    for k in range(16):
        a = k * math.pi / 8.0
        r = 16 if k % 4 == 0 else (10 if k % 2 == 0 else 6)
        for s in range(r):
            _faint(c, round(cx + math.sin(a) * s), round(cy - math.cos(a) * s))
    for k in range(48):
        a = k * math.tau / 48.0
        _faint(c, round(cx + math.cos(a) * 7.5), round(cy + math.sin(a) * 7.5))
    # "N" above it.
    for i in range(5):
        _faint(c, cx - 2, cy - 24 + i)
        _faint(c, cx + 2, cy - 24 + i)
        _faint(c, cx - 2 + i, cy - 24 + i)


def make_roller() -> np.ndarray:
    """A rolled-up paper end lying across the top or bottom of the open sheet: a cylinder lit from
    above, the spiral of the roll showing at both ends."""
    w, h = ROLLER_W - 2, ROLLER_H - 2
    c = Canvas(w, h)
    shade = [1, 2, 3, 4, 4, 3, 3, 3, 2, 2, 2, 1, 1, 0]
    for y in range(h):
        c.rect(4, y, w - 5, y, PAPER[shade[y]])
    # Curl lines where paper layers show along the roll.
    for x in range(14, w - 10, 29):
        c.px(x, 5, PAPER[2])
        c.px(x + 1, 6, PAPER[2])
    for left in (True, False):
        cx = 4.5 if left else w - 4.5
        c.ellipse(cx, 7.0, 3.6, 7.0, PAPER[4] if left else PAPER[1])
        c.ellipse(cx, 7.0, 2.2, 4.6, PAPER[2])
        c.ellipse(cx, 7.0, 1.1, 2.4, PAPER[0])
    c.outline(INK_OUT)
    return _crop_to(c.a, ROLLER_W, ROLLER_H)


def _crop_to(a: np.ndarray, w: int, h: int) -> np.ndarray:
    """Pads a picture to w x h, centred (room for the outline)."""
    out = np.zeros((h, w, 4), dtype=np.uint8)
    ah, aw = a.shape[:2]
    out[(h - ah) // 2:(h - ah) // 2 + ah, (w - aw) // 2:(w - aw) // 2 + aw] = a
    return out


# --- stop pictures ---------------------------------------------------------------------------

def _thick(c: Canvas, x0: int, y0: int, x1: int, y1: int, color: str) -> None:
    c.line(x0, y0, x1, y1, color)
    c.line(x0 + 1, y0, x1 + 1, y1, color)


def make_shop() -> np.ndarray:
    c = Canvas(ICON, ICON)
    # Walls and door.
    c.rect(5, 12, 18, 20, WOOD[2])
    c.rect(5, 12, 6, 20, WOOD[3])
    for py in (15, 18):
        c.line(7, py, 18, py, WOOD[1])
    c.rect(10, 15, 13, 20, DARKWOOD[0])
    c.px(12, 18, GOLD[3])
    # Peaked roof.
    c.poly([(3.0, 11.5), (11.5, 3.0), (20.5, 11.5)], RED[1])
    c.poly([(3.0, 11.5), (11.5, 3.0), (11.5, 11.5)], RED[2])
    c.line(11, 4, 11, 10, RED[3])
    # Striped awning with a scalloped hem.
    for x in range(3, 21):
        col = RED[3] if (x // 2) % 2 == 0 else CREAM[3]
        c.rect(x, 11, x, 12, col)
        if x % 2 == 1:
            c.px(x, 13, col)
    # The coin sign on its bracket.
    c.line(19, 13, 21, 13, DARKWOOD[1])
    c.line(21, 13, 21, 14, DARKWOOD[1])
    c.ellipse(21.0, 17.0, 2.6, 2.6, GOLD[2])
    c.px(20, 16, GOLD[4])
    c.px(21, 17, GOLD[1])
    c.outline(INK_OUT)
    return c.a


def make_rest() -> np.ndarray:
    c = Canvas(ICON, ICON)
    # Flames: outer orange, amber middle, pale core.
    c.poly([(6.5, 18.0), (7.0, 12.0), (9.0, 9.0), (10.0, 4.0), (12.5, 8.0), (14.0, 2.5), (15.5, 9.0),
            (17.5, 12.0), (17.5, 18.0)], EMBER[2])
    c.poly([(8.5, 18.0), (9.0, 13.0), (11.0, 10.0), (12.0, 7.0), (14.0, 11.0), (15.5, 13.5),
            (15.5, 18.0)], AMBER[2])
    c.poly([(10.5, 18.0), (11.0, 14.0), (12.5, 11.5), (13.5, 14.5), (13.5, 18.0)], AMBER[3])
    # Crossed logs.
    for x0, y0, x1, y1 in ((4, 21, 18, 16), (6, 16, 20, 21)):
        _thick(c, x0, y0, x1, y1, WOOD[1])
        c.line(x0, y0 - 1, x1, y1 - 1, WOOD[3])
    c.px(4, 20, WOOD[4])
    c.px(20, 20, WOOD[4])
    # Stones around the fire, bigger in front, odd sizes.
    for sx, sy, rx, ry in ((3.5, 19.5, 1.6, 1.3), (6.5, 21.8, 2.0, 1.4), (11.5, 22.3, 2.3, 1.4),
                           (16.5, 22.0, 2.0, 1.3), (20.5, 19.8, 1.7, 1.3)):
        c.ellipse(sx, sy, rx, ry, STONE[2])
        c.px(int(sx - rx * 0.4), int(sy - ry * 0.5), STONE[4])
    c.outline(INK_OUT)
    return c.a


def make_rotten_hollow() -> np.ndarray:
    c = Canvas(ICON, ICON)
    c.ellipse(12.0, 20.5, 10.5, 2.6, MOSS[1])
    c.ellipse(10.0, 19.8, 6.5, 1.4, MOSS[2])
    # The big dead tree: thick trunk, twisted bare branches, a glowing rot hollow.
    c.rect(7, 9, 10, 20, DEAD[2])
    c.rect(7, 9, 7, 20, DEAD[3])
    c.rect(10, 11, 10, 20, DEAD[1])
    c.px(6, 20, DEAD[2])
    c.px(11, 20, DEAD[1])
    for x0, y0, x1, y1 in ((8, 9, 4, 4), (9, 10, 14, 5), (7, 12, 3, 10), (12, 7, 15, 8), (5, 6, 3, 5)):
        c.line(x0, y0, x1, y1, DEAD[2])
    c.line(8, 8, 6, 5, DEAD[3])
    c.ellipse(8.8, 15.5, 1.4, 2.0, PURPLE[0])
    c.px(8, 15, ROT[2])
    c.px(9, 16, ROT[1])
    # A smaller one behind, to the right.
    c.rect(17, 12, 18, 20, DEAD[1])
    c.px(17, 12, DEAD[2])
    for x0, y0, x1, y1 in ((17, 12, 15, 9), (18, 13, 21, 9), (21, 9, 22, 7), (15, 9, 15, 7)):
        c.line(x0, y0, x1, y1, DEAD[1])
    c.outline(INK_OUT)
    return c.a


def make_sunken_bog() -> np.ndarray:
    c = Canvas(ICON, ICON)
    c.ellipse(12.5, 18.0, 10.5, 4.6, MUD[2])
    c.ellipse(12.5, 18.2, 8.8, 3.4, WATER[1])
    c.ellipse(11.5, 17.6, 6.5, 2.2, WATER[2])
    c.line(8, 17, 11, 17, WATER[4])
    c.line(14, 19, 16, 19, WATER[3])
    # Reeds with cattail heads on the left.
    for rx, top in ((2, 9), (5, 6), (8, 10)):
        c.line(rx, 17, rx, top + 3, MOSS[3] if rx == 5 else MOSS[2])
        c.rect(rx, top, rx, top + 2, WOOD[1])
        c.px(rx, top - 1, MOSS[2])
    c.line(3, 16, 1, 12, MOSS[3])
    # A rot toadstool on the right bank.
    c.rect(19, 13, 19, 16, BONE[3])
    c.ellipse(19.5, 12.5, 3.5, 1.9, PURPLE[2])
    c.px(18, 12, ROT[2])
    c.px(20, 11, ROT[2])
    c.px(17, 12, PURPLE[3])
    c.outline(INK_OUT)
    return c.a


def make_ashen_ruins() -> np.ndarray:
    c = Canvas(ICON, ICON)
    c.ellipse(12.0, 20.6, 10.5, 2.4, ASH[1])
    c.ellipse(11.0, 20.0, 6.0, 1.2, ASH[3])
    # A tall column with its capital, fluted (lit left edge, a groove, shaded right).
    c.rect(5, 6, 8, 20, STONE[2])
    c.rect(5, 6, 5, 20, STONE[4])
    c.rect(7, 7, 7, 19, STONE[1])
    c.rect(8, 6, 8, 20, STONE[1])
    c.rect(4, 4, 9, 5, WARM[3])
    c.line(4, 5, 9, 5, WARM[2])
    c.rect(4, 20, 9, 20, WARM[1])
    # A shorter column broken off at a slant.
    for x, top in ((15, 10), (16, 11), (17, 12), (18, 13)):
        c.rect(x, top, x, 20, STONE[2])
    c.rect(15, 10, 15, 20, STONE[4])
    c.rect(18, 13, 18, 20, STONE[1])
    c.rect(14, 20, 19, 20, WARM[1])
    # The fallen lintel and rubble.
    c.rect(9, 17, 16, 19, WARM[2])
    c.line(9, 17, 16, 17, WARM[3])
    c.line(13, 17, 13, 19, WARM[1])
    c.px(21, 20, STONE[3])
    c.px(20, 19, STONE[2])
    c.px(3, 19, STONE[3])
    c.outline(INK_OUT)
    return c.a


def make_lair() -> np.ndarray:
    c = Canvas(LAIR, LAIR)
    # The crag: lit faces on the left, shade on the right.
    c.poly([(1.0, 30.5), (5.0, 17.0), (9.0, 12.0), (13.0, 9.0), (16.0, 6.5), (19.0, 9.0), (23.0, 11.0),
            (27.0, 17.0), (31.0, 30.5)], WARM[1])
    c.poly([(1.0, 30.5), (5.0, 17.0), (9.0, 12.0), (13.0, 9.0), (16.0, 6.5), (16.0, 30.5)], WARM[2])
    c.poly([(3.0, 25.0), (6.0, 17.0), (10.0, 13.0), (8.0, 20.0)], WARM[3])
    for x0, y0, x1, y1 in ((20, 12, 24, 19), (11, 14, 9, 19), (25, 21, 28, 26)):
        c.line(x0, y0, x1, y1, WARM[0])
    # The cave mouth, red eyes in the dark.
    c.ellipse(16.0, 25.5, 6.5, 7.5, ROBE[0])
    c.ellipse(16.0, 26.5, 5.0, 6.0, SEPIA[0])
    c.rect(9, 30, 23, 31, WARM[1])
    c.px(14, 24, EMBER[3])
    c.px(18, 24, EMBER[3])
    c.px(14, 25, EMBER[1])
    c.px(18, 25, EMBER[1])
    # Bones at the mouth.
    c.line(8, 29, 11, 28, BONE[3])
    c.px(22, 29, BONE[3])
    c.px(23, 28, BONE[2])
    # The crown on the peak.
    c.rect(12, 4, 20, 6, GOLD[2])
    c.rect(12, 4, 20, 4, GOLD[3])
    for sx in (12, 16, 20):
        c.rect(sx, 1, sx, 3, GOLD[3])
    for sx in (14, 18):
        c.px(sx, 3, GOLD[2])
    c.px(16, 5, RED[3])
    c.rect(12, 7, 20, 7, WARM[2])
    c.outline(INK_OUT)
    return c.a


def make_elite() -> np.ndarray:
    """An elite fight (DESIGN.md 8.6): a horned skull over two crossed blades."""
    c = Canvas(ICON, ICON)
    for x0, y0, x1, y1 in ((3, 21, 20, 4), (20, 21, 3, 4)):
        c.line(x0, y0, x1, y1, STONE[3])
        c.line(x0 + 1, y0, x1 + 1, y1, STONE[1])
    for hx, hy in ((4, 20), (19, 20)):
        c.rect(hx - 1, hy - 1, hx + 1, hy + 1, DARKWOOD[1])
    # Horns.
    c.poly([(6.0, 9.0), (2.5, 4.0), (3.0, 1.5), (5.0, 5.0), (8.0, 7.0)], BONE[2])
    c.poly([(17.0, 9.0), (20.5, 4.0), (20.0, 1.5), (18.0, 5.0), (15.0, 7.0)], BONE[2])
    # The skull: dome, cheeks, jaw, dark eyes with a red glint.
    c.ellipse(11.5, 10.5, 5.5, 5.0, BONE[3])
    c.rect(8, 13, 15, 17, BONE[3])
    c.rect(9, 17, 14, 18, BONE[2])
    c.ellipse(9.2, 11.5, 1.6, 1.8, SEPIA[0])
    c.ellipse(13.8, 11.5, 1.6, 1.8, SEPIA[0])
    c.px(9, 11, RED[3])
    c.px(14, 11, RED[3])
    c.px(11, 14, SEPIA[0])
    c.px(12, 14, SEPIA[0])
    for tx in (10, 12, 14):
        c.px(tx, 17, SEPIA[1])
    c.line(8, 8, 10, 6, BONE[-1])
    c.outline(INK_OUT)
    return c.a


def make_event() -> np.ndarray:
    """A "?" stop (DESIGN.md 8.7): a big question mark in red ink over a curl of mist."""
    c = Canvas(ICON, ICON)
    c.ellipse(12.0, 19.0, 9.5, 3.0, PAPER[2])
    c.ellipse(8.0, 17.5, 4.0, 2.0, PAPER[1])
    c.ellipse(16.0, 18.0, 4.5, 2.0, PAPER[1])
    rows = [
        "..xxxxx..",
        ".xxx.xxx.",
        "xxx...xxx",
        "......xxx",
        ".....xxx.",
        "....xxx..",
        "...xxx...",
        "...xxx...",
        ".........",
        "...xxx...",
        "...xxx...",
    ]
    c.ascii(rows, {"x": RED_INK[1]}, x=7, y=3)
    for y in range(3, 14):
        for x in range(7, 16):
            if c.get(x, y)[3] > 0 and c.get(x - 1, y)[3] == 0:
                c.px(x, y, RED_INK[2])
    c.outline(INK_OUT)
    return c.a


def make_treasure() -> np.ndarray:
    """A treasure stop (DESIGN.md 8.8): a gold-banded chest, its lid a little open, light inside."""
    c = Canvas(ICON, ICON)
    c.ellipse(12.0, 21.0, 9.5, 1.8, SEPIA[1])
    c.rect(4, 12, 19, 20, WOOD[2])
    c.rect(4, 12, 5, 20, WOOD[3])
    c.rect(18, 12, 19, 20, WOOD[1])
    c.poly([(3.5, 11.5), (5.0, 6.0), (18.5, 6.0), (20.5, 11.5)], WOOD[3])
    c.line(5, 7, 18, 7, WOOD[4])
    c.rect(4, 11, 19, 11, AMBER[3])
    for bx in (7, 16):
        c.rect(bx, 6, bx + 1, 20, GOLD[2])
        c.rect(bx, 6, bx, 20, GOLD[3])
    c.rect(10, 13, 13, 16, GOLD[2])
    c.px(11, 14, SEPIA[0])
    c.px(12, 14, SEPIA[0])
    c.px(11, 15, SEPIA[0])
    c.px(9, 10, AMBER[-1])
    c.px(14, 9, AMBER[-1])
    c.outline(INK_OUT)
    return c.a


def make_lair_husk_lord() -> np.ndarray:
    """The first act's boss lair (DESIGN.md 8.9): a huge hollow tree crowned in gold, eyes in its
    hollow."""
    c = Canvas(LAIR, LAIR)
    c.ellipse(16.0, 29.5, 14.0, 2.4, MOSS[1])
    # Roots and trunk.
    c.poly([(5.0, 30.0), (10.0, 24.0), (11.0, 10.0), (21.0, 10.0), (22.0, 24.0), (27.0, 30.0)], DEAD[2])
    c.poly([(5.0, 30.0), (10.0, 24.0), (11.0, 10.0), (15.0, 10.0), (14.0, 30.0)], DEAD[3])
    c.line(18, 12, 20, 28, DEAD[1])
    # Bare crooked limbs.
    for x0, y0, x1, y1 in ((12, 11, 6, 5), (6, 5, 4, 6), (20, 11, 26, 4), (26, 4, 28, 5), (16, 10, 15, 6),
                           (9, 8, 7, 9), (23, 8, 25, 9)):
        c.line(x0, y0, x1, y1, DEAD[2])
        c.line(x0 + 1, y0, x1 + 1, y1, DEAD[1])
    # The hollow with eyes.
    c.ellipse(16.0, 20.0, 3.6, 4.6, SEPIA[0])
    c.px(15, 19, ROT[3])
    c.px(17, 19, ROT[3])
    c.px(15, 20, ROT[1])
    c.px(17, 20, ROT[1])
    # The gold crown caught in its branches.
    c.rect(12, 6, 20, 7, GOLD[2])
    c.rect(12, 6, 20, 6, GOLD[3])
    for sx in (12, 16, 20):
        c.rect(sx, 3, sx, 5, GOLD[3])
    c.px(16, 7, RED[3])
    c.outline(INK_OUT)
    return c.a


def make_flag() -> np.ndarray:
    """The party's banner: three stripes for the three heroes, a swallowtail end."""
    c = Canvas(14, 22)
    c.rect(2, 2, 2, 20, DARKWOOD[1])
    c.rect(2, 2, 2, 6, WOOD[3])
    c.ellipse(2.5, 1.5, 1.4, 1.4, GOLD[3])
    stripes = (BLUE[3], RED[3], GOLD[3])
    for i, col in enumerate(stripes):
        c.rect(3, 3 + i * 3, 11, 5 + i * 3, col)
    c.clear(11, 7)
    c.clear(10, 7)
    c.clear(11, 6)
    c.clear(11, 8)
    c.ellipse(2.5, 21.0, 2.5, 0.8, SEPIA[1])
    c.outline(INK_OUT)
    return c.a


def make_ring(size: int) -> np.ndarray:
    """A quick pen circle: one stroke a little more than round, the ends not quite meeting."""
    c = Canvas(size, size)
    cx = cy = size / 2.0
    r0 = size / 2.0 - 3.0
    steps = 360
    for i in range(steps + 40):
        a = math.radians(-70.0 + i)
        r = r0 - 1.4 + 1.6 * i / (steps + 40)
        x = cx + math.cos(a) * r * 1.0
        y = cy + math.sin(a) * r * 0.94
        c.px(int(x), int(y), RED_INK[1])
        c.px(int(x + math.cos(a)), int(y + math.sin(a)), RED_INK[2])
    return c.a


ZONES = {"rotten_hollow": make_rotten_hollow, "sunken_bog": make_sunken_bog, "ashen_ruins": make_ashen_ruins}


def _mock(paper: np.ndarray, icons: dict[str, np.ndarray]) -> np.ndarray:
    """A sample map for the preview: a few stops placed the way the game spaces them."""
    c = Canvas(PAPER_W, PAPER_H)
    c.a = paper.copy()
    spots = [("lair", 220, 30), ("rest", 110, 88), ("rest", 220, 88), ("rotten_hollow", 330, 146),
             ("sunken_bog", 165, 204), ("shop", 275, 262), ("ashen_ruins", 110, 320),
             ("rest", 220, 378), ("flag", 204, 357), ("ring", 220, 378)]
    for name, x, y in spots:
        img = icons[name]
        h, w = img.shape[:2]
        c.paste(img, x - w // 2, y - h // 2)
    return c.a


def build(ctx) -> None:
    paper = make_paper()
    ctx.save("sprites/ui/map_paper.png", paper, scale=MAP_SCALE)
    ctx.save("sprites/ui/map_roller.png", make_roller(), scale=MAP_SCALE)
    icons = {"shop": make_shop(), "rest": make_rest(), "lair": make_lair(), "flag": make_flag(),
             "ring": make_ring(RING)}
    ctx.save("sprites/ui/map_shop.png", icons["shop"], scale=8)
    ctx.save("sprites/ui/map_rest.png", icons["rest"], scale=8)
    for zone_id, fn in ZONES.items():
        icons[zone_id] = fn()
        ctx.save("sprites/ui/map_zone_%s.png" % zone_id, icons[zone_id], scale=8)
    ctx.save("sprites/ui/map_lair_hollow_king.png", icons["lair"], scale=8)
    ctx.save("sprites/ui/map_lair_husk_lord.png", make_lair_husk_lord(), scale=8)
    ctx.save("sprites/ui/map_elite.png", make_elite(), scale=8)
    ctx.save("sprites/ui/map_event.png", make_event(), scale=8)
    ctx.save("sprites/ui/map_treasure.png", make_treasure(), scale=8)
    ctx.save("sprites/ui/map_flag.png", icons["flag"], scale=8)
    ctx.save("sprites/ui/map_ring.png", icons["ring"], scale=8)
    ctx.save("sprites/ui/map_ring_big.png", make_ring(RING_BIG), scale=8)
    ctx.extra("map_mock.png", _mock(paper, icons), scale=MAP_SCALE)
