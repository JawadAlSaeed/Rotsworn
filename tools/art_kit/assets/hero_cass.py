"""Cass, the Mender (healer and support): hero sheet and portrait.

A gold robe with a purple sash, a wide-brimmed pointed hat (gold, purple band, crooked tip),
long auburn hair, a herb satchel and a tall wooden staff topped by a glowing cyan crystal.

Phase 10 reuse: POSES holds the keyframes (plain dicts); `model(pose)` builds the SDF model plus
its overlays, `render_pose(pose)` returns one finished RGBA frame. In-betweens are
`render_pose(blend(POSES[a], POSES[b], t))` (kit.rig.blend).

Pose keys on top of kit.rig.pose_skeleton's:
  staff_base (x, y, z) and staff_dir: where the staff's foot is and which way it points;
  grip_n / grip_f: distance along the staff where the near / far hand holds it (None = free);
  glow 0..2 (crystal: dim, glowing, flaring), dim (crystal dark: hurt, down);
  ward 0..1 (parry ward ring), ward_at (offset from the chest, torso frame), ward_r (half
  width, half height in pixels);
  hem (dx, dy, dz) robe hem offset (swing), flare (extra hem radius);
  hat_tilt (rx, ry, rz) degrees on top of the head; hat_world (x, y, z, rx, ry, rz) puts the hat
  on the ground instead (angles in view terms: rx tips it toward the viewer, rz leans it across
  the screen, ry spins it); hair (dx, dy, dz) swing of the long hair; hair_dir lays it out in a
  direction (lying down); fringe (low, teeth) shape of the bangs; tails (dx, dy, dz) sash tail
  swing; eyes "open" | "closed" | "wince";
  root (rx, ry, rz) turns the whole skeleton about the pelvis and root_shift moves it (lying
  down); drape + hem_open: the lying robe;
  lock_front / sprig_at: portrait extras (a lock over the shoulder, the herb sprig's spot).
"""
from __future__ import annotations

import math
from typing import Any, Callable

import numpy as np

from kit import specs
from kit.palette import INK, M, Material
from kit.post import cleanup, outline
from kit.render import Camera, Frame, line3d, render
from kit.rig import Build, Skeleton, blend, pose_skeleton
from kit.sdf import (Box, Capsule, Custom, Cylinder, Ellipsoid, Node, RoundCone, SmoothUnion, Sphere,
                     Subtract, Torus, Union, basis, rot)
from kit.sheet import hstack

ID = "cass"

BUILD = Build(ankle_h=1.4, shin=7.2, thigh=7.4, spine=8.2, neck=1.5, head_r=4.9, shoulder_w=3.4,
              hip_w=1.6, upper_arm=5.3, forearm=5.0, foot_len=2.9)

# --- Materials --------------------------------------------------------------------------------

SKIN = M["skin_fair"]
# The face uses the same fair-skin ramp but never its reddest shadow, so the face front (turned
# away from the light) stays soft.
FACE = Material(name="cass_face", colors=list(M["skin_fair"].colors), lo=1.0, hi=4.0, wrap=0.35, ao=0.4)
# Shared auburn ramp; highlights stop short of the palest tan so the hair stays red-brown.
HAIR = Material(name="cass_hair", colors=list(M["hair_auburn"].colors), hi=3.4, wrap=0.3)
ROBE = M["cloth_gold"]
HAT = Material.make("cass_hat", "#a8802c", wrap=0.4)
SASH = M["cloth_purple"]
WOOD = M["wood"]
FIT = M["gold"]
BOOTS = M["leather_dark"]
LEGS = M["cloth_charcoal"]
BAG = M["leather"]
STRAP = M["leather_dark"]
HERB = M["grass"]
BLOOM = Material.make("cass_bloom", "#e7d2df", below=2, above=1, wrap=0.5)
_CY = M["glow_cyan"].colors
# The staff crystal is drawn as a faceted gem in screen space (see _crystal): a deep-to-pale
# cyan ramp (the shared glow_cyan in the middle) and, for the "crystal dark" beats, a grey-teal.
CRYSTAL = Material(name="cass_crystal", colors=["#0f5f7e", "#1b93b5", _CY[1], _CY[2], _CY[3], "#e2fff8"],
                   emissive=True, outline="#0b3247")
CRYSTAL_DIM = Material(name="cass_crystal_dim", colors=["#203c4c", "#2f5562", "#456c74", "#638788", "#83a09d"],
                       emissive=True, outline="#0d1f2b")
# Ramp indices (shade facet, ridge, lit facet, glint) for dim / resting / glowing / flaring.
CRYSTAL_TONES = {"dim": (1, 2, 3, 4), 0: (2, 3, 3, 4), 1: (3, 4, 4, 5), 2: (4, 5, 5, 5)}
CRYSTAL_LEN = 5.8   # model units from the claw to the tip
CRYSTAL_HW = 1.65   # half width at the widest point
FX = Material(name="cass_fx", colors=list(_CY), emissive=True)
EYE = Material(name="cass_eye", colors=[INK, "#3a2638", "#5a3f4e"], ao=0.0)
IRIS = Material.make("cass_iris", "#2f7a74", below=2, above=2)
WHITE = M["eye_white"]
BLUSH = Material(name="cass_blush", colors=["#e9a08c"])

FX_GROUPS = ("cass_fx", "cass_fx_stamp")
STAFF_LEN = 35.0
LIFT = 0.9  # pixels: soles of the boots dip a little below y = 0
TIGHT_GROUPS = ("arm", "hand", "cuff", "bag", "staff", "fit")
PLEATS = 9
PLEAT_AMP = 0.32


# --- Small shapes the kit does not have --------------------------------------------------------


def capped_cone(a: Any, b: Any, ra: float, rb: float, rnd: float = 0.0) -> Callable[[np.ndarray], np.ndarray]:
    """Distance to a cone cut flat at both ends (a robe skirt), edges rounded by `rnd`."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ra -= rnd
    rb -= rnd
    ba = b - a
    baba = float(ba @ ba)
    rba = rb - ra
    k = rba * rba + baba

    def fn(P: np.ndarray) -> np.ndarray:
        pa = P - a
        papa = np.sum(pa * pa, axis=1)
        paba = (pa @ ba) / baba
        x = np.sqrt(np.maximum(papa - paba * paba * baba, 0.0))
        cax = np.maximum(0.0, x - np.where(paba < 0.5, ra, rb))
        cay = np.abs(paba - 0.5) - 0.5
        f = np.clip((rba * (x - ra) + paba * baba) / k, 0.0, 1.0)
        cbx = x - ra - f * rba
        cby = paba - f
        s = np.where((cbx < 0.0) & (cay < 0.0), -1.0, 1.0)
        return s * np.sqrt(np.minimum(cax * cax + cay * cay * baba, cbx * cbx + cby * cby * baba)) - rnd

    return fn


def pleated(fn: Callable[[np.ndarray], np.ndarray], top: Any, hem: Any, n: int = 8, amp: float = 0.3,
            phase: float = 0.0) -> Callable[[np.ndarray], np.ndarray]:
    """Vertical folds on a skirt-like shape: ridges that grow toward the hem (not an exact
    distance, fine for small `amp`)."""
    top = np.asarray(top, float)
    hem = np.asarray(hem, float)
    ax = hem - top
    L2 = float(ax @ ax)
    axn = ax / math.sqrt(L2)
    u = np.cross(axn, (0.0, 0.0, 1.0))
    if np.linalg.norm(u) < 1e-3:
        u = np.cross(axn, (1.0, 0.0, 0.0))
    u = u / np.linalg.norm(u)
    w = np.cross(axn, u)

    def f(P: np.ndarray) -> np.ndarray:
        q = P - top
        s = np.clip((q @ ax) / L2, 0.0, 1.0)
        th = np.arctan2(q @ w, q @ u)
        return fn(P) - amp * s ** 1.3 * np.sin(n * th + phase)

    return f


def fringe(r: float, low: float = 0.3, teeth: float = 2.0) -> Callable[[np.ndarray], np.ndarray]:
    """Bangs: a thin shell over the forehead whose lower edge zigzags into locks (head frame).
    low: height of the lowest lock tips (head radii above the head centre); teeth: locks per
    head radius across the brow."""
    c = np.array([-0.06 * r, 0.07 * r, 0.0])
    rad = np.array([0.93 * r + 0.4, 0.93 * r + 0.4, 0.9 * r + 0.4])

    def fn(Q: np.ndarray) -> np.ndarray:
        q = (Q - c) / rad
        k0 = np.linalg.norm(q, axis=1)
        shell = (k0 - 1.0) * rad.min()
        zz = Q[:, 2] / r
        tri = np.abs(((zz * teeth + 0.5) % 2.0) - 1.0)         # 0..1 zigzag across the brow
        edge = r * (low + 0.13 * tri) - Q[:, 1]                # keep y above the jagged edge
        front = 0.1 * r - Q[:, 0]                               # only over the front of the head
        return np.maximum(np.maximum(shell, edge), front)

    return fn


def band(rx: float, rz: float, h: float) -> Callable[[np.ndarray], np.ndarray]:
    """An elliptic ring band around local y (a sash, a hat band)."""

    def fn(Q: np.ndarray) -> np.ndarray:
        e = np.sqrt((Q[:, 0] / rx) ** 2 + (Q[:, 2] / rz) ** 2)
        d_side = (e - 1.0) * min(rx, rz)
        d_y = np.abs(Q[:, 1]) - h
        return np.maximum(d_side, d_y)

    return fn


def _v(x: Any) -> np.ndarray:
    return np.asarray(x, dtype=float)


def _unit(x: Any) -> np.ndarray:
    v = _v(x)
    return v / (np.linalg.norm(v) + 1e-9)


# --- Poses -------------------------------------------------------------------------------------

H0 = BUILD.stand_hip()

# Every key any pose uses has a neutral value here, so kit.rig.blend always has both ends (a key
# missing on one side would be copied whole). On/off keys are numbers read as "on" from 0.5;
# None-valued keys switch halfway through a blend.
_BASE: dict[str, Any] = dict(
    glow=0, ward=0, ward_at=(11.0, -1.0, 0.0), ward_r=(3.0, 9.0), hem=(0.0, 0.0, 0.0), flare=0.0,
    hat_tilt=(0.0, 0.0, 0.0), hat_world=None, hair=(0.0, 0.0, 0.0), hair_dir=None,
    fringe=(0.3, 2.0), tails=(0.0, 0.0, 0.0), eyes="open", toe_n=0.0, toe_f=0.0,
    knee_n=(1.0, 0.0, 0.15), knee_f=(1.0, 0.0, -0.15), side_lean=0.0,
    grip_n=None, grip_f=None, dim=0.0, drape=0.0, hem_open=1.0, lock_front=0.0,
    root=(0.0, 0.0, 0.0), root_shift=(0.0, 0.0, 0.0),
)


def _pose(**kw: Any) -> dict[str, Any]:
    p = dict(_BASE)
    p.update(kw)
    return p


POSES: dict[str, dict[str, Any]] = {
    # Standing at home: staff upright in the forward hand, the other hand by the satchel.
    "idle": _pose(
        pelvis=(0.0, H0 - 0.1, 0.0), lean=2.0, head=(4.0, -24.0, 0.0),
        foot_n=(0.8, 1.4, 1.8), foot_f=(-0.6, 1.4, -1.8),
        staff_base=(8.2, 0.0, -0.6), staff_dir=(0.0, 1.0, 0.0), grip_f=19.5,
        hand_n=(-0.6, 13.4, 3.8),
    ),
    # Combat stance: a step back into a low, wide stance, leaning in, the staff held in both
    # hands across the body and angled at the enemy, crystal lit.
    "ready": _pose(
        pelvis=(-4.2, H0 - 2.4, 0.0), lean=14.0, head=(0.0, -27.0, 0.0),
        foot_n=(0.6, 1.4, 2.2), foot_f=(-8.6, 1.4, -1.8),
        staff_base=(-5.0, 2.0, 8.6), staff_dir=(0.377, 0.838, -0.395), grip_n=12.5, grip_f=18.5,
        glow=1, hem=(0.3, 0.0, 0.0), flare=0.6, hat_tilt=(0.0, 0.0, -4.0),
        hair=(-0.8, 0.2, 0.0), tails=(-0.4, 0.0, 0.0),
    ),
    # Ward: leaning back, staff held across in front, a glowing arc between Cass and the hit.
    "parry": _pose(
        pelvis=(-1.6, H0 - 1.4, 0.0), lean=-6.0, head=(8.0, -22.0, 0.0),
        foot_n=(1.8, 1.4, 2.0), foot_f=(-4.6, 1.4, -1.8), toe_n=10.0,
        staff_base=(-1.49, 8.6, 13.21), staff_dir=(0.10, 0.62, -0.78), grip_n=9.0, grip_f=17.0,
        glow=1, ward=1, ward_at=(11.0, -1.0, 0.0), ward_r=(3.0, 9.0),
        hem=(-0.6, 0.0, 0.0), flare=0.4, hat_tilt=(0.0, 0.0, 6.0),
        hair=(0.4, 0.0, 0.0), tails=(0.3, 0.0, 0.0), eyes="wince",
    ),
    # Hop back to the left: low, leaning away, the near arm thrown back for balance, staff
    # held close and tilted with the body, robe swinging forward.
    "dodge": _pose(
        pelvis=(-4.4, H0 - 2.6, 0.0), lean=-16.0, head=(6.0, -22.0, 0.0),
        foot_n=(1.6, 1.8, 2.0), foot_f=(-8.4, 1.4, -1.8), toe_n=24.0,
        staff_base=(5.4, 2.0, -2.4), staff_dir=(-0.17, 0.985, 0.0), grip_f=16.0,
        hand_n=(-9.4, 13.0, 4.2),
        hem=(3.0, 0.8, 0.0), flare=1.8, hat_tilt=(0.0, 0.0, 12.0),
        hair=(2.6, 0.8, 0.0), tails=(2.4, 0.8, 0.0),
    ),
    # Tucked in the air: knees up, feet folded back, robe flared, staff held at the side.
    "jump": _pose(
        pelvis=(0.0, H0 + 2.6, 0.0), lean=16.0, head=(-4.0, -22.0, 0.0),
        foot_n=(-1.6, 9.6, 1.9), foot_f=(-3.6, 8.4, -1.8), toe_n=-20.0, toe_f=-30.0,
        knee_n=(1.0, 0.2, 0.2), knee_f=(1.0, 0.2, -0.2),
        staff_base=(5.0, 4.5, -2.6), staff_dir=(0.12, 0.99, 0.0), grip_f=16.0,
        hand_n=(4.0, 15.5, 4.0),
        hem=(1.0, 1.0, 0.0), flare=2.2, hat_tilt=(0.0, 0.0, -10.0),
        hair=(-1.2, 2.6, 0.0), tails=(-1.2, 2.2, 0.0),
    ),
    # Knocked back: thrown off balance, head snapped back, hat knocked askew, the staff tipping
    # forward out of a loose grip, crystal dim.
    "hurt": _pose(
        pelvis=(2.3, H0 - 1.2, 0.0), lean=-22.0, head=(-16.0, -16.0, 8.0),
        foot_n=(6.9, 3.0, 2.0), foot_f=(0.5, 1.4, -1.8), toe_n=28.0,
        staff_base=(4.3, 6.0, 2.6), staff_dir=(0.22, 0.975, 0.0), grip_n=12.0,
        hand_f=(8.1, 24.0, -3.4), dim=1.0,
        hem=(2.2, 0.2, 0.0), flare=0.8, hat_tilt=(14.0, 0.0, 20.0),
        hair=(3.0, 1.0, 0.0), tails=(1.8, 0.0, 0.0), eyes="wince",
    ),
    # Thrust: deep lunge to the right, staff driven level at the enemy, crystal flaring.
    "strike": _pose(
        pelvis=(-0.6, H0 - 3.0, 0.0), lean=18.0, head=(-2.0, -27.0, 0.0),
        foot_n=(7.4, 1.7, 2.0), foot_f=(-7.4, 1.6, -1.8), toe_f=-14.0,
        knee_n=(1.0, 0.1, 0.2),
        staff_base=(-18.03, 13.68, -4.71), staff_dir=(0.918, 0.12, 0.379), grip_n=16.0, grip_f=23.0,
        glow=2, hem=(-1.4, 0.0, 0.0), flare=1.4, hat_tilt=(0.0, 0.0, 10.0),
        hair=(-3.0, 0.8, 0.0), tails=(-2.0, 0.0, 0.0),
    ),
    # Collapsed on the back, eyes shut. A whole body is too long for the frame, so it lies bent
    # at the hips: the legs run along the screen, the upper body turns away into the depth (the
    # face still shows, upright, on the left). The hat fell on the legs and sits crown up; the
    # staff lies behind with its dimmed crystal by the head.
    "down": _pose(
        root=(0.0, 42.0, 90.0), root_shift=(-0.5, 3.2 - H0, -6.3), drape=1.0, hem_open=0.0,
        pelvis=(0.0, H0, 0.0), lean=0.0, side_lean=-55.0, head=(0.0, -30.0, 0.0),
        foot_n=(-2.2, 6.8, 1.0), foot_f=(-2.0, 6.0, -1.4),
        hand_n=(1.0, 13.0, 5.0), hand_f=(3.0, 17.0, -2.0),
        staff_base=(-4.57, 0.6, -30.57), staff_dir=(-0.148, 0.0, 0.989),
        hat_world=(2.0, 3.2, -11.47, 0.0, 0.0, -8.0),
        hair_dir=(-0.5, -0.2, -0.85), eyes="closed", dim=1.0,
    ),
}

# The portrait: the idle body, face turned a little more to the viewer, crystal lit by the face.
PORTRAIT_POSE = _pose(**dict(POSES["idle"], head=(3.0, -42.0, 0.0), glow=1, lock_front=1.0,
                             fringe=(0.15, 2.6)))


# --- Model ------------------------------------------------------------------------------------


Overlay = Callable[[Frame, Camera], None]


def _staff(pose: dict[str, Any]) -> tuple[np.ndarray, np.ndarray]:
    base = _v(pose.get("staff_base", (6.0, 0.0, 1.0)))
    d = _unit(pose.get("staff_dir", (0.0, 1.0, 0.0)))
    return base, d


def skeleton(pose: dict[str, Any]) -> Skeleton:
    """pose_skeleton with the hands put on the staff grips and the optional root turn."""
    p = dict(pose)
    base, d = _staff(pose)
    for s in ("n", "f"):
        g = pose.get("grip_" + s)
        if g is not None:
            p["hand_" + s] = tuple(base + d * float(g))
    sk = pose_skeleton(BUILD, p)
    root = _v(pose.get("root", (0.0, 0.0, 0.0)))
    shift = _v(pose.get("root_shift", (0.0, 0.0, 0.0)))
    if np.any(root != 0.0) or np.any(shift != 0.0):
        # Turn the whole body about the pelvis, then move it by root_shift (lying down).
        Rr = rot(*root)
        piv = sk["pelvis"].copy()
        for k, v in sk.j.items():
            sk.j[k] = Rr @ (v - piv) + piv + shift
        sk.torso = Rr @ sk.torso
        sk.head = Rr @ sk.head
        sk.hips = Rr @ sk.hips
    return sk


def model(pose: dict[str, Any], portrait: bool = False) -> tuple[Node, list[Overlay]]:
    """The SDF model of Cass in `pose`, plus overlays drawn after rendering (staff, straps, eyes,
    glows). portrait=True swaps 1-pixel lines for real thin shapes and adds face detail."""
    b = BUILD
    sk = skeleton(pose)
    t = sk.torso
    hR = sk.head
    hc = sk["head"]
    r = b.head_r
    parts: list[Node] = []
    ovs: list[Overlay] = []

    # Robe: chest, waist and a flared skirt as one soft body (or, lying down, cloth draped
    # along the legs: a cone skirt seen from its open end reads as a drum).
    hem_c, hem_r = _hem(sk, pose)
    skirt_top = sk["belly"] + t @ _v((0.0, 0.6, 0.0))
    upper = [
        Ellipsoid(ROBE, sk["chest"] + t @ _v((0.0, -2.0, 0.0)), (2.8, 3.4, 3.3), R=t, group="robe"),
        Ellipsoid(ROBE, sk["belly"], (2.4, 3.0, 2.7), R=t, group="robe"),
        Sphere(ROBE, sk["shoulder_n"] + t @ _v((0.0, 0.3, -0.3)), 1.55, group="robe"),
        Sphere(ROBE, sk["shoulder_f"] + t @ _v((0.0, 0.3, 0.3)), 1.55, group="robe"),
    ]
    if float(pose.get("drape", 0.0)) >= 0.5:
        lower: list[Node] = []
        holes: list[Node] = []
        trims: list[Node] = []
        for s_ in ("n", "f"):
            kn, an = sk["knee_" + s_], sk["ankle_" + s_]
            sd = _unit(an - kn)
            lo = kn + (an - kn) * 0.62
            lower.append(RoundCone(ROBE, sk["hip_" + s_], kn, 2.5, 2.3, group="robe"))
            lower.append(Custom(ROBE, capped_cone(kn, lo, 2.3, 2.6, 0.3), group="robe"))
            holes.append(Custom(ROBE, capped_cone(lo - sd * 2.5, lo + sd * 0.6, 1.4, 1.9), group="robe"))
            trims.append(Custom(SASH, capped_cone(lo - sd * 1.0, lo + sd * 0.02, 2.85, 2.9, 0.3), group="trim"))
        robe = SmoothUnion(*upper, *lower, k=1.6)
        if float(pose.get("hem_open", 1.0)) >= 0.5:
            hollow: Node = Union(*holes)
            parts.append(Subtract(robe, hollow, k=0.2))
            parts.append(Subtract(Union(*trims), hollow, k=0.2))
        else:
            parts.append(robe)
            parts.append(Union(*trims))
        axis = t @ _v((0.0, 1.0, 0.0))
    else:
        robe = SmoothUnion(
            *upper,
            Custom(ROBE, pleated(capped_cone(skirt_top, hem_c, 2.7, hem_r, 0.4), skirt_top, hem_c,
                                 PLEATS, PLEAT_AMP), group="robe"),
            # The robe drapes over the thighs and knees (they shape it, not poke through).
            RoundCone(ROBE, sk["hip_n"], sk["knee_n"], 2.0, 1.75, group="robe"),
            RoundCone(ROBE, sk["hip_f"], sk["knee_f"], 2.0, 1.75, group="robe"),
            k=1.4,
        )
        # Hollow under the hem, so a raised robe shows its dark inside and the legs.
        skirt_len = float(np.linalg.norm(skirt_top - hem_c))
        axis = _unit(skirt_top - hem_c)
        in_top = hem_c + axis * skirt_len * 0.55
        hollow = Custom(ROBE, capped_cone(in_top, hem_c - axis * 0.8,
                                          2.7 + (hem_r - 2.7) * 0.45 - 1.1, hem_r - 0.6, 0.0), group="robe")
        parts.append(Subtract(robe, hollow, k=0.3))
        # Purple hem trim echoing the sash and hat band.
        s_trim = 1.0 - 1.15 / skirt_len
        trim = Custom(SASH, pleated(capped_cone(hem_c + axis * 1.15, hem_c - axis * 0.05,
                                                2.7 + (hem_r - 2.7) * s_trim + 0.28, hem_r + 0.28, 0.35),
                                    skirt_top, hem_c, PLEATS, PLEAT_AMP), group="trim")
        parts.append(Subtract(trim, hollow, k=0.3))
    # Sash with a knot on the near side, two tails lying on the skirt.
    sash_c = sk["belly"] + t @ _v((0.0, -0.3, 0.0))
    parts.append(Custom(SASH, band(3.35, 3.45, 1.0), pos=sash_c, R=t, group="sash"))
    knot = sash_c + t @ _v((1.6, -0.1, 2.3))
    parts.append(Sphere(SASH, knot, 0.8, group="sash"))
    tails = _v(pose.get("tails", (0.0, 0.0, 0.0)))

    def on_skirt(p: np.ndarray, off: float) -> np.ndarray:
        ba = hem_c - skirt_top
        u = float(np.clip((p - skirt_top) @ ba / (ba @ ba), 0.0, 1.0))
        c = skirt_top + ba * u
        rad = p - c
        return c + _unit(rad) * (2.7 + (hem_r - 2.7) * u + off)

    for k, (ln, side) in enumerate(((5.0, 0.6), (4.0, -0.5))):
        pts = [knot]
        for f in (0.5, 1.0):
            q = knot + axis * (-ln * f) + t @ _v((0.25 * f, 0.0, side * f)) + tails * f * (0.9 - 0.2 * k)
            pts.append(on_skirt(q, 0.35))
        for a, c in zip(pts[:-1], pts[1:]):
            parts.append(RoundCone(SASH, a, c, 0.55, 0.5, group="sash", thin=True))

    # Neck, collar and head (cranium, cheeks, a jaw tapering to the chin; the nose only shows at
    # portrait size). H() places points in head radii in the head's frame.
    def H(x: float, y: float, z: float) -> np.ndarray:
        return hc + hR @ _v((x * r, y * r, z * r))

    parts.append(Capsule(SKIN, sk["chest"], sk["neck"] + t @ _v((0.0, 0.4, 0.0)), 1.15, group="skin"))
    col_c = sk["chest"] + t @ _v((0.2, 0.9, 0.0))
    parts.append(Torus(SASH, col_c, 1.55, 0.55, R=t @ rot(0.0, 0.0, -12.0), group="collar"))
    parts.append(Sphere(FIT, col_c + t @ _v((1.75, -0.35, 0.25)), 0.5, group="clasp"))
    head_parts: list[Node] = [
        Ellipsoid(FACE, H(-0.06, 0.07, 0.0), (r * 0.93, r * 0.93, r * 0.9), R=hR, group="head"),
        Ellipsoid(FACE, H(0.3, -0.33, 0.0), (r * 0.56, r * 0.5, r * 0.72), R=hR, group="head"),
        RoundCone(FACE, H(0.18, -0.4, 0.0), H(0.6, -0.86, 0.0), r * 0.55, r * 0.2, group="head"),
    ]
    if portrait:
        head_parts.append(RoundCone(FACE, H(0.86, -0.1, 0.0), H(0.96, -0.32, 0.0), 0.35, 0.42, group="head"))
    parts.append(SmoothUnion(*head_parts, k=1.3))

    # Arms: robe sleeves that flare at the wrist with purple cuffs, bare hands.
    for sd in ("n", "f"):
        sh, el, hd = sk["shoulder_" + sd], sk["elbow_" + sd], sk["hand_" + sd]
        cuff = el + (hd - el) * 0.72
        parts.append(SmoothUnion(
            RoundCone(ROBE, sh, el, 1.4, 1.25, group="arm" + sd),
            RoundCone(ROBE, el, cuff, 1.25, 1.7, group="arm" + sd),
            k=0.6,
        ))
        parts.append(RoundCone(SASH, el + (hd - el) * 0.6, cuff, 1.68, 1.82, group="cuff" + sd))
        parts.append(Sphere(SKIN, hd, 1.05, group="hand" + sd))
        parts.append(Capsule(SKIN, cuff, hd, 0.7, group="hand" + sd))

    # Legs (under the robe) and boots.
    for sd in ("n", "f"):
        parts.append(RoundCone(LEGS, sk["hip_" + sd], sk["knee_" + sd], 1.2, 1.05, group="leg" + sd))
        parts.append(RoundCone(BOOTS, sk["knee_" + sd], sk["ankle_" + sd], 1.2, 1.25, group="boot" + sd))
        parts.append(RoundCone(BOOTS, sk["ankle_" + sd], sk["toe_" + sd], 1.3, 1.0, group="boot" + sd))

    # Hair: a cap behind the face, a fringe with a jagged edge under the brim, locks by the
    # cheeks and a long back mass.
    hair_off = _v(pose.get("hair", (0.0, 0.0, 0.0)))
    nape = hc + hR @ _v((-2.4, -1.0, 0.0))
    lying_hair = pose.get("hair_dir") is not None
    if lying_hair:
        back_end = nape + _unit(pose["hair_dir"]) * 10.0
    else:
        back_end = sk["chest"] + t @ _v((-2.6, -5.0, 0.0)) + hair_off
    back_mid = nape * 0.5 + back_end * 0.5 + hair_off * 0.3
    if not lying_hair:
        back_mid = back_mid + t @ _v((-0.8, 0.0, 0.0))
    hair_parts: list[Node] = [
        Ellipsoid(HAIR, H(-0.3, 0.14, 0.0), (r * 0.95, r * 0.98, r * 0.99), R=hR, group="hair"),
        Custom(HAIR, fringe(r, *pose.get("fringe", (0.3, 2.0))), pos=hc, R=hR, group="hair"),
        RoundCone(HAIR, H(-0.08, 0.3, 0.84), H(-0.02, -0.92, 0.78), 1.15, 0.55, group="hair"),
        RoundCone(HAIR, H(-0.08, 0.3, -0.84), H(-0.02, -0.85, -0.78), 1.1, 0.55, group="hair"),
        RoundCone(HAIR, nape, back_mid, 3.7, 3.2, group="hair"),
        RoundCone(HAIR, back_mid, back_end, 3.2, 2.0, group="hair"),
    ]
    if float(pose.get("lock_front", 0.0)) >= 0.5:
        sh = sk["shoulder_n"]
        hair_parts.append(RoundCone(HAIR, H(-0.3, -0.3, 0.8), sh + t @ _v((0.9, 1.2, 0.6)), 1.3, 1.3, group="hair"))
        hair_parts.append(RoundCone(HAIR, sh + t @ _v((0.9, 1.2, 0.6)), sh + t @ _v((1.6, -3.5, 0.2)), 1.3, 0.8, group="hair"))
    parts.append(SmoothUnion(*hair_parts, k=1.0))

    # Hat: on the head, or lying on the ground.
    if pose.get("hat_world") is not None:
        # Angles in view terms: rx tips the crown toward the viewer, rz leans it across the
        # screen, ry spins it about its own axis (the hero camera's yaw is undone around them).
        hx, hy, hz, rx, ry, rz = pose["hat_world"]
        yaw = -Camera(1, 1).yaw
        hat_R = rot(0.0, yaw, 0.0) @ rot(rx, 0.0, rz) @ rot(0.0, ry - yaw, 0.0)
        hat_base = _v((hx, hy + 0.9, hz))
    else:
        hat_R = hR @ rot(0.0, 0.0, 9.0) @ rot(*pose.get("hat_tilt", (0.0, 0.0, 0.0)))
        hat_base = hc + hR @ _v((0.1, 2.9, 0.0))
    parts.extend(_hat(hat_base, hat_R, sprig=portrait, sprig_at=pose.get("sprig_at", (0.4, 1.4, 4.2))))

    # Satchel hanging just below the sash on the near hip (so the sash stays a clean band across
    # the waist), strap over the far shoulder down to the sash, herbs poking out.
    bag_at = _v(pose.get("bag_at", (1.0, -0.6, 2.6)))
    bag_R = sk.hips @ rot(0.0, math.degrees(math.atan2(bag_at[0], bag_at[2])), 0.0)
    bag_c = on_skirt(sk["pelvis"] + sk.hips @ bag_at, 0.75)
    parts.append(Box(BAG, bag_c, (1.55, 1.35, 0.75), R=bag_R, round=0.55, group="bag"))
    parts.append(Box(STRAP, bag_c + bag_R @ _v((0.0, 0.85, 0.3)), (1.6, 0.55, 0.6), R=bag_R, round=0.3, group="bagflap"))
    chest_c = sk["chest"] + t @ _v((0.0, -2.0, 0.0))

    def on_chest(q: tuple[float, float, float], off: float = 0.45) -> np.ndarray:
        qv = _v(q)
        rr = _v((2.8, 3.4, 3.3)) + 0.25
        return chest_c + t @ (qv / np.linalg.norm(qv / rr) * (1.0 + off / 3.0))

    strap_pts = [on_chest((0.3, 2.6, -2.4)), on_chest((2.0, 1.0, -1.4)), on_chest((2.4, -0.6, 1.0)),
                 on_chest((1.6, -1.9, 2.6))]
    ovs.append(_line(strap_pts, STRAP, [2, 2, 2], "strap", bias=1.2))
    herb_a = bag_c + bag_R @ _v((-0.7, 1.4, -0.2))
    up = t @ _v((0.0, 1.0, 0.0))
    ovs.append(_line([herb_a, herb_a + up * 2.2 + t @ _v((-0.8, 0.0, 0.0))], HERB, [2], "herb"))
    ovs.append(_line([herb_a + t @ _v((0.5, 0.0, 0.0)), herb_a + up * 1.8 + t @ _v((0.9, 0.0, 0.0))], HERB, [3], "herb"))

    # Staff: shaft, gold claw, crystal.
    base, d = _staff(pose)
    top = base + d * STAFF_LEN
    side = _unit(np.cross(d, _v((0.0, 0.0, 1.0)))) if abs(d[2]) < 0.9 else _unit(np.cross(d, _v((0.0, 1.0, 0.0))))
    if portrait:
        parts.append(Capsule(WOOD, base, top, 0.45, group="staff"))
    else:
        ovs.append(_line([base, base + d * (STAFF_LEN * 0.6), top], WOOD, [2, 3], "staff"))
    parts.append(Sphere(FIT, top + d * 0.1, 0.85, group="fit"))
    glow = int(round(float(pose.get("glow", 0))))
    dim = float(pose.get("dim", 0.0)) >= 0.5
    cry = top + d * (0.4 + CRYSTAL_LEN * 0.42)
    ovs.append(_crystal(top + d * 0.4, d, "dim" if dim else glow, portrait))
    for sgn in (1.0, -1.0):
        ovs.append(_line([top + d * 0.3, top + d * 1.1 + side * sgn * 1.4, top + d * 2.3 + side * sgn * 1.1],
                         FIT, [3, 2], "fit"))
    if glow >= 1:
        ovs.append(_sparkle(cry, glow))
    if float(pose.get("ward", 0)) >= 0.5:
        ovs.append(_ward(sk, pose))

    ovs.append(_eyes(sk, str(pose.get("eyes", "open")), portrait))
    if portrait:
        ovs.append(_face_portrait(sk))
        ovs.append(lambda frame, cam: _hair_strands(frame))
    return Union(*parts), ovs


def _hem(sk: Skeleton, pose: dict[str, Any]) -> tuple[np.ndarray, float]:
    an, af = sk["ankle_n"], sk["ankle_f"]
    kn, kf = sk["knee_n"], sk["knee_f"]
    ank = (an + af) * 0.5
    kne = (kn + kf) * 0.5
    c = ank + (kne - ank) * 0.32 + _v(pose.get("hem", (0.0, 0.0, 0.0)))
    spread = float(np.linalg.norm((an - af)[[0, 1]]))
    rr = 4.6 + max(0.0, spread - 3.0) * 0.45 + float(pose.get("flare", 0.0))
    return c, rr


def _hat(base: np.ndarray, R: np.ndarray, sprig: bool = False,
         sprig_at: tuple[float, float, float] = (-1.6, 1.4, 4.1)) -> list[Node]:
    def P(x: float, y: float, z: float = 0.0) -> np.ndarray:
        return base + R @ _v((x, y, z))

    brim = SmoothUnion(
        Cylinder(HAT, P(0.3, 0.0), 5.5, 0.45, R=R, round=0.4, group="hat"),
        Torus(HAT, P(0.3, -0.25), 6.4, 0.55, R=R, group="hat"),
        k=0.6,
    )
    crown = SmoothUnion(
        Custom(HAT, capped_cone(P(0.0, 0.2), P(-0.3, 4.0), 4.1, 3.0, 0.3), group="hat"),
        RoundCone(HAT, P(-0.3, 3.8), P(-1.0, 6.4), 3.0, 1.9, group="hat"),
        RoundCone(HAT, P(-1.0, 6.4), P(-2.5, 8.2), 1.9, 1.05, group="hat"),
        RoundCone(HAT, P(-2.5, 8.2), P(-4.4, 8.4), 1.05, 0.5, group="hat"),
        k=0.7,
    )
    hb = Custom(SASH, band(4.25, 4.25, 0.75), pos=P(-0.05, 1.2), R=R, group="hatband")
    parts: list[Node] = [brim, crown, hb]
    if sprig:
        # A healer's sprig tucked into the band on the near side: three leaves fanning up and
        # back, and a small pale bloom (portrait only; at sprite size it would be noise).
        root = P(*sprig_at)
        for (dx, dy, dz), ln in (((-0.6, 1.0, 0.25), 1.9), ((-1.0, 0.55, 0.35), 1.7), ((-0.15, 1.0, 0.45), 1.4)):
            d = R @ _unit((dx, dy, dz))
            parts.append(Ellipsoid(HERB, root + d * ln * 0.75, (ln * 0.75, 0.42, 0.62),
                                   R=basis(d, R @ _v((0.0, 0.0, 1.0))), group="sprig"))
        parts.append(Sphere(BLOOM, root + R @ _v((0.35, 0.55, 0.45)), 0.55, group="sprig"))
    return parts


def _line(pts: list[np.ndarray], mat: Material, idx: list[int], group: str,
          always: bool = False, bias: float = 0.6) -> Overlay:
    def ov(frame: Frame, cam: Camera) -> None:
        line3d(frame, cam, pts, mat, idx, group=group, depth_bias=bias, always=always)

    return ov


def _sparkle(c: np.ndarray, level: int) -> Overlay:
    """A small 4-point twinkle (glowing) or a big star (flaring) around the crystal; the crystal
    itself stays visible in the middle."""
    if level >= 2:
        rows = ["....a....", "....b....", "....b....", "...b.b...", "abb...bba", "...b.b...", "....b....", "....b....", "....a...."]
    else:
        rows = ["...a...", ".......", ".......", "a.....a", ".......", ".......", "...a..."]
    o = len(rows) // 2
    legend = {"a": 2, "b": 3}

    def ov(frame: Frame, cam: Camera) -> None:
        cx, cy, _ = cam.project(c)
        x0, y0 = int(math.floor(cx)) - o, int(math.floor(cy)) - o
        part = frame.add_part(FX, "cass_fx")
        for r, row in enumerate(rows):
            for q, ch in enumerate(row):
                if ch not in legend:
                    continue
                x, y = x0 + q, y0 + r
                if not (0 <= x < frame.W and 0 <= y < frame.H):
                    continue
                p = frame.part[y, x]
                if p >= 0 and frame.groups[p] in ("crystal", "fit"):
                    continue
                frame.put(x, y, part, legend[ch], -np.inf)

    return ov


def _crystal(base: np.ndarray, d: np.ndarray, level: Any, portrait: bool) -> Overlay:
    """The staff crystal: a pointed gem (a kite in screen space, widest a little above the claw)
    split into facets. The facet toward the light is lit, the other one shaded, a ridge runs
    up the middle and one glint sits near the top. Drawn as an overlay so it stays crisp at 5 px."""
    mat = CRYSTAL_DIM if level == "dim" else CRYSTAL
    shade, ridge, lit, glint = CRYSTAL_TONES[level]
    tip3 = base + d * CRYSTAL_LEN
    waist = 0.38
    light = _unit((-0.6, -0.75))  # toward the light, screen space (y down)

    def ov(frame: Frame, cam: Camera) -> None:
        bx, by, bd = cam.project(base)
        tx, ty, td = cam.project(tip3)
        ax_, ay_ = tx - bx, ty - by
        L = math.hypot(ax_, ay_)
        if L < 1e-3:
            return
        a = np.array([ax_ / L, ay_ / L])
        perp = np.array([-a[1], a[0]])
        lit_sgn = 1.0 if perp @ light >= 0.0 else -1.0
        hw = CRYSTAL_HW / cam.scale
        depth = (bd + td) * 0.5 - 0.8
        part = frame.add_part(mat, "crystal")
        cells: list[tuple[int, int, float, float]] = []
        x_lo, x_hi = int(math.floor(min(bx, tx) - hw - 1)), int(math.ceil(max(bx, tx) + hw + 1))
        y_lo, y_hi = int(math.floor(min(by, ty) - hw - 1)), int(math.ceil(max(by, ty) + hw + 1))
        for y in range(y_lo, y_hi + 1):
            for x in range(x_lo, x_hi + 1):
                rel = np.array([x + 0.5 - bx, y + 0.5 - by])
                u = float(rel @ a) / L
                v = float(rel @ perp) * lit_sgn  # > 0: on the light's side
                if not (-0.02 <= u <= 1.0):
                    continue
                prof = u / waist if u < waist else (1.0 - u) / (1.0 - waist)
                if abs(v) <= hw * prof + 0.2:
                    cells.append((x, y, u, v))
        if not cells:
            return
        ridge_w = 0.5 if not portrait else 0.9
        best = None
        for x, y, u, v in cells:
            if abs(v) <= ridge_w:
                i = lit if u > waist else ridge
            elif v > 0:
                i = lit if (u > waist or not portrait) else ridge
            else:
                i = shade if (u <= waist + 0.15 or not portrait) else ridge
                if portrait and u <= waist * 0.6:
                    i = max(0, shade - 1)
            frame.put(x, y, part, i, depth)
            score = u - 0.3 * abs(v - (0.6 if portrait else 0.3))
            if v >= -0.3 and u <= (0.8 if portrait else 0.85) and (best is None or score > best[0]):
                best = (score, x, y)
        if best is not None:
            frame.put(best[1], best[2], part, glint, depth)
            if portrait:
                # A short highlight streak down the lit facet.
                for k in (1, 2):
                    gx = int(math.floor(best[1] + 0.5 - a[0] * k * 1.4))
                    gy = int(math.floor(best[2] + 0.5 - a[1] * k * 1.4))
                    if 0 <= gx < frame.W and 0 <= gy < frame.H and frame.part[gy, gx] == part:
                        frame.idx[gy, gx] = glint - 1 if k == 2 else glint

    return ov


def _ellipse_ring(cx: float, cy: float, a: float, b: float) -> list[tuple[int, int, float]]:
    """Pixels of a clean 1-pixel ellipse outline (centre, half width a, half height b): the inside
    pixels that touch the outside on a side. Each comes with its angle (degrees, 0 = right)."""
    out: list[tuple[int, int, float]] = []

    def inside(x: int, y: int) -> bool:
        return ((x + 0.5 - cx) / a) ** 2 + ((y + 0.5 - cy) / b) ** 2 <= 1.0

    for y in range(int(math.floor(cy - b)) - 1, int(math.ceil(cy + b)) + 2):
        for x in range(int(math.floor(cx - a)) - 1, int(math.ceil(cx + a)) + 2):
            if inside(x, y) and not all(inside(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out.append((x, y, math.degrees(math.atan2(-(y + 0.5 - cy) / b, (x + 0.5 - cx) / a))))
    return out


def _ward(sk: Skeleton, pose: dict[str, Any]) -> Overlay:
    """A glowing ward disc between Cass and the hit: an upright ring seen edge-on (bright on the
    side facing the enemy, dimmer on the far rim), drawn in screen space so it stays crisp."""
    at = _v(pose.get("ward_at", (7.0, -1.5, 0.0)))
    a, b = pose.get("ward_r", (3.0, 8.5))
    c3 = sk["chest"] + sk.torso @ at

    def ov(frame: Frame, cam: Camera) -> None:
        cx, cy, _ = cam.project(c3)
        hi = frame.add_part(FX, "cass_fx")
        for x, y, t in _ellipse_ring(cx, cy, float(a), float(b)):
            front = math.cos(math.radians(t)) > -0.2
            frame.put(x, y, hi, 3 if front else 2, -np.inf)

    return ov


def _eyes(sk: Skeleton, kind: str, portrait: bool) -> Overlay:
    """Two eyes: the near one at the anchor, the far one two pixels toward the face front. Only
    drawn on face pixels, so an eye never sticks out past the cheek."""
    r = BUILD.head_r
    a_n = sk["head"] + sk.head @ _v((r * 0.84, -r * 0.1, r * 0.44))

    def ov(frame: Frame, cam: Camera) -> None:
        if portrait:
            return
        ax, ay, _ = cam.project(a_n)
        x0, y0 = int(math.floor(ax)), int(math.floor(ay))
        if kind == "open":
            cells = [(0, 0), (0, 1), (2, 0), (2, 1)]
        elif kind == "closed":
            # Shut eyes: a short dash each.
            cells = [(-1, 1), (0, 1), (2, 1), (3, 1)]
        else:
            cells = [(0, 1), (2, 1)]
        part = frame.add_part(EYE, "head_eye")
        for dx, dy in cells:
            x, y = x0 + dx, y0 + dy
            if (0 <= x < frame.W and 0 <= y < frame.H and frame.part[y, x] >= 0
                    and frame.groups[frame.part[y, x]] == "head"):
                # The far eye needs face beyond it, or it would merge with the outline.
                if dx >= 2:
                    q = frame.part[y, x + 1] if x + 1 < frame.W else -1
                    if q < 0 or frame.groups[q] != "head":
                        continue
                frame.part[y, x] = part
                frame.idx[y, x] = 0

    return ov


# Portrait face, drawn by hand at portrait size as one picture placed on the projection of the
# nose tip (the "+" cell is the origin and is left as skin). Legend: L lash (ink), l lower lash,
# W eye white, w shaded white, I iris dark, i iris, j iris light, H highlight, b brow,
# n nose shadow, N nose light, m mouth, p lip, c blush.
FACE_STAMPS: dict[str, tuple[tuple[float, float, float], tuple[int, int], list[str]]] = {
    # name: (point on the head in head radii, origin cell, rows)
    "face": ((0.97, -0.33, 0.0), (10, 8), [
        "...................",
        "...bbbb.....bbb....",
        "..b............b...",
        "...................",
        "...LLLL....LLL.....",
        "..LWIIi....WIIL....",
        "...WHIi....WHi.....",
        "...wjji.....ji.....",
        "....ll....+.l......",
        ".cc......N.....c...",
        "..........n........",
        "...................",
        ".......mmm.........",
        "........p..........",
    ]),
}


def _face_portrait(sk: Skeleton) -> Overlay:
    r = BUILD.head_r
    legend: dict[str, tuple[Material, int]] = {
        "L": (EYE, 0), "l": (FACE, 1), "W": (WHITE, 1), "w": (WHITE, 0), "I": (IRIS, 0),
        "i": (IRIS, 2), "j": (IRIS, 3), "H": (WHITE, 1), "b": (HAIR, 0), "n": (FACE, 1),
        "N": (FACE, 4), "m": (FACE, 0), "p": (FACE, 1), "c": (BLUSH, 0),
    }

    def ov(frame: Frame, cam: Camera) -> None:
        parts: dict[str, int] = {}
        for name, (pt, org, rows) in FACE_STAMPS.items():
            ax, ay, _ = cam.project(sk["head"] + sk.head @ (_v(pt) * r))
            x0, y0 = int(math.floor(ax)) - org[0], int(math.floor(ay)) - org[1]
            for ry, row in enumerate(rows):
                for rx, ch in enumerate(row):
                    if ch not in legend:
                        continue
                    x, y = x0 + rx, y0 + ry
                    if not (0 <= x < frame.W and 0 <= y < frame.H):
                        continue
                    p = frame.part[y, x]
                    # Features sit on skin; brows may also cross the fringe.
                    if p < 0 or frame.groups[p] not in (("head", "hair") if ch == "b" else ("head",)):
                        continue
                    mat, i = legend[ch]
                    if mat.name not in parts:
                        parts[mat.name] = frame.add_part(mat, "head")
                    frame.part[y, x] = parts[mat.name]
                    frame.idx[y, x] = i

    return ov


def _hair_strands(frame: Frame, seed: int = 7) -> None:
    """Portrait hair texture: wavy vertical strands, one shade darker in the grooves and one
    lighter on lit crests."""
    from kit.noise import fbm2
    ys, xs = np.nonzero(frame.part >= 0)
    hair = np.array([frame.groups[frame.part[y, x]] == "hair" for y, x in zip(ys, xs)], dtype=bool)
    ys, xs = ys[hair], xs[hair]
    if ys.size == 0:
        return
    warp = fbm2(xs * 0.07, ys * 0.05, seed=seed, octaves=2)
    s = np.sin((xs + 6.0 * warp) * (2.0 * math.pi / 3.4))
    for y, x, v in zip(ys, xs, s):
        m = frame.mats[frame.part[y, x]]
        if v > 0.8:
            frame.idx[y, x] = max(0, frame.idx[y, x] - 1)
        elif v < -0.9 and frame.idx[y, x] >= 2:
            frame.idx[y, x] = min(m.top(), frame.idx[y, x] + 1)


def _contours(frame: Frame, gap: float = 2.5, gap_tight: float = 0.9, steps: int = 2) -> None:
    """kit.post.contours, but arms, hands and gear get a line even close to the body (gold sleeve
    over gold robe would melt together otherwise)."""
    H, W = frame.H, frame.W
    tight = [g.startswith(TIGHT_GROUPS) for g in frame.groups]
    darker = np.zeros((H, W), dtype=bool)
    for y in range(H):
        for x in range(W):
            p = frame.part[y, x]
            if p < 0:
                continue
            for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < W and 0 <= ny < H):
                    continue
                q = frame.part[ny, nx]
                if q < 0 or q == p or frame.groups[q] == frame.groups[p]:
                    continue
                g = gap_tight if (tight[p] or tight[q]) else gap
                if frame.depth[y, x] > frame.depth[ny, nx] + g:
                    darker[y, x] = True
                    break
    frame.idx = np.where(darker, np.maximum(frame.idx - steps, 0), frame.idx)


# --- Rendering ---------------------------------------------------------------------------------


def hero_camera() -> Camera:
    """The hero frame camera, lifted so the boot soles sit on the second-to-last row."""
    return Camera(*specs.HERO_FRAME, cy=-0.5 - LIFT)


def render_frame(pose: dict[str, Any], cam: Camera | None = None, portrait: bool = False) -> Frame:
    """Renders `pose` with its overlays, before contours and outline."""
    cam = cam or hero_camera()
    node, ovs = model(pose, portrait)
    frame = render(node, cam)
    for ov in ovs:
        ov(frame, cam)
    _brim_shadow(frame)
    return frame


def _brim_shadow(frame: Frame) -> None:
    """The hat brim shades what is right under it: one step darker on the first face row and on
    two rows of hair (pixel-art cast shadow; the renderer itself has none)."""
    H, W = frame.H, frame.W
    for x in range(W):
        for y in range(H - 1):
            p = frame.part[y, x]
            if p < 0 or frame.groups[p] != "hat":
                continue
            q = frame.part[y + 1, x]
            if q < 0 or frame.groups[q] not in ("head", "hair", "skin"):
                continue
            for k, rows in ((1, ("head", "hair", "skin")), (2, ("hair",))):
                yy = y + k
                r = frame.part[yy, x] if yy < H else -1
                if r >= 0 and frame.groups[r] in rows:
                    frame.idx[yy, x] = max(0, frame.idx[yy, x] - 1)


def finish_frame(frame: Frame) -> np.ndarray:
    _contours(frame)
    cleanup(frame)
    outline(frame, skip_groups=FX_GROUPS)
    return frame.rgba()


def render_pose(pose: dict[str, Any], cam: Camera | None = None, portrait: bool = False) -> np.ndarray:
    """One finished frame (RGBA) of `pose` (hero frame camera unless `cam` is given)."""
    return finish_frame(render_frame(pose, cam, portrait))


def render_between(a: str, b: str, t: float) -> np.ndarray:
    """An in-between frame from keyframe POSES[a] (t = 0) to POSES[b] (t = 1), for animations."""
    return render_pose(blend(POSES[a], POSES[b], t))


PORTRAIT_SCALE = 0.325  # model units per portrait pixel (the face fills most of the frame)
PORTRAIT_HEAD = (21.0, 24.5)  # where the head centre lands (pixel column, row)


def portrait_camera() -> Camera:
    """Same yaw and pitch as the fighter, closer, centred on the head."""
    sk = skeleton(PORTRAIT_POSE)
    cam = Camera(specs.PORTRAIT, specs.PORTRAIT, scale=PORTRAIT_SCALE)
    v = cam.view(sk["head"])
    cam.cx = float(v[0]) - (PORTRAIT_HEAD[0] - cam.W / 2.0) * cam.scale
    cam.cy = float(v[1]) - (cam.H - 0.5 - PORTRAIT_HEAD[1]) * cam.scale
    return cam


def build(ctx) -> None:
    frames = [render_pose(POSES[name]) for name in specs.HERO_POSES]
    sheet = hstack(frames)
    ctx.save("sprites/characters/%s.png" % ID, sheet, frame_w=specs.HERO_FRAME[0])
    ctx.extra("sheet_1x.png", sheet, scale=1, frame_w=specs.HERO_FRAME[0])
    ctx.extra("sheet_2x.png", sheet, scale=2, frame_w=specs.HERO_FRAME[0])
    por = render_pose(PORTRAIT_POSE, portrait_camera(), portrait=True)
    ctx.save("sprites/portraits/%s.png" % ID, por)
