extends GutTest
## Controller buzz (card #299, DESIGN.md 7.14): RumbleMixer plays patterns per pad (the stronger
## motor wins when two overlap, a finished pattern stops the pad once), each pad buzzes only for its
## own player's heroes, and every pattern the game asks for is in data/presentation/rumble.tres.

const KEYBOARD := PlayerRoster.KEYBOARD
const SET_PATH := "res://data/presentation/rumble.tres"
## Every pattern name the game code plays.
const USED := ["parry", "parry_final", "dodge", "jump", "press_perfect", "press_good", "hurt",
		"hurt_heavy", "downed", "ultimate", "boss_rage", "doom", "streak", "thunder", "press_finish"]


func _steps(list: Array) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for v: Vector3i in list:
		out.append(v)
	return out


func test_step_at_walks_the_steps_and_ends() -> void:
	var steps := _steps([Vector3i(50, 0, 100), Vector3i(0, 80, 50)])
	assert_eq(RumbleMixer.step_at(steps, -1), Vector2i(-1, 0), "not started")
	assert_eq(RumbleMixer.step_at(steps, 0), Vector2i(0, 100))
	assert_eq(RumbleMixer.step_at(steps, 99), Vector2i(0, 1))
	assert_eq(RumbleMixer.step_at(steps, 100), Vector2i(1, 50))
	assert_eq(RumbleMixer.step_at(steps, 150), Vector2i(-1, 0), "over")


func test_levels_scale_and_stop_once_when_done() -> void:
	var mixer := RumbleMixer.new()
	mixer.play(3, _steps([Vector3i(100, 50, 100)]), 1000, 0.5)
	var now: Dictionary = mixer.levels(1010)
	assert_true(now.has(3))
	assert_almost_eq((now[3] as Vector3).x, 0.5, 0.001, "weak motor at half strength")
	assert_almost_eq((now[3] as Vector3).y, 0.25, 0.001)
	assert_almost_eq((now[3] as Vector3).z, 0.09, 0.001, "90 ms left in the step")
	var ended: Dictionary = mixer.levels(1200)
	assert_eq(ended.get(3), Vector3.ZERO, "the pad is told to stop once")
	assert_false(mixer.levels(1300).has(3), "then it is forgotten")
	assert_true(mixer.is_idle())


func test_two_patterns_on_one_pad_take_the_stronger_motor() -> void:
	var mixer := RumbleMixer.new()
	mixer.play(0, _steps([Vector3i(90, 10, 100)]), 0)
	mixer.play(0, _steps([Vector3i(20, 70, 200)]), 0)
	var level: Vector3 = mixer.levels(10)[0]
	assert_almost_eq(level.x, 0.9, 0.001)
	assert_almost_eq(level.y, 0.7, 0.001)
	level = mixer.levels(150)[0]
	assert_almost_eq(level.x, 0.2, 0.001, "the short one ended: the long one alone")


func test_no_pad_or_no_strength_plays_nothing() -> void:
	var mixer := RumbleMixer.new()
	mixer.play(-1, _steps([Vector3i(50, 50, 100)]), 0)
	mixer.play(0, _steps([Vector3i(50, 50, 100)]), 0, 0.0)
	assert_true(mixer.is_idle(), "keyboard (-1) and vibration at 0 never buzz")


func test_too_many_patterns_drop_the_oldest() -> void:
	var mixer := RumbleMixer.new()
	mixer.play(0, _steps([Vector3i(100, 0, 1000)]), 0, 1.0, 2)
	mixer.play(0, _steps([Vector3i(10, 0, 1000)]), 0, 1.0, 2)
	mixer.play(0, _steps([Vector3i(20, 0, 1000)]), 0, 1.0, 2)
	assert_almost_eq((mixer.levels(10)[0] as Vector3).x, 0.2, 0.001, "the strong first one was dropped")


func test_stop_all_names_every_buzzing_pad() -> void:
	var mixer := RumbleMixer.new()
	mixer.play(0, _steps([Vector3i(50, 0, 100)]), 0)
	mixer.play(2, _steps([Vector3i(50, 0, 100)]), 0)
	var stopped := mixer.stop_all()
	stopped.sort()
	assert_eq(stopped, [0, 2] as Array[int])
	assert_true(mixer.is_idle())


func test_solo_buzzes_the_pad_in_use_only() -> void:
	var roster := PlayerRoster.solo(3, KEYBOARD)
	assert_eq(RumbleMixer.pads_of_player(roster, 0, 1, true), [1] as Array[int], "the pad that was last used")
	assert_eq(RumbleMixer.pads_of_player(roster, 0, 1, false), [] as Array[int], "a key was pressed since")
	assert_eq(RumbleMixer.pads_of_player(roster, 0, -1, true), [] as Array[int], "no pad yet")
	assert_eq(RumbleMixer.pads_of_player(null, 0, 2, true), [2] as Array[int], "no fight: the pad in use")


func test_local_coop_buzzes_each_players_own_pad() -> void:
	var roster := PlayerRoster.solo(3, KEYBOARD)
	roster.join(0)
	roster.join(1)
	assert_eq(RumbleMixer.pads_of_player(roster, 1, 1, true), [0] as Array[int], "P2's own pad, not the last one used")
	assert_eq(RumbleMixer.pads_of_player(roster, 2, 0, true), [1] as Array[int])
	assert_eq(RumbleMixer.pads_of_player(roster, 0, 1, true), [] as Array[int], "the keyboard player has no pad")


func test_online_buzzes_only_this_machines_player() -> void:
	var roster := PlayerRoster.online(3, 1, 7)
	roster.join_peer(7)
	var mine := roster.player_of_peer(7)
	var host := roster.player_of_peer(1)
	assert_eq(RumbleMixer.pads_of_player(roster, mine, 0, true), [0] as Array[int])
	assert_eq(RumbleMixer.pads_of_player(roster, host, 0, true), [] as Array[int], "the host's heroes buzz the host's pad")


func test_every_pattern_the_game_plays_is_in_the_data() -> void:
	var set := load(SET_PATH) as RumbleSet
	assert_not_null(set)
	for pattern_name: String in USED:
		var pattern := set.find(pattern_name)
		assert_not_null(pattern, "missing buzz '%s'" % pattern_name)
		if pattern == null:
			continue
		assert_gt(pattern.length_ms(), 0, pattern_name)
		assert_lt(pattern.length_ms(), 2500, "%s: a buzz stays short" % pattern_name)
		for step: Vector3i in pattern.steps:
			assert_true(step.x >= 0 and step.x <= 100 and step.y >= 0 and step.y <= 100 and step.z > 0,
					"%s: strengths in percent, lengths positive" % pattern_name)
	assert_not_null(set.find(set.test_pattern), "the Settings test buzz exists")


func test_vibration_setting_clamps_and_defaults_to_full() -> void:
	var before := PlayerSettings._config
	PlayerSettings._config = ConfigFile.new()
	PlayerSettings.set_persistence(false)
	assert_eq(PlayerSettings.rumble_percent(), 100, "on at full by default")
	PlayerSettings.set_rumble_percent(140)
	assert_eq(PlayerSettings.rumble_percent(), 100)
	PlayerSettings.set_rumble_percent(-5)
	assert_eq(PlayerSettings.rumble_percent(), 0)
	PlayerSettings._config = before
	PlayerSettings.set_persistence(true)


func test_controller_page_lists_vibration() -> void:
	var bindings := ControlBindings.from_input_map()
	var rows := SettingsScreen.controls_rows(SettingsScreen.ControlsPage.CONTROLLER, bindings, false)
	assert_true(rows.has("vibration"))
	assert_lt(rows.find("vibration"), rows.find("reset"), "above the page's reset")
	var keys := SettingsScreen.controls_rows(SettingsScreen.ControlsPage.KEYBOARD, bindings, false)
	assert_false(keys.has("vibration"), "the keyboard has nothing to buzz")


func test_a_scale_above_one_is_stronger_but_capped() -> void:
	var mixer := RumbleMixer.new()
	mixer.play(0, _steps([Vector3i(40, 80, 100)]), 0, 1.5)
	var level: Vector3 = mixer.levels(10)[0]
	assert_almost_eq(level.x, 0.6, 0.001, "40% x 1.5")
	assert_almost_eq(level.y, 1.0, 0.001, "80% x 1.5 is capped at full")
