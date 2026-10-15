"""Enemy attack effects (phase 12): rock spikes for rock ground hits and the projectiles of ranged
hits.

How the game uses them (keep in mind when changing them):
- rock_spike.png is one row of ROCK_FRAMES rock shapes, ROCK_CELL each, feet on the second-to-last
  row. Rows of them burst out of the floor along a lane toward a hero (DESIGN.md 3.10): the game
  stands them up by stretching from the feet, so each must read as a rock at any height, and the
  last row (bigger) stands right in front of the hero. Billboards that turn with the camera.
- <projectile>.png is one row of PROJ_FRAMES cells, PROJ_CELL each, looped while it flies
  (DESIGN.md 3.9). The game moves it along an arc and adds two faint copies behind it, so the
  shape itself needs no motion blur. It must read on dark and light floors at fight scale.

Purple stays the ground-hit colour, so rocks are plain earth and stone (the floor warning and the
wind-up glow already say "jump"). Projectiles carry their monster's colour: bile green, stone
grey, shade violet.
"""
from __future__ import annotations

import math

import numpy as np

from kit.palette import M, Material
from kit.post import finish
from kit.render import Camera, render
from kit.sdf import Ellipsoid, Moved, Prism, Sphere, SmoothUnion, Union, rot

ROCK_CELL = (16, 24)
ROCK_FRAMES = 4
PROJ_CELL = (20, 20)
PROJ_FRAMES = 4

# Freshly torn stone: the world's warm stone, a step brighter so it stands off the floor tiles.
ROCK = Material.make("fx_rock", "#857868", below=2, above=2, wrap=0.25, dither=True)
EARTH = M["dirt"]

# Rock shapes, each a list of spikes: (x of the foot, foot half width, height, lean in pixels
# of the tip to the right, polygon jag (how far the side kinks in)).
ROCK_SHAPES = (
    ((0.0, 4.2, 19.0, 1.5, 0.8),),
    ((-1.8, 3.4, 17.0, -1.5, 0.6), (3.0, 2.6, 11.0, 2.0, 0.5)),
    ((0.5, 5.0, 14.0, 3.0, 1.2),),
    ((-3.0, 2.6, 12.0, -2.0, 0.5), (0.8, 3.4, 20.0, 0.5, 0.7), (4.2, 2.2, 8.0, 1.5, 0.4)),
)


def _spike(m: Material, foot_x: float, half: float, height: float, lean: float, jag: float) -> Prism:
    """A jagged stone shard standing on y = 0: a polygon (front view) extruded toward the viewer."""
    poly = [
        (foot_x - half, 0.0),
        (foot_x - half * 0.75 + lean * 0.3, height * 0.45),
        (foot_x - half * 0.45 + lean * 0.6 - jag, height * 0.7),
        (foot_x + lean, height),
        (foot_x + half * 0.4 + lean * 0.6 + jag, height * 0.62),
        (foot_x + half * 0.85 + lean * 0.25, height * 0.3),
        (foot_x + half, 0.0),
    ]
    return Prism(m, (0.0, 0.0, 0.0), poly, hz=half * 0.8, round=0.6, group="rock",
                 bumps=(0.45, 0.35, int(height * 7 + foot_x * 3) % 97))


def make_rock_spike(shape) -> np.ndarray:
    parts = [_spike(ROCK, *s) for s in shape]
    # A lip of torn-up earth round the feet.
    parts.append(Ellipsoid(EARTH, (0.5, 0.2, 0.0), (6.2, 1.6, 3.0), group="earth",
                           bumps=(0.4, 0.6, 11)))
    model = Union(*parts)
    cam = Camera(*ROCK_CELL)
    return finish(render(model, cam))


def make_rock_sheet() -> np.ndarray:
    return np.concatenate([make_rock_spike(s) for s in ROCK_SHAPES], axis=1)


# --- Projectiles -------------------------------------------------------------------------------

BILE = M["bile"]
BILE_GLOW = M["glow_rot"]
STONE = Material.make("fx_thrown_stone", "#77706a", below=2, above=2, wrap=0.25, dither=True)
EMBER = M["glow_ember"]
CHAR = Material.make("fx_char", "#3e3434", below=1, above=2, wrap=0.25)
MUD = M["bog_mud"]
MUD_WET = Material.make("fx_mud_wet", "#5a5a36", below=2, above=2, wrap=0.3, spec=0.6, spec_power=10.0)
SHADE = M["shade_edge"]
SHADE_GLOW = M["glow_violet"]
LIGHT = Material.make("fx_light", "#fff2b8", below=2, above=1, emissive=True)
LIGHT_HALO = M["glow_amber"]

# Every projectile model is centred here (model units = pixels), in the middle of its cell, and
# drawn K times the size of its first sketch (12 px cells were too small to read in a fight).
CENTRE = (0.0, 9.5, 0.0)
K = 1.6


def _cam() -> Camera:
    return Camera(*PROJ_CELL, yaw=0.0, pitch=0.0)


def _glob(frame: int) -> np.ndarray:
    """A wobbling glob of bile with a glowing rot core: it squashes and stretches as it flies."""
    phase = frame / PROJ_FRAMES * math.tau
    sx = K * (3.6 + 0.6 * math.cos(phase))
    sy = K * (3.4 - 0.5 * math.cos(phase))
    body = Ellipsoid(BILE, CENTRE, (sx, sy, K * 3.2), group="glob")
    drip = Sphere(BILE, (CENTRE[0] + K * (3.0 + 0.4 * math.sin(phase)), CENTRE[1] - K * 1.6, 0.0), K * 1.3, group="glob")
    core = Sphere(BILE_GLOW, (CENTRE[0] - K * 0.6, CENTRE[1] + K * 0.6, K * 2.0), K * 1.4, group="core")
    model = Union(SmoothUnion(body, drip, k=K * 1.6), core)
    return finish(render(model, _cam()), contour_gap=0)


def _stone(frame: int) -> np.ndarray:
    """A lumpy thrown stone that tumbles a full turn per loop."""
    R = rot(0.0, 0.0, frame * 360.0 / PROJ_FRAMES)
    a = Ellipsoid(STONE, (0.0, 0.0, 0.0), (K * 3.8, K * 3.0, K * 3.0), R=R, bumps=(0.6, 0.35, 5))
    b = Ellipsoid(STONE, (K * 1.6, K * 1.4, K * 0.4), (K * 2.0, K * 1.8, K * 2.0), R=R, bumps=(0.5, 0.4, 9))
    model = Moved(SmoothUnion(a, b, k=K * 1.2), CENTRE)
    return finish(render(model, _cam()))


def _bolt(frame: int) -> np.ndarray:
    """A shade bolt: a violet glowing heart in a ragged shadow shell that flickers."""
    phase = frame / PROJ_FRAMES * math.tau
    shell = Ellipsoid(SHADE, CENTRE, (K * (4.0 + 0.4 * math.sin(phase)), K * 3.2, K * 3.0), group="shell",
                      bumps=(0.7, 0.8, 3 + frame))
    tail = Ellipsoid(SHADE, (CENTRE[0] + K * 3.2, CENTRE[1] + K * 0.3 * math.cos(phase), 0.0), (K * 2.0, K * 1.4, K * 1.4),
                     group="shell")
    heart = Sphere(SHADE_GLOW, (CENTRE[0] - K * 0.8, CENTRE[1], K * 2.2), K * (1.7 + 0.3 * math.cos(phase)), group="heart")
    model = Union(SmoothUnion(shell, tail, k=K * 1.5), heart)
    return finish(render(model, _cam()), contour_gap=0)


def _mud(frame: int) -> np.ndarray:
    """A clot of bog mud with a wet sheen and a trailing drip, wobbling as it flies."""
    phase = frame / PROJ_FRAMES * math.tau
    body = Ellipsoid(MUD, CENTRE, (K * (3.7 + 0.4 * math.sin(phase)), K * (3.2 - 0.3 * math.sin(phase)), K * 3.2),
                     group="mud", bumps=(0.6, 0.45, 13 + frame))
    drip = Sphere(MUD, (CENTRE[0] + K * 3.2, CENTRE[1] - K * (1.0 + 0.4 * math.cos(phase)), 0.0), K * 1.2, group="mud")
    sheen = Sphere(MUD_WET, (CENTRE[0] - K * 0.8, CENTRE[1] + K * 1.0, K * 2.2), K * 1.3, group="sheen")
    model = Union(SmoothUnion(body, drip, k=K * 1.4), sheen)
    return finish(render(model, _cam()), contour_gap=0)


def _cinder(frame: int) -> np.ndarray:
    """A burning clinker from the Ashen Husk: charred black stone cracked open on a glowing ember
    heart, tumbling."""
    R = rot(0.0, 0.0, frame * 360.0 / PROJ_FRAMES)
    a = Ellipsoid(CHAR, (0.0, 0.0, 0.0), (K * 3.6, K * 3.0, K * 3.0), R=R, bumps=(0.6, 0.4, 21), group="char")
    core = Ellipsoid(EMBER, (K * 0.6, K * 0.4, K * 1.6), (K * 2.2, K * 1.8, K * 1.6), R=R, group="ember")
    model = Moved(Union(a, core), CENTRE)
    return finish(render(model, _cam()))


def _light(frame: int) -> np.ndarray:
    """Cass's light bolt (card #81): a pale gold heart in a pulsing amber halo, with a short
    comet tail of light."""
    phase = frame / PROJ_FRAMES * math.tau
    halo = Ellipsoid(LIGHT_HALO, CENTRE, (K * (3.4 + 0.5 * math.sin(phase)), K * (3.0 + 0.4 * math.sin(phase)), K * 2.6),
                     group="halo")
    # Heroes stand on the left and cast to the right: the tail trails on the left.
    tail = Ellipsoid(LIGHT_HALO, (CENTRE[0] - K * 3.0, CENTRE[1], 0.0), (K * (2.4 + 0.4 * math.cos(phase)), K * 1.0, K * 1.0),
                     group="halo")
    heart = Sphere(LIGHT, (CENTRE[0] + K * 0.6, CENTRE[1], K * 2.2), K * (1.9 + 0.3 * math.cos(phase)), group="heart")
    model = Union(SmoothUnion(halo, tail, k=K * 1.5), heart)
    return finish(render(model, _cam()), contour_gap=0)


PROJECTILES = {
    "cinder": _cinder,
    "mud_glob": _mud,
    "bile_glob": _glob,
    "thrown_stone": _stone,
    "shade_bolt": _bolt,
    "light_bolt": _light,
}


def make_projectile(name: str) -> np.ndarray:
    return np.concatenate([PROJECTILES[name](f) for f in range(PROJ_FRAMES)], axis=1)


def build(ctx) -> None:
    ctx.save("sprites/fx/rock_spike.png", make_rock_sheet(), frame_w=ROCK_CELL[0])
    for name in PROJECTILES:
        ctx.save("sprites/fx/%s.png" % name, make_projectile(name), frame_w=PROJ_CELL[0])
