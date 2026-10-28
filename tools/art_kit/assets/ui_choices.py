"""Icons for the side-by-side choice cards (phase 22, card #288): two or three choices sit side by
side as cards, each with a picture and a few words, and what a choice costs or gives shows as small
icon chips instead of a sentence.

Card pictures, 24x24, drawn at 4x on a card (96 px), outlined in the game's ink:
- ui/choice_rest.png: a big red heart (the campfire's Rest: everyone heals).
- ui/choice_train.png: a chunky gold arrow pointing up (Train: attribute points).
- ui/choice_watch.png: an open eye with an amber iris (Keep watch: the team gauge is full).
- ui/choice_forge.png: a hammer over an anvil, a spark flying (Upgrade: a Relic becomes Relic+).
- ui/choice_host.png: a stone beacon with a fire on top, calls going out both ways (Host Online).
- ui/choice_join.png: an open doorway with a gold arrow going in (Join Online).

Chip icons, 12x12, drawn at 3x in a chip (36 px):
- ui/chip_coin.png: gold (a price or a reward).
- ui/chip_heart.png: HP (a heal, or HP paid).
- ui/chip_heart_cracked.png: max HP lost for good (a split heart, darker).
- ui/chip_bag.png: a backpack item (lost, found or given).
- ui/chip_skull.png: a curse (a rotten item), its eyes glowing rot green.
- ui/chip_fight.png: two crossed swords (an ambush fight).
- ui/chip_die.png: a die (the chance a risk strikes).
- ui/chip_up.png: a small gold up arrow (XP, attribute points, a level).
- ui/chip_gauge.png: a flame in the team gauge's orange.
- ui/chip_relic.png: a faceted violet gem (a Relic).
"""
from __future__ import annotations

import numpy as np

from kit.canvas import Canvas
from kit.color import ramp
from kit.palette import INK, M

CARD = 24
CHIP = 12

GOLD = M["gold"].colors
IRON = M["iron"].colors
STONE = M["stone"].colors
WOOD = M["wood"].colors
DARKWOOD = M["wood_dark"].colors
BLADE = M["blade"].colors
LEATHER = M["leather"].colors
BONE = M["bone"].colors
AMBER = M["glow_amber"].colors
EMBER = M["glow_ember"].colors
ROT = M["glow_rot"].colors
VIOLET = M["glow_violet"].colors
# The heart's red, darkest first (the HP bar's low red, a little deeper).
HEART = ramp("#d8343c", below=2, above=2, step_l=0.085)
# A heart lost for good: the same heart, bruised and dull.
BRUISE = ramp("#8e2e48", below=2, above=2, step_l=0.08)
VIOLET_DEEP = ramp(VIOLET[0], below=1, above=0)[0]


def _ascii(size: int, rows: list[str], legend: dict[str, str], outline: bool = True) -> np.ndarray:
    """A hand-drawn icon: each character a colour, '.' clear; then the ink outline around it (and
    inside its holes)."""
    c = Canvas(size, size)
    c.ascii(rows, legend)
    if outline:
        c.outline(INK)
    return c.a


def _thick(c: Canvas, x0: int, y0: int, x1: int, y1: int, color: str) -> None:
    """A 2-pixel line (the line and the one under it)."""
    c.line(x0, y0, x1, y1, color)
    c.line(x0, y0 + 1, x1, y1 + 1, color)


# --- card pictures ---------------------------------------------------------------------------

def make_rest() -> np.ndarray:
    """A big heart, lit from the upper left: a bright glint on the left lobe, the right side and
    the point in shadow."""
    c = Canvas(CARD, CARD)
    for y in range(CARD):
        for x in range(CARD):
            u = (x + 0.5 - 12.0) / 9.3
            v = (10.6 - (y + 0.5)) / 8.6
            if (u * u + v * v - 1.0) ** 3 - u * u * v ** 3 > 0.0:
                continue
            # Light falls from the upper left: closer to that point is brighter.
            d = (u + 0.55) ** 2 + (v - 0.55) ** 2
            idx = 4 if d < 0.05 else 3 if d < 0.45 else 2 if d < 1.5 else 1 if d < 2.6 else 0
            c.px(x, y, HEART[idx])
    c.outline(INK)
    return c.a


def make_train() -> np.ndarray:
    """A chunky arrow pointing up, in worn gold: the left faces lit, the right in shade, a bright
    edge along the head's upper left."""
    return _ascii(CARD, [
        "........................",
        "...........WL...........",
        "..........WLLM..........",
        ".........WLLLMM.........",
        "........WLLLLMMM........",
        ".......WLLLLLMMMM.......",
        "......WLLLLLLMMMMM......",
        ".....WLLLLLLLMMMMMM.....",
        "....WLLLLLLLLMMMMMMM....",
        "...WLLLLLLLLLMMMMMMMd...",
        "...ddddLLLLLLMMMMdddd...",
        ".......LLLLLLMMMMd......",
        ".......LLLLLLMMMMd......",
        ".......LLLLLLMMMMd......",
        ".......LLLLLLMMMMd......",
        ".......LLLLLLMMMMd......",
        ".......LLLLLLMMMMd......",
        ".......LLLLLLMMMMd......",
        ".......LLLLLLMMMMd......",
        ".......LLLLLLMMMMd......",
        ".......dddddddddd.......",
        "........................",
        "........................",
        "........................",
    ], {"W": GOLD[4], "L": GOLD[3], "M": GOLD[2], "d": GOLD[1]})


def make_watch() -> np.ndarray:
    """An open eye, awake in the dark: pale white, an amber iris with a dark pupil and a glint,
    the upper lid heavy with three lashes."""
    return _ascii(CARD, [
        "........................",
        "........................",
        "........................",
        "........................",
        "......l....l....l.......",
        ".......l...l...l........",
        "........lllllll.........",
        ".....llllWWWWWlllll.....",
        "...lllWWWaaaaaWWWWlll...",
        "..llWWWWaAAAAAaWWWWWll..",
        ".llWWWWaAgpppAAaWWWWWll.",
        "lWWWWWWaAApppAAaWWWWWWWl",
        ".sWWWWWaAApppAAaWWWWWWs.",
        "..ssWWWWaAAAAAaWWWWWss..",
        "....sssWWaaaaaWWWsss....",
        ".......ssssssssss.......",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
    ], {"l": INK, "W": BONE[3], "s": BONE[1], "a": EMBER[1], "A": AMBER[2], "p": INK, "g": AMBER[3]})


def make_forge() -> np.ndarray:
    """A hammer raised over an anvil, a spark flying from the anvil's face: a Relic becomes
    Relic+ (the campfire's Upgrade, DESIGN.md 8.25). The anvil is iron with a lit top face and a horn to the left; the hammer has an iron
    head and a wooden handle."""
    return _ascii(CARD, [
        "........................",
        "..........HHHHHHH.......",
        "..........HhhhhhhK......",
        "..........HhhhhhhK......",
        "..........kkkkkkkk......",
        ".............WW.........",
        "............WWw.........",
        "...a.......WWw..........",
        "....a.....WWw...........",
        "..a......WWw............",
        ".....a..WWw.............",
        "...a....ww..............",
        "........................",
        "TTTTTTTTTTTTTTTTTTTT....",
        ".tttIIIIIIIIIIIIIIIi....",
        "...tIIIIIIIIIIIIIIIi....",
        "......IIIIIIIIIIIii.....",
        ".......iIIIIIIIii.......",
        "........IIIIIIIi........",
        "......IIIIIIIIIIii......",
        ".....IIIIIIIIIIIIii.....",
        ".....iiiiiiiiiiiiii.....",
        "........................",
        "........................",
    ], {"H": IRON[4], "h": IRON[3], "K": IRON[2], "k": IRON[1], "W": WOOD[3], "w": WOOD[1],
        "T": IRON[4], "t": IRON[3], "I": IRON[2], "i": IRON[1], "a": AMBER[3]})


def make_host() -> np.ndarray:
    """A stone beacon with a fire on its top and calls going out on both sides: the one who opens
    the game for the others."""
    return _ascii(CARD, [
        "........................",
        "...........f............",
        "..........fF............",
        "..........fFf...........",
        ".........fFYFf..........",
        ".........fYWYf..........",
        "..g......fYWYf......g...",
        ".g...g...BBBBBB...g..g..",
        ".g..g...BSBSSBSB...g.g..",
        "g...g...SSSSSSSs...g..g.",
        "g..g.....SSSSSs.....g.g.",
        "g..g.....SSdSSs.....g.g.",
        "g...g....SddSSs....g..g.",
        ".g..g....SSSSSs....g.g..",
        ".g...g...SSSSSs...g..g..",
        "..g......SSSSSs......g..",
        ".........SSSSSs.........",
        "........SSSSSSss........",
        ".......SSSSSSSsss.......",
        ".......sssssssssss......",
        "........................",
        "........................",
        "........................",
        "........................",
    ], {"f": EMBER[1], "F": EMBER[2], "Y": AMBER[2], "W": AMBER[3], "B": STONE[4], "S": STONE[3],
        "s": STONE[1], "d": INK, "g": GOLD[3]})


def make_join() -> np.ndarray:
    """An open doorway in a wooden frame, dark inside, with a gold arrow going in: joining a game
    someone else opened."""
    return _ascii(CARD, [
        "........................",
        "........................",
        "...........WWWWWWW......",
        "..........WwwwwwwwW.....",
        ".........WwdddddddwW....",
        ".........WwdddddddwW....",
        ".........WwdddddddwW....",
        ".........WwdddddddwW....",
        ".........WwdddddddwW....",
        ".........WwdddddddwW....",
        ".........WwddLddddwW....",
        "..LLLLLLLLLLLLMddddwW...",
        "..MMMMMMMMMMMMMMdddwW...",
        ".........WwddMddddwW....",
        ".........WwdddddddwW....",
        ".........WwdddddddwW....",
        ".........WwdddddddwW....",
        ".........WwdddddddwW....",
        ".........WwdddddddwW....",
        "........WWWWWWWWWWWWW...",
        "........................",
        "........................",
        "........................",
        "........................",
    ], {"W": WOOD[3], "w": WOOD[1], "d": DARKWOOD[0], "L": GOLD[4], "M": GOLD[2]})


def make_coin() -> np.ndarray:
    """A small worn-gold coin lit from the upper left, a darker rim and a stamped mark."""
    c = Canvas(CHIP, CHIP)
    c.ellipse(6.0, 6.0, 5.0, 5.0, GOLD[2])
    c.ellipse(5.6, 5.6, 4.0, 4.0, GOLD[3])
    c.ellipse(6.0, 6.0, 1.6, 1.6, GOLD[2])
    c.px(3, 3, GOLD[4])
    c.px(4, 2, GOLD[4])
    c.px(2, 4, GOLD[4])
    c.outline(INK)
    return c.a


_HEART_ROWS = [
    "............",
    "............",
    "..WLL..LMM..",
    ".WLLLLLMMMd.",
    ".LLLLLMMMMd.",
    ".LLLLMMMMdd.",
    "..LLMMMMdd..",
    "...MMMMdd...",
    "....MMdd....",
    ".....dd.....",
    "............",
    "............",
]


def make_heart() -> np.ndarray:
    """A small red heart: HP healed or paid."""
    return _ascii(CHIP, _HEART_ROWS, {"W": HEART[4], "L": HEART[3], "M": HEART[2], "d": HEART[1]})


def make_heart_cracked() -> np.ndarray:
    """The heart bruised and split down the middle: max HP lost for good."""
    rows = [list(r) for r in _HEART_ROWS]
    for x, y in ((6, 3), (5, 4), (6, 5), (5, 6), (6, 7)):
        rows[y][x] = "."
    return _ascii(CHIP, ["".join(r) for r in rows], {"W": BRUISE[4], "L": BRUISE[3], "M": BRUISE[2],
                                                      "d": BRUISE[1]})


def make_bag() -> np.ndarray:
    """A leather sack tied with gold: a backpack item."""
    return _ascii(CHIP, [
        "............",
        ".....LM.....",
        "....LLMd....",
        ".....GG.....",
        "....LLMd....",
        "...LLLMMd...",
        "..LLLLMMMd..",
        "..LLLMMMMd..",
        "..LLMMMMdd..",
        "...dddddd...",
        "............",
        "............",
    ], {"L": LEATHER[4], "M": LEATHER[3], "d": LEATHER[1], "G": GOLD[3]})


def make_skull() -> np.ndarray:
    """A bone skull with rot-green eyes: a curse."""
    return _ascii(CHIP, [
        "............",
        "...WLLLLM...",
        "..WLLLLLMM..",
        "..LLLLLLMM..",
        "..LggLLggM..",
        "..LggLLggM..",
        "..LLLddLMM..",
        "...LLLLMM...",
        "...LdLLdM...",
        "...LLLLMM...",
        "............",
        "............",
    ], {"W": BONE[4], "L": BONE[3], "M": BONE[1], "d": INK, "g": ROT[1]})


def make_fight() -> np.ndarray:
    """Two swords crossed, points up: a fight."""
    c = Canvas(CHIP, CHIP)
    for mirror in (True, False):
        def X(x: int) -> int:
            return CHIP - 1 - x if mirror else x
        c.line(X(1), 1, X(7), 7, BLADE[4])
        c.line(X(1), 2, X(6), 7, BLADE[2])
        c.line(X(5), 9, X(9), 5, GOLD[3])
        c.px(X(8), 8, LEATHER[2])
        c.px(X(9), 9, LEATHER[2])
        c.px(X(10), 10, GOLD[2])
    c.outline(INK)
    return c.a


def make_die() -> np.ndarray:
    """A bone die showing five: the chance a risk strikes."""
    return _ascii(CHIP, [
        "............",
        ".WWWWWWWWWL.",
        ".WppWWWWppL.",
        ".WppWWWWppL.",
        ".WWWWWWWWWs.",
        ".WWWWppWWWs.",
        ".WWWWppWWWs.",
        ".WWWWWWWWWs.",
        ".LppWWWWpps.",
        ".LppWWWWpps.",
        ".Lssssssss..",
        "............",
    ], {"W": BONE[3], "L": BONE[2], "s": BONE[0], "p": INK})


def make_up() -> np.ndarray:
    """A small gold arrow pointing up: XP, attribute points, a level."""
    return _ascii(CHIP, [
        "............",
        ".....LM.....",
        "....LLMM....",
        "...LLLMMd...",
        "..LLLLMMMd..",
        ".LLLLLMMMMd.",
        "....LLMd....",
        "....LLMd....",
        "....LLMd....",
        "....LLMd....",
        "............",
        "............",
    ], {"L": GOLD[4], "M": GOLD[3], "d": GOLD[1]})


def make_gauge() -> np.ndarray:
    """A flame in the team gauge's orange, white-hot at its heart."""
    return _ascii(CHIP, [
        "............",
        "......L.....",
        ".....LL.....",
        ".....LMM....",
        "....LLMM.L..",
        "...LLYMMML..",
        "..LLYYYMMd..",
        "..LYYWYYMd..",
        "..LYWWWYMd..",
        "...LYWYMd...",
        "....dddd....",
        "............",
    ], {"L": EMBER[2], "M": EMBER[1], "d": EMBER[0], "Y": AMBER[2], "W": AMBER[3]})


def make_relic() -> np.ndarray:
    """A faceted violet gem lit from the upper left: a Relic."""
    return _ascii(CHIP, [
        "............",
        ".....LM.....",
        "....LHMd....",
        "...LHHMdd...",
        "..LHHHMddd..",
        ".LHHHHMdddd.",
        ".bbbbbcccce.",
        "..bbbbccce..",
        "...bbbcce...",
        "....bbce....",
        ".....be.....",
        "............",
    ], {"H": VIOLET[3], "L": VIOLET[2], "M": VIOLET[1], "d": VIOLET[0], "b": VIOLET[1], "c": VIOLET[0],
        "e": VIOLET_DEEP})


CARDS = {
    "choice_rest": make_rest, "choice_train": make_train,
    "choice_watch": make_watch, "choice_forge": make_forge, "choice_host": make_host,
    "choice_join": make_join,
}
CHIPS = {
    "chip_coin": make_coin, "chip_heart": make_heart, "chip_heart_cracked": make_heart_cracked,
    "chip_bag": make_bag, "chip_skull": make_skull, "chip_fight": make_fight, "chip_die": make_die,
    "chip_up": make_up, "chip_gauge": make_gauge, "chip_relic": make_relic,
}


def _sheet(parts: list[np.ndarray], scale: int, gap: int = 4) -> np.ndarray:
    """The icons side by side at `scale` on the cards' dark ink, for review."""
    big = [np.repeat(np.repeat(p, scale, axis=0), scale, axis=1) for p in parts]
    h = max(b.shape[0] for b in big) + gap * 2
    w = sum(b.shape[1] for b in big) + gap * (len(big) + 1)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[...] = (8, 6, 10, 255)
    x = gap
    for b in big:
        alpha = b[..., 3:4].astype(np.float64) / 255.0
        area = out[gap:gap + b.shape[0], x:x + b.shape[1], :3].astype(np.float64)
        out[gap:gap + b.shape[0], x:x + b.shape[1], :3] = (b[..., :3] * alpha + area * (1.0 - alpha)).astype(np.uint8)
        x += b.shape[1] + gap
    return out


def build(ctx) -> None:
    cards = {name: fn() for name, fn in CARDS.items()}
    chips = {name: fn() for name, fn in CHIPS.items()}
    for name, img in cards.items():
        ctx.save("sprites/ui/%s.png" % name, img, scale=8)
    for name, img in chips.items():
        ctx.save("sprites/ui/%s.png" % name, img, scale=8)
    ctx.extra("cards_4x.png", _sheet(list(cards.values()), 4), scale=1)
    ctx.extra("chips_3x.png", _sheet(list(chips.values()), 3), scale=1)
