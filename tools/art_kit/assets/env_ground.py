"""Ground pieces for the living zones (DESIGN.md 8.12): 32x32 seamless textures laid on the floor
by ZoneGroundData (roads, trails, plazas, mud, moss, planks, water, ash, lily pads).

Same rules as env_tiles (whose helpers this uses): every shape is periodic so the tiles join
without seams, light comes from the upper left, shading comes in clusters (despeckle), and every
pixel is one palette colour. They sit on top of a zone's floor tile, so they keep its moderate
contrast. Roads and planks run along x (the way zones run). The lily pads are the only texture
with clear pixels: the ground shader drops them, so pads float on the water drawn under them.
"""
from __future__ import annotations

import math

import numpy as np

from kit.palette import M, Material
from assets.env_tiles import (DIRT_DIM, MOSS_DIM, T, Tex, despeckle, joints, norm, pnoise, shade,
                              stones, top, wrapd, wshift)

STONE = Material.make("ground_stone", "#6b6870", below=3, above=2, shadow_chroma=0.6).colors
STONE_WARM = Material.make("ground_stone_warm", "#77706a", below=3, above=2, shadow_chroma=0.6).colors
DIRT = Material.make("ground_dirt", "#5e4a38", below=3, above=2, shadow_chroma=0.8).colors
LEAF = Material.make("ground_leaf", "#5e3f2a", below=2, above=1, light_chroma=0.7).colors
LEAF_DEAD = Material.make("ground_leaf_dead", "#4a4230", below=2, above=1).colors
EARTH = Material.make("ground_earth", "#3a3028", below=2, above=2, shadow_chroma=0.7).colors
MUD = Material.make("ground_mud", "#3e3a2a", below=2, above=2, shadow_chroma=0.7).colors
WOOD = Material.make("ground_wood", "#6a5038", below=3, above=2).colors
WATER = Material.make("ground_water", "#2f4d47", below=2, above=3, light_chroma=0.8).colors
ASH = Material.make("ground_ash", "#6e6a68", below=2, above=2, shadow_chroma=0.5).colors
EMBER = ["#4a2a2e", "#7c3429", "#b2522e"]
LILY = Material.make("ground_lily", "#4f7a3a", below=2, above=2).colors
BLOOM = ["#c98fb0", "#ecc8d8"]


def road_cobble() -> np.ndarray:
    """An old cobbled road: small rounded stones in rows, dark joints, moss in a few."""
    tex = Tex([STONE, DIRT_DIM, MOSS_DIM])
    sid, edge = stones(201, 4, 0.5, 0.8)
    joint = joints(sid) | (edge < 0.45)
    face = ~joint
    rng = np.random.default_rng(5)
    tone = rng.integers(2, 4, sid.max() + 1)
    lvl = tone[sid].astype(np.float64)
    # Each cobble domed: lit toward the upper left, shaded toward the lower right.
    lit = face & (wshift(joint, 0, -1) | wshift(joint, -1, 0))
    dark = face & (wshift(joint, 0, 1) | wshift(joint, 1, 0)) & ~lit
    lvl = lvl + lit * 1 - dark * 1
    tex.set(face, 0, lvl)
    tex.set(joint, 1, 1)
    moss = joint & top(pnoise(203, 4, 2), 0.35)
    tex.set(moss, 2, 1)
    tex.clean(keep=lit | dark | joint)
    return tex.rgba()


def paving() -> np.ndarray:
    """A plaza's big square slabs, worn and cracked, dirt in the joints."""
    tex = Tex([STONE_WARM, DIRT_DIM, MOSS_DIM])
    sid, edge = stones(211, 2, 0.12, 0.25)
    joint = joints(sid)
    face = ~joint
    lvl = np.where(sid % 2 == 0, 3, 2).astype(np.float64)
    lit = face & (wshift(joint, 0, -1) | wshift(joint, -1, 0))
    dark = face & (wshift(joint, 0, 1) | wshift(joint, 1, 0)) & ~lit
    wear = face & top(np.where(face, pnoise(213, 6, 2), -1.0), 0.12)
    lvl = lvl + lit - dark - wear
    tex.set(face, 0, lvl)
    tex.set(joint, 1, 1)
    # Cracks: short dark runs across two slabs.
    for (x0, y0, x1, y1) in ((4, 6, 11, 10), (20, 22, 26, 19), (18, 4, 21, 9)):
        for t in np.linspace(0.0, 1.0, 12):
            x = int(round(x0 + (x1 - x0) * t))
            y = int(round(y0 + (y1 - y0) * t + math.sin(t * 6.0)))
            if face[y % T, x % T]:
                tex.px(x, y, 1, 1)
    tex.set(joint & top(pnoise(215, 4, 2), 0.3), 2, 1)
    tex.clean(keep=lit | dark | joint)
    return tex.rgba()


def dirt_trail() -> np.ndarray:
    """A packed dirt trail: soft humps worn smooth, pebbles, a few tufts of dead grass."""
    tex = Tex([DIRT, STONE, LEAF_DEAD])
    h = pnoise(221, 3, 3) * 0.7 + pnoise(222, 8, 2) * 0.3
    lvl = 2.0 + shade(h * 2.0) * 3.0 + (h - 0.5) * 1.0
    tex.set(np.ones((T, T), bool), 0, lvl)
    peb = top(pnoise(225, 16, 1), 0.035)
    tex.set(peb, 1, 3)
    tex.set(wshift(peb, 1, 1) & ~peb, 1, 1)
    tuft = top(pnoise(227, 8, 1), 0.025) & ~peb
    tex.set(tuft, 2, 2)
    tex.clean(keep=peb | tuft)
    return tex.rgba()


def leaf_litter() -> np.ndarray:
    """Forest floor: dead leaves over dark earth, a few fresher rust ones on top."""
    tex = Tex([EARTH, LEAF_DEAD, LEAF])
    tex.set(np.ones((T, T), bool), 0, 2)
    tex.set(top(pnoise(232, 4, 2), 0.4), 0, 1)
    rng = np.random.default_rng(231)
    yy, xx = np.mgrid[0:T, 0:T]
    for i in range(30):
        cx, cy = rng.uniform(0, T, 2)
        ang = rng.uniform(0, math.pi)
        a, b = rng.uniform(1.8, 2.8), rng.uniform(0.9, 1.4)
        dx = wrapd(cx)[None, :]
        dy = wrapd(cy)[:, None]
        u = dx * math.cos(ang) + dy * math.sin(ang)
        v = -dx * math.sin(ang) + dy * math.cos(ang)
        leaf = (u / a) ** 2 + (v / b) ** 2 < 1.0
        m = 2 if i % 5 == 0 else 1
        lvl = 1 + (u < 0) * 1 - (v > 0.4) * 1
        tex.set(leaf, m, lvl)
    tex.clean()
    return tex.rgba()


def mud() -> np.ndarray:
    """Wet black mud: soft humps, glistening wet spots, a footprint or two."""
    tex = Tex([MUD, WATER])
    h = pnoise(241, 4, 3) * 0.7 + pnoise(242, 8, 2) * 0.3
    lvl = 2.0 + shade(h * 5.0) * 7.0
    tex.set(np.ones((T, T), bool), 0, lvl)
    wet = top(-h, 0.12)
    tex.set(wet, 1, 1)
    tex.set(wet & wshift(~wet, -1, -1), 1, 3)
    tex.clean(keep=wet)
    return tex.rgba()


def moss() -> np.ndarray:
    """A thick moss carpet in clumps, lit on their upper left."""
    tex = Tex([MOSS_DIM, LILY])
    h = pnoise(251, 6, 3)
    lvl = 1.5 + shade(h * 5.0) * 7.0 + (h - 0.5) * 2.0
    tex.set(np.ones((T, T), bool), 0, lvl)
    bright = top(h + shade(h * 5.0), 0.1)
    tex.set(bright, 1, 3)
    tex.clean()
    return tex.rgba()


def planks() -> np.ndarray:
    """A boardwalk: boards laid across the way (long along z, 8 pixels wide), dark gaps between
    them, a board end here and there, iron nails near the ends."""
    tex = Tex([WOOD, ["#1f1a17", "#2a221c"], ["#58585e", "#8a8a90"]])
    y = np.arange(T)[:, None] + np.zeros((1, T), dtype=int)
    x = np.zeros((T, 1), dtype=int) + np.arange(T)[None, :]
    col = x // 8
    gap = (x % 8) == 7
    shift = (col * 11) % T
    end = ((y + shift) % 32) == 0
    face = ~gap & ~end
    grain = pnoise(261, 2, 1)
    tone = np.array([2, 3, 2, 2])[col % 4]
    lvl = tone + ((x % 8) == 0) * 1 - ((x % 8) == 6) * 1
    lvl = lvl + np.where(np.sin((y + col * 9) * 0.55 + grain * 4.0) > 0.9, -1, 0)
    tex.set(face, 0, lvl)
    tex.set(gap | end, 1, 0)
    nails = face & ((((y + shift) % 32) == 2) | (((y + shift) % 32) == 30)) & (((x % 8) == 2) | ((x % 8) == 4))
    tex.set(nails, 2, 1)
    return tex.rgba()


def water() -> np.ndarray:
    """Murky water: soft light ripples in short arcs on a dark green body (the shader scrolls two
    copies of it and tints it per zone)."""
    tex = Tex([WATER])
    h = pnoise(271, 4, 2)
    tex.set(np.ones((T, T), bool), 0, 1 + (h > 0.5))
    rip = np.abs(np.sin((pnoise(272, 4, 2) * 2.0 + np.arange(T)[:, None] / T) * math.tau * 3.0)) > 0.93
    rip &= pnoise(273, 8, 1) > 0.45
    tex.set(rip, 0, 3)
    tex.set(rip & top(pnoise(274, 16, 1), 0.25), 0, 4)
    tex.clean(keep=rip)
    return tex.rgba()


def ash_ground() -> np.ndarray:
    """Drifted ash: soft grey dunes, black char, a few dim embers."""
    tex = Tex([ASH, ["#262224", "#3a3436"], EMBER])
    h = pnoise(281, 4, 3)
    lvl = 2.0 + shade(h * 5.0) * 7.0
    tex.set(np.ones((T, T), bool), 0, lvl)
    char = top(pnoise(282, 8, 2), 0.1)
    tex.set(char, 1, 1)
    ember = char & top(pnoise(283, 16, 1), 0.03)
    tex.set(ember, 2, 1)
    tex.clean(keep=ember)
    return tex.rgba()


def lily_pads() -> np.ndarray:
    """Lily pads with their notch, one pale bloom, on clear pixels (laid over water)."""
    out = np.zeros((T, T, 4), dtype=np.uint8)
    tex = Tex([LILY, BLOOM])
    mask = np.zeros((T, T), bool)
    for (cx, cy, r, notch) in ((8.0, 9.0, 4.2, 0.6), (23.0, 6.0, 3.0, 2.4), (20.0, 22.0, 4.6, 4.0),
                               (5.0, 25.0, 2.6, 1.2)):
        dx = wrapd(cx)[None, :]
        dy = wrapd(cy)[:, None] * 1.25
        d = np.hypot(dx, dy)
        ang = np.arctan2(dy, dx)
        cut = np.abs(((ang - notch + math.pi) % math.tau) - math.pi) < 0.35
        pad = (d < r) & ~(cut & (d > 0.8))
        mask |= pad
        tex.set(pad, 0, 2 + (dx < -0.5) * 1 - (d > r - 1.0) * 1)
    bloom = (np.hypot(wrapd(20.5)[None, :], wrapd(21.0)[:, None]) < 1.6)
    tex.set(bloom, 1, 1)
    mask |= bloom
    rgba = tex.rgba()
    out[mask] = rgba[mask]
    return out


TEXTURES = {
    "road_cobble": road_cobble, "paving": paving, "dirt_trail": dirt_trail, "leaf_litter": leaf_litter,
    "mud": mud, "moss": moss, "planks": planks, "water": water, "ash_ground": ash_ground,
}


def build(ctx) -> None:
    imgs = []
    for name, fn in TEXTURES.items():
        img = fn()
        assert img.shape == (T, T, 4) and (img[..., 3] == 255).all(), name
        ctx.save("sprites/env/%s.png" % name, img, tile=True)
        imgs.append(np.pad(np.tile(img, (3, 3, 1)), ((0, 0), (0, 4), (0, 0))))
    pads = lily_pads()
    ctx.save("sprites/env/lily_pads.png", pads, tile=True)
    ctx.extra("ground_3x3.png", np.concatenate(imgs, 1), scale=2)
