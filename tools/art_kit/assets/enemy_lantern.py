"""Marsh Lantern: a bog wisp trapped in a rusted iron lantern that drifts over the mire on its own,
spitting sparks of lightning (phase 19, card #258). A floater: it never touches the floor.

Silhouette: a tall six-sided lantern cage (a domed cap with a hook, rusted bars, a heavy base) with
a crackling yellow-white light inside it, two eye-glints in the light, and long strands of dark
marsh weed hanging from the base. Colour areas: rusted iron, the cyan-white core light, dark green
weed with a few pale reed ends.

Built straight from a pose dict (kit.monster). Model units are pixels before SIZE; x forward (it
faces right in the model, the camera mirrors it), y up, z toward the viewer.

Pose keys:
    c        (x, y) of the lantern's centre
    tilt     how far the lantern leans, degrees (+ = top forward)
    flare    0..1 how big and bright the light is (1 = the tell, a cast)
    sway     degrees the weed swings back (+ = trails behind)
    eyes     1 = the eye-glints show, 0 = shut (hurt)
    dead     1 = the light has gone out
"""
from __future__ import annotations

import math
from typing import Any

import numpy as np

from kit.beast import build_enemy, cone, decal, dir2, finish, framed, pose_with, unit, v
from kit.monster import Scaled, standard_clips
from kit.palette import M, Material
from kit.render import Camera, Frame, render
from kit.sdf import Ellipsoid, Node, Sphere, Union, rot
from kit.specs import ENEMY_FRAME, PORTRAIT

ID = "marsh_lantern"
S = ENEMY_FRAME[ID]
SIZE = 1.15
CAM_CX = 0.0
CAM_CY = -0.5
IDLE_CYCLE_PERCENT = 90

IRON = Material.make("lantern_iron", "#6a5248", wrap=0.3, ao=0.5, spec=0.4, spec_power=10.0)
CAP = Material.make("lantern_cap", "#4e3c38", wrap=0.3, ao=0.5)
LIGHT = Material.make("lantern_light", "#fff4b0", below=2, above=1, emissive=True)
HALO = M["glow_cyan"]
DEAD = Material.make("lantern_dead", "#3a3a40", below=1, above=1, wrap=0.3)
WEED = Material.make("lantern_weed", "#3d4a30", wrap=0.35, ao=0.5)
REED = Material.make("lantern_reed", "#8a8a5a", wrap=0.4, ao=0.4)

HALF_H = 9.0
RADIUS = 6.0
BARS = 6


def _pose(**kw: Any) -> dict[str, Any]:
    p: dict[str, Any] = dict(c=(0.0, 30.0), tilt=0.0, flare=0.4, sway=10.0, eyes=1.0, dead=0.0)
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    # Hanging still in the air, the light flickering, the weed hanging down.
    "idle": _pose(),
    # The tell: drawn back and up, the light swelling white-hot.
    "windup": _pose(c=(-3.0, 33.0), tilt=-14.0, flare=1.0, sway=-8.0),
    # Lurching forward through the air.
    "lunge": _pose(c=(5.0, 29.0), tilt=22.0, flare=0.8, sway=35.0),
    # Swinging at the end of the lunge, the light bursting.
    "contact": _pose(c=(6.0, 28.0), tilt=30.0, flare=0.9, sway=40.0),
    # Knocked back, swinging hard, the light dim.
    "hurt": _pose(c=(-4.0, 31.0), tilt=-26.0, flare=0.1, sway=-25.0, eyes=0.0),
    # The cast: thrust forward, the light at its brightest.
    "slam": _pose(c=(3.0, 30.0), tilt=12.0, flare=1.0, sway=20.0),
}


def model(p: dict[str, Any]) -> Node:
    cx, cy = p["c"]
    c = v((cx, cy, 0.0))
    R = rot(0.0, 0.0, -float(p["tilt"]))
    up = R @ v((0.0, 1.0, 0.0))
    dead = float(p.get("dead", 0.0)) >= 0.5
    flare = 0.0 if dead else float(p.get("flare", 0.0))
    parts: list[Node] = []
    top = c + up * HALF_H
    base = c - up * HALF_H
    # The cage: a domed cap with a ring hook, six bars, a heavy base plate.
    parts.append(Ellipsoid(CAP, top + up * 1.2, (RADIUS + 1.0, 2.8, RADIUS + 1.0), R=R, group="cage"))
    parts.append(cone(CAP, top + up * 3.4, top + up * 6.0, 1.0, 0.6, group="cage"))
    parts.append(Ellipsoid(IRON, top + up * 6.6, (1.6, 1.6, 0.6), group="hook"))
    parts.append(Ellipsoid(CAP, base - up * 0.8, (RADIUS + 0.8, 2.0, RADIUS + 0.8), R=R, group="cage"))
    for k in range(BARS):
        a = math.tau * (k + 0.5) / BARS
        off = R @ v((math.cos(a) * RADIUS, 0.0, math.sin(a) * RADIUS))
        parts.append(cone(IRON, top + off, base + off, 0.8, 0.8, group="cage"))
    # The light inside, swelling with the flare, in a cyan halo.
    if dead:
        parts.append(Sphere(DEAD, c, 2.4, group="core"))
    else:
        parts.append(Ellipsoid(HALO, c, (3.4 + 1.6 * flare, 4.6 + 2.0 * flare, 3.4 + 1.6 * flare), group="halo"))
        parts.append(Sphere(LIGHT, c + v((0.0, 0.0, 1.2)), 2.2 + 1.2 * flare, group="core"))
    # Weed strands hanging from the base, swinging back with `sway`.
    sway = float(p.get("sway", 0.0))
    for i, (zo, length, xo) in enumerate(((2.8, 13.0, 1.5), (-2.5, 11.0, -1.0), (0.4, 15.0, 0.0), (4.4, 9.0, -2.5))):
        start = base - up * 1.5 + R @ v((xo, 0.0, zo))
        d = dir2(-90.0 - sway * (0.7 + 0.1 * i))
        mid = start + d * length * 0.55
        end = mid + dir2(-90.0 - sway * (1.0 + 0.1 * i)) * length * 0.45
        parts.append(cone(WEED, start, mid, 1.3, 0.9, group="weed"))
        parts.append(cone(WEED if i % 2 else REED, mid, end, 0.9, 0.4, group="weed"))
    return Scaled(Union(*parts), SIZE)


def camera() -> Camera:
    return Camera(S, S, face="left", cx=CAM_CX, cy=CAM_CY)


def _eyes(fr: Frame, cam: Camera, p: dict[str, Any], big: bool = False) -> None:
    if float(p.get("eyes", 1.0)) < 0.5 or float(p.get("dead", 0.0)) >= 0.5:
        return
    cx, cy = p["c"]
    rows = ["a.a"] if not big else ["a..a"]
    pt = v((cx + 1.0, cy + 0.6, 4.0)) * SIZE
    decal(fr, cam, pt, rows, {"a": (HALO, 0)}, ("core", "halo"), tol=6.0, group="eye")


def render_frame(p: dict[str, Any], cam: Camera | None = None) -> Frame:
    cam = cam or camera()
    fr = render(model(p), cam)
    _eyes(fr, cam, p)
    return fr


def finish_frame(fr: Frame) -> np.ndarray:
    return finish(fr, keep=("eye", "core", "halo"))


def render_cell(p: dict[str, Any]) -> np.ndarray:
    return finish_frame(render_frame(p))


PORTRAIT_POSE = pose_with(POSES["idle"], flare=0.7)


def render_portrait(p: dict[str, Any]) -> np.ndarray:
    cx, cy = p["c"]
    cam = framed(PORTRAIT, 0.62, v((cx, cy + 1.0, 0.0)) * SIZE, (24.0, 24.0))
    fr = render(model(p), cam)
    _eyes(fr, cam, p, big=True)
    return finish_frame(fr)


IDLE = POSES["idle"]
BREATH = pose_with(IDLE, c=(0.0, 31.5), flare=0.6, sway=4.0)
SHIVER = pose_with(POSES["windup"], c=(-3.5, 33.5), tilt=-18.0, sway=-12.0)
STAGGER = pose_with(POSES["hurt"], c=(-5.0, 30.0), tilt=-34.0, sway=-35.0)
DEATH = [pose_with(POSES["hurt"], flare=0.6),
         pose_with(IDLE, c=(0.0, 24.0), tilt=-20.0, flare=0.0, dead=1.0, eyes=0.0, sway=-20.0),
         pose_with(IDLE, c=(0.0, 16.0), tilt=30.0, dead=1.0, eyes=0.0, sway=10.0),
         pose_with(IDLE, c=(0.0, 11.0), tilt=70.0, dead=1.0, eyes=0.0, sway=60.0)]
WALK = [pose_with(IDLE, c=(0.0, 30.0 + dy), tilt=t, sway=s) for dy, t, s in ((0.0, 6.0, 20.0), (1.2, 8.0, 26.0),
                                                                             (0.0, 6.0, 20.0), (-1.2, 4.0, 14.0))]
CHASE = [pose_with(IDLE, c=(1.0, 29.0 + dy), tilt=t, sway=s, flare=0.7) for dy, t, s in
         ((0.0, 16.0, 34.0), (1.4, 20.0, 40.0), (0.0, 16.0, 34.0), (-1.4, 12.0, 28.0))]

CLIPS = standard_clips(POSES, BREATH, SHIVER, STAGGER, DEATH, WALK, CHASE, throw=True)


def build(ctx) -> None:
    build_enemy(ctx, ID, S, POSES, CLIPS, render_frame, finish_frame, render_cell,
                render_portrait(PORTRAIT_POSE), IDLE_CYCLE_PERCENT, floats=True)
