"""A posable human skeleton (heroes, the husk, the king): proportions + pose -> joint positions.

Poses name where the important things go (pelvis, hands, feet, lean, head turn) and two-bone IK
works out elbows and knees with fixed bone lengths, so every pose keeps the same proportions and
in-between frames can be made by blending two poses (`blend`).

Axes as in sdf.py: x forward (facing), y up, z toward the camera's side. "n" = near side (+z,
the arm and leg nearer the viewer), "f" = far side.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any

import numpy as np

from .palette import Material
from .sdf import Capsule, Ellipsoid, Node, Prim, RoundCone, Sphere, SmoothUnion, Union, basis, rot


@dataclass
class Build:
    """Body proportions in model units (one unit = one sprite pixel at scale 1)."""

    ankle_h: float = 1.5
    shin: float = 8.6
    thigh: float = 8.6
    spine: float = 9.2      # pelvis centre -> shoulder line
    neck: float = 2.0
    head_r: float = 5.4
    shoulder_w: float = 4.3  # centre -> shoulder joint
    hip_w: float = 2.2
    upper_arm: float = 6.4
    forearm: float = 6.0
    foot_len: float = 3.6

    def stand_hip(self) -> float:
        return self.ankle_h + self.shin + self.thigh - 0.4


@dataclass
class Skeleton:
    j: dict[str, np.ndarray] = field(default_factory=dict)
    torso: np.ndarray = field(default_factory=lambda: np.eye(3))
    head: np.ndarray = field(default_factory=lambda: np.eye(3))
    hips: np.ndarray = field(default_factory=lambda: np.eye(3))

    def __getitem__(self, k: str) -> np.ndarray:
        return self.j[k]


def two_bone(a: np.ndarray, target: np.ndarray, l1: float, l2: float, pole: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Elbow/knee and end position reaching from `a` toward `target`, bending toward `pole`."""
    v = target - a
    d = float(np.linalg.norm(v))
    d = min(max(d, abs(l1 - l2) + 1e-3), l1 + l2 - 1e-3)
    dirv = v / (np.linalg.norm(v) + 1e-9)
    along = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
    h = math.sqrt(max(l1 * l1 - along * along, 0.0))
    p = pole - dirv * float(np.dot(pole, dirv))
    if np.linalg.norm(p) < 1e-6:
        p = np.array([0.0, 0.0, 1.0]) - dirv * dirv[2]
    p = p / (np.linalg.norm(p) + 1e-9)
    mid = a + dirv * along + p * h
    end = a + dirv * d
    return mid, end


def _v(x: Any) -> np.ndarray:
    return np.asarray(x, dtype=float)


def pose_skeleton(b: Build, pose: dict[str, Any]) -> Skeleton:
    """Pose keys (all optional):
    pelvis (x, y, z); lean (deg, + = top forward); side_lean (deg, + = top toward camera);
    twist (deg, upper body yaw vs hips); hip_yaw (deg); head (pitch down, yaw, tilt) degrees;
    hand_n / hand_f targets; elbow_n / elbow_f pole vectors; foot_n / foot_f ankle targets;
    knee_n / knee_f pole vectors; toe_n / toe_f foot pitch (deg, + = toes up);
    stance (default foot spread along x when feet are not given)."""
    sk = Skeleton()
    hip_y = b.stand_hip()
    pelvis = _v(pose.get("pelvis", (0.0, hip_y, 0.0)))
    hip_yaw = float(pose.get("hip_yaw", 0.0))
    hips = rot(0.0, hip_yaw, 0.0)
    lean = float(pose.get("lean", 0.0))
    side = float(pose.get("side_lean", 0.0))
    twist = float(pose.get("twist", 0.0))
    torso = rot(0.0, hip_yaw + twist, 0.0) @ rot(side, 0.0, -lean)
    sk.hips = hips
    sk.torso = torso
    chest = pelvis + torso @ _v((0.0, b.spine, 0.0))
    neck = chest + torso @ _v((0.25, b.neck, 0.0))
    hp, hy, ht = pose.get("head", (0.0, 0.0, 0.0))
    head_R = torso @ rot(0.0, hy, -hp) @ rot(ht, 0.0, 0.0)
    sk.head = head_R
    head = neck + head_R @ _v((0.3, b.head_r * 0.92, 0.0))
    sk.j.update(pelvis=pelvis, chest=chest, neck=neck, head=head,
                belly=pelvis + torso @ _v((0.0, b.spine * 0.45, 0.0)))

    for side_name, sgn in (("n", 1.0), ("f", -1.0)):
        sh = chest + torso @ _v((0.0, -0.6, sgn * b.shoulder_w))
        default_hand = sh + torso @ _v((0.6, -(b.upper_arm + b.forearm) * 0.93, sgn * 0.7))
        hand_t = _v(pose.get("hand_" + side_name, default_hand))
        pole = _v(pose.get("elbow_" + side_name, torso @ _v((-1.0, -0.2, sgn * 0.5))))
        elbow, hand = two_bone(sh, hand_t, b.upper_arm, b.forearm, pole)
        sk.j["shoulder_" + side_name] = sh
        sk.j["elbow_" + side_name] = elbow
        sk.j["hand_" + side_name] = hand

        hip = pelvis + hips @ _v((0.0, -0.8, sgn * b.hip_w))
        stance = float(pose.get("stance", 0.0))
        default_foot = _v((hip[0] + sgn * stance * 0.5, b.ankle_h, hip[2] + sgn * 0.3))
        foot_t = _v(pose.get("foot_" + side_name, default_foot))
        kpole = _v(pose.get("knee_" + side_name, hips @ _v((1.0, 0.0, sgn * 0.15))))
        knee, ankle = two_bone(hip, foot_t, b.thigh, b.shin, kpole)
        toe_pitch = float(pose.get("toe_" + side_name, 0.0))
        toe_yaw = float(pose.get("toe_yaw_" + side_name, hip_yaw))
        toe_dir = rot(0.0, toe_yaw, toe_pitch) @ _v((1.0, 0.0, 0.0))
        sk.j["hip_" + side_name] = hip
        sk.j["knee_" + side_name] = knee
        sk.j["ankle_" + side_name] = ankle
        sk.j["toe_" + side_name] = ankle + toe_dir * b.foot_len + _v((0.0, -b.ankle_h * 0.55, 0.0))
    return sk


def blend(a: dict[str, Any], b: dict[str, Any], t: float) -> dict[str, Any]:
    """In-between pose: numbers and tuples are mixed (t = 0 gives a, 1 gives b). Keys missing on
    one side are taken from the other."""
    out: dict[str, Any] = {}
    for k in set(a) | set(b):
        if k not in a:
            out[k] = b[k]
        elif k not in b:
            out[k] = a[k]
        else:
            va, vb = a[k], b[k]
            if isinstance(va, (int, float)) and isinstance(vb, (int, float)):
                out[k] = va + (vb - va) * t
            elif isinstance(va, (tuple, list)) and isinstance(vb, (tuple, list)):
                out[k] = tuple(x + (y - x) * t for x, y in zip(va, vb))
            else:
                out[k] = vb if t >= 0.5 else va
    return out


def ease(t: float) -> float:
    return t * t * (3.0 - 2.0 * t)


@dataclass
class BodyMats:
    skin: Material
    shirt: Material
    pants: Material
    boots: Material
    sleeve: Material | None = None   # upper arm (defaults to shirt)
    glove: Material | None = None    # hands (defaults to skin)


def body(sk: Skeleton, b: Build, m: BodyMats, group: str = "body", chest_r: float = 4.2,
         waist_r: float = 3.3, hip_r: float = 3.5, limb_r: float = 1.55, leg_r: float = 1.9,
         boot_r: float = 1.7, bare_forearm: bool = False, smooth: float = 1.2) -> list[Node]:
    """A plain clothed body for the skeleton: torso, neck, head, arms, legs, boots. Asset modules
    add their own clothes, hair, armour and gear on top (or skip this and build their own)."""
    t = sk.torso
    parts: list[Node] = []
    torso = SmoothUnion(
        Ellipsoid(m.shirt, sk["chest"] + t @ _v((0.0, -2.2, 0.0)), (chest_r * 0.78, chest_r, chest_r * 1.05), R=t, group=group),
        Ellipsoid(m.shirt, sk["belly"], (waist_r * 0.85, waist_r * 1.3, waist_r), R=t, group=group),
        Ellipsoid(m.pants, sk["pelvis"], (hip_r * 0.85, hip_r * 0.8, hip_r * 1.02), R=sk.hips, group=group),
        k=smooth,
    )
    parts.append(torso)
    parts.append(Capsule(m.skin, sk["chest"], sk["neck"], 1.3, group=group))
    parts.append(Ellipsoid(m.skin, sk["head"], (b.head_r * 0.95, b.head_r, b.head_r * 0.92), R=sk.head, group=group + "_head"))
    for s in ("n", "f"):
        sleeve = m.sleeve or m.shirt
        parts.append(RoundCone(sleeve, sk["shoulder_" + s], sk["elbow_" + s], limb_r * 1.08, limb_r * 0.95, group=group + "_arm" + s))
        parts.append(RoundCone(m.skin if bare_forearm else sleeve, sk["elbow_" + s], sk["hand_" + s], limb_r * 0.95, limb_r * 0.8, group=group + "_arm" + s))
        parts.append(Sphere(m.glove or m.skin, sk["hand_" + s], limb_r * 0.95, group=group + "_arm" + s))
        parts.append(RoundCone(m.pants, sk["hip_" + s], sk["knee_" + s], leg_r * 1.1, leg_r * 0.92, group=group + "_leg" + s))
        parts.append(RoundCone(m.boots, sk["knee_" + s], sk["ankle_" + s], boot_r * 1.0, boot_r * 0.9, group=group + "_leg" + s))
        parts.append(RoundCone(m.boots, sk["ankle_" + s], sk["toe_" + s], boot_r * 0.95, boot_r * 0.75, group=group + "_leg" + s))
    return parts


def frame_of(a: np.ndarray, b: np.ndarray, up: Any = (0.0, 1.0, 0.0)) -> np.ndarray:
    """A rotation whose x axis runs from a to b (for gear held along a forearm, straps, blades)."""
    return basis(b - a, up)
