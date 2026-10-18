"""Shapes every piece builds from: boxes, tubes, rocks, plane cuts, brick courses, planks.

Blender axes: z up, the front of a piece faces -y (the game camera's side). Every function takes
`mat`, the surface its faces belong to (an index into the piece's surfaces), so one piece can wear
several textures (stone and wood, bark and rot).
"""
from __future__ import annotations

import math
import random
from typing import Callable

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

BMesh = bmesh.types.BMesh


def _tag(bm: BMesh, before: set, mat: int) -> set:
    """Puts the faces made since `before` on surface `mat`; returns them."""
    made = set(bm.faces) - before
    for f in made:
        f.material_index = mat
    return made


def box(bm: BMesh, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float,
        turn: Matrix | None = None, mat: int = 0) -> set:
    """An axis-aligned box from corner to corner, then turned about its own centre."""
    before = set(bm.faces)
    centre = Vector(((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5))
    scale = Matrix.Diagonal((x1 - x0, y1 - y0, z1 - z0, 1.0))
    spin = turn if turn is not None else Matrix.Identity(4)
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(centre) @ spin @ scale)
    return _tag(bm, before, mat)


def merge(into: BMesh, part: BMesh) -> None:
    """Appends one bmesh's geometry (with its surfaces) to another, so cuts made on `part` never
    touch the rest."""
    mesh = bpy.data.meshes.new("_part")
    part.to_mesh(mesh)
    into.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)


def cut(bm: BMesh, co: Vector, no: Vector, fill: bool = True, mat: int | None = None) -> None:
    """Slices away everything on the side `no` points to, closing the hole with a flat face (on
    surface `mat`, or the surface the cut faces had)."""
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_outer=True)
    if not fill:
        return
    border = [e for e in bm.edges if e.is_boundary]
    near = border[0].link_faces[0].material_index if border and border[0].link_faces else 0
    before = set(bm.faces)
    bmesh.ops.holes_fill(bm, edges=border, sides=0)
    _tag(bm, before, near if mat is None else mat)


def tube(bm: BMesh, path: list[Vector], radii: list[float], sides: int, mat: int = 0) -> set:
    """A tube along `path` with a ring of `sides` corners of radius radii[i] at each point, closed
    at its end (its start is meant to sit inside something)."""
    before = set(bm.faces)
    rings = []
    for i, p in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        u = t.cross(Vector((0.0, 0.0, 1.0)))
        u = u.normalized() if u.length > 1e-4 else Vector((1.0, 0.0, 0.0))
        v = t.cross(u)  # (u, v, t) right-handed, so the faces below face outward
        rings.append([bm.verts.new(p + (u * math.cos(k * math.tau / sides) + v * math.sin(k * math.tau / sides))
                                   * radii[i]) for k in range(sides)])
    for lo, hi in zip(rings, rings[1:]):
        for k in range(sides):
            j = (k + 1) % sides
            bm.faces.new((lo[k], lo[j], hi[j], hi[k]))
    tip = bm.verts.new(path[-1] + (path[-1] - path[-2]).normalized() * radii[-1])
    for k in range(sides):
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % sides], tip))
    return _tag(bm, before, mat)


def lump(centre: Vector, radii: Vector, seed: int, cuts: int, rng: random.Random, mat: int = 0) -> BMesh:
    """A rock in its own bmesh: a noisy squashed ball with a few flat facets sliced off it. Merge
    it into the piece with `merge`."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    shift = Vector((seed * 1.31, seed * 0.57, seed * 0.93))
    for v in bm.verts:
        n = v.co.normalized()
        d = 1.0 + 0.17 * noise.noise(n * 1.6 + shift)
        v.co = Vector((n.x * radii.x, n.y * radii.y, n.z * radii.z)) * d + centre
    for _ in range(cuts):
        a = rng.uniform(0.0, math.tau)
        up = rng.uniform(-0.15, 0.85)
        no = Vector((math.cos(a) * math.sqrt(1 - up * up), math.sin(a) * math.sqrt(1 - up * up), up))
        reach = Vector((no.x * radii.x, no.y * radii.y, no.z * radii.z)).length
        cut(bm, centre + no * reach * rng.uniform(0.72, 0.86), no)
    # The fills come out facing either way; the lump is closed, so outward is well defined.
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.material_index = mat
    return bm


def brick_courses(bm: BMesh, rng: random.Random, width: float, depth: float, courses: int,
                  top: Callable[[float], float], course: float = 0.4, brick: float = 0.5,
                  loose: bool = True, recess: float = 0.1, mat: int = 0) -> None:
    """A brick wall along x (centred), `depth` thick, built course by course up to the height
    `top(x)`: its broken top steps like real brickwork, the top brick of each column sits a
    little loose and turned, a few bricks are knocked back into the wall, and no brick floats
    over a gap. Courses of 0.4 m match ruin_wall.png at a texture world size of 1.6."""
    rows: list[list[tuple[float, float, bool]]] = []
    for c in range(courses):
        row = []
        x = -width * 0.5 - (brick * 0.5 if c % 2 else 0.0)
        while x < width * 0.5 - 1e-6:
            bx0, bx1 = max(x, -width * 0.5), min(x + brick, width * 0.5)
            if bx1 - bx0 > 0.05:
                kept = c == 0 or top((bx0 + bx1) * 0.5) + rng.uniform(-0.15, 0.15) >= (c + 1) * course
                kept = kept and (c == 0 or any(k and b0 < bx1 - 0.01 and b1 > bx0 + 0.01
                                               for (b0, b1, k) in rows[c - 1]))
                row.append((bx0, bx1, kept))
            x += brick
        rows.append(row)

    def covered(c: int, x0: float, x1: float) -> bool:
        return c < courses and any(k and b0 < x1 - 0.01 and b1 > x0 + 0.01 for (b0, b1, k) in rows[c])

    for c, row in enumerate(rows):
        z0, z1 = c * course, (c + 1) * course
        run: list[float] = []

        def flush() -> None:
            if run:
                # Each run of bricks sits a hair in or out, so the face is not one flat plane.
                lean = rng.uniform(-0.025, 0.025)
                box(bm, run[0], run[1], -depth * 0.5 + lean, depth * 0.5 + lean, z0, z1, mat=mat)
                run.clear()

        for (x0, x1, kept) in row:
            if not kept:
                flush()
                continue
            is_loose = loose and not covered(c + 1, x0, x1) and c > 0
            knocked = (not is_loose and 0 < c < courses - 1 and covered(c + 1, x0, x1)
                       and rng.random() < recess)
            if is_loose:
                flush()
                turn = Matrix.Rotation(math.radians(rng.uniform(-5.0, 5.0)), 4, "Z")
                dy = rng.uniform(-0.04, 0.04)
                box(bm, x0 + 0.02, x1 - 0.02, -depth * 0.5 + 0.02 + dy, depth * 0.5 - 0.02 + dy, z0,
                    z1 - rng.uniform(0.0, 0.04), turn, mat=mat)
            elif knocked:
                flush()
                box(bm, x0, x1, -depth * 0.5 + 0.16, depth * 0.5, z0, z1, mat=mat)
            elif run:
                run[1] = x1
            else:
                run.extend((x0, x1))
        flush()


def profile(points: list[tuple[float, float]]) -> Callable[[float], float]:
    """A height along x through `points` (x, height), straight between them."""
    def at(x: float) -> float:
        for (xa, ha), (xb, hb) in zip(points, points[1:]):
            if xa <= x <= xb:
                return ha + (hb - ha) * (x - xa) / (xb - xa)
        return points[-1][1] if x > points[-1][0] else points[0][1]
    return at


def loose_bricks(bm: BMesh, spots: list[tuple[float, float, float, float]], size=(0.44, 0.22, 0.19),
                 mat: int = 0) -> None:
    """Fallen bricks lying on the ground: (x, y, yaw degrees, tilt degrees) each."""
    for (x, y, yaw, tilt) in spots:
        turn = Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(tilt), 4, "X")
        box(bm, x - size[0] * 0.5, x + size[0] * 0.5, y - size[1] * 0.5, y + size[1] * 0.5, 0.0, size[2],
            turn, mat=mat)


def lathe(bm: BMesh, rings: list[tuple], sides: int, mat: int = 0, cap_top: bool = True,
          cap_bottom: bool = False, flute: float = 0.0, wobble: float = 0.0, seed: int = 0,
          matrix: Matrix | None = None) -> set:
    """A turned solid around the z axis: `rings` are (z, radius) from the bottom up, or
    (z, radius, lifts) with one z offset per corner (a broken top). `flute` pulls every other
    corner in by that share (a fluted column), `wobble` roughens the radius with noise. The top
    closes in a fan to its middle (it may be jagged); then everything moves by `matrix`."""
    before = set(bm.faces)
    made = []
    rows = []
    for ring in rings:
        z, r = ring[0], ring[1]
        lifts = ring[2] if len(ring) > 2 else None
        row = []
        for k in range(sides):
            a = k * math.tau / sides
            rr = r * (1.0 - flute * (k % 2))
            if wobble:
                rr *= 1.0 + wobble * noise.noise(Vector((math.cos(a) * 2.0, math.sin(a) * 2.0, z * 3.0 + seed)))
            row.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z + (lifts[k] if lifts else 0.0))))
        rows.append(row)
        made.extend(row)
    for lo, hi in zip(rows, rows[1:]):
        for k in range(sides):
            j = (k + 1) % sides
            bm.faces.new((lo[k], lo[j], hi[j], hi[k]))
    if cap_top:
        top_row = rows[-1]
        mid = sum((v.co for v in top_row), Vector()) / sides
        centre = bm.verts.new(mid)
        made.append(centre)
        for k in range(sides):
            bm.faces.new((top_row[k], top_row[(k + 1) % sides], centre))
    if cap_bottom:
        bm.faces.new(list(reversed(rows[0])))
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=made)
    return _tag(bm, before, mat)


def prism(bm: BMesh, outline: list[tuple[float, float]], y0: float, y1: float, mat: int = 0,
          matrix: Matrix | None = None) -> set:
    """A slab: the convex `outline` (x, z points, either order) pushed through from y0 to y1, then
    moved by `matrix`. Used for arch stones, gravestones, steps."""
    before = set(bm.faces)
    front = [bm.verts.new((x, y0, z)) for (x, z) in outline]
    back = [bm.verts.new((x, y1, z)) for (x, z) in outline]
    n = len(outline)
    faces = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
    for k in range(n):
        j = (k + 1) % n
        faces.append(bm.faces.new((front[k], back[k], back[j], front[j])))
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=front + back)
    return _tag(bm, before, mat)


def plank(bm: BMesh, a: Vector, b: Vector, width: float, thick: float, up: Vector | None = None,
          mat: int = 0) -> set:
    """A board from point a to point b (its middle line), `width` across and `thick` deep; `up`
    is the board's face direction (default: as flat as it can lie)."""
    along = (b - a)
    length = along.length
    x = along.normalized()
    up = (up or Vector((0.0, 0.0, 1.0))).normalized()
    y = up.cross(x)
    y = y.normalized() if y.length > 1e-4 else Vector((0.0, 1.0, 0.0))
    z = x.cross(y)
    frame = Matrix((x, y, z)).transposed().to_4x4()
    centre = (a + b) * 0.5
    before = set(bm.faces)
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(centre) @ frame
                          @ Matrix.Diagonal((length, width, thick, 1.0)))
    return _tag(bm, before, mat)
