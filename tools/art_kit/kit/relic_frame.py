"""The Relic icon's frame, as the game draws it (scripts/relics/relic_icon.gd), for the art kit.

The game draws a Relic's picture (assets/sprites/relics/<id>.png) inside a frame whose shape says
the Relic's kind: a spearhead for attack, a heater shield for defence, a round seal for support
(DESIGN.md 8.17 "The icons", 8.25 "Icons"). The picture fills a square of PICTURE_SHARE frame radii
at PICTURE_OFFSET, big enough to cover the whole inside of every frame, so each picture is drawn to
fill its own frame's shape (`safe_mask`); the frame's edge is drawn over it. The square's side snaps
to a whole number of screen pixels per picture pixel when one is close (crisp pixels), and the picture
is blown up (nearest) to the next whole number and then filtered smooth, so its pixels show even at
any scale (and under 1x no rows are dropped). This module mirrors those numbers so `relic_icons.py` can
fit each picture to its frame (`safe_mask`), `check.py` can enforce it, and the previews can show a
picture in its frame at the sizes the game uses (`compose`).
Keep the numbers in step with relic_icon.gd (frame_points, EDGE_*, PICTURE_*, picture_rect).
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw

# The grid the Relics are drawn on (assets/relic_icons.py), in pixels. Each shipped picture is that
# drawing fitted to its frame on its own square canvas (relic_icons.py fit, CANVAS_MAX), so its side
# varies; the game scales any side to PICTURE_SHARE frame radii.
PICTURE = 24

KINDS = ("attack", "defence", "support")
# relic_icon.gd PICTURE_SHARE and PICTURE_OFFSET: the picture's square, its side in frame radii and
# its centre's offset from the frame's centre (in frame radii). The square covers nearly all of every
# frame's inside (the spearhead's thin tip and the shield's point aside).
PICTURE_SHARE = 1.68
PICTURE_OFFSET = (0.0, -0.02)
# relic_icon.gd PICTURE_SNAP_UP / PICTURE_SNAP_DOWN: the side snaps to a whole number of screen pixels
# per picture pixel when that is at most this much bigger / at least this much of the unsnapped side.
PICTURE_SNAP_UP = 1.04
PICTURE_SNAP_DOWN = 0.88
# relic_icon.gd PICTURE_PRESCALE_MAX: the most a picture is blown up (nearest) before the smooth filter.
PICTURE_PRESCALE_MAX = 8
EDGE_SHARE, EDGE_MIN, EDGE_MAX = 0.055, 1.75, 4.0
INNER_GAP_SHARE, INNER_EDGES, INNER_MIN_RADIUS = 0.22, 1.7, 13.0
# How far inside the frame's edge line a picture's pixel centres must stay, in frame radii: about
# half the edge on the list icons (46 px: an edge of 2.5 px on a radius of 20.5 px), so the edge, drawn
# over the picture, covers at most the picture's outer ink line, never the object.
SAFE_INSET = 0.07

# relic_icon.gd colours (FILL tinted by the kind's sign colour, the rarity edges, rot-touched).
FILL = (0.03, 0.025, 0.04)
FILL_TINT = 0.08
SIGN_COLORS = {"attack": (1.0, 0.47, 0.16), "defence": (0.58, 0.7, 0.84), "support": (0.48, 0.78, 0.38)}
RARITY_COLORS = {"common": (0.75, 0.75, 0.77), "rare": (0.38, 0.62, 1.0), "legendary": (1.0, 0.8, 0.3)}
ROT_COLOR = (0.78, 0.4, 0.95)
# The sizes the game shows a Relic at (map chips up to the Relic book's big page).
PREVIEW_SIDES = (26, 36, 46, 64, 92, 168)


def _bezier(a, c, b, t):
    u = 1.0 - t
    return (a[0] * u * u + c[0] * 2 * u * t + b[0] * t * t, a[1] * u * u + c[1] * 2 * u * t + b[1] * t * t)


def frame_points(kind: str) -> list[tuple[float, float]]:
    """The frame in unit size, centred on (0, 0), y down (relic_icon.gd _spearhead, _heater, _seal)."""
    if kind == "attack":
        tip, widest, barb, notch = (0.0, -1.0), (0.7, 0.22), (0.48, 0.9), (0.0, 0.6)
        side = [_bezier(tip, (0.48, -0.36), widest, i / 7) for i in range(1, 8)]
        side += [_bezier(widest, (0.7, 0.62), barb, i / 4) for i in range(1, 5)]
        return [tip] + side + [notch] + [(-x, y) for x, y in reversed(side)]
    if kind == "defence":
        top, half, steps = -0.86, 0.84, 12
        pts = [(-half, top), (half, top)]
        for i in range(1, steps + 1):
            t = i / steps
            pts.append((half * (1 - t * t), top + t * (1 - top)))
        for i in range(steps - 1, 0, -1):
            t = i / steps
            pts.append((-half * (1 - t * t), top + t * (1 - top)))
        return pts
    if kind == "support":
        return [(math.cos(-math.pi / 2 + math.tau * i / 40) * 0.92, math.sin(-math.pi / 2 + math.tau * i / 40) * 0.92)
                for i in range(40)]
    raise ValueError("kind %r is not one of %s" % (kind, ", ".join(KINDS)))


def _inside(x: float, y: float, pts) -> bool:
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def _edge_distance(x: float, y: float, pts) -> float:
    best = 9.0
    for i in range(len(pts)):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % len(pts)]
        dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(x - (ax + t * dx), y - (ay + t * dy)))
    return best


def safe_mask(kind: str, inset: float = SAFE_INSET, n: int = PICTURE) -> np.ndarray:
    """(n, n) bools: the picture's pixels whose centre sits inside the frame, at least `inset` frame
    radii from its edge line, and off the picture's 1-pixel border. A picture keeps every opaque pixel
    in here, so the frame's edge never cuts it (the spearhead narrows to its tip, the shield to its
    point, the seal is round): this is the shape each picture is fitted to."""
    pts = frame_points(kind)
    ox, oy = PICTURE_OFFSET
    m = np.zeros((n, n), dtype=bool)
    for y in range(1, n - 1):
        for x in range(1, n - 1):
            fx = ox + ((x + 0.5) / n - 0.5) * PICTURE_SHARE
            fy = oy + ((y + 0.5) / n - 0.5) * PICTURE_SHARE
            m[y, x] = _inside(fx, fy, pts) and _edge_distance(fx, fy, pts) >= inset
    return m


def picture_rect(cx: float, cy: float, radius: float, n: int = PICTURE) -> tuple[float, float, float]:
    """relic_icon.gd picture_rect at 1:1 (a 1920x1080 screen): the picture's square (left, top, side) in
    a frame of `radius` centred on (cx, cy). The side snaps to a whole multiple of the `n` picture pixels
    when one is near (PICTURE_SNAP_UP, PICTURE_SNAP_DOWN), and the corner sits on a whole pixel, so
    pixels stay crisp."""
    side = radius * PICTURE_SHARE
    scale = side / n
    up, down = math.ceil(scale), math.floor(scale)
    if up >= 1 and up / scale <= PICTURE_SNAP_UP:
        side = up * n
    elif down >= 1 and down / scale >= PICTURE_SNAP_DOWN:
        side = down * n
    x = cx + PICTURE_OFFSET[0] * radius - side * 0.5
    y = cy + PICTURE_OFFSET[1] * radius - side * 0.5
    return _round_half_away(x), _round_half_away(y), side


def _round_half_away(v: float) -> float:
    """Godot's round(): halves go away from zero (Python's round() goes to even)."""
    return math.floor(v + 0.5) if v >= 0 else -math.floor(-v + 0.5)


def prescale(scale: float) -> int:
    """relic_icon.gd picture_prescale: how many times a picture shown at `scale` screen pixels per
    picture pixel is blown up (nearest) before the smooth filter draws it; 1 under 1x."""
    return min(max(math.ceil(scale - 0.001), 1), PICTURE_PRESCALE_MAX)


def _place(picture: np.ndarray, side: int, left: float, top: float, size: float) -> np.ndarray:
    """The picture drawn into a (side, side) layer at (left, top), `size` px square, like relic_icon.gd
    _crisp: blown up (nearest) `prescale` times, then filtered bilinear. Exact at a whole number, every
    picture pixel the same size at any other scale."""
    times = prescale(size / picture.shape[0])
    picture = np.repeat(np.repeat(picture, times, axis=0), times, axis=1)
    n = picture.shape[0]
    tile = np.zeros((side, side, 4), dtype=np.uint8)
    # Filtered premultiplied, so clear pixels do not darken the edges (Godot's import fixes their
    # colour to their neighbours', which looks the same).
    pre = picture.astype(float)
    pre[..., :3] *= pre[..., 3:4] / 255.0
    for y in range(side):
        v = (y + 0.5 - top) / size
        if not 0.0 <= v < 1.0:
            continue
        for x in range(side):
            u = (x + 0.5 - left) / size
            if not 0.0 <= u < 1.0:
                continue
            fx, fy = u * n - 0.5, v * n - 0.5
            x0, y0 = math.floor(fx), math.floor(fy)
            tx, ty = fx - x0, fy - y0
            acc = np.zeros(4)
            for yy, wy in ((y0, 1 - ty), (y0 + 1, ty)):
                for xx, wx in ((x0, 1 - tx), (x0 + 1, tx)):
                    acc += pre[min(max(yy, 0), n - 1), min(max(xx, 0), n - 1)] * (wx * wy)
            if acc[3] > 0:
                rgb = np.clip(acc[:3] * 255.0 / acc[3], 0, 255).round().astype(int)
                tile[y, x] = (rgb[0], rgb[1], rgb[2], round(acc[3]))
    return tile


def _rgba(c, a: float = 1.0) -> tuple[int, int, int, int]:
    return (round(c[0] * 255), round(c[1] * 255), round(c[2] * 255), round(a * 255))


def compose(picture: np.ndarray, kind: str, rarity: str, rot: bool, side: int,
            bg: tuple[int, int, int] = (34, 31, 40)) -> Image.Image:
    """The whole icon at `side` px, drawn in relic_icon.gd's order (fill, inner line, picture, edge,
    rot drip), the picture placed and filtered like the game (picture_rect, _place). For review only."""
    ss = 4
    edge = min(max(side * EDGE_SHARE, EDGE_MIN), EDGE_MAX)
    radius = side * 0.5 - edge
    cx, cy = side * 0.5, side * 0.5
    pts = [(cx + x * radius, cy + y * radius) for x, y in frame_points(kind)]
    edge_c = ROT_COLOR if rot else RARITY_COLORS[rarity]
    sign = SIGN_COLORS[kind]
    fill = tuple(FILL[i] + (sign[i] - FILL[i]) * FILL_TINT for i in range(3))
    big = [(x * ss, y * ss) for x, y in pts]
    under = Image.new("RGBA", (side * ss, side * ss), bg + (255,))
    d = ImageDraw.Draw(under)
    d.polygon(big, fill=_rgba(fill, 0.95))
    if kind == "support" or radius >= INNER_MIN_RADIUS:
        gap = max(edge * INNER_EDGES, radius * INNER_GAP_SHARE)
        inner = [(cx * ss + (x - cx) * ss * (radius - gap) / radius, cy * ss + (y - cy) * ss * (radius - gap) / radius)
                 for x, y in pts]
        d.line(inner + [inner[0]], fill=_rgba(edge_c, 0.7 if kind == "support" else 0.45),
               width=max(1, round(max(1.0, edge * 0.45) * ss)))
    out = under.resize((side, side), Image.BOX)
    left, top, size = picture_rect(cx, cy, radius, picture.shape[0])
    out.alpha_composite(Image.fromarray(_place(picture, side, left, top, size), "RGBA"))
    over = Image.new("RGBA", (side * ss, side * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    d.line(big + [big[0]], fill=_rgba(edge_c), width=max(1, round(edge * ss)), joint="curve")
    if rot:
        # The drip hangs from the frame's point furthest low and left (relic_icon.gd _draw_drip).
        ax, ay = max(pts, key=lambda p: (p[0] - cx) * -0.6 + (p[1] - cy) * 0.8)
        drop = max(1.2, radius * 0.09)
        dy = max(2.5, radius * 0.17)
        d.polygon([((ax - drop * 0.6) * ss, (ay - drop * 0.3) * ss), ((ax + drop * 0.6) * ss, (ay - drop * 0.3) * ss),
                   ((ax + drop) * ss, (ay + dy) * ss), ((ax - drop) * ss, (ay + dy) * ss)], fill=_rgba(ROT_COLOR))
        d.ellipse([((ax - drop) * ss, (ay + dy - drop) * ss), ((ax + drop) * ss, (ay + dy + drop) * ss)],
                  fill=_rgba(ROT_COLOR))
    out.alpha_composite(over.resize((side, side), Image.BOX))
    return out
