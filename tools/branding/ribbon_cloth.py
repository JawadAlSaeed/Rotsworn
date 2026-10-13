"""The bone-white ribbon binding the crest's weapons, painted as cloth (card #47).

Unlike the metal parts it is not a flat mask with a bevel: each strip is drawn as many small
quads that know where they are along the ribbon (s) and across it (v), so the cloth can twist
(front and back faces, narrowing edge-on), curve round the bundle (cylinder light on the wraps),
crease along its length, end in a swallowtail notch with frayed threads, and get grimier towards
the ends. Everything here is in the emblem's own units; `place` maps them to image pixels.
"""
import math

import cv2
import numpy as np

# Supersampling for smooth edges.
SS = 3
CLOTH_FRONT = [(0.0, (40, 34, 26)), (0.35, (120, 108, 88)), (0.65, (190, 178, 152)), (0.85, (226, 216, 192)), (1.0, (246, 240, 224))]
CLOTH_BACK = [(0.0, (30, 25, 18)), (0.4, (96, 84, 64)), (0.75, (160, 144, 114)), (1.0, (204, 190, 160))]
ROT_STAIN = np.array([0.30, 0.32, 0.14], np.float32)
GRIME = np.array([0.22, 0.20, 0.14], np.float32)


def catmull(points, per_segment=24):
    pts = np.array(points, np.float64)
    out = []
    for i in range(len(pts) - 1):
        p0, p1 = pts[max(0, i - 1)], pts[i]
        p2, p3 = pts[i + 1], pts[min(len(pts) - 1, i + 2)]
        for t in np.linspace(0, 1, per_segment, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return np.array(out)


class Cloth:
    """Accumulates cloth strips in a supersampled box, then hands back image-sized maps."""

    def __init__(self, shape, place, box):
        """box: (x0, y0, x1, y1) in emblem units, the only area the ribbon may cover."""
        self.shape = shape
        self.tx, self.ty, self.scale = place
        x0, y0 = (box[0] * self.scale + self.tx), (box[1] * self.scale + self.ty)
        x1, y1 = (box[2] * self.scale + self.tx), (box[3] * self.scale + self.ty)
        self.ox, self.oy = max(0, int(x0)), max(0, int(y0))
        self.bw, self.bh = min(shape[1], int(x1) + 1) - self.ox, min(shape[0], int(y1) + 1) - self.oy
        self.alpha = np.zeros((self.bh * SS, self.bw * SS), np.float32)
        self.lum = np.zeros_like(self.alpha)
        self.back = np.zeros_like(self.alpha)
        self.along = np.zeros_like(self.alpha)

    def px(self, pts):
        """Emblem units -> supersampled pixels."""
        p = np.asarray(pts, np.float64)
        return np.stack([(p[..., 0] * self.scale + self.tx - self.ox) * SS, (p[..., 1] * self.scale + self.ty - self.oy) * SS], axis=-1)

    def quad(self, corners, lum, back, along):
        poly = np.round(corners).astype(np.int32).reshape(-1, 1, 2)
        for arr, val in ((self.alpha, 1.0), (self.lum, lum), (self.back, back), (self.along, along)):
            cv2.fillPoly(arr, [poly], float(val))

    def strip(self, centre, width, shade, subs=10, notch=0.0, twist=None):
        """A strip along `centre` (emblem units, already smooth). width(s) in emblem units;
        shade(s, v, facing) -> lum; twist(s) -> facing in -1..1 (None: always face on)."""
        c = self.px(centre)
        n_pts = len(c)
        normals = []
        for i in range(n_pts):
            d = c[min(i + 1, n_pts - 1)] - c[max(i - 1, 0)]
            normals.append(np.array([-d[1], d[0]]) / (np.linalg.norm(d) + 1e-9))
        normals = np.array(normals)
        s_of = np.linspace(0.0, 1.0, n_pts)
        facing = np.array([twist(s) if twist else 1.0 for s in s_of])
        half = np.array([width(s) for s in s_of]) * self.scale * SS * 0.5 * (0.2 + 0.8 * np.abs(facing))
        vs = np.linspace(-1.0, 1.0, subs + 1)
        for i in range(n_pts - 1):
            s_mid = (s_of[i] + s_of[i + 1]) / 2
            f_mid = (facing[i] + facing[i + 1]) / 2
            for j in range(subs):
                v_mid = (vs[j] + vs[j + 1]) / 2
                if notch and s_mid > 1.0 - notch * (1.0 - abs(v_mid)):
                    continue          # the swallowtail cut at the end
                a = c[i] + normals[i] * half[i] * vs[j]
                b = c[i + 1] + normals[i + 1] * half[i + 1] * vs[j]
                cc = c[i + 1] + normals[i + 1] * half[i + 1] * vs[j + 1]
                d = c[i] + normals[i] * half[i] * vs[j + 1]
                v_seen = v_mid if f_mid >= 0 else -v_mid
                self.quad([a, b, cc, d], shade(s_mid, v_seen, f_mid), 1.0 if f_mid < 0 else 0.0, s_mid)

    def threads(self, end, direction, rng, count=5, length=(10, 20), lum=0.6):
        """Frayed threads at a tail's end."""
        e = self.px(end)
        for _ in range(count):
            ang = math.atan2(direction[1], direction[0]) + rng.normal(0, 0.18)
            ln = rng.uniform(*length) * self.scale * SS
            start = e + rng.normal(0, 5 * self.scale * SS, 2)
            stop = start + np.array([math.cos(ang), math.sin(ang)]) * ln
            for arr, val in ((self.alpha, 0.85), (self.lum, lum), (self.back, 0.0), (self.along, 1.0)):
                cv2.line(arr, tuple(np.round(start).astype(int)), tuple(np.round(stop).astype(int)), float(val),
                         max(1, int(0.9 * self.scale * SS)), cv2.LINE_8)

    def maps(self):
        """(alpha, lum, back, along) at image size, edges antialiased."""
        small = cv2.resize(self.alpha, (self.bw, self.bh), interpolation=cv2.INTER_AREA)
        out = []
        for arr in (None, self.lum, self.back, self.along):
            full = np.zeros(self.shape, np.float32)
            if arr is None:
                part = small
            else:
                part = cv2.resize(arr * self.alpha, (self.bw, self.bh), interpolation=cv2.INTER_AREA) / np.maximum(small, 1e-4)
            full[self.oy:self.oy + self.bh, self.ox:self.ox + self.bw] = part
            out.append(full)
        return out


def ramp(stops, v):
    v = np.clip(v, 0.0, 1.0)
    xs = [s[0] for s in stops]
    return np.stack([np.interp(v, xs, [s[1][c] / 255.0 for s in stops]) for c in range(3)], axis=-1).astype(np.float32)


def colour(alpha, lum, back, along, fbm, rng, px):
    """Cloth colour from the strip maps: weave, grime, rot towards the ends, darker edges."""
    shape = alpha.shape
    col = ramp(CLOTH_FRONT, lum) * (1 - back[..., None]) + ramp(CLOTH_BACK, lum) * back[..., None]
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]].astype(np.float32)
    weave = 1.0 + 0.045 * np.sin(xx * 2.4 / px) * np.sin(yy * 2.4 / px) + (fbm(shape, 1.2 * px, 2, rng) - 0.5) * 0.12
    col *= weave[..., None]
    grime = np.clip((fbm(shape, 10 * px, 4, rng) - 0.45) * 1.8, 0, 1) * 0.35
    col = col * (1 - grime[..., None]) + GRIME * grime[..., None]
    stain = np.clip((fbm(shape, 7 * px, 4, rng) - 0.75 + along * 0.55) * 2.2, 0, 1) * np.clip(along * 1.4 - 0.2, 0, 1)
    col = col * (1 - stain[..., None] * 0.7) + ROT_STAIN * stain[..., None] * 0.7
    inside = cv2.distanceTransform((alpha > 0.5).astype(np.uint8), cv2.DIST_L2, 5)
    col *= (0.7 + 0.3 * np.clip(inside / (1.6 * px), 0, 1))[..., None]
    return np.clip(col, 0, 1)


# --- the ribbon on the crest -------------------------------------------------------------------

def wraps(cloth, cross):
    """Three turns of ribbon round the crossing, like cloth round a bundle of hafts."""
    cx, cy = cross
    for k, y0 in enumerate((-42, -14, 14)):
        xs = np.linspace(-40, 40, 40)
        u = (xs + 40) / 80
        centre = np.stack([xs, cy + y0 + xs * 0.26 + 6 * (1 - (xs / 40) ** 2)], axis=-1)

        def width(s, k=k):
            return 25 * (0.7 + 0.3 * math.sin(math.pi * s))

        def shade(s, v, f):
            round_light = 0.32 + 0.68 * max(0.0, math.cos((s - 0.4) * math.pi * 0.95))
            return round_light * (0.8 + 0.2 * (1 - v * v)) - 0.04 * k

        cloth.strip(centre, width, shade, subs=8)
    # the knot on the right where the tails come out: two short, fat loops
    for pts in ([(16, cy + 22), (30, cy + 26), (44, cy + 38)], [(20, cy + 40), (34, cy + 36), (46, cy + 44)]):
        cloth.strip(catmull(pts, 10), lambda s: 24 * (0.55 + 0.45 * math.sin(math.pi * s)),
                    lambda s, v, f: (0.4 + 0.55 * math.sin(math.pi * s)) * (0.78 + 0.22 * (1 - v * v)), subs=8)


def tails(cloth, cross, rng):
    """The two tails streaming from the knot in the wind: twisting, creased, cut in a swallowtail,
    frayed."""
    cx, cy = cross
    specs = [
        ([(40, cy + 34), (84, cy + 24), (132, cy + 40), (182, cy + 26), (232, cy + 44), (282, cy + 36)], 28, 0.3, 1.3),
        ([(40, cy + 46), (78, cy + 62), (120, cy + 58), (160, cy + 80), (202, cy + 74)], 25, 1.9, 1.0),
    ]
    for pts, w, phase, turns in specs:
        centre = catmull(pts, 30)
        creases = rng.uniform(-0.8, 0.8, 3)

        def twist(s, phase=phase, turns=turns):
            return math.cos(phase + s * turns * math.pi)

        def width(s, w=w):
            return w * (1.0 - 0.18 * s)

        def shade(s, v, f, creases=creases):
            face = 0.42 + 0.58 * abs(f)
            curl = 0.84 + 0.16 * (1 - v * v)
            crease = 1.0 - sum(0.16 * math.exp(-((v - c) / 0.08) ** 2) for c in creases)
            return face * curl * crease * (1.0 - 0.18 * s)

        cloth.strip(centre, width, shade, subs=12, notch=0.07, twist=twist)
        end, before = centre[-1], centre[-6]
        cloth.threads(end, end - before, rng)


def tails_root(cross):
    """Where the tails hang from (emblem units): the sway grows from here."""
    return (42.0, cross[1] + 40.0)


# --- the ribbon tied straight across the crest (the user's sketch, 2026-10-13) ----------------

def band_across(cloth, cross):
    """One band laid straight across the crest at the crossing, gently rippled, in front of the
    daggers and the staff."""
    cx, cy = cross
    xs = np.linspace(-262, 262, 90)
    centre = np.stack([xs, cy + 5 * np.sin(xs / 262 * math.pi * 2.0 + 0.4)], axis=-1)

    def shade(s, v, f):
        ripple = 0.62 + 0.3 * math.cos(s * math.pi * 4.0 + 0.8)
        crease = 1.0 - 0.14 * math.exp(-((v - 0.35) / 0.1) ** 2) - 0.1 * math.exp(-((v + 0.4) / 0.08) ** 2)
        return ripple * crease * (0.84 + 0.16 * (1 - v * v))

    cloth.strip(centre, lambda s: 34.0, shade, subs=12)


def tails_right(cloth, cross, rng):
    """The tails flowing off the band's right end."""
    cx, cy = cross
    specs = [
        ([(256, cy - 2), (300, cy - 14), (350, cy + 4), (398, cy - 12), (448, cy + 2)], 30, 0.2, 1.2),
        ([(256, cy + 10), (294, cy + 32), (340, cy + 28), (386, cy + 50)], 26, 1.7, 0.9),
    ]
    for pts, w, phase, turns in specs:
        centre = catmull(pts, 30)
        creases = rng.uniform(-0.8, 0.8, 3)

        def twist(s, phase=phase, turns=turns):
            return math.cos(phase + s * turns * math.pi)

        def shade(s, v, f, creases=creases):
            face = 0.42 + 0.58 * abs(f)
            crease = 1.0 - sum(0.16 * math.exp(-((v - c) / 0.08) ** 2) for c in creases)
            return face * (0.84 + 0.16 * (1 - v * v)) * crease * (1.0 - 0.15 * s)

        cloth.strip(centre, lambda s, w=w: w * (1.0 - 0.15 * s), shade, subs=12, notch=0.08, twist=twist)
        cloth.threads(centre[-1], centre[-1] - centre[-6], rng)
