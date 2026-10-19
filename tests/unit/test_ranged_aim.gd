extends GutTest
## Ranged hits and spell bolts on screen (DESIGN.md 3.9 and 2.10, cards #165 and #166): the
## indicator's pure timing (the brackets close exactly at the declared impact, the time the defence
## is judged on), the shot release (a bolt leaves at the press, or at the end of the press window
## when none came), and the data rules that make both readable. Presentation only: none of it
## touches the combat core.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const ATTACK_DIR := "res://data/enemy_attacks"
const EPS: float = 0.0001

var _visuals := CombatVisuals.new()


# --- RangedAim ---------------------------------------------------------------------------------

func test_progress_runs_from_launch_to_impact() -> void:
	assert_almost_eq(RangedAim.progress(500.0, 500.0, 1300.0), 0.0, EPS)
	assert_almost_eq(RangedAim.progress(900.0, 500.0, 1300.0), 0.5, EPS)
	assert_almost_eq(RangedAim.progress(1300.0, 500.0, 1300.0), 1.0, EPS, "closed exactly at impact")
	assert_almost_eq(RangedAim.progress(100.0, 500.0, 1300.0), 0.0, EPS, "clamped before the launch")
	assert_almost_eq(RangedAim.progress(2000.0, 500.0, 1300.0), 1.0, EPS, "clamped after the impact")
	assert_almost_eq(RangedAim.progress(1299.0, 500.0, 1300.0), 0.99875, EPS, "not closed a millisecond early")


func test_progress_with_no_flight_is_a_step_at_impact() -> void:
	assert_almost_eq(RangedAim.progress(999.0, 1000.0, 1000.0), 0.0, EPS)
	assert_almost_eq(RangedAim.progress(1000.0, 1000.0, 1000.0), 1.0, EPS)


func test_it_shows_a_lead_before_the_throw_and_never_before_zero() -> void:
	assert_almost_eq(RangedAim.show_from_ms(900.0, 300.0), 600.0, EPS)
	assert_almost_eq(RangedAim.show_from_ms(100.0, 300.0), 0.0, EPS)
	assert_almost_eq(RangedAim.show_from_ms(500.0, -50.0), 500.0, EPS, "a negative lead is no lead")


func test_state_fades_in_holds_and_fades_out() -> void:
	# Launch 800, impact 1400, decided at 1400, 300 ms lead, 100 ms fades: visible from 500.
	var before := RangedAim.state(499.0, 800.0, 1400.0, 1400.0, 300.0, 100.0)
	assert_false(bool(before.shown), "hidden before its lead")
	assert_almost_eq(float(before.alpha), 0.0, EPS)
	var half_in := RangedAim.state(550.0, 800.0, 1400.0, 1400.0, 300.0, 100.0)
	assert_almost_eq(float(half_in.alpha), 0.5, EPS)
	assert_true(bool(half_in.shown))
	var flying := RangedAim.state(1100.0, 800.0, 1400.0, 1400.0, 300.0, 100.0)
	assert_almost_eq(float(flying.alpha), 1.0, EPS)
	assert_false(bool(flying.locked), "still open while it flies")
	assert_almost_eq(float(flying.progress), 0.5, EPS)
	var landed := RangedAim.state(1400.0, 800.0, 1400.0, 1400.0, 300.0, 100.0)
	assert_true(bool(landed.locked), "locked at impact")
	assert_almost_eq(float(landed.progress), 1.0, EPS)
	var fading := RangedAim.state(1450.0, 800.0, 1400.0, 1400.0, 300.0, 100.0)
	assert_almost_eq(float(fading.alpha), 0.5, EPS)
	assert_false(bool(RangedAim.state(1500.0, 800.0, 1400.0, 1400.0, 300.0, 100.0).shown), "gone after the fade")


func test_a_hit_decided_after_the_impact_keeps_the_bracket_until_then() -> void:
	var waiting := RangedAim.state(1500.0, 800.0, 1400.0, 1600.0, 300.0, 100.0)
	assert_almost_eq(float(waiting.alpha), 1.0, EPS, "the hit is not decided yet")
	assert_true(bool(waiting.locked))


func test_bracket_size_shrinks_to_its_end_size_at_impact() -> void:
	assert_almost_eq(RangedAim.radius_px(0.0, 120.0, 46.0), 120.0, EPS)
	assert_almost_eq(RangedAim.radius_px(0.5, 120.0, 46.0), 83.0, EPS)
	assert_almost_eq(RangedAim.radius_px(1.0, 120.0, 46.0), 46.0, EPS)
	assert_almost_eq(RangedAim.radius_px(2.0, 120.0, 46.0), 46.0, EPS, "never smaller than its end size")


func test_lock_pulse_is_only_right_after_the_impact() -> void:
	assert_almost_eq(RangedAim.lock_pulse(999.0, 1000.0, 200.0), 0.0, EPS)
	assert_almost_eq(RangedAim.lock_pulse(1000.0, 1000.0, 200.0), 1.0, EPS)
	assert_almost_eq(RangedAim.lock_pulse(1100.0, 1000.0, 200.0), 0.5, EPS)
	assert_almost_eq(RangedAim.lock_pulse(1200.0, 1000.0, 200.0), 0.0, EPS)
	assert_almost_eq(RangedAim.lock_pulse(1000.0, 1000.0, 0.0), 0.0, EPS, "no pulse length, no pulse")


# --- the indicator matches what is judged ---------------------------------------------------------

func test_every_shipped_ranged_hit_closes_its_bracket_on_the_judged_impact() -> void:
	var ranged := 0
	for file: String in DirAccess.get_files_at(ATTACK_DIR):
		if not file.ends_with(".tres"):
			continue
		var attack := load(ATTACK_DIR.path_join(file)) as EnemyAttackData
		if attack.is_support():
			continue  # A support move (card #259) has no hits to play.
		var declared := Fx.declared_attack(attack)
		var hits := EnemyChoreography.with_close_times(declared.hits as Array, declared.prompts as Array, 0)
		EnemyChoreography.add_hit_data(hits, attack)
		for i: int in hits.size():
			if not EnemyChoreography.is_ranged(hits[i]):
				continue
			ranged += 1
			var label := "%s hit %d" % [attack.id, i]
			var impact := float((hits[i] as Dictionary).at_ms)
			var launch := EnemyChoreography.motion_start(hits, i, _visuals)
			assert_lt(launch, impact, label + ": launches before it lands")
			assert_almost_eq(RangedAim.progress(impact, launch, impact), 1.0, EPS, label + ": closed at impact")
			assert_lt(RangedAim.progress(impact - 1.0, launch, impact), 1.0, label + ": open just before")
			# Every prompt of this hit is judged at the very time the bracket closes.
			var prompts := 0
			for prompt: Dictionary in declared.prompts:
				if int(prompt.hit) == i:
					prompts += 1
					assert_eq(float(prompt.at_ms), impact, label + ": the prompt is judged at the declared hit time")
			assert_gt(prompts, 0, label + ": somebody defends it")
			# The indicator is up before the projectile leaves, and the bracket is already
			# wide enough to see closing for the whole flight.
			var s := RangedAim.state(launch, launch, impact, impact, float(_visuals.ranged_aim_lead_ms),
					float(_visuals.ranged_aim_fade_ms))
			assert_true(bool(s.shown), label + ": shown when the projectile leaves")
	assert_gt(ranged, 0, "shipped ranged hits")


func test_indicator_data_is_sane() -> void:
	var visuals := load("res://data/presentation/combat_visuals.tres") as CombatVisuals
	assert_gt(visuals.ranged_aim_start_px, visuals.ranged_aim_end_px, "the bracket closes in, not out")
	assert_gt(visuals.ranged_aim_end_px, 0.0)
	assert_gt(visuals.ranged_aim_path_points, 1)
	assert_gt(visuals.ranged_aim_dash_px, 0.0)
	assert_true(Fx.shipped_tuning().show_ranged_aim, "the indicator is on by default")


# --- SpellShot ---------------------------------------------------------------------------------

## A press prompt as the engine declares it: the ring's moment and the GOOD and PERFECT windows.
func _prompt(at_ms: int) -> Dictionary:
	return {"at_ms": at_ms, "windows": {
		Defense.Outcome.PRESS: [-200000, 200000],
		Defense.Outcome.PRESS_PERFECT: [-70000, 70000],
	}}


func test_a_shot_leaves_at_the_press() -> void:
	var end_us := SpellShot.window_end_us(_prompt(800), 0)
	assert_eq(end_us, 1000000, "the window closes 200 ms after the ring's moment")
	assert_eq(SpellShot.release_us(700000, end_us), 700000, "an early press shoots at once")
	assert_eq(SpellShot.release_us(800000, end_us), 800000)
	assert_eq(SpellShot.release_us(950000, end_us), 950000, "a late press shoots when it was pressed")


func test_a_shot_with_no_press_leaves_at_the_end_of_the_window() -> void:
	var end_us := SpellShot.window_end_us(_prompt(800), 0)
	# The judge noticed the closed window a frame later: the shot still leaves at the end.
	assert_eq(SpellShot.release_us(end_us + 16000, end_us), end_us)
	# An early press that used the ring up as a miss leaves with that press, not at the end.
	assert_eq(SpellShot.release_us(400000, end_us), 400000)


func test_the_window_end_includes_the_lag_compensation() -> void:
	assert_eq(SpellShot.window_end_us(_prompt(800), 50000), 1050000)


func test_a_bolt_lands_after_its_flight_and_is_in_the_air_between() -> void:
	var release := 900000
	var flight := 320000
	assert_eq(SpellShot.landing_us(release, flight), 1220000)
	assert_false(SpellShot.in_flight(release - 1, release, flight))
	assert_true(SpellShot.in_flight(release, release, flight))
	assert_true(SpellShot.in_flight(1219999, release, flight))
	assert_false(SpellShot.in_flight(1220000, release, flight), "landed")
	assert_almost_eq(SpellShot.progress(1060000, release, flight), 0.5, EPS)
	assert_lt(SpellShot.progress(release - 1000, release, flight), 0.0)
	assert_gt(SpellShot.progress(1300000, release, flight), 1.0)


func test_a_zero_flight_still_lands_after_the_release() -> void:
	assert_eq(SpellShot.landing_us(500000, 0), 500001)


func test_a_spell_lands_before_its_followups_ring() -> void:
	# The bolt must have landed before the allies' follow-up moment (follow_up_delay_ms after the
	# press moment), even for the latest press the window takes.
	var tuning := Fx.shipped_tuning()
	for path: String in ["res://data/abilities/reveal.tres", "res://data/abilities/smite.tres"]:
		var spell := load(path) as AbilityData
		assert_not_null(spell.projectile, path)
		var at_us := spell.press_times_ms[spell.press_times_ms.size() - 1] * 1000
		var latest_release := SpellShot.window_end_us({"at_ms": spell.press_times_ms[spell.press_times_ms.size() - 1],
				"windows": {Defense.Outcome.PRESS: [-tuning.skill_press_window_ms * 1000, tuning.skill_press_window_ms * 1000]}}, 0)
		var landing := SpellShot.landing_us(latest_release, spell.projectile_flight_ms * 1000)
		assert_lt(landing, at_us + tuning.follow_up_delay_ms * 1000,
				"%s: the bolt lands before the follow-ups strike" % spell.id)
