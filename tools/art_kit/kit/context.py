"""What a build step hands to each asset module: where files go, and saving with previews."""
from __future__ import annotations

import os
from typing import Mapping, Sequence

import numpy as np

from .clips import Cell, pack, previews, write_tres
from .sheet import preview, save_png, tiled_preview
from .specs import ENEMY_POSES, HERO_POSES

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.dirname(os.path.dirname(HERE))
ASSETS = os.path.join(PROJECT, "assets")
CLIPS_DIR = os.path.join(PROJECT, "data", "clips")
PREVIEW = os.path.join(HERE, "preview")


class Context:
    def __init__(self, module: str, write_assets: bool = True) -> None:
        self.module = module
        self.write_assets = write_assets
        self.saved: list[str] = []

    def save(self, rel: str, rgba: np.ndarray, frame_w: int | None = None, tile: bool = False,
             scale: int | None = None, frame_h: int | None = None) -> str:
        """Saves assets/<rel> (unless preview-only) and a zoomed preview in preview/<rel>.

        frame_w / frame_h: cell size of a sheet (the preview draws gaps between cells).
        tile: also save a 3x3 tiled preview (ground textures)."""
        rel = rel.replace("\\", "/")
        if self.write_assets:
            save_png(rgba, os.path.join(ASSETS, rel))
        h, w = rgba.shape[:2]
        if scale is None:
            scale = max(2, min(8, 900 // max(w, 1), 420 // max(h, 1)))
        preview(rgba, os.path.join(PREVIEW, rel), scale=scale, frame_w=frame_w, frame_h=frame_h)
        if tile:
            tiled_preview(rgba, os.path.join(PREVIEW, rel.replace(".png", "_tiled.png")))
        self.saved.append(rel)
        return rel

    def save_fighter(self, rel_png: str, legacy_frames: Sequence[np.ndarray],
                     clips: Mapping[str, Sequence[Cell]], cell: tuple[int, int], body_w: int,
                     clips_id: str, preview_ms: Mapping[str, int] | None = None) -> dict[str, list[int]]:
        """Saves a fighter: the grid sheet assets/<rel_png> and its layout data/clips/<clips_id>.tres
        (both skipped when preview-only), the sheet preview, a GIF per clip and a labelled contact
        sheet in preview/<module>/. Returns the clip name -> cell indices map.

        legacy_frames: the key poses in the legacy order (row 0), each `cell` (w, h) big.
        clips: name -> cells in play order: an RGBA array or an int row-0 key (kit.clips.render_clips
        turns a module's CLIPS spec into this).
        body_w: the fighter's width in the old one-row frame (the game sizes the shadow from it).
        preview_ms: review GIF lengths that differ from kit.clips.PREVIEW_MS (e.g. a fast idle)."""
        for i, f in enumerate(legacy_frames):
            if (f.shape[1], f.shape[0]) != tuple(cell):
                raise ValueError("%s: key %d is %dx%d, the cell is %dx%d"
                                 % (rel_png, i, f.shape[1], f.shape[0], cell[0], cell[1]))
        sheet, index_map, hframes, vframes = pack(legacy_frames, clips)
        self.save(rel_png, sheet, frame_w=cell[0], frame_h=cell[1])
        if self.write_assets:
            write_tres(os.path.join(CLIPS_DIR, clips_id + ".tres"), cell, hframes, vframes, body_w, index_map)
            self.saved.append("data/clips/%s.tres" % clips_id)
        enemy = "/enemies/" in "/" + rel_png.replace("\\", "/")
        keys = (ENEMY_POSES if enemy else HERO_POSES)[:len(legacy_frames)]
        previews(os.path.join(PREVIEW, self.module), self.module, sheet, cell, hframes, index_map, keys,
                 enemy=enemy, ms=preview_ms)
        return index_map

    def extra(self, name: str, rgba: np.ndarray, scale: int = 6, frame_w: int | None = None) -> str:
        """A review-only picture in preview/<module>/<name> (never a game file)."""
        path = os.path.join(PREVIEW, self.module, name)
        preview(rgba, path, scale=scale, frame_w=frame_w)
        return path
