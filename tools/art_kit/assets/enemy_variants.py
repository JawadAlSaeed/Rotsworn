"""Monster variants (phase 12, DESIGN.md 2.16): tougher, recoloured kin of the monsters, met
deeper in a run. Each is its base monster's finished sheet and portrait recoloured by OKLCH rules
(kit.variant), so it moves exactly like the base and shares its clips (data/clips/<base>.tres).
This module runs after the base monsters (modules build in name order) and reads their sheets
from assets/sprites/.
"""
from __future__ import annotations

import os

import numpy as np

from kit.context import ASSETS
from kit.variant import anything, band, glow, recolor, shift

# variant id -> (base id, rules, one line on the look). Rules run in order; the first match wins.
VARIANTS: dict[str, tuple[str, list, str]] = {
    # Burnt in the ruins' old fires: ash-grey skin and bark, the rot core turned to embers.
    "ashen_husk": ("rotten_husk", [
        (glow(90, 160), shift(to_h=55.0, c=1.25, dl=0.02)),
        (band(270, 350, 0.05), shift(to_h=30.0, c=1.1)),
        (anything, shift(c=0.25, dl=0.04, to_h=60.0, pull=0.5)),
    ], "ash grey, ember core"),
    # Swollen with bile: sick yellow-olive flesh, the belly gone sallow, the glow a fierce yellow.
    "blight_bloat": ("bloat", [
        (glow(90, 160), shift(to_h=100.0, c=1.2, dl=0.04)),
        (band(270, 345, 0.03), shift(to_h=105.0, c=1.1, dl=0.02)),
        (anything, shift(to_h=90.0, pull=0.5, c=1.1)),
    ], "bile yellow"),
    # Gorged on blood: dark red bodies, pink-tinged wings.
    "blood_gnats": ("gnat_swarm", [
        (band(60, 120, 0.06), shift(to_h=25.0, c=1.2)),
        (band(200, 300, 0.0), shift(to_h=10.0, c=1.6, dl=-0.02)),
        (anything, shift(to_h=15.0, pull=0.7, c=1.6)),
    ], "blood red"),
    # Hollowed out to a cold spirit: pale ice blue, cyan eyes.
    "hollow_shade": ("shade", [
        (glow(250, 330), shift(to_h=200.0, c=0.9, dl=0.05)),
        (glow(90, 160), shift(to_h=195.0)),
        (anything, shift(to_h=235.0, c=0.8, dl=0.16)),
    ], "ice blue"),
    # Mange to the bone: pale bone fur, dark spots kept, eyes burning red.
    "bone_hyena": ("rot_hyena", [
        (glow(90, 160), shift(to_h=25.0, c=1.4)),
        (band(270, 350, 0.05), shift(to_h=10.0)),
        (lambda L, C, h: L > 0.45, shift(c=0.45, dl=0.12, to_h=85.0, pull=0.5)),
        (anything, shift(c=0.8)),
    ], "bone pale"),
    # Fat on plague: a violet-sheened abdomen, yellow eyes.
    "plague_fly": ("carrion_fly", [
        (glow(90, 160), shift(to_h=95.0, c=1.1, dl=0.05)),
        (band(0, 40, 0.06), shift(to_h=95.0, c=1.0, dl=0.12)),
        (band(100, 180, 0.0), shift(to_h=320.0, c=1.6)),
        (anything, shift(dh=0.0)),
    ], "plague violet"),
    # Older and darker: bog-brown skin, glowing red eyes.
    "elder_toad": ("mire_toad", [
        (glow(40, 90), shift(to_h=25.0, c=1.2)),
        (glow(90, 160), shift(to_h=40.0, c=1.2)),
        (band(270, 350, 0.05), shift(to_h=20.0)),
        (anything, shift(to_h=60.0, pull=0.6, dl=-0.05, c=1.05)),
    ], "dark bog brown"),
}


def _load(rel: str) -> np.ndarray:
    from PIL import Image
    return np.array(Image.open(os.path.join(ASSETS, rel)).convert("RGBA"))


def build(ctx) -> None:
    for vid, (base, rules, _look) in VARIANTS.items():
        sheet = recolor(_load("sprites/enemies/%s.png" % base), rules)
        ctx.save("sprites/enemies/%s.png" % vid, sheet)
        por = recolor(_load("sprites/portraits/%s.png" % base), rules)
        ctx.save("sprites/portraits/%s.png" % vid, por)
