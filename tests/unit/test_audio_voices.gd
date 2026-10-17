extends GutTest
## Sound voice picking (card #183): a free player first, steal the one nearly done only when all
## are busy; the per-cue cooldown.


func test_free_player_first() -> void:
	assert_eq(VoicePool.pick([true, false, true] as Array[bool], [5.0, 0.0, 0.1] as Array[float]), 1)
	assert_eq(VoicePool.pick([false, false] as Array[bool], [0.0, 0.0] as Array[float]), 0)


func test_steals_the_one_with_least_time_left_when_all_busy() -> void:
	assert_eq(VoicePool.pick([true, true, true] as Array[bool], [3.0, 0.2, 1.0] as Array[float]), 1)


func test_no_players() -> void:
	assert_eq(VoicePool.pick([] as Array[bool], [] as Array[float]), -1)


func test_cooldown() -> void:
	assert_false(VoicePool.in_cooldown(-1, 1000, 30), "never played")
	assert_true(VoicePool.in_cooldown(990, 1000, 30))
	assert_false(VoicePool.in_cooldown(900, 1000, 30))


func test_mix_data_loads_with_sane_numbers() -> void:
	var mix := load("res://data/audio/mix.tres") as AudioMix
	assert_not_null(mix)
	assert_lt(mix.limiter_ceiling_db, 0.0, "headroom under 0 dBFS")
