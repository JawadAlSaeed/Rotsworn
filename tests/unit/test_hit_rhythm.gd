extends GutTest
## HitRhythm and the hit index of EnemyChoreography.sample (DESIGN 3.8): rhythm rows space icons
## by time (with a minimum step, squeezed to a maximum width), and during an attack exactly the
## hit whose motion is playing is active (a feint from its false start), landed hits are done.
## Uses the default CombatVisuals so edits to the .tres files never break it.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const ATTACK_DIR := "res://data/enemy_attacks"
const ICON: float = 30.0
const GAP: float = 4.0
const PX_PER_MS: float = 0.2
## Sampling step through an attack (ms).
const STEP_MS: float = 5.0
const EPS: float = 0.01

var _visuals := CombatVisuals.new()


## The declared hit list of every shipped attack: [{name, hits}].
func _declared_attacks() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for file: String in DirAccess.get_files_at(ATTACK_DIR):
		if not file.ends_with(".tres"):
			continue
		var attack := load(ATTACK_DIR.path_join(file)) as EnemyAttackData
		if attack.is_support():
			continue  # A support move (card #259) has no hits to play.
		var declared := Fx.declared_attack(attack)
		list.append({"name": attack.id, "hits": declared.hits})
	return list


# --- layout -----------------------------------------------------------------------------------

func test_icons_are_spaced_by_time() -> void:
	var c := HitRhythm.layout([800, 1600, 1900], ICON, PX_PER_MS, GAP, 1000.0)
	assert_almost_eq(c[0], 15.0, EPS, "the first icon starts at the row's left edge")
	assert_almost_eq(c[1] - c[0], 160.0, EPS, "800 ms apart at 0.2 px per ms")
	assert_almost_eq(c[2] - c[1], 60.0, EPS, "a short gap stays short: the rhythm shows")
	assert_almost_eq(HitRhythm.row_width(c, ICON), 250.0, EPS)


func test_close_hits_keep_a_minimum_step() -> void:
	var c := HitRhythm.layout([0, 50, 100], ICON, PX_PER_MS, GAP, 1000.0)
	assert_almost_eq(c[1] - c[0], ICON + GAP, EPS, "icons never overlap")
	assert_almost_eq(c[2] - c[1], ICON + GAP, EPS)


func test_long_rows_are_squeezed_evenly() -> void:
	var times := [0, 500, 1000, 1500, 2000, 2500]
	var c := HitRhythm.layout(times, ICON, PX_PER_MS, GAP, 300.0)
	assert_lte(HitRhythm.row_width(c, ICON), 300.0 + EPS, "the row fits its maximum width")
	assert_gt(HitRhythm.row_width(c, ICON), 290.0, "and uses most of it")
	for i: int in range(2, c.size()):
		assert_almost_eq(c[i] - c[i - 1], c[1] - c[0], EPS, "equal gaps stay equal when squeezed")
	var tight := HitRhythm.layout(times, ICON, PX_PER_MS, GAP, 10.0)
	for i: int in range(1, tight.size()):
		assert_almost_eq(tight[i] - tight[i - 1], ICON + GAP, EPS, "never squeezed below the minimum step")


func test_single_and_empty_rows() -> void:
	var one := HitRhythm.layout([900], ICON, PX_PER_MS, GAP, 100.0)
	assert_eq(one.size(), 1)
	assert_almost_eq(HitRhythm.row_width(one, ICON), ICON, EPS)
	var none := HitRhythm.layout([], ICON, PX_PER_MS, GAP, 100.0)
	assert_eq(none.size(), 0)
	assert_eq(HitRhythm.row_width(none, ICON), 0.0)


func test_shipped_attacks_fit_the_default_row() -> void:
	for a: Dictionary in _declared_attacks():
		var times: Array = []
		for hit: Dictionary in a.hits:
			times.append(int(hit.at_ms))
		var c := HitRhythm.layout(times, _visuals.intent_icon_px, _visuals.rhythm_px_per_ms,
				_visuals.rhythm_min_gap_px, _visuals.rhythm_max_width_px)
		assert_lte(HitRhythm.row_width(c, _visuals.intent_icon_px), _visuals.rhythm_max_width_px + EPS, a.name)


# --- states during an attack ------------------------------------------------------------------

func test_one_hit_at_a_time_is_active_from_its_motion_to_its_impact() -> void:
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		var last := float((hits[hits.size() - 1] as Dictionary).at_ms)
		var t := -STEP_MS
		while t <= last + STEP_MS:
			var states := HitRhythm.states(hits, t, _visuals)
			assert_lte(states.count(HitRhythm.State.ACTIVE), 1, "%s at %.0f ms" % [a.name, t])
			for i: int in hits.size():
				var impact := float((hits[i] as Dictionary).at_ms)
				var start := EnemyChoreography.motion_start(hits, i, _visuals)
				var expected := HitRhythm.State.UPCOMING
				if t >= impact:
					expected = HitRhythm.State.DONE
				elif t >= start:
					expected = HitRhythm.State.ACTIVE
				if states[i] != expected:
					fail_test("%s hit %d at %.0f ms: state %d, expected %d" % [a.name, i, t, states[i], expected])
					return
			t += STEP_MS
		var done := HitRhythm.states(hits, last, _visuals)
		assert_eq(done.count(HitRhythm.State.DONE), hits.size(), "%s: every hit is done at the last impact" % a.name)
	assert_true(true)


func test_a_feint_lights_up_at_its_false_start() -> void:
	var feints := 0
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		for i: int in hits.size():
			var hit: Dictionary = hits[i]
			if not bool(hit.feint):
				continue
			feints += 1
			var false_start := EnemyChoreography.motion_start(hits, i, _visuals)
			var real_lunge := float(hit.at_ms) - float(hit.approach_ms)
			assert_lt(false_start, real_lunge, "%s: the false start comes before the real lunge" % a.name)
			var states := HitRhythm.states(hits, false_start, _visuals)
			assert_eq(states[i], HitRhythm.State.ACTIVE, "%s: active from the false start, so the marker fools too" % a.name)
	assert_gt(feints, 0, "the shipped attacks include feints")


func test_active_hit_index() -> void:
	var states: Array[int] = [HitRhythm.State.DONE, HitRhythm.State.ACTIVE, HitRhythm.State.UPCOMING]
	assert_eq(HitRhythm.active_hit(states), 1)
	var idle: Array[int] = [HitRhythm.State.DONE, HitRhythm.State.UPCOMING]
	assert_eq(HitRhythm.active_hit(idle), -1)


# --- the pose knows its hit -------------------------------------------------------------------

func test_motion_and_wind_up_name_their_hit() -> void:
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		assert_eq(int(EnemyChoreography.sample(hits, -1.0, _visuals).hit), -1, "%s: no hit before the clock" % a.name)
		for i: int in hits.size():
			var start := EnemyChoreography.motion_start(hits, i, _visuals)
			# A motion clamped to the previous impact waits for that hit's contact and recoil.
			if i > 0 and start <= float((hits[i - 1] as Dictionary).at_ms):
				continue
			var moving := EnemyChoreography.sample(hits, start + 1.0, _visuals)
			assert_eq(int(moving.hit), i, "%s: the motion starting at %.0f ms belongs to hit %d" % [a.name, start, i])
			var before := EnemyChoreography.sample(hits, start - 1.0, _visuals)
			if int(before.pose) == EnemyChoreography.Pose.WINDUP:
				assert_eq(int(before.hit), i, "%s: the wind-up before hit %d glows for it" % [a.name, i])
