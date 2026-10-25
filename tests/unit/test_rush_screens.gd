extends GutTest
## The Fight Rush screens (DESIGN.md 8.21, card #305). The Rush screen between fights: after a win
## its reward cards side by side (Heal, Train, an item; Relics after elites and bosses), Heal greyed
## when nobody would gain HP and naming a hero whose Relics change it, the hand-out of an item or Relic
## over it, the next pick, then the ready phase (Fight and Party) that asks for the fight once; a
## watching client takes nothing; it fits the screen at the largest text size. The Rush's end screen
## (RUSH OVER, the record, no Kept row), the Fight Rush players screen's title and the fight end's
## Rewards / Results hints. Uses the shipped Rush data. Nothing here touches user://.

const RUSH_PATH := "res://data/rush/fight_rush.tres"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const SCREEN_SIZE := Vector2(1920.0, 1080.0)

var _rush: RushData
var _tuning: Tuning
var _size_index: int = 0


func before_all() -> void:
	_rush = load(RUSH_PATH) as RushData


func before_each() -> void:
	_tuning = (load(TUNING_PATH) as Tuning).duplicate() as Tuning
	_size_index = HudStyle.text_size_index()


func after_each() -> void:
	HudStyle.set_text_size_index(_size_index)


## A Rush that has just won fight `n` (the fights before it replayed by the dev head start), its
## cards on show. `hurt`: everyone ends the fight at half HP (else full).
func _won(n: int, hurt: bool = true) -> RushState:
	var r := RushState.begin_rush(_rush, _tuning, 7, null, n)
	r.next_fight()
	assert_eq(r.fight, n)
	var hp: Array[int] = []
	for slot: int in r.party_size():
		@warning_ignore("integer_division")
		hp.append(r.max_hp(slot) / 2 if hurt else r.max_hp(slot))
	r.finish_fight(RunState.VICTORY, hp, r.encounter_now(), {})
	return r


func _screen(r: RushState, best: int = 0, remote: bool = false) -> RushRewardScreen:
	var screen := RushRewardScreen.new()
	screen.remote = remote
	add_child_autofree(screen)
	screen.setup(r, best)
	return screen


func _press_on(node: Node, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	node._unhandled_input(event)


func _texts(menu: ListMenu) -> Array:
	return menu.items.map(func(row: Dictionary) -> String: return String(row.get("text", "")))


func _kinds(r: RushState) -> Array:
	return r.offer.map(func(card: Dictionary) -> String: return String(card.kind))


func _chip_texts(row: Dictionary) -> Array:
	return (row.get("chips", []) as Array).map(func(chip: Dictionary) -> String: return String(chip.get("text", "")))


func _card_of(r: RushState, kind: String) -> int:
	for i: int in r.offer.size():
		if String(r.offer[i].kind) == kind:
			return i
	return -1


func _gear(r: RushState, id: String) -> GearData:
	return r.data.gear.filter(func(g: GearData) -> bool: return g != null and g.id == id)[0] as GearData


# --- the pick phase -----------------------------------------------------------------------------

func test_a_normal_win_shows_heal_train_and_an_item_side_by_side() -> void:
	var r := _won(3)
	assert_eq(_kinds(r), ["heal", "point", "item"])
	var screen := _screen(r)
	var menu := screen.menu()
	assert_true(screen.is_picking())
	assert_eq(screen.title_text(), "REWARD")
	assert_true(menu.horizontal, "the cards sit side by side")
	var item := r.card_thing(2) as ItemData
	assert_eq(_texts(menu), ["Heal", "Train", item.display_name])
	for row: Dictionary in menu.items:
		assert_true(row.get("icon") is Texture2D, "%s has a picture" % row.text)
		assert_false((row.get("chips", []) as Array).is_empty(), "%s says what it gives" % row.text)
	assert_eq(_chip_texts(menu.items[0])[0], "+%d%% HP" % _tuning.rush_heal_card_percent)
	assert_eq(_chip_texts(menu.items[1]), [RushRewardScreen.points_text(_tuning.rush_point_card_points)])
	assert_eq(_chip_texts(menu.items[2])[0], RushRewardScreen.rarity_word(int(item.rarity)), "the item's rarity first")
	assert_eq(menu.items[2].color, BackpackGrid.rarity_color(int(item.rarity)))
	assert_eq(screen.chip_texts(), ["Fight 3"] as Array[String], "no best yet, one pick")
	assert_has(screen.footer_entries(), [&"@leftright", "Choose"])
	assert_has(screen.footer_entries(), [&"menu_confirm", "Take"])
	assert_has(screen.footer_entries(), [&"party_menu", "Party"])
	for label: Node in screen.find_children("*", "Label", true, false):
		assert_false((label as Label).text.contains("gold") or (label as Label).text.contains("Gold"), "no gold on a Rush")


func test_the_best_and_extra_picks_show_as_chips() -> void:
	var r := _won(3)
	r.picks_left = 2
	var screen := _screen(r, 16)
	assert_eq(screen.chip_texts(), ["Fight 3", "Best 16", "+1 pick"] as Array[String])


func test_a_card_that_cannot_be_filled_is_left_out() -> void:
	var r := _won(3)
	var screen := _screen(r)
	assert_eq(screen.menu().items.size(), 3)
	# No item the party wants: the item card is not rolled.
	r.offer.remove_at(2)
	screen.refresh()
	assert_eq(_texts(screen.menu()), ["Heal", "Train"])
	assert_eq(_screen(r).menu().items.size(), 2, "a fresh screen too")


func test_heal_is_greyed_at_full_hp_and_refused() -> void:
	var r := _won(3, false)
	assert_false(r.card_enabled(0))
	var screen := _screen(r)
	assert_false(bool(screen.menu().items[0].enabled), "nobody would gain HP")
	assert_eq(screen.menu().index, 1, "the cursor starts on the first card that can be taken")
	watch_signals(screen)
	var picks := r.pick_no
	screen.menu().index = 0
	_press_on(screen, &"menu_confirm")
	assert_true(r.picking(), "nothing was taken")
	assert_eq(r.pick_no, picks)
	assert_false(screen.take(0), "nor by the bot's take()")
	assert_signal_not_emitted(screen, "acted")


func test_heal_names_a_hunger_charm_wearer() -> void:
	var r := _won(3)
	assert_false(r.give_relic(_gear(r, "hunger_charm"), 0).is_empty())
	var chips := _chip_texts(_screen(r).menu().items[0])
	assert_eq(chips.size(), 2, "everyone's heal, then the hero it differs for")
	assert_eq(chips[1], "%s +0%%" % r.data.party[0].display_name)
	var dim: Dictionary = _screen(r).menu().items[0].chips[1]
	assert_eq(dim.color, HudStyle.TEXT_DIM)


func test_taking_train_gives_points_and_moves_to_the_ready_phase() -> void:
	var r := _won(3)
	var before := r.bonus_points.duplicate()
	var screen := _screen(r)
	watch_signals(screen)
	screen.menu().index = 1
	_press_on(screen, &"menu_confirm")
	for slot: int in r.party_size():
		assert_eq(r.bonus_points[slot], before[slot] + _tuning.rush_point_card_points)
	assert_signal_emit_count(screen, "acted", 1)
	assert_false(screen.is_picking())
	assert_eq(screen.title_text(), "FIGHT 4", "the next fight's number")
	assert_eq(_texts(screen.menu()), ["Fight", "Party"])
	assert_eq(screen.menu().index, 0, "the cursor starts on Fight")
	for row: Dictionary in screen.menu().items:
		assert_true(row.get("icon") is Texture2D, "%s has a picture" % row.text)
	assert_has(screen.footer_entries(), [&"menu_confirm", "Select"])
	assert_has(screen.footer_entries(), [&"party_menu", "Party"])
	assert_gt(r.unspent_points(), 0)
	assert_eq(_chip_texts(screen.menu().items[1]), [RushRewardScreen.points_text(r.unspent_points())],
			"Party shows the points to spend")
	assert_eq(_chip_texts(screen.menu().items[0]), [], "fight 4 is a normal fight")
	assert_eq(screen.chip_texts(), [] as Array[String], "the fight won is no longer shown")


func test_the_fight_card_says_elite_or_boss() -> void:
	var elite := _won(4)
	var screen := _screen(elite)
	assert_true(screen.take(_card_of(elite, "point")))
	assert_eq(screen.title_text(), "FIGHT 5")
	assert_eq(_chip_texts(screen.menu().items[0]), ["Elite"])
	var boss := _won(9)
	var other := _screen(boss, 12)
	assert_true(other.take(_card_of(boss, "point")))
	assert_eq(_chip_texts(other.menu().items[0]), ["Boss"])
	assert_eq(other.chip_texts(), ["Best 12"] as Array[String], "the best stays on show")


func test_taking_a_relic_asks_who_gets_it_and_then_rolls_the_next_pick() -> void:
	var r := _won(5)
	assert_eq(_kinds(r), ["heal", "point", "relic"], "an elite offers a Relic")
	var relic_index := _card_of(r, "relic")
	var gear := r.card_thing(relic_index) as GearData
	var screen := _screen(r)
	assert_true(screen.menu().items[relic_index].get("icon_make") is Callable, "the Relic's own icon")
	assert_eq(String(screen.menu().items[relic_index].get("value", "")), "",
			"no New tag: a Rush keeps nothing for the Relic book (DESIGN.md 8.21, 8.24)")
	# An extra pick waits after this one (XP past the top level, D1).
	r.picks_left = 2
	screen.refresh()
	watch_signals(screen)
	assert_false(screen.take(relic_index), "a Relic card needs the hero who gets it")
	screen.menu().index = relic_index
	_press_on(screen, &"menu_confirm")
	assert_true(screen.is_giving(), "Who gets it?")
	assert_eq(screen.title_text(), RelicGift.ASK)
	assert_eq(screen.menu().items.size(), r.party_size(), "one card per hero")
	_press_on(screen, &"menu_cancel")
	assert_false(screen.is_giving(), "Back: the cards again")
	assert_eq(screen.menu().index, relic_index)
	_press_on(screen, &"menu_confirm")
	screen.menu().index = 2
	_press_on(screen, &"menu_confirm")
	assert_eq(r.holder_of(gear), 2, "the hero picked has it")
	assert_null(screen.overlay(), "nothing to hand out: no party screen")
	assert_signal_emit_count(screen, "acted", 1)
	assert_true(screen.is_picking(), "the extra pick")
	assert_eq(_kinds(r), ["heal", "point", "item"], "an extra pick is the normal set")
	assert_eq(screen.menu().items.size(), 3)
	assert_eq(screen.title_text(), "REWARD")


func test_a_relic_card_never_offers_one_the_party_has() -> void:
	var r := _won(10)
	var offered: Array[GearData] = []
	for i: int in r.offer.size():
		if r.card_thing(i) is GearData:
			offered.append(r.card_thing(i) as GearData)
	assert_eq(offered.size(), 2)
	var again := _won(10)
	for item: GearData in offered:
		again.add_relic(item)
	again.roll_offer()
	for i: int in again.offer.size():
		assert_false(offered.has(again.card_thing(i)), "no copies in a Rush either")


func test_an_item_that_fits_goes_straight_into_the_pack() -> void:
	var r := _won(3)
	var item := r.card_thing(2) as ItemData
	var screen := _screen(r)
	assert_true(screen.take(2))
	assert_null(screen.overlay(), "room in the pack: no party screen")
	if item.kind != ItemData.Kind.UPGRADE:
		var held := r.backpack.entries.filter(func(e: Dictionary) -> bool: return (e.item as ItemData) == item)
		assert_eq(held.size(), 1, "the item is in")
	assert_false(screen.is_picking())
	assert_eq(_texts(screen.menu()), ["Fight", "Party"])


func test_a_boss_offers_train_and_two_relics() -> void:
	var r := _won(10)
	assert_eq(_kinds(r), ["point", "relic", "relic"])
	var screen := _screen(r)
	assert_ne(screen.menu().items[1].text, screen.menu().items[2].text, "two different Relics")


# --- the ready phase ----------------------------------------------------------------------------

func test_the_ready_phase_asks_for_the_fight_once() -> void:
	var r := _won(3)
	var screen := _screen(r)
	watch_signals(screen)
	screen.fight_now()
	assert_signal_not_emitted(screen, "fight_requested", "not while picking")
	assert_true(screen.take(_card_of(r, "point")))
	screen.menu().index = RushRewardScreen.READY_FIGHT
	_press_on(screen, &"menu_confirm")
	screen.fight_now()
	_press_on(screen, &"menu_confirm")
	assert_signal_emit_count(screen, "fight_requested", 1)


func test_party_opens_from_the_card_and_the_button() -> void:
	var r := _won(3)
	var screen := _screen(r)
	watch_signals(screen)
	_press_on(screen, &"party_menu")
	assert_signal_emit_count(screen, "party_requested", 1, "the button works while picking")
	assert_true(screen.take(_card_of(r, "point")))
	screen.menu().index = RushRewardScreen.READY_PARTY
	_press_on(screen, &"menu_confirm")
	assert_signal_emit_count(screen, "party_requested", 2)
	assert_signal_not_emitted(screen, "fight_requested")


func test_a_new_rush_opens_on_the_ready_phase() -> void:
	var r := RushState.begin_rush(_rush, _tuning, 7)
	var screen := _screen(r)
	assert_false(screen.is_picking())
	assert_eq(screen.title_text(), "FIGHT 1")
	assert_eq(_texts(screen.menu()), ["Fight", "Party"])


func test_a_watching_client_takes_nothing() -> void:
	var r := _won(3)
	var screen := _screen(r, 0, true)
	assert_eq(screen.footer_entries(), [[&"party_menu", "Party"]], "only the party button: no card to take")
	for row: Dictionary in screen.menu().items:
		assert_false(bool(row.enabled), "%s is the host's to take" % row.text)
	watch_signals(screen)
	screen.menu().index = 1
	_press_on(screen, &"menu_confirm")
	assert_false(screen.take(1))
	assert_true(r.picking(), "nothing was taken")
	assert_signal_not_emitted(screen, "acted")
	_press_on(screen, &"party_menu")
	assert_signal_emit_count(screen, "party_requested", 1, "a friend may still look at the party")


## While the host gets ready, a watching friend sees Fight greyed and Party lit, the cursor on it:
## Confirm there (or the party button the footer shows) opens the party screen; Fight stays the host's.
func test_a_watching_client_can_open_the_party_from_the_ready_phase() -> void:
	var r := _won(3)
	assert_true(r.take_card(_card_of(r, "point")).has("kind"))
	r.next_offer()
	assert_false(r.picking())
	var screen := _screen(r, 0, true)
	assert_eq(screen.title_text(), "FIGHT 4")
	var rows := screen.menu().items
	assert_false(bool(rows[RushRewardScreen.READY_FIGHT].enabled), "Fight is the host's")
	assert_true(bool(rows[RushRewardScreen.READY_PARTY].enabled), "the party is everyone's")
	assert_eq(screen.menu().index, RushRewardScreen.READY_PARTY, "the cursor starts on Party")
	assert_eq(screen.footer_entries(), [[&"party_menu", "Party"]])
	watch_signals(screen)
	_press_on(screen, &"menu_confirm")
	assert_signal_emit_count(screen, "party_requested", 1, "Confirm on Party opens it")
	_press_on(screen, &"menu_right")
	assert_eq(screen.menu().index, RushRewardScreen.READY_PARTY, "a friend's cursor does not move")
	screen.menu().index = RushRewardScreen.READY_FIGHT
	_press_on(screen, &"menu_confirm")
	screen.fight_now()
	assert_signal_not_emitted(screen, "fight_requested", "never from a friend")
	assert_signal_emit_count(screen, "party_requested", 1)
	var host := _screen(r)
	assert_eq(host.menu().index, RushRewardScreen.READY_FIGHT, "the host's cursor starts on Fight, as before")


# --- layout ---------------------------------------------------------------------------------------

func _fits(screen: RushRewardScreen, what: String) -> void:
	var column := screen.menu().get_parent() as Control
	var need := column.get_combined_minimum_size()
	assert_lte(need.y, SCREEN_SIZE.y - ListMenu.FOOTER_STRIP_PX, "%s fits the height (it is %d tall)" % [what, int(need.y)])
	assert_lte(need.x, SCREEN_SIZE.x, "%s fits the width (it is %d wide)" % [what, int(need.x)])


func test_the_screen_fits_1920x1080_at_the_largest_text_size() -> void:
	HudStyle.set_text_size_index(HudStyle.fonts().text_size_percents.size() - 1)
	var normal := _won(3)
	assert_false(normal.give_relic(_gear(normal, "hunger_charm"), 0).is_empty())
	assert_false(normal.give_relic(_gear(normal, "rain_pouch"), 1).is_empty())
	normal.picks_left = 2
	var samples: Array[Array] = [[normal, "a normal pick"], [_won(5), "an elite pick"], [_won(10), "a boss pick"]]
	var ready := _won(9)
	ready.take_card(_card_of(ready, "point"))
	samples.append([ready, "the ready phase"])
	for sample: Array in samples:
		var screen := _screen(sample[0] as RushState, 16)
		await get_tree().process_frame
		_fits(screen, String(sample[1]))
		screen.visible = false


# --- step (d): the Rush end, the players screen title, the fight end hints ------------------------

## Every Label text under `node`.
static func _labels_of(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for label: Node in node.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts


func _end(r: RushState, best: Dictionary, new_record: bool, recap: Dictionary) -> RunEndScreen:
	var end := RunEndScreen.new()
	add_child_autofree(end)
	end.setup_rush(r, 0, best, new_record, [] as Array[int], recap)
	return end


func test_the_rush_end_shows_the_fight_the_record_and_no_kept_row() -> void:
	var r := _won(3)
	r.picks_left = 0
	r.next_fight()
	r.finish_fight(RunState.DEFEAT, [0, 0, 0] as Array[int], r.encounter_now(), {})
	assert_eq(r.result, RunState.DEFEAT)
	var recap := {"enemies": ["Rotten Husk"], "last_blow": {"name": "Swipe", "source": "Rotten Husk", "amount": 23}}
	var end := _end(r, RushRecords.entry(4, "2026-10-24"), true, recap)
	var texts := _labels_of(end)
	assert_true(texts.has("RUSH OVER"), "the title")
	assert_true(texts.has("NEW RECORD"), "a new record says so")
	assert_true(texts.has("Fight 4"), "the fight reached")
	assert_true(texts.has("Best 4") and texts.has("2026-10-24"), "the record and its day")
	assert_true(texts.has("Solo"), "the party size")
	assert_true(texts.has("Killed by"), "a loss shows the killer")
	assert_false(texts.has("Kept"), "nothing from a Rush is kept")
	assert_eq(end.find_children("*", "RelicIcon", true, false).size(), 0, "no Kept row of Relics")
	for text: String in texts:
		assert_false(text.contains("Gold") or text.contains("RUN OVER"), "'%s' is not a run's word" % text)


func test_a_rush_given_up_has_no_killer_and_no_record_line() -> void:
	var r := _won(3)
	r.give_up()
	var recap := {"enemies": ["Rotten Husk"], "last_blow": {"name": "Swipe", "source": "Rotten Husk", "amount": 23}}
	var texts := _labels_of(_end(r, {}, false, recap))
	assert_true(texts.has("RUSH OVER"))
	assert_false(texts.has("Killed by"), "Give up is not a loss: no killer")
	assert_false(texts.has("NEW RECORD"))
	# (The defence rows' star reads "Best" alone; the record chip reads "Best 16".)
	assert_false(texts.any(func(t: String) -> bool: return t.begins_with("Best ")), "no record kept: no Best chip")
	assert_true(texts.has("Fight 3"), "the fight won last is the fight reached")
	var plain := _labels_of(_end(_won(2), {}, false, {}))
	assert_true(plain.has("RUSH OVER"), "builds without a recap too")


func test_a_rush_given_up_before_its_first_fight_shows_no_fight_0() -> void:
	var r := RushState.begin_rush(_rush, _tuning, 7)
	r.give_up()
	assert_eq(r.reached(), 0, "Fight was never pressed")
	var chips := RunEndScreen.rush_chips(r, RushRecords.entry(16, "2026-10-20")).map(
			func(chip: Dictionary) -> String: return String(chip.text))
	assert_eq(chips, ["Best 16", "Solo"], "no sword chip without a fight")
	var texts := _labels_of(_end(r, RushRecords.entry(16, "2026-10-20"), false, {}))
	assert_true(texts.has("RUSH OVER"))
	assert_true(texts.has("Best 16") and texts.has("Solo"), "the record and the party size still show")
	assert_false(texts.any(func(t: String) -> bool: return t.begins_with("Fight ")), "no Fight 0 (nor any fight) chip")
	assert_eq(RunEndScreen.rush_chips(r, {}).map(func(chip: Dictionary) -> String: return String(chip.text)),
			["Solo"], "no fight and no record: the party size alone")


func test_the_rush_end_chips_read_fight_best_and_party_size() -> void:
	var r := _won(16)
	r.note_players(2)
	var texts := RunEndScreen.rush_chips(r, RushRecords.entry(16, "2026-10-24")).map(
			func(chip: Dictionary) -> String: return String(chip.text))
	assert_eq(texts, ["Fight 16", "Best 16", "Duo"])
	var icons := RunEndScreen.rush_chips(r, RushRecords.entry(16, "2026-10-24")).map(
			func(chip: Dictionary) -> Variant: return chip.icon)
	assert_eq(icons, [&"sword", &"star", &"person"], "each word has its icon")
	assert_eq(String(RunEndScreen.rush_chips(r, RushRecords.entry(16, "2026-10-24"))[1].detail), "2026-10-24")
	var none := RunEndScreen.rush_chips(r, {}).map(func(chip: Dictionary) -> String: return String(chip.text))
	assert_eq(none, ["Fight 16", "Duo"], "no record: no Best chip")
	r.note_players(3)
	assert_eq(String(RunEndScreen.rush_chips(r, {})[1].text), "Trio")


func test_the_players_screen_takes_its_title() -> void:
	var data := _rush.run
	var names: Array[String] = []
	var portraits: Array[String] = []
	for c: CharacterData in data.party:
		names.append(c.display_name)
		portraits.append(c.big_portrait_path)
	var rush_lobby := LobbyScreen.new()
	rush_lobby.hero_portraits = portraits
	rush_lobby.title_text = "Fight Rush"
	rush_lobby.setup(names, null, PlayerRoster.KEYBOARD)
	add_child_autofree(rush_lobby)
	assert_true(_labels_of(rush_lobby).has("Fight Rush"), "the Fight Rush players screen")
	assert_false(_labels_of(rush_lobby).has("Players"))
	var run_lobby := LobbyScreen.new()
	run_lobby.hero_portraits = portraits
	run_lobby.setup(names, null, PlayerRoster.KEYBOARD)
	add_child_autofree(run_lobby)
	assert_true(_labels_of(run_lobby).has("Players"), "a run's keeps its title")


func test_a_rush_fight_end_says_rewards_or_results() -> void:
	var fight := CombatController.new()
	fight.configure_run(_won(3))
	fight._result = "victory"
	assert_eq(fight._end_hints(), [[&"menu_confirm", "Rewards"]], "a win goes on to the cards")
	fight._result = "defeat"
	assert_eq(fight._end_hints(), [[&"menu_confirm", "Results"]], "a loss goes on to the end")
	fight.free()
	var run_fight := CombatController.new()
	run_fight.configure_run(RunState.new())
	run_fight._result = "victory"
	assert_eq(run_fight._end_hints(), [[&"menu_confirm", "On with the run"]], "a run's words stay")
	run_fight.free()
