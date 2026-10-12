class_name Status
extends RefCounted
## Status ids and how long each one lasts (DESIGN.md 2.10). Statuses live on Combatant.statuses
## as id -> {turns: int, source: int}. Their numbers (bonus, damage cut, slow) are in Tuning.

## On an enemy: the next damaging skill that consumes it deals extra damage and removes it.
const EXPOSED := "exposed"
## On a party member: takes guard_damage_percent of each hit until their next turn.
const GUARDED := "guarded"
## On an enemy: its next single-target attack must target the source (the taunter).
const TAUNTED := "taunted"
## Speed is slow_speed_percent of normal for `turns` of the holder's turns.
const SLOWED := "slowed"
## On a party member: counters deal riposte_counter_percent until their next turn.
const RIPOSTE := "riposte"

const ALL: Array[String] = [EXPOSED, GUARDED, TAUNTED, SLOWED, RIPOSTE]


static func is_known(id: String) -> bool:
	return ALL.has(id)


## True if the status ends when its holder's next turn starts.
static func ends_at_own_turn(id: String) -> bool:
	return id == GUARDED or id == RIPOSTE


## True if the status counts down at the end of each of its holder's turns.
static func counts_turns(id: String) -> bool:
	return id == SLOWED
