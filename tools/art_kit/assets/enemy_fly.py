"""Carrion Fly: a bloated blowfly as big as a dog, fat on the rot (phase 12).

Silhouette: a round bristly thorax, a swollen striped abdomen hanging behind it, a small head
almost all eyes (two big glossy red compound eyes) with a stabbing proboscis, two long smoky
wings standing up off its back, and six thin legs dangling under it. It hovers (a floater, like
the gnats and the shade): it never touches the floor. Colour areas: a metallic blue-black body,
dull green rings on the abdomen with a few glowing rot pustules, dark red eyes, smoky pale wings.

Wings flap by frame: `flap` +1 = raised, -1 = swept down. Built straight from a pose dict like
enemy_hyena (no humanoid rig). Model units are pixels before SIZE; x forward (it faces right in
the model, the camera mirrors it), y up, z toward the viewer.

Pose keys:
    body     (x, y) of the thorax centre
    pitch    body tilt, degrees (+ = nose up)
    flap     -1..1 wing stroke
    sweep    wing angle back along the body, degrees (a dive sweeps them back)
    curl     degrees the abdomen curls under (the tell, a spit)
    legs     0..1 legs reaching forward (a strike) instead of dangling
    stab     0..1 the proboscis thrust out
    glow     0..1 how brightly the pustules glow (1 = the tell)
    dead     1 = on its back, wings crumpled, pustules dark
"""
from __future__ import annotations

import math
from typing import Any

import numpy as np

from kit.beast import build_enemy, cone, finish, framed, mix, pose_with, unit, v
from kit.palette import M, Material
from kit.render import Camera, Frame, line3d, render
from kit.sdf import Ellipsoid, Moved, Node, SmoothUnion, Sphere, Union, rot
from kit.specs import ENEMY_FRAME, ENEMY_POSES, PORTRAIT

ID = "carrion_fly"
S = ENEMY_FRAME[ID]
SIZE = 1.5
CAM_CX = 1.0
CAM_CY = 1.5
# Mirrors idle_cycle_percent in data/enemies/carrion_fly.tres (a quick buzz).
IDLE_CYCLE_PERCENT = 35

# --- Materials -----------------------------------------------------------------------------------
SHELL = Material.make("fly_shell", "#2e3442", below=2, above=2, spec=0.9, spec_power=10.0, wrap=0.2)
ABDOMEN = Material.make("fly_abdomen", "#3d4a36", spec=0.6, spec_power=8.0, wrap=0.3)
BAND = Material.make("fly_band", "#6a7a3e", wrap=0.35)
EYE = Material.make("fly_eye", "#8a2a2a", below=2, above=2, spec=1.0, spec_power=16.0, wrap=0.2)
WING = Material.make("fly_wing", "#9aa4ac", below=1, above=2, wrap=0.6, dither=True)
LEG = Material.make("fly_leg", "#24242c", below=1, above=2, wrap=0.2)
PROBOSCIS = Material.make("fly_proboscis", "#4a3a32", wrap=0.3)
PUS = Material.make("fly_pustule", "#7aa344", below=2, above=1, emissive=True, glow_index=2)
PUS_HOT = Material(name="fly_pustule_hot", colors=list(M["glow_rot"].colors), emissive=True, glow_index=3)
PUS_DEAD = Material.make("fly_pustule_dead", "#3f4a30", below=1, above=1, wrap=0.3)

HOVER_Y = 24.0


def _pose(**kw: Any) -> dict[str, Any]:
    p: dict[str, Any] = dict(body=(0.0, HOVER_Y), pitch=6.0, flap=1.0, sweep=20.0, curl=10.0, legs=0.0,
                             stab=0.0, glow=0.0, dead=0.0)
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    # Hovering, wings up, legs dangling.
    "idle": _pose(),
    # The tell: pulled up and back, abdomen curled under, pustules flaring, wings high.
    "windup": _pose(body=(-4.0, HOVER_Y + 3.5), pitch=24.0, flap=1.0, curl=50.0, glow=1.0, legs=0.3),
    # Diving at the target: nose down, wings swept back, legs reaching.
    "lunge": _pose(body=(5.0, HOVER_Y - 6.0), pitch=-34.0, flap=-0.3, sweep=60.0, curl=0.0, legs=1.0,
                   stab=0.5, glow=0.6),
    # The stab: proboscis thrust into the target, legs grabbing.
    "contact": _pose(body=(6.0, HOVER_Y - 5.0), pitch=-18.0, flap=-1.0, sweep=35.0, curl=20.0, legs=1.0,
                     stab=1.0, glow=0.6),
    # Knocked tumbling back and up, wings flung out.
    "hurt": _pose(body=(-5.0, HOVER_Y + 3.0), pitch=40.0, flap=0.4, sweep=-10.0, curl=-20.0, legs=0.2),
    # Dive-bombing the floor: nose down low, abdomen slammed under.
    "slam": _pose(body=(4.0, 17.0), pitch=-48.0, flap=-1.0, sweep=50.0, curl=40.0, legs=1.0, glow=0.6),
}
# The spit (clip `shoot`): rears back, abdomen pumped forward under it, proboscis out.
SHOOT = _pose(body=(-3.0, HOVER_Y + 2.0), pitch=18.0, flap=-0.5, curl=70.0, stab=1.0, glow=0.8, legs=0.4)


# --- Model ---------------------------------------------------------------------------------------

def _axes(p: dict[str, Any]) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    bx, by = p["body"]
    a = math.radians(float(p["pitch"]))
    return v((bx, by, 0.0)), v((math.cos(a), math.sin(a), 0.0)), v((-math.sin(a), math.cos(a), 0.0))


def _Rz(d: np.ndarray) -> np.ndarray:
    return rot(0.0, 0.0, math.degrees(math.atan2(d[1], d[0])))


PUSTULES = ((0.3, 0.5, 0.8, 1.5), (0.55, 0.15, 0.95, 1.3), (0.72, 0.75, 0.55, 1.2))


def model(p: dict[str, Any]) -> Node:
    c, f, u = _axes(p)
    parts: list[Node] = []
    thorax = Ellipsoid(SHELL, c, (6.0, 5.6, 5.6), R=_Rz(f), group="body", bumps=(0.25, 0.9, 3))
    # Abdomen: hangs behind and below, curling under by `curl`.
    ca = math.radians(180.0 + float(p["curl"]))
    adir = unit(f * math.cos(ca) - u * math.sin(ca))
    ac = c + adir * 9.5 - u * 1.0
    abdomen = Ellipsoid(ABDOMEN, ac, (8.5, 6.5, 6.6), R=_Rz(adir), group="body")
    parts.append(SmoothUnion(thorax, abdomen, k=2.0))
    for k in (0.2, 0.55):
        parts.append(Ellipsoid(BAND, c + adir * (5.0 + 8.0 * k) - u * 1.0, (1.4, 6.6 - 1.5 * k, 6.7 - 1.5 * k),
                               R=_Rz(adir), group="band"))
    pus = PUS_DEAD if p.get("dead", 0.0) >= 0.5 else (PUS_HOT if float(p["glow"]) >= 0.9 else PUS)
    for t, h, z, r in PUSTULES:
        side = unit(np.cross(v((0.0, 0.0, 1.0)), adir))
        pt = c + adir * (5.0 + 9.0 * t) + side * (h * 5.0) + v((0.0, 0.0, z * 6.4)) - u * 1.0
        parts.append(Sphere(pus, pt, r, group="pustule"))
    # Head: two big eyes and the proboscis.
    hc = c + f * 6.0 + u * 0.5
    parts.append(Sphere(SHELL, hc, 3.2, group="head"))
    for z in (2.6, -2.6):
        parts.append(Ellipsoid(EYE, hc + f * 1.0 + u * 0.8 + v((0.0, 0.0, z)), (2.8, 3.4, 2.4), R=_Rz(f), group="eye"))
    stab = float(p["stab"])
    pa = hc + f * 2.0 - u * 2.0
    pdir = unit(f * (0.5 + 0.5 * stab) - u * (1.0 - 0.6 * stab))
    parts.append(cone(PROBOSCIS, pa, pa + pdir * (4.0 + 5.0 * stab), 1.2, 0.6, group="proboscis", thin=True))
    parts += _wings(p, c, f, u)
    node: Node = Union(*parts)
    if float(p.get("dead", 0.0)) >= 0.5:
        node = Moved(node, c, rot(0.0, 0.0, 0.0))
    return Scaled(node, SIZE)


def _wings(p: dict[str, Any], c: np.ndarray, f: np.ndarray, u: np.ndarray) -> list[Node]:
    """Two wings standing up off the back. The stroke (`flap`) mostly twists each wing about its
    own length (face-on at +1, edge-on at 0, turned over at -1), so the beat shows while the wing
    tips, the sprite's top, stay put (the game anchors popups to the idle top)."""
    out: list[Node] = []
    flap = float(p["flap"])
    sweep = math.radians(float(p["sweep"]))
    lift = math.radians(WING_LIFT)
    for z in (2.8, -2.8):
        root = c + u * 4.5 + v((0.0, 0.0, z * 0.6))
        d = unit(-f * math.sin(sweep) + u * math.sin(lift) * math.cos(sweep)
                 + v((0.0, 0.0, math.copysign(math.cos(lift), z) * 0.8)))
        wc = root + d * 8.0
        R = _wing_R(d, f) @ rot(flap * WING_TWIST * (1.0 if z > 0 else -1.0), 0.0, 0.0)
        out.append(Ellipsoid(WING, wc, (9.0, 0.5, 3.6), R=R, group="wing_n" if z > 0 else "wing_f"))
    return out


# Wings stand this many degrees up off the back; a full stroke twists them this far.
WING_LIFT = 52.0
WING_TWIST = 70.0


def _wing_R(d: np.ndarray, f: np.ndarray) -> np.ndarray:
    """Wing axes: local x along the wing, local y its thin side, local z across it."""
    x = unit(d)
    zz = unit(np.cross(x, unit(f + v((0.0, 0.3, 0.0)))))
    y = unit(np.cross(zz, x))
    return np.stack([x, y, zz], axis=1)


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


# Legs: (hip offset forward, side, splay: + = the leg points forward, - = back).
LEGS = ((2.5, 1.0, 0.8), (0.0, 1.0, 0.0), (-2.5, 1.0, -0.8), (2.5, -1.0, 0.6), (-2.5, -1.0, -0.6))


def _legs(fr: Frame, cam: Camera, p: dict[str, Any]) -> None:
    """Six thin jointed legs drawn as 1-pixel lines: dangling, or reaching forward to strike."""
    c, f, u = _axes(p)
    reach = float(p["legs"])
    for fo, side, splay in LEGS:
        hip = c + f * fo - u * 3.6 + v((0.0, 0.0, side * 2.6))
        knee = hip + unit(f * (splay + 1.2 * reach) - u * (0.7 - 0.3 * reach) + v((0.0, 0.0, side * 0.5))) * 4.5
        foot = knee + unit(f * (0.4 * splay + 0.6 * reach) - u + v((0.0, 0.0, side * 0.2))) * 5.0
        pts = [x * SIZE for x in (hip, knee, foot)]
        line3d(fr, cam, pts, LEG, 1, group="leg_n" if side > 0 else "leg_f")


# --- Rendering -----------------------------------------------------------------------------------

def camera() -> Camera:
    return Camera(S, S, face="left", cx=CAM_CX, cy=CAM_CY)


def render_frame(p: dict[str, Any], cam: Camera | None = None) -> Frame:
    cam = cam or camera()
    fr = render(model(p), cam)
    _legs(fr, cam, p)
    return fr


def finish_frame(fr: Frame) -> np.ndarray:
    return finish(fr, keep=("pustule", "proboscis", "leg_n", "leg_f"))


def render_cell(p: dict[str, Any]) -> np.ndarray:
    return finish_frame(render_frame(p))


PORTRAIT_SCALE = 0.8
PORTRAIT_AT = (22.0, 24.0)
PORTRAIT_POSE = pose_with(POSES["idle"], stab=0.5, glow=0.6, pitch=0.0)


def render_portrait(p: dict[str, Any]) -> np.ndarray:
    c, f, u = _axes(p)
    cam = framed(PORTRAIT, PORTRAIT_SCALE, (c + f * 4.0 + u * 1.0) * SIZE, PORTRAIT_AT)
    fr = render(model(p), cam)
    return finish_frame(fr)


# --- Clips ---------------------------------------------------------------------------------------
K = {n: i for i, n in enumerate(ENEMY_POSES)}
IDLE, WINDUP, LUNGE, CONTACT, HURT, SLAM = (POSES[n] for n in ENEMY_POSES)


def _beat(p: dict[str, Any], flap: float, dy: float = 0.0, **kw: Any) -> dict[str, Any]:
    """`p` at another point of the wing stroke, bobbing `dy`."""
    bx, by = p["body"]
    return pose_with(p, flap=flap, body=(bx, by + dy), **kw)


FLAP = [K["idle"], _beat(IDLE, 0.0, -0.3), _beat(IDLE, -1.0, -0.5), _beat(IDLE, 0.0, -0.2)]
COIL_1 = _beat(mix(IDLE, WINDUP, 0.45), -0.5, glow=0.5)
COIL_2 = _beat(mix(IDLE, WINDUP, 0.8), 0.5, glow=1.0)
SHIVER = _beat(WINDUP, -0.6, -0.6)
LUNGE_1 = mix(WINDUP, LUNGE, 0.35)
LUNGE_2 = mix(WINDUP, LUNGE, 0.7)
STAB_1 = _beat(CONTACT, 0.0, 0.5, stab=0.8)
STAB_2 = mix(CONTACT, IDLE, 0.45)
RECOIL_1 = _beat(mix(CONTACT, IDLE, 0.6), 0.6)
RETURN_1 = _beat(mix(CONTACT, IDLE, 0.5), -0.8, pitch=-6.0)
RETURN_2 = _beat(mix(CONTACT, IDLE, 0.8), 0.8)
SLAM_2 = _beat(SLAM, 0.2, 1.0)
SLAM_3 = mix(SLAM, IDLE, 0.4)
SLAM_UP = _beat(mix(SLAM, IDLE, 0.75), -0.5)
HURT_1 = _beat(mix(HURT, IDLE, 0.5), -0.6)
STAGGER_1 = pose_with(HURT, body=(-6.0, HOVER_Y + 1.5), pitch=50.0, flap=-1.0)
STAGGER_2 = _beat(mix(HURT, IDLE, 0.6), 1.0, -3.0)
# Death: a last spasm, the wings stop, it drops to the floor and lies there, pustules dark.
DEATH_1 = pose_with(HURT, pitch=60.0, flap=-1.0, curl=-30.0)
DEATH_2 = pose_with(IDLE, body=(0.0, 14.0), pitch=-30.0, flap=-1.0, sweep=70.0, glow=0.0, dead=1.0)
DEATH_3 = pose_with(DEATH_2, body=(0.0, 8.0), pitch=-10.0, curl=20.0)
DEATH_4 = pose_with(DEATH_2, body=(0.0, 6.5), pitch=0.0, curl=10.0, sweep=80.0, legs=0.6)
SHOOT_2 = _beat(SHOOT, 0.6, 0.6, curl=50.0, stab=0.6)
# Flying around a zone: a forward tilt and fast wings; chasing tilts further.
WALK = [_beat(IDLE, 1.0, 0.0, pitch=-4.0), _beat(IDLE, -0.2, -0.8, pitch=-4.0), _beat(IDLE, -1.0, -1.2, pitch=-4.0),
        _beat(IDLE, 0.0, -0.4, pitch=-4.0)]
CHASE = [_beat(IDLE, 1.0, 0.0, pitch=-16.0, legs=0.6, glow=0.6),
         _beat(IDLE, -1.0, -1.0, pitch=-16.0, legs=0.6, glow=0.6),
         _beat(IDLE, 1.0, -0.4, pitch=-18.0, legs=0.7, glow=0.6),
         _beat(IDLE, -1.0, -1.2, pitch=-18.0, legs=0.7, glow=0.6)]

CLIPS: dict[str, list[Any]] = {
    "idle": FLAP,
    "windup": [COIL_1, COIL_2, K["windup"]],
    "windup_hold": [K["windup"], SHIVER],
    "lunge": [LUNGE_1, LUNGE_2, K["lunge"]],
    "contact": [K["contact"], STAB_1, STAB_2],
    "recoil": [RECOIL_1, K["idle"]],
    "return": [RETURN_1, RETURN_2, K["idle"]],
    "slam": [K["slam"], SLAM_2, SLAM_3],
    "slam_recover": [SLAM_UP, K["idle"]],
    "hurt": [K["hurt"], HURT_1, K["idle"]],
    "stagger": [K["hurt"], STAGGER_1, STAGGER_2, K["idle"]],
    "death": [DEATH_1, DEATH_2, DEATH_3, DEATH_4],
    "walk": WALK,
    "chase": CHASE,
    "windup_shoot": [COIL_1, _beat(SHOOT, 1.0, 0.0, stab=0.0, glow=1.0), _beat(SHOOT, -1.0, -0.6, stab=0.0, glow=1.0)],
    "shoot": [SHOOT, SHOOT_2, K["idle"]],
}


def build(ctx) -> None:
    build_enemy(ctx, ID, S, POSES, CLIPS, render_frame, finish_frame, render_cell,
                render_portrait(PORTRAIT_POSE), IDLE_CYCLE_PERCENT, floats=True)
