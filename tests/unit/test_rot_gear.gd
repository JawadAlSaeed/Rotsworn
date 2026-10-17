extends GutTest
## Rot-touched gear (card #198, DESIGN.md 8.16): strong pieces with a price. Each new passive's
## effect and drawback in the engine, the pieces' numbers on the run side, spoils that offer one,
## shops that sell them rarely, the bot's pick, the Tonic fix, and determinism. Never touches the
## real user:// files.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const RUN_PATH := "res://data/runs/rotten_road.tres"
const NONE: int = Defense.Outcome.NONE
const DODGE: int = Defense.Outcome.DODGE
const PARRY: int = Defense.Outcome.PARRY
const FOE: int = Fx.ENEMY_ID
const SLOW_ENEMY: int = 10

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func _run(seed_value: int = 7) -> RunState:
	return RunState.begin(_data, _tuning.duplicate(true) as Tuning, seed_value)


func _piece(id: String) -> GearData:
	for item: GearData in _data.gear:
		if item.id == id:
			return item
	fail_test("the shipped run has the gear %s" % id)
	return GearData.new()


func _rot_pieces() -> Array[GearData]:
	var found: Array[GearData] = []
	for item: GearData in _data.gear:
		if item.rot_touched:
			found.append(item)
	return found


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


# --- the data -----------------------------------------------------------------------------------

func test_about_ten_rot_touched_pieces_ship_each_with_a_price_or_a_condition() -> void:
	var pieces := _rot_pieces()
	assert_gte(pieces.size(), 10)
	var ids := {}
	for item: GearData in pieces:
		assert_false(ids.has(item.id), "%s is listed once" % item.id)
		ids[item.id] = true
		assert_gte(int(item.rarity), _tuning.run_spoils_min_rarity, "%s can be offered by spoils" % item.id)
		assert_false(item.description.is_empty(), item.id)
		assert_false(GearData.effect_text(item.effect, item.amount).is_empty(), "%s has an effect line" % item.id)
		if item.has_drawback():
			assert_false(GearData.drawback_text(item.drawback, item.drawback_amount).is_empty(), item.id)
			assert_true(item.effect_line().contains("|"), "%s shows both halves" % item.id)
	var priced := pieces.filter(func(item: GearData) -> bool: return item.has_drawback())
	assert_gte(priced.size(), pieces.size() - 2, "mostly drawbacks; at most a couple only have a condition")


func test_rot_touched_gear_has_its_own_colour_and_name() -> void:
	var crown := _piece("rotten_crown")
	var step := BackpackGrid.gear_step(crown)
	assert_eq(BackpackGrid.rarity_name(step), "rot-touched")
	assert_eq(BackpackGrid.rarity_color(step), GearData.ROT_TOUCHED_COLOR)
	var plain := _piece("iron_charm")
	assert_ne(BackpackGrid.gear_step(plain), step)
	assert_false(plain.rot_touched)


func test_every_rot_touched_piece_reaches_a_valid_fight_setup() -> void:
	var husk := load("res://data/encounters/husk_fight.tres") as EncounterData
	for item: GearData in _rot_pieces():
		var run := _run()
		run.wear(0, 0, item)
		var setup := run.fight_setup(husk, 3, CombatSetup.Opening.NORMAL)
		assert_true(setup.validate().is_empty(), "%s: %s" % [item.id, str(setup.validate())])
		var engine := CombatEngine.new(setup)
		engine.start()
		assert_true(engine.get_combatant(0).is_alive(), item.id)


# --- each piece on the run side -----------------------------------------------------------------

func test_rotten_crown_adds_power_and_weakens_healing() -> void:
	var run := _run()
	var before := run.power_percent(0)
	run.wear(0, 0, _piece("rotten_crown"))
	assert_eq(run.power_percent(0), before + 35)
	assert_eq(int(run.passives(0)[Passive.HEAL_TAKEN]), -40)
	run.hp[0] = 10
	var healed := run.heal(0, 100)
	assert_eq(healed, 60, "100 points of healing arrive as 60")
	assert_eq(run.heal(1, 0), 0)


func test_gravebound_ring_trades_max_hp_for_counters() -> void:
	var run := _run()
	var before := run.total_max_hp_percent(0)
	run.wear(0, 0, _piece("gravebound_ring"))
	assert_eq(int(run.passives(0)[Passive.COUNTER]), 80)
	assert_eq(run.total_max_hp_percent(0), before - 15)
	assert_eq(run.hp[0], mini(run.hp[0], run.max_hp(0)), "HP is cut to the lower max")


func test_hunger_charm_heals_on_kills_but_the_campfire_does_nothing_for_the_wearer() -> void:
	var run := _run()
	run.wear(0, 0, _piece("hunger_charm"))
	assert_eq(int(run.passives(0)[Passive.KILL_HEAL]), 8)
	assert_eq(run.rest_heal_percent_of(0), 0)
	assert_eq(run.rest_heal_percent_of(1), run.rest_heal_percent())
	for slot: int in run.party_size():
		run.hp[slot] = 1
	var healed := run.rest()
	assert_eq(healed[0], 0, "the wearer gets nothing from Rest")
	assert_gt(healed[1], 0, "everyone else still does")
	assert_eq(run.hp[0], 1)


func test_last_ember_and_the_others_set_their_passives() -> void:
	var run := _run()
	var wants := {
		"last_ember": {Passive.LOW_HP_POWER: 40},
		"ash_veil": {Passive.DODGE_AP: 1, Passive.PARRY_AP: -1},
		"thorned_gauntlet": {Passive.THORNS: 30, Passive.TOUGH: -10},
		"oathbreakers_band": {Passive.START_AP: 2},
		"chain_of_silence": {Passive.GAUGE: 50, Passive.START_AP: -1},
		"bloodletters_fang": {Passive.CRIT: 25, Passive.ROT: 4},
		"hollow_mantle": {Passive.TOUGH: 25},
		"pale_tithe": {Passive.PERFECT_PRESS: 40, Passive.HEAL: -50},
		"plague_bell": {Passive.EXPOSED: 90},
	}
	for id: String in wants:
		run = _run()
		run.wear(0, 0, _piece(id))
		assert_eq(run.passives(0), wants[id], id)


func test_stat_drawbacks_change_the_hero_stats() -> void:
	var run := _run()
	var speed := run.speed(0)
	var power := run.power_percent(0)
	run.wear(0, 0, _piece("hollow_mantle"))
	assert_eq(run.speed(0), speed - 10)
	assert_eq(run.defense_percent(0), 25)
	run.wear(0, 1, _piece("plague_bell"))
	assert_eq(run.power_percent(0), power - 10)
	run = _run()
	run.wear(1, 0, _piece("thorned_gauntlet"))
	assert_eq(run.defense_percent(1), -10, "the hero takes 10% more")
	run = _run()
	run.wear(1, 0, _piece("bloodletters_fang"))
	assert_eq(run.crit_percent(1), _tuning.crit_base_percent + 25)


func test_oathbreakers_band_costs_max_hp_after_each_fight_won() -> void:
	var run := _run()
	run.go(run.choices()[0])
	run.wear(0, 0, _piece("oathbreakers_band"))
	var husk := load("res://data/encounters/husk_fight.tres") as EncounterData
	var before := run.max_hp_percent.duplicate()
	var hp: Array[int] = [run.max_hp(0), run.max_hp(1), run.max_hp(2)]
	run.finish_fight(RunState.VICTORY, hp, husk)
	assert_lt(run.max_hp_percent[0], before[0], "the wearer lost max HP for good")
	assert_eq(run.max_hp_percent[1], before[1], "the others did not")
	assert_eq(run.max_hp_percent[2], before[2])
	var floor_points: int = _tuning.event_max_hp_floor_percent
	for i: int in 40:
		run.finish_fight(RunState.VICTORY, hp, husk)
	assert_gte(run.max_hp_percent[0], floor_points, "never below the floor events also keep")
	assert_gte(run.hp[0], 1)


func test_a_drawback_on_the_same_effect_takes_away_and_empty_sums_vanish() -> void:
	var odd := GearData.new()
	odd.effect = GearData.Effect.TOUGH
	odd.amount = 10
	odd.drawback = GearData.Effect.TOUGH
	odd.drawback_amount = 10
	var run := _run()
	run.gear[0][0] = odd
	assert_false(run.passives(0).has(Passive.TOUGH), "10 - 10 leaves nothing")
	assert_eq(odd.contribution(GearData.Effect.TOUGH), 0)
	var rot := GearData.new()
	rot.effect = GearData.Effect.MAX_HP
	rot.drawback = GearData.Effect.ROT
	rot.drawback_amount = 3
	assert_eq(rot.contribution(GearData.Effect.ROT), 3, "a loss effect adds its loss")


# --- the engine: each new passive ---------------------------------------------------------------

func test_healing_received_is_scaled_in_fights() -> void:
	var mend := Fx.skill("mend", AbilityData.Target.ALLY, 0, [800], {"damage_percent": 0, "heal_percent": 30})
	for case: Array in [[-40, 18], [0, 30], [50, 45]]:
		var setup := Fx.kit_setup([[mend], [mend], [mend]], [Fx.attack("one", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})
		for i: int in 3:
			setup.party_passives.append({Passive.HEAL_TAKEN: int(case[0])})
		setup.party_start_hp.assign([10, 10, 10])
		var engine := CombatEngine.new(setup)
		engine.start()
		engine.submit(Fx.use(engine, "mend", engine.active_actor))
		var events := engine.submit(Fx.resolve_now(engine, [[0, Defense.Outcome.PRESS]]))
		assert_eq(int(Fx.first_of(events, "healed").amount), int(case[1]), "HEAL_TAKEN %d" % int(case[0]))


func test_a_kill_heals_the_killer() -> void:
	var hurt: Array[int] = [50, 50, 50]
	var engine := _engine([Fx.attack("one", [Fx.hit(900)])], {Passive.KILL_HEAL: 8},
			{"enemy_speed": SLOW_ENEMY, "enemy_hp_percent": 1}, hurt)
	var actor := engine.active_actor
	var events := engine.submit(Fx.use(engine, "basic_attack"))
	var healed := Fx.first_of(events, "healed")
	assert_eq(int(healed.target), actor)
	assert_eq(int(healed.amount), 8, "8% of 100 max HP")
	assert_lt(Fx.index_of(events, "downed"), Fx.index_of(events, "healed"), "after the kill")
	var plain := _engine([Fx.attack("one", [Fx.hit(900)])], {}, {"enemy_speed": SLOW_ENEMY, "enemy_hp_percent": 1}, hurt)
	assert_eq(Fx.of_type(plain.submit(Fx.use(plain, "basic_attack")), "healed").size(), 0, "no gear, no heal")


func test_power_rises_only_while_low_on_hp() -> void:
	var limit: int = Tuning.new().rot_low_hp_percent
	for case: Array in [[limit - 1, true], [limit, false], [100, false]]:
		var hp: Array[int] = [int(case[0]), 100, 100]
		var engine := _engine([Fx.attack("one", [Fx.hit(900)])], {Passive.LOW_HP_POWER: 40}, {"enemy_speed": SLOW_ENEMY}, hp)
		var c := engine.get_combatant(0)
		var expected := CombatMath.percent_min1(c.power, 140) if bool(case[1]) else c.power
		assert_eq(engine._power_of(c), expected, "HP %d of 100" % int(case[0]))
	var plain := _engine([Fx.attack("one", [Fx.hit(900)])], {}, {"enemy_speed": SLOW_ENEMY}, [5, 5, 5] as Array[int])
	assert_eq(plain._power_of(plain.get_combatant(0)), plain.get_combatant(0).power, "no gear: no bonus")


func test_low_hp_power_reaches_a_basic_attack() -> void:
	var low: Array[int] = [10, 10, 10]
	var strong := _engine([Fx.attack("one", [Fx.hit(900)])], {Passive.LOW_HP_POWER: 100}, {"enemy_speed": SLOW_ENEMY}, low)
	var weak := _engine([Fx.attack("one", [Fx.hit(900)])], {}, {"enemy_speed": SLOW_ENEMY}, low)
	var strong_hit := int(Fx.first_of(strong.submit(Fx.use(strong, "basic_attack")), "damage").amount)
	var weak_hit := int(Fx.first_of(weak.submit(Fx.use(weak, "basic_attack")), "damage").amount)
	assert_gt(strong_hit, weak_hit)


func test_dodge_gives_ap_and_a_parry_gives_none_with_ash_veil() -> void:
	var passives := {Passive.DODGE_AP: 1, Passive.PARRY_AP: -1}
	var base := Defense.ap_reward(DODGE, Tuning.new())
	for case: Array in [[DODGE, base + 1], [PARRY, 0], [NONE, 0]]:
		var engine := _engine([Fx.attack("one", [Fx.hit(900)])], passives)
		var t := _target(engine)
		var before := engine.get_combatant(t).ap
		engine.submit(Fx.resolve_now(engine, [[0, int(case[0])]]))
		assert_eq(engine.get_combatant(t).ap - before, int(case[1]), "outcome %d" % int(case[0]))
	var plain := _engine([Fx.attack("one", [Fx.hit(900)])])
	var t2 := _target(plain)
	var ap := plain.get_combatant(t2).ap
	plain.submit(Fx.resolve_now(plain, [[0, PARRY]]))
	assert_eq(plain.get_combatant(t2).ap - ap, Tuning.new().ap_per_parry, "without the veil a parry gives its AP")


func test_thorns_hurt_the_attacker_and_negative_tough_hurts_the_wearer() -> void:
	var engine := _engine([Fx.attack("one", [Fx.hit(900, Fx.NORMAL, 100)])], {Passive.THORNS: 30, Passive.TOUGH: -10})
	var plain := _engine([Fx.attack("one", [Fx.hit(900, Fx.NORMAL, 100)])])
	var plain_damage := int((plain.sequence.prompts as Array)[0].damage)
	var damage := int((engine.sequence.prompts as Array)[0].damage)
	assert_between(damage, CombatMath.percent_min1(plain_damage, 110) - 1, CombatMath.percent_min1(plain_damage, 110) + 1,
			"10% more")
	var foe_before := engine.get_combatant(FOE).hp
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
	var thorn := Fx.of_type(events, "damage").filter(func(e: Dictionary) -> bool: return e.cause == "thorns")
	assert_eq(thorn.size(), 1)
	var back := CombatMath.percent_min1(damage, 30)
	assert_eq(int(thorn[0].amount), back)
	assert_eq(int(thorn[0].target), FOE)
	assert_eq(engine.get_combatant(FOE).hp, foe_before - back)
	var defended := _engine([Fx.attack("one", [Fx.hit(900)])], {Passive.THORNS: 30})
	var hp := defended.get_combatant(FOE).hp
	defended.submit(Fx.resolve_now(defended, [[0, DODGE]]))
	assert_eq(defended.get_combatant(FOE).hp, hp, "a hit that never landed reflects nothing")


func test_thorns_that_kill_the_attacker_end_the_fight_cleanly() -> void:
	var engine := _engine([Fx.attack("flurry", [Fx.hit(900), Fx.hit(1200), Fx.hit(1500)])], {Passive.THORNS: 100},
			{"enemy_hp_percent": 1})
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE], [1, NONE], [2, NONE]]))
	assert_eq(engine.phase, CombatEngine.Phase.ENDED, "the thorns finished it")
	assert_eq(String(Fx.first_of(events, "combat_ended").result), "victory")
	assert_eq(Fx.of_type(events, "damage").filter(func(e: Dictionary) -> bool: return e.cause == "thorns").size(), 1,
			"no more reflections once it is down")


func test_the_team_gauge_fills_more_with_gauge_gear() -> void:
	var cut := Fx.skill("cut", AbilityData.Target.SINGLE_ENEMY, 0, [800], {"damage_percent": 100, "gauge_gain": 20})
	for case: Array in [[0, 20], [50, 30], [-100, 0]]:
		var setup := Fx.kit_setup([[cut], [cut], [cut]], [Fx.attack("one", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})
		for i: int in 3:
			setup.party_passives.append({Passive.GAUGE: int(case[0])})
		var engine := CombatEngine.new(setup)
		engine.start()
		engine.submit(Fx.use(engine, "cut"))
		var events := engine.submit(Fx.resolve_now(engine, [[0, Defense.Outcome.PRESS]]))
		assert_eq(engine.team_gauge, int(case[1]), "GAUGE %d" % int(case[0]))
		assert_gte(Fx.of_type(events, "sequence_resolved").size(), 1)


func test_start_ap_can_be_a_gain_or_a_loss_and_never_below_zero() -> void:
	var base: int = Tuning.new().start_ap
	assert_eq(_engine([Fx.attack("one", [Fx.hit(900)])], {Passive.START_AP: 2}).get_combatant(0).ap, base + 2)
	assert_eq(_engine([Fx.attack("one", [Fx.hit(900)])], {Passive.START_AP: -1}).get_combatant(0).ap, maxi(0, base - 1))
	assert_eq(_engine([Fx.attack("one", [Fx.hit(900)])], {Passive.START_AP: -9}).get_combatant(0).ap, 0)


func test_rot_gear_drains_the_wearer_each_turn_but_never_to_zero() -> void:
	var engine := _engine([Fx.attack("one", [Fx.hit(900)])], {Passive.ROT: 4}, {"enemy_speed": SLOW_ENEMY})
	var actor := engine.get_combatant(0)
	var events: Array[Dictionary] = []
	engine._start_of_turn(actor, events)
	var rot := Fx.of_type(events, "damage").filter(func(e: Dictionary) -> bool: return e.cause == "rot")
	assert_eq(rot.size(), 1)
	assert_eq(int(rot[0].amount), 4, "4% of 100 max HP")
	actor.hp = 2
	events.clear()
	engine._start_of_turn(actor, events)
	assert_eq(actor.hp, 1, "never below 1 HP")


func test_healing_dealt_can_be_halved_and_a_heal_never_goes_negative() -> void:
	var mend := Fx.skill("mend", AbilityData.Target.ALLY, 0, [800], {"damage_percent": 0, "heal_percent": 30})
	var setup := Fx.kit_setup([[mend], [mend], [mend]], [Fx.attack("one", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})
	for i: int in 3:
		setup.party_passives.append({Passive.HEAL: -50})
	setup.party_start_hp.assign([10, 10, 10])
	var engine := CombatEngine.new(setup)
	engine.start()
	engine.submit(Fx.use(engine, "mend", engine.active_actor))
	var events := engine.submit(Fx.resolve_now(engine, [[0, Defense.Outcome.PRESS]]))
	assert_eq(int(Fx.first_of(events, "healed").amount), 15, "Pale Tithe: 30 becomes 15")


# --- determinism --------------------------------------------------------------------------------

func test_the_same_seed_and_commands_give_the_same_events_with_every_new_passive() -> void:
	var passives := {Passive.HEAL_TAKEN: -40, Passive.KILL_HEAL: 8, Passive.LOW_HP_POWER: 40, Passive.DODGE_AP: 1,
			Passive.PARRY_AP: -1, Passive.THORNS: 30, Passive.GAUGE: 50, Passive.TOUGH: -10}
	var runs: Array = []
	for i: int in 2:
		var engine := _engine([Fx.attack("flurry", [Fx.hit(900), Fx.hit(1200)])], passives, {"seed": 11})
		var all: Array = []
		all.append_array(engine.submit(Fx.resolve_now(engine, [[0, NONE], [1, DODGE]])))
		all.append_array(engine.submit(Fx.use(engine, "basic_attack")))
		runs.append(var_to_str(all))
	assert_eq(runs[0], runs[1])


# --- spoils and shops ---------------------------------------------------------------------------

func test_spoils_always_offer_a_rot_touched_piece_among_their_choices() -> void:
	for seed_value: int in range(1, 25):
		var run := _run(seed_value)
		for stop: Dictionary in run.map.stops:
			var loot := run.loot_choices(int(stop.id))
			assert_eq(loot.size(), _tuning.run_loot_choices, "seed %d stop %d" % [seed_value, int(stop.id)])
			var rot := loot.filter(func(item: GearData) -> bool: return item.rot_touched)
			assert_eq(rot.size(), _tuning.rot_gear_spoils_count, "one rot-touched piece")
			assert_true(loot[loot.size() - 1].rot_touched, "listed last")
			for item: GearData in loot:
				assert_gte(int(item.rarity), _tuning.run_spoils_min_rarity, "the spoils rule stays")
			assert_eq(run.loot_choices(int(stop.id)), loot, "the same stop offers the same loot")


func test_spoils_skip_rot_touched_gear_the_party_wears_and_run_out_gracefully() -> void:
	var run := _run()
	var stop := int(run.choices()[0])
	for item: GearData in _rot_pieces():
		var free := run.free_gear_slot(0)
		if free < 0:
			break
		run.wear(0, free, item)
	for slot: int in range(1, run.party_size()):
		for item: GearData in _rot_pieces():
			if not run.owns(item) and run.free_gear_slot(slot) >= 0:
				run.wear(slot, run.free_gear_slot(slot), item)
	var loot := run.loot_choices(stop)
	for item: GearData in loot:
		assert_false(run.owns(item), "worn gear is not offered again")
	assert_eq(loot.size(), _tuning.run_loot_choices, "ordinary gear fills the choices")


func test_a_single_spoils_choice_is_never_forced_to_be_rot_touched() -> void:
	var ladder: Array[OathData] = []
	var oath := OathData.new()
	oath.loot_choices_add = -20
	ladder.append(oath)
	var data := _data.duplicate() as RunData
	data.oaths = ladder
	var run := RunState.begin(data, _tuning.duplicate(true) as Tuning, 7, 1)
	assert_eq(run.loot_choice_count(), 1)
	var plain := 0
	for stop: Dictionary in run.map.stops:
		var loot := run.loot_choices(int(stop.id))
		assert_eq(loot.size(), 1)
		if not loot[0].rot_touched:
			plain += 1
	assert_eq(plain, run.map.stops.size(), "with one choice it is an ordinary piece")


func test_the_rot_spoils_count_is_tuning() -> void:
	var tuning := _tuning.duplicate(true) as Tuning
	tuning.rot_gear_spoils_count = 0
	var run := RunState.begin(_data, tuning, 3)
	for stop: Dictionary in run.map.stops:
		for item: GearData in run.loot_choices(int(stop.id)):
			assert_false(item.rot_touched, "0 turns the guarantee off")
	tuning.rot_gear_spoils_count = 2
	var two := RunState.begin(_data, tuning, 3)
	var loot := two.loot_choices(int(two.map.stops[0].id))
	assert_eq(loot.filter(func(item: GearData) -> bool: return item.rot_touched).size(), 2)
	assert_eq(loot.size(), tuning.run_loot_choices)


func test_shops_sell_rot_touched_gear_rarely() -> void:
	var rot := 0
	var all := 0
	for seed_value: int in range(1, 80):
		var run := _run(seed_value)
		for stop: Dictionary in run.map.stops:
			for item: GearData in run.shop_gear(int(stop.id)):
				all += 1
				if item.rot_touched:
					rot += 1
	var pool_share := float(_rot_pieces().size()) / float(_data.gear.size())
	assert_gt(rot, 0, "they do turn up")
	assert_lt(float(rot) / float(all), pool_share * 0.75, "but less often than their share of the pool")


# --- the bot ------------------------------------------------------------------------------------

func test_the_bot_takes_a_bearable_rot_touched_piece_and_refuses_a_costly_one() -> void:
	var iron := _piece("iron_charm")
	var veil := _piece("ash_veil")
	var crown := _piece("rotten_crown")
	var ember := _piece("last_ember")
	var offered: Array[GearData] = [iron, veil]
	assert_eq(GearBot.pick(offered), 1, "Ash Veil's price is a parry's AP: bearable")
	offered = [_piece("second_wind"), crown]
	assert_eq(GearBot.pick(offered), 0, "the Crown's weaker healing is not")
	assert_eq(GearBot.score(crown), -1)
	offered = [iron, ember, crown]
	assert_eq(GearBot.pick(offered), 1, "a piece with no drawback is welcome")
	var costly: Array[GearData] = [crown, _piece("gravebound_ring")]
	assert_eq(GearBot.pick(costly), 0, "nothing bearable: the first, no crash")
	var none: Array[GearData] = []
	assert_eq(GearBot.pick(none), 0)


func test_the_bot_sells_rot_touched_gear_it_refuses_instead_of_wearing_it() -> void:
	var run := _run()
	var screen := PartyScreen.new()
	add_child_autofree(screen)
	screen.setup(run, "", {"gear": _piece("rotten_crown")})
	screen.auto_settle()
	assert_false(run.owns(_piece("rotten_crown")), "refused: sold on the spot")
	assert_gt(run.gold, 0)
	var other := PartyScreen.new()
	add_child_autofree(other)
	other.setup(run, "", {"gear": _piece("ash_veil")})
	other.auto_settle()
	assert_true(run.owns(_piece("ash_veil")), "bearable: worn")


# --- the Tonic fix ------------------------------------------------------------------------------

func test_tonics_cannot_be_upgraded_or_combined_so_the_cap_limits_max_hp() -> void:
	var run := _run()
	var tonic := run.items_by_id()["tonic"] as ItemData
	assert_false(tonic.combinable(), "no stronger Tonic")
	var a := run.add_item(tonic)
	var b := run.add_item(tonic)
	assert_false(run.can_upgrade(a))
	assert_false(run.can_combine(a, b))
	assert_false(run.upgrade_item(a))
	assert_true((run.items_by_id()["salve"] as ItemData).combinable(), "other consumables still combine")


func test_a_tonic_gives_the_same_max_hp_whatever_its_level() -> void:
	var run := _run()
	var tonic := run.items_by_id()["tonic"] as ItemData
	var uid := run.add_item(tonic)
	# An old save can hold a levelled Tonic: it must not give more.
	run.backpack.entry(uid).level = 2
	assert_eq(run.entry_amount(run.backpack.entry(uid)), tonic.amount_percent)
	var before := run.max_hp_percent[0]
	assert_true(run.use_item(uid, 0))
	assert_eq(run.max_hp_percent[0], before + tonic.amount_percent)
	var second := run.add_item(tonic)
	run.backpack.entry(second).level = 3
	assert_true(run.use_item(second, 0))
	assert_eq(run.max_hp_percent[0], before + 2 * tonic.amount_percent, "two Tonics, two plain gains")
	var third := run.add_item(tonic)
	assert_false(run.use_item(third, 0), "the cap still holds")


func test_a_tonic_heals_its_new_hp_whatever_the_wearer_gear_says() -> void:
	var run := _run()
	run.wear(0, 0, _piece("rotten_crown"))
	var tonic := run.items_by_id()["tonic"] as ItemData
	var before_max := run.max_hp(0)
	var before_hp := run.hp[0]
	assert_true(run.use_item(run.add_item(tonic), 0))
	assert_eq(run.hp[0] - before_hp, run.max_hp(0) - before_max, "the new HP is filled in full")


# --- saving -------------------------------------------------------------------------------------

func test_worn_rot_touched_gear_survives_a_save() -> void:
	var run := _run()
	run.wear(0, 0, _piece("rotten_crown"))
	run.wear(1, 1, _piece("oathbreakers_band"))
	var copy := RunState.from_dict(run.data, run.tuning, run.to_dict())
	assert_not_null(copy)
	assert_eq(copy.gear[0][0], _piece("rotten_crown"))
	assert_eq(copy.gear[1][1], _piece("oathbreakers_band"))
	assert_eq(copy.passives(0), run.passives(0))
