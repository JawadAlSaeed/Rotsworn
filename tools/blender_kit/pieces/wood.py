"""Wood and village pieces: stumps, logs, fences, a cart, a well, a stilt hut, chests (card #225).
Each is built near the size of the flat sprite it replaces (one sprite pixel = 0.05 m)."""
from __future__ import annotations

import math
import random

import bmesh
from mathutils import Matrix, Vector, noise

from kit.parts import box, lathe, lump, merge, plank, prism, tube
from kit.piece import Piece, Surface

BARK, ROT = 0, 1
WOOD, EARTH = 0, 1
CART_STONE = 1
WELL_STONE, WELL_WOOD, WELL_THATCH = 0, 1, 2
HUT_WOOD, HUT_THATCH, HUT_GLASS = 0, 1, 2
CHEST_WOOD, CHEST_IRON, CHEST_GOLD = 0, 1, 2
FRONT = Vector((0.0, -1.0, 0.0))  # boards face the camera


def _turn(yaw: float = 0.0, tilt_x: float = 0.0, tilt_y: float = 0.0) -> Matrix:
    return (Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(tilt_x), 4, "X")
            @ Matrix.Rotation(math.radians(tilt_y), 4, "Y"))


def stump_rotten(bm, rng: random.Random) -> set:
    """A rotten stump: a flared trunk broken off in splinters, hollow and rotted inside (its own
    surface), with roots that hug the ground and dive into it. Returns the hollow (painted dark)."""
    sides = 10
    jag = [rng.uniform(0.0, 0.1) for _ in range(sides)]
    jag[2] += 0.3  # one tall splinter and two shorter ones
    jag[3] += 0.12
    jag[7] += 0.14
    rings: list[list] = []
    for (z, r) in ((0.0, 0.68), (0.2, 0.55), (0.5, 0.49), (None, 0.47), (None, 0.32)):
        ring = []
        for i in range(sides):
            a = i * math.tau / sides
            wob = 1.0 + 0.08 * noise.noise(Vector((math.cos(a) * 2.0, math.sin(a) * 2.0, 5.0)))
            h = z if z is not None else 0.95 + jag[i] - (0.07 if r < 0.4 else 0.0)
            ring.append(bm.verts.new((math.cos(a) * r * wob, math.sin(a) * r * wob, h)))
        rings.append(ring)
    for lo, hi in zip(rings[:4], rings[1:4]):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((lo[i], lo[j], hi[j], hi[i])).material_index = BARK
    for i in range(sides):  # the rim between the bark and the hollow
        j = (i + 1) % sides
        bm.faces.new((rings[3][i], rings[3][j], rings[4][j], rings[4][i])).material_index = BARK
    floor = bm.verts.new((0.0, 0.0, 0.62))
    hollow = set()
    for i in range(sides):
        j = (i + 1) % sides
        f = bm.faces.new((rings[4][i], rings[4][j], floor))
        f.material_index = ROT
        hollow.add(f)
    for k in range(5):
        a = k * math.tau / 5 + rng.uniform(-0.3, 0.3)
        reach = rng.uniform(0.85, 1.05)
        bend = rng.uniform(-0.35, 0.35)
        path = []
        for t, r, z in ((0.0, 0.4, 0.3), (0.35, 0.7, 0.13), (0.7, 0.92, 0.05), (1.0, 1.02, -0.06)):
            aa = a + bend * t * t
            path.append(Vector((math.cos(aa) * r * reach, math.sin(aa) * r * reach, z)))
        tube(bm, path, [0.2, 0.14, 0.09, 0.035], 5, mat=BARK)
    return hollow


def grave_cross(bm, rng: random.Random) -> set:
    """A wooden grave cross leaning a little in its low mound of earth (the grave_cross sprite)."""
    part = lump(Vector((0.0, 0.0, -0.05)), Vector((0.42, 0.55, 0.2)), 47, 2, rng, mat=EARTH)
    merge(bm, part)
    part.free()
    lean = (Matrix.Translation((0.0, 0.18, 0.0)) @ Matrix.Rotation(math.radians(-5.0), 4, "X")
            @ Matrix.Rotation(math.radians(4.0), 4, "Y"))
    post = box(bm, -0.06, 0.06, -0.045, 0.045, 0.0, 1.0, mat=WOOD)
    bar = box(bm, -0.26, 0.26, -0.04, 0.04, 0.62, 0.72, mat=WOOD)
    verts = {v for f in post | bar for v in f.verts}
    bmesh.ops.transform(bm, matrix=lean, verts=list(verts))
    return set()


def fence(bm, rng: random.Random) -> set:
    """A broken fence: three posts, a top rail, the lower rail snapped with its far half fallen
    to the ground (the fence sprite)."""
    for x in (-0.8, 0.0, 0.8):
        h = 0.8 + rng.uniform(-0.06, 0.02)
        box(bm, x - 0.055, x + 0.055, -0.055, 0.055, 0.0, h, _turn(rng.uniform(-4.0, 4.0), rng.uniform(-3.0, 3.0)))
    plank(bm, Vector((-0.86, -0.07, 0.62)), Vector((0.86, -0.07, 0.64)), 0.1, 0.04, up=FRONT)
    plank(bm, Vector((-0.86, -0.07, 0.32)), Vector((0.06, -0.07, 0.3)), 0.1, 0.04, up=FRONT)
    plank(bm, Vector((0.1, -0.09, 0.27)), Vector((0.88, -0.2, 0.03)), 0.1, 0.04, up=FRONT)
    return set()


def signpost(bm, rng: random.Random) -> set:
    """A crooked signpost with two arrow boards pointing opposite ways."""
    box(bm, -0.06, 0.06, -0.06, 0.06, 0.0, 1.45, _turn(0.0, 2.0, -2.0))
    right = [(0.0, 1.12), (0.5, 1.12), (0.64, 1.21), (0.5, 1.3), (0.0, 1.3)]
    left = [(0.0, 0.84), (-0.46, 0.84), (-0.6, 0.925), (-0.46, 1.01), (0.0, 1.01)]
    prism(bm, right, -0.1, -0.06, matrix=_turn(0.0, 0.0, -4.0))
    prism(bm, left, -0.1, -0.06, matrix=_turn(0.0, 0.0, 5.0))
    return set()


def _wheel(bm, centre: Vector, r: float, thick: float) -> None:
    """A spoked wheel standing in the x-z plane: a rim of short boards, six spokes, a hub."""
    n = 12
    for k in range(n):
        a0, a1 = k * math.tau / n, (k + 1) * math.tau / n
        p0 = centre + Vector((math.cos(a0) * r, 0.0, math.sin(a0) * r))
        p1 = centre + Vector((math.cos(a1) * r, 0.0, math.sin(a1) * r))
        plank(bm, p0, p1, thick, 0.07, up=FRONT)
    for k in range(6):
        a = k * math.tau / 6 + 0.2
        plank(bm, centre, centre + Vector((math.cos(a) * r, 0.0, math.sin(a) * r)), thick * 0.6, 0.04, up=FRONT)
    lathe(bm, [(-thick, 0.08), (thick, 0.08)], 8, cap_bottom=True,
          matrix=Matrix.Translation(centre) @ Matrix.Rotation(math.radians(90.0), 4, "X"))


def cart(bm, rng: random.Random) -> set:
    """A broken hand cart: its plank bed with low sides, one spoked wheel left, the other corner
    propped on a stone, its two shafts resting on the ground."""
    z0, z1 = 0.36, 0.44
    box(bm, -0.75, 0.45, -0.42, 0.42, z0, z1)
    box(bm, -0.75, 0.45, -0.44, -0.38, z1, z1 + 0.22)
    box(bm, -0.75, 0.45, 0.38, 0.44, z1, z1 + 0.18, _turn(0.0, 6.0))
    box(bm, -0.79, -0.73, -0.44, 0.44, z1, z1 + 0.25)
    _wheel(bm, Vector((-0.2, -0.52, 0.36)), 0.34, 0.07)
    part = lump(Vector((-0.2, 0.3, 0.12)), Vector((0.24, 0.2, 0.22)), 53, 3, rng, mat=CART_STONE)
    merge(bm, part)
    part.free()
    for y in (-0.3, 0.3):
        plank(bm, Vector((0.4, y, 0.4)), Vector((1.25, y * 0.85, 0.03)), 0.07, 0.07)
    return set()


def log(bm, rng: random.Random) -> set:
    """A fallen log, bark all round, its broken ends rotted, a branch stub."""
    lie = Matrix.Translation((-0.85, 0.0, 0.32)) @ Matrix.Rotation(math.radians(90.0), 4, "Y")
    faces = lathe(bm, [(0.0, 0.3), (0.6, 0.33), (1.2, 0.31), (1.7, 0.28)], 9, cap_bottom=True,
                  wobble=0.08, seed=5, matrix=lie, mat=BARK)
    for f in faces:
        f.normal_update()
        if abs(f.normal.x) > 0.85:
            f.material_index = ROT
    tube(bm, [Vector((0.25, -0.12, 0.5)), Vector((0.32, -0.25, 0.7)), Vector((0.36, -0.3, 0.82))],
         [0.09, 0.07, 0.05], 5, mat=BARK)
    return set()


def well(bm, rng: random.Random) -> set:
    """An old well: a round stone wall with a rim of stones round the dark hole, two posts, a
    beam with a rope and bucket, a little straw roof. Returns the hole (painted dark)."""
    faces = lathe(bm, [(0.0, 0.55), (0.5, 0.52)], 12, mat=WELL_STONE)
    hole = set()
    for f in faces:
        f.normal_update()
        if f.normal.z > 0.9:
            hole.add(f)
    for k in range(12):
        a = k * math.tau / 12
        c = Vector((math.cos(a) * 0.47, math.sin(a) * 0.47, 0.5))
        box(bm, c.x - 0.13, c.x + 0.13, c.y - 0.07, c.y + 0.07, 0.5, 0.6,
            Matrix.Rotation(a + math.pi * 0.5, 4, "Z"), mat=WELL_STONE)
    for x in (-0.47, 0.47):
        box(bm, x - 0.05, x + 0.05, -0.05, 0.05, 0.5, 1.36, mat=WELL_WOOD)
    box(bm, -0.55, 0.55, -0.045, 0.045, 1.26, 1.34, mat=WELL_WOOD)
    box(bm, -0.012, 0.012, -0.012, 0.012, 0.86, 1.26, mat=WELL_WOOD)
    lathe(bm, [(0.7, 0.09), (0.86, 0.11)], 8, mat=WELL_WOOD)
    prism(bm, [(-0.68, 1.34), (0.68, 1.34), (0.0, 1.66)], -0.5, 0.5, mat=WELL_THATCH)
    return hole


def stilt_hut(bm, rng: random.Random) -> set:
    """A bog hut on stilts: four posts, a plank deck, board walls, a door, one lit window, a
    steep straw roof and a ladder up to the deck."""
    for (x, y) in ((-0.62, -0.52), (0.62, -0.52), (-0.62, 0.52), (0.62, 0.52)):
        box(bm, x - 0.07, x + 0.07, y - 0.07, y + 0.07, 0.0, 1.02,
            _turn(0.0, rng.uniform(-2.0, 2.0), rng.uniform(-2.0, 2.0)))
    box(bm, -0.86, 0.86, -0.76, 0.76, 1.0, 1.1)
    box(bm, -0.66, 0.66, -0.56, 0.56, 1.1, 2.02)
    box(bm, -0.42, -0.08, -0.6, -0.55, 1.1, 1.8)                      # door
    box(bm, 0.18, 0.46, -0.59, -0.55, 1.45, 1.74, mat=HUT_GLASS)      # lit window
    lathe(bm, [(1.98, 1.12), (2.8, 0.05)], 4, mat=HUT_THATCH, cap_bottom=True,
          matrix=Matrix.Rotation(math.radians(45.0), 4, "Z"))
    for x in (0.14, 0.5):
        plank(bm, Vector((x, -1.18, 0.0)), Vector((x, -0.78, 1.08)), 0.06, 0.06)
    for k in range(4):
        z = 0.22 + k * 0.24
        y = -1.18 + (z / 1.08) * 0.4
        box(bm, 0.12, 0.52, y - 0.03, y + 0.03, z - 0.025, z + 0.025)
    return set()


def _chest_body(bm) -> set:
    """The chest's box and its iron bands; returns the top of the box (the inside, when open)."""
    faces = box(bm, -0.52, 0.52, -0.32, 0.32, 0.0, 0.46, mat=CHEST_WOOD)
    inside = set()
    for f in faces:
        f.normal_update()
        if f.normal.z > 0.9:
            inside.add(f)
    for x in (-0.34, 0.34):
        box(bm, x - 0.04, x + 0.04, -0.335, 0.335, 0.0, 0.47, mat=CHEST_IRON)
    box(bm, -0.535, 0.535, -0.335, 0.335, 0.0, 0.06, mat=CHEST_IRON)
    return inside


def _chest_lid(bm) -> list:
    """The lid (closed, on top of the body) with its bands and lock plate; returns its verts."""
    made = set()
    made |= box(bm, -0.54, 0.54, -0.34, 0.34, 0.46, 0.68, mat=CHEST_WOOD)
    for x in (-0.34, 0.34):
        made |= box(bm, x - 0.04, x + 0.04, -0.355, 0.355, 0.46, 0.7, mat=CHEST_IRON)
    made |= box(bm, -0.08, 0.08, -0.37, -0.33, 0.36, 0.56, mat=CHEST_GOLD)
    return list({v for f in made for v in f.verts})


def chest_closed(bm, rng: random.Random) -> set:
    """A locked wooden chest with iron bands and a gold lock plate (the lock catches the light)."""
    _chest_body(bm)
    _chest_lid(bm)
    return set()


def chest_open(bm, rng: random.Random) -> set:
    """The same chest, its lid thrown back on its hinge, gold glinting inside the dark box."""
    inside = _chest_body(bm)
    hinge = Vector((0.0, 0.34, 0.46))
    swing = Matrix.Translation(hinge) @ Matrix.Rotation(math.radians(-110.0), 4, "X") @ Matrix.Translation(-hinge)
    bmesh.ops.transform(bm, matrix=swing, verts=_chest_lid(bm))
    for (x, y, r) in ((-0.2, -0.05, 0.16), (0.12, 0.06, 0.2), (0.3, -0.1, 0.12)):
        part = lump(Vector((x, y, 0.42)), Vector((r, r * 0.8, r * 0.45)), 59, 2, rng, mat=CHEST_GOLD)
        merge(bm, part)
        part.free()
    return inside


PIECES = [
    Piece("stump_rotten", stump_rotten, 223, [Surface("bark", "bark.png"), Surface("rot", "hollow_floor.png")]),
    Piece("grave_cross", grave_cross, 233, [Surface("wood", "planks.png"), Surface("earth", "dirt_trail.png")], moss=0.5),
    Piece("fence", fence, 234, [Surface("wood", "planks.png")], moss=0.6),
    Piece("signpost", signpost, 235, [Surface("wood", "planks.png")], moss=0.4),
    Piece("cart", cart, 236, [Surface("wood", "planks.png"), Surface("stone", "cliff.png")], moss=0.6),
    Piece("log", log, 237, [Surface("bark", "bark.png"), Surface("rot", "hollow_floor.png")]),
    Piece("well", well, 238, [Surface("stone", "ruin_wall.png"), Surface("wood", "planks.png"),
                              Surface("thatch", "thatch.png")], moss=0.6),
    Piece("stilt_hut", stilt_hut, 239, [Surface("wood", "planks.png"), Surface("thatch", "thatch.png"),
                                        Surface("glass", "glass.png")], moss=0.5),
    Piece("chest_closed", chest_closed, 240, [Surface("wood", "planks.png"), Surface("iron", "iron.png"),
                                              Surface("gold", "gold.png")], moss=0.0),
    Piece("chest_open", chest_open, 241, [Surface("wood", "planks.png"), Surface("iron", "iron.png"),
                                          Surface("gold", "gold.png")], moss=0.0),
]
