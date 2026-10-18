"""Raised ground (card #230): rocky ledges and cliff edges that give a zone Octopath-style height.
Looks only: walking stays flat, a ledge is solid like a wall. The top is its own surface (the
zone's ground: moss, ash, bog), the face is rock."""
from __future__ import annotations

import math
import random

import bmesh
from mathutils import Vector, noise

from kit.piece import Piece, Surface

ROCK, TOP = 0, 1


def _ledge(bm, rng: random.Random, length: float, depth: float, height: float, seed: int,
           steps: int = 14) -> None:
    """A shelf of raised ground along x: a craggy rock face in front (it bulges and leans, its
    upper lip overhangs a little), a flat top with a ragged front edge, plain rock sides and back.
    Built as columns of corners joined into one closed solid."""
    cols = []
    for i in range(steps + 1):
        t = i / steps
        x = -length * 0.5 + t * length
        n1 = noise.noise(Vector((x * 0.9, seed * 0.37, 0.5)))
        n2 = noise.noise(Vector((x * 2.1, seed * 0.71, 1.5)))
        end = min(t, 1.0 - t) * steps  # corners near the ends taper down
        fall = min(1.0, end / 2.0)
        top = height * (0.75 + 0.25 * fall) + 0.12 * n1
        front = -depth * 0.5 + 0.18 * n2
        cols.append([
            bm.verts.new((x, front + 0.12, 0.0)),                    # foot of the face
            bm.verts.new((x, front - 0.08 + 0.1 * n1, top * 0.5)),   # the bulge
            bm.verts.new((x, front - 0.04, top)),                    # the lip
            bm.verts.new((x, front + 0.25, top + 0.03 * n2)),        # top, just behind the lip
            bm.verts.new((x, depth * 0.5, top)),                     # top, back edge
            bm.verts.new((x, depth * 0.5, 0.0)),                     # back foot
        ])
    for a, b in zip(cols, cols[1:]):
        for k in range(6):
            j = (k + 1) % 6
            f = bm.faces.new((a[k], b[k], b[j], a[j]))
            f.material_index = TOP if k in (2, 3) else ROCK
    for ring, flip in ((cols[0], True), (cols[-1], False)):
        f = bm.faces.new(list(reversed(ring)) if flip else ring)
        f.material_index = ROCK
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))


def _cliff(bm, length: float, depth: float, height: float, seed: int, steps: int, rows: int) -> None:
    """A tall cliff face along x: the face in `rows` bands, each bulging and stepping on its own
    noise and leaning back a little higher up, a ragged top rim with the zone's ground on top.
    Closed into one solid (the underside is the ground)."""
    cols = []
    for i in range(steps + 1):
        t = i / steps
        x = -length * 0.5 + t * length
        end = min(t, 1.0 - t) * steps
        fall = min(1.0, end / 2.5)
        top = height * (0.8 + 0.2 * fall) + 0.35 * noise.noise(Vector((x * 0.6, seed * 0.31, 2.5)))
        ring = []
        for r in range(rows + 1):
            f = r / rows
            bulge = 0.55 * noise.noise(Vector((x * 1.1, r * 1.7, seed * 0.53)))
            ring.append(bm.verts.new((x, -depth * 0.5 + bulge + 0.35 * f, top * f)))
        ring.append(bm.verts.new((x, -depth * 0.5 + 0.7, top + 0.04)))   # the rim, just behind the lip
        ring.append(bm.verts.new((x, depth * 0.5, top)))                 # top, back edge
        ring.append(bm.verts.new((x, depth * 0.5, 0.0)))                 # back foot
        cols.append(ring)
    n = len(cols[0])
    for a, b in zip(cols, cols[1:]):
        for k in range(n):
            j = (k + 1) % n
            f = bm.faces.new((a[k], b[k], b[j], a[j]))
            f.material_index = TOP if k in (rows, rows + 1) else ROCK
    for ring, flip in ((cols[0], True), (cols[-1], False)):
        bm.faces.new(list(reversed(ring)) if flip else ring).material_index = ROCK
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))


def cliff_wall(bm, rng: random.Random) -> set:
    """A tall cliff wall, 8 m long, 2 m deep, about 5 m high: what stands at the back of a fight
    arena (four of them side by side close it off)."""
    _cliff(bm, 8.0, 2.0, 5.0, 11, steps=18, rows=5)
    return set()


def ledge_rock(bm, rng: random.Random) -> set:
    """A low shelf of raised ground, 6 m long, 2 m deep, about 1.2 m high."""
    _ledge(bm, rng, 6.0, 2.0, 1.2, 3)
    return set()


def ledge_rock_tall(bm, rng: random.Random) -> set:
    """A cliff edge, 6 m long, 2.4 m deep, about 2.5 m high."""
    _ledge(bm, rng, 6.0, 2.4, 2.5, 7, steps=16)
    return set()


PIECES = [
    Piece("ledge_rock", ledge_rock, 259, [Surface("rock", "cliff.png"), Surface("top", "moss.png")], moss=0.6),
    Piece("ledge_rock_tall", ledge_rock_tall, 260, [Surface("rock", "cliff.png"), Surface("top", "moss.png")],
          moss=0.6),
    Piece("cliff_wall", cliff_wall, 261, [Surface("rock", "cliff.png"), Surface("top", "moss.png")], moss=0.5),
]
