class_name WorldPieceData
extends Resource
## A 3D world piece made in Blender (DESIGN.md 5.6): its model and what each of its surfaces
## wears. One file per look in data/pieces/; an arena places it with a ZonePropData or a
## ZoneBlockData. The same model in another place's stone is just another piece file.

@export var id: String = ""
## The shape (tools/blender_kit/build.py): one mesh, its foot on the ground at the origin.
## A missing file shows a placeholder box and one warning.
@export_file_path("*.glb") var model_path: String = ""
## One per material of the model, matched by name, else by order (a model surface with no
## match shows the checkerboard placeholder).
@export var surfaces: Array[PieceSurfaceData] = []
## Flat sprites it carries (a brazier's fire): they stay pixel art, glowing and swaying.
@export var sprites: Array[PieceSpriteData] = []
## How sharply the texture turns between faces: high keeps each slanted face one clean
## projection, low blends the three projections there.
@export_range(1.0, 64.0, 0.5) var texture_sharpness: float = 16.0
