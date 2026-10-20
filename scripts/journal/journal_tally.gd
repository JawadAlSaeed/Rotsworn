class_name JournalTally
extends RefCounted
## What one fight adds to the Rot Journal (card #200): which enemies were there, the attacks they
## used, the hit kinds and marks seen, and how each hit was answered. Fed by CombatMirror with every
## event in playback order (like FightRecap), so it reads what the presentation sees, never the engine
## (CLAUDE.md rule 7), and works the same for the host and online clients. Pure.
## to_dict() is shaped as RotJournal.record_fight() wants it: {enemies: {enemy id: entry}}.

## Enemy data id -> entry ({name, met, beaten, attacks}, see RotJournal).
var _enemies: Dictionary = {}
## The party slots this machine's players play (card #283: each player's defence counts for them
## alone). Empty: every hero counts (one machine, solo or local co-op).
var local_slots: Array[int] = []


## Takes one event; `mirror` has already applied it.
func feed(ev: Dictionary, mirror: CombatMirror) -> void:
	match String(ev.get("type", "")):
		"combat_started":
			_enemies.clear()
			for id: int in mirror.enemy_ids:
				_entry(mirror, id)
		"timed_sequence_declared":
			if String(ev.get("kind", "")) == CombatEngine.SEQUENCE_ENEMY_ATTACK:
				_on_attack(ev, mirror)
		"prompt_resolved":
			_on_prompt(ev, mirror)
		"enemy_support":
			# A heal or a shield on a fellow monster (card #259): seen, with no hits to answer.
			var helped := _attack(mirror, int(ev.get("enemy", -1)), String(ev.get("attack", "")), String(ev.get("name", "")))
			if not helped.is_empty():
				helped["seen"] = int(helped["seen"]) + 1
		"doom_broken":
			var record := _attack(mirror, int(ev.get("enemy", -1)), String(ev.get("attack", "")), String(ev.get("name", "")))
			if not record.is_empty():
				record["broken"] = int(record["broken"]) + 1
		"downed":
			var down := int(ev.get("target", -1))
			if mirror.enemy_ids.has(down):
				var entry := _entry(mirror, down)
				if not entry.is_empty():
					entry["beaten"] = int(entry["beaten"]) + 1


func _on_attack(ev: Dictionary, mirror: CombatMirror) -> void:
	var record := _attack(mirror, int(ev.get("source", -1)), String(ev.get("action", "")), String(ev.get("name", "")))
	if record.is_empty():
		return
	record["seen"] = int(record["seen"]) + 1
	for hit: Variant in ev.get("hits", []):
		if not hit is Dictionary:
			continue
		var key := RotJournal.kind_key(int((hit as Dictionary).get("kind", -1)))
		if not key.is_empty():
			_count(record["kinds"], key)
		var mark := String((hit as Dictionary).get("mark", ""))
		if not mark.is_empty():
			_count(record["marks"], mark)


func _on_prompt(ev: Dictionary, mirror: CombatMirror) -> void:
	# The mirror kept the declaration of the sequence this prompt belongs to.
	var seq := mirror.sequence
	if seq.is_empty() or int(seq.get("seq", -1)) != int(ev.get("seq", -2)) \
			or String(seq.get("kind", "")) != CombatEngine.SEQUENCE_ENEMY_ATTACK:
		return
	var record := _attack(mirror, int(seq.get("source", -1)), String(seq.get("action", "")), String(seq.get("name", "")))
	if record.is_empty():
		return
	if not local_slots.is_empty() and not local_slots.has(mirror.party_ids.find(int(ev.get("character", -1)))):
		return
	match int(ev.get("outcome", Defense.Outcome.NONE)):
		Defense.Outcome.PARRY:
			record["parried"] = int(record["parried"]) + 1
		Defense.Outcome.DODGE:
			record["dodged"] = int(record["dodged"]) + 1
		Defense.Outcome.JUMP:
			record["jumped"] = int(record["jumped"]) + 1
		_:
			record["hit"] = int(record["hit"]) + 1


static func _count(into: Dictionary, key: String) -> void:
	into[key] = int(into.get(key, 0)) + 1


## The fight's entry for enemy fighter `id` (made on first use; empty if it is not an enemy).
func _entry(mirror: CombatMirror, id: int) -> Dictionary:
	var fighter := mirror.fighter(id)
	if fighter.is_empty() or int(fighter.get("team", -1)) != Combatant.Team.ENEMY:
		return {}
	var data_id := String(fighter.get("data_id", ""))
	if data_id.is_empty():
		return {}
	if not _enemies.has(data_id):
		_enemies[data_id] = {"name": String(fighter.get("display_name", "")), "met": 1, "beaten": 0, "attacks": {}}
	return _enemies[data_id]


func _attack(mirror: CombatMirror, enemy_fighter: int, attack_id: String, attack_name: String) -> Dictionary:
	var entry := _entry(mirror, enemy_fighter)
	if entry.is_empty() or attack_id.is_empty():
		return {}
	var attacks: Dictionary = entry["attacks"]
	if not attacks.has(attack_id):
		attacks[attack_id] = {"name": attack_name, "seen": 0, "broken": 0, "parried": 0, "dodged": 0, "jumped": 0,
				"hit": 0, "kinds": {}, "marks": {}}
	return attacks[attack_id]


## The fight so far, for RotJournal.record_fight().
func to_dict() -> Dictionary:
	return {"enemies": _enemies.duplicate(true)}
