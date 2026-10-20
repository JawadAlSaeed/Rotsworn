"""Combat effects (shadow, slash, spark, ground-wave crest) and the small HUD icons.

Effects are drawn in 2D with alpha (the game blends them). Every colour comes from a palette ramp
and every alpha is one of a few steps, so even the soft things stay crisp pixel art. The HUD icons
are hand-drawn pixel grids: fully opaque or clear, outlined, shown at 18 to 60 px with nearest
filtering.

How the game uses them (keep in mind when changing them):
- shadow.png lies flat on the ground under each fighter, stretched to the fighter's width; the
  camera sees it almost edge-on (about 3 rows), so its left-right profile matters most.
- slash.png is a billboard at the struck enemy, mirrored for strikes going left, growing 1.3x
  from its centre while it fades. Drawn for a strike going right, centred on the sprite.
- spark.png flies out in bursts, shrinking to 0.4x, and is tinted (warm white for strikes,
  rot-green for deaths), so its core stays near white and cream and only the ray tips go gold.
- shockwave.png is the crest of a ground wave: several copies stand side by side along the party
  line (bottom on the ground) and travel from the enemy (right) to the party (left), so its back
  fades out to merge with the neighbours and it leans left, the way it moves.
- One colour means one thing (DESIGN.md "One colour per defence"): purple is the ground hit you
  jump, so the wave crest and the ground-hit icon use the violet ramp built from the game's
  ground_hit_color, the same purple as the floor warning, the wind-up glow and the marker ring.
"""
from __future__ import annotations

import math
import os

import numpy as np

from kit.canvas import Canvas, rgba8
from kit.color import darken_for_outline, from_oklch, ramp, to_oklch
from kit.palette import INK, M

# --- Colours ---------------------------------------------------------------------------------

SHADOW_INK = INK  # the game's darkest violet-black
SHADOW_MAX = 168  # about 66% over the middle half
SHADOW_STEP = 28  # six even alpha steps
SHADOW_FLAT = 0.55  # full strength out to this share of the radius (the rest falls off)

# Slash: (lavender, unused), blue, pale blue, very pale blue, near-white core.
SLASH = ramp("#a8c4f0", below=2, above=2, step_l=0.09)

# Slash geometry: circle centre and radius (the outer edge), arc from tail to head (degrees, y
# down: a swing over the top ending low on the right), the body's thickest width.
SLASH_CENTRE = (10.5, 20.5)
SLASH_R = 15.85
SLASH_ARC = (-130.0, 30.0)
SLASH_THICK = 8.0
SLASH_BODY = (0.27, 0.56)  # along the arc: where the solid body starts, where it is thickest
SLASH_FALL = 1.0  # how the body narrows from its thickest point to the head (a quarter
# cosine, so the inner edge has no corner at the thickest point)
SLASH_TIP_W = 2.0  # below this width the head goes on as a 1-pixel line
# Speed streaks in the tail: (distance in from the outer edge, where it starts along the arc).
SLASH_STREAKS = ((0.5, 0.03), (3.0, 0.13))

# Spark, darkest first: deep gold (fading ray tips), gold, pale gold, cream, near-white core
# (light and warm-neutral, so both game tints still read).
SPARK = ramp("#f6c35a", below=1, above=3, step_l=0.06)

# Ground hit purple: the game's ground_hit_color (data/presentation/combat_visuals.tres).
GROUND_HIT = "#c766ff"


def _violet_ramp() -> list[str]:
    """Six violet steps around GROUND_HIT, darkest first: deep body, body, mid, the ground-hit
    purple itself, lilac, and a near-white lilac for the bright top edge. Hue stays violet (no
    warm drift toward pink in the lights), shadows lean blue-violet."""
    L, C, h = to_oklch(GROUND_HIT)
    steps = ((-0.39, 0.57, -16.0), (-0.29, 0.75, -11.0), (-0.19, 0.88, -6.0), (-0.07, 0.97, -2.0),
             (0.05, 0.75, 1.0), (0.21, 0.31, 4.0))
    return [from_oklch(L + dl, C * dc, h + dh) for dl, dc, dh in steps]


VIOLET = _violet_ramp()
WAVE = VIOLET  # the crest's energy, darkest first; WAVE[5] is the bright top edge
EARTH = M["dirt"].colors

# Crest: a rolling wall of violet energy. Its top edge as (top row, number of columns) runs from
# WAVE_BODY_X on: flat over the crest, then a rounded shoulder whose stair runs shrink steadily
# (a clean convex curve, no wobble).
WAVE_BODY_X = 14
WAVE_TOP_RUNS = ((2, 2), (3, 6), (4, 5), (5, 4), (6, 3), (7, 2), (8, 2), (9, 1), (10, 1), (11, 1),
                 (12, 1), (13, 1))
# Shading under the top edge, by depth in pixels: the bright edge, a lit band, then the glowing
# body; the bottom WAVE_FOOT rows sit in the dark where the energy leaves the ground.
WAVE_BANDS = (5, 4, 3, 3, 2)
WAVE_FOOT = 2
# Energy tongues licking up off the top edge and trailing back: (column, height in pixels).
WAVE_TONGUES = ((22, 3), (29, 2))
# Light streaks running back along the body, parallel to the top edge: (first column, length,
# depth under the edge).
WAVE_STREAKS = ((15, 6, 5), (23, 5, 5), (18, 4, 8), (29, 3, 4))
# The ridge of earth the wave tears up along its foot: height in pixels per column from
# WAVE_EARTH_X (0 = a gap where the energy reaches the ground). Jagged, ends with the body.
WAVE_EARTH_X = 7
WAVE_EARTH = (1, 2, 3, 3, 2, 1, 0, 1, 2, 2, 3, 2, 1, 1, 0, 1, 2, 2, 1, 1, 2, 3, 2, 1, 0, 1, 2, 2,
              1, 1, 2, 1, 1, 1)
# The back fades so neighbouring crests merge into one front: alpha share from this column on,
# two columns per step, gone by the last.
WAVE_FADE_X = 34
WAVE_FADE = (0.85, 0.7, 0.55, 0.4, 0.25, 0.12, 0.0)

# AP gem (cyan) and its empty socket.
GEM = ramp("#4cc8ea", below=3, above=2) + ["#e4fdff"]  # 7 colours, darkest first; last = glint
GEM_OUT = darken_for_outline(GEM[0])
SOCKET = ramp("#3e3e56", below=2, above=3, step_l=0.1)

# Sword icon.
BLADE = M["blade"].colors
HILT = M["gold"].colors
GRIP = M["leather"].colors

def _lock_gold() -> list[str]:
    """The padlock's body: the HUD's gold (the same tones as the sword's hilt), with its darkest
    step swapped for a deep shade taken from the gold's own hue (the kit's darkest gold is orange
    and made the keyhole look like a second material)."""
    gold = M["gold"].colors
    L, C, h = to_oklch(gold[1])
    return [from_oklch(L - 0.12, C * 0.85, h + 4.0)] + gold[1:]


LOCK_BODY = _lock_gold()
SHACKLE = M["iron"].colors


# --- Helpers ---------------------------------------------------------------------------------

def _rgba(colors: list[str], idx: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """An RGBA image from per-pixel ramp indices and alpha (0 = clear)."""
    H, W = idx.shape
    out = np.zeros((H, W, 4), dtype=np.uint8)
    lut = np.array([rgba8(c) for c in colors], dtype=np.uint8)
    on = alpha > 0
    out[on] = lut[np.clip(idx[on], 0, len(colors) - 1)]
    out[..., 3] = np.where(on, alpha, 0).astype(np.uint8)
    return out


def _supersample(W: int, H: int, ss: int = 4) -> tuple[np.ndarray, np.ndarray]:
    """Sample point coordinates (H, W, ss*ss) inside every pixel."""
    o = (np.arange(ss) + 0.5) / ss
    oy, ox = np.meshgrid(o, o, indexing="ij")
    ys = np.arange(H)[:, None, None] + oy.reshape(1, 1, -1)
    xs = np.arange(W)[None, :, None] + ox.reshape(1, 1, -1)
    return np.broadcast_to(xs, (H, W, ss * ss)), np.broadcast_to(ys, (H, W, ss * ss))


def _neighbours(on: np.ndarray) -> np.ndarray:
    """How many of the 8 pixels around each pixel are set."""
    H, W = on.shape
    pad = np.pad(on, 1)
    return sum(pad[1 + dy:H + 1 + dy, 1 + dx:W + 1 + dx].astype(np.int32)
               for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dx or dy)


def _drop_lonely(img: np.ndarray) -> np.ndarray:
    """Clears pixels with no visible neighbour (8 around): stray specks."""
    on = img[..., 3] > 0
    out = img.copy()
    out[on & (_neighbours(on) == 0)] = 0
    return out


def _step(values: np.ndarray, edges: list[float], levels: list[int]) -> np.ndarray:
    """Maps values to levels[i] for the first edge they are below (levels has one more entry)."""
    out = np.full(np.shape(values), levels[-1], dtype=np.int32)
    for e, lv in reversed(list(zip(edges, levels))):
        out = np.where(values < e, lv, out)
    return out


# --- Effects ---------------------------------------------------------------------------------

def make_shadow() -> np.ndarray:
    """A soft violet-black ellipse: flat and dense over the middle half, then falling off in even
    steps to nothing at the rim (no ring, no hard edge)."""
    W, H = 32, 12
    xs, ys = _supersample(W, H, 4)
    d = np.sqrt(((xs - 16.0) / 15.8) ** 2 + ((ys - 6.0) / 5.9) ** 2)
    # Strength averaged over each pixel (smooth contours), then snapped to even steps.
    t = (np.clip((1.0 - d) / (1.0 - SHADOW_FLAT), 0.0, 1.0) ** 0.75).mean(-1)
    q = (np.round(SHADOW_MAX * t / SHADOW_STEP) * SHADOW_STEP).astype(np.int32)
    q = np.minimum(q, SHADOW_MAX)
    idx = np.zeros((H, W), dtype=np.int32)
    return _rgba([SHADOW_INK], idx, q)


def _arc_path(cx: float, cy: float, rad: float, a0: float, a1: float, s0: float,
              s1: float) -> list[tuple[int, int, float]]:
    """A clean 1-pixel arc (x, y, s) at radius `rad` between arc positions s0 and s1: one pixel
    per step, with the L-shaped corner pixels removed (a "pixel-perfect" line)."""
    pts: list[tuple[int, int, float]] = []
    for s in np.linspace(s0, s1, 600):
        ang = a0 + (a1 - a0) * s
        x = int(math.floor(cx + rad * math.cos(ang)))
        y = int(math.floor(cy + rad * math.sin(ang)))
        if not pts or pts[-1][:2] != (x, y):
            pts.append((x, y, float(s)))
    out: list[tuple[int, int, float]] = []
    for i, p in enumerate(pts):
        if out and i < len(pts) - 1:
            q, n = out[-1], pts[i + 1]
            if abs(q[0] - n[0]) == 1 and abs(q[1] - n[1]) == 1:
                continue  # p is the corner of an L between q and n
        out.append(p)
    return out


def make_slash() -> np.ndarray:
    """A crescent swing trail arcing over the top and down to the lower right (a strike going
    right). The body swells to SLASH_THICK mid-swing and tapers into a 1-pixel line ending in one
    bright point; across it runs a pale rim, a white core, then pale blue and blue on the inside.
    The tail at the upper left is two thin speed streaks that fade out. Sampled at pixel centres,
    so both edges are clean digital curves."""
    W = H = 32
    cx, cy, R = SLASH_CENTRE[0], SLASH_CENTRE[1], SLASH_R
    a0, a1 = math.radians(SLASH_ARC[0]), math.radians(SLASH_ARC[1])  # tail -> head
    s_body, s_peak = SLASH_BODY
    yy, xx = np.mgrid[0:H, 0:W] + 0.5
    r = np.hypot(xx - cx, yy - cy)
    ang = np.arctan2(yy - cy, xx - cx)
    ang = np.where(ang < a0 - 0.5, ang + 2.0 * math.pi, ang)  # one continuous range over the arc
    s = (ang - a0) / (a1 - a0)  # 0 tail .. 1 head
    sc = np.clip(s, 0.0, 1.0)
    rise = np.clip((sc - s_body) / (s_peak - s_body), 0.0, 1.0)
    rise = rise * rise * (3.0 - 2.0 * rise)
    thick = np.where(sc < s_peak, 2.0 + (SLASH_THICK - 2.0) * rise,
                     SLASH_THICK * np.cos(0.5 * math.pi * (sc - s_peak) / (1.0 - s_peak))
                     ** SLASH_FALL)
    s_head = s_peak + (1.0 - s_peak) * (2.0 / math.pi) * math.acos(
        (SLASH_TIP_W / SLASH_THICK) ** (1.0 / SLASH_FALL))
    on = (s >= s_body) & (s <= s_head) & (r <= R) & (r > R - thick)
    u = (R - r) / np.maximum(thick, 1e-6)  # 0 outer edge .. 1 inner edge
    # Thin parts are white with a pale inner edge; thick parts get the full set of bands, with
    # the rim taken from the mask itself (pixels whose outer neighbour is clear) so it is one
    # unbroken pixel line.
    pad_on = np.pad(on, 1)
    pad_r = np.pad(r, 1)
    rim = np.zeros_like(on)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        n_on = pad_on[1 + dy:H + 1 + dy, 1 + dx:W + 1 + dx]
        n_r = pad_r[1 + dy:H + 1 + dy, 1 + dx:W + 1 + dx]
        rim |= on & ~n_on & (n_r > R)
    # The darker inner bands only where the body is thick enough to hold them, so the bands
    # never flip order where the thin and thick parts meet.
    bands = _step(u, [0.5, 0.68, 0.86], [4, 3, 2, 1])
    bands = np.maximum(bands, np.where(thick < 4.5, 3, np.where(thick < 6.0, 2, 1)))
    idx = np.where(thick < 3.5, np.where(u < 0.67, 4, 3), np.where(rim, 3, bands))
    sv = np.where(on, sc, 0.0)
    # The thin parts are clean 1-pixel arcs: the speed streaks (very pale) running into the body,
    # and the head (white) running out of it to a point.
    lines = [(R - d, s0, s_body + (0.04 if d < 1.0 else -0.01), 3) for d, s0 in SLASH_STREAKS]
    lines.append((R - 0.5, s_head - 0.02, 1.0, 4))
    for rad, s0, s1, col in lines:
        for (x, y, sp) in _arc_path(cx, cy, rad, a0, a1, s0, s1):
            if 0 <= x < W and 0 <= y < H and not on[y, x]:
                on[y, x] = True
                idx[y, x] = col
                sv[y, x] = sp
    alpha = np.where(on, _step(sv, [0.1, 0.18, 0.26], [90, 150, 210, 255]), 0)
    return _drop_lonely(_rgba(SLASH, idx, alpha))


def make_spark() -> np.ndarray:
    """A sharp 4-point star: a near-white diamond core in a cream ring with gold corners, and four
    1-pixel rays going pale gold, gold, then deep gold fading out at the tips. Light and warm-neutral,
    so both game tints (warm white strikes, rot-green deaths) still read."""
    deep, gold, pale, cream, white = SPARK
    rows = [
        "................",
        ".......4........",
        ".......3........",
        ".......2........",
        ".......1........",
        "......2C2.......",
        ".....2CWC2......",
        ".4321CWWWC1234..",
        ".....2CWC2......",
        "......2C2.......",
        ".......1........",
        ".......2........",
        ".......3........",
        ".......4........",
        "................",
        "................",
    ]
    cv = Canvas(16, 16)
    cv.ascii(rows, {"W": white, "C": cream, "1": pale, "2": gold, "3": (deep, 220),
                    "4": (deep, 120)})
    return cv.a


# The crest's head, drawn by hand: the lip curls over toward the left (the way the wave travels)
# and hangs free over open ground; under it the leading face is lit (it faces the light), with
# one dark line of shadow under the lip, so the curl reads by shading, not as a hole. Digits are
# WAVE indices, letters earth (a darkest .. e lightest); clods of torn earth are flung up ahead of
# the face and violet droplets off the lip, getting smaller as they fly.
WAVE_HEAD = [
    "..............",
    ".4............",
    "...44....55555",
    "...44..5544444",
    "......54433333",
    ".....544223333",
    ".de..5421.4333",
    ".cb..42...4333",
    "..........4333",
    "...ed.....4332",
    "...cb......433",
    "...ba......432",
    "...........432",
    ".ed.........43",
    ".ba.........43",
    "............43",
]
# The droplets in WAVE_HEAD thin out the farther they fly: ((x, y), alpha).
WAVE_DROPS = (((1, 1), 140), ((3, 2), 230), ((4, 2), 230), ((3, 3), 230), ((4, 3), 230))


def _wave_top_rows() -> dict[int, int]:
    """Top row of the body for each column from WAVE_BODY_X on."""
    tops: dict[int, int] = {}
    x = WAVE_BODY_X
    for row, n in WAVE_TOP_RUNS:
        for _ in range(n):
            tops[x] = row
            x += 1
    return tops


def make_shockwave() -> np.ndarray:
    """The crest of a ground wave: a rolling wall of violet ground-hit energy surging left (the
    way it travels) over a broken ridge of torn earth. A curling lip over a lit face at the front,
    a bright lilac top edge with tongues of energy licking off it, a rounded shoulder at the back
    that fades out (so neighbouring crests merge into one front), clods of earth thrown ahead."""
    W, H = 64, 16
    idx = np.full((H, W), -1, dtype=np.int32)  # WAVE index, -1 = clear
    earth = np.full((H, W), -1, dtype=np.int32)  # EARTH index, -1 = none

    # The body: bands that follow the top edge (a glow), dark only at the foot.
    tops = _wave_top_rows()
    for x, top in tops.items():
        for y in range(top, H):
            idx[y, x] = WAVE_BANDS[min(y - top, len(WAVE_BANDS) - 1)]
            if y >= H - WAVE_FOOT and y - top >= len(WAVE_BANDS) - 1:
                idx[y, x] = 1
    for x0, n, depth in WAVE_STREAKS:
        for x in range(x0, x0 + n):
            y = tops[x] + depth
            if y < H - WAVE_FOOT and idx[y, x] == 2:
                idx[y, x] = 3
    # Tongues of flame: a lit base on the edge, narrowing and trailing back to a bright tip.
    for x0, h in WAVE_TONGUES:
        top = tops[x0]
        shape = {3: ((-1, 0, "544"), (-2, 2, "54"), (-3, 4, "5")),
                 2: ((-1, 0, "54"), (-2, 2, "5"))}[h]
        for dy, dx, cols in shape:
            for k, ch in enumerate(cols):
                idx[top + dy, x0 + dx + k] = int(ch)
    # The hand-drawn head over the front of the body.
    for y, row in enumerate(WAVE_HEAD):
        for x, ch in enumerate(row):
            if ch.isdigit():
                idx[y, x] = int(ch)
            elif ch in "abcde":
                earth[y, x] = "abcde".index(ch)
    # The torn earth ridge along the foot: up-slopes and peaks catch the light (it comes from the
    # upper left), down-slopes stay in shade, the bottom row is darker.
    for i, h in enumerate(WAVE_EARTH):
        x = WAVE_EARTH_X + i
        left = WAVE_EARTH[i - 1] if i else 0
        for k in range(h):
            y = H - 1 - k
            if k == h - 1:
                earth[y, x] = 4 if h > left else (3 if h == left else 2)
            else:
                earth[y, x] = 1 if k == 0 else 2

    out = np.zeros((H, W, 4), dtype=np.uint8)
    wave_lut = np.array([rgba8(c) for c in WAVE], dtype=np.uint8)
    earth_lut = np.array([rgba8(c) for c in EARTH], dtype=np.uint8)
    on = idx >= 0
    out[on] = wave_lut[idx[on]]
    dirt = earth >= 0
    out[dirt] = earth_lut[earth[dirt]]
    for (x, y), a in WAVE_DROPS:
        if out[y, x, 3]:
            out[y, x, 3] = a

    # The back fades so neighbouring crests merge into one front.
    fade = np.ones(W)
    for x in range(WAVE_FADE_X, W):
        fade[x] = WAVE_FADE[min((x - WAVE_FADE_X) // 2, len(WAVE_FADE) - 1)]
    out[..., 3] = np.round(out[..., 3] * fade[None, :]).astype(np.uint8)
    out[out[..., 3] == 0] = 0
    return out


# --- HUD icons -------------------------------------------------------------------------------

def _icon(size: int, rows: list[str], legend: dict[str, str], outline: str | None = INK) -> np.ndarray:
    """A hand-drawn icon; with `outline`, a 1-pixel outline is added around it (and inside its
    holes), so the grid only holds the fill."""
    c = Canvas(size, size)
    c.ascii(rows, legend)
    if outline:
        c.outline(outline)
    return c.a


def make_ap_pip() -> np.ndarray:
    """A filled AP gem: a faceted cyan diamond lit from the upper left (light upper facets with a
    bright ridge and glint, darker lower facets)."""
    return _icon(10, [
        "....oo....",
        "...oWTo...",
        "..oWHTLo..",
        ".oWHHTLLo.",
        "oHHHHTLLLo",
        "oMMMMbbbbo",
        ".oMMMbbdo.",
        "..oMMbdo..",
        "...oMdo...",
        "....oo....",
    ], {"o": GEM_OUT, "W": GEM[6], "T": GEM[5], "H": GEM[4], "L": GEM[3], "M": GEM[2], "b": GEM[1],
        "d": GEM[0]}, outline=None)


def make_ap_pip_empty() -> np.ndarray:
    """The empty AP socket: the same diamond, dark and recessed (shadowed upper left inside, a lit
    lip lower right), its rim light enough to keep the diamond shape on the dark panel."""
    return _icon(10, [
        "....oo....",
        "...oRRo...",
        "..oRddRo..",
        ".oRdddsRo.",
        "oRdddsssRo",
        "oRdsssssLo",
        ".oRsssLLo.",
        "..oRsLLo..",
        "...oLLo...",
        "....oo....",
    ], {"o": INK, "R": SOCKET[4], "L": SOCKET[5], "d": SOCKET[0], "s": SOCKET[1]}, outline=None)


def make_hit_normal() -> np.ndarray:
    """A small sword pointing up-right: a pointed blade (light edge, mid, shaded edge), a
    two-pixel gold crossguard with a bright boss, a leather grip and a knob pommel, chunky enough
    to read at 18 px. A hit you parry or dodge."""
    return _icon(12, [
        "............",
        "..........W.",
        ".........W..",
        "........WL..",
        ".......WLs..",
        "...G..WLs...",
        "...gGWLs....",
        "....gKs.....",
        "...pPgG.....",
        ".QpP..gG....",
        ".QQ.........",
        "............",
    ], {"W": BLADE[4], "L": BLADE[3], "s": BLADE[1], "G": HILT[3], "K": HILT[4], "g": HILT[1],
        "P": GRIP[3], "p": GRIP[1], "Q": HILT[2]})


def make_hit_ground() -> np.ndarray:
    """The shockwave crest in small (its colours, the ground-hit purple): a lip curling left that
    hangs free over open ground (no hole for the outline to fill), a lit face leaning forward, a
    rounded shoulder, over a strip of torn earth. A hit you jump."""
    return _icon(12, [
        "............",
        "....TTTT....",
        "..TTLLLLTT..",
        ".TLLMMMMLLT.",
        ".TLmmLMMMML.",
        ".Lm..LMMMMM.",
        ".....LMMMMM.",
        "......LMmMM.",
        "......LmmmD.",
        ".EEf.EEEfEE.",
        ".effeffeffe.",
        "............",
    ], {"T": WAVE[5], "L": WAVE[4], "M": WAVE[3], "m": WAVE[2], "D": WAVE[1], "E": EARTH[3],
        "e": EARTH[1], "f": EARTH[2]})


# Forced-choice hits (card #187): the game's rend_hit_color (bone, near the PARRY readout's
# yellow) and sweep_hit_color (sickly green, near the DODGE readout's green).
REND_HIT = "#f5db94"
SWEEP_HIT = "#99db38"
REND = ramp(REND_HIT, below=3, above=1, step_l=0.1)  # 5 colours, darkest first
SWEEP = ramp(SWEEP_HIT, below=3, above=1, step_l=0.1)


def make_hit_rend() -> np.ndarray:
    """Three claw gashes raking down to the left, in bone: bright tips at the top, thick middles,
    shaded thin tails; the middle gash longest. A hit only a parry stops (a dodge or a jump is the
    wrong button)."""
    return _icon(12, [
        "............",
        "......W.....",
        "...W..WL..W.",
        "...WL.LL..WL",
        "..WLL.LM.WLL",
        "..LLM.LM.LLM",
        "..LM.LMs.LM.",
        ".LMs.LM..Ms.",
        ".Ms..Ms..s..",
        ".s...M......",
        ".....s......",
        "............",
    ], {"W": REND[4], "L": REND[3], "M": REND[2], "s": REND[1]})


def make_hit_sweep() -> np.ndarray:
    """A wide crescent, the path of a low swing from one side to the other, in sickly green: thin
    bright tips up at both ends, the thick shaded belly at the bottom. Too wide to parry or jump
    over: a hit only a dodge avoids."""
    return _icon(12, [
        "............",
        "............",
        ".T........T.",
        ".LT......TL.",
        ".LT......TL.",
        ".MLT....TLM.",
        "..MLTTTTLM..",
        "..mMLLLLMm..",
        "...mmMMmm...",
        ".....dd.....",
        "............",
        "............",
    ], {"T": SWEEP[4], "L": SWEEP[3], "M": SWEEP[2], "m": SWEEP[1], "d": SWEEP[0]})


def make_hit_ranged() -> np.ndarray:
    """A thrown orb flying left, toward the party (card #278): a round ball in the sword's blade
    steel, lit from the upper left, with three gold speed lines streaming off its back (the
    middle one longest, touching the ball). Still a normal hit (parry or dodge), so it keeps the
    sword's steel and gold; its round shape and level lines read apart from the sword's diagonal
    and the rend's slanted gashes at 18 px."""
    return _icon(12, [
        "............",
        "............",
        "..LWLM......",
        ".LWWLMs.TTg.",
        ".LWWLMs.....",
        ".LWLMMsTTTg.",
        ".LLMMss.....",
        ".MMMsss.TTg.",
        "..Mssd......",
        "............",
        "............",
        "............",
    ], {"W": BLADE[4], "L": BLADE[3], "M": BLADE[2], "s": BLADE[1], "d": BLADE[0], "T": HILT[3],
        "g": HILT[2]})


def make_lock() -> np.ndarray:
    """A padlock: iron shackle over a bevelled worn-gold body (light top and left, dark right and
    bottom) with a keyhole: a dark slot whose shaded top reads as the round head."""
    return _icon(12, [
        "............",
        "....SSSS....",
        "...Sssssd...",
        "...Sd..Sd...",
        "...Sd..Sd...",
        ".HKKKKKKKKG.",
        ".KGGakkaGGg.",
        ".KGGakkaGGg.",
        ".KGGGkkGGGg.",
        ".KGGGkkGGGg.",
        ".ggggggggga.",
        "............",
    ], {"S": SHACKLE[4], "s": SHACKLE[2], "d": SHACKLE[1], "H": LOCK_BODY[4], "K": LOCK_BODY[3],
        "G": LOCK_BODY[2], "g": LOCK_BODY[1], "a": LOCK_BODY[0], "k": INK})


def make_controller() -> np.ndarray:
    """A game controller seen from above (card #167, the "Controller recommended" screen): an
    iron body lit from the top (light edge, dark underside) with two bumpers, two grips, a cross
    pad on the left, four worn-gold buttons on the right and two sticks. Built from a few shapes
    and then shaded by depth below the top edge, so it keeps the HUD icons' flat, outlined look."""
    W, H = 32, 22
    ys, xs = np.mgrid[0:H, 0:W]
    px, py = xs + 0.5, ys + 0.5

    def rrect(x0: float, y0: float, x1: float, y1: float, r: float) -> np.ndarray:
        cx = np.clip(px, x0 + r, x1 - r)
        cy = np.clip(py, y0 + r, y1 - r)
        return (px - cx) ** 2 + (py - cy) ** 2 <= r * r

    def ellipse(cx: float, cy: float, rx: float, ry: float) -> np.ndarray:
        return ((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2 <= 1.0

    bumpers = rrect(6, 2, 12, 6, 1.5) | rrect(20, 2, 26, 6, 1.5)
    body = rrect(2, 4, 30, 14, 4.5) | ellipse(8, 14.5, 6.0, 6.0) | ellipse(24, 14.5, 6.0, 6.0)
    mask = body | bumpers
    top = np.full(W, H, dtype=int)
    for x in range(W):
        col = np.nonzero(body[:, x])[0]
        if col.size:
            top[x] = col[0]
    depth = ys - top[None, :]
    idx = np.where(depth < 1, 4, np.where(depth < 4, 3, np.where(depth < 9, 2, 1)))
    idx = np.where(bumpers & ~body, 4, idx)
    img = _rgba(SHACKLE, idx, np.where(mask, 255, 0))
    c = Canvas(W, H)
    c.a[:] = img
    # Seam between the bumpers and the body.
    for x0, x1 in ((6, 12), (20, 26)):
        for x in range(x0 + 1, x1 - 1):
            c.px(x, 5, SHACKLE[1])
    # Cross pad: a plus of ink with a lit centre.
    for dx, dy in ((0, -2), (-1, -1), (0, -1), (1, -1), (-2, 0), (-1, 0), (0, 0), (1, 0), (2, 0),
                   (-1, 1), (0, 1), (1, 1), (0, 2)):
        c.px(9 + dx, 9 + dy, INK)
    c.px(9, 9, SHACKLE[2])
    # Buttons: four gold gems in a diamond, each lit top left.
    for bx, by in ((23, 7), (26, 9), (23, 11), (20, 9)):
        c.px(bx, by, LOCK_BODY[4])
        c.px(bx + 1, by, LOCK_BODY[2])
        c.px(bx, by + 1, LOCK_BODY[2])
        c.px(bx + 1, by + 1, LOCK_BODY[1])
    # Sticks: a dark well with a lighter cap.
    for sx, sy in ((13, 13), (19, 13)):
        for dx in range(-1, 3):
            for dy in range(-1, 3):
                if not (dx in (-1, 2) and dy in (-1, 2)):
                    c.px(sx + dx, sy + dy, INK)
        c.px(sx, sy, SHACKLE[4])
        c.px(sx + 1, sy, SHACKLE[3])
        c.px(sx, sy + 1, SHACKLE[3])
        c.px(sx + 1, sy + 1, SHACKLE[2])
    c.outline(INK)
    return c.a


# --- Review pictures -------------------------------------------------------------------------

def _over(bg: tuple[int, int, int], img: np.ndarray) -> np.ndarray:
    """img alpha-blended over a flat background (opaque RGBA)."""
    a = img[..., 3:4].astype(np.float64) / 255.0
    rgb = img[..., :3].astype(np.float64) * a + np.array(bg, dtype=np.float64) * (1.0 - a)
    out = np.zeros(img.shape, dtype=np.uint8)
    out[..., :3] = np.round(rgb).astype(np.uint8)
    out[..., 3] = 255
    return out


def _scale_nearest(img: np.ndarray, px: float, py: float | None = None) -> np.ndarray:
    """Resizes an image to px x py with nearest filtering (like the HUD does)."""
    h, w = img.shape[:2]
    n = int(round(px))
    m = int(round(py if py is not None else px * h / w))
    ys = np.minimum((np.arange(m) + 0.5) * h / m, h - 1).astype(int)
    xs = np.minimum((np.arange(n) + 0.5) * w / n, w - 1).astype(int)
    return img[ys][:, xs]


def _paste(dst: np.ndarray, img: np.ndarray, x: int, y: int) -> None:
    h, w = img.shape[:2]
    H, W = dst.shape[:2]
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(W, x + w), min(H, y + h)
    if x1 <= x0 or y1 <= y0:
        return
    src = img[y0 - y:y1 - y, x0 - x:x1 - x]
    a = src[..., 3:4].astype(np.float64) / 255.0
    region = dst[y0:y1, x0:x1, :3].astype(np.float64)
    dst[y0:y1, x0:x1, :3] = np.round(src[..., :3] * a + region * (1.0 - a)).astype(np.uint8)
    dst[y0:y1, x0:x1, 3] = 255


def _tint(img: np.ndarray, rgb: tuple[float, float, float]) -> np.ndarray:
    out = img.copy()
    out[..., :3] = np.round(img[..., :3] * np.array(rgb)).astype(np.uint8)
    return out


def _squash(img: np.ndarray, sy: float) -> np.ndarray:
    """img squashed vertically by sy (nearest), like a flat ground sprite seen from a low camera."""
    h = img.shape[0]
    n = max(1, int(round(h * sy)))
    ys = np.minimum((np.arange(n) + 0.5) * h / n, h - 1).astype(int)
    return img[ys]


def _disc(dst: np.ndarray, cx: float, cy: float, r: float, ring: tuple[int, int, int],
          width: float) -> None:
    """The hit marker's dark disc with a coloured ring (hit_marker_layer.gd), for review."""
    H, W = dst.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W] + 0.5
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    inside = d <= r
    base = dst[..., :3].astype(np.float64)
    disc = base * 0.15 + np.array((10, 8, 13), dtype=np.float64) * 0.85
    dst[..., :3] = np.where(inside[..., None], np.round(disc), dst[..., :3]).astype(np.uint8)
    on_ring = np.abs(d - r) <= width * 0.5
    dst[on_ring, :3] = ring


def _floor(W: int, H: int) -> np.ndarray:
    """The arena floor (the game's floor tile, tiled) for context, or flat dark if missing."""
    from PIL import Image

    path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))), "assets", "sprites", "env", "floor_tile.png")
    out = np.zeros((H, W, 4), dtype=np.uint8)
    out[..., :3] = (34, 31, 40)
    out[..., 3] = 255
    if os.path.exists(path):
        tile = np.array(Image.open(path).convert("RGBA"))
        th, tw = tile.shape[:2]
        reps = np.tile(tile, (H // th + 1, W // tw + 1, 1))[:H, :W]
        out[..., :3] = reps[..., :3]
    return out


def review_sheet(parts: dict[str, np.ndarray]) -> np.ndarray:
    """Everything at 1x on the game's dark floor colour; the HUD icons at the sizes the HUD shows
    them (nearest filter) on the panel colour and on the hit marker discs; the spark tinted like a
    strike and a death burst; the slash grown as it fades; the shadow as the low camera sees it;
    and five crests placed like the game's travelling wave front on the dark floor and on the
    real floor tile (each nearer one 13 px left and 6 px lower, drawn on top)."""
    W, H = 400, 200
    bg = (34, 31, 40)
    sheet = np.zeros((H, W, 4), dtype=np.uint8)
    sheet[..., :3] = bg
    sheet[..., 3] = 255
    x = 2
    for name in ("shadow", "slash", "spark", "shockwave", "ap_pip", "ap_pip_empty", "hit_normal",
                 "hit_ground", "lock"):
        img = parts[name]
        _paste(sheet, img, x, 2)
        x += img.shape[1] + 3
    # HUD sizes on the panel colour: gems at 18 px (max AP 9) and 20 px, hit icons at 18 px
    # (timeline), 30 px (intent) and 42 px (active), the lock at 56 px.
    panel = (13, 13, 18)
    sheet[38:102, 2:212, :3] = panel
    y = 40
    for i in range(4):
        _paste(sheet, _scale_nearest(parts["ap_pip"], 18), 4 + i * 20, y)
    for i in range(2):
        _paste(sheet, _scale_nearest(parts["ap_pip_empty"], 18), 84 + i * 20, y)
    for i in range(2):
        _paste(sheet, _scale_nearest(parts["ap_pip"], 20), 4 + i * 22, y + 22)
    _paste(sheet, _scale_nearest(parts["ap_pip_empty"], 20), 48, y + 22)
    _paste(sheet, _scale_nearest(parts["hit_normal"], 18), 4, y + 44)
    _paste(sheet, _scale_nearest(parts["hit_ground"], 18), 24, y + 44)
    _paste(sheet, _scale_nearest(parts["hit_normal"], 30), 76, y + 22)
    _paste(sheet, _scale_nearest(parts["hit_ground"], 30), 108, y + 22)
    _paste(sheet, _scale_nearest(parts["hit_rend"], 18), 44, y + 44)
    _paste(sheet, _scale_nearest(parts["hit_sweep"], 18), 64, y + 44)
    _paste(sheet, _scale_nearest(parts["hit_ranged"], 18), 128, y)  # the 18 px row has no room left
    _paste(sheet, _scale_nearest(parts["lock"], 56), 152, y + 2)
    # Hit markers: the icon on a dark disc with the normal (red-orange) or ground (purple) ring.
    _disc(sheet, 150, 168, 25, (230, 110, 60), 3)
    _paste(sheet, _scale_nearest(parts["hit_normal"], 42), 129, 147)
    _disc(sheet, 210, 168, 25, (199, 102, 255), 3)
    _paste(sheet, _scale_nearest(parts["hit_ground"], 42), 189, 147)
    # Spark tinted for a strike and for a death burst (and shrunk as it flies); the slash grown
    # as it fades.
    _paste(sheet, _tint(parts["spark"], (1.0, 0.95, 0.8)), 216, 40)
    _paste(sheet, _tint(parts["spark"], (0.72, 0.88, 0.36)), 234, 40)
    _paste(sheet, _scale_nearest(_tint(parts["spark"], (1.0, 0.95, 0.8)), 10), 219, 58)
    _paste(sheet, _scale_nearest(_tint(parts["spark"], (0.72, 0.88, 0.36)), 10), 237, 58)
    _paste(sheet, _scale_nearest(_tint(parts["spark"], (1.0, 0.95, 0.8)), 6), 222, 72)
    _paste(sheet, _scale_nearest(_tint(parts["spark"], (0.72, 0.88, 0.36)), 6), 240, 72)
    big = _scale_nearest(parts["slash"], 42).copy()
    big[..., 3] = (big[..., 3] * 0.5).astype(np.uint8)
    _paste(sheet, big, 256, 38)
    _paste(sheet, parts["slash"], 261, 43 + 42)
    # The shadow as seen from the combat camera (a flat sprite seen at a low angle).
    _paste(sheet, _squash(parts["shadow"], 0.28), 216, 90)
    # A wave front: five crests along the party line, on the dark floor and on the floor tile.
    for i in range(5):
        _paste(sheet, parts["shockwave"], 4 + (4 - i) * 13, 112 + i * 6)
    floor = _floor(118, 80)
    for i in range(5):
        _paste(floor, parts["shockwave"], 2 + (4 - i) * 13, 14 + i * 6)
    _paste(floor, _squash(parts["shadow"], 0.28), 70, 70)
    _paste(floor, _squash(parts["shadow"], 0.28), 30, 4)
    _paste(floor, parts["slash"], 84, 2)
    _paste(floor, _tint(parts["spark"], (0.72, 0.88, 0.36)), 92, 40)
    _paste(floor, _tint(parts["spark"], (1.0, 0.95, 0.8)), 100, 58)
    _paste(sheet, floor, W - floor.shape[1] - 2, H - floor.shape[0] - 2)
    return sheet


def wave_front_view(crest: np.ndarray, u: float) -> np.ndarray:
    """Five crests placed the way the game places them (timed_sequence_runner._update_wave) and
    seen through the combat camera (combat_visuals.tres: camera (0.8, 3.4, 10) looking at (0, 1, 0),
    fov 40, fx_pixel_size 0.045), at travel share u (1 = reaching the party). The three heroes are
    grey posts for scale, the floor a faint grid. 1600x900 viewport, cropped."""
    VW, VH = 1600, 900
    f = (VH / 2) / math.tan(math.radians(20.0))
    cam = np.array([0.8, 3.4, 10.0])
    fwd = np.array([0.0, 1.0, 0.0]) - cam
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0.0, 1.0, 0.0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)

    def proj(p: np.ndarray) -> tuple[float, float, float]:
        d = p - cam
        z = float(d @ fwd)
        return VW / 2 + f * float(d @ right) / z, VH / 2 - f * float(d @ up) / z, z

    img = np.zeros((VH, VW, 4), dtype=np.uint8)
    img[..., :3] = (40, 37, 44)
    img[..., 3] = 255
    for g in np.arange(-8.0, 8.01, 1.0):
        for t in np.linspace(-8.0, 8.0, 700):
            for p in (np.array([g, 0.0, t]), np.array([t, 0.0, g])):
                x, y, z = proj(p)
                if z > 0 and 0 <= x < VW and 0 <= y < VH:
                    img[int(y), int(x), :3] = (52, 48, 58)
    party = [np.array(p) for p in ((-2.1, 0.0, -1.5), (-2.9, 0.0, 0.0), (-3.7, 0.0, 1.5))]
    for p in party:
        x0, y0, z = proj(p)
        _, y1, _ = proj(p + np.array([0.0, 1.6, 0.0]))
        w = f * 0.6 / z
        img[int(y1):int(y0), int(x0 - w / 2):int(x0 + w / 2), :3] = (70, 66, 74)
    a, b = party[0], party[-1]
    along = b - a
    along /= np.linalg.norm(along)
    normal = np.array([along[2], 0.0, -along[0]])
    enemy = np.array([2.5, 0.0, 0.0])
    if normal @ (enemy - a) < 0:
        normal = -normal
    front = normal * max(float(normal @ (enemy - a)), 2.0) * (1.0 - u)
    margin = along * 0.8
    pts = [(a - margin) + ((b + margin) - (a - margin)) * (i / 4.0) + front for i in range(5)]
    pts.sort(key=lambda p: -proj(p)[2])  # far ones first, near ones drawn on top
    h, w = crest.shape[:2]
    for p in pts:
        x, y, z = proj(p)
        s = f * 0.045 / z
        spr = _scale_nearest(crest, w * s, h * s)
        _paste(img, spr, int(round(x - spr.shape[1] / 2)), int(round(y - spr.shape[0])))
    return img[300:780, 0:1000]


def compare_old(parts: dict[str, np.ndarray]) -> np.ndarray | None:
    """Old placeholders (top row) over the new art (bottom row), 1x on the dark floor colour."""
    from PIL import Image

    old_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "preview",
                           "_old")
    names = (("fx", "shadow"), ("fx", "slash"), ("fx", "spark"), ("fx", "shockwave"),
             ("ui", "ap_pip"), ("ui", "ap_pip_empty"), ("ui", "hit_normal"), ("ui", "hit_ground"),
             ("ui", "lock"))
    W = sum(parts[n].shape[1] + 3 for _, n in names) + 2
    sheet = np.zeros((72, W, 4), dtype=np.uint8)
    sheet[..., :3] = (34, 31, 40)
    sheet[..., 3] = 255
    x = 2
    for group, n in names:
        path = os.path.join(old_dir, group, n + ".png")
        if os.path.exists(path):
            old = np.array(Image.open(path).convert("RGBA"))
            _paste(sheet, old[:34, :parts[n].shape[1]], x, 2)
        _paste(sheet, parts[n], x, 37)
        x += parts[n].shape[1] + 3
    return sheet


def _save_sheet(ctx, name: str, img: np.ndarray, scale: int) -> str:
    """An already-opaque review sheet saved once (ctx.extra would repeat it on three
    backgrounds)."""
    from PIL import Image

    path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "preview",
                        ctx.module, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    h, w = img.shape[:2]
    Image.fromarray(img.astype(np.uint8), "RGBA").resize((w * scale, h * scale),
                                                          Image.NEAREST).save(path)
    return path


def build(ctx) -> None:
    parts = {
        "shadow": make_shadow(),
        "slash": make_slash(),
        "spark": make_spark(),
        "shockwave": make_shockwave(),
        "ap_pip": make_ap_pip(),
        "ap_pip_empty": make_ap_pip_empty(),
        "hit_normal": make_hit_normal(),
        "hit_ground": make_hit_ground(),
        "hit_rend": make_hit_rend(),
        "hit_sweep": make_hit_sweep(),
        "hit_ranged": make_hit_ranged(),
        "lock": make_lock(),
        "controller": make_controller(),
    }
    for name in ("shadow", "slash", "spark", "shockwave"):
        ctx.save("sprites/fx/%s.png" % name, parts[name])
    for name in ("ap_pip", "ap_pip_empty", "hit_normal", "hit_ground", "hit_rend", "hit_sweep", "hit_ranged",
                 "lock", "controller"):
        ctx.save("sprites/ui/%s.png" % name, parts[name])
    sheet = review_sheet(parts)
    _save_sheet(ctx, "review_1x.png", sheet, 1)
    _save_sheet(ctx, "review_4x.png", sheet, 4)
    _save_sheet(ctx, "old_vs_new_4x.png", compare_old(parts), 4)
    fronts = np.concatenate([wave_front_view(parts["shockwave"], u) for u in (0.5, 0.9)], axis=0)
    _save_sheet(ctx, "review_wave_front.png", fronts, 1)
