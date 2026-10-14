"""Builds the game's pixel art from the asset modules in tools/art_kit/assets/.

    python tools/art_kit/build.py                 # every module
    python tools/art_kit/build.py hero_alder fx   # only these modules
    python tools/art_kit/build.py --preview-only hero_alder   # previews, game files untouched
    python tools/art_kit/build.py --list

Each module defines build(ctx) and saves its pictures with ctx.save(...). Game files go to
res://assets/..., zoomed previews for review to tools/art_kit/preview/ (not in git). After a
build, run Godot's import (run_game.bat does it) so the game picks the files up.
"""
from __future__ import annotations

import argparse
import importlib
import os
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from kit.context import Context  # noqa: E402

ASSET_DIR = os.path.join(HERE, "assets")


def modules() -> list[str]:
    return sorted(f[:-3] for f in os.listdir(ASSET_DIR) if f.endswith(".py") and not f.startswith("_"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--preview-only", action="store_true")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    names = args.names or modules()
    if args.list:
        print("\n".join(modules()))
        return 0
    failed = 0
    for name in names:
        t = time.time()
        ctx = Context(name, write_assets=not args.preview_only)
        try:
            mod = importlib.import_module("assets." + name)
            mod.build(ctx)
            print("%-18s ok   %5.1fs  %s" % (name, time.time() - t, ", ".join(ctx.saved)))
        except Exception:
            failed += 1
            print("%-18s FAIL" % name)
            traceback.print_exc()
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
