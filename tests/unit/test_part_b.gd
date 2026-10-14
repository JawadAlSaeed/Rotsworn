extends GutTest
## Phase 4 Part B (DESIGN 8): counters grow with longer and mixed strings (card #52); gear
## passives in fights (start AP, AP on counter, heal on jump, counter, Second Wind, perfect press,
## Exposed, tough, heal); run stats reach the engine (power, speed, max HP); the boss's phase two;
## party levels and XP; gear in the run (loot, shop, bag, equip); the shipped Part B data.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const NONE: int = Defense.Outcome.NONE
const PARRY: int = Defense.Outcome.PARRY
const JUMP: int = Defense.Outcome.JUMP
const FOE: int = Fx.ENEMY_ID
const POWERS: Array[int] = [36, 48, 40]
const SLOW_ENEMY: int = 10
const RUN_PATH := "res://data/runs/rotten_road.tres"


func _engine(attacks: Array, passives: Dictionary = {}, options: Dictionary = {}, start_hp: Array[int] = []) -> CombatEngine:
	var setup := Fx.setup(attacks, options)
	for i: int in 3:
		setup.party_passives.append(passives.duplicate())
	setup.party_start_hp = start_hp
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


func _target(engine: CombatEngine) -> int:
	return int((engine.sequence.targets as Array)[0])


func _counter_damage(events: Array[Dictionary]) -> int:
	for e: Dictionary in Fx.of_type(events, "damage"):
		if String(e.cause) in ["counter", "team_counter"]:
			return int(e.amount)
	return -1


# --- counters (card #52) ----------------------------------------------------------------------

func test_longer_strings_make_stronger_counters() -> void:
	var one := _engine([Fx.attack("one", [Fx.hit(900)])])
	var t1 := _target(one)
	var one_damage := _counter_damage(one.submit(Fx.resolve_now(one, [[0, PARRY]])))
	assert_eq(one_damage, CombatMath.percent(POWERS[t1], 150), "one hit: the plain counter")
	var five := _engine([Fx.attack("five", [Fx.hit(900, Fx.NORMAL, 20), Fx.hit(1200, Fx.NORMAL, 20),
			Fx.hit(1500, Fx.NORMAL, 20), Fx.hit(1800, Fx.NORMAL, 20), Fx.hit(2100, Fx.NORMAL, 20)])])
	var t5 := _target(five)
	var events := five.submit(Fx.resolve_now(five, [[0, PARRY], [1, PARRY], [2, PARRY], [3, PARRY], [4, PARRY]]))
	assert_eq(_counter_damage(events), CombatMath.percent(POWERS[t5], 150 + 4 * 25), "five parried hits: +25% each after the first")
	assert_eq(int(Fx.first_of(events, "counter").hits), 5)


func test_mixed_strings_add_the_mixed_bonus() -> void:
	var engine := _engine([Fx.attack("mix", [Fx.hit(900), Fx.hit(1500, Fx.GROUND)])])
	var t := _target(engine)
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY], [1, JUMP]]))
	assert_eq(_counter_damage(events), CombatMath.percent(POWERS[t], 150 + 25 + 50))
	assert_true(bool(Fx.first_of(events, "counter").mixed))


# --- gear passives ----------------------------------------------------------------------------

func test_gear_counter_bonus_and_ap_after_a_counter() -> void:
	var engine := _engine([Fx.attack("one", [Fx.hit(900)])], {Passive.COUNTER: 50, Passive.AP_ON_COUNTER: 1})
	var t := _target(engine)
	var ap_before := engine.get_combatant(t).ap
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY]]))
	assert_eq(_counter_damage(events), CombatMath.percent(POWERS[t], 200))
	var gear_ap := Fx.of_type(events, "ap_changed").filter(func(e: Dictionary) -> bool: return e.reason == "gear")
	assert_eq(gear_ap.size(), 1, "+1 AP from gear after the counter")
	assert_eq(engine.get_combatant(t).ap, ap_before + Defense.ap_reward(PARRY, Tuning.new()) + 1)


func test_start_ap_from_gear() -> void:
	var engine := _engine([Fx.attack("one", [Fx.hit(900)])], {Passive.START_AP: 2})
	assert_eq(engine.get_combatant(0).ap, Tuning.new().start_ap + 2)


func test_a_perfect_jump_heals_with_gear() -> void:
	var start: Array[int] = [50, 50, 50]
	var engine := _engine([Fx.attack("slam", [Fx.hit(900, Fx.GROUND)])], {Passive.HEAL_ON_JUMP: 10}, {}, start)
	var t := _target(engine)
	var events := engine.submit(Fx.resolve_now(engine, [[0, JUMP]]))
	var healed := Fx.first_of(events, "healed")
	assert_eq(int(healed.target), t)
	assert_eq(int(healed.amount), 10, "10% of 100 max HP")
	assert_lt(Fx.index_of(events, "prompt_resolved"), Fx.index_of(events, "healed"), "the heal follows the jump")


func test_tough_gear_lowers_enemy_hits() -> void:
	var plain := _engine([Fx.attack("one", [Fx.hit(900, Fx.NORMAL, 100)])])
	var tough := _engine([Fx.attack("one", [Fx.hit(900, Fx.NORMAL, 100)])], {Passive.TOUGH: 50})
	var plain_damage := int((plain.sequence.prompts as Array)[0].damage)
	var tough_damage := int((tough.sequence.prompts as Array)[0].damage)
	assert_eq(tough_damage, CombatMath.percent_min1(plain_damage, 50))


func test_second_wind_gets_up_once_after_the_attack() -> void:
	var killer := Fx.attack("kill", [Fx.hit(900, Fx.NORMAL, 500)])
	var engine := _engine([killer], {Passive.SECOND_WIND: 30})
	var t := _target(engine)
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
	assert_eq(Fx.of_type(events, "downed").size(), 1)
	var revived := Fx.first_of(events, "revived")
	assert_eq(int(revived.target), t)
	assert_eq(int(revived.hp), 30)
	assert_gt(Fx.index_of(events, "revived"), Fx.index_of(events, "sequence_resolved"), "back up when the attack ends")
	assert_true(engine.get_combatant(t).second_wind_used)


func test_perfect_press_and_exposed_gear_in_skill_damage() -> void:
	var cut := Fx.skill("cut", AbilityData.Target.SINGLE_ENEMY, 0, [800], {"damage_percent": 100, "press_damage_percent": 20})
	var setup := Fx.kit_setup([[cut], [cut], [cut]], [Fx.attack("one", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})
	for i: int in 3:
		setup.party_passives.append({Passive.PERFECT_PRESS: 30, Passive.EXPOSED: 40})
	var engine := CombatEngine.new(setup)
	engine.start()
	var actor := engine.active_actor
	engine.submit(Fx.use(engine, "cut"))
	var prompt: Dictionary = (engine.sequence.prompts as Array)[0]
	assert_eq(int(prompt.perfect_damage), CombatMath.percent_min1(POWERS[actor], 150), "100 + 20 + 30 gear")
	assert_eq(int(prompt.press_damage), CombatMath.percent_min1(POWERS[actor], 100))
	engine = CombatEngine.new(setup)
	engine.start()
	assert_eq(engine._exposed_bonus(engine.get_combatant(engine.active_actor), cut, true),
			Tuning.new().exposed_bonus_percent + 40)


func test_heal_gear_makes_heals_stronger() -> void:
	var mend := Fx.skill("mend", AbilityData.Target.ALLY, 0, [800], {"damage_percent": 0, "heal_percent": 30})
	var setup := Fx.kit_setup([[mend], [mend], [mend]], [Fx.attack("one", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})
	for i: int in 3:
		setup.party_passives.append({Passive.HEAL: 50})
	setup.party_start_hp.assign([10, 10, 10])
	var engine := CombatEngine.new(setup)
	engine.start()
	engine.submit(Fx.use(engine, "mend", engine.active_actor))
	var events := engine.submit(Fx.resolve_now(engine, [[0, Defense.Outcome.PRESS]]))
	assert_eq(int(Fx.first_of(events, "healed").amount), 45, "30% of 100, +50%")


func test_run_stats_reach_the_engine() -> void:
	var setup := Fx.setup([Fx.attack("one", [Fx.hit(900)])])
	setup.party_power_percent.assign([150, 100, 100])
	setup.party_speed_bonus.assign([25, 0, 0])
	setup.party_max_hp_percent.assign([120, 100, 100])
	var engine := CombatEngine.new(setup)
	engine.start()
	var c0 := engine.get_combatant(0)
	assert_eq(c0.power, CombatMath.percent_min1(POWERS[0], 150))
	assert_eq(c0.speed, setup.party[0].speed + 25)
	assert_eq(c0.max_hp, 120)


func test_unknown_passives_are_refused() -> void:
	var setup := Fx.setup([Fx.attack("one", [Fx.hit(900)])])
	setup.party_passives.append({"fly": 1})
	assert_false(setup.validate().is_empty())


# --- the boss ---------------------------------------------------------------------------------

func test_boss_enters_phase_two_once() -> void:
	var setup := Fx.setup([Fx.attack("swipe", [Fx.hit(900)])])
	var rage := Fx.attack("rage", [Fx.hit(900), Fx.hit(1200)])
	setup.enemies[0].phase_two_hp_percent = 99
	setup.enemies[0].phase_two_attacks.assign([rage])
	setup.enemies[0].phase_two_speed = 300
	setup.enemies[0].phase_two_text = "RAGE"
	var engine := CombatEngine.new(setup)
	engine.start()
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY]]))
	var phase := Fx.first_of(events, "enemy_phase")
	assert_eq(int(phase.enemy), FOE)
	assert_eq(String(phase.text), "RAGE")
	var boss := engine.get_combatant(FOE)
	assert_eq(boss.phase, 2)
	assert_eq(boss.attack_ids, ["rage"] as Array[String])
	assert_eq(boss.speed, 300)
	# At speed 300 it attacks again at once, with a phase two attack.
	assert_eq(String(engine.sequence.action), "rage", "its next attack is a phase two attack")
	assert_eq(Fx.of_type(engine.submit(Fx.resolve_now(engine, [[0, PARRY]])), "enemy_phase").size(), 0,
			"phase two starts once")


# --- the run: levels and gear -----------------------------------------------------------------

func _run() -> RunState:
	return RunState.begin(load(RUN_PATH) as RunData, Tuning.new(), 5)


func test_xp_levels_the_whole_party() -> void:
	var run := _run()
	var t := Tuning.new()
	var max_before := run.max_hp(0)
	var power_before := run.power(0)
	run.hp[0] = 10
	assert_eq(run.levels_from(t.run_xp_first_level - 1), 0)
	assert_eq(run.levels_from(t.run_xp_first_level), 1)
	assert_eq(run.add_xp(t.run_xp_first_level + 5), 1)
	assert_eq(run.level, 2)
	assert_eq(run.xp, 5)
	assert_eq(run.xp_to_next(), t.run_xp_first_level + t.run_xp_level_step)
	assert_eq(run.max_hp(0), CombatSetup.scaled_max_hp(t, run.data.party[0], 100 + t.run_level_hp_percent))
	assert_gt(run.power(0), power_before)
	assert_eq(run.hp[0], 10 + run.max_hp(0) - max_before, "a level up heals what max HP grew")
	run.add_xp(1000000)
	assert_eq(run.level, t.run_max_level, "levels stop at the max")
	assert_eq(run.xp, 0)


func test_a_victory_pays_xp() -> void:
	var run := _run()
	run.go(run.choices()[0])
	var husk := load("res://data/encounters/husk_fight.tres") as EncounterData
	var hp: Array[int] = [50, 50, 50]
	var got := run.finish_fight(RunState.VICTORY, hp, husk)
	assert_eq(int(got.xp), RunState.encounter_xp(husk))
	assert_gt(int(got.xp), 0)


func test_loot_and_shop_offer_gear_the_party_does_not_own() -> void:
	var run := _run()
	var loot := run.loot_choices(3)
	assert_eq(loot.size(), Tuning.new().run_loot_choices)
	assert_eq(run.loot_choices(3), loot, "the same stop offers the same loot")
	assert_eq(run.wear(0, 0, loot[0]), 0)
	assert_eq(run.wear(1, 0, loot[0]), -1, "one of each")
	assert_false(run.loot_choices(3).has(loot[0]), "worn gear is not offered again")
	var shop := run.shop_gear(4)
	assert_eq(shop.size(), Tuning.new().run_shop_gear)
	run.gold = 0
	assert_false(run.buy_gear(shop[0]))
	run.gold = shop[0].price
	assert_true(run.buy_gear(shop[0]))
	assert_eq(run.gold, 0)
	assert_eq(run.wear(2, 0, shop[0]), 0, "bought gear goes straight on a hero")


func test_wear_swap_and_sell_gear() -> void:
	var run := _run()
	var charm := _gear(run, GearData.Effect.MAX_HP)
	var stone := _gear(run, GearData.Effect.POWER)
	var hp_before := run.hp[0]
	var max_before := run.max_hp(0)
	assert_eq(run.wear(0, 0, charm), 0, "an empty slot sells nothing")
	assert_gt(run.max_hp(0), max_before)
	assert_eq(run.hp[0], hp_before, "putting gear on never heals")
	run.gold = 0
	assert_eq(run.wear(0, 0, stone), run.gear_sell_price(charm), "a full slot sells what was there")
	assert_eq(run.gold, CombatMath.percent(charm.price, run.tuning.item_sell_percent))
	assert_false(run.owns(charm), "sold gear is gone")
	assert_eq(run.power_percent(0), 100 + stone.amount)
	assert_eq(run.wear(1, 0, stone), -1, "worn gear cannot be worn twice")
	run.wear(1, 0, charm)
	run.hp[1] = run.max_hp(1)
	assert_true(run.swap_gear(1, 0, 2, 1), "gear moves to another hero")
	assert_eq(run.gear[2][1], charm)
	assert_eq(run.free_gear_slot(1), 0)
	assert_eq(run.hp[1], run.max_hp(1), "HP is cut to the lower max")
	assert_true(run.swap_gear(2, 1, 0, 0), "two worn pieces swap")
	assert_eq(run.gear[0][0], charm)
	assert_eq(run.gear[2][1], stone)
	assert_false(run.swap_gear(1, 0, 2, 0), "an empty slot has nothing to move")
	run.gold = 0
	assert_eq(run.sell_new_gear(_gear(run, GearData.Effect.SPEED)), run.gold, "new gear nobody wears is sold")


func test_gear_reaches_the_fight_setup() -> void:
	var run := _run()
	var ring := _gear(run, GearData.Effect.COUNTER)
	var boots := _gear(run, GearData.Effect.SPEED)
	var coin := _gear(run, GearData.Effect.GOLD)
	for item: GearData in [ring, boots, coin]:
		run.wear(1, run.free_gear_slot(1), item)
	var husk := load("res://data/encounters/husk_fight.tres") as EncounterData
	var setup := run.fight_setup(husk, 1, CombatSetup.Opening.NORMAL)
	assert_eq(setup.party_passives[1], {Passive.COUNTER: ring.amount})
	var engine := CombatEngine.new(setup)
	engine.start()
	var brin := engine.get_combatant(1)
	assert_eq(brin.speed, run.speed(1))
	assert_eq(brin.power, run.power(1))
	assert_eq(brin.max_hp, run.max_hp(1))
	assert_eq(run.gold_for(husk), CombatMath.percent(RunState.encounter_gold(husk), 100 + coin.amount))


func _gear(run: RunState, effect: GearData.Effect) -> GearData:
	for item: GearData in run.data.gear:
		if item.effect == effect:
			return item
	fail_test("the shipped run has gear with effect %d" % effect)
	return GearData.new()


# --- shipped data -----------------------------------------------------------------------------

func test_shipped_gear_and_boss() -> void:
	var data := load(RUN_PATH) as RunData
	assert_gte(data.gear.size(), 10, "enough gear for a few runs")
	var ids := {}
	for item: GearData in data.gear:
		assert_false(ids.has(item.id), "%s is listed once" % item.id)
		ids[item.id] = true
		assert_gt(item.price, 0)
		assert_false(item.description.is_empty(), "%s says what it does" % item.id)
	var boss_fight := data.final_encounter
	assert_true(boss_fight.boss, "the run ends with a boss")
	var boss := boss_fight.enemies[0]
	assert_gt(boss.phase_two_hp_percent, 0, "the boss has a phase two")
	assert_gt(boss.phase_two_attacks.size(), 0)
	assert_false(boss.phase_two_text.is_empty())
	var setup := RunState.begin(data, Tuning.new(), 1).fight_setup(boss_fight, 1, CombatSetup.Opening.NORMAL)
	assert_eq(setup.validate(), PackedStringArray())
	for file: String in DirAccess.get_files_at("res://data/enemies"):
		if file.ends_with(".tres"):
			var enemy := load("res://data/enemies".path_join(file)) as EnemyData
			if enemy != boss:
				assert_gt(enemy.xp, 0, "%s gives XP" % enemy.id)
