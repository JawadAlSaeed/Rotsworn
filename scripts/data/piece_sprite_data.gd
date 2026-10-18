class_name PieceSpriteData
extends Resource
## A flat sprite a 3D world piece carries (DESIGN.md 5.6): a brazier's fire, a campfire's flames.
## It stays pixel art, lit like a prop, glowing and swaying, so fire keeps its flicker.

## The sprite (transparent background, its bottom edge at `offset`).
@export_file_path("*.png") var sprite_path: String = ""
## Where its bottom middle sits, from the piece's foot (before the piece is turned and scaled).
@export var offset: Vector3 = Vector3.ZERO
## World units per pixel.
@export_range(0.005, 1.0, 0.001) var pixel_size: float = 0.05
## Glow (emission) strength (0 = none).
@export_range(0.0, 8.0, 0.05) var glow: float = 0.0
@export var glow_color: Color = Color(1.0, 1.0, 1.0)
## The top of the sprite sways this far and back (world units), like a flame in the wind.
@export_range(0.0, 1.0, 0.005) var sway: float = 0.0
