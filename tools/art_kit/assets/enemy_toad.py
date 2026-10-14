"""Mire Toad: a toad grown as big as a cart in the bog, warty and slick, its back a garden of moss
and rot (phase 12).

Silhouette: a wide squat dome of a body, a broad flat head with a huge lipped mouth, two bulging
eyes standing up on top, short thick front legs planted wide, big folded hind legs at the back.
Colour areas: mottled bog-olive skin with darker warts, a pale sallow throat sac that swells in
the tell and before a spit, moss patches on the back, a purple rot lesion with a glowing rot-green
core in the flank, and amber eyes that flare. It jumps: its ground attacks are hops that shake
the floor (DESIGN.md 2.15).

Built straight from a pose dict like enemy_hyena (no humanoid rig). Model units are pixels before
SIZE; x forward (it faces right in the model, the camera mirrors it), y up, z toward the viewer.

Pose keys:
    body     (x, y) of the body's centre
    pitch    body tilt, degrees (+ = front up)
    squash   0..1 how flat it presses (a crouch or a belly flop)
    mouth    jaw opening, degrees
    throat   0..1 how far the throat sac swells
    fn/ff    front foot (near/far) position; hn/hf hind foot position (x, y, z)
    fold     0..1 how folded the hind legs are (1 = sitting, 0 = kicked straight back)
    glow     0..1 eye brightness (1 = the tell)
    roll     degrees it rolls onto its back (death)
    dead     1 = the rot core has gone dark
"""
from __future__ import annotations

import math
from typing import Any

import numpy as np

from kit.beast import build_enemy, cone, decal, finish, framed, lift_off_last_row, mix, pose_with, unit, v
from kit.palette import M, Material
from kit.render import Camera, Frame, render
from kit.rig import two_bone
from kit.sdf import Ellipsoid, Moved, Node, SmoothUnion, Sphere, Union, rot
from kit.specs import ENEMY_FRAME, ENEMY_POSES, PORTRAIT

ID = "mire_toad"
S = ENEMY_FRAME[ID]
SIZE = 1.65
CAM_CX = 1.5
CAM_CY = -3.5
# Mirrors idle_cycle_percent in data/enemies/mire_toad.tres (slow, heavy breathing).
IDLE_CYCLE_PERCENT = 150

# --- Materials -----------------------------------------------------------------------------------
SKIN = Material.make("toad_skin", "#5e6438", wrap=0.4, ao=0.6, dither=True)
WART = Material.make("toad_wart", "#454a2a", wrap=0.35, ao=0.5)
BELLY = Material.make("toad_belly", "#a69a62", wrap=0.45, ao=0.5)
THROAT = Material.make("toad_throat", "#bfae72", wrap=0.5, ao=0.4)
LIP = Material.make("toad_lip", "#4a4a2c", wrap=0.35, ao=0.5)
MAW = Material.make("toad_maw", "#6a2638", below=1, above=1, wrap=0.2, ao=0.1)
TONGUE = Material.make("toad_tongue", "#a8485a", wrap=0.3, ao=0.2)
MOSS = M["moss"]
EYEBALL = Material.make("toad_eyeball", "#6a5a2c", wrap=0.3, spec=0.7, spec_power=12.0)
EYE = M["glow_amber"]
LESION = M["rot_purple"]
CORE = Material.make("toad_rot_core", "#7aa344", below=2, above=1, emissive=True, glow_index=2)
CORE_DEAD = Material.make("toad_rot_dead", "#3f4a30", below=1, above=1, wrap=0.3)

BODY_R = (14.0, 10.0, 12.0)
FRONT_UPPER, FRONT_LOWER = 6.0, 6.0
HIND_THIGH, HIND_SHIN = 9.0, 9.0
FOOT_Z = 9.0


def _pose(**kw: Any) -> dict[str, Any]:
    p: dict[str, Any] = dict(
        body=(-2.0, 13.0), pitch=14.0, squash=0.0, mouth=0.0, throat=0.2,
        fn=(10.0, 1.4, FOOT_Z), ff=(10.0, 1.4, -FOOT_Z), hn=(-10.0, 1.4, FOOT_Z + 2.0),
        hf=(-10.0, 1.4, -FOOT_Z - 2.0), fold=1.0, glow=0.0, roll=0.0, dead=0.0,
    )
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    # Sitting squat, front up, the throat sac breathing.
    "idle": _pose(),
    # The tell: pressed flat and low, gathering for a jump, throat swollen, eyes flaring amber.
    "windup": _pose(body=(-4.0, 10.0), pitch=6.0, squash=0.5, throat=1.0, glow=1.0,
                    fn=(9.0, 1.4, FOOT_Z + 1.0), ff=(9.0, 1.4, -FOOT_Z - 1.0)),
    # In the air, stretched toward the target: hind legs kicked straight back, front legs reaching.
    "lunge": _pose(body=(4.0, 22.0), pitch=-6.0, mouth=14.0, throat=0.3, glow=0.6, fold=0.0,
                   fn=(20.0, 12.0, FOOT_Z), ff=(18.0, 13.0, -FOOT_Z), hn=(-24.0, 14.0, FOOT_Z),
                   hf=(-22.0, 16.0, -FOOT_Z)),
    # Landing on the target, front feet slapped down ahead, mouth wide.
    "contact": _pose(body=(3.0, 13.5), pitch=-6.0, squash=0.3, mouth=34.0, throat=0.0, glow=0.6,
                     fn=(18.0, 1.4, FOOT_Z + 1.0), ff=(16.0, 1.4, -FOOT_Z - 1.0), fold=0.6),
    # Recoil: rocked back on its haunches, front feet off the ground, mouth agape.
    "hurt": _pose(body=(-5.0, 15.0), pitch=32.0, mouth=22.0, throat=0.0,
                  fn=(6.0, 7.0, FOOT_Z), ff=(5.0, 5.0, -FOOT_Z)),
    # The belly flop: smacked flat on the floor, legs splayed wide.
    "slam": _pose(body=(0.0, 8.5), pitch=0.0, squash=1.0, mouth=12.0, throat=0.6, glow=0.6,
                  fn=(14.0, 1.4, FOOT_Z + 4.0), ff=(13.0, 1.4, -FOOT_Z - 4.0), hn=(-16.0, 1.4, FOOT_Z + 5.0),
                  hf=(-15.0, 1.4, -FOOT_Z - 5.0), fold=0.4),
}
# A spit (clip `shoot`): head thrown up, mouth wide, throat sac full.
SHOOT = _pose(body=(-3.0, 14.0), pitch=26.0, mouth=44.0, throat=1.0, glow=0.8)


# --- Model ---------------------------------------------------------------------------------------

def _frame(p: dict[str, Any]) -> tuple[np.ndarray, np.ndarray, np.ndarray, float]:
    """Body centre, forward and up directions, and the squash factor."""
    bx, by = p["body"]
    a = math.radians(float(p["pitch"]))
    fwd = v((math.cos(a), math.sin(a), 0.0))
    up = v((-math.sin(a), math.cos(a), 0.0))
    return v((bx, by, 0.0)), fwd, up, float(p["squash"])


def _R(fwd: np.ndarray) -> np.ndarray:
    return rot(0.0, 0.0, math.degrees(math.atan2(fwd[1], fwd[0])))


# Warts on the back: (forward, up, side) on the body's surface directions, radius.
WARTS = ((-0.2, 0.9, 0.4, 1.6), (0.3, 0.8, 0.55, 1.3), (-0.6, 0.6, 0.6, 1.5), (0.1, 0.6, 0.8, 1.2),
         (-0.4, 0.3, 0.9, 1.4), (0.5, 0.4, 0.75, 1.1), (-0.8, 0.2, 0.55, 1.2), (0.0, 0.95, -0.2, 1.4),
         (-0.5, 0.8, -0.3, 1.3))
MOSS_PATCHES = ((-0.1, 1.0, 0.0, (5.0, 2.0, 4.0)), (-0.6, 0.75, 0.25, (3.5, 1.6, 3.0)))


def _on_body(c: np.ndarray, fwd: np.ndarray, up: np.ndarray, radii: np.ndarray,
             f: float, u: float, s: float) -> np.ndarray:
    d = unit(fwd * f + up * u + v((0.0, 0.0, s)))
    k = 1.0 / math.sqrt((d @ fwd / radii[0]) ** 2 + (d @ up / radii[1]) ** 2 + (d[2] / radii[2]) ** 2)
    return c + d * k


def model(p: dict[str, Any]) -> Node:
    c, fwd, up, sq = _frame(p)
    radii = v(BODY_R) * v((1.0 + 0.15 * sq, 1.0 - 0.35 * sq, 1.0 + 0.15 * sq))
    R = _R(fwd)
    body = Ellipsoid(SKIN, c, radii, R=R, group="body")
    belly = Ellipsoid(BELLY, c - up * radii[1] * 0.45 + fwd * 2.0, radii * v((0.8, 0.6, 0.85)), R=R, group="body")
    head_c = c + fwd * radii[0] * 0.75 + up * radii[1] * 0.25
    head = Ellipsoid(SKIN, head_c, (8.5, 5.6 * (1.0 - 0.25 * sq), 9.0), R=R, group="body")
    parts: list[Node] = [SmoothUnion(body, head, k=3.5), belly]
    # Lower jaw: hinged at the back of the head, swinging down by `mouth`.
    m = math.radians(float(p["mouth"]))
    jdir = unit(fwd * math.cos(m) - up * math.sin(m))
    hinge = head_c - fwd * 3.0 - up * 2.2
    jaw_c = hinge + jdir * 5.5
    parts.append(Ellipsoid(LIP, jaw_c, (6.5, 2.2, 8.4), R=_R(jdir), group="jaw"))
    throat = float(p["throat"])
    parts.append(Ellipsoid(THROAT, jaw_c - up * (1.5 + 2.0 * throat) - jdir * 1.5,
                           (5.0 + 2.0 * throat, 2.2 + 3.2 * throat, 6.0 + 1.5 * throat), R=_R(jdir), group="throat"))
    if float(p["mouth"]) > 10.0:
        parts.append(Ellipsoid(MAW, (head_c + jaw_c) / 2 + fwd * 1.0 - up * 0.8, (5.0, 1.6 + 1.5 * math.sin(m), 7.0),
                               R=R, group="maw"))
        parts.append(Ellipsoid(TONGUE, jaw_c + up * 1.2 + fwd * 0.5, (3.6, 1.0, 3.0), R=_R(jdir), group="maw"))
    # Bulging eyes on top of the head.
    for z in (4.6, -4.6):
        e = head_c + up * 5.0 - fwd * 1.0 + v((0.0, 0.0, z))
        parts.append(Sphere(EYEBALL, e, 2.9, group="eyeball"))
    # Warts and moss on the back, the rot lesion in the flank.
    for f, u, s, r in WARTS:
        parts.append(Sphere(WART, _on_body(c, fwd, up, radii, f, u, s), r, group="body"))
    for f, u, s, rr in MOSS_PATCHES:
        parts.append(Ellipsoid(MOSS, _on_body(c, fwd, up, radii, f, u, s), rr, R=R, group="moss"))
    les = _on_body(c, fwd, up, radii, -0.3, -0.05, 1.0)
    parts.append(Ellipsoid(LESION, les, (3.6, 3.0, 1.4), group="body"))
    parts.append(Ellipsoid(CORE_DEAD if p.get("dead", 0.0) >= 0.5 else CORE, les + v((0.0, 0.0, 0.9)),
                           (2.0, 1.7, 1.0), group="core"))
    parts += _legs(p, c, fwd, up, radii)
    node: Node = Union(*parts)
    roll = float(p.get("roll", 0.0))
    if roll:
        node = Moved(node, (0.0, 0.0, 0.0), rot(roll, 0.0, 0.0))
    return Scaled(node, SIZE)


def _foot(p: dict[str, Any], key: str) -> np.ndarray:
    """A foot's spot, lifted a little when it is splayed toward the viewer: in the 3/4 view a near
    foot shows lower on screen, and it must stay on the second-to-last row."""
    f = v(p[key])
    return v((f[0], max(f[1], 1.4 + NEAR_LIFT * max(0.0, f[2] - FOOT_Z - 2.5)), f[2]))


NEAR_LIFT = 0.3


def _legs(p: dict[str, Any], c: np.ndarray, fwd: np.ndarray, up: np.ndarray, radii: np.ndarray) -> list[Node]:
    out: list[Node] = []
    for key, z in (("fn", 1.0), ("ff", -1.0)):
        top = c + fwd * radii[0] * 0.45 - up * radii[1] * 0.3 + v((0.0, 0.0, z * radii[2] * 0.6))
        foot = _foot(p, key)
        elbow, end = two_bone(top, foot + v((0.0, 1.5, 0.0)), FRONT_UPPER, FRONT_LOWER, v((-0.6, 0.0, z)))
        grp = "leg_n" if z > 0 else "leg_f"
        out += [cone(SKIN, top, elbow, 3.2, 2.4, group=grp), cone(SKIN, elbow, end, 2.4, 1.8, group=grp),
                Ellipsoid(SKIN, foot + v((1.6, 0.4, 0.0)), (3.2, 1.2, 2.6), group=grp)]
    fold = float(p["fold"])
    for key, z in (("hn", 1.0), ("hf", -1.0)):
        hip = c - fwd * radii[0] * 0.5 - up * radii[1] * 0.1 + v((0.0, 0.0, z * radii[2] * 0.7))
        foot = _foot(p, key)
        pole = unit(fwd * (0.4 + 0.6 * fold) + up * (1.0 - fold))
        knee, ankle = two_bone(hip, foot + v((2.5, 2.0, 0.0)), HIND_THIGH, HIND_SHIN, pole)
        grp = "leg_n" if z > 0 else "leg_f"
        out += [cone(SKIN, hip, knee, 5.4, 3.2, group=grp), cone(SKIN, knee, ankle, 3.0, 2.0, group=grp),
                Ellipsoid(SKIN, foot + v((1.0, 0.4, 0.0)), (4.4, 1.2, 2.8), group=grp)]
    return out


class Scaled(Node):
    """Scales a whole model uniformly about the ground origin."""

    def __init__(self, child: Node, k: float) -> None:
        self.child = child
        self.k = k

    def eval(self, P):
        d, part = self.child.eval(P / self.k)
        return d * self.k, part

    def leaves(self):
        return self.child.leaves()


# --- Rendering -----------------------------------------------------------------------------------

def camera() -> Camera:
    return Camera(S, S, face="left", cx=CAM_CX, cy=CAM_CY)


def _eyes(fr: Frame, cam: Camera, p: dict[str, Any], big: bool = False) -> None:
    c, fwd, up, sq = _frame(p)
    radii = v(BODY_R) * v((1.0 + 0.15 * sq, 1.0 - 0.35 * sq, 1.0 + 0.15 * sq))
    head_c = c + fwd * radii[0] * 0.75 + up * radii[1] * 0.25
    hot = float(p.get("glow", 0.0)) >= 0.9
    rows = (["aa", "ab"] if big else ["ab"]) if not hot else (["aa", "aa"] if big else ["aa"])
    legend = {"a": (EYE, 3 if hot else 2), "b": (EYE, 1)}
    for z in (4.6, -4.6):
        pt = (head_c + up * 5.6 + fwd * 1.0 + v((0.0, 0.0, z * 1.25))) * SIZE
        decal(fr, cam, pt, rows, legend, ("eyeball",), tol=3.5, group="eye")


def render_frame(p: dict[str, Any], cam: Camera | None = None) -> Frame:
    cam = cam or camera()
    fr = render(model(p), cam)
    _eyes(fr, cam, p)
    lift_off_last_row(fr)
    return fr


def finish_frame(fr: Frame) -> np.ndarray:
    return finish(fr, keep=("eye", "core"))


def render_cell(p: dict[str, Any]) -> np.ndarray:
    return finish_frame(render_frame(p))


PORTRAIT_SCALE = 0.85
PORTRAIT_AT = (21.0, 25.0)
PORTRAIT_POSE = pose_with(POSES["idle"], mouth=16.0, throat=0.6, glow=0.6)


def render_portrait(p: dict[str, Any]) -> np.ndarray:
    c, fwd, up, _ = _frame(p)
    head_c = c + fwd * BODY_R[0] * 0.75 + up * BODY_R[1] * 0.25
    cam = framed(PORTRAIT, PORTRAIT_SCALE, (head_c + up * 2.0) * SIZE, PORTRAIT_AT)
    fr = render(model(p), cam)
    _eyes(fr, cam, p, big=True)
    return finish_frame(fr)


# --- Clips ---------------------------------------------------------------------------------------
K = {n: i for i, n in enumerate(ENEMY_POSES)}
IDLE, WINDUP, LUNGE, CONTACT, HURT, SLAM = (POSES[n] for n in ENEMY_POSES)

BREATH = pose_with(IDLE, throat=0.75, body=(-2.0, 12.6))
COIL_1 = mix(IDLE, WINDUP, 0.45, glow=0.5)
COIL_2 = mix(IDLE, WINDUP, 0.8, glow=1.0)
SHIVER = pose_with(WINDUP, throat=0.7, body=(-4.0, 10.4))
# The leap: legs push off, then it flies stretched.
LUNGE_1 = mix(WINDUP, LUNGE, 0.3, hn=(-14.0, 1.4, FOOT_Z + 2.0), hf=(-14.0, 1.4, -FOOT_Z - 2.0), fold=0.3)
LUNGE_2 = mix(WINDUP, LUNGE, 0.7)
LAND_1 = pose_with(CONTACT, mouth=30.0, squash=0.45, body=(3.0, 11.0))
LAND_2 = mix(CONTACT, IDLE, 0.45, mouth=12.0)
RECOIL_1 = mix(CONTACT, IDLE, 0.65)
RETURN_1 = mix(LUNGE, IDLE, 0.6, body=(0.0, 18.0))
RETURN_2 = mix(CONTACT, IDLE, 0.8, squash=0.2)
FLOP_2 = pose_with(SLAM, squash=0.9, body=(0.0, 9.0), mouth=20.0)
FLOP_3 = mix(SLAM, IDLE, 0.4)
FLOP_UP = mix(SLAM, IDLE, 0.75)
HURT_1 = mix(HURT, IDLE, 0.5)
STAGGER_1 = pose_with(HURT, body=(-7.0, 16.0), pitch=40.0, mouth=30.0)
STAGGER_2 = pose_with(IDLE, body=(-2.0, 10.5), pitch=2.0, squash=0.4, mouth=10.0)
# Death: a croak, it sags flat as the core goes dark, then its legs give out and splay.
DEATH_1 = pose_with(HURT, mouth=40.0, throat=1.0)
DEATH_2 = pose_with(SLAM, squash=0.7, mouth=24.0, throat=0.0, glow=0.0, dead=1.0)
DEATH_3 = pose_with(DEATH_2, squash=1.0, body=(0.0, 8.0), mouth=16.0)
DEATH_4 = pose_with(DEATH_3, body=(0.0, 7.0), pitch=-6.0, mouth=8.0,
                    fn=(16.0, 1.4, FOOT_Z + 6.0), ff=(15.0, 1.4, -FOOT_Z - 6.0), hn=(-18.0, 1.4, FOOT_Z + 7.0),
                    hf=(-17.0, 1.4, -FOOT_Z - 7.0), fold=0.2)
SHOOT_2 = pose_with(SHOOT, mouth=30.0, throat=0.3, pitch=18.0)


def _hop(t: float) -> dict[str, Any]:
    """A frame of the zone hop: crouch (0), push (0.25), air (0.5), land (0.75)."""
    if t < 0.125:
        return pose_with(IDLE, squash=0.4, body=(-3.0, 11.0), throat=0.4)
    if t < 0.375:
        return mix(IDLE, LUNGE, 0.45, mouth=0.0, glow=0.0)
    if t < 0.625:
        return pose_with(mix(IDLE, LUNGE, 0.8), body=(1.0, 20.0), mouth=0.0, glow=0.0)
    return pose_with(IDLE, squash=0.3, body=(-1.0, 11.5), throat=0.3)


# Two short hops per cycle: down on cells 0 and 2 (the footstep moments), up in between.
WALK = [_hop(0.0), _hop(0.5), _hop(0.75), _hop(0.25)]
CHASE = [_hop(0.0), pose_with(_hop(0.5), glow=0.6, mouth=14.0), _hop(0.75), pose_with(_hop(0.25), glow=0.6, mouth=10.0)]

CLIPS: dict[str, list[Any]] = {
    "idle": [K["idle"], mix(IDLE, BREATH, 0.5), BREATH, mix(IDLE, BREATH, 0.5)],
    "windup": [COIL_1, COIL_2, K["windup"]],
    "windup_hold": [K["windup"], SHIVER],
    "lunge": [LUNGE_1, LUNGE_2, K["lunge"]],
    "contact": [K["contact"], LAND_1, LAND_2],
    "recoil": [RECOIL_1, K["idle"]],
    "return": [RETURN_1, RETURN_2, K["idle"]],
    "slam": [K["slam"], FLOP_2, FLOP_3],
    "slam_recover": [FLOP_UP, K["idle"]],
    "hurt": [K["hurt"], HURT_1, K["idle"]],
    "stagger": [K["hurt"], STAGGER_1, STAGGER_2, K["idle"]],
    "death": [DEATH_1, DEATH_2, DEATH_3, DEATH_4],
    "walk": WALK,
    "chase": CHASE,
    "windup_shoot": [COIL_1, pose_with(SHOOT, mouth=10.0, throat=1.0), pose_with(SHOOT, mouth=10.0, throat=1.0)],
    "shoot": [SHOOT, SHOOT_2, K["idle"]],
}


def build(ctx) -> None:
    build_enemy(ctx, ID, S, POSES, CLIPS, render_frame, finish_frame, render_cell,
                render_portrait(PORTRAIT_POSE), IDLE_CYCLE_PERCENT)
