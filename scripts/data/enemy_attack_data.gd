class_name EnemyAttackData
extends Resource
## An enemy move: who it targets and the hits it is made of.

enum TargetMode {
	## One party member (named in the banner).
	SINGLE,
	## The whole party.
	PARTY,
	## Each hero in turn (Pack Bite, DESIGN.md 3.11): hit i strikes only the i-th target, the
	## targets being every standing hero from a random one on, in party order. Normal hits only.
	EACH,
}

## Unique id used in events and save data.
@export var id: String = ""
@export var display_name: String = ""
@export var target_mode: TargetMode = TargetMode.SINGLE
## How likely the enemy is to pick this move compared to its other moves.
@export_range(0, 100) var weight: int = 1
## Play the alert sound when the attack starts.
@export var alert_cue: bool = true
## Allow the training ring on this attack (turn off for feints).
@export var allow_timing_ring: bool = true
## How long the training ring takes to close on this attack, in percent of tuning ring_lead_ms
## (100 = normal speed, lower = faster).
@export_range(20, 300, 1, "suffix:%") var ring_lead_percent: int = 100
## Hits in the order they land. Impact times must increase.
@export var hits: Array[AttackHitData] = []


## How long before each hit the training ring appears, in milliseconds.
func ring_lead_ms(tuning: Tuning) -> int:
	return CombatMath.percent(tuning.ring_lead_ms, ring_lead_percent)
