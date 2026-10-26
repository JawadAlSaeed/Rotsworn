class_name ZonePropData
extends Resource
## One sprite standing in a place (DESIGN.md 7.3): a tree, a rock, a lamp. Drawn as a billboard
## like the fighters, lit by the scene.

## The sprite (transparent background, feet at the bottom edge).
@export_file_path("*.png") var sprite_path: String = ""
## Where its feet are.
@export var position: Vector3 = Vector3.ZERO
## World units per pixel.
@export_range(0.005, 1.0, 0.001) var pixel_size: float = 0.05
@export var flip: bool = false
## Glow (emission) strength: makes it light up and bloom, for fungus or embers (0 = none).
@export_range(0.0, 8.0, 0.05) var glow: float = 0.0
@export var glow_color: Color = Color(1.0, 1.0, 1.0)
## Wind (DESIGN.md 8.12): the top of the sprite sways this far (world units) and back, slowly;
## grass, reeds and leaves sway, stone does not (0).
@export_range(0.0, 1.0, 0.005) var sway: float = 0.0
## A soft shadow blob on the ground under it (StageLook "Contact shadows"). Turn off for flat
## ground cover (grass, ferns, reeds), where a blob would only dirty the floor. Glowing props
## never get one.
@export var contact_shadow: bool = true

@export_group("3D piece")
## A 3D piece shown instead of the sprite (DESIGN.md 5.6): its foot at `position`, its own size
## times `scale`, turned by `rotation_y_degrees`, mirrored by `flip`. It casts a real shadow and its surfaces carry their own glow, so the sprite
## fields, `glow`, `sway` and `contact_shadow` are unused. Null: the sprite.
@export var piece: WorldPieceData
@export_range(-180.0, 180.0, 0.5) var rotation_y_degrees: float = 0.0
@export_range(0.1, 4.0, 0.01) var scale: float = 1.0
