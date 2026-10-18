"""Swaps flat sprite props for 3D pieces in the data (DESIGN.md 5.6). Plain Python:

    python tools/blender_kit/swap_props.py SPRITE=PIECE[:TURN[:SCALE]] ... [--dry-run]

Every ZonePropData in data/ (zone sections, zones, arena looks) whose sprite is
assets/sprites/env/SPRITE.png gets `piece` set to data/pieces/PIECE.tres. Its position, flip and
solid radius stay; a sprite drawn at another pixel size than 0.05 gets the matching `scale`;
TURN (degrees) gives each copy a turn of up to that much either way, picked from the file and the
prop's id, so a row of the same piece does not look stamped (0 or none: no turn); SCALE sizes
every copy (for a piece bigger than the sprite it replaces). The sprite path
stays in the file (the piece wins; removing the piece brings the sprite back). Props that already
have a piece are left alone. Prints how many props each swap changed.
"""
from __future__ import annotations

import glob
import os
import re
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SPRITE_PIXEL = 0.05

SUB = re.compile(r'(\[sub_resource type="Resource" id="([^"]+)"\]\n)(.*?)(?=\n\n|\n\[|\Z)', re.S)


def _turn(file: str, sub_id: str, spread: float) -> float:
    if spread <= 0.0:
        return 0.0
    h = zlib.crc32(("%s|%s" % (os.path.basename(file), sub_id)).encode()) / 0xFFFFFFFF
    return round((h * 2.0 - 1.0) * spread, 1)


def swap_file(path: str, swaps: dict[str, tuple[str, float, float]]) -> dict[str, int]:
    with open(path, encoding="utf-8", newline="") as f:
        text = f.read()
    prop_script = re.search(r'\[ext_resource type="Script" path="res://scripts/data/zone_prop_data.gd" id="([^"]+)"\]', text)
    if not prop_script:
        return {}
    script_ref = 'script = ExtResource("%s")' % prop_script.group(1)
    counts: dict[str, int] = {}
    needed: set[str] = set()

    def edit(m: re.Match) -> str:
        head, sub_id, body = m.group(1), m.group(2), m.group(3)
        if script_ref not in body or "\npiece = " in "\n" + body:
            return m.group(0)
        sprite = re.search(r'sprite_path = "res://assets/sprites/env/(\w+)\.png"', body)
        if not sprite or sprite.group(1) not in swaps:
            return m.group(0)
        piece, spread, size = swaps[sprite.group(1)]
        lines = [body, 'piece = ExtResource("pc_%s")' % piece]
        turn = _turn(path, sub_id, spread)
        if turn:
            lines.append("rotation_y_degrees = %s" % turn)
        px = re.search(r"pixel_size = ([\d.]+)", body)
        scale = size * (float(px.group(1)) / SPRITE_PIXEL if px else 1.0)
        if abs(scale - 1.0) > 1e-6:
            lines.append("scale = %s" % round(scale, 3))
        counts[sprite.group(1)] = counts.get(sprite.group(1), 0) + 1
        needed.add(piece)
        return head + "\n".join(lines)

    text = SUB.sub(edit, text)
    if not needed:
        return {}
    exts = list(re.finditer(r'\[ext_resource [^\]]*\]\n', text))
    add = "".join('[ext_resource type="Resource" path="res://data/pieces/%s.tres" id="pc_%s"]\n' % (p, p)
                  for p in sorted(needed) if 'id="pc_%s"' % p not in text)
    at = exts[-1].end()
    text = text[:at] + add + text[at:]
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    return counts


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    swaps: dict[str, tuple[str, float, float]] = {}
    for a in args:
        sprite, _, rest = a.partition("=")
        piece, _, opts = rest.partition(":")
        spread, _, size = opts.partition(":")
        if not sprite or not piece:
            print("bad swap '%s' (want SPRITE=PIECE[:TURN])" % a)
            return 1
        if not os.path.exists(os.path.join(ROOT, "data", "pieces", piece + ".tres")):
            print("no piece file data/pieces/%s.tres (build it first)" % piece)
            return 1
        swaps[sprite] = (piece, float(spread or 0.0), float(size or 1.0))
    total: dict[str, int] = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "**", "*.tres"), recursive=True)):
        if dry:
            with open(path, encoding="utf-8") as f:
                text = f.read()
            for s in swaps:
                n = text.count('sprite_path = "res://assets/sprites/env/%s.png"' % s)
                if n:
                    total[s] = total.get(s, 0) + n
            continue
        for s, n in swap_file(path, swaps).items():
            total[s] = total.get(s, 0) + n
    for s in swaps:
        print("%s -> %s: %d props%s" % (s, swaps[s][0], total.get(s, 0), " (dry run)" if dry else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
