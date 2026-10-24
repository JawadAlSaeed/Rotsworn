extends GutTest
## Wind-up attacks charge in (DESIGN.md 3.12, card #310): an attacker that runs up skips the run when
## its attack's first hit winds up long enough. It winds up near home, its first lunge charges all
## the way to the contact point and still reaches it exactly at impact, and it stays close through
## the rest of the string. The attack clock, the impact times and every beat's timing stay exactly
## as they were: only where the enemy stands changes. Quick openers keep the phase 23 run-up.
## Uses the default CombatVisuals and Tuning so edits to the .tres files never break it.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const NEAR: float = 0.8
const LATENCY_MS: int = 30
const EPS: float = 0.0001

var _visuals := CombatVisuals.new()


func before_each() -> void:
	_visuals = CombatVisuals.new()


func _hit(at_ms: float, approach_ms: float = 400.0, kind: int = AttackHitData.Kind.NORMAL) -> Dictionary:
	return {"at_ms": at_ms, "kind": kind, "approach_ms": approach_ms, "feint": false, "close_ms": 120.0}


func _attack(id: String) -> EnemyAttackData:
	return load("res://data/enemy_attacks/%s.tres" % id) as EnemyAttackData


func _enemy(id: String) -> EnemyData:
	return load("res://data/enemies/%s.tres" % id) as EnemyData


## The engine's declared hits of a shipped attack, with close times and the attack's hit data.
func _declared(attack: EnemyAttackData, tuning: Tuning = null) -> Dictionary:
	var options := {} if tuning == null else {"tuning": tuning}
	var declared := Fx.declared_attack(attack, options)
	var hits := EnemyChoreography.with_close_times(declared.hits as Array, declared.prompts as Array, LATENCY_MS)
	EnemyChoreography.add_hit_data(hits, attack)
	return {"hits": hits, "prompts": declared.prompts}


func test_wind_up_attacks_charge_and_quick_openers_run_up() -> void:
	var charging := {"bloat": "bloat_belly_slam", "barrow_brute": "brute_maul", "rot_hyena": "hyena_pounce"}
	for enemy_id: String in charging:
		var attack := _attack(charging[enemy_id])
		var hits: Array = _declared(attack).hits
		assert_true(EnemyChoreography.charges(attack, _enemy(enemy_id), hits, _visuals), attack.id)
		assert_false(EnemyChoreography.runs_up(attack, _enemy(enemy_id), hits, _visuals), attack.id + ": no run first")
	# The approved run-ups stay: the Husk's swipe and the King's chop.
	var running := {"rotten_husk": "husk_swipe", "hollow_king": "king_cleave"}
	for enemy_id: String in running:
		var attack := _attack(running[enemy_id])
		var hits: Array = _declared(attack).hits
		assert_true(EnemyChoreography.runs_up(attack, _enemy(enemy_id), hits, _visuals), attack.id)
		assert_false(EnemyChoreography.charges(attack, _enemy(enemy_id), hits, _visuals), attack.id + ": no charge")
	# Slams, throws and enemies that never run stay home.
	var bloat := _enemy("bloat")
	for id: String in ["bloat_quake", "bloat_bile_spit"]:
		var hits: Array = _declared(_attack(id)).hits
		assert_false(EnemyChoreography.charges(_attack(id), bloat, hits, _visuals), id)
		assert_false(EnemyChoreography.runs_up(_attack(id), bloat, hits, _visuals), id)
	var walker := bloat.duplicate() as EnemyData
	walker.runs_up = false
	var slam := _attack("bloat_belly_slam")
	assert_false(EnemyChoreography.charges(slam, walker, _declared(slam).hits as Array, _visuals), "not a runner")


func test_the_choice_follows_the_authored_wind_up_only() -> void:
	var slam := _attack("bloat_belly_slam")
	assert_eq(EnemyChoreography.windup_ms(slam, _declared(slam).hits as Array), 1200, "impact 1600 - approach 400")
	# A faster attack tempo (deeper in a run) shortens the declared wind-up, never the choice.
	var fast := Fx.no_crit_tuning()
	fast.attack_tempo_percent = 70
	var quick: Array = _declared(slam, fast).hits
	assert_lt(float((quick[0] as Dictionary).at_ms), 1600.0, "the tempo applies")
	assert_true(EnemyChoreography.charges(slam, _enemy("bloat"), quick, _visuals), "still a charge")
	var v := CombatVisuals.new()
	v.charge_windup_min_ms = 1300
	assert_false(EnemyChoreography.charges(slam, _enemy("bloat"), quick, v), "under the threshold: runs up")
	assert_true(EnemyChoreography.runs_up(slam, _enemy("bloat"), quick, v))


func test_a_charge_keeps_the_plain_lead_in() -> void:
	var tuning := Tuning.new()
	tuning.attack_lead_in_ms = 700
	tuning.run_up_ms = 450
	var slam := _attack("bloat_belly_slam")
	var runs := EnemyChoreography.runs_up(slam, _enemy("bloat"), _declared(slam).hits as Array, _visuals)
	assert_eq(EnemyChoreography.lead_in_ms(tuning, runs), 700, "nothing runs before the clock")
	var swipe := _attack("husk_swipe")
	runs = EnemyChoreography.runs_up(swipe, _enemy("rotten_husk"), _declared(swipe).hits as Array, _visuals)
	assert_eq(EnemyChoreography.lead_in_ms(tuning, runs), 1150, "a run-up still adds its run")


func test_a_charge_winds_up_near_home_and_arrives_at_impact() -> void:
	_visuals.charge_windup_share = 0.15
	_visuals.enemy_windup_coil_ms = 240
	var hits := [_hit(1600.0)]
	assert_almost_eq(float(EnemyChoreography.sample(hits, -1.0, _visuals, NEAR, true).approach), 0.0, EPS,
			"home before the clock")
	var first := EnemyChoreography.sample(hits, 0.0, _visuals, NEAR, true)
	assert_eq(int(first.beat), EnemyChoreography.Beat.WINDUP)
	assert_almost_eq(float(first.approach), 0.0, EPS, "the wind-up starts at home")
	var coiled := EnemyChoreography.sample(hits, 240.0, _visuals, NEAR, true)
	assert_almost_eq(float(coiled.approach), 0.15, EPS, "a short step out during the coil")
	var late := EnemyChoreography.sample(hits, 1199.0, _visuals, NEAR, true)
	assert_eq(int(late.beat), EnemyChoreography.Beat.WINDUP)
	assert_almost_eq(float(late.approach), 0.15, EPS, "winds up there, far from the hero")
	var last := 0.0
	for t: int in range(0, 1600):
		var s := EnemyChoreography.sample(hits, float(t), _visuals, NEAR, true)
		assert_true(float(s.approach) >= last - EPS, "never steps back before the strike, %d ms" % t)
		last = float(s.approach)
	var arriving := EnemyChoreography.sample(hits, 1599.0, _visuals, NEAR, true)
	assert_eq(int(arriving.beat), EnemyChoreography.Beat.LUNGE, "charging in on the strike")
	assert_true(float(arriving.approach) < 1.0)
	var contact := EnemyChoreography.sample(hits, 1600.0, _visuals, NEAR, true)
	assert_eq(int(contact.beat), EnemyChoreography.Beat.CONTACT)
	assert_almost_eq(float(contact.approach), 1.0, EPS, "in contact exactly at impact")


func test_a_charge_from_home_when_the_share_is_zero() -> void:
	_visuals.charge_windup_share = 0.0
	var hits := [_hit(1600.0)]
	assert_almost_eq(float(EnemyChoreography.sample(hits, 1000.0, _visuals, NEAR, true).approach), 0.0, EPS)
	_visuals.charge_windup_share = 0.95
	assert_almost_eq(float(EnemyChoreography.sample(hits, 1000.0, _visuals, NEAR, true).approach), NEAR, EPS,
			"never winds up past where a run-up would stop")


func test_after_the_first_charge_it_stays_close_then_goes_home() -> void:
	var hits := [_hit(1600.0), _hit(2100.0, 200.0), _hit(2600.0, 200.0), _hit(3200.0, 450.0, AttackHitData.Kind.GROUND)]
	for t: int in range(1600, 3200, 3):
		var s := EnemyChoreography.sample(hits, float(t), _visuals, NEAR, true)
		assert_true(float(s.approach) >= NEAR - EPS, "stays close after the first charge, %d ms" % t)
	for impact: float in [2100.0, 2600.0]:
		var at := EnemyChoreography.sample(hits, impact, _visuals, NEAR, true)
		assert_eq(int(at.beat), EnemyChoreography.Beat.CONTACT, "contact at %.0f" % impact)
		assert_almost_eq(float(at.approach), 1.0, EPS)
	var t := 3200.0
	while int(EnemyChoreography.sample(hits, t, _visuals, NEAR, true).beat) != EnemyChoreography.Beat.AFTER:
		t += 1.0
	assert_almost_eq(float(EnemyChoreography.sample(hits, t, _visuals, NEAR, true).approach), 0.0, EPS, "home again")


func test_shipped_wind_up_attacks_keep_their_clock_and_arrive_at_impact() -> void:
	var seen: Dictionary = {}
	for file: String in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var enemy := load("res://data/enemies/" + file) as EnemyData
		for attack: EnemyAttackData in enemy.attacks:
			if attack == null or attack.is_support() or seen.has(attack.id):
				continue
			var declared := _declared(attack)
			var hits: Array = declared.hits
			if not EnemyChoreography.charges(attack, enemy, hits, _visuals):
				continue
			seen[attack.id] = true
			_check_clock(attack, hits, declared.prompts as Array)
			_check_beats(attack.id, hits)
	assert_true(seen.has("bloat_belly_slam"), "the Bloat's Belly Slam charges")
	assert_gt(seen.size(), 5, "every wind-up attack, not just one: %s" % [seen.keys()])


## The attack clock's impact times are the authored ones (default tempo): the charge never moves a
## hit or a prompt.
func _check_clock(attack: EnemyAttackData, hits: Array, prompts: Array) -> void:
	for hit: Dictionary in hits:
		var data: AttackHitData = attack.hits[int(hit.index)]
		assert_eq(int(hit.at_ms), data.impact_ms, "%s hit %d on its authored time" % [attack.id, int(hit.index)])
	for p: Dictionary in prompts:
		assert_eq(int(p.at_ms), int((hits[int(p.hit)] as Dictionary).at_ms), "%s: prompt on its hit" % attack.id)
	var clock := AttackClock.new()
	clock.start(5_000_000)
	for p: Dictionary in prompts:
		var impact_us := int(p.at_ms) * 1000
		assert_eq(clock.attack_time_us(5_000_000 + impact_us), impact_us, "%s: judged at impact" % attack.id)


## Every beat keeps its times (the same beat, pose, hit, glow and progress as the run-up version at
## every millisecond); only the approach differs. Each lunge reaches contact exactly at impact.
func _check_beats(id: String, hits: Array) -> void:
	var last := hits[hits.size() - 1] as Dictionary
	var end := int(float(last.at_ms) + float(last.close_ms)) + _visuals.contact_after_close_ms + _visuals.return_ms + 50
	var mismatches := 0
	for t: int in range(-20, end):
		var ran := EnemyChoreography.sample(hits, float(t), _visuals, NEAR)
		var charged := EnemyChoreography.sample(hits, float(t), _visuals, NEAR, true)
		for key: String in ["beat", "pose", "hit", "glow", "beat_ms", "beat_len_ms", "beat_u"]:
			if not is_equal_approx(float(ran[key]), float(charged[key])):
				mismatches += 1
	assert_eq(mismatches, 0, "%s: every beat on the same time as before" % id)
	for i: int in hits.size():
		var hit: Dictionary = hits[i]
		if not AttackHitData.is_strike(int(hit.kind)) or EnemyChoreography.is_ranged(hit):
			continue
		var at := float(hit.at_ms)
		var before := EnemyChoreography.sample(hits, at - 1.0, _visuals, NEAR, true)
		assert_eq(int(before.beat), EnemyChoreography.Beat.LUNGE, "%s hit %d: lunging 1 ms before impact" % [id, i])
		assert_lt(float(before.approach), 1.0, id)
		var contact := EnemyChoreography.sample(hits, at, _visuals, NEAR, true)
		assert_eq(int(contact.beat), EnemyChoreography.Beat.CONTACT, "%s hit %d: contact at impact" % [id, i])
		assert_almost_eq(float(contact.approach), 1.0, EPS, id)
	var opening := EnemyChoreography.sample(hits, 0.0, _visuals, NEAR, true)
	assert_almost_eq(float(opening.approach), 0.0, EPS, "%s: winds up from home" % id)
