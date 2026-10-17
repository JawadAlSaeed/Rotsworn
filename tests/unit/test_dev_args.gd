extends GutTest
## Dev switches work only in debug builds (card #182).


func test_release_build_ignores_dev_switches() -> void:
	var args := PackedStringArray(["--autoplay", "--tuning=user://easy.tres", "--seed=3"])
	assert_eq(DevArgs.filter(args, false), PackedStringArray(), "a release build sees none")
	assert_eq(DevArgs.filter(args, true), args, "a debug build sees all")
