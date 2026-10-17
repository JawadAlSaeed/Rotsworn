extends GutTest
## The menus around Save & Quit (DESIGN 8.14): the main menu has a Continue row only when a run is
## saved, and picking it says so; the pause menu's Save & Quit row asks for a save and quit.

var _picked: Array[StringName] = []
var _save_quit: int = 0
var _left: int = 0


func _list_in(node: Node) -> ListMenu:
	if node is ListMenu:
		return node as ListMenu
	for child: Node in node.get_children():
		var found := _list_in(child)
		if found != null:
			return found
	return null


func _press(node: Node, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	node._unhandled_input(event)


func _main_menu(can_continue: bool, start: StringName = MainMenu.NEW_RUN, practice: bool = false) -> MainMenu:
	var menu := MainMenu.new()
	add_child_autofree(menu)
	menu.setup(BrandingData.new(), start, "", can_continue, practice)
	menu.chosen.connect(func(item: StringName) -> void: _picked.append(item))
	return menu


func before_each() -> void:
	_picked.clear()
	_save_quit = 0
	_left = 0


func test_main_menu_without_a_save_has_no_continue() -> void:
	var menu := _main_menu(false)
	var list := _list_in(menu)
	assert_eq(list.items.size(), MainMenu.ITEMS.size())
	assert_eq(String(list.items[0].text), "New Run")
	_press(menu, &"menu_confirm")
	assert_eq(_picked, [MainMenu.NEW_RUN] as Array[StringName])


func test_main_menu_with_a_save_starts_on_continue() -> void:
	var menu := _main_menu(true, MainMenu.CONTINUE)
	var list := _list_in(menu)
	assert_eq(list.items.size(), MainMenu.ITEMS.size() + 1)
	assert_eq(String(list.items[0].text), "Continue")
	assert_eq(list.index, 0, "the cursor rests on Continue")
	_press(menu, &"menu_confirm")
	assert_eq(_picked, [MainMenu.CONTINUE] as Array[StringName])


func test_main_menu_rows_still_map_to_their_choices_after_continue() -> void:
	var menu := _main_menu(true, MainMenu.SETTINGS)
	assert_eq(_list_in(menu).index, 4, "Settings is the fifth row with Continue above New Run, Online, Extras")
	_press(menu, &"menu_confirm")
	assert_eq(_picked, [MainMenu.SETTINGS] as Array[StringName])


func test_extras_opens_in_place_and_back_returns() -> void:
	var menu := _main_menu(false, MainMenu.EXTRAS)
	var list := _list_in(menu)
	_press(menu, &"menu_confirm")
	assert_eq(_picked.size(), 0, "Extras opens a list, it is not a choice")
	assert_eq(list.items.map(func(row: Dictionary) -> String: return String(row.text)),
			["Tutorial", "Journal", "Credits", "Back"], "players see no Practice")
	_press(menu, &"menu_confirm")
	assert_eq(_picked, [MainMenu.TUTORIAL] as Array[StringName])
	_press(menu, &"menu_cancel")
	assert_eq(String(list.items[list.index].text), "Extras", "cancel goes back to the Extras row")


func test_practice_shows_in_extras_only_for_test_builds() -> void:
	var menu := _main_menu(false, MainMenu.PRACTICE, true)
	var list := _list_in(menu)
	assert_eq(String(list.items[list.index].text), "Practice", "coming back from Practice reopens Extras on it")
	assert_eq(list.items.size(), 5, "Tutorial, Practice, Journal, Credits, Back")
	_press(menu, &"menu_confirm")
	assert_eq(_picked, [MainMenu.PRACTICE] as Array[StringName])


func _pause_menu(save_text: String) -> PauseMenu:
	var pause := PauseMenu.new()
	add_child_autofree(pause)
	pause.setup("Abandon run", "gone", "", "", save_text, "kept")
	pause.save_quit_requested.connect(func() -> void: _save_quit += 1)
	pause.leave_requested.connect(func() -> void: _left += 1)
	return pause


func test_pause_menu_save_and_quit_row() -> void:
	var pause := _pause_menu("Save & Quit")
	var list := _list_in(pause)
	var texts: Array[String] = []
	for item: Dictionary in list.items:
		texts.append(String(item.text))
	assert_eq(texts, ["Continue", "Settings", "Save & Quit", "Abandon run"] as Array[String])
	list.index = 2
	_press(pause, &"menu_confirm")
	assert_eq(_save_quit, 1)
	assert_eq(_left, 0)
	list.index = 3
	_press(pause, &"menu_confirm")
	assert_eq(_left, 1, "Abandon run still leaves")


func test_pause_menu_without_save_has_no_such_row() -> void:
	var pause := _pause_menu("")
	assert_eq(_list_in(pause).items.size(), 3)
