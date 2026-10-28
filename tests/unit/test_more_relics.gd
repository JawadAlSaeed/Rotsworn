extends GutTest
## Phase 20 (card #242, DESIGN.md 8.17): 16 more Relics, eight of them with new effects; 63 in all
## since phase 27 (DESIGN.md 8.25). The shipped data, each effect in the engine or the run, and run
## fights that drop no Relics (DESIGN.md 8.24; the old drop lists stay as data, unused).

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const RUN_PATH := "res://data/runs/rotten_road.tres"
const PARRY: int = Defense.Outcome.PARRY
const SLOW_ENEMY: int = 10
const NEW_IDS: Array[String] = ["brimming_cup", "reapers_coin", "first_light", "mossbed",
	"breakers_maul", "butchers_edge", "still_water", "bramble_coat", "fox_step", "marrow_charm", "bone_whistle",
	"tallow_candle", "hollow_drum", "sour_milk", "crown_of_thorns"]

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
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

## The monsters' drop lists are kept as data though runs no longer roll them (DESIGN.md 8.24); since
## phase 27 they name no cut Relic, and the 17 new Relics are on none (DESIGN.md 8.25).
func test_sixty_three_relics_ship_and_the_drop_lists_name_only_shipped_ones() -> void:
	var shipped := load(RUN_PATH) as RunData
	assert_eq(shipped.gear.size(), 63)
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
	for id: Variant in dropped:
		assert_true(ids.has(String(id)), "%s on a drop list ships" % id)
	for id: String in NEW_IDS:
		assert_true(ids.has(id), "%s ships" % id)


func test_the_new_relics_say_what_they_do_and_have_no_stat_line() -> void:
	var shipped := load(RUN_PATH) as RunData
	for item: GearData in shipped.gear:
		if not NEW_IDS.has(item.id):
			continue
		assert_false(item.description.is_empty(), item.id)
		assert_false(GearData.effect_text(item.effect, item.amount).is_empty(), item.id + " has an effect line")
		assert_false("stat_points" in item, "no stat line since phase 27 (DESIGN.md 8.25)")


func test_won_run_fights_drop_no_relics() -> void:
	var run := RunState.begin(load(RUN_PATH) as RunData, Fx.run_tuning(_tuning), 7)
	run.go(run.choices()[0])
	var husk := load("res://data/encounters/husk_fight.tres") as EncounterData
	var guard := load("res://data/encounters/guard_gorged_one.tres") as EncounterData
	for encounter: EncounterData in [husk, guard, run.final_encounter()]:
		var got := run.finish_fight(RunState.VICTORY, run.hp.duplicate(), encounter)
		assert_false(got.has("relics"), "%s: no drops to hand out" % encounter.id)
	assert_true(run.relics.is_empty(), "Relics come from Elite stops, bosses, chests and shops only")
	assert_false("relic_drop_percent" in run.tuning, "the drop chance is gone")


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
	assert_eq(hits[1], CombatMath.percent_min1(100, CombatMath.percent(base, 125)), "a multiplier (DESIGN.md 8.25)")


func test_crit_damage_grows_with_the_relic() -> void:
	var engine := _engine({Passive.CRIT_DAMAGE: 50})
	var plain := _engine({})
	var base := plain._crit_damage(plain.get_combatant(0), 100)
	assert_eq(base, CombatMath.percent_min1(100, plain.tuning.crit_damage_percent))
	assert_eq(engine._crit_damage(engine.get_combatant(0), 100),
			CombatMath.percent_min1(100, CombatMath.percent(engine.tuning.crit_damage_percent, 150)), "a multiplier")


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

