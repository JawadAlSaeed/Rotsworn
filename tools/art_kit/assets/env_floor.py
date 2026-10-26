"""The open floors of the five places (card #186; the fifth, the Leech Queen's lair, card #323): calm, seamless 32x32 ground in three variants each.

The floor fills most of the screen behind every walk and every fight, so it must stay out of the
way: heroes and enemies are the strong colours. Rules for these tiles:

- Low contrast. The base is one ramp in three close steps (a luma spread of about 8), the detail
  (leaves, flecks, cracks, pebbles) sits only a step or two off it, in small clusters.
- No stripes and no motif. The base comes from a sum of waves pointing in evenly spread directions
  (`waves`), so it is isotropic and exactly periodic, and the detail is scattered with a seeded
  random generator and wraps over the tile edge. `check.py` tests that rows and columns do not
  average out differently (a stripe) and that the tile joins itself.
- Variants (`_b`, `_c`) share the palette, the mean tone and the amount of detail, so the floor
  shader (scripts/stage/floor_ground.gdshader) can switch between them region by region and
  mirror them without a visible change of material, only of pattern.

Each look lists its tiles in data/looks/<place>.tres (floor_tile_path and floor_variant_paths).
"""
from __future__ import annotations

import math

import numpy as np

from kit.palette import Material
from assets.env_tiles import MOSS_DIM, T, Tex, bresenham, despeckle, norm, top, wrapd

# --- Palettes (one ramp each; the tiles stay inside a few steps of it) ---------------------------

EARTH = Material.make("floor_earth", "#372b23", below=2, above=3, step_l=0.026, shadow_chroma=0.7).colors
LEAF_OLIVE = Material.make("floor_leaf_olive", "#443d2a", below=1, above=2, step_l=0.04).colors
LEAF_RUST = Material.make("floor_leaf_rust", "#4c3125", below=1, above=2, step_l=0.04,
                          light_chroma=0.7).colors
PEBBLE = Material.make("floor_pebble", "#5a5650", below=2, above=1, step_l=0.04, grey_hue=60).colors

ASH_BASE = Material.make("floor_ash", "#625f5e", below=2, above=3, step_l=0.03, grey_hue=70,
                         shadow_chroma=0.6, shadow_shift=4).colors
ASH_CHAR = Material.make("floor_char", "#4a4543", below=1, above=2, step_l=0.04, grey_hue=55,
                         shadow_chroma=0.8).colors
ASH_EMBER = ["#4a2a2e", "#6a3027"]

MUD = Material.make("floor_mud", "#493f2e", below=2, above=3, step_l=0.03, shadow_chroma=0.85,
                    shadow_shift=3).colors
POOL = Material.make("floor_pool", "#4a4a38", below=2, above=2, step_l=0.035, shadow_chroma=0.8,
                     light_chroma=0.7).colors

BASALT = Material.make("floor_basalt", "#3b3438", below=2, above=3, step_l=0.03, shadow_chroma=0.8).colors
BASALT_EDGE = Material.make("floor_basalt_edge", "#2c2629", below=1, above=1, step_l=0.035).colors
GLINT = ["#4a2429", "#6a2d2f"]

# The Leech Queen's lair (phase 26, card #323): black silt under a skin of black water, a violet
# glint where her rot shows through.
SILT = Material.make("floor_silt", "#2f2c2c", below=2, above=3, step_l=0.026, shadow_chroma=0.8,
                     grey_hue=300).colors
BLACK_POOL = Material.make("floor_black_pool", "#28282f", below=2, above=2, step_l=0.03, shadow_chroma=0.8).colors
MIRE_GLINT = ["#3a2a44", "#4e3460"]

MOSS_CALM = Material.make("floor_moss", "#434e30", below=2, above=3, step_l=0.034,
                          shadow_chroma=0.75, shadow_shift=6).colors


# --- Helpers -------------------------------------------------------------------------------------

def waves(seed: int, count: int = 14, kmin: float = 1.6, kmax: float = 5.2) -> np.ndarray:
    """A periodic, isotropic field in [0, 1]: a sum of cosines whose directions are spread evenly
    over the half circle, so no direction (and so no stripe) dominates."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:T, 0:T]
    out = np.zeros((T, T))
    for i in range(count):
        ang = (i + rng.uniform(0.1, 0.9)) / count * math.pi
        mag = rng.uniform(kmin, kmax)
        kx, ky = int(round(mag * math.cos(ang))), int(round(mag * math.sin(ang)))
        if kx == 0 and ky == 0:
            kx = 1
        out += math.hypot(kx, ky) ** -0.8 * np.cos(math.tau * (kx * xx + ky * yy) / T + rng.uniform(0, math.tau))
    return norm(out)


def bands(h: np.ndarray, shares: tuple[float, ...]) -> np.ndarray:
    """Splits a field into len(shares) levels holding exactly these shares of the pixels (low
    first), so every variant carries the same amount of each tone."""
    edges = np.cumsum(shares)[:-1]
    qs = np.quantile(h, edges)
    return np.digitize(h, qs)


def ellipse(rng: np.random.Generator, a: float, b: float) -> np.ndarray:
    """A periodic ellipse of half sizes a and b (px) at a random place and angle."""
    cx, cy = rng.uniform(0, T, 2)
    ang = rng.uniform(0.0, math.pi)
    dx = wrapd(cx)[None, :]
    dy = wrapd(cy)[:, None]
    u = dx * math.cos(ang) + dy * math.sin(ang)
    v = -dx * math.sin(ang) + dy * math.cos(ang)
    return (u / a) ** 2 + (v / b) ** 2 < 1.0


def line(rng: np.random.Generator, length: int) -> np.ndarray:
    """A short 1-pixel line (a twig, a crack) at a random place and angle, wrapping."""
    x0, y0 = int(rng.integers(0, T)), int(rng.integers(0, T))
    ang = rng.uniform(0.0, math.tau)
    x1, y1 = int(round(x0 + math.cos(ang) * length)), int(round(y0 + math.sin(ang) * length))
    m = np.zeros((T, T), bool)
    for x, y in bresenham(x0, y0, x1, y1):
        m[y % T, x % T] = True
    return m


def calm_base(tex: Tex, mat: int, seed: int, mid: int = 2, shares=(0.27, 0.46, 0.27)) -> np.ndarray:
    """Paints the base: three neighbouring steps of one ramp, in clusters. Returns the level map."""
    h = waves(seed) * 0.8 + waves(seed + 50, 10, 3.0, 7.0) * 0.2
    lvl = bands(h, shares) + (mid - 1)
    tex.set(np.ones((T, T), bool), mat, lvl)
    key = despeckle(tex.key(), passes=4)
    tex.from_key(key)
    return tex.lvl.copy()


# --- Rotten Hollow: dead leaves on dark earth ----------------------------------------------------

def hollow_floor(var: int = 0, leaves: int = 11, rust: int = 3) -> np.ndarray:
    """Forest floor: dark earth in soft drifts, a scatter of dead leaves, a few twigs and pebbles."""
    tex = Tex([EARTH, LEAF_OLIVE, LEAF_RUST, PEBBLE])
    seed = 300 + var * 17
    calm_base(tex, 0, seed)
    rng = np.random.default_rng(seed + 3)
    keep = np.zeros((T, T), bool)
    for i in range(leaves + rust):
        m = ellipse(rng, rng.uniform(1.9, 2.7), rng.uniform(0.9, 1.3))
        r = i >= leaves
        tex.set(m, 2 if r else 1, 1 if r else int(rng.integers(0, 2)) + 1)
        keep |= m
    for _ in range(2):
        tex.set(line(rng, int(rng.integers(4, 7))), 0, 0)
    for _ in range(2):
        m = ellipse(rng, 1.3, 1.0)
        tex.set(m, 3, 2)
        tex.set(np.roll(np.roll(m, 1, 0), 1, 1) & ~m, 0, 0)
        keep |= m
    tex.clean(keep=keep)
    return tex.rgba()


# --- Ashen Ruins: a skin of ash --------------------------------------------------------------------

def ash_floor(var: int = 0, flecks: int = 5, ember_count: int = 1) -> np.ndarray:
    """Drifted ash in soft dunes, flecks of char, a hairline crack or two, a dim ember."""
    tex = Tex([ASH_BASE, ASH_CHAR, ASH_EMBER])
    seed = 400 + var * 19
    calm_base(tex, 0, seed)
    rng = np.random.default_rng(seed + 3)
    keep = np.zeros((T, T), bool)
    for _ in range(flecks):
        m = ellipse(rng, rng.uniform(1.4, 2.4), rng.uniform(0.8, 1.2))
        tex.set(m, 1, 1)
        keep |= m
    for _ in range(ember_count):
        x, y = int(rng.integers(2, T - 2)), int(rng.integers(2, T - 2))
        tex.px(x, y, 2, 1)
        tex.px(x + 1, y, 2, 0)
        keep[y, x] = keep[y, (x + 1) % T] = True
    tex.clean(keep=keep)
    return tex.rgba()


# --- Sunken Bog: wet mud and shallow pools ------------------------------------------------------

def bog_floor(var: int = 0, pools: int = 3, moss_clumps: int = 0) -> np.ndarray:
    """Wet mud in wetter and drier drifts, a few dull pools, and little clumps of moss."""
    tex = Tex([MUD, POOL, MOSS_DIM])
    seed = 500 + var * 23
    calm_base(tex, 0, seed)
    rng = np.random.default_rng(seed + 3)
    keep = np.zeros((T, T), bool)
    for _ in range(pools):
        m = ellipse(rng, rng.uniform(4.5, 7.0), rng.uniform(2.6, 4.0))
        tex.set(m, 1, 2)
        keep |= m
    for _ in range(moss_clumps):
        m = ellipse(rng, rng.uniform(2.0, 3.0), rng.uniform(1.4, 2.0))
        tex.set(m & (tex.mat == 0), 2, 0)  # the dimmest moss step
        keep |= m
    tex.clean(keep=keep)
    return tex.rgba()


# --- Hollow Throne: dark cracked basalt -----------------------------------------------------------

def throne_floor(var: int = 0) -> np.ndarray:
    """The King's arena: dark basalt in soft worn drifts, a few hairline cracks that wander, and
    here and there a dull red glint where the rot burns through."""
    tex = Tex([BASALT, BASALT_EDGE, GLINT])
    seed = 600 + var * 29
    calm_base(tex, 0, seed)
    rng = np.random.default_rng(seed + 7)
    cracks = np.zeros((T, T), bool)
    for _ in range(3):
        x, y = int(rng.integers(0, T)), int(rng.integers(0, T))
        ang = rng.uniform(0.0, math.tau)
        for _step in range(3):
            ang += rng.uniform(-0.9, 0.9)
            nx, ny = int(round(x + math.cos(ang) * 4)), int(round(y + math.sin(ang) * 4))
            for px_, py_ in bresenham(x, y, nx, ny):
                cracks[py_ % T, px_ % T] = True
            x, y = nx, ny
    tex.set(cracks, 1, 1)
    glints = 0
    ys, xs = np.nonzero(cracks)
    while glints < 2:
        i = int(rng.integers(0, len(ys)))
        tex.px(int(xs[i]), int(ys[i]), 2, 1)
        glints += 1
    tex.clean(keep=cracks)
    return tex.rgba()


# --- The Leech Queen's lair: black silt and black water ------------------------------------------

def mire_floor(var: int = 0, pools: int = 4) -> np.ndarray:
    """Her arena: black silt in soft drifts, wide pools of black water over it, and here and there
    a dull violet glint at a pool's edge."""
    tex = Tex([SILT, BLACK_POOL, MIRE_GLINT])
    seed = 800 + var * 37
    calm_base(tex, 0, seed)
    rng = np.random.default_rng(seed + 5)
    keep = np.zeros((T, T), bool)
    for _ in range(pools):
        m = ellipse(rng, rng.uniform(4.5, 7.5), rng.uniform(2.4, 3.8))
        tex.set(m, 1, int(rng.integers(1, 3)))
        keep |= m
    edge = keep & ~np.roll(keep, 1, 0)
    ys, xs = np.nonzero(edge)
    for _ in range(min(2, len(ys))):
        i = int(rng.integers(0, len(ys)))
        tex.px(int(xs[i]), int(ys[i]), 2, 1)
        tex.px(int(xs[i]) + 1, int(ys[i]), 2, 0)
    tex.clean(keep=keep)
    return tex.rgba()

# --- The three ground tiles the shader mixes, per look -------------------------------------------

FLOORS = {
    "hollow_floor": hollow_floor,
    "ash_tile": ash_floor,
    "bog_tile": bog_floor,
    "throne_tile": throne_floor,
    "mire_tile": mire_floor,
}
VARIANT_SUFFIX = ("", "_b", "_c")


def moss_calm(var: int = 0) -> np.ndarray:
    """A moss patch's texture: a dull olive carpet in small clumps, with only a few lighter ones.
    The ground shader dithers its edge into the floor, so it needs no bright rim of its own."""
    tex = Tex([MOSS_CALM, MOSS_DIM])
    seed = 700 + var * 31
    h = waves(seed, 14, 2.0, 6.0)
    tex.set(np.ones((T, T), bool), 0, bands(h, (0.2, 0.45, 0.35)) + 1)
    bright = top(waves(seed + 5, 12, 3.0, 7.0), 0.1)
    tex.set(bright, 1, 3)
    tex.clean(keep=bright)
    return tex.rgba()


def leaf_patch(var: int = 0) -> np.ndarray:
    """A drift of fallen leaves for a clearing: the same earth as the floor under it with more,
    brighter leaves. Calm like the floors: no row of leaves lines up with another."""
    return hollow_floor(var + 5, leaves=17, rust=5)


def build(ctx) -> None:
    imgs = []
    for name, fn in FLOORS.items():
        row = []
        for i, suffix in enumerate(VARIANT_SUFFIX):
            img = fn(i)
            assert img.shape == (T, T, 4) and (img[..., 3] == 255).all(), name
            ctx.save("sprites/env/%s%s.png" % (name, suffix), img, tile=True)
            row.append(img)
        # Review picture: each variant tiled 4x4, then all three mixed in a checker of 2x2 blocks.
        tiles = [np.tile(r, (4, 4, 1)) for r in row]
        mixed = np.zeros((T * 4, T * 4, 4), np.uint8)
        for by in range(4):
            for bx in range(4):
                mixed[by * T:(by + 1) * T, bx * T:(bx + 1) * T] = row[(bx * 2 + by * 3 + (bx ^ by)) % 3]
        imgs.append(np.concatenate(tiles + [mixed], 1))
    ctx.extra("floors_4x4.png", np.concatenate(imgs, 0), scale=1)
    ctx.extra("floors_4x4_x2.png", np.concatenate(imgs, 0), scale=2)
