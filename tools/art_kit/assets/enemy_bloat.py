"""The Bloat: a huge rot-swollen brute. A giant sagging pale belly is the main shape, with a
hunched purple back, a small fat head sunk between the shoulders (pale face, gaping mouth), stubby
clawed legs, short heavy arms ending in club fists, pustules and a few bile-green boils.

Sheet: sprites/enemies/bloat.png, a grid of 92x92 cells facing left (row 0 = the six key poses,
then one row per animation clip, data/clips/bloat.tres) and its 48x48 portrait.

The body is a small custom skeleton (pelvis, torso frame, shoulders, IK arms and legs), so the
clip cells (CLIPS) are POSES dicts blended with kit.rig.blend plus a few changed keys: a slow
heaving idle, a waddling walk, a swell-and-burst death and the Tier 2 belly wind-up.
"""
from __future__ import annotations

import os
from typing import Any

import numpy as np
from PIL import Image

from kit.color import mix
from kit.noise import fbm3
from kit.palette import M, Material
from kit.post import cleanup, contours, outline
from kit.render import Camera, Frame, line3d, render
from kit.rig import blend, two_bone
from kit.sdf import (Custom, Ellipsoid, Intersect, Node, Prim, RoundCone, SmoothUnion, Sphere, Subtract,
                     Union, basis, rot)
from kit.clips import render_clips
from kit.sheet import hstack
from kit.specs import ENEMY_FRAME, ENEMY_POSES, PORTRAIT

ID = "bloat"
S = ENEMY_FRAME[ID]

# --- Materials ---------------------------------------------------------------------------------
# The shared bloat ramps, lit a step darker than the defaults so the mass reads heavy rather
# than pastel. No dithering on the purple skin (checkerboard noise at 1x).

_FLESH = M["bloat_flesh"].colors
_PALE = M["bloat_pale"].colors
SKIN = Material(name="bloat_skin", colors=_FLESH, wrap=0.05, ao=0.9, hi=2.35)
# Forearms, shins and feet: the same ramp, lit darker still (rot pools in the limbs).
LIMB = Material(name="bloat_limb", colors=_FLESH, wrap=0.05, ao=0.9, hi=2.15)
# The club fists: calloused and paler than the arms (like the face and belly), so the hands
# read at 1x against the purple body; a separate material so the wrist seam can find them.
FIST = Material(name="bloat_fist", colors=[mix(p, f, 0.4) for p, f in zip(_PALE, _FLESH)], wrap=0.1, ao=0.9, hi=3.1)
# The belly: the pale ramp with one sickly olive step under it for the core shadow, and a soft
# terminator (wrap) so the shading bands curve with the form.
_OLIVE = mix(_PALE[0], "#5d6a2a", 0.42)
BELLY = Material(name="bloat_belly", colors=[_OLIVE] + _PALE, wrap=0.25, ao=0.8, lo=0.35, hi=3.75,
                 outline=M["bloat_pale"].outline)
# Belly blotches: the belly ramp nudged toward the purple skin (low contrast, same light index).
MOTTLE = Material(name="bloat_mottle", colors=[mix(c, _FLESH[min(i, 4)], 0.3) for i, c in enumerate(BELLY.colors)],
                  wrap=0.25, ao=0.8, lo=0.35, hi=3.75, outline=M["bloat_pale"].outline)
FACE = Material(name="bloat_face", colors=_PALE, wrap=0.2, ao=0.8, hi=3.3)
BRUISE = Material.make("bloat_bruise", "#6e4b78", wrap=0.1, ao=0.9, hi=3.0)
MOUTH = Material.make("bloat_mouth", "#3a1830", below=1, above=1, wrap=0.2, ao=0.1)
BONE = M["bone"]
BILE = M["bile"]
SAC = Material.make("bloat_sac", "#77763f", wrap=0.3)
GLOW = M["glow_rot"]
EYE = M["glow_amber"]
DUST = M["ash"]
DIRT = M["dirt"]


def _v(x: Any) -> np.ndarray:
    return np.asarray(x, dtype=float)


# --- Proportions (model units = sprite pixels) --------------------------------------------------

HIP_Y = 20.0          # pelvis height standing
THIGH = 10.0
SHIN = 9.5
ANKLE_H = 4.0
UPPER_ARM = 12.0      # short, heavy arms: the club fist adds about 11 past the wrist
FOREARM = 11.0
# Offsets from the pelvis in the torso frame (z mirrored for the far side).
SHOULDER = (-2.0, 36.0, 25.0)
HIP_W = 13.0
BELLY_C = (9.0, 13.0, 0.0)
BELLY_R = (29.5, 22.0, 27.5)
BELLY_SAG = 0.16       # how much wider the belly is low down than high up
HUMP_C = (-5.0, 39.0, 0.0)
HUMP_R = (16.5, 15.5, 21.5)
NECK = (13.0, 36.0, 0.0)
HEAD_R = (7.0, 6.0, 6.6)
FIST_C = 3.5           # fist centre past the wrist, along the forearm
FIST_R = (8.6, 7.6, 8.2)


# --- Poses ---------------------------------------------------------------------------------------
# Keys:
#   root (x, y, z) whole-body shift; pelvis (x, y, z) from root; lean (deg, + = top forward);
#   side (deg, + = top toward the viewer); squash (1 = normal, < 1 = the whole soft upper body
#   compressed by an impact, widening to keep its bulk); shrug (x, y, z) shoulder shift in the
#   torso frame (hunched forward / down); belly (sx, sy, sz) squash/stretch; belly_off (x, y, z)
#   extra belly shift in the torso frame; belly_tilt (deg, + = belly hangs back from the lean); ripple (0 .. 1 jiggle bands); head (pitch down, yaw,
#   tilt); jaw (0 closed .. 1 wide); teeth (1 all, 0.5 fangs and tusks, 0 tusks only);
#   hand_n / hand_f wrist targets (root space); elbow_n / elbow_f pole vectors;
#   foot_n / foot_f ankle targets (root space); knee_n / knee_f poles; toe_n / toe_f foot pitch
#   (+ = toes up); glow (0 dull boils .. 1 all swollen and blazing); eyes (0 squeezed shut .. 1
#   open); ground (1 = flesh flattened on the ground and an impact drawn under the fists).

# Every pose sets every key (missing ones come from here), so kit.rig.blend can mix any two.
DEFAULT_POSE: dict[str, Any] = dict(
    root=(0.0, 0.0, 0.0), pelvis=(0.0, HIP_Y, 0.0), lean=0.0, side=0.0, squash=1.0, shrug=(0.0, 0.0, 0.0),
    belly=(1.0, 1.0, 1.0), belly_off=(0.0, 0.0, 0.0), belly_tilt=0.0, ripple=0.0, head=(0.0, -32.0, 0.0), jaw=0.5,
    teeth=0.5,
    hand_n=(4.0, 38.0, 37.0), hand_f=(14.0, 42.0, -32.0),
    elbow_n=(-1.0, 0.0, 0.6), elbow_f=(-1.0, 0.0, -0.6),
    foot_n=(3.0, ANKLE_H, 20.0), foot_f=(8.0, ANKLE_H, -19.0),
    knee_n=(0.5, 0.0, 1.0), knee_f=(0.5, 0.0, -1.0), toe_n=0.0, toe_f=0.0,
    glow=0.3, eyes=1.0, ground=0.0,
)

_KEY_POSES: dict[str, dict[str, Any]] = {
    # Upright and heavy: head pushed forward, short arms held out from the belly's flanks.
    "idle": dict(
        lean=6.0, head=(6.0, -32.0, 0.0), jaw=0.6,
        hand_n=(-4.0, 42.0, 44.0), hand_f=(20.0, 44.0, -30.0),
        elbow_n=(-1.0, -0.2, 0.9), elbow_f=(-1.0, 0.0, -0.6),
        foot_n=(3.0, ANKLE_H, 20.0), foot_f=(8.0, ANKLE_H, -19.0),
        glow=0.3,
    ),
    # The tell: rears back, belly out, both fists high over the head, every boil blazing.
    "windup": dict(
        root=(3.0, 0.0, 0.0), pelvis=(-3.0, HIP_Y - 1.0, 0.0), lean=-14.0, belly=(1.06, 0.98, 1.03),
        belly_off=(4.0, 0.0, 0.0), head=(-20.0, -32.0, 0.0), jaw=1.0,
        hand_n=(-12.0, 71.0, 30.0), hand_f=(2.0, 69.0, -22.0),
        elbow_n=(-0.3, -0.2, 1.0), elbow_f=(-0.3, -0.2, -1.0),
        foot_n=(4.0, ANKLE_H, 20.0), foot_f=(2.0, ANKLE_H, -19.0),
        glow=1.0,
    ),
    # Waddling in belly first: the far foot planted ahead, the near one pushing off behind on its
    # toes, the arms counter-swinging (near back and down, far fist forward over the belly).
    "lunge": dict(
        root=(6.0, 0.0, 0.0), pelvis=(0.0, HIP_Y - 1.5, 0.0), lean=-6.0, side=4.0,
        belly=(1.05, 1.0, 1.0), belly_off=(6.0, 1.0, 0.0), head=(8.0, -32.0, 0.0), jaw=0.8,
        hand_n=(-18.0, 38.0, 32.0), hand_f=(16.0, 50.0, -26.0),
        elbow_n=(-1.0, 0.0, 0.5), elbow_f=(-1.0, -0.4, -0.5),
        foot_n=(-13.0, ANKLE_H + 3.0, 20.0), foot_f=(14.0, ANKLE_H, -18.0), toe_n=-38.0,
        knee_n=(0.5, 0.0, 1.0), knee_f=(0.6, 0.0, -1.0),
        glow=0.45,
    ),
    # The hit: belly thrown forward and flattened against the target, the near arm flung back
    # out of the way, the far fist driving in over the belly.
    "contact": dict(
        root=(-2.0, 0.0, 0.0), lean=18.0, belly=(0.88, 1.08, 1.06), belly_off=(15.0, 2.0, 0.0),
        head=(-10.0, -32.0, 0.0), jaw=1.0,
        hand_n=(-3.0, 47.0, 36.0), hand_f=(34.0, 52.0, -20.0),
        elbow_n=(-1.0, 0.3, 0.6), elbow_f=(-0.4, 0.6, -1.0),
        foot_n=(8.0, ANKLE_H, 20.0), foot_f=(-12.0, ANKLE_H, -19.0), toe_f=-20.0,
        glow=0.5,
    ),
    # Knocked back: rocks onto its heels, head snapped back, eyes shut, arms flung out and down,
    # the belly jiggling in two broad waves.
    "hurt": dict(
        root=(4.0, 0.0, 0.0), pelvis=(0.0, HIP_Y - 0.5, 0.0), lean=-20.0, side=-4.0,
        belly=(0.95, 1.07, 1.03), belly_off=(3.0, 0.0, 0.0), ripple=1.0,
        head=(2.0, -32.0, 12.0), jaw=0.45, teeth=0.0,
        hand_n=(-12.0, 40.0, 40.0), hand_f=(-2.0, 44.0, -40.0),
        elbow_n=(0.0, 1.0, 0.5), elbow_f=(0.0, 1.0, -0.5),
        foot_n=(4.0, ANKLE_H, 20.0), foot_f=(-4.0, ANKLE_H, -19.0), toe_n=15.0,
        glow=0.3, eyes=0.0,
    ),
    # Crashing down: squashed low and hunched forward, both club fists pounding the ground in
    # front (elbows out), the belly bulging forward under the chest.
    "slam": dict(
        root=(6.0, 0.0, 0.0), pelvis=(-6.0, 8.0, 0.0), lean=28.0, squash=0.8, shrug=(8.0, -2.0, -3.0),
        belly=(0.8, 0.85, 1.12), belly_off=(-12.0, -3.0, 0.0), belly_tilt=14.0,
        head=(-18.0, -32.0, 0.0), jaw=1.0,
        hand_n=(9.0, 12.0, 37.0), hand_f=(24.0, 14.0, -21.0),
        elbow_n=(0.3, 0.5, 1.0), elbow_f=(0.0, 0.3, -1.0),
        foot_n=(-4.0, ANKLE_H, 21.0), foot_f=(-10.0, ANKLE_H, -20.0),
        knee_n=(0.7, 0.0, 1.0), knee_f=(0.7, 0.0, -1.0),
        glow=0.6, ground=1.0,
    ),
}

POSES: dict[str, dict[str, Any]] = {k: {**DEFAULT_POSE, **v} for k, v in _KEY_POSES.items()}


# --- Skeleton -------------------------------------------------------------------------------------


def skeleton(pose: dict[str, Any]) -> dict[str, Any]:
    """Joint positions (root space) plus frames: T = torso, H = head, J = jaw, fist_R_* = fists."""
    sk: dict[str, Any] = {}
    root = _v(pose.get("root", (0.0, 0.0, 0.0)))
    pelvis = root + _v(pose.get("pelvis", (0.0, HIP_Y, 0.0)))
    T = rot(float(pose.get("side", 0.0)), 0.0, -float(pose.get("lean", 0.0)))
    sk["root"], sk["pelvis"], sk["T"] = root, pelvis, T
    q = float(pose.get("squash", 1.0))
    Q = _v((1.0, q, 1.0))
    wide = 1.0 / np.sqrt(q)
    sk["squash"] = q
    sk["belly"] = pelvis + T @ (_v(BELLY_C) * Q + _v(pose.get("belly_off", (0.0, 0.0, 0.0))))
    # The belly's own frame: it may hang back toward upright (gravity) when the torso leans.
    sk["B"] = T @ rot(0.0, 0.0, float(pose.get("belly_tilt", 0.0)))
    sk["belly_r"] = _v(BELLY_R) * _v(pose.get("belly", (1.0, 1.0, 1.0)))
    sk["hump"] = pelvis + T @ (_v(HUMP_C) * Q)
    sk["hump_r"] = _v(HUMP_R) * _v((wide, q, wide))
    sk["neck"] = pelvis + T @ (_v(NECK) * Q)
    hp, hy, ht = pose.get("head", (0.0, 0.0, 0.0))
    H = T @ rot(0.0, hy, -hp) @ rot(ht, 0.0, 0.0)
    sk["H"] = H
    sk["head"] = sk["neck"] + H @ _v((3.0, 5.0, 0.0))
    jaw = float(pose.get("jaw", 0.5))
    sk["J"] = H @ rot(0.0, 0.0, -(6.0 + 30.0 * jaw))
    sk["hinge"] = sk["head"] + H @ _v((-2.0, -1.5, 0.0))
    shrug = _v(pose.get("shrug", (0.0, 0.0, 0.0)))
    for s, sgn in (("n", 1.0), ("f", -1.0)):
        sh = pelvis + T @ _v((SHOULDER[0] + shrug[0], SHOULDER[1] * q + shrug[1],
                              sgn * (SHOULDER[2] * wide + shrug[2])))
        hand_t = _v(pose.get("hand_" + s, (6.0, 30.0, sgn * 30.0))) + root
        pole = _v(pose.get("elbow_" + s, (-1.0, 0.0, sgn)))
        elbow, hand = two_bone(sh, hand_t, UPPER_ARM, FOREARM, pole)
        sk["shoulder_" + s], sk["elbow_" + s], sk["hand_" + s] = sh, elbow, hand
        # The fist's back faces up and out (away from the body), its knuckles lead.
        sk["fist_R_" + s] = basis(hand - elbow, (0.0, 1.0, 0.45 * sgn))
        hip = pelvis + _v((0.0, -1.5, sgn * HIP_W))
        foot_t = _v(pose.get("foot_" + s, (0.0, ANKLE_H, sgn * 14.0))) + root
        kpole = _v(pose.get("knee_" + s, (0.5, 0.0, sgn)))
        knee, ankle = two_bone(hip, foot_t, THIGH, SHIN, kpole)
        sk["hip_" + s], sk["knee_" + s], sk["ankle_" + s] = hip, knee, ankle
        sk["foot_R_" + s] = rot(0.0, sgn * -14.0, float(pose.get("toe_" + s, 0.0)))
    return sk


# --- Painting skin patterns onto SDF parts ---------------------------------------------------------


class Painted(Node):
    """A body whose surface material changes by pattern (blotches, pale belly, face) without
    changing its shape: the distance comes from `base`, the part id is swapped by each layer's
    mask. Pattern coordinates are local to the base leaf that was hit (its own position and
    axes), so blotches stick to the body from pose to pose."""

    def __init__(self, base: Node, layers: list[tuple[Prim, Any]]) -> None:
        self.base = base
        self.layers = layers  # (material holder prim, mask(Q, leaf) -> bool array)
        self._leaves = base.leaves()

    def eval(self, P):
        d, p = self.base.eval(P)
        near = np.nonzero(d < 1.0)[0]
        if near.size == 0 or not self.layers:
            return d, p
        pn = p[near]
        out = pn.copy()
        by_part = {leaf.part: leaf for leaf in self._leaves}
        for part in np.unique(pn):
            leaf = by_part.get(int(part))
            if leaf is None:
                continue
            sel = np.nonzero(pn == part)[0]
            Q = _pattern_local(leaf, P[near[sel]])
            for holder, mask_fn in self.layers:
                m = mask_fn(Q, leaf)
                if m is not None:
                    out[sel[m]] = holder.part
        p = p.copy()
        p[near] = out
        return d, p

    def leaves(self):
        return self._leaves + [h for h, _ in self.layers]


def _pattern_local(leaf: Prim, P: np.ndarray) -> np.ndarray:
    if isinstance(leaf, RoundCone):
        return (P - leaf.a) @ basis(leaf.b - leaf.a)
    return (P - leaf.pos) @ leaf.R


def _holder(mat: Material, group: str, name: str = "") -> Prim:
    return Sphere(mat, (0.0, -1e5, 0.0), 0.0, group=group, name=name)


def _seed(name: str) -> int:
    return sum((i + 1) * ord(c) for i, c in enumerate(name)) % 997


def _pale_field(Q: np.ndarray) -> np.ndarray:
    """> 0 on the pale front and underside of the belly (ragged edge), in belly-local units."""
    q = Q / _v(BELLY_R)
    t = q[:, 0] * 0.95 - q[:, 1] * 0.45 + q[:, 2] * 0.2
    return t - 0.12 - 0.22 * fbm3(Q * 0.16, 41, octaves=2)


def _layer_pale(Q, leaf):
    return _pale_field(Q) > 0 if leaf.name == "belly" else None


def _layer_bruise(Q, leaf):
    if leaf.name.startswith(("fist", "knuckle")):
        return None
    if leaf.name == "hump":
        return fbm3(Q * 0.1, 11 + _seed(leaf.name), octaves=2) > 0.12
    m = fbm3(Q * 0.1, 11 + _seed(leaf.name), octaves=2) > 0.3
    if leaf.name == "belly":
        m &= _pale_field(Q) <= 0
    return m


def _layer_mottle(Q, leaf):
    """Round, soft blotches on the pale belly (one octave of low-frequency noise)."""
    if leaf.name != "belly":
        return None
    return (fbm3(Q * 0.09, 29, octaves=1) > 0.42) & (_pale_field(Q) > 0.1)


def _layer_face(Q, leaf):
    """The pale face on the front of the purple cranium, below the brow."""
    if leaf.name != "cran":
        return None
    return (Q[:, 0] > 2.6 + 0.35 * np.abs(Q[:, 2])) & (Q[:, 1] < 1.6)


def _layer_head_bruise(Q, leaf):
    if leaf.name != "cran":
        return None
    return (fbm3(Q * 0.3, 23, octaves=2) > 0.3) & ~_layer_face(Q, leaf)


# --- Model -------------------------------------------------------------------------------------------

# Boils: (on "belly" or "hump", direction from that blob's centre in the torso frame, radius,
# glows even at rest).
BOILS = [
    ("belly", (-0.25, 0.55, 0.8), 2.8, True),
    ("belly", (0.15, -0.2, 0.97), 2.3, False),
    ("hump", (-0.5, 0.45, 0.72), 2.6, True),
    ("belly", (-0.6, -0.05, 0.8), 2.1, False),
    ("hump", (0.15, 0.75, 0.62), 2.0, False),
]

# Teeth: upper fangs and pegs (z, length, x shift, min `teeth` to show) and lower teeth
# (z, length, root radius, min `teeth`); the outer lower two are tusks and always show.
TEETH_TOP = [(-2.3, 2.0, 0.1, 0.4), (2.3, 2.0, 0.1, 0.4), (-0.6, 1.1, 0.25, 0.9), (1.0, 0.9, 0.25, 0.9)]
TEETH_LOW = [(-3.3, 2.9, 0.85, 0.0), (3.3, 2.9, 0.85, 0.0), (-0.9, 1.0, 0.5, 0.9), (1.0, 1.2, 0.5, 0.9)]

PUSTULES = [
    ("hump", (-0.55, 0.75, 0.35), 2.4),
    ("hump", (-0.85, 0.35, 0.4), 2.1),
    ("hump", (-0.2, 0.9, 0.35), 1.9),
    ("belly", (-0.75, 0.3, 0.6), 1.8),
]


class Rippled(Ellipsoid):
    """The belly: an ellipsoid that sags (wider low down, like a hanging gut instead of an egg)
    with optional jiggle bands (hurt): two broad waves running round it."""

    def __init__(self, *a, ripple: float = 0.0, sag: float = 0.0, **kw) -> None:
        super().__init__(*a, **kw)
        self.ripple = ripple
        self.sag = sag

    def dist_local(self, Q):
        if self.sag:
            t = np.clip(-Q[:, 1] / self.radii[1], -1.0, 1.0)
            f = (1.0 + self.sag * t)[:, None]
            Qs = Q * np.concatenate([1.0 / f, np.ones_like(f), 1.0 / f], axis=1)
            d = super().dist_local(Qs) * (1.0 - self.sag)
        else:
            d = super().dist_local(Q)
        if self.ripple:
            # Two fat rolls bulging out above and below a groove across the middle; strongest on
            # the front, none at the back.
            front = np.clip(Q[:, 0] / self.radii[0] + 0.3, 0.0, 1.0)
            d = d + 1.4 * self.ripple * front * np.cos(Q[:, 1] * (2.0 * np.pi / 22.0) - 0.4)
        return d


def _sagged(local: np.ndarray, radii: np.ndarray, sag: float) -> np.ndarray:
    """A point on the plain belly ellipsoid moved onto the sagging belly (see Rippled)."""
    f = 1.0 + sag * float(np.clip(-local[1] / radii[1], -1.0, 1.0))
    return local * _v((f, 1.0, f))


def _on_surface(center: np.ndarray, radii: np.ndarray, R: np.ndarray, d: Any,
                sag: float = 0.0) -> tuple[np.ndarray, np.ndarray]:
    dv = _v(d) / np.linalg.norm(d)
    p = center + R @ _sagged(dv * radii, radii, sag)
    n = R @ (dv / radii)
    return p, n / np.linalg.norm(n)


def _arm(sk: dict[str, Any], s: str) -> tuple[Node, Node, list[Node]]:
    """One arm: shoulder, upper arm and a forearm that thickens toward the hand (blended into
    the body), the club fist with three knuckles (a hard join at the wrist, so it never melts into
    the belly) and its short bone nails."""
    g = "arm_" + s
    sh, el, hd = sk["shoulder_" + s], sk["elbow_" + s], sk["hand_" + s]
    R = sk["fist_R_" + s]
    c = hd + R @ _v((FIST_C, 0.0, 0.0))
    flesh = SmoothUnion(
        Sphere(SKIN, sh, 7.4, group=g, name="delt_" + s),
        RoundCone(SKIN, sh, el, 6.6, 5.6, group=g, name="upper_" + s),
        RoundCone(LIMB, el, hd, 5.0, 6.3, group=g, name="fore_" + s),
        k=1.5,
    )
    fist = SmoothUnion(
        Ellipsoid(FIST, c, FIST_R, R=R, group=g, name="fist_" + s),
        *[Sphere(FIST, c + R @ _v((6.4, 2.8, z)), 2.7, group=g, name="knuckle_" + s) for z in (-4.4, 0.0, 4.4)],
        k=1.0,
    )
    nails = [RoundCone(BONE, c + R @ _v((7.4, -2.2, z)), c + R @ _v((10.4, -3.6, z)), 1.3, 0.55, group="claw")
             for z in (-3.8, 0.2, 4.0)]
    return flesh, fist, nails


def model(pose: dict[str, Any], sk: dict[str, Any] | None = None) -> Node:
    sk = sk or skeleton(pose)
    T, H, J = sk["T"], sk["H"], sk["J"]
    jaw = float(pose.get("jaw", 0.5))
    glow = float(pose.get("glow", 0.3))
    teeth = float(pose.get("teeth", 0.5))

    # Flesh: one smooth mass (belly, hump, pelvis, neck fat, legs); arms blend in at the shoulder.
    belly = Rippled(SKIN, sk["belly"], sk["belly_r"], R=sk["B"], group="body", name="belly",
                    ripple=float(pose.get("ripple", 0.0)), sag=BELLY_SAG)
    hump = Ellipsoid(SKIN, sk["hump"], sk["hump_r"], R=T, group="body", name="hump")
    pelvis = Ellipsoid(SKIN, sk["pelvis"] + T @ _v((0.0, 2.0, 0.0)), (12.0, 9.0, 14.0), R=T, group="body", name="pelvis")
    neck = Ellipsoid(SKIN, sk["neck"] + T @ _v((-4.0, 1.5, 0.0)), (8.5, 7.5, 10.0), R=T, group="body", name="neckfat")
    legs: list[Node] = []
    claws: list[Node] = []
    arms: list[Node] = []
    fists: list[Node] = []
    for s in ("n", "f"):
        arm, fist, nails = _arm(sk, s)
        arms.append(arm)
        fists.append(fist)
        claws += nails
        gl = "leg_" + s
        legs.append(RoundCone(SKIN, sk["hip_" + s], sk["knee_" + s], 8.6, 7.2, group=gl, name="thigh_" + s))
        legs.append(RoundCone(LIMB, sk["knee_" + s], sk["ankle_" + s], 7.0, 6.2, group=gl, name="shin_" + s))
        fr = sk["foot_R_" + s]
        legs.append(Ellipsoid(LIMB, sk["ankle_" + s] + fr @ _v((4.0, -0.5, 0.0)), (9.0, 3.5, 7.0), R=fr, group=gl,
                              name="foot_" + s))
        for tz in (-3.8, 0.0, 3.8):
            tip = sk["ankle_" + s] + fr @ _v((14.4, -2.9, tz))
            claws.append(RoundCone(BONE, tip + fr @ _v((-2.6, 0.9, 0.0)), tip, 1.5, 0.6, group="claw"))

    flesh = SmoothUnion(SmoothUnion(SmoothUnion(hump, pelvis, neck, k=6.0), belly, k=3.5), *legs, k=3.0)
    if pose.get("ground", 0.0):
        # Squashed flat against the ground (slam): the belly spreads instead of sinking in.
        flesh = Intersect(flesh, Custom(SKIN, lambda Q: 0.6 - Q[:, 1]))
    body = Painted(
        SmoothUnion(flesh, *arms, k=2.5),
        [
            (_holder(BELLY, "body", "belly_pale"), _layer_pale),
            (_holder(BRUISE, "body"), _layer_bruise),
            (_holder(MOTTLE, "body", "belly_mottle"), _layer_mottle),
        ],
    )

    # Head: a small fat head sunk between the shoulders: purple cranium, a heavy frowning brow,
    # a pale face with fat jowls pushing up under slit eyes, a hanging jaw and a dark gaping mouth.
    hc = sk["head"]
    cran = Ellipsoid(SKIN, hc, HEAD_R, R=H, group="head", name="cran")
    brows = [Ellipsoid(SKIN, hc + H @ _v((4.6, 1.9, sgn * 2.6)), (2.6, 1.5, 3.4), R=H @ rot(-sgn * 18.0, 0.0, 0.0),
                       group="head", name="brow") for sgn in (1.0, -1.0)]
    jowls = [Ellipsoid(FACE, hc + H @ _v((3.4, -1.9, sgn * 4.4)), (4.4, 4.0, 3.6), R=H, group="head",
                       name="jowl") for sgn in (1.0, -1.0)]
    jaw_e = Ellipsoid(FACE, sk["hinge"] + J @ _v((5.4, -3.0, 0.0)), (6.0, 3.0, 6.0), R=J, group="head", name="jaw")
    head = SmoothUnion(cran, *brows, *jowls, jaw_e, k=1.5)
    cav_c = hc + H @ _v((6.6, -2.9 - 2.4 * jaw, 0.0))
    cavity = Ellipsoid(MOUTH, cav_c, (4.4, 1.5 + 2.6 * jaw, 3.9), R=H, group="mouth")
    head = Subtract(head, cavity, k=0.5, b_material=True)
    eyes_open = float(pose.get("eyes", 1.0)) > 0.5
    for sgn in (1.0, -1.0) if eyes_open else ():
        sock = Sphere(MOUTH, hc + H @ _v((6.6, 0.5, sgn * 2.8)), 1.5, group="mouth")
        head = Subtract(head, sock, k=0.3, b_material=True)
    head = Painted(head, [(_holder(FACE, "head"), _layer_face), (_holder(BRUISE, "head"), _layer_head_bruise)])

    parts: list[Node] = [body, *fists, head, *claws]

    # Eyes: small amber slits deep under the brow (drawn as dark lines when shut, see overlays).
    if eyes_open:
        for sgn in (1.0, -1.0):
            e = hc + H @ _v((5.6, 0.3, sgn * 2.8))
            r = float(pose.get("eye_r", 0.95))
            parts.append(Ellipsoid(EYE, e, (r * 0.8, r * 0.75, r * 1.2), R=H, group="eye", thin=True))

    # Teeth: two crooked upper fangs (plus small pegs), two tusks jutting up from the lower jaw.
    for z, ln, dx, need in TEETH_TOP:
        if teeth < need:
            continue
        top = hc + H @ _v((6.6 + dx, -2.1, z))
        parts.append(RoundCone(BONE, top, top + H @ _v((0.25, -ln, 0.0)), 0.65, 0.3, group="teeth", thin=True))
    for z, ln, r, need in TEETH_LOW:
        if teeth < need:
            continue
        bot = sk["hinge"] + J @ _v((10.0 - 0.15 * abs(z), -1.4, z))
        parts.append(RoundCone(BONE, bot, bot + J @ _v((0.4, ln, 0.15 * z)), r, 0.3, group="teeth", thin=True))

    # Boils: a shaded bile sac with a glowing core that swells with `glow`; pale pustules.
    blobs = {"belly": (sk["belly"], sk["belly_r"], sk["B"]), "hump": (sk["hump"], sk["hump_r"], T)}
    for i, (where, d, r, lit) in enumerate(BOILS):
        c, rr, R = blobs[where]
        p, n = _on_surface(c, rr, R, d, BELLY_SAG if where == "belly" else 0.0)
        on = lit or glow >= 0.4 + 0.12 * i
        rad = r * (1.0 + 0.45 * glow)
        parts.append(Sphere(BILE if on else SAC, p, rad, group="boil"))
        if on:
            core = rad * (0.45 + 0.45 * glow)
            parts.append(Sphere(GLOW, p + n * (rad - core * 0.7), core, group="boil"))
    for where, d, r in PUSTULES:
        c, rr, R = blobs[where]
        p, n = _on_surface(c, rr, R, d, BELLY_SAG if where == "belly" else 0.0)
        parts.append(Sphere(FACE, p + n * 0.4, r, group="pus"))
    return Union(*parts)


# --- Rendering ---------------------------------------------------------------------------------------

# View point at the bottom-centre pixel: centres the idle body and puts the lowest point of the
# near foot (which the camera's pitch pushes below the y = 0 line) on the second-to-last row.
CAM_CX = -6.5
CAM_CY = -5.5


def camera() -> Camera:
    return Camera(S, S, face="left", cx=CAM_CX, cy=CAM_CY)


# Belly veins: polylines of (azimuth, elevation) degrees on the belly ellipsoid (torso frame;
# azimuth 0 = straight ahead, 90 = toward the viewer), creeping from the purple flank into the
# lit pale front. A branch is just another path starting on its main vein.
VEINS = [
    [(70, 28), (66, 26), (62, 25), (58, 22), (55, 18), (53, 14)],
    [(62, 25), (59, 30), (55, 32)],
    [(78, 2), (74, -1), (70, -1), (66, -4), (63, -8)],
]


def _belly_point(sk: dict[str, Any], az: float, el: float, lift: float = 0.25) -> np.ndarray:
    a, e = np.radians(az), np.radians(el)
    d = _v((np.cos(e) * np.cos(a), np.sin(e), np.cos(e) * np.sin(a)))
    return sk["belly"] + sk["B"] @ _sagged(d * (sk["belly_r"] + lift), sk["belly_r"], BELLY_SAG)


# The navel (azimuth, elevation on the belly, as for VEINS): a dark dimple that makes the big
# pale shape read as a gut, not an egg.
NAVEL = (38.0, -8.0)


def _is_belly(fr: Frame, p: int) -> bool:
    return p >= 0 and (fr.mats[p] is BELLY or fr.mats[p] is MOTTLE)


def _is_flesh(fr: Frame, p: int) -> bool:
    return p >= 0 and any(fr.mats[p] is m for m in (SKIN, LIMB, BRUISE))


def _paint_navel(fr: Frame, cam: Camera, sk: dict[str, Any]) -> None:
    x0, y0, d0 = cam.project(_belly_point(sk, *NAVEL))
    x, y = int(np.floor(x0)), int(np.floor(y0))
    dark = fr.add_part(BRUISE, "body")
    # (dx, dy, part or None = shift the belly colour, ramp index or shift): a shadowed upper
    # fold, a dark hole and a lit lower lip.
    cells = ((0, -1, None, -1), (1, -1, None, -1),
             (0, 0, dark, 0), (1, 0, dark, 1),
             (0, 1, None, 1), (1, 1, None, 1))
    for dx, dy, part, v in cells:
        px, py = x + dx, y + dy
        if not (0 <= px < fr.W and 0 <= py < fr.H):
            continue
        p = fr.part[py, px]
        if not _is_belly(fr, p) or fr.depth[py, px] < d0 - 1.5:
            continue
        if part is None:
            fr.idx[py, px] = max(0, min(fr.mats[p].top(), fr.idx[py, px] + v))
        else:
            fr.part[py, px], fr.idx[py, px] = part, v


def _paint_vein(fr: Frame, cam: Camera, pts: list[np.ndarray]) -> None:
    """A 1-pixel vein over the lit part of the visible belly only, one shade darker than the skin
    under it (same hue), so it reads as a soft vein, not a crack."""
    proj = [cam.project(p) for p in pts]
    for (x0, y0, d0), (x1, y1, d1) in zip(proj, proj[1:]):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for k in range(n + 1):
            u = k / n
            x, y = int(np.floor(x0 + (x1 - x0) * u)), int(np.floor(y0 + (y1 - y0) * u))
            if not (0 <= x < fr.W and 0 <= y < fr.H):
                continue
            p = fr.part[y, x]
            if not _is_belly(fr, p) or fr.depth[y, x] < d0 + (d1 - d0) * u - 1.5 or fr.idx[y, x] < 3:
                continue
            fr.idx[y, x] -= 1


def _paint_crease(fr: Frame) -> None:
    """The fat overhang: where the belly hangs over the pelvis and legs, the flesh right under its
    rim is a dark crease and the rim itself catches a lit lip."""
    crease: list[tuple[int, int]] = []
    lip: list[tuple[int, int]] = []
    for y in range(1, fr.H - 1):
        for x in range(fr.W):
            p, q = fr.part[y, x], fr.part[y - 1, x]
            if p < 0 or not _is_belly(fr, q) or _is_belly(fr, p):
                continue
            if not _is_flesh(fr, p) or fr.depth[y - 1, x] > fr.depth[y, x] - 0.5:
                continue
            crease.append((x, y))
            lip.append((x, y - 1))
    for x, y in crease:
        fr.idx[y, x] = 0
        p = fr.part[y + 1, x]
        if _is_flesh(fr, p):
            fr.idx[y + 1, x] = max(0, min(fr.idx[y + 1, x], 1))
    for x, y in lip:
        fr.idx[y, x] = min(fr.mats[fr.part[y, x]].top(), fr.idx[y, x] + 1)


def _paint_fists(fr: Frame) -> None:
    """A dark seam where each club fist meets its forearm, and a dark edge on whatever lies
    behind a fist (the pale fists must not melt into the pale belly)."""
    seam, edge = [], []
    for y in range(1, fr.H - 1):
        for x in range(1, fr.W - 1):
            p = fr.part[y, x]
            if p < 0 or fr.mats[p] is FIST or fr.mats[p] is BONE:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = fr.part[y + dy, x + dx]
                if q < 0 or fr.mats[q] is not FIST:
                    continue
                if fr.mats[p] is LIMB and fr.depth[y, x] < fr.depth[y + dy, x + dx] + 3.0:
                    seam.append((x, y))
                    break
                if fr.depth[y, x] > fr.depth[y + dy, x + dx] + 1.0:
                    edge.append((x, y))
                    break
    for x, y in seam:
        fr.idx[y, x] = 0
    for x, y in edge:
        fr.fixed[y][x] = fr.mats[fr.part[y, x]].outline


def _paint_impact(fr: Frame, cam: Camera, sk: dict[str, Any]) -> None:
    """Ground cracks and dust kicked up round both fists (slam)."""
    for s, sgn in (("n", 1.0), ("f", -1.0)):
        c = sk["hand_" + s] + sk["fist_R_" + s] @ _v((FIST_C, 0.0, 0.0))
        g = _v((c[0], 0.0, c[2]))
        for ang, ln in ((150.0, 9.0), (195.0, 7.0), (110.0, 6.0)):
            a = np.radians(ang)
            d = _v((np.cos(a), 0.0, np.sin(a) * sgn))
            pts = [g + d * 5.0, g + d * (5.0 + ln * 0.5) + _v((0.0, 0.0, 1.2 * sgn)), g + d * (5.0 + ln)]
            line3d(fr, cam, pts, DIRT, 0, group="crack", depth_bias=0.5)
        # Dust puffs at the fist's sides, on the ground.
        dust = fr.add_part(DUST, "dust")
        for off in ((-9.0, 2.0, 0.0), (9.5, 1.5, 3.0 * sgn)):
            px, py, pd = cam.project(g + _v(off))
            x, y = int(np.floor(px)), int(np.floor(py))
            for dx, dy, i in ((0, 0, 3), (1, 0, 2), (-1, 0, 2), (0, -1, 4), (1, -1, 3)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < fr.W and 0 <= yy < fr.H - 1 and fr.part[yy, xx] < 0:
                    fr.put(xx, yy, dust, i, pd)


def overlays(fr: Frame, cam: Camera, pose: dict[str, Any], sk: dict[str, Any]) -> None:
    """Hand-placed bits drawn over the render: belly crease, veins and navel, wrist seams, shut
    eyes, bile drool from the lower lip and the slam's impact."""
    _paint_crease(fr)
    for path in VEINS:
        _paint_vein(fr, cam, [_belly_point(sk, az, el) for az, el in path])
    _paint_navel(fr, cam, sk)
    _paint_fists(fr)
    H, hc = sk["H"], sk["head"]
    if float(pose.get("eyes", 1.0)) <= 0.5:
        for sgn in (1.0, -1.0):
            e = hc + H @ _v((6.2, 0.2, sgn * 2.8))
            line3d(fr, cam, [e + H @ _v((0.0, 0.0, -1.1)), e + H @ _v((0.0, 0.0, 1.1))], MOUTH, 0,
                   group="mouth", depth_bias=2.0)
    jaw = float(pose.get("jaw", 0.5))
    lip = sk["hinge"] + sk["J"] @ _v((10.0, -2.6, 1.6))
    drop = 3.0 + 3.0 * jaw
    line3d(fr, cam, [lip, lip + _v((0.4, -drop, 0.2))], BILE, [3], group="drool", depth_bias=2.5)
    if float(pose.get("ground", 0.0)) > 0.5:
        _paint_impact(fr, cam, sk)
    # Phase 10 clip cells only (the row-0 keys never set these keys).
    if float(pose.get("dust", 0.0)) > 0.0:
        _paint_dust(fr, cam, sk, float(pose["dust"]))
    if float(pose.get("burst", 0.0)) > 0.0:
        _paint_burst(fr, cam, sk, float(pose["burst"]))


# The slam's second cell: dust thrown up at both ends of the body on the ground (screen offsets
# from the body's ground footprint ends, pixels outward and up, and the puff radius).
DUST_PUFFS = [(1.0, 3.0, 3.2), (-2.0, 8.0, 2.4), (4.0, 9.0, 1.8), (6.0, 3.0, 2.0), (1.0, 13.0, 1.4)]


def _paint_dust(fr: Frame, cam: Camera, sk: dict[str, Any], amount: float) -> None:
    """Round puffs of ash at both ends of the body's footprint, lit on top, only on clear
    pixels (the body stays in front)."""
    solid = fr.part >= 0
    ys, xs = np.nonzero(solid[fr.H - 8:])
    if len(xs) == 0:
        return
    x0, x1 = xs.min(), xs.max()
    dust = fr.add_part(DUST, "dust")
    ground = fr.H - 3
    for side, end in ((-1, x0), (1, x1)):
        for dx, dy, r in DUST_PUFFS:
            px, py, r = end + side * dx * amount, ground - dy * amount, r * amount
            for yy in range(int(py - r) - 1, int(py + r) + 2):
                for xx in range(int(px - r) - 1, int(px + r) + 2):
                    d = np.hypot(xx + 0.5 - px, (yy + 0.5 - py) * 1.15)
                    if d > r or not (2 <= xx < fr.W - 2 and 2 <= yy < fr.H - 2) or solid[yy, xx]:
                        continue
                    i = 4 if yy + 0.5 < py - r * 0.35 else (3 if yy + 0.5 < py + r * 0.3 else 1)
                    fr.put(xx, yy, dust, i, -1e5)


# Death: glowing splits across the stretched gut (paths of azimuth, elevation on the belly as for
# VEINS, and the burst share at which each one opens), and spores spraying out of the body
# (screen offsets from the belly's centre, pixels, and the share they appear at).
BURST_CRACKS = [
    ([(30, 30), (36, 22), (33, 14), (40, 6), (37, -2)], 0.0),
    ([(52, 12), (58, 4), (55, -6), (61, -14)], 0.0),
    ([(18, -10), (24, -18), (20, -26)], 0.6),
    ([(42, 36), (50, 30), (48, 24)], 0.6),
    ([(64, 26), (70, 18)], 0.8),
]
BURST_SPORES = [(-34, -6, 0.6), (-30, -22, 0.8), (-22, -34, 0.6), (-8, -40, 0.9), (-38, 8, 0.9),
                (-26, 20, 0.8), (6, -42, 1.0), (-40, -14, 1.0), (16, -36, 0.9), (-14, 28, 1.0),
                (-37, -30, 1.0), (-2, -34, 1.0), (-31, 2, 1.0), (24, -28, 1.0), (-42, 18, 1.0)]


def _paint_burst(fr: Frame, cam: Camera, sk: dict[str, Any], amount: float) -> None:
    """The gut splitting with rot-light: glowing cracks over the visible belly (a dark seam
    beside each) and, at a full burst, spores flung out round the body."""
    glow = fr.add_part(GLOW, "burst")
    seam = fr.add_part(BRUISE, "burst")
    for path, need in BURST_CRACKS:
        if amount < need:
            continue
        pts = [cam.project(_belly_point(sk, az, el)) for az, el in path]
        for (x0, y0, d0), (x1, y1, d1) in zip(pts, pts[1:]):
            n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
            for k in range(n + 1):
                u = k / n
                x, y = int(np.floor(x0 + (x1 - x0) * u)), int(np.floor(y0 + (y1 - y0) * u))
                if not (1 <= x < fr.W - 1 and 1 <= y < fr.H - 1):
                    continue
                if not _is_belly(fr, fr.part[y, x]) and fr.mats[fr.part[y, x]] is not GLOW:
                    continue
                if fr.depth[y, x] < d0 + (d1 - d0) * u - 2.0:
                    continue
                fr.part[y, x], fr.idx[y, x] = glow, GLOW.top()
                if _is_belly(fr, fr.part[y, x + 1]):
                    fr.part[y, x + 1], fr.idx[y, x + 1] = seam, 0
    if amount < 0.6:
        return
    bx, by, _ = cam.project(sk["belly"])
    for dx, dy, need in BURST_SPORES:
        if amount < need:
            continue
        x, y = int(bx + dx), int(by + dy)
        big = ((-1, 0, 1), (0, -1, 1), (1, 1, 0)) if need >= 0.9 else ()
        for ddx, ddy, i in ((0, 0, GLOW.top()), (1, 0, 2), (0, 1, 2)) + big:
            xx, yy = x + ddx, y + ddy
            if 2 <= xx < fr.W - 2 and 2 <= yy < fr.H - 2 and fr.part[yy, xx] < 0:
                fr.put(xx, yy, glow, i, -1e6)


def render_frame(pose: dict[str, Any], cam: Camera) -> Frame:
    sk = skeleton(pose)
    fr = render(model(pose, sk), cam)
    overlays(fr, cam, pose, sk)
    return fr


def despeckle(fr: Frame) -> None:
    """Removes single pixels whose eight neighbours all share one other colour (lone specks of
    the blotch patterns); the kit's cleanup only looks at four neighbours of the same part."""
    col = [[fr.mats[p].colors[i] if p >= 0 else None for p, i in zip(rp, ri)] for rp, ri in zip(fr.part, fr.idx)]
    for y in range(1, fr.H - 1):
        for x in range(1, fr.W - 1):
            c = col[y - 1][x - 1]
            if col[y][x] is None or c is None or c == col[y][x]:
                continue
            if all(col[y + dy][x + dx] == c for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx):
                fr.part[y, x], fr.idx[y, x] = fr.part[y, x - 1], fr.idx[y, x - 1]


def finish(fr: Frame) -> np.ndarray:
    """The kit's finish() chain (contours, cleanup, outline) with despeckle() before the outline."""
    contours(fr, 2.5, 2)
    cleanup(fr)
    despeckle(fr)
    outline(fr)
    return fr.rgba()


def render_pose(pose: dict[str, Any], cam: Camera | None = None) -> np.ndarray:
    """One finished RGBA frame for any pose dict (a key pose or a blend of two)."""
    return finish(render_frame(pose, cam or camera()))


def portrait() -> np.ndarray:
    """48x48 close-up of the head in 3/4 view facing left, mouth agape (two fangs, two tusks),
    the jowls, neck fat and a boil-studded shoulder filling the lower right. Rendered at 2.4x
    the sprite's detail, so the eyes are made smaller and the belly's dithering is turned off
    (its checkerboard would be noise this close)."""
    pose = {**POSES["idle"], "jaw": 0.85, "head": (4.0, -16.0, 0.0), "eye_r": 0.75, "teeth": 0.5}
    sk = skeleton(pose)
    scale = 0.42
    at = (21.0, 20.0)  # where the head centre lands in the portrait (pixels)
    v = Camera(PORTRAIT, PORTRAIT, face="left", scale=scale).view(sk["head"])
    cam = Camera(PORTRAIT, PORTRAIT, face="left", scale=scale,
                 cx=v[0] - (at[0] - PORTRAIT / 2) * scale, cy=v[1] - (PORTRAIT - 0.5 - at[1]) * scale)
    dither = BELLY.dither
    try:
        BELLY.dither = False
        fr = render(model(pose, sk), cam)
    finally:
        BELLY.dither = dither
    overlays(fr, cam, pose, sk)
    return finish(fr)


def _on_dark(rgba: np.ndarray, color: tuple[int, int, int] = (0x1e, 0x1a, 0x24)) -> np.ndarray:
    out = np.zeros_like(rgba)
    out[..., :3] = color
    out[..., 3] = 255
    solid = rgba[..., 3] > 0
    out[solid, :3] = rgba[solid, :3]
    return out


# --- Animation clips (phase 10, plan 4.2) ----------------------------------------------------------
# Every in-between is a pose dict built from the key poses with kit.rig.blend plus a few changed
# keys, so it keeps the rig's proportions and the camera's fixed floor (feet stay put). Row 0 keys
# are referenced by index (IDLE 0, WINDUP 1, LUNGE 2, CONTACT 3, HURT 4, SLAM 5).

K_IDLE, K_WINDUP, K_LUNGE, K_CONTACT, K_HURT, K_SLAM = range(6)


def _p(base: dict[str, Any], **kw: Any) -> dict[str, Any]:
    """`base` with some keys changed (every key must already exist, so a typo fails loudly)."""
    bad = set(kw) - set(DEFAULT_POSE) - {"dust", "burst", "eye_r"}
    assert not bad, bad
    return {**base, **kw}


def _mix(a: str | dict[str, Any], b: str | dict[str, Any], t: float, **kw: Any) -> dict[str, Any]:
    pa = POSES[a] if isinstance(a, str) else a
    pb = POSES[b] if isinstance(b, str) else b
    return _p(blend(pa, pb, t), **kw)


_I = POSES["idle"]
_W = POSES["windup"]
_L = POSES["lunge"]
_C = POSES["contact"]
_H = POSES["hurt"]
_S = POSES["slam"]

# Idle: a slow heave. Breathing in, the belly swells, the body rises half a pixel and the short
# arms drift out; the boils pulse a little brighter. The top stays within a pixel of the key.
IDLE_IN = _p(_I, pelvis=(0.0, HIP_Y + 0.3, 0.0), belly=(1.025, 1.02, 1.025), jaw=0.66, glow=0.38,
             hand_n=(-4.5, 42.6, 44.8), hand_f=(20.5, 44.6, -30.6), head=(5.0, -32.0, 0.0))
IDLE_FULL = _p(_I, pelvis=(0.0, HIP_Y + 0.6, 0.0), belly=(1.05, 1.04, 1.05), jaw=0.72, glow=0.46,
               hand_n=(-5.0, 43.2, 45.6), hand_f=(21.0, 45.2, -31.2), head=(4.0, -32.0, 0.0))

# Wind-up coil: sinks and gathers the fists low (the anticipation), then heaves them up.
COIL_1 = _mix(_I, _W, 0.12, pelvis=(-1.0, HIP_Y - 2.5, 0.0), squash=0.94, lean=2.0,
              hand_n=(-9.0, 36.0, 40.0), hand_f=(15.0, 37.0, -28.0), belly=(1.04, 0.97, 1.04),
              head=(10.0, -32.0, 0.0), jaw=0.8, glow=0.55)
COIL_2 = _mix(_I, _W, 0.78, pelvis=(-2.5, HIP_Y - 0.6, 0.0), glow=0.85)
# The hold's shiver: fists pushed a little higher, the gut quivering, every boil blazing.
SHIVER = _p(_W, root=(3.8, 0.0, 0.0), hand_n=(-12.5, 72.5, 30.0), hand_f=(1.5, 70.4, -22.0),
            belly=(1.08, 0.99, 1.05), ripple=0.35, jaw=0.9, head=(-22.0, -32.0, 2.0))

# Lunge: from the reared-up wind-up into the belly-first waddle (the key is "arriving").
LUNGE_1 = _mix(_W, _L, 0.34)
LUNGE_2 = _mix(_W, _L, 0.7)

# Contact follow-through: the belly squashes further into the target, then rebounds, jiggling.
FOLLOW_1 = _p(_C, lean=21.0, belly=(0.84, 1.1, 1.1), belly_off=(18.0, 1.5, 0.0), hand_f=(37.0, 50.0, -20.0),
              hand_n=(-2.0, 50.0, 32.0), jaw=0.9, ripple=0.3)
FOLLOW_2 = _mix(_C, _I, 0.35, ripple=0.6, jaw=0.8)
# Recoil (mid-string): pulls back off the target.
RECOIL_1 = _mix(_C, _I, 0.55, ripple=0.4)
# Return: steps back home, the near foot lifting and planting behind.
RETURN_1 = _mix(_C, _I, 0.78, foot_n=(-5.0, ANKLE_H + 3.0, 20.0), toe_n=-20.0, ripple=0.3,
                pelvis=(0.0, HIP_Y + 0.4, 0.0))
RETURN_2 = _mix(_C, _I, 0.94, foot_n=(-1.0, ANKLE_H, 20.0), pelvis=(0.0, HIP_Y - 0.6, 0.0), ripple=0.15)

# Slam: the impact key, then the body bouncing on the flattened gut in a cloud of dust, then
# heaving itself up off the ground.
SLAM_DUST = _p(_S, pelvis=(-6.0, 8.8, 0.0), squash=0.79, dust=1.0, glow=0.5)
SLAM_RISE = _mix(_S, _I, 0.38, ground=0.0, glow=0.45, pelvis=(-4.0, 13.0, 0.0))
SLAM_WAIT = _mix(_S, _I, 0.72, ground=0.0, glow=0.35)

# Hurt: the key, then settling back down with the belly still wobbling.
HURT_1 = _mix(_H, _I, 0.5, ripple=0.6, eyes=0.0)
# Stagger (counter or big hit): rocks right back onto its heels, then sways forward and settles.
STAGGER_1 = _p(_H, root=(5.0, 0.0, 0.0), pelvis=(0.0, HIP_Y - 1.5, 0.0), lean=-29.0, side=-7.0,
               belly=(0.94, 1.1, 1.04), ripple=1.0, head=(-6.0, -32.0, 18.0), jaw=0.75,
               hand_n=(-8.0, 54.0, 38.0), hand_f=(2.0, 56.0, -38.0), toe_n=26.0, toe_f=14.0)
STAGGER_2 = _mix(STAGGER_1, _I, 0.55, ripple=0.7, eyes=0.0, lean=4.0)

# Death (BURST): shudders, swells up onto its toes, the gut stretching and the boils blazing,
# then splits with light (the game bursts it into sparks at the end of the clip).
DEATH_1 = _p(_H, belly=(1.04, 1.12, 1.06), ripple=0.8, glow=0.6, jaw=0.9, eyes=0.0)
DEATH_2 = _p(_I, pelvis=(0.0, HIP_Y + 1.5, 0.0), lean=-8.0, belly=(1.14, 1.18, 1.14),
             belly_off=(2.0, 2.0, 0.0), head=(-14.0, -32.0, 0.0), jaw=1.0, teeth=0.0, glow=0.9, eyes=0.0,
             hand_n=(-6.0, 50.0, 40.0), hand_f=(16.0, 54.0, -34.0), toe_n=-15.0, toe_f=-15.0)
DEATH_3 = _p(DEATH_2, root=(-2.0, 0.0, 0.0), pelvis=(0.0, HIP_Y + 2.5, 0.0), belly=(1.22, 1.26, 1.2),
             head=(-22.0, -32.0, 0.0), glow=1.0, hand_n=(-6.0, 55.0, 38.0), hand_f=(14.0, 59.0, -34.0),
             burst=0.5)
DEATH_4 = _p(DEATH_3, root=(-3.0, 0.0, 0.0), belly=(1.27, 1.3, 1.24), ripple=0.5, burst=1.0)

# Walking (zone): a side-to-side waddle, a stubby stride, the arms swinging against the legs.
WALK_1 = _p(_I, side=6.0, pelvis=(0.0, HIP_Y - 1.0, 0.0), belly=(1.02, 0.97, 1.02), foot_n=(12.0, ANKLE_H, 20.0),
            foot_f=(-4.0, ANKLE_H, -19.0), toe_f=-18.0, hand_n=(-8.0, 42.0, 40.0), hand_f=(26.0, 46.0, -28.0),
            head=(8.0, -30.0, -4.0))
WALK_2 = _p(_I, pelvis=(0.0, HIP_Y + 1.2, 0.0), belly=(0.99, 1.04, 0.99), foot_n=(4.0, ANKLE_H, 20.0),
            foot_f=(5.0, ANKLE_H + 4.0, -19.0), toe_f=-10.0, ripple=0.25)
WALK_3 = _p(_I, side=-6.0, pelvis=(0.0, HIP_Y - 1.0, 0.0), belly=(1.02, 0.97, 1.02), foot_n=(-5.0, ANKLE_H, 20.0),
            foot_f=(15.0, ANKLE_H, -19.0), toe_n=-18.0, hand_n=(4.0, 44.0, 40.0), hand_f=(12.0, 43.0, -30.0),
            head=(8.0, -34.0, 4.0))
WALK_4 = _p(_I, pelvis=(0.0, HIP_Y + 1.2, 0.0), belly=(0.99, 1.04, 0.99), foot_n=(4.0, ANKLE_H + 4.0, 20.0),
            foot_f=(8.0, ANKLE_H, -19.0), toe_n=-10.0, ripple=0.25)
# Chasing: belly first and leaning back like the lunge, longer strides, the arms pumping.
CHASE_1 = _p(_L, root=(4.0, 0.0, 0.0), side=4.0, foot_n=(-12.0, ANKLE_H + 2.0, 20.0), toe_n=-35.0,
             foot_f=(14.0, ANKLE_H, -18.0))
CHASE_2 = _p(_L, root=(4.0, 0.0, 0.0), side=0.0, pelvis=(0.0, HIP_Y + 0.5, 0.0), foot_n=(2.0, ANKLE_H + 4.0, 20.0),
             toe_n=-10.0, foot_f=(4.0, ANKLE_H, -18.0), hand_n=(-6.0, 42.0, 34.0), hand_f=(8.0, 46.0, -28.0))
CHASE_3 = _p(_L, root=(4.0, 0.0, 0.0), side=-4.0, foot_n=(14.0, ANKLE_H, 20.0), toe_n=0.0,
             foot_f=(-12.0, ANKLE_H + 2.0, -18.0), toe_f=-35.0, hand_n=(10.0, 50.0, 34.0), hand_f=(-8.0, 40.0, -28.0))
CHASE_4 = _p(_L, root=(4.0, 0.0, 0.0), side=0.0, pelvis=(0.0, HIP_Y + 0.5, 0.0), foot_n=(4.0, ANKLE_H, 20.0),
             toe_n=0.0, foot_f=(2.0, ANKLE_H + 4.0, -18.0), toe_f=-10.0, hand_n=(2.0, 46.0, 34.0),
             hand_f=(2.0, 44.0, -28.0))

# Tier 2, Belly Slam (attack hit anim "belly"): instead of raising its fists it draws a huge
# breath, leaning back, the arms going wide and the gut swelling with every boil lit; then it
# throws the swollen gut forward (belly_lunge ends on the lunge key, contact is the shared one).
BELLY_1 = _p(_I, pelvis=(0.0, HIP_Y - 1.2, 0.0), lean=2.0, belly=(1.07, 1.04, 1.06), head=(-2.0, -32.0, 0.0),
             jaw=0.3, glow=0.5, hand_n=(-6.0, 41.0, 41.0), hand_f=(21.0, 43.0, -33.0))
BELLY_2 = _p(_I, pelvis=(-0.6, HIP_Y + 0.5, 0.0), lean=-8.0, belly=(1.14, 1.1, 1.12),
             belly_off=(3.0, 1.5, 0.0), head=(-12.0, -32.0, 0.0), jaw=0.15, glow=0.8,
             hand_n=(-4.0, 46.0, 37.0), hand_f=(22.0, 50.0, -35.0), toe_n=8.0)
BELLY_FULL = _p(_I, pelvis=(-1.0, HIP_Y + 1.0, 0.0), lean=-12.0, belly=(1.2, 1.14, 1.16),
                belly_off=(5.0, 2.0, 0.0), head=(-16.0, -32.0, 0.0), jaw=0.1, glow=1.0,
                hand_n=(-3.0, 50.0, 35.0), hand_f=(22.0, 54.0, -35.0), toe_n=10.0)
BELLY_SHIVER = _p(BELLY_FULL, belly=(1.22, 1.15, 1.18), ripple=0.3, root=(0.6, 0.0, 0.0),
                  hand_n=(-3.4, 50.6, 35.4), hand_f=(22.4, 54.6, -35.4))
BELLY_LUNGE_1 = _mix(BELLY_FULL, _L, 0.35, jaw=0.5)
BELLY_LUNGE_2 = _mix(BELLY_FULL, _L, 0.7)

# Clip name -> cells in play order (int = a row-0 key, dict = a pose). Timing is the game's.
CLIPS: dict[str, list[Any]] = {
    "idle": [K_IDLE, IDLE_IN, IDLE_FULL, IDLE_IN],
    "windup": [COIL_1, COIL_2, K_WINDUP],
    "windup_hold": [K_WINDUP, SHIVER],
    "lunge": [LUNGE_1, LUNGE_2, K_LUNGE],
    "contact": [K_CONTACT, FOLLOW_1, FOLLOW_2],
    "recoil": [RECOIL_1, K_IDLE],
    "return": [RETURN_1, RETURN_2, K_IDLE],
    "slam": [K_SLAM, SLAM_DUST, SLAM_RISE],
    "slam_recover": [SLAM_WAIT, K_IDLE],
    "hurt": [K_HURT, HURT_1, K_IDLE],
    "stagger": [K_HURT, STAGGER_1, STAGGER_2, K_IDLE],
    "death": [DEATH_1, DEATH_2, DEATH_3, DEATH_4],
    "walk": [WALK_1, WALK_2, WALK_3, WALK_4],
    "chase": [CHASE_1, CHASE_2, CHASE_3, CHASE_4],
    # Tier 2 (per-attack prefix "belly"; any missing <belly>_<x> falls back to <x>).
    "belly_windup": [BELLY_1, BELLY_2, BELLY_FULL],
    "belly_windup_hold": [BELLY_FULL, BELLY_SHIVER],
    "belly_lunge": [BELLY_LUNGE_1, BELLY_LUNGE_2, K_LUNGE],
}
# Review GIF lengths that differ from kit.clips (the slow heave: idle_cycle_percent 140).
IDLE_CYCLE_PERCENT = 140
PREVIEW_MS = {"idle": 1800 * IDLE_CYCLE_PERCENT // 100}


def _key(pose: dict[str, Any]) -> str:
    return repr(sorted(pose.items()))


def render_many(poses: list[dict[str, Any]]) -> list[np.ndarray]:
    """render_pose for many poses, in worker processes (a bloat frame takes seconds); one by one
    when a process pool cannot start."""
    if len(poses) < 4:
        return [render_pose(p) for p in poses]
    try:
        from concurrent.futures import ProcessPoolExecutor
        workers = max(1, min(len(poses), (os.cpu_count() or 2) - 1))
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


def render_named_clips(names: list[str]) -> dict[str, list[np.ndarray]]:
    """The cells of the named clips (row-0 keys rendered too), for review strips."""
    uniq = _unique_poses(names)
    imgs = render_many([POSES[n] for n in ENEMY_POSES] + list(uniq.values()))
    keys, done = imgs[:len(ENEMY_POSES)], dict(zip(uniq, imgs[len(ENEMY_POSES):]))
    return {n: [keys[e] if isinstance(e, int) else done[_key(e)] for e in CLIPS[n]] for n in names}


def build(ctx) -> None:
    uniq = _unique_poses(list(CLIPS))
    imgs = render_many([POSES[name] for name in ENEMY_POSES] + list(uniq.values()))
    frames, done = imgs[:len(ENEMY_POSES)], dict(zip(uniq, imgs[len(ENEMY_POSES):]))
    cells = render_clips(CLIPS, lambda p: done[_key(p)])
    ctx.save_fighter("sprites/enemies/%s.png" % ID, frames, cells, (S, S), S, ID, preview_ms=PREVIEW_MS)
    sheet = hstack(frames)
    face = portrait()
    ctx.save("sprites/portraits/%s.png" % ID, face)
    # Review pictures: the sheet at real size on the game's dark ground, and the portrait at
    # real size and at the HUD's 56 px.
    ctx.extra("sheet_1x.png", _on_dark(sheet), scale=1, frame_w=S)
    ctx.extra("sheet_dark_3x.png", _on_dark(sheet), scale=3, frame_w=S)
    hud = np.asarray(Image.fromarray(_on_dark(face)).resize((56, 56), Image.NEAREST))
    pad = np.zeros((56, 48 + 4 + 56, 4), dtype=np.uint8)
    pad[:48, :48] = _on_dark(face)
    pad[:, 52:] = hud
    ctx.extra("portrait_1x_and_hud.png", pad, scale=3)
