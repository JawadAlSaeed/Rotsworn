"""Every piece, by name. A new group of pieces is a new module here, added to MODULES."""
from __future__ import annotations

from pieces import fire, ground, ruins, shrines, stone, wood

MODULES = [stone, wood, fire, shrines, ruins, ground]

PIECES = {p.name: p for m in MODULES for p in m.PIECES}
