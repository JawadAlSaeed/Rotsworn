extends GutTest
## Every defence press shows its move (card #309): a press that defends nothing (early, late, the
## wrong button, locked out, nothing left to defend, or still in the lead-in) plays the jump, dodge
## or parry on the pressing player's targeted heroes anyway, without touching judging. A move still
## playing is never cut short, a hit that lands always replaces it (from where the body was), and a
## jump that starts in the air carries on from that height.

const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const HERO_PATH := "res://data/characters/alder.tres"
const OUT_SHARE: float = TimedSequenceRunner.DODGE_OUT_SHARE
const BACK_SHARE: float = TimedSequenceRunner.DODGE_BACK_SHARE
const HERO: int = 10
## The one hit of the test attack: a ground wave at 1000 ms, jumpable from 150 ms before to 100 ms
## after (attack time, microseconds).
const IMPACT_MS: int = 1000
const IMPACT_US: int = IMPACT_MS * 1000
const OPEN_US: int = -150_000
const CLOSE_US: int = 100_000
const DEVICE: int = PlayerRoster.KEYBOARD

var _visuals: CombatVisuals
var _tuning: Tuning


func before_all() -> void:
	_visuals = load(VISUALS_PATH) as CombatVisuals
	_tuning = load(TUNING_PATH) as Tuning


# --- the moves (PartyAnim, pure) ----------------------------------------------------------------

func test_a_missed_jump_leaves_the_floor_and_lands() -> void:
	var t := 300_000
	var jump := PartyAnim.missed(Defense.Outcome.JUMP, t, _visuals)
	assert_eq(int(jump.kind), TimedSequenceRunner.Anim.JUMP, "a real jump, not a crouch on the spot")
	assert_true(bool(jump.get("missed", false)))
	var air := _visuals.jump_airtime_ms * 1000
	assert_eq(int(jump.until_us) - t, air, "the whole airtime")
	assert_eq(int(jump.apex_us) - t, _visuals.jump_airtime_ms * 500, "the apex half way: aimed at no hit")
	assert_eq(PartyAnim.lift(jump, t), 0.0, "takes off from the floor")
	assert_gt(PartyAnim.lift(jump, t + _visuals.jump_airtime_ms * 250), 0.5, "well up on the way")
	assert_almost_eq(PartyAnim.lift(jump, int(jump.apex_us)), 1.0, 0.001, "full height at the apex")
	assert_lt(PartyAnim.lift(jump, int(jump.until_us) - 1000), 0.05, "nearly down just before landing")
	assert_eq(PartyAnim.lift(jump, int(jump.until_us)), 0.0, "on the floor once over")


func test_a_missed_dodge_slides_out_and_back() -> void:
	var t := 500_000
	var dodge := PartyAnim.missed(Defense.Outcome.DODGE, t, _visuals)
	assert_eq(int(dodge.kind), TimedSequenceRunner.Anim.DODGE, "a real dodge, not a lean on the spot")
	assert_true(bool(dodge.get("missed", false)))
	var length := _visuals.dodge_pose_min_ms * 1000
	assert_eq(int(dodge.until_us) - t, length)
	assert_eq(PartyAnim.slide(dodge, t, OUT_SHARE, BACK_SHARE), 0.0, "starts on the spot")
	assert_almost_eq(PartyAnim.slide(dodge, t + _visuals.dodge_pose_min_ms * 500, OUT_SHARE, BACK_SHARE), 1.0, 0.001, "out in the middle")
	assert_lt(PartyAnim.slide(dodge, int(dodge.until_us) - 1000, OUT_SHARE, BACK_SHARE), 0.05, "back at the end")
	assert_eq(PartyAnim.lift(dodge, t + _visuals.dodge_pose_min_ms * 500), 0.0, "a dodge stays on the floor")


func test_a_missed_parry_raises_the_guard_and_never_shows_its_hit() -> void:
	var t := 700_000
	var parry := PartyAnim.missed(Defense.Outcome.PARRY, t, _visuals)
	assert_eq(int(parry.frame), FighterView.CharPose.PARRY)
	assert_eq(int(parry.until_us) - t, _visuals.whiff_pose_ms * 1000)
	var clips := SpriteClips.new()
	clips.frame_size = Vector2i(8, 8)
	clips.hframes = 8
	clips.vframes = 8
	clips.clips = {"parry": PackedInt32Array([8, 2]), "parry_hit": PackedInt32Array([9, 10, 2])}
	var count := EnemyAnim.counter(clips)
	assert_eq(String(PartyAnim.pick(parry, t, count, OUT_SHARE, BACK_SHARE).clip), "parry", "the guard goes up at the press")
	for at: int in range(t, int(parry.until_us), 10_000):
		assert_eq(String(PartyAnim.pick(parry, at, count, OUT_SHARE, BACK_SHARE).clip), "parry",
				"never the clang frames (%d us)" % at)
	assert_eq(PartyAnim.lift(parry, t + 50_000), 0.0)
	assert_eq(PartyAnim.slide(parry, t + 50_000, OUT_SHARE, BACK_SHARE), 0.0)


func test_only_the_defence_buttons_have_a_missed_move() -> void:
	assert_true(PartyAnim.missed(Defense.Outcome.PRESS, 0, _visuals).is_empty(), "a skill press is not a defence")
	assert_true(PartyAnim.missed(Defense.Outcome.NONE, 0, _visuals).is_empty())
	assert_true(PartyAnim.defence(Defense.Outcome.NONE, 0, 100_000, 50_000, _visuals).is_empty())


func test_a_successful_defence_keeps_its_spans() -> void:
	# Pressed 60 ms before the impact, late edge 100 ms.
	var t := IMPACT_US - 60_000
	var parry := PartyAnim.defence(Defense.Outcome.PARRY, t, IMPACT_US, CLOSE_US, _visuals)
	assert_eq(int(parry.until_us), maxi(IMPACT_US + CLOSE_US, t + _visuals.parry_pose_min_ms * 1000))
	assert_eq(int(parry.contact_us), IMPACT_US, "contact at the impact")
	assert_false(parry.has("missed"))
	var dodge := PartyAnim.defence(Defense.Outcome.DODGE, t, IMPACT_US, CLOSE_US, _visuals)
	assert_eq(int(dodge.until_us), maxi(IMPACT_US + CLOSE_US, t + _visuals.dodge_pose_min_ms * 1000))
	var late := PartyAnim.defence(Defense.Outcome.PARRY, IMPACT_US + 30_000, IMPACT_US, CLOSE_US, _visuals)
	assert_eq(int(late.contact_us), IMPACT_US + 30_000, "a press after the impact: contact at the press")
	# A jump pressed with time to spare: the apex at the impact; contact once the body is clear.
	var early := IMPACT_US - 200_000
	var jump := PartyAnim.defence(Defense.Outcome.JUMP, early, IMPACT_US, CLOSE_US, _visuals)
	var rise := clampi(200_000, _visuals.jump_rise_fast_ms * 1000, _visuals.jump_airtime_ms * 500)
	assert_eq(int(jump.apex_us), early + rise)
	assert_eq(int(jump.land_us), early + rise + maxi(_visuals.jump_airtime_ms * 1000 - rise, _visuals.jump_rise_fast_ms * 1000))
	assert_eq(int(jump.until_us), int(jump.land_us))
	var clear := early + roundi(float(rise) * (1.0 - sqrt(1.0 - TimedSequenceRunner.JUMP_CLEAR_HEIGHT)))
	assert_eq(int(jump.contact_us), maxi(IMPACT_US, clear))
	assert_almost_eq(PartyAnim.lift(jump, int(jump.apex_us)), 1.0, 0.001)
	# Pressed at the impact: the fastest rise.
	var quick := PartyAnim.defence(Defense.Outcome.JUMP, IMPACT_US, IMPACT_US, CLOSE_US, _visuals)
	assert_eq(int(quick.apex_us) - IMPACT_US, _visuals.jump_rise_fast_ms * 1000)


func test_a_jump_from_the_air_carries_on_from_its_height() -> void:
	var t := 2_000_000
	var jump := PartyAnim.defence(Defense.Outcome.JUMP, t, t + 200_000, CLOSE_US, _visuals, 0.8)
	assert_almost_eq(PartyAnim.lift(jump, t), 0.8, 0.001, "no drop to the floor first")
	assert_almost_eq(PartyAnim.lift(jump, int(jump.apex_us)), 1.0, 0.001)
	assert_eq(int(jump.contact_us), t + 200_000, "already clear of the wave: contact at the impact")
	var last := 0.8
	for at: int in range(t, int(jump.apex_us), 10_000):
		var y := PartyAnim.lift(jump, at)
		assert_true(y >= last - 0.0001, "keeps rising (%d us)" % at)
		last = y


func test_a_flinch_falls_and_eases_back_from_where_the_hit_caught_it() -> void:
	var hurt := {"kind": TimedSequenceRunner.Anim.HURT, "frame": FighterView.CharPose.HURT, "from_us": 0,
			"until_us": 320_000, "heavy": false, "lift": 0.9, "slide": 0.5}
	assert_almost_eq(PartyAnim.lift(hurt, 0), 0.9, 0.001, "starts at the height it was caught at")
	assert_almost_eq(PartyAnim.slide(hurt, 0, OUT_SHARE, BACK_SHARE), 0.5, 0.001, "and where it had slid to")
	var high := 1.0
	var out := 1.0
	for at: int in range(0, 320_000, 10_000):
		var y := PartyAnim.lift(hurt, at)
		var x := PartyAnim.slide(hurt, at, OUT_SHARE, BACK_SHARE)
		assert_true(y <= high + 0.0001 and x <= out + 0.0001, "only ever comes down and back (%d us)" % at)
		high = y
		out = x
	assert_lt(PartyAnim.lift(hurt, 319_000), 0.05, "on the floor by the end of the flinch")
	assert_eq(PartyAnim.lift(hurt, 320_000), 0.0)
	var plain := hurt.duplicate()
	plain.erase("lift")
	plain.erase("slide")
	assert_eq(PartyAnim.lift(plain, 100_000), 0.0, "a flinch on the floor stays there")
	assert_eq(PartyAnim.slide(plain, 100_000, OUT_SHARE, BACK_SHARE), 0.0)


func test_a_pose_that_takes_over_starts_from_where_the_body_is() -> void:
	var t := 3_000_000
	# A parry caught in the air comes down through its stance.
	var parry := PartyAnim.defence(Defense.Outcome.PARRY, t, t + 50_000, CLOSE_US, _visuals, 0.7, 0.4)
	assert_almost_eq(PartyAnim.lift(parry, t), 0.7, 0.001)
	assert_almost_eq(PartyAnim.slide(parry, t, OUT_SHARE, BACK_SHARE), 0.4, 0.001)
	assert_lt(PartyAnim.lift(parry, int(parry.until_us) - 1000), 0.05, "down by the end")
	# A dodge from mid-slide slides on out from there, then comes back as usual.
	var dodge := PartyAnim.defence(Defense.Outcome.DODGE, t, t + 50_000, CLOSE_US, _visuals, 0.0, 0.6)
	assert_almost_eq(PartyAnim.slide(dodge, t, OUT_SHARE, BACK_SHARE), 0.6, 0.001, "no snap back to the spot")
	assert_eq(int(dodge.until_us) - t, _visuals.dodge_pose_min_ms * 1000)
	assert_almost_eq(PartyAnim.slide(dodge, t + _visuals.dodge_pose_min_ms * 500, OUT_SHARE, BACK_SHARE), 1.0, 0.001)
	assert_lt(PartyAnim.slide(dodge, int(dodge.until_us) - 1000, OUT_SHARE, BACK_SHARE), 0.05)
	# A jump from mid-slide rises while it eases back to the spot.
	var jump := PartyAnim.defence(Defense.Outcome.JUMP, t, t + 200_000, CLOSE_US, _visuals, 0.0, 0.5)
	assert_almost_eq(PartyAnim.slide(jump, t, OUT_SHARE, BACK_SHARE), 0.5, 0.001)
	assert_eq(PartyAnim.lift(jump, t), 0.0)
	# A fresh pose starts on the spot, exactly as before.
	var fresh := PartyAnim.defence(Defense.Outcome.PARRY, t, t + 50_000, CLOSE_US, _visuals)
	assert_eq(PartyAnim.lift(fresh, t + 10_000), 0.0)
	assert_eq(PartyAnim.slide(fresh, t + 10_000, OUT_SHARE, BACK_SHARE), 0.0)


# --- the runner: every press, the judge untouched -----------------------------------------------

## A runner in the middle of the test attack (its clock started at real time `clock_us`), with
## hero HERO targeted and alive. `pending`: the engine still waits for the hit's prompt, so the hit
## lands when it expires.
func _runner(clock_us: int, pending: bool = false) -> TimedSequenceRunner:
	var view := CombatView.new()
	add_child_autofree(view)
	view._visuals = _visuals
	view.camera = CombatCamera.new()
	view.camera.setup(_visuals)
	view.add_child(view.camera)
	view.add_fighter(HERO, true, 0, load(HERO_PATH) as CharacterData)
	var hud := CombatHud.new()
	add_child_autofree(hud)
	hud.setup(view, _visuals, _tuning)
	var mirror := CombatMirror.new()
	mirror.fighters = {HERO: {"alive": true, "max_hp": 100, "hp": 100}}
	mirror.party_ids.assign([HERO])
	if pending:
		mirror.sequence = {"seq": 0, "states": [CombatEngine.PromptState.PENDING]}
	var prompts: Array = [{"idx": 0, "hit": 0, "character": HERO, "at_ms": IMPACT_MS, "damage": 5,
			"windows": {Defense.Outcome.JUMP: [OPEN_US, CLOSE_US]}}]
	var runner: TimedSequenceRunner = autofree(TimedSequenceRunner.new())
	runner._submit = func(_command: Dictionary) -> Array[Dictionary]: return [] as Array[Dictionary]
	runner._apply_now = func(_event: Dictionary) -> void: pass
	runner._mirror = mirror
	runner._view = view
	runner._hud = hud
	runner._tuning = _tuning
	runner._visuals = _visuals
	runner._options = CombatOptions.new()
	runner._seq = 0
	runner._prompts = prompts
	runner._hits = [{"at_ms": IMPACT_MS, "kind": AttackHitData.Kind.GROUND}]
	runner._targets.assign([HERO])
	# The judge works with no lag compensation and the press device adds none, so attack times
	# here are exactly the judged times whatever this machine's calibration.
	runner._latency_ms = PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.input_kind_of_device(DEVICE))
	runner._judges = JudgeSet.new(_tuning.whiff_lockout_ms, 0, _tuning.press_reach_back_max_ms, _tuning.late_press_report_ms)
	runner._judges.set_prompts(prompts, {})
	runner._clock.start(clock_us)
	runner._active = true
	return runner


## A clock start well in the past, so every press stamp is before the real-time hit-stop a landed
## hit starts (the freeze never covers a test press).
func _clock_start() -> int:
	return Time.get_ticks_usec() - 10_000_000


## Presses `action` at attack time `t_us` the way DefenseInput delivers it.
func _press(runner: TimedSequenceRunner, clock_us: int, action: int, t_us: int) -> Dictionary:
	var reports: Array[Dictionary] = []
	var catch := func(_action: int, report: Dictionary) -> void: reports.append(report)
	runner.press_judged.connect(catch)
	runner._on_pressed(action, clock_us + t_us, 0, DEVICE)
	runner.press_judged.disconnect(catch)
	return reports[0] if not reports.is_empty() else {}


func test_an_early_jump_still_jumps() -> void:
	var clock := _clock_start()
	var runner := _runner(clock)
	var report := _press(runner, clock, Defense.Outcome.JUMP, 300_000)
	assert_eq(int(report.result), DefenseJudge.Result.WHIFF, "judged exactly as before: a whiff")
	assert_eq(int(report.reason), DefenseJudge.Reason.EARLY)
	var anim: Dictionary = runner._anims.get(HERO, {})
	assert_eq(int(anim.get("kind", -1)), TimedSequenceRunner.Anim.JUMP, "the hero jumps (card #309)")
	assert_eq(int(anim.from_us), 300_000)
	assert_gt(PartyAnim.lift(anim, 400_000), 0.5, "off the floor")
	assert_true(runner._judges.is_locked_out(0, 400_000), "the whiff lockout is untouched")


func test_every_press_shows_its_move_and_none_is_cut_short() -> void:
	var clock := _clock_start()
	var runner := _runner(clock, true)
	# An early jump: a whiff, and the hero jumps.
	_press(runner, clock, Defense.Outcome.JUMP, 300_000)
	var jump: Dictionary = runner._anims[HERO]
	# Locked out while in the air: the jump goes on (a double tap never drops a jumper).
	var locked := _press(runner, clock, Defense.Outcome.DODGE, 400_000)
	assert_eq(int(locked.result), DefenseJudge.Result.LOCKED)
	assert_eq(runner._anims[HERO], jump, "the jump is not cut short")
	# After the landing, the wrong button: a whiff, and the guard goes up.
	var wrong := _press(runner, clock, Defense.Outcome.PARRY, 790_000)
	assert_eq(int(wrong.result), DefenseJudge.Result.WHIFF)
	assert_eq(int(wrong.reason), DefenseJudge.Reason.WRONG_ACTION)
	var parry: Dictionary = runner._anims[HERO]
	assert_eq(int(parry.kind), TimedSequenceRunner.Anim.WHIFF)
	assert_eq(int(parry.frame), FighterView.CharPose.PARRY)
	assert_eq(int(parry.from_us), 790_000)
	# Locked out again once the guard is down: the press still shows its move.
	var dodge_at := 790_000 + _visuals.whiff_pose_ms * 1000 + 10_000
	assert_lt(dodge_at, IMPACT_US + CLOSE_US, "still before the hit lands")
	var locked_again := _press(runner, clock, Defense.Outcome.DODGE, dodge_at)
	assert_eq(int(locked_again.result), DefenseJudge.Result.LOCKED)
	var dodge: Dictionary = runner._anims[HERO]
	assert_eq(int(dodge.kind), TimedSequenceRunner.Anim.DODGE, "a locked-out press dodges too")
	assert_eq(int(dodge.from_us), dodge_at)
	assert_true(runner._press_times.size() == 4, "every press was judged, none skipped")
	# The hit lands mid-slide: the flinch wins, knocked on from where the slide had got to.
	var land_at := IMPACT_US + CLOSE_US + 1000
	runner._expire(land_at)
	var hurt: Dictionary = runner._anims[HERO]
	assert_eq(int(hurt.kind), TimedSequenceRunner.Anim.HURT, "the hit reaction replaces the move")
	assert_almost_eq(float(hurt.slide), PartyAnim.slide(dodge, land_at, OUT_SHARE, BACK_SHARE), 0.0001)
	assert_gt(float(hurt.slide), 0.0)
	# A press during the flinch keeps the flinch.
	_press(runner, clock, Defense.Outcome.JUMP, land_at + 20_000)
	assert_eq(int((runner._anims[HERO] as Dictionary).kind), TimedSequenceRunner.Anim.HURT, "the hit is what happened")


func test_a_hit_on_a_hero_in_the_air_drops_them_through_the_flinch() -> void:
	var clock := _clock_start()
	var runner := _runner(clock, true)
	# Pressed just before the window opens: EARLY, and still in the air when the hit lands.
	var t := IMPACT_US + OPEN_US - 50_000
	var report := _press(runner, clock, Defense.Outcome.JUMP, t)
	assert_eq(int(report.reason), DefenseJudge.Reason.EARLY)
	var jump: Dictionary = runner._anims[HERO]
	var land_at := IMPACT_US + CLOSE_US + 1000
	assert_lt(land_at, int(jump.until_us), "still in the air when the hit lands")
	runner._expire(land_at)
	var hurt: Dictionary = runner._anims[HERO]
	assert_eq(int(hurt.kind), TimedSequenceRunner.Anim.HURT)
	assert_almost_eq(PartyAnim.lift(hurt, land_at), PartyAnim.lift(jump, land_at), 0.0001, "no snap to the floor")
	assert_gt(float(hurt.lift), 0.0)
	assert_eq(PartyAnim.lift(hurt, int(hurt.until_us)), 0.0, "down by the end of the flinch")


func test_a_press_with_nothing_left_to_defend_still_moves() -> void:
	var clock := _clock_start()
	var runner := _runner(clock)
	runner._judges.resolve_all_remaining()
	var report := _press(runner, clock, Defense.Outcome.DODGE, 2_000_000)
	assert_eq(int(report.result), DefenseJudge.Result.DONE)
	assert_eq(int((runner._anims.get(HERO, {}) as Dictionary).get("kind", -1)), TimedSequenceRunner.Anim.DODGE)


func test_a_press_during_the_lead_in_moves_but_is_not_judged() -> void:
	var runner := _runner(0)
	runner._clock = AttackClock.new()
	var lead_in_end := Time.get_ticks_usec() + 600_000
	runner._lead_in_end_us = lead_in_end
	var judged: Array[int] = []
	var catch := func(action: int, _report: Dictionary) -> void: judged.append(action)
	runner.press_judged.connect(catch)
	runner._on_pressed(Defense.Outcome.JUMP, lead_in_end - 200_000, 0, DEVICE)
	runner.press_judged.disconnect(catch)
	var anim: Dictionary = runner._anims.get(HERO, {})
	assert_eq(int(anim.get("kind", -1)), TimedSequenceRunner.Anim.JUMP, "the banner is up, the hero still jumps")
	assert_eq(int(anim.from_us), -200_000, "on the lead-in's attack time, running into the clock's")
	assert_true(judged.is_empty(), "nothing judged")
	assert_true(runner._press_times.is_empty())
	assert_false(runner._judges.is_locked_out(0, 0), "no lockout")


func test_only_the_pressing_players_living_targets_move() -> void:
	var runner: TimedSequenceRunner = autofree(TimedSequenceRunner.new())
	runner._visuals = _visuals
	var mirror := CombatMirror.new()
	mirror.fighters = {10: {"alive": true}, 11: {"alive": true}, 12: {"alive": false}, 13: {"alive": true}}
	runner._mirror = mirror
	runner._targets.assign([10, 11, 12])
	runner._owners = {10: 0, 11: 1, 12: 0, 13: 0}
	runner._show_press_pose(Defense.Outcome.JUMP, 100_000, 0)
	assert_true(runner._anims.has(10), "player 0's targeted hero")
	assert_false(runner._anims.has(11), "another player's hero")
	assert_false(runner._anims.has(12), "a downed hero")
	assert_false(runner._anims.has(13), "a hero this attack does not target")


func test_a_successful_jump_from_a_missed_one_carries_on_in_the_air() -> void:
	var runner: TimedSequenceRunner = autofree(TimedSequenceRunner.new())
	runner._visuals = _visuals
	assert_true(runner._start_press_anim(HERO, Defense.Outcome.JUMP, 0))
	var missed: Dictionary = runner._anims[HERO]
	var t := _visuals.jump_airtime_ms * 600
	var before := PartyAnim.lift(missed, t)
	assert_gt(before, 0.3, "still well up")
	assert_false(runner._start_press_anim(HERO, Defense.Outcome.PARRY, t), "a missed move is not cut short")
	runner._start_defence_anim(HERO, Defense.Outcome.JUMP, t, t + 100_000, CLOSE_US)
	var jump: Dictionary = runner._anims[HERO]
	assert_false(jump.has("missed"), "a defended jump takes over")
	assert_almost_eq(PartyAnim.lift(jump, t), before, 0.0001, "from the height it was at")
	assert_true(runner._start_press_anim(HERO, Defense.Outcome.PARRY, int(jump.until_us)), "free again once landed")


func test_a_defence_after_a_missed_dodge_takes_over_mid_slide() -> void:
	var runner: TimedSequenceRunner = autofree(TimedSequenceRunner.new())
	runner._visuals = _visuals
	assert_true(runner._start_press_anim(HERO, Defense.Outcome.DODGE, 0))
	var missed: Dictionary = runner._anims[HERO]
	var t := _visuals.dodge_pose_min_ms * 500
	var out := PartyAnim.slide(missed, t, OUT_SHARE, BACK_SHARE)
	assert_gt(out, 0.5, "out on the slide")
	runner._start_defence_anim(HERO, Defense.Outcome.PARRY, t, t + 30_000, CLOSE_US)
	var parry: Dictionary = runner._anims[HERO]
	assert_eq(int(parry.kind), TimedSequenceRunner.Anim.PARRY)
	assert_almost_eq(PartyAnim.slide(parry, t, OUT_SHARE, BACK_SHARE), out, 0.0001, "no snap back to the spot")
