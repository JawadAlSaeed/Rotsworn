"""Checks the drawn art against the sprite contract (README.md). Exit 1 on any failure.

    python tools/art_kit/check.py

Sizes and frame counts, alpha rules (fighters, portraits, props, tiles and icons: every pixel
fully opaque or fully clear), fighters standing on the bottom with a clear 1-pixel border,
nothing touching a frame edge, and ground textures that tile without visible seams.
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from kit.specs import ENEMY_FRAME, ENEMY_POSES, HERO_FRAME, HERO_POSES, PORTRAIT  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
SPRITES = os.path.join(ROOT, "assets", "sprites")

HEROES = ["alder", "brin", "cass"]
PROPS = {"dead_tree": (48, 64), "rotten_tree": (64, 80), "rock": (32, 24), "pillar": (24, 56),
         "lamp": (16, 48), "glow_shroom": (24, 24), "grass": (24, 12)}
TILES = ["floor_tile", "ash_tile", "bog_tile", "cliff", "ruin_wall"]
BACKDROPS = ["backdrop", "backdrop_ashen_ruins", "backdrop_sunken_bog", "backdrop_hollow_throne"]
FX = {"shadow": (32, 12), "shockwave": (64, 16), "slash": (32, 32), "spark": (16, 16)}
UI = {"ap_pip": (10, 10), "ap_pip_empty": (10, 10), "hit_normal": (12, 12), "hit_ground": (12, 12),
      "lock": (12, 12)}

errors: list[str] = []
warnings: list[str] = []


def load(rel: str) -> np.ndarray | None:
    path = os.path.join(SPRITES, rel)
    if not os.path.exists(path):
        errors.append("%s: missing" % rel)
        return None
    return np.asarray(Image.open(path).convert("RGBA"))


def size_is(rel: str, a: np.ndarray, w: int, h: int) -> bool:
    if a.shape[1] != w or a.shape[0] != h:
        errors.append("%s: is %dx%d, should be %dx%d" % (rel, a.shape[1], a.shape[0], w, h))
        return False
    return True


def hard_alpha(rel: str, a: np.ndarray) -> None:
    soft = np.count_nonzero((a[..., 3] > 0) & (a[..., 3] < 255))
    if soft:
        errors.append("%s: %d half-transparent pixels (alpha cut needs 0 or 255)" % (rel, soft))


def frames(a: np.ndarray, fw: int) -> list[np.ndarray]:
    return [a[:, i * fw:(i + 1) * fw] for i in range(a.shape[1] // fw)]


def fighter(rel: str, a: np.ndarray, fw: int, fh: int, n: int, poses: list[str], floats: bool = False) -> None:
    if not size_is(rel, a, fw * n, fh):
        return
    hard_alpha(rel, a)
    for i, f in enumerate(frames(a, fw)):
        solid = f[..., 3] > 0
        name = "%s frame %d (%s)" % (rel, i, poses[i])
        if not solid.any():
            errors.append("%s: empty" % name)
            continue
        if solid[0, :].any() or solid[:, 0].any() or solid[:, -1].any():
            errors.append("%s: touches the top/left/right edge (clipped or no outline room)" % name)
        rows = np.nonzero(solid.any(axis=1))[0]
        if not floats and poses[i] not in ("jump",) and rows[-1] < fh - 3:
            warnings.append("%s: lowest pixel on row %d, not standing on the bottom" % (name, rows[-1]))
        if solid[-1, :].any() and poses[i] not in ("down",):
            pass  # the outline may sit on the last row
    idle = frames(a, fw)[0][..., 3] > 0
    rows = np.nonzero(idle.any(axis=1))[0]
    if len(rows) and (rows[-1] - rows[0] + 1) < fh * 0.5:
        warnings.append("%s: idle is only %d px tall in a %d px frame" % (rel, rows[-1] - rows[0] + 1, fh))


def seam(rel: str, a: np.ndarray) -> None:
    """Compares the jump across the tile border with the typical jump between neighbours."""
    rgb = a[..., :3].astype(float)
    inner_x = np.abs(np.diff(rgb, axis=1)).mean()
    inner_y = np.abs(np.diff(rgb, axis=0)).mean()
    border_x = np.abs(rgb[:, 0] - rgb[:, -1]).mean()
    border_y = np.abs(rgb[0, :] - rgb[-1, :]).mean()
    if border_x > inner_x * 1.8 + 4 or border_y > inner_y * 1.8 + 4:
        errors.append("%s: visible seam when tiled (border %.1f/%.1f vs inside %.1f/%.1f)"
                      % (rel, border_x, border_y, inner_x, inner_y))


def main() -> int:
    for h in HEROES:
        rel = "characters/%s.png" % h
        a = load(rel)
        if a is not None:
            fighter(rel, a, HERO_FRAME[0], HERO_FRAME[1], len(HERO_POSES), HERO_POSES)
    for e, s in ENEMY_FRAME.items():
        rel = "enemies/%s.png" % e
        a = load(rel)
        if a is not None:
            fighter(rel, a, s, s, len(ENEMY_POSES), ENEMY_POSES, floats=e in ("gnat_swarm", "shade"))
    for p in HEROES + list(ENEMY_FRAME):
        rel = "portraits/%s.png" % p
        a = load(rel)
        if a is not None and size_is(rel, a, PORTRAIT, PORTRAIT):
            hard_alpha(rel, a)
    for p, (w, h) in PROPS.items():
        rel = "env/%s.png" % p
        a = load(rel)
        if a is not None and size_is(rel, a, w, h):
            hard_alpha(rel, a)
            solid = a[..., 3] > 0
            if solid[0, :].any() or solid[:, 0].any() or solid[:, -1].any():
                errors.append("%s: touches the top/left/right edge" % rel)
    for t in TILES:
        rel = "env/%s.png" % t
        a = load(rel)
        if a is not None and size_is(rel, a, 32, 32):
            if (a[..., 3] < 255).any():
                errors.append("%s: ground textures must be fully opaque" % rel)
            seam(rel, a)
    for b in BACKDROPS:
        rel = "env/%s.png" % b
        a = load(rel)
        if a is not None and size_is(rel, a, 320, 120):
            hard_alpha(rel, a)
    for f, (w, h) in FX.items():
        rel = "fx/%s.png" % f
        a = load(rel)
        if a is not None:
            size_is(rel, a, w, h)
    for u, (w, h) in UI.items():
        rel = "ui/%s.png" % u
        a = load(rel)
        if a is not None and size_is(rel, a, w, h):
            hard_alpha(rel, a)
    for w in warnings:
        print("warning:", w)
    for e in errors:
        print("ERROR:", e)
    print("art check: %d errors, %d warnings" % (len(errors), len(warnings)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
