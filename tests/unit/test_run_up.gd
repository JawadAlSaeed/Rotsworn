extends GutTest
## Run up and swing (DESIGN.md 3.12, card #244): an attacker that runs up stands a step short of
## its target when the clock starts, every hit steps in from there and lands exactly at impact as
## before, the recoil never takes it further back, and after the last hit it goes home over
## return_ms. Which attacks open with a run, and the longer lead-in every machine waits.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const NEAR: float = 0.8

var _visuals := CombatVisuals.new()
var _tuning := Tuning.new()


func _hit(at_ms: float, kind: int = AttackHitData.Kind.NORMAL, feint: bool = false) -> Dictionary:
	return {"at_ms": at_ms, "kind": kind, "approach_ms": 200, "feint": feint, "close_ms": 120.0}


func _declared(attack_id: String) -> Array:
	var attack := load("res://data/enemy_attacks/%s.tres" % attack_id) as EnemyAttackData
	var hits: Array = Fx.declared_attack(attack).hits as Array
	EnemyChoreography.add_hit_data(hits, attack)
	return hits


func test_the_attack_starts_where_the_run_stopped() -> void:
	var hits := [_hit(900.0)]
	var s := EnemyChoreography.sample(hits, 0.0, _visuals, NEAR)
	assert_eq(int(s.beat), EnemyChoreography.Beat.WINDUP)
	assert_almost_eq(float(s.approach), NEAR, 0.0001, "winds up next to the hero, not at home")


func test_each_swing_steps_in_and_lands_at_impact() -> void:
	var hits := [_hit(900.0), _hit(1400.0), _hit(1900.0)]
	for t: int in range(0, 1900, 3):
		var s := EnemyChoreography.sample(hits, float(t), _visuals, NEAR)
		assert_true(float(s.approach) >= NEAR - 0.0001, "never further back than the run stopped, %d ms" % t)
	for impact: float in [900.0, 1400.0, 1900.0]:
		var at := EnemyChoreography.sample(hits, impact, _visuals, NEAR)
		assert_eq(int(at.beat), EnemyChoreography.Beat.CONTACT, "contact at %.0f" % impact)
		assert_almost_eq(float(at.approach), 1.0, 0.0001, "in contact at %.0f" % impact)
		var before := EnemyChoreography.sample(hits, impact - 100.0, _visuals, NEAR)
		assert_eq(int(before.beat), EnemyChoreography.Beat.LUNGE, "the swing before %.0f" % impact)
		assert_true(float(before.approach) < 1.0 and float(before.approach) >= NEAR)


func test_it_is_home_as_soon_as_an_enemy_that_lunged() -> void:
	# A counter dashes in after counter_delay_ms: the attacker must be home by then, as before.
	_visuals.return_ms = 260
	var hits := [_hit(900.0)]
	var t := 900.0
	while int(EnemyChoreography.sample(hits, t, _visuals, NEAR).beat) != EnemyChoreography.Beat.RETURN:
		t += 1.0
	var s := EnemyChoreography.sample(hits, t, _visuals, NEAR)
	assert_almost_eq(float(s.beat_len_ms), 260.0, 0.001, "goes home over return_ms")
	var walked := EnemyChoreography.sample(hits, t, _visuals)
	assert_eq(float(walked.beat_ms), float(s.beat_ms), "starts home at the same moment")
	var home := EnemyChoreography.sample(hits, t + 261.0, _visuals, NEAR)
	assert_eq(int(home.beat), EnemyChoreography.Beat.AFTER)
	assert_almost_eq(float(home.approach), 0.0, 0.0001, "home again")


func test_slams_and_throws_play_where_it_stands() -> void:
	var hits := [_hit(900.0), _hit(1500.0, AttackHitData.Kind.GROUND)]
	var slam_at := EnemyChoreography.motion_start(hits, 1, _visuals) + 1.0
	var s := EnemyChoreography.sample(hits, slam_at, _visuals, NEAR)
	assert_eq(int(s.beat), EnemyChoreography.Beat.SLAM)
	assert_almost_eq(float(s.approach), NEAR, 0.0001, "slams next to the hero")


func test_only_runners_opening_with_a_melee_hit_run_up() -> void:
	var husk := load("res://data/enemies/rotten_husk.tres") as EnemyData
	var swipe := load("res://data/enemy_attacks/husk_swipe.tres") as EnemyAttackData
	assert_true(EnemyChoreography.runs_up(swipe, husk, _declared("husk_swipe"), _tuning), "a claw swipe")
	assert_true(EnemyChoreography.runs_up(load("res://data/enemy_attacks/husk_rot_combo.tres"), husk,
			_declared("husk_rot_combo"), _tuning), "a string that opens with claws, a slam in the middle")
	assert_false(EnemyChoreography.runs_up(load("res://data/enemy_attacks/husk_ground_slam.tres"), husk,
			_declared("husk_ground_slam"), _tuning), "a slam opens it: stays home")
	assert_false(EnemyChoreography.runs_up(load("res://data/enemy_attacks/husk_rock_toss.tres"), husk,
			_declared("husk_rock_toss"), _tuning), "a throw opens it: stays home")
	var walker := husk.duplicate() as EnemyData
	walker.runs_up = false
	assert_false(EnemyChoreography.runs_up(swipe, walker, _declared("husk_swipe"), _tuning), "not a runner")
	assert_false(EnemyChoreography.runs_up(swipe, null, _declared("husk_swipe"), _tuning))
	assert_false(EnemyChoreography.runs_up(null, husk, _declared("husk_swipe"), _tuning))


func test_the_run_lengthens_the_lead_in() -> void:
	var tuning := Tuning.new()
	tuning.attack_lead_in_ms = 700
	tuning.run_up_ms = 450
	assert_eq(EnemyChoreography.lead_in_ms(tuning, false), 700)
	assert_eq(EnemyChoreography.lead_in_ms(tuning, true), 1150)


func test_claw_bite_and_blade_enemies_run_up() -> void:
	for id: String in ["rotten_husk", "hollow_king", "rot_hyena", "rot_rat", "shade", "barrow_brute", "bloat"]:
		assert_true((load("res://data/enemies/%s.tres" % id) as EnemyData).runs_up, id)
	# Throwers have no melee opening, and a toad's tongue reaches from home.
	for id: String in ["ember_slinger", "marsh_lantern", "mire_toad"]:
		assert_false((load("res://data/enemies/%s.tres" % id) as EnemyData).runs_up, id)


func test_the_run_cycles_the_chase_clip() -> void:
	var clips := SpriteClips.new()
	clips.frame_size = Vector2i(8, 8)
	clips.hframes = 8
	clips.vframes = 8
	clips.clips = {"idle": PackedInt32Array([0]), "chase": PackedInt32Array([1, 2, 3, 4])}
	_visuals.run_up_cycle_ms = 400
	var count := EnemyAnim.counter(clips)
	assert_eq(String(EnemyAnim.run(count, 0.0, _visuals).clip), "chase")
	assert_eq(int(EnemyAnim.run(count, 150.0, _visuals).index), ClipMath.loop(4, 150.0, 400.0))
	clips.clips.erase("chase")
	assert_eq(String(EnemyAnim.run(count, 150.0, _visuals).clip), "", "no chase clip: the legacy pose")


func test_brin_and_alder_run_up_cass_casts_from_her_spot() -> void:
	for id: String in ["brin", "alder"]:
		assert_true((load("res://data/characters/%s.tres" % id) as CharacterData).runs_up, id)
	assert_false((load("res://data/characters/cass.tres") as CharacterData).runs_up, "cass")


func test_a_hero_stops_a_step_short_of_the_strike_point() -> void:
	assert_almost_eq(SkillSequenceRunner.near_share(10.0, 1.0), 0.9, 0.0001)
	assert_almost_eq(SkillSequenceRunner.near_share(4.0, 1.0) * 4.0, 3.0, 0.0001, "one step short")
	assert_eq(SkillSequenceRunner.near_share(0.5, 1.0), 0.0, "already closer than a step: stays put")
	assert_eq(SkillSequenceRunner.near_share(0.0, 1.0), 0.0)


func test_the_hero_arrives_before_the_earliest_wind_up() -> void:
	# The run loop is a one-shot override: it must end before any skill's wind-up frames start, or
	# it would hide them (DESIGN.md 3.12).
	var tuning := load("res://data/tuning/tuning.tres") as Tuning
	var visuals := load("res://data/presentation/combat_visuals.tres") as CombatVisuals
	for file: String in DirAccess.get_files_at("res://data/abilities"):
		if not file.ends_with(".tres"):
			continue
		var ability := load("res://data/abilities/" + file) as AbilityData
		if ability.press_times_ms.is_empty() or ability.projectile != null or not ability.targets_enemies():
			continue
		var windup_ms := visuals.skill_windup_ms * ability.windup_percent / 100
		assert_true(tuning.hero_run_up_ms <= ability.press_times_ms[0] - windup_ms,
				"%s: first wind-up at %d ms" % [ability.id, ability.press_times_ms[0] - windup_ms])
