"""Barrow Brute: a hulking grave-giant dug out of an old barrow mound, slow and enormous, swinging a
tomb-stone maul (phase 19, card #257).

Silhouette: a huge hunched torso, a small head sunk between massive shoulders, one shoulder armoured
with a cracked tomb slab, arms like tree trunks, short thick legs, and a long maul whose head is a
broken grave stone. Colour areas: grey-green dead skin, dark barrow earth caked over the legs and
belly, a weathered grey slab and maul head, pale bone (teeth, the maul's binding), rot-green eyes
and a rot-green seam glowing between the slab's cracks.

Built straight from a pose dict (kit.monster). Model units are pixels before SIZE; x forward (it
faces right in the model, the camera mirrors it), y up, z toward the viewer.

Pose keys:
    hip       (x, y) of the hips
    lean      torso lean, degrees (+ = forward)
    head      head tilt, degrees (+ = chin up)
    an, bn    near (maul) arm: shoulder angle (0 forward, 90 up, -90 down) and elbow bend
    af, bf    far arm
    fn, ff    near and far foot (x, y, z)
    glow      0..1 eyes and seam (1 = the tell)
    eyes      1 = open, 0 = shut
    roll      degrees it topples sideways (death)
    dead      1 = the glow has gone out
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
from kit.sdf import Box, Ellipsoid, Moved, Node, SmoothUnion, Sphere, Union, rot
from kit.specs import ENEMY_FRAME, PORTRAIT

ID = "barrow_brute"
S = ENEMY_FRAME[ID]
SIZE = 1.5
CAM_CX = -8.0
CAM_CY = -0.5
# Mirrors idle_cycle_percent in data/enemies/barrow_brute.tres (slow, heavy breaths).
IDLE_CYCLE_PERCENT = 150

SKIN = Material.make("brute_skin", "#6b7262", wrap=0.35, ao=0.6)
EARTH = Material.make("brute_earth", "#4d4136", wrap=0.3, ao=0.6, dither=True)
SLAB = Material.make("brute_slab", "#7c7a74", wrap=0.25, ao=0.5, dither=True)
BONE = M["bone"]
WOOD = M["wood_dark"]
EYE = M["glow_rot"]
SEAM = Material.make("brute_seam", "#7aa344", below=2, above=1, emissive=True, glow_index=2)
SEAM_DEAD = Material.make("brute_seam_dead", "#3f4a30", below=1, above=1, wrap=0.3)

SPINE, NECK = 20.0, 1.5
ARM1, ARM2 = 14.0, 13.0
THIGH, SHIN = 12.0, 11.0
HIP_Z, SHOULDER_Z = 5.0, 9.5


def _pose(**kw: Any) -> dict[str, Any]:
    p: dict[str, Any] = dict(
        hip=(0.0, 21.0), lean=18.0, head=-4.0, an=-55.0, bn=20.0, af=-80.0, bf=15.0,
        fn=(5.0, 1.0, HIP_Z), ff=(-5.0, 1.0, -HIP_Z), glow=0.3, eyes=1.0, roll=0.0, dead=0.0,
    )
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    # Hunched and heavy, the maul hanging from one fist, its head resting near the floor.
    "idle": _pose(),
    # The tell: reared up, the maul hauled over its head, eyes and seam blazing.
    "windup": _pose(hip=(-2.0, 18.5), lean=-6.0, head=12.0, an=100.0, bn=35.0, af=20.0, bf=25.0,
                    fn=(7.0, 1.0, HIP_Z), ff=(-7.0, 1.0, -HIP_Z), glow=1.0),
    # The lurch forward, the maul coming over.
    "lunge": _pose(hip=(4.0, 20.0), lean=26.0, head=0.0, an=55.0, bn=10.0, af=-20.0, bf=30.0,
                   fn=(13.0, 1.0, HIP_Z), ff=(-6.0, 1.0, -HIP_Z), glow=0.8),
    # The blow lands: bent over, the maul driven down in front.
    "contact": _pose(hip=(0.0, 18.0), lean=40.0, head=-10.0, an=-25.0, bn=-15.0, af=-40.0, bf=30.0,
                     fn=(9.0, 1.0, HIP_Z), ff=(-9.0, 1.0, -HIP_Z), glow=0.6),
    # Rocked back, head thrown up, eyes shut.
    "hurt": _pose(hip=(-2.0, 20.5), lean=-10.0, head=22.0, an=-100.0, bn=30.0, af=-110.0, bf=20.0,
                  fn=(4.0, 1.0, HIP_Z), ff=(-8.0, 1.0, -HIP_Z), eyes=0.0, glow=0.2),
    # The stamp: the maul smashed straight down at its feet, knees bent.
    "slam": _pose(hip=(1.0, 17.0), lean=34.0, head=-14.0, an=-70.0, bn=-10.0, af=-60.0, bf=20.0,
                  fn=(9.0, 1.0, HIP_Z), ff=(-7.0, 1.0, -HIP_Z), glow=0.8),
}


def _R(d: np.ndarray) -> np.ndarray:
    return rot(0.0, 0.0, math.degrees(math.atan2(d[1], d[0])))


def skeleton(p: dict[str, Any]) -> dict[str, Any]:
    hx, hy = p["hip"]
    hip = v((hx, hy, 0.0))
    sp = dir2(90.0 - float(p["lean"]))
    fwd = unit(np.cross(sp, v((0.0, 0.0, 1.0))))
    chest = hip + sp * SPINE
    hd = dir2(90.0 - float(p["lean"]) * 0.6 + float(p["head"]))
    head = chest + sp * NECK + fwd * 4.0 + hd * 3.0
    return {"hip": hip, "sp": sp, "fwd": fwd, "chest": chest, "head": head, "hd": hd}


def _maul(hand: np.ndarray, grip: np.ndarray, dead: bool) -> list[Node]:
    """The maul: a dark wooden haft through the fist, bound in bone, a broken grave stone for a head."""
    top = hand + grip * 11.0
    tail = hand - grip * 4.0
    head_c = top + grip * 2.4
    R = _R(grip)
    return [cone(WOOD, tail, top, 1.2, 1.2, group="maul"),
            cone(BONE, top - grip * 1.5, top + grip * 0.5, 1.7, 1.7, group="maul"),
            Box(SLAB, head_c, (3.6, 6.0, 3.6), R=R, round=0.8, group="stone")]


def _arm(sk: dict[str, Any], a: float, b: float, z: float, group: str) -> tuple[list[Node], np.ndarray, np.ndarray]:
    sh = sk["chest"] - sk["sp"] * 2.5 + v((0.0, 0.0, z))
    elbow, hand = limb(sh, a, b, ARM1, ARM2)
    parts: list[Node] = [cone(SKIN, sh, elbow, 5.0, 4.0, group=group), cone(SKIN, elbow, hand, 4.0, 3.6, group=group),
                         Sphere(SKIN, hand, 3.8, group=group)]
    fore = unit(hand - elbow)
    return parts, hand, fore


def _leg(sk: dict[str, Any], foot: Any, z: float) -> list[Node]:
    top = sk["hip"] + v((0.0, -1.5, z))
    knee, end = two_bone(top, v(foot) + v((0.0, 2.0, 0.0)), THIGH, SHIN, v((1.0, 0.0, 0.0)))
    grp = "leg_n" if z > 0 else "leg_f"
    return [cone(EARTH, top, knee, 5.4, 4.4, group=grp), cone(EARTH, knee, end, 4.4, 3.8, group=grp),
            Ellipsoid(EARTH, end + v((2.0, -1.0, 0.0)), (5.0, 2.2, 3.6), group=grp)]


def model(p: dict[str, Any]) -> Node:
    sk = skeleton(p)
    hip, sp, fwd, chest, head, hd = (sk[k] for k in ("hip", "sp", "fwd", "chest", "head", "hd"))
    dead = float(p.get("dead", 0.0)) >= 0.5
    parts: list[Node] = []
    torso = SmoothUnion(Ellipsoid(SKIN, chest - sp * 5.0 + fwd * 1.0, (10.0, 12.0, 10.0), R=_R(sp), group="body"),
                        Ellipsoid(SKIN, chest + fwd * 1.0, (7.0, 9.0, 9.5), group="body"),
                        Ellipsoid(EARTH, hip + sp * 3.0 + fwd * 1.5, (8.5, 8.0, 8.5), group="belly"), k=4.0)
    parts.append(torso)
    # The tomb slab over the near shoulder, cracked, a rot seam glowing in the crack.
    slab_c = chest - sp * 1.0 + v((0.0, 0.0, SHOULDER_Z - 1.0)) - fwd * 1.0
    parts.append(Box(SLAB, slab_c, (7.0, 3.0, 6.0), R=_R(fwd) @ rot(0.0, 0.0, 15.0), round=0.8, group="slab"))
    parts.append(Ellipsoid(SEAM_DEAD if dead else SEAM, slab_c + sp * 2.6 + v((0.0, 0.0, 2.0)), (4.0, 0.7, 2.6),
                           group="seam"))
    # A small head sunk between the shoulders, a heavy jaw with bone teeth.
    parts.append(Ellipsoid(SKIN, head, (5.0, 5.4, 5.0), group="head"))
    jaw = head + fwd * 2.0 - hd * 3.2
    parts.append(Ellipsoid(SKIN, jaw, (4.0, 2.6, 4.4), group="head"))
    for z in (1.8, -1.8):
        parts.append(cone(BONE, jaw + fwd * 3.2 + v((0.0, 1.2, z)), jaw + fwd * 3.4 + v((0.0, 3.0, z)), 0.8, 0.4,
                          group="teeth", thin=True))
    far, _, _ = _arm(sk, float(p["af"]), float(p["bf"]), -SHOULDER_Z, "arm_f")
    near, hand, fore = _arm(sk, float(p["an"]), float(p["bn"]), SHOULDER_Z, "arm_n")
    parts += far + near
    # The haft runs along the forearm's line, turned a little up toward the shoulder.
    grip = unit(fore + sp * 0.15)
    parts += _maul(hand + v((0.0, 0.0, 1.0)), grip, dead)
    parts += _leg(sk, p["fn"], HIP_Z) + _leg(sk, p["ff"], -HIP_Z)
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
    hot = float(p.get("glow", 0.0)) >= 0.9
    rows = (["aa", "ab"] if big else ["aa"]) if hot else (["ab"] if big else ["b"])
    for z in (2.2, -2.2):
        pt = (sk["head"] + sk["fwd"] * 4.4 + sk["hd"] * 1.0 + v((0.0, 0.0, z))) * SIZE
        decal(fr, cam, pt, rows, {"a": (EYE, 3), "b": (EYE, 2)}, ("head",), tol=4.0, group="eye")


def render_frame(p: dict[str, Any], cam: Camera | None = None) -> Frame:
    cam = cam or camera()
    fr = render(model(p), cam)
    _eyes(fr, cam, p)
    lift_off_last_row(fr)
    return fr


def finish_frame(fr: Frame) -> np.ndarray:
    return finish(fr, keep=("eye", "seam", "teeth"))


def render_cell(p: dict[str, Any]) -> np.ndarray:
    return finish_frame(render_frame(p))


PORTRAIT_POSE = pose_with(POSES["idle"], head=8.0, glow=0.8)


def render_portrait(p: dict[str, Any]) -> np.ndarray:
    sk = skeleton(p)
    cam = framed(PORTRAIT, 1.3, (sk["head"] - sk["sp"] * 1.0) * SIZE, (25.0, 23.0))
    fr = render(model(p), cam)
    _eyes(fr, cam, p, big=True)
    return finish_frame(fr)


IDLE = POSES["idle"]
BREATH = pose_with(IDLE, hip=(0.0, 20.4), lean=20.0, head=-6.0, glow=0.45)
SHIVER = pose_with(POSES["windup"], an=104.0, bn=38.0, head=16.0)
STAGGER = pose_with(POSES["hurt"], lean=-16.0, head=26.0, hip=(-3.0, 20.0))
DEATH = [pose_with(POSES["hurt"], head=30.0),
         pose_with(IDLE, hip=(0.0, 15.0), lean=40.0, head=-20.0, an=-80.0, af=-80.0, glow=0.0, dead=1.0, eyes=0.0,
                   fn=(8.0, 1.0, HIP_Z), ff=(-3.0, 1.0, -HIP_Z)),
         pose_with(IDLE, hip=(0.0, 10.0), lean=62.0, head=-10.0, an=-40.0, af=-50.0, glow=0.0, dead=1.0, eyes=0.0,
                   fn=(10.0, 1.0, HIP_Z), ff=(0.0, 1.0, -HIP_Z), roll=10.0),
         pose_with(IDLE, hip=(0.0, 7.0), lean=78.0, head=0.0, an=-10.0, af=-20.0, glow=0.0, dead=1.0, eyes=0.0,
                   fn=(12.0, 1.0, HIP_Z), ff=(2.0, 1.0, -HIP_Z), roll=18.0)]
_WALK = ("fn", "ff", "hip", "af")
WALK = gait(IDLE, _WALK, [
    ((9.0, 1.0, HIP_Z), (-6.0, 1.0, -HIP_Z), (0.0, 20.4), -70.0),
    ((3.0, 4.0, HIP_Z), (-2.0, 1.0, -HIP_Z), (0.0, 21.4), -80.0),
    ((-6.0, 1.0, HIP_Z), (9.0, 1.0, -HIP_Z), (0.0, 20.4), -95.0),
    ((-2.0, 1.0, HIP_Z), (3.0, 4.0, -HIP_Z), (0.0, 21.4), -85.0),
])
CHASE = gait(IDLE, _WALK, [
    ((12.0, 2.0, HIP_Z), (-8.0, 2.0, -HIP_Z), (1.0, 20.0), -50.0),
    ((4.0, 5.0, HIP_Z), (-3.0, 1.0, -HIP_Z), (1.0, 21.0), -70.0),
    ((-8.0, 2.0, HIP_Z), (12.0, 2.0, -HIP_Z), (1.0, 20.0), -100.0),
    ((-3.0, 1.0, HIP_Z), (4.0, 5.0, -HIP_Z), (1.0, 21.0), -80.0),
], lean=26.0, glow=0.6)

CLIPS = standard_clips(POSES, BREATH, SHIVER, STAGGER, DEATH, WALK, CHASE)


def build(ctx) -> None:
    build_enemy(ctx, ID, S, POSES, CLIPS, render_frame, finish_frame, render_cell,
                render_portrait(PORTRAIT_POSE), IDLE_CYCLE_PERCENT)
