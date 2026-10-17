extends GutTest
## Where the phase 16 features meet (card #197): a save from another build is kept, not deleted;
## what a stop already did is part of the saved run (an event result, a sold shelf item); the run
## knows when a fight decides it; phase-two-only attacks are found and checked like the others.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const RUN_PATH := "res://data/runs/rotten_road.tres"
const FINGERPRINT := "abc123"

var _tuning: Tuning
var _data: RunData
var _path: String


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func before_each() -> void:
	_path = OS.get_temp_dir().path_join("rotsworn_test_seams_%d.json" % Time.get_ticks_usec())
	RunSave.delete(_path)


func after_each() -> void:
	RunSave.delete(_path)


func _run() -> RunState:
	return RunState.begin(_data, _tuning, 4242)


## A run (the first seed that has one) whose first map has a stop of type `type`.
func _run_with(type: int) -> RunState:
	for seed_value: int in range(1, 200):
		var run := RunState.begin(_data, _tuning, seed_value)
		for stop: Dictionary in run.map.stops:
			if int(stop.type) == type:
				return run
	fail_test("no seed has a stop of type %d" % type)
	return _run()


## Puts the party on the first stop of type `type` of the current map.
func _go_to(run: RunState, type: int) -> void:
	for stop: Dictionary in run.map.stops:
		if int(stop.type) == type:
			run.at = int(stop.id)
			return
	fail_test("no stop of type %d" % type)


# --- a save from another build is kept --------------------------------------------------------

func test_a_fingerprint_mismatch_is_kept_not_deleted() -> void:
	RunSave.save(_run().to_dict(), FINGERPRINT, true, 1, _path)
	var loaded := RunSave.load_save("another build", _path)
	assert_eq(loaded.status, RunSave.REJECTED)
	assert_true(bool(loaded.keep), "an intact file of another build is kept")
	assert_true(RunSave.exists(_path), "loading never removes the file")
	# The build that made it can still read it.
	assert_eq(RunSave.load_save(FINGERPRINT, _path).status, RunSave.LOADED)


func test_a_format_mismatch_is_kept_too() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": RunSave.FORMAT_VERSION + 1, "fingerprint": FINGERPRINT,
			"in_stop": false, "players": 1, "run": {}}))
	file.close()
	var loaded := RunSave.load_save(FINGERPRINT, _path)
	assert_eq(loaded.status, RunSave.REJECTED)
	assert_true(bool(loaded.keep))
	assert_true(RunSave.exists(_path))


func test_a_damaged_file_is_not_marked_keep() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	var loaded := RunSave.load_save(FINGERPRINT, _path)
	assert_eq(loaded.status, RunSave.REJECTED)
	assert_false(bool(loaded.keep), "a damaged file may be deleted")


# --- what a stop already did is saved --------------------------------------------------------

func _risky_choice(percent: int) -> EventChoiceData:
	var choice := EventChoiceData.new()
	choice.done_text = "You reach in."
	choice.risk_text = "It bites."
	choice.risk_percent = percent
	var risk := ZoneOfferData.new()
	risk.cost_gold = 50
	choice.risk_deal = risk
	return choice


func test_an_event_choice_is_final_in_the_saved_run() -> void:
	var run := _run_with(RunMap.StopType.EVENT)
	_go_to(run, RunMap.StopType.EVENT)
	assert_false(run.stop_done, "nothing done at the stop yet")
	run.gold = 200
	var got := run.choose_event(_risky_choice(100), run.at, 0)
	assert_true(bool(got.ok))
	assert_true(bool(got.risk), "the risk struck")
	assert_lt(run.gold, 200, "the risk took gold")
	assert_true(run.stop_done)
	assert_string_contains(run.stop_text, "It bites.")
	# The checkpoint written right after: a continued run has the result and the stop is marked done.
	RunSave.save(run.to_dict(), FINGERPRINT, true, 1, _path)
	var loaded := RunSave.load_save(FINGERPRINT, _path)
	var copy := RunState.from_dict(_data, _tuning, loaded.run as Dictionary)
	assert_not_null(copy)
	assert_eq(copy.gold, run.gold, "the risk's price stays paid")
	assert_true(copy.stop_done, "the choice cannot be made again")
	assert_eq(copy.stop_text, run.stop_text)
	assert_eq(copy.to_dict(), run.to_dict())


func test_a_choice_without_a_result_text_still_marks_the_stop_done() -> void:
	var run := _run_with(RunMap.StopType.EVENT)
	_go_to(run, RunMap.StopType.EVENT)
	run.choose_event(EventChoiceData.new(), run.at, 0)
	assert_true(run.stop_done)
	assert_eq(run.stop_text, "You walk on.")


func test_the_next_stop_starts_clean() -> void:
	var run := _run()
	run.choose_event(EventChoiceData.new(), run.at, 0)
	run.mark_sold(2)
	var next := run.choices()[0]
	assert_true(run.go(next))
	assert_false(run.stop_done)
	assert_eq(run.stop_text, "")
	assert_true(run.shop_sold.is_empty())


func test_sold_shelf_items_survive_a_save_and_a_restock_clears_them() -> void:
	var run := _run()
	run.gold = 1000
	run.mark_sold(1)
	run.mark_sold(1)
	run.mark_sold(3)
	assert_eq(run.shop_sold, [1, 3] as Array[int], "each shelf once")
	var copy := RunState.from_dict(_data, _tuning, run.to_dict())
	assert_not_null(copy)
	assert_eq(copy.shop_sold, [1, 3] as Array[int])
	run.unmark_sold(1)
	assert_eq(run.shop_sold, [3] as Array[int], "a refunded purchase is back on sale")
	assert_true(run.restock())
	assert_true(run.shop_sold.is_empty(), "new wares, nothing sold yet")


func test_an_older_save_without_the_new_keys_still_loads() -> void:
	var d := _run().to_dict()
	d.erase("shop_sold")
	d.erase("stop_done")
	d.erase("stop_text")
	var copy := RunState.from_dict(_data, _tuning, d)
	assert_not_null(copy)
	assert_false(copy.stop_done)
	assert_true(copy.shop_sold.is_empty())


func test_bad_stop_progress_data_is_refused() -> void:
	var d := _run().to_dict()
	d["shop_sold"] = ["x"]
	assert_null(RunState.from_dict(_data, _tuning, d))
	d = _run().to_dict()
	d["stop_done"] = 1
	assert_null(RunState.from_dict(_data, _tuning, d))


# --- the run knows when a fight decides it -------------------------------------------------------

func test_a_defeat_decides_the_run_and_an_escape_never_does() -> void:
	var run := _run()
	_go_to(run, RunMap.StopType.ZONE)
	assert_true(run.decides_run(RunState.DEFEAT))
	assert_false(run.decides_run(RunState.ESCAPED))
	assert_false(run.decides_run(RunState.VICTORY), "a zone fight is not the last one")


func test_only_the_last_acts_boss_decides_a_win() -> void:
	var run := _run()
	var last := run.acts().size() - 1
	if last > 0:
		_go_to(run, RunMap.StopType.FINAL)
		assert_false(run.decides_run(RunState.VICTORY), "an earlier act's boss goes on to the next act")
		run.act = last
		run.map = run._make_map(last)
	_go_to(run, RunMap.StopType.FINAL)
	assert_true(run.is_last_act())
	assert_true(run.decides_run(RunState.VICTORY))
	assert_true(run.decides_run(RunState.DEFEAT))
	assert_false(run.decides_run(RunState.ESCAPED))
	run.result = RunState.DEFEAT
	assert_false(run.decides_run(RunState.DEFEAT), "an ended run is not decided again")


# --- phase two attacks ----------------------------------------------------------------------------

func test_all_attacks_includes_phase_two_only_attacks_once() -> void:
	var shared := Fx.attack("shared", [Fx.hit(900)])
	var only_two := Fx.attack("only_two", [Fx.hit(900)])
	var enemy := Fx.enemy("boss", [shared])
	enemy.phase_two_attacks.assign([shared, only_two, null])
	var ids: Array[String] = []
	for attack: EnemyAttackData in enemy.all_attacks():
		ids.append(attack.id)
	assert_eq(ids, ["shared", "only_two"] as Array[String])


func test_the_shipped_phase_two_bosses_list_their_phase_two_attacks() -> void:
	for file: String in ["ash_warden", "mire_mother"]:
		var enemy := load("res://data/enemies/%s.tres" % file) as EnemyData
		assert_gt(enemy.phase_two_attacks.size(), 0, file)
		var all := enemy.all_attacks()
		for attack: EnemyAttackData in enemy.phase_two_attacks:
			assert_true(all.has(attack), "%s: %s is found for the fight's presentation" % [file, attack.id])


func _setup_with_phase_two(attack: EnemyAttackData) -> CombatSetup:
	var setup := Fx.setup([Fx.attack("light", [Fx.hit(900)])])
	setup.enemies[0].phase_two_attacks.assign([attack])
	return setup


func test_validate_checks_phase_two_attacks_hits() -> void:
	assert_true(_setup_with_phase_two(Fx.attack("fine", [Fx.hit(900)])).validate().is_empty())
	var empty_slot := Fx.attack("hole", [Fx.hit(900)])
	empty_slot.hits.append(null)
	assert_false(_setup_with_phase_two(empty_slot).validate().is_empty(), "a null hit slot")
	var no_hits := Fx.attack("none", [])
	assert_false(_setup_with_phase_two(no_hits).validate().is_empty(), "no hits")
	var backwards := Fx.attack("backwards", [Fx.hit(1500), Fx.hit(900)])
	assert_false(_setup_with_phase_two(backwards).validate().is_empty(), "hit times must increase")
	var bad_status := Fx.attack("bad_status", [Fx.hit(900)])
	bad_status.hits[0].on_hit_status = "rotten"
	assert_false(_setup_with_phase_two(bad_status).validate().is_empty(), "a mark that is no hero debuff")
