"""The game's shared materials: every colour the art uses comes from a ramp made here.

A Material is a colour ramp (darkest first) plus how light maps onto it. Asset modules pick
materials by name (`M["steel"]`) and may add their own with `Material.make(...)`, but should reuse
these first so the whole game reads as one palette.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .color import darken_for_outline, ramp

# One near-black for the darkest outlines and pupils, a warm violet so it never looks grey-dead.
INK = "#160f1a"


@dataclass
class Material:
    name: str
    colors: list[str]
    # Light 0..1 maps onto ramp positions lo..hi (fractional index, rounded per pixel).
    lo: float = 0.0
    hi: float = 4.0
    # Specular highlight strength (0 = none) and tightness; pushes pixels to the top colour.
    spec: float = 0.0
    spec_power: float = 18.0
    # Emissive materials ignore light and use `glow_index` (default: top colour).
    emissive: bool = False
    glow_index: int | None = None
    # Ordered dithering where two colours meet (for big, flat-ish surfaces).
    dither: bool = False
    # Outline colour for pixels next to this material (default: from the darkest colour).
    outline: str = ""
    # How much the ambient-occlusion term darkens (0 = ignore crevices).
    ao: float = 0.6
    # Lambert wrap: 0 = hard terminator, 0.5 = soft cloth-like falloff.
    wrap: float = 0.25
    extra: dict = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.outline:
            self.outline = darken_for_outline(self.colors[0])
        if self.hi > len(self.colors) - 1:
            self.hi = float(len(self.colors) - 1)

    @staticmethod
    def make(name: str, base: str, below: int = 2, above: int = 2, **kw) -> "Material":
        ramp_kw = {k: kw.pop(k) for k in list(kw) if k in (
            "step_l", "shadow_shift", "light_shift", "shadow_chroma", "light_chroma", "grey_hue")}
        colors = ramp(base, below=below, above=above, **ramp_kw)
        kw.setdefault("hi", float(len(colors) - 1))
        return Material(name=name, colors=colors, **kw)

    def top(self) -> int:
        return len(self.colors) - 1


def _m(name: str, base: str, below: int = 2, above: int = 2, **kw) -> Material:
    return Material.make(name, base, below, above, **kw)


# --- Shared library ---------------------------------------------------------------------------
# Index 2 is the base colour for the usual 5-colour ramp (2 below, 2 above).

M: dict[str, Material] = {}


def _add(*mats: Material) -> None:
    for m in mats:
        M[m.name] = m


_add(
    # People
    _m("skin", "#d39a72", wrap=0.45, ao=0.5),
    _m("skin_fair", "#e3ad86", wrap=0.45, ao=0.5),
    _m("skin_tan", "#b97d58", wrap=0.45, ao=0.5),
    _m("hair_black", "#352a33", step_l=0.075, wrap=0.3),
    _m("hair_brown", "#6a4733", wrap=0.3),
    _m("hair_auburn", "#93492f", wrap=0.3),
    _m("eye_white", "#e9e2d6", below=1, above=0, emissive=True),
    # Cloth and leather
    _m("cloth_blue", "#3d5d97", wrap=0.4),
    _m("cloth_red", "#a3382f", wrap=0.4),
    _m("cloth_gold", "#c49a3c", wrap=0.4),
    _m("cloth_purple", "#5f4385", wrap=0.4),
    _m("cloth_charcoal", "#3c3e50", wrap=0.4),
    _m("cloth_cream", "#cdbd98", wrap=0.4),
    _m("canvas", "#8a7a52", wrap=0.4, dither=False),
    _m("leather", "#7a5034", wrap=0.35),
    _m("leather_dark", "#4e3426", wrap=0.35),
    # Metal and wood
    _m("steel", "#7f8ca6", spec=0.9, spec_power=14.0, wrap=0.15),
    _m("iron", "#5c616f", spec=0.6, wrap=0.15),
    _m("blade", "#aab6c4", above=2, spec=1.0, spec_power=10.0, wrap=0.1),
    _m("gold", "#c4a04a", spec=0.9, spec_power=12.0, wrap=0.15),
    _m("gold_worn", "#a8873f", spec=0.6, wrap=0.2),
    _m("wood", "#7b5a3b", wrap=0.3),
    _m("wood_dark", "#4f3a2c", wrap=0.3),
    _m("bone", "#d2c8a6", wrap=0.35),
    # Glows (emissive)
    _m("glow_cyan", "#74e6e0", below=2, above=1, emissive=True),
    _m("glow_rot", "#bfe85e", below=2, above=1, emissive=True),
    _m("glow_amber", "#ffb54d", below=2, above=1, emissive=True),
    _m("glow_violet", "#b98cff", below=2, above=1, emissive=True),
    _m("glow_ember", "#f07a36", below=2, above=1, emissive=True),
    # Rot and monsters
    _m("husk_skin", "#7a7c58", wrap=0.35, dither=False),
    _m("husk_bark", "#5a4a3e", wrap=0.3),
    _m("rot_purple", "#6b3d6c", wrap=0.35),
    _m("rot_green", "#6f8a35", wrap=0.35),
    _m("bloat_flesh", "#9c7aa0", wrap=0.45, dither=True),
    _m("bloat_pale", "#c7a59a", wrap=0.45, dither=True),
    _m("bile", "#8fae3a", wrap=0.4),
    _m("gnat_body", "#2c2433", below=1, above=2, spec=0.8, spec_power=8.0),
    _m("gnat_wing", "#b8c7d8", below=1, above=1, wrap=0.6),
    _m("shade_cloth", "#2d2645", wrap=0.5, step_l=0.07),
    _m("shade_edge", "#6b58a8", wrap=0.5),
    _m("king_robe", "#5a2337", wrap=0.4),
    _m("king_armor", "#4b4f60", spec=0.7, wrap=0.15),
    # World
    _m("stone", "#6d6971", wrap=0.25, dither=True),
    _m("stone_warm", "#7a6e66", wrap=0.25, dither=True),
    _m("moss", "#5f7832", wrap=0.4),
    _m("dirt", "#5b4636", wrap=0.35, dither=True),
    _m("ash", "#7b7570", wrap=0.35, dither=True),
    _m("bog_mud", "#4b4631", wrap=0.35, dither=True),
    _m("bog_water", "#2f4b46", wrap=0.3),
    _m("grass", "#6c8636", wrap=0.45),
    _m("dead_wood", "#5e4b3f", wrap=0.3),
    _m("leaves_rot", "#56692c", wrap=0.45, dither=True),
)
