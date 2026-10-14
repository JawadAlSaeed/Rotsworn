class_name Passive
extends RefCounted
## Passive effects a party member brings into a fight, from their gear (DESIGN.md 8). They are the
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

const ALL: Array[String] = [START_AP, AP_ON_COUNTER, HEAL_ON_JUMP, COUNTER, SECOND_WIND, PERFECT_PRESS, EXPOSED,
	TOUGH, HEAL, ROT]


static func amount(c: Combatant, key: String) -> int:
	return int(c.passives.get(key, 0))
