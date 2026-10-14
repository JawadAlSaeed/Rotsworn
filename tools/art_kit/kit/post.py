"""Clean-up passes that make a render read like hand-made pixel art.

Order used by the asset modules: render -> overlays -> contours -> cleanup -> outline.
"""
from __future__ import annotations

import numpy as np

from .palette import INK
from .render import Frame

N4 = ((0, -1), (-1, 0), (1, 0), (0, 1))


def contours(frame: Frame, gap: float = 2.5, steps: int = 2) -> None:
    """Draws inner lines where one part passes in front of another: the farther pixel along the
    edge goes `steps` ramp colours darker. Parts in the same group are one body and get none."""
    H, W = frame.H, frame.W
    darker = np.zeros((H, W), dtype=bool)
    for y in range(H):
        for x in range(W):
            p = frame.part[y, x]
            if p < 0:
                continue
            for dx, dy in N4:
                nx, ny = x + dx, y + dy
                if not (0 <= nx < W and 0 <= ny < H):
                    continue
                q = frame.part[ny, nx]
                if q < 0 or q == p or frame.groups[q] == frame.groups[p]:
                    continue
                if frame.depth[y, x] > frame.depth[ny, nx] + gap:
                    darker[y, x] = True
                    break
    frame.idx = np.where(darker, np.maximum(frame.idx - steps, 0), frame.idx)


def cleanup(frame: Frame, passes: int = 1) -> None:
    """Removes lone pixels: a pixel whose four neighbours all agree on one colour of the same part
    takes that colour (stray shading specks, single-pixel holes)."""
    H, W = frame.H, frame.W
    for _ in range(passes):
        changed = False
        part = frame.part.copy()
        idx = frame.idx.copy()
        for y in range(1, H - 1):
            for x in range(1, W - 1):
                n = [(part[y + dy, x + dx], idx[y + dy, x + dx]) for dx, dy in N4]
                if n[0] == n[1] == n[2] == n[3] and n[0] != (part[y, x], idx[y, x]):
                    if part[y, x] < 0 or n[0][0] == part[y, x]:
                        frame.part[y, x], frame.idx[y, x] = n[0]
                        if n[0][0] >= 0:
                            frame.depth[y, x] = min(frame.depth[y + dy, x + dx] for dx, dy in N4)
                        changed = True
        if not changed:
            break


def edge_light(frame: Frame, steps: int = 1, sides: tuple[str, ...] = ("top",)) -> None:
    """Brightens solid pixels whose `sides` neighbour is empty (a rim of light along the top or
    left edge). Emissive parts are left alone."""
    H, W = frame.H, frame.W
    off = {"top": (0, -1), "left": (-1, 0), "right": (1, 0), "bottom": (0, 1)}
    lit = np.zeros((H, W), dtype=bool)
    for s in sides:
        dx, dy = off[s]
        for y in range(H):
            for x in range(W):
                if frame.part[y, x] < 0 or frame.mats[frame.part[y, x]].emissive:
                    continue
                nx, ny = x + dx, y + dy
                if not (0 <= nx < W and 0 <= ny < H) or frame.part[ny, nx] < 0:
                    lit[y, x] = True
    for y, x in zip(*np.nonzero(lit)):
        m = frame.mats[frame.part[y, x]]
        frame.idx[y, x] = min(m.top(), frame.idx[y, x] + steps)


def outline(frame: Frame, color: str | None = None, inner: bool = False,
            diagonal: bool = False, skip_groups: tuple[str, ...] = ()) -> None:
    """A 1-pixel outline around the silhouette in each touching material's outline colour (or one
    `color`). inner=True draws it on the edge pixels instead of outside them (keeps the size).
    diagonal=True also closes diagonal gaps (heavier look). Groups in `skip_groups` (glows,
    effects) get no outline."""
    H, W = frame.H, frame.W
    solid = frame.part >= 0
    nbrs = N4 + (((-1, -1), (1, -1), (-1, 1), (1, 1)) if diagonal else ())
    paint: list[tuple[int, int, str]] = []
    for y in range(H):
        for x in range(W):
            if inner:
                if not solid[y, x]:
                    continue
                p = frame.part[y, x]
                if frame.groups[p] in skip_groups:
                    continue
                edge = False
                for dx, dy in nbrs:
                    nx, ny = x + dx, y + dy
                    if not (0 <= nx < W and 0 <= ny < H) or not solid[ny, nx]:
                        edge = True
                        break
                if edge:
                    paint.append((x, y, color or frame.mats[p].outline))
            else:
                if solid[y, x] or frame.fixed[y][x] is not None:
                    continue
                best = None
                for dx, dy in nbrs:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and solid[ny, nx]:
                        p = frame.part[ny, nx]
                        if frame.groups[p] in skip_groups:
                            continue
                        if best is None or frame.depth[ny, nx] < frame.depth[best[1], best[0]]:
                            best = (nx, ny)
                if best is not None:
                    p = frame.part[best[1], best[0]]
                    paint.append((x, y, color or frame.mats[p].outline))
    for x, y, c in paint:
        frame.fixed[y][x] = c
        if not inner:
            frame.depth[y, x] = np.inf


def ink(frame: Frame) -> None:
    """Outline in the shared near-black INK colour (strongest separation)."""
    outline(frame, color=INK)


def finish(frame: Frame, contour_gap: float = 2.5, contour_steps: int = 2, clean: bool = True,
           rim: bool = False, outline_color: str | None = None,
           skip_groups: tuple[str, ...] = ()) -> np.ndarray:
    """The usual chain: contours, cleanup, optional rim light, outline. Returns RGBA."""
    if contour_gap > 0:
        contours(frame, contour_gap, contour_steps)
    if clean:
        cleanup(frame)
    if rim:
        edge_light(frame)
    outline(frame, color=outline_color, skip_groups=skip_groups)
    return frame.rgba()
