"""The "Controller recommended" picture in the logo's style (card #167, user 2026-10-18: "one with
the game logo style"): a gamepad drawn like the crest behind ROTSWORN, flat worn-gold lines on
nothing, no bevels or shine, the edges crumbling. The outline is a double line like Alder's shield
in the crest (a thick line and a thin one inside it), with the cross pad, four buttons, two sticks
and the staff's little gem between the shoulders.

    python tools/branding/controller_mark.py

Writes assets/branding/controller_mark.png (shown by ControllerNotice; path and size in
data/branding/branding.tres). Uses minimal_branding.py's renderer and wear, so it needs what that
tool needs (Godot console build, OpenCV, NumPy, Pillow).
"""
import os

import cv2
import numpy as np

import minimal_branding as mn
from paint_branding import REPO

OUT = os.path.join(REPO, "assets", "branding", "controller_mark.png")
W, H = 1300, 900            # canvas (emblem units, before minimal_branding.SCALE)
CX, CY = 650, 440           # where the pad's centre sits on the canvas
OUTER, INNER = 14, 5        # the body's double line, like the crest shield's (12, 4)
PART = 9                    # cross pad, buttons and sticks
INSET = 0.9                 # the inner line is the body scaled this much about the centre
WEAR = 0.7                  # the crest's "rough" wear
SPECKS = 70

# The body: a classic pad, wide shoulders and two grips; top edge slightly arched.
BODY = ("M -300,-210 C -100,-238 100,-238 300,-210 C 400,-198 448,-150 460,-60 C 480,80 472,200 432,265 "
        "C 402,318 330,322 300,286 C 250,230 220,150 160,130 L -160,130 C -220,150 -250,230 -300,286 "
        "C -330,322 -402,318 -432,265 C -472,200 -480,80 -460,-60 C -448,-150 -400,-198 -300,-210 Z")


def cross(cx, cy, arm, half):
    """A plus sign's outline: arms `arm` long from the centre, `half` wide each side."""
    p = [(-half, -arm), (half, -arm), (half, -half), (arm, -half), (arm, half), (half, half), (half, arm),
         (-half, arm), (-half, half), (-arm, half), (-arm, -half), (-half, -half)]
    return "M" + " L".join(f"{cx + x},{cy + y}" for x, y in p) + " Z"


def parts():
    """name -> SVG fragment (white shapes; the wear is added after rendering)."""
    stroke = 'fill="none" stroke="#fff" stroke-linejoin="round"'
    buttons = "".join(f'<circle cx="{250 + dx}" cy="{-40 + dy}" r="25" {stroke} stroke-width="{PART}"/>'
                      for dx, dy in ((0, -64), (64, 0), (0, 64), (-64, 0)))
    sticks = "".join(f'<circle cx="{x}" cy="58" r="46" {stroke} stroke-width="{PART}"/>'
                     f'<circle cx="{x}" cy="58" r="14" fill="#fff"/>' for x in (-128, 128))
    return {
        "body": (f'<path d="{BODY}" {stroke} stroke-width="{OUTER}"/>'
                 f'<path d="{BODY}" transform="scale({INSET})" {stroke} stroke-width="{INNER}"/>'),
        "inside": (f'<path d="{cross(-250, -40, 96, 26)}" {stroke} stroke-width="{PART}"/>' + buttons + sticks
                   # the staff's gem from the crest, small, between the shoulders
                   + '<path d="M0,-150 L16,-118 L0,-96 L-16,-118 Z" fill="#fff"/>'),
    }


def main() -> int:
    head = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">'
    svgs = {name: f'{head}<g transform="translate({CX},{CY})">{svg}</g></svg>' for name, svg in parts().items()}
    masks = mn.render(svgs, "controller_mark")
    rng = np.random.default_rng(mn.SEED)
    st = dict(mn.STYLES["rough"])
    px = mn.SCALE
    shape = masks["body"].shape
    out = mn.Layer(shape)
    every = np.zeros(shape, np.float32)
    for name in ("body", "inside"):
        col, a, _ = mn.worn(masks[name], mn.GOLD_FLAT, rng, px, WEAR, st)
        out.over(col, a)
        every = np.maximum(every, masks[name])
    out.over(mn.ramp(mn.GOLD_FLAT, np.full(shape, 0.7, np.float32)), mn.specks(shape, every, rng, px, SPECKS))
    image, _ = mn.crop_all({"logo": out.image()})
    image["logo"].save(OUT)
    print("wrote %s %dx%d" % (OUT, image["logo"].size[0], image["logo"].size[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
