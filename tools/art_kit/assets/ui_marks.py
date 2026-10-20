"""Mark icons (phase 19, cards #252, #262; every status since phase 22): one small badge per
status, drawn on the hero panels and the enemy panels next to the turns left, on a marking hit in
an attack's hit row, and in the Glossary.

Each icon is a 10x10 hand-drawn shape in three shades of the status's HUD colour
(HudStyle.STATUS_COLORS, so the badge and the word always agree), inside a 12x12 cell with a
1-pixel ink outline. Shapes are picked to read at 1x on the dark panel: a drop for rot, a split
heart for blight, a down arrow for weakness, a flame, a lightning bolt, an hourglass for slow, a
spiral for daze, a sealed speech bubble for hush, a crossed shield for the ward, a round buckler
for a monster's shield, a gem with an arrow for the AP drain; and (phase 22) a cracked shield for
exposed, a helmet for guard, a "!" for taunted, crossed swords for riposte, two drops for bleeding,
a plus for renew, a crosshair for Death Mark, an up arrow for empowered and dizzy stars for a
staggered enemy (not a status: CombatVisuals.stagger_text_color).
"""
from __future__ import annotations

import numpy as np

from kit.canvas import Canvas
from kit.color import from_oklch, ramp, to_oklch
from kit.palette import INK

SIZE = 12

# Mirrors HudStyle.STATUS_COLORS (scripts/combat/presentation/hud_style.gd), as hex.
COLORS = {
    "rotting": (0.68, 0.86, 0.22),
    "blighted": (0.82, 0.45, 0.88),
    "weakened": (0.72, 0.74, 0.84),
    "burning": (1.0, 0.5, 0.18),
    "shocked": (1.0, 0.95, 0.42),
    "slowed": (0.7, 0.6, 1.0),
    "dazed": (1.0, 0.68, 0.72),
    "hushed": (0.52, 0.58, 0.95),
    "warded": (0.96, 0.94, 0.72),
    "shielded": (0.62, 0.86, 0.92),
    "ap_drain": (0.55, 0.88, 1.0),
    # Phase 22: the other statuses, so every badge on a panel is an icon.
    "exposed": (1.0, 0.55, 0.3),
    "guarded": (0.55, 0.8, 1.0),
    "taunted": (1.0, 0.4, 0.4),
    "riposte": (1.0, 0.85, 0.35),
    "bleeding": (0.9, 0.2, 0.25),
    "regen": (0.45, 1.0, 0.5),
    "marked": (1.0, 0.3, 0.7),
    "empowered": (1.0, 0.75, 0.3),
    # Mirrors CombatVisuals.stagger_text_color.
    "staggered": (0.6, 0.85, 1.0),
}

SHAPES = {
    "rotting": [
        "....M.....",
        "....M.....",
        "...MLM....",
        "...MLM....",
        "..MLLLM...",
        "..MLLMM...",
        ".MLLMMMD..",
        ".MLMMMMD..",
        "..MMMMD...",
        "...DDD....",
    ],
    "blighted": [
        ".MM...MM..",
        "MLLM.MLLM.",
        "MLLLMLLLM.",
        "MLLL.LLMM.",
        ".MLL.LMMD.",
        "..ML.LMD..",
        "...M.MD...",
        "....MD....",
        "..........",
        "..........",
    ],
    "weakened": [
        "...MMMM...",
        "...MLLM...",
        "...MLLM...",
        "...MLLM...",
        ".MMMLLMMM.",
        "..MLLLLD..",
        "...MLLD...",
        "....MD....",
        "..........",
        "..........",
    ],
    "burning": [
        "....L.....",
        "....LM....",
        "...LMM..L.",
        "..LMMM..M.",
        "..LMLMMMM.",
        ".LMLLLMMD.",
        ".MMLLLLMD.",
        ".MMLLLLMD.",
        "..DMLLMD..",
        "...DDDD...",
    ],
    "shocked": [
        ".....LLL..",
        "....LLM...",
        "...LLM....",
        "..LLMMLL..",
        "..MMMLLM..",
        ".....LM...",
        "....LM....",
        "...LM.....",
        "..LM......",
        "..M.......",
    ],
    "slowed": [
        ".DDDDDDDD.",
        "..MLLLLM..",
        "..MLLLLM..",
        "...MLLM...",
        "....LM....",
        "....ML....",
        "...M..M...",
        "..M.LL.M..",
        "..MLLLLM..",
        ".DDDDDDDD.",
    ],
    "dazed": [
        "..MMMMM...",
        ".M.....M..",
        "M..LLL..M.",
        "M.L...L.M.",
        "M.L.L.L.M.",
        "M.L..LL.M.",
        "M..L....M.",
        ".M..LLLL..",
        "..M.......",
        "...MMMMM..",
    ],
    "hushed": [
        "..MMMMMM..",
        ".MLLLLLLM.",
        "MLLLLLLLLM",
        "MLDDDDDDLM",
        "MLLLLLLLLM",
        ".MLLLLLLM.",
        "..MMMMMM..",
        "...MM.....",
        "..MM......",
        "..........",
    ],
    "warded": [
        ".DMMMMMMD.",
        ".MLLLLLLM.",
        ".MLLMMLLM.",
        ".MLMMMMLM.",
        ".MLLMMLLM.",
        ".MLLMMLLM.",
        "..MLLLLM..",
        "...MLLM...",
        "....MM....",
        "..........",
    ],
    "shielded": [
        "...MMMM...",
        "..MLLLLM..",
        ".MLLMMLLM.",
        ".MLMDDMLM.",
        ".MLMDDMLM.",
        ".MLLMMLLM.",
        "..MLLLLM..",
        "...MMMM...",
        "..........",
        "..........",
    ],
    "ap_drain": [
        "....MM....",
        "...MLLM...",
        "..MLLLLM..",
        "...MLLM...",
        "....MM....",
        "..........",
        "....DD....",
        "....DD....",
        "..DDDDDD..",
        "...DDDD...",
    ],
    # A shield with a crack down it (the crack fills with the ink outline).
    "exposed": [
        "MMMMMMMMD.",
        "MLLLL.LMD.",
        "MLLL.LLMD.",
        "MLLLL.LMD.",
        "MLLL.LLMD.",
        "MLLLL.LMD.",
        ".MLL.LMD..",
        "..MLL.D...",
        "...MDD....",
        "....D.....",
    ],
    # A helmet with a T-shaped visor.
    "guarded": [
        "..MMMMM...",
        ".MLLLLLM..",
        "MLLLLLLLM.",
        "ML.....LD.",
        "MLLL.LLLD.",
        "MLLL.LLLD.",
        "MLL...LLD.",
        ".ML...LD..",
        "..........",
        "..........",
    ],
    "taunted": [
        "...MMMM...",
        "...MLLM...",
        "...MLLM...",
        "...MLLD...",
        "....MD....",
        "....MD....",
        "..........",
        "....MM....",
        "...MLLD...",
        "....DD....",
    ],
    # Two blades crossed, their guards and pommels at the bottom.
    "riposte": [
        "L........L",
        ".L......L.",
        "..M....M..",
        "...M..M...",
        "....MM....",
        "..D.MM.D..",
        "...M..M...",
        "..D.DD.D..",
        ".D......D.",
        "M........M",
    ],
    # A big drop and a small one (rot is a single drop).
    "bleeding": [
        "..M.......",
        "..M....M..",
        ".MLM...M..",
        ".MLM..MLM.",
        "MLLLM.MLD.",
        "MLLMM..D..",
        "MLMMMD....",
        "MMMMMD....",
        ".MMMD.....",
        "..DD......",
    ],
    "regen": [
        "...MMMM...",
        "...MLLM...",
        "...MLLM...",
        "MMMMLLMMMM",
        "MLLLLLLLLD",
        "MLLLLLLLLD",
        "MMMMLLMDDD",
        "...MLLD...",
        "...MLLD...",
        "...MDDD...",
    ],
    # A crosshair: the next skills on it hit harder.
    "marked": [
        "...MLM....",
        ".MM.L.MM..",
        ".M..L..M..",
        "M.......M.",
        "LLL.M.LLL.",
        "M.......M.",
        ".M..L..M..",
        ".MM.L.MM..",
        "...MLM....",
        "..........",
    ],
    # Weakness's arrow turned up.
    "empowered": [
        "....ML....",
        "...MLLM...",
        "..MLLLLM..",
        ".MMMLLMMM.",
        "...MLLM...",
        "...MLLM...",
        "...MLLD...",
        "...MDDD...",
        "..........",
        "..........",
    ],
    # Dizzy stars: a big sparkle, a small one and a speck.
    "staggered": [
        "...L......",
        "...L......",
        "..MLM.....",
        "LLLLLLL...",
        "..MLM.....",
        "...L....M.",
        "...L...MLM",
        "........M.",
        ".M........",
        "..........",
    ],
}


def _hex(rgb: tuple[float, float, float]) -> str:
    return "#%02x%02x%02x" % tuple(int(round(c * 255)) for c in rgb)


def make(mark: str) -> np.ndarray:
    base = _hex(COLORS[mark])
    shades = ramp(base, below=2, above=1, step_l=0.12)
    legend = {"D": shades[0], "M": shades[2], "L": shades[3]}
    c = Canvas(SIZE, SIZE)
    c.ascii(SHAPES[mark], legend, 1, 1)
    c.outline(INK)
    return c.a


def build(ctx) -> None:
    for mark in SHAPES:
        ctx.save("sprites/ui/mark_%s.png" % mark, make(mark))
