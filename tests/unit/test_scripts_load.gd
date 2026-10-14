extends GutTest
## The big presentation scripts no unit test instantiates still parse and load: a type-inference
## error in them would otherwise only show up in a smoke run.

const SCRIPTS := [
	"res://scripts/combat/presentation/combat_controller.gd",
	"res://scripts/combat/presentation/skill_sequence_runner.gd",
	"res://scripts/combat/presentation/timed_sequence_runner.gd",
	"res://scripts/explore/zone_controller.gd",
	"res://scenes/main.gd",
]


func test_presentation_scripts_load() -> void:
	for path: String in SCRIPTS:
		var script := load(path) as GDScript
		assert_not_null(script, "%s loads" % path)
		if script != null:
			assert_true(script.can_instantiate(), "%s compiles" % path)
