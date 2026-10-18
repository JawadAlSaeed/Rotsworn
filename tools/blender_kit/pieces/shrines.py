"""Shrines, rot seals, the gate and the fountain (card #226). Their glowing parts (blood, gold,
holy water, eyes, runes, rot) are surfaces of their own, so the game can light them and dim a
shrine once it is used."""
from __future__ import annotations

import math
import random

from mathutils import Matrix, Vector

from kit.parts import box, lathe, lump, merge, tube
from kit.piece import Piece, Surface

BLOOD_RED = (1.0, 0.3, 0.25)
WAR_AMBER = (1.0, 0.7, 0.3)
PLENTY_GOLD = (1.0, 0.85, 0.4)
SPRING_CYAN = (0.35, 1.0, 0.85)
SEAL_GREEN = (0.55, 1.0, 0.45)


def _gem(bm, at: Vector, r: float, mat: int) -> None:
    """A small faceted knob (a glowing nodule): two five-sided cones base to base."""
    lathe(bm, [(at.z - r, 0.02), (at.z, r), (at.z + r, 0.02)], 5, mat=mat, cap_bottom=True,
          matrix=Matrix.Translation((at.x, at.y, 0.0)))


def shrine_altar(bm, rng: random.Random) -> set:
    """The blood altar: a squat stone block with bone horns rising from its corners and a red
    cloth laid over it and hanging down the front, wet with blood (it glows)."""
    STONE, BONE, CLOTH = 0, 1, 2
    box(bm, -0.58, 0.58, -0.36, 0.36, 0.0, 0.72, mat=STONE)
    box(bm, -0.66, 0.66, -0.42, 0.42, 0.72, 0.84, mat=STONE)
    for side in (-1.0, 1.0):
        tube(bm, [Vector((side * 0.54, 0.0, 0.8)), Vector((side * 0.7, 0.0, 1.02)), Vector((side * 0.64, -0.02, 1.24))],
             [0.07, 0.05, 0.02], 5, mat=BONE)
    box(bm, -0.26, 0.26, -0.44, 0.44, 0.84, 0.865, mat=CLOTH)
    box(bm, -0.26, 0.26, -0.455, -0.43, 0.3, 0.865, mat=CLOTH)
    part = lump(Vector((0.4, -0.5, 0.05)), Vector((0.1, 0.11, 0.09)), 83, 1, rng, mat=BONE)  # a skull's worth
    merge(bm, part)
    part.free()
    return set()


def shrine_idol(bm, rng: random.Random) -> set:
    """The war idol: a carved wooden post bound in iron, a squared head with glowing eyes and two
    long horns."""
    WOOD, IRON, BONE, EYES = 0, 1, 2, 3
    lathe(bm, [(0.0, 0.25), (0.15, 0.22), (1.45, 0.19)], 8, mat=WOOD)
    for z in (0.45, 1.0):
        lathe(bm, [(z, 0.215), (z + 0.07, 0.215)], 8, mat=IRON, cap_top=False)
    box(bm, -0.22, 0.22, -0.2, 0.2, 1.42, 1.86, mat=WOOD)
    box(bm, -0.24, 0.24, -0.22, 0.22, 1.42, 1.48, mat=IRON)
    for x in (-0.09, 0.09):
        box(bm, x - 0.045, x + 0.045, -0.215, -0.19, 1.66, 1.72, mat=EYES)
    for side in (-1.0, 1.0):
        tube(bm, [Vector((side * 0.2, 0.0, 1.78)), Vector((side * 0.4, 0.0, 1.9)), Vector((side * 0.46, 0.0, 2.1)),
                  Vector((side * 0.4, 0.0, 2.24))], [0.07, 0.055, 0.035, 0.015], 5, mat=BONE)
    return set()


def shrine_plenty(bm, rng: random.Random) -> set:
    """The shrine of plenty: a stone chalice on a stepped foot, heaped with glowing gold."""
    STONE, GOLD = 0, 1
    lathe(bm, [(0.0, 0.34), (0.12, 0.32), (0.2, 0.17), (0.72, 0.13), (0.8, 0.24), (0.94, 0.44), (1.0, 0.46)], 10,
          mat=STONE)
    part = lump(Vector((0.0, 0.0, 0.98)), Vector((0.36, 0.3, 0.17)), 89, 2, rng, mat=GOLD)
    merge(bm, part)
    part.free()
    for (x, y) in ((0.42, -0.36), (-0.35, -0.42)):  # coins spilled at its foot
        lathe(bm, [(0.0, 0.06), (0.02, 0.06)], 6, mat=GOLD, matrix=Matrix.Translation((x, y, 0.0)))
    return set()


def shrine_spring(bm, rng: random.Random) -> set:
    """The healing spring: a round stone basin of glowing water, a slim obelisk standing in it
    with a thread of the same water running down its face."""
    STONE, WATER = 0, 1
    faces = lathe(bm, [(0.0, 0.76), (0.34, 0.73), (0.42, 0.62)], 12, mat=STONE)
    for f in faces:
        f.normal_update()
        if f.normal.z > 0.9:
            f.material_index = WATER
    lathe(bm, [(0.36, 0.17), (1.5, 0.11), (1.68, 0.02)], 4, mat=STONE, matrix=Matrix.Rotation(math.radians(45.0), 4, "Z"))
    box(bm, -0.025, 0.025, -0.13, -0.09, 0.42, 1.42, mat=WATER)
    return set()


def seal_stone(bm, rng: random.Random) -> set:
    """A rot seal: a dark standing stone with a rune cut into its face that glows sickly green."""
    STONE, RUNE = 0, 1
    lathe(bm, [(0.0, 0.33), (0.85, 0.28), (1.2, 0.21), (1.36, 0.05)], 7, mat=STONE, wobble=0.06, seed=3,
          matrix=Matrix.Diagonal((1.0, 0.62, 1.0, 1.0)))
    y = -0.19
    for (x0, x1, z0, z1) in ((-0.03, 0.03, 0.42, 1.08), (-0.2, 0.2, 0.86, 0.91), (-0.15, 0.15, 0.58, 0.63)):
        box(bm, x0, x1, y - 0.02, y + 0.01, z0, z1, mat=RUNE)
    for side in (-1.0, 1.0):  # the rune's two hooks
        box(bm, side * 0.12, side * 0.17, y - 0.02, y + 0.01, 0.98, 1.08, mat=RUNE)
    return set()


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


def rot_gate(bm, rng: random.Random) -> set:
    """The rot gate: a wall of twisted roots 30 m long across the way out, 1.2 m thick and 2.6 m
    tall, studded with glowing rot (it sinks into the ground when enough seals are taken)."""
    ROOT, ROT = 0, 1
    length, steps = 30.0, 14
    for k, (z, r) in enumerate(((0.35, 0.36), (0.95, 0.32), (1.55, 0.3), (2.2, 0.26))):
        path, radii = [], []
        for i in range(steps + 1):
            t = i / steps
            path.append(Vector((math.sin(t * 9.0 + k * 1.7) * 0.22, -length * 0.5 + t * length,
                                z + math.sin(t * 13.0 + k) * 0.2)))
            radii.append(r * (0.85 + 0.3 * rng.random()))
        tube(bm, path, radii, 5, mat=ROOT)
    for i in range(12):
        y = -length * 0.5 + (i + 0.5) * length / 12 + rng.uniform(-0.6, 0.6)
        x = rng.uniform(-0.2, 0.2)
        tube(bm, [Vector((x, y, -0.05)), Vector((x + 0.1, y + 0.2, 1.2)), Vector((x - 0.05, y - 0.1, 2.45)),
                  Vector((x, y, 2.6))], [0.18, 0.15, 0.12, 0.04], 5, mat=ROOT)
    for i in range(16):
        y = -length * 0.5 + (i + 0.5) * length / 16 + rng.uniform(-0.5, 0.5)
        _gem(bm, Vector((rng.choice((-0.42, 0.42)), y, rng.uniform(0.4, 2.2))), rng.uniform(0.09, 0.14), ROT)
    return set()


PIECES = [
    Piece("shrine_altar", shrine_altar, 246, [Surface("stone", "cliff.png"), Surface("bone", "bone.png"),
                                              Surface("blood", "cloth_red.png", glow=0.8, glow_color=BLOOD_RED)],
          moss=0.3),
    Piece("shrine_idol", shrine_idol, 247, [Surface("wood", "bark.png"), Surface("iron", "iron.png"),
                                            Surface("bone", "bone.png"),
                                            Surface("eyes", "glow_pale.png", glow=2.4, glow_color=WAR_AMBER)], moss=0.3),
    Piece("shrine_plenty", shrine_plenty, 248, [Surface("stone", "stone_dressed.png"),
                                                Surface("gold", "gold.png", glow=1.2, glow_color=PLENTY_GOLD)],
          moss=0.5),
    Piece("shrine_spring", shrine_spring, 249, [Surface("stone", "stone_dressed.png"),
                                                Surface("water", "glow_pale.png", glow=1.6, glow_color=SPRING_CYAN)],
          moss=0.6),
    Piece("seal_stone", seal_stone, 250, [Surface("stone", "cliff.png"),
                                          Surface("rune", "glow_pale.png", glow=2.2, glow_color=SEAL_GREEN)], moss=0.4),
    Piece("fountain", fountain, 251, [Surface("stone", "stone_dressed.png")], moss=0.7),
    Piece("rot_gate", rot_gate, 252, [Surface("root", "rot_gate.png", world_size=2.4),
                                      Surface("rot", "glow_pale.png", glow=2.0, glow_color=SEAL_GREEN)], moss=0.0),
]
