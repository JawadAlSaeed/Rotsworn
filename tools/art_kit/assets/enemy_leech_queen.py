"""The Leech Queen, act 2's boss (phase 26, card #323, DESIGN.md 8.23): enemy sheet (108x108 cells,
facing left), clips and portrait.

A pale, gaunt crowned queen whose body ends at the waist in a giant segmented leech tail, coiled in a
pool of black water. Silhouette: a thin upright torso on top of a thick ringed tail that drops into
the water and coils behind her, long dark hair falling down her back, a crown of twisted roots, long
thin arms with clawed fingers. Colour areas: pale violet-grey skin, near-black hair, the tail's wet
dark olive rings (the tail's skin grows up over her chest like a gown's bodice), a worn-gold band in
the root crown, the black pool, and a violet glow (eyes, crown, the glands along the coil) that
flares on her tell. About 85 px tall (heroes are about 45 px), the Husk Lord's and Hollow King's size
class.

Built straight from a pose dict (kit.monster). Model units are pixels before SIZE; x forward (she
faces right in the model, the camera mirrors her), y up, z toward the viewer.

Pose keys:
    body     (x, y) of the waist, where the torso meets the tail
    lean     torso lean, degrees (+ = forward)
    head     head tilt, degrees (+ = chin up)
    an, bn   near arm: shoulder angle (0 forward, 90 up, -90 down) and elbow bend
    af, bf   far arm
    claw     0..1 how far the fingers spread
    jaw      0..1 how far the mouth gapes (the bite)
    tail     0..1 the tail's end swept round the near side to the front (the sweep)
    wave     0..1 the black water rising in a wave in front of her (the ground waves)
    hair     x offset of the hair's ends (negative = trailing behind)
    glow     0..1 eyes, crown and glands (1 = the tell)
    eyes     1 = open, 0 = shut
    crown    degrees the crown is knocked askew
    dead     1 = the glow has gone out
"""
from __future__ import annotations

import math
from typing import Any

import numpy as np

from kit.beast import build_enemy, cone, decal, dir2, finish, framed, lift_off_last_row, mix, pose_with, unit, v
from kit.monster import Scaled, limb, standard_clips
from kit.palette import M, Material
from kit.render import Camera, Frame, render
from kit.sdf import Box, Ellipsoid, Intersect, Node, SmoothUnion, Sphere, Union, basis, rot
from kit.specs import ENEMY_FRAME, PORTRAIT

ID = "leech_queen"
S = ENEMY_FRAME[ID]
SIZE = 1.0
CAM_CX = -3.0
CAM_CY = -3.0
# Mirrors idle_cycle_percent in data/enemies/leech_queen.tres (a slow, swaying breath).
IDLE_CYCLE_PERCENT = 125

SKIN = Material.make("queen_skin", "#b3a7b0", wrap=0.45, ao=0.5)
HAIR = Material.make("queen_hair", "#2e2630", step_l=0.07, wrap=0.3)
LEECH = Material.make("queen_leech", "#3f3a30", wrap=0.3, ao=0.5, spec=0.7, spec_power=10.0)
RING = Material.make("queen_ring", "#4f4634", wrap=0.3, ao=0.5, spec=0.7, spec_power=10.0)
BELLY = Material.make("queen_belly", "#6a5a3c", wrap=0.35, ao=0.5)
WATER = Material.make("black_water", "#262a31", below=1, above=2, wrap=0.2, spec=1.0, spec_power=8.0)
ROOT = M["dead_wood"]
GOLD = M["gold_worn"]
GLOW = M["glow_violet"]
GLOW_DEAD = Material.make("queen_glow_dead", "#4a3f55", below=1, above=1, wrap=0.3)
MOUTH = Material.make("queen_mouth", "#3a2232", below=1, above=1)
TEETH = M["bone"]

SPINE, NECK = 16.5, 3.5
ARM1, ARM2 = 12.0, 11.0
SHOULDER_Z = 7.0
POOL = (33.0, 20.0)


def _pose(**kw: Any) -> dict[str, Any]:
    p: dict[str, Any] = dict(
        body=(4.0, 31.0), lean=6.0, head=-6.0, an=-48.0, bn=70.0, af=-62.0, bf=58.0, claw=0.3,
        jaw=0.0, tail=0.0, wave=0.0, hair=-1.0, glow=0.35, eyes=1.0, crown=0.0, dead=0.0,
    )
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    # Upright on her coil, one clawed hand raised as if beckoning, the other low.
    "idle": _pose(),
    # The tell: reared up and back on the tail, arms flung up and wide, mouth open, glow blazing.
    "windup": _pose(body=(0.0, 37.0), lean=-14.0, head=14.0, an=62.0, bn=38.0, af=48.0, bf=42.0, claw=1.0,
                    jaw=0.6, hair=-5.0, glow=1.0),
    # The strike: thrown forward off the coil, both claws reaching, mouth wide.
    "lunge": _pose(body=(13.0, 30.0), lean=42.0, head=-8.0, an=8.0, bn=-8.0, af=-2.0, bf=-4.0, claw=1.0,
                   jaw=1.0, hair=-7.0, glow=0.7),
    # The bite lands: bent right over, the mouth clamped on.
    "contact": _pose(body=(16.0, 27.0), lean=58.0, head=-22.0, an=-18.0, bn=12.0, af=-28.0, bf=20.0, claw=0.8,
                     jaw=0.75, hair=-3.0, glow=0.8),
    # Struck: rocked back, head thrown up, eyes shut.
    "hurt": _pose(body=(-1.0, 32.0), lean=-20.0, head=26.0, an=-112.0, bn=24.0, af=-122.0, bf=18.0, claw=0.2,
                  jaw=0.4, hair=2.0, eyes=0.0, glow=0.2, crown=6.0),
    # The tail slaps the water: hunched low, the tail end whipped round to the front, the pool
    # rising in a wave.
    "slam": _pose(body=(3.0, 28.0), lean=24.0, head=-10.0, an=-38.0, bn=16.0, af=-20.0, bf=32.0, claw=0.6,
                  jaw=0.3, tail=0.55, wave=1.0, hair=-4.0, glow=1.0),
}


def skeleton(p: dict[str, Any]) -> dict[str, Any]:
    bx, by = p["body"]
    waist = v((bx, by, 0.0))
    sp = dir2(90.0 - float(p["lean"]))
    fwd = unit(np.cross(sp, v((0.0, 0.0, 1.0))))
    chest = waist + sp * SPINE
    hd = dir2(90.0 - float(p["lean"]) * 0.7 + float(p["head"]))
    hf = unit(np.cross(hd, v((0.0, 0.0, 1.0))))
    head = chest + sp * NECK + hd * 5.0 + fwd * 0.8
    return {"waist": waist, "sp": sp, "fwd": fwd, "chest": chest, "head": head, "hd": hd, "hf": hf}


def spline(pts: list[np.ndarray], step: float) -> list[tuple[np.ndarray, np.ndarray]]:
    """Points every `step` units along a Catmull-Rom curve through `pts`, with the tangent."""
    out: list[tuple[np.ndarray, np.ndarray]] = []
    ext = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    carry = 0.0
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        n = 24
        prev = p1
        for k in range(1, n + 1):
            t = k / n
            q = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                       + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
            seg = float(np.linalg.norm(q - prev))
            carry += seg
            if carry >= step or not out:
                out.append((q, unit(q - prev)))
                carry = 0.0
            prev = q
    return out


# Tail radius along its length (share of the length -> radius).
TAIL_R = ((0.0, 6.2), (0.12, 7.6), (0.3, 8.6), (0.5, 8.0), (0.68, 6.6), (0.85, 4.2), (1.0, 1.6))
# Everything of the tail below this height is under the black water.
WATERLINE = 1.6


def _radius(f: float) -> float:
    for (f0, r0), (f1, r1) in zip(TAIL_R, TAIL_R[1:]):
        if f <= f1:
            return r0 + (r1 - r0) * (f - f0) / max(f1 - f0, 1e-6)
    return TAIL_R[-1][1]


def tail_points(p: dict[str, Any]) -> list[np.ndarray]:
    """The tail's guide points: down from the waist into the water in front, under the water, up
    in a great arching hump behind her, down again, then the end: curling up out of the water
    behind (tail 0) or whipped round the near side to the front (tail 1)."""
    bx, by = p["body"]
    t = float(p.get("tail", 0.0))
    hump = float(p.get("hump", 1.0))
    sk = skeleton(p)
    base = bx * 0.3
    pts = [sk["waist"] + sk["sp"] * 2.0, sk["waist"] - sk["sp"] * 8.0 + v((-0.5, 0.0, 0.5)),
           v((base + 0.0, 9.0, 2.5)), v((base - 6.0, 0.0, 3.0)), v((base - 15.0, 0.0, 1.0)),
           v((base - 19.0, 8.0 + 4.0 * hump, 0.0)), v((base - 24.5, 12.0 + 9.0 * hump, -1.0)),
           v((base - 30.0, 8.0 + 4.0 * hump, -2.0)), v((base - 33.5, 0.0, -2.0))]
    rest = [v((base - 38.0, -1.0, -1.0)), v((base - 41.5, 5.0, 0.0)), v((base - 42.5, 10.0, 1.0))]
    swept = [v((base - 30.0, 4.0, 14.0)), v((bx - 4.0, 6.0, 19.0)), v((bx + 21.0, 6.5, 12.0))]
    pts += [a * (1 - t) + b * t for a, b in zip(rest, swept)]
    return pts


def _tail(p: dict[str, Any], dead: bool) -> tuple[Node, list[np.ndarray]]:
    segs = spline(tail_points(p), 3.4)
    parts: list[Node] = []
    tops: list[np.ndarray] = []
    n = len(segs)
    for i, (c, d) in enumerate(segs):
        r = _radius(i / max(n - 1, 1))
        if c[1] + r < WATERLINE - 0.5:
            continue
        mat = RING if i % 2 else LEECH
        parts.append(Ellipsoid(mat, c, (2.5, r, r * 1.05), R=basis(d), group="tail"))
        if i % 4 == 1 and 0.42 < i / n < 0.75 and c[1] > 6.0:
            tops.append(c + v((0.0, r * 0.9, 0.0)))
    # The pale underside where the tail rises out of the water toward her waist.
    for i in range(1, min(6, n)):
        c, d = segs[i]
        r = _radius(i / max(n - 1, 1))
        parts.append(Ellipsoid(BELLY, c + v((r * 0.32, 0.0, 0.0)), (2.1, r * 0.8, r * 0.78), R=basis(d), group="tail"))
    above = Box(WATER, v((0.0, WATERLINE + 60.0, 0.0)), (300.0, 60.0, 300.0))
    return Intersect(Union(*parts), above), tops


def _arm(sk: dict[str, Any], a: float, b: float, z: float, claw: float, group: str) -> list[Node]:
    sh = sk["chest"] - sk["sp"] * 1.0 + v((0.0, 0.0, z))
    elbow, hand = limb(sh, a, b, ARM1, ARM2)
    fore = unit(hand - elbow)
    parts: list[Node] = [cone(SKIN, sh, elbow, 2.0, 1.6, group=group), cone(SKIN, elbow, hand, 1.6, 1.2, group=group),
                         Ellipsoid(SKIN, hand + fore * 0.8, (1.8, 1.3, 1.5), R=basis(fore), group=group)]
    up = unit(np.cross(v((0.0, 0.0, 1.0)), fore))
    for k in (-1.0, 0.0, 1.0):
        spread = 18.0 * k * (0.4 + claw)
        d = unit(fore * math.cos(math.radians(spread)) + up * math.sin(math.radians(spread)) * 0.8
                 - up * 0.35 * (1.0 - claw))
        base = hand + fore * 1.8 + v((0.0, 0.0, k * 0.6))
        parts.append(cone(SKIN, base, base + d * 4.6, 0.55, 0.3, group=group + "_claw", thin=True))
    return parts


def _crown(sk: dict[str, Any], tilt: float, dead: bool) -> list[Node]:
    """A crown of roots: a worn-gold band round the brow, twisted roots rising out of it."""
    hd, hf, head = sk["hd"], sk["hf"], sk["head"]
    R = basis(hd, hf) @ rot(0.0, 0.0, 0.0)
    tilt_R = rot(0.0, 0.0, tilt)
    base = head + hd * 3.4
    parts: list[Node] = []
    ring: list[Node] = []
    for i in range(8):
        a = math.radians(i * 45.0 + 10.0)
        off = tilt_R @ (hf * math.cos(a) * 3.9 + v((0.0, 0.0, 1.0)) * math.sin(a) * 3.7)
        ring.append(Sphere(GOLD, base + off, 1.0, group="crown"))
    parts.append(SmoothUnion(*ring, k=1.2))
    for i, (ang, h) in enumerate(((10.0, 7.5), (55.0, 6.0), (100.0, 8.5), (145.0, 6.5), (190.0, 7.0),
                                  (235.0, 5.5), (280.0, 8.0), (325.0, 6.0))):
        a = math.radians(ang)
        out = tilt_R @ (hf * math.cos(a) + v((0.0, 0.0, 1.0)) * math.sin(a))
        root = base + out * 3.6
        mid = root + tilt_R @ (hd * h * 0.55) + out * 1.4
        tip = mid + tilt_R @ (hd * h * 0.5) + out * 1.6 + tilt_R @ (hf * (0.8 if i % 2 else -0.8))
        parts.append(cone(ROOT, root, mid, 0.9, 0.65, group="crown_root", thin=True))
        parts.append(cone(ROOT, mid, tip, 0.65, 0.3, group="crown_root", thin=True))
    if not dead:
        parts.append(Sphere(GLOW, base + tilt_R @ (hf * 3.9 + hd * 0.4), 0.9, group="crown_gem"))
    return parts


def _hair(sk: dict[str, Any], sway: float) -> list[Node]:
    """Long dark hair falling down her back to below the waist, and two locks framing the face."""
    head, hd, hf, sp, fwd, waist = (sk[k] for k in ("head", "hd", "hf", "sp", "fwd", "waist"))
    crown = head + hd * 2.5 - hf * 1.0
    parts: list[Node] = [Ellipsoid(HAIR, head + hd * 1.0 - hf * 1.4, (4.4, 5.0, 4.6), R=basis(hf, hd), group="hair")]
    for z in (-3.0, 0.0, 3.0):
        nape = crown - hf * 3.0 + v((0.0, 0.0, z * 0.8))
        mid = sk["chest"] - fwd * 5.5 + v((sway * 0.5, 0.0, z))
        end = waist - fwd * 6.5 - sp * 3.0 + v((sway, 0.0, z * 1.1))
        parts.append(cone(HAIR, nape, mid, 3.0, 2.6, group="hair"))
        parts.append(cone(HAIR, mid, end, 2.6, 1.2, group="hair"))
    for z in (3.6, -3.6):
        temple = head + hf * 0.5 + hd * 1.0 + v((0.0, 0.0, z))
        low = sk["chest"] + fwd * 1.5 + sp * 1.0 + v((0.0, 0.0, z * 1.05))
        parts.append(cone(HAIR, temple, low, 1.4, 0.8, group="hair_lock"))
    return parts


def _pool(p: dict[str, Any]) -> list[Node]:
    bx, _ = p["body"]
    wave = float(p.get("wave", 0.0))
    parts: list[Node] = [Ellipsoid(WATER, v((bx * 0.3 - 15.0, 0.9, 1.0)), (POOL[0], 1.3, POOL[1]), group="water")]
    if wave > 0.0:
        parts.append(Ellipsoid(WATER, v((bx + 13.0 + 7.0 * wave, 1.2, 2.0)), (3.5 + wave, 1.0 + 3.5 * wave, 15.0),
                               group="water"))
    return parts


def model(p: dict[str, Any]) -> Node:
    sk = skeleton(p)
    waist, sp, fwd, chest, head, hd, hf = (sk[k] for k in ("waist", "sp", "fwd", "chest", "head", "hd", "hf"))
    dead = float(p.get("dead", 0.0)) >= 0.5
    parts: list[Node] = []
    tail, _ = _tail(p, dead)
    parts.append(tail)
    parts += _pool(p)
    # A thin, gaunt torso: the tail's dark skin grows up over the belly and chest like a bodice;
    # pale shoulders, collarbones and neck above it.
    torso = SmoothUnion(Ellipsoid(LEECH, waist + sp * 4.0, (5.4, 7.0, 5.6), R=basis(fwd, sp), group="body"),
                        Ellipsoid(LEECH, chest - sp * 3.5 + fwd * 0.6, (5.6, 5.4, 6.4), R=basis(fwd, sp), group="body"),
                        k=3.0)
    parts.append(torso)
    parts.append(Ellipsoid(SKIN, chest + sp * 0.2, (4.4, 3.0, 7.6), R=basis(fwd, sp), group="shoulders"))
    parts.append(cone(SKIN, chest + sp * 1.5, chest + sp * NECK + hd * 1.5, 1.8, 1.6, group="shoulders"))
    # The head: long and gaunt, a sharp chin; the jaw drops open for the bite.
    jaw = float(p.get("jaw", 0.0))
    parts.append(Ellipsoid(SKIN, head, (3.4, 4.4, 3.4), R=basis(hf, hd), group="head"))
    parts.append(Ellipsoid(SKIN, head + hf * 1.6 - hd * (2.6 + 1.6 * jaw), (2.2, 1.6, 2.4), R=basis(hf, hd), group="head"))
    parts += _hair(sk, float(p.get("hair", 0.0)))
    parts += _crown(sk, float(p.get("crown", 0.0)), dead)
    claw = float(p.get("claw", 0.0))
    parts += _arm(sk, float(p["af"]), float(p["bf"]), -SHOULDER_Z, claw, "arm_f")
    parts += _arm(sk, float(p["an"]), float(p["bn"]), SHOULDER_Z, claw, "arm_n")
    return Scaled(Union(*parts), SIZE)


def camera() -> Camera:
    return Camera(S, S, face="left", cx=CAM_CX, cy=CAM_CY)


def _face(fr: Frame, cam: Camera, p: dict[str, Any], big: bool = False) -> None:
    """Eyes (violet, hot on the tell), the gaping mouth and the glands along the coil."""
    sk = skeleton(p)
    dead = float(p.get("dead", 0.0)) >= 0.5
    hot = float(p.get("glow", 0.0)) >= 0.9
    eye_mat = GLOW_DEAD if dead else GLOW
    if float(p.get("eyes", 1.0)) >= 0.5:
        rows = (["aa", "ab"] if big else ["aa"]) if hot else (["ab"] if big else ["b"])
        for z in (1.5, -1.5):
            pt = (sk["head"] + sk["hf"] * 3.0 + sk["hd"] * 0.6 + v((0.0, 0.0, z))) * SIZE
            decal(fr, cam, pt, rows, {"a": (eye_mat, 3 if not dead else 1), "b": (eye_mat, 2 if not dead else 1)},
                  ("head",), tol=4.0, group="eye")
    jaw = float(p.get("jaw", 0.0))
    if jaw >= 0.3:
        rows = ["tmt", "mmm", "tmt"] if jaw >= 0.7 else ["mm"]
        pt = (sk["head"] + sk["hf"] * 3.0 - sk["hd"] * (2.0 + 1.0 * jaw)) * SIZE
        decal(fr, cam, pt, rows, {"m": (MOUTH, 0), "t": (TEETH, 3)}, ("head",), tol=4.0, group="mouth")
    if not dead:
        _, tops = _tail(p, dead)
        glow = float(p.get("glow", 0.0))
        rows = ["aa", "aa"] if glow >= 0.9 else (["a"] if glow >= 0.3 else [])
        for pt in tops:
            if rows:
                decal(fr, cam, pt * SIZE, rows, {"a": (GLOW, 2 if glow < 0.9 else 3)}, ("tail",), tol=5.0, group="gland")


def render_frame(p: dict[str, Any], cam: Camera | None = None) -> Frame:
    cam = cam or camera()
    fr = render(model(p), cam)
    _face(fr, cam, p)
    lift_off_last_row(fr)
    return fr


def finish_frame(fr: Frame) -> np.ndarray:
    return finish(fr, keep=("eye", "mouth", "gland", "claw", "crown_root", "crown_gem", "hair_lock"))


def render_cell(p: dict[str, Any]) -> np.ndarray:
    return finish_frame(render_frame(p))


PORTRAIT_POSE = pose_with(POSES["idle"], head=4.0, glow=0.8, jaw=0.35)


def render_portrait(p: dict[str, Any]) -> np.ndarray:
    sk = skeleton(p)
    cam = framed(PORTRAIT, 0.5, (sk["head"] + sk["hd"] * 1.5) * SIZE, (24.0, 22.0))
    fr = render(model(p), cam)
    _face(fr, cam, p, big=True)
    return finish_frame(fr)


IDLE = POSES["idle"]
BREATH = pose_with(IDLE, body=(4.0, 31.4), lean=5.0, head=-5.0, an=-44.0, bn=74.0, af=-60.0, hair=-2.0, glow=0.5)
SHIVER = pose_with(POSES["windup"], body=(-0.5, 37.5), an=66.0, af=52.0, head=17.0, hair=-6.0)
STAGGER = pose_with(POSES["hurt"], lean=-28.0, head=32.0, body=(-3.0, 31.0), crown=12.0)
DEATH = [
    pose_with(POSES["hurt"], head=34.0, jaw=1.0, glow=0.6, eyes=1.0, an=80.0, af=70.0, bn=30.0, bf=30.0),
    pose_with(IDLE, body=(6.0, 25.0), lean=48.0, head=-26.0, an=-90.0, bn=10.0, af=-95.0, bf=10.0, claw=0.0,
              glow=0.1, eyes=0.0, crown=18.0, hair=-2.0),
    pose_with(IDLE, body=(8.0, 17.0), lean=74.0, head=-34.0, an=-60.0, bn=-10.0, af=-70.0, bf=0.0, claw=0.0,
              glow=0.0, eyes=0.0, dead=1.0, crown=28.0, hair=1.0),
    pose_with(IDLE, body=(9.0, 10.0), lean=86.0, head=-30.0, an=-20.0, bn=-10.0, af=-30.0, bf=0.0, claw=0.0,
              glow=0.0, eyes=0.0, dead=1.0, crown=34.0, hair=2.0),
]
# She glides on the tail: the body bobs, the coil rolls, the tail's end swings a little.
WALK = [pose_with(IDLE, body=(4.0 + dx, 31.0 + dy), lean=8.0 + dl, tail=t, hair=h) for dx, dy, dl, t, h in
        ((0.0, 0.0, 0.0, 0.0, -2.0), (0.8, 0.8, 2.0, 0.08, -3.0), (1.6, 0.0, 4.0, 0.12, -4.0), (0.8, 0.8, 2.0, 0.06, -3.0))]
CHASE = [pose_with(IDLE, body=(6.0 + dx, 29.5 + dy), lean=24.0 + dl, an=-20.0, bn=30.0, af=-30.0, bf=20.0, claw=0.8,
                   tail=t, hair=-6.0 + h, glow=0.6) for dx, dy, dl, t, h in
         ((0.0, 0.0, 0.0, 0.0, 0.0), (1.2, 1.0, 3.0, 0.1, -1.0), (2.4, 0.0, 6.0, 0.16, -2.0), (1.2, 1.0, 3.0, 0.08, -1.0))]
# The phase-two rage (DESIGN.md 3.3): rearing up on the coil, arms wide, the scream.
RAGE = [mix(IDLE, POSES["windup"], 0.5),
        pose_with(POSES["windup"], body=(-1.0, 39.0), head=22.0, jaw=1.0, an=78.0, af=66.0, glow=1.0),
        pose_with(POSES["windup"], body=(-1.5, 40.0), head=26.0, jaw=1.0, an=84.0, af=70.0, claw=1.0, glow=1.0,
                  hair=-8.0),
        pose_with(POSES["windup"], body=(-1.0, 39.0), head=22.0, jaw=0.8, an=74.0, af=62.0, glow=1.0),
        mix(POSES["windup"], IDLE, 0.6)]
# The tail sweep (hits tagged anim "tail", DESIGN.md 5.5): she leans away while the tail's end
# swings round the near side and through the front.
TAIL_COIL = pose_with(IDLE, body=(1.0, 33.0), lean=-8.0, head=6.0, an=-20.0, bn=60.0, af=30.0, bf=40.0, tail=0.15,
                      claw=0.8, glow=1.0, hair=-3.0)
TAIL_LUNGE = pose_with(IDLE, body=(3.0, 31.0), lean=10.0, head=-4.0, an=-50.0, bn=20.0, af=-10.0, bf=30.0, tail=0.7,
                       claw=0.6, glow=0.8, hair=-5.0)
TAIL_CONTACT = pose_with(IDLE, body=(5.0, 30.0), lean=16.0, head=-8.0, an=-60.0, bn=10.0, af=-30.0, bf=20.0, tail=1.0,
                         claw=0.6, glow=0.8, hair=-6.0, wave=0.3)
# The spit: drawing back, the head thrown forward.
SPIT_COIL = pose_with(IDLE, body=(1.0, 34.0), lean=-10.0, head=18.0, jaw=0.5, glow=1.0, hair=-4.0)
SPIT = pose_with(IDLE, body=(7.0, 31.0), lean=30.0, head=-6.0, jaw=1.0, glow=0.8, an=-70.0, bn=30.0, af=-80.0,
                 bf=20.0, hair=-6.0)

CLIPS = standard_clips(POSES, BREATH, SHIVER, STAGGER, DEATH, WALK, CHASE)
CLIPS["rage"] = RAGE
CLIPS["tail_windup"] = [mix(IDLE, TAIL_COIL, 0.4), mix(IDLE, TAIL_COIL, 0.8), TAIL_COIL]
CLIPS["tail_lunge"] = [mix(TAIL_COIL, TAIL_LUNGE, 0.5), TAIL_LUNGE]
CLIPS["tail_contact"] = [TAIL_CONTACT, mix(TAIL_CONTACT, IDLE, 0.4), mix(TAIL_CONTACT, IDLE, 0.75)]
CLIPS["windup_shoot"] = [mix(IDLE, SPIT_COIL, 0.4), mix(IDLE, SPIT_COIL, 0.8), SPIT_COIL]
CLIPS["shoot"] = [SPIT, mix(SPIT, IDLE, 0.4), mix(SPIT, IDLE, 0.75), IDLE]


def build(ctx) -> None:
    build_enemy(ctx, ID, S, POSES, CLIPS, render_frame, finish_frame, render_cell,
                render_portrait(PORTRAIT_POSE), IDLE_CYCLE_PERCENT)
