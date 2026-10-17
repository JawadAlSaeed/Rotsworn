class_name ZoneSectionData
extends Resource
## A hand-made slice of a long zone (DESIGN.md 8.5). ZoneAssembler lays a zone's sections end to
## end, left to right. Everything here is placed in the section's own frame: x from 0 to `width`,
## z the zone's depth (bounds_min.y .. bounds_max.y). Every section keeps the lane (z within
## ZoneAssembler.LANE) free at x = 0 and x = width, so any two sections join.

@export var id: String = ""
## Length along x (world units).
@export_range(4.0, 200.0, 0.5) var width: float = 30.0
@export var blocks: Array[ZoneBlockData] = []
@export var props: Array[ZonePropData] = []
@export var lights: Array[ZoneLightData] = []
## Roads, trails, mud, moss, planks and water (DESIGN.md 8.12).
@export var grounds: Array[ZoneGroundData] = []
## Crows, frogs and rats (DESIGN.md 8.12).
@export var critters: Array[ZoneCritterData] = []
## Roaming enemies, guards and champions. An enemy with no encounter takes one from the zone's
## roamer_pool; chance_percent decides whether it is there on a visit.
@export var enemies: Array[ZoneEnemyData] = []
@export var item_spots: Array[Vector3] = []
## Locked chests (a key opens them).
@export var chests: Array[Vector3] = []
## Where this section's rot seal may stand; a visit picks one of them (empty: no seal here).
@export var seal_spots: Array[Vector3] = []
## Where shrines stand (each visit picks which shrine from the zone's pool).
@export var shrine_spots: Array[Vector3] = []
## Where a wanderer may stand (at most one wanderer per visit, from all sections' spots).
@export var wanderer_spots: Array[Vector3] = []
## The gate to the guard (the end section): solid until the party holds enough seals.
@export var gate: ZoneBlockData
## Where the leader starts (the start section; feet).
@export var player_start: Vector3 = Vector3.ZERO
