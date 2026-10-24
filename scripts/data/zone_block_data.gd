class_name ZoneBlockData
extends Resource
## One solid 3D block in a place (DESIGN.md 7.3): a cliff, a wall, a ruin. Textured on every side
## (the texture tiles in world space), casts and receives shadows.

## Centre of the block's bottom face.
@export var position: Vector3 = Vector3.ZERO
@export var size: Vector3 = Vector3(2.0, 2.0, 2.0)
## Turn around the vertical axis, in degrees.
@export_range(-180.0, 180.0, 0.5) var rotation_y_degrees: float = 0.0
## Seamlessly tileable surface (32x32).
@export_file_path("*.png") var texture_path: String = ""
## World size of one texture tile.
@export_range(0.1, 10.0, 0.05) var texture_world_size: float = 1.6
## A 3D piece shown instead of the box (DESIGN.md 5.6): stretched to fill `size`, its footprint
## centred on `position`, wearing the piece's own textures (the two texture fields above are then
## unused). Null: the plain box.
@export var piece: WorldPieceData
