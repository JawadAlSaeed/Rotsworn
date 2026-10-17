"""The "?" stops' pictures (DESIGN.md 5.4 and 8.7, card #199): one small painted scene per event, and
one for each act's ambush page.

Each picture is 128x64 art pixels, fully opaque. The event screen shows it at `picture_scale`
(data/presentation/stop_visuals.tres) with nearest filtering inside a thin frame. They are built in
two layers so they match the rest of the game:

- the back, painted flat with the kit's colour ramps (`Painter` in _event_paint.py): a sky, far
  ridges and dead trees, ground, mist, glows and a vignette. Bands are cut by a light ordered
  dither, never blended, so every pixel is a ramp colour.
- the front, the thing the event is about, built as a small 3D model and rendered by the same
  camera and light as every prop and fighter (`render_fit`, `finish_prop`), then pasted on the
  back over a soft contact shadow. One art pixel is one model unit, so a hooded figure here is the
  size of the shop's.

Everything is deterministic (seeded noise, no wall clock). The last step snaps every pixel to the
colours the scene was made of, so a picture holds a few dozen colours, no more.

- sprites/events/<event id>.png: one per event in data/events/ (16).
- sprites/events/ambush_<act id>.png: the page a "?" that turned into a fight shows (one per act).
"""
from __future__ import annotations

import math

import numpy as np

from kit.sdf import (Box, Capsule, Cylinder, Ellipsoid, Moved, Prism, RoundCone, SmoothUnion, Sphere, Subtract,
                     Torus, Union, rot)
from kit.render import line3d, stamp

from assets._event_paint import *  # noqa: F401,F403
from assets._event_paint import _hooded, _face, _world  # noqa: F401


def prop(model, w: int, h: int, name: str, skip: tuple[str, ...] = (), post=None, centre: str = "origin",
         scale: float = 1.0, **kw) -> np.ndarray:
    """A model (camera-aligned frame, feet on y = 0) as a finished sprite w x h. `post(frame, cam)`
    may add stamps and thin lines before the outline. `scale` blows the model up about its feet (the
    pictures are close-ups, so a figure here may stand taller than one in a fight)."""
    if scale != 1.0:
        model = Scaled(model, scale)
    frame, cam = render_fit(_face(GroundCut(model)), w, h, name=name, centre=centre)
    if post is not None:
        post(frame, cam)
    return finish_prop(frame, skip_groups=skip, **kw)


def backdrop(seed: int, sky: list[str], hz: int, ground: list[str], ground_tone: float = 0.45,
             far_tone: float = 0.5, trees: tuple = (), moon: tuple | None = None, ridge_amp: float = 8.0,
             tree_col: int = 1, stars: int = 0) -> Painter:
    """The back every outdoor picture shares: sky (with a moon), two ridges, bare trees, ground."""
    p = new_painter(seed)
    p.sky(sky, hz, stars=stars)
    if moon is not None:
        mx, my, mr = moon
        p.disk(mx, my, mr, lch_ramp([(0.36, 0.02, 330.0), (0.46, 0.02, 340.0), (0.56, 0.02, 350.0)]),
               halo=mr * 2.4)
    p.ridge(SILHOUETTE, hz - 1, ridge_amp * 1.5, 34.0, seed + 4, far_tone + 0.12, fade=0.3, y_to=hz + 4)
    p.ridge(SILHOUETTE, hz + 1, ridge_amp, 21.0, seed + 7, far_tone - 0.06, fade=0.2, y_to=hz + 4)
    for x, h in trees:
        p.dead_tree(x, hz + 3, h, rgb(SILHOUETTE[tree_col]), x + seed, lean=0.08 * ((x % 3) - 1))
    p.ground(ground, hz + 2, tone=ground_tone, seed=seed)
    return p


# --- The Tithe Collector: a hooded figure in a road that stops at the edge of nothing ------------


def scene_tithe_collector() -> np.ndarray:
    p = new_painter(11)
    hz = 33
    p.sky(DUSK, hz)
    p.disk(100, 13, 5, lch_ramp([(0.35, 0.02, 330.0), (0.45, 0.02, 340.0), (0.55, 0.02, 350.0)]), halo=12)
    p.ridge(SILHOUETTE, hz, 6, 30.0, 4, 0.5, fade=0.25)
    for x, h in ((7, 22), (22, 14), (108, 17), (120, 25)):
        p.dead_tree(x, hz + 2, h, rgb(SILHOUETTE[1]), x, lean=0.1)
    p.ground(DEAD_GRASS[:4], hz + 1, tone=0.45, seed=2)
    # The road: a pale dirt band widening toward the viewer.
    cx = 64.0 + 2.5 * np.sin(YY / 6.0)
    half = 2.0 + (YY - hz) * 0.75
    road = (np.abs(XX + 0.5 - cx) < half) & (YY > hz)
    rut = np.abs(np.abs(XX + 0.5 - cx) - half * 0.5) < 0.8
    t = 0.55 + (fbm2(XX / 5.0, YY / 2.0, seed=31) - 0.5) * 0.45 - rut * 0.15
    p.paint(road, ROAD, t, d=0.4)
    # Where the road behind the collector should be there is a bite of nothing, ragged at its rim.
    rim = 1.0 - np.hypot((XX + 0.5 - 62.0) / 34.0, (YY + 0.5 - 43.0) / 12.5)         + (fbm2(XX / 4.0, YY / 3.0, seed=77, octaves=3) - 0.5) * 0.5
    bite = (rim > 0.0) & (YY > hz - 1)
    p.paint(bite, VOID, 0.1 + 0.8 * np.clip(rim * 1.2, 0, 1) * 0.0 + 0.55 * (1.0 - (YY - hz) / 24.0), d=0.45)
    lip = bite & (rim < 0.12)
    p.paint(lip & (YY > 40), SILHOUETTE[:3], np.full_like(XX, 0.3))
    for (sx, sy, w) in ((44, 36, 3), (82, 38, 2), (52, 33, 2), (72, 34, 3), (90, 35, 2)):
        p.img[sy, sx:sx + w] = rgb(ROAD[2])
        p.img[sy + 1, sx:sx + w - 1] = rgb(ROAD[0])
    p.mist(hz + 6, 6, "#7a6a88", strength=0.45)
    # The figure and its bowl, standing on the near rim.
    cloak = mat("ev_tithe_cloak", "#4a4054", below=2, above=1, wrap=0.45, outline=INK)
    parts = _hooded(cloak, hood_y=26.0, belt=LEATHER)
    bowl = Subtract(Cylinder(BONE, (0.0, 11.2, 7.0), 3.2, 1.2, round=0.8, group="bowl"),
                    Cylinder(BONE, (0.0, 12.6, 7.0), 2.4, 0.9))
    fig = prop(Union(*parts, bowl), 26, 40, "tithe")
    p.shadow(64, 57, 9, 2.4)
    p.paste(fig, 64, 58)
    p.mist(60, 4, "#5a4a62", strength=0.2, seed=3)
    p.vignette(0.55)
    return p.rgba()


# --- The Weeping Well -----------------------------------------------------------------------------

WELL_STONE = lch_mat("ev_well_stone", [(0.22, 0.02, 250.0), (0.29, 0.018, 255.0), (0.36, 0.016, 270.0),
                                       (0.43, 0.014, 300.0), (0.5, 0.016, 90.0)], wrap=0.25, ao=0.35,
                     outline_L=0.15)


def scene_weeping_well() -> np.ndarray:
    p = backdrop(21, OLIVE_SKY, 30, DEAD_GRASS[:4], ground_tone=0.32, far_tone=0.42,
                 trees=((6, 24), (20, 16), (101, 18), (116, 27), (92, 11)), moon=(30, 13, 4))
    p.glow(64, 52, 34, 9, CYAN_GLOW, strength=0.35, levels=3)
    ring = Subtract(Cylinder(WELL_STONE, (0, 4.8, 0), 13.0, 4.8, round=1.0, group="stone", bumps=(0.45, 0.5, 5)),
                    Cylinder(WELL_STONE, (0, 7.2, 0), 10.0, 4.2))
    water = Ellipsoid(WATER_DARK, (0, 7.0, 0), (10.2, 0.9, 10.2), group="water")
    glint = Sphere(WATER_GLINT, (2.5, 7.2, 3.0), 0.9, group="glint")
    rope = Capsule(LEATHER, (0.0, 23.0, -1.0), (0.0, 13.0, 3.0), 0.35, group="rope", thin=True)
    bucket = Cylinder(WOOD, (0.0, 11.4, 3.4), 2.2, 1.8, round=0.4, group="bucket")
    posts = [Capsule(WOOD_ROT, (sx * 12.0, 6.0, -4.0), (sx * 11.4, 25.0, -4.0), 1.5, group="post",
                     bumps=(0.3, 0.6, 7 + int(sx))) for sx in (-1, 1)]
    beam = Capsule(WOOD_ROT, (-13.5, 24.0, -4.0), (13.5, 24.3, -4.0), 1.3, group="post", bumps=(0.25, 0.6, 9))
    roof = Prism(WOOD_ROT, (0.0, 25.0, -4.0), [(-15.5, 0.0), (15.5, 0.0), (0.0, 6.0)], 5.5, round=0.5,
                 group="roof", bumps=(0.3, 0.5, 4))
    model = Union(ring, water, glint, rope, bucket, *posts, beam, roof)

    def tears(frame, cam):
        for x, y0, n in ((-8.0, 8.5, 5), (-3.0, 8.5, 3), (4.5, 8.5, 6), (9.5, 8.5, 4)):
            pts = [_world((x, y0 - k, math.sqrt(max(169.0 - x * x, 1.0)) - 0.3)) for k in range(n + 1)]
            line3d(frame, cam, pts, WATER_GLINT, 0, group="tear", depth_bias=0.2)

    sprite = prop(model, 46, 40, "well", skip=("glint", "tear"), post=tears)
    p.shadow(64, 57, 15, 3)
    p.paste(sprite, 64, 58)
    p.glow(64, 41, 14, 9, PURPLE_GLOW, strength=0.3, levels=3)
    p.motes(9, 54, 76, 20, 44, "#b98cff", seed=2)
    p.mist(55, 5, "#4f6c66", strength=0.3)
    p.vignette(0.5)
    return p.rgba()


# --- Gambler's Bones -----------------------------------------------------------------------------


def scene_gamblers_bones() -> np.ndarray:
    p = backdrop(31, NIGHT, 31, MUD[:4], ground_tone=0.4, far_tone=0.4,
                 trees=((8, 26), (21, 17), (104, 22), (118, 15), (40, 10), (88, 10)), moon=(100, 11, 4), stars=10)
    p.glow(64, 40, 30, 20, AMBER_GLOW, strength=0.55, levels=4)
    table_top = Box(WOOD_ROT, (0.0, 15.0, 6.0), (21.0, 1.2, 8.5), round=0.5, group="wood", bumps=(0.3, 0.6, 3))
    legs = [Box(WOOD_ROT, (sx * 18.5, 7.0, 6.0 + sz * 6.0), (1.3, 7.0, 1.3), round=0.4, group="wood",
                bumps=(0.3, 0.6, 5)) for sx in (-1, 1) for sz in (-1, 1)]
    chair = Box(WOOD_ROT, (0.0, 22.0, -9.0), (8.0, 22.0, 1.3), round=0.5, group="wood", bumps=(0.3, 0.6, 8))
    slats = [Box(WOOD_ROT, (0.0, 26.0 + 6.0 * k, -9.0), (9.0, 0.9, 1.5), group="wood") for k in range(3)]
    chest = Ellipsoid(HOLE, (0.0, 23.5, -3.8), (5.0, 7.0, 2.2), group="void")
    ribs = [Capsule(BONE, (-5.4 + k * 0.4, 18.5 + 3.0 * k, -2.0), (5.4 - k * 0.4, 18.5 + 3.0 * k, -2.0), 0.85,
                    group="ribs", thin=True) for k in range(4)]
    spine = Capsule(BONE, (0.0, 15.5, -3.6), (0.0, 29.0, -3.6), 0.9, group="ribs")
    collar = Capsule(BONE, (-6.5, 29.2, -2.4), (6.5, 29.2, -2.4), 0.9, group="ribs")
    shoulders = [Sphere(BONE, (sx * 6.9, 28.6, -2.2), 1.5, group="ribs") for sx in (-1, 1)]
    arms = []
    for sx in (-1, 1):
        arms.append(Capsule(BONE, (sx * 6.9, 28.2, -2.2), (sx * 8.6, 20.5, 2.5), 0.85, group="arm"))
        arms.append(Capsule(BONE, (sx * 8.6, 20.5, 2.5), (sx * 5.2, 17.5, 9.5), 0.8, group="arm"))
        arms.append(Sphere(BONE, (sx * 5.0, 17.4, 10.8), 1.25, group="arm"))
    skull = Sphere(BONE, (0.0, 35.3, -2.4), 4.3, group="skull", bumps=(0.15, 0.7, 2))
    jaw = Ellipsoid(BONE, (0.0, 31.3, -1.2), (2.9, 1.7, 2.6), group="skull")
    sockets = [Sphere(HOLE, (sx * 1.9, 35.6, 1.0), 1.2, group="eye") for sx in (-1, 1)]
    nose = Ellipsoid(HOLE, (0.0, 33.3, 1.7), (0.6, 0.9, 0.6), group="eye")
    brim = Cylinder(CLOTH_BLACK, (0.5, 38.8, -2.4), 8.4, 0.5, R=rot(-10.0, 0.0, 6.0), round=0.3, group="hat")
    crown = Cylinder(CLOTH_BLACK, (0.7, 41.6, -2.4), 4.2, 2.6, R=rot(-10.0, 0.0, 6.0), round=0.9, group="hat")
    band = Torus(GOLD_DULL, (0.6, 39.8, -2.4), 4.3, 0.45, R=rot(-10.0, 0.0, 6.0), group="band", thin=True)
    dice = [Box(CREAM, (sx * 4.0, 18.6, 11.0), (1.1, 1.1, 1.1), R=rot(0.0, 25.0 + 40 * k, 0.0), group="dice")
            for k, sx in ((0, -1), (1, 1))]
    dice.append(Box(CREAM, (1.5, 16.9, 7.5), (1.0, 1.0, 1.0), R=rot(10.0, 60.0, 0.0), group="dice"))
    coins = [Cylinder(GOLD, (-13.0, 16.5 + 0.55 * k, 8.0), 1.7, 0.28, group="coin") for k in range(4)]
    candle = Cylinder(BONE, (14.0, 19.0, 4.0), 1.1, 2.6, group="candle")
    flame = Sphere(AMBER, (14.0, 22.6, 4.0), 0.9, group="flame")
    model = Union(table_top, *legs, chair, *slats, chest, *ribs, spine, collar, *shoulders, *arms, skull, jaw,
                  *sockets, nose, brim, crown, band, *dice, *coins, candle, flame)
    sprite = prop(model, 52, 52, "bones", skip=("flame",))
    p.shadow(64, 57, 24, 4)
    p.paste(sprite, 64, 58)
    p.glow(78, 37, 6, 5, AMBER_GLOW, strength=0.6, levels=3, power=1.0)
    p.mist(57, 4, "#4a4458", strength=0.25)
    p.vignette(0.55)
    return p.rgba()


# --- The Hungry Scarecrow ------------------------------------------------------------------------


def scene_hungry_scarecrow() -> np.ndarray:
    p = backdrop(41, ASH_SKY, 30, DIRT[:4], ground_tone=0.36, far_tone=0.45,
                 trees=((12, 14), (112, 16), (98, 9)), moon=(88, 14, 5), ridge_amp=4.0)
    # Dead stalks in rows running to the horizon.
    rng = np.random.default_rng(5)
    for row in range(10):
        y = 31 + int(row ** 1.5 * 1.1)
        for x in range(2 + (row * 7) % 6, SW, 5 + row // 3):
            if abs(x - 64) < 7 + row:
                continue
            h = 2 + row // 2
            if rng.random() < 0.85:
                p.pixels([(x, y - k) for k in range(h)], rgb("#6a5c38") * (0.7 + 0.04 * row))
                p.pixels([(x + 1, y - h + 1)], rgb("#7d6d42"))
    body = Ellipsoid(CLOTH_GREY, (0.0, 29.0, 0.5), (6.0, 8.5, 3.2), group="shirt", bumps=(0.4, 0.6, 3))
    post = Capsule(WOOD, (0.0, -1.0, -0.5), (0.0, 46.0, -0.5), 1.5, group="post", bumps=(0.25, 0.7, 11))
    bar = Capsule(WOOD, (-15.0, 33.5, -0.5), (15.0, 33.0, -0.5), 1.2, group="post", bumps=(0.2, 0.7, 12))
    sleeves = []
    for sx in (-1, 1):
        sleeves.append(RoundCone(CLOTH_BROWN, (sx * 4.0, 33.5, 0.0), (sx * 13.5, 33.0, 0.2), 3.0, 2.2, group="sleeve",
                                 bumps=(0.35, 0.6, 4)))
        for k in range(3):
            sleeves.append(Capsule(STRAW, (sx * (13.0 + k * 0.6), 33.0, 0.0), (sx * (17.0 + k), 31.0 - 2.4 * k, 0.5),
                                   0.35, group="straw", thin=True))
        for k in range(3):
            x0 = sx * (5.0 + 3.5 * k)
            sleeves.append(Prism(CLOTH_BROWN, (x0, 31.0, 1.0), [(-1.7, 0.0), (1.7, 0.0), (0.2, -4.5 - k)], 0.5,
                                 group="sleeve"))
    hem = [Prism(CLOTH_GREY, (-4.5 + 3.0 * k, 22.0, 3.0), [(-1.6, 0.0), (1.6, 0.0), (0.0, -3.0 - (k % 2) * 1.5)], 0.5,
                 group="shirt") for k in range(4)]
    head = Ellipsoid(CANVAS, (0.0, 42.0, 0.8), (5.6, 6.2, 4.9), group="sack", bumps=(0.45, 0.5, 6))
    tie = Torus(LEATHER, (0.0, 37.3, 0.4), 3.4, 0.55, group="tie", thin=True)
    top = [Ellipsoid(CANVAS, (0.4, 47.6, 0.6), (1.7, 1.9, 1.6), group="sack"),
           Torus(LEATHER, (0.4, 46.4, 0.6), 1.5, 0.35, group="tie", thin=True)]
    neck = [Capsule(STRAW, (sx * 2.0, 37.0, 3.0), (sx * 4.6, 35.4 - k, 4.0), 0.35, group="straw", thin=True)
            for sx in (-1, 1) for k in range(2)]
    grain = [Ellipsoid(STRAW, (3.5 + 3.0 * k - (k % 2) * 7.0, 0.7, 5.0 + (k % 3) * 2.0), (1.7, 0.7, 1.2),
                       group="grain") for k in range(5)]

    def face(frame, cam):
        for sx in (-1, 1):
            stamp(frame, cam, _world((sx * 2.5, 43.6, 5.4)), ["xx", "xx"], {"x": (HOLE, 0)}, origin=(0, 0))
        stamp(frame, cam, _world((0.0, 39.6, 5.7)), ["xxxxxxx"], {"x": (HOLE, 0)}, origin=(3, 0))
        stamp(frame, cam, _world((0.0, 38.8, 5.7)), ["c.c.c.c"], {"c": (CREAM, 1)}, origin=(3, 0))
        stamp(frame, cam, _world((0.0, 40.4, 5.7)), ["c.c.c.c"], {"c": (CREAM, 1)}, origin=(3, 0))

    model = Union(body, post, bar, *sleeves, *hem, head, tie, *top, *neck, *grain)
    sprite = prop(model, 46, 62, "scarecrow", post=face)
    p.shadow(64, 57, 11, 2.5)
    p.paste(sprite, 64, 58)
    for x, y in ((38, 20), (47, 14), (96, 22)):
        p.pixels([(x, y), (x + 1, y), (x - 1, y - 1), (x + 2, y - 1)], rgb(SILHOUETTE[0]))
    p.mist(57, 4, "#6a6048", strength=0.25)
    p.vignette(0.55)
    return p.rgba()


# --- The Black Mirror ----------------------------------------------------------------------------


def scene_black_mirror() -> np.ndarray:
    hz = 30
    p = backdrop(51, NIGHT, hz, DEAD_GRASS[:4], ground_tone=0.3, far_tone=0.38,
                 trees=((7, 22), (22, 14), (113, 20)), moon=(36, 12, 4), stars=14)
    p.water(WATER_DARK.colors, hz + 4, tone=0.55, seed=2)
    # The drowned oak the mirror leans on: a big bare silhouette standing in the water.
    p.big_tree(84, hz + 15, 46, 6.0, rgb(SILHOUETTE[0]), 5, lean=-0.12, limbs=5)
    frame_mat = GOLD_DULL
    outer = Union(Box(frame_mat, (0.0, 20.0, 0.0), (11.0, 20.0, 1.7), round=1.0, group="frame", bumps=(0.2, 0.9, 3)),
                  Cylinder(frame_mat, (0.0, 40.0, 0.0), 11.0, 1.7, R=rot(90.0, 0.0, 0.0), round=1.0, group="frame"))
    glass = Union(Box(BLACK_GLASS, (0.0, 20.0, 1.3), (8.6, 18.0, 1.0), group="glass"),
                  Cylinder(BLACK_GLASS, (0.0, 38.0, 1.3), 8.6, 1.0, R=rot(90.0, 0.0, 0.0), group="glass"))
    feet = [Box(frame_mat, (sx * 7.0, 0.8, 3.0), (2.0, 0.8, 1.2), group="frame") for sx in (-1, 1)]
    model = Moved(Union(outer, glass, *feet), R=rot(-7.0, 0.0, 3.0))
    sprite = prop(model, 34, 62, "mirror", skip=())
    # Paint the glass: a cold sheen, and the party looking back.
    glass_cols = {tuple(int(v) for v in rgb(c) * 255 + 0.5) for c in BLACK_GLASS.colors}
    mask = np.zeros(sprite.shape[:2], bool)
    for y in range(sprite.shape[0]):
        for x in range(sprite.shape[1]):
            if sprite[y, x, 3] and tuple(int(v) for v in sprite[y, x, :3]) in glass_cols:
                mask[y, x] = True
    ys, xs = np.nonzero(mask)
    deep = lch_ramp([(0.15, 0.035, 300.0), (0.2, 0.05, 296.0), (0.27, 0.06, 290.0), (0.36, 0.07, 280.0),
                     (0.5, 0.075, 250.0)])
    if len(ys):
        y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
        rr = ramp_rgb(deep)
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if not mask[y, x]:
                    continue
                streak = ((x - x0) * 1.0 + (y - y0) * 0.8) % 17.0
                t = 0.18 + 0.5 * (1.0 - (y - y0) / max(1, y1 - y0)) * 0.6
                if streak < 2.0:
                    t += 0.32
                elif 5.0 < streak < 6.0:
                    t += 0.15
                k = int(np.clip(math.floor(t * 4 + B[y, x] * 0.5), 0, 4))
                sprite[y, x, :3] = (rr[k] * 255 + 0.5).astype(np.uint8)
        # Three dark figures stand in the glass, a moment too late; their eyes catch the light.
        cxg = (x0 + x1) // 2
        for k, (dx, hgt, base) in enumerate(((-4, 10, 0), (0, 12, 1), (4, 10, 0))):
            by = y1 - 1 - base
            top = by - hgt
            for yy in range(top, by + 1):
                w = 2 if yy < top + 4 else 3 + (yy - top - 4) // 3
                for xx in range(cxg + dx - w, cxg + dx + w):
                    if 0 <= yy < sprite.shape[0] and 0 <= xx < sprite.shape[1] and mask[yy, xx]:
                        sprite[yy, xx, :3] = (rr[0] * 255 + 0.5).astype(np.uint8)
            ey = top + 2
            for ex in (cxg + dx - 1, cxg + dx + 1):
                if mask[ey, ex]:
                    sprite[ey, ex, :3] = (rgb(CYAN_GLOW) * 255 + 0.5).astype(np.uint8)
    p.palette.extend(deep)
    p.palette.append(CYAN_GLOW)
    p.reflect(sprite, 60, 58, 6, strength=0.5, tint="#14203a")
    p.glow(60, 36, 20, 28, "#7a5cc8", strength=0.22, levels=3)
    p.paste(sprite, 60, 58)
    p.mist(58, 3, "#4a5a78", strength=0.3)
    p.vignette(0.55)
    return p.rgba()


# --- The Buried Cairn ----------------------------------------------------------------------------


def scene_buried_cairn() -> np.ndarray:
    p = backdrop(61, ASH_SKY, 31, DEAD_GRASS[:4], ground_tone=0.34, far_tone=0.5,
                 trees=((9, 18), (118, 22), (104, 11)), ridge_amp=9.0)
    p.tufts(26, 36, 62, "#4f5530", seed=1)
    p.pebbles(18, 36, 62, "#7b7570", "#403b3c", seed=2)
    # The pit someone started: a dark hole in the grass with a rim of thrown earth.
    d = np.hypot((XX + 0.5 - 90.0) / 13.0, (YY + 0.5 - 52.0) / 3.8)
    p.paint((d < 1.35) & (d >= 1.0), DIRT, 0.7 - 0.4 * (YY - 49.0) / 6.0, d=0.3)
    p.paint(d < 1.0, VOID, 0.25 + 0.6 * np.clip((YY - 48.0) / 6.0, 0, 1) * 0.0 + 0.0 * XX, d=0.2)
    stones = []
    spec = [((-9.5, 3.4, 0.0), (6.8, 3.9, 5.2)), ((0.5, 3.0, 2.0), (6.4, 3.4, 5.0)), ((9.8, 3.1, -1.0), (5.6, 3.2, 4.6)),
            ((-5.0, 8.6, 0.5), (6.0, 3.6, 4.7)), ((5.0, 8.4, 0.5), (5.8, 3.4, 4.5)),
            ((-1.0, 13.2, 0.8), (5.6, 3.4, 4.4)), ((3.0, 17.4, 0.5), (4.4, 3.0, 3.8)), ((0.0, 21.0, 0.3), (3.2, 2.4, 3.0))]
    for k, (pos, rad) in enumerate(spec):
        stones.append(Ellipsoid(STONE, pos, rad, R=rot(0.0, 20.0 * k, 4.0 * (k % 3)), group="stone", bumps=(0.55, 0.55, 20 + k)))
    moss = [Ellipsoid(MOSS, (-7.0, 6.0, 4.0), (3.4, 1.2, 2.2), group="moss", bumps=(0.4, 0.8, 3)),
            Ellipsoid(MOSS, (6.0, 11.2, 2.5), (2.6, 1.0, 1.8), group="moss", bumps=(0.4, 0.8, 4))]
    slab = Box(SAND_STONE, (-0.6, 10.5, 5.4), (3.4, 5.0, 0.9), R=rot(-6.0, 0.0, 3.0), round=0.5, group="slab",
               bumps=(0.2, 0.9, 8))

    def scratches(frame, cam):
        rows = ["x.xx.x", ".x..x.", "xx.x.x", "..xx..", "x.x.xx"]
        for r, row in enumerate(rows):
            stamp(frame, cam, _world((-3.0, 14.0 - r * 1.8, 6.5)), [row], {"x": (HOLE, 0)}, origin=(0, 0))

    cairn = prop(Union(*stones, *moss, slab), 54, 46, "cairn", post=scratches, scale=1.3)
    # The spoil heap and the spade left standing in it.
    heap = Ellipsoid(SOIL_FRESH, (0.0, 3.2, 0.0), (11.0, 4.6, 6.0), group="soil", bumps=(0.8, 0.6, 5))
    clod = [Ellipsoid(SOIL_FRESH, (sx, 1.0, 5.6), (2.0, 1.2, 1.6), group="soil", bumps=(0.5, 0.8, 6)) for sx in (-6.5, 7.5)]
    shaft = Capsule(WOOD, (2.5, 5.0, 1.0), (4.5, 24.0, 1.0), 0.7, group="spade", thin=True)
    grip = Capsule(WOOD, (3.4, 24.6, 1.0), (7.0, 24.2, 1.0), 0.75, group="spade")
    blade = Box(IRON, (2.2, 7.2, 1.0), (2.0, 3.2, 0.5), R=rot(0.0, 0.0, 6.0), round=0.3, group="spade")
    mound = prop(Union(heap, *clod, shaft, grip, blade), 30, 30, "heap")
    p.shadow(48, 58, 22, 4)
    p.paste(cairn, 48, 59)
    p.shadow(98, 59, 13, 2.5)
    p.paste(mound, 98, 60)
    for x, y in ((24, 15), (31, 12), (30, 19)):
        p.pixels([(x, y), (x + 1, y), (x - 1, y - 1), (x + 2, y - 1), (x + 1, y + 1)], rgb(SILHOUETTE[0]))
    p.mist(55, 5, "#6f6a70", strength=0.3)
    p.vignette(0.5)
    return p.rgba()


# --- The Drowned Chapel --------------------------------------------------------------------------


def scene_drowned_chapel() -> np.ndarray:
    hz = 28
    p = backdrop(71, NIGHT, hz, DEAD_GRASS[:4], ground_tone=0.3, far_tone=0.4,
                 trees=((6, 20), (118, 24), (17, 11)), moon=(100, 13, 4), stars=16, ridge_amp=8.0)
    wl = 49  # the water line on the chapel
    p.water(WATER_DARK.colors, hz + 3, tone=0.5, seed=4)
    p.mist(hz + 5, 5, "#56648a", strength=0.4)
    nave = Box(SAND_STONE, (-9.0, 12.0, 0.0), (13.0, 12.0, 8.0), round=0.6, group="wall", bumps=(0.35, 0.6, 3))
    gable = Prism(SAND_STONE, (-9.0, 24.0, 0.0), [(-14.0, 0.0), (14.0, 0.0), (0.0, 11.0)], 8.4, group="roof",
                  bumps=(0.3, 0.6, 5))
    roof = Prism(WOOD_ROT, (-9.0, 24.0, 0.0), [(-15.5, -0.6), (15.5, -0.6), (0.0, 11.8), (0.0, 9.6)], 9.2,
                 group="tiles", bumps=(0.3, 0.8, 6))
    tower = Box(SAND_STONE, (13.0, 20.0, 0.0), (6.4, 20.0, 6.4), round=0.5, group="wall", bumps=(0.35, 0.6, 7))
    belfry = Box(HOLE, (13.0, 36.0, 4.2), (3.2, 4.4, 3.0), group="void")
    bell = RoundCone(GOLD_DULL, (13.0, 38.0, 2.0), (13.0, 33.4, 2.0), 1.4, 2.8, group="bell")
    spire = Union(Prism(WOOD_ROT, (13.0, 40.0, 0.0), [(-7.4, 0.0), (7.4, 0.0), (0.0, 12.0)], 1.5, group="tiles"),
                  Prism(WOOD_ROT, (13.0, 40.0, 0.0), [(-7.4, 0.0), (7.4, 0.0), (0.0, 12.0)], 1.5, R=rot(0.0, 90.0, 0.0), group="tiles"))
    door = Box(HOLE, (-9.0, 6.0, 8.2), (3.2, 6.0, 0.8), group="void")
    arch = Cylinder(HOLE, (-9.0, 12.0, 8.2), 3.2, 0.8, R=rot(90.0, 0.0, 0.0), group="void")
    window = Cylinder(HOLE, (-9.0, 20.0, 8.2), 2.0, 0.8, R=rot(90.0, 0.0, 0.0), group="void")
    cross = Union(Box(IRON, (13.0, 53.0, 0.0), (0.45, 2.4, 0.45), group="cross", thin=True),
                  Box(IRON, (13.0, 54.0, 0.0), (1.6, 0.45, 0.45), group="cross", thin=True))
    model = Union(nave, gable, roof, tower, belfry, bell, spire, door, arch, window, cross)
    sprite = prop(model, 56, 62, "chapel", centre="bbox")
    # Only what stands above the water: cut the sprite at the water line, with its reflection below.
    keep = sprite.shape[0] - 2 - (58 - wl)
    cut = sprite[:keep].copy()
    cut[-1:, :, :3] = (cut[-1:, :, :3] * 0.45).astype(np.uint8)
    p.reflect(np.vstack([cut, np.zeros((2, cut.shape[1], 4), np.uint8)]), 64, wl, 16, strength=0.45, tint="#14203a")
    p.glow(64, wl, 34, 6, "#5f78b8", strength=0.25, levels=3)
    p.paste(np.vstack([cut, np.zeros((2, cut.shape[1], 4), np.uint8)]), 64, wl + 1)
    # The ripples rising from the dark where something keeps time with the bell.
    for r, a in ((26, 0.9), (36, 0.6), (47, 0.4)):
        ring = np.abs(np.hypot((XX + 0.5 - 64.0) / r, (YY + 0.5 - (wl + 3.0)) / (r * 0.16)) - 1.0)
        p.tint(np.where((ring < 0.045) & (YY > wl + 1), a, 0.0), "#8aa2d8", levels=2, strength=0.55)
    for x, y in ((24, 56), (98, 54), (40, 59), (88, 60)):
        p.pixels([(x, y), (x + 1, y), (x + 2, y)], "#5a6c98")
    p.mist(wl + 2, 3, "#56648a", strength=0.3, seed=2)
    p.vignette(0.55)
    return p.rgba()


# --- The Hanging Cage ----------------------------------------------------------------------------


def scene_hanging_cage() -> np.ndarray:
    p = backdrop(81, DUSK, 30, DEAD_GRASS[:4], ground_tone=0.34, far_tone=0.45,
                 trees=((7, 22), (117, 24), (110, 12)), moon=(104, 12, 4), ridge_amp=8.0)
    p.tufts(24, 38, 62, "#4f5530", seed=3)
    p.pebbles(14, 38, 62, "#7b7570", "#403b3c", seed=4)
    parts = []
    parts += branch(BARK, [(-18.0, -1.5, 0.0), (-17.0, 12.0, 0.2), (-19.0, 26.0, 0.0), (-17.5, 40.0, 0.0), (-18.0, 49.0, 0.0)],
                    [4.6, 3.6, 3.2, 2.8, 2.4], group="tree", amp=0.3, ridges=4, twist=0.2)
    parts += roots(BARK, [(-25.0, 2.0, 1.4, 1.0), (-12.0, 3.0, 1.2, 0.9), (-18.0, -3.0, 1.2, 0.9)], "tree", 4.0, 2.6)
    parts += branch(BARK, [(-17.5, 41.0, 0.0), (-8.0, 45.0, 0.0), (4.0, 46.0, 0.0), (16.0, 44.5, 0.0), (24.0, 42.5, 0.0)],
                    [2.2, 1.9, 1.6, 1.3, 1.0], group="tree", ridged=False)
    parts += branch(BARK, [(-8.0, 45.0, 0.0), (-10.0, 51.0, 0.0), (-8.0, 56.0, 0.0)], [1.0, 0.8, 0.6], group="tree", ridged=False)
    parts += branch(BARK, [(4.0, 46.0, 0.0), (7.0, 52.0, 0.0), (5.5, 58.0, 0.0)], [1.0, 0.8, 0.6], group="tree", ridged=False)
    parts += branch(BARK, [(-19.0, 26.0, 0.0), (-26.0, 31.0, 0.0), (-31.0, 29.0, 0.0)], [1.4, 1.0, 0.7], group="tree", ridged=False)
    tree = SmoothUnion(*parts, k=1.0)
    cx = 22.0
    top, bot, R0 = 30.0, 6.0, 6.5
    bars = []
    for k in range(10):
        a = k * math.tau / 10.0
        bars.append(Capsule(CAGE_IRON, (cx + R0 * math.cos(a), bot, R0 * 0.7 * math.sin(a)),
                            (cx + R0 * math.cos(a) * 0.82, top, R0 * 0.7 * math.sin(a) * 0.82), 0.42, group="bars", thin=True))
        bars.append(Capsule(CAGE_IRON, (cx + R0 * math.cos(a) * 0.82, top, R0 * 0.7 * math.sin(a) * 0.82),
                            (cx, top + 5.0, 0.0), 0.38, group="bars", thin=True))
    rings = [Torus(CAGE_IRON, (cx, bot, 0.0), R0, 0.5, R=np.diag([1.0, 1.0, 0.7]), group="bars", thin=True),
             Torus(CAGE_IRON, (cx, top, 0.0), R0 * 0.82, 0.5, R=np.diag([1.0, 1.0, 0.7]), group="bars", thin=True),
             Torus(CAGE_IRON, (cx, 18.0, 0.0), R0 * 0.93, 0.4, R=np.diag([1.0, 1.0, 0.7]), group="bars", thin=True),
             Cylinder(CAGE_IRON, (cx, bot - 0.5, 0.0), R0, 0.5, R=np.diag([1.0, 1.0, 0.7]), group="floor")]
    chain = [Capsule(CAGE_IRON, (cx, 36.0, 0.0), (cx, 42.5, 0.0), 0.5, group="chain", thin=True)]
    chain += [Torus(CAGE_IRON, (cx, 36.5 + 2.0 * k, 0.0), 0.9, 0.3, R=rot(90.0, 25.0 * k, 0.0), group="chain", thin=True) for k in range(3)]
    body = [RoundCone(CLOTH_GREY, (cx - 0.5, 8.0, -0.5), (cx + 0.5, 20.0, -0.5), 4.4, 3.6, group="rags", bumps=(0.4, 0.6, 9)),
            Sphere(FLESH_ROT, (cx + 2.0, 24.0, 0.0), 2.9, group="skin"),
            Capsule(FLESH_ROT, (cx + 3.0, 18.0, 1.5), (cx + 4.6, 11.0, 3.0), 0.9, group="skin"),
            Sphere(FLESH_ROT, (cx + 4.7, 10.2, 3.3), 1.2, group="skin"),
            Capsule(GOLD, (cx + 4.7, 10.0, 3.4), (cx + 4.7, 5.6, 3.4), 0.5, group="key", thin=True),
            Torus(GOLD, (cx + 4.7, 11.4, 3.4), 1.1, 0.4, R=rot(90.0, 0.0, 0.0), group="key", thin=True),
            Capsule(GOLD, (cx + 4.7, 6.2, 3.4), (cx + 6.0, 6.2, 3.4), 0.4, group="key", thin=True)]
    prop_sprite = prop(Union(tree, *bars, *rings, *chain, *body), 76, 66, "cage", centre="bbox")
    p.shadow(52, 58, 20, 3)
    p.paste(prop_sprite, 52, 59)
    p.glow(77, 47, 4, 3, AMBER_GLOW, strength=0.35, levels=2, power=1.0)
    p.mist(57, 4, "#5a4a62", strength=0.22)
    p.vignette(0.5)
    return p.rgba()


# --- Merchant's Wreck ----------------------------------------------------------------------------


def scene_merchant_wreck() -> np.ndarray:
    hz = 30
    p = backdrop(91, OLIVE_SKY, hz, MUD[:4], ground_tone=0.42, far_tone=0.42,
                 trees=((8, 22), (24, 12), (112, 26), (97, 10)), moon=(90, 13, 4), ridge_amp=8.0)
    # Ruts of the road the wagon left.
    for k in range(4):
        y = 37 + k * 6
        p.paint((np.abs(YY - (y + np.sin(XX / 11.0 + k) * 1.2)) < 0.7) & (XX < 70 + k * 8), MUD, np.full_like(XX, 0.12), d=0.2)
    p.pebbles(14, 36, 62, "#7b7570", "#403b3c", seed=3)
    p.tufts(14, 36, 62, "#4f5530", seed=4)
    bed_outer = Box(WAGON_WOOD, (0.0, 11.0, 0.0), (19.0, 7.5, 10.0), R=rot(0.0, 0.0, -16.0), round=0.8, group="bed",
                    bumps=(0.4, 0.5, 5))
    bed_inner = Box(WAGON_WOOD, (0.0, 14.2, 0.0), (17.0, 7.0, 8.0), R=rot(0.0, 0.0, -16.0), group="bed")
    bed = Subtract(bed_outer, bed_inner, k=0.3)
    planks = [Box(WAGON_WOOD, (-2.0 + 2.2 * k, 6.0 - 0.6 * k, 10.1), (0.2, 6.0, 0.35), R=rot(0.0, 0.0, -16.0), group="plank") for k in range(1)]
    cx_w, cy_w, z_w = -9.0, 10.5, 11.5
    wheel = [Torus(WAGON_WOOD, (cx_w, cy_w, z_w), 10.0, 1.7, R=rot(90.0, 0.0, 0.0), group="wheel", bumps=(0.2, 0.7, 4)),
             Torus(IRON, (cx_w, cy_w, z_w + 0.4), 10.7, 0.5, R=rot(90.0, 0.0, 0.0), group="tyre", thin=True),
             Cylinder(WAGON_WOOD, (cx_w, cy_w, z_w), 2.2, 1.9, R=rot(90.0, 0.0, 0.0), round=0.5, group="wheel")]
    for k in range(8):
        a = k * math.tau / 8.0 + 0.2
        if k == 3:
            continue
        wheel.append(Capsule(WAGON_WOOD, (cx_w + 2.0 * math.cos(a), cy_w + 2.0 * math.sin(a), z_w),
                             (cx_w + 9.6 * math.cos(a), cy_w + 9.6 * math.sin(a), z_w), 0.55, group="wheel", thin=True))
    crates = [Box(WAGON_WOOD, (-4.0, 18.0, 1.0), (5.0, 4.0, 4.5), R=rot(0.0, 15.0, -10.0), round=0.4, group="crate", bumps=(0.25, 0.8, 3)),
              Box(WAGON_WOOD, (8.0, 17.0, 0.0), (4.0, 3.6, 4.0), R=rot(0.0, -20.0, -14.0), round=0.4, group="crate", bumps=(0.25, 0.8, 4)),
              Box(WAGON_WOOD, (20.0, 3.6, 10.0), (5.0, 3.6, 4.5), R=rot(0.0, 25.0, 8.0), round=0.4, group="crate", bumps=(0.25, 0.8, 5)),
              Box(WAGON_WOOD, (27.0, 2.8, 4.0), (3.4, 2.8, 3.4), R=rot(0.0, -10.0, 20.0), round=0.4, group="crate", bumps=(0.25, 0.8, 6)),
              Box(WAGON_WOOD, (-24.0, 2.4, 6.0), (4.6, 2.4, 4.0), R=rot(8.0, 40.0, 0.0), round=0.4, group="crate", bumps=(0.25, 0.8, 7))]
    sacks = [Ellipsoid(CANVAS, (14.0, 3.6, 12.5), (4.6, 3.8, 3.6), group="sack", bumps=(0.5, 0.6, 8)),
             Ellipsoid(CANVAS, (32.0, 2.4, 9.0), (3.4, 2.4, 3.0), group="sack", bumps=(0.5, 0.6, 9))]
    tarp = Ellipsoid(TARP, (-10.0, 19.5, -1.0), (8.0, 2.0, 7.0), R=rot(0.0, 0.0, -14.0), group="tarp", bumps=(0.6, 0.5, 4))
    goods = [Cylinder(GOLD, (19.0 + 2.5 * k, 0.4 + 0.3 * k, 14.0), 1.5, 0.25, R=rot(75.0, 0.0, 0.0), group="coin") for k in range(3)]
    goods.append(Cylinder(IRON, (-30.0, 4.0, 11.0), 3.3, 4.0, round=0.8, group="barrel"))
    model = Union(bed, *planks, *wheel, *crates, *sacks, tarp, *goods)
    sprite = prop(model, 100, 54, "wreck", centre="bbox", scale=1.25)
    p.shadow(64, 58, 42, 4)
    p.paste(sprite, 64, 59)
    p.eyes(16, 36, AMBER_GLOW, gap=3)
    p.eyes(111, 38, AMBER_GLOW, gap=3)
    p.mist(56, 5, "#5e6a48", strength=0.28)
    p.vignette(0.55)
    return p.rgba()


# --- Rot Blossom ---------------------------------------------------------------------------------


def scene_rot_blossom() -> np.ndarray:
    plum = lch_ramp([(0.2, 0.04, 330.0), (0.27, 0.05, 330.0), (0.34, 0.055, 335.0), (0.41, 0.06, 340.0),
                     (0.48, 0.06, 345.0)])
    p = backdrop(101, plum, 29, DEAD_GRASS[:4], ground_tone=0.3, far_tone=0.4,
                 trees=((7, 22), (22, 12), (112, 24), (100, 12)), moon=(34, 12, 4), ridge_amp=8.0, stars=8)
    p.glow(66, 36, 32, 28, "#b04a90", strength=0.25, levels=4)
    p.tufts(20, 38, 62, "#4a4a30", seed=5)
    tunic, trousers = CLOTH_GREY, CLOTH_BLACK
    body = [RoundCone(tunic, (-23.0, 5.0, 1.0), (-6.0, 5.4, 1.0), 4.4, 5.0, group="tunic", bumps=(0.4, 0.6, 3)),
            Sphere(SKIN_PALE, (-28.0, 5.2, 2.6), 3.5, group="skin", bumps=(0.2, 0.8, 4)),
            Sphere(HOLE, (-29.0, 6.2, 5.6), 1.0, group="eye"), Sphere(HOLE, (-26.2, 6.4, 5.8), 1.0, group="eye"),
            Ellipsoid(HOOD_DARK, (-30.0, 5.0, 0.4), (3.0, 3.6, 3.4), group="hood"),
            RoundCone(trousers, (-6.0, 4.6, 0.0), (4.0, 5.6, 3.0), 3.8, 3.3, group="legs", bumps=(0.4, 0.6, 5)),
            RoundCone(trousers, (4.0, 5.6, 3.0), (12.0, 2.8, 5.0), 3.3, 2.7, group="legs", bumps=(0.4, 0.6, 6)),
            RoundCone(trousers, (-6.0, 3.6, -3.0), (5.0, 3.0, -4.0), 3.6, 3.1, group="legs", bumps=(0.4, 0.6, 7)),
            RoundCone(trousers, (5.0, 3.0, -4.0), (12.0, 2.4, -2.0), 3.1, 2.6, group="legs", bumps=(0.4, 0.6, 8)),
            Ellipsoid(LEATHER_D, (14.5, 2.6, 5.4), (3.8, 2.3, 2.3), R=rot(0.0, 0.0, 12.0), group="boot"),
            Ellipsoid(LEATHER_D, (14.0, 2.2, -1.8), (3.8, 2.3, 2.3), R=rot(0.0, 0.0, 12.0), group="boot"),
            Torus(LEATHER, (-6.5, 5.2, 1.0), 4.8, 0.6, R=rot(0.0, 0.0, 90.0), group="belt", thin=True),
            RoundCone(SKIN_PALE, (-20.0, 6.0, 4.5), (-14.0, 8.4, 5.4), 1.4, 1.2, group="skin"),
            Sphere(SKIN_PALE, (-13.0, 8.6, 5.4), 1.5, group="skin"),
            RoundCone(SKIN_PALE, (-20.0, 3.0, 5.0), (-10.0, 1.0, 8.5), 1.3, 1.2, group="skin"),
            Sphere(SKIN_PALE, (-9.0, 0.8, 8.8), 1.5, group="skin")]
    stem = branch(ROT_STEM, [(-14.0, 8.0, 1.5), (-10.0, 16.0, 0.5), (-1.0, 24.0, -0.5), (5.0, 30.0, -0.5)],
                  [3.0, 2.7, 2.3, 2.0], group="stem", ridged=False)
    tendrils = [Capsule(ROT_STEM, (-14.0, 8.5, 2.0), (x, 4.6, 6.0), 0.8, group="stem", thin=True)
                for x in (-24.0, -18.0, -6.0, 0.0)]
    leaves = [Ellipsoid(ROT_LEAF, (-18.0, 16.0, 0.0), (6.8, 1.6, 2.6), R=rot(0.0, 0.0, 30.0), group="leaf", bumps=(0.3, 0.8, 2)),
              Ellipsoid(ROT_LEAF, (1.0, 16.0, 1.0), (6.8, 1.6, 2.6), R=rot(0.0, 0.0, -26.0), group="leaf", bumps=(0.3, 0.8, 3))]
    hx, hy = 6.0, 34.0
    petals = []
    rng = np.random.default_rng(3)
    for k in range(14):
        a = k * 360.0 / 14.0 + 6.0
        lower = 200 < a < 340
        length = 12.5 + 3.5 * rng.random() - (2.0 if lower else 0.0)
        droop = 0.35 if lower else 0.1
        dirx, diry = math.cos(math.radians(a)), math.sin(math.radians(a)) - droop
        ang = math.degrees(math.atan2(diry, dirx))
        mid = (hx + dirx * length * 0.55, hy + diry * length * 0.5, (-2.0 if k % 2 else 0.8))
        petals.append(Ellipsoid(PETAL_DARK if k % 3 == 0 else (PETAL_LIGHT if k % 3 == 1 else PETAL), mid,
                                (length * 0.55, 2.5 + 0.8 * (k % 2), 1.2), R=rot(0.0, 0.0, ang),
                                group="petal%d" % (k % 3), bumps=(0.35, 0.9, 20 + k)))
    core = Sphere(FRUIT, (hx, hy, 2.4), 3.8, group="fruit")
    stamens = [Capsule(PETAL_PALE, (hx, hy, 3.0), (hx + 5.0 * math.cos(a), hy + 5.0 * math.sin(a), 5.0), 0.3, group="st", thin=True)
               for a in (0.4, 1.5, 2.6, 3.8, 5.0)]
    pods = []
    for dx, sz in ((-7.0, 1.0), (8.0, 0.9)):
        pods.append(Capsule(ROT_STEM, (hx + dx * 0.4, hy - 4.0, 1.0), (hx + dx * 1.3, hy - 11.0, 2.0), 0.6, group="stem", thin=True))
        pods.append(Sphere(FRUIT, (hx + dx * 1.35, hy - 12.6, 2.2), 2.1 * sz, group="fruit"))
    model = Union(*body, *stem, *tendrils, *leaves, *petals, core, *stamens, *pods)
    sprite = prop(model, 76, 62, "blossom", skip=("fruit",), centre="bbox", scale=1.12)
    p.shadow(64, 58, 28, 4)
    p.paste(sprite, 62, 59)
    p.glow(68, 22, 14, 12, "#e090b8", strength=0.4, levels=3)
    p.motes(14, 30, 100, 8, 56, "#e8a0c8", seed=3)
    p.motes(8, 30, 100, 20, 56, "#c8e070", seed=4, halo=False)
    p.mist(57, 4, "#6a4a6a", strength=0.28)
    p.vignette(0.55)
    return p.rgba()


# --- The Sealed Door -----------------------------------------------------------------------------


def scene_sealed_door() -> np.ndarray:
    hz = 24
    p = backdrop(111, ASH_SKY, hz, DEAD_GRASS[:4], ground_tone=0.3, far_tone=0.4,
                 trees=((6, 18), (118, 20), (108, 10)), ridge_amp=7.0)
    dome = np.hypot((XX + 0.5 - 64.0) / 56.0, (YY + 0.5 - 70.0) / 49.0)
    t = 0.62 - 0.35 * (YY - 21.0) / 40.0 + (fbm2(XX / 9.0, YY / 5.0, seed=6, octaves=3) - 0.5) * 0.5
    p.paint(dome < 1.0, DEAD_GRASS, t, d=0.4)
    p.paint((dome < 1.0) & (dome > 0.93), DIRT, 0.4 + (fbm2(XX / 4.0, YY / 4.0, seed=7) - 0.5) * 0.4, d=0.4)
    p.ground([DEAD_GRASS[0], DEAD_GRASS[1], DEAD_GRASS[2]], 56, tone=0.35, seed=9)
    p.tufts(30, 30, 62, "#4a4a30", seed=6)
    p.pebbles(14, 56, 62, "#7b7570", "#403b3c", seed=2)
    p.glow(64, 44, 26, 22, EMBER_GLOW, strength=0.3, levels=4)
    doorw, top = 12.0, 30.0
    slab = Union(Box(DOOR_IRON, (0.0, 15.0, 0.0), (doorw, 15.0, 2.0), round=0.6, group="door", bumps=(0.2, 0.9, 3)),
                 Cylinder(DOOR_IRON, (0.0, top, 0.0), doorw, 2.0, R=rot(90.0, 0.0, 0.0), round=0.6, group="door",
                          bumps=(0.2, 0.9, 4)))
    groove = Box(HOLE, (0.0, 17.0, 2.0), (0.4, 17.0, 0.5), group="groove")
    bands = [Box(DOOR_IRON, (0.0, y, 2.3), (doorw + 0.6, 1.3, 0.7), round=0.3, group="band") for y in (6.0, 18.0, 29.0)]
    rivets = [Sphere(DOOR_IRON, (x, y, 3.0), 0.7, group="rivet") for y in (6.0, 18.0, 29.0) for x in (-9.0, -5.0, 5.0, 9.0)]
    seals = [Ellipsoid(SEAL_RED, (0.0, y, 3.0), (3.0, 3.0, 1.0), group="wax", bumps=(0.3, 0.9, 5 + k)) for k, y in
             enumerate((12.0, 24.0, 33.5))]
    glow_gap = [Box(EMBER, (0.0, 0.9, 2.3), (doorw - 1.5, 0.45, 0.3), group="seam", thin=True),
                Box(EMBER, (-doorw + 0.3, 8.0, 2.2), (0.25, 7.0, 0.3), group="seam", thin=True),
                Box(EMBER, (doorw - 0.3, 5.0, 2.2), (0.25, 4.0, 0.3), group="seam", thin=True)]
    rust = [Ellipsoid(RUST, (x, 14.0 - 4.0 * (k % 2), 2.2), (1.0, 3.4 + (k % 3), 0.4), group="rust") for k, x in
            enumerate((-8.0, -5.5, 6.0, 8.5))]
    frame = [Box(SAND_STONE, (sx * (doorw + 3.4), 17.0, 0.0), (3.4, 17.0, 3.4), round=0.6, group="frame", bumps=(0.4, 0.6, 7 + k))
             for k, sx in enumerate((-1, 1))]
    arch = Subtract(Cylinder(SAND_STONE, (0.0, top, 0.0), doorw + 6.8, 3.4, R=rot(90.0, 0.0, 0.0), round=0.6, group="frame",
                             bumps=(0.4, 0.6, 9)), Cylinder(SAND_STONE, (0.0, top, 0.0), doorw - 0.3, 5.0, R=rot(90.0, 0.0, 0.0)))
    arch = Intersect(arch, Box(SAND_STONE, (0.0, top + 10.0, 0.0), (30.0, 10.0, 6.0)))
    step = Box(SAND_STONE, (0.0, 0.8, 5.0), (doorw + 5.0, 0.8, 3.0), round=0.3, group="frame", bumps=(0.3, 0.6, 11))
    model = Union(slab, groove, *bands, *rivets, *seals, *glow_gap, *frame, arch, step)
    sprite = prop(model, 56, 60, "door", skip=("seam",))
    p.paste(sprite, 64, 57)
    for r, a in ((16, 0.8), (24, 0.5), (33, 0.3)):
        ring = np.abs(np.hypot((XX + 0.5 - 64.0) / r, (YY + 0.5 - 58.0) / (r * 0.18)) - 1.0)
        p.tint(np.where((ring < 0.05) & (YY > 56), a, 0.0), EMBER_GLOW, levels=2, strength=0.5)
    p.motes(8, 50, 78, 20, 54, "#f0a060", seed=2, halo=False)
    p.mist(58, 4, "#6a5048", strength=0.25)
    p.vignette(0.55)
    return p.rgba()


# --- Shrine of Old Kings -------------------------------------------------------------------------


def kneeling_king(side: int, x: float, tone: Material = SAND_STONE) -> list:
    """A robed stone king on his knees toward +x (side 1) or -x (side -1), head bowed, hands on the altar."""
    s = float(side)
    parts = [
        RoundCone(tone, (x - s * 1.0, 1.6, 0.0), (x + s * 1.5, 20.0, 0.0), 7.6, 4.8, group="king", bumps=(0.45, 0.6, 3)),
        Ellipsoid(tone, (x, 1.2, 0.0), (9.0, 1.6, 6.0), group="king", bumps=(0.3, 0.7, 4)),
        Ellipsoid(tone, (x + s * 1.5, 21.0, 0.0), (6.2, 2.8, 3.8), group="king", bumps=(0.3, 0.7, 5)),
        Sphere(tone, (x + s * 5.4, 24.6, 0.0), 3.3, group="king", bumps=(0.2, 0.8, 6)),
        RoundCone(tone, (x + s * 4.0, 21.0, 0.0), (x + s * 13.0, 16.4, 0.0), 2.6, 1.8, group="king", bumps=(0.3, 0.7, 7)),
        Sphere(tone, (x + s * 14.0, 15.9, 0.0), 1.7, group="king"),
        Cylinder(KING_GOLD, (x + s * 5.4, 27.6, 0.0), 3.4, 1.0, R=rot(0.0, 0.0, -s * 16.0), round=0.4, group="crown"),
    ]
    for k in range(5):
        a = (k - 2) * 0.55
        parts.append(Prism(KING_GOLD, (x + s * 5.4 + math.sin(a) * 3.0 - s * 0.6, 28.4, math.cos(a) * 3.0 - 0.1),
                           [(-0.9, 0.0), (0.9, 0.0), (0.0, 2.6)], 0.5, R=rot(0.0, 0.0, -s * 16.0), group="crown"))
    return parts


def scene_shrine_of_kings() -> np.ndarray:
    hz = 27
    hall = lch_ramp([(0.17, 0.02, 300.0), (0.21, 0.025, 300.0), (0.26, 0.028, 300.0), (0.31, 0.03, 300.0),
                     (0.36, 0.03, 70.0)])
    p = new_painter(121)
    p.paint(YY < hz + 3, hall, 1.0 - YY / hz * 0.9, d=0.3)
    for k, x in enumerate((6, 24, 44, 84, 104, 122)):
        w = 6 if k in (0, 5) else 5
        p.paint((np.abs(XX + 0.5 - x) < w / 2.0) & (YY < hz + 4), SILHOUETTE, np.full_like(XX, 0.25 + 0.1 * (k % 2)), d=0.2)
    p.disk(64, 8, 3.2, lch_ramp([(0.4, 0.03, 80.0), (0.5, 0.04, 82.0), (0.6, 0.05, 84.0)]), halo=26)
    t = 0.34 + (fbm2(XX / 6.0, YY / 3.0, seed=12) - 0.5) * 0.25
    yy = np.clip(YY - hz, 0.1, None)
    row = np.floor(np.log1p(yy) * 4.2)
    colw = 5.0 + yy * 1.1
    seam_x = ((XX - 64.0 + (row % 2) * colw / 2.0) % colw) < 0.8
    seam_y = (np.log1p(yy) * 4.2 % 1.0) < 0.14
    p.paint(YY >= hz + 3, hall, t, d=0.3)
    p.paint((YY >= hz + 3) & (seam_x | seam_y), hall[:2], np.full_like(XX, 0.35), d=0.0)
    p.glow(64, 36, 40, 22, AMBER_GLOW, strength=0.4, levels=4)
    altar_body = Box(DARK_STONE, (0.0, 7.0, 0.0), (10.0, 7.0, 6.0), round=0.7, group="altar", bumps=(0.3, 0.6, 3))
    base = Box(DARK_STONE, (0.0, 1.0, 0.0), (12.0, 1.0, 7.5), round=0.4, group="altar", bumps=(0.3, 0.6, 5))
    leaf = Box(KING_GOLD, (0.0, 14.4, 0.0), (10.6, 0.8, 6.6), round=0.4, group="gold")
    loose = [Box(KING_GOLD, (sx * (12.0 + 3.0 * k), 0.4, 6.0 + 2.0 * k), (1.1, 0.25, 0.8), R=rot(0.0, 30.0 * k, 0.0), group="gold") for
             k, sx in ((0, -1), (1, 1), (2, -1))]
    behind = [RoundCone(SAND_STONE, (0.0, 10.0, -8.0), (0.0, 27.0, -8.0), 7.2, 4.8, group="king2", bumps=(0.4, 0.6, 9)),
              Ellipsoid(SAND_STONE, (0.0, 27.5, -8.0), (6.2, 2.8, 3.6), group="king2", bumps=(0.3, 0.7, 12)),
              Sphere(SAND_STONE, (0.0, 31.0, -5.8), 3.3, group="king2", bumps=(0.2, 0.8, 10)),
              Cylinder(KING_GOLD, (0.0, 34.0, -5.9), 3.4, 1.0, R=rot(14.0, 0.0, 0.0), round=0.4, group="crown")]
    for k in range(5):
        a = (k - 2) * 0.55
        behind.append(Prism(KING_GOLD, (math.sin(a) * 3.0, 34.9, -6.0 + math.cos(a) * 3.0), [(-0.9, 0.0), (0.9, 0.0), (0.0, 2.6)], 0.5,
                            group="crown"))
    behind += [RoundCone(SAND_STONE, (sx * 5.0, 26.0, -7.0), (sx * 3.4, 15.8, -2.0), 1.9, 1.5, group="king2", bumps=(0.3, 0.7, 13))
               for sx in (-1, 1)]
    model = Union(altar_body, base, leaf, *loose, *behind, *kneeling_king(1, -26.0), *kneeling_king(-1, 26.0))
    sprite = prop(model, 80, 48, "kings")
    p.shadow(64, 57, 38, 4)
    p.paste(sprite, 64, 58)
    p.motes(22, 38, 90, 14, 56, "#e8c466", seed=2)
    p.mist(58, 4, "#4a4258", strength=0.25)
    p.vignette(0.6)
    return p.rgba()


# --- The Whispering Mask -------------------------------------------------------------------------


def scene_whispering_mask() -> np.ndarray:
    teal = lch_ramp([(0.18, 0.03, 190.0), (0.23, 0.034, 185.0), (0.3, 0.038, 178.0), (0.37, 0.04, 170.0),
                     (0.44, 0.04, 160.0)])
    p = backdrop(131, teal, 28, MOSS_G, ground_tone=0.22, far_tone=0.36,
                 trees=((6, 24), (21, 16), (108, 22), (121, 14), (95, 10)), moon=(100, 12, 4), ridge_amp=7.0, stars=8)
    p.glow(62, 40, 30, 22, "#e0b84a", strength=0.3, levels=4)
    p.tufts(28, 36, 62, "#2f4a24", seed=7)
    mound = Ellipsoid(MOSS, (0.0, 2.4, 0.0), (23.0, 5.0, 11.0), group="moss", bumps=(0.9, 0.5, 3))
    fern = []
    for k, a in enumerate((-70, -48, -30, 34, 55, 76)):
        r = math.radians(a)
        fern.append(Capsule(MOSS, (math.sin(r) * 13.0, 4.0, 4.0), (math.sin(r) * 21.0, 11.0 - 2 * (k % 2), 5.0 + (k % 3)), 0.5,
                            group="fern", thin=True))
    cy = 17.0
    upper = Ellipsoid(MASK_GOLD, (0.0, cy + 2.0, 0.0), (7.4, 9.4, 3.6), group="mask", bumps=(0.08, 0.8, 2))
    lower = Ellipsoid(MASK_GOLD, (0.0, cy - 6.4, 0.3), (4.4, 8.6, 3.0), group="mask", bumps=(0.08, 0.8, 3))
    chin = Ellipsoid(MASK_GOLD, (0.0, cy - 13.0, 1.0), (1.8, 3.2, 1.6), group="mask")
    shell = SmoothUnion(upper, lower, chin, k=2.4)
    brow_ridge = Capsule(MASK_GOLD, (-6.6, cy + 5.4, 2.6), (6.6, cy + 5.4, 2.6), 1.0, group="mask")
    lids = [Capsule(MASK_GOLD, (sx * 0.9, cy + 4.0, 3.5), (sx * 5.8, cy + 2.6, 3.0), 0.5, group="mask", thin=True) for sx in (-1, 1)]
    nose = RoundCone(MASK_GOLD, (0.0, cy + 4.6, 3.2), (0.0, cy - 3.4, 3.9), 0.7, 1.4, group="mask")
    eyes = [Ellipsoid(HOLE, (sx * 3.1, cy + 2.4, 3.3), (2.4, 0.75, 1.0), R=rot(0.0, 0.0, -sx * 20.0), group="eye") for sx in (-1, 1)]
    mouth = Ellipsoid(HOLE, (0.0, cy - 6.8, 3.0), (2.1, 0.55, 0.8), group="eye")
    marks = [Capsule(MASK_GOLD_DARK, (sx * 2.5, cy - 0.2, 3.7), (sx * 3.6, cy - 6.0, 3.2), 0.3, group="mask", thin=True) for sx in (-1, 1)]
    crest = []
    for k in range(7):
        a = (k - 3) * 0.34
        length = 8.0 - abs(k - 3) * 1.1
        crest.append(Prism(MASK_GOLD, (math.sin(a) * 6.4, cy + 9.4 + math.cos(a) * 1.6, 0.0),
                           [(-1.2, 0.0), (1.2, 0.0), (0.0, length)], 0.9, R=rot(0.0, 0.0, -math.degrees(a)), group="crest"))
    mask = Moved(Union(shell, brow_ridge, *lids, nose, *eyes, mouth, *marks, *crest), R=rot(-26.0, 0.0, 3.0))
    creep = [Ellipsoid(MOSS, (-6.4, 6.0, 6.2), (4.0, 1.7, 2.6), R=rot(0.0, 0.0, 30.0), group="moss", bumps=(0.5, 0.8, 5)),
             Ellipsoid(MOSS, (7.0, 8.2, 4.6), (3.2, 1.3, 2.0), R=rot(0.0, 0.0, -35.0), group="moss", bumps=(0.5, 0.8, 6)),
             Capsule(ROT_STEM, (-9.0, 10.0, 5.2), (-3.0, 6.4, 8.0), 0.45, group="vine", thin=True),
             Capsule(ROT_STEM, (-3.0, 6.4, 8.0), (5.0, 8.5, 6.0), 0.4, group="vine", thin=True)]
    roots_ = [Capsule(BARK, (sx * 12.0, 3.0, -2.0), (sx * 24.0, 0.0, 6.0), 1.4, group="root", bumps=(0.3, 0.7, 4)) for sx in (-1, 1)]
    model = Union(mound, *fern, mask, *creep, *roots_)
    sprite = prop(model, 80, 56, "mask", centre="bbox", scale=1.3)
    p.shadow(64, 57, 24, 4)
    p.paste(sprite, 64, 58)
    for k, x in enumerate((54, 62, 71, 78)):
        p.wisp(x, 41 - (k % 2) * 3, 15 + 3 * (k % 3), "#f0d27a", seed=k * 3, drift=0.6, alpha=0.75)
    p.motes(14, 36, 92, 12, 56, "#f0d27a", seed=5)
    p.mist(58, 4, "#3f5a54", strength=0.3)
    p.vignette(0.55)
    return p.rgba()


# --- The Widow's Wager ---------------------------------------------------------------------------


def chair(x: float, side: int, mat_: Material = WOOD_ROT) -> list:
    """A plain wooden chair seen from the side, its back at x and its seat reaching toward `side`."""
    s = float(side)
    return [Box(mat_, (x + s * 4.0, 11.0, 0.0), (5.0, 0.8, 5.0), round=0.3, group="chair", bumps=(0.25, 0.7, 3)),
            Box(mat_, (x - s * 0.8, 21.0, 0.0), (0.9, 10.0, 5.0), round=0.3, group="chair", bumps=(0.25, 0.7, 4)),
            Capsule(mat_, (x - s * 0.8, 11.0, 4.2), (x - s * 0.8, 0.0, 4.4), 0.8, group="chair"),
            Capsule(mat_, (x - s * 0.8, 11.0, -4.2), (x - s * 0.8, 0.0, -4.4), 0.8, group="chair"),
            Capsule(mat_, (x + s * 7.8, 11.0, 4.2), (x + s * 8.0, 0.0, 4.4), 0.8, group="chair"),
            Capsule(mat_, (x + s * 7.8, 11.0, -4.2), (x + s * 8.0, 0.0, -4.4), 0.8, group="chair")]


def scene_widows_wager() -> np.ndarray:
    p = backdrop(141, DUSK, 30, DEAD_GRASS[:4], ground_tone=0.28, far_tone=0.42,
                 trees=((7, 22), (20, 12), (112, 24), (100, 11), (88, 8)), moon=(92, 13, 4), ridge_amp=8.0)
    p.glow(64, 52, 26, 10, EMBER_GLOW, strength=0.16, levels=3)
    p.tufts(20, 38, 62, "#4a4a30", seed=3)
    p.pebbles(14, 40, 62, "#7b7570", "#403b3c", seed=2)
    # The widow, in profile on her chair, head bowed over the chips in her hands.
    x = -25.0
    widow = chair(x, 1) + [
        RoundCone(CLOTH_BLACK, (x + 2.0, 13.0, 0.0), (x + 3.0, 26.0, 0.0), 5.2, 4.0, group="dress", bumps=(0.3, 0.6, 5)),
        Ellipsoid(CLOTH_BLACK, (x + 5.5, 10.0, 0.0), (8.5, 4.5, 5.2), group="dress", bumps=(0.4, 0.5, 6)),
        Capsule(CLOTH_BLACK, (x + 9.0, 11.0, 0.0), (x + 11.0, 1.5, 0.0), 3.0, group="dress", bumps=(0.3, 0.6, 7)),
        Ellipsoid(CLOTH_BLACK, (x + 11.0, 1.6, 0.0), (4.0, 1.6, 3.0), group="dress"),
        Ellipsoid(CLOTH_BLACK, (x + 3.5, 28.5, 0.0), (4.4, 4.4, 4.0), group="veil", bumps=(0.2, 0.7, 8)),
        Sphere(SKIN_PALE, (x + 6.0, 27.8, 1.2), 1.9, group="face"),
        Ellipsoid(CLOTH_BLACK, (x + 3.0, 24.4, 0.0), (5.0, 2.4, 3.6), group="dress"),
        RoundCone(CLOTH_BLACK, (x + 4.0, 24.0, 2.0), (x + 9.5, 17.0, 3.6), 2.3, 1.7, group="sleeve"),
        Sphere(SKIN_PALE, (x + 11.0, 16.0, 3.8), 1.3, group="hand"),
        Box(CREAM, (x + 12.2, 15.2, 3.8), (1.0, 0.35, 0.8), R=rot(0.0, 20.0, 15.0), group="chip")]
    stool = [Cylinder(WOOD_ROT, (-9.0, 8.5, 7.0), 4.4, 0.6, round=0.3, group="stool", bumps=(0.25, 0.7, 3))]
    stool += [Capsule(WOOD_ROT, (-9.0 + dx, 8.0, 7.0 + dz), (-9.0 + dx * 1.4, 0.0, 7.0 + dz * 1.4), 0.6, group="stool")
              for dx, dz in ((-2.6, 1.6), (2.6, 1.6), (0.0, -3.0))]
    chips = [Box(CREAM, (-11.0 + 2.6 * k, 9.4, 6.0 + (k % 2) * 2.6), (1.1, 0.3, 0.8), R=rot(0.0, 25.0 * k, 0.0), group="chip") for k in range(4)]
    hat = [Cylinder(CLOTH_BROWN, (30.0, 12.2, 0.0), 4.4, 0.35, R=rot(0.0, 0.0, 10.0), round=0.2, group="hat"),
           Cylinder(CLOTH_BROWN, (30.2, 14.0, 0.0), 2.4, 1.6, round=0.6, group="hat")]
    other = chair(26.0, -1) + hat
    pit = []
    for k in range(10):
        a = k * math.tau / 10.0
        pit.append(Ellipsoid(STONE, (3.0 + math.cos(a) * 9.5, 2.0, 2.0 + math.sin(a) * 4.0), (3.0, 2.4, 2.6), group="stone", bumps=(0.3, 0.6, 30 + k)))
    logs = [Capsule(CHARRED, (-4.0, 3.0, 1.0), (10.0, 5.0, 3.0), 2.0, group="log", bumps=(0.3, 0.8, 4)),
            Capsule(CHARRED, (-2.0, 4.0, 4.0), (9.0, 3.4, -1.0), 1.8, group="log", bumps=(0.3, 0.8, 5)),
            Capsule(CHARRED, (0.0, 3.0, -1.0), (7.0, 6.4, 1.0), 1.6, group="log", bumps=(0.3, 0.8, 6)),
            Ellipsoid(ASHEN, (3.0, 2.0, 2.0), (9.0, 1.2, 4.0), group="ash")]
    ember = Sphere(EMBER, (4.5, 4.4, 4.6), 0.7, group="ember")
    model = Union(*widow, *stool, *chips, *other, *pit, *logs, ember)
    sprite = prop(model, 96, 56, "widow", skip=("ember",), centre="bbox", scale=1.18)
    p.shadow(64, 57, 42, 4)
    p.paste(sprite, 64, 59)
    p.glow(66, 49, 6, 4, EMBER_GLOW, strength=0.4, levels=2, power=1.0)
    p.mist(59, 4, "#5a4a62", strength=0.25)
    p.vignette(0.55)
    return p.rgba()


# --- A Wounded Pilgrim ---------------------------------------------------------------------------


def road_scene(p: Painter, hz: int, cx0: float = 64.0, narrow: float = 2.0, widen: float = 0.8) -> None:
    cx = cx0 + 2.5 * np.sin(YY / 6.0)
    half = narrow + (YY - hz) * widen
    road = (np.abs(XX + 0.5 - cx) < half) & (YY > hz)
    rut = np.abs(np.abs(XX + 0.5 - cx) - half * 0.5) < 0.8
    t = 0.55 + (fbm2(XX / 5.0, YY / 2.0, seed=p.seed + 31) - 0.5) * 0.45 - rut * 0.15
    p.paint(road, ROAD, t, d=0.4)


def scene_wounded_pilgrim() -> np.ndarray:
    hz = 30
    p = backdrop(151, DUSK, hz, DEAD_GRASS[:4], ground_tone=0.28, far_tone=0.42,
                 trees=((7, 24), (21, 13), (112, 22), (101, 12)), moon=(96, 12, 4), ridge_amp=8.0)
    road_scene(p, hz, cx0=62.0, narrow=3.0, widen=0.95)
    p.pebbles(12, 40, 62, "#7b7570", "#403b3c", seed=2)
    pool = np.hypot((XX + 0.5 - 60.0) / 13.0, (YY + 0.5 - 55.0) / 3.4)
    p.paint(pool < 1.0, BLOOD_RAMP, 0.35 + 0.45 * (1.0 - pool), d=0.3)
    for k in range(8):
        p.pixels([(33 - 2 * k + (k % 2), 54 + (k % 3) - 1)], BLOOD_RAMP[1])
    parts = [RoundCone(PILGRIM_ROBE, (-9.0, 4.6, 1.0), (4.0, 4.4, 0.0), 4.8, 4.6, group="robe", bumps=(0.4, 0.6, 3)),
             RoundCone(PILGRIM_ROBE, (4.0, 4.4, 0.0), (14.0, 3.4, -1.0), 4.6, 3.6, group="robe", bumps=(0.4, 0.6, 4)),
             Ellipsoid(PILGRIM_ROBE, (-8.0, 5.4, 0.8), (5.8, 4.8, 4.6), group="robe", bumps=(0.4, 0.6, 5)),
             Ellipsoid(HOOD_DARK, (-18.0, 5.0, 0.0), (4.6, 4.2, 4.0), group="hood", bumps=(0.3, 0.6, 6)),
             Sphere(SKIN_PALE, (-16.4, 4.6, 3.0), 3.3, group="face", bumps=(0.12, 0.8, 7)),
             Ellipsoid(HOOD_DARK, (-16.4, 7.4, 2.6), (3.6, 1.3, 3.0), group="hood"),
             Ellipsoid(BLOOD_DARK, (-1.0, 7.6, 4.6), (4.0, 2.6, 0.8), R=rot(0.0, 0.0, 20.0), group="blood"),
             Ellipsoid(BLOOD_DARK, (3.4, 6.4, 4.2), (2.4, 1.8, 0.7), group="blood"),
             Torus(SASH, (2.0, 5.0, 0.0), 4.7, 0.5, R=rot(0.0, 0.0, 90.0), group="sash", thin=True),
             Box(LEATHER, (-4.8, 9.0, 6.0), (4.2, 3.2, 2.6), R=rot(0.0, 0.0, 8.0), round=0.8, group="satchel"),
             Capsule(LEATHER, (-9.0, 10.6, 3.4), (-1.0, 4.8, 5.8), 0.55, group="strap", thin=True),
             RoundCone(PILGRIM_ROBE, (-11.0, 6.6, 3.0), (-6.4, 7.8, 6.6), 1.9, 1.6, group="sleeve"),
             Sphere(SKIN_PALE, (-5.4, 8.2, 7.4), 1.4, group="hand"),
             RoundCone(PILGRIM_ROBE, (-11.0, 3.6, 2.8), (-19.0, 1.4, 8.0), 1.9, 1.5, group="sleeve"),
             Sphere(SKIN_PALE, (-20.4, 1.2, 8.6), 1.4, group="hand"),
             RoundCone(PILGRIM_ROBE, (4.0, 4.4, 2.0), (9.0, 10.0, 3.6), 3.0, 2.6, group="leg"),
             RoundCone(PILGRIM_ROBE, (9.0, 10.0, 3.6), (14.0, 3.6, 5.6), 2.6, 2.1, group="leg"),
             Ellipsoid(LEATHER_D, (16.4, 2.4, 6.0), (3.6, 2.4, 2.4), R=rot(0.0, 0.0, 6.0), group="boot"),
             Ellipsoid(LEATHER_D, (16.8, 3.2, -1.6), (3.6, 2.5, 2.5), R=rot(0.0, 0.0, 14.0), group="boot"),
             Capsule(WOOD, (-2.0, 1.0, 12.0), (24.0, 1.6, 10.0), 0.8, group="staff"),
             Capsule(WOOD, (24.0, 1.6, 10.0), (28.0, 3.6, 9.4), 0.6, group="staff", thin=True),
             Cylinder(LEATHER_D, (26.0, 0.9, 3.0), 6.4, 0.4, R=rot(8.0, 0.0, 6.0), round=0.2, group="hat"),
             Cylinder(LEATHER_D, (26.2, 3.0, 3.0), 3.2, 2.0, R=rot(8.0, 0.0, 6.0), round=0.8, group="hat")]

    def closed_eyes(frame, cam):
        for dx in (-1.4, 1.2):
            stamp(frame, cam, _world((-16.8 + dx, 5.2, 6.0)), ["xx"], {"x": (HOLE, 0)}, origin=(0, 0))

    sprite = prop(Union(*parts), 84, 34, "pilgrim", post=closed_eyes, centre="bbox", scale=1.2)
    p.shadow(64, 57, 34, 3.6)
    p.paste(sprite, 64, 59)
    p.mist(60, 3, "#5a4a62", strength=0.18)
    p.vignette(0.55)
    return p.rgba()


# --- The Bone Collector --------------------------------------------------------------------------


def scene_bone_collector() -> np.ndarray:
    p = backdrop(161, OLIVE_SKY, 30, MUD[:4], ground_tone=0.38, far_tone=0.4,
                 trees=((6, 24), (20, 13), (112, 24), (122, 14)), moon=(104, 12, 4), ridge_amp=8.0)
    p.glow(60, 42, 26, 20, AMBER_GLOW, strength=0.32, levels=4)
    p.pebbles(12, 42, 62, "#8a8068", "#403b3c", seed=2)
    pts = [(0.0, -1.5, 0.0), (1.0, 10.0, 0.0), (-1.0, 20.0, 0.0), (1.0, 30.0, 0.0), (0.0, 37.0, 0.0)]
    rr = [14.0, 12.0, 11.0, 10.0, 9.0]
    trunk = branch(HOLLOW_BARK, pts, rr, group="tree", amp=0.6, ridges=5, twist=0.15)
    trunk += roots(HOLLOW_BARK, [(-19.0, 4.0, 3.0, 1.8), (18.0, 5.0, 2.8, 1.6), (-9.0, 11.0, 2.4, 1.4), (10.0, 12.0, 2.4, 1.4)], "tree", 5.0, 5.0)
    for pts_, rad in (([(-4.0, 33.0, 0.0), (-11.0, 39.0, 0.0), (-16.0, 47.0, 0.0), (-15.0, 54.0, 0.0)], [6.0, 4.0, 2.6, 1.2]),
                      ([(4.0, 34.0, 0.0), (11.0, 41.0, 0.0), (16.0, 46.0, 0.0), (23.0, 49.0, 0.0)], [6.0, 4.0, 2.6, 1.2]),
                      ([(0.0, 36.0, 0.0), (2.0, 45.0, 0.0), (-1.0, 53.0, 0.0)], [5.0, 3.0, 1.2]),
                      ([(-11.0, 39.0, 0.0), (-19.0, 41.0, 0.0), (-24.0, 38.0, 0.0)], [2.6, 1.6, 0.9]),
                      ([(11.0, 41.0, 0.0), (19.0, 36.0, 0.0), (22.0, 31.0, 0.0)], [2.6, 1.6, 0.9])):
        trunk += branch(HOLLOW_BARK, pts_, rad, group="tree", ridged=False)
    hollow = Union(Ellipsoid(HOLE, (1.0, 14.0, 8.5), (8.5, 11.0, 4.5), group="hollow"),
                   Box(HOLE, (1.0, 6.0, 8.5), (6.0, 6.5, 3.6), group="hollow"))
    lantern = [Capsule(CAGE_IRON, (-13.0, 33.0, 9.0), (-13.0, 26.0, 9.0), 0.35, group="chain", thin=True),
               Box(CAGE_IRON, (-13.0, 24.8, 9.0), (1.8, 0.4, 1.8), group="lamp"),
               Box(AMBER, (-13.0, 22.4, 9.0), (1.3, 1.9, 1.3), group="flame")]
    tree = prop(Union(*trunk, hollow, *lantern), 74, 62, "hollow_tree", skip=("flame",), centre="bbox")
    coat = LEATHER_D
    man = [Cylinder(HOLLOW_BARK, (0.0, 2.2, 0.0), 6.0, 2.2, round=0.8, group="stump", bumps=(0.3, 0.7, 5)),
           RoundCone(coat, (0.0, 5.0, 0.0), (0.0, 17.0, 0.0), 6.0, 4.6, group="coat", bumps=(0.3, 0.6, 3)),
           Ellipsoid(coat, (0.0, 17.5, 0.0), (5.6, 2.6, 3.8), group="coat"),
           Ellipsoid(CLOTH_BROWN, (0.0, 21.2, 0.0), (4.6, 4.8, 4.2), group="hood", bumps=(0.2, 0.7, 4)),
           Ellipsoid(HOLE, (0.4, 20.6, 2.6), (2.6, 2.8, 1.9), group="face"),
           Sphere(AMBER, (-0.6, 21.2, 4.3), 0.4, group="eye"), Sphere(AMBER, (1.7, 21.2, 4.3), 0.4, group="eye"),
           Capsule(coat, (-4.0, 13.0, 1.0), (-5.0, 8.0, 7.0), 1.8, group="coat"),
           Capsule(coat, (-5.0, 8.0, 7.0), (-1.0, 5.6, 9.0), 1.6, group="coat"),
           Capsule(coat, (4.0, 13.0, 1.0), (5.0, 8.4, 7.0), 1.8, group="coat"),
           Capsule(coat, (5.0, 8.4, 7.0), (2.5, 6.0, 9.6), 1.6, group="coat"),
           Sphere(SKIN, (-0.6, 5.2, 9.6), 1.2, group="hand"), Sphere(SKIN, (2.8, 5.6, 10.0), 1.2, group="hand"),
           Capsule(CREAM, (-0.6, 5.2, 9.6), (3.0, 5.6, 10.0), 0.3, group="string", thin=True)]
    # The coat of knucklebones: a mantle of them over the shoulders and a bandolier across the chest.
    for k in range(9):
        a = (k - 4) * 0.36
        man.append(Sphere(BONE, (math.sin(a) * 5.4, 17.6 + 0.5 * math.cos(a), math.cos(a) * 3.4), 1.0, group="knuckle"))
    for k in range(6):
        t = k / 5.0
        cx, cy = -4.2 + 8.6 * t, 17.0 - 9.0 * t
        man.append(Capsule(BONE, (cx - 0.9, cy + 0.4, 4.4 + 0.6 * t), (cx + 0.9, cy - 0.4, 4.6 + 0.6 * t), 0.7, group="knuckle"))
    sprite = prop(Union(*man), 32, 40, "collector", skip=("eye",), centre="bbox", scale=1.35)
    p.shadow(62, 57, 24, 4)
    p.paste(tree, 62, 58)
    p.glow(63, 52, 10, 8, AMBER_GLOW, strength=0.3, levels=3, power=1.0)
    p.paste(sprite, 63, 58)
    # Strings of knucklebones hanging off the limbs: a thread with a bone every few pixels, now and then a long one.
    for x, y, n in ((43, 8, 5), (88, 14, 4), (59, 7, 6)):
        for k in range(n * 3 + 2):
            p.pixels([(x + (1 if (k // 7) % 2 else 0), y + 3 + k)], rgb(CREAM.colors[1]))
        for k in range(n):
            yy = y + 5 + k * 3
            sx = x + (1 if (k // 2) % 2 else 0)
            if k % 3 == 2:
                p.pixels([(sx, yy), (sx, yy + 1), (sx, yy + 2)], rgb(BONE.colors[3]))
            else:
                p.pixels([(sx - 1, yy), (sx, yy), (sx + 1, yy + 1)], rgb(BONE.colors[3]))
    p.mist(58, 4, "#5e6a48", strength=0.25)
    p.vignette(0.55)
    return p.rgba()


# --- Ambushes ------------------------------------------------------------------------------------


def lurker(p: Painter, x: float, y: float, s: float, eye: str, face: int = 1, crouch: float = 1.0) -> None:
    """A hunched dark shape in the undergrowth, only its eyes lit: a body, a low head with ears."""
    body = np.hypot((XX + 0.5 - x) / (6.5 * s), (YY + 0.5 - y) / (3.6 * s * crouch)) < 1.0
    head = np.hypot((XX + 0.5 - (x + face * 5.8 * s)) / (3.0 * s), (YY + 0.5 - (y - 1.4 * s)) / (2.5 * s)) < 1.0
    ear = np.zeros_like(body)
    for dx in (4.4, 6.8):
        ex = x + face * dx * s
        for k in range(int(3 * s) + 1):
            ear |= (np.abs(XX + 0.5 - (ex + face * k * 0.2)) < max(0.5, 1.4 * s - k * 0.5)) & (YY == int(y - 3.6 * s - k))
    mask = body | head | ear
    p.img[mask] = rgb(SILHOUETTE[0]) * 0.8
    rim = mask & ~np.roll(mask, 1, axis=0)
    p.img[rim] = rgb(SILHOUETTE[2])
    p.palette.extend([SILHOUETTE[0], SILHOUETTE[2]])
    p.eyes(int(x + face * 5.2 * s), int(y - 1.8 * s), eye, gap=2)


def scene_ambush_rotten_road() -> np.ndarray:
    hz = 31
    p = new_painter(171)
    p.sky(DUSK, hz)
    p.ridge(SILHOUETTE, hz - 1, 12.0, 34.0, 175, 0.5, fade=0.3, y_to=hz + 4)
    p.ground(DEAD_GRASS[:3], hz + 2, tone=0.22, seed=3)
    road_scene(p, hz, cx0=64.0, narrow=3.0, widen=0.8)
    # The tree line closes in on both sides.
    for x, base, h, w in ((8, 62, 56, 7), (26, 50, 40, 4), (112, 62, 58, 7), (96, 50, 40, 4), (44, 40, 26, 2), (84, 40, 26, 2)):
        p.big_tree(x, base, h, w, rgb(SILHOUETTE[0] if w > 4 else SILHOUETTE[1]), x, lean=0.03 * (1 if x < 64 else -1), limbs=4)
    p.mist(hz + 6, 6, "#6a5a7a", strength=0.5)
    for x, y, s, f, e in ((14, 46, 1.3, 1, AMBER_GLOW), (36, 41, 0.9, 1, ROT_GLOW), (100, 44, 1.2, -1, AMBER_GLOW),
                          (82, 39, 0.8, -1, ROT_GLOW), (122, 52, 1.5, -1, AMBER_GLOW)):
        lurker(p, x, y, s, e, f)
    for x, y, e in ((6, 22, AMBER_GLOW), (28, 28, ROT_GLOW), (50, 30, AMBER_GLOW), (112, 24, ROT_GLOW), (90, 31, AMBER_GLOW),
                    (118, 36, ROT_GLOW), (4, 38, ROT_GLOW)):
        p.eyes(x, y, e, gap=3 if x % 2 else 2)
    pouch = [Ellipsoid(LEATHER, (0.0, 2.8, 0.0), (4.2, 3.2, 3.4), group="pouch", bumps=(0.3, 0.6, 3)),
             Torus(LEATHER, (0.0, 5.4, 0.0), 1.8, 0.7, group="pouch"),
             Capsule(LEATHER, (-1.5, 6.0, 0.0), (-4.5, 5.5, 1.0), 0.4, group="tie", thin=True)]
    pouch += [Cylinder(GOLD, (4.0 + 2.2 * k, 0.4 + 0.2 * k, 3.0 + (k % 2) * 2.0), 1.4, 0.25, R=rot(80.0, 0.0, 12.0 * k), group="coin") for k in range(5)]
    sprite = prop(Union(*pouch), 28, 14, "pouch", centre="bbox")
    p.glow(66, 56, 14, 5, AMBER_GLOW, strength=0.5, levels=3)
    p.paste(sprite, 66, 58)
    p.mist(60, 3, "#5a4a62", strength=0.2)
    p.vignette(0.65)
    return p.rgba()


def scene_ambush_ashen_deep() -> np.ndarray:
    hz = 28
    p = new_painter(181)
    p.sky(ASH_SKY, hz, clouds=0.12)
    p.glow(64, hz, 70, 12, EMBER_GLOW, strength=0.55, levels=4)
    p.ridge(ASH_DARK, hz - 1, 10.0, 28.0, 185, 0.45, fade=0.25, y_to=hz + 6)
    p.ground(ASH_GROUND, hz + 3, tone=0.4, seed=5, spread=0.2)
    for k, (base, amp, seed, tone) in enumerate(((38, 5.0, 11, 0.36), (49, 6.0, 13, 0.46))):
        crest = p.ridge(ASH_GROUND, base, amp, 20.0, seed, tone, fade=0.35)
        for x in range(SW):
            cy = int(crest[x])
            if cy > hz + 3:
                p.img[cy, x] = rgb(ASH_GROUND[min(4, int(tone * 4) + 1)])
    p.mist(hz + 4, 5, "#7a5a4a", strength=0.35)
    HAND = ["..x.x..", "x.x.x.x", "x.xxx.x", "xxxxxxx", ".xxxxx.", "..xxx..", "..xxx.."]
    for x, y, lean in ((22, 51, -0.3), (38, 46, 0.25), (92, 47, -0.2), (108, 53, 0.35), (76, 42, 0.1)):
        h = 6 + (x % 4)
        tx = x + lean * h
        for k in range(h):
            xx = round(x + (tx - x) * k / h)
            p.pixels([(xx, y - k), (xx + 1, y - k)], BONE.colors[2])
            p.pixels([(xx + 2, y - k)], BONE.colors[0])
        for r, row in enumerate(HAND):
            for c, ch in enumerate(row):
                if ch == "x":
                    p.pixels([(round(tx) - 2 + c, y - h - len(HAND) + 2 + r + 1)], BONE.colors[3 if c < 4 else 1])
    for x, y, s, f in ((14, 56, 1.5, 1), (50, 38, 0.85, 1), (100, 58, 1.6, -1), (122, 44, 1.0, -1), (40, 60, 1.0, 1)):
        lurker(p, x, y, s, EMBER_GLOW, f, crouch=0.9)
    for x, y in ((60, 36), (68, 36), (86, 40), (30, 40), (4, 48)):
        p.eyes(x, y, EMBER_GLOW, gap=2)
    coffer = [Box(KING_GOLD, (0.0, 4.0, 0.0), (6.5, 4.0, 4.5), round=0.8, group="coffer", bumps=(0.2, 0.9, 3)),
              Box(DOOR_IRON, (0.0, 4.0, 4.6), (6.7, 0.6, 0.4), group="band"), Box(DOOR_IRON, (0.0, 7.0, 4.6), (6.7, 0.6, 0.4), group="band"),
              Box(KING_GOLD, (0.5, 9.4, -2.0), (6.5, 0.9, 4.2), R=rot(-32.0, 0.0, 0.0), round=0.4, group="coffer"),
              Ellipsoid(KING_GOLD, (0.0, 8.0, 1.0), (5.0, 1.8, 3.0), group="coin", bumps=(0.4, 0.9, 4))]
    coffer += [Cylinder(KING_GOLD, (7.5 + 2.0 * k, 0.4, 3.0), 1.3, 0.25, R=rot(80.0, 0.0, 10.0 * k), group="coin") for k in range(3)]
    sprite = prop(Union(*coffer), 34, 18, "coffer", centre="bbox")
    p.glow(64, 55, 16, 6, AMBER_GLOW, strength=0.55, levels=3)
    p.shadow(64, 58, 10, 2.2)
    p.paste(sprite, 64, 58)
    p.motes(16, 4, 124, 8, 56, "#c88a58", seed=3, halo=False)
    p.vignette(0.65)
    return p.rgba()


SCENES = {
    "black_mirror": scene_black_mirror,
    "bone_collector": scene_bone_collector,
    "buried_cairn": scene_buried_cairn,
    "drowned_chapel": scene_drowned_chapel,
    "gamblers_bones": scene_gamblers_bones,
    "hanging_cage": scene_hanging_cage,
    "hungry_scarecrow": scene_hungry_scarecrow,
    "merchant_wreck": scene_merchant_wreck,
    "rot_blossom": scene_rot_blossom,
    "sealed_door": scene_sealed_door,
    "shrine_of_kings": scene_shrine_of_kings,
    "tithe_collector": scene_tithe_collector,
    "weeping_well": scene_weeping_well,
    "whispering_mask": scene_whispering_mask,
    "widows_wager": scene_widows_wager,
    "wounded_pilgrim": scene_wounded_pilgrim,
    "ambush_rotten_road": scene_ambush_rotten_road,
    "ambush_ashen_deep": scene_ambush_ashen_deep,
}

MAX_COLOURS = 96


def check_scene(name: str, rgba: np.ndarray) -> list[str]:
    """The picture contract: 128x64, fully opaque, a few dozen colours at most."""
    problems = []
    if rgba.shape[:2] != (SH, SW):
        problems.append("is %dx%d, should be %dx%d" % (rgba.shape[1], rgba.shape[0], SW, SH))
    if (rgba[..., 3] != 255).any():
        problems.append("has clear or half-clear pixels")
    n = len({tuple(int(v) for v in px) for px in rgba.reshape(-1, 4)})
    if n > MAX_COLOURS:
        problems.append("uses %d colours (at most %d)" % (n, MAX_COLOURS))
    for q in problems:
        print("  check %s: %s" % (name, q))
    return problems


def build(ctx) -> None:
    from kit.sheet import grid
    tiles = []
    for name, fn in SCENES.items():
        rgba = fn()
        check_scene(name, rgba)
        ctx.save("sprites/events/%s.png" % name, rgba, scale=6)
        tiles.append(rgba)
    ctx.extra("events_contact.png", grid(tiles, 3), scale=3)
