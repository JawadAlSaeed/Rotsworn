extends GutTest
## The run (DESIGN 8): the map is well formed for many seeds (rows, stop types, paths that never
## cross, everything reachable, the same seed makes the same map); RunState carries HP and gold
## between fights, gets the downed back up after a victory, ends on a defeat or the final win,
## rests and shops by the rules; fights start with the run's HP and max HP; the shipped run data
## is complete. Uses the shipped run with Tuning.new() for the rules.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const SEEDS: int = 200

var _tuning := Tuning.new()
var _data: RunData


func before_all() -> void:
	_data = load(RUN_PATH) as RunData


func _map(seed_value: int) -> RunMap:
	return RunMap.generate(CombatRng.new(seed_value), _tuning, 3)


func _run(seed_value: int = 1) -> RunState:
	return RunState.begin(_data, _tuning, seed_value)


# --- the map ----------------------------------------------------------------------------------

func test_rows_and_stop_types() -> void:
	for s: int in range(1, SEEDS):
		var map := _map(s)
		assert_eq(map.row_count(), _tuning.run_map_rows + 1, "rows plus the final fight")
		var last := map.row_count() - 1
		assert_eq(map.rows[last].size(), 1, "one final fight")
		assert_eq(int(map.stop(map.final_id()).type), RunMap.StopType.FINAL)
		for r: int in last:
			var width: int = map.rows[r].size()
			assert_between(width, _tuning.run_map_min_width, _tuning.run_map_max_width, "row width")
			for id: int in map.rows[r]:
				var type := int(map.stop(id).type)
				assert_ne(type, RunMap.StopType.FINAL, "only the top is the final fight")
				if r == 0:
					assert_eq(type, RunMap.StopType.ZONE, "the run starts in zones")
				if r == last - 1:
					assert_eq(type, RunMap.StopType.REST, "a rest before the final fight")
		assert_gt(map.count_type(RunMap.StopType.SHOP), 0, "seed %d has a shop" % s)
		if is_failing():
			return


func test_paths_never_cross_and_reach_everything() -> void:
	for s: int in range(1, SEEDS):
		var map := _map(s)
		for st: Dictionary in map.stops:
			var row := int(st.row)
			if row < map.row_count() - 1:
				assert_gt((st.next as Array).size(), 0, "seed %d: stop %d leads on" % [s, st.id])
			if row > 0:
				assert_gt((st.prev as Array).size(), 0, "seed %d: stop %d can be reached" % [s, st.id])
			for n: int in st.next:
				assert_eq(int(map.stop(n).row), row + 1, "paths go one row up")
		for r: int in map.row_count() - 1:
			var pairs: Array[Vector2i] = []
			for id: int in map.rows[r]:
				for n: int in map.stop(id).next:
					pairs.append(Vector2i(int(map.stop(id).col), int(map.stop(n).col)))
			for a: Vector2i in pairs:
				for b: Vector2i in pairs:
					assert_false(RunMap.paths_cross(a.x, a.y, b.x, b.y), "seed %d row %d: paths cross" % [s, r])
		if is_failing():
			return


func test_no_shop_or_rest_twice_in_a_row() -> void:
	for s: int in range(1, SEEDS):
		var map := _map(s)
		for st: Dictionary in map.stops:
			var type := int(st.type)
			if type != RunMap.StopType.SHOP and type != RunMap.StopType.REST:
				continue
			for n: int in st.next:
				assert_ne(int(map.stop(n).type), type, "seed %d: %s twice in a row" % [s, RunMap.TYPE_NAMES[type]])
		if is_failing():
			return


func test_zone_stops_get_a_zone_not_met_last_on_the_way_there() -> void:
	for s: int in range(1, SEEDS):
		var map := _map(s)
		for st: Dictionary in map.stops:
			if int(st.type) != RunMap.StopType.ZONE:
				assert_eq(int(st.zone), -1)
				continue
			assert_between(int(st.zone), 0, 2, "a zone stop has a zone")
			# Only when the paths leading here already met every zone last can one repeat.
			var before := map.last_zones_before(int(st.id))
			if before.size() < 3:
				assert_false(before.has(int(st.zone)), "seed %d: same zone twice in a row" % s)
		if is_failing():
			return


func test_same_seed_same_map() -> void:
	assert_eq(var_to_str(_map(42).stops), var_to_str(_map(42).stops))
	var differs := false
	for s: int in range(2, 12):
		differs = differs or var_to_str(_map(1).stops) != var_to_str(_map(s).stops)
	assert_true(differs, "different seeds make different maps")


# --- the run's rules --------------------------------------------------------------------------

func test_a_run_starts_full_at_the_bottom() -> void:
	var run := _run()
	assert_eq(run.at, -1)
	assert_eq(run.gold, _tuning.run_start_gold)
	for slot: int in run.party_size():
		assert_eq(run.hp[slot], run.max_hp(slot), "full HP")
	assert_eq(run.choices(), run.map.choices(-1))


func test_you_can_only_go_to_a_connected_stop() -> void:
	var run := _run()
	var first := run.choices()[0]
	var far := run.map.final_id()
	assert_false(run.go(far), "cannot jump to the final fight")
	assert_true(run.go(first))
	assert_eq(run.at, first)
	assert_false(run.go(first), "cannot stay")
	assert_true(run.go(run.choices()[0]))
	assert_eq(run.path.size(), 2)


func test_hp_carries_over_and_victory_pays_gold() -> void:
	var run := _run()
	run.go(run.choices()[0])
	var encounter := load("res://data/encounters/husk_fight.tres") as EncounterData
	var after: Array[int] = [40, 0, run.max_hp(2) + 50]
	var won := int(run.finish_fight(RunState.VICTORY, after, encounter).gold)
	assert_eq(won, RunState.encounter_gold(encounter))
	assert_gt(won, 0, "fights pay gold")
	assert_eq(run.gold, _tuning.run_start_gold + won)
	assert_eq(run.hp[0], 40, "HP carries over")
	assert_eq(run.hp[1], _tuning.run_downed_revive_hp, "the downed get back up")
	assert_eq(run.hp[2], run.max_hp(2), "never above max")
	assert_false(run.is_over())
	assert_eq(run.fights_won, 1)


func test_a_defeat_ends_the_run() -> void:
	var run := _run()
	run.go(run.choices()[0])
	var after: Array[int] = [0, 0, 0]
	assert_eq(run.finish_fight(RunState.DEFEAT, after, _data.final_encounter), {"gold": 0, "xp": 0, "levels": 0})
	assert_true(run.is_over())
	assert_eq(run.result, RunState.DEFEAT)
	assert_false(run.go(run.map.stop(run.at).next[0]), "nothing goes on after the end")


func test_winning_the_final_fight_clears_the_run() -> void:
	var run := _run()
	while run.map.stop(run.at).get("type", -1) != RunMap.StopType.FINAL:
		assert_true(run.go(run.choices()[0]))
	var after: Array[int] = [10, 10, 10]
	run.finish_fight(RunState.VICTORY, after, _data.final_encounter)
	assert_eq(run.result, RunState.VICTORY)
	assert_eq(run.path.size(), run.map.row_count(), "one stop per row")


func test_rest_heals_a_share_of_max_hp() -> void:
	var run := _run()
	run.hp[0] = 1
	run.hp[1] = run.max_hp(1) - 3
	var healed := run.rest()
	assert_eq(healed[0], CombatMath.percent(run.max_hp(0), _tuning.run_rest_heal_percent))
	assert_eq(run.hp[0], 1 + healed[0])
	assert_eq(healed[1], 3, "never above max")
	assert_eq(healed[2], 0)


func test_shop_items_cost_gold_and_do_what_they_say() -> void:
	var run := _run()
	var salve := _item(ShopItemData.Effect.HEAL_ONE)
	var feast := _item(ShopItemData.Effect.HEAL_ALL)
	var tonic := _item(ShopItemData.Effect.MAX_HP_ONE)
	run.gold = 0
	run.hp[0] = 1
	assert_false(run.buy(salve, 0), "no gold, no salve")
	assert_eq(run.hp[0], 1)
	run.gold = salve.price + feast.price + tonic.price
	assert_true(run.buy(salve, 0))
	assert_eq(run.hp[0], 1 + CombatMath.percent(run.max_hp(0), salve.amount_percent))
	run.hp[1] = 1
	run.hp[2] = 1
	assert_true(run.buy(feast, -1), "a feast needs nobody picked")
	assert_eq(run.hp[2], 1 + CombatMath.percent(run.max_hp(2), feast.amount_percent))
	var before_max := run.max_hp(1)
	var before_hp := run.hp[1]
	assert_true(run.buy(tonic, 1))
	assert_eq(run.max_hp(1), CombatMath.percent_min1(before_max, 100 + tonic.amount_percent))
	assert_eq(run.hp[1], before_hp + run.max_hp(1) - before_max, "the new HP is filled")
	assert_eq(run.gold, 0)
	assert_false(run.can_buy(salve, 0))


func _item(effect: ShopItemData.Effect) -> ShopItemData:
	for item: ShopItemData in _data.shop_items:
		if item.effect == effect:
			return item
	fail_test("the shipped shop sells effect %d" % effect)
	return ShopItemData.new()


func test_fights_start_with_the_runs_hp_and_max_hp() -> void:
	var run := _run()
	run.max_hp_percent[0] = 130
	run.hp[0] = 7
	run.hp[1] = run.max_hp(1)
	var setup := run.fight_setup(load("res://data/encounters/husk_fight.tres") as EncounterData, 3,
			CombatSetup.Opening.NORMAL)
	assert_eq(setup.party.size(), _data.party.size(), "the run's party fights")
	assert_eq(setup.team_ultimate, _data.team_ultimate)
	var engine := CombatEngine.new(setup)
	var events := engine.start()
	assert_eq(String(events[0].type), "combat_started", "the fight starts")
	var party := engine.combatants.filter(func(c: Combatant) -> bool: return c.is_party())
	assert_eq(party[0].max_hp, run.max_hp(0), "engine and run agree on max HP")
	assert_eq(party[0].hp, 7)
	assert_eq(party[1].hp, run.max_hp(1))


# --- shipped data -----------------------------------------------------------------------------

func test_shipped_run_is_complete() -> void:
	assert_not_null(_data, "the run file loads")
	assert_between(_data.party.size(), 1, 3)
	assert_not_null(_data.team_ultimate)
	assert_not_null(_data.final_encounter)
	assert_not_null(_data.final_look)
	assert_gte(_data.zones.size(), 3, "three zones to pick from")
	assert_gt(_data.shop_items.size(), 0)
	for item: ShopItemData in _data.shop_items:
		assert_gt(item.price, 0, "%s costs something" % item.id)
	for zone: ZoneData in _data.zones:
		var guards := 0
		for e: ZoneEnemyData in zone.enemies:
			if e.guard:
				guards += 1
		assert_eq(guards, 1, "%s has one guard at its exit" % zone.id)
	var setup := _run().fight_setup(_data.final_encounter, 1, CombatSetup.Opening.NORMAL)
	assert_eq(setup.validate(), PackedStringArray(), "the final fight is a valid setup")


func test_every_enemy_pays_gold() -> void:
	for file: String in DirAccess.get_files_at("res://data/enemies"):
		if file.ends_with(".tres"):
			var enemy := load("res://data/enemies".path_join(file)) as EnemyData
			# The boss ends the run: its gold would never be spent.
			if enemy.phase_two_hp_percent == 0:
				assert_gt(enemy.gold, 0, "%s pays gold" % enemy.id)
