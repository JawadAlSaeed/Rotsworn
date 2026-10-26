extends GutTest
## Backlog run rules: the team gauge carries over between fights (card #146).

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const RUN_PATH := "res://data/runs/rotten_road.tres"


func test_a_fight_can_start_with_gauge() -> void:
	var setup := Fx.setup([Fx.attack("one", [Fx.hit(900)])])
	setup.start_team_gauge = 40
	var engine := CombatEngine.new(setup)
	var events := engine.start()
	assert_eq(engine.team_gauge, 40)
	var gauge := Fx.first_of(events, "team_gauge")
	assert_eq(int(gauge.value), 40)
	assert_gt(Fx.index_of(events, "team_gauge"), Fx.index_of(events, "combat_started"), "after the fighters exist")
	var mirror := CombatMirror.new()
	for e: Dictionary in events:
		mirror.apply(e)
	assert_eq(mirror.team_gauge, 40, "the screen shows it too")


func test_no_gauge_event_when_empty() -> void:
	var engine := CombatEngine.new(Fx.setup([Fx.attack("one", [Fx.hit(900)])]))
	assert_eq(Fx.of_type(engine.start(), "team_gauge").size(), 0)


func test_too_much_gauge_is_refused() -> void:
	var setup := Fx.setup([Fx.attack("one", [Fx.hit(900)])])
	setup.start_team_gauge = setup.tuning.team_gauge_max + 1
	assert_false(setup.validate().is_empty())


func test_the_run_carries_the_gauge() -> void:
	var run := RunState.begin(load(RUN_PATH) as RunData, Tuning.new(), 3)
	assert_eq(run.team_gauge, 0, "a new run starts empty")
	run.carry_team_gauge(70)
	assert_eq(run.team_gauge, CombatMath.percent(70, run.tuning.run_team_gauge_carry_percent))
	var husk := load("res://data/encounters/husk_fight.tres") as EncounterData
	assert_eq(run.fight_setup(husk, 2, CombatSetup.Opening.NORMAL).start_team_gauge, run.team_gauge)
	run.carry_team_gauge(9999)
	assert_eq(run.team_gauge, CombatMath.percent(run.tuning.team_gauge_max, run.tuning.run_team_gauge_carry_percent),
			"never past full")
	var copy := RunState.from_dict(run.data, run.tuning, run.to_dict())
	assert_eq(copy.team_gauge, run.team_gauge, "online players see it too")
	run.tuning.run_team_gauge_carry_percent = 0
	run.carry_team_gauge(70)
	assert_eq(run.team_gauge, 0, "0% keeps the old rule")


# --- the loading screen blocks input (card #132) ----------------------------------------------

func test_the_transition_covers_only_while_shown() -> void:
	var t := ScreenTransition.new()
	add_child_autofree(t)
	t.setup(CombatVisuals.new())
	assert_false(t.is_covering(), "nothing shown at first")
	await t.fade_out()
	assert_true(t.is_covering(), "black: input is blocked")
	await t.fade_in()
	assert_false(t.is_covering(), "faded back in: input works again")


# --- feints on the hit timeline (card #129) ---------------------------------------------------

func test_intents_say_which_hits_are_feints() -> void:
	var real := Fx.hit(900)
	var fake := Fx.hit(1500)
	fake.feint = true
	var events := CombatEngine.new(Fx.setup([Fx.attack("tricky", [real, fake])], {"enemy_speed": 10})).start()
	var shown := Fx.first_of(events, "intent")
	assert_eq(Array(shown.feints), [false, true])
	assert_eq((shown.kinds as Array).size(), (shown.feints as Array).size())


# --- graphics options (card #112) -------------------------------------------------------------

func _look() -> StageLook:
	var look := StageLook.new()
	look.fog_density = 0.02
	look.glow_enabled = true
	look.sun_shadows = true
	return look


func test_graphics_options_turn_parts_of_a_look_off_and_on() -> void:
	var kept: ConfigFile = PlayerSettings._config
	# An in-memory settings file, never saved, so the player's own file is untouched.
	PlayerSettings._config = ConfigFile.new()
	var env := StageBuilder.environment(_look())
	var sun := StageBuilder.sun(_look())
	assert_true(env.environment.fog_enabled, "on by default")
	assert_true(sun.shadow_enabled)
	PlayerSettings._config.set_value(PlayerSettings.SECTION_GRAPHICS, "fog", false)
	PlayerSettings._config.set_value(PlayerSettings.SECTION_GRAPHICS, "shadows", false)
	var root := Node.new()
	root.add_child(env)
	root.add_child(sun)
	StageBuilder.apply_settings(root)
	assert_false(env.environment.fog_enabled, "fog off")
	assert_false(sun.shadow_enabled, "shadows off")
	assert_true(env.environment.glow_enabled, "bloom untouched")
	PlayerSettings._config.set_value(PlayerSettings.SECTION_GRAPHICS, "fog", true)
	StageBuilder.apply_settings(root)
	assert_true(env.environment.fog_enabled, "back on: the look still wants it")
	var plain := StageLook.new()
	plain.fog_density = 0.0
	plain.fog_height_density = 0.0
	var bare := StageBuilder.environment(plain)
	assert_false(bare.environment.fog_enabled, "a look without fog stays without")
	bare.free()
	root.free()
	PlayerSettings._config = kept


func test_screen_shake_setting_is_a_percent() -> void:
	var kept: ConfigFile = PlayerSettings._config
	PlayerSettings._config = ConfigFile.new()
	assert_eq(PlayerSettings.screen_shake_percent(), 100, "full by default")
	PlayerSettings._config.set_value(PlayerSettings.SECTION_GAME, PlayerSettings.KEY_SHAKE, 250)
	assert_eq(PlayerSettings.screen_shake_percent(), 100, "never above full")
	PlayerSettings._config = kept
