"""The Rotsworn logo (card #47): minimal, in the spirit of the Clair Obscur: Expedition 33 logo.
Slim knightly capitals (Cinzel 600) in flat, worn gold on black: no bevels, shine or shadows,
the edges crumbling. Behind the word, large and faint, the crest drawn flat: Alder's shield as an
outline, Brin's twin daggers crossed, Cass's staff, and one ribbon tied straight across them, its
tails flowing off to the right. Where one part passes in front of another a thin gap is cut.

    python tools/branding/minimal_branding.py            the game's logo and icon (user pick: B, rough)
    python tools/branding/minimal_branding.py options    every layout and style, for choosing

The game's files (assets/branding/):
  rotsworn_logo.png             the whole logo, still (menus, loading cards, credits)
  rotsworn_logo_back.png        title screen: the faint crest without the ribbon's tails
  rotsworn_logo_tails.png       title screen: the ribbon's tails (they sway)
  rotsworn_logo_front.png       title screen: the letters, cracks only (the wear is drawn live)
  rotsworn_logo_front_edge.png  title screen: how far each pixel is from a letter's edge, for the
                                moving wear ("static"): 0.5 is the edge, 1 is EDGE_RANGE px inside
  icon_1024.png, icon.png, icon.ico  the crest alone on a black tile
"""
import math
import os
import subprocess
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw

import make_branding as mb
from paint_branding import GODOT, REPO, blur, cracks, fbm, ramp

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out", "options")
LAYERS = os.path.join(HERE, "out", "layers_min")
BRANDING = os.path.join(REPO, "assets", "branding")
SCALE = 1.5
SEED = 11
## The edge map spans this many pixels each way from a letter's edge (BrandingData.letters_edge_range_px).
EDGE_RANGE = 24.0
## Room left round the logo when it is cropped (pixels): the tails sway, specks fall off the edges.
MARGIN = 40

GOLD_FLAT = [(0.0, (78, 54, 26)), (0.35, (146, 106, 56)), (0.6, (198, 160, 102)), (0.82, (232, 206, 156)),
             (1.0, (250, 236, 204))]
BONE_FLAT = [(0.0, (110, 100, 82)), (0.45, (178, 166, 142)), (0.8, (222, 212, 190)), (1.0, (242, 236, 220))]
CROSS_Y = -150.0
GAP = 7.0                   # the cut between overlapping parts (emblem units)

# Two looks. "rough" is the one the user picked: thin crest lines, heavy crumbling wear.
STYLES = {
    "rough": dict(dagger_half=15, guard=(70, 14, 9, 72), grip=18, pommel=(18, 16, 30), fuller=(5, 22),
                  shield=(12, 4), staff=(12, 9, 10, 462), ribbon=(28, 24, 20),
                  near_px=5.0, patches=False, crest_wear=0.7, letter_wear=1.0, specks=160, ribbon_alpha=None),
    "clean": dict(dagger_half=19, guard=(74, 18, 12, 76), grip=22, pommel=(22, 20, 34), fuller=(6, 24),
                  shield=(18, 6), staff=(16, 13, 13, 466), ribbon=(38, 32, 26),
                  near_px=2.5, patches=True, crest_wear=0.3, letter_wear=0.7, specks=50, ribbon_alpha=0.3),
}


# --- flat crest -------------------------------------------------------------------------------

def band(points, width, swallowtail=0.0, per=20):
    """A flat strip along a smooth line; swallowtail cuts a V into its far end (share of width)."""
    pts = np.array(points, np.float64)
    path = []
    for i in range(len(pts) - 1):
        p0, p1 = pts[max(0, i - 1)], pts[i]
        p2, p3 = pts[i + 1], pts[min(len(pts) - 1, i + 2)]
        for t in np.linspace(0, 1, per, endpoint=False):
            t2, t3 = t * t, t * t * t
            path.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    path.append(pts[-1])
    path = np.array(path)
    left, right = [], []
    for i, p in enumerate(path):
        d = path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]
        n = np.array([-d[1], d[0]]) / (np.linalg.norm(d) + 1e-9)
        left.append(p + n * width / 2)
        right.append(p - n * width / 2)
    end = path[-1]
    d = path[-1] - path[-2]
    d /= np.linalg.norm(d) + 1e-9
    notch = [end - d * width * swallowtail] if swallowtail else []
    poly = left + notch + right[::-1]
    return '<path d="M' + " L".join(f"{x:.1f},{y:.1f}" for x, y in poly) + ' Z" fill="#fff"/>'


def dagger(angle, st):
    """A slim flat dagger turned by `angle` about the crossing; the fuller is a separate cut."""
    t = f'transform="translate(0,{CROSS_Y}) rotate({angle})"'
    hilt, length, half = -380, 900, st["dagger_half"]
    gw, gh, gr, gx = st["guard"]
    pa, pb, pc = st["pommel"]
    fw, fy = st["fuller"]
    g, tip = hilt + 150, hilt + length
    body = (f'<path {t} d="M{-half},{g} L{half},{g} L{half * 0.8},{tip - 80} L0,{tip} L{-half * 0.8},{tip - 80} Z" fill="#fff"/>'
            f'<rect {t} x="{-gw}" y="{g - gh / 2}" width="{2 * gw}" height="{gh}" rx="3" fill="#fff"/>'
            f'<rect {t} x="{-st["grip"] / 2}" y="{hilt + 30}" width="{st["grip"]}" height="{g - hilt - 30}" fill="#fff"/>'
            f'<path {t} d="M0,{hilt - pa} L{pb},{hilt + 6} L0,{hilt + pc} L{-pb},{hilt + 6} Z" fill="#fff"/>'
            f'<circle {t} cx="{-gx}" cy="{g}" r="{gr}" fill="#fff"/><circle {t} cx="{gx}" cy="{g}" r="{gr}" fill="#fff"/>')
    fuller = f'<rect {t} x="{-fw / 2}" y="{g + fy}" width="{fw}" height="{(tip - g) * 0.5}" fill="#fff"/>'
    return body, fuller


def crest_parts(st):
    w, top, point = 250, -300, 360
    a_body, a_fuller = dagger(-36, st)
    b_body, b_fuller = dagger(36, st)
    outer = mb.shield_path(w, top, point)
    inner = mb.shield_path(w, top, point, 26)
    so, si = st["shield"]
    sw, rw, fw, foot = st["staff"]
    band_w, tail_a, tail_b = st["ribbon"]
    tails = (band([(250, CROSS_Y + 2), (300, CROSS_Y - 10), (352, CROSS_Y + 8), (404, CROSS_Y - 6), (452, CROSS_Y + 6)], tail_a, swallowtail=0.9)
             + band([(250, CROSS_Y + 10), (292, CROSS_Y + 30), (338, CROSS_Y + 26), (384, CROSS_Y + 44)], tail_b, swallowtail=0.9))
    across = band([(-262, CROSS_Y + 6), (-150, CROSS_Y - 4), (-40, CROSS_Y + 4), (80, CROSS_Y - 4), (200, CROSS_Y + 4), (262, CROSS_Y)], band_w)
    return {
        "shield": f'<path d="{outer}" fill="none" stroke="#fff" stroke-width="{so}"/><path d="{inner}" fill="none" stroke="#fff" stroke-width="{si}"/>',
        "dagger_a": a_body, "fuller_a": a_fuller,
        "dagger_b": b_body, "fuller_b": b_fuller,
        "staff": (f'<rect x="{-sw / 2}" y="-470" width="{sw}" height="900" fill="#fff"/>'
                  f'<path d="M{-fw},430 L{fw},430 L0,{foot} Z" fill="#fff"/>'
                  f'<circle cx="0" cy="-555" r="34" fill="none" stroke="#fff" stroke-width="{rw}"/>'
                  '<path d="M0,-650 L10,-604 L0,-589 L-10,-604 Z" fill="#fff"/>'
                  '<path d="M-14,-500 C-50,-512 -70,-540 -66,-574 C-56,-550 -38,-528 -10,-518 Z" fill="#fff"/>'
                  '<path d="M14,-500 C50,-512 70,-540 66,-574 C56,-550 38,-528 10,-518 Z" fill="#fff"/>'
                  '<rect x="-14" y="-506" width="28" height="16" fill="#fff"/>'),
        # the ribbon tied straight across the crest at the crossing, its tails flowing right
        "ribbon": across + tails,
        # not drawn on its own: tells which part of the ribbon is the tails (they sway on the title)
        "ribbon_tails": tails,
        "ribbon_band": across,
    }


# Back to front; each part is cut where a part in front of it passes over.
CREST_ORDER = ["shield", "dagger_a", "dagger_b", "staff", "ribbon"]
CUTS = {"dagger_a": "fuller_a", "dagger_b": "fuller_b"}


# --- layouts ----------------------------------------------------------------------------------

def layouts():
    """name -> (canvas w, h, crest place (tx, ty, scale), crest opacity, words [(text, size, cx, baseline)])."""
    return {
        "crest_above": (1800, 1000, (900, 400, 0.5), 1.0, [("ROTSWORN", 190, 900, 850)]),
        "crest_behind": (1800, 1150, (900, 600, 0.85), 0.42, [("ROTSWORN", 220, 900, 690)]),
        "split": (2200, 900, (1060, 450, 0.55), 1.0, [("ROT", 200, 590, 520), ("SWORN", 200, 1760, 520)]),
        "icon": (1024, 1024, (512, 560, 0.74), 1.0, []),
    }


def render(svgs, tag):
    os.makedirs(LAYERS, exist_ok=True)
    args = [GODOT, "--headless", "--path", REPO, "-s", "tools/branding/render_svg.gd", "--", str(SCALE)]
    for name, svg in svgs.items():
        src = os.path.join(LAYERS, f"{tag}_{name}.svg")
        with open(src, "w", encoding="utf-8", newline="\n") as f:
            f.write(svg)
        args += [src, os.path.join(LAYERS, f"{tag}_{name}.png")]
    subprocess.run(args, check=True, capture_output=True, timeout=300)
    return {name: np.asarray(Image.open(os.path.join(LAYERS, f"{tag}_{name}.png")).convert("RGBA"), np.float32)[:, :, 3] / 255.0
            for name in svgs}


def worn(mask, stops, rng, px, wear, st):
    """Flat worn gold: a soft two-way gradient with brushed streaks, chipped and pitted at the
    edges, a few hairline breaks. Returns (rgb, alpha, alpha with the cracks only)."""
    shape = mask.shape
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    tone = 0.55 + 0.18 * np.sin(xx / w * math.pi * 2.2 + 0.6) + 0.12 * (1 - yy / h) + (fbm(shape, 120 * px, 3, rng) - 0.5) * 0.35
    streaks = cv2.resize(rng.random((max(2, int(h / (1.2 * px))), max(2, int(w / (80 * px)))), dtype=np.float32), (w, h),
                         interpolation=cv2.INTER_CUBIC)
    tone += (streaks - 0.5) * 0.12
    col = ramp(stops, tone)
    d = cv2.distanceTransform((mask > 0.5).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    near = np.exp(-d / (st["near_px"] * px))
    if st["patches"]:
        where = np.clip((fbm(shape, 60 * px, 3, rng) - 0.5) * 4.0, 0.0, 1.0)     # wear comes in patches
        pits = (fbm(shape, 2.2 * px, 2, rng) * (0.5 + 0.6 * near) * (0.6 + 0.6 * where)) > 0.8 - 0.06 * wear
        chips = (fbm(shape, 6 * px, 3, rng) * near * where) > 0.5 - 0.06 * wear
        line, _ = cracks(shape, rng, px, 90)
        line *= np.clip((fbm(shape, 90 * px, 2, rng) - 0.55) * 6.0, 0.0, 1.0)
    else:
        pits = (fbm(shape, 2.2 * px, 2, rng) * (0.55 + 0.75 * near)) > 0.74 - 0.08 * wear
        chips = (fbm(shape, 7 * px, 3, rng) * near) > 0.42 - 0.06 * wear
        line, _ = cracks(shape, rng, px, 80)
    cracked = mask * (1 - np.clip(line * 1.4 * wear, 0, 1))
    alpha = cracked * (1 - pits) * (1 - chips)
    return np.clip(col, 0, 1), np.clip(alpha, 0, 1), np.clip(cracked, 0, 1)


def specks(shape, near_mask, rng, px, count):
    """A few flakes of gold just off the edges, like the worn edges are crumbling."""
    out = np.zeros(shape, np.float32)
    band_ = (blur(near_mask, 8 * px) > 0.05) & (near_mask < 0.5)
    ys, xs = np.nonzero(band_)
    if len(ys) == 0:
        return out
    for i in rng.choice(len(ys), size=min(count, len(ys)), replace=False):
        cv2.circle(out, (int(xs[i]), int(ys[i])), int(rng.uniform(0.6, 1.8) * px), 0.85, -1, cv2.LINE_AA)
    return out


class Layer:
    def __init__(self, shape):
        self.rgb = np.zeros(shape + (3,), np.float32)
        self.a = np.zeros(shape, np.float32)

    def over(self, c, a):
        out_a = a + self.a * (1 - a)
        self.rgb = (c * a[..., None] + self.rgb * (self.a * (1 - a))[..., None]) / np.maximum(out_a, 1e-6)[..., None]
        self.a = out_a

    def image(self):
        return Image.fromarray((np.concatenate([np.clip(self.rgb, 0, 1), self.a[..., None]], -1) * 255 + 0.5).astype(np.uint8), "RGBA")


def build(name, style):
    """{"logo", "back", "tails", "front", "edge"} images, all the same size (uncropped)."""
    st = STYLES[style]
    W, H, (tx, ty, sc), crest_alpha, words = layouts()[name]
    head = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">'
    svgs = {part: f'{head}<g transform="translate({tx},{ty}) scale({sc})">{svg}</g></svg>' for part, svg in crest_parts(st).items()}
    letters = []
    for text, size, cx, base in words:
        paths, _ = mb.word_paths(text, size, cx, base, tracking=0.07, weight=600)
        letters += [d for d, _, _ in paths]
    svgs["letters"] = head + "".join(f'<path d="{d}" fill="#fff"/>' for d in letters) + "</svg>"
    m = render(svgs, f"{name}_{style}")
    rng = np.random.default_rng(SEED)
    px = SCALE
    shape = m["letters"].shape
    gap_k = max(3, int(GAP * sc * SCALE) | 1)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (gap_k, gap_k))
    # crest: cut each part where the parts in front of it pass over, then the fullers
    crest = {}
    for i, part in enumerate(CREST_ORDER):
        mask = m[part].copy()
        front = np.zeros(shape, np.float32)
        for later in CREST_ORDER[i + 1:]:
            front = np.maximum(front, m[later])
        mask *= 1 - cv2.dilate(front, kernel)
        if part in CUTS:
            mask *= 1 - m[CUTS[part]]
        crest[part] = mask
    back, tails = Layer(shape), Layer(shape)
    tails_only = np.clip(m["ribbon_tails"] * (1 - m["ribbon_band"]), 0, 1)
    for part in CREST_ORDER:
        col, a, _ = worn(crest[part], BONE_FLAT if part == "ribbon" else GOLD_FLAT, rng, px, st["crest_wear"], st)
        if name == "crest_behind":
            boost = st["ribbon_alpha"] if part == "ribbon" and st["ribbon_alpha"] else 0.0
            a = a * min(1.0, crest_alpha + boost)
        if part == "ribbon":
            tails.over(col, a * tails_only)
            a = a * (1 - tails_only)
        back.over(col, a)
    # the crest is cut away round the letters in the 'behind' layout so they read cleanly
    if name == "crest_behind":
        halo = cv2.dilate(m["letters"], cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (int(10 * px) | 1,) * 2))
        back.a *= 1 - halo
        tails.a *= 1 - halo
    front, live = Layer(shape), Layer(shape)
    if words:
        col, a, cracked = worn(m["letters"], GOLD_FLAT, rng, px, st["letter_wear"], st)
        front.over(col, a)
        front.over(ramp(GOLD_FLAT, np.full(shape, 0.7, np.float32)), specks(shape, m["letters"], rng, px, st["specks"]))
        live.over(col, cracked)
    logo = back.image()
    logo.alpha_composite(tails.image())
    logo.alpha_composite(front.image())
    inside = cv2.distanceTransform((m["letters"] > 0.5).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    outside = cv2.distanceTransform((m["letters"] <= 0.5).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    edge = np.clip(0.5 + (inside - outside) / (2 * EDGE_RANGE), 0, 1)
    return {"logo": logo, "back": back.image(), "tails": tails.image(), "front": live.image(),
            "edge": Image.fromarray((edge * 255 + 0.5).astype(np.uint8), "L")}


def crop_all(images, margin=MARGIN):
    x0, y0, x1, y1 = images["logo"].getbbox()
    w, h = images["logo"].size
    box = (max(0, x0 - margin), max(0, y0 - margin), min(w, x1 + margin), min(h, y1 + margin))
    return {k: v.crop(box) for k, v in images.items()}, box


def make_icon():
    """The crest alone, clean style (it must read at 16 px), on a black rounded tile."""
    crest = build("icon", "clean")["logo"]
    crest = crest.crop(crest.getbbox())
    n = 1024
    tile = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle((16, 16, n - 16, n - 16), radius=170, fill=(11, 11, 12, 255))
    fit = int(n * 0.84)
    crest.thumbnail((fit, fit), Image.LANCZOS)
    tile.alpha_composite(crest, ((n - crest.width) // 2, (n - crest.height) // 2))
    return tile


def write_game_files():
    images, box = crop_all(build("crest_behind", "rough"))
    for key, name in (("logo", "rotsworn_logo"), ("back", "rotsworn_logo_back"), ("tails", "rotsworn_logo_tails"),
                      ("front", "rotsworn_logo_front"), ("edge", "rotsworn_logo_front_edge")):
        images[key].save(os.path.join(BRANDING, f"{name}.png"))
    size = images["logo"].size
    # the knot the tails hang from: the band's right end
    tx, ty, sc = layouts()["crest_behind"][2]
    root = ((262 * sc + tx) * SCALE - box[0], (CROSS_Y * sc + ty) * SCALE - box[1])
    print(f"wrote the logo and its layers {size}")
    print(f"ribbon_root = Vector2({root[0] / size[0]:.4f}, {root[1] / size[1]:.4f})  letters_edge_range_px = {EDGE_RANGE}")
    icon = make_icon()
    icon.save(os.path.join(BRANDING, "icon_1024.png"))
    icon.resize((256, 256), Image.LANCZOS).save(os.path.join(BRANDING, "icon.png"))
    icon.save(os.path.join(BRANDING, "icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("wrote icon_1024.png, icon.png, icon.ico")


def write_options():
    os.makedirs(OUT, exist_ok=True)
    for name in ("crest_above", "crest_behind", "split"):
        for style in STYLES:
            img = build(name, style)["logo"]
            img.crop(img.getbbox()).save(os.path.join(OUT, f"{name}_{style}.png"))
            print("wrote", name, style)


if __name__ == "__main__":
    write_options() if "options" in sys.argv[1:] else write_game_files()
