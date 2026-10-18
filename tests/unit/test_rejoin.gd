extends GutTest
## Rejoining an online game (DESIGN.md 9.2, card #205): seat tokens and the grace time (SeatBook),
## an away player's seat in the roster (the host plays their heroes, they get them back), and the
## fight as it stands for a player who joined again mid-fight (CombatEngine.resume_events()).

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const Bot := preload("res://tests/helpers/combat_bot.gd")

const HOST: int = 1
const PEER_A: int = 1001
const PEER_B: int = 2002
const PEER_A2: int = 3003
const GRACE_MS: int = 120000


# --- seat tokens ------------------------------------------------------------------------------

func test_a_token_names_one_seat() -> void:
	var seats := SeatBook.new()
	assert_true(seats.add(PEER_A, "aaa"))
	assert_true(seats.add(PEER_B, "bbb"))
	assert_false(seats.add(PEER_A, "ccc"), "one seat per peer")
	assert_false(seats.add(PEER_A2, "aaa"), "a token is never shared")
	assert_false(seats.add(PEER_A2, ""), "an empty token is no token")
	assert_eq(seats.token_of(PEER_A), "aaa")
	assert_eq(seats.peer_of("bbb"), PEER_B)
	assert_eq(seats.peer_of(""), 0)
	assert_eq(seats.peer_of("zzz"), 0)


func test_claiming_moves_the_seat_to_the_new_connection() -> void:
	var seats := SeatBook.new()
	seats.add(PEER_A, "aaa")
	seats.add(PEER_B, "bbb")
	assert_true(seats.set_away(PEER_A, 1000))
	assert_false(seats.set_away(PEER_A, 2000), "already away")
	assert_eq(seats.claim("aaa", PEER_A2), PEER_A, "the seat it had")
	assert_false(seats.has(PEER_A))
	assert_eq(seats.token_of(PEER_A2), "aaa")
	assert_false(seats.is_away(PEER_A2), "back")
	assert_eq(seats.away_peers(), [] as Array[int])


func test_no_claim_without_the_right_token() -> void:
	var seats := SeatBook.new()
	seats.add(PEER_A, "aaa")
	seats.add(PEER_B, "bbb")
	seats.set_away(PEER_A, 0)
	assert_eq(seats.claim("", PEER_A2), 0, "no token")
	assert_eq(seats.claim("guess", PEER_A2), 0, "a wrong token")
	assert_eq(seats.claim("aaa", PEER_B), 0, "a seated player cannot take a second seat")
	assert_eq(seats.token_of(PEER_A), "aaa", "the away seat is still there")
	assert_eq(seats.claim("bbb", PEER_A2), PEER_B,
			"a token wins its own seat even if the old connection still looks alive")


func test_grace_time_runs_out() -> void:
	var seats := SeatBook.new()
	seats.add(PEER_A, "aaa")
	seats.add(PEER_B, "bbb")
	seats.set_away(PEER_A, 5000)
	assert_eq(seats.time_left(PEER_A, 5000 + 1000, GRACE_MS), GRACE_MS - 1000)
	assert_eq(seats.time_left(PEER_B, 6000, GRACE_MS), 0, "not away")
	assert_eq(seats.expired(5000 + GRACE_MS - 1, GRACE_MS), [] as Array[int], "still kept")
	assert_eq(seats.expired(5000 + GRACE_MS, GRACE_MS), [PEER_A] as Array[int], "given up")
	assert_false(seats.has(PEER_A), "forgotten")
	assert_eq(seats.claim("aaa", PEER_A2), 0, "too late to come back")
	assert_eq(seats.expired(10_000_000, GRACE_MS), [] as Array[int], "only away seats run out")


# --- the roster -------------------------------------------------------------------------------

func _three() -> PlayerRoster:
	var roster := PlayerRoster.online(3, HOST, HOST)
	roster.join_peer(PEER_A)
	roster.join_peer(PEER_B)
	return roster


func test_an_away_player_keeps_the_seat_and_the_host_plays_it() -> void:
	var roster := _three()
	assert_true(roster.set_away(PEER_A))
	assert_false(roster.set_away(PEER_A), "once")
	assert_false(roster.set_away(HOST), "the host is never away")
	assert_eq(roster.owners, [0, 1, 2] as Array[int], "the seats stay")
	assert_eq(roster.owner_of(1), 0, "the host plays P2's hero meanwhile")
	assert_eq(roster.seat_of(1), 1)
	assert_eq(roster.heroes_of(0), [0, 1] as Array[int])
	assert_eq(roster.heroes_of(1), [] as Array[int])
	assert_eq(roster.owner_of(2), 2, "P3 plays on")
	assert_eq(roster.player_count(), 3, "nobody moves up")
	assert_eq(roster.validate(), [] as Array[String])


func test_the_away_seat_travels_as_data() -> void:
	var roster := _three()
	roster.set_away(PEER_B)
	var data := roster.to_dict()
	assert_eq(Fx.find_illegal_value(data), "", "only plain values go over the network")
	var seen := PlayerRoster.from_dict(data, PEER_A)
	assert_not_null(seen)
	assert_eq(seen.away, [2] as Array[int])
	assert_eq(seen.owner_of(2), 0)
	var old := {"devices": [-1, -1], "owners": [0, 1, 0], "peers": [HOST, PEER_A]}
	assert_not_null(PlayerRoster.from_dict(old, PEER_A), "a roster without the away list still reads")
	var bad := roster.to_dict()
	bad["away"] = [0]
	assert_null(PlayerRoster.from_dict(bad, PEER_A), "the host cannot be away")
	bad["away"] = ["x"]
	assert_null(PlayerRoster.from_dict(bad, PEER_A), "malformed")


func test_coming_back_gets_the_same_seat() -> void:
	var roster := _three()
	roster.set_away(PEER_A)
	assert_eq(roster.rebind_peer(PEER_A, PEER_B), -1, "a peer that already plays cannot take another seat")
	assert_eq(roster.rebind_peer(HOST, PEER_A2), -1, "nobody takes the host's seat")
	assert_eq(roster.rebind_peer(PEER_A, PEER_A2), 1)
	assert_eq(roster.peers, [HOST, PEER_A2, PEER_B] as Array[int])
	assert_true(roster.is_away(1), "still the host's heroes until the seat is given back")
	assert_eq(roster.owner_of(1), 0)
	assert_true(roster.set_back(PEER_A2))
	assert_false(roster.set_back(PEER_A2), "once")
	assert_eq(roster.owner_of(1), 1, "P2 plays their hero again")
	var seen := PlayerRoster.from_dict(roster.to_dict(), PEER_A2)
	assert_eq(seen.local_players(), [1] as Array[int], "the new connection is P2 on its machine")


func test_a_seat_given_up_while_away() -> void:
	var roster := _three()
	roster.set_away(PEER_B)
	roster.set_away(PEER_A)
	assert_true(roster.drop_peer(PEER_A), "P2's grace time ran out")
	assert_eq(roster.owners, [0, 0, 1] as Array[int], "P2's hero is the host's for good, P3 becomes P2")
	assert_eq(roster.away, [1] as Array[int], "the other away player moved up with their seat")
	assert_eq(roster.owner_of(2), 0, "and is still played by the host")
	assert_eq(roster.validate(), [] as Array[String])


# --- the fight as it stands -------------------------------------------------------------------

func _apply(mirror: CombatMirror, events: Array) -> void:
	for e: Dictionary in events:
		if String(e.type) != "command_rejected":
			mirror.apply(e)


func test_resume_events_rebuild_the_fight_on_a_fresh_mirror() -> void:
	var checked := 0
	for seed_value: int in [2, 9, 41]:
		for defence: int in [Bot.Defence.PERFECT, Bot.Defence.MIXED]:
			var label := "seed %d defence %d" % [seed_value, defence]
			var engine := CombatEngine.new(Fx.shipped_setup(seed_value))
			var bot := Bot.new(defence as Bot.Defence)
			var full := CombatMirror.new()
			_apply(full, engine.start())
			var rejoined: CombatMirror = null
			var steps := 0
			while engine.phase != CombatEngine.Phase.ENDED and steps < Bot.MAX_STEPS:
				steps += 1
				if engine.phase == CombatEngine.Phase.AWAITING_TIMING:
					assert_eq(engine.resume_events(), [] as Array[Dictionary], "never mid-attack: " + label)
				elif rejoined == null and steps > 4:
					var before := engine.snapshot()
					var events := engine.resume_events()
					assert_eq(engine.snapshot(), before, "asking changes nothing: " + label)
					assert_eq(Fx.find_illegal_value(events), "", "plain data: " + label)
					rejoined = CombatMirror.new()
					_apply(rejoined, events)
					assert_eq(rejoined.projection(), CombatMirror.project_snapshot(engine.snapshot()), label)
					assert_eq(rejoined.turn, engine.turn_number, label)
					assert_eq(rejoined.active_actor, engine.active_actor, label)
					assert_eq(rejoined.living_enemy_ids(), engine.living_enemy_ids(), label)
					assert_eq(rejoined.intents.keys(), full.intents.keys(), "the same intents shown: " + label)
					checked += 1
				var batch := engine.submit(bot.next_command(engine))
				_apply(full, batch)
				if rejoined != null:
					_apply(rejoined, batch)
			assert_eq(engine.phase, CombatEngine.Phase.ENDED, label)
			if rejoined != null:
				assert_eq(rejoined.projection(), full.projection(), "both machines end the same: " + label)
				assert_eq(rejoined.result, engine.result, label)
	assert_gt(checked, 3, "rejoined mid-fight in most fights")


func test_resume_after_the_end_says_how_it_ended() -> void:
	var engine := CombatEngine.new(Fx.shipped_setup(3))
	Bot.new().play(engine)
	assert_eq(engine.phase, CombatEngine.Phase.ENDED)
	var events := engine.resume_events()
	assert_eq(String(events.back().type), "combat_ended")
	var mirror := CombatMirror.new()
	_apply(mirror, events)
	assert_eq(mirror.result, engine.result)
	assert_eq(mirror.projection(), CombatMirror.project_snapshot(engine.snapshot()))
	assert_eq(CombatEngine.new(Fx.shipped_setup(3)).resume_events(), [] as Array[Dictionary], "nothing before the start")
