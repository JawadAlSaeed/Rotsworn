extends GutTest
## Save & Quit (DESIGN 8.13): the run save round trips through a file, a write that fails leaves the
## old save alone, a save from other content or another format is refused, and delete clears it
## all. Every test uses a file in the OS temp folder, never the player's real save.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const FINGERPRINT := "abc123"

var _tuning := Tuning.new()
var _data: RunData
var _path: String


func before_all() -> void:
	_data = load(RUN_PATH) as RunData


func before_each() -> void:
	_path = OS.get_temp_dir().path_join("rotsworn_test_run_save_%d.json" % Time.get_ticks_usec())
	RunSave.delete(_path)


func after_each() -> void:
	# A test may have made a folder where the temp file goes.
	if DirAccess.dir_exists_absolute(_path + RunSave.TEMP_SUFFIX):
		DirAccess.remove_absolute(_path + RunSave.TEMP_SUFFIX)
	RunSave.delete(_path)


func _progressed_run() -> RunState:
	var run := RunState.begin(_data, _tuning, 4242)
	run.gold = 77
	run.add_xp(0, 150)
	run.hp[1] = 5
	var first := run.choices()[0]
	run.go(first)
	return run


func test_round_trip_keeps_the_whole_run() -> void:
	var run := _progressed_run()
	assert_true(RunSave.save(run.to_dict(), FINGERPRINT, true, 2, _path), "saved")
	assert_true(RunSave.exists(_path))
	var loaded := RunSave.load_save(FINGERPRINT, _path)
	assert_eq(loaded.status, RunSave.LOADED)
	assert_true(bool(loaded.in_stop), "in a stop")
	assert_eq(int(loaded.players), 2)
	var copy := RunState.from_dict(_data, _tuning, loaded.run as Dictionary)
	assert_not_null(copy, "the run fits again")
	assert_eq(copy.to_dict(), run.to_dict(), "the same run, key for key")
	assert_eq(copy.at, run.at, "the same stop")


func test_numbers_come_back_as_ints() -> void:
	RunSave.save({"seed": 5, "list": [1, 2, [3]], "nested": {"a": 7}}, FINGERPRINT, false, 1, _path)
	var loaded := RunSave.load_save(FINGERPRINT, _path)
	assert_eq(typeof(loaded.run.seed), TYPE_INT)
	assert_eq(typeof(loaded.run.list[2][0]), TYPE_INT)
	assert_eq(typeof(loaded.run.nested.a), TYPE_INT)
	assert_false(bool(loaded.in_stop), "on the map")


func test_the_dictionary_is_saved_as_it_is() -> void:
	# Another builder adds keys to RunState.to_dict(); the save never looks at them.
	var run := _progressed_run().to_dict()
	run["oath"] = 3
	run["something_new"] = {"x": [1, 2]}
	RunSave.save(run, FINGERPRINT, false, 1, _path)
	var loaded := RunSave.load_save(FINGERPRINT, _path)
	assert_eq(loaded.run, run)


func test_missing_save() -> void:
	assert_false(RunSave.exists(_path))
	assert_eq(RunSave.load_save(FINGERPRINT, _path).status, RunSave.MISSING)


func test_other_content_is_refused() -> void:
	RunSave.save(_progressed_run().to_dict(), FINGERPRINT, false, 1, _path)
	var loaded := RunSave.load_save("another content", _path)
	assert_eq(loaded.status, RunSave.REJECTED)
	assert_string_contains(String(loaded.reason), "content")


func test_other_format_is_refused() -> void:
	var body := {"format": RunSave.FORMAT_VERSION + 1, "fingerprint": FINGERPRINT, "in_stop": false, "players": 1,
			"run": {"seed": 1}}
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(body))
	file.close()
	var loaded := RunSave.load_save(FINGERPRINT, _path)
	assert_eq(loaded.status, RunSave.REJECTED)
	assert_string_contains(String(loaded.reason), "version")


func test_damaged_file_is_refused() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("{\"format\": 1, \"fingerp")
	file.close()
	assert_eq(RunSave.load_save(FINGERPRINT, _path).status, RunSave.REJECTED)


func test_a_run_from_other_data_does_not_fit() -> void:
	# The file reads fine, but RunState refuses it (the caller then deletes it).
	RunSave.save({"seed": 9, "at": 0}, FINGERPRINT, false, 1, _path)
	var loaded := RunSave.load_save(FINGERPRINT, _path)
	assert_eq(loaded.status, RunSave.LOADED)
	assert_null(RunState.from_dict(_data, _tuning, loaded.run as Dictionary))


func test_a_failed_write_keeps_the_old_save() -> void:
	var old := _progressed_run()
	RunSave.save(old.to_dict(), FINGERPRINT, false, 1, _path)
	# A folder where the temp file goes makes the write fail.
	DirAccess.make_dir_absolute(_path + RunSave.TEMP_SUFFIX)
	var newer := _progressed_run()
	newer.gold = 999
	assert_false(RunSave.save(newer.to_dict(), FINGERPRINT, true, 1, _path), "the write failed")
	var loaded := RunSave.load_save(FINGERPRINT, _path)
	assert_eq(loaded.status, RunSave.LOADED)
	assert_eq(int(loaded.run.gold), 77, "still the old save")
	assert_false(bool(loaded.in_stop))


func test_saving_into_a_missing_folder_fails_cleanly() -> void:
	var bad := OS.get_temp_dir().path_join("rotsworn_no_such_folder_%d/run.json" % Time.get_ticks_usec())
	assert_false(RunSave.save({"seed": 1}, FINGERPRINT, false, 1, bad))
	assert_false(RunSave.exists(bad))


func test_a_new_save_replaces_the_old_one_and_a_temp_file_is_left_behind_by_none() -> void:
	RunSave.save({"seed": 1, "gold": 1}, FINGERPRINT, false, 1, _path)
	RunSave.save({"seed": 1, "gold": 2}, FINGERPRINT, true, 1, _path)
	assert_eq(int(RunSave.load_save(FINGERPRINT, _path).run.gold), 2)
	assert_false(FileAccess.file_exists(_path + RunSave.TEMP_SUFFIX), "no temp file")


func test_a_leftover_temp_file_changes_nothing() -> void:
	RunSave.save({"seed": 1, "gold": 1}, FINGERPRINT, false, 1, _path)
	var junk := FileAccess.open(_path + RunSave.TEMP_SUFFIX, FileAccess.WRITE)
	junk.store_string("half written")
	junk.close()
	assert_eq(int(RunSave.load_save(FINGERPRINT, _path).run.gold), 1)
	# And the next save simply writes over it.
	assert_true(RunSave.save({"seed": 1, "gold": 3}, FINGERPRINT, false, 1, _path))
	assert_eq(int(RunSave.load_save(FINGERPRINT, _path).run.gold), 3)


func test_the_backup_covers_a_broken_main_file() -> void:
	RunSave.save({"seed": 1, "gold": 1}, FINGERPRINT, false, 1, _path)
	RunSave.save({"seed": 1, "gold": 2}, FINGERPRINT, false, 1, _path)
	# The main file breaks after the second save: the first is still there as the backup.
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("garbage")
	file.close()
	var loaded := RunSave.load_save(FINGERPRINT, _path)
	assert_eq(loaded.status, RunSave.LOADED)
	assert_eq(int(loaded.run.gold), 1)


func test_delete_clears_everything() -> void:
	RunSave.save({"seed": 1}, FINGERPRINT, false, 1, _path)
	RunSave.save({"seed": 1}, FINGERPRINT, false, 1, _path)
	var junk := FileAccess.open(_path + RunSave.TEMP_SUFFIX, FileAccess.WRITE)
	junk.close()
	RunSave.delete(_path)
	assert_false(RunSave.exists(_path))
	assert_false(FileAccess.file_exists(_path + RunSave.TEMP_SUFFIX))
	assert_eq(RunSave.load_save(FINGERPRINT, _path).status, RunSave.MISSING)


func test_player_count_is_kept_within_bounds() -> void:
	RunSave.save({"seed": 1}, FINGERPRINT, false, 99, _path)
	assert_eq(int(RunSave.load_save(FINGERPRINT, _path).players), PlayerRoster.MAX_PLAYERS)
