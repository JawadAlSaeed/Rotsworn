extends GutTest
## Run (DESIGN.md 2.13): a perfect press on the Run ring takes that hero out of the fight; the
## fight ends as "escaped" once every standing hero ran. Anything else only costs the turn.
## Bosses (the run's final fight is one) cannot be run from. An escape keeps the run's HP and
## gives nothing.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const RUN_PATH := "res://data/runs/rotten_road.tres"


## A started fight where the party acts first, with Run available.
func _engine(can_run: bool = true) -> CombatEngine:
	var setup := Fx.kit_setup([], [Fx.attack("swipe", [Fx.hit(900)])], {"enemy_speed": 10})
	setup.run_ability = load(CombatSetup.RUN_ABILITY_PATH) as AbilityData
	setup.can_run = can_run
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


func test_a_perfect_press_takes_only_that_hero_out() -> void:
	var engine := _engine()
	assert_eq(engine.phase, CombatEngine.Phase.AWAITING_ACTION)
	var actor := engine.active_actor
	var used := engine.submit(Fx.use(engine, "run"))
	assert_eq(Fx.first_of(used, "timed_sequence_declared").get("kind"), CombatEngine.SEQUENCE_SKILL)
	var events := engine.submit(Fx.resolve_now(engine, [[0, Defense.Outcome.PRESS_PERFECT]]))
	assert_eq(Fx.first_of(events, "escaped").get("character"), actor)
	assert_true(Fx.first_of(events, "combat_ended").is_empty(), "the others fight on")
	assert_true(engine.get_combatant(actor).escaped)
	assert_false(engine.living_party_ids().has(actor), "out of the fight")
	assert_false(engine.downed_party_ids().has(actor), "not downed: cannot be revived")
	assert_false(engine.preview_turn_order(8).has(actor), "never gets another turn")


func test_the_fight_ends_when_every_standing_hero_ran() -> void:
	var engine := _engine()
	var ended: Dictionary = {}
	for i: int in 3:
		assert_eq(engine.phase, CombatEngine.Phase.AWAITING_ACTION, "a hero's turn (%d)" % i)
		engine.submit(Fx.use(engine, "run"))
		ended = Fx.first_of(engine.submit(Fx.resolve_now(engine, [[0, Defense.Outcome.PRESS_PERFECT]])), "combat_ended")
	assert_eq(ended.get("result"), "escaped")
	assert_eq(engine.result, "escaped")
	assert_eq(engine.phase, CombatEngine.Phase.ENDED)


func test_the_run_ring_has_a_wider_perfect_window() -> void:
	var engine := _engine()
	var used := engine.submit(Fx.use(engine, "run"))
	var prompt: Dictionary = (Fx.first_of(used, "timed_sequence_declared").prompts as Array)[0]
	var edges: Array = prompt.windows[Defense.Outcome.PRESS_PERFECT]
	var run := load(CombatSetup.RUN_ABILITY_PATH) as AbilityData
	var tuning := Tuning.new()
	var wanted := mini(CombatMath.percent(tuning.skill_perfect_window_ms, run.perfect_window_percent), tuning.skill_press_window_ms)
	assert_gt(run.perfect_window_percent, 100, "Run is a little easier than a skill")
	assert_eq((int(edges[1]) - int(edges[0])) / 1000, wanted)


func test_a_good_or_missed_press_only_loses_the_turn() -> void:
	for outcome: int in [Defense.Outcome.PRESS, Defense.Outcome.NONE]:
		var engine := _engine()
		var actor := engine.active_actor
		engine.submit(Fx.use(engine, "run"))
		var events := engine.submit(Fx.resolve_now(engine, [[0, outcome]]))
		assert_true(Fx.first_of(events, "combat_ended").is_empty(), "no escape on outcome %d" % outcome)
		assert_eq(Fx.first_of(events, "turn_ended").get("actor"), actor, "the turn is over")
		assert_ne(engine.phase, CombatEngine.Phase.ENDED)
		assert_eq(Fx.of_type(events, "damage").size(), 0, "running deals no damage")


func test_no_run_when_the_fight_does_not_allow_it() -> void:
	var engine := _engine(false)
	var events := engine.submit(Fx.use(engine, "run"))
	assert_eq(Fx.first_of(events, "command_rejected").get("reason"), "unknown_ability")


func test_bosses_cannot_be_run_from() -> void:
	var tuning := Tuning.new()
	for case: Array in [["husk_fight", true], ["final_stand", true], ["hollow_king", false]]:
		var encounter := load("res://data/encounters/%s.tres" % case[0]) as EncounterData
		var setup := CombatSetup.from_encounter(encounter, tuning, 1)
		assert_eq(setup.can_run, bool(case[1]), String(case[0]))


func test_an_escape_keeps_hp_and_gives_nothing() -> void:
	var run := RunState.begin(load(RUN_PATH) as RunData, Fx.shipped_tuning(), 1)
	var gold := run.gold
	var hp: Array[int] = []
	for slot: int in run.party_size():
		hp.append(maxi(1, run.max_hp(slot) / 2))
	var reward := run.finish_fight(RunState.ESCAPED, hp, null)
	assert_eq(reward, {"gold": 0, "xp": 0, "levels": 0})
	assert_eq(run.hp, hp, "HP carries on")
	assert_eq(run.gold, gold)
	assert_false(run.is_over(), "the run goes on")
