"""Animation clips for fighter sheets (phase 10, DESIGN.md 5.5, plan 2.4-2.5).

A fighter is one grid sheet plus a generated `SpriteClips` resource (data/clips/<id>.tres) that
names its clips. Row 0 holds the legacy key poses in the legacy order (heroes idle..down, enemies
idle..slam), so every old `set_pose(int)` still shows the right frame. Every clip starts its own
row and wraps after SHEET_COLS cells. A clip only lists which cells play, in order; a repeated
cell holds longer. How long a clip plays is the game's business (combat_visuals.tres), never the
art's.

    cam = cell_camera(Camera(*HERO_FRAME), HERO_CELL)     # the legacy camera, padded to the cell
    keys = [render_pose(POSES[n], cam) for n in HERO_POSES]
    cells = render_clips(CLIPS, lambda p: render_pose(p, cam))
    ctx.save_fighter("sprites/characters/x.png", keys, cells, HERO_CELL, HERO_BODY_W, "x")

API:
  cell_camera(cam, cell) -> CellCamera   the legacy frame camera widened to a bigger cell
  pad_frame(rgba, cell) -> rgba          a legacy frame placed in a cell (centred, on the floor)
  render_clips(spec, render) -> clips    CLIPS spec (int keys and pose dicts) -> cells for pack
  pack(legacy, clips, cols, max_px) -> (sheet, index_map, hframes, vframes)
  write_tres(path, frame_size, hframes, vframes, body_width_px, index_map)
  read_tres(path) -> dict                the same fields back (script defaults when left out)
  previews(out_dir, module, sheet, ...)  a GIF per clip and a labelled contact sheet
"""
from __future__ import annotations

import hashlib
import os
import re
from dataclasses import dataclass
from typing import Any, Callable, Mapping, Sequence

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from .render import Camera
from .sheet import grid
from .specs import MAX_SHEET, SHEET_COLS, SHEET_COLS_WIDE

Cell = np.ndarray | int

SCRIPT_PATH = "res://scripts/data/sprite_clips.gd"
# SpriteClips script defaults (scripts/data/sprite_clips.gd): Godot leaves a default out when it
# re-saves a file, so read_tres falls back to these.
TRES_DEFAULTS: dict[str, Any] = {"frame_size": (48, 56), "hframes": 8, "vframes": 1, "body_width_px": 32}


# --- Camera ---------------------------------------------------------------------------------------


@dataclass
class CellCamera(Camera):
    """Camera(W, H) for a cell that is a legacy frame plus `pad_x` clear pixels on the left and the
    right and `pad_top` on top. It is the same view as a plain Camera(W, H) (centred, fixed scale,
    feet on the second-to-last row), but its maths runs in the legacy frame's coordinates with the
    legacy depth origin, so a pose renders to bit-identical pixels inside the legacy area. A plain
    Camera(48, 56) differs from the 32x48 render by a few pixels on some poses (float rounding at
    grazing rays and a farther ray start), which would break row 0 = the phase 9 frames."""

    pad_x: int = 0
    pad_top: int = 0

    def __post_init__(self) -> None:
        super().__post_init__()
        iw, ih = self._inner()
        self.z0 = max(iw, ih) * self.scale * 2.0

    def _inner(self) -> tuple[int, int]:
        return self.W - 2 * self.pad_x, self.H - self.pad_top

    def project(self, p: Sequence[float]) -> tuple[float, float, float]:
        iw, ih = self._inner()
        v = self.view(p)
        px = (v[0] - self.cx) / self.scale + iw / 2.0
        py = ih - 0.5 - (v[1] - self.cy) / self.scale
        return px + self.pad_x, py + self.pad_top, self.z0 - v[2]

    def rays(self, ss: int) -> tuple[np.ndarray, np.ndarray]:
        iw, ih = self._inner()
        offs = (np.arange(ss) + 0.5) / ss
        xs = ((np.arange(self.W) - self.pad_x)[:, None] + offs[None, :]).reshape(-1)
        ys = ((np.arange(self.H) - self.pad_top)[:, None] + offs[None, :]).reshape(-1)
        gy, gx = np.meshgrid(ys, xs, indexing="ij")
        vx = (gx - iw / 2.0) * self.scale + self.cx
        vy = (ih - gy) * self.scale + self.cy - 0.5 * self.scale
        V = np.stack([vx.ravel(), vy.ravel(), np.full(vx.size, self.z0)], axis=1)
        O = V @ self.R
        D = np.array([0.0, 0.0, -1.0]) @ self.R
        return O, D


def cell_camera(cam: Camera, cell: tuple[int, int]) -> CellCamera:
    """`cam` (a legacy frame camera, e.g. Camera(32, 48) or a module's lifted variant) widened to
    `cell` (w, h): the extra width split evenly left and right, the extra height all on top."""
    pad_w = cell[0] - cam.W
    pad_h = cell[1] - cam.H
    if pad_w < 0 or pad_h < 0 or pad_w % 2:
        raise ValueError("cell %s cannot hold a %dx%d frame centred" % (cell, cam.W, cam.H))
    return CellCamera(cell[0], cell[1], scale=cam.scale, yaw=cam.yaw, pitch=cam.pitch, cx=cam.cx,
                      cy=cam.cy, face=cam.face, pad_x=pad_w // 2, pad_top=pad_h)


def pad_frame(rgba: np.ndarray, cell: tuple[int, int]) -> np.ndarray:
    """A legacy frame inside a bigger cell exactly where cell_camera renders it: centred left to
    right, standing on the same bottom row."""
    h, w = rgba.shape[:2]
    pad_w, pad_h = cell[0] - w, cell[1] - h
    if pad_w < 0 or pad_h < 0 or pad_w % 2:
        raise ValueError("cell %s cannot hold a %dx%d frame centred" % (cell, w, h))
    out = np.zeros((cell[1], cell[0], 4), dtype=np.uint8)
    out[pad_h:, pad_w // 2:pad_w // 2 + w] = rgba
    return out


# --- Clips -> sheet -------------------------------------------------------------------------------


def _norm(v: Any) -> Any:
    if isinstance(v, np.ndarray):
        return tuple(_norm(x) for x in v.tolist())
    if isinstance(v, (list, tuple)):
        return tuple(_norm(x) for x in v)
    if isinstance(v, dict):
        return tuple(sorted((k, _norm(x)) for k, x in v.items()))
    if isinstance(v, (np.floating, np.integer)):
        return v.item()
    return v


def render_clips(spec: Mapping[str, Sequence[Any]],
                 render: Callable[[dict[str, Any]], np.ndarray]) -> dict[str, list[Cell]]:
    """An asset module's CLIPS (name -> entries: an int row-0 key, a pose dict or a finished RGBA
    cell) -> cells for pack(). A pose dict is rendered once however often it appears."""
    done: dict[Any, np.ndarray] = {}
    out: dict[str, list[Cell]] = {}
    for name, entries in spec.items():
        cells: list[Cell] = []
        for e in entries:
            if isinstance(e, (int, np.integer)) and not isinstance(e, bool):
                cells.append(int(e))
            elif isinstance(e, np.ndarray):
                cells.append(e)
            elif isinstance(e, dict):
                key = _norm(e)
                if key not in done:
                    done[key] = render(e)
                cells.append(done[key])
            else:
                raise TypeError("clip %r: an entry must be an int key, a pose dict or an RGBA array" % name)
        out[name] = cells
    return out


def _digest(a: np.ndarray) -> str:
    return hashlib.sha1(str(a.shape).encode() + np.ascontiguousarray(a).tobytes()).hexdigest()


def _layout(n_legacy: int, new_counts: Sequence[int], cols: int) -> tuple[int, list[int]]:
    """Rows needed and the first cell of each clip's new frames (-1 = the clip adds none)."""
    rows = 1
    starts = []
    for k in new_counts:
        if k == 0:
            starts.append(-1)
            continue
        starts.append(rows * cols)
        rows += (k + cols - 1) // cols
    return rows, starts


def pack(legacy: Sequence[np.ndarray], clips: Mapping[str, Sequence[Cell]], cols: int = SHEET_COLS,
         max_px: int = MAX_SHEET) -> tuple[np.ndarray, dict[str, list[int]], int, int]:
    """Lays a fighter out on a grid sheet: row 0 = the legacy keys in order, then one fresh row
    per clip that brings new frames (wrapping after `cols`). Identical frames (same bytes) are
    stored once; an int entry is a row-0 key. Switches to SHEET_COLS_WIDE columns only when `cols`
    would make the sheet taller than `max_px`.

    Returns (sheet RGBA, index_map name -> cell indices in play order, hframes, vframes)."""
    if not legacy:
        raise ValueError("pack: no legacy frames")
    h, w = legacy[0].shape[:2]
    for i, f in enumerate(legacy):
        if f.shape != (h, w, 4):
            raise ValueError("pack: legacy frame %d is %s, expected %dx%d RGBA" % (i, f.shape, w, h))
    n_legacy = len(legacy)

    # Which frames are new, clip by clip, first appearance first (legacy keys count as seen).
    seen: dict[str, tuple[int, int]] = {}  # digest -> (clip number or -1 for row 0, order)
    for i, f in enumerate(legacy):
        seen.setdefault(_digest(f), (-1, i))
    new_frames: list[list[np.ndarray]] = []
    refs: list[list[tuple[int, int]]] = []  # per clip entry: (clip number or -1, order)
    for ci, (name, cells) in enumerate(clips.items()):
        if not cells:
            raise ValueError("pack: clip %r is empty" % name)
        mine: list[np.ndarray] = []
        r: list[tuple[int, int]] = []
        for e in cells:
            if isinstance(e, (int, np.integer)) and not isinstance(e, bool):
                if not 0 <= int(e) < n_legacy:
                    raise ValueError("pack: clip %r: key %d is not a row-0 pose (0..%d)" % (name, e, n_legacy - 1))
                r.append((-1, int(e)))
                continue
            if not isinstance(e, np.ndarray) or e.shape != (h, w, 4):
                raise ValueError("pack: clip %r: a cell must be a %dx%d RGBA array or an int key" % (name, w, h))
            d = _digest(e)
            if d not in seen:
                seen[d] = (ci, len(mine))
                mine.append(e.astype(np.uint8))
            r.append(seen[d])
        new_frames.append(mine)
        refs.append(r)

    counts = [len(m) for m in new_frames]
    for c in ([cols] if cols != SHEET_COLS else [SHEET_COLS, SHEET_COLS_WIDE]):
        if n_legacy > c:
            raise ValueError("pack: %d legacy frames do not fit a %d-column row 0" % (n_legacy, c))
        rows, starts = _layout(n_legacy, counts, c)
        if rows * h <= max_px and c * w <= max_px:
            break
    else:
        raise ValueError("pack: %d rows of %dx%d cells exceed %d px even at %d columns"
                         % (rows, w, h, max_px, c))

    cells: list[np.ndarray | None] = [None] * (rows * c)
    for i, f in enumerate(legacy):
        cells[i] = f.astype(np.uint8)
    for ci, mine in enumerate(new_frames):
        for j, f in enumerate(mine):
            cells[starts[ci] + j] = f
    index_map = {name: [k if ci < 0 else starts[ci] + k for ci, k in refs[n]]
                 for n, name in enumerate(clips)}
    return grid(cells, c, (w, h)), index_map, c, rows


# --- The SpriteClips resource ---------------------------------------------------------------------


def write_tres(path: str, frame_size: tuple[int, int], hframes: int, vframes: int, body_width_px: int,
               index_map: Mapping[str, Sequence[int]]) -> str:
    """Writes the SpriteClips .tres exactly as the game expects it (plan 2.1): no uid, keys sorted,
    so the same clips always give the same file."""
    lines = [
        '[gd_resource type="Resource" script_class="SpriteClips" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="%s" id="1_clips"]' % SCRIPT_PATH,
        "",
        "[resource]",
        'script = ExtResource("1_clips")',
        "frame_size = Vector2i(%d, %d)" % (int(frame_size[0]), int(frame_size[1])),
        "hframes = %d" % int(hframes),
        "vframes = %d" % int(vframes),
        "body_width_px = %d" % int(body_width_px),
    ]
    names = sorted(index_map)
    for name in names:
        if not re.fullmatch(r"[a-z0-9_]+", name):
            raise ValueError("clip name %r: use lower-case letters, digits and _" % name)
    if names:
        lines.append("clips = {")
        entries = ['"%s": PackedInt32Array(%s)' % (n, ", ".join(str(int(i)) for i in index_map[n]))
                   for n in names]
        lines.append(",\n".join(entries))
        lines.append("}")
    else:
        lines.append("clips = {}")
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    return path


def read_tres(path: str) -> dict[str, Any]:
    """Reads a SpriteClips .tres back (a regex reader, not a Godot parser): frame_size, hframes,
    vframes, body_width_px, clips (name -> list of ints) and script (its path or None)."""
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    out: dict[str, Any] = dict(TRES_DEFAULTS)
    m = re.search(r'\[ext_resource[^\]]*type="Script"[^\]]*path="([^"]+)"', text)
    out["script"] = m.group(1) if m else None
    m = re.search(r"^frame_size = Vector2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)", text, re.M)
    if m:
        out["frame_size"] = (int(m.group(1)), int(m.group(2)))
    for key in ("hframes", "vframes", "body_width_px"):
        m = re.search(r"^%s = (-?\d+)\s*$" % key, text, re.M)
        if m:
            out[key] = int(m.group(1))
    clips: dict[str, list[int]] = {}
    m = re.search(r"^clips = \{(.*?)\}", text, re.M | re.S)
    if m:
        for name, body in re.findall(r'(?:&)?"([^"]+)"\s*:\s*PackedInt32Array\(([^)]*)\)', m.group(1)):
            clips[name] = [int(x) for x in body.replace(" ", "").split(",") if x != ""]
    out["clips"] = clips
    return out


# --- Previews -------------------------------------------------------------------------------------

# Review GIF lengths in ms. They mirror the defaults in combat_visuals.tres
# (plan 2.3) so a GIF moves at about game speed; the game, not this table, decides the real ones.
PREVIEW_MS: dict[str, int] = {
    "idle": 1600, "ready": 900, "down": 2400, "stand_front": 1600, "stand_back": 1600,
    "draw": 450, "parry": 150, "parry_hit": 200, "dodge": 250, "jump_up": 240, "jump_down": 240,
    "hurt": 320, "stagger": 480, "strike": 270, "strike_alt": 270, "strike_big": 270, "cast": 270,
    "follow_up": 270, "ultimate_1": 270, "ultimate_2": 270, "leap": 220, "fall": 360,
    "get_up": 420, "victory": 600, "victory_hold": 1200, "pickup": 700, "run": 400, "rage": 700,
    # A walk cycle is two steps: walk_stride 1.0 at explore_walk_speed 4.5 u/s.
    "walk_side": 444, "walk_front": 444, "walk_back": 444,
}
ENEMY_PREVIEW_MS: dict[str, int] = {
    "idle": 1800, "windup": 240, "windup_ground": 240, "windup_hold": 160, "lunge": 180,
    "contact": 160, "recoil": 120, "return": 260, "slam": 260, "slam_recover": 200, "hurt": 320,
    "stagger": 480, "death": 400, "rage": 700,
    # Two steps per cycle: roam_stride 0.9 at 1.2 u/s (wander), 3.6 u/s (chase).
    "walk": 1500, "chase": 500,
}
WINDUP_MS = 220
DEFAULT_MS = 400
HOLD_MS = 600  # a one-shot GIF rests on its last cell this long before it starts again
LOOPS = {"idle", "ready", "down", "stand_front", "stand_back", "walk_side", "walk_front", "walk_back",
         "walk", "chase", "run", "windup_hold", "victory_hold"}
GIF_SCALE = 6
FLOOR_BG = (34, 31, 40)      # the dark zone floor of the other previews
FLOOR_LINE = (52, 48, 60)    # a band under the feet, so floor contact reads
INK = (226, 218, 200)
DIM = (150, 144, 136)


def preview_ms(name: str, enemy: bool = False, overrides: Mapping[str, int] | None = None) -> int:
    """How long the review GIF plays `name`: the override, the table, then the clip-name fallbacks
    of the game (`<x>_b` -> `<x>`, `<prefix>_<x>` -> `<x>`, `*_windup`, any other hero name plays
    as a strike)."""
    table = dict(ENEMY_PREVIEW_MS if enemy else PREVIEW_MS)
    table.update(overrides or {})
    if name in table:
        return table[name]
    base = name[:-2] if name.endswith("_b") else name
    if base in table:
        return table[base]
    parts = base.split("_")
    for i in range(1, len(parts)):
        tail = "_".join(parts[i:])
        if tail in table:
            return table[tail]
    if base.endswith("_windup"):
        return WINDUP_MS
    # The game plays any other unknown hero clip as a strike (a per-skill name).
    return DEFAULT_MS if enemy else PREVIEW_MS["strike"]


def _font(size: int = 12) -> ImageFont.ImageFont:
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # older Pillow: bitmap font only
        return ImageFont.load_default()


def _cell(sheet: np.ndarray, frame_size: tuple[int, int], hframes: int, i: int) -> np.ndarray:
    w, h = frame_size
    r, c = divmod(i, hframes)
    return sheet[r * h:(r + 1) * h, c * w:(c + 1) * w]


def _on_floor(rgba: np.ndarray, scale: int) -> Image.Image:
    """One cell zoomed on the dark floor with a lighter band under the bottom row."""
    h, w = rgba.shape[:2]
    band = 2
    tile = Image.new("RGBA", (w * scale, (h + band) * scale), FLOOR_BG + (255,))
    ImageDraw.Draw(tile).rectangle([0, h * scale, w * scale, (h + band) * scale], fill=FLOOR_LINE + (255,))
    img = Image.fromarray(rgba.astype(np.uint8), "RGBA").resize((w * scale, h * scale), Image.NEAREST)
    tile.alpha_composite(img)
    return tile


def _durations(n: int, total_ms: int) -> list[int]:
    """n frame lengths spread evenly over total_ms, rounded to the GIF's 10 ms ticks without drift."""
    marks = [int(round(total_ms * k / n / 10.0)) * 10 for k in range(n + 1)]
    return [max(10, b - a) for a, b in zip(marks, marks[1:])]


def write_gif(path: str, cells: Sequence[np.ndarray], total_ms: int, loop: bool,
              scale: int = GIF_SCALE) -> str:
    """The cells spread evenly over total_ms (as the game plays a one-shot); a one-shot then rests
    on its last cell for HOLD_MS before starting again."""
    frames = [_on_floor(c, scale).convert("RGB") for c in cells]
    durs = _durations(len(frames), total_ms)
    if not loop:
        durs[-1] += HOLD_MS
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=durs, loop=0, disposal=1,
                   optimize=False)
    return path


def contact_sheet(path: str, title: str, sheet: np.ndarray, frame_size: tuple[int, int], hframes: int,
                  index_map: Mapping[str, Sequence[int]], key_names: Sequence[str], enemy: bool,
                  ms: Mapping[str, int] | None = None) -> str:
    """Every clip as a labelled row of its cells (row 0 = the legacy keys), zoomed, on the floor."""
    w, h = frame_size
    scale = max(2, min(4, 200 // h))
    font = _font(12)
    label_w = 170
    gap = 6
    cap = 16
    rows: list[tuple[str, str, list[int], list[str]]] = [
        ("row 0 (keys)", "legacy poses", list(range(len(key_names))), list(key_names))]
    for name, cells in index_map.items():
        n_ms = preview_ms(name, enemy, ms)
        kind = "loop" if name in LOOPS else "one-shot"
        rows.append((name, "%d cells, %d ms %s" % (len(cells), n_ms, kind), list(cells),
                     ["#%d" % i for i in cells]))
    most = max(len(r[2]) for r in rows)
    tile_w, tile_h = w * scale, (h + 2) * scale
    out_w = label_w + most * (tile_w + gap) + gap
    head = 26
    out_h = head + len(rows) * (tile_h + cap + gap) + gap
    out = Image.new("RGBA", (out_w, out_h), (24, 22, 28, 255))
    d = ImageDraw.Draw(out)
    d.text((gap, 6), title, fill=INK + (255,), font=font)
    for r, (name, sub, cells, caps) in enumerate(rows):
        y = head + r * (tile_h + cap + gap)
        d.text((gap, y + 4), name, fill=INK + (255,), font=font)
        d.text((gap, y + 20), sub, fill=DIM + (255,), font=font)
        for k, (i, c) in enumerate(zip(cells, caps)):
            x = label_w + k * (tile_w + gap)
            out.alpha_composite(_on_floor(_cell(sheet, frame_size, hframes, i), scale), (x, y))
            d.text((x + 2, y + tile_h + 1), c, fill=DIM + (255,), font=font)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    out.save(path)
    return path


def previews(out_dir: str, module: str, sheet: np.ndarray, frame_size: tuple[int, int], hframes: int,
             index_map: Mapping[str, Sequence[int]], key_names: Sequence[str], enemy: bool = False,
             ms: Mapping[str, int] | None = None) -> list[str]:
    """Review pictures for a fighter: <out_dir>/clips/<name>.gif per clip (game-speed, 6x, dark
    floor; stale GIFs of removed clips are deleted) and <out_dir>/<module>_clips.png, a labelled
    contact sheet of every clip."""
    written = []
    gif_dir = os.path.join(out_dir, "clips")
    if os.path.isdir(gif_dir):
        for f in os.listdir(gif_dir):
            if f.endswith(".gif") and f[:-4] not in index_map:
                os.remove(os.path.join(gif_dir, f))
    for name, cells in index_map.items():
        frames = [_cell(sheet, frame_size, hframes, i) for i in cells]
        written.append(write_gif(os.path.join(gif_dir, name + ".gif"), frames,
                                 preview_ms(name, enemy, ms), name in LOOPS))
    vframes = sheet.shape[0] // frame_size[1]
    title = "%s: %dx%d cells, %d x %d grid (%dx%d px), %d clips" % (
        module, frame_size[0], frame_size[1], hframes, vframes, sheet.shape[1], sheet.shape[0],
        len(index_map))
    written.append(contact_sheet(os.path.join(out_dir, module + "_clips.png"), title, sheet, frame_size,
                                 hframes, index_map, key_names, enemy, ms))
    return written
