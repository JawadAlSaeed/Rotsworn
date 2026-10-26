"""Backpack items (DESIGN.md 8.1) and the treasure stop's chest.

An item's icon covers its whole shape on the backpack grid, unturned: ITEM_CELL pixels per grid
cell, so a 1x2 item is 16x32. Cells outside an L-shaped item stay clear. The game draws the icon
over the item's cells with nearest filtering and turns it with the item. Icons are hand-drawn
pixel grids (fully opaque or clear) with the kit's dark ink outline, lit from the upper left.

- salve.png (1x1): a clay pot of green ointment with a wooden lid.
- feast.png (2x1): a long loaf of bread with a roast leg lying on it.
- bomb.png (1x1): a round iron bomb with a lit fuse.
- smelling_salts.png (1x1): a small stoppered vial of glowing green salts.
- silver_ring.png (1x1), rot_gem.png (1x1), golden_idol.png (1x2): treasure, only worth gold.
- Charms (they help just by being in the backpack). Stones: ember_stone, iron_stone (1x1),
  lodestone (2x2, boosts touching stones). Bones: knucklebone, wolf_tooth (1x1), bone_totem (1x3,
  boosts touching bones). Herbs: heartleaf (1x1), wake_root (L), rain_pouch (1x1, boosts touching
  herbs). Rotten: rotting_heart (1x1), grave_moss (2x1), sickly green and violet.
- antidote.png (1x1): a slim corked vial of teal antidote with a leaf at its neck (phase 19).
- holy_water.png (1x1): a round flask of glowing pale holy water, gold stopper and band (phase 19).
- env/chest_closed.png, env/chest_open.png: the treasure stop's chest (DESIGN.md 8.8; it was the
  locked chest in a zone until phase 26, 8.22, which also took the Key and the glinting spot away).
- ui/backpack_5.png: the party's open backpack seen from the front (its lining as tall as the old
  grid's 5 rows), drawn behind the pack's pockets at BACKPACK_SCALE. The lining is COLS x 5 CELL
  art pixels with GAP between cells, its top-left at backpack_origin(); since card #332 the game
  sews its 4 pockets on it, two to a row. data/presentation/combat_visuals.tres holds the same
  numbers for the game. (The 6 and 7 row versions went with the Bigger Pack, card #332.)
"""
from __future__ import annotations

import numpy as np

from kit.canvas import Canvas
from kit.color import ramp
from kit.palette import INK, M

ITEM_CELL = 16

# The backpack art (art pixels; the game scales it up by BACKPACK_SCALE).
BACKPACK_SCALE = 4
CELL = 23
GAP = 1
COLS = 4
STRAP = 5  # shoulder straps showing at both sides
WALL = 7  # the body's side walls
PAD = 2  # lining showing around the grid
ROLL = 15  # the bedroll strapped across the top
RIM = 6  # the leather rim of the opening
POCKET = 18  # the front pocket under the opening

WOOD = M["wood"].colors
CLAY = M["bone"].colors
HERB = M["moss"].colors
GLASS = M["blade"].colors
BLANKET = M["cloth_red"].colors
GOLD = M["gold"].colors
CRUST = M["cloth_gold"].colors
MEAT = M["leather"].colors
CANVAS = M["canvas"].colors
LEATHER = M["leather"].colors
LINING = M["cloth_charcoal"].colors
IRON = M["iron"].colors
STEEL = M["steel"].colors
ROT = M["glow_rot"].colors
VIOLET = M["glow_violet"].colors
PURPLE = M["rot_purple"].colors
DARKWOOD = M["wood_dark"].colors
EMBER = M["glow_ember"].colors
STONE_RAMP = M["stone"].colors
# Phase 19: the Antidote's pale teal and Holy Water's glowing pale gold.
TEAL = ramp("#5fb8a8", below=2, above=1, step_l=0.09)
HOLY = ramp("#d8d09a", below=1, above=2, step_l=0.08)

def _draw(w: int, h: int, rows: list[str], legend: dict[str, str]) -> np.ndarray:
    for r in rows:
        if len(r) != w:
            raise ValueError("row %r is %d wide, want %d" % (r, len(r), w))
    if len(rows) != h:
        raise ValueError("%d rows, want %d" % (len(rows), h))
    c = Canvas(w, h)
    c.ascii(rows, legend)
    c.outline(INK)
    return c.a


def make_salve() -> np.ndarray:
    """A squat clay pot with a wooden lid and a green herb label."""
    return _draw(16, 16, [
        "................",
        "................",
        ".....LLLLLL.....",
        "....LllllllL....",
        "....dddddddd....",
        "...JJJJJJJJjj...",
        "...JggggggGjj...",
        "...JgHGGGGGjk...",
        "...JgGhhGGGjk...",
        "...JgGGGGGGjk...",
        "...JggggggGjk...",
        "...JJjjjjjjjk...",
        "....jjjjjjjk....",
        "................",
        "................",
        "................",
    ], {"L": WOOD[3], "l": WOOD[2], "d": WOOD[1], "J": CLAY[3], "j": CLAY[2], "k": CLAY[1],
        "g": HERB[3], "G": HERB[2], "H": HERB[4], "h": HERB[1]})


def make_antidote() -> np.ndarray:
    """A slim corked vial of pale teal antidote with a green leaf tied to its neck (phase 19)."""
    return _draw(16, 16, [
        "................",
        "......CCc.......",
        "......CCc.......",
        "......NWn.......",
        "......NWn.gG....",
        ".....NWTTngGG...",
        "....NWTTTTnGh...",
        "....NWTTTTn.h...",
        "....NWTTTtn.....",
        "....NWTTTtn.....",
        "....NTTTttn.....",
        ".....nttttn.....",
        "......nnnn......",
        "................",
        "................",
        "................",
    ], {"C": WOOD[3], "c": WOOD[1], "N": GLASS[3], "n": GLASS[1], "W": GLASS[4],
        "T": TEAL[3], "t": TEAL[1], "g": HERB[3], "G": HERB[2], "h": HERB[1]})


def make_holy_water() -> np.ndarray:
    """A round flask of glowing pale holy water with a gold stopper and a gold band (phase 19)."""
    return _draw(16, 16, [
        "................",
        "......KKk.......",
        "......KKk.......",
        "......NWn.......",
        ".....NWWnn......",
        "....NWLLLLn.....",
        "...NWLHLLLLn....",
        "...NLHHLLLLn....",
        "...NKKKKKKkn....",
        "...NLLLLLLln....",
        "...NLLLLLlln....",
        "....nLLllln.....",
        ".....nnnnn......",
        "................",
        "................",
        "................",
    ], {"K": GOLD[3], "k": GOLD[1], "N": GLASS[3], "n": GLASS[1], "W": GLASS[4],
        "L": HOLY[2], "l": HOLY[1], "H": HOLY[3]})


def make_feast() -> np.ndarray:
    """A long loaf of bread across both cells with a roast leg lying on its left end."""
    c = Canvas(32, 16)
    # The loaf: crust in three steps (dark under, lit top-left), with scored cuts.
    c.ellipse(16.5, 9.5, 14.5, 5.0, CRUST[1])
    c.ellipse(15.5, 8.7, 13.0, 4.0, CRUST[2])
    c.ellipse(14.0, 7.6, 9.0, 2.0, CRUST[3])
    for x in (13, 19, 25):
        c.line(x, 6, x + 2, 10, CRUST[0])
    # The roast leg: meat on the loaf's left end, its bone pointing up and right.
    c.ellipse(7.5, 8.5, 5.0, 4.2, MEAT[1])
    c.ellipse(6.8, 7.8, 3.8, 3.0, MEAT[2])
    c.ellipse(6.0, 7.0, 1.8, 1.4, MEAT[3])
    c.line(11, 5, 14, 2, CLAY[3])
    c.line(11, 6, 14, 3, CLAY[2])
    c.ellipse(15.0, 2.0, 1.4, 1.4, CLAY[3])
    c.ellipse(15.8, 3.6, 1.4, 1.4, CLAY[2])
    c.outline(INK)
    return c.a


def make_bomb() -> np.ndarray:
    """A round iron bomb, lit from the upper left, with a short fuse and a spark."""
    c = Canvas(16, 16)
    c.ellipse(7.5, 9.5, 5.5, 5.5, IRON[1])
    c.ellipse(6.8, 8.8, 4.2, 4.2, IRON[2])
    c.ellipse(5.8, 7.6, 1.8, 1.8, IRON[4])
    c.rect(6, 3, 9, 4, IRON[3])
    c.line(9, 3, 11, 1, LEATHER[3])
    c.px(12, 1, EMBER[3])
    c.px(12, 0, GOLD[4])
    c.px(13, 1, GOLD[3])
    c.outline(INK)
    return c.a


def make_smelling_salts() -> np.ndarray:
    """A small round vial of glowing green salts with a cork."""
    return _draw(16, 16, [
        "................",
        "......CCc.......",
        "......CCc.......",
        "......NWn.......",
        ".....NWGGn......",
        "....NWGGGGn.....",
        "....NGGHGGn.....",
        "...NGGGGGGGn....",
        "...NGGGgGGGn....",
        "...NGGGGGGgn....",
        "....NGGGGgn.....",
        ".....nnnnn......",
        "................",
        "................",
        "................",
        "................",
    ], {"C": WOOD[3], "c": WOOD[1], "N": GLASS[3], "n": GLASS[1], "W": GLASS[4], "G": ROT[2], "g": ROT[1],
        "H": ROT[3]})


def make_silver_ring() -> np.ndarray:
    """A silver ring with a small blue stone."""
    return _draw(16, 16, [
        "................",
        "................",
        "......bBb.......",
        ".....bBWBb......",
        "......SSS.......",
        "....SSs.sSS.....",
        "...SS.....sS....",
        "...S.......s....",
        "...S.......s....",
        "...Ss.....ss....",
        "....sS...ss.....",
        ".....sssss......",
        "................",
        "................",
        "................",
        "................",
    ], {"S": GLASS[4], "s": GLASS[2], "B": M["glow_cyan"].colors[2], "b": M["glow_cyan"].colors[0],
        "W": M["glow_cyan"].colors[3]})


def make_rot_gem() -> np.ndarray:
    """A cut violet gem with a sickly glow at its heart."""
    return _draw(16, 16, [
        "................",
        "................",
        "................",
        ".....VVVVV......",
        "....VWHHHvV.....",
        "...VWHHHHHvV....",
        "...vvvvvvvvv....",
        "....pPGPPPp.....",
        ".....pPPPp......",
        "......pPp.......",
        ".......p........",
        "................",
        "................",
        "................",
        "................",
        "................",
    ], {"V": VIOLET[2], "v": VIOLET[1], "W": VIOLET[3], "H": VIOLET[2], "P": PURPLE[3], "p": PURPLE[1],
        "G": ROT[2]})


def make_golden_idol() -> np.ndarray:
    """A small golden idol: a round-headed figure with gem eyes on a stepped base."""
    rows = [
        "................",
        "................",
        "......GGGG......",
        ".....GHHHGg.....",
        "....GHGGGGgg....",
        "....GHrGGrgg....",
        "....GHGGGGgg....",
        ".....GGggggg....",
        "......Gggg......",
        "....GGGGgggg....",
        "...GHGGGGgggg...",
        "...GHG.GGg.gg...",
        "...GHG.GGg.gg...",
        "...GG..GGg..g...",
        "....G..GGg......",
        ".......GGg......",
        "......GGGgg.....",
        ".....GHGGGggg...",
        ".....GHGGGggg...",
        "....GGGGGGgggg..",
        "....GHGGGGGggg..",
        "...dddddddddddd.",
        "...GHHGGGGGGggg.",
        "...GGGGGGGGGggg.",
        "...dddddddddddd.",
        "..GHHGGGGGGGgggg",
        "..GGGGGGGGGGgggg",
        "..dddddddddddddd",
        "................",
        "................",
        "................",
        "................",
    ]
    return _draw(16, 32, rows, {"G": GOLD[2], "H": GOLD[4], "g": GOLD[1], "d": GOLD[0], "r": EMBER[2]})


def make_chest(opened: bool) -> np.ndarray:
    """A small wooden chest with iron bands and a gold lock, lit from the upper left. Open: the lid
    stands up behind it and a glow comes from inside."""
    c = Canvas(28, 24)
    top = 10
    # Body.
    c.rect(2, top, 25, 21, DARKWOOD[2])
    c.rect(2, top, 4, 21, DARKWOOD[3])
    c.rect(23, top, 25, 21, DARKWOOD[1])
    c.rect(2, 21, 25, 21, DARKWOOD[1])
    for x in (6, 21):
        c.rect(x, top, x + 1, 21, IRON[2])
        c.px(x, top, IRON[4])
    if opened:
        # The lid stands open behind; the inside glows gold.
        c.rect(3, 1, 24, top - 3, DARKWOOD[1])
        c.rect(3, 1, 24, 2, DARKWOOD[2])
        for x in (6, 21):
            c.rect(x, 1, x + 1, top - 3, IRON[1])
        c.rect(3, top - 2, 24, top + 1, GOLD[3])
        c.rect(5, top - 2, 22, top - 2, GOLD[4])
    else:
        # The rounded lid and the gold lock.
        c.rect(2, top - 5, 25, top - 1, DARKWOOD[2])
        c.rect(3, top - 6, 24, top - 6, DARKWOOD[3])
        c.rect(2, top - 1, 25, top - 1, DARKWOOD[1])
        for x in (6, 21):
            c.rect(x, top - 6, x + 1, top - 1, IRON[3])
        c.rect(12, top - 2, 15, top + 3, GOLD[2])
        c.px(12, top - 2, GOLD[4])
        c.px(13, top + 1, INK)
    c.outline(INK)
    return c.a


def _stone(c: Canvas, cx: float, cy: float, rx: float, ry: float, ramp: list[str]) -> None:
    """A rounded stone lit from the upper left: dark body, lighter middle, a small highlight."""
    c.ellipse(cx, cy, rx, ry, ramp[1])
    c.ellipse(cx - rx * 0.15, cy - ry * 0.15, rx * 0.75, ry * 0.7, ramp[2])
    c.ellipse(cx - rx * 0.4, cy - ry * 0.4, rx * 0.25, ry * 0.22, ramp[4] if len(ramp) > 4 else ramp[-1])


def make_ember_stone() -> np.ndarray:
    """A dark stone cracked open, glowing ember orange in the cracks."""
    c = Canvas(16, 16)
    _stone(c, 8.0, 9.0, 6.0, 5.0, STONE_RAMP)
    for x, y in ((6, 8), (7, 9), (8, 9), (9, 10), (10, 10), (8, 8), (9, 7)):
        c.px(x, y, EMBER[2])
    c.px(8, 9, EMBER[3])
    c.outline(INK)
    return c.a


def make_iron_stone() -> np.ndarray:
    """A heavy iron-grey stone with a dull metal sheen."""
    c = Canvas(16, 16)
    _stone(c, 8.0, 9.0, 6.0, 5.0, IRON)
    c.line(5, 11, 10, 11, IRON[0])
    c.outline(INK)
    return c.a


def make_lodestone() -> np.ndarray:
    """A big dark lodestone with little iron filings standing up on it (it pulls stones together)."""
    c = Canvas(32, 32)
    _stone(c, 16.0, 17.5, 13.0, 11.0, STONE_RAMP)
    for x, y in ((9, 9), (12, 7), (16, 6), (20, 7), (23, 9), (10, 13), (22, 12)):
        c.line(x, y, x, y - 2, IRON[3])
    c.rect(14, 15, 18, 19, VIOLET[1])
    c.rect(15, 16, 16, 17, VIOLET[3])
    c.outline(INK)
    return c.a


def make_knucklebone() -> np.ndarray:
    """A little knucklebone dice with dots, worn smooth."""
    c = Canvas(16, 16)
    c.ellipse(5.0, 6.0, 3.0, 3.0, CLAY[3])
    c.ellipse(11.0, 11.0, 3.0, 3.0, CLAY[2])
    c.line(5, 6, 11, 11, CLAY[3])
    c.line(6, 6, 11, 10, CLAY[3])
    c.line(5, 7, 10, 11, CLAY[2])
    c.px(5, 5, CLAY[4])
    c.px(10, 10, INK)
    c.outline(INK)
    return c.a


def make_wolf_tooth() -> np.ndarray:
    """A long curved fang on a leather cord."""
    return _draw(16, 16, [
        "................",
        "..cc........cc..",
        "...cc......cc...",
        ".....cc..cc.....",
        "......cWWc......",
        "......WTTT......",
        "......WTTt......",
        "......WTTt......",
        ".......TTt......",
        ".......TTt......",
        "........Tt......",
        "........Tt......",
        ".........t......",
        "................",
        "................",
        "................",
    ], {"c": LEATHER[2], "W": CLAY[4], "T": CLAY[3], "t": CLAY[1]})


def make_bone_totem() -> np.ndarray:
    """A tall totem of stacked bones and a small skull on top, bound with cord."""
    c = Canvas(16, 48)
    c.ellipse(8.0, 6.0, 5.0, 5.0, CLAY[3])
    c.rect(5, 8, 11, 12, CLAY[3])
    c.rect(6, 6, 7, 7, INK)
    c.rect(9, 6, 10, 7, INK)
    c.rect(7, 10, 9, 10, CLAY[1])
    c.ellipse(6.5, 4.5, 1.2, 1.2, CLAY[4])
    for y0 in (14, 24, 34):
        c.rect(6, y0, 10, y0 + 8, CLAY[2])
        c.rect(6, y0, 7, y0 + 8, CLAY[3])
        c.ellipse(5.5, y0 + 0.5, 1.6, 1.6, CLAY[3])
        c.ellipse(10.5, y0 + 0.5, 1.6, 1.6, CLAY[2])
        c.rect(5, y0 + 4, 11, y0 + 5, LEATHER[2])
    c.rect(4, 43, 12, 46, WOOD[1])
    c.outline(INK)
    return c.a


def make_heartleaf() -> np.ndarray:
    """A heart-shaped green leaf with a pale vein."""
    return _draw(16, 16, [
        "................",
        "................",
        "...GGG...GGG....",
        "..GHHGG.GHHGG...",
        "..GHGGGGGGGgG...",
        "..GGGGGVGGGgG...",
        "...GGGGVGGGg....",
        "....GGGVGGg.....",
        ".....GGVGg......",
        "......GVg.......",
        ".......V........",
        ".......s........",
        "................",
        "................",
        "................",
        "................",
    ], {"G": HERB[2], "H": HERB[4], "g": HERB[1], "V": HERB[4], "s": WOOD[2]})


def make_wake_root() -> np.ndarray:
    """A knobbly root that bends: down the left cell, then along the bottom right cell, glowing a
    little at its tips."""
    c = Canvas(32, 32)
    c.rect(5, 2, 10, 24, WOOD[2])
    c.rect(5, 2, 6, 24, WOOD[3])
    c.rect(5, 20, 28, 25, WOOD[2])
    c.rect(5, 20, 28, 21, WOOD[3])
    for x, y in ((8, 8), (7, 15), (14, 23), (21, 22)):
        c.ellipse(x + 0.5, y + 0.5, 2.0, 1.6, WOOD[1])
    c.ellipse(7.5, 2.5, 2.0, 2.0, ROT[2])
    c.ellipse(28.5, 22.5, 2.0, 2.0, ROT[2])
    c.outline(INK)
    c.a[0:16, 16:32] = np.where(c.a[0:16, 16:32, 3:4] > 0, 0, c.a[0:16, 16:32])
    return c.a


def make_rain_pouch() -> np.ndarray:
    """A small cloth pouch, tied at the top, damp and dripping blue."""
    c = Canvas(16, 16)
    c.ellipse(8.0, 10.0, 5.5, 4.5, CANVAS[2])
    c.ellipse(7.0, 9.0, 3.5, 3.0, CANVAS[3])
    c.rect(6, 4, 10, 6, CANVAS[2])
    c.rect(5, 5, 11, 5, LEATHER[2])
    c.px(12, 13, M["glow_cyan"].colors[2])
    c.px(12, 14, M["glow_cyan"].colors[1])
    c.px(4, 12, M["glow_cyan"].colors[2])
    c.outline(INK)
    return c.a


def make_rotting_heart() -> np.ndarray:
    """A swollen violet heart oozing sickly green rot."""
    c = Canvas(16, 16)
    c.ellipse(5.5, 6.5, 3.5, 3.5, PURPLE[2])
    c.ellipse(10.5, 6.5, 3.5, 3.5, PURPLE[2])
    c.poly([(2.2, 7.5), (13.8, 7.5), (8.0, 14.5)], PURPLE[2])
    c.ellipse(5.0, 5.5, 1.5, 1.3, PURPLE[4])
    for x, y in ((9, 8), (10, 9), (7, 11), (8, 12), (11, 7)):
        c.px(x, y, ROT[2])
    c.px(8, 15, ROT[1])
    c.outline(INK)
    return c.a


def make_grave_moss() -> np.ndarray:
    """A clump of grey-green grave moss on a bit of stone, glowing faintly rot-green."""
    c = Canvas(32, 16)
    c.rect(3, 11, 28, 14, STONE_RAMP[1])
    c.rect(3, 11, 28, 11, STONE_RAMP[2])
    for cx, cy, r in ((8, 8, 4.5), (15, 7, 5.0), (23, 8, 4.5)):
        c.ellipse(cx, cy, r, r * 0.8, M["moss"].colors[1])
        c.ellipse(cx - 1, cy - 1, r * 0.6, r * 0.5, M["moss"].colors[2])
    for x, y in ((9, 6), (15, 4), (22, 6), (18, 8)):
        c.px(x, y, ROT[2])
    c.outline(INK)
    return c.a


def backpack_origin() -> tuple[int, int]:
    """The first grid cell's top-left in the backpack art (art pixels)."""
    return STRAP + WALL + PAD, ROLL + RIM + PAD


def _round_rect(c: Canvas, x0: int, y0: int, x1: int, y1: int, r: int, color: str, r_bottom: int = -1) -> None:
    """A filled rectangle with its top corners cut round by radius r and its bottom corners by
    r_bottom (r if negative); corners inclusive."""
    rb = r if r_bottom < 0 else r_bottom
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            rr = r if y < (y0 + y1) / 2 else rb
            dx = max(x0 + rr - x, 0, x - (x1 - rr))
            dy = max(y0 + rr - y, 0, y - (y1 - rr))
            if dx * dx + dy * dy <= rr * rr + rr:
                c.px(x, y, color)


def make_backpack(rows: int) -> np.ndarray:
    """An adventurer's canvas backpack seen from the front, its top open: a red bedroll strapped
    across the top, shoulder straps showing at both sides, a body with round shoulders and
    stitched seams, the dark lining (with its drawstring) the grid sits on, and a buckled front
    pocket below. Lit from the upper left like everything else."""
    gw = COLS * CELL + (COLS - 1) * GAP
    gh = rows * CELL + (rows - 1) * GAP
    ox, oy = backpack_origin()
    W = gw + 2 * (PAD + WALL + STRAP)
    H = oy + gh + PAD + POCKET
    c = Canvas(W, H)
    bx0, bx1 = STRAP, W - 1 - STRAP
    by0 = ROLL - 4
    # Shoulder straps behind the body: they bulge out at the sides and come back in lower down.
    for side in (0, 1):
        for y in range(by0 + 6, H - 10):
            t = (y - by0 - 6) / max(1, H - 16 - by0)
            bulge = int(round(STRAP * (1.0 - abs(t - 0.35) * 1.4)))
            bulge = max(1, min(STRAP, bulge))
            for k in range(bulge):
                x = bx0 - 1 - k if side == 0 else bx1 + 1 + k
                c.px(x, y, LEATHER[3] if (side == 0 and k == bulge - 1) else LEATHER[1])
    # The body: canvas with round shoulders, lit on the left, shaded right and low.
    _round_rect(c, bx0, by0, bx1, H - 1, 12, CANVAS[2], 6)
    for y in range(by0, H):
        for x in range(bx0, bx1 + 1):
            if c.a[y, x, 3] == 0 or not (bx0 <= x <= bx1):
                continue
            if tuple(c.a[y, x, :3]) != tuple(c.get(x, y)[:3]):
                continue
            if x <= bx0 + 2:
                c.px(x, y, CANVAS[3])
            elif x >= bx1 - 2:
                c.px(x, y, CANVAS[1])
    # Stitched seams down both sides.
    for y in range(by0 + 12, H - 4):
        if (y // 2) % 2 == 0:
            c.px(bx0 + 3, y, CANVAS[4])
            c.px(bx1 - 3, y, CANVAS[3])
    # The opening: the leather rim, then the dark lining with a pale drawstring along its top.
    rim_y = ROLL
    c.rect(ox - PAD - 2, rim_y, ox + gw - 1 + PAD + 2, rim_y + RIM - 1, LEATHER[2])
    c.rect(ox - PAD - 2, rim_y, ox + gw - 1 + PAD + 2, rim_y, LEATHER[3])
    c.rect(ox - PAD - 2, rim_y + RIM - 1, ox + gw - 1 + PAD + 2, rim_y + RIM - 1, LEATHER[0])
    for x in range(ox - PAD, ox + gw + PAD, 3):
        c.px(x, rim_y + 2, CLAY[3] if (x // 3) % 2 == 0 else CLAY[2])
    c.rect(ox - PAD, oy - PAD, ox + gw - 1 + PAD, oy + gh - 1 + PAD, LINING[1])
    c.rect(ox - PAD, oy - PAD, ox + gw - 1 + PAD, oy - 1, LINING[0])
    c.rect(ox - PAD, oy - PAD, ox - PAD, oy + gh - 1 + PAD, LINING[0])
    # The front pocket under the opening: a canvas pouch with a leather flap and a gold buckle.
    py0 = oy + gh + PAD + 2
    _round_rect(c, bx0 + 8, py0, bx1 - 8, H - 3, 2, CANVAS[1], 5)
    c.rect(bx0 + 9, py0 + 1, bx1 - 9, py0 + 1, CANVAS[3])
    _round_rect(c, bx0 + 8, py0, bx1 - 8, py0 + 6, 2, LEATHER[1], 3)
    c.rect(bx0 + 9, py0, bx1 - 9, py0, LEATHER[3])
    mid = W // 2
    c.rect(mid - 1, py0 + 4, mid + 1, py0 + 10, LEATHER[0])
    c.rect(mid - 2, py0 + 7, mid + 2, py0 + 9, GOLD[2])
    c.px(mid - 2, py0 + 7, GOLD[4])
    c.px(mid, py0 + 8, LEATHER[0])
    # The bedroll across the top: a red blanket roll with spiral ends and two leather ties.
    rx0, rx1 = bx0 + 4, bx1 - 4
    for y in range(0, ROLL - 1):
        t = (y + 0.5) / (ROLL - 1)
        shade = BLANKET[3] if t < 0.3 else (BLANKET[2] if t < 0.75 else BLANKET[1])
        c.rect(rx0 + 3, y, rx1 - 3, y, shade)
    for ex, light in ((rx0 + 3, True), (rx1 - 3, False)):
        c.ellipse(ex + 0.5, (ROLL - 1) / 2.0, 3.5, (ROLL - 1) / 2.0, BLANKET[2] if light else BLANKET[1])
        c.ellipse(ex + 0.5, (ROLL - 1) / 2.0, 2.0, 3.6, BLANKET[0])
        c.ellipse(ex + 0.5, (ROLL - 1) / 2.0, 1.0, 1.6, BLANKET[3])
    for tx in (rx0 + 14, rx1 - 16):
        c.rect(tx, 0, tx + 2, ROLL - 2, LEATHER[1])
        c.rect(tx, 0, tx, ROLL - 2, LEATHER[3])
        c.rect(tx, ROLL - 6, tx + 2, ROLL - 4, GOLD[2])
    c.outline(INK)
    return c.a


def build(ctx) -> None:
    for name, img in (("salve", make_salve()), ("feast", make_feast()),
                      ("bomb", make_bomb()), ("smelling_salts", make_smelling_salts()),
                      ("silver_ring", make_silver_ring()), ("rot_gem", make_rot_gem()),
                      ("golden_idol", make_golden_idol()), ("ember_stone", make_ember_stone()),
                      ("iron_stone", make_iron_stone()), ("lodestone", make_lodestone()),
                      ("knucklebone", make_knucklebone()), ("wolf_tooth", make_wolf_tooth()),
                      ("bone_totem", make_bone_totem()), ("heartleaf", make_heartleaf()),
                      ("wake_root", make_wake_root()), ("rain_pouch", make_rain_pouch()),
                      ("rotting_heart", make_rotting_heart()), ("grave_moss", make_grave_moss()),
                      ("antidote", make_antidote()),
                      ("holy_water", make_holy_water())):
        ctx.save("sprites/items/%s.png" % name, img, scale=8)
    ctx.save("sprites/env/chest_closed.png", make_chest(False), scale=8)
    ctx.save("sprites/env/chest_open.png", make_chest(True), scale=8)
    ctx.save("sprites/ui/backpack_5.png", make_backpack(5), scale=4)
