extends GutTest
## Skill presses climb and a perfect skill gets a finish (card #307); the killing blow hushes the
## song until the next one (card #308).

const AUDIO_SCRIPT := preload("res://scripts/autoload/audio.gd")


func test_each_perfect_press_rings_higher_up_to_the_top() -> void:
	assert_almost_eq(SkillSequenceRunner.ladder_pitch(0, 1.5, 5), 1.0, 0.0001, "the first press is the plain sound")
	assert_almost_eq(SkillSequenceRunner.ladder_pitch(2, 1.5, 5), pow(2.0, 3.0 / 12.0), 0.0001)
	assert_almost_eq(SkillSequenceRunner.ladder_pitch(9, 1.5, 5), SkillSequenceRunner.ladder_pitch(5, 1.5, 5), 0.0001,
			"it stops climbing at the top step")
	assert_gt(SkillSequenceRunner.ladder_pitch(1, 1.5, 5), SkillSequenceRunner.ladder_pitch(0, 1.5, 5))


func test_the_finish_needs_every_press_perfect() -> void:
	var none := {}
	assert_true(SkillSequenceRunner.all_perfect_done(3, none, {0: true, 1: true, 2: true}, true, 2))
	assert_false(SkillSequenceRunner.all_perfect_done(3, none, {0: true, 1: true}, true, 2), "one still to come")
	assert_false(SkillSequenceRunner.all_perfect_done(3, none, {0: true, 1: true, 2: true}, false, 2),
			"a good press or a miss spoiled it")
	assert_false(SkillSequenceRunner.all_perfect_done(1, none, {0: true}, true, 2), "one press is not enough")
	assert_true(SkillSequenceRunner.all_perfect_done(3, {2: true}, {0: true, 1: true}, true, 2),
			"a voided press (its target fell) does not count against it")


func test_the_hush_silences_the_song_until_the_next_one() -> void:
	var audio: Node = AUDIO_SCRIPT.new()
	add_child_autofree(audio)
	audio.hush_music(true, 0)
	assert_eq(audio._music_hush_db, AUDIO_SCRIPT.SILENT_DB, "the killing blow: silence")
	audio.hush_music(false)
	assert_eq(audio._music_hush_db, 0.0, "a restart brings the song back")
	audio.hush_music(true, 0)
	audio.play_music("")
	assert_eq(audio._music_hush_db, 0.0, "the next song starts without the hush")


func test_the_finish_buzz_and_numbers_are_in_the_data() -> void:
	var visuals := load("res://data/presentation/combat_visuals.tres") as CombatVisuals
	assert_gt(visuals.press_ladder_max_steps, 0)
	assert_gt(visuals.press_finish_min_presses, 1, "a single press is no finish")
	assert_true(visuals.kill_silence)
	var rumble := load("res://data/presentation/rumble.tres") as RumbleSet
	assert_not_null(rumble.find("press_finish"))
