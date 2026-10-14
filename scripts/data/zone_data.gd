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
## Glinting spots (feet on the ground) the leader can pick something up from in a run (DESIGN.md
## 8.1). What each holds is picked by the run's seed.
@export var item_spots: Array[Vector3] = []
## Locked chests (feet on the ground; 0 or 1 per zone). A key from the backpack opens one; what it
## holds is picked by the run's seed (DESIGN.md 8.1).
@export var chests: Array[Vector3] = []
## Sound cue for each of the leader's steps (its ground: grass, mud, stone).
@export var footstep_sfx: String = "footstep_grass"
## This zone's song. Empty: MusicSet.zone_path.
@export_file("*.wav", "*.ogg", "*.mp3") var music_path: String = ""
## Background sound that loops while exploring here (wind, drips, flies; card #99). Empty: none.
@export_file("*.wav", "*.ogg", "*.mp3") var ambience_path: String = ""
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var ambience_volume_db: float = 0.0
