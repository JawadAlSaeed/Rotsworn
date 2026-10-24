extends GutTest
## The First Strike press (DESIGN.md 8.22, card #320): a Fight stop's fight opens with one press ring
## on the place's name card. The pure judge (FirstStrikeJudge) gives First Strike for a GOOD or
## PERFECT press with the skill press windows and a normal start for an early, late, mashed or
## missing one; in local co-op any player's press counts. The ring on the card (FirstStrikeRing)
## judges from DefenseInput stamps, a friend's only watches and shows the host's result; Main rings
## only Fight stops, puts the opening into the fight's setup, and online the host's result reaches the
## friends (and anyone who gets in later). The bots keep their skill press habits on it. The tutorial
## and the glossary teach the press. Uses the shipped data; nothing touches the user's settings.

const TUNING_PATH := "res://data/tuning/tuning.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const RUN_PATH := "res://data/runs/rotten_road.tres"
const MAIN_PATH := "res://scenes/main.gd"
const TUTORIAL_PATH := "res://data/tutorial/tutorial.tres"
const HUSKS_PATH := "res://data/encounters/husk_fight.tres"
const TIPS_PATH := "res://data/branding/tips.tres"
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


# --- the ring on the card ------------------------------------------------------------------------

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
	assert_false(ring.is_finished(), "the card holds the result a moment")
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
	assert_false(ring.is_finished(), "the card holds the result a moment")
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
	assert_gt(lost._result_at_us, 0, "no result came: it goes on, so the card never hangs")
	assert_eq(lost.opening(), CombatSetup.Opening.NORMAL)


func test_the_picture_ring_starts_over() -> void:
	var ring := _ring(PlayerRoster.solo(3), FirstStrikeRing.Mode.LOOP)
	ring._start(Time.get_ticks_usec())
	ring._judge.advance(ring._moment_us * 3)
	ring._on_decided(Time.get_ticks_usec() - (_visuals.first_strike_result_ms + 1) * 1000)
	ring._process(0.0)
	assert_false(ring.is_finished(), "never done")
	assert_false(ring._started, "it starts over")


# --- the name card: the ring on it, and the fight waiting for it ------------------------------------

## Main without its own start-up (no menus, music, network or input): the card tests give it only
## what _fade_to needs.
class FadeHarness extends "res://scenes/main.gd":
	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _input(_event: InputEvent) -> void:
		pass


## A Main whose transitions are instant and whose cards have no tips (so only a ring brings one).
func _fade_main() -> FadeHarness:
	var main := FadeHarness.new()
	var look := _visuals.duplicate() as CombatVisuals
	look.transition_out_ms = 0
	look.transition_in_ms = 0
	var tips := TipSet.new()
	tips.fade_ms = 0
	main._options = CombatOptions.new()
	main._transition = ScreenTransition.new()
	add_child_autofree(main)
	main.add_child(main._transition)
	main._transition.setup(look)
	main._transition.setup_tips(tips, "")
	return main


## A ring that shows at once and whose result goes at once (the card tests wait in real time).
func _quick_ring(roster: PlayerRoster, mode: FirstStrikeRing.Mode) -> FirstStrikeRing:
	_tuning.first_strike_ring_delay_ms = 0
	var look := _visuals.duplicate() as CombatVisuals
	look.first_strike_result_ms = 0
	var ring := FirstStrikeRing.new()
	ring.setup(_tuning, look, CombatOptions.new(), roster, mode, 7)
	return ring


func test_the_name_card_carries_the_ring_with_or_without_tips() -> void:
	var shipped := load(TIPS_PATH) as TipSet
	assert_false(shipped.tips.is_empty())
	for tips: TipSet in [shipped, TipSet.new()]:
		var transition := ScreenTransition.new()
		add_child_autofree(transition)
		transition.setup(_visuals)
		transition.setup_tips(tips, "")
		var ring := _quick_ring(PlayerRoster.solo(3), FirstStrikeRing.Mode.PRESS)
		await transition.show_tip("Rotten Hollow", ring)
		var tipped := "%d tips" % tips.tips.size()
		assert_not_null(transition._card, tipped + ": a card")
		if transition._card == null:
			ring.free()
			continue
		assert_true(transition._card.is_ancestor_of(ring), tipped + ": the ring is on it")
		assert_not_null(ring._input, tipped + ": its _ready ran (its own DefenseInput)")
		assert_true(ring._input.is_inside_tree())
		assert_true(transition.is_covering())
		await transition.hide_tip()
	var bare := ScreenTransition.new()
	add_child_autofree(bare)
	bare.setup(_visuals)
	bare.setup_tips(TipSet.new(), "")
	await bare.show_tip("Rotten Hollow")
	assert_null(bare._card, "no tips and no ring: no card")


func test_the_card_holds_the_fight_until_the_ring_is_done() -> void:
	var main := _fade_main()
	var ring := _quick_ring(PlayerRoster.solo(3), FirstStrikeRing.Mode.PRESS)
	var built: Array = []
	main._fade_to(func() -> void: built.append(ring.opening()), "Rotten Hollow", false, ring)
	assert_true(await wait_until(func() -> bool: return is_instance_valid(ring) and ring._started, 5.0),
			"the ring shows on the card")
	assert_true(main._transition._card != null and main._transition._card.is_ancestor_of(ring), "on the name card")
	await wait_seconds(0.3)
	assert_false(ring.is_finished())
	assert_eq(built, [], "no fight while the ring is undecided")
	ring._input.inject_press(Defense.Outcome.PRESS, PlayerRoster.KEYBOARD)
	assert_eq(ring.word(), FirstStrikeRing.WORD_EARLY, "pressed long before its moment")
	assert_true(await wait_until(func() -> bool: return not built.is_empty(), 5.0), "then the fight")
	assert_eq(built, [CombatSetup.Opening.NORMAL], "built once, with the ring's opening")
	assert_true(await wait_until(func() -> bool: return not main._busy, 5.0), "and the card goes")


func test_a_friends_card_waits_for_the_hosts_result() -> void:
	var main := _fade_main()
	var ring := _quick_ring(PlayerRoster.online(3, 1, 1001), FirstStrikeRing.Mode.WATCH)
	var built: Array = []
	main._fade_to(func() -> void: built.append(ring.opening()), "Rotten Hollow", false, ring)
	assert_true(await wait_until(func() -> bool: return is_instance_valid(ring) and ring._started, 5.0))
	await wait_seconds(0.3)
	assert_eq(built, [], "the friend's card waits for the host")
	ring.show_host_result("first_strike", FirstStrikeRing.WORD_PERFECT)
	assert_true(await wait_until(func() -> bool: return not built.is_empty(), 5.0))
	assert_eq(built, [CombatSetup.Opening.FIRST_STRIKE], "the host's opening")
	assert_true(await wait_until(func() -> bool: return not main._busy, 5.0))


func test_a_card_left_behind_never_builds_its_fight() -> void:
	var main := _fade_main()
	var ring := _quick_ring(PlayerRoster.solo(3), FirstStrikeRing.Mode.PRESS)
	var built: Array = []
	main._first_strike_ring = ring
	main._fade_to(func() -> void: built.append(ring.opening()), "Rotten Hollow", false, ring)
	assert_true(await wait_until(func() -> bool: return is_instance_valid(ring) and ring._started, 5.0))
	main._flow_gen += 1
	assert_true(await wait_until(func() -> bool: return not main._busy and not main._transition.is_covering(), 5.0),
			"the card goes")
	assert_eq(built, [], "the flow moved on: no fight")
	assert_null(main._first_strike_ring)


# --- Main: which fights ring, and where the opening goes ---------------------------------------------

func test_only_fight_stops_ring() -> void:
	for type: int in RunMap.StopType.values():
		assert_eq(_main.call("_rings_first_strike", type), type == RunMap.StopType.FIGHT,
				"%s rings: %s" % [RunMap.TYPE_NAMES[type], type == RunMap.StopType.FIGHT])
	var enter := _body("func _enter_stop(")
	assert_string_contains(enter, "if _rings_first_strike(int(stop.type)) and not _busy:",
			"never announced while a transition would drop its fight")
	assert_string_contains(enter, "_new_first_strike_ring(FirstStrikeRing.Mode.PRESS)")
	for header: String in ["func _start_final_fight(", "func _begin_rush_fight(", "func _start_rush_fight("]:
		assert_false(_body(header).contains("FirstStrikeRing"), header + " opens normally")
		assert_false(_body(header).contains("_run_opening"), header + " never sets an opening")


func test_the_opening_goes_into_the_fights_setup() -> void:
	var combat := _body("func _start_combat(")
	assert_string_contains(combat, "_combat.configure(_encounter, _tuning, _visuals, _options, _fight_look, _run_opening, _fight_air)")
	assert_string_contains(combat, "_run_opening = CombatSetup.Opening.NORMAL", "used up by its fight")
	var start := _body("func _start_stop_fight(")
	assert_string_contains(start, "var opening := _stop_opening(ringed)")
	assert_string_contains(start, "_run_opening = opening\n\t_start_combat()")
	assert_string_contains(start, "print(\"AUTOPLAY_OPENING %s stop=%d\"")
	assert_string_contains(FileAccess.get_file_as_string("res://scripts/combat/presentation/combat_controller.gd"),
			"_run.fight_setup(_encounter, _pick_seed(), _opening)", "the controller builds its setup with it")
	# The setup a run fight is built from carries the opening into the engine.
	var data := load(RUN_PATH) as RunData
	var run := RunState.begin(data, _tuning, 7)
	var husks := load(HUSKS_PATH) as EncounterData
	var setup := run.fight_setup(husks, 5, CombatSetup.Opening.FIRST_STRIKE)
	assert_eq(setup.opening, CombatSetup.Opening.FIRST_STRIKE)
	var events := CombatEngine.new(setup).start()
	var started: Dictionary = {}
	var order: Array = []
	for ev: Dictionary in events:
		if String(ev.type) == "combat_started" and started.is_empty():
			started = ev
		if String(ev.type) == "turn_order" and order.is_empty():
			order = ev.order
	assert_eq(String(started.opening), "first_strike", "the gold FIRST STRIKE banner's event")
	var party := setup.party.size()
	for i: int in party:
		assert_lt(int(order[i]), party, "every hero acts before any enemy")
	# A controller given the opening keeps it for that setup.
	var controller := CombatController.new()
	controller.configure(husks, _tuning, _visuals, CombatOptions.new(), null, CombatSetup.Opening.FIRST_STRIKE)
	assert_eq(controller._opening, CombatSetup.Opening.FIRST_STRIKE)
	controller.free()


func test_main_reads_the_opening_from_the_ring() -> void:
	var main: Node = _main.new()
	autofree(main)
	var ring := FirstStrikeRing.new()
	autofree(ring)
	ring._opening = CombatSetup.Opening.FIRST_STRIKE
	main.set("_first_strike_ring", ring)
	assert_eq(main.call("_stop_opening", true), CombatSetup.Opening.FIRST_STRIKE, "a Fight stop's ring")
	assert_eq(main.call("_stop_opening", false), CombatSetup.Opening.NORMAL, "a Guard stop never")
	main.set("_first_strike_ring", null)
	assert_eq(main.call("_stop_opening", true), CombatSetup.Opening.NORMAL, "no ring, no First Strike")


# --- online --------------------------------------------------------------------------------------

func test_online_the_host_decides_and_the_friends_get_its_opening() -> void:
	assert_eq(NetSession.PROTOCOL, 5, "the fingerprint already keeps other builds out")
	var decided := _body("func _on_first_strike_decided(")
	assert_string_contains(decided, "if not Net.is_host():")
	assert_string_contains(decided, "Net.broadcast(\"opening\", {\"fight\": _net_seed, \"opening\": opening_name, \"word\": word})")
	assert_string_contains(decided, "_net_fight[\"opening\"] = opening_name", "kept for anyone who gets in later")
	var announce := _body("func _announce_stop_fight(")
	assert_string_contains(announce, "_send_screen({\"name\": \"stop_fight\", \"seed\": _net_seed, \"ring\": ring})")
	var enter := _body("func _enter_stop(")
	assert_lt(enter.find("_announce_stop_fight(true)"), enter.find("_new_first_strike_ring("),
			"the friends hear of the fight before the host's ring runs")
	var client := _body("func _client_screen(")
	assert_string_contains(client, "_new_first_strike_ring(FirstStrikeRing.Mode.WATCH)")
	var messages := _body("func _on_net_message(")
	assert_lt(messages.find("\"opening\":"), messages.find("_net_queue.append("),
			"the host's result is taken at once, not behind the card that waits for it")
	# What the friend makes of the host's word.
	assert_eq(_main.call("_opening_of", {"fight": 9, "opening": "first_strike"}, 9), CombatSetup.Opening.FIRST_STRIKE)
	assert_eq(_main.call("_opening_of", {"fight": 9, "opening": "normal"}, 9), CombatSetup.Opening.NORMAL)
	assert_eq(_main.call("_opening_of", {"fight": 8, "opening": "first_strike"}, 9), CombatSetup.Opening.NORMAL,
			"another fight's result")
	assert_eq(_main.call("_opening_of", {}, 9), CombatSetup.Opening.NORMAL, "none came")
	var main: Node = _main.new()
	autofree(main)
	var ring := FirstStrikeRing.new()
	autofree(ring)
	ring.setup(_tuning, _visuals, CombatOptions.new(), PlayerRoster.online(3, 1, 1001), FirstStrikeRing.Mode.WATCH)
	main.set("_first_strike_ring", ring)
	main.set("_net_seed", 321)
	main.call("_take_net_opening", {"fight": 321, "opening": "first_strike", "word": "GOOD"}, 321)
	assert_eq(ring._host_result, {"opening": "first_strike", "word": "GOOD"}, "the watched ring shows it")
	assert_eq(_main.call("_opening_of", main.get("_net_opening"), 321), CombatSetup.Opening.FIRST_STRIKE,
			"the friend's fight starts with it")


func test_a_friend_watches_only_an_undecided_fight_stop_ring() -> void:
	var p := {"name": "stop_fight", "seed": 5, "ring": true}
	assert_true(_main.call("_watches_first_strike", p, {}), "a Fight stop's ring")
	assert_false(_main.call("_watches_first_strike", {"name": "stop_fight", "seed": 5, "ring": false}, {}), "a Guard stop's")
	assert_false(_main.call("_watches_first_strike", {"name": "stop_fight", "seed": 5}, {}), "an older host's message")
	assert_false(_main.call("_watches_first_strike", p, {"fight": 5, "opening": "normal"}), "its result is in already")
	assert_true(_main.call("_watches_first_strike", p, {"fight": 4, "opening": "normal"}), "the last fight's result")
	var decided := p.duplicate()
	decided["opening"] = "first_strike"
	assert_false(_main.call("_watches_first_strike", decided, {}), "a friend who gets in once it is decided")
	var going := p.duplicate()
	going["rejoin"] = true
	assert_false(_main.call("_watches_first_strike", going, {}), "a friend who gets in mid-fight")


func test_a_friend_who_gets_in_during_the_card_gets_the_result() -> void:
	var data := load(RUN_PATH) as RunData
	var host := RunState.begin(data, _tuning, 7)
	host.go(host.choices()[0])
	var roster := PlayerRoster.online(data.party.size(), 1, 1)
	roster.join_peer(1001)
	var fight := {"name": "stop_fight", "seed": 321, "ring": true}
	# During the host's ring: the friend watches it and waits for the broadcast.
	var before: Array[Dictionary] = _main.call("_catch_up_messages", host, roster, true, {"name": "map"}, fight, false)
	var payload := before[2].payload as Dictionary
	assert_false(bool(payload.rejoin), "nothing is built yet: no resume to wait for")
	assert_true(_main.call("_watches_first_strike", payload, {}))
	# Once decided the fight's message carries it: no ring, straight on with the host's opening.
	fight["opening"] = "first_strike"
	fight["word"] = "PERFECT"
	var after: Array[Dictionary] = _main.call("_catch_up_messages", host, roster, true, {"name": "map"}, fight, false)
	payload = after[2].payload as Dictionary
	assert_false(_main.call("_watches_first_strike", payload, {}))
	var main: Node = _main.new()
	autofree(main)
	main.call("_take_net_opening", payload, 321)
	assert_eq(_main.call("_opening_of", main.get("_net_opening"), 321), CombatSetup.Opening.FIRST_STRIKE)


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
	assert_string_contains(_body("func _show_sample_first_strike("), "FirstStrikeRing.Mode.LOOP")


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
