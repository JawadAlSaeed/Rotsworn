extends SceneTree
## Writes the difficulty ladder (DESIGN.md 8.15, 8.17): twelve oaths in data/runs/oaths/ and the run's
## list of them. Each oath only lists what it ADDS; a run at Oath N has oaths 1 to N together.
## Rewrites every file it owns. Run it after bootstrap_phase15.gd (that one keeps the oaths: it
## loads the run first).
## Run: Godot --headless --path . -s tools/bootstrap_oaths.gd

const RUN_PATH := "res://data/runs/rotten_road.tres"
const DIR := "res://data/runs/oaths/"

var _written: int = 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var ladder: Array[OathData] = []
	# Run start gold is 0 in tuning.tres, so Want pinches the gold coming in instead.
	ladder.append(_oath("thorns", "Oath of Thorns", "Elites have 20% more HP and hit 10% harder.",
			{"elite_hp_percent_add": 20, "elite_power_percent_add": 10}))
	ladder.append(_oath("want", "Oath of Want", "Shops charge 15% more. Fights pay 25% less gold.",
			{"shop_price_percent_add": 15, "gold_percent_add": -25}))
	ladder.append(_oath("embers", "Oath of Embers", "The campfire's Rest heals 15 points of percent less.",
			{"rest_heal_percent_add": -15}))
	ladder.append(_oath("deep", "Oath of the Deep", "Enemies grow stronger faster with every row.",
			{"enemy_hp_row_add": 2, "enemy_power_row_add": 1}))
	ladder.append(_oath("crowns", "Oath of Crowns", "Guards and bosses have 15% more HP and hit 10% harder.",
			{"boss_hp_percent_add": 15, "boss_power_percent_add": 10}))
	ladder.append(_oath("wounds", "Oath of Wounds", "The party starts the run at 75% HP.",
			{"start_hp_percent": 75}))
	ladder.append(_oath("scarcity", "Oath of Scarcity", "Spoils offer one choice fewer.",
			{"loot_choices_add": -1}))
	ladder.append(_oath("silence", "Oath of Silence", "Only half the team gauge carries into the next fight.",
			{"team_gauge_carry_percent_add": -50}))
	ladder.append(_oath("long_road", "Oath of the Long Road", "The rest between acts heals 25 points of percent less.",
			{"act_heal_percent_add": -25}))
	ladder.append(_oath("rot", "Oath of Rot", "Every enemy hits 10% harder.",
			{"enemy_power_percent_add": 10}))
	# Phase 17 (DESIGN.md 8.17): Relics stay between runs, so the top of the ladder bites into them.
	ladder.append(_oath("empty_hand", "Oath of the Empty Hand", "Each hero has one Relic slot fewer all run.",
			{"relic_slots_add": -1}))
	ladder.append(_oath("forgetting", "Oath of Forgetting", "Heroes get half the Echo points.",
			{"echo_points_percent_add": -50}))
	var run := load(RUN_PATH) as RunData
	run.oaths.assign(ladder)
	var err := ResourceSaver.save(run, RUN_PATH)
	if err != OK:
		push_error("bootstrap_oaths: could not save %s (%d)" % [RUN_PATH, err])
	print("bootstrap_oaths: wrote %d oaths and the run" % _written)
	quit()


## One oath saved to disk (and loaded back, so the run points at the file). `fields` are the
## modifiers it sets.
func _oath(id: String, title: String, description: String, fields: Dictionary) -> OathData:
	var oath := OathData.new()
	oath.id = id
	oath.title = title
	oath.description = description
	for key: String in fields:
		oath.set(key, int(fields[key]))
	var path := DIR + id + ".tres"
	var err := ResourceSaver.save(oath, path)
	if err != OK:
		push_error("bootstrap_oaths: could not save %s (%d)" % [path, err])
		return oath
	_written += 1
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as OathData
