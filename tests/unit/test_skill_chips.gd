extends GutTest
## Card #292: in a fight the skills and items lists show the chosen row in a few words (its
## short_text) over labelled icon chips worked out from its data, instead of a sentence. The full
## description stays on the Y screen and in the Glossary; with no short_text the description shows,
## so the line is never blank.

const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const ABILITIES_DIR := "res://data/abilities"
const ITEMS_DIR := "res://data/items"
## The fight's screen (project.godot) and the most a list panel may take of its height.
const SCREEN := Vector2(1920.0, 1080.0)
const MOST_HEIGHT_SHARE: float = 0.75

var _visuals: CombatVisuals
## HudStyle's fonts and the theme's before this file loaded the game's (put back after it).
var _saved_fonts: Array = []


func before_all() -> void:
	_visuals = load(VISUALS_PATH) as CombatVisuals
	# Measure with the game's own fonts, as main.gd loads them: they are wider than Godot's.
	_saved_fonts = [HudStyle._title_font, HudStyle._body_font, HudStyle._select_font, HudStyle._number_font,
			HudStyle._punch_font, HudStyle._fonts, ThemeDB.get_default_theme().default_font, ThemeDB.fallback_font]
	HudStyle.load_fonts()


func after_all() -> void:
	HudStyle._title_font = _saved_fonts[0]
	HudStyle._body_font = _saved_fonts[1]
	HudStyle._select_font = _saved_fonts[2]
	HudStyle._number_font = _saved_fonts[3]
	HudStyle._punch_font = _saved_fonts[4]
	HudStyle._fonts = _saved_fonts[5]
	ThemeDB.get_default_theme().default_font = _saved_fonts[6]
	ThemeDB.fallback_font = _saved_fonts[7]


func after_each() -> void:
	HudStyle.set_text_size_index(0)


func _load_all(dir_path: String) -> Array[Resource]:
	var list: Array[Resource] = []
	var dir := DirAccess.open(dir_path)
	assert_not_null(dir, dir_path)
	if dir == null:
		return list
	for file: String in dir.get_files():
		var name := file.trim_suffix(".remap")
		if name.ends_with(".tres"):
			list.append(load(dir_path.path_join(name)))
	return list


func _abilities() -> Array[AbilityData]:
	var list: Array[AbilityData] = []
	for res: Resource in _load_all(ABILITIES_DIR):
		if res is AbilityData:
			list.append(res as AbilityData)
	return list


func _fight_items() -> Array[ItemData]:
	var list: Array[ItemData] = []
	for res: Resource in _load_all(ITEMS_DIR):
		if res is ItemData and (res as ItemData).usable_in_fight():
			list.append(res as ItemData)
	return list


func _words(text: String) -> int:
	return text.split(" ", false).size()


func _entry(ability: AbilityData, extra: Dictionary = {}) -> Dictionary:
	var entry := {"ability": ability, "usable": true, "reason": "", "targets": [3, 4], "pick_target": true}
	entry.merge(extra, true)
	return entry


func _basic() -> AbilityData:
	var a := AbilityData.new()
	a.id = "basic_attack"
	a.display_name = "Attack"
	a.ap_gain = 1
	return a


## A menu open on the skills list, its rows `abilities` (after a basic attack).
func _menu(entries: Array[Dictionary]) -> ActionMenu:
	var menu := ActionMenu.new()
	menu.visuals = _visuals
	add_child_autofree(menu)
	menu.actor_ap = 9
	menu.max_ap = 9
	var all: Array[Dictionary] = [_entry(_basic())]
	all.append_array(entries)
	menu.open(Color(0.3, 0.5, 0.9), all, {3: "Husk", 4: "Rat"})
	return menu


## The chip nodes under the list's short line.
func _chips(menu: ActionMenu) -> Array[Control]:
	var list: Array[Control] = []
	for line: Node in menu._chip_box.get_children():
		if line.is_queued_for_deletion():
			continue
		for chip: Node in line.get_children():
			list.append(chip as Control)
	return list


func _chip_texts(menu: ActionMenu) -> PackedStringArray:
	var texts := PackedStringArray()
	for chip: Control in _chips(menu):
		for label: Node in chip.find_children("*", "Label", true, false):
			texts.append((label as Label).text)
	return texts


func _data_texts(chips: Array[Dictionary]) -> PackedStringArray:
	var texts := PackedStringArray()
	for chip: Dictionary in chips:
		texts.append(String(chip.text))
	return texts


## True if a chip's icon is something MapScreen.icon_chip draws: a texture, a glyph, or the path of
## a picture that is really there (a missing one would show the placeholder checkerboard).
func _has_icon(chip: Dictionary) -> bool:
	var icon: Variant = chip.get("icon")
	if icon is Texture2D:
		return true
	if icon is StringName:
		return UiGlyph.KINDS.has(icon)
	return icon is String and AssetLoader.has_art(String(icon))


# --- the data -----------------------------------------------------------------------------------

func test_every_ability_has_a_short_line_of_three_to_six_words() -> void:
	var abilities := _abilities()
	assert_gt(abilities.size(), 30, "every skill file is read")
	for ability: AbilityData in abilities:
		var words := _words(ability.short_text)
		assert_between(words, 3, 6, "%s: \"%s\"" % [ability.id, ability.short_text])
		assert_false(ability.short_text.ends_with("."), "%s: a line, not a sentence" % ability.id)
		assert_false(ability.description.is_empty(), "%s keeps its full description (Y screen)" % ability.id)


func test_every_fight_item_has_a_short_line_of_three_to_six_words() -> void:
	var items := _fight_items()
	assert_gt(items.size(), 3, "the fight items are read")
	for item: ItemData in items:
		assert_between(_words(item.short_text), 3, 6, "%s: \"%s\"" % [item.id, item.short_text])


func test_every_ability_and_fight_item_chip_is_an_icon_with_a_short_word() -> void:
	for ability: AbilityData in _abilities():
		var chips := ActionMenu.ability_chips(ability, _visuals.ap_pip_path)
		assert_gt(chips.size(), 0, "%s has chips" % ability.id)
		for chip: Dictionary in chips:
			assert_true(_has_icon(chip), "%s: \"%s\" has a picture" % [ability.id, chip.text])
			assert_between(_words(String(chip.text)), 1, 3, "%s: \"%s\" is a word or three" % [ability.id, chip.text])
	for item: ItemData in _fight_items():
		var chips := ActionMenu.item_chips(item, item.amount_percent, _visuals.ap_pip_path)
		assert_gt(chips.size(), 1, "%s: its cost or reach and what it does" % item.id)
		for chip: Dictionary in chips:
			assert_true(_has_icon(chip), "%s: \"%s\" has a picture" % [item.id, chip.text])
			assert_between(_words(String(chip.text)), 1, 3, "%s: \"%s\"" % [item.id, chip.text])


func test_the_chips_come_from_the_skill_data() -> void:
	var cuts := load(ABILITIES_DIR.path_join("quick_cuts.tres")) as AbilityData
	var texts := _data_texts(ActionMenu.ability_chips(cuts, _visuals.ap_pip_path))
	assert_eq(texts, PackedStringArray(["1 AP", "One foe", "Hits 4", "40% dmg"]), "Quick Cuts")
	var mend := load(ABILITIES_DIR.path_join("mend.tres")) as AbilityData
	texts = _data_texts(ActionMenu.ability_chips(mend, _visuals.ap_pip_path))
	assert_eq(texts, PackedStringArray(["1 AP", "One ally", "Heal 30%", "Cleanse 1"]), "Mend")
	var storm := load(ABILITIES_DIR.path_join("fang_storm.tres")) as AbilityData
	assert_true(_data_texts(ActionMenu.ability_chips(storm, _visuals.ap_pip_path)).has("All foes"))
	var wall := load(ABILITIES_DIR.path_join("shield_wall.tres")) as AbilityData
	assert_true(_data_texts(ActionMenu.ability_chips(wall, _visuals.ap_pip_path)).has("Party"))
	var basic := load(ABILITIES_DIR.path_join("basic_attack.tres")) as AbilityData
	assert_true(_data_texts(ActionMenu.ability_chips(basic, _visuals.ap_pip_path)).has("+1 AP"), "a skill that gains AP")
	# The mark it leaves: its own icon and word, with its turns.
	var hamstring := load(ABILITIES_DIR.path_join("hamstring.tres")) as AbilityData
	var slowed: Dictionary = {}
	for chip: Dictionary in ActionMenu.ability_chips(hamstring, _visuals.ap_pip_path):
		if String(chip.text).begins_with(HudStyle.STATUS_NAMES[Status.SLOWED]):
			slowed = chip
	assert_eq(String(slowed.get("text", "")), "SLOWED 2")
	assert_eq(slowed.get("icon"), HudStyle.mark_icon(Status.SLOWED), "the mark's own icon")
	# Taunt and guard, on foes and on the user.
	var unbreakable := load(ABILITIES_DIR.path_join("unbreakable.tres")) as AbilityData
	texts = _data_texts(ActionMenu.ability_chips(unbreakable, _visuals.ap_pip_path))
	assert_true(texts.has("TAUNTED") and texts.has("GUARD"), "Unbreakable: %s" % ", ".join(texts))


func test_the_item_chips_come_from_the_item() -> void:
	var salve := load(ITEMS_DIR.path_join("salve.tres")) as ItemData
	assert_eq(_data_texts(ActionMenu.item_chips(salve, 60, _visuals.ap_pip_path)),
			PackedStringArray(["1 AP", "One ally", "Heal 60%", "Cleanse 1"]), "the amount at the item's level")
	var bomb := load(ITEMS_DIR.path_join("bomb.tres")) as ItemData
	assert_true(_data_texts(ActionMenu.item_chips(bomb, bomb.amount_percent, "")).has("All foes"))
	var feast := load(ITEMS_DIR.path_join("feast.tres")) as ItemData
	assert_true(_data_texts(ActionMenu.item_chips(feast, feast.amount_percent, "")).has("Party"))
	var salts := load(ITEMS_DIR.path_join("smelling_salts.tres")) as ItemData
	assert_true(_data_texts(ActionMenu.item_chips(salts, salts.amount_percent, "")).has("Revive 40%"))
	var water := load(ITEMS_DIR.path_join("holy_water.tres")) as ItemData
	var texts := _data_texts(ActionMenu.item_chips(water, water.amount_percent, ""))
	assert_true(texts.has("Cleanse all") and texts.has("Heal 10%"), ", ".join(texts))


# --- the menu -----------------------------------------------------------------------------------

func test_the_list_shows_the_short_line_and_icon_chips_not_the_sentence() -> void:
	var mend := load(ABILITIES_DIR.path_join("mend.tres")) as AbilityData
	var menu := _menu([_entry(mend)])
	menu._pick_option(ActionMenu.Option.SKILLS)
	assert_true(menu.is_listing())
	assert_eq(menu._description.text, mend.short_text, "the short line")
	assert_ne(menu._description.text, mend.description, "not the sentence")
	var chips := _chips(menu)
	assert_eq(chips.size(), 4)
	for chip: Control in chips:
		var pictures := chip.find_children("*", "TextureRect", true, false)
		pictures.append_array(chip.find_children("*", "UiGlyph", true, false))
		assert_eq(pictures.size(), 1, "%s: one picture" % chip.name)
		var labels := chip.find_children("*", "Label", true, false)
		assert_eq(labels.size(), 1, "%s: one word" % chip.name)
		if labels.size() == 1:
			assert_false((labels[0] as Label).text.is_empty(), "%s: never a bare icon" % chip.name)
	var texts := _chip_texts(menu)
	assert_true(texts.has("Heal 30%") and texts.has("One ally"), ", ".join(texts))
	await get_tree().process_frame


func test_moving_the_cursor_changes_the_chips() -> void:
	var mend := load(ABILITIES_DIR.path_join("mend.tres")) as AbilityData
	var cuts := load(ABILITIES_DIR.path_join("quick_cuts.tres")) as AbilityData
	var menu := _menu([_entry(mend), _entry(cuts)])
	menu._pick_option(ActionMenu.Option.SKILLS)
	menu._move_skill(1)
	assert_eq(menu._description.text, cuts.short_text)
	assert_true(_chip_texts(menu).has("Hits 4"), ", ".join(_chip_texts(menu)))
	assert_false(_chip_texts(menu).has("Heal 30%"), "the old row's chips are gone")
	await get_tree().process_frame


func test_with_no_short_line_the_description_shows() -> void:
	var odd := AbilityData.new()
	odd.id = "odd"
	odd.display_name = "Odd"
	odd.description = "A skill nobody gave a short line."
	odd.ap_cost = 2
	odd.press_times_ms.assign([800])
	var menu := _menu([_entry(odd)])
	menu._pick_option(ActionMenu.Option.SKILLS)
	assert_eq(menu._description.text, odd.description, "never blank")
	assert_true(_chip_texts(menu).has("2 AP"), "its chips still show")
	await get_tree().process_frame


func test_an_item_row_shows_the_items_line_and_chips() -> void:
	var salve := load(ITEMS_DIR.path_join("salve.tres")) as ItemData
	# The controller's stand-in for a fight item (CombatController._item_ability()).
	var stand_in := AbilityData.new()
	stand_in.id = "item:7"
	stand_in.display_name = salve.display_name
	stand_in.description = salve.description
	stand_in.ap_cost = salve.ap_cost
	stand_in.target = AbilityData.Target.ALLY
	var menu := _menu([_entry(stand_in, {"item": true, "item_data": salve, "amount": salve.amount_percent})])
	menu._pick_option(ActionMenu.Option.ITEMS)
	assert_true(menu.is_listing())
	assert_eq(menu._description.text, salve.short_text)
	var texts := _chip_texts(menu)
	assert_true(texts.has("Heal 50%") and texts.has("Cleanse 1"), ", ".join(texts))
	assert_false(texts.has("100% dmg"), "the stand-in's damage is not the item's")
	await get_tree().process_frame


func test_an_item_without_its_data_falls_back_to_the_stand_in() -> void:
	var stand_in := AbilityData.new()
	stand_in.id = "item:8"
	stand_in.display_name = "Feast"
	stand_in.description = "Heals everyone."
	stand_in.ap_cost = 1
	stand_in.target = AbilityData.Target.SELF
	var entry := _entry(stand_in, {"item": true})
	assert_eq(ActionMenu.short_line(entry), "Heals everyone.")
	var texts := _data_texts(ActionMenu.entry_chips(entry, ""))
	assert_eq(texts, PackedStringArray(["1 AP", "Party"]), "a party item, no made-up damage")


## The skills list (every skill that is a row) and the items list (every fight item) at text size
## `size_index`: the run button and the team ultimate are diamond buttons, so their chips are put
## under the list by hand. Every row's chips stay inside their lines, and the panel is as wide with
## them as without, so it never grows or moves while the cursor does.
func _check_the_lists_fit(size_index: int) -> void:
	HudStyle.set_text_size_index(size_index)
	var rows: Array[Dictionary] = []
	var buttons: Array[AbilityData] = []
	for ability: AbilityData in _abilities():
		if ability.escape or ability.team_ultimate:
			buttons.append(ability)
		else:
			rows.append(_entry(ability))
	var menu := _menu(rows)
	await get_tree().process_frame
	menu._pick_option(ActionMenu.Option.SKILLS)
	assert_true(menu.is_listing(), "the skills list is open")
	for row: int in rows.size():
		var ability := rows[row].ability as AbilityData
		assert_eq(menu._description.text, ability.short_text, "%s: its short line" % ability.id)
		_assert_fits(menu, ability.id)
		menu._move_skill(1)
	for ability: AbilityData in buttons:
		menu._description.text = ActionMenu.short_line(_entry(ability))
		menu._show_chips(ActionMenu.entry_chips(_entry(ability), _visuals.ap_pip_path))
		_assert_fits(menu, ability.id)
	var items: Array[Dictionary] = []
	for item: ItemData in _fight_items():
		# The controller's stand-in for a fight item (CombatController._item_ability()).
		var stand_in := AbilityData.new()
		stand_in.id = "item:%s" % item.id
		stand_in.display_name = item.display_name
		stand_in.description = item.description
		stand_in.ap_cost = item.ap_cost
		items.append(_entry(stand_in, {"item": true, "item_data": item, "amount": item.amount_percent}))
	var bag := _menu(items)
	await get_tree().process_frame
	bag._pick_option(ActionMenu.Option.ITEMS)
	assert_true(bag.is_listing(), "the items list is open")
	for row: int in items.size():
		var item := items[row].item_data as ItemData
		assert_eq(bag._description.text, item.short_text, "%s: its short line" % item.id)
		_assert_fits(bag, item.id)
		bag._move_skill(1)
	await get_tree().process_frame


## The list as it stands: the chips at the player's text size, each line of them at most
## DETAIL_WIDTH, and the panel no wider than without them (at normal text: LIST_WIDTH).
func _assert_fits(menu: ActionMenu, what: String) -> void:
	var chips := _chips(menu)
	assert_gt(chips.size(), 1, "%s: its chips" % what)
	for chip: Control in chips:
		for label: Node in chip.find_children("*", "Label", true, false):
			assert_eq((label as Label).label_settings.font_size, HudStyle.scaled(ActionMenu.DETAIL_CHIP_SIZE),
					"%s: the player's text size applies" % what)
	for line: Node in menu._chip_box.get_children():
		if line.is_queued_for_deletion():
			continue
		var width := (line as Control).get_combined_minimum_size().x
		assert_lte(width, ActionMenu.DETAIL_WIDTH, "%s: a chip line (%d px) wraps inside the panel" % [what, int(width)])
	# The short line and the chips wrap; they never make the panel wider than the rest of it does.
	var size := menu._list.get_combined_minimum_size()
	menu._chip_box.visible = false
	var without := menu._list.get_combined_minimum_size()
	menu._chip_box.visible = true
	assert_almost_eq(size.x, without.x, 0.5, "%s: the chips keep the panel's width (%d px, %d without)"
			% [what, int(size.x), int(without.x)])
	if HudStyle.text_scale_percent() == 100:
		assert_almost_eq(size.x, ActionMenu.LIST_WIDTH, 0.5, "%s: the panel keeps its own width (%d px)" % [what, int(size.x)])
	assert_lte(size.x, SCREEN.x * 0.35, "%s: a side panel, not a page (%d px wide)" % [what, int(size.x)])
	assert_lte(size.y, SCREEN.y * MOST_HEIGHT_SHARE, "%s: the panel (%d px tall) fits the screen" % [what, int(size.y)])


func test_every_list_row_fits_its_panel_at_normal_text_size() -> void:
	assert_eq(HudStyle.text_scale_percent(), 100, "normal text size")
	await _check_the_lists_fit(0)


func test_every_list_row_fits_its_panel_at_the_largest_text_size() -> void:
	var largest := HudStyle.fonts().text_size_percents.size() - 1
	HudStyle.set_text_size_index(largest)
	assert_gt(HudStyle.text_scale_percent(), 100, "a bigger text size is on")
	await _check_the_lists_fit(largest)
