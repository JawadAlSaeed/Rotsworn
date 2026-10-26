"""Run-stop things (DESIGN.md 8.10, 8.11): the campfire, the Rag Merchant and the gear icon, and
the hooded figure and materials the event pictures reuse (_event_paint.py).

Until phase 26 this module also drew the long zones' things (DESIGN.md 8.5): the rot seal, the gate
tile, four shrines and three wanderers. They went with the walkable zones (8.22).

Same rules as env_props: small 3D models in the camera-aligned frame (x = screen right, y = up,
z = toward the viewer), rendered with the shared camera and light, cut flat on the ground, outlined.
The game draws them with `fighter_sprite.gdshader`, where `self_glow` makes the WHOLE texture emit,
so anything that glows keeps its stone dark and only its glowing bits bright.
"""
from __future__ import annotations

import math

import numpy as np

from kit.palette import INK, M, Material
from kit.sdf import Box, Capsule, Ellipsoid, RoundCone, Sphere, Torus, Union, rot

from assets.env_props import GroundCut, _face, check, finish_prop, ink_outline, lch_mat, mat, render_fit

# Dark, cold stone for things that glow: the shader multiplies the whole sprite by its glow, so
# the stone must sit low for the runes to stand out.
DARK_STONE = lch_mat("zone_dark_stone", [(0.2, 0.012, 290.0), (0.25, 0.012, 300.0), (0.3, 0.014, 95.0),
                                         (0.355, 0.016, 100.0)], wrap=0.25, ao=0.3, outline_L=0.15)
EMBER = Material("zone_ember", M["glow_amber"].colors, emissive=True, glow_index=2,
                 outline=ink_outline("#c26a2a", 0.25))
GOLD = mat("zone_gold", "#c4a04a", below=2, above=1, spec=0.6, spec_power=8.0, wrap=0.3)
WOOD = mat("zone_wood", "#5e4634", below=2, above=1, wrap=0.3)
IRON = mat("zone_iron", "#4c505c", below=2, above=1, spec=0.4, wrap=0.2, outline=INK)
SKIN = M["skin"]
LEATHER = mat("zone_leather", "#6e4a33", below=2, above=1, wrap=0.35)
CANVAS = mat("zone_canvas", "#8a7a52", below=2, above=1, wrap=0.45)
HOLE = Material("zone_hood_dark", [INK, "#241c22"], hi=1.0, outline=INK)

# --- A hooded figure (the Rag Merchant, and the event pictures) ----------------------------------


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


def build(ctx) -> None:
    for name, fn in (("campfire", make_campfire), ("shopkeeper", make_shopkeeper)):
        rgba = fn()
        check(name, rgba)
        ctx.save("sprites/env/%s.png" % name, rgba)
    ctx.save("sprites/ui/gear_icon.png", make_gear_icon(), scale=8)
