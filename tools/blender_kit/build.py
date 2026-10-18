"""Builds the game's 3D world pieces in Blender (DESIGN.md 5.6). Runs with no window:

    blender --background --factory-startup --python tools/blender_kit/build.py -- [names...] [--out DIR] [--preview [FILE]]

No names: every piece. Writes one .glb per piece into assets/models/ (or --out) and prints each
piece's size in game axes (x, height, depth). A piece with no data file yet gets one
(data/pieces/<name>.tres with its surfaces' textures; never overwritten, not with --out).
--preview also renders the review sheet (default tools/blender_kit/preview/pieces.png, not in git). Then run `python tools/blender_kit/check.py`.
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
DEFAULT_OUT = os.path.join(ROOT, "assets", "models")

import bpy  # noqa: E402

from kit import piece as kit_piece  # noqa: E402
from kit import preview  # noqa: E402
from pieces import PIECES  # noqa: E402


def _args() -> tuple[list[str], str, str]:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names: list[str] = []
    out = DEFAULT_OUT
    shot = ""
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--out" and i + 1 < len(argv):
            out = argv[i + 1]
            i += 2
            continue
        if a == "--preview":
            if i + 1 < len(argv) and not argv[i + 1].startswith("--") and argv[i + 1].endswith(".png"):
                shot = argv[i + 1]
                i += 2
                continue
            shot = os.path.join(HERE, "preview", "pieces.png")
        elif not a.startswith("--"):
            names.append(a)
        i += 1
    return names, out, shot


def main() -> None:
    names, out, shot = _args()
    unknown = [n for n in names if n not in PIECES]
    if unknown:
        print("BLENDER_KIT_ERROR unknown pieces: %s (known: %s)" % (", ".join(unknown), ", ".join(PIECES)))
        sys.exit(1)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj)
    built = []
    for name in names or list(PIECES):
        p = PIECES[name]
        obj = kit_piece.make(p)
        kit_piece.export(obj, out)
        size = kit_piece.game_size(obj)
        tris = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
        print("PIECE %s size=Vector3(%.3f, %.3f, %.3f) triangles=%d surfaces=%s"
              % (name, size.x, size.y, size.z, tris, ",".join(s.name for s in p.surfaces)))
        made = kit_piece.write_data(p, obj, ROOT) if out == DEFAULT_OUT else ""
        if made:
            print("DATA %s" % made)
        built.append((p, obj))
    if shot:
        preview.render(built, shot, ROOT)
        print("PREVIEW %s" % shot)
    print("BLENDER_KIT_DONE %d" % len(built))


main()
