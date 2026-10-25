extends GutTest
## A run without zones (DESIGN.md 8.22, cards #316 and #317, and the guards joining the Elite stops):
## new maps (rules 4) have no Guard stops, and an Elite stop holds one of its act's elite groups or
## its place's guard, a seeded pick (run_elite_guard_percent) that never gives a road the guard at
## two Elite stops in a row; the guard pays its spoils (a crowned one the crown's legendary), and an
## elite group or a guard gives a pick of Relics, a plain fight none (DESIGN.md 8.24). Map rules 3 (a row of Guard stops) and 1 and 2 stay as
## they were for older runs. A Fight stop's fight, every run fight's weather and a Fight stop's drop
## are seeded picks from the run state alone (the same on every machine, an online friend builds the
## same fight); a Fight stop never repeats the last Fight stop's fight while its place has another;
## old saves are kept but not offered; the bots' readiness habit lives in RunAutoplay.
## Uses the shipped run data; files go to the system temp folder, never user://.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const MAIN_PATH := "res://scenes/main.gd"
const SEEDS: int = 60
const HOST: int = 1
const PEER_A: int = 1001

var _data: RunData
var _tuning: Tuning
var _main: GDScript
var _save_path: String = ""


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_main = load(MAIN_PATH) as GDScript


func before_each() -> void:
	_tuning = (load(TUNING_PATH) as Tuning).duplicate() as Tuning


func after_each() -> void:
	if not _save_path.is_empty():
		RunSave.delete(_save_path)
		_save_path = ""


func _run(seed_value: int = 7) -> RunState:
	return RunState.begin(_data, _tuning, seed_value)


## The first stop of `type` on the current act's map (-1: none).
func _first(run: RunState, type: int) -> int:
	for stop: Dictionary in run.map.stops:
		if int(stop.type) == type:
			return int(stop.id)
	return -1


## Walks `run` from the start to a stop of `type` along the map's roads (each step the first choice
## that can still reach one). False if none is reachable.
func _walk_to(run: RunState, type: int) -> bool:
	while not run.is_over():
		var picked := -1
		for id: int in run.choices():
			if int(run.map.stop(id).type) == type:
				run.go(id)
				return true
			if picked < 0 and _leads_to(run.map, id, type):
				picked = id
		if picked < 0:
			return false
		run.go(picked)
		run.end_ambush()
	return false


func _leads_to(map: RunMap, from_id: int, type: int) -> bool:
	for id: int in MapScreen.reachable_from(map, from_id):
		if int(map.stop(id).type) == type:
			return true
	return false


## Walks `run` from where it is to stop `target` along the map's roads. False if it cannot get there.
func _walk_to_stop(run: RunState, target: int) -> bool:
	while not run.is_over() and run.at != target:
		var picked := -1
		for id: int in run.choices():
			if picked < 0 and MapScreen.reachable_from(run.map, id).has(target):
				picked = id
		if picked < 0:
			return false
		run.go(picked)
		run.end_ambush()
	return run.at == target


## A run of map rules 3 (a row of Guard stops), as a run saved before the guards joined the Elite
## stops would load.
func _rules_3_run(seed_value: int = 7) -> RunState:
	var old := _run(seed_value).to_dict()
	old["map_rules"] = 3
	return RunState.from_dict(_data, _tuning, old)


## The nearest Elite stops on the roads leading to stop `id` (the stops between are passed through).
func _elites_before(map: RunMap, id: int) -> Array[int]:
	var found: Array[int] = []
	var seen := {}
	var todo: Array[int] = []
	todo.assign(map.stop(id).prev)
	while not todo.is_empty():
		var p: int = todo.pop_back()
		if seen.has(p):
			continue
		seen[p] = true
		if int(map.stop(p).type) == RunMap.StopType.ELITE:
			found.append(p)
		else:
			todo.append_array(map.stop(p).prev)
	return found


## The first seed (from 1) whose first act has an Elite stop that holds the guard (`guard`) or an
## elite group, and that stop: [seed, stop id], or [-1, -1].
func _elite_stop_holding(guard: bool) -> Array[int]:
	for s: int in range(1, SEEDS * 4):
		var run := _run(s)
		for stop: Dictionary in run.map.stops:
			if int(stop.type) == RunMap.StopType.ELITE and run.elite_holds_guard(int(stop.id)) == guard:
				return [s, int(stop.id)] as Array[int]
	return [-1, -1] as Array[int]


## The host and one friend online, a share of the heroes each.
func _online_two() -> PlayerRoster:
	var roster := PlayerRoster.online(_data.party.size(), HOST, HOST)
	roster.join_peer(PEER_A)
	return roster


## What a friend's machine makes of the catch-up messages (run_start, then each screen's state).
func _friend_after(messages: Array[Dictionary]) -> RunState:
	var start := bytes_to_var(var_to_bytes(messages[0].payload as Dictionary)) as Dictionary
	var game: RunState = _main.call("_client_game", _data, _tuning, int(start.seed), int(start.oath))
	if game == null:
		return null
	for message: Dictionary in messages.slice(1):
		var screen := bytes_to_var(var_to_bytes(message.payload as Dictionary)) as Dictionary
		assert_true(game.apply_dict(screen.run as Dictionary), "%s fits the friend's run" % screen.name)
	return game


## Main.AfterFight's value `key` (-1: none).
func _after_fight(key: String) -> int:
	var values: Variant = _main.get_script_constant_map().get("AfterFight", {})
	return int((values as Dictionary).get(key, -1)) if values is Dictionary else -1


## The text of function `header` in main.gd, up to the next top-level function.
func _body(header: String) -> String:
	var source := FileAccess.get_file_as_string(MAIN_PATH)
	var start := source.find(header)
	assert_gt(start, -1, "found: %s" % header)
	if start < 0:
		return ""
	var end := source.find("\nfunc ", start + 1)
	var static_end := source.find("\nstatic func ", start + 1)
	if static_end > 0 and (end < 0 or static_end < end):
		end = static_end
	return source.substr(start, end - start if end > start else -1)


# --- map rules 4: no Guard stops ---------------------------------------------------------------------

## New maps have no Guard stop and no guard row: the row that was the guards' gets ordinary stops by
## the rules that made it before the guard row came (a rules 4 map is a rules 2 map), so the elite
## stops keep their rows and counts.
func test_new_maps_have_no_guard_stops_and_the_guard_row_is_ordinary_again() -> void:
	assert_eq(RunState.MAP_RULES, 4)
	var row_one := {}
	for s: int in range(1, SEEDS):
		var run := _run(s)
		assert_eq(run.map_rules, 4)
		for act: int in run.acts().size():
			var map := run._make_map(act)
			assert_eq(map.count_type(RunMap.StopType.GUARD), 0, "seed %d act %d: no Guard stops" % [s, act + 1])
			assert_eq(map.stops, run._make_map(act, 2).stops, "seed %d act %d: the rules 2 map" % [s, act + 1])
			for id: int in map.rows[0]:
				assert_eq(int(map.stop(id).type), RunMap.StopType.FIGHT, "row 0 stays all Fight stops")
			for id: int in map.rows[1]:
				row_one[int(map.stop(id).type)] = true
		if is_failing():
			return
	assert_gt(row_one.size(), 2, "row 1 holds ordinary stops of several kinds: %s" % str(row_one.keys()))


# --- Elite stops: an elite group or the place's guard ------------------------------------------------

## The pick is the run's: the same from the same state, on every machine, wherever the party walked,
## and the stop fights what it holds (the guard is its place's, deep in a deep act or row; a group is
## one of the act's elites).
func test_an_elite_stops_pick_is_seeded_and_stable() -> void:
	var kinds := {}
	for s: int in range(1, SEEDS):
		var run := _run(s)
		var copy := RunState.from_dict(_data, _tuning, run.to_dict())
		for act: int in run.acts().size():
			if act > 0:
				run.next_act()
				copy.next_act()
			for stop: Dictionary in run.map.stops:
				var id := int(stop.id)
				var held := run.elite_holds_guard(id)
				if int(stop.type) != RunMap.StopType.ELITE:
					assert_false(held, "only Elite stops hold a guard")
					assert_null(run.guard_of(id), "no guard at a %s stop" % RunMap.TYPE_NAMES[int(stop.type)])
					continue
				assert_eq(copy.elite_holds_guard(id), held, "seed %d: the same pick from the same state" % s)
				assert_eq(run.elite_holds_guard(id), held, "asked again: the same")
				kinds[held] = true
				var fight := run.elite_stop_fight(id)
				var place := run.zone_of(stop)
				assert_not_null(fight, "seed %d: an Elite stop always has a fight" % s)
				if fight == null:
					continue
				if held:
					assert_true(fight == place.guard or fight == place.guard.deep, "its place's guard")
					assert_true(fight.mini_boss and not fight.can_run, "a guard, no running")
					var deep := run.act_data().deep or int(stop.row) >= _tuning.run_deep_row
					assert_eq(fight, place.guard.deep if deep else place.guard, "deep in a deep act or row")
				else:
					assert_eq(fight, run.elite_of(id), "an elite group")
					assert_true(fight.elite and not fight.mini_boss)
				# Walking there changes nothing: the pick needs no path.
				if s > 20:
					continue
				var walker := RunState.from_dict(_data, _tuning, run.to_dict())
				if _walk_to_stop(walker, id):
					assert_eq(walker.elite_holds_guard(id), held, "seed %d: the same once the party stands there" % s)
					assert_eq(walker.encounter_now(), fight, "and it fights the same")
		if is_failing():
			return
	assert_eq(kinds.size(), 2, "some Elite stops hold the guard, others a group")


## The guard's share of the Elite stops that may hold it matches tuning.run_elite_guard_percent, over
## many seeds (each such stop rolls on its own); 0 never gives a guard, 100 gives one wherever the
## rules allow it.
func test_the_guard_share_follows_the_tuning() -> void:
	var allowed := 0
	var guards := 0
	var all_elites := 0
	for s: int in range(1, 241):
		var run := _run(s)
		for act: int in run.acts().size():
			if act > 0:
				run.next_act()
			for stop: Dictionary in run.map.stops:
				if int(stop.type) != RunMap.StopType.ELITE:
					continue
				all_elites += 1
				var id := int(stop.id)
				if run._guard_elite_before(id):
					continue
				allowed += 1
				guards += 1 if run.elite_holds_guard(id) else 0
	var share := roundi(100.0 * float(guards) / float(maxi(1, allowed)))
	gut.p("Elite stops: %d, could hold the guard: %d, held it: %d (%d%%)" % [all_elites, allowed, guards, share])
	assert_gt(allowed, 300, "enough Elite stops to tell")
	assert_between(share, _tuning.run_elite_guard_percent - 6, _tuning.run_elite_guard_percent + 6,
			"about run_elite_guard_percent of them")
	for percent: int in [0, 100]:
		_tuning.run_elite_guard_percent = percent
		var held := 0
		var could := 0
		for s: int in range(1, SEEDS):
			var run := _run(s)
			for stop: Dictionary in run.map.stops:
				var id := int(stop.id)
				if int(stop.type) != RunMap.StopType.ELITE or run._guard_elite_before(id):
					continue
				could += 1
				held += 1 if run.elite_holds_guard(id) else 0
		assert_eq(held, 0 if percent == 0 else could, "%d%%" % percent)


## No road meets the guard at two Elite stops in a row (while the act has elite groups). With every
## roll a guard (100%) the rule is what keeps the second Elite stop on a road a group.
func test_no_road_meets_the_guard_twice_in_a_row() -> void:
	var blocked := 0
	for percent: int in [_tuning.run_elite_guard_percent, 100]:
		_tuning.run_elite_guard_percent = percent
		for s: int in range(1, SEEDS * 2):
			var run := _run(s)
			for act: int in run.acts().size():
				if act > 0:
					run.next_act()
				for stop: Dictionary in run.map.stops:
					if int(stop.type) != RunMap.StopType.ELITE:
						continue
					var id := int(stop.id)
					var before := _elites_before(run.map, id)
					var guard_before := false
					for p: int in before:
						guard_before = guard_before or run.elite_holds_guard(p)
					if run.elite_holds_guard(id):
						assert_false(guard_before, "seed %d act %d: never the guard twice in a row on a road" % [s, act + 1])
					elif guard_before:
						blocked += 1
			if is_failing():
				return
	assert_gt(blocked, 0, "the rule turned some guards into groups")


## The act's crowned elite rolls like any Elite stop. A crowned guard keeps the crown's spoils (a
## legendary Relic first) but fights as every guard does: the crown's extra HP and power are an elite
## group's.
func test_a_crowned_elite_stop_may_hold_the_guard_with_the_crowns_spoils() -> void:
	_tuning.run_elite_guard_percent = 100
	var crowned_guards := 0
	for s: int in range(1, SEEDS):
		var run := _run(s)
		for stop: Dictionary in run.map.stops:
			var id := int(stop.id)
			if not bool(stop.get("crown", false)) or not run.elite_holds_guard(id):
				continue
			crowned_guards += 1
			assert_true(_walk_to_stop(run, id))
			assert_true(run.is_crowned())
			var guard := run.encounter_now()
			assert_true(guard.mini_boss, "seed %d: the crowned stop holds the guard" % s)
			var spoils := run.loot_choices(id)
			assert_eq(int(spoils[0].rarity), ItemData.Rarity.LEGENDARY, "the crown's legendary comes first")
			var setup := run.fight_setup(guard, 1, CombatSetup.Opening.NORMAL)
			run.map.stops[id].crown = false
			var plain := run.fight_setup(guard, 1, CombatSetup.Opening.NORMAL)
			assert_eq(setup.enemy_hp_percent, plain.enemy_hp_percent, "no crown HP on a guard")
			assert_eq(setup.enemy_power_percent, plain.enemy_power_percent, "no crown power on a guard")
			break
	assert_gt(crowned_guards, 0, "a crowned stop held the guard")


## An act with no elite groups whose place has a guard still gets Elite stops, and every one holds
## the guard (there is nothing else to hold).
func test_an_act_without_elite_groups_holds_its_guard_at_every_elite_stop() -> void:
	var met := 0
	for s: int in range(1, SEEDS):
		var run := _run(s)
		var act := run.act_data(0).duplicate() as ActData
		var none: Array[EncounterData] = []
		act.elites = none
		run._acts[0] = act
		run.map = run._make_map(0)
		for stop: Dictionary in run.map.stops:
			if int(stop.type) == RunMap.StopType.ELITE:
				met += 1
				assert_true(run.elite_holds_guard(int(stop.id)), "seed %d: the guard" % s)
				assert_true(run.elite_stop_fight(int(stop.id)).mini_boss)
	assert_gt(met, 0, "such an act still has Elite stops")


## The map gives an Elite stop any of its act's places, so an act with no elite groups gets Elite
## stops only when every place has a guard: two guarded places, every Elite stop holds its own
## place's guard; one place without a guard, no Elite stops at all (none is left with nothing).
func test_an_act_without_elite_groups_needs_a_guard_in_every_place() -> void:
	var met := 0
	for guarded_both: bool in [true, false]:
		for s: int in range(1, SEEDS):
			var run := _run(s)
			var act := run.act_data(0).duplicate() as ActData
			var none: Array[EncounterData] = []
			act.elites = none
			var other := act.zones[0].duplicate() as ZoneData
			if not guarded_both:
				other.guard = null
			var places: Array[ZoneData] = [act.zones[0], other]
			act.zones = places
			run._acts[0] = act
			run.map = run._make_map(0)
			for stop: Dictionary in run.map.stops:
				if int(stop.type) != RunMap.StopType.ELITE:
					continue
				assert_true(guarded_both, "seed %d: no Elite stop when a place has no guard" % s)
				met += 1
				var fight := run.elite_stop_fight(int(stop.id))
				assert_not_null(fight, "seed %d: never an Elite stop with nothing" % s)
				var guard := run.zone_of(stop).guard
				if fight != null:
					assert_true(fight == guard or fight == guard.deep, "seed %d: its own place's guard" % s)
			if is_failing():
				return
	assert_gt(met, 0, "two guarded places still give Elite stops")


## A guard at an Elite stop pays as a guard did: its spoils (pick 1 of 3 Relics, one more when
## flawless, the line "The guard fell."), no item drop.
func test_a_guard_elite_stop_pays_guard_spoils() -> void:
	var found := _elite_stop_holding(true)
	assert_gt(found[0], 0, "some seed puts the guard at an Elite stop")
	if found[0] < 0:
		return
	var run := _run(found[0])
	assert_true(_walk_to_stop(run, found[1]), "a road reaches it")
	var place := run.zone_of(run.current())
	var guard := run.encounter_now()
	assert_true(guard == place.guard or guard == place.guard.deep, "its place's guard")
	assert_null(run.fight_drop(), "spoils, no item drop")
	var plain_count := run.loot_choice_count()
	assert_eq(plain_count, 3, "pick 1 of 3")
	var owned := run.relics.size()
	run.finish_fight(RunState.VICTORY, run.hp.duplicate(), guard, {"hits_taken": 0})
	assert_eq(run.relics.size(), owned, "the win itself drops no Relic: the spoils give one")
	assert_true(run.flawless, "no hit taken: flawless")
	assert_eq(run.loot_choice_count(), plain_count + 1, "one more spoils choice")
	assert_eq(run.loot_choices(run.at).size(), run.loot_choice_count())
	for item: GearData in run.loot_choices(run.at):
		assert_false(run.owns(item), "only Relics the run does not have")
	assert_eq(_main.call("_after_run_fight", RunState.VICTORY, RunMap.StopType.ELITE, false, false, false, false),
			_after_fight("SPOILS"))
	assert_eq(_main.call("_spoils_line", RunMap.StopType.ELITE, false, true), "The guard fell. Take one.")


## An elite group gives spoils as before; a Fight stop's win and an ambush's (unless its event says
## so) give none, and no won fight drops a Relic by itself (DESIGN.md 8.24).
func test_only_elite_stops_and_bosses_give_spoils() -> void:
	var found := _elite_stop_holding(false)
	assert_gt(found[0], 0)
	if found[0] < 0:
		return
	var run := _run(found[0])
	for id: int in run.choices():
		if run.at < 0 and MapScreen.reachable_from(run.map, id).has(found[1]):
			run.go(id)
	run.end_ambush()
	assert_eq(int(run.current().type), RunMap.StopType.FIGHT, "row 0 is Fight stops")
	var fight := run.encounter_now()
	run.finish_fight(RunState.VICTORY, run.hp.duplicate(), fight)
	assert_true(run.relics.is_empty(), "a Fight stop drops no Relic")
	assert_eq(_main.call("_after_run_fight", RunState.VICTORY, RunMap.StopType.FIGHT, false, false, false, false),
			_after_fight("MAP"), "a Fight stop: on to the map")
	assert_eq(_main.call("_after_run_fight", RunState.VICTORY, RunMap.StopType.ELITE, true, false, false, false),
			_after_fight("MAP"), "an ambush without spoils")
	assert_eq(_main.call("_after_run_fight", RunState.VICTORY, RunMap.StopType.ELITE, true, true, false, false),
			_after_fight("SPOILS"), "an ambush whose event gives spoils")
	assert_eq(_main.call("_after_run_fight", RunState.VICTORY, RunMap.StopType.FINAL, false, false, false, false),
			_after_fight("SPOILS"), "an act's boss")
	assert_true(_walk_to_stop(run, found[1]))
	var group := run.encounter_now()
	assert_true(group.elite and not group.mini_boss, "an elite group")
	run.finish_fight(RunState.VICTORY, run.hp.duplicate(), group)
	assert_true(run.relics.is_empty(), "the win itself drops none: the spoils give one")
	assert_eq(run.loot_choices(run.at).size(), run.loot_choice_count())
	assert_eq(_main.call("_spoils_line", RunMap.StopType.ELITE, false, false), "The elite fell. Take one.")


# --- map rules 3 (runs made before the guards joined the Elite stops) ------------------------------

func test_rules_3_maps_have_a_guard_row_with_a_place_for_every_guard() -> void:
	for s: int in range(1, SEEDS):
		var run := _run(s)
		for act: int in run.acts().size():
			var map := run._make_map(act, 3)
			assert_eq(map.rows[_tuning.run_guard_row].size(), map.count_type(RunMap.StopType.GUARD),
					"seed %d act %d: the guard row is all guards and only it" % [s, act + 1])
			for id: int in map.rows[_tuning.run_guard_row]:
				var stop := map.stop(id)
				assert_eq(int(stop.type), RunMap.StopType.GUARD)
				assert_between(int(stop.zone), 0, run.act_data(act).zones.size() - 1, "a guard stands in a place")
				# Only when the roads here already met every place last can one repeat.
				var recent := map.last_zones_before(id)
				if recent.size() < run.act_data(act).zones.size():
					assert_false(recent.has(int(stop.zone)), "seed %d: not the place just fought in" % s)
			for id: int in map.rows[0]:
				assert_eq(int(map.stop(id).type), RunMap.StopType.FIGHT, "row 0 stays all Fight stops")
		if is_failing():
			return


func test_the_guard_row_keeps_every_road_and_never_moves() -> void:
	for s: int in range(1, SEEDS):
		var with_guards := RunMap.generate(CombatRng.new(s), _tuning, 3, true, true, true, true)
		var without := RunMap.generate(CombatRng.new(s), _tuning, 3, true, true, true, false)
		assert_eq(with_guards.stops.size(), without.stops.size(), "seed %d: the same stops" % s)
		for i: int in with_guards.stops.size():
			assert_eq(with_guards.stops[i].next, without.stops[i].next, "seed %d: the same roads" % s)
		assert_eq(without.count_type(RunMap.StopType.GUARD), 0, "map rules 2 have no guards")
		if is_failing():
			return


func test_a_guard_row_too_close_to_the_boss_is_left_out() -> void:
	_tuning.run_guard_row = _tuning.run_map_rows - 1
	var map := RunMap.generate(CombatRng.new(3), _tuning, 3, true, true, true, true)
	assert_eq(map.count_type(RunMap.StopType.GUARD), 0, "never the campfire row before the boss")
	_tuning.run_guard_row = -1
	assert_eq(RunMap.generate(CombatRng.new(3), _tuning, 3, true, true, true, true).count_type(RunMap.StopType.GUARD),
			0, "-1: none")


## Row 0 stays all Fight stops: a guard row of 0 means none, so the act never opens on a guard.
func test_a_guard_row_of_0_is_none() -> void:
	_tuning.run_guard_row = 0
	for s: int in range(1, SEEDS):
		var map := RunMap.generate(CombatRng.new(s), _tuning, 3, true, true, true, true)
		assert_eq(map.count_type(RunMap.StopType.GUARD), 0, "seed %d: no guards" % s)
		for id: int in map.rows[0]:
			assert_eq(int(map.stop(id).type), RunMap.StopType.FIGHT, "seed %d: row 0 stays all Fight stops" % s)
		assert_gt(map.count_type(RunMap.StopType.TREASURE), 0, "seed %d: the treasure row is kept" % s)
		if is_failing():
			return


## A guard row on the treasure row keeps both: the guards hold the row and the chests stand on the
## row before it (after it when that is row 0), then move as treasure rows do. Every guard row the
## map can have, with and without the moving rows (map rules 1).
func test_a_guard_row_on_the_treasure_row_keeps_the_treasure() -> void:
	var last_guard := _tuning.run_map_rows - 2
	for guard_row: int in range(1, last_guard + 1):
		_tuning.run_guard_row = guard_row
		_tuning.run_treasure_row = guard_row
		var home := guard_row - 1 if guard_row > 1 else guard_row + 1
		for s: int in range(1, SEEDS):
			for moving: bool in [true, false]:
				var map := RunMap.generate(CombatRng.new(s), _tuning, 3, true, true, moving, true)
				var what := "guard row %d seed %d%s" % [guard_row, s, "" if moving else " (rules 1)"]
				assert_eq(map.count_type(RunMap.StopType.GUARD), map.rows[guard_row].size(), what + ": the row is all guards")
				var treasure_rows: Array[int] = []
				for r: int in map.row_count():
					var all_treasure := true
					for id: int in map.rows[r]:
						all_treasure = all_treasure and int(map.stop(id).type) == RunMap.StopType.TREASURE
					if all_treasure:
						treasure_rows.append(r)
				assert_eq(treasure_rows.size(), 1, what + ": one treasure row")
				assert_eq(map.count_type(RunMap.StopType.TREASURE),
						map.rows[treasure_rows[0]].size() if treasure_rows.size() == 1 else -1, what + ": chests only there")
				if treasure_rows.size() == 1:
					assert_ne(treasure_rows[0], guard_row, what)
					assert_gte(treasure_rows[0], 1, what + ": never row 0")
					if moving:
						assert_lte(absi(treasure_rows[0] - home), _tuning.run_treasure_row_spread, what)
					else:
						assert_eq(treasure_rows[0], home, what + ": the row before the guards")
				for id: int in map.rows[0]:
					assert_eq(int(map.stop(id).type), RunMap.StopType.FIGHT, what + ": row 0 stays all Fight stops")
				if is_failing():
					return


func test_runs_made_by_older_rules_keep_their_maps() -> void:
	var run := _run(9)
	var act := run.act_data()
	for rules: int in [1, 2, 3]:
		var old := run.to_dict()
		old["map_rules"] = rules
		var copy := RunState.from_dict(_data, _tuning, old)
		assert_not_null(copy, "rules %d still read" % rules)
		if copy == null:
			continue
		assert_eq(copy.map_rules, rules)
		var plain := RunMap.generate(CombatRng.new(9), _tuning, act.zones.size(), not act.elites.is_empty(),
				not act.events.is_empty(), rules >= 2, rules == 3)
		assert_eq(copy.map.stops, plain.stops, "rules %d: the map it was made with" % rules)
		assert_eq(copy.map.count_type(RunMap.StopType.GUARD), copy.map.rows[_tuning.run_guard_row].size() if rules == 3 else 0,
				"rules %d: a guard row only in rules 3" % rules)
		for stop: Dictionary in copy.map.stops:
			assert_false(copy.elite_holds_guard(int(stop.id)), "rules %d: an Elite stop holds a group, as it did" % rules)
	for rules: int in [0, RunState.MAP_RULES + 1]:
		var bad := run.to_dict()
		bad["map_rules"] = rules
		assert_null(RunState.from_dict(_data, _tuning, bad), "map rules %d are refused" % rules)


# --- Fight stops -------------------------------------------------------------------------------------

func test_a_fight_stop_fights_one_of_its_places_monsters_the_same_on_every_machine() -> void:
	var picked := {}
	for s: int in range(1, SEEDS):
		var run := _run(s)
		var copy := RunState.from_dict(_data, _tuning, run.to_dict())
		for stop: Dictionary in run.map.stops:
			var fight := run.fight_of(int(stop.id))
			if int(stop.type) != RunMap.StopType.FIGHT:
				assert_null(fight, "only Fight stops have one")
				continue
			assert_not_null(fight)
			if fight == null:
				continue
			var base := fight
			for e: EncounterData in run.zone_of(stop).roamer_pool:
				if e != null and e.deep == fight:
					base = e
			assert_has(run.zone_of(stop).roamer_pool, base, "seed %d: from its place's monsters" % s)
			assert_false(fight.boss or fight.mini_boss or fight.elite, "a plain fight")
			assert_eq(copy.fight_of(int(stop.id)), fight, "the same pick from the same state")
			picked[fight.id] = true
		if is_failing():
			return
	assert_gt(picked.size(), 5, "the picks vary")


func test_a_fight_stop_never_repeats_the_last_fight_stops_fight() -> void:
	var guarded := 0
	for s: int in range(1, SEEDS):
		var run := _run(s)
		var a := int(run.map.rows[0][0])
		var b := int(run.map.rows[2][0])
		# The stop between is no Fight stop (a shop), so `a` is the last Fight stop on the road to `b`.
		run.map.stops[int(run.map.rows[1][0])].type = RunMap.StopType.SHOP
		run.map.stops[b].type = RunMap.StopType.FIGHT
		run.map.stops[b].zone = run.map.stops[a].zone
		var unseen := run.fight_of(b)
		run.path.assign([a, int(run.map.rows[1][0])])
		var first := run.fight_of(a)
		var then := run.fight_of(b)
		assert_ne(then.id, first.id, "seed %d: never the same fight twice in a row" % s)
		if unseen.id == first.id:
			guarded += 1
		if is_failing():
			return
	assert_gt(guarded, 0, "the rule changed a pick that would have repeated")


func test_the_shipped_run_is_deep_only_in_its_deep_act() -> void:
	# The balance pass (#321, DESIGN.md 8.23): no row of an act is deep enough for the variants, so
	# only the deep act (the third) brings them; the rule itself is tested below at the old row 4.
	assert_gte(_tuning.run_deep_row, _tuning.run_map_rows, "no deep rows before the boss")
	for s: int in range(1, 20):
		var run := _run(s)
		for act: int in [0, 1]:
			run.act = act
			run.map = run._make_map(act)
			for stop: Dictionary in run.map.stops:
				if int(stop.type) == RunMap.StopType.FINAL:
					continue
				run.at = int(stop.id)
				assert_false(run.is_deep(), "seed %d act %d row %d" % [s, act + 1, int(stop.row)])


func test_deep_rows_and_acts_bring_deep_versions() -> void:
	# The deep-row rule at the row it had before #321 (the shipped run has none before act 3).
	_tuning.run_deep_row = 4
	var run := _run(5)
	var deep_row := -1
	for stop: Dictionary in run.map.stops:
		if int(stop.row) >= _tuning.run_deep_row and int(stop.row) < run.map.row_count() - 2:
			deep_row = int(stop.id)
			break
	assert_gt(deep_row, -1)
	run.map.stops[deep_row].type = RunMap.StopType.FIGHT
	run.map.stops[deep_row].zone = 0
	var base := run._fight_base(deep_row)
	var has_deep := base.deep != null and not base.deep.enemies.is_empty()
	assert_eq(run.fight_of(deep_row), base.deep if has_deep else base, "a deep row fights the deep version")
	var shallow := int(run.map.rows[0][0])
	assert_eq(run.fight_of(shallow), run._fight_base(shallow), "row 0 fights the plain one")
	# Three acts since card #323: the second (the Drowned Mire) keeps its guard plain before the deep
	# rows, the third (the Ashen Deep) always brings the deep one. Every Elite stop the rules allow
	# holds the guard here (100%).
	_tuning.run_elite_guard_percent = 100
	var places := {1: "sunken_bog", 2: "ashen_ruins"}
	var seen := {}
	for s: int in range(1, SEEDS):
		var each := _run(s)
		for act: int in [1, 2]:
			each.act = act
			each.map = each._make_map(act)
			for stop: Dictionary in each.map.stops:
				if not each.elite_holds_guard(int(stop.id)):
					continue
				var place := each.zone_of(stop)
				assert_eq(place.id, String(places[act]), "act %d's place" % (act + 1))
				var deep := act == 2 or int(stop.row) >= _tuning.run_deep_row
				assert_eq(each.guard_of(int(stop.id)), place.guard.deep if deep else place.guard,
						"act %d row %d" % [act + 1, int(stop.row)])
				seen["%d %s" % [act, deep]] = true
	assert_true(seen.has("1 false"), "the second act's guard is plain in its early rows")
	assert_true(seen.has("1 true"), "and deep in its deep rows")
	assert_true(seen.has("2 true"), "the third act's guards are deep")
	assert_false(seen.has("2 false"))


func test_a_fight_stop_rolls_a_drop_and_other_stops_none() -> void:
	var drops := 0
	for s: int in range(1, SEEDS):
		var run := _run(s)
		run.go(run.choices()[0])
		assert_eq(int(run.current().type), RunMap.StopType.FIGHT)
		assert_eq(run.fight_drop(), run.drop_for(run.at), "the stop's own drop roll")
		drops += 1 if run.fight_drop() != null else 0
		for stop: Dictionary in run.map.stops:
			if int(stop.type) == RunMap.StopType.ELITE:
				run.at = int(stop.id)
				assert_null(run.fight_drop(), "an Elite stop (a group or the guard) pays spoils, no drop")
	assert_gt(drops, 0, "some fights drop something")
	assert_lt(drops, SEEDS - 1, "not every fight does")


# --- weather, look and air -------------------------------------------------------------------------

func test_every_run_fight_but_the_boss_rolls_a_seeded_weather() -> void:
	var seen := {}
	for s: int in range(1, SEEDS):
		var run := _run(s)
		var copy := RunState.from_dict(_data, _tuning, run.to_dict())
		for stop: Dictionary in run.map.stops:
			run.at = int(stop.id)
			copy.at = int(stop.id)
			var type := int(stop.type)
			var weather := run.weather_now()
			assert_eq(copy.weather_now(), weather, "the same weather from the same state")
			if type == RunMap.StopType.FINAL:
				assert_null(weather, "the boss's lair has no weather")
				assert_eq(run.look_now(), run.final_look())
				assert_true(run.air_now().is_empty())
				continue
			var place := run.zone_now()
			if type == RunMap.StopType.FIGHT or type == RunMap.StopType.GUARD or type == RunMap.StopType.ELITE:
				assert_eq(place, run.zone_of(stop), "fought in the stop's place")
				assert_eq(run.look_now(), place.look)
				assert_eq(run.air_now().size(), place.ambient.size())
				if weather != null:
					assert_has(place.weathers, weather, "one of its place's weathers")
				seen[weather.id if weather != null else "clear"] = true
			else:
				assert_null(place, "no fight here")
				assert_null(weather)
		if is_failing():
			return
	assert_gt(seen.size(), 2, "the weather varies: %s" % str(seen.keys()))
	assert_true(seen.has("clear"), "clear weather happens too")


func test_an_ambush_is_fought_in_a_place_under_a_weather() -> void:
	var run := _run(11)
	run.at = _first(run, RunMap.StopType.EVENT)
	run._set_ambush(run.act_data().ambushes[0], false)
	assert_eq(run.encounter_now(), run.ambush_encounter())
	assert_not_null(run.zone_now(), "one of the act's places")
	assert_eq(run.look_now(), run.ambush_look())
	assert_eq(run.zone_now().ambient.size(), run.air_now().size(), "and its air")
	var weather := run.weather_now()
	if weather != null:
		assert_has(run.zone_now().weathers, weather)
	assert_null(run.fight_drop(), "an ambush rolls no drop")


func test_the_fight_weather_stream_is_its_own() -> void:
	var consts: Dictionary = (load("res://scripts/run/run_state.gd") as Script).get_script_constant_map()
	var salts: Array[int] = []
	for key: String in consts:
		if key.ends_with("_SALT"):
			salts.append(int(consts[key]))
	for salt: int in [RunState.FIGHT_SALT, RunState.FIGHT_WEATHER_SALT, RunState.ELITE_GUARD_SALT]:
		assert_eq(salts.count(salt), 1, "%d is used once" % salt)


# --- Guard stops (map rules 3) -----------------------------------------------------------------------

## A rules 3 run (one that loaded) still fights its Guard stops' guards and pays as before.
func test_a_rules_3_guard_stop_fights_its_places_guard_and_pays_like_a_guard() -> void:
	var run := _rules_3_run(7)
	assert_not_null(run)
	if run == null:
		return
	assert_true(_walk_to(run, RunMap.StopType.GUARD), "a road reaches the guard row")
	var place := run.zone_of(run.current())
	var guard := run.encounter_now()
	assert_eq(guard, place.guard, "its place's guard, plain in the first act")
	assert_true(guard.mini_boss and not guard.can_run, "no running from a guard")
	var plain_count := run.loot_choice_count()
	run.finish_fight(RunState.VICTORY, run.hp.duplicate(), guard, {"hits_taken": 0})
	assert_true(run.relics.is_empty(), "no Relic drops by itself (DESIGN.md 8.24): the spoils give one")
	assert_true(run.flawless, "no hit taken: flawless")
	assert_eq(run.loot_choice_count(), plain_count + 1, "one more spoils choice")
	assert_eq(run.loot_choices(run.at).size(), run.loot_choice_count())
	var copy := RunState.from_dict(_data, _tuning, run.to_dict())
	assert_eq(copy.map_rules, 3, "kept and sent online")


func test_every_place_has_its_guard() -> void:
	var guards := {"rotten_hollow": "guard_gorged_one", "sunken_bog": "guard_mire_mother",
			"ashen_ruins": "guard_ash_warden"}
	for zone: ZoneData in _data.zones:
		assert_not_null(zone.guard, "%s has a guard" % zone.id)
		if zone.guard != null:
			assert_eq(zone.guard.id, String(guards.get(zone.id, "")), "%s: its own guard" % zone.id)
			assert_eq(zone.guard.deep.id, "deep_" + zone.guard.id, "with its deep version")


func test_every_place_still_names_its_song_and_loop() -> void:
	# Unplayed since the zones went (DESIGN.md 8.22 G6, G7), but kept so the talk can bring them back.
	var songs := {"rotten_hollow": "hollow", "sunken_bog": "bog", "ashen_ruins": "ruins"}
	for zone: ZoneData in _data.zones:
		var short := String(songs.get(zone.id, "?"))
		assert_eq(zone.music_path, "res://assets/audio/music/zone_%s.ogg" % short, "%s: its song" % zone.id)
		assert_eq(zone.ambience_path, "res://assets/audio/ambience/ambience_%s.ogg" % short, "%s: its loop" % zone.id)
		assert_true(ResourceLoader.exists(zone.music_path), "%s: the song is still in assets/" % zone.id)
		assert_true(ResourceLoader.exists(zone.ambience_path), "%s: the loop is still in assets/" % zone.id)


# --- saves and online --------------------------------------------------------------------------------

func test_a_save_from_before_is_kept_but_not_offered() -> void:
	assert_eq(RunSave.FORMAT_VERSION, 6)
	_save_path = OS.get_temp_dir().path_join("rotsworn_test_run_fights_%d.json" % Time.get_ticks_usec())
	# Format 1: saved inside a zone. Format 2: the first phase 26 builds, whose Hanging Cage still
	# gave a Key. The Key's file is gone (card #319), so such a pack no longer loads: the main menu
	# would delete the run as broken (it never checks the fingerprint, card #208) if the format let it in.
	# Format 3: two acts; its act 2 (the Ashen Deep) is act 3 now (card #323), so it would carry on
	# in the wrong place. Format 4: a row of Guard stops (map rules 3), from before the guards joined
	# the Elite stops (DESIGN.md 8.22). Format 5: Relic slots, levels and Echoes (DESIGN.md 8.24).
	var run := _run()
	run.add_item(run.items_by_id()["salve"] as ItemData)
	var with_key := run.to_dict()
	assert_not_null(RunState.from_dict(_data, _tuning, with_key), "the same pack with a Salve fits")
	var rows: Array = (with_key.backpack as Array)[3]
	(rows[0] as Array)[1] = "key"
	assert_null(RunState.from_dict(_data, _tuning, with_key), "a pack holding a Key no longer fits")
	for format: int in [1, 2, 3, 4, 5]:
		var old := {"format": format, "fingerprint": "x", "in_stop": false, "players": 1, "run": with_key}
		var file := FileAccess.open(_save_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(old))
		file.close()
		var loaded := RunSave.load_save("", _save_path)
		assert_eq(loaded.status, RunSave.REJECTED, "a format %d run is not offered" % format)
		assert_true(bool(loaded.keep), "but stays on disk (format %d)" % format)
		assert_true(RunSave.exists(_save_path))
	assert_true(RunSave.save(_run().to_dict(), "x", true, 1, _save_path))
	assert_eq(RunSave.load_save("", _save_path).status, RunSave.LOADED, "a new save reads")


func test_a_friend_builds_the_hosts_fight_stop_from_the_state_alone() -> void:
	assert_eq(NetSession.PROTOCOL, 8, "the messages without a mode (card #331)")
	assert_has(_main.get_script_constant_map().get("NET_FIGHT_SCREENS") as Array, "stop_fight")
	for s: int in [3, 7, 21]:
		var host := _run(s)
		for type: int in [RunMap.StopType.FIGHT]:
			assert_true(_walk_to(host, type))
			var messages: Array[Dictionary] = _main.call("_catch_up_messages", host, _online_two(), true,
					{"name": "map"}, {"name": "stop_fight", "seed": 321}, true)
			assert_eq(messages.size(), 3)
			var fight := messages[2].payload as Dictionary
			assert_eq(String(fight.name), "stop_fight")
			assert_true(bool(fight.rejoin), "a friend who gets in mid-fight gets it as it stands")
			var friend := _friend_after(messages)
			assert_not_null(friend)
			if friend == null:
				return
			assert_eq(friend.encounter_now(), host.encounter_now(), "seed %d: the same fight" % s)
			assert_eq(friend.weather_now(), host.weather_now(), "the same weather")
			assert_eq(friend.fight_drop(), host.fight_drop(), "the same drop")
			assert_eq(friend.zone_now(), host.zone_now(), "the same place")
			assert_eq(friend.look_now(), host.look_now())


## An Elite stop's fight (the host's "final_fight" message): the friend builds the same pick, guard
## or group, the same fight and weather from the run state alone. The Elite stops changed no message
## or field (Net.PROTOCOL 6 was taking turns', card #314; 7 the Relics without slots, DESIGN.md 8.24;
## 8 the messages without a mode, card #331).
func test_a_friend_builds_the_hosts_elite_stop_from_the_state_alone() -> void:
	assert_eq(NetSession.PROTOCOL, 8)
	for guard: bool in [true, false]:
		var found := _elite_stop_holding(guard)
		assert_gt(found[0], 0)
		if found[0] < 0:
			continue
		var host := _run(found[0])
		assert_true(_walk_to_stop(host, found[1]))
		var messages: Array[Dictionary] = _main.call("_catch_up_messages", host, _online_two(), true,
				{"name": "map"}, {"name": "final_fight", "seed": 321}, true)
		var friend := _friend_after(messages)
		assert_not_null(friend)
		if friend == null:
			return
		assert_eq(friend.at, host.at)
		assert_eq(friend.elite_holds_guard(friend.at), guard, "the same pick")
		assert_eq(friend.encounter_now(), host.encounter_now(), "the same fight")
		assert_eq(friend.encounter_now().mini_boss, guard)
		assert_eq(friend.weather_now(), host.weather_now(), "the same weather")
		assert_eq(friend.zone_now(), host.zone_now(), "the same place")
	var final := _body("func _start_final_fight(")
	assert_string_contains(final, "_encounter = _run.encounter_now()", "an Elite stop's fight is the run state's")
	assert_string_contains(final, "AUTOPLAY_ELITE stop=%d kind=%s enc=%s")


func test_main_builds_stop_fights_from_the_run_state() -> void:
	var enter := _body("func _enter_stop(")
	assert_string_contains(enter, "RunMap.StopType.FIGHT, RunMap.StopType.GUARD:")
	assert_string_contains(enter, "_fade_to(_start_stop_fight, ")
	var start := _body("func _start_stop_fight(")
	assert_string_contains(start, "_run.encounter_now()")
	assert_string_contains(start, "_run.fight_drop()")
	# The host's fight seed and its message (card #320: a Fight stop's at its swirl, a Guard stop's here).
	var announce := _body("func _announce_stop_fight(")
	assert_string_contains(announce, "\"stop_fight\"")
	assert_string_contains(start, "_announce_stop_fight(false)")
	assert_string_contains(enter, "_announce_stop_fight(true)")
	var place := _body("func _set_run_fight_place(")
	assert_string_contains(place, "_run.weather_now()")
	assert_string_contains(place, "_weather_or_forced(")
	for body: String in [start, place, announce]:
		assert_false(body.contains("randi()") or body.contains("randf"), "nothing rolled outside the run state")
	assert_eq(start.count("randi_range"), 0, "the seed is the announcement's")
	assert_eq(announce.count("randi_range"), 1, "only the host's fight seed")
	var client := _body("func _client_screen(")
	assert_string_contains(client, "\"stop_fight\":")
	assert_string_contains(client, "_fade_to(_start_stop_fight, ")
	var over := _body("func _on_run_fight_over(")
	assert_string_contains(over, "_takes_fight_drop(result, type, ambushed, _drop != null)")
	assert_string_contains(over, "_after_run_fight(result, type, ambushed, ambush_spoils, _run.is_over(), found != null)")
	# The map bot takes Elite stops by its fitness check alone; there are no Guard stops to weigh.
	var bot := _body("func _autoplay_map(")
	assert_string_contains(bot, "RunMap.StopType.ELITE if _autoplay_elite_ready() else -1")
	assert_string_contains(bot, "RunMap.StopType.EVENT, RunMap.StopType.FIGHT]")
	assert_false(bot.contains("StopType.GUARD"), "no Guard stops in the bot's choices")


# --- what follows a run fight (Main's pure rules) ------------------------------------------------------

## A run fight's end screen leads on by its result, its stop and whether it was an ambush: a Fight
## stop's drop goes in the pack only after its win (the party screen holds one that did not fit); a
## guard, an elite or a boss gives spoils; an ambush only with its event's spoils; an escape or a loss
## that leaves the run going goes to the map; the run's end whenever it is over (DESIGN.md 2.13, 8.22).
func test_what_follows_a_run_fight() -> void:
	var win := RunState.VICTORY
	var ran := RunState.ESCAPED
	var lost := RunState.DEFEAT
	var fight := RunMap.StopType.FIGHT
	var guard := RunMap.StopType.GUARD
	var elite := RunMap.StopType.ELITE
	var boss := RunMap.StopType.FINAL
	var event := RunMap.StopType.EVENT
	var end := _after_fight("END")
	var map := _after_fight("MAP")
	var party := _after_fight("PARTY")
	var spoils := _after_fight("SPOILS")
	var cases := [
		# [result, stop, ambushed, ambush spoils, over, drop left, takes the drop (with one), next, what]
		[win, fight, false, false, false, false, true, map, "a Fight stop's win: the drop fits, the map"],
		[win, fight, false, false, false, true, true, party, "a Fight stop's win: the pack is full"],
		[ran, fight, false, false, false, false, false, map, "running from a Fight stop passes it"],
		[lost, fight, false, false, true, false, false, end, "a lost Fight stop ends the run"],
		[win, guard, false, false, false, false, false, spoils, "a guard gives spoils, no drop"],
		[ran, guard, false, false, false, false, false, map, "no running from a guard, but never spoils"],
		[lost, guard, false, false, true, false, false, end, "a lost guard ends the run"],
		[win, elite, false, false, false, false, false, spoils, "an elite gives spoils, no drop"],
		[ran, elite, false, false, false, false, false, map, "running from an elite passes it"],
		[lost, elite, false, false, true, false, false, end, "a lost elite ends the run"],
		[win, boss, false, false, false, false, false, spoils, "an act's boss gives spoils"],
		[win, boss, false, false, true, false, false, end, "the last boss ends the run"],
		[win, event, true, false, false, false, false, map, "an ambush without spoils: the map"],
		[win, event, true, true, false, false, false, spoils, "an ambush with spoils"],
		[win, fight, true, false, false, false, false, map, "an ambush never drops, even at a Fight stop"],
		[ran, event, true, true, false, false, false, map, "running from an ambush: the map"],
		[lost, event, true, false, true, false, false, end, "a lost ambush ends the run"],
	]
	for c: Array in cases:
		var what := String(c[8])
		assert_eq(_main.call("_takes_fight_drop", c[0], c[1], c[2], true), c[6], what + ": the drop")
		assert_false(_main.call("_takes_fight_drop", c[0], c[1], c[2], false), what + ": no drop rolled")
		assert_eq(_main.call("_after_run_fight", c[0], c[1], c[2], c[3], c[4], c[5]), c[7], what)
	assert_eq(_main.call("_spoils_line", guard, false), "The guard fell. Take one.")
	assert_eq(_main.call("_spoils_line", elite, false, true), "The guard fell. Take one.", "a guard at an Elite stop")
	assert_eq(_main.call("_spoils_line", event, true, true), "The elite fell. Take one.", "an ambush reads as an elite's")
	assert_eq(_main.call("_spoils_line", boss, false), "The boss fell. Take one.")
	assert_eq(_main.call("_spoils_line", elite, false), "The elite fell. Take one.")
	assert_eq(_main.call("_spoils_line", event, true), "The elite fell. Take one.", "an ambush's spoils read as an elite's")
	var item := ItemData.new()
	item.display_name = "Tonic"
	assert_eq(_main.call("_pack_full_note", item), "The enemy dropped a Tonic, but the pack is full.")


## The Journal says where a fight was met: a run fight's place, else its own name.
func test_the_journal_names_a_run_fights_place() -> void:
	assert_eq(_main.call("_journal_place", "Rot Rats", "Sunken Bog"), "Sunken Bog", "a run's Fight, Guard, elite or ambush")
	assert_eq(_main.call("_journal_place", "Rot Rats", ""), "Rot Rats", "a boss or a practice fight")
	var record := _body("func _record_journal(")
	assert_string_contains(record, "_fight_place if _run != null else \"\"", "a practice fight never names a run place")


## --weather=ID forces every run fight's weather (dev tool, DESIGN.md 8.22): none given keeps the
## rolled one, "clear" clears it, a known id gives that weather, and a typo is an error (clear).
func test_weather_forces_run_fights() -> void:
	var main: Node = _main.new()
	autofree(main)
	var options := CombatOptions.new()
	main.set("_options", options)
	var rolled := load("res://data/weather/fog.tres") as WeatherData
	var rain := load("res://data/weather/rain.tres") as WeatherData
	assert_not_null(rolled)
	assert_not_null(rain)
	options.weather_id = ""
	assert_eq(main.call("_weather_or_forced", rolled), rolled, "no --weather: the rolled weather")
	assert_null(main.call("_weather_or_forced", null), "no --weather: a clear roll stays clear")
	options.weather_id = "clear"
	assert_null(main.call("_weather_or_forced", rolled), "clear: no weather")
	options.weather_id = "rain"
	assert_eq(main.call("_weather_or_forced", rolled), rain, "rain over the rolled fog")
	assert_eq(main.call("_weather_or_forced", null), rain, "rain over a clear roll")
	options.weather_id = "rainn"
	assert_null(main.call("_weather_or_forced", rolled), "a typo never keeps the rolled weather")
	assert_push_error("no weather 'rainn'", "a typo is an error, never a quiet test of clear weather")


## A friend's "The host is choosing" line is never left over a fight (it draws above the fight's HUD):
## every fight is built through _start_combat, which hides it. A Fight or Guard stop's fight swirls in
## from the map as every other run fight does (with its sound), then shows the place's name card.
func test_a_fight_hides_the_watch_line_and_stop_fights_swirl_in() -> void:
	assert_string_contains(_body("func _start_combat("), "_watch_layer.visible = false")
	for header: String in ["func _start_stop_fight(", "func _start_final_fight("]:
		assert_string_contains(_body(header), "_start_combat()", header + " builds through _start_combat")
	# Card #320: a Fight stop's card carries its First Strike ring (none on a Guard stop's).
	assert_string_contains(_body("func _enter_stop("),
			"_fade_to(_start_stop_fight, zone.display_name if zone != null else \"\", true, ring)")
	assert_string_contains(_body("func _client_screen("),
			"_fade_to(_start_stop_fight, zone.display_name if zone != null else \"\", true, ring)")
	var fade := _body("func _fade_to(")
	assert_string_contains(fade, "Sfx.play(\"encounter_swirl\")")
	assert_string_contains(fade, "await _transition.swirl_out()")


# --- the bots' habit -----------------------------------------------------------------------------------

func test_the_bots_readiness_habit_lives_in_run_autoplay() -> void:
	var ready := Vector3i(RunAutoplay.READY_MIN_LOWEST_PERCENT, RunAutoplay.READY_MIN_AVERAGE_PERCENT,
			RunAutoplay.READY_MIN_LEVEL)
	assert_true(RunAutoplay.is_ready(ready))
	assert_false(RunAutoplay.is_ready(ready - Vector3i(1, 0, 0)), "the weakest hero too hurt")
	assert_false(RunAutoplay.is_ready(ready - Vector3i(0, 1, 0)), "the party too hurt")
	assert_false(RunAutoplay.is_ready(ready - Vector3i(0, 0, 1)), "too green")
	assert_false(DirAccess.dir_exists_absolute("res://scripts/explore"), "the zone bot went with the zones")
