extends GutTest
## The glossary (card #207, DESIGN.md 7.12): the data file loads and is complete and true to the
## game's own icons and colours, the screen builds and moves, and the two ways in (Extras, the
## pause menu) lead to it. Nothing here touches the user's settings, saves or journal.

const MAX_TERM_CHARS: int = 26
const MAX_TEXT_CHARS: int = 260
## Terms the card names; each must be in the book.
const REQUIRED := [
	"hit_normal", "hit_ground", "hit_rend", "hit_sweep", "thrown", "feint", "press_perfect", "press_good",
	"press_miss", "parry", "dodge", "jump", "counter", "team_counter", "follow_up", "ap", "team_gauge",
	"team_ultimate", "status_exposed", "status_marked", "status_rotting", "status_blighted", "status_weakened",
	"ap_drain", "doom", "break", "stagger", "status_bleeding", "status_slowed", "elite", "guard", "champion",
	"oath", "seal", "shrine", "wanderer", "gear", "charm", "rot_touched", "backpack", "rotten_item",
	"camp_rest", "camp_train", "stop_zone", "stop_elite", "stop_event", "stop_treasure", "stop_rest", "stop_shop",
]

var _data: GlossaryData
var _visuals: CombatVisuals


func before_each() -> void:
	_data = load(GlossaryScreen.GLOSSARY_PATH) as GlossaryData
	_visuals = load("res://data/presentation/combat_visuals.tres") as CombatVisuals


func _press(screen: Node, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	screen._unhandled_input(event)


func test_the_file_loads_with_topics_and_terms() -> void:
	assert_not_null(_data, "glossary.tres loads as GlossaryData")
	assert_gt(_data.topic_ids.size(), 5, "several topics")
	assert_eq(_data.topic_ids.size(), _data.topic_names.size(), "every topic has a name")
	assert_gt(_data.entries.size(), 50, "a real book")


func test_every_entry_is_complete() -> void:
	var ids: Dictionary = {}
	for entry: GlossaryEntry in _data.entries:
		assert_false(entry.id.is_empty(), "an entry has an id")
		assert_false(ids.has(entry.id), "id %s is unique" % entry.id)
		ids[entry.id] = true
		assert_true(_data.topic_ids.has(entry.topic), "%s: topic %s exists" % [entry.id, entry.topic])
		assert_false(entry.term.strip_edges().is_empty(), "%s has a term" % entry.id)
		assert_lte(entry.term.length(), MAX_TERM_CHARS, "%s: the term fits the list" % entry.id)
		assert_false(entry.text.strip_edges().is_empty(), "%s has text" % entry.id)
		assert_lte(entry.text.length(), MAX_TEXT_CHARS, "%s: the text is short (2-3 lines)" % entry.id)
		assert_false("  " in entry.text, "%s: no double spaces in the text" % entry.id)


func test_every_topic_has_terms() -> void:
	for topic_id: String in _data.topic_ids:
		assert_gt(_data.topic_entries(topic_id).size(), 0, "topic %s has terms" % topic_id)
		assert_lte(_data.topic_entries(topic_id).size(), 12, "topic %s stays a short list" % topic_id)
	assert_eq(_data.topic_index("fight"), 0, "the book opens on the fight")
	assert_eq(_data.topic_index("nope"), -1)


func test_every_icon_exists() -> void:
	for entry: GlossaryEntry in _data.entries:
		if entry.icon_path.is_empty():
			continue
		assert_true(ResourceLoader.exists(entry.icon_path) or FileAccess.file_exists(entry.icon_path),
				"%s: icon %s exists" % [entry.id, entry.icon_path])


func test_the_cards_terms_are_all_there() -> void:
	for id: String in REQUIRED:
		assert_not_null(_data.find(id), "the glossary explains %s" % id)


## What the book shows for a hit kind, a defence readout or a status is what the game draws.
func test_colours_and_words_follow_the_game() -> void:
	assert_eq(_data.find("hit_normal").color, _visuals.normal_hit_color)
	assert_eq(_data.find("hit_ground").color, _visuals.ground_hit_color)
	assert_eq(_data.find("hit_rend").color, _visuals.rend_hit_color)
	assert_eq(_data.find("hit_sweep").color, _visuals.sweep_hit_color)
	assert_eq(_data.find("feint").color, _visuals.rhythm_feint_color)
	assert_eq(_data.find("parry").color, HudStyle.PARRY)
	assert_eq(_data.find("dodge").color, HudStyle.DODGE)
	assert_eq(_data.find("jump").color, HudStyle.JUMP)
	assert_eq(_data.find("press_perfect").color, HudStyle.GOLD)
	assert_eq(_data.find("doom").color, _visuals.doom_text_color)
	assert_eq(_data.find("stagger").color, _visuals.stagger_text_color)
	assert_eq(_data.find("rot_touched").color, GearData.ROT_TOUCHED_COLOR)
	assert_eq(_data.find("hit_normal").icon_path, _visuals.hit_icon_normal_path)
	assert_eq(_data.find("hit_ground").icon_path, _visuals.hit_icon_ground_path)
	assert_eq(_data.find("hit_rend").icon_path, _visuals.hit_icon_rend_path)
	assert_eq(_data.find("hit_sweep").icon_path, _visuals.hit_icon_sweep_path)
	for status: String in HudStyle.STATUS_NAMES:
		var entry := _data.find("status_" + status)
		if entry == null:
			entry = _data.find(status)
		if entry == null:
			continue
		assert_eq(entry.tag, String(HudStyle.STATUS_NAMES[status]), "%s: the word the HUD prints" % status)
		assert_eq(entry.color, HudStyle.STATUS_COLORS[status], "%s: the colour the HUD uses" % status)
	for status: String in Status.DEBUFFS:
		var entry := _data.find("status_" + status)
		if entry == null:
			entry = _data.find(status)
		assert_not_null(entry, "the hero mark %s is explained" % status)


func test_the_screen_builds_for_every_topic_and_term() -> void:
	var screen := GlossaryScreen.new()
	add_child_autofree(screen)
	screen.setup(_data)
	var seen := 0
	for t: int in _data.topic_ids.size():
		assert_eq(screen.topic(), t, "the strip is on topic %d" % t)
		var terms := _data.topic_entries(_data.topic_ids[t])
		for i: int in terms.size():
			assert_eq(screen.selected_entry().id, terms[i].id, "the cursor is on %s" % terms[i].id)
			assert_gt(screen._panel.get_child_count(), 1, "%s fills the plate" % terms[i].id)
			seen += 1
			_press(screen, &"menu_down")
		_press(screen, &"menu_right")
	assert_eq(seen, _data.entries.size(), "every term was shown")


func test_cancel_closes_and_left_right_wrap_round() -> void:
	var screen := GlossaryScreen.new()
	add_child_autofree(screen)
	screen.setup(_data)
	var closed: Array[bool] = []
	screen.closed.connect(func() -> void: closed.append(true))
	assert_eq(screen.topic(), 0)
	_press(screen, &"menu_left")
	assert_eq(screen.topic(), _data.topic_ids.size() - 1, "left from the first wraps to the last")
	_press(screen, &"menu_right")
	assert_eq(screen.topic(), 0, "and right wraps back")
	_press(screen, &"menu_down")
	assert_eq(screen.selected_entry().id, _data.topic_entries(_data.topic_ids[0])[1].id, "down picks the next term")
	_press(screen, &"menu_right")
	assert_eq(screen.selected_entry().id, _data.topic_entries(_data.topic_ids[1])[0].id, "a new topic starts at its first term")
	_press(screen, &"menu_cancel")
	assert_eq(closed.size(), 1, "Back closes")


func test_it_opens_on_a_named_topic() -> void:
	var screen := GlossaryScreen.new()
	add_child_autofree(screen)
	screen.setup(_data, "dooms")
	assert_eq(_data.topic_ids[screen.topic()], "dooms")
	var unknown := GlossaryScreen.new()
	add_child_autofree(unknown)
	unknown.setup(_data, "no_such_topic")
	assert_eq(unknown.topic(), 0, "an unknown topic opens the first")


func test_an_empty_glossary_still_builds() -> void:
	var screen := GlossaryScreen.new()
	add_child_autofree(screen)
	screen.setup(GlossaryData.new())
	assert_null(screen.selected_entry())
	_press(screen, &"menu_right")
	_press(screen, &"menu_down")
	assert_true(true, "no crash on an empty book")


## The fullest page of every topic fits the plate, and the whole screen fits above the footer.
func test_every_page_fits_the_screen() -> void:
	var screen := GlossaryScreen.new()
	add_child_autofree(screen)
	screen.setup(_data)
	var tallest := 0.0
	for t: int in _data.topic_ids.size():
		for i: int in screen._terms.size():
			screen._menu.index = i
			screen._refresh()
			tallest = maxf(tallest, screen._panel.get_combined_minimum_size().y)
			assert_lte(screen._panel.get_combined_minimum_size().x, GlossaryScreen.PANEL_WIDTH - 40.0,
					"%s fits the plate's width" % screen.selected_entry().id)
		_press(screen, &"menu_right")
	assert_lte(tallest, GlossaryScreen.PANEL_HEIGHT - 40.0, "the page fits the plate (it is %d)" % int(tallest))
	# Old rows of a list are only freed at the end of the frame, so measure a fresh screen opened on the
	# longest topic.
	var longest := 0
	for t: int in _data.topic_ids.size():
		if _data.topic_entries(_data.topic_ids[t]).size() > _data.topic_entries(_data.topic_ids[longest]).size():
			longest = t
	var fresh := GlossaryScreen.new()
	add_child_autofree(fresh)
	fresh.setup(_data, _data.topic_ids[longest])
	var column: Control = fresh._count.get_parent()
	assert_lte(column.get_combined_minimum_size().y, 1080.0 - ListMenu.FOOTER_STRIP_PX, "the screen fits")
	assert_lte(fresh._menu.get_parent().get_combined_minimum_size().x, 1920.0 - 60.0, "list and page fit the width")


func test_an_icon_is_scaled_by_whole_numbers() -> void:
	var plate := GlossaryScreen.picture(_data.find("hit_normal"))
	assert_not_null(plate)
	var icon := plate.get_child(0).get_child(0) as TextureRect
	assert_eq(icon.custom_minimum_size.x, icon.custom_minimum_size.y, "a square icon stays square")
	assert_eq(int(icon.custom_minimum_size.x) % 12, 0, "a 12 px icon grows by a whole number")
	plate.free()
	var swatch := GlossaryScreen.picture(_data.find("press_good"))
	assert_not_null(swatch, "a colour alone gets a swatch")
	swatch.free()
	assert_null(GlossaryScreen.picture(_data.find("turn_order")), "no picture, no plate")


func test_extras_leads_to_the_glossary() -> void:
	var extras := MainMenu.EXTRAS_ITEMS
	assert_eq(extras.find(MainMenu.GLOSSARY), extras.find(MainMenu.TUTORIAL) + 1, "the row sits right after the tutorial")
	assert_eq(String(MainMenu.LABELS[MainMenu.GLOSSARY]), "Glossary")
	var source := FileAccess.get_file_as_string("res://scenes/main.gd")
	assert_true("MainMenu.GLOSSARY:" in source and "_show_glossary.call_deferred()" in source, "Main opens the glossary for that row")
	assert_true("_pause.glossary_requested.connect(_on_pause_glossary)" in source, "Main opens it from the pause menu")


func test_the_pause_menu_has_a_glossary_row() -> void:
	var pause := PauseMenu.new()
	add_child_autofree(pause)
	pause.setup("Abandon run", "The run is lost.")
	var asked: Array[bool] = []
	pause.glossary_requested.connect(func() -> void: asked.append(true))
	_press(pause, &"menu_down")
	_press(pause, &"menu_down")
	_press(pause, &"menu_confirm")
	assert_eq(asked.size(), 1, "Continue, Settings, then Glossary")
