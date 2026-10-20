class_name RelicCollection
extends RefCounted
## The Relics this machine has found (DESIGN.md 8.17, 8.19), kept forever between runs: which Relics
## were found, each one's Echo pips (filled by wearing it in won fights, run after run; full pips
## mean its Echo is learned for good), and the Relic bag (cards #265, #266): the Relics the team
## brings into the next run, picked on the main menu's Relics page. The bag starts small and grows
## with the Echoes learned. Relic levels are not kept: they last one run (RunState). Pure: RelicFile
## saves it.

## 2 since phase 21 (#280): found + pips. A file of format 1 (levels kept forever) still loads: every
## Relic it holds is found, and its old level becomes pips (LEGACY_PIPS_PER_LEVEL per level above 1,
## so the old top level 5 is a full 12).
const FORMAT_VERSION: int = 2
const LEGACY_FORMAT: int = 1
const LEGACY_PIPS_PER_LEVEL: int = 3

## Relic id -> true for every Relic ever found, in the order found.
var found: Dictionary = {}
## Relic id -> Echo pips filled so far (only found Relics; never above the pips needed).
var pips: Dictionary = {}
## The Relic ids in the bag, in the order they were put in (only Relics found, each once).
var bag: Array[String] = []


## True if the Relic with this id was ever found.
func owns(id: String) -> bool:
	return found.has(id)


## The Relic's Echo pips (0: none yet, or not found).
func pips_of(id: String) -> int:
	return int(pips.get(id, 0))


## True if the Relic's Echo is learned for good (its pips reached `needed`).
func is_learned(id: String, needed: int) -> bool:
	return owns(id) and pips_of(id) >= needed


## How many Echoes are learned for good.
func learned_count(needed: int) -> int:
	var total := 0
	for id: Variant in found:
		if is_learned(String(id), needed):
			total += 1
	return total


## How many different Relics were found.
func count() -> int:
	return found.size()


## The found Relic ids, in the order found.
func found_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in found:
		ids.append(String(id))
	return ids


## How many Relics the bag holds (card #266): tuning.relic_bag_start, one more for every
## relic_bag_echoes_per_slot Echoes learned, never past relic_bag_max.
func bag_size(tuning: Tuning) -> int:
	if tuning == null:
		return 0
	var grown := learned_count(tuning.mastery_needed) / maxi(1, tuning.relic_bag_echoes_per_slot)
	return clampi(tuning.relic_bag_start + grown, 0, maxi(tuning.relic_bag_start, tuning.relic_bag_max))


## Takes a run in: every Relic in `found_ids` is found, and each Relic's pips become the higher of
## the two (`run_pips`: id -> the run's total), so taking the same run in twice changes nothing (a
## continued stop can never farm pips). A Relic found for the first time goes into the bag while it
## has room by `tuning` (null: never; user pick 2026-10-19). Returns true if anything changed.
func merge(found_ids: Array, run_pips: Dictionary, tuning: Tuning = null) -> bool:
	var changed := false
	var firsts: Array[String] = []
	for id: Variant in found_ids:
		if typeof(id) == TYPE_STRING and not owns(String(id)):
			found[String(id)] = true
			firsts.append(String(id))
			changed = true
	for id: Variant in run_pips:
		var value := int(run_pips[id])
		if typeof(id) == TYPE_STRING and owns(String(id)) and value > pips_of(String(id)):
			pips[String(id)] = mini(value, tuning.mastery_needed) if tuning != null else value
			changed = true
	var size := bag_size(tuning)
	for id: String in firsts:
		if bag_ids().size() < size:
			bag = bag_ids()
			bag.append(id)
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


## Takes the last Relics out of the bag while it holds more than `size` (a bag from before the bag
## shrank, card #266). True if anything came out.
func trim_bag(size: int) -> bool:
	var ids := bag_ids()
	if ids.size() <= size:
		return false
	bag = ids.slice(0, maxi(0, size))
	return true


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
	return {"found": found_ids(), "pips": pips.duplicate(), "bag": bag_ids()}


## A collection from to_dict() data; anything malformed in it is skipped, never a crash. Data of
## format 1 ("levels": id -> level) gets every Relic found and LEGACY_PIPS_PER_LEVEL pips per level
## above 1. A file from before the bag (phase 17's per-hero "picks") gets those Relics in its bag.
static func from_dict(d: Dictionary) -> RelicCollection:
	var c := RelicCollection.new()
	var ids: Variant = d.get("found")
	if ids is Array:
		for id: Variant in ids:
			if typeof(id) == TYPE_STRING:
				c.found[String(id)] = true
		var filled: Variant = d.get("pips", {})
		if filled is Dictionary:
			for id: Variant in filled:
				var value: Variant = filled[id]
				if typeof(id) == TYPE_STRING and c.owns(String(id)) and _is_number(value) and int(value) > 0:
					c.pips[String(id)] = int(value)
	else:
		var levels: Variant = d.get("levels", {})
		if levels is Dictionary:
			for id: Variant in levels:
				var level: Variant = levels[id]
				if typeof(id) == TYPE_STRING and _is_number(level) and int(level) > 0:
					c.found[String(id)] = true
					if int(level) > 1:
						c.pips[String(id)] = (int(level) - 1) * LEGACY_PIPS_PER_LEVEL
	var packed: Array = []
	var bag_data: Variant = d.get("bag")
	if bag_data is Array:
		packed = bag_data
	else:
		var chosen: Variant = d.get("picks", {})
		if chosen is Dictionary:
			for hero: Variant in chosen:
				if chosen[hero] is Array:
					packed.append_array(chosen[hero] as Array)
	for id: Variant in packed:
		if typeof(id) == TYPE_STRING and c.owns(String(id)) and not c.bag.has(String(id)):
			c.bag.append(String(id))
	return c


## Every Relic of `gear` found, with its Echo learned (pips `needed`): the --relics=all dev switch
## for balance runs.
static func all_of(gear: Array[GearData], needed: int) -> RelicCollection:
	var c := RelicCollection.new()
	for item: GearData in gear:
		if item != null:
			c.found[item.id] = true
			c.pips[item.id] = needed
	return c


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
