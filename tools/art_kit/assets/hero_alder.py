"""Alder, the Warden (the tank): hero sheet (8 poses) and portrait.

A broad, warm, sturdy protector: big steel pauldrons, breastplate and rerebraces over a blue
tabard, brown leather belt and boots, short brown hair and a full beard, a LARGE heater shield on
the near arm (deep-blue field, worn-gold rim, a bright gold alder leaf) which is Alder's only
weapon, and a big travel backpack (grey-olive canvas pack, leather flap, an oxblood bedroll
strapped on top, a strap over the near pauldron).

Phase 10 reuses this module: POSES holds the keyframes (plain dicts, blend them with
kit.rig.blend), model(pose) builds the SDF model and render_pose(pose) renders one frame.
CLIPS (end of the file) names every Tier 1 animation (plan 4.1) as cells in play order: an int is a
row-0 key, a dict a pose (a keyframe from P() or an in-between from mix()). build() renders them in
48x56 cells with the 32x48 camera padded (kit.clips.cell_camera), so row 0 stays the phase 9 art.
No sword: strike is a shield shove, strike_alt an upward rim swipe, strike_big a two-hand shield
slam, cast the shield raised overhead on a braced stance. The shield always hangs from the near
hand (only the down pose drops it) and the backpack is part of the torso, so it shows in every cell.

Pose keys on top of kit.rig.pose_skeleton's:
- hip_lean: degrees the hips and skirt tip with the body (default a third of `lean`).
- shield_n, shield_up: the shield's face normal and its top direction (world vectors).
- shield_off: (x, y) offset of the shield centre from the near hand, in the shield's plane.
- shield_at, shield_drop: world position of the dropped shield (down) and how far (0..1) the
  shield has moved from the hand to it.
- shield_push: extra distance of the shield out along its face normal (default 0).
- head_fwd, head_up, head_aim: world vectors that aim the head directly (face direction, top of
  the head) and how much (0..1) they replace the `head` angles (the lying pose uses them).
Every pose carries every key (see _complete), so kit.rig.blend never borrows a key from the
other pose.
- eyes: 0 open, 1 squeezed shut (hurt), 2 closed (down). Numbers so poses stay blendable.
`side_lean` (kit.rig) rolls the upper body about the spine when it lies flat (down); the hips
roll with it here. Head yaw in poses is relative: HEAD_YAW turns every face a little toward the
camera so the face reads in the 3/4 view.
"""
from __future__ import annotations

import math
import os
from typing import Any

import numpy as np

from kit import specs
from kit.clips import cell_camera, render_clips
from kit.palette import INK, M, Material
from kit.post import cleanup, contours, outline
from kit.render import Camera, Frame, line3d, render, stamp
from kit.rig import Build, Skeleton, blend, pose_skeleton
from kit.sdf import (Box, Custom, Cylinder, Ellipsoid, Intersect, Node, Prism, RoundCone, SmoothUnion,
                     Sphere, Subtract, Torus, Union, rot)
from kit.sheet import hstack

# --- Materials --------------------------------------------------------------------------------

BROWN_INK = "#2b1a12"   # outline for worn gold (a brown ink, not a red halo)

MAT: dict[str, Material] = {
    # Skin and hair shadows stay brown (no mauve or maroon in the darkest steps).
    "skin": Material.make("alder_skin", "#d39a72", wrap=0.5, ao=0.5, shadow_shift=5.0, shadow_chroma=0.95,
                          outline="#3f2117"),
    "hair": Material.make("alder_hair", "#6e3b22", wrap=0.3, light_chroma=1.0, light_shift=4.0,
                          shadow_shift=3.0, shadow_chroma=0.8, outline="#22110b"),
    "hair_hi": Material.make("alder_hair_hi", "#6e3b22", wrap=0.3, light_chroma=1.0, light_shift=4.0,
                             shadow_shift=3.0, shadow_chroma=0.8, lo=1.5, outline="#22110b"),
    "mouth": Material.make("alder_mouth", "#7a3f34", wrap=0.3, outline="#3f2117"),
    # Navy-grey shadows, not violet.
    "tabard": Material.make("alder_tabard", "#34508c", wrap=0.4, hi=3.3, shadow_shift=4.0, shadow_chroma=0.75),
    # A neutral steel with a near-white glint so the metal pops against all the blue.
    "steel": Material("alder_steel", ["#555565", "#6c717f", "#878e98", "#a4acb3", "#bbc3c8", "#d7dcdf"],
                      hi=4.0, spec=1.0, spec_power=14.0, wrap=0.15),
    "gold": Material("alder_gold", list(M["gold_worn"].colors), spec=0.6, wrap=0.2, outline=BROWN_INK),
    # The emblem uses only the brightest gold so it stands off the deep-blue field by value.
    "emblem": Material("alder_emblem", ["#ae7c2a", "#c0994d", "#d2b56e", "#eacf96"], lo=1.3, hi=3.0,
                       spec=0.4, wrap=0.35, outline=BROWN_INK),
    "leather": M["leather"],
    "leather_dark": M["leather_dark"],
    "pants": M["cloth_charcoal"],
    "canvas": Material.make("alder_canvas", "#76745f", wrap=0.4),
    "wool": Material.make("alder_bedroll", "#874240", wrap=0.4, shadow_shift=6.0, shadow_chroma=0.9),
    "stripe": M["cloth_cream"],
    # Deep-blue field: mid tone about L* 40, Alder's accent #5b7fbf as the lit step.
    "field": Material("alder_field", ["#171f4e", "#2a3d74", "#3e5c9c", "#5b7fbf", "#7199d4"], lo=0.5,
                      spec=0.15, wrap=0.35),
    "wood": M["wood_dark"],
    "ink": Material("alder_ink", [INK]),
    "eye": M["eye_white"],
    "iris": Material.make("alder_iris", "#4f6f9f", wrap=0.3),
    "blush": Material.make("alder_blush", "#d4846c", wrap=0.45, shadow_shift=5.0),
}

# --- Proportions ------------------------------------------------------------------------------

B = Build(ankle_h=1.5, shin=9.2, thigh=9.2, spine=10.8, neck=1.4, head_r=5.4, shoulder_w=6.0,
          hip_w=2.5, upper_arm=6.6, forearm=6.2, foot_len=3.8)
HIP = B.stand_hip()
CH = HIP + B.spine      # chest height when standing straight
AH = B.ankle_h
HEAD_YAW = -20.0
HAIR_OFF = 0.4          # hair shell thickness over the skull
BEARD_OFF = 0.45        # beard shell thickness over the jaw
PAULDRON = (3.6, 2.6, 3.2)
ROLL_R = 1.65           # bedroll radius and half length
ROLL_HALF = 3.6


def _v(x: Any) -> np.ndarray:
    return np.asarray(x, dtype=float)


def _unit(x: Any) -> np.ndarray:
    v = _v(x)
    return v / (np.linalg.norm(v) + 1e-9)


def frame_nu(normal: Any, up: Any) -> np.ndarray:
    """Rotation whose local z is `normal` and local y as close to `up` as possible."""
    z = _unit(normal)
    y = _v(up) - z * float(np.dot(_v(up), z))
    if np.linalg.norm(y) < 1e-6:
        y = np.array([0.0, 1.0, 0.0]) - z * z[1]
    y = _unit(y)
    x = np.cross(y, z)
    return np.stack([x, y, z], axis=1)


def _frame_y(top: np.ndarray, bot: np.ndarray, fwd: np.ndarray) -> np.ndarray:
    """Rotation whose local y runs from bot to top and local x leans toward fwd."""
    y = _unit(top - bot)
    x = _unit(fwd - y * float(np.dot(fwd, y)))
    return np.stack([x, y, np.cross(x, y)], axis=1)


# --- Shield -----------------------------------------------------------------------------------

SHIELD_POLY = [(-6.0, 7.4), (0.0, 8.0), (6.0, 7.4), (6.0, 1.5), (5.4, -2.6), (4.0, -5.8),
               (2.1, -8.0), (0.0, -9.3), (-2.1, -8.0), (-4.0, -5.8), (-5.4, -2.6), (-6.0, 1.5)]
SHIELD_BEND = 0.05


def _leaf_poly(h: float = 5.0, w: float = 3.2, y0: float = 0.3, stem: float = 1.2) -> list[tuple[float, float]]:
    """An alder leaf pointing up: a bold, symmetric pointed oval on a short stem (it stays a leaf
    when the shield turns; a midrib only made it read as a bean at sprite size)."""
    n = 14
    right = [(w * math.sin(math.pi * i / n) ** 0.85, y0 - h + 2.0 * h * i / n) for i in range(n + 1)]
    left = [(-x, y) for x, y in reversed(right)]
    return [(0.5, y0 - h - stem)] + right[1:-1] + [right[-1]] + left[1:-1] + [(-0.5, y0 - h - stem)]


LEAF_POLY = _leaf_poly()


class BentPrism(Prism):
    """A Prism whose face bends back toward its sides (z -= bend * x^2), shrunk by `inset` and
    moved `zoff` along its face normal."""

    def __init__(self, mat: Material, pos, poly, hz: float, R=None, bend: float = 0.0,
                 inset: float = 0.0, zoff: float = 0.0, **kw) -> None:
        super().__init__(mat, pos, poly, hz, R=R, **kw)
        self.bend = bend
        self.inset = inset
        self.zoff = zoff

    def dist_local(self, Q):
        q = Q.copy()
        q[:, 2] = q[:, 2] + self.bend * q[:, 0] * q[:, 0] - self.zoff
        d2 = self._poly2d(q[:, 0], q[:, 1]) + self.round + self.inset
        dz = np.abs(q[:, 2]) - (self.hz - self.round)
        outside = np.hypot(np.maximum(d2, 0), np.maximum(dz, 0))
        return (outside + np.minimum(np.maximum(d2, dz), 0.0) - self.round) * 0.9


def shield_parts(center: np.ndarray, R: np.ndarray) -> list[Node]:
    bend = SHIELD_BEND
    return [
        BentPrism(MAT["gold"], center, SHIELD_POLY, 0.75, R=R, bend=bend, round=0.3, group="shield_rim"),
        BentPrism(MAT["field"], center, SHIELD_POLY, 0.5, R=R, bend=bend, inset=1.1, zoff=0.45,
                  group="shield_field"),
        BentPrism(MAT["wood"], center, SHIELD_POLY, 0.45, R=R, bend=bend, inset=0.7, zoff=-0.55,
                  group="shield_back"),
        BentPrism(MAT["emblem"], center, LEAF_POLY, 0.3, R=R, bend=bend, zoff=1.0, group="shield_emblem"),
    ]


# --- The model --------------------------------------------------------------------------------


def _hip_frame(pose: dict[str, Any]) -> np.ndarray:
    lean = float(pose.get("lean", 0.0))
    hl = float(pose.get("hip_lean", lean / 3.0))
    roll = float(pose.get("side_lean", 0.0)) * min(abs(hl) / 60.0, 1.0)
    return rot(0.0, float(pose.get("hip_yaw", 0.0)), 0.0) @ rot(roll, 0.0, -hl)


def skeleton(pose: dict[str, Any]) -> Skeleton:
    p = dict(pose)
    hp, hy, ht = p.get("head", (0.0, 0.0, 0.0))
    p["head"] = (hp, hy + HEAD_YAW, ht)
    sk = pose_skeleton(B, p)
    w = float(pose.get("head_aim", 0.0))
    if w > 0.0:
        # Lying poses aim the head with world vectors (face direction, top of the head); head_aim
        # mixes them with the rig's head so in-betweens turn the head smoothly.
        f = _unit((1.0 - w) * sk.head[:, 0] + w * _unit(pose["head_fwd"]))
        u = (1.0 - w) * sk.head[:, 1] + w * _unit(pose["head_up"])
        u = _unit(u - f * float(np.dot(u, f)))
        sk.head = np.stack([f, u, np.cross(f, u)], axis=1)
        sk.j["head"] = sk["neck"] + sk.head @ _v((0.3, B.head_r * 0.92, 0.0))
    return sk


def _surface(sk: Skeleton, y: float, z: float, out: float = 0.25) -> np.ndarray:
    """A point `out` units in front of the skull's face at head-local height y and side z."""
    r = B.head_r
    a, b, c = r * 0.93, r, r * 0.9
    x = a * float(np.sqrt(max(1.0 - (y / b) ** 2 - (z / c) ** 2, 0.0)))
    return sk["head"] + sk.head @ _v((x + out, y, z))


HAIR_C = (-0.3, 0.3, 0.0)


def _hair_radii() -> np.ndarray:
    r = B.head_r
    return _v((r * 0.93 + HAIR_OFF, r + HAIR_OFF - 0.1, r * 0.9 + HAIR_OFF))


# Portrait hair locks (head-local centre, radii, tilt): big soft clumps with their own light.
LOCKS = [((1.6, 5.2, 1.4), (2.3, 1.15, 1.7), 18.0), ((-1.2, 5.6, 1.9), (2.5, 1.2, 1.9), 8.0),
         ((-3.9, 4.0, 2.6), (2.0, 1.2, 1.7), -15.0), ((0.4, 5.6, -1.6), (2.4, 1.15, 1.8), 12.0),
         ((-2.8, 5.0, -1.4), (2.2, 1.2, 1.8), 0.0)]


def head_parts(sk: Skeleton, fine: bool = False) -> list[Node]:
    """Skull, short hair with a hairline, full beard with sideburns, moustache, nose, ear.
    fine=True (portrait) sculpts the face: brow ridge, nose bridge and nostrils, cheeks, lower
    lip, a two-part drooping moustache, brows and big locks of hair."""
    H = sk.head
    head = sk["head"]
    r = B.head_r
    parts: list[Node] = []

    def at(x: float, y: float, z: float) -> np.ndarray:
        return head + H @ _v((x, y, z))

    skull = Ellipsoid(MAT["skin"], head, (r * 0.93, r, r * 0.9), R=H, group="head")
    ear = Ellipsoid(MAT["skin"], at(-0.7, -0.3, r * 0.9 + 0.2), (0.95, 1.45, 0.7), R=H @ rot(0.0, 12.0, 0.0),
                    group="ear")
    if fine:
        parts.append(SmoothUnion(
            skull,
            Ellipsoid(MAT["skin"], at(r * 0.74, 1.4, 0.0), (1.0, 0.65, 3.1), R=H, group="head"),
            RoundCone(MAT["skin"], at(r * 0.84, 1.05, 0.0), at(r * 0.93 + 1.5, -0.8, 0.0), 0.5, 0.92,
                      group="head"),
            Sphere(MAT["skin"], at(r * 0.9 + 0.55, -1.1, 0.82), 0.53, group="head"),
            Sphere(MAT["skin"], at(r * 0.9 + 0.55, -1.1, -0.82), 0.53, group="head"),
            Ellipsoid(MAT["skin"], at(r * 0.62, -0.55, 2.45), (1.45, 1.05, 1.25), R=H, group="head"),
            Ellipsoid(MAT["skin"], at(r * 0.62, -0.55, -2.45), (1.45, 1.05, 1.25), R=H, group="head"),
            Ellipsoid(MAT["skin"], at(r * 0.86, -2.7, 0.0), (0.6, 0.32, 1.15), R=H, group="head"),
            k=0.7,
        ))
        parts.append(ear)
        parts.append(Ellipsoid(MAT["skin"], at(-0.5, -0.35, r * 0.9 + 0.57), (0.5, 0.85, 0.3), R=H,
                               group="ear"))
    else:
        parts.append(skull)
        parts.append(Sphere(MAT["skin"], at(r * 0.9, -0.5, 0.0), 0.9, group="head"))
        parts.append(ear)

    # Hair: a shell over the skull, kept above a hairline that is high at the brow, low at the nape.
    shell: Node = Ellipsoid(MAT["hair"], at(*HAIR_C), _hair_radii(), R=H, group="hair")
    if fine:
        # A few big locks melted into the shell: grouped light, no speckle.
        locks = [Ellipsoid(MAT["hair"], at(x, y, z), radii, R=H @ rot(0.0, 0.0, tilt), group="hair")
                 for (x, y, z), radii, tilt in LOCKS]
        shell = SmoothUnion(shell, *locks, k=0.7)
    hairline = Custom(MAT["hair"], lambda Q: (1.5 + 0.5 * Q[:, 0] - Q[:, 1]) / 1.12, pos=head, R=H)
    parts.append(Intersect(shell, hairline))

    # Beard: a shell over the jaw below a beard line (sideburns run up to the hair by the ear).
    def beard_line(Q):
        x, y, z = Q[:, 0], Q[:, 1], Q[:, 2]
        front = -1.5 + np.clip(np.abs(z) / 3.3, 0.0, 1.0) * 1.0
        lim = front + np.clip(1.6 - x, 0.0, 2.6) * 1.5
        return np.maximum(y - lim, -1.6 - x)

    bshell = Ellipsoid(MAT["hair"], at(0.4, -0.6, 0.0), (r * 0.93 + BEARD_OFF, r + BEARD_OFF - 0.2,
                                                          r * 0.9 + BEARD_OFF), R=H, group="beard")
    beard_cut = Custom(MAT["hair"], beard_line, pos=head, R=H)
    if fine:
        # Leave the lower lip and a little chin skin above the beard's bulk free.
        mouth = Ellipsoid(MAT["hair"], at(r * 0.9, -2.7, 0.0), (1.7, 0.45, 1.45), R=H)
        parts.append(Intersect(Subtract(bshell, mouth, k=0.2), beard_cut))
    else:
        parts.append(Intersect(bshell, beard_cut))
    parts.append(Ellipsoid(MAT["hair"], at(2.4, -4.4, 0.0), (2.4, 2.2, 3.0), R=H, group="beard"))
    if fine:
        for sgn in (1.0, -1.0):
            # A big, warm, drooping moustache (each half sweeps out and down past the mouth).
            parts.append(Ellipsoid(MAT["hair_hi"], at(r * 0.88 + 0.8, -1.85, sgn * 1.25), (1.0, 0.7, 1.75),
                                   R=H @ rot(sgn * 26.0, 0.0, -8.0), group="moustache"))
            parts.append(Ellipsoid(MAT["hair_hi"], at(r * 0.74 + 0.8, -2.6, sgn * 2.65), (0.78, 1.05, 0.72),
                                   R=H @ rot(sgn * 30.0, 0.0, 0.0), group="moustache"))
            # Thick, gently arched brows on the brow ridge (warm, not stern).
            a = _surface(sk, 1.8, sgn * 0.8, 0.25)
            b = _surface(sk, 2.1, sgn * 2.1, 0.3)
            c = _surface(sk, 1.7, sgn * 3.2, 0.2)
            parts.append(RoundCone(MAT["hair"], a, b, 0.42, 0.46, group="brow"))
            parts.append(RoundCone(MAT["hair"], b, c, 0.46, 0.3, group="brow"))
    else:
        parts.append(Ellipsoid(MAT["hair_hi"], at(r * 0.86 + 0.3, -1.65, 0.0), (1.0, 0.72, 2.5),
                               R=H @ rot(0.0, 0.0, -10.0), group="beard"))
    return parts


# Pack strap from the pack over the near pauldron and down the chest: torso-space guide points and
# the torso axis each one is pushed along until it sits on the surface (see _drape).
STRAP_PTS = (((-3.8, 0.6, 6.0), None), ((-1.8, 2.0, 6.4), 1), ((0.4, 2.0, 6.5), 1), ((2.6, 1.2, 6.0), 1),
             ((3.4, -1.4, 4.8), 0), ((3.0, -4.8, 4.0), 0))
# The far strap only peeks over the far shoulder (a line on the sprite).
STRAP_FAR = ((-3.0, 1.6, -4.6), (-0.4, 3.0, -4.8), (2.6, 2.0, -4.4))


def _drape(body: Node, chest: np.ndarray, t: np.ndarray, guide) -> list[np.ndarray]:
    """Guide points (torso space) pushed along their torso axis until they clear `body`."""
    out = []
    for p, axis in guide:
        q = chest + t @ _v(p)
        if axis is not None:
            d = t[:, axis]
            for _ in range(80):
                if float(body.eval(q[None, :])[0][0]) >= 0.3:
                    break
                q = q + d * 0.12
        out.append(q)
    return out


def model(pose: dict[str, Any], detail: str = "sprite") -> tuple[Node, dict[str, Any]]:
    """The SDF model of Alder in `pose` plus what the overlays need (skeleton, anchors).
    detail="portrait" adds the fine face."""
    fine = detail == "portrait"
    sk = skeleton(pose)
    t = sk.torso
    hp = _hip_frame(pose)
    parts: list[Node] = []
    chest, pelvis, belly = sk["chest"], sk["pelvis"], sk["belly"]

    # Torso: blue tabard body, steel breastplate and gorget over it, belt with a gold buckle.
    parts.append(SmoothUnion(
        Ellipsoid(MAT["tabard"], chest + t @ _v((0.0, -2.6, 0.0)), (3.9, 5.0, 5.4), R=t),
        Ellipsoid(MAT["tabard"], belly, (3.5, 4.2, 4.4), R=t),
        Ellipsoid(MAT["tabard"], pelvis + hp @ _v((0.0, 0.2, 0.0)), (3.4, 3.2, 4.2), R=hp),
        k=1.4,
    ))
    parts.append(Ellipsoid(MAT["steel"], chest + t @ _v((0.35, -2.0, 0.0)), (4.05, 4.5, 5.5), R=t, group="plate"))
    parts.append(Ellipsoid(MAT["steel"], chest + t @ _v((0.2, 0.9, 0.0)), (2.6, 1.3, 3.0), R=t, group="plate"))
    belt_c = pelvis + hp @ _v((0.0, 2.3, 0.0))
    parts.append(Intersect(Ellipsoid(MAT["leather_dark"], belt_c, (3.75, 2.0, 4.65), R=t),
                           Box(MAT["leather_dark"], belt_c, (9.0, 0.75, 9.0), R=t)))
    parts.append(Box(MAT["gold"], belt_c + t @ _v((3.7, 0.0, 0.6)), (0.45, 0.85, 0.85), R=t, group="buckle"))
    # Tabard front panel hanging toward the knees.
    kn = 0.5 * (sk["knee_n"] + sk["knee_f"])
    top = pelvis + hp @ _v((2.6, 0.6, 0.0))
    bot = top + (kn + hp @ _v((1.6, 1.6, 0.0)) - top) * 0.85
    parts.append(Box(MAT["tabard"], 0.5 * (top + bot), (0.45, float(np.linalg.norm(bot - top)) * 0.5, 2.5),
                     R=_frame_y(top, bot, hp @ _v((1.0, 0.0, 0.0))), round=0.3, group="panel"))

    # Legs: short blue skirt over the thigh tops, dark trousers, boots with turned-down cuffs.
    for s in ("n", "f"):
        hipj, knee, ankle, toe = sk["hip_" + s], sk["knee_" + s], sk["ankle_" + s], sk["toe_" + s]
        parts.append(RoundCone(MAT["tabard"], hipj, hipj + (knee - hipj) * 0.35, 2.5, 2.6, group="leg" + s))
        parts.append(RoundCone(MAT["pants"], hipj, knee, 2.0, 1.75, group="leg" + s))
        parts.append(RoundCone(MAT["leather_dark"], knee + (ankle - knee) * 0.12, ankle, 1.9, 1.6, group="boot" + s))
        parts.append(RoundCone(MAT["leather"], knee + (ankle - knee) * 0.1, knee + (ankle - knee) * 0.28,
                               2.15, 2.05, group="cuff" + s))
        parts.append(RoundCone(MAT["leather_dark"], ankle, toe, 1.65, 1.35, group="boot" + s))
        parts.append(Sphere(MAT["steel"], knee + sk.hips @ _v((0.7, 0.2, 0.0)), 1.35, group="knee" + s))

    # Arms: steel rerebrace, vambrace and gauntlet, a big two-plate pauldron with gold trim.
    for s, sgn in (("n", 1.0), ("f", -1.0)):
        sh, el, hd = sk["shoulder_" + s], sk["elbow_" + s], sk["hand_" + s]
        parts.append(RoundCone(MAT["steel"], sh, el, 1.75, 1.5, group="arm" + s))
        parts.append(Sphere(MAT["pants"], el, 1.45, group="elbow" + s))
        parts.append(RoundCone(MAT["steel"], el + (hd - el) * 0.12, hd, 1.65, 1.5, group="vamb" + s))
        parts.append(Sphere(MAT["steel"], hd, 1.6, group="vamb" + s))
        pc = sh + t @ _v((0.0, 0.9, sgn * 0.6))
        pr = t @ rot(sgn * -14.0, 0.0, 0.0)
        parts.append(Ellipsoid(MAT["steel"], pc, PAULDRON, R=pr, group="pauldron" + s))
        parts.append(Ellipsoid(MAT["steel"], pc + t @ _v((0.0, -2.0, sgn * 0.6)), (3.1, 1.8, 2.8),
                               R=t @ rot(sgn * -20.0, 0.0, 0.0), group="pauldron2" + s))
        parts.append(Torus(MAT["gold"], pc + pr @ _v((0.0, -1.0, 0.0)), 3.3, 0.4, R=pr, group="trim" + s))

    parts.append(RoundCone(MAT["skin"], chest + t @ _v((0.2, 0.5, 0.0)), sk["neck"], 1.6, 1.6, group="head"))
    parts.extend(head_parts(sk, fine))

    # The pack strap over the near pauldron, down the chest.
    pts = _drape(Union(*parts), chest, t, STRAP_PTS)
    for a, b in zip(pts[:-1], pts[1:]):
        parts.append(RoundCone(MAT["leather"], a, b, 0.5, 0.5, group="strap", thin=True))

    # Backpack: canvas pack, leather flap, a smaller bedroll strapped on top (below the nape).
    pk = chest + t @ _v((-6.3, -4.1, 0.0))
    parts.append(Box(MAT["canvas"], pk, (2.6, 4.0, 4.2), R=t, round=1.4, group="pack"))
    parts.append(Box(MAT["leather"], pk + t @ _v((0.15, 2.3, 0.0)), (2.75, 1.7, 4.3), R=t, round=1.0, group="flap"))
    roll_c = pk + t @ _v((-1.0, 5.4, 1.0))
    rr = t @ rot(90.0, 0.0, 0.0)
    parts.append(Cylinder(MAT["wool"], roll_c, ROLL_R, ROLL_HALF, R=rr, round=0.45, group="roll"))
    for zz in (-2.0, 2.0):
        parts.append(Cylinder(MAT["leather_dark"], roll_c + t @ _v((0.0, 0.0, zz)), 1.85, 0.35, R=rr,
                              group="rollstrap"))

    # The shield on the near arm.
    sr = frame_nu(pose.get("shield_n", (0.0, 0.0, 1.0)), pose.get("shield_up", (0.0, 1.0, 0.0)))
    so = pose.get("shield_off", (0.0, 0.0))
    push = float(pose.get("shield_push", 0.0))
    s_center = sk["hand_n"] + sr @ _v((so[0], so[1], 2.3 + push))
    drop = float(pose.get("shield_drop", 0.0))
    if drop > 0.0:   # the dropped shield (down) lies at a world position
        s_center = (1.0 - drop) * s_center + drop * _v(pose["shield_at"])
    parts.extend(shield_parts(s_center, sr))

    info = {"sk": sk, "shield_c": s_center, "shield_R": sr, "pack": pk, "roll": (roll_c, rr)}
    return Union(*parts), info


# --- Finishing --------------------------------------------------------------------------------

N4 = ((0, -1), (-1, 0), (1, 0), (0, 1))


def _ring(fr: Frame, inner: str, outer: str, steps: int = 2) -> None:
    """Darkens `outer`-group pixels that touch `inner`-group pixels (a dark line round the
    emblem, which sits too close to the field for kit contours to see it)."""
    H, W = fr.H, fr.W
    g = np.array([fr.groups[p] if p >= 0 else "" for p in fr.part.ravel()]).reshape(H, W)
    darker = np.zeros((H, W), dtype=bool)
    for y in range(H):
        for x in range(W):
            if g[y, x] != outer:
                continue
            for dx, dy in N4:
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and g[ny, nx] == inner:
                    darker[y, x] = True
                    break
    fr.idx = np.where(darker, np.maximum(fr.idx - steps, 0), fr.idx)


def _despur(fr: Frame, passes: int = 3) -> None:
    """Drops solid pixels with at most one solid 4-neighbour (1-pixel tips that would grow an
    outline spur)."""
    for _ in range(passes):
        solid = fr.part >= 0
        pad = np.pad(solid, 1)
        n = pad[:-2, 1:-1].astype(int) + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:]
        lone = solid & (n <= 1)
        if not lone.any():
            break
        fr.part[lone] = -1
        fr.depth[lone] = np.inf


def _despur_rgba(rgba: np.ndarray, passes: int = 3) -> np.ndarray:
    out = rgba.copy()
    for _ in range(passes):
        op = out[..., 3] > 0
        pad = np.pad(op, 1)
        n = pad[:-2, 1:-1].astype(int) + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:]
        lone = op & (n <= 1)
        if not lone.any():
            break
        out[lone] = 0
    return out


def finish_alder(fr: Frame, contour_gap: float = 2.5, contour_steps: int = 2) -> np.ndarray:
    """kit.post.finish plus the emblem ring and spur removal."""
    contours(fr, contour_gap, contour_steps)
    _ring(fr, "shield_emblem", "shield_field", 2)
    cleanup(fr)
    _despur(fr)
    outline(fr)
    return _despur_rgba(fr.rgba())


# --- Overlays ---------------------------------------------------------------------------------

EYE_Y = 0.7
EYE_Z = 1.95


def _overlays(fr, cam: Camera, pose: dict[str, Any], info: dict[str, Any]) -> None:
    sk: Skeleton = info["sk"]
    t = sk.torso
    chest = sk["chest"]
    line3d(fr, cam, [chest + t @ _v(p) for p in STRAP_FAR], MAT["leather"], 1, group="strap", depth_bias=0.8)
    # Near eye only at sprite size (the far one would sit on the face's edge as a notch): a dark
    # pixel with a brow pixel above; shut eyes are a brow-coloured dash.
    eyes = int(round(float(pose.get("eyes", 0))))
    legend = {"b": (MAT["hair"], 0), "e": (MAT["ink"], 0), "c": (MAT["hair"], 0)}
    anchor = _surface(sk, EYE_Y, EYE_Z)
    if eyes == 0:
        stamp(fr, cam, anchor, ["b", "e"], legend, origin=(0, 1), depth_bias=0.5)
    else:
        stamp(fr, cam, anchor, ["cc"], legend, origin=(0, 0), depth_bias=0.5)


# --- Poses ------------------------------------------------------------------------------------

POSES: dict[str, dict[str, Any]] = {
    "idle": {
        # Relaxed, the shield carried on the near forearm at his side (owner's pick, 2026-10-21,
        # card #297): its face to us, its edge toward the enemy, tipped so the point aims back and
        # down. Until then it hung low in front of him.
        "pelvis": (0.0, HIP - 0.3, 0.0),
        "foot_n": (2.5, AH, 3.6), "foot_f": (-2.5, AH, -3.2),
        "hand_n": (4.6, HIP + 1.4, 7.0), "elbow_n": (-0.6, -1.0, 0.4),
        "hand_f": (0.4, CH - 12.0, -7.6),
        "shield_n": (0.12, 0.0, 1.0), "shield_up": (0.45, 0.9, 0.0), "shield_off": (-2.4, -1.6),
        "head": (2.0, 0.0, 0.0),
    },
    "ready": {
        # Braced on the turn: wide, low stance, shield forward covering the body.
        "pelvis": (0.6, HIP - 3.0, 0.0), "lean": 10.0,
        "foot_n": (5.5, AH, 3.0), "foot_f": (-5.5, AH, -2.6), "toe_f": 6.0,
        "hand_n": (6.6, CH - 7.2, 4.4), "elbow_n": (-0.5, -1.0, 0.8),
        "hand_f": (4.0, CH - 8.8, -3.8),
        "shield_n": (0.75, 0.0, 0.66), "shield_up": (0.0, 1.0, 0.0), "shield_off": (0.0, -1.0),
        "head": (6.0, 0.0, 0.0),
    },
    "parry": {
        # Shield thrust up and forward, body crouched and head tucked behind it.
        "pelvis": (-0.8, HIP - 3.4, 0.0), "lean": 14.0,
        "foot_n": (4.2, AH, 3.0), "foot_f": (-5.0, AH, -2.6), "toe_f": 8.0,
        "hand_n": (9.1, CH + 0.4, 4.2), "elbow_n": (0.0, -1.0, 0.6),
        "hand_f": (3.0, CH - 5.8, -3.4),
        "shield_n": (0.85, 0.15, 0.5), "shield_up": (-0.2, 1.0, 0.0), "shield_off": (0.0, 0.0),
        "shield_push": 1.5,
        "head": (25.0, 0.0, 0.0),
    },
    "dodge": {
        # A low backward slide: weight on the bent back leg, front leg stretched toward the enemy
        # with the toe up, torso and head pulled back behind the raised shield.
        "pelvis": (-0.4, HIP - 6.0, 0.0), "lean": -25.0, "hip_lean": -10.0,
        "foot_f": (-2.6, AH, -2.8), "knee_f": (1.0, 0.0, -0.1), "toe_f": 0.0,
        "foot_n": (10.5, AH, 3.2), "toe_n": 25.0,
        "hand_n": (4.6, CH - 4.4, 5.8), "elbow_n": (-0.6, -1.0, 0.6),
        "hand_f": (-10.0, CH - 16.0, -2.0),
        "shield_n": (0.9, 0.15, 0.4), "shield_up": (0.0, 1.0, 0.0), "shield_off": (0.0, 0.0),
        "head": (-15.0, 0.0, 0.0),
    },
    "jump": {
        # Tucked in the air: knees drawn up in front, the shield held low under them.
        "pelvis": (-2.0, 18.5, 0.0), "lean": -14.0, "hip_lean": -8.0,
        "foot_n": (4.4, 14.0, 3.0), "foot_f": (3.6, 14.8, -2.4),
        "knee_n": (1.0, 0.6, 0.05), "knee_f": (1.0, 0.6, -0.05), "toe_n": -15.0, "toe_f": -15.0,
        "hand_n": (5.5, 17.0, 6.5), "elbow_n": (-0.5, -1.0, 0.6),
        "hand_f": (-8.0, 23.0, -6.0), "elbow_f": (0.0, -1.0, -0.3),
        "shield_n": (0.8, -0.2, 0.55), "shield_up": (0.25, 0.97, 0.0), "shield_off": (0.0, -4.5),
        "head": (8.0, 0.0, 0.0),
    },
    "hurt": {
        # Knocked back: chest open, head thrown back with eyes shut, shield arm flung out.
        "pelvis": (1.8, HIP - 1.6, 0.0), "lean": -20.0,
        "foot_n": (6.8, AH, 3.0), "foot_f": (-1.0, AH + 2.6, -2.6), "toe_f": -10.0,
        "hand_n": (-2.4, CH - 4.0, 8.6), "elbow_n": (0.0, -0.3, 1.0),
        "hand_f": (-1.5, CH - 3.0, -5.0),
        "shield_n": (-0.15, 0.15, 0.98), "shield_up": (-0.68, 0.73, 0.0), "shield_off": (0.0, 0.0),
        "head": (-16.0, 0.0, 6.0),
        "eyes": 1,
    },
    "strike": {
        # Shield bash: a deep forward lunge, arm driving the shield face to the right, head tucked
        # behind its rim, back leg straight with the heel up.
        "pelvis": (-2.4, HIP - 4.0, 0.0), "lean": 33.0, "hip_lean": 12.0,
        "foot_n": (5.6, AH, 3.0), "foot_f": (-10.5, AH + 1.4, -2.6), "toe_f": -30.0,
        "hand_n": (11.6, CH - 5.0, 3.4), "elbow_n": (-0.4, -1.0, 0.4),
        "hand_f": (-7.0, CH - 9.0, -4.6),
        "shield_n": (0.95, 0.0, 0.3), "shield_up": (0.25, 1.0, 0.0), "shield_off": (0.0, 0.0),
        "head": (25.0, 0.0, 0.0),
    },
    "down": {
        # Collapsed face-down, rolled a little toward the viewer: pack on top, knees drawn up toward
        # the viewer with the boots at the left, head on its cheek at the right resting on the near
        # arm, the dropped shield behind the body (only its rim and some field show).
        "pelvis": (-7.2, 4.6, 0.0), "lean": 90.0, "hip_lean": 90.0, "side_lean": -30.0, "hip_yaw": -10.0,
        "foot_n": (-9.0, 1.9, 9.5), "knee_n": (0.5, 0.0, 1.0), "toe_n": -75.0, "toe_yaw_n": 90.0,
        "foot_f": (-10.2, 1.9, 6.0), "knee_f": (0.5, 0.0, 1.0), "toe_f": -75.0, "toe_yaw_f": 90.0,
        "hand_n": (5.0, 2.5, 5.0), "elbow_n": (0.0, 0.3, 1.0),
        "hand_f": (8.0, 1.6, 0.0), "elbow_f": (0.0, 1.0, 0.0),
        "shield_at": (-6.0, 8.0, -9.0), "shield_drop": 1.0,
        "shield_n": (0.1, 0.3, 0.95), "shield_up": (1.0, 0.1, 0.0),
        "head_fwd": (0.15, -0.2, 1.0), "head_up": (1.0, 0.2, 0.6), "head_aim": 1.0,
        "eyes": 2,
    },
}


def _complete(pose: dict[str, Any]) -> dict[str, Any]:
    """Fills every optional key with its neutral value (what pose_skeleton would assume), so two
    poses always blend key by key."""
    p = dict(pose)
    lean = float(p.get("lean", 0.0))
    side = float(p.get("side_lean", 0.0))
    yaw = float(p.get("hip_yaw", 0.0))
    torso = rot(0.0, yaw + float(p.get("twist", 0.0)), 0.0) @ rot(side, 0.0, -lean)
    hips = rot(0.0, yaw, 0.0)
    defaults = {
        "lean": 0.0, "side_lean": 0.0, "twist": 0.0, "hip_yaw": 0.0, "hip_lean": lean / 3.0,
        "head": (0.0, 0.0, 0.0), "head_fwd": (1.0, 0.0, 0.0), "head_up": (0.0, 1.0, 0.0), "head_aim": 0.0,
        "elbow_n": tuple(torso @ _v((-1.0, -0.2, 0.5))), "elbow_f": tuple(torso @ _v((-1.0, -0.2, -0.5))),
        "knee_n": tuple(hips @ _v((1.0, 0.0, 0.15))), "knee_f": tuple(hips @ _v((1.0, 0.0, -0.15))),
        "toe_n": 0.0, "toe_f": 0.0, "toe_yaw_n": yaw, "toe_yaw_f": yaw,
        "shield_off": (0.0, 0.0), "shield_push": 0.0, "shield_at": (0.0, 0.0, 0.0), "shield_drop": 0.0,
        "eyes": 0,
    }
    for k, v in defaults.items():
        p.setdefault(k, v)
    return p


POSES = {name: _complete(p) for name, p in POSES.items()}


# --- Rendering --------------------------------------------------------------------------------


def render_pose(pose: dict[str, Any], cam: Camera | None = None) -> np.ndarray:
    """One RGBA frame of Alder in `pose` (default: the 32x48 sheet camera)."""
    cam = cam or Camera(*specs.HERO_FRAME)
    node, info = model(pose)
    fr = render(node, cam)
    _overlays(fr, cam, pose, info)
    return finish_alder(fr)


# --- Portrait ---------------------------------------------------------------------------------

# Idle, the head turned a touch toward the viewer and the shield lifted and tipped so its top
# corner (gold rim, blue field) pokes up at the bottom edge.
PORTRAIT_POSE: dict[str, Any] = dict(POSES["idle"], head=(-2.0, -6.0, 0.0), hand_n=(7.5, 19.8, 5.0),
                                     elbow_n=(-1.0, 0.0, 0.6),
                                     shield_n=(0.6, 0.0, 0.8), shield_up=(0.55, 1.0, 0.0),
                                     shield_off=(0.0, 0.0))
PORTRAIT_SCALE = 0.375
# Eye stamps at portrait size, drawn looking right: k lash line, w white, i iris, h catch light,
# l lower lid shadow. m mouth line, r cheek blush.
NEAR_EYE = [".kkkkk",
            "kwwIpk",
            ".wwiik",
            "..lll."]
FAR_EYE = ["kkk",
           "Ipk",
           "iik"]
EYE_LEGEND = {"k": ("ink", 0), "w": ("eye", 1), "I": ("iris", 3), "p": ("ink", 0), "i": ("iris", 1),
              "l": ("skin", 1), "m": ("mouth", 2), "r": ("blush", 2)}


def _shell_pt(sk: Skeleton, x: float, y: float, z: float, out: float = 0.0) -> np.ndarray:
    """The point on the hair shell (plus `out`) in head-local direction (x, y, z)."""
    c = _v(HAIR_C)
    radii = _hair_radii()
    d = _v((x, y, z))
    d = d / np.linalg.norm(d / radii)
    n = d / (radii * radii)
    n = n / np.linalg.norm(n)
    return sk["head"] + sk.head @ (c + d + n * out)


# Hair strands (head-local directions from the brow back over the crown): light ones on the
# lit near side, dark partings between the locks; beard strands run down from the cheek.
HAIR_STRANDS = [
    (3, [(0.75, 0.62, 0.55), (0.45, 0.85, 0.6), (0.0, 0.9, 0.62), (-0.5, 0.7, 0.62)]),
    (1, [(0.78, 0.6, 0.3), (0.4, 0.87, 0.36), (-0.1, 0.95, 0.4)]),
]
BEARD_STRANDS = [
    (1, [(0.45, -0.35, 0.95), (0.55, -0.65, 0.8), (0.6, -0.9, 0.5)]),
    (3, [(0.65, -0.4, 0.8), (0.7, -0.7, 0.62), (0.62, -0.95, 0.4)]),
]


def portrait_camera(sk: Skeleton) -> Camera:
    cam = Camera(specs.PORTRAIT, specs.PORTRAIT, scale=PORTRAIT_SCALE)
    v = cam.view(sk["head"] + _v((0.0, -1.2, 0.0)))
    # Put the head centre a little right of and above the frame centre.
    cam.cx = float(v[0]) - 1.5 * PORTRAIT_SCALE
    cam.cy = float(v[1]) - (specs.PORTRAIT - 0.5 - 22.0) * PORTRAIT_SCALE
    return cam


def _roll_spiral(fr: Frame, cam: Camera, info: dict[str, Any]) -> None:
    """The bedroll's rolled-up end: a dark spiral on the near end cap."""
    c, rr = info["roll"]
    pts = []
    for k in range(48):
        a = k / 47.0 * 2.2 * 2.0 * math.pi
        rad = (ROLL_R - 0.35) * (1.0 - k / 56.0)
        pts.append(c + rr @ _v((rad * math.cos(a), ROLL_HALF + 0.05, rad * math.sin(a))))
    line3d(fr, cam, pts, MAT["wool"], 0, group="roll_line", depth_bias=0.6)


def render_portrait(pose: dict[str, Any] | None = None) -> np.ndarray:
    """The 48x48 head-and-shoulders portrait: the same model, rendered closer, with a real face."""
    pose = pose or PORTRAIT_POSE
    node, info = model(pose, "portrait")
    sk: Skeleton = info["sk"]
    cam = portrait_camera(sk)
    fr = render(node, cam, ss=3, ao_dist=0.8)
    _roll_spiral(fr, cam, info)
    legend = {k: (MAT[m], i) for k, (m, i) in EYE_LEGEND.items()}
    stamp(fr, cam, _surface(sk, EYE_Y, EYE_Z, 0.1), NEAR_EYE, legend, origin=(3, 1), depth_bias=0.3)
    stamp(fr, cam, _surface(sk, EYE_Y, -EYE_Z, 0.1), FAR_EYE, legend, origin=(1, 1), depth_bias=0.3)
    stamp(fr, cam, _surface(sk, -2.5, 0.1, 0.4), ["mmm"], legend, origin=(1, 0), depth_bias=1.5)
    stamp(fr, cam, _surface(sk, -0.75, 2.8, 0.1), ["rr"], legend, origin=(0, 0), depth_bias=0.3)
    for idx, pts in HAIR_STRANDS:
        line3d(fr, cam, [_shell_pt(sk, *p, out=0.05) for p in pts], MAT["hair"], idx, group="hair",
               depth_bias=0.3)
    beard_c = _v((0.4, -0.6, 0.0))
    for idx, pts in BEARD_STRANDS:
        q = [sk["head"] + sk.head @ (beard_c + _unit(p) * (B.head_r + 0.6)) for p in pts]
        line3d(fr, cam, q, MAT["hair"], idx, group="beard", depth_bias=0.4)
    return finish_alder(fr, contour_gap=0.8, contour_steps=1)


def sheet() -> np.ndarray:
    return hstack([render_pose(POSES[name]) for name in specs.HERO_POSES])


def _review(path: str, frames: list[np.ndarray], cols: int, scale: int,
            bg: tuple[int, int, int] = (34, 31, 40), gap: int = 6) -> None:
    """A dark-background grid of frames (zoomed), plus every frame at 1x and 2x along the bottom."""
    from PIL import Image
    h, w = frames[0].shape[:2]
    rows = (len(frames) + cols - 1) // cols
    W = cols * (w * scale + gap) + gap
    strip_w = gap + len(frames) * (w + 2) + 8 + len(frames) * (w * 2 + 2)
    Hh = rows * (h * scale + gap) + gap + h * 2 + gap
    out = Image.new("RGBA", (max(W, strip_w), Hh), bg + (255,))
    for i, f in enumerate(frames):
        im = Image.fromarray(f.astype(np.uint8), "RGBA")
        big = im.resize((w * scale, h * scale), Image.NEAREST)
        cx = gap + (i % cols) * (w * scale + gap)
        cy = gap + (i // cols) * (h * scale + gap)
        tile = Image.new("RGBA", big.size, (40, 37, 47, 255))
        tile.alpha_composite(big)
        out.paste(tile, (cx, cy))
        y0 = rows * (h * scale + gap) + gap
        out.alpha_composite(im, (gap + i * (w + 2), y0))
        out.alpha_composite(im.resize((w * 2, h * 2), Image.NEAREST),
                            (gap + len(frames) * (w + 2) + 8 + i * (w * 2 + 2), y0))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path)


# --- Clips (phase 10) -------------------------------------------------------------------------

K = {name: i for i, name in enumerate(specs.HERO_POSES)}


def P(base: dict[str, Any], **kw: Any) -> dict[str, Any]:
    """A keyframe: `base` with some keys changed (every key stays present, see _complete)."""
    return _complete(dict(base, **kw))


def mix(a: dict[str, Any], b: dict[str, Any], t: float, **kw: Any) -> dict[str, Any]:
    """An in-between of two keyframes (t = 0 gives a), with some keys changed."""
    return P(blend(a, b, t), **kw)


IDLE, READY, PARRY, DODGE, JUMP, HURT, STRIKE, DOWN = (POSES[n] for n in specs.HERO_POSES)

# Breathing: the out-breath end of each stance loop. The body sinks a little and the shield dips;
# the head moves at most 1 px, because the game measures its anchors on the key cell only.
IDLE_OUT = P(IDLE, pelvis=(0.0, HIP - 0.9, 0.0), lean=1.5, hand_n=(4.6, HIP + 0.8, 7.0),
             hand_f=(0.3, CH - 12.6, -7.6), head=(3.0, 0.0, 0.0))
READY_OUT = P(READY, pelvis=(0.5, HIP - 3.9, 0.0), lean=11.5, hand_n=(6.6, CH - 7.9, 4.4),
              hand_f=(4.0, CH - 9.4, -3.8), head=(7.0, 0.0, 0.0))

# Draw (fight start): a hitch of the shoulders, the shield swung up and knocked across the
# chest, then let down to the idle key.
DRAW_1 = P(IDLE, pelvis=(-0.3, HIP - 1.6, 0.0), lean=5.0, hand_n=(3.2, CH - 10.8, 7.6), elbow_n=(-1.0, 0.0, 0.6),
           shield_n=(0.8, 0.0, 0.6), shield_up=(0.15, 1.0, 0.0), shield_off=(0.5, -3.0),
           hand_f=(-0.6, CH - 11.6, -7.4), head=(6.0, 0.0, 0.0))
DRAW_2 = P(IDLE, pelvis=(0.4, HIP - 1.2, 0.0), lean=7.0, foot_n=(3.6, AH, 3.4), foot_f=(-3.4, AH, -3.0),
           hand_n=(7.4, CH - 5.4, 5.0), elbow_n=(-0.5, -1.0, 0.8), hand_f=(3.6, CH - 8.0, -4.4),
           shield_n=(0.8, 0.0, 0.6), shield_up=(0.0, 1.0, 0.0), shield_off=(0.0, -0.5), head=(4.0, 0.0, 0.0))
DRAW_3 = mix(DRAW_2, IDLE, 0.55)

# Parry: snap the shield up; on the hit it is driven back into him, then he pushes it out again.
PARRY_SNAP = mix(READY, PARRY, 0.55)
PARRY_HIT_1 = P(PARRY, pelvis=(-2.8, HIP - 3.4, 0.0), lean=-4.0, hip_lean=-2.0, toe_n=14.0,
                hand_n=(5.4, CH - 1.4, 5.0), shield_push=0.0, shield_n=(0.75, 0.3, 0.6),
                shield_up=(-0.6, 1.0, 0.0), head=(34.0, 0.0, 0.0), eyes=1)
PARRY_HIT_2 = mix(PARRY_HIT_1, PARRY, 0.5, eyes=0)

# Dodge: in and out of the key slide.
DODGE_IN = mix(READY, DODGE, 0.45)
DODGE_OUT = mix(DODGE, READY, 0.7)

# Jump: crouch and push, rise tucked, the key at the top; then legs reach down and he lands low.
JUMP_PUSH = P(READY, pelvis=(-1.2, HIP - 8.0, 0.0), lean=28.0, hip_lean=14.0,
              hand_n=(5.0, CH - 14.5, 5.8), hand_f=(-6.5, CH - 15.0, -5.0), head=(-2.0, 0.0, 0.0))
JUMP_TUCK = mix(JUMP_PUSH, JUMP, 0.6)
JUMP_OPEN = P(JUMP, pelvis=(-1.0, 15.0, 0.0), lean=0.0, hip_lean=0.0,
              foot_n=(2.6, 3.6, 3.0), foot_f=(-2.0, 4.8, -2.6), toe_n=-20.0, toe_f=-25.0,
              hand_n=(6.0, 16.0, 6.2), hand_f=(-8.5, 20.5, -6.0))
JUMP_LAND = P(JUMP_PUSH, pelvis=(-0.6, HIP - 5.4, 0.0), lean=14.0, hand_n=(6.4, CH - 9.5, 5.0),
              hand_f=(-2.0, CH - 12.0, -5.0), shield_n=(0.8, 0.0, 0.6), shield_off=(0.0, -2.0))

# Hurt: the key held, a recoil (shield coming back in), then the recovery toward ready.
HURT_RECOIL = P(HURT, pelvis=(1.0, HIP - 2.4, 0.0), lean=-6.0, hip_lean=-2.0,
                foot_f=(-1.8, AH, -2.6), toe_f=0.0, hand_n=(2.4, CH - 7.6, 8.2), elbow_n=(-0.6, -0.6, 0.8),
                shield_n=(0.45, 0.1, 0.9), shield_up=(-0.3, 1.0, 0.0), hand_f=(-1.0, CH - 6.0, -5.4),
                head=(-4.0, 0.0, 4.0), eyes=1)
HURT_RECOVER = mix(HURT_RECOIL, READY, 0.55, eyes=0)

# Stagger (a heavy hit): thrown back a step, the shield arm flung wide, then hunched forward to
# catch his balance and slowly up again.
STAGGER_1 = P(HURT, pelvis=(-2.6, HIP - 2.6, 0.0), lean=-34.0, hip_lean=-12.0,
              foot_n=(5.0, AH, 3.0), foot_f=(-8.4, AH, -2.6), toe_n=24.0, toe_f=0.0,
              hand_n=(-5.0, CH + 0.6, 8.0), hand_f=(-7.0, CH - 4.0, -5.2),
              shield_n=(-0.35, 0.2, 0.92), shield_up=(-0.85, 0.55, 0.0), head=(-22.0, 0.0, 8.0), eyes=1)
STAGGER_2 = P(READY, pelvis=(-1.6, HIP - 5.0, 0.0), lean=24.0, hip_lean=8.0,
              foot_n=(4.4, AH, 3.0), foot_f=(-6.2, AH, -2.6), toe_f=4.0,
              hand_n=(5.0, CH - 13.0, 6.6), hand_f=(2.0, CH - 15.0, -4.6),
              shield_n=(0.9, -0.1, 0.4), shield_up=(0.2, 1.0, 0.0), shield_off=(0.0, -2.0),
              head=(24.0, 0.0, -4.0), eyes=1)
STAGGER_3 = mix(STAGGER_2, READY, 0.4, eyes=0)

# Strike: shield shove. Wind-up: the shield drawn in to the chest, weight sinking onto the back
# foot. The key is the hit; the shield follows through a touch further, then back to ready.
STRIKE_W1 = P(READY, pelvis=(-1.2, HIP - 3.6, 0.0), lean=2.0, hip_lean=0.0,
              foot_f=(-6.2, AH, -2.6), hand_n=(4.2, CH - 7.6, 5.4), hand_f=(1.6, CH - 9.0, -4.2),
              shield_n=(0.82, 0.0, 0.57), head=(10.0, 0.0, 0.0))
STRIKE_W2 = P(STRIKE_W1, pelvis=(-3.0, HIP - 4.8, 0.0), lean=-10.0, hip_lean=-4.0, twist=-22.0,
              foot_f=(-7.4, AH, -2.6), hand_n=(0.6, CH - 7.6, 6.0), hand_f=(-4.6, CH - 10.6, -4.6),
              shield_n=(0.8, 0.0, 0.6), head=(16.0, 0.0, 0.0))
STRIKE_FOLLOW = P(STRIKE, hand_n=(12.6, CH - 5.6, 3.2), shield_push=1.2, lean=36.0)
STRIKE_RECOVER = mix(STRIKE, READY, 0.55)

# Strike alt: an upward rim swipe. Wind-up: crouched, the shield swung low and back with its rim
# leading; the hit is the rim sweeping up in front; it follows through high, then back to ready.
ALT_W1 = P(READY, pelvis=(-0.6, HIP - 4.6, 0.0), lean=18.0, hip_lean=8.0,
           hand_n=(3.4, CH - 13.0, 6.6), elbow_n=(-0.6, -0.8, 0.6), hand_f=(3.6, CH - 10.0, -4.6),
           shield_n=(0.45, -0.2, 0.87), shield_up=(0.6, -0.8, 0.0), shield_off=(0.0, 1.0), head=(14.0, 0.0, 0.0))
ALT_W2 = P(ALT_W1, pelvis=(-1.2, HIP - 5.2, 0.0), lean=22.0, hand_n=(-0.8, CH - 14.0, 7.2),
           shield_n=(0.25, -0.25, 0.94), shield_up=(-0.2, -1.0, 0.0), head=(18.0, 0.0, 0.0))
ALT_1 = P(READY, pelvis=(0.6, HIP - 3.0, 0.0), lean=12.0, hip_lean=6.0,
          foot_n=(6.4, AH, 3.0), foot_f=(-5.6, AH, -2.6), toe_f=12.0,
          hand_n=(10.2, CH - 4.0, 4.6), elbow_n=(-0.4, -1.0, 0.6), hand_f=(0.0, CH - 10.0, -4.8),
          shield_n=(0.35, 0.0, 0.94), shield_up=(1.0, 0.45, 0.0), shield_off=(0.0, 1.5), head=(0.0, 0.0, 0.0))
ALT_2 = P(ALT_1, pelvis=(1.0, HIP - 1.4, 0.0), lean=-2.0, hip_lean=0.0, foot_f=(-5.2, AH + 1.0, -2.6),
          toe_f=-20.0, hand_n=(7.4, CH + 5.4, 4.2), elbow_n=(-0.6, -0.6, 0.6), hand_f=(-2.0, CH - 9.0, -5.0),
          shield_n=(0.3, 0.1, 0.95), shield_up=(0.3, 1.0, 0.0), shield_off=(0.0, 2.0), head=(-10.0, 0.0, 0.0))
ALT_RECOVER = mix(ALT_2, READY, 0.55)

# Strike big: a two-hand shield slam. Wind-up: both hands heave the shield up over the head; the
# hit drives its tip down into the ground in front; he sags into it, then back to ready.
BIG_W1 = P(READY, pelvis=(-0.6, HIP - 2.6, 0.0), lean=4.0, hip_lean=2.0,
           hand_n=(4.4, CH - 2.0, 4.0), elbow_n=(-0.4, -1.0, 0.8), hand_f=(3.6, CH - 2.4, -1.6),
           elbow_f=(-0.4, -1.0, -0.6), shield_n=(0.5, 0.0, 0.87), shield_up=(0.0, 1.0, 0.0),
           shield_off=(0.0, 1.0), head=(-4.0, 0.0, 0.0))
BIG_W2 = P(BIG_W1, pelvis=(-2.0, HIP - 2.0, 0.0), lean=-16.0, hip_lean=-5.0, foot_f=(-6.4, AH, -2.6),
           hand_n=(-1.4, CH + 9.4, 3.4), hand_f=(-2.2, CH + 8.8, -1.8), elbow_n=(0.4, -0.2, 0.9),
           elbow_f=(0.4, -0.2, -0.9), shield_n=(-0.2, 0.35, 0.92), shield_up=(-1.0, 0.45, 0.0),
           shield_off=(-1.0, 0.5), head=(-18.0, 0.0, 0.0))
BIG_1 = P(READY, pelvis=(0.0, HIP - 5.2, 0.0), lean=22.0, hip_lean=10.0,
          foot_n=(6.0, AH, 3.0), foot_f=(-7.4, AH, -2.6), toe_f=10.0,
          hand_n=(12.4, CH - 14.0, 4.6), elbow_n=(-0.2, -1.0, 0.8), hand_f=(11.2, CH - 13.4, -0.8),
          elbow_f=(-0.2, -1.0, -0.6), shield_n=(0.55, 0.1, 0.83), shield_up=(0.3, 0.95, 0.0),
          shield_off=(0.0, -5.6), head=(14.0, 0.0, 0.0))
BIG_2 = P(BIG_1, pelvis=(-0.2, HIP - 6.4, 0.0), lean=28.0, hand_n=(12.2, CH - 15.0, 4.6),
          hand_f=(11.0, CH - 14.4, -0.8), head=(24.0, 0.0, 0.0))
BIG_RECOVER = mix(BIG_2, READY, 0.5)

# Cast: the shield raised high on one arm and the stance braced wide (a rallying guard).
CAST_1 = P(READY, pelvis=(-0.4, HIP - 5.6, 0.0), lean=-4.0, hip_lean=0.0,
           foot_n=(6.8, AH, 3.2), foot_f=(-6.8, AH, -2.8), toe_f=6.0,
           hand_n=(5.6, CH + 8.2, 4.6), elbow_n=(-0.4, -0.6, 0.8), hand_f=(3.4, HIP - 4.0, -5.0),
           elbow_f=(-1.0, 0.0, -0.6), shield_n=(0.55, 0.55, 0.62), shield_up=(-0.75, 0.65, 0.0),
           shield_off=(0.0, 0.0), head=(-16.0, 0.0, 0.0))
CAST_2 = P(CAST_1, pelvis=(-0.5, HIP - 6.4, 0.0), hand_n=(5.8, CH + 7.4, 4.6), shield_push=0.6)
CAST_W1 = mix(READY, CAST_1, 0.35)
CAST_W2 = mix(READY, CAST_1, 0.7)
CAST_RECOVER = mix(CAST_2, READY, 0.55)

# Leap (the follow-up hop): crouch and spring, tucked in the air behind the shield, land low.
# The game moves the body along the hop's arc, so the cells only lift the feet a little.
LEAP_1 = P(JUMP_PUSH, lean=26.0, foot_f=(-6.6, AH + 0.8, -2.6), toe_f=-24.0, hand_n=(7.6, CH - 9.5, 5.0),
           shield_n=(0.85, 0.0, 0.52), shield_off=(0.0, -1.5))
LEAP_2 = P(JUMP, pelvis=(-0.6, HIP - 1.0, 0.0), lean=8.0, hip_lean=0.0,
           foot_n=(4.2, 8.6, 3.0), foot_f=(-2.6, 9.6, -2.4), hand_n=(8.4, CH - 6.0, 5.0), hand_f=(-4.0, CH - 6.0, -5.6),
           shield_n=(0.85, 0.0, 0.52), shield_up=(0.1, 1.0, 0.0), shield_off=(0.0, -1.0), head=(8.0, 0.0, 0.0))
LEAP_3 = JUMP_LAND

# Fall: from the hurt key down onto the knees, tipping forward with the shield sliding off, then the
# down key. The dropped shield always heads for where it lies in the down key.
SHIELD_REST = DOWN["shield_at"]
FALL_1 = P(HURT, pelvis=(0.4, 11.0, 0.0), lean=18.0, hip_lean=10.0,
           foot_n=(-4.2, AH, 3.4), foot_f=(-5.6, AH, -2.6), knee_n=(1.0, 0.0, 0.1), knee_f=(1.0, 0.0, -0.1),
           toe_n=-40.0, toe_f=-40.0, hand_n=(5.4, 9.6, 7.0), elbow_n=(-0.6, 0.0, 0.8), hand_f=(3.0, 9.0, -5.0),
           shield_n=(0.8, 0.0, 0.6), shield_up=(0.1, 1.0, 0.0), shield_off=(0.0, -1.0),
           shield_at=SHIELD_REST, head=(28.0, 0.0, 0.0), eyes=1)
FALL_2 = mix(FALL_1, DOWN, 0.55, shield_at=SHIELD_REST, eyes=1)

# Get up: from the down key onto hands and knees, the shield taken up, a knee planted, then idle.
GETUP_1 = P(FALL_1, pelvis=(-2.6, 9.8, 0.0), lean=58.0, hip_lean=30.0,
            foot_n=(-8.4, AH, 3.6), foot_f=(-9.0, AH, -2.6), hand_n=(6.0, 3.2, 6.0), hand_f=(5.0, 2.6, -3.6),
            elbow_n=(-1.0, 0.2, 0.6), shield_drop=0.55, shield_n=(0.4, 0.4, 0.85), shield_up=(1.0, 0.2, 0.0),
            head=(-6.0, 0.0, 0.0), eyes=0)
GETUP_2 = P(READY, pelvis=(-0.8, 12.2, 0.0), lean=16.0, hip_lean=6.0,
            foot_n=(4.0, AH, 3.4), foot_f=(-6.6, AH, -2.6), knee_f=(1.0, 0.0, -0.1), toe_f=-40.0,
            hand_n=(6.2, CH - 14.0, 6.0), hand_f=(3.6, 13.0, -3.8),
            shield_n=(0.8, 0.0, 0.6), shield_off=(0.0, -2.0), head=(4.0, 0.0, 0.0))

# Victory: the shield thrust up high, then planted tip-down in front with a hand on its rim, chest
# out (victory_hold breathes on that).
VIC_1 = P(READY, pelvis=(0.0, HIP - 4.6, 0.0), lean=14.0, hand_n=(5.0, CH - 11.0, 6.0),
          hand_f=(1.4, CH - 12.0, -5.6), head=(10.0, 0.0, 0.0))
VIC_2 = P(IDLE, pelvis=(0.4, HIP - 0.6, 0.0), lean=-6.0, hip_lean=-2.0, foot_n=(3.4, AH, 3.6),
          foot_f=(-3.0, AH, -3.2), hand_n=(4.0, CH + 9.0, 5.2), elbow_n=(-0.4, -0.4, 0.9),
          hand_f=(-1.0, CH - 11.0, -6.4), shield_n=(0.45, 0.1, 0.9), shield_up=(0.2, 1.0, 0.0),
          shield_off=(0.0, 1.5), head=(-16.0, 0.0, 0.0))
VIC_4 = P(IDLE, pelvis=(0.0, HIP - 0.5, 0.0), lean=-5.0, hip_lean=-1.5,
          foot_n=(2.0, AH, 3.6), foot_f=(-3.2, AH, -3.2),
          hand_n=(8.0, 18.2, 6.0), elbow_n=(-1.0, -0.2, 0.6), hand_f=(-2.6, HIP + 1.4, -6.4),
          elbow_f=(-0.6, 0.2, -1.0), shield_n=(0.7, 0.0, 0.7), shield_up=(0.05, 1.0, 0.0),
          shield_off=(0.0, -7.8), head=(-10.0, 0.0, 0.0))
VIC_3 = mix(VIC_2, VIC_4, 0.5)
VIC_4B = P(VIC_4, pelvis=(0.0, HIP - 1.1, 0.0), lean=-3.5, head=(-8.0, 0.0, 0.0))

# Run (combat): the dash up to an enemy before a strike (about 0.4 s across the stage). A heavy
# run: leaning in, the shield carried on the near forearm at his side as in the idle (face to us,
# tipped so its point aims back), bobbing with him; the far arm pumps. The near foot strikes on
# cell 0, the far foot on cell 4; both feet are off the floor on cells 3 and 7.
RUN_CELLS = 8
# One leg's ankle (x from the pelvis, height) and toe pitch per cell, the near leg; the far leg is
# four cells later. Strike, weight taken, push-off, leaving the floor, heel kicked up behind, knee
# driving through, reaching, coming down for the next strike.
RUN_LEG = ((6.2, AH, 6.0), (1.8, AH, 0.0), (-5.0, AH + 0.6, -38.0), (-8.6, 4.8, -52.0),
           (-7.0, 10.2, -66.0), (0.4, 9.8, -36.0), (6.4, 6.4, -8.0), (7.8, 2.8, 6.0))
# Pelvis height per half cycle: sinking onto the strike, lowest as it takes the weight, rising
# off the push into the flight (the head moves about a pixel and a half).
RUN_HIP = (HIP - 2.2, HIP - 2.8, HIP - 1.9, HIP - 1.3)
RUN_PELVIS_X = -1.0
RUN_LEAN = 22.0


def run_pose(k: int) -> dict[str, Any]:
    """Cell k of the 8-cell side run."""
    phi = k / RUN_CELLS
    sw = math.cos(2.0 * math.pi * phi)            # +1: near leg forward, far arm forward
    py = RUN_HIP[k % 4]
    px = RUN_PELVIS_X
    nx, ny, nt = RUN_LEG[k % RUN_CELLS]
    fx, fy, ft = RUN_LEG[(k + RUN_CELLS // 2) % RUN_CELLS]
    pose = P(IDLE, pelvis=(px, py, 0.0), lean=RUN_LEAN, hip_lean=RUN_LEAN / 3.0, twist=-4.0 * sw,
             hip_yaw=4.0 * sw, head=(-13.0, 0.0, 0.0),
             foot_n=(px + nx, ny, 3.0), toe_n=nt, knee_n=(1.0, 0.0, 0.15), toe_yaw_n=0.0,
             foot_f=(px + fx, fy, -2.8), toe_f=ft, knee_f=(1.0, 0.0, -0.15), toe_yaw_f=0.0,
             elbow_f=(-1.0, -0.3, -0.5),
             shield_up=(0.5 + 0.06 * sw, 0.87, 0.0))
    # The hands are placed from the shoulders: the shield hand where the idle carries it (a touch
    # of swing), the far fist pumping from behind the hip to forward of the chest.
    sk = skeleton(pose)
    sn, sf = sk["shoulder_n"], sk["shoulder_f"]
    pose["hand_n"] = (float(sn[0]) + 3.6 - 0.6 * sw, float(sn[1]) - 8.6, float(sn[2]) + 1.0)
    pose["hand_f"] = (float(sf[0]) + 1.4 + 5.0 * sw, float(sf[1]) - 8.6 + 2.2 * sw, float(sf[2]) + 1.4)
    return pose

# Clip name -> cells in play order (int = a row-0 key, dict = a pose). The game sets the timing.
CLIPS: dict[str, list[Any]] = {
    "idle": [K["idle"], mix(IDLE, IDLE_OUT, 0.5), IDLE_OUT, mix(IDLE, IDLE_OUT, 0.5)],
    "ready": [K["ready"], mix(READY, READY_OUT, 0.5), READY_OUT, mix(READY, READY_OUT, 0.5)],
    "draw": [DRAW_1, DRAW_2, DRAW_3, K["idle"]],
    "parry": [PARRY_SNAP, K["parry"]],
    "parry_hit": [PARRY_HIT_1, PARRY_HIT_2, K["parry"]],
    "dodge": [DODGE_IN, K["dodge"], K["dodge"], DODGE_OUT],
    "jump_up": [JUMP_PUSH, JUMP_TUCK, K["jump"]],
    "jump_down": [K["jump"], JUMP_OPEN, JUMP_LAND],
    "hurt": [K["hurt"], K["hurt"], HURT_RECOIL, HURT_RECOVER],
    "stagger": [K["hurt"], STAGGER_1, STAGGER_1, STAGGER_2, STAGGER_3, HURT_RECOVER],
    "strike_windup": [STRIKE_W1, STRIKE_W2],
    "strike": [K["strike"], STRIKE_FOLLOW, STRIKE_RECOVER],
    "strike_alt_windup": [ALT_W1, ALT_W2],
    "strike_alt": [ALT_1, ALT_2, ALT_RECOVER],
    "strike_big_windup": [BIG_W1, BIG_W2],
    "strike_big": [BIG_1, BIG_2, BIG_RECOVER],
    "cast_windup": [CAST_W1, CAST_W2],
    "cast": [CAST_1, CAST_2, CAST_RECOVER],
    "leap": [LEAP_1, LEAP_2, LEAP_3],
    "fall": [K["hurt"], FALL_1, FALL_2, K["down"]],
    "get_up": [K["down"], GETUP_1, GETUP_2, K["idle"]],
    "victory": [VIC_1, VIC_2, VIC_3, VIC_4],
    "victory_hold": [VIC_4, VIC_4B],
    "run": [run_pose(k) for k in range(RUN_CELLS)],
}

_CAM: list[Camera] = []


def cell_cam() -> Camera:
    """The 48x56 cell camera: the 32x48 sheet camera padded, so the key poses keep their pixels."""
    if not _CAM:
        _CAM.append(cell_camera(Camera(*specs.HERO_FRAME), specs.HERO_CELL))
    return _CAM[0]


def render_cell(pose: dict[str, Any]) -> np.ndarray:
    """One 48x56 cell of Alder in `pose`."""
    return render_pose(pose, cell_cam())


def frame_ok(rgba: np.ndarray) -> bool:
    """The sprite contract: a clear top row, left and right column (room for the outline)."""
    s = rgba[..., 3] > 0
    return not (s[0, :].any() or s[:, 0].any() or s[:, -1].any())


def render_cells(poses: list[dict[str, Any]]) -> list[np.ndarray]:
    """Renders many cells (about a second each), in worker processes when it can."""
    if len(poses) < 8:
        return [render_cell(p) for p in poses]
    try:
        from concurrent.futures import ProcessPoolExecutor
        workers = max(1, min(8, (os.cpu_count() or 2) - 2))
        with ProcessPoolExecutor(max_workers=workers) as ex:
            return list(ex.map(render_cell, poses, chunksize=2))
    except (OSError, RuntimeError, ImportError):
        return [render_cell(p) for p in poses]


def clip_cells(names: list[str] | None = None) -> dict[str, list[Any]]:
    """CLIPS (or only `names`) rendered: every distinct pose once, in parallel."""
    from kit.clips import _norm
    spec = {n: CLIPS[n] for n in (names or CLIPS)}
    todo: dict[Any, dict[str, Any]] = {}
    for entries in spec.values():
        for e in entries:
            if isinstance(e, dict):
                todo.setdefault(_norm(e), e)
    done = dict(zip(todo, render_cells(list(todo.values()))))
    return render_clips(spec, lambda p: done[_norm(p)])


def clip_strips(keys: list[np.ndarray], cells: dict[str, list[Any]]) -> np.ndarray:
    """Every clip as one row of cells (int entries are the row-0 keys), for review pictures."""
    cols = max(len(c) for c in cells.values())
    blank = np.zeros((specs.HERO_CELL[1], specs.HERO_CELL[0], 4), dtype=np.uint8)
    rows = [hstack([keys[c] if isinstance(c, int) else c for c in cs] + [blank] * (cols - len(cs)))
            for cs in cells.values()]
    return np.concatenate(rows, axis=0)


def build(ctx) -> None:
    from kit.context import PREVIEW
    # 48x56 cells: the 32x48 camera padded, so the key poses keep their exact pixels.
    frames = [render_cell(POSES[name]) for name in specs.HERO_POSES]
    cells = clip_cells()
    bad = sorted({name for name, cs in cells.items() for c in cs
                  if isinstance(c, np.ndarray) and not frame_ok(c)})
    if bad:
        raise ValueError("alder: clip cells touch the cell edge (no outline room): %s" % ", ".join(bad))
    ctx.save_fighter("sprites/characters/alder.png", frames, cells, specs.HERO_CELL, specs.HERO_BODY_W,
                     "alder")
    # Every clip as a row of cells at game size and 3x (the GIFs cannot be reviewed everywhere).
    strips = clip_strips(frames, cells)
    ctx.extra("clips_1x.png", strips, scale=1)
    ctx.extra("clips_3x.png", strips, scale=3, frame_w=specs.HERO_CELL[0])
    sil = np.zeros_like(strips)
    sil[..., :3] = 24
    sil[..., 3] = np.where(strips[..., 3] > 0, 255, 0)
    ctx.extra("clips_silhouettes.png", sil, scale=2, frame_w=specs.HERO_CELL[0])
    por = render_portrait()
    ctx.save("sprites/portraits/alder.png", por)
    out = os.path.join(PREVIEW, ctx.module)
    _review(os.path.join(out, "review_portrait.png"), [por], cols=1, scale=8)
    _review(os.path.join(out, "review_sheet.png"), frames, cols=4, scale=6)
