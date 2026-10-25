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
	assert_eq(NetSession.PROTOCOL, 6, "choices in turns (card #314): an older build must not join")


func test_modes_are_what_the_states_say() -> void:
	assert_eq(_const("MODE_RUN"), RunState.begin(_rush.run, _tuning, 7).mode())
	assert_eq(_const("MODE_RUSH"), RushState.begin_rush(_rush, _tuning, 7).mode())


func test_run_start_says_which_game() -> void:
	var roster := _online_two()
	var rush := RushState.begin_rush(_rush, _tuning, 7)
	var start := _sent(_main.call("_run_start_message", rush, roster, false) as Dictionary)
	var keys := start.keys()
	keys.sort()
	assert_eq(keys, ["late", "mode", "oath", "records", "roster", "seed"])
	assert_eq(start.mode, "rush")
	assert_eq(typeof(start.seed), TYPE_INT, "ints stay ints over the RPC path")
	assert_eq(int(start.seed), 7)
	assert_eq(int(start.oath), 0, "no Oaths in a Rush")
	assert_false(bool(start.late))
	assert_false(bool(start.records), "no word from the host: no record")
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
	assert_string_contains(_body("func _input("),
			"(_screen is RushRewardScreen and (event.is_action(&\"party_menu\") or event.is_action(&\"menu_confirm\")))")
	assert_string_contains(_body("func _rebuild_watched_screen("), "_refresh_rush_screen()")
	assert_string_contains(_body("func _refresh_rush_screen("), "(_screen as RushRewardScreen).refresh()")
	assert_string_contains(_body("func _new_rush("),
			"Net.broadcast(\"run_start\", _run_start_message(rush, _players, false, _rush_records_ok()))")
	assert_string_contains(_body("func _on_online_started("), "_new_rush if _mode == MODE_RUSH else _new_run")
	assert_string_contains(_body("func _ready("), "_mode = MODE_RUSH if _options.rush else MODE_RUN")


## Only the host gives the Rush up, for everyone: RUSH OVER shows on every machine.
func test_the_host_gives_up_for_everyone() -> void:
	assert_string_contains(_body("func _open_pause("), "Net.is_host() and _gives_up_rush()")
	assert_string_contains(_body("func _gives_up_rush("), "_gives_up_rush_now(_run is RushState, Net.is_online(), Net.is_host()")
	assert_string_contains(_body("func _on_pause_leave("), "if _gives_up_rush():")
	var main: Node = _main.new()
	autofree(main)
	main.set("_run", RushState.begin_rush(_rush, _tuning, 7))
	assert_true(main.call("_gives_up_rush"), "alone: the pause gives the Rush up")
	main.set("_run", RunState.begin(_rush.run, _tuning, 7))
	assert_false(main.call("_gives_up_rush"), "a run abandons, as before")


## Online the pause opens over a fight that has ended (offline it never does). Once a lost fight has
## decided the Rush, its end screen still up, the host's row ends the game instead of giving up, so
## the loss never turns into a Rush given up (RUSH OVER keeps its killer row and rush_over result).
## A Give up already asked before the loss lands on the fight's own end.
func test_a_lost_fight_is_never_given_up() -> void:
	var cases := [
		# [rush, online, host, over, decided, gives up, what]
		[true, false, false, false, false, true, "alone, a Rush going on"],
		[true, false, false, false, true, true, "alone (the pause never opens over an ended fight)"],
		[true, true, true, false, false, true, "the host, the Rush going on"],
		[true, true, true, false, true, false, "the host on a lost fight's end screen"],
		[true, true, true, true, true, false, "the host after RUSH OVER"],
		[true, true, false, false, false, false, "a friend only leaves"],
		[false, false, false, false, false, false, "a run"],
		[false, true, true, false, false, false, "an online run"],
	]
	for c: Array in cases:
		assert_eq(_main.call("_gives_up_rush_now", c[0], c[1], c[2], c[3], c[4]), c[5], String(c[6]))
	var gives := _body("func _gives_up_rush(")
	assert_string_contains(gives, "_run != null and _decided_run == _run")
	var give_up := _body("func _give_up_rush(")
	var routed := give_up.find("_on_rush_fight_over(_combat.fight_result())")
	assert_gt(routed, -1, "a Give up asked before the loss takes the fight's own end")
	assert_string_contains(give_up, "if _decided_run == rush and not rush.is_over() and _combat != null:")
	assert_lt(routed, give_up.find("rush.give_up()"), "before anything gives the Rush up")
	var controller := load("res://scripts/combat/presentation/combat_controller.gd") as GDScript
	var methods: Array = controller.get_script_method_list().map(func(m: Dictionary) -> String: return String(m.name))
	assert_has(methods, "fight_result", "the fight says how it ended")
	# The RunState rule the guard leans on: a loss only gets its result when the fight's end is taken.
	var r := RushState.begin_rush(_rush, _tuning, 7)
	r.next_fight()
	assert_true(r.decides_run(RunState.DEFEAT))
	assert_false(r.is_over(), "decided, but no result yet: Give up would have overwritten it")
	var down: Array[int] = []
	for slot: int in r.party_size():
		down.append(0)
	r.finish_fight(RunState.DEFEAT, down, r.encounter_now(), {})
	assert_eq(r.result, RunState.DEFEAT)
	r.give_up()
	assert_eq(r.result, RunState.DEFEAT, "after the fight's end the loss stays")


## The online host's words in a Fight Rush: Give up while it goes on, End the game ("Back to the main
## menu for everyone.", nothing is lost) once it is decided or over; a friend's notice when the host
## leaves after RUSH OVER, and the drop-in's Join line, which comes before the game is known.
func test_an_online_rush_speaks_of_the_rush() -> void:
	assert_eq(_const("RUSH_END_ONLINE"), "Back to the main menu for everyone.")
	var pause := _body("func _open_pause(")
	var ended := pause.find("elif Net.is_host() and _run is RushState:")
	assert_gt(ended, pause.find("elif Net.is_host() and _gives_up_rush():"), "after the Give up row")
	assert_lt(ended, pause.find("_pause.setup(\"End the game\", \"The run ends for everyone.\")"), "before the run's row")
	assert_string_contains(pause, "_pause.setup(\"End the game\", RUSH_END_ONLINE)")
	assert_string_contains(_body("func _on_pause_leave("), "\"\" if _run is RushState else \"The run is lost.\"")
	assert_eq(_main.call("_host_gone_notice", true, true), "The Rush is over.")
	assert_eq(_main.call("_host_gone_notice", true, false), "The run is over.", "a run as before")
	assert_eq(_main.call("_host_gone_notice", false, true), "The host left the game.")
	assert_eq(_main.call("_host_gone_notice", false, false), "The host left the game.")
	assert_string_contains(_body("func _on_net_host_lost("), "_host_gone_notice(_client_done, _run is RushState)")
	var joining := String(_const("JOINING_STATUS"))
	assert_false(joining.to_lower().contains("run") or joining.to_lower().contains("rush"), "names neither game")
	assert_string_contains(_body("func _on_net_peer_joined("), "show_status(JOINING_STATUS)")
	assert_false(FileAccess.get_file_as_string(MAIN_PATH).contains("Joining the run"))


## A friend's change to the shared party reaches the host, whose Fight Rush screen redraws (the Party
## card's points), as the friends' copies do with each new state. Not while a gift is handed out.
func test_a_friends_change_redraws_the_hosts_rush_screen() -> void:
	var r := _won(3)
	var train := -1
	for i: int in r.offer.size():
		if String(r.offer[i].kind) == RushState.CARD_POINT:
			train = i
	assert_gt(train, -1)
	var main: Node = _main.new()
	autofree(main)
	main.set("_run", r)
	var screen := RushRewardScreen.new()
	add_child_autofree(screen)
	screen.setup(r)
	assert_true(screen.take(train))
	assert_false(screen.is_picking(), "the ready phase")
	main.set("_screen", screen)
	var chips := func() -> Array:
		return (screen.menu().items[RushRewardScreen.READY_PARTY].get("chips", []) as Array).map(
				func(chip: Dictionary) -> String: return String(chip.get("text", "")))
	var before := r.unspent_points()
	assert_eq(chips.call(), [RushRewardScreen.points_text(before)])
	var spent: Array = (r.attributes[0] as Array).duplicate()
	var free := r.free_points(0)
	assert_gt(free, 0)
	spent[0] = int(spent[0]) + free
	var op := _sent({"op": {"op": "attributes", "slot": 0, "values": spent}}).op as Dictionary
	assert_true(main.call("_apply_bag_op", op), "the friend's spend is made")
	assert_eq(r.unspent_points(), before - free)
	var after: Array = [] if r.unspent_points() == 0 else [RushRewardScreen.points_text(r.unspent_points())]
	assert_eq(chips.call(), after, "the host's Party card shows what is left")
	assert_false(main.call("_apply_bag_op", {"op": "attributes", "slot": 0, "values": [99, 0, 0, 0, 0]}),
			"a change that cannot be made is refused")
	var on_message := _body("func _on_net_message(")
	var bag := on_message.substr(on_message.find("\"bag\":"), on_message.find("\"seated_ready\":") - on_message.find("\"bag\":"))
	assert_string_contains(bag, "_apply_bag_op(op)", "every other bag op is a party change (a hand_out is a find in hand, card #314)")
	assert_string_contains(_body("func _refresh_rush_screen("), ".is_settling()")


# --- records -------------------------------------------------------------------------------------

## D20: a friend who got into the Rush after it started writes no record for it.
func test_a_late_friend_keeps_no_record() -> void:
	var options := CombatOptions.from_args(PackedStringArray(["--rush"]), _tuning)
	var on_time: Dictionary = _main.call("_rush_records_flags", options, _tuning, true, false)
	var late: Dictionary = _main.call("_rush_records_flags", options, _tuning, true, true)
	assert_true(RushRecords.allowed(on_time), "there from the start: records as offline")
	assert_false(RushRecords.allowed(late), "joined late: no record")
	assert_true(late.late)
	assert_string_contains(_body("func _rush_records_ok("), "client and (_rush_late or Net.joined_mid_run)")
	var start := _body("func _client_message(")
	assert_true(start.contains("_rush_late = _late_after_start(late, _rush_late, same_game)"),
			"late from the catch-up, kept through a rejoin of the same Rush")
	assert_lt(start.find("var late := _late_baseline("), start.find("_rush_late = _late_after_start("))
	assert_string_contains(_body("func _forget_own_start("), "_rush_late = false")
	assert_true(_body("func _note_rush_record(").contains("if not Net.is_client():"), "the host counts the players")


## D9 online: a friend's machine cannot see the host's switches, so the host sends its own verdict
## with run_start (and with every catch-up); a Rush the host started as a bot or with dev switches
## (a head start, pretend Relics, a cap, a seed) keeps no record on any friend's machine. The host's
## head start, which comes in its state, keeps the record out there too.
func test_a_hosts_dev_rush_keeps_no_record_on_friends_machines() -> void:
	var options := CombatOptions.from_args(PackedStringArray(["--rush"]), _tuning)
	assert_true(RushRecords.allowed(_main.call("_rush_records_flags", options, _tuning, true, false, true, 1)),
			"a clean friend in a clean host's Rush: records as offline")
	assert_false(RushRecords.allowed(_main.call("_rush_records_flags", options, _tuning, true, false, false, 1)),
			"the host's Rush is a bot or dev one: no record")
	assert_false(RushRecords.allowed(_main.call("_rush_records_flags", options, _tuning, true, false, true, 40)),
			"the host's head start (from its state): no record")
	# What the host sends: its verdict, through the RPC path, at the start and with a catch-up.
	var rush := RushState.begin_rush(_rush, _tuning, 7)
	assert_true(bool(_sent(_main.call("_run_start_message", rush, _online_two(), false, true) as Dictionary).records))
	assert_false(bool(_sent(_main.call("_run_start_message", rush, _online_two(), false, false) as Dictionary).records))
	var caught: Array[Dictionary] = _main.call("_catch_up_messages", rush, _online_two(), false, {"name": "rush_reward"},
			{}, false, true)
	assert_true(bool(_sent(caught[0].payload as Dictionary).records), "a catch-up carries the host's verdict")
	var host_dev := CombatOptions.from_args(PackedStringArray(["--rush", "--rush-start=40", "--relics=all"]), _tuning)
	assert_false(RushRecords.allowed(_main.call("_rush_records_flags", host_dev, _tuning, true)),
			"the host with dev switches says no")
	# Where each machine reads it.
	var ok := _body("func _rush_records_ok(")
	assert_string_contains(ok, "_rush_host_clean or not client")
	assert_string_contains(ok, "rush.start_fight if rush != null else 1")
	assert_string_contains(_body("func _catch_up("), "var records := _run is RushState and _rush_records_ok()")
	assert_string_contains(_body("func _client_message("), "_rush_host_clean = typeof(p.get(\"records\")) == TYPE_BOOL and bool(p.records)")
	var start := _body("func _client_message(")
	assert_lt(start.find("_rush_host_clean = "), start.find("_begin_rush_records()"), "known before the records are read")
	assert_string_contains(_body("func _forget_own_start("), "_rush_host_clean = false")
	# A Main alone (host or offline) judges its own Rush, head start included.
	var main: Node = _main.new()
	autofree(main)
	main.set("_options", options)
	main.set("_tuning", _tuning)
	main.set("_run", RushState.begin_rush(_rush, _tuning, 7))
	assert_true(main.call("_rush_records_ok"), "a plain Rush")
	main.set("_run", RushState.begin_rush(_rush, _tuning, 7, null, 40))
	assert_false(main.call("_rush_records_ok"), "a Rush that started at fight 40")


# --- getting in mid-Rush: drop-in, rejoin, a crashed friend's seat (h2) --------------------------

## The host's Rush `r` after its picks, on to the next fight (the state the fight's screen carries).
static func _picked_and_on(r: RushState) -> RushState:
	while r.picking():
		var got := r.take_card(r._bot_card())
		if got.give is GearData:
			r.add_relic(got.give as GearData)
		elif got.give is ItemData:
			r.add_item(got.give as ItemData)
		r.next_offer()
	r.next_fight()
	return r


## What a friend's machine makes of the catch-up messages: the game run_start builds, then each
## screen's state applied in order (as the client's pump does). Null when run_start builds nothing.
func _friend_after(messages: Array[Dictionary]) -> RunState:
	var start := _sent(messages[0].payload as Dictionary)
	var game: RunState = _main.call("_client_game", _main.call("_message_mode", start), _rush.run, _rush, _tuning,
			int(start.seed), int(start.oath))
	if game == null:
		return null
	for message: Dictionary in messages.slice(1):
		var screen := _sent(message.payload as Dictionary)
		assert_true(game.apply_dict(screen.run as Dictionary), "%s fits the friend's game" % screen.name)
	return game


## A friend who drops into a Rush fight (or comes back to it with their seat's token) gets run_start
## for a Rush, the Rush screen the fight began from, then the fight itself as a resume, every screen
## with the whole state: their machine builds the host's fight, never the next one.
func test_a_friend_who_gets_in_mid_fight_gets_the_hosts_rush_fight() -> void:
	var host := _picked_and_on(_won(5))
	host.note_players(2)
	var place := {"name": "rush_reward"}
	var fight := {"name": "rush_fight", "seed": 321}
	var messages: Array[Dictionary] = _main.call("_catch_up_messages", host, _online_two(), true, place, fight, true)
	var kinds: Array[String] = []
	for message: Dictionary in messages:
		kinds.append(String(message.kind))
	assert_eq(kinds, ["run_start", "screen", "screen"] as Array[String])
	var start := messages[0].payload as Dictionary
	assert_eq(start.mode, "rush", "the friend builds a Rush")
	assert_true(bool(start.late), "a drop-in's catch-up: no record for this Rush (D20)")
	var shown := messages[1].payload as Dictionary
	assert_eq(shown.name, "rush_reward")
	assert_has(_const("WATCHED_SCREENS") as Array, shown.name)
	var in_fight := _sent(messages[2].payload as Dictionary)
	assert_eq(in_fight.name, "rush_fight")
	assert_has(_const("NET_FIGHT_SCREENS") as Array, in_fight.name)
	assert_eq(int(in_fight.seed), 321, "the host's fight seed")
	assert_true(bool(in_fight.rejoin), "built on the host: the fight comes as it stands (a resume)")
	assert_false(place.has("run") or fight.has("run"), "the kept screens are not changed")
	var friend := _friend_after(messages) as RushState
	assert_not_null(friend, "a Rush on the friend's machine")
	if friend == null:
		return
	assert_eq(friend.to_dict(), host.to_dict(), "the same Rush as the host's")
	assert_eq(friend.fight, 6)
	assert_eq(friend.encounter_now(), host.encounter_now(), "the same fight")
	assert_eq(friend.weather_now(), host.weather_now())
	assert_eq(friend.most_players, 2, "the most players seen comes from the host")
	var rejoin: Array[Dictionary] = _main.call("_catch_up_messages", host, _online_two(), false, place, fight, false)
	assert_false(bool((rejoin[0].payload as Dictionary).late), "a token rejoin is on time")
	assert_false(bool((rejoin[2].payload as Dictionary).rejoin), "a fight announced, not built yet: it starts there")


## On the Rush screen there is no fight to send: the friend watches the host's picks, same cards.
func test_a_friend_who_gets_in_on_the_rush_screen_watches_the_picks() -> void:
	var host := _won(3)
	assert_true(host.picking(), "the host is choosing")
	var messages: Array[Dictionary] = _main.call("_catch_up_messages", host, _online_two(), true,
			{"name": "rush_reward"}, {}, false)
	assert_eq(messages.size(), 2, "run_start and the Rush screen")
	assert_eq((messages[1].payload as Dictionary).name, "rush_reward")
	var friend := _friend_after(messages) as RushState
	assert_not_null(friend)
	if friend == null:
		return
	assert_true(friend.picking())
	assert_eq(friend.offer, host.offer, "the same cards")
	assert_eq(friend.picks_left, host.picks_left)
	# The Rush is over (given up or lost) while a seat comes back: RUSH OVER shows there.
	host.give_up()
	var over: Array[Dictionary] = _main.call("_catch_up_messages", host, _online_two(), false, {"name": "rush_end"}, {}, false)
	var ended := _friend_after(over) as RushState
	assert_not_null(ended)
	if ended != null:
		assert_true(ended.is_over())
		assert_eq(ended.result, host.result)
		assert_eq(ended.reached(), host.reached(), "the same fight reached")


## Who gets in late (default D20, no record): a drop-in's catch-up says so, a friend whose game
## crashed comes back late too (as a newcomer, or by the seat file's token: _late_baseline), a token
## rejoin of the same Rush keeps what it was, a new Rush clears it.
func test_late_follows_the_friend_through_a_rejoin_of_the_same_rush() -> void:
	var cases := [
		# [said late, was late, same game, late now, what]
		[false, false, false, false, "there from the start"],
		[true, false, false, true, "dropped in"],
		[true, false, true, true, "a crashed friend's machine starting over in its old seat"],
		[false, true, true, true, "dropped in, then back with the seat's token"],
		[false, false, true, false, "there from the start, back with the token"],
		[false, true, false, false, "late last Rush, on time in this one"],
	]
	for c: Array in cases:
		assert_eq(_main.call("_late_after_start", c[0], c[1], c[2]), c[3], String(c[4]))
	assert_string_contains(_body("func _client_message("), "_rush_late = _late_after_start(late, _rush_late, same_game)")
	assert_string_contains(_body("func _on_net_peer_rejoined("), "_catch_up(new_peer, false)")
	assert_string_contains(_body("func _seat_newcomer("), "_catch_up(peer, true)")
	assert_string_contains(_body("func _catch_up("),
			"_catch_up_messages(_run, _players, late, _net_place, _net_fight, mid_fight, records)")
	# The record baseline is read once per Rush: a seat taken back keeps it (the record written before
	# the drop must not become the one to beat).
	assert_string_contains(_body("func _client_message("), "if _run is RushState and not same_game:")


## The host lets friends into a Rush that goes on, up to a free seat (an away seat is always its
## player's), and shuts the door once the Rush is decided.
func test_drop_in_follows_the_rush() -> void:
	var main: Node = _main.new()
	autofree(main)
	var rush := _picked_and_on(_won(2))
	main.set("_run", rush)
	var alone := PlayerRoster.online(_rush.run.party.size(), HOST, HOST)
	main.set("_players", alone)
	assert_eq(main.call("_drop_in_refusal", 0), "", "a Rush going on takes a newcomer")
	var full := PlayerRoster.online(_rush.run.party.size(), HOST, HOST)
	full.join_peer(PEER_A)
	full.join_peer(PEER_A + 1)
	main.set("_players", full)
	assert_eq(main.call("_drop_in_refusal", 0), JoinGate.REASON_FULL, "every hero has a player")
	assert_eq(main.call("_drop_in_refusal", PEER_A), "", "an away seat goes to the friend coming back for it")
	main.set("_decided_run", rush)
	assert_eq(main.call("_drop_in_refusal", PEER_A), JoinGate.REASON_CLOSED, "decided: nobody gets in")
	main.set("_decided_run", null)
	rush.give_up()
	assert_eq(main.call("_drop_in_refusal", 0), JoinGate.REASON_CLOSED, "over: nobody gets in")
	assert_string_contains(_body("func _new_rush("), "_set_drop_in(true)")
	assert_string_contains(_body("func _close_decided_rush("), "_set_drop_in(false)")


# --- Again (h2) ----------------------------------------------------------------------------------

## Again after an online Rush: the host's players screen is the Fight Rush one again, with the same
## seats (a friend who dropped in keeps theirs; one still away is let go), and every friend's machine
## follows it there, on time for the next Rush.
func test_again_goes_back_to_the_rush_players_screen_with_the_same_seats() -> void:
	var roster := _online_two()
	var late := roster.join_peer_midrun(PEER_A + 1)
	assert_gt(late, 0, "a friend dropped in")
	roster.set_joining(PEER_A + 1)
	roster.set_back(PEER_A + 1)
	var again := _sent(_main.call("_lobby_message", roster, 0, _const("MODE_RUSH")) as Dictionary)
	assert_eq(_main.call("_message_mode", again), "rush", "the Fight Rush players screen")
	var friend := PlayerRoster.from_dict(again.roster as Dictionary, PEER_A + 1)
	assert_not_null(friend)
	if friend == null:
		return
	assert_true(friend.same_as(roster), "the same seats")
	assert_eq(friend.player_count(), 3)
	assert_eq(friend.heroes_of(late), roster.heroes_of(late), "the friend who dropped in keeps their hero")
	var play_again := _body("func _play_again(")
	var mode_at := play_again.find("_mode = MODE_RUSH if was_rush else MODE_RUN")
	assert_gt(mode_at, -1, "Again is for the same game")
	assert_lt(mode_at, play_again.find("if Net.is_client():"), "on every machine")
	assert_lt(play_again.find("Net.seats.remove(peer)"), play_again.find("_show_host_lobby()"), "a friend still away is let go")
	assert_lt(play_again.find("_show_host_lobby()"), play_again.find("Net.broadcast(\"again\""))
	assert_string_contains(play_again, "_forget_own_start()")
	assert_string_contains(play_again, "_show_rush_lobby()")
	var message := _body("func _client_message(")
	var again_branch := message.substr(message.find("\"again\":"), message.find("\"run_start\":") - message.find("\"again\":"))
	for line: String in ["_forget_own_start()", "Net.joined_mid_run = false", "_mode = again_mode"]:
		assert_string_contains(again_branch, line)
	assert_string_contains(_body("func _forget_own_start("), "_rush_late = false")


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
