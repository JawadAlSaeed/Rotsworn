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
## others), next: Array[int], prev: Array[int], crown: bool (the act's crowned elite, card #286)}.
var stops: Array[Dictionary] = []
## Stop ids per row, left to right. The last row holds only the final fight.
var rows: Array[Array] = []


## Makes a map: tuning.run_map_rows rows, then the final fight. `zone_count` zones to pick from.
## An act with no elite fights or no events (`has_elites`, `has_events` false) never gets those
## stops, so a stop can never be left with nothing to play.
## `moving_rows` false: the map rules before phase 21 (no moved rows, no crowned elite), for a run
## saved before it.
static func generate(rng: CombatRng, tuning: Tuning, zone_count: int, has_elites: bool = true,
		has_events: bool = true, moving_rows: bool = true) -> RunMap:
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
	# Phase 21 (card #286), after the rest so a seed's paths stay as they were: the campfire and
	# treasure rows move, and one elite wears the rot crown.
	if moving_rows:
		map._vary_rows(rng, tuning, has_elites, has_events)
		map._crown_elite(rng, tuning, has_elites)
		map._fix_zones(rng, zone_count)
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


## The weights of the middle types (zone, rest, shop, elite, event) for a stop in row `r`.
func _middle_weights(tuning: Tuning, r: int, has_elites: bool, has_events: bool) -> Array[int]:
	var weights: Array[int] = [tuning.run_weight_zone, tuning.run_weight_rest, tuning.run_weight_shop,
			tuning.run_weight_elite, tuning.run_weight_event]
	if r < tuning.run_elite_min_row or not has_elites:
		weights[3] = 0
	if not has_events:
		weights[4] = 0
	return weights


## The campfire row is one row earlier tuning.run_rest_row_shift_percent of the time, and the
## treasure row moves up to tuning.run_treasure_row_spread rows (card #286), so rest and reward land
## in different places each act. A row that gives up its campfires or its chests gets middle stops,
## with the old rules kept: never the same shop, campfire or elite twice in a row, no campfire right
## before the campfire row, and a shop somewhere on the map.
func _vary_rows(rng: CombatRng, tuning: Tuning, has_elites: bool, has_events: bool) -> void:
	var last := rows.size() - 1
	var rest_row := last - 1
	if rest_row - 1 > tuning.run_treasure_row and rest_row - 1 >= 1 			and rng.range_int(0, 99) < tuning.run_rest_row_shift_percent:
		for id: int in rows[rest_row - 1]:
			stops[id].type = StopType.REST
		for id: int in rows[rest_row]:
			_retype(stops[id], rng, _middle_weights(tuning, rest_row, has_elites, has_events), true)
		rest_row -= 1
		for id: int in rows[rest_row - 1]:
			if int(stops[id].type) == StopType.REST:
				_retype(stops[id], rng, _middle_weights(tuning, rest_row - 1, has_elites, has_events), true)
	var treasure := tuning.run_treasure_row
	if treasure >= 1 and treasure < rest_row:
		var spread := maxi(0, tuning.run_treasure_row_spread)
		var moved := clampi(treasure + rng.range_int(-spread, spread), 1, rest_row - 1)
		if moved != treasure:
			for id: int in rows[moved]:
				stops[id].type = StopType.TREASURE
			for id: int in rows[treasure]:
				_retype(stops[id], rng, _middle_weights(tuning, treasure, has_elites, has_events), treasure == rest_row - 1)
	if count_type(StopType.SHOP) == 0:
		var spots: Array[int] = []
		for r: int in range(1, rest_row):
			for id: int in rows[r]:
				var st: Dictionary = stops[id]
				if int(st.type) != StopType.TREASURE and not _neighbour_has(st, StopType.SHOP):
					spots.append(id)
		if not spots.is_empty():
			stops[spots[rng.range_int(0, spots.size() - 1)]].type = StopType.SHOP


## Gives stop `s` a middle type by `weights` (zone, rest, shop, elite, event) that is not the same
## shop, campfire or elite as a stop next to it (before or after), and no campfire when `no_rest`.
func _retype(s: Dictionary, rng: CombatRng, weights: Array[int], no_rest: bool) -> void:
	var kinds: Array[int] = [StopType.ZONE, StopType.REST, StopType.SHOP, StopType.ELITE, StopType.EVENT]
	for attempt: int in TYPE_REROLLS:
		var index := rng.pick_weighted(weights)
		var type := kinds[index] if index >= 0 else StopType.ZONE
		if type == StopType.REST and no_rest:
			continue
		if type != StopType.ZONE and type != StopType.EVENT and _neighbour_has(s, type):
			continue
		s.type = type
		return
	s.type = StopType.ZONE


## True if a stop leading to `s` or one it leads to is of `type`.
func _neighbour_has(s: Dictionary, type: int) -> bool:
	for id: Variant in s.prev:
		if int(stops[int(id)].type) == type:
			return true
	for id: Variant in s.next:
		if int(stops[int(id)].type) == type:
			return true
	return false


## One elite of the act wears the rot crown (card #286): harder, and its spoils always hold a
## legendary Relic. An act with elites gets at least one elite stop for it (a middle zone or "?"
## stop from tuning.run_elite_min_row up with no elite next to it, so a road goes through it:
## every stop can be reached).
func _crown_elite(rng: CombatRng, tuning: Tuning, has_elites: bool) -> void:
	for s: Dictionary in stops:
		s.crown = false
	if not has_elites:
		return
	var elites: Array[int] = []
	var spare: Array[int] = []
	for s: Dictionary in stops:
		if int(s.type) == StopType.ELITE:
			elites.append(int(s.id))
		elif (int(s.type) == StopType.ZONE or int(s.type) == StopType.EVENT) and int(s.row) >= tuning.run_elite_min_row 				and not _neighbour_has(s, StopType.ELITE):
			spare.append(int(s.id))
	if elites.is_empty():
		if spare.is_empty():
			return
		var made: Dictionary = stops[spare[rng.range_int(0, spare.size() - 1)]]
		made.type = StopType.ELITE
		elites.append(int(made.id))
	stops[elites[rng.range_int(0, elites.size() - 1)]].crown = true


## After rows moved: every zone stop with no zone, or with the zone met last on the way to it, gets
## a fresh one (row by row, so each sees the stops before it as they end up); elites keep or get a
## zone (their look); every other stop has none.
func _fix_zones(rng: CombatRng, zone_count: int) -> void:
	if zone_count <= 0:
		return
	for row: Array in rows:
		for id: int in row:
			var s: Dictionary = stops[id]
			match int(s.type):
				StopType.ELITE:
					if int(s.zone) < 0:
						s.zone = rng.range_int(0, zone_count - 1)
				StopType.ZONE:
					var recent := last_zones_before(id)
					if int(s.zone) < 0 or recent.has(int(s.zone)):
						var allowed: Array[int] = []
						for z: int in zone_count:
							if not recent.has(z):
								allowed.append(z)
						s.zone = allowed[rng.range_int(0, allowed.size() - 1)] if not allowed.is_empty() 								else rng.range_int(0, zone_count - 1)
				_:
					s.zone = -1


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
