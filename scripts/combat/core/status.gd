class_name Status
extends RefCounted
## Status ids and how long each one lasts (DESIGN.md 2.10, 8.4). Statuses live on
## Combatant.statuses as id -> {turns: int, source: int}. Their numbers (bonus, damage cut, slow,
## bleed, regen) are in Tuning.

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
## On an enemy (Open Vein): at the start of each of its turns it loses bleed_power_percent of the
## source's power, for `turns` of its turns.
const BLEEDING := "bleeding"
## On a party member (Renew): at the start of each of their turns they heal regen_percent of
## their max HP, for `turns` of their turns.
const REGEN := "regen"
## On an enemy (Death Mark): the next `turns` damaging skills on it deal marked_bonus_percent
## more; each skill that lands on it uses one.
const MARKED := "marked"
## On a party member (Shadowstep): their next damaging skill deals empowered_bonus_percent more,
## then it is gone.
const EMPOWERED := "empowered"

## Hero debuffs (card #194). An enemy hit that lands undefended can leave one (AttackHitData.on_hit_status).
## Each lasts `turns` of the holder's turns; hit again, the turns refresh (never stack or multiply).
## At the start of each of the holder's turns they lose rotting_percent of max HP, never below 1 HP
## from rot alone.
const ROTTING := "rotting"
## Healing the holder receives is cut by blighted_heal_cut_percent.
const BLIGHTED := "blighted"
## The holder's power is cut by weakened_power_cut_percent (skills, counters, follow-ups, bleed).
const WEAKENED := "weakened"

const ALL: Array[String] = [EXPOSED, GUARDED, TAUNTED, SLOWED, RIPOSTE, BLEEDING, REGEN, MARKED, EMPOWERED,
		ROTTING, BLIGHTED, WEAKENED]

## The debuffs, in the order a cleanse removes them (the one that hurts most first).
const DEBUFFS: Array[String] = [ROTTING, BLIGHTED, WEAKENED]

## The mark an enemy hit shows when it only drains AP (not a status). Presentation and the intent
## event use it like a status id.
const MARK_AP_DRAIN := "ap_drain"


static func is_known(id: String) -> bool:
	return ALL.has(id)


## True for a hero debuff an enemy hit can leave (and a cleanse removes).
static func is_debuff(id: String) -> bool:
	return DEBUFFS.has(id)


## True if the status ends when its holder's next turn starts.
static func ends_at_own_turn(id: String) -> bool:
	return id == GUARDED or id == RIPOSTE


## True if the status counts down at the end of each of its holder's turns.
static func counts_turns(id: String) -> bool:
	return id == SLOWED or id == BLEEDING or id == REGEN or is_debuff(id)


## True if the status shows a number of uses or turns left.
static func shows_count(id: String) -> bool:
	return counts_turns(id) or id == MARKED
