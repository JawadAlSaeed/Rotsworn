"""Turns an SDF model into crisp pixel art.

Each pixel shoots a few straight rays (orthographic camera, 3x3 per pixel by default). A pixel is
solid when at least half its rays hit, takes the material most of them hit, and gets one colour
from that material's ramp, picked from the light at that spot (direct light, a soft ambient,
ambient occlusion in creases and a specular glint on metal). No blending, no anti-aliasing: every
pixel is a palette colour, like hand-made pixel art.

The result is a `Frame`: per-pixel part id, ramp index and depth. Overlays (thin lines, stamps)
and the post passes in post.py work on that, and `Frame.rgba()` turns it into colours at the end.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Sequence

import numpy as np

from .palette import Material
from .sdf import Node, Prim, rot

# Light in view space (x right, y up, z toward the viewer): from the upper left, a bit in front.
DEFAULT_LIGHT = (-0.6, 0.7, 0.4)
BAYER2 = np.array([[0.125, 0.625], [0.875, 0.375]])


@dataclass
class Camera:
    """Orthographic camera. `scale` = model units per pixel. (cx, cy) = the view point at the
    centre of the bottom pixel row; by default a model standing on y = 0 (a character's feet)
    fills up to the second-to-last row, so the outline fits in the last one. yaw turns the
    model's front (+x) toward the viewer (negative = 3/4 view of a right-facing model); pitch
    tilts the camera down.

    face="left" draws the same right-facing model facing left (enemies): it is mirrored, so its
    near side (+z) still faces the viewer and the light still comes from the upper left."""

    W: int
    H: int
    scale: float = 1.0
    yaw: float = -28.0
    pitch: float = 10.0
    cx: float = 0.0
    cy: float = -0.5
    face: str = "right"
    R: np.ndarray = field(init=False)

    def __post_init__(self) -> None:
        if self.face == "left":
            self.R = rot(self.pitch, 0.0, 0.0) @ rot(0.0, 180.0 - self.yaw, 0.0) @ np.diag([1.0, 1.0, -1.0])
        else:
            self.R = rot(self.pitch, 0.0, 0.0) @ rot(0.0, self.yaw, 0.0)
        self.z0 = max(self.W, self.H) * self.scale * 2.0

    def view(self, p: Sequence[float]) -> np.ndarray:
        return self.R @ np.asarray(p, dtype=float)

    def project(self, p: Sequence[float]) -> tuple[float, float, float]:
        """Model point -> (pixel x, pixel y, depth). Depth grows away from the viewer."""
        v = self.view(p)
        px = (v[0] - self.cx) / self.scale + self.W / 2.0
        py = self.H - 0.5 - (v[1] - self.cy) / self.scale
        return px, py, self.z0 - v[2]

    def rays(self, ss: int) -> tuple[np.ndarray, np.ndarray]:
        """Ray origins (H*W*ss*ss, 3) in model space and the shared direction."""
        offs = (np.arange(ss) + 0.5) / ss
        xs = (np.arange(self.W)[:, None] + offs[None, :]).reshape(-1)  # W*ss
        ys = (np.arange(self.H)[:, None] + offs[None, :]).reshape(-1)  # H*ss
        gy, gx = np.meshgrid(ys, xs, indexing="ij")  # (H*ss, W*ss)
        vx = (gx - self.W / 2.0) * self.scale + self.cx
        # The centre of the bottom row (H - 1) sits at view y = cy (matches project()).
        vy = (self.H - gy) * self.scale + self.cy - 0.5 * self.scale
        V = np.stack([vx.ravel(), vy.ravel(), np.full(vx.size, self.z0)], axis=1)
        O = V @ self.R  # R^T applied to row vectors
        D = np.array([0.0, 0.0, -1.0]) @ self.R
        return O, D


class Frame:
    """One rendered image as palette references (see module doc)."""

    def __init__(self, W: int, H: int) -> None:
        self.W = W
        self.H = H
        self.part = np.full((H, W), -1, dtype=np.int32)
        self.idx = np.zeros((H, W), dtype=np.int32)
        self.depth = np.full((H, W), np.inf)
        self.light = np.zeros((H, W))
        self.mats: list[Material] = []
        self.groups: list[str] = []
        # Pixels with a fixed colour (outlines, effects): (H, W) hex strings or None.
        self.fixed: list[list[str | None]] = [[None] * W for _ in range(H)]
        self.alpha = np.full((H, W), 255, dtype=np.int32)

    def add_part(self, mat: Material, group: str) -> int:
        self.mats.append(mat)
        self.groups.append(group)
        return len(self.mats) - 1

    def solid(self) -> np.ndarray:
        fixed = np.array([[c is not None for c in row] for row in self.fixed])
        return (self.part >= 0) | fixed

    def put(self, x: int, y: int, part: int, idx: int, depth: float = -np.inf) -> bool:
        if 0 <= x < self.W and 0 <= y < self.H and depth <= self.depth[y, x]:
            self.part[y, x] = part
            self.idx[y, x] = max(0, min(idx, self.mats[part].top()))
            self.depth[y, x] = depth
            self.fixed[y][x] = None
            return True
        return False

    def color_at(self, x: int, y: int) -> str | None:
        if self.fixed[y][x] is not None:
            return self.fixed[y][x]
        p = self.part[y, x]
        if p < 0:
            return None
        return self.mats[p].colors[self.idx[y, x]]

    def rgba(self) -> np.ndarray:
        out = np.zeros((self.H, self.W, 4), dtype=np.uint8)
        cache: dict[str, tuple[int, int, int]] = {}
        for y in range(self.H):
            for x in range(self.W):
                c = self.color_at(x, y)
                if c is None:
                    continue
                if c not in cache:
                    v = c.lstrip("#")
                    cache[c] = (int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16))
                out[y, x, :3] = cache[c]
                out[y, x, 3] = self.alpha[y, x]
        return out


def _normals(model: Node, P: np.ndarray, e: float) -> np.ndarray:
    k = np.array([[1, -1, -1], [-1, -1, 1], [-1, 1, -1], [1, 1, 1]], dtype=float)
    n = np.zeros_like(P)
    for row in k:
        d, _ = model.eval(P + row * e)
        n += row[None, :] * d[:, None]
    return n / (np.linalg.norm(n, axis=1, keepdims=True) + 1e-9)


def render(model: Node, cam: Camera, ss: int = 3, light: Sequence[float] = DEFAULT_LIGHT,
           ambient: float = 0.06, ao_dist: float = 1.2, steps: int = 140,
           coverage: float = 0.5, thin_coverage: float = 0.25, dither_band: float = 0.22,
           shade_bias: float = 0.0) -> Frame:
    """Renders `model` through `cam` into a Frame (see module doc).

    ao_dist: how far (model units) creases are looked for; shade_bias: added to every light value
    (brighter or darker sprite overall)."""
    leaves = model.leaves()
    for i, leaf in enumerate(leaves):
        leaf.part = i
    frame = Frame(cam.W, cam.H)
    for leaf in leaves:
        frame.add_part(leaf.mat, leaf.group)

    O, D = cam.rays(ss)
    n_rays = O.shape[0]
    t = np.zeros(n_rays)
    hit = np.zeros(n_rays, dtype=bool)
    alive = np.ones(n_rays, dtype=bool)
    eps = 0.02 * cam.scale
    tmax = cam.z0 * 2.0
    for _ in range(steps):
        idx = np.nonzero(alive)[0]
        if idx.size == 0:
            break
        P = O[idx] + t[idx, None] * D
        d, _ = model.eval(P)
        done = d < eps
        hit[idx[done]] = True
        t[idx] += np.maximum(d, eps * 0.5) * 0.85
        gone = t[idx] > tmax
        alive[idx[done | gone]] = False

    hidx = np.nonzero(hit)[0]
    P = O[hidx] + t[hidx, None] * D
    _, part = model.eval(P)
    nrm = _normals(model, P, 0.05 * cam.scale)

    # Ambient occlusion: how much of the space just off the surface is inside something.
    occ = np.zeros(hidx.size)
    for k, h in enumerate((0.35, 0.8, 1.5)):
        hh = h * ao_dist
        d, _ = model.eval(P + nrm * hh)
        occ += (0.5 ** k) * np.clip((hh - d) / hh, 0.0, 1.0)
    ao = np.clip(1.0 - occ / 1.75, 0.0, 1.0)

    nv = nrm @ cam.R.T
    L = np.asarray(light, dtype=float)
    L = L / np.linalg.norm(L)
    ndl = nv @ L
    wrap = np.array([leaves[p].mat.wrap for p in part])
    aok = np.array([leaves[p].mat.ao for p in part])
    diffuse = np.clip((ndl + wrap) / (1.0 + wrap), 0.0, 1.0)
    value = ambient + (1.0 - ambient) * diffuse
    value = value * (1.0 - aok * (1.0 - ao)) + shade_bias
    Rv = 2.0 * ndl[:, None] * nv - L[None, :]
    spec_w = np.array([leaves[p].mat.spec for p in part])
    spec_p = np.array([leaves[p].mat.spec_power for p in part])
    spec = spec_w * np.clip(Rv[:, 2], 0.0, 1.0) ** spec_p

    # Per-pixel vote.
    H, W = cam.H, cam.W
    sy, sx = np.divmod(np.arange(n_rays), W * ss)
    py = sy // ss
    px = sx // ss
    pix = (py * W + px)[hidx]
    n_parts = len(leaves)
    counts = np.zeros((H * W, n_parts), dtype=np.int32)
    np.add.at(counts, (pix, part), 1)
    vsum = np.zeros((H * W, n_parts))
    np.add.at(vsum, (pix, part), value)
    ssum = np.zeros((H * W, n_parts))
    np.add.at(ssum, (pix, part), spec)
    dmin = np.full((H * W, n_parts), np.inf)
    np.minimum.at(dmin, (pix, part), t[hidx])
    ndl_sum = np.zeros((H * W, n_parts))
    np.add.at(ndl_sum, (pix, part), ndl)

    total = counts.sum(axis=1)
    thin = np.array([leaf.thin for leaf in leaves])
    # Prefer the majority; break ties toward the nearer part.
    score = counts * 1000.0 - np.where(np.isfinite(dmin), dmin, 1e6) * 1e-3
    best = np.argmax(score, axis=1)
    best_count = counts[np.arange(H * W), best]
    need = math.ceil(ss * ss * coverage)
    need_thin = max(1, math.ceil(ss * ss * thin_coverage))
    solid = (total >= need) | ((best_count >= need_thin) & thin[best])
    # A thin part wins its pixel even when a bigger part behind it got more rays.
    if thin.any():
        thin_counts = np.where(thin[None, :], counts, 0)
        tbest = np.argmax(thin_counts - np.where(np.isfinite(dmin), dmin, 1e6) * 1e-6, axis=1)
        tc = thin_counts[np.arange(H * W), tbest]
        nearer = dmin[np.arange(H * W), tbest] <= dmin[np.arange(H * W), best]
        take = (tc >= need_thin) & nearer
        best = np.where(take, tbest, best)
        best_count = counts[np.arange(H * W), best]
        solid = solid | take

    for flat in np.nonzero(solid)[0]:
        y, x = divmod(int(flat), W)
        p = int(best[flat])
        c = counts[flat, p]
        mat = leaves[p].mat
        v = vsum[flat, p] / c
        s = ssum[flat, p] / c
        if mat.emissive:
            top = mat.glow_index if mat.glow_index is not None else mat.top()
            f = float(top) - (1.0 if ndl_sum[flat, p] / c < -0.35 else 0.0)
        else:
            f = mat.lo + v * (mat.hi - mat.lo)
            if s > 0.35:
                f = max(f, mat.top() - (0 if s > 0.6 else 1) + 0.0)
        if mat.dither:
            fl = math.floor(f)
            frac = f - fl
            if abs(frac - 0.5) < dither_band:
                i = fl + (1 if frac > BAYER2[y % 2, x % 2] else 0)
            else:
                i = int(round(f))
        else:
            i = int(round(f))
        frame.part[y, x] = p
        frame.idx[y, x] = max(0, min(mat.top(), i))
        frame.depth[y, x] = dmin[flat, p]
        frame.light[y, x] = v
    return frame


# --- Overlays: thin lines and hand-drawn stamps on top of a render -----------------------------


def line3d(frame: Frame, cam: Camera, pts: Sequence[Sequence[float]], mat: Material,
           idx: int | Sequence[int], group: str = "", depth_bias: float = 0.6,
           always: bool = False) -> int:
    """Draws a 1-pixel polyline through model points (blades, staffs, straps, hair strands),
    hidden where the model is in front of it unless `always`. `idx` is one ramp index or one per
    segment. Returns the new part id."""
    part = frame.add_part(mat, group or mat.name)
    proj = [cam.project(p) for p in pts]
    for s in range(len(proj) - 1):
        (x0, y0, d0), (x1, y1, d1) = proj[s], proj[s + 1]
        ii = idx if isinstance(idx, int) else idx[s]
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for k in range(n + 1):
            u = k / max(n, 1)
            x = int(math.floor(x0 + (x1 - x0) * u))
            y = int(math.floor(y0 + (y1 - y0) * u))
            d = d0 + (d1 - d0) * u - depth_bias
            if always:
                d = -np.inf
            frame.put(x, y, part, ii, d)
    return part


def stamp(frame: Frame, cam: Camera, anchor: Sequence[float], rows: Sequence[str],
          legend: dict[str, tuple[Material, int]], origin: tuple[int, int] = (0, 0),
          depth_bias: float = 1.0, always: bool = False, flip: bool = False) -> None:
    """Pastes a tiny hand-drawn picture (rows of characters; '.' or ' ' = clear) with its
    `origin` character cell on the projection of `anchor` (eyes, emblems, mouths, rivets).
    Hidden when something is in front of the anchor unless `always`."""
    ax, ay, ad = cam.project(anchor)
    ax_i = int(math.floor(ax))
    ay_i = int(math.floor(ay))
    parts: dict[str, int] = {}
    for ch, (mat, _) in legend.items():
        parts[ch] = frame.add_part(mat, mat.name + "_stamp")
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch in ". " or ch not in legend:
                continue
            cc = (len(row) - 1 - c) if flip else c
            x = ax_i + cc - (len(row) - 1 - origin[0] if flip else origin[0])
            y = ay_i + r - origin[1]
            if not (0 <= x < frame.W and 0 <= y < frame.H):
                continue
            if not always and frame.depth[y, x] < ad - depth_bias - 3.0 and frame.part[y, x] >= 0:
                continue
            mat, i = legend[ch]
            frame.part[y, x] = parts[ch]
            frame.idx[y, x] = i
            frame.depth[y, x] = ad - depth_bias
            frame.fixed[y][x] = None
