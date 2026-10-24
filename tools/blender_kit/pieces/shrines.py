"""The dry fountain (card #226). Until phase 26 this module also built the zones' shrines, rot seals
and the gate, with glowing surfaces of their own so the game could dim a used shrine; they went
with the walkable zones (DESIGN.md 8.22, G7)."""
from __future__ import annotations

import math
import random

from mathutils import Matrix, Vector

from kit.parts import box, lathe
from kit.piece import Piece, Surface


def fountain(bm, rng: random.Random) -> set:
    """A dry fountain: a wide round basin with a rim of stones round its dusty floor, a pedestal
    in the middle with an empty bowl. Returns the basin floor (painted dark)."""
    faces = lathe(bm, [(0.0, 0.98), (0.34, 0.95)], 16)
    floor = set()
    for f in faces:
        f.normal_update()
        if f.normal.z > 0.9:
            floor.add(f)
    n = 18
    for k in range(n):
        a = k * math.tau / n
        c = Vector((math.cos(a) * 0.9, math.sin(a) * 0.9, 0.34))
        box(bm, c.x - 0.17, c.x + 0.17, c.y - 0.08, c.y + 0.08, 0.34, 0.44, Matrix.Rotation(a + math.pi * 0.5, 4, "Z"))
    lathe(bm, [(0.34, 0.2), (0.78, 0.13), (0.84, 0.26), (0.92, 0.3)], 10)
    return floor


PIECES = [
    Piece("fountain", fountain, 251, [Surface("stone", "stone_dressed.png")], moss=0.7),
]
