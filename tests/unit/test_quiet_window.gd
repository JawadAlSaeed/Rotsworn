extends GutTest
## Quiet picture runs (card #168): only the quiet launcher's shadow project turns the no-focus
## window on; the real project and every normal start stay as they are.


func test_quiet_only_when_the_no_focus_setting_is_on() -> void:
	assert_true(QuietWindow.is_quiet(true), "no_focus on: quiet")
	assert_false(QuietWindow.is_quiet(false), "no_focus off: normal")
	assert_false(QuietWindow.is_quiet(null), "setting missing: normal")
	assert_false(QuietWindow.is_quiet("true"), "a stray string is not the flag")


func test_a_normal_test_run_is_not_quiet() -> void:
	assert_false(QuietWindow.active(), "the test run uses the real project settings")


func test_the_real_project_never_sets_no_focus() -> void:
	# The flag must only ever exist in the launcher's shadow copy. If it landed in project.godot,
	# every normal start would open a window that cannot take focus (and could not be typed into).
	var text := FileAccess.get_file_as_string("res://project.godot")
	assert_false(text.is_empty(), "project.godot readable")
	assert_false(text.contains("no_focus"), "project.godot has no no_focus line")
	assert_false(FileAccess.file_exists("res://override.cfg"), "no override.cfg next to project.godot")


func test_the_launcher_files_exist() -> void:
	for path in ["res://quiet_run.bat", "res://tools/quiet_run.ps1", "res://tools/quiet_focus_check.ps1", "res://tools/quiet/QuietNative.cs"]:
		assert_true(FileAccess.file_exists(path), "%s exists" % path)


func test_the_launcher_keeps_the_promises_in_the_docs() -> void:
	var script := FileAccess.get_file_as_string("res://tools/quiet_run.ps1")
	assert_true(script.contains("window/size/no_focus"), "turns the no-focus flag on")
	assert_true(script.contains("--audio-driver"), "runs silent")
	assert_true(script.contains("Rotsworn-quiet"), "builds the shadow project outside the repo")
	assert_false(script.contains("Remove-Item -Recurse"), "never deletes recursively (folder links lead into the real project)")
