"""Rotten Husk: a person the rot dried and hollowed out into a bark-skinned, hunched thing.

Silhouette: a heavy, high hump armoured in a few big dark bark plates with broken branches growing
out of it, a skull-like head hanging forward on a jutting neck, very long arms with bark-crusted
forearms ending in big hooked bone claws (three talons and a thumb hook), lean bent legs on clawed
bark feet, tattered rags at the hips. Colour areas: olive-grey husk skin (a paler, greyer face),
a dark bark shell (hump plates) and brown bark (forearms, knees, feet), pale bone (claws and
fangs), dull brown rags, a few violet rot lesions, and the rot core: a hole eaten into the flank,
two ribs across it, glowing a dim rot-green (bright in the windup tell, with the eyes and mouth).

The talons are drawn as crisp 1-2 pixel strokes over the render (draw_talons), not as 3D shapes:
three hooks of one hand are one body part, so as shapes they merged into a pale blob, while as
strokes each keeps its own outline. Close-ups (the portrait) use the same curves as 3D cones.
Eyes, lesions and the glowing mouth are small decals painted onto the rendered surface (only on
the right body part, never off the silhouette), so they stay clean 2-3 pixel shapes.

Phase 10: POSES holds the keyframes (plain dicts, every pose carrying every key), model(pose)
builds the SDF model and render_pose(pose) draws one RGBA frame. CLIPS (at the end) lists every
animation clip of plan 4.2 as row-0 keys and pose dicts, most of them hand-set in-betweens
(kit.rig.blend plus changes); the build renders them in worker processes. Pose keys used only by
clips (absent = off, so the row-0 keys render exactly as in phase 9):
    dead     1 = the rot core has gone dark (death)
    rubble   0..1 flight time of the clods the slam throws up round the claws
    crumbs   0..1 how much bark has fallen off onto the floor (death)
"""
from __future__ import annotations

import math
import os
from typing import Any, Sequence

import numpy as np

from kit.color import to_oklch
from kit.palette import INK, M, Material
from kit.post import cleanup, contours, outline
from kit.render import DEFAULT_LIGHT, Camera, Frame, line3d, render
from kit.rig import Build, Skeleton, blend, pose_skeleton
from kit.sdf import (Box, Cylinder, Ellipsoid, Node, Prim, Prism, RoundCone, SmoothUnion, Sphere,
                     Subtract, Torus, Union, basis, rot)
from kit.clips import ENEMY_PREVIEW_MS, render_clips
from kit.sheet import hstack
from kit.specs import ENEMY_FRAME, ENEMY_POSES, HERO_CELL, HERO_FRAME, PORTRAIT

ID = "rotten_husk"
S = ENEMY_FRAME[ID]

# Taller and longer-limbed than a hero (a hero is about 45 px): about 60 px when it rears up.
BUILD = Build(ankle_h=2.2, shin=12.0, thigh=11.5, spine=16.0, neck=3.0, head_r=5.0,
              shoulder_w=7.0, hip_w=3.1, upper_arm=12.5, forearm=12.0, foot_len=5.0)

# --- Materials -----------------------------------------------------------------------------------
# The shared husk_skin ramp steps its shadows toward green (its hue walks the short way to
# violet, through green), which reads as a frog. Same mid and light colours, but the two shadow
# steps go olive-grey then violet-grey, so the husk looks dried and dead.
SKIN = Material(name="husk_hide", colors=["#413845", "#5c5c48"] + M["husk_skin"].colors[2:],
                wrap=0.35, ao=0.5)
# Bark stops below its greyest top colour, so lit bark stays brown instead of stone-grey.
BARK = Material(name="husk_bark", colors=list(M["husk_bark"].colors), hi=3.2, wrap=0.3)
# The hump's shell: the same bark kept to its three darkest colours, so the plates read as one
# dark mass over the paler dead skin instead of a patchwork.
PLATE = Material(name="husk_plate", colors=list(M["husk_bark"].colors), hi=2.45, wrap=0.3, ao=0.3)
# The face: dried skin stretched over the skull, a step paler and greyer than the body so the
# head reads apart from the hump it hangs in front of.
FACE = Material(name="husk_face", colors=["#4a4049", "#6b6955", "#8d8c6f", "#aaa68a", "#c4bea2"],
                wrap=0.35, ao=0.5)
LESION = M["rot_purple"]
BONE = M["bone"]
# Ribs showing in the rot hole: skin-covered bone, paler than the hide but duller than the
# claws (which own the bright bone colours).
RIB = Material(name="husk_rib", colors=["#5e5a4c", "#7d7a62", "#a39f83", "#bdb79a", "#cfc8a9"],
               hi=3.0, wrap=0.4)
EYE = M["glow_rot"]
# Rags: a dull warm brown-grey, lighter than the shadows they hang in, so the strips show.
RAG = Material.make("husk_rag", "#6a5d4e", wrap=0.45, ao=0.4)
MAW = Material.make("husk_maw", "#3b2233", below=1, above=1, wrap=0.2, ao=0.2)
# The rot core in the flank: the husk's accent rot-green (#7aa344), a dim glow at rest; in the
# windup tell it flares to the bright rot glow with the eyes and the mouth.
CORE = Material.make("husk_rot_core", "#7aa344", below=2, above=1, emissive=True, glow_index=2)
CORE_HOT = Material(name="husk_rot_core_hot", colors=list(EYE.colors), emissive=True, glow_index=3)
# Phase 10: the core once the husk is dead (a dark, unlit rot), and the clods its slam throws up
# and the bark that falls off it as it crumbles.
CORE_DEAD = Material.make("husk_rot_core_dead", "#3f4a30", below=1, above=1, wrap=0.3, ao=0.3)
CLOD = Material.make("husk_clod", "#857260", wrap=0.35, ao=0.2)

# --- Poses ---------------------------------------------------------------------------------------
# Keys from kit.rig.pose_skeleton (pelvis, lean, side_lean, twist, hand_*, elbow_*, foot_*, knee_*,
# toe_*) plus the husk's own:
#   neck        neck direction, degrees from straight up toward the front (90 = level forward)
#   head        (pitch down, yaw, tilt) of the face in degrees, relative to level
#   jaw         jaw opening in degrees
#   claw_n/f    direction the hand points; hook_n/f: the way its talons curl (world directions)
#   spread_n/f  how far the talons fan apart (1 = normal)
#   curl        how hooked the talons are (1 = normal; never below 1, the hooks are the husk)
#   glow        0..1 eye brightness (1 = the windup tell: eyes, mouth and rot core flare)
#   eyes        1 = eyes lit, 0 = shut dark (the hurt flinch)
#   rag         (x, z) swing of the hanging rags


def _pose(**kw: Any) -> dict[str, Any]:
    """A pose carrying every key (so any two blend cleanly), defaults filled in."""
    p: dict[str, Any] = dict(
        pelvis=(-6.0, 22.0, 0.0), lean=50.0, side_lean=0.0, twist=0.0,
        neck=110.0, head=(-12.0, -10.0, 0.0), jaw=14.0, glow=0.0, eyes=1.0,
        hand_n=(14.0, 12.0, 7.0), elbow_n=(-1.0, 0.0, 0.5), claw_n=(0.3, -1.0, 0.0),
        hook_n=(1.0, 0.0, 0.0), spread_n=1.0,
        hand_f=(8.0, 14.0, -7.0), elbow_f=(-1.0, 0.0, -0.5), claw_f=(0.3, -1.0, 0.0),
        hook_f=(1.0, 0.0, 0.0), spread_f=1.0,
        foot_n=(4.0, 2.2, 4.4), foot_f=(-11.0, 2.2, -4.0),
        knee_n=(1.0, 0.0, 0.15), knee_f=(1.0, 0.0, -0.15), toe_n=0.0, toe_f=6.0,
        curl=1.0, rag=(0.0, 0.0),
    )
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    # Hunched and swaying, head hanging forward low, long arms dangling in front, the claws
    # hanging down and hooking forward like scythes.
    "idle": _pose(
        pelvis=(-10.3, 21.3, 0.0), lean=54.0, side_lean=3.0, twist=10.0,
        neck=98.0, head=(-10.0, -28.0, -4.0), jaw=26.0,
        hand_n=(14.0, 11.5, 8.0), elbow_n=(-1.0, 0.1, 0.6), claw_n=(0.25, -1.0, 0.1),
        hook_n=(1.0, 0.0, 0.0),
        hand_f=(18.0, 16.5, -6.0), elbow_f=(-0.6, -0.3, -1.0), claw_f=(0.3, -1.0, -0.1),
        hook_f=(1.0, 0.0, 0.0),
        foot_n=(0.4, 2.2, 4.6), foot_f=(-16.6, 2.2, -4.2), toe_f=6.0,
    ),
    # The tell: rears up with the hump still topping the silhouette, near claw raised high and
    # back, roaring; eyes, mouth and the rot core flare rot-green.
    "windup": _pose(
        pelvis=(-7.2, 23.0, 0.0), lean=30.0, side_lean=-3.0, twist=-20.0,
        neck=72.0, head=(-26.0, -14.0, 4.0), jaw=40.0, glow=1.0,
        hand_n=(-12.0, 50.0, 6.0), elbow_n=(-0.2, 1.0, 0.8), claw_n=(0.2, 1.0, 0.0),
        hook_n=(1.0, 0.1, 0.0), spread_n=1.6,
        hand_f=(14.0, 22.0, -7.0), elbow_f=(-1.0, -0.4, -0.6), claw_f=(0.3, -1.0, 0.0),
        hook_f=(1.0, 0.0, 0.0), spread_f=1.4,
        foot_n=(4.5, 2.2, 4.6), foot_f=(-16.8, 2.2, -4.4), toe_f=10.0,
        curl=1.15, rag=(-1.0, 0.0),
    ),
    # Lurching in low toward the target: a long, low arrow pointing left, the near claw reaching
    # out ahead at shoulder height, the lead foot far forward, the back leg trailing.
    "lunge": _pose(
        pelvis=(-8.0, 17.0, 0.0), lean=72.0, side_lean=2.0, twist=20.0,
        neck=100.0, head=(-18.0, -14.0, -4.0), jaw=32.0, glow=0.6,
        hand_n=(30.0, 24.0, 6.0), elbow_n=(-0.4, -1.0, 0.6), claw_n=(1.0, -0.3, 0.0),
        hook_n=(0.0, -1.0, 0.0), spread_n=1.4,
        hand_f=(-16.0, 14.0, -7.0), elbow_f=(0.2, -1.0, -0.6), claw_f=(-0.6, -1.0, 0.0),
        hook_f=(1.0, 0.0, 0.0), spread_f=0.8,
        foot_n=(11.0, 2.2, 4.6), foot_f=(-25.0, 3.0, -3.8), toe_f=34.0, knee_f=(1.0, -0.3, -0.2),
        curl=1.1, rag=(-3.0, 0.0),
    ),
    # The swipe landing: body twisted into it, the near arm flung straight out and swept down
    # through the target, talons spread and raking; the far arm swung back; head up, eyes on
    # the target.
    "contact": _pose(
        pelvis=(-13.0, 18.0, 0.0), lean=62.0, side_lean=-3.0, twist=45.0,
        neck=120.0, head=(-42.0, -18.0, 0.0), jaw=34.0, glow=0.6,
        hand_n=(28.0, 26.0, 3.0), elbow_n=(0.0, -1.0, 0.6), claw_n=(1.0, -0.7, 0.0),
        hook_n=(-0.2, -1.0, 0.0), spread_n=1.8,
        hand_f=(-14.0, 14.0, -7.0), elbow_f=(0.2, -1.0, -0.6), claw_f=(-0.6, -1.0, 0.0),
        hook_f=(1.0, 0.0, 0.0), spread_f=0.8,
        foot_n=(4.0, 2.2, 4.6), foot_f=(-26.0, 2.2, -4.0), toe_f=20.0,
        rag=(-2.0, 1.0),
    ),
    # Recoil: arched back, head snapped up and back, the near arm flung back behind, the far arm
    # thrown up in front, the far foot kicked back off the ground.
    "hurt": _pose(
        pelvis=(-8.0, 21.5, 0.0), lean=-34.0, side_lean=6.0, twist=-10.0,
        neck=-18.0, head=(-60.0, -6.0, 18.0), jaw=40.0, eyes=0.0,
        hand_n=(-22.0, 32.0, 9.0), elbow_n=(0.2, -1.0, 0.6), claw_n=(-0.6, -1.0, 0.0),
        hook_n=(1.0, 0.0, 0.0), spread_n=1.2,
        hand_f=(10.0, 44.0, -8.0), elbow_f=(0.2, -1.0, -0.4), claw_f=(0.6, 1.0, 0.0),
        hook_f=(1.0, 0.0, 0.0), spread_f=1.2,
        foot_n=(3.0, 2.2, 4.6), foot_f=(-14.0, 10.0, -3.6), toe_f=30.0,
        curl=1.1, rag=(2.5, 0.0),
    ),
    # Both claws smashed into the ground in front at two points, elbows flared up and out, body
    # folded down between them, hump high, head between the arms.
    "slam": _pose(
        pelvis=(-10.3, 20.4, 0.0), lean=80.0, side_lean=0.0, twist=0.0,
        neck=140.0, head=(-10.0, -10.0, 0.0), jaw=38.0, glow=0.6,
        hand_n=(12.0, 4.0, 10.0), elbow_n=(-0.3, 0.8, 1.0), claw_n=(1.0, -0.4, 0.2),
        hook_n=(0.0, -1.0, 0.0), spread_n=1.4,
        hand_f=(22.0, 4.0, -9.0), elbow_f=(-0.3, 0.8, -1.0), claw_f=(1.0, -0.4, -0.2),
        hook_f=(0.0, -1.0, 0.0), spread_f=1.4,
        foot_n=(4.5, 2.2, 4.8), foot_f=(-16.6, 2.2, -4.4), toe_f=10.0,
        curl=1.0, rag=(1.5, 0.0),
    ),
}


# --- Small helpers -------------------------------------------------------------------------------


def _v(x: Sequence[float]) -> np.ndarray:
    return np.asarray(x, dtype=float)


def _unit(x: Sequence[float]) -> np.ndarray:
    v = _v(x)
    return v / (np.linalg.norm(v) + 1e-9)


def _rotate_toward(d: np.ndarray, toward: np.ndarray, deg: float) -> np.ndarray:
    """Turns direction d toward `toward` (in their common plane) by deg degrees."""
    d = _unit(d)
    t = _v(toward) - d * float(np.dot(toward, d))
    if np.linalg.norm(t) < 1e-6:
        return d
    t = _unit(t)
    a = math.radians(deg)
    return d * math.cos(a) + t * math.sin(a)


def _frame_n(normal: Sequence[float], hint: Sequence[float] = (0.0, 1.0, 0.0)) -> np.ndarray:
    """Rotation whose local y is `normal` (a plate lying on a surface), local x near `hint`."""
    n = _unit(normal)
    h = _v(hint)
    if abs(float(np.dot(_unit(h), n))) > 0.95:
        h = _v((1.0, 0.0, 0.0)) if abs(n[0]) < 0.9 else _v((0.0, 0.0, 1.0))
    t = _unit(h - n * float(np.dot(h, n)))
    return basis(t, n)


def _surf(c: np.ndarray, radii: Sequence[float], R: np.ndarray,
          local_dir: Sequence[float]) -> tuple[np.ndarray, np.ndarray]:
    """Point and outward normal on an ellipsoid where the ray from its centre along `local_dir`
    (in the ellipsoid's own axes) leaves it."""
    d = _unit(local_dir)
    r = _v(radii)
    p = d / math.sqrt(float(np.sum((d / r) ** 2)))
    n = _unit(p / r ** 2)
    return c + R @ p, R @ n


def _leaf_bound(p: Prim) -> tuple[np.ndarray, float]:
    """A sphere around one primitive (for the Bounded speed-up)."""
    pad = abs(p.bumps[0]) * 1.6 if p.bumps else 0.0
    if isinstance(p, RoundCone):
        return (p.a + p.b) / 2.0, float(np.linalg.norm(p.b - p.a)) / 2.0 + max(p.ra, p.rb) + pad
    if isinstance(p, Sphere):
        return p.pos, p.r + pad
    if isinstance(p, Ellipsoid):
        return p.pos, float(p.radii.max()) + pad
    if isinstance(p, Box):
        return p.pos, float(np.linalg.norm(p.half)) + pad
    if isinstance(p, Torus):
        return p.pos, p.R0 + p.r + pad
    if isinstance(p, Cylinder):
        return p.pos, math.hypot(p.r, p.h) + pad
    if isinstance(p, Prism):
        return p.pos, float(np.linalg.norm(p.poly, axis=1).max()) + p.hz + pad
    return p.pos, 1e6


class Bounded(Node):
    """Wraps a body part in a bounding sphere: rays far from it skip evaluating its shapes (a pure
    speed-up; the distance returned far away is a safe lower bound)."""

    MARGIN = 2.5

    def __init__(self, child: Node) -> None:
        self.child = child
        self._leaves = child.leaves()
        spheres = [_leaf_bound(lf) for lf in self._leaves]
        lo = np.min([c - r for c, r in spheres], axis=0)
        hi = np.max([c + r for c, r in spheres], axis=0)
        self.c = (lo + hi) / 2.0
        self.r = max(float(np.linalg.norm(c - self.c)) + r for c, r in spheres)

    def eval(self, P: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        ds = np.linalg.norm(P - self.c, axis=1) - self.r
        part = np.full(P.shape[0], self._leaves[0].part, dtype=np.int32)
        near = ds < self.MARGIN
        if near.any():
            dn, pn = self.child.eval(P[near])
            ds = ds.copy()
            ds[near] = dn
            part[near] = pn
        return ds, part

    def leaves(self) -> list[Prim]:
        return self._leaves


class Scaled(Node):
    """Scales a whole model uniformly about the ground origin (poses stay in design units)."""

    def __init__(self, child: Node, k: float) -> None:
        self.child = child
        self.k = k

    def eval(self, P: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        d, p = self.child.eval(P / self.k)
        return d * self.k, p

    def leaves(self) -> list[Prim]:
        return self.child.leaves()


# --- Skeleton ------------------------------------------------------------------------------------

RIB_R = (5.4, 7.2, 6.6)
HUMP_R = (6.8, 6.6, 7.6)
NECK_LEN = 8.0
# Where the rot core is eaten into the rib cage (torso-local direction: the near flank).
CAVITY_DIR = (0.45, 0.0, 1.0)
HEAD = 1.48  # head size factor
CLAW = 1.2   # talon length factor
# Whole-model size: poses and proportions are in design units, the sprite is SIZE times that.
SIZE = 1.1


def skeleton(pose: dict[str, Any]) -> Skeleton:
    """rig.pose_skeleton for limbs, plus the husk's own neck and head: the neck leaves the front
    of the chest (the hunch), and the head is placed by `neck` and `head`."""
    sk = pose_skeleton(BUILD, pose)
    t = sk.torso
    yaw = float(pose.get("hip_yaw", 0.0)) + float(pose.get("twist", 0.0))
    base = sk["chest"] + t @ _v((3.2, -0.6, 0.0))
    a = math.radians(float(pose.get("neck", 60.0)))
    ndir = rot(0.0, yaw, 0.0) @ _v((math.sin(a), math.cos(a), 0.0))
    neck_top = base + ndir * NECK_LEN
    hp, hy, ht = pose.get("head", (0.0, 0.0, 0.0))
    H = rot(0.0, yaw + hy, -hp) @ rot(ht, 0.0, 0.0)
    sk.head = H
    sk.j["neck"] = base
    sk.j["neck_top"] = neck_top
    sk.j["head"] = neck_top + H @ _v((0.9, 1.5, 0.0))
    # Torso landmarks (shared by the model and the rags).
    sk.j["rib"] = sk["chest"] + t @ _v((1.0, -4.6, 0.0))
    sk.j["hump"] = sk["chest"] + t @ _v((-3.4, -0.6, 0.0))
    return sk


def head_point(sk: Skeleton, x: float, y: float, z: float) -> np.ndarray:
    """A point in the head's own frame (design units, head-size scaled)."""
    return sk["head"] + sk.head @ _v((x * HEAD, y * HEAD, z * HEAD))


# --- Model ---------------------------------------------------------------------------------------


def _above(p: np.ndarray, r: float) -> np.ndarray:
    """Keeps a claw sphere (radius r at p) on or above the floor, and never lower on screen than
    the second-to-last row: in the 3/4 view the floor in front of and beside the husk shows
    lower than its feet, so claws resting far forward are lifted a hair to stay in the frame."""
    vx, vy, vz = Camera(S, S, face="left").R[1]
    lowest = (CAM_CY + 0.5 + 0.35) / SIZE + r - vx * p[0] - vz * p[2]
    return _v((p[0], max(p[1], r + 0.1, lowest / vy), p[2]))


def _cone(mat: Material, a: np.ndarray, b: np.ndarray, ra: float, rb: float, **kw) -> Prim:
    """RoundCone that stays valid when clamping made the segment shorter than the radius step."""
    if float(np.linalg.norm(b - a)) < abs(ra - rb) + 0.05:
        return Sphere(mat, a if ra >= rb else b, max(ra, rb), **kw)
    return RoundCone(mat, a, b, ra, rb, **kw)


def _hand_axes(sk: Skeleton, side: str, pose: dict[str, Any]) -> tuple[np.ndarray, ...]:
    """Palm centre and its axes: f = where the hand points, h = the way the talons curl,
    s = across the palm."""
    el, ha = sk["elbow_" + side], sk["hand_" + side]
    fore = _unit(ha - el)
    f = _unit(pose.get("claw_" + side, fore))
    hook = _unit(pose.get("hook_" + side, (1.0, 0.0, 0.0)))
    h = hook - f * float(np.dot(hook, f))
    h = _unit(h) if np.linalg.norm(h) > 1e-6 else _unit(np.cross(f, (0.0, 0.0, 1.0)))
    s = _unit(np.cross(f, h))
    return ha + f * 0.4, f, h, s


# Talon shape: (length, bend toward the curl in degrees) per step, base to tip. Nearly straight
# for the first half, then most of the bend in the last third: a clear hook at the tip.
TALON_STEPS = ((1.6, 0.0), (1.6, 3.0), (1.5, 6.0), (1.3, 16.0), (1.1, 32.0), (0.9, 44.0),
               (0.7, 50.0))
# The three talons: (offset along the curl, fan angle, length, offset across, base width px).
TALONS = ((-1.05, -14.0, 0.86, 0.9, 2), (0.15, 0.0, 1.05, 0.0, 3), (1.3, 14.0, 0.9, -0.9, 2))


def talon_curves(sk: Skeleton, side: str, pose: dict[str, Any]) -> list[tuple[list[np.ndarray], int]]:
    """The talons of one hand as model-space polylines (design units) with their base width in
    pixels: three long hooks stacked along the curl direction (so from the side they read as a
    rake of separate hooks) and a short thumb hook."""
    hand, f, h, s = _hand_axes(sk, side, pose)
    curl = max(1.0, float(pose.get("curl", 1.0)))
    spread = float(pose.get("spread_" + side, 1.0))
    out: list[tuple[list[np.ndarray], int]] = []
    for off, fan, ln, zo, w in TALONS:
        p = hand + f * 2.4 - h * off * 1.45 * spread + s * zo
        d = _rotate_toward(f, -h if fan < 0 else h, abs(fan) * spread)
        pts = [p]
        for length, bend in TALON_STEPS:
            d = _rotate_toward(d, h, bend * curl)
            p = p + d * length * ln * CLAW
            pts.append(p)
        out.append((pts, w))
    p = hand + f * 0.4 + h * 1.9
    d = _rotate_toward(f, h, 55.0)
    pts = [p]
    for length, bend in ((1.4, 10.0), (1.2, 30.0), (1.0, 45.0)):
        d = _rotate_toward(d, h, bend * curl)
        p = p + d * length * 0.7 * CLAW
        pts.append(p)
    out.append((pts, 1))
    return out


def _talons3d(curves: list[tuple[list[np.ndarray], int]], group: str) -> list[Node]:
    """The talons as tapering 3D cones (for close-ups, where pixel lines would be too thin)."""
    out: list[Node] = []
    for pts, w in curves:
        n = len(pts) - 1
        r0 = 0.75 if w > 1 else 0.6
        for i in range(n):
            ra = r0 * (1.0 - i / n) + 0.1
            rb = r0 * (1.0 - (i + 1) / n) + 0.1
            out.append(_cone(BONE, pts[i], pts[i + 1], ra, rb, group=group, thin=True))
    return out


def _hand(sk: Skeleton, side: str, pose: dict[str, Any], group: str, talons3d: bool) -> list[Node]:
    """A big bony hand: a knuckly palm with a bark crust on its back (talons: see talon_curves)."""
    hand, f, h, s = _hand_axes(sk, side, pose)
    R = np.stack([f, h, s], axis=1)
    out: list[Node] = [
        Ellipsoid(SKIN, _above(hand + f * 1.0, 1.9), (2.6, 2.0, 2.4), R=R, group=group + "_hand"),
        Ellipsoid(BARK, _above(hand + f * 0.6 - h * 1.0, 1.4), (2.2, 1.2, 2.1), R=R,
                  group=group + "_hand", bumps=(0.12, 1.2, 71)),
    ]
    if talons3d:
        out += _talons3d(talon_curves(sk, side, pose), group + "_claw")
    return out


def _arm(sk: Skeleton, side: str, pose: dict[str, Any], talons3d: bool = False) -> Node:
    g = "arm_" + side
    sh, el, ha = sk["shoulder_" + side], sk["elbow_" + side], sk["hand_" + side]
    up = _unit(el - sh)
    fore = _unit(ha - el)
    seed = 10 if side == "n" else 14
    # A bark spur grows back out of the elbow (a cruel point on the silhouette).
    spur_d = _unit(up * 0.8 - fore * 0.6)
    parts: list[Node] = [
        RoundCone(SKIN, sh, el, 2.6, 1.8, group=g),
        Sphere(SKIN, el, 2.0, group=g),
        # Bark grown over the forearm like a bracer, thicker toward the wrist.
        RoundCone(BARK, el + fore * 0.4, ha - fore * 0.2, 2.0, 2.8, group=g + "_bark",
                  bumps=(0.16, 0.9, seed + 1)),
        RoundCone(BARK, el - fore * 0.2, el + spur_d * 3.6, 1.3, 0.35, group=g + "_bark",
                  thin=True),
    ]
    parts += _hand(sk, side, pose, g, talons3d)
    return Bounded(Union(*parts))


def _leg(sk: Skeleton, side: str) -> Node:
    g = "leg_" + side
    hip, kn, an, toe = sk["hip_" + side], sk["knee_" + side], sk["ankle_" + side], sk["toe_" + side]
    fdir = _unit(toe - an)
    sdir = _unit(np.cross(fdir, (0.0, 1.0, 0.0)))
    seed = 20 if side == "n" else 25
    parts: list[Node] = [
        RoundCone(SKIN, hip, kn, 2.6, 1.7, group=g),
        Sphere(SKIN, kn, 1.8, group=g),
        RoundCone(SKIN, kn, an, 1.5, 1.1, group=g),
        # Bark knee cap; bark crusts the foot, which ends in two bone toe claws.
        Ellipsoid(BARK, kn + _v((0.8, 0.3, 0.0)), (1.5, 1.9, 1.8), group=g + "_bark",
                  bumps=(0.15, 1.0, seed + 2)),
        RoundCone(BARK, an, toe, 1.5, 1.0, group=g + "_bark"),
    ]
    for off in (-0.9, 0.9):
        b = toe + sdir * off - fdir * 0.6
        b = _above(b, 0.6)
        parts.append(_cone(BONE, b, _above(b + fdir * 2.2 + _v((0.0, -0.5, 0.0)), 0.25), 0.6, 0.25,
                           group=g + "_claw", thin=True))
    return Bounded(Union(*parts))


def _cavity(sk: Skeleton) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Centre, outward normal and frame of the rot core's opening on the flank."""
    cav_p, cav_n = _surf(sk["rib"], RIB_R, sk.torso, CAVITY_DIR)
    CF = _frame_n(cav_n, sk.torso @ _v((0.0, 1.0, 0.0)))  # x = up the spine, y = out, z = across
    return cav_p, cav_n, CF


def _torso(sk: Skeleton, pose: dict[str, Any]) -> Node:
    t = sk.torso
    ch, be, pe = sk["chest"], sk["belly"], sk["pelvis"]
    rib_c, hump_c = sk["rib"], sk["hump"]
    flesh = SmoothUnion(
        Ellipsoid(SKIN, rib_c, RIB_R, R=t, group="torso"),
        Ellipsoid(SKIN, hump_c, HUMP_R, R=t, group="torso"),
        Ellipsoid(SKIN, ch + t @ _v((1.6, 0.8, 0.0)), (4.0, 3.4, 6.0), R=t, group="torso"),
        Ellipsoid(SKIN, be + t @ _v((0.4, -1.2, 0.0)), (2.6, 4.4, 3.3), R=t, group="torso"),
        Ellipsoid(SKIN, pe, (3.3, 3.0, 4.2), R=sk.hips, group="torso"),
        Sphere(SKIN, sk["shoulder_n"], 3.1, group="torso"),
        Sphere(SKIN, sk["shoulder_f"], 3.1, group="torso"),
        RoundCone(SKIN, sk["neck"], sk["neck_top"], 2.4, 1.7, group="torso"),
        k=2.2,
    )
    # The rot core: a hole eaten into the near flank, lined with a rot-green glow (dark once dead).
    core = CORE_HOT if float(pose.get("glow", 0.0)) >= 0.9 else CORE
    if float(pose.get("dead", 0.0)) >= 0.5:
        core = CORE_DEAD
    cav_p, cav_n, CF = _cavity(sk)
    cavity = Ellipsoid(core, cav_p - cav_n * 0.6, (3.0, 1.9, 2.6), R=CF, group="cavity")
    parts: list[Node] = [Subtract(flesh, cavity, b_material=True)]
    # Two ribs bridge the hole (kept inside it, so they never poke out of the skin).
    for dy in (1.0, -1.0):
        a = cav_p + CF @ _v((dy + 0.2, -0.9, -2.4))
        b = cav_p + CF @ _v((dy - 0.2, -0.9, 2.4))
        mid = cav_p + CF @ _v((dy, -0.45, 0.0))
        parts.append(RoundCone(RIB, a, mid, 0.42, 0.38, group="rib", thin=True))
        parts.append(RoundCone(RIB, mid, b, 0.38, 0.34, group="rib", thin=True))
    up = t @ _v((0.0, 1.0, 0.0))
    # A few big bark plates armour the hump (torso-local directions: -x = back, +y = up the
    # spine, +z = near side): one dark shell, split by a couple of dark seams.
    for d, rad, seed in (((-0.75, 0.55, 0.05), (5.6, 1.5, 5.4), 31),
                         ((-1.0, -0.35, 0.2), (4.6, 1.4, 5.0), 32),
                         ((-0.2, 0.95, 0.15), (3.8, 1.3, 4.6), 36)):
        p, n = _surf(hump_c, HUMP_R, t, d)
        parts.append(Ellipsoid(PLATE, p - n * 0.55, rad, R=_frame_n(n, up), group="plates",
                               bumps=(0.18, 0.8, seed)))
    # A bark pauldron over the near shoulder widens the shoulder line.
    sh = sk["shoulder_n"]
    parts.append(Ellipsoid(PLATE, sh + t @ _v((-0.6, 1.4, 0.0)), (3.2, 1.7, 2.9), R=t,
                           group="plates", bumps=(0.15, 1.1, 37)))
    # Dead branches growing out of the back of the hump (the silhouette's signature).
    for d, ln, bend, fork in (((-0.75, -0.55, 0.25), 10.0, 30.0, 0.55),
                              ((-0.45, -0.85, -0.3), 7.5, 40.0, 0.5),
                              ((-0.2, -0.7, 0.75), 5.5, 30.0, 0.0)):
        p, n = _surf(hump_c, HUMP_R, t, d)
        dd = _unit(_rotate_toward(n, (0.0, 1.0, 0.0), bend))
        tip = p + dd * ln
        parts.append(RoundCone(BARK, p - n * 0.8, tip, 1.5, 0.45, group="branch", thin=True))
        if fork > 0:
            fp = p + dd * ln * fork
            fd = _rotate_toward(dd, (0.0, 1.0, 0.0), 50.0)
            parts.append(RoundCone(BARK, fp, fp + fd * ln * 0.42, 0.7, 0.35, group="branch",
                                   thin=True))
    return Bounded(Union(*parts))


# Upper fangs: (angle around the mouth, length, inward hook). Uneven on purpose: two long fangs
# at the corners, one broken stub, one short; a long lower fang rises over the upper row.
UPPER_FANGS = ((-60.0, 2.1, 0.5), (-22.0, 0.6, 0.0), (16.0, 1.3, 0.3), (54.0, 2.4, 0.6))
LOWER_FANGS = ((-34.0, 1.3, 0.3), (30.0, 2.1, 0.5))


def _head(sk: Skeleton, pose: dict[str, Any]) -> Node:
    """A skull with dried skin stretched over it: round cranium, short face, deep sockets over
    sunken cheeks, a nose hole, a heavy bark brow, a skin-covered jaw hanging open on long,
    uneven fangs."""
    H = sk.head
    c = sk["head"]
    k = HEAD

    def hp(x: float, y: float, z: float) -> np.ndarray:
        return c + H @ _v((x * k, y * k, z * k))

    jaw = float(pose.get("jaw", 10.0))
    J = H @ rot(0.0, 0.0, -jaw)
    hinge = hp(-0.2, -1.1, 0.0)

    def jp(x: float, y: float, z: float) -> np.ndarray:
        return hinge + J @ _v((x * k, y * k, z * k))

    def r3(a: float, b: float, cc: float) -> tuple[float, float, float]:
        return (a * k, b * k, cc * k)

    skull = SmoothUnion(
        Ellipsoid(FACE, hp(-0.5, 0.9, 0.0), r3(3.6, 3.5, 3.2), R=H, group="head"),
        Ellipsoid(FACE, hp(2.1, -0.4, 0.0), r3(2.0, 1.5, 2.1), R=H, group="head"),
        # Cheekbones: the face is gaunt, so they stand out over the sunken cheeks.
        Ellipsoid(FACE, hp(1.7, 0.0, 1.8), r3(1.2, 0.8, 0.8), R=H, group="head"),
        Ellipsoid(FACE, hp(1.7, 0.0, -1.8), r3(1.2, 0.8, 0.8), R=H, group="head"),
        k=1.2,
    )
    holes = Union(
        Sphere(MAW, hp(2.45, 0.8, 1.35), 1.1 * k, group="socket"),
        Sphere(MAW, hp(2.45, 0.8, -1.35), 1.1 * k, group="socket"),
        Sphere(MAW, hp(3.45, 0.05, 0.0), 0.42 * k, group="socket"),
    )
    # The cheeks fall in under the cheekbones (the skin is dried onto the skull).
    hollows = Union(
        Sphere(FACE, hp(1.4, -1.25, 2.75), 1.05 * k, group="head"),
        Sphere(FACE, hp(1.4, -1.25, -2.75), 1.05 * k, group="head"),
    )
    parts: list[Node] = [
        Subtract(Subtract(skull, hollows), holes, b_material=True),
        # A heavy bark brow ridge low over both sockets (a scowl), dipping over the nose.
        Ellipsoid(BARK, hp(2.45, 1.75, 0.9), r3(1.0, 0.55, 1.5), R=H @ rot(-14, 0, -18),
                  group="brow", bumps=(0.1, 1.2, 52)),
        Ellipsoid(BARK, hp(2.6, 1.6, -0.6), r3(0.9, 0.5, 1.0), R=H @ rot(14, 0, -18),
                  group="brow", bumps=(0.1, 1.2, 55)),
        # Bark crusting the crown and the back of the skull.
        Ellipsoid(BARK, hp(-1.4, 3.2, 0.8), r3(2.1, 1.0, 1.7), R=H @ rot(20, 0, 18), group="brow",
                  bumps=(0.18, 1.0, 53)),
        Ellipsoid(BARK, hp(-3.0, 1.5, -0.5), r3(1.3, 1.9, 1.8), R=H, group="brow",
                  bumps=(0.18, 1.0, 54)),
        # The jaw: dried skin over two slim rami from under the ears to a pointed chin (a U),
        # hanging open on the dark inside of the mouth, so only the fangs are pale.
        RoundCone(FACE, jp(0.0, 0.0, 1.35), jp(3.0, -0.35, 0.8), 0.6 * k, 0.45 * k,
                  group="jaw"),
        RoundCone(FACE, jp(0.0, 0.0, -1.35), jp(3.0, -0.35, -0.8), 0.6 * k, 0.45 * k,
                  group="jaw"),
        RoundCone(FACE, jp(3.0, -0.35, 0.8), jp(3.0, -0.35, -0.8), 0.5 * k, 0.5 * k,
                  group="jaw"),
        # Inside of the mouth, between the upper teeth and the jaw.
        Ellipsoid(MAW, hp(1.9, -1.5, 0.0), r3(2.0, 1.0, 1.45), R=H, group="maw"),
        Ellipsoid(MAW, jp(1.7, 0.35, 0.0), r3(1.7, 0.6, 1.1), R=J, group="maw"),
    ]
    # Jagged teeth: thin fangs of uneven length that hook back into the mouth at the tip, with
    # dark gaps between them.
    for a, ln, hook in UPPER_FANGS:
        ar = math.radians(a)
        top = hp(1.7 + 1.9 * math.cos(ar), -1.25, 1.65 * math.sin(ar))
        mid = top + H @ _v((0.2, -ln * 0.6, 0.0)) * k
        tip = mid + H @ _v((-hook * 0.5, -ln * 0.4, -math.sin(ar) * hook * 0.3)) * k
        parts.append(RoundCone(BONE, top, mid, 0.27 * k, 0.17 * k, group="teeth", thin=True))
        parts.append(RoundCone(BONE, mid, tip, 0.17 * k, 0.06, group="teeth", thin=True))
    for a, ln, hook in LOWER_FANGS:
        ar = math.radians(a)
        bot = jp(1.9 + 1.25 * math.cos(ar), -0.1, 1.15 * math.sin(ar))
        mid = bot + J @ _v((-0.1, ln * 0.6, 0.0)) * k
        tip = mid + J @ _v((-hook * 0.5, ln * 0.4, -math.sin(ar) * hook * 0.3)) * k
        parts.append(RoundCone(BONE, bot, mid, 0.27 * k, 0.17 * k, group="teeth", thin=True))
        parts.append(RoundCone(BONE, mid, tip, 0.17 * k, 0.06, group="teeth", thin=True))
    return Bounded(Union(*parts))


def _rags(sk: Skeleton, pose: dict[str, Any]) -> Node:
    """A thin rope belt and torn loincloth strips that hang with gravity, whatever the lean; the
    longest strips hang on the near side, over the thigh."""
    pe = sk["pelvis"]
    hips = sk.hips
    sx, sz = pose.get("rag", (0.0, 0.0))
    parts: list[Node] = [
        Torus(RAG, pe + hips @ _v((0.0, 0.7, 0.0)), 3.8, 0.55, R=hips, group="rag"),
    ]
    # (side, offset across, width, length, tilt): side +1 = front, -1 = back, 0.25 = near hip.
    strips = ((1.0, 1.6, 1.5, 9.5, -4.0), (0.3, 3.9, 1.4, 11.0, 6.0), (-0.4, 3.6, 1.2, 8.0, -5.0),
              (-1.0, -1.2, 1.5, 9.0, 5.0))
    for side, off, wd, ln, tilt in strips:
        top = pe + hips @ _v((side * 3.3, 0.6, off))
        hang = _unit(rot(0.0, 0.0, tilt) @ _v((sx * 0.13 * np.sign(side), -1.0, sz * 0.13)))
        normal = hips @ _unit((side, 0.0, 0.8 if abs(side) < 0.5 else 0.0))
        normal = _unit(normal - hang * float(np.dot(normal, hang)))
        across = _unit(np.cross(normal, hang))
        R = np.stack([across, -hang, normal], axis=1)
        poly = [(-wd, 0.6), (wd, 0.6), (wd * 0.9, -ln * 0.72), (wd * 0.35, -ln),
                (-wd * 0.15, -ln * 0.74), (-wd * 0.7, -ln * 0.92), (-wd * 1.05, -ln * 0.55)]
        parts.append(Prism(RAG, top, poly, 0.45, R=R, group="rag", thin=True))
    return Bounded(Union(*parts))


# Clods the slam throws up around each claw: (along x, across z, peak height, radius), design
# units. They fly out and fall back over `rubble` 0..1 (0 and 1 = on the ground).
RUBBLE = ((4.0, 3.0, 10.0, 2.1), (-4.0, 4.5, 7.0, 1.7), (1.0, 1.0, 15.0, 1.4))
# Bark that falls off the husk as it crumbles (death): (x, z, radius, seed) lying on the ground.
CRUMBS = ((14.0, 6.5, 1.8, 81), (-2.0, 8.0, 1.4, 82), (24.0, 2.0, 1.3, 83), (-18.0, 5.0, 1.6, 84))


def _rubble(sk: Skeleton, pose: dict[str, Any]) -> list[Node]:
    """The slam's clods (pose key `rubble`, the flight time 0..1) and the death's fallen bark
    (pose key `crumbs` 0..1, how much has fallen)."""
    out: list[Node] = []
    t = float(pose.get("rubble", 0.0))
    if 0.0 < t < 1.0:
        for side, sgn in (("n", 1.0), ("f", -1.0)):
            h = sk["hand_" + side]
            for i, (dx, dz, peak, r) in enumerate(RUBBLE):
                y = r + peak * 4.0 * t * (1.0 - t)
                c = _v((h[0] + 3.0 + dx * t, y, h[2] + sgn * dz * t))
                out.append(Box(CLOD, c, (r, r * 0.8, r), R=rot(30.0 * i + 50.0 * t, 20.0 * i, 40.0 * t),
                               round=0.35, group="rubble"))
    k = float(pose.get("crumbs", 0.0))
    for i, (x, z, r, seed) in enumerate(CRUMBS[:int(round(k * len(CRUMBS)))]):
        out.append(Ellipsoid(PLATE, _v((x, r * 0.55, z)), (r * 1.3, r * 0.55, r), R=rot(0.0, 37.0 * i, 0.0),
                             group="crumbs", bumps=(0.12, 1.0, seed)))
    return out


def model(pose: dict[str, Any], sk: Skeleton | None = None, talons3d: bool = True) -> Node:
    """The husk as one SDF model for `pose` (design units scaled by SIZE). Sprites draw the
    talons as pixel lines instead (talons3d=False, then draw_talons after rendering)."""
    sk = sk or skeleton(pose)
    return Scaled(Union(
        _torso(sk, pose),
        _head(sk, pose),
        _arm(sk, "n", pose, talons3d),
        _arm(sk, "f", pose, talons3d),
        _leg(sk, "n"),
        _leg(sk, "f"),
        _rags(sk, pose),
        *_rubble(sk, pose),
    ), SIZE)


# --- Decals: eyes, lesions, the glowing mouth ----------------------------------------------------

HEAD_GROUPS = ("head", "socket", "brow", "jaw", "maw", "teeth")


def _toward_viewer(cam: Camera, light: float = 0.5) -> np.ndarray:
    """Model-space direction toward the viewer, tipped toward the light (where a decal on a
    rounded part shows best)."""
    view = cam.R.T @ _v((0.0, 0.0, 1.0))
    lit = cam.R.T @ _unit(DEFAULT_LIGHT)
    return _unit(view + lit * light)


def decal(fr: Frame, cam: Camera, point: np.ndarray, rows: Sequence[str],
          legend: dict[str, tuple[Material, int]], on_groups: Sequence[str],
          tol: float = 2.0, inset: int = 0, toward: tuple[float, float] | None = None,
          group: str = "decal") -> bool:
    """Paints a tiny pattern centred on model `point` (already scaled), only over visible pixels
    of `on_groups` whose depth is within `tol` of the point (so it never floats off the
    silhouette or onto a part passing in front). inset > 0: every painted pixel must have solid
    neighbours that far around it; when it does not, the pattern slides up to two pixels toward
    the screen point `toward` (e.g. the head's centre). Returns whether anything was painted."""
    ax, ay, ad = cam.project(point)
    h, w = len(rows), max(len(r) for r in rows)
    x0, y0 = int(math.floor(ax - (w - 1) / 2.0)), int(math.floor(ay - (h - 1) / 2.0))
    cells = [(c, r, ch) for r, row in enumerate(rows) for c, ch in enumerate(row) if ch in legend]

    def allowed(x: int, y: int) -> bool:
        if not (1 <= x < fr.W - 1 and 1 <= y < fr.H - 1):
            return False
        p = fr.part[y, x]
        return p >= 0 and fr.groups[p] in on_groups and abs(fr.depth[y, x] - ad) <= tol

    def fits(ox: int, oy: int) -> bool:
        for c, r, _ in cells:
            x, y = ox + c, oy + r
            if not allowed(x, y):
                return False
            for dx in range(-inset, inset + 1):
                for dy in range(-inset, inset + 1):
                    if abs(dx) + abs(dy) != inset or not (0 <= x + dx < fr.W and 0 <= y + dy < fr.H):
                        continue
                    if fr.part[y + dy, x + dx] < 0:
                        return False
        return True

    ox, oy = x0, y0
    if inset:
        tries = [(x0, y0)]
        if toward is not None:
            sx = int(np.sign(round(toward[0] - ax)))
            sy = int(np.sign(round(toward[1] - ay)))
            for k in (1, 2):
                tries += [(x0 + sx * k, y0), (x0, y0 + sy * k), (x0 + sx * k, y0 + sy * k)]
        for tx, ty in tries:
            if fits(tx, ty):
                ox, oy = tx, ty
                break
        else:
            return False
    parts = {ch: fr.add_part(mat, group) for ch, (mat, _) in legend.items()}
    done = False
    for c, r, ch in cells:
        x, y = ox + c, oy + r
        if inset == 0 and not allowed(x, y):
            continue
        fr.part[y, x] = parts[ch]
        fr.idx[y, x] = legend[ch][1]
        fr.fixed[y][x] = None
        done = True
    return done


def _eyes(fr: Frame, cam: Camera, sk: Skeleton, pose: dict[str, Any], big: bool = False) -> None:
    """Small glowing eyes deep in the sockets: a 2-pixel slit each, set one pixel in from the
    head's outline (a lone eye pixel on the edge reads as noise). Brighter in the windup tell."""
    if float(pose.get("eyes", 1.0)) < 0.5:
        return
    glow = float(pose.get("glow", 0.0))
    hot = glow >= 0.9
    centre = cam.project(sk["head"] * SIZE)[:2]
    lo, hi = (2, 3) if hot else ((1, 2) if glow >= 0.5 else (1, 2))
    if big:
        rows = ["ab", "bc"] if not hot else ["aa", "ab"]
        legend = {"a": (EYE, 3), "b": (EYE, 2), "c": (EYE, 1)}
    else:
        rows = ["ab"] if not hot else ["aa"]
        legend = {"a": (EYE, hi), "b": (EYE, lo + 1 if hot else hi)}
    for z in (1.35, -1.35):
        p = head_point(sk, 2.75, 0.8, z * 0.95) * SIZE
        decal(fr, cam, p, rows, legend, HEAD_GROUPS, tol=4.0, inset=1, toward=centre,
              group="eye")


# Lesions: violet rot spots, light in the middle with a dark lower rim (2-3 pixels across).
LESION_ROWS = (".ab", "abc", ".cc")
LESION_LEGEND = {"a": (LESION, 4), "b": (LESION, 3), "c": (LESION, 1)}
LESION_SMALL = ("ab", "bc")


def _lesions(fr: Frame, cam: Camera, sk: Skeleton) -> None:
    """Rot lesions on lit skin: the near upper arm, the near thigh, the near shoulder."""
    tv = _toward_viewer(cam)
    spots = (
        (sk["shoulder_n"] + (sk["elbow_n"] - sk["shoulder_n"]) * 0.42, 2.3, ("arm_n",), LESION_ROWS),
        (sk["hip_n"] + (sk["knee_n"] - sk["hip_n"]) * 0.45, 2.3, ("leg_n",), LESION_SMALL),
        (sk["rib"] + sk.torso @ _v((-1.0, 3.2, 3.6)), 1.4, ("torso",), LESION_SMALL),
    )
    for c, r, groups, rows in spots:
        decal(fr, cam, (c + tv * r) * SIZE, rows, LESION_LEGEND, groups, tol=2.2, group="lesion")


def _maw_glow(fr: Frame, cam: Camera, sk: Skeleton, pose: dict[str, Any]) -> None:
    """The windup tell's open mouth: one solid block of rot-green glow (not a scatter of glowing
    pixels between the fangs)."""
    if float(pose.get("glow", 0.0)) < 0.9:
        return
    jaw = math.radians(float(pose.get("jaw", 10.0)))
    p = head_point(sk, 2.9, -1.55 - 1.0 * math.sin(jaw), 0.0) * SIZE
    decal(fr, cam, p, ("aaa", "bab", ".b."), {"a": (EYE, 3), "b": (EYE, 2)},
          ("maw", "teeth", "jaw", "head"), tol=5.0, group="maw_glow")


# --- Rendering -----------------------------------------------------------------------------------

# Two pixels right of centre: the long arms reach ahead (left), so this centres the body's mass.
CAM_CX = -2.0
# Two pixels above the default: things touching the floor on the near side sit lower on screen
# in the 3/4 view, and they must stay on the second-to-last row (the outline takes the last).
CAM_CY = -2.5
CONTOUR_GAP = 2.5


# Small details that are meant to be one or two pixels (never smoothed away).
DETAIL = ("teeth", "socket", "maw", "lesion", "rib", "cavity", "eye", "maw_glow")
N8 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1))


def despeckle(fr: Frame) -> None:
    """Shading specks: a pixel whose colour none of its 8 neighbours share takes the shade most
    of its same-material neighbours have (kit cleanup only fixes the case where all four direct
    neighbours agree). Thin parts with few same-material neighbours need only two to agree."""
    H, W = fr.H, fr.W
    part, idx = fr.part.copy(), fr.idx.copy()
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            p = part[y, x]
            if p < 0:
                continue
            g = fr.groups[p]
            if fr.mats[p].emissive or g.endswith(DETAIL) or "claw" in g:
                continue
            same, votes, n_mat = False, {}, 0
            for dx, dy in N8:
                q = part[y + dy, x + dx]
                if q < 0 or fr.mats[q] is not fr.mats[p]:
                    continue
                n_mat += 1
                if idx[y + dy, x + dx] == idx[y, x]:
                    same = True
                    break
                votes[idx[y + dy, x + dx]] = votes.get(idx[y + dy, x + dx], 0) + 1
            if same or not votes:
                continue
            best, n = max(votes.items(), key=lambda kv: kv[1])
            if n >= 3 or (n >= 2 and n_mat <= 4):
                fr.idx[y, x] = best


N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))


def seams(fr: Frame) -> None:
    """Splits in the bark shell: where two plates meet, the farther one gets a dark line, so the
    shell reads as a few big pieces. Only the bark side darkens (the skin stays clean)."""
    H, W = fr.H, fr.W
    part, idx, depth = fr.part.copy(), fr.idx.copy(), fr.depth
    plate = np.array([m is PLATE or m is BARK for m in fr.mats] + [False])
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            p = part[y, x]
            if p < 0 or not plate[p]:
                continue
            for dx, dy in N4:
                q = part[y + dy, x + dx]
                if q < 0 or q == p or not plate[q] or fr.groups[q] != fr.groups[p]:
                    continue
                if depth[y, x] > depth[y + dy, x + dx] + 0.25:
                    fr.idx[y, x] = max(0, idx[y, x] - 2)
                    break


_INK_L = to_oklch(INK)[0]


def _clamp_ink(fr: Frame) -> None:
    """No colour darker than the palette's darkest ink (some materials' outline colours are
    near-black)."""
    for y in range(fr.H):
        for x in range(fr.W):
            c = fr.fixed[y][x]
            if c is not None and to_oklch(c)[0] < _INK_L:
                fr.fixed[y][x] = INK


def _finish(fr: Frame) -> np.ndarray:
    """kit.post.finish plus the bark seams, despeckle and ink clamp passes (contours, seams,
    cleanup, despeckle, outline)."""
    contours(fr, CONTOUR_GAP, 2)
    seams(fr)
    cleanup(fr)
    despeckle(fr)
    outline(fr)
    _clamp_ink(fr)
    return fr.rgba()


def _pixel_path(fr: Frame, cam: Camera, pts: list[np.ndarray]) -> list[tuple[int, int, float]]:
    """A model-space polyline as a clean 1-pixel path (no doubled corner pixels), kept inside the
    frame's 1-pixel margin and never below the second-to-last row."""
    proj = [cam.project(p * SIZE) for p in pts]
    samples: list[tuple[float, float, float]] = []
    for (x0, y0, d0), (x1, y1, d1) in zip(proj[:-1], proj[1:]):
        n = int(max(abs(x1 - x0), abs(y1 - y0)) * 4) + 1
        for k in range(n):
            u = k / n
            samples.append((x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, d0 + (d1 - d0) * u))
    samples.append(proj[-1])
    pix: list[tuple[int, int, float]] = []
    for x, y, d in samples:
        px = min(max(int(math.floor(x)), 2), fr.W - 3)
        py = min(max(int(math.floor(y)), 2), fr.H - 2)
        if pix and pix[-1][:2] == (px, py):
            continue
        pix.append((px, py, d))
    clean: list[tuple[int, int, float]] = []
    for i, q in enumerate(pix):
        if clean and i < len(pix) - 1:
            a, b = clean[-1], pix[i + 1]
            if abs(a[0] - b[0]) == 1 and abs(a[1] - b[1]) == 1:
                continue  # an L corner: the diagonal step alone reads cleaner
        clean.append(q)
    return clean


def draw_talons(fr: Frame, cam: Camera, sk: Skeleton, pose: dict[str, Any]) -> None:
    """Draws every talon as a crisp pale hook, 1 pixel wide (2 at the base of the big ones, the
    second pixel on the shadow side), so each hook keeps its own outline at sprite size. Hidden
    where the body is in front, and skipped for a hand the body hides (its talons would float)."""
    for side in ("f", "n"):
        hand = [i for i, g in enumerate(fr.groups) if g == "arm_%s_hand" % side]
        if int(np.isin(fr.part, hand).sum()) < 4:
            continue
        for t, (pts, w) in enumerate(talon_curves(sk, side, pose)):
            part = fr.add_part(BONE, "arm_%s_claw%d" % (side, t))
            path = _pixel_path(fr, cam, pts)
            n = len(path)
            for i, (x, y, d) in enumerate(path):
                fr.put(x, y, part, 3, d - 1.0)
                if w > 1 and i < n * (0.6 if w > 2 else 0.33):
                    # Shadow side: the neighbour toward the lower right of the stroke.
                    j = min(i + 1, n - 1)
                    tx, ty = path[j][0] - path[max(i - 1, 0)][0], path[j][1] - path[max(i - 1, 0)][1]
                    ox, oy = (-ty, tx) if (-ty + tx) > 0 else (ty, -tx)
                    ox, oy = int(np.sign(ox)), int(np.sign(oy))
                    if abs(ox) + abs(oy) == 2:
                        ox, oy = (ox, 0) if abs(tx) < abs(ty) else (0, oy)
                    qx, qy = x + ox, min(y + oy, fr.H - 2)
                    if 2 <= qx < fr.W - 2 and fr.part[qy, qx] != part:
                        fr.put(qx, qy, part, 1, d - 1.0)


def render_frame(pose: dict[str, Any], size: int = S, cam: Camera | None = None) -> Frame:
    """The husk in `pose` as an unfinished Frame (render + talons + decals), for checks and post
    passes."""
    if cam is None:
        cam = Camera(size, size, face="left", cx=CAM_CX, cy=CAM_CY)
    sk = skeleton(pose)
    fr = render(model(pose, sk, talons3d=False), cam)
    _lesions(fr, cam, sk)
    draw_talons(fr, cam, sk, pose)
    _maw_glow(fr, cam, sk, pose)
    _eyes(fr, cam, sk, pose)
    return fr


def render_pose(pose: dict[str, Any], size: int = S, cam: Camera | None = None) -> np.ndarray:
    """One RGBA frame of the husk in `pose` (facing left, feet on the second-to-last row)."""
    return _finish(render_frame(pose, size, cam))


def _framed(size: int, scale: float, point: np.ndarray, at: tuple[float, float]) -> Camera:
    """A left-facing camera that puts model `point` at pixel `at` (x, y)."""
    v = Camera(size, size, scale=scale, face="left").view(point)
    return Camera(size, size, scale=scale, face="left", cx=float(v[0]) - (at[0] - size / 2.0) * scale,
                  cy=float(v[1]) - (size - 0.5 - at[1]) * scale)


PORTRAIT_SCALE = 0.40
PORTRAIT_AT = (24.0, 26.0)


def _cracks(fr: Frame, cam: Camera, sk: Skeleton) -> None:
    """Close-up only: thin bark cracks splitting the dried skin across the scalp and down the
    near cheek."""
    def surface(pts: Sequence[tuple[float, float, float]]) -> list[np.ndarray]:
        out = []
        c = head_point(sk, -0.5, 0.9, 0.0)
        for x, y, z in pts:
            p, _ = _surf(c, (3.6 * HEAD, 3.5 * HEAD, 3.2 * HEAD), sk.head, (x, y, z))
            out.append(p * SIZE)
        return out

    crack = Material(name="husk_crack", colors=list(BARK.colors))
    for pts, idx in (
            (((0.2, 1.0, 0.55), (0.45, 0.8, 0.7), (0.55, 0.55, 0.85), (0.75, 0.3, 0.8)), 0),
            (((0.75, -0.05, 0.9), (0.6, -0.3, 1.0), (0.62, -0.55, 0.95)), 1)):
        line3d(fr, cam, surface(pts), crack, idx, group="crack", depth_bias=0.8)


def render_portrait(pose: dict[str, Any]) -> np.ndarray:
    """48x48 close-up of the head and shoulders (same model, zoomed in), facing left."""
    sk = skeleton(pose)
    cam = _framed(PORTRAIT, PORTRAIT_SCALE, sk["head"] * SIZE, PORTRAIT_AT)
    fr = render(model(pose, sk), cam)
    _cracks(fr, cam, sk)
    # One violet lesion eating into the brow above the near eye.
    decal(fr, cam, head_point(sk, 1.2, 2.7, 1.9) * SIZE, LESION_ROWS, LESION_LEGEND, ("head",),
          tol=3.0, group="lesion")
    _eyes(fr, cam, sk, pose, big=True)
    return _finish(fr)


# Head up a little and turned toward the viewer just enough that both eyes and the fangs show
# while it still clearly faces left; jaw open; arms dropped out of the frame; the bark-plated
# hump fills the corner behind.
PORTRAIT_POSE = blend(POSES["idle"], dict(neck=75.0, head=(-2.0, -30.0, -6.0), jaw=34.0, glow=0.6,
                                          hand_n=(10.0, 6.0, 8.0), hand_f=(12.0, 6.0, -6.0)), 1.0)


def _check(name: str, fr: Frame, rgba: np.ndarray) -> list[str]:
    """Sprite contract: nothing on the top or side edges, the body standing on the
    second-to-last row (the last row is outline only)."""
    a = rgba[..., 3] > 0
    issues = []
    if a[0].any() or a[:, 0].any() or a[:, -1].any():
        issues.append("%s touches the top or side edge" % name)
    if (fr.part[-1] >= 0).any():
        issues.append("%s has body pixels on the last row" % name)
    if not (fr.part[-2] >= 0).any():
        issues.append("%s does not stand on the second-to-last row" % name)
    return issues


# --- Review pictures (preview only, never game files) --------------------------------------------

_BG = (34, 31, 40)


def _on(rgba: np.ndarray, bg: tuple[int, int, int] = _BG) -> np.ndarray:
    """An RGBA picture flattened onto an opaque background."""
    out = np.empty_like(rgba)
    a = rgba[..., 3:4].astype(float) / 255.0
    out[..., :3] = (rgba[..., :3] * a + np.array(bg) * (1.0 - a)).astype(np.uint8)
    out[..., 3] = 255
    return out


def _load(path: str) -> np.ndarray | None:
    try:
        from PIL import Image
        return np.array(Image.open(path).convert("RGBA"))
    except (OSError, ImportError):
        return None


def _review(ctx, frames: list[np.ndarray], por: np.ndarray) -> None:
    from PIL import Image
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    game = os.path.join(os.path.dirname(os.path.dirname(here)), "assets", "sprites")
    sheet = hstack(frames)
    ctx.extra("sheet_1x.png", sheet, scale=1, frame_w=S)
    ctx.extra("sheet_3x.png", sheet, scale=3, frame_w=S)
    # Every frame big, three to a row.
    gap = 2
    grid = np.zeros((2 * S + gap, 3 * S + 2 * gap, 4), dtype=np.uint8)
    grid[..., 3] = 255
    for i, f in enumerate(frames):
        r, c = divmod(i, 3)
        grid[r * (S + gap):r * (S + gap) + S, c * (S + gap):c * (S + gap) + S] = _on(f)
    ctx.extra("frames_5x.png", grid, scale=5)
    # The old placeholder (64 px frames) above the new sheet, on the same baseline.
    old = _load(os.path.join(here, "preview", "_old", "enemies", ID + ".png"))
    if old is not None:
        oh, ow = old.shape[:2]
        rows = np.zeros((S * 2, sheet.shape[1], 4), dtype=np.uint8)
        fw = ow // 6
        for i in range(6):
            rows[S - oh:S, i * S + (S - fw) // 2:i * S + (S - fw) // 2 + fw] = old[:, i * fw:(i + 1) * fw]
        rows[S:] = sheet
        ctx.extra("old_vs_new_3x.png", _on(rows), scale=3)
    # Next to the heroes (idle frames), same pixel density, on a shared floor.
    heroes = [_load(os.path.join(game, "characters", n + ".png")) for n in ("alder", "brin", "cass")]
    heroes = [h for h in heroes if h is not None]
    row = np.zeros((S, 8 + len(heroes) * 40 + 2 * S + 8, 4), dtype=np.uint8)
    x = 8
    for h in heroes:
        if h.shape[0] != HERO_FRAME[1]:  # a grid sheet: its idle key, cropped to the old frame
            px = (HERO_CELL[0] - HERO_FRAME[0]) // 2
            h = h[HERO_CELL[1] - HERO_FRAME[1]:HERO_CELL[1], px:px + HERO_FRAME[0]]
        row[S - h.shape[0]:, x:x + 32] = h[:, :32]
        x += 40
    row[:, x:x + S] = frames[0]
    row[:, x + S:x + 2 * S] = np.maximum(row[:, x + S:x + 2 * S], frames[1])
    ctx.extra("context_heroes_3x.png", _on(row), scale=3)
    # The turn-order row: every portrait at the HUD's 56 px.
    pors = []
    for n in ("alder", "brin", "cass", "bloat", "shade", ID):
        p = por if n == ID else _load(os.path.join(game, "portraits", n + ".png"))
        if p is not None:
            img = Image.fromarray(_on(p)).resize((56, 56), Image.NEAREST)
            pors.append(np.array(img))
    if pors:
        strip = np.zeros((60, len(pors) * 64, 4), dtype=np.uint8)
        strip[..., 3] = 255
        for i, p in enumerate(pors):
            strip[2:58, i * 64 + 4:i * 64 + 60] = p
        ctx.extra("portraits_hud_2x.png", strip, scale=2)


# --- Clips (phase 10) ----------------------------------------------------------------------------
# The review GIFs breathe at game speed: this mirrors idle_cycle_percent in
# data/enemies/rotten_husk.tres (the game's number; change both together).
IDLE_CYCLE_PERCENT = 90
# Row-0 keys by name (an int in a clip is a key cell).
K = {n: i for i, n in enumerate(ENEMY_POSES)}


def _k(name: str, **kw: Any) -> dict[str, Any]:
    """Key pose `name` with some keys changed."""
    p = dict(POSES[name])
    p.update(kw)
    return p


def _mix(a: dict[str, Any], b: dict[str, Any], t: float, **kw: Any) -> dict[str, Any]:
    """An in-between of two poses, with some keys then set by hand."""
    p = blend(a, b, t)
    p.update(kw)
    return p


IDLE, WINDUP, LUNGE, CONTACT, HURT, SLAM = (POSES[n] for n in ENEMY_POSES)

# Breathing out: the hump sinks a hair, the head and arms sway forward and down, the jaw gapes.
BREATH = _k("idle", pelvis=(-10.3, 20.8, 0.0), lean=56.0, side_lean=2.0, head=(-6.0, -28.0, -4.0),
            jaw=34.0, hand_n=(15.5, 11.0, 8.0), hand_f=(19.5, 15.8, -6.0), rag=(0.8, 0.3))

# The coil: sinks and draws the near claw back low, then sweeps it up as the core flares.
COIL_1 = _k("idle", pelvis=(-9.0, 19.6, 0.0), lean=60.0, twist=-4.0, neck=104.0,
            head=(-4.0, -20.0, 0.0), jaw=20.0, glow=0.6,
            hand_n=(-13.0, 21.0, 8.0), elbow_n=(-0.2, -1.0, 0.6), claw_n=(-0.8, -0.6, 0.0),
            hook_n=(1.0, 0.0, 0.0), hand_f=(16.0, 14.5, -6.0), toe_f=8.0)
COIL_2 = _mix(COIL_1, WINDUP, 0.6, hand_n=(-17.0, 38.0, 7.0), elbow_n=(-0.4, 0.6, 0.8),
              claw_n=(-0.2, 1.0, 0.0), hook_n=(1.0, 0.0, 0.0), glow=1.0, jaw=34.0)
# Held: the raised claw trembles, the jaw works, the talons flex.
SHIVER = _k("windup", pelvis=(-7.2, 22.7, 0.0), hand_n=(-11.0, 49.0, 6.5), spread_n=1.75,
            jaw=46.0, head=(-28.0, -12.0, 6.0), hand_f=(14.5, 21.5, -7.0), spread_f=1.55,
            rag=(-1.4, 0.2))

# The lunge: drops forward as the raised claw comes over the top, then reaches out (arriving).
LUNGE_1 = _k("windup", pelvis=(-8.0, 20.5, 0.0), lean=50.0, twist=0.0, side_lean=0.0,
             neck=90.0, head=(-20.0, -14.0, 0.0), jaw=36.0, glow=1.0,
             hand_n=(4.0, 46.0, 7.0), elbow_n=(-0.6, 0.4, 0.8), claw_n=(0.7, 0.7, 0.0),
             hook_n=(0.7, -0.7, 0.0), spread_n=1.5,
             hand_f=(6.0, 16.0, -7.0), foot_n=(7.0, 3.4, 4.6), toe_f=12.0, rag=(-2.0, 0.0))
LUNGE_2 = _mix(LUNGE_1, LUNGE, 0.55, hand_n=(22.0, 36.0, 6.0), claw_n=(1.0, 0.2, 0.0),
               hook_n=(0.3, -1.0, 0.0), foot_n=(9.0, 3.2, 4.6), glow=0.6)

# Follow-through: the claw rakes down and back across the body, then hangs as it settles.
FOLLOW_1 = _k("contact", pelvis=(-13.0, 17.5, 0.0), lean=68.0, twist=55.0, head=(-30.0, -18.0, 0.0),
              jaw=30.0, glow=0.5, hand_n=(27.0, 11.0, 9.0), elbow_n=(-0.2, -1.0, 0.6),
              claw_n=(0.3, -1.0, 0.3), hook_n=(-1.0, -0.3, 0.0), spread_n=1.6,
              hand_f=(-10.0, 18.0, -7.0))
FOLLOW_2 = _k("contact", pelvis=(-12.0, 18.5, 0.0), lean=62.0, twist=35.0, head=(-20.0, -20.0, 0.0),
              jaw=26.0, glow=0.3, hand_n=(19.0, 10.0, 8.0), elbow_n=(-0.6, -0.6, 0.6),
              claw_n=(0.3, -1.0, 0.1), hook_n=(1.0, 0.0, 0.0), spread_n=1.2,
              hand_f=(4.0, 15.0, -7.0), toe_f=12.0, rag=(-1.0, 0.5))

# Tier 2, the other claw (`lunge_b`, `contact_b`, e.g. every second hit of a string): the far
# claw comes over the top and rakes while the near one swings back. It settles into the same
# FOLLOW_2, so recoil and return follow it as they follow the near claw.
LUNGE_B1 = _k("idle", pelvis=(-8.0, 20.5, 0.0), lean=50.0, side_lean=0.0, twist=-14.0, neck=92.0,
              head=(-20.0, -16.0, 0.0), jaw=36.0, glow=0.9,
              hand_f=(0.0, 44.0, -8.0), elbow_f=(-0.6, 0.4, -0.8), claw_f=(0.6, 0.8, 0.0),
              hook_f=(0.7, -0.7, 0.0), spread_f=1.5,
              hand_n=(-6.0, 18.0, 8.0), elbow_n=(0.0, -1.0, 0.6), claw_n=(-0.5, -1.0, 0.0),
              foot_n=(6.0, 3.4, 4.6), toe_f=12.0, rag=(-2.0, 0.0))
LUNGE_B2 = _mix(LUNGE_B1, LUNGE, 0.55, hand_f=(20.0, 34.0, -6.0), claw_f=(1.0, 0.2, 0.0),
                hook_f=(0.3, -1.0, 0.0), spread_f=1.5, hand_n=(-12.0, 16.0, 7.0),
                claw_n=(-0.6, -1.0, 0.0), hook_n=(1.0, 0.0, 0.0), foot_n=(9.0, 3.2, 4.6), glow=0.6)
LUNGE_B3 = _k("lunge", twist=-10.0, hand_f=(29.0, 25.0, -5.0), elbow_f=(-0.4, -1.0, -0.6),
              claw_f=(1.0, -0.3, 0.0), hook_f=(0.0, -1.0, 0.0), spread_f=1.4,
              hand_n=(-14.0, 14.0, 8.0), elbow_n=(0.2, -1.0, 0.6), claw_n=(-0.6, -1.0, 0.0),
              hook_n=(1.0, 0.0, 0.0), spread_n=0.8)
CONTACT_B = _k("contact", twist=10.0, side_lean=3.0, hand_f=(27.0, 25.0, -3.0), elbow_f=(0.0, -1.0, -0.6),
               claw_f=(1.0, -0.7, 0.0), hook_f=(-0.2, -1.0, 0.0), spread_f=1.8,
               hand_n=(-12.0, 15.0, 8.0), elbow_n=(0.2, -1.0, 0.6), claw_n=(-0.6, -1.0, 0.0),
               hook_n=(1.0, 0.0, 0.0), spread_n=0.8)
FOLLOW_B1 = _k("contact", pelvis=(-13.0, 17.5, 0.0), lean=68.0, twist=0.0, head=(-30.0, -18.0, 0.0),
               jaw=30.0, glow=0.5, hand_f=(26.0, 11.0, -6.0), elbow_f=(-0.2, -1.0, -0.6),
               claw_f=(0.3, -1.0, -0.3), hook_f=(-1.0, -0.3, 0.0), spread_f=1.6,
               hand_n=(-6.0, 16.0, 8.0), elbow_n=(0.0, -1.0, 0.6), claw_n=(-0.2, -1.0, 0.0),
               hook_n=(1.0, 0.0, 0.0), spread_n=1.0)

RECOIL_1 = _mix(FOLLOW_2, IDLE, 0.55, pelvis=(-12.0, 21.0, 0.0), lean=50.0)
# Walking back home: a step back with the near foot, then a shuffle with the far one.
RETURN_1 = _mix(FOLLOW_2, IDLE, 0.45, foot_n=(-2.0, 5.5, 4.6), glow=0.0)
RETURN_2 = _mix(FOLLOW_2, IDLE, 0.8, foot_f=(-15.0, 3.8, -4.2), toe_f=14.0, glow=0.0)

# The slam: clods thrown up round the claws while it is down, falling as it starts to rise.
SLAM_DUST = _k("slam", pelvis=(-10.3, 19.9, 0.0), lean=82.0, jaw=42.0, rubble=0.45)
SLAM_RISE = _mix(SLAM, IDLE, 0.3, rubble=0.85, glow=0.3)
SLAM_UP = _mix(SLAM, IDLE, 0.6, glow=0.1)

HURT_1 = _mix(HURT, IDLE, 0.5, eyes=1.0, hand_f=(14.0, 16.0, -7.0), hand_n=(8.0, 22.0, 8.0))
# Stagger: knocked further back a step, then doubled over catching itself.
STAGGER_1 = _k("hurt", pelvis=(-8.0, 20.8, 0.0), lean=-38.0, neck=-30.0, head=(-66.0, -4.0, 22.0),
               jaw=44.0, hand_n=(-18.0, 27.0, 9.0), hand_f=(2.0, 46.0, -8.0),
               foot_n=(-3.0, 2.2, 4.6), foot_f=(-17.0, 2.2, -4.0), toe_n=10.0, toe_f=12.0)
STAGGER_2 = _k("idle", pelvis=(-11.0, 18.5, 0.0), lean=75.0, side_lean=0.0, twist=0.0,
               neck=130.0, head=(-30.0, -20.0, 0.0), jaw=30.0, eyes=1.0,
               hand_n=(6.0, 12.0, 8.0), hand_f=(10.0, 14.0, -6.0),
               foot_n=(2.0, 2.2, 4.6), foot_f=(-18.0, 2.2, -4.4))

# Death (rot): a last throe, the knees buckle as the core goes dark, it folds onto its knees and
# crumbles face down, bark falling off it.
DEATH_1 = _k("hurt", lean=-44.0, neck=-34.0, head=(-70.0, -4.0, 24.0), jaw=48.0,
             hand_n=(-18.0, 38.0, 9.0), hand_f=(16.0, 46.0, -8.0))
DEATH_2 = _k("idle", pelvis=(-9.0, 15.0, 0.0), lean=34.0, side_lean=6.0, twist=0.0, neck=96.0,
             head=(14.0, -20.0, 16.0), jaw=34.0, eyes=0.0, dead=1.0,
             hand_n=(4.0, 6.0, 9.0), elbow_n=(-1.0, 0.0, 0.6), claw_n=(0.0, -1.0, 0.0),
             hand_f=(0.0, 8.0, -7.0), claw_f=(0.0, -1.0, 0.0),
             foot_n=(2.0, 2.2, 4.6), foot_f=(-14.0, 2.2, -4.2), toe_f=0.0)
DEATH_3 = _k("idle", pelvis=(-10.0, 11.0, 0.0), lean=60.0, side_lean=4.0, twist=0.0, neck=120.0,
             head=(20.0, -20.0, 10.0), jaw=30.0, eyes=0.0, dead=1.0,
             hand_n=(14.0, 3.0, 9.0), claw_n=(1.0, -0.4, 0.0), hand_f=(16.0, 4.0, -7.0),
             foot_n=(-12.0, 2.2, 4.4), foot_f=(-14.0, 2.2, -4.4), toe_n=-60.0, toe_f=-60.0,
             crumbs=0.25)
DEATH_4 = _k("idle", pelvis=(-12.0, 11.0, 0.0), lean=100.0, side_lean=4.0, twist=0.0, neck=150.0,
             head=(40.0, -10.0, 20.0), jaw=20.0, eyes=0.0, dead=1.0,
             hand_n=(18.0, 2.5, 9.0), claw_n=(1.0, -0.2, 0.0), hand_f=(8.0, 2.5, -8.0),
             claw_f=(1.0, -0.2, 0.0), foot_n=(-22.0, 2.2, 4.4), foot_f=(-24.0, 2.2, -4.4),
             toe_n=-60.0, toe_f=-60.0, rag=(1.0, 0.0), crumbs=1.0)


def _gait(near_x: float, far_x: float, near_up: float, far_up: float, bob: float, swing: float,
          lean: float = 52.0, pelvis_y: float = 20.8, reach: float = 0.0, **kw: Any) -> dict[str, Any]:
    """A walking or running frame: where each foot is along the ground (and lifted), the body's
    bob, and the arms swinging against the legs (swing +1 = near claw forward; reach moves both
    claws forward and up, as when it runs at its prey)."""
    p = _k("idle", pelvis=(-6.0, pelvis_y + bob, 0.0), lean=lean, side_lean=-3.0 * swing,
           twist=8.0 * swing, neck=100.0, head=(-14.0 - 3.0 * bob, -24.0, -3.0 * swing),
           foot_n=(near_x, 2.2 + near_up, 4.6), foot_f=(far_x, 2.2 + far_up, -4.2),
           knee_n=(1.0, 0.3 if near_up > 0.5 else 0.0, 0.15),
           knee_f=(1.0, 0.3 if far_up > 0.5 else 0.0, -0.15),
           toe_n=14.0 if near_up > 0.5 else 0.0, toe_f=14.0 if far_up > 0.5 else 0.0,
           hand_n=(15.0 + 8.0 * swing + reach, 12.5 + 0.5 * reach, 8.0),
           hand_f=(17.0 - 8.0 * swing + reach, 15.5 + 0.5 * reach, -6.0),
           rag=(-1.5 * swing, 0.0))
    p.update(kw)
    return p


# Two steps per cycle; a foot is planted on cells 0 and 2 (the footstep moments). A step is 18
# design units (about 20 px = the zones' roam stride of 0.9 at 0.045 per px, until phase 26), so the planted
# foot keeps pace with the ground.
WALK = [_gait(6.0, -12.0, 0.0, 0.0, -0.4, -1.0), _gait(-3.0, -4.5, 0.0, 6.0, 0.9, 0.0),
        _gait(-12.0, 6.0, 0.0, 0.0, -0.4, 1.0), _gait(-4.5, -3.0, 6.0, 0.0, 0.9, 0.0)]
# The hunting lope: low and long, claws reaching for the prey, jaw open, eyes lit.
_RUN = dict(lean=68.0, pelvis_y=19.0, reach=3.0, jaw=36.0, glow=0.6, neck=96.0)
CHASE = [_gait(9.0, -15.0, 0.0, 1.5, -0.8, -1.1, **_RUN), _gait(-1.0, -10.0, 0.0, 8.0, 1.2, 0.0, **_RUN),
         _gait(-15.0, 9.0, 1.5, 0.0, -0.8, 1.1, **_RUN), _gait(-10.0, -1.0, 8.0, 0.0, 1.2, 0.0, **_RUN)]

# Clip name -> cells in play order (int = a row-0 key, dict = a pose). The game sets the timing.
CLIPS: dict[str, list[Any]] = {
    "idle": [K["idle"], _mix(IDLE, BREATH, 0.5), BREATH, _mix(IDLE, BREATH, 0.5)],
    "windup": [COIL_1, COIL_2, K["windup"]],
    "windup_hold": [K["windup"], SHIVER],
    "lunge": [LUNGE_1, LUNGE_2, K["lunge"]],
    "contact": [K["contact"], FOLLOW_1, FOLLOW_2],
    "recoil": [RECOIL_1, K["idle"]],
    "return": [RETURN_1, RETURN_2, K["idle"]],
    "slam": [K["slam"], SLAM_DUST, SLAM_RISE],
    "slam_recover": [SLAM_UP, K["idle"]],
    "hurt": [K["hurt"], HURT_1, K["idle"]],
    "stagger": [K["hurt"], STAGGER_1, STAGGER_2, K["idle"]],
    "death": [DEATH_1, DEATH_2, DEATH_3, DEATH_4],
    "walk": WALK,
    "chase": CHASE,
    "lunge_b": [LUNGE_B1, LUNGE_B2, LUNGE_B3],
    "contact_b": [CONTACT_B, FOLLOW_B1, FOLLOW_2],
}


def _render_cell(pose: dict[str, Any]) -> np.ndarray:
    return _finish(render_frame(pose))


def render_cells(poses: Sequence[dict[str, Any]]) -> list[np.ndarray]:
    """Renders many poses, in worker processes when it can (a clip set is about 30 frames)."""
    if len(poses) < 4:
        return [_render_cell(p) for p in poses]
    try:
        from concurrent.futures import ProcessPoolExecutor
        workers = max(1, min(8, (os.cpu_count() or 2) - 2, len(poses)))
        with ProcessPoolExecutor(max_workers=workers) as ex:
            return list(ex.map(_render_cell, poses))
    except (OSError, RuntimeError, ImportError):
        return [_render_cell(p) for p in poses]


def _clip_cells() -> dict[str, list[Any]]:
    """CLIPS rendered: every distinct pose once, in parallel."""
    from kit.clips import _norm
    todo: dict[Any, dict[str, Any]] = {}
    for entries in CLIPS.values():
        for e in entries:
            if isinstance(e, dict):
                todo.setdefault(_norm(e), e)
    done = dict(zip(todo, render_cells(list(todo.values()))))
    return render_clips(CLIPS, lambda p: done[_norm(p)])


def build(ctx) -> None:
    frames = []
    for name in ENEMY_POSES:
        fr = render_frame(POSES[name])
        f = _finish(fr)
        for msg in _check(name, fr, f):
            print("  WARN", msg)
        frames.append(f)
    cells = _clip_cells()
    ctx.save_fighter("sprites/enemies/%s.png" % ID, frames, cells, (S, S), S, ID,
                     preview_ms={"idle": ENEMY_PREVIEW_MS["idle"] * IDLE_CYCLE_PERCENT // 100})
    por = render_portrait(PORTRAIT_POSE)
    ctx.save("sprites/portraits/%s.png" % ID, por)
    _review(ctx, frames, por)
