class_name Passive
extends RefCounted
## Passive effects a party member brings into a fight, from their gear and attributes (DESIGN.md 8). They are the
## keys of Combatant.passives; amounts are integers and add up when two items give the same one.
## Gear that only changes stats (max HP, power, speed) is folded into the setup instead.

## Extra AP at the start of the fight.
const START_AP := "start_ap"
## AP gained after each counter this character takes part in (solo or team).
const AP_ON_COUNTER := "ap_on_counter"
## Heals this percent of max HP on each perfect jump.
const HEAL_ON_JUMP := "heal_on_jump"
## Adds this many points to the counter (and team counter) percent.
const COUNTER := "counter"
## Once per fight: downed during an enemy attack, back up at its end with this percent of max HP.
const SECOND_WIND := "second_wind"
## Adds this many points to a perfect skill press.
const PERFECT_PRESS := "perfect_press"
## Adds this many points to the Exposed bonus of this character's skills.
const EXPOSED := "exposed"
## Enemy hits on this character deal this percent less.
const TOUGH := "tough"
## Heals this character gives are this percent stronger.
const HEAL := "heal"
## Rotten items (DESIGN.md 8.1): loses this percent of max HP at the start of each of their turns
## (never below 1 HP).
const ROT := "rot"
## Adds this many points to the critical hit chance (Luck, DESIGN.md 8.2).
const CRIT := "crit"

## Rot-touched gear (DESIGN.md 8.16). Their drawbacks are the same keys with a negative amount, so
## START_AP, COUNTER, PERFECT_PRESS, EXPOSED, TOUGH (hits deal MORE) and HEAL can also be below 0.
## Healing this character receives is this percent stronger (negative: weaker).
const HEAL_TAKEN := "heal_taken"
## Every kill this character makes heals them this percent of their max HP.
const KILL_HEAL := "kill_heal"
## Power +this percent while their HP is under tuning.rot_low_hp_percent of their max.
const LOW_HP_POWER := "low_hp_power"
## AP gained on each dodge (the base is 0).
const DODGE_AP := "dodge_ap"
## AP gained on each parry, added to tuning.ap_per_parry (negative: the parry gives less, never below 0).
const PARRY_AP := "parry_ap"
## An enemy hit that lands on this character hurts the enemy for this percent of the damage dealt.
const THORNS := "thorns"
## The team gauge this character's skills and follow-ups fill is this percent bigger.
const GAUGE := "gauge"

const ALL: Array[String] = [START_AP, AP_ON_COUNTER, HEAL_ON_JUMP, COUNTER, SECOND_WIND, PERFECT_PRESS, EXPOSED,
	TOUGH, HEAL, ROT, CRIT, HEAL_TAKEN, KILL_HEAL, LOW_HP_POWER, DODGE_AP, PARRY_AP, THORNS, GAUGE]


static func amount(c: Combatant, key: String) -> int:
	return int(c.passives.get(key, 0))
