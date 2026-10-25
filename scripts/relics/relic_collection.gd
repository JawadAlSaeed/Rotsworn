class_name RelicCollection
extends RefCounted
## The Relic book (DESIGN.md 8.17, 8.24, card #328): every Relic this machine ever found (picked in a
## run, won or lost), kept forever between runs. Before a run each hero may take one Relic from it
## (RunState.start_left). Pure: RelicFile saves it.

## 3 since the Relic book (#328): the found Relics only. Files of format 1 (levels kept forever,
## phases 17 to 20) and 2 (Echo pips and the Relic bag, phases 21 to 26) still load: every Relic they
## hold is found; levels, pips and the bag are dropped.
const FORMAT_VERSION: int = 3
## The older formats that still load (RelicFile).
const OLD_FORMATS: Array[int] = [1, 2]

## Relic id -> true for every Relic ever found, in the order found.
var found: Dictionary = {}


## True if the Relic with this id was ever found.
func owns(id: String) -> bool:
	return found.has(id)


## How many different Relics were found.
func count() -> int:
	return found.size()


## The found Relic ids, in the order found.
func found_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in found:
		ids.append(String(id))
	return ids


## The found Relics of `gear` (a run's RunData.gear), in `gear`'s order.
func found_of(gear: Array[GearData]) -> Array[GearData]:
	var list: Array[GearData] = []
	for item: GearData in gear:
		if item != null and owns(item.id):
			list.append(item)
	return list


## Takes a run in: every Relic in `found_ids` is found, so taking the same run in twice changes
## nothing. Returns true if anything changed.
func merge(found_ids: Array) -> bool:
	var changed := false
	for id: Variant in found_ids:
		if typeof(id) == TYPE_STRING and not owns(String(id)):
			found[String(id)] = true
			changed = true
	return changed


## Everything as plain data (for RelicFile).
func to_dict() -> Dictionary:
	return {"found": found_ids()}


## A book from to_dict() data; anything malformed in it is skipped, never a crash. Data of format 1
## ("levels": id -> level) gets every Relic found; format 2's Echo pips and bag are dropped (a Relic
## in its bag was found, so it is in "found").
static func from_dict(d: Dictionary) -> RelicCollection:
	var c := RelicCollection.new()
	var ids: Variant = d.get("found")
	if ids is Array:
		for id: Variant in ids:
			if typeof(id) == TYPE_STRING:
				c.found[String(id)] = true
	else:
		var levels: Variant = d.get("levels", {})
		if levels is Dictionary:
			for id: Variant in levels:
				var level: Variant = levels[id]
				if typeof(id) == TYPE_STRING and _is_number(level) and int(level) > 0:
					c.found[String(id)] = true
	return c


## Every Relic of `gear` found: the --relics=all dev switch for balance runs.
static func all_of(gear: Array[GearData]) -> RelicCollection:
	var c := RelicCollection.new()
	for item: GearData in gear:
		if item != null:
			c.found[item.id] = true
	return c


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
