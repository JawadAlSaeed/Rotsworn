class_name ZoneOfferData
extends Resource
## A shrine or a wanderer in a zone (DESIGN.md 8.5): walk up, Confirm, and it asks a yes/no
## question: pay this, get that. Each one works once per zone visit. Paying and giving are done by
## RunState.take_offer (pure, tested); only in a run.

enum Kind {
	## Stands still where a section put it ("Pray").
	SHRINE,
	## A friendly stranger met on some visits ("Talk").
	WANDERER,
}

@export var id: String = ""
@export var display_name: String = ""
@export var kind: Kind = Kind.SHRINE
## The question and the line under it (the price and the gift).
@export var question: String = ""
@export_multiline var detail: String = ""
@export var yes_text: String = "Yes"
@export var no_text: String = "Not now"

@export_group("Look")
## Its sprite (feet at the bottom edge), lit like a prop.
@export_file_path("*.png") var sprite_path: String = ""
@export_range(0.005, 1.0, 0.001) var pixel_size: float = 0.05
## Glow of the sprite and the small light beside it (0: none).
@export_range(0.0, 8.0, 0.05) var glow: float = 0.0
@export var glow_color: Color = Color(1.0, 1.0, 1.0)
## Walkers cannot come closer than this to its feet.
@export_range(0.0, 5.0, 0.05) var solid_radius: float = 0.45

@export_group("Price")
@export_range(0, 10000) var cost_gold: int = 0
## Every standing hero loses this percent of their max HP (never below 1 HP).
@export_range(0, 100, 1, "suffix:%") var cost_hp_percent: int = 0

@export_group("Gift")
## Every hero heals this percent of their max HP (downed heroes too).
@export_range(0, 100, 1, "suffix:%") var heal_percent: int = 0
@export_range(0, 10000) var gold: int = 0
## Every hero gets this much XP.
@export_range(0, 10000) var xp: int = 0
## Added to the team gauge (up to its max).
@export_range(0, 1000) var team_gauge: int = 0
## A fixed item (for example a Key).
@export var item: ItemData
## A found item of at least this rarity, picked by the run's seed (-1: none).
@export_range(-1, 2) var find_rarity: int = -1
