extends GutTest
## EnemyAnim (DESIGN 5.5, cards #60, #63 and #69): the attacking enemy's clip cells follow the
## choreography's beats on attack time. contact[0] first shows exactly at impact and the last lunge
## cell just before it; the wind-up coils then shivers; a hit-stop freezes the frame; prefixes and
## alternate limbs fall back to the plain clips; a sheet without clips shows the legacy poses.
## Uses synthetic clips and the default CombatVisuals, so art and .tres edits never break it.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const ATTACK_DIR := "res://data/enemy_attacks"
const LATENCY_MS: int = 30
const IDLE_PERIOD_MS: float = 1800.0
const IDLE_PHASE_MS: float = 250.0

var _visuals := CombatVisuals.new()


## A grid sheet whose clips use distinct cells: row 0 holds the six legacy keys (0..5).
func _clips(extra: Dictionary = {}) -> SpriteClips:
	var c := SpriteClips.new()
	c.frame_size = Vector2i(8, 8)
	c.hframes = 8
	c.vframes = 8
	c.body_width_px = 8
	c.clips = {
		"idle": PackedInt32Array([0, 6, 7, 6]),
		"windup": PackedInt32Array([8, 9, 1]),
		"windup_hold": PackedInt32Array([1, 10]),
		"lunge": PackedInt32Array([11, 12, 2]),
		"contact": PackedInt32Array([3, 13, 14]),
		"recoil": PackedInt32Array([15, 0]),
		"return": PackedInt32Array([16, 17, 0]),
		"slam": PackedInt32Array([5, 18, 19]),
		"slam_recover": PackedInt32Array([20, 0]),
	}
	c.clips.merge(extra, true)
	return c


## Hits as the runner holds them (engine-declared, with close times) for every shipped attack.
func _declared_attacks() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for file: String in DirAccess.get_files_at(ATTACK_DIR):
		if not file.ends_with(".tres"):
			continue
		var attack := load(ATTACK_DIR.path_join(file)) as EnemyAttackData
		if attack.is_support():
			continue  # A support move (card #259) has no hits to play.
		var declared := Fx.declared_attack(attack)
		var hits := EnemyChoreography.with_close_times(declared.hits as Array, declared.prompts as Array, LATENCY_MS)
		EnemyChoreography.add_hit_data(hits, attack)
		list.append({"name": attack.id, "hits": hits})
	return list


## One normal hit at `at_ms` (and more after it), as the runner holds them.
func _hit(at_ms: float, kind: int = AttackHitData.Kind.NORMAL, anim: String = "", feint: bool = false) -> Dictionary:
	return {"at_ms": at_ms, "kind": kind, "approach_ms": 200, "feint": feint, "close_ms": 120.0, "anim": anim}


func _pick(hits: Array, t_ms: float, clips: SpriteClips) -> Dictionary:
	var s := EnemyChoreography.sample(hits, t_ms, _visuals)
	return EnemyAnim.pick(s, hits, EnemyAnim.counter(clips), _visuals, t_ms, IDLE_PERIOD_MS, IDLE_PHASE_MS)


## The sheet cell a pick shows on `clips` (FighterView resolves the name the same way); -1 for the
## legacy pose.
func _cell(pick: Dictionary, clips: SpriteClips) -> int:
	var cells := ClipNames.cells(clips, String(pick.clip))
	return cells[clampi(int(pick.index), 0, cells.size() - 1)] if not cells.is_empty() else -1


## The clip a pick resolves to on `clips` ("" = legacy pose).
func _shown(pick: Dictionary, clips: SpriteClips) -> String:
	return ClipNames.resolve(clips, String(pick.clip))


func test_contact_cell_0_shows_at_impact_and_the_last_lunge_cell_just_before() -> void:
	var clips := _clips()
	var checked := 0
	for a: Dictionary in _declared_attacks():
		var hits: Array = a.hits
		for i: int in hits.size():
			var hit: Dictionary = hits[i]
			if int(hit.kind) != AttackHitData.Kind.NORMAL or EnemyChoreography.is_ranged(hit):
				continue
			var at := float(hit.at_ms)
			var label := "%s hit %d" % [a.name, i]
			assert_eq(_cell(_pick(hits, at, clips), clips), 3, label + ": contact[0] (the connect frame) at impact")
			assert_eq(_cell(_pick(hits, at - 1.0, clips), clips), 2, label + ": the arriving lunge cell 1 ms before")
			checked += 1
	assert_gt(checked, 20, "every shipped normal hit")


func test_contact_cells_spread_over_the_hold() -> void:
	var clips := _clips()
	var hits := [_hit(1000.0)]
	var s := EnemyChoreography.sample(hits, 1000.0, _visuals)
	var hold := float(s.beat_len_ms)
	assert_eq(_cell(_pick(hits, 1000.0 + hold / 3.0 + 0.5, clips), clips), 13)
	assert_eq(_cell(_pick(hits, 1000.0 + hold - 0.5, clips), clips), 14, "the last contact cell at the end of the hold")


func test_windup_coils_then_shivers() -> void:
	var clips := _clips()
	var hits := [_hit(1000.0)]
	var coil := float(_visuals.enemy_windup_coil_ms)
	var shiver := float(_visuals.enemy_windup_shiver_ms)
	assert_eq(_cell(_pick(hits, 0.0, clips), clips), 8, "the coil starts with the wind-up")
	assert_eq(_cell(_pick(hits, coil - 1.0, clips), clips), 1, "the coil ends on the wind-up key")
	assert_eq(_shown(_pick(hits, coil, clips), clips), "windup_hold")
	assert_eq(_cell(_pick(hits, coil, clips), clips), 1, "then the held wind-up shivers")
	assert_eq(_cell(_pick(hits, coil + shiver * 0.5, clips), clips), 10)
	assert_eq(_cell(_pick(hits, coil + shiver, clips), clips), 1, "one shiver cycle every enemy_windup_shiver_ms")


func test_a_short_windup_squeezes_the_coil_into_it() -> void:
	var clips := _clips()
	var hits := [_hit(150.0)]
	# The lunge starts at 0 when approach_ms is longer than the time before impact: no wind-up.
	assert_eq(int(EnemyChoreography.sample(hits, 0.0, _visuals).beat), EnemyChoreography.Beat.LUNGE)
	hits = [_hit(320.0)]
	var s := EnemyChoreography.sample(hits, 0.0, _visuals)
	var span := float(s.beat_len_ms)
	assert_lt(span, float(_visuals.enemy_windup_coil_ms), "a wind-up shorter than the coil")
	assert_eq(_cell(_pick(hits, span - 0.5, clips), clips), 1, "the whole coil plays inside it")


func test_without_a_shiver_clip_the_coil_holds_its_last_cell() -> void:
	var clips := _clips()
	clips.clips.erase("windup_hold")
	var hits := [_hit(1000.0)]
	assert_eq(_cell(_pick(hits, float(_visuals.enemy_windup_coil_ms) + 100.0, clips), clips), 1)


func test_a_ground_hit_winds_up_with_its_own_clip_or_the_plain_one() -> void:
	var hits := [_hit(1000.0, AttackHitData.Kind.GROUND)]
	var plain := _clips()
	assert_eq(_shown(_pick(hits, 0.0, plain), plain), "windup", "windup_ground falls back to windup")
	var own := _clips({"windup_ground": PackedInt32Array([21, 22, 1])})
	assert_eq(_shown(_pick(hits, 0.0, own), own), "windup_ground")
	assert_eq(_cell(_pick(hits, 0.0, own), own), 21)


func test_slam_and_its_recovery_spread_over_their_beats() -> void:
	var clips := _clips()
	# A slow wave: the slam ends long before the wave reaches the party.
	var ground := _hit(1000.0, AttackHitData.Kind.GROUND)
	ground.approach_ms = 500
	var hits := [ground]
	var start := EnemyChoreography.motion_start(hits, 0, _visuals)
	var slam_end := start + float(_visuals.slam_hold_ms)
	assert_lt(slam_end, 1000.0)
	assert_eq(_cell(_pick(hits, start, clips), clips), 5, "slam[0] (the ground key) when the wave starts")
	assert_eq(_cell(_pick(hits, slam_end - 0.5, clips), clips), 19)
	assert_eq(int(EnemyChoreography.sample(hits, slam_end, _visuals).beat), EnemyChoreography.Beat.GROUND_WAIT)
	assert_eq(_cell(_pick(hits, slam_end, clips), clips), 20, "then it recovers while the wave travels")
	assert_eq(_cell(_pick(hits, 999.5, clips), clips), 0)


func test_a_feint_shows_the_lunge_cells_a_real_lunge_shows() -> void:
	var clips := _clips()
	var hits := [_hit(1600.0, AttackHitData.Kind.NORMAL, "", true)]
	var start := EnemyChoreography.motion_start(hits, 0, _visuals)
	var lunge_start := 1600.0 - 200.0
	var x := 0.0
	while x < 200.0 * float(_visuals.feint_portion_percent) / 100.0:
		assert_eq(_cell(_pick(hits, start + x, clips), clips), _cell(_pick(hits, lunge_start + x, clips), clips),
				"+%.0f ms" % x)
		x += 5.0
	var hold_at := start + 200.0 * float(_visuals.feint_portion_percent) / 100.0 + 1.0
	assert_eq(_shown(_pick(hits, hold_at, clips), clips), "windup_hold", "the feint's pause shivers")


func test_recoil_and_return_follow_their_progress() -> void:
	var clips := _clips()
	var hits := [_hit(900.0), _hit(1400.0)]
	var t := 900.0
	while int(EnemyChoreography.sample(hits, t, _visuals).beat) != EnemyChoreography.Beat.RECOIL:
		t += 1.0
	assert_eq(_cell(_pick(hits, t, clips), clips), 15, "recoil[0] as the recoil starts")
	t = 1400.0
	while int(EnemyChoreography.sample(hits, t, _visuals).beat) != EnemyChoreography.Beat.RETURN:
		t += 1.0
	assert_eq(_cell(_pick(hits, t, clips), clips), 16, "return[0] as the walk home starts")
	var s := EnemyChoreography.sample(hits, t, _visuals)
	assert_eq(_cell(_pick(hits, t + float(s.beat_len_ms) - 0.5, clips), clips), 0, "home on the idle key")


func test_idle_breathes_on_attack_time_before_and_after() -> void:
	var clips := _clips()
	var hits := [_hit(1000.0)]
	var after := 3000.0
	assert_eq(int(EnemyChoreography.sample(hits, after, _visuals).beat), EnemyChoreography.Beat.AFTER)
	for step: int in 12:
		var t := after + float(step) * 150.0
		var pick := _pick(hits, t, clips)
		assert_eq(String(pick.clip), "idle")
		assert_eq(int(pick.index), ClipMath.loop(4, t, IDLE_PERIOD_MS, IDLE_PHASE_MS), "at %.0f ms" % t)


func test_a_hit_stop_freezes_the_frame() -> void:
	var clips := _clips()
	var hits := [_hit(1000.0)]
	var clock := AttackClock.new()
	clock.start(0)
	# A pause starting 50 ms into the coil: real time runs on, attack time and the cell do not.
	clock.pause_for(50_000, 120_000)
	var at_pause := _pick(hits, float(clock.attack_time_us(50_000)) / 1000.0, clips)
	for real_us: int in [60_000, 100_000, 169_000]:
		var t_ms := float(clock.attack_time_us(real_us)) / 1000.0
		assert_eq(_pick(hits, t_ms, clips), at_pause, "frozen at real %d us" % real_us)
	assert_ne(_pick(hits, float(clock.attack_time_us(400_000)) / 1000.0, clips), at_pause, "moves on after the pause")


func test_a_hit_prefix_is_tried_first_then_the_plain_clip() -> void:
	var hits := [_hit(1600.0, AttackHitData.Kind.NORMAL, "belly")]
	var plain := _clips()
	assert_eq(_shown(_pick(hits, 0.0, plain), plain), "windup", "no belly_windup: the plain wind-up")
	var own := _clips({"belly_windup": PackedInt32Array([30, 31])})
	assert_eq(_shown(_pick(hits, 0.0, own), own), "belly_windup")
	var coil := float(_visuals.enemy_windup_coil_ms)
	assert_eq(_cell(_pick(hits, coil - 1.0, own), own), 31, "its own cell count spreads over the coil")
	assert_eq(_shown(_pick(hits, 1599.0, own), own), "lunge", "no belly_lunge: the plain lunge")


func test_odd_hits_try_the_alternate_limb() -> void:
	var hits := [_hit(900.0), _hit(1400.0), _hit(1900.0)]
	var plain := _clips()
	assert_eq(_shown(_pick(hits, 1399.0, plain), plain), "lunge", "no lunge_b: the plain lunge")
	var alt := _clips({"lunge_b": PackedInt32Array([40, 41, 42]), "contact_b": PackedInt32Array([43, 44])})
	assert_eq(_shown(_pick(hits, 899.0, alt), alt), "lunge", "hit 0: the first limb")
	assert_eq(_cell(_pick(hits, 1399.0, alt), alt), 42, "hit 1: the other limb")
	assert_eq(_cell(_pick(hits, 1400.0, alt), alt), 43)
	assert_eq(_shown(_pick(hits, 1899.0, alt), alt), "lunge", "hit 2: the first limb again")


func test_a_sheet_without_clips_shows_the_legacy_poses() -> void:
	var hits := [_hit(900.0), _hit(1400.0, AttackHitData.Kind.GROUND), _hit(2200.0, AttackHitData.Kind.NORMAL, "x", true)]
	for clips: SpriteClips in [null, SpriteClips.new()]:
		var t := -20.0
		while t < 3500.0:
			assert_eq(String(_pick(hits, t, clips).clip), "", "legacy pose at %.0f ms" % t)
			t += 10.0


func test_idle_beats_without_their_clip_breathe_instead() -> void:
	var clips := _clips()
	for clip: String in ["recoil", "return", "slam_recover"]:
		clips.clips.erase(clip)
	var hits := [_hit(900.0), _hit(1400.0)]
	var t := 900.0
	while int(EnemyChoreography.sample(hits, t, _visuals).beat) != EnemyChoreography.Beat.RECOIL:
		t += 1.0
	assert_eq(String(_pick(hits, t, clips).clip), "idle", "no recoil clip: the idle loop")
	assert_eq(String(_pick(hits, 899.0, clips).clip), "lunge", "the others still play")
