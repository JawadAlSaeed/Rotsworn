"""Mark icons (phase 19, cards #252, #262): one small badge per hero mark and ward, drawn on the
hero panels next to the turns left and in the Glossary.

Each icon is a 10x10 hand-drawn shape in three shades of the mark's HUD colour (HudStyle.STATUS_COLORS,
so the badge and the word always agree), inside a 12x12 cell with a 1-pixel ink outline. Shapes are
picked to read at 1x on the dark panel: a drop for rot, a split heart for blight, a down arrow for
weakness, a flame, a lightning bolt, an hourglass for slow, a spiral for daze, a sealed speech bubble
for hush, a crossed shield for the ward, a round buckler for a monster's shield, a gem with an arrow
for the AP drain.
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
