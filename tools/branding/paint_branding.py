"""Paints the Rotsworn logo and game icon (card #47): tarnished gold, steel, wood, cloth and rot.

    python tools/branding/paint_branding.py

The picture follows the logo brief: "ROTSWORN" in heavy knightly serif (Cinzel 900) in tarnished
gold, eaten by rot (moss, thorny vines, fine cracks), over a crest of three weapons sworn
together: Alder's heavy sword and shield, Brin's twin daggers and Cass's healer's staff, bound by
one bone-white ribbon. Deep forest green, a sickly yellow-green glow, no outlines.

Each part is rendered as a flat mask by Godot (render_svg.gd), then shaded here: bevelled and lit
metal, grain and scratches, soft shadows. Writes:
  assets/branding/rotsworn_logo.png  (2700 x 1500, transparent)
  assets/branding/icon_1024.png, icon.png (256), icon.ico
Needs: pip install fonttools numpy opencv-python-headless pillow
"""
import math
import os
import subprocess

import cv2
import numpy as np
from PIL import Image

import make_branding as mb
import metal_finish
import ribbon_cloth

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = mb.REPO
LAYERS = os.path.join(HERE, "out", "layers")
GODOT = os.environ.get("GODOT", r"C:/Users/Drago/Godot/Godot_v4.7.2-stable_win64_console.exe")
SEED = 7
## Where the daggers and the staff cross and the ribbon binds them (emblem units).
CROSS = (0.0, -150.0)
## The area the ribbon may cover (emblem units).
RIBBON_BOX = (-300.0, -260.0, 500.0, 120.0)
## "wraps": wound round the crossing, tails from a knot; "band": tied straight across the crest.
RIBBON_STYLE = "wraps"
## Brin's twin daggers: turned this far each way about CROSS; hilt end, length (emblem units).
DAGGER_ANGLES = (-36.0, 36.0)
DAGGER_HILT_Y = -380.0
DAGGER_LENGTH = 900.0

# Material ramps: (position 0..1, RGB), dark to light.
GOLD = [(0.0, (24, 15, 5)), (0.28, (84, 58, 22)), (0.5, (150, 112, 48)), (0.7, (204, 168, 92)),
        (0.86, (236, 210, 148)), (1.0, (255, 246, 214))]
BRONZE = [(0.0, (18, 12, 6)), (0.35, (60, 42, 20)), (0.6, (112, 82, 40)), (0.85, (170, 138, 80)),
          (1.0, (226, 206, 156))]
STEEL = [(0.0, (20, 23, 26)), (0.35, (66, 72, 78)), (0.6, (128, 136, 142)), (0.85, (196, 202, 207)),
         (1.0, (246, 248, 250))]
WOOD = [(0.0, (14, 9, 5)), (0.5, (54, 36, 20)), (1.0, (120, 88, 56))]
LEATHER = [(0.0, (12, 7, 4)), (0.5, (44, 28, 14)), (1.0, (104, 72, 42))]
CLOTH = [(0.0, (52, 44, 32)), (0.45, (164, 148, 116)), (0.8, (222, 210, 182)), (1.0, (244, 236, 214))]
PAINT = [(0.0, (5, 12, 6)), (0.4, (14, 34, 16)), (0.7, (26, 58, 26)), (1.0, (58, 92, 42))]
MOSS = [(0.0, (10, 18, 6)), (0.5, (38, 62, 16)), (1.0, (104, 136, 40))]
GLOW = (150, 214, 46)


# --- geometry as flat masks (design units; the shield's centre is 0,0) ------------------------

def rot(angle, dx=0.0, dy=0.0, about=(0.0, 0.0)):
    return f'transform="translate({about[0]},{about[1]}) rotate({angle}) translate({dx},{dy})"'


def blade_parts(angle, length, half, hilt_y, guard, dx=0.0, pommel=22, about=(0.0, 0.0)):
    """One blade, hilt up at hilt_y, turned by `angle` about `about`; dx shifts it sideways."""
    t = rot(angle, dx, 0.0, about)
    tip = hilt_y + length
    g = hilt_y + 150
    return {
        "blade": f'<path {t} d="M{-half},{g} L{half},{g} L{half * 0.85},{tip - half * 5} L0,{tip} L{-half * 0.85},{tip - half * 5} Z" fill="#fff"/>',
        "grip": f'<rect {t} x="-14" y="{hilt_y + 36}" width="28" height="{g - hilt_y - 36}" rx="7" fill="#fff"/>',
        "wraps": "".join(f'<path {t} d="M-14,{hilt_y + 50 + i * 22} L14,{hilt_y + 61 + i * 22}" stroke="#fff" stroke-width="6" stroke-linecap="round"/>'
                         for i in range(int((g - hilt_y - 50) / 22))),
        "hilt": (f'<path {t} d="M{-guard},{g - 9} Q0,{g - 20} {guard},{g - 9} L{guard},{g + 9} Q0,{g - 2} {-guard},{g + 9} Z" fill="#fff"/>'
                 f'<path {t} d="M-24,{g - 16} L24,{g - 16} L17,{g + 22} L0,{g + 34} L-17,{g + 22} Z" fill="#fff"/>'
                 f'<circle {t} cx="{-guard}" cy="{g}" r="13" fill="#fff"/><circle {t} cx="{guard}" cy="{g}" r="13" fill="#fff"/>'
                 f'<path {t} d="M0,{hilt_y - pommel} L{pommel},{hilt_y + 8} L0,{hilt_y + 36} L{-pommel},{hilt_y + 8} Z" fill="#fff"/>'),
    }


def tree(rng):
    """A bare tree of rot, as gold inlay on the shield: a trunk from the point, branching up."""
    lines = []

    def branch(x, y, ang, ln, w, depth):
        x2, y2 = x + math.cos(ang) * ln, y + math.sin(ang) * ln
        bend = rng.normal(0, ln * 0.12)
        mx, my = (x + x2) / 2 - math.sin(ang) * bend, (y + y2) / 2 + math.cos(ang) * bend
        lines.append(f'<path d="M{x:.1f},{y:.1f} Q{mx:.1f},{my:.1f} {x2:.1f},{y2:.1f}" stroke="#fff" stroke-width="{w:.1f}" stroke-linecap="round" fill="none"/>')
        if depth == 0:
            return
        for spread in (-0.45, 0.4):
            branch(x2, y2, ang + spread + rng.normal(0, 0.15), ln * rng.uniform(0.66, 0.8), max(2.5, w * 0.7), depth - 1)

    branch(0, 300, -math.pi / 2, 130, 11, 5)
    return "".join(lines)


def emblem_parts(rng, field_only_tree=True):
    w, top, point = 250, -300, 360
    parts = {}
    # Alder is the shield. In front of it: Brin's twin daggers crossed, and Cass's staff, all
    # bound together by one ribbon where they cross.
    cross = CROSS
    dag_a = blade_parts(DAGGER_ANGLES[0], DAGGER_LENGTH, 18, DAGGER_HILT_Y, 70, pommel=20, about=cross)
    dag_b = blade_parts(DAGGER_ANGLES[1], DAGGER_LENGTH, 18, DAGGER_HILT_Y, 70, pommel=20, about=cross)
    parts["blade_a"], parts["blade_b"] = dag_a["blade"], dag_b["blade"]
    for name in ("grip", "wraps", "hilt"):
        parts[name] = dag_a[name] + dag_b[name]
    # Cass's staff: dark wood with a crescent head and a spike
    parts["staff"] = '<rect x="-12" y="-470" width="24" height="880" rx="10" fill="#fff"/>'
    parts["ferrule"] = '<path d="M-15,396 L15,396 L10,440 L0,462 L-10,440 Z" fill="#fff"/>'
    parts["staffhead"] = (
        '<path fill-rule="evenodd" d="M0,-578 A46,46 0 1 1 -0.1,-578 Z M0,-558 A26,26 0 1 0 0.1,-558 Z" fill="#fff"/>'
        '<path d="M0,-664 L13,-612 L0,-572 L-13,-612 Z" fill="#fff"/>'
        '<path d="M-20,-484 C-60,-500 -82,-536 -76,-578 C-64,-550 -44,-522 -14,-510 Z" fill="#fff"/>'
        '<path d="M20,-484 C60,-500 82,-536 76,-578 C64,-550 44,-522 14,-510 Z" fill="#fff"/>'
        '<rect x="-20" y="-496" width="40" height="26" rx="5" fill="#fff"/>')
    parts["shield"] = f'<path d="{mb.shield_path(w, top, point)}" fill="#fff"/>'
    parts["field"] = f'<path d="{mb.shield_path(w, top, point, 24)}" fill="#fff"/>'
    parts["rivets"] = "".join(f'<circle cx="{x}" cy="{y}" r="9" fill="#fff"/>' for x, y in
                              [(-200, -264), (200, -264), (-228, -40), (228, -40), (-152, 200), (152, 200), (0, 318)])
    parts["tree"] = tree(rng)
    return parts


def layer_svgs(kind, rng):
    if kind == "logo":
        W, H = 1800, 1150
        tx, ty, sc = W / 2, H / 2 + 118, 0.95
    else:
        W = H = 1024
        tx, ty, sc = W / 2, H / 2 + 115, 0.93
    place = f"translate({tx},{ty}) scale({sc})"
    head = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">'
    parts = emblem_parts(rng)
    out = {name: f'{head}<g transform="{place}">{svg}</g></svg>' for name, svg in parts.items()}
    meta = {"place": (tx, ty, sc)}
    if kind == "logo":
        size, baseline = 250, 830
        letters, _ = mb.word_paths("ROTSWORN", size, W / 2, baseline)
        out["letters"] = head + "".join(f'<path d="{d}" fill="#fff"/>' for d, _, _ in letters) + "</svg>"
        meta.update({"cap_top": baseline - size * 0.70, "baseline": baseline})
    return out, meta


def render_masks(kind, scale, rng):
    os.makedirs(LAYERS, exist_ok=True)
    svgs, meta = layer_svgs(kind, rng)
    args = [GODOT, "--headless", "--path", REPO, "-s", "tools/branding/render_svg.gd", "--", str(scale)]
    for name, svg in svgs.items():
        src = os.path.join(LAYERS, f"{kind}_{name}.svg")
        with open(src, "w", encoding="utf-8", newline="\n") as f:
            f.write(svg)
        args += [src, os.path.join(LAYERS, f"{kind}_{name}.png")]
    subprocess.run(args, check=True, capture_output=True, timeout=300)
    masks = {}
    for name in svgs:
        im = np.asarray(Image.open(os.path.join(LAYERS, f"{kind}_{name}.png")).convert("RGBA"), dtype=np.float32) / 255.0
        masks[name] = np.ascontiguousarray(im[:, :, 3])
    tx, ty, sc = meta.pop("place")
    meta = {k: v * scale for k, v in meta.items()}
    meta["place"] = (tx * scale, ty * scale, sc * scale)
    return masks, meta


# --- shading ---------------------------------------------------------------------------------

def fbm(shape, cell, octaves, rng):
    """Smooth value noise in 0..1, features about `cell` pixels wide."""
    h, w = shape
    total = np.zeros(shape, np.float32)
    amp, norm = 1.0, 0.0
    for _ in range(octaves):
        gh, gw = max(2, int(h / cell) + 2), max(2, int(w / cell) + 2)
        total += cv2.resize(rng.random((gh, gw), dtype=np.float32), (w, h), interpolation=cv2.INTER_CUBIC) * amp
        norm += amp
        amp *= 0.5
        cell /= 2.0
    return np.clip(total / norm, 0.0, 1.0)


def ramp(stops, v):
    v = np.clip(v, 0.0, 1.0)
    xs = [s[0] for s in stops]
    return np.stack([np.interp(v, xs, [s[1][c] / 255.0 for s in stops]) for c in range(3)], axis=-1).astype(np.float32)


def blur(a, px):
    if px <= 0:
        return a
    k = int(px * 3) | 1
    return cv2.GaussianBlur(a, (k, k), px)


def inside_distance(mask):
    return cv2.distanceTransform((mask > 0.5).astype(np.uint8), cv2.DIST_L2, 5).astype(np.float32)


def vertical_share(mask, top=None, bottom=None):
    """0 at the bottom of the shape (or `bottom`), 1 at its top (or `top`)."""
    ys = np.where(mask.max(axis=1) > 0.5)[0]
    if len(ys) == 0:
        return np.zeros_like(mask)
    top = ys[0] if top is None else top
    bottom = ys[-1] if bottom is None else bottom
    col = np.clip((bottom - np.arange(mask.shape[0], dtype=np.float32)) / max(1.0, bottom - top), 0, 1)
    return np.broadcast_to(col[:, None], mask.shape)


def shade(mask, stops, bevel_px, rng, px, grit=0.12, dents=0.0, shine=30.0, spec_amt=0.7,
          tilt=0.35, tiltmap=None, contrast=1.0, rounded=True):
    """A lit, bevelled surface: the bevel catches light from the top left like polished metal."""
    shape = mask.shape
    t = np.clip(inside_distance(mask) / max(1.0, bevel_px), 0.0, 1.0)
    h = (np.sin(t * math.pi / 2) if rounded else t) * bevel_px
    h = h + (fbm(shape, 2.5 * px, 3, rng) - 0.5) * grit * bevel_px
    if dents:
        h = h + (fbm(shape, 20 * px, 3, rng) - 0.5) * dents * bevel_px
    h = blur(h, 0.7 * px)
    gy, gx = np.gradient(h)
    n = np.stack([-gx, -gy, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    light = np.array([-0.5, -0.7, 0.5], np.float32)
    light /= np.linalg.norm(light)
    diffuse = np.clip((n * light).sum(-1), 0.0, 1.0)
    half = light + np.array([0, 0, 1], np.float32)
    half /= np.linalg.norm(half)
    spec = np.clip((n * half).sum(-1), 0.0, 1.0) ** shine
    sky = np.clip(0.5 - 0.75 * n[..., 1] - 0.3 * n[..., 0], 0.0, 1.0)     # faces turned up catch the sky
    tm = vertical_share(mask) if tiltmap is None else tiltmap
    v = 0.18 + tm * tilt + (sky - 0.5) * 0.7 * contrast + (diffuse - 0.55) * 0.35
    col = ramp(stops, v) + (spec * spec_amt)[..., None]
    return np.clip(col, 0, 1.4)


def scratches(shape, rng, px, count, length, angle_deg=None):
    m = np.zeros(shape, np.float32)
    for _ in range(count):
        x, y = rng.uniform(0, shape[1]), rng.uniform(0, shape[0])
        a = math.radians(angle_deg + rng.normal(0, 6) if angle_deg is not None else rng.uniform(0, 360))
        ln = rng.uniform(0.3, 1.0) * length * px
        cv2.line(m, (int(x), int(y)), (int(x + math.cos(a) * ln), int(y + math.sin(a) * ln)), float(rng.uniform(0.3, 1.0)),
                 max(1, int(0.5 * px)), cv2.LINE_AA)
    return m


def cracks(shape, rng, px, cell):
    """Hairline cracks of even width: where smooth noise crosses its middle value, measured in
    pixels (value / slope), and only in some places. Returns the line and a soft halo round it."""
    n = fbm(shape, cell * px, 4, rng)
    gy, gx = np.gradient(n)
    dist = np.abs(n - 0.5) / np.maximum(np.hypot(gx, gy), 1e-6)
    line = np.clip(1.0 - dist / (0.7 * px), 0.0, 1.0)
    line *= np.clip((fbm(shape, cell * 1.5 * px, 3, rng) - 0.5) * 6.0, 0.0, 1.0)
    return line, blur(line, 2 * px)


class Canvas:
    def __init__(self, shape):
        self.rgb = np.zeros(shape + (3,), np.float32)
        self.a = np.zeros(shape, np.float32)

    def over(self, rgb, alpha):
        alpha = np.clip(alpha, 0.0, 1.0)
        out_a = alpha + self.a * (1 - alpha)
        safe = np.maximum(out_a, 1e-6)[..., None]
        self.rgb = (np.asarray(rgb) * alpha[..., None] + self.rgb * (self.a * (1 - alpha))[..., None]) / safe
        self.a = out_a

    def shadow(self, mask, px, dx, dy, opacity):
        m = np.roll(np.roll(blur(mask, px), int(dy), axis=0), int(dx), axis=1)
        self.over(np.zeros(mask.shape + (3,), np.float32), m * opacity)

    def glow(self, mask, px, color, opacity):
        self.over(np.broadcast_to(np.array(color, np.float32) / 255.0, mask.shape + (3,)), blur(mask, px) * opacity)

    def image(self):
        rgba = np.concatenate([np.clip(self.rgb, 0, 1), self.a[..., None]], axis=-1)
        return Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA")


def tarnish(col, mask, rng, px, amount):
    """Darker, greener patches where the metal has aged."""
    patch = np.clip((fbm(mask.shape, 30 * px, 4, rng) - 0.45) * 2.5, 0, 1) * amount
    aged = col * 0.55 + np.array([0.06, 0.09, 0.03], np.float32)
    return col * (1 - patch[..., None]) + aged * patch[..., None]


# --- the pictures ----------------------------------------------------------------------------

def paint_emblem(cv, m, meta, rng, px):
    shape = cv.a.shape
    zero = np.zeros(shape + (3,), np.float32)
    cv.glow(m["shield"], 50 * px, GLOW, 0.35)
    # the shield: a bronze rim, then the painted field with a tree of rot inlaid in old gold
    shield, field = m["shield"], m["field"]
    cv.shadow(shield, 16 * px, 0, 14 * px, 0.8)
    col = shade(shield, BRONZE, 14 * px, rng, px, grit=0.1, dents=0.22, shine=26, tilt=0.3)
    col = tarnish(col * (1.0 - scratches(shape, rng, px, 80, 26) * 0.35)[..., None], shield, rng, px, 0.5)
    cv.over(col, shield)
    edge = np.clip(inside_distance(field) / (70 * px), 0.0, 1.0)
    grunge = fbm(shape, 36 * px, 5, rng)
    fine = fbm(shape, 3 * px, 2, rng)
    v = 0.12 + 0.5 * edge + (grunge - 0.5) * 0.4 + (fine - 0.5) * 0.12 + vertical_share(field) * 0.12
    col = ramp(PAINT, v)
    rot_stain = np.clip((fbm(shape, 60 * px, 3, rng) - 0.58) * 3.5, 0.0, 1.0)
    col = col * (1 - rot_stain[..., None] * 0.4) + np.array([0.30, 0.40, 0.10], np.float32) * rot_stain[..., None] * 0.4
    worn = scratches(shape, rng, px, 140, 34)
    col = col * (1 - worn[..., None] * 0.3) + np.array([0.36, 0.34, 0.26], np.float32) * worn[..., None] * 0.3
    cv.over(col, field)
    cv.over(zero, np.clip(1.0 - inside_distance(field) / (12 * px), 0.0, 1.0) * field * 0.6)
    tree = m["tree"] * field
    cv.glow(tree, 10 * px, GLOW, 0.25)
    cv.shadow(tree, 2 * px, 2 * px, 3 * px, 0.7)
    col = tarnish(shade(m["tree"], GOLD, 4 * px, rng, px, grit=0.2, shine=30, spec_amt=0.5, tilt=0.15), m["tree"], rng, px, 0.55)
    cv.over(col, tree * 0.6)
    rivets = m["rivets"]
    cv.shadow(rivets, 3 * px, 2 * px, 3 * px, 0.7)
    cv.over(tarnish(shade(rivets, BRONZE, 9 * px, rng, px, grit=0.05, shine=50), rivets, rng, px, 0.4), rivets)
    # the twin daggers in front of the shield: polished steel with a ridge, fuller and honed edges
    tx, ty, sc = meta["place"]
    cross_px = (CROSS[0] * sc + tx, CROSS[1] * sc + ty)
    guard_at, tip_at = (DAGGER_HILT_Y + 150) * sc, (DAGGER_HILT_Y + DAGGER_LENGTH) * sc
    for name, angle in (("blade_a", DAGGER_ANGLES[0]), ("blade_b", DAGGER_ANGLES[1])):
        blade = m[name]
        cv.shadow(blade, 6 * px, 4 * px, 7 * px, 0.6)
        col = metal_finish.steel_blade(blade, cross_px, angle, guard_at, tip_at, rng, px)
        col *= (1.0 - scratches(shape, rng, px, 50, 30, angle + 90) * 0.12)[..., None]
        col = tarnish(col, blade, rng, px, 0.12)
        cv.over(col, blade)
    grip = m["grip"]
    cv.over(shade(grip, LEATHER, 6 * px, rng, px, grit=0.5, shine=8, spec_amt=0.12, tilt=0.1), grip)
    wraps = m["wraps"] * grip
    cv.over(shade(m["wraps"], BRONZE, 2.5 * px, rng, px, grit=0.2, shine=20, spec_amt=0.3, tilt=0.1), wraps)
    hilt = m["hilt"]
    cv.shadow(hilt, 5 * px, 3 * px, 5 * px, 0.6)
    cv.over(tarnish(shade(hilt, GOLD, 7 * px, rng, px, grit=0.15, shine=36), hilt, rng, px, 0.45), hilt)
    # the staff in front, its foot capped in bronze
    staff = m["staff"]
    cv.shadow(staff, 8 * px, 5 * px, 9 * px, 0.6)
    grain = fbm((shape[0], max(8, shape[1] // 40)), 6 * px, 3, rng)
    grain = cv2.resize(grain, (shape[1], shape[0]), interpolation=cv2.INTER_LINEAR)
    col = shade(staff, WOOD, 8 * px, rng, px, grit=0.3, shine=8, spec_amt=0.1, tilt=0.1)
    col *= (0.75 + 0.5 * grain)[..., None]
    cv.over(col, staff)
    head = m["staffhead"]
    cv.shadow(head, 6 * px, 3 * px, 6 * px, 0.6)
    col = tarnish(shade(head, GOLD, 9 * px, rng, px, grit=0.12, shine=40), head, rng, px, 0.5)
    cv.over(col, head)
    ferrule = m["ferrule"]
    cv.over(tarnish(shade(ferrule, BRONZE, 6 * px, rng, px, grit=0.1, shine=30), ferrule, rng, px, 0.4), ferrule)

def paint_letters(cv, m, meta, rng, px):
    shape = cv.a.shape
    letters = m["letters"]
    base, top = meta["baseline"], meta["cap_top"]
    cv.shadow(letters, 14 * px, 6 * px, 12 * px, 0.85)
    cv.shadow(letters, 3 * px, 0, 3 * px, 0.75)
    tm = vertical_share(letters, top, base)
    col = metal_finish.chiselled_gold(letters, tm, 11 * px, rng, px, fbm, GOLD)
    col = tarnish(col, letters, rng, px, 0.4)
    line, halo = cracks(shape, rng, px, 120)
    col *= (1.0 - (line * 0.8 + halo * 0.25) * letters)[..., None]
    col *= (1.0 - scratches(shape, rng, px, 160, 16) * 0.15 * letters)[..., None]
    cv.over(col, letters)
    # moss creeping up from the bottoms and settling on the tops
    ys = np.arange(shape[0], dtype=np.float32)[:, None]
    band = np.clip(1.0 - (base - ys) / (46 * px), 0.0, 1.0) + np.clip(1.0 - (ys - top) / (20 * px), 0.0, 1.0) * 0.7
    patch = fbm(shape, 16 * px, 5, rng)
    moss = np.clip((patch * band - 0.4) * 4.0, 0.0, 1.0) * letters
    moss *= np.clip(fbm(shape, 2 * px, 2, rng) * 1.6, 0, 1)
    col = shade(np.clip(moss * 3, 0, 1), MOSS, 3 * px, rng, px, grit=0.9, shine=6, spec_amt=0.05, tilt=0.0)
    cv.over(col, np.clip(moss * 1.4, 0, 1))


def paint_ribbon(cv, part, meta, rng, px):
    """The cloth ribbon: part "tails" (they hang and sway) or "wraps" (round the crossing)."""
    cloth = ribbon_cloth.Cloth(cv.a.shape, meta["place"], RIBBON_BOX)
    band = RIBBON_STYLE == "band"
    if part == "tails":
        (ribbon_cloth.tails_right if band else ribbon_cloth.tails)(cloth, CROSS, rng)
    elif band:
        ribbon_cloth.band_across(cloth, CROSS)
    else:
        ribbon_cloth.wraps(cloth, CROSS)
    alpha, lum, back, along = cloth.maps()
    cv.shadow(alpha, 5 * px, 3 * px, 7 * px, 0.6)
    cv.shadow(alpha, 1.5 * px, 1 * px, 2 * px, 0.45)
    cv.over(ribbon_cloth.colour(alpha, lum, back, along, fbm, rng, px), alpha)


def paint(kind, scale):
    """Returns the layers back to front: emblem, ribbon tails, front (ribbon wraps and letters)."""
    rng = np.random.default_rng(SEED)
    masks, meta = render_masks(kind, scale, rng)
    shape = next(iter(masks.values())).shape
    back, tails, front = Canvas(shape), Canvas(shape), Canvas(shape)
    paint_emblem(back, masks, meta, rng, scale)
    paint_ribbon(tails, "tails", meta, rng, scale)
    paint_ribbon(front, "wraps", meta, rng, scale)
    if kind == "logo":
        paint_letters(front, masks, meta, rng, scale)
    root = (256.0, CROSS[1]) if RIBBON_STYLE == "band" else ribbon_cloth.tails_root(CROSS)
    tx, ty, sc = meta["place"]
    root_uv = ((root[0] * sc + tx) / shape[1], (root[1] * sc + ty) / shape[0])
    return [back.image(), tails.image(), front.image()], root_uv


def flatten(layers):
    out = layers[0].copy()
    for layer in layers[1:]:
        out.alpha_composite(layer)
    return out


def main():
    # The game now uses the minimal logo (minimal_branding.py); this painted one is kept for reference.
    branding = os.path.join(HERE, "out", "painted")
    os.makedirs(branding, exist_ok=True)
    layers, root_uv = paint("logo", 1.5)
    logo = flatten(layers)
    logo.save(os.path.join(branding, "rotsworn_logo.png"))
    # The title screen draws the logo in three layers so the ribbon's tails can sway between them.
    for name, layer in zip(("back", "tails", "front"), layers):
        layer.save(os.path.join(branding, f"rotsworn_logo_{name}.png"))
    print("wrote rotsworn_logo.png and its back, tails and front layers", logo.size)
    print(f"ribbon_root = Vector2({root_uv[0]:.4f}, {root_uv[1]:.4f})  (put in data/branding/branding.tres)")
    icon = flatten(paint("icon", 1.0)[0])
    icon.save(os.path.join(branding, "icon_1024.png"))
    icon.resize((256, 256), Image.LANCZOS).save(os.path.join(branding, "icon.png"))
    icon.save(os.path.join(branding, "icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("wrote icon_1024.png, icon.png, icon.ico")


if __name__ == "__main__":
    main()
