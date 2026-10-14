"""Signed distance shapes: the 3D building blocks every model is made of.

A model is a tree of nodes. Leaves (Prim subclasses) are simple shapes with a material; inner
nodes combine them (union, smooth union, subtract, intersect). `eval(P)` returns, for points
P (N, 3), the distance to the surface and which leaf is nearest (its `part` id), so the renderer
knows both where the surface is and what it is made of.

Units: model units, usually "one unit = one sprite pixel" (see render.Camera.scale).
Axes: x forward (the way a character faces), y up, z toward the camera's side.
"""
from __future__ import annotations

import math
from typing import Callable, Sequence

import numpy as np

from .noise import fbm3
from .palette import Material

Vec = Sequence[float]


def rot(rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> np.ndarray:
    """Rotation matrix from Euler degrees, applied z first, then x, then y (R @ v)."""
    ax, ay, az = (math.radians(a) for a in (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Ry @ Rx @ Rz


def basis(forward: Vec, up: Vec = (0.0, 1.0, 0.0)) -> np.ndarray:
    """Rotation whose local x points along `forward` and local y as close to `up` as possible."""
    f = np.asarray(forward, dtype=float)
    f = f / (np.linalg.norm(f) + 1e-9)
    u = np.asarray(up, dtype=float)
    u = u - f * np.dot(u, f)
    if np.linalg.norm(u) < 1e-6:
        u = np.array([0.0, 0.0, 1.0]) - f * f[2]
    u = u / (np.linalg.norm(u) + 1e-9)
    s = np.cross(f, u)
    return np.stack([f, u, s], axis=1)


class Node:
    def eval(self, P: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        raise NotImplementedError

    def leaves(self) -> list["Prim"]:
        raise NotImplementedError


class Prim(Node):
    """A shape with a material. `pos` / `R` place it (R = local axes as columns).

    `group`: parts in the same group never get contour lines between them (one body).
    `thin`: kept even when it covers less than half a pixel (straps, horns, fingers).
    `bumps`: (amplitude, frequency, seed) noise added to the surface (rock, rot, bark).
    """

    part: int = -1

    def __init__(self, mat: Material, pos: Vec = (0, 0, 0), R: np.ndarray | None = None,
                 group: str = "", thin: bool = False,
                 bumps: tuple[float, float, int] | None = None, name: str = "") -> None:
        self.mat = mat
        self.pos = np.asarray(pos, dtype=float)
        self.R = np.eye(3) if R is None else np.asarray(R, dtype=float)
        self.group = group or name or mat.name
        self.thin = thin
        self.bumps = bumps
        self.name = name

    def local(self, P: np.ndarray) -> np.ndarray:
        return (P - self.pos) @ self.R

    def dist_local(self, Q: np.ndarray) -> np.ndarray:
        raise NotImplementedError

    def eval(self, P: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        d = self.dist_local(self.local(P))
        if self.bumps is not None:
            amp, freq, seed = self.bumps
            d = d + amp * fbm3(P * freq, seed, octaves=2)
        return d, np.full(P.shape[0], self.part, dtype=np.int32)

    def leaves(self) -> list["Prim"]:
        return [self]


class Sphere(Prim):
    def __init__(self, mat: Material, pos: Vec, r: float, **kw) -> None:
        super().__init__(mat, pos, **kw)
        self.r = r

    def dist_local(self, Q):
        return np.linalg.norm(Q, axis=1) - self.r


class Ellipsoid(Prim):
    def __init__(self, mat: Material, pos: Vec, radii: Vec, R: np.ndarray | None = None, **kw) -> None:
        super().__init__(mat, pos, R, **kw)
        self.radii = np.asarray(radii, dtype=float)

    def dist_local(self, Q):
        k0 = np.linalg.norm(Q / self.radii, axis=1)
        k1 = np.linalg.norm(Q / (self.radii * self.radii), axis=1)
        return np.where(k1 > 1e-9, k0 * (k0 - 1.0) / np.maximum(k1, 1e-9), -self.radii.min())


class Box(Prim):
    """Box with half sizes `half`, corners rounded by `round` (inside the half sizes)."""

    def __init__(self, mat: Material, pos: Vec, half: Vec, R: np.ndarray | None = None,
                 round: float = 0.0, **kw) -> None:
        super().__init__(mat, pos, R, **kw)
        self.half = np.asarray(half, dtype=float)
        self.round = round

    def dist_local(self, Q):
        q = np.abs(Q) - (self.half - self.round)
        outside = np.linalg.norm(np.maximum(q, 0.0), axis=1)
        inside = np.minimum(np.max(q, axis=1), 0.0)
        return outside + inside - self.round


class RoundCone(Prim):
    """A capsule that may taper: sphere radius ra at a to rb at b (world points)."""

    def __init__(self, mat: Material, a: Vec, b: Vec, ra: float, rb: float | None = None, **kw) -> None:
        super().__init__(mat, (0, 0, 0), **kw)
        self.a = np.asarray(a, dtype=float)
        self.b = np.asarray(b, dtype=float)
        self.ra = ra
        self.rb = ra if rb is None else rb

    def local(self, P):
        return P

    def dist_local(self, P):
        a, b, r1, r2 = self.a, self.b, self.ra, self.rb
        ba = b - a
        l2 = float(np.dot(ba, ba))
        if l2 < 1e-9:
            return np.linalg.norm(P - a, axis=1) - max(r1, r2)
        rr = r1 - r2
        a2 = l2 - rr * rr
        il2 = 1.0 / l2
        pa = P - a
        y = pa @ ba
        z = y - l2
        x2v = pa * l2 - y[:, None] * ba
        x2 = np.sum(x2v * x2v, axis=1)
        y2 = y * y * l2
        z2 = z * z * l2
        k = math.copysign(1.0, rr) * rr * rr * x2
        res = (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1
        res = np.where(np.sign(z) * a2 * z2 > k, np.sqrt(x2 + z2) * il2 - r2, res)
        res = np.where(np.sign(y) * a2 * y2 < k, np.sqrt(x2 + y2) * il2 - r1, res)
        return res


def Capsule(mat: Material, a: Vec, b: Vec, r: float, **kw) -> RoundCone:
    return RoundCone(mat, a, b, r, r, **kw)


class Cylinder(Prim):
    """Upright cylinder along local y: radius r, half height h, edges rounded by `round`."""

    def __init__(self, mat: Material, pos: Vec, r: float, h: float, R: np.ndarray | None = None,
                 round: float = 0.0, **kw) -> None:
        super().__init__(mat, pos, R, **kw)
        self.r = r
        self.h = h
        self.round = round

    def dist_local(self, Q):
        dx = np.hypot(Q[:, 0], Q[:, 2]) - (self.r - self.round)
        dy = np.abs(Q[:, 1]) - (self.h - self.round)
        outside = np.hypot(np.maximum(dx, 0), np.maximum(dy, 0))
        return outside + np.minimum(np.maximum(dx, dy), 0.0) - self.round


class Torus(Prim):
    """Ring in the local xz plane: major radius R0, tube radius r."""

    def __init__(self, mat: Material, pos: Vec, R0: float, r: float, R: np.ndarray | None = None, **kw) -> None:
        super().__init__(mat, pos, R, **kw)
        self.R0 = R0
        self.r = r

    def dist_local(self, Q):
        q = np.hypot(Q[:, 0], Q[:, 2]) - self.R0
        return np.hypot(q, Q[:, 1]) - self.r


class Prism(Prim):
    """A 2D polygon (local x, y; any simple shape) extruded along local z by half depth `hz`,
    edges rounded by `round`. Good for shields, blades, capes, leaves, crowns."""

    def __init__(self, mat: Material, pos: Vec, poly: Sequence[Vec], hz: float,
                 R: np.ndarray | None = None, round: float = 0.0, **kw) -> None:
        super().__init__(mat, pos, R, **kw)
        self.poly = np.asarray(poly, dtype=float)
        self.hz = hz
        self.round = round

    def _poly2d(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        v = self.poly
        n = len(v)
        d = (x - v[0, 0]) ** 2 + (y - v[0, 1]) ** 2
        s = np.ones_like(x)
        j = n - 1
        for i in range(n):
            ex, ey = v[j, 0] - v[i, 0], v[j, 1] - v[i, 1]
            wx, wy = x - v[i, 0], y - v[i, 1]
            t = np.clip((wx * ex + wy * ey) / (ex * ex + ey * ey + 1e-12), 0.0, 1.0)
            bx, by = wx - ex * t, wy - ey * t
            d = np.minimum(d, bx * bx + by * by)
            c1 = y >= v[i, 1]
            c2 = y < v[j, 1]
            c3 = ex * wy > ey * wx
            flip = (c1 & c2 & c3) | (~c1 & ~c2 & ~c3)
            s = np.where(flip, -s, s)
            j = i
        return s * np.sqrt(d)

    def dist_local(self, Q):
        d2 = self._poly2d(Q[:, 0], Q[:, 1]) + self.round
        dz = np.abs(Q[:, 2]) - (self.hz - self.round)
        outside = np.hypot(np.maximum(d2, 0), np.maximum(dz, 0))
        return outside + np.minimum(np.maximum(d2, dz), 0.0) - self.round


class Custom(Prim):
    """Any distance function of local points: fn(Q) -> (N,)."""

    def __init__(self, mat: Material, fn: Callable[[np.ndarray], np.ndarray], pos: Vec = (0, 0, 0),
                 R: np.ndarray | None = None, **kw) -> None:
        super().__init__(mat, pos, R, **kw)
        self.fn = fn

    def dist_local(self, Q):
        return self.fn(Q)


# --- Combining ----------------------------------------------------------------------------------


class Union(Node):
    def __init__(self, *children: Node) -> None:
        self.children: list[Node] = [c for c in children if c is not None]

    def add(self, *nodes: Node) -> "Union":
        self.children.extend(n for n in nodes if n is not None)
        return self

    def eval(self, P):
        if not self.children:
            return np.full(P.shape[0], 1e9), np.full(P.shape[0], -1, dtype=np.int32)
        best_d, best_p = self.children[0].eval(P)
        for c in self.children[1:]:
            d, p = c.eval(P)
            closer = d < best_d
            best_d = np.where(closer, d, best_d)
            best_p = np.where(closer, p, best_p)
        return best_d, best_p

    def leaves(self):
        out: list[Prim] = []
        for c in self.children:
            out.extend(c.leaves())
        return out


class SmoothUnion(Union):
    """Blends children into one soft shape (flesh, roots, blobs). k = blend width in units."""

    def __init__(self, *children: Node, k: float = 1.5) -> None:
        super().__init__(*children)
        self.k = k

    def eval(self, P):
        if not self.children:
            return super().eval(P)
        best_d, best_p = self.children[0].eval(P)
        acc = best_d
        for c in self.children[1:]:
            d, p = c.eval(P)
            h = np.clip(0.5 + 0.5 * (d - acc) / self.k, 0.0, 1.0)
            acc = d * (1 - h) + acc * h - self.k * h * (1 - h)
            closer = d < best_d
            best_d = np.where(closer, d, best_d)
            best_p = np.where(closer, p, best_p)
        return acc, best_p


class Subtract(Node):
    """`a` with `b` carved out (k > 0 rounds the cut edge). The cut takes a's material, or
    `b`'s if `b_material` is True (a hole lined with something)."""

    def __init__(self, a: Node, b: Node, k: float = 0.0, b_material: bool = False) -> None:
        self.a = a
        self.b = b
        self.k = k
        self.b_material = b_material

    def eval(self, P):
        da, pa = self.a.eval(P)
        db, pb = self.b.eval(P)
        if self.k > 0:
            h = np.clip(0.5 - 0.5 * (da + db) / self.k, 0.0, 1.0)
            d = da * (1 - h) + (-db) * h + self.k * h * (1 - h)
        else:
            d = np.maximum(da, -db)
        if self.b_material:
            return d, np.where(-db > da, pb, pa)
        return d, pa

    def leaves(self):
        return self.a.leaves() + (self.b.leaves() if self.b_material else [])


class Intersect(Node):
    def __init__(self, a: Node, b: Node) -> None:
        self.a = a
        self.b = b

    def eval(self, P):
        da, pa = self.a.eval(P)
        db, _ = self.b.eval(P)
        return np.maximum(da, db), pa

    def leaves(self):
        return self.a.leaves()


class Moved(Node):
    """Moves / rotates a whole subtree (for props placed as a unit, swaying, mirrored copies)."""

    def __init__(self, child: Node, pos: Vec = (0, 0, 0), R: np.ndarray | None = None) -> None:
        self.child = child
        self.pos = np.asarray(pos, dtype=float)
        self.R = np.eye(3) if R is None else np.asarray(R, dtype=float)

    def eval(self, P):
        return self.child.eval((P - self.pos) @ self.R)

    def leaves(self):
        return self.child.leaves()
