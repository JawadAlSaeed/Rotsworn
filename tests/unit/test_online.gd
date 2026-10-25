extends GutTest
## Online co-op (DESIGN.md 9.2): the online roster (one player per machine, sent as data, a player
## dropping out mid-run), the defence arbiter (deadlines from the ack, NONE when overdue, only own
## prompts, once each, stale sequences, a client leaving), the content fingerprint, and the run
## state the host sends (round trip, refusals).

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const NONE: int = Defense.Outcome.NONE
const PARRY: int = Defense.Outcome.PARRY
const HOST: int = 1
const PEER_A: int = 1001
const PEER_B: int = 2002
const MS: int = 1000

var _tuning := Tuning.new()


# --- roster -----------------------------------------------------------------------------------

func test_online_roster_one_player_per_machine() -> void:
	var host_view := PlayerRoster.online(3, HOST, HOST)
	assert_true(host_view.is_online())
	assert_eq(host_view.join_peer(PEER_A), 1)
	assert_eq(host_view.join_peer(PEER_A), -1, "a machine joins once")
	assert_eq(host_view.owners, [0, 1, 0] as Array[int])
	assert_eq(host_view.local_players(), [0] as Array[int], "the host plays P1 only")
	for device: int in [PlayerRoster.KEYBOARD, 0, 3, PlayerRoster.ANY]:
		assert_eq(host_view.player_of_device(device), 0, "any device on the host's machine is P1")
	assert_true(host_view.may_control(0, 0))
	assert_false(host_view.may_control(PlayerRoster.KEYBOARD, 1), "P2's hero is played on P2's machine")
	assert_eq(host_view.validate(), [] as Array[String])


func test_online_roster_travels_as_data() -> void:
	var host_view := PlayerRoster.online(3, HOST, HOST)
	host_view.join_peer(PEER_A)
	host_view.join_peer(PEER_B)
	host_view.move_hero(0, 1)
	var data := host_view.to_dict()
	assert_eq(Fx.find_illegal_value(data), "", "only plain values go over the network")
	var client_view := PlayerRoster.from_dict(data, PEER_B)
	assert_not_null(client_view)
	assert_eq(client_view.owners, host_view.owners)
	assert_eq(client_view.local_players(), [2] as Array[int], "seen from P3's machine")
	assert_eq(client_view.player_of_device(PlayerRoster.KEYBOARD), 2)
	assert_null(PlayerRoster.from_dict({"devices": [1], "owners": "x", "peers": []}, PEER_A), "malformed data refused")
	assert_null(PlayerRoster.from_dict({"devices": [-1, -1], "owners": [0, 0, 0], "peers": [HOST, HOST]}, PEER_A),
			"one machine as two players refused")


func test_dropped_player_hands_heroes_to_the_host() -> void:
	var roster := PlayerRoster.online(3, HOST, HOST)
	roster.join_peer(PEER_A)
	roster.join_peer(PEER_B)
	assert_eq(roster.owners, [0, 1, 2] as Array[int])
	assert_true(roster.drop_peer(PEER_A))
	assert_eq(roster.peers, [HOST, PEER_B] as Array[int])
	assert_eq(roster.owners, [0, 0, 1] as Array[int], "P2's hero goes to the host, P3 becomes P2")
	assert_false(roster.drop_peer(HOST), "the host never drops itself")
	assert_false(roster.drop_peer(9999))


# --- arbiter ----------------------------------------------------------------------------------

## A three-hit attack on the whole party: prompts 0-2 hit 0 (900 ms), 3-5 hit 1, 6-8 hit 2.
func _engine() -> CombatEngine:
	var attack := Fx.attack("triple", [Fx.hit(900), Fx.hit(1200), Fx.hit(1500)], Fx.PARTY)
	return Fx.started([attack])


## Prompts of character 1 belong to PEER_A, character 2 to PEER_B (the host plays character 0).
func _arbiter(engine: CombatEngine, now_us: int = 0) -> DefenseArbiter:
	var arbiter := DefenseArbiter.new(3000, 1500, 100)
	var owners: Dictionary = {}
	for p: Dictionary in engine.sequence.prompts:
		if int(p.character) == 1:
			owners[int(p.idx)] = PEER_A
		elif int(p.character) == 2:
			owners[int(p.idx)] = PEER_B
	arbiter.declare(int(engine.sequence.seq), engine.sequence.prompts, owners, 700, now_us)
	return arbiter


func _idxs(results: Array) -> Array[int]:
	var list: Array[int] = []
	for r: Dictionary in results:
		list.append(int(r.prompt))
	return list


func test_deadline_counts_from_the_ack() -> void:
	var engine := _engine()
	var arbiter := _arbiter(engine)
	var p1: Dictionary = engine.sequence.prompts[1]
	var late := 0
	for action: Variant in (p1.windows as Dictionary):
		late = maxi(late, int((p1.windows[action] as Array)[1]))
	# No ack yet: the start counts as declare + ack timeout.
	assert_eq(arbiter.deadline_us(1), 3000 * MS + 700 * MS + 900 * MS + late + 1 * 100 * MS + 1500 * MS)
	arbiter.ack(PEER_A, int(engine.sequence.seq), 5000 * MS)
	assert_eq(arbiter.deadline_us(1), 5000 * MS + 700 * MS + 900 * MS + late + 100 * MS + 1500 * MS,
			"a late ack moves the deadline")
	assert_eq(arbiter.deadline_us(0), -1, "the host's own prompts are not refereed")
	assert_eq(arbiter.deadline_us(4) - arbiter.deadline_us(1), 300 * MS + 100 * MS,
			"later hits: their own impact plus one more hit-stop allowance")


func test_overdue_prompts_resolve_as_none_once() -> void:
	var engine := _engine()
	var arbiter := _arbiter(engine)
	var seq := int(engine.sequence.seq)
	arbiter.ack(PEER_A, seq, 0)
	arbiter.ack(PEER_B, seq, 0)
	assert_eq(arbiter.overdue(arbiter.deadline_us(1) - 1).size(), 0, "nothing before the deadline")
	var due := arbiter.overdue(arbiter.deadline_us(2))
	assert_eq(_idxs(due), [1, 2] as Array[int])
	assert_eq(int(due[0].outcome), NONE)
	assert_eq(arbiter.overdue(arbiter.deadline_us(2)).size(), 0, "each prompt once")
	var events := engine.submit(CombatCommands.resolve_prompts(seq, due))
	assert_eq(Fx.of_type(events, "command_rejected").size(), 0, "the engine takes the arbiter's results")


func test_accepts_only_own_open_prompts_of_this_sequence() -> void:
	var engine := _engine()
	var arbiter := _arbiter(engine)
	var seq := int(engine.sequence.seq)
	var results := [CombatCommands.prompt_result(1, PARRY, 0), CombatCommands.prompt_result(2, PARRY, 0),
			CombatCommands.prompt_result(0, PARRY, 0), {"prompt": "x"}, "junk"]
	assert_eq(_idxs(arbiter.accept(PEER_A, seq, results)), [1] as Array[int],
			"only PEER_A's prompt (not PEER_B's, not the host's, not junk)")
	assert_eq(arbiter.accept(PEER_A, seq, results).size(), 0, "a duplicate is dropped")
	assert_eq(arbiter.accept(PEER_B, seq + 1, results).size(), 0, "a stale sequence is dropped")
	assert_false(_idxs(arbiter.overdue(1 << 40)).has(1), "an accepted prompt is never resolved again")


func test_a_leaving_client_is_resolved_at_once() -> void:
	var engine := _engine()
	var arbiter := _arbiter(engine)
	arbiter.drop_peer(PEER_B)
	assert_eq(_idxs(arbiter.overdue(0)), [2, 5, 8] as Array[int], "PEER_B's prompts now, PEER_A's wait")
	assert_true(arbiter.has_open())


func test_engine_resolved_prompts_are_left_alone() -> void:
	var engine := _engine()
	var arbiter := _arbiter(engine)
	arbiter.mark_resolved([1, 4])
	assert_eq(_idxs(arbiter.overdue(1 << 40)), [2, 5, 7, 8] as Array[int])
	arbiter.clear()
	assert_eq(arbiter.seq(), -1)
	assert_false(arbiter.has_open())


# --- fingerprint ------------------------------------------------------------------------------

func test_fingerprint_is_stable_and_sees_changes() -> void:
	var dir := "user://test_data_hash"
	DirAccess.make_dir_recursive_absolute(dir + "/sub")
	_write(dir + "/a.tres", "value = 1\n")
	_write(dir + "/sub/b.tres", "x\n")
	var first := DataHash.compute(dir, "1.0")
	assert_eq(DataHash.compute(dir, "1.0"), first, "same files, same fingerprint")
	assert_ne(DataHash.compute(dir, "1.1"), first, "another version differs")
	_write(dir + "/a.tres", "value = 1\r\n")
	assert_eq(DataHash.compute(dir, "1.0"), first, "line endings do not count")
	_write(dir + "/a.tres", "value = 2\n")
	assert_ne(DataHash.compute(dir, "1.0"), first, "a changed number differs")
	_write(dir + "/a.tres", "value = 1\n")
	_write(dir + "/sub/b.tres.import", "anything")
	assert_eq(DataHash.compute(dir, "1.0"), first, "import side files do not count")
	var other := "user://test_data_hash_code"
	DirAccess.make_dir_recursive_absolute(other)
	_write(other + "/c.gd", "var a = 1
")
	var roots: Array[String] = [dir, other]
	var both: String = DataHash.compute_roots(roots, "1.0")
	_write(other + "/c.gd", "var a = 2
")
	assert_ne(DataHash.compute_roots(roots, "1.0"), both, "a changed script differs")
	assert_eq(DataHash.short_id(both).length(), 8)
	assert_eq(DataHash.of_game().length(), 64, "the game's own fingerprint is a SHA-256")
	# Saves check data and version only, so a code-only update keeps a saved run (card #208).
	assert_eq(DataHash.of_content().length(), 64)
	assert_ne(DataHash.of_content(), DataHash.of_game(), "the save fingerprint leaves the code out")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# --- run state --------------------------------------------------------------------------------

func _run() -> RunState:
	var data := load("res://data/runs/rotten_road.tres") as RunData
	return RunState.begin(data, _tuning, 4242)


func test_run_state_round_trip() -> void:
	var run := _run()
	run.go(run.choices()[0])
	run.gold = 123
	run.hp[1] = 7
	run.add_xp(0, 200)
	run.add_xp(2, 70)
	run.auto_spend(0)
	run.set_attributes(2, [1, 0, 0, 0, 1])
	run.give_relic(run.data.gear[0], 0)
	run.give_relic(run.data.gear[1], 2)
	run.give_relic(run.data.gear[2], 2)
	run.add_item(run.data.shop_items[1])
	run.add_item(run.data.shop_items[0])
	var data := run.to_dict()
	assert_eq(Fx.find_illegal_value(data), "", "only plain values go over the network")
	var copy := RunState.from_dict(run.data, _tuning, data)
	assert_not_null(copy)
	assert_eq(copy.to_dict(), data, "the other machine sees the same run")
	assert_eq(copy.max_hp(2), run.max_hp(2), "the heroes' Relics count there too")
	assert_eq(copy.relics_of(2), [run.data.gear[1], run.data.gear[2]] as Array[GearData], "in the order given")
	assert_eq(copy.choices(), run.choices(), "the same map from the seed")


func test_run_state_refuses_what_does_not_fit() -> void:
	var run := _run()
	var before := run.to_dict()
	var bad := before.duplicate(true)
	bad.gear[0] = ["no_such_gear"]
	assert_false(run.apply_dict(bad), "unknown gear")
	bad = before.duplicate(true)
	bad.gear[0] = [run.data.gear[0].id]
	bad.gear[1] = [run.data.gear[0].id]
	bad.relics = {run.data.gear[0].id: 1}
	assert_false(run.apply_dict(bad), "one Relic given to two heroes")
	bad = before.duplicate(true)
	bad.gear[0] = [run.data.gear[0].id]
	assert_false(run.apply_dict(bad), "a hero's Relic the run does not have")
	bad = before.duplicate(true)
	bad.backpack[3] = [[1, "no_such_item", 0, 0, 0]]
	assert_false(run.apply_dict(bad), "unknown item")
	bad = before.duplicate(true)
	bad.hp = [1, 2]
	assert_false(run.apply_dict(bad), "wrong party size")
	bad = before.duplicate(true)
	bad.seed = 1
	assert_false(run.apply_dict(bad), "another run")
	bad = before.duplicate(true)
	bad.gold = "lots"
	assert_false(run.apply_dict(bad), "not a number")
	assert_eq(run.to_dict(), before, "a refused state changes nothing")
