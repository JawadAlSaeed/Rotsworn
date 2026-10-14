"""Zone and arena props: lit billboard sprites standing on the ground (DESIGN.md 7.3).

dead_tree, rotten_tree, rock, pillar, lamp and glow_shroom are small 3D models rendered with the
shared camera and light (same look as the fighters); grass is drawn in 2D because it is a few
1-pixel blades. Every prop: alpha cut, outlined, its base on the second-to-last row, centred left
to right, at least 1 clear pixel on every side.

The game draws props with `fighter_sprite.gdshader`: `self_glow` makes the WHOLE texture emit
(colour x glow), so glowing props keep everything that should not glow dark (lamp iron, shroom
stems) and their glowing parts bright.

Models are built in a camera-aligned frame (`_face`): x = screen right, y = up, z = toward the
viewer, which makes trees and their branches easy to place by eye. Things that stand on the
ground are cut flat by `GroundCut` so every contact point lands on one pixel row.

Surface detail that must stay inside the silhouette (moss, rot, flat rock facets) is painted after
the render from the 3D hit point and normal of each pixel (`surface`), so it never adds bumps or
outline nubs to the shape.
"""
from __future__ import annotations

import dataclasses
import math
from typing import Callable, Sequence

import numpy as np

from kit.canvas import Canvas, rgba8
from kit.color import from_oklch, to_oklch
from kit.noise import fbm3
from kit.palette import INK, M, Material
from kit.post import cleanup, contours, edge_light, outline
from kit.render import DEFAULT_LIGHT, Camera, Frame, line3d, render, stamp
from kit.sdf import (Box, Capsule, Custom, Cylinder, Ellipsoid, Moved, Node, Prim, RoundCone,
                     SmoothUnion, Sphere, Subtract, Torus, Union, rot)

CAM_YAW = -28.0  # the kit Camera's default yaw and pitch
CAM_PITCH = 10.0
_R_YAW = rot(0.0, CAM_YAW, 0.0)
_R_PITCH = rot(CAM_PITCH, 0.0, 0.0)
_LIGHT = np.asarray(DEFAULT_LIGHT, float) / np.linalg.norm(DEFAULT_LIGHT)
N4 = ((0, -1), (-1, 0), (1, 0), (0, 1))


# --- Shared helpers ------------------------------------------------------------------------------


def _face(node: Node) -> Node:
    """Wraps a model authored in the camera-aligned frame (x = screen right) so the default
    3/4 camera sees it straight on."""
    return Moved(node, R=_R_YAW.T)


def _world(q: Sequence[float]) -> np.ndarray:
    """A camera-aligned point (see `_face`) in model space (for stamp / line3d anchors)."""
    return np.asarray(q, dtype=float) @ _R_YAW


def ink_outline(base: str, L: float = 0.2, C: float = 0.035) -> str:
    """A dark outline in the hue of `base`, never darker than palette.INK (the bible's darkest)."""
    _, _, h = to_oklch(base)
    L = max(L, to_oklch(INK)[0] + 0.005)
    return from_oklch(L, C, h)


def mat(name: str, base: str, below: int = 2, above: int = 2, outline_L: float = 0.2,
        **kw) -> Material:
    """Material.make with an outline that respects INK (see `ink_outline`)."""
    m = Material.make(name, base, below=below, above=above, **kw)
    if "outline" not in kw:
        m.outline = ink_outline(m.colors[0], outline_L)
    return m


class GroundCut(Node):
    """Cuts a model (camera-aligned frame) flat where it meets the ground. The cut follows the
    screen, not the world: everything below the pixel row of y = `level` goes, so roots in front
    and behind all end on the same row and the sprite stands on a clean flat base."""

    def __init__(self, child: Node, level: float = 0.0) -> None:
        self.child = child
        self.level = level
        self.c = math.cos(math.radians(CAM_PITCH))
        self.s = math.sin(math.radians(CAM_PITCH))

    def eval(self, P):
        d, p = self.child.eval(P)
        up = self.c * P[:, 1] - self.s * P[:, 2]
        return np.maximum(d, self.level - up), p

    def leaves(self):
        return self.child.leaves()


def knot_hole(frame: Frame, cam: Camera, at: Sequence[float], bark: Material, big: bool = False) -> None:
    """A dark knot hole in the bark facing the viewer."""
    rows = ([".oo.", "oxxo", "oxxo", ".oo."] if big else [".o.", "oxo", "oxo", ".o."])
    stamp(frame, cam, _world(at), rows, {"o": (bark, 0), "x": (HOLE, 0)}, origin=(1, 1))


def _crop(src: Frame, x0: int, y0: int, W: int, H: int) -> Frame:
    out = Frame(W, H)
    out.mats = list(src.mats)
    out.groups = list(src.groups)
    out.part = src.part[y0:y0 + H, x0:x0 + W].copy()
    out.idx = src.idx[y0:y0 + H, x0:x0 + W].copy()
    out.depth = src.depth[y0:y0 + H, x0:x0 + W].copy()
    out.light = src.light[y0:y0 + H, x0:x0 + W].copy()
    out.alpha = src.alpha[y0:y0 + H, x0:x0 + W].copy()
    out.fixed = [row[x0:x0 + W] for row in src.fixed[y0:y0 + H]]
    return out


def render_fit(model: Node, W: int, H: int, centre: str = "origin", pad: int = 24,
               ss: int = 3, name: str = "", **rkw) -> tuple[Frame, Camera]:
    """Renders `model` into a W x H frame with its lowest pixel on the second-to-last row and
    centred left to right ("origin": the model's x = 0 on the middle column, for things that
    stand on one point like trees; "bbox": the whole silhouette centred). Returns the frame and
    a camera that projects exactly onto it (for line3d / stamp overlays and `surface`)."""
    probe = Camera(W + 2 * pad, H + 2 * pad, cy=-0.5 - pad)
    big = render(model, probe, ss=ss, **rkw)
    ys, xs = np.nonzero(big.part >= 0)
    bottom = int(ys.max())
    k = H - 2 - bottom + pad
    if centre == "bbox":
        cx = int(round((int(xs.min()) + int(xs.max()) - 2 * pad - W + 1) / 2.0))
    else:
        cx = 0
    ox, oy = pad + cx, pad - k
    frame = _crop(big, ox, oy, W, H)
    cam = Camera(W, H, cx=float(cx), cy=-0.5 + k)
    cam.z0 = probe.z0
    # Anything cut off by the frame or touching its edge (no room for the outline)?
    inside = big.part[oy + 1:oy + H - 1, ox + 1:ox + W - 1] >= 0
    if inside.sum() != (big.part >= 0).sum():
        print("  warning: %s does not fit %dx%d with a 1 px margin (%d px outside)"
              % (name or "model", W, H, int((big.part >= 0).sum() - inside.sum())))
    return frame, cam


def surface(frame: Frame, cam: Camera, model: Node, eps: float = 0.06) -> tuple[np.ndarray, np.ndarray]:
    """The 3D hit point and surface normal of every solid pixel, in the camera-aligned frame
    (H, W, 3 each; NaN where empty). Used to paint moss, rot and facets onto the render."""
    H, W = frame.H, frame.W
    O, D = cam.rays(1)
    t = frame.depth.reshape(-1)
    ok = (frame.part.reshape(-1) >= 0) & np.isfinite(t)
    P = np.full((H * W, 3), np.nan)
    N = np.full((H * W, 3), np.nan)
    if ok.any():
        p = O[ok] + t[ok, None] * D
        k = np.array([[1, -1, -1], [-1, -1, 1], [-1, 1, -1], [1, 1, 1]], dtype=float)
        n = np.zeros_like(p)
        for row in k:
            d, _ = model.eval(p + row * eps)
            n += row[None, :] * d[:, None]
        n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-9
        P[ok] = p @ _R_YAW.T
        N[ok] = n @ _R_YAW.T
    return P.reshape(H, W, 3), N.reshape(H, W, 3)


def light_of(n_face: np.ndarray, wrap: float, ambient: float = 0.06) -> np.ndarray:
    """The kit's diffuse light for camera-aligned normals (..., 3), 0..1."""
    nv = n_face @ _R_PITCH.T
    ndl = nv @ _LIGHT
    return ambient + (1.0 - ambient) * np.clip((ndl + wrap) / (1.0 + wrap), 0.0, 1.0)


def ramp_index(m: Material, v: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(m.lo + v * (m.hi - m.lo)), 0, m.top()).astype(np.int32)


def components(mask: np.ndarray) -> list[list[tuple[int, int]]]:
    """4-connected pixel groups of a mask."""
    seen = np.zeros_like(mask, dtype=bool)
    out = []
    H, W = mask.shape
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        stack = [(int(y0), int(x0))]
        seen[y0, x0] = True
        comp = []
        while stack:
            y, x = stack.pop()
            comp.append((y, x))
            for dx, dy in N4:
                ny, nx = y + dy, x + dx
                if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        out.append(comp)
    return out


def paint(frame: Frame, mask: np.ndarray, m: Material, idx: np.ndarray, group: str,
          min_px: int = 3) -> int:
    """Repaints the masked pixels with material `m` (one new part), dropping specks smaller than
    `min_px` pixels. Returns the part id."""
    keep = np.zeros_like(mask)
    for comp in components(mask):
        if len(comp) >= min_px:
            for y, x in comp:
                keep[y, x] = True
    part = frame.add_part(m, group)
    frame.part = np.where(keep, part, frame.part)
    frame.idx = np.where(keep, np.clip(idx, 0, m.top()), frame.idx)
    return part


def prune(frame: Frame, groups: tuple[str, ...]) -> None:
    """Removes silhouette nubs: pixels of these groups held on by at most one solid neighbour
    (a lone pixel poking out of a rock reads as dirt on the sprite)."""
    for _ in range(2):
        solid = frame.part >= 0
        kill = []
        for y, x in zip(*np.nonzero(solid)):
            if frame.groups[frame.part[y, x]] not in groups:
                continue
            n = sum(1 for dx, dy in N4
                    if 0 <= x + dx < frame.W and 0 <= y + dy < frame.H and solid[y + dy, x + dx])
            if n <= 1:
                kill.append((y, x))
        for y, x in kill:
            frame.part[y, x] = -1
            frame.depth[y, x] = np.inf
        if not kill:
            break


def drop_to_base(frame: Frame) -> None:
    """Moves the picture down so its lowest pixel sits on the second-to-last row again."""
    ys = np.nonzero((frame.part >= 0).any(axis=1))[0]
    k = frame.H - 2 - int(ys.max())
    if k <= 0:
        return
    for name in ("part", "idx", "depth", "light", "alpha"):
        a = getattr(frame, name)
        b = np.roll(a, k, axis=0)
        b[:k] = -1 if name == "part" else (np.inf if name == "depth" else (255 if name == "alpha" else 0))
        setattr(frame, name, b)
    frame.fixed = [[None] * frame.W for _ in range(k)] + frame.fixed[:frame.H - k]


def despeckle(frame: Frame, groups: tuple[str, ...]) -> None:
    """Removes lone pixels the kit's `cleanup` misses because they sit between different parts
    (a canopy pixel left inside a rot patch, a bark speck between two trunk segments): a pixel of
    these groups whose four neighbours all show one other colour takes that colour."""
    H, W = frame.H, frame.W
    col = [[frame.color_at(x, y) if frame.part[y, x] >= 0 else None for x in range(W)]
           for y in range(H)]
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            p = frame.part[y, x]
            if p < 0 or frame.groups[p] not in groups:
                continue
            nb = [(x + dx, y + dy) for dx, dy in N4]
            cs = {col[ny][nx] for nx, ny in nb}
            if len(cs) != 1 or None in cs or col[y][x] in cs:
                continue
            nx, ny = nb[0]
            if frame.groups[frame.part[ny, nx]] not in groups:
                continue
            frame.part[y, x] = frame.part[ny, nx]
            frame.idx[y, x] = frame.idx[ny, nx]


def finish_prop(frame: Frame, contour_gap: float = 2.5, contour_steps: int = 2,
                skip_groups: tuple[str, ...] = (), clean_passes: int = 1,
                prune_groups: tuple[str, ...] = (), clean_groups: tuple[str, ...] = ()
                ) -> np.ndarray:
    if prune_groups:
        prune(frame, prune_groups)
        drop_to_base(frame)
    if clean_groups:
        despeckle(frame, clean_groups)
    if contour_gap > 0:
        contours(frame, contour_gap, contour_steps)
    cleanup(frame, passes=clean_passes)
    outline(frame, skip_groups=skip_groups)
    return frame.rgba()


class Ridged(RoundCone):
    """A tapered branch with bark ridges running round it (twisting along its length)."""

    def __init__(self, mat_: Material, a, b, ra: float, rb: float, ridges: float = 5.0,
                 amp: float = 0.3, twist: float = 0.15, s0: float = 0.0, **kw) -> None:
        super().__init__(mat_, a, b, ra, rb, **kw)
        u = self.b - self.a
        self.len = float(np.linalg.norm(u))
        self.u = u / (self.len + 1e-9)
        ref = np.array([0.0, 0.0, 1.0]) if abs(self.u[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
        e1 = np.cross(self.u, ref)
        self.e1 = e1 / (np.linalg.norm(e1) + 1e-9)
        self.e2 = np.cross(self.u, self.e1)
        self.ridges = ridges
        self.amp = amp
        self.twist = twist
        self.s0 = s0

    def eval(self, P):
        d, part = super().eval(P)
        if self.amp > 0:
            q = P - self.a
            ang = np.arctan2(q @ self.e2, q @ self.e1)
            along = q @ self.u + self.s0
            # Ridges fade out on thin twigs (radius < 1) so they stay clean lines.
            t = np.clip((q @ self.u) / max(self.len, 1e-6), 0.0, 1.0)
            r = self.ra + (self.rb - self.ra) * t
            k = np.clip(r - 0.6, 0.0, 1.0)
            d = d + self.amp * k * np.sin(self.ridges * ang + self.twist * along)
        return d, part


def branch(m: Material, pts: Sequence[Sequence[float]], radii: Sequence[float],
           group: str = "", ridged: bool = True, thin_r: float = 0.9, amp: float = 0.3,
           ridges: float = 5.0, twist: float = 0.18, bumps=None) -> list[Prim]:
    """A polyline limb as tapered segments (radius per point)."""
    out: list[Prim] = []
    s = 0.0
    for i in range(len(pts) - 1):
        a, b = np.asarray(pts[i], float), np.asarray(pts[i + 1], float)
        ra, rb = radii[i], radii[i + 1]
        thin = rb < thin_r
        if ridged:
            out.append(Ridged(m, a, b, ra, rb, ridges=ridges, amp=amp, twist=twist, s0=s,
                              group=group, thin=thin, bumps=bumps))
        else:
            out.append(RoundCone(m, a, b, ra, rb, group=group, thin=thin, bumps=bumps))
        s += float(np.linalg.norm(b - a))
    return out


def roots(m: Material, ends: Sequence[tuple[float, float, float, float]], group: str,
          top: float, r0: float, tip_r: float = 0.7) -> list[Prim]:
    """Roots gripping the ground: each leaves the trunk, runs low and ends in a tip that reaches
    just under the ground cut (so every tip lands on the base row). ends = (x, z, mid radius,
    mid height)."""
    s = math.sin(math.radians(CAM_PITCH))
    out: list[Prim] = []
    for ex, ez, r, lift in ends:
        mid = (ex * 0.6, lift, ez * 0.6)
        tip = (ex, s * ez - 0.25, ez)
        out += branch(m, [(ex * 0.1, top, ez * 0.1), mid, tip], [r0, r, tip_r],
                      group=group, ridged=False)
    return out


def bark_lines(frame: Frame, cam: Camera, trunk: Sequence[Sequence[float]], radii: Sequence[float],
               offsets: Sequence[float], m: Material, idx: int, y_range: tuple[float, float],
               group: str) -> None:
    """Dark grooves running up the front of a trunk (at these fractions of its radius)."""
    for off in offsets:
        pts = []
        for (x, y, z), r in zip(trunk, radii):
            if not y_range[0] <= y <= y_range[1]:
                continue
            dx = off * r
            pts.append(_world((x + dx, y, z + math.sqrt(max(r * r - dx * dx, 0.0)) - 0.1)))
        if len(pts) > 1:
            line3d(frame, cam, pts, m, idx, group=group, depth_bias=0.7)


def pixel_path(pts2d: Sequence[tuple[float, float]]) -> list[tuple[int, int]]:
    """A 1-pixel polyline through screen points with no doubled corners (pixel-perfect: of three
    pixels making an L, the middle one goes), so a twig reads as one clean stroke."""
    path: list[tuple[int, int]] = []
    for (x0, y0), (x1, y1) in zip(pts2d[:-1], pts2d[1:]):
        a = (int(math.floor(x0)), int(math.floor(y0)))
        b = (int(math.floor(x1)), int(math.floor(y1)))
        dx, dy = abs(b[0] - a[0]), -abs(b[1] - a[1])
        sx, sy = (1 if b[0] > a[0] else -1), (1 if b[1] > a[1] else -1)
        err = dx + dy
        x, y = a
        while True:
            if not path or path[-1] != (x, y):
                path.append((x, y))
            if (x, y) == b:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x += sx
            if e2 <= dx:
                err += dx
                y += sy
    out: list[tuple[int, int]] = []
    for p in path:
        if len(out) >= 2:
            (ax, ay), (bx, by) = out[-2], out[-1]
            if abs(p[0] - ax) == 1 and abs(p[1] - ay) == 1 and (bx == ax or by == ay):
                out[-1] = p
                continue
        out.append(p)
    return out


def twig(frame: Frame, cam: Camera, pts: Sequence[Sequence[float]], m: Material, idx: int,
         group: str, depth_bias: float = 0.4, tip: int = 0) -> list[tuple[int, int]]:
    """A 1-pixel twig through camera-aligned points (see `pixel_path`), drawn into the frame
    before the outline so it gets one too. Hidden behind nearer parts of the model. The last
    `tip` pixels are left out and returned, to be drawn after the outline (`draw_tip`) so the
    twig ends in a fine point rather than a blunt, outlined stub."""
    part = frame.add_part(m, group)
    proj = [cam.project(_world(p)) for p in pts]
    path = pixel_path([(x, y) for x, y, _ in proj])
    body = path[:len(path) - tip] if tip else path
    d0, d1 = proj[0][2], proj[-1][2]
    for k, (x, y) in enumerate(body):
        d = d0 + (d1 - d0) * k / max(len(path) - 1, 1) - depth_bias
        frame.put(x, y, part, idx, d)
    return path[len(body):]


def flatten_thin(frame: Frame, model: Node, idx: int) -> None:
    """Gives thin parts (twigs) one flat ramp colour: their per-pixel shading only flickers."""
    leaves = model.leaves()
    thin = np.array([leaf.thin for leaf in leaves] + [False] * (len(frame.mats) - len(leaves)))
    mask = (frame.part >= 0) & thin[np.maximum(frame.part, 0)]
    frame.idx = np.where(mask, idx, frame.idx)


# --- Materials -----------------------------------------------------------------------------------

BARK = mat("prop_bark", "#5a4a40", wrap=0.3)
BARK_PALE = mat("prop_bark_pale", "#9a8a72", below=1, above=1, wrap=0.3)  # fresh broken wood
ROT_BARK = mat("prop_rot_bark", "#4f4136", wrap=0.3)


def lch_mat(name: str, stops: Sequence[tuple[float, float, float]], outline_L: float = 0.2,
            **kw) -> Material:
    """A material from hand-picked OKLCH stops (darkest first), for ramps whose shadows must keep
    their own hue (the sickly olive canopy, lichen stone) instead of drifting toward the kit's
    shared shadow hue."""
    colors = [from_oklch(L, C, h) for L, C, h in stops]
    m = Material(name, colors, **kw)
    if "outline" not in kw:
        m.outline = ink_outline(colors[0], outline_L)
    return m


# Sickly olive leaves: the shade stays olive (hue ~110) rather than going blue-green.
CANOPY = lch_mat("prop_canopy", [(0.28, 0.042, 124.0), (0.35, 0.052, 120.0),
                                 (0.43, 0.064, 115.0), (0.515, 0.074, 110.0),
                                 (0.60, 0.078, 102.0)], wrap=0.35, ao=0.2, outline_L=0.19)
# Leaves the rot has killed: dead brown-olive, darker than the living canopy round them.
DEAD_LEAF = lch_mat("prop_dead_leaf", [(0.27, 0.042, 78.0), (0.335, 0.05, 84.0),
                                       (0.40, 0.056, 90.0)], wrap=0.35)
ROT = mat("prop_rot", "#6e3f78", below=2, above=1, wrap=0.4, shadow_chroma=0.85,
          outline="#2a1430")
# Weathered prop stone: a step darker than the ground tiles' stone and lichen-tinted (olive grey,
# not the tiles' violet grey), so rocks and pillars stand off the floor they sit on.
STONE = lch_mat("prop_stone", [(0.27, 0.018, 295.0), (0.345, 0.012, 330.0),
                               (0.415, 0.012, 95.0), (0.485, 0.016, 100.0),
                               (0.56, 0.017, 95.0)], wrap=0.25, ao=0.3, outline_L=0.17)
COLUMN = dataclasses.replace(STONE, name="prop_column", ao=0.35)
# The fresh face where the column snapped: paler, warmer stone than its weathered skin.
FRACTURE = lch_mat("prop_fracture", [(0.5, 0.022, 85.0), (0.58, 0.024, 82.0),
                                     (0.65, 0.022, 80.0)], wrap=0.3, outline=STONE.outline)
# The ground tiles' moss (env_tiles MOSS_DIM): muted, so props sit in the same world.
MOSS = mat("prop_moss", "#56683a", below=2, above=1, wrap=0.5, shadow_chroma=0.75,
           shadow_shift=6.0)
LAMP_IRON = mat("prop_lamp_iron", "#3d3f4a", spec=0.5, spec_power=10.0, wrap=0.2, step_l=0.07,
                outline=INK)
# Lamp iron lit warm by its own lantern (the pixels right next to the glass).
LAMP_SPILL = lch_mat("prop_lamp_spill", [(0.36, 0.045, 50.0), (0.45, 0.07, 58.0)], outline=INK)
LANTERN = Material("prop_lantern", M["glow_amber"].colors, emissive=True, glow_index=2,
                   outline=ink_outline("#c26a2a", 0.25))
SHROOM_CAP = mat("prop_shroom_cap", "#74e6e0", below=3, above=1, wrap=0.4, ao=0.3,
                 shadow_chroma=0.8, outline_L=0.24)
SHROOM_CAP.lo = 1.6
SHROOM_GILL = mat("prop_shroom_gill", "#2f6f73", below=1, above=1, wrap=0.5)
SHROOM_STEM = mat("prop_shroom_stem", "#2c3f45", below=1, above=2, wrap=0.5)
SOIL = mat("prop_shroom_soil", "#33362c", below=1, above=1, wrap=0.4)
HOLE = Material("prop_hole", [INK, "#2b2026"], hi=1.0, outline=INK)


# --- Dead tree -----------------------------------------------------------------------------------

DEAD_TRUNK = [(0, -1.5, 0), (1.4, 5.5, 0.2), (-0.6, 11, 0.4), (-1.4, 16.5, 0), (0.2, 21, 0)]
DEAD_TRUNK_R = [3.9, 3.0, 2.7, 2.5, 2.3]
DEAD_FORK = (0.2, 21.0, 0.0)
# The crown, drawn by hand (points, radii) in the camera-aligned frame: three limbs out of the
# fork, each bending at hard angles (old wood grows in zig-zags) and splitting into crooked
# branches. The left limb reaches up and out, the right one runs out low and flat and droops,
# the leader in the middle is the tallest: a wind-bent, uneven crown with clear sky between the
# limbs.
DEAD_LIMBS = [
    # Left limb: up and out, with a long branch out sideways that droops at its end.
    ([DEAD_FORK, (-4.0, 25.0, 0.5), (-8.0, 28.5, 0.8), (-11.0, 33.0, 0.8), (-15.0, 37.0, 0.5),
      (-17.5, 41.0, 0.3)], [2.0, 1.6, 1.35, 1.1, 0.9, 0.7]),
    ([(-8.0, 28.5, 0.8), (-12.5, 29.2, 1.0), (-16.0, 28.2, 1.0), (-19.0, 28.8, 0.8)],
     [0.95, 0.78, 0.62, 0.5]),
    ([(-11.0, 33.0, 0.8), (-10.0, 38.0, 0.9), (-11.5, 43.0, 0.8), (-10.5, 47.0, 0.6)],
     [0.9, 0.72, 0.58, 0.5]),
    # The leader up the middle, the tallest.
    ([DEAD_FORK, (1.2, 27.0, -0.5), (-0.5, 32.5, -0.8), (1.5, 38.0, -0.8), (0.5, 43.0, -0.6),
      (2.0, 47.5, -0.4)], [2.05, 1.75, 1.45, 1.2, 0.95, 0.72]),
    ([(0.5, 43.0, -0.6), (-3.0, 47.0, -0.6), (-4.5, 50.5, -0.5)], [0.75, 0.6, 0.5]),
    ([(1.5, 38.0, -0.8), (5.5, 41.0, -0.6), (7.5, 44.5, -0.5)], [0.8, 0.62, 0.5]),
    # Right limb: low, reaching out flat, a branch hanging under it.
    ([DEAD_FORK, (4.0, 24.0, -0.3), (8.0, 25.5, -0.5), (12.0, 28.5, -0.6), (15.5, 31.0, -0.6),
      (19.0, 32.5, -0.4)], [1.95, 1.6, 1.35, 1.1, 0.9, 0.68]),
    ([(15.5, 31.0, -0.6), (16.5, 35.5, -0.5), (18.5, 38.5, -0.4)], [0.75, 0.6, 0.5]),
    ([(8.0, 25.5, -0.5), (11.0, 23.8, -0.2), (13.5, 22.5, 0.0)], [0.85, 0.65, 0.5]),
]
# 1-pixel twigs out of the branch ends (camera-aligned points): crooked, splaying outward at
# 30 to 60 degrees, the ones on the low right limb drooping or hooked, their tips at many
# heights. Their last two pixels are drawn after the outline so each ends in a fine point.
DEAD_TWIGS = [
    [(-17.5, 41.0, 0.3), (-19.5, 44.0, 0.3), (-22.0, 46.0, 0.3)],
    [(-19.0, 28.8, 0.8), (-21.0, 28.0, 0.8), (-22.5, 25.5, 0.8)],
    [(-10.5, 47.0, 0.6), (-12.0, 50.5, 0.6), (-14.5, 52.5, 0.6)],
    [(-0.5, 32.5, -0.8), (-4.5, 34.5, -0.8), (-6.0, 37.5, -0.8)],
    [(2.0, 47.5, -0.4), (3.5, 52.0, -0.4), (2.5, 56.0, -0.4), (4.5, 59.5, -0.4)],
    [(-4.5, 50.5, -0.5), (-6.5, 54.0, -0.5), (-9.0, 55.5, -0.5)],
    [(7.5, 44.5, -0.5), (10.5, 47.0, -0.5), (11.5, 50.5, -0.5)],
    [(18.5, 38.5, -0.4), (21.0, 41.5, -0.4), (21.5, 44.0, -0.4)],
    [(19.0, 32.5, -0.4), (21.0, 31.5, -0.4), (22.0, 29.0, -0.4)],
    [(13.5, 22.5, 0.0), (15.5, 21.5, 0.0), (16.5, 19.0, 0.0)],
]
# A short stub where a lower limb snapped off, its broken end pale.
DEAD_STUB = ([(-0.2, 12.0, 1.2), (-4.0, 14.0, 1.6), (-6.5, 14.4, 1.8)], [1.5, 1.15, 1.0])
TWIG_TIP = 2  # pixels at the end of each twig drawn without an outline


def dead_tree_model(limbs=None) -> Node:
    m = BARK
    parts: list[Prim] = []
    # Trunk: an S-bend, with ridged bark twisting up it.
    parts += branch(m, DEAD_TRUNK, DEAD_TRUNK_R, group="tree", amp=0.22, ridges=4, twist=0.22)
    parts += roots(m, [(-6.0, 0.8, 1.2, 1.0), (5.6, 1.2, 1.1, 0.9), (1.6, 4.6, 1.0, 0.8),
                       (-2.6, -3.6, 1.0, 0.9)], "tree", 4.0, 2.2)
    for pts, radii in (limbs or DEAD_LIMBS):
        parts += branch(m, pts, radii, group="tree", ridged=False)
    parts += branch(m, *DEAD_STUB, group="tree", ridged=False)
    return _face(GroundCut(SmoothUnion(*parts, k=1.0)))


def make_dead_tree(limbs=None, rim: bool = True, flat: bool = True) -> np.ndarray:
    model = dead_tree_model(limbs)
    frame, cam = render_fit(model, 48, 64, name="dead_tree")
    if flat:
        flatten_thin(frame, model, 2)
    tips = []
    for pts in DEAD_TWIGS:
        tips.append(twig(frame, cam, pts, BARK, 2, "tree", tip=TWIG_TIP))
    bark_lines(frame, cam, DEAD_TRUNK, DEAD_TRUNK_R, (-0.45, 0.35), BARK, 1, (4.0, 20.0), "tree")
    knot_hole(frame, cam, (0.6, 7.0, 2.9), BARK, big=True)
    # The pale broken end of the snapped limb (two pixels: fresh wood and its shaded edge).
    end = DEAD_STUB[0][-1]
    stamp(frame, cam, _world((end[0] - 0.3, end[1], end[2])), ["p", "m"],
          {"p": (BARK_PALE, 1), "m": (BARK_PALE, 0)}, origin=(0, 0), always=True)
    if rim:
        edge_light(frame, 1, ("top", "left"))
    rgba = finish_prop(frame, clean_groups=("tree",))
    for tail in tips:
        draw_tip(rgba, tail, [BARK.colors[1], BARK.colors[0]])
    return rgba


def draw_tip(rgba: np.ndarray, tail: Sequence[tuple[int, int]], colors: Sequence[str]) -> None:
    """The fine end of a twig: single pixels drawn after the outline, darkening to the point."""
    H, W = rgba.shape[:2]
    for k, (x, y) in enumerate(tail):
        if 1 <= x < W - 1 and 1 <= y < H - 1:
            rgba[y, x] = rgba8(colors[min(k, len(colors) - 1)])


# --- Rotten tree ---------------------------------------------------------------------------------

# The whole tree is modelled at 1 unit = 1 pixel, then scaled up to fill its 64 x 80 frame.
ROT_SCALE = 1.08


@dataclasses.dataclass(frozen=True)
class Lobe:
    """One leaf mass of the crown (camera-aligned frame, before scaling). `tier` is the ramp
    index of the lit band along its top (the crown's upper masses catch more light); `scallops`
    and `phase` shape its leafy outline."""

    x: float
    y: float
    z: float
    rx: float
    ry: float
    rz: float
    tier: int
    scallops: int
    phase: float

    @property
    def c(self) -> np.ndarray:
        return np.array([self.x, self.y, self.z])

    @property
    def s(self) -> np.ndarray:
        return np.array([self.rx, self.ry, self.rz])


# Six big leaf masses: a crown top, a mass up on the right, a heavy left side drooping low over
# the left limb, a low right mass the right limb runs into, and one in front over the fork.
ROT_LOBES = [
    Lobe(-1.5, 60.0, -2.0, 11.5, 9.0, 9.0, 4, 12, 0.4),
    Lobe(11.0, 56.0, -3.0, 8.0, 7.0, 7.0, 4, 9, 1.3),
    Lobe(-12.5, 50.5, 0.0, 8.5, 7.0, 7.0, 3, 10, 0.9),
    Lobe(-19.0, 41.5, 0.5, 6.2, 5.2, 6.0, 3, 7, 0.1),
    Lobe(16.0, 45.5, 0.0, 7.0, 5.6, 6.0, 3, 8, 1.9),
    Lobe(1.0, 45.0, 4.0, 9.5, 6.2, 6.0, 3, 11, 0.6),
]
LOBE_SCALLOP = 2.0  # how deep the notches between the leafy scallops of an outline are (px)
# Bites the rot has taken out of the crown's edge (x, y, z, radius; before scaling).
ROT_BITES: list[tuple[float, float, float, float]] = []
# Rot sores: (x, y before scaling, radius in px, seed, vertical squash). Wet patches that spread
# along the dark pockets between the leaf masses; two sit on the crown's lower edge so the rot
# can drip off it.
SORES = [(-6.0, 53.0, 4.6, 1, 1.1), (13.0, 41.0, 4.2, 2, 1.1), (-19.0, 37.5, 3.8, 3, 1.2)]
# Drips: (x hint before scaling, length in px). Each drips from the nearest column within 4 px
# where the lowest crown pixel is rot and only sky lies below it.
DRIPS = [(-19.0, 3), (13.0, 2)]

ROT_TRUNK = [(0, -1.5, 0), (2.4, 5.5, 0.3), (-0.6, 11, 0.4), (1.8, 16.5, 0), (0.2, 22, 0)]
ROT_TRUNK_R = [5.6, 4.5, 4.0, 3.7, 3.4]
ROT_FORK = (0.2, 22.0, 0.0)
# Limbs out of the fork: (points, radii). Each bends at elbows; the left one leaves low and
# runs out nearly level, the right one rises steeply, then bends out under its leaf mass.
ROT_LIMBS = [
    ([ROT_FORK, (-4.0, 26.0, 0.6), (-10.0, 29.0, 1.0), (-14.0, 35.0, 0.8), (-17.0, 39.0, 0.5)],
     [3.0, 2.3, 1.7, 1.3, 1.0]),
    ([ROT_FORK, (4.0, 28.0, 0.0), (8.0, 31.0, -0.3), (13.0, 36.0, -0.5), (16.0, 42.0, -0.5)],
     [2.8, 2.1, 1.6, 1.2, 0.9]),
    ([ROT_FORK, (1.5, 30.0, 2.0), (0.0, 39.0, 2.0)], [2.6, 2.0, 1.6]),
]
# A short snapped stub on the right limb's elbow.
ROT_STUB = ([(8.0, 31.0, -0.3), (11.5, 30.2, 0.5)], [1.15, 0.95])
# Bare dead twigs poking out of the crown where the rot has killed the leaves (camera-aligned
# points before scaling); their last pixels are drawn after the outline.
ROT_TWIGS = [
    [(16.0, 42.0, -0.5), (20.5, 44.5, -0.5), (24.5, 44.0, -0.5)],
    [(-7.0, 63.0, 0.0), (-8.5, 67.5, 0.0), (-11.5, 70.0, 0.0)],
]


def lobe_node(lb: Lobe) -> Node:
    """A leaf mass: an ellipsoid whose outline is cut into leafy scallops (round bumps with
    sharp notches between them)."""
    s = lb.s
    k = min(lb.rx, lb.ry, lb.rz)

    def fn(Q):
        e = (np.linalg.norm(Q / s, axis=1) - 1.0) * k
        th = np.arctan2(Q[:, 1] / lb.ry, Q[:, 0] / lb.rx)
        notch = 1.0 - np.sqrt(np.abs(np.cos(0.5 * lb.scallops * th + lb.phase)))
        return (e + LOBE_SCALLOP * notch) * 0.7

    return Custom(CANOPY, fn, pos=lb.c, group="canopy")


def rotten_tree_parts() -> tuple[Node, Node, list[Prim]]:
    """(wood, canopy, lobe leaves) of the rotten tree, camera-aligned frame."""
    m = ROT_BARK
    trunk = branch(m, ROT_TRUNK, ROT_TRUNK_R, group="trunk", amp=0.5, ridges=5, twist=0.3)
    wood: list[Prim] = list(trunk)
    # Burls: knobbly swellings on the trunk.
    wood.append(Sphere(m, (3.9, 9.0, 2.0), 2.1, group="trunk", bumps=(0.3, 0.8, 41)))
    wood.append(Sphere(m, (-2.8, 15.5, 2.4), 1.6, group="trunk", bumps=(0.3, 0.8, 42)))
    wood += roots(m, [(-8.0, 1.0, 1.6, 1.3), (7.6, 1.5, 1.5, 1.2), (3.6, -4.6, 1.3, 1.1),
                      (-4.6, -4.2, 1.3, 1.1), (-1.2, 5.6, 1.3, 1.0)], "trunk", 4.5, 3.4, tip_r=0.8)
    for pts, radii in ROT_LIMBS:
        wood += branch(m, pts, radii, group="trunk", amp=0.35, ridges=4, twist=0.25)
    wood += branch(m, *ROT_STUB, group="trunk", ridged=False)
    lobes = [lobe_node(lb) for lb in ROT_LOBES]
    canopy: Node = Union(*lobes)
    if ROT_BITES:
        canopy = Subtract(canopy, Union(*[Sphere(CANOPY, (x, y, z), r) for x, y, z, r in ROT_BITES]),
                          k=0.3)
    return GroundCut(SmoothUnion(*wood, k=1.4)), canopy, lobes


class Scaled(Node):
    """Scales a whole model up (or down) about the origin by `k`."""

    def __init__(self, child: Node, k: float) -> None:
        self.child = child
        self.k = k

    def eval(self, P):
        d, p = self.child.eval(P / self.k)
        return d * self.k, p

    def leaves(self):
        return self.child.leaves()


def rotten_tree_model() -> tuple[Node, list[Prim]]:
    wood, canopy, lobes = rotten_tree_parts()
    return _face(Scaled(Union(wood, canopy), ROT_SCALE)), lobes


def _smooth(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _rs(pts: Sequence[Sequence[float]]) -> list[tuple[float, float, float]]:
    """Authored rotten-tree points scaled like the model (for overlays)."""
    return [tuple(float(v) * ROT_SCALE for v in q) for q in pts]


def _groups_of(frame: Frame) -> np.ndarray:
    groups = np.array(frame.groups + [""])
    return groups[np.where(frame.part >= 0, frame.part, len(frame.groups))]


def _shift(a: np.ndarray, dx: int, dy: int, fill) -> np.ndarray:
    """a[y + dy, x + dx] at every (y, x) (fill outside the picture)."""
    H, W = a.shape
    out = np.full_like(a, fill)
    ys0, ys1 = max(0, -dy), min(H, H - dy)
    xs0, xs1 = max(0, -dx), min(W, W - dx)
    out[ys0:ys1, xs0:xs1] = a[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx]
    return out


# Light thresholds of the lobe shading (smooth lobe light, 0..1).
LOBE_MID = 0.6    # above: the mass's lit body, below: its shaded body
LOBE_BAND = 0.5    # the lit band along an upper-left edge needs at least this much light
LOBE_BAND2 = 0.72  # ... and a second pixel of it this much


def shade_lobes(frame: Frame, Q: np.ndarray, lobe_parts: Sequence[int]
                ) -> tuple[np.ndarray, np.ndarray]:
    """Shades the crown mass by mass, like hand-painted foliage: each leaf mass lit by its own
    smooth shape (no per-leaf noise), its body in two values, a lit band along its upper-left
    edge (on the silhouette and where it overlaps a mass behind it) and a dark pocket under any
    mass hanging in front of it. Returns (lobe id per pixel, -1 elsewhere; pocket mask)."""
    H, W = frame.H, frame.W
    lid = np.full((H, W), -1)
    for i, p in enumerate(lobe_parts):
        lid[frame.part == p] = i
    leaf = lid >= 0
    n = np.zeros((H, W, 3))
    n[..., 2] = 1.0
    for i, lb in enumerate(ROT_LOBES):
        m = lid == i
        if m.any():
            g = (Q[m] - lb.c) / (lb.s ** 2)
            n[m] = g / (np.linalg.norm(g, axis=1, keepdims=True) + 1e-9)
    v = np.where(leaf, light_of(n, CANOPY.wrap), 0.0)
    tiers = np.array([lb.tier for lb in ROT_LOBES] + [0])
    tier = tiers[lid]
    idx = np.where(v > LOBE_MID, tier - 1, tier - 2)
    depth = np.where(leaf, frame.depth, np.inf)
    solid = frame.part >= 0
    sdepth = np.where(solid, frame.depth, np.inf)

    def open_toward(dx: int, dy: int) -> np.ndarray:
        """This pixel's neighbour at (dx, dy) is sky, or a mass (or wood) behind this one."""
        nl = _shift(lid, dx, dy, -1)
        nd = _shift(sdepth, dx, dy, np.inf)
        return leaf & (nl != lid) & ((nd == np.inf) | (nd > depth + 1.0))

    edge1 = open_toward(0, -1) | open_toward(-1, 0) | open_toward(-1, -1)
    edge2 = (open_toward(0, -2) | open_toward(-2, 0)) & ~edge1
    up = n[..., 1] > -0.15
    band = (edge1 & up & (v > LOBE_BAND)) | (edge2 & up & (v > LOBE_BAND2))
    idx = np.where(band, tier, idx)
    # Pockets: under the lower edge of a mass hanging in front of this one.
    pocket = np.zeros((H, W), dtype=bool)
    for dx, dy in ((0, -1), (0, -2), (-1, -1), (1, -1)):
        nl = _shift(lid, dx, dy, -1)
        nd = _shift(depth, dx, dy, np.inf)
        pocket |= leaf & (nl >= 0) & (nl != lid) & (nd < depth - 1.0)
    idx = np.where(pocket & ~band, tier - 3, idx)
    frame.idx = np.where(leaf, np.clip(idx, 0, CANOPY.top()), frame.idx)
    return lid, pocket


def make_rotten_tree() -> np.ndarray:
    model, lobes = rotten_tree_model()
    frame, cam = render_fit(model, 64, 80, name="rotten_tree")
    Q, Nn = surface(frame, cam, model)
    Q = Q / ROT_SCALE
    solid = frame.part >= 0
    g = _groups_of(frame)
    wood = solid & (g == "trunk")
    y = np.nan_to_num(Q[..., 1])
    x = np.nan_to_num(Q[..., 0])
    lid, pocket = shade_lobes(frame, Q, [lb.part for lb in lobes])
    leaf = lid >= 0
    # Shade under the crown on the limbs and upper trunk (one step: the limbs stay readable).
    frame.idx = np.where(wood & (y > 21.0), np.maximum(frame.idx - 1, 0), frame.idx)
    # Light still catches the tops of the limbs between the leaves.
    rim = np.zeros_like(wood)
    rim[1:] = wood[1:] & ~solid[:-1]
    rim &= (y > 20.0) & (y < 42.0)
    frame.idx = np.where(rim, np.minimum(frame.idx + 1, ROT_BARK.top()), frame.idx)

    # Rot: wet violet patches spreading along the dark pockets between the leaf masses, the
    # leaves round them dying to a dead brown-olive.
    tiers = np.array([lb.tier for lb in ROT_LOBES] + [0])
    rel = np.where(leaf, frame.idx - tiers[lid] + 3, 0)
    dark = np.clip(1.0 - rel / 3.0, 0.0, 1.0) + 0.6 * pocket
    score = np.full(frame.part.shape, -9.0)
    dying = np.full(frame.part.shape, -9.0)
    nq = np.nan_to_num(Q).reshape(-1, 3)
    for sx, sy, sr, seed, squash in SORES:
        n = fbm3(nq * 0.7, 90 + seed, octaves=3).reshape(score.shape)
        s = 1.0 - np.hypot(x - sx, (y - sy) * squash) / sr + 0.9 * n + 0.5 * dark
        score = np.maximum(score, s)
        below = np.clip((sy - y) / sr, 0.0, 1.0)
        dn = fbm3(nq * 0.45, 70 + seed, octaves=2).reshape(score.shape)
        dd = 1.0 - np.hypot(x - sx, (y - sy) * 1.2) / (sr * 1.45) + 0.6 * dn + 0.3 * below
        dying = np.maximum(dying, dd)
    rot_px = leaf & (score > 0.5)
    dead = leaf & (dying > 0.5) & ~rot_px
    paint(frame, dead, DEAD_LEAF, np.array([0, 1, 2, 2, 2])[np.clip(rel, 0, 4)], "canopy",
          min_px=4)
    # Wet rot: its edge the base violet, its body darker, a darkest core only at the heart of
    # each sore.
    inner = rot_px & _shift(rot_px, 0, -1, False) & _shift(rot_px, 0, 1, False) \
        & _shift(rot_px, -1, 0, False) & _shift(rot_px, 1, 0, False)
    core = inner & _shift(inner, 0, -1, False) & _shift(inner, 0, 1, False) \
        & _shift(inner, -1, 0, False) & _shift(inner, 1, 0, False)
    rot_idx = np.where(core, 0, np.where(inner, 1, 2))
    paint(frame, rot_px, ROT, rot_idx, "rot", min_px=4)

    bark_lines(frame, cam, _rs(ROT_TRUNK), [r * ROT_SCALE for r in ROT_TRUNK_R], (-0.55, 0.45),
               ROT_BARK, 1, (4.0 * ROT_SCALE, 22.0 * ROT_SCALE), "trunk")
    # The rot is in the wood too: a violet-lipped knot hole weeping down the bark.
    hole = _rs([(-0.4, 12.5, 4.0)])[0]
    stamp(frame, cam, _world(hole), [".oo.", "oxxo", "oxxo", ".oo."],
          {"o": (ROT, 1), "x": (HOLE, 0)}, origin=(1, 1))
    hx, hy, _ = cam.project(_world(hole))
    seep_x = int(math.floor(hx))
    g = _groups_of(frame)
    for k, ci in ((3, 1), (4, 1), (5, 0), (6, 0)):
        yy = int(math.floor(hy)) + k
        if frame.part[yy, seep_x] >= 0 and g[yy, seep_x] == "trunk":
            frame.put(seep_x, yy, frame.add_part(ROT, "trunk"), ci, -np.inf)
    # The snapped stub's broken end: one pixel of the bark's lit step.
    sx_, sy_, _ = cam.project(_world(_rs([ROT_STUB[0][-1]])[0]))
    if frame.part[int(sy_), int(sx_)] >= 0:
        frame.idx[int(sy_), int(sx_)] = ROT_BARK.top() - 1

    tips = [twig(frame, cam, _rs(pts), ROT_BARK, 2, "trunk", tip=TWIG_TIP) for pts in ROT_TWIGS]
    g = _groups_of(frame)
    drips = drip_columns(frame, cam, g)
    rgba = finish_prop(frame, contour_gap=4.0, contour_steps=1,
                       clean_groups=("canopy", "rot", "trunk"))
    for tail in tips:
        draw_tip(rgba, tail, [ROT_BARK.colors[1], ROT_BARK.colors[0]])
    rot_drips(rgba, drips)
    return rgba


def drip_columns(frame: Frame, cam: Camera, g: np.ndarray) -> list[tuple[int, int, int]]:
    """Where rot drips off the crown: (x, y of the crown's lowest pixel, length) for each of
    DRIPS, at a column whose lowest canopy pixel is rot with only sky below it."""
    crown = (g == "canopy") | (g == "rot")
    out = []
    H = frame.H
    for hx, length in DRIPS:
        px, _, _ = cam.project(_world((hx * ROT_SCALE, 40.0, 0.0)))
        best = None
        for x in range(frame.W):
            ys = np.nonzero(crown[:, x])[0]
            if len(ys) == 0:
                continue
            y = int(ys.max())
            if g[y, x] != "rot" or y + length + 2 >= H:
                continue
            if (frame.part[y + 1:y + length + 3, max(x - 1, 0):x + 2] >= 0).any():
                continue
            d = abs(x + 0.5 - px)
            if d <= 4.0 and (best is None or d < best[0]):
                best = (d, x, y)
        if best is not None:
            out.append((best[1], best[2], length))
    return out


def rot_drips(rgba: np.ndarray, drips: Sequence[tuple[int, int, int]]) -> None:
    """Rot dripping off the crown's lower edge: a 1-pixel run drawn after the outline (so it
    stays one pixel wide), starting in the outline row under the rot and ending in the darkest
    rot colour."""
    for x, y, length in drips:
        for k in range(1, length + 1):
            c = ROT.colors[0] if k == length else ROT.colors[1]
            rgba[y + k, x] = rgba8(c)


# --- Rock ----------------------------------------------------------------------------------------


class Facets:
    """A faceted boulder: an ellipsoid of half sizes `size` cut by planes (a ring of side faces,
    a ring of upper faces and a top), so it reads as broken stone with flat faces that catch the
    light in clean bands. `which(Q)` tells which face a surface point is on."""

    def __init__(self, centre: Sequence[float], size: Sequence[float], seed: int, ring: int = 6,
                 upper: int = 3, round_r: float = 0.2, ell_scale: float = 1.08,
                 cuts: Sequence[tuple[Sequence[float], float]] = ()) -> None:
        rng = np.random.default_rng(seed)
        dirs = []
        for i in range(ring):
            az = 2 * math.pi * (i + rng.uniform(-0.2, 0.2)) / ring
            el = math.radians(rng.uniform(0.0, 18.0))
            dirs.append((math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el)))
        for i in range(upper):
            az = 2 * math.pi * (i + 0.5 + rng.uniform(-0.25, 0.25)) / upper
            el = math.radians(rng.uniform(40.0, 58.0))
            dirs.append((math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el)))
        dirs.append((rng.uniform(-0.15, 0.15), 1.0, rng.uniform(-0.15, 0.15)))
        nrm = np.asarray(dirs, float)
        self.nrm = nrm / np.linalg.norm(nrm, axis=1, keepdims=True)
        self.s = np.asarray(size, float)
        self.h = np.sqrt(((self.nrm * self.s) ** 2).sum(axis=1)) * rng.uniform(0.86, 0.95, len(self.nrm))
        # Extra planes (normal, distance from the centre) that cut the silhouette itself: a flat
        # shelf, a chipped corner.
        for n_, h_ in cuts:
            n_ = np.asarray(n_, float) / np.linalg.norm(n_)
            self.nrm = np.vstack([self.nrm, n_])
            self.h = np.append(self.h, h_)
        self.c = np.asarray(centre, float)
        self.k = round_r
        self.ell_scale = ell_scale

    def __call__(self, Q: np.ndarray) -> np.ndarray:
        q = Q - self.c
        d = q @ self.nrm.T - self.h[None, :]
        k = self.k
        m = d.max(axis=1)
        planes = m + k * np.log(np.exp((d - m[:, None]) / k).sum(axis=1)) - k * 0.6
        s = self.s * self.ell_scale
        ell = (np.linalg.norm(q / s, axis=1) - 1.0) * s.min()
        bottom = -q[:, 1] - self.s[1] * 0.75
        return np.maximum(np.maximum(planes, ell), bottom)

    def which(self, Q: np.ndarray) -> np.ndarray:
        return np.argmax((Q - self.c) @ self.nrm.T - self.h[None, :], axis=1)


# A flat top shelf and a chipped upper-left corner cut the outline itself, so the boulder reads
# as broken, angular stone (like the pillar), not a smooth bun.
ROCK_MAIN = Facets((-1.5, 6.5, 0.0), (11.8, 9.6, 8.5), seed=21, ring=7, upper=4, ell_scale=1.25,
                   cuts=[((0.15, 1.0, 0.1), 6.8), ((-0.85, 0.55, 0.2), 9.6)])
ROCK_SIDE = Facets((9.5, 2.8, 5.0), (4.4, 3.8, 3.8), seed=9, ring=5, upper=2)


def rock_model() -> Node:
    body = Custom(STONE, ROCK_MAIN, group="rock")
    small = Custom(STONE, ROCK_SIDE, group="pebble")
    return _face(GroundCut(Union(body, small)))


def flat_facets(frame: Frame, Q: np.ndarray, Nn: np.ndarray, parts: dict[int, Facets],
                m: Material) -> np.ndarray:
    """Shades each facet of these parts with one flat colour (its plane's light) and returns the
    facet id per pixel (-1 elsewhere). Pixels on the rounded ellipsoid keep their own normal."""
    fid = np.full(frame.part.shape, -1)
    for part, fac in parts.items():
        mask = frame.part == part
        if not mask.any():
            continue
        q = Q[mask]
        d = (q - fac.c) @ fac.nrm.T - fac.h[None, :]
        w = np.argmax(d, axis=1)
        on_plane = d[np.arange(len(w)), w] > -0.45
        n = np.where(on_plane[:, None], fac.nrm[w], Nn[mask])
        # Weathered stone: the shadow side a step darker than plain light gives.
        frame.idx[mask] = ramp_index(m, np.clip(light_of(n, m.wrap) * 1.05 - 0.05, 0.0, 1.0))
        fid[mask] = np.where(on_plane, w + 100 * part, -1)
    return fid


def crease_lines(frame: Frame, fid: np.ndarray) -> None:
    """Where two facets meet in the same colour, the lower one's edge goes one step darker, so
    every face edge reads."""
    H, W = fid.shape
    dark = np.zeros_like(fid, dtype=bool)
    for y in range(H):
        for x in range(W):
            if fid[y, x] < 0:
                continue
            for dx, dy in ((0, -1), (-1, 0), (1, 0)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < W and 0 <= ny < H) or fid[ny, nx] < 0 or fid[ny, nx] == fid[y, x]:
                    continue
                if frame.idx[ny, nx] == frame.idx[y, x] and frame.part[ny, nx] == frame.part[y, x]:
                    dark[y, x] = True
    frame.idx = np.where(dark, np.maximum(frame.idx - 1, 0), frame.idx)


def make_rock() -> np.ndarray:
    model = rock_model()
    frame, cam = render_fit(model, 32, 24, centre="bbox", name="rock")
    Q, Nn = surface(frame, cam, model)
    leaves = model.leaves()
    fid = flat_facets(frame, Q, Nn, {leaves[0].part: ROCK_MAIN, leaves[1].part: ROCK_SIDE}, STONE)
    crease_lines(frame, fid)
    # Moss in ragged patches on the upward faces of the big stone only.
    up = np.nan_to_num(Nn[..., 1])
    n = fbm3(np.nan_to_num(Q).reshape(-1, 3) * np.array([0.22, 0.3, 0.22]), 33, octaves=2)
    n = n.reshape(up.shape)
    moss = (frame.part == leaves[0].part) & (up > 0.5) & (n + 0.25 * up > 0.28)
    moss_m = dataclasses.replace(MOSS, outline=STONE.outline)
    v = np.nan_to_num(light_of(Nn, MOSS.wrap))
    paint(frame, moss, moss_m, ramp_index(moss_m, v), "moss", min_px=4)
    # A short crack down the big front face: points on the stone (camera-aligned x, y), each
    # snapped to the visible pixel showing that spot, so the crack follows the shape.
    main = leaves[0].part
    on_main = frame.part == main
    pix = []
    for cx_, cy_ in ROCK_CRACK:
        d = np.where(on_main, np.hypot(np.nan_to_num(Q[..., 0], nan=1e3) - cx_,
                                       np.nan_to_num(Q[..., 1], nan=1e3) - cy_), np.inf)
        y_, x_ = np.unravel_index(int(np.argmin(d)), d.shape)
        pix.append((x_ + 0.5, y_ + 0.5))
    for x, y in pixel_path(pix):
        if frame.part[y, x] == main:
            frame.idx[y, x] = 0
    contact_band(frame, [main, leaves[1].part])
    return finish_prop(frame, prune_groups=("rock", "pebble", "moss"))


# The crack on the front face (camera-aligned x, y on the stone).
ROCK_CRACK = [(-2.5, 11.0), (-3.5, 9.0), (-2.5, 7.0), (-2.5, 6.0)]


# --- Pillar --------------------------------------------------------------------------------------

PILLAR_R = 5.6
RING_Y = 6.2
# Flutes: angles round the shaft (degrees from the viewer, + = right) of the grooves drawn.
FLUTES = (-52.0, -14.0, 24.0, 60.0)
# Where the column snapped: the height of the break across the shaft (screen x -> y, at the
# shaft's middle; the front edge sits lower so the broken face shows). One deep V notch left of
# centre and two jagged teeth on the right.
BREAK = [(-6.5, 39.0), (-4.5, 39.8), (-3.5, 38.2), (-2.5, 35.0), (-1.5, 32.6), (-0.5, 36.0),
         (0.5, 40.5), (1.5, 45.5), (2.5, 41.0), (3.5, 40.0), (4.5, 46.5), (6.5, 46.0)]
BREAK_SLOPE = 0.15  # how much lower the front edge of the break is, per unit toward the viewer
# The crack down the front of the shaft, running out of the bottom of the notch (x, y).
PILLAR_CRACK = [(-1.5, 31.6), (-1.5, 29.0), (-1.9, 27.0), (-0.5, 24.5), (0.3, 21.5), (1.6, 19.0)]
JOINT_Y = 17.0  # one drum joint across the shaft (a column built of drums, not a post)


def _break_top(x: np.ndarray, z: np.ndarray) -> np.ndarray:
    bx, by = zip(*BREAK)
    return np.interp(x, bx, by) - BREAK_SLOPE * z


def pillar_model() -> Node:
    def shaft(Q):
        x, y, z = Q[:, 0], Q[:, 1], Q[:, 2]
        r = PILLAR_R - 0.012 * y
        d_side = np.hypot(x, z) - r
        top = _break_top(x, z) + 0.4 * fbm3(Q * np.array([0.9, 0.0, 0.9]), 61, octaves=2)
        # The break's slopes are steep: divide by their Lipschitz bound so the march never
        # overshoots.
        d_top = (y - top) / 2.8
        d_bot = 5.5 - y
        return np.maximum(np.maximum(d_side, d_top), d_bot)

    col = Custom(COLUMN, shaft, group="pillar", bumps=(0.08, 0.7, 62))
    turn = rot(0.0, 22.0, 0.0)
    plinth = Box(STONE, (0, 1.6, 0), (7.5, 1.7, 7.5), R=turn, round=0.4, group="pillar",
                 bumps=(0.15, 0.6, 63))
    step = Box(STONE, (0, 4.4, 0), (6.6, 1.2, 6.6), R=turn, round=0.35, group="pillar",
               bumps=(0.15, 0.6, 64))
    ring = Cylinder(STONE, (0, RING_Y, 0), PILLAR_R + 0.6, 0.8, round=0.4, group="pillar")
    stone = Union(col, plinth, step, ring)
    # Chipped edges.
    for i, (cx, cy, cz, r) in enumerate(((-5.6, 3.2, 4.5, 1.8), (5.5, 16.0, 2.5, 1.3),
                                          (-4.2, 26.0, 3.8, 1.1), (6.0, 1.0, -3.0, 1.6))):
        stone = Subtract(stone, Sphere(STONE, (cx, cy, cz), r), k=0.3)
    return _face(GroundCut(stone))


def on_surface(frame: Frame, cam: Camera, pts: Sequence[Sequence[float]], parts: Sequence[int]
               ) -> list[tuple[int, int]]:
    """The pixels of a 1-pixel line through camera-aligned points (see `pixel_path`) that land on
    these parts (for cracks and joints painted into a surface, never outside it)."""
    proj = [cam.project(_world(p)) for p in pts]
    return [(x, y) for x, y in pixel_path([(px, py) for px, py, _ in proj])
            if 0 <= x < frame.W and 0 <= y < frame.H and frame.part[y, x] in parts]


def contact_band(frame: Frame, parts: Sequence[int], steps: int = 1) -> None:
    """The bottom row of these parts one step darker: the prop sits on the ground."""
    y = frame.H - 2
    for x in range(frame.W):
        if frame.part[y, x] in parts:
            frame.idx[y, x] = max(frame.idx[y, x] - steps, 0)


def make_pillar() -> np.ndarray:
    model = pillar_model()
    frame, cam = render_fit(model, 24, 56, name="pillar")
    Q, Nn = surface(frame, cam, model)
    leaves = model.leaves()
    stone_parts = [lf.part for lf in leaves]
    shaft_part = leaves[0].part
    y = np.nan_to_num(Q[..., 1])
    x = np.nan_to_num(Q[..., 0])
    up = np.nan_to_num(Nn[..., 1])
    v = np.nan_to_num(light_of(Nn, COLUMN.wrap))
    stone_px = np.isin(frame.part, stone_parts)
    # Weathered stone: the shadow side of everything a step darker than plain light gives.
    frame.idx = np.where(stone_px, ramp_index(COLUMN, np.clip(v * 1.05 - 0.02, 0.0, 1.0)),
                         frame.idx)
    shaft = (frame.part == shaft_part) & (up < 0.5)
    # Flutes: straight grooves, one whole pixel column each (a dark groove, its lit far wall
    # beside it on the light side), so they read as clean lines down the shaft.
    for a in FLUTES:
        col = int(math.floor(PILLAR_R * math.sin(math.radians(a)) - cam.cx + frame.W / 2.0))
        m = shaft[:, col] & (y[:, col] > RING_Y + 1.2) & (y[:, col] < _break_top(
            np.full(frame.H, PILLAR_R * math.sin(math.radians(a))), np.zeros(frame.H)) - 4.0)
        frame.idx[m, col] = np.maximum(frame.idx[m, col] - 1, 0)
        if a < 30.0 and 0 <= col + 1 < frame.W:
            m2 = m & shaft[:, col + 1]
            frame.idx[m2, col + 1] = np.minimum(frame.idx[m2, col + 1] + 1, COLUMN.top())
    # A drum joint: a dark line round the front of the shaft.
    rj = PILLAR_R - 0.012 * JOINT_Y - 0.1
    joint = [(rj * math.sin(math.radians(a)), JOINT_Y, rj * math.cos(math.radians(a)))
             for a in range(-84, 85, 12)]
    for px_, py_ in on_surface(frame, cam, joint, [shaft_part]):
        frame.idx[py_, px_] = max(frame.idx[py_, px_] - 2, 0)
    # The fresh fracture where it snapped: the break's upward faces in pale, unweathered stone.
    # It also shows as a pale lip along the whole jagged top edge (the top pixel of each column,
    # two where the edge drops steeply), brightest on the faces turned toward the light.
    fracture = (frame.part == shaft_part) & (up > 0.3) & (y > 28.0)
    on_shaft = frame.part == shaft_part
    tops_ = [int(np.nonzero(on_shaft[:, c])[0].min()) if on_shaft[:, c].any() else -1
             for c in range(frame.W)]
    for c, t in enumerate(tops_):
        if t < 0 or y[t, c] < 28.0:
            continue
        steep = max((tops_[c + d] - t) if 0 <= c + d < frame.W and tops_[c + d] >= 0 else 0
                    for d in (-1, 1))
        for k in range(1 + (steep >= 2)):
            if on_shaft[t + k, c]:
                fracture[t + k, c] = True
    paint(frame, fracture, FRACTURE, ramp_index(FRACTURE, v), "pillar", min_px=1)
    # The crack: out of the bottom of the notch and down the front of the shaft.
    crack = [(cx, cy, math.sqrt(max(PILLAR_R ** 2 - cx * cx, 0.0)) - 0.15) for cx, cy in PILLAR_CRACK]
    hole = frame.add_part(HOLE, "pillar")
    for px_, py_ in on_surface(frame, cam, crack, [shaft_part]):
        frame.part[py_, px_] = hole
        frame.idx[py_, px_] = 1
    # Moss: on the shadow side of the step tops and the base, creeping a little up the shaft's
    # shaded side. The lit fronts of the steps stay stone.
    n = fbm3(np.nan_to_num(Q).reshape(-1, 3) * np.array([0.3, 0.18, 0.3]), 65, octaves=2).reshape(y.shape)
    tops = (up > 0.6) & (y < 8.0) & (x + 3.0 * n > 0.5)
    base = (y < 2.6 + 1.6 * n) & (x + 4.0 * n > 3.5)
    climb = (y < 9.5 + 5.0 * n) & (x + 2.0 * n > 3.6) & shaft
    moss = stone_px & (tops | base | climb)
    mv = np.nan_to_num(light_of(Nn, MOSS.wrap))
    moss_m = dataclasses.replace(MOSS, outline=STONE.outline)
    moss_part = paint(frame, moss, moss_m, ramp_index(moss_m, mv * 0.9), "moss", min_px=3)
    contact_band(frame, stone_parts + [moss_part])
    return finish_prop(frame, prune_groups=("pillar", "moss"))


# --- Lamp ----------------------------------------------------------------------------------------

# Centre of the glass, near where the zone data puts the real light (1.9 m up at 0.05 m a pixel).
LANTERN_Y = 35.5


def lamp_model() -> Node:
    iron = LAMP_IRON
    parts: list[Node] = []
    turn = rot(0.0, 45.0, 0.0)
    # Stepped foot.
    parts.append(Box(iron, (0, 1.0, 0), (3.5, 1.1, 3.5), R=turn, round=0.5, group="iron"))
    parts.append(Cylinder(iron, (0, 2.7, 0), 2.2, 0.8, round=0.4, group="iron"))
    # Post with collars.
    top = LANTERN_Y - 5.5
    parts.append(RoundCone(iron, (0, 3.0, 0), (0, top + 0.5, 0), 1.2, 0.9, group="iron"))
    parts.append(Cylinder(iron, (0, 11.0, 0), 1.7, 0.55, round=0.3, group="iron"))
    parts.append(Cylinder(iron, (0, top, 0), 1.9, 0.6, round=0.3, group="iron"))
    # Little scroll arms holding the lantern.
    for sx in (-1.0, 1.0):
        parts.append(Torus(iron, (sx * 2.3, top + 0.6, 0), 1.35, 0.42, R=rot(90.0, 0.0, 0.0),
                           group="iron", thin=True))
    gy = LANTERN_Y
    # Lantern facing the viewer square on: base plate, one pane framed by the two front posts
    # (the back posts hide behind them), a pointed roof and a knob.
    parts.append(Box(iron, (0, gy - 3.9, 0), (3.3, 0.6, 3.3), round=0.3, group="iron"))
    for sx, sz in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        parts.append(Capsule(iron, (sx * 2.45, gy - 3.4, sz * 2.45), (sx * 2.6, gy + 3.2, sz * 2.6),
                             0.5, group="iron", thin=True))
    parts.append(Box(LANTERN, (0, gy, 0), (2.4, 3.4, 2.4), round=0.2, group="iron"))
    roof_y = gy + 3.4

    def roof_fn(Q):
        h = Q[:, 1] - roof_y
        pyramid = np.maximum(np.abs(Q[:, 0]), np.abs(Q[:, 2])) - (3.6 - 0.95 * h)
        return np.maximum(pyramid * 0.7, np.maximum(-h, h - 3.4))

    parts.append(Custom(iron, roof_fn, group="iron"))
    parts.append(Sphere(iron, (0, roof_y + 3.9, 0), 0.95, group="iron"))
    # A little spike on the knob, and the old ladder rest across the post under the lantern
    # (a lamplighter leaned a ladder on it): the silhouette of a real old street lamp.
    parts.append(RoundCone(iron, (0, roof_y + 4.5, 0), (0, roof_y + 6.0, 0), 0.45, 0.2,
                           group="iron", thin=True))
    bar_y = top - 3.0
    parts.append(Capsule(iron, (-3.0, bar_y, 0), (3.0, bar_y, 0), 0.42, group="iron", thin=True))
    for sx in (-1.0, 1.0):
        parts.append(Sphere(iron, (sx * 3.3, bar_y, 0), 0.7, group="iron"))
    return _face(GroundCut(Union(*parts)))


def make_lamp() -> np.ndarray:
    model = lamp_model()
    frame, cam = render_fit(model, 16, 48, name="lamp")
    glass = np.array([frame.mats[p].name == LANTERN.name if p >= 0 else False
                      for p in frame.part.ravel()]).reshape(frame.part.shape)
    # A darker amber rim round the pane (glass in a frame, not a flat orange block).
    edge = np.zeros_like(glass)
    for dx, dy in N4:
        sh = np.roll(np.roll(glass, -dy, axis=0), -dx, axis=1)
        edge |= glass & ~sh
    frame.idx = np.where(edge, 1, frame.idx)
    # The flame: a pale core low in the middle of the pane.
    ys, xs = np.nonzero(glass & ~edge)
    cx = (xs.min() + xs.max()) / 2.0
    for fx in sorted({int(math.floor(cx)), int(math.ceil(cx))}):
        for fy in (ys.max() - 1, ys.max()):
            if glass[fy, fx]:
                frame.idx[fy, fx] = 3
    # The lantern lights its own iron: a warm spill on the roof's underside and the base plate
    # right above and below the pane, and on the frame posts beside it.
    iron = (frame.part >= 0) & ~glass
    spill = frame.add_part(LAMP_SPILL, "iron")
    gys = np.nonzero(glass.any(axis=1))[0]
    y0, y1 = int(gys.min()), int(gys.max())
    for x in range(frame.W):
        if glass[:, x].any():
            for y, k in ((y0 - 1, 0), (y1 + 1, 1)):
                if iron[y, x]:
                    frame.part[y, x], frame.idx[y, x] = spill, k
    for y in range(y0 + 1, y1 + 1):
        for x in range(frame.W):
            if iron[y, x] and ((x + 1 < frame.W and glass[y, x + 1]) or (x > 0 and glass[y, x - 1])):
                frame.part[y, x], frame.idx[y, x] = spill, 0
    return finish_prop(frame)


# --- Glow mushrooms -------------------------------------------------------------------------------

# (x, z, stem height, cap radius, tilt degrees toward screen right): a tall one, one leaning out
# to the left, a shorter one low on the right and two buttons in front.
SHROOMS = [
    (-0.2, -1.0, 12.5, 5.2, -4.0),
    (5.0, 1.0, 6.5, 2.9, 9.0),
    (-5.4, 0.8, 7.8, 3.3, -16.0),
    (0.5, 5.4, 2.2, 1.9, 12.0),
    (-3.6, 4.8, 1.5, 1.5, -12.0),
]


def shroom_model() -> Node:
    parts: list[Node] = []
    for i, (x, z, h, r, tilt) in enumerate(SHROOMS):
        R = rot(0.0, 0.0, -tilt)
        top = np.array([x, 0.0, z]) + R @ np.array([0.0, h, 0.0])
        parts.append(RoundCone(SHROOM_STEM, (x, -0.5, z), top, max(0.6, r * 0.16),
                               max(0.45, r * 0.12), group="stem%d" % i, thin=True))
        cap_c = top + R @ np.array([0.0, -0.2, 0.0])

        def cap_fn(Q, r=r):
            # A dome: an ellipsoid with its underside cut away, the rim curling down a little.
            e = (np.linalg.norm(Q / np.array([r, r * 0.85, r]), axis=1) - 1.0) * r * 0.8
            under = -Q[:, 1] + 0.1 * r - 0.14 * np.hypot(Q[:, 0], Q[:, 2])
            return np.maximum(e, under)

        parts.append(Custom(SHROOM_CAP, cap_fn, pos=cap_c, R=R.T, group="cap%d" % i))
        parts.append(Cylinder(SHROOM_GILL, cap_c + R @ np.array([0.0, -0.2, 0.0]), r * 0.86, 0.25,
                              R=R.T, group="cap%d" % i))
    # A low mound of dark soil they grow from.
    parts.append(Ellipsoid(SOIL, (-0.6, -0.2, 2.0), (6.4, 1.8, 3.4), group="soil",
                           bumps=(0.3, 0.8, 81)))
    return _face(GroundCut(Union(*parts)))


def make_glow_shroom() -> np.ndarray:
    model = shroom_model()
    frame, cam = render_fit(model, 24, 24, centre="bbox", name="glow_shroom")
    # Caps glow from within: brightest on top, shading down to a deeper teal round the rim, with
    # the light only nudging it (so each cap is a clean dome of 3 to 4 bands, not speckled).
    Q, Nn = surface(frame, cam, model)
    groups = np.array(frame.groups + [""])
    cap = (frame.part >= 0) & np.char.startswith(groups[np.where(frame.part >= 0, frame.part,
                                                                 len(frame.groups))], "cap")
    caps_m = np.array([m.name == SHROOM_CAP.name for m in frame.mats] + [False])
    cap &= caps_m[np.where(frame.part >= 0, frame.part, len(frame.mats))]
    up = np.clip(np.nan_to_num(Nn[..., 1]), 0.0, 1.0)
    v = 0.5 * np.nan_to_num(light_of(Nn, SHROOM_CAP.wrap)) + 0.5 * up ** 0.7
    frame.idx = np.where(cap, np.clip(np.rint(0.6 + v * 3.6), 1, 4).astype(np.int32), frame.idx)
    # Two darker spots on the big cap (so it is not one flat cyan dome) and the shadow of its
    # gills under the rim.
    big = cap & (_groups_of(frame) == "cap0")
    ys, xs = np.nonzero(big)
    top, cx = int(ys.min()), int(round((xs.min() + xs.max()) / 2.0))
    for sx, sy in ((-3, 2), (-2, 2), (2, 3), (3, 3)):
        if big[top + sy, cx + sx]:
            frame.idx[top + sy, cx + sx] = max(frame.idx[top + sy, cx + sx] - 2, 1)
    for x in range(frame.W):
        col = np.nonzero(big[:, x])[0]
        if len(col) and col.max() + 1 < frame.H and not big[col.max() + 1, x]:
            frame.idx[col.max(), x] = max(frame.idx[col.max(), x] - 1, 0)
    return finish_prop(frame, contour_gap=1.5, contour_steps=1)


# --- Grass ----------------------------------------------------------------------------------------

GRASS_INK = "#28301c"
GREEN = mat("prop_grass", "#68743a", shadow_chroma=0.75, shadow_shift=6.0).colors
DRY = mat("prop_dry_grass", "#7d7549", shadow_chroma=0.75, shadow_shift=6.0).colors

# Blades as (root x, bend point, tip, dry?, back?) in pixels, the base row being y = 10. A
# loose tuft leaning to the right (wind and growth both push it that way), so a flipped copy reads
# as a different tuft: the tallest blade leans out right of centre, a long blade arches low over
# to the left, the seed-head weed stands up on the left, and the right side is shorter and
# higher. The back blades are a shade darker. Roots spread over 5 pixels so the tuft never
# clots into a dark lump.
BLADES = [
    (12, (13.0, 6.0), (15.5, 1.0), False, False),
    (11, (11.0, 7.0), (12.0, 3.0), False, True),
    (13, (15.0, 7.5), (18.5, 5.0), True, False),
    (10, (7.5, 7.0), (4.0, 7.5), False, False),
    (11, (9.5, 7.5), (8.5, 5.0), True, False),
    (12, (13.0, 7.5), (14.0, 4.5), True, True),
]
# A weed stalk with a seed head: (root x, bend point, tip).
WEED = (10, (8.8, 6.0), (8.0, 2.5))


def _blade_pixels(x0: int, mid: tuple[float, float], tip: tuple[float, float]) -> list[tuple[int, int]]:
    """A curved 1-pixel blade from its root on the base row through `mid` to `tip` (a quadratic
    curve, rasterised pixel-perfect)."""
    pts = []
    for k in range(9):
        t = k / 8.0
        a = (1 - t) * (1 - t)
        b = 2 * (1 - t) * t
        c = t * t
        pts.append((a * (x0 + 0.5) + b * (mid[0] + 0.5) + c * (tip[0] + 0.5),
                    a * 10.5 + b * (mid[1] + 0.5) + c * (tip[1] + 0.5)))
    return pixel_path(pts)


def make_grass() -> np.ndarray:
    c = Canvas(24, 12)
    roots_x = []
    for x0, mid, tip, dry, back in BLADES:
        ramp_ = DRY if dry else GREEN
        px = _blade_pixels(x0, mid, tip)
        n = len(px)
        for i, (x, y) in enumerate(px):
            # One dark green at the roots (the tuft's base reads as one clump), lighter toward
            # the tip (which catches the light).
            if 10 - y < 2:
                c.px(x, y, GREEN[1])
                continue
            ci = 3 if i >= n - 2 else 2
            c.px(x, y, ramp_[ci - (1 if back else 0)])
        roots_x.append(x0)
    x0, mid, tip = WEED
    px = _blade_pixels(x0, mid, tip)
    for x, y in px:
        c.px(x, y, GREEN[1] if 10 - y < 2 else DRY[1])
    tx, ty = px[-1]
    for dx, dy, ci in ((0, -1, 3), (1, 0, 3), (1, -1, 4), (0, 0, 2)):
        c.px(tx + dx, ty + dy, DRY[ci])
    roots_x.append(x0)
    # One dark contact row under the roots: the tuft sits on the ground, the tips stay light.
    for x in range(min(roots_x), max(roots_x) + 1):
        c.px(x, 11, GRASS_INK)
    return c.a


# --- Build ---------------------------------------------------------------------------------------


PROPS: dict[str, Callable[[], np.ndarray]] = {
    "dead_tree": make_dead_tree,
    "rotten_tree": make_rotten_tree,
    "rock": make_rock,
    "pillar": make_pillar,
    "lamp": make_lamp,
    "glow_shroom": make_glow_shroom,
    "grass": make_grass,
}


def lineup(images: Sequence[np.ndarray], gap: int = 4) -> np.ndarray:
    H = max(i.shape[0] for i in images)
    W = sum(i.shape[1] for i in images) + gap * (len(images) + 1)
    out = np.zeros((H + 2 * gap, W, 4), dtype=np.uint8)
    x = gap
    for img in images:
        h, w = img.shape[:2]
        out[gap + H - h:gap + H, x:x + w] = img
        x += w + gap
    return out


# World units per pixel the zones use for each prop (data/zones, data/looks), for the review scene.
PIXEL_SIZE = {"dead_tree": 0.06, "rotten_tree": 0.06, "rock": 0.05, "pillar": 0.055, "lamp": 0.05,
              "glow_shroom": 0.045, "grass": 0.045}
FIGHTER_PIXEL = 0.045


def _load(rel: str) -> np.ndarray | None:
    import os
    from PIL import Image
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))), "assets", rel)
    try:
        return np.asarray(Image.open(path).convert("RGBA"))
    except OSError:
        return None


def scene(made: dict[str, np.ndarray], tile_rel: str, width: int = 330, height: int = 136) -> np.ndarray:
    """A review picture: the props standing on a zone floor at their in-game relative sizes, with
    a hero for scale (fighters are drawn at 0.045 a pixel)."""
    from PIL import Image
    out = np.zeros((height, width, 4), dtype=np.uint8)
    out[..., :3] = (15, 15, 23)
    out[..., 3] = 255
    tile = _load(tile_rel)
    ground_y = height - 22
    if tile is not None:
        t = np.tile(tile, (2, width // 32 + 1, 1))[:, :width]
        out[ground_y - 6:ground_y - 6 + 22] = t[:22]
    else:
        out[ground_y - 6:, :3] = (60, 64, 66)
    hero = _load("sprites/characters/alder.png")
    items = []
    if hero is not None:
        items.append(("hero", hero[:, :32], FIGHTER_PIXEL))
    order = ["dead_tree", "grass", "rock", "lamp", "pillar", "glow_shroom", "rotten_tree", "grass"]
    for n in order:
        if n in made:
            items.append((n, made[n], PIXEL_SIZE[n]))
    x = 6
    canvas = Image.fromarray(out, "RGBA")
    for n, img, ps in items:
        f = ps / FIGHTER_PIXEL
        h, w = img.shape[:2]
        im = Image.fromarray(img, "RGBA").resize((max(1, round(w * f)), max(1, round(h * f))), Image.NEAREST)
        canvas.alpha_composite(im, (x, ground_y + 2 - im.height))
        x += im.width - 2
    return np.asarray(canvas)


def check(name: str, rgba: np.ndarray) -> list[str]:
    """The prop contract: alpha cut, base on the second-to-last row (outline below it), centred,
    nothing on the top, left or right edge (the outline needs that pixel), no colour darker than
    palette.INK. Prints and returns the problems."""
    problems = []
    a = rgba[..., 3]
    H, W = a.shape
    if not np.isin(a, (0, 255)).all():
        problems.append("half-transparent pixels")
    solid = a > 0
    if solid[0, :].any() or solid[:, 0].any() or solid[:, -1].any():
        problems.append("touches the top/left/right edge (no room for the outline)")
    rows = np.nonzero(solid.any(axis=1))[0]
    cols = np.nonzero(solid.any(axis=0))[0]
    if rows.max() != H - 1:
        problems.append("lowest pixel on row %d, expected the outline on %d" % (rows.max(), H - 1))
    left, right = int(cols.min()), W - 1 - int(cols.max())
    if abs(left - right) > 2:
        problems.append("off centre (%d px clear on the left, %d on the right)" % (left, right))
    ink_l = to_oklch(INK)[0] - 0.002
    darker = set()
    for c in {tuple(int(v) for v in p) for p in rgba[solid][:, :3]}:
        if to_oklch("#%02x%02x%02x" % c)[0] < ink_l:
            darker.add("#%02x%02x%02x" % c)
    if darker:
        problems.append("colours darker than INK: %s" % ", ".join(sorted(darker)))
    for p in problems:
        print("  check %s: %s" % (name, p))
    return problems


def build(ctx) -> None:
    made = {}
    for name, fn in PROPS.items():
        rgba = fn()
        check(name, rgba)
        ctx.save("sprites/env/%s.png" % name, rgba)
        made[name] = rgba
    ctx.extra("lineup_1x.png", lineup(list(made.values())), scale=1)
    ctx.extra("lineup_3x.png", lineup(list(made.values())), scale=3)
    for tile in ("floor_tile", "ash_tile", "bog_tile"):
        ctx.extra("scene_%s.png" % tile, scene(made, "sprites/env/%s.png" % tile), scale=3)
