class_name RelicCollection
extends RefCounted
## The Relics this machine has found (DESIGN.md 8.17), kept forever between runs: each Relic's
## level (a copy raises it), and the Relic bag (card #265): the Relics the team brings into the next
## run, picked on the main menu's Relics page. In a run the whole team shares the bag and puts its
## Relics on any hero as slots open; Relics left out of the bag stay home. Pure: RelicFile saves it.
## Only Relics and their levels carry over; Echoes are learned again in every run (RunState).

const FORMAT_VERSION: int = 1

## Relic id -> level (1 or more).
var levels: Dictionary = {}
## The Relic ids in the bag, in the order they were put in (only Relics found, each once).
var bag: Array[String] = []


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
## A Relic found for the first time goes into the bag while it holds fewer than `bag_size` (0: never;
## user pick 2026-10-19). Returns true if anything changed.
func merge(run_levels: Dictionary, bag_size: int = 0) -> bool:
	var changed := false
	for id: Variant in run_levels:
		var level := int(run_levels[id])
		if typeof(id) == TYPE_STRING and level > level_of(String(id)):
			var first := not owns(String(id))
			levels[String(id)] = level
			changed = true
			if first and bag_ids().size() < bag_size:
				bag = bag_ids()
				bag.append(String(id))
	return changed


## The Relic ids in the bag (found ones only).
func bag_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in bag:
		if owns(id) and not ids.has(id):
			ids.append(id)
	return ids


## True if Relic `id` is in the bag.
func in_bag(id: String) -> bool:
	return bag_ids().has(id)


## Puts Relic `id` in the bag, or takes it out if it is in. False if it cannot go in (not found yet,
## or the bag already holds `size`).
func toggle_bag(id: String, size: int) -> bool:
	if in_bag(id):
		bag.erase(id)
		return true
	if not owns(id) or bag_ids().size() >= size:
		return false
	bag = bag_ids()
	bag.append(id)
	return true


## Fills the bag's free room with the found Relics not in it, the best first by `score` (higher
## first, -1 never), ties in `gear` order. For bots and for a player's first bag.
func fill_bag(gear: Array[GearData], size: int, score: Callable) -> void:
	var left: Array[GearData] = []
	for item: GearData in gear:
		if item != null and owns(item.id) and not in_bag(item.id) and int(score.call(item)) >= 0:
			left.append(item)
	# A stable sort: a lower score never jumps ahead of a higher one, equal ones keep gear's order.
	var ranked: Array[GearData] = []
	while not left.is_empty():
		var best := 0
		for i: int in left.size():
			if int(score.call(left[i])) > int(score.call(left[best])):
				best = i
		ranked.append(left.pop_at(best))
	bag = bag_ids()
	for item: GearData in ranked:
		if bag.size() >= size:
			break
		bag.append(item.id)


## Everything as plain data (for RelicFile).
func to_dict() -> Dictionary:
	return {"levels": levels.duplicate(), "bag": bag_ids()}


## A collection from to_dict() data; anything malformed in it is skipped, never a crash. A file
## from before the bag (phase 17's per-hero "picks") gets those Relics in its bag, heroes in order.
static func from_dict(d: Dictionary) -> RelicCollection:
	var c := RelicCollection.new()
	var found: Variant = d.get("levels", {})
	if found is Dictionary:
		for id: Variant in found:
			var level: Variant = found[id]
			if typeof(id) == TYPE_STRING and (typeof(level) == TYPE_INT or typeof(level) == TYPE_FLOAT) and int(level) > 0:
				c.levels[String(id)] = int(level)
	var ids: Array = []
	var packed: Variant = d.get("bag")
	if packed is Array:
		ids = packed
	else:
		var chosen: Variant = d.get("picks", {})
		if chosen is Dictionary:
			for hero: Variant in chosen:
				if chosen[hero] is Array:
					ids.append_array(chosen[hero] as Array)
	for id: Variant in ids:
		if typeof(id) == TYPE_STRING and c.owns(String(id)) and not c.bag.has(String(id)):
			c.bag.append(String(id))
	return c


## Every Relic of `gear` found at the top level (the --relics=all dev switch for balance runs).
static func all_of(gear: Array[GearData], level: int) -> RelicCollection:
	var c := RelicCollection.new()
	for item: GearData in gear:
		if item != null:
			c.levels[item.id] = level
	return c
