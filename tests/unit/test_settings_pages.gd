extends GutTest
## Settings > Controls in two pages, Keyboard and Controller (card #277, DESIGN.md 6.1 and 7.5):
## which actions each page lists (the F1 stats overlay only in a debug build), a page's reset only
## touches its own device, the page opened for the device in use, turning the page (LT / RT, Left /
## Right, a click), and rebinding on each page with the clash warnings and the no-lock-out rule (the
## screen tests of card #190 moved here from test_control_bindings.gd). Nothing here reads or
## writes the real user://settings.cfg.

var _project: ControlBindings
var _settings_before: ConfigFile
var _shared_before: ControlBindings
var _pad_before: bool
var _both_before: bool


func before_each() -> void:
	# The project's own keys, read before any test changes the Input Map.
	_project = ControlBindings.from_input_map()
	_settings_before = PlayerSettings._config
	PlayerSettings._config = ConfigFile.new()
	PlayerSettings.set_persistence(false)
	_shared_before = ControlBindings.shared
	ControlBindings.shared = null
	_pad_before = ButtonPrompts._pad
	_both_before = ButtonPrompts._both
	ButtonPrompts._pad = false
	ButtonPrompts._both = false


func after_each() -> void:
	_project.apply_to_input_map(true)
	PlayerSettings._config = _settings_before
	PlayerSettings.set_persistence(true)
	ControlBindings.shared = _shared_before
	ButtonPrompts._pad = _pad_before
	ButtonPrompts._both = _both_before
	HudStyle.set_text_size_index(0)


static func _key(code: int) -> Dictionary:
	return {"k": "key", "code": code}


static func _button(code: int) -> Dictionary:
	return {"k": "btn", "code": code}


static func _key_press(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.pressed = true
	return ev


static func _pad_press(button: int, device: int = 1) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button as JoyButton
	ev.pressed = true
	ev.device = device
	return ev


static func _action(name: StringName) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


static func _click(at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = at
	ev.pressed = true
	return ev


## A settings screen on its Controls section (on the Keyboard page: no pad is in use).
func _settings_screen() -> SettingsScreen:
	var screen := SettingsScreen.new()
	var tuning := load("res://data/tuning/tuning.tres") as Tuning
	var visuals := load("res://data/presentation/combat_visuals.tres") as CombatVisuals
	add_child_autofree(screen)
	screen.setup(tuning, visuals)
	screen.open_section(SettingsScreen.Section.CONTROLS)
	return screen


## The list row of an action (or "reset" / "back") on the page shown.
static func _row(screen: SettingsScreen, id: String) -> int:
	return screen._rows_of(SettingsScreen.Section.CONTROLS).find(id)


## What the row shows on its right: a binding's name (drawn as its button picture) or the value text.
static func _value(screen: SettingsScreen, id: String) -> String:
	return screen.shown_value(_row(screen, id))


# --- which actions a page lists (pure) ------------------------------------------------------

func test_both_pages_list_every_action_and_the_stats_overlay_only_in_a_debug_build() -> void:
	for kind: String in [ControlBindings.KEY, ControlBindings.PAD]:
		var shipped := _project.listed_actions(kind, false)
		var debug := _project.listed_actions(kind, true)
		assert_false(shipped.has(&"debug_overlay"), "%s page: no stats overlay in the real game" % kind)
		assert_true(debug.has(&"debug_overlay"), "%s page: the stats overlay in a debug build" % kind)
		assert_eq(debug.size(), ControlBindings.ACTIONS.size(), "every action has a %s, so every one is listed" % kind)
		var expected: Array[StringName] = []
		for action: StringName in ControlBindings.ACTIONS:
			if not ControlBindings.DEBUG_ONLY.has(action):
				expected.append(action)
		assert_eq(shipped, expected, "%s page: the actions in the usual order" % kind)


func test_a_page_lists_only_actions_with_an_input_of_its_own_kind() -> void:
	var model := ControlBindings.new({
		"defend_parry": {"key": [_key(KEY_SPACE)], "pad": []},
		"defend_dodge": {"key": [], "pad": [_button(JOY_BUTTON_B)]},
	})
	assert_eq(model.listed_actions(ControlBindings.KEY, true), [&"defend_parry"] as Array[StringName])
	assert_eq(model.listed_actions(ControlBindings.PAD, true), [&"defend_dodge"] as Array[StringName])


func test_page_rows_are_the_page_actions_then_its_options_then_reset_and_back() -> void:
	for page: int in SettingsScreen.ControlsPage.size():
		for debug: bool in [false, true]:
			var rows := SettingsScreen.controls_rows(page as SettingsScreen.ControlsPage, _project, debug)
			var actions := _project.listed_actions(SettingsScreen.PAGE_KINDS[page], debug)
			var options: Array = SettingsScreen.PAGE_OPTION_ROWS[page]
			assert_eq(rows.size(), actions.size() + options.size() + 2)
			for i: int in actions.size():
				assert_eq(rows[i], "ctl:" + String(actions[i]))
			assert_eq(rows[rows.size() - 2], "reset", "the page's own reset")
			assert_eq(rows[rows.size() - 1], "back")
			assert_eq(rows.has("ctl:debug_overlay"), debug, "page %d, debug %s: stats overlay" % [page, debug])


func test_the_two_pages_are_keyboard_then_controller() -> void:
	assert_eq(SettingsScreen.PAGE_NAMES, ["Keyboard", "Controller"] as Array[String])
	assert_eq(SettingsScreen.PAGE_KINDS[SettingsScreen.ControlsPage.KEYBOARD], ControlBindings.KEY)
	assert_eq(SettingsScreen.PAGE_KINDS[SettingsScreen.ControlsPage.CONTROLLER], ControlBindings.PAD)
	for glyph: StringName in SettingsScreen.PAGE_GLYPHS:
		assert_true(UiGlyph.KINDS.has(glyph), "%s is a drawn picture" % glyph)


# --- the page opened for the device in use --------------------------------------------------

func test_the_page_for_each_device() -> void:
	assert_eq(SettingsScreen.page_for_device(false), SettingsScreen.ControlsPage.KEYBOARD)
	assert_eq(SettingsScreen.page_for_device(true), SettingsScreen.ControlsPage.CONTROLLER)


func test_the_device_in_use_is_the_last_one_used_even_in_local_co_op() -> void:
	ButtonPrompts._both = true
	ButtonPrompts._pad = false
	assert_true(ButtonPrompts.shows_pad(), "co-op hints show both kinds")
	assert_false(ButtonPrompts.pad_in_use(), "but the keyboard was used last")
	ButtonPrompts._pad = true
	assert_true(ButtonPrompts.pad_in_use())


func test_controls_opens_the_keyboard_page_after_a_key() -> void:
	ButtonPrompts._pad = false
	var screen := _settings_screen()
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.KEYBOARD)
	assert_eq(screen._kind(), ControlBindings.KEY)
	assert_true(screen._device_strip.visible, "the page tabs show on Controls")


func test_controls_opens_the_controller_page_after_a_pad() -> void:
	ButtonPrompts._pad = true
	var screen := _settings_screen()
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.CONTROLLER)
	assert_eq(screen._kind(), ControlBindings.PAD)


func test_coming_back_to_controls_opens_the_page_of_the_device_used_then() -> void:
	var screen := _settings_screen()
	screen.open_page(SettingsScreen.ControlsPage.CONTROLLER)
	screen.open_section(SettingsScreen.Section.SOUND)
	assert_false(screen._device_strip.visible, "no page tabs on other sections")
	screen.open_section(SettingsScreen.Section.CONTROLS)
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.KEYBOARD, "the keyboard is in use")
	ButtonPrompts._pad = true
	screen.open_section(SettingsScreen.Section.GAME)
	screen.open_section(SettingsScreen.Section.CONTROLS)
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.CONTROLLER)


# --- each page shows only its own buttons ---------------------------------------------------

func test_each_page_shows_only_its_own_buttons() -> void:
	var screen := _settings_screen()
	var rows := screen._rows_of(SettingsScreen.Section.CONTROLS)
	assert_eq(rows, SettingsScreen.controls_rows(SettingsScreen.ControlsPage.KEYBOARD, ControlBindings.current(),
			OS.is_debug_build()))
	assert_eq(_value(screen, "ctl:defend_parry"), "Space")
	assert_eq(_value(screen, "ctl:fight_ultimate"), HudStyle.input_name(_project.primary(&"fight_ultimate", ControlBindings.KEY)))
	screen.open_page(SettingsScreen.ControlsPage.CONTROLLER)
	assert_eq(_value(screen, "ctl:defend_parry"), "RB")
	assert_eq(_value(screen, "ctl:fight_ultimate"), "RT")
	for i: int in screen._menu.items.size():
		var value := screen.shown_value(i)
		assert_false(value.contains("Key ") or value.contains("Pad "), "one button per row, not two columns")


func test_the_stats_overlay_row_only_in_a_debug_build() -> void:
	var screen := _settings_screen()
	assert_eq(_row(screen, "ctl:debug_overlay") >= 0, OS.is_debug_build())
	screen.open_page(SettingsScreen.ControlsPage.CONTROLLER)
	assert_eq(_row(screen, "ctl:debug_overlay") >= 0, OS.is_debug_build())


func test_aliases_in_the_detail_line_are_the_page_own() -> void:
	var screen := _settings_screen()
	screen._menu.index = _row(screen, "ctl:move_up")
	screen._refresh()
	assert_true(screen._detail.text.contains("Up"), "the arrow key next to W: " + screen._detail.text)
	screen.open_page(SettingsScreen.ControlsPage.CONTROLLER)
	screen._menu.index = _row(screen, "ctl:move_up")
	screen._refresh()
	assert_true(screen._detail.text.contains("stick"), "the stick next to the D-pad: " + screen._detail.text)


# --- turning the page -----------------------------------------------------------------------

func test_lt_and_rt_open_the_pages_and_keep_the_cursor_on_the_action() -> void:
	var screen := _settings_screen()
	var parry := _row(screen, "ctl:defend_parry")
	screen._menu.index = parry
	screen._refresh()
	screen._unhandled_input(_action(&"party_skills"))
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.CONTROLLER, "RT (K): the Controller page")
	assert_eq(screen._menu.index, _row(screen, "ctl:defend_parry"), "still on Parry")
	screen._unhandled_input(_action(&"party_skills"))
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.CONTROLLER, "RT again stays there")
	screen._unhandled_input(_action(&"party_attributes"))
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.KEYBOARD, "LT (T): the Keyboard page")
	assert_eq(screen._menu.index, parry)


func test_left_and_right_on_any_controls_row_turn_the_page() -> void:
	var screen := _settings_screen()
	screen._menu.index = _row(screen, "ctl:defend_dodge")
	screen._refresh()
	screen._unhandled_input(_action(&"menu_right"))
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.CONTROLLER)
	assert_eq(screen._menu.index, _row(screen, "ctl:defend_dodge"))
	screen._unhandled_input(_action(&"menu_left"))
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.KEYBOARD)
	screen._menu.index = _row(screen, "reset")
	screen._refresh()
	screen._unhandled_input(_action(&"menu_right"))
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.CONTROLLER, "from the reset row too")
	assert_eq(screen._menu.index, _row(screen, "reset"), "still on the reset row")


func test_page_keys_do_nothing_on_other_sections() -> void:
	var screen := _settings_screen()
	screen.open_section(SettingsScreen.Section.SOUND)
	screen._unhandled_input(_action(&"party_skills"))
	assert_eq(screen._section, SettingsScreen.Section.SOUND)
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.KEYBOARD)


func test_the_page_cannot_turn_while_waiting_for_a_new_button() -> void:
	var screen := _settings_screen()
	screen._controls_answer(&"defend_parry", &"confirm")
	screen._unhandled_input(_action(&"party_skills"))
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.KEYBOARD)
	assert_eq(screen._capture_kind, ControlBindings.KEY, "still waiting for a key")


func test_clicking_a_page_tab_opens_it() -> void:
	var screen := _settings_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	var tab := screen._device_tabs[SettingsScreen.ControlsPage.CONTROLLER]
	screen._unhandled_input(_click(tab.get_global_rect().get_center()))
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.CONTROLLER)
	await get_tree().process_frame
	tab = screen._device_tabs[SettingsScreen.ControlsPage.KEYBOARD]
	screen._unhandled_input(_click(tab.get_global_rect().get_center()))
	assert_eq(screen._device_page, SettingsScreen.ControlsPage.KEYBOARD)


func test_the_two_page_tabs_sit_side_by_side() -> void:
	var screen := _settings_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	var left := screen._device_tabs[0].get_global_rect()
	var right := screen._device_tabs[1].get_global_rect()
	assert_almost_eq(left.get_center().y, right.get_center().y, 1.0, "on one line")
	assert_lt(left.end.x, right.position.x, "Keyboard left of Controller")


func test_every_page_fits_the_screen_at_every_text_size() -> void:
	for size: int in PlayerSettings.TEXT_SIZE_NAMES.size():
		HudStyle.set_text_size_index(size)
		var screen := _settings_screen()
		for page: int in SettingsScreen.ControlsPage.size():
			screen.open_page(page as SettingsScreen.ControlsPage)
			# The rows of the page before are freed at the end of the frame.
			await get_tree().process_frame
			var height := screen._page.get_combined_minimum_size().y
			assert_lte(height, 1080.0 - ListMenu.FOOTER_STRIP_PX, "text %d, page %d fits (it is %d tall)" % [size, page, int(height)])
			assert_lte(screen._page.get_combined_minimum_size().x, 1920.0, "text %d, page %d fits the width" % [size, page])
		screen.visible = false


# --- a page's reset touches only its own device ---------------------------------------------

func test_reset_kind_puts_back_only_that_kind() -> void:
	var model := ControlBindings.from_input_map()
	assert_true(bool(model.assign(&"defend_parry", _key(KEY_K)).ok))
	assert_true(bool(model.assign(&"defend_dodge", _button(JOY_BUTTON_X)).ok))
	assert_true(bool(model.assign(&"fight_ultimate", _button(JOY_BUTTON_LEFT_SHOULDER)).ok))
	assert_false(model.is_kind_default(ControlBindings.KEY))
	assert_false(model.is_kind_default(ControlBindings.PAD))
	model.reset_kind(ControlBindings.KEY)
	assert_true(model.is_kind_default(ControlBindings.KEY), "every key is back")
	assert_true(ControlBindings.same(model.primary(&"defend_parry", ControlBindings.KEY), _key(KEY_SPACE)))
	assert_true(ControlBindings.same(model.primary(&"defend_dodge", ControlBindings.PAD), _button(JOY_BUTTON_X)), "the pad kept its change")
	assert_false(model.is_kind_default(ControlBindings.PAD))
	assert_eq(model.conflict_pairs(), [])
	assert_true(model.reachable())
	model.reset_kind(ControlBindings.PAD)
	assert_true(model.is_default())


func test_no_mix_of_changes_and_page_resets_can_lock_the_player_out() -> void:
	var model := ControlBindings.from_input_map()
	var rng := RandomNumberGenerator.new()
	rng.seed = 277
	var keys: Array[int] = [KEY_A, KEY_B, KEY_E, KEY_K, KEY_L, KEY_SPACE, KEY_SHIFT, KEY_ENTER, KEY_Q, KEY_W, KEY_ESCAPE]
	for step: int in 300:
		var roll := rng.randi() % 10
		if roll == 0:
			model.reset_kind(ControlBindings.KEY if rng.randi() % 2 == 0 else ControlBindings.PAD)
		else:
			var action: StringName = ControlBindings.ACTIONS[rng.randi() % ControlBindings.ACTIONS.size()]
			var input := _key(keys[rng.randi() % keys.size()]) if roll % 2 == 0 else _button(rng.randi() % JOY_BUTTON_SDL_MAX)
			model.assign(action, input, rng.randi() % 2 == 0)
		assert_eq(model.conflict_pairs(), [], "step %d: no clash" % step)
		assert_true(model.reachable(), "step %d: confirm, back and pause keep a key and a button" % step)
	model.reset_kind(ControlBindings.KEY)
	model.reset_kind(ControlBindings.PAD)
	assert_true(model.is_default())


func test_a_page_reset_on_the_screen_leaves_the_other_device_alone() -> void:
	var screen := _settings_screen()
	screen._controls_answer(&"defend_parry", &"confirm")
	screen._input(_key_press(KEY_K))
	screen.open_page(SettingsScreen.ControlsPage.CONTROLLER)
	screen._controls_answer(&"defend_parry", &"confirm")
	screen._input(_pad_press(JOY_BUTTON_Y))
	assert_eq(HudStyle.binding_parts(&"defend_parry"), ["K", "Y"] as Array[String])
	assert_eq(_value(screen, "reset"), "changed")
	screen._reset_controls()
	assert_eq(HudStyle.binding_parts(&"defend_parry")[1], "Y", "the first Confirm only asks")
	screen._reset_controls()
	assert_eq(HudStyle.binding_parts(&"defend_parry"), ["K", "RB"] as Array[String], "the pad is back, the key stays")
	assert_eq(_value(screen, "reset"), "", "nothing changed on this page now")
	var saved: Dictionary = PlayerSettings.control_overrides()
	assert_true(saved.has("defend_parry"), "the keyboard change is still saved")
	screen.open_page(SettingsScreen.ControlsPage.KEYBOARD)
	assert_eq(_value(screen, "reset"), "changed")
	screen._reset_controls()
	screen._reset_controls()
	assert_true(ControlBindings.current().is_default())
	assert_eq(PlayerSettings.control_overrides(), {})


func test_a_page_reset_with_nothing_changed_there_says_so() -> void:
	var screen := _settings_screen()
	screen.open_page(SettingsScreen.ControlsPage.CONTROLLER)
	screen._controls_answer(&"defend_parry", &"confirm")
	screen._input(_pad_press(JOY_BUTTON_Y))
	screen.open_page(SettingsScreen.ControlsPage.KEYBOARD)
	assert_eq(_value(screen, "reset"), "", "no key is changed")
	screen._reset_controls()
	screen._reset_controls()
	assert_eq(HudStyle.binding_parts(&"defend_parry")[1], "Y", "the keyboard reset never touches the pad")


# --- rebinding on the pages (card #190's screen tests) ---------------------------------------

func test_screen_rebinds_a_key_and_saves_it() -> void:
	var screen := _settings_screen()
	screen._controls_answer(&"defend_parry", &"confirm")
	assert_eq(screen._capture_kind, ControlBindings.KEY)
	screen._input(_key_press(KEY_K))
	assert_eq(screen._capture_kind, "", "done waiting")
	assert_true(ControlBindings.same(ControlBindings.current().primary(&"defend_parry", ControlBindings.KEY), _key(KEY_K)))
	assert_eq(HudStyle.binding_parts(&"defend_parry")[0], "K", "the hints follow")
	assert_eq(_value(screen, "ctl:defend_parry"), "K")
	var saved: Dictionary = PlayerSettings.control_overrides()
	assert_true(saved.has("defend_parry"))
	assert_eq(saved.size(), 1)


func test_screen_controller_page_takes_a_button_and_ignores_keys() -> void:
	var screen := _settings_screen()
	screen._controls_answer(&"defend_parry", &"right")
	assert_eq(screen._kind(), ControlBindings.PAD, "Right: the Controller page")
	screen._controls_answer(&"defend_parry", &"confirm")
	screen._input(_key_press(KEY_K))
	assert_eq(screen._capture_kind, ControlBindings.PAD, "a key does not answer a button question")
	assert_true(screen._note.contains("Controller page"), "it says which device this page takes: " + screen._note)
	screen._input(_pad_press(JOY_BUTTON_Y))
	assert_eq(screen._capture_kind, "")
	assert_eq(HudStyle.binding_parts(&"defend_parry")[1], "Y")
	assert_eq(HudStyle.binding_parts(&"defend_parry")[0], "Space", "the key is untouched")


func test_screen_keyboard_page_ignores_pad_buttons() -> void:
	var screen := _settings_screen()
	screen._controls_answer(&"defend_parry", &"confirm")
	screen._input(_pad_press(JOY_BUTTON_Y))
	assert_eq(screen._capture_kind, ControlBindings.KEY, "a button does not answer a key question")
	assert_true(screen._note.contains("Keyboard page"), screen._note)
	assert_true(ControlBindings.current().is_default())


func test_screen_escape_and_menu_button_cancel_and_nothing_changes() -> void:
	var screen := _settings_screen()
	screen._controls_answer(&"defend_parry", &"confirm")
	screen._input(_key_press(KEY_ESCAPE))
	assert_eq(screen._capture_kind, "")
	screen.open_page(SettingsScreen.ControlsPage.CONTROLLER)
	screen._controls_answer(&"defend_parry", &"confirm")
	screen._input(_pad_press(JOY_BUTTON_START, 0))
	assert_eq(screen._capture_kind, "")
	assert_true(ControlBindings.current().is_default())
	assert_eq(PlayerSettings.control_overrides(), {})


func test_screen_waiting_too_long_cancels() -> void:
	var screen := _settings_screen()
	screen._controls_answer(&"defend_parry", &"confirm")
	screen._capture_until_ms = Time.get_ticks_msec() - 1
	screen._process(0.0)
	assert_eq(screen._capture_kind, "")
	assert_true(ControlBindings.current().is_default())


func test_screen_conflict_asks_to_swap_and_confirm_swaps() -> void:
	var screen := _settings_screen()
	screen._controls_answer(&"defend_dodge", &"confirm")
	screen._input(_key_press(KEY_SPACE))
	assert_false(screen._swap.is_empty(), "Space is Parry's: asks first")
	assert_true(screen._note.contains("Parry"), "the clash warning names it: " + screen._note)
	assert_true(ControlBindings.current().is_default(), "nothing changed yet")
	screen._unhandled_input(_key_press(KEY_ENTER))
	assert_true(screen._swap.is_empty())
	assert_eq(HudStyle.binding_parts(&"defend_dodge")[0], "Space")
	assert_eq(HudStyle.binding_parts(&"defend_parry")[0], "Shift")


func test_screen_controller_page_warns_of_a_clash_too() -> void:
	var screen := _settings_screen()
	screen.open_page(SettingsScreen.ControlsPage.CONTROLLER)
	screen._controls_answer(&"defend_dodge", &"confirm")
	screen._input(_pad_press(JOY_BUTTON_RIGHT_SHOULDER))
	assert_false(screen._swap.is_empty(), "RB is Parry's: asks first")
	assert_true(screen._note.contains("Parry"), screen._note)
	screen._unhandled_input(_key_press(KEY_BACKSPACE))
	assert_true(screen._swap.is_empty())
	assert_true(ControlBindings.current().is_default(), "Back: nothing changed")


func test_screen_conflict_back_leaves_it() -> void:
	var screen := _settings_screen()
	screen._controls_answer(&"defend_dodge", &"confirm")
	screen._input(_key_press(KEY_SPACE))
	screen._unhandled_input(_key_press(KEY_BACKSPACE))
	assert_true(screen._swap.is_empty())
	assert_true(ControlBindings.current().is_default())


func test_screen_reserved_key_keeps_waiting() -> void:
	var screen := _settings_screen()
	screen._controls_answer(&"defend_dodge", &"confirm")
	screen._input(_key_press(KEY_F2))
	assert_eq(screen._capture_kind, ControlBindings.KEY, "still waiting for a usable key")
	screen._input(_key_press(KEY_L))
	assert_eq(HudStyle.binding_parts(&"defend_dodge")[0], "L")


func test_screen_reset_asks_twice() -> void:
	var screen := _settings_screen()
	screen._controls_answer(&"defend_parry", &"confirm")
	screen._input(_key_press(KEY_K))
	assert_false(ControlBindings.current().is_default())
	screen._reset_controls()
	assert_false(ControlBindings.current().is_default(), "the first Confirm only asks")
	screen._reset_controls()
	assert_true(ControlBindings.current().is_default())
	assert_eq(HudStyle.binding_parts(&"defend_parry")[0], "Space")
	assert_eq(PlayerSettings.control_overrides(), {})


func test_screen_reset_row_and_back_row_are_last_on_both_pages() -> void:
	var screen := _settings_screen()
	for page: int in SettingsScreen.ControlsPage.size():
		screen.open_page(page as SettingsScreen.ControlsPage)
		var rows := screen._rows_of(SettingsScreen.Section.CONTROLS)
		assert_eq(rows[rows.size() - 2], "reset")
		assert_eq(rows[rows.size() - 1], "back")
		assert_eq(screen._menu.items.size(), rows.size())
