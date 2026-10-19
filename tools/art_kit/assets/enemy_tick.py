"""Pus Tick: a tick gorged on rot until its back is one huge sac of pus that swells, glows and at
last bursts over everything near it (phase 19, card #260).

Silhouette: a small dark armoured head with hooked mouthparts in front, a huge round swollen sac
behind it shining with sick yellow-green pus and veined with violet, eight short jointed legs.
Colour areas: dark chitin, a pale yellow-green sac with violet veins, a rot-green glow that grows
as it swells (the Burst's countdown on screen).

Built straight from a pose dict (kit.monster). Model units are pixels before SIZE; x forward (it
faces right in the model, the camera mirrors it), y up, z toward the viewer.

Pose keys:
    body     (x, y) of the sac's centre
    swell    0..1 how swollen the sac is (1 = about to burst)
    pitch    body tilt, degrees (+ = head up)
    reach    0..1 the front legs and mouthparts thrust forward (a bite)
    spread   0..1 the legs splay wide (a stamp)
    glow     0..1 the pus glow (1 = the tell)
    roll     degrees it rolls over (death)
    dead     1 = burst and flat
"""
from __future__ import annotations

import math
from typing import Any

import numpy as np

from kit.beast import build_enemy, cone, decal, dir2, finish, framed, lift_off_last_row, pose_with, unit, v
from kit.monster import Scaled, gait, standard_clips
from kit.palette import M, Material
from kit.render import Camera, Frame, render
from kit.sdf import Ellipsoid, Moved, Node, SmoothUnion, Sphere, Union, rot
from kit.specs import ENEMY_FRAME, PORTRAIT

ID = "pus_tick"
S = ENEMY_FRAME[ID]
SIZE = 1.0
CAM_CX = 1.0
CAM_CY = -0.5
IDLE_CYCLE_PERCENT = 110

CHITIN = Material.make("tick_chitin", "#3e3438", wrap=0.3, ao=0.5, spec=0.5, spec_power=12.0)
SAC = Material.make("tick_sac", "#a9b062", wrap=0.45, ao=0.4, spec=0.6, spec_power=14.0)
VEIN = M["rot_purple"]
GLOW = Material.make("tick_glow", "#bfe85e", below=2, above=1, emissive=True)
FLAT = Material.make("tick_flat", "#5a5440", wrap=0.3, ao=0.5)

LEGS = 4


def _pose(**kw: Any) -> dict[str, Any]:
    p: dict[str, Any] = dict(body=(-2.0, 11.0), swell=0.3, pitch=6.0, reach=0.0, spread=0.0, glow=0.3, roll=0.0,
                             dead=0.0)
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    "idle": _pose(),
    # The tell: the sac swelling, glowing, the head ducked down.
    "windup": _pose(body=(-3.0, 12.5), swell=1.0, pitch=-6.0, glow=1.0, spread=0.4),
    # Scuttling forward, mouthparts out.
    "lunge": _pose(body=(1.0, 11.0), swell=0.4, pitch=-4.0, reach=1.0, glow=0.6),
    # The bite.
    "contact": _pose(body=(2.0, 10.0), swell=0.4, pitch=-14.0, reach=0.8, glow=0.6),
    # Struck: rocked back, legs up.
    "hurt": _pose(body=(-3.0, 12.0), swell=0.2, pitch=24.0, spread=0.6, glow=0.1),
    # The burst's stamp: squashed down, legs splayed wide, the sac blazing.
    "slam": _pose(body=(-2.0, 9.0), swell=0.9, pitch=0.0, spread=1.0, glow=1.0),
}


def _R(d: np.ndarray) -> np.ndarray:
    return rot(0.0, 0.0, math.degrees(math.atan2(d[1], d[0])))


def model(p: dict[str, Any]) -> Node:
    bx, by = p["body"]
    c = v((bx, by, 0.0))
    sp = dir2(float(p["pitch"]))
    dead = float(p.get("dead", 0.0)) >= 0.5
    swell = float(p.get("swell", 0.0))
    reach = float(p.get("reach", 0.0))
    spread = float(p.get("spread", 0.0))
    parts: list[Node] = []
    r = 8.0 + 2.6 * swell
    if dead:
        parts.append(Ellipsoid(FLAT, v((bx, 2.0, 0.0)), (r * 1.1, 2.4, r * 0.9), group="sac"))
    else:
        parts.append(Ellipsoid(SAC, c - sp * 1.5, (r, r * 0.86, r * 0.92), R=_R(sp), group="sac"))
        glow = float(p.get("glow", 0.0))
        parts.append(Ellipsoid(GLOW, c - sp * 2.0 + v((0.0, r * 0.25, r * 0.7)), (2.2 + 2.0 * glow, 1.6 + 1.6 * glow, 1.2),
                               group="glow"))
    # The head: a small armoured shield in front, with hooked mouthparts.
    head = c + sp * (r * 0.75 + 1.5) - v((0.0, 2.0, 0.0))
    parts.append(Ellipsoid(CHITIN, head, (4.0, 3.0, 4.4), R=_R(sp), group="head"))
    for z in (1.2, -1.2):
        tip = head + sp * (4.0 + 2.5 * reach) - v((0.0, 1.6 - reach, 0.0)) + v((0.0, 0.0, z))
        parts.append(cone(CHITIN, head + sp * 2.5 + v((0.0, 0.0, z)), tip, 1.0, 0.4, group="jaw"))
    # Eight short legs from under the sac, near pair in front reaching with `reach`.
    for i in range(LEGS):
        t = (i + 0.5) / LEGS
        along = (t - 0.5) * r * 1.3
        for z in (1.0, -1.0):
            root = c + sp * along - v((0.0, r * 0.45, 0.0)) + v((0.0, 0.0, z * r * 0.55))
            out = 4.5 + 3.0 * spread + (3.0 * reach if i == LEGS - 1 else 0.0)
            knee = root + v((along * 0.25, 3.0, z * out))
            foot = v((root[0] + along * 0.35 + (2.5 * reach if i == LEGS - 1 else 0.0), 0.8 if not dead else 0.6,
                      z * (out + 1.5)))
            grp = "leg_n" if z > 0 else "leg_f"
            parts.append(cone(CHITIN, root, knee, 1.2, 0.9, group=grp))
            parts.append(cone(CHITIN, knee, foot, 0.9, 0.5, group=grp))
    node: Node = Union(*parts)
    roll = float(p.get("roll", 0.0))
    if roll:
        node = Moved(node, (0.0, 0.0, 0.0), rot(roll, 0.0, 0.0))
    return Scaled(node, SIZE)


def camera() -> Camera:
    return Camera(S, S, face="left", cx=CAM_CX, cy=CAM_CY)


def _veins(fr: Frame, cam: Camera, p: dict[str, Any]) -> None:
    if float(p.get("dead", 0.0)) >= 0.5:
        return
    bx, by = p["body"]
    r = 8.0 + 2.6 * float(p.get("swell", 0.0))
    rows = ["a...", ".a..", ".aa.", "...a"]
    for dx, dy in ((-2.0, 2.5), (2.5, -1.0)):
        pt = v((bx + dx, by + dy, r * 0.85)) * SIZE
        decal(fr, cam, pt, rows, {"a": (VEIN, 2)}, ("sac",), tol=4.0, group="vein")


def render_frame(p: dict[str, Any], cam: Camera | None = None) -> Frame:
    cam = cam or camera()
    fr = render(model(p), cam)
    _veins(fr, cam, p)
    lift_off_last_row(fr)
    return fr


def finish_frame(fr: Frame) -> np.ndarray:
    return finish(fr, keep=("glow", "vein"))


def render_cell(p: dict[str, Any]) -> np.ndarray:
    return finish_frame(render_frame(p))


PORTRAIT_POSE = pose_with(POSES["idle"], swell=0.6, glow=0.8)


def render_portrait(p: dict[str, Any]) -> np.ndarray:
    bx, by = p["body"]
    cam = framed(PORTRAIT, 0.55, v((bx + 4.0, by, 0.0)) * SIZE, (24.0, 26.0))
    fr = render(model(p), cam)
    _veins(fr, cam, p)
    return finish_frame(fr)


IDLE = POSES["idle"]
BREATH = pose_with(IDLE, swell=0.45, glow=0.45, body=(-2.0, 11.4))
SHIVER = pose_with(POSES["windup"], swell=0.9, body=(-3.0, 12.0), pitch=-2.0)
STAGGER = pose_with(POSES["hurt"], pitch=32.0, spread=0.8)
DEATH = [pose_with(POSES["slam"], swell=1.0, glow=1.0),
         pose_with(IDLE, body=(-2.0, 7.0), swell=0.0, pitch=-10.0, spread=1.0, glow=0.0),
         pose_with(IDLE, dead=1.0, spread=1.0, pitch=-20.0, body=(-2.0, 5.0)),
         pose_with(IDLE, dead=1.0, spread=1.2, pitch=-24.0, body=(-2.0, 4.0))]
WALK = [pose_with(IDLE, body=(-2.0 + dx, 11.0 + dy), spread=s) for dx, dy, s in
        ((0.0, 0.0, 0.2), (0.5, 0.6, 0.0), (1.0, 0.0, 0.2), (0.5, 0.6, 0.0))]
CHASE = [pose_with(IDLE, body=(-1.0 + dx, 11.0 + dy), spread=s, reach=0.4, glow=0.6) for dx, dy, s in
         ((0.0, 0.0, 0.3), (1.0, 0.8, 0.0), (2.0, 0.0, 0.3), (1.0, 0.8, 0.0))]

CLIPS = standard_clips(POSES, BREATH, SHIVER, STAGGER, DEATH, WALK, CHASE)


def build(ctx) -> None:
    build_enemy(ctx, ID, S, POSES, CLIPS, render_frame, finish_frame, render_cell,
                render_portrait(PORTRAIT_POSE), IDLE_CYCLE_PERCENT)
