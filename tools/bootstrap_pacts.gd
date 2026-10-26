extends SceneTree
## Phase 21 (card #285, DESIGN.md 8.19): the starting pacts. Writes one EventChoiceData per pact into
## data/runs/pacts/ (its deal inside it) and gives the run its pact list, title, story and picture.
## Each pact is good for a real price (DESIGN.md 8.7's deal fields); a run offers
## tuning.run_pact_choices of them before its first stop, picked by its seed. Re-runnable: rewrites
## the files. First numbers: tune them in the files after play.
## Run: Godot --headless --path . -s tools/bootstrap_pacts.gd

const DIR := "res://data/runs/pacts/"
const RUN_PATH := "res://data/runs/rotten_road.tres"
const ITEM_DIR := "res://data/items/"

## id -> [choice text, done text, {deal fields}].
const PACTS := {
	"blood_gold": ["Blood for gold", "The coins are warm.",
			{"gold": 120, "cost_max_hp_percent": 10, "cost_max_hp_target": ZoneOfferData.HpTarget.EVERYONE}],
	"hungry_relic": ["Feed the hungry Relic", "Something old wakes in all of you.",
			{"relic_rarity": 1, "cost_rotten": "rotting_heart"}],
	"borrowed_years": ["Borrow years", "You feel older, and wiser.",
			{"xp": 60, "cost_hp_percent": 40}],
	"crown_of_ash": ["Take the crown of ash", "It fits too well.",
			{"relic_rarity": 2, "cost_max_hp_percent": 25, "cost_max_hp_target": ZoneOfferData.HpTarget.CHOSEN}],
	"storm_gauge": ["Drink the storm", "Your blood hums.",
			{"team_gauge": 100, "item": "bomb", "cost_hp_percent": 20}],
	"rot_purse": ["Take the rotten purse", "The gold smells of the grave.",
			{"gold": 200, "cost_rotten": "grave_moss"}],
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var pacts: Array[EventChoiceData] = []
	for id: String in PACTS:
		var row: Array = PACTS[id]
		var choice := EventChoiceData.new()
		choice.text = String(row[0])
		choice.done_text = String(row[1])
		var deal := ZoneOfferData.new()
		deal.id = "pact_" + id
		deal.display_name = String(row[0])
		var fields: Dictionary = row[2]
		for key: String in fields:
			var value: Variant = fields[key]
			if key == "cost_rotten" or key == "item":
				value = load(ITEM_DIR + String(value) + ".tres")
			deal.set(key, value)
		choice.deal = deal
		var path := DIR + id + ".tres"
		var err := ResourceSaver.save(choice, path)
		if err != OK:
			push_error("bootstrap_pacts: could not write %s (%d)" % [path, err])
			continue
		pacts.append(load(path) as EventChoiceData)
	var run := load(RUN_PATH) as RunData
	run.pacts = pacts
	run.pact_title = "The Crossroads"
	run.pact_text = "A masked figure waits where the road splits. It offers a gift for the road ahead, and names its price."
	run.pact_picture_path = "res://assets/sprites/events/whispering_mask.png"
	var err := ResourceSaver.save(run, RUN_PATH)
	if err != OK:
		push_error("bootstrap_pacts: could not write the run (%d)" % err)
	print("bootstrap_pacts: %d pacts" % pacts.size())
	quit()
