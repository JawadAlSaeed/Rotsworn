class_name ZoneCritterData
extends Resource
## A small animal that makes a place feel alive (DESIGN.md 8.12): it idles, and when the leader
## comes near it gets away: a crow flies up and off, a frog hops away, a rat scurries off. Only
## for show (no fights, no online sync: each machine plays it from the leader it sees).

enum Kind { CROW, FROG, RAT }

@export var kind: Kind = Kind.CROW
## Where it sits (feet).
@export var position: Vector3 = Vector3.ZERO
## Its sheet: four frames side by side (idle, idle, move, move).
@export_file_path("*.png") var sprite_path: String = ""
@export_range(0.005, 1.0, 0.001) var pixel_size: float = 0.045
@export var flip: bool = false
