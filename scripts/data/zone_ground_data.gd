class_name ZoneGroundData
extends Resource
## A piece of ground laid on the floor of a place (DESIGN.md 8.12): a road, a trail, mud, moss, a
## boardwalk, or water. Drawn flat just above the floor with a ragged, pixelated edge; its texture
## tiles in world space like the floor's. Water moves and shimmers and, when solid, cannot be
## walked into (ZoneMotion turns it into obstacles).

enum Kind {
	## Plain ground: a road, a trail, a patch of mud or moss, planks.
	PATCH,
	## Moving water (the texture scrolls in two layers; deeper toward the middle).
	WATER,
}

@export var kind: Kind = Kind.PATCH
## Centre on the ground.
@export var position: Vector3 = Vector3.ZERO
## Size along x and z before turning (world units).
@export var size: Vector2 = Vector2(4.0, 4.0)
@export_range(-180.0, 180.0, 0.5) var rotation_y_degrees: float = 0.0
## An ellipse (pools, clearings) instead of a rectangle (roads, planks).
@export var round: bool = false
## Seamlessly tileable surface (32x32).
@export_file_path("*.png") var texture_path: String = ""
## World size of one texture tile.
@export_range(0.1, 10.0, 0.05) var texture_world_size: float = 1.6
## How ragged the edge is (0: a clean edge, 1: deeply eaten away), in world units of bite.
@export_range(0.0, 2.0, 0.01) var edge_noise: float = 0.4
## Pieces with a higher layer draw on top of lower ones (a road over a clearing).
@export_range(0, 9) var layer: int = 0
@export var tint: Color = Color(1.0, 1.0, 1.0)
## Water only: the colour deep in the middle.
@export var deep_color: Color = Color(0.04, 0.1, 0.09)
## Walkers cannot step onto it (deep water).
@export var solid: bool = false
## Water only: a stream's flow, in world units a second along the piece's own x and z (before
## turning); zero is still water's slow drift (card #232).
@export var flow: Vector2 = Vector2.ZERO
## Water only: the share of spots where a ripple ring spreads now and then (0: none).
@export_range(0.0, 1.0, 0.01) var ripples: float = 0.0
## The rim of a (non-water) piece fades into the floor: this many art pixels deep it thins out in
## a dither pattern, so the floor shows through and there is no cut-out edge (0 = a hard edge).
@export_range(0, 12, 1) var fringe_pixels: int = 4
## The outermost two art pixels are this much darker than the rest (1 = not darker).
@export_range(0.5, 1.0, 0.01) var edge_shade: float = 0.9
