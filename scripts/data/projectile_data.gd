class_name ProjectileData
extends Resource
## What a ranged enemy hit throws (DESIGN.md 3.9): a spit glob, a stone, a shadow bolt. Presentation
## only: the engine never reads it, so a ranged hit is judged exactly like a lunge (parry or dodge
## when it arrives). The flight lasts the hit's approach_ms and ends at impact.

## Unique id (for checks and tools).
@export var id: String = ""
## Sprite sheet: one row of equal frames that loop while it flies (a tumble, a pulse).
@export_file_path("*.png") var texture_path: String = ""
@export_range(1, 16) var hframes: int = 1
## One loop of the frames, in ms of attack time.
@export_range(10, 2000, 1, "suffix:ms") var loop_ms: int = 240
## World units per sprite pixel.
@export_range(0.005, 0.2, 0.001) var pixel_size: float = 0.04
## Height of the arc at mid-flight, in world units (0 = a straight shot).
@export_range(0.0, 6.0, 0.05) var arc_height: float = 0.6
## Faint copies along its path just behind it (0 = none), each `trail_gap_ms` further back.
@export_range(0, 6) var trail_count: int = 2
@export_range(5, 200, 1, "suffix:ms") var trail_gap_ms: int = 35
## Colour of the burst when it hits, and of its trail.
@export var color: Color = Color(0.6, 0.9, 0.3, 1.0)
## Sound when it leaves the enemy (a cue in the sfx library).
@export var launch_sfx: String = "lunge"
## Sound when it hits a hero, instead of the hit's own impact sound (empty: the hit's).
@export var hit_sfx: String = ""
## Where it leaves from, from the enemy's centre: `x` toward its target, `y` up (world units).
@export var launch_offset: Vector2 = Vector2(0.6, 0.3)
