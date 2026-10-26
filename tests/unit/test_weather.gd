extends GutTest
## Weather (card #303, DESIGN.md 8.20): a weather is picked from a seed by its weights (the same on
## every machine; a run fight's own roll is tested in test_run_fights.gd), changes only a copy of a
## place's look and its air, and every shipped weather is complete (icon, sounds, air art).

const ZONES := ["res://data/zones/rotten_hollow.tres", "res://data/zones/sunken_bog.tres",
		"res://data/zones/ashen_ruins.tres"]
const LIBRARY := "res://data/audio/sfx_library.tres"


func _weather(id: String) -> WeatherData:
	var w := WeatherData.new()
	w.id = id
	return w


func test_pick_is_the_same_for_a_seed_and_follows_the_weights() -> void:
	var list: Array[WeatherData] = [_weather("rain"), _weather("fog"), _weather("never")]
	var weights: Array[int] = [3, 1, 0]
	var seen := {}
	for seed_value: int in range(1, 400):
		var a := WeatherData.pick(list, weights, 2, seed_value)
		assert_eq(a, WeatherData.pick(list, weights, 2, seed_value), "same seed, same weather")
		seen[a.id if a != null else "clear"] = int(seen.get(a.id if a != null else "clear", 0)) + 1
	assert_true(seen.has("clear") and seen.has("rain") and seen.has("fog"), str(seen))
	assert_false(seen.has("never"), "a weight of 0 never comes")
	assert_gt(int(seen.rain), int(seen.fog), "rain weighs more than fog")


func test_pick_with_nothing_is_clear() -> void:
	var none: Array[WeatherData] = []
	var no_weights: Array[int] = []
	assert_null(WeatherData.pick(none, no_weights, 3, 7))
	assert_null(WeatherData.pick(none, no_weights, 0, 7))
	var one: Array[WeatherData] = [_weather("rain")]
	assert_eq(WeatherData.pick(one, no_weights, 0, 7).id, "rain", "a missing weight counts 1")


func test_apply_changes_a_copy_only() -> void:
	var look := StageLook.new()
	var before := look.light_energy
	var w := _weather("dusk")
	w.light_energy_percent = 50
	w.sun_pitch_degrees = -20.0
	w.fog_density_add = 0.01
	w.light_color = Color.RED
	w.light_color_mix = 1.0
	w.sway_percent = 300
	var out := w.apply_to(look)
	assert_ne(out, look)
	assert_eq(look.light_energy, before, "the zone's own look is shared: never changed")
	assert_almost_eq(out.light_energy, before * 0.5, 0.0001)
	assert_eq(out.light_rotation_degrees.x, -20.0, "a low sun")
	assert_almost_eq(out.fog_density, look.fog_density + 0.01, 0.0001)
	assert_eq(out.light_color, Color.RED)
	assert_eq(out.sway_percent, 300)
	assert_eq(out.light_rotation_degrees.y, look.light_rotation_degrees.y, "the sun keeps its direction")


func test_air_thins_the_zone_and_adds_its_own() -> void:
	var zone_air: Array[ZoneAmbientData] = [ZoneAmbientData.new()]
	zone_air[0].amount = 40
	var w := _weather("rain")
	w.zone_air_percent = 25
	var drops := ZoneAmbientData.new()
	drops.id = "drops"
	w.air = [drops] as Array[ZoneAmbientData]
	var out := w.air_with(zone_air)
	assert_eq(out.size(), 2)
	assert_eq(out[0].amount, 10)
	assert_eq(zone_air[0].amount, 40, "the zone's own air is not changed")
	assert_eq(out[1], drops)
	w.zone_air_percent = 0
	assert_eq(w.air_with(zone_air).size(), 1, "0%: the zone's own air is gone")


func test_shipped_weather_is_complete() -> void:
	var library := load(LIBRARY) as SfxLibrary
	for path: String in ZONES:
		var zone := load(path) as ZoneData
		assert_false(zone.weathers.is_empty(), "%s has weather" % path)
		assert_eq(zone.weather_weights.size(), zone.weathers.size(), "%s: one weight per weather" % path)
		for w: WeatherData in zone.weathers:
			assert_not_null(w, path)
			if w == null:
				continue
			assert_false(w.display_name.is_empty(), w.id)
			if not w.ambience_path.is_empty():
				assert_true(ResourceLoader.exists(w.ambience_path), w.ambience_path)
			if w.has_lightning():
				assert_not_null(library.find(w.thunder_sfx), "%s: thunder cue" % w.id)
			for air: ZoneAmbientData in w.air:
				assert_true(ResourceLoader.exists(air.texture_path), air.texture_path)
			assert_lt(w.air.reduce(func(n: int, a: ZoneAmbientData) -> int: return n + a.amount, 0), 1500,
					"%s: a particle budget (card #237)" % w.id)


func test_wind_scales_the_sway_of_props() -> void:
	var data := ZonePropData.new()
	data.sway = 0.2
	var look := StageLook.new()
	look.sway_percent = 250
	look.sway_speed_percent = 200
	var sprite := StageBuilder.prop(data, look)
	var mat := sprite.material_override as ShaderMaterial
	assert_almost_eq(float(mat.get_shader_parameter("sway")), 0.5, 0.0001)
	assert_almost_eq(float(mat.get_shader_parameter("sway_speed")), StageBuilder.SWAY_SPEED * 2.0, 0.0001)
	sprite.free()


func test_rain_streaks_stand_along_their_fall() -> void:
	var rain := ZoneAmbientData.new()
	rain.stretch = 10.0
	rain.size = 0.03
	rain.velocity = Vector3(0, -12, 0)
	var particles := StageBuilder.ambient(rain)
	assert_eq(particles.transform_align, GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY)
	assert_almost_eq((particles.draw_pass_1 as QuadMesh).size.y, 0.3, 0.0001)
	particles.free()
	var mote := StageBuilder.ambient(ZoneAmbientData.new())
	assert_eq(mote.transform_align, GPUParticles3D.TRANSFORM_ALIGN_DISABLED, "other air is unchanged")
	mote.free()


func test_a_guards_rage_shifts_from_the_weathered_room() -> void:
	var look := (load(ZONES[0]) as ZoneData).look
	var storm := load("res://data/weather/storm.tres") as WeatherData
	var out := storm.apply_to(look)
	assert_almost_eq(out.phase_ambient_energy, look.phase_ambient_energy * storm.ambient_energy_percent / 100.0, 0.0001)
	assert_almost_eq(out.phase_light_energy, look.phase_light_energy * storm.light_energy_percent / 100.0, 0.0001)
	assert_almost_eq(out.phase_vignette_strength, clampf(look.phase_vignette_strength + storm.vignette_add, 0.0, 1.0), 0.0001)
	assert_eq(signf(out.phase_light_energy - out.light_energy), signf(look.phase_light_energy - look.light_energy),
			"the rage still dims or brightens the room the same way as in clear weather")


func test_drifting_air_is_born_upwind() -> void:
	var dust := ZoneAmbientData.new()
	dust.velocity = Vector3(6, 0.2, 0.3)
	dust.lifetime = 3.0
	var particles := StageBuilder.ambient(dust)
	var offset := (particles.process_material as ParticleProcessMaterial).emission_shape_offset
	assert_almost_eq(offset.x, -9.0, 0.001, "half of its 18 m drift")
	assert_almost_eq(offset.y, 0.0, 0.001, "falling and rising are left alone")
	assert_true(particles.visibility_aabb.has_point(Vector3(-9.0 - dust.area.x, 0, 0)), "still drawn where it is born")
	particles.free()
	dust.wobble = 0.4
	var turbulent := StageBuilder.ambient(dust)
	assert_eq((turbulent.process_material as ParticleProcessMaterial).emission_shape_offset, Vector3.ZERO,
			"wobbling air hardly drifts: it stays round the camera")
	turbulent.free()


func test_lightning_lights_up_and_always_gives_the_light_back() -> void:
	var storm := load("res://data/weather/storm.tres") as WeatherData
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_energy = 0.5
	var fx := WeatherFx.new().setup(storm, env, load("res://data/presentation/combat_visuals.tres") as CombatVisuals)
	add_child_autofree(fx)
	var before := PlayerSettings.flash_mode()
	PlayerSettings.set_persistence(false)
	PlayerSettings.set_flash_mode(PlayerSettings.FLASH_FULL)
	fx.strike()
	assert_gt(env.environment.ambient_light_energy, 0.5, "the sky lights up")
	fx.process_mode = Node.PROCESS_MODE_DISABLED
	assert_eq(env.environment.ambient_light_energy, 0.5, "held behind the pause menu: the flash ends at once")
	fx.process_mode = Node.PROCESS_MODE_INHERIT
	PlayerSettings.set_flash_mode(PlayerSettings.FLASH_OFF)
	fx.strike()
	assert_eq(env.environment.ambient_light_energy, 0.5, "Flashes off: no flash")
	PlayerSettings.set_flash_mode(PlayerSettings.FLASH_FULL)
	fx.strike()
	remove_child(fx)
	assert_eq(env.environment.ambient_light_energy, 0.5, "parked for a fight: the zone's own light")
	add_child(fx)
	PlayerSettings.set_flash_mode(before)
	PlayerSettings.set_persistence(true)
	env.free()


func test_no_lightning_behind_the_backpack() -> void:
	var storm := load("res://data/weather/storm.tres") as WeatherData
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_energy = 0.5
	# A box: a lambda keeps a copy of a plain local.
	var held := [true]
	var fx := WeatherFx.new().setup(storm, env, load("res://data/presentation/combat_visuals.tres") as CombatVisuals,
			func() -> bool: return bool(held[0]))
	add_child_autofree(fx)
	fx._next_ms = 0
	fx._process(0.0)
	assert_eq(env.environment.ambient_light_energy, 0.5, "the zone's own pause holds the storm")
	assert_gt(fx._next_ms, Time.get_ticks_msec() + storm.lightning_min_ms - 100, "and the next strike is a whole gap away")
	held[0] = false
	fx._next_ms = 0
	var before := PlayerSettings.flash_mode()
	PlayerSettings.set_persistence(false)
	PlayerSettings.set_flash_mode(PlayerSettings.FLASH_FULL)
	fx._process(0.0)
	assert_gt(env.environment.ambient_light_energy, 0.5, "free again: it strikes")
	PlayerSettings.set_flash_mode(before)
	PlayerSettings.set_persistence(true)
	env.free()
