extends GutTest
## Card #336: a switch inside a screen (a kind, a sort, a hero, a topic, a page) is LT / RT on a
## pad and 1 / 3 on the keyboard (ControlBindings.SWITCH_PREV / SWITCH_NEXT); LB / RB (Z / C) stay
## the main tabs. The Relics tab's kind and the Relic book's sort left X / R, the Glossary's topics
## took LT / RT too, and the fight's ultimate is still RT. Uses the shipped run and input map.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const RUN_PATH := "res://data/runs/rotten_road.tres"

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = Fx.without_relic_stats(load(RUN_PATH) as RunData)
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func _action(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _relic(id: String) -> GearData:
	for item: GearData in _data.gear:
		if item != null and item.id == id:
			return item
	fail_test("no Relic %s" % id)
	return null


func _book(ids: Array) -> RelicCollection:
	var c := RelicCollection.new()
	c.merge(ids)
	return c


func _relics_tab(run: RunState) -> RelicsTab:
	var screen := PartyScreen.new()
	add_child_autofree(screen)
	screen.setup(run, "", {})
	screen.open_relics(0)
	return screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab


func _key_of(action: StringName) -> int:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			return (event as InputEventKey).physical_keycode
	return KEY_NONE


func _axis_of(action: StringName) -> int:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			return (event as InputEventJoypadMotion).axis
	return -1


func test_the_switch_is_lt_rt_and_1_3_and_the_tabs_stay_lb_rb() -> void:
	assert_eq(_axis_of(ControlBindings.SWITCH_PREV), JOY_AXIS_TRIGGER_LEFT, "LT")
	assert_eq(_axis_of(ControlBindings.SWITCH_NEXT), JOY_AXIS_TRIGGER_RIGHT, "RT")
	assert_eq(_key_of(ControlBindings.SWITCH_PREV), KEY_1, "1, above Q")
	assert_eq(_key_of(ControlBindings.SWITCH_NEXT), KEY_3, "3, above E")
	assert_eq(_key_of(&"item_turn_left"), KEY_Z, "the main tabs stay Z / C")
	assert_eq(_key_of(&"item_turn_right"), KEY_C)
	assert_eq(_axis_of(&"fight_ultimate"), JOY_AXIS_TRIGGER_RIGHT, "the fight's ultimate is still RT")
	var model := ControlBindings.from_input_map()
	assert_eq(model.conflict_pairs(), [], "1 and 3 clash with nothing")


func test_the_relics_tab_kind_is_lt_rt_from_the_rows_and_the_grid() -> void:
	var run := RunState.begin(_data, Fx.run_tuning(_tuning), 7)
	run.give_relic(_relic("whetstone"), 0)
	var tab := _relics_tab(run)
	assert_eq(tab._zone, RelicsTab.Zone.HEROES)
	var start := tab.filter()
	assert_true(tab.handle_input(_action(ControlBindings.SWITCH_NEXT)), "RT on the hero rows")
	assert_ne(tab.filter(), start, "the kind moved on")
	assert_true(tab.handle_input(_action(ControlBindings.SWITCH_PREV)))
	assert_eq(tab.filter(), start, "LT goes back")
	tab.handle_input(_action(&"menu_right"))
	assert_eq(tab._zone, RelicsTab.Zone.GRID)
	tab.handle_input(_action(ControlBindings.SWITCH_PREV))
	assert_ne(tab.filter(), start, "LT in the grid too, wrapping round")
	var kind := tab.filter()
	tab.handle_input(_action(&"item_move"))
	assert_eq(tab.filter(), kind, "X / R no longer changes the kind")
	assert_has(tab.hints(), [ControlBindings.SWITCH_NEXT, "Kind"], "the hint shows the new buttons")
	assert_has(tab.hints(), [ControlBindings.SWITCH_PREV, ""])


func test_the_relic_book_sorts_on_lt_rt_not_x() -> void:
	var screen := RelicsScreen.new()
	add_child_autofree(screen)
	screen.setup(_book(["whetstone", "iron_charm"]), _data.gear)
	var start := screen.sort()
	screen._unhandled_input(_action(&"item_move"))
	assert_eq(screen.sort(), start, "X / R is not the sort any more")
	screen._unhandled_input(_action(ControlBindings.SWITCH_NEXT))
	assert_ne(screen.sort(), start, "RT sorts")
	screen._unhandled_input(_action(ControlBindings.SWITCH_PREV))
	assert_eq(screen.sort(), start, "LT sorts back")
	assert_eq(screen.hints().slice(1, 3), RelicsScreen.SORT_HINTS)


func test_the_starting_relics_sort_on_lt_rt_and_skip_on_x() -> void:
	var book := _book(["whetstone", "iron_charm"])
	var run := RunState.begin(_data, Fx.run_tuning(_tuning), 7, 0, book)
	var screen := StartRelicsScreen.new()
	add_child_autofree(screen)
	screen.setup_pick(run, book, [0, 1, 2] as Array[int])
	var start := screen.sort()
	screen._unhandled_input(_action(ControlBindings.SWITCH_NEXT))
	assert_ne(screen.sort(), start, "RT sorts")
	assert_eq(screen.chooser(), 0, "and skips nobody")
	screen._unhandled_input(_action(&"item_move"))
	assert_eq(screen.chooser(), 1, "X / R skips the hero choosing")
	assert_false(run.start_open(0))
	screen._unhandled_input(_action(&"menu_cancel"))
	assert_eq(screen.chooser(), 0, "Back takes the Skip back")


func test_the_glossary_topics_follow_lt_rt() -> void:
	var data := load(GlossaryScreen.GLOSSARY_PATH) as GlossaryData
	var screen := GlossaryScreen.new()
	add_child_autofree(screen)
	screen.setup(data)
	screen._unhandled_input(_action(ControlBindings.SWITCH_NEXT))
	assert_eq(screen.topic(), 1, "RT: the next topic")
	screen._unhandled_input(_action(ControlBindings.SWITCH_PREV))
	screen._unhandled_input(_action(ControlBindings.SWITCH_PREV))
	assert_eq(screen.topic(), data.topic_ids.size() - 1, "LT wraps round to the last")
	assert_has(GlossaryScreen.FOOTER_HINTS, [ControlBindings.SWITCH_NEXT, "Topic"])
