"""Saving sprite sheets and making zoomed preview pictures for review."""
from __future__ import annotations

import os
from typing import Sequence

import numpy as np
from PIL import Image

# Preview backgrounds: a dark zone floor, a mid stone grey and a pale menu tone.
PREVIEW_BGS = ((34, 31, 40), (88, 84, 92), (178, 170, 156))


def hstack(frames: Sequence[np.ndarray]) -> np.ndarray:
    """One-row sheet of equal frames (the game's sprite sheet layout)."""
    h = frames[0].shape[0]
    for f in frames:
        assert f.shape[0] == h and f.shape[1] == frames[0].shape[1], "frames must be the same size"
    return np.concatenate(list(frames), axis=1)


def grid(frames: Sequence[np.ndarray | None], cols: int, cell: tuple[int, int] | None = None) -> np.ndarray:
    """Frames laid out left to right, top to bottom, `cols` per row (a fighter's grid sheet).
    None leaves that cell clear. Every frame must be the cell size ((w, h); taken from the first
    frame when not given)."""
    if cell is None:
        first = next(f for f in frames if f is not None)
        cell = (first.shape[1], first.shape[0])
    w, h = cell
    rows = max(1, (len(frames) + cols - 1) // cols)
    out = np.zeros((rows * h, cols * w, 4), dtype=np.uint8)
    for i, f in enumerate(frames):
        if f is None:
            continue
        assert f.shape[0] == h and f.shape[1] == w, "frame %d is %dx%d, cells are %dx%d" % (
            i, f.shape[1], f.shape[0], w, h)
        r, c = divmod(i, cols)
        out[r * h:(r + 1) * h, c * w:(c + 1) * w] = f
    return out


def save_png(arr: np.ndarray, path: str) -> str:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    Image.fromarray(arr.astype(np.uint8), "RGBA").save(path, optimize=True)
    return path


def preview(arr: np.ndarray, path: str, scale: int = 6, frame_w: int | None = None,
            bgs: Sequence[tuple[int, int, int]] = PREVIEW_BGS, frame_h: int | None = None) -> str:
    """Saves the image zoomed `scale` times on each background (stacked), with thin gaps between
    frames when frame_w is given (and between rows of a grid sheet when frame_h is given), so a
    reviewer can judge it like it will look in game."""
    h, w = arr.shape[:2]
    img = Image.fromarray(arr.astype(np.uint8), "RGBA")
    big = img.resize((w * scale, h * scale), Image.NEAREST)
    gap = 4
    fw = frame_w or w
    fh = frame_h or h
    n_cols = w // fw
    n_rows = h // fh
    block_w = w * scale + (n_cols - 1) * gap
    block_h = h * scale + (n_rows - 1) * gap
    out = Image.new("RGBA", (block_w, (block_h + gap) * len(bgs)), (0, 0, 0, 255))
    for i, bg in enumerate(bgs):
        y0 = i * (block_h + gap)
        for r in range(n_rows):
            for c in range(n_cols):
                tile = Image.new("RGBA", (fw * scale, fh * scale), bg + (255,))
                crop = big.crop((c * fw * scale, r * fh * scale, (c + 1) * fw * scale, (r + 1) * fh * scale))
                tile.alpha_composite(crop)
                out.paste(tile, (c * (fw * scale + gap), y0 + r * (fh * scale + gap)))
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    out.save(path)
    return path


def tiled_preview(arr: np.ndarray, path: str, times: int = 3, scale: int = 4) -> str:
    """A ground texture repeated times x times (to spot seams and repetition)."""
    tiled = np.tile(arr, (times, times, 1))
    img = Image.fromarray(tiled.astype(np.uint8), "RGBA")
    img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    img.save(path)
    return path
