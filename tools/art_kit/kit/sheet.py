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


def save_png(arr: np.ndarray, path: str) -> str:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    Image.fromarray(arr.astype(np.uint8), "RGBA").save(path, optimize=True)
    return path


def preview(arr: np.ndarray, path: str, scale: int = 6, frame_w: int | None = None,
            bgs: Sequence[tuple[int, int, int]] = PREVIEW_BGS) -> str:
    """Saves the image zoomed `scale` times on each background (stacked), with thin gaps between
    frames when frame_w is given, so a reviewer can judge it like it will look in game."""
    h, w = arr.shape[:2]
    img = Image.fromarray(arr.astype(np.uint8), "RGBA")
    big = img.resize((w * scale, h * scale), Image.NEAREST)
    gap = 4
    n_frames = (w // frame_w) if frame_w else 1
    out_w = w * scale + (n_frames - 1) * gap
    out = Image.new("RGBA", (out_w, (h * scale + gap) * len(bgs)), (0, 0, 0, 255))
    for i, bg in enumerate(bgs):
        y0 = i * (h * scale + gap)
        if frame_w:
            for f in range(n_frames):
                x0 = f * (frame_w * scale + gap)
                tile = Image.new("RGBA", (frame_w * scale, h * scale), bg + (255,))
                crop = big.crop((f * frame_w * scale, 0, (f + 1) * frame_w * scale, h * scale))
                tile.alpha_composite(crop)
                out.paste(tile, (x0, y0))
        else:
            tile = Image.new("RGBA", (w * scale, h * scale), bg + (255,))
            tile.alpha_composite(big)
            out.paste(tile, (0, y0))
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
