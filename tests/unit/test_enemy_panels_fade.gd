extends GutTest
## EnemyPanelsFade (DESIGN 7.1, card #268): the enemy panels step back while an enemy attack plays
## and come back to full at once on a parry or a counter.

const ATTACK_ALPHA: float = 0.3
const FADE_MS: int = 200
const HOLD_MS: int = 600


func _fade() -> EnemyPanelsFade:
	var fade := EnemyPanelsFade.new()
	fade.configure(ATTACK_ALPHA, FADE_MS, HOLD_MS)
	return fade


func test_full_outside_an_enemy_attack() -> void:
	var fade := _fade()
	assert_eq(fade.target(), 1.0)
	assert_eq(fade.step(1.0), 1.0)


func test_attack_fades_down_over_the_fade_time() -> void:
	var fade := _fade()
	fade.set_attacking(true)
	assert_eq(fade.target(), ATTACK_ALPHA)
	# The full range takes FADE_MS: halfway there after a tenth of a second.
	assert_almost_eq(fade.step(0.1), 0.5, 0.001)
	assert_almost_eq(fade.step(0.1), ATTACK_ALPHA, 0.001, "never below the attack see-through")


func test_attack_over_fades_back_up() -> void:
	var fade := _fade()
	fade.set_attacking(true)
	fade.step(1.0)
	fade.set_attacking(false)
	assert_eq(fade.target(), 1.0)
	assert_almost_eq(fade.step(0.1), ATTACK_ALPHA + 0.5, 0.001)
	assert_almost_eq(fade.step(1.0), 1.0, 0.001)


func test_parry_is_full_at_once_then_steps_back_after_the_hold() -> void:
	var fade := _fade()
	fade.set_attacking(true)
	fade.step(1.0)
	fade.show_now()
	assert_eq(fade.alpha(), 1.0, "no fade in: full the moment the parry lands")
	assert_eq(fade.step(0.5), 1.0, "still held")
	assert_eq(fade.step(0.09), 1.0, "still held just before the hold ends")
	fade.step(0.02)
	assert_eq(fade.target(), ATTACK_ALPHA, "more hits coming: back to see-through")
	assert_almost_eq(fade.step(1.0), ATTACK_ALPHA, 0.001)


func test_parried_last_hit_stays_full_until_the_attack_is_over() -> void:
	var fade := _fade()
	fade.set_attacking(true)
	fade.step(1.0)
	fade.show_now(true)
	assert_eq(fade.step(5.0), 1.0, "held past the parry hold, for the counter")
	fade.set_attacking(false)
	assert_eq(fade.step(0.1), 1.0)


func test_next_attack_drops_the_last_attacks_hold() -> void:
	var fade := _fade()
	fade.set_attacking(true)
	fade.show_now(true)
	fade.set_attacking(false)
	fade.set_attacking(true)
	assert_eq(fade.target(), ATTACK_ALPHA)


func test_attack_start_said_twice_keeps_a_running_hold() -> void:
	var fade := _fade()
	fade.set_attacking(true)
	fade.show_now()
	fade.set_attacking(true)
	assert_eq(fade.target(), 1.0)


func test_zero_fade_time_jumps_straight_to_the_target() -> void:
	var fade := EnemyPanelsFade.new()
	fade.configure(ATTACK_ALPHA, 0, HOLD_MS)
	fade.set_attacking(true)
	assert_eq(fade.step(0.016), ATTACK_ALPHA)


func test_shipped_numbers_fade_but_keep_the_panels_visible() -> void:
	var visuals := load("res://data/presentation/combat_visuals.tres") as CombatVisuals
	assert_gt(visuals.enemy_panels_attack_alpha, 0.0, "the bars must still be readable")
	assert_lt(visuals.enemy_panels_attack_alpha, 1.0, "the bars must step back during attacks")
	assert_gt(visuals.enemy_panels_fade_ms, 0)
	assert_gt(visuals.enemy_panels_parry_hold_ms, 0)
