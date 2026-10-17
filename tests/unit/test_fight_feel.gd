extends GutTest
## Fight feel (DESIGN 7.3, cards #179 and #185): the camera trauma model, the Flashes setting and
## the tuned numbers in combat_visuals.tres.

const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"


func _trauma() -> CameraTrauma:
	var t := CameraTrauma.new()
	t.configure(6.0, 1.5, 0.32, 1.6)
	return t


func test_trauma_accumulates_and_clamps() -> void:
	var t := _trauma()
	t.add(0.4)
	t.add(0.4)
	assert_almost_eq(t.trauma(), 0.8, 0.0001, "hits add up")
	t.add(0.9)
	assert_eq(t.trauma(), 1.0, "never above 1")
	t.add(-5.0)
	assert_eq(t.trauma(), 1.0, "a negative amount adds nothing")


func test_trauma_drains_per_second_whatever_the_frame_rate() -> void:
	var slow := _trauma()
	var fast := _trauma()
	slow.add(1.0)
	fast.add(1.0)
	for i: int in 15:
		slow.step(1.0 / 30.0)
	for i: int in 240:
		fast.step(1.0 / 480.0)
	assert_almost_eq(slow.trauma(), 0.25, 0.0001, "half a second at 1.5 per second")
	assert_almost_eq(fast.trauma(), slow.trauma(), 0.0001, "same drain at 30 and 480 fps")
	slow.step(10.0)
	assert_eq(slow.trauma(), 0.0, "never below zero")


func test_amplitude_is_trauma_squared() -> void:
	var t := _trauma()
	t.add(0.5)
	assert_almost_eq(t.amount(), 0.25, 0.0001)
	var peak := 0.0
	for i: int in 2000:
		peak = maxf(peak, absf(t.offset(float(i) * 0.001).x))
	assert_true(peak <= 0.25 * 0.32 + 0.0001, "never above trauma squared times the maximum")
	assert_true(peak > 0.25 * 0.32 * 0.5, "and it does reach most of it")


func test_a_big_hit_shakes_much_more_than_a_graze() -> void:
	var graze := _trauma()
	var big := _trauma()
	graze.add(0.2)
	big.add(0.7)
	assert_true(big.amount() > graze.amount() * 8.0, "0.7 against 0.2 is over 8 times the shake")


func test_shake_is_the_same_signal_at_any_frame_rate() -> void:
	# The wave reads the clock, not a random number per frame: the same instant gives the same offset.
	var a := _trauma()
	var b := _trauma()
	a.add(0.8)
	b.add(0.8)
	assert_eq(a.offset(12.345), b.offset(12.345))
	assert_eq(a.roll(12.345), b.roll(12.345))
	assert_ne(a.offset(12.345), a.offset(12.4), "and it moves with time")


func test_shake_setting_scales_the_result_and_zero_is_still() -> void:
	var t := _trauma()
	t.add(1.0)
	var full := t.offset(0.123)
	assert_almost_eq(t.offset(0.123, 0.5).x, full.x * 0.5, 0.0001)
	assert_eq(t.offset(0.123, 0.0), Vector3.ZERO)
	assert_eq(t.roll(0.123, 0.0), 0.0)


func test_no_trauma_means_no_shake_and_no_roll() -> void:
	var t := _trauma()
	assert_eq(t.offset(1.0), Vector3.ZERO)
	assert_eq(t.roll(1.0), 0.0)


func test_roll_stays_small() -> void:
	var t := _trauma()
	t.add(1.0)
	for i: int in 500:
		assert_true(absf(t.roll(float(i) * 0.003)) <= deg_to_rad(1.6) + 0.0001)


func test_flash_scales_come_from_data() -> void:
	var v := load(VISUALS_PATH) as CombatVisuals
	assert_eq(v.screen_flash_scale(PlayerSettings.FLASH_FULL), 1.0)
	assert_eq(v.fighter_flash_scale(PlayerSettings.FLASH_FULL), 1.0)
	assert_almost_eq(v.screen_flash_scale(PlayerSettings.FLASH_REDUCED), 0.4, 0.0001)
	assert_almost_eq(v.fighter_flash_scale(PlayerSettings.FLASH_REDUCED), 0.5, 0.0001)
	assert_eq(v.screen_flash_scale(PlayerSettings.FLASH_OFF), 0.0, "no screen flashes at Off")
	assert_true(v.fighter_flash_scale(PlayerSettings.FLASH_OFF) < v.fighter_flash_scale(PlayerSettings.FLASH_REDUCED))
	assert_true(v.fighter_flash_scale(PlayerSettings.FLASH_OFF) > 0.0, "a hit still reads as a faint tint")


func test_flash_mode_setting_defaults_to_full_and_reads_bad_values_as_full() -> void:
	var kept: ConfigFile = PlayerSettings._config
	PlayerSettings._config = ConfigFile.new()
	assert_eq(PlayerSettings.flash_mode(), PlayerSettings.FLASH_FULL, "full by default")
	PlayerSettings._config.set_value(PlayerSettings.SECTION_GAME, PlayerSettings.KEY_FLASH, PlayerSettings.FLASH_OFF)
	assert_eq(PlayerSettings.flash_mode(), PlayerSettings.FLASH_OFF)
	PlayerSettings._config.set_value(PlayerSettings.SECTION_GAME, PlayerSettings.KEY_FLASH, 9)
	assert_eq(PlayerSettings.flash_mode(), PlayerSettings.FLASH_FULL, "a bad value reads as full")
	PlayerSettings._config = kept


func test_impact_tiers_grow_with_the_moment() -> void:
	var v := load(VISUALS_PATH) as CombatVisuals
	assert_true(v.shake_strike < v.shake_strike_perfect, "a perfect press hits harder than a good one")
	assert_true(v.shake_strike_perfect < v.shake_ultimate_hit, "an ultimate hit harder still")
	assert_true(v.shake_hurt < v.shake_hurt_heavy, "a heavy hit shakes more than a graze")
	assert_true(v.shake_parry < v.shake_parry_final)
	assert_true(v.shake_hurt < v.shake_parry_final, "DESIGN 3.6: a parry shakes more than a hit taken")
	assert_true(v.shake_counter < v.shake_team_counter)
	assert_true(v.kill_shake > v.shake_counter, "the last kill is the biggest tier")
	assert_true(v.boss_kill_shake >= v.kill_shake and v.boss_kill_hitstop_ms > v.kill_hitstop_ms)
	assert_true(v.boss_kill_hitstop_ms <= 200 and v.kill_hitstop_ms >= 80, "freezes stay short")
	assert_true(v.shake_hz * 3.7 < 30.0, "the top sine layer stays under half of 60 fps")
