class_name Combatant
extends RefCounted
## Runtime state of one fighter. Only CombatEngine changes it; everyone else reads it.

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
	}
