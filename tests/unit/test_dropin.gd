extends GutTest
## Phase 25 drop-in co-op (DESIGN.md 9.3, cards #304, #311): joining and leaving mid-run without
## dealing the heroes out again (a newcomer takes one hero from whoever holds the most, a leaver's
## heroes go to P1), trading heroes on the in-run Players overlay, an online newcomer catching up
## (away and joining), and P1's real device while solo. Online: who the host lets in (JoinGate), the
## away seat a newcomer may take (SeatBook), short refusal texts, combat batches kept per fight
## until that fight is built (FightInbox), the turn's open menu and a running sequence's players kept
## through roster changes, the --join-after switch, and a late joiner's Relic baseline coming only
## from a drop-in's catch-up. The bot's drop-in switches (--pad-join-after and friends) parse.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const TUNING_PATH := "res://data/tuning/tuning.tres"
const MAIN_PATH := "res://scenes/main.gd"
const CONTROLLER_PATH := "res://scripts/combat/presentation/combat_controller.gd"

const KEYBOARD: int = PlayerRoster.KEYBOARD
const ANY: int = PlayerRoster.ANY
const HOST: int = 1
const PEER_A: int = 1001
const PEER_B: int = 2002
const PEER_C: int = 3003


## A local roster with these devices (player -> device) and owners (hero slot -> player).
func _local(devices: Array, owners: Array) -> PlayerRoster:
	var roster := PlayerRoster.new()
	roster.devices.assign(devices)
	roster.owners.assign(owners)
	return roster


## The text of function `header` (e.g. "func _pump(") in `source`, up to the next top-level func.
func _body(source: String, header: String) -> String:
	var start := source.find(header)
	assert_gt(start, -1, "found: %s" % header)
	if start < 0:
		return ""
	var end := source.find("\nfunc ", start + 1)
	var static_end := source.find("\nstatic func ", start + 1)
	if static_end > 0 and (end < 0 or static_end < end):
		end = static_end
	return source.substr(start, end - start if end > start else -1)


## Host, P2 (PEER_A) and P3 (PEER_B) online, a hero each.
func _online_three() -> PlayerRoster:
	var roster := PlayerRoster.online(3, HOST, HOST)
	roster.join_peer(PEER_A)
	roster.join_peer(PEER_B)
	return roster


# --- joining mid-run (card #304) ----------------------------------------------------------------

func test_join_midrun_takes_brin_then_cass_from_p1() -> void:
	var roster := PlayerRoster.solo(3, 0)
	assert_eq(roster.join_midrun(1), 1)
	assert_eq(roster.owners, [0, 1, 0] as Array[int], "P2 takes Brin, the usual deal's hero")
	assert_eq(roster.devices, [0, 1] as Array[int])
	assert_eq(roster.join_midrun(2), 2)
	assert_eq(roster.owners, [0, 1, 2] as Array[int], "P3 takes Cass")
	assert_eq(roster.validate(), [] as Array[String])


func test_join_midrun_takes_only_from_the_donor() -> void:
	var roster := _local([0, 1], [0, 1, 1])
	assert_eq(roster.join_midrun(2), 2)
	assert_eq(roster.owners, [0, 1, 2] as Array[int], "P2 holds two and has Cass: Cass goes")
	roster = _local([0, 1], [0, 0, 1])
	assert_eq(roster.join_midrun(2), 2)
	assert_eq(roster.owners, [0, 2, 1] as Array[int], "P1 has no Cass: their last hero goes, P2 keeps theirs")
	assert_eq(roster.validate(), [] as Array[String])


func test_join_midrun_refusals() -> void:
	var roster := _local([KEYBOARD, 0], [0, 1, 0])
	var before := roster.to_dict()
	assert_eq(roster.join_midrun(0), -1, "a device joins once")
	assert_eq(roster.join_midrun(ANY), -1, "the bot's code presses are nobody's device")
	assert_eq(roster.to_dict(), before, "unchanged")
	var full := _local([KEYBOARD, 0, 1], [0, 1, 2])
	before = full.to_dict()
	assert_eq(full.join_midrun(2), -1, "at most three players")
	assert_eq(full.to_dict(), before, "unchanged")
	var no_spare := _local([KEYBOARD, 0], [0, 1])
	assert_eq(no_spare.join_midrun(1), -1, "nobody holds two heroes")
	assert_eq(no_spare.devices, [KEYBOARD, 0] as Array[int])
	var online := PlayerRoster.online(3, HOST, HOST)
	before = online.to_dict()
	assert_eq(online.join_midrun(0), -1, "online the host seats friends itself")
	assert_eq(online.to_dict(), before, "unchanged")


func test_can_join_midrun() -> void:
	var roster := PlayerRoster.solo(3, KEYBOARD)
	assert_true(roster.can_join_midrun(), "solo with three heroes")
	roster.join_midrun(0)
	assert_eq(roster.owners, [0, 1, 0] as Array[int])
	assert_true(roster.can_join_midrun(), "P1 still holds two")
	roster.join_midrun(1)
	assert_false(roster.can_join_midrun(), "three players")


func test_donor_hero_and_seats_held() -> void:
	var roster := _local([0, 1], [0, 0, 1, 1])
	assert_eq(roster.seats_held(0), 2)
	assert_eq(roster.seats_held(1), 2)
	assert_eq(roster.donor_hero(2), 1, "a tie goes to the lower player; P1's last hero")
	roster = _local([0, 1, 2], [0, 1, 2])
	assert_eq(roster.donor_hero(3), -1, "nobody holds two")
	var online := _online_three()
	online.set_away(PEER_A)
	assert_eq(online.seats_held(1), 1, "an away seat still holds its hero")


func test_an_away_seat_never_gives_a_hero() -> void:
	# The host handed Cass to P2 in the lobby; P2's Wi-Fi drops, and a newcomer comes within 15 s.
	var roster := PlayerRoster.online(3, HOST, HOST)
	roster.join_peer(PEER_A)
	roster.owners.assign([0, 1, 1])
	assert_true(roster.set_away(PEER_A))
	assert_eq(roster.donor_hero(2), -1, "only the away P2 holds two: nobody gives")
	assert_false(roster.can_join_midrun(), "the newcomer gets Game full")
	assert_eq(roster.join_peer_midrun(PEER_B), -1)
	assert_eq(roster.owners, [0, 1, 1] as Array[int], "P2 keeps both heroes for their token")
	assert_true(roster.set_back(PEER_A))
	assert_eq(roster.donor_hero(2), 2, "back: P2 gives Cass again")
	# A seated player who holds two still gives while someone else is away.
	var four := PlayerRoster.online(4, HOST, HOST)
	four.join_peer(PEER_A)
	four.owners.assign([0, 0, 1, 1])
	four.set_away(PEER_A)
	assert_eq(four.donor_hero(2), 1, "the host gives (its last hero), not the away P2")
	assert_eq(four.join_peer_midrun(PEER_B), 2)
	assert_eq(four.owners, [0, 2, 1, 1] as Array[int], "the away seat's heroes stay")
	# A joining player (always also away) never gives either.
	var joining := PlayerRoster.online(3, HOST, HOST)
	joining.join_peer(PEER_A)
	joining.owners.assign([0, 1, 1])
	joining.set_joining(PEER_A)
	assert_eq(joining.donor_hero(2), -1, "a friend still catching up keeps their heroes")


func test_join_peer_midrun_is_away_and_joining() -> void:
	var roster := PlayerRoster.online(3, HOST, HOST)
	assert_eq(roster.join_peer_midrun(PEER_A), 1)
	assert_eq(roster.owners, [0, 1, 0] as Array[int])
	assert_eq(roster.peers, [HOST, PEER_A] as Array[int])
	assert_true(roster.is_away(1), "the host plays the hero until the hand-over")
	assert_true(roster.is_joining(1))
	assert_eq(roster.owner_of(1), 0)
	assert_eq(roster.validate(), [] as Array[String])
	assert_eq(roster.join_peer_midrun(PEER_A), -1, "a peer joins once")
	assert_true(roster.set_back(PEER_A))
	assert_false(roster.is_away(1))
	assert_false(roster.is_joining(1), "handed over")
	assert_eq(roster.owner_of(1), 1)
	assert_eq(PlayerRoster.solo(3, KEYBOARD).join_peer_midrun(PEER_A), -1, "only online")


func test_set_joining_marks_a_taken_seat() -> void:
	var roster := _online_three()
	assert_false(roster.set_joining(HOST), "the host never joins")
	assert_false(roster.set_joining(PEER_C), "an unknown peer")
	assert_true(roster.set_joining(PEER_A))
	assert_true(roster.set_joining(PEER_A), "again: no change")
	assert_eq(roster.away, [1] as Array[int])
	assert_eq(roster.joining, [1] as Array[int])
	assert_eq(roster.owner_of(1), 0, "the host plays the hero meanwhile")
	assert_eq(roster.validate(), [] as Array[String])


# --- leaving and trading mid-run (card #311) ----------------------------------------------------

func test_leave_midrun_gives_heroes_to_p1_only() -> void:
	var roster := _local([0, 1, 2], [0, 1, 2])
	assert_true(roster.leave_midrun(1))
	assert_eq(roster.devices, [0, 2] as Array[int], "P3 moves up to P2")
	assert_eq(roster.owners, [0, 0, 1] as Array[int], "P2's hero goes to P1, P3 keeps theirs")
	roster = _local([0, 1], [0, 1, 0])
	assert_true(roster.leave_midrun(0), "a lost P1 pad's Give heroes")
	assert_eq(roster.devices, [1] as Array[int], "the old P2 is P1 now")
	assert_eq(roster.owners, [0, 0, 0] as Array[int])
	assert_false(roster.leave_midrun(0), "the last player never leaves")
	assert_false(roster.leave_midrun(5), "a bad index")
	var online := _online_three()
	assert_false(online.leave_midrun(1), "online players leave by dropping out")
	assert_eq(online.player_count(), 3)


func test_trade_hero_moves_or_swaps() -> void:
	var roster := _local([0, 1], [0, 1, 0])
	assert_true(roster.trade_hero(2, 1))
	assert_eq(roster.owners, [0, 1, 1] as Array[int], "P1 had two: a move")
	roster = _local([0, 1, 2], [0, 1, 2])
	assert_true(roster.trade_hero(0, 1))
	assert_eq(roster.owners, [1, 0, 2] as Array[int], "P1's only hero: P1 and P2 swap")
	roster = _local([0, 1], [0, 1, 0])
	assert_true(roster.trade_hero(1, 1))
	assert_eq(roster.owners, [1, 0, 0] as Array[int], "two players swap too (in run only)")
	assert_eq(roster.validate(), [] as Array[String])
	assert_false(roster.trade_hero(7, 1), "a bad slot")
	assert_false(roster.trade_hero(0, 0), "a bad step")
	assert_false(PlayerRoster.solo(3, KEYBOARD).trade_hero(0, 1), "solo: nothing to hand over")


# --- data ---------------------------------------------------------------------------------------

func test_joining_travels_and_shifts() -> void:
	var roster := _online_three()
	roster.set_joining(PEER_B)
	var data := roster.to_dict()
	assert_eq(Fx.find_illegal_value(data), "", "only plain values go over the network")
	var seen := PlayerRoster.from_dict(data, PEER_A)
	assert_not_null(seen)
	assert_eq(seen.joining, [2] as Array[int])
	var old := roster.to_dict()
	old.erase("joining")
	assert_not_null(PlayerRoster.from_dict(old, PEER_A), "a roster without the joining list still reads")
	var bad := roster.to_dict()
	bad["joining"] = ["x"]
	assert_null(PlayerRoster.from_dict(bad, PEER_A), "malformed")
	assert_true(roster.drop_peer(PEER_A))
	assert_eq(roster.joining, [1] as Array[int], "P3 moved up to P2, still joining")
	assert_eq(roster.away, [1] as Array[int])
	var stray := roster.to_dict()
	stray["joining"] = [1]
	stray["away"] = []
	assert_null(PlayerRoster.from_dict(stray, PEER_A), "joining is always away too")


func test_same_as() -> void:
	var roster := _local([KEYBOARD, 0], [0, 1, 0])
	assert_true(roster.copy().same_as(roster), "a copy is the same")
	assert_false(roster.same_as(null))
	var joined := roster.copy()
	joined.join_midrun(1)
	assert_false(joined.same_as(roster), "someone joined")
	var online := _online_three()
	var catching_up := online.copy()
	catching_up.set_joining(PEER_A)
	assert_false(catching_up.same_as(online), "someone is catching up")
	var other_machine := PlayerRoster.from_dict(online.to_dict(), PEER_A)
	assert_true(other_machine.same_as(online), "local_peer is per machine")
	assert_false(PlayerRoster.solo(3, KEYBOARD).same_as(PlayerRoster.solo(3, 0)),
			"another device: not the same (Main treats both solo as no change)")


func test_owners_text() -> void:
	assert_eq(_local([KEYBOARD, 0], [0, 1, 0]).owners_text(), "0,1,0")
	assert_eq(PlayerRoster.new().owners_text(), "")


# --- devices ------------------------------------------------------------------------------------

func test_free_pad() -> void:
	assert_eq(PlayerRoster.free_pad(_local([0], [0])), 1)
	assert_eq(PlayerRoster.free_pad(_local([KEYBOARD], [0])), 0)
	assert_eq(PlayerRoster.free_pad(_local([0, 2], [0, 1])), 1)


func test_play_device_skips_pause_and_back() -> void:
	assert_eq(PlayerRoster.play_device_after(KEYBOARD, 0, false, true), 0, "a press in play counts")
	assert_eq(PlayerRoster.play_device_after(0, 1, true, true), 0, "a friend's Menu or B never counts")
	assert_eq(PlayerRoster.play_device_after(0, 1, false, false), 0, "not while a menu is up")
	assert_eq(PlayerRoster.play_device_after(0, ANY, false, true), 0, "code presses are nobody's")
	assert_eq(PlayerRoster.play_device_after(KEYBOARD, 0, false, true, true), KEYBOARD,
			"in co-op no press counts: it may be a friend's (P2 choosing)")
	assert_eq(PlayerRoster.play_device_after(KEYBOARD, 0, false, true, false), 0, "solo again: it counts")


func test_overlay_p1_device_never_a_dead_pad() -> void:
	var pads: Array[int] = [0, 1]
	var none: Array[int] = []
	assert_eq(PlayerRoster.overlay_p1_device(1, 0, KEYBOARD, pads), 1, "the device P1 played on")
	assert_eq(PlayerRoster.overlay_p1_device(KEYBOARD, 0, 1, pads), KEYBOARD, "the keyboard is always there")
	assert_eq(PlayerRoster.overlay_p1_device(ANY, 0, KEYBOARD, pads), 0, "no press yet: the roster's")
	assert_eq(PlayerRoster.overlay_p1_device(3, 0, KEYBOARD, pads), 0, "a pad unplugged since: the roster's")
	assert_eq(PlayerRoster.overlay_p1_device(0, 0, KEYBOARD, none), KEYBOARD,
			"a solo run's pad died: the keyboard that pressed last, never the dead pad")
	assert_eq(PlayerRoster.overlay_p1_device(0, 0, 1, [1] as Array[int]), 1, "or the other pad that pressed last")
	assert_eq(PlayerRoster.overlay_p1_device(0, 0, 2, none), KEYBOARD, "else the keyboard")
	assert_eq(PlayerRoster.overlay_p1_device(ANY, ANY, ANY, none), KEYBOARD, "the bot's ANY is nobody's")


func test_main_resets_p1s_device_when_the_roster_changes() -> void:
	var source := FileAccess.get_file_as_string(MAIN_PATH)
	for fn: String in ["func _apply_local_roster(", "func _on_pad_dropped(", "func _on_lobby_started(",
			"func _new_run(", "func _continue_run("]:
		assert_true(_body(source, fn).contains("_reset_play_device()"), "%s resets P1's device" % fn)
	assert_true(_body(source, "func _note_play_device(").contains("_players.is_coop()"),
			"no press counts in co-op")
	assert_true(_body(source, "func _on_pause_players(").contains("PlayerRoster.overlay_p1_device("),
			"the overlay never makes a dead pad P1")


# --- online: who gets in (JoinGate, card #304) -------------------------------------------------

func test_gate_lobby_open() -> void:
	var gate := JoinGate.decide(false, false, 0, 0, 0, 2)
	assert_eq(int(gate.verdict), JoinGate.Verdict.LOBBY)
	assert_eq(String(gate.reason), "")
	assert_eq(int(JoinGate.decide(false, false, 0, 1, 0, 2).verdict), JoinGate.Verdict.LOBBY)
	gate = JoinGate.decide(false, false, 0, 2, 0, 2)
	assert_eq(int(gate.verdict), JoinGate.Verdict.REFUSE, "two friends already")
	assert_eq(String(gate.reason), JoinGate.REASON_FULL)
	gate = JoinGate.decide(false, true, PEER_A, 1, 0, 2)
	assert_eq(int(gate.verdict), JoinGate.Verdict.LOBBY, "the lobby gives a fresh seat, token or not")
	assert_eq(int(gate.old_peer), 0)


func test_gate_token_gets_its_own_seat_back_even_when_drop_in_is_shut() -> void:
	var gate := JoinGate.decide(true, false, PEER_A, 2, PEER_A, 2)
	assert_eq(int(gate.verdict), JoinGate.Verdict.REJOIN)
	assert_eq(int(gate.old_peer), PEER_A)
	gate = JoinGate.decide(true, true, PEER_A, 2, PEER_B, 2)
	assert_eq(int(gate.verdict), JoinGate.Verdict.REJOIN, "a token always wins over a takeover")
	assert_eq(int(gate.old_peer), PEER_A)


func test_gate_started_and_shut() -> void:
	var gate := JoinGate.decide(true, false, 0, 1, 0, 2)
	assert_eq(int(gate.verdict), JoinGate.Verdict.REFUSE)
	assert_eq(String(gate.reason), JoinGate.REASON_CLOSED)
	gate = JoinGate.decide(true, false, 0, 1, PEER_A, 2)
	assert_eq(int(gate.verdict), JoinGate.Verdict.REFUSE, "no takeover while drop-in is shut")
	assert_eq(String(gate.reason), JoinGate.REASON_CLOSED)


func test_gate_new_seat_and_away_seat() -> void:
	var gate := JoinGate.decide(true, true, 0, 1, 0, 2)
	assert_eq(int(gate.verdict), JoinGate.Verdict.NEW_SEAT)
	assert_eq(int(gate.old_peer), 0)
	gate = JoinGate.decide(true, true, 0, 1, PEER_B, 2)
	assert_eq(int(gate.verdict), JoinGate.Verdict.TAKE_AWAY, "an old enough away seat before a free one")
	assert_eq(int(gate.old_peer), PEER_B)
	gate = JoinGate.decide(true, true, 0, 2, 0, 2)
	assert_eq(int(gate.verdict), JoinGate.Verdict.REFUSE, "a fresh away seat is passed as 0 and still counts as used")
	assert_eq(String(gate.reason), JoinGate.REASON_FULL)
	gate = JoinGate.decide(true, true, 0, 2, PEER_B, 2)
	assert_eq(int(gate.verdict), JoinGate.Verdict.TAKE_AWAY)
	assert_eq(int(gate.old_peer), PEER_B)


func test_ready_action() -> void:
	assert_eq(JoinGate.ready_action(0, 0), JoinGate.Ready.SEAT_NOW, "both on a place screen")
	assert_eq(JoinGate.ready_action(5, 5), JoinGate.Ready.AT_QUIET, "the same fight")
	assert_eq(JoinGate.ready_action(5, 0), JoinGate.Ready.IGNORE, "the host left that fight")
	assert_eq(JoinGate.ready_action(0, 5), JoinGate.Ready.IGNORE, "the client has not built the fight yet")
	assert_eq(JoinGate.ready_action(5, 6), JoinGate.Ready.IGNORE, "another fight")


func test_an_announced_fight_counts_before_it_is_built() -> void:
	assert_eq(JoinGate.host_fight(0, 0), 0, "a place screen")
	assert_eq(JoinGate.host_fight(7, 0), 7, "announced, the swirl still running: already that fight")
	assert_eq(JoinGate.host_fight(7, 7), 7, "built")
	assert_eq(JoinGate.host_fight(0, 7), 7, "over, on the way back to the zone: still in the tree")
	assert_eq(JoinGate.ready_action(0, JoinGate.host_fight(7, 0)), JoinGate.Ready.IGNORE,
			"caught up on the place screen during the swirl: no hero yet (that fight would start on the old roster)")
	assert_eq(JoinGate.ready_action(7, JoinGate.host_fight(7, 7)), JoinGate.Ready.AT_QUIET,
			"the client shows the fight: at its next quiet moment")
	var body := _body(FileAccess.get_file_as_string(MAIN_PATH), "func _on_seated_ready(")
	assert_true(body.contains("JoinGate.host_fight(int(_net_fight.get(\"seed\", 0))"), "Main counts the announced fight")
	assert_true(body.contains("_combat.fight_seed() == client_fight"), "and seats at a quiet moment only in that fight")


func test_seat_book_size_and_longest_away() -> void:
	var seats := SeatBook.new()
	assert_eq(seats.size(), 0)
	assert_eq(seats.longest_away(20000, 15000), 0, "nobody away")
	seats.add(PEER_A, "aaa")
	seats.add(PEER_B, "bbb")
	seats.add(PEER_C, "ccc")
	assert_eq(seats.size(), 3)
	seats.set_away(PEER_B, 100)
	seats.set_away(PEER_A, 50)
	assert_eq(seats.longest_away(20000, 15000), PEER_A, "away since 50: the longest")
	assert_eq(seats.longest_away(10000, 15000), 0, "too fresh: held for its token")
	assert_eq(seats.longest_away(15050, 15000), PEER_A, "exactly old enough")
	assert_eq(seats.size(), 3, "away seats still count")
	assert_eq(seats.claim("aaa", 4004), PEER_A)
	assert_eq(seats.size(), 3, "a claim keeps the count")
	assert_eq(seats.longest_away(20000, 15000), PEER_B, "PEER_A's seat is back")
	seats.remove(PEER_B)
	assert_eq(seats.size(), 2)
	assert_eq(seats.longest_away(20000, 15000), 0)


func test_join_texts_are_short() -> void:
	for text: String in [JoinGate.REASON_FULL, JoinGate.REASON_CLOSED, NetSession.REASON_UNREACHABLE]:
		assert_lte(text.split(" ", false).size(), 4, "'%s': at most 4 words" % text)
		assert_false(text.contains(". "), "'%s': one sentence" % text)
		assert_false(text.is_empty())


func test_takeover_wait_is_in_tuning() -> void:
	var tuning := load(TUNING_PATH) as Tuning
	assert_gt(tuning.net_takeover_after_ms, 0, "a quick rejoin is never pre-empted")
	assert_lt(tuning.net_takeover_after_ms, tuning.net_rejoin_grace_ms, "a crashed friend can come back before the seat goes")


# --- online: batches per fight (FightInbox, cards #205, #304) ----------------------------------

func test_fight_inbox_keeps_batches_per_fight() -> void:
	var inbox := FightInbox.new()
	var a := {"kind": "events", "seq": 1, "fight": 11}
	var b := {"kind": "events", "seq": 1, "fight": 22}
	var c := {"kind": "events", "seq": 2, "fight": 11}
	inbox.add(a)
	inbox.add(b)
	inbox.add(c)
	assert_eq(inbox.size(), 3)
	assert_eq(inbox.take(11), [a, c] as Array[Dictionary], "in arrival order")
	assert_eq(inbox.size(), 1, "the next fight's batch stays")
	inbox.add({"kind": "events", "seq": 3, "fight": 11})
	assert_eq(inbox.size(), 1, "a played fight's late batch is dropped")
	assert_eq(inbox.take(22), [b] as Array[Dictionary])
	assert_eq(inbox.size(), 0)
	inbox.clear()
	inbox.add({"kind": "events", "seq": 4, "fight": 11})
	assert_eq(inbox.size(), 1, "clear forgets which fights were played")


func test_fight_inbox_drops_fights_passed_and_untagged_batches() -> void:
	var inbox := FightInbox.new()
	inbox.add({"seq": 1})
	inbox.add({"seq": 1, "fight": "x"})
	assert_eq(inbox.size(), 0, "no fight seed: nothing could take it")
	inbox.add({"seq": 1, "fight": 11})
	inbox.add({"seq": 1, "fight": 22})
	inbox.add({"seq": 1, "fight": 33})
	assert_eq(inbox.take(44), [] as Array[Dictionary], "a fight with nothing here yet")
	assert_eq(inbox.size(), 3, "the others still wait")
	assert_eq(inbox.take(22).size(), 1)
	assert_eq(inbox.size(), 1, "fight 11 came before 22: passed")
	inbox.add({"seq": 2, "fight": 11})
	assert_eq(inbox.size(), 1, "a passed fight counts as played")
	assert_eq(inbox.take(33).size(), 1)


func test_newest_roster_reads_the_queue() -> void:
	var main_script := load(MAIN_PATH) as GDScript
	var now := PlayerRoster.online(3, HOST, PEER_A)
	now.join_peer_midrun(PEER_A)
	assert_true(now.is_joining(1))
	var seated := now.copy()
	seated.set_back(PEER_A)
	var queue: Array[Dictionary] = []
	assert_eq(main_script.call("_newest_roster", queue, now), now, "nothing waiting: the roster in use")
	queue.append({"kind": "screen", "payload": {"name": "map"}})
	queue.append({"kind": "roster", "payload": {"roster": seated.to_dict()}})
	queue.append({"kind": "screen", "payload": {"name": "shop", "roster": now.to_dict()}})
	var newest: PlayerRoster = main_script.call("_newest_roster", queue, now)
	assert_true(newest != null and newest.same_as(seated), "the hand-over waiting behind a transition")
	assert_false(newest.is_joining(1), "so a lost host keeps the seat token")
	assert_eq(newest.local_peer, PEER_A, "seen from this machine")
	queue.append({"kind": "roster", "payload": {"roster": {"devices": "bad"}}})
	assert_true((main_script.call("_newest_roster", queue, now) as PlayerRoster).same_as(seated),
			"a malformed one is skipped")
	assert_true(_body(FileAccess.get_file_as_string(MAIN_PATH), "func _on_net_host_lost(").contains(
			"_newest_roster(_net_queue, _players)"), "a lost host reads it")


func test_caught_up_waits_until_playback_drained() -> void:
	assert_false(CombatController.drained(false, true, false), "nothing from the host yet")
	assert_false(CombatController.drained(true, false, false), "batches still queued")
	assert_false(CombatController.drained(true, true, true), "an event or attack still playing")
	assert_true(CombatController.drained(true, true, false), "everything the host sent has played")
	var source := FileAccess.get_file_as_string(CONTROLLER_PATH)
	assert_true(_body(source, "func _pump(").contains("_note_caught_up()"), "checked each time playback drains")


func test_a_resume_into_a_raging_boss() -> void:
	var calm := {"type": "combat_started", "resume": true, "fighters": [
			{"id": 0, "team": Combatant.Team.PARTY, "phase": 1}, {"id": 5, "team": Combatant.Team.ENEMY, "phase": 1}]}
	assert_false(CombatController.raging_on_resume(calm), "phase one")
	var raging := calm.duplicate(true)
	(raging.fighters as Array)[1]["phase"] = 2
	assert_true(CombatController.raging_on_resume(raging), "the boss raged before this machine got in")
	var live := raging.duplicate(true)
	live.erase("resume")
	assert_false(CombatController.raging_on_resume(live), "a fight from its start rages on its own event")
	assert_false(CombatController.raging_on_resume({"type": "combat_started", "resume": true}), "no fighters")
	var body := _body(FileAccess.get_file_as_string(CONTROLLER_PATH), "func _resume_mood(")
	assert_true(body.contains("shift_to_phase_two(true)"), "the arena's phase-two look at once")
	assert_true(body.contains("rage_music_path"), "and the rage song")


# --- local: a fight paused for nothing goes on (pause_reached) ---------------------------------

func test_quiet_pauses_resume_deferred() -> void:
	var body := _body(FileAccess.get_file_as_string(MAIN_PATH), "func _on_combat_pause_reached(")
	assert_false(body.contains("_combat.resume_after_pause()"),
			"never from inside the fight's event loop: its queue would stall")
	assert_eq(body.count("_resume_quiet_pause.call_deferred()"), 2, "the roster change and the pad that came back")


# --- online: menus and sequences through roster changes (cards #205, #304) ---------------------

func test_keeps_menu() -> void:
	assert_true(CombatController.keeps_menu(1, 1, true, true, -1), "same player, same machine, nobody gone")
	assert_true(CombatController.keeps_menu(0, 0, false, false, 0), "another machine's hero stays another's")
	assert_false(CombatController.keeps_menu(0, 1, true, false, -1), "the hero changed hands")
	assert_false(CombatController.keeps_menu(1, 1, false, true, -1), "the hero came to this machine")
	assert_false(CombatController.keeps_menu(1, 1, true, true, PEER_A), "somebody left")
	assert_false(CombatController.keeps_menu(-1, -1, true, true, -1), "no hero was choosing")


func test_runner_keeps_its_roster_through_a_sequence() -> void:
	var a := _online_three()
	var b := PlayerRoster.online(3, HOST, HOST)
	var oa := {10: 0, 11: 1, 12: 2}
	var ob := {10: 0, 11: 0, 12: 0}
	for runner: Variant in [autofree(TimedSequenceRunner.new()), autofree(SkillSequenceRunner.new())]:
		var label: String = "TimedSequenceRunner" if runner is TimedSequenceRunner else "SkillSequenceRunner"
		runner.set_players(a, oa)
		runner._active = true
		runner.set_players(b, ob)
		assert_eq(runner._roster, a, "%s: the sequence keeps its players" % label)
		assert_eq(runner._owners, oa, "%s: and its owners" % label)
		runner._active = false
		runner._take_held_players()
		assert_eq(runner._roster, b, "%s: the change lands when it hands back" % label)
		assert_eq(runner._owners, ob, "%s: owners too" % label)
		runner._take_held_players()
		assert_eq(runner._roster, b, "%s: nothing held any more" % label)
		runner.set_players(a, oa)
		assert_eq(runner._roster, a, "%s: between sequences a change lands at once" % label)


func test_join_after_switch() -> void:
	var options := CombatOptions.from_args(PackedStringArray(["--join=127.0.0.1", "--join-after=40"]), null)
	assert_eq(options.join_after_s, 40)
	assert_eq(options.join_address, "127.0.0.1", "--join-after is not read as --join")
	assert_eq(CombatOptions.from_args(PackedStringArray(["--join=127.0.0.1"]), null).join_after_s, 0, "at once by default")
	assert_eq(CombatOptions.from_args(PackedStringArray(["--host=1"]), null).host_players, 1, "--host=1 hosts alone")


# --- online: what a late joiner keeps (card #304) ----------------------------------------------

func test_late_flag_only_from_a_drop_in_catch_up() -> void:
	var source := FileAccess.get_file_as_string(MAIN_PATH)
	var start := source.find("func _catch_up(")
	assert_gt(start, -1, "main.gd has _catch_up")
	var end := source.find("\nfunc ", start + 1)
	var body := source.substr(start, end - start if end > start else -1)
	# The message is built in one place (card #312 added the mode); only _catch_up passes a real late.
	assert_true(body.contains("_run_start_message(_run, _players, late)"), "run_start says late only from _catch_up")
	assert_true(_body(source, "static func _run_start_message(").contains("\"late\": late"))
	for header: String in ["func _new_run(", "func _new_rush("]:
		assert_true(_body(source, header).contains("_run_start_message(") and _body(source, header).contains(", false)"),
				"%s starts everyone on time" % header)
	assert_false(source.contains("_join_pending = Net.joined_mid_run"),
			"the baseline never comes from joined_mid_run (it outlives Again)")
	assert_true(source.contains("_join_pending = bool(p.get(\"late\", false))"), "it comes from run_start's flag")


# --- dev and bot switches (cards #304, #311) ----------------------------------------------------

func test_dev_switches_parse() -> void:
	var options := CombatOptions.from_args(PackedStringArray(["--pad-join-after=30", "--pad-leave-after=90",
			"--roster-in-fight", "--seat-in-fight", "--crash-after=50", "--host=1"]), null)
	assert_eq(options.pad_join_after_s, 30)
	assert_eq(options.pad_leave_after_s, 90)
	assert_true(options.roster_in_fight)
	assert_true(options.seat_in_fight)
	assert_eq(options.crash_after_s, 50)
	assert_eq(options.host_players, 1)
	var plain := CombatOptions.from_args(PackedStringArray(["--drop-in-fight", "--drop-after=20"]), null)
	assert_eq(plain.pad_join_after_s, 0, "never by default")
	assert_eq(plain.pad_leave_after_s, 0)
	assert_false(plain.roster_in_fight, "--drop-in-fight is not --roster-in-fight")
	assert_false(plain.seat_in_fight, "--drop-in-fight is not --seat-in-fight")
	assert_eq(plain.crash_after_s, 0)
	assert_eq(plain.drop_after_s, 20)
