"""Long-zone things (DESIGN.md 8.5): the rot seal, the gate texture, four shrines and three
wanderers.

Same rules as env_props: small 3D models in the camera-aligned frame (x = screen right, y = up,
z = toward the viewer), rendered with the shared camera and light, cut flat on the ground, outlined.
The game draws them with `fighter_sprite.gdshader`, where `self_glow` makes the WHOLE texture emit,
so anything that glows (the seal, the shrines) keeps its stone dark and only its glowing bits
bright. The gate texture is a 2D seamless tile of rotten roots for a ZoneBlockData.
"""
from __future__ import annotations

import math

import numpy as np

from kit.noise import fbm3
from kit.palette import INK, M, Material
from kit.sdf import (Box, Capsule, Cylinder, Ellipsoid, Prism, RoundCone, Sphere, Subtract, Torus,
                     Union, rot)

from assets.env_props import (GroundCut, STONE, _face, check, finish_prop, ink_outline, lch_mat, mat,
                              render_fit)

# Dark, cold stone for things that glow: the shader multiplies the whole sprite by its glow, so
# the stone must sit low for the runes to stand out.
DARK_STONE = lch_mat("zone_dark_stone", [(0.2, 0.012, 290.0), (0.25, 0.012, 300.0), (0.3, 0.014, 95.0),
                                         (0.355, 0.016, 100.0)], wrap=0.25, ao=0.3, outline_L=0.15)
RUNE = Material("zone_rune", M["glow_rot"].colors, emissive=True, glow_index=3,
                outline=ink_outline("#4f6b1f", 0.22))
WATER = Material("zone_water", M["glow_cyan"].colors, emissive=True, glow_index=2,
                 outline=ink_outline("#2f6f73", 0.22))
BLOOD = Material("zone_blood", ["#4a1016", "#6e1a1f", "#9a2a26", "#c4473a"], emissive=True, glow_index=2,
                 outline=ink_outline("#4a1016", 0.18))
EMBER = Material("zone_ember", M["glow_amber"].colors, emissive=True, glow_index=2,
                 outline=ink_outline("#c26a2a", 0.25))
GOLD = mat("zone_gold", "#c4a04a", below=2, above=1, spec=0.6, spec_power=8.0, wrap=0.3)
BONE = mat("zone_bone", "#cfc4a0", below=2, above=1, wrap=0.35)
WOOD = mat("zone_wood", "#5e4634", below=2, above=1, wrap=0.3)
IRON = mat("zone_iron", "#4c505c", below=2, above=1, spec=0.4, wrap=0.2, outline=INK)
SKIN = M["skin"]
LEATHER = mat("zone_leather", "#6e4a33", below=2, above=1, wrap=0.35)
CANVAS = mat("zone_canvas", "#8a7a52", below=2, above=1, wrap=0.45)
HOLE = Material("zone_hood_dark", [INK, "#241c22"], hi=1.0, outline=INK)

PIXEL_SIZE = {
    "seal_stone": 0.05, "shrine_spring": 0.05, "shrine_altar": 0.05, "shrine_idol": 0.05,
    "shrine_plenty": 0.05, "wanderer_peddler": 0.045, "wanderer_robber": 0.045, "wanderer_pilgrim": 0.045,
}


# --- The rot seal -------------------------------------------------------------------------------


def make_seal_stone() -> np.ndarray:
    """A leaning standing stone with a glowing rune carved into its face."""
    stone = Box(DARK_STONE, (0, 11.0, 0), (4.2, 11.0, 2.6), R=rot(0.0, 10.0, -4.0), round=1.6,
                group="stone", bumps=(0.35, 0.45, 11))
    cap = Ellipsoid(DARK_STONE, (-0.6, 21.5, 0), (3.8, 2.4, 2.4), group="stone", bumps=(0.3, 0.5, 12))
    base = Ellipsoid(DARK_STONE, (0, 0.6, 0), (6.0, 1.6, 3.6), group="stone", bumps=(0.25, 0.6, 13))
    # The rune: a ring with a stroke through it, raised just out of the face.
    rune_z = 2.55
    ring = Torus(RUNE, (0.2, 12.5, rune_z), 2.6, 0.55, R=rot(90.0, 0.0, 0.0), group="rune", thin=True)
    stroke = Capsule(RUNE, (0.2, 7.5, rune_z), (0.2, 18.0, rune_z), 0.5, group="rune", thin=True)
    tick = Capsule(RUNE, (-1.8, 15.8, rune_z), (2.2, 15.8, rune_z), 0.45, group="rune", thin=True)
    model = _face(GroundCut(Union(base, stone, cap, ring, stroke, tick)))
    frame, _ = render_fit(model, 16, 28, name="seal_stone")
    return finish_prop(frame, skip_groups=("rune",))


# --- The gate (a seamless block texture) --------------------------------------------------------


def make_rot_gate(T: int = 32) -> np.ndarray:
    """Rotten roots woven into a wall: dark twisting strands running up, glowing rot in the gaps.
    Every term is periodic in T, so the tile repeats seamlessly both ways."""
    y, x = np.mgrid[0:T, 0:T].astype(float)
    tau = 2.0 * math.pi
    out = np.zeros((T, T, 4), dtype=np.uint8)
    bark = [(0x1c, 0x17, 0x1b), (0x2b, 0x22, 0x24), (0x3d, 0x30, 0x2c), (0x52, 0x41, 0x35), (0x66, 0x52, 0x40)]
    glow = [(0x3c, 0x52, 0x1a), (0x6f, 0x8a, 0x35), (0xbf, 0xe8, 0x5e)]
    best = np.full((T, T), 9.0)
    shade = np.zeros((T, T))
    for k, (phase, amp, width) in enumerate(((0.0, 3.0, 3.2), (11.0, 2.5, 2.6), (21.0, 3.4, 3.0),
                                             (5.5, 2.0, 2.0), (27.0, 2.2, 2.2))):
        # A strand winds up the tile: its centre x moves with y (two periods, so it twists).
        cx = (phase + amp * np.sin(tau * y / T * (1 + k % 2) + k)) % T
        d = np.abs(((x - cx + T / 2) % T) - T / 2)
        inside = d < width
        t = d / width
        closer = inside & (d < best)
        best = np.where(closer, d, best)
        # Round strand: lit on its left, dark on its right edge.
        side = (x - cx + T / 2) % T - T / 2
        shade = np.where(closer, 0.75 - 0.6 * t * np.sign(side) * 0.8 - 0.25 * t * t, shade)
    n = np.zeros((T, T))
    for i in range(T):
        for j in range(T):
            n[i, j] = math.sin(tau * (i * 3 + j) / T) * 0.15 + math.sin(tau * (j * 2 - i) / T) * 0.12
    strand = best < 9.0
    level = np.clip(shade + n, 0.0, 0.999)
    idx = (level * len(bark)).astype(int)
    rgb = np.zeros((T, T, 3), dtype=np.uint8)
    for i, c in enumerate(bark):
        rgb[strand & (idx == i)] = c
    # Gaps: deep dark with a rot glow pooling in a periodic pattern.
    g = np.sin(tau * x / T * 2 + 1.3) * np.sin(tau * y / T * 3) + n
    gap = ~strand
    rgb[gap] = bark[0]
    rgb[gap & (g > 0.35)] = glow[0]
    rgb[gap & (g > 0.6)] = glow[1]
    rgb[gap & (g > 0.85)] = glow[2]
    # Bark grain: a darker line every few pixels along each strand.
    grain = strand & (((y + 2 * x) % 7) == 0) & (level < 0.7)
    rgb[grain] = bark[max(0, 1)]
    out[..., :3] = rgb
    out[..., 3] = 255
    return out


# --- Shrines ------------------------------------------------------------------------------------


def make_shrine_spring() -> np.ndarray:
    """A stone basin on a low foot, brimming with glowing water that spills over its front lip,
    fed by a spout from a carved post behind it."""
    foot = Cylinder(DARK_STONE, (0, 1.2, 0), 6.0, 1.2, round=0.5, group="stone", bumps=(0.2, 0.6, 24))
    bowl = Cylinder(DARK_STONE, (0, 5.0, 0), 8.0, 2.6, round=1.4, group="stone", bumps=(0.2, 0.6, 22))
    rim = Torus(DARK_STONE, (0, 7.4, 0), 7.2, 1.4, group="stone", bumps=(0.2, 0.6, 21))
    water = Ellipsoid(WATER, (0, 8.0, 0), (6.4, 2.0, 6.4), group="water")
    spill = Box(WATER, (0.5, 4.6, 7.6), (1.8, 3.2, 0.5), round=0.4, group="water")
    puddle = Ellipsoid(WATER, (1.0, 0.3, 9.0), (3.6, 0.5, 1.6), group="water")
    post = Box(DARK_STONE, (0, 11.0, -6.5), (2.2, 11.0, 1.6), round=0.8, group="stone", bumps=(0.25, 0.5, 23))
    knob = Sphere(DARK_STONE, (0, 22.6, -6.5), 2.0, group="stone")
    drip = Capsule(WATER, (0, 17.0, -4.8), (0, 9.0, -3.6), 0.6, group="water", thin=True)
    model = _face(GroundCut(Union(foot, bowl, rim, water, spill, puddle, post, knob, drip)))
    frame, _ = render_fit(model, 32, 34, name="shrine_spring")
    return finish_prop(frame, skip_groups=("water",))


def make_shrine_altar() -> np.ndarray:
    """A heavy slab altar with a pool of blood on top, bones at its foot, two red candles."""
    slab = Box(DARK_STONE, (0, 9.0, 0), (9.0, 1.6, 4.5), round=0.7, group="stone", bumps=(0.2, 0.6, 31))
    legs = [Box(DARK_STONE, (sx * 6.0, 3.8, 0), (2.2, 3.8, 3.4), round=0.6, group="stone",
                bumps=(0.25, 0.6, 32)) for sx in (-1, 1)]
    pool = Ellipsoid(BLOOD, (0, 10.8, 0.5), (6.0, 1.1, 3.0), group="blood")
    drip = Capsule(BLOOD, (2.5, 10.2, 4.2), (2.6, 6.5, 4.4), 0.5, group="blood", thin=True)
    candles = []
    for sx in (-1, 1):
        candles.append(Cylinder(BONE, (sx * 7.6, 12.6, 1.0), 0.9, 2.2, group="candle"))
        candles.append(Sphere(EMBER, (sx * 7.6, 15.5, 1.0), 0.75, group="flame"))
    skull = Sphere(BONE, (-3.5, 1.9, 5.0), 1.9, group="bone")
    bone = Capsule(BONE, (1.0, 0.8, 5.2), (5.5, 1.2, 4.0), 0.6, group="bone", thin=True)
    model = _face(GroundCut(Union(*legs, slab, pool, drip, *candles, skull, bone)))
    frame, _ = render_fit(model, 30, 26, name="shrine_altar")
    return finish_prop(frame, skip_groups=("blood", "flame"))


def make_shrine_idol() -> np.ndarray:
    """A crude carved war idol: a stacked wooden post with a horned head and burning eyes."""
    post = RoundCone(WOOD, (0, 0.0, 0), (0, 22.0, 0), 3.6, 3.0, group="wood", bumps=(0.25, 0.6, 41))
    head = Box(WOOD, (0, 25.5, 0), (4.2, 4.0, 3.4), round=1.4, group="wood", bumps=(0.2, 0.6, 42))
    horns = [RoundCone(BONE, (sx * 3.6, 28.0, 0), (sx * 7.5, 33.5, 0.5), 1.3, 0.4, group="bone", thin=True)
             for sx in (-1, 1)]
    eyes = [Sphere(EMBER, (sx * 1.7, 26.0, 3.3), 0.8, group="eye") for sx in (-1, 1)]
    mouth = Box(HOLE, (0, 22.8, 3.2), (2.0, 0.6, 0.4), group="mouth")
    bands = [Torus(IRON, (0, yy, 0), 3.5, 0.5, group="band", thin=True) for yy in (8.0, 15.0)]
    base = Ellipsoid(DARK_STONE, (0, 1.0, 0), (6.0, 2.2, 4.0), group="stone", bumps=(0.3, 0.6, 43))
    model = _face(GroundCut(Union(base, post, head, *horns, *eyes, mouth, *bands)))
    frame, _ = render_fit(model, 20, 40, name="shrine_idol")
    return finish_prop(frame, skip_groups=("eye",))


def make_shrine_plenty() -> np.ndarray:
    """A stone pedestal holding a wide bowl heaped with old gold."""
    foot = Cylinder(DARK_STONE, (0, 1.4, 0), 5.0, 1.4, round=0.6, group="stone", bumps=(0.2, 0.6, 51))
    stem = RoundCone(DARK_STONE, (0, 2.5, 0), (0, 12.0, 0), 2.6, 2.0, group="stone", bumps=(0.15, 0.6, 52))
    bowl = Subtract(Cylinder(DARK_STONE, (0, 14.0, 0), 7.5, 2.4, round=1.6, group="stone"),
                    Cylinder(DARK_STONE, (0, 16.4, 0), 6.0, 1.6), k=0.4)
    coins = Ellipsoid(GOLD, (0, 15.6, 0), (5.8, 2.2, 5.0), group="gold", bumps=(0.35, 0.9, 53))
    spill = [Cylinder(GOLD, (x, yy, z), 1.1, 0.3, R=rot(70.0, 0.0, 10.0), group="coin")
             for x, yy, z in ((6.5, 0.4, 4.0), (-5.0, 0.4, 5.0))]
    model = _face(GroundCut(Union(foot, stem, bowl, coins, *spill)))
    frame, _ = render_fit(model, 26, 30, name="shrine_plenty")
    return finish_prop(frame)


# --- Wanderers ----------------------------------------------------------------------------------


def _hooded(cloak: Material, hood_y: float = 30.0, belt: Material | None = None) -> list:
    """A hooded figure in a long cloak (feet at y 0): an A-line robe, narrow sloping shoulders, a
    rounded hood standing clear of them, sleeves bent forward with the hands in front, and the face
    a shadow under the hood."""
    robe = RoundCone(cloak, (0, 2.0, 0), (0, hood_y - 7.5, 0), 6.4, 3.2, group="cloak", bumps=(0.15, 0.5, 61))
    hem = Ellipsoid(cloak, (0, 2.0, 0), (6.8, 2.0, 4.6), group="cloak")
    shoulders = Ellipsoid(cloak, (0, hood_y - 6.0, 0), (5.0, 2.4, 3.2), group="cloak")
    hood = Ellipsoid(cloak, (0, hood_y, -0.2), (3.8, 4.2, 3.8), group="cloak")
    peak = RoundCone(cloak, (0, hood_y + 2.0, -1.0), (-0.6, hood_y + 5.0, -2.2), 2.2, 0.6, group="cloak")
    face = Ellipsoid(HOLE, (0, hood_y - 0.6, 2.6), (2.3, 2.8, 1.6), group="face")
    nose = Sphere(SKIN, (0.4, hood_y - 1.0, 3.8), 0.7, group="skin")
    sleeves = []
    hands = []
    for sx in (-1, 1):
        elbow = (sx * 5.0, hood_y - 12.0, 1.2)
        sleeves.append(RoundCone(cloak, (sx * 4.2, hood_y - 6.5, 0.0), elbow, 1.9, 1.7, group="sleeve"))
        sleeves.append(RoundCone(cloak, elbow, (sx * 2.2, hood_y - 14.0, 4.0), 1.7, 1.9, group="sleeve"))
        hands.append(Sphere(SKIN, (sx * 1.6, hood_y - 14.2, 5.2), 1.1, group="skin"))
    parts = [hem, robe, shoulders, *sleeves, hood, peak, face, nose, *hands]
    if belt is not None:
        parts.append(Torus(belt, (0, hood_y - 15.5, 0), 4.3, 0.6, group="belt", thin=True))
    return parts


def make_wanderer_peddler() -> np.ndarray:
    """The Key Peddler: brown cloak, a tall pack on his back hung with keys, a lit lantern."""
    cloak = mat("zone_peddler_cloak", "#6a4a32", below=2, above=1, wrap=0.45)
    parts = _hooded(cloak, hood_y=29.0, belt=LEATHER)
    pack = Box(CANVAS, (-2.5, 30.0, -4.5), (5.0, 7.5, 2.6), round=1.2, group="pack")
    roll = Cylinder(LEATHER, (-2.5, 38.6, -4.5), 1.8, 5.2, R=rot(0.0, 0.0, 90.0), round=0.8, group="roll")
    keys = [Torus(GOLD, (x, yy, -1.6), 0.9, 0.3, R=rot(90.0, 0.0, 0.0), group="keys", thin=True)
            for x, yy in ((-7.2, 26.0), (-7.4, 23.0))]
    lantern = [Capsule(IRON, (2.0, 15.0, 5.4), (2.4, 11.0, 5.6), 0.35, group="iron", thin=True),
               Box(EMBER, (2.4, 9.6, 5.6), (1.3, 1.6, 1.3), round=0.3, group="lantern")]
    model = _face(GroundCut(Union(pack, roll, *keys, *parts, *lantern)))
    frame, _ = render_fit(model, 26, 44, name="wanderer_peddler")
    return finish_prop(frame, skip_groups=("lantern",))


def make_wanderer_robber() -> np.ndarray:
    """The Grave Robber: a dark ragged cloak, a spade over the shoulder, a lumpy sack."""
    cloak = mat("zone_robber_cloak", "#3a3646", below=1, above=2, wrap=0.45, outline=INK)
    parts = _hooded(cloak, hood_y=29.0, belt=LEATHER)
    handle = Capsule(WOOD, (-6.5, 11.0, 1.0), (5.5, 37.0, -2.5), 0.6, group="spade", thin=True)
    blade = Box(IRON, (6.5, 39.2, -2.8), (1.8, 2.6, 0.4), R=rot(0.0, 0.0, -25.0), round=0.3, group="spade")
    sack = Ellipsoid(CANVAS, (-6.5, 5.0, 2.0), (3.6, 4.6, 3.2), group="sack", bumps=(0.4, 0.6, 71))
    tie = Torus(LEATHER, (-6.5, 9.3, 2.0), 1.4, 0.4, group="sack", thin=True)
    model = _face(GroundCut(Union(*parts, handle, blade, sack, tie)))
    frame, _ = render_fit(model, 28, 46, name="wanderer_robber")
    return finish_prop(frame)


def make_wanderer_pilgrim() -> np.ndarray:
    """The Old Pilgrim: a pale travel robe, a wide hat over the hood and a tall walking staff."""
    cloak = mat("zone_pilgrim_cloak", "#a89a78", below=2, above=1, wrap=0.45)
    parts = _hooded(cloak, hood_y=28.5, belt=WOOD)
    brim = Cylinder(LEATHER, (0, 32.5, 0), 7.5, 0.5, round=0.3, group="hat")
    crown = RoundCone(LEATHER, (0, 32.5, 0), (0, 36.0, 0), 3.4, 2.4, group="hat")
    staff = Capsule(WOOD, (7.5, 0.5, 2.5), (7.0, 40.0, 2.5), 0.7, group="staff", thin=True)
    charm = Sphere(EMBER, (7.0, 41.4, 2.5), 0.9, group="charm")
    beard = Ellipsoid(BONE, (0, 25.2, 3.5), (1.8, 2.6, 1.0), group="beard")
    model = _face(GroundCut(Union(*parts, beard, brim, crown, staff, charm)))
    frame, _ = render_fit(model, 24, 46, name="wanderer_pilgrim")
    return finish_prop(frame, skip_groups=("charm",))


# --- Run stops: the campfire, the shopkeeper, the gear icon (DESIGN.md 8.10, 8.11) ------------


def make_campfire() -> np.ndarray:
    """Crossed logs in a ring of stones with a tall fire on them (the campfire screen)."""
    parts = []
    for i, ang in enumerate((-25.0, 25.0, 90.0)):
        R = rot(0.0, ang, 0.0)
        a = R @ np.array([-8.0, 1.6, 0.0])
        b = R @ np.array([8.0, 1.6, 0.0])
        parts.append(RoundCone(WOOD, tuple(a), tuple(b), 1.6, 1.4, group="log", bumps=(0.15, 0.7, 81 + i)))
    for k in range(9):
        t = k / 9.0 * 2.0 * math.pi
        parts.append(Ellipsoid(DARK_STONE, (math.cos(t) * 9.5, 1.0, math.sin(t) * 6.5), (2.0, 1.5, 1.6),
                               group="stone", bumps=(0.2, 0.7, 90 + k)))
    flames = [((0.0, 3.0, 0.0), (0.0, 17.0, 0.0), 4.2, 0.4), ((-2.6, 3.0, 0.6), (-3.6, 12.0, 0.8), 2.6, 0.3),
              ((2.8, 3.0, 0.4), (3.8, 13.5, 0.6), 2.6, 0.3)]
    for i, (a, b, ra, rb) in enumerate(flames):
        parts.append(RoundCone(EMBER, a, b, ra, rb, group="flame"))
    parts.append(RoundCone(Material("zone_flame_core", ["#ffd27a", "#ffe9b0", "#fff6d8"], emissive=True, glow_index=1,
                                    outline=ink_outline("#c26a2a", 0.3)), (0.0, 3.5, 3.6), (0.0, 11.0, 3.4),
                           2.0, 0.3, group="core"))
    model = _face(GroundCut(Union(*parts)))
    frame, _ = render_fit(model, 32, 30, name="campfire")
    return finish_prop(frame, skip_groups=("flame", "core"))


def make_shopkeeper() -> np.ndarray:
    """The Rag Merchant: a stout hooded trader in patched purple, a gold chain and a little set of
    scales in his hands."""
    cloak = mat("zone_merchant_cloak", "#5b3f72", below=2, above=1, wrap=0.45)
    parts = _hooded(cloak, hood_y=29.0, belt=GOLD)
    patch = Box(CANVAS, (-3.5, 10.0, 4.4), (1.4, 1.6, 0.4), group="patch")
    chain = Torus(GOLD, (0, 22.5, 1.0), 3.6, 0.35, R=rot(70.0, 0.0, 0.0), group="chain", thin=True)
    medal = Sphere(GOLD, (0, 19.8, 4.0), 0.9, group="chain")
    post = Capsule(IRON, (1.6, 15.0, 6.0), (1.6, 21.0, 6.0), 0.35, group="scale", thin=True)
    beam = Capsule(IRON, (-2.6, 21.0, 6.0), (5.8, 21.0, 6.0), 0.35, group="scale", thin=True)
    pans = [Ellipsoid(GOLD, (x, 18.6, 6.0), (1.5, 0.5, 1.5), group="scale") for x in (-2.6, 5.8)]
    model = _face(GroundCut(Union(*parts, patch, chain, medal, post, beam, *pans)))
    frame, _ = render_fit(model, 26, 44, name="shopkeeper")
    return finish_prop(frame)


def make_gear_icon() -> np.ndarray:
    """A worn gold amulet with a red stone: the shop's picture for a piece of gear (16x16)."""
    from kit.canvas import Canvas
    c = Canvas(16, 16)
    gold = M["gold"].colors
    red = M["cloth_red"].colors
    c.line(4, 1, 7, 5, gold[1])
    c.line(11, 1, 8, 5, gold[1])
    c.ellipse(7.5, 9.5, 4.6, 4.8, gold[2])
    c.ellipse(7.0, 9.0, 3.6, 3.8, gold[3])
    c.ellipse(7.5, 9.5, 2.3, 2.5, red[2])
    c.px(6, 8, red[-1])
    c.px(10, 12, gold[1])
    c.outline(INK)
    return c.a


PROPS = {
    "seal_stone": make_seal_stone,
    "shrine_spring": make_shrine_spring,
    "shrine_altar": make_shrine_altar,
    "shrine_idol": make_shrine_idol,
    "shrine_plenty": make_shrine_plenty,
    "wanderer_peddler": make_wanderer_peddler,
    "wanderer_robber": make_wanderer_robber,
    "wanderer_pilgrim": make_wanderer_pilgrim,
}


def build(ctx) -> None:
    for name, fn in PROPS.items():
        rgba = fn()
        check(name, rgba)
        ctx.save("sprites/env/%s.png" % name, rgba)
    ctx.save("sprites/env/rot_gate.png", make_rot_gate(), tile=True)
    for name, fn in (("campfire", make_campfire), ("shopkeeper", make_shopkeeper)):
        rgba = fn()
        check(name, rgba)
        ctx.save("sprites/env/%s.png" % name, rgba)
    ctx.save("sprites/ui/gear_icon.png", make_gear_icon(), scale=8)
