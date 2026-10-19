"""Rot Priest: a hollow-eyed priest of the rot in tattered vestments, who keeps its fellow monsters
on their feet: it heals them and wards them with bone, and hushes heroes with a word (phase 19,
card #259).

Silhouette: a tall, narrow robed figure swelling to a wide hem on the floor, a tall bone mitre over
a gaunt grey face, a long thin arm swinging a censer on a chain that leaks rot-green smoke, the
other hand raised in blessing. Colour areas: faded violet-grey robes with a dull gold trim, pale
bone (the mitre, the hand), a grey-green face, a dark iron censer with a rot-green glow.

Built straight from a pose dict (kit.monster). Model units are pixels before SIZE; x forward (it
faces right in the model, the camera mirrors it), y up, z toward the viewer.

Pose keys:
    hip       (x, y) of the hips
    lean      torso lean, degrees (+ = forward)
    head      head tilt, degrees
    an, bn    near (censer) arm: shoulder angle (0 forward, 90 up, -90 down) and elbow bend
    af, bf    far (blessing) arm
    chain     the censer chain's angle from the hand, degrees (-90 = hanging straight down)
    hem       (x) how far the robe's hem trails forward (+) or back (-)
    glow      0..1 the censer and eyes (1 = the tell)
    eyes      1 = open, 0 = shut
    roll      degrees it topples sideways (death)
    dead      1 = the censer has gone out
"""
from __future__ import annotations

import math
from typing import Any

import numpy as np

from kit.beast import build_enemy, cone, decal, dir2, finish, framed, lift_off_last_row, pose_with, unit, v
from kit.monster import Scaled, limb, standard_clips
from kit.palette import M, Material
from kit.render import Camera, Frame, render
from kit.sdf import Ellipsoid, Moved, Node, SmoothUnion, Sphere, Union, rot
from kit.specs import ENEMY_FRAME, PORTRAIT

ID = "rot_priest"
S = ENEMY_FRAME[ID]
SIZE = 1.25
CAM_CX = 0.0
CAM_CY = -0.5
IDLE_CYCLE_PERCENT = 120

ROBE = Material.make("priest_robe", "#6a5a6e", wrap=0.35, ao=0.5)
TRIM = Material.make("priest_trim", "#9a7a44", below=1, above=1, wrap=0.3)
FACE = Material.make("priest_face", "#7d8070", wrap=0.4, ao=0.4)
BONE = M["bone"]
IRON = Material.make("priest_iron", "#4a4448", wrap=0.3, ao=0.4, spec=0.4, spec_power=10.0)
GLOW = M["glow_rot"]
DEAD = Material.make("priest_censer_dead", "#3f4a30", below=1, above=1, wrap=0.3)

SPINE, NECK = 15.0, 2.0
ARM1, ARM2 = 9.0, 9.0
SHOULDER_Z = 4.2


def _pose(**kw: Any) -> dict[str, Any]:
    p: dict[str, Any] = dict(
        hip=(0.0, 17.0), lean=4.0, head=-4.0, an=-60.0, bn=30.0, af=-70.0, bf=60.0, chain=-90.0, hem=0.0,
        glow=0.4, eyes=1.0, roll=0.0, dead=0.0,
    )
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    # Upright, the censer hanging from one hand, the other hand folded at the chest.
    "idle": _pose(),
    # The tell: the censer swung high overhead, smoke blazing, the other hand raised.
    "windup": _pose(lean=-8.0, head=12.0, an=110.0, bn=20.0, af=60.0, bf=30.0, chain=150.0, hem=-2.0, glow=1.0),
    # Gliding forward, the censer swinging out ahead.
    "lunge": _pose(hip=(3.0, 17.0), lean=16.0, an=20.0, bn=0.0, af=-110.0, bf=20.0, chain=10.0, hem=-4.0, glow=0.8),
    # The censer strikes: arm down and forward, the chain whipping.
    "contact": _pose(hip=(3.0, 16.5), lean=22.0, head=-10.0, an=-20.0, bn=-10.0, af=-120.0, bf=20.0, chain=-30.0,
                     hem=-4.0, glow=0.6),
    # Struck: thrown back, arms flung, eyes shut.
    "hurt": _pose(hip=(-2.0, 17.0), lean=-16.0, head=20.0, an=-120.0, bn=30.0, af=-130.0, bf=20.0, chain=-120.0,
                  hem=3.0, eyes=0.0, glow=0.2),
    # The blessing cast: both arms thrust forward, the censer held out burning.
    "slam": _pose(hip=(1.0, 17.0), lean=10.0, head=4.0, an=10.0, bn=-10.0, af=20.0, bf=-10.0, chain=-60.0, glow=1.0),
}


def _R(d: np.ndarray) -> np.ndarray:
    return rot(0.0, 0.0, math.degrees(math.atan2(d[1], d[0])))


def skeleton(p: dict[str, Any]) -> dict[str, Any]:
    hx, hy = p["hip"]
    hip = v((hx, hy, 0.0))
    sp = dir2(90.0 - float(p["lean"]))
    fwd = unit(np.cross(sp, v((0.0, 0.0, 1.0))))
    chest = hip + sp * SPINE
    hd = dir2(90.0 - float(p["lean"]) * 1.2 + float(p["head"]))
    head = chest + sp * NECK + hd * 3.4
    return {"hip": hip, "sp": sp, "fwd": fwd, "chest": chest, "head": head, "hd": hd}


def _arm(sk: dict[str, Any], a: float, b: float, z: float, group: str) -> tuple[list[Node], np.ndarray]:
    sh = sk["chest"] - sk["sp"] * 1.5 + v((0.0, 0.0, z))
    elbow, hand = limb(sh, a, b, ARM1, ARM2)
    return [cone(ROBE, sh, elbow, 2.6, 2.2, group=group), cone(ROBE, elbow, hand, 2.2, 1.6, group=group),
            Sphere(BONE, hand, 1.4, group=group)], hand


def model(p: dict[str, Any]) -> Node:
    sk = skeleton(p)
    hip, sp, fwd, chest, head, hd = (sk[k] for k in ("hip", "sp", "fwd", "chest", "head", "hd"))
    dead = float(p.get("dead", 0.0)) >= 0.5
    glow = 0.0 if dead else float(p.get("glow", 0.0))
    parts: list[Node] = []
    # The robe: a narrow torso swelling to a wide hem on the floor, a gold trim at the hem.
    hem_c = v((float(p["hip"][0]) + float(p.get("hem", 0.0)), 1.6, 0.0))
    parts.append(SmoothUnion(Ellipsoid(ROBE, (hip + chest) / 2, (7.6, 4.2, 4.0), R=_R(sp), group="body"),
                             cone(ROBE, hip + sp * 2.0, hem_c + v((0.0, 1.5, 0.0)), 4.4, 7.4, group="body"), k=2.5))
    parts.append(Ellipsoid(TRIM, hem_c, (7.6, 1.4, 7.4), group="trim"))
    parts.append(cone(TRIM, chest + fwd * 3.0, hip + fwd * 3.6 + sp * 1.0, 0.9, 0.9, group="trim"))
    # A gaunt face under a tall bone mitre.
    parts.append(Ellipsoid(FACE, head + fwd * 0.6, (3.0, 3.4, 2.8), group="head"))
    parts.append(cone(BONE, head + hd * 1.8, head + hd * 7.5 - fwd * 0.6, 3.2, 1.4, group="mitre"))
    parts.append(cone(ROBE, head + hd * 1.0 - fwd * 2.0, chest - fwd * 3.0, 2.8, 3.6, group="body"))
    far, _ = _arm(sk, float(p["af"]), float(p["bf"]), -SHOULDER_Z, "arm_f")
    near, hand = _arm(sk, float(p["an"]), float(p["bn"]), SHOULDER_Z, "arm_n")
    parts += far + near
    # The censer on its chain.
    cen = hand + dir2(float(p["chain"])) * 7.0
    parts.append(cone(IRON, hand, cen, 0.4, 0.4, group="chain", thin=True))
    parts.append(Sphere(IRON, cen, 2.4, group="censer"))
    parts.append(Ellipsoid(DEAD if dead else GLOW, cen + v((0.0, 1.6, 0.6)), (1.6 + glow, 1.0 + glow * 1.6, 1.6 + glow),
                           group="smoke"))
    node: Node = Union(*parts)
    roll = float(p.get("roll", 0.0))
    if roll:
        node = Moved(node, (0.0, 0.0, 0.0), rot(roll, 0.0, 0.0))
    return Scaled(node, SIZE)


def camera() -> Camera:
    return Camera(S, S, face="left", cx=CAM_CX, cy=CAM_CY)


def _eyes(fr: Frame, cam: Camera, p: dict[str, Any], big: bool = False) -> None:
    if float(p.get("eyes", 1.0)) < 0.5 or float(p.get("dead", 0.0)) >= 0.5:
        return
    sk = skeleton(p)
    rows = ["aa"] if big else ["a"]
    for z in (1.3, -1.3):
        pt = (sk["head"] + sk["fwd"] * 2.8 + sk["hd"] * 0.6 + v((0.0, 0.0, z))) * SIZE
        decal(fr, cam, pt, rows, {"a": (GLOW, 3 if float(p.get("glow", 0.0)) >= 0.9 else 2)}, ("head",), tol=3.0,
              group="eye")


def render_frame(p: dict[str, Any], cam: Camera | None = None) -> Frame:
    cam = cam or camera()
    fr = render(model(p), cam)
    _eyes(fr, cam, p)
    lift_off_last_row(fr)
    return fr


def finish_frame(fr: Frame) -> np.ndarray:
    return finish(fr, keep=("eye", "smoke", "chain", "trim"))


def render_cell(p: dict[str, Any]) -> np.ndarray:
    return finish_frame(render_frame(p))


PORTRAIT_POSE = pose_with(POSES["idle"], head=6.0, glow=0.8)


def render_portrait(p: dict[str, Any]) -> np.ndarray:
    sk = skeleton(p)
    cam = framed(PORTRAIT, 0.6, (sk["head"] + sk["hd"] * 1.0) * SIZE, (24.0, 24.0))
    fr = render(model(p), cam)
    _eyes(fr, cam, p, big=True)
    return finish_frame(fr)


IDLE = POSES["idle"]
BREATH = pose_with(IDLE, chain=-80.0, glow=0.6, head=-2.0)
SHIVER = pose_with(POSES["windup"], chain=170.0, an=116.0)
STAGGER = pose_with(POSES["hurt"], lean=-22.0, head=26.0, chain=-150.0)
DEATH = [pose_with(POSES["hurt"], head=30.0),
         pose_with(IDLE, hip=(0.0, 13.0), lean=30.0, head=-20.0, an=-90.0, af=-90.0, chain=-90.0, glow=0.0, dead=1.0,
                   eyes=0.0),
         pose_with(IDLE, hip=(0.0, 9.0), lean=55.0, head=-20.0, an=-60.0, af=-60.0, chain=-80.0, dead=1.0, eyes=0.0,
                   roll=12.0),
         pose_with(IDLE, hip=(0.0, 6.0), lean=75.0, head=-10.0, an=-30.0, af=-40.0, chain=-60.0, dead=1.0, eyes=0.0,
                   roll=22.0)]
# It glides: the hem sways, the censer swings.
WALK = [pose_with(IDLE, hem=h, chain=c, hip=(0.0, 17.0 + dy)) for h, c, dy in
        ((2.0, -70.0, 0.0), (0.0, -90.0, 0.4), (-2.0, -110.0, 0.0), (0.0, -90.0, 0.4))]
CHASE = [pose_with(IDLE, lean=14.0, hem=h, chain=c, hip=(1.0, 17.0 + dy), glow=0.7) for h, c, dy in
         ((-3.0, -50.0, 0.0), (-4.0, -70.0, 0.5), (-5.0, -100.0, 0.0), (-4.0, -70.0, 0.5))]

CLIPS = standard_clips(POSES, BREATH, SHIVER, STAGGER, DEATH, WALK, CHASE, throw=True)


def build(ctx) -> None:
    build_enemy(ctx, ID, S, POSES, CLIPS, render_frame, finish_frame, render_cell,
                render_portrait(PORTRAIT_POSE), IDLE_CYCLE_PERCENT)
