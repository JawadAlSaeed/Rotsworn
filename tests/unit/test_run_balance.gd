extends GutTest
## Phase 16 run exploits and the last fight (cards #175 to #177): Restock costs more each time,
## a hero drinks only so many Tonics, an attribute reset can never heal, elites cannot be fled,
## HP never stays above max after a backpack change, a map never rolls a
## stop its act has nothing for, a Slowed boss stays slowed in phase two, and the Hollow King is the
## hardest fight of the run. Uses the shipped run and tuning.

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

## Since phase 17 only Relics and Echoes raise max HP (the backpack's charms are gone, DESIGN.md
## 8.17): taking one off, moving it, or taking an Echo off never leaves a hero above max HP.
func test_hp_never_stays_above_max_after_a_relic_or_echo_comes_off() -> void:
	var charm: GearData = null
	for item: GearData in _run().data.gear:
		if item.effect == GearData.Effect.MAX_HP and not item.rot_touched:
			charm = item
	for how: String in ["take_off", "swap", "echo"]:
		var r := _run()
		r.guards_beaten = 1
		var wearer := 1 if how == "echo" else 0
		r.wear(wearer, 0, charm)
		if how == "echo":
			r.mastery[charm.id] = r.tuning.mastery_needed
			r.add_xp(0, 400)
			assert_true(r.set_echo(0, charm, true))
		for slot: int in r.party_size():
			r.hp[slot] = r.max_hp(slot)
		var with_it := r.max_hp(0)
		match how:
			"take_off":
				r.take_off(0, 0)
			"swap":
				r.swap_gear(0, 0, 2, 1)
			"echo":
				r.set_echo(0, charm, false)
		assert_lt(r.max_hp(0), with_it, "%s: it was worth max HP" % how)
		for slot: int in r.party_size():
			assert_lte(r.hp[slot], r.max_hp(slot), "%s: hero %d" % [how, slot])


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
	# Since card #323 the third act's guard is the deep Ash Warden at its act's Guard row: two whole
	# acts behind it plus the row.
	var third_guard_hp := 100 + (2 * (_tuning.run_map_rows + 1) + _tuning.run_guard_row) * _tuning.run_enemy_hp_row_percent
	if _tuning.run_enemy_scale_bosses:
		third_guard_hp = 100
	var warden := load("res://data/encounters/deep_guard_ash_warden.tres") as EncounterData
	assert_gt(_hp_of(king_fight, 100), _hp_of(warden, third_guard_hp), "more HP than the third act's guard")


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
