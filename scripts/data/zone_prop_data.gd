class_name ZonePropData
extends Resource
## One sprite standing in a place (DESIGN.md 7.3): a tree, a rock, a lamp. Drawn as a billboard
## like the fighters, lit by the scene.

## The sprite (transparent background, feet at the bottom edge).
@export_file_path("*.png") var sprite_path: String = ""
## Where its feet are.
@export var position: Vector3 = Vector3.ZERO
## World units per pixel.
@export_range(0.005, 1.0, 0.001) var pixel_size: float = 0.06
@export var flip: bool = false
## The player and roaming enemies cannot walk closer than this to its feet (0 = walk through).
@export_range(0.0, 10.0, 0.05) var solid_radius: float = 0.0
## Glow (emission) strength: makes it light up and bloom, for fungus or embers (0 = none).
@export_range(0.0, 8.0, 0.05) var glow: float = 0.0
@export var glow_color: Color = Color(1.0, 1.0, 1.0)
