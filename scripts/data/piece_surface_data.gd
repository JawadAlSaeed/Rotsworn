class_name PieceSurfaceData
extends Resource
## One texture area of a 3D world piece (DESIGN.md 5.6): which pixel texture it wears and whether
## it glows. Matched to the model's material of the same name.

## The model's material this surface paints (tools/blender_kit names them: stone, bark, rot).
@export var name: String = ""
## Seamlessly tileable texture (32x32), laid over the surface in world space.
@export_file_path("*.png") var texture_path: String = ""
## World size of one texture tile (1.6: one texture pixel is 0.05, a sprite prop's pixel).
@export_range(0.1, 10.0, 0.05) var texture_world_size: float = 1.6
## Glow (emission) strength: makes the surface light up and bloom, for lamp glass, embers or a
## shrine's crystal (0 = none). The glow follows the texture's pixels.
@export_range(0.0, 8.0, 0.05) var glow: float = 0.0
@export var glow_color: Color = Color(1.0, 1.0, 1.0)
