"""The Hollow King, the final boss: enemy sheet (108x108 cells, facing left), clips and portrait.

A tall, gaunt undead king: a skull face with rot-green eyes under a broken worn-gold crown,
rusted dark armour with an open ribcage and a glowing rot core, a long ragged wine-red cloak and
a huge notched cleaver-sword. About 95 px tall (heroes are about 45 px).

Built for phase 10: POSES holds plain keyframe dicts, `model(pose)` builds the SDF model of one
pose and `render_pose(pose)` turns it into a finished RGBA frame, so in-between frames are just
`render_pose(kit.rig.blend(POSES[a], POSES[b], t))`. All frames share one camera (`camera()`,
fitted once to the idle pose), so the king's feet stay put between frames.

Pose keys on top of kit.rig.pose_skeleton's (pelvis, lean, head, hand_*, foot_*, ...):
    turn        degrees the whole king is turned toward the viewer (24 = presenting, < 0 = more
                profile, attacking to the left)
    sword_ang   blade direction in the side plane, degrees (0 forward, -90 down, 90 up, 180 back)
    sword_out   blade tilt toward the viewer (+z), degrees
    sword_roll  turn of the blade about its own axis, degrees (0 = flat side to the viewer)
    two_hand    0..1, how far the far hand moves onto the sword grip
    glow        0..1, rot core / eye glow strength (>= 0.9 also lights the blade: the attack tell)
    crown_tilt  degrees the crown is knocked askew
    jaw         degrees the jaw hangs open
    claw_f      0..1, how far the far hand's fingers spread (0 = fist)
    cloak_sway  x offset of the cloak hem (negative = trailing behind)
    cloak_flare multiplier on the hem width
    cloak_hem   height of the hem's lowest tatters
    cloak_lift  how far the back of the cloak billows up (0..1)
    cloak_open  degrees the cloak's near edge pulls back (bares the near arm, shows the lining)
    debris      0..1, rubble thrown up where the blade hits the ground (slam)
    bury        how deep the blade tip goes into the ground (clipped below y = 0 when > 0)
    brow, socket   size of the brow ridges / eye sockets (1 = sprite size; the portrait scowls more)
    eye_cap, eye_y largest pupil radius and pupil height in the socket (small hot pupils, portrait)

Phase 10 clips (CLIPS at the end: every clip of plan 4.2 plus rage, rendered in worker processes)
add keys that are absent from the row-0 keys, so those render as in phase 9:
    eyes        0 = the sockets go dark (death)
    crown_at    model point the fallen crown's band is centred on (death); crown_rot its turn
    debris_fly  how high and far the slam's rubble has flown (1 = the slam key)
    seam        the blade's rot seam whatever the glow (the sword swing): 1 = lit along the whole
                blade; below 1 = only that share of it from the guard, in the seam's darker green
                (it kindles up the blade as the swing starts and dies back to the guard after it),
                drawn as a steady stepped line on the blade's own pixels; absent = lit when
                glow >= 0.9
    grip_f      where the far hand holds the grip with two_hand: share of GRIP_LEN from the near
                hand toward the pommel (default GRIP_F; below 0 = toward the guard)
    grip_at     how far (model units) the near hand sits from the grip's middle toward the pommel
                (default 0): with grip_f < 0 the sword swing holds the far fist above the near one
                on the blade's side, so the two arms reach the grip without crossing
    fist, cuff  the bone fists' size (1 = as drawn) and where the forearm plate stops (share of the
                forearm back from the fist, default 0.3): the swing bares bigger fists so both
                hands on the grip read
    smear, smear_from   the swing smear: the area the blade swept since the cell before (see
                SMEAR_BANDS)

The sword swing (windup, windup_hold, lunge, contact, recoil) is the overhead chop of the COIL_*,
SWING_* and CLEAVE_* keys (one swing for every hit: the sheet has no lunge_b / contact_b, so odd
hits fall back to it); row 0 keeps the phase 9 windup / lunge / contact keys, which other clips'
poses are built from.
"""
from __future__ import annotations

import math
from dataclasses import replace
from typing import Any

import numpy as np

from kit.noise import fbm3
from kit.palette import M, Material
from kit.post import cleanup, contours, outline
from kit.render import Camera, Frame, line3d, render
from kit.rig import Build, blend, pose_skeleton
from kit.sdf import (Box, Capsule, Custom, Ellipsoid, Intersect, Moved, Node, Prim, Prism,
                     RoundCone, SmoothUnion, Sphere, Subtract, Torus, Union, basis, rot)
from kit.clips import ENEMY_PREVIEW_MS, render_clips
from kit.sheet import hstack
from kit.specs import ENEMY_FRAME, ENEMY_POSES, PORTRAIT

ID = "hollow_king"
S = ENEMY_FRAME[ID]
# Model units per sheet pixel. Above 1 the king is drawn smaller in his frame (same pixel size in
# game): at 1.0 his idle crown stood 4.3 world units tall and left the top of the fight camera.
SHEET_SCALE = 1.19

# --- Materials ----------------------------------------------------------------------------------
ROBE = replace(M["king_robe"], lo=1.1)                       # cloak outside: lifted off the darkest
                                                            # shades so it separates from wine fog
LINING = Material.make("king_lining", "#8e2f3a", wrap=0.4)   # the boss accent, inside the cloak
ARMOR = M["king_armor"]
GOLD = M["gold_worn"]
IRON = replace(M["iron"], lo=0.6, hi=3.2)                   # the cleaver: kept off the top colours so
                                                            # the planted blade does not outshine him
EDGE = replace(M["blade"], name="king_edge", hi=3.0, spec=0.4)  # the honed cleaver edge
BONE = M["bone"]
RIB = replace(BONE, name="king_rib", hi=2.0)                 # ribs a step darker than the skull
GLOW = M["glow_rot"]
GLOW_CORE = replace(GLOW, name="king_core", glow_index=2)   # the core reads green; its heart is hot
SINEW = M["husk_bark"]
GRIP = M["leather_dark"]
HOLLOW = Material.make("king_hollow", "#2e1a33", below=1, above=1, wrap=0.2, ao=0.0)
STONE = replace(M["stone_warm"], lo=1.0)                     # rubble from the slam
RUST = Material.make("king_rust", "#6a4434", wrap=0.2)        # rust patches eating the armour
SEAM_IDX = 1  # the tell's seam along the blade: a mid rot-green, like the core (not the yellow top)

# --- Proportions ---------------------------------------------------------------------------------
KING = Build(ankle_h=3.0, shin=21.0, thigh=21.0, spine=23.0, neck=5.6, head_r=7.0,
             shoulder_w=10.5, hip_w=4.8, upper_arm=15.5, forearm=14.5, foot_len=7.0)
HIP_Y = KING.stand_hip()
BLADE_LEN = 44.0
GRIP_LEN = 9.0
GRIP_F = 0.42  # the far hand's place on the grip (share of GRIP_LEN behind the near hand)
# By default the king is turned this many degrees toward the viewer on top of the shared camera,
# so more of his front shows than a hero's: the open chest, both pauldrons, the skull face. Poses
# change it with the `turn` key (attacks turn him toward the heroes, to the left).
MODEL_YAW = 24.0
# The viewer's direction in camera-turned model space (before the king's own turn).
_CR = Camera(8, 8, face="left").R
_TO_VIEWER = _CR.T @ np.array([0.0, 0.0, 1.0])
_SCREEN_RIGHT = _CR.T @ np.array([1.0, 0.0, 0.0])


def _v(x: Any) -> np.ndarray:
    return np.asarray(x, dtype=float)


def turn_R(pose: dict[str, Any]) -> np.ndarray:
    """The king's turn toward the viewer for this pose (model -> world)."""
    return rot(0.0, -float(pose.get("turn", MODEL_YAW)), 0.0)


def world(p: Any, pose: dict[str, Any]) -> np.ndarray:
    """A model point after the king's turn (for overlays drawn on the frame)."""
    return turn_R(pose) @ _v(p)


def screen_axes(pose: dict[str, Any]) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Model-space directions of: the viewer, screen-right along the ground, toward the viewer
    along the ground. Moving along the ground's screen-right keeps a point on the same row."""
    R = turn_R(pose)
    view = R.T @ _TO_VIEWER
    sr = R.T @ _SCREEN_RIGHT
    gx = np.array([sr[0], 0.0, sr[2]]) / np.hypot(sr[0], sr[2])
    gz = np.array([view[0], 0.0, view[2]]) / np.hypot(view[0], view[2])
    return view, gx, gz


# --- Poses (keyframes) ---------------------------------------------------------------------------
_BASE: dict[str, Any] = {
    "turn": MODEL_YAW, "sword_out": 0.0, "sword_roll": 0.0, "two_hand": 0.0, "glow": 0.3, "crown_tilt": 0.0,
    "jaw": 0.0, "claw_f": 0.0, "cloak_sway": 0.0, "cloak_flare": 1.0, "cloak_hem": 1.0,
    "cloak_lift": 0.0, "debris": 0.0, "bury": 0.0,
    "cloak_open": 0.0, "brow": 1.0, "socket": 1.0, "eye_cap": 9.0, "eye_y": -0.6,
}


def _pose(**kw: Any) -> dict[str, Any]:
    p = dict(_BASE)
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    # Towering, sword planted point-down before him, both hands on the pommel, cloak hanging.
    "idle": _pose(
        pelvis=(0.0, HIP_Y - 0.6, 0.0), lean=4.0, head=(8.0, -12.0, 0.0),
        hand_n=(12.0, 48.0, 8.0), hand_f=(12.0, 50.0, 4.0), elbow_n=(0.2, -1.0, 0.6),
        elbow_f=(0.2, -1.0, -0.6), foot_n=(-1.0, 3.0, 12.5), foot_f=(8.0, 3.0, -9.0),
        sword_ang=-90.0, two_hand=1.0, bury=1.5, glow=0.5, turn=28.0, cloak_flare=1.6,
    ),
    # The tell: sword hoisted high behind him, the other claw thrust out, roaring, core and
    # blade flaring.
    "windup": _pose(
        pelvis=(-4.0, HIP_Y - 2.5, 0.0), lean=-8.0, twist=-14.0, head=(-12.0, 0.0, 0.0),
        hand_n=(-17.0, 88.0, 16.0), hand_f=(26.0, 68.0, -2.0), elbow_n=(0.0, -0.2, 1.0),
        elbow_f=(-0.3, -1.0, -0.4), foot_n=(-10.0, 3.0, 9.0), foot_f=(14.0, 3.0, -7.0),
        sword_ang=172.0, sword_out=-6.0, glow=1.0, jaw=20.0, claw_f=1.0, turn=18.0,
        cloak_sway=-6.0, cloak_flare=1.1, cloak_lift=0.3,
    ),
    # Striding in, sword low and trailing behind, cloak streaming back.
    "lunge": _pose(
        pelvis=(7.0, HIP_Y - 6.0, 0.0), lean=22.0, head=(-18.0, -16.0, 0.0),
        hand_n=(-3.0, 30.0, 15.0), hand_f=(36.0, 46.0, 3.0), elbow_n=(-0.3, 0.2, 1.0),
        elbow_f=(-0.4, -1.0, -0.5), foot_n=(25.0, 3.0, 6.0), foot_f=(-13.0, 3.0, -6.0),
        knee_f=(0.2, 0.0, -0.3), toe_f=20.0, claw_f=1.0,
        sword_ang=-165.0, sword_out=8.0, glow=0.6, turn=18.0,
        cloak_sway=-16.0, cloak_flare=1.15, cloak_hem=5.0, cloak_lift=0.4, cloak_open=40.0,
    ),
    # The cleave lands: swung through forward at a hero's chest height, arms fully extended,
    # the weight thrown onto the bent front leg (his most forward pose).
    "contact": _pose(
        pelvis=(12.0, HIP_Y - 8.0, 0.0), lean=20.0, twist=-6.0, head=(-12.0, -14.0, 0.0),
        hand_n=(35.0, 51.0, -3.0), hand_f=(31.0, 53.0, -6.0), elbow_n=(0.3, -1.0, 0.5),
        elbow_f=(0.0, -1.0, -0.4), foot_n=(30.0, 3.0, 6.0), foot_f=(-10.0, 3.0, -6.0),
        knee_f=(0.2, 0.0, -0.3), toe_f=24.0,
        sword_ang=-26.0, sword_out=20.0, two_hand=1.0, glow=0.65, jaw=12.0, turn=22.0,
        cloak_sway=-14.0, cloak_flare=1.2, cloak_hem=3.0, cloak_lift=0.5,
    ),
    # Staggered back: reeling, crown knocked askew, clutching the core, sword dragging.
    "hurt": _pose(
        pelvis=(-8.0, HIP_Y - 2.0, 0.0), lean=-18.0, head=(-24.0, 0.0, 10.0),
        hand_n=(-6.0, 38.0, 12.0), hand_f=(10.0, 60.0, 8.0), elbow_n=(-0.2, -0.4, 1.0),
        elbow_f=(-0.5, -0.8, 0.3), foot_n=(8.0, 6.5, 6.0), foot_f=(-13.0, 3.0, -6.0),
        toe_n=18.0, claw_f=0.6, sword_ang=-140.0, sword_out=24.0, glow=0.1, crown_tilt=24.0,
        jaw=18.0, cloak_sway=8.0, cloak_flare=0.95, bury=1.0, turn=16.0,
    ),
    # Grave Stomp / Kingsfall: dropped to one knee, leaning over the blade he has just driven
    # into the ground, rubble flying, cracks glowing.
    "slam": _pose(
        pelvis=(-6.0, 23.0, 0.0), lean=38.0, head=(-30.0, -16.0, 0.0),
        hand_n=(32.0, 24.0, 3.0), hand_f=(30.0, 27.0, 0.0), elbow_n=(-0.2, -0.4, 1.0),
        elbow_f=(-0.2, -1.0, -0.6), foot_n=(17.0, 3.0, 6.0), foot_f=(-26.0, 3.5, -6.0),
        knee_n=(1.0, 0.5, 0.2), knee_f=(0.4, -1.0, -0.1), toe_f=-170.0,
        sword_ang=-84.0, sword_out=0.0, two_hand=1.0, glow=0.85, jaw=14.0, bury=4.0, turn=16.0,
        debris=1.0, cloak_sway=-14.0, cloak_flare=1.35, cloak_hem=0.5, cloak_lift=0.8,
    ),
}

# The portrait looks down at the viewer (head pitched forward) from under a heavy scowling brow:
# small hot pupils low in dark sockets, the skull three-quarter to the left. The crown's points
# may crop at the top so the face stays big.
PORTRAIT_POSE: dict[str, Any] = dict(POSES["idle"], head=(2.0, -14.0, 0.0), turn=20.0, glow=0.55,
                                     jaw=10.0, brow=1.2, eye_cap=0.6, eye_y=-0.9)


# --- Speed: skip far-away parts --------------------------------------------------------------


class Bounded(Node):
    """Evaluates its child only near a bounding sphere; elsewhere the (smaller) sphere distance
    stands in, which is safe for marching. `margin` must exceed the AO probe distance."""

    def __init__(self, child: Node, center: Any, radius: float, margin: float = 3.0) -> None:
        self.child = child
        self.c = _v(center)
        self.r = float(radius)
        self.margin = margin
        self.first = child.leaves()[0]

    def eval(self, P: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        db = np.linalg.norm(P - self.c, axis=1) - self.r
        near = db < self.margin
        d = db.copy()
        part = np.full(P.shape[0], self.first.part, dtype=np.int32)
        if near.any():
            dn, pn = self.child.eval(P[near])
            d[near] = dn
            part[near] = pn
        return d, part

    def leaves(self) -> list[Prim]:
        return self.child.leaves()


def bounded(child: Node, pts: list[Any], pad: float) -> Bounded:
    """Bounds a part by the sphere around `pts` grown by `pad` (its thickest radius)."""
    arr = np.array([_v(p) for p in pts])
    c = (arr.min(axis=0) + arr.max(axis=0)) * 0.5
    r = float(np.max(np.linalg.norm(arr - c, axis=1))) + pad
    return Bounded(child, c, r)


# --- Parts ------------------------------------------------------------------------------------


def _hash1(i: np.ndarray, seed: int) -> np.ndarray:
    h = (i.astype(np.int64) * 374761393 + seed * 668265263) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF).astype(np.float64) / 65535.0


def cloak_fn(top: np.ndarray, bot: np.ndarray, top_r: tuple[float, float], bot_r: tuple[float, float],
             top_y: float, hem_y: float, phi_top: float, phi_bot: float, lift: float,
             shell: float, thick: float, seed: int = 7, rag: float = 7.0, open_n: float = 0.0):
    """A hanging cloak as a thin, open-fronted, flared shell with vertical folds and a tattered hem.

    The axis runs from `top` (at the shoulders) to `bot` (the hem centre); radii (depth x, width z)
    grow from top_r to bot_r. phi_* = how far round from the back the cloth reaches (degrees).
    `shell` = 1.0 for the outside cloth, a little less for the lining just inside it. `open_n`
    (degrees) pulls the near-side edge back toward the spine, baring the near arm (and showing
    the lining) when the cloak streams behind him."""
    span = max(top_y - hem_y, 1.0)

    def fn(Q: np.ndarray) -> np.ndarray:
        y = Q[:, 1]
        t = np.clip((top_y - y) / span, 0.0, 1.0)
        te = t ** 0.7
        ts = t ** 1.6  # the hem swings, the shoulders stay put
        cx = top[0] + (bot[0] - top[0]) * ts
        cz = top[2] + (bot[2] - top[2]) * ts
        rx = top_r[0] + (bot_r[0] - top_r[0]) * te
        rz = top_r[1] + (bot_r[1] - top_r[1]) * te
        dx = Q[:, 0] - cx
        dz = Q[:, 2] - cz
        phi = np.arctan2(dz, -dx)  # 0 = straight behind, +-pi = in front
        fold = 1.0 + (0.025 + 0.075 * t) * np.sin(phi * 7.0 + 0.8)
        rx = rx * fold
        rz = rz * fold
        e = np.sqrt((dx / rx) ** 2 + (dz / rz) ** 2)
        rmin = np.minimum(rx, rz)
        d_shell = np.abs(e - shell) * rmin - thick
        pmax = np.radians(phi_top + (phi_bot - phi_top) * t - np.where(phi > 0, open_n * t ** 0.5, 0.0))
        rr = np.hypot(dx, dz)
        d_ang = (np.abs(phi) - pmax) * np.minimum(rr, rmin) * 0.8
        # Tattered hem: ragged strips of different lengths.
        k = 9.0
        u = (phi + math.pi) / (2 * math.pi) * k * 2.0
        seg = np.floor(u)
        frac = u - seg
        tooth = 1.0 - np.abs(frac * 2.0 - 1.0)
        tear = _hash1(seg, seed)
        hem = hem_y + rag * (1.0 - tooth ** 0.6 * (0.3 + 0.7 * tear)) + 2.5 * np.abs(phi) / math.pi
        hem = hem + lift * 7.0 * np.cos(phi) ** 2  # the back billows up when moving
        d_bot = hem - y
        d_top = y - top_y - 2.0 * np.clip(1.0 - np.abs(phi) / 1.6, 0.0, 1.0)
        d = np.maximum(np.maximum(d_shell, d_ang), np.maximum(d_bot, d_top))
        return d * 0.7

    return fn


def cloak(sk, pose: dict[str, Any]) -> Node:
    chest = sk["chest"]
    sway = float(pose["cloak_sway"])
    flare = float(pose["cloak_flare"])
    hem_y = float(pose["cloak_hem"])
    lift = float(pose["cloak_lift"])
    top_y = chest[1] + 0.5
    top = _v((chest[0] - 3.0, top_y, chest[2]))
    bot = _v((sk["pelvis"][0] - 8.0 + sway, hem_y, sk["pelvis"][2]))
    top_r = (7.5, 11.5)
    bot_r = (15.0 * flare, 18.0 * flare)
    args = (top, bot, top_r, bot_r, top_y, hem_y, 108.0, 82.0, lift)
    op = float(pose["cloak_open"])
    outer = Custom(ROBE, cloak_fn(*args, shell=1.0, thick=0.8, open_n=op), group="cloak")
    inner = Custom(LINING, cloak_fn(*args, shell=0.87, thick=0.8, open_n=op), group="cloak")
    # A stiff standing collar behind the skull.
    neck = sk["neck"]
    ctop = neck[1] + 7.0
    collar_args = (_v((neck[0] - 3.5, ctop, neck[2])), _v((chest[0] - 3.0, chest[1] - 1.0, chest[2])),
                   (7.0, 10.0), (6.0, 9.0), ctop, chest[1] - 1.0, 70.0, 95.0, 0.0)
    col_out = Custom(ROBE, cloak_fn(*collar_args, shell=1.0, thick=0.9, seed=3, rag=0.0), group="collar")
    col_in = Custom(LINING, cloak_fn(*collar_args, shell=0.86, thick=0.9, seed=3, rag=0.0), group="collar")
    pts = [top + _v((0, 4, 0)), bot - _v((0, 2, 0)), top - _v((top_r[0], 0, top_r[1])),
           bot + _v((bot_r[0], 0, bot_r[1])), bot - _v((bot_r[0], 0, bot_r[1]))]
    cpts = [_v((neck[0], ctop + 2, neck[2])), chest]
    return Union(bounded(Union(outer, inner), pts, 8.0), bounded(Union(col_out, col_in), cpts, 12.0))


def skull(sk, pose: dict[str, Any], glow: float) -> list[Node]:
    """A long, gaunt skull: deep sockets with rot-green pinpoint eyes, a nose hole, cheekbones,
    and a hinged jaw (pose key `jaw`) with a dark mouth line and teeth."""
    h = sk.head
    c = sk["head"]
    jaw = math.radians(float(pose["jaw"]))

    def at(x: float, y: float, z: float) -> np.ndarray:
        return c + h @ _v((x, y, z))

    cran = Ellipsoid(BONE, at(-0.9, 1.4, 0.0), (6.4, 6.4, 5.8), R=h, group="skull")
    # A heavy, overhanging brow whose inner ends dip toward the middle: a scowl that shadows the
    # top of each socket.
    bs = float(pose.get("brow", 1.0))
    brow_n = Ellipsoid(BONE, at(4.3, 1.6, 2.6), (2.4 * bs, 1.8 * bs, 3.2), R=h @ rot(-36.0, 0.0, 0.0), group="skull")
    brow_f = Ellipsoid(BONE, at(4.3, 1.6, -2.6), (2.4 * bs, 1.8 * bs, 3.2), R=h @ rot(36.0, 0.0, 0.0), group="skull")
    # The bone between the brows juts down: the inner tops of the sockets dip into a V.
    glabella = Ellipsoid(BONE, at(5.3, 0.6, 0.0), (1.4, 1.6 * bs, 1.3), R=h, group="skull")
    face = Ellipsoid(BONE, at(3.6, -1.6, 0.0), (2.8, 3.2, 3.6), R=h, group="skull")
    cheek_n = Ellipsoid(BONE, at(3.0, -1.2, 3.2), (2.0, 1.6, 1.6), R=h, group="skull")
    cheek_f = Ellipsoid(BONE, at(3.0, -1.2, -3.2), (2.0, 1.6, 1.6), R=h, group="skull")
    upper = Box(BONE, at(4.2, -4.0, 0.0), (1.6, 1.1, 2.3), R=h, round=0.9, group="skull")
    head = SmoothUnion(cran, brow_n, brow_f, glabella, face, cheek_n, cheek_f, upper, k=1.4)
    # The jaw hinges just below the ear.
    hinge = at(0.4, -2.6, 0.0)
    J = h @ rot(0.0, 0.0, -math.degrees(jaw))
    mand = SmoothUnion(
        Box(BONE, hinge + J @ _v((3.6, -2.6, 0.0)), (1.7, 1.0, 2.1), R=J, round=0.8, group="skull"),
        RoundCone(BONE, hinge + J @ _v((0.0, 0.0, 2.6)), hinge + J @ _v((3.0, -2.8, 2.2)), 1.0, 1.0, group="skull"),
        RoundCone(BONE, hinge + J @ _v((0.0, 0.0, -2.6)), hinge + J @ _v((3.0, -2.8, -2.2)), 1.0, 1.0, group="skull"),
        k=1.0,
    )
    sr = float(pose.get("socket", 1.0))
    holes = Union(
        Ellipsoid(HOLLOW, at(5.0, -0.4, 2.6), (2.6 * sr, 2.2 * sr, 2.5 * sr), R=h @ rot(-22.0, 0.0, 0.0)),
        Ellipsoid(HOLLOW, at(5.0, -0.4, -2.6), (2.6 * sr, 2.2 * sr, 2.5 * sr), R=h @ rot(22.0, 0.0, 0.0)),
        Ellipsoid(HOLLOW, at(6.3, -3.0, 0.0), (1.3, 1.0, 0.75), R=h),
    )
    teeth_gap = Box(HOLLOW, at(5.0, -5.1, 0.0), (2.6, 0.35 + 1.6 * math.sin(jaw), 2.4), R=h)
    out: list[Node] = [Subtract(Union(head, mand), Union(holes, teeth_gap), k=0.3, b_material=True)]
    # The pupils sit low in the sockets; `eye_cap` keeps them small where pixels are big (portrait).
    er = min(0.5 + 0.6 * glow, float(pose.get("eye_cap", 9.0)))
    ey = float(pose.get("eye_y", -0.6))
    if float(pose.get("eyes", 1.0)) < 0.5:  # dead: the sockets go dark
        return out
    for zs in (2.5, -2.5):
        out.append(Sphere(GLOW_CORE, at(4.9, ey, zs), er, group="glow"))
        out.append(Sphere(GLOW, at(5.0 + er * 0.7, ey, zs), er * 0.5, group="glow"))
    return out


# A crack running down the forehead from under the crown (portrait only), head-local points.
# The forehead crack (portrait only): head-local start just under the crown band, then pixel
# steps (dx, dy) down toward the far brow, zigzagging, with a short fork.
CRACK_AT = (4.6, 3.9, 2.3)
CRACK_PATH = [(0, 0), (0, 1), (-1, 2), (-1, 3), (-2, 4), (-1, 5), (-1, 6), (-2, 7), (-3, 8), (-3, 9)]
CRACK_FORK = [(0, 5), (1, 6)]
# The nasal hole in the portrait: an upside-down heart (point up, two lobes down), drawn as pixels
# so it stays a clean dark shape apart from the sockets. Head-local anchor of its top pixel.
NOSE_AT = (6.9, -2.1, 0.0)
NOSE_ROWS = [".x.", "xxx", "x.x"]


def skull_crack(frame: Frame, cam: Camera, pose: dict[str, Any]) -> None:
    """A solid, jagged 1-px crack down the forehead, drawn only over the bare skull."""
    sk = skeleton(pose)
    ax, ay, _ = cam.project(world(sk["head"] + sk.head @ _v(CRACK_AT), pose))
    x0, y0 = int(math.floor(ax)), int(math.floor(ay))
    part = frame.add_part(HOLLOW, "skull_crack")
    for dx, dy in CRACK_PATH + CRACK_FORK:
        x, y = x0 + dx, y0 + dy
        if (0 <= x < frame.W and 0 <= y < frame.H and frame.part[y, x] >= 0
                and frame.groups[frame.part[y, x]] == "skull" and frame.mats[frame.part[y, x]] is BONE):
            frame.part[y, x] = part
            frame.idx[y, x] = 0


def nose_hole(frame: Frame, cam: Camera, pose: dict[str, Any]) -> None:
    sk = skeleton(pose)
    ax, ay, _ = cam.project(world(sk["head"] + sk.head @ _v(NOSE_AT), pose))
    part = frame.add_part(HOLLOW, "skull_nose")
    x0 = int(math.floor(ax)) - len(NOSE_ROWS[0]) // 2
    y0 = int(math.floor(ay))
    for r, row in enumerate(NOSE_ROWS):
        for c, ch in enumerate(row):
            x, y = x0 + c, y0 + r
            if ch == "x" and 0 <= x < frame.W and 0 <= y < frame.H and frame.part[y, x] >= 0:
                frame.part[y, x] = part
                frame.idx[y, x] = 0


def teeth_lines(pose: dict[str, Any]) -> list[list[np.ndarray]]:
    """Short dark strokes across the mouth line (gaps between the teeth), in model space."""
    sk = skeleton(pose)
    h = sk.head
    c = sk["head"]
    jaw = math.radians(float(pose["jaw"]))
    gap = 0.35 + 1.6 * math.sin(jaw)
    out = []
    for i in range(-2, 3):
        z = i * 1.25
        x = 5.95 - 0.1 * z * z
        out.append([c + h @ _v((x, -4.0, z)), c + h @ _v((x - 0.2, -5.1 - gap - 0.9, z))])
    return out


# How high the band sits above the skull centre: low on the brow, so it shades the scowl.
CROWN_Y = 5.2
# (angle round the band, length, outward bend): lengths under 4 are snapped stubs.
# The point straight behind the front stub (180) is snapped too, so no back point fills the gap
# in the silhouette.
CROWN_POINTS = [(0, 7.5, 0.0), (40, 1.6, 0.0), (85, 6.5, 0.7), (130, 6.0, 0.0), (180, 2.0, 0.0),
                (228, 6.5, 0.0), (276, 5.5, 0.0), (320, 6.5, 0.0)]


def crown(sk, pose: dict[str, Any]) -> Node:
    tilt = float(pose["crown_tilt"])
    h = sk.head @ rot(tilt * 0.4, 0.0, -tilt)
    c = sk["head"] + sk.head @ _v((-0.9 - tilt * 0.05, CROWN_Y, 0.0))
    if "crown_at" in pose:
        # Knocked off (the death): the band's centre at a model point, turned by crown_rot.
        c = _v(pose["crown_at"])
        h = rot(*pose.get("crown_rot", (0.0, 0.0, 0.0)))
    band = Torus(GOLD, c, 5.6, 1.35, R=h, group="crown")
    parts: list[Node] = [band]
    # Points round the band (angle 0 = front, 90 = the near side). The one at the camera-facing
    # front-near corner is snapped to a stub, one beside it is bent outward, one at the back
    # is snapped too: a broken crown from any of his turns.
    for ang, ln, bend in CROWN_POINTS:
        a = math.radians(ang)
        out_dir = _v((math.cos(a), 0.0, math.sin(a)))
        base = c + h @ (out_dir * 5.6 + _v((0.0, 0.6, 0.0)))
        if ln < 4.0:
            # A snapped point: a thick stub with a slanted break.
            tip = base + h @ _v((0.0, ln, 0.0))
            stub = RoundCone(GOLD, base, tip, 1.4, 1.1, group="crown")
            cut = Box(GOLD, tip + h @ (out_dir * 0.6 + _v((0.0, 0.9, 0.0))), (2.4, 1.0, 2.4),
                      R=h @ rot(0.0, -ang, 0.0) @ rot(0.0, 0.0, 28.0))
            parts.append(Subtract(stub, cut))
            continue
        lean_out = 0.08 + bend
        if bend > 0:
            # Bent outward at a kink half-way up.
            mid = base + h @ (out_dir * 0.3 + _v((0.0, ln * 0.5, 0.0)))
            tip = mid + h @ (out_dir * (lean_out * ln) + _v((0.0, ln * 0.4, 0.0)))
            parts.append(RoundCone(GOLD, base, mid, 1.35, 0.8, group="crown"))
            parts.append(RoundCone(GOLD, mid, tip, 0.8, 0.35, group="crown"))
            continue
        tip = base + h @ (out_dir * (lean_out * ln) + _v((0.0, ln, 0.0)))
        parts.append(RoundCone(GOLD, base, tip, 1.35, 0.35, group="crown"))
    ring = Union(*parts)
    ga = math.radians(58.0)
    gap = Box(GOLD, c + h @ _v((5.6 * math.cos(ga), 0.0, 5.6 * math.sin(ga))), (0.9, 2.0, 0.9),
              R=h @ rot(0.0, -58.0, 0.0))
    gem = Ellipsoid(LINING, c + h @ _v((6.5, 0.2, 0.0)), (0.9, 1.3, 1.1), R=h, group="gem")
    # A wine-red velvet cap fills the crown, so no bare skull-top shows through the points.
    cap = Ellipsoid(LINING, c + h @ _v((0.0, 0.3, 0.0)), (5.2, 2.7, 5.2), R=h, group="crown_cap")
    return Union(Subtract(ring, gap), gem, cap)


# The open chest: the hollow cut into the breastplate (centre z, radii) and the core's radius
# (base + per unit of glow, so the windup flare is clearly bigger than idle).
HOLE_Z = 2.2
HOLE_R = (5.5, 7.5, 6.5)
CORE_R0 = 3.6
CORE_RG = 2.2
# Ribs round a vertical axis through the core: (height, droop toward the sides) per rib.
RIB_AXIS = (1.6, HOLE_Z)
RIB_RX = 6.5    # front of the ribcage, from the axis (just proud of the plate)
RIB_RZ = 6.6    # half-width of the ribcage
RIBS = ((3.8, 2.6), (0.8, 3.0), (-2.2, 3.4))
# The sternum sits this many degrees round toward the viewer's side, so in his usual turns it
# shows near the middle of the opening with ribs curving away on both sides of it.
RIB_YAW = 24.0
RIB_SPAN = 62.0


def ribcage(cc: np.ndarray, t: np.ndarray) -> list[Node]:
    """A sternum down the middle of the hollow and curved ribs hanging from it on both sides:
    each rib is an arc round the body that droops toward the sides, so from any turn the ribs
    read as a ribcage (stacked arches) rather than straight bars."""
    ax, az = RIB_AXIS

    def p(theta: float, y: float, droop: float) -> np.ndarray:
        th = math.radians(theta + RIB_YAW)
        return cc + t @ _v((ax + RIB_RX * math.cos(th), y - droop * math.sin(math.radians(abs(theta))),
                            az + RIB_RZ * math.sin(th)))

    out: list[Node] = [
        RoundCone(RIB, p(0.0, 6.0, 0.0), p(0.0, -4.6, 0.0), 0.75, 0.6, group="ribs", thin=True),
    ]
    for y, droop in RIBS:
        for sgn in (1.0, -1.0):
            angs = [sgn * a for a in np.linspace(4.0, RIB_SPAN, 4)]
            for a0, a1 in zip(angs[:-1], angs[1:]):
                out.append(RoundCone(RIB, p(a0, y, droop), p(a1, y, droop), 0.55, 0.5,
                                     group="ribs", thin=True))
    return out


def torso(sk, pose: dict[str, Any], glow: float) -> list[Node]:
    t = sk.torso
    ch = sk["chest"]
    cc = ch + t @ _v((0.4, -4.2, 0.0))
    plate = SmoothUnion(
        Ellipsoid(ARMOR, cc, (7.6, 9.0, 9.8), R=t, group="armor"),
        Ellipsoid(ARMOR, sk["belly"] + t @ _v((0.0, -1.0, 0.0)), (5.2, 6.0, 6.6), R=t, group="armor"),
        k=2.0,
    )
    hole_c = cc + t @ _v((6.0, -0.8, HOLE_Z))
    hole = Ellipsoid(HOLLOW, hole_c, HOLE_R, R=t)
    out: list[Node] = [Subtract(plate, hole, k=0.6, b_material=True)]
    # The glowing core deep in the hollow, and a ribcage across the opening in front of it.
    core = cc + t @ _v((2.0, -1.0, HOLE_Z))
    out.append(Sphere(GLOW_CORE, core, CORE_R0 + CORE_RG * glow, group="glow"))
    out.append(Sphere(GLOW, core + t @ _v((2.6 + 0.9 * glow, 0.6, 1.0)), 0.9 + 1.2 * glow, group="glow"))
    out += ribcage(cc, t)
    # Gorget: a plate collar round the neck.
    out.append(RoundCone(ARMOR, ch + t @ _v((-0.6, -0.5, 0.0)), ch + t @ _v((0.0, 1.8, 0.0)), 5.4, 4.2, group="armor"))
    # Belt and the plate skirt (tassets) with a gold hem.
    belly = sk["belly"]
    out.append(Torus(GOLD, belly + t @ _v((0.0, -3.4, 0.0)), 5.6, 1.1, R=t, group="belt"))
    pel = sk["pelvis"]
    hips = sk.hips
    sk_top = pel + hips @ _v((0.0, 2.0, 0.0))
    sk_bot = pel + hips @ _v((0.6, -7.0, 0.0))
    skirt = RoundCone(ARMOR, sk_top, sk_bot, 6.4, 8.2, group="skirt")
    skirt_cut = Box(ARMOR, sk_bot + hips @ _v((0.0, -4.6 - 4.0, 0.0)), (14.0, 4.0, 14.0), R=hips)
    # No gold hem on the skirt: gold is kept for the crown, pauldron trims, belt and hilt, so the
    # body does not read as a stack of thin gold stripes.
    out.append(Subtract(skirt, skirt_cut))
    out.append(Capsule(SINEW, ch + t @ _v((-0.6, 2.0, 0.0)), sk["neck"], 1.8, group="neck"))
    out += tabard(sk, pose)
    return out


TABARD_POLY = [(-4.8, 0.0), (4.8, 0.0), (6.0, -28.0), (3.8, -32.5), (1.8, -29.0), (0.0, -34.5),
               (-2.0, -29.5), (-4.0, -33.0), (-6.0, -28.0)]


def tabard(sk, pose: dict[str, Any]) -> list[Node]:
    """The wine-red royal tabard hanging from the belt between the legs, swinging with the cloak."""
    top = sk["belly"] + sk.torso @ _v((0.0, -3.4, 0.0)) + sk.hips @ _v((6.6, 0.0, 0.0))
    swing = -float(pose["cloak_sway"]) * 1.2 - 9.0
    # Hangs down (gravity) whatever the lean; swings back when he moves.
    R = rot(0.0, float(pose.get("hip_yaw", 0.0)), -swing) @ np.array(
        [[0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]])
    panel = Prism(LINING, top, TABARD_POLY, 0.6, R=R, round=0.3, group="tabard")
    return [panel]


PAULDRON_R = (9.0, 6.0, 8.0)
PAULDRON_SPIKES = (10.0, 7.0)


def pauldron(sk, side: str) -> list[Node]:
    t = sk.torso
    sgn = 1.0 if side == "n" else -1.0
    sh = sk["shoulder_" + side]
    c = sh + t @ _v((-0.3, 1.4, sgn * 4.0))
    R = t @ rot(sgn * 30.0, 0.0, 0.0)
    g = "pauldron" + side
    # Big, high shoulder plates: the boss's shoulder line is far broader than his gaunt limbs.
    rad = _v(PAULDRON_R)
    out: list[Node] = [
        Ellipsoid(ARMOR, c, tuple(rad), R=R, group=g),
        Ellipsoid(GOLD, c + R @ _v((0.0, -rad[1] * 0.42, 0.0)), (rad[0] + 0.4, 2.2, rad[2] + 0.4), R=R,
                  group=g + "trim"),
    ]
    for dx, ln in ((-3.4, PAULDRON_SPIKES[0]), (1.8, PAULDRON_SPIKES[1])):
        base = c + R @ _v((dx, rad[1] * 0.68, sgn * 1.4))
        tip = base + R @ _v((-2.0, ln, sgn * 4.0))  # splayed outward: a broad, spiky shoulder line
        out.append(RoundCone(ARMOR, base, tip, 2.0, 0.4, group=g))
    return out


def hand_claw(sk, side: str, spread: float) -> list[Node]:
    """Bony fingers: curled round a grip at 0, splayed claws at 1."""
    el, ha = sk["elbow_" + side], sk["hand_" + side]
    fwd = (ha - el) / (np.linalg.norm(ha - el) + 1e-9)
    R = basis(fwd, (0.0, 1.0, 0.0))
    out: list[Node] = []
    if spread < 0.3:
        return out
    for i, (fy, fz) in enumerate(((0.6, 1.0), (0.0, -0.2), (-0.7, -1.2))):
        base = ha + R @ _v((1.6, fy, fz))
        tip = base + R @ _v((3.6 * spread, fy * 2.0 - 1.6, fz * 1.8))
        out.append(RoundCone(BONE, base, tip, 0.75, 0.45, group="claw" + side))
    return out


def arm(sk, side: str, pose: dict[str, Any]) -> list[Node]:
    sh, el, ha = sk["shoulder_" + side], sk["elbow_" + side], sk["hand_" + side]
    g = "arm" + side
    out: list[Node] = [
        RoundCone(SINEW, sh, el, 2.2, 1.7, group=g),
        Sphere(ARMOR, el, 2.6, group=g),
        RoundCone(ARMOR, el + (ha - el) * 0.12, ha - (ha - el) * float(pose.get("cuff", 0.3)), 2.3, 3.0,
                  group=g),
        Sphere(BONE, ha, 2.5 * float(pose.get("fist", 1.0)), group=g + "hand"),
    ]
    if side == "f":
        out += hand_claw(sk, side, float(pose["claw_f"]) * (1.0 - float(pose["two_hand"])))
    return out


def leg(sk, side: str) -> list[Node]:
    hp, kn, an, to = sk["hip_" + side], sk["knee_" + side], sk["ankle_" + side], sk["toe_" + side]
    g = "leg" + side
    return [
        RoundCone(ARMOR, hp, kn, 3.4, 2.7, group=g),
        Sphere(ARMOR, kn, 3.2, group=g + "knee"),
        RoundCone(ARMOR, kn + (an - kn) * 0.1, an, 3.0, 2.2, group=g),
        RoundCone(ARMOR, an, to, 2.6, 1.1, group=g),
    ]


# Where the viewer sits, in model space (before the king's turn): the blade's flat faces it.


def sword_frame(pose: dict[str, Any]) -> tuple[np.ndarray, np.ndarray]:
    """Blade direction and the blade's local axes (x along, y toward the edge, z out of the
    flat). The flat is turned to the viewer; sword_roll turns it further about the blade."""
    a = math.radians(float(pose["sword_ang"]))
    o = math.radians(float(pose["sword_out"]))
    d = _v((math.cos(a) * math.cos(o), math.sin(a) * math.cos(o), math.sin(o)))
    view = screen_axes(pose)[0]
    n0 = view - d * float(np.dot(view, d))
    n0 = n0 / (np.linalg.norm(n0) + 1e-9)
    R = basis(d, np.cross(n0, d)) @ rot(float(pose["sword_roll"]), 0.0, 0.0)
    return d, R


# The cleaver in blade space: x from the guard to the tip, +y the notched edge, -y the spine.
_BL = BLADE_LEN
EDGE_PTS = [(0.0, 3.6), (8.0, 4.4), (9.8, 2.6), (11.8, 4.8), (_BL - 24.0, 6.4), (_BL - 22.2, 3.8),
            (_BL - 20.0, 6.8), (_BL - 12.0, 7.8), (_BL - 9.8, 5.0), (_BL - 7.6, 8.4), (_BL - 2.5, 8.6),
            (_BL, 5.8)]
SPINE_PTS = [(_BL - 0.6, -0.6), (_BL - 9.0, -3.8), (0.0, -3.0)]
BLADE_POLY = EDGE_PTS + SPINE_PTS
BODY_POLY = [(x, y - 2.3) for x, y in EDGE_PTS[:-1]] + [(_BL - 1.0, 3.2)] + SPINE_PTS


def grip_mid(sk, pose: dict[str, Any], d: np.ndarray) -> np.ndarray:
    """The middle of the grip (the near hand's place unless the pose sets `grip_at`)."""
    return sk["hand_n"] + d * float(pose.get("grip_at", 0.0))


def sword(sk, pose: dict[str, Any]) -> Node:
    d, R = sword_frame(pose)
    hand = grip_mid(sk, pose, d)
    guard = hand + d * (GRIP_LEN * 0.5 + 0.6)
    b0 = guard + d * 0.8
    parts: list[Node] = [
        Prism(IRON, b0, BODY_POLY, 1.25, R=R, round=0.45, group="sword"),
        Prism(EDGE, b0, BLADE_POLY, 0.7, R=R, round=0.3, group="sword"),
        Box(GOLD, guard, (1.2, 6.6, 2.0), R=R, round=0.5, group="hilt"),
        Capsule(GRIP, hand - d * (GRIP_LEN * 0.5), guard, 1.3, group="grip"),
        Sphere(GOLD, hand - d * (GRIP_LEN * 0.5 + 1.5), 2.0, group="hilt"),
    ]
    node: Node = Union(*parts)
    if float(pose["bury"]) > 0:
        ground = Box(IRON, (0.0, 200.0, 0.0), (400.0, 200.0, 400.0))
        node = Intersect(node, ground)
    tip = guard + d * BLADE_LEN
    return bounded(node, [hand - d * (GRIP_LEN * 0.5 + 3.5), tip, guard], 10.0)




def debris(pose: dict[str, Any], tip: np.ndarray) -> list[Node]:
    """Rubble thrown up round the point where the blade bit into the ground (laid out on screen:
    sx pixels right, y up, a little toward the viewer so the body does not hide it)."""
    k = float(pose["debris"])
    if k <= 0.01:
        return []
    # debris_fly (phase 10 clips): how high and far the chunks have flown (1 = the slam key).
    fly = float(pose.get("debris_fly", 1.0))
    rng = np.random.default_rng(91)
    _, GROUND_X, GROUND_Z = screen_axes(pose)
    out: list[Node] = []
    # A few big chunks (they must read at 1x) and two resting on the ground.
    for i, (sx, y, r) in enumerate(((-13.0, 10.0, 3.0), (11.0, 16.0, 2.6), (-5.0, 25.0, 2.0),
                                    (-25.0, 2.8, 2.6), (21.0, 2.6, 2.2))):
        rr = r * (0.6 + 0.4 * k)
        c = tip + GROUND_X * (sx * k * 0.8 * (0.5 + 0.5 * fly)) + GROUND_Z * 2.0
        c[1] = rr + (y - rr) * k * fly
        out.append(Box(STONE, c, (rr, rr * 0.75, rr), R=rot(*rng.uniform(0, 90, 3)), round=0.35,
                       group="debris%d" % i))
    return out


# Rot-green cracks along the floor row, running out from both sides of the blade where it bit
# into the ground: (pixels out from the blade's edge, rows up). Hot right by the blade, dimmer
# further out; a short burst rises along each side of the blade.
CRACK_OUT = [(1, 0), (2, 0), (3, 1), (4, 1), (5, 1), (6, 0), (7, 0), (8, 1), (9, 1), (10, 0),
             (11, 0), (12, 1), (13, 1)]
CRACK_BURST = [(1, 1), (1, 2), (2, 3), (4, 2)]
CRACK_REACH = (13, 9)  # left, right


def floor_cracks(frame: Frame, cam: Camera, pose: dict[str, Any]) -> None:
    """Draws the slam's glowing cracks on the floor row (the billboard's ground line), into the
    empty pixels only, so feet and rubble stay in front."""
    k = float(pose["debris"])
    if k <= 0.01:
        return
    tip = ground_point(skeleton(pose), pose)
    x0 = int(math.floor(cam.project(world(tip, pose))[0]))
    floor = frame.H - 2
    # The blade's edges on the floor row (the cracks start where the steel ends).
    xl = xr = x0
    while xl > 1 and frame.part[floor, xl - 1] >= 0:
        xl -= 1
    while xr < frame.W - 2 and frame.part[floor, xr + 1] >= 0:
        xr += 1
    part = frame.add_part(GLOW_CORE, "glow")
    for sgn, edge, reach in ((-1, xl, CRACK_REACH[0]), (1, xr, CRACK_REACH[1])):
        for out, up in CRACK_OUT[:int(round(reach * k))] + CRACK_BURST:
            x, y = edge + sgn * out, floor - up
            if 0 < x < frame.W - 1 and frame.part[y, x] < 0:
                frame.part[y, x] = part
                frame.idx[y, x] = 3 if out <= 4 else (2 if out <= 8 else 1)
                frame.depth[y, x] = 1e6


def skeleton(pose: dict[str, Any]):
    """The posed skeleton (model space); the far hand slides onto the grip by `two_hand`."""
    sk = pose_skeleton(KING, pose)
    k = float(pose.get("two_hand", 0.0))
    if k > 0.01:
        d, _ = sword_frame(pose)
        grip = sk["hand_n"] - d * (GRIP_LEN * float(pose.get("grip_f", GRIP_F)))
        p2 = dict(pose)
        hf = _v(pose.get("hand_f", sk["hand_f"]))
        p2["hand_f"] = tuple(hf + (grip - hf) * k)
        sk = pose_skeleton(KING, p2)
    return sk


def model(pose: dict[str, Any]) -> Node:
    """The whole king in one pose (see the module doc for the pose keys), turned to the viewer."""
    sk = skeleton(pose)
    glow = float(pose["glow"])
    hc = sk["head"]
    if "crown_at" in pose:  # the crown has fallen off: bounded on its own
        ca = _v(pose["crown_at"])
        head: Node = Union(bounded(Union(*skull(sk, pose, glow)), [hc + _v((0, 9, 0)), hc - _v((0, 9, 0))], 12.0),
                           bounded(crown(sk, pose), [ca - _v((9, 9, 9)), ca + _v((9, 9, 9))], 3.0))
    else:
        head = bounded(Union(*skull(sk, pose, glow), crown(sk, pose)), [hc + _v((0, 14, 0)), hc - _v((0, 9, 0))], 12.0)
    groups: list[Node] = [
        head,
        bounded(Union(*torso(sk, pose, glow), *pauldron(sk, "n"), *pauldron(sk, "f")),
                [sk["chest"], sk["pelvis"] - _v((0, 12, 0)), sk["neck"]], 20.0),
        cloak(sk, pose),
    ]
    for s in ("n", "f"):
        groups.append(bounded(Union(*arm(sk, s, pose)),
                              [sk["shoulder_" + s], sk["elbow_" + s], sk["hand_" + s]], 8.0))
        groups.append(bounded(Union(*leg(sk, s)),
                              [sk["hip_" + s], sk["knee_" + s], sk["ankle_" + s], sk["toe_" + s]], 4.5))
    groups.append(sword(sk, pose))
    groups.extend(debris(pose, ground_point(sk, pose)))
    return Moved(Union(*groups), R=turn_R(pose))


def ground_point(sk, pose: dict[str, Any]) -> np.ndarray:
    """Where the blade meets the ground (or its tip, if it does not reach)."""
    d, _ = sword_frame(pose)
    guard = grip_mid(sk, pose, d) + d * (GRIP_LEN * 0.5 + 0.6)
    tip = guard + d * (BLADE_LEN + 0.8)
    if tip[1] < 0.0 < guard[1]:
        tip = guard + (tip - guard) * (guard[1] / (guard[1] - tip[1]))
    return tip


# --- Rendering ----------------------------------------------------------------------------------


def _seam(pose: dict[str, Any]) -> float:
    """How much of the blade's rot seam shows (0 = none, 1 = all of it, lit). It shows in the tell
    (glow >= 0.9); the swing keys set `seam` to keep it steady through the whole chop while the
    core dims, and to kindle it up the blade and let it die back (see the module doc)."""
    return float(pose.get("seam", 1.0 if float(pose["glow"]) >= 0.9 else 0.0))


def _overlays(frame: Frame, cam: Camera, pose: dict[str, Any], portrait: bool = False) -> None:
    """Things too thin for the model: the rot seam that lights along the blade in the tell, and
    the gaps between the teeth in the portrait."""
    floor_cracks(frame, cam, pose)
    if portrait:
        for pts in teeth_lines(pose):
            line3d(frame, cam, [world(p, pose) for p in pts], HOLLOW, 0, group="teeth", depth_bias=0.9)
        skull_crack(frame, cam, pose)
        nose_hole(frame, cam, pose)
    lit = _seam(pose)
    if lit > 0.05 and not portrait:
        sk = skeleton(pose)
        d, R = sword_frame(pose)
        guard = grip_mid(sk, pose, d) + d * (GRIP_LEN * 0.5 + 0.6)
        # Along whichever flat faces the viewer: a blade rolled over (sword_roll 180, the notched
        # edge leading a chop) shows its back flat, and the seam must not wink out there.
        face = 1.0 if float(np.dot(R[:, 2], screen_axes(pose)[0])) >= 0.0 else -1.0
        side = R @ _v((0.0, 0.0, 1.6 * face))
        pts = [guard + d * 3.0 + side + R @ _v((0, 1.0, 0)), guard + d * (BLADE_LEN - 6.0) + side + R @ _v((0, 3.0, 0))]
        if "seam" in pose:
            pts[1] = pts[0] + (pts[1] - pts[0]) * min(lit, 1.0)
            seam_line(frame, cam, [world(p, pose) for p in pts], SEAM_IDX if lit >= 0.99 else 0)
        else:
            line3d(frame, cam, [world(p, pose) for p in pts], GLOW, SEAM_IDX, group="glow", depth_bias=2.0)


def seam_line(frame: Frame, cam: Camera, pts: list[np.ndarray], idx: int = SEAM_IDX) -> None:
    """The sword swing's seam (poses with the `seam` key): a 4-connected stepped line (a pixel
    at every corner step, so a steep diagonal never breaks into dots), drawn only on the blade's
    own pixels (a buried or hidden part of the blade shows no seam floating in the air)."""
    (x0, y0, d0), (x1, y1, d1) = cam.project(pts[0]), cam.project(pts[1])
    part = frame.add_part(GLOW, "glow")
    n = int(max(abs(x1 - x0), abs(y1 - y0)) * 4) + 1
    cells: list[tuple[int, int, float]] = []
    for k in range(n + 1):
        u = k / n
        c = (int(math.floor(x0 + (x1 - x0) * u)), int(math.floor(y0 + (y1 - y0) * u)), d0 + (d1 - d0) * u)
        if cells and cells[-1][:2] == c[:2]:
            continue
        if cells and cells[-1][0] != c[0] and cells[-1][1] != c[1]:
            # A corner step: fill the corner on the side the true line passes closer to.
            px, py, pd = cells[-1]
            a, b = (c[0], py), (px, c[1])
            dist = [abs((y1 - y0) * (q[0] + 0.5 - x0) - (x1 - x0) * (q[1] + 0.5 - y0)) for q in (a, b)]
            q = a if dist[0] <= dist[1] else b
            cells.append((q[0], q[1], (pd + c[2]) * 0.5))
        cells.append(c)
    for x, y, dd in cells:
        if 0 <= x < frame.W and 0 <= y < frame.H and frame.part[y, x] >= 0 \
                and frame.groups[frame.part[y, x]] == "sword":
            frame.put(x, y, part, idx, dd - 2.0)


def finish_frame(frame: Frame) -> np.ndarray:
    contours(frame, gap=2.5, steps=2)
    cleanup(frame)
    outline(frame)
    return frame.rgba()


# The swing smear (the chop's hit cell): the area the cleaver swept since the cell before, from
# where it was (`smear_from`: sword_ang, sword_out and the near hand x, y, z of that cell) to where
# it is, filled in its edge colours: a wedge along the outer part of the blade, widest against it
# and tapering back toward where the swing came from, with a bright rim along the tip's path,
# pale next to the blade and darker further back, so it reads as one heavy sweep of the blade.
# SMEAR_BANDS[smear] = per band, lightest first: (share of the blade it covers from the tip, share
# of the sweep it leaves out from its start, EDGE colour index; a pixel takes the first band that
# covers it). Each band starts SMEAR_TAPER[smear] as deep as it ends against the blade. Only the
# strike has one (1): the swing's other cells read by their spacing, without trails.
SMEAR_BANDS: dict[int, list[tuple[float, float, int]]] = {
    # A thin arc off the tip: deeper bands filled in an opaque slab that read as an axe head.
    1: [(0.10, 0.0, -1), (0.30, 0.5, -3)],
}
SMEAR_TAPER = {1: 0.25}
SMEAR_CURVE = 1.6  # > 1: the bands stay thin along the arc and swell near the blade (a crescent)
SMEAR_STEPS = 48  # in-between blades rasterised per smear
SMEAR_MARGIN = 3  # clear pixels the smear keeps from the frame's left and right edges


def _smear_quad(pose: dict[str, Any], hand: np.ndarray, cam: Camera, x0: float,
                scale: float = 1.0) -> list[tuple[float, float]]:
    """The blade's outline from `x0` (blade space, guard to tip) out to the tip, in pixels, with
    the near hand at `hand` and the blade's length times `scale` (the notches left out: a smear
    is a soft shape)."""
    d, R = sword_frame(pose)
    b0 = hand + d * (float(pose.get("grip_at", 0.0)) + GRIP_LEN * 0.5 + 1.4)
    e0 = 3.6 + (8.6 - 3.6) * x0 / BLADE_LEN
    pts = [(x0, -3.2), (BLADE_LEN - 9.0, -3.8), (BLADE_LEN - 0.6, -0.6), (BLADE_LEN, 5.8),
           (BLADE_LEN - 2.5, 8.6), (x0, e0)]
    out = []
    for x, y in pts:
        px, py, _ = cam.project(world(b0 + R @ _v((max(x, x0) * scale, y, 0.0)), pose))
        out.append((px, py))
    return out


def swing_smear(rgba: np.ndarray, cam: Camera, pose: dict[str, Any]) -> np.ndarray:
    """Draws the swing smear (see SMEAR_BANDS) into the empty pixels only, so the king, his blade
    and their outline stay on top, and never into the frame's clear border."""
    k = int(pose.get("smear", 0))
    if k <= 0 or "smear_from" not in pose:
        return rgba
    from PIL import Image, ImageDraw

    ang0, out0, *hand0 = (float(v) for v in pose["smear_from"])
    ang1, out1 = float(pose["sword_ang"]), float(pose["sword_out"])
    sweep = (ang1 - ang0 + 180.0) % 360.0 - 180.0  # the short way round
    h0, h1 = _v(hand0), skeleton(pose)["hand_n"]

    def blade_at(t: float) -> tuple[dict[str, Any], np.ndarray]:
        return dict(pose, sword_ang=ang0 + sweep * t, sword_out=out0 + (out1 - out0) * t), h0 + (h1 - h0) * t

    # Where the swept arc would leave the frame (a swing past the frame's edge), the in-between
    # blades are drawn shorter by a smooth dip (none at either end, so the smear still meets both
    # blades): its outer edge stays a rounded arc instead of being cut flat by the border.
    lo, hi = SMEAR_MARGIN + 0.5, S - SMEAR_MARGIN - 0.5
    dip = 0.0
    for i in range(1, 16):
        t = i / 16.0
        p, hand = blade_at(t)
        g = np.array(_smear_quad(p, hand, cam, 0.0, 0.0)[0])
        fit = 1.0
        for c in _smear_quad(p, hand, cam, 0.0):
            for ax, (cl, ch) in enumerate(((lo, hi), (2.5, S - 3.0))):
                dv = c[ax] - g[ax]
                if g[ax] + dv < cl and dv < 0:
                    fit = min(fit, (cl - g[ax]) / dv)
                elif g[ax] + dv > ch and dv > 0:
                    fit = min(fit, (ch - g[ax]) / dv)
        dip = max(dip, (1.0 - fit) / math.sin(math.pi * t))
    dip = min(dip, 0.4)
    out = rgba.copy()
    free = rgba[..., 3] == 0
    free[:2, :] = False
    free[S - 2:, :] = False
    free[:, :SMEAR_MARGIN] = False
    free[:, S - SMEAR_MARGIN:] = False
    taken = np.zeros(free.shape, dtype=bool)
    taper = SMEAR_TAPER[k]
    for share, skip, ci in SMEAR_BANDS[k]:
        img = Image.new("L", (S * 4, S * 4), 0)
        draw = ImageDraw.Draw(img)
        for i in range(SMEAR_STEPS + 1):
            u = i / SMEAR_STEPS
            t = skip + (1.0 - skip) * u
            x0 = BLADE_LEN * (1.0 - share * (taper + (1.0 - taper) * u ** SMEAR_CURVE))
            p, hand = blade_at(t)
            quad = _smear_quad(p, hand, cam, x0, 1.0 - dip * math.sin(math.pi * t))
            draw.polygon([(x * 4.0, y * 4.0) for x, y in quad], fill=255)
        # A pixel joins the band when most of it is covered (4x4 samples), so edges stay clean.
        cover = np.asarray(img, dtype=np.float32).reshape(S, 4, S, 4).mean(axis=(1, 3)) / 255.0
        m = (cover >= 0.5) & free & ~taken
        c = EDGE.colors[ci]
        out[m, :3] = [int(c[j:j + 2], 16) for j in (1, 3, 5)]
        out[m, 3] = 255
        taken |= m
    return out


def ground_contacts(pose: dict[str, Any]) -> list[np.ndarray]:
    """Points where the king touches the ground in this pose (feet, a knee, a planted blade)."""
    sk = skeleton(pose)
    pts = []
    for side in "nf":
        for j in ("ankle_", "toe_", "knee_"):
            p = sk[j + side]
            if p[1] < 4.5:
                pts.append(_v((p[0], 0.0, p[2])))
    if float(pose["bury"]) > 0:
        pts.append(ground_point(sk, pose))
    return pts


def _lowest_row(pose: dict[str, Any], cam: Camera) -> float:
    gz = screen_axes(pose)[2]
    return max(cam.project(world(p + gz * 2.0, pose))[1] for p in ground_contacts(pose))


_CAM: list[Camera] = []


def camera(pose: dict[str, Any] | None = None) -> Camera:
    """The enemy-sheet camera. It is fitted once so the idle pose stands centred with its feet on
    the second-to-last row; for other poses it only shifts by whole rows so that pose's ground
    contact sits on the same row (the sprite is a billboard: its floor line must not move)."""
    if not _CAM:
        cam = Camera(S, S, scale=SHEET_SCALE, face="left")
        f = render(model(POSES["idle"]), cam, ss=3)
        ys, xs = np.nonzero(f.part >= 0)
        cam.cx = float(round(cam.cx - (S / 2.0 - (xs.min() + xs.max() + 1) / 2.0) * cam.scale))
        cam.cy = float(round(cam.cy + (S - 2 - _feet_row(f)) * cam.scale - 0.5)) + 0.5
        _CAM.append(cam)
        _CAM.append(_lowest_row(POSES["idle"], cam))  # type: ignore[arg-type]
    base: Camera = _CAM[0]
    cam = Camera(S, S, scale=SHEET_SCALE, face="left", cx=base.cx, cy=base.cy)
    if pose is not None:
        shift = round(float(_CAM[1]) - _lowest_row(pose, cam))  # type: ignore[arg-type]
        cam.cy += shift * cam.scale
    return cam


def _hit_points(frame: Frame, cam: Camera, pose: dict[str, Any], ys: np.ndarray, xs: np.ndarray) -> np.ndarray:
    """Model-space surface points behind the given pixels (pixel centre ray at the stored depth)."""
    vx = (xs + 0.5 - cam.W / 2.0) * cam.scale + cam.cx
    vy = (cam.H - (ys + 0.5)) * cam.scale + cam.cy - 0.5 * cam.scale
    V = np.stack([vx, vy, np.full(vx.shape, cam.z0)], axis=1)
    O = V @ cam.R
    D = np.array([0.0, 0.0, -1.0]) @ cam.R
    P = O + frame.depth[ys, xs][:, None] * D
    return P @ turn_R(pose)


# Rust only eats the big plates (breastplate, pauldrons, plate skirt): on thin greaves, arm
# guards and the sword it reads as blood or stray pixels. Patches smaller than this are dropped.
RUST_GROUPS = ("armor", "pauldronn", "pauldronf", "skirt")
RUST_MIN_PATCH = 6


def _drop_small(mask: np.ndarray, min_size: int) -> np.ndarray:
    """Keeps only the 4-connected regions of `mask` with at least `min_size` pixels."""
    out = mask.copy()
    seen = np.zeros(mask.shape, dtype=bool)
    H, W = mask.shape
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        stack = [(y0, x0)]
        seen[y0, x0] = True
        comp = []
        while stack:
            y, x = stack.pop()
            comp.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if len(comp) < min_size:
            for y, x in comp:
                out[y, x] = False
    return out


def rust(frame: Frame, cam: Camera, pose: dict[str, Any], leaves: list[Prim], amount: float = 0.4,
         freq: float = 0.26) -> None:
    """Eats rust patches into the armour plates. The noise is read in each plate's own space, so
    the patches stay put on the plate from pose to pose (no swimming in animation)."""
    ys, xs = np.nonzero(frame.part >= 0)
    plate = np.array([leaf.mat is ARMOR and leaf.group in RUST_GROUPS
                      and (leaf.group == "skirt" or not isinstance(leaf, RoundCone)) for leaf in leaves]
                     + [False] * (len(frame.mats) - len(leaves)), dtype=bool)
    keep = plate[frame.part[ys, xs]]
    ys, xs = ys[keep], xs[keep]
    if ys.size == 0:
        return
    P = _hit_points(frame, cam, pose, ys, xs)
    parts = frame.part[ys, xs]
    mask = np.zeros(ys.size, dtype=bool)
    for p in np.unique(parts):
        leaf = leaves[p]
        sel = parts == p
        if isinstance(leaf, RoundCone):
            Q = (P[sel] - leaf.a) @ basis(leaf.b - leaf.a)
        else:
            Q = leaf.local(P[sel])
        seed = sum(ord(c) for c in leaf.group) * 7 + int(p) % 3
        n = fbm3(Q * freq + 11.0, seed=seed, octaves=2)
        mask[sel] = n > amount
    rust_parts: dict[str, int] = {}
    hit = np.zeros(frame.part.shape, dtype=bool)
    hit[ys[mask], xs[mask]] = True
    # No specks: a patch pixel needs at least two patch neighbours, repeated until stable, so
    # only solid patches survive (pairs and short strings of rust pixels read as noise).
    for _ in range(4):
        nb = np.zeros(hit.shape, dtype=np.int32)
        nb[1:, :] += hit[:-1, :]
        nb[:-1, :] += hit[1:, :]
        nb[:, 1:] += hit[:, :-1]
        nb[:, :-1] += hit[:, 1:]
        new = hit & (nb >= 2)
        if (new == hit).all():
            break
        hit = new
    hit = _drop_small(hit, RUST_MIN_PATCH)
    for y, x in zip(*np.nonzero(hit)):
        g = frame.groups[frame.part[y, x]]
        if g not in rust_parts:
            rust_parts[g] = frame.add_part(RUST, g)
        frame.part[y, x] = rust_parts[g]
        frame.idx[y, x] = min(frame.idx[y, x], RUST.top() - 1)


def _feet_row(frame: Frame) -> int:
    """The lowest row covered by the legs (boots, or a knee on the ground): the floor row."""
    legs = np.array([g.startswith("leg") for g in frame.groups] + [False])
    mask = (frame.part >= 0) & legs[np.where(frame.part >= 0, frame.part, -1)]
    rows = np.nonzero(mask.any(axis=1))[0]
    return int(rows.max()) if rows.size else frame.H - 2


def render_pose(pose: dict[str, Any], cam: Camera | None = None, portrait: bool = False) -> np.ndarray:
    """One finished RGBA frame of the king in `pose` (enemy-sheet camera unless given; with it,
    the lowest pixel always lands on the floor row, S - 2, re-rendering once if needed)."""
    node = model(pose)
    if cam is None:
        cam = camera(pose)
        frame = render(node, cam, ss=3)
        for _ in range(3):
            low = _feet_row(frame)
            if low == S - 2:
                break
            cam.cy += (S - 2 - low) * cam.scale
            frame = render(node, cam, ss=3)
        # The floor hides whatever reaches below the floor row (a planted blade, rubble, cloth).
        frame.part[S - 1:, :] = -1
    else:
        frame = render(node, cam, ss=3)
    if not portrait:
        # (At portrait size the rust patches turn into big brown blots on the shoulders.)
        rust(frame, cam, pose, node.leaves())
    _overlays(frame, cam, pose, portrait)
    rgba = finish_frame(frame)
    # After the outline: a smear is motion, not a solid thing, so it gets no dark edge.
    return rgba if portrait else swing_smear(rgba, cam, pose)


# Portrait framing: model units per pixel, and the pixel (column, row) the skull centre lands on.
PORTRAIT_SCALE = 0.42
PORTRAIT_HEAD_AT = (25.0, 26.0)


def portrait_camera() -> Camera:
    sk = skeleton(PORTRAIT_POSE)
    sc = PORTRAIT_SCALE
    cam = Camera(PORTRAIT, PORTRAIT, scale=sc, face="left")
    v = cam.view(world(sk["head"], PORTRAIT_POSE))
    cam.cx = float(v[0]) - (PORTRAIT_HEAD_AT[0] - PORTRAIT / 2.0) * sc
    cam.cy = float(v[1]) - (PORTRAIT - 0.5 - PORTRAIT_HEAD_AT[1]) * sc
    return cam


def check_margins(rgba: np.ndarray, name: str) -> list[str]:
    a = rgba[..., 3] > 0
    bad = []
    if a[0].any():
        bad.append("top")
    if a[:, 0].any():
        bad.append("left")
    if a[:, -1].any():
        bad.append("right")
    return ["%s touches the %s edge" % (name, b) for b in bad]


def _review_pictures(ctx, sheet: np.ndarray, por: np.ndarray) -> None:
    """Extra pictures for review only: the sheet at 1x and 3x, the old placeholder above the new
    sheet at the same pixel size, and the portrait at 1x and 2x."""
    import os

    from PIL import Image

    from kit.context import PREVIEW

    ctx.extra("sheet_1x.png", sheet, scale=1, frame_w=S)
    ctx.extra("sheet_3x.png", sheet, scale=3, frame_w=S)
    old_path = os.path.join(PREVIEW, "_old", "enemies", ID + ".png")
    if os.path.exists(old_path):
        old = np.array(Image.open(old_path).convert("RGBA"))
        w = max(old.shape[1], sheet.shape[1])
        both = np.zeros((old.shape[0] + 4 + sheet.shape[0], w, 4), dtype=np.uint8)
        both[:old.shape[0], :old.shape[1]] = old
        both[old.shape[0] + 4:, :sheet.shape[1]] = sheet
        ctx.extra("old_vs_new.png", both, scale=2)
    ctx.extra("portrait_1x_2x.png", np.concatenate(
        [np.pad(por, ((PORTRAIT // 2, PORTRAIT // 2), (0, 4), (0, 0))),
         np.kron(por, np.ones((2, 2, 1), dtype=np.uint8))], axis=1), scale=2)


# --- Clips (phase 10) ----------------------------------------------------------------------------
# The review GIFs breathe at game speed: this mirrors idle_cycle_percent in
# data/enemies/hollow_king.tres (the game's number; change both together).
IDLE_CYCLE_PERCENT = 130
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
H = HIP_Y

# Breathing: the hands stay on the pommel (the planted sword never moves); the chest rises, the
# cloak stirs and the rot core swells and brightens like a slow heartbeat.
BREATH = _k("idle", lean=5.5, head=(10.0, -12.0, 0.0), glow=0.75, cloak_sway=1.5, cloak_flare=1.64)

# The sword swing, an overhead chop (windup, windup_hold, lunge, contact, recoil), every hit of a
# string. Screen angles of the blade (0 = toward the heroes, 90 = up, 180 = behind him):
# 232 (down and back) -> 156 -> 110 held high -> 90 -> 61 -> 22 -> -40 on the hit -> -50 -> -42,
# then -58 -> 234 back toward the coil. The steps into the hit grow (20, 29, 39, 62 degrees), so
# the chop speeds up all the way into the hit. Throughout: one blade length on screen (the blade
# keeps a 25 degree tilt toward the viewer, so it never pumps); the skull stays turned to the
# viewer as in idle and no hand, guard or arm crosses the face; both fists hold the grip, the far
# one above the near one on the blade's side (two_hand, grip_at, grip_f), bared and a size bigger
# so both read (fist, cuff); the rot seam kindles up the blade in the first coil cell, stays lit to
# the recoil and dies back in its last cell (`seam`); the blade never rests point-down on the floor
# (it reads as a leg there). He steps in with the far foot (the one toward the heroes on screen),
# both feet at the same depth from the viewer so they stand on the same floor row.
# windup[0]: wrenches the cleaver out of the floor and swings it down and back across the cloak;
# the seam starts to kindle from the guard (seam < 1: part of the blade, darker green).
COIL_1 = _pose(pelvis=(-1.0, H - 1.2, 0.0), lean=3.0, head=(12.0, -12.0, 0.0), hand_n=(6.9, 54.1, 8.0),
               elbow_n=(0.2, -1.0, 0.6), elbow_f=(0.2, -1.0, -0.6), foot_n=(-3.9, 3.0, 10.5),
               foot_f=(9.4, 3.0, -7.8), sword_ang=-80.2, sword_out=50.3, two_hand=1.0, grip_at=2.0,
               grip_f=-0.44, fist=1.2, cuff=0.42, glow=0.85, seam=0.45, jaw=6.0, turn=26.0,
               cloak_sway=-2.0, cloak_flare=1.45)
# windup[1]: cocks it back at shoulder height, the seam lit along the whole blade.
COIL_2 = _pose(pelvis=(-3.0, H - 3.0, 0.0), lean=-3.0, twist=-10.0, head=(-6.0, -4.0, 0.0),
               hand_n=(-19.6, 70.0, 8.0), elbow_n=(-0.6, -0.6, 0.8), elbow_f=(0.2, -0.6, -1.0),
               foot_n=(-9.6, 3.0, 10.6), foot_f=(10.3, 3.0, -11.5), sword_ang=123.8, sword_out=58.3,
               two_hand=1.0, grip_at=2.0, grip_f=-0.44, fist=1.2, cuff=0.42, glow=1.0, seam=1.0,
               jaw=12.0, turn=20.0, cloak_sway=-4.0, cloak_flare=1.25, cloak_lift=0.15)
# windup[2] and windup_hold[0], the tell: crouched to spring, both fists on the grip just
# beside the crown (a clear gap between hilt and crown), the blade high above his head.
CLEAVE_UP = _pose(pelvis=(-4.0, H - 6.0, 0.0), lean=-6.0, twist=-6.0, head=(-12.0, -2.0, 0.0),
                  hand_n=(-30.2, 76.1, 4.0), elbow_n=(-1.0, -1.2, 0.6), elbow_f=(0.6, -0.4, -0.8),
                  foot_n=(-11.5, 3.0, 10.5), foot_f=(10.8, 3.0, -12.6), sword_ang=91.4, sword_out=24.2,
                  two_hand=1.0, grip_at=2.0, grip_f=-0.44, fist=1.2, cuff=0.42, glow=1.0, seam=1.0,
                  jaw=20.0, turn=18.0, cloak_sway=-6.0, cloak_flare=1.1, cloak_lift=0.3)
# windup_hold[1]: the blade trembles a hair higher, the jaw works, the cloak stirs.
CLEAVE_SHIVER = _pose(pelvis=(-4.0, H - 6.4, 0.0), lean=-6.0, twist=-6.0, head=(-14.0, -1.0, 2.0),
                      hand_n=(-30.2, 76.7, 4.0), elbow_n=(-1.0, -1.2, 0.6), elbow_f=(0.6, -0.4, -0.8),
                      foot_n=(-11.5, 3.0, 10.5), foot_f=(10.8, 3.0, -12.6), sword_ang=92.6,
                      sword_out=25.6, two_hand=1.0, grip_at=2.0, grip_f=-0.44, fist=1.2, cuff=0.42,
                      glow=1.0, seam=1.0, jaw=27.0, turn=18.0, cloak_sway=-6.5, cloak_flare=1.12,
                      cloak_lift=0.32)
# lunge[0]: the far foot lifts to step in as the blade comes upright over his shoulder.
SWING_1 = _pose(pelvis=(-3.0, H - 4.0, -0.7), lean=-4.0, twist=-6.0, head=(-12.0, -2.0, 0.0),
                hand_n=(-24.4, 74.3, 3.0), elbow_n=(-1.0, -1.2, 0.6), elbow_f=(0.6, -0.4, -0.8),
                foot_n=(-10.7, 3.0, 9.6), foot_f=(12.5, 6.0, -14.4), knee_f=(1.0, 0.2, -0.2),
                toe_f=10.0, sword_ang=79.1, sword_out=10.4, two_hand=1.0, grip_at=2.0, grip_f=-0.44,
                fist=1.2, cuff=0.42, glow=0.95, seam=1.0, jaw=18.0, turn=18.0, cloak_sway=-8.0,
                cloak_flare=1.1, cloak_lift=0.35, cloak_open=10.0)
# lunge[1]: the body leans in ahead of the arms, the blade tipping forward past the crown's
# back (the face stays clear).
SWING_2 = _pose(pelvis=(-0.93, H - 4.1, -0.77), lean=4.0, twist=-4.0, head=(-14.0, -4.0, 2.0),
                hand_n=(-24.5, 71.0, 2.0), elbow_n=(-1.0, -1.0, 0.4), elbow_f=(0.6, -0.4, -0.6),
                foot_n=(-9.6, 3.0, 10.6), foot_f=(13.5, 3.0, -15.0), sword_ang=59.6, sword_out=-8.1,
                two_hand=1.0, grip_at=2.0, grip_f=-0.44, fist=1.2, cuff=0.42, glow=0.85, seam=1.0,
                jaw=16.0, turn=20.0, cloak_sway=-12.0, cloak_flare=1.15, cloak_hem=4.0, cloak_lift=0.4,
                cloak_open=25.0)
# lunge[2], just before impact: the fists swing down in front of him, below and left of the
# face, the blade out toward the hero.
SWING_3 = _pose(pelvis=(-1.82, H - 5.6, 1.55), lean=2.0, side_lean=-4.0, twist=2.0,
                head=(-12.0, -8.0, 4.0), hand_n=(15.3, 60.0, 2.0), elbow_n=(0.3, -0.8, 0.8),
                elbow_f=(0.0, -1.0, -0.4), foot_n=(-7.7, 3.0, 10.7), foot_f=(13.7, 3.0, -14.8),
                sword_ang=26.6, sword_out=-24.5, two_hand=1.0, grip_at=2.0, grip_f=-0.44, fist=1.2,
                cuff=0.42, glow=0.75, seam=1.0, jaw=14.0, turn=22.0, cloak_sway=-14.0, cloak_flare=1.2,
                cloak_hem=3.0, cloak_lift=0.5)
# contact[0], the hit: both feet planted wide, both arms reaching out toward the hero (the
# face well above and behind the fists), the strike's heavy smear of the whole sweep.
CLEAVE_HIT = _pose(pelvis=(-5.12, H - 6.0, 5.67), lean=10.0, side_lean=-12.0, twist=4.0,
                   head=(-8.0, -14.0, 6.0), hand_n=(22.1, 63.1, 0.0), elbow_n=(0.3, -1.0, 0.5),
                   elbow_f=(0.0, -1.0, -0.4), foot_n=(-7.7, 3.0, 10.7), foot_f=(13.7, 3.0, -14.8),
                   sword_ang=-30.7, sword_out=-11.5, two_hand=1.0, grip_at=2.0, grip_f=-0.44, fist=1.2,
                   cuff=0.42, glow=0.65, seam=1.0, jaw=12.0, turn=22.0, cloak_sway=-14.0,
                   cloak_flare=1.2, cloak_hem=3.0, cloak_lift=0.5, smear=1,
                   smear_from=(26.6, -24.5, 15.3, 60.0, 2.0))
# contact[1]: the blade drives on down through the hero, the body sinking low over the
# bent front leg (the tip kept off the floor).
CLEAVE_PRESS = _pose(pelvis=(-3.48, H - 10.2, 3.72), lean=10.0, side_lean=-12.0, twist=4.0,
                     head=(-2.0, -16.0, 8.0), hand_n=(24.0, 59.1, 0.0), elbow_n=(0.3, -1.0, 0.5),
                     elbow_f=(0.0, -1.0, -0.4), foot_n=(-7.7, 3.0, 10.7), foot_f=(13.7, 3.0, -14.8),
                     sword_ang=-37.8, sword_out=-5.8, two_hand=1.0, grip_at=2.0, grip_f=-0.44, fist=1.2,
                     cuff=0.42, glow=0.55, seam=1.0, jaw=8.0, turn=22.0, cloak_sway=-11.0,
                     cloak_flare=1.2, cloak_hem=3.0, cloak_lift=0.35)
# contact[2]: rising out of it, the blade held out toward the hero, angled, off the floor.
CLEAVE_REST = _pose(pelvis=(-2.95, H - 4.8, 3.09), lean=2.0, side_lean=-4.0, twist=4.0,
                    head=(-4.0, -12.0, 6.0), hand_n=(17.5, 60.7, 0.0), elbow_n=(0.3, -1.0, 0.5),
                    elbow_f=(0.0, -1.0, -0.4), foot_n=(-7.7, 3.0, 10.7), foot_f=(13.7, 3.0, -14.8),
                    sword_ang=-32.2, sword_out=-10.4, two_hand=1.0, grip_at=2.0, grip_f=-0.44, fist=1.2,
                    cuff=0.42, glow=0.5, seam=1.0, jaw=4.0, turn=22.0, cloak_sway=-7.0, cloak_flare=1.2,
                    cloak_hem=2.0, cloak_lift=0.2)
# recoil[0] (between hits): pulling the blade back in, still angled toward the hero.
CLEAVE_RECOIL = _pose(pelvis=(-0.63, H - 2.8, 1.49), lean=6.0, side_lean=-4.0, head=(4.0, -12.0, 3.0),
                      hand_n=(23.7, 61.1, 6.0), elbow_n=(0.2, -1.0, 0.6), elbow_f=(0.2, -1.0, -0.6),
                      foot_n=(-5.6, 3.0, 10.7), foot_f=(12.3, 3.0, -13.0), sword_ang=-43.2,
                      sword_out=-3.0, two_hand=1.0, grip_at=2.0, grip_f=-0.44, fist=1.2, cuff=0.42,
                      glow=0.45, seam=1.0, jaw=2.0, turn=25.0, cloak_sway=-3.0, cloak_flare=1.4,
                      cloak_hem=1.5)
# recoil[1]: the blade swung back under to the coil's place (down and back across the cloak,
# never point-down on the floor), the seam dying back toward the guard.
CLEAVE_SETTLE = _pose(pelvis=(-0.5, H - 1.6, 0.0), lean=4.0, head=(10.0, -12.0, 0.0),
                      hand_n=(6.9, 57.7, 8.0), elbow_n=(0.2, -1.0, 0.6), elbow_f=(0.2, -1.0, -0.6),
                      foot_n=(-3.9, 3.0, 10.5), foot_f=(10.1, 3.0, -8.8), sword_ang=-79.0,
                      sword_out=48.6, two_hand=1.0, grip_at=2.0, grip_f=-0.44, fist=1.2, cuff=0.42,
                      glow=0.6, seam=0.45, jaw=3.0, turn=26.0, cloak_sway=-2.5, cloak_flare=1.45)

# The walk home starts from this settled follow-through (the old sweep's).
FOLLOW_2 = _k("contact", pelvis=(10.0, H - 7.0, 0.0), lean=22.0, twist=-4.0, head=(2.0, -14.0, 0.0),
              hand_n=(25.0, 41.0, 2.0), hand_f=(22.0, 43.0, -2.0), sword_ang=-68.0, sword_out=20.0,
              bury=1.0, glow=0.45, jaw=4.0, cloak_sway=-6.0, cloak_lift=0.2, cloak_hem=2.0)

# Walking back home, the cleaver's point dragging: the front foot steps back, then the other.
RETURN_1 = _mix(FOLLOW_2, IDLE, 0.4, foot_n=(14.0, 8.0, 9.0), bury=1.0, glow=0.45)
RETURN_2 = _mix(FOLLOW_2, IDLE, 0.8, foot_f=(4.0, 6.0, -8.0), bury=1.0, glow=0.5)

# The slam: rubble flies up round the planted blade, then falls as he starts to rise.
SLAM_DUST = _k("slam", debris_fly=1.45, head=(-36.0, -16.0, 0.0), jaw=18.0, cloak_lift=0.6)
SLAM_RISE = _k("slam", debris_fly=0.55, pelvis=(-5.0, 25.0, 0.0), lean=34.0, head=(-22.0, -14.0, 0.0),
               jaw=10.0, cloak_lift=0.45, glow=0.75)
SLAM_UP = _k("slam", pelvis=(-3.0, 34.0, 0.0), lean=20.0, head=(-6.0, -14.0, 0.0),
             hand_n=(22.0, 38.0, 4.0), hand_f=(20.0, 40.0, 2.0), foot_n=(12.0, 3.0, 9.0),
             foot_f=(-14.0, 3.0, -7.0), knee_n=(1.0, 0.0, 0.2), knee_f=(1.0, 0.0, -0.2), toe_f=10.0,
             sword_ang=-86.0, bury=2.0, debris=0.25, glow=0.6, jaw=4.0, cloak_hem=1.0, cloak_lift=0.2,
             cloak_sway=-6.0, cloak_flare=1.45)

HURT_1 = _mix(HURT, IDLE, 0.5, crown_tilt=10.0)
# Stagger: reels a step further back, crown knocked askew, then leans on the cleaver to catch
# himself.
STAGGER_1 = _k("hurt", pelvis=(-10.0, H - 3.0, 0.0), lean=-24.0, head=(-30.0, 6.0, 14.0), crown_tilt=34.0,
               hand_f=(4.0, 64.0, 10.0), foot_n=(2.0, 8.0, 7.0), foot_f=(-16.0, 3.0, -6.0),
               sword_ang=-150.0, sword_out=30.0, jaw=24.0, glow=0.05, cloak_sway=12.0)
STAGGER_2 = _k("idle", pelvis=(-2.0, H - 6.0, 0.0), lean=26.0, head=(14.0, -12.0, 0.0),
               hand_n=(14.0, 40.0, 6.0), hand_f=(14.0, 42.0, 2.0), foot_n=(4.0, 3.0, 12.0),
               foot_f=(-6.0, 3.0, -8.0), sword_ang=-90.0, bury=2.0, crown_tilt=14.0, glow=0.3,
               jaw=10.0, cloak_flare=1.4)

# Death (rot): reels, drops to one knee on the planted cleaver, slumps over it as the crown
# falls, and comes to rest head bowed with the crown on the floor before him.
_KNEEL = dict(foot_n=(14.0, 3.0, 7.0), foot_f=(-20.0, 3.5, -6.0), knee_n=(1.0, 0.5, 0.2),
              knee_f=(0.4, -1.0, -0.1), toe_f=-170.0, sword_ang=-88.0, sword_out=0.0, bury=3.0,
              glow=0.0, eyes=0.0, turn=18.0, cloak_hem=0.5, cloak_flare=1.4, cloak_sway=-4.0)
DEATH_1 = _k("hurt", pelvis=(-6.0, H - 2.0, 0.0), lean=-14.0, head=(-34.0, 0.0, 14.0), crown_tilt=30.0,
             hand_f=(10.0, 58.0, 8.0), sword_ang=-120.0, sword_out=30.0, jaw=30.0, glow=0.05)
DEATH_2 = _k("slam", pelvis=(-4.0, 26.0, 0.0), lean=26.0, head=(-4.0, -12.0, 10.0), crown_tilt=-28.0,
             hand_n=(22.0, 40.0, 4.0), hand_f=(20.0, 42.0, 0.0), two_hand=0.6, jaw=20.0, debris=0.0,
             **_KNEEL)
DEATH_3 = _k("slam", pelvis=(-4.0, 24.0, 0.0), lean=36.0, head=(-18.0, -14.0, 14.0),
             hand_n=(22.0, 34.0, 4.0), hand_f=(14.0, 20.0, -8.0), two_hand=0.0, claw_f=0.4, jaw=24.0,
             debris=0.0, crown_at=(34.0, 27.0, -2.0), crown_rot=(40.0, 0.0, 80.0), **_KNEEL)
DEATH_4 = _k("slam", pelvis=(-4.0, 22.0, 0.0), lean=44.0, head=(-18.0, -14.0, 20.0),
             hand_n=(22.0, 30.0, 4.0), hand_f=(16.0, 8.0, -8.0), two_hand=0.0, claw_f=0.3, jaw=30.0,
             debris=0.0, crown_at=(39.0, 7.5, -7.0), crown_rot=(15.0, 30.0, 75.0), **_KNEEL)


# Rage (phase two, Tier 2): gathers himself over the pommel as the core flares, rips the cleaver
# up, throws his arms wide and roars at the sky with the cloak billowing, then plants it again.
RAGE_1 = _k("idle", pelvis=(0.0, H - 2.5, 0.0), lean=14.0, head=(8.0, -12.0, 0.0), glow=0.95,
            jaw=6.0, cloak_flare=1.4, cloak_sway=-1.0)
RAGE_2 = _k("idle", pelvis=(-1.0, H - 0.8, 0.0), lean=0.0, head=(-6.0, -10.0, 0.0),
            hand_n=(11.0, 61.0, 8.0), hand_f=(11.0, 63.0, 4.0), sword_ang=-96.0, sword_out=4.0,
            bury=0.0, glow=1.0, jaw=16.0, cloak_flare=1.5, cloak_lift=0.3, turn=26.0)
RAGE_3 = _k("idle", pelvis=(-2.0, H - 1.5, 0.0), lean=-12.0, head=(-36.0, -6.0, 0.0),
            hand_n=(-18.0, 47.0, 20.0), elbow_n=(-0.4, 0.2, 1.0), hand_f=(16.0, 84.0, -8.0),
            elbow_f=(0.6, -0.6, -0.6), two_hand=0.0, claw_f=1.0, sword_ang=-150.0, sword_out=20.0,
            bury=0.0, glow=1.0, jaw=34.0, turn=30.0, cloak_flare=1.75, cloak_lift=1.0,
            cloak_open=30.0, cloak_sway=2.0)
RAGE_4 = dict(RAGE_3, head=(-40.0, -2.0, 4.0), jaw=38.0, hand_f=(17.0, 86.0, -7.0),
              cloak_lift=0.85, cloak_sway=3.5, sword_ang=-146.0)
RAGE_5 = _k("idle", glow=1.0, jaw=8.0, cloak_lift=0.35, cloak_flare=1.7, head=(4.0, -12.0, 0.0))


def _gait(near_x: float, far_x: float, near_up: float, far_up: float, bob: float, swing: float,
          run: bool = False, **kw: Any) -> dict[str, Any]:
    """A walking or running frame: each foot along the ground (and lifted), the body's bob and
    the free claw swinging against the legs. Walking he drags the cleaver's point behind him;
    running he carries it low and trailing."""
    p = _k("idle", pelvis=(2.0, H - (5.0 if run else 2.0) + bob, 0.0), lean=18.0 if run else 6.0,
           twist=-6.0 * swing, head=(-10.0 if run else 4.0, -12.0, 0.0), turn=22.0,
           foot_n=(near_x, 3.0 + near_up, 9.0), foot_f=(far_x, 3.0 + far_up, -7.0),
           knee_n=(1.0, 0.3 if near_up > 1 else 0.0, 0.2), knee_f=(1.0, 0.3 if far_up > 1 else 0.0, -0.2),
           toe_n=16.0 if near_up > 1 else 0.0, toe_f=16.0 if far_up > 1 else 0.0,
           hand_n=(-2.0 + 3.0 * swing, 40.0, 15.0), elbow_n=(-0.4, -0.4, 1.0),
           hand_f=(14.0 - 10.0 * swing + (12.0 if run else 0.0), 46.0 + (4.0 if run else 0.0), -2.0),
           elbow_f=(-0.4, -1.0, -0.4), two_hand=0.0, claw_f=0.8 if run else 0.5,
           sword_ang=-168.0 if run else -150.0, sword_out=8.0, bury=1.0,
           glow=0.6 if run else 0.5, jaw=14.0 if run else 0.0,
           cloak_sway=(-14.0 if run else -5.0) + 2.0 * bob, cloak_flare=1.15 if run else 1.35,
           cloak_lift=0.45 if run else 0.1, cloak_open=25.0 if run else 0.0, cloak_hem=3.0 if run else 1.0)
    p.update(kw)
    return p


# Two steps per cycle; a foot is planted on cells 0 and 2 (the footstep moments).
WALK = [_gait(14.0, -12.0, 0.0, 0.0, -0.8, -1.0), _gait(2.0, -2.0, 0.0, 9.0, 0.6, 0.0),
        _gait(-12.0, 14.0, 0.0, 0.0, -0.8, 1.0), _gait(-2.0, 2.0, 9.0, 0.0, 0.6, 0.0)]
CHASE = [_gait(22.0, -18.0, 0.0, 2.0, -1.5, -1.0, run=True), _gait(2.0, -6.0, 0.0, 14.0, 1.0, 0.0, run=True),
         _gait(-18.0, 22.0, 2.0, 0.0, -1.5, 1.0, run=True), _gait(-6.0, 2.0, 14.0, 0.0, 1.0, 0.0, run=True)]

# Clip name -> cells in play order (int = a row-0 key, dict = a pose). The game sets the timing.
CLIPS: dict[str, list[Any]] = {
    "idle": [K["idle"], _mix(IDLE, BREATH, 0.5), BREATH, _mix(IDLE, BREATH, 0.5)],
    # The sword swing, every hit of a string (odd hits ask for lunge_b / contact_b and fall back
    # to these: the King has one swing).
    "windup": [COIL_1, COIL_2, CLEAVE_UP],
    "windup_hold": [CLEAVE_UP, CLEAVE_SHIVER],
    "lunge": [SWING_1, SWING_2, SWING_3],
    "contact": [CLEAVE_HIT, CLEAVE_PRESS, CLEAVE_REST],
    "recoil": [CLEAVE_RECOIL, CLEAVE_SETTLE],
    "return": [RETURN_1, RETURN_2, K["idle"]],
    "slam": [K["slam"], SLAM_DUST, SLAM_RISE],
    "slam_recover": [SLAM_UP, K["idle"]],
    "hurt": [K["hurt"], HURT_1, K["idle"]],
    "stagger": [K["hurt"], STAGGER_1, STAGGER_2, K["idle"]],
    "death": [DEATH_1, DEATH_2, DEATH_3, DEATH_4],
    "walk": WALK,
    "chase": CHASE,
    "rage": [RAGE_1, RAGE_2, RAGE_3, RAGE_4, RAGE_5],
}


def _cam_state() -> tuple[float, float, float]:
    camera()
    return (_CAM[0].cx, _CAM[0].cy, float(_CAM[1]))  # type: ignore[union-attr]


def _init_worker(state: tuple[float, float, float]) -> None:
    """A render worker starts with the parent's fitted sheet camera (fitting it costs a render)."""
    _CAM[:] = [Camera(S, S, scale=SHEET_SCALE, face="left", cx=state[0], cy=state[1]), state[2]]


def render_cells(poses: list[dict[str, Any]]) -> list[np.ndarray]:
    """Renders many poses (about 5 s each for the king), in worker processes when it can."""
    if len(poses) < 4:
        return [render_pose(p) for p in poses]
    import os
    try:
        from concurrent.futures import ProcessPoolExecutor
        workers = max(1, min(8, (os.cpu_count() or 2) - 2, len(poses)))
        with ProcessPoolExecutor(max_workers=workers, initializer=_init_worker,
                                 initargs=(_cam_state(),)) as ex:
            return list(ex.map(render_pose, poses))
    except (OSError, RuntimeError, ImportError):
        return [render_pose(p) for p in poses]


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
        f = render_pose(POSES[name])
        for msg in check_margins(f, name):
            print("  warning:", msg)
        frames.append(f)
    ctx.save_fighter("sprites/enemies/%s.png" % ID, frames, _clip_cells(), (S, S), S, ID,
                     preview_ms={"idle": ENEMY_PREVIEW_MS["idle"] * IDLE_CYCLE_PERCENT // 100})
    sheet = hstack(frames)
    por = render_pose(PORTRAIT_POSE, portrait_camera(), portrait=True)
    ctx.save("sprites/portraits/%s.png" % ID, por)
    _review_pictures(ctx, sheet, por)
