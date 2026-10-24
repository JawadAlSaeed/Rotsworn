extends GutTest
## Fight Rush online (DESIGN.md 8.21, card #312): the host plays the Rush exactly as offline and its
## friends follow. Which game it is (a run or a Fight Rush) travels in the "lobby", "again" and
## "run_start" messages; a friend builds the same Rush from run_start and the host's state over the
## RPC path (no head start of its own); the Rush screens are watched and a Rush fight is kept for a
## friend who gets in mid-fight; a friend who got in late writes no record; the players screens of
## an online Rush carry its title and no Oath row. Uses the shipped Rush data; nothing touches user://.

const MAIN_PATH := "res://scenes/main.gd"
const RUSH_PATH := "res://data/rush/fight_rush.tres"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const HOST: int = 1
const PEER_A: int = 1001

var _rush: RushData
var _tuning: Tuning
var _main: GDScript


func before_all() -> void:
	_rush = load(RUSH_PATH) as RushData
	_main = load(MAIN_PATH) as GDScript


func before_each() -> void:
	_tuning = (load(TUNING_PATH) as Tuning).duplicate() as Tuning


## Main's constant `key`.
func _const(key: String) -> Variant:
	return _main.get_script_constant_map().get(key)


## The host and one friend online, a share of the heroes each.
func _online_two() -> PlayerRoster:
	var roster := PlayerRoster.online(_rush.run.party.size(), HOST, HOST)
	roster.join_peer(PEER_A)
	return roster


## What arrives on the other machine: the RPC path turns the message into bytes and back.
static func _sent(message: Dictionary) -> Dictionary:
	return bytes_to_var(var_to_bytes(message)) as Dictionary


## A Rush that started at fight `n` (the fights before replayed by the dev head start) and has just
## won fight `n`, its cards on show.
func _won(n: int) -> RushState:
	var r := RushState.begin_rush(_rush, _tuning, 7, null, n)
	r.next_fight()
	var hp: Array[int] = []
	for slot: int in r.party_size():
		@warning_ignore("integer_division")
		hp.append(r.max_hp(slot) / 2)
	r.finish_fight(RunState.VICTORY, hp, r.encounter_now(), {})
	return r


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


static func _labels_of(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for label: Node in node.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	return texts


# --- the messages --------------------------------------------------------------------------------

func test_the_protocol_moved_on() -> void:
	assert_eq(NetSession.PROTOCOL, 4, "lobby, again and run_start carry the mode: an older build must not join")


func test_modes_are_what_the_states_say() -> void:
	assert_eq(_const("MODE_RUN"), RunState.begin(_rush.run, _tuning, 7).mode())
	assert_eq(_const("MODE_RUSH"), RushState.begin_rush(_rush, _tuning, 7).mode())


func test_run_start_says_which_game() -> void:
	var roster := _online_two()
	var rush := RushState.begin_rush(_rush, _tuning, 7)
	var start := _sent(_main.call("_run_start_message", rush, roster, false) as Dictionary)
	var keys := start.keys()
	keys.sort()
	assert_eq(keys, ["late", "mode", "oath", "roster", "seed"])
	assert_eq(start.mode, "rush")
	assert_eq(typeof(start.seed), TYPE_INT, "ints stay ints over the RPC path")
	assert_eq(int(start.seed), 7)
	assert_eq(int(start.oath), 0, "no Oaths in a Rush")
	assert_false(bool(start.late))
	assert_eq(start.roster, roster.to_dict())
	var run := RunState.begin(_rush.run, _tuning, 9, 1)
	var late := _sent(_main.call("_run_start_message", run, roster, true) as Dictionary)
	assert_eq(late.mode, "run")
	assert_eq(int(late.seed), 9)
	assert_eq(int(late.oath), run.oath)
	assert_true(bool(late.late), "a drop-in's catch-up")


func test_lobby_and_again_say_which_game() -> void:
	var roster := _online_two()
	var lobby := _sent(_main.call("_lobby_message", roster, 0, "rush") as Dictionary)
	var keys := lobby.keys()
	keys.sort()
	assert_eq(keys, ["mode", "oath", "roster"])
	assert_eq(lobby.mode, "rush")
	assert_eq(lobby.roster, roster.to_dict())
	assert_eq(String((_main.call("_lobby_message", roster, 2, "run") as Dictionary).mode), "run")
	for header: String in ["func _on_online_roster_changed(", "func _on_online_oath_changed("]:
		assert_true(_body(header).contains("_lobby_message("), "%s sends the mode" % header)
	assert_string_contains(_body("func _play_again("), "Net.broadcast(\"again\", _lobby_message(")


func test_only_a_rush_message_means_a_rush() -> void:
	assert_eq(_main.call("_message_mode", {}), "run", "a message from before the Fight Rush")
	assert_eq(_main.call("_message_mode", {"mode": "rush"}), "rush")
	assert_eq(_main.call("_message_mode", {"mode": "run"}), "run")
	assert_eq(_main.call("_message_mode", {"mode": 5}), "run")
	assert_eq(_main.call("_message_mode", {"mode": "RUSH"}), "run")


# --- a friend follows the host's Rush ------------------------------------------------------------

## run_start builds the Rush from the host's seed (no head start here); each screen's state then
## makes it the host's, through the bytes the RPC path sends: the same fight, look, weather, cards.
func test_a_friend_builds_the_hosts_rush() -> void:
	var host := _won(5)
	host.note_players(2)
	var start := _sent(_main.call("_run_start_message", host, _online_two(), false) as Dictionary)
	var game: RunState = _main.call("_client_game", _main.call("_message_mode", start), _rush.run, _rush, _tuning,
			int(start.seed), int(start.oath))
	assert_true(game is RushState, "a Rush starts on the friend's machine")
	var friend := game as RushState
	if friend == null:
		return
	assert_eq(friend.fight, 0, "the friend replays nothing: the host's state brings it")
	var screen := _sent({"name": "rush_reward", "run": host.to_dict()})
	assert_true(friend.apply_dict(screen.run as Dictionary))
	assert_eq(friend.to_dict(), host.to_dict(), "the same Rush on both machines")
	assert_eq(friend.start_fight, 5)
	assert_eq(friend.offer, host.offer, "the same cards")
	assert_eq(friend.most_players, 2, "the most players seen comes from the host")
	assert_eq(friend.open_relic_slots(), host.open_relic_slots())
	# The host takes its picks and goes on: the next fight's state alone builds the same fight there.
	while host.picking():
		var got := host.take_card(host._bot_card())
		if got.give is GearData:
			host.add_relic(got.give as GearData)
		elif got.give is ItemData:
			host.add_item(got.give as ItemData)
		host.next_offer()
	host.next_fight()
	var fight := _sent({"name": "rush_fight", "seed": 123, "run": host.to_dict()})
	assert_true(friend.apply_dict(fight.run as Dictionary))
	assert_eq(friend.fight, 6)
	assert_eq(friend.encounter_now(), host.encounter_now(), "the same encounter")
	assert_eq(friend.look_now(), host.look_now(), "the same place")
	assert_eq(friend.weather_now(), host.weather_now(), "the same weather")
	assert_eq(friend.fight_numbers(friend.encounter_now()), host.fight_numbers(host.encounter_now()),
			"the same enemy numbers")


func test_each_message_builds_only_its_own_game() -> void:
	var run: RunState = _main.call("_client_game", "run", _rush.run, _rush, _tuning, 7, 0)
	assert_false(run is RushState, "a run's run_start builds a run")
	var rush := RushState.begin_rush(_rush, _tuning, 7)
	assert_false(run.apply_dict(rush.to_dict()), "a Rush's state never fits a run")
	assert_false(rush.apply_dict(run.to_dict()), "nor a run's a Rush")
	assert_null(_main.call("_client_game", "rush", _rush.run, null, _tuning, 7, 0), "no Rush data: nothing to build")
	assert_null(_main.call("_client_game", "run", null, _rush, _tuning, 7, 0), "no run data: nothing to build")
	var source := _body("func _client_message(")
	assert_string_contains(source, "_client_game(_mode, _run_data, _rush_data, _tuning, start_seed")
	assert_string_contains(source, "_autoplay_fail(\"run_state_mismatch\")")


## The Rush screens are watched run screens; a Rush fight is a fight going on (a friend who gets in
## mid-fight is shown it); a friend's party screen closes back to the Rush screen.
func test_the_rush_screens_travel() -> void:
	var fights: Array = _const("NET_FIGHT_SCREENS")
	var watched: Array = _const("WATCHED_SCREENS")
	assert_has(fights, "rush_fight")
	assert_has(watched, "rush_reward")
	assert_has(watched, "rush_end")
	assert_does_not_have(watched, "rush_fight", "a fight is built, not watched")
	for screen_name: String in ["map", "rest", "shop", "loot", "party", "run_end", "event", "treasure"]:
		assert_has(watched, screen_name, "the run's screens are still watched")
	var main: Node = _main.new()
	autofree(main)
	main.set("_run", RushState.begin_rush(_rush, _tuning, 7))
	assert_eq((main.call("_watched_screen_builder", {"name": "rush_reward"}) as Callable).get_method(), &"_show_rush_reward")
	assert_eq((main.call("_watched_screen_builder", {"name": "rush_end"}) as Callable).get_method(), &"_show_rush_end")
	var party := main.call("_watched_screen_builder", {"name": "party", "note": ""}) as Callable
	assert_eq(party.get_method(), &"_show_party")
	var back: Variant = party.get_bound_arguments().back()
	assert_true(back is Callable and (back as Callable).get_method() == &"_show_rush_reward",
			"in a Rush the party screen closes back to the Rush screen")
	main.set("_run", RunState.begin(_rush.run, _tuning, 7))
	var run_back: Variant = (main.call("_watched_screen_builder", {"name": "party"}) as Callable).get_bound_arguments().back()
	assert_false((run_back as Callable).is_valid(), "in a run it closes to the map, as before")
	assert_string_contains(_body("func _send_screen("), "NET_FIGHT_SCREENS.has(")
	assert_string_contains(_body("func _client_screen("), "WATCHED_SCREENS.has(")


## A friend builds the fight the host's state names (never rolls the next one), may open the party
## screen from the Rush screen, and sees the Rush screen redrawn as the host takes cards.
func test_a_friend_watches_the_rush_screen_and_builds_its_fights() -> void:
	var screen := _body("func _client_screen(")
	var fight := screen.substr(screen.find("\"rush_fight\":"))
	assert_string_contains(fight, "_begin_rush_fight()")
	assert_false(screen.contains("_start_rush_fight("), "the next fight is the host's to roll")
	assert_string_contains(_body("func _input("), "(_screen is RushRewardScreen and event.is_action(&\"party_menu\"))")
	assert_string_contains(_body("func _rebuild_watched_screen("), "(_screen as RushRewardScreen).refresh()")
	assert_string_contains(_body("func _new_rush("), "Net.broadcast(\"run_start\", _run_start_message(rush, _players, false))")
	assert_string_contains(_body("func _on_online_started("), "_new_rush if _mode == MODE_RUSH else _new_run")
	assert_string_contains(_body("func _ready("), "_mode = MODE_RUSH if _options.rush else MODE_RUN")


## Only the host gives the Rush up, for everyone: RUSH OVER shows on every machine.
func test_the_host_gives_up_for_everyone() -> void:
	assert_string_contains(_body("func _open_pause("), "Net.is_host() and _gives_up_rush()")
	var gives := _body("func _gives_up_rush(")
	assert_string_contains(gives, "not Net.is_online() or (Net.is_host() and not _run.is_over())")
	assert_string_contains(_body("func _on_pause_leave("), "if _gives_up_rush():")


# --- records -------------------------------------------------------------------------------------

## D20: a friend who got into the Rush after it started writes no record for it.
func test_a_late_friend_keeps_no_record() -> void:
	var options := CombatOptions.from_args(PackedStringArray(["--rush"]), _tuning)
	var on_time: Dictionary = _main.call("_rush_records_flags", options, _tuning, true, false)
	var late: Dictionary = _main.call("_rush_records_flags", options, _tuning, true, true)
	assert_true(RushRecords.allowed(on_time), "there from the start: records as offline")
	assert_false(RushRecords.allowed(late), "joined late: no record")
	assert_true(late.late)
	assert_string_contains(_body("func _rush_records_ok("), "Net.is_client() and (_rush_late or Net.joined_mid_run)")
	var start := _body("func _client_message(")
	assert_true(start.contains("_rush_late = bool(p.get(\"late\", false)) or (_rush_late and same_game)"),
			"late from the catch-up, kept through a rejoin of the same Rush")
	assert_string_contains(_body("func _forget_own_start("), "_rush_late = false")
	assert_true(_body("func _note_rush_record(").contains("if not Net.is_client():"), "the host counts the players")


# --- the players screens -------------------------------------------------------------------------

func test_an_online_rush_players_screen_has_its_title_and_no_oaths() -> void:
	var names: Array[String] = []
	var portraits: Array[String] = []
	for c: CharacterData in _rush.run.party:
		names.append(c.display_name)
		portraits.append(c.big_portrait_path)
	var roster := _online_two()
	for is_host: bool in [true, false]:
		var rush_lobby := LobbyScreen.new()
		rush_lobby.hero_portraits = portraits
		rush_lobby.title_text = String(_const("RUSH_TITLE"))
		rush_lobby.setup_online(names, roster, is_host, [] as Array[String], 7777)
		add_child_autofree(rush_lobby)
		assert_true(_labels_of(rush_lobby).has("Fight Rush"), "host %s: titled Fight Rush" % is_host)
		assert_false(_labels_of(rush_lobby).has("Host Online") or _labels_of(rush_lobby).has("Online Players"))
		assert_eq(rush_lobby.call("_oath_row"), -1, "no Oath row")
		var run_lobby := LobbyScreen.new()
		run_lobby.hero_portraits = portraits
		run_lobby.oaths = _rush.run.oaths
		run_lobby.setup_online(names, roster, is_host, [] as Array[String], 7777)
		add_child_autofree(run_lobby)
		assert_true(_labels_of(run_lobby).has("Host Online" if is_host else "Online Players"), "a run's keeps its title")
		assert_gt(int(run_lobby.call("_oath_row")), -1, "and its Oath row")
	assert_string_contains(_body("func _show_host_lobby("), "lobby.title_text = RUSH_TITLE")
	assert_string_contains(_body("func _show_client_lobby("), "lobby.title_text = RUSH_TITLE")
