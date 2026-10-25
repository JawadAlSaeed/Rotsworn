extends GutTest
## Phase 16 run exploits and the last fight (cards #175 to #177): Restock costs more each time,
## a hero drinks only so many Tonics, an attribute reset can never heal, elites cannot be fled,
## HP never stays above max after a backpack change, a map never rolls a
## stop its act has nothing for, a Slowed boss stays slowed in phase two, the Hollow King is the
## hardest fight of the run, and no Elite stop's guard has more HP than its act's boss (#321). Uses
## the shipped run and tuning.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const SEEDS: int = 30

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func _run(seed_value: int = 7) -> RunState:
	return RunState.begin(_data, _tuning.duplicate(true) as Tuning, seed_value)


func _tonic(run: RunState) -> ItemData:
	return run.items_by_id()["tonic"] as ItemData


# --- Restock ----------------------------------------------------------------------------------

func test_each_restock_in_a_visit_costs_more() -> void:
	var run := _run()
	run.gold = 10000
	run.go(run.choices()[0])
	var expected := _tuning.shop_restock_price
	for i: int in 4:
		assert_eq(run.restock_price(), expected, "restock %d" % i)
		var before := run.gold
		assert_true(run.restock())
		assert_eq(before - run.gold, expected)
		expected += _tuning.shop_restock_step
	assert_gt(_tuning.shop_restock_step, 0, "the price really rises")


func test_restock_price_starts_over_at_the_next_stop() -> void:
	var run := _run()
	run.gold = 10000
	run.go(run.choices()[0])
	run.restock()
	run.restock()
	assert_gt(run.restock_price(), _tuning.shop_restock_price)
	run.go(run.choices()[0])
	assert_eq(run.restock_price(), _tuning.shop_restock_price, "a new shop is a new price")


func test_restock_refuses_when_poor() -> void:
	var run := _run()
	run.gold = _tuning.shop_restock_price
	assert_true(run.restock())
	run.gold = _tuning.shop_restock_price
	assert_false(run.restock(), "the second one costs more than that")
	assert_eq(run.gold, _tuning.shop_restock_price, "nothing was taken")


# --- Tonics -----------------------------------------------------------------------------------

func test_a_hero_drinks_only_so_many_tonics() -> void:
	var run := _run()
	var cap := _tuning.tonic_max_per_hero
	assert_gt(cap, 0)
	for i: int in cap:
		assert_true(run.use_item(run.add_item(_tonic(run)), 0), "tonic %d" % i)
	var before_max := run.max_hp(0)
	var uid := run.add_item(_tonic(run))
	assert_false(run.can_use_item(uid, 0), "the hero is full")
	assert_false(run.use_item(uid, 0))
	assert_eq(run.max_hp(0), before_max, "no more max HP")
	assert_ne(run.backpack.entry(uid), {}, "the tonic is not used up")
	assert_ne(run.use_blocked_reason(uid, 0), "", "the screen can say why")
	assert_true(run.can_use_item(uid, 1), "another hero can still drink it")
	assert_eq(run.use_blocked_reason(uid, 1), "")
	assert_true(run.apply_op({"op": "use", "uid": uid, "slot": 1}), "the same through an online op")


func test_the_shop_stops_selling_tonics_nobody_can_drink() -> void:
	var run := _run()
	var tonic := _tonic(run)
	assert_true(run.wants(tonic))
	for slot: int in run.party_size():
		for i: int in _tuning.tonic_max_per_hero:
			assert_true(run.use_item(run.add_item(tonic), slot))
	assert_false(run.wants(tonic), "every hero is full: not worth buying")
	assert_true(run.wants(run.items_by_id()["salve"] as ItemData), "other wares are untouched")


func test_tonics_drunk_are_kept_in_the_run_data() -> void:
	var run := _run()
	run.use_item(run.add_item(_tonic(run)), 2)
	var copy := RunState.from_dict(_data, _tuning, run.to_dict())
	assert_not_null(copy)
	assert_eq(copy.tonics_used, run.tonics_used)
	assert_eq(copy.tonics_left(2), _tuning.tonic_max_per_hero - 1)
	var bad := run.to_dict()
	bad.tonics_used = [0]
	assert_null(RunState.from_dict(_data, _tuning, bad), "a wrong party size is refused")


# --- the attribute reset ----------------------------------------------------------------------

func _levelled() -> RunState:
	var run := _run()
	run.add_xp(0, _tuning.run_xp_first_level * 6)
	return run


func test_a_wounded_hero_cannot_reset_and_respend_for_free_hp() -> void:
	var run := _levelled()
	assert_true(run.set_attributes(0, [run.earned_points(0), 0, 0, 0, 0]), "all into Vitality")
	run.hp[0] = 1
	assert_false(run.set_attributes(0, Attributes.empty()), "too wounded to give the max HP back")
	assert_eq(run.hp[0], 1)
	assert_eq(run.attribute(0, Attributes.Kind.VITALITY), run.earned_points(0), "nothing changed")
	assert_true(run.attributes_wound_blocked(0, Attributes.empty()))


func test_no_sequence_of_attribute_changes_ever_heals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for trial: int in 40:
		var run := _levelled()
		var earned := run.earned_points(0)
		run.set_attributes(0, [rng.randi_range(0, earned), 0, 0, 0, 0])
		run.hp[0] = rng.randi_range(1, run.max_hp(0))
		var start_missing := run.max_hp(0) - run.hp[0]
		for step: int in 12:
			var spend := Attributes.empty()
			var left := earned
			for kind: int in Attributes.COUNT:
				spend[kind] = rng.randi_range(0, left)
				left -= spend[kind]
			run.set_attributes(0, spend)
			assert_lte(run.hp[0], run.max_hp(0))
			assert_gte(run.hp[0], 1)
			assert_eq(run.max_hp(0) - run.hp[0], start_missing, "trial %d step %d: the same HP missing" % [trial, step])


func test_a_healthy_hero_can_still_reset() -> void:
	var run := _levelled()
	run.set_attributes(0, [run.earned_points(0), 0, 0, 0, 0])
	run.hp[0] = run.max_hp(0) - 5
	assert_true(run.set_attributes(0, Attributes.empty()))
	assert_eq(run.max_hp(0) - run.hp[0], 5, "still missing the same HP")


# --- elites cannot be fled --------------------------------------------------------------------

func test_elites_guards_and_bosses_cannot_be_run_from() -> void:
	var seen := 0
	for path: String in DirAccess.get_files_at("res://data/encounters"):
		if not path.ends_with(".tres"):
			continue
		var encounter := load("res://data/encounters/" + path) as EncounterData
		if encounter.elite or encounter.mini_boss or encounter.boss:
			seen += 1
			var setup := CombatSetup.from_encounter(encounter, _tuning, 1)
			assert_false(setup.can_run, "%s shows CAN'T RUN" % encounter.id)
	assert_gte(seen, 12, "the eight elites, the guards and the bosses were checked")
	var plain := load("res://data/encounters/husk_fight.tres") as EncounterData
	assert_true(CombatSetup.from_encounter(plain, _tuning, 1).can_run, "an ordinary fight can still be left")


func test_an_elite_made_in_data_needs_no_can_run_flag() -> void:
	var made := EncounterData.new()
	made.elite = true
	made.can_run = true
	assert_false(CombatSetup.from_encounter(made, _tuning, 1).can_run)


# --- HP above max -----------------------------------------------------------------------------

## Since phase 17 only Relics raise max HP (the backpack's charms are gone, DESIGN.md 8.17). A
## Relic is given for good (8.24): one that raises max HP never heals, and one whose price is max HP
## (the Gravebound Ring) never leaves a hero above max HP.
func test_hp_never_rises_or_stays_above_max_when_a_relic_is_given() -> void:
	var r := _run()
	var charm: GearData = null
	for item: GearData in r.data.gear:
		if item.effect == GearData.Effect.MAX_HP and not item.rot_touched:
			charm = item
	var ring := r.relic_by_id("gravebound_ring")
	assert_not_null(charm)
	assert_not_null(ring)
	for slot: int in r.party_size():
		r.hp[slot] = r.max_hp(slot)
	var full := r.max_hp(0)
	assert_false(r.give_relic(charm, 0).is_empty())
	assert_gt(r.max_hp(0), full, "it is worth max HP")
	assert_eq(r.hp[0], full, "but heals nothing")
	var before := r.max_hp(1)
	assert_false(r.give_relic(ring, 1).is_empty())
	assert_lt(r.max_hp(1), before, "the ring costs max HP")
	for slot: int in r.party_size():
		assert_lte(r.hp[slot], r.max_hp(slot), "hero %d" % slot)


# --- a map for an act without elites or events ------------------------------------------------

func test_a_map_never_rolls_stops_the_act_has_nothing_for() -> void:
	var elites := 0
	var events := 0
	for s: int in range(1, SEEDS):
		var map := RunMap.generate(CombatRng.new(s), _tuning, 3, false, false)
		elites += map.count_type(RunMap.StopType.ELITE)
		events += map.count_type(RunMap.StopType.EVENT)
		assert_eq(map.stop(map.final_id()).type, RunMap.StopType.FINAL)
	assert_eq(elites, 0, "no elite stops")
	assert_eq(events, 0, "no event stops")
	var with_both := 0
	for s: int in range(1, SEEDS):
		var map := RunMap.generate(CombatRng.new(s), _tuning, 3)
		with_both += map.count_type(RunMap.StopType.ELITE) + map.count_type(RunMap.StopType.EVENT)
	assert_gt(with_both, 0, "an act that has them still rolls them")


func test_the_shipped_acts_make_the_same_maps_as_before() -> void:
	var run := _run(3)
	var plain := RunMap.generate(CombatRng.new(3), _tuning, run.act_data(0).zones.size())
	assert_eq(run.map.stops.size(), plain.stops.size())
	for i: int in plain.stops.size():
		assert_eq(int(run.map.stops[i].type), int(plain.stops[i].type), "stop %d" % i)


# --- the last fight ---------------------------------------------------------------------------

func _hp_of(encounter: EncounterData, scale_percent: int) -> int:
	var total := 0
	for enemy: EnemyData in encounter.enemies:
		total += CombatMath.percent(CombatMath.percent(_tuning.base_enemy_hp, enemy.hp_percent), scale_percent)
	return total


func test_the_hollow_king_is_the_hardest_fight_of_the_run() -> void:
	var king_fight := load("res://data/encounters/hollow_king.tres") as EncounterData
	var king := king_fight.enemies[0]
	var lord_fight := load("res://data/encounters/husk_lord_fight.tres") as EncounterData
	# A guard as deep as the second act's last row (the worst case): one whole act behind it plus the row.
	var depth_hp := 100 + (_tuning.run_map_rows + 1 + _tuning.run_map_rows - 1) * _tuning.run_enemy_hp_row_percent
	if _tuning.run_enemy_scale_bosses:
		depth_hp = 100
	assert_gte(king_fight.enemies.size(), 2, "the King brings a court")
	assert_gt(_hp_of(king_fight, 100), _hp_of(lord_fight, 100), "more HP than the act 1 boss fight")
	for file: String in ["guard_ash_warden", "guard_gorged_one", "guard_mire_mother", "deep_guard_ash_warden",
			"deep_guard_gorged_one", "deep_guard_mire_mother"]:
		var guard := load("res://data/encounters/%s.tres" % file) as EncounterData
		assert_gt(_hp_of(king_fight, 100), _hp_of(guard, depth_hp), "more HP than %s at the deepest row" % file)
		for enemy: EnemyData in guard.enemies:
			if not enemy.phase_two_attacks.is_empty():
				assert_gte(king.power_percent, enemy.power_percent, "as strong as %s" % enemy.id)
				assert_gt(king.speed, enemy.speed, "faster than %s" % enemy.id)
				assert_gt(king.phase_two_speed, enemy.phase_two_speed, "enrages faster than %s" % enemy.id)
	var lord := lord_fight.enemies[0]
	assert_gt(king.power_percent, lord.power_percent)
	assert_gt(king.phase_two_speed, lord.phase_two_speed)
	# The third act's guard at its Elite stops (the deep Ash Warden, DESIGN.md 8.22, 8.23) is checked
	# against the King with the run's own fight numbers in the test below (#321).


## The HP in all `encounter`'s enemies start a fight with under `setup`, as the engine builds them
## (the encounter's own HP share and the depth are in setup.enemy_hp_percent).
func _fight_hp(encounter: EncounterData, setup: CombatSetup) -> int:
	var total := 0
	for enemy: EnemyData in encounter.enemies:
		total += CombatMath.percent_min1(CombatMath.percent_min1(_tuning.base_enemy_hp, enemy.hp_percent),
				setup.enemy_hp_percent)
	return total


## A run at oath `oath` in act `act` (0-based) standing on the first stop of row `row` of that act's map.
func _run_at(act: int, row: int, seed_value: int = 7, oath: int = 0) -> RunState:
	var run := RunState.begin(_data, _tuning.duplicate(true) as Tuning, seed_value, oath)
	assert_eq(run.oath, oath)
	run.act = act
	run.map = run._make_map(act)
	run.at = int(run.map.rows[row][0])
	return run


func test_no_elite_stop_guard_is_bigger_than_its_act_boss() -> void:
	# The balance pass for the three-act run (#321, DESIGN.md 8.23, T5): on every row an Elite stop
	# can stand on (from run_elite_min_row to the row before the boss, where a moved campfire row
	# leaves middle stops), the guard it may hold (its deep version in a deep act or row) starts its
	# fight with less HP in all than its act's boss fight, both built by the run's fight_setup at the
	# same oath. Every oath of the ladder: the Deep's growth per row reaches the guards and not the
	# bosses (run_enemy_scale_bosses is off), and the Crowns raise both, so the high oaths are the
	# tightest (act 2's Mire Mother on row 5 from Oath 4, the Deep, on had 177 to 188 HP to spare).
	var checked := 0
	var tightest := 1 << 30
	var where := ""
	for oath: int in range(0, _data.oaths.size() + 1):
		for act: int in _data.acts.size():
			var info := _data.acts[act]
			var boss := info.final_encounter
			var boss_run := _run_at(act, _tuning.run_map_rows, 7, oath)
			var boss_hp := _fight_hp(boss, boss_run.fight_setup(boss, 1, CombatSetup.Opening.NORMAL))
			for zone: ZoneData in info.zones:
				if zone.guard == null:
					continue
				for row: int in range(_tuning.run_elite_min_row, _tuning.run_map_rows):
					var run := _run_at(act, row, 7, oath)
					var guard := run._deep_version(zone.guard, run.at)
					var guard_hp := _fight_hp(guard, run.fight_setup(guard, 1, CombatSetup.Opening.NORMAL))
					assert_lt(guard_hp, boss_hp, "oath %d act %d row %d: %s (%d HP) under %s (%d HP)"
							% [oath, act + 1, row, guard.id, guard_hp, boss.id, boss_hp])
					if boss_hp - guard_hp < tightest:
						tightest = boss_hp - guard_hp
						where = "oath %d act %d row %d %s" % [oath, act + 1, row, guard.id]
					checked += 1
	assert_gte(checked, (_data.oaths.size() + 1) * 3 * (_tuning.run_map_rows - _tuning.run_elite_min_row),
			"every oath, every act's guard on every row")
	gut.p("Tightest guard against its boss: %d HP to spare (%s)" % [tightest, where])


func test_the_boss_test_sees_what_the_engine_builds() -> void:
	# The helper above counts the encounter's own HP share (guards have 90%), which _hp_of does not.
	var guard := load("res://data/encounters/guard_gorged_one.tres") as EncounterData
	var run := _run_at(0, 0)
	var setup := run.fight_setup(guard, 1, CombatSetup.Opening.NORMAL)
	assert_eq(setup.enemy_hp_percent, guard.enemy_hp_percent, "row 0: the encounter's share only")
	var engine := CombatEngine.new(setup)
	engine.start()
	var built := 0
	for c: Combatant in engine.combatants:
		if c.team == Combatant.Team.ENEMY:
			built += c.max_hp
	assert_eq(_fight_hp(guard, setup), built, "the same HP the engine gives its enemies")


func test_the_leech_queen_sits_between_the_husk_lord_and_the_hollow_king() -> void:
	# Act 2's boss (card #323, DESIGN.md 8.23): tougher than act 1's, gentler than the run's end.
	var lord_fight := load("res://data/encounters/husk_lord_fight.tres") as EncounterData
	var queen_fight := load("res://data/encounters/leech_queen_fight.tres") as EncounterData
	var king_fight := load("res://data/encounters/hollow_king.tres") as EncounterData
	assert_gt(_hp_of(queen_fight, 100), _hp_of(lord_fight, 100), "more HP than the Husk Lord's fight")
	assert_lt(_hp_of(queen_fight, 100), _hp_of(king_fight, 100), "less than the Hollow King's")
	var lord := lord_fight.enemies[0]
	var queen := queen_fight.enemies[0]
	var king := king_fight.enemies[0]
	for key: String in ["hp_percent", "power_percent", "speed", "phase_two_speed"]:
		assert_gt(int(queen.get(key)), int(lord.get(key)), "the Queen's %s above the Lord's" % key)
		assert_lt(int(queen.get(key)), int(king.get(key)), "and below the King's")
