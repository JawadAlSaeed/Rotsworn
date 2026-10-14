"""Shade: a floating wraith of shadow (sprites/enemies/shade.png + sprites/portraits/shade.png).

A tall hooded figure in tattered dark violet cloth with no legs: the robe ends in ragged tongue
tails a little above the ground, torn strips peel off its sides and hang from the sleeves. Long
thin grey arms end in long pale claws; two cold eyes glow in the dark of the hood. Because the
cloth is almost as dark as the zone floor, a lighter violet rim runs along its top and left
edges, a faint bounce light along its bottom and right edges, and the tail tips fade into the
brighter edge violet.

The eyes are laid out in screen space (see _eye_spots): the same size and spacing in every frame
of a glow level, never merged into one bar; build() checks every frame has two eye shapes.

Built facing +x (near side +z) and rendered facing left. Poses are plain dicts (POSES) of numbers
and tuples, every pose carrying every key, so phase 10 can blend them (kit.rig.blend) into
in-between frames; IN_BETWEENS holds extra keys where a straight blend looks wrong:

    frame = render_pose(blend(POSES["idle"], POSES["windup"], 0.5))
"""
from __future__ import annotations

import math
from collections import Counter, deque
from dataclasses import replace
from typing import Any

import numpy as np

from kit.palette import M, Material
from kit.post import cleanup, contours, outline
from kit.render import Camera, Frame, line3d, render
from kit.rig import blend, two_bone
from kit.sdf import Ellipsoid, Node, RoundCone, SmoothUnion, Subtract, Union, rot
from kit.sheet import hstack
from kit.specs import ENEMY_FRAME, ENEMY_POSES, PORTRAIT

ID = "shade"
S = ENEMY_FRAME[ID]

# --- Materials ---------------------------------------------------------------------------------
# Every outline is a dark violet no darker than palette.INK, so the edge still separates from a
# dark floor on the bottom and right sides where there is no rim.
OUTLINE = "#1c1236"
# The robe: shade_cloth pushed a little toward the shade's accent (#4b4f7a), cooler and more
# violet, so the body matches its violet rim. It never drops to the near-black bottom of the
# ramp, so folds stay readable on dark floors.
CLOTH = replace(M["shade_cloth"], colors=["#17112f", "#211b43", "#2d2850", "#413a61", "#544b72"],
                lo=0.6, outline=OUTLINE)
# Hems, tail tips and the rim: the lighter violet "glow" along the cloth edges.
EDGE = replace(M["shade_edge"], lo=1.0, outline=OUTLINE)
# Thin shadowy forearms and hands, a clear step greyer and lighter than the robe so the arms
# separate from it instead of dissolving into the cloth.
LIMB = Material.make("shade_limb", "#6a6484", lo=1.0, wrap=0.35, outline=OUTLINE)
# Long pale cold claws (the brightest lit thing on the body after the eyes).
CLAW = Material.make("shade_claw", "#aea8d2", lo=1.0, spec=0.4, wrap=0.3, outline=OUTLINE)
# The dark inside the hood: flat, two tones (the side away from the light a step darker); the
# main tone is the robe's darkest violet, so the palette stays tight.
VOID = Material("shade_void", ["#110b1d", "#17112f", "#2b2045"], emissive=True, glow_index=1,
                outline=OUTLINE)
# Pale cold glowing eyes (the top kept off pure white).
EYE = Material("shade_eye", ["#5f9fc8", "#84cfe6", "#a6eef5", "#e2fbfb"], emissive=True)
# The windup tell: claws and tail tips light up violet.
CLAW_GLOW = replace(CLAW, lo=2.0, hi=4.0)
TIP_GLOW = replace(M["glow_violet"], outline=OUTLINE)
# Outside the windup a few dim violet pixels still smoulder at the tail tips (a ghostly glow).
TIP_DIM = replace(M["glow_violet"], name="glow_violet_dim", glow_index=0, outline=OUTLINE)

# The direction toward the viewer in model space (the shade is always drawn facing left).
VIEW = Camera(8, 8, face="left").R[2].copy()

# --- Body proportions (model units = sprite pixels) ---------------------------------------------
SPINE = 15.0        # waist -> shoulder line
SH_W = 6.6          # centre -> shoulder joint (z)
UPPER_ARM = 11.5
FOREARM = 11.5
ARM_R = (1.3, 0.9)  # forearm radius at the elbow and the wrist
ROBE_LEN = 11.0     # waist -> hem centre
HEM_R = 6.2
CLAW_LEN = (5.0, 4.4)
# Robe fold ridges: (angle round the body, 0 = front, 90 = near side; radius; first spine segment
# it starts on, 0 = chest, 1 = waist, 2 = hem) and how deep they sit in the cloth. They stand
# well proud of the robe so each catches the light as a long streak with a dark groove beside it.
FOLDS = ((10.0, 2.1, 1), (55.0, 2.3, 0), (105.0, 2.1, 1))
FOLD_INSET = 0.45
# Blend width of the folds into the robe: small keeps a crisp dark groove beside each ridge.
FOLD_K = 0.9
# Cloth tones from the light value (index 1..4; 0 is kept for contour lines): the lit plane
# reaches the top colour so the hood and shoulders turn clearly from light to shadow.
CLOTH_BANDS = (0.26, 0.47, 0.66)
# The robe tone its bottom and right edges are lifted to (see _bounce).
BOUNCE_TONE = 2

# Robe tails: (angle round the hem, 0 = front, 90 = near side; length; thickness; wave phase;
# slot; rag). The slot (-1..1) is where the tail sits in the fan as seen from the camera, so a wide
# fan splays them evenly instead of stacking the near and far ones; rag (-1..1) bends each tail
# its own way (times the pose's `rag` degrees) so the hem reads torn, not combed.
TAILS = (
    (75.0, 0.82, 1.00, 0.0, 0.33, 0.6),
    (20.0, 0.62, 0.80, 1.9, 1.0, -0.9),
    (-40.0, 0.90, 0.80, 3.1, 0.67, 0.3),
    (-100.0, 1.05, 0.95, 4.4, 0.0, -0.4),
    (125.0, 0.72, 1.05, 5.3, -0.33, 1.0),
    (170.0, 1.18, 1.00, 2.5, -1.0, -0.7),
    (-150.0, 0.86, 0.85, 0.9, -0.67, 0.2),
)
# Torn rags hanging from each sleeve: (where along shoulder -> cuff, length, angle offset deg).
# In the windup the spread arms carry them as ragged bat wings.
SLEEVE_RAGS = ((0.45, 0.75, 14.0), (0.8, 1.0, 0.0), (1.08, 0.7, -16.0))
# Low waves in the robe surface (body frame), so its sides step irregularly like torn, flowing
# cloth instead of running dead straight. (amplitude, along-body frequency, around frequency,
# phase) per wave; the amplitude grows toward the hem.
RIPPLE = ((0.3, 0.45, 2.0, 0.4), (0.15, 0.9, -3.0, 2.2))
# Strips peeling off the robe's sides: (angle round the body, -28 = the front edge and 152 = the
# back edge as the camera sees them; where on the spine chain, 1 = waist, 2 = hips, 3 = hem;
# length vs the tail vector; rag stray -1..1).
SIDE_RAGS = ((-30.0, 1.5, 0.42, -0.8), (-24.0, 2.3, 0.5, 0.5), (148.0, 1.2, 0.5, 0.9),
             (156.0, 2.1, 0.62, -0.4))

# --- Poses --------------------------------------------------------------------------------------
# base: waist (x, y); lean: deg, + = top forward; bend: extra lean of the upper back (curls the
# spine); twist: upper body yaw; hood: (pitch down, yaw, tilt) deg (yaw < 0 turns the face toward
# the viewer); hood_fwd: how far the hood juts forward; point: tips the hood's point back (deg);
# hand_n / hand_f: claw-hand targets; elbow_n / elbow_f: elbow pole vectors; wrist_*: claw bend
# vs forearm (deg); claw_*: (spread, curl) deg; sleeve: (x, y) where the torn sleeve hangs from
# the forearm; sleeve_r: sleeve thickness; skirt: direction waist -> hem; tail: where the tails
# stream (x, y); tail_len / tail_th: tail length and thickness; wave: how much they ripple; fan:
# how far they splay apart (deg); curl: how much they bend along their length (deg, + = toward
# +y when trailing forward, - = up when trailing back); rag: how far each tail strays from that
# curl its own way (deg); lift: raises the tail ends (a splash); flare: hem width; waist: torso
# width (a narrow waist over a wide hem reads as flowing cloth); tatter: length of the strips
# peeling off the robe's sides; drift: tail wave phase
# (animate it); eye: 0 dim, 1 normal, 2 blazing; glow: >= 0.5 lights the claws and tail tips (the
# windup tell), >= 0.2 a dim smoulder at the tail tips.
DEFAULTS: dict[str, Any] = dict(
    base=(0.0, 30.0), lean=6.0, bend=10.0, twist=0.0, hood=(8.0, -22.0, 0.0), hood_fwd=1.5, point=0.0,
    hand_n=(6.0, 28.0, 9.0), elbow_n=(-1.0, -0.4, 0.6),
    hand_f=(14.0, 34.0, -3.0), elbow_f=(-0.5, -1.0, -0.3),
    wrist_n=0.0, wrist_f=0.0, claw_n=(16.0, 40.0), claw_f=(18.0, -45.0),
    sleeve=(-1.0, -8.0), sleeve_r=1.1,
    skirt=(-0.35, -1.0), tail=(-9.0, -14.0), tail_len=1.0, tail_th=1.0, wave=1.0, fan=14.0,
    curl=0.0, rag=14.0, tatter=1.0, lift=0.0, flare=1.0, waist=0.92, drift=0.0, eye=1.0,
    glow=0.25,
)


def _pose(**kw: Any) -> dict[str, Any]:
    bad = set(kw) - set(DEFAULTS)
    assert not bad, bad
    return dict(DEFAULTS, **kw)


POSES: dict[str, dict[str, Any]] = {
    # Floating hunched over, both claws held out in front at two heights, hooked, ready to grab.
    "idle": _pose(
        lean=10.0, bend=14.0, skirt=(-0.2, -1.0), tail=(-6.0, -15.0), flare=1.12, waist=0.88,
        hand_n=(15.0, 24.0, 8.0), elbow_n=(-1.0, -0.2, 0.8), wrist_n=20.0, claw_n=(24.0, 22.0),
        hand_f=(18.0, 33.0, -3.0), wrist_f=-10.0, claw_f=(22.0, -40.0), rag=18.0,
    ),
    # Rising tall, arms spread wide, claws up and hooked toward the target, torn sleeves hanging
    # from the arms like ragged bat wings; eyes, claws and tail tips blaze.
    "windup": _pose(
        base=(-1.0, 34.0), lean=-4.0, bend=-6.0, hood=(4.0, -15.0, 0.0), hood_fwd=1.5,
        point=-25.0,
        hand_n=(-17.0, 54.0, 15.0), elbow_n=(-0.6, -1.0, 0.8),
        hand_f=(12.0, 59.0, -11.0), elbow_f=(0.3, -1.0, -0.6),
        wrist_n=-10.0, wrist_f=-10.0, claw_n=(26.0, -35.0), claw_f=(26.0, -35.0),
        sleeve=(-1.0, -10.0), sleeve_r=1.3, skirt=(-0.2, -1.0), tail=(-5.0, -15.0),
        tail_len=1.1, fan=22.0, rag=16.0, flare=1.45, waist=0.8, drift=1.2, eye=2.0, glow=1.0,
    ),
    # Streaking forward in a low swoop like a comet: the far claw leads (the lowest point), the
    # near arm is swept back beneath the body, and the robe tapers back into a long thin wedge.
    "lunge": _pose(
        base=(0.0, 28.0), lean=72.0, bend=-10.0, hood=(-30.0, -10.0, 0.0), hood_fwd=2.5,
        point=35.0,
        hand_n=(-2.0, 30.0, 2.0), elbow_n=(0.0, -1.0, 0.3),
        hand_f=(23.0, 20.0, -2.0), elbow_f=(-0.2, -1.0, -0.4),
        wrist_n=0.0, wrist_f=40.0, claw_n=(10.0, 30.0), claw_f=(24.0, -25.0),
        sleeve=(-7.0, 1.5), skirt=(-0.95, 0.2), tail=(-20.0, 3.0), tail_len=1.2, tail_th=0.7,
        wave=1.4, fan=14.0, curl=-10.0, rag=16.0, tatter=0.6, flare=0.6, waist=0.82, drift=2.4,
    ),
    # The rake landing: the body upright, the near arm fully extended low with three claws fanned
    # and hooked down, the far arm flung up and back as a counterweight (a diagonal slash).
    "contact": _pose(
        base=(15.0, 25.0), lean=25.0, bend=0.0, twist=-35.0, hood=(-10.0, -14.0, 0.0),
        hood_fwd=2.0, point=10.0,
        hand_n=(46.0, 17.0, 6.0), elbow_n=(0.0, 1.0, 0.6),
        hand_f=(-14.0, 52.0, -8.0), elbow_f=(0.0, -1.0, -0.5),
        wrist_n=-35.0, wrist_f=0.0, claw_n=(35.0, -45.0), claw_f=(24.0, -30.0),
        sleeve=(-4.0, -6.0), skirt=(-0.55, -0.85), tail=(-16.0, -10.0), tail_len=1.05,
        wave=1.3, fan=12.0, drift=3.6, eye=1.5,
    ),
    # Knocked back: shoved hard in the middle, the body folds into a crescent with its back
    # bowed out away from the hit; the hood (bowed, eyes dimmed) and the robe tails are left
    # behind, the tails swinging forward under the body together as one ragged sheet; the arms
    # hang limp with the claws folded shut.
    "hurt": _pose(
        base=(-8.0, 32.0), lean=-25.0, bend=55.0, hood=(30.0, -20.0, 0.0), hood_fwd=0.5,
        point=0.0,
        hand_n=(2.0, 24.0, 8.0), elbow_n=(-1.0, -0.3, 0.5),
        hand_f=(-2.0, 28.0, -6.0), elbow_f=(-1.0, -0.3, -0.5),
        wrist_n=10.0, wrist_f=10.0, claw_n=(6.0, 15.0), claw_f=(6.0, 15.0),
        sleeve=(-3.0, -6.0), skirt=(0.5, -1.0), tail=(12.0, -6.0), tail_len=1.15, tail_th=0.85,
        wave=0.8, fan=12.0, curl=30.0, rag=6.0, drift=4.8, eye=0.0, glow=0.0,
    ),
    # Diving head first to smash the ground: the hood is the lowest mass above two claws driven
    # into the floor apart, the robe thrown up behind and torn into a ragged spray of tails.
    "slam": _pose(
        base=(-6.0, 25.5), lean=110.0, bend=-15.0, hood=(-45.0, -40.0, 0.0), point=80.0,
        hand_n=(23.0, 5.0, 1.0), elbow_n=(0.3, 1.0, 0.4),
        hand_f=(10.0, 10.0, -7.0), elbow_f=(0.3, 1.0, -0.4),
        wrist_n=55.0, wrist_f=30.0, claw_n=(30.0, 0.0), claw_f=(30.0, 0.0),
        sleeve=(-3.0, 4.0), skirt=(-0.6, 0.8), tail=(-11.0, 11.0), tail_len=1.8, tail_th=0.65,
        wave=3.0, fan=12.0, curl=-15.0, rag=30.0, tatter=1.4, flare=0.55, waist=0.85, drift=4.2,
        eye=2.0,
    ),
}


# Extra keyframes for phase 10, not in the sheet: (from, to) -> a pose to pass through halfway,
# where a straight blend looks wrong. Contact -> hurt: the tails swing from trailing back to
# swept forward, so a straight blend shortens them into a stump; here they hang straight down.
IN_BETWEENS: dict[tuple[str, str], dict[str, Any]] = {
    ("contact", "hurt"): dict(blend(POSES["contact"], POSES["hurt"], 0.5), tail=(-3.0, -16.0),
                              tail_len=0.95, curl=0.0, rag=12.0, fan=16.0),
}


# --- Skeleton -----------------------------------------------------------------------------------


def _v(x: Any) -> np.ndarray:
    return np.asarray(x, dtype=float)


def _unit(v: np.ndarray) -> np.ndarray:
    return v / (np.linalg.norm(v) + 1e-9)


def _turn(v: np.ndarray, axis: np.ndarray, deg: float) -> np.ndarray:
    """Rotates v about `axis` by `deg` degrees (Rodrigues)."""
    k = _unit(axis)
    th = math.radians(deg)
    return v * math.cos(th) + np.cross(k, v) * math.sin(th) + k * float(np.dot(k, v)) * (1.0 - math.cos(th))


def skeleton(p: dict[str, Any]) -> dict[str, Any]:
    """Pose dict -> joint positions and frames (all in model space)."""
    bx, by = p["base"]
    base = _v((bx, by, 0.0))
    yaw = rot(0.0, p.get("twist", 0.0), 0.0)
    L = yaw @ rot(0.0, 0.0, -p["lean"])                       # waist -> mid back
    T = yaw @ rot(0.0, 0.0, -(p["lean"] + p["bend"]))         # mid back -> shoulders
    mid = base + L @ _v((0.0, SPINE * 0.5, 0.0))
    chest = mid + T @ _v((0.0, SPINE * 0.5, 0.0))
    hp, hy, ht = p["hood"]
    Hr = T @ rot(0.0, hy, -hp) @ rot(ht, 0.0, 0.0)
    # The hood's point hangs from the crown: it follows the body and only part of the head's
    # pitch (a bowed head would otherwise swing it forward like a horn), plus `point` (+ = back).
    Pr = T @ rot(0.0, hy, -hp * 0.4 + p["point"])
    neck = chest + T @ _v((0.6, 1.2, 0.0))
    head = neck + Hr @ _v((p["hood_fwd"], 4.8, 0.0))
    sk: dict[str, Any] = dict(base=base, L=L, T=T, mid=mid, chest=chest, neck=neck, head=head, Hr=Hr,
                              Pr=Pr)
    for s, sg in (("n", 1.0), ("f", -1.0)):
        sh = chest + T @ _v((-0.3, -1.4, sg * SH_W))
        elbow, hand = two_bone(sh, _v(p["hand_" + s]), UPPER_ARM, FOREARM, _v(p["elbow_" + s]))
        sk["shoulder_" + s], sk["elbow_" + s], sk["hand_" + s] = sh, elbow, hand
    sx, sy = p["skirt"]
    sk["hem"] = base + _unit(_v((sx, sy, 0.0))) * ROBE_LEN
    return sk


# --- Model --------------------------------------------------------------------------------------


def _claw_paths(sk: dict[str, Any], p: dict[str, Any], s: str) -> list[tuple[np.ndarray, ...]]:
    """(root, knuckle, tip) of each of the three claws of hand `s`. They bend, splay and hook in
    the picture plane (about the axis toward the viewer), so they always read as separate fingers
    instead of hiding behind each other."""
    elbow, hand = sk["elbow_" + s], sk["hand_" + s]
    f = _unit(hand - elbow)
    a = _unit(VIEW - f * float(np.dot(VIEW, f)))
    spread, curl = p["claw_" + s]
    d0 = _turn(f, a, p["wrist_" + s])
    out = []
    for i in (-1.0, 0.0, 1.0):
        d = _turn(d0, a, spread * i)
        k = 0.82 if i else 1.0
        root = hand + d * 0.9
        mid = root + d * CLAW_LEN[0] * k
        tip = mid + _turn(d, a, curl) * CLAW_LEN[1] * k
        out.append((root, mid, tip))
    return out


def _claws(sk: dict[str, Any], p: dict[str, Any], s: str, glow: bool, r: float = 1.0) -> list[Node]:
    """Three long claws (see _claw_paths); the windup lights them."""
    out: list[Node] = []
    for root, mid, tip in _claw_paths(sk, p, s):
        out.append(RoundCone(CLAW_GLOW if glow else CLAW, root, mid, 0.62 * r, 0.45 * r, thin=True,
                             group="claw" + s))
        out.append(RoundCone(TIP_GLOW if glow else CLAW, mid, tip, 0.45 * r, 0.2 * r, thin=True,
                             group="claw" + s))
    return out


def _tails(sk: dict[str, Any], p: dict[str, Any]) -> list[Node]:
    base, hem = sk["base"], sk["hem"]
    axis = _unit(hem - base)
    ez = _v((0.0, 0.0, 1.0))
    ef = _unit(np.cross(ez, axis))        # "front" round the hem (forward for a hanging robe)
    tx, ty = p["tail"]
    tvec = _v((tx, ty, 0.0)) * p["tail_len"]
    hr = HEM_R * p["flare"]
    glow = p["glow"]
    out: list[Node] = []
    for n, (ang, ln, th, ph, slot, rag) in enumerate(TAILS):
        a = math.radians(ang)
        ring = ef * math.cos(a) + ez * math.sin(a)
        tv = _turn(tvec, ez, p["fan"] * slot)
        side = _unit(np.cross(_unit(tv), ez))
        root = hem + ring * hr * 0.75
        tip = hem + tv * ln + ring * hr * 0.6 * p["flare"]
        # Bend the tail along its length (curl, plus this tail's own stray) keeping its chord
        # roughly where it was.
        curl = p["curl"] + p["rag"] * rag
        chord = tip - root
        length = float(np.linalg.norm(chord))
        d0 = _turn(_unit(chord), ez, -curl * 0.5)
        wave = math.sin(p["drift"] + ph) * p["wave"]
        up = _v((0.0, p["lift"], 0.0))
        m1 = root + d0 * length * 0.36 + side * wave * 1.2 + up * 0.15
        m2 = m1 + _turn(d0, ez, curl * 0.5) * length * 0.34 - side * wave * 2.2 + up * 0.35
        end = m2 + _turn(d0, ez, curl) * length * 0.32 + up * 0.5
        # Each tail is a tongue (broad where it leaves the hem, tapering hard to a point), so
        # neighbours merge into one jagged sheet at the hem instead of reading as fingers.
        r0 = 2.5 * th * p["tail_th"]
        g = "tail%d" % n
        out.append(RoundCone(CLOTH, root, m1, r0 * 1.25, r0 * 0.66, group=g))
        out.append(RoundCone(CLOTH, m1, m2, r0 * 0.66, r0 * 0.4, group=g))
        if glow >= 0.5:
            out.append(RoundCone(TIP_GLOW, m2, end, r0 * 0.4, 0.35, group=g))
        elif glow >= 0.2:
            cut = m2 + (end - m2) * 0.62
            out.append(RoundCone(EDGE, m2, cut, r0 * 0.4, 0.5, group=g))
            out.append(RoundCone(TIP_DIM, cut, end, 0.5, 0.35, group=g))
        else:
            out.append(RoundCone(EDGE, m2, end, r0 * 0.4, 0.35, group=g))
    return out


class _Ripple(Node):
    """Low waves added to a child's surface in the body's own frame (so they move with the body
    and blended poses do not crawl). Stronger toward the hem: the sides of the robe step
    irregularly like torn, flowing cloth instead of running dead straight."""

    def __init__(self, child: Node, origin: np.ndarray, R: np.ndarray, top: float,
                 bottom: float) -> None:
        self.child = child
        self.origin = origin
        self.R = R
        self.top = top
        self.bottom = bottom

    def eval(self, P: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        d, part = self.child.eval(P)
        Q = (P - self.origin) @ self.R
        u = Q[:, 1]
        around = np.arctan2(Q[:, 2], Q[:, 0])
        w = np.zeros_like(d)
        for amp, fu, fa, ph in RIPPLE:
            w += amp * np.sin(u * fu + around * fa + ph)
        k = np.clip((self.top - u) / max(self.top - self.bottom, 1e-6), 0.0, 1.0)
        return d + w * (0.35 + 0.65 * k), part

    def leaves(self) -> list:
        return self.child.leaves()


def _sleeve(sk: dict[str, Any], p: dict[str, Any], s: str) -> list[Node]:
    """A wide torn sleeve from the shoulder to just past the elbow, with ragged strips hanging
    from it (the cloth hangs `sleeve` way; the strip ends fade into the edge violet)."""
    sh, el, ha = sk["shoulder_" + s], sk["elbow_" + s], sk["hand_" + s]
    sr = p["sleeve_r"]
    ez = _v((0.0, 0.0, 1.0))
    cuff = el + (ha - el) * 0.3
    g = "sleeve" + s
    out: list[Node] = [RoundCone(CLOTH, sh, cuff, 2.3 * sr, 2.6 * sr, group=g)]
    hang = _v((*p["sleeve"], 0.0))
    for t, ln, ang in SLEEVE_RAGS:
        root = sh + (cuff - sh) * t if t <= 1.0 else cuff + (ha - el) * 0.3 * (t - 1.0)
        tip = root + _turn(hang, ez, ang) * ln
        mid = root + (tip - root) * 0.62
        out.append(RoundCone(CLOTH, root, mid, 1.9 * sr, 0.9 * sr, group=g))
        out.append(RoundCone(EDGE, mid, tip, 0.9 * sr, 0.35, group=g))
    return out


def model(p: dict[str, Any], line_claws: tuple[str, ...] = ()) -> Node:
    """The shade in pose `p` as one SDF. Hands named in `line_claws` get no claw shapes (the
    portrait draws those as clean 1-px lines instead, see portrait_frame)."""
    sk = skeleton(p)
    T, L, Hr = sk["T"], sk["L"], sk["Hr"]
    head, chest, mid, base, hem = sk["head"], sk["chest"], sk["mid"], sk["base"], sk["hem"]
    glow = p["glow"] >= 0.5
    hr = HEM_R * p["flare"]
    wr = p["waist"]
    # One soft body: hood, its drooping point, the mantle it falls onto, and the torso as two
    # long cones down the spine (a few big planes instead of a stack of blobs).
    body: list[Node] = [
        Ellipsoid(CLOTH, head, (6.6, 7.0, 6.0), R=Hr, group="robe"),
        RoundCone(CLOTH, head + Hr @ _v((-2.2, 2.6, 0.0)), head + sk["Pr"] @ _v((-7.0, 8.0, 0.0)), 4.2,
                  0.6, group="robe"),
        Ellipsoid(CLOTH, chest + T @ _v((-0.8, 0.0, 0.0)), (6.2, 4.6, 8.6), R=T, group="robe"),
        RoundCone(CLOTH, chest + T @ _v((-0.3, -2.5, 0.0)), mid, 5.7, 5.3 * wr, group="robe"),
        RoundCone(CLOTH, mid, base, 5.3 * wr, 5.2 * wr, group="robe"),
        RoundCone(CLOTH, base, hem, 5.2 * wr, hr * 0.95, group="robe"),
    ]
    # Wide fold ridges down the lit front of the robe, from the chest to the hem along the bent
    # spine: each catches the light as one long streak, with a groove between them.
    ez = _v((0.0, 0.0, 1.0))
    chain = [chest + T @ _v((-0.3, -2.5, 0.0)), mid, base, hem]
    radii = [5.7, 5.3 * wr, 5.2 * wr, hr * 0.95]
    segs = [_unit(chain[i + 1] - chain[i]) for i in range(3)]
    axes = [segs[0], _unit(segs[0] + segs[1]), _unit(segs[1] + segs[2]), segs[2]]
    folds: list[Node] = []
    for ang, fr, start in FOLDS:
        a = math.radians(ang)
        pts = []
        for c, ax, r in zip(chain, axes, radii):
            ring = _unit(np.cross(ez, ax)) * math.cos(a) + ez * math.sin(a)
            pts.append(c + ring * (r - FOLD_INSET))
        for i in range(start, 3):
            folds.append(RoundCone(CLOTH, pts[i], pts[i + 1], fr, fr * 1.15, group="robe"))
    # Torn strips peeling off the robe's front and back edges (where its outline is), streaming
    # the way the tails go, so the sides of the robe step raggedly instead of running straight.
    tx, ty = p["tail"]
    tdir = _v((tx, ty, 0.0))
    rags: list[Node] = []
    for n, (ang, t, ln, rag) in enumerate(SIDE_RAGS):
        i = min(int(t), 2)
        f = t - i
        c = chain[i] + (chain[i + 1] - chain[i]) * f
        ax = _unit(axes[i] * (1.0 - f) + axes[i + 1] * f)
        r = radii[i] + (radii[i + 1] - radii[i]) * f
        a = math.radians(ang)
        ring = _unit(np.cross(ez, ax)) * math.cos(a) + ez * math.sin(a)
        root = c + ring * (r - 1.0)
        d = _turn(tdir, ez, p["rag"] * rag) * ln * p["tatter"]
        tip = root + d + ring * 1.2
        m = root + (tip - root) * 0.6
        rags.append(RoundCone(CLOTH, root, m, 1.7, 0.9, group="robe"))
        rags.append(RoundCone(EDGE, m, tip, 0.9, 0.35, group="robe"))
    torso = SmoothUnion(SmoothUnion(*body[2:], k=3.0), *folds, k=FOLD_K)
    # The waves run along the body from the chest (calm) to the hem (strongest); the hood stays
    # smooth so its outline and the face opening keep one clean curve, and the thin tails are
    # left out so they never break apart.
    torso = _Ripple(torso, base, L, top=SPINE, bottom=-ROBE_LEN)
    robe = SmoothUnion(SmoothUnion(SmoothUnion(*body[:2], k=3.0), torso, k=2.2), *_tails(sk, p),
                       *rags, k=1.4)
    # The face opening, its top kept below the crown so the brim stays one smooth curve (a
    # higher cut leaves a notch that reads as a second, cat-like ear when the hood bows).
    cavity = Ellipsoid(VOID, head + Hr @ _v((4.3, -1.5, 0.0)), (4.0, 4.6, 4.2), R=Hr, group="void")
    parts: list[Node] = [Subtract(robe, cavity, k=0.8, b_material=True)]
    for s in ("n", "f"):
        el, ha = sk["elbow_" + s], sk["hand_" + s]
        parts += _sleeve(sk, p, s)
        parts.append(RoundCone(LIMB, el, ha, ARM_R[0], ARM_R[1], group="arm" + s))
        parts.append(Ellipsoid(LIMB, ha, (1.5, 1.2, 1.3), group="arm" + s))
        if s not in line_claws:
            parts += _claws(sk, p, s, glow)
    return Union(*parts)


# --- Rendering ----------------------------------------------------------------------------------


def _tone(frame: Frame) -> None:
    """Cloth tones from the light by fixed bands (CLOTH_BANDS) instead of the material's linear
    ramp: the lit planes reach the top violet and the shadow side stays dark, a clear turn of the
    form rather than two close mid tones."""
    ids = [i for i, m in enumerate(frame.mats) if m.name == CLOTH.name]
    mask = np.isin(frame.part, ids)
    v = frame.light
    tone = 1 + sum((v > t).astype(np.int32) for t in CLOTH_BANDS)
    frame.idx = np.where(mask, tone, frame.idx)


def _merge_islands(frame: Frame, names: tuple[str, ...], min_size: int = 3) -> None:
    """Tone islands smaller than `min_size` pixels inside the cloth take the commonest tone round
    them, so the robe reads as a few clean planes instead of camouflage noise."""
    H, W = frame.H, frame.W
    ids = [i for i, m in enumerate(frame.mats) if m.name in names]
    mask = np.isin(frame.part, ids)
    for _ in range(2):
        seen = np.zeros((H, W), dtype=bool)
        changed = False
        for y0 in range(H):
            for x0 in range(W):
                if not mask[y0, x0] or seen[y0, x0]:
                    continue
                tone = frame.idx[y0, x0]
                comp = []
                q = deque([(x0, y0)])
                seen[y0, x0] = True
                while q:
                    x, y = q.popleft()
                    comp.append((x, y))
                    for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
                        nx, ny = x + dx, y + dy
                        if (0 <= nx < W and 0 <= ny < H and not seen[ny, nx] and mask[ny, nx]
                                and frame.idx[ny, nx] == tone):
                            seen[ny, nx] = True
                            q.append((nx, ny))
                if len(comp) >= min_size:
                    continue
                cs = set(comp)
                votes: Counter = Counter()
                for x, y in comp:
                    for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < W and 0 <= ny < H and (nx, ny) not in cs and mask[ny, nx]:
                            votes[int(frame.idx[ny, nx])] += 1
                if votes:
                    t = votes.most_common(1)[0][0]
                    for x, y in comp:
                        frame.idx[y, x] = t
                    changed = True
        if not changed:
            break


def _rim(frame: Frame) -> None:
    """Lighter violet along the top and left edges of the cloth (reads on dark floors). On the
    shadow side a top edge is lit only where it runs for 2+ pixels, so steep stair-stepped edges
    do not get a dotted line of single rim pixels."""
    H, W = frame.H, frame.W
    rim = frame.add_part(EDGE, "rim")
    cloth = {i for i, m in enumerate(frame.mats) if m.name == CLOTH.name}
    is_cloth = np.isin(frame.part, list(cloth))
    empty = frame.part < 0
    up = np.zeros((H, W), dtype=bool)
    up[1:] = is_cloth[1:] & empty[:-1]
    up[0] = is_cloth[0]
    left = np.zeros((H, W), dtype=bool)
    left[:, 1:] = is_cloth[:, 1:] & empty[:, :-1]
    left[:, 0] = is_cloth[:, 0]
    run = np.zeros((H, W), dtype=bool)
    run[:, 1:] |= up[:, 1:] & up[:, :-1]
    run[:, :-1] |= up[:, :-1] & up[:, 1:]
    lit = frame.light > 0.45
    top = up & (run | lit)
    side = left & ~top
    frame.part[top | side] = rim
    frame.idx[top] = 3
    frame.idx[side] = 2


def _bounce(frame: Frame) -> None:
    """A faint bounce light (one step up, never past the mid violet) on the robe's bottom and
    right edges, so its shadow side does not melt into a dark floor."""
    H, W = frame.H, frame.W
    cloth = np.isin(frame.part, [i for i, m in enumerate(frame.mats) if m.name == CLOTH.name])
    empty = frame.part < 0
    edge = np.zeros((H, W), dtype=bool)
    edge[:-1] |= cloth[:-1] & empty[1:]
    edge[:, :-1] |= cloth[:, :-1] & empty[:, 1:]
    lift = edge & (frame.idx < BOUNCE_TONE)
    frame.idx[lift] = BOUNCE_TONE


def _lip(frame: Frame) -> None:
    """A violet lip where the hood cloth meets the dark inside, so the face opening reads."""
    H, W = frame.H, frame.W
    lip = frame.add_part(EDGE, "lip")
    void = {i for i, m in enumerate(frame.mats) if m.name == VOID.name}
    cloth = {i for i, m in enumerate(frame.mats) if m.name in (CLOTH.name, EDGE.name)}
    paint = []
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if frame.part[y, x] in cloth and any(frame.part[y + dy, x + dx] in void
                                                 for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1))):
                paint.append((x, y))
    for x, y in paint:
        frame.part[y, x] = lip
        frame.idx[y, x] = 1


# Sprite eyes per glow level: (dx, dy, ramp index) from the eye's top-left pixel on its bottom
# row. Every eye is EYE_W wide; the pair keeps the same size and spacing in every frame.
EYE_CELLS = {
    0: [(0, 0, 1), (1, 0, 0)],                             # hurt: a dim slit
    1: [(0, 0, 3), (1, 0, 2)],                             # a cold slit
    2: [(0, 0, 3), (1, 0, 3), (0, -1, 2), (1, -1, 2)],     # blazing 2x2 (the tell)
}
EYE_W = 2
EYE_GAP = {0: 1, 1: 1, 2: 2}
# Portrait eyes: slanted slits, outer ends raised, a cold glare (screen-left eye, then the other).
PORTRAIT_EYES = (("23..", "1333", "..21"), ("..32", "3331", "12.."))
PORTRAIT_EYE_W = 4
PORTRAIT_EYE_GAP = 2


def _eye_spots(cam: Camera, sk: dict[str, Any], w: int, gap: int) -> list[tuple[int, int]]:
    """Where the two eyes go on screen (top-left pixel of each, left eye first). The 3D eye points
    project only ~2 px apart, so they are laid out in screen space: centred on the pair's
    projection, on one row (a 1-px step only when the hood tilts past 30 deg), always exactly
    `gap` pixels apart so they never merge into one bar."""
    head, Hr = sk["head"], sk["Hr"]
    pts = sorted(cam.project(head + Hr @ _v((2.8, -0.6, sg * 2.0)))[:2] for sg in (1.0, -1.0))
    (lx, ly), (rx, ry) = pts
    mx, my = (lx + rx) * 0.5, (ly + ry) * 0.5
    x0 = int(math.floor(mx - (2 * w + gap) * 0.5 + 0.5))
    y0 = int(math.floor(my))
    ys = [y0, y0]
    if abs(math.degrees(math.atan2(ry - ly, max(rx - lx, 1e-6)))) > 30.0:
        ys[0 if ly < ry else 1] -= 1
    return [(x0, ys[0]), (x0 + w + gap, ys[1])]


def _eyes(frame: Frame, cam: Camera, sk: dict[str, Any], level: float, big: bool = False) -> None:
    core = frame.add_part(EYE, "eye")
    void = {j for j, m in enumerate(frame.mats) if m.name == VOID.name}
    lit: list[tuple[int, int]] = []
    if big:
        spots = _eye_spots(cam, sk, PORTRAIT_EYE_W, PORTRAIT_EYE_GAP)
        cells_of = [[(c, r - 1, int(ch)) for r, row in enumerate(PORTRAIT_EYES[n])
                     for c, ch in enumerate(row) if ch != "."] for n in range(2)]
        # The eyes light the dark inside the hood round them: two rings, the inner one brighter.
        for xi, yi in spots:
            for dy in range(-4, 5):
                for dx in range(-4, 8):
                    e = (dx - 1.5) ** 2 + dy * dy * 1.7
                    if e <= 18.0:
                        lit.append((xi + dx, yi + dy))
    else:
        lvl = int(round(min(max(level, 0.0), 2.0)))
        spots = _eye_spots(cam, sk, EYE_W, EYE_GAP[lvl])
        cells_of = [EYE_CELLS[lvl]] * 2
        for xi, yi in spots:
            if lvl == 2:
                # Blazing: a ring of the hood's dark round each eye lights up.
                lit += [(xi + dx, yi + dy) for dy in range(-2, 2) for dx in range(-1, 3)]
            elif lvl == 1:
                # A 1-px spill of cold light on the hood's dark just under each eye.
                lit += [(xi + dx, yi + 1) for dx in range(EYE_W)]
    for xx, yy in lit:
        if 0 <= xx < frame.W and 0 <= yy < frame.H and frame.part[yy, xx] in void:
            frame.idx[yy, xx] = 2
    for (xi, yi), cells in zip(spots, cells_of):
        for dx, dy, i in cells:
            frame.put(xi + dx, yi + dy, core, i)


def render_frame(p: dict[str, Any], W: int = S, H: int = S, scale: float = 1.0,
                 cx: float = 0.0, cy: float = -0.5, portrait: bool = False) -> Frame:
    """The finished Frame of the shade in pose `p`, facing left (see render_pose). The portrait
    draws the near hand's claws as clean 1-px lines (at portrait scale the SDF claws would be
    3 px thick and lumpy)."""
    cam = Camera(W, H, scale=scale, cx=cx, cy=cy, face="left")
    sk = skeleton(p)
    frame = render(model(p, line_claws=("n",) if portrait else ()), cam, ambient=0.1)
    _tone(frame)
    _merge_islands(frame, (CLOTH.name,), min_size=3)
    if portrait:
        # Drawn before the contour pass, so the hood right beside each claw goes dark and the
        # fingers stay separate lines.
        for root, mid, tip in _claw_paths(sk, p, "n"):
            line3d(frame, cam, [root, mid, tip], CLAW, list(PORTRAIT_CLAW_TONES), group="clawn",
                   depth_bias=1.0)
    contours(frame, gap=2.5, steps=2)
    cleanup(frame)
    _bounce(frame)
    _rim(frame)
    _lip(frame)
    _eyes(frame, cam, sk, p["eye"], big=portrait)
    outline(frame)
    return frame


def render_pose(p: dict[str, Any], W: int = S, H: int = S, scale: float = 1.0,
                cx: float = 0.0, cy: float = -0.5, portrait: bool = False) -> np.ndarray:
    """One frame (RGBA) of the shade in pose `p`, facing left."""
    return render_frame(p, W, H, scale, cx, cy, portrait).rgba()


def _components(mask: np.ndarray) -> list[list[tuple[int, int]]]:
    """8-connected pixel groups of a mask."""
    H, W = mask.shape
    seen = np.zeros_like(mask)
    out = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        comp = []
        q = deque([(int(x0), int(y0))])
        seen[y0, x0] = True
        while q:
            x, y = q.popleft()
            comp.append((x, y))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((nx, ny))
        out.append(comp)
    return out


def _check(frame: Frame, name: str) -> str:
    """Bounds, stray single pixels, the outline margin and the two separate eyes of one frame
    (printed by build)."""
    rgba = frame.rgba()
    a = rgba[:, :, 3] > 0
    ys, xs = np.nonzero(a)
    p = np.pad(a, 1)
    lone = a & ~(p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:])
    fill = frame.part >= 0
    edge = int(fill[0].sum() + fill[-1].sum() + fill[:, 0].sum() + fill[:, -1].sum())
    eye_ids = [i for i, m in enumerate(frame.mats) if m.name == EYE.name]
    eyes = _components(np.isin(frame.part, eye_ids))
    msg = "%s x %d..%d y %d..%d lone=%d edge_fill=%d eyes=%s" % (
        name, xs.min(), xs.max(), ys.min(), ys.max(), int(lone.sum()), edge,
        "+".join(str(len(e)) for e in eyes))
    assert len(eyes) == 2, "%d eye shapes (want 2 apart): %s" % (len(eyes), msg)
    assert edge == 0, "touches the frame edge: " + msg
    return msg


# The near hand is raised beside the face on the screen-left side, its long claws running up
# past the hood brim and hooking in over it, so they frame the face instead of covering it; the
# far hand stays hidden behind the body.
PORTRAIT_POSE = dict(POSES["idle"], hood=(6.0, -32.0, 0.0), point=-10.0,
                     hand_n=(17.2, 40.0, 6.0), elbow_n=(0.2, -1.0, 0.6), claw_n=(20.0, 40.0),
                     wrist_n=44.0, hand_f=(6.0, 30.0, -3.0))
PORTRAIT_SCALE = 0.4
# Where the eyes sit in the 48-px portrait (the pair's centre, pixels).
PORTRAIT_EYE_AT = (20.0, 21.5)
# Claw line tones (CLAW ramp index): the base segment, then the hooked tip.
PORTRAIT_CLAW_TONES = (3, 4)


def portrait_frame() -> Frame:
    """Head and shoulders at 2.5x the sprite's detail: the eyes framed a little above the
    middle, the hood point running off the top and the shoulders off the bottom."""
    p = PORTRAIT_POSE
    sk = skeleton(p)
    eye = sk["head"] + sk["Hr"] @ _v((2.8, -0.6, 0.0))
    vx, vy = Camera(S, S, face="left").view(eye)[:2]
    sc = PORTRAIT_SCALE
    ex, ey = PORTRAIT_EYE_AT
    cx = vx - (ex - PORTRAIT / 2.0) * sc
    cy = vy - (PORTRAIT - 0.5 - ey) * sc
    return render_frame(p, PORTRAIT, PORTRAIT, scale=sc, cx=cx, cy=cy, portrait=True)


def portrait() -> np.ndarray:
    return portrait_frame().rgba()


def build(ctx) -> None:
    frames = []
    for name in ENEMY_POSES:
        fr = render_frame(POSES[name])
        print("  " + _check(fr, name))
        frames.append(fr.rgba())
    sheet = hstack(frames)
    ctx.save("sprites/enemies/%s.png" % ID, sheet, frame_w=S)
    ctx.extra("sheet_x6.png", sheet, scale=5, frame_w=S)
    ctx.extra("sheet_x1.png", sheet, scale=1, frame_w=S)
    por = portrait()
    ctx.save("sprites/portraits/%s.png" % ID, por)
    ctx.extra("portrait_x1.png", por, scale=1)
    ctx.extra("portrait_hud56.png", _hud(por), scale=2)
    ctx.extra("scale_vs_hero.png", _with_hero(frames[0]), scale=4)
    # Phase 10 check: in-betweens from blended pose dicts (idle -> windup, contact -> hurt); the
    # hood point must not flip between keyframes.
    tweens = [render_pose(blend(POSES["idle"], POSES["windup"], t)) for t in (0.0, 0.33, 0.66, 1.0)]
    ctx.extra("blend_idle_windup.png", hstack(tweens), scale=4, frame_w=S)
    mid = IN_BETWEENS[("contact", "hurt")]
    keys = [POSES["contact"], blend(POSES["contact"], mid, 0.5), mid, blend(mid, POSES["hurt"], 0.5),
            POSES["hurt"]]
    ctx.extra("blend_contact_hurt.png", hstack([render_pose(k) for k in keys]), scale=4, frame_w=S)
    floor = _floor_strip(len(frames))
    if floor is not None:
        ctx.extra("ingame_floor_x4.png", _over(floor, sheet), scale=4, frame_w=S)


def _floor_strip(n: int) -> np.ndarray | None:
    """A 1x strip of the in-game mossy floor (from the art director's screenshot crop, about 3x
    zoomed) behind n frames, or None when that crop is not there."""
    import os
    from PIL import Image
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(here, "preview", "_review", "bgcrop_floor.png")
    if not os.path.exists(path):
        return None
    im = Image.open(path).convert("RGBA")
    im = im.resize((im.width // 3, im.height // 3), Image.NEAREST)
    tile = np.array(im)
    reps = (n * S) // tile.shape[1] + 1
    strip = np.concatenate([tile] * reps, axis=1)[:, :n * S]
    out = np.zeros((S, n * S, 4), dtype=np.uint8)
    h = min(S, strip.shape[0])
    out[S - h:] = strip[:h]
    out[:S - h] = strip[0]
    return out


def _over(bg: np.ndarray, fg: np.ndarray) -> np.ndarray:
    """fg pasted over bg (alpha cut: a sprite pixel is there or not)."""
    out = bg.copy()
    solid = fg[:, :, 3] > 0
    out[solid] = fg[solid]
    return out


def _hud(por: np.ndarray) -> np.ndarray:
    """The portrait at the HUD's 56 px (nearest, the way the turn-order row shows it)."""
    from PIL import Image
    return np.array(Image.fromarray(por, "RGBA").resize((56, 56), Image.NEAREST))


def _hero_idle() -> np.ndarray | None:
    """The new Alder's idle frame (32x48), read back from the hero module's dark-background
    preview (3x, 4-px gaps) when it exists, else the old placeholder sheet; None if neither."""
    import os
    from PIL import Image
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    new = os.path.join(here, "preview", "sprites", "characters", "alder.png")
    if os.path.exists(new):
        im = np.array(Image.open(new).convert("RGBA"))
        if im.shape[1] == 32 * 8 * 3 + 7 * 4:
            tile = im[1:48 * 3:3, 1:32 * 3:3]
            out = np.zeros((48, 32, 4), dtype=np.uint8)
            solid = np.any(tile[:, :, :3] != (34, 31, 40), axis=2)
            out[solid] = tile[solid]
            return out
    old = os.path.join(here, "preview", "_old", "characters", "alder.png")
    if os.path.exists(old):
        return np.array(Image.open(old).convert("RGBA"))[:, :32]
    return None


def _with_hero(idle: np.ndarray) -> np.ndarray:
    """The idle frame beside a hero idle frame (same pixel density) to judge the size."""
    out = np.zeros((S, S + 40, 4), dtype=np.uint8)
    out[:, 40:] = idle
    hero = _hero_idle()
    if hero is not None:
        out[S - hero.shape[0]:, 4:36] = hero
    return out
