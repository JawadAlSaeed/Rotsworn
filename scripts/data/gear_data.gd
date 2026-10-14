class_name GearData
extends Resource
## One piece of gear (DESIGN.md 8), like a Picto in Clair Obscur: a passive effect for the
## character who wears it. Found as loot after a zone's guard, or bought in shops. Each item is
## worn by one character at a time; unworn gear waits in the party's bag.

enum Effect {
	## Max HP +amount%.
	MAX_HP,
	## Power +amount%.
	POWER,
	## Speed +amount (speed points).
	SPEED,
	## +amount AP at the start of every fight.
	START_AP,
	## +amount AP after each counter.
	AP_ON_COUNTER,
	## Heal amount% of max HP on each perfect jump.
	HEAL_ON_JUMP,
	## Counters +amount percent points.
	COUNTER,
	## Once per fight, downed during an enemy attack: back up at its end with amount% HP.
	SECOND_WIND,
	## Perfect skill presses +amount percent points.
	PERFECT_PRESS,
	## Exposed bonus +amount percent points.
	EXPOSED,
	## Enemy hits deal amount% less.
	TOUGH,
	## Heals this character gives +amount%.
	HEAL,
	## The party gets amount% more gold from fights.
	GOLD,
}

## Effect -> Passive key for the effects the fight engine runs ("" = folded into stats or the run).
const PASSIVE_KEYS := {
	Effect.START_AP: Passive.START_AP, Effect.AP_ON_COUNTER: Passive.AP_ON_COUNTER,
	Effect.HEAL_ON_JUMP: Passive.HEAL_ON_JUMP, Effect.COUNTER: Passive.COUNTER,
	Effect.SECOND_WIND: Passive.SECOND_WIND, Effect.PERFECT_PRESS: Passive.PERFECT_PRESS,
	Effect.EXPOSED: Passive.EXPOSED, Effect.TOUGH: Passive.TOUGH, Effect.HEAL: Passive.HEAL,
}

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Shop price (gold). Swapped out for new gear, it sells for tuning.item_sell_percent of this.
@export_range(0, 10000) var price: int = 60
## Common, rare or legendary (ItemData.Rarity): its name's colour, and how often loot offers it
## (rarer gear turns up more the deeper the run goes, DESIGN.md 8.1).
@export var rarity: ItemData.Rarity = ItemData.Rarity.COMMON
@export var effect: Effect = Effect.MAX_HP
@export_range(1, 1000) var amount: int = 10


## What an effect of `amount` does, in a few words ("Power +5%"), for charms and gear.
static func effect_text(effect: Effect, amount: int) -> String:
	match effect:
		Effect.MAX_HP:
			return "Max HP +%d%%" % amount
		Effect.POWER:
			return "Power +%d%%" % amount
		Effect.SPEED:
			return "Speed +%d" % amount
		Effect.START_AP:
			return "+%d AP at fight start" % amount
		Effect.AP_ON_COUNTER:
			return "+%d AP per counter" % amount
		Effect.HEAL_ON_JUMP:
			return "Perfect jumps heal %d%%" % amount
		Effect.COUNTER:
			return "Counters +%d%%" % amount
		Effect.SECOND_WIND:
			return "Second wind at %d%%" % amount
		Effect.PERFECT_PRESS:
			return "Perfect presses +%d%%" % amount
		Effect.EXPOSED:
			return "Exposed +%d%%" % amount
		Effect.TOUGH:
			return "Enemy hits -%d%%" % amount
		Effect.HEAL:
			return "Heals +%d%%" % amount
		Effect.GOLD:
			return "Gold +%d%%" % amount
	return ""


## The Passive key this gear gives in fights, or "" if it only changes stats or gold.
func passive_key() -> String:
	return String(PASSIVE_KEYS.get(effect, ""))
