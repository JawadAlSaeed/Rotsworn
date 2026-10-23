class_name CombatMirror
extends RefCounted
## What the presentation knows about a fight, built only by applying events in playback order.
## The HUD and views read this, never the engine, so:
## - bars change when the matching animation plays, not when the engine already moved on;
## - network clients (phase 5), which have no engine, use exactly the same code.
## Pure: no nodes, no time.

## id -> {id, team, slot, data_id, display_name, max_hp, hp, ap, power, speed, alive,
## statuses: {status id: {turns, source}}, and for enemies the Charged Doom state (card #195):
## charge_attack ("" = none), charge_left (enemy turns until it unleashes), charge_total, charge_damage
## (taken toward the break), break_hp (the damage that breaks it), staggered (turns it still loses)}
var fighters: Dictionary = {}
var party_ids: Array[int] = []
var enemy_ids: Array[int] = []
var turn: int = 0
var active_actor: int = -1
var turn_order: Array[int] = []
## The last declared timed sequence, with "states" and "outcomes" kept up to date.
var sequence: Dictionary = {}
var result: String = ""
## Shared team gauge (its size is tuning team_gauge_max).
var team_gauge: int = 0
## The party's perfect defences in a row and the best run this fight (card #300).
var defence_streak: int = 0
var best_defence_streak: int = 0
## Enemy id -> its last intent event (what it does next). Removed when the attack starts or the
## enemy goes down.
var intents: Dictionary = {}
var practice: Dictionary = {"invulnerable_party": false, "immortal_enemies": false, "force_attack": ""}
var practice_allowed: bool = false
var seed_value: int = 0
## Backpack items not used yet (DESIGN.md 8.1): uid -> CombatEngine.item_info() data.
var items: Dictionary = {}
## The uids used so far, in order (the run takes them out of the backpack afterwards).
var used_items: Array[int] = []
## What happened in this fight, for the RUN OVER screen (card #191); fed by apply().
var recap := FightRecap.new()
## What this fight adds to the Rot Journal (card #200); fed by apply() like the recap.
var journal := JournalTally.new()


func apply(event: Dictionary) -> void:
	_apply(event)
	recap.feed(event, self)
	journal.feed(event, self)


func _apply(event: Dictionary) -> void:
	match String(event.get("type", "")):
		"combat_started":
			fighters.clear()
			party_ids.clear()
			enemy_ids.clear()
			defence_streak = 0
			best_defence_streak = 0
			seed_value = int(event.seed)
			practice_allowed = bool(event.practice_allowed)
			items.clear()
			used_items.clear()
			for info: Variant in event.get("items", []):
				if info is Dictionary:
					items[int((info as Dictionary).uid)] = (info as Dictionary).duplicate()
			for d: Dictionary in event.fighters:
				var f := {
					"id": int(d.id),
					"team": int(d.team),
					"slot": int(d.slot),
					"data_id": String(d.data_id),
					"display_name": String(d.display_name),
					"ability_ids": (d.get("ability_ids", []) as Array).duplicate(),
					"max_hp": int(d.max_hp),
					"hp": int(d.hp),
					"ap": int(d.ap),
					"power": int(d.power),
					"speed": int(d.speed),
					"alive": int(d.hp) > 0 and not bool(d.get("escaped", false)),
					"escaped": bool(d.get("escaped", false)),
					"statuses": (d.get("statuses", {}) as Dictionary).duplicate(true),
					"charge_attack": String(d.get("charge_attack", "")),
					"charge_left": int(d.get("charge_left", 0)),
					"charge_total": 0,
					"charge_damage": int(d.get("charge_damage", 0)),
					"break_hp": 0,
					"staggered": int(d.get("staggered_turns", 0)),
				}
				fighters[f.id] = f
				if f.team == Combatant.Team.PARTY:
					party_ids.append(f.id)
				else:
					enemy_ids.append(f.id)
		"turn_started":
			turn = int(event.turn)
			active_actor = int(event.actor)
		"turn_order":
			turn_order.assign(event.order)
		"damage":
			_set_hp(int(event.target), int(event.hp))
		"downed":
			_set_hp(int(event.target), 0)
			intents.erase(int(event.target))
			_clear_doom(int(event.target))
			fighter(int(event.target))["staggered"] = 0
		"healed", "revived":
			_set_hp(int(event.target), int(event.hp))
		"status_changed":
			var statuses: Dictionary = fighter(int(event.target)).get("statuses", {})
			if bool(event.active):
				statuses[String(event.status)] = {"turns": int(event.turns), "source": int(event.source)}
			else:
				statuses.erase(String(event.status))
		"team_gauge":
			team_gauge = int(event.value)
		"defence_streak":
			defence_streak = int(event.value)
			best_defence_streak = int(event.best)
		"intent":
			intents[int(event.enemy)] = event.duplicate(true)
			_note_doom_intent(event)
		"doom_charging":
			var gathering := fighter(int(event.enemy))
			gathering.charge_attack = String(event.attack)
			gathering.charge_left = int(event.left)
			gathering.charge_total = int(event.total)
			gathering.charge_damage = int(event.damage)
			gathering.break_hp = int(event.break_hp)
		"doom_progress":
			fighter(int(event.enemy)).charge_damage = int(event.damage)
		"doom_broken":
			_clear_doom(int(event.enemy))
			fighter(int(event.enemy))["staggered"] = int(event.stagger_turns)
		"doom_unleashed":
			_clear_doom(int(event.enemy))
		"stagger_changed":
			fighter(int(event.enemy))["staggered"] = int(event.turns)
		"escaped":
			var runner := fighter(int(event.character))
			runner.escaped = true
			runner.alive = false
		"ap_changed":
			fighter(int(event.character)).ap = int(event.ap)
		"timed_sequence_declared":
			sequence = event.duplicate(true)
			if String(event.kind) == CombatEngine.SEQUENCE_ENEMY_ATTACK:
				intents.erase(int(event.source))
			var states: Array[int] = []
			var outcomes: Array[int] = []
			for i: int in (event.prompts as Array).size():
				states.append(CombatEngine.PromptState.PENDING)
				outcomes.append(Defense.Outcome.NONE)
			sequence["states"] = states
			sequence["outcomes"] = outcomes
		"prompt_resolved":
			var f := fighter(int(event.character))
			f.hp = int(event.hp)
			f.alive = f.hp > 0 and not bool(f.get("escaped", false))
			f.ap = int(event.ap)
			if _is_current(event):
				sequence.states[int(event.prompt)] = CombatEngine.PromptState.RESOLVED
				sequence.outcomes[int(event.prompt)] = int(event.outcome)
		"prompts_voided":
			if _is_current(event):
				for idx: int in event.prompts:
					sequence.states[idx] = CombatEngine.PromptState.VOID
		"item_used":
			items.erase(int(event.uid))
			used_items.append(int(event.uid))
		"turn_ended":
			if active_actor == int(event.actor):
				active_actor = -1
		"practice_changed":
			practice = {
				"invulnerable_party": bool(event.invulnerable_party),
				"immortal_enemies": bool(event.immortal_enemies),
				"force_attack": String(event.force_attack),
			}
		"combat_ended":
			result = String(event.result)
			active_actor = -1


## An intent that is a Charged Doom says how far its countdown and damage are; any other intent
## means the enemy is not charging.
func _note_doom_intent(event: Dictionary) -> void:
	var f := fighter(int(event.enemy))
	if f.is_empty():
		return
	if event.has("charge_total"):
		f.charge_attack = String(event.attack)
		f.charge_left = int(event.charge_left)
		f.charge_total = int(event.charge_total)
		f.charge_damage = int(event.charge_damage)
		f.break_hp = int(event.break_hp)
	else:
		_clear_doom(int(event.enemy))


func _clear_doom(id: int) -> void:
	var f := fighter(id)
	if f.is_empty():
		return
	f.charge_attack = ""
	f.charge_left = 0
	f.charge_total = 0
	f.charge_damage = 0
	f.break_hp = 0


## True while the enemy is gathering a Doom (the countdown runs and the party can break it).
func is_charging(id: int) -> bool:
	return is_alive(id) and int(fighter(id).get("charge_left", 0)) > 0


## True while the enemy is staggered.
func is_staggered(id: int) -> bool:
	return is_alive(id) and int(fighter(id).get("staggered", 0)) > 0


func fighter(id: int) -> Dictionary:
	return fighters.get(id, {})


func is_alive(id: int) -> bool:
	return bool(fighter(id).get("alive", false))


func has_status(id: int, status: String) -> bool:
	return (fighter(id).get("statuses", {}) as Dictionary).has(status)


func downed_party_ids() -> Array[int]:
	var list: Array[int] = []
	for id: int in party_ids:
		# A hero who ran (DESIGN.md 2.13) is out of the fight, not down: nobody can revive them.
		if not is_alive(id) and not bool(fighter(id).get("escaped", false)):
			list.append(id)
	return list


func living_party_ids() -> Array[int]:
	return _living(party_ids)


func living_enemy_ids() -> Array[int]:
	return _living(enemy_ids)


func _living(ids: Array[int]) -> Array[int]:
	var list: Array[int] = []
	for id: int in ids:
		if is_alive(id):
			list.append(id)
	return list


## The fields the mirror tracks, in a shape comparable with project_snapshot().
func projection() -> Dictionary:
	var hp: Dictionary = {}
	var ap: Dictionary = {}
	var statuses: Dictionary = {}
	var dooms: Dictionary = {}
	for id: int in fighters:
		hp[id] = int(fighters[id].hp)
		ap[id] = int(fighters[id].ap)
		statuses[id] = (fighters[id].statuses as Dictionary).duplicate(true)
		dooms[id] = [int(fighters[id].charge_left), int(fighters[id].charge_damage), int(fighters[id].staggered)]
	var left: Array = items.keys()
	left.sort()
	return {"hp": hp, "ap": ap, "statuses": statuses, "team_gauge": team_gauge, "result": result,
			"practice": practice.duplicate(), "items_left": left, "dooms": dooms,
			"streak": [defence_streak, best_defence_streak]}


## The same projection taken from CombatEngine.snapshot(), for tests.
static func project_snapshot(snap: Dictionary) -> Dictionary:
	var hp: Dictionary = {}
	var ap: Dictionary = {}
	var statuses: Dictionary = {}
	var dooms: Dictionary = {}
	for d: Dictionary in snap.combatants:
		hp[int(d.id)] = int(d.hp)
		ap[int(d.id)] = int(d.ap)
		statuses[int(d.id)] = (d.statuses as Dictionary).duplicate(true)
		dooms[int(d.id)] = [int(d.get("charge_left", 0)), int(d.get("charge_damage", 0)), int(d.get("staggered_turns", 0))]
	var left: Array = (snap.get("items_left", []) as Array).duplicate()
	left.sort()
	return {"hp": hp, "ap": ap, "statuses": statuses, "team_gauge": int(snap.team_gauge),
			"result": String(snap.result), "practice": (snap.practice as Dictionary).duplicate(), "items_left": left,
			"dooms": dooms, "streak": [int(snap.get("defence_streak", 0)), int(snap.get("best_defence_streak", 0))]}


func _set_hp(id: int, hp: int) -> void:
	var f := fighter(id)
	if f.is_empty():
		return
	f.hp = hp
	f.alive = hp > 0 and not bool(f.get("escaped", false))


func _is_current(event: Dictionary) -> bool:
	return not sequence.is_empty() and int(sequence.seq) == int(event.seq)
