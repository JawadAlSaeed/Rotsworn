extends GutTest
## Online run choices in turns (card #314, DESIGN.md 9.2 "Taking turns"): each new choice screen
## belongs to the next seated player in seat order, skipping a seat that is away or joining; the same
## screen again keeps its owner; a drop or a leave passes the turn on; with Take turns off the host
## makes every choice. The host makes a friend's choice only on their turn, on the screen up now, and
## only one the screen can take. A find with no room on a friend's turn is handed to them to place.
## Nothing touches user:// (the settings run in memory).

const MAIN_PATH := "res://scenes/main.gd"
const RUN_PATH := "res://data/runs/rotten_road.tres"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const EVENTS_DIR := "res://data/events"
const HOST: int = 1
const PEER_A: int = 1001
const PEER_B: int = 1002

var _data: RunData
var _tuning: Tuning
var _main: GDScript
var _settings_before: ConfigFile


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_main = load(MAIN_PATH) as GDScript


func before_each() -> void:
	_tuning = (load(TUNING_PATH) as Tuning).duplicate() as Tuning
	_settings_before = PlayerSettings._config
	PlayerSettings._config = ConfigFile.new()
	PlayerSettings.set_persistence(false)


func after_each() -> void:
	PlayerSettings._config = _settings_before
	PlayerSettings.set_persistence(true)


## The host and `friends` friends online (peers PEER_A, PEER_B).
func _roster(friends: int) -> PlayerRoster:
	var roster := PlayerRoster.online(_data.party.size(), HOST, HOST)
	for peer: int in [PEER_A, PEER_B].slice(0, friends):
		roster.join_peer(peer)
	return roster


func _run() -> RunState:
	return RunState.begin(_data, _tuning, 7)


func _item(run: RunState, id: String) -> ItemData:
	return run.items_by_id()[id] as ItemData


## Fills every free pocket of the backpack with `id`.
func _fill(run: RunState, id: String) -> void:
	var item := _item(run, id)
	for i: int in run.backpack.width:
		run.add_item(item)


## The text of function `header` in main.gd, up to the next top-level function.
func _body(header: String) -> String:
	var source := FileAccess.get_file_as_string(MAIN_PATH)
	var start := source.find(header)
	assert_gt(start, -1, "found: %s" % header)
	if start < 0:
		return ""
	var end := source.find("\nfunc ", start + 1)
	var static_end := source.find("\nstatic func ", start + 1)
	if static_end > 0 and (end < 0 or static_end < end):
		end = static_end
	return source.substr(start, end - start if end > start else -1)


# --- the order ----------------------------------------------------------------------------------

func test_each_new_choice_goes_to_the_next_player_in_seat_order() -> void:
	var roster := _roster(2)
	var turns := ChoiceTurns.new()
	var owners: Array[int] = []
	for key: String in ["map:0:0", "stop:0:1", "map:0:1", "stop:0:2", "map:0:2"]:
		turns.turn_for(key, roster)
		owners.append(turns.player)
	assert_eq(owners, [0, 1, 2, 0, 1], "P1, P2, P3, then round again")
	assert_eq(turns.peer, PEER_A, "P2's machine")


func test_the_same_screen_again_keeps_its_owner() -> void:
	var roster := _roster(2)
	var turns := ChoiceTurns.new()
	turns.turn_for("map:0:0", roster)
	turns.turn_for("stop:0:1", roster)
	assert_false(turns.turn_for("stop:0:1", roster), "a result or a redraw is the same choice")
	assert_eq(turns.player, 1)


func test_an_away_or_joining_seat_is_skipped() -> void:
	var roster := _roster(2)
	roster.set_away(PEER_A)
	var turns := ChoiceTurns.new()
	turns.turn_for("map:0:0", roster)
	turns.turn_for("stop:0:1", roster)
	assert_eq(turns.player, 2, "P2 is away: P3 next")
	roster.set_back(PEER_A)
	roster.set_joining(PEER_B)
	turns.turn_for("map:0:1", roster)
	assert_eq(turns.player, 0, "P3 is joining: round to P1")
	assert_eq(ChoiceTurns.seated(roster), [0, 1] as Array[int])


func test_a_drop_passes_the_turn_on() -> void:
	var roster := _roster(2)
	var turns := ChoiceTurns.new()
	turns.turn_for("map:0:0", roster)
	turns.turn_for("stop:0:1", roster)
	assert_eq(turns.player, 1)
	roster.set_away(PEER_A)
	assert_true(turns.pass_if_gone(roster), "P2 dropped: the turn passes")
	assert_eq(turns.player, 2)
	assert_eq(turns.peer, PEER_B)
	assert_eq(turns.key, "stop:0:1", "the same screen, a new owner")
	assert_false(turns.pass_if_gone(roster), "P3 is still here")


func test_a_leave_passes_the_turn_to_who_moves_up() -> void:
	var roster := _roster(2)
	var turns := ChoiceTurns.new()
	turns.turn_for("map:0:0", roster)
	turns.turn_for("stop:0:1", roster)
	roster.drop_peer(PEER_A)
	assert_true(turns.pass_if_gone(roster))
	assert_eq(turns.peer, PEER_B, "P3 moved up into P2's seat: theirs now")
	assert_eq(turns.player, 1)
	turns.turn_for("map:0:1", roster)
	assert_eq(turns.player, 0, "then round to P1")


func test_a_seat_moving_up_keeps_the_turn() -> void:
	var roster := _roster(2)
	var turns := ChoiceTurns.new()
	for key: String in ["map:0:0", "stop:0:1", "map:0:1"]:
		turns.turn_for(key, roster)
	assert_eq(turns.peer, PEER_B)
	roster.drop_peer(PEER_A)
	assert_false(turns.pass_if_gone(roster), "P3's own turn goes on")
	assert_eq(turns.player, 1, "now in seat 2")
	turns.turn_for("stop:0:2", roster)
	assert_eq(turns.player, 0)


func test_a_rejoin_before_the_drop_was_noticed_passes_the_turn() -> void:
	var roster := _roster(2)
	var turns := ChoiceTurns.new()
	turns.turn_for("map:0:0", roster)
	turns.turn_for("stop:0:1", roster)
	assert_eq(turns.peer, PEER_A)
	# P2 is back with a new connection before the host saw the old one go: no away or left signal.
	assert_eq(roster.rebind_peer(PEER_A, 2001), 1)
	assert_true(roster.set_away(2001), "away until caught up")
	assert_true(turns.pass_if_gone(roster), "the old peer is gone: the turn passes")
	assert_eq(turns.player, 2)
	assert_eq(turns.peer, PEER_B)
	var rejoined := _body("func _on_net_peer_rejoined(")
	assert_true(rejoined.contains("_pass_turn()"))
	assert_lt(rejoined.find("_pass_turn()"), rejoined.find("_catch_up("), "the screen they get carries it")
	var newcomer := _body("func _seat_newcomer(")
	assert_lt(newcomer.find("_pass_turn()"), newcomer.find("_catch_up("), "a seat taken over too")


func test_a_turn_already_used_is_not_passed_on() -> void:
	# P2 took the map step into a fight and dropped in it: no screen of theirs is up, so the turn is not
	# passed on (it would give P3's turn away). The spoils after the fight are P3's, as with no drop.
	var roster := _roster(2)
	var turns := ChoiceTurns.new()
	turns.turn_for("map:0:0", roster)
	turns.turn_for("map:0:1", roster)
	assert_eq(turns.player, 1, "P2's map step")
	roster.set_away(PEER_A)
	turns.turn_for("loot:0:2", roster)
	assert_eq(turns.player, 2, "an away seat keeps its peer: P3 after P2")
	var stale := ChoiceTurns.new()
	stale.turn_for("map:0:0", roster)
	roster.set_back(PEER_A)
	stale.turn_for("map:0:1", roster)
	roster.set_away(PEER_A)
	stale.pass_if_gone(roster)
	stale.turn_for("loot:0:2", roster)
	assert_eq(stale.player, 0, "passed in the fight, it skips P3: what _pass_turn must not do")
	# Main passes a turn only while its screen is still the place everyone is on.
	var run := _run()
	var map_key: String = _main.call("_choice_key_of", "map", run)
	var on := func(place: Dictionary, fight: Dictionary, key: String) -> bool:
		return bool(_main.call("_turn_on_screen", place, fight, run, key))
	assert_true(on.call({"name": "map"}, {}, map_key), "the map is up: a drop passes the turn")
	assert_false(on.call({"name": "map"}, {"name": "stop_fight"}, map_key), "in the fight it chose")
	assert_false(on.call({"name": "map"}, {}, ""), "no turn yet")
	assert_true(on.call({"name": "event", "pact": true}, {}, "pact"), "the pact goes as an event screen")
	run.go(run.choices()[0])
	assert_false(on.call({"name": "map"}, {}, map_key), "the step was taken (its fade): the map's key moved on")
	var stop_key: String = _main.call("_choice_key_of", "loot", run)
	assert_true(on.call({"name": "loot"}, {}, stop_key), "the spoils are up")
	assert_false(on.call({"name": "party"}, {}, stop_key), "the spoil was taken: its party screen")
	assert_string_contains(_body("func _pass_turn("), "_turn_on_screen(_net_place, _net_fight, _run, _turns.key)")


func test_the_last_seat_dropping_wraps_to_p1() -> void:
	var roster := _roster(1)
	var turns := ChoiceTurns.new()
	turns.turn_for("map:0:0", roster)
	turns.turn_for("stop:0:1", roster)
	roster.set_away(PEER_A)
	assert_true(turns.pass_if_gone(roster))
	assert_eq(turns.player, 0)
	assert_eq(turns.peer, HOST)


func test_take_turns_off_leaves_every_choice_to_the_host() -> void:
	var roster := _roster(2)
	var turns := ChoiceTurns.new()
	turns.enabled = false
	for key: String in ["map:0:0", "stop:0:1", "map:0:1"]:
		turns.turn_for(key, roster)
		assert_eq(turns.player, 0)
		assert_eq(turns.peer, HOST)


func test_alone_every_choice_is_p1s() -> void:
	var roster := _roster(0)
	var turns := ChoiceTurns.new()
	turns.turn_for("map:0:0", roster)
	turns.turn_for("stop:0:1", roster)
	assert_eq(turns.player, 0)


func test_only_the_owner_for_the_screen_up_now_may_choose() -> void:
	var roster := _roster(2)
	var turns := ChoiceTurns.new()
	assert_false(turns.allows(HOST, ""), "no turn yet")
	turns.turn_for("map:0:0", roster)
	turns.turn_for("stop:0:1", roster)
	assert_true(turns.allows(PEER_A, "stop:0:1"))
	assert_false(turns.allows(PEER_B, "stop:0:1"), "not P3's turn")
	assert_false(turns.allows(PEER_A, "map:0:0"), "a stale choice for the last screen")
	assert_eq(turns.to_dict(), {"key": "stop:0:1", "peer": PEER_A, "player": 1})
	turns.reset()
	assert_eq(turns.key, "")
	assert_eq(turns.player, -1)


# --- the keys -----------------------------------------------------------------------------------

func test_each_choice_screen_has_its_own_key() -> void:
	var run := _run()
	assert_eq(_main.call("_choice_key_of", "map", run), "map:0:0")
	assert_eq(_main.call("_choice_key_of", "pact", run), "pact")
	assert_eq(_main.call("_choice_key_of", "party", run), "", "the party screen has no turn")
	run.go(run.choices()[0])
	assert_eq(_main.call("_choice_key_of", "event", run), "stop:0:1")
	assert_eq(_main.call("_choice_key_of", "shop", run), "stop:0:1", "one stop, one screen")
	assert_eq(_main.call("_choice_key_of", "loot", run), "loot:0:1", "spoils after its fight: a new turn")
	assert_eq(_main.call("_choice_key_of", "map", run), "map:0:1")


# --- the host checks a friend's request ---------------------------------------------------------

## A host Main (not in the tree) on `screen`, its turn given to P2 for `key`.
func _host_on(screen: Node, run: RunState, key: String) -> Node:
	var main: Node = autofree(_main.new())
	var roster := _roster(2)
	main.set("_players", roster)
	main.set("_run", run)
	main.set("_screen", screen)
	var turns: ChoiceTurns = main.get("_turns")
	turns.turn_for("first", roster)
	turns.turn_for(key, roster)
	assert_eq(turns.peer, PEER_A)
	return main


func _event_screen(run: RunState, id: String) -> EventScreen:
	var screen := EventScreen.new()
	add_child_autofree(screen)
	screen.setup(run, load("%s/%s.tres" % [EVENTS_DIR, id]) as EventData)
	return screen


func test_the_host_makes_a_friends_choice_on_their_turn() -> void:
	var run := _run()
	run.gold = 500
	var screen := _event_screen(run, "gamblers_bones")
	screen.watching = true
	var main := _host_on(screen, run, "stop:0:1")
	main.call("_on_friend_choice", PEER_A, {"key": "stop:0:1", "choice": {"do": "walk_on"}})
	assert_true(screen.is_decided(), "P2 walked on")


func test_the_host_drops_a_choice_from_the_wrong_player_or_screen() -> void:
	var run := _run()
	run.gold = 500
	var screen := _event_screen(run, "gamblers_bones")
	var main := _host_on(screen, run, "stop:0:1")
	main.call("_on_friend_choice", PEER_B, {"key": "stop:0:1", "choice": {"do": "walk_on"}})
	assert_false(screen.is_decided(), "not P3's turn")
	main.call("_on_friend_choice", PEER_A, {"key": "map:0:0", "choice": {"do": "walk_on"}})
	assert_false(screen.is_decided(), "a stale choice for another screen")
	main.call("_on_friend_choice", PEER_A, {"key": "stop:0:1", "choice": "walk_on"})
	assert_false(screen.is_decided(), "not a choice")
	main.call("_on_friend_choice", PEER_A, {"key": "stop:0:1", "choice": {"do": "open"}})
	assert_false(screen.is_decided(), "not one this screen has")


func test_a_choice_the_screen_cannot_take_is_refused() -> void:
	var run := _run()
	var rest := RestScreen.new()
	add_child_autofree(rest)
	rest.setup(run)
	assert_eq(_main.call("_make_choice", rest, {"do": "watch"}), "", "Keep watch is the boss fire's")
	assert_eq(_main.call("_make_choice", rest, {"do": "upgrade", "uid": 999}), "", "no such item")
	assert_eq(_main.call("_make_choice", rest, {"do": "rest"}), "rest")
	assert_true(rest.has_acted())
	assert_eq(_main.call("_make_choice", rest, {"do": "train"}), "", "once per campfire")
	var map := MapScreen.new()
	add_child_autofree(map)
	map.setup(run, null, false)
	assert_eq(_main.call("_make_choice", map, {"do": "stop", "id": -5}), "", "not a next stop")
	assert_eq(_main.call("_make_choice", map, {"do": "buy", "index": 0}), "", "not a map choice")


func test_leave_waits_until_the_screen_shows_the_way_on() -> void:
	var run := _run()
	var rest := RestScreen.new()
	add_child_autofree(rest)
	rest.setup(run)
	var left := [0]
	rest.done.connect(func() -> void: left[0] += 1)
	assert_eq(_main.call("_make_choice", rest, {"do": "leave"}), "", "nothing taken at the fire yet")
	assert_eq(left[0], 0)
	assert_eq(_main.call("_make_choice", rest, {"do": "rest"}), "rest")
	assert_eq(_main.call("_make_choice", rest, {"do": "leave"}), "leave", "Back to the map is up now")
	assert_eq(left[0], 1)
	var chest_run := _run()
	chest_run.go(chest_run.choices()[0])
	var chest := TreasureScreen.new()
	add_child_autofree(chest)
	chest.setup(chest_run)
	assert_eq(_main.call("_make_choice", chest, {"do": "leave"}), "", "the chest is still shut")
	chest.open_chest(false)
	assert_true(_main.call("_can_leave", chest), "opened: Continue is up")
	var event := _event_screen(_run(), "gamblers_bones")
	assert_eq(_main.call("_make_choice", event, {"do": "leave"}), "", "undecided: its way out is walk_on")
	assert_eq(_main.call("_make_choice", event, {"do": "walk_on"}), "walk_on")
	assert_true(_main.call("_can_leave", event), "You walk on: Continue is up")
	assert_true(_body("func _autoplay_event(").contains("screen.walk_on"), "a friend's bot walks on, as a player")


func test_the_spoils_are_greyed_on_another_players_turn() -> void:
	var run := _run()
	var loot := LootScreen.new()
	loot.watching = true
	add_child_autofree(loot)
	loot.setup(run.loot_choices(run.at), "", run)
	assert_gt(loot.menu().items.size(), 0)
	for row: Dictionary in loot.menu().items:
		assert_false(bool(row.enabled), "another player's pick")
	assert_true(loot.footer_entries().is_empty(), "nothing to press")
	loot.set_turn(false)
	for row: Dictionary in loot.menu().items:
		assert_true(bool(row.enabled), "the turn passed here")
	assert_true(str(loot.footer_entries()).contains("Take") or str(loot.footer_entries()).contains("Continue"))
	loot.set_turn(true)
	assert_false(bool(loot.menu().items[0].enabled), "and greyed again")


func test_a_friends_own_party_screen_stays_over_the_map_drawn_again() -> void:
	assert_true(_main.call("_waits_under_party", "map", {"name": "map"}, true), "the map drawn again")
	assert_false(_main.call("_waits_under_party", "map", {"name": "party"}, true),
			"a party screen the host sent follows the host")
	assert_false(_main.call("_waits_under_party", "map", {"name": "map"}, false), "no party screen up")
	assert_false(_main.call("_waits_under_party", "shop", {"name": "map"}, true), "the party went on to a stop")
	var client := _body("func _client_screen(")
	assert_lt(client.find("_waits_under_party("), client.find("_fade_to("), "checked before the screen is replaced")


func test_the_host_opens_a_chest_and_takes_a_spoil_for_a_friend() -> void:
	var run := _run()
	run.go(run.choices()[0])
	var chest := TreasureScreen.new()
	add_child_autofree(chest)
	chest.setup(run)
	assert_eq(_main.call("_make_choice", chest, {"do": "open", "rotten": false}), "open plain")
	assert_true(chest.is_open())
	assert_eq(_main.call("_make_choice", chest, {"do": "open", "rotten": true}), "", "one chest only")
	var loot := LootScreen.new()
	add_child_autofree(loot)
	loot.setup(run.loot_choices(run.at), "", run)
	# The friend whose turn it is plays the third hero (DESIGN.md 8.24): only they may get the spoil.
	loot.give_heroes = func(_device: int) -> Array[int]: return [2] as Array[int]
	var taken: Array = []
	loot.chosen.connect(func(item: GearData, hero: int) -> void: taken.append([item, hero]))
	assert_eq(_main.call("_make_choice", loot, {"do": "take", "index": 0}), "", "a spoil needs its hero")
	assert_eq(_main.call("_make_choice", loot, {"do": "take", "index": 0, "hero": 0}), "",
			"not a hero of the player whose turn it is")
	assert_eq(_main.call("_make_choice", loot, {"do": "take", "index": 0, "hero": 2}), "take 0")
	assert_eq(_main.call("_make_choice", loot, {"do": "take", "index": 0, "hero": 2}), "", "one spoil")
	assert_eq(taken, [[run.loot_choices(run.at)[0], 2]])


func test_the_host_takes_the_rotten_chests_relic_for_a_friend() -> void:
	var run := _run()
	run.go(run.choices()[0])
	var chest := TreasureScreen.new()
	add_child_autofree(chest)
	chest.setup(run)
	chest.give_heroes = func(_device: int) -> Array[int]: return [1] as Array[int]
	assert_eq(_main.call("_make_choice", chest, {"do": "open", "rotten": true}), "open rotten")
	assert_true(chest.relic_waiting(), "a pick of Relics waits")
	assert_false(_main.call("_can_leave", chest), "the way on shows once one is taken")
	var offered := chest.relic_choices()
	assert_eq(offered.size(), run.relic_choice_count())
	assert_eq(_main.call("_make_choice", chest, {"do": "relic", "index": 1, "hero": 0}), "", "not their hero")
	assert_eq(_main.call("_make_choice", chest, {"do": "relic", "index": 1, "hero": 1}), "relic 1")
	assert_eq(run.relics_of(1), [offered[1]] as Array[GearData], "the friend's hero has it")
	assert_false(chest.relic_waiting())
	assert_eq(_main.call("_make_choice", chest, {"do": "relic", "index": 0, "hero": 1}), "", "one Relic only")
	for item: GearData in offered:
		if item != offered[1]:
			assert_false(run.owns(item), "the others are gone")


# --- a friend's own screen asks the host --------------------------------------------------------

func test_a_friends_screen_on_their_turn_asks_and_changes_nothing() -> void:
	var run := _run()
	run.gold = 500
	var asked: Array[Dictionary] = []
	var screen := EventScreen.new()
	screen.remote = true
	screen.asks = func(choice: Dictionary) -> void: asked.append(choice)
	add_child_autofree(screen)
	screen.setup(run, load("%s/gamblers_bones.tres" % EVENTS_DIR) as EventData)
	assert_true(bool(screen.rows()[0].enabled), "their turn: the cards are lit")
	var gold := run.gold
	assert_true(screen.choose(0))
	assert_eq(asked, [{"do": "choose", "index": 0, "pick": -1, "hero": -1}] as Array[Dictionary], "no Relic: no hero")
	assert_eq(run.gold, gold, "the host makes it")
	assert_false(screen.is_decided())


func test_a_watching_screen_is_greyed_until_its_turn_comes() -> void:
	var run := _run()
	var rest := RestScreen.new()
	rest.watching = true
	add_child_autofree(rest)
	rest.setup(run)
	for row: Dictionary in rest.menu().items:
		assert_false(bool(row.enabled), "another player's turn")
	rest.set_turn(false)
	assert_true(bool(rest.menu().items[0].enabled), "the turn passed here")
	var remote := RestScreen.new()
	remote.remote = true
	add_child_autofree(remote)
	remote.setup(run)
	assert_true(remote.is_greyed(), "a friend watching")
	remote.set_turn(false, func(_c: Dictionary) -> void: pass)
	assert_false(remote.is_greyed(), "a friend whose turn it is")


func test_a_friends_map_and_shop_ask_the_host() -> void:
	var run := _run()
	var asked: Array[Dictionary] = []
	var map := MapScreen.new()
	map.asks = func(choice: Dictionary) -> void: asked.append(choice)
	add_child_autofree(map)
	map.setup(run, null, false)
	var stops: Array[int] = []
	map.stop_chosen.connect(func(id: int) -> void: stops.append(id))
	map.choose(map.choices()[0])
	assert_eq(asked, [{"do": "stop", "id": map.choices()[0]}] as Array[Dictionary])
	assert_true(stops.is_empty(), "the host goes there")
	var shop_run := _run()
	shop_run.go(shop_run.choices()[0])
	shop_run.gold = 999
	var shop := ShopScreen.new()
	shop.remote = true
	shop.asks = func(choice: Dictionary) -> void: asked.append(choice)
	add_child_autofree(shop)
	shop.setup(shop_run, shop_run.shop_gear(shop_run.at))
	var gold := shop_run.gold
	assert_true(shop.buy(0))
	assert_eq(asked.back(), {"do": "buy", "index": 0, "hero": -1}, "an item: no hero")
	assert_eq(shop_run.gold, gold)
	shop.leave()
	assert_eq(asked.back(), {"do": "leave"})


# --- a find with no room on a friend's turn ------------------------------------------------------

func test_a_find_with_no_room_is_handed_to_the_friend_whose_turn_it_is() -> void:
	var run := _run()
	_fill(run, "salve")
	var screen := _event_screen(run, "gamblers_bones")
	var handed: Array[Node] = []
	screen.hand_off = func(from: Node) -> void: handed.append(from)
	screen.give([_item(run, "salve")])
	assert_eq(handed, [screen] as Array[Node])
	assert_null(screen.overlay(), "no backpack opens on the host")
	assert_true(screen.is_settling(), "it waits for them")
	assert_eq(String(screen.owed().get("note", "")), "No room")
	assert_false(screen.settle_owed({"op": BagTab.HAND_OUT, "to": "pocket", "pocket": 0}), "that pocket is full")
	assert_true(screen.is_settling())
	var count := run.backpack.entries.size()
	assert_true(screen.settle_owed({"op": BagTab.HAND_OUT, "to": "leave"}))
	assert_false(screen.is_settling())
	assert_eq(run.backpack.entries.size(), count, "left behind")


## An event's choice is saved the moment it is made (its risk rolled), before its finds are in the
## backpack: while one is still being placed, here or by a friend, Save & Quit waits (it would keep the
## choice without the find, and Continue shows only the result).
func test_save_and_quit_waits_while_a_find_is_being_placed() -> void:
	var run := _run()
	_fill(run, "salve")
	var screen := _event_screen(run, "gamblers_bones")
	assert_false(_main.call("_gift_in_hand", screen), "nothing handed out")
	screen.hand_off = func(_from: Node) -> void: pass
	screen.give([_item(run, "salve")])
	assert_true(_main.call("_gift_in_hand", screen), "handed to a friend to place")
	screen.hand_off = Callable()
	screen.take_back_owed()
	assert_true(_main.call("_gift_in_hand", screen), "in the host's own hands")
	assert_false(_main.call("_gift_in_hand", null), "no screen")
	var quit := _body("func _on_pause_save_quit(")
	assert_lt(quit.find("_gift_in_hand(_screen)"), quit.find("_save_quit_online()"), "checked before anything is saved")
	assert_lt(quit.find("_gift_in_hand(_screen)"), quit.find("_write_checkpoint()"))


func test_the_turn_back_home_opens_the_owed_find_here() -> void:
	var run := _run()
	_fill(run, "salve")
	var screen := _event_screen(run, "gamblers_bones")
	screen.hand_off = func(_from: Node) -> void: pass
	screen.give([_item(run, "salve")])
	screen.hand_off = Callable()
	screen.take_back_owed()
	assert_not_null(screen.overlay(), "the host's own backpack holds it")
	assert_true(screen.owed().is_empty())


func test_the_friend_places_the_handed_find_through_the_host() -> void:
	var run := _run()
	var salve := _item(run, "salve")
	assert_eq(BagTab.place_new(run, salve, {"to": "pocket", "pocket": 0}), BagTab.PLACED)
	assert_eq(BagTab.place_new(run, salve, {"to": "pocket", "pocket": 0}), "", "taken now")
	var uid := run.backpack.uid_at(Vector2i(0, 0))
	var other := _item(run, "bandage") if run.items_by_id().has("bandage") else salve
	assert_eq(BagTab.place_new(run, other, {"to": "swap", "uid": uid, "pocket": 0}), BagTab.PLACED)
	assert_eq(run.backpack.entry(run.backpack.uid_at(Vector2i(0, 0))).item, other)
	assert_eq(BagTab.place_new(run, salve, {"to": "fit"}), BagTab.PLACED)
	assert_eq(BagTab.place_new(run, salve, {"to": "leave"}), BagTab.LEFT)
	assert_eq(BagTab.place_new(run, salve, {"to": "nowhere"}), "")


func _steps(name: String) -> Dictionary:
	return _main.get_script_constant_map()[name] as Dictionary


func test_a_handed_find_waits_for_a_screen_that_can_take_it() -> void:
	var steps := _steps("GiftStep")
	var run := _run()
	run.go(run.choices()[0])
	var shop := ShopScreen.new()
	shop.remote = true
	add_child_autofree(shop)
	shop.setup(run, run.shop_gear(run.at))
	var party := PartyScreen.new()
	party.remote = true
	add_child_autofree(party)
	party.setup(run, "")
	var gift := {"key": "stop:0:1", "gift": 3, "item": "salve"}
	var step := func(turn_key: String, mine: bool, held: int, holding: bool, done: int, screen: Node, busy: bool) -> int:
		return int(_main.call("_gift_step", gift, turn_key, mine, held, holding, done, screen, busy))
	assert_eq(step.call("stop:0:1", true, 0, false, 0, shop, false), steps.HOLD, "the shop is up, nothing open over it")
	assert_eq(step.call("stop:0:1", true, 0, false, 0, party, false), steps.WAIT, "our own party screen: it waits")
	assert_eq(step.call("stop:0:1", true, 0, false, 0, shop, true), steps.WAIT, "a transition: it waits")
	assert_eq(step.call("stop:0:1", false, 0, false, 0, shop, false), steps.DROP, "the turn passed on")
	assert_eq(step.call("map:0:1", true, 0, false, 0, shop, false), steps.DROP, "the party moved on")
	assert_eq(step.call("stop:0:1", true, 0, false, 3, shop, false), steps.DROP, "placed already: a copy")
	shop.hold_gift("Sell", {"icon": &"coin"})
	assert_not_null(shop.overlay())
	assert_eq(step.call("stop:0:1", true, 2, false, 2, shop, false), steps.WAIT, "the Sell backpack is open: it waits")
	assert_eq(step.call("stop:0:1", true, 3, true, 2, shop, false), steps.DROP, "that very find is in hand")


func test_the_host_hands_a_find_again_only_to_a_new_owner() -> void:
	var steps := _steps("OwedStep")
	assert_eq(_main.call("_owed_step", PEER_A, PEER_A), steps.KEEP, "their seat moved up: it stays with them")
	assert_eq(_main.call("_owed_step", PEER_A, PEER_B), steps.HAND, "P2 dropped: P3 places it")
	assert_eq(_main.call("_owed_step", 0, PEER_B), steps.HAND)
	assert_eq(_main.call("_owed_step", PEER_A, HOST), steps.TAKE_BACK, "the host's turn: its own backpack")


func test_a_placing_counts_only_for_the_find_handed_out_now() -> void:
	var run := _run()
	_fill(run, "salve")
	var screen := _event_screen(run, "gamblers_bones")
	screen.hand_off = func(_from: Node) -> void: pass
	screen.give([_item(run, "salve")])
	var main := _host_on(screen, run, "stop:0:1")
	main.set("_gift_no", 2)
	main.set("_gift_peer", PEER_A)
	var leave := {"op": BagTab.HAND_OUT, "to": "leave"}
	main.call("_on_hand_out", PEER_A, _main.call("_numbered_placing", leave, 1))
	assert_true(screen.is_settling(), "meant for an earlier hand-out")
	main.call("_on_hand_out", PEER_B, _main.call("_numbered_placing", leave, 2))
	assert_true(screen.is_settling(), "not the machine holding it")
	main.call("_on_hand_out", PEER_A, leave)
	assert_true(screen.is_settling(), "no number")
	main.call("_on_hand_out", PEER_A, _main.call("_numbered_placing", leave, 2))
	assert_false(screen.is_settling(), "placed (left behind)")
	assert_eq(main.get("_gift_peer"), 0, "nobody holds it now")
	assert_eq(_main.call("_numbered_placing", leave, 4), {"op": BagTab.HAND_OUT, "to": "leave", "gift": 4})
	assert_false(_main.call("_placing_counts", PEER_A, {"gift": 2}, PEER_A, 2, PEER_B), "the turn moved on")


func test_a_handed_find_is_kept_until_it_can_be_placed_and_sent_again_on_a_choice() -> void:
	var friend := _body("func _client_gift(")
	assert_true(friend.contains("_pending_gift = "), "kept, never thrown away")
	assert_false(friend.contains("hold_gift("), "opened only once a screen can take it")
	assert_true(_body("func _process(").contains("_offer_pending_gift()"), "tried again while it waits")
	assert_true(_body("func _offer_pending_gift(").contains("hold_gift("))
	assert_true(_body("func _send_bag_op(").contains("_numbered_placing("), "a placing carries the find's number")
	var host := _body("func _on_friend_choice(")
	assert_lt(host.find("_send_gift("), host.find("_make_choice("), "their find comes first, sent again")
	var turn := _body("func _apply_turn_to_screen(")
	assert_true(turn.contains("_owed_step("), "handed again only to a new owner")


func test_a_friends_backpack_asks_the_host_to_place_a_handed_find() -> void:
	var run := _run()
	_fill(run, "salve")
	var count := run.backpack.entries.size()
	var party := PartyScreen.new()
	party.remote = true
	add_child_autofree(party)
	party.setup(run, "No room", {"item": _item(run, "salve")})
	var ops: Array[Dictionary] = []
	party.op_requested.connect(func(op: Dictionary) -> void: ops.append(op))
	party.auto_settle()
	assert_eq(ops, [{"op": BagTab.HAND_OUT, "to": "fit"}] as Array[Dictionary])
	assert_eq(run.backpack.entries.size(), count, "the host's state comes back")


# --- the switch and the wiring ------------------------------------------------------------------

func test_take_turns_is_on_unless_turned_off() -> void:
	assert_true(PlayerSettings.take_turns())
	PlayerSettings.set_take_turns(false)
	assert_false(PlayerSettings.take_turns())
	assert_true(SettingsScreen.section_rows(SettingsScreen.Section.GAME, false).has("take_turns"))
	assert_true(_body("func _begin_choice(").contains("PlayerSettings.take_turns()"), "read for each new choice")


func test_every_choice_screen_takes_its_turn_before_it_is_built() -> void:
	for header: String in ["func _show_map(", "func _show_rest(", "func _show_shop(", "func _show_event(",
			"func _show_treasure(", "func _show_loot("]:
		var body := _body(header)
		assert_true(body.contains("_begin_choice("), header)
		assert_true(body.find("_wire_turn(") < body.find(".setup("), "%s: wired before setup" % header)
		assert_true(body.contains("_autoplay_choice("), "%s: its bot plays only its turn" % header)


func test_input_is_the_turns_owners_and_drops_pass_the_turn() -> void:
	assert_true(_body("func _input(").contains("not _my_turn()"))
	assert_true(_body("func _on_net_peer_away(").contains("_pass_turn()"))
	assert_true(_body("func _on_net_peer_left(").contains("_pass_turn()"))
	var host := _body("func _on_net_message(")
	assert_true(host.contains("\"choice\""))
	assert_true(host.contains("BagTab.HAND_OUT"))
	assert_true(_body("func _client_message(").contains("\"turn\""))
	assert_true(_body("func _send_screen(").contains("\"turn\""), "choice screens carry the turn")
	assert_true(_body("func _build_watch_layer(").contains("&\"person\""), "the chip: an icon and a tag")
	assert_eq(_main.call("_choice_word", {"do": "stop", "id": 4}), "stop id=4")
