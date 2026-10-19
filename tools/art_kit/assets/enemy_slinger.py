"""Ember Slinger: a gaunt ash ghoul of the burnt ruins that never comes close: it hurls burning
pitch and cinders from a clay firepot at its hip (phase 19, card #256).

Silhouette: a thin, stooped figure in a charred hooded rag, long bony arms, a round clay pot slung
at the hip with embers glowing in its mouth, a burning glob held in the throwing hand. Colour
areas: ash-grey skin cracked with ember light, near-black charred rags, a warm clay pot, ember
orange glow (the hand, the pot, the eyes, the cracks).

Built straight from a pose dict (kit.monster, like the phase 12 monsters). Model units are pixels
before SIZE; x forward (it faces right in the model, the camera mirrors it), y up, z toward the
viewer.

Pose keys:
    hip       (x, y) of the hips
    lean      torso lean, degrees (+ = forward)
    head      head tilt on the neck, degrees (+ = chin up)
    an, bn    near (throwing) arm: shoulder angle (0 forward, 90 up, -90 down) and elbow bend
    af, bf    far arm, the same
    fn, ff    near and far foot (x, y, z)
    glow      0..1 the ember in the hand (1 = the tell, about to throw)
    eyes      1 = open, 0 = shut
    roll      degrees it topples sideways (death)
    dead      1 = the embers have gone out
"""
from __future__ import annotations

import math
from typing import Any

import numpy as np

from kit.beast import build_enemy, cone, decal, dir2, finish, framed, lift_off_last_row, pose_with, unit, v
from kit.monster import Scaled, gait, limb, standard_clips
from kit.palette import M, Material
from kit.render import Camera, Frame, render
from kit.rig import two_bone
from kit.sdf import Ellipsoid, Moved, Node, SmoothUnion, Sphere, Union, rot
from kit.specs import ENEMY_FRAME, PORTRAIT

ID = "ember_slinger"
S = ENEMY_FRAME[ID]
SIZE = 1.3
CAM_CX = 1.0
CAM_CY = -0.5
IDLE_CYCLE_PERCENT = 100

ASH = Material.make("slinger_ash", "#8d857c", wrap=0.35, ao=0.5)
RAG = Material.make("slinger_rag", "#4a3f3d", wrap=0.3, ao=0.5)
CLAY = Material.make("slinger_clay", "#7d5a43", wrap=0.35, ao=0.5)
EMBER = M["glow_ember"]
DARK_EMBER = Material.make("slinger_ember_dead", "#4a3a34", below=1, above=1, wrap=0.3)

SPINE, NECK = 13.0, 2.5
ARM1, ARM2 = 8.5, 8.5
THIGH, SHIN = 9.0, 9.0
HIP_Z, SHOULDER_Z = 2.6, 4.0


def _pose(**kw: Any) -> dict[str, Any]:
    p: dict[str, Any] = dict(
        hip=(0.0, 17.0), lean=12.0, head=-5.0, an=-70.0, bn=25.0, af=-100.0, bf=10.0,
        fn=(3.0, 0.8, HIP_Z), ff=(-3.0, 0.8, -HIP_Z), glow=0.4, eyes=1.0, roll=0.0, dead=0.0,
    )
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    # Stooped, the burning glob held low in the throwing hand, the other hand on the pot.
    "idle": _pose(),
    # The tell: leaning back, the throwing arm cocked up behind the head, the glob blazing.
    "windup": _pose(hip=(-1.0, 16.0), lean=-8.0, head=10.0, an=125.0, bn=35.0, af=10.0, bf=10.0,
                    fn=(5.0, 0.8, HIP_Z), ff=(-5.0, 0.8, -HIP_Z), glow=1.0),
    # Stepping into the throw, the arm coming over.
    "lunge": _pose(hip=(2.0, 16.0), lean=20.0, head=0.0, an=70.0, bn=-10.0, af=-130.0, bf=10.0,
                   fn=(9.0, 0.8, HIP_Z), ff=(-4.0, 0.8, -HIP_Z), glow=0.8),
    # The follow-through: bent over, the arm whipped down and forward, the hand empty.
    "contact": _pose(hip=(2.0, 15.0), lean=30.0, head=-10.0, an=-30.0, bn=0.0, af=-140.0, bf=10.0,
                     fn=(9.0, 0.8, HIP_Z), ff=(-5.0, 0.8, -HIP_Z), glow=0.0),
    # Struck: thrown back, arms flung, eyes shut.
    "hurt": _pose(hip=(-2.0, 16.5), lean=-18.0, head=20.0, an=-120.0, bn=30.0, af=-130.0, bf=20.0,
                  fn=(2.0, 0.8, HIP_Z), ff=(-6.0, 0.8, -HIP_Z), eyes=0.0, glow=0.2),
    # The release: the arm straight out where the glob left it.
    "slam": _pose(hip=(1.5, 16.0), lean=18.0, head=4.0, an=20.0, bn=-5.0, af=-130.0, bf=10.0,
                  fn=(8.0, 0.8, HIP_Z), ff=(-5.0, 0.8, -HIP_Z), glow=0.2),
}


def skeleton(p: dict[str, Any]) -> dict[str, Any]:
    hx, hy = p["hip"]
    hip = v((hx, hy, 0.0))
    sp = dir2(90.0 - float(p["lean"]))
    chest = hip + sp * SPINE
    hd = dir2(90.0 - float(p["lean"]) * 1.3 + float(p["head"]))
    head = chest + sp * NECK + hd * 3.6
    fwd = unit(np.cross(sp, v((0.0, 0.0, 1.0))))
    return {"hip": hip, "sp": sp, "chest": chest, "head": head, "hd": hd, "fwd": fwd}


def _arm(sk: dict[str, Any], a: float, b: float, z: float, mat_hand: Material | None, glow: float,
         group: str) -> list[Node]:
    sh = sk["chest"] - sk["sp"] * 1.5 + v((0.0, 0.0, z))
    elbow, hand = limb(sh, a, b, ARM1, ARM2)
    parts: list[Node] = [cone(RAG, sh, elbow, 2.2, 1.6, group=group), cone(ASH, elbow, hand, 1.5, 1.1, group=group),
                         Sphere(ASH, hand, 1.5, group=group)]
    if mat_hand is not None:
        parts.append(Sphere(mat_hand, hand + v((0.6, 0.6, 0.6)), 1.4 + 0.9 * glow, group="ember"))
    return parts


def _leg(sk: dict[str, Any], foot: Any, z: float) -> list[Node]:
    top = sk["hip"] + v((0.0, -1.0, z))
    knee, end = two_bone(top, v(foot) + v((0.0, 1.0, 0.0)), THIGH, SHIN, v((1.0, 0.0, 0.0)))
    grp = "leg_n" if z > 0 else "leg_f"
    return [cone(ASH, top, knee, 2.0, 1.5, group=grp), cone(ASH, knee, end, 1.5, 1.2, group=grp),
            Ellipsoid(ASH, end + v((1.2, -0.4, 0.0)), (2.4, 1.1, 1.4), group=grp)]


def model(p: dict[str, Any]) -> Node:
    sk = skeleton(p)
    hip, sp, chest, head, hd, fwd = (sk[k] for k in ("hip", "sp", "chest", "head", "hd", "fwd"))
    dead = float(p.get("dead", 0.0)) >= 0.5
    glow = float(p.get("glow", 0.0))
    parts: list[Node] = []
    # A thin ribbed torso under a charred rag that hangs from the shoulders to the knees.
    parts.append(SmoothUnion(Ellipsoid(ASH, (hip + chest) / 2 + fwd * 0.4, (7.6, 3.6, 3.4), R=_R(sp), group="body"),
                             Ellipsoid(ASH, hip + sp * 1.0, (3.6, 3.0, 3.4), group="body"), k=2.0))
    # A charred cape hanging behind, and a rag round the hips.
    parts.append(cone(RAG, chest + sp * 0.5 - fwd * 2.2, hip - sp * 4.0 - fwd * 3.6, 3.0, 4.2, group="rag"))
    parts.append(cone(RAG, hip + sp * 1.0, hip - sp * 4.5 + fwd * 0.6, 3.8, 4.4, group="rag"))
    # Hood and face: the hood a bigger shell behind and over the skull.
    parts.append(Ellipsoid(ASH, head + hd * 0.2 + fwd * 1.0, (3.2, 3.4, 3.0), group="head"))
    parts.append(Ellipsoid(RAG, head - fwd * 1.2 + hd * 0.6, (3.8, 4.2, 3.8), group="hood"))
    parts.append(cone(RAG, head - fwd * 2.0 + hd * 2.5, head - fwd * 5.0 + hd * 1.0, 1.6, 0.6, group="hood"))
    # The firepot at the far hip, embers in its mouth.
    pot = hip + fwd * 0.8 - sp * 1.0 + v((0.0, 0.0, 4.6))
    parts.append(Sphere(CLAY, pot, 3.4, group="pot"))
    parts.append(Ellipsoid(DARK_EMBER if dead else EMBER, pot + sp * 2.8, (2.0, 0.8, 2.0), group="ember"))
    parts += _arm(sk, float(p["af"]), float(p["bf"]), -SHOULDER_Z, None, 0.0, "arm_f")
    parts += _arm(sk, float(p["an"]), float(p["bn"]), SHOULDER_Z, None if dead or glow <= 0.05 else EMBER, glow, "arm_n")
    parts += _leg(sk, p["fn"], HIP_Z) + _leg(sk, p["ff"], -HIP_Z)
    node: Node = Union(*parts)
    roll = float(p.get("roll", 0.0))
    if roll:
        node = Moved(node, (0.0, 0.0, 0.0), rot(roll, 0.0, 0.0))
    return Scaled(node, SIZE)


def _R(d: np.ndarray) -> np.ndarray:
    return rot(0.0, 0.0, math.degrees(math.atan2(d[1], d[0])))


def camera() -> Camera:
    return Camera(S, S, face="left", cx=CAM_CX, cy=CAM_CY)


def _marks(fr: Frame, cam: Camera, p: dict[str, Any], big: bool = False) -> None:
    sk = skeleton(p)
    dead = float(p.get("dead", 0.0)) >= 0.5
    if float(p.get("eyes", 1.0)) >= 0.5 and not dead:
        rows = ["aa"] if big else ["a"]
        for z in (1.4, -1.4):
            pt = (sk["head"] + sk["fwd"] * 2.6 + sk["hd"] * 0.4 + v((0.0, 0.0, z))) * SIZE
            decal(fr, cam, pt, rows, {"a": (EMBER, 3)}, ("head",), tol=3.0, group="eye")
    if not dead:
        # Ember cracks across the chest.
        crack = ["a..", ".b.", "..a"]
        pt = (sk["chest"] - sk["sp"] * 4.0 + sk["fwd"] * 3.4 + v((0.0, 0.0, 2.0))) * SIZE
        decal(fr, cam, pt, crack, {"a": (EMBER, 1), "b": (EMBER, 2)}, ("body",), tol=3.0, group="crack")


def render_frame(p: dict[str, Any], cam: Camera | None = None) -> Frame:
    cam = cam or camera()
    fr = render(model(p), cam)
    _marks(fr, cam, p)
    lift_off_last_row(fr)
    return fr


def finish_frame(fr: Frame) -> np.ndarray:
    return finish(fr, keep=("eye", "ember", "crack"))


def render_cell(p: dict[str, Any]) -> np.ndarray:
    return finish_frame(render_frame(p))


PORTRAIT_POSE = pose_with(POSES["idle"], head=6.0, glow=0.9, an=-40.0, bn=70.0)


def render_portrait(p: dict[str, Any]) -> np.ndarray:
    sk = skeleton(p)
    cam = framed(PORTRAIT, 0.5, (sk["head"] - sk["sp"] * 1.5) * SIZE, (24.0, 22.0))
    fr = render(model(p), cam)
    _marks(fr, cam, p, big=True)
    return finish_frame(fr)


IDLE = POSES["idle"]
BREATH = pose_with(IDLE, hip=(0.0, 16.6), lean=15.0, head=-8.0, glow=0.55)
SHIVER = pose_with(POSES["windup"], an=158.0, bn=48.0, head=14.0)
STAGGER = pose_with(POSES["hurt"], lean=-24.0, head=26.0, hip=(-3.0, 16.0))
DEATH = [pose_with(POSES["hurt"], head=30.0),
         pose_with(IDLE, hip=(0.0, 12.0), lean=40.0, head=-20.0, an=-90.0, af=-90.0, glow=0.0, dead=1.0, eyes=0.0,
                   fn=(4.0, 0.8, HIP_Z), ff=(-2.0, 0.8, -HIP_Z)),
         pose_with(IDLE, hip=(0.0, 8.0), lean=60.0, head=-20.0, an=-60.0, af=-60.0, glow=0.0, dead=1.0, eyes=0.0,
                   fn=(6.0, 0.8, HIP_Z), ff=(0.0, 0.8, -HIP_Z), roll=15.0),
         pose_with(IDLE, hip=(0.0, 5.0), lean=80.0, head=-10.0, an=-20.0, af=-30.0, glow=0.0, dead=1.0, eyes=0.0,
                   fn=(8.0, 0.8, HIP_Z), ff=(2.0, 0.8, -HIP_Z), roll=25.0)]
_WALK = ("fn", "ff", "hip", "an", "af")
WALK = gait(IDLE, _WALK, [
    ((6.0, 0.8, HIP_Z), (-4.0, 0.8, -HIP_Z), (0.0, 16.5), -80.0, -95.0),
    ((2.0, 3.0, HIP_Z), (-1.0, 0.8, -HIP_Z), (0.0, 17.3), -70.0, -110.0),
    ((-4.0, 0.8, HIP_Z), (6.0, 0.8, -HIP_Z), (0.0, 16.5), -60.0, -120.0),
    ((-1.0, 0.8, HIP_Z), (2.0, 3.0, -HIP_Z), (0.0, 17.3), -70.0, -105.0),
])
CHASE = gait(IDLE, _WALK, [
    ((9.0, 1.5, HIP_Z), (-6.0, 2.0, -HIP_Z), (1.0, 16.0), -40.0, -130.0),
    ((3.0, 4.0, HIP_Z), (-2.0, 0.8, -HIP_Z), (1.0, 17.0), -60.0, -110.0),
    ((-6.0, 2.0, HIP_Z), (9.0, 1.5, -HIP_Z), (1.0, 16.0), -90.0, -80.0),
    ((-2.0, 0.8, HIP_Z), (3.0, 4.0, -HIP_Z), (1.0, 17.0), -70.0, -100.0),
], lean=24.0)

CLIPS = standard_clips(POSES, BREATH, SHIVER, STAGGER, DEATH, WALK, CHASE, throw=True)


def build(ctx) -> None:
    build_enemy(ctx, ID, S, POSES, CLIPS, render_frame, finish_frame, render_cell,
                render_portrait(PORTRAIT_POSE), IDLE_CYCLE_PERCENT)
