extends GutTest
## Phase 20 (card #242, DESIGN.md 8.17): 16 more Relics, 50 in all, eight of them with new effects.
## The shipped data, each new effect in the engine or the run, and the lower drop chance (#243).

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const RUN_PATH := "res://data/runs/rotten_road.tres"
const PARRY: int = Defense.Outcome.PARRY
const SLOW_ENEMY: int = 10
const NEW_IDS: Array[String] = ["brimming_cup", "reapers_coin", "victors_wreath", "first_light", "mossbed",
	"breakers_maul", "butchers_edge", "still_water", "bramble_coat", "fox_step", "marrow_charm", "bone_whistle",
	"tallow_candle", "hollow_drum", "sour_milk", "crown_of_thorns"]

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = Fx.without_relic_stats(load(RUN_PATH) as RunData)
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func _engine(passives: Dictionary, options: Dictionary = {}, start_hp: Array[int] = []) -> CombatEngine:
	var setup := Fx.setup([Fx.attack("one", [Fx.hit(900)])], options)
	for i: int in 3:
		setup.party_passives.append(passives.duplicate())
	setup.party_start_hp = start_hp
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


func _piece(id: String) -> GearData:
	for item: GearData in _data.gear:
		if item.id == id:
			return item
	fail_test("the shipped run has the Relic %s" % id)
	return GearData.new()


# --- the data -----------------------------------------------------------------------------------

func test_fifty_relics_ship_and_every_one_is_dropped_by_a_monster() -> void:
	var shipped := load(RUN_PATH) as RunData
	assert_eq(shipped.gear.size(), 50)
	var dropped := {}
	for file: String in DirAccess.get_files_at("res://data/enemies/"):
		if not file.ends_with(".tres"):
			continue
		var enemy := load("res://data/enemies/" + file) as EnemyData
		for item: GearData in enemy.relic_drops:
			dropped[item.id] = true
	var ids := {}
	for item: GearData in shipped.gear:
		assert_false(ids.has(item.id), "%s is listed once" % item.id)
		ids[item.id] = true
		assert_true(dropped.has(item.id), "%s is dropped by some monster" % item.id)
	for id: String in NEW_IDS:
		assert_true(ids.has(id), "%s ships" % id)


func test_the_new_relics_say_what_they_do_and_have_a_stat_line() -> void:
	var shipped := load(RUN_PATH) as RunData
	for item: GearData in shipped.gear:
		if not NEW_IDS.has(item.id):
			continue
		assert_false(item.description.is_empty(), item.id)
		assert_false(GearData.effect_text(item.effect, item.amount).is_empty(), item.id + " has an effect line")
		assert_gt(item.stat_points, 0, item.id + " has a stat line")
		assert_between(item.echo_cost, 1, 4, item.id + ": an Echo cost (by strength since phase 21)")
		var runs_in_fight := GearData.PASSIVE_KEYS.has(item.effect)
		assert_true(runs_in_fight or item.effect == GearData.Effect.WIN_HEAL or item.effect == GearData.Effect.SPEED,
				item.id + " does something")


func test_the_drop_chance_is_eight_percent() -> void:
	assert_eq(_tuning.relic_drop_percent, 8, "card #243: 25% fewer drops than 10%")


# --- the new effects ----------------------------------------------------------------------------

func test_full_hp_power_only_at_full_hp() -> void:
	for case: Array in [[100, true], [99, false]]:
		var hp: Array[int] = [int(case[0]), 100, 100]
		var engine := _engine({Passive.FULL_HP_POWER: 20}, {"enemy_speed": SLOW_ENEMY}, hp)
		var c := engine.get_combatant(0)
		var expected := CombatMath.percent_min1(c.power, 120) if bool(case[1]) else c.power
		assert_eq(engine._power_of(c), expected, "HP %d of 100" % int(case[0]))


func test_a_kill_gives_ap() -> void:
	var options := {"enemy_speed": SLOW_ENEMY, "enemy_hp_percent": 1}
	var with := _engine({Passive.KILL_AP: 1}, options)
	var plain := _engine({}, options)
	var actor := with.active_actor
	with.submit(Fx.use(with, "basic_attack"))
	plain.submit(Fx.use(plain, "basic_attack"))
	assert_eq(with.get_combatant(actor).ap, plain.get_combatant(actor).ap + 1)


func test_fights_can_start_empowered_or_with_regen() -> void:
	var engine := _engine({Passive.START_EMPOWERED: 1, Passive.START_REGEN: 2})
	var hero := engine.get_combatant(0)
	assert_true(hero.has_status(Status.EMPOWERED))
	assert_true(hero.has_status(Status.REGEN))
	assert_eq(int((hero.statuses[Status.REGEN] as Dictionary).turns), 2)
	var plain := _engine({})
	assert_false(plain.get_combatant(0).has_status(Status.EMPOWERED))
	assert_false(plain.get_combatant(0).has_status(Status.REGEN))


func test_staggered_enemies_take_more_from_a_breaker() -> void:
	var hits: Array[int] = []
	for passives: Dictionary in [{}, {Passive.STAGGER_DAMAGE: 25}]:
		var engine := _engine(passives, {"enemy_speed": SLOW_ENEMY})
		var foe := engine.get_combatant(Fx.ENEMY_ID)
		foe.staggered_turns = 1
		var events: Array[Dictionary] = []
		engine._deal_damage(engine.get_combatant(0), foe, 100, "test", events)
		hits.append(int(Fx.first_of(events, "damage").amount))
	var base := 100 + _tuning.stagger_damage_taken_percent
	assert_eq(hits[0], CombatMath.percent_min1(100, base))
	assert_eq(hits[1], CombatMath.percent_min1(100, base + 25))


func test_crit_damage_grows_with_the_relic() -> void:
	var engine := _engine({Passive.CRIT_DAMAGE: 50})
	var plain := _engine({})
	var base := plain._crit_damage(plain.get_combatant(0), 100)
	assert_eq(base, CombatMath.percent_min1(100, plain.tuning.crit_damage_percent))
	assert_eq(engine._crit_damage(engine.get_combatant(0), 100),
			CombatMath.percent_min1(100, engine.tuning.crit_damage_percent + 50))


func test_a_perfect_parry_heals_with_still_water() -> void:
	var hurt: Array[int] = [50, 50, 50]
	var engine := _engine({Passive.PARRY_HEAL: 3}, {}, hurt)
	var target := int((engine.sequence.prompts as Array)[0].character)
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY]]))
	var healed := Fx.first_of(events, "healed")
	assert_eq(int(healed.target), target)
	assert_eq(int(healed.amount), 3, "3% of 100 max HP")
	var plain := _engine({}, {}, hurt)
	assert_eq(Fx.of_type(plain.submit(Fx.resolve_now(plain, [[0, PARRY]])), "healed").size(), 0)


func test_a_won_fight_heals_the_wreath_wearer() -> void:
	var encounter := load("res://data/encounters/husk_fight.tres") as EncounterData
	var left: Array[int] = []
	var max_hp := 0
	for wear: bool in [false, true]:
		var run := RunState.begin(_data, Fx.all_slots(_tuning), 7)
		if wear:
			run.wear(0, 0, _piece("victors_wreath"))
		var low: Array[int] = [10, 10, 10]
		run.finish_fight(RunState.VICTORY, low, encounter)
		left.append(run.hp[0])
		max_hp = run.max_hp(0)
	assert_eq(left[1] - left[0], CombatMath.percent_min1(max_hp, 10))
