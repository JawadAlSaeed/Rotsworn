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
## Counters (and team counters) deal this percent more (a multiplier, DESIGN.md 8.25).
const COUNTER := "counter"
## Once per fight: downed during an enemy attack, back up at its end with this percent of max HP.
const SECOND_WIND := "second_wind"
## A perfect skill press deals this percent more (a multiplier, DESIGN.md 8.25).
const PERFECT_PRESS := "perfect_press"
## This character's skills on an Exposed foe deal this percent more on top of the Exposed bonus
## (a multiplier of the Exposed factor, DESIGN.md 8.25).
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
## Any foe falls: this character heals this percent of their max HP (Hunger Charm, DESIGN.md 8.25).
const KILL_HEAL := "kill_heal"
## Power +this percent while their HP is under tuning.rot_low_hp_percent of their max.
const LOW_HP_POWER := "low_hp_power"
## AP gained on each dodge (the base is 0).
const DODGE_AP := "dodge_ap"
## AP gained on each parry, added to tuning.ap_per_parry (negative: the parry gives less, never below 0).
const PARRY_AP := "parry_ap"
## Each parry hurts the attacker for this percent of the hit's damage (Bramble Coat, DESIGN.md 8.25).
const THORNS := "thorns"
## The team gauge this character's skills and follow-ups fill is this percent bigger.
const GAUGE := "gauge"

## Relics against marks (card #263). Marks left on this character last this many fewer turns (never
## under 1).
const MARK_SHORTEN := "mark_shorten"
## Each perfect parry lifts this many of this character's marks (Status.DEBUFFS order).
const PARRY_CLEANSE := "parry_cleanse"
## The fight starts with this character Warded (no marks) for this many of their turns.
const WARD_START := "ward_start"

## More Relics (phase 20, card #242). Power +this percent while at full HP.
const FULL_HP_POWER := "full_hp_power"
## AP gained for each enemy this character downs or staggers (Reaper's Coin, DESIGN.md 8.25).
const KILL_AP := "kill_ap"
## The fight starts with this character Empowered for this many damaging skills.
const START_EMPOWERED := "start_empowered"
## The fight starts with this character under Regen for this many of their turns.
const START_REGEN := "start_regen"
## This character's damage to a Staggered enemy is this percent bigger (a multiplier on top of the
## Stagger bonus, DESIGN.md 8.25).
const STAGGER_DAMAGE := "stagger_damage"
## This character's critical hits deal this percent more (multiplies tuning.crit_damage_percent).
const CRIT_DAMAGE := "crit_damage"
## Each parry heals this character this percent of their max HP.
const PARRY_HEAL := "parry_heal"

## Relics reworked (phase 27, DESIGN.md 8.25): see GearData.Effect for what each does.
const COUNTER_TURN := "counter_turn"
const COUNTER_EMPOWER := "counter_empower"
const START_GUARDED := "start_guarded"
const JUMP_AP := "jump_ap"
const FIRST_HIT_EXPOSE := "first_hit_expose"
const FIRST_HIT_BLEED := "first_hit_bleed"
const THIRD_SKILL := "third_skill"
const COUNTER_STACK := "counter_stack"
const COUNTER_CRIT := "counter_crit"
const COUNTER_CRIT_DAMAGE := "counter_crit_damage"
const FOLLOW_UP_DAMAGE := "follow_up_damage"
const FIRST_STRIKE_EXPOSE := "first_strike_expose"
const FIRST_STRIKE_SLOW := "first_strike_slow"
const LEFTOVER_AP := "leftover_ap"
const SKILL_HIT_RAMP := "skill_hit_ramp"
const LAST_STANDING_POWER := "last_standing_power"
const FALL_TEAM_AP := "fall_team_ap"
const DODGE_ALL_CRIT := "dodge_all_crit"
const JUMP_ALL_CRIT := "jump_all_crit"
const DEFEND_WINDOW := "defend_window"
const NULL_HIT := "null_hit"
const DODGE_COUNTER := "dodge_counter"
const BLEED_DAMAGE := "bleed_damage"
const COUNTER_EXPOSE := "counter_expose"
const NOT_HIT_POWER := "not_hit_power"
const COUNTER_HEAL := "counter_heal"
const CRIT_BLEED := "crit_bleed"
const ALLY_FALL_HEAL := "ally_fall_heal"
const ALLY_FALL_AP := "ally_fall_ap"
const ULTIMATE_AP := "ultimate_ap"
const AP_GUARD := "ap_guard"
const PERFECT_WINDOW := "perfect_window"
const HEALED_SHARE := "healed_share"
const ITEM_POWER := "item_power"
const FULL_START_AP := "full_start_ap"
const OTHER_PRESS := "other_press"
const PARRY_BLEED := "parry_bleed"
const DODGE_BLEED := "dodge_bleed"
const DODGE_HASTE := "dodge_haste"
const COUNTER_GAUGE := "counter_gauge"
const SKILL_COST_CUT := "skill_cost_cut"
const FIRST_TURN := "first_turn"
const LOW_HP_REGEN := "low_hp_regen"
const FIRST_HIT_GUARD := "first_hit_guard"
const HIT_AP := "hit_ap"
const HIT_HEAL := "hit_heal"
const BASIC_AP := "basic_ap"

const ALL: Array[String] = [START_AP, AP_ON_COUNTER, HEAL_ON_JUMP, COUNTER, SECOND_WIND, PERFECT_PRESS, EXPOSED,
	TOUGH, HEAL, ROT, CRIT, HEAL_TAKEN, KILL_HEAL, LOW_HP_POWER, DODGE_AP, PARRY_AP, THORNS, GAUGE, MARK_SHORTEN,
	PARRY_CLEANSE, WARD_START, FULL_HP_POWER, KILL_AP, START_EMPOWERED, START_REGEN, STAGGER_DAMAGE, CRIT_DAMAGE,
	PARRY_HEAL,
	COUNTER_TURN, COUNTER_EMPOWER, START_GUARDED, JUMP_AP, FIRST_HIT_EXPOSE, FIRST_HIT_BLEED, THIRD_SKILL,
	COUNTER_STACK, COUNTER_CRIT, COUNTER_CRIT_DAMAGE, FOLLOW_UP_DAMAGE, FIRST_STRIKE_EXPOSE, FIRST_STRIKE_SLOW,
	LEFTOVER_AP, SKILL_HIT_RAMP, LAST_STANDING_POWER, FALL_TEAM_AP, DODGE_ALL_CRIT, JUMP_ALL_CRIT,
	DEFEND_WINDOW, NULL_HIT, DODGE_COUNTER, BLEED_DAMAGE, COUNTER_EXPOSE, NOT_HIT_POWER, COUNTER_HEAL,
	CRIT_BLEED, ALLY_FALL_HEAL, ALLY_FALL_AP, ULTIMATE_AP, AP_GUARD, PERFECT_WINDOW, HEALED_SHARE, ITEM_POWER,
	FULL_START_AP, OTHER_PRESS, PARRY_BLEED, DODGE_BLEED, DODGE_HASTE, COUNTER_GAUGE, SKILL_COST_CUT,
	FIRST_TURN, LOW_HP_REGEN, FIRST_HIT_GUARD, HIT_AP, HIT_HEAL, BASIC_AP]


static func amount(c: Combatant, key: String) -> int:
	return int(c.passives.get(key, 0))
