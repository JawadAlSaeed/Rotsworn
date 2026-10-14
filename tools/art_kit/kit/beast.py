"""Shared helpers for the phase 12 monsters (enemy_fly, enemy_hyena, enemy_toad): small maths,
safe cones, a decal painter, the finishing passes, the sprite checks and the build of a fighter
sheet with its clips and portrait. The older enemy modules keep their own copies; these
modules are built on plain SDF parts placed straight from a pose dict (no humanoid rig).
"""
from __future__ import annotations

import math
import os
from typing import Any, Callable, Mapping, Sequence

import numpy as np

from .clips import ENEMY_PREVIEW_MS, _norm, render_clips
from .color import to_oklch
from .palette import INK, Material
from .post import cleanup, contours, outline
from .render import Camera, Frame
from .rig import blend
from .sdf import RoundCone, Sphere
from .specs import ENEMY_POSES


def v(x: Sequence[float]) -> np.ndarray:
    return np.asarray(x, dtype=float)


def unit(x: Sequence[float]) -> np.ndarray:
    a = v(x)
    return a / (np.linalg.norm(a) + 1e-9)


def dir2(deg: float) -> np.ndarray:
    """A direction in the side plane: 0 = forward (+x), 90 = straight up."""
    a = math.radians(deg)
    return v((math.cos(a), math.sin(a), 0.0))


def cone(mat: Material, a: Sequence[float], b: Sequence[float], ra: float, rb: float, **kw) -> Any:
    """RoundCone that stays valid when the segment is shorter than the radius step."""
    a, b = v(a), v(b)
    if float(np.linalg.norm(b - a)) < abs(ra - rb) + 0.05:
        return Sphere(mat, a if ra >= rb else b, max(ra, rb), **kw)
    return RoundCone(mat, a, b, ra, rb, **kw)


def pose_with(base: Mapping[str, Any], **kw: Any) -> dict[str, Any]:
    """A copy of `base` with some keys changed."""
    p = dict(base)
    p.update(kw)
    return p


def mix(a: Mapping[str, Any], b: Mapping[str, Any], t: float, **kw: Any) -> dict[str, Any]:
    """An in-between of two poses, with some keys then set by hand."""
    p = blend(dict(a), dict(b), t)
    p.update(kw)
    return p


def framed(size: int, scale: float, point: Sequence[float], at: tuple[float, float]) -> Camera:
    """A left-facing camera that puts model `point` at pixel `at` (x, y)."""
    vv = Camera(size, size, scale=scale, face="left").view(point)
    return Camera(size, size, scale=scale, face="left", cx=float(vv[0]) - (at[0] - size / 2.0) * scale,
                  cy=float(vv[1]) - (size - 0.5 - at[1]) * scale)


def decal(fr: Frame, cam: Camera, point: Sequence[float], rows: Sequence[str],
          legend: Mapping[str, tuple[Material, int]], on_groups: Sequence[str], tol: float = 3.0,
          group: str = "decal") -> bool:
    """Paints a tiny pattern centred on model `point`, only over visible pixels of `on_groups`
    whose depth is within `tol` of the point (never off the silhouette or onto a part in front)."""
    ax, ay, ad = cam.project(v(point))
    h, w = len(rows), max(len(r) for r in rows)
    x0, y0 = int(math.floor(ax - (w - 1) / 2.0)), int(math.floor(ay - (h - 1) / 2.0))
    parts = {ch: fr.add_part(mat, group) for ch, (mat, _) in legend.items()}
    done = False
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch not in legend:
                continue
            x, y = x0 + c, y0 + r
            if not (1 <= x < fr.W - 1 and 1 <= y < fr.H - 1):
                continue
            p = fr.part[y, x]
            if p < 0 or fr.groups[p] not in on_groups or abs(fr.depth[y, x] - ad) > tol:
                continue
            fr.part[y, x] = parts[ch]
            fr.idx[y, x] = legend[ch][1]
            fr.fixed[y][x] = None
            done = True
    return done


def lift_off_last_row(fr: Frame, most: int = 3) -> int:
    """Moves the whole picture up (at most `most` pixels) until no body pixel is on the last row,
    which belongs to the outline: a foot splayed toward the viewer shows lower on screen in the
    3/4 view. Returns how far it moved."""
    moved = 0
    while moved < most and (fr.part[-1] >= 0).any() and not (fr.part[0] >= 0).any():
        fr.part = np.roll(fr.part, -1, axis=0)
        fr.part[-1] = -1
        fr.idx = np.roll(fr.idx, -1, axis=0)
        fr.depth = np.roll(fr.depth, -1, axis=0)
        fr.depth[-1] = np.inf
        fr.light = np.roll(fr.light, -1, axis=0)
        fr.alpha = np.roll(fr.alpha, -1, axis=0)
        fr.fixed = fr.fixed[1:] + [[None] * fr.W]
        moved += 1
    return moved


N8 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1))


def despeckle(fr: Frame, keep: Sequence[str] = ()) -> None:
    """A pixel whose colour none of its 8 neighbours share takes the shade most of its
    same-material neighbours have. Emissive parts and groups ending in `keep` are left alone."""
    part, idx = fr.part.copy(), fr.idx.copy()
    for y in range(1, fr.H - 1):
        for x in range(1, fr.W - 1):
            p = part[y, x]
            if p < 0 or fr.mats[p].emissive or fr.groups[p].endswith(tuple(keep)):
                continue
            same, votes, n_mat = False, {}, 0
            for dx, dy in N8:
                q = part[y + dy, x + dx]
                if q < 0 or fr.mats[q] is not fr.mats[p]:
                    continue
                n_mat += 1
                if idx[y + dy, x + dx] == idx[y, x]:
                    same = True
                    break
                votes[idx[y + dy, x + dx]] = votes.get(idx[y + dy, x + dx], 0) + 1
            if same or not votes:
                continue
            best, n = max(votes.items(), key=lambda kv: kv[1])
            if n >= 3 or (n >= 2 and n_mat <= 4):
                fr.idx[y, x] = best


_INK_L = to_oklch(INK)[0]


def finish(fr: Frame, contour_gap: float = 2.5, keep: Sequence[str] = ()) -> np.ndarray:
    """Contours, cleanup, despeckle, outline, and no colour darker than the palette's ink."""
    contours(fr, contour_gap, 2)
    cleanup(fr)
    despeckle(fr, keep)
    outline(fr)
    for y in range(fr.H):
        for x in range(fr.W):
            c = fr.fixed[y][x]
            if c is not None and to_oklch(c)[0] < _INK_L:
                fr.fixed[y][x] = INK
    return fr.rgba()


def check(name: str, fr: Frame, rgba: np.ndarray, floats: bool = False) -> list[str]:
    """Sprite contract: nothing on the top or side edges; a standing fighter's body ends on the
    second-to-last row (the last row is outline only)."""
    a = rgba[..., 3] > 0
    issues = []
    if a[0].any() or a[:, 0].any() or a[:, -1].any():
        issues.append("%s touches the top or side edge" % name)
    if (fr.part[-1] >= 0).any():
        issues.append("%s has body pixels on the last row" % name)
    if not floats and not (fr.part[-2] >= 0).any():
        issues.append("%s does not stand on the second-to-last row" % name)
    return issues


def render_many(fn: Callable[[dict[str, Any]], np.ndarray], poses: Sequence[dict[str, Any]]) -> list[np.ndarray]:
    """Renders poses with `fn` (a module-level function, so worker processes can run it)."""
    if len(poses) < 4:
        return [fn(p) for p in poses]
    try:
        from concurrent.futures import ProcessPoolExecutor
        workers = max(1, min(8, (os.cpu_count() or 2) - 2, len(poses)))
        with ProcessPoolExecutor(max_workers=workers) as ex:
            return list(ex.map(fn, poses))
    except (OSError, RuntimeError, ImportError):
        return [fn(p) for p in poses]


def clip_cells(clips: Mapping[str, Sequence[Any]], fn: Callable[[dict[str, Any]], np.ndarray]) -> dict[str, list[Any]]:
    """CLIPS rendered: every distinct pose once, in parallel."""
    todo: dict[Any, dict[str, Any]] = {}
    for entries in clips.values():
        for e in entries:
            if isinstance(e, dict):
                todo.setdefault(_norm(e), e)
    done = dict(zip(todo, render_many(fn, list(todo.values()))))
    return render_clips(clips, lambda p: done[_norm(p)])


def build_enemy(ctx, cid: str, size: int, poses: Mapping[str, dict[str, Any]],
                clips: Mapping[str, Sequence[Any]], frame_fn: Callable[[dict[str, Any]], Frame],
                finish_fn: Callable[[Frame], np.ndarray], cell_fn: Callable[[dict[str, Any]], np.ndarray],
                portrait: np.ndarray, idle_percent: int = 100, floats: bool = False) -> None:
    """Saves an enemy: row-0 keys (checked), the clip grid and its .tres, and the portrait.
    cell_fn(pose) must equal finish_fn(frame_fn(pose)) and be a module-level function (worker
    processes render the clips with it)."""
    frames = []
    for name in ENEMY_POSES:
        fr = frame_fn(poses[name])
        f = finish_fn(fr)
        for msg in check(name, fr, f, floats):
            print("  WARN", cid, msg)
        frames.append(f)
    cells = clip_cells(clips, cell_fn)
    ctx.save_fighter("sprites/enemies/%s.png" % cid, frames, cells, (size, size), size, cid,
                     preview_ms={"idle": ENEMY_PREVIEW_MS["idle"] * idle_percent // 100})
    ctx.save("sprites/portraits/%s.png" % cid, portrait)
