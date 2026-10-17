class_name Combatant
extends RefCounted
## Runtime state of one fighter. Only CombatEngine changes it; everyone else reads it.

## Longest attack history an enemy keeps.
const RECENT_MAX: int = 8

enum Team {
	PARTY,
	ENEMY,
}

## Index in the engine's combatant list. Party members come first, so ids double as tie-breakers.
var id: int = -1
var team: Team = Team.PARTY
## Position within its side (0, 1, 2...).
var slot: int = 0
## Id of the CharacterData or EnemyData this fighter was built from.
var data_id: String = ""
var display_name: String = ""
var max_hp: int = 1
var hp: int = 1
var ap: int = 0
## Base damage of this fighter's attacks before move multipliers.
var power: int = 1
## Current speed (a status may change it) and the speed from data.
var speed: int = 100
var base_speed: int = 100
## Timeline position of this fighter's next turn.
var next_turn_at: int = 0
## Party only: abilities this fighter may use.
var ability_ids: Array[String] = []
## Enemy only: attacks this fighter may use.
var attack_ids: Array[String] = []
## Status id -> {turns: int, source: int (combatant id)}. See Status.
var statuses: Dictionary = {}
## Party only: perfect defences (parry or jump) since this fighter's last turn ended.
var perfect_defenses: int = 0
## Gear passives (Passive keys -> amount), party only.
var passives: Dictionary = {}
var second_wind_used: bool = false
## Enemy phase: 1, or 2 once it has dropped under its phase two HP (bosses).
var phase: int = 1
## Enemy only: ids of the attacks it used, oldest first (at most RECENT_MAX), the turns left on each
## attack's cooldown, and the hero its last single-target attack hit (-1 = none). They steer its
## next choice (DESIGN.md 2.3).
var recent_attacks: Array[String] = []
var attack_cooldowns: Dictionary = {}
var last_target: int = -1
## Ran from the fight (DESIGN.md 2.13): out of it for good, neither standing nor downed.
var escaped: bool = false


## Standing in the fight (not downed, not escaped).
func is_alive() -> bool:
	return hp > 0 and not escaped


func is_party() -> bool:
	return team == Team.PARTY


func has_status(id: String) -> bool:
	return statuses.has(id)


static func from_dict(d: Dictionary) -> Combatant:
	var c := Combatant.new()
	c.id = int(d.id)
	c.team = int(d.team) as Team
	c.slot = int(d.slot)
	c.data_id = String(d.data_id)
	c.display_name = String(d.display_name)
	c.max_hp = int(d.max_hp)
	c.hp = int(d.hp)
	c.ap = int(d.ap)
	c.power = int(d.power)
	c.speed = int(d.speed)
	c.base_speed = int(d.base_speed)
	c.next_turn_at = int(d.next_turn_at)
	c.ability_ids.assign(d.ability_ids)
	c.attack_ids.assign(d.attack_ids)
	c.statuses = (d.statuses as Dictionary).duplicate(true)
	c.perfect_defenses = int(d.perfect_defenses)
	c.passives = (d.get("passives", {}) as Dictionary).duplicate()
	c.second_wind_used = bool(d.get("second_wind_used", false))
	c.phase = int(d.get("phase", 1))
	c.escaped = bool(d.get("escaped", false))
	c.recent_attacks.assign(d.get("recent_attacks", []))
	c.attack_cooldowns = (d.get("attack_cooldowns", {}) as Dictionary).duplicate()
	c.last_target = int(d.get("last_target", -1))
	return c


func to_dict() -> Dictionary:
	return {
		"id": id,
		"team": team,
		"slot": slot,
		"data_id": data_id,
		"display_name": display_name,
		"max_hp": max_hp,
		"hp": hp,
		"ap": ap,
		"power": power,
		"speed": speed,
		"base_speed": base_speed,
		"next_turn_at": next_turn_at,
		"ability_ids": ability_ids.duplicate(),
		"attack_ids": attack_ids.duplicate(),
		"statuses": statuses.duplicate(true),
		"perfect_defenses": perfect_defenses,
		"passives": passives.duplicate(),
		"second_wind_used": second_wind_used,
		"phase": phase,
		"escaped": escaped,
		"recent_attacks": recent_attacks.duplicate(),
		"attack_cooldowns": attack_cooldowns.duplicate(),
		"last_target": last_target,
	}


## How many of the latest attacks in a row were this one.
func repeat_run(attack_id: String) -> int:
	var run := 0
	for i: int in range(recent_attacks.size() - 1, -1, -1):
		if recent_attacks[i] != attack_id:
			break
		run += 1
	return run


## Notes that an attack was used: history, cooldown and (single target) the hero it hit.
func note_attack(attack_id: String, cooldown_turns: int, single_target: int) -> void:
	recent_attacks.append(attack_id)
	while recent_attacks.size() > RECENT_MAX:
		recent_attacks.remove_at(0)
	if cooldown_turns > 0:
		attack_cooldowns[attack_id] = cooldown_turns
	if single_target >= 0:
		last_target = single_target


## Called at the start of the enemy's turn: every cooldown runs one turn down.
func tick_cooldowns() -> void:
	for attack_id: String in attack_cooldowns.keys():
		var left := int(attack_cooldowns[attack_id]) - 1
		if left <= 0:
			attack_cooldowns.erase(attack_id)
		else:
			attack_cooldowns[attack_id] = left
