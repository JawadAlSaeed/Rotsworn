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
	## One fellow monster (a support move, card #259): no hits, no defence; see `support`.
	ALLY,
}

## What a support move does to the fellow monster it picks (card #259). A support move has no hits.
enum Support {
	## An ordinary attack.
	NONE,
	## Heals the most wounded standing monster (itself included) by support_percent of its max HP.
	## Only picked while one of them is at or under support_below_percent of its max HP.
	HEAL,
	## Shields a standing monster (Status.SHIELDED) for support_turns of its turns. Only picked while
	## one of them has no shield.
	SHIELD,
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
## It cannot be picked for the enemy's first this many intents of the fight (0 = none): a Doom
## never opens a fight (the first intent is picked before the first turn; each turn ticks one).
@export_range(0, 8) var start_cooldown_turns: int = 0
## Finisher: when any standing hero is at or under finisher_below_percent of their max HP, the
## weight is multiplied by finisher_weight_percent. 0 below percent = off.
@export_range(0, 100, 1, "suffix:%") var finisher_below_percent: int = 0
@export_range(1, 1000, 1, "suffix:%") var finisher_weight_percent: int = 100
## Desperation: when the enemy itself is at or under low_hp_below_percent of its max HP, the
## weight is multiplied by low_hp_weight_percent. 0 below percent = off.
@export_range(0, 100, 1, "suffix:%") var low_hp_below_percent: int = 0
@export_range(1, 1000, 1, "suffix:%") var low_hp_weight_percent: int = 100
@export_group("Charged Doom (DESIGN.md 2.3)")
## 0 = an ordinary move. Above 0 the move is a Doom: the enemy does not strike at once. The move
## takes this many of the enemy's turns from the moment it is announced; the first charge_turns - 1
## of them are spent gathering (the intent stays, with a countdown) and it unleashes on the last.
## A Doom is party-wide and needs break_damage_percent and a cooldown (see CombatSetup.validate).
@export_range(0, 6) var charge_turns: int = 0
## Break: if the party deals this share of the enemy's max HP while the Doom is announced or being
## gathered, the Doom is cancelled and the enemy is staggered (tuning stagger_turns,
## stagger_damage_taken_percent).
@export_range(0, 100, 1, "suffix:%") var break_damage_percent: int = 0
@export_group("Support (card #259)")
## A support move helps a fellow monster instead of striking (target_mode ALLY, no hits).
@export var support: Support = Support.NONE
@export_range(0, 100, 1, "suffix:%") var support_percent: int = 0
@export_range(1, 100, 1, "suffix:%") var support_below_percent: int = 75
@export_range(0, 10) var support_turns: int = 2
@export_group("Self-destruct (card #260)")
## The attacker falls when this attack is over (a Pus Tick's Burst): it is spent.
@export var self_destruct: bool = false
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


## True for a support move (heals or shields a fellow monster, card #259).
func is_support() -> bool:
	return support != Support.NONE


## True for a Charged Doom (charge_turns above 0).
func is_doom() -> bool:
	return charge_turns > 0


## How long before each hit the training ring appears, in milliseconds.
func ring_lead_ms(tuning: Tuning) -> int:
	return CombatMath.percent(tuning.ring_lead_ms, ring_lead_percent)
