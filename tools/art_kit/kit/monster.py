"""Shared parts for the phase 19 monsters (enemy_rat, enemy_slinger, enemy_brute, enemy_lantern,
enemy_priest, enemy_tick): a uniform scale node, the eye decal and the standard enemy clip list
(kit.specs.TIER1_ENEMY plus the throw clips) built from a module's six row-0 keys and a few
hand-set poses. Like kit.beast (the phase 12 monsters), every model is built straight from a pose
dict; this only saves each module from repeating the same clip table.
"""
from __future__ import annotations

from typing import Any, Mapping, Sequence

from .beast import mix, pose_with
from .sdf import Node
from .specs import ENEMY_POSES

K = {n: i for i, n in enumerate(ENEMY_POSES)}


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


def standard_clips(poses: Mapping[str, dict[str, Any]], breath: dict[str, Any], shiver: dict[str, Any],
                   stagger: dict[str, Any], death: Sequence[dict[str, Any]], walk: Sequence[dict[str, Any]],
                   chase: Sequence[dict[str, Any]], throw: bool = False, **hand: Any) -> dict[str, list[Any]]:
    """Every Tier 1 enemy clip from the six keys: the wind-up coils in two steps, the lunge
    stretches in two, the contact and slam settle back, the hurt recovers. `throw` adds
    windup_shoot / shoot (a ranged monster's throw: the wind-up held back, the slam as the release).
    `hand` overrides any in-between by name (coil_1, coil_2, lunge_1, lunge_2, bite_1, bite_2,
    recoil_1, return_1, return_2, slam_2, slam_3, slam_up, hurt_1)."""
    idle, windup, lunge, contact, hurt, slam = (poses[n] for n in ENEMY_POSES)
    p = {
        "coil_1": mix(idle, windup, 0.4),
        "coil_2": mix(idle, windup, 0.8),
        "lunge_1": mix(windup, lunge, 0.35),
        "lunge_2": mix(windup, lunge, 0.7),
        "bite_1": mix(contact, slam, 0.3),
        "bite_2": mix(contact, idle, 0.4),
        "recoil_1": mix(contact, idle, 0.6),
        "return_1": mix(contact, idle, 0.5),
        "return_2": mix(contact, idle, 0.85),
        "slam_2": mix(slam, contact, 0.3),
        "slam_3": mix(slam, idle, 0.4),
        "slam_up": mix(slam, idle, 0.75),
        "hurt_1": mix(hurt, idle, 0.5),
    }
    p.update(hand)
    clips: dict[str, list[Any]] = {
        "idle": [K["idle"], mix(idle, breath, 0.5), breath, mix(idle, breath, 0.5)],
        "windup": [p["coil_1"], p["coil_2"], K["windup"]],
        "windup_hold": [K["windup"], shiver],
        "lunge": [p["lunge_1"], p["lunge_2"], K["lunge"]],
        "contact": [K["contact"], p["bite_1"], p["bite_2"]],
        "recoil": [p["recoil_1"], K["idle"]],
        "return": [p["return_1"], p["return_2"], K["idle"]],
        "slam": [K["slam"], p["slam_2"], p["slam_3"]],
        "slam_recover": [p["slam_up"], K["idle"]],
        "hurt": [K["hurt"], p["hurt_1"], K["idle"]],
        "stagger": [K["hurt"], stagger, mix(stagger, idle, 0.5), K["idle"]],
        "death": list(death),
        "walk": list(walk),
        "chase": list(chase),
    }
    if throw:
        clips["windup_shoot"] = [p["coil_1"], p["coil_2"], K["windup"]]
        clips["shoot"] = [K["slam"], p["slam_2"], p["slam_3"], K["idle"]]
    return clips


def gait(base: dict[str, Any], keys: Sequence[str], offsets: Sequence[Sequence[Any]], **kw: Any) -> list[dict[str, Any]]:
    """Walk or run cells: each entry of `offsets` gives, per key in `keys`, the value to set (any
    other key from `kw` is set on every cell)."""
    cells = []
    for row in offsets:
        p = pose_with(base, **kw)
        for k, val in zip(keys, row):
            p[k] = val
        cells.append(p)
    return cells


def limb(root: Any, a_deg: float, b_deg: float, l1: float, l2: float, z: float = 0.0) -> tuple[Any, Any]:
    """A two-segment limb in the side plane from `root`: the upper part at a_deg (0 = forward, 90 =
    up, -90 = down), the lower part turned b_deg more. Returns (elbow, hand), z-shifted by `z`."""
    import numpy as np
    from .beast import dir2
    r = np.asarray(root, dtype=float)
    elbow = r + dir2(a_deg) * l1
    hand = elbow + dir2(a_deg + b_deg) * l2
    if z:
        elbow = elbow + np.array((0.0, 0.0, z))
        hand = hand + np.array((0.0, 0.0, z))
    return elbow, hand
