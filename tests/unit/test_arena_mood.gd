extends GutTest
## The arena's phase-two shift and a place's air in its fights (card #196, DESIGN.md 7.3 and 8.12).

const LOOK_DIR := "res://data/looks/"
const ACT_DIR := "res://data/runs/acts/"
const ZONE_DIR := "res://data/zones/"


func _look(shift: bool = true) -> StageLook:
	var look := StageLook.new()
	look.phase_two_enabled = shift
	look.fog_density = 0.02
	look.phase_fog_density = 0.06
	look.light_energy = 1.0
	look.phase_light_energy = 0.5
	look.light_color = Color(1, 1, 1)
	look.phase_light_color = Color(1, 0, 0)
	look.phase_lamp_percent = 200
	return look


func test_values_start_at_the_base_and_end_at_phase_two() -> void:
	var look := _look()
	var start := PhaseShift.values(look, 0.0)
	var end := PhaseShift.values(look, 1.0)
	assert_almost_eq(float(start.fog_density), 0.02, 0.0001)
	assert_almost_eq(float(end.fog_density), 0.06, 0.0001)
	assert_eq(end.light_color, Color(1, 0, 0))
	assert_almost_eq(float(start.lamp_scale), 1.0, 0.0001)
	assert_almost_eq(float(end.lamp_scale), 2.0, 0.0001)


func test_values_halfway_are_between() -> void:
	var mid := PhaseShift.values(_look(), 0.5)
	assert_almost_eq(float(mid.light_energy), 0.75, 0.0001)
	assert_almost_eq(float(mid.fog_density), 0.04, 0.0001)


func test_a_look_without_a_shift_never_changes() -> void:
	var look := _look(false)
	assert_false(PhaseShift.has_shift(look))
	assert_almost_eq(float(PhaseShift.values(look, 1.0).fog_density), 0.02, 0.0001)
	assert_almost_eq(float(PhaseShift.values(look, 1.0).lamp_scale), 1.0, 0.0001)


func test_progress_is_clamped_and_eased() -> void:
	assert_eq(PhaseShift.ease_t(-1.0), 0.0)
	assert_eq(PhaseShift.ease_t(2.0), 1.0)
	assert_almost_eq(PhaseShift.ease_t(0.5), 0.5, 0.0001)
	assert_lt(PhaseShift.ease_t(0.1), 0.1, "slow start")
	assert_almost_eq(float(PhaseShift.values(_look(), 7.0).fog_density), 0.06, 0.0001)


func test_the_shift_takes_longer_when_flashes_are_toned_down() -> void:
	assert_eq(PhaseShift.duration_ms(1000, 200, PlayerSettings.FLASH_FULL), 1000)
	assert_eq(PhaseShift.duration_ms(1000, 200, PlayerSettings.FLASH_REDUCED), 2000)
	assert_eq(PhaseShift.duration_ms(1000, 200, PlayerSettings.FLASH_OFF), 2000)


func test_fight_air_is_thinner_and_shallower_and_leaves_the_zone_data_alone() -> void:
	var data := ZoneAmbientData.new()
	data.amount = 80
	data.area = Vector3(14.0, 3.0, 10.0)
	var list: Array[ZoneAmbientData] = [data, null]
	var air := PhaseShift.fight_air(list, 50, 60)
	assert_eq(air.size(), 1, "null entries are skipped")
	assert_eq(air[0].amount, 40)
	assert_almost_eq(air[0].area.z, 6.0, 0.0001)
	assert_almost_eq(air[0].area.x, 14.0, 0.0001)
	assert_eq(data.amount, 80)
	assert_almost_eq(data.area.z, 10.0, 0.0001)
	data.amount = 1
	assert_eq(PhaseShift.fight_air(list, 10, 100)[0].amount, 1, "never fewer than one")


func test_the_mood_tweens_the_environment_and_stops() -> void:
	var look := _look()
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	var lamps: Array[FlickerLight] = []
	var lamp := FlickerLight.new()
	lamp.setup(2.0, 0, 6.0)
	lamps.append(lamp)
	var mood := ArenaMood.new()
	add_child_autofree(mood)
	add_child_autofree(sun)
	add_child_autofree(lamp)
	mood.setup(look, env, sun, null, lamps)
	assert_false(mood.shifted())
	mood.begin(1000)
	assert_true(mood.shifted())
	mood._process(0.5)
	assert_almost_eq(env.fog_density, 0.04, 0.0001)
	mood._process(0.6)
	assert_almost_eq(env.fog_density, 0.06, 0.0001)
	assert_almost_eq(sun.light_energy, 0.5, 0.0001)
	assert_almost_eq(lamp.light_energy, 4.0, 0.0001)
	assert_false(mood.is_processing(), "done: no more per-frame work")
	mood.begin(1000)
	assert_false(mood.is_processing(), "a second phase does not start it again")


func test_a_look_without_a_shift_ignores_begin() -> void:
	var mood := ArenaMood.new()
	add_child_autofree(mood)
	mood.setup(_look(false), Environment.new(), null, null, [] as Array[FlickerLight])
	mood.begin(1000)
	assert_false(mood.shifted())


func test_every_boss_and_guard_arena_has_a_phase_two_look() -> void:
	var looks: Array[StageLook] = []
	for file: String in DirAccess.get_files_at(ACT_DIR):
		if file.ends_with(".tres"):
			var act := load(ACT_DIR + file) as ActData
			assert_not_null(act.final_look, "%s names its boss lair" % file)
			looks.append(act.final_look)
	for file: String in DirAccess.get_files_at(ZONE_DIR):
		if file.ends_with(".tres"):
			var zone := load(ZONE_DIR + file) as ZoneData
			assert_not_null(zone.look, "%s has a look" % file)
			looks.append(zone.look)
	assert_gt(looks.size(), 4)
	for look: StageLook in looks:
		assert_true(PhaseShift.has_shift(look), "%s shifts in phase two" % look.resource_path)


func test_every_phase_two_look_really_changes_the_room() -> void:
	for file: String in DirAccess.get_files_at(LOOK_DIR):
		if not file.ends_with(".tres"):
			continue
		var look := load(LOOK_DIR + file) as StageLook
		if not PhaseShift.has_shift(look):
			continue
		var start := PhaseShift.values(look, 0.0)
		var end := PhaseShift.values(look, 1.0)
		var moved := 0
		for key: String in start:
			if start[key] != end[key]:
				moved += 1
		assert_gt(moved, 3, "%s: the shift touches light, fog and vignette" % file)
		assert_not_null(look.phase_burst, "%s has a puff of particles" % file)
		assert_lte(float(end.fog_density), 0.3, "%s keeps the fog readable" % file)


func test_the_throne_goes_darker_and_redder() -> void:
	var look := load(LOOK_DIR + "hollow_throne.tres") as StageLook
	var start := PhaseShift.values(look, 0.0)
	var end := PhaseShift.values(look, 1.0)
	assert_lt(float(end.light_energy), float(start.light_energy))
	assert_gt((end.light_color as Color).r - (end.light_color as Color).g,
			(start.light_color as Color).r - (start.light_color as Color).g, "redder light")
	assert_gt(float(end.vignette_strength), float(start.vignette_strength))
	assert_gt(float(end.fog_density), float(start.fog_density))
	assert_false(look.arena_air.is_empty(), "the throne has embers in the air")


func test_fight_air_is_data() -> void:
	var visuals := load("res://data/presentation/combat_visuals.tres") as CombatVisuals
	assert_gt(visuals.fight_air_percent, 0)
	assert_lt(visuals.fight_air_percent, 100, "a fight thins its place's own air")
	assert_gt(visuals.phase_look_ms, 0)
	assert_lt(visuals.fight_air_offset.z, 1.0, "the air hangs behind the fighters")
	for file: String in DirAccess.get_files_at(ZONE_DIR):
		if file.ends_with(".tres"):
			var zone := load(ZONE_DIR + file) as ZoneData
			assert_false(zone.ambient.is_empty(), "%s has air to bring into its fights" % file)
