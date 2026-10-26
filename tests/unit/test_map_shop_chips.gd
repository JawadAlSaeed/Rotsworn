extends GutTest
## Cards #294 and #295 (phase 22's UI rule, DESIGN.md 7.13): the run map's legend is small and dim,
## every row a picture with its word, the picked stop's kind lit; the shop's line under the shelves
## shows an item as its picture, its name and a few icon chips worked out from its fields (the same
## chips as the fight's Items list), never its sentence. Uses the shipped run; never touches the
## player's files.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const MAP_VISUALS_PATH := "res://data/presentation/map_visuals.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const SCREEN := Vector2(1920.0, 1080.0)
## A chip says one to three words.
const MAX_CHIP_WORDS: int = 3

var _data: RunData
var _tuning: Tuning
var _look: MapVisuals
var _coin: String = ""


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning
	_look = load(MAP_VISUALS_PATH) as MapVisuals
	_coin = (load(VISUALS_PATH) as CombatVisuals).gold_icon_path


func after_each() -> void:
	HudStyle.set_text_size_index(0)


func _run(seed_value: int = 7) -> RunState:
	return RunState.begin(_data, _tuning.duplicate(true) as Tuning, seed_value)


## Every Label's text under `node`.
func _texts(node: Node) -> Array[String]:
	var found: Array[String] = []
	if node is Label:
		found.append((node as Label).text)
	for child: Node in node.get_children():
		found.append_array(_texts(child))
	return found


func _labels(node: Node) -> Array[Label]:
	var found: Array[Label] = []
	for label: Node in node.find_children("*", "Label", true, false):
		found.append(label as Label)
	return found


func _pictures(node: Node) -> int:
	return node.find_children("*", "TextureRect", true, false).size() + node.find_children("*", "UiGlyph", true, false).size()


func _icon_exists(icon: Variant) -> bool:
	if icon is StringName:
		return UiGlyph.KINDS.has(icon)
	var path := String(icon)
	return not path.is_empty() and FileAccess.file_exists(path)


func _map(run: RunState) -> MapScreen:
	var map := MapScreen.new()
	add_child_autofree(map)
	map.setup(run, _look, false)
	return map


func _chip_texts(chips: Array) -> Array[String]:
	var texts: Array[String] = []
	for chip: Array in chips:
		texts.append(String(chip[1]))
	return texts


func _item(effect: ItemData.Effect, amount: int, in_fight: bool = false, cleanse: int = 0) -> ItemData:
	var item := ItemData.new()
	item.effect = effect
	item.amount_percent = amount
	item.use_in_fight = in_fight
	item.cleanse_count = cleanse
	return item


# --- the map's legend (card #294) --------------------------------------------------------------------

func test_every_legend_row_is_a_picture_with_its_word() -> void:
	var run := _run()
	var map := _map(run)
	var entries := MapScreen.legend_entries(run, _look)
	assert_eq(map._legend_rows.size(), entries.size(), "a row for every kind of stop")
	for type: int in [RunMap.StopType.FIGHT, RunMap.StopType.REST, RunMap.StopType.SHOP,
			RunMap.StopType.FINAL, RunMap.StopType.ELITE, RunMap.StopType.EVENT, RunMap.StopType.TREASURE]:
		assert_true(map._legend_rows.has(type), "%s has a legend row" % RunMap.TYPE_NAMES[type])
	# The guards wait at Elite stops (DESIGN.md 8.22): no Guard line.
	assert_false(map._legend_rows.has(RunMap.StopType.GUARD), "no Guard row in the legend")
	for entry: Array in entries:
		var row: Control = map._legend_rows[int(entry[0])]
		assert_eq(row.find_children("*", "TextureRect", true, false).size(), 1, "%s: its picture" % entry[2])
		assert_eq(_texts(row), [String(entry[2])] as Array[String], "%s: with its word, never a bare picture" % entry[2])
		assert_true(_icon_exists(entry[1]), "%s: the picture %s is drawn" % [entry[2], entry[1]])


func test_the_legend_is_small_and_dim_and_lights_the_picked_kind() -> void:
	assert_lt(_look.legend_size, _look.label_size, "the legend's words are smaller than the stops' names")
	assert_lt(_look.legend_alpha, _look.legend_lit_alpha, "dim rows, a lit row")
	assert_lte(_look.legend_alpha, 0.6, "the legend stays quiet")
	var run := _run()
	var map := _map(run)
	for entry: Array in MapScreen.legend_entries(run, _look):
		var row: Control = map._legend_rows[int(entry[0])]
		var picture := row.find_children("*", "TextureRect", true, false)[0] as TextureRect
		assert_eq(picture.custom_minimum_size, picture.texture.get_size() * float(_look.legend_icon_scale),
				"%s: the picture grows by a whole number, and stays small" % entry[2])
		assert_lte(picture.custom_minimum_size.y, 32.0 * float(_look.legend_icon_scale), "%s is small" % entry[2])
	var choices := map.choices()
	for i: int in choices.size():
		map._sel = i
		map._update_detail()
		var picked := int(run.map.stop(choices[i]).type)
		for type: int in map._legend_rows:
			var alpha := (map._legend_rows[type] as Control).modulate.a
			if type == picked:
				assert_almost_eq(alpha, _look.legend_lit_alpha, 0.001, "the picked kind's row is lit")
			else:
				assert_almost_eq(alpha, _look.legend_alpha, 0.001, "the other rows are dim")
	# The detail rows swapped out above are freed at the frame's end.
	await get_tree().process_frame


func test_the_legend_fits_left_of_the_paper_at_the_largest_text_size() -> void:
	HudStyle.set_text_size_index(HudStyle.fonts().text_size_percents.size() - 1)
	var run := _run()
	var map := _map(run)
	await get_tree().process_frame
	for label: Label in _labels(map._legend_box):
		assert_eq(label.label_settings.font_size, HudStyle.scaled(_look.legend_size), "the player's text size applies")
	var size := map._legend_box.get_combined_minimum_size()
	var paper := AssetLoader.texture(_look.paper_path, Vector2i(440, 520)).get_size()
	var paper_left := (SCREEN.x - paper.x * float(_look.pixel_scale)) * 0.5
	assert_lt(float(_look.legend_left) + size.x, paper_left, "the legend (%d px wide) stays off the map" % int(size.x))
	assert_lt(size.y, SCREEN.y * 0.5, "a compact column (it is %d px tall)" % int(size.y))


# --- the shop's item chips (card #295) ----------------------------------------------------------------

func test_every_item_shows_a_few_icon_chips_not_its_sentence() -> void:
	var all: Array[ItemData] = []
	all.append_array(_data.shop_items)
	all.append_array(_data.found_items)
	assert_gt(all.size(), 0)
	for item: ItemData in all:
		if item == null:
			continue
		var chips := ShopScreen.item_chips(item, _look, _coin)
		assert_between(chips.size(), 1, _look.item_chips_max, "%s: one to %d chips" % [item.id, _look.item_chips_max])
		var words := 0
		for chip: Array in chips:
			var text := String(chip[1])
			var count := text.split(" ", false).size()
			words += count
			assert_true(_icon_exists(chip[0]), "%s: '%s' has its icon (%s)" % [item.id, text, chip[0]])
			assert_between(count, 1, MAX_CHIP_WORDS, "%s: '%s' is a word or a few" % [item.id, text])
			assert_false(text.contains("."), "%s: '%s' is not a sentence" % [item.id, text])
			assert_true(chip[2] is Color, "%s: '%s' has its colour" % [item.id, text])
		assert_lte(words, _look.item_words_max, "%s: %d words in all" % [item.id, words])


func test_the_chips_say_what_each_kind_of_item_does() -> void:
	var salve := _item(ItemData.Effect.HEAL_ONE, 50, true, 1)
	assert_eq(_chip_texts(ShopScreen.item_chips(salve, _look, _coin)), ["1 AP", "One ally", "Heal 50%", "Cleanse 1"]
			as Array[String], "a heal: its AP, who, how much and the mark it lifts (4 chips fit)")
	var bomb := _item(ItemData.Effect.DAMAGE_ALL, 120, true)
	var chips := ShopScreen.item_chips(bomb, _look, _coin)
	assert_eq(_chip_texts(chips), ["1 AP", "All foes", "120% dmg"] as Array[String])
	assert_eq([chips[0][0], chips[1][0], chips[2][0]], [_look.ap_icon_path, &"skull", &"sword"],
			"the AP picture, then the fight's foes and damage glyphs")
	assert_eq(_chip_texts(ShopScreen.item_chips(_item(ItemData.Effect.REVIVE_ONE, 40, true), _look, _coin)),
			["1 AP", "Downed ally", "Revive 40%"] as Array[String])
	assert_eq(_chip_texts(ShopScreen.item_chips(_item(ItemData.Effect.CLEANSE_ONE, 0, true, Status.CLEANSE_ALL), _look,
			_coin)), ["1 AP", "One ally", "Cleanse all"] as Array[String])
	assert_eq(_chip_texts(ShopScreen.item_chips(_item(ItemData.Effect.CLEANSE_ALL, 10, true, Status.CLEANSE_ALL), _look,
			_coin)), ["1 AP", "Party", "Cleanse all", "Heal 10%"] as Array[String])
	var feast := _item(ItemData.Effect.HEAL_ALL, 30, true)
	feast.ap_cost = 2
	assert_eq(_chip_texts(ShopScreen.item_chips(feast, _look, _coin)), ["2 AP", "Party", "Heal 30%"] as Array[String],
			"a fight item's own AP cost")
	assert_eq(_chip_texts(ShopScreen.item_chips(_item(ItemData.Effect.HEAL_ONE, 25), _look, _coin)),
			["One ally", "Heal 25%"] as Array[String], "a heal used only on the map has no AP chip")
	chips = ShopScreen.item_chips(_item(ItemData.Effect.HEAL_ONE, 25), _look, _coin)
	assert_eq([chips[0][0], chips[1][0]], [&"person", &"heart"], "the fight's person and heart glyphs")
	assert_eq(chips[1][2], HudStyle.HEAL)
	var curse := ItemData.new()
	curse.kind = ItemData.Kind.CURSE
	curse.rotten = true
	curse.rot_percent = 3
	assert_eq(_chip_texts(ShopScreen.item_chips(curse, _look, _coin)), ["Curse", "-3% a turn"] as Array[String])
	var idol := ItemData.new()
	idol.kind = ItemData.Kind.TREASURE
	chips = ShopScreen.item_chips(idol, _look, _coin)
	assert_eq(_chip_texts(chips), ["To gold"] as Array[String])
	assert_eq(String(chips[0][0]), _coin, "treasure: the gold coin")
	# The Tonic and the Bigger Pack went with card #332: their retired effects have no chips of their own.
	for retired: ItemData.Effect in [ItemData.Effect.MAX_HP_ONE, ItemData.Effect.ADD_ROW]:
		for text: String in _chip_texts(ShopScreen.item_chips(_item(retired, 15), _look, _coin)):
			assert_false(text.contains("max HP") or text.contains("pocket"), "no chip for a retired effect: %s" % text)


func test_the_shop_and_the_fight_describe_an_item_the_same_way() -> void:
	var all: Array[ItemData] = []
	all.append_array(_data.shop_items)
	all.append_array(_data.found_items)
	var checked := 0
	for item: ItemData in all:
		if item == null or not item.usable_in_fight():
			continue
		checked += 1
		var fight := ActionMenu.item_chips(item, item.amount_percent, _look.ap_icon_path)
		var shop := ShopScreen.item_chips(item, _look, _coin)
		assert_gt(shop.size(), 0, "%s: chips in the shop" % item.id)
		for i: int in shop.size():
			var chip: Array = shop[i]
			assert_eq(chip[0], fight[i].icon, "%s chip %d: the fight's picture" % [item.id, i])
			assert_eq(String(chip[1]), String(fight[i].text), "%s chip %d: the fight's words, in its order" % [item.id, i])
			assert_eq(chip[2], fight[i].color, "%s chip %d: the fight's colour" % [item.id, i])
	assert_gt(checked, 0, "the run has fight items")


func test_the_line_stays_within_the_data_limits() -> void:
	var look := _look.duplicate() as MapVisuals
	var bomb := _item(ItemData.Effect.DAMAGE_ALL, 120, true)
	look.item_chips_max = 1
	assert_eq(_chip_texts(ShopScreen.item_chips(bomb, look, _coin)), ["1 AP"] as Array[String], "chips_max")
	look.item_chips_max = 3
	look.item_words_max = 4
	assert_eq(_chip_texts(ShopScreen.item_chips(bomb, look, _coin)), ["1 AP", "All foes"] as Array[String],
			"a chip that would go over the words is left out")
	var curse := ItemData.new()
	curse.kind = ItemData.Kind.CURSE
	curse.rot_percent = 2
	look.item_words_max = 1
	assert_eq(_chip_texts(ShopScreen.item_chips(curse, look, _coin)), ["Curse"] as Array[String], "words_max")


func _shop_run() -> RunState:
	var run := _run()
	run.go(run.choices()[0])
	run.gold = 999
	return run


func test_the_shop_shows_an_item_as_its_picture_name_and_chips() -> void:
	var run := _shop_run()
	var shop := ShopScreen.new()
	add_child_autofree(shop)
	shop.setup(run, run.shop_gear(run.at))
	assert_gt(shop.items().size(), 0, "the shop sells items")
	for i: int in shop.items().size():
		var item := shop.items()[i]
		var detail := shop.detail(i)
		assert_eq(String(detail.line), "", "%s: no sentence" % item.id)
		assert_eq(String(detail.title), item.display_name)
		assert_true(detail.icon is Texture2D, "%s: its picture" % item.id)
		assert_eq(detail.chips, ShopScreen.item_chips(item, shop._look, shop._coin), "%s: its chips" % item.id)
		shop._sel = i
		shop._show_selection()
		var row := shop._detail
		var shown := row.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
		assert_eq(shown.size(), 1 + (detail.chips as Array).size(), "%s: the item, then its chips" % item.id)
		assert_eq(_texts(shown[0]), [item.display_name] as Array[String], "%s: the head is its name" % item.id)
		assert_eq(_pictures(shown[0]), 1, "%s: with its picture" % item.id)
		for k: int in range(1, shown.size()):
			assert_eq(_pictures(shown[k]), 1, "%s chip %d: a picture" % [item.id, k])
			assert_eq(_texts(shown[k]).size(), 1, "%s chip %d: with its word" % [item.id, k])
		for text: String in _texts(row):
			assert_ne(text, item.description, "%s: its sentence is gone" % item.id)
			assert_lte(text.split(" ", false).size(), MAX_CHIP_WORDS, "'%s' is a few words" % text)
	await get_tree().process_frame


func test_the_shop_footer_names_the_directions_the_shop_moves_with() -> void:
	# The cursor reads the menu directions. The move actions only mark P1's pad since phase 26
	# (DESIGN.md 8.22 G8), so a chip naming them would follow a rebinding that does nothing here.
	var run := _shop_run()
	var shop := ShopScreen.new()
	add_child_autofree(shop)
	shop.setup(run, run.shop_gear(run.at))
	var bars := shop.find_children("*", "HintBar", true, false)
	assert_eq(bars.size(), 1, "the shop has one footer")
	var token: StringName = ((bars[0] as HintBar)._entries[0] as Array)[0]
	assert_true(HudStyle.NAV_TOKENS.has(token), "its first chip is the directions")
	var actions: Array = HudStyle.NAV_TOKENS.get(token, [])
	assert_eq(actions.size(), 4, "all four of them")
	for action: StringName in actions:
		assert_true(String(action).begins_with("menu_"), "%s is a menu direction" % action)
	assert_gt(shop.count(), 1, "something to move to")
	shop._sel = 0
	var press := InputEventAction.new()
	press.action = &"menu_right"
	press.pressed = true
	shop._unhandled_input(press)
	assert_eq(shop._sel, 1, "and a menu direction moves the cursor")
	await get_tree().process_frame


func test_a_relic_in_the_shop_keeps_its_chips() -> void:
	var run := _shop_run()
	var shop := ShopScreen.new()
	add_child_autofree(shop)
	shop.setup(run, run.shop_gear(run.at))
	var first := shop.items().size()
	assert_lt(first, shop.count(), "the shop sells Relics")
	var gear := run.shop_gear(run.at)[0]
	var detail := shop.detail(first)
	assert_eq(detail.icon, gear)
	assert_eq(detail.chips, ShopScreen.relic_chips(run, gear), "a Relic still shows its level, stat and effect chips")
