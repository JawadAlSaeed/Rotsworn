extends GutTest
## Every defence press shows its move (card #309): a press that defends nothing (early, late, the
## wrong button, locked out, nothing left to defend, or still in the lead-in) plays the jump, dodge
## or parry on the pressing player's targeted heroes anyway, without touching judging. A move still
## playing is never cut short, a hit that lands always replaces it (from where the body was), and a
## jump that starts in the air carries on from that height. Code review: a press during a hit-stop
## poses at the time on screen (judged at the shifted time), a hero with nothing left to defend gets
## no move the hand-back would cut off, and in an each-in-turn attack only the hero the hit strikes
## moves.

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
## The second hero (another player's in the co-op tests) and the pad its player presses on.
const OTHER: int = 11
const PAD: int = 0

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
	var prompts: Array = [{"idx": 0, "hit": 0, "character": HERO, "at_ms": IMPACT_MS, "damage": 5,
			"windows": {Defense.Outcome.JUMP: [OPEN_US, CLOSE_US]}}]
	var hits: Array = [{"at_ms": IMPACT_MS, "kind": AttackHitData.Kind.GROUND, "close_ms": float(CLOSE_US) / 1000.0}]
	var heroes: Array[int] = [HERO]
	return _runner_for(clock_us, heroes, prompts, hits, {}, pending)


## A runner like _runner() with these heroes (all targeted and alive), prompts and hits. `owners`
## maps a hero to its player (empty: all player 0); with two players player 0 presses on PAD and
## player 1 on DEVICE (the keyboard). `pending`: the engine still waits for every prompt.
func _runner_for(clock_us: int, heroes: Array[int], prompts: Array, hits: Array, owners: Dictionary = {},
		pending: bool = false) -> TimedSequenceRunner:
	var view := CombatView.new()
	add_child_autofree(view)
	view._visuals = _visuals
	view.camera = CombatCamera.new()
	view.camera.setup(_visuals)
	view.add_child(view.camera)
	for slot: int in heroes.size():
		view.add_fighter(heroes[slot], true, slot, load(HERO_PATH) as CharacterData)
	var hud := CombatHud.new()
	add_child_autofree(hud)
	hud.setup(view, _visuals, _tuning)
	var mirror := CombatMirror.new()
	for id: int in heroes:
		mirror.fighters[id] = {"alive": true, "max_hp": 100, "hp": 100}
	mirror.party_ids.assign(heroes)
	if pending:
		var states: Array = []
		for _prompt: Dictionary in prompts:
			states.append(CombatEngine.PromptState.PENDING)
		mirror.sequence = {"seq": 0, "states": states}
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
	runner._hits = hits
	runner._targets.assign(heroes)
	runner._owners = owners
	var players: Array[int] = []
	for id: int in owners:
		if not players.has(int(owners[id])):
			players.append(int(owners[id]))
	if players.size() > 1:
		var roster := PlayerRoster.solo(heroes.size(), PAD)
		roster.devices = [PAD, DEVICE]
		runner._roster = roster
	# Who each hit strikes, as start() lays it out.
	for i: int in hits.size():
		runner._hit_targets.append([] as Array[int])
	for prompt: Dictionary in prompts:
		(runner._hit_targets[int(prompt.hit)] as Array[int]).append(int(prompt.character))
	# The judge works with no lag compensation and the press device adds none, so attack times
	# here are exactly the judged times whatever this machine's calibration.
	runner._latency_ms = PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.input_kind_of_device(DEVICE))
	runner._judges = JudgeSet.new(_tuning.whiff_lockout_ms, 0, _tuning.press_reach_back_max_ms, _tuning.late_press_report_ms)
	runner._judges.set_prompts(prompts, owners)
	runner._clock.start(clock_us)
	runner._active = true
	return runner


## A clock start well in the past, so every press stamp is before the real-time hit-stop a landed
## hit starts (the freeze never covers a test press). Never negative, as real timestamps never are
## (the freeze ledger relies on that), even when the test runs in the first seconds after start-up.
func _clock_start() -> int:
	return maxi(0, Time.get_ticks_usec() - 10_000_000)


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
	# Well before the attack can hand back, so the dodge is over long before.
	var report := _press(runner, clock, Defense.Outcome.DODGE, 300_000)
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
	runner._tuning = _tuning
	runner._hits = [{"at_ms": IMPACT_MS, "kind": AttackHitData.Kind.NORMAL}]
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
	var runner := _runner(_clock_start(), true)
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
	var runner := _runner(_clock_start(), true)
	assert_true(runner._start_press_anim(HERO, Defense.Outcome.DODGE, 0))
	var missed: Dictionary = runner._anims[HERO]
	var t := _visuals.dodge_pose_min_ms * 500
	var out := PartyAnim.slide(missed, t, OUT_SHARE, BACK_SHARE)
	assert_gt(out, 0.5, "out on the slide")
	runner._start_defence_anim(HERO, Defense.Outcome.PARRY, t, t + 30_000, CLOSE_US)
	var parry: Dictionary = runner._anims[HERO]
	assert_eq(int(parry.kind), TimedSequenceRunner.Anim.PARRY)
	assert_almost_eq(PartyAnim.slide(parry, t, OUT_SHARE, BACK_SHARE), out, 0.0001, "no snap back to the spot")


# --- code review: presses in a hit-stop, the hand-back, each in turn ------------------------------

func test_a_press_in_another_players_freeze_never_cuts_their_flinch_short() -> void:
	# Local co-op: HERO is player 1's (the keyboard), OTHER player 0's (a pad). Hit 0 lands on HERO;
	# while HERO still flinches, OTHER's parry freezes the shared clock for player 0, and player 1
	# mashes inside that freeze with nothing left to defend.
	var clock := _clock_start()
	var heroes: Array[int] = [HERO, OTHER]
	var prompts: Array = [
		{"idx": 0, "hit": 0, "character": HERO, "at_ms": IMPACT_MS, "damage": 5,
				"windows": {Defense.Outcome.JUMP: [OPEN_US, CLOSE_US]}},
		{"idx": 1, "hit": 1, "character": OTHER, "at_ms": IMPACT_MS * 3, "damage": 5,
				"windows": {Defense.Outcome.PARRY: [-100_000, CLOSE_US]}},
	]
	var hits: Array = [{"at_ms": IMPACT_MS, "kind": AttackHitData.Kind.GROUND, "close_ms": 100.0},
			{"at_ms": IMPACT_MS * 3, "kind": AttackHitData.Kind.NORMAL, "close_ms": 100.0}]
	var runner := _runner_for(clock, heroes, prompts, hits, {HERO: 1, OTHER: 0}, true)
	# No late-press report: the press is a plain DONE whatever the tuning says.
	runner._judges = JudgeSet.new(_tuning.whiff_lockout_ms, 0, _tuning.press_reach_back_max_ms, 0)
	runner._judges.set_prompts(prompts, runner._owners)
	runner._expire(IMPACT_US + CLOSE_US + 1000)
	var flinch: Dictionary = runner._anims[HERO]
	assert_eq(int(flinch.kind), TimedSequenceRunner.Anim.HURT, "hit 0 landed on HERO")
	# The freeze starts with 60 ms of flinch left (attack time) and lasts 110 ms; the press comes
	# 90 ms into it, so its freeze-shifted time is past the flinch while the screen still shows it.
	var freeze_t := int(flinch.until_us) - 60_000
	var others: Array[int] = [OTHER]
	runner._freeze(clock + freeze_t, 110, others)
	var judged: Array[Dictionary] = []
	var catch := func(_action: int, report: Dictionary) -> void: judged.append(report)
	runner.press_judged.connect(catch)
	runner._on_pressed(Defense.Outcome.JUMP, clock + freeze_t + 90_000, 0, DEVICE)
	runner.press_judged.disconnect(catch)
	assert_eq(judged.size(), 1, "player 1's press is judged, not dropped (card #180)")
	assert_eq(int(judged[0].result), DefenseJudge.Result.DONE)
	assert_eq(int((runner._press_times.back() as Dictionary).t), freeze_t + 90_000,
			"judged at the time it would have had without the freeze")
	assert_eq(runner._anims[HERO], flinch, "the flinch on screen is not cut short (the hit wins)")


func test_a_press_in_a_freeze_starts_its_move_frozen() -> void:
	# Solo: the hurt freeze after a last hit (nobody's) covers a press with nothing left to defend.
	var clock := _clock_start()
	var runner := _runner(clock)
	runner._judges.resolve_all_remaining()
	var freeze_t := 400_000
	var nobody: Array[int] = []
	runner._freeze(clock + freeze_t, 50, nobody)
	var report := _press(runner, clock, Defense.Outcome.DODGE, freeze_t + 30_000)
	assert_eq(int(report.result), DefenseJudge.Result.DONE)
	assert_eq(int((runner._press_times.back() as Dictionary).t), freeze_t + 30_000, "judged as if unfrozen")
	var dodge: Dictionary = runner._anims.get(HERO, {})
	assert_eq(int(dodge.get("kind", -1)), TimedSequenceRunner.Anim.DODGE)
	assert_eq(int(dodge.from_us), freeze_t, "starts at the frozen time on screen, frozen with everything else")


func test_a_hero_with_nothing_left_gets_no_move_the_hand_back_would_cut() -> void:
	var clock := _clock_start()
	var runner := _runner(clock)
	runner._judges.resolve_all_remaining()
	runner._tail_received = true
	runner._end_reason = "completed"
	var hand_back := IMPACT_US + _tuning.attack_recover_ms * 1000
	var jump_us := _visuals.jump_airtime_ms * 1000
	var dodge_us := _visuals.dodge_pose_min_ms * 1000
	assert_false(runner._start_press_anim(HERO, Defense.Outcome.JUMP, hand_back - jump_us + 10_000),
			"a jump still in the air at the hand-back never starts")
	assert_false(runner._anims.has(HERO))
	assert_true(runner._start_press_anim(HERO, Defense.Outcome.DODGE, hand_back - dodge_us - 10_000),
			"a dodge back on the spot before the hand-back plays")
	# A counter hands back sooner: counter_delay_ms after the last impact.
	var countered := _runner(clock)
	countered._judges.resolve_all_remaining()
	countered._tail_received = true
	countered._end_reason = "completed"
	countered._has_counter = true
	var dash := IMPACT_US + _tuning.counter_delay_ms * 1000
	assert_false(countered._start_press_anim(HERO, Defense.Outcome.DODGE, dash - dodge_us + 10_000),
			"never mid-slide when the counter dashes")
	assert_true(countered._start_press_anim(HERO, Defense.Outcome.DODGE, dash - dodge_us - 10_000))
	# A hero whose hit is still to come gets the move: the hit or a defence replaces it anyway.
	var waiting := _runner(clock, true)
	assert_true(waiting._start_press_anim(HERO, Defense.Outcome.JUMP, IMPACT_US + 50_000), "still pending")


func test_mashing_after_a_good_last_jump_starts_no_jump_the_hand_back_cuts() -> void:
	var clock := _clock_start()
	var runner := _runner(clock, true)
	var good := _press(runner, clock, Defense.Outcome.JUMP, IMPACT_US - 100_000)
	assert_eq(int(good.result), DefenseJudge.Result.SUCCESS)
	var jump: Dictionary = runner._anims[HERO]
	# The engine answered (the helper's submit answers nothing): the prompt is resolved and the
	# attack is over, so it hands back attack_recover_ms after the impact.
	var states: Array = runner._mirror.sequence.states
	states[0] = CombatEngine.PromptState.RESOLVED
	runner._tail_received = true
	runner._end_reason = "completed"
	var mash := int(jump.until_us) + 10_000
	assert_lt(mash, IMPACT_US + _tuning.attack_recover_ms * 1000, "mashed before the hand-back")
	var report := _press(runner, clock, Defense.Outcome.JUMP, mash)
	assert_eq(int(report.result), DefenseJudge.Result.DONE)
	assert_eq(runner._anims[HERO], jump, "no new jump that the hand-back would leave floating")


func test_each_in_turn_a_missed_press_moves_only_the_hero_its_hit_strikes() -> void:
	var clock := _clock_start()
	var heroes: Array[int] = [10, 11, 12]
	var prompts: Array = []
	var hits: Array = []
	for i: int in heroes.size():
		var at_ms := IMPACT_MS + 500 * i
		prompts.append({"idx": i, "hit": i, "character": heroes[i], "at_ms": at_ms, "damage": 5,
				"windows": {Defense.Outcome.DODGE: [OPEN_US, CLOSE_US], Defense.Outcome.PARRY: [OPEN_US, CLOSE_US]}})
		hits.append({"at_ms": at_ms, "kind": AttackHitData.Kind.NORMAL, "close_ms": 100.0})
	var runner := _runner_for(clock, heroes, prompts, hits, {}, true)
	runner._event = {"mode": EnemyAttackData.TargetMode.EACH}
	# An early dodge against hit 0 (it strikes hero 10): only hero 10 slides, as a good one would.
	var report := _press(runner, clock, Defense.Outcome.DODGE, IMPACT_US - 400_000)
	assert_eq(int(report.result), DefenseJudge.Result.WHIFF)
	assert_eq(int(report.reason), DefenseJudge.Reason.EARLY)
	assert_eq(int(report.hit), 0)
	assert_true(runner._anims.has(10), "the hero hit 0 is aimed at")
	assert_false(runner._anims.has(11), "not the hero hit 1 strikes later")
	assert_false(runner._anims.has(12), "not the hero hit 2 strikes later")
	# With no hit (locked out, nothing left, the lead-in): the hit aimed at them at that moment.
	assert_eq(runner._press_pose_heroes(0, -1, -200_000), [10] as Array[int], "in the lead-in: the first hit")
	assert_eq(runner._press_pose_heroes(0, -1, IMPACT_US + 300_000), [11] as Array[int], "hit 0 closed: hit 1")
	assert_eq(runner._press_pose_heroes(0, -1, 9_000_000), [12] as Array[int], "after the last hit: its hero")
	assert_eq(runner._press_pose_heroes(0, 2, 0), [12] as Array[int], "a whiff measured against hit 2")
	# Every other attack moves all of the player's living targets, as before.
	runner._event = {"mode": EnemyAttackData.TargetMode.PARTY}
	assert_eq(runner._press_pose_heroes(0, 0, 0), heroes)
