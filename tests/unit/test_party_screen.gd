extends GutTest
## The Y screen (card #270, DESIGN.md 8.18): its tabs, which tab opens first, the info strip,
## toasts, and that a tab in the middle of something keeps the screen on it.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const RUN_PATH := "res://data/runs/rotten_road.tres"

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = Fx.without_relic_stats(load(RUN_PATH) as RunData)
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func _run() -> RunState:
	return RunState.begin(_data, Fx.all_slots(_tuning), 7)


func _relic(id: String) -> GearData:
	for item: GearData in _data.gear:
		if item.id == id:
			return item
	fail_test("no Relic %s" % id)
	return null


func _screen(run: RunState, note: String = "", held: Dictionary = {}, shop: bool = false) -> PartyScreen:
	var screen := PartyScreen.new()
	screen.shop_mode = shop
	add_child_autofree(screen)
	screen.setup(run, note, held)
	return screen


func test_four_tabs_with_skills_when_a_hero_has_a_tree() -> void:
	var screen := _screen(_run())
	for tab: int in [PartyScreen.Tab.RELICS, PartyScreen.Tab.BAG, PartyScreen.Tab.HERO, PartyScreen.Tab.SKILLS]:
		assert_not_null(screen.tab_node(tab), PartyScreen.TAB_NAMES[tab])
		assert_true(screen.select_tab(tab))
		assert_eq(screen.current_tab(), tab)
		assert_true(screen.tab_node(tab).visible, "only the chosen tab shows")


func test_what_is_in_hand_picks_the_tab() -> void:
	var run := _run()
	var relic := _relic("whetstone")
	run.add_relic(relic)
	var with_relic := _screen(run, "New Relic: Whetstone", {"gear": relic})
	assert_eq(with_relic.current_tab(), PartyScreen.Tab.RELICS)
	assert_true(with_relic.holding_new())
	assert_false(with_relic.select_tab(PartyScreen.Tab.BAG), "no tab change with a Relic in hand")
	var salve := run.items_by_id()["salve"] as ItemData
	var with_item := _screen(run, "", {"item": salve})
	assert_eq(with_item.current_tab(), PartyScreen.Tab.BAG)
	assert_true(with_item.holding_new())
	var shop := _screen(run, "", {}, true)
	assert_eq(shop.current_tab(), PartyScreen.Tab.BAG, "a shop opens on the Bag")


func test_a_new_relic_goes_on_the_slot_it_is_put_on() -> void:
	var run := _run()
	var relic := _relic("whetstone")
	run.add_relic(relic)
	var screen := _screen(run, "", {"gear": relic})
	watch_signals(screen)
	screen.close_when_settled = true
	var tab := screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab
	tab._confirm_slot()
	assert_eq(run.gear[0][0], relic, "on the first free slot")
	assert_false(screen.holding_new())
	assert_signal_emitted(screen, "done", "it closes once settled")


func test_the_strip_and_the_toast() -> void:
	var run := _run()
	var relic := _relic("whetstone")
	run.add_relic(relic)
	run.wear(0, 0, relic)
	var screen := _screen(run, "Hello")
	screen.open_relics(0, 0)
	screen.select_tab(PartyScreen.Tab.RELICS)
	var tab := screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab
	tab.focus_slot(0, 0)
	var info := tab.info()
	assert_eq(String(info.title), relic.display_name, "the strip names the Relic under the cursor")
	assert_eq(info.icon, relic)
	assert_true(screen._toast.visible, "the note shows as a toast")
	screen.show_toast("Alder", relic)
	assert_true(screen._toast.visible)


func test_the_bag_tab_menu_keeps_the_screen_on_it() -> void:
	var run := _run()
	var salve := run.items_by_id()["salve"] as ItemData
	run.add_item(salve)
	var screen := _screen(run)
	screen.select_tab(PartyScreen.Tab.BAG)
	var bag := screen.tab_node(PartyScreen.Tab.BAG) as BagTab
	bag._grid.cursor = 0
	bag._confirm_grid()
	assert_true(bag.busy(), "the item menu is open")
	assert_false(screen.select_tab(PartyScreen.Tab.RELICS))
	assert_eq(String(bag.info().title), "Salve")


func test_open_attributes_and_skills_follow_the_hero() -> void:
	var screen := _screen(_run())
	screen.open_relics(2, 0)
	(screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab).focus_slot(2, 0)
	screen.open_attributes()
	assert_eq(screen.current_tab(), PartyScreen.Tab.HERO)
	assert_eq(screen.tab_node(PartyScreen.Tab.HERO).hero, 2)
	screen.open_skills()
	assert_eq(screen.current_tab(), PartyScreen.Tab.SKILLS)


func test_every_tab_says_something_on_the_strip_and_few_hints() -> void:
	var run := _run()
	run.add_item(run.items_by_id()["salve"] as ItemData)
	var screen := _screen(run)
	for tab: int in [PartyScreen.Tab.RELICS, PartyScreen.Tab.BAG, PartyScreen.Tab.HERO, PartyScreen.Tab.SKILLS]:
		screen.select_tab(tab)
		var node := screen.tab_node(tab)
		assert_false(String(node.info().get("title", "")).is_empty(), "%s fills the strip" % PartyScreen.TAB_NAMES[tab])
		assert_lte(node.hints().size(), 4, "%s: at most four hints" % PartyScreen.TAB_NAMES[tab])


func _press(action: StringName) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e


func test_right_into_the_bag_aims_at_an_open_slot() -> void:
	var run := _real_slots_run()
	var relic := _relic("whetstone")
	run.add_relic(relic)
	var screen := _screen(run)
	screen.select_tab(PartyScreen.Tab.RELICS)
	var tab := screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab
	tab.focus_slot(0, 0)
	for i: int in 3:
		tab.handle_input(_press(&"menu_right"))
	assert_eq(tab._zone, RelicsTab.Zone.BAG, "right past the last slot goes into the bag")
	tab.handle_input(_press(&"menu_confirm"))
	assert_eq(run.gear[0][0], relic, "the pick goes on the open slot, not the locked one walked over")


func test_right_click_in_the_bag_steps_back_and_keeps_the_screen_open() -> void:
	var run := _run()
	run.add_relic(_relic("whetstone"))
	var screen := _screen(run)
	watch_signals(screen)
	screen.open_relics(0, 0)
	var tab := screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab
	assert_eq(tab._zone, RelicsTab.Zone.BAG)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	screen._unhandled_input(click)
	assert_eq(tab._zone, RelicsTab.Zone.SLOTS, "back to the slot")
	assert_signal_not_emitted(screen, "done")


func test_the_footer_shows_at_most_four_hints_on_every_tab() -> void:
	var run := _run()
	run.add_item(run.items_by_id()["salve"] as ItemData)
	var relic := _relic("whetstone")
	run.add_relic(relic)
	run.wear(0, 0, relic)
	var screen := _screen(run)
	for tab: int in [PartyScreen.Tab.RELICS, PartyScreen.Tab.BAG, PartyScreen.Tab.HERO, PartyScreen.Tab.SKILLS]:
		screen.select_tab(tab)
		var entries := screen.hint_entries()
		assert_lte(PartyScreen.visible_hints(entries), 4, PartyScreen.TAB_NAMES[tab])
		assert_eq(String((entries.back() as Array)[1]), "Tabs", "%s ends with LB / RB Tabs" % PartyScreen.TAB_NAMES[tab])


## A run with the shipped slot rules (one slot open at the start).
func _real_slots_run() -> RunState:
	return RunState.begin(_data, _tuning, 7)
