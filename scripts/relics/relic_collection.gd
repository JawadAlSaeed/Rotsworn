class_name RelicCollection
extends RefCounted
## The Relics this machine has found (DESIGN.md 8.17), kept forever between runs: each Relic's
## level (a copy raises it), and the Relics each hero is set to bring into the next run (picked on
## the main menu's Relics screen; a run puts them on as its slots open). Pure: RelicFile saves it.
## Only Relics and their levels carry over; Echoes are learned again in every run (RunState).

const FORMAT_VERSION: int = 1

## Relic id -> level (1 or more).
var levels: Dictionary = {}
## Hero (CharacterData) id -> the Relic ids to bring, in the order they go on.
var picks: Dictionary = {}


## True if the Relic with this id was ever found.
func owns(id: String) -> bool:
	return levels.has(id)


## The Relic's level (0: not found yet).
func level_of(id: String) -> int:
	return int(levels.get(id, 0))


## How many different Relics were found.
func count() -> int:
	return levels.size()


## Takes the run's Relics in (RunState.relics: id -> level): every Relic at the higher of the two
## levels, so taking the same run in twice changes nothing (a continued stop can never farm a copy).
## Returns true if anything changed.
func merge(run_levels: Dictionary) -> bool:
	var changed := false
	for id: Variant in run_levels:
		var level := int(run_levels[id])
		if typeof(id) == TYPE_STRING and level > level_of(String(id)):
			levels[String(id)] = level
			changed = true
	return changed


## The Relic ids hero `hero_id` brings into the next run.
func picks_for(hero_id: String) -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in picks.get(hero_id, []):
		if typeof(id) == TYPE_STRING and owns(String(id)):
			ids.append(String(id))
	return ids


## Sets what hero `hero_id` brings (only Relics found, each once, at most `slots`); a Relic picked
## for another hero moves to this one.
func set_picks(hero_id: String, ids: Array[String], slots: int) -> void:
	var kept: Array = []
	for id: String in ids:
		if owns(id) and not kept.has(id) and kept.size() < slots:
			kept.append(id)
	for other: Variant in picks.keys():
		if String(other) != hero_id:
			var theirs: Array = (picks[other] as Array).filter(func(x: Variant) -> bool: return not kept.has(x))
			picks[other] = theirs
	picks[hero_id] = kept


## The hero id that brings Relic `id` ("" if nobody does).
func picked_by(id: String) -> String:
	for hero: Variant in picks:
		if (picks[hero] as Array).has(id):
			return String(hero)
	return ""


## Everything as plain data (for RelicFile).
func to_dict() -> Dictionary:
	return {"levels": levels.duplicate(), "picks": picks.duplicate(true)}


## A collection from to_dict() data; anything malformed in it is skipped, never a crash.
static func from_dict(d: Dictionary) -> RelicCollection:
	var c := RelicCollection.new()
	var found: Variant = d.get("levels", {})
	if found is Dictionary:
		for id: Variant in found:
			var level: Variant = found[id]
			if typeof(id) == TYPE_STRING and (typeof(level) == TYPE_INT or typeof(level) == TYPE_FLOAT) and int(level) > 0:
				c.levels[String(id)] = int(level)
	var chosen: Variant = d.get("picks", {})
	if chosen is Dictionary:
		for hero: Variant in chosen:
			if typeof(hero) == TYPE_STRING and chosen[hero] is Array:
				var ids: Array = []
				for id: Variant in chosen[hero]:
					if typeof(id) == TYPE_STRING and c.owns(String(id)) and not ids.has(String(id)):
						ids.append(String(id))
				c.picks[String(hero)] = ids
	return c


## Every Relic of `gear` found at the top level (the --relics=all dev switch for balance runs).
static func all_of(gear: Array[GearData], level: int) -> RelicCollection:
	var c := RelicCollection.new()
	for item: GearData in gear:
		if item != null:
			c.levels[item.id] = level
	return c
