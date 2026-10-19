class_name ZoneData
extends Resource
## One explorable place (DESIGN.md 7.4): its look, its walkable area, what stands in it and the
## enemies that roam it. Everything is placed in world units on the ground plane (y up).

## Unique id used in commands and save data.
@export var id: String = ""
@export var display_name: String = ""
## Its picture on the run map (DESIGN.md 8): the place painted on the old paper.
@export_file("*.png") var map_icon_path: String = ""
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
## Roads, trails, mud, moss, planks and water laid on the floor (DESIGN.md 8.12).
@export var grounds: Array[ZoneGroundData] = []
## Small animals that get away when the leader comes near (DESIGN.md 8.12).
@export var critters: Array[ZoneCritterData] = []
## What always drifts through the air here: fireflies, ash, leaves, spores, mist (DESIGN.md 8.12).
@export var ambient: Array[ZoneAmbientData] = []
@export var enemies: Array[ZoneEnemyData] = []
## Glinting spots (feet on the ground) the leader can pick something up from in a run (DESIGN.md
## 8.1). What each holds is picked by the run's seed.
@export var item_spots: Array[Vector3] = []
## Locked chests (feet on the ground; 0 or 1 per zone). A key from the backpack opens one; what it
## holds is picked by the run's seed (DESIGN.md 8.1).
@export var chests: Array[Vector3] = []
## Rot seals (feet): the gate opens once the party holds tuning.zone_seals_needed of them (DESIGN.md 8.5).
@export var seal_spots: Array[Vector3] = []
## The gate to the guard (null: none): solid until enough seals are held.
@export var gate: ZoneBlockData
## The way out (DESIGN.md 8.5): in a run, once the guard is beaten the zone stays open and the
## party leaves from here when it wants. A zone without one moves on as soon as the guard falls.
@export var has_exit: bool = false
@export var exit_spot: Vector3 = Vector3.ZERO
## Shrines and wanderers standing here (DESIGN.md 8.5), each at the spot of the same index.
@export var offers: Array[ZoneOfferData] = []
@export var offer_spots: Array[Vector3] = []

@export_group("Sections")
## A long zone (DESIGN.md 8.5) is built each visit by ZoneAssembler from these: the start, then
## middle_count of the middle sections (picked and shuffled by a seed), then the end (gate and
## guard). No start section: the zone is used as it is (the fields above).
@export var start_section: ZoneSectionData
@export var middle_sections: Array[ZoneSectionData] = []
@export_range(0, 10) var middle_count: int = 3
@export var end_section: ZoneSectionData
## Fights for a section's roaming spots that name none.
@export var roamer_pool: Array[EncounterData] = []
## Shrines a section's shrine spots pick from.
@export var shrines: Array[ZoneOfferData] = []
## Wanderers; wanderer_percent of visits meet one.
@export var wanderers: Array[ZoneOfferData] = []
@export_range(0, 100, 1, "suffix:%") var wanderer_percent: int = 60
## The texture of the walls the assembler puts along the back and at both ends.
@export_file_path("*.png") var edge_texture_path: String = ""
@export_range(0.5, 12.0, 0.1) var edge_height: float = 5.0

@export_group("")
## Sound cue for each of the leader's steps (its ground: grass, mud, stone).
@export var footstep_sfx: String = "footstep_grass"
## This zone's song. Empty: MusicSet.zone_path.
@export_file("*.wav", "*.ogg", "*.mp3") var music_path: String = ""
## Background sound that loops while exploring here (wind, drips, flies; card #99). Empty: none.
@export_file("*.wav", "*.ogg", "*.mp3") var ambience_path: String = ""
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var ambience_volume_db: float = 0.0
