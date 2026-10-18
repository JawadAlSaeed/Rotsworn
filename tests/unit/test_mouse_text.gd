extends GutTest
## Mouse in the menus (card #202, DESIGN.md 6.2) and the text size setting (card #203, 7.5).
## Nothing here reads or writes the real user://settings.cfg.

var _settings_before: ConfigFile


func before_each() -> void:
	_settings_before = PlayerSettings._config
	PlayerSettings._config = ConfigFile.new()
	PlayerSettings.set_persistence(false)


func after_each() -> void:
	PlayerSettings._config = _settings_before
	PlayerSettings.set_persistence(true)
	HudStyle.set_text_size_index(0)
	# The pointer's state is static: back to the start.
	MouseCursor._mouse_active = true
	MouseCursor._menus_allowed = true
	MouseCursor._shown = true


static func _motion(at: Vector2, relative: Vector2 = Vector2(1, 0)) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.relative = relative
	return event


static func _button(index: int, at: Vector2 = Vector2.ZERO, pressed: bool = true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.position = at
	event.pressed = pressed
	return event


# --- the pure helpers ------------------------------------------------------------------------

func test_a_point_finds_its_row() -> void:
	var rects: Array[Rect2] = [Rect2(0, 0, 100, 40), Rect2(0, 50, 100, 40), Rect2()]
	assert_eq(MenuMouse.row_at(rects, Vector2(10, 10)), 0)
	assert_eq(MenuMouse.row_at(rects, Vector2(10, 60)), 1)
	assert_eq(MenuMouse.row_at(rects, Vector2(10, 45)), -1, "the gap between rows is nobody's")
	assert_eq(MenuMouse.row_at(rects, Vector2(500, 500)), -1)
	assert_eq(MenuMouse.row_at(rects, Vector2.ZERO + Vector2(0.5, 0.5)), 0, "an empty rectangle never matches")


func test_the_nearest_point_within_the_radius_wins() -> void:
	var points: Array[Vector2] = [Vector2(100, 100), Vector2(160, 100)]
	assert_eq(MenuMouse.nearest_within(points, Vector2(110, 100), 30.0), 0)
	assert_eq(MenuMouse.nearest_within(points, Vector2(150, 100), 30.0), 1)
	assert_eq(MenuMouse.nearest_within(points, Vector2(125, 100), 30.0), 0, "the closer of two")
	assert_eq(MenuMouse.nearest_within(points, Vector2(300, 300), 30.0), -1, "too far from both")


func test_buttons_mean_confirm_back_or_scroll() -> void:
	assert_eq(MenuMouse.answer_for_button(MOUSE_BUTTON_LEFT), &"confirm")
	assert_eq(MenuMouse.answer_for_button(MOUSE_BUTTON_RIGHT), &"cancel")
	assert_eq(MenuMouse.answer_for_button(MOUSE_BUTTON_XBUTTON1), &"cancel", "the mouse's back button")
	assert_eq(MenuMouse.answer_for_button(MOUSE_BUTTON_MIDDLE), &"")
	assert_eq(MenuMouse.wheel_step(MOUSE_BUTTON_WHEEL_UP), -1)
	assert_eq(MenuMouse.wheel_step(MOUSE_BUTTON_WHEEL_DOWN), 1)
	assert_eq(MenuMouse.wheel_step(MOUSE_BUTTON_LEFT), 0)
	assert_true(MenuMouse.is_back(_button(MOUSE_BUTTON_RIGHT)))
	assert_false(MenuMouse.is_back(_button(MOUSE_BUTTON_RIGHT, Vector2.ZERO, false)), "a release is not a press")
	assert_true(MenuMouse.is_click(_button(MOUSE_BUTTON_LEFT)))
	assert_false(MenuMouse.is_click(_motion(Vector2.ZERO)))


func test_the_side_of_a_row_steps_the_value() -> void:
	assert_eq(MenuMouse.side_of(0.1), -1)
	assert_eq(MenuMouse.side_of(0.49), -1)
	assert_eq(MenuMouse.side_of(0.5), 1)
	assert_eq(MenuMouse.side_of(0.95), 1)


func test_activity_tells_the_mouse_from_the_other_devices() -> void:
	assert_eq(MenuMouse.activity(_motion(Vector2(5, 5))), MenuMouse.Activity.MOUSE)
	assert_eq(MenuMouse.activity(_motion(Vector2(5, 5), Vector2.ZERO)), MenuMouse.Activity.NONE, "no movement")
	assert_eq(MenuMouse.activity(_button(MOUSE_BUTTON_LEFT)), MenuMouse.Activity.MOUSE)
	var key := InputEventKey.new()
	key.keycode = KEY_S
	key.pressed = true
	assert_eq(MenuMouse.activity(key), MenuMouse.Activity.OTHER)
	key.pressed = false
	assert_eq(MenuMouse.activity(key), MenuMouse.Activity.NONE, "a key coming up")
	var pad := InputEventJoypadButton.new()
	pad.pressed = true
	assert_eq(MenuMouse.activity(pad), MenuMouse.Activity.OTHER)
	var stick := InputEventJoypadMotion.new()
	stick.axis_value = 0.2
	assert_eq(MenuMouse.activity(stick), MenuMouse.Activity.NONE, "stick drift")
	stick.axis_value = -0.9
	assert_eq(MenuMouse.activity(stick), MenuMouse.Activity.OTHER)


func test_the_pointer_shows_only_for_the_mouse_on_a_menu() -> void:
	assert_true(MenuMouse.pointer_visible(true, true))
	assert_false(MenuMouse.pointer_visible(false, true), "a key or pad was used last")
	assert_false(MenuMouse.pointer_visible(true, false), "in a fight or a zone")


func test_the_pointer_hides_for_keys_and_shows_again_for_the_mouse() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_S
	key.pressed = true
	MouseCursor.note_event(key)
	assert_false(MouseCursor.is_shown())
	MouseCursor.note_event(_motion(Vector2(3, 3)))
	assert_true(MouseCursor.is_shown())
	MouseCursor.set_menus_allowed(false)
	assert_false(MouseCursor.is_shown(), "hidden in fights and zones whatever moved")
	MouseCursor.note_event(_motion(Vector2(9, 9)))
	assert_false(MouseCursor.is_shown())
	MouseCursor.set_menus_allowed(true)
	assert_true(MouseCursor.is_shown())


func test_no_input_action_listens_to_the_mouse() -> void:
	# The defence buttons are judged from input timestamps (DefenseInput); a mouse button must never
	# be one of them, nor any other action.
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			assert_false(event is InputEventMouse, "%s has a mouse input" % action)


# --- a ListMenu with the mouse ---------------------------------------------------------------

func _menu(count: int = 4) -> ListMenu:
	var menu := ListMenu.new()
	add_child_autofree(menu)
	var items: Array[Dictionary] = []
	for i: int in count:
		items.append({"text": "Row %d" % i, "value": "<  v  >" if i == 1 else ""})
	menu.set_items(items)
	await get_tree().process_frame
	await get_tree().process_frame
	return menu


func _centre_of(menu: ListMenu, row: int) -> Vector2:
	return menu._rows[row].get_global_rect().get_center()


func test_pointing_at_a_row_chooses_it() -> void:
	var menu := await _menu()
	assert_eq(menu.index, 0)
	assert_eq(menu.handle(_motion(_centre_of(menu, 2))), &"", "moving only chooses")
	assert_eq(menu.index, 2)
	menu.handle(_motion(Vector2(-500, -500)))
	assert_eq(menu.index, 2, "pointing at nothing keeps the choice")


func test_a_left_click_confirms_the_row_under_it() -> void:
	var menu := await _menu()
	assert_eq(menu.handle(_button(MOUSE_BUTTON_LEFT, _centre_of(menu, 3))), &"confirm")
	assert_eq(menu.index, 3, "the clicked row is the chosen one")
	assert_eq(menu.handle(_button(MOUSE_BUTTON_LEFT, Vector2(-500, -500))), &"", "a click on nothing does nothing")
	assert_eq(menu.index, 3)
	assert_eq(menu.handle(_button(MOUSE_BUTTON_LEFT, _centre_of(menu, 0), false)), &"", "a release does nothing")


func test_a_right_click_or_the_back_button_goes_back() -> void:
	var menu := await _menu()
	assert_eq(menu.handle(_button(MOUSE_BUTTON_RIGHT, Vector2(-500, -500))), &"cancel", "anywhere on the screen")
	assert_eq(menu.handle(_button(MOUSE_BUTTON_XBUTTON1)), &"cancel")


func test_the_wheel_moves_the_cursor_and_stops_at_the_ends() -> void:
	var menu := await _menu()
	assert_eq(menu.handle(_button(MOUSE_BUTTON_WHEEL_DOWN)), &"")
	assert_eq(menu.index, 1)
	menu.handle(_button(MOUSE_BUTTON_WHEEL_UP))
	menu.handle(_button(MOUSE_BUTTON_WHEEL_UP))
	assert_eq(menu.index, 0, "the wheel does not wrap round")
	for i: int in 9:
		menu.handle(_button(MOUSE_BUTTON_WHEEL_DOWN))
	assert_eq(menu.index, 3)


func test_a_click_says_where_across_the_row_it_landed() -> void:
	var menu := await _menu()
	var rect: Rect2 = menu._rows[1].get_global_rect()
	menu.handle(_button(MOUSE_BUTTON_LEFT, rect.position + Vector2(rect.size.x * 0.1, rect.size.y * 0.5)))
	assert_almost_eq(menu.clicked_share, 0.1, 0.02)
	assert_eq(menu.clicked_value_share, -1.0, "not on the value")
	var value_rect: Rect2 = menu._values[1].get_global_rect()
	menu.handle(_button(MOUSE_BUTTON_LEFT, value_rect.get_center()))
	assert_almost_eq(menu.clicked_value_share, 0.5, 0.05)
	menu.handle(_motion(_centre_of(menu, 2)))
	assert_eq(menu.clicked_share, -1.0, "forgotten after another event")


func test_rows_that_are_not_shown_cannot_be_pointed_at() -> void:
	var menu := ListMenu.new()
	menu.window_rows = 2
	add_child_autofree(menu)
	var items: Array[Dictionary] = []
	for i: int in 5:
		items.append({"text": "Row %d" % i})
	menu.set_items(items)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(menu._rows[4].is_visible_in_tree(), "row 4 is scrolled out of the window")
	assert_ne(menu.row_at(menu._rows[4].get_global_rect().get_center()), 4, "so it cannot be pointed at")
	menu.set_row_shown(1, false)
	await get_tree().process_frame
	assert_eq(menu.row_at(menu._rows[1].get_global_rect().get_center()), -1, "a row the owner hides")


func test_the_keyboard_still_works_in_a_list_that_has_the_mouse() -> void:
	var menu := await _menu()
	var down := InputEventAction.new()
	down.action = &"menu_down"
	down.pressed = true
	menu.handle(down)
	assert_eq(menu.index, 1)
	var confirm := InputEventAction.new()
	confirm.action = &"menu_confirm"
	confirm.pressed = true
	assert_eq(menu.handle(confirm), &"confirm")
	assert_eq(menu.clicked_share, -1.0, "not a click")


func test_controls_are_found_by_their_screen_rectangle() -> void:
	var holder := Control.new()
	holder.size = Vector2(400, 400)
	add_child_autofree(holder)
	var a := Control.new()
	a.position = Vector2(10, 10)
	a.size = Vector2(100, 50)
	var b := Control.new()
	b.position = Vector2(10, 100)
	b.size = Vector2(100, 50)
	holder.add_child(a)
	holder.add_child(b)
	var hidden := Control.new()
	hidden.position = Vector2(10, 200)
	hidden.size = Vector2(100, 50)
	hidden.visible = false
	holder.add_child(hidden)
	await get_tree().process_frame
	var all: Array = [a, b, hidden]
	assert_eq(MenuMouse.control_at(all, Vector2(50, 30)), 0)
	assert_eq(MenuMouse.control_at(all, Vector2(50, 120)), 1)
	assert_eq(MenuMouse.control_at(all, Vector2(50, 220)), -1, "hidden")
	assert_almost_eq(MenuMouse.share_across(a, Vector2(60, 30)), 0.5, 0.01)
	assert_eq(MenuMouse.share_across(a, Vector2(300, 30)), -1.0)


# --- text size -------------------------------------------------------------------------------

func test_the_text_size_steps_come_from_data() -> void:
	var fonts := load("res://data/presentation/ui_fonts.tres") as UiFonts
	assert_eq(fonts.text_size_percents.size(), PlayerSettings.TEXT_SIZE_NAMES.size(), "a percent for every name")
	assert_eq(fonts.text_percent(0), 100, "Normal is as drawn")
	assert_gt(fonts.text_percent(1), 100)
	assert_gt(fonts.text_percent(2), fonts.text_percent(1))
	assert_eq(fonts.text_percent(99), fonts.text_percent(fonts.text_size_percents.size() - 1), "limited")
	assert_eq(UiFonts.new().text_percent(-3), 100)


func test_scaled_sizes_follow_the_chosen_step() -> void:
	assert_eq(HudStyle.scaled(20), 20, "normal changes nothing")
	HudStyle.set_text_size_index(2)
	var percent := HudStyle.text_scale_percent()
	assert_gt(percent, 100)
	assert_eq(HudStyle.scaled(20), roundi(20.0 * float(percent) / 100.0))
	assert_gte(HudStyle.scaled(1), 1)
	var label := HudStyle.make_label("x", 20)
	var number := HudStyle.make_number("1", 20)
	var title := HudStyle.make_title("T", 20)
	assert_eq(label.label_settings.font_size, HudStyle.scaled(20), "labels are built at the new size")
	assert_eq(number.label_settings.font_size, HudStyle.scaled(20))
	assert_eq(title.label_settings.font_size, HudStyle.scaled(20))
	assert_eq(HudStyle.punch_settings(40).font_size, 40, "damage popups and banners keep their size")
	assert_eq(HudStyle.worn_settings(56).font_size, 56, "the big gold titles keep their size")
	label.free()
	number.free()
	title.free()


func test_the_text_size_is_saved_and_a_bad_value_reads_as_normal() -> void:
	assert_eq(PlayerSettings.text_size_index(), 0, "Normal by default")
	PlayerSettings.set_text_size_index(2)
	assert_eq(PlayerSettings.text_size_index(), 2)
	assert_eq(HudStyle.text_size_index(), 2, "HudStyle follows at once")
	PlayerSettings.set_text_size_index(3)
	assert_eq(PlayerSettings.text_size_index(), 0, "the number wraps round")
	PlayerSettings.set_text_size_index(-1)
	assert_eq(PlayerSettings.text_size_index(), 2)
	PlayerSettings._config.set_value(PlayerSettings.SECTION_GAME, PlayerSettings.KEY_TEXT_SIZE, 17)
	assert_eq(PlayerSettings.text_size_index(), 0, "an edited file cannot break it")
	PlayerSettings._config.set_value(PlayerSettings.SECTION_GAME, PlayerSettings.KEY_TEXT_SIZE, "big")
	assert_eq(PlayerSettings.text_size_index(), 0)


func test_bigger_text_shows_fewer_list_rows() -> void:
	assert_eq(SettingsScreen.fitting_rows(100), SettingsScreen.ROWS_AT_NORMAL_SIZE)
	assert_lt(SettingsScreen.fitting_rows(130), SettingsScreen.fitting_rows(100))
	assert_gte(SettingsScreen.fitting_rows(400), 4, "never fewer than four")


func _settings_screen() -> SettingsScreen:
	var screen := SettingsScreen.new()
	var tuning := load("res://data/tuning/tuning.tres") as Tuning
	var visuals := load("res://data/presentation/combat_visuals.tres") as CombatVisuals
	add_child_autofree(screen)
	screen.setup(tuning, visuals)
	return screen


func test_every_settings_section_fits_the_screen_at_the_largest_text() -> void:
	HudStyle.set_text_size_index(PlayerSettings.TEXT_SIZE_NAMES.size() - 1)
	var screen := _settings_screen()
	for section: int in SettingsScreen.Section.size():
		screen.open_section(section as SettingsScreen.Section)
		# The rows of the section before are freed at the end of the frame.
		await get_tree().process_frame
		var height := screen._page.get_combined_minimum_size().y
		assert_lte(height, 1080.0 - ListMenu.FOOTER_STRIP_PX, "section %d fits (it is %d tall)" % [section, int(height)])
		assert_lte(screen._page.get_combined_minimum_size().x, 1920.0, "section %d fits the width" % section)


func test_changing_the_text_size_in_settings_rebuilds_the_page_at_the_new_size() -> void:
	var screen := _settings_screen()
	screen.open_section(SettingsScreen.Section.GAME)
	var before := screen._tabs[0].label_settings.font_size
	var confirm := InputEventAction.new()
	confirm.action = &"menu_confirm"
	confirm.pressed = true
	assert_eq(screen._rows_of(SettingsScreen.Section.GAME)[0], "text_size")
	screen._unhandled_input(confirm)
	assert_eq(PlayerSettings.text_size_index(), 1, "Confirm steps to Large")
	assert_gt(screen._tabs[0].label_settings.font_size, before, "the section names are drawn bigger")
	assert_eq(screen._section, SettingsScreen.Section.GAME, "still on the same section")
	assert_eq(screen._menu.index, 0, "and the same row")


func test_clicking_a_value_row_steps_by_the_side_clicked() -> void:
	var screen := _settings_screen()
	screen.open_section(SettingsScreen.Section.SOUND)
	await get_tree().process_frame
	await get_tree().process_frame
	var rect: Rect2 = screen._menu._rows[1].get_global_rect()
	var before := PlayerSettings.channel_percent("music")
	screen._unhandled_input(_button(MOUSE_BUTTON_LEFT, rect.position + Vector2(rect.size.x * 0.9, rect.size.y * 0.5)))
	assert_eq(PlayerSettings.channel_percent("music"), mini(100, before + PlayerSettings.VOLUME_STEP_PERCENT) if before < 100 else 100)
	rect = screen._menu._rows[1].get_global_rect()
	PlayerSettings.set_channel_percent("music", 50)
	screen._unhandled_input(_button(MOUSE_BUTTON_LEFT, rect.position + Vector2(rect.size.x * 0.1, rect.size.y * 0.5)))
	assert_eq(PlayerSettings.channel_percent("music"), 50 - PlayerSettings.VOLUME_STEP_PERCENT, "the left half turns it down")


func test_clicking_a_section_name_opens_it() -> void:
	var screen := _settings_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	var tab: Label = screen._tabs[SettingsScreen.Section.SOUND]
	screen._unhandled_input(_button(MOUSE_BUTTON_LEFT, tab.get_global_rect().get_center()))
	assert_eq(screen._section, SettingsScreen.Section.SOUND)


# --- the backpack grid ----------------------------------------------------------------------

func test_a_point_finds_its_backpack_cell() -> void:
	# 5 x 3 cells of 90 px, 10 px apart, the first at (20, 30).
	var origin := Vector2(20, 30)
	assert_eq(BackpackGrid.cell_index(Vector2(25, 35), origin, 90.0, 10.0, 5, 3), Vector2i(0, 0))
	assert_eq(BackpackGrid.cell_index(Vector2(20 + 100 * 2 + 50, 30 + 100 + 5), origin, 90.0, 10.0, 5, 3), Vector2i(2, 1))
	assert_eq(BackpackGrid.cell_index(Vector2(20 + 100 * 4 + 89, 30 + 100 * 2 + 89), origin, 90.0, 10.0, 5, 3), Vector2i(4, 2))
	assert_eq(BackpackGrid.cell_index(Vector2(10, 35), origin, 90.0, 10.0, 5, 3), Vector2i(-1, -1), "left of the grid")
	assert_eq(BackpackGrid.cell_index(Vector2(25, 20), origin, 90.0, 10.0, 5, 3), Vector2i(-1, -1), "above it")
	assert_eq(BackpackGrid.cell_index(Vector2(20 + 100 * 5 + 5, 35), origin, 90.0, 10.0, 5, 3), Vector2i(-1, -1), "right of it")
	assert_eq(BackpackGrid.cell_index(Vector2(25, 30 + 100 * 3 + 5), origin, 90.0, 10.0, 5, 3), Vector2i(-1, -1), "below it")
