extends GutTest
## Cards #187 and #188 (DESIGN.md 2.4, 3.8, 8.3): forced-choice hits (REND: parry only, SWEEP: dodge
## only) in hard fights, and enemy attacks that speed up with depth, elites, guards, bosses and
## phase two. Windows, judging, the engine, the online referee, the run and the shipped data.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const NONE: int = Defense.Outcome.NONE
const DODGE: int = Defense.Outcome.DODGE
const PARRY: int = Defense.Outcome.PARRY
const JUMP: int = Defense.Outcome.JUMP
const NORMAL: int = AttackHitData.Kind.NORMAL
const GROUND: int = AttackHitData.Kind.GROUND
const REND: int = AttackHitData.Kind.REND
const SWEEP: int = AttackHitData.Kind.SWEEP
const FOE: int = Fx.ENEMY_ID
const MS: int = 1000
const PEER_A: int = 2
const PEER_B: int = 3
## A forced hit needs at least this long after the hit before it (authored ms): time to see its
## colour and change buttons. Two forced hits in a row are never closer than this either.
const FORCED_MIN_GAP_MS: int = 300
## A feint inside a string needs this long after the hit before it, or its false start eats that
## hit's contact pose (approach + combat_visuals feint_lead_ms, 350, at tempo 100).
const FEINT_MIN_GAP_MS: int = 550
const ENCOUNTER_DIR := "res://data/encounters"
const RUN_PATH := "res://data/runs/rotten_road.tres"

var _tuning := Tuning.new()


func _forced(at_ms: int, kind: int, feint: bool = false) -> AttackHitData:
	var hit := Fx.hit(at_ms)
	hit.forced_kind = kind
	hit.forced_feint = feint
	return hit


## A started fight against one enemy using `attacks`; `hard` = an elite, guard or boss fight.
func _engine(attacks: Array, hard: bool, options: Dictionary = {}) -> CombatEngine:
	var setup := Fx.setup(attacks, options)
	setup.forced_hits = hard
	setup.attack_tempo_percent = int(options.get("tempo", 0))
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


func _judge(kind: int) -> DefenseJudge:
	var judge := DefenseJudge.new(300, 0, _tuning.press_reach_back_max_ms, _tuning.late_press_report_ms)
	judge.set_prompts([{"idx": 0, "hit": 0, "character": 0, "at_ms": 1000, "kind": kind,
			"windows": Defense.build_windows(kind, _tuning), "perfect": Defense.perfect_outcomes(kind)}])
	return judge


# --- windows ----------------------------------------------------------------------------------

func test_each_forced_kind_takes_one_button_at_its_usual_window() -> void:
	var parry := _tuning.window_edges_us(_tuning.parry_window_ms)
	var dodge := _tuning.window_edges_us(_tuning.dodge_window_ms)
	assert_eq(Defense.build_windows(REND, _tuning), {PARRY: [parry.x, parry.y]}, "a rend: parry only")
	assert_eq(Defense.build_windows(SWEEP, _tuning), {DODGE: [dodge.x, dodge.y]}, "a sweep: dodge only")
	assert_eq(Defense.perfect_outcomes(REND), [PARRY] as Array[int], "a parried rend counts for a counter")
	assert_eq(Defense.perfect_outcomes(SWEEP), [] as Array[int], "a sweep never counts for a counter")
	assert_eq(Defense.best_outcome(NORMAL), PARRY)
	assert_eq(Defense.best_outcome(REND), PARRY)
	assert_eq(Defense.best_outcome(SWEEP), DODGE)
	assert_eq(Defense.best_outcome(GROUND), JUMP)
	assert_eq(Defense.sanitize(DODGE, Defense.build_windows(REND, _tuning)), NONE)
	assert_eq(Defense.sanitize(PARRY, Defense.build_windows(SWEEP, _tuning)), NONE)


func test_the_judge_takes_the_right_button_and_calls_the_wrong_one_wrong() -> void:
	for case: Array in [[REND, PARRY, [DODGE, JUMP]], [SWEEP, DODGE, [PARRY, JUMP]]]:
		var kind: int = case[0]
		var right: int = case[1]
		var ok := _judge(kind).press(right, 1000 * MS)
		assert_eq(int(ok.result), DefenseJudge.Result.SUCCESS, "%d: the right button works" % kind)
		assert_eq(int(ok.outcome), right)
		for wrong: int in case[2]:
			var judge := _judge(kind)
			var report := judge.press(wrong, 1000 * MS)
			assert_eq(int(report.result), DefenseJudge.Result.WHIFF, "%d: button %d is a whiff" % [kind, wrong])
			assert_eq(int(report.reason), DefenseJudge.Reason.WRONG_ACTION, "and it says why")
			assert_true(judge.is_locked_out(1000 * MS + 1), "a wrong button starts the lockout")
			judge.advance(2000 * MS)
			assert_eq(int((judge.pop_ready()[0] as Dictionary).outcome), NONE, "the hit lands")


# --- the engine -------------------------------------------------------------------------------

func test_an_ordinary_fight_keeps_normal_hits_normal() -> void:
	var attack := Fx.attack("rake", [_forced(900, REND, true), Fx.hit(1200)])
	var engine := _engine([attack], false)
	var hits: Array = engine.sequence.hits
	assert_eq(int(hits[0].kind), NORMAL, "a forced kind only shows in a hard fight")
	assert_false(bool(hits[0].feint), "and so does a forced feint")
	assert_true((engine.sequence.prompts[0].windows as Dictionary).has(DODGE))


func test_a_hard_fight_declares_the_forced_kinds_and_feints() -> void:
	var attack := Fx.attack("rake", [_forced(900, REND, true), Fx.hit(1200), _forced(1600, SWEEP)])
	var setup := Fx.setup([attack])
	setup.forced_hits = true
	var engine := CombatEngine.new(setup)
	var intent := Fx.first_of(engine.start(), "intent")
	assert_eq(intent.kinds, [REND, NORMAL, SWEEP], "the intent shows the kinds")
	assert_eq(intent.feints, [true, false, false])
	var hits: Array = engine.sequence.hits
	assert_eq([int(hits[0].kind), int(hits[1].kind), int(hits[2].kind)], [REND, NORMAL, SWEEP])
	assert_true(bool(hits[0].feint))
	var prompts: Array = engine.sequence.prompts
	assert_eq((prompts[0].windows as Dictionary).keys(), [PARRY])
	assert_eq((prompts[2].windows as Dictionary).keys(), [DODGE])


func test_an_enemy_marked_forced_hits_uses_them_in_any_fight() -> void:
	var setup := Fx.setup([Fx.attack("rake", [_forced(900, SWEEP)])])
	setup.enemies[0].forced_hits = true
	var engine := CombatEngine.new(setup)
	engine.start()
	assert_eq(int(engine.sequence.hits[0].kind), SWEEP, "the deep variants always use them")


func test_a_parried_rend_counters_and_a_dodged_one_lands() -> void:
	var attack := Fx.attack("rend", [_forced(900, REND)])
	var dodged := _engine([attack], true)
	var events := dodged.submit(Fx.resolve_now(dodged, [[0, DODGE]]))
	var resolved := Fx.first_of(events, "prompt_resolved")
	assert_eq(int(resolved.outcome), NONE, "the engine refuses a dodge on a rend")
	assert_gt(int(resolved.damage), 0, "the hit lands")
	var parried := _engine([attack], true)
	events = parried.submit(Fx.resolve_now(parried, [[0, PARRY]]))
	resolved = Fx.first_of(events, "prompt_resolved")
	assert_eq(int(resolved.outcome), PARRY)
	assert_true(bool(resolved.perfect), "a parried rend is perfect")
	assert_eq(Fx.of_type(events, "counter").size(), 1, "and earns the counter")


func test_a_dodged_sweep_is_safe_but_never_countered() -> void:
	var attack := Fx.attack("sweep", [_forced(900, SWEEP)])
	var parried := _engine([attack], true)
	var resolved := Fx.first_of(parried.submit(Fx.resolve_now(parried, [[0, PARRY]])), "prompt_resolved")
	assert_eq(int(resolved.outcome), NONE, "a parry does not stop a sweep")
	assert_gt(int(resolved.damage), 0)
	var dodged := _engine([attack], true)
	var events := dodged.submit(Fx.resolve_now(dodged, [[0, DODGE]]))
	resolved = Fx.first_of(events, "prompt_resolved")
	assert_eq(int(resolved.outcome), DODGE)
	assert_eq(int(resolved.damage), 0, "a dodge avoids it")
	assert_false(bool(resolved.perfect))
	assert_eq(Fx.of_type(events, "counter").size(), 0, "a string with a sweep is never countered")


func test_a_rend_string_counts_as_parries_for_the_mixed_bonus() -> void:
	var attack := Fx.attack("mix", [_forced(900, REND), Fx.hit(1500, GROUND, 100, 400)])
	var engine := _engine([attack], true)
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY], [1, JUMP]]))
	var counter := Fx.first_of(events, "counter")
	assert_true(bool(counter.mixed), "a parried rend and a jump make a mixed string")


func test_setup_refuses_a_forced_kind_that_is_not_rend_or_sweep() -> void:
	var bad := Fx.hit(900)
	bad.forced_kind = GROUND
	assert_false(Fx.setup([Fx.attack("bad", [bad])]).validate().is_empty())
	var ground := Fx.hit(900, GROUND)
	ground.forced_kind = REND
	assert_false(Fx.setup([Fx.attack("bad", [ground])]).validate().is_empty(), "only a normal hit is forced")
	assert_true(Fx.setup([Fx.attack("ok", [_forced(900, SWEEP)])]).validate().is_empty())


# --- tempo (card #188) ------------------------------------------------------------------------

func test_the_setup_tempo_shrinks_the_declared_hits() -> void:
	var attack := Fx.attack("pair", [Fx.hit(900), Fx.hit(1300, NORMAL, 100, 250)])
	var plain := _engine([attack], false)
	assert_eq(int(plain.sequence.hits[0].at_ms), 900, "0 = tuning's tempo (100)")
	var setup := Fx.setup([attack])
	setup.attack_tempo_percent = 80
	var engine := CombatEngine.new(setup)
	var intent := Fx.first_of(engine.start(), "intent")
	assert_eq(intent.times, [720, 1040], "the intent's rhythm is the faster one")
	var hits: Array = engine.sequence.hits
	assert_eq([int(hits[0].at_ms), int(hits[1].at_ms)], [720, 1040])
	assert_eq([int(hits[0].approach_ms), int(hits[1].approach_ms)], [160, 200], "the lunges are quicker too")
	assert_eq(int(engine.sequence.prompts[0].at_ms), 720, "the judged impact moves with it")


func test_the_tempo_never_goes_under_the_floor() -> void:
	var attack := Fx.attack("one", [Fx.hit(1000)])
	var engine := _engine([attack], false, {"tempo": 40})
	assert_eq(int(engine.sequence.hits[0].at_ms), CombatMath.percent(1000, _tuning.attack_tempo_floor_percent))
	assert_eq(CombatSetup.tempo_floor(_tuning), 70)


func _boss_setup(tempo: int) -> CombatSetup:
	var setup := Fx.setup([Fx.attack("swipe", [Fx.hit(1000)])])
	setup.enemies[0].phase_two_hp_percent = 99
	setup.enemies[0].phase_two_attacks.assign([Fx.attack("rage", [Fx.hit(1000), Fx.hit(1500)])])
	setup.enemies[0].phase_two_speed = 300
	setup.enemies[0].phase_two_tempo_percent = 80
	setup.attack_tempo_percent = tempo
	return setup


func test_phase_two_speeds_up_the_strings() -> void:
	var engine := CombatEngine.new(_boss_setup(90))
	engine.start()
	assert_eq(int(engine.sequence.hits[0].at_ms), 900, "phase one: the fight's tempo")
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY]]))
	assert_eq(Fx.of_type(events, "enemy_phase").size(), 1)
	var boss := engine.get_combatant(FOE)
	assert_eq(boss.tempo_percent, 80, "kept on the combatant")
	assert_eq(int(boss.to_dict().tempo_percent), 80, "and in its snapshot")
	assert_eq(Combatant.from_dict(boss.to_dict()).tempo_percent, 80)
	var expected := maxi(CombatMath.percent(90, 80), CombatSetup.tempo_floor(_tuning))
	assert_eq(String(engine.sequence.action), "rage")
	assert_eq(int(engine.sequence.hits[0].at_ms), CombatMath.percent(1000, expected), "phase two: 72% of authored")
	assert_eq(int(engine.sequence.hits[1].at_ms), CombatMath.percent(1500, expected))
	var floored := CombatEngine.new(_boss_setup(75))
	floored.start()
	floored.submit(Fx.resolve_now(floored, [[0, PARRY]]))
	assert_eq(int(floored.sequence.hits[0].at_ms), CombatMath.percent(1000, 70), "phase two stops at the floor")


func test_tempo_is_deterministic_and_survives_a_restore() -> void:
	var a := CombatEngine.new(_boss_setup(85))
	var b := CombatEngine.new(_boss_setup(85))
	assert_eq(a.start(), b.start())
	assert_eq(a.submit(Fx.resolve_now(a, [[0, PARRY]])), b.submit(Fx.resolve_now(b, [[0, PARRY]])), "same seed, same events")
	var restored := CombatEngine.restore(_boss_setup(85), a.snapshot())
	assert_eq(restored.get_combatant(FOE).tempo_percent, 80, "phase two's tempo comes back with the snapshot")
	assert_eq(restored.submit(Fx.resolve_now(restored, [[0, DODGE], [1, DODGE]])),
			a.submit(Fx.resolve_now(a, [[0, DODGE], [1, DODGE]])), "a restored fight goes on the same")


# --- the online referee -----------------------------------------------------------------------

func test_the_referee_accepts_the_right_button_and_refuses_the_wrong_one() -> void:
	var attack := Fx.attack("rake", [_forced(900, REND), _forced(1400, SWEEP)], Fx.PARTY)
	var engine := _engine([attack], true)
	var arbiter := DefenseArbiter.new(3000, 1500, 100)
	var owners: Dictionary = {}
	for p: Dictionary in engine.sequence.prompts:
		if int(p.character) == 1:
			owners[int(p.idx)] = PEER_A
		elif int(p.character) == 2:
			owners[int(p.idx)] = PEER_B
	var seq := int(engine.sequence.seq)
	arbiter.declare(seq, engine.sequence.prompts, owners, 700, 0)
	# Prompts: hit 0 (rend) 0-2, hit 1 (sweep) 3-5; character 1 has 1 and 4, character 2 has 2 and 5.
	var a := arbiter.accept(PEER_A, seq, [CombatCommands.prompt_result(1, PARRY, 0),
			CombatCommands.prompt_result(4, PARRY, 0)])
	assert_eq(a.size(), 2)
	assert_eq(int(a[0].outcome), PARRY, "a parry on a rend is accepted")
	assert_eq(int(a[1].outcome), NONE, "a parry on a sweep is refused: the hit lands")
	var b := arbiter.accept(PEER_B, seq, [CombatCommands.prompt_result(2, DODGE, 0),
			CombatCommands.prompt_result(5, DODGE, 0)])
	assert_eq(int(b[0].outcome), NONE, "a dodge on a rend is refused")
	assert_eq(int(b[1].outcome), DODGE, "a dodge on a sweep is accepted")


# --- the run ----------------------------------------------------------------------------------

func _run() -> RunState:
	return RunState.begin(load(RUN_PATH) as RunData, Tuning.new(), 5)


func test_hard_encounters_use_forced_hits() -> void:
	for id: String in ["elite_twin_husks", "guard_gorged_one", "hollow_king"]:
		var hard := load(ENCOUNTER_DIR.path_join(id + ".tres")) as EncounterData
		assert_true(CombatSetup.from_encounter(hard, _tuning, 1).forced_hits, id)
	var plain := load(ENCOUNTER_DIR.path_join("husk_fight.tres")) as EncounterData
	assert_false(CombatSetup.from_encounter(plain, _tuning, 1).forced_hits, "an ordinary fight (and the tutorial's)")


func test_enemies_get_faster_with_depth_elites_guards_and_bosses() -> void:
	var run := _run()
	var t := run.tuning
	var husk := load(ENCOUNTER_DIR.path_join("husk_fight.tres")) as EncounterData
	var elite := load(ENCOUNTER_DIR.path_join("elite_twin_husks.tres")) as EncounterData
	var guard := load(ENCOUNTER_DIR.path_join("guard_gorged_one.tres")) as EncounterData
	var boss := run.data.final_encounter
	run.go(run.choices()[0])
	assert_eq(run.enemy_tempo_percent(husk), t.attack_tempo_percent, "the first row plays as authored")
	while int(run.current().row) < 3:
		run.go(run.choices()[0])
	var row3 := t.attack_tempo_percent - 3 * t.run_enemy_tempo_row_percent
	assert_lt(row3, 100, "deeper is faster")
	assert_eq(run.enemy_tempo_percent(husk), row3)
	assert_eq(run.enemy_tempo_percent(elite), CombatMath.percent(row3, t.elite_tempo_percent))
	assert_eq(run.enemy_tempo_percent(guard), CombatMath.percent(row3, t.guard_tempo_percent))
	assert_eq(run.enemy_tempo_percent(boss), CombatMath.percent(row3, t.boss_tempo_percent))
	assert_lt(run.enemy_tempo_percent(elite), row3)
	assert_eq(run.fight_setup(elite, 4, CombatSetup.Opening.NORMAL).attack_tempo_percent,
			run.enemy_tempo_percent(elite), "the run fills the fight's tempo")
	t.run_enemy_tempo_row_percent = 10
	assert_eq(run.enemy_tempo_percent(boss), CombatSetup.tempo_floor(t), "never under the floor")


func test_shipped_tempo_numbers_stay_fair() -> void:
	var t := Fx.shipped_tuning()
	assert_gte(t.attack_tempo_floor_percent, 65, "the windows do not shrink, so the strings must stay readable")
	assert_lte(t.attack_tempo_floor_percent, 100)
	assert_between(t.run_enemy_tempo_row_percent, 1, 3, "a small step per row")
	for pct: int in [t.elite_tempo_percent, t.guard_tempo_percent, t.boss_tempo_percent]:
		assert_between(pct, 80, 100)


# --- the shipped data -------------------------------------------------------------------------

func _attacks() -> Dictionary:
	var by_id: Dictionary = {}
	var dir := DirAccess.open("res://data/enemy_attacks")
	for file: String in dir.get_files():
		if file.ends_with(".tres"):
			var attack := load("res://data/enemy_attacks".path_join(file)) as EnemyAttackData
			by_id[attack.id] = attack
	return by_id


## Attack ids that hard fights (elite, guard, boss) and forced_hits enemies use.
func _hard_attack_ids() -> Dictionary:
	var ids: Dictionary = {}
	var dir := DirAccess.open(ENCOUNTER_DIR)
	for file: String in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var encounter := load(ENCOUNTER_DIR.path_join(file)) as EncounterData
		var hard := encounter.elite or encounter.boss or encounter.mini_boss
		for enemy: EnemyData in encounter.enemies:
			if hard or enemy.forced_hits:
				for attack: EnemyAttackData in enemy.attacks + enemy.phase_two_attacks:
					ids[attack.id] = true
	return ids


func test_every_forced_hit_has_a_fair_gap() -> void:
	var checked := 0
	for attack: EnemyAttackData in _attacks().values():
		var prev_forced := false
		for i: int in attack.hits.size():
			var hit := attack.hits[i]
			var label := "%s hit %d" % [attack.id, i]
			var forced := AttackHitData.is_forced(hit.kind_in(true))
			if hit.forced_kind != NORMAL:
				assert_eq(hit.kind, NORMAL, label + ": only a normal hit is forced")
				assert_null(hit.projectile, label + ": a throw is never forced")
			if forced and i > 0:
				var gap := hit.impact_ms - attack.hits[i - 1].impact_ms
				assert_gte(gap, FORCED_MIN_GAP_MS, label + ": time to read the kind and change buttons")
				assert_false(prev_forced and gap <= 250, label + ": never two forced kinds in a row in 250 ms")
				checked += 1
			if hit.feint_in(true) and i > 0:
				assert_gte(hit.impact_ms - attack.hits[i - 1].impact_ms, FEINT_MIN_GAP_MS,
						label + ": a feint inside a string needs room for its false start")
			prev_forced = forced
	assert_gt(checked, 10, "the shipped strings hold forced hits")


func test_forced_hits_are_used_sparingly_and_only_where_the_fight_is_hard() -> void:
	var attacks := _attacks()
	var hard := _hard_attack_ids()
	var strikes := 0
	var forced := 0
	for id: String in attacks:
		var attack: EnemyAttackData = attacks[id]
		for hit: AttackHitData in attack.hits:
			if hit.projectile != null or hit.kind != NORMAL:
				continue
			if AttackHitData.is_forced(hit.forced_kind):
				assert_true(hard.has(id), "%s: a forced hit only matters in a hard fight" % id)
			if hard.has(id):
				strikes += 1
				forced += 1 if AttackHitData.is_forced(hit.forced_kind) else 0
	@warning_ignore("integer_division")
	var share := forced * 100 / maxi(1, strikes)
	assert_between(share, 15, 40, "about one hit in four (%d of %d)" % [forced, strikes])


func test_ordinary_first_zone_fights_and_the_tutorial_have_no_forced_hits() -> void:
	var dir := DirAccess.open(ENCOUNTER_DIR)
	var checked := 0
	for file: String in dir.get_files():
		if not file.ends_with(".tres") or file.begins_with("deep_"):
			continue
		var encounter := load(ENCOUNTER_DIR.path_join(file)) as EncounterData
		if encounter.elite or encounter.boss or encounter.mini_boss:
			continue
		for enemy: EnemyData in encounter.enemies:
			assert_false(enemy.forced_hits, "%s: %s fights as authored" % [encounter.id, enemy.id])
		checked += 1
	assert_gt(checked, 5)
	var tutorial := load("res://data/tutorial/tutorial.tres") as TutorialData
	assert_false(CombatSetup.from_encounter(tutorial.encounter, _tuning, 1).forced_hits, "the tutorial fight")


func test_every_hard_string_has_a_feint() -> void:
	var attacks := _attacks()
	for id: String in _hard_attack_ids():
		var attack: EnemyAttackData = attacks[id]
		var lunges := 0
		var feints := 0
		for hit: AttackHitData in attack.hits:
			if hit.kind != GROUND and hit.projectile == null:
				lunges += 1
				feints += 1 if hit.feint_in(true) else 0
		if lunges >= 2:
			assert_gt(feints, 0, "%s: a hard fight's string fakes out somewhere" % id)


func test_no_shipped_string_beats_a_strict_metronome() -> void:
	# Review combat-feel #4: three or more evenly spaced hits that one button answers let one steady
	# tap rhythm beat them (a string mixing ground and normal hits needs two buttons anyway).
	for attack: EnemyAttackData in _attacks().values():
		if attack.hits.size() < 3:
			continue
		var kinds: Dictionary = {}
		for hit: AttackHitData in attack.hits:
			kinds[hit.kind] = true
		if kinds.size() > 1:
			continue
		var gaps: Dictionary = {}
		for i: int in range(1, attack.hits.size()):
			gaps[attack.hits[i].impact_ms - attack.hits[i - 1].impact_ms] = true
		assert_gt(gaps.size(), 1, "%s: the gaps are not all the same" % attack.id)
