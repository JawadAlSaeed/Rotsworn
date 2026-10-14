"""What a build step hands to each asset module: where files go, and saving with previews."""
from __future__ import annotations

import os

import numpy as np

from .sheet import preview, save_png, tiled_preview

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.dirname(os.path.dirname(HERE))
ASSETS = os.path.join(PROJECT, "assets")
PREVIEW = os.path.join(HERE, "preview")


class Context:
    def __init__(self, module: str, write_assets: bool = True) -> None:
        self.module = module
        self.write_assets = write_assets
        self.saved: list[str] = []

    def save(self, rel: str, rgba: np.ndarray, frame_w: int | None = None, tile: bool = False,
             scale: int | None = None) -> str:
        """Saves assets/<rel> (unless preview-only) and a zoomed preview in preview/<rel>.

        frame_w: frame width of a one-row sheet (preview draws gaps between frames).
        tile: also save a 3x3 tiled preview (ground textures)."""
        rel = rel.replace("\\", "/")
        if self.write_assets:
            save_png(rgba, os.path.join(ASSETS, rel))
        h, w = rgba.shape[:2]
        if scale is None:
            scale = max(2, min(8, 900 // max(w, 1), 420 // max(h, 1)))
        preview(rgba, os.path.join(PREVIEW, rel), scale=scale, frame_w=frame_w)
        if tile:
            tiled_preview(rgba, os.path.join(PREVIEW, rel.replace(".png", "_tiled.png")))
        self.saved.append(rel)
        return rel

    def extra(self, name: str, rgba: np.ndarray, scale: int = 6, frame_w: int | None = None) -> str:
        """A review-only picture in preview/<module>/<name> (never a game file)."""
        path = os.path.join(PREVIEW, self.module, name)
        preview(rgba, path, scale=scale, frame_w=frame_w)
        return path
