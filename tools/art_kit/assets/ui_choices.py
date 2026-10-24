"""Icons for the side-by-side choice cards (phase 22, card #288): two or three choices sit side by
side as cards, each with a picture and a few words, and what a choice costs or gives shows as small
icon chips instead of a sentence.

Card pictures, 24x24, drawn at 4x on a card (96 px), outlined in the game's ink:
- ui/choice_rest.png: a big red heart (the campfire's Rest: everyone heals).
- ui/choice_train.png: a chunky gold arrow pointing up (Train: attribute points).
- ui/choice_upgrade.png: a hammer over an anvil, a spark flying (Upgrade: an item goes up a level).
- ui/choice_watch.png: an open eye with an amber iris (Keep watch: the team gauge is full).
- ui/choice_sharpen.png: a blade drawn across a whetstone, sparks off the edge (Sharpen: more AP).
- ui/choice_host.png: a stone beacon with a fire on top, calls going out both ways (Host Online).
- ui/choice_join.png: an open doorway with a gold arrow going in (Join Online).
- ui/choice_heal.png: a round red flask, corked, a white heart glinting in it (Fight Rush: Heal).
- ui/choice_fight.png: two swords crossed, points up (Fight Rush: the next fight).
- ui/choice_party.png: three small heads side by side (Fight Rush: the party screen).
- ui/choice_run.png: a road winding up a hill to a red flag (the main menu's New Run cards: Run).
- ui/choice_rush.png: a sword across four tally marks (the main menu's New Run cards: Fight Rush).

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
# The flask's empty glass, darkest first.
GLASS = M["steel"].colors
SKIN = M["skin"].colors
HAIR_AUBURN = M["hair_auburn"].colors
HAIR_BLACK = M["hair_black"].colors
HAIR_BROWN = M["hair_brown"].colors
CLOTH_BLUE = M["cloth_blue"].colors
CLOTH_RED = M["cloth_red"].colors
CLOTH_PURPLE = M["cloth_purple"].colors
GRASS = M["grass"].colors
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


def make_upgrade() -> np.ndarray:
    """A hammer raised over an anvil, a spark flying from the anvil's face: the item goes up a
    level. The anvil is iron with a lit top face and a horn to the left; the hammer has an iron
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


def make_sharpen() -> np.ndarray:
    """A blade drawn across a whetstone: the stone a grey block with a lit top, the blade a
    steel diagonal with a gold crossguard, sparks flying off the edge where they meet."""
    return _ascii(CARD, [
        "........................",
        ".....................W..",
        "....................WL..",
        "...................WLs..",
        "..................WLs...",
        ".................WLs....",
        "................WLs.....",
        "...............WLs......",
        "..............WLs.......",
        ".......a.....WLs........",
        "....a.......WLs.........",
        "......a....WLs..a.......",
        "..a.......WLs.....a.....",
        "....a....WLs............",
        ".......GWLs.............",
        "......GgKs..............",
        ".....pPgG...............",
        "...QpP.gG...............",
        "...QQSSSSSSSSSSSSSS.....",
        "....sSSSSSSSSSSSSSSd....",
        "....ssssssssssssssdd....",
        ".....dddddddddddddd.....",
        "........................",
        "........................",
    ], {"W": BLADE[4], "L": BLADE[3], "s": STONE[2], "G": GOLD[3], "g": GOLD[1], "K": GOLD[4],
        "P": LEATHER[3], "p": LEATHER[1], "Q": GOLD[2], "S": STONE[4], "d": STONE[1], "a": AMBER[3]})


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


def make_heal() -> np.ndarray:
    """A round flask of red draught, corked: the liquid lit from the upper left, an empty band of
    glass over it, and a small white heart glinting in the red (the Heal card)."""
    c = Canvas(CARD, CARD)
    cx, cy, r = 12.0, 15.0, 7.6
    for y in range(CARD):
        for x in range(CARD):
            dx = x + 0.5 - cx
            dy = y + 0.5 - cy
            if dx * dx + dy * dy > r * r:
                continue
            if y < 11:
                c.px(x, y, GLASS[3] if dx < -3.0 else GLASS[1])
                continue
            d = (dx + 3.2) ** 2 + (dy + 2.0) ** 2
            idx = 3 if d < 12.0 else 2 if d < 40.0 else 1 if d < 75.0 else 0
            c.px(x, y, HEART[idx])
    # The surface of the draught, a brighter line.
    for x in range(6, 18):
        if c.a[11, x, 3] > 0:
            c.px(x, 11, HEART[4])
    # The neck, its rim and the cork.
    c.rect(10, 4, 13, 8, GLASS[2])
    c.px(10, 5, GLASS[4])
    c.px(10, 6, GLASS[4])
    c.rect(9, 3, 14, 3, GLASS[4])
    c.rect(10, 1, 13, 2, WOOD[3])
    c.px(13, 1, WOOD[1])
    c.px(13, 2, WOOD[1])
    # A streak of light down the left of the glass.
    c.px(6, 10, GLASS[4])
    c.px(5, 12, HEART[4])
    c.px(5, 13, HEART[4])
    # The heart glint.
    for x, y in ((8, 13), (10, 13), (7, 14), (8, 14), (9, 14), (10, 14), (11, 14), (8, 15), (9, 15),
                 (10, 15), (9, 16)):
        c.px(x, y, BONE[4])
    c.outline(INK)
    return c.a


def make_fight_card() -> np.ndarray:
    """Two swords crossed, points up, steel blades with a bright edge, gold guards and leather
    grips: the next fight."""
    c = Canvas(CARD, CARD)
    for mirror in (False, True):
        def X(x: int) -> int:
            return CARD - 1 - x if mirror else x
        c.line(X(2), 1, X(15), 14, BLADE[4])
        c.line(X(1), 2, X(14), 15, BLADE[2])
        c.line(X(2), 2, X(14), 14, BLADE[3])
        c.line(X(13), 17, X(17), 13, GOLD[3])
        c.line(X(14), 17, X(17), 14, GOLD[1])
        c.line(X(16), 16, X(19), 19, LEATHER[3])
        c.line(X(16), 17, X(18), 19, LEATHER[1])
        c.px(X(20), 20, GOLD[3])
        c.px(X(21), 21, GOLD[2])
        c.px(X(20), 21, GOLD[1])
        c.px(X(21), 20, GOLD[2])
    c.outline(INK)
    return c.a


def make_party() -> np.ndarray:
    """Three small heads side by side, each with their shoulders: auburn hair in blue, black hair
    in red (in front, a little higher), brown hair in purple (the party screen)."""
    head = [
        ".HHHH.",
        "HHHHHh",
        "HhSSSh",
        "SeSSeS",
        "SSSSSs",
        ".ssss.",
        "..ss..",
        ".CCCc.",
        "CCCCCc",
        "CCCCCc",
        "CCCCcc",
        "cccccc",
    ]
    c = Canvas(CARD, CARD)
    # The one in front stands higher, its shoulders reaching as low as the others'.
    figures = (
        (2, 7, HAIR_AUBURN, CLOTH_BLUE, 0),
        (16, 7, HAIR_BROWN, CLOTH_PURPLE, 0),
        (9, 5, HAIR_BLACK, CLOTH_RED, 2),
    )
    for x, y, hair, cloth, taller in figures:
        rows = head[:-1] + ["CCCCCc"] * taller + head[-1:]
        c.ascii(rows, {"H": hair[3], "h": hair[1], "S": SKIN[3], "s": SKIN[1], "e": INK,
                       "C": cloth[3], "c": cloth[1]}, x, y)
    c.outline(INK)
    return c.a


def make_run() -> np.ndarray:
    """A green hill lit from the upper left, a pale road winding up it (wide at its foot, swinging
    right, then left) to a red flag on the top: the run, a journey across the map to its last
    fight."""
    c = Canvas(CARD, CARD)
    # The hill: a dome from the bottom row up to its top under the flag.
    top, bottom, cx, rx = 9, 21, 11.5, 11.4
    ry = bottom + 1 - top
    for y in range(top, bottom + 1):
        for x in range(CARD):
            u = (x + 0.5 - cx) / rx
            v = (bottom + 1 - (y + 0.5)) / ry
            if u * u + v * v > 1.0:
                continue
            d = (u + 0.45) ** 2 + (v - 0.75) ** 2
            c.px(x, y, GRASS[2 if d < 0.35 else 1 if d < 1.1 else 0])
    # The road's middle at a few heights (y, x), eased in between; it narrows as it climbs.
    bends = [(21.5, 7.5), (19.0, 13.5), (16.5, 15.5), (14.5, 11.5), (12.5, 9.0), (10.5, 11.5)]

    def middle(y: float) -> float:
        for (y0, x0), (y1, x1) in zip(bends, bends[1:]):
            if y1 <= y <= y0:
                t = (y0 - y) / (y0 - y1)
                t = t * t * (3.0 - 2.0 * t)
                return x0 + (x1 - x0) * t
        return bends[-1][1]

    road_top = top + 1
    for y in range(road_top, bottom + 1):
        half = 0.7 + 2.0 * (y - road_top) / float(bottom - road_top)
        mid = middle(y + 0.5)
        xs = [x for x in range(CARD) if abs(x + 0.5 - mid) <= half]
        for x in xs:
            c.px(x, y, BONE[2])
        if xs:
            c.px(xs[0], y, BONE[3])
            if len(xs) > 2:
                c.px(xs[-1], y, BONE[1])
    # The flag on the hilltop: a wooden pole, a gold knob, a swallowtail pennant waving right.
    pole = 11
    c.px(pole, 1, GOLD[4])
    c.rect(pole, 2, pole, top, WOOD[3])
    for y, x1 in ((2, 18), (3, 19), (4, 18), (5, 17), (6, 18), (7, 19)):
        cloth = CLOTH_RED[3] if y == 2 else CLOTH_RED[1] if y == 7 else CLOTH_RED[2]
        c.rect(pole + 1, y, x1, y, cloth)
    c.px(pole + 1, 2, CLOTH_RED[4])
    c.outline(INK)
    return c.a


def make_rush() -> np.ndarray:
    """Four tally marks scratched in bone, and a sword laid across them as the fifth stroke, point
    up and to the right: Fight Rush, one fight after another, counted."""
    c = Canvas(CARD, CARD)
    # The marks, each two pixels wide (lit left, shaded right) and a little uneven in height.
    for x, top, bottom in ((4, 5, 19), (8, 4, 19), (12, 5, 20), (16, 4, 19)):
        c.rect(x, top, x, bottom, BONE[3])
        c.rect(x + 1, top, x + 1, bottom, BONE[1])
        c.px(x, top, BONE[4])
    # The sword: a steel blade from the point (upper right) down to a gold guard, a leather grip
    # and a gold pommel at the lower left.
    c.line(21, 2, 9, 14, BLADE[4])
    c.line(22, 2, 10, 14, BLADE[3])
    c.line(22, 3, 10, 15, BLADE[2])
    c.line(6, 13, 11, 18, GOLD[3])
    c.line(6, 14, 10, 18, GOLD[1])
    c.line(7, 16, 4, 19, LEATHER[3])
    c.line(8, 16, 5, 19, LEATHER[1])
    c.px(3, 20, GOLD[3])
    c.px(2, 21, GOLD[2])
    c.px(3, 21, GOLD[1])
    c.px(2, 20, GOLD[4])
    c.outline(INK)
    return c.a


# --- chip icons ------------------------------------------------------------------------------

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
    "choice_rest": make_rest, "choice_train": make_train, "choice_upgrade": make_upgrade,
    "choice_watch": make_watch, "choice_sharpen": make_sharpen, "choice_host": make_host,
    "choice_join": make_join, "choice_heal": make_heal, "choice_fight": make_fight_card,
    "choice_party": make_party, "choice_run": make_run, "choice_rush": make_rush,
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
