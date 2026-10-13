"""Realistic metal finishes for the Rotsworn logo (card #47).

steel_blade: a polished dagger blade with a diamond cross-section: two flat facets lit
differently, a bright ridge down the middle, honed edges, a fuller (groove), reflections that
streak along the blade and fine brushing marks, instead of a bevelled lump.

chiselled_gold: cast gold letters with flat chamfered edges like engraved metal: the face reflects
a soft horizon (dark below, bright above, wavering), the chamfers catch the light by the way they
face, the rims are rubbed bright, and the surface is smooth with only a little grain.
"""
import math

import cv2
import numpy as np

STEEL = [(0.0, (16, 19, 23)), (0.25, (52, 58, 66)), (0.5, (110, 118, 127)), (0.75, (178, 185, 193)),
         (0.9, (222, 227, 232)), (1.0, (252, 253, 255))]
LIGHT = np.array([-0.5, -0.7, 0.55], np.float32) / np.linalg.norm([-0.5, -0.7, 0.55])
HALF = (LIGHT + np.array([0, 0, 1], np.float32)) / np.linalg.norm(LIGHT + np.array([0, 0, 1], np.float32))


def ramp(stops, v):
    v = np.clip(v, 0.0, 1.0)
    xs = [s[0] for s in stops]
    return np.stack([np.interp(v, xs, [s[1][c] / 255.0 for s in stops]) for c in range(3)], axis=-1).astype(np.float32)


def inside_distance(mask):
    # The exact distance: the 5x5 approximation leaves ripples on smooth curves once it is lit.
    return cv2.distanceTransform((mask > 0.5).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE).astype(np.float32)


def blur(a, px):
    k = int(px * 3) | 1
    return cv2.GaussianBlur(a, (k, k), px) if px > 0 else a


def steel_blade(mask, cross, angle_deg, guard_at, tip_at, rng, px):
    """A blade turned by angle_deg (SVG rotate) about `cross` (pixels); guard_at and tip_at are
    distances from `cross` along the blade towards the tip (pixels)."""
    h, w = mask.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    th = math.radians(angle_deg)
    dx, dy = -math.sin(th), math.cos(th)          # towards the tip
    nx, ny = math.cos(th), math.sin(th)           # across the blade
    rx, ry = xx - cross[0], yy - cross[1]
    along = rx * dx + ry * dy
    perp = rx * nx + ry * ny
    d = inside_distance(mask)
    local_half = np.maximum(d + np.abs(perp), 1.0)
    t = np.clip(np.abs(perp) / local_half, 0.0, 1.0)      # 0 on the ridge, 1 on the edge
    side = np.where(perp >= 0, 1.0, -1.0).astype(np.float32)
    edge = t > 0.84
    k = np.where(edge, 1.6, 0.42).astype(np.float32)        # facet slope; the honed edge is steeper
    n = np.stack([side * k * nx, side * k * ny, np.ones_like(t)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    diffuse = np.clip((n * LIGHT).sum(-1), 0.0, 1.0)
    spec = np.clip((n * HALF).sum(-1), 0.0, 1.0) ** 90
    u = (along - guard_at) / max(1.0, tip_at - guard_at)
    env = (0.5 + 0.3 * np.sin(u * math.tau * 1.1 + side * 1.2 + 0.7)
           + 0.13 * np.sin(u * math.tau * 3.3 + side * 0.5 + 2.0))
    v = 0.16 + 0.5 * diffuse + 0.45 * (env - 0.5)
    v = v + np.where(edge, 0.2, 0.0)
    v = v + 0.2 * np.exp(-(perp / (0.9 * px)) ** 2)                          # the ridge catches light
    fuller = ((along > guard_at + 14 * px) & (along < guard_at + (tip_at - guard_at) * 0.55)).astype(np.float32)
    groove = np.exp(-(perp / (0.17 * local_half + 0.5)) ** 2) * fuller
    v = v - 0.3 * groove + 0.18 * np.exp(-((perp - 0.2 * local_half) / (0.06 * local_half + 0.5)) ** 2) * fuller
    phases = rng.uniform(0, math.tau, 4)
    brushed = sum(np.sin(perp * f / px + p) for f, p in zip((0.9, 1.7, 3.1, 5.3), phases)) * 0.012
    v = v + brushed
    col = ramp(STEEL, v)
    glint = np.clip((env - 0.8) * 4.0, 0.0, 1.0) * (1 - t * 0.5)
    col = col + (spec * 0.55 + glint * 0.35)[..., None]
    # a faint cool tint in the shadows, a warmer one in the light
    col = col * np.array([0.98, 1.0, 1.04], np.float32)
    return np.clip(col, 0.0, 1.0)


def chiselled_gold(mask, tm, bevel_px, rng, px, fbm, stops):
    """Cast gold letters: flat face, flat chamfers, horizon reflection. tm: 0 at the baseline, 1 at
    the cap height."""
    shape = mask.shape
    d = inside_distance(mask)
    t = np.clip(d / max(1.0, bevel_px), 0.0, 1.0)
    height = blur(t * bevel_px, 1.1 * px)
    gy, gx = np.gradient(height)
    n = np.stack([-gx, -gy, np.ones_like(height)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    on_bevel = np.clip((1.0 - t) * 1.6, 0.0, 1.0)
    facing = np.clip(-0.78 * n[..., 1] - 0.5 * n[..., 0], -1.0, 1.0) / 0.93      # up-left facing chamfers are lit
    v_bevel = 0.5 + 0.5 * facing
    wave = (fbm(shape, 60 * px, 3, rng) - 0.5) * 0.12                               # the horizon is not ruler-straight
    h_tm = np.clip(tm + wave, 0.0, 1.0)
    v_face = np.interp(h_tm, [0.0, 0.25, 0.44, 0.52, 0.66, 0.85, 1.0], [0.4, 0.3, 0.26, 0.6, 0.86, 0.76, 0.66])
    v = v_face * (1 - on_bevel) + v_bevel * on_bevel
    v = v + (fbm(shape, 1.6 * px, 2, rng) - 0.5) * 0.05                            # fine casting grain
    rim = np.exp(-d / (1.2 * px)) * np.clip(facing, 0.0, 1.0) * 0.25                # rubbed bright edges
    v = v + rim
    spec = np.clip((n * HALF).sum(-1), 0.0, 1.0) ** 50 * on_bevel
    col = ramp(stops, v) + (spec * 0.6)[..., None]
    return np.clip(col, 0.0, 1.0)
