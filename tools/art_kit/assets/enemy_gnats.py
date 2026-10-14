"""Gnat Swarm: a buzzing cloud of gnats whose shape suggests a creature (enemy sheet + portrait).

Not one body. The swarm is a few soft lobes (head, body, crest, belly, tail, a reaching front
lobe, a low wisp) plus two streams of gnats orbiting round it. Each lobe owns a fixed, seeded set
of gnats placed in its own unit space, so a pose only moves and reshapes lobes and streams and
every gnat keeps its identity: blending two pose dicts (kit.rig.blend) gives smooth in-between
frames for phase 10, and the "t" key makes the gnats buzz in place and the streams flow.

The look: evening gnats. Near-ink bodies, so the mass reads as a dark cloud on the arena's
mid-grey floor; wings lit gold by the one light at the swarm's upper-left (the swarm's accent,
#c9b458), cool grey glints on its shadow side, which also draw its edge on a near-black
backdrop. The swarm is lit as one volume (lumps lean on the normals of the ellipsoid round all
lobes), so it reads as one cloud.

Layers, back to front:
1. a small dense core (SDF blobs, smooth-unioned and lumpy) inside the lobes, re-lit as one
   volume, its edge frayed so it dissolves into gnats, then recoloured as grain: dark gnat
   bodies with mid-tone and glinting gnats (3D cells fixed to the swarm's space), a 1-pixel
   gold edge where lit with lit wings below it, a broken cool back-light on the shadow side and
   a few see-through holes;
2. gnats on the core's face (they buzz with "t") and its INK outline;
3. the dense zone: many gnats just outside the core, allowed to touch and to cover the
   outline, so the mass turns into specks gradually (dense in the middle, sparse at the edges);
4. the streams: ragged dashed trails of gnats along orbits, hidden behind the mass, over it in
   front (the idle swirl, the windup's spinning rings, the lunge's speed trails);
5. the halo: strays kept apart so each is a distinct speck, some drawn as motion streaks, plus
   the blow streaks of the hurt pose and the splash of the slam;
6. the face: a hollow with two glowing eyes in INK sockets lighting the gnats round them, and a
   dark maw framed by lighter gnats with a few lit teeth;
7. the stinger (contact): a needle of packed gnats poured from the maw, an impact star at its tip.

Sheet: sprites/enemies/gnat_swarm.png, a grid of 56x56 cells (row 0 = the six key poses, then one
row per animation clip, data/clips/gnat_swarm.tres). The clip cells (CLIPS) are blended pose dicts:
a fast buzzing idle, the ball stretching into the lunge stream, and a death that scatters the
swarm. Entry points: POSES, CLIPS, model(pose), render_pose(pose) and render_portrait().
"""
from __future__ import annotations

import math
import os
from typing import Any

import numpy as np

from kit.palette import INK, Material
from kit.rig import blend
from kit.post import cleanup
from kit.render import Camera, Frame, render
from kit.sdf import Ellipsoid, Node, SmoothUnion, rot
from kit.clips import render_clips
from kit.sheet import hstack
from kit.specs import ENEMY_FRAME, ENEMY_POSES, PORTRAIT

ID = "gnat_swarm"
S = ENEMY_FRAME[ID]

# --- Materials ---------------------------------------------------------------------------------
# Gnat bodies: near-ink darks (index 0 is INK itself), so the swarm is a clearly dark mass on the
# arena floor and walls (luma 45-50); the mid tones (#281f2e .. #53474b) are only ever grain.
MASS = Material("gnat_mass", ["#160f1a", "#1c1320", "#281f2e", "#3a2f3d", "#53474b"],
                wrap=0.5, ao=0.4, outline=INK)
GOLD = Material("gnat_gold", ["#5f5136", "#8c7a47", "#c9b458", "#ecdc98"], outline=INK)
# Wing glints in shadow: cool grey (also the back-light on the swarm's shadow side).
GLINT = Material("gnat_glint", ["#55526a", "#8e93a8", "#bcc6d2"], outline=INK)
# The hollow of the maw: near-ink.
MAW = Material("gnat_maw", ["#0f0a13", "#1c1320", "#2b1d2c"], outline=INK)
# Eyes (emissive): amber edge, yellow body, near-white hot centre. Also the impact star.
EYE = Material("gnat_eye", ["#a8701c", "#e0b23a", "#f2dc6a", "#fff4c4"], emissive=True,
               outline=INK)

LIGHT = np.array([-0.6, 0.7, 0.4]) / np.linalg.norm([-0.6, 0.7, 0.4])
# The light's direction on screen (x right, y down): an edge facing this way is a lit edge.
SCREEN_LIGHT = (-0.6, -0.8)

# --- Lobes, streams and their gnats -------------------------------------------------------------
LOBES = ["head", "body", "crest", "belly", "tail", "reach", "wisp"]
LOBE_N = [380, 500, 300, 280, 160, 180, 120]       # gnats per lobe at density 1
LOBE_CORE = [1.0, 1.0, 0.9, 1.0, 0.55, 0.85, 0.35]  # how solid each lobe's core is
HALO_SHARE = 0.15   # share of a lobe's gnats that fly outside it
STREAMS = ["stream_a", "stream_b"]


def _lobe_gnats(k: int, n: int) -> dict[str, np.ndarray]:
    """The fixed gnats of lobe k: unit direction, radius (<1 inside, >1 halo) and hashes."""
    rng = np.random.default_rng(9100 + k)
    d = rng.normal(size=(n, 3))
    d /= np.linalg.norm(d, axis=1, keepdims=True) + 1e-9
    u = rng.random(n)
    halo = rng.random(n) < HALO_SHARE
    rho = np.where(halo, 0.95 + rng.random(n) ** 1.7 * 0.8, u ** 0.33)
    return {"dir": d, "rho": rho, "halo": halo, "h_glint": rng.random(n),
            "h_shape": rng.random(n), "phase": rng.random((n, 3)) * math.tau,
            "freq": 0.6 + rng.random(n) * 0.8}


_CACHE: dict[tuple[int, int], dict[str, np.ndarray]] = {}


def _gnats(k: int, density: float) -> dict[str, np.ndarray]:
    n = max(1, int(round(LOBE_N[k] * density)))
    if (k, n) not in _CACHE:
        # Drawn from one long seeded list, so a denser set starts with the same gnats.
        full = _lobe_gnats(k, max(n, LOBE_N[k] * 4))
        _CACHE[(k, n)] = {a: v[:n] for a, v in full.items()}
    return _CACHE[(k, n)]


# --- Poses --------------------------------------------------------------------------------------
# Model space: x forward (toward the heroes; drawn facing left), y up, z toward the viewer. One
# unit = one pixel. A pose is all numbers, so kit.rig.blend mixes two of them:
#   <lobe>    (centre x, y, z, radii x, y, z, tilt degrees about z; + = front end up)
#   <stream>  (centre x, y, z, start radius, end radius, plane tilt about z, plane tilt about x,
#             start angle, end angle, filled share 0..1). The plane at tilt x 90 faces the
#             viewer; angle 0 = front, 90 = down, 180 = back, 270 = up.
#   sting     (length px, thickness px, degrees below the horizontal) the needle out of the
#             maw toward the target; length 0 = none
#   cores     optional per-lobe core share (default LOBE_CORE): thin a lobe into loose gnats
#   glow      0..1 the gnats catch the eyes' light: more gold, brighter glints (the windup tell)
#   core      size of the dense core inside the lobes (0 = none, 1 = as big as the lobes)
#   spread    how far halo gnats stray (1 = normal)
#   swirl     degrees the halo turns around each lobe (a spiral look)
#   drift     (x, y, z) pull on halo gnats (streaming behind, blown away, settling)
#   eye       eye glow and size: 0 squeezed shut, 1 normal slits, 2 flared
#   maw       how open the maw is (0 grimace, 0.3 shut, 1 open, 2 gaping)
#   face      (x, y) screen nudge of the face from the head's front, pixels
#   t         buzz time (phase 10 loops it; 0 for the stills): gnats buzz, streams flow
#   streak    (sx, sy, radial, share) strays drawn as motion streaks (see draw_halo)
#   fray      how much the core's edge breaks up into gnats (0 = smooth, 1 = normal)
#   scatter   share 0..1 of the dense zone flung off as lone gnats (blown apart)
#   gold_cut  model height below which nothing is lit gold (the hurt swarm keeps gold only on
#             its crest, so no second face appears under the real one); -99 = no cut
#   sparkle   extra share of strays that glint, pale on the shadow side (the hurt scatter)
#   ragged    how irregular the streams are (1 = clumps and gaps, 0 = crisp even rings)
#   blow      0..1 the long streaks of gnats blown up and right, away from a hit
#   splash    0..1 gnats splashing up at the ends of the slam's layer
#   rim       optional share of the lit edge that is solid gold (default 1)
#   tone      optional lift of the core's grain toward the mid tones (the portrait, default 0)
#   inner_gold  optional share of the gold glints kept inside the lit edge (default 1)
#   face_on   optional; below 0.5 no face is drawn (the death clip's scattered cloud, default 1)
#   density   optional share of the gnats drawn (the death clip thins out, default 1)
POSES: dict[str, dict[str, Any]] = {
    # Loose, round, hovering; the face at the upper front, a tail tapering down behind.
    "idle": {
        "head":  (4.0, 32.0, 1.0, 10.5, 10.0, 10.0, 0.0),
        "body":  (-4.5, 28.0, -1.0, 10.0, 9.0, 9.0, 0.0),
        "crest": (-11.0, 31.5, -2.0, 6.0, 5.0, 6.0, 20.0),
        "belly": (-3.0, 20.0, 0.0, 8.0, 6.5, 7.5, 0.0),
        "tail":  (-6.5, 13.0, 0.0, 5.0, 5.0, 4.5, -30.0),
        "reach": (7.0, 22.5, 2.0, 5.0, 4.0, 5.0, 0.0),
        "wisp":  (-10.5, 8.5, -1.0, 3.0, 3.0, 2.5, -40.0),
        "sting": (0.0, 0.0, 0.0),
        "stream_a": (-2.0, 24.0, 0.0, 16.0, 19.0, -15.0, 25.0, 200.0, 520.0, 1.0),
        "stream_b": (-1.0, 33.0, 0.0, 12.0, 14.0, 10.0, 20.0, 20.0, 300.0, 0.0),
        "core": 0.5, "spread": 1.0, "swirl": 25.0, "drift": (0.0, 0.0, 0.0),
        "eye": 1.0, "maw": 0.8, "face": (0.0, 0.0), "t": 0.0, "glow": 0.0,
        "streak": (0.0, 0.0, 0.0, 0.0), "fray": 1.0, "scatter": 0.0,
        "cores": (1.0, 1.0, 0.9, 1.0, 0.85, 0.45, 0.75),
        "gold_cut": -99.0, "sparkle": 0.1, "ragged": 1.0, "blow": 0.0, "splash": 0.0,
    },
    # The tell: pulled into a tight dense ball, raised, gnats orbiting close, eyes flaring.
    "windup": {
        "head":  (5.0, 33.0, 1.0, 6.5, 6.0, 6.5, 0.0),
        "body":  (-1.0, 30.0, 0.0, 8.5, 8.5, 8.0, 0.0),
        "crest": (-4.5, 34.5, -1.0, 5.5, 4.5, 5.0, 0.0),
        "belly": (0.0, 25.0, 0.0, 6.5, 5.0, 6.0, 0.0),
        "tail":  (-3.0, 22.5, 0.0, 4.0, 3.5, 4.0, 0.0),
        "reach": (5.5, 26.5, 1.5, 3.5, 3.5, 3.5, 0.0),
        "wisp":  (-1.0, 20.0, 0.0, 3.0, 2.5, 3.0, 0.0),
        "sting": (0.0, 0.0, 0.0),
        "stream_a": (-0.5, 29.5, 0.0, 12.5, 13.0, 20.0, 75.0, 0.0, 330.0, 1.0),
        "stream_b": (-0.5, 29.5, 0.0, 15.0, 15.5, -25.0, 60.0, 180.0, 470.0, 1.0),
        "core": 0.86, "spread": 0.9, "swirl": 80.0, "drift": (0.0, 0.0, 0.0),
        "eye": 2.0, "maw": 0.3, "face": (0.0, 0.0), "t": 0.0, "glow": 1.0,
        "streak": (0.0, 0.0, 2.5, 0.55), "fray": 0.6, "scatter": 0.0,
        "cores": (1.0, 1.0, 0.9, 1.0, 0.8, 0.9, 0.6),
        "gold_cut": -99.0, "sparkle": 0.1, "ragged": 0.25, "blow": 0.0, "splash": 0.0,
    },
    # Moving in: stretched into a long stream toward the heroes, face first, trailing behind.
    "lunge": {
        "head":  (10.0, 26.0, 1.0, 7.5, 6.5, 7.0, -3.0),
        "body":  (-4.0, 24.0, 0.0, 8.0, 7.0, 7.0, 0.0),
        "crest": (-11.0, 25.5, -1.0, 6.5, 5.0, 5.5, 5.0),
        "belly": (3.0, 22.5, 0.0, 7.5, 6.0, 6.5, 0.0),
        "tail":  (-17.5, 26.5, -1.0, 5.5, 4.0, 4.5, 8.0),
        "reach": (16.5, 23.5, 1.0, 5.0, 4.0, 4.0, -5.0),
        "wisp":  (-22.5, 28.0, -1.0, 3.5, 2.5, 3.0, 10.0),
        "sting": (0.0, 0.0, 0.0),
        "stream_a": (-19.0, -50.0, 0.0, 80.0, 80.0, 0.0, 90.0, 278.0, 262.0, 1.0),
        "stream_b": (-18.0, -61.0, 0.0, 80.0, 80.0, 0.0, 90.0, 278.6, 266.0, 1.0),
        "core": 0.62, "spread": 1.0, "swirl": 0.0, "drift": (-6.0, 0.5, 0.0),
        "eye": 1.2, "maw": 1.0, "face": (0.0, 0.0), "t": 0.0, "glow": 0.2,
        "streak": (3.5, 0.0, 0.0, 0.6), "fray": 1.0, "scatter": 0.1,
        "cores": (1.0, 1.0, 0.6, 1.0, 0.25, 0.85, 0.0),
        "gold_cut": -99.0, "sparkle": 0.1, "ragged": 1.0, "blow": 0.0, "splash": 0.0,
    },
    # The hit: the front tipped down at the target, a needle of gnats out of the gaping maw.
    "contact": {
        "head":  (8.0, 23.0, 1.0, 7.5, 7.0, 7.0, -12.0),
        "body":  (-1.5, 23.5, 0.0, 9.0, 8.0, 8.0, -8.0),
        "crest": (-8.5, 28.5, -1.0, 7.0, 5.0, 6.0, 0.0),
        "belly": (1.5, 16.0, 0.0, 7.0, 5.0, 6.0, -10.0),
        "tail":  (-14.5, 27.0, -1.0, 5.0, 4.0, 4.5, 0.0),
        "reach": (13.0, 18.0, 1.0, 4.5, 3.5, 3.5, -15.0),
        "wisp":  (-19.5, 29.5, -1.0, 3.5, 2.5, 3.0, 0.0),
        "sting": (11.0, 2.0, 22.0),
        "stream_a": (-16.0, -50.0, 0.0, 80.0, 80.0, 0.0, 90.0, 276.0, 266.0, 1.0),
        "stream_b": (-15.0, -62.0, 0.0, 80.0, 80.0, 0.0, 90.0, 277.0, 264.0, 1.0),
        "core": 0.68, "spread": 0.85, "swirl": 0.0, "drift": (-3.0, 0.0, 0.0),
        "eye": 2.0, "maw": 1.7, "face": (0.0, 0.0), "t": 0.0, "glow": 0.5,
        "streak": (2.5, 0.0, 0.0, 0.45), "fray": 1.0, "scatter": 0.0,
        "cores": (1.0, 1.0, 0.8, 1.0, 0.4, 0.85, 0.0),
        "gold_cut": -99.0, "sparkle": 0.1, "ragged": 1.0, "blow": 0.0, "splash": 0.0,
    },
    # Recoil: knocked back and blown apart, the core broken up, eyes squeezed shut.
    "hurt": {
        "head":  (3.0, 33.0, 1.0, 8.0, 7.0, 7.5, 25.0),
        "body":  (-3.0, 26.0, 0.0, 10.0, 9.0, 9.0, 10.0),
        "crest": (-10.0, 35.0, -1.0, 6.0, 5.0, 6.0, 20.0),
        "belly": (0.0, 16.0, 0.0, 7.0, 5.0, 7.0, -10.0),
        "tail":  (-12.0, 19.0, -1.0, 5.0, 5.0, 5.0, 0.0),
        "reach": (6.0, 20.0, 2.0, 4.0, 4.0, 4.0, -20.0),
        "wisp":  (-8.0, 8.0, -1.0, 4.0, 3.0, 4.0, 0.0),
        "sting": (0.0, 0.0, 0.0),
        "stream_a": (-4.0, 26.0, 0.0, 16.0, 23.0, 10.0, 70.0, 250.0, 160.0, 0.0),
        "stream_b": (-4.0, 18.0, 0.0, 14.0, 21.0, -10.0, 70.0, 80.0, 0.0, 0.0),
        "core": 0.45, "spread": 2.0, "swirl": -40.0, "drift": (-7.0, 2.5, 0.0),
        "eye": 0.0, "maw": 0.0, "face": (0.0, 0.0), "t": 0.0, "glow": 0.0,
        "streak": (-1.5, 0.0, -2.0, 0.5), "fray": 2.0, "scatter": 0.55,
        "cores": (0.85, 0.9, 0.0, 0.0, 0.0, 0.0, 0.0),
        "gold_cut": 34.0, "sparkle": 0.35, "ragged": 1.0, "blow": 1.0, "splash": 0.0,
    },
    # Ground wave: crashed down into a low layer spreading over the ground, face still up front.
    "slam": {
        "head":  (11.0, 12.0, 1.5, 7.0, 6.5, 7.0, 10.0),
        "body":  (0.0, 6.5, 0.0, 13.0, 5.0, 10.0, 0.0),
        "crest": (-9.0, 7.0, -1.0, 9.0, 4.0, 8.0, -5.0),
        "belly": (4.0, 3.5, 0.0, 12.0, 3.0, 9.0, 0.0),
        "tail":  (-17.0, 4.0, -1.0, 7.0, 3.0, 6.0, 0.0),
        "reach": (20.0, 4.0, 2.0, 9.0, 3.0, 7.0, 0.0),
        "wisp":  (-21.0, 3.0, -1.0, 5.0, 2.0, 5.0, 0.0),
        "sting": (0.0, 0.0, 0.0),
        "stream_a": (0.0, 2.5, 0.0, 20.0, 26.0, 0.0, 0.0, 15.0, 165.0, 1.0),
        "stream_b": (0.0, 2.5, 0.0, 22.0, 27.0, 0.0, 0.0, 195.0, 345.0, 1.0),
        "core": 0.6, "spread": 1.5, "swirl": 0.0, "drift": (0.0, 3.0, 0.0),
        "eye": 2.0, "maw": 1.0, "face": (0.0, 0.0), "t": 0.0, "glow": 0.4,
        "streak": (0.0, 1.0, -1.5, 0.35), "fray": 1.0, "scatter": 0.15,
        "cores": (1.0, 1.0, 0.9, 1.0, 0.6, 0.85, 0.4),
        "gold_cut": -99.0, "sparkle": 0.15, "ragged": 1.0, "blow": 0.0, "splash": 1.0,
    },
}


def _cores(pose: dict[str, Any]) -> tuple[float, ...]:
    return tuple(pose.get("cores", LOBE_CORE))


def lobe_frames(pose: dict[str, Any]) -> list[tuple[np.ndarray, np.ndarray, np.ndarray]]:
    """(centre, radii, rotation) for every lobe."""
    out = []
    for name in LOBES:
        v = pose[name]
        out.append((np.array(v[0:3], float), np.array(v[3:6], float), rot(0.0, 0.0, v[6])))
    return out


def model(pose: dict[str, Any]) -> Node:
    """The dense core: lumpy blobs inside the lobes."""
    core = float(pose["core"])
    blobs = []
    for k, (c, r, R) in enumerate(lobe_frames(pose)):
        blobs.append(Ellipsoid(MASS, c, np.maximum(r * core * _cores(pose)[k], 0.6), R=R,
                               group="swarm", bumps=(0.6, 0.55, 31 + k)))
    return SmoothUnion(*blobs, k=3.5)


# The swarm is lit as one volume: normals lean toward those of the ellipsoid round all its lobes,
# so lumps do not catch their own highlights and the lower swarm sits in its own shadow.
FORM_MIX = 0.6     # share of the whole-swarm form in a normal (the rest: the local surface)
LOW_DIM = 0.72     # light kept at the very bottom of the swarm


def form_box(pose: dict[str, Any]) -> tuple[np.ndarray, np.ndarray]:
    """Centre and half size of the box round every lobe: the swarm's big form."""
    lo = np.full(3, np.inf)
    hi = np.full(3, -np.inf)
    for c, r, R in lobe_frames(pose):
        e = np.sqrt(((R * r[None, :]) ** 2).sum(axis=1))
        lo = np.minimum(lo, c - e)
        hi = np.maximum(hi, c + e)
    return (lo + hi) / 2.0, np.maximum((hi - lo) / 2.0, 1.0)


def form_normals(p: np.ndarray, local: np.ndarray, pose: dict[str, Any]) -> tuple[np.ndarray, np.ndarray]:
    """Normals mixed from the local ones and the big form's, and the height share 0..1."""
    C, Rb = form_box(pose)
    nb = (p - C[None, :]) / (Rb[None, :] ** 2)
    nb /= np.linalg.norm(nb, axis=1, keepdims=True) + 1e-9
    n = (1.0 - FORM_MIX) * local + FORM_MIX * nb
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-9
    hgt = np.clip((p[:, 1] - (C[1] - Rb[1])) / (2.0 * Rb[1]), 0.0, 1.0)
    return n, hgt


def _surface_points(frame: Frame, cam: Camera, ys: np.ndarray, xs: np.ndarray) -> np.ndarray:
    vx = (xs + 0.5 - cam.W / 2.0) * cam.scale + cam.cx
    vy = (cam.H - ys - 0.5) * cam.scale + cam.cy
    vz = cam.z0 - frame.depth[ys, xs]
    return np.stack([vx, vy, vz], axis=1) @ cam.R


def relight(frame: Frame, cam: Camera, mdl: Node, pose: dict[str, Any]) -> None:
    """Re-shades the rendered core with the big-form normals (see FORM_MIX)."""
    ys, xs = np.nonzero(frame.part >= 0)
    if len(ys) == 0:
        return
    P = _surface_points(frame, cam, ys, xs)
    e = 0.3
    k = np.array([[1, -1, -1], [-1, -1, 1], [-1, 1, -1], [1, 1, 1]], dtype=float)
    ns = np.zeros_like(P)
    for row in k:
        d, _ = mdl.eval(P + row * e)
        ns += row[None, :] * d[:, None]
    ns /= np.linalg.norm(ns, axis=1, keepdims=True) + 1e-9
    n, hgt = form_normals(P, ns, pose)
    ndl = (n @ cam.R.T) @ LIGHT
    v = 0.08 + 0.92 * np.clip((ndl + 0.4) / 1.4, 0.0, 1.0)
    v = v * (LOW_DIM + (1.0 - LOW_DIM) * hgt)
    # The windup's glow: the packed gnats catch the eyes' light, brightest at the top.
    v = v + 0.16 * float(pose.get("glow", 0.0)) * (0.4 + 0.6 * hgt)
    frame.light[ys, xs] = v
    for y, x, vv in zip(ys, xs, v):
        m = frame.mats[frame.part[y, x]]
        frame.idx[y, x] = max(0, min(m.top(), int(round(m.lo + vv * (m.hi - m.lo)))))


def gnat_positions(pose: dict[str, Any], density: float = 1.0) -> dict[str, np.ndarray]:
    """World positions of every lobe gnat in the pose with pseudo-normals, classes and hashes.
    Classes: inner (inside the core), dense (just outside it), halo (strays)."""
    spread = float(pose["spread"])
    swirl = math.radians(float(pose["swirl"]))
    drift = np.array(pose["drift"], float)
    t = float(pose["t"])
    core = float(pose["core"])
    scatter = float(pose.get("scatter", 0.0))
    keys = ("p", "n", "inner", "dense", "halo", "h_glint", "h_shape", "anchor")
    cols: dict[str, list[np.ndarray]] = {k: [] for k in keys}
    for k, (c, r, R) in enumerate(lobe_frames(pose)):
        g = _gnats(k, density)
        kc = core * _cores(pose)[k]
        # The dense zone loosens with the spread too (blown apart) or tightens (packed).
        loose = np.where(g["rho"] > kc, kc + (g["rho"] - kc) * (1.0 + 0.5 * (spread - 1.0)),
                         g["rho"])
        # Scatter: that share of the dense zone breaks off into lone flying gnats (blown apart).
        flung = (g["rho"] > kc) & ~g["halo"] & ((g["freq"] - 0.6) / 0.8 < scatter)
        halo = g["halo"] | flung
        loose = np.where(flung, loose * (1.0 + 0.5 * scatter), loose)
        rho = np.where(g["halo"], 0.95 + (g["rho"] - 0.95) * spread, loose)
        d = g["dir"]
        ang = swirl * np.clip(rho - 0.6, 0.0, None)
        ca, sa = np.cos(ang), np.sin(ang)
        d = np.stack([d[:, 0] * ca - d[:, 1] * sa, d[:, 0] * sa + d[:, 1] * ca, d[:, 2]], axis=1)
        p = c[None, :] + (d * rho[:, None] * r[None, :]) @ R.T
        p = p + drift[None, :] * np.clip(rho - 0.75, 0.0, None)[:, None]
        amp = 0.3 + 0.6 * np.clip(rho - 0.7, 0.0, None)
        p = p + amp[:, None] * np.sin(t * g["freq"][:, None] * math.tau + g["phase"])
        n = (d / np.maximum(r[None, :], 1e-3)) @ R.T
        n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-9
        cols["p"].append(p)
        cols["n"].append(n)
        cols["inner"].append(~halo & (rho <= kc))
        cols["dense"].append(~halo & (rho > kc))
        cols["halo"].append(halo)
        cols["h_glint"].append(g["h_glint"])
        cols["h_shape"].append(g["h_shape"])
        cols["anchor"].append(np.repeat(c[None, :], len(p), axis=0))
    out = {k: np.concatenate(v) for k, v in cols.items()}
    out["n"], out["hgt"] = form_normals(out["p"], out["n"], pose)
    out["lift"] = 0.28 * float(pose.get("glow", 0.0))
    out["gold_ok"] = out["p"][:, 1] > float(pose.get("gold_cut", -99.0))
    return out


# --- Drawing passes -----------------------------------------------------------------------------


def _shade(n: np.ndarray, hgt: np.ndarray, cam: Camera) -> np.ndarray:
    """Light value 0..1 for gnats: the one light on their normal (mostly the swarm's big form),
    dimmer low on the swarm (it shades itself)."""
    ndl = (n @ cam.R.T) @ LIGHT
    v = 0.1 + 0.9 * np.clip((ndl + 0.5) / 1.5, 0.0, 1.0)
    return v * (LOW_DIM + (1.0 - LOW_DIM) * hgt)


def _ok(x: int, y: int, W: int, H: int) -> bool:
    """Inside the frame with the 1-pixel margin kept clear."""
    return 1 <= x < W - 1 and 1 <= y < H - 1


def _pix(cam: Camera, p: np.ndarray) -> tuple[int, int, float]:
    x, y, d = cam.project(p)
    return int(math.floor(x)), int(math.floor(y)), d


class Paint:
    """The frame parts gnats are painted with, and which colour a gnat gets from its light.
    Bodies are always dark (never gold: a lit swarm is many lit wings, not a gold coat)."""

    def __init__(self, frame: Frame, group: str) -> None:
        self.mass = frame.add_part(MASS, group)
        self.gold = frame.add_part(GOLD, group)
        self.glint = frame.add_part(GLINT, group)
        self.hot = frame.add_part(EYE, group)

    def body(self, v: float) -> tuple[int, int]:
        if v > 0.66:
            return self.mass, 2
        if v > 0.42:
            return self.mass, 1
        return self.mass, 0

    def wing(self, v: float, gold: bool = True, pale: bool = False) -> tuple[int, int]:
        if gold and v > 0.74:
            return self.gold, 2
        if gold and v > 0.55:
            return self.gold, 1
        if v > 0.46 and not pale:
            return self.mass, 4
        return self.glint, 2 if pale else 1


def _hash3(c: np.ndarray, seed: int) -> np.ndarray:
    """A stable random value 0..1 for each integer 3D cell (rows of c)."""
    h = (c[:, 0].astype(np.int64) * 374761393 + c[:, 1].astype(np.int64) * 668265263
         + c[:, 2].astype(np.int64) * 1442695041 + seed * 144665) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFF) / 65535.0


def _hash2(x: int, y: int, seed: int) -> float:
    return float(_hash3(np.array([[x, y, seed]]), seed)[0])


def _shift(mask: np.ndarray, dx: int, dy: int) -> np.ndarray:
    """mask moved by (dx, dy) pixels, empty where it came from outside."""
    H, W = mask.shape
    out = np.zeros_like(mask)
    out[max(0, dy):H + min(0, dy), max(0, dx):W + min(0, dx)] = \
        mask[max(0, -dy):H - max(0, dy), max(0, -dx):W - max(0, dx)]
    return out


def _rings(mask: np.ndarray, n: int) -> list[np.ndarray]:
    """The outer n one-pixel rings of mask (4-neighbour erosion), outermost first."""
    out = []
    cur = mask.copy()
    for _ in range(n):
        inner = cur & _shift(cur, 0, 1) & _shift(cur, 0, -1) & _shift(cur, 1, 0) & _shift(cur, -1, 0)
        out.append(cur & ~inner)
        cur = inner
    return out


def _facing(mask: np.ndarray) -> np.ndarray:
    """How much each pixel's way out of mask faces the light (1 = straight at it, -1 = away):
    the outward direction is the sum of the offsets to the empty pixels in a 5x5 window."""
    ox = np.zeros(mask.shape)
    oy = np.zeros(mask.shape)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            if dx == 0 and dy == 0:
                continue
            empty = ~_shift(mask, -dx, -dy)
            w = 1.0 / math.hypot(dx, dy)
            ox += empty * dx * w
            oy += empty * dy * w
    n = np.hypot(ox, oy) + 1e-9
    return (ox * SCREEN_LIGHT[0] + oy * SCREEN_LIGHT[1]) / n


# Share of the core's outer rings (outermost first) that drop out: (shadow side, lit side).
FRAY_DROP = [(0.50, 0.20), (0.24, 0.08), (0.08, 0.0)]


def fray_core(frame: Frame, cam: Camera, core: np.ndarray, fray: float = 1.0,
              seed: int = 17) -> np.ndarray:
    """Frays the core's edge so it dissolves into gnats instead of ending in a smooth wall: some
    pixels of the outer rings drop out. The choice comes from 3D cells fixed in the swarm's
    space, so the fraying moves with the swarm. Returns the new core mask."""
    if fray <= 0:
        return core
    ys, xs = np.nonzero(core)
    P = _surface_points(frame, cam, ys, xs)
    h = np.full(core.shape, 1.0)
    h[ys, xs] = _hash3(np.floor(P / (1.5 * cam.scale ** 0.5)), seed)
    rings = _rings(core, 3)
    lit = frame.light > 0.2
    drop = np.zeros_like(core)
    for k, ring in enumerate(rings):
        p_dark, p_lit = FRAY_DROP[k]
        drop |= ring & (h < np.where(lit, p_lit, p_dark) * fray)
    # Never leave a lone core pixel sticking out after a drop.
    for _ in range(2):
        keep = core & ~drop
        nb = (_shift(keep, 0, 1).astype(int) + _shift(keep, 0, -1) + _shift(keep, 1, 0)
              + _shift(keep, -1, 0))
        drop |= keep & (nb <= 1)
    frame.part[drop] = -1
    frame.depth[drop] = np.inf
    return core & ~drop


GRAIN_CELL = 1.0     # size of a gnat cell in the core, model units at scale 1
GRAIN_GLINT = 0.12   # share of core gnats that glint (gold where lit, pale grey in shadow)


def grain_core(frame: Frame, cam: Camera, core: np.ndarray, pose: dict[str, Any],
               seed: int = 5) -> None:
    """Recolours the core as packed gnats. Each surface point falls in a 3D cell fixed to the
    swarm's space (so the grain moves with it); the cell is a dark gnat body or a mid-tone one
    (more of those in the light), and some glint. Edges: the lit edge keeps a solid 1-pixel gold
    line, under it lit wings and dark bodies alternate; the shadow edge gets a broken cool
    back-light so the shape also reads on a near-black ground."""
    ys, xs = np.nonzero(core & (frame.part >= 0))
    if len(ys) == 0:
        return
    glow = float(pose.get("glow", 0.0))
    cut = float(pose.get("gold_cut", -99.0))
    solid = float(pose.get("rim", 1.0))
    tone = float(pose.get("tone", 0.0))
    inner_gold = float(pose.get("inner_gold", 1.0))
    P = _surface_points(frame, cam, ys, xs)
    # Seen closer (the portrait) the gnats grow a little, but stay specks.
    C = np.floor(P / (GRAIN_CELL * cam.scale ** 0.5))
    h = _hash3(C, seed)
    g = _hash3(C, seed + 7)
    e = _hash3(C, seed + 13)
    gold_ok = P[:, 1] > cut
    ring = np.full(core.shape, 3)
    for k, r in enumerate(_rings(core, 3)):
        ring[r & (ring == 3)] = k
    face = _facing(core)
    mass = frame.add_part(MASS, "swarm")
    gold = frame.add_part(GOLD, "swarm")
    glint = frame.add_part(GLINT, "swarm")
    for i, (y, x) in enumerate(zip(ys, xs)):
        v = float(frame.light[y, x]) + 0.15 * glow
        hi, gi, ei = float(h[i]), float(g[i]), float(e[i])
        r, f, ok = int(ring[y, x]), float(face[y, x]), bool(gold_ok[i])
        # Base grain: dark bodies, mid-tone ones more often in the light.
        vt = v + tone
        if hi < 0.16 + 0.34 * vt:
            col = (mass, 4 if vt > 0.62 else 3)
        elif hi < 0.3 + 0.4 * vt:
            col = (mass, 2)
        else:
            col = (mass, 1 if ei < 0.45 else 0)
        if gi < (GRAIN_GLINT if v > 0.42 else GRAIN_GLINT * 0.5) + 0.12 * glow:
            if v > 0.6 and ok and (r <= 2 or ei < inner_gold):
                col = (gold, 2 if v > 0.82 else 1)
            elif v > 0.42:
                col = (mass, 4)
            else:
                col = (glint, 2 if ei > 0.8 else 1)
        if f > 0.3 and v > 0.5 and ok:
            # The lit edge: one solid gold pixel, then lit wings among dark bodies.
            if r == 0 and ei < solid:
                col = (gold, 2 if v > 0.68 else 1)
            elif r == 0:
                col = (mass, 0)
            elif r <= 2:
                if hi < 0.55 - 0.15 * r + 0.2 * glow:
                    col = (gold, 2 if (v > 0.8 and gi < 0.5) else 1)
                else:
                    col = (mass, 0 if ei < 0.5 else 1)
        elif f < -0.2 and r == 0:
            # The shadow edge: a broken cool back-light.
            if ei < 0.24:
                col = (glint, 1)
            elif ei < 0.48:
                col = (mass, 4)
            else:
                col = (mass, 0)
        frame.part[y, x], frame.idx[y, x] = col


HOLES = 0.07   # share of the core's 2nd and 3rd rings left see-through (gaps between gnats)


def cut_holes(frame: Frame, cam: Camera, core: np.ndarray, seed: int = 23) -> np.ndarray:
    """Opens a few 1-pixel see-through gaps in the dense ring, never two side by side."""
    rings = _rings(core, 3)
    cand = rings[1] | rings[2]
    ys, xs = np.nonzero(cand)
    if len(ys) == 0:
        return core
    P = _surface_points(frame, cam, ys, xs)
    h = _hash3(np.floor(P / (GRAIN_CELL * cam.scale ** 0.5)), seed)
    holes = np.zeros_like(core)
    for y, x, hv in zip(ys, xs, h):
        if hv < HOLES and not holes[y - 1:y + 2, x - 1:x + 2].any():
            holes[y, x] = True
            frame.part[y, x] = -1
            frame.fixed[y][x] = None
            frame.depth[y, x] = np.inf
    return core & ~holes


def draw_surface_gnats(frame: Frame, cam: Camera, g: dict[str, np.ndarray],
                       core_mask: np.ndarray) -> None:
    """Gnats on the face of the core (they buzz with "t"): dark specks and a few wing glints."""
    paint = Paint(frame, "swarm")
    val = _shade(g["n"], g["hgt"], cam) + g["lift"]
    for i in np.nonzero(g["inner"])[0]:
        xi, yi, dep = _pix(cam, g["p"][i])
        if not (0 <= xi < frame.W and 0 <= yi < frame.H) or not core_mask[yi, xi]:
            continue
        if dep > frame.depth[yi, xi] + 1.2:
            continue   # buried inside the core
        if g["h_glint"][i] < (0.05 if val[i] > 0.45 else 0.025):
            frame.put(xi, yi, *paint.wing(float(val[i]), bool(g["gold_ok"][i])), -1e6)


def mass_outline(frame: Frame, mask: np.ndarray) -> np.ndarray:
    """INK outline outside `mask` (4-neighbours). Returns mask + outline."""
    out = (_shift(mask, 0, 1) | _shift(mask, 0, -1) | _shift(mask, 1, 0)
           | _shift(mask, -1, 0)) & ~mask
    for y, x in zip(*np.nonzero(out)):
        frame.part[y, x] = -1
        frame.fixed[y][x] = INK
        frame.depth[y, x] = np.inf
    return mask | out


def draw_dense_gnats(frame: Frame, cam: Camera, g: dict[str, np.ndarray],
                     core: np.ndarray) -> None:
    """Gnats of the dense zone just outside the core: allowed to touch each other and to cover
    the INK outline, so they fray the mass's edge into a fuzz of dark bodies with lit wings."""
    paint = Paint(frame, "swarm")
    val = _shade(g["n"], g["hgt"], cam) + g["lift"]
    W, H = frame.W, frame.H
    for i in np.nonzero(g["dense"])[0]:
        xi, yi, dep = _pix(cam, g["p"][i])
        v = float(val[i])
        if not _ok(xi, yi, W, H) or core[yi, xi]:
            continue
        ok = bool(g["gold_ok"][i])
        part, bi = paint.body(v)
        frame.put(xi, yi, part, bi, dep)
        if g["h_shape"][i] < 0.3:
            x2 = xi + (1 if g["h_shape"][i] < 0.15 else -1)
            if _ok(x2, yi, W, H) and not core[yi, x2]:
                frame.put(x2, yi, part, bi, dep)
        glints = 0.34 if (v > 0.55 and ok) else 0.12
        if g["h_glint"][i] < glints and _ok(xi, yi - 1, W, H) and not core[yi - 1, xi]:
            frame.put(xi, yi - 1, *paint.wing(v, ok), dep - 0.1)


# --- Streams ------------------------------------------------------------------------------------
# Each stream is drawn by walking along its path in screen pixels with a seeded pattern of dashes
# (clumps of gnats) and gaps; "t" slides the pattern along, so the stream flows when animated.


def _stream_pattern(k: int, ragged: float) -> list[tuple[float, float, int]]:
    """(dash length, gap length, sideways jitter) in pixels for stream k."""
    rng = np.random.default_rng(9300 + k)
    out = []
    for _ in range(96):
        dash = 2.5 + ragged * (rng.choice([1, 2, 2, 3, 3, 4]) - 2.5)
        gap = 1.6 + ragged * (rng.choice([1, 2, 2, 3, 3, 4]) - 1.6)
        jit = int(rng.choice([0, 0, 0, 1, -1])) if ragged > 0.5 else 0
        out.append((max(1.0, dash), max(1.0, gap), jit))
    return out


def draw_streams(frame: Frame, cam: Camera, pose: dict[str, Any],
                 face_xy: tuple[float, float]) -> np.ndarray:
    """Gnats streaming round the swarm: ragged dashes (clumps of gnats) with a glinting leading
    gnat, hidden where they pass behind the mass and drawn over it in front; thinner where the
    stream starts and ends. Returns their pixels."""
    paint = Paint(frame, "stream")
    W, H = frame.W, frame.H
    used = np.zeros((H, W), bool)
    t = float(pose["t"])
    ragged = float(pose.get("ragged", 1.0))
    glow = float(pose.get("glow", 0.0))
    cut = float(pose.get("gold_cut", -99.0))
    for k, name in enumerate(STREAMS):
        v = pose[name]
        fill = float(v[9])
        if fill <= 0.02:
            continue
        c = np.array(v[0:3], float)
        R = rot(v[6], 0.0, v[5])
        n_s = 900
        s = np.linspace(0.0, fill, n_s)
        th = np.radians(v[7] + (v[8] - v[7]) * s)
        # The radius wobbles by about a pixel, so the orbit is not a drawn ellipse.
        wob = ragged * 0.9 * np.sin(s * math.tau * (2.0 + k) + 1.7 * k) * np.sin(
            s * math.tau * 5.3 + 0.4 + k)
        rad = v[3] + (v[4] - v[3]) * s + wob
        local = np.stack([rad * np.cos(th), np.zeros_like(th), rad * np.sin(th)], axis=1)
        P = c[None, :] + local @ R.T
        nrm = local @ R.T
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-9
        nrm, hgt = form_normals(P, nrm, pose)
        val = _shade(nrm, hgt, cam) + 0.28 * glow + 0.1
        V = P @ cam.R.T
        px = (V[:, 0] - cam.cx) / cam.scale + W / 2.0
        py = H - 0.5 - (V[:, 1] - cam.cy) / cam.scale
        dep = cam.z0 - V[:, 2]
        arc = np.concatenate([[0.0], np.cumsum(np.hypot(np.diff(px), np.diff(py)))])
        total = arc[-1]
        pat = _stream_pattern(k, ragged)
        # Pattern boundaries, slid along the stream by t (it flows).
        bounds = []
        a = -(t * 6.0) % sum(d + gp for d, gp, _ in pat[:8])
        j = 0
        while a < total + 1.0:
            dash, gap, jit = pat[j % len(pat)]
            bounds.append((a, a + dash, jit))
            a += dash + gap
            j += 1
        bi = 0
        for b0, b1, jit in bounds:
            # Thin the ends of the stream (it leaves and joins the mass): single gnats there.
            end = min(b0, total - b1)
            if end < 6.0 * ragged and _hash2(int(b0 * 10), k, 41) < 0.5:
                continue
            if end < 6.0 * ragged:
                b1 = b0 + 1.0
            sel = np.nonzero((arc >= b0) & (arc < b1))[0]
            if len(sel) == 0:
                continue
            cells: list[tuple[int, int, int]] = []
            for i in sel:
                xi, yi = int(math.floor(px[i])), int(math.floor(py[i]))
                tx, ty = px[min(i + 1, n_s - 1)] - px[max(i - 1, 0)], py[min(i + 1, n_s - 1)] - py[max(i - 1, 0)]
                if abs(tx) > abs(ty):
                    yi += jit
                else:
                    xi += jit
                if cells and cells[-1][:2] == (xi, yi):
                    continue
                cells.append((xi, yi, int(i)))
            bi += 1
            for n_, (xi, yi, i) in enumerate(cells):
                if not _ok(xi, yi, W, H):
                    continue
                if frame.part[yi, xi] >= 0 and dep[i] > frame.depth[yi, xi] - 0.5:
                    continue   # behind the mass
                vv = float(val[i])
                ok = P[i, 1] > cut
                back = min(len(cells) - 1 - n_, 3)
                # The leading gnat glints and the ones behind it fade: lit gold in the light,
                # cool grey in shadow, so a dash reads on the dark and the mid-grey ground.
                lit = ok and vv > 0.62
                if back == 0 and glow > 0.6 and _hash2(xi, yi, 43) < 0.6 and                         math.hypot(xi - face_xy[0], yi - face_xy[1]) < 12.0:
                    col = (paint.hot, 3)   # white-hot near the flaring eyes (the windup)
                elif lit and glow > 0.5:
                    # The windup's rings: whole dashes lit by the flaring eyes.
                    col = [(paint.gold, 3 if vv > 0.9 else 2), (paint.gold, 2),
                           (paint.gold, 1), (paint.gold, 0)][back]
                elif lit:
                    col = [(paint.gold, 2), (paint.gold, 1), (paint.mass, 4),
                           (paint.mass, 2)][back]
                else:
                    col = [(paint.glint, 2), (paint.glint, 1), (paint.mass, 4),
                           (paint.mass, 2)][back]
                frame.put(xi, yi, *col, -1e5)
                used[yi, xi] = True
    return used


def _streak_cells(x: int, y: int, vx: float, vy: float) -> list[tuple[int, int]]:
    """Pixels of a motion streak from (x, y) along (vx, vy) (its length in pixels), head first."""
    n = int(round(math.hypot(vx, vy)))
    if n < 1:
        return [(x, y)]
    out = []
    for k in range(n + 1):
        c = (int(math.floor(x + 0.5 + vx * k / n)), int(math.floor(y + 0.5 + vy * k / n)))
        if not out or out[-1] != c:
            out.append(c)
    return out


def draw_halo(frame: Frame, cam: Camera, g: dict[str, np.ndarray], blocked: np.ndarray,
              pose: dict[str, Any]) -> None:
    """Halo gnats outside the mass: each a distinct speck (no two touch side by side), a dark
    body with its wing glint above or to one side, or only the glint (the body lost in the dark).

    pose["streak"] = (sx, sy, radial, share): that share of the strays are drawn as motion
    streaks, the trail pointing along screen (sx, sy) plus `radial` pixels away from the centre
    of their lobe (radial > 0: they rush inward, < 0: they are flung out). The trail fades from
    the glinting head into the gnat's body colour. pose["sparkle"] makes more strays glint."""
    paint = Paint(frame, "fringe")
    val = _shade(g["n"], g["hgt"], cam) + g["lift"]
    sx, sy, radial, share = pose.get("streak", (0.0, 0.0, 0.0, 0.0))
    sparkle = float(pose.get("sparkle", 0.0))
    taken = blocked.copy()          # mass, outline, streams: a gnat may touch, not cover
    near = np.zeros_like(blocked)    # placed halo gnats: no other gnat may touch them sideways
    H, W = taken.shape
    idx = np.nonzero(g["halo"])[0]
    proj = {i: _pix(cam, g["p"][i]) for i in idx}
    for i in sorted(idx, key=lambda j: proj[j][2]):   # nearest first: they win the space
        xi, yi, _ = proj[i]
        hs, hg = float(g["h_shape"][i]), float(g["h_glint"][i])
        v = float(val[i])
        ok = bool(g["gold_ok"][i])
        pale = hs > 0.5 and sparkle > 0.2
        streak = hg < share
        if streak:
            ax, ay, _ = cam.project(g["anchor"][i])
            rx, ry = xi + 0.5 - ax, yi + 0.5 - ay
            rn = math.hypot(rx, ry) + 1e-6
            # Longer streaks for the gnats farther out: they are moving fastest.
            k = 0.6 + 0.8 * hs
            vx, vy = (sx + radial * rx / rn) * k, (sy + radial * ry / rn) * k
            cells = _streak_cells(xi, yi, vx, vy)
            if len(cells) < 2:
                streak = False
        if not streak:
            if hs < 0.22:
                cells = [(xi, yi), (xi + (1 if hs < 0.11 else -1), yi)]   # wings spread
            else:
                cells = [(xi, yi)]
        if not all(_ok(cx, cy, W, H) and not taken[cy, cx] for cx, cy in cells):
            continue
        if any(near[cy - 1:cy + 2, cx - 1:cx + 2].any() for cx, cy in cells[:1]) or any(
                near[cy, cx] or near[cy, cx - 1] or near[cy, cx + 1] or near[cy - 1, cx]
                or near[cy + 1, cx] for cx, cy in cells[1:]):
            continue
        if streak:
            # Head: the glint; trail: dimmer toward the end.
            for n_, (cx, cy) in enumerate(cells):
                if n_ == 0:
                    part, bi = paint.wing(v + 0.15, ok, pale)
                elif n_ == 1 and len(cells) > 2:
                    part, bi = paint.mass, 4
                else:
                    part, bi = paint.body(v)
                frame.put(cx, cy, part, bi, -1e5)
                near[cy, cx] = taken[cy, cx] = True
            continue
        glint = hg < (0.55 if v > 0.45 else 0.3) + sparkle
        gpos = None
        if glint:
            # Wing glint above, or up to one side (wings catch the light at an angle).
            for gx, gy in ((0, -1), (-1, -1), (1, -1), (0, -1))[int(hs * 4) % 4:] + ((0, -1),):
                cx, cy = xi + gx, yi + gy
                if _ok(cx, cy, W, H) and not taken[cy, cx]:
                    gpos = (cx, cy)
                    break
        lone = glint and hg < (0.18 if v > 0.45 else 0.08) + sparkle * 0.5 and len(cells) == 1
        for cx, cy in cells:
            if lone:
                frame.put(cx, cy, *paint.wing(v, ok, pale), -1e5)
            else:
                frame.put(cx, cy, *paint.body(v), -1e5)
            near[cy, cx] = taken[cy, cx] = True
        if gpos is not None and not lone:
            frame.put(gpos[0], gpos[1], *paint.wing(v, ok, pale), -1e5)
            near[gpos[1], gpos[0]] = taken[gpos[1], gpos[0]] = True


# The hurt pose's blow: long streaks of gnats flung up and to the right, away from the hit.
# (direction round the swarm in degrees, 0 = right, -90 = up; where the streak starts as a share
# of the way to the cloud's farthest gnat that way; length in pixels)
BLOW = [(-105.0, 0.75, 5), (-75.0, 0.7, 7), (-45.0, 0.65, 6), (-15.0, 0.6, 5), (20.0, 0.6, 4)]


def draw_blow(frame: Frame, mass: np.ndarray, pose: dict[str, Any]) -> None:
    """Streaks of flung gnats through the thin outer cloud: a pale leading glint flying up and
    right, then a grey and a dark tail pointing back at the swarm."""
    amt = float(pose.get("blow", 0.0))
    if amt <= 0.05:
        return
    ys, xs = np.nonzero(mass)
    if len(ys) == 0:
        return
    cx, cy = xs.mean(), ys.mean()
    cloud = frame.solid()
    paint = Paint(frame, "fringe")
    W, H = frame.W, frame.H
    dx, dy = 0.8, -0.6   # flying right and up
    for ang, start, length in BLOW:
        a = math.radians(ang)
        ux, uy = math.cos(a), math.sin(a)
        far, r = 0.0, 0.0
        while r < 60:
            x, y = int(cx + ux * r), int(cy + uy * r)
            if not (0 <= x < W and 0 <= y < H):
                break
            if cloud[y, x]:
                far = r
            r += 0.5
        n = max(2, int(round(length * amt)))
        tx, ty = cx + ux * far * start, cy + uy * far * start
        while n > 2 and not _ok(int(tx + dx * n), int(ty + dy * n), W, H):
            n -= 1
        cells = _streak_cells(int(tx + dx * n), int(ty + dy * n), -dx * n, -dy * n)
        if not all(_ok(x, y, W, H) for x, y in cells):
            continue
        for n_, (x, y) in enumerate(cells):
            col = [(paint.glint, 2), (paint.glint, 2), (paint.glint, 1), (paint.mass, 4)][min(n_, 3)]
            frame.put(x, y, *col, -1e5)


def draw_splash(frame: Frame, mass: np.ndarray, pose: dict[str, Any]) -> None:
    """The slam: gnats splashing up off both ends of the crashed layer, and its front edge on
    the ground row catching the light."""
    amt = float(pose.get("splash", 0.0))
    if amt <= 0.05:
        return
    ys, xs = np.nonzero(mass)
    if len(ys) == 0:
        return
    paint = Paint(frame, "fringe")
    W, H = frame.W, frame.H
    x0, x1 = xs.min(), xs.max()
    yb = ys.max()
    # Arcs of gnats flying up and out at each end: (side, dx out, dy up, colour).
    drops = [(-1, 1, 3, "g"), (-1, 3, 6, "p"), (-1, 0, 8, "g"), (-1, 5, 4, "d"),
             (1, 1, 4, "p"), (1, 3, 7, "g"), (1, 0, 9, "p"), (1, 4, 3, "d")]
    for side, ox, oy, kind in drops:
        bx = x0 + 4 if side < 0 else x1 - 4
        x = int(bx + side * ox * amt)
        y = int(yb - 4 - oy * amt)
        if not _ok(x, y, W, H) or mass[y, x]:
            continue
        col = {"g": (paint.gold, 2), "p": (paint.glint, 2), "d": (paint.mass, 0)}[kind]
        frame.put(x, y, *col, -1e5)
        if kind != "d" and _ok(x, y + 1, W, H) and not mass[y + 1, x]:
            frame.put(x, y + 1, paint.mass, 0, -1e5)
    # Front edge on the ground row: lit specks along the left half of the bottom edge.
    for x in range(x0, (x0 + x1) // 2):
        col = np.nonzero(mass[:, x])[0]
        if len(col) == 0:
            continue
        y = col.max() - 1
        if frame.part[y, x] >= 0 and _hash2(x, y, 51) < 0.45:
            frame.put(x, y, *((paint.gold, 1) if _hash2(x, y, 52) < 0.5 else (paint.glint, 1)),
                      -1e5)


# --- The face -----------------------------------------------------------------------------------
# Drawn in screen space (the swarm faces left, so the far eye is the left one). a/o/y/w = eye
# (amber, orange-gold, yellow, hot), m/n = maw hollow (deep, less deep), r = the lighter gnats of
# its lip, t = a lit gnat (teeth along the maw's edge). Eyes get an INK socket automatically.
# Normal eyes are slits slanting down toward each other (a scowl); flared ones are wide and
# hot; hurt ones squeeze shut (> <, amber only, so they never read as open).
FACE_SPRITE = {
    "eyes": {
        0: ["a.....a",
            ".o...o.",
            "a.....a"],
        1: ["yyy....yyyy",
            ".ywwa.awwy."],
        2: ["yy......yyy",
            "ywwy...ywwwy",
            ".ywwa.awwwy.",
            "..aa...aaa.."],
    },
    "maw": {
        # Hurt: a clenched grimace, gritted teeth (pale gnats) in a dark slot.
        0: ["mmmmmmm",
            "mgmgmgm",
            ".mmmmm."],
        # Shut tight (the windup's strain).
        1: ["mmmmm",
            ".rrr."],
        # Open: a ragged top of lit gnats (teeth) over the hollow, a mid-tone lower lip.
        2: ["rtmmmtr",
            "mtnnntm",
            "mnnnnnm",
            "rmtmtmr",
            ".r...r."],
        # Gaping: long fangs above, teeth below.
        3: ["rtmmmmtr",
            "mtnnnntm",
            "mtnnnntm",
            "mnnnnnnm",
            "mnnnnnnm",
            "rmtmmtmr",
            ".r....r."],
    },
}
# Where the maw sits under the eyes (x, y offset from the eye stamp's top-left).
MAW_AT = {0: (0, 4), 1: (3, 3), 2: (2, 3), 3: (2, 5)}


def face_anchor(pose: dict[str, Any]) -> np.ndarray:
    """Model point on the front of the head lobe where the face sits (3/4 view: a little toward
    the near side, so the whole face lands on the swarm)."""
    c, r, R = lobe_frames(pose)[0]
    return c + R @ np.array([r[0] * 0.55, r[1] * 0.05, r[2] * 0.55])


def head_front(pose: dict[str, Any], cam: Camera) -> tuple[float, float]:
    """Screen point of the face anchor plus the pose's face nudge."""
    x, y, _ = cam.project(face_anchor(pose))
    fx, fy = pose["face"]
    return x + fx, y + fy


def _maw_key(m: float) -> int:
    return 0 if m < 0.15 else (1 if m < 0.5 else (2 if m < 1.2 else 3))


def face_layout(pose: dict[str, Any], cam: Camera) -> dict[str, Any]:
    """Where the sprite face's eye and maw stamps go (screen pixels)."""
    fx, fy = head_front(pose, cam)
    lvl = float(pose["eye"])
    ek = 0 if lvl < 0.5 else (1 if lvl < 1.5 else 2)
    mk = _maw_key(float(pose["maw"]))
    eyes = FACE_SPRITE["eyes"][ek]
    x0 = int(math.floor(fx)) - len(eyes[0]) // 2
    y0 = int(math.floor(fy)) - 1
    mx, my = MAW_AT[mk]
    if ek == 0:
        mx += (len(eyes[0]) - len(FACE_SPRITE["maw"][mk][0])) // 2
    return {"fx": fx, "fy": fy, "eyes": eyes, "x0": x0, "y0": y0, "lvl": lvl,
            "maw": FACE_SPRITE["maw"][mk], "mx": x0 + mx, "my": y0 + my}


def paste_rows(frame: Frame, rows: list[str], x0: int, y0: int,
               legend: dict[str, tuple[int, int]], socket: bool = False) -> None:
    """Pastes a hand-drawn stamp on top of everything ('.' = leave). socket=True rings the
    stamp's pixels with INK (4-neighbours) so the glow pops on any part of the swarm."""
    pts = [(x0 + c, y0 + r, ch) for r, row in enumerate(rows) for c, ch in enumerate(row)
           if ch in legend]
    own = {(x, y) for x, y, _ in pts}
    if socket:
        for x, y, _ in pts:
            for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
                nx, ny = x + dx, y + dy
                if (nx, ny) not in own and 0 <= nx < frame.W and 0 <= ny < frame.H:
                    frame.part[ny, nx] = -1
                    frame.fixed[ny][nx] = INK
                    frame.depth[ny, nx] = -1e9
    for x, y, ch in pts:
        if 0 <= x < frame.W and 0 <= y < frame.H:
            part, i = legend[ch]
            frame.put(x, y, part, i, -1e9)


def face_legend(frame: Frame) -> dict[str, tuple[int, int]]:
    eye = frame.add_part(EYE, "eye")
    maw = frame.add_part(MAW, "maw")
    lip = frame.add_part(GOLD, "maw")
    rim = frame.add_part(MASS, "maw")
    return {"a": (eye, 0), "o": (eye, 1), "y": (eye, 2), "w": (eye, 3), "m": (maw, 0),
            "n": (maw, 1), "k": (maw, 2), "t": (lip, 2), "r": (rim, 4),
            "g": (frame.add_part(GLINT, "maw"), 1)}


def shade_face(frame: Frame, cx: float, cy: float, rx: float, ry: float,
               seed: int = 11) -> None:
    """The face is a hollow in the swarm: the gnats round the eyes and maw sit in its shadow
    (no gold), so the glowing eyes and the lit rim of the maw read at a glance. Where the face
    would hang over the swarm's edge, gnats gather behind it (thinning toward the oval's rim) so
    the face always sits in the swarm."""
    shadow = frame.add_part(MASS, "swarm")
    for y in range(max(1, int(cy - ry)), min(frame.H - 1, int(cy + ry) + 1)):
        for x in range(max(1, int(cx - rx)), min(frame.W - 1, int(cx + rx) + 1)):
            d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
            if d > 1.0:
                continue
            p = frame.part[y, x]
            if p < 0:
                h = _hash2(x, y, seed)
                if frame.fixed[y][x] is None and h > 0.15 + 0.85 * d * d:
                    frame.put(x, y, shadow, 0, -1e8)
                continue
            if frame.mats[p] not in (MASS, GOLD, GLINT):
                continue
            frame.part[y, x] = shadow
            frame.idx[y, x] = 0 if (d < 0.45 or _hash2(x, y, seed + 1) < 0.6) else 1


def maw_rim(frame: Frame, pts: list[tuple[int, int]], idx: int = 3) -> None:
    """A rim of lighter gnats round the maw, so the dark hollow reads against the swarm."""
    own = set(pts)
    rim = frame.add_part(MASS, "swarm")
    for x, y in pts:
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1), (-1, -1), (1, -1)):
            nx, ny = x + dx, y + dy
            if (nx, ny) in own or not (0 <= nx < frame.W and 0 <= ny < frame.H):
                continue
            p = frame.part[ny, nx]
            if p >= 0 and frame.mats[p] is MASS:
                frame.part[ny, nx] = rim
                frame.idx[ny, nx] = idx


def eye_light(frame: Frame, eyes: list[tuple[int, int]], reach: float, seed: int = 3,
              skip: tuple[int, int, int, int] | None = None) -> None:
    """The eyes light the gnats round them: a warm ring just outside the INK sockets, thinning
    into a few lit gnats further out (more with a flared glow). `skip` = (x0, y0, x1, y1), a box
    left dark (round the maw, so its lit teeth stand alone)."""
    if reach <= 0 or not eyes:
        return
    gold = frame.add_part(GOLD, "swarm")
    ex = np.array([e[0] for e in eyes], float)
    ey = np.array([e[1] for e in eyes], float)
    x0, x1 = int(ex.min() - reach - 1), int(ex.max() + reach + 2)
    y0, y1 = int(ey.min() - reach - 1), int(ey.max() + reach + 2)
    for y in range(max(0, y0), min(frame.H, y1)):
        for x in range(max(0, x0), min(frame.W, x1)):
            p = frame.part[y, x]
            if p < 0 or frame.mats[p] not in (MASS, GLINT):
                continue
            if skip is not None and skip[0] <= x <= skip[2] and skip[1] <= y <= skip[3]:
                continue
            d = float(np.min(np.hypot(ex - x, ey - y)))
            if d <= 1.0 or d > reach:
                continue
            h = _hash2(x, y, seed)
            f = (d - 1.0) / max(reach - 1.0, 1e-6)    # 0 at the socket, 1 at the reach
            if h > 0.35 + 0.65 * f:
                frame.part[y, x] = gold
                frame.idx[y, x] = 1 if (f < 0.3 and h > 0.8) else 0


def draw_face(frame: Frame, cam: Camera, pose: dict[str, Any]) -> None:
    lay = face_layout(pose, cam)
    legend = face_legend(frame)
    fx, fy, x0, y0 = lay["fx"], lay["fy"], lay["x0"], lay["y0"]
    eyes, maw = lay["eyes"], lay["maw"]
    shade_face(frame, fx + 0.5, fy + 2.5, 7.5, 6.0)
    paste_rows(frame, maw, lay["mx"], lay["my"], legend)
    pts = [(x0 + c, y0 + r) for r, row in enumerate(eyes) for c, ch in enumerate(row)
           if ch != "."]
    if lay["lvl"] >= 0.5:
        box = (lay["mx"] - 1, lay["my"], lay["mx"] + len(maw[0]), lay["my"] + len(maw))
        eye_light(frame, pts, 1.8 + 1.4 * lay["lvl"], skip=box)
    paste_rows(frame, eyes, x0, y0, legend, socket=True)


# The portrait's face, about twice the sprite's: two scowling almond eyes (the far one a little
# smaller) with hot cores in INK sockets, and a gaping maw under them, its top edge ragged with
# lit gnats hanging in like teeth.
PORTRAIT_EYE_L = [
    "yo.......",
    "ayyo.....",
    ".aywwyo..",
    "..aywwwy.",
    "...aaoyya",
]
PORTRAIT_EYE_R = [
    "........oy",
    ".....oyyya",
    "..oywwwya.",
    ".ywwwwwya.",
    "ayyoaaa...",
]
PORTRAIT_EYE_GAP = 3
PORTRAIT_MAW = [
    "..rr.rrrrr.rr..",
    ".rtmtmmtmmtmtr.",
    "rmtmmmmtmmmmtmr",
    "rmmnnnnnnnnnmmr",
    "rmnnnnkkknnnnmr",
    ".rmnnnnnnnnnmr.",
    "..rmmtmmmtmmr..",
    "...rr.rrr.rr...",
]
PORTRAIT_MAW_AT = (3, 6)   # maw offset from the eyes' top-left


def draw_portrait_face(frame: Frame, cx: float, cy: float) -> None:
    """The portrait's big face centred on (cx, cy) (the middle of the eyes)."""
    legend = face_legend(frame)
    eyes = [a + "." * PORTRAIT_EYE_GAP + b for a, b in zip(PORTRAIT_EYE_L, PORTRAIT_EYE_R)]
    x0 = int(round(cx)) - len(eyes[0]) // 2
    y0 = int(round(cy)) - len(eyes) // 2
    shade_face(frame, cx + 0.5, cy + 5.0, 12.5, 9.5)
    mx, my = x0 + PORTRAIT_MAW_AT[0], y0 + PORTRAIT_MAW_AT[1]
    paste_rows(frame, PORTRAIT_MAW, mx, my, legend)
    pts = [(x0 + c, y0 + r) for r, row in enumerate(eyes) for c, ch in enumerate(row)
           if ch != "."]
    eye_light(frame, pts, 5.0, skip=(mx - 1, my, mx + len(PORTRAIT_MAW[0]),
                                     my + len(PORTRAIT_MAW)))
    paste_rows(frame, eyes, x0, y0, legend, socket=True)


# --- The stinger --------------------------------------------------------------------------------
# The hit landing at the needle's tip: a hot star (W centre, Y arms) and pale gnats flung out (p).
IMPACT = [
    "p..Y..p",
    "...Y...",
    "..YWY..",
    "YYWWWYY",
    "..YWY..",
    "...Y...",
    "p.....p",
]


def draw_sting(frame: Frame, pose: dict[str, Any], start: tuple[int, int]) -> None:
    """The needle: gnats poured out of the maw, packed into a thin point aimed down at the
    target (an INK core with a gold top edge, 2 pixels thick tapering to a 1-pixel tip), and the
    impact star at its tip."""
    length, thick, tilt = pose["sting"]
    if length <= 0.5:
        return
    paint = Paint(frame, "sting")
    W, H = frame.W, frame.H
    x0, y0 = start
    slope = math.tan(math.radians(tilt))
    n = int(round(length))
    tip = (x0, y0)
    for i in range(n + 1):
        x = x0 - i
        y = int(math.floor(y0 + 0.5 + i * slope))
        f = i / max(n, 1)
        th = 2 if (thick >= 2 and f < 0.6) else 1
        if not _ok(x, y, W, H):
            break
        tip = (x, y)
        if th == 2 and _ok(x, y + 1, W, H):
            frame.put(x, y, paint.gold, 2 if f > 0.2 else 1, -1e9)
            frame.put(x, y + 1, paint.mass, 0, -1e9)
        else:
            frame.put(x, y, paint.gold, 2, -1e9)
            if f < 0.85 and _ok(x, y + 1, W, H):
                frame.put(x, y + 1, paint.mass, 0, -1e9)
    # Gnats pouring from the maw, converging into the needle's base.
    for dx, dy, kind in ((1, -2, "g"), (3, -3, "d"), (2, 3, "d"), (4, 3, "p"), (0, -3, "d"),
                         (5, -2, "g")):
        x, y = x0 - dx, int(math.floor(y0 + 0.5 + dx * slope)) + dy
        if _ok(x, y, W, H) and frame.part[y, x] < 0 and frame.fixed[y][x] is None:
            col = {"g": (paint.gold, 2), "p": (paint.glint, 2), "d": (paint.mass, 0)}[kind]
            frame.put(x, y, *col, -1e9)
    legend = {"W": (paint.hot, 3), "Y": (paint.hot, 2), "p": (paint.glint, 2)}
    tx, ty = tip
    rows = IMPACT
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            x, y = tx - 3 + c, ty - 3 + r
            if ch in legend and _ok(x, y, W, H):
                frame.put(x, y, *legend[ch], -1e9)


# --- Rendering ----------------------------------------------------------------------------------


def sprite_camera() -> Camera:
    return Camera(S, S, face="left")


def render_pose(pose: dict[str, Any], cam: Camera | None = None, density: float = 1.0,
                face: str = "sprite") -> np.ndarray:
    """One frame of the swarm in `pose` (RGBA, alpha cut). face: "sprite", "portrait" or ""."""
    cam = cam or sprite_camera()
    mdl = model(pose)
    frame = render(mdl, cam, ss=3, ao_dist=2.5)
    relight(frame, cam, mdl, pose)
    cleanup(frame)
    core = fray_core(frame, cam, frame.part >= 0, float(pose.get("fray", 1.0)))
    grain_core(frame, cam, core, pose)
    # A clip cell may thin the swarm (the death clip's last gnats); the keys never set it.
    g = gnat_positions(pose, density * float(pose.get("density", 1.0)))
    draw_surface_gnats(frame, cam, g, core)
    mass = mass_outline(frame, core)
    core = cut_holes(frame, cam, core)
    draw_dense_gnats(frame, cam, g, core)
    if face == "sprite":
        lay = face_layout(pose, cam)
        face_xy = (lay["fx"], lay["fy"])
    else:
        face_xy = head_front(pose, cam)
    streams = draw_streams(frame, cam, pose, face_xy)
    # Strays keep a pixel away from the streams, so the streams read as lines.
    lane = streams.copy()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        lane |= _shift(streams, dx, dy)
    draw_halo(frame, cam, g, (frame.part >= 0) | mass | lane, pose)
    draw_blow(frame, mass, pose)
    draw_splash(frame, mass, pose)
    if face == "sprite" and float(pose.get("face_on", 1.0)) >= 0.5:
        draw_face(frame, cam, pose)
        draw_sting(frame, pose, (lay["mx"], lay["my"] + len(lay["maw"]) // 2))
    elif face == "portrait":
        draw_portrait_face(frame, *face_xy)
    return frame.rgba()


# The portrait: the swarm's head seen close (scale < 1 = zoomed in), the face in the middle.
PORTRAIT_SCALE = 0.6
PORTRAIT_FACE_AT = (24.0, 20.0)   # where the middle of the eyes lands in the 48 x 48 picture


def portrait_pose() -> dict[str, Any]:
    pose = dict(POSES["idle"])
    # A round head with the body behind it to the right and below (cut by the frame there).
    pose.update({"spread": 0.7, "stream_a": POSES["idle"]["stream_a"][:9] + (0.0,),
                 "stream_b": POSES["idle"]["stream_b"][:9] + (0.0,),
                 "head": (4.0, 32.0, 1.0, 12.0, 11.5, 11.0, 0.0),
                 "body": (-8.0, 27.0, -2.0, 11.0, 10.0, 10.0, 0.0),
                 "crest": (-12.0, 35.0, -2.0, 7.0, 5.5, 7.0, 15.0),
                 "belly": (-6.0, 18.0, 0.0, 11.0, 6.0, 10.0, 0.0),
                 "tail": (-14.0, 20.0, -0.5, 6.0, 6.0, 6.0, 0.0),
                 "wisp": (-2.0, 17.0, 2.0, 5.0, 3.5, 5.0, 0.0),
                 "reach": (6.0, 24.0, 2.0, 5.0, 4.0, 5.0, 0.0),
                 "core": 0.85, "fray": 0.8, "sparkle": 0.0, "rim": 0.5, "tone": 0.2,
                 "inner_gold": 0.2,
                 "cores": (1.0, 1.0, 0.9, 1.0, 0.9, 0.6, 0.8)})
    return pose


def portrait_camera(pose: dict[str, Any]) -> Camera:
    cam = Camera(PORTRAIT, PORTRAIT, scale=PORTRAIT_SCALE, face="left")
    v = cam.view(face_anchor(pose))
    px, py = PORTRAIT_FACE_AT
    cam.cx = float(v[0] - (px - PORTRAIT / 2.0) * cam.scale)
    cam.cy = float(v[1] - (PORTRAIT - 0.5 - py) * cam.scale)
    return cam


def render_portrait() -> np.ndarray:
    pose = portrait_pose()
    return render_pose(pose, portrait_camera(pose), density=1.2, face="portrait")


def _check_margins(img: np.ndarray, name: str, bust: bool = False) -> None:
    """Warns when anything but the outline reaches the frame edge (the last row may hold the
    outline under a swarm that crashed to the ground; a portrait is a bust, cut by the bottom
    and right edges), or when a pixel is half transparent."""
    a = img[..., 3] > 0
    ink = np.array([int(INK[i:i + 2], 16) for i in (1, 3, 5)])
    bottom_ok = bust or all((img[-1, x, :3] == ink).all() for x in np.nonzero(a[-1])[0])
    if a[0].any() or a[:, 0].any() or (a[:, -1].any() and not bust) or not bottom_ok:
        print("  warning: %s touches the frame edge" % name)
    if ((img[..., 3] > 0) & (img[..., 3] < 255)).any():
        print("  warning: %s has half-transparent pixels" % name)


def anim_test() -> np.ndarray:
    """Review strip for phase 10: blended in-betweens and buzz frames (never a game file)."""
    from kit.rig import blend
    frames = [render_pose(blend(POSES["idle"], POSES["windup"], 0.5)),
              render_pose(blend(POSES["lunge"], POSES["contact"], 0.5)),
              render_pose(blend(POSES["idle"], POSES["slam"], 0.5))]
    for t in (0.33, 0.66):
        frames.append(render_pose(dict(POSES["idle"], t=t)))
    return hstack(frames)


# --- Animation clips (phase 10, plan 4.2) ----------------------------------------------------------
# In-betweens are pose dicts: kit.rig.blend of two keys (every gnat keeps its identity, so a blend
# moves the cloud smoothly) plus a few changed keys. Streams are set by hand where a blend of two
# different orbits would make a wild circle. "t" buzzes the gnats and slides the streams, so a
# held shape still crawls. Row-0 keys by index: IDLE 0, WINDUP 1, LUNGE 2, CONTACT 3, HURT 4, SLAM 5.

K_IDLE, K_WINDUP, K_LUNGE, K_CONTACT, K_HURT, K_SLAM = range(6)


def _p(base: dict[str, Any], **kw: Any) -> dict[str, Any]:
    """`base` with some keys changed (only keys the renderer knows)."""
    bad = set(kw) - set(POSES["idle"]) - {"rim", "tone", "inner_gold", "face_on", "density"}
    assert not bad, bad
    return {**base, **kw}


def _mix(a: dict[str, Any], b: dict[str, Any], u: float, /, **kw: Any) -> dict[str, Any]:
    """blend(a, b, u) with some keys changed (u, not t: "t" is the buzz-time pose key)."""
    return _p(blend(a, b, u), **kw)


def _fill(stream: tuple, share: float) -> tuple:
    """A stream with its filled share changed."""
    return tuple(stream[:9]) + (share,)


_I = POSES["idle"]
_W = POSES["windup"]
_L = POSES["lunge"]
_C = POSES["contact"]
_H = POSES["hurt"]
_S = POSES["slam"]

# Idle: the cloud buzzes in place and the orbit flows; the lobes breathe a little. Played as a
# ping-pong (k0, a, b, a) so the buzz never jumps back.
IDLE_A = _p(_I, t=0.22, swirl=30.0, belly=(-3.0, 20.5, 0.0, 8.2, 6.6, 7.6, 0.0),
            tail=(-6.0, 13.5, 0.0, 5.0, 5.0, 4.5, -26.0))
IDLE_B = _p(_I, t=0.44, swirl=35.0, belly=(-3.0, 21.0, 0.0, 8.4, 6.8, 7.8, 0.0),
            tail=(-5.5, 14.0, 0.0, 5.0, 5.0, 4.5, -22.0), wisp=(-10.0, 9.5, -1.0, 3.0, 3.0, 2.5, -35.0))

# Wind-up coil: the cloud pulls in and rises; the orbit tightens and tilts into the spinning
# rings; the eyes start to flare.
COIL_1 = _mix(_I, _W, 0.35, eye=1.0, glow=0.35, t=0.1)
COIL_2 = _mix(_I, _W, 0.72, eye=2.0, glow=0.75, t=0.2)
# The hold: the packed ball trembles and its rings spin.
SHIVER = _p(_W, t=0.5, swirl=95.0, core=0.88,
            head=(5.5, 33.5, 1.0, 6.5, 6.0, 6.5, 0.0), body=(-1.0, 30.5, 0.0, 8.5, 8.5, 8.0, 0.0))

# Lunge: the ball stretches into a stream toward the target, face first; the rings unwind into
# speed trails. The key (row 0) is the arriving frame.
LUNGE_1 = _mix(_W, _L, 0.33, stream_a=(-0.5, 28.0, 0.0, 13.0, 15.0, 12.0, 80.0, 30.0, 300.0, 0.7),
               stream_b=_fill(_L["stream_b"], 0.0), eye=2.0, glow=0.7, ragged=0.5, t=0.15)
LUNGE_2 = _mix(_W, _L, 0.7, stream_a=_fill(_L["stream_a"], 0.55), stream_b=_fill(_L["stream_b"], 0.4),
               eye=1.2, glow=0.4, ragged=0.9, t=0.3)

# Contact follow-through: the needle drives in further, then the swarm draws back off it.
FOLLOW_1 = _p(_C, sting=(13.0, 2.0, 24.0), t=0.2, head=(7.5, 22.5, 1.0, 7.5, 7.0, 7.0, -14.0))
FOLLOW_2 = _mix(_C, _I, 0.3, sting=(5.0, 1.0, 20.0), stream_a=_fill(_L["stream_a"], 0.6),
                stream_b=_fill(_L["stream_b"], 0.0), maw=1.2, eye=1.5, t=0.35)
# Recoil (mid-string): pulls back into a loose cloud.
RECOIL_1 = _mix(_C, _I, 0.55, sting=(0.0, 0.0, 0.0), stream_a=_fill(_I["stream_a"], 0.5),
                stream_b=_I["stream_b"], eye=1.0, maw=1.0, t=0.4)
# Return: drifts home, the orbit closing round it again.
RETURN_1 = _mix(_C, _I, 0.6, sting=(0.0, 0.0, 0.0), stream_a=_fill(_I["stream_a"], 0.55),
                stream_b=_I["stream_b"], eye=1.0, maw=0.9, t=0.3)
RETURN_2 = _mix(_C, _I, 0.85, sting=(0.0, 0.0, 0.0), stream_a=_fill(_I["stream_a"], 0.8),
                stream_b=_I["stream_b"], eye=1.0, maw=0.8, t=0.15)

# Slam: the crash key, gnats splashing higher off the layer, then the cloud lifting off it.
SLAM_SPLASH = _p(_S, splash=1.6, spread=1.7, scatter=0.25, t=0.3, drift=(0.0, 4.0, 0.0))
SLAM_RISE = _mix(_S, _I, 0.4, stream_a=_fill(_I["stream_a"], 0.4), stream_b=_fill(_I["stream_b"], 0.0),
                 splash=0.0, eye=1.4, t=0.45)
SLAM_WAIT = _mix(_S, _I, 0.75, stream_a=_fill(_I["stream_a"], 0.75), stream_b=_fill(_I["stream_b"], 0.0),
                 splash=0.0, eye=1.0, t=0.6)

# Hurt: the blown-apart key, then the gnats swarming back together.
HURT_1 = _mix(_H, _I, 0.5, stream_a=_fill(_I["stream_a"], 0.5), stream_b=_fill(_I["stream_b"], 0.0),
              eye=0.0, maw=0.0, blow=0.3, gold_cut=-99.0, t=0.3)
# Stagger: blown further apart and knocked back, then regathering.
STAGGER_1 = _p(_H, spread=2.6, scatter=0.75, blow=1.4, drift=(-9.0, 3.0, 0.0), core=0.38,
               head=(1.0, 34.0, 1.0, 8.0, 7.0, 7.5, 30.0), body=(-5.0, 27.0, 0.0, 10.0, 9.0, 9.0, 14.0), t=0.4)
STAGGER_2 = _mix(STAGGER_1, _I, 0.55, stream_a=_fill(_I["stream_a"], 0.4), stream_b=_fill(_I["stream_b"], 0.0),
                 eye=0.0, maw=0.0, blow=0.4, gold_cut=-99.0, t=0.6)

# Death (BURST): the swarm bursts outward, the gnats flying off as streaks; the face goes out and
# the cloud thins to a last spray (the game bursts it into sparks then).
DEATH_1 = _p(_H, spread=1.9, scatter=0.6, core=0.38, t=0.3, streak=(0.0, -0.5, -2.0, 0.35))
DEATH_2 = _p(_H, spread=2.3, scatter=0.85, core=0.26, blow=0.0, drift=(-2.0, 2.0, 0.0), t=0.6,
             cores=(0.7, 0.8, 0.0, 0.0, 0.0, 0.0, 0.0), sparkle=0.4, streak=(0.0, -0.5, -3.0, 0.55),
             density=0.8)
DEATH_3 = _p(DEATH_2, spread=2.7, scatter=1.0, core=0.1, face_on=0.0, drift=(0.0, 3.0, 0.0), t=0.9,
             swirl=-60.0, sparkle=0.5, streak=(0.0, -0.5, -3.5, 0.6), density=0.5)
DEATH_4 = _p(DEATH_3, spread=3.0, core=0.0, t=1.2, swirl=-90.0, drift=(2.0, 4.0, 0.0), sparkle=0.6,
             streak=(0.0, -0.5, -2.5, 0.4), density=0.28)

# Chasing (zone): the stretched stream, buzzing along.
CHASE_A = _p(_L, t=0.33, head=(10.0, 26.5, 1.0, 7.5, 6.5, 7.0, -3.0))
CHASE_B = _p(_L, t=0.66, head=(10.0, 25.5, 1.0, 7.5, 6.5, 7.0, -5.0), tail=(-17.5, 27.5, -1.0, 5.5, 4.0, 4.5, 12.0))

# Clip name -> cells in play order (int = a row-0 key, dict = a pose). Timing is the game's. The
# swarm floats: walk reuses the idle cells.
CLIPS: dict[str, list[Any]] = {
    "idle": [K_IDLE, IDLE_A, IDLE_B, IDLE_A],
    "windup": [COIL_1, COIL_2, K_WINDUP],
    "windup_hold": [K_WINDUP, SHIVER],
    "lunge": [LUNGE_1, LUNGE_2, K_LUNGE],
    "contact": [K_CONTACT, FOLLOW_1, FOLLOW_2],
    "recoil": [RECOIL_1, K_IDLE],
    "return": [RETURN_1, RETURN_2, K_IDLE],
    "slam": [K_SLAM, SLAM_SPLASH, SLAM_RISE],
    "slam_recover": [SLAM_WAIT, K_IDLE],
    "hurt": [K_HURT, HURT_1, K_IDLE],
    "stagger": [K_HURT, STAGGER_1, STAGGER_2, K_IDLE],
    "death": [DEATH_1, DEATH_2, DEATH_3, DEATH_4],
    "walk": [K_IDLE, IDLE_A, IDLE_B, IDLE_A],
    "chase": [K_LUNGE, CHASE_A, CHASE_B, CHASE_A],
}
# Review GIF lengths that differ from kit.clips (the fast buzz: idle_cycle_percent 35).
IDLE_CYCLE_PERCENT = 35
PREVIEW_MS = {"idle": 1800 * IDLE_CYCLE_PERCENT // 100}


def _key(pose: dict[str, Any]) -> str:
    return repr(sorted(pose.items()))


def render_many(poses: list[dict[str, Any]]) -> list[np.ndarray]:
    """render_pose for many poses, in worker processes; one by one when a pool cannot start."""
    if len(poses) < 8:
        return [render_pose(p) for p in poses]
    try:
        from concurrent.futures import ProcessPoolExecutor
        workers = max(1, min(len(poses) // 2, (os.cpu_count() or 2) - 1))
        with ProcessPoolExecutor(max_workers=workers) as ex:
            return list(ex.map(render_pose, poses))
    except Exception as e:  # noqa: BLE001 - any pool failure: fall back to one process
        print("  parallel render failed (%s); rendering one by one" % e)
        return [render_pose(p) for p in poses]


def _unique_poses(names: list[str]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    for n in names:
        for e in CLIPS[n]:
            if isinstance(e, dict):
                out.setdefault(_key(e), e)
    return out


def _key_poses() -> list[dict[str, Any]]:
    return [POSES.get(name, POSES["idle"]) for name in ENEMY_POSES]


def render_named_clips(names: list[str]) -> dict[str, list[np.ndarray]]:
    """The cells of the named clips (row-0 keys rendered too), for review strips."""
    uniq = _unique_poses(names)
    imgs = render_many(_key_poses() + list(uniq.values()))
    keys, done = imgs[:len(ENEMY_POSES)], dict(zip(uniq, imgs[len(ENEMY_POSES):]))
    return {n: [keys[e] if isinstance(e, int) else done[_key(e)] for e in CLIPS[n]] for n in names}


def build(ctx) -> None:
    uniq = _unique_poses(list(CLIPS))
    imgs = render_many(_key_poses() + list(uniq.values()))
    frames, done = imgs[:len(ENEMY_POSES)], dict(zip(uniq, imgs[len(ENEMY_POSES):]))
    for name, img in zip(ENEMY_POSES, frames):
        _check_margins(img, name)
    cells = render_clips(CLIPS, lambda p: done[_key(p)])
    ctx.save_fighter("sprites/enemies/%s.png" % ID, frames, cells, (S, S), S, ID, preview_ms=PREVIEW_MS)
    sheet = hstack(frames)
    ctx.extra("sheet_1x.png", sheet, scale=1, frame_w=S)
    ctx.extra("sheet_2x.png", sheet, scale=2, frame_w=S)
    por = render_portrait()
    _check_margins(por, "portrait", bust=True)
    ctx.save("sprites/portraits/%s.png" % ID, por)
    ctx.extra("portrait_1x.png", por, scale=1)
    ctx.extra("portrait_8x.png", por, scale=8)
    ctx.extra("anim_test.png", anim_test(), scale=4, frame_w=S)
