extends GutTest
## EnemyChoreography (DESIGN 3.3, 3.6, 3.7): what you see is what is judged. For every shipped
## attack, as the engine declares it: a normal lunge reaches the contact point exactly at impact,
## the contact pose holds until the hit can no longer be defended (where the string leaves room),
## a ground wave launches approach_ms before impact and a feint's false start comes feint_lead_ms
## earlier. Uses the default Tuning and CombatVisuals so edits to the .tres files never break it.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const ATTACK_DIR := "res://data/enemy_attacks"
const LATENCY_MS: int = 30
## Close enough for float milliseconds.
const EPS: float = 0.001

var _visuals := CombatVisuals.new()


## {name, hits (with close times), prompts} for every shipped attack, declared by the engine.
func _declared_attacks() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for file: String in DirAccess.get_files_at(ATTACK_DIR):
		if not file.ends_with(".tres"):
			continue
		var attack := load(ATTACK_DIR.path_join(file)) as EnemyAttackData
		if attack.is_support():
			continue  # A support move (card #259) has no hits to play.
		var declared := Fx.declared_attack(attack)
		var prompts: Array = declared.prompts
		var hits := EnemyChoreography.with_close_times(declared.hits as Array, prompts, LATENCY_MS)
		EnemyChoreography.add_hit_data(hits, attack)
		list.append({
			"name": attack.id,
			"hits": hits,
			"prompts": prompts,
		})
	return list


func test_shipped_attacks_are_found() -> void:
	var files := 0
	for file: String in DirAccess.get_files_at(ATTACK_DIR):
		if file.ends_with(".tres") and not (load(ATTACK_DIR.path_join(file)) as EnemyAttackData).is_support():
			files += 1
	assert_gt(files, 5, "phase 2 adds attacks to the husk's five")
	assert_eq(_declared_attacks().size(), files)


func test_close_times_are_late_edge_plus_latency() -> void:
	var tuning := Tuning.new()
	for a: Dictionary in _declared_attacks():
		for hit: Dictionary in a.hits:
			var late_ms := float(tuning.window_edges_us(tuning.dodge_window_ms).y) / 1000.0
			if int(hit.kind) == AttackHitData.Kind.GROUND:
				late_ms = float(tuning.window_edges_us(tuning.jump_window_ms).y) / 1000.0
			elif int(hit.kind) == AttackHitData.Kind.REND:
				# A rend everywhere (the Barrow Brute's slam, card #257): only the parry's window.
				late_ms = float(tuning.window_edges_us(tuning.parry_window_ms).y) / 1000.0
			assert_almost_eq(float(hit.close_ms), late_ms + LATENCY_MS, EPS, a.name)


func test_normal_lunges_reach_contact_exactly_at_impact() -> void:
	for a: Dictionary in _declared_attacks():
		for i: int in (a.hits as Array).size():
			var hit: Dictionary = a.hits[i]
			if int(hit.kind) != AttackHitData.Kind.NORMAL or EnemyChoreography.is_ranged(hit):
				continue
			var at := float(hit.at_ms)
			var label := "%s hit %d" % [a.name, i]
			var before := EnemyChoreography.sample(a.hits, at - 1.0, _visuals)
			assert_eq(int(before.pose), EnemyChoreography.Pose.LUNGE, label + ": still lunging 1 ms before impact")
			assert_lt(float(before.approach), 1.0, label)
			var contact := EnemyChoreography.sample(a.hits, at, _visuals)
			assert_eq(int(contact.pose), EnemyChoreography.Pose.CONTACT, label + ": contact at impact")
			assert_almost_eq(float(contact.approach), 1.0, EPS, label)


func test_contact_holds_until_the_hit_closes_where_the_string_allows() -> void:
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		for i: int in hits.size():
			var hit: Dictionary = hits[i]
			if int(hit.kind) != AttackHitData.Kind.NORMAL or EnemyChoreography.is_ranged(hit):
				continue
			var at := float(hit.at_ms)
			var hold := maxf(float(_visuals.contact_hold_ms), float(hit.close_ms))
			if i == hits.size() - 1:
				hold = maxf(float(_visuals.contact_hold_ms), float(hit.close_ms) + float(_visuals.contact_after_close_ms))
			else:
				var next_motion := float(EnemyChoreography.cues(hits, _visuals).filter(
						func(c: Dictionary) -> bool: return int(c.hit) == i + 1)[0].at_ms)
				hold = minf(hold, next_motion - at - float(_visuals.recoil_min_ms))
			var label := "%s hit %d" % [a.name, i]
			var held := EnemyChoreography.sample(hits, at + hold - 1.0, _visuals)
			assert_eq(int(held.pose), EnemyChoreography.Pose.CONTACT, label + ": still in contact")
			if i == hits.size() - 1:
				assert_gt(hold, float(hit.close_ms), label + ": the last hit holds past its close (it lands after it)")


func test_cues_match_the_motion() -> void:
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		var cues := EnemyChoreography.cues(hits, _visuals)
		for i: int in hits.size():
			var hit: Dictionary = hits[i]
			var mine := cues.filter(func(c: Dictionary) -> bool: return int(c.hit) == i)
			var label := "%s hit %d" % [a.name, i]
			var earliest := float(hits[i - 1].at_ms) if i > 0 else 0.0
			var launch := maxf(float(hit.at_ms) - float(hit.approach_ms), earliest)
			if int(hit.kind) == AttackHitData.Kind.GROUND:
				assert_eq(mine.size(), 1, label)
				assert_eq(String(mine[0].type), EnemyChoreography.CUE_SLAM, label)
				assert_almost_eq(float(mine[0].at_ms), launch, EPS, label + ": the wave launches approach_ms before impact")
			elif EnemyChoreography.is_ranged(hit):
				assert_eq(mine.size(), 1, label)
				assert_eq(String(mine[0].type), EnemyChoreography.CUE_SHOOT, label)
				assert_almost_eq(float(mine[0].at_ms), launch, EPS, label + ": the throw leaves approach_ms before impact")
			elif bool(hit.feint):
				assert_eq(mine.size(), 2, label)
				assert_eq(String(mine[0].type), EnemyChoreography.CUE_FEINT, label)
				assert_almost_eq(float(mine[0].at_ms), maxf(launch - float(_visuals.feint_lead_ms), earliest), EPS, label)
				assert_almost_eq(float(mine[1].at_ms), launch, EPS, label + ": the real lunge")
			else:
				assert_eq(mine.size(), 1, label)
				assert_almost_eq(float(mine[0].at_ms), launch, EPS, label)


func test_nothing_moves_before_the_clock_or_after_the_attack() -> void:
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		var start := EnemyChoreography.sample(hits, -1.0, _visuals)
		assert_eq([int(start.pose), float(start.approach)], [EnemyChoreography.Pose.IDLE, 0.0], a.name)
		var last: Dictionary = hits[hits.size() - 1]
		var settled := float(last.at_ms) + float(last.close_ms) + float(_visuals.contact_after_close_ms) 				+ float(_visuals.slam_hold_ms) + float(_visuals.return_ms) + 1.0
		var end := EnemyChoreography.sample(hits, settled, _visuals)
		assert_eq(int(end.pose), EnemyChoreography.Pose.IDLE, a.name)
		assert_almost_eq(float(end.approach), 0.0, EPS, a.name + ": back home")


# --- beats (phase 10, DESIGN 5.5): which part of the attack a moment belongs to ----------------

## The beat sample() gives at `t`.
func _beat_at(hits: Array, t: float) -> int:
	return int(EnemyChoreography.sample(hits, t, _visuals).beat)


func test_each_cue_starts_its_beat() -> void:
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		for cue: Dictionary in EnemyChoreography.cues(hits, _visuals):
			var s := EnemyChoreography.sample(hits, float(cue.at_ms), _visuals)
			var label := "%s cue %s of hit %d" % [a.name, String(cue.type), int(cue.hit)]
			var expected := EnemyChoreography.Beat.LUNGE
			match String(cue.type):
				EnemyChoreography.CUE_FEINT:
					expected = EnemyChoreography.Beat.FEINT_START
				EnemyChoreography.CUE_SLAM:
					expected = EnemyChoreography.Beat.SLAM
				EnemyChoreography.CUE_SHOOT:
					expected = EnemyChoreography.Beat.SHOOT
			assert_eq(int(s.beat), expected, label)
			assert_eq(int(s.hit), int(cue.hit), label)
			assert_almost_eq(float(s.beat_ms), 0.0, EPS, label + ": the beat starts at its cue")


func test_contact_beat_starts_at_impact_and_the_lunge_arrives_just_before() -> void:
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		for i: int in hits.size():
			var hit: Dictionary = hits[i]
			if int(hit.kind) != AttackHitData.Kind.NORMAL or EnemyChoreography.is_ranged(hit):
				continue
			var at := float(hit.at_ms)
			var label := "%s hit %d" % [a.name, i]
			var contact := EnemyChoreography.sample(hits, at, _visuals)
			assert_eq(int(contact.beat), EnemyChoreography.Beat.CONTACT, label)
			assert_almost_eq(float(contact.beat_ms), 0.0, EPS, label + ": contact[0] shows exactly at impact")
			assert_gt(float(contact.beat_len_ms), 0.0, label)
			var arriving := EnemyChoreography.sample(hits, at - 0.5, _visuals)
			assert_eq(int(arriving.beat), EnemyChoreography.Beat.LUNGE, label)
			assert_gt(float(arriving.beat_u), 0.99, label + ": the lunge is arriving 0.5 ms before impact")
			assert_lt(float(arriving.beat_u), 1.0, label)


func test_a_feints_false_start_shows_the_same_progress_as_a_real_lunge() -> void:
	var feints := 0
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		for i: int in hits.size():
			var hit: Dictionary = hits[i]
			if int(hit.kind) != AttackHitData.Kind.NORMAL or not bool(hit.feint):
				continue
			feints += 1
			var start := EnemyChoreography.motion_start(hits, i, _visuals)
			var lunge_start := float(hit.at_ms) - float(hit.approach_ms)
			var portion := float(_visuals.feint_portion_percent) / 100.0
			var label := "%s hit %d" % [a.name, i]
			var x := 0.0
			while x < float(hit.approach_ms) * portion:
				var fake := EnemyChoreography.sample(hits, start + x, _visuals)
				var real := EnemyChoreography.sample(hits, lunge_start + x, _visuals)
				assert_eq(int(fake.beat), EnemyChoreography.Beat.FEINT_START, label)
				assert_eq(int(real.beat), EnemyChoreography.Beat.LUNGE, label)
				assert_almost_eq(float(fake.beat_u), float(real.beat_u), EPS, "%s at +%.0f ms" % [label, x])
				x += 7.0
			assert_eq(_beat_at(hits, start + float(hit.approach_ms) * portion), EnemyChoreography.Beat.FEINT_HOLD, label)
	assert_gt(feints, 0, "the shipped attacks have feints")


## Sweeps every shipped attack at 1 ms steps: each (hit, beat) is one unbroken run, its beat_ms
## counts up from the run's start and never goes back, its length matches the run, and beat_u
## stays within 0..1. The poses are the ones the beats name.
func test_beats_are_contiguous_and_count_up() -> void:
	var pose_of := {
		EnemyChoreography.Beat.BEFORE: EnemyChoreography.Pose.IDLE,
		EnemyChoreography.Beat.WINDUP: EnemyChoreography.Pose.WINDUP,
		EnemyChoreography.Beat.SLAM: EnemyChoreography.Pose.SLAM,
		EnemyChoreography.Beat.GROUND_WAIT: EnemyChoreography.Pose.IDLE,
		EnemyChoreography.Beat.FEINT_START: EnemyChoreography.Pose.LUNGE,
		EnemyChoreography.Beat.FEINT_HOLD: EnemyChoreography.Pose.WINDUP,
		EnemyChoreography.Beat.LUNGE: EnemyChoreography.Pose.LUNGE,
		EnemyChoreography.Beat.CONTACT: EnemyChoreography.Pose.CONTACT,
		EnemyChoreography.Beat.RECOIL: EnemyChoreography.Pose.IDLE,
		EnemyChoreography.Beat.RETURN: EnemyChoreography.Pose.IDLE,
		EnemyChoreography.Beat.AFTER: EnemyChoreography.Pose.IDLE,
		EnemyChoreography.Beat.SHOOT: EnemyChoreography.Pose.CONTACT,
		EnemyChoreography.Beat.FLIGHT: EnemyChoreography.Pose.IDLE,
	}
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		var last: Dictionary = hits[hits.size() - 1]
		var end := float(last.at_ms) + float(last.close_ms) + float(_visuals.contact_after_close_ms) \
				+ float(_visuals.slam_hold_ms) + float(_visuals.return_ms) + 300.0
		var seen: Dictionary = {}
		var key := ""
		var run_from := 0.0
		var previous := {}
		var t := -50.0
		while t <= end:
			var s := EnemyChoreography.sample(hits, t, _visuals)
			var label := "%s at %.0f ms" % [a.name, t]
			assert_eq(int(s.pose), int(pose_of[int(s.beat)]), label + ": the pose the beat names")
			assert_between(float(s.beat_u), 0.0, 1.0, label)
			var now_key := "%d:%d" % [int(s.hit), int(s.beat)]
			if now_key != key:
				assert_false(seen.has(now_key), label + ": beat %s comes back" % now_key)
				seen[now_key] = true
				# Samples are 1 ms apart: a run starts less than 1 ms after its beat began.
				assert_lt(float(s.beat_ms), 1.0, label + ": a new beat starts near 0 ms")
				if not previous.is_empty() and float(previous.beat_len_ms) >= 0.0:
					var run := t - run_from
					assert_almost_eq(run, float(previous.beat_len_ms), 1.0, label + ": the run matched beat " + key)
				key = now_key
				run_from = t
			else:
				assert_true(float(s.beat_ms) >= float(previous.beat_ms), label + ": beat_ms never goes back")
				# Before the clock there is no beat start to count from.
				if int(s.beat) != EnemyChoreography.Beat.BEFORE:
					assert_almost_eq(float(s.beat_ms) - float(previous.beat_ms), 1.0, EPS, label + ": beat_ms is elapsed time")
				assert_eq(float(s.beat_len_ms), float(previous.beat_len_ms), label + ": one length per beat")
			previous = s
			t += 1.0
		assert_eq(int(previous.beat), EnemyChoreography.Beat.AFTER, a.name + ": ends after the attack")
