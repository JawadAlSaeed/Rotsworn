extends GutTest
## Two or three choices side by side, with icons (card #288): the run's choice screens (spoils,
## campfire, treasure, "?" events and the starting pact) show their choices as cards with a picture
## and icon chips instead of sentences, and the main menu's Online page is two cards (the zone
## shrine's question with its chips went with the zones in phase 26, DESIGN.md 8.22). The bots' methods keep working. Uses the shipped run.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const EVENTS_DIR := "res://data/events"
## The screen the menus are laid out for, less the footer strip.
const SCREEN_HEIGHT: float = 1080.0

var _data: RunData
var _tuning: Tuning
var _look: StopVisuals
var _picked: Array[StringName] = []
var _events: Array[int] = []


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning
	_look = StopVisuals.load_default()


func before_each() -> void:
	_picked.clear()
	_events.clear()


## A run with an empty purse (the shipped run starts with run_start_gold since #321).
func _run(seed_value: int = 7) -> RunState:
	var run := RunState.begin(_data, _tuning, seed_value)
	run.gold = 0
	return run


func _event(id: String) -> EventData:
	return load("%s/%s.tres" % [EVENTS_DIR, id]) as EventData


func _press_on(node: Node, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	node._unhandled_input(event)


func _press(menu: ListMenu, action: StringName) -> StringName:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return menu.handle(event)


func _texts(menu: ListMenu) -> Array:
	return menu.items.map(func(row: Dictionary) -> String: return String(row.get("text", "")))


func _chip_kinds(chips: Array) -> Array:
	return chips.map(func(chip: Dictionary) -> String: return String(chip.get("kind", "")))


## The row of cards a horizontal list draws (its HBoxContainer child), or null.
func _strip(menu: ListMenu) -> HBoxContainer:
	for child: Node in menu.get_children():
		if child is HBoxContainer and not child.is_queued_for_deletion():
			return child as HBoxContainer
	return null


# --- the cards themselves -------------------------------------------------------------------------

func test_a_card_shows_its_icon_and_chips_and_greys_when_it_cannot_be_taken() -> void:
	var menu := ListMenu.new()
	add_child_autofree(menu)
	menu.horizontal = true
	var coin := AssetLoader.texture(_look.chip_gold_path, Vector2i(12, 12))
	var items: Array[Dictionary] = [
		{"text": "Pay", "icon": coin, "chips": [{"icon": coin, "text": "-40"}, {"icon": coin, "text": "+80"}]},
		{"text": "Too dear", "enabled": false, "icon": coin, "chips": [{"icon": coin, "text": "-999"}]},
	]
	menu.set_items(items)
	var cards := _strip(menu)
	assert_not_null(cards)
	assert_eq(cards.get_child_count(), 2)
	var first := cards.get_child(0)
	assert_eq(first.find_children("*", "TextureRect", true, false).size(), 3, "the card's icon and one per chip")
	assert_eq(first.find_children("*", "HFlowContainer", true, false).size(), 1, "its chips in one line")
	assert_eq(menu.card_chips(0).size(), 2)
	var grey := cards.get_child(1)
	for node: Node in grey.find_children("*", "TextureRect", true, false):
		var faded := false
		var at: Node = node
		while at != grey and not faded:
			faded = (at as CanvasItem).modulate.a < 1.0
			at = at.get_parent()
		assert_true(faded, "a card that cannot be taken greys its icon and chips")


func test_a_card_list_can_turn_back_into_a_column() -> void:
	var menu := ListMenu.new()
	add_child_autofree(menu)
	menu.horizontal = true
	var items: Array[Dictionary] = [{"text": "Rest"}, {"text": "Train"}]
	menu.set_items(items)
	assert_not_null(_strip(menu))
	menu.horizontal = false
	var list: Array[Dictionary] = [{"text": "Salve"}, {"text": "Bomb"}, {"text": "Back"}]
	menu.set_items(list)
	assert_null(_strip(menu), "no row of cards left behind")
	assert_eq(menu.get_child_count(), 3, "a column's rows are the list's own children, as before")
	assert_eq(_press(menu, &"menu_down"), &"")
	assert_eq(menu.index, 1)
	assert_eq(_press(menu, &"menu_right"), &"right", "a column still reports left and right")


func test_chips_wrap_inside_the_card_instead_of_widening_it() -> void:
	var lines := ListMenu.chip_lines([{"text": "A very long name for a reward that goes on"}, {"text": "+1"},
			{"text": "55%", "newline": true}], 284.0)
	add_child_autofree(lines)
	assert_eq(lines.get_child_count(), 2, "a chip marked newline starts a second line")
	assert_lte(lines.get_combined_minimum_size().x, 284.0 + 1.0)


# --- what a deal costs and gives, as chips --------------------------------------------------------

func test_offer_chips_carry_the_numbers_that_will_be_paid() -> void:
	var run := _run()
	var offer := ZoneOfferData.new()
	offer.cost_gold = 40
	offer.cost_hp_percent = 10
	offer.cost_max_hp_percent = 5
	offer.heal_percent = 30
	offer.gold = 80
	offer.xp = 20
	var chips := run.offer_chips(offer, 150)
	assert_eq(_chip_kinds(chips), ["gold", "hp", "max_hp", "heal", "gold", "xp"], "the price first, then the gift")
	assert_eq(String(chips[0].text), "-%d gold" % CombatMath.percent(40, 150))
	assert_true(bool(chips[0].cost))
	assert_eq(String(chips[3].text), "+30% HP")
	assert_eq(String(chips[4].text), "+%d gold" % CombatMath.percent(80, 150))
	assert_false(bool(chips[4].cost))
	for chip: Dictionary in chips:
		assert_false(_look.chip_icon_path(String(chip.kind)).is_empty(), "%s has an icon" % chip.kind)


func _max_hp_chip(chips: Array) -> String:
	for chip: Dictionary in chips:
		if String(chip.kind) == "max_hp":
			return String(chip.text)
	return ""


func test_a_max_hp_chip_says_who_pays() -> void:
	var run := _run()
	var texts: Array[String] = []
	for target: int in [ZoneOfferData.HpTarget.EVERYONE, ZoneOfferData.HpTarget.CHOSEN, ZoneOfferData.HpTarget.RANDOM]:
		var offer := ZoneOfferData.new()
		offer.cost_max_hp_percent = 5
		offer.cost_max_hp_target = target as ZoneOfferData.HpTarget
		texts.append(_max_hp_chip(run.offer_chips(offer)))
	assert_eq(texts, ["-5% max HP all", "-5% max HP 1", "-5% max HP 1?"] as Array[String], "everyone, a hero you pick, a random hero")
	# The shipped events: everyone pays at the Black Mirror, one random hero at the Hanging Cage.
	var mirror := _max_hp_chip(run.choice_chips(_event("black_mirror").choices[0]))
	var cage := _max_hp_chip(run.choice_chips(_event("hanging_cage").choices[0]))
	assert_true(mirror.ends_with(" all"), mirror)
	assert_true(cage.ends_with(" 1?"), cage)
	assert_ne(mirror.get_slice(" ", 3), cage.get_slice(" ", 3), "who pays differs on the cards")
	var item := ZoneOfferData.new()
	item.cost_item = ZoneOfferData.ItemCost.RANDOM
	var random_item := String(run.offer_chips(item)[0].text)
	item.cost_item = ZoneOfferData.ItemCost.CHOSEN
	assert_ne(random_item, String(run.offer_chips(item)[0].text), "a random item and a picked one differ")


func test_a_curse_a_fight_and_a_risk_get_their_own_icons() -> void:
	var run := _run()
	var stop := -2
	var bones := run.choice_chips(_event("gamblers_bones").choices[1], stop)
	assert_has(_chip_kinds(bones), "curse", "the purse's risk is a curse")
	var die := bones.filter(func(chip: Dictionary) -> bool: return String(chip.kind) == "risk")
	assert_eq(die.size(), 1, "a die for the chance")
	assert_eq(String(die[0].text), "Risk %d%%" % _event("gamblers_bones").choices[1].risk_percent)
	assert_true(bool(die[0].newline), "the risk goes on its own line")
	for chip: Dictionary in bones.slice(bones.find(die[0])):
		assert_true(bool(chip.get("risk", false)), "what the risk does is marked as the risk")
	assert_has(_chip_kinds(run.choice_chips(_event("sealed_door").choices[0])), "fight", "an ambush is a fight chip")
	var entries := StopScreen.chip_entries(bones, _look)
	assert_eq(entries.size(), bones.size())
	for entry: Dictionary in entries:
		assert_true(entry.icon is Texture2D, "every chip has its picture")
	assert_eq(entries[0].color, _look.chip_gift_color, "+60 gold is a gift")


# --- "?" events and the starting pact ---------------------------------------------------------

func _event_screen(run: RunState, event: EventData) -> EventScreen:
	var screen := EventScreen.new()
	add_child_autofree(screen)
	screen.setup(run, event)
	screen.chosen.connect(func(index: int, _text: String) -> void: _events.append(index))
	return screen


func test_an_event_shows_its_choices_as_cards_with_price_chips() -> void:
	var run := _run()
	var event := _event("gamblers_bones")
	var screen := _event_screen(run, event)
	assert_true(screen.menu().horizontal, "the choices sit side by side")
	assert_eq(screen.rows().size(), event.choices.size(), "no Leave card")
	var stake := screen.rows()[0].chips as Array
	assert_eq(String(stake[0].text), "-%d gold" % CombatMath.percent(event.choices[0].deal.cost_gold, run.event_scale(run.at)))
	assert_false(bool(screen.rows()[0].enabled), "greyed: the party cannot pay the stake")
	assert_has(screen.footer_entries(), [&"menu_cancel", "Leave"])
	assert_has(screen.footer_entries(), [&"@leftright", "Choose"])
	var column := screen.menu().get_parent() as Control
	assert_lte(column.get_combined_minimum_size().y, SCREEN_HEIGHT - ListMenu.FOOTER_STRIP_PX, "the screen fits")


func test_cancel_leaves_an_event_and_the_bot_methods_still_work() -> void:
	var run := _run()
	var screen := _event_screen(run, _event("gamblers_bones"))
	_press_on(screen, &"menu_cancel")
	assert_eq(_events, [-1] as Array[int], "cancel walks on, taking nothing")
	assert_eq(String(screen.rows()[0].text), "Continue")
	assert_false(screen.menu().horizontal, "one way on: no cards")
	var done := [false]
	screen.done.connect(func() -> void: done[0] = true)
	screen.leave()
	assert_true(done[0])
	var other := _event_screen(_run(), _event("gamblers_bones"))
	assert_true(other.choose(1), "the bot's choose() takes a choice")
	assert_eq(_events.back(), 1)


## Three heroes or fewer: who pays is three cards with the heroes' faces, and Back is the cancel
## button, never a row (owner, phase 22).
func test_who_pays_is_hero_cards_and_back_returns_to_the_choices() -> void:
	var run := _run()
	var screen := _event_screen(run, _event("whispering_mask"))
	screen.menu().index = 0
	_press_on(screen, &"menu_confirm")
	assert_true(screen.menu().horizontal, "who pays: the heroes side by side")
	assert_eq(screen.rows().size(), run.party_size(), "no Back row")
	assert_true(screen.rows()[0].get("icon") is Texture2D, "each hero card shows the hero's face")
	assert_has(screen.footer_entries(), [&"menu_cancel", "Back"])
	_press_on(screen, &"menu_cancel")
	assert_true(screen.menu().horizontal, "back to the cards")
	assert_eq(screen.menu().index, 0, "on the choice that asked")
	assert_eq(_events.size(), 0, "nothing was taken")


func test_a_greyed_card_that_asks_who_pays_does_not_open_the_list() -> void:
	var run := _run()
	for slot: int in run.party_size():
		run.max_hp_percent[slot] = _tuning.event_max_hp_floor_percent
	var screen := _event_screen(run, _event("whispering_mask"))
	assert_false(bool(screen.rows()[0].enabled), "nobody has max HP left to give")
	screen.menu().index = 0
	_press_on(screen, &"menu_confirm")
	assert_true(screen.menu().horizontal, "still the cards")
	assert_eq(screen.rows().size(), 2)
	assert_eq(_events.size(), 0, "nothing was taken")


func test_the_starting_pact_is_three_cards() -> void:
	var run := _run()
	var pact := run.pact_event()
	assert_not_null(pact)
	var screen := _event_screen(run, pact)
	assert_true(screen.menu().horizontal)
	assert_eq(screen.rows().size(), _tuning.run_pact_choices)
	for row: Dictionary in screen.rows():
		assert_false((row.chips as Array).is_empty(), "%s: its price and gift as chips" % row.text)
	var column := screen.menu().get_parent() as Control
	assert_lte(column.get_combined_minimum_size().x, 1920.0 - 60.0, "three cards fit the width")


# --- the campfire -----------------------------------------------------------------------------

func _rest(run: RunState) -> RestScreen:
	var rest := RestScreen.new()
	add_child_autofree(rest)
	rest.setup(run)
	return rest


func test_the_campfire_choices_are_cards_with_icons_and_numbers() -> void:
	var run := _run()
	var rest := _rest(run)
	var menu := rest.menu()
	assert_true(menu.horizontal)
	assert_eq(_texts(menu), ["Rest", "Train", "Upgrade"])
	for row: Dictionary in menu.items:
		assert_true(row.icon is Texture2D, "%s has a picture" % row.text)
	assert_eq(String((menu.items[0].chips as Array)[0].text), "+%d%% HP" % run.rest_heal_percent(), "Rest says how much it heals")
	assert_eq(String((menu.items[1].chips as Array)[0].text), "+%d points" % _tuning.rest_train_points)
	assert_false(bool(menu.items[2].enabled), "nothing to upgrade in an empty pack")
	for entry: Array in rest.footer_entries():
		assert_ne(entry[0], &"menu_cancel", "no Back while choosing")
	_press_on(rest, &"menu_cancel")
	assert_false(rest.has_acted(), "Back does nothing while choosing")
	assert_true(menu.horizontal)


func test_a_greyed_upgrade_card_does_nothing_when_chosen() -> void:
	var run := _run()
	var rest := _rest(run)
	assert_false(bool(rest.menu().items[2].enabled), "nothing to upgrade in an empty pack")
	rest.menu().index = 2
	_press_on(rest, &"menu_confirm")
	assert_true(rest.menu().horizontal, "still the three cards, no empty item list")
	assert_eq(_texts(rest.menu()), ["Rest", "Train", "Upgrade"])
	_press_on(rest, &"menu_confirm")
	assert_false(rest.has_acted(), "and a second press does not Rest by itself")


func test_upgrading_lists_the_items_and_back_returns() -> void:
	var run := _run()
	run.add_item(run.items_by_id()["salve"] as ItemData)
	var rest := _rest(run)
	assert_true(bool(rest.menu().items[2].enabled))
	rest.menu().index = 2
	_press_on(rest, &"menu_confirm")
	assert_true(rest.menu().horizontal, "one item to upgrade: a card")
	assert_eq(rest.menu().items.size(), 1, "no Back row")
	assert_has(rest.footer_entries(), [&"menu_cancel", "Back"])
	_press_on(rest, &"menu_cancel")
	assert_true(rest.menu().horizontal)
	assert_eq(rest.menu().index, 2, "back on Upgrade")
	assert_true(rest.upgrade_now(rest.upgradable()[0]), "the bot's upgrade_now() still works")
	assert_eq(_texts(rest.menu()), ["Back to the map"])


func test_the_bot_rests_and_trains_as_before() -> void:
	var run := _run()
	run.hp[0] = 1
	var rest := _rest(run)
	rest.rest_now()
	assert_gt(run.hp[0], 1)
	assert_true(rest.has_acted())
	var other := _rest(_run())
	var before := run.free_points(0)
	other.train_now()
	assert_true(other.has_acted())
	assert_eq(other.run.free_points(0), before + _tuning.rest_train_points)


# --- treasure ---------------------------------------------------------------------------------

func _treasure(run: RunState) -> TreasureScreen:
	var screen := TreasureScreen.new()
	add_child_autofree(screen)
	screen.setup(run)
	return screen


func test_the_two_chests_are_cards_with_what_they_give_and_risk() -> void:
	var run := _run()
	run.go(run.choices()[0])
	var screen := _treasure(run)
	var menu := screen.menu()
	assert_true(menu.horizontal)
	assert_eq(_texts(menu), ["Plain", "Rotten"])
	for row: Dictionary in menu.items:
		assert_true(row.icon is Texture2D, "a chest on each card")
	assert_true(menu.items[1].icon_color is Color, "the rotten chest is tinted")
	var plain := menu.items[0].chips as Array
	assert_eq(String(plain[0].text), "+%d gold" % _tuning.run_treasure_gold)
	var rotten := _chip_kinds(menu.items[1].chips as Array)
	assert_eq(rotten, ["relic", "curse", "fight"])
	assert_eq(String((menu.items[1].chips as Array)[1].text), "Curse %d%%" % _tuning.rotten_chest_curse_percent)
	screen.open_chest(false)
	assert_true(screen.is_open(), "the bot's open_chest() still works")
	assert_false(screen.menu().horizontal)


# --- spoils -----------------------------------------------------------------------------------

func test_spoils_are_relic_cards_with_their_icon_tag_and_stat() -> void:
	var run := _run()
	run.go(run.choices()[0])
	var gear := run.loot_choices(run.at)
	assert_false(gear.is_empty())
	var loot := LootScreen.new()
	add_child_autofree(loot)
	loot.setup(gear, "The guard fell.", run)
	var menu := loot.menu()
	assert_true(menu.horizontal)
	assert_eq(menu.items.size(), gear.size())
	var cards := _strip(menu)
	assert_eq(cards.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is RelicIcon).size(),
			gear.size(), "each Relic's own icon")
	for i: int in gear.size():
		assert_eq(String(menu.items[i].value), "New", "a Relic the run lacks is New")
		assert_false((menu.items[i].chips as Array).is_empty(), "what it does, as chips")
	for label: Node in loot.find_children("*", "Label", true, false):
		assert_false((label as Label).text.contains("Take one"), "no sentence over the cards")
	var taken: Array = []
	loot.chosen.connect(func(item: GearData, hero: int) -> void: taken.append([item, hero]))
	assert_false(loot.take(0), "a Relic needs the hero who gets it (DESIGN.md 8.24)")
	assert_true(loot.take(0, 1))
	assert_eq(taken, [[gear[0], 1]], "the bot's take() still works")
	assert_false(loot.take(1, 1), "once")


func test_the_spoils_ask_who_gets_the_relic() -> void:
	var run := _run()
	run.go(run.choices()[0])
	var gear := run.loot_choices(run.at)
	var loot := LootScreen.new()
	add_child_autofree(loot)
	loot.setup(gear, "", run)
	var taken: Array = []
	loot.chosen.connect(func(item: GearData, hero: int) -> void: taken.append([item, hero]))
	loot.menu().index = 1
	_press_on(loot, &"menu_confirm")
	assert_true(loot.is_giving(), "a Relic picked: who gets it?")
	assert_true(taken.is_empty())
	var cards := loot.menu().items
	assert_eq(cards.size(), run.party_size(), "a card per hero")
	for slot: int in cards.size():
		assert_eq(String(cards[slot].text), run.data.party[slot].display_name, "the hero's name")
		assert_true(bool(cards[slot].enabled), "solo: any hero")
	_press_on(loot, &"menu_cancel")
	assert_false(loot.is_giving(), "Back to the Relics")
	assert_eq(loot.menu().index, 1, "on the Relic picked")
	_press_on(loot, &"menu_confirm")
	loot.menu().index = 2
	_press_on(loot, &"menu_confirm")
	assert_eq(taken, [[gear[1], 2]], "the Relic and its hero")
	# Local co-op: only the picking player's heroes (Main's give_heroes).
	var duo := LootScreen.new()
	add_child_autofree(duo)
	duo.give_heroes = func(_device: int) -> Array[int]: return [0, 2] as Array[int]
	duo.setup(gear, "", run)
	_press_on(duo, &"menu_confirm")
	assert_true(duo.is_giving())
	assert_false(bool(duo.menu().items[1].enabled), "another player's hero is greyed")
	assert_eq(duo.menu().index, 0, "the cursor starts on a hero who may get it")
	var solo := LootScreen.new()
	add_child_autofree(solo)
	solo.give_heroes = func(_device: int) -> Array[int]: return [1] as Array[int]
	solo.setup(gear, "", run)
	var got: Array = []
	solo.chosen.connect(func(item: GearData, hero: int) -> void: got.append(hero))
	_press_on(solo, &"menu_confirm")
	assert_eq(got, [1], "one hero who may: no hero step")


func test_only_a_relic_the_book_lacks_is_new_and_the_hero_step_survives_a_redraw() -> void:
	var main_script := load("res://scenes/main.gd") as GDScript
	var run := _run()
	run.go(run.choices()[0])
	var gear := run.loot_choices(run.at)
	assert_gt(gear.size(), 1)
	var book := RelicCollection.new()
	book.merge([gear[0].id])
	var booked := RunState.begin(_data, _tuning, 7, 0, book)
	var loot := LootScreen.new()
	add_child_autofree(loot)
	loot.setup(gear, "", booked)
	assert_eq(String(loot.menu().items[0].value), "", "in the Relic book already: no tag (no Home)")
	assert_eq(String(loot.menu().items[1].value), "New", "not in the book yet")
	for chip: Array in ShopScreen.relic_chips(booked, gear[0]):
		assert_false(["New", "Home"].has(String(chip[1])), "a shelf has no tag for it either")
	assert_eq(String(ShopScreen.relic_chips(booked, gear[1])[0][1]), "New")
	# Online a friend's "Who gets it?" stays up when the host's newer state comes (card #326).
	assert_false(main_script.call("_keeps_hero_pick", loot))
	_press_on(loot, &"menu_confirm")
	assert_true(loot.is_giving())
	assert_true(main_script.call("_keeps_hero_pick", loot), "the hero cards are not rebuilt away")
	_press_on(loot, &"menu_cancel")
	assert_false(main_script.call("_keeps_hero_pick", loot))
	var shop := ShopScreen.new()
	add_child_autofree(shop)
	run.gold = 999
	shop.setup(run, gear)
	var shelf := shop.items().size()
	assert_true(shop.is_relic(shelf))
	assert_false(main_script.call("_keeps_hero_pick", shop))
	shop._open_give_pick(shelf)
	assert_true(main_script.call("_keeps_hero_pick", shop), "the shop's hero pick too")
	shop._close_pick()
	assert_false(main_script.call("_keeps_hero_pick", shop))
	assert_false(main_script.call("_keeps_hero_pick", _treasure(run)), "a closed chest")


# --- the yes/no prompt ---------------------------------------------------------------------------

func test_a_question_keeps_its_answers_side_by_side() -> void:
	var prompt := ConfirmPrompt.new()
	add_child_autofree(prompt)
	prompt.setup("Abandon this run?", "The run is lost.", "Abandon run", "Keep playing")
	assert_true(prompt._menu.horizontal)
	assert_eq(prompt._menu.items.size(), 2)


# --- the main menu's Online page --------------------------------------------------------------

func _main_menu(start: StringName = MainMenu.ONLINE) -> MainMenu:
	var menu := MainMenu.new()
	add_child_autofree(menu)
	menu.setup(BrandingData.new(), start)
	menu.chosen.connect(func(item: StringName) -> void: _picked.append(item))
	return menu


func _list_in(node: Node) -> ListMenu:
	for found: Node in node.find_children("*", "", true, false):
		if found is ListMenu:
			return found as ListMenu
	return null


func test_online_is_host_and_join_side_by_side() -> void:
	var menu := _main_menu()
	var list := _list_in(menu)
	assert_false(menu.is_showing_cards(), "the main list is a column")
	_press_on(menu, &"menu_confirm")
	assert_eq(_picked.size(), 0, "Online opens its page")
	assert_true(menu.is_showing_cards())
	assert_eq(_texts(list), ["Host", "Join"], "no Back card: Back is the cancel button")
	for row: Dictionary in list.items:
		assert_true(row.icon is Texture2D, "%s has a picture" % row.text)
	_press_on(menu, &"menu_right")
	_press_on(menu, &"menu_confirm")
	assert_eq(_picked, [MainMenu.JOIN_ONLINE] as Array[StringName])
	_press_on(menu, &"menu_cancel")
	assert_false(menu.is_showing_cards())
	assert_eq(String(list.items[list.index].text), "Online", "cancel goes back to the Online row")


## Online > Host starts hosting a run at once (the second mode's cards before it were cut, card #331);
## coming back from hosting rests on Online.
func test_host_hosts_a_run_straight_away() -> void:
	var menu := _main_menu()
	_press_on(menu, &"menu_confirm")
	_press_on(menu, &"menu_confirm")
	assert_eq(_picked, [MainMenu.HOST_ONLINE] as Array[StringName], "Host emits HOST_ONLINE, no cards first")
	var back := _main_menu(MainMenu.HOST_ONLINE)
	assert_false(back.is_showing_cards())
	assert_eq(String(_list_in(back).items[_list_in(back).index].text), "Online", "back from hosting: on Online")


## New Run starts the run's path at once, as before phase 25 (card #331): no cards open.
func test_new_run_starts_straight_away() -> void:
	var menu := _main_menu(MainMenu.NEW_RUN)
	var list := _list_in(menu)
	assert_eq(String(list.items[list.index].text), "New Run")
	_press_on(menu, &"menu_confirm")
	assert_eq(_picked, [MainMenu.NEW_RUN] as Array[StringName], "New Run emits NEW_RUN, no cards first")
	assert_false(menu.is_showing_cards())


func test_extras_stays_a_list_with_back() -> void:
	var menu := _main_menu(MainMenu.EXTRAS)
	_press_on(menu, &"menu_confirm")
	assert_false(menu.is_showing_cards())
	assert_eq(String(_list_in(menu).items.back().text), "Back")


## A card's word stays on one line: the cards grow (sharing the row) and a word too long even then
## gets a smaller font (owner, phase 22).
func test_card_words_stay_on_one_line() -> void:
	var menu := ListMenu.new()
	add_child_autofree(menu)
	menu.horizontal = true
	var items: Array[Dictionary] = [{"text": "Borrow years"}, {"text": "Take the crown of ash"},
			{"text": "Blood for gold"}]
	menu.set_items(items)
	for i: int in items.size():
		var width := ListMenu.title_width(String(items[i].text), menu.card_title_size(i))
		assert_true(width <= menu._card_inner() + 0.5, "%s fits on one line" % items[i].text)
	assert_eq(menu.card_title_size(1), menu.item_size, "three cards have room for it at full size")
	var long: Array[Dictionary] = [{"text": "An extremely long choice name that cannot possibly fit"},
			{"text": "B"}, {"text": "C"}]
	menu.set_items(long)
	assert_lt(menu.card_title_size(0), menu.item_size, "too long even then: a smaller font")
	assert_true(menu._card_w * 3.0 + float(ListMenu.CARD_GAP * 2) <= ListMenu.CARD_ROW_MAX_WIDTH + 0.5,
			"the row never gets wider than the screen allows")
