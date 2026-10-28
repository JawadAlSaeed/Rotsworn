extends GutTest
## The Y screen (card #270, DESIGN.md 8.18): its tabs, which tab opens first, the info strip,
## toasts, and that a tab in the middle of something keeps the screen on it.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const RUN_PATH := "res://data/runs/rotten_road.tres"

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func _run() -> RunState:
	return RunState.begin(_data, Fx.run_tuning(_tuning), 7)


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
	run.give_relic(relic, 1)
	var with_relic := _screen(run, "New", {"icon": relic})
	assert_eq(with_relic.current_tab(), PartyScreen.Tab.RELICS, "a Relic just given: the Relics tab")
	assert_eq(with_relic.tab_node(PartyScreen.Tab.RELICS).hero, 1, "on its hero")
	assert_false(with_relic.holding_new(), "a Relic is given before the screen opens, never held")
	assert_true(with_relic.select_tab(PartyScreen.Tab.BAG))
	var salve := run.items_by_id()["salve"] as ItemData
	var with_item := _screen(run, "", {"item": salve})
	assert_eq(with_item.current_tab(), PartyScreen.Tab.BAG)
	assert_true(with_item.holding_new())
	var shop := _screen(run, "", {}, true)
	assert_eq(shop.current_tab(), PartyScreen.Tab.BAG, "a shop opens on the Bag")


func test_a_waiting_relic_is_given_from_the_grid_for_good() -> void:
	var run := _run()
	var relic := _relic("whetstone")
	run.add_relic(relic)
	var screen := _screen(run)
	screen.open_relics(0, true)
	var tab := screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab
	assert_eq(tab._zone, RelicsTab.Zone.GRID, "Confirm on a hero opens the grid of waiting Relics")
	assert_eq(tab.badge(), 1, "one waits")
	assert_true(tab.put(relic))
	assert_eq(run.relics_of(0), [relic] as Array[GearData], "Alder has it")
	assert_eq(tab._zone, RelicsTab.Zone.HEROES, "back on the hero rows")
	assert_eq(tab.badge(), 0)
	tab.focus_hero(1, true)
	assert_eq(tab._zone, RelicsTab.Zone.HEROES, "nothing left to give: the grid stays shut")
	assert_eq(String(tab.info().title), "Nothing to give")
	assert_false(tab.put(relic), "given for good: it never moves to another hero")
	assert_eq(run.holder_of(relic), 0)


func test_with_nothing_waiting_the_relics_tab_offers_no_give() -> void:
	var run := _run()
	run.give_relic(_relic("whetstone"), 0)
	var screen := _screen(run)
	screen.open_relics(1)
	var tab := screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab
	tab.focus_hero(1)
	var words := tab.hints().map(func(hint: Array) -> String: return String(hint[1]))
	assert_false(words.has("Give"), "a new run has nothing waiting: no Give")
	assert_eq(tab.info().icon, &"gem", "a hero with no Relics: no plus inviting one")
	var press := InputEventAction.new()
	press.action = &"menu_right"
	press.pressed = true
	tab.handle_input(press)
	assert_eq(tab._zone, RelicsTab.Zone.GRID, "the grid still opens to look")
	words = tab.hints().map(func(hint: Array) -> String: return String(hint[1]))
	assert_false(words.has("Give"), "nor in the grid")
	assert_true(words.has("Kind"), "its filter still works")
	for node: Node in tab.find_children("*", "", true, false):
		if node is RelicIcon:
			assert_ne((node as RelicIcon).slot_state(), RelicIcon.SlotState.EMPTY, "no empty plus slot")


func test_the_strip_and_the_toast() -> void:
	var run := _run()
	var relic := _relic("whetstone")
	run.give_relic(relic, 0)
	var screen := _screen(run, "Hello")
	screen.open_relics(0)
	screen.select_tab(PartyScreen.Tab.RELICS)
	var tab := screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab
	tab.focus_hero(0)
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
	screen.open_relics(2)
	(screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab).focus_hero(2)
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


func test_right_past_a_heros_last_relic_goes_into_the_grid_for_them() -> void:
	var run := RunState.begin(_data, _tuning, 7)
	run.give_relic(_relic("coffin_lid"), 1)
	var relic := _relic("whetstone")
	run.add_relic(relic)
	var screen := _screen(run)
	screen.select_tab(PartyScreen.Tab.RELICS)
	var tab := screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab
	tab.focus_hero(1)
	tab.handle_input(_press(&"menu_right"))
	assert_eq(tab._zone, RelicsTab.Zone.GRID, "right past the last Relic goes into the grid")
	tab.handle_input(_press(&"menu_confirm"))
	assert_eq(run.relics_of(1), [_relic("coffin_lid"), relic] as Array[GearData],
			"the waiting Relic, listed first, goes to the hero just left; no slot limit")


func test_right_click_in_the_bag_steps_back_and_keeps_the_screen_open() -> void:
	var run := _run()
	run.add_relic(_relic("whetstone"))
	var screen := _screen(run)
	watch_signals(screen)
	screen.open_relics(0, true)
	var tab := screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab
	assert_eq(tab._zone, RelicsTab.Zone.GRID)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	screen._unhandled_input(click)
	assert_eq(tab._zone, RelicsTab.Zone.HEROES, "back to the hero rows")
	assert_signal_not_emitted(screen, "done")


func test_the_footer_shows_at_most_four_hints_on_every_tab() -> void:
	var run := _run()
	run.add_item(run.items_by_id()["salve"] as ItemData)
	var relic := _relic("whetstone")
	run.give_relic(relic, 0)
	run.add_relic(_relic("coffin_lid"))
	var screen := _screen(run)
	for tab: int in [PartyScreen.Tab.RELICS, PartyScreen.Tab.BAG, PartyScreen.Tab.HERO, PartyScreen.Tab.SKILLS]:
		screen.select_tab(tab)
		var entries := screen.hint_entries()
		assert_lte(PartyScreen.visible_hints(entries), 4, PartyScreen.TAB_NAMES[tab])
		assert_eq(String((entries.back() as Array)[1]), "Tabs", "%s ends with LB / RB Tabs" % PartyScreen.TAB_NAMES[tab])

