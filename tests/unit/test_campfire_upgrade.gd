extends GutTest
## The campfire's Upgrade (DESIGN.md 8.11, 8.25, card #333): the third card, the Relic pick and its Back,
## co-op and the host's check, the bot's pick, Sharpen gone, and how a Relic+ shows everywhere.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const RUN_PATH := "res://data/runs/rotten_road.tres"
const MAIN_PATH := "res://scenes/main.gd"
const GEAR_DIR := "res://data/gear"

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func _run(seed_value: int = 7) -> RunState:
	return RunState.begin(_data, Fx.run_tuning(_tuning), seed_value)


func _relic(id: String) -> GearData:
	for item: GearData in _data.gear:
		if item.id == id:
			return item
	fail_test("the shipped run has the Relic %s" % id)
	return GearData.new()


func _rest(run: RunState, give_heroes: Callable = Callable()) -> RestScreen:
	var rest := RestScreen.new()
	rest.give_heroes = give_heroes
	add_child_autofree(rest)
	rest.setup(run)
	return rest


func _press_on(node: Node, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	node._unhandled_input(event)


func _texts(menu: ListMenu) -> Array:
	return menu.items.map(func(row: Dictionary) -> String: return String(row.get("text", "")))


## A run at the campfire before the boss.
func _at_watch_fire(run: RunState) -> void:
	for s: Dictionary in run.map.stops:
		if int(s.type) != RunMap.StopType.REST:
			continue
		run.at = int(s.id)
		if run.is_watch_fire():
			return
	fail_test("the map has a campfire before the boss")


# --- the cards ---------------------------------------------------------------------------------

func test_upgrade_is_the_third_card_lit_only_when_a_relic_can_be() -> void:
	var run := _run()
	var rest := _rest(run)
	assert_eq(_texts(rest.menu()), ["Rest", "Train", "Upgrade"])
	assert_true(rest.menu().items[2].icon is Texture2D, "a hammer and anvil")
	assert_false(rest.menu().is_enabled(2), "no Relic: dim")
	_press_on(rest, &"menu_right")
	_press_on(rest, &"menu_right")
	_press_on(rest, &"menu_confirm")
	assert_false(rest.is_picking(), "a dim card opens nothing")
	assert_false(rest.has_acted())
	run.give_relic(_relic("coffin_lid"), 0)
	var lit := _rest(run)
	assert_true(lit.menu().is_enabled(2), "a hero holds a Relic that is not + yet")
	run.upgrade_relic("coffin_lid")
	assert_false(_rest(run).menu().is_enabled(2), "every Relic is + already: dim again")


func test_before_the_boss_upgrade_takes_sharpens_place() -> void:
	var run := _run(3)
	_at_watch_fire(run)
	run.give_relic(_relic("wake_root"), 1)
	var rest := _rest(run)
	assert_eq(_texts(rest.menu()), ["Rest", "Keep watch", "Upgrade"])
	assert_true(rest.menu().is_enabled(2))
	assert_false(rest.has_method("sharpen_now"), "Sharpen went (DESIGN.md 8.25)")
	assert_false("sharpen_ap" in _tuning)
	assert_false("sharpened" in run)


# --- the pick ----------------------------------------------------------------------------------

func test_upgrade_opens_the_pick_back_returns_and_confirm_upgrades() -> void:
	var run := _run()
	run.give_relic(_relic("wake_root"), 0)
	run.give_relic(_relic("hounds_tooth"), 1)
	run.add_relic(_relic("coffin_lid"))
	var rest := _rest(run)
	rest.menu().index = RestScreen.CARD_UPGRADE
	_press_on(rest, &"menu_confirm")
	assert_true(rest.is_picking(), "Upgrade opens the pick")
	var ids: Array = rest.menu().items.map(func(row: Dictionary) -> String: return String(row.relic))
	assert_eq(ids, ["wake_root", "hounds_tooth"], "the heroes' Relics, in the run's order (not one still waiting)")
	var footer: Array = rest.footer_entries().map(func(entry: Array) -> StringName: return entry[0])
	assert_true(footer.has(&"menu_cancel"), "Back shows")
	# Back steps back to the three cards (Back never skips, DESIGN.md 8.24).
	_press_on(rest, &"menu_cancel")
	assert_false(rest.is_picking())
	assert_false(rest.has_acted(), "nothing done")
	assert_eq(_texts(rest.menu()), ["Rest", "Train", "Upgrade"])
	assert_eq(rest.menu().index, RestScreen.CARD_UPGRADE, "the cursor back on Upgrade")
	_press_on(rest, &"menu_confirm")
	_press_on(rest, &"menu_right")
	_press_on(rest, &"menu_confirm")
	assert_true(run.is_plus(_relic("hounds_tooth")), "the chosen Relic is Relic+")
	assert_false(run.is_plus(_relic("wake_root")))
	assert_true(rest.has_acted(), "the fire's one choice")
	assert_eq(_texts(rest.menu()), ["Back to the map"])
	assert_string_contains(rest._text.text, "Hound's Tooth+")


func test_a_pick_card_shows_who_holds_it_and_what_its_plus_adds() -> void:
	var run := _run()
	run.give_relic(_relic("hounds_tooth"), 1)
	var cards := RestScreen.pick_cards(run, [_relic("hounds_tooth")] as Array[GearData])
	assert_eq(cards.size(), 1)
	var card := cards[0]
	assert_eq(String(card.text), "Hound's Tooth")
	assert_true(card.icon_make is Callable, "its icon, big")
	var chips: Array = card.chips
	assert_eq(String(chips[0].text), run.data.party[1].display_name, "who holds it")
	assert_eq(chips[0].glyph, &"person")
	var gold: Array = chips.filter(func(chip: Dictionary) -> bool: return chip.get("glyph") == &"up")
	assert_eq(gold.size(), 1, "one chip for what Relic+ changes")
	assert_eq(String(gold[0].text), GearData.effect_text(GearData.Effect.FOLLOW_UP_DAMAGE, 80))
	assert_eq(gold[0].color, HudStyle.GOLD)
	assert_false(card.has("detail"), "no line under the cards: the chips say it, as on the Spoils")


func test_many_relics_show_three_cards_at_a_time() -> void:
	var run := _run()
	var ids: Array[String] = ["wake_root", "hounds_tooth", "coffin_lid", "grave_tag", "kingsbane_nail"]
	for i: int in ids.size():
		run.give_relic(_relic(ids[i]), i % run.party_size())
	var rest := _rest(run)
	assert_true(rest.open_upgrade())
	assert_eq(rest.picks().size(), 5)
	assert_eq(rest.menu().window_rows, RestScreen.PICK_SHOWN)
	assert_eq(rest._ask_label.text, "Which Relic?  (1 of 5)", "the count says more cards wait")
	for i: int in 4:
		_press_on(rest, &"menu_right")
	assert_eq(rest.menu().index, 4, "the last card slides in")
	assert_eq(rest.menu().top_row(), 2)
	assert_eq(rest._ask_label.text, "Which Relic?  (5 of 5)")
	assert_eq(RestScreen.pick_ask(0, RestScreen.PICK_SHOWN), RestScreen.PICK_ASK, "no count when all show")
	_press_on(rest, &"menu_cancel")
	assert_eq(rest.menu().window_rows, 0, "the three cards all show again")


## The pick takes the fire's place in a stage of a fixed height: the page never moves (the title
## stays where the three cards had it, scrolling the cards too) and it fits above the footer, for
## every Relic: all of them in the row (the widest cards) and each alone (the narrowest, tallest).
func test_the_pick_keeps_the_page_still_and_above_the_footer() -> void:
	var room := 1080.0 - ListMenu.FOOTER_STRIP_PX
	var run := _run()
	var count := 0
	for item: GearData in _data.gear:
		if item != null:
			run.give_relic(item, count % run.party_size())
			count += 1
	var rest := _rest(run)
	await _laid_out()
	var column := _column(rest)
	var title := column.get_child(0) as Control
	var height := column.get_combined_minimum_size().y
	var title_y := title.global_position.y
	assert_lte(height, room, "the three cards fit above the footer (%d)" % int(height))
	assert_true(rest.open_upgrade())
	assert_false(rest._scene_box.visible, "the cards take the fire's place")
	for i: int in rest.picks().size():
		rest.menu().index = i
		rest.menu().redraw()
		await _laid_out()
		assert_eq(column.get_combined_minimum_size().y, height, "the page keeps its height at %s" % rest.picks()[i].id)
		assert_eq(title.global_position.y, title_y, "the title stays put at %s" % rest.picks()[i].id)
	rest.close_upgrade()
	assert_true(rest._scene_box.visible, "Back brings the fire back")
	for item: GearData in _data.gear:
		if item == null:
			continue
		var alone := _run()
		alone.give_relic(item, 0)
		var one := _rest(alone)
		assert_true(one.open_upgrade(), item.id)
		await _laid_out()
		assert_eq(_column(one).get_combined_minimum_size().y, height, "%s alone fits the stage" % item.id)
		one.queue_free()


func _column(screen: Node) -> VBoxContainer:
	for child: Node in screen.get_children():
		if child is VBoxContainer:
			return child
	return null


## Wrapped labels (chips) know their height once laid out.
func _laid_out() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_the_upgrade_pays_rain_pouch_too() -> void:
	var run := _run()
	run.give_relic(_relic("rain_pouch"), 0)
	run.hp[0] = 1
	var rest := _rest(run)
	assert_true(rest.upgrade_now("rain_pouch"))
	assert_gt(run.hp[0], 1, "any campfire pick heals with Rain Pouch, Upgrade too")
	assert_string_contains(rest._text.text, "Rain Pouch")


# --- co-op and online ----------------------------------------------------------------------------

func test_local_co_op_upgrades_only_the_pickers_heroes_relics() -> void:
	var run := _run()
	run.give_relic(_relic("wake_root"), 0)
	run.give_relic(_relic("hounds_tooth"), 1)
	# Pad 5 plays hero 1; the keyboard plays hero 0 (as Main._give_heroes answers).
	var heroes := func(device: int) -> Array[int]:
		var mine: Array[int] = []
		mine.append(1 if device == 5 else 0)
		return mine
	var rest := _rest(run, heroes)
	assert_true(rest.open_upgrade(5))
	assert_eq(rest.picks(), [_relic("hounds_tooth")] as Array[GearData], "only their own hero's Relic")
	assert_false(rest.upgrade_now("wake_root", 5), "another player's hero's Relic is refused")
	assert_true(rest.upgrade_now("hounds_tooth", 5))
	var only_brin := _run()
	only_brin.give_relic(_relic("hounds_tooth"), 1)
	var other := _rest(only_brin, heroes)
	assert_false(other.open_upgrade(PlayerRoster.KEYBOARD), "nothing of theirs to upgrade: no pick")


func test_the_host_checks_a_friends_upgrade_against_the_turns_heroes() -> void:
	var main_script := load(MAIN_PATH) as GDScript
	var run := _run()
	run.give_relic(_relic("wake_root"), 0)
	run.give_relic(_relic("hounds_tooth"), 1)
	var turn_heroes := func(_device: int) -> Array[int]:
		var mine: Array[int] = [1]
		return mine
	var rest := _rest(run, turn_heroes)
	assert_eq(String(main_script.call("_make_rest_choice", rest, "upgrade", {"relic": "wake_root"})), "",
			"not a hero of the player whose turn it is")
	assert_false(run.is_plus(_relic("wake_root")))
	assert_eq(String(main_script.call("_make_rest_choice", rest, "upgrade", {"relic": "hounds_tooth"})), "upgrade hounds_tooth")
	assert_true(run.is_plus(_relic("hounds_tooth")))
	assert_eq(String(main_script.call("_make_rest_choice", rest, "sharpen", {})), "", "no Sharpen")


func test_a_friends_pick_is_asked_of_the_host_and_watching_greys_it() -> void:
	var run := _run()
	run.give_relic(_relic("wake_root"), 0)
	var rest := _rest(run)
	var asked: Array[Dictionary] = []
	rest.set_turn(false, func(choice: Dictionary) -> void: asked.append(choice))
	assert_true(rest.open_upgrade())
	assert_true(rest.upgrade_now("wake_root"))
	assert_eq(asked, [{"do": "upgrade", "relic": "wake_root"}] as Array[Dictionary])
	assert_false(run.is_plus(_relic("wake_root")), "the host does it")
	rest.set_turn(true)
	assert_false(rest.is_picking(), "another player's turn closes the pick")
	assert_false(rest.menu().is_enabled(2))
	assert_false(rest.open_upgrade(), "no pick while watching")


# --- the bot -------------------------------------------------------------------------------------

func test_the_bot_upgrades_the_relic_whose_plus_helps_most() -> void:
	var run := _run()
	assert_null(GearBot.upgrade_pick(run, [] as Array[GearData]), "nothing to upgrade")
	var coffin := _relic("coffin_lid")
	var tooth := _relic("hounds_tooth")
	# Coffin Lid 1 > 2 turns (+100%) helps more than Hound's Tooth 50 > 80 (+60%).
	assert_gt(GearBot.upgrade_gain(coffin), GearBot.upgrade_gain(tooth))
	assert_eq(GearBot.upgrade_pick(run, [tooth, coffin] as Array[GearData]), coffin)
	# A rider the parrying bot cannot use (Plague Lancet's dodge Bleed) is worth less than one it can.
	assert_lt(GearBot.upgrade_gain(_relic("plague_bell")), GearBot.upgrade_gain(_relic("grave_tag")))
	# A smaller price counts (Rotten Crown loses 1% HP a turn instead of 3%).
	assert_gt(GearBot.upgrade_gain(_relic("rotten_crown")), int(_relic("rotten_crown").rarity) * 10)
	assert_eq(GearBot.upgrade_gain(GearData.new()), -1, "no + at all")
	for item: GearData in _data.gear:
		assert_gte(GearBot.upgrade_gain(item), 0, "%s: the bot can weigh its +" % item.id)


func test_the_bot_scores_and_fits_every_relic() -> void:
	var dodge_only := GearBot.score(_relic("fox_step"))
	var parry := GearBot.score(_relic("still_water"))
	assert_gt(parry, dodge_only, "the bot parries: a parry Relic over a dodge one of the same rarity")
	assert_eq(GearBot.score(_relic("ash_veil")), -1, "Ash Veil takes the parry's AP")
	var party := _data.party
	var frail := 0
	var tough := 0
	for i: int in party.size():
		if party[i].hp_percent < party[frail].hp_percent:
			frail = i
		if party[i].hp_percent > party[tough].hp_percent:
			tough = i
	var run := _run()
	assert_eq(GearBot.best_hero(run, _relic("martyrs_ash")), frail, "Martyr's Ash: the one who falls first")
	assert_eq(GearBot.best_hero(run, _relic("lone_lantern")), tough, "Lone Lantern: the one still standing")
	var costly := 0
	var cost_of := func(hero: CharacterData) -> int:
		var total := 0
		for skill: AbilityData in hero.skills:
			total += skill.ap_cost if skill != null else 0
		return total
	for i: int in party.size():
		if int(cost_of.call(party[i])) > int(cost_of.call(party[costly])):
			costly = i
	assert_eq(GearBot.best_hero(run, _relic("rotten_crown")), costly, "Rotten Crown: the costliest skills")
	for item: GearData in _data.gear:
		var points := GearBot.score(item)
		assert_true(points == -1 or points >= 0, "%s has a score" % item.id)


# --- how a Relic+ shows ------------------------------------------------------------------------

func test_every_relic_has_a_plus_line_and_chips() -> void:
	var dir := DirAccess.open(GEAR_DIR)
	var count := 0
	for file: String in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var item := load("%s/%s" % [GEAR_DIR, file]) as GearData
		count += 1
		assert_eq(item.shown_name(true), item.display_name + "+")
		assert_eq(item.shown_name(false), item.display_name)
		assert_eq(item.text_line(false), item.description)
		assert_string_contains(item.text_line(true), item.description)
		assert_string_contains(item.text_line(true), "Relic+: " + item.plus_text)
		var plus := item.plus_texts()
		assert_false(plus.is_empty(), "%s: its + changes something to show" % item.id)
		for text: String in plus:
			assert_ne(text, GearData.effect_text(item.effect, item.amount), "%s: a + chip is not today's" % item.id)
		assert_eq(LootScreen.plus_chips(item).size(), plus.size())
	assert_eq(count, 63)


## A Relic+ that only lowers its price says the price it leaves, in the price's skull and colour, not
## as a gold gain (Black Ichor+: hits on you only +15%).
func test_a_lower_price_chip_reads_as_the_price_now() -> void:
	var item := _relic("black_ichor")
	var price := item.plus_price_text()
	assert_eq(price, "Price now: " + GearData.drawback_text(item.drawback, item.drawback_amount_plus))
	assert_true(item.plus_texts().has(price))
	var found := false
	for chip: Dictionary in LootScreen.plus_chips(item):
		if String(chip.text) == price:
			found = true
			assert_eq(chip.glyph, &"skull")
			assert_eq(chip.color, LootScreen.DRAWBACK_COLOR)
		else:
			assert_eq(chip.glyph, &"up", "a gain stays a gold up chip")
	assert_true(found)
	assert_eq(_relic("coffin_lid").plus_price_text(), "", "no price, no price chip")


func test_a_relic_plus_icon_wears_the_gold_plus() -> void:
	var item := _relic("coffin_lid")
	var plain := RelicIcon.make(item, 52.0)
	var plus := RelicIcon.make(item, 52.0, true, 0, 0, true)
	var unknown := RelicIcon.make(item, 52.0, false, 0, 0, true)
	add_child_autofree(plain)
	add_child_autofree(plus)
	add_child_autofree(unknown)
	assert_false(plain.shows_plus())
	assert_true(plus.shows_plus())
	assert_false(unknown.shows_plus(), "an unknown Relic shows only its ?")
	plain.set_plus(true)
	assert_true(plain.shows_plus())


func test_the_y_screen_shows_name_plus_and_both_lines() -> void:
	var run := _run()
	run.give_relic(_relic("hounds_tooth"), 1)
	var tab := RelicsTab.new()
	tab.run = run
	var before := tab._relic_info(_relic("hounds_tooth"))
	assert_eq(String(before.title), "Hound's Tooth")
	assert_false(bool(before.plus))
	assert_eq(String(before.line), "Follow-ups hit +50%.")
	run.upgrade_relic("hounds_tooth")
	var after := tab._relic_info(_relic("hounds_tooth"))
	assert_eq(String(after.title), "Hound's Tooth+")
	assert_true(bool(after.plus), "the strip's icon gets the gold +")
	assert_string_contains(String(after.line), "Relic+: +80%.")
	tab.free()


## The hero rows' narrow name under an icon: a long Relic+ name is cut before its "+", never the "+".
func test_a_long_relic_plus_name_keeps_its_plus_under_the_icon() -> void:
	var font := ThemeDB.fallback_font
	var item := _relic("gravediggers_spade")
	var whole := item.shown_name(true)
	var width := font.get_string_size(whole, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x * 0.6
	var cut := RelicsTab.fit_name(item, true, font, 18, width)
	assert_true(cut.ends_with("\u2026+"), "the + stays: " + cut)
	assert_lte(font.get_string_size(cut, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, width)
	assert_eq(RelicsTab.fit_name(item, true, font, 18, 9999.0), whole, "whole when it fits")
	assert_eq(RelicsTab.fit_name(item, false, font, 18, width), item.display_name, "a plain name: the label trims it")


func test_the_relic_book_shows_each_relics_plus_line() -> void:
	var item := _relic("coffin_lid")
	var chips := RelicsScreen.focus_chips(item, true)
	var gold: Array = chips.filter(func(chip: Dictionary) -> bool: return chip.get("glyph") == &"up")
	assert_eq(gold.size(), 1, "what its + changes")
	assert_true(bool(gold[0].newline), "on a line of its own")
	var book := RelicCollection.new()
	book.merge(["coffin_lid"])
	var screen := RelicsScreen.new()
	add_child_autofree(screen)
	screen.setup(book, _data.gear)
	assert_true(screen.focus(item))
	assert_string_contains(screen._detail_more.text, item.description)
	assert_string_contains(screen._detail_more.text, "Relic+: Guarded for 2 turns.")


func test_the_map_and_the_glossary_name_the_upgrade() -> void:
	var run := _run()
	var look := load("res://data/presentation/map_visuals.tres") as MapVisuals
	for stop: Dictionary in run.map.stops:
		if int(stop.type) != RunMap.StopType.REST:
			continue
		var chips := MapScreen.detail_chips(run, stop, look, "")
		assert_eq(String(chips[chips.size() - 1].text), RestScreen.UPGRADE_CHIP)
		break
	var glossary := load("res://data/glossary/glossary.tres") as GlossaryData
	assert_not_null(glossary.find("relic_plus"))
	assert_not_null(glossary.find("camp_upgrade"))
	for entry: GlossaryEntry in glossary.entries:
		assert_false(entry.text.contains("Sharpen"), "%s: Sharpen went" % entry.id)
