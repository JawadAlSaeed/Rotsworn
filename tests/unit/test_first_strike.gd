extends GutTest
## The First Strike press (DESIGN.md 8.22, cards #320 and #335): a Fight stop's fight opens, after
## its intro (the camera sweeping over the enemies), with one press ring in the middle of the fight.
## The pure judge (FirstStrikeJudge) gives First Strike for a GOOD or PERFECT press with the skill
## press windows and a normal start for an early, late, mashed or missing one; in local co-op any
## player's press counts. The ring (FirstStrikeRing) judges from DefenseInput stamps, a friend's only
## watches and shows the host's result. The engine waits for the result (CombatSetup.Opening.RING,
## the command set_opening) before the first turn, so online it reaches the friends as a fight event.
## Main rings only Fight stops. The bots keep their skill press habits on it. The tutorial and the
## glossary teach the press. Uses the shipped data; nothing touches the user's settings.

const TUNING_PATH := "res://data/tuning/tuning.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const RUN_PATH := "res://data/runs/rotten_road.tres"
const MAIN_PATH := "res://scenes/main.gd"
const TUTORIAL_PATH := "res://data/tutorial/tutorial.tres"
const HUSKS_PATH := "res://data/encounters/husk_fight.tres"
const SEEDS: int = 1000

var _tuning: Tuning
var _visuals: CombatVisuals
var _main: GDScript


func before_all() -> void:
	_main = load(MAIN_PATH) as GDScript


func before_each() -> void:
	_tuning = (load(TUNING_PATH) as Tuning).duplicate() as Tuning
	_visuals = load(VISUALS_PATH) as CombatVisuals


func _judge(players: Array[int] = [0], latency_ms: int = 0) -> FirstStrikeJudge:
	return FirstStrikeJudge.new(_tuning, players, latency_ms)


## The ring's GOOD and PERFECT edges (us, relative to its moment).
func _good() -> Array:
	return Defense.build_windows(AttackHitData.Kind.PRESS, _tuning)[Defense.Outcome.PRESS]


func _perfect() -> Array:
	return Defense.build_windows(AttackHitData.Kind.PRESS, _tuning)[Defense.Outcome.PRESS_PERFECT]


# --- judging -----------------------------------------------------------------------------------

func test_the_ring_is_judged_with_the_skill_press_windows() -> void:
	var judge := _judge()
	assert_eq(judge.moment_us(), _tuning.first_strike_ring_lead_ms * 1000, "it closes after the ring's lead")
	assert_eq(judge.windows(), Defense.build_windows(AttackHitData.Kind.PRESS, _tuning),
			"the same windows a skill press has")
	assert_gt(_tuning.first_strike_ring_lead_ms * 1000, -int(_good()[0]), "the ring shows before its window opens")
	assert_false(judge.is_decided(), "nothing decided before a press or the window's end")
	assert_eq(judge.opening(), CombatSetup.Opening.NORMAL)


func test_a_perfect_press_gives_first_strike() -> void:
	var judge := _judge()
	var report := judge.press(0, judge.moment_us())
	assert_eq(int(report.result), DefenseJudge.Result.SUCCESS)
	assert_true(judge.is_decided(), "decided at once")
	assert_eq(judge.opening(), CombatSetup.Opening.FIRST_STRIKE)
	assert_eq(judge.outcome(), Defense.Outcome.PRESS_PERFECT)
	assert_eq(judge.winner(), 0)


func test_a_good_press_gives_first_strike_too() -> void:
	var judge := _judge()
	@warning_ignore("integer_division")
	var good_only := (int(_good()[0]) + int(_perfect()[0])) / 2
	var report := judge.press(0, judge.moment_us() + good_only)
	assert_eq(int(report.result), DefenseJudge.Result.SUCCESS)
	assert_eq(judge.opening(), CombatSetup.Opening.FIRST_STRIKE)
	assert_eq(judge.outcome(), Defense.Outcome.PRESS, "GOOD, not PERFECT")


func test_an_early_press_spends_the_ring() -> void:
	var judge := _judge()
	var report := judge.press(0, judge.moment_us() + int(_good()[0]) - 50000)
	assert_eq(int(report.result), DefenseJudge.Result.WHIFF)
	assert_eq(int(report.reason), DefenseJudge.Reason.EARLY)
	assert_true(judge.is_decided(), "one press per ring: an early one decides")
	assert_eq(judge.opening(), CombatSetup.Opening.NORMAL)
	# Even right as the ring appears (lag compensation takes it before the ring): still spent.
	var at_once := _judge([0], 30)
	at_once.press(0, 1000)
	assert_true(at_once.is_decided())
	assert_eq(at_once.opening(), CombatSetup.Opening.NORMAL)
	assert_eq(int(at_once.press(0, at_once.moment_us()).result), DefenseJudge.Result.DONE, "no second try")
	assert_eq(at_once.opening(), CombatSetup.Opening.NORMAL)


func test_a_late_press_starts_normally() -> void:
	var judge := _judge()
	var report := judge.press(0, judge.moment_us() + int(_good()[1]) + 50000)
	assert_eq(int(report.result), DefenseJudge.Result.WHIFF)
	assert_eq(int(report.reason), DefenseJudge.Reason.LATE)
	assert_true(judge.is_decided())
	assert_eq(judge.opening(), CombatSetup.Opening.NORMAL)


func test_a_press_a_frame_after_the_window_passed_is_still_late() -> void:
	# The game advances the ring every frame, so the window has usually passed before a late press.
	var judge := _judge()
	assert_eq(judge.advance(judge.moment_us() + int(_good()[1]) + 16000), 1, "the window passed: MISS")
	assert_true(judge.is_decided())
	var report := judge.press(0, judge.moment_us() + int(_good()[1]) + 50000)
	assert_eq(int(report.result), DefenseJudge.Result.WHIFF, "still judged, as on a skill ring")
	assert_eq(int(report.reason), DefenseJudge.Reason.LATE)
	assert_eq(judge.opening(), CombatSetup.Opening.NORMAL, "it changes nothing")
	# Until late_press_report_ms after the moment (the lag compensation taken off first), then nothing.
	for latency: int in [0, 30]:
		var edge := _judge([0], latency)
		edge.advance(edge.moment_us() + int(_good()[1]) + 16000 + latency * 1000)
		assert_eq(edge.late_until_us(latency), edge.moment_us() + (_tuning.late_press_report_ms + latency) * 1000)
		assert_eq(int(edge.press(0, edge.late_until_us(latency)).result), DefenseJudge.Result.WHIFF,
				"lag %d: the last moment still says LATE" % latency)
		var after := _judge([0], latency)
		after.advance(after.moment_us() + int(_good()[1]) + 16000 + latency * 1000)
		assert_eq(int(after.press(0, after.late_until_us(latency) + 1).result), DefenseJudge.Result.DONE,
				"lag %d: after it, nothing" % latency)
	# A laggier device's extra counts too.
	var pad := _judge([0], 0)
	pad.advance(pad.moment_us() + int(_good()[1]) + 16000)
	assert_eq(int(pad.press(0, pad.late_until_us(40), -1, 40).result), DefenseJudge.Result.WHIFF)
	# An early press that spent the try never turns LATE.
	var early := _judge()
	early.press(0, early.moment_us() - 400000)
	assert_eq(int(early.press(0, early.moment_us() + int(_good()[1]) + 50000).result), DefenseJudge.Result.DONE)


func test_no_press_starts_normally_once_the_window_has_passed() -> void:
	var judge := _judge()
	assert_eq(judge.advance(judge.moment_us()), 0)
	assert_eq(judge.advance(judge.moment_us() + int(_good()[1])), 0, "the window's last moment still counts")
	assert_false(judge.is_decided())
	assert_eq(judge.advance(judge.moment_us() + int(_good()[1]) + 1), 1, "one MISS")
	assert_true(judge.is_decided())
	assert_eq(judge.opening(), CombatSetup.Opening.NORMAL)
	assert_eq(judge.advance(judge.moment_us() * 2), 0, "said once")


func test_lag_compensation_moves_the_window_as_for_a_skill_press() -> void:
	var judge := _judge([0], 40)
	judge.press(0, judge.moment_us() + 40000)
	assert_eq(judge.outcome(), Defense.Outcome.PRESS_PERFECT, "a press 40 ms late on a 40 ms laggy setup is perfect")
	var pad := _judge([0], 0)
	pad.press(0, pad.moment_us() + 40000, -1, 40)
	assert_eq(pad.outcome(), Defense.Outcome.PRESS_PERFECT, "a laggier device's extra counts too")


func test_mashing_gets_no_first_strike() -> void:
	var judge := _judge()
	var t := 0
	var results: Array[int] = []
	while t < judge.moment_us() + 300000:
		results.append(int(judge.press(0, t).result))
		t += 70000
	assert_eq(results[0], DefenseJudge.Result.WHIFF, "the first press is early")
	for r: int in results.slice(1):
		assert_eq(r, DefenseJudge.Result.DONE, "the ring is spent: nothing after counts")
	assert_eq(judge.opening(), CombatSetup.Opening.NORMAL)


func test_in_local_co_op_any_players_press_counts() -> void:
	var judge := _judge([0, 1])
	judge.press(0, judge.moment_us() - 400000)
	assert_false(judge.is_decided(), "P1's early press spends only P1's try")
	assert_eq(int(judge.press(0, judge.moment_us()).result), DefenseJudge.Result.DONE, "P1 has no second try")
	judge.press(1, judge.moment_us() + int(_good()[0]) + 10000)
	assert_true(judge.is_decided())
	assert_eq(judge.opening(), CombatSetup.Opening.FIRST_STRIKE, "P2's GOOD press counts")
	assert_eq(judge.winner(), 1)
	var nobody := _judge([0, 1])
	nobody.press(0, nobody.moment_us() - 400000)
	assert_eq(nobody.advance(nobody.moment_us() + int(_good()[1]) + 1), 1, "P2's try ran out (P1's was spent)")
	assert_eq(nobody.opening(), CombatSetup.Opening.NORMAL)
	var three := _judge([0, 1, 2])
	three.press(2, three.moment_us())
	assert_eq(three.opening(), CombatSetup.Opening.FIRST_STRIKE, "P3 counts as well")
	var stranger := _judge([0])
	assert_eq(int(stranger.press(1, stranger.moment_us()).result), DefenseJudge.Result.DONE, "a player not in it")
	assert_false(stranger.is_decided())
	var none := _judge([] as Array[int])
	assert_true(none.is_decided(), "nobody may press: a normal start")
	assert_eq(none.opening(), CombatSetup.Opening.NORMAL)


func test_a_decided_ring_takes_no_more_presses() -> void:
	var judge := _judge()
	judge.press(0, judge.moment_us())
	assert_eq(int(judge.press(0, judge.moment_us() + 10000).result), DefenseJudge.Result.DONE)
	assert_eq(judge.advance(judge.moment_us() * 3), 0)
	assert_eq(judge.opening(), CombatSetup.Opening.FIRST_STRIKE, "it stays")


# --- the bots ------------------------------------------------------------------------------------

func test_the_perfect_bot_strikes_first_and_the_miss_bot_never_presses() -> void:
	var rng := RandomNumberGenerator.new()
	for mode: String in [CombatOptions.AUTOPLAY_PERFECT, CombatOptions.AUTOPLAY_ESCAPE]:
		var judge := _judge()
		var at := FirstStrikeBot.press_at(mode, 60, rng, judge.moment_us(), judge.windows())
		judge.press(0, at)
		assert_eq(judge.outcome(), Defense.Outcome.PRESS_PERFECT, mode + " presses perfectly")
	assert_eq(FirstStrikeBot.press_at(CombatOptions.AUTOPLAY_MISS, 60, rng, 1000000, _judge().windows()), -1)
	assert_false(FirstStrikeBot.mashes(CombatOptions.AUTOPLAY_MISS))
	assert_false(FirstStrikeBot.mashes(CombatOptions.AUTOPLAY_PERFECT))


func test_the_average_bot_lands_it_at_its_skill_with_its_seeded_luck() -> void:
	var windows := _judge().windows()
	var moment := _judge().moment_us()
	for skill: int in [0, 100]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for i: int in 50:
			var at := FirstStrikeBot.press_at(CombatOptions.AUTOPLAY_AVERAGE, skill, rng, moment, windows)
			assert_eq(at >= 0, skill == 100, "skill %d" % skill)
	var landed := 0
	var perfect := 0
	var picks: Array[int] = []
	for s: int in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var judge := _judge()
		var at := FirstStrikeBot.press_at(CombatOptions.AUTOPLAY_AVERAGE, 60, rng, moment, windows)
		picks.append(at)
		if at < 0:
			judge.advance(moment * 2)
			assert_eq(judge.opening(), CombatSetup.Opening.NORMAL)
			continue
		judge.press(0, at)
		assert_eq(judge.opening(), CombatSetup.Opening.FIRST_STRIKE, "every planned press lands")
		landed += 1
		if judge.outcome() == Defense.Outcome.PRESS_PERFECT:
			perfect += 1
	assert_between(landed * 100, 54 * SEEDS, 66 * SEEDS, "about 60 percent land")
	assert_between(perfect * 100, 40 * landed, 60 * landed, "half of them perfect, half good")
	for s: int in 20:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		assert_eq(FirstStrikeBot.press_at(CombatOptions.AUTOPLAY_AVERAGE, 60, rng, moment, windows), picks[s],
				"the same seed, the same luck")


func test_the_masher_is_judged_honestly() -> void:
	assert_true(FirstStrikeBot.mashes(CombatOptions.AUTOPLAY_MASH))
	assert_eq(FirstStrikeBot.press_at(CombatOptions.AUTOPLAY_MASH, 60, RandomNumberGenerator.new(), 1000000,
			_judge().windows()), -1, "it plans no press: it mashes")
	var firsts := 0
	for s: int in 300:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var judge := _judge()
		var t := FirstStrikeBot.mash_gap_us(rng)
		var first_press := -1
		while t < judge.moment_us() + 400000:
			var gap := FirstStrikeBot.mash_gap_us(rng)
			assert_between(gap, (Autoplay.MASH_INTERVAL_MS - Autoplay.MASH_JITTER_MS) * 1000,
					(Autoplay.MASH_INTERVAL_MS + Autoplay.MASH_JITTER_MS) * 1000)
			var action := FirstStrikeBot.mash_action(rng)
			assert_has(Autoplay.MASH_ACTIONS, action)
			if action == Defense.Outcome.PRESS:
				if first_press < 0:
					first_press = t
				judge.press(0, t)
			t += gap
		judge.advance(judge.moment_us() * 2)
		var rel := first_press - judge.moment_us()
		var in_window := first_press >= 0 and rel >= int(_good()[0]) and rel <= int(_good()[1])
		assert_eq(judge.opening() == CombatSetup.Opening.FIRST_STRIKE, in_window,
				"seed %d: only a first skill press inside the window counts" % s)
		if in_window:
			firsts += 1
	assert_lt(firsts * 100, 25 * 300, "mashing rarely pays")


# --- the ring itself ------------------------------------------------------------------------------

func _ring(roster: PlayerRoster, mode: FirstStrikeRing.Mode, options: CombatOptions = null) -> FirstStrikeRing:
	var ring := FirstStrikeRing.new()
	ring.setup(_tuning, _visuals, options if options != null else CombatOptions.new(), roster, mode, 7)
	add_child_autofree(ring)
	return ring


## The real time at which a press from `device` lands on ring time `rel_us` from the ring's moment
## (the ring takes off the device's lag compensation, as the game does).
func _stamp(ring: FirstStrikeRing, start_us: int, rel_us: int, device: int) -> int:
	var latency := PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.input_kind_of_device(device))
	return start_us + ring._moment_us + rel_us + latency * 1000


func test_the_ring_takes_presses_stamped_by_its_own_input() -> void:
	var ring := _ring(PlayerRoster.solo(3), FirstStrikeRing.Mode.PRESS)
	assert_not_null(ring._input, "its own DefenseInput stamps the presses (rule 3)")
	assert_false(ring._input.is_armed(), "the button is free until the ring shows")
	var said: Array = []
	ring.decided.connect(func(opening: CombatSetup.Opening, word: String) -> void: said.append([opening, word]))
	var start := Time.get_ticks_usec()
	ring._start(start)
	assert_true(ring._input.is_armed(), "the skill press button is armed while the ring shows")
	ring._on_pressed(Defense.Outcome.PRESS, _stamp(ring, start, 0, PlayerRoster.KEYBOARD), 0, PlayerRoster.KEYBOARD)
	assert_eq(ring.opening(), CombatSetup.Opening.FIRST_STRIKE)
	assert_eq(ring.word(), FirstStrikeRing.WORD_PERFECT)
	assert_eq(said, [[CombatSetup.Opening.FIRST_STRIKE, FirstStrikeRing.WORD_PERFECT]], "decided once")
	assert_false(ring._input.is_armed(), "the button goes back to the menus")
	assert_false(ring.is_finished(), "the ring holds the result a moment")
	ring._result_at_us = Time.get_ticks_usec() - (_visuals.first_strike_result_ms + 1) * 1000
	ring._process(0.0)
	assert_true(ring.is_finished(), "then the fight")


func test_an_early_press_on_the_ring_is_a_normal_start() -> void:
	var ring := _ring(PlayerRoster.solo(3), FirstStrikeRing.Mode.PRESS)
	var start := Time.get_ticks_usec()
	ring._start(start)
	ring._on_pressed(Defense.Outcome.PRESS, _stamp(ring, start, -500000, PlayerRoster.KEYBOARD), 0, PlayerRoster.KEYBOARD)
	assert_eq(ring.opening(), CombatSetup.Opening.NORMAL)
	assert_eq(ring.word(), FirstStrikeRing.WORD_EARLY)


## Moves the ring's clock so that now is `rel_us` after the end of its GOOD window (the base lag
## compensation added, as the judge takes it off) and runs one frame. Returns the clock's start.
func _frame_after_window(ring: FirstStrikeRing, rel_us: int) -> int:
	var origin := Time.get_ticks_usec() - (ring._moment_us + int(_good()[1]) + rel_us + ring._latency_ms * 1000)
	ring._clock.start(origin)
	ring._process(0.016)
	return origin


func test_a_late_press_after_the_rings_miss_says_late() -> void:
	var ring := _ring(PlayerRoster.solo(3), FirstStrikeRing.Mode.PRESS)
	var said: Array = []
	ring.decided.connect(func(opening: CombatSetup.Opening, word: String) -> void: said.append([opening, word]))
	ring._start(Time.get_ticks_usec())
	# A frame 30 ms after the window: MISS at once, as on a skill ring, and still listening.
	var origin := _frame_after_window(ring, 30000)
	assert_eq(ring.word(), FirstStrikeRing.WORD_MISS)
	assert_eq(ring.opening(), CombatSetup.Opening.NORMAL)
	assert_true(ring._input.is_armed(), "the button still takes a late press")
	assert_eq(said, [], "not told yet: a late press may still come")
	# A press 60 ms after the window: LATE, the word a skill ring gives it.
	ring._on_pressed(Defense.Outcome.PRESS, _stamp(ring, origin, int(_good()[1]) + 60000, PlayerRoster.KEYBOARD), 0,
			PlayerRoster.KEYBOARD)
	assert_eq(ring.word(), FirstStrikeRing.WORD_LATE)
	assert_eq(ring.opening(), CombatSetup.Opening.NORMAL, "still a normal start")
	assert_eq(said, [[CombatSetup.Opening.NORMAL, FirstStrikeRing.WORD_LATE]], "told once, with its word")
	assert_false(ring._input.is_armed(), "the button goes back to the menus")
	ring._on_pressed(Defense.Outcome.PRESS, _stamp(ring, origin, int(_good()[1]) + 90000, PlayerRoster.KEYBOARD), 0,
			PlayerRoster.KEYBOARD)
	assert_eq(said.size(), 1, "one word per ring")
	assert_false(ring.is_finished(), "the ring holds the result a moment")
	ring._result_at_us = Time.get_ticks_usec() - (_visuals.first_strike_result_ms + 1) * 1000
	ring._process(0.0)
	assert_true(ring.is_finished(), "then the fight")


func test_with_no_late_press_the_rings_miss_stands() -> void:
	var ring := _ring(PlayerRoster.solo(3), FirstStrikeRing.Mode.PRESS)
	var said: Array = []
	ring.decided.connect(func(opening: CombatSetup.Opening, word: String) -> void: said.append([opening, word]))
	ring._start(Time.get_ticks_usec())
	_frame_after_window(ring, 30000)
	assert_eq(said, [])
	# Once the time for a late press is over (for the laggiest device here): MISS is the word.
	var late_end := ring._judge.late_until_us(ring._late_latency_ms)
	ring._clock.start(Time.get_ticks_usec() - late_end - 1000)
	ring._process(0.016)
	assert_eq(said, [[CombatSetup.Opening.NORMAL, FirstStrikeRing.WORD_MISS]], "told once the wait is over")
	assert_false(ring._input.is_armed())
	ring._on_pressed(Defense.Outcome.PRESS, Time.get_ticks_usec(), 0, PlayerRoster.KEYBOARD)
	assert_eq(ring.word(), FirstStrikeRing.WORD_MISS, "a press after it changes nothing")
	assert_eq(said.size(), 1)
	ring._result_at_us = Time.get_ticks_usec() - (_visuals.first_strike_result_ms + 1) * 1000
	ring._process(0.0)
	assert_true(ring.is_finished())


func test_the_ring_takes_any_local_players_press() -> void:
	var roster := PlayerRoster.solo(3, 0)
	assert_eq(roster.join(1), 1)
	var ring := _ring(roster, FirstStrikeRing.Mode.PRESS)
	var start := Time.get_ticks_usec()
	ring._start(start)
	ring._on_pressed(Defense.Outcome.PRESS, _stamp(ring, start, -500000, 0), 0, 0)
	assert_eq(ring._result_at_us, 0, "P1 was early, P2 can still press")
	ring._on_pressed(Defense.Outcome.PRESS, _stamp(ring, start, int(_good()[0]) + 20000, 1), 0, 1)
	assert_eq(ring.opening(), CombatSetup.Opening.FIRST_STRIKE, "P2's pad pressed it GOOD")
	assert_eq(ring.word(), FirstStrikeRing.WORD_GOOD)


func test_the_bot_presses_the_ring_through_its_input() -> void:
	var options := CombatOptions.new()
	options.autoplay_mode = CombatOptions.AUTOPLAY_PERFECT
	var ring := _ring(PlayerRoster.solo(3), FirstStrikeRing.Mode.PRESS, options)
	ring._start(Time.get_ticks_usec())
	assert_eq(ring._bot_presses.size(), 1, "one planned press")
	var at := int(ring._bot_presses[0])
	# The bot presses half a frame early: well before that (whatever this frame took), not yet.
	@warning_ignore("integer_division")
	var lead := int(ring.get_process_delta_time() * 1000000.0) / 2
	ring._press_bots(at - lead - 100000)
	assert_eq(ring._result_at_us, 0, "not yet")
	# The bot presses through DefenseInput, stamped now: the ring's clock is moved back so that now is
	# the planned moment (plus the lag compensation the judge takes off).
	ring._clock.start(Time.get_ticks_usec() - at - ring._latency_ms * 1000)
	ring._press_bots(at + ring._latency_ms * 1000)
	assert_true(ring._bot_presses.is_empty(), "pressed")
	assert_eq(ring.opening(), CombatSetup.Opening.FIRST_STRIKE, "the perfect bot strikes first")
	options.autoplay_mode = CombatOptions.AUTOPLAY_MISS
	var idle := _ring(PlayerRoster.solo(3), FirstStrikeRing.Mode.PRESS, options)
	idle._start(Time.get_ticks_usec())
	assert_true(idle._bot_presses.is_empty() and idle._next_mash_us == 0, "the miss bot never presses")


func test_a_friend_watches_the_hosts_ring_and_shows_its_result() -> void:
	var friend := PlayerRoster.online(3, 1, 1001)
	var ring := _ring(friend, FirstStrikeRing.Mode.WATCH)
	assert_null(ring._input, "no press is taken on a friend's ring")
	assert_almost_eq(ring._ring_box.modulate.a, _visuals.first_strike_watch_alpha, 0.001, "dimmed")
	var start := Time.get_ticks_usec()
	ring._start(start)
	ring._watch(0, start)
	assert_eq(ring._result_at_us, 0, "waits for the host")
	ring.show_host_result("first_strike", FirstStrikeRing.WORD_PERFECT)
	ring._watch(1000, start)
	assert_eq(ring.opening(), CombatSetup.Opening.FIRST_STRIKE, "the host's opening")
	assert_eq(ring.word(), FirstStrikeRing.WORD_PERFECT, "and its word")
	ring.show_host_result("normal", FirstStrikeRing.WORD_MISS)
	assert_eq(ring.opening(), CombatSetup.Opening.FIRST_STRIKE, "the first result stands")
	var lost := _ring(friend, FirstStrikeRing.Mode.WATCH)
	lost._start(start)
	var wait_end := lost._moment_us + int(_good()[1]) + _tuning.net_opening_wait_ms * 1000
	lost._watch(wait_end, start)
	assert_eq(lost._result_at_us, 0, "still waiting")
	lost._watch(wait_end + 1, start)
	assert_gt(lost._result_at_us, 0, "no result came: it goes on, so the fight never hangs")
	assert_eq(lost.opening(), CombatSetup.Opening.NORMAL)


func test_the_picture_ring_starts_over() -> void:
	var ring := _ring(PlayerRoster.solo(3), FirstStrikeRing.Mode.LOOP)
	ring._start(Time.get_ticks_usec())
	ring._judge.advance(ring._moment_us * 3)
	ring._on_decided(Time.get_ticks_usec() - (_visuals.first_strike_result_ms + 1) * 1000)
	ring._process(0.0)
	assert_false(ring.is_finished(), "never done")
	assert_false(ring._started, "it starts over")


# --- the engine: a Fight stop's fight waits for its ring (card #335) ---------------------------------

func _husk_setup(opening: CombatSetup.Opening, seed_value: int = 5) -> CombatSetup:
	var data := load(RUN_PATH) as RunData
	var run := RunState.begin(data, _tuning, 7)
	return run.fight_setup(load(HUSKS_PATH) as EncounterData, seed_value, opening)


func _first(events: Array[Dictionary], type: String) -> Dictionary:
	for ev: Dictionary in events:
		if String(ev.get("type", "")) == type:
			return ev
	return {}


func _rejected(events: Array[Dictionary]) -> bool:
	return events.size() == 1 and String(events[0].type) == "command_rejected"


func test_a_ring_fight_waits_for_its_opening_before_the_first_turn() -> void:
	var engine := CombatEngine.new(_husk_setup(CombatSetup.Opening.RING))
	var start := engine.start()
	assert_eq(String(_first(start, "combat_started").opening), "ring", "the presentation knows a ring comes")
	assert_true(_first(start, "turn_started").is_empty(), "no turn before the ring's result")
	assert_eq(engine.phase, CombatEngine.Phase.AWAITING_OPENING)
	assert_false(_first(start, "intent").is_empty(), "the enemies' intents are already shown")
	assert_true(engine.resume_events().is_empty(), "a friend who gets in now is seated at the first turn")
	assert_true(_rejected(engine.submit(CombatCommands.use_ability(1, 0, "attack", [3] as Array[int]))),
			"nobody acts yet")
	var events := engine.submit(CombatCommands.set_opening("first_strike", FirstStrikeRing.WORD_PERFECT))
	assert_eq(String(events[0].type), "opening", "the result first, then the first turn")
	assert_eq(String(events[0].opening), "first_strike")
	assert_eq(String(events[0].word), FirstStrikeRing.WORD_PERFECT, "the word goes to the friends")
	assert_false(_first(events, "turn_started").is_empty())
	var order: Array = _first(events, "turn_order").order
	var party := engine.party_ids().size()
	for i: int in party:
		assert_lt(int(order[i]), party, "every hero acts before any enemy")
	assert_true(_rejected(engine.submit(CombatCommands.set_opening("normal"))), "once only")


func test_set_opening_takes_only_normal_or_first_strike_and_only_a_ring_fight() -> void:
	var engine := CombatEngine.new(_husk_setup(CombatSetup.Opening.RING))
	engine.start()
	for bad: String in ["ring", "", "first strike", "FIRST_STRIKE"]:
		assert_true(_rejected(engine.submit(CombatCommands.set_opening(bad))), "%s is refused" % bad)
		assert_eq(engine.phase, CombatEngine.Phase.AWAITING_OPENING, "and changes nothing")
	var odd := engine.submit({"type": CombatCommands.SET_OPENING, "opening": "normal", "word": 7})
	assert_eq(String(odd[0].word), "", "a word that is not text is dropped")
	var plain := CombatEngine.new(_husk_setup(CombatSetup.Opening.NORMAL))
	plain.start()
	assert_true(_rejected(plain.submit(CombatCommands.set_opening("first_strike"))), "a fight with no ring")


func test_a_ring_fight_is_deterministic_and_matches_the_old_opening() -> void:
	var commands: Array[Dictionary] = [CombatCommands.set_opening("first_strike", "GOOD")]
	var a := CombatEngine.new(_husk_setup(CombatSetup.Opening.RING, 11))
	var b := CombatEngine.new(_husk_setup(CombatSetup.Opening.RING, 11))
	var ea := a.start()
	var eb := b.start()
	for c: Dictionary in commands:
		ea.append_array(a.submit(c))
		eb.append_array(b.submit(c))
	assert_eq(ea, eb, "same seed, same commands, same events")
	var old := CombatEngine.new(_husk_setup(CombatSetup.Opening.FIRST_STRIKE, 11))
	var eo := old.start()
	assert_eq(_first(ea, "turn_order").order, _first(eo, "turn_order").order,
			"the ring's First Strike is the same turn order as a First Strike setup")
	assert_eq(_first(ea, "turn_started").actor, _first(eo, "turn_started").actor)
	var normal := CombatEngine.new(_husk_setup(CombatSetup.Opening.RING, 11))
	var en := normal.start()
	en.append_array(normal.submit(CombatCommands.set_opening("normal", "MISS")))
	var plain := CombatEngine.new(_husk_setup(CombatSetup.Opening.NORMAL, 11)).start()
	assert_eq(_first(en, "turn_order").order, _first(plain, "turn_order").order, "a miss is a normal start")


func test_a_fight_waiting_for_its_ring_survives_a_snapshot() -> void:
	var setup := _husk_setup(CombatSetup.Opening.RING)
	var engine := CombatEngine.new(setup)
	engine.start()
	var copy := CombatEngine.restore(setup, engine.snapshot())
	assert_eq(copy.phase, CombatEngine.Phase.AWAITING_OPENING)
	assert_eq(copy.submit(CombatCommands.set_opening("normal")), engine.submit(CombatCommands.set_opening("normal")))


# --- the fight: its intro, then the ring (card #335) -------------------------------------------------

func test_the_intro_sweep_goes_from_the_first_enemy_to_the_last() -> void:
	var spots := _visuals.enemy_positions.duplicate()
	var order := CameraShots.sweep_order(spots)
	for i: int in order.size() - 1:
		assert_lte(order[i].x, order[i + 1].x, "left to right")
	var shots := CameraShots.intro_sweep(_visuals, order)
	var base := CameraShots.base(_visuals)
	assert_lt((shots[0].target as Vector3).x, (shots[1].target as Vector3).x, "it pans right")
	assert_lt((shots[0].pos as Vector3).distance_to(shots[0].target), (base.pos as Vector3).distance_to(base.target),
			"closer than the base view")
	var lone := CameraShots.intro_sweep(_visuals, [Vector3(3.0, 0.0, 0.0)] as Array[Vector3])
	assert_ne(lone[0].target, lone[1].target, "a lone enemy still gets a slow pan")
	assert_eq(CameraShots.intro_sweep(_visuals, [] as Array[Vector3]), [base, base] as Array[Dictionary])
	var half := CameraShots.blend(shots[0], shots[1], 0.5)
	assert_almost_eq(half.target, ((shots[0].target as Vector3) + (shots[1].target as Vector3)) * 0.5,
			Vector3(0.001, 0.001, 0.001))
	assert_eq(CameraShots.blend(shots[0], shots[1], 2.0), shots[1], "clamped")
	assert_eq(_visuals.intro_sweep_ms, 1500, "about a second and a half (card #335)")


## A shipped fight whose intro and ring are quick: the intro sweeps `intro_ms`, the ring shows at once
## and holds its result no time.
func _ring_fight(intro_ms: int, opening: CombatSetup.Opening = CombatSetup.Opening.RING) -> CombatController:
	var look := _visuals.duplicate() as CombatVisuals
	look.intro_sweep_ms = intro_ms
	look.intro_name_fade_ms = 0
	look.first_strike_result_ms = 0
	_tuning.first_strike_ring_delay_ms = 0
	var fight := (load("res://scenes/combat.tscn") as PackedScene).instantiate() as CombatController
	fight.configure(load(HUSKS_PATH) as EncounterData, _tuning, look, CombatOptions.new(), null, opening)
	return fight


func test_the_fight_sweeps_over_the_enemies_then_rings() -> void:
	var fight := _ring_fight(400)
	var played: Array = []
	fight.opening_played.connect(func(opening: String, word: String) -> void: played.append([opening, word]))
	var covered := [true]
	fight.screen_covered = func() -> bool: return covered[0]
	add_child_autofree(fight)
	assert_true(await wait_until(func() -> bool: return not fight.mirror.enemy_ids.is_empty(), 5.0), "built")
	await wait_seconds(0.3)
	assert_true(fight.hud.intro_names().is_empty(), "the intro waits while the screen is covered")
	assert_null(fight.first_strike_ring())
	covered[0] = false
	assert_true(await wait_until(func() -> bool: return not fight.hud.intro_names().is_empty(), 2.0),
			"then the names show")
	var shown_at := Time.get_ticks_msec()
	var names := fight.hud.intro_names()
	for id: int in fight.mirror.enemy_ids:
		assert_true(names.has(String(fight.mirror.fighter(id).display_name)), "each enemy's name")
	assert_true(fight.view.camera.is_sweeping(), "while the camera sweeps")
	assert_null(fight.first_strike_ring(), "no ring during the sweep")
	assert_true(await wait_until(func() -> bool: return fight.first_strike_ring() != null, 3.0), "then the ring")
	assert_gte(Time.get_ticks_msec() - shown_at, 400 - 50, "only after the sweep")
	assert_true(fight.hud.intro_names().is_empty(), "the names went with the intro")
	var ring := fight.first_strike_ring()
	assert_true(fight.hud.is_ancestor_of(ring), "in the middle of the fight's screen")
	assert_eq(ring.mode(), FirstStrikeRing.Mode.PRESS)
	assert_eq(fight.engine.phase, CombatEngine.Phase.AWAITING_OPENING, "the first turn waits")
	assert_true(await wait_until(func() -> bool: return ring._input.is_armed(), 2.0))
	ring._input.inject_press(Defense.Outcome.PRESS, PlayerRoster.KEYBOARD)
	assert_eq(ring.word(), FirstStrikeRing.WORD_EARLY, "pressed long before its moment")
	assert_true(await wait_until(func() -> bool: return not played.is_empty(), 3.0), "the opening plays")
	assert_eq(played, [["normal", FirstStrikeRing.WORD_EARLY]], "once, with the ring's result")
	assert_ne(fight.engine.phase, CombatEngine.Phase.AWAITING_OPENING, "and the fight goes on")
	assert_null(fight.first_strike_ring(), "the ring is gone")


func test_every_other_fight_gets_the_intro_and_no_ring() -> void:
	var fight := _ring_fight(300, CombatSetup.Opening.NORMAL)
	add_child_autofree(fight)
	assert_true(await wait_until(func() -> bool: return not fight.hud.intro_names().is_empty(), 5.0), "the intro")
	assert_true(await wait_until(func() -> bool: return fight.engine.turn_number > 0 and fight.hud.intro_names().is_empty(), 3.0))
	assert_null(fight.first_strike_ring(), "no ring")
	var none := _ring_fight(0, CombatSetup.Opening.NORMAL)
	add_child_autofree(none)
	await wait_seconds(0.3)
	assert_true(none.hud.intro_names().is_empty(), "intro_sweep_ms 0: no intro")


func test_a_friends_fight_watches_the_hosts_ring() -> void:
	var fight := CombatController.new()
	fight._net_mode = CombatController.NetMode.CLIENT
	fight._visuals = _visuals
	fight._tuning = _tuning
	fight._options = CombatOptions.new()
	var hud_ring := FirstStrikeRing.new()
	hud_ring.setup(_tuning, _visuals, CombatOptions.new(), PlayerRoster.online(3, 1, 1001), FirstStrikeRing.Mode.WATCH)
	autofree(hud_ring)
	fight._opening_ring = hud_ring
	fight._take_host_opening({"type": "opening", "opening": "first_strike", "word": "GOOD"})
	assert_eq(hud_ring._host_result, {"opening": "first_strike", "word": "GOOD"}, "the watched ring shows it at once")
	fight._opening_ring = null
	fight._early_opening = {}
	fight._take_host_opening({"type": "opening", "opening": "normal", "word": "MISS"})
	assert_eq(fight._early_opening, {"opening": "normal", "word": "MISS"}, "kept for a ring not shown yet")
	fight._net_mode = CombatController.NetMode.HOST
	fight._early_opening = {}
	fight._take_host_opening({"type": "opening", "opening": "normal", "word": "MISS"})
	assert_true(fight._early_opening.is_empty(), "the host decides it")
	fight.free()
	var source := FileAccess.get_file_as_string("res://scripts/combat/presentation/combat_controller.gd")
	assert_string_contains(source, "var mode := FirstStrikeRing.Mode.WATCH if _net_mode == NetMode.CLIENT else first_strike_mode")


# --- Main: which fights ring, and where the opening goes ---------------------------------------------

func test_only_fight_stops_ring() -> void:
	for type: int in RunMap.StopType.values():
		assert_eq(_main.call("_rings_first_strike", type), type == RunMap.StopType.FIGHT,
				"%s rings: %s" % [RunMap.TYPE_NAMES[type], type == RunMap.StopType.FIGHT])
	var start := _body("func _start_stop_fight(")
	assert_string_contains(start, "_run_opening = CombatSetup.Opening.RING if ringed else CombatSetup.Opening.NORMAL")
	assert_false(_body("func _enter_stop(").contains("FirstStrikeRing"), "no ring on the name card any more")
	assert_false(_body("func _fade_to(").contains("FirstStrikeRing"))
	for header: String in ["func _start_final_fight("]:
		assert_false(_body(header).contains("FirstStrikeRing"), header + " opens normally")
		assert_false(_body(header).contains("_run_opening"), header + " never sets an opening")


func test_the_opening_goes_into_the_fights_setup() -> void:
	var combat := _body("func _start_combat(")
	assert_string_contains(combat, "_combat.configure(_encounter, _tuning, _visuals, _options, _fight_look, _run_opening, _fight_air)")
	assert_string_contains(combat, "_run_opening = CombatSetup.Opening.NORMAL", "used up by its fight")
	assert_string_contains(combat, "_combat.first_strike_bot_seed = _first_strike_bot_seed()")
	assert_string_contains(combat, "_combat.opening_played.connect(_on_fight_opening)")
	assert_string_contains(combat, "_combat.screen_covered = _transition.is_covering")
	assert_string_contains(_body("func _on_fight_opening("), "print(\"AUTOPLAY_OPENING %s stop=%d\"")
	assert_string_contains(FileAccess.get_file_as_string("res://scripts/combat/presentation/combat_controller.gd"),
			"_run.fight_setup(_encounter, _pick_seed(), _opening)", "the controller builds its setup with it")
	var setup := _husk_setup(CombatSetup.Opening.RING)
	assert_eq(setup.opening, CombatSetup.Opening.RING)
	var controller := CombatController.new()
	controller.configure(load(HUSKS_PATH) as EncounterData, _tuning, _visuals, CombatOptions.new(), null,
			CombatSetup.Opening.RING)
	assert_eq(controller._opening, CombatSetup.Opening.RING)
	controller.free()


func test_online_the_ring_comes_with_the_fight() -> void:
	assert_eq(NetSession.PROTOCOL, 9, "no bump: the fingerprint keeps other builds out; 9 is the pack's (card #332)")
	var announce := _body("func _announce_stop_fight(")
	assert_string_contains(announce, "_send_screen({\"name\": \"stop_fight\", \"seed\": _net_seed})")
	assert_string_contains(_body("func _start_stop_fight("), "_announce_stop_fight()",
			"every stop fight is announced once the host's card is done")
	var messages := _body("func _on_net_message(")
	assert_false(messages.contains("\"opening\":"), "no separate opening message: it is a fight event")
	var client := _body("func _client_screen(")
	assert_false(client.contains("FirstStrikeRing"), "a friend's card has no ring either")


# --- the words that teach it ----------------------------------------------------------------------

func test_the_tutorial_card_teaches_the_press() -> void:
	var data := load(TUTORIAL_PATH) as TutorialData
	var card: TutorialStepData = null
	for step: TutorialStepData in data.steps:
		if step.title == "First Strike":
			card = step
	assert_not_null(card)
	if card == null:
		return
	assert_string_contains(card.text, "{skill_press}", "it names the button")
	assert_string_contains(card.text, "ring")
	assert_string_contains(card.text, "Fight stop")
	assert_false(card.text.to_lower().contains("zone"), "no zones any more")
	assert_string_contains(card.tip, "GOOD or PERFECT")


func test_the_glossary_explains_the_press() -> void:
	var book := load(GlossaryScreen.GLOSSARY_PATH) as GlossaryData
	var entry := book.find("first_strike")
	assert_not_null(entry)
	if entry == null:
		return
	for word: String in ["Fight stop", "ring", "GOOD or PERFECT", "before any enemy"]:
		assert_string_contains(entry.text, word)
	for gone: String in ["zone", "roaming"]:
		assert_false(entry.text.to_lower().contains(gone), "no " + gone)
	assert_eq(entry.tag, "FIRST STRIKE!", "the banner's words")
	assert_eq(entry.color, HudStyle.GOLD, "the banner's gold")


func test_the_picture_mode_is_wired() -> void:
	assert_string_contains(_body("func _open_dev_screen("), "\"first_strike\":")
	assert_string_contains(_body("func _show_sample_first_strike("), "_first_strike_picture = true")
	assert_string_contains(_body("func _show_sample_first_strike("), "_fade_to(_start_stop_fight, ")
	assert_string_contains(_body("func _start_combat("), "_combat.first_strike_mode = FirstStrikeRing.Mode.LOOP",
			"the picture's fight rings over and over")


## The text of function `header` in main.gd, up to the next top-level function.
func _body(header: String) -> String:
	var source := FileAccess.get_file_as_string(MAIN_PATH)
	var start := source.find(header)
	assert_gt(start, -1, "found: %s" % header)
	if start < 0:
		return ""
	var end := source.find("\nfunc ", start + 1)
	var static_end := source.find("\nstatic func ", start + 1)
	if static_end > 0 and (end < 0 or static_end < end):
		end = static_end
	return source.substr(start, end - start if end > start else -1)
