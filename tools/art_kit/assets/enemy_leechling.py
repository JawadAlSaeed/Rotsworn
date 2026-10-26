"""Leechling: a leech as long as a man's arm, one of the Leech Queen's brood (phase 26, card #323,
DESIGN.md 8.23). It inches along in loops and bites with a round sucker mouth ringed with teeth.

Silhouette: a fat ringed body, thick at the back, narrowing to a blunt head that rears up; a round
sucker mouth on the front end. Colour areas: the Queen's wet dark olive rings, a pale ochre belly,
a dark mouth with bone teeth, two violet eye spots that flare on its tell.

Built straight from a pose dict (kit.monster), with the Queen's tail parts. Model units are pixels
before SIZE; x forward (it faces right in the model, the camera mirrors it), y up, z toward the
viewer.

Pose keys:
    head     (x, y) of the head's front end
    tail_x   x of the tail's end
    arch     0..1 how high the middle loops up (inching)
    gape     0..1 how wide the sucker opens
    glow     0..1 eye glow (1 = the tell)
    dead     1 = limp and dark
"""
from __future__ import annotations

from typing import Any

import numpy as np

from assets.enemy_leech_queen import BELLY, GLOW, GLOW_DEAD, LEECH, MOUTH, RING, TEETH, spline
from kit.beast import build_enemy, decal, finish, framed, lift_off_last_row, mix, pose_with, unit, v
from kit.monster import Scaled, standard_clips
from kit.render import Camera, Frame, render
from kit.sdf import Ellipsoid, Node, Union, basis
from kit.specs import ENEMY_FRAME, PORTRAIT

ID = "leechling"
S = ENEMY_FRAME[ID]
SIZE = 1.25
CAM_CX = -2.0
CAM_CY = 1.4
# Mirrors idle_cycle_percent in data/enemies/leechling.tres.
IDLE_CYCLE_PERCENT = 80

# Body radius from the tail's end (0) to the head (1).
BODY_R = ((0.0, 2.6), (0.3, 4.4), (0.65, 4.0), (0.9, 3.0), (1.0, 2.6))


def _r(f: float) -> float:
    for (f0, r0), (f1, r1) in zip(BODY_R, BODY_R[1:]):
        if f <= f1:
            return r0 + (r1 - r0) * (f - f0) / max(f1 - f0, 1e-6)
    return BODY_R[-1][1]


def _pose(**kw: Any) -> dict[str, Any]:
    p: dict[str, Any] = dict(head=(10.0, 7.0), tail_x=-14.0, arch=0.15, gape=0.2, glow=0.3, dead=0.0)
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    "idle": _pose(),
    # The tell: bunched up, the head reared high, the sucker wide open.
    "windup": _pose(head=(5.0, 16.0), tail_x=-11.0, arch=0.9, gape=1.0, glow=1.0),
    # The lunge: stretched out flat and long.
    "lunge": _pose(head=(17.0, 6.0), tail_x=-13.0, arch=0.0, gape=1.0, glow=0.7),
    # The bite: the head clamped down in front.
    "contact": _pose(head=(18.0, 4.0), tail_x=-11.0, arch=0.35, gape=0.6, glow=0.7),
    # Struck: curled back, the head flung up and back.
    "hurt": _pose(head=(2.0, 13.0), tail_x=-15.0, arch=0.6, gape=0.0, glow=0.1),
    # A thrash: the body slapped down flat, the head low.
    "slam": _pose(head=(14.0, 3.5), tail_x=-15.0, arch=0.0, gape=0.5, glow=0.9),
}


def path(p: dict[str, Any]) -> list[np.ndarray]:
    hx, hy = p["head"]
    tx = float(p["tail_x"])
    arch = float(p["arch"])
    mid_x = (hx + tx) * 0.5 - 1.0
    return [v((tx, 2.0, 0.0)), v((tx * 0.5 + mid_x * 0.5, 3.6 + 5.0 * arch, 0.0)),
            v((mid_x + 3.0, 4.0 + 7.0 * arch, 0.0)), v((hx - 3.5, max(hy - 1.0, 3.0), 0.0)), v((hx, hy, 0.0))]


def model(p: dict[str, Any]) -> Node:
    dead = float(p.get("dead", 0.0)) >= 0.5
    segs = spline(path(p), 2.0)
    n = len(segs)
    parts: list[Node] = []
    for i, (c, d) in enumerate(segs):
        r = _r(i / max(n - 1, 1))
        parts.append(Ellipsoid(RING if i % 2 else LEECH, c, (1.5, r, r * 1.1), R=basis(d), group="body"))
        if 0 < i < n - 1:
            parts.append(Ellipsoid(BELLY, c - v((0.0, r * 0.45, 0.0)), (1.3, r * 0.55, r * 0.9), R=basis(d),
                                   group="body"))
    head, d = segs[-1]
    gape = float(p.get("gape", 0.0))
    parts.append(Ellipsoid(LEECH, head + d * 0.6, (1.4, 2.4 + 0.9 * gape, 2.6 + 0.9 * gape), R=basis(d), group="head"))
    if not dead:
        parts.append(Ellipsoid(MOUTH, head + d * 1.5, (0.6, 1.4 + 1.0 * gape, 1.6 + 1.0 * gape), R=basis(d),
                               group="mouth"))
    return Scaled(Union(*parts), SIZE)


def camera() -> Camera:
    return Camera(S, S, face="left", cx=CAM_CX, cy=CAM_CY)


def _eyes(fr: Frame, cam: Camera, p: dict[str, Any], big: bool = False) -> None:
    segs = spline(path(p), 2.0)
    head, d = segs[-1]
    up = unit(np.cross(v((0.0, 0.0, 1.0)), d))
    dead = float(p.get("dead", 0.0)) >= 0.5
    hot = float(p.get("glow", 0.0)) >= 0.9
    mat = GLOW_DEAD if dead else GLOW
    rows = ["aa"] if (hot or big) else ["b"]
    for z in (1.4, -1.4):
        pt = (head - d * 1.0 + up * 2.2 + v((0.0, 0.0, z))) * SIZE
        decal(fr, cam, pt, rows, {"a": (mat, 3 if not dead else 1), "b": (mat, 2 if not dead else 1)},
              ("head", "body"), tol=3.0, group="eye")
    if not dead and float(p.get("gape", 0.0)) >= 0.5:
        pt = (head + d * 1.9) * SIZE
        decal(fr, cam, pt, ["t.t", "...", "t.t"], {"t": (TEETH, 3)}, ("mouth", "head"), tol=3.0, group="teeth")


def render_frame(p: dict[str, Any], cam: Camera | None = None) -> Frame:
    cam = cam or camera()
    fr = render(model(p), cam)
    _eyes(fr, cam, p)
    lift_off_last_row(fr)
    return fr


def finish_frame(fr: Frame) -> np.ndarray:
    return finish(fr, keep=("eye", "teeth", "mouth"))


def render_cell(p: dict[str, Any]) -> np.ndarray:
    return finish_frame(render_frame(p))


PORTRAIT_POSE = pose_with(POSES["windup"], gape=0.8, glow=0.8)


def render_portrait(p: dict[str, Any]) -> np.ndarray:
    hx, hy = p["head"]
    cam = framed(PORTRAIT, 0.45, v((hx - 4.0, hy - 4.0, 0.0)) * SIZE, (22.0, 26.0))
    fr = render(model(p), cam)
    _eyes(fr, cam, p, big=True)
    return finish_frame(fr)


IDLE = POSES["idle"]
BREATH = pose_with(IDLE, head=(10.5, 7.8), arch=0.25, gape=0.3, glow=0.45)
SHIVER = pose_with(POSES["windup"], head=(5.5, 16.5), gape=0.85)
STAGGER = pose_with(POSES["hurt"], head=(0.0, 14.0), arch=0.75)
DEATH = [pose_with(POSES["hurt"], head=(1.0, 15.0), gape=1.0, glow=0.6),
         pose_with(IDLE, head=(8.0, 6.0), arch=0.4, gape=0.0, glow=0.1),
         pose_with(IDLE, head=(11.0, 3.2), tail_x=-15.0, arch=0.05, gape=0.0, glow=0.0, dead=1.0),
         pose_with(IDLE, head=(12.0, 2.8), tail_x=-16.0, arch=0.0, gape=0.0, glow=0.0, dead=1.0)]
# Inching: the back end draws up into a loop, then the front stretches out.
WALK = [pose_with(IDLE, head=(10.0, 7.0), tail_x=-14.0, arch=0.1),
        pose_with(IDLE, head=(10.0, 6.5), tail_x=-9.0, arch=0.7),
        pose_with(IDLE, head=(14.0, 7.0), tail_x=-8.0, arch=0.45),
        pose_with(IDLE, head=(15.0, 6.0), tail_x=-12.0, arch=0.1)]
CHASE = [pose_with(w, gape=0.6, glow=0.6, arch=float(w["arch"]) * 1.2) for w in WALK]

CLIPS = standard_clips(POSES, BREATH, SHIVER, STAGGER, DEATH, WALK, CHASE,
                       coil_2=mix(IDLE, POSES["windup"], 0.75, gape=0.8))


def build(ctx) -> None:
    build_enemy(ctx, ID, S, POSES, CLIPS, render_frame, finish_frame, render_cell,
                render_portrait(PORTRAIT_POSE), IDLE_CYCLE_PERCENT)
