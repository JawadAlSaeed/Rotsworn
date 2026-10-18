"""Lights and fires: a street lamp, a brazier, a swamp lantern, a campfire (card #227). The bodies
are 3D; lamp glass and coals glow; flames stay flat pixel sprites the piece carries, so they
still sway and flicker like the rest of the art."""
from __future__ import annotations

import math
import random

from mathutils import Matrix, Vector

from kit.parts import box, lathe, lump, merge, tube
from kit.piece import Carried, Piece, Surface

IRON, GLASS = 0, 1
B_IRON, B_EMBER = 0, 1
S_WOOD, S_IRON, S_GLASS = 0, 1, 2
C_BARK, C_STONE, C_EMBER = 0, 1, 2

AMBER = (1.0, 0.68, 0.36)
FIRE = (1.0, 0.55, 0.25)


def _lantern(bm, centre: Vector, half: float, height: float, iron: int, glass: int) -> None:
    """A four-sided lantern: glass panes between iron corner posts, an iron floor and a little
    pyramid roof with a ring on top."""
    x, y, z = centre
    box(bm, x - half, x + half, y - half, y + half, z, z + height, mat=glass)
    for (dx, dy) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        cx, cy = x + dx * half, y + dy * half
        box(bm, cx - 0.025, cx + 0.025, cy - 0.025, cy + 0.025, z - 0.02, z + height + 0.02, mat=iron)
    box(bm, x - half - 0.03, x + half + 0.03, y - half - 0.03, y + half + 0.03, z - 0.05, z, mat=iron)
    lathe(bm, [(z + height, (half + 0.06) * 1.414), (z + height + 0.16, 0.03)], 4, mat=iron, cap_bottom=True,
          matrix=Matrix.Translation((x, y, 0.0)) @ Matrix.Rotation(math.radians(45.0), 4, "Z"))


def lamp(bm, rng: random.Random) -> set:
    """An iron street lamp: a stepped foot, a thin post, a collar, a lit lantern on top."""
    lathe(bm, [(0.0, 0.22), (0.1, 0.2), (0.16, 0.11)], 8, mat=IRON)
    lathe(bm, [(0.16, 0.06), (1.72, 0.05)], 8, mat=IRON, cap_top=False)
    lathe(bm, [(1.7, 0.1), (1.78, 0.09)], 8, mat=IRON)
    _lantern(bm, Vector((0.0, 0.0, 1.8)), 0.13, 0.32, IRON, GLASS)
    return set()


def brazier(bm, rng: random.Random) -> set:
    """An iron bowl on three legs heaped with glowing coals; its fire is a flat sprite."""
    for k in range(3):
        a = k * math.tau / 3 + 0.4
        tube(bm, [Vector((math.cos(a) * 0.22, math.sin(a) * 0.18, 0.0)),
                  Vector((math.cos(a) * 0.17, math.sin(a) * 0.14, 0.35)),
                  Vector((math.cos(a) * 0.12, math.sin(a) * 0.1, 0.68))], [0.03, 0.03, 0.03], 5, mat=B_IRON)
    faces = lathe(bm, [(0.6, 0.08), (0.66, 0.2), (0.74, 0.28), (0.8, 0.3)], 10, mat=B_IRON)
    for f in faces:
        f.normal_update()
        if f.normal.z > 0.95:
            f.material_index = B_EMBER
    lathe(bm, [(0.78, 0.32), (0.82, 0.32)], 10, mat=B_IRON, cap_top=False)
    part = lump(Vector((0.0, 0.0, 0.8)), Vector((0.22, 0.2, 0.07)), 61, 2, rng, mat=B_EMBER)
    merge(bm, part)
    part.free()
    return set()


def swamp_lantern(bm, rng: random.Random) -> set:
    """A crooked wooden pole bending over at the top, a lit lantern hanging from it on a chain."""
    tube(bm, [Vector((0.0, 0.0, -0.05)), Vector((0.02, 0.0, 0.9)), Vector((0.0, 0.0, 1.7)),
              Vector((0.08, 0.0, 1.92)), Vector((0.3, 0.0, 1.95))], [0.07, 0.06, 0.055, 0.05, 0.04], 6, mat=S_WOOD)
    box(bm, 0.29, 0.31, -0.01, 0.01, 1.62, 1.92, mat=S_IRON)
    _lantern(bm, Vector((0.3, 0.0, 1.32)), 0.1, 0.24, S_IRON, S_GLASS)
    return set()


def campfire(bm, rng: random.Random) -> set:
    """A ring of stones round three crossed logs on a bed of coals; its flames are a flat sprite."""
    for k in range(9):
        a = k * math.tau / 9 + rng.uniform(-0.1, 0.1)
        part = lump(Vector((math.cos(a) * 0.5, math.sin(a) * 0.38, 0.03)),
                    Vector((0.13, 0.11, 0.1)) * rng.uniform(0.85, 1.15), 70 + k, 2, rng, mat=C_STONE)
        merge(bm, part)
        part.free()
    for k, yaw in enumerate((-25.0, 25.0, 90.0)):
        d = Vector((math.cos(math.radians(yaw)), math.sin(math.radians(yaw)), 0.0))
        z = 0.08 + k * 0.05
        tube(bm, [-d * 0.4 + Vector((0, 0, z)), Vector((0, 0, z + 0.03)), d * 0.4 + Vector((0, 0, z))],
             [0.08, 0.075, 0.07], 6, mat=C_BARK)
    part = lump(Vector((0.0, 0.0, 0.0)), Vector((0.3, 0.24, 0.08)), 79, 2, rng, mat=C_EMBER)
    merge(bm, part)
    part.free()
    return set()


PIECES = [
    Piece("lamp", lamp, 242, [Surface("iron", "iron.png"), Surface("glass", "glass.png", glow=1.6, glow_color=AMBER)],
          moss=0.3),
    Piece("brazier", brazier, 243, [Surface("iron", "iron.png"), Surface("ember", "gold.png", glow=1.4, glow_color=FIRE)],
          moss=0.0, carried=[Carried("flame.png", (0.0, 0.0, 0.8))]),
    Piece("swamp_lantern", swamp_lantern, 244, [Surface("wood", "bark.png"), Surface("iron", "iron.png"),
                                                Surface("glass", "glass.png", glow=1.4, glow_color=AMBER)], moss=0.6),
    Piece("campfire", campfire, 245, [Surface("bark", "bark.png"), Surface("stone", "cliff.png"),
                                      Surface("ember", "gold.png", glow=1.4, glow_color=FIRE)],
          moss=0.0, carried=[Carried("flame_big.png", (0.0, -0.05, 0.08), glow=1.4)]),
]
