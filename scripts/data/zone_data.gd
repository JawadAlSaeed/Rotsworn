class_name ZoneData
extends Resource
## One explorable place (DESIGN.md 7.4): its look, its walkable area, what stands in it and the
## enemies that roam it. Everything is placed in world units on the ground plane (y up).

## Unique id used in commands and save data.
@export var id: String = ""
@export var display_name: String = ""
## Lighting, post-processing, ground art; also used for the fights that start here.
@export var look: StageLook
## The party member who walks around (their sprite and idle pose).
@export var leader: CharacterData
## The walkable area on the ground (x, z). The edges are invisible walls.
@export var bounds_min: Vector2 = Vector2(-12.0, -12.0)
@export var bounds_max: Vector2 = Vector2(12.0, 12.0)
## Where the leader starts (feet).
@export var player_start: Vector3 = Vector3.ZERO
@export var blocks: Array[ZoneBlockData] = []
@export var props: Array[ZonePropData] = []
@export var lights: Array[ZoneLightData] = []
@export var enemies: Array[ZoneEnemyData] = []
