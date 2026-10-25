"""Icons for the run's info screens (phase 22: an icon and a word instead of a sentence).

Drawn like the map's stop pictures and the gold coin (24x24, lit from the upper left, a dark sepia
ink outline), so they sit beside them in a row of chips under the map, in the shop and on the run's
end screen. The game draws them with nearest filtering at a whole multiple.

- ui/restock.png: new wares on the shelves (the shop's Restock): two cream arrows chasing each
  other round a circle.
- ui/door.png: back to the map (the shop's Leave): an arched plank door in a stone frame, a gold
  ring for a handle, standing ajar on a warm light.

Paths: data/presentation/map_visuals.tres (restock_icon_path, leave_icon_path). (The anvil for the
shop's Upgrade went with the item levels, card #332.)
"""
from __future__ import annotations

import math

import numpy as np

from kit.canvas import Canvas
from kit.color import ramp
from kit.palette import M

ICON = 24

SEPIA = ramp("#4b3527", below=1, above=2, step_l=0.08)  # the map's ink, darkest first
INK_OUT = SEPIA[0]
IRON = M["iron"].colors
GOLD = M["gold"].colors
CREAM = M["cloth_cream"].colors
WOOD = M["wood"].colors
STONE = M["stone"].colors
AMBER = M["glow_amber"].colors


def make_restock() -> np.ndarray:
    """Two arrows chasing each other round a circle (new wares): cream, lit on the upper left."""
    c = Canvas(ICON, ICON)
    cx, cy = 11.5, 12.0
    inner, outer = 4.4, 7.0
    gap = math.radians(40.0)
    gaps = (math.radians(-60.0), math.radians(120.0))
    for y in range(ICON):
        for x in range(ICON):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            r = math.hypot(dx, dy)
            if not inner <= r <= outer:
                continue
            a = math.atan2(dy, dx)
            if any(abs(math.remainder(a - g, math.tau)) < gap for g in gaps):
                continue
            # Light from the upper left: brighter where the ring faces it.
            facing = -(dx + dy) / (r * math.sqrt(2.0))
            c.px(x, y, CREAM[3] if facing > 0.35 else (CREAM[2] if facing > -0.4 else CREAM[1]))
    # Each arc ends (clockwise) at a gap in a wide arrowhead pointing on round the circle.
    mid = (inner + outer) * 0.5
    for g in gaps:
        end = g - gap
        tip = end + math.radians(52.0)
        pts = [(cx + mid * math.cos(tip), cy + mid * math.sin(tip)),
               (cx + (inner - 2.6) * math.cos(end), cy + (inner - 2.6) * math.sin(end)),
               (cx + (outer + 2.6) * math.cos(end), cy + (outer + 2.6) * math.sin(end))]
        c.poly(pts, CREAM[3] if g > 0 else CREAM[2])
    c.outline(INK_OUT)
    return c.a


def make_door() -> np.ndarray:
    """An arched plank door in a stone frame with a gold ring handle, ajar on a warm light."""
    c = Canvas(ICON, ICON)
    # The stone frame: an arch over two jambs.
    c.ellipse(11.5, 9.0, 8.0, 7.0, STONE[2])
    c.rect(4, 9, 19, 21, STONE[2])
    c.rect(4, 9, 5, 21, STONE[3])
    c.rect(18, 9, 19, 21, STONE[1])
    # The doorway: warm light where the door stands open.
    c.ellipse(11.5, 9.5, 6.0, 5.5, AMBER[2])
    c.rect(6, 9, 17, 21, AMBER[2])
    c.rect(14, 8, 17, 21, AMBER[3])
    # The door: planks swung in a little (narrower than the doorway), its edge in shadow.
    c.ellipse(10.0, 9.5, 4.5, 5.5, WOOD[2])
    c.rect(6, 9, 14, 21, WOOD[2])
    c.rect(6, 9, 7, 21, WOOD[3])
    for px_x in (9, 12):
        c.line(px_x, 6, px_x, 21, WOOD[1])
    c.rect(14, 8, 14, 21, WOOD[0])
    # Iron bands and the gold ring.
    for band_y in (10, 17):
        c.line(6, band_y, 13, band_y, IRON[1])
    c.px(12, 13, GOLD[3])
    c.px(13, 14, GOLD[2])
    c.px(12, 15, GOLD[2])
    c.px(11, 14, GOLD[3])
    # The step.
    c.rect(3, 21, 20, 22, STONE[1])
    c.rect(3, 21, 20, 21, STONE[3])
    c.outline(INK_OUT)
    return c.a


def build(ctx) -> None:
    ctx.save("sprites/ui/restock.png", make_restock(), scale=8)
    ctx.save("sprites/ui/door.png", make_door(), scale=8)
