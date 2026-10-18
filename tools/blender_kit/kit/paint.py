"""Vertex colours: the tint the game multiplies over a piece's pixel texture (DESIGN.md 5.6).

Linear colours (the game reads them as they are). Moss grows in patches on faces that look up, the
foot darkens where the piece meets the ground, chosen faces (a stump's hollow) go dark.
"""
from __future__ import annotations

import bmesh
from mathutils import Vector, noise

MOSS = (0.50, 0.70, 0.30)
# Faces looking up more than this (normal z) start to take moss; fully mossy when flat.
MOSS_UP = 0.55
# Moss grows in patches: noise above this (-1..1) keeps it.
MOSS_PATCH = -0.25
# The foot is this dark at the ground and fades to no tint FOOT_HEIGHT metres up.
FOOT = 0.55
FOOT_HEIGHT = 0.6
DARK = 0.35

LAYER = "Col"


def paint(bm: bmesh.types.BMesh, seed: int, dark: set | None = None, moss: float = 1.0) -> None:
    """Writes the piece's vertex colours. `dark` faces get DARK; `moss` 0 turns moss off."""
    layer = bm.loops.layers.float_color.new(LAYER)
    shift = Vector((seed * 0.71, seed * 0.29, seed * 0.43))
    dark = dark or set()
    for f in bm.faces:
        up = f.normal.z
        for loop in f.loops:
            co = loop.vert.co
            if f in dark:
                c = [DARK] * 3
            else:
                foot = FOOT + (1.0 - FOOT) * min(1.0, max(0.0, co.z / FOOT_HEIGHT))
                c = [foot] * 3
                if moss > 0.0 and up > MOSS_UP and noise.noise(co * 2.2 + shift) > MOSS_PATCH:
                    t = min(1.0, (up - MOSS_UP) / (1.0 - MOSS_UP) * 1.6) * moss
                    c = [c[i] * (1.0 + (MOSS[i] - 1.0) * t) for i in range(3)]
            loop[layer] = (c[0], c[1], c[2], 1.0)
