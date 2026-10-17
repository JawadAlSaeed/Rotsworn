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
@export_group("Choice (DESIGN.md 2.3)")
## The enemy may pick this move at most this many turns running while it has another usable move
## (0 = no limit). Stops a husk swiping five times in a row.
@export_range(0, 8) var max_in_a_row: int = 2
## After the enemy uses it, it cannot pick it again for this many of its next turns (0 = none).
@export_range(0, 8) var cooldown_turns: int = 0
## Finisher: when any standing hero is at or under finisher_below_percent of their max HP, the
## weight is multiplied by finisher_weight_percent. 0 below percent = off.
@export_range(0, 100, 1, "suffix:%") var finisher_below_percent: int = 0
@export_range(1, 1000, 1, "suffix:%") var finisher_weight_percent: int = 100
## Desperation: when the enemy itself is at or under low_hp_below_percent of its max HP, the
## weight is multiplied by low_hp_weight_percent. 0 below percent = off.
@export_range(0, 100, 1, "suffix:%") var low_hp_below_percent: int = 0
@export_range(1, 1000, 1, "suffix:%") var low_hp_weight_percent: int = 100
@export_group("")
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
