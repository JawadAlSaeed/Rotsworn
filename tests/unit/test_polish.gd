extends GutTest
## Phase 6 polish: button hints follow the device in use (card #45: keyboard keys, pad buttons, or
## both in mixed local co-op), {action} templates, the HP damage trail and the menu rows.

var _pad_before: bool
var _both_before: bool


func before_each() -> void:
	_pad_before = ButtonPrompts._pad
	_both_before = ButtonPrompts._both
	ButtonPrompts._pad = false
	ButtonPrompts._both = false


func after_each() -> void:
	ButtonPrompts._pad = _pad_before
	ButtonPrompts._both = _both_before


func test_binding_parts_read_the_input_map() -> void:
	assert_eq(HudStyle.binding_parts(&"defend_parry"), ["Space", "RB"] as Array[String])
	assert_eq(HudStyle.binding_parts(&"menu_confirm"), ["Enter", "A"] as Array[String])


func test_nav_tokens_have_both_kinds() -> void:
	var parts := HudStyle.binding_parts(&"@move")
	assert_eq(parts[0], "WASD")
	assert_eq(parts[1], "L-stick")


func test_hints_show_keys_then_pad_then_both() -> void:
	assert_eq(ButtonPrompts.mode(), ButtonPrompts.Mode.KEYBOARD)
	assert_eq(HudStyle.binding_text(&"defend_parry"), "Space")
	ButtonPrompts._pad = true
	assert_eq(ButtonPrompts.mode(), ButtonPrompts.Mode.PAD)
	assert_eq(HudStyle.binding_text(&"defend_parry"), "RB")
	ButtonPrompts.set_both(true)
	assert_eq(ButtonPrompts.mode(), ButtonPrompts.Mode.BOTH)
	assert_eq(HudStyle.binding_text(&"defend_parry"), "Space / RB")


func test_unbound_kind_falls_back_to_what_exists() -> void:
	# The practice keys have no pad button; a pad player still sees the key rather than nothing.
	InputMap.add_action(&"test_only_key")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_K
	InputMap.action_add_event(&"test_only_key", ev)
	ButtonPrompts._pad = true
	assert_eq(HudStyle.binding_text(&"test_only_key"), "K")
	InputMap.erase_action(&"test_only_key")


func test_prompt_templates_fill_in_buttons() -> void:
	assert_eq(PromptLabel.fill("press {menu_confirm} to join"), "press Enter to join")
	ButtonPrompts._pad = true
	assert_eq(PromptLabel.fill("press {menu_confirm} to join"), "press A to join")
	assert_eq(PromptLabel.fill("{defend_parry} then {defend_dodge}"), "RB then B")
	assert_eq(PromptLabel.fill("no buttons"), "no buttons")


func test_hint_bar_draws_one_chip_per_kind_shown() -> void:
	var row := HintBar.entry_row(&"defend_parry", "Parry", 24)
	# Chip, text.
	assert_eq(row.get_child_count(), 2)
	row.free()
	ButtonPrompts._both = true
	row = HintBar.entry_row(&"defend_parry", "Parry", 24)
	# Key chip, "/", pad chip, text.
	assert_eq(row.get_child_count(), 4)
	row.free()


func test_trail_bar_keeps_the_lost_part_then_drains() -> void:
	var bar := TrailBar.new(Color.GREEN, 20.0, Color.YELLOW, 300, 300, 200)
	add_child_autofree(bar)
	bar.set_values(100, 100)
	assert_eq(bar._bar.value, 100.0)
	bar.set_values(60, 100)
	# The bar drops at once; the trail still shows the old value.
	assert_eq(bar._bar.value, 60.0)
	assert_eq(bar._trail.value, 100.0)
	await wait_seconds(0.8)
	assert_almost_eq(bar._trail.value, 60.0, 0.01)


func test_list_menu_rows_carry_values_and_wrap() -> void:
	var menu := ListMenu.new()
	add_child_autofree(menu)
	var items: Array[Dictionary] = [{"text": "Volume", "value": "50%"}, {"text": "Back"}]
	menu.set_items(items)
	assert_eq(menu._values[0].text, "50%")
	assert_false(menu._values[1].visible)
	menu._move(-1)
	assert_eq(menu.index, 1)
	menu._move(1)
	assert_eq(menu.index, 0)


func test_button_chip_picks_a_picture_per_button() -> void:
	assert_eq(ButtonChip.shape_of("A", true), ButtonChip.Shape.FACE)
	assert_eq(ButtonChip.shape_of("Menu", true), ButtonChip.Shape.MENU)
	assert_eq(ButtonChip.shape_of("View", true), ButtonChip.Shape.VIEW)
	assert_eq(ButtonChip.shape_of("D-pad up", true), ButtonChip.Shape.DPAD)
	assert_eq(ButtonChip.shape_of("L-stick", true), ButtonChip.Shape.STICK)
	assert_eq(ButtonChip.shape_of("RB", true), ButtonChip.Shape.PILL)
	# Keyboard keys are always key caps, even one called "A".
	assert_eq(ButtonChip.shape_of("A", false), ButtonChip.Shape.KEY)


func test_dpad_lights_the_arms_the_hint_means() -> void:
	assert_eq(ButtonChip.dpad_directions("D-pad \u2191\u2193"), [Vector2i.UP, Vector2i.DOWN] as Array[Vector2i])
	assert_eq(ButtonChip.dpad_directions("D-pad \u2190\u2192"), [Vector2i.LEFT, Vector2i.RIGHT] as Array[Vector2i])
	assert_eq(ButtonChip.dpad_directions("D-pad left"), [Vector2i.LEFT] as Array[Vector2i])
	assert_eq(ButtonChip.dpad_directions("D-pad").size(), 4)


func test_ink_box_is_inside_the_line_and_centred_letters_are_measurable() -> void:
	var line := TextLine.new()
	line.add_string("A", ThemeDB.fallback_font, 40)
	var ink := ButtonChip.ink_rect(line)
	assert_gt(ink.size.x, 0.0)
	assert_gt(ink.size.y, 0.0)
	# Capital letters sit above the baseline and within the line's width.
	assert_lt(ink.position.y, 0.0)
	assert_lte(ink.end.x, line.get_size().x + 2.0)


func test_chip_sizes_follow_the_font_size() -> void:
	var face := ButtonChip.new("A", true, 40)
	assert_eq(face.custom_minimum_size, Vector2(50.0, 50.0))
	var key := ButtonChip.new("Backspace", false, 40)
	assert_gt(key.custom_minimum_size.x, key.custom_minimum_size.y)
	face.free()
	key.free()
