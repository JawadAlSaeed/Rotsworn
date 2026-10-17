extends GutTest
## The Rot Journal (card #200): JournalTally collects a fight from mirror events, RotJournal adds,
## merges and serialises, JournalFile writes it crash-safely, the screen shows it. Every file test
## uses a path in the OS temp folder, never the player's real journal.

var _mirror: CombatMirror
var _path: String


func before_each() -> void:
	_path = OS.get_temp_dir().path_join("rotsworn_test_journal_%d.json" % Time.get_ticks_usec())
	JournalFile.delete(_path)
	_mirror = CombatMirror.new()
	_mirror.apply({"type": "combat_started", "seed": 1, "practice_allowed": false, "fighters": [
		_fighter(1, Combatant.Team.PARTY, 0, "hero", "Hero"),
		_fighter(10, Combatant.Team.ENEMY, 0, "rotten_husk", "Rotten Husk"),
		_fighter(11, Combatant.Team.ENEMY, 1, "rotten_husk", "Rotten Husk"),
		_fighter(12, Combatant.Team.ENEMY, 2, "gnat_swarm", "Gnat Swarm"),
	]})


func after_each() -> void:
	if DirAccess.dir_exists_absolute(_path + JournalFile.TEMP_SUFFIX):
		DirAccess.remove_absolute(_path + JournalFile.TEMP_SUFFIX)
	JournalFile.delete(_path)


func _fighter(id: int, team: int, slot: int, data_id: String, display_name: String) -> Dictionary:
	return {"id": id, "team": team, "slot": slot, "data_id": data_id, "display_name": display_name,
			"max_hp": 100, "hp": 100, "ap": 0, "power": 10, "speed": 10}


func _declare(seq: int, source: int, attack: String, hits: Array) -> void:
	_mirror.apply({"type": "timed_sequence_declared", "seq": seq, "kind": CombatEngine.SEQUENCE_ENEMY_ATTACK,
			"source": source, "action": attack, "name": attack.capitalize(), "mode": 0, "targets": [1],
			"alert_cue": false, "allow_timing_ring": false, "hits": hits, "prompts": [{}, {}, {}]})


func _resolve(seq: int, prompt: int, outcome: int) -> void:
	_mirror.apply({"type": "prompt_resolved", "seq": seq, "prompt": prompt, "hit": prompt, "character": 1,
			"outcome": outcome, "perfect": false, "offset_us": 0, "damage": 5, "hp": 50, "max_hp": 100,
			"ap": 0, "ap_delta": 0, "downed": false})


func _hit(kind: int, mark: String = "") -> Dictionary:
	var hit := {"index": 0, "at_ms": 0, "kind": kind}
	if not mark.is_empty():
		hit["mark"] = mark
	return hit


## A fight where a husk slams twice (a ground hit jumped once, taken once) and a gnat stings.
func _play_fight() -> void:
	_declare(1, 10, "husk_ground_slam", [_hit(AttackHitData.Kind.GROUND), _hit(AttackHitData.Kind.GROUND)])
	_resolve(1, 0, Defense.Outcome.JUMP)
	_resolve(1, 1, Defense.Outcome.NONE)
	_declare(2, 12, "gnat_sting", [_hit(AttackHitData.Kind.NORMAL, "rotting"), _hit(AttackHitData.Kind.REND)])
	_resolve(2, 0, Defense.Outcome.PARRY)
	_resolve(2, 1, Defense.Outcome.DODGE)
	_mirror.apply({"type": "downed", "target": 11})


func test_tally_counts_enemies_attacks_and_answers() -> void:
	_play_fight()
	var fight := _mirror.journal.to_dict()
	var husk: Dictionary = fight.enemies.rotten_husk
	assert_eq(husk.met, 1, "two husks are one meeting")
	assert_eq(husk.beaten, 1, "one husk went down")
	var slam: Dictionary = husk.attacks.husk_ground_slam
	assert_eq(slam.seen, 1)
	assert_eq([slam.jumped, slam.hit, slam.parried, slam.dodged], [1, 1, 0, 0])
	assert_eq(slam.kinds, {"ground": 2})
	var sting: Dictionary = fight.enemies.gnat_swarm.attacks.gnat_sting
	assert_eq([sting.parried, sting.dodged], [1, 1])
	assert_eq(sting.kinds, {"normal": 1, "rend": 1})
	assert_eq(sting.marks, {"rotting": 1})


func test_tally_notes_a_broken_doom() -> void:
	_mirror.apply({"type": "doom_broken", "enemy": 10, "attack": "husk_timber_fall", "name": "Timber Fall",
			"damage": 100, "break_hp": 100, "stagger_turns": 1})
	var record: Dictionary = _mirror.journal.to_dict().enemies.rotten_husk.attacks.husk_timber_fall
	assert_eq(record.broken, 1)
	assert_eq(record.seen, 0)


func test_tally_resets_with_the_next_fight() -> void:
	_play_fight()
	_mirror.apply({"type": "combat_started", "seed": 2, "practice_allowed": false, "fighters": [
		_fighter(1, Combatant.Team.PARTY, 0, "hero", "Hero"), _fighter(10, Combatant.Team.ENEMY, 0, "shade", "Shade")]})
	assert_eq(_mirror.journal.to_dict().enemies.keys(), ["shade"])


func test_prompts_of_other_sequences_and_party_skills_are_ignored() -> void:
	_declare(1, 10, "husk_swipe", [_hit(AttackHitData.Kind.NORMAL)])
	_resolve(9, 0, Defense.Outcome.PARRY)
	_mirror.apply({"type": "timed_sequence_declared", "seq": 3, "kind": "skill", "source": 1, "action": "slash",
			"name": "Slash", "mode": 0, "targets": [10], "alert_cue": false, "allow_timing_ring": false,
			"hits": [_hit(AttackHitData.Kind.PRESS)], "prompts": [{}]})
	_resolve(3, 0, Defense.Outcome.PRESS)
	var attacks: Dictionary = _mirror.journal.to_dict().enemies.rotten_husk.attacks
	assert_eq(attacks.keys(), ["husk_swipe"])
	assert_eq(attacks.husk_swipe.parried, 0, "a stale prompt is not counted")


func test_record_adds_up_across_fights() -> void:
	_play_fight()
	var journal := RotJournal.new()
	journal.record_fight(_mirror.journal.to_dict(), "Rotten Hollow")
	journal.record_fight(_mirror.journal.to_dict(), "Bone Marsh")
	journal.record_fight(_mirror.journal.to_dict(), "Rotten Hollow")
	assert_eq(journal.met_count(), 2)
	var husk := journal.enemy("rotten_husk")
	assert_eq(husk.met, 3)
	assert_eq(husk.beaten, 3)
	assert_eq(husk.places, ["Rotten Hollow", "Bone Marsh"], "a place once, in the order met")
	var slam := journal.attack("rotten_husk", "husk_ground_slam")
	assert_eq([slam.seen, slam.jumped, slam.hit], [3, 3, 3])
	assert_eq(slam.kinds.ground, 6)
	assert_true(journal.has_seen_attack("rotten_husk", "husk_ground_slam"))
	assert_false(journal.has_seen_attack("rotten_husk", "husk_swipe"))
	assert_false(journal.has_met("shade"))
	assert_true(journal.enemy("shade").is_empty())


func test_places_are_capped_and_a_blank_place_is_not_kept() -> void:
	var journal := RotJournal.new()
	var fight := {"enemies": {"x": {"name": "X", "met": 1}}}
	for i: int in RotJournal.MAX_PLACES + 3:
		journal.record_fight(fight, "Place %d" % i)
	journal.record_fight(fight, "")
	assert_eq((journal.enemy("x").places as Array).size(), RotJournal.MAX_PLACES)


func test_merge_adds_two_journals() -> void:
	_play_fight()
	var a := RotJournal.new()
	a.record_fight(_mirror.journal.to_dict(), "A")
	var b := RotJournal.new()
	b.record_fight(_mirror.journal.to_dict(), "B")
	a.merge(b)
	assert_eq(a.enemy("rotten_husk").met, 2)
	assert_eq(a.enemy("rotten_husk").places, ["A", "B"])
	assert_eq(a.attack("gnat_swarm", "gnat_sting").parried, 2)
	assert_eq(b.enemy("rotten_husk").met, 1, "the merged-in journal is untouched")


func test_round_trip_through_a_dict_and_json() -> void:
	_play_fight()
	var journal := RotJournal.new()
	journal.record_fight(_mirror.journal.to_dict(), "Rotten Hollow")
	var copy := RotJournal.from_dict(journal.to_dict())
	assert_eq(copy.to_dict(), journal.to_dict())
	var json := JSON.new()
	assert_eq(json.parse(JSON.stringify(journal.to_dict())), OK)
	assert_eq(RotJournal.from_dict(json.data as Dictionary).to_dict(), journal.to_dict(), "JSON floats become counts again")


func test_junk_in_a_file_is_dropped_not_trusted() -> void:
	var journal := RotJournal.from_dict({"enemies": {
		"good": {"name": "Good", "met": 2.0, "beaten": -5, "places": ["Here", 7, ""], "attacks": {
			"a": {"name": "A", "seen": "many", "parried": 3, "hit": 99999999, "kinds": {"normal": 1, "bogus": 4, "ground": -2}, "marks": 5},
			"b": "nope"}},
		"": {"met": 1},
		"bad": 7,
	}, "extra": 1})
	assert_eq(journal.enemies.keys(), ["good"])
	var good := journal.enemy("good")
	assert_eq([good.met, good.beaten], [2, 0])
	assert_eq(good.places, ["Here"])
	var a := journal.attack("good", "a")
	assert_eq([a.seen, a.parried, a.hit], [0, 3, RotJournal.MAX_COUNT])
	assert_eq(a.kinds, {"normal": 1})
	assert_eq(a.marks, {})
	assert_true(journal.attack("good", "b").is_empty())
	assert_eq(RotJournal.from_dict({"enemies": "no"}).met_count(), 0)


func test_which_fights_count() -> void:
	assert_true(RotJournal.counts_fight(true, false, false, false), "a person's run fight")
	assert_false(RotJournal.counts_fight(false, false, false, false), "practice")
	assert_false(RotJournal.counts_fight(true, true, false, false), "a bot")
	assert_false(RotJournal.counts_fight(true, false, true, false), "the tutorial")
	assert_true(RotJournal.counts_fight(false, true, false, true), "a dev journal path is a sandbox")


func test_file_round_trip_and_missing() -> void:
	assert_eq(JournalFile.load_journal(_path).status, JournalFile.MISSING)
	_play_fight()
	assert_true(JournalFile.record(_mirror.journal.to_dict(), "Rotten Hollow", _path))
	assert_true(JournalFile.record(_mirror.journal.to_dict(), "Rotten Hollow", _path))
	var loaded := JournalFile.load_journal(_path)
	assert_eq(loaded.status, JournalFile.LOADED)
	assert_eq((loaded.journal as RotJournal).enemy("rotten_husk").met, 2, "the second write adds to the first")
	assert_false(FileAccess.file_exists(_path + JournalFile.TEMP_SUFFIX), "no temp file left behind")


func test_a_damaged_file_falls_back_to_the_backup() -> void:
	_play_fight()
	JournalFile.record(_mirror.journal.to_dict(), "", _path)
	JournalFile.record(_mirror.journal.to_dict(), "", _path)
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	var loaded := JournalFile.load_journal(_path)
	assert_eq(loaded.status, JournalFile.LOADED, "the backup is the previous good file")
	assert_eq((loaded.journal as RotJournal).enemy("rotten_husk").met, 1)


func test_a_damaged_file_with_no_backup_starts_again_and_is_replaced() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("garbage")
	file.close()
	var loaded := JournalFile.load_journal(_path)
	assert_eq(loaded.status, JournalFile.REJECTED)
	assert_false(bool(loaded.keep), "nothing worth keeping")
	_play_fight()
	assert_true(JournalFile.record(_mirror.journal.to_dict(), "", _path), "the next fight rewrites it")
	assert_eq(JournalFile.load_journal(_path).status, JournalFile.LOADED)


func test_a_file_of_another_version_is_kept_and_never_written_over() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": RotJournal.FORMAT_VERSION + 1, "journal": {}}))
	file.close()
	var before := FileAccess.get_file_as_string(_path)
	var loaded := JournalFile.load_journal(_path)
	assert_eq(loaded.status, JournalFile.REJECTED)
	assert_true(bool(loaded.keep))
	assert_eq((loaded.journal as RotJournal).met_count(), 0)
	_play_fight()
	assert_false(JournalFile.record(_mirror.journal.to_dict(), "", _path), "refused")
	assert_eq(FileAccess.get_file_as_string(_path), before, "the file is untouched")


func test_a_failed_write_leaves_the_old_file() -> void:
	_play_fight()
	JournalFile.record(_mirror.journal.to_dict(), "", _path)
	var before := FileAccess.get_file_as_string(_path)
	# A folder where the temp file goes makes the write fail.
	DirAccess.make_dir_absolute(_path + JournalFile.TEMP_SUFFIX)
	assert_false(JournalFile.save(RotJournal.new(), _path))
	assert_eq(FileAccess.get_file_as_string(_path), before)


func test_every_enemy_is_listed_and_every_attack_has_an_id() -> void:
	var enemies := JournalScreen.load_enemies()
	assert_gt(enemies.size(), 10)
	var ids: Dictionary = {}
	for data: EnemyData in enemies:
		assert_false(ids.has(data.id), "unique enemy id " + data.id)
		ids[data.id] = true
		assert_false(data.display_name.is_empty())
		for attack: EnemyAttackData in data.all_attacks():
			assert_false(attack.id.is_empty(), data.id + " has an attack without an id")
	for i: int in range(1, enemies.size()):
		assert_lte(enemies[i - 1].display_name.naturalnocasecmp_to(enemies[i].display_name), 0, "alphabetical")


func test_screen_text() -> void:
	assert_eq(JournalScreen.kinds_text({"rend": 2, "normal": 1, "ground": 0}), "Normal, Rend")
	assert_eq(JournalScreen.kinds_text({}), "")
	assert_eq(JournalScreen.record_text({"parried": 3, "dodged": 2, "hit": 4}), "parried 3  dodged 2  jumped 0  hit 4")
	assert_eq(JournalScreen.record_text({"parried": 1, "broken": 2}), "parried 1  dodged 0  jumped 0  hit 0  broken 2")
	assert_eq(JournalScreen.facts_text({"met": 1, "beaten": 1}), "Met in 1 fight     Beaten 1 time")
	assert_eq(JournalScreen.facts_text({"met": 3, "beaten": 0}), "Met in 3 fights     Beaten 0 times")
	var enemies := JournalScreen.load_enemies()
	assert_string_contains(JournalScreen.summary_text(RotJournal.new(), enemies), "Nothing met yet")
	var journal := RotJournal.new()
	journal.record_fight({"enemies": {enemies[0].id: {"name": "x", "met": 1}}})
	assert_eq(JournalScreen.summary_text(journal, enemies), "Met 1 of %d enemies" % enemies.size())


func test_screen_builds_for_every_enemy_and_closes_on_back() -> void:
	_play_fight()
	var journal := RotJournal.new()
	journal.record_fight(_mirror.journal.to_dict(), "Rotten Hollow")
	var screen := JournalScreen.new()
	add_child_autofree(screen)
	var enemies := JournalScreen.load_enemies()
	screen.setup(journal, enemies)
	var closed: Array[bool] = []
	screen.closed.connect(func() -> void: closed.append(true))
	var down := InputEventAction.new()
	down.action = &"menu_down"
	down.pressed = true
	for i: int in enemies.size():
		screen._unhandled_input(down)
	var back := InputEventAction.new()
	back.action = &"menu_cancel"
	back.pressed = true
	screen._unhandled_input(back)
	assert_eq(closed.size(), 1)


## The fullest page (every attack seen, kinds, marks, a Doom) still fits the panel, and the whole
## screen fits above the footer at 1920x1080.
func test_the_fullest_page_fits_the_screen() -> void:
	var enemies := JournalScreen.load_enemies()
	var journal := RotJournal.new()
	for data: EnemyData in enemies:
		var attacks: Dictionary = {}
		for attack: EnemyAttackData in data.all_attacks():
			attacks[attack.id] = {"name": attack.display_name, "seen": 3, "broken": 1, "parried": 12, "dodged": 34,
					"jumped": 5, "hit": 678, "kinds": {"normal": 4, "ground": 1, "rend": 2, "sweep": 1},
					"marks": {"rotting": 1, "ap_drain": 1}}
		journal.record_fight({"enemies": {data.id: {"name": data.display_name, "met": 12, "beaten": 34, "attacks": attacks}}},
				"A long place name, Another long place name, Third place name")
	var screen := JournalScreen.new()
	add_child_autofree(screen)
	screen.setup(journal, enemies)
	var tallest := 0.0
	var widest := 0.0
	for i: int in enemies.size():
		screen._menu.index = i
		screen._refresh()
		tallest = maxf(tallest, screen._panel.get_combined_minimum_size().y)
		widest = maxf(widest, screen._panel.get_combined_minimum_size().x)
	assert_lte(widest, JournalScreen.PANEL_WIDTH - 40.0, "the page is not wider than the panel (it is %d)" % int(widest))
	assert_lte(tallest, JournalScreen.PANEL_HEIGHT - 40.0, "the page fits the panel (it is %d)" % int(tallest))
	assert_lte(screen._menu.get_parent().get_combined_minimum_size().x, 1920.0 - 60.0, "list and page fit the width")
	var column: Control = screen._summary.get_parent()
	assert_lte(column.get_combined_minimum_size().y, 1080.0 - ListMenu.FOOTER_STRIP_PX, "the screen fits")
