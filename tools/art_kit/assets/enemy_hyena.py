"""Rot Hyena: a mangy carrion hyena the rot keeps on its feet, hunting in packs (phase 12).

Silhouette: the hyena's sloping back (high, heavy shoulders, low hips), a big blunt head on a
thick neck, round ears, a ragged dark mane bristling from the nape to mid-back, a short dark
tail tuft, long front legs and bent hind legs. Colour areas: dull sandy-dun fur with dark brown
spots, a near-black mane, muzzle and tail tuft, pale bone teeth, a rot wound eaten into the
haunch (purple rim, a dim rot-green glow inside) and rot-green eyes that flare in the tell.

A model built straight from a pose dict (no humanoid rig): the hips and the spine's pitch place
the body; each leg is a two-bone chain reaching for its paw; neck, head, jaw and tail are
angles. Model units are pixels before SIZE; x is forward (the hyena faces right in the model;
the camera mirrors it to face left like every enemy), y up, z toward the viewer.

Pose keys:
    hip       (x, y) of the hip joint
    pitch     spine angle, degrees (+ = shoulders higher than hips)
    neck      neck angle from forward, degrees (+ = up)
    head      head pitch, degrees (+ = muzzle up)
    jaw       jaw opening, degrees
    tail      tail angle from straight back, degrees (+ = up)
    fn/ff     front paw (near/far) position; hn/hf hind paw position (x, y, z)
    crouch    0..1 how far the shoulders hunch down into the neck (the tell)
    glow      0..1 eye brightness (1 = the tell)
    eyes      1 = open, 0 = shut (hurt)
    roll      degrees the whole body rolls onto its side (death: it falls over)
    dead      1 = the rot wound has gone dark
"""
from __future__ import annotations

import math
from typing import Any

import numpy as np

from kit.beast import (build_enemy, cone, decal, dir2, finish, framed, lift_off_last_row, mix, pose_with,
                        unit, v)
from kit.palette import M, Material
from kit.render import Camera, Frame, render
from kit.rig import two_bone
from kit.sdf import Ellipsoid, Moved, Node, SmoothUnion, Sphere, Union, rot
from kit.specs import ENEMY_FRAME, ENEMY_POSES, PORTRAIT

ID = "rot_hyena"
S = ENEMY_FRAME[ID]
SIZE = 1.0
CAM_CX = -4.5
CAM_CY = -1.5
# Mirrors idle_cycle_percent in data/enemies/rot_hyena.tres (quick, nervous breathing).
IDLE_CYCLE_PERCENT = 80

# --- Materials -----------------------------------------------------------------------------------
FUR = Material.make("hyena_fur", "#7d765c", wrap=0.3, ao=0.6)
# Legs: a step darker and browner than the body, so they read apart from it.
LEGFUR = Material.make("hyena_leg", "#655e48", wrap=0.3, ao=0.6)
# The belly and throat: a paler, greyer dun.
PALE = Material.make("hyena_pale", "#968a70", wrap=0.4, ao=0.5)
SPOT = Material.make("hyena_spot", "#352c27", wrap=0.35, ao=0.4)
MANE = Material.make("hyena_mane", "#352c2d", wrap=0.3, ao=0.4)
MUZZLE = Material.make("hyena_muzzle", "#403533", wrap=0.3, ao=0.4)
NOSE = Material.make("hyena_nose", "#2d2429", below=1, above=1, wrap=0.2, spec=0.6)
MAW = Material.make("hyena_maw", "#5a2232", below=1, above=1, wrap=0.2, ao=0.1)
BONE = M["bone"]
EYE = M["glow_rot"]
LESION = M["rot_purple"]
CORE = Material.make("hyena_rot_core", "#7aa344", below=2, above=1, emissive=True, glow_index=2)
CORE_DEAD = Material.make("hyena_rot_dead", "#3f4a30", below=1, above=1, wrap=0.3)

# --- Body measures (model px) --------------------------------------------------------------------
SPINE = 24.0
FRONT_UPPER, FRONT_LOWER = 11.5, 11.0
HIND_THIGH, HIND_SHIN, HOCK = 9.0, 8.0, 4.5
NECK_LEN = 6.0
LEG_Z = 4.3


def _pose(**kw: Any) -> dict[str, Any]:
    p: dict[str, Any] = dict(
        hip=(-12.0, 17.0), pitch=22.0, neck=6.0, head=-18.0, jaw=10.0, tail=-35.0,
        fn=(10.5, 1.6, LEG_Z), ff=(7.0, 1.6, -LEG_Z), hn=(-11.0, 1.6, LEG_Z), hf=(-15.0, 1.6, -LEG_Z),
        crouch=0.0, glow=0.0, eyes=1.0, roll=0.0, dead=0.0,
    )
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    # Standing square, head low and level, mouth a little open, watching.
    "idle": _pose(),
    # The tell: crouched back on its haunches, chest low, head down and thrust forward, jaw wide,
    # tail up, eyes flaring rot-green: coiled to spring.
    "windup": _pose(hip=(-15.0, 12.5), pitch=10.0, neck=-6.0, head=-6.0, jaw=34.0, tail=20.0,
                    fn=(12.0, 1.6, LEG_Z), ff=(9.0, 1.6, -LEG_Z), hn=(-12.0, 1.6, LEG_Z),
                    hf=(-16.0, 1.6, -LEG_Z), crouch=1.0, glow=1.0),
    # Flying at the target: stretched long and low, front legs reaching, hind legs kicked back,
    # jaws open wide.
    "lunge": _pose(hip=(-10.0, 17.5), pitch=8.0, neck=-10.0, head=0.0, jaw=40.0, tail=0.0,
                   fn=(22.0, 9.0, LEG_Z), ff=(19.0, 7.0, -LEG_Z), hn=(-27.0, 7.0, LEG_Z),
                   hf=(-24.0, 5.0, -LEG_Z), glow=0.6),
    # The bite: landed with the front paws planted wide, the head driven down and forward, the
    # jaws snapped shut.
    "contact": _pose(hip=(-13.0, 14.5), pitch=6.0, neck=-28.0, head=-18.0, jaw=4.0, tail=-10.0,
                     fn=(17.0, 1.6, LEG_Z), ff=(13.0, 1.6, -LEG_Z), hn=(-12.0, 1.6, LEG_Z),
                     hf=(-17.0, 1.6, -LEG_Z), glow=0.6),
    # Recoil: reared back, head flung up and back, mouth open, eyes shut.
    "hurt": _pose(hip=(-14.0, 14.0), pitch=34.0, neck=44.0, head=26.0, jaw=26.0, tail=-50.0,
                  fn=(6.0, 6.0, LEG_Z), ff=(4.0, 3.0, -LEG_Z), hn=(-13.0, 1.6, LEG_Z),
                  hf=(-17.0, 1.6, -LEG_Z), eyes=0.0),
    # Front paws stamped down hard together, chest dropped between them, head low.
    "slam": _pose(hip=(-12.0, 16.5), pitch=2.0, neck=-22.0, head=-22.0, jaw=24.0, tail=10.0,
                  fn=(13.0, 1.6, LEG_Z - 1.0), ff=(12.0, 1.6, -LEG_Z + 1.0), hn=(-13.0, 1.6, LEG_Z),
                  hf=(-16.0, 1.6, -LEG_Z), glow=0.6),
}


# --- Skeleton ------------------------------------------------------------------------------------

def skeleton(p: dict[str, Any]) -> dict[str, Any]:
    hx, hy = p["hip"]
    hip = v((hx, hy, 0.0))
    sh = hip + dir2(float(p["pitch"])) * SPINE
    sh = sh - v((0.0, 2.5 * float(p["crouch"]), 0.0))
    spine = unit(sh - hip)
    neck0 = sh + spine * 3.0 + v((0.0, 2.0, 0.0))
    ndir = dir2(float(p["neck"]))
    neck1 = neck0 + ndir * NECK_LEN
    hdir = dir2(float(p["neck"]) * 0.25 + float(p["head"]))
    return {"hip": hip, "sh": sh, "spine": spine, "neck0": neck0, "neck1": neck1, "hdir": hdir}


def _front_leg(sk: dict[str, Any], paw: Any, z: float) -> list[Node]:
    top = sk["sh"] + v((1.5, -3.0, z))
    elbow, end = two_bone(top, v(paw), FRONT_UPPER, FRONT_LOWER, v((-1.0, 0.0, 0.0)))
    grp = "leg_n" if z > 0 else "leg_f"
    return [cone(FUR, top, elbow, 3.4, 2.0, group=grp), cone(LEGFUR, elbow, end, 1.8, 1.4, group=grp),
            Ellipsoid(MUZZLE, end + v((1.4, 0.2, 0.0)), (2.6, 1.4, 1.8), group=grp)]


def _hind_leg(sk: dict[str, Any], paw: Any, z: float) -> list[Node]:
    top = sk["hip"] + v((0.5, -2.0, z))
    paw = v(paw)
    hock = paw + v((-2.5, HOCK, 0.0))
    knee, end = two_bone(top, hock, HIND_THIGH, HIND_SHIN, v((1.0, 0.0, 0.0)))
    grp = "leg_n" if z > 0 else "leg_f"
    return [cone(FUR, top + v((0.0, 1.5, 0.0)), knee, 4.2, 2.2, group=grp),
            cone(LEGFUR, knee, end, 1.9, 1.5, group=grp),
            cone(LEGFUR, end, paw + v((0.0, 0.6, 0.0)), 1.7, 1.5, group=grp),
            Ellipsoid(MUZZLE, paw + v((1.2, 0.2, 0.0)), (2.4, 1.3, 1.7), group=grp)]


# Spots on the body, in (along the spine 0..1, height above the spine line, z) and size.
SPOTS = ((0.12, -1.5, 5.0, 2.0), (0.3, 1.8, 5.2, 1.8), (0.45, -2.2, 5.6, 2.1), (0.62, 1.2, 6.2, 1.8),
         (0.78, -2.8, 6.4, 2.0), (0.92, 2.5, 6.2, 1.6), (0.22, -4.2, 4.2, 1.5), (0.55, 4.0, 4.6, 1.4),
         (0.85, 5.5, 4.4, 1.5), (0.4, -4.8, 3.6, 1.3))
# Mane bristles from the nape along the back: (along neck 0..1 or back 0..1, length, lean).
MANE_TUFTS = (("neck", 0.15, 5.2), ("neck", 0.5, 5.0), ("neck", 0.85, 4.2), ("back", 0.98, 5.6),
              ("back", 0.84, 4.8), ("back", 0.68, 3.8), ("back", 0.52, 2.8), ("back", 0.38, 2.0))


def _torso(sk: dict[str, Any], p: dict[str, Any]) -> list[Node]:
    hip, sh, sp = sk["hip"], sk["sh"], sk["spine"]
    up = unit(np.cross(v((0.0, 0.0, 1.0)), sp))
    chest = Ellipsoid(FUR, sh + up * 0.5 + sp * 0.5, (8.0, 8.0, 6.8), group="body")
    barrel = Ellipsoid(FUR, (hip + sh) / 2 - up * 0.5, (11.5, 5.4, 5.6),
                       R=_spine_R(sp), group="body")
    haunch = Ellipsoid(FUR, hip + up * -0.5, (6.0, 6.0, 5.6), group="body")
    belly = Ellipsoid(PALE, (hip + sh) / 2 - up * 3.6 + sp * 2.0, (8.0, 2.6, 4.6), R=_spine_R(sp), group="body")
    body = SmoothUnion(chest, barrel, haunch, k=3.0)
    parts: list[Node] = [body, belly]
    for t, h, z, r in SPOTS:
        c = hip + (sh - hip) * t + up * h + v((0.0, 0.0, z))
        parts.append(Ellipsoid(SPOT, c, (r * 1.35, r * 1.05, 0.8), group="body"))
    # The rot wound in the haunch: a purple rim round a glowing hole.
    wound = hip + up * 1.5 + sp * 1.5 + v((0.0, 0.0, 5.0))
    parts.append(Ellipsoid(LESION, wound, (3.6, 3.0, 1.4), group="body"))
    parts.append(Ellipsoid(CORE_DEAD if p.get("dead", 0.0) >= 0.5 else CORE, wound + v((0.0, 0.0, 0.8)),
                           (2.2, 1.8, 1.1), group="wound"))
    return parts


def _spine_R(sp: np.ndarray) -> np.ndarray:
    a = math.degrees(math.atan2(sp[1], sp[0]))
    return rot(0.0, 0.0, a)


def _mane(sk: dict[str, Any]) -> list[Node]:
    out: list[Node] = []
    hip, sh, n0, n1 = sk["hip"], sk["sh"], sk["neck0"], sk["neck1"]
    up = unit(np.cross(v((0.0, 0.0, 1.0)), sk["spine"]))
    for where, t, length in MANE_TUFTS:
        if where == "neck":
            base = n0 + (n1 - n0) * t + v((0.0, 3.2, 0.0))
            tip = base + unit(v((-0.5, 1.0, 0.0))) * length
        else:
            base = hip + (sh - hip) * t + up * (5.2 + 2.5 * t)
            tip = base + unit(up - sk["spine"] * 0.6) * length
        out.append(cone(MANE, base, tip, 1.9, 0.5, group="mane"))
    return out


def _head(sk: dict[str, Any], p: dict[str, Any]) -> list[Node]:
    n0, n1, hd = sk["neck0"], sk["neck1"], sk["hdir"]
    up = unit(np.cross(v((0.0, 0.0, 1.0)), hd))
    neck = cone(FUR, n0, n1, 6.4, 5.2, group="body")
    throat = cone(PALE, n0 - v((0.0, 2.5, 0.0)), n1 - up * 2.2, 3.2, 2.6, group="body")
    skull_c = n1 + hd * 2.5 + up * 0.8
    skull = Ellipsoid(FUR, skull_c, (6.4, 5.6, 5.2), R=_spine_R(hd), group="head")
    snout_a = skull_c + hd * 3.0 - up * 0.6
    snout_b = snout_a + hd * 6.5 - up * 0.8
    snout = cone(MUZZLE, snout_a, snout_b, 3.8, 3.0, group="head")
    nose = Sphere(NOSE, snout_b + hd * 1.6 + up * 0.6, 1.5, group="head")
    # The jaw hinges under the skull and swings down by `jaw`.
    ja = math.radians(float(p["jaw"]))
    jdir = unit(hd * math.cos(ja) - up * math.sin(ja))
    jaw_a = skull_c + hd * 1.5 - up * 2.6
    jaw_b = jaw_a + jdir * 8.5
    jaw = cone(MUZZLE, jaw_a, jaw_b, 2.4, 1.6, group="jaw")
    parts: list[Node] = [neck, throat, skull, snout, nose, jaw]
    if float(p["jaw"]) > 12.0:
        mouth = (snout_a + jaw_b) / 2 - up * 0.6
        parts.append(Ellipsoid(MAW, mouth + v((0.0, 0.0, 1.5)), (3.4, 1.6, 2.2), R=_spine_R(hd), group="maw"))
        for k in (0.35, 0.7):
            top = snout_a + (snout_b - snout_a) * k - up * 2.4 + v((0.0, 0.0, 1.6))
            parts.append(cone(BONE, top, top - up * 1.6 + hd * 0.2, 0.7, 0.3, group="teeth", thin=True))
            low = jaw_a + (jaw_b - jaw_a) * (k + 0.1) + unit(np.cross(v((0.0, 0.0, 1.0)), jdir)) * 1.6 + v((0.0, 0.0, 1.4))
            parts.append(cone(BONE, low, low + unit(np.cross(v((0.0, 0.0, 1.0)), jdir)) * 1.3, 0.6, 0.3, group="teeth", thin=True))
    # Round ears on top, pricked back.
    for z in (2.6, -2.6):
        e = skull_c + up * 5.4 - hd * 3.0 + v((0.0, 0.0, z * 1.2))
        parts.append(Ellipsoid(MUZZLE, e, (3.0, 3.2, 1.2), R=_spine_R(unit(up - hd * 0.3)), group="ear"))
    return parts


def _tail(sk: dict[str, Any], p: dict[str, Any]) -> list[Node]:
    base = sk["hip"] + v((-5.5, 2.0, 0.0))
    d = dir2(180.0 - float(p["tail"]))
    mid = base + d * 5.0
    tip = mid + unit(d + v((0.0, -0.4, 0.0))) * 4.0
    return [cone(FUR, base, mid, 2.0, 1.6, group="tail"), cone(MANE, mid, tip, 2.4, 1.2, group="tail")]


def model(p: dict[str, Any]) -> Node:
    sk = skeleton(p)
    parts: list[Node] = []
    parts += _torso(sk, p)
    parts += _mane(sk)
    parts += _head(sk, p)
    parts += _tail(sk, p)
    parts += _front_leg(sk, p["fn"], LEG_Z) + _front_leg(sk, p["ff"], -LEG_Z)
    parts += _hind_leg(sk, p["hn"], LEG_Z) + _hind_leg(sk, p["hf"], -LEG_Z)
    node: Node = Union(*parts)
    roll = float(p.get("roll", 0.0))
    if roll:
        node = Moved(node, (0.0, 0.0, 0.0), rot(roll, 0.0, 0.0))
    return Scaled(node, SIZE)


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
    if float(p.get("eyes", 1.0)) < 0.5:
        return
    sk = skeleton(p)
    hd = sk["hdir"]
    up = unit(np.cross(v((0.0, 0.0, 1.0)), hd))
    hot = float(p.get("glow", 0.0)) >= 0.9
    rows = (["ab", "bb"] if big else ["ab"]) if not hot else (["aa", "ab"] if big else ["aa"])
    legend = {"a": (EYE, 3 if hot else 2), "b": (EYE, 2 if hot else 1)}
    skull_c = sk["neck1"] + hd * 2.5 + up * 0.8
    for z in (3.4, -3.4):
        pt = (skull_c + hd * 3.0 + up * 1.6 + v((0.0, 0.0, z))) * SIZE
        decal(fr, cam, pt, rows, legend, ("head",), tol=3.5, group="eye")


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


PORTRAIT_SCALE = 0.5
PORTRAIT_AT = (25.0, 24.0)
PORTRAIT_POSE = pose_with(POSES["idle"], neck=22.0, head=-4.0, jaw=26.0, glow=0.6)


def render_portrait(p: dict[str, Any]) -> np.ndarray:
    sk = skeleton(p)
    cam = framed(PORTRAIT, PORTRAIT_SCALE, (sk["neck1"] + sk["hdir"] * 4.0 + v((0.0, 1.0, 0.0))) * SIZE, PORTRAIT_AT)
    fr = render(model(p), cam)
    _eyes(fr, cam, p, big=True)
    return finish_frame(fr)


# --- Clips ---------------------------------------------------------------------------------------
K = {n: i for i, n in enumerate(ENEMY_POSES)}
IDLE, WINDUP, LUNGE, CONTACT, HURT, SLAM = (POSES[n] for n in ENEMY_POSES)

BREATH = pose_with(IDLE, hip=(-12.0, 16.5), pitch=23.0, neck=8.0, head=-18.0, jaw=16.0, tail=-38.0)
COIL_1 = mix(IDLE, WINDUP, 0.4, glow=0.5)
COIL_2 = mix(IDLE, WINDUP, 0.8, glow=1.0)
SHIVER = pose_with(WINDUP, hip=(-15.0, 12.0), jaw=40.0, head=-4.0, tail=26.0)
LUNGE_1 = mix(WINDUP, LUNGE, 0.35, hn=(-14.0, 1.6, LEG_Z), hf=(-17.0, 1.6, -LEG_Z))
LUNGE_2 = mix(WINDUP, LUNGE, 0.7)
BITE_1 = pose_with(CONTACT, jaw=14.0, head=-24.0, neck=-14.0)
BITE_2 = mix(CONTACT, IDLE, 0.4, jaw=8.0)
RECOIL_1 = mix(CONTACT, IDLE, 0.6)
RETURN_1 = mix(CONTACT, IDLE, 0.5, fn=(13.0, 4.0, LEG_Z))
RETURN_2 = mix(CONTACT, IDLE, 0.85, hf=(-14.0, 4.0, -LEG_Z))
SLAM_2 = pose_with(SLAM, hip=(-12.0, 15.5), jaw=30.0)
SLAM_3 = mix(SLAM, IDLE, 0.4)
SLAM_UP = mix(SLAM, IDLE, 0.75)
HURT_1 = mix(HURT, IDLE, 0.5, eyes=1.0)
STAGGER_1 = pose_with(HURT, hip=(-16.0, 13.5), pitch=38.0, neck=52.0, head=30.0, fn=(4.0, 9.0, LEG_Z))
STAGGER_2 = pose_with(IDLE, hip=(-13.0, 13.0), pitch=8.0, neck=0.0, head=-30.0, jaw=20.0)
# Death: a last yelp, the legs give out, it slumps onto its side and the wound goes dark.
DEATH_1 = pose_with(HURT, jaw=36.0, head=32.0)
DEATH_2 = pose_with(IDLE, hip=(-12.0, 12.0), pitch=4.0, neck=6.0, head=-30.0, jaw=20.0, eyes=0.0, dead=1.0,
                    fn=(12.0, 1.6, LEG_Z + 1.0), ff=(9.0, 1.6, -LEG_Z - 1.0), tail=-60.0)
DEATH_3 = pose_with(DEATH_2, hip=(-12.0, 9.0), pitch=0.0, neck=-6.0, roll=20.0)
DEATH_4 = pose_with(DEATH_2, hip=(-12.0, 7.0), pitch=-2.0, neck=-12.0, head=-20.0, roll=30.0, jaw=10.0,
                    fn=(16.0, 2.0, LEG_Z + 2.0), ff=(13.0, 2.0, -LEG_Z), hn=(-20.0, 2.0, LEG_Z + 2.0),
                    hf=(-18.0, 2.0, -LEG_Z))


def _gait(fn: float, ff: float, hn: float, hf: float, lift: tuple[float, float, float, float],
          bob: float, run: bool = False) -> dict[str, Any]:
    """A walking or running frame: each paw's x offset from its standing spot and its lift."""
    base = IDLE
    return pose_with(base, hip=(-12.0 + (2.0 if run else 0.0), 17.0 + bob), pitch=14.0 if run else 20.0,
                     neck=20.0 if run else 30.0, head=-10.0 if run else -14.0, jaw=24.0 if run else 12.0,
                     tail=-10.0 if run else -30.0, glow=0.6 if run else 0.0,
                     fn=(10.5 + fn, 1.6 + lift[0], LEG_Z), ff=(7.0 + ff, 1.6 + lift[1], -LEG_Z),
                     hn=(-11.0 + hn, 1.6 + lift[2], LEG_Z), hf=(-15.0 + hf, 1.6 + lift[3], -LEG_Z))


# A trot: diagonal pairs swing together; a pair is planted on cells 0 and 2.
WALK = [_gait(4.0, -4.0, -4.0, 4.0, (0, 0, 0, 0), -0.4), _gait(0.0, 0.0, 0.0, 0.0, (0, 3.5, 3.5, 0), 0.6),
        _gait(-4.0, 4.0, 4.0, -4.0, (0, 0, 0, 0), -0.4), _gait(0.0, 0.0, 0.0, 0.0, (3.5, 0, 0, 3.5), 0.6)]
# The gallop: front pair reaching, then gathered under the body.
CHASE = [_gait(8.0, 6.0, -8.0, -6.0, (2, 4, 1, 3), 1.0, run=True),
         _gait(2.0, 0.0, -2.0, 0.0, (4, 2, 0, 0), 0.0, run=True),
         _gait(-5.0, -6.0, 6.0, 4.0, (0, 0, 3, 5), -0.6, run=True),
         _gait(0.0, -2.0, 2.0, 0.0, (0, 0, 4, 2), 0.4, run=True)]

CLIPS: dict[str, list[Any]] = {
    "idle": [K["idle"], mix(IDLE, BREATH, 0.5), BREATH, mix(IDLE, BREATH, 0.5)],
    "windup": [COIL_1, COIL_2, K["windup"]],
    "windup_hold": [K["windup"], SHIVER],
    "lunge": [LUNGE_1, LUNGE_2, K["lunge"]],
    "contact": [K["contact"], BITE_1, BITE_2],
    "recoil": [RECOIL_1, K["idle"]],
    "return": [RETURN_1, RETURN_2, K["idle"]],
    "slam": [K["slam"], SLAM_2, SLAM_3],
    "slam_recover": [SLAM_UP, K["idle"]],
    "hurt": [K["hurt"], HURT_1, K["idle"]],
    "stagger": [K["hurt"], STAGGER_1, STAGGER_2, K["idle"]],
    "death": [DEATH_1, DEATH_2, DEATH_3, DEATH_4],
    "walk": WALK,
    "chase": CHASE,
}


def build(ctx) -> None:
    build_enemy(ctx, ID, S, POSES, CLIPS, render_frame, finish_frame, render_cell,
                render_portrait(PORTRAIT_POSE), IDLE_CYCLE_PERCENT)
