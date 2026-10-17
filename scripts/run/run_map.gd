class_name RunMap
extends RefCounted
## The branching map of one run (DESIGN.md 8), like Slay the Spire: rows of stops from the
## bottom (row 0) to the final fight at the top. Every stop leads to one or more stops in the next
## row, paths never cross, every stop can be reached and every stop reaches the final fight.
## Pure and seeded (CombatRng), so the same seed always makes the same map.

## ELITE, EVENT and TREASURE came in phase 15 (DESIGN.md 8.6 to 8.8); new types go at the end so
## saved numbers keep their meaning.
enum StopType { ZONE, REST, SHOP, FINAL, ELITE, EVENT, TREASURE }

const TYPE_NAMES: Array[String] = ["zone", "rest", "shop", "final", "elite", "event", "treasure"]
## A middle stop re-rolls its type this many times to avoid repeating its parent's shop or rest.
const TYPE_REROLLS: int = 6

## Every stop: {id: int, row: int, col: int, width: int (stops in that row), type: StopType,
## zone: int (index into the act's zones: a zone stop's place, an elite fight's look; -1 for the
## others), next: Array[int], prev: Array[int]}.
var stops: Array[Dictionary] = []
## Stop ids per row, left to right. The last row holds only the final fight.
var rows: Array[Array] = []


## Makes a map: tuning.run_map_rows rows, then the final fight. `zone_count` zones to pick from.
## An act with no elite fights or no events (`has_elites`, `has_events` false) never gets those
## stops, so a stop can never be left with nothing to play.
static func generate(rng: CombatRng, tuning: Tuning, zone_count: int, has_elites: bool = true,
		has_events: bool = true) -> RunMap:
	var map := RunMap.new()
	var row_total := maxi(2, tuning.run_map_rows)
	var lo := clampi(mini(tuning.run_map_min_width, tuning.run_map_max_width), 1, 6)
	var hi := clampi(maxi(tuning.run_map_min_width, tuning.run_map_max_width), 1, 6)
	for r: int in row_total:
		map._add_row(r, rng.range_int(lo, hi))
	map._add_row(row_total, 1)
	for r: int in row_total:
		map._connect(r, rng, tuning.run_map_extra_path_percent)
	map._assign_types(rng, tuning, has_elites, has_events)
	map._assign_zones(rng, zone_count)
	return map


func stop(id: int) -> Dictionary:
	return stops[id] if id >= 0 and id < stops.size() else {}


func row_count() -> int:
	return rows.size()


func final_id() -> int:
	return int(rows[rows.size() - 1][0]) if not rows.is_empty() else -1


## The stops you can go to from stop `from_id` (-1: the start, so the first row).
func choices(from_id: int) -> Array[int]:
	var list: Array[int] = []
	if from_id < 0:
		if not rows.is_empty():
			for id: int in rows[0]:
				list.append(id)
		return list
	list.assign(stop(from_id).get("next", []))
	return list


## Stops of one type (tests and the bot).
func count_type(type: StopType) -> int:
	var n := 0
	for s: Dictionary in stops:
		if int(s.type) == type:
			n += 1
	return n


## True if two paths between the same two rows cross: (a1 -> b1) and (a2 -> b2), by column.
static func paths_cross(a1: int, b1: int, a2: int, b2: int) -> bool:
	return (a1 < a2 and b1 > b2) or (a1 > a2 and b1 < b2)


# --- building ---------------------------------------------------------------------------------

func _add_row(r: int, width: int) -> void:
	var ids: Array[int] = []
	for col: int in width:
		var id := stops.size()
		var next: Array[int] = []
		var prev: Array[int] = []
		stops.append({"id": id, "row": r, "col": col, "width": width, "type": StopType.ZONE, "zone": -1,
				"next": next, "prev": prev})
		ids.append(id)
	rows.append(ids)


## Paths from row `r` to row r + 1: every stop to the nearest stop above it, every stop above
## reached by at least one, then a few extra paths to neighbours. Never crossing.
func _connect(r: int, rng: CombatRng, extra_percent: int) -> void:
	var below: Array = rows[r]
	var above: Array = rows[r + 1]
	var na := below.size()
	var nb := above.size()
	var pairs: Array[Vector2i] = []
	for i: int in na:
		pairs.append(Vector2i(i, _nearest(i, na, nb)))
	for j: int in nb:
		var reached := false
		for p: Vector2i in pairs:
			if p.y == j:
				reached = true
		if reached:
			continue
		# Closest stop below first; the first one that crosses nothing gets the path.
		var order: Array[int] = []
		for i: int in na:
			order.append(i)
		var target := _nearest(j, nb, na)
		order.sort_custom(func(x: int, y: int) -> bool: return absi(x - target) < absi(y - target))
		for i: int in order:
			if _can_add(pairs, i, j):
				pairs.append(Vector2i(i, j))
				break
	for i: int in na:
		if rng.range_int(1, 100) > extra_percent:
			continue
		var step := 1 if rng.range_int(0, 1) == 1 else -1
		var j := _nearest(i, na, nb) + step
		if j >= 0 and j < nb and _can_add(pairs, i, j):
			pairs.append(Vector2i(i, j))
	for p: Vector2i in pairs:
		var from := int(below[p.x])
		var to := int(above[p.y])
		(stops[from].next as Array).append(to)
		(stops[to].prev as Array).append(from)
	for id: int in below:
		(stops[id].next as Array).sort_custom(func(x: int, y: int) -> bool: return int(stops[x].col) < int(stops[y].col))


## Column in a row of `to_width` closest to column `col` of a row of `from_width` (integers).
@warning_ignore("integer_division")
static func _nearest(col: int, from_width: int, to_width: int) -> int:
	if from_width <= 1:
		return (to_width - 1) / 2
	return (col * (to_width - 1) * 2 + (from_width - 1)) / (2 * (from_width - 1))


static func _can_add(pairs: Array[Vector2i], i: int, j: int) -> bool:
	for p: Vector2i in pairs:
		if p == Vector2i(i, j) or paths_cross(p.x, p.y, i, j):
			return false
	return true


## Row 0 is zones, the row before the final fight rests, run_treasure_row treasure; the others
## are picked by weight: zones, shops, rests, elites (not before run_elite_min_row) and events.
func _assign_types(rng: CombatRng, tuning: Tuning, has_elites: bool = true, has_events: bool = true) -> void:
	var last := rows.size() - 1
	var weights: Array[int] = [tuning.run_weight_zone, tuning.run_weight_rest, tuning.run_weight_shop,
			tuning.run_weight_elite, tuning.run_weight_event]
	var kinds: Array[int] = [StopType.ZONE, StopType.REST, StopType.SHOP, StopType.ELITE, StopType.EVENT]
	var middle: Array[int] = []
	for r: int in rows.size():
		for id: int in rows[r]:
			var s: Dictionary = stops[id]
			if r == last:
				s.type = StopType.FINAL
			elif r == 0:
				s.type = StopType.ZONE
			elif r == last - 1:
				s.type = StopType.REST
			elif r == tuning.run_treasure_row:
				s.type = StopType.TREASURE
			else:
				middle.append(id)
				var row_weights := weights.duplicate()
				if r < tuning.run_elite_min_row or not has_elites:
					row_weights[3] = 0
				if not has_events:
					row_weights[4] = 0
				s.type = _pick_middle(rng, row_weights, kinds, s, r == last - 2)
	if count_type(StopType.SHOP) == 0 and not middle.is_empty():
		stops[middle[rng.range_int(0, middle.size() - 1)]].type = StopType.SHOP


## A middle stop's type: never the same shop, rest or elite as a stop leading to it, and no rest
## right before the rest row.
func _pick_middle(rng: CombatRng, weights: Array[int], kinds: Array[int], s: Dictionary,
		before_rest_row: bool) -> int:
	for attempt: int in TYPE_REROLLS:
		var index := rng.pick_weighted(weights)
		var type := kinds[index] if index >= 0 else StopType.ZONE
		if type == StopType.ZONE or type == StopType.EVENT:
			return type
		if type == StopType.REST and before_rest_row:
			continue
		var repeats := false
		for p: int in s.prev:
			if int(stops[p].type) == type:
				repeats = true
		if not repeats:
			return type
	return StopType.ZONE


## Each zone stop gets a zone, if possible not the one met last on any path leading to it (shops
## and rests in between do not count), so the same place does not come twice in a row.
func _assign_zones(rng: CombatRng, zone_count: int) -> void:
	if zone_count <= 0:
		return
	for s: Dictionary in stops:
		if int(s.type) == StopType.ELITE:
			# An elite fight takes place in one of the act's zones (its look).
			s.zone = rng.range_int(0, zone_count - 1)
			continue
		if int(s.type) != StopType.ZONE:
			continue
		var recent := last_zones_before(int(s.id))
		var allowed: Array[int] = []
		for z: int in zone_count:
			if not recent.has(z):
				allowed.append(z)
		if allowed.is_empty():
			s.zone = rng.range_int(0, zone_count - 1)
		else:
			s.zone = allowed[rng.range_int(0, allowed.size() - 1)]


## The zones of the closest zone stops on every path leading to stop `id` ({zone: true}).
func last_zones_before(id: int) -> Dictionary:
	var found := {}
	var seen := {}
	var todo: Array[int] = []
	todo.assign(stop(id).get("prev", []))
	while not todo.is_empty():
		var p: int = todo.pop_back()
		if seen.has(p):
			continue
		seen[p] = true
		if int(stops[p].type) == StopType.ZONE:
			if int(stops[p].zone) >= 0:
				found[int(stops[p].zone)] = true
		else:
			todo.append_array(stops[p].prev)
	return found
