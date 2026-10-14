"""Recolouring a finished sheet into a monster variant (phase 12, DESIGN.md 2.16).

A variant reuses its base monster's sheet layout and clips: only colours change. Every distinct
opaque colour is converted to OKLCH and passed through a list of rules; the first rule whose test
matches decides its new colour. Outline ink (very dark) is never touched, so the outline and the
pixel structure stay exactly the base monster's.
"""
from __future__ import annotations

from typing import Callable, Sequence

import numpy as np

from .color import from_oklch, to_oklch

LCh = tuple[float, float, float]
Rule = tuple[Callable[[float, float, float], bool], Callable[[float, float, float], LCh]]

# Colours this dark are outline ink: kept as they are.
INK_L = 0.21


def hue_in(h: float, lo: float, hi: float) -> bool:
    """h within [lo, hi] going round the circle (lo may be above hi: 330..30)."""
    h %= 360.0
    lo %= 360.0
    hi %= 360.0
    return lo <= h <= hi if lo <= hi else h >= lo or h <= hi


def glow(lo: float, hi: float, min_l: float = 0.62, min_c: float = 0.1) -> Callable[[float, float, float], bool]:
    """A test for bright, saturated colours in a hue band (the emissive glows)."""
    return lambda L, C, h: L >= min_l and C >= min_c and hue_in(h, lo, hi)


def band(lo: float, hi: float, min_c: float = 0.0) -> Callable[[float, float, float], bool]:
    """A test for any colour in a hue band (with at least this chroma)."""
    return lambda L, C, h: C >= min_c and hue_in(h, lo, hi)


def anything(L: float, C: float, h: float) -> bool:
    return True


def shift(dh: float = 0.0, c: float = 1.0, dl: float = 0.0, to_h: float | None = None,
          pull: float = 1.0) -> Callable[[float, float, float], LCh]:
    """A transform: hue moved by dh (or pulled `pull` of the way to `to_h`), chroma scaled by c,
    lightness moved by dl."""
    def fn(L: float, C: float, h: float) -> LCh:
        nh = h + dh
        if to_h is not None:
            d = ((to_h - h + 540.0) % 360.0) - 180.0
            nh = h + d * pull
        return max(0.0, min(1.0, L + dl)), max(0.0, C * c), nh % 360.0
    return fn


def recolor(rgba: np.ndarray, rules: Sequence[Rule]) -> np.ndarray:
    """A copy of `rgba` with every opaque colour remapped by the first matching rule."""
    out = rgba.copy()
    on = rgba[..., 3] > 0
    cols, inverse = np.unique(rgba[on][:, :3], axis=0, return_inverse=True)
    new = cols.copy()
    for i, c in enumerate(cols):
        hx = "#%02x%02x%02x" % tuple(int(x) for x in c)
        L, C, h = to_oklch(hx)
        if L < INK_L:
            continue
        for test, fn in rules:
            if test(L, C, h):
                nl, nc, nh = fn(L, C, h)
                v = from_oklch(nl, nc, nh).lstrip("#")
                new[i] = (int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16))
                break
    px = out[on]
    px[:, :3] = new[inverse.reshape(-1)]
    out[on] = px
    return out
