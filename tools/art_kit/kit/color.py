"""Colour maths: hex <-> RGB, OKLab / OKLCH, and hue-shifted ramps.

Ramps are how every material gets its colours: a base colour is stepped darker and lighter in
OKLCH (a colour space where equal steps look equally different), with shadows leaning toward a
cool hue and highlights toward a warm one, the way pixel artists shade by hand.
"""
from __future__ import annotations

import math

# Shadows lean toward blue-violet, highlights toward warm yellow.
SHADOW_HUE = 285.0
LIGHT_HUE = 85.0


def hex_to_rgb(value: str) -> tuple[float, float, float]:
    """'#rrggbb' or 'rrggbb' -> floats 0..1."""
    v = value.lstrip("#")
    return tuple(int(v[i:i + 2], 16) / 255.0 for i in (0, 2, 4))  # type: ignore[return-value]


def rgb_to_hex(rgb: tuple[float, float, float]) -> str:
    return "#" + "".join("%02x" % max(0, min(255, round(c * 255.0))) for c in rgb)


def rgb8(value: str) -> tuple[int, int, int]:
    r, g, b = hex_to_rgb(value)
    return (round(r * 255), round(g * 255), round(b * 255))


def _to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _to_srgb(c: float) -> float:
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1.0 / 2.4) - 0.055


def rgb_to_oklab(rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    r, g, b = (_to_linear(c) for c in rgb)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = (math.copysign(abs(x) ** (1.0 / 3.0), x) for x in (l, m, s))
    return (
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    )


def oklab_to_rgb(lab: tuple[float, float, float]) -> tuple[float, float, float]:
    L, a, b = lab
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return (_to_srgb(r), _to_srgb(g), _to_srgb(bb))


def to_oklch(value: str) -> tuple[float, float, float]:
    L, a, b = rgb_to_oklab(hex_to_rgb(value))
    return (L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360.0)


def from_oklch(L: float, C: float, h: float) -> str:
    # Pull chroma in until the colour fits sRGB, so ramps never clip into odd hues.
    for _ in range(40):
        a = C * math.cos(math.radians(h))
        b = C * math.sin(math.radians(h))
        L_ = max(0.0, min(1.0, L))
        l = (L_ + 0.3963377774 * a + 0.2158037573 * b) ** 3
        m = (L_ - 0.1055613458 * a - 0.0638541728 * b) ** 3
        s = (L_ - 0.0894841775 * a - 1.2914855480 * b) ** 3
        r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        bb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        if min(r, g, bb) >= -0.001 and max(r, g, bb) <= 1.001:
            break
        C *= 0.92
    return rgb_to_hex(oklab_to_rgb((max(0.0, min(1.0, L)), a, b)))


def _toward(h: float, target: float, amount: float) -> float:
    """Moves hue h toward target by at most `amount` degrees (shortest way round)."""
    diff = (target - h + 540.0) % 360.0 - 180.0
    if abs(diff) <= amount:
        return target
    return (h + math.copysign(amount, diff)) % 360.0


def ramp(base: str, below: int = 2, above: int = 2, step_l: float = 0.085,
         shadow_shift: float = 14.0, light_shift: float = 9.0,
         shadow_chroma: float = 1.05, light_chroma: float = 0.82,
         grey_hue: float | None = None) -> list[str]:
    """A ramp of below + 1 + above colours, darkest first; the base sits at index `below`.

    Each step down: lightness - step_l, hue toward SHADOW_HUE by shadow_shift degrees, chroma
    times shadow_chroma. Each step up: lightness + step_l (shrinking), hue toward LIGHT_HUE,
    chroma times light_chroma. Near-grey colours (very low chroma) get `grey_hue` (or a cool
    default) so their shadows still lean cool.
    """
    L, C, h = to_oklch(base)
    if C < 0.012:
        h = grey_hue if grey_hue is not None else 260.0
    out: list[str] = []
    for i in range(below, 0, -1):
        hh = _toward(h, SHADOW_HUE, shadow_shift * i)
        cc = C * (shadow_chroma ** i) + 0.004 * i
        out.append(from_oklch(L - step_l * i, cc, hh))
    out.append(base if base.startswith("#") else "#" + base)
    for i in range(1, above + 1):
        hh = _toward(h, LIGHT_HUE, light_shift * i)
        cc = C * (light_chroma ** i)
        out.append(from_oklch(L + step_l * i * (1.0 - 0.12 * (i - 1)), cc, hh))
    return out


def darken_for_outline(value: str, amount: float = 0.45) -> str:
    """The outline colour for a ramp: its darkest colour pushed darker and toward violet."""
    L, C, h = to_oklch(value)
    return from_oklch(L * (1.0 - amount), C * 0.8 + 0.01, _toward(h, SHADOW_HUE, 30.0))


def mix(a: str, b: str, t: float) -> str:
    """Mixes two colours in OKLab (t = 0 gives a, 1 gives b)."""
    la = rgb_to_oklab(hex_to_rgb(a))
    lb = rgb_to_oklab(hex_to_rgb(b))
    return rgb_to_hex(oklab_to_rgb(tuple(x + (y - x) * t for x, y in zip(la, lb))))  # type: ignore[arg-type]
