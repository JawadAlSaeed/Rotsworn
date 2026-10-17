"""Cuts the DragonRot wordmark out of the studio intro for the main menu's corner (DESIGN.md 7.5).

    python tools/branding/studio_logo.py

The intro (assets/video/dragonrot_intro.ogv, made by render_intro.py) is the only source of the
studio logo: it is drawn by code, with no picture file. This takes one clean frame (after the
drips, before the fade), crops the "DragonRot" letters (not the small "DEVELOPED BY" line) and turns
the near-black background see-through: the letters sit on black, so a pixel's alpha is its
brightness above the background, and its colour is un-blended from black.
Writes assets/branding/dragonrot_logo.png. Needs ffmpeg and Pillow.
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
VIDEO = os.path.join(REPO, "assets", "video", "dragonrot_intro.ogv")
OUT = os.path.join(REPO, "assets", "branding", "dragonrot_logo.png")
FRAME_S = 3.1  # the wordmark is whole and still here
# A pixel brighter than LETTER_MIN (0-255, brightest channel) is part of a letter; the background,
# its stars and the faint green glow stay below it.
LETTER_MIN = 110
# Alpha ramps from 0 at FADE_FROM to 1 at FADE_TO (brightest channel), keeping the letters' soft
# edges and dropping the background.
FADE_FROM = 40
FADE_TO = 150
# Background stars are a few pixels each: bright specks in groups smaller than this are dropped,
# and a row or column counts as part of the letters only with at least LINE_MIN bright pixels.
SPECK_MAX = 60
LINE_MIN = 4
PAD = 6
# The saved logo's height: about three times its size in the menu corner, scaled smoothly, so it
# stays clean when the game draws it small (with mipmaps, see its .import).
OUT_HEIGHT = 120


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        frame_path = os.path.join(tmp, "frame.png")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(FRAME_S), "-i", VIDEO, "-frames:v", "1",
                        frame_path], check=True)
        frame = Image.open(frame_path).convert("RGB")
    w, h = frame.size
    px = frame.load()
    # The letters' box: the tallest run of bright rows (the small line above is a separate run).
    rows = [sum(1 for x in range(0, w, 2) if max(px[x, y]) > LETTER_MIN) >= LINE_MIN for y in range(h)]
    runs, start = [], None
    for y, bright in enumerate(rows + [False]):
        if bright and start is None:
            start = y
        elif not bright and start is not None:
            runs.append((start, y))
            start = None
    top, bottom = max(runs, key=lambda r: r[1] - r[0])
    cols = [x for x in range(w) if sum(1 for y in range(top, bottom) if max(px[x, y]) > LETTER_MIN) >= LINE_MIN]
    box = (max(0, cols[0] - PAD), max(0, top - PAD), min(w, cols[-1] + 1 + PAD), min(h, bottom + PAD))
    crop = frame.crop(box)
    out = Image.new("RGBA", crop.size)
    src = crop.load()
    dst = out.load()
    for y in range(crop.size[1]):
        for x in range(crop.size[0]):
            r, g, b = src[x, y]
            a = min(1.0, max(0.0, (max(r, g, b) - FADE_FROM) / float(FADE_TO - FADE_FROM)))
            if a <= 0.0:
                dst[x, y] = (0, 0, 0, 0)
            else:
                # Seen on black, a pixel is colour x coverage: undo that so edges keep their colour.
                cover = max(r, g, b) / 255.0 or 1.0
                k = min(1.0 / cover, 4.0) if a < 1.0 else 1.0
                dst[x, y] = (min(255, int(r * k)), min(255, int(g * k)), min(255, int(b * k)), int(a * 255))
    _drop_specks(out)
    width = max(1, round(out.size[0] * OUT_HEIGHT / out.size[1]))
    out = out.resize((width, OUT_HEIGHT), Image.LANCZOS)
    out.save(OUT)
    print("wrote %s %dx%d" % (OUT, out.size[0], out.size[1]))
    return 0


def _drop_specks(image: Image.Image) -> None:
    """Clears every group of visible pixels smaller than SPECK_MAX (the intro's stars)."""
    w, h = image.size
    px = image.load()
    seen = bytearray(w * h)
    for y0 in range(h):
        for x0 in range(w):
            if seen[y0 * w + x0] or px[x0, y0][3] == 0:
                continue
            group, stack = [], [(x0, y0)]
            seen[y0 * w + x0] = 1
            while stack:
                x, y = stack.pop()
                group.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny][3] > 0:
                        seen[ny * w + nx] = 1
                        stack.append((nx, ny))
            if len(group) < SPECK_MAX:
                for x, y in group:
                    px[x, y] = (0, 0, 0, 0)


if __name__ == "__main__":
    sys.exit(main())
