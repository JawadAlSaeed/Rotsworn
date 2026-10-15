extends GutTest
## Phase 13 step 1 (DESIGN.md 8.2): a level per hero, attribute points and critical hits.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const RUN_PATH := "res://data/runs/rotten_road.tres"
const SLOW_ENEMY: int = 10
const POWERS: Array[int] = [36, 48, 40]


func _run() -> RunState:
	return RunState.begin(load(RUN_PATH) as RunData, Tuning.new(), 5)


## A run where hero 0 has reached level 3 (two level ups of points).
func _levelled() -> RunState:
	var run := _run()
	var t := run.tuning
	run.add_xp(0, t.run_xp_first_level + t.run_xp_first_level + t.run_xp_level_step)
	return run


# --- attributes -------------------------------------------------------------------------------

func test_points_come_from_levels() -> void:
	var run := _levelled()
	var t := run.tuning
	assert_eq(run.levels[0], 3)
	assert_eq(run.earned_points(0), t.attr_start_points + 2 * t.attr_points_per_level)
	assert_eq(run.free_points(0), run.earned_points(0))
	assert_eq(run.free_points(1), t.attr_start_points, "a hero who did not level has none new")
	assert_true(run.has_free_points())


func test_each_attribute_raises_its_stat() -> void:
	var t := Tuning.new()
	for kind: int in Attributes.COUNT:
		var run := _levelled()
		var before_hp := run.max_hp(0)
		var before_power := run.power(0)
		var before_speed := run.speed(0)
		var values := Attributes.empty()
		values[kind] = 2
		assert_true(run.set_attributes(0, values), Attributes.NAMES[kind])
		match kind:
			Attributes.Kind.VITALITY:
				assert_eq(run.total_max_hp_percent(0), 100 + 2 * t.run_level_hp_percent + 2 * t.attr_vitality_hp_percent)
				assert_gt(run.max_hp(0), before_hp)
			Attributes.Kind.MIGHT:
				assert_eq(run.power_percent(0), 100 + 2 * t.run_level_power_percent + 2 * t.attr_might_power_percent)
				assert_gt(run.power(0), before_power)
			Attributes.Kind.AGILITY:
				assert_eq(run.speed(0), before_speed + 2 * t.attr_agility_speed)
			Attributes.Kind.DEFENSE:
				assert_eq(int(run.passives(0).get(Passive.TOUGH, 0)), 2 * t.attr_defense_percent)
				assert_eq(run.defense_percent(0), 2 * t.attr_defense_percent)
			Attributes.Kind.LUCK:
				assert_eq(int(run.passives(0).get(Passive.CRIT, 0)), 2 * t.attr_luck_crit_percent)
				assert_eq(run.crit_percent(0), t.crit_base_percent + 2 * t.attr_luck_crit_percent)


func test_attributes_reach_the_fight() -> void:
	var run := _levelled()
	run.set_attributes(0, [0, 1, 2, 1, 1])
	var husk := load("res://data/encounters/husk_fight.tres") as EncounterData
	var setup := run.fight_setup(husk, 9, CombatSetup.Opening.NORMAL)
	assert_eq(setup.party_power_percent[0], run.power_percent(0))
	assert_eq(setup.party_speed_bonus[0], run.speed_bonus(0))
	assert_eq(int(setup.party_passives[0].get(Passive.CRIT, 0)), run.tuning.attr_luck_crit_percent)
	assert_eq(int(setup.party_passives[0].get(Passive.TOUGH, 0)), run.tuning.attr_defense_percent)
	assert_eq(setup.validate(), PackedStringArray())


func test_spending_more_than_earned_is_refused() -> void:
	var run := _levelled()
	var too_many := Attributes.empty()
	too_many[0] = run.earned_points(0) + 1
	assert_false(run.set_attributes(0, too_many))
	assert_false(run.set_attributes(0, [1, 1]), "five numbers")
	assert_false(run.set_attributes(0, [-1, 0, 0, 0, 0]), "never below 0")
	assert_false(run.set_attributes(0, ["1", 0, 0, 0, 0]), "whole numbers only")
	assert_false(run.set_attributes(7, Attributes.empty()), "no such hero")
	assert_eq(Attributes.total(run.attributes[0]), 0, "nothing changed")


func test_a_reset_never_heals() -> void:
	var run := _levelled()
	run.set_attributes(0, [run.earned_points(0), 0, 0, 0, 0])
	run.hp[0] = run.max_hp(0) - 30
	assert_true(run.set_attributes(0, Attributes.empty()), "a reset")
	assert_eq(run.max_hp(0) - run.hp[0], 30, "still missing the same HP")
	assert_true(run.set_attributes(0, [run.earned_points(0), 0, 0, 0, 0]))
	assert_eq(run.max_hp(0) - run.hp[0], 30, "spending again does not heal either")
	run.hp[0] = 1
	run.set_attributes(0, Attributes.empty())
	assert_eq(run.hp[0], 1, "never below 1 HP")


func test_the_bot_spends_evenly() -> void:
	var run := _levelled()
	run.auto_spend(0)
	assert_eq(run.free_points(0), 0)
	var values: Array = run.attributes[0]
	assert_true(values.max() - values.min() <= 1, "evenly: %s" % str(values))


func test_attributes_as_an_op() -> void:
	var run := _levelled()
	assert_true(run.apply_op({"op": "attributes", "slot": 0, "values": [1, 1, 0, 0, 0]}))
	assert_eq(run.attribute(0, Attributes.Kind.MIGHT), 1)
	assert_false(run.apply_op({"op": "attributes", "slot": 0, "values": [99, 0, 0, 0, 0]}))
	assert_false(run.apply_op({"op": "attributes", "slot": "0", "values": [0, 0, 0, 0, 0]}))
	assert_false(run.apply_op({"op": "attributes", "slot": 0}))


func test_bad_attributes_in_run_data_are_refused() -> void:
	var run := _levelled()
	var data := run.to_dict()
	data.attributes = [[1, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
	assert_null(RunState.from_dict(run.data, run.tuning, data))
	data = run.to_dict()
	data.levels = [1, 1]
	assert_null(RunState.from_dict(run.data, run.tuning, data), "one level per hero")


# --- critical hits ----------------------------------------------------------------------------

func _crit_tuning(base: int) -> Tuning:
	var t := Tuning.new()
	t.crit_base_percent = base
	return t


func _skill_engine(t: Tuning, passives: Dictionary = {}) -> CombatEngine:
	var cut := Fx.skill("cut", AbilityData.Target.SINGLE_ENEMY, 0, [800], {"damage_percent": 100})
	var setup := Fx.kit_setup([[cut], [cut], [cut]], [Fx.attack("one", [Fx.hit(900)])],
			{"enemy_speed": SLOW_ENEMY, "tuning": t})
	for i: int in 3:
		setup.party_passives.append(passives.duplicate())
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


func test_a_sure_crit_deals_the_crit_damage() -> void:
	var t := _crit_tuning(100)
	var engine := _skill_engine(t)
	var actor := engine.active_actor
	engine.submit(Fx.use(engine, "cut"))
	var prompt: Dictionary = (engine.sequence.prompts as Array)[0]
	assert_true(bool(prompt.crit))
	var normal := CombatMath.percent_min1(POWERS[actor], 100)
	assert_eq(int(prompt.press_damage), CombatMath.percent_min1(normal, t.crit_damage_percent))
	var events := engine.submit(Fx.resolve_now(engine, [[0, Defense.Outcome.PRESS]]))
	var hit := Fx.first_of(events, "damage")
	assert_true(bool(hit.crit), "the damage event says it was a critical hit")
	assert_eq(int(hit.amount), CombatMath.percent_min1(normal, t.crit_damage_percent))


func test_a_missed_press_never_crits() -> void:
	var engine := _skill_engine(_crit_tuning(100))
	engine.submit(Fx.use(engine, "cut"))
	var events := engine.submit(Fx.resolve_now(engine, [[0, Defense.Outcome.NONE]]))
	for e: Dictionary in Fx.of_type(events, "damage"):
		assert_false(bool(e.crit))


func test_no_crits_at_zero_and_luck_adds_chance() -> void:
	var engine := _skill_engine(_crit_tuning(0))
	engine.submit(Fx.use(engine, "cut"))
	assert_false(bool((engine.sequence.prompts as Array)[0].crit))
	var lucky := _skill_engine(_crit_tuning(0), {Passive.CRIT: 100})
	lucky.submit(Fx.use(lucky, "cut"))
	assert_true(bool((lucky.sequence.prompts as Array)[0].crit), "Luck alone can make it sure")


func test_enemies_never_crit() -> void:
	var engine := Fx.started([Fx.attack("one", [Fx.hit(900, Fx.NORMAL, 100)])], {"tuning": _crit_tuning(100)})
	assert_eq(engine.crit_chance(engine.get_combatant(Fx.ENEMY_ID)), 0)
	var events := engine.submit(Fx.resolve_now(engine, [[0, Defense.Outcome.NONE]]))
	for e: Dictionary in Fx.of_type(events, "damage"):
		assert_false(bool(e.crit))


func test_counters_can_crit() -> void:
	var t := _crit_tuning(100)
	var engine := Fx.started([Fx.attack("one", [Fx.hit(900, Fx.NORMAL, 100)])], {"tuning": t})
	var events := engine.submit(Fx.resolve_now(engine, [[0, Defense.Outcome.PARRY]]))
	var counter := {}
	for e: Dictionary in Fx.of_type(events, "damage"):
		if String(e.cause) == "counter":
			counter = e
	assert_false(counter.is_empty(), "a perfect parry counters")
	assert_true(bool(counter.crit))


func test_defense_is_capped() -> void:
	var t := Fx.no_crit_tuning()
	var attack := Fx.attack("one", [Fx.hit(900, Fx.NORMAL, 100)])
	var setup := Fx.setup([attack], {"tuning": t})
	for i: int in 3:
		setup.party_passives.append({Passive.TOUGH: 95})
	var engine := CombatEngine.new(setup)
	engine.start()
	var plain := Fx.started([attack], {"tuning": t})
	var plain_damage := int((plain.sequence.prompts as Array)[0].damage)
	assert_eq(int((engine.sequence.prompts as Array)[0].damage),
			CombatMath.percent_min1(plain_damage, 100 - t.tough_max_percent))


func test_crits_stay_deterministic() -> void:
	var a := _skill_engine(_crit_tuning(50))
	var b := _skill_engine(_crit_tuning(50))
	assert_eq(a.submit(Fx.use(a, "cut")), b.submit(Fx.use(b, "cut")), "same seed, same crits")


# --- enemies grow with depth (card #105, DESIGN.md 8.3) ---------------------------------------

func test_enemies_grow_each_row() -> void:
	var run := _run()
	var t := run.tuning
	var husk := load("res://data/encounters/husk_fight.tres") as EncounterData
	run.go(run.choices()[0])
	assert_eq(run.enemy_hp_percent(), 100, "the first row is as in the data")
	while int(run.current().row) < 3:
		run.go(run.choices()[0])
	assert_eq(run.enemy_hp_percent(), 100 + 3 * t.run_enemy_hp_row_percent)
	assert_eq(run.enemy_power_percent(), 100 + 3 * t.run_enemy_power_row_percent)
	var setup := run.fight_setup(husk, 4, CombatSetup.Opening.NORMAL)
	assert_eq(setup.enemy_hp_percent, run.enemy_hp_percent())
	var engine := CombatEngine.new(setup)
	engine.start()
	var foe := engine.get_combatant(engine.enemy_ids()[0])
	var plain := CombatMath.percent_min1(t.base_enemy_hp, husk.enemies[0].hp_percent)
	assert_eq(foe.max_hp, CombatMath.percent_min1(plain, run.enemy_hp_percent()))
	var power := CombatMath.percent_min1(t.base_enemy_hit_damage, husk.enemies[0].power_percent)
	assert_eq(foe.power, CombatMath.percent_min1(power, run.enemy_power_percent()))


func test_bosses_keep_their_own_numbers() -> void:
	var run := _run()
	while int(run.current().get("row", -1)) < 3:
		run.go(run.choices()[0])
	var boss := run.data.final_encounter
	assert_true(boss.boss)
	assert_eq(run.fight_setup(boss, 4, CombatSetup.Opening.NORMAL).enemy_hp_percent, 100)
	run.tuning.run_enemy_scale_bosses = true
	assert_eq(run.fight_setup(boss, 4, CombatSetup.Opening.NORMAL).enemy_hp_percent, run.enemy_hp_percent())
