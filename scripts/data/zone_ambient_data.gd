class_name ZoneAmbientData
extends Resource
## Something always drifting through a place (DESIGN.md 8.12): fireflies, ash, falling leaves,
## spores, low mist. Particles in a box that follows the camera's spot; each lives `lifetime`
## seconds, fading in and out.

@export var id: String = ""
## A small pixel sprite (white or coloured; `color` tints it).
@export_file_path("*.png") var texture_path: String = ""
@export var color: Color = Color(1.0, 1.0, 1.0)
## Emission strength (0: lit like the place; above 0 it glows and blooms).
@export_range(0.0, 8.0, 0.05) var glow: float = 0.0
@export_range(1, 2000) var amount: int = 40
@export_range(0.1, 60.0, 0.1) var lifetime: float = 6.0
## World size of one particle.
@export_range(0.01, 10.0, 0.01) var size: float = 0.12
## Half the box they appear in, around the camera's spot, and the box's centre height.
@export var area: Vector3 = Vector3(12.0, 2.0, 8.0)
@export_range(-5.0, 20.0, 0.05) var height: float = 1.5
## Average drift (world units a second) and how much each one wanders off it (degrees).
@export var velocity: Vector3 = Vector3(0.2, 0.0, 0.0)
@export_range(0.0, 180.0, 1.0) var spread: float = 30.0
## Wobble in the air (fireflies, leaves): turbulence strength (0: none).
@export_range(0.0, 4.0, 0.01) var wobble: float = 0.0
## Soft see-through quads (mist) instead of hard pixels.
@export var soft: bool = false
## Leaves turn as they fall.
@export var spin: bool = false
