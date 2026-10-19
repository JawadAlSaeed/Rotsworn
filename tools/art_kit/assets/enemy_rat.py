"""Rot Rat: a dog-sized sewer rat the rot keeps fat and quick, always met in threes (phase 19,
card #255).

Silhouette: a low hunched body, a long pointed snout with yellow incisors, big round pink ears, a
long bare pink tail curling up behind, short quick legs. Colour areas: mangy grey-brown fur, a
paler belly, dull pink ears, nose, paws and tail, a violet rot sore on the flank with a dim
rot-green heart, and rot-green eyes that flare in the tell.

Built straight from a pose dict like enemy_hyena (no rig). Model units are pixels before SIZE;
x is forward (it faces right in the model; the camera mirrors it to face left like every enemy),
y up, z toward the viewer.

Pose keys:
    body      (x, y) of the body's centre
    pitch     spine angle, degrees (+ = shoulders up)
    head      head pitch, degrees (+ = snout up)
    jaw       jaw opening, degrees
    tail      tail lift, degrees (+ = curls up)
    fn/ff     front paw (near/far) position; hn/hf hind paw position (x, y, z)
    glow      0..1 eye brightness (1 = the tell)
    eyes      1 = open, 0 = shut (hurt)
    roll      degrees the whole body rolls onto its side (death)
    dead      1 = the sore has gone dark
"""
from __future__ import annotations

import math
from typing import Any

import numpy as np

from kit.beast import build_enemy, cone, decal, dir2, finish, framed, lift_off_last_row, mix, pose_with, unit, v
from kit.monster import Scaled, gait, standard_clips
from kit.palette import M, Material
from kit.render import Camera, Frame, render
from kit.sdf import Ellipsoid, Moved, Node, SmoothUnion, Sphere, Union, rot
from kit.specs import ENEMY_FRAME, PORTRAIT

ID = "rot_rat"
S = ENEMY_FRAME[ID]
SIZE = 1.0
CAM_CX = 4.0
CAM_CY = -1.0
# Mirrors idle_cycle_percent in data/enemies/rot_rat.tres (a quick, twitchy breath).
IDLE_CYCLE_PERCENT = 70

FUR = Material.make("rat_fur", "#6a5f57", wrap=0.3, ao=0.6)
PALE = Material.make("rat_belly", "#8c8076", wrap=0.4, ao=0.5)
PINK = Material.make("rat_pink", "#a8767a", wrap=0.4, ao=0.4)
DARK = Material.make("rat_dark", "#3b3236", wrap=0.3, ao=0.4)
TOOTH = Material.make("rat_tooth", "#d8b860", below=1, above=1, wrap=0.3)
EYE = M["glow_rot"]
LESION = M["rot_purple"]
CORE = Material.make("rat_rot_core", "#7aa344", below=2, above=1, emissive=True, glow_index=2)
CORE_DEAD = Material.make("rat_rot_dead", "#3f4a30", below=1, above=1, wrap=0.3)

LEG_Z = 3.2


def _pose(**kw: Any) -> dict[str, Any]:
    p: dict[str, Any] = dict(
        body=(0.0, 8.5), pitch=6.0, head=-12.0, jaw=6.0, tail=40.0,
        fn=(9.0, 1.2, LEG_Z), ff=(7.0, 1.2, -LEG_Z), hn=(-7.0, 1.2, LEG_Z + 0.4), hf=(-9.0, 1.2, -LEG_Z - 0.4),
        glow=0.0, eyes=1.0, roll=0.0, dead=0.0,
    )
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    # Hunched on all fours, snout low and twitching, tail curled up behind.
    "idle": _pose(),
    # The tell: sat back on its haunches, chest up, jaws wide on the yellow teeth, eyes flaring.
    "windup": _pose(body=(-2.5, 7.0), pitch=22.0, head=6.0, jaw=34.0, tail=45.0, fn=(6.0, 4.0, LEG_Z),
                    ff=(5.0, 3.0, -LEG_Z), glow=1.0),
    # The leap: stretched long and low, front paws reaching, hind legs kicked back.
    "lunge": _pose(body=(0.5, 9.5), pitch=-2.0, head=-4.0, jaw=40.0, tail=18.0, fn=(12.0, 5.0, LEG_Z),
                   ff=(10.5, 4.0, -LEG_Z), hn=(-15.0, 4.0, LEG_Z), hf=(-13.0, 3.0, -LEG_Z), glow=0.6),
    # The bite: landed, snout driven down, jaws snapped shut.
    "contact": _pose(body=(2.0, 7.5), pitch=-10.0, head=-26.0, jaw=4.0, tail=15.0, fn=(13.0, 1.2, LEG_Z),
                     ff=(11.0, 1.2, -LEG_Z), glow=0.6),
    # Recoil: reared up, head flung back, eyes shut.
    "hurt": _pose(body=(-2.0, 9.0), pitch=30.0, head=30.0, jaw=24.0, tail=40.0, fn=(5.0, 6.0, LEG_Z),
                  ff=(4.0, 4.0, -LEG_Z), hn=(-8.0, 0.4, LEG_Z + 0.4), hf=(-10.0, 0.4, -LEG_Z - 0.4), eyes=0.0),
    # Both front paws stamped down together, chest low.
    "slam": _pose(body=(1.0, 7.0), pitch=-4.0, head=-20.0, jaw=26.0, tail=30.0, fn=(11.0, 1.2, LEG_Z - 1.0),
                  ff=(10.0, 1.2, -LEG_Z + 1.0), glow=0.6),
}


def _R(d: np.ndarray) -> np.ndarray:
    return rot(0.0, 0.0, math.degrees(math.atan2(d[1], d[0])))


def _frame(p: dict[str, Any]) -> dict[str, Any]:
    bx, by = p["body"]
    c = v((bx, by, 0.0))
    sp = dir2(float(p["pitch"]))
    up = unit(np.cross(v((0.0, 0.0, 1.0)), sp))
    hd = dir2(float(p["pitch"]) * 0.3 + float(p["head"]))
    hup = unit(np.cross(v((0.0, 0.0, 1.0)), hd))
    sh = c + sp * 6.0
    hc = sh + sp * 4.0 + up * 1.5
    return {"c": c, "sp": sp, "up": up, "hd": hd, "hup": hup, "hip": c - sp * 7.0, "sh": sh, "hc": hc}


def model(p: dict[str, Any]) -> Node:
    f = _frame(p)
    c, sp, up, hd, hup, hip, sh, hc = (f[k] for k in ("c", "sp", "up", "hd", "hup", "hip", "sh", "hc"))
    parts: list[Node] = []
    body = SmoothUnion(Ellipsoid(FUR, c, (10.0, 6.0, 5.8), R=_R(sp), group="body"),
                       Ellipsoid(FUR, hip + up * 0.8, (6.2, 6.4, 5.6), group="body"),
                       Ellipsoid(FUR, sh + up * 0.4, (5.0, 5.0, 4.6), group="body"), k=2.5)
    parts += [body, Ellipsoid(PALE, c - up * 3.4 + sp * 1.0, (7.0, 2.2, 4.0), R=_R(sp), group="body")]
    sore = c + up * 1.2 - sp * 2.0 + v((0.0, 0.0, 5.2))
    parts.append(Ellipsoid(LESION, sore, (2.8, 2.2, 1.2), group="body"))
    parts.append(Ellipsoid(CORE_DEAD if float(p.get("dead", 0.0)) >= 0.5 else CORE, sore + v((0.0, 0.0, 0.7)),
                           (1.6, 1.2, 0.9), group="wound"))
    # Head: a round skull, a long pointed snout, a pink nose, the jaw hinged under it.
    parts.append(Ellipsoid(FUR, hc, (4.6, 3.8, 3.6), R=_R(hd), group="head"))
    tip = hc + hd * 7.5 - hup * 0.8
    parts.append(cone(FUR, hc + hd * 2.0, tip, 2.7, 1.0, group="head"))
    parts.append(Sphere(PINK, tip + hd * 0.6, 1.0, group="head"))
    ja = math.radians(float(p["jaw"]))
    jdir = unit(hd * math.cos(ja) - hup * math.sin(ja))
    jaw_a = hc + hd * 1.2 - hup * 2.0
    parts.append(cone(FUR, jaw_a, jaw_a + jdir * 5.5, 1.6, 0.8, group="jaw"))
    # The incisors: two yellow teeth at the front, the lower one on the jaw.
    parts.append(cone(TOOTH, tip - hup * 0.6, tip - hup * 2.2 - hd * 0.2, 0.6, 0.4, group="teeth", thin=True))
    if float(p["jaw"]) > 10.0:
        low = jaw_a + jdir * 5.0
        parts.append(cone(TOOTH, low, low + hup * 1.4, 0.5, 0.35, group="teeth", thin=True))
    for z in (2.4, -2.4):
        parts.append(Ellipsoid(PINK, hc + hup * 3.6 - hd * 1.2 + v((0.0, 0.0, z)), (2.2, 2.5, 0.8),
                               R=_R(unit(hup - hd * 0.4)), group="ear"))
    # A long bare tail in three bending segments.
    t0 = hip - sp * 5.0 + up * 0.5
    lift = float(p["tail"])
    pts = [t0]
    for k in range(3):
        d = dir2(180.0 - lift * (0.5 + 0.35 * k))
        pts.append(pts[-1] + d * 4.6)
    for k in range(3):
        parts.append(cone(PINK, pts[k], pts[k + 1], 1.3 - 0.3 * k, 1.0 - 0.3 * k, group="tail"))
    # Short legs: one bend each, a dark paw.
    for key, z, front in (("fn", LEG_Z, True), ("ff", -LEG_Z, True), ("hn", LEG_Z + 0.4, False),
                          ("hf", -LEG_Z - 0.4, False)):
        paw = v(p[key])
        top = (sh - up * 2.0 if front else hip - up * 1.0) + v((0.0, 0.0, z))
        knee = (top + paw) / 2 + (v((1.2, 0.5, 0.0)) if front else v((-2.0, 1.5, 0.0)))
        grp = "leg_n" if z > 0 else "leg_f"
        parts += [cone(FUR, top, knee, 2.4 if not front else 2.0, 1.5, group=grp),
                  cone(FUR, knee, paw + v((0.0, 0.5, 0.0)), 1.4, 1.1, group=grp),
                  Ellipsoid(PINK, paw + v((1.0, 0.2, 0.0)), (1.8, 0.9, 1.3), group=grp)]
    node: Node = Union(*parts)
    roll = float(p.get("roll", 0.0))
    if roll:
        node = Moved(node, (0.0, 0.0, 0.0), rot(roll, 0.0, 0.0))
    return Scaled(node, SIZE)


def camera() -> Camera:
    return Camera(S, S, face="left", cx=CAM_CX, cy=CAM_CY)


def _eyes(fr: Frame, cam: Camera, p: dict[str, Any], big: bool = False) -> None:
    if float(p.get("eyes", 1.0)) < 0.5:
        return
    f = _frame(p)
    hot = float(p.get("glow", 0.0)) >= 0.9
    rows = (["aa", "ab"] if big else ["a"]) if hot else (["ab", "bb"] if big else ["b"])
    legend = {"a": (EYE, 3), "b": (EYE, 2)}
    for z in (2.8, -2.8):
        pt = (f["hc"] + f["hd"] * 2.6 + f["hup"] * 1.2 + v((0.0, 0.0, z))) * SIZE
        decal(fr, cam, pt, rows, legend, ("head",), tol=3.0, group="eye")


def render_frame(p: dict[str, Any], cam: Camera | None = None) -> Frame:
    cam = cam or camera()
    fr = render(model(p), cam)
    _eyes(fr, cam, p)
    lift_off_last_row(fr)
    return fr


def finish_frame(fr: Frame) -> np.ndarray:
    return finish(fr, keep=("eye", "teeth", "wound"))


def render_cell(p: dict[str, Any]) -> np.ndarray:
    return finish_frame(render_frame(p))


PORTRAIT_POSE = pose_with(POSES["idle"], head=8.0, jaw=26.0, glow=0.6)


def render_portrait(p: dict[str, Any]) -> np.ndarray:
    f = _frame(p)
    cam = framed(PORTRAIT, 0.4, (f["hc"] + f["hd"] * 2.5) * SIZE, (26.0, 25.0))
    fr = render(model(p), cam)
    _eyes(fr, cam, p, big=True)
    return finish_frame(fr)


IDLE = POSES["idle"]
BREATH = pose_with(IDLE, body=(0.0, 8.0), head=-8.0, jaw=12.0, tail=30.0)
SHIVER = pose_with(POSES["windup"], body=(-2.5, 6.6), jaw=40.0, head=10.0)
STAGGER = pose_with(POSES["hurt"], body=(-3.0, 8.0), pitch=36.0, head=36.0, fn=(4.0, 8.0, LEG_Z))
DEATH = [pose_with(POSES["hurt"], jaw=36.0, head=34.0),
         pose_with(IDLE, body=(0.0, 6.0), pitch=2.0, head=-28.0, jaw=18.0, eyes=0.0, dead=1.0, tail=0.0),
         pose_with(IDLE, body=(0.0, 4.5), pitch=0.0, head=-20.0, jaw=12.0, eyes=0.0, dead=1.0, tail=-5.0, roll=20.0),
         pose_with(IDLE, body=(0.0, 3.6), pitch=-2.0, head=-16.0, jaw=10.0, eyes=0.0, dead=1.0, tail=-10.0, roll=32.0,
                   fn=(12.0, 2.0, LEG_Z + 2.0), hn=(-10.0, 2.0, LEG_Z + 2.0))]
_LEGS = ("fn", "ff", "hn", "hf", "body")
WALK = gait(IDLE, _LEGS, [
    ((12.0, 1.2, LEG_Z), (5.0, 1.2, -LEG_Z), (-9.0, 1.2, LEG_Z), (-6.0, 1.2, -LEG_Z), (0.0, 8.2)),
    ((9.0, 3.0, LEG_Z), (7.0, 1.2, -LEG_Z), (-7.0, 1.2, LEG_Z), (-9.0, 3.0, -LEG_Z), (0.0, 9.0)),
    ((6.0, 1.2, LEG_Z), (10.0, 1.2, -LEG_Z), (-5.0, 1.2, LEG_Z), (-11.0, 1.2, -LEG_Z), (0.0, 8.2)),
    ((8.0, 1.2, LEG_Z), (8.0, 3.0, -LEG_Z), (-8.0, 3.0, LEG_Z), (-8.0, 1.2, -LEG_Z), (0.0, 9.0)),
])
CHASE = gait(IDLE, _LEGS, [
    ((15.0, 3.0, LEG_Z), (13.0, 4.0, -LEG_Z), (-11.0, 1.2, LEG_Z), (-9.0, 2.0, -LEG_Z), (1.0, 9.5)),
    ((10.0, 1.2, LEG_Z), (8.0, 1.2, -LEG_Z), (-6.0, 3.0, LEG_Z), (-4.0, 4.0, -LEG_Z), (1.0, 8.0)),
    ((6.0, 2.0, LEG_Z), (5.0, 1.2, -LEG_Z), (-13.0, 4.0, LEG_Z), (-11.0, 3.0, -LEG_Z), (1.0, 9.0)),
    ((11.0, 4.0, LEG_Z), (9.0, 3.0, -LEG_Z), (-9.0, 1.2, LEG_Z), (-7.0, 1.2, -LEG_Z), (1.0, 8.6)),
], pitch=2.0, head=-6.0, jaw=20.0, tail=12.0, glow=0.6)

CLIPS = standard_clips(POSES, BREATH, SHIVER, STAGGER, DEATH, WALK, CHASE)


def build(ctx) -> None:
    build_enemy(ctx, ID, S, POSES, CLIPS, render_frame, finish_frame, render_cell,
                render_portrait(PORTRAIT_POSE), IDLE_CYCLE_PERCENT)
