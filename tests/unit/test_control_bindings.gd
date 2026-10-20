extends GutTest
## Rebinding keys and buttons (card #190, DESIGN.md 6 and 7.5): the binding model (what is bound,
## conflicts, swap, saving) and how it reaches the Input Map and the button hints. The settings
## screen's Controls pages and a page's own reset (card #277) are in test_settings_pages.gd.
## Nothing here reads or writes the real user://settings.cfg.

var _project: ControlBindings
var _settings_before: ConfigFile
var _shared_before: ControlBindings


func before_each() -> void:
	# The project's own keys, read before any test changes the Input Map.
	_project = ControlBindings.from_input_map()
	_settings_before = PlayerSettings._config
	PlayerSettings._config = ConfigFile.new()
	PlayerSettings.set_persistence(false)
	_shared_before = ControlBindings.shared
	ControlBindings.shared = null


func after_each() -> void:
	_project.apply_to_input_map(true)
	PlayerSettings._config = _settings_before
	PlayerSettings.set_persistence(true)
	ControlBindings.shared = _shared_before


static func _key(code: int) -> Dictionary:
	return {"k": "key", "code": code}


static func _button(code: int) -> Dictionary:
	return {"k": "btn", "code": code}


# --- the defaults ---------------------------------------------------------------------------

func test_every_action_exists_and_has_a_key_and_a_pad_input() -> void:
	for action: StringName in ControlBindings.ACTIONS:
		assert_true(InputMap.has_action(action), "%s is in the Input Map" % action)
		assert_false(_project.inputs(action, ControlBindings.KEY).is_empty(), "%s has a key" % action)
		assert_false(_project.inputs(action, ControlBindings.PAD).is_empty(), "%s has a pad input" % action)
		assert_true(ControlBindings.LABELS.has(action), "%s has a label" % action)
		assert_true(ControlBindings.DETAILS.has(action), "%s has a line of help" % action)


func test_the_defaults_do_not_clash_and_keep_confirm_back_and_pause() -> void:
	assert_eq(_project.conflict_pairs(), [], "no two live actions share a button by default")
	assert_true(_project.reachable())
	assert_true(_project.is_default())


func test_groups_only_name_rebindable_actions() -> void:
	for group: Array in ControlBindings.GROUPS:
		for action: StringName in group:
			assert_true(ControlBindings.ACTIONS.has(action), "%s is rebindable" % action)


func test_first_inputs_are_what_the_hints_show() -> void:
	assert_eq(HudStyle.input_name(_project.primary(&"defend_parry", ControlBindings.KEY)), "Space")
	assert_eq(HudStyle.input_name(_project.primary(&"defend_parry", ControlBindings.PAD)), "RB")
	assert_eq(HudStyle.input_name(_project.primary(&"fight_ultimate", ControlBindings.PAD)), "RT")
	assert_eq(HudStyle.input_name(_project.primary(&"defend_dodge", ControlBindings.KEY)), "Shift")


# --- events ---------------------------------------------------------------------------------

func test_events_round_trip_and_match_every_pad() -> void:
	for input: Dictionary in [_key(KEY_K), _button(JOY_BUTTON_X), {"k": "axis", "code": JOY_AXIS_TRIGGER_RIGHT, "dir": 1}]:
		var ev := ControlBindings.event_from_input(input)
		assert_not_null(ev)
		assert_true(ControlBindings.same(ControlBindings.input_from_event(ev), input))
		assert_eq(ev.device, -1, "bound to all devices")


func test_a_rebound_button_reaches_the_input_map_for_any_pad() -> void:
	var model := ControlBindings.from_input_map()
	assert_true(bool(model.assign(&"defend_dodge", _button(JOY_BUTTON_X)).ok))
	model.apply_to_input_map()
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_X
	press.pressed = true
	press.device = 2
	assert_true(InputMap.event_is_action(press, &"defend_dodge"), "pad 2 dodges with X")
	press.button_index = JOY_BUTTON_B
	assert_false(InputMap.event_is_action(press, &"defend_dodge"), "the old button no longer dodges")


func test_a_rebound_key_is_matched_the_way_defense_input_matches() -> void:
	var model := ControlBindings.from_input_map()
	assert_true(bool(model.assign(&"defend_parry", _key(KEY_K)).ok))
	model.apply_to_input_map()
	var press := InputEventKey.new()
	press.physical_keycode = KEY_K
	press.pressed = true
	# DefenseInput asks with exact_match false; the menus with true.
	assert_true(press.is_action_pressed(&"defend_parry", false, false))
	assert_true(press.is_action_pressed(&"defend_parry", false, true))
	press.physical_keycode = KEY_SPACE
	assert_false(press.is_action_pressed(&"defend_parry", false, false), "Space no longer parries")
	assert_true(press.is_action_pressed(&"skill_press", false, false), "but it is still the skill press")


func test_hints_follow_a_rebinding() -> void:
	var model := ControlBindings.from_input_map()
	assert_true(bool(model.assign(&"defend_parry", _key(KEY_K)).ok))
	assert_true(bool(model.assign(&"defend_parry", _button(JOY_BUTTON_Y)).ok))
	model.apply_to_input_map()
	assert_eq(HudStyle.binding_parts(&"defend_parry"), ["K", "Y"] as Array[String])
	assert_eq(HudStyle.binding_text(&"defend_parry"), "K")
	assert_eq(PromptLabel.fill("parry with {defend_parry}"), "parry with K")
	_project.apply_to_input_map(true)
	assert_eq(HudStyle.binding_parts(&"defend_parry"), ["Space", "RB"] as Array[String])


func test_movement_hints_follow_the_keys() -> void:
	assert_eq(HudStyle.binding_parts(&"@move"), ["WASD", "L-stick"] as Array[String])
	assert_eq(HudStyle.binding_parts(&"@updown"), ["↑↓", "D-pad ↑↓"] as Array[String])
	var model := ControlBindings.from_input_map()
	assert_true(bool(model.assign(&"move_up", _key(KEY_I)).ok))
	assert_true(bool(model.assign(&"menu_up", _key(KEY_I)).ok))
	model.apply_to_input_map()
	assert_eq(HudStyle.binding_parts(&"@move")[0], "IASD")
	assert_eq(HudStyle.binding_parts(&"@updown")[0], "I/Down")


# --- rebinding rules ------------------------------------------------------------------------

func test_rebinding_replaces_the_first_key_and_keeps_the_aliases() -> void:
	var model := ControlBindings.from_input_map()
	var arrows := model.inputs(&"move_up", ControlBindings.KEY)
	assert_eq(arrows.size(), 2, "W and the up arrow")
	var result := model.assign(&"move_up", _key(KEY_I))
	assert_true(bool(result.ok))
	var after := model.inputs(&"move_up", ControlBindings.KEY)
	assert_eq(after.size(), 2)
	assert_true(ControlBindings.same(after[0], _key(KEY_I)))
	assert_true(ControlBindings.same(after[1], arrows[1]), "the arrow key still walks")
	assert_false(model.is_default())


func test_giving_an_alias_as_the_first_key_does_not_double_it() -> void:
	var model := ControlBindings.from_input_map()
	var up := model.inputs(&"move_up", ControlBindings.KEY)[1]
	assert_true(bool(model.assign(&"move_up", up).ok))
	assert_eq(model.inputs(&"move_up", ControlBindings.KEY).size(), 1)


func test_two_defence_buttons_cannot_share_a_key() -> void:
	var model := ControlBindings.from_input_map()
	var result := model.assign(&"defend_dodge", _key(KEY_SPACE))
	assert_false(bool(result.ok))
	assert_eq(result.why, "conflict")
	assert_eq(result.with, [&"defend_parry"] as Array[StringName])
	assert_true(model.is_default(), "a refused change changes nothing")


func test_the_same_key_is_fine_in_groups_that_never_run_together() -> void:
	var model := ControlBindings.from_input_map()
	# Parry and the skill press both use Space already; E is Attack and Confirm in the fight menu.
	assert_true(bool(model.assign(&"defend_parry", _key(KEY_E)).ok), "E in the defence group is free")
	assert_true(bool(model.assign(&"field_strike", _key(KEY_I)).ok))
	assert_true(bool(model.assign(&"menu_up", _key(KEY_I)).ok), "walking and menus are different groups")
	assert_eq(model.conflict_pairs(), [])


func test_attack_and_confirm_may_share_and_back_and_pause_may_share() -> void:
	var model := ControlBindings.from_input_map()
	assert_true(bool(model.assign(&"fight_attack", _key(KEY_ENTER)).ok), "Confirm also has Enter")
	assert_true(bool(model.assign(&"pause", _key(KEY_Q)).ok), "Back also has Q")


func test_a_button_held_by_two_actions_cannot_be_swapped() -> void:
	var model := ControlBindings.from_input_map()
	var result := model.assign(&"fight_skills", _key(KEY_E))
	assert_eq(result.why, "conflict")
	assert_eq((result.with as Array).size(), 2, "Attack and Confirm both have E")
	assert_false(model.can_swap(&"fight_skills", _key(KEY_E)))
	assert_eq(model.assign(&"fight_skills", _key(KEY_E), true).why, "no_swap")


func test_swap_trades_places() -> void:
	var model := ControlBindings.from_input_map()
	assert_true(model.can_swap(&"defend_dodge", _key(KEY_SPACE)))
	var result := model.assign(&"defend_dodge", _key(KEY_SPACE), true)
	assert_true(bool(result.ok))
	assert_eq(result.swapped, &"defend_parry")
	assert_true(ControlBindings.same(model.primary(&"defend_dodge", ControlBindings.KEY), _key(KEY_SPACE)))
	assert_true(ControlBindings.same(model.primary(&"defend_parry", ControlBindings.KEY), _key(KEY_SHIFT)))
	assert_eq(model.conflict_pairs(), [])


func test_swap_with_a_pad_button() -> void:
	var model := ControlBindings.from_input_map()
	var result := model.assign(&"defend_parry", _button(JOY_BUTTON_A), true)
	assert_eq(result.swapped, &"defend_jump", "A was Jump")
	assert_true(ControlBindings.same(model.primary(&"defend_jump", ControlBindings.PAD), _button(JOY_BUTTON_RIGHT_SHOULDER)))


func test_swap_with_an_alias_puts_the_old_key_there() -> void:
	var model := ControlBindings.from_input_map()
	var down_key := model.primary(&"menu_down", ControlBindings.KEY)
	# W is the second key of "menu up" (WASD next to the arrows).
	var result := model.assign(&"menu_down", _key(KEY_W), true)
	assert_true(bool(result.ok), "menu down takes W, menu up takes the arrow it gave up")
	assert_eq(result.swapped, &"menu_up")
	assert_true(ControlBindings.same(model.primary(&"menu_down", ControlBindings.KEY), _key(KEY_W)))
	var up_keys := model.inputs(&"menu_up", ControlBindings.KEY)
	var has_old := false
	for held: Dictionary in up_keys:
		has_old = has_old or ControlBindings.same(held, down_key)
		assert_false(ControlBindings.same(held, _key(KEY_W)), "menu up lost W")
	assert_true(has_old)
	assert_eq(model.conflict_pairs(), [])


func test_reserved_and_unsupported_inputs_are_refused() -> void:
	var model := ControlBindings.from_input_map()
	assert_eq(model.assign(&"defend_parry", _key(KEY_ESCAPE)).why, "reserved")
	assert_eq(model.assign(&"defend_parry", _key(KEY_F2)).why, "reserved")
	assert_eq(model.assign(&"defend_parry", _button(JOY_BUTTON_START)).why, "reserved")
	assert_eq(model.assign(&"defend_parry", {"k": "axis", "code": JOY_AXIS_LEFT_X, "dir": 1}).why, "unsupported", "sticks drift")
	assert_eq(model.assign(&"defend_parry", {"k": "axis", "code": JOY_AXIS_TRIGGER_LEFT, "dir": -1}).why, "unsupported")
	assert_eq(model.assign(&"defend_parry", {}).why, "unsupported")
	assert_eq(model.assign(&"ui_accept", _key(KEY_K)).why, "unknown")
	assert_true(bool(model.assign(&"defend_parry", {"k": "axis", "code": JOY_AXIS_TRIGGER_LEFT, "dir": 1}).ok), "a trigger is fine")
	assert_true(model.inputs(&"defend_parry", ControlBindings.PAD).size() >= 1)


func test_no_series_of_changes_can_lock_the_player_out() -> void:
	var model := ControlBindings.from_input_map()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1190
	var keys: Array[int] = [KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K, KEY_L,
			KEY_SPACE, KEY_SHIFT, KEY_ENTER, KEY_TAB, KEY_BACKSPACE, KEY_UP, KEY_DOWN, KEY_Q, KEY_W, KEY_ESCAPE]
	for step: int in 400:
		var action: StringName = ControlBindings.ACTIONS[rng.randi() % ControlBindings.ACTIONS.size()]
		var input: Dictionary
		if rng.randi() % 2 == 0:
			input = _key(keys[rng.randi() % keys.size()])
		else:
			input = _button(rng.randi() % JOY_BUTTON_SDL_MAX)
		model.assign(action, input, rng.randi() % 2 == 0)
		assert_eq(model.conflict_pairs(), [], "step %d: no clash" % step)
		assert_true(model.reachable(), "step %d: confirm, back and pause keep a key and a button" % step)
		for each: StringName in ControlBindings.ACTIONS:
			assert_false(model.inputs(each, ControlBindings.KEY).is_empty(), "%s keeps a key" % each)
			assert_false(model.inputs(each, ControlBindings.PAD).is_empty(), "%s keeps a pad input" % each)
	model.reset_all()
	assert_true(model.is_default())


func test_reset_one_action_and_all() -> void:
	var model := ControlBindings.from_input_map()
	model.assign(&"defend_parry", _key(KEY_K))
	model.assign(&"defend_jump", _key(KEY_L))
	model.reset_action(&"defend_parry")
	assert_true(model.is_action_default(&"defend_parry"))
	assert_false(model.is_action_default(&"defend_jump"))
	model.reset_all()
	assert_true(model.is_default())
	assert_eq(model.overrides(), {})


# --- saving ---------------------------------------------------------------------------------

func test_changes_survive_saving_and_loading() -> void:
	var model := ControlBindings.from_input_map()
	model.assign(&"defend_parry", _key(KEY_K))
	model.assign(&"defend_dodge", _button(JOY_BUTTON_X))
	model.assign(&"fight_ultimate", _button(JOY_BUTTON_LEFT_SHOULDER))
	var saved := model.overrides()
	assert_eq(saved.size(), 3, "only the changed actions are saved")
	PlayerSettings.set_control_overrides(saved)
	var again := ControlBindings.from_input_map()
	again.load_overrides(PlayerSettings.control_overrides())
	for action: StringName in ControlBindings.ACTIONS:
		for kind: String in [ControlBindings.KEY, ControlBindings.PAD]:
			var a := model.inputs(action, kind)
			var b := again.inputs(action, kind)
			assert_eq(a.size(), b.size(), "%s %s" % [action, kind])
			for i: int in a.size():
				assert_true(ControlBindings.same(a[i], b[i]))
	PlayerSettings.set_control_overrides({})
	assert_eq(PlayerSettings.control_overrides(), {}, "saving nothing forgets the changes")


func test_the_saved_form_is_plain_data() -> void:
	var model := ControlBindings.from_input_map()
	model.assign(&"defend_parry", _key(KEY_K))
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "defend_parry", model.overrides()["defend_parry"])
	var text := cfg.encode_to_text()
	var back := ConfigFile.new()
	assert_eq(back.parse(text), OK)
	var loaded := ControlBindings.from_input_map()
	loaded.load_overrides({"defend_parry": back.get_value("controls", "defend_parry")})
	assert_true(ControlBindings.same(loaded.primary(&"defend_parry", ControlBindings.KEY), _key(KEY_K)))


func test_a_broken_file_is_ignored_piece_by_piece() -> void:
	var model := ControlBindings.from_input_map()
	model.load_overrides({
		"defend_parry": {"key": [{"k": "key", "code": KEY_K}], "pad": "junk"},
		"not_an_action": {"key": [{"k": "key", "code": KEY_K}]},
		"defend_jump": 7,
		"defend_dodge": {"key": [{"k": "btn", "code": 3}, {"k": "key"}, 5]},
	})
	assert_true(ControlBindings.same(model.primary(&"defend_parry", ControlBindings.KEY), _key(KEY_K)))
	assert_true(ControlBindings.same(model.primary(&"defend_parry", ControlBindings.PAD), _project.primary(&"defend_parry", ControlBindings.PAD)), "bad pad list: default kept")
	assert_true(model.is_action_default(&"defend_jump"))
	assert_true(model.is_action_default(&"defend_dodge"), "nothing usable in it")


func test_a_saved_clash_or_lost_confirm_drops_every_change() -> void:
	var clash := ControlBindings.from_input_map()
	clash.load_overrides({
		"defend_parry": {"key": [{"k": "key", "code": KEY_K}]},
		"defend_dodge": {"key": [{"k": "key", "code": KEY_K}]},
	})
	assert_true(clash.is_default(), "two defence buttons on K: back to the defaults")
	var empty := ControlBindings.from_input_map()
	empty.load_overrides({"menu_confirm": {"key": [], "pad": []}, "defend_parry": {"key": [{"k": "key", "code": KEY_K}]}})
	assert_true(empty.reachable())
	assert_true(ControlBindings.same(empty.primary(&"defend_parry", ControlBindings.KEY), _key(KEY_K)))


func test_escape_in_a_saved_file_is_fine_for_back_and_pause() -> void:
	var model := ControlBindings.from_input_map()
	model.assign(&"pause", _key(KEY_P))
	var saved := model.overrides()
	var loaded := ControlBindings.from_input_map()
	loaded.load_overrides(saved)
	assert_true(ControlBindings.same(loaded.primary(&"pause", ControlBindings.KEY), _key(KEY_P)))
	var with_escape := ControlBindings.from_input_map()
	with_escape.load_overrides({"menu_cancel": {"key": [{"k": "key", "code": KEY_ESCAPE}, {"k": "key", "code": KEY_BACKSPACE}]}})
	assert_true(ControlBindings.same(with_escape.primary(&"menu_cancel", ControlBindings.KEY), _key(KEY_ESCAPE)))


# --- the menu list scrolls ------------------------------------------------------------------

func test_a_list_with_a_window_scrolls_with_the_cursor() -> void:
	var menu := ListMenu.new()
	menu.window_rows = 3
	add_child_autofree(menu)
	var items: Array[Dictionary] = []
	for i: int in 8:
		items.append({"text": "Row %d" % i})
	menu.set_items(items)
	assert_eq(menu.top_row(), 0)
	menu.index = 4
	menu.redraw()
	assert_eq(menu.top_row(), 2, "the chosen row is the last one shown")
	menu.index = 0
	menu.redraw()
	assert_eq(menu.top_row(), 0)
	menu.index = 7
	menu.redraw()
	assert_eq(menu.top_row(), 5)


# --- the Controls pages in the settings screen ---------------------------------------------
# Rebinding on the settings screen (its Keyboard and Controller pages, card #277) is tested in
# test_settings_pages.gd.

static func _key_press(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.pressed = true
	return ev


# --- the timing path and start-up -----------------------------------------------------------

func test_defense_input_stamps_a_rebound_key_and_not_the_old_one() -> void:
	var model := ControlBindings.from_input_map()
	assert_true(bool(model.assign(&"defend_parry", _key(KEY_K)).ok))
	assert_true(bool(model.assign(&"defend_dodge", _button(JOY_BUTTON_X)).ok))
	model.apply_to_input_map()
	var defense := DefenseInput.new()
	add_child_autofree(defense)
	defense.arm_all()
	watch_signals(defense)
	defense._input(_key_press(KEY_K))
	assert_signal_emit_count(defense, "pressed", 1)
	assert_eq(get_signal_parameters(defense, "pressed")[0], Defense.Outcome.PARRY)
	defense._input(_key_press(KEY_SPACE))
	assert_signal_emit_count(defense, "pressed", 1, "Space no longer parries")
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_X
	press.pressed = true
	press.device = 1
	defense._input(press)
	assert_signal_emit_count(defense, "pressed", 2)
	assert_eq(get_signal_parameters(defense, "pressed")[0], Defense.Outcome.DODGE)
	assert_eq(get_signal_parameters(defense, "pressed")[3], 1, "the press still names the pad it came from")


func test_install_applies_the_saved_changes_before_anything_reads_them() -> void:
	var model := ControlBindings.from_input_map()
	model.assign(&"defend_parry", _key(KEY_K))
	model.assign(&"menu_confirm", _key(KEY_X))
	var installed := ControlBindings.install(model.overrides())
	assert_eq(installed, ControlBindings.shared)
	assert_eq(HudStyle.binding_parts(&"defend_parry")[0], "K")
	assert_eq(HudStyle.binding_parts(&"menu_confirm")[0], "X")
	assert_true(installed.reachable())
	# Untouched actions keep the project's own events.
	assert_eq(HudStyle.binding_parts(&"defend_jump")[0], "W")


func test_install_with_nothing_saved_leaves_the_input_map_alone() -> void:
	var before := InputMap.action_get_events(&"defend_parry").size()
	var installed := ControlBindings.install({})
	assert_true(installed.is_default())
	assert_eq(InputMap.action_get_events(&"defend_parry").size(), before)
