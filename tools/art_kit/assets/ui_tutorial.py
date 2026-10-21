"""Pictures for the tutorial's lesson cards (card #293, phase 22: a picture and a short line instead
of two sentences).

Most lessons use the game's own icons (a hit kind, the AP gem, a mark, the team gauge, the Relic
gem; data/tutorial/tutorial.tres icon_path). These four had nothing that fits, so they are drawn
here like the map's stop pictures (24x24, lit from the upper left, a dark ink outline); the card
shows them with nearest filtering at a whole multiple.

- ui/tutorial_ring.png: a timed press (the Attack lesson): the pale ring that shrinks onto a hero,
  the gold PERFECT band it closes on and the target in the middle, as the fight draws them.
- ui/tutorial_follow_up.png: the follow-ups (the Follow-ups lesson): two of the blue rings that
  appear on the other heroes, overlapping, each closing on a bright target.
- ui/tutorial_cleanse.png: lifting a mark (the Lift a mark lesson): the green Rot drop with a white
  sparkle washing over it.
- ui/tutorial_echo.png: an Echo (the Echoes lesson): the violet echo of the menus' Echo glyph, a
  dot in a ring with a sound wave either side.
"""
from __future__ import annotations

import math

import numpy as np

from kit.canvas import Canvas
from kit.color import ramp, rgb_to_hex
from kit.palette import M

ICON = 24

INK_OUT = ramp("#4b3527", below=1, above=2, step_l=0.08)[0]  # the map's sepia ink, darkest
GOLD = M["gold"].colors
# The fight's colours (HudStyle): the press ring's pale white, the follow-up ring's blue (JUMP),
# the Rot mark's green (STATUS_COLORS.rotting) and the Echo's violet (the Glossary's Echo term).
PALE = ramp(rgb_to_hex((0.9, 0.95, 1.0)), below=2, above=0, step_l=0.1)
BLUE = ramp(rgb_to_hex((0.55, 0.88, 1.0)), below=2, above=1, step_l=0.1)
ROT = ramp(rgb_to_hex((0.68, 0.86, 0.22)), below=2, above=1, step_l=0.1)
VIOLET = ramp(rgb_to_hex((0.62, 0.32, 0.72)), below=1, above=2, step_l=0.1)
WHITE = "#fbf6e8"


def _lit(dx: float, dy: float, r: float, shades: list[str]) -> str:
    """The shade of a ring pixel lit from the upper left: brightest where it faces the light."""
    facing = -(dx + dy) / (max(r, 1e-6) * math.sqrt(2.0))
    if facing > 0.35:
        return shades[-1]
    if facing > -0.4:
        return shades[-2]
    return shades[-3]


def _ring(c: Canvas, cx: float, cy: float, inner: float, outer: float, shades: list[str],
          arcs: list[tuple[float, float]] | None = None) -> None:
    """An annulus (or only the arcs given as (centre, half width) in degrees), lit on the upper left."""
    for y in range(c.H):
        for x in range(c.W):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            r = math.hypot(dx, dy)
            if not inner <= r <= outer:
                continue
            if arcs is not None:
                a = math.degrees(math.atan2(dy, dx))
                if not any(abs(math.remainder(a - mid, 360.0)) <= half for mid, half in arcs):
                    continue
            c.px(x, y, _lit(dx, dy, r, shades))


def make_ring() -> np.ndarray:
    """The press ring closing on its target: pale outer ring, gold band, a bright centre."""
    c = Canvas(ICON, ICON)
    cx, cy = 12.0, 12.0
    _ring(c, cx, cy, 9.2, 11.4, PALE)
    _ring(c, cx, cy, 4.0, 6.2, GOLD[2:])
    c.ellipse(cx, cy, 1.7, 1.7, WHITE)
    c.outline(INK_OUT)
    return c.a


def make_follow_up() -> np.ndarray:
    """Two blue follow-up rings, one behind the other, each closing on a bright target."""
    c = Canvas(ICON, ICON)
    for cx, cy in ((8.6, 8.6), (15.4, 15.4)):
        # Each ring's own ink edge, so the front ring reads over the back one.
        part = Canvas(ICON, ICON)
        _ring(part, cx, cy, 5.0, 7.4, BLUE)
        part.ellipse(cx, cy, 1.6, 1.6, WHITE)
        part.outline(INK_OUT)
        c.paste(part.a, 0, 0)
    return c.a


def make_cleanse() -> np.ndarray:
    """The green Rot drop with a white sparkle over its upper right: the mark washing off."""
    c = Canvas(ICON, ICON)
    # The drop: a round belly and a point up and to the left, lit on its upper left.
    cx, cy, r = 9.5, 15.0, 6.4
    c.poly([(3.6, 13.0), (9.5, 2.5), (15.4, 13.0)], ROT[1])
    for y in range(ICON):
        for x in range(ICON):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            if d <= r:
                c.px(x, y, _lit(dx, dy, d * 1.4, ROT[:3]) if d > r * 0.55 else ROT[2])
    c.rect(5, 12, 6, 15, ROT[3])
    c.px(7, 10, ROT[3])
    c.px(6, 17, ROT[3])
    # The sparkle: a four-point star with a white core, a smaller glint beside it.
    sx, sy = 17, 6
    for i in range(-5, 6):
        shade = WHITE if abs(i) <= 2 else PALE[1]
        c.px(sx + i, sy, shade)
        c.px(sx, sy + i, shade)
    for d in (-1, 1):
        c.px(sx + d, sy + d, PALE[2])
        c.px(sx + d, sy - d, PALE[2])
    c.px(20, 13, WHITE)
    c.px(19, 13, PALE[1])
    c.px(21, 13, PALE[1])
    c.px(20, 12, PALE[1])
    c.px(20, 14, PALE[1])
    c.outline(INK_OUT)
    return c.a


def make_echo() -> np.ndarray:
    """The Echo: a violet dot in a ring with a sound wave on either side (the menus' Echo glyph)."""
    c = Canvas(ICON, ICON)
    cx, cy = 12.0, 12.0
    c.ellipse(cx, cy, 2.6, 2.6, VIOLET[2])
    c.px(11, 11, VIOLET[3])
    _ring(c, cx, cy, 5.0, 6.8, VIOLET[1:])
    _ring(c, cx, cy, 9.2, 11.0, VIOLET[1:], arcs=[(0.0, 46.0), (180.0, 46.0)])
    c.outline(INK_OUT)
    return c.a


def build(ctx) -> None:
    ctx.save("sprites/ui/tutorial_ring.png", make_ring(), scale=8)
    ctx.save("sprites/ui/tutorial_follow_up.png", make_follow_up(), scale=8)
    ctx.save("sprites/ui/tutorial_cleanse.png", make_cleanse(), scale=8)
    ctx.save("sprites/ui/tutorial_echo.png", make_echo(), scale=8)
