class_name OathData
extends Resource
## One step of the difficulty ladder (DESIGN.md 8.15). A run played "at Oath N" has the rules of
## oaths 1 to N all at once, so each oath only lists what it ADDS. Every number is a change from the
## normal rule and defaults to "no change"; the base rules stay in tuning.tres.

@export var id: String = ""
@export var title: String = ""
## One short player-facing line: what this oath does.
@export var description: String = ""

@export_group("Enemies")
## Elite fights: added to tuning elite_hp_percent / elite_power_percent (points of percent).
@export var elite_hp_percent_add: int = 0
@export var elite_power_percent_add: int = 0
## Act bosses and the places' guards (mini-bosses): their HP and power, in percent over their data.
@export var boss_hp_percent_add: int = 0
@export var boss_power_percent_add: int = 0
## Every enemy's power, in percent over what it would be.
@export var enemy_power_percent_add: int = 0
## Added to tuning run_enemy_hp_row_percent / run_enemy_power_row_percent: enemies grow faster per
## map row.
@export var enemy_hp_row_add: int = 0
@export var enemy_power_row_add: int = 0

@export_group("The run")
## Added to tuning run_rest_heal_percent (negative: the campfire Rest heals less).
@export var rest_heal_percent_add: int = 0
## Added to tuning run_act_heal_percent (the heal between acts).
@export var act_heal_percent_add: int = 0
## Added to the run's starting gold (never below 0 gold).
@export var start_gold_add: int = 0
## Added to every shop price (items, gear, services). Selling is not changed.
@export var shop_price_percent_add: int = 0
## Added to the gold a won fight pays, in percent (negative: less; the pay never goes below 0).
## Applied after the party's gold charms and gear.
@export var gold_percent_add: int = 0
## Added to the number of spoils choices (negative: fewer; never fewer than one).
@export var loot_choices_add: int = 0
## Added to tuning run_team_gauge_carry_percent (negative: less of the gauge carries over).
@export var team_gauge_carry_percent_add: int = 0
## The party starts the run at this percent of its max HP (100: full). With several oaths the
## lowest one counts.
@export_range(1, 100, 1, "suffix:%") var start_hp_percent: int = 100

@export_group("Relics and Echoes")
## Added to the Relic slots a hero has open (negative: fewer; never under one, DESIGN.md 8.17).
@export var relic_slots_add: int = 0
## Added to every hero's Echo points, in percent (-50: half, rounded down; never below 0).
@export var echo_points_percent_add: int = 0


## The modifier `field` summed over oaths 1..`oath` of `ladder` (oath 0: nothing). An oath past the
## ladder's end counts as the last one.
static func total(ladder: Array[OathData], oath: int, field: StringName) -> int:
	var sum := 0
	for i: int in mini(maxi(oath, 0), ladder.size()):
		if ladder[i] != null:
			sum += int(ladder[i].get(field))
	return sum


## The percent of max HP the party starts at under oaths 1..`oath` (100 when none lowers it).
static func start_hp_for(ladder: Array[OathData], oath: int) -> int:
	var lowest := 100
	for i: int in mini(maxi(oath, 0), ladder.size()):
		if ladder[i] != null:
			lowest = mini(lowest, ladder[i].start_hp_percent)
	return lowest


## `oath` kept inside 0..ladder size.
static func clamp_oath(ladder: Array[OathData], oath: int) -> int:
	return clampi(oath, 0, ladder.size())


## "Oath 3", or "No oath" for 0.
static func label(oath: int) -> String:
	return "Oath %d" % oath if oath > 0 else "No oath"


## The descriptions of oaths 1..`oath`, newest first (the lines the picking screen lists).
static func rule_lines(ladder: Array[OathData], oath: int) -> Array[String]:
	var lines: Array[String] = []
	for i: int in range(mini(maxi(oath, 0), ladder.size()) - 1, -1, -1):
		if ladder[i] != null:
			lines.append("%d  %s: %s" % [i + 1, ladder[i].title, ladder[i].description])
	return lines
