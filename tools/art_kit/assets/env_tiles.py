"""Ground and wall textures (32x32, seamless) and the far backdrops (320x120) of every place.

Textures are drawn in 2D from a height map: light from the upper left (the kit's one light) is
baked into ramp indices, so every pixel is one palette colour. Everything that shapes a texture
is periodic (rolled differences, periodic noise, points copied into the neighbouring tiles), so
the tiles join without seams. They are seen many at once from a tilted camera, so the contrast
stays moderate and the detail comes in clusters, never single-pixel noise.

Backdrops are layered silhouettes, far to near, coloured from each place's own sky and fog
(data/looks/*.tres): farther layers sit closer to the fog colour, nearer ones go dark and catch a
thin rim of moonlight on their upper-left edges. Pixels are fully opaque or fully clear.
"""
from __future__ import annotations

import math
import os
import re

import numpy as np
from PIL import Image

from kit.canvas import rgba8
from kit.color import hex_to_rgb, mix, rgb_to_hex
from kit.context import PREVIEW
from kit.noise import fbm2
from kit.palette import INK, M, Material
from kit.sheet import preview

T = 32  # texture size
# The kit's light (upper left, a little in front) in texture space: x right, y down, z out.
LIGHT = np.array([-0.55, -0.62, 0.78])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = N4 + ((1, 1), (1, -1), (-1, 1), (-1, -1))


# --- Shared texture helpers ---------------------------------------------------------------------

def _phase(seed: int, k: int) -> float:
    """A fixed, seed-dependent shift of the noise lattice (as a share of one cell). Value noise
    is flat at its lattice points, and every octave of a periodic noise has one on the tile's
    edge; shifting the lattice keeps flat, structureless strips off the seam."""
    return ((seed * 0.6180339887 + k * 0.4142135624) % 1.0) * 0.6 + 0.2


def pnoise(seed: int, cells: int, octaves: int = 3, gain: float = 0.5) -> np.ndarray:
    """Periodic fractal noise on the 32x32 tile in [0, 1] (cells = lattice cells per tile)."""
    c = (np.arange(T) + 0.5) * (cells / T)
    x, y = np.meshgrid(c + _phase(seed, 1), c + _phase(seed, 2))
    n = fbm2(x, y, seed=seed, octaves=octaves, period=cells, gain=gain)
    lo, hi = n.min(), n.max()
    return (n - lo) / max(hi - lo, 1e-9)


def norm(a: np.ndarray) -> np.ndarray:
    """Stretches a field to [0, 1]."""
    lo, hi = a.min(), a.max()
    return (a - lo) / max(hi - lo, 1e-9)


def top(a: np.ndarray, frac: float) -> np.ndarray:
    """Mask of the `frac` share of pixels where `a` is highest (area control for patches)."""
    return a > np.quantile(a, 1.0 - frac)


def pnoise_1d(seed: int, cells: int, n: int = T, octaves: int = 2) -> np.ndarray:
    """Periodic 1D noise along x in [0, 1] (one row of 2D periodic noise)."""
    x = (np.arange(n) + 0.5) * (cells / n) + _phase(seed, 3)
    y = np.full_like(x, 0.37)
    v = fbm2(x, y, seed=seed, octaves=octaves, period=cells)
    lo, hi = v.min(), v.max()
    return (v - lo) / max(hi - lo, 1e-9)


def shade(h: np.ndarray, slope: float = 1.0) -> np.ndarray:
    """Baked light from a periodic height map, relative to flat ground (0 = as lit as flat,
    positive = facing the light)."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * slope
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * slope
    nz = 1.0 / np.sqrt(dx * dx + dy * dy + 1.0)
    d = (-dx * LIGHT[0] - dy * LIGHT[1] + LIGHT[2]) * nz
    return d - LIGHT[2]


def wshift(a: np.ndarray, dx: int, dy: int, wrap: bool = True) -> np.ndarray:
    """a moved so out[y, x] = a[y + dy, x + dx] (wrapping, or repeating the edge)."""
    if wrap:
        return np.roll(np.roll(a, -dy, 0), -dx, 1)
    H, W = a.shape
    ys = np.clip(np.arange(H) + dy, 0, H - 1)
    xs = np.clip(np.arange(W) + dx, 0, W - 1)
    return a[ys][:, xs]


def despeckle(key: np.ndarray, wrap: bool = True, passes: int = 3,
              keep: np.ndarray | None = None) -> np.ndarray:
    """Lone pixels (no 4-neighbour of the same colour) take their most common neighbour's colour,
    so shading comes in clusters, as a pixel artist would place it."""
    key = key.copy()
    for _ in range(passes):
        nb = np.stack([wshift(key, dx, dy, wrap) for dx, dy in N4])
        lonely = ~(nb == key[None]).any(0)
        if keep is not None:
            lonely &= ~keep
        if not lonely.any():
            break
        counts = np.stack([(nb == nb[i][None]).sum(0) for i in range(4)])
        best = np.take_along_axis(nb, counts.argmax(0)[None], 0)[0]
        key = np.where(lonely, best, key)
    return key


class Tex:
    """A texture as a material index map plus a ramp index map."""

    def __init__(self, mats: list[str | list[str]], H: int = T, W: int = T) -> None:
        self.ramps: list[list[str]] = [M[m].colors if isinstance(m, str) else m for m in mats]
        self.names = [m if isinstance(m, str) else "custom%d" % i for i, m in enumerate(mats)]
        self.mat = np.zeros((H, W), dtype=np.int64)
        self.lvl = np.zeros((H, W), dtype=np.int64)

    def set(self, where: np.ndarray, mat: int, lvl: np.ndarray | int) -> None:
        top = len(self.ramps[mat]) - 1
        lv = np.clip(np.rint(lvl), 0, top).astype(np.int64) if not isinstance(lvl, int) else lvl
        self.mat = np.where(where, mat, self.mat)
        self.lvl = np.where(where, lv, self.lvl)

    def key(self) -> np.ndarray:
        return self.mat * 16 + self.lvl

    def from_key(self, key: np.ndarray) -> None:
        self.mat = key // 16
        self.lvl = key % 16

    def clean(self, wrap: bool = True, passes: int = 3, keep: np.ndarray | None = None) -> None:
        self.from_key(despeckle(self.key(), wrap, passes, keep))

    def px(self, x: int, y: int, mat: int, lvl: int) -> None:
        self.mat[y % self.mat.shape[0], x % self.mat.shape[1]] = mat
        self.lvl[y % self.mat.shape[0], x % self.mat.shape[1]] = max(
            0, min(len(self.ramps[mat]) - 1, lvl))

    def bump(self, x: int, y: int, d: int) -> None:
        """Moves one pixel d steps along its own ramp (wrapping coordinates)."""
        y %= self.mat.shape[0]
        x %= self.mat.shape[1]
        top = len(self.ramps[self.mat[y, x]]) - 1
        self.lvl[y, x] = max(0, min(top, self.lvl[y, x] + d))

    def rgba(self) -> np.ndarray:
        H, W = self.mat.shape
        out = np.zeros((H, W, 4), dtype=np.uint8)
        for mi, ramp in enumerate(self.ramps):
            for li, col in enumerate(ramp):
                sel = (self.mat == mi) & (self.lvl == li)
                if sel.any():
                    out[sel] = rgba8(col)
        return out


def bresenham(x0: int, y0: int, x1: int, y1: int) -> list[tuple[int, int]]:
    pts = []
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        pts.append((x0, y0))
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy
    return pts


def crack_path(rng: np.random.Generator, x: int, y: int, steps: int,
               heading: float) -> list[tuple[int, int]]:
    """A wandering crack: short straight runs joined into a pixel-perfect path."""
    pts = [(x, y)]
    ang = heading
    fx, fy = float(x), float(y)
    for _ in range(steps):
        ang += rng.uniform(-0.7, 0.7)
        run = rng.integers(2, 4)
        nx, ny = fx + math.cos(ang) * run, fy + math.sin(ang) * run
        seg = bresenham(int(round(fx)), int(round(fy)), int(round(nx)), int(round(ny)))
        pts.extend(seg[1:])
        fx, fy = nx, ny
    return pts


def stones(seed: int, cells: int, jitter: float, warp: float, merge: tuple = (),
           warp_cells: int = 4) -> tuple[np.ndarray, np.ndarray]:
    """Periodic irregular paving: (stone id, distance to the nearest joint in pixels). Joints
    are exact bisectors between stone points, so the distance is true; `merge` joins cells into
    bigger slabs; the lookup is domain-warped so the joints wobble like worn stone."""
    rng = np.random.default_rng(seed)
    grid = np.stack(np.meshgrid(np.arange(cells), np.arange(cells)), -1).reshape(-1, 2)
    pts = (grid + 0.5 + (rng.random((cells * cells, 2)) - 0.5) * jitter) * (T / cells)
    sid = np.arange(cells * cells)
    for a, b in merge:
        sid[sid == sid[b]] = sid[a]
    P, I = [], []
    for ox in (-1, 0, 1):
        for oy in (-1, 0, 1):
            P.append(pts + np.array([ox * T, oy * T]))
            I.append(sid)
    P = np.concatenate(P)
    I = np.concatenate(I)
    yy, xx = np.mgrid[0:T, 0:T] + 0.5
    if warp:
        wx = (pnoise(seed + 1, warp_cells, 2) - 0.5) * 2 * warp
        wy = (pnoise(seed + 2, warp_cells, 2) - 0.5) * 2 * warp
        xx = xx + wx
        yy = yy + wy
    d2 = (xx[..., None] - P[:, 0]) ** 2 + (yy[..., None] - P[:, 1]) ** 2
    near = d2.argmin(-1)
    s = I[near]
    p1 = P[near]
    d1 = np.take_along_axis(d2, near[..., None], -1)[..., 0]
    sep = np.sqrt(((P[None, None, :, :] - p1[:, :, None, :]) ** 2).sum(-1))
    bis = (d2 - d1[..., None]) / (2 * np.maximum(sep, 1e-6))
    bis = np.where(I[None, None, :] == s[..., None], np.inf, bis)
    return s, bis.min(-1)


def wrapd(c: float, n: int = T) -> np.ndarray:
    """Signed periodic distance from coordinate c along one axis of the tile."""
    return ((np.arange(n) + 0.5 - c + n / 2) % n) - n / 2


# --- Ground and wall textures -------------------------------------------------------------------

# A dim, smouldering ember (the lit glow ramp is far too hot for ash on the ground).
EMBER_DIM = ["#4a2a2e", "#7c3429", "#b2522e"]
# Moss for ground and walls: the shared moss ramp with greyer shadows, so seams full of moss do
# not turn into bright green grid lines once the game's colour grading saturates them.
MOSS_DIM = Material.make("moss_dim", "#56683a", shadow_chroma=0.75, shadow_shift=6).colors
# Packed dirt between flagstones: the shared dirt ramp with greyer, less rusty shadows.
DIRT_DIM = Material.make("dirt_dim", "#54473a", shadow_chroma=0.75, shadow_shift=6).colors


def joints(sid: np.ndarray) -> np.ndarray:
    """A 1-pixel joint wherever a stone meets another (on the upper/left stone of each pair), so
    no two neighbouring face pixels of different stones ever touch."""
    return (sid != wshift(sid, 1, 0)) | (sid != wshift(sid, 0, 1))


def junctions(sid: np.ndarray) -> np.ndarray:
    """Pixels where three or more stones meet (within a 3x3 neighbourhood)."""
    nb = np.stack([wshift(sid, dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)])
    s = np.sort(nb, 0)
    return (1 + (np.diff(s, axis=0) != 0).sum(0)) >= 3


def cap_runs(mask: np.ndarray, longest: int) -> np.ndarray:
    """Breaks every straight run (along rows and columns, wrapping) of a mask longer than
    `longest` pixels, so a line of moss never draws a stripe across the tile."""
    out = mask.copy()
    for axis in (0, 1):
        m = out if axis == 1 else out.T
        for r in range(m.shape[0]):
            row = m[r]
            if row.all():
                row[::longest] = False
                continue
            start = int(np.argmin(row))  # a gap: runs are counted from there, wrapping
            run = 0
            for k in range(1, m.shape[1] + 1):
                i = (start + k) % m.shape[1]
                if row[i]:
                    run += 1
                    if run > longest:
                        row[i] = False
                        run = 0
                else:
                    run = 0
    return out


# Old flagstones: a warm grey, a little dirtier than the cool wall stone, in fine steps so each
# slab can have its own tone.
FLAG = Material.make("flagstone", "#5a5450", below=2, above=3, step_l=0.055, grey_hue=60,
                     shadow_chroma=0.6, shadow_shift=6).colors


def floor_tile(moss_seed: int = 90) -> np.ndarray:
    """Rotten Hollow ground: old flagstones, each worn flat with its own tone, dark joints with
    moss in some and packed dirt in others."""
    tex = Tex([FLAG, DIRT_DIM, MOSS_DIM])
    FL, DI, MO = 0, 1, 2
    rng = np.random.default_rng(101)
    sid, edge = stones(7, 3, 0.75, 1.1, merge=((4, 5),))
    joint = joints(sid)
    # A worn joint is wider in places.
    joint |= edge < 0.25 + 0.5 * (pnoise(21, 4, 2) > 0.7)
    face = ~joint
    # One tone per slab (a few lighter, a few darker), a lit top-left bevel and a shaded
    # bottom-right one, each one pixel wide.
    tone = np.array([2, 2, 3, 2, 2, 2, 3, 2, 3])
    lvl = tone[sid].astype(np.float64)
    lit = face & (wshift(joint, 0, -1) | wshift(joint, -1, 0))
    dark = face & (wshift(joint, 0, 1) | wshift(joint, 1, 0)) & ~lit
    lvl = lvl + lit - dark
    # Worn pits: a few small dips in the faces.
    pits = face & ~lit & ~dark & top(np.where(face, pnoise(31, 8, 1), -1.0), 0.035)
    lvl = lvl - pits
    tex.set(face, FL, lvl)
    # Joints: dark packed dirt.
    tex.set(joint, DI, 1)
    tex.clean(keep=lit | dark | joint)

    # Packed dirt: soft patches filling a few joints where three slabs meet, spilling onto the
    # slab corners.
    dn = pnoise(42, 4, 2)
    jy, jx = np.nonzero(junctions(sid) & joint)
    yy, xx = np.mgrid[0:T, 0:T]
    picked: list[tuple[int, int]] = []
    for i in np.argsort(-dn[jy, jx]):
        y0, x0 = int(jy[i]), int(jx[i])
        if all(min(abs(x0 - x1), T - abs(x0 - x1)) + min(abs(y0 - y1), T - abs(y0 - y1)) > 10
               for (x1, y1) in picked):
            picked.append((x0, y0))
        if len(picked) == 3:
            break
    rag = pnoise(43, 8, 1)
    dirt = np.zeros((T, T), dtype=bool)
    for k, (x0, y0) in enumerate(picked):
        dx = wrapd(x0 + 0.5)[None, :]
        dy = wrapd(y0 + 0.5)[:, None]
        r = (3.4, 2.8, 2.4)[k]
        dirt |= np.hypot(dx, dy * 1.2) + (rag - 0.5) * 2.0 < r
    dh = norm(pnoise(44, 8, 1))
    tex.set(dirt, DI, 2)
    tex.set(dirt & (dh > 0.6) & ~joint, DI, 3)
    tex.set(dirt & joint & (dh < 0.45), DI, 1)

    # Moss: in about half the joints, in short runs (no stripe across the tile), spilling onto a
    # slab edge where it grows thickest.
    mn = norm(pnoise(moss_seed, 4, 2) * 0.6 + pnoise(moss_seed - 2, 8, 2) * 0.4)
    gate = pnoise(moss_seed + 7, 8, 1) > 0.3
    in_joint = joint & ~dirt & (mn > np.quantile(mn[joint], 0.5)) & gate
    in_joint = cap_runs(in_joint, 7)
    q = np.quantile(mn, 0.93)
    clump = (mn > q) & (edge < 1.8) & ~dirt
    moss = in_joint | clump
    tex.set(moss, MO, 1)
    tex.set(clump & ~joint & (shade(mn * 3.0) > -0.02), MO, 2)
    tex.clean(keep=lit | dark | joint)

    # A few hairline cracks inside the bigger slabs.
    for (x, y, a, n) in ((7, 20, -0.6, 3), (24, 8, 2.2, 3), (17, 28, -1.9, 2)):
        for (px_, py_) in crack_path(rng, x, y, n, a):
            if tex.mat[py_ % T, px_ % T] == FL and face[py_ % T, px_ % T]:
                tex.px(px_, py_, DI, 1)
    return tex.rgba()


def highpass(a: np.ndarray) -> np.ndarray:
    """Removes a periodic field's tile-sized waves (the lowest frequencies), so no tile is
    lighter on one side than the other and the ground shows no checker from tile to tile."""
    f = np.fft.fft2(a)
    for ky in (-1, 0, 1):
        for kx in (-1, 0, 1):
            if kx or ky:
                f[ky, kx] = 0
    return np.real(np.fft.ifft2(f))


def components(mask: np.ndarray) -> tuple[np.ndarray, int]:
    """Labels the 8-connected parts of a mask on the tile (wrapping); returns (labels, count),
    label -1 outside the mask."""
    lab = -np.ones(mask.shape, dtype=np.int64)
    n = 0
    H, W = mask.shape
    for y0, x0 in zip(*np.nonzero(mask)):
        if lab[y0, x0] >= 0:
            continue
        stack = [(int(y0), int(x0))]
        lab[y0, x0] = n
        while stack:
            y, x = stack.pop()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = (y + dy) % H, (x + dx) % W
                    if mask[yy, xx] and lab[yy, xx] < 0:
                        lab[yy, xx] = n
                        stack.append((yy, xx))
        n += 1
    return lab, n


def keep_long(mask: np.ndarray, shortest: int) -> np.ndarray:
    """Drops the connected bits of a line mask shorter than `shortest` pixels (dashes)."""
    lab, n = components(mask)
    out = mask.copy()
    for i in range(n):
        if (lab == i).sum() < shortest:
            out[lab == i] = False
    return out


def blob(x: float, y: float, r: float, rag: np.ndarray, squash: float = 1.3) -> np.ndarray:
    """A soft-edged round patch at (x, y) on the tile (wrapping), ragged by a noise field."""
    dx = wrapd(x)[None, :]
    dy = wrapd(y)[:, None] * squash
    return np.hypot(dx, dy) + (rag - 0.5) * 1.6 < r


def fill_small(mask: np.ndarray, smallest: int) -> np.ndarray:
    """Removes the parts of a mask smaller than `smallest` pixels, and fills its holes smaller
    than that (so pools have no pinholes and no one-pixel splashes)."""
    out = mask.copy()
    for m, val in ((out, False), (~out, True)):
        lab, n = components(m)
        for i in range(n):
            sel = lab == i
            if sel.sum() < smallest:
                out[sel] = val
    return out


# Cliff rock: the darkest, coolest stone of the set, so the back walls sit behind the ground.
# Fine steps, so a facet can turn a little from its neighbour without drawing a hard shape.
CLIFF_ROCK = Material.make("cliff_rock", "#464856", below=3, above=3, step_l=0.042,
                           shadow_chroma=1.0).colors


def cliff(var: int = 0) -> np.ndarray:
    """Rock face for cliff blocks: three thick strata with ragged edges, each a ledge lit on top
    and shadowed underneath, its face broken into a few big, gently turned planes, and real
    fractures that cut down through a ledge."""
    tex = Tex([CLIFF_ROCK])
    RK = 0
    xs = np.arange(T)
    # Bed tops: a gentle undulation plus a ragged, broken edge (no smooth wave to repeat).
    base = (1.0, 13.0, 21.0)
    bnd = np.stack([b + (pnoise_1d(141 + i + var * 7, 1, octaves=1) - 0.5) * 2.0
                    + (pnoise_1d(151 + i + var * 7, 4, octaves=2) - 0.5) * 2.6
                    for i, b in enumerate(base)])
    top_row = np.floor(bnd).astype(np.int64)  # (beds, T)
    nb = len(base)
    yy = np.arange(T)[:, None]
    bed = np.zeros((T, T), dtype=np.int64)
    depth = np.zeros((T, T), dtype=np.int64)  # rows below the bed's top
    height = np.zeros((T, T), dtype=np.int64)  # the bed's thickness in this column
    for k in range(nb):
        t0 = top_row[k][None, :]
        t1 = (top_row[k + 1] if k + 1 < nb else top_row[0] + T)[None, :]
        for shift in (0, -T):
            y_ = yy - shift
            sel = (y_ >= t0) & (y_ < t1)
            bed = np.where(sel, k, bed)
            depth = np.where(sel, y_ - t0, depth)
            height = np.where(sel, t1 - t0, height)
    # Weathering: water running down each bed's face leaves vertical flutes, light ones hanging
    # from the ledge and dark ones rising from the shadowed foot, each its own length.
    lvl = np.full((T, T), 3, dtype=np.int64)
    rel = depth / np.maximum(height - 1, 1)
    for k in range(nb):
        f = pnoise_1d(191 + k * 5 + var * 11, 8, octaves=2)
        ln = pnoise_1d(192 + k * 5 + var * 11, 8, octaves=1)
        lit_f = (f > 0.66)[None, :] & (rel < 0.25 + 0.6 * ln[None, :])
        dark_f = (f < 0.3)[None, :] & (rel > 0.75 - 0.6 * ln[None, :])
        lvl = np.where((bed == k) & lit_f, 4, lvl)
        lvl = np.where((bed == k) & dark_f, 2, lvl)
    # Each bed: a 2-pixel lit ledge on top (the second row only where the ledge is deep), a
    # 2-pixel shadowed underside.
    deep = pnoise_1d(181 + var, 4, octaves=1)[None, :] > 0.35
    lvl = np.where(depth == 1, 5, np.where((depth == 2) & deep, 4, lvl))
    lvl = np.where(depth == height - 1, 1, np.where(depth == height - 2, np.minimum(lvl, 2), lvl))
    # Partings: two run the full width; the third fades out along the face.
    part = depth == 0
    fade = pnoise_1d(171 + var, 2, octaves=2) > 0.45
    shown = np.ones((nb, T), dtype=bool)
    shown[2] = fade
    for k in range(nb):
        r = top_row[k] % T
        part[r, xs] = shown[k]
        hide = ~shown[k]
        # Where the parting fades, the beds meet flush: no ledge, no underside.
        for dy in (-2, -1, 0, 1, 2):
            rr = (top_row[k] + dy) % T
            lvl[rr[hide], xs[hide]] = 3
    lvl = np.where(part, 0, lvl)
    tex.set(np.ones((T, T), bool), RK, lvl)
    tex.clean(keep=part)
    # Fractures: dark cracks from the foot of one bed down across the parting into the next,
    # nearly vertical with a few one-pixel jogs, lit on their right lip, gaping at the parting.
    for (x, k, n, jogs) in ((6, 0, 11, (5, -8)), (23, 1, 8, (4,)), (14, 2, 10, (-6, 8))):
        y = int(top_row[k][x]) - 3
        for j in range(n):
            if j in [abs(v) for v in jogs]:
                x += 1 if (j in jogs) else -1
            tex.px(x, y + j, RK, 0)
            tex.bump(x + 1, y + j, 2)
            if 2 <= j < 5:
                tex.px(x - 1, y + j, RK, 1)
    # Shift the beds so no parting runs along the tile's own edge (the tile stays seamless).
    return np.roll(tex.rgba(), 3, axis=0)


# Wall bricks: a neutral grey between the warm flagstones and the cool cliff rock, in fine steps.
WALL = Material.make("wall_stone", "#575557", below=3, above=3, step_l=0.04, shadow_chroma=0.9,
                     shadow_shift=8).colors
# Old lime mortar gone dark with dirt: warmer than the bricks.
MORTAR = Material.make("mortar_dirty", "#3f3631", below=2, above=1, step_l=0.05, grey_hue=50,
                       shadow_chroma=0.8).colors


def ruin_wall(var: int = 0) -> np.ndarray:
    """Ruined stone-brick wall: dark warm mortar, worn bricks with bevelled edges, chipped
    corners and one bitten-out top edge, a touch of moss on one ledge."""
    tex = Tex([WALL, MORTAR, MOSS_DIM])
    WL, MT, MO = 0, 1, 2
    rng = np.random.default_rng(505 + var)
    rows = [  # (row top, row height incl. mortar, x offset, brick lengths incl. mortar)
        (0, 8, 3, (13, 10, 9)),
        (8, 8, 9, (8, 14, 10)),
        (16, 8, 0, (11, 11, 10)),
        (24, 8, 6, (15, 8, 9)),
    ]
    BH = 7  # brick height without mortar
    brick = -np.ones((T, T), dtype=np.int64)
    bx = np.zeros((T, T), dtype=np.int64)
    by = np.zeros((T, T), dtype=np.int64)
    blen = np.ones((T, T), dtype=np.int64)
    corners: list[tuple[int, int, int]] = []  # (brick, x of its left column, y of its top row)
    n = 0
    for (top_, rh, off, lens) in rows:
        x = off
        for L in lens:
            for yy_ in range(top_, top_ + BH):
                for k in range(L - 1):
                    xx_ = (x + k) % T
                    brick[yy_, xx_] = n
                    bx[yy_, xx_] = k
                    by[yy_, xx_] = yy_ - top_
                    blen[yy_, xx_] = L - 1
            corners.append((n, x, top_))
            x += L
            n += 1
    mortar = brick < 0
    b = np.maximum(brick, 0)
    # Each brick one flat tone: most alike, two a fine step darker, one a step lighter.
    tone = np.zeros(n, dtype=np.int64)
    tone[[2, 7]] = -1
    tone[[5]] = 1
    face = 3 + tone[b]
    # Bevels: a lit top edge and left edge, a shaded bottom and right edge.
    lit_t = by == 0
    lit_l = (bx == 0) & (by > 0) & (by < BH - 1)
    dark_b = by == BH - 1
    dark_r = (bx == blen - 1) & (by > 0) & ~dark_b
    lvl = face + 2 * lit_t + lit_l - 2 * dark_b - dark_r
    tex.set(~mortar, WL, lvl)
    # Mortar: dark, darkest in the shadow just under a brick.
    tex.set(mortar, MT, 1)
    tex.set(mortar & wshift(~mortar, 0, -1) & (by[np.arange(T) - 1][:, :] >= 0), MT, 0)
    tex.clean(keep=lit_t | lit_l | dark_b | dark_r)

    def chunk(px: list[tuple[int, int]]) -> None:
        """Knocks pixels out of a brick: the hole is mortar-dark, the broken face below/right
        of it catches the light, the face above/left of it falls in shade."""
        hole = np.zeros((T, T), dtype=bool)
        for (x, y) in px:
            hole[y % T, x % T] = True
        tex.set(hole, MT, 0)
        rim_lit = ~hole & ~mortar & (wshift(hole, 0, -1) | wshift(hole, -1, 0))
        rim_dk = ~hole & ~mortar & (wshift(hole, 0, 1) | wshift(hole, 1, 0)) & ~rim_lit
        tex.lvl = np.where(rim_lit & (tex.mat == WL), np.minimum(tex.lvl + 1, 6), tex.lvl)
        tex.lvl = np.where(rim_dk & (tex.mat == WL), np.maximum(tex.lvl - 1, 0), tex.lvl)

    # Chips: bites out of a few brick corners.
    for bi, corner, size in ((0, "tl", 3), (4, "br", 3), (6, "tr", 2), (8, "bl", 2), (10, "tl", 2)):
        _, x0, y0 = corners[bi]
        L = int(blen[y0, x0 % T])
        pts = []
        for i in range(size):
            for j in range(size - i):
                pts.append((x0 + (i if corner[1] == "l" else L - 1 - i),
                            y0 + (j if corner[0] == "t" else BH - 1 - j)))
        chunk(pts)
    # A missing chunk bitten out of one brick's top edge.
    _, x0, y0 = corners[9]
    chunk([(x0 + 3 + i, y0 + j) for i in range(5) for j in range((1, 2, 3, 2, 1)[i])])
    # Hairline cracks running in from the edge of two bricks.
    for (x, y, path) in ((18, 7, ((1, 1), (1, 0), (1, 1), (1, 1))),
                         (2, 31, ((1, -1), (1, 0), (1, -1), (1, -1)))):
        for (dx, dy) in path:
            x, y = x + dx, y + dy
            if not mortar[y % T, x % T] and tex.mat[y % T, x % T] == WL:
                tex.bump(x, y, -2)
    # Damp: the rain that runs off the mossy ledge has stained the bricks under it a shade
    # darker, in a soft streak (no hard shape inside a brick).
    damp = np.zeros((T, T), dtype=bool)
    for (x, y, w, h) in ((13, 27, 3, 4), (14, 31, 2, 3), (28, 9, 2, 4)):
        damp[np.ix_(np.arange(y, y + h) % T, np.arange(x, x + w) % T)] = True
    sel = damp & (tex.mat == WL) & ~mortar
    tex.lvl = np.where(sel, np.maximum(tex.lvl - 1, 0), tex.lvl)
    # A touch of moss: a clump on one brick ledge, spilling over and dripping a little.
    clump = ["..aab...", ".abbcba.", "aabbbbaa", ".a..a...", "....a..."]
    for r, row in enumerate(clump):
        for c, ch in enumerate(row):
            if ch != ".":
                tex.px(11 + c, 22 + r, MO, {"a": 1, "b": 1, "c": 2}[ch])
    for c, ch in enumerate(".ab."):
        if ch != ".":
            tex.px(27 + c, 7, MO, 1)
    tex.px(28, 8, MO, 1)
    # Shift the courses so no mortar line runs along the tile's own edge (still seamless).
    return np.roll(tex.rgba(), 4, axis=0)


# --- Backdrops ----------------------------------------------------------------------------------

BW, BH = 320, 120
_YY, _XX = np.mgrid[0:BH, 0:BW] + 0.5
LOOKS = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))), "data", "looks")
# Used when a look file cannot be read (the values in data/looks when these were drawn).
LOOK_FALLBACK = {
    "rotten_hollow": ((0.06, 0.07, 0.1), (0.17, 0.19, 0.28), (0.34, 0.36, 0.5)),
    "ashen_ruins": ((0.06, 0.06, 0.09), (0.2, 0.21, 0.28), (0.38, 0.42, 0.58)),
    "sunken_bog": ((0.04, 0.07, 0.06), (0.14, 0.24, 0.18), (0.3, 0.42, 0.36)),
    "hollow_throne": ((0.07, 0.03, 0.04), (0.26, 0.12, 0.14), (0.42, 0.3, 0.34)),
}


def look_colors(name: str) -> tuple[str, str, str]:
    """(sky, fog, ambient) of a place, read from its StageLook so the backdrop melts into it."""
    vals = list(LOOK_FALLBACK[name])
    try:
        with open(os.path.join(LOOKS, name + ".tres"), encoding="utf-8") as f:
            text = f.read()
        for i, key in enumerate(("background_color", "fog_color", "ambient_color")):
            m = re.search(r"^%s = Color\(([^)]*)\)" % key, text, re.M)
            if m:
                vals[i] = tuple(float(v) for v in m.group(1).split(",")[:3])
    except OSError:
        pass
    return tuple(rgb_to_hex(v) for v in vals)  # type: ignore[return-value]


def lnoise(seed: int, scale: float, octaves: int = 3, n: int = BW) -> np.ndarray:
    """1D noise along the backdrop's width in [0, 1] (scale = pixels per lattice cell)."""
    x = (np.arange(n) + 0.5) / scale
    v = fbm2(x, np.full_like(x, 0.5 + seed * 0.013), seed=seed, octaves=octaves)
    return norm(v)


def m_profile(prof: np.ndarray) -> np.ndarray:
    """Everything below a skyline (one y per column)."""
    return _YY >= prof[None, :]


def m_rect(x0: float, y0: float, x1: float, y1: float) -> np.ndarray:
    return (_XX >= x0) & (_XX < x1) & (_YY >= y0) & (_YY < y1)


def m_poly(pts: list[tuple[float, float]]) -> np.ndarray:
    """Filled polygon (pixel centres inside, even-odd)."""
    out = np.zeros((BH, BW), dtype=bool)
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[i - 1]
        if y1 == y2:
            continue
        cross = ((y1 > _YY) != (y2 > _YY)) & (_XX < (x2 - x1) * (_YY - y1) / (y2 - y1) + x1)
        out ^= cross
    return out


def m_disc(cx: float, cy: float, r: float) -> np.ndarray:
    return (_XX - cx) ** 2 + (_YY - cy) ** 2 <= r * r


def m_seg(x0: float, y0: float, x1: float, y1: float, r0: float, r1: float) -> np.ndarray:
    """A tapered stroke from (x0, y0) radius r0 to (x1, y1) radius r1. Thin strokes (both radii
    under 0.75) are drawn pixel-perfect, one pixel wide."""
    out = np.zeros((BH, BW), dtype=bool)
    if max(r0, r1) < 0.75:
        for (x, y) in bresenham(int(math.floor(x0)), int(math.floor(y0)), int(math.floor(x1)),
                                int(math.floor(y1))):
            if 0 <= x < BW and 0 <= y < BH:
                out[y, x] = True
        return out
    pad = max(r0, r1) + 1
    xa, xb = int(max(0, min(x0, x1) - pad)), int(min(BW, max(x0, x1) + pad + 1))
    ya, yb = int(max(0, min(y0, y1) - pad)), int(min(BH, max(y0, y1) + pad + 1))
    if xa >= xb or ya >= yb:
        return out
    X = _XX[ya:yb, xa:xb]
    Y = _YY[ya:yb, xa:xb]
    dx, dy = x1 - x0, y1 - y0
    L2 = max(dx * dx + dy * dy, 1e-9)
    t = np.clip(((X - x0) * dx + (Y - y0) * dy) / L2, 0, 1)
    d = np.hypot(X - (x0 + t * dx), Y - (y0 + t * dy))
    out[ya:yb, xa:xb] = d <= (r0 + (r1 - r0) * t)
    return out


class Backdrop:
    """A backdrop as a palette index map (-1 = clear sky), painted far to near."""

    def __init__(self, look: str) -> None:
        self.sky, self.fog, self.amb = look_colors(look)
        self.pal: list[str] = []
        self.idx = -np.ones((BH, BW), dtype=np.int64)
        self.keep = np.zeros((BH, BW), dtype=bool)  # hand-placed details the clean-up leaves
        # The two ends of the depth ramp: the far haze (fog lifted toward the ambient light) and
        # the darkest near silhouette (the sky pushed toward the game's ink).
        self.haze = mix(self.fog, self.amb, 0.4)
        self.dark = mix(mix(self.sky, INK, 0.55), "#000000", 0.12)

    def c(self, color: str) -> int:
        if color not in self.pal:
            self.pal.append(color)
        return self.pal.index(color)

    def depth(self, t: float) -> str:
        """Silhouette colour at depth t (0 = farthest haze, 1 = nearest and darkest)."""
        return mix(self.haze, self.dark, t)

    def rim(self, t: float, amount: float = 0.3) -> str:
        """Moonlight catching the upper-left edges of a silhouette at depth t."""
        return mix(self.depth(t), self.amb, amount)

    def paint(self, mask: np.ndarray, color: str, keep: bool = False) -> None:
        i = self.c(color)
        self.idx[mask] = i
        if keep:
            self.keep |= mask
        else:
            self.keep &= ~mask

    def layer(self, mask: np.ndarray, t: float, rim: float = 0.0, fade: float = 0.0,
              fade_from: float = BH, fade_to: float = BH) -> None:
        """Paints one silhouette layer: flat depth colour, optionally fading toward the haze
        lower down (mist at its feet) and with a moonlit rim on its upper-left edges."""
        self.paint(mask, self.depth(t))
        if fade > 0:
            # Two stepped bands toward the haze (pixel art: no gradients), wavy edges.
            wob = (lnoise(int(t * 1000) + 7, 9.0, 2) - 0.5) * 4
            for k, f in ((1, 0.5), (2, 1.0)):
                yb = fade_from + (fade_to - fade_from) * (k - 1) + wob[None, :]
                self.paint(mask & (_YY >= yb), self.depth(t - fade * f))
        if rim > 0:
            self.paint(rim_edge(mask), self.rim(t, rim))

    def dot(self, x: int, y: int, color: str) -> None:
        if 0 <= x < BW and 0 <= y < BH:
            self.idx[y, x] = self.c(color)
            self.keep[y, x] = True

    def clean(self) -> None:
        """Removes stray pixels: lone opaque pixels in the sky, lone holes, and lone colour
        specks (hand-placed details are kept)."""
        solid = self.idx >= 0
        n8 = sum(wshift(solid, dx, dy, False) for dx, dy in N8)
        stray = solid & (n8 == 0) & ~self.keep
        self.idx[stray] = -1
        solid = self.idx >= 0
        n4 = sum(wshift(solid, dx, dy, False) for dx, dy in N4)
        hole = ~solid & (n4 == 4)
        if hole.any():
            nb = np.stack([wshift(self.idx, dx, dy, False) for dx, dy in N4])
            self.idx = np.where(hole, nb.max(0), self.idx)
        key = self.idx + 1
        cleaned = despeckle(key, wrap=False, passes=2, keep=self.keep | (key == 0))
        # Never let the clean-up turn an opaque pixel clear or the other way round.
        self.idx = np.where((cleaned == 0) != (key == 0), self.idx, cleaned - 1)
        # Opaque specks with no neighbour of their colour at all (edge pixels the pass above
        # could not fix) take the commonest colour of their opaque neighbours.
        nb = np.stack([wshift(self.idx, dx, dy, False) for dx, dy in N8])
        lone = (self.idx >= 0) & ~(nb == self.idx[None]).any(0) & ~self.keep
        for y, x in zip(*np.nonzero(lone)):
            vals = [v for v in nb[:, y, x] if v >= 0]
            if vals:
                self.idx[y, x] = max(set(vals), key=vals.count)

    def rgba(self) -> np.ndarray:
        """The image, with colours that differ by a hair (left over from mixing each layer
        with the fog) snapped to one shared colour."""
        out = np.zeros((BH, BW, 4), dtype=np.uint8)
        used = [i for i in range(len(self.pal)) if (self.idx == i).any()]
        cols = {i: rgba8(self.pal[i]).astype(np.int64) for i in used}
        # The commonest colour of a near-identical group wins.
        used.sort(key=lambda i: -int((self.idx == i).sum()))
        final: dict[int, np.ndarray] = {}
        for i in used:
            for j in final:
                if np.abs(cols[i][:3] - final[j][:3]).max() <= 3:
                    final[i] = final[j]
                    break
            else:
                final[i] = cols[i]
        for i in used:
            out[self.idx == i] = final[i].astype(np.uint8)
        return out


def rim_edge(mask: np.ndarray) -> np.ndarray:
    """The upper-left edge pixels of a silhouette, where it is at least 4 pixels thick (limbs
    and twigs stay dark instead of turning into lines of light)."""
    up = wshift(mask, 0, -1, False) & (np.arange(BH) > 0)[:, None]
    left = wshift(mask, -1, 0, False) & (np.arange(BW) > 0)[None, :]
    thick = mask.copy()
    for k in (1, 2, 3):
        thick &= wshift(mask, 0, k, False) & wshift(mask, k, 0, False)
    return thick & (~up | ~left)


def dead_tree(rng: np.random.Generator, x: float, y: float, h: float, lean: float = 0.0,
              spread: float = 1.0, depth: int = 3, twig: float = 0.42,
              width: float | None = None, decay: float = 0.62) -> np.ndarray:
    """A bare, crooked dead tree rooted at (x, y), about h pixels tall."""
    out = np.zeros((BH, BW), dtype=bool)
    w0 = width if width is not None else max(0.8, h / 18.0)

    def branch(x0: float, y0: float, ang: float, length: float, r: float, d: int) -> None:
        nonlocal out
        # Two bent sub-segments per limb so nothing grows ruler-straight.
        for _ in range(2):
            ang += rng.uniform(-0.22, 0.22)
            x1 = x0 + math.cos(ang) * length / 2
            y1 = y0 - math.sin(ang) * length / 2
            r1 = max(r * (0.8 + (decay - 0.62)), 0.3)
            out |= m_seg(x0, y0, x1, y1, r, r1)
            x0, y0, r = x1, y1, r1
        if d <= 0 or length < 3:
            return
        k = int(rng.integers(2, 4))
        for j in range(k):
            side = -1 if j % 2 == 0 else 1
            a = ang + side * spread * rng.uniform(0.35, 0.85)
            # Limbs curl back up the way old dead oaks do.
            a = a + (math.pi / 2 - a) * 0.15
            branch(x0, y0, a, length * rng.uniform(0.5, 0.72), r * decay, d - 1)

    trunk_ang = math.pi / 2 + lean
    # The trunk first, then limbs from the top and one or two lower down.
    branch(x, y, trunk_ang, h * 0.55, w0, depth)
    for frac in (0.32, 0.45):
        if rng.random() < 0.8:
            bx_ = x + math.cos(trunk_ang) * h * frac
            by_ = y - math.sin(trunk_ang) * h * frac
            side = 1 if rng.random() < 0.5 else -1
            branch(bx_, by_, trunk_ang + side * rng.uniform(0.6, 1.0), h * twig, w0 * 0.55,
                   max(0, depth - 2))
    # Root flare.
    out |= m_poly([(x - w0 * 2.2, y + 1), (x - w0 * 0.6, y - h * 0.08),
                   (x + w0 * 0.6, y - h * 0.08), (x + w0 * 2.4, y + 1)])
    return out


# --- Backdrop scenes ----------------------------------------------------------------------------

def far_hills(bd: Backdrop, rng: np.random.Generator, base: float, amp: float, seed: int,
              spikes: float = 0.0) -> np.ndarray:
    """Rolling far hills, optionally bristling with tiny dead trees on top."""
    prof = base + (lnoise(seed, 70.0) - 0.5) * amp + (lnoise(seed + 1, 18.0, 2) - 0.5) * amp * 0.3
    mask = m_profile(prof)
    if spikes > 0:
        x = 0
        while x < BW:
            if rng.random() < spikes:
                h = rng.uniform(2, 6)
                yb = prof[min(x, BW - 1)]
                mask |= m_seg(x + 0.5, yb, x + 0.5 + rng.uniform(-1, 1), yb - h, 0.3, 0.3)
                if h > 4 and rng.random() < 0.6:
                    mask |= m_seg(x + 0.5, yb - h * 0.6, x + 0.5 + rng.choice([-2, 2]),
                                  yb - h * 0.6 - 1.5, 0.3, 0.3)
            x += int(rng.integers(2, 5))
    return mask


def tufts(rng: np.random.Generator, prof: np.ndarray, density: float) -> np.ndarray:
    """Grass and weed blades poking up along a ground line."""
    out = np.zeros((BH, BW), dtype=bool)
    x = 0
    while x < BW:
        if rng.random() < density:
            yb = prof[x]
            for k in range(int(rng.integers(1, 4))):
                h = rng.uniform(1.5, 4.5)
                lean = rng.uniform(-1.5, 1.5)
                out |= m_seg(x + k + 0.5, yb + 0.5, x + k + 0.5 + lean, yb - h, 0.3, 0.3)
        x += int(rng.integers(2, 6))
    return out


def backdrop_rotten_hollow() -> Backdrop:
    """Rotten Hollow: a dead forest under a sick moon's light, a ruined watchtower whose last
    windows still glow rot-green."""
    bd = Backdrop("rotten_hollow")
    rng = np.random.default_rng(1001)
    # Far: hazy hills bristling with dead trees, a distant broken tower.
    far = far_hills(bd, rng, 74.0, 16.0, 11, spikes=0.55)
    # The distant tower: a broken, stepped crown with a stub still standing, one window slit.
    ghost = m_poly([(57, 80), (57.5, 50), (59, 50), (59, 45), (60, 45), (60, 41), (61, 41),
                    (61, 47), (63, 47), (63, 51), (65, 51), (65, 55), (67, 55), (67, 59),
                    (68, 59), (68.5, 80)])
    ghost &= ~m_rect(61, 58, 62, 64)
    far |= ghost
    bd.layer(far, 0.0)
    # Middle: a band of dead woods.
    ground_b = 88 + (lnoise(21, 40.0) - 0.5) * 8
    mid = m_profile(ground_b)
    for x in np.sort(rng.uniform(0, BW, 26)):
        h = rng.uniform(12, 26)
        mid |= dead_tree(rng, x, ground_b[int(x)] + 1, h, lean=rng.uniform(-0.15, 0.15),
                         depth=2, spread=0.9)
    bd.layer(mid, 0.44, rim=0.12, fade=0.2, fade_from=91, fade_to=96)
    # Near-middle: the ruined watchtower and its fallen curtain wall.
    # The tower's crown is broken in steps: one corner and a jutting stub still stand, the
    # middle has fallen in, the right side has lost course after course, a block is missing.
    tower = m_poly([(195, 106), (197, 22), (200, 22), (200, 12), (202, 12), (202, 18), (205, 18),
                    (205, 24), (209, 24), (209, 29), (213, 29), (213, 25), (216, 25), (216, 32),
                    (219, 32), (219, 38), (221.5, 38), (223.5, 106)])
    tower &= ~m_rect(213, 34, 216, 37)
    tower |= m_poly([(191, 106), (195, 84), (197, 106)])  # buttress
    wall = m_poly([(222, 106), (222, 66), (229, 64), (233, 68), (240, 66), (246, 72),
                   (252, 70), (258, 78), (264, 82), (268, 106)])
    arch = m_rect(234, 82, 244, 106) | m_disc(239, 82, 5)
    wall &= ~arch
    trees_c = dead_tree(rng, 120, 104, 40, lean=0.12, depth=3, spread=1.0)
    trees_c |= dead_tree(np.random.default_rng(31), 160, 104, 34, lean=-0.12, depth=3,
                         spread=0.8, decay=0.66)
    ground_c = m_profile(100 + (lnoise(31, 30.0) - 0.5) * 6)
    mid2 = tower | wall | trees_c | ground_c
    t_c = 0.68
    bd.layer(mid2, t_c, rim=0.2)
    # Moonlight down the tower's lit left side, so it stands clear of the ground it rises from.
    left_edge = tower & ~wshift(tower, -1, 0, False)
    bd.paint(left_edge & (_YY < 100), bd.rim(t_c, 0.2))
    bd.paint(wshift(left_edge, -1, 0, False) & tower & (_YY < 100) & (_YY > 24), bd.rim(t_c, 0.1))
    # The tower's last lit windows: a sickly rot glow.
    glow = mix("#a6d46a", bd.depth(t_c), 0.42)
    glow_dim = mix(glow, bd.depth(t_c), 0.5)
    for (x, y) in ((206, 38), (211, 60), (203, 78)):
        bd.paint(m_rect(x, y, x + 2, y + 3), glow_dim, keep=True)
        bd.paint(m_rect(x, y, x + 2, y + 2), glow, keep=True)
    for (x, y) in ((214, 46),):  # a dark, empty window
        bd.paint(m_rect(x, y, x + 2, y + 3), bd.depth(0.9), keep=True)
    # Near: the hollow's floor, two great dead trees framing the view, old grave stakes.
    ground_d = 108 + (lnoise(41, 34.0) - 0.5) * 7
    near = m_profile(ground_d)
    near |= dead_tree(np.random.default_rng(7), 24, ground_d[24] + 2, 90, lean=0.06,
                      depth=4, spread=1.05, width=4.2, decay=0.74)
    near |= dead_tree(np.random.default_rng(12), 300, ground_d[300] + 2, 80, lean=-0.1,
                      depth=4, spread=1.0, width=3.6, decay=0.74)
    for (x, h, tilt) in ((74, 9, 0.1), (82, 7, -0.15), (90, 10, 0.05), (262, 8, -0.1),
                         (272, 11, 0.12)):
        yb = ground_d[x] + 1
        near |= m_seg(x, yb, x + tilt * h, yb - h, 0.9, 0.7)
        if h > 8:
            near |= m_seg(x - 2.5 + tilt * h * 0.7, yb - h * 0.7, x + 2.5 + tilt * h * 0.7,
                          yb - h * 0.7, 0.55, 0.55)
    for (x, w, h) in ((140, 9, 4), (178, 6, 3), (236, 11, 5)):  # boulders
        near |= m_poly([(x, ground_d[x] + 2), (x + 1, ground_d[x] - h + 1), (x + w * 0.4, ground_d[x] - h),
                        (x + w, ground_d[x] - h + 2), (x + w + 1, ground_d[x] + 2)])
    near |= tufts(rng, ground_d, 0.5)
    bd.layer(near, 0.94, rim=0.28)
    bd.clean()
    return bd


# --- Ashen Ruins backdrop

def skyline(rng: np.random.Generator, x0: float, x1: float, base: float, hmin: float,
            hmax: float, wmin: int, wmax: int,
            max_spires: int = 3) -> tuple[np.ndarray, list[tuple[int, int]]]:
    """A far, burned city: gutted shells with ragged tops, broken towers, a few roofs and domes
    still standing and at most `max_spires` spires. Buildings overlap (no sky shows between them
    down to the ground). Returns the mask and the empty windows' top-left corners."""
    out = np.zeros((BH, BW), dtype=bool)
    wins: list[tuple[int, int]] = []
    spires = 0
    x = x0
    kinds = ["gutted", "gutted", "broken", "broken", "broken", "flat", "gable", "dome", "spire"]
    while x < x1:
        w = int(rng.integers(wmin, wmax + 1))
        h = rng.uniform(hmin, hmax)
        top = base - h
        kind = str(rng.choice(kinds))
        if kind == "spire" and spires >= max_spires:
            kind = "broken"
        m = m_rect(x, top, x + w, base + 1)
        if kind == "gable":
            m |= m_poly([(x - 0.5, top + 0.5), (x + w / 2, top - w * 0.6), (x + w + 0.5, top + 0.5)])
        elif kind == "spire":
            spires += 1
            sw = max(2.0, w * 0.4)
            cx = x + w / 2
            m |= m_rect(cx - sw / 2, top - h * 0.35, cx + sw / 2, top + 1)
            m |= m_poly([(cx - sw / 2 - 0.5, top - h * 0.35 + 0.5), (cx, top - h * 0.35 - w * 1.2),
                         (cx + sw / 2 + 0.5, top - h * 0.35 + 0.5)])
        elif kind == "dome":
            m |= m_disc(x + w / 2, top + 0.5, w / 2) & (_YY < top + 1)
        elif kind == "flat":
            for k in range(0, w, 2):  # battlements
                m |= m_rect(x + k, top - 1, x + k + 1, top)
        elif kind == "broken":
            # The top fallen away on a slant, a stub left standing on one side.
            cut = [(x + w * 0.3, top - 1), (x + w + 1, top - 1), (x + w + 1, top + h * 0.4),
                   (x + w * 0.6, top + h * 0.15)]
            if rng.random() < 0.5:
                cut = [(2 * x + w - px_, py_) for (px_, py_) in cut]
            m &= ~m_poly(cut)
        else:  # gutted: the walls burned down to ragged stumps of different heights
            k = 0
            while k < w:
                step = int(rng.integers(1, 4))
                drop = rng.uniform(0, h * 0.3)
                m &= ~m_rect(x + k, top - 1, x + k + step, top + drop)
                k += step
        out |= m
        # An empty window in some of the taller shells.
        if kind in ("gutted", "flat", "broken") and h > 14 and w >= 6 and rng.random() < 0.7:
            wins.append((int(x + w / 2 - 1 + rng.integers(-1, 2)), int(top + h * 0.45)))
        x += w + int(rng.integers(-2, 1))
    # Fill every column down from its top, so no sky shows through a gap between buildings.
    out = np.maximum.accumulate(out, axis=0)
    for (wx, wy) in wins:
        out[wy:wy + 2, wx:wx + 1] = False
    return out, wins


def burned_house(rng: np.random.Generator, x: float, base: float, w: float, h: float,
                 roof: float, collapse: str = "") -> tuple[np.ndarray, list[tuple[int, int]]]:
    """A burned-out house: walls, a gabled roof (one side fallen in), bare rafters, a chimney,
    empty windows. Returns the mask and the windows' top-left corners."""
    top = base - h
    m = m_rect(x, top, x + w, base + 1)
    ridge = (x + w / 2, top - roof)
    m |= m_poly([(x - 1, top + 0.5), ridge, (x + w + 1, top + 0.5)])
    m |= m_rect(x + w * 0.72, top - roof * 0.9, x + w * 0.72 + 2, top)  # chimney
    if collapse:
        # Half the roof burned through: cut it out and leave the rafters standing.
        side = -1 if collapse == "left" else 1
        cx = ridge[0] + side * 1
        cut = m_poly([(cx, ridge[1] + 1.5), (cx + side * w * 0.65, top + 0.5),
                      (cx + side * w * 0.65, top + 2.5), (cx, top + 2.5)])
        m &= ~cut
        for k in range(1, 4):
            rx = ridge[0] + side * k * w * 0.16
            m |= m_seg(rx, ridge[1] + 1 + k * roof * 0.32, rx + side * 0.5, top + 1, 0.3, 0.3)
        m |= m_seg(ridge[0], ridge[1] + 1, ridge[0] + side * w * 0.55, top + 1, 0.3, 0.3)
    wins = []
    nwin = max(1, int(w // 6))
    for i in range(nwin):
        wx = int(x + (i + 0.5) * w / nwin - 1)
        for wy in (int(top + 3), int(top + h * 0.55)):
            if wy + 3 < base - 1:
                m &= ~m_rect(wx, wy, wx + 2, wy + 3)
                wins.append((wx, wy))
    return m, wins


def smoke(rng: np.random.Generator, x: float, y: float, h: float, r0: float,
          r1: float, drift: float) -> np.ndarray:
    """A plume of smoke rising from (x, y): billowing puffs that widen, then lean over with the
    wind, flatten and thin out into torn streaks near the top."""
    out = np.zeros((BH, BW), dtype=bool)
    steps = int(h / 2.5)
    for i in range(steps):
        t = i / max(steps - 1, 1)
        if t > 0.62 and rng.random() < 0.4:
            continue  # the plume thins out and tears
        cx = x + drift * t ** 1.6 * h + rng.uniform(-1.0, 1.0) * (0.4 + t)
        cy = y - t * h * (1 - 0.25 * t) + rng.uniform(-0.6, 0.6)
        grow = min(1.0, t / 0.45)
        thin = max(0.0, (t - 0.55) / 0.45)
        r = (r0 + (r1 - r0) * grow) * (1 - 0.65 * thin) * rng.uniform(0.8, 1.15)
        # Puffs stretch out sideways as the wind takes them.
        rx = r * (1 + 0.9 * thin)
        ry = max(0.8, r * (1 - 0.45 * thin))
        out |= ((_XX - cx) / rx) ** 2 + ((_YY - cy) / ry) ** 2 <= 1.0
        if t < 0.6 and rng.random() < 0.5:  # a side billow low down
            out |= m_disc(cx + rng.choice([-1, 1]) * r * 0.8, cy + rng.uniform(-1, 1), r * 0.6)
    return out


def ember(bd: Backdrop, x: int, y: int, t: float, size: int = 1) -> None:
    """A dim smouldering point with a darker glow round it."""
    core = mix("#f08a40", bd.depth(t), 0.25)
    halo = mix("#c0502e", bd.depth(t), 0.6)
    for dx, dy in ((-1, 0), (size, 0), (0, -1), (0, 1)):
        bd.dot(x + dx, y + dy, halo)
    for k in range(size):
        bd.dot(x + k, y, core)


def backdrop_ashen_ruins() -> Backdrop:
    """Ashen Ruins: a burned city's skyline, smoke still rising, embers glowing in empty
    windows and among the rubble."""
    bd = Backdrop("ashen_ruins")
    rng = np.random.default_rng(2002)
    # Smoke first (it is the farthest thing), then the far city in the haze.
    plume = smoke(rng, 70, 82, 74, 2.5, 7.0, 0.22) | smoke(rng, 238, 80, 62, 2.0, 6.0, 0.26)
    bd.paint(plume, mix(bd.haze, bd.fog, 0.55))
    far, far_wins = skyline(rng, -4, BW + 4, 86.0, 12.0, 36.0, 5, 13, max_spires=3)
    far |= m_profile(86 + (lnoise(51, 30.0) - 0.5) * 3)
    t_f = 0.04
    bd.layer(far, t_f)
    # The fires still burning down in the streets light the city's feet: three stepped bands
    # with ragged tops, warmer toward the ground.
    for k, (row, amt, hot) in enumerate(((73.0, 0.13, "#9a5a48"), (79.0, 0.24, "#b0643e"),
                                        (84.0, 0.36, "#c8703e"))):
        rag = (lnoise(55 + k, 6.0, 2) - 0.5) * 6 + (lnoise(58 + k, 22.0, 2) - 0.5) * 4
        bd.paint(far & (_YY >= row + rag[None, :]), mix(bd.depth(t_f), hot, amt))
    # A few of the shells' empty windows show the fire inside.
    for i, (wx, wy) in enumerate(far_wins):
        if i % 3 == 1:
            bd.paint(m_rect(wx, wy, wx + 1, wy + 2), mix(bd.depth(t_f), "#d0703e", 0.45), keep=True)
    # Middle: the burned district, a ruined hall with a broken steeple.
    base_b = 96.0
    mid = m_profile(base_b + (lnoise(52, 25.0) - 0.5) * 4)
    wins_b: list[tuple[int, int]] = []
    for (x, w, h, roof, col) in ((6, 16, 14, 8, "right"), (26, 12, 18, 7, ""), (176, 14, 12, 7, "left"),
                                 (194, 18, 16, 9, "right"), (300, 15, 15, 8, "left")):
        m, wins = burned_house(rng, x, base_b, w, h, roof, col)
        mid |= m
        wins_b += wins
    # The hall: a long nave, its roof gone, a broken steeple.
    hall = m_rect(96, 66, 150, base_b + 1)
    hall |= m_poly([(94, 66.5), (100, 60), (112, 61), (116, 65), (121, 59), (124, 62), (129, 66.5)])
    hall |= m_rect(128, 38, 140, 67)
    hall |= m_poly([(127.5, 38.5), (131, 34), (133, 36), (135, 29), (137, 33), (140.5, 38.5)])
    for k in range(5):  # the nave's tall window holes
        hall &= ~(m_rect(100 + k * 9, 74, 104 + k * 9, 86) | m_disc(102 + k * 9, 74, 2))
    hall &= ~(m_rect(132, 44, 136, 52) | m_disc(134, 44, 2))
    mid |= hall
    for k in range(4):  # charred roof beams across the open nave
        bx = 100 + k * 8
        mid |= m_seg(bx, 66, bx + 5, 61 - (k % 2) * 2, 0.3, 0.3)
    t_b = 0.45
    bd.layer(mid, t_b, rim=0.12)
    # Embers still smoulder low inside a few burned-out houses: a dim red glow along the bottom
    # of the empty window, one hotter pixel in it.
    for i in (1, 4, 9):
        if i < len(wins_b):
            wx, wy = wins_b[i]
            glow = mix("#a8402c", bd.depth(t_b), 0.5)
            bd.paint(m_rect(wx, wy + 2, wx + 2, wy + 3), glow, keep=True)
            bd.dot(wx + (i % 2), wy + 2, mix("#e07a3c", bd.depth(t_b), 0.4))
    # Near-middle: a broken arcade and a wall stub, charred beams leaning.
    base_c = 104.0
    mid2 = m_profile(base_c + (lnoise(53, 20.0) - 0.5) * 5)
    arc = m_rect(214, 70, 290, base_c + 1)
    for k in range(6):
        ax = 218 + k * 12
        arc &= ~(m_rect(ax, 80, ax + 8, base_c + 1) | m_disc(ax + 4, 80, 4))
    arc &= ~m_poly([(256, 69), (292, 69), (292, 92), (282, 94), (276, 86), (268, 82), (262, 76)])
    mid2 |= arc
    mid2 |= m_poly([(36, base_c + 1), (38, 72), (42, 70), (44, 75), (49, 73), (52, 80), (55, 79),
                    (58, base_c + 1)])
    mid2 &= ~(m_rect(44, 84, 48, 92) | m_disc(46, 84, 2))
    mid2 |= m_seg(60, base_c, 74, 84, 1.2, 0.9) | m_seg(160, base_c, 150, 88, 1.0, 0.8)
    bd.layer(mid2, 0.7, rim=0.2)
    # Near: rubble, a charred post or two, a burned tree.
    ground_d = 110 + (lnoise(54, 26.0) - 0.5) * 8
    near = m_profile(ground_d)
    for (x, w, h) in ((22, 22, 7), (98, 30, 6), (176, 18, 5), (300, 26, 8)):  # rubble heaps
        pts = [(x, ground_d[min(x, BW - 1)] + 2)]
        for i in range(1, 6):
            pts.append((x + w * i / 6, ground_d[min(int(x + w * i / 6), BW - 1)] - h * math.sin(i / 6 * math.pi)
                        + rng.uniform(-1.5, 1.5)))
        pts.append((x + w, ground_d[min(x + w, BW - 1)] + 2))
        near |= m_poly(pts)
    near |= m_seg(132, ground_d[132] + 1, 131, ground_d[132] - 14, 1.0, 0.8)
    near |= m_seg(131, ground_d[132] - 10, 135, ground_d[132] - 12, 0.6, 0.5)
    near |= dead_tree(np.random.default_rng(23), 252, ground_d[252] + 2, 40, lean=0.05, depth=2,
                      spread=0.9, width=2.0, decay=0.6)
    near |= m_poly([(286, ground_d[286] + 2), (287, 88), (292, 86), (293, ground_d[293] + 2)])  # column
    bd.layer(near, 0.95, rim=0.28)
    for (x, t_) in ((44, 0.95), (112, 0.95), (186, 0.95), (308, 0.95)):
        ember(bd, x, int(ground_d[x]) + 2, t_)
    ember(bd, 241, int(base_c) - 1, 0.7, 2)
    bd.clean()
    return bd


# --- Sunken Bog backdrop

def hang_moss(rng: np.random.Generator, mask: np.ndarray, x0: int, x1: int, y0: int, y1: int,
              n: int, lmin: int = 3, lmax: int = 9) -> np.ndarray:
    """Strands of moss hanging from the undersides of limbs inside a box."""
    out = np.zeros((BH, BW), dtype=bool)
    tries = 0
    while n > 0 and tries < n * 30:
        tries += 1
        x = int(rng.integers(max(0, x0), min(BW, x1)))
        col = mask[y0:y1, x]
        ys = np.nonzero(col[:-1] & ~col[1:])[0]
        if not len(ys):
            continue
        y = y0 + int(rng.choice(ys)) + 1
        length = int(rng.integers(lmin, lmax + 1))
        for k in range(length):
            if y + k >= BH or mask[y + k, x]:
                break
            out[y + k, x] = True
        n -= 1
    return out


def mist_top(seed: int, top: float, amp: float, scale: float, rag: float = 0.0) -> np.ndarray:
    """The top edge of a mist bank: a slow roll plus, optionally, a ragged, torn fringe."""
    t = top + (lnoise(seed, scale, 3) - 0.5) * 2 * amp
    if rag > 0:
        t = t + (lnoise(seed + 5, 3.0, 2) - 0.5) * 2 * rag
    return t


def mist_band(seed: int, top: float, bottom: float, amp: float, scale: float,
              rag: float = 0.0) -> np.ndarray:
    """A low bank of mist: a wavy (optionally ragged) top edge, a gently wavy bottom edge."""
    t = mist_top(seed, top, amp, scale, rag)
    b = bottom + (lnoise(seed + 1, scale * 1.5, 2) - 0.5) * amp
    return (_YY >= t[None, :]) & (_YY < b[None, :])


def sink_into_mist(bd: "Backdrop", mask: np.ndarray, top: np.ndarray, color: str, mist: str,
                   rows: int = 3) -> None:
    """Fades a silhouette into a mist bank below it: a band of a halfway colour just above the
    mist's top edge (one clear step, no gradient)."""
    band = mask & (_YY >= top[None, :] - rows) & (_YY < top[None, :])
    bd.paint(band, mix(color, mist, 0.5))


def drowned_tree(rng: np.random.Generator, x: float, y: float, h: float, lean: float,
                 snap: float = 0.0, width: float | None = None) -> np.ndarray:
    """A dead tree standing in the water, its foot flared like a swamp cypress. A snapped one
    is a bare trunk with a splintered top and a stub of a limb."""
    w = width if width is not None else max(0.9, h / 16.0)
    if snap <= 0:
        m = dead_tree(rng, x, y, h, lean=lean, depth=2, spread=0.75, twig=0.35, width=w,
                      decay=0.66)
    else:
        th = h * (1 - snap)
        tx = x + math.sin(lean) * th
        m = m_seg(x, y, tx, y - th, w * 1.1, w * 0.8)
        # Splintered top: two jagged points.
        m |= m_poly([(tx - w, y - th + 1), (tx - w * 0.6, y - th - 3), (tx, y - th - 1),
                     (tx + w * 0.4, y - th - 4), (tx + w, y - th + 1)])
        sy = y - th * 0.6
        sx = x + math.sin(lean) * th * 0.6
        side = 1 if rng.random() < 0.5 else -1
        m |= m_seg(sx, sy, sx + side * th * 0.25, sy - th * 0.18, 0.6, 0.3)
    m |= m_poly([(x - w * 3.2, y + 1), (x - w * 0.9, y - h * 0.12), (x + w * 0.9, y - h * 0.12),
                 (x + w * 3.4, y + 1)])
    return m


def backdrop_sunken_bog() -> Backdrop:
    """Sunken Bog: drowned dead trees standing in still black water, low banks of mist, a far
    treeline lost in the murk."""
    bd = Backdrop("sunken_bog")
    rng = np.random.default_rng(3003)
    water_y = 97
    # Far treeline in the haze: a drowned forest fading into the murk.
    far = far_hills(bd, rng, 82.0, 8.0, 61, spikes=0.0)
    for x in np.sort(rng.uniform(-6, BW + 6, 40)):
        far |= dead_tree(rng, x, 84, rng.uniform(12, 30), lean=rng.uniform(-0.2, 0.2), depth=2,
                         spread=0.8)
    bd.layer(far, 0.0)
    # Two stepped mist tones, each a clear step lighter than the trees they swallow: a thin
    # upper bank and a denser low one.
    mist2 = mix(bd.haze, bd.amb, 0.3)
    mist = mix(bd.haze, bd.amb, 0.5)
    top1 = mist_top(62, 79, 4.0, 22.0, rag=1.2)
    sink_into_mist(bd, far, top1, bd.depth(0.0), mist2)
    bd.paint(mist_band(62, 79, 92, 4.0, 22.0, rag=1.2), mist2)
    # A nearer rank of tall dead trees, half lost in the mist.
    far2 = np.zeros((BH, BW), dtype=bool)
    for (x, h, lean) in ((66, 56, -0.06), (134, 48, 0.08), (170, 62, -0.1), (238, 52, 0.05),
                         (300, 44, 0.1), (98, 40, 0.12), (210, 38, -0.12)):
        far2 |= drowned_tree(rng, x, 90, h, lean)
    far2_moss = hang_moss(rng, far2, 0, BW, 28, 84, 18, 3, 8)
    bd.layer(far2 | far2_moss, 0.05)
    top2 = mist_top(63, 85, 2.5, 16.0, rag=1.0)
    sink_into_mist(bd, far2, top2 - 2, bd.depth(0.05), mist2, rows=3)
    bd.paint(far2 & (_YY >= top2[None, :] - 2) & (_YY < top2[None, :]), mist2)
    bd.paint(mist_band(63, 85, 92, 2.5, 16.0, rag=1.0), mist)
    # Middle: drowned trees standing in the water.
    mid = np.zeros((BH, BW), dtype=bool)
    specs = ((44, 58, 0.1, 0.0), (82, 34, -0.15, 0.45), (114, 50, 0.05, 0.0), (152, 30, 0.25, 0.5),
             (190, 54, -0.08, 0.0), (224, 38, 0.12, 0.4), (262, 46, -0.2, 0.0), (280, 26, 0.3, 0.55))
    for (x, h, lean, snap) in specs:
        mid |= drowned_tree(rng, x, water_y + 1, h, lean, snap)
    mid_moss = hang_moss(rng, mid, 0, BW, 30, water_y - 6, 34)
    bd.layer(mid | mid_moss, 0.56, rim=0.12)
    # Still water: dark, with reflected trunks and long thin glints of the mist.
    water = m_rect(0, water_y, BW, BH)
    bd.paint(water, bd.depth(0.6))
    refl = np.zeros((BH, BW), dtype=bool)
    for (x, h, lean, snap) in specs:
        for k in range(0, int(h * 0.35)):
            if rng.random() < 0.7:
                y = water_y + 1 + k
                xx = int(round(x - lean * k * 0.6))
                refl |= m_rect(xx - 1, y, xx + 1, y + 1)
    bd.paint(refl & water, bd.depth(0.75))
    for i in range(18):
        y = int(rng.integers(water_y + 2, BH - 3))
        x = int(rng.integers(0, BW - 10))
        L = int(rng.integers(5, 22))
        bd.paint(m_rect(x, y, x + L, y + 1) & water, mix(bd.depth(0.6), mist, 0.45))
    # Low mist rolling over the water in front of the trees.
    bd.paint(mist_band(64, 93, 101, 3.5, 18.0, rag=1.0), mist2)
    bd.paint(mist_band(65, 96, 100, 2.0, 12.0, rag=0.8), mist)
    # Near: two great drowned trees leaning in from the sides, knees and reeds in the water.
    near = dead_tree(np.random.default_rng(41), 24, BH + 1, 94, lean=0.08, depth=3, spread=0.9,
                     width=4.6, decay=0.72)
    near |= dead_tree(np.random.default_rng(46), 298, BH + 1, 88, lean=-0.1, depth=3,
                      spread=0.85, width=4.0, decay=0.72)
    for (x, w) in ((24, 4.6), (298, 4.0)):  # flared, drowned feet
        near |= m_poly([(x - w * 3.4, BH + 1), (x - w * 0.9, BH - 12), (x + w * 0.9, BH - 12),
                        (x + w * 3.6, BH + 1)])
    for (x, h) in ((52, 6), (60, 4), (244, 5), (252, 7), (262, 4)):  # cypress knees
        near |= m_poly([(x - 2.5, BH), (x - 0.5, BH - h), (x + 0.5, BH - h), (x + 2.5, BH)])
    reeds = np.zeros((BH, BW), dtype=bool)
    for x in list(range(60, 92, 3)) + list(range(200, 236, 3)):
        h = rng.uniform(6, 15)
        lean = rng.uniform(-2, 2)
        reeds |= m_seg(x + 0.5, BH, x + 0.5 + lean, BH - h, 0.3, 0.3)
        if rng.random() < 0.35:  # a cattail head
            reeds |= m_rect(x + lean * 0.9, BH - h - 1, x + lean * 0.9 + 1, BH - h + 3)
    near_moss = hang_moss(rng, near, 0, BW, 4, 90, 44, 4, 14)
    bd.layer(near | near_moss | reeds, 0.95, rim=0.25)
    bd.clean()
    return bd


# --- Hollow Throne backdrop

def crags(seed: int, base: float, amp: float, scale: float) -> np.ndarray:
    """Sharp mountain ridges (folded noise makes peaks instead of rolling hills)."""
    n1 = np.abs(lnoise(seed, scale, 3) - 0.5) * 2
    n2 = np.abs(lnoise(seed + 1, scale * 0.4, 2) - 0.5) * 2
    prof = base - (1 - n1) * amp - (1 - n2) * amp * 0.25
    return m_profile(prof)


def tower(x: float, w: float, top: float, base: float, roof: float = 0.0,
          battlements: bool = False) -> np.ndarray:
    """A castle tower: a shaft, then a pointed roof with eaves or a crown of battlements."""
    m = m_rect(x, top, x + w, base)
    if roof > 0:
        m |= m_poly([(x - 1.5, top + 0.5), (x + w / 2, top - roof), (x + w + 1.5, top + 0.5)])
    if battlements:
        m |= m_rect(x - 1, top - 1, x + w + 1, top + 1)
        for k in range(0, int(w) + 2, 3):
            m |= m_rect(x - 1 + k, top - 3, x + k + 1, top - 1)
    return m


def backdrop_hollow_throne() -> Backdrop:
    """Hollow Throne: the Hollow King's keep on its crag, spires against a blood moon, a long
    broken bridge, the throne fire glowing in a few windows."""
    bd = Backdrop("hollow_throne")
    rng = np.random.default_rng(4004)
    # A pale, sick moon behind everything.
    moon = mix(bd.haze, "#d9b7a4", 0.27)
    moon_dark = mix(moon, bd.haze, 0.35)
    disc = m_disc(236, 36, 17)
    bd.paint(disc, moon)
    bd.paint(m_disc(230, 31, 4.5) | m_disc(243, 42, 3.5) | m_disc(240, 27, 2.2), moon_dark)
    # A lighter limb on the upper left, where the light catches it, rounds the disc.
    limb = disc & ~(wshift(disc, 0, -1, False) & wshift(disc, -1, 0, False))
    limb &= _XX + _YY < 236 + 36 - 4
    bd.paint(limb, mix(moon, "#f2d6c4", 0.3))
    # Far crags in the red haze.
    far = crags(71, 88.0, 26.0, 46.0)
    bd.layer(far, 0.05)
    # Mid crags flanking the castle rock.
    mid_rock = crags(72, 98.0, 16.0, 30.0)
    bd.layer(mid_rock, 0.48)
    # The castle on its crag.
    rock = m_poly([(96, 121), (104, 98), (112, 90), (122, 84), (140, 80), (170, 79), (196, 82),
                   (212, 90), (222, 100), (232, 121)])
    keep = m_rect(146, 30, 176, 82)
    keep |= m_rect(144, 30, 178, 33)
    for k in range(0, 34, 4):
        keep |= m_rect(144 + k, 26, 146 + k, 30)
    spire = tower(156, 10, 14, 32, roof=12)
    left_t = tower(126, 11, 46, 82, roof=10)
    right_t = tower(188, 10, 42, 82, roof=11)
    far_t = tower(204, 7, 58, 84, battlements=True)
    wall = m_rect(114, 62, 214, 84)
    for k in range(0, 100, 4):
        wall |= m_rect(114 + k, 59, 116 + k, 62)
    hall = m_rect(116, 52, 146, 64) | m_poly([(114.5, 52.5), (131, 42), (147.5, 52.5)])
    castle = keep | spire | left_t | right_t | far_t | wall | hall
    # The gate (dark inside), and a banner on the spire.
    gate = m_rect(156, 70, 166, 84) | m_disc(161, 70, 5)
    castle |= m_seg(161, 3, 161, 0.5, 0.3, 0.3) & ~m_rect(0, 0, BW, 1)
    castle |= m_poly([(161.5, 2), (167, 3.5), (165, 5), (168, 7), (161.5, 6)])
    # The bridge: arches over the chasm toward the gate, broken in the middle.
    bridge = m_rect(20, 84, 116, 89)
    for k in range(6):
        ax = 24 + k * 15
        bridge &= ~(m_rect(ax, 92, ax + 10, 121) | m_disc(ax + 5, 92, 5))
    bridge |= m_rect(20, 89, 116, 121) & ~m_rect(0, 92, BW, 121) | m_rect(20, 89, 116, 92)
    for k in range(7):
        px_ = 20 + k * 15
        bridge |= m_rect(px_ - 1, 89, px_ + 4, 121)
    bridge &= ~m_poly([(58, 80), (70, 80), (69, 96), (66, 100), (62, 97), (59, 92)])
    castle |= bridge
    t_k = 0.78
    # The crag the keep stands on sits a step back toward the fog, so the keep keeps its base
    # against the near rocks; its lit upper-left edge catches the moon.
    bd.layer(rock & ~castle, 0.64, rim=0.12)
    bd.layer(castle, t_k, rim=0.16)
    # Moonlight down the keep's and towers' lit left sides.
    for part in (keep, left_t, right_t, hall):
        edge = part & ~wshift(part, -1, 0, False) & ~wshift(castle, -1, 0, False)
        bd.paint(edge & (_YY < 82), bd.rim(t_k, 0.22))
    bd.paint(gate & castle, bd.depth(1.0))
    # The throne fire in a few windows: dim red, brighter at the bottom of each.
    fire = mix("#e0603a", bd.depth(t_k), 0.3)
    fire_dim = mix("#a03030", bd.depth(t_k), 0.5)
    for (x, y, h) in ((152, 40, 5), (168, 40, 5), (160, 52, 6), (130, 56, 4), (191, 54, 4),
                      (159, 20, 4), (138, 56, 4)):
        bd.paint(m_rect(x, y, x + 2, y + h), fire_dim, keep=True)
        bd.paint(m_rect(x, y + h - 2, x + 2, y + h), fire, keep=True)
    bd.paint(m_disc(161, 62, 2.6), fire_dim, keep=True)
    bd.paint(m_disc(161, 62.6, 1.3), fire, keep=True)
    # Near: jagged rocks, a row of pikes, a dead tree.
    ground_d = 110 + (lnoise(81, 28.0) - 0.5) * 8
    near = m_profile(ground_d)
    near |= m_poly([(0, 121), (0, 70), (6, 66), (10, 74), (16, 70), (22, 82), (30, 88), (40, 100),
                    (46, 121)])
    near |= m_poly([(276, 121), (284, 94), (292, 86), (298, 78), (304, 82), (310, 72), (316, 76),
                    (320, 74), (320, 121)])
    for x in range(64, 104, 6):
        yb = ground_d[x] + 1
        h = rng.uniform(9, 14)
        near |= m_seg(x + 0.5, yb, x + 0.5 + rng.uniform(-1, 1), yb - h, 0.6, 0.3)
    near |= dead_tree(np.random.default_rng(83), 250, ground_d[250] + 2, 46, lean=-0.12, depth=3,
                      spread=0.9, width=2.4, decay=0.66)
    near |= tufts(rng, ground_d, 0.35)
    bd.layer(near, 0.95, rim=0.22)
    bd.clean()
    return bd


# --- Build --------------------------------------------------------------------------------------

def game_view(bd: Backdrop, fog_share: float = 0.37) -> np.ndarray:
    """How the game shows a backdrop (for review only): the sky renders as the fog colour and
    the backdrop, about 23 units from the combat camera, takes on about a third of the fog."""
    img = bd.rgba().astype(np.float64)
    fog = np.array([c * 255 for c in hex_to_rgb(bd.fog)])
    solid = img[..., 3:4] > 0
    rgb = np.where(solid, img[..., :3] * (1 - fog_share) + fog * fog_share, fog)
    out = np.concatenate([rgb, np.full((BH, BW, 1), 255.0)], -1)
    return np.rint(out).astype(np.uint8)


BACKDROPS = {
    "backdrop": "rotten_hollow",
    "backdrop_ashen_ruins": "ashen_ruins",
    "backdrop_sunken_bog": "sunken_bog",
    "backdrop_hollow_throne": "hollow_throne",
}


def build(ctx) -> None:
    textures = {
        "floor_tile": floor_tile,
        "cliff": cliff,
        "ruin_wall": ruin_wall,
    }
    imgs = {}
    for name, fn in textures.items():
        img = fn()
        assert img.shape == (T, T, 4) and (img[..., 3] == 255).all(), name
        imgs[name] = img
        ctx.save("sprites/env/%s.png" % name, img, tile=True)
    # Review sheet: every texture tiled 4x4 at 2x, the way many tiles meet on screen.
    row = np.concatenate([np.pad(np.tile(i, (4, 4, 1)), ((0, 0), (0, 4), (0, 0)))
                          for i in imgs.values()], 1)
    ctx.extra("tiles_4x4.png", row, scale=2)
    ctx.extra("tiles_1x.png", row, scale=1)
    # Review sheet: the old placeholders (top row) over the new textures, each tiled 3x3.
    old_dir = os.path.join(PREVIEW, "_old", "env")
    olds, news = [], []
    for name, img in imgs.items():
        path = os.path.join(old_dir, name + ".png")
        if os.path.exists(path):
            old = np.asarray(Image.open(path).convert("RGBA"))
            olds.append(np.pad(np.tile(old, (3, 3, 1)), ((0, 4), (0, 4), (0, 0))))
            news.append(np.pad(np.tile(img, (3, 3, 1)), ((0, 4), (0, 4), (0, 0))))
    if olds:
        ctx.extra("tiles_old_vs_new.png", np.concatenate([np.concatenate(olds, 1),
                                                          np.concatenate(news, 1)], 0), scale=2)

    views = []
    for file, look in BACKDROPS.items():
        bd = globals()["backdrop_" + look]()
        img = bd.rgba()
        a = img[..., 3]
        assert img.shape == (BH, BW, 4) and ((a == 0) | (a == 255)).all(), file
        ctx.save("sprites/env/%s.png" % file, img, scale=3)
        views.append(np.pad(game_view(bd), ((0, 4), (0, 0), (0, 0))))
    # Review sheet: every backdrop as the game shows it (sky = fog colour), at 1x and 3x.
    sheet = np.concatenate(views, 0)
    out = os.path.join(PREVIEW, ctx.module)
    preview(sheet, os.path.join(out, "backdrops_game_view.png"), scale=3, bgs=((0, 0, 0),))
    preview(sheet, os.path.join(out, "backdrops_game_view_1x.png"), scale=1, bgs=((0, 0, 0),))
