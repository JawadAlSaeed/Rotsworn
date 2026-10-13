"""Shapes for the Rotsworn logo (card #47): the shield outline and the lettering (Cinzel 900 as
outlines, so no font is needed). paint_branding.py builds the real logo and icon from these.

    python tools/branding/make_branding.py

writes a flat, cartoon-style sketch (tools/branding/out/) for quick layout checks only.
Needs: pip install fonttools
"""
import math
import os

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out")
FONT = os.path.join(REPO, "assets", "fonts", "Cinzel.ttf")

# Palette: old gold lettering, a rot-green field, cold steel, sickly glow.
GOLD = [(0.0, "#FFF2C2"), (0.32, "#EBC15E"), (0.62, "#B8852C"), (1.0, "#6A4413")]
RIM = [(0.0, "#F3D27A"), (0.5, "#A9792A"), (1.0, "#5E3C10")]
FIELD = [(0.0, "#3F7A2E"), (0.55, "#1F4A22"), (1.0, "#0E2412")]
STEEL = [(0.0, "#F4F7F9"), (0.45, "#B7C0C7"), (1.0, "#5F6971")]
ROT = [(0.0, "#E6FF8A"), (0.5, "#A6D93B"), (1.0, "#4E7D16")]
INK = "#120D05"


def gradient(gid, stops, x1=0, y1=0, x2=0, y2=1, units=None):
    attrs = f'id="{gid}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"'
    if units:
        attrs += f' gradientUnits="{units}"'
    inner = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return f"<linearGradient {attrs}>{inner}</linearGradient>"


def radial(gid, stops, cx=0.5, cy=0.5, r=0.5):
    inner = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="{r}">{inner}</radialGradient>'


# --- shapes ----------------------------------------------------------------------------------

def shield_path(w, top, point, inset=0.0):
    """A heater shield centred on x=0: flat-ish top at y=top, point at y=point, half width w."""
    w -= inset
    top += inset
    point -= inset * 1.6
    shoulder = top + (point - top) * 0.36
    return (f"M{-w:.1f},{top:.1f} C{-w * 0.45:.1f},{top + 26:.1f} {w * 0.45:.1f},{top + 26:.1f} {w:.1f},{top:.1f} "
            f"L{w:.1f},{shoulder:.1f} C{w:.1f},{shoulder + (point - shoulder) * 0.55:.1f} {w * 0.5:.1f},{point - 60:.1f} 0,{point:.1f} "
            f"C{-w * 0.5:.1f},{point - 60:.1f} {-w:.1f},{shoulder + (point - shoulder) * 0.55:.1f} {-w:.1f},{shoulder:.1f} Z")


def sword(angle, length=1000, blade_w=48, hilt_y=-490):
    """One sword pointing down, hilt up at hilt_y, turned by `angle` degrees about (0, 0)."""
    tip = hilt_y + length
    g = hilt_y + 150          # crossguard line
    half = blade_w / 2
    parts = [
        # blade with a long taper to the tip
        f'<path d="M{-half},{g} L{half},{g} L{half * 0.9},{tip - 120} L0,{tip} L{-half * 0.9},{tip - 120} Z" fill="url(#steel)" stroke="{INK}" stroke-width="5"/>',
        # fuller (the groove down the blade)
        f'<path d="M-4,{g + 20} L4,{g + 20} L2,{tip - 170} L-2,{tip - 170} Z" fill="#59636B" opacity="0.8"/>',
        # grip
        f'<rect x="-15" y="{hilt_y + 40}" width="30" height="{g - hilt_y - 40}" rx="8" fill="#3A2614" stroke="{INK}" stroke-width="5"/>',
    ]
    for i in range(4):
        y = hilt_y + 52 + i * 24
        parts.append(f'<path d="M-15,{y} L15,{y + 12}" stroke="#6E4C26" stroke-width="5"/>')
    parts += [
        # straight crossguard with a centre block and knobbed ends
        f'<rect x="-96" y="{g - 11}" width="192" height="22" rx="6" fill="url(#rim)" stroke="{INK}" stroke-width="5"/>',
        f'<path d="M-30,{g - 18} L30,{g - 18} L22,{g + 26} L0,{g + 40} L-22,{g + 26} Z" fill="url(#rim)" stroke="{INK}" stroke-width="5"/>',
        f'<circle cx="-100" cy="{g}" r="16" fill="url(#rim)" stroke="{INK}" stroke-width="5"/>',
        f'<circle cx="100" cy="{g}" r="16" fill="url(#rim)" stroke="{INK}" stroke-width="5"/>',
        # pommel
        f'<path d="M0,{hilt_y - 22} L24,{hilt_y + 10} L0,{hilt_y + 40} L-24,{hilt_y + 10} Z" fill="url(#rim)" stroke="{INK}" stroke-width="5"/>',
    ]
    return f'<g transform="rotate({angle})">' + "".join(parts) + "</g>"


def rot_sigil(scale=1.0):
    """A drop of rot on the shield with veins spreading from it."""
    s = scale
    veins = []
    for ang, ln, bend in [(-150, 150, 30), (-110, 175, -26), (-70, 175, 26), (-30, 150, -30),
                          (20, 120, 22), (160, 120, -22), (90, 95, 0)]:
        a = math.radians(ang)
        x2, y2 = math.cos(a) * ln * s, math.sin(a) * ln * s
        mx, my = x2 * 0.5 - math.sin(a) * bend * s, y2 * 0.5 + math.cos(a) * bend * s
        veins.append(f'<path d="M0,{-10 * s:.1f} Q{mx:.1f},{my - 10 * s:.1f} {x2:.1f},{y2 - 10 * s:.1f}" '
                     f'stroke="#9BD13A" stroke-width="{7 * s:.1f}" stroke-linecap="round" fill="none" opacity="0.55"/>')
    drop = (f'<path d="M0,{-95 * s:.1f} C{30 * s:.1f},{-40 * s:.1f} {58 * s:.1f},{-2 * s:.1f} {58 * s:.1f},{34 * s:.1f} '
            f'A{58 * s:.1f},{58 * s:.1f} 0 0 1 {-58 * s:.1f},{34 * s:.1f} C{-58 * s:.1f},{-2 * s:.1f} {-30 * s:.1f},{-40 * s:.1f} 0,{-95 * s:.1f} Z" '
            f'fill="url(#rot)" stroke="{INK}" stroke-width="{5 * s:.1f}"/>')
    shine = f'<ellipse cx="{-20 * s:.1f}" cy="{20 * s:.1f}" rx="{12 * s:.1f}" ry="{20 * s:.1f}" fill="#F6FFD0" opacity="0.6"/>'
    return f'<circle r="{120 * s:.1f}" fill="url(#sickglow)"/>' + "".join(veins) + drop + shine


def emblem(rot_scale=1.0, rot_y=10):
    """Crossed swords behind the shield, and the rot sigil on it (at rot_y). Centred on (0, 0)."""
    w, top, point = 250, -300, 360
    out = [sword(-36), sword(36)]
    out.append(f'<path d="{shield_path(w + 8, top - 8, point + 12)}" fill="{INK}"/>')
    out.append(f'<path d="{shield_path(w, top, point)}" fill="url(#rim)"/>')
    out.append(f'<path d="{shield_path(w, top, point, 26)}" fill="url(#field)" stroke="{INK}" stroke-width="5"/>')
    # rivets on the rim
    for x, y in [(-200, -262), (200, -262), (-226, -40), (226, -40), (-150, 200), (150, 200), (0, 316)]:
        out.append(f'<circle cx="{x}" cy="{y}" r="9" fill="#F3D27A" stroke="{INK}" stroke-width="4"/>')
    out.append(f'<g transform="translate(0,{rot_y})">{rot_sigil(rot_scale)}</g>')
    return "".join(out)


def defs():
    return ("<defs>" + gradient("rim", RIM) + gradient("field", FIELD) + gradient("steel", STEEL, 0, 0, 1, 0)
            + gradient("rot", ROT) +
            radial("sickglow", [(0, "#B8F04A", 0.55), (1, "#B8F04A", 0)]) +
            radial("halo", [(0, "#9BD13A", 0.35), (0.6, "#6FA82A", 0.12), (1, "#6FA82A", 0)]) + "</defs>")


# --- lettering --------------------------------------------------------------------------------

def word_paths(text, size, centre_x, baseline, tracking=0.04, weight=900):
    """The word as one SVG path per letter (Cinzel at `weight`), centred on centre_x.
    Returns ([(path, x, advance)], width)."""
    font = instantiateVariableFont(TTFont(FONT), {"wght": weight})
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    names = [cmap[ord(ch)] for ch in text]
    advances = [glyphs[n].width * scale for n in names]
    total = sum(advances) + tracking * size * (len(names) - 1)
    x = centre_x - total / 2
    paths = []
    for name, adv in zip(names, advances):
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, baseline)))
        paths.append((pen.getCommands(), x, adv))
        x += adv + tracking * size
    return paths, total


def drip(x, y, length, width):
    return (f'<path d="M{x - width / 2:.1f},{y:.1f} C{x - width / 2:.1f},{y + length * 0.5:.1f} {x - width * 0.35:.1f},{y + length * 0.7:.1f} '
            f'{x - width * 0.35:.1f},{y + length * 0.82:.1f} A{width * 0.35:.1f},{width * 0.35:.1f} 0 0 0 {x + width * 0.35:.1f},{y + length * 0.82:.1f} '
            f'C{x + width * 0.35:.1f},{y + length * 0.7:.1f} {x + width / 2:.1f},{y + length * 0.5:.1f} {x + width / 2:.1f},{y:.1f} Z" '
            f'fill="url(#rot)" stroke="{INK}" stroke-width="3"/>')


def logo_svg():
    W, H = 1800, 1000
    size, baseline = 250, 618
    letters, _ = word_paths("ROTSWORN", size, W / 2, baseline)
    cap = size * 0.70
    text_grad = gradient("gold", GOLD, 0, baseline - cap, 0, baseline, "userSpaceOnUse")
    body = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">',
            defs().replace("</defs>", text_grad + "</defs>")]
    body.append(f'<ellipse cx="{W / 2}" cy="{H / 2 + 20}" rx="560" ry="470" fill="url(#halo)"/>')
    body.append(f'<g transform="translate({W / 2},{H / 2 + 6}) scale(1.08)">{emblem(0.72, -168)}</g>')
    # drips of rot hanging from the letters (drawn first, so the letters sit on top of them)
    for i, (d, x, adv) in enumerate(letters):
        if i in (0, 2, 4, 5, 7):
            body.append(drip(x + adv * (0.3 if i % 2 else 0.68), baseline - 16, 70 + (i * 23) % 40, 24))
    # the dark outline and drop shadow, then the gold letters
    for d, _, _ in letters:
        body.append(f'<path d="{d}" transform="translate(7,10)" fill="#000" opacity="0.55"/>')
    for d, _, _ in letters:
        body.append(f'<path d="{d}" fill="{INK}" stroke="{INK}" stroke-width="16" stroke-linejoin="round"/>')
    for d, _, _ in letters:
        body.append(f'<path d="{d}" fill="url(#gold)"/>')
    body.append("</svg>")
    return "".join(body)


def icon_svg():
    S = 1024
    body = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {S} {S}" width="{S}" height="{S}">', defs(),
            f'<circle cx="{S / 2}" cy="{S / 2}" r="470" fill="url(#halo)"/>',
            f'<g transform="translate({S / 2},{S / 2 + 6}) scale(1.16)">{emblem(1.25)}</g>', "</svg>"]
    return "".join(body)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, svg in [("rotsworn_logo.svg", logo_svg()), ("rotsworn_icon.svg", icon_svg())]:
        with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(svg)
        print("wrote", name, len(svg), "bytes")


if __name__ == "__main__":
    main()
