extends GutTest
## The RUN OVER recap (card #191): FightRecap, fed through CombatMirror.apply with hand-made events,
## and the music resume rule (card #192). No scenes, no settings, no saves.

var _mirror: CombatMirror


func before_each() -> void:
	_mirror = CombatMirror.new()
	_mirror.apply({"type": "combat_started", "seed": 1, "practice_allowed": false, "fighters": [
		_fighter(1, Combatant.Team.PARTY, 0, "Hero"),
		_fighter(2, Combatant.Team.PARTY, 1, "Mage"),
		_fighter(10, Combatant.Team.ENEMY, 0, "Husk"),
		_fighter(11, Combatant.Team.ENEMY, 1, "Husk"),
		_fighter(12, Combatant.Team.ENEMY, 2, "Gnat"),
	]})


func _fighter(id: int, team: int, slot: int, display_name: String) -> Dictionary:
	return {"id": id, "team": team, "slot": slot, "data_id": display_name.to_lower(), "display_name": display_name,
			"max_hp": 100, "hp": 100, "ap": 0, "power": 10, "speed": 10}


func _declare(seq: int, source: int, attack: String) -> void:
	_mirror.apply({"type": "timed_sequence_declared", "seq": seq, "kind": CombatEngine.SEQUENCE_ENEMY_ATTACK,
			"source": source, "action": attack.to_lower(), "name": attack, "mode": 0, "targets": [1],
			"alert_cue": false, "allow_timing_ring": false, "hits": [], "prompts": [{}, {}, {}]})


func _resolve(seq: int, prompt: int, target: int, outcome: int, damage: int) -> void:
	_mirror.apply({"type": "prompt_resolved", "seq": seq, "prompt": prompt, "hit": prompt, "character": target,
			"outcome": outcome, "perfect": false, "offset_us": 0, "damage": damage, "hp": 50, "max_hp": 100,
			"ap": 0, "ap_delta": 0, "downed": false})


func test_names_the_enemies_and_groups_equal_ones() -> void:
	assert_eq(_mirror.recap.enemies, ["Husk", "Husk", "Gnat"] as Array[String])
	assert_eq(FightRecap.enemy_line(_mirror.recap.enemies), "Husk x2, Gnat")


func test_defence_counts_only_enemy_attacks() -> void:
	_declare(1, 10, "Maul")
	_resolve(1, 0, 1, Defense.Outcome.PARRY, 0)
	_resolve(1, 1, 1, Defense.Outcome.DODGE, 0)
	_resolve(1, 2, 1, Defense.Outcome.NONE, 12)
	_declare(2, 12, "Sting")
	_resolve(2, 0, 2, Defense.Outcome.JUMP, 0)
	var r := _mirror.recap
	assert_eq([r.parried, r.dodged, r.jumped], [1, 1, 1])
	assert_eq(r.hits_taken, 1)
	assert_eq(r.hits_defended, 3)


func test_top_attack_adds_up_all_hits_of_one_attack() -> void:
	_declare(1, 10, "Maul")
	_resolve(1, 0, 1, Defense.Outcome.NONE, 10)
	_resolve(1, 1, 1, Defense.Outcome.NONE, 10)
	_declare(2, 12, "Sting")
	_resolve(2, 0, 1, Defense.Outcome.NONE, 15)
	var top := _mirror.recap.top_attack
	assert_eq(top.name, "Maul", "two 10s beat one 15")
	assert_eq(top.source, "Husk")
	assert_eq(top.amount, 20)


func test_last_blow_is_the_hit_that_downed_the_last_hero() -> void:
	_declare(1, 10, "Maul")
	_resolve(1, 0, 1, Defense.Outcome.NONE, 40)
	_mirror.apply({"type": "downed", "target": 1})
	_declare(2, 12, "Sting")
	_resolve(2, 0, 2, Defense.Outcome.NONE, 9)
	_mirror.apply({"type": "downed", "target": 2})
	var last := _mirror.recap.last_blow
	assert_eq(last.name, "Sting")
	assert_eq(last.source, "Gnat")
	assert_eq(last.target, "Mage")
	assert_eq(last.amount, 9)


func test_damage_events_on_the_party_count_as_blows() -> void:
	_mirror.apply({"type": "damage", "source": 10, "target": 1, "amount": 7, "hp": 0, "max_hp": 100,
			"cause": "bleed", "crit": false})
	_mirror.apply({"type": "downed", "target": 1})
	assert_eq(_mirror.recap.last_blow.name, "Bleed")
	assert_eq(_mirror.recap.last_blow.amount, 7)
	# Damage the party deals is not a blow on the party.
	_mirror.apply({"type": "damage", "source": 1, "target": 10, "amount": 30, "hp": 0, "max_hp": 100,
			"cause": "ability", "crit": false})
	assert_eq(_mirror.recap.top_attack.amount, 7)


func test_a_new_fight_clears_the_recap() -> void:
	_declare(1, 10, "Maul")
	_resolve(1, 0, 1, Defense.Outcome.NONE, 10)
	_mirror.apply({"type": "combat_started", "seed": 2, "practice_allowed": false, "fighters": [
		_fighter(1, Combatant.Team.PARTY, 0, "Hero"), _fighter(10, Combatant.Team.ENEMY, 0, "Gnat")]})
	assert_true(_mirror.recap.top_attack.is_empty())
	assert_eq(_mirror.recap.hits_taken, 0)
	assert_eq(_mirror.recap.enemies, ["Gnat"] as Array[String])


func test_lines_read_in_order_and_skip_what_is_missing() -> void:
	assert_eq(FightRecap.lines({}, "X", "").size(), 0, "no fight seen: nothing")
	_declare(1, 10, "Maul")
	_resolve(1, 0, 1, Defense.Outcome.PARRY, 0)
	_resolve(1, 1, 1, Defense.Outcome.NONE, 30)
	_mirror.apply({"type": "downed", "target": 1})
	var lines := FightRecap.lines(_mirror.recap.to_dict(), "Husk Pair", "Stop 4, act 1, Oath 2")
	assert_eq(lines.size(), 4)
	assert_string_contains(lines[0], "Husk Pair")
	assert_string_contains(lines[0], "Husk x2, Gnat")
	assert_string_contains(lines[0], "Oath 2")
	assert_string_contains(lines[1], "Maul")
	assert_string_contains(lines[2], "on Hero")
	assert_string_contains(lines[3], "parried 1")
	assert_string_contains(lines[3], "hits taken 1 of 2")
	var quiet := FightRecap.lines({"enemies": ["Gnat"], "top_attack": {}, "last_blow": {}}, "", "")
	assert_eq(quiet.size(), 2, "a fight with no hit taken: who and the defence line")


func test_resume_position_rule() -> void:
	var audio: Script = load("res://scripts/autoload/audio.gd")
	assert_eq(audio.resume_position(12.5, 60.0), 12.5)
	assert_eq(audio.resume_position(0.0, 60.0), 0.0)
	assert_eq(audio.resume_position(-3.0, 60.0), 0.0)
	assert_eq(audio.resume_position(60.0, 60.0), 0.0, "past the end: from the start")
	assert_eq(audio.resume_position(75.0, 60.0), 0.0)
	assert_eq(audio.resume_position(5.0, 0.0), 5.0, "unknown length: trust the position")


func test_the_shipped_music_set_has_an_elite_field_that_may_be_empty() -> void:
	var music := load("res://data/audio/music.tres") as MusicSet
	assert_not_null(music)
	assert_true(music.elite_path.is_empty() or ResourceLoader.exists(music.elite_path), "no invented files")
