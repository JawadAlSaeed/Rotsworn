"""Bigger ruins to walk past and around (card #229): broken stairs, a plank footbridge, a ruined
house, the stub of a round tower, a fallen gate."""
from __future__ import annotations

import math
import random

import bmesh
from mathutils import Matrix, Vector

from kit.parts import box, brick_courses, loose_bricks, lump, merge, plank, prism, profile
from kit.piece import Piece, Surface

STONE, WOOD = 0, 1


def _turn(yaw: float = 0.0, tilt_x: float = 0.0, tilt_y: float = 0.0) -> Matrix:
    return (Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(tilt_x), 4, "X")
            @ Matrix.Rotation(math.radians(tilt_y), 4, "Y"))


def _wall(bm, rng: random.Random, length: float, depth: float, courses: int, top, matrix: Matrix,
          mat: int = STONE, recess: float = 0.1) -> None:
    """A broken brick wall (kit brick_courses) built along x at the origin, then moved by `matrix`."""
    part = bmesh.new()
    brick_courses(part, rng, width=length, depth=depth, courses=courses, top=top, recess=recess, mat=mat)
    bmesh.ops.transform(part, matrix=matrix, verts=list(part.verts))
    merge(bm, part)
    part.free()


def stairs_broken(bm, rng: random.Random) -> set:
    """Five worn stone steps up to a small landing that leads nowhere now, their right ends broken
    away, a low side wall on the left and a few fallen stones at the foot."""
    rise, run = 0.2, 0.34
    for k in range(5):
        right = 0.8 - (rng.uniform(0.1, 0.45) if k >= 2 else rng.uniform(0.0, 0.08))
        box(bm, -0.8, right, -0.95 + k * run, 1.0, k * rise, (k + 1) * rise + 0.002)
    # The side wall: its outline is (depth, height), turned so it runs along the stairs on the left.
    prism(bm, [(-0.95, 0.0), (1.0, 0.0), (1.0, 1.05), (-0.95, 0.25)], 0.8, 0.98,
          matrix=Matrix.Rotation(math.radians(90.0), 4, "Z"))
    loose_bricks(bm, [(0.75, -1.15, 30.0, 6.0), (0.35, -1.3, -45.0, 0.0), (1.0, -0.6, 80.0, 10.0)],
                 size=(0.36, 0.24, 0.18))
    return set()


def bridge_planks(bm, rng: random.Random) -> set:
    """A footbridge of loose planks 4.2 m long on two stringers and six posts, a rail along its
    far side, the near rail broken off with one post leaning out. Walkable: its deck sits low."""
    deck = 0.26
    for k in range(14):
        x = -2.1 + 0.15 + k * 0.3
        if k == 9:
            continue  # one plank missing
        z = deck + rng.uniform(-0.015, 0.015)
        turn = _turn(rng.uniform(-4.0, 4.0))
        box(bm, x - 0.13, x + 0.13, -0.7, 0.7, z, z + 0.05, turn, mat=0)
    for y in (-0.5, 0.5):
        box(bm, -2.1, 2.1, y - 0.06, y + 0.06, deck - 0.12, deck, mat=0)
    for x in (-2.0, 0.0, 2.0):
        for y in (-0.62, 0.62):
            top = deck + (0.95 if y > 0 else (0.35 if x != 2.0 else 0.95))
            lean = _turn(0.0, 14.0 if (x == 2.0 and y < 0) else 0.0)
            box(bm, x - 0.06, x + 0.06, y - 0.06, y + 0.06, -0.3, top, lean, mat=0)
    plank(bm, Vector((-2.05, 0.62, deck + 0.85)), Vector((2.05, 0.62, deck + 0.88)), 0.09, 0.05,
          up=Vector((0.0, -1.0, 0.0)), mat=0)
    return set()


def house_broken(bm, rng: random.Random) -> set:
    """A ruined cottage, 4 m by 3 m: the back wall still high with a broken top, a side wall
    with an empty window, the other side fallen low, two stubs either side of the doorway in
    front, charred roof beams fallen in. Inside: rubble."""
    d = 0.4
    _wall(bm, rng, 4.0, d, 7, profile([(-2.0, 2.6), (-0.8, 2.75), (0.4, 2.2), (1.2, 2.4), (2.0, 1.6)]),
          Matrix.Translation((0.0, 1.4, 0.0)))
    side = profile([(-1.6, 2.6), (-0.4, 2.4), (0.4, 2.3), (1.6, 1.7)])
    _wall(bm, rng, 3.2, d, 7, side, Matrix.Translation((-1.8, 0.0, 0.0)) @ Matrix.Rotation(math.radians(90.0), 4, "Z"))
    _wall(bm, rng, 3.2, d, 3, profile([(-1.6, 1.2), (0.0, 0.8), (1.6, 0.5)]),
          Matrix.Translation((1.8, 0.0, 0.0)) @ Matrix.Rotation(math.radians(90.0), 4, "Z"))
    for x0, x1, h in ((-2.0, -0.7, 1.1), (0.7, 2.0, 0.75)):
        top = profile([(-1.0, h), (1.0, h * 0.7)])
        _wall(bm, rng, x1 - x0, d, 3, top, Matrix.Translation(((x0 + x1) * 0.5, -1.4, 0.0)))
    # The window: a dark pane on the side wall's outer face (painted dark, it reads as a hole).
    window = box(bm, -2.04, -1.99, -0.4, 0.2, 1.3, 1.8)
    for (a, b) in ((Vector((-1.7, 1.25, 2.55)), Vector((1.3, 1.2, 0.05))),
                   (Vector((-1.75, -0.2, 2.2)), Vector((0.6, -0.6, 0.0))),
                   (Vector((-1.6, 0.6, 0.05)), Vector((1.4, 0.9, 0.12)))):
        plank(bm, a, b, 0.16, 0.14, mat=WOOD)
    part = lump(Vector((0.4, 0.3, 0.05)), Vector((0.6, 0.45, 0.25)), 97, 4, rng)
    merge(bm, part)
    part.free()
    return window


def tower_ruined(bm, rng: random.Random) -> set:
    """The stub of a round watchtower: a ring of dressed blocks, course on course, broken off
    unevenly from 1 m to 4 m high, a doorway facing front, fallen blocks round its foot."""
    r, n, course = 1.25, 10, 0.42
    for c in range(9):
        z0 = c * course
        for k in range(n):
            a = (k + 0.5 * (c % 2)) * math.tau / n
            height = 1.2 + 2.8 * (0.5 + 0.5 * math.cos(a - 2.2)) + rng.uniform(-0.3, 0.3)
            if z0 + course > height:
                continue
            if abs(math.atan2(math.sin(a + math.pi * 0.5), math.cos(a + math.pi * 0.5))) < 0.35 and c < 5:
                continue  # the doorway (front, -y)
            c_ = Vector((math.cos(a) * r, math.sin(a) * r, 0.0))
            w = r * math.tau / n * 0.5 - 0.02
            box(bm, c_.x - w, c_.x + w, c_.y - 0.22, c_.y + 0.22, z0, z0 + course - 0.01,
                Matrix.Rotation(a + math.pi * 0.5, 4, "Z"))
    for k in range(5):
        a = rng.uniform(0.0, math.tau)
        rr = r + rng.uniform(0.45, 0.9)
        x, y = math.cos(a) * rr, math.sin(a) * rr
        box(bm, x - 0.3, x + 0.3, y - 0.2, y + 0.2, 0.0, 0.38, _turn(rng.uniform(0, 180), rng.uniform(-12, 12)))
    return set()


def gate_ruined(bm, rng: random.Random) -> set:
    """A fallen gateway: two square pillars with stepped caps, 2.4 m apart, the lintel stone
    that spanned them fallen and leaning from one to the ground."""
    for x in (-1.5, 1.5):
        box(bm, x - 0.36, x + 0.36, -0.36, 0.36, 0.0, 0.25)
        box(bm, x - 0.28, x + 0.28, -0.28, 0.28, 0.25, 2.65 if x < 0 else 1.9)
        if x < 0:
            box(bm, x - 0.34, x + 0.34, -0.34, 0.34, 2.65, 2.8)
    prism(bm, [(-1.3, 2.62), (-1.15, 2.85), (1.3, 0.3), (1.15, 0.05)], -0.25, 0.25)
    for (x, y, s) in ((1.1, -0.5, 0.3), (0.6, 0.55, 0.24)):
        box(bm, x - s, x + s, y - s * 0.7, y + s * 0.7, 0.0, s, _turn(rng.uniform(0, 180), rng.uniform(-10, 10)))
    return set()


PIECES = [
    Piece("stairs_broken", stairs_broken, 254, [Surface("stone", "stone_dressed.png")], moss=0.8),
    Piece("bridge_planks", bridge_planks, 255, [Surface("wood", "planks.png")], moss=0.5),
    Piece("house_broken", house_broken, 256, [Surface("stone", "ruin_wall.png"), Surface("wood", "bark.png")],
          moss=0.8),
    Piece("tower_ruined", tower_ruined, 257, [Surface("stone", "stone_dressed.png")], moss=0.8),
    Piece("gate_ruined", gate_ruined, 258, [Surface("stone", "stone_dressed.png")], moss=0.7),
]
