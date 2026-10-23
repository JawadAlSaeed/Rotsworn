"""Props that make each zone its own place (DESIGN.md 8.12), the critters that live there, and the
particles that drift through it.

Ashen Ruins: a broken arch, a headless statue, a fallen column, rubble, a brazier, a torn banner,
gravestones, a dry fountain, a low broken wall, bones. Sunken Bog (swamp and jungle): reeds, a
mangrove, a tree hung with moss, a giant mushroom, a fallen log, a hut on stilts, a swamp lantern,
ferns. Rotten Hollow (rotting forest): bushes, a stump, thorns, a broken fence, a broken cart, a
well, a signpost, a grave cross, a dead pine. Critters: a crow, a frog, a rat (four frames each:
idle, idle, move, move). Particles: a mote, an ash flake, a leaf, a spore, a mist puff, a rain streak
and a splash (weather, card #303).

Same rules as env_props: small 3D models in the camera-aligned frame (x = screen right, y = up,
z = toward the viewer), cut flat on the ground, outlined; tiny or flat things (reeds, ferns, the
critters, the particles) are drawn in 2D. Anything that glows keeps its body dark (the game's
self_glow lights the whole sprite).
"""
from __future__ import annotations

import math

import numpy as np

from kit.canvas import Canvas
from kit.palette import INK, M, Material
from kit.sdf import (Box, Capsule, Cylinder, Ellipsoid, Prism, RoundCone, Sphere, Subtract, Torus,
                     Union, rot)

from assets.env_props import (BARK, BARK_PALE, CANOPY, COLUMN, DEAD_LEAF, FRACTURE, GroundCut, LAMP_IRON,
                              LANTERN, MOSS, ROT, ROT_BARK, SHROOM_STEM, SOIL, STONE, _face, check,
                              finish_prop, ink_outline, lch_mat, mat, render_fit)

EMBER = Material("life_ember", M["glow_amber"].colors, emissive=True, glow_index=2,
                 outline=ink_outline("#c26a2a", 0.25))
CLOTH_RED = mat("life_banner", "#7a2a28", below=2, above=1, wrap=0.5)
GOLD_WORN = mat("life_gold", "#a8873f", below=2, above=1, spec=0.4, wrap=0.3)
BONE = mat("life_bone", "#cfc4a0", below=2, above=1, wrap=0.35)
THATCH = mat("life_thatch", "#7d6a42", below=2, above=1, wrap=0.45)
PLANK = mat("life_plank", "#5e4634", below=2, above=1, wrap=0.3)
MANGROVE = mat("life_mangrove", "#4a4234", below=2, above=1, wrap=0.3)
SWAMP_LEAF = lch_mat("life_swamp_leaf", [(0.27, 0.05, 150.0), (0.34, 0.06, 145.0), (0.42, 0.07, 140.0),
                                         (0.5, 0.075, 135.0)], wrap=0.4, outline_L=0.18)
HANGING_MOSS = lch_mat("life_hanging_moss", [(0.33, 0.035, 120.0), (0.41, 0.045, 118.0),
                                             (0.5, 0.05, 115.0)], wrap=0.5)
MUSH_CAP = mat("life_mush_cap", "#7b3f5c", below=2, above=1, wrap=0.4)
MUSH_SPOT = Material("life_mush_spot", M["glow_cyan"].colors, emissive=True, glow_index=2,
                     outline=ink_outline("#2f6f73", 0.22))
WATER_DARK = mat("life_water", "#2a4a46", below=1, above=2, wrap=0.3)
WOOD_DARK = mat("life_wood_dark", "#4f3a2c", below=2, above=1, wrap=0.3)

PIXEL_SIZE = {}


def _outlined(c: Canvas) -> np.ndarray:
    """A 2D prop with a free pixel above and on both sides, then the outline (the prop contract)."""
    H, W = c.a.shape[:2]
    big = Canvas(W + 4, H + 2)
    big.a[2:, 2:W + 2] = c.a
    big.outline(INK)
    return big.a


def _prop(name: str, pixel: float):
    def wrap(fn):
        PIXEL_SIZE[name] = pixel
        PROPS[name] = fn
        return fn
    return wrap


PROPS: dict = {}


# --- Ashen Ruins --------------------------------------------------------------------------------


@_prop("arch_broken", 0.055)
def make_arch_broken() -> np.ndarray:
    """Two square piers; the arch springs from the left one, curves over and breaks off in the
    air short of the right pier, which stands lower, its top shattered."""
    parts = []
    for sx, h in ((-14.0, 36.0), (14.0, 28.0)):
        parts.append(Box(COLUMN, (sx, h * 0.5, 0), (4.2, h * 0.5, 3.6), round=0.6, group="stone",
                         bumps=(0.2, 0.5, 301 + int(sx))))
        parts.append(Box(COLUMN, (sx, 2.0, 0), (5.2, 2.0, 4.4), round=0.5, group="stone"))
    parts.append(Box(COLUMN, (-14.0, 37.0, 0), (5.0, 1.4, 4.2), round=0.4, group="stone"))
    # The arch: voussoirs along a half circle from the left pier, the last few missing.
    cx, cy, r = 0.0, 36.0, 14.0
    for k in range(9):
        a0 = math.pi - k * (math.pi / 12.0)
        a1 = a0 - math.pi / 12.0
        p0 = (cx + math.cos(a0) * r, cy + math.sin(a0) * r, 0.0)
        p1 = (cx + math.cos(a1) * r, cy + math.sin(a1) * r, 0.0)
        parts.append(RoundCone(COLUMN, p0, p1, 3.6, 3.6, group="stone", bumps=(0.15, 0.6, 305 + k)))
    # Ivy hanging from the arch and the left pier.
    for x, y0, y1 in ((-16.5, 36.0, 20.0), (-11.0, 42.0, 30.0), (-4.0, 48.5, 40.0), (3.0, 49.5, 43.0)):
        parts.append(Capsule(MOSS, (x, y0, 3.6), (x - 0.5, y1, 3.8), 0.9, group="ivy", thin=True))
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 44, 58, name="arch_broken")
    return finish_prop(frame)


@_prop("statue_headless", 0.055)
def make_statue_headless() -> np.ndarray:
    """A stone knight on a square plinth, helmed, both hands on a sword held point down, a cloak
    falling behind; his left arm broken off at the elbow."""
    plinth = Box(COLUMN, (0, 5.0, 0), (6.5, 5.0, 5.0), round=0.6, group="stone", bumps=(0.15, 0.6, 311))
    cap = Box(COLUMN, (0, 10.6, 0), (7.2, 0.8, 5.6), round=0.4, group="stone")
    legs = RoundCone(STONE, (0, 11.4, 0), (0, 20.0, 0), 3.6, 3.4, group="statue", bumps=(0.12, 0.6, 312))
    cloak = RoundCone(STONE, (0, 11.6, -1.8), (0, 29.0, -1.6), 5.6, 4.0, group="statue", bumps=(0.12, 0.6, 313))
    chest = Ellipsoid(STONE, (0, 25.0, 0.6), (4.4, 5.0, 3.0), group="statue")
    shoulders = Ellipsoid(STONE, (0, 29.0, 0), (6.0, 2.2, 3.2), group="statue")
    head = Sphere(STONE, (0, 33.0, 0.2), 2.6, group="statue")
    crest = Box(STONE, (0, 35.4, 0.2), (0.6, 1.0, 2.0), group="statue")
    sword = Box(STONE, (0, 16.0, 4.0), (0.8, 6.0, 0.4), group="statue")
    hilt = Box(STONE, (0, 22.4, 4.0), (3.0, 0.6, 0.6), group="statue")
    arm = RoundCone(STONE, (4.8, 28.4, 0.6), (1.4, 23.6, 3.8), 1.6, 1.3, group="statue")
    stub = RoundCone(STONE, (-4.8, 28.4, 0.6), (-4.4, 25.4, 1.6), 1.6, 1.4, group="statue")
    broken = Cylinder(FRACTURE, (-4.4, 25.0, 1.7), 1.3, 0.4, R=rot(20.0, 0.0, 0.0), group="break")
    moss = Ellipsoid(MOSS, (-2.5, 11.4, 2.0), (3.5, 0.9, 2.4), group="moss")
    model = _face(GroundCut(Union(plinth, cap, cloak, legs, chest, shoulders, head, crest, sword, hilt, arm,
                                  stub, broken, moss)))
    frame, _ = render_fit(model, 22, 42, name="statue_headless")
    return finish_prop(frame)


@_prop("column_fallen", 0.055)
def make_column_fallen() -> np.ndarray:
    """A toppled column: three drums lying in a broken line, one cracked off at a slant."""
    parts = []
    for i, (x, z, a) in enumerate(((-12.0, 0.0, 0.0), (0.5, 1.0, 8.0), (13.0, -0.5, -12.0))):
        R = rot(0.0, a, 90.0)
        parts.append(Cylinder(COLUMN, (x, 4.6, z), 4.6, 5.6, R=R, round=0.6, group="stone",
                              bumps=(0.18, 0.6, 321 + i)))
    parts.append(Box(COLUMN, (-22.0, 2.6, 1.0), (2.4, 2.6, 2.8), round=0.6, group="stone"))
    parts.append(Ellipsoid(MOSS, (2.0, 8.6, 1.0), (5.0, 1.2, 3.0), group="moss"))
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 56, 20, centre="bbox", name="column_fallen")
    return finish_prop(frame)


@_prop("rubble", 0.05)
def make_rubble() -> np.ndarray:
    """A heap of broken blocks and chips."""
    parts = []
    blocks = ((-5.0, 2.6, 0.0, 3.4, 2.6, 2.6, 15.0), (3.0, 2.2, 1.5, 3.0, 2.2, 2.2, -20.0),
              (-0.5, 6.4, 0.5, 2.6, 2.0, 2.2, 35.0), (7.5, 1.4, -1.0, 2.0, 1.4, 1.8, 5.0),
              (-9.0, 1.2, 2.0, 1.6, 1.2, 1.4, -40.0))
    for i, (x, y, z, hx, hy, hz, a) in enumerate(blocks):
        parts.append(Box(STONE, (x, y, z), (hx, hy, hz), R=rot(0.0, a, a * 0.3), round=0.5, group="stone",
                         bumps=(0.2, 0.7, 331 + i)))
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 28, 16, centre="bbox", name="rubble")
    return finish_prop(frame)


@_prop("brazier", 0.05)
def make_brazier() -> np.ndarray:
    """An iron bowl on three legs, heaped with burning coals and a tall flame."""
    parts = []
    for i in range(3):
        t = i / 3.0 * math.tau + 0.4
        parts.append(Capsule(LAMP_IRON, (math.cos(t) * 4.0, 0.0, math.sin(t) * 3.0),
                             (math.cos(t) * 2.4, 13.0, math.sin(t) * 1.8), 0.6, group="iron", thin=True))
    bowl = Subtract(Ellipsoid(LAMP_IRON, (0, 15.0, 0), (5.6, 3.2, 4.4), group="iron"),
                    Box(LAMP_IRON, (0, 19.0, 0), (8.0, 3.0, 8.0)))
    parts.append(bowl)
    parts.append(Torus(LAMP_IRON, (0, 15.8, 0), 5.2, 0.6, group="iron"))
    parts.append(Ellipsoid(EMBER, (0, 16.4, 0.4), (4.4, 1.4, 3.2), group="coal"))
    parts.append(RoundCone(EMBER, (0, 16.0, 1.0), (0.4, 26.0, 1.2), 3.4, 0.4, group="flame"))
    parts.append(RoundCone(EMBER, (-2.0, 16.0, 1.4), (-2.8, 22.0, 1.4), 1.8, 0.3, group="flame"))
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 16, 30, name="brazier")
    return finish_prop(frame, skip_groups=("flame", "coal"))


@_prop("flame", 0.05)
def make_flame() -> np.ndarray:
    """The brazier's fire on its own (card #227): a tall flame and a short one, cut flat at the
    bottom. 3D braziers carry it as a flat sprite, so the fire stays pixel art and sways."""
    parts = [RoundCone(EMBER, (0, 0.0, 1.0), (0.4, 10.0, 1.2), 3.4, 0.4, group="flame"),
             RoundCone(EMBER, (-2.0, 0.0, 1.4), (-2.8, 6.0, 1.4), 1.8, 0.3, group="flame")]
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 12, 14, name="flame")
    return finish_prop(frame, skip_groups=("flame",))


@_prop("flame_big", 0.05)
def make_flame_big() -> np.ndarray:
    """The campfire's fire on its own (card #227): three flames round a bright core."""
    parts = [RoundCone(EMBER, (0.0, 0.0, 0.0), (0.0, 14.0, 0.0), 4.2, 0.4, group="flame"),
             RoundCone(EMBER, (-2.6, 0.0, 0.6), (-3.6, 9.0, 0.8), 2.6, 0.3, group="flame"),
             RoundCone(EMBER, (2.8, 0.0, 0.4), (3.8, 10.5, 0.6), 2.6, 0.3, group="flame"),
             RoundCone(Material("life_flame_core", ["#ffd27a", "#ffe9b0", "#fff6d8"], emissive=True, glow_index=1,
                                outline=ink_outline("#c26a2a", 0.3)), (0.0, 0.5, 3.6), (0.0, 8.0, 3.4),
                       2.0, 0.3, group="core")]
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 20, 18, name="flame_big")
    return finish_prop(frame, skip_groups=("flame", "core"))


@_prop("banner_torn", 0.05)
def make_banner_torn() -> np.ndarray:
    """A pole with a torn, faded red banner hanging from a cross bar (it sways in the wind)."""
    c = Canvas(16, 48)
    wood = M["wood_dark"].colors
    red = CLOTH_RED.colors
    gold = GOLD_WORN.colors
    c.rect(3, 2, 3, 46, wood[1])
    c.rect(4, 2, 4, 46, wood[2])
    c.rect(3, 4, 14, 5, wood[2])
    c.px(3, 1, gold[2])
    # The cloth: wider at the top, ragged tails at the bottom, a faded crown sigil.
    for y in range(6, 34):
        w = 10 - (y - 6) // 7
        x0 = 5
        rag = (y > 26) and ((y + 0) % 3 == 0)
        for x in range(x0, x0 + w):
            if rag and x % 3 == 1:
                continue
            col = red[2] if x < x0 + 3 else red[1]
            if y > 30 and (x * 7 + y) % 5 == 0:
                continue
            c.px(x, y, col)
    for x, y in ((8, 11), (10, 11), (12, 11), (8, 12), (9, 12), (10, 12), (11, 12), (12, 12), (8, 13), (12, 13)):
        c.px(x, y, gold[1])
    return _outlined(c)


@_prop("gravestone", 0.05)
def make_gravestone() -> np.ndarray:
    """A worn headstone leaning back a little, a cross cut into it, moss at its foot."""
    stone = Box(STONE, (0, 7.0, 0), (4.0, 7.0, 1.4), R=rot(-8.0, 0.0, 6.0), round=0.9, group="stone",
                bumps=(0.18, 0.6, 341))
    top_ = Cylinder(STONE, (0.7, 13.6, -0.8), 4.0, 1.4, R=rot(90.0 - 8.0, 0.0, 6.0), group="stone")
    cross = [Box(ROT_BARK, (0.6, 9.5, 1.3), (0.5, 2.8, 0.3), R=rot(-8.0, 0.0, 6.0), group="cut"),
             Box(ROT_BARK, (0.6, 10.5, 1.3), (1.8, 0.5, 0.3), R=rot(-8.0, 0.0, 6.0), group="cut")]
    moss = Ellipsoid(MOSS, (0.0, 0.6, 1.2), (4.6, 1.4, 2.0), group="moss")
    model = _face(GroundCut(Union(stone, top_, *cross, moss)))
    frame, _ = render_fit(model, 14, 22, name="gravestone")
    return finish_prop(frame)


@_prop("fountain", 0.055)
def make_fountain() -> np.ndarray:
    """A round stone basin, dry and cracked, a broken stump of its pillar in the middle."""
    basin = Cylinder(COLUMN, (0, 3.6, 0), 15.0, 3.6, round=1.2, group="stone", bumps=(0.15, 0.6, 351))
    hollow = Cylinder(COLUMN, (0, 6.0, 0), 12.6, 2.6)
    bowl = Subtract(basin, hollow, k=0.6)
    puddle = Cylinder(WATER_DARK, (0, 4.2, 0), 12.4, 0.4, group="water")
    pillar = Cylinder(COLUMN, (0, 10.0, 0), 2.6, 7.0, round=0.6, group="stone", bumps=(0.15, 0.6, 352))
    lip = Torus(COLUMN, (0, 7.0, 0), 13.8, 1.2, group="stone")
    model = _face(GroundCut(Union(bowl, puddle, pillar, lip)))
    frame, _ = render_fit(model, 40, 26, centre="bbox", name="fountain")
    return finish_prop(frame)


@_prop("wall_low", 0.055)
def make_wall_low() -> np.ndarray:
    """A low stretch of old wall, its top broken into steps, a block fallen at its foot."""
    parts = []
    for i, (x, h) in enumerate(((-12.0, 13.0), (-5.0, 16.0), (2.0, 11.0), (9.0, 7.0), (14.0, 4.0))):
        parts.append(Box(COLUMN, (x, h * 0.5, 0), (3.6, h * 0.5, 2.4), round=0.4, group="stone",
                         bumps=(0.2, 0.6, 361 + i)))
    parts.append(Box(STONE, (13.0, 1.6, 4.0), (2.4, 1.6, 2.0), R=rot(0.0, 25.0, 10.0), round=0.4, group="stone"))
    parts.append(Ellipsoid(MOSS, (-8.0, 15.6, 0.0), (4.0, 1.2, 2.6), group="moss"))
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 40, 22, centre="bbox", name="wall_low")
    return finish_prop(frame)


@_prop("bones", 0.045)
def make_bones() -> np.ndarray:
    """A skull and a few long bones in the dirt."""
    c = Canvas(18, 10)
    b = BONE.colors
    c.ellipse(5.0, 5.0, 3.0, 2.6, b[2])
    c.rect(3, 6, 7, 8, b[2])
    c.px(4, 5, INK)
    c.px(6, 5, INK)
    c.px(5, 7, b[0])
    c.line(9, 8, 16, 6, b[3])
    c.line(10, 6, 15, 8, b[1])
    c.px(16, 5, b[3])
    c.px(9, 9, b[2])
    return _outlined(c)


# --- Sunken Bog: swamp and jungle --------------------------------------------------------------


@_prop("reeds", 0.045)
def make_reeds() -> np.ndarray:
    """Tall reeds and cattails in a clump (they sway)."""
    c = Canvas(18, 32)
    g = M["leaves_rot"].colors
    brown = M["wood"].colors
    rng = np.random.default_rng(371)
    for i in range(9):
        x0 = 3 + i * 1.5 + rng.uniform(-0.5, 0.5)
        top = int(rng.integers(4, 14))
        lean = rng.uniform(-2.5, 2.5)
        col = g[1 + i % 3]
        pts = [(x0 + lean * (1 - (y - top) / (30 - top)) ** 2, y) for y in range(top, 31)]
        for x, y in pts:
            c.px(int(round(x)), y, col)
        if i % 3 == 0:
            x = int(round(x0 + lean))
            c.rect(x, top - 4, x, top - 1, brown[1])
            c.px(x, top - 5, g[3])
    return _outlined(c)


@_prop("mangrove", 0.06)
def make_mangrove() -> np.ndarray:
    """A swamp tree on arching stilt roots, a low wide crown of dark leaves."""
    parts = []
    parts.append(RoundCone(MANGROVE, (0, 10.0, 0), (1.0, 34.0, 0), 2.8, 2.0, group="trunk", bumps=(0.2, 0.7, 381)))
    for i, (x, z) in enumerate(((-9.0, 2.0), (8.0, 3.0), (-5.0, -4.0), (6.0, -3.0), (0.0, 6.0))):
        mid = (x * 0.6, 8.0, z * 0.6)
        parts.append(RoundCone(MANGROVE, (0.0, 12.0, 0.0), mid, 1.6, 1.2, group="root"))
        parts.append(RoundCone(MANGROVE, mid, (x, 0.0, z), 1.2, 1.0, group="root"))
    for i, (x, y, z, r) in enumerate(((0.0, 38.0, 0.0, 9.0), (-10.0, 34.0, 1.0, 7.0), (10.0, 35.0, -1.0, 7.5),
                                      (-4.0, 42.0, -2.0, 6.0), (6.0, 41.0, 2.0, 6.0))):
        parts.append(Ellipsoid(SWAMP_LEAF, (x, y, z), (r, r * 0.6, r * 0.8), group="leaf",
                               bumps=(0.6, 0.6, 382 + i)))
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 48, 56, name="mangrove")
    return finish_prop(frame)


@_prop("moss_tree", 0.06)
def make_moss_tree() -> np.ndarray:
    """A crooked swamp tree with long beards of grey-green moss hanging from its limbs (it sways)."""
    parts = [RoundCone(BARK, (0, 0.0, 0), (2.0, 30.0, 0), 3.4, 2.0, group="trunk", bumps=(0.25, 0.6, 391))]
    limbs = (((2.0, 26.0, 0.0), (-12.0, 36.0, 1.0)), ((2.0, 28.0, 0.0), (14.0, 38.0, -1.0)),
             ((2.0, 30.0, 0.0), (4.0, 44.0, 0.0)))
    for a, b in limbs:
        parts.append(RoundCone(BARK, a, b, 1.6, 0.8, group="trunk"))
    for i, (x, y) in enumerate(((-11.0, 35.0), (-7.0, 32.0), (11.0, 37.0), (7.0, 34.0), (3.0, 42.0), (-3.0, 30.0))):
        length = 8.0 + (i % 3) * 3.0
        parts.append(RoundCone(HANGING_MOSS, (x, y, 1.0), (x + 0.5, y - length, 1.4), 1.6, 0.5,
                               group="moss", bumps=(0.3, 1.2, 392 + i)))
    for i, (x, y, r) in enumerate(((-11.0, 37.0, 4.0), (12.0, 39.0, 4.5), (4.0, 45.0, 4.0))):
        parts.append(Ellipsoid(SWAMP_LEAF, (x, y, 0.0), (r, r * 0.6, r * 0.7), group="leaf", bumps=(0.5, 0.7, 399 + i)))
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 40, 54, name="moss_tree")
    return finish_prop(frame)


@_prop("giant_mushroom", 0.055)
def make_giant_mushroom() -> np.ndarray:
    """A mushroom as tall as a man, its purple cap spotted with glowing cyan."""
    stem = RoundCone(SHROOM_STEM, (0, 0.0, 0), (0.8, 18.0, 0), 2.6, 1.8, group="stem")
    cap = Subtract(Ellipsoid(MUSH_CAP, (0.8, 20.0, 0), (10.0, 5.0, 8.0), group="cap"),
                   Ellipsoid(MUSH_CAP, (0.8, 16.0, 0), (9.0, 3.4, 7.0)))
    spots = [Sphere(MUSH_SPOT, (x, y, z), r, group="spot") for x, y, z, r in
             ((-4.0, 22.5, 4.0, 1.2), (3.5, 23.5, 3.0, 1.0), (0.0, 24.6, 0.5, 0.9), (6.5, 20.5, 4.0, 0.8),
              (-7.0, 20.0, 2.0, 0.8))]
    small = [RoundCone(SHROOM_STEM, (7.0, 0.0, 3.0), (7.5, 5.0, 3.0), 0.8, 0.6, group="stem"),
             Ellipsoid(MUSH_CAP, (7.5, 5.6, 3.0), (2.6, 1.4, 2.2), group="cap")]
    model = _face(GroundCut(Union(stem, cap, *spots, *small)))
    frame, _ = render_fit(model, 26, 32, name="giant_mushroom")
    return finish_prop(frame, skip_groups=("spot",))


@_prop("log", 0.05)
def make_log() -> np.ndarray:
    """A fallen tree trunk on its side, moss on top, a broken stub of a branch."""
    R = rot(0.0, 8.0, 90.0)
    trunk = Cylinder(BARK, (0, 3.6, 0), 3.6, 14.0, R=R, round=1.0, group="bark", bumps=(0.25, 0.6, 411))
    end = Cylinder(BARK_PALE, (14.0, 3.6, -2.0), 3.0, 0.4, R=R, group="end")
    moss = Ellipsoid(MOSS, (-2.0, 7.0, 0.5), (9.0, 1.4, 2.6), group="moss")
    stub = RoundCone(BARK, (-6.0, 6.0, 1.0), (-8.0, 10.0, 2.0), 1.2, 0.7, group="bark")
    model = _face(GroundCut(Union(trunk, end, moss, stub)))
    frame, _ = render_fit(model, 36, 16, centre="bbox", name="log")
    return finish_prop(frame)


@_prop("stilt_hut", 0.06)
def make_stilt_hut() -> np.ndarray:
    """A small hut on stilts over the bog: plank walls, a thatched roof, a ladder, a lit window."""
    parts = []
    for x, z in ((-8.0, -5.0), (8.0, -5.0), (-8.0, 5.0), (8.0, 5.0)):
        parts.append(Capsule(PLANK, (x, 0.0, z), (x, 14.0, z), 0.9, group="wood"))
    parts.append(Box(PLANK, (0, 15.0, 0), (11.0, 1.0, 7.5), group="wood"))
    parts.append(Box(PLANK, (0, 22.0, 0), (8.5, 6.5, 5.6), round=0.4, group="wall", bumps=(0.15, 0.8, 421)))
    roof = Prism(THATCH, (0, 31.0, 0), [(-12.0, 0.0), (0.0, 9.0), (12.0, 0.0)], 7.4, round=0.6, group="roof")
    parts.append(roof)
    parts.append(Box(LANTERN, (3.5, 23.0, 5.7), (1.6, 1.8, 0.2), group="window"))
    parts.append(Box(WOOD_DARK, (-3.5, 21.0, 5.7), (1.8, 4.5, 0.2), group="door"))
    for y in (3.0, 6.0, 9.0, 12.0):
        parts.append(Box(PLANK, (-3.5, y, 9.0), (2.2, 0.35, 0.35), group="ladder"))
    parts.append(Capsule(PLANK, (-5.6, 0.0, 9.0), (-5.6, 15.0, 7.5), 0.4, group="ladder", thin=True))
    parts.append(Capsule(PLANK, (-1.4, 0.0, 9.0), (-1.4, 15.0, 7.5), 0.4, group="ladder", thin=True))
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 48, 56, centre="bbox", name="stilt_hut")
    return finish_prop(frame, skip_groups=("window",))


@_prop("swamp_lantern", 0.05)
def make_swamp_lantern() -> np.ndarray:
    """A crooked pole stuck in the mud with a lantern hanging from its hook."""
    pole = RoundCone(WOOD_DARK, (0, 0.0, 0), (1.5, 34.0, 0), 1.0, 0.7, group="pole")
    arm = Capsule(WOOD_DARK, (1.5, 33.0, 0), (6.0, 34.0, 0), 0.6, group="pole", thin=True)
    chain = Capsule(LAMP_IRON, (6.0, 33.5, 0), (6.0, 29.0, 0), 0.3, group="iron", thin=True)
    cage = Box(LAMP_IRON, (6.0, 26.5, 0), (1.8, 2.6, 1.8), round=0.3, group="iron")
    glass = Box(LANTERN, (6.0, 26.5, 0.2), (1.3, 2.0, 1.6), group="glass")
    model = _face(GroundCut(Union(pole, arm, chain, cage, glass)))
    frame, _ = render_fit(model, 16, 40, centre="bbox", name="swamp_lantern")
    return finish_prop(frame, skip_groups=("glass",))


@_prop("fern", 0.045)
def make_fern() -> np.ndarray:
    """A jungle fern: arching fronds with paired leaflets (it sways)."""
    c = Canvas(24, 18)
    g = SWAMP_LEAF.colors
    fronds = ((12, 17, -10, 6), (12, 17, -5, 2), (12, 17, 1, 1), (12, 17, 6, 3), (12, 17, 10, 7))
    for i, (x0, y0, dx, peak) in enumerate(fronds):
        steps = 12
        for s in range(steps + 1):
            t = s / steps
            x = x0 + dx * t
            y = y0 - (y0 - peak) * math.sin(t * math.pi * 0.85)
            col = g[1 + (i % 2)]
            c.px(int(round(x)), int(round(y)), col)
            if 0 < s < steps and s % 2 == 0:
                c.px(int(round(x)), int(round(y)) - 1, g[3])
                c.px(int(round(x)) + (1 if dx > 0 else -1), int(round(y)) + 1, g[2])
    return _outlined(c)


# --- Rotten Hollow: the rotting forest ------------------------------------------------------------


@_prop("bush", 0.05)
def make_bush() -> np.ndarray:
    """A dark, round bush of olive leaves (it sways a little)."""
    parts = [Ellipsoid(CANOPY, (x, y, z), (r, r * 0.8, r * 0.85), group="leaf", bumps=(0.6, 0.7, 431 + i))
             for i, (x, y, z, r) in enumerate(((0.0, 6.0, 0.0, 7.0), (-6.0, 4.5, 1.0, 5.0), (6.0, 4.8, -1.0, 5.4),
                                               (1.0, 10.0, -1.0, 4.6)))]
    parts.append(Ellipsoid(DEAD_LEAF, (-3.0, 9.0, 3.0), (2.4, 1.6, 1.6), group="dead"))
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 28, 20, centre="bbox", name="bush")
    return finish_prop(frame)


@_prop("stump", 0.05)
def make_stump() -> np.ndarray:
    """An old cut stump, its top pale and ringed, roots gripping the ground, a mushroom on it."""
    body = RoundCone(BARK, (0, 0.0, 0), (0, 7.0, 0), 5.0, 4.2, group="bark", bumps=(0.25, 0.6, 441))
    top_ = Cylinder(BARK_PALE, (0, 7.0, 0), 4.0, 0.5, group="top")
    roots = [RoundCone(BARK, (0, 2.0, 0), (math.cos(a) * 7.0, 0.0, math.sin(a) * 5.0), 1.6, 0.8, group="bark")
             for a in (0.3, 2.1, 3.8, 5.2)]
    shroom = [Capsule(SHROOM_STEM, (4.6, 3.0, 2.0), (5.6, 4.6, 2.2), 0.4, group="m"),
              Ellipsoid(ROT, (5.8, 5.0, 2.2), (1.6, 0.8, 1.2), group="m")]
    model = _face(GroundCut(Union(body, top_, *roots, *shroom)))
    frame, _ = render_fit(model, 20, 14, centre="bbox", name="stump")
    return finish_prop(frame)


@_prop("thorns", 0.05)
def make_thorns() -> np.ndarray:
    """A tangle of black thorny briars."""
    c = Canvas(30, 20)
    d = ROT_BARK.colors
    rng = np.random.default_rng(451)
    for i in range(9):
        x, y = rng.uniform(4, 26), 19.0
        ang = rng.uniform(-2.6, -0.5)
        for s in range(14):
            nx, ny = x + math.cos(ang) * 1.4, y + math.sin(ang) * 1.4
            c.line(int(round(x)), int(round(y)), int(round(nx)), int(round(ny)), d[1 + (i % 2)])
            if s % 3 == 1:
                c.px(int(round(nx)) + 1, int(round(ny)) - 1, d[3])
            x, y = nx, ny
            ang += rng.uniform(-0.45, 0.45)
            if y < 2:
                break
    return _outlined(c)


# --- More plants (card #231): so no two spots of ground look the same ------------------------------


def _blades(c: Canvas, rng: np.random.Generator, n: int, x_lo: float, x_hi: float, top_lo: int, top_hi: int,
            lean: float, ramp: list[str], tip: list[str] | None = None) -> None:
    """Grass blades from the bottom row up to a random top, each bending its own way, lighter
    toward the tip (it catches the light), darkest at the root."""
    H = c.a.shape[0]
    for i in range(n):
        x0 = rng.uniform(x_lo, x_hi)
        top = int(rng.integers(top_lo, top_hi))
        bend = rng.uniform(-lean, lean)
        for y in range(top, H):
            t = (y - top) / max(1, H - 1 - top)
            x = int(round(x0 + bend * (1.0 - t) ** 2))
            if H - 1 - y < 2:
                col = ramp[1]
            elif y - top < 2:
                col = (tip or ramp)[3]
            else:
                col = ramp[2 + (i % 2) - (1 if t > 0.6 else 0)]
            c.px(x, y, col)


@_prop("grass_tall", 0.045)
def make_grass_tall() -> np.ndarray:
    """A tall tuft of wild grass, a few dry blades among the green (it sways)."""
    c = Canvas(16, 22)
    rng = np.random.default_rng(901)
    _blades(c, rng, 6, 2, 14, 1, 9, 3.5, M["grass"].colors, M["leaves_rot"].colors)
    _blades(c, rng, 2, 3, 13, 4, 11, 3.0, M["canvas"].colors)
    return _outlined(c)


def _flowers(seed: int, heads: list[str]) -> np.ndarray:
    c = Canvas(18, 12)
    rng = np.random.default_rng(seed)
    _blades(c, rng, 5, 3, 15, 5, 9, 1.5, M["grass"].colors)
    for i in range(7):
        x, y = int(rng.integers(2, 16)), int(rng.integers(2, 7))
        c.line(x, y + 1, x + int(rng.integers(-1, 2)), 11, M["grass"].colors[1 + i % 2])
        col = heads[i % len(heads)]
        c.rect(x, y - 1, x + 1, y, col)
        c.px(x, y - 1, heads[0])
    return _outlined(c)


@_prop("flowers_pale", 0.045)
def make_flowers_pale() -> np.ndarray:
    """A clump of small pale wildflowers, cream and a little yellow (they sway)."""
    return _flowers(911, [M["cloth_cream"].colors[3], M["bone"].colors[2], M["gold"].colors[3]])


@_prop("flowers_violet", 0.045)
def make_flowers_violet() -> np.ndarray:
    """A clump of small rot-violet flowers (they sway)."""
    return _flowers(921, [M["cloth_purple"].colors[3], M["rot_purple"].colors[3], M["cloth_purple"].colors[2]])


@_prop("fern_big", 0.045)
def make_fern_big() -> np.ndarray:
    """A big olive forest fern: long arching fronds with paired leaflets (it sways)."""
    c = Canvas(30, 22)
    g = CANOPY.colors
    fronds = ((15, 21, -13, 8), (15, 21, -7, 3), (15, 21, -1, 1), (15, 21, 6, 2), (15, 21, 13, 7), (15, 21, 3, 6))
    for i, (x0, y0, dx, peak) in enumerate(fronds):
        steps = 15
        for s in range(steps + 1):
            t = s / steps
            x = x0 + dx * t
            y = y0 - (y0 - peak) * math.sin(t * math.pi * 0.85)
            c.px(int(round(x)), int(round(y)), g[1 + (i % 2)])
            if 0 < s < steps and s % 2 == 0:
                c.px(int(round(x)), int(round(y)) - 1, g[3])
                c.px(int(round(x)) + (1 if dx > 0 else -1), int(round(y)) + 1, g[2])
    return _outlined(c)


@_prop("bush_dead", 0.05)
def make_bush_dead() -> np.ndarray:
    """A low bush the rot has killed: dry brown-olive leaves, bare twigs poking out (it sways a
    little)."""
    parts = [Ellipsoid(DEAD_LEAF, (x, y, z), (r, r * 0.75, r * 0.8), group="leaf", bumps=(0.6, 0.7, 931 + i))
             for i, (x, y, z, r) in enumerate(((0.0, 4.5, 0.0, 5.6), (-5.0, 3.5, 1.0, 4.0), (4.6, 3.6, -1.0, 4.2)))]
    for i, (a, b) in enumerate((((-3.0, 6.0, 1.0), (-7.0, 11.0, 1.0)), ((2.0, 7.0, 0.0), (5.0, 12.0, 0.5)),
                                ((0.0, 8.0, 1.0), (0.5, 13.0, 1.0)))):
        parts.append(Capsule(ROT_BARK, a, b, 0.45, group="twig", thin=True))
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 24, 16, centre="bbox", name="bush_dead")
    return finish_prop(frame)


@_prop("mushrooms_small", 0.045)
def make_mushrooms_small() -> np.ndarray:
    """Three little mushrooms in the leaf litter, two brown and one rot-violet."""
    c = Canvas(14, 10)
    stem = M["bone"].colors
    for (x, h, w, cap) in ((3, 4, 2, M["leather"].colors), (7, 6, 3, M["leather"].colors),
                           (11, 3, 2, M["rot_purple"].colors)):
        c.rect(x, 9 - h, x, 9, stem[2])
        c.rect(x - w, 9 - h - 1, x + w, 9 - h, cap[2])
        c.rect(x - w + 1, 9 - h - 2, x + w - 1, 9 - h - 2, cap[3])
        c.px(x - w, 9 - h, cap[1])
    return _outlined(c)


@_prop("grass_ash", 0.045)
def make_grass_ash() -> np.ndarray:
    """A tuft of grass gone grey in the ash, a few blades still dull green (it sways)."""
    c = Canvas(20, 12)
    rng = np.random.default_rng(941)
    _blades(c, rng, 8, 2, 16, 1, 7, 2.5, M["ash"].colors)
    _blades(c, rng, 3, 4, 14, 3, 8, 2.0, M["leaves_rot"].colors)
    return _outlined(c)


@_prop("fence", 0.05)
def make_fence() -> np.ndarray:
    """A broken wooden fence: three posts, two rails, one rail hanging loose."""
    parts = []
    for i, x in enumerate((-13.0, 0.0, 13.0)):
        h = (11.0, 12.0, 8.0)[i]
        parts.append(Box(PLANK, (x, h * 0.5, 0), (1.0, h * 0.5, 1.0), round=0.3, group="wood", bumps=(0.1, 0.8, 461 + i)))
    parts.append(Box(PLANK, (-6.5, 8.5, 1.2), (7.6, 0.7, 0.4), round=0.2, group="wood"))
    parts.append(Box(PLANK, (-6.5, 4.0, 1.2), (7.6, 0.7, 0.4), round=0.2, group="wood"))
    parts.append(Box(PLANK, (6.5, 6.5, 1.2), (7.0, 0.7, 0.4), R=rot(0.0, 0.0, -22.0), round=0.2, group="wood"))
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 34, 16, centre="bbox", name="fence")
    return finish_prop(frame)


@_prop("cart", 0.05)
def make_cart() -> np.ndarray:
    """A broken cart tipped on one wheel, its other wheel lying against it."""
    bed = Box(PLANK, (0, 7.0, 0), (10.0, 2.4, 5.0), R=rot(0.0, 0.0, -10.0), round=0.4, group="wood",
              bumps=(0.1, 0.8, 471))
    sides = Box(PLANK, (0, 10.0, -4.4), (10.0, 2.0, 0.5), R=rot(0.0, 0.0, -10.0), group="wood")
    wheel = Torus(WOOD_DARK, (-6.0, 5.4, 5.6), 4.6, 0.8, R=rot(90.0, 0.0, 0.0), group="wheel")
    hub = Cylinder(LAMP_IRON, (-6.0, 5.4, 5.8), 1.0, 0.6, R=rot(90.0, 0.0, 0.0), group="hub")
    spokes = [Capsule(WOOD_DARK, (-6.0, 5.4, 5.6), (-6.0 + math.cos(a) * 4.2, 5.4 + math.sin(a) * 4.2, 5.6),
                      0.35, group="wheel", thin=True) for a in np.linspace(0, math.tau, 6, endpoint=False)]
    loose = Torus(WOOD_DARK, (9.0, 1.0, 6.5), 4.0, 0.7, R=rot(15.0, 0.0, 0.0), group="wheel")
    shafts = [Capsule(PLANK, (10.0, 4.0, z), (19.0, 0.5, z), 0.5, group="wood", thin=True) for z in (-3.0, 3.0)]
    model = _face(GroundCut(Union(bed, sides, wheel, hub, *spokes, loose, *shafts)))
    frame, _ = render_fit(model, 40, 22, centre="bbox", name="cart")
    return finish_prop(frame)


@_prop("well", 0.05)
def make_well() -> np.ndarray:
    """A round stone well with a little wooden roof and a hanging bucket."""
    ring = Subtract(Cylinder(STONE, (0, 4.0, 0), 7.0, 4.0, round=0.8, group="stone", bumps=(0.2, 0.6, 481)),
                    Cylinder(STONE, (0, 6.0, 0), 5.2, 4.0))
    dark = Cylinder(Material("life_well_dark", [INK, "#1c1a22"], hi=1.0, outline=INK), (0, 6.6, 0), 5.0, 0.3, group="dark")
    posts = [Box(PLANK, (sx * 6.0, 12.0, 0), (0.7, 8.0, 0.7), group="wood") for sx in (-1, 1)]
    roof = Prism(THATCH, (0, 21.5, 0), [(-9.0, 0.0), (0.0, 5.0), (9.0, 0.0)], 4.8, round=0.4, group="roof")
    beam = Capsule(PLANK, (-6.0, 17.0, 0), (6.0, 17.0, 0), 0.5, group="wood", thin=True)
    rope = Capsule(M["canvas"], (1.0, 17.0, 0), (1.0, 11.5, 0), 0.25, group="rope", thin=True)
    bucket = Cylinder(PLANK, (1.0, 10.0, 0), 1.6, 1.6, group="wood")
    model = _face(GroundCut(Union(ring, dark, *posts, roof, beam, rope, bucket)))
    frame, _ = render_fit(model, 24, 30, name="well")
    return finish_prop(frame)


@_prop("signpost", 0.05)
def make_signpost() -> np.ndarray:
    """A leaning signpost with two pointing boards, one cracked."""
    post = RoundCone(PLANK, (0, 0.0, 0), (0.6, 26.0, 0), 1.0, 0.8, group="wood")
    a = Prism(PLANK, (3.5, 22.0, 0.8), [(-4.0, -1.6), (4.0, -1.6), (6.0, 0.0), (4.0, 1.6), (-4.0, 1.6)], 0.5,
              group="board")
    b = Prism(PLANK, (-3.0, 17.0, 0.8), [(4.0, -1.5), (-4.0, -1.5), (-6.0, 0.0), (-4.0, 1.5), (4.0, 1.5)], 0.5,
              R=rot(0.0, 0.0, 12.0), group="board")
    model = _face(GroundCut(Union(post, a, b)))
    frame, _ = render_fit(model, 26, 30, name="signpost")
    return finish_prop(frame)


@_prop("grave_cross", 0.05)
def make_grave_cross() -> np.ndarray:
    """A wooden grave cross on a low mound."""
    c = Canvas(14, 20)
    w = M["wood_dark"].colors
    d = M["dirt"].colors
    c.ellipse(7.0, 18.0, 6.0, 2.0, d[1])
    c.rect(6, 3, 7, 17, w[2])
    c.rect(6, 3, 6, 17, w[3])
    c.rect(3, 7, 10, 8, w[2])
    c.rect(3, 7, 10, 7, w[3])
    c.px(8, 12, w[0])
    return _outlined(c)


@_prop("pine_dead", 0.06)
def make_pine_dead() -> np.ndarray:
    """A tall dead conifer: a straight dark trunk and tiers of bare, drooping branches."""
    parts = [RoundCone(ROT_BARK, (0, 0.0, 0), (0, 58.0, 0), 2.6, 0.4, group="trunk", bumps=(0.2, 0.6, 491))]
    for i in range(7):
        y = 14.0 + i * 6.5
        span = 11.0 - i * 1.3
        for sx in (-1, 1):
            parts.append(RoundCone(ROT_BARK, (0, y, 0), (sx * span, y - 3.0 - (i % 2), (i % 3 - 1) * 1.5),
                                   0.7, 0.3, group="trunk", thin=True))
    for i, (x, y) in enumerate(((-8.0, 18.0), (7.0, 24.0), (-5.0, 34.0), (5.0, 40.0))):
        parts.append(Ellipsoid(DEAD_LEAF, (x, y, 0.5), (3.0, 1.4, 1.6), group="needles", bumps=(0.4, 0.8, 495 + i)))
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 28, 64, name="pine_dead")
    return finish_prop(frame)


# --- Critters (four frames: idle, idle, move, move) ------------------------------------------------

def _sheet(frames: list[np.ndarray]) -> np.ndarray:
    return np.concatenate(frames, 1)


def make_crow() -> np.ndarray:
    """A crow: perched, perched with its head turned, wings up, wings down."""
    W, H = 16, 14
    k = ["#141218", "#24222c", "#3a3846"]
    beak = "#8a7a52"
    out = []
    for f in range(4):
        c = Canvas(W, H)
        if f < 2:
            c.ellipse(7.0, 9.0, 3.6, 2.6, k[1])
            c.ellipse(10.5 if f == 0 else 9.5, 6.0, 2.0, 1.8, k[1])
            c.px(12 if f == 0 else 8, 6, beak)
            c.px(11 if f == 0 else 9, 5, "#c0b070")
            c.line(3, 10, 1, 12, k[0])
            c.line(6, 12, 6, 13, beak)
            c.line(8, 12, 8, 13, beak)
            c.line(5, 8, 9, 8, k[2])
        else:
            c.ellipse(8.0, 8.0, 3.2, 2.0, k[1])
            c.ellipse(11.5, 7.0, 1.7, 1.5, k[1])
            c.px(13, 7, beak)
            up = f == 2
            c.poly([(5.0, 7.5), (2.0, 2.0 if up else 12.0), (9.0, 7.5)], k[0])
            c.poly([(7.0, 7.5), (11.0, 1.5 if up else 12.5), (10.0, 7.5)], k[2])
            c.line(4, 9, 1, 10, k[0])
        c.outline(INK)
        out.append(c.a)
    return _sheet(out)


def make_frog() -> np.ndarray:
    """A frog: sitting, throat puffed, mid-hop, landing."""
    W, H = 14, 12
    g = SWAMP_LEAF.colors
    belly = "#b8b07a"
    out = []
    for f in range(4):
        c = Canvas(W, H)
        if f < 2:
            c.ellipse(7.0, 8.0, 4.6, 2.8, g[1])
            c.ellipse(9.5, 6.0, 2.4, 2.0, g[2])
            c.px(10, 5, "#e8d048")
            c.px(11, 5, INK)
            if f == 1:
                c.ellipse(10.0, 8.4, 1.6, 1.2, belly)
            c.line(3, 10, 5, 10, g[0])
            c.line(9, 10, 11, 10, g[0])
        else:
            c.ellipse(7.0, 6.0, 4.4, 2.2, g[1])
            c.ellipse(10.5, 5.0, 2.0, 1.6, g[2])
            c.px(11, 4, "#e8d048")
            c.line(3, 7, 0, 10 if f == 2 else 9, g[0])
            c.line(5, 7, 2, 11 if f == 2 else 9, g[0])
            c.line(10, 7, 12, 9, g[0])
        c.outline(INK)
        out.append(c.a)
    return _sheet(out)


def make_rat() -> np.ndarray:
    """A rat: sniffing, sniffing with its nose up, running (legs out, legs in)."""
    W, H = 16, 9
    f_ = ["#2c2628", "#4a3e3c", "#6a5a54"]
    pink = "#b88a88"
    out = []
    for f in range(4):
        c = Canvas(W, H)
        c.ellipse(7.0, 5.5, 4.0, 2.2, f_[1])
        c.ellipse(11.5, 5.0 if f != 1 else 4.0, 2.2, 1.6, f_[1])
        c.px(13, 5 if f != 1 else 4, pink)
        c.px(11, 4 if f != 1 else 3, INK)
        c.px(10, 3 if f != 1 else 2, f_[2])
        c.line(3, 6, 0, 4 if f % 2 == 0 else 6, pink)
        legs = ((5, 8), (9, 8)) if f != 2 else ((3, 8), (11, 8))
        for x, y in legs:
            c.px(x, y, f_[0])
        c.line(5, 4, 9, 4, f_[2])
        c.outline(INK)
        out.append(c.a)
    return _sheet(out)


# --- Particles ----------------------------------------------------------------------------------

def make_mote() -> np.ndarray:
    """A firefly / glowing mote: a bright pixel in a dimmer cross (tinted by the zone's data)."""
    a = np.zeros((3, 3, 4), dtype=np.uint8)
    a[1, 1] = (255, 255, 255, 255)
    for x, y in ((0, 1), (2, 1), (1, 0), (1, 2)):
        a[y, x] = (190, 190, 190, 255)
    return a


def make_ash() -> np.ndarray:
    a = np.zeros((2, 2, 4), dtype=np.uint8)
    a[0, 0] = a[1, 1] = (200, 196, 192, 255)
    a[0, 1] = (150, 146, 144, 255)
    return a


def make_leaf() -> np.ndarray:
    c = Canvas(6, 5)
    col = DEAD_LEAF.colors
    c.px(1, 2, col[1]); c.px(2, 1, col[2]); c.px(2, 2, col[2]); c.px(3, 2, col[1]); c.px(3, 3, col[0])
    c.px(4, 2, col[2]); c.px(2, 3, col[1]); c.px(5, 1, col[0])
    return c.a


def make_spore() -> np.ndarray:
    a = np.zeros((3, 3, 4), dtype=np.uint8)
    a[1, 1] = (220, 255, 200, 255)
    a[0, 1] = a[1, 0] = (150, 200, 140, 255)
    return a


def make_mist() -> np.ndarray:
    """A soft puff of mist: alpha falls off from the middle in a few hard steps (pixel art)."""
    W, H = 32, 16
    y, x = np.mgrid[0:H, 0:W]
    d = np.hypot((x - W / 2 + 0.5) / (W / 2), (y - H / 2 + 0.5) / (H / 2))
    alpha = np.select([d < 0.45, d < 0.7, d < 0.9], [110, 70, 35], 0).astype(np.uint8)
    out = np.zeros((H, W, 4), dtype=np.uint8)
    out[..., :3] = 235
    out[..., 3] = alpha
    return out


def make_rain_drop() -> np.ndarray:
    """A rain streak (weather, card #303): one pixel wide, brightest in row 0 and fading to row 5.
    The game stretches it and turns the quad's top edge (row 0) along the fall, so on screen the
    drop is bright at its falling foot and fades up its tail."""
    a = np.zeros((6, 1, 4), dtype=np.uint8)
    for y, alpha in enumerate((240, 200, 150, 110, 70, 40)):
        a[y, 0] = (220, 230, 245, alpha)
    return a


def make_splash() -> np.ndarray:
    """A raindrop landing: a tiny crown thrown up on both sides of a bright middle."""
    a = np.zeros((3, 5, 4), dtype=np.uint8)
    a[2, 1] = a[2, 2] = a[2, 3] = (230, 238, 250, 230)
    a[1, 0] = a[1, 4] = (200, 214, 235, 170)
    a[0, 2] = (215, 225, 245, 150)
    return a


CRITTERS = {"crow": make_crow, "frog": make_frog, "rat": make_rat}
PARTICLES = {"mote": make_mote, "ash_flake": make_ash, "leaf": make_leaf, "spore": make_spore, "mist": make_mist,
             "rain_drop": make_rain_drop, "splash": make_splash}


def build(ctx) -> None:
    for name, fn in PROPS.items():
        rgba = fn()
        check(name, rgba)
        ctx.save("sprites/env/%s.png" % name, rgba)
    for name, fn in CRITTERS.items():
        ctx.save("sprites/env/critter_%s.png" % name, fn(), scale=6)
    for name, fn in PARTICLES.items():
        ctx.save("sprites/fx/%s.png" % name, fn(), scale=8)
