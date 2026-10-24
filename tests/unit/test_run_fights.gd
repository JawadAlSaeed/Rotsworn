extends GutTest
## A run without zones (DESIGN.md 8.22, cards #316 and #317): map rules 3 put a row of Guard stops
## in every act (rules 1 and 2 stay as they were); a Fight stop's fight, every run fight's weather
## and a Fight stop's drop are seeded picks from the run state alone (the same on every machine, an
## online friend builds the same fight); a Fight stop never repeats the last Fight stop's fight while
## its place has another; a Guard stop fights its place's guard (deep in a deep act) and pays like a
## guard did; old saves are kept but not offered; the bots' readiness habit lives in RunAutoplay.
## Uses the shipped run data; files go to the system temp folder, never user://.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const MAIN_PATH := "res://scenes/main.gd"
const SEEDS: int = 60
const HOST: int = 1
const PEER_A: int = 1001

var _data: RunData
var _tuning: Tuning
var _main: GDScript
var _save_path: String = ""


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_main = load(MAIN_PATH) as GDScript


func before_each() -> void:
	_tuning = (load(TUNING_PATH) as Tuning).duplicate() as Tuning


func after_each() -> void:
	if not _save_path.is_empty():
		RunSave.delete(_save_path)
		_save_path = ""


func _run(seed_value: int = 7) -> RunState:
	return RunState.begin(_data, _tuning, seed_value)


## The first stop of `type` on the current act's map (-1: none).
func _first(run: RunState, type: int) -> int:
	for stop: Dictionary in run.map.stops:
		if int(stop.type) == type:
			return int(stop.id)
	return -1


## Walks `run` from the start to a stop of `type` along the map's roads (each step the first choice
## that can still reach one). False if none is reachable.
func _walk_to(run: RunState, type: int) -> bool:
	while not run.is_over():
		var picked := -1
		for id: int in run.choices():
			if int(run.map.stop(id).type) == type:
				run.go(id)
				return true
			if picked < 0 and _leads_to(run.map, id, type):
				picked = id
		if picked < 0:
			return false
		run.go(picked)
		run.end_ambush()
	return false


func _leads_to(map: RunMap, from_id: int, type: int) -> bool:
	for id: int in MapScreen.reachable_from(map, from_id):
		if int(map.stop(id).type) == type:
			return true
	return false


## The host and one friend online, a share of the heroes each.
func _online_two() -> PlayerRoster:
	var roster := PlayerRoster.online(_data.party.size(), HOST, HOST)
	roster.join_peer(PEER_A)
	return roster


## What a friend's machine makes of the catch-up messages (run_start, then each screen's state).
func _friend_after(messages: Array[Dictionary]) -> RunState:
	var start := bytes_to_var(var_to_bytes(messages[0].payload as Dictionary)) as Dictionary
	var game: RunState = _main.call("_client_game", _main.call("_message_mode", start), _data, null, _tuning,
			int(start.seed), int(start.oath))
	if game == null:
		return null
	for message: Dictionary in messages.slice(1):
		var screen := bytes_to_var(var_to_bytes(message.payload as Dictionary)) as Dictionary
		assert_true(game.apply_dict(screen.run as Dictionary), "%s fits the friend's run" % screen.name)
	return game


## Main.AfterFight's value `key` (-1: none).
func _after_fight(key: String) -> int:
	var values: Variant = _main.get_script_constant_map().get("AfterFight", {})
	return int((values as Dictionary).get(key, -1)) if values is Dictionary else -1


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


# --- map rules 3: a row of Guard stops -----------------------------------------------------------

func test_new_runs_have_a_guard_row_with_a_place_for_every_guard() -> void:
	for s: int in range(1, SEEDS):
		var run := _run(s)
		assert_eq(run.map_rules, RunState.MAP_RULES)
		for act: int in run.acts().size():
			var map := run._make_map(act)
			assert_eq(map.rows[_tuning.run_guard_row].size(), map.count_type(RunMap.StopType.GUARD),
					"seed %d act %d: the guard row is all guards and only it" % [s, act + 1])
			for id: int in map.rows[_tuning.run_guard_row]:
				var stop := map.stop(id)
				assert_eq(int(stop.type), RunMap.StopType.GUARD)
				assert_between(int(stop.zone), 0, run.act_data(act).zones.size() - 1, "a guard stands in a place")
				# Only when the roads here already met every place last can one repeat.
				var recent := map.last_zones_before(id)
				if recent.size() < run.act_data(act).zones.size():
					assert_false(recent.has(int(stop.zone)), "seed %d: not the place just fought in" % s)
			for id: int in map.rows[0]:
				assert_eq(int(map.stop(id).type), RunMap.StopType.FIGHT, "row 0 stays all Fight stops")
		if is_failing():
			return


func test_the_guard_row_keeps_every_road_and_never_moves() -> void:
	for s: int in range(1, SEEDS):
		var with_guards := RunMap.generate(CombatRng.new(s), _tuning, 3)
		var without := RunMap.generate(CombatRng.new(s), _tuning, 3, true, true, true, false)
		assert_eq(with_guards.stops.size(), without.stops.size(), "seed %d: the same stops" % s)
		for i: int in with_guards.stops.size():
			assert_eq(with_guards.stops[i].next, without.stops[i].next, "seed %d: the same roads" % s)
		assert_eq(without.count_type(RunMap.StopType.GUARD), 0, "map rules 2 have no guards")
		if is_failing():
			return


func test_a_guard_row_too_close_to_the_boss_is_left_out() -> void:
	_tuning.run_guard_row = _tuning.run_map_rows - 1
	var map := RunMap.generate(CombatRng.new(3), _tuning, 3)
	assert_eq(map.count_type(RunMap.StopType.GUARD), 0, "never the campfire row before the boss")
	_tuning.run_guard_row = -1
	assert_eq(RunMap.generate(CombatRng.new(3), _tuning, 3).count_type(RunMap.StopType.GUARD), 0, "-1: none")


## Row 0 stays all Fight stops: a guard row of 0 means none, so the act never opens on a guard.
func test_a_guard_row_of_0_is_none() -> void:
	_tuning.run_guard_row = 0
	for s: int in range(1, SEEDS):
		var map := RunMap.generate(CombatRng.new(s), _tuning, 3)
		assert_eq(map.count_type(RunMap.StopType.GUARD), 0, "seed %d: no guards" % s)
		for id: int in map.rows[0]:
			assert_eq(int(map.stop(id).type), RunMap.StopType.FIGHT, "seed %d: row 0 stays all Fight stops" % s)
		assert_gt(map.count_type(RunMap.StopType.TREASURE), 0, "seed %d: the treasure row is kept" % s)
		if is_failing():
			return


## A guard row on the treasure row keeps both: the guards hold the row and the chests stand on the
## row before it (after it when that is row 0), then move as treasure rows do. Every guard row the
## map can have, with and without the moving rows (map rules 1).
func test_a_guard_row_on_the_treasure_row_keeps_the_treasure() -> void:
	var last_guard := _tuning.run_map_rows - 2
	for guard_row: int in range(1, last_guard + 1):
		_tuning.run_guard_row = guard_row
		_tuning.run_treasure_row = guard_row
		var home := guard_row - 1 if guard_row > 1 else guard_row + 1
		for s: int in range(1, SEEDS):
			for moving: bool in [true, false]:
				var map := RunMap.generate(CombatRng.new(s), _tuning, 3, true, true, moving)
				var what := "guard row %d seed %d%s" % [guard_row, s, "" if moving else " (rules 1)"]
				assert_eq(map.count_type(RunMap.StopType.GUARD), map.rows[guard_row].size(), what + ": the row is all guards")
				var treasure_rows: Array[int] = []
				for r: int in map.row_count():
					var all_treasure := true
					for id: int in map.rows[r]:
						all_treasure = all_treasure and int(map.stop(id).type) == RunMap.StopType.TREASURE
					if all_treasure:
						treasure_rows.append(r)
				assert_eq(treasure_rows.size(), 1, what + ": one treasure row")
				assert_eq(map.count_type(RunMap.StopType.TREASURE),
						map.rows[treasure_rows[0]].size() if treasure_rows.size() == 1 else -1, what + ": chests only there")
				if treasure_rows.size() == 1:
					assert_ne(treasure_rows[0], guard_row, what)
					assert_gte(treasure_rows[0], 1, what + ": never row 0")
					if moving:
						assert_lte(absi(treasure_rows[0] - home), _tuning.run_treasure_row_spread, what)
					else:
						assert_eq(treasure_rows[0], home, what + ": the row before the guards")
				for id: int in map.rows[0]:
					assert_eq(int(map.stop(id).type), RunMap.StopType.FIGHT, what + ": row 0 stays all Fight stops")
				if is_failing():
					return


func test_runs_made_by_older_rules_keep_their_maps() -> void:
	var run := _run(9)
	var act := run.act_data()
	for rules: int in [1, 2]:
		var old := run.to_dict()
		old["map_rules"] = rules
		var copy := RunState.from_dict(_data, _tuning, old)
		assert_not_null(copy, "rules %d still read" % rules)
		if copy == null:
			continue
		assert_eq(copy.map_rules, rules)
		var plain := RunMap.generate(CombatRng.new(9), _tuning, act.zones.size(), not act.elites.is_empty(),
				not act.events.is_empty(), rules >= 2, false)
		assert_eq(copy.map.stops, plain.stops, "rules %d: the map it was made with" % rules)
		assert_eq(copy.map.count_type(RunMap.StopType.GUARD), 0)
	for rules: int in [0, RunState.MAP_RULES + 1]:
		var bad := run.to_dict()
		bad["map_rules"] = rules
		assert_null(RunState.from_dict(_data, _tuning, bad), "map rules %d are refused" % rules)


# --- Fight stops -------------------------------------------------------------------------------------

func test_a_fight_stop_fights_one_of_its_places_monsters_the_same_on_every_machine() -> void:
	var picked := {}
	for s: int in range(1, SEEDS):
		var run := _run(s)
		var copy := RunState.from_dict(_data, _tuning, run.to_dict())
		for stop: Dictionary in run.map.stops:
			var fight := run.fight_of(int(stop.id))
			if int(stop.type) != RunMap.StopType.FIGHT:
				assert_null(fight, "only Fight stops have one")
				continue
			assert_not_null(fight)
			if fight == null:
				continue
			var base := fight
			for e: EncounterData in run.zone_of(stop).roamer_pool:
				if e != null and e.deep == fight:
					base = e
			assert_has(run.zone_of(stop).roamer_pool, base, "seed %d: from its place's monsters" % s)
			assert_false(fight.boss or fight.mini_boss or fight.elite, "a plain fight")
			assert_eq(copy.fight_of(int(stop.id)), fight, "the same pick from the same state")
			picked[fight.id] = true
		if is_failing():
			return
	assert_gt(picked.size(), 5, "the picks vary")


func test_a_fight_stop_never_repeats_the_last_fight_stops_fight() -> void:
	var guarded := 0
	for s: int in range(1, SEEDS):
		var run := _run(s)
		var a := int(run.map.rows[0][0])
		var b := int(run.map.rows[2][0])
		run.map.stops[b].type = RunMap.StopType.FIGHT
		run.map.stops[b].zone = run.map.stops[a].zone
		var unseen := run.fight_of(b)
		run.path.assign([a, int(run.map.rows[1][0])])
		var first := run.fight_of(a)
		var then := run.fight_of(b)
		assert_ne(then.id, first.id, "seed %d: never the same fight twice in a row" % s)
		if unseen.id == first.id:
			guarded += 1
		if is_failing():
			return
	assert_gt(guarded, 0, "the rule changed a pick that would have repeated")


func test_deep_rows_and_acts_bring_deep_versions() -> void:
	var run := _run(5)
	var deep_row := -1
	for stop: Dictionary in run.map.stops:
		if int(stop.row) >= _tuning.run_deep_row and int(stop.row) < run.map.row_count() - 2:
			deep_row = int(stop.id)
			break
	assert_gt(deep_row, -1)
	run.map.stops[deep_row].type = RunMap.StopType.FIGHT
	run.map.stops[deep_row].zone = 0
	var base := run._fight_base(deep_row)
	var has_deep := base.deep != null and not base.deep.enemies.is_empty()
	assert_eq(run.fight_of(deep_row), base.deep if has_deep else base, "a deep row fights the deep version")
	var shallow := int(run.map.rows[0][0])
	assert_eq(run.fight_of(shallow), run._fight_base(shallow), "row 0 fights the plain one")
	run.act = 1
	run.map = run._make_map(1)
	var guard_stop := _first(run, RunMap.StopType.GUARD)
	var place := run.zone_of(run.map.stop(guard_stop))
	assert_eq(run.guard_of(guard_stop), place.guard.deep, "the second act's guards are deep")


func test_a_fight_stop_rolls_a_drop_and_other_stops_none() -> void:
	var drops := 0
	for s: int in range(1, SEEDS):
		var run := _run(s)
		run.go(run.choices()[0])
		assert_eq(int(run.current().type), RunMap.StopType.FIGHT)
		assert_eq(run.fight_drop(), run.drop_for(run.at), "the stop's own drop roll")
		drops += 1 if run.fight_drop() != null else 0
		run.at = _first(run, RunMap.StopType.GUARD)
		assert_null(run.fight_drop(), "a guard pays spoils, no drop")
		run.at = _first(run, RunMap.StopType.ELITE)
		if run.at >= 0:
			assert_null(run.fight_drop(), "an elite rolls no drop")
	assert_gt(drops, 0, "some fights drop something")
	assert_lt(drops, SEEDS - 1, "not every fight does")


# --- weather, look and air -------------------------------------------------------------------------

func test_every_run_fight_but_the_boss_rolls_a_seeded_weather() -> void:
	var seen := {}
	for s: int in range(1, SEEDS):
		var run := _run(s)
		var copy := RunState.from_dict(_data, _tuning, run.to_dict())
		for stop: Dictionary in run.map.stops:
			run.at = int(stop.id)
			copy.at = int(stop.id)
			var type := int(stop.type)
			var weather := run.weather_now()
			assert_eq(copy.weather_now(), weather, "the same weather from the same state")
			if type == RunMap.StopType.FINAL:
				assert_null(weather, "the boss's lair has no weather")
				assert_eq(run.look_now(), run.final_look())
				assert_true(run.air_now().is_empty())
				continue
			var place := run.zone_now()
			if type == RunMap.StopType.FIGHT or type == RunMap.StopType.GUARD or type == RunMap.StopType.ELITE:
				assert_eq(place, run.zone_of(stop), "fought in the stop's place")
				assert_eq(run.look_now(), place.look)
				assert_eq(run.air_now().size(), place.ambient.size())
				if weather != null:
					assert_has(place.weathers, weather, "one of its place's weathers")
				seen[weather.id if weather != null else "clear"] = true
			else:
				assert_null(place, "no fight here")
				assert_null(weather)
		if is_failing():
			return
	assert_gt(seen.size(), 2, "the weather varies: %s" % str(seen.keys()))
	assert_true(seen.has("clear"), "clear weather happens too")


func test_an_ambush_is_fought_in_a_place_under_a_weather() -> void:
	var run := _run(11)
	run.at = _first(run, RunMap.StopType.EVENT)
	run._set_ambush(run.act_data().ambushes[0], false)
	assert_eq(run.encounter_now(), run.ambush_encounter())
	assert_not_null(run.zone_now(), "one of the act's places")
	assert_eq(run.look_now(), run.ambush_look())
	assert_eq(run.zone_now().ambient.size(), run.air_now().size(), "and its air")
	var weather := run.weather_now()
	if weather != null:
		assert_has(run.zone_now().weathers, weather)
	assert_null(run.fight_drop(), "an ambush rolls no drop")


func test_the_fight_weather_stream_is_its_own() -> void:
	var consts: Dictionary = (load("res://scripts/run/run_state.gd") as Script).get_script_constant_map()
	var salts: Array[int] = []
	for key: String in consts:
		if key.ends_with("_SALT"):
			salts.append(int(consts[key]))
	for salt: int in [RunState.FIGHT_SALT, RunState.FIGHT_WEATHER_SALT]:
		assert_eq(salts.count(salt), 1, "%d is used once" % salt)
		for rush_salt: int in [RushState.RUSH_FIGHT_SALT, RushState.RUSH_LOOK_SALT, RushState.RUSH_OFFER_SALT,
				RushState.RUSH_WEATHER_SALT]:
			assert_ne(salt, rush_salt)


# --- Guard stops -------------------------------------------------------------------------------------

func test_a_guard_stop_fights_its_places_guard_and_pays_like_a_guard() -> void:
	var run := _run(7)
	assert_true(_walk_to(run, RunMap.StopType.GUARD), "a road reaches the guard row")
	var place := run.zone_of(run.current())
	var guard := run.encounter_now()
	assert_eq(guard, place.guard, "its place's guard, plain in the first act")
	assert_true(guard.mini_boss and not guard.can_run, "no running from a guard")
	assert_eq(run.mastery_gain(guard), _tuning.mastery_guard, "a guard's Echo pips")
	var slots_before := run.open_relic_slots()
	var plain_count := run.loot_choice_count()
	run.finish_fight(RunState.VICTORY, run.hp.duplicate(), guard, {"hits_taken": 0})
	assert_eq(run.guards_beaten, 1)
	assert_eq(run.open_relic_slots(), slots_before + 1, "the first guard opens a Relic slot")
	assert_true(run.flawless, "no hit taken: flawless")
	assert_eq(run.loot_choice_count(), plain_count + 1, "one more spoils choice")
	assert_eq(run.loot_choices(run.at).size(), run.loot_choice_count())
	var copy := RunState.from_dict(_data, _tuning, run.to_dict())
	assert_eq(copy.guards_beaten, 1, "kept and sent online")


func test_every_place_has_its_guard() -> void:
	var guards := {"rotten_hollow": "guard_gorged_one", "sunken_bog": "guard_mire_mother",
			"ashen_ruins": "guard_ash_warden"}
	for zone: ZoneData in _data.zones:
		assert_not_null(zone.guard, "%s has a guard" % zone.id)
		if zone.guard != null:
			assert_eq(zone.guard.id, String(guards.get(zone.id, "")), "%s: its own guard" % zone.id)
			assert_eq(zone.guard.deep.id, "deep_" + zone.guard.id, "with its deep version")


func test_every_place_still_names_its_song_and_loop() -> void:
	# Unplayed since the zones went (DESIGN.md 8.22 G6, G7), but kept so the talk can bring them back.
	var songs := {"rotten_hollow": "hollow", "sunken_bog": "bog", "ashen_ruins": "ruins"}
	for zone: ZoneData in _data.zones:
		var short := String(songs.get(zone.id, "?"))
		assert_eq(zone.music_path, "res://assets/audio/music/zone_%s.ogg" % short, "%s: its song" % zone.id)
		assert_eq(zone.ambience_path, "res://assets/audio/ambience/ambience_%s.ogg" % short, "%s: its loop" % zone.id)
		assert_true(ResourceLoader.exists(zone.music_path), "%s: the song is still in assets/" % zone.id)
		assert_true(ResourceLoader.exists(zone.ambience_path), "%s: the loop is still in assets/" % zone.id)


# --- saves and online --------------------------------------------------------------------------------

func test_a_save_from_before_is_kept_but_not_offered() -> void:
	assert_eq(RunSave.FORMAT_VERSION, 3)
	_save_path = OS.get_temp_dir().path_join("rotsworn_test_run_fights_%d.json" % Time.get_ticks_usec())
	# Format 1: saved inside a zone. Format 2: the first phase 26 builds, whose Hanging Cage still
	# gave a Key. The Key's file is gone (card #319), so such a pack no longer loads: the main menu
	# would delete the run as broken (it never checks the fingerprint, card #208) if the format let it in.
	var run := _run()
	run.add_item(run.items_by_id()["salve"] as ItemData)
	var with_key := run.to_dict()
	assert_not_null(RunState.from_dict(_data, _tuning, with_key), "the same pack with a Salve fits")
	var rows: Array = (with_key.backpack as Array)[3]
	(rows[0] as Array)[1] = "key"
	assert_null(RunState.from_dict(_data, _tuning, with_key), "a pack holding a Key no longer fits")
	for format: int in [1, 2]:
		var old := {"format": format, "fingerprint": "x", "in_stop": false, "players": 1, "run": with_key}
		var file := FileAccess.open(_save_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(old))
		file.close()
		var loaded := RunSave.load_save("", _save_path)
		assert_eq(loaded.status, RunSave.REJECTED, "a format %d run is not offered" % format)
		assert_true(bool(loaded.keep), "but stays on disk (format %d)" % format)
		assert_true(RunSave.exists(_save_path))
	assert_true(RunSave.save(_run().to_dict(), "x", true, 1, _save_path))
	assert_eq(RunSave.load_save("", _save_path).status, RunSave.LOADED, "a new save reads")


func test_a_friend_builds_the_hosts_fight_stop_from_the_state_alone() -> void:
	assert_eq(NetSession.PROTOCOL, 5)
	assert_has(_main.get_script_constant_map().get("NET_FIGHT_SCREENS") as Array, "stop_fight")
	for s: int in [3, 7, 21]:
		var host := _run(s)
		for type: int in [RunMap.StopType.FIGHT, RunMap.StopType.GUARD]:
			assert_true(_walk_to(host, type))
			var messages: Array[Dictionary] = _main.call("_catch_up_messages", host, _online_two(), true,
					{"name": "map"}, {"name": "stop_fight", "seed": 321}, true)
			assert_eq(messages.size(), 3)
			var fight := messages[2].payload as Dictionary
			assert_eq(String(fight.name), "stop_fight")
			assert_true(bool(fight.rejoin), "a friend who gets in mid-fight gets it as it stands")
			var friend := _friend_after(messages)
			assert_not_null(friend)
			if friend == null:
				return
			assert_eq(friend.encounter_now(), host.encounter_now(), "seed %d: the same fight" % s)
			assert_eq(friend.weather_now(), host.weather_now(), "the same weather")
			assert_eq(friend.fight_drop(), host.fight_drop(), "the same drop")
			assert_eq(friend.zone_now(), host.zone_now(), "the same place")
			assert_eq(friend.look_now(), host.look_now())


func test_main_builds_stop_fights_from_the_run_state() -> void:
	var enter := _body("func _enter_stop(")
	assert_string_contains(enter, "RunMap.StopType.FIGHT, RunMap.StopType.GUARD:")
	assert_string_contains(enter, "_fade_to(_start_stop_fight, ")
	var start := _body("func _start_stop_fight(")
	assert_string_contains(start, "_run.encounter_now()")
	assert_string_contains(start, "_run.fight_drop()")
	# The host's fight seed and its message (card #320: a Fight stop's at its swirl, a Guard stop's here).
	var announce := _body("func _announce_stop_fight(")
	assert_string_contains(announce, "\"stop_fight\"")
	assert_string_contains(start, "_announce_stop_fight(false)")
	assert_string_contains(enter, "_announce_stop_fight(true)")
	var place := _body("func _set_run_fight_place(")
	assert_string_contains(place, "_run.weather_now()")
	assert_string_contains(place, "_weather_or_forced(")
	for body: String in [start, place, announce]:
		assert_false(body.contains("randi()") or body.contains("randf"), "nothing rolled outside the run state")
	assert_eq(start.count("randi_range"), 0, "the seed is the announcement's")
	assert_eq(announce.count("randi_range"), 1, "only the host's fight seed")
	var client := _body("func _client_screen(")
	assert_string_contains(client, "\"stop_fight\":")
	assert_string_contains(client, "_fade_to(_start_stop_fight, ")
	var over := _body("func _on_run_fight_over(")
	assert_string_contains(over, "_takes_fight_drop(result, type, ambushed, _drop != null)")
	assert_string_contains(over, "_after_run_fight(result, type, ambushed, ambush_spoils, _run.is_over(), found != null)")
	assert_string_contains(_body("func _begin_rush_fight("), "_weather_or_forced(rush.weather_now())")
	assert_string_contains(_body("func _autoplay_map("), "RunMap.StopType.GUARD, RunMap.StopType.FIGHT]")


# --- what follows a run fight (Main's pure rules) ------------------------------------------------------

## A run fight's end screen leads on by its result, its stop and whether it was an ambush: a Fight
## stop's drop goes in the pack only after its win (the party screen holds one that did not fit); a
## guard, an elite or a boss gives spoils; an ambush only with its event's spoils; an escape or a loss
## that leaves the run going goes to the map; the run's end whenever it is over (DESIGN.md 2.13, 8.22).
func test_what_follows_a_run_fight() -> void:
	var win := RunState.VICTORY
	var ran := RunState.ESCAPED
	var lost := RunState.DEFEAT
	var fight := RunMap.StopType.FIGHT
	var guard := RunMap.StopType.GUARD
	var elite := RunMap.StopType.ELITE
	var boss := RunMap.StopType.FINAL
	var event := RunMap.StopType.EVENT
	var end := _after_fight("END")
	var map := _after_fight("MAP")
	var party := _after_fight("PARTY")
	var spoils := _after_fight("SPOILS")
	var cases := [
		# [result, stop, ambushed, ambush spoils, over, drop left, takes the drop (with one), next, what]
		[win, fight, false, false, false, false, true, map, "a Fight stop's win: the drop fits, the map"],
		[win, fight, false, false, false, true, true, party, "a Fight stop's win: the pack is full"],
		[ran, fight, false, false, false, false, false, map, "running from a Fight stop passes it"],
		[lost, fight, false, false, true, false, false, end, "a lost Fight stop ends the run"],
		[win, guard, false, false, false, false, false, spoils, "a guard gives spoils, no drop"],
		[ran, guard, false, false, false, false, false, map, "no running from a guard, but never spoils"],
		[lost, guard, false, false, true, false, false, end, "a lost guard ends the run"],
		[win, elite, false, false, false, false, false, spoils, "an elite gives spoils, no drop"],
		[ran, elite, false, false, false, false, false, map, "running from an elite passes it"],
		[lost, elite, false, false, true, false, false, end, "a lost elite ends the run"],
		[win, boss, false, false, false, false, false, spoils, "an act's boss gives spoils"],
		[win, boss, false, false, true, false, false, end, "the last boss ends the run"],
		[win, event, true, false, false, false, false, map, "an ambush without spoils: the map"],
		[win, event, true, true, false, false, false, spoils, "an ambush with spoils"],
		[win, fight, true, false, false, false, false, map, "an ambush never drops, even at a Fight stop"],
		[ran, event, true, true, false, false, false, map, "running from an ambush: the map"],
		[lost, event, true, false, true, false, false, end, "a lost ambush ends the run"],
	]
	for c: Array in cases:
		var what := String(c[8])
		assert_eq(_main.call("_takes_fight_drop", c[0], c[1], c[2], true), c[6], what + ": the drop")
		assert_false(_main.call("_takes_fight_drop", c[0], c[1], c[2], false), what + ": no drop rolled")
		assert_eq(_main.call("_after_run_fight", c[0], c[1], c[2], c[3], c[4], c[5]), c[7], what)
	assert_eq(_main.call("_spoils_line", guard, false), "The guard fell. Take one.")
	assert_eq(_main.call("_spoils_line", boss, false), "The boss fell. Take one.")
	assert_eq(_main.call("_spoils_line", elite, false), "The elite fell. Take one.")
	assert_eq(_main.call("_spoils_line", event, true), "The elite fell. Take one.", "an ambush's spoils read as an elite's")
	var item := ItemData.new()
	item.display_name = "Tonic"
	assert_eq(_main.call("_pack_full_note", item), "The enemy dropped a Tonic, but the pack is full.")


## The Journal says where a fight was met: a run fight's place, else its own name.
func test_the_journal_names_a_run_fights_place() -> void:
	assert_eq(_main.call("_journal_place", "Rot Rats", "Sunken Bog"), "Sunken Bog", "a run's Fight, Guard, elite or ambush")
	assert_eq(_main.call("_journal_place", "Rot Rats", ""), "Rot Rats", "a boss, a Rush or a practice fight")
	var record := _body("func _record_journal(")
	assert_string_contains(record, "_fight_place if _run != null and not (_run is RushState) else \"\"",
			"a Rush fight never names a run place")


## --weather=ID forces every run and Rush fight's weather (dev tool, DESIGN.md 8.22): none given keeps
## the rolled one, "clear" clears it, a known id gives that weather, and a typo is an error (clear).
func test_weather_forces_run_and_rush_fights() -> void:
	var main: Node = _main.new()
	autofree(main)
	var options := CombatOptions.new()
	main.set("_options", options)
	var rolled := load("res://data/weather/fog.tres") as WeatherData
	var rain := load("res://data/weather/rain.tres") as WeatherData
	assert_not_null(rolled)
	assert_not_null(rain)
	options.weather_id = ""
	assert_eq(main.call("_weather_or_forced", rolled), rolled, "no --weather: the rolled weather")
	assert_null(main.call("_weather_or_forced", null), "no --weather: a clear roll stays clear")
	options.weather_id = "clear"
	assert_null(main.call("_weather_or_forced", rolled), "clear: no weather")
	options.weather_id = "rain"
	assert_eq(main.call("_weather_or_forced", rolled), rain, "rain over the rolled fog")
	assert_eq(main.call("_weather_or_forced", null), rain, "rain over a clear roll")
	options.weather_id = "rainn"
	assert_null(main.call("_weather_or_forced", rolled), "a typo never keeps the rolled weather")
	assert_push_error("no weather 'rainn'", "a typo is an error, never a quiet test of clear weather")


## A friend's "The host is choosing" line is never left over a fight (it draws above the fight's HUD):
## every fight is built through _start_combat, which hides it. A Fight or Guard stop's fight swirls in
## from the map as every other run fight does (with its sound), then shows the place's name card.
func test_a_fight_hides_the_watch_line_and_stop_fights_swirl_in() -> void:
	assert_string_contains(_body("func _start_combat("), "_watch_layer.visible = false")
	for header: String in ["func _start_stop_fight(", "func _start_final_fight(", "func _begin_rush_fight("]:
		assert_string_contains(_body(header), "_start_combat()", header + " builds through _start_combat")
	# Card #320: a Fight stop's card carries its First Strike ring (none on a Guard stop's).
	assert_string_contains(_body("func _enter_stop("),
			"_fade_to(_start_stop_fight, zone.display_name if zone != null else \"\", true, ring)")
	assert_string_contains(_body("func _client_screen("),
			"_fade_to(_start_stop_fight, zone.display_name if zone != null else \"\", true, ring)")
	var fade := _body("func _fade_to(")
	assert_string_contains(fade, "Sfx.play(\"encounter_swirl\")")
	assert_string_contains(fade, "await _transition.swirl_out()")


# --- the bots' habit -----------------------------------------------------------------------------------

func test_the_bots_readiness_habit_lives_in_run_autoplay() -> void:
	var ready := Vector3i(RunAutoplay.READY_MIN_LOWEST_PERCENT, RunAutoplay.READY_MIN_AVERAGE_PERCENT,
			RunAutoplay.READY_MIN_LEVEL)
	assert_true(RunAutoplay.is_ready(ready))
	assert_false(RunAutoplay.is_ready(ready - Vector3i(1, 0, 0)), "the weakest hero too hurt")
	assert_false(RunAutoplay.is_ready(ready - Vector3i(0, 1, 0)), "the party too hurt")
	assert_false(RunAutoplay.is_ready(ready - Vector3i(0, 0, 1)), "too green")
	assert_false(DirAccess.dir_exists_absolute("res://scripts/explore"), "the zone bot went with the zones")
