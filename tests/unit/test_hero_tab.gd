extends GutTest
## The Y screen's Hero tab (DESIGN.md 8.18): the old Attributes page's rules (8.2, card #175) on the
## new page, the Echo box's door to the Echoes page, and what the tab tells the screen.

const RUN_PATH := "res://data/runs/rotten_road.tres"


## A run where hero 0 has reached level 3 (two level ups of points); the others have none.
func _run() -> RunState:
	var run := RunState.begin(load(RUN_PATH) as RunData, Tuning.new(), 5)
	var t := run.tuning
	run.add_xp(0, t.run_xp_first_level + t.run_xp_first_level + t.run_xp_level_step)
	return run


func _tab(run: RunState, remote: bool = false) -> HeroTab:
	var tab := HeroTab.new()
	add_child_autofree(tab)
	tab.setup(run, remote)
	return tab


func _press(tab: HeroTab, action: StringName) -> bool:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return tab.handle_input(event)


## The viewport point at the middle of `control` (as mouse events report it).
func _centre_of(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func test_adding_and_taking_back_points() -> void:
	var run := _run()
	var tab := _tab(run)
	var free := run.free_points(0)
	assert_gt(free, 1, "hero 0 has points to spend")
	tab.choose_row(Attributes.Kind.MIGHT)
	assert_eq(tab.row(), Attributes.Kind.MIGHT)
	var power := run.power(0)
	assert_true(tab.change(1), "a point goes in")
	assert_eq(run.attribute(0, Attributes.Kind.MIGHT), 1)
	assert_eq(run.free_points(0), free - 1)
	assert_gt(run.power(0), power, "Might raises power")
	assert_true(_press(tab, &"menu_right"), "right adds")
	assert_true(_press(tab, &"menu_confirm"), "Confirm adds too")
	assert_eq(run.attribute(0, Attributes.Kind.MIGHT), 3)
	assert_true(_press(tab, &"menu_left"), "left takes one back")
	assert_eq(run.attribute(0, Attributes.Kind.MIGHT), 2)
	assert_true(tab.change(-1))
	assert_true(tab.change(-1))
	assert_false(tab.change(-1), "nothing left to take back")
	assert_eq(run.attribute(0, Attributes.Kind.MIGHT), 0)
	assert_eq(run.free_points(0), free)


func test_no_points_no_change() -> void:
	var run := _run()
	var tab := _tab(run)
	tab.set_hero(1)
	assert_eq(run.free_points(1), 0, "hero 1 never levelled")
	watch_signals(tab)
	assert_false(tab.change(1))
	assert_eq(Attributes.total(run.attributes[1]), 0, "nothing changed")
	assert_signal_emitted(tab, "toast", "a short toast says why")


func test_every_point_can_go_and_the_last_one_is_refused() -> void:
	var run := _run()
	var tab := _tab(run)
	tab.choose_row(Attributes.Kind.LUCK)
	var free := run.free_points(0)
	for i: int in free:
		assert_true(tab.change(1))
	assert_false(tab.change(1), "out of points")
	assert_eq(run.attribute(0, Attributes.Kind.LUCK), free)


func test_the_reset_asks_first() -> void:
	var run := _run()
	var tab := _tab(run)
	run.set_attributes(0, [1, 2, 0, 1, 0])
	assert_true(_press(tab, &"item_move"))
	assert_true(tab.busy(), "the question is open")
	assert_false(tab._prompt.is_processing_unhandled_input(), "the question hears keys only through the tab")
	assert_eq(Attributes.total(run.attributes[0]), 4, "nothing taken back yet")
	assert_lte(tab.hints().size(), 4)
	assert_true(_press(tab, &"menu_cancel"), "Back goes to the question")
	assert_false(tab.busy())
	assert_eq(Attributes.total(run.attributes[0]), 4, "kept")
	# A press in the frame that answered the question goes nowhere (another pad): wait a frame.
	await get_tree().process_frame
	_press(tab, &"item_move")
	assert_true(tab.busy())
	_press(tab, &"menu_down")
	_press(tab, &"menu_confirm")
	assert_false(tab.busy(), "answered")
	assert_eq(Attributes.total(run.attributes[0]), 0, "every point back")
	assert_eq(run.free_points(0), run.earned_points(0))


func test_a_reset_with_nothing_spent_does_not_ask() -> void:
	var run := _run()
	var tab := _tab(run)
	_press(tab, &"item_move")
	assert_false(tab.busy())


func test_too_wounded_refuses() -> void:
	var run := _run()
	var tab := _tab(run)
	run.set_attributes(0, [run.earned_points(0), 0, 0, 0, 0])
	run.hp[0] = 1
	tab.refresh()
	tab.choose_row(Attributes.Kind.VITALITY)
	watch_signals(tab)
	assert_false(tab.change(-1), "too wounded to give up max HP (card #175)")
	assert_eq(run.attribute(0, Attributes.Kind.VITALITY), run.earned_points(0), "nothing changed")
	assert_signal_emitted(tab, "toast")
	var line := String(tab.info().line)
	assert_string_contains(line, "wounded")
	assert_false(line.contains("\n"), "one line")
	_press(tab, &"item_move")
	assert_true(tab.busy(), "the reset still asks")
	_press(tab, &"menu_down")
	_press(tab, &"menu_confirm")
	assert_false(tab.busy())
	assert_eq(run.attribute(0, Attributes.Kind.VITALITY), run.earned_points(0), "the reset is refused too")
	assert_eq(run.hp[0], 1, "never below 1 HP")


func test_changing_hero() -> void:
	var run := _run()
	var tab := _tab(run)
	assert_eq(tab.hero, 0)
	assert_true(_press(tab, &"party_skills"), "RT: the next hero")
	assert_eq(tab.hero, 1)
	assert_true(_press(tab, &"party_attributes"), "LT: back")
	assert_eq(tab.hero, 0)
	_press(tab, &"party_attributes")
	assert_eq(tab.hero, run.party_size() - 1, "round the party")
	tab.set_hero(0)
	tab.choose_row(Attributes.Kind.AGILITY)
	tab.change(1)
	tab.set_hero(2)
	assert_eq(Attributes.total(run.attributes[2]), 0, "a point goes to the hero shown")
	assert_eq(run.attribute(0, Attributes.Kind.AGILITY), 1)
	tab.set_hero(99)
	assert_eq(tab.hero, run.party_size() - 1, "clamped")


func test_a_click_on_a_face_picks_that_hero() -> void:
	var run := _run()
	var tab := _tab(run)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = _centre_of(tab._faces[2].box as Control)
	assert_true(tab.handle_input(click))
	assert_eq(tab.hero, 2)


func test_the_mouse_picks_a_row_and_a_click_adds() -> void:
	var run := _run()
	var tab := _tab(run)
	var move := InputEventMouseMotion.new()
	move.position = _centre_of(tab._rows[Attributes.Kind.DEFENSE].panel as Control)
	tab.handle_input(move)
	assert_eq(tab.row(), Attributes.Kind.DEFENSE, "pointing picks the row")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = move.position
	assert_true(tab.handle_input(click))
	assert_eq(run.attribute(0, Attributes.Kind.DEFENSE), 1, "a click adds a point")


func test_the_badge_sums_free_points() -> void:
	var run := _run()
	var tab := _tab(run)
	var sum := 0
	for slot: int in run.party_size():
		sum += run.free_points(slot)
	assert_eq(tab.badge(), sum)
	assert_gt(tab.badge(), 0)
	tab.change(1)
	assert_eq(tab.badge(), sum - 1)


func test_info_has_a_title_for_every_stop() -> void:
	var run := _run()
	var tab := _tab(run)
	for r: int in HeroTab.STOPS:
		tab.choose_row(r)
		var info := tab.info()
		assert_false(String(info.get("title", "")).is_empty(), "stop %d has a title" % r)
		assert_true(UiGlyph.KINDS.has(info.get("icon")), "stop %d has a glyph" % r)
		assert_true(info.get("color") is Color)
		assert_gt((info.get("chips", []) as Array).size(), 0, "stop %d has chips" % r)
		for chip: Array in info.chips:
			assert_eq(chip.size(), 3, "[glyph, text, colour]")
		assert_false(String(info.get("line", "")).contains("\n"), "one line")
	tab.choose_row(Attributes.Kind.VITALITY)
	assert_eq(String(tab.info().chips[0][1]), str(run.max_hp(0)), "the stat as the old page showed it")
	tab.choose_row(Attributes.Kind.DEFENSE)
	assert_eq(String(tab.info().chips[0][1]), "%d%%" % run.defense_percent(0))
	assert_eq(String(tab.info().chips[1][1]), Attributes.per_point_text(Attributes.Kind.DEFENSE, run.tuning))


func test_hints_stay_at_four() -> void:
	var run := _run()
	var tab := _tab(run)
	for r: int in HeroTab.STOPS:
		tab.choose_row(r)
		var hints := tab.hints()
		assert_lte(hints.size(), 4, "stop %d" % r)
		for entry: Array in hints:
			var action := StringName(entry[0])
			assert_true(InputMap.has_action(action) or HudStyle.NAV_TOKENS.has(action), "%s is a button" % action)


func test_the_echo_box_asks_for_the_echoes_page() -> void:
	var run := _run()
	var tab := _tab(run)
	tab.set_hero(1)
	_press(tab, &"menu_up")
	assert_eq(tab.row(), HeroTab.ECHO_ROW, "up from the first row wraps to the Echo box")
	watch_signals(tab)
	assert_true(_press(tab, &"menu_confirm"))
	assert_signal_emitted_with_parameters(tab, "echoes_requested", [1])
	assert_false(_press(tab, &"menu_right"), "left and right do nothing there")
	assert_eq(Attributes.total(run.attributes[1]), 0)


func test_an_online_client_asks_the_host() -> void:
	var run := _run()
	var tab := _tab(run, true)
	tab.choose_row(Attributes.Kind.MIGHT)
	watch_signals(tab)
	assert_true(tab.change(1))
	assert_signal_emitted(tab, "op_requested")
	assert_eq(run.attribute(0, Attributes.Kind.MIGHT), 0, "the client does not change its copy")
	var op: Dictionary = get_signal_parameters(tab, "op_requested")[0]
	assert_eq(String(op.op), "attributes")
	assert_eq(int(op.slot), 0)
	assert_eq(Attributes.total(op.values), 1)
	assert_eq(int(op.values[Attributes.Kind.MIGHT]), 1)
	assert_true(run.apply_op(op), "the host takes it as it took the old page's")
	tab.refresh()
	assert_eq((tab._rows[Attributes.Kind.MIGHT].points as Label).text, "1", "the host's answer is redrawn")


func test_refresh_redraws_from_the_run() -> void:
	var run := _run()
	var tab := _tab(run)
	run.set_attributes(0, [0, 0, 2, 0, 0])
	tab.refresh()
	assert_eq((tab._rows[Attributes.Kind.AGILITY].points as Label).text, "2")
	assert_eq(tab._stat_values[Attributes.Kind.AGILITY].text, str(run.speed(0)))
	assert_eq((tab._faces[0].badge as Control).visible, run.free_points(0) > 0, "the badge shows while points wait")
	assert_false((tab._faces[1].badge as Control).visible, "no badge without points")
