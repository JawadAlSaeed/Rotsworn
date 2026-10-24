"""Checks the drawn art against the sprite contract (README.md). Exit 1 on any failure.

    python tools/art_kit/check.py
    python tools/art_kit/check.py --legacy <dir>        # row 0 must equal these one-row sheets
    python tools/art_kit/check.py --require hero_brin   # Tier 1 clips must exist (module or id)

Sizes and frame counts, alpha rules (fighters, portraits, props, tiles and icons: every pixel
fully opaque or fully clear), fighters standing on the bottom with a clear 1-pixel border,
nothing touching a frame edge, and ground textures that tile without visible seams.

Fighters with a data/clips/<id>.tres are checked as grid sheets (plan 2.4, DESIGN 5.5): the PNG is
frame_size x (hframes, vframes) and at most MAX_SHEET px; every clip index is a cell; row 0 holds
the legacy keys and nothing else; every used cell follows the border, alpha and feet rules; idle,
ready and the stands keep their top within 1 px of their key; walk cycles touch the floor on
frames 0 and N/2. With --legacy <dir> (holding characters/<id>.png and enemies/<id>.png one-row
sheets, e.g. a phase 9 copy), row 0 must equal those frames padded into the cells pixel for pixel.
Fighters without a .tres are checked as the old one-row sheets.
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from kit.clips import SCRIPT_PATH, pad_frame, read_tres  # noqa: E402
from kit.specs import (AIRBORNE, ENEMY_FRAME, ENEMY_POSES, FIGHTERS, FLOATERS, HERO_BODY_W,  # noqa: E402
                       HERO_CELL, HERO_FRAME, HERO_POSES, MAX_SHEET, PORTRAIT, STEADY_TOP, STEADY_TOP_PX,
                       TIER1_ENEMY, TIER1_HERO, TIER1_LEADER, TIER1_LEADERS)

ROOT = os.path.dirname(os.path.dirname(HERE))
SPRITES = os.path.join(ROOT, "assets", "sprites")
CLIPS_DIR = os.path.join(ROOT, "data", "clips")

HEROES = ["alder", "brin", "cass"]
PROPS = {"dead_tree": (48, 64), "rotten_tree": (64, 80), "rock": (32, 24), "pillar": (24, 56),
         "lamp": (16, 48), "glow_shroom": (24, 24), "grass": (24, 12)}
TILES = ["floor_tile", "cliff", "ruin_wall"]
# The open floors (card #186): three variants each, calm, seamless, no stripes.
FLOORS = ["hollow_floor", "ash_tile", "bog_tile", "throne_tile"]
FLOOR_FILES = [f + s for f in FLOORS for s in ("", "_b", "_c")]
# The ground patches that lie on the floor: also seamless and stripe-free (they may be busier).
PATCHES = ["leaf_litter", "moss"]
BACKDROPS = ["backdrop", "backdrop_ashen_ruins", "backdrop_sunken_bog", "backdrop_hollow_throne"]
FX = {"shadow": (32, 12), "shockwave": (64, 16), "slash": (32, 32), "spark": (16, 16)}
UI = {"ap_pip": (10, 10), "ap_pip_empty": (10, 10), "hit_normal": (12, 12), "hit_ground": (12, 12),
      "lock": (12, 12), "controller": (32, 22), "map_paper": (440, 520), "map_roller": (450, 16), "map_shop": (24, 24),
      "map_rest": (24, 24), "map_zone_rotten_hollow": (24, 24), "map_zone_sunken_bog": (24, 24),
      "map_zone_ashen_ruins": (24, 24), "map_lair_hollow_king": (32, 32), "map_flag": (14, 22),
      "map_ring": (30, 30), "map_ring_big": (40, 40), "map_guard": (24, 24)}
# Map pictures that float on the paper (no ground under them): a clear 1-pixel border all round, so
# their outline is never cut off at the frame's edge.
UI_CLEAR_BORDER = ["map_elite", "map_event", "map_guard", "map_ring", "map_ring_big"]

# The "?" pictures (card #199): one per event file in data/events/, and one per act's ambush page.
EVENT_PICTURE = (128, 64)
EVENT_PICTURE_COLOURS = 96
AMBUSH_PICTURES = ["ambush_rotten_road", "ambush_ashen_deep"]

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
    """An old one-row sheet (a fighter with no data/clips/<id>.tres)."""
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
    idle = frames(a, fw)[0][..., 3] > 0
    rows = np.nonzero(idle.any(axis=1))[0]
    if len(rows) and (rows[-1] - rows[0] + 1) < fh * 0.5:
        warnings.append("%s: idle is only %d px tall in a %d px frame" % (rel, rows[-1] - rows[0] + 1, fh))


def _rows(solid: np.ndarray) -> np.ndarray:
    return np.nonzero(solid.any(axis=1))[0]


def fighter_grid(rel: str, a: np.ndarray, cid: str, hero: bool, legacy_dir: str | None,
                 require: bool) -> None:
    """A grid sheet with its data/clips/<cid>.tres (see the module doc)."""
    tres = "data/clips/%s.tres" % cid
    info = read_tres(os.path.join(CLIPS_DIR, cid + ".tres"))
    if info["script"] != SCRIPT_PATH:
        errors.append("%s: script is %r, should be %s" % (tres, info["script"], SCRIPT_PATH))
    fw, fh = info["frame_size"]
    hf, vf = info["hframes"], info["vframes"]
    if hero:
        if (fw, fh) != HERO_CELL:
            errors.append("%s: frame_size %dx%d, hero cells are %dx%d" % (tres, fw, fh, *HERO_CELL))
        if info["body_width_px"] != HERO_BODY_W:
            errors.append("%s: body_width_px %d, should be %d" % (tres, info["body_width_px"], HERO_BODY_W))
    else:
        base = ENEMY_FRAME[cid]
        if fw != fh or fw < base or (fw - base) % 2:
            errors.append("%s: frame_size %dx%d, enemy cells are squares of at least %d (grown evenly)"
                          % (tres, fw, fh, base))
        if info["body_width_px"] != base:
            errors.append("%s: body_width_px %d, should be %d (sizes the shadow)"
                          % (tres, info["body_width_px"], base))
    if not size_is(rel, a, fw * hf, fh * vf):
        return
    if a.shape[0] > MAX_SHEET or a.shape[1] > MAX_SHEET:
        errors.append("%s: %dx%d is over %d px on a side" % (rel, a.shape[1], a.shape[0], MAX_SHEET))
    hard_alpha(rel, a)
    poses = HERO_POSES if hero else ENEMY_POSES
    n_keys = len(poses)
    if hf < n_keys:
        errors.append("%s: %d columns cannot hold the %d legacy keys in row 0" % (tres, hf, n_keys))
        return
    n = hf * vf
    cells = [a[(i // hf) * fh:(i // hf + 1) * fh, (i % hf) * fw:(i % hf + 1) * fw] for i in range(n)]
    solid = [c[..., 3] > 0 for c in cells]
    clips: dict[str, list[int]] = info["clips"]
    used: dict[int, list[str]] = {}
    for name, idx in sorted(clips.items()):
        if not idx:
            errors.append("%s: clip %r has no cells" % (tres, name))
        for i in idx:
            if not 0 <= i < n:
                errors.append("%s: clip %r uses cell %d, the sheet has %d (0..%d)" % (tres, name, i, n, n - 1))
            elif name not in used.setdefault(i, []):
                used[i].append(name)
    floats = cid in FLOATERS
    for i in range(n):
        what = poses[i] if i < n_keys else (", ".join(used.get(i, [])) or "unused")
        name = "%s cell %d (%s)" % (rel, i, what)
        if n_keys <= i < hf:
            if solid[i].any():
                errors.append("%s: row 0 holds only the %d legacy keys; this cell must be clear" % (name, n_keys))
            continue
        if not solid[i].any():
            if i < n_keys or i in used:
                errors.append("%s: empty" % name)
            continue
        if i >= n_keys and i not in used:
            warnings.append("%s: not used by any clip" % name)
        s = solid[i]
        if s[0, :].any() or s[:, 0].any() or s[:, -1].any():
            errors.append("%s: touches the top/left/right edge (clipped or no outline room)" % name)
        airborne = floats or (i < n_keys and poses[i] == "jump") or any(c in AIRBORNE for c in used.get(i, []))
        if not airborne and _rows(s)[-1] < fh - 3:
            warnings.append("%s: lowest pixel on row %d, not standing on the bottom" % (name, _rows(s)[-1]))
    if solid[0].any():
        r0 = _rows(solid[0])
        tall = int(r0[-1] - r0[0] + 1)
        old_h = HERO_FRAME[1] if hero else ENEMY_FRAME[cid]
        if tall < old_h * 0.5:
            warnings.append("%s: idle is only %d px tall (old frame %d px)" % (rel, tall, old_h))
    # Steady loops: the game measures head and popup anchors on cell 0 only. The ready key itself
    # is a crouch below the idle top, so ready is measured from its own key.
    for name in STEADY_TOP:
        idx = [i for i in clips.get(name, []) if 0 <= i < n and solid[i].any()]
        if not idx:
            continue
        key = idx[0] if name == "ready" else 0
        if not solid[key].any():
            continue
        top = int(_rows(solid[key])[0])
        for i in idx:
            t = int(_rows(solid[i])[0])
            if abs(t - top) > STEADY_TOP_PX:
                errors.append("%s: clip %r cell %d top is row %d, %d px from its key's row %d (at most %d)"
                              % (rel, name, i, t, abs(t - top), top, STEADY_TOP_PX))
    if clips.get("idle") and clips["idle"][0] != 0:
        warnings.append("%s: clip 'idle' should start on cell 0 (the idle key)" % tres)
    # Walk cycles plant a foot on frames 0 and N/2 (the footstep moments).
    if not floats:
        for name, idx in sorted(clips.items()):
            if not name.startswith("walk") or not idx:
                continue
            for k in sorted({0, len(idx) // 2}):
                i = idx[k]
                if 0 <= i < n and solid[i].any() and _rows(solid[i])[-1] < fh - 2:
                    errors.append("%s: clip %r frame %d (cell %d) does not touch the floor (lowest row %d)"
                                  % (rel, name, k, i, _rows(solid[i])[-1]))
    if legacy_dir:
        kind = "characters" if hero else "enemies"
        path = os.path.join(legacy_dir, kind, cid + ".png")
        if not os.path.exists(path):
            errors.append("%s: no legacy sheet %s to compare row 0 with" % (rel, path))
        else:
            old = np.asarray(Image.open(path).convert("RGBA"))
            ow = HERO_FRAME[0] if hero else ENEMY_FRAME[cid]
            if old.shape[1] != ow * n_keys:
                errors.append("%s: legacy sheet is %d px wide, expected %d one-row frames of %d"
                              % (path, old.shape[1], n_keys, ow))
            else:
                for i in range(n_keys):
                    want = pad_frame(old[:, i * ow:(i + 1) * ow], (fw, fh))
                    diff = int(np.count_nonzero(np.any(want != cells[i], axis=2)))
                    if diff:
                        errors.append("%s cell %d (%s): %d px differ from the legacy frame"
                                      % (rel, i, poses[i], diff))
    if require:
        need = (TIER1_HERO + (TIER1_LEADER if cid in TIER1_LEADERS else [])) if hero else TIER1_ENEMY
        missing = [c for c in need if c not in clips]
        if missing:
            errors.append("%s: Tier 1 clips missing: %s" % (tres, ", ".join(missing)))


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


def luma(a: np.ndarray) -> np.ndarray:
    return a[..., :3].astype(float) @ np.array([0.299, 0.587, 0.114])


def calm(rel: str, a: np.ndarray, max_std: float) -> None:
    """A floor must be low contrast and must not stripe: the average of each row (or column) may
    not swing more than a share of the tile's own spread, or tiling it draws bands across the
    screen. Both are the complaint behind card #186."""
    l = luma(a)
    std = l.std()
    if std > max_std:
        errors.append("%s: too busy for a floor (luma spread %.1f, at most %.1f)" % (rel, std, max_std))
    rows, cols = l.mean(1).std(), l.mean(0).std()
    if max(rows, cols) > 0.45 * std + 1.0:
        errors.append("%s: stripes when tiled (row averages vary %.1f, column %.1f, spread %.1f)"
                      % (rel, rows, cols, std))


def main() -> int:
    ap = argparse.ArgumentParser(description="Checks the art against the sprite contract.")
    ap.add_argument("--legacy", metavar="DIR",
                    help="folder with characters/<id>.png and enemies/<id>.png one-row sheets; row 0 "
                         "of every grid sheet must equal them pixel for pixel")
    ap.add_argument("--require", nargs="*", default=[], metavar="NAME",
                    help="fighter modules or ids (or 'all') whose Tier 1 clips must all exist")
    args = ap.parse_args()
    ids = set(FIGHTERS.values())
    require: set[str] = set()
    for r in args.require:
        if r == "all":
            require |= ids
        elif r in FIGHTERS:
            require.add(FIGHTERS[r])
        elif r in ids:
            require.add(r)
        else:
            errors.append("--require %s: not a fighter module or id (%s)" % (r, ", ".join(sorted(FIGHTERS))))
    grid_n = 0
    for e in HEROES + list(ENEMY_FRAME):
        hero = e in HEROES
        rel = ("characters/%s.png" if hero else "enemies/%s.png") % e
        has_clips = os.path.exists(os.path.join(CLIPS_DIR, e + ".tres"))
        if e in require and not has_clips:
            errors.append("%s: --require needs data/clips/%s.tres" % (rel, e))
        a = load(rel)
        if a is None:
            continue
        if has_clips:
            grid_n += 1
            fighter_grid(rel, a, e, hero, args.legacy, e in require)
        elif hero:
            fighter(rel, a, HERO_FRAME[0], HERO_FRAME[1], len(HERO_POSES), HERO_POSES)
        else:
            fighter(rel, a, ENEMY_FRAME[e], ENEMY_FRAME[e], len(ENEMY_POSES), ENEMY_POSES, floats=e in FLOATERS)
    if os.path.isdir(CLIPS_DIR):
        for f in sorted(os.listdir(CLIPS_DIR)):
            if f.endswith(".tres") and f[:-5] not in HEROES and f[:-5] not in ENEMY_FRAME:
                warnings.append("data/clips/%s: no fighter sheet of that id" % f)
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
    means: dict[str, list[float]] = {}
    for t in FLOOR_FILES + PATCHES:
        rel = "env/%s.png" % t
        a = load(rel)
        if a is not None and size_is(rel, a, 32, 32):
            if (a[..., 3] < 255).any():
                errors.append("%s: ground textures must be fully opaque" % rel)
            seam(rel, a)
            calm(rel, a, 10.0 if t in FLOOR_FILES else 16.0)
            if t in FLOOR_FILES:
                means.setdefault(t.rsplit("_", 1)[0] if t[-2:] in ("_b", "_c") else t, []).append(luma(a).mean())
    for name, m in means.items():
        if len(m) == 3 and max(m) - min(m) > 3.0:
            errors.append("env/%s: variants differ in tone by %.1f luma, so the floor would blotch"
                          % (name, max(m) - min(m)))
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
    for u in UI_CLEAR_BORDER:
        rel = "ui/%s.png" % u
        a = load(rel)
        if a is not None:
            solid = a[..., 3] > 0
            if solid[0, :].any() or solid[-1, :].any() or solid[:, 0].any() or solid[:, -1].any():
                errors.append("%s: touches a frame edge (clipped or no outline room)" % rel)
    events_dir = os.path.join(ROOT, "data", "events")
    event_ids = sorted(f[:-5] for f in os.listdir(events_dir) if f.endswith(".tres")) if os.path.isdir(events_dir) else []
    for e in event_ids + AMBUSH_PICTURES:
        rel = "events/%s.png" % e
        a = load(rel)
        if a is not None and size_is(rel, a, *EVENT_PICTURE):
            if (a[..., 3] != 255).any():
                errors.append("%s: event pictures must be fully opaque" % rel)
            n = len({tuple(int(v) for v in px) for px in a.reshape(-1, 4)})
            if n > EVENT_PICTURE_COLOURS:
                errors.append("%s: %d colours (at most %d)" % (rel, n, EVENT_PICTURE_COLOURS))
    for w in warnings:
        print("warning:", w)
    for e in errors:
        print("ERROR:", e)
    print("art check: %d errors, %d warnings (%d grid sheets%s)" % (
        len(errors), len(warnings), grid_n, "; row 0 compared with " + args.legacy if args.legacy else ""))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
