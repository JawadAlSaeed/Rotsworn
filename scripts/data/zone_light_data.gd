class_name ZoneLightData
extends Resource
## One point light in a place (DESIGN.md 7.3): a lamp, a glowing pool. Strong local lights are a
## big part of the HD-2D look.

@export var position: Vector3 = Vector3(0.0, 1.5, 0.0)
@export var color: Color = Color(1.0, 0.7, 0.4)
@export_range(0.0, 16.0, 0.05) var energy: float = 2.0
## How far it reaches (world units).
@export_range(0.1, 50.0, 0.1) var reach: float = 6.0
## Flicker like a flame: up to this percent of the energy, this many times a second.
@export_range(0, 100, 1, "suffix:%") var flicker_percent: int = 0
@export_range(0.1, 20.0, 0.1) var flicker_hz: float = 6.0
@export var shadows: bool = false
