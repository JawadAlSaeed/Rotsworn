"""Brin, the Reaver: the hero sheet (a grid of 48x56 cells, facing right: row 0 the 8 key poses,
then one row per animation clip) and the 48x48 portrait.

Lean and quick: twin daggers, a red headband whose two tails trail behind the head, spiky dark
hair, a red tunic under a leather vest, wrapped forearms, charcoal trousers, dark boots and a
belt with a pouch.

Phase 10 reuse: `POSES` holds the keyframes as plain dicts (blend them with `kit.rig.blend`),
`model(pose)` builds the SDF model and `render_pose(pose)` returns one RGBA frame. Every keyframe
carries the same keys (`complete()`), so blends never jump. Pose keys on top of
`kit.rig.pose_skeleton`'s:
  dag_n / dag_f   dagger direction (model space, any length) from each hand
  drop            0..1: >= 0.5 the daggers lie on the floor at drop_n / drop_f instead
  drop_n / drop_f (x0, z0, x1, z1): a dropped dagger, grip end to tip, on the floor
  wind            where the headband tails stream (model space; length = how straight)
  tail_len        headband tail length (1 = full)
  root_rot        (rx, ry, rz) degrees: turns the whole posed body about the pelvis (flip, fall)
  root_pos        moves the whole posed body afterwards
  dag_front       1 = the daggers are held in front of everything (drawn on top)
  ground          1 = clip everything below the floor (flat soles), 0 = airborne
  eyes            "open", "wince" or "shut"
Generated in-betweens should pass `frame_ok()` (1 clear pixel on the top, left and right);
`render_fitted(pose)` nudges an in-between sideways when it touches one side.

Clips (phase 10): `CLIPS` names each animation's cells in play order, an int being a row-0 key and
a dict a pose (usually a `blend` of keyframes); `build` renders them in 48x56 cells with the
legacy camera padded by `kit.clips.cell_camera`, so row 0 is pixel for pixel the 32x48 art.
"""
from __future__ import annotations

import dataclasses
import math
import os
from typing import Any

import numpy as np
from PIL import Image

from kit.color import to_oklch
from kit.palette import INK, M, Material
from kit.post import cleanup, contours, outline
from kit.render import Camera, Frame, line3d, render
from kit.clips import cell_camera, render_clips
from kit.rig import Build, Skeleton, blend, pose_skeleton
from kit.sdf import (Box, Capsule, Ellipsoid, Intersect, Node, Prism, RoundCone, SmoothUnion,
                     Sphere, Subtract, Torus, Union, basis, rot)
from kit.sheet import hstack
from kit.specs import HERO_BODY_W, HERO_CELL, HERO_FRAME, HERO_POSES, PORTRAIT

# --- Look -----------------------------------------------------------------------------------------

ACCENT = "#c2453d"
_INK_L = to_oklch(INK)[0]


def _mat(name: str, colors: list[str], **kw: Any) -> Material:
    kw.setdefault("hi", float(len(colors) - 1))
    return _ink_safe(Material(name=name, colors=list(colors), **kw))


def _ink_safe(m: Material) -> Material:
    """A private copy whose outline is never darker than palette.INK (the art bible's darkest)."""
    m = dataclasses.replace(m, colors=list(m.colors))
    if to_oklch(m.outline)[0] < _INK_L:
        m.outline = INK
    return m


MAT: dict[str, Material] = {
    "skin": _ink_safe(M["skin"]),
    # Cool blue-black hair with a clear highlight band, so the spikes read on dark ground.
    "hair": _mat("brin_hair", ["#221d2b", "#2d2839", "#3a3446", "#4f4a62", "#67647e"],
                 spec=0.5, spec_power=8.0, wrap=0.25, hi=3.0, lo=0.5),
    # The accent red, little hue swing: crimson shadows, never peach or magenta.
    "band": _mat("brin_band", ["#5e1a20", "#84252a", "#a83634", ACCENT, "#d0533f"], wrap=0.45, lo=0.6),
    # Four steps on the small torso: fewer one-pixel colour islands.
    "tunic": _mat("brin_tunic", ["#5a1a22", "#7e2629", "#a13832", "#c24a3b"], wrap=0.5, lo=0.4),
    # Dark leather, a step below the tunic's shadows, so the vest reads as its own garment.
    "vest": _mat("brin_vest", ["#271b1b", "#352520", "#463126", "#5b402f", "#73533c"], wrap=0.35, hi=3.4),
    "belt": _ink_safe(M["leather"]),
    "wrap": _mat("brin_wrap", ["#7d6650", "#8f7b62", "#a19174", "#b6a98d", "#c7bea6"], wrap=0.4),
    "wrap_band": _mat("brin_wrap_band", ["#5c4a3c", "#6d5948", "#7d6650"], wrap=0.4),
    "pants": _mat("brin_pants", ["#1f1e2e", "#2c2c3e", "#3c3e50", "#535468", "#67677a"], wrap=0.4),
    "boots": _mat("brin_boot", ["#21171a", "#2f2220", "#3f2e28", "#533f36", "#665046"], wrap=0.3),
    "blade": _ink_safe(M["blade"]),
    "grip": _ink_safe(M["leather"]),
    "guard": _ink_safe(M["gold_worn"]),
    "ink": _mat("brin_ink", ["#241a26", "#3a2f38"]),
    "eye_white": _ink_safe(M["eye_white"]),
    "iris": _mat("brin_iris", ["#5a3520", "#8a5a34", "#b07e48"]),
    "mouth": _mat("brin_mouth", ["#6e2f33", "#8a4a44", "#a0604f"]),
}

# The portrait's skin: the same colours with an extra step between each, dithered where two
# meet, so the light/shadow edge across the face is a soft band instead of a hard line.
_SKIN_P = ["#aa5b52", "#b86c5a", "#c47e62", "#cd8d6a", "#d39a72", "#dcab83", "#e4ba92", "#ecc9a4"]
MAT_PORTRAIT: dict[str, Material] = {
    "skin": _mat("brin_skin_p", _SKIN_P, wrap=0.6, lo=0.6, hi=6.6, ao=0.6),
}

BUILD = Build(
    ankle_h=1.5, shin=8.9, thigh=9.1, spine=9.0, neck=1.6, head_r=5.1,
    shoulder_w=3.8, hip_w=2.0, upper_arm=6.3, forearm=5.9, foot_len=3.3,
)
HIP_Y = BUILD.stand_hip()


def _v(*a: float) -> np.ndarray:
    return np.array(a, dtype=float)


# --- Poses (keyframes) ----------------------------------------------------------------------------

POSES: dict[str, dict[str, Any]] = {
    # Loose stance, daggers low: blades hang out to both sides like an upturned V.
    "idle": {
        "pelvis": (0.0, HIP_Y + 0.2, 0.0), "lean": 3.0, "twist": -14.0, "head": (2.0, 6.0, 0.0),
        "foot_n": (4.0, 1.5, 0.8), "knee_n": (1.0, 0.0, 0.4),
        "foot_f": (-3.6, 1.5, -0.6), "knee_f": (0.2, 0.0, 1.0), "toe_yaw_f": -45.0,
        "hand_n": (-2.4, 15.2, 5.4), "elbow_n": (-1.0, 0.0, 0.6),
        "hand_f": (4.4, 15.4, -4.6), "elbow_f": (-1.0, 0.0, -0.5),
        "dag_n": (-0.45, -1.0, 0.25), "dag_f": (0.5, -1.0, -0.15),
        "wind": (-1.0, -0.4, -0.2), "ground": 1.0, "eyes": "open",
    },
    # Wide low crouch leaning in, both blades up and forward as two diagonals.
    "ready": {
        "pelvis": (-1.0, HIP_Y - 5.6, 0.0), "lean": 32.0, "twist": -10.0, "head": (-22.0, -6.0, 0.0),
        "foot_n": (7.4, 1.5, 2.8), "foot_f": (-8.4, 1.5, -2.2), "toe_f": 15.0,
        "hand_n": (8.5, 15.5, 4.0), "elbow_n": (-1.0, -0.8, 0.6),
        "hand_f": (7.5, 19.5, -2.5), "elbow_f": (-0.6, -1.0, -0.6),
        "dag_n": (0.832, 0.255, -0.493), "dag_f": (0.624, 0.633, -0.458),
        "root_pos": (-3.0, 0.0, 0.0),
        "wind": (-1.0, -0.1, -0.2), "ground": 1.0, "eyes": "open",
    },
    # Braced on a straight back leg, hands pushed forward, blades crossed in an X off the face.
    "parry": {
        "pelvis": (-3.0, HIP_Y - 2.0, 0.0), "lean": -12.0, "head": (14.0, 0.0, 0.0),
        "foot_n": (3.2, 1.5, 2.6), "foot_f": (-9.0, 1.5, -2.2), "toe_f": 15.0,
        "hand_n": (5.6, 25.4, 3.4), "elbow_n": (-0.2, -1.0, 1.0),
        "hand_f": (7.4, 25.6, -4.0), "elbow_f": (0.0, -1.0, -1.0),
        "dag_n": (0.567, 0.696, -0.44), "dag_f": (-0.486, 0.87, 0.085), "dag_front": 1.0,
        "root_pos": (1.2, 0.0, 0.0),
        "wind": (-1.0, 0.0, -0.2), "tail_len": 0.85, "ground": 1.0, "eyes": "wince",
    },
    # Sidestep back to the left: weight over the rear foot, leaning far back, the front leg
    # stretched out straight, a guard blade forward and the far arm flung back.
    "dodge": {
        "pelvis": (-5.0, HIP_Y - 3.2, 0.0), "lean": -34.0, "head": (-4.0, 0.0, 0.0),
        "foot_n": (6.0, 1.5, 2.6), "toe_n": 40.0, "knee_n": (1.0, 0.6, 0.2),
        "foot_f": (-6.0, 1.5, -2.0), "toe_f": 5.0,
        "hand_n": (2.0, 23.0, 5.0), "elbow_n": (-1.0, -0.8, 0.6), "dag_n": (0.85, 0.55, 0.0),
        "hand_f": (-14.0, 15.0, -3.0), "elbow_f": (0.0, 1.0, -0.3), "dag_f": (-0.15, -0.951, 0.27),
        "root_pos": (6.6, 0.0, 0.0),
        "wind": (1.0, 0.55, 0.1), "ground": 1.0, "eyes": "open",
    },
    # Tucked back flip: knees to the chest, head tucked, body turned past horizontal.
    "jump": {
        "pelvis": (0.0, HIP_Y, 0.0), "lean": 30.0, "head": (24.0, 0.0, 0.0),
        "foot_n": (2.4, HIP_Y - 2.0, 2.3), "knee_n": (1.0, 1.0, 0.2), "toe_n": -60.0,
        "foot_f": (1.4, HIP_Y - 3.0, -2.3), "knee_f": (1.0, 1.0, -0.2), "toe_f": -60.0,
        "hand_n": (6.0, HIP_Y + 2.0, 5.0), "dag_n": (0.75, -0.6, 0.1),
        "hand_f": (-6.0, HIP_Y + 4.0, -4.0), "dag_f": (-0.7, 0.7, 0.0),
        "root_rot": (0.0, 0.0, 88.0), "root_pos": (4.8, -4.0, 0.0),
        "wind": (-0.3, -1.0, -0.2), "ground": 0.0, "eyes": "open",
    },
    # Knocked back: arched back, head thrown back a little, rear foot kicked up, arms flung low.
    "hurt": {
        "pelvis": (-0.6, HIP_Y - 1.2, 0.0), "lean": -30.0, "head": (-4.0, 0.0, 6.0),
        "foot_n": (2.8, 1.5, 2.5), "toe_n": 25.0,
        "foot_f": (-4.0, 9.0, -2.0), "knee_f": (1.0, 0.4, -0.1), "toe_f": -20.0,
        "hand_n": (-7.0, 18.0, 5.0), "elbow_n": (-0.6, 0.8, 1.0), "dag_n": (-0.6, -0.8, 0.2),
        "hand_f": (6.0, 24.0, -3.4), "elbow_f": (0.0, -1.0, -0.5), "dag_f": (0.3, 0.95, 0.0),
        "root_pos": (2.8, 0.0, 0.0),
        "wind": (0.8, 0.9, 0.0), "ground": 1.0, "eyes": "wince",
    },
    # Deep lunge: front knee over the toes, rear leg long behind, body pitched in over the
    # front knee, the front blade thrust level, the back blade swept down behind.
    "strike": {
        "pelvis": (-4.4, HIP_Y - 3.4, 0.0), "lean": 42.0, "twist": -12.0, "head": (-26.0, 0.0, 0.0),
        "foot_n": (4.6, 1.5, 2.8), "knee_n": (1.0, 0.2, 0.2),
        "foot_f": (-14.2, 1.5, -2.0), "toe_f": 35.0,
        "hand_n": (5.3, 20.6, 2.0), "elbow_n": (0.0, -1.0, 0.4), "dag_n": (0.883, 0.000, -0.469),
        "hand_f": (-8.6, 17.0, -3.4), "dag_f": (-0.4, -0.9, 0.0),
        "root_pos": (-0.6, 0.0, 0.0),
        "wind": (-1.0, 0.2, -0.1), "ground": 1.0, "eyes": "open",
    },
    # On the near side facing us, head on the floor at the left, knees drawn up, the top arm
    # limp in front, both daggers dropped on the floor. Posed standing, then laid down by
    # root_rot (x of this pose turns toward the viewer, y to the left).
    "down": {
        "pelvis": (0.0, HIP_Y, 0.0), "lean": 28.0, "head": (8.0, -10.0, 14.0),
        "foot_n": (0.5, HIP_Y - 2.5, 2.4), "knee_n": (1.0, 0.6, 0.1), "toe_n": 30.0,
        "foot_f": (1.5, HIP_Y - 3.3, -2.4), "knee_f": (1.0, 0.6, -0.1), "toe_f": 30.0,
        "hand_n": (6.0, HIP_Y + 4.0, 4.5), "elbow_n": (0.0, -1.0, 0.6),
        "hand_f": (5.5, HIP_Y + 1.0, 2.5), "elbow_f": (0.3, 0.0, -1.0),
        "dag_n": (1.0, 0.0, 0.0), "dag_f": (1.0, 0.0, 0.0),
        "drop": 1.0, "drop_n": (-15.2, -3.0, -7.3, -3.0), "drop_f": (9.3, -6.0, 2.3, -2.0),
        "root_rot": (90.0, 30.0, 90.0), "root_pos": (-6.1, 5.4 - HIP_Y, -30.0),
        "wind": (-0.3, -1.0, 0.4), "tail_len": 0.8, "ground": 1.0, "eyes": "shut",
    },
}

POSE_DEFAULTS: dict[str, Any] = {
    "lean": 0.0, "side_lean": 0.0, "twist": 0.0, "hip_yaw": 0.0, "head": (0.0, 0.0, 0.0),
    "toe_n": 0.0, "toe_f": 0.0, "dag_n": (1.0, 0.0, 0.0), "dag_f": (1.0, 0.0, 0.0),
    "drop": 0.0, "drop_n": (0.0, 6.0, 7.0, 6.0), "drop_f": (0.0, -4.0, 7.0, -4.0),
    "dag_front": 0.0, "wind": (-1.0, -0.3, 0.0), "tail_len": 1.0,
    "root_rot": (0.0, 0.0, 0.0), "root_pos": (0.0, 0.0, 0.0), "ground": 1.0, "eyes": "open",
}


def complete(pose: dict[str, Any]) -> dict[str, Any]:
    """The pose with every key spelled out, including the elbow/knee poles and toe turn the rig
    would otherwise derive itself. kit.rig.blend copies a key missing on one side wholesale, so
    keyframes that share all keys blend smoothly (phase 10 in-betweens)."""
    out = dict(POSE_DEFAULTS)
    out.update(pose)
    hip_yaw = float(out["hip_yaw"])
    torso = (rot(0.0, hip_yaw + float(out["twist"]), 0.0)
             @ rot(float(out["side_lean"]), 0.0, -float(out["lean"])))
    hips = rot(0.0, hip_yaw, 0.0)
    for side, sgn in (("n", 1.0), ("f", -1.0)):
        out.setdefault("elbow_" + side, tuple(float(v) for v in torso @ _v(-1.0, -0.2, sgn * 0.5)))
        out.setdefault("knee_" + side, tuple(float(v) for v in hips @ _v(1.0, 0.0, sgn * 0.15)))
        out.setdefault("toe_yaw_" + side, hip_yaw)
    return out


POSES = {name: complete(p) for name, p in POSES.items()}

# The portrait: chest turned toward the viewer so the shoulders frame the face, head turned on
# toward us, headband tails hanging down behind the head.
PORTRAIT_POSE: dict[str, Any] = dict(
    POSES["idle"], hip_yaw=-20.0, twist=0.0, head=(4.0, -12.0, 0.0), lean=0.0,
    hand_n=(-1.0, 14.0, 6.5), hand_f=(1.0, 14.0, -6.5),
    wind=(-0.7, -0.6, 0.25), tail_len=0.9,
)


# --- Skeleton -------------------------------------------------------------------------------------


def skeleton(pose: dict[str, Any]) -> Skeleton:
    """The rig's skeleton, then the whole body turned/moved by root_rot / root_pos."""
    sk = pose_skeleton(BUILD, pose)
    R = rot(*pose.get("root_rot", (0.0, 0.0, 0.0)))
    off = _v(*pose.get("root_pos", (0.0, 0.0, 0.0)))
    pivot = sk["pelvis"].copy()
    for k in list(sk.j):
        sk.j[k] = R @ (sk.j[k] - pivot) + pivot + off
    sk.torso = R @ sk.torso
    sk.head = R @ sk.head
    sk.hips = R @ sk.hips
    sk.root = R  # type: ignore[attr-defined]
    return sk


def _unit(v: Any) -> np.ndarray:
    a = np.asarray(v, dtype=float)
    return a / (np.linalg.norm(a) + 1e-9)


# --- Model ----------------------------------------------------------------------------------------

# Hair spikes in head units (base on the skull, direction, length, base radius): a few long
# jagged points swept up and back (speed), then shorter side tufts.
SPIKES = [
    ((0.40, 0.84, 0.05), (0.40, 1.0, 0.05), 0.50, 0.30),    # front crest, over the brow
    ((0.04, 0.97, 0.0), (-0.40, 1.0, 0.0), 0.74, 0.34),     # crown
    ((-0.46, 0.84, 0.0), (-1.0, 0.70, 0.0), 0.88, 0.35),    # back-top
    ((-0.82, 0.40, 0.04), (-1.0, 0.10, 0.0), 0.84, 0.33),   # back
    ((-0.78, -0.04, 0.10), (-0.85, -0.5, 0.05), 0.62, 0.28),  # nape
    ((-0.12, 0.74, 0.62), (-0.55, 0.75, 0.65), 0.58, 0.28),  # near side
    ((-0.10, 0.76, -0.60), (-0.45, 0.8, -0.65), 0.52, 0.26),  # far side
]
# Fringe locks falling over the front of the band (break its straight line).
FRINGE = [
    ((0.70, 0.70, 0.30), (0.92, 0.44, 0.34), 0.11),
    ((0.80, 0.66, -0.06), (0.99, 0.42, -0.04), 0.10),
]


def head_parts(sk: Skeleton, pose: dict[str, Any], portrait: bool) -> list[Node]:
    b = BUILD
    H = sk.head
    c = sk["head"]
    r = b.head_r

    def P(x: float, y: float, z: float) -> np.ndarray:
        return c + H @ _v(x * r, y * r, z * r)

    out: list[Node] = []
    skin = MAT_PORTRAIT["skin"] if portrait else MAT["skin"]
    face = [
        Ellipsoid(skin, c, (r * 0.92, r * 0.96, r * 0.86), R=H, group="head"),
        # Jaw: broad, with a squarer chin (a lean young man, not a child).
        Ellipsoid(skin, P(0.28, -0.46, 0.0), (r * 0.60, r * 0.50, r * 0.60), R=H, group="head"),
        Ellipsoid(skin, P(0.60, -0.74, 0.0), (r * 0.26, r * 0.22, r * 0.30), R=H, group="head"),
    ]
    if portrait:
        # The nose only shows at portrait size (at sprite size it is lost in the face edge).
        face.append(Ellipsoid(skin, P(0.92, -0.18, -0.04), (r * 0.2, r * 0.22, r * 0.13),
                              R=H @ rot(0, 0, 10), group="head"))
    out.append(SmoothUnion(*face, k=0.6))
    # Ears are their own shapes, so they get a contour against the cheek and hair.
    for zs in (1.0, -1.0):
        out.append(Ellipsoid(skin, P(-0.08, -0.22, 0.86 * zs), (r * 0.19, r * 0.28, r * 0.14),
                             R=H @ rot(0, 0, -8), group="ear"))

    hair = MAT["hair"]
    cap_c = P(-0.10, 0.14, 0.0)
    cap_r = _v(r * 0.98, r * 0.95, r * 0.93)
    cap = Ellipsoid(hair, cap_c, cap_r, R=H, group="hair")
    # Hairline: the face and cheeks stay bare below the band; behind the ears the hair falls to
    # the nape.
    face_cut = Box(hair, P(0.64, -0.50, 0.0), (r * 1.0, r * 0.80, r * 1.4), R=H @ rot(0, 0, -8),
                   group="hair")
    ear_cut = Box(hair, P(0.08, -0.56, 0.0), (r * 0.36, r * 0.58, r * 1.4), group="hair", R=H)
    out.append(Subtract(Subtract(cap, face_cut, k=0.4), ear_cut, k=0.3))
    for k, (base, d, ln, rad) in enumerate(SPIKES):
        p0 = P(*base)
        dd = H @ _unit(d)
        # Alternate groups so a spike passing in front of another gets a contour line.
        out.append(RoundCone(hair, p0, p0 + dd * ln * r, r * rad, r * 0.05, group="hair_%d" % (k % 2),
                             thin=True))
    for a, bb, rad in FRINGE:
        out.append(RoundCone(hair, P(*a), P(*bb), r * rad, r * 0.05, group="fringe", thin=True))

    band = MAT["band"]
    # The band hugs the skull: a thin slice of a shell just outside the hair cap, a little lower
    # at the back.
    half = 0.12 if portrait else 0.15
    shell = Ellipsoid(band, cap_c, cap_r * _v(1.07, 1.0, 1.08), R=H, group="band")
    slab = Box(band, P(0.0, 0.40, 0.0), (r * 2.0, r * half, r * 2.0), R=H @ rot(0, 0, 12), group="band")
    out.append(Intersect(shell, slab))
    knot = P(-1.02, 0.30, 0.10)
    out.append(Sphere(band, knot, r * 0.20, group="band"))
    out.extend(tails(knot, pose, r))
    return out


def tails(knot: np.ndarray, pose: dict[str, Any], r: float) -> list[Node]:
    """Two headband tails: chains that stream along `wind` and droop where the wind is weak."""
    wind = np.asarray(pose.get("wind", (-1.0, -0.3, 0.0)), dtype=float)
    strength = min(float(np.linalg.norm(wind)), 1.5)
    wdir = _unit(wind)
    scale = float(pose.get("tail_len", 1.0))
    out: list[Node] = []
    for i, (length, zoff, phase, rad) in enumerate(((8.0, 0.5, 0.0, 0.62), (6.2, -0.4, 1.7, 0.55))):
        pts = [knot + _v(0.0, 0.0, zoff)]
        n = 4
        for k in range(n):
            u = (k + 1) / n
            droop = (1.0 - strength * 0.6) * u * 0.9
            wave = 0.35 * math.sin(phase + u * 3.4)
            d = _unit(wdir + _v(0.0, -droop, 0.0) + _v(0.0, wave, wave * 0.4) + _v(0, -0.25 * i, 0))
            pts.append(pts[-1] + d * length * scale / n)
        for k in range(n):
            ra = rad * (1.0 - 0.15 * k)
            out.append(RoundCone(MAT["band"], pts[k], pts[k + 1], ra, ra * 0.85, group="tail_%d" % i,
                                 thin=True))
    return out


VEST_CHEST = (3.45, 3.8, 4.3)
VEST_BELLY = (2.95, 3.0, 3.4)
VEST_CAP = (1.55, 1.25, 1.65)
V_OPEN = [(-1.5, 4.8), (1.5, 4.8), (0.6, -4.2), (-0.6, -4.2)]
SLEEVE_R = (1.15, 1.0)


def torso_parts(sk: Skeleton) -> list[Node]:
    t = sk.torso
    hp = sk.hips
    out: list[Node] = []
    chest_c = sk["chest"] + t @ _v(0.0, -2.0, 0.0)
    tunic = SmoothUnion(
        Ellipsoid(MAT["tunic"], chest_c, (2.9, 3.4, 3.6), R=t, group="torso"),
        Ellipsoid(MAT["tunic"], sk["belly"], (2.4, 3.4, 2.8), R=t, group="torso"),
        Ellipsoid(MAT["tunic"], sk["pelvis"] + hp @ _v(0.0, -0.4, 0.0), (2.8, 2.6, 3.1), R=hp, group="torso"),
        k=1.2,
    )
    out.append(tunic)
    # The vest owns the torso's shape: it wraps the back and caps the shoulders, so the red only
    # shows as the sleeves and a narrow V down the front.
    vest = SmoothUnion(
        Ellipsoid(MAT["vest"], chest_c + t @ _v(-0.35, 0.3, 0.0), VEST_CHEST, R=t, group="vest"),
        Ellipsoid(MAT["vest"], sk["belly"] + t @ _v(-0.2, 0.5, 0.0), VEST_BELLY, R=t, group="vest"),
        *[Ellipsoid(MAT["vest"], sk["shoulder_" + s] + t @ _v(-0.2, 0.55, 0.0), VEST_CAP, R=t, group="vest")
          for s in ("n", "f")],
        k=1.0,
    )
    # A narrow V-shaped front opening: the red tunic shows from the collar down to the belt.
    swap = np.stack([t @ _v(0.0, 0.0, 1.0), t @ _v(0.0, 1.0, 0.0), t @ _v(1.0, 0.0, 0.0)], axis=1)
    opening = Prism(MAT["vest"], chest_c + t @ _v(3.2, 0.0, 0.0), V_OPEN, 2.3, R=swap, group="vest")
    out.append(Subtract(vest, opening, k=0.2))
    # Belt, a worn gold buckle and a pouch on the near hip.
    belt_c = sk["pelvis"] + hp @ _v(0.0, 1.5, 0.0)
    out.append(Torus(MAT["belt"], belt_c, 2.75, 0.55, R=t, group="belt"))
    out.append(Box(MAT["guard"], belt_c + t @ _v(2.95, 0.0, 0.25), (0.4, 0.62, 0.75), R=t, group="buckle"))
    out.append(Box(MAT["belt"], belt_c + hp @ _v(0.4, -1.1, 3.0), (0.95, 1.0, 0.6), R=hp, round=0.3,
                   group="pouch"))
    out.append(Capsule(MAT["skin"], sk["chest"], sk["neck"], 1.05, group="neck"))
    # The tunic's collar, a soft roll round the base of the neck.
    out.append(Torus(MAT["tunic"], sk["chest"] + t @ _v(0.25, 0.1, 0.0), 1.45, 0.55, R=t @ rot(0, 0, -12),
                     group="collar"))
    return out


def limb_parts(sk: Skeleton) -> list[Node]:
    out: list[Node] = []
    for s in ("n", "f"):
        sh, el, ha = sk["shoulder_" + s], sk["elbow_" + s], sk["hand_" + s]
        g = "arm_" + s
        out.append(RoundCone(MAT["tunic"], sh, el, *SLEEVE_R, group=g))
        out.append(RoundCone(MAT["wrap"], el, ha, 1.22, 0.98, group=g))
        # Bindings: two darker turns of the wrap, so the forearm reads as wrapped, not gloved.
        fa = ha - el
        fR = basis(np.array([fa[1], -fa[0], 0.0]) if abs(fa[2]) < 0.9 * np.linalg.norm(fa) else _v(1, 0, 0), fa)
        for u, rr in ((0.32, 1.16), (0.68, 1.06)):
            out.append(Torus(MAT["wrap_band"], el + fa * u, rr, 0.24, R=fR, group=g, thin=True))
        out.append(Sphere(MAT["skin"], ha, 1.15, group=g))
        hip, kn, an, to = sk["hip_" + s], sk["knee_" + s], sk["ankle_" + s], sk["toe_" + s]
        g = "leg_" + s
        mid = kn + (an - kn) * 0.45
        out.append(RoundCone(MAT["pants"], hip, kn, 1.95, 1.55, group=g))
        out.append(RoundCone(MAT["pants"], kn, mid, 1.55, 1.45, group=g))
        out.append(RoundCone(MAT["boots"], mid, an, 1.7, 1.45, group=g))
        out.append(RoundCone(MAT["boots"], an, to, 1.45, 1.05, group=g))
    return out


def model(pose: dict[str, Any], sk: Skeleton | None = None, portrait: bool = False) -> Node:
    """The SDF model of Brin in `pose` (daggers and face marks are overlays, see render_pose)."""
    sk = sk or skeleton(pose)
    parts: list[Node] = []
    parts += torso_parts(sk)
    parts += limb_parts(sk)
    parts += head_parts(sk, pose, portrait)
    body: Node = Union(*parts)
    if float(pose.get("ground", 1.0)) >= 0.5:
        # Flat soles on the floor, then a cut that is flat on screen: the camera looks down a
        # little, so a sole nearer the viewer would dip into the last row (the outline's row).
        floor = Box(MAT["boots"], (0.0, 60.0, 0.0), (200.0, 60.0, 200.0))
        cam_R = Camera(*HERO_FRAME).R
        n = cam_R[1, :]
        screen_floor = Box(MAT["boots"], n * 100.0, (300.0, 100.0, 300.0), R=basis(cam_R[0, :], n))
        body = Intersect(Intersect(body, floor), screen_floor)
    return body


# --- Overlays: daggers and face -------------------------------------------------------------------

BLADE_TIP = 10.0  # hand -> blade tip, model units (grip 1.6 behind the hand, guard at 1.3)


def _dagger(frame: Frame, cam: Camera, h: np.ndarray, d: np.ndarray, g: str, front: bool,
            lift) -> None:
    """One dagger held at `h` pointing along `d`: leather grip, gold guard, steel blade."""
    side = np.cross(d, _v(0.0, 0.0, 1.0))
    if np.linalg.norm(side) < 0.3:
        side = np.cross(d, _v(0.0, 1.0, 0.0))
    side = _unit(side)
    base = h + d * 1.3
    tip = h + d * BLADE_TIP
    line3d(frame, cam, lift([h - d * 1.6, base - d * 0.3]), MAT["grip"], 1, group=g, always=front)
    line3d(frame, cam, lift([base - side * 1.1, base + side * 1.1]), MAT["guard"], 2, group=g, always=front)
    line3d(frame, cam, lift([base + d * 0.4, tip]), MAT["blade"], [3], group=g, always=front)


def _dropped_dagger(frame: Frame, cam: Camera, ends: list[np.ndarray], g: str) -> None:
    """A dagger lying on the floor from grip end to tip, drawn only where it keeps a pixel of
    clear floor between itself and the body (so it reads as its own object)."""
    a, b = ends
    length = float(np.linalg.norm(b - a))
    body = frame.part >= 0
    pix: dict[tuple[int, int], tuple[Material, int]] = {}
    for k in range(int(length * 4) + 1):
        u = k / max(1, int(length * 4))
        x, y, _ = cam.project(a + (b - a) * u)
        xi, yi = int(math.floor(x)), int(math.floor(y))
        along = u * length
        mat, idx = ((MAT["grip"], 1) if along < 2.2 else (MAT["guard"], 2) if along < 3.0
                    else (MAT["blade"], 3))
        pix.setdefault((xi, yi), (mat, idx))
    parts: dict[str, int] = {}
    for (x, y), (mat, idx) in pix.items():
        if not (1 <= x < frame.W - 1 and 1 <= y < frame.H - 1):
            continue
        if body[y - 1:y + 2, x - 1:x + 2].any():
            continue
        if mat.name not in parts:
            parts[mat.name] = frame.add_part(mat, g)
        frame.put(x, y, parts[mat.name], idx, -np.inf)


def dagger_lines(frame: Frame, cam: Camera, sk: Skeleton, pose: dict[str, Any]) -> None:
    """Twin daggers as crisp 1-pixel lines, in the hands or dropped on the floor."""
    R = getattr(sk, "root", np.eye(3))
    grounded = float(pose.get("ground", 1.0)) >= 0.5
    up = cam.R[1, :]

    def lift(pts: list[np.ndarray]) -> list[np.ndarray]:
        # Lines are not clipped like the model: keep a blade on the floor off the outline row.
        if not grounded:
            return pts
        return [p + up * max(0.0, 0.6 - float(cam.view(p)[1])) for p in pts]

    front = float(pose.get("dag_front", 0.0)) >= 0.5  # held up in front of everything
    for s in ("n", "f"):
        g = "dagger_" + s
        if float(pose.get("drop", 0.0)) >= 0.5:
            x0, z0, x1, z1 = pose.get("drop_" + s)
            _dropped_dagger(frame, cam, lift([_v(x0, 0.0, z0), _v(x1, 0.0, z1)]), g)
            continue
        _dagger(frame, cam, sk["hand_" + s], R @ _unit(pose.get("dag_" + s, (1.0, 0.0, 0.0))), g,
                front, lift)


# Sprite eyes per expression: (near eye rows, far eye rows); "e" = ink.
EYE_SPRITE = {
    "open": (["e", "e"], ["e", "e"]),
    "wince": (["e"], ["e"]),
    "shut": (["ee"], ["ee"]),
}


def _paint_on_face(frame: Frame, cam: Camera, anchor: np.ndarray, rows: list[str], mat: Material,
                   idx: int, shift: int = 0) -> int:
    """Like kit.render.stamp, but only onto pixels of the face (an eye never spills off the head
    or onto hair, band or hands). `shift` moves it along the row in pixels. Returns how many
    pixels it painted."""
    ax, ay, ad = cam.project(anchor)
    x0, y0 = int(math.floor(ax)) + shift, int(math.floor(ay))
    part = frame.add_part(mat, "face_mark")
    n = 0
    for r_, row in enumerate(rows):
        for c_, ch in enumerate(row):
            x, y = x0 + c_, y0 + r_
            if ch != "e" or not (0 <= x < frame.W and 0 <= y < frame.H):
                continue
            p = frame.part[y, x]
            if p < 0 or frame.groups[p] != "head" or frame.depth[y, x] < ad - 4.0:
                continue
            frame.part[y, x] = part
            frame.idx[y, x] = idx
            frame.depth[y, x] = ad - 1.0
            n += 1
    return n


def _face_edge(frame: Frame, y: int, x0: int) -> int:
    """The last face pixel going right from x0 on row y (the face's front edge)."""
    x = x0
    while x + 1 < frame.W and frame.part[y, x + 1] >= 0 and frame.groups[frame.part[y, x + 1]] == "head":
        x += 1
    return x


def _transpose(rows: list[str]) -> list[str]:
    w = max(len(r) for r in rows)
    return ["".join(r[i] if i < len(r) else "." for r in rows) for i in range(w)]


def face_marks(frame: Frame, cam: Camera, sk: Skeleton, pose: dict[str, Any]) -> None:
    """1-2 pixel eyes on the sprite's face, set back from the shaded front edge so they read;
    both eyes with a pixel of skin between them when the head is turned enough to show both."""
    r = BUILD.head_r
    H = sk.head
    c = sk["head"]
    near, far = EYE_SPRITE.get(str(pose.get("eyes", "open")), EYE_SPRITE["open"])
    # A head lying on its side has its eye line upright on screen: turn the marks with it.
    across = cam.R @ (H @ _v(0.0, 0.0, 1.0))
    if abs(across[1]) > abs(across[0]):
        near, far = _transpose(near), _transpose(far)
    a_near = c + H @ _v(0.80 * r, 0.0, 0.46 * r)
    a_far = c + H @ _v(0.88 * r, 0.0, -0.24 * r)
    pn, pf = cam.project(a_near), cam.project(a_far)
    if abs(across[1]) > abs(across[0]):
        _paint_on_face(frame, cam, a_near, near, MAT["ink"], 0)
        # Keep a pixel of skin between the eyes, or they melt into one dark blot.
        if abs(math.floor(pf[1]) - math.floor(pn[1])) - len(near) >= 1:
            _paint_on_face(frame, cam, a_far, far, MAT["ink"], 0)
        return
    # Facing sideways: the far eye one pixel in from the face's front edge (so it does not melt
    # into the outline), the near eye two pixels behind it (one pixel of skin between them).
    xn, xf, y = math.floor(pn[0]), math.floor(pf[0]), math.floor(pn[1])
    edge = _face_edge(frame, y, xn) if 0 <= y < frame.H else xf
    xf = min(xf, edge - 1)
    xn = min(xn, xf - 1 - len(near[0]))
    _paint_on_face(frame, cam, a_near, near, MAT["ink"], 0, shift=xn - math.floor(pn[0]))
    if xf - xn - len(near[0]) >= 1 and xf > xn:
        _paint_on_face(frame, cam, a_far, far, MAT["ink"], 0, shift=xf - math.floor(pf[0]))


# --- Clean-up passes -----------------------------------------------------------------------------

KEEP_GROUPS = ("face_mark", "dagger_n", "dagger_f", "buckle")


def merge_islands(frame: Frame) -> None:
    """A shading pixel whose colour none of its 8 neighbours share takes the most common shade of
    its own material around it (cuts speckle on the small torso). Marks and lines are kept."""
    H, W = frame.H, frame.W
    part, idx = frame.part.copy(), frame.idx.copy()
    for y in range(H):
        for x in range(W):
            p = part[y, x]
            if p < 0 or frame.groups[p] in KEEP_GROUPS or frame.groups[p].startswith("face_"):
                continue
            mat = frame.mats[p]
            col = mat.colors[idx[y, x]]
            votes: dict[int, int] = {}
            lonely = True
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if not (dx or dy):
                        continue
                    nx, ny = x + dx, y + dy
                    if not (0 <= nx < W and 0 <= ny < H) or part[ny, nx] < 0:
                        continue
                    q = part[ny, nx]
                    if frame.mats[q].colors[idx[ny, nx]] == col:
                        lonely = False
                        break
                    if frame.mats[q].name == mat.name:
                        votes[idx[ny, nx]] = votes.get(idx[ny, nx], 0) + 1
                if not lonely:
                    break
            if lonely and votes:
                frame.idx[y, x] = max(sorted(votes), key=lambda i: votes[i])


def vest_edge(frame: Frame) -> None:
    """The vest's edge along the front opening one step lighter (worn leather catching light),
    so the vest and the red tunic part cleanly."""
    H, W = frame.H, frame.W
    lit = []
    for y in range(H):
        for x in range(W):
            p = frame.part[y, x]
            if p < 0 or frame.groups[p] != "vest":
                continue
            for dx, dy in ((1, 0), (-1, 0)):
                nx = x + dx
                if 0 <= nx < W and frame.part[y, nx] >= 0 and frame.groups[frame.part[y, nx]] == "torso":
                    lit.append((y, x))
                    break
    for y, x in lit:
        m = frame.mats[frame.part[y, x]]
        frame.idx[y, x] = min(m.top(), frame.idx[y, x] + 1)


def finish_frame(frame: Frame, contour_gap: float = 2.5) -> np.ndarray:
    """kit.post.finish plus this module's passes: contours, clean-up, island merge, vest edge,
    outline (outline colours are never darker than INK, see _ink_safe)."""
    contours(frame, contour_gap, 2)
    cleanup(frame)
    vest_edge(frame)
    merge_islands(frame)
    outline(frame)
    return frame.rgba()


def frame_ok(rgba: np.ndarray) -> bool:
    """The sprite contract: a clear top row, left and right column (room for the outline)."""
    s = rgba[..., 3] > 0
    return not (s[0, :].any() or s[:, 0].any() or s[:, -1].any())


# --- Rendering ------------------------------------------------------------------------------------


def render_pose(pose: dict[str, Any], cam: Camera | None = None) -> np.ndarray:
    """One 32x48 RGBA frame of Brin in `pose` (any blend of POSES)."""
    cam = cam or Camera(*HERO_FRAME)
    sk = skeleton(pose)
    frame = render(model(pose, sk), cam)
    dagger_lines(frame, cam, sk, pose)
    face_marks(frame, cam, sk, pose)
    return finish_frame(frame)


def render_fitted(pose: dict[str, Any], tries: int = 4) -> np.ndarray:
    """render_pose, nudging the whole body sideways (root_pos x) when a generated in-between
    touches the left or right frame edge. Leaves it as is when both sides overflow."""
    pose = dict(pose)
    rgba = render_pose(pose)
    for _ in range(tries):
        s = rgba[..., 3] > 0
        left, right = bool(s[:, 0].any()), bool(s[:, -1].any())
        if left == right:
            break
        cols = np.nonzero(s.any(axis=0))[0]
        need = (1 - cols[0]) if left else (rgba.shape[1] - 2 - cols[-1])
        x, y, z = pose.get("root_pos", (0.0, 0.0, 0.0))
        pose["root_pos"] = (x + need / 0.88, y, z)
        rgba = render_pose(pose)
    return rgba


# Portrait face marks in pixels, placed around the projected eyes, nose tip and mouth. Keys:
# k lash ink, w eye white, h catch-light, i iris, p pupil, l lower lid, b brow, n nose shadow,
# m mouth, e ear shadow. Each entry: (rows, origin column, origin row).
P_EYE_NEAR = ([
    ".kkkkk",
    "kwwIpk",
    ".wwiik",
    "..lll.",
], 2, 1)
P_EYE_FAR = ([
    "kkk",
    "Ipk",
    "iik",
], 1, 1)
P_BROW_NEAR = ([
    "bbbb..",
    "..bbbb",
], 2, 4)
P_BROW_FAR = ([
    "..bb",
    "bbb.",
], 1, 4)
P_NOSE = ([
    ".n",
    "nn",
], 1, 0)
P_MOUTH = ([
    "....m",
    ".mmm.",
], 2, 1)
P_EAR = ([
    "e",
    "e",
], 0, 0)


def _pix(frame: Frame, x: int, y: int, part: int, idx: int, depth: float) -> None:
    if 0 <= x < frame.W and 0 <= y < frame.H and frame.part[y, x] >= 0:
        frame.part[y, x] = part
        frame.idx[y, x] = idx
        frame.depth[y, x] = depth
        frame.fixed[y][x] = None


def portrait_face(frame: Frame, cam: Camera, sk: Skeleton) -> None:
    """A real face at portrait size: whites, irises, catch-lights, brows, nose and mouth, drawn
    in pixels around where the 3D head puts each feature (only onto the model, never outside)."""
    r = BUILD.head_r
    H = sk.head
    c = sk["head"]

    def at(x: float, y: float, z: float) -> tuple[int, int]:
        px, py, _ = cam.project(c + H @ _v(x * r, y * r, z * r))
        return int(math.floor(px)), int(math.floor(py))

    skin_p = MAT_PORTRAIT["skin"]
    legend = {
        "k": (MAT["ink"], 0), "w": (MAT["eye_white"], 0), "h": (MAT["eye_white"], 1),
        "i": (MAT["iris"], 1), "I": (MAT["iris"], 2), "p": (MAT["ink"], 0), "b": (MAT["hair"], 0), "l": (skin_p, 2),
        "m": (MAT["mouth"], 0), "n": (skin_p, 1), "e": (skin_p, 1),
    }
    parts = {ch: frame.add_part(mat, "face_" + ch) for ch, (mat, _) in legend.items()}
    near = at(0.84, -0.06, 0.36)
    far = at(0.86, -0.06, -0.38)
    nose = at(1.02, -0.36, -0.06)
    mouth = at(0.86, -0.62, 0.04)
    ear = at(-0.06, -0.26, 1.0)
    for (rows, ox, oy), (ax, ay) in ((P_EYE_NEAR, near), (P_EYE_FAR, far), (P_BROW_NEAR, near),
                                      (P_BROW_FAR, far), (P_NOSE, nose), (P_MOUTH, mouth),
                                      (P_EAR, ear)):
        for ry, row in enumerate(rows):
            for rx, ch in enumerate(row):
                if ch in legend:
                    _pix(frame, ax + rx - ox, ay + ry - oy, parts[ch], legend[ch][1], -1e3)


def portrait_camera(sk: Skeleton, s: float = 0.335, col: float = 24.0, row: float = 22.0) -> Camera:
    """The sprite's camera angle, closer, with the head centre on pixel (col, row)."""
    hv = Camera(PORTRAIT, PORTRAIT, scale=s).view(sk["head"])
    return Camera(PORTRAIT, PORTRAIT, scale=s, cx=float(hv[0]) - (col - PORTRAIT / 2.0) * s,
                  cy=float(hv[1]) - (PORTRAIT - 0.5 - row) * s)


def ear_edge(frame: Frame) -> None:
    """The ear's rim where it meets the cheek one step darker, so the ear reads as its own shape
    (it sits at about the cheek's depth, so the usual contour pass leaves it out)."""
    H, W = frame.H, frame.W
    rim = []
    for y in range(H):
        for x in range(W):
            p = frame.part[y, x]
            if p < 0 or frame.groups[p] != "ear":
                continue
            for dx, dy in ((1, 0), (0, -1), (1, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and frame.part[ny, nx] >= 0                         and frame.groups[frame.part[ny, nx]] == "head":
                    rim.append((y, x))
                    break
    for y, x in rim:
        frame.idx[y, x] = max(0, frame.idx[y, x] - 2)


NECK_LIFT = 0.9  # portrait only, model units


def render_portrait() -> np.ndarray:
    """48x48 head and shoulders: the same model, closer, with a face drawn at full size."""
    pose = complete(PORTRAIT_POSE)
    sk = skeleton(pose)
    # Seen this close the neck needs a little more length, or the chin sits on the collar.
    lift = sk.torso @ _v(0.0, NECK_LIFT, 0.0)
    sk.j["neck"] = sk["neck"] + lift
    sk.j["head"] = sk["head"] + lift
    cam = portrait_camera(sk)
    frame = render(model(pose, sk, portrait=True), cam, ss=3)
    ear_edge(frame)
    portrait_face(frame, cam, sk)
    return finish_frame(frame, contour_gap=3.0)


def _old_vs_new(old_path: str, new: np.ndarray) -> np.ndarray | None:
    """The placeholder above the new art (same size) for review; None if it is missing."""
    try:
        old = np.asarray(Image.open(old_path).convert("RGBA"))
    except OSError:
        return None
    if old.shape[1] != new.shape[1]:
        return None
    gap = np.zeros((2, new.shape[1], 4), dtype=np.uint8)
    return np.concatenate([old, gap, new], axis=0)


# --- Clips (phase 10) -----------------------------------------------------------------------------

# Breathing: the out-breath end of each stance loop (key, half-way, out-breath, half-way). The
# body sinks a little on bent knees, the blades dip and the headband tails drop; the head moves at
# most 1 px from the key, because the game measures its head and popup anchors on cell 0 only.
BREATH_OUT: dict[str, dict[str, Any]] = {
    "idle": complete(dict(
        POSES["idle"], pelvis=(0.0, HIP_Y + 0.2 - 0.8, 0.0), lean=3.5, head=(2.5, 6.0, 0.0),
        hand_n=(-2.5, 14.6, 5.4), hand_f=(4.35, 14.8, -4.6), wind=(-1.0, -0.6, -0.1))),
    "ready": complete(dict(
        POSES["ready"], pelvis=(-1.0, HIP_Y - 5.6 - 0.9, 0.0), lean=33.0, head=(-22.0, -6.0, 0.0),
        hand_n=(8.5, 14.7, 4.0), hand_f=(7.5, 18.7, -2.5), wind=(-1.0, -0.3, -0.1))),
}


def _breath(stance: str, t: float) -> dict[str, Any]:
    return blend(POSES[stance], BREATH_OUT[stance], t)


# Clip name -> cells in play order (int = a row-0 key, dict = a pose). The game sets the timing.
CLIPS: dict[str, list[Any]] = {
    "idle": [HERO_POSES.index("idle"), _breath("idle", 0.5), _breath("idle", 1.0), _breath("idle", 0.5)],
    "ready": [HERO_POSES.index("ready"), _breath("ready", 0.5), _breath("ready", 1.0), _breath("ready", 0.5)],
}


def build(ctx) -> None:
    cam = cell_camera(Camera(*HERO_FRAME), HERO_CELL)
    keys = [render_pose(POSES[name], cam) for name in HERO_POSES]
    cells = render_clips(CLIPS, lambda p: render_pose(p, cam))
    bad = [name for name, f in zip(HERO_POSES, keys) if not frame_ok(f)]
    bad += sorted({name for name, cs in cells.items() for c in cs
                   if isinstance(c, np.ndarray) and not frame_ok(c)})
    if bad:
        raise ValueError("brin: frames touch the frame edge (no outline room): %s" % ", ".join(bad))
    ctx.save_fighter("sprites/characters/brin.png", keys, cells, HERO_CELL, HERO_BODY_W, "brin")
    portrait = render_portrait()
    ctx.save("sprites/portraits/brin.png", portrait)
    # Review pictures of the key poses at the old frame size: actual size, 2x, and next to the
    # old placeholder (the cells crop back to the 32x48 frames exactly).
    px = (HERO_CELL[0] - HERO_FRAME[0]) // 2
    sheet = hstack([k[HERO_CELL[1] - HERO_FRAME[1]:, px:px + HERO_FRAME[0]] for k in keys])
    ctx.extra("sheet_1x.png", sheet, scale=1, frame_w=HERO_FRAME[0])
    ctx.extra("sheet_2x.png", sheet, scale=2, frame_w=HERO_FRAME[0])
    ctx.extra("portrait_1x.png", portrait, scale=1)
    ctx.extra("portrait_hud.png", portrait, scale=5)
    old_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "preview", "_old")
    cmp_sheet = _old_vs_new(os.path.join(old_dir, "characters", "brin.png"), sheet)
    if cmp_sheet is not None:
        ctx.extra("old_vs_new_sheet.png", cmp_sheet, scale=3, frame_w=HERO_FRAME[0])
