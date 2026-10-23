extends GutTest
## The defence streak (card #300): the engine counts the party's perfect parries and jumps in a row
## across a fight (a dodge keeps it, a hit taken ends it), fills the team gauge at every
## defence_streak_step, keeps it in snapshots, and the mirror follows it from the events alone.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const NONE: int = Defense.Outcome.NONE
const DODGE: int = Defense.Outcome.DODGE
const PARRY: int = Defense.Outcome.PARRY


## A three-hit string on one hero, the foe acting first.
func _string_attack() -> EnemyAttackData:
	return Fx.attack("flurry", [Fx.hit(900, Fx.NORMAL, 20), Fx.hit(1200, Fx.NORMAL, 20), Fx.hit(1500, Fx.NORMAL, 20)])


func _engine(step: int = 2, gauge: int = 10) -> CombatEngine:
	var tuning := Fx.no_crit_tuning()
	tuning.defence_streak_step = step
	tuning.defence_streak_gauge = gauge
	var engine := Fx.started([_string_attack()], {"tuning": tuning})
	assert_eq(engine.phase, CombatEngine.Phase.AWAITING_TIMING, "the foe opens with its string")
	return engine


func _streak_events(events: Array[Dictionary]) -> Array[Dictionary]:
	return Fx.of_type(events, "defence_streak")


func test_parries_count_up_and_a_step_fills_the_gauge() -> void:
	var engine := _engine()
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY], [1, PARRY], [2, PARRY]]))
	var streak := _streak_events(events)
	assert_eq(streak.size(), 3)
	assert_eq(streak.map(func(e: Dictionary) -> int: return int(e.value)), [1, 2, 3])
	assert_eq(streak.map(func(e: Dictionary) -> bool: return bool(e.milestone)), [false, true, false],
			"every 2nd in a row is a step")
	assert_eq(engine.defence_streak, 3)
	assert_eq(engine.best_defence_streak, 3)
	var at := events.find(streak[1])
	assert_eq(String(events[at + 1].type), "team_gauge", "the step's gauge follows its streak event")
	assert_eq(int(events[at + 1].delta), 10)
	assert_eq(engine.team_gauge, 10)


func test_a_dodge_keeps_the_streak_and_a_hit_ends_it() -> void:
	var engine := _engine(5)
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY], [1, DODGE], [2, NONE]]))
	var streak := _streak_events(events)
	assert_eq(streak.size(), 2, "the dodge adds nothing and sends nothing")
	assert_eq(int(streak[0].value), 1)
	assert_eq(int(streak[1].value), 0, "the hit ends it")
	assert_eq(int(streak[1].lost), 1, "and says how long it was")
	assert_eq(int(streak[1].best), 1)
	assert_eq(engine.defence_streak, 0)
	assert_eq(engine.best_defence_streak, 1)


func test_a_hit_with_no_streak_sends_nothing() -> void:
	var engine := _engine()
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE], [1, NONE], [2, NONE]]))
	assert_true(_streak_events(events).is_empty())


func test_no_gauge_when_turned_off() -> void:
	var engine := _engine(2, 0)
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY], [1, PARRY], [2, PARRY]]))
	assert_true(Fx.of_type(events, "team_gauge").is_empty())
	assert_eq(engine.team_gauge, 0)


func test_snapshot_keeps_the_streak() -> void:
	var engine := _engine(5)
	engine.submit(Fx.resolve_now(engine, [[0, PARRY], [1, PARRY], [2, PARRY]]))
	var snap := engine.snapshot()
	assert_eq(int(snap.defence_streak), 3)
	var restored := CombatEngine.restore(Fx.setup([_string_attack()]), snap)
	assert_eq(restored.defence_streak, 3)
	assert_eq(restored.best_defence_streak, 3)
	var old := snap.duplicate(true)
	old.erase("defence_streak")
	old.erase("best_defence_streak")
	assert_eq(CombatEngine.restore(Fx.setup([_string_attack()]), old).defence_streak, 0, "an older snapshot has none")


func test_the_mirror_follows_the_engine() -> void:
	var tuning := Fx.no_crit_tuning()
	tuning.defence_streak_step = 2
	var engine := CombatEngine.new(Fx.setup([_string_attack()], {"tuning": tuning}))
	var mirror := CombatMirror.new()
	for ev: Dictionary in engine.start():
		mirror.apply(ev)
	for ev: Dictionary in engine.submit(Fx.resolve_now(engine, [[0, PARRY], [1, PARRY], [2, NONE]])):
		mirror.apply(ev)
	assert_eq(mirror.defence_streak, 0)
	assert_eq(mirror.best_defence_streak, 2)
	assert_eq(mirror.projection(), CombatMirror.project_snapshot(engine.snapshot()))
