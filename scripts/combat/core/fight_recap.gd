class_name FightRecap
extends RefCounted
## What happened in one fight, kept for the RUN OVER screen (DESIGN.md 8, card #191): which enemies,
## the attack that dealt the most damage to the party, the blow that downed the last hero, and how
## the defence went. Fed by CombatMirror with every event in playback order, so it works the same
## for the host and for online clients (each shows its own copy, which matches the host's because
## the events are the same). Pure: no nodes, no time, integers only.

## Enemy names as the fight began (one entry per enemy).
var enemies: Array[String] = []
## The biggest attack: {name, source, amount} (empty until a hit lands). "amount" is the whole
## attack's damage to the party, all its hits together.
var top_attack: Dictionary = {}
## The blow that downed the last hero to go down: {name, source, target, amount} (empty if none).
var last_blow: Dictionary = {}
var parried: int = 0
var dodged: int = 0
var jumped: int = 0
## Enemy hits the party defended / took, in hits (not attacks).
var hits_defended: int = 0
var hits_taken: int = 0
## Per party slot (the mirror's party order): [parried, dodged, jumped, hits taken] (card #283).
var heroes: Array = []

## Sequence number -> {name, source, amount}: damage dealt so far by that attack.
var _attacks: Dictionary = {}
## The latest hit on each hero (fighter id -> {name, source, target, amount}).
var _last_hit: Dictionary = {}


## Takes one event; `mirror` has already applied it (names come from its fighters).
func feed(ev: Dictionary, mirror: CombatMirror) -> void:
	match String(ev.get("type", "")):
		"combat_started":
			_reset()
			for id: int in mirror.enemy_ids:
				enemies.append(String(mirror.fighter(id).get("display_name", "")))
			for id: int in mirror.party_ids:
				heroes.append([0, 0, 0, 0])
		"prompt_resolved":
			_on_prompt(ev, mirror)
		"damage":
			var target := int(ev.get("target", -1))
			if mirror.party_ids.has(target) and int(ev.amount) > 0:
				var cause := String(ev.get("cause", "")).replace("_", " ").capitalize()
				_hit(target, {"name": cause, "source": _name(mirror, int(ev.get("source", -1))),
						"target": _name(mirror, target), "amount": int(ev.amount)}, -1)
		"downed":
			var down := int(ev.get("target", -1))
			if mirror.party_ids.has(down) and _last_hit.has(down):
				last_blow = (_last_hit[down] as Dictionary).duplicate()


func _on_prompt(ev: Dictionary, mirror: CombatMirror) -> void:
	# The mirror kept the declaration of the sequence this prompt belongs to.
	var seq := mirror.sequence
	if seq.is_empty() or int(seq.get("seq", -1)) != int(ev.seq) \
			or String(seq.get("kind", "")) != CombatEngine.SEQUENCE_ENEMY_ATTACK:
		return
	var target := int(ev.character)
	var amount := int(ev.get("damage", 0))
	var slot := mirror.party_ids.find(target)
	var mine: Array = heroes[slot] if slot >= 0 and slot < heroes.size() else [0, 0, 0, 0]
	match int(ev.outcome):
		Defense.Outcome.PARRY:
			parried += 1
			mine[0] = int(mine[0]) + 1
		Defense.Outcome.DODGE:
			dodged += 1
			mine[1] = int(mine[1]) + 1
		Defense.Outcome.JUMP:
			jumped += 1
			mine[2] = int(mine[2]) + 1
	if int(ev.outcome) != Defense.Outcome.NONE:
		hits_defended += 1
	if amount > 0:
		hits_taken += 1
		mine[3] = int(mine[3]) + 1
		_hit(target, {"name": String(seq.get("name", "")), "source": _name(mirror, int(seq.get("source", -1))),
				"target": _name(mirror, target), "amount": amount}, int(ev.seq))


## Remembers a hit on a hero; `seq` >= 0 adds it to that attack's total.
func _hit(target: int, hit: Dictionary, seq: int) -> void:
	_last_hit[target] = hit
	var whole := hit
	if seq >= 0:
		var total: Dictionary = _attacks.get(seq, {"name": hit.name, "source": hit.source, "amount": 0})
		total.amount = int(total.amount) + int(hit.amount)
		_attacks[seq] = total
		whole = total
	# Strict "more than": the first of two equal attacks stays on top (stable, no tie noise).
	if top_attack.is_empty() or int(whole.amount) > int(top_attack.amount):
		top_attack = {"name": whole.name, "source": whole.source, "amount": int(whole.amount)}


func _name(mirror: CombatMirror, id: int) -> String:
	return String(mirror.fighter(id).get("display_name", ""))


func _reset() -> void:
	enemies.clear()
	top_attack = {}
	last_blow = {}
	parried = 0
	dodged = 0
	jumped = 0
	hits_defended = 0
	hits_taken = 0
	heroes.clear()
	_attacks.clear()
	_last_hit.clear()


## The numbers as a plain Dictionary (easy to hand on and to test).
func to_dict() -> Dictionary:
	return {"enemies": enemies.duplicate(), "top_attack": top_attack.duplicate(), "last_blow": last_blow.duplicate(),
			"parried": parried, "dodged": dodged, "jumped": jumped,
			"hits_defended": hits_defended, "hits_taken": hits_taken, "heroes": heroes.duplicate(true)}


## "Husk x2, Gnat" for a list of names (equal names grouped, first-seen order).
static func enemy_line(names: Array) -> String:
	var order: Array[String] = []
	var counts: Dictionary = {}
	for n: Variant in names:
		var key := String(n)
		if not counts.has(key):
			order.append(key)
			counts[key] = 0
		counts[key] = int(counts[key]) + 1
	var parts := PackedStringArray()
	for key: String in order:
		parts.append(key if int(counts[key]) == 1 else "%s x%d" % [key, counts[key]])
	return ", ".join(parts)


## The RUN OVER lines for a recap Dictionary (to_dict), the encounter's name and `where` (a short
## place line such as "Stop 7, act 2, Oath 3"). Empty when the recap has nothing (no fight seen).
static func lines(recap: Dictionary, encounter_name: String, where: String) -> Array[String]:
	var out: Array[String] = []
	if recap.is_empty() or (recap.get("enemies", []) as Array).is_empty():
		return out
	var foes := enemy_line(recap.enemies)
	var head := "Finished by  %s" % (encounter_name if not encounter_name.is_empty() else foes)
	if not encounter_name.is_empty() and encounter_name != foes:
		head += "  (%s)" % foes
	if not where.is_empty():
		head += "      " + where
	out.append(head)
	var top: Dictionary = recap.get("top_attack", {})
	if not top.is_empty():
		out.append("Hardest hit  %s, %s   %d damage" % [top.name, top.source, top.amount])
	var last: Dictionary = recap.get("last_blow", {})
	if not last.is_empty():
		out.append("Last blow  %s, %s, on %s   %d damage" % [last.name, last.source, last.target, last.amount])
	var hits := int(recap.get("hits_defended", 0)) + int(recap.get("hits_taken", 0))
	out.append("Defence  parried %d, dodged %d, jumped %d   hits taken %d of %d" % [int(recap.get("parried", 0)),
			int(recap.get("dodged", 0)), int(recap.get("jumped", 0)), int(recap.get("hits_taken", 0)), hits])
	return out
