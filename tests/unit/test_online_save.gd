extends GutTest
## Save & Quit for online runs (card #313, DESIGN.md 8.14, 9.2, 9.3): the host's online slot round
## trips with its seats and never touches the local slot, a save from another game version is refused
## and kept, the slot goes when the run ends or is abandoned, a friend's token takes their own seat
## back, a newcomer fills a saved seat nobody took and then a free one, a held seat waits for its
## token, and the switches, the players screen's Continue and the notices. Every file is a temp one.

const MAIN_PATH := "res://scenes/main.gd"
const NET_PATH := "res://scripts/autoload/net.gd"
const RUN_PATH := "res://data/runs/rotten_road.tres"
const BRANDING_PATH := "res://data/branding/branding.tres"
const FINGERPRINT := "abc123"
const HOST := 1
const PEER_A := 1001
const PEER_B := 1002
const NEW_A := 2001
const NEW_B := 2002
const NEW_C := 2003
const GRACE_MS := 300000
const REJOIN_MS := 120000
const TAKEOVER_MS := 15000

var _tuning := Tuning.new()
var _data: RunData
var _path: String
var _local_path: String
var _seat_path: String
var _main: GDScript
var _source: String
var _settings_before: ConfigFile
var _pad_before: bool
var _both_before: bool


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_main = load(MAIN_PATH) as GDScript
	_source = FileAccess.get_file_as_string(MAIN_PATH)


func before_each() -> void:
	var stamp := Time.get_ticks_usec()
	_path = OS.get_temp_dir().path_join("rotsworn_test_online_save_%d.json" % stamp)
	_local_path = OS.get_temp_dir().path_join("rotsworn_test_local_save_%d.json" % stamp)
	_seat_path = OS.get_temp_dir().path_join("rotsworn_test_seat_%d.json" % stamp)
	_settings_before = PlayerSettings._config
	PlayerSettings._config = ConfigFile.new()
	PlayerSettings.set_persistence(false)
	_pad_before = ButtonPrompts._pad
	_both_before = ButtonPrompts._both
	ButtonPrompts._pad = false
	ButtonPrompts._both = false


func after_each() -> void:
	RunSave.delete(_path)
	RunSave.delete(_local_path)
	SeatFile.delete(_seat_path)
	PlayerSettings._config = _settings_before
	PlayerSettings.set_persistence(true)
	ButtonPrompts._pad = _pad_before
	ButtonPrompts._both = _both_before


## The body of Main's function `header` (up to the next top-level func).
func _body(header: String) -> String:
	var start := _source.find(header)
	if start < 0:
		return ""
	var end := _source.find("\nfunc ", start + 1)
	var end_static := _source.find("\nstatic func ", start + 1)
	if end_static >= 0 and (end < 0 or end_static < end):
		end = end_static
	return _source.substr(start, end - start if end >= 0 else -1)


## The host and two friends (P2 PEER_A, P3 PEER_B), one hero each, both with a seat token.
func _three() -> PlayerRoster:
	var roster := PlayerRoster.online(3, HOST, HOST)
	roster.join_peer(PEER_A)
	roster.join_peer(PEER_B)
	return roster


func _seats(with_b: bool = true) -> SeatBook:
	var seats := SeatBook.new()
	seats.add(PEER_A, "tokA")
	if with_b:
		seats.add(PEER_B, "tokB")
	return seats


func _progressed_run() -> RunState:
	var run := RunState.begin(_data, _tuning, 4242)
	run.gold = 55
	run.go(run.choices()[0])
	return run


## The seats as the online slot keeps them, through the file and back.
func _through_file(roster: PlayerRoster, seats: SeatBook) -> Dictionary:
	assert_true(RunSave.save({"seed": 1}, FINGERPRINT, false, roster.player_count(), _path,
			SavedSeats.capture(roster, seats)), "saved")
	var loaded := RunSave.load_save("", _path, RunSave.game_version(), true)
	assert_eq(String(loaded.status), RunSave.LOADED)
	return loaded.online as Dictionary


# --- the online slot (RunSave) -----------------------------------------------------------------

func test_the_online_slot_round_trips_the_run_and_its_seats() -> void:
	var run := _progressed_run()
	var roster := _three()
	assert_true(RunSave.save(run.to_dict(), FINGERPRINT, true, 3, _path, SavedSeats.capture(roster, _seats())))
	var loaded := RunSave.load_save("", _path, RunSave.game_version(), true)
	assert_eq(String(loaded.status), RunSave.LOADED)
	assert_true(bool(loaded.in_stop), "inside the stop")
	assert_eq(int(loaded.players), 3)
	var copy := RunState.from_dict(_data, _tuning, loaded.run as Dictionary)
	assert_not_null(copy)
	assert_eq(copy.to_dict(), run.to_dict(), "the same run")
	var seats := loaded.online as Dictionary
	assert_eq(SavedSeats.tokens_of(seats), {PEER_A: "tokA", PEER_B: "tokB"}, "each friend's token, by the peer they had")
	var back := SavedSeats.restore(seats, 3)
	assert_not_null(back, "the roster fits again")
	assert_eq(back.peers, [HOST, PEER_A, PEER_B] as Array[int])
	assert_eq(back.owners, roster.owners, "the same heroes")
	assert_eq(back.away, [1, 2] as Array[int], "every friend away until they are back")
	assert_eq(back.joining, [] as Array[int])
	assert_eq(back.local_peer, HOST)


func test_the_local_slot_is_left_alone() -> void:
	assert_ne(RunSave.ONLINE_PATH, RunSave.PATH, "two slots")
	assert_true(RunSave.save({"local": 1}, FINGERPRINT, false, 1, _local_path))
	assert_true(RunSave.save({"online": 2}, FINGERPRINT, true, 2, _path, SavedSeats.capture(_three(), _seats())))
	var local := RunSave.load_save("", _local_path)
	assert_eq(String(local.status), RunSave.LOADED)
	assert_eq(int(local.run.local), 1, "the local run as it was")
	assert_false(bool(local.in_stop))
	assert_eq(local.online, {}, "a local save has no seats")
	RunSave.delete(_path)
	assert_true(RunSave.exists(_local_path), "deleting the online slot keeps the local one")
	assert_eq(String(RunSave.load_save("", _local_path, RunSave.game_version(), true).status), RunSave.REJECTED,
			"a local save is never taken for an online one")
	# Main keeps them apart: online the host's path is the online slot, and the friend never saves.
	var path_body := _body("func _run_save_path(")
	assert_string_contains(path_body, "if Net.is_online():")
	assert_string_contains(path_body, "return _online_save_path()")
	assert_string_contains(_body("func _online_save_path("), "RunSave.ONLINE_PATH")
	assert_string_contains(_body("func _save_io_ok("), "return Net.is_host() and")
	assert_string_contains(_body("func _valid_save("), "if Net.is_online() or not _save_io_ok()")


func test_a_save_from_another_version_is_refused_and_kept() -> void:
	assert_true(RunSave.save({"seed": 1}, FINGERPRINT, false, 2, _path, SavedSeats.capture(_three(), _seats())))
	var file := FileAccess.open(_path, FileAccess.READ)
	var body := JSON.parse_string(file.get_as_text()) as Dictionary
	file.close()
	assert_eq(String(body.version), RunSave.game_version(), "the game's version goes in the file")
	var other := RunSave.load_save("", _path, "0.0.0-other", true)
	assert_eq(String(other.status), RunSave.REJECTED)
	assert_true(bool(other.keep), "kept: the other build can still continue it")
	assert_string_contains(String(other.reason), "another version")
	assert_true(RunSave.exists(_path), "still on disk")
	assert_eq(String(RunSave.load_save("", _path, RunSave.game_version(), true).status), RunSave.LOADED,
			"the same version loads it")
	assert_string_contains(_body("func _valid_online_save("), "RunSave.load_save(\"\", _online_save_path(), RunSave.game_version(), true)")
	assert_string_contains(_body("func _valid_online_save("), "_online_save_note = \"Saved run: another version (kept)\"")


func test_an_online_load_needs_the_seats() -> void:
	assert_true(RunSave.save({"seed": 1}, FINGERPRINT, false, 1, _path))
	var loaded := RunSave.load_save("", _path, RunSave.game_version(), true)
	assert_eq(String(loaded.status), RunSave.REJECTED)
	assert_false(bool(loaded.get("keep", false)), "damaged: no seats in an online save")


func test_the_slot_goes_when_the_run_ends_or_is_abandoned() -> void:
	assert_true(RunSave.save({"seed": 1}, FINGERPRINT, false, 2, _path, SavedSeats.capture(_three(), _seats())))
	RunSave.delete(_path)
	assert_false(RunSave.exists(_path))
	assert_eq(String(RunSave.load_save("", _path, RunSave.game_version(), true).status), RunSave.MISSING)
	# Main: abandoning, a decided last fight and the run's end clear the slot it saves to (the online
	# one while hosting); a new online run over it asks first and deletes it when it begins.
	for fn: String in ["func _abandon_run(", "func _show_run_end("]:
		assert_string_contains(_body(fn), "_clear_run_save()", fn)
	var clear := _body("func _clear_run_save(")
	assert_string_contains(clear, "if _save_slot_ok():")
	assert_string_contains(clear, "RunSave.delete(_run_save_path())")
	assert_string_contains(_body("func _new_run("), "RunSave.delete(_run_save_path())")
	assert_string_contains(_body("func _on_online_started("), "_online_save_in_the_way()")
	assert_string_contains(_body("func _reset_progress("), "RunSave.delete(_online_save_path())")


func test_the_host_saves_the_seats_with_each_checkpoint() -> void:
	var write := _body("func _write_checkpoint(")
	assert_string_contains(write, "SavedSeats.capture(_players, Net.seats) if Net.is_host() else {}")
	var quit := _body("func _save_quit_online(")
	assert_lt(quit.find("_write_checkpoint() if _checkpoint_in_stop else _save_run(false)"),
			quit.find("Net.broadcast(\"saved\" if saved else \"menu\")"), "saved before the friends are told")
	assert_string_contains(quit, "_put_away = true")
	assert_string_contains(_body("func _on_pause_save_quit("), "_save_quit_online()")
	# A friend's pause never offers it: the row is the host's only.
	var pause := _body("func _open_pause(")
	var host_row := pause.find("elif Net.is_host() and _save_allowed():")
	assert_gt(host_row, 0)
	assert_lt(host_row, pause.find("elif Net.is_client():"))
	assert_eq(pause.count("_pause.save_quit_requested.connect(_on_pause_save_quit)"), 2, "the host's and a local run's")


# --- held seats (SeatBook.hold) ----------------------------------------------------------------

func test_a_held_seat_waits_for_its_token_its_own_time() -> void:
	var seats := SeatBook.new()
	assert_true(seats.hold(PEER_A, "tokA", 1000, GRACE_MS))
	assert_false(seats.hold(PEER_A, "tokA", 1000, GRACE_MS), "once")
	assert_true(seats.is_held(PEER_A))
	assert_eq(seats.away_peers(), [PEER_A] as Array[int], "away from the start")
	assert_eq(seats.time_left(PEER_A, 2000, REJOIN_MS), GRACE_MS - 1000, "its own grace time, not the rejoin one")
	assert_eq(seats.expired(1000 + REJOIN_MS, REJOIN_MS), [] as Array[int], "not gone after the usual grace")
	assert_eq(seats.longest_away(1000 + TAKEOVER_MS, TAKEOVER_MS), PEER_A, "a newcomer may take it after a while")
	assert_eq(seats.claim("tokA", NEW_A), PEER_A, "its token takes it back")
	assert_false(seats.is_held(NEW_A))
	assert_false(seats.is_held(PEER_A))
	assert_eq(seats.away_peers(), [] as Array[int])
	assert_eq(seats.token_of(NEW_A), "tokA")


func test_a_held_seat_goes_when_its_time_is_up() -> void:
	var seats := SeatBook.new()
	seats.hold(PEER_A, "tokA", 0, GRACE_MS)
	seats.add(PEER_B, "tokB")
	seats.set_away(PEER_B, 0)
	assert_eq(seats.expired(REJOIN_MS, REJOIN_MS), [PEER_B] as Array[int], "a dropped seat keeps the usual time")
	assert_eq(seats.expired(GRACE_MS, REJOIN_MS), [PEER_A] as Array[int], "the held one its own")
	assert_false(seats.has(PEER_A))
	assert_false(seats.is_held(PEER_A))


# --- who sits where on Continue (SavedSeats) ---------------------------------------------------

func test_a_returning_token_gets_its_own_seat() -> void:
	var roster := _three()
	var seats := _through_file(roster, _seats())
	var back := SavedSeats.restore(seats, 3)
	# They come back in the other order, each with their own token.
	var lobby: Array[int] = [NEW_A, NEW_B]
	var placed := SavedSeats.seat_lobby(back, SavedSeats.tokens_of(seats), lobby, {NEW_A: "tokB", NEW_B: "tokA"})
	assert_eq(placed.seated, {NEW_A: 2, NEW_B: 1}, "each in their own seat, whatever the order")
	assert_eq(placed.refused, [] as Array[int])
	assert_eq(placed.waiting, {}, "no seat left waiting")
	assert_eq(back.peers, [HOST, NEW_B, NEW_A] as Array[int])
	assert_eq(back.owners, roster.owners, "their own heroes")
	assert_eq(back.away, [] as Array[int], "both play at once")


func test_a_newcomer_fills_a_saved_seat_then_a_free_one() -> void:
	var seats := _through_file(_three(), _seats())
	var back := SavedSeats.restore(seats, 3)
	var lobby: Array[int] = [NEW_A]
	var placed := SavedSeats.seat_lobby(back, SavedSeats.tokens_of(seats), lobby, {})
	assert_eq(placed.seated, {NEW_A: 1}, "no token: the first saved seat nobody took")
	assert_eq(placed.waiting, {PEER_B: "tokB"}, "P3's seat waits for its token")
	assert_eq(back.away, [2] as Array[int])
	# One friend saved, two on the screen: the token holder gets theirs, the other a free seat.
	var two := PlayerRoster.online(3, HOST, HOST)
	two.join_peer(PEER_A)
	var one_saved := _through_file(two, _seats(false))
	var again := SavedSeats.restore(one_saved, 3)
	var both: Array[int] = [NEW_B, NEW_A]
	var sat := SavedSeats.seat_lobby(again, SavedSeats.tokens_of(one_saved), both, {NEW_A: "tokA"})
	assert_eq(int((sat.seated as Dictionary)[NEW_A]), 1, "the token's own seat")
	assert_eq(int((sat.seated as Dictionary)[NEW_B]), 2, "a new seat by the drop-in rule")
	assert_eq(again.player_count(), 3)
	assert_eq(again.away, [] as Array[int])
	for player: int in 3:
		assert_eq(again.seats_held(player), 1, "a hero each")


func test_a_full_game_turns_the_extra_friend_away() -> void:
	var seats := _through_file(_three(), _seats())
	var back := SavedSeats.restore(seats, 3)
	var lobby: Array[int] = [NEW_A, NEW_B, NEW_C]
	var placed := SavedSeats.seat_lobby(back, SavedSeats.tokens_of(seats), lobby, {NEW_A: "tokA", NEW_B: "tokB"})
	assert_eq(placed.refused, [NEW_C] as Array[int], "no seat left")
	assert_eq(back.player_count(), 3)
	assert_eq(back.player_of_peer(NEW_C), -1)


func test_a_seat_without_a_token_is_given_up() -> void:
	var roster := _three()
	var seats := _through_file(roster, _seats(false))
	assert_eq(SavedSeats.tokens_of(seats), {PEER_A: "tokA"})
	var back := SavedSeats.restore(seats, 3)
	assert_eq(back.peers, [HOST, PEER_A] as Array[int], "P3 had no token: nobody could claim it")
	assert_eq(back.owner_of(2), 0, "its hero goes to the host")
	assert_eq(back.away, [1] as Array[int])


func test_seats_that_do_not_fit_are_refused() -> void:
	assert_null(SavedSeats.restore({}, 3), "no roster")
	var seats := SavedSeats.capture(_three(), _seats())
	assert_null(SavedSeats.restore(seats, 2), "another party size")
	assert_null(SavedSeats.restore({"roster": PlayerRoster.solo(3).to_dict(), "tokens": {}}, 3), "a local roster")
	var other_host := PlayerRoster.online(3, 7, 7)
	assert_null(SavedSeats.restore({"roster": other_host.to_dict(), "tokens": {}}, 3), "the host is peer 1")
	assert_eq(SavedSeats.tokens_of({"tokens": {"x": "t", "1": "host", "1001": 5, "1002": "tokB"}}), {PEER_B: "tokB"},
			"only friends' peers with a token")
	assert_eq(SavedSeats.capture(null, SeatBook.new()), {})


# --- the friend's seat file (SeatFile) ---------------------------------------------------------

func test_a_friend_keeps_their_token_for_that_host() -> void:
	assert_eq(SeatFile.token_for("10.0.0.5", _seat_path), "", "nothing kept yet")
	assert_true(SeatFile.save(" 10.0.0.5 ", "tokA", _seat_path))
	assert_eq(SeatFile.token_for("10.0.0.5", _seat_path), "tokA")
	assert_eq(SeatFile.token_for("10.0.0.9", _seat_path), "", "only for the host that gave it")
	assert_false(SeatFile.save("10.0.0.5", "", _seat_path), "no token, nothing to keep")
	assert_false(SeatFile.save("10.0.0.5", "tokA", ""), "no file (a bot without --seat-path)")
	var file := FileAccess.open(_seat_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	assert_eq(SeatFile.token_for("10.0.0.5", _seat_path), "", "a broken file keeps nothing")
	SeatFile.delete(_seat_path)
	assert_false(FileAccess.file_exists(_seat_path))
	# Net shows it when joining with no token in memory; Main writes it when the host saves.
	var net := FileAccess.get_file_as_string(NET_PATH)
	assert_string_contains(net, "_seat_token = SeatFile.token_for(_seat_address, seat_file)")
	var saved := _body("func _on_net_message(")
	assert_lt(saved.find("SeatFile.save(Net.seat_address(), Net.seat_token(), Net.seat_file)"),
			saved.find("_end_online(HOST_SAVED_NOTICE, &\"save\")"), "kept before the seat is forgotten")


# --- switches, the players screen and the notices ---------------------------------------------

func test_the_switches() -> void:
	var options := CombatOptions.from_args(PackedStringArray(["--autoplay", "--online-save-path=C:/x/online.json",
			"--continue-online", "--save-quit-at=3", "--seat-path=C:/x/seat.json"]), _tuning)
	assert_eq(options.online_save_path, "C:/x/online.json")
	assert_true(options.continue_online)
	assert_eq(options.save_quit_at, 3)
	assert_eq(options.seat_path, "C:/x/seat.json")
	var none := CombatOptions.from_args(PackedStringArray(["--save-quit-at=-4"]), _tuning)
	assert_eq(none.save_quit_at, 0)
	assert_false(none.continue_online)
	assert_eq(none.online_save_path, "")
	assert_string_contains(_body("func _autoplay_start_online("), "_on_online_continued(lobby.roster())")
	assert_string_contains(_body("func _on_stop_chosen("), "if _autoplay_save_quit_now():")


func _lobby(is_host: bool, line: String) -> LobbyScreen:
	var names: Array[String] = []
	var portraits: Array[String] = []
	for c: CharacterData in _data.party:
		names.append(c.display_name)
		portraits.append(c.big_portrait_path)
	var lobby := LobbyScreen.new()
	lobby.hero_portraits = portraits
	lobby.continue_line = line
	var roster := PlayerRoster.online(names.size(), HOST, HOST if is_host else PEER_A)
	lobby.setup_online(names, roster, is_host, [] as Array[String], 7777)
	add_child_autofree(lobby)
	return lobby


static func _action(name: StringName) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func test_the_host_screen_offers_continue_beside_start() -> void:
	var lobby := _lobby(true, "Act 1, Stop 3")
	assert_true(lobby.has_continue())
	assert_eq(lobby._menu.index, lobby._continue_row(), "the cursor rests on Continue")
	assert_eq(lobby._continue_row(), lobby._start_row() + 1, "after Start, side by side")
	watch_signals(lobby)
	lobby._unhandled_input(_action(&"menu_confirm"))
	assert_signal_emitted(lobby, "continued", "Confirm on Continue")
	assert_signal_not_emitted(lobby, "started")
	lobby._unhandled_input(_action(&"menu_up"))
	assert_eq(lobby._menu.index, lobby._start_row())
	lobby._unhandled_input(_action(&"menu_confirm"))
	assert_signal_emitted(lobby, "started", "Confirm on Start starts a new run")
	assert_signal_emit_count(lobby, "continued", 1)


func test_no_continue_without_a_save_or_for_a_friend() -> void:
	assert_false(_lobby(true, "").has_continue(), "no saved online run")
	assert_false(_lobby(false, "Act 1, Stop 3").has_continue(), "a friend's screen")
	var state := RunState.begin(_data, _tuning, 9)
	state.go(state.choices()[0])
	assert_eq(_main.call("_continue_line_of", state), "Act 1, Stop 1")


func test_the_notices_are_a_picture_and_a_few_words() -> void:
	var constants := _main.get_script_constant_map()
	for key: String in ["HOST_SAVED_NOTICE", "RUN_SAVED_ONLINE_NOTICE"]:
		var text := String(constants.get(key, ""))
		assert_false(text.is_empty(), key)
		assert_lte(text.split(" ", false).size(), 5, "short: %s" % text)
		assert_false(text.contains("."), "no sentence: %s" % text)
	var menu := MainMenu.new()
	add_child_autofree(menu)
	menu.setup(load(BRANDING_PATH) as BrandingData, MainMenu.NEW_RUN, "Host saved the run", false, false, 0, true, &"save")
	var notice := menu.find_child("Notice", true, false)
	assert_not_null(notice, "the notice line")
	var glyphs := notice.find_children("*", "Control", true, false).filter(
			func(n: Node) -> bool: return n is PauseMenu.RowGlyph)
	assert_eq(glyphs.size(), 1, "the save picture")
	assert_eq((glyphs[0] as PauseMenu.RowGlyph).kind, &"save")
	var words := notice.find_children("*", "Label", true, false)
	assert_eq((words[0] as Label).text, "Host saved the run")
	# The friend goes home at once on "saved", with a clear line for the bot.
	var saved := _body("func _on_net_message(")
	assert_string_contains(saved, "\"saved\":")
	assert_string_contains(saved, "print(\"AUTOPLAY_RESULT host_saved\")")
	assert_string_contains(_body("func _on_online_continued("), "start[\"continued\"] = true")
