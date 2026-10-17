class_name AttackHitData
extends Resource
## One hit inside an enemy attack.

enum Kind {
	## Dodge or parry it.
	NORMAL,
	## A shockwave along the floor. Only a jump avoids it.
	GROUND,
	## Party skill presses only (never used in enemy attack data).
	PRESS,
	## A rending blow (card #187): only a parry stops it; a dodge or a jump is the wrong button.
	REND,
	## A wide sweep (card #187): only a dodge avoids it; a parry or a jump is the wrong button, and
	## it can never be part of a counter.
	SWEEP,
}

## How a ground hit looks on its way to the party (DESIGN.md 3.10). Presentation only.
enum GroundLook {
	## A shockwave front parallel to the party line.
	WAVE,
	## Rocks bursting out of the ground in a lane toward each target, the last row under them.
	ROCKS,
}

## When the hit lands, in milliseconds after the attack starts (scaled by tuning attack_tempo_percent).
@export_range(0, 20000, 1, "suffix:ms") var impact_ms: int = 1000
@export var kind: Kind = Kind.NORMAL
## What this normal hit becomes in a hard fight (an elite, a guard, a boss, or an enemy marked
## EnemyData.forced_hits, card #187): REND or SWEEP. NORMAL = it stays a normal hit everywhere.
## So one attack serves an ordinary fight and a hard one (DESIGN.md 2.4).
@export var forced_kind: Kind = Kind.NORMAL
## Damage, in percent of the enemy's power.
@export_range(0, 1000, 5, "suffix:%") var damage_percent: int = 100
## Normal hits: how long the visible lunge into the target lasts, ending at impact.
## Ground hits: how long the shockwave travels before reaching the party.
@export_range(50, 3000, 1, "suffix:ms") var approach_ms: int = 200
## Fake-out: the enemy starts a lunge early, stops, and holds before the real one.
@export var feint: bool = false
## In a hard fight (see forced_kind) this hit is a feint even when `feint` is off: elites, guards
## and bosses fake out where an ordinary fight does not (review combat-feel #4).
@export var forced_feint: bool = false
## Normal hits: what the enemy throws instead of lunging (null = a lunge). It flies for
## approach_ms and arrives at impact (DESIGN.md 3.9). Presentation only.
@export var projectile: ProjectileData
## Ground hits: how the attack travels along the floor.
@export var ground_look: GroundLook = GroundLook.WAVE
## Sound cue played if the hit connects.
@export var impact_sfx: String = "hurt"
@export_group("Marks (card #194)")
## A mark this hit leaves on a hero who takes it undefended and survives it: a hero debuff
## ("rotting", "blighted", "weakened"; see Status), "" for none. A successful dodge, parry or jump
## prevents it. The intent shows which hits mark, so it is always honest.
@export var on_hit_status: String = ""
## How many of the hero's turns the debuff lasts (a second hit refreshes it, it never stacks).
@export_range(1, 10) var on_hit_status_turns: int = 2
## AP the hero loses to this hit when it lands undefended (0 = none).
@export_range(0, 9) var on_hit_ap_drain: int = 0
## The mark only comes in a hard fight (an elite, guard or boss fight, or a forced_hits enemy), like
## forced_kind: one attack serves an ordinary fight, where it is just damage, and a hard one.
@export var on_hit_hard_only: bool = false
@export_group("")
## Animation prefix for this hit's enemy clips (presentation only, DESIGN.md 5.5): `<anim>_lunge`
## is tried before `lunge`, and so on. Empty: the plain clips.
@export var anim: String = ""


## True for a hit the enemy delivers with its body or a throw (normal, rend, sweep), not along the
## floor. Presentation treats them alike; only their colour and icon differ.
static func is_strike(hit_kind: int) -> bool:
	return hit_kind == Kind.NORMAL or hit_kind == Kind.REND or hit_kind == Kind.SWEEP


## True for a forced-choice hit: one that only one button answers (REND, SWEEP).
static func is_forced(hit_kind: int) -> bool:
	return hit_kind == Kind.REND or hit_kind == Kind.SWEEP


## The kind this hit has in a fight: its forced kind in a hard fight, else its own.
func kind_in(hard: bool) -> int:
	if hard and kind == Kind.NORMAL and is_forced(forced_kind):
		return forced_kind
	return kind


## True if this hit is a feint in a fight (hard: an elite, guard or boss fight, or a forced_hits
## enemy).
func feint_in(hard: bool) -> bool:
	return feint or (hard and forced_feint)


## True if this hit leaves a mark (a status or an AP drain) in a fight (hard: see on_hit_hard_only).
func marks_in(hard: bool) -> bool:
	if on_hit_hard_only and not hard:
		return false
	return not on_hit_status.is_empty() or on_hit_ap_drain > 0


## What the intent shows for a marking hit: its status id, else Status.MARK_AP_DRAIN, else "".
func mark_id_in(hard: bool) -> String:
	if not marks_in(hard):
		return ""
	return on_hit_status if not on_hit_status.is_empty() else Status.MARK_AP_DRAIN
