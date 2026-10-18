extends GutTest
## First-run polish (cards #167 and #204, DESIGN.md 3.2 and 7.7): the "Controller recommended"
## notice's rules, the once-only lag calibration offer, and the lag compensation kept per kind of
## input (keyboard and pad) down to the judge. Nothing here reads or writes the real
## user://settings.cfg.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const BRANDING_PATH := "res://data/branding/branding.tres"
const PARRY: int = Defense.Outcome.PARRY
const SUCCESS: int = DefenseJudge.Result.SUCCESS
const WHIFF: int = DefenseJudge.Result.WHIFF

var _settings_before: ConfigFile
var _tuning := Tuning.new()


func before_each() -> void:
	_settings_before = PlayerSettings._config
	PlayerSettings._config = ConfigFile.new()
	PlayerSettings.set_persistence(false)


func after_each() -> void:
	PlayerSettings._config = _settings_before
	PlayerSettings.set_persistence(true)


# --- the controller notice (#167) -----------------------------------------------------------

func test_notice_data_is_complete_and_the_icon_exists() -> void:
	var branding := load(BRANDING_PATH) as BrandingData
	assert_not_null(branding)
	assert_false(branding.controller_title.strip_edges().is_empty())
	assert_false(branding.controller_text.strip_edges().is_empty())
	assert_true(ResourceLoader.exists(branding.controller_icon_path), "the icon: %s" % branding.controller_icon_path)
	assert_gt(branding.controller_hold_ms, 0, "the shipped notice shows")
	assert_gt(ControllerNotice.total_ms(branding), branding.controller_skip_guard_ms,
			"the skip guard ends before the notice does")
	assert_lt(ControllerNotice.total_ms(branding), 6000, "it fades out by itself after a few seconds")


func test_notice_is_due_follows_the_data() -> void:
	var branding := BrandingData.new()
	branding.controller_hold_ms = 2000
	branding.controller_skip_with_pad = false
	assert_true(ControllerNotice.is_due(branding, false))
	assert_true(ControllerNotice.is_due(branding, true), "shown even with a pad plugged in by default")
	branding.controller_skip_with_pad = true
	assert_true(ControllerNotice.is_due(branding, false))
	assert_false(ControllerNotice.is_due(branding, true), "the data can skip it for a player who has a pad")
	branding.controller_hold_ms = 0
	assert_false(ControllerNotice.is_due(branding, false), "no hold time: no notice")


# --- the calibration offer (#204) -----------------------------------------------------------

func test_offer_is_due_once_and_only_to_the_uncalibrated() -> void:
	assert_true(PlayerSettings.calibration_offer_due(false, false), "a new player is offered it")
	assert_false(PlayerSettings.calibration_offer_due(true, false), "never twice")
	assert_false(PlayerSettings.calibration_offer_due(false, true), "not to a player who calibrated already")
	assert_false(PlayerSettings.calibration_offer_due(true, true))


func test_offered_flag_is_remembered() -> void:
	assert_false(PlayerSettings.calibration_offered(), "nothing is offered on a new machine")
	assert_true(PlayerSettings.calibration_offer_due(PlayerSettings.calibration_offered(), PlayerSettings.is_calibrated()))
	PlayerSettings.set_calibration_offered(true)
	assert_true(PlayerSettings.calibration_offered())
	assert_false(PlayerSettings.calibration_offer_due(PlayerSettings.calibration_offered(), PlayerSettings.is_calibrated()),
			"after the first offer a New Run goes straight on")


func test_offer_and_tutorial_offer_are_separate_flags() -> void:
	PlayerSettings.set_tutorial_offered(true)
	assert_false(PlayerSettings.calibration_offered(), "the tutorial offer does not use up the calibration offer")
	PlayerSettings.set_calibration_offered(true)
	PlayerSettings.set_tutorial_offered(false)
	assert_true(PlayerSettings.calibration_offered())


func test_saving_a_calibration_ends_the_offer() -> void:
	PlayerSettings.set_latency_compensation_ms(40, _tuning, PlayerSettings.INPUT_PAD)
	assert_true(PlayerSettings.is_calibrated())
	assert_false(PlayerSettings.calibration_offer_due(false, PlayerSettings.is_calibrated()),
			"a player who calibrated in Settings first is not offered it")


# --- one value per kind of input (#204) -----------------------------------------------------

func test_device_codes_map_to_a_kind() -> void:
	assert_eq(PlayerSettings.input_kind_of_device(PlayerRoster.KEYBOARD), PlayerSettings.INPUT_KEYBOARD)
	assert_eq(PlayerSettings.input_kind_of_device(PlayerRoster.ANY), PlayerSettings.INPUT_KEYBOARD, "the bot counts as keys")
	assert_eq(PlayerSettings.input_kind_of_device(0), PlayerSettings.INPUT_PAD)
	assert_eq(PlayerSettings.input_kind_of_device(3), PlayerSettings.INPUT_PAD)


func test_each_kind_keeps_its_own_value() -> void:
	var default := _tuning.input_latency_compensation_ms
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_KEYBOARD), default)
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_PAD), default)
	PlayerSettings.set_latency_compensation_ms(70, _tuning, PlayerSettings.INPUT_PAD)
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_PAD), 70)
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_KEYBOARD), default,
			"calibrating the pad leaves the keyboard alone")
	assert_true(PlayerSettings.is_calibrated(PlayerSettings.INPUT_PAD))
	assert_false(PlayerSettings.is_calibrated(PlayerSettings.INPUT_KEYBOARD))
	PlayerSettings.set_latency_compensation_ms(10, _tuning, PlayerSettings.INPUT_KEYBOARD)
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_KEYBOARD), 10)
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_PAD), 70)


func test_values_stay_inside_the_calibration_bounds() -> void:
	PlayerSettings.set_latency_compensation_ms(9999, _tuning, PlayerSettings.INPUT_PAD)
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_PAD), _tuning.calibration_max_ms)
	PlayerSettings.set_latency_compensation_ms(-9999, _tuning, PlayerSettings.INPUT_KEYBOARD)
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_KEYBOARD), _tuning.calibration_min_ms)


func test_an_old_single_value_covers_both_kinds_until_replaced() -> void:
	# Before the kinds existed one value was saved under timing/latency_compensation_ms.
	PlayerSettings._config.set_value(PlayerSettings.SECTION_TIMING, PlayerSettings.KEY_LATENCY, 55)
	assert_true(PlayerSettings.is_calibrated(), "an older calibration counts: no offer")
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_KEYBOARD), 55)
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_PAD), 55)
	PlayerSettings.set_latency_compensation_ms(20, _tuning, PlayerSettings.INPUT_PAD)
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_PAD), 20)
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_KEYBOARD), 55)


func test_reset_forgets_every_kind() -> void:
	PlayerSettings._config.set_value(PlayerSettings.SECTION_TIMING, PlayerSettings.KEY_LATENCY, 55)
	PlayerSettings.set_latency_compensation_ms(20, _tuning, PlayerSettings.INPUT_PAD)
	PlayerSettings.set_latency_compensation_ms(25, _tuning, PlayerSettings.INPUT_KEYBOARD)
	PlayerSettings.reset_latency_compensation()
	assert_false(PlayerSettings.is_calibrated())
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_PAD), _tuning.input_latency_compensation_ms)
	assert_eq(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_KEYBOARD), _tuning.input_latency_compensation_ms)


func test_the_judge_base_is_the_smaller_value() -> void:
	PlayerSettings.set_latency_compensation_ms(60, _tuning, PlayerSettings.INPUT_PAD)
	PlayerSettings.set_latency_compensation_ms(20, _tuning, PlayerSettings.INPUT_KEYBOARD)
	assert_eq(PlayerSettings.base_latency_compensation_ms(_tuning), 20)


# --- the judge uses the pressing device's value ----------------------------------------------

func _single_hit_judges(base_ms: int) -> JudgeSet:
	var attack := Fx.attack("jab", [Fx.hit(900, Fx.NORMAL, 50)], Fx.PARTY)
	var engine := Fx.started([attack])
	var judges := JudgeSet.new(_tuning.whiff_lockout_ms, base_ms, _tuning.press_reach_back_max_ms,
			_tuning.late_press_report_ms)
	judges.set_prompts(engine.sequence.prompts, {})
	return judges


func test_a_laggier_device_is_judged_earlier() -> void:
	# The default parry window is -97.5 .. +52.5 ms around the hit at 900 ms.
	var late_us := 900000 + 52500 + 30000
	assert_eq(int(_single_hit_judges(0).press(0, PARRY, late_us).result), WHIFF, "30 ms past the window on the base")
	assert_eq(int(_single_hit_judges(0).press(0, PARRY, late_us, -1, 30).result), SUCCESS,
			"the same press from a device that lags 30 ms more is on time")


func test_extra_lag_equals_building_the_judge_with_that_value() -> void:
	for t_us: int in [800000, 850000, 900000, 950000, 952500, 960000]:
		var direct := _single_hit_judges(35).press(0, PARRY, t_us)
		var shifted := _single_hit_judges(5).press(0, PARRY, t_us, -1, 30)
		assert_eq(int(shifted.result), int(direct.result), "same verdict at %d us" % t_us)
		assert_eq(int(shifted.offset_us), int(direct.offset_us), "same offset at %d us" % t_us)


func test_extra_lag_also_moves_the_reach_back_start() -> void:
	# A press 40 ms after its pump: the reach back is shifted the same way, so it stays the same span.
	var plain := _single_hit_judges(35).press(0, PARRY, 960000, 920000)
	var shifted := _single_hit_judges(5).press(0, PARRY, 960000, 920000, 30)
	assert_eq(int(shifted.result), int(plain.result))
	assert_eq(int(shifted.offset_us), int(plain.offset_us))


func test_extra_lag_is_never_negative() -> void:
	var late_us := 900000 + 52500 + 10000
	assert_eq(int(_single_hit_judges(30).press(0, PARRY, late_us, -1, -50).result),
			int(_single_hit_judges(30).press(0, PARRY, late_us).result), "a negative extra counts as none")
