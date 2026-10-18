"""Stone pieces: ruins, rocks, carved stone and bones (card #224). Each is built at the size of the
flat sprite it replaces (one sprite pixel = 0.05 m), so the zones keep their layout."""
from __future__ import annotations

import math
import random

import bmesh
from mathutils import Matrix, Vector

from kit.parts import box, brick_courses, lathe, loose_bricks, lump, merge, prism, profile, tube
from kit.piece import Piece, Surface


def _turn(yaw: float = 0.0, tilt_x: float = 0.0, tilt_y: float = 0.0) -> Matrix:
    return (Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(tilt_x), 4, "X")
            @ Matrix.Rotation(math.radians(tilt_y), 4, "Y"))


def _at(x: float, y: float, z: float) -> Matrix:
    return Matrix.Translation((x, y, z))


def _jagged(rng: random.Random, sides: int, low: float, high: float, spikes: dict[int, float]) -> list[float]:
    """Per-corner lifts for a broken top: each corner low..high, a few spikes higher."""
    out = [rng.uniform(low, high) for _ in range(sides)]
    for k, extra in spikes.items():
        out[k % sides] += extra
    return out


# --- Ruins ---------------------------------------------------------------------------------------

def ruin_wall_broken(bm, rng: random.Random) -> set:
    """A ruined brick wall, 4 m long: tall at the left, a deep bite where it fell, a stub at the
    right, fallen bricks in front of the bite."""
    top = profile([(-2.0, 2.5), (-1.5, 2.45), (-1.1, 2.05), (-0.7, 1.95), (-0.35, 1.3), (0.2, 0.75),
                   (0.7, 0.7), (1.05, 1.2), (1.5, 1.65), (2.0, 1.45)])
    brick_courses(bm, rng, width=4.0, depth=0.6, courses=7, top=top)
    loose_bricks(bm, [(0.1, -0.52, 18.0, 6.0), (0.62, -0.6, -32.0, 0.0), (1.0, -0.48, 71.0, 9.0),
                      (-0.4, -0.55, 95.0, -5.0)])
    return set()


def wall_low(bm, rng: random.Random) -> set:
    """A low broken wall, 2 m long: three courses at the left stepping down to one at the right,
    two fallen bricks at its foot (the wall_low sprite)."""
    top = profile([(-1.0, 1.35), (-0.45, 1.3), (-0.2, 0.9), (0.35, 0.88), (0.55, 0.5), (1.0, 0.5)])
    brick_courses(bm, rng, width=2.0, depth=0.5, courses=3, top=top, recess=0.0)
    loose_bricks(bm, [(0.7, -0.45, 25.0, 4.0), (0.25, -0.5, -60.0, 0.0)])
    return set()


def arch_broken(bm, rng: random.Random) -> set:
    """One side of a fallen arch: a jamb on its plinth with the arch stones still curving over
    from it and breaking off past the top, the stub of the far jamb, fallen stones between."""
    depth = 0.5
    box(bm, -1.12, -0.42, -0.31, 0.31, 0.0, 0.22)                      # plinth
    box(bm, -1.0, -0.55, -depth * 0.5, depth * 0.5, 0.22, 1.75)        # jamb
    inner, outer = 0.7, 1.15
    cx, cz = -0.55 + inner, 1.75
    a = 180.0
    for k, span in enumerate((16.0, 16.0, 16.0, 15.0, 15.0, 14.0, 11.0)):
        a0, a1 = math.radians(a), math.radians(a - span + 1.0)
        pts = [(cx + math.cos(t) * r, cz + math.sin(t) * r)
               for (t, r) in ((a0, inner), (a0, outer), (a1, outer), (a1, inner))]
        sag = _at(0.0, 0.0, -0.012 * (k - 3) ** 2) if k >= 4 else None  # the last stones have slipped
        prism(bm, pts, -depth * 0.5, depth * 0.5, matrix=sag)
        a -= span
    box(bm, cx + inner, cx + inner + 0.45, -depth * 0.5, depth * 0.5, 0.0, 0.55)  # far jamb's stub
    box(bm, cx + inner - 0.06, cx + inner + 0.51, -0.31, 0.31, 0.0, 0.18)
    for (x, y, yaw, tilt, s) in ((0.2, -0.45, 30.0, 8.0, 0.32), (0.55, -0.3, -50.0, 0.0, 0.26),
                                 (-0.15, -0.6, 70.0, 12.0, 0.22)):
        box(bm, x - s * 0.6, x + s * 0.6, y - s * 0.5, y + s * 0.5, 0.0, s * 0.7, _turn(yaw, tilt))
    return set()


# --- Carved stone --------------------------------------------------------------------------------

def pillar(bm, rng: random.Random) -> set:
    """A broken fluted column on a stepped plinth, snapped off high with a splinter standing up,
    a chunk of it lying at the foot."""
    box(bm, -0.45, 0.45, -0.45, 0.45, 0.0, 0.2)
    box(bm, -0.37, 0.37, -0.37, 0.37, 0.2, 0.32)
    sides = 16
    lathe(bm, [(0.32, 0.33), (0.4, 0.3), (1.5, 0.29), (2.3, 0.28, _jagged(rng, sides, 0.0, 0.18, {3: 0.32, 4: 0.28}))],
          sides, flute=0.1)
    part = lump(Vector((0.55, -0.42, 0.06)), Vector((0.22, 0.18, 0.16)), 31, 3, rng)
    merge(bm, part)
    part.free()
    return set()


def column_fallen(bm, rng: random.Random) -> set:
    """A fallen column: three drums lying in a row, a little out of line, the last one tipped,
    and a broken chunk at its end."""
    lie = Matrix.Rotation(math.radians(90.0), 4, "Y")
    r = 0.42
    for k, (x, yaw, sink) in enumerate(((-0.95, 4.0, 0.0), (-0.05, -5.0, 0.0), (0.85, 9.0, 0.06))):
        m = _at(x, 0.0, r - sink) @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ lie @ _at(0.0, 0.0, -0.42)
        lathe(bm, [(0.0, r), (0.84, r)], 14, flute=0.08, cap_bottom=True, matrix=m)
    part = lump(Vector((1.4, -0.2, 0.08)), Vector((0.2, 0.18, 0.16)), 37, 3, rng)
    merge(bm, part)
    part.free()
    return set()


def statue_headless(bm, rng: random.Random) -> set:
    """A robed figure on a plinth with its head broken off: hands folded in front, the neck a
    jagged stump."""
    box(bm, -0.45, 0.45, -0.35, 0.35, 0.0, 0.6)
    box(bm, -0.5, 0.5, -0.4, 0.4, 0.6, 0.68)
    body = Matrix.Diagonal((1.0, 0.7, 1.0, 1.0))
    lathe(bm, [(0.68, 0.4), (0.9, 0.36), (1.3, 0.3), (1.6, 0.31), (1.74, 0.21)], 10, matrix=body)
    for side in (-1.0, 1.0):  # arms hang from the shoulders and fold in front
        tube(bm, [Vector((side * 0.27, 0.0, 1.62)), Vector((side * 0.32, -0.04, 1.38)),
                  Vector((side * 0.2, -0.2, 1.22)), Vector((side * 0.04, -0.25, 1.2))], [0.09, 0.085, 0.08, 0.07], 5)
    part = lump(Vector((0.0, -0.27, 1.2)), Vector((0.1, 0.07, 0.08)), 43, 0, rng)  # the folded hands
    merge(bm, part)
    part.free()
    lathe(bm, [(1.72, 0.11), (1.8, 0.1, _jagged(rng, 6, 0.0, 0.08, {1: 0.07}))], 6)   # neck stump
    return set()


def gravestone(bm, rng: random.Random) -> set:
    """A round-topped headstone on a low base, leaning back a little, one shoulder chipped."""
    box(bm, -0.34, 0.34, -0.15, 0.15, 0.0, 0.08)
    w, shoulder = 0.27, 0.72
    outline = [(-w, 0.0), (w, 0.0), (w, shoulder)]
    outline += [(math.cos(math.radians(t)) * w, shoulder + math.sin(math.radians(t)) * w)
                for t in range(18, 180, 18)]
    outline += [(-w, shoulder)]
    lean = _at(0.0, 0.0, 0.06) @ _turn(4.0, -6.0)
    prism(bm, outline, -0.07, 0.07, matrix=lean)
    return set()


def bones(bm, rng: random.Random) -> set:
    """A skull and two long bones crossed beside it. Returns the eye sockets (painted dark)."""
    eyes = set()
    skull = bmesh.new()
    bmesh.ops.create_icosphere(skull, subdivisions=2, radius=1.0)
    for v in skull.verts:
        v.co = Vector((v.co.x * 0.15, v.co.y * 0.17, v.co.z * 0.14 + 0.13)) + Vector((-0.3, 0.0, 0.0))
    skull.normal_update()
    for f in skull.faces:
        c = f.calc_center_median()
        if f.normal.y < -0.5 and 0.12 < c.z < 0.2 and 0.03 < abs(c.x + 0.3) < 0.09:
            f.tag = True
    marked = [f.calc_center_median().copy() for f in skull.faces if f.tag]
    merge(bm, skull)
    skull.free()
    box(bm, -0.39, -0.21, -0.19, -0.07, 0.0, 0.06)  # jaw
    for f in bm.faces:
        if any((f.calc_center_median() - m).length < 1e-4 for m in marked):
            eyes.add(f)
    for (a, b) in ((Vector((-0.05, -0.18, 0.04)), Vector((0.5, 0.12, 0.04))),
                   (Vector((-0.02, 0.16, 0.035)), Vector((0.48, -0.16, 0.035)))):
        mid = [a + (b - a) * t for t in (0.0, 0.33, 0.66, 1.0)]
        tube(bm, mid, [0.035, 0.028, 0.028, 0.035], 5)
        for end in (a, b):
            part = lump(end, Vector((0.05, 0.05, 0.045)), 41, 0, rng)
            merge(bm, part)
            part.free()
    return eyes




def rock_mossy(bm, rng: random.Random) -> set:
    """A big mossy boulder with a smaller one leaning on it and a pebble at its foot."""
    return _rocks(bm, rng, ((Vector((0.0, 0.0, 0.32)), Vector((1.15, 0.9, 0.82)), 3, 7),
                            (Vector((1.05, -0.38, 0.12)), Vector((0.52, 0.46, 0.42)), 11, 5),
                            (Vector((-0.98, -0.58, 0.02)), Vector((0.3, 0.26, 0.22)), 17, 3)))


def rock(bm, rng: random.Random) -> set:
    """A rock about 1.5 m across with a smaller stone at its side (the rock sprite)."""
    return _rocks(bm, rng, ((Vector((0.0, 0.0, 0.22)), Vector((0.66, 0.55, 0.72)), 5, 6),
                            (Vector((0.62, -0.3, 0.06)), Vector((0.3, 0.27, 0.27)), 13, 4)))


def rubble(bm, rng: random.Random) -> set:
    """A low heap of broken stone: a few rough lumps and squared blocks thrown together."""
    _rocks(bm, rng, ((Vector((-0.2, 0.05, 0.08)), Vector((0.36, 0.3, 0.3)), 19, 4),
                     (Vector((0.3, -0.05, 0.05)), Vector((0.3, 0.26, 0.24)), 23, 4),
                     (Vector((0.0, 0.28, 0.03)), Vector((0.25, 0.2, 0.2)), 29, 3)))
    for (x, y, z, yaw, tilt, s) in ((-0.5, -0.22, 0.0, 25.0, 0.0, 0.3), (0.55, 0.22, 0.0, -40.0, 0.0, 0.26),
                                    (0.05, -0.25, 0.12, 60.0, 18.0, 0.24), (-0.2, 0.0, 0.3, -15.0, 10.0, 0.2)):
        box(bm, x - s * 0.6, x + s * 0.6, y - s * 0.45, y + s * 0.45, z, z + s * 0.6, _turn(yaw, tilt))
    return set()


def _rocks(bm, rng: random.Random, lumps) -> set:
    for centre, radii, seed, cuts in lumps:
        part = lump(centre, radii, seed, cuts, rng)
        merge(bm, part)
        part.free()
    return set()


PIECES = [
    Piece("ruin_wall_broken", ruin_wall_broken, 221, [Surface("stone", "ruin_wall.png")]),
    Piece("rock_mossy", rock_mossy, 222, [Surface("stone", "cliff.png")]),
    Piece("rock", rock, 224, [Surface("stone", "cliff.png")]),
    Piece("rubble", rubble, 225, [Surface("stone", "stone_dressed.png")]),
    Piece("wall_low", wall_low, 226, [Surface("stone", "ruin_wall.png")]),
    Piece("arch_broken", arch_broken, 227, [Surface("stone", "stone_dressed.png")]),
    Piece("pillar", pillar, 228, [Surface("stone", "stone_dressed.png")]),
    Piece("column_fallen", column_fallen, 229, [Surface("stone", "stone_dressed.png")]),
    Piece("statue_headless", statue_headless, 230, [Surface("stone", "stone_dressed.png")], moss=0.7),
    Piece("gravestone", gravestone, 231, [Surface("stone", "stone_dressed.png")], moss=0.8),
    Piece("bones", bones, 232, [Surface("bone", "bone.png")], moss=0.0),
]
