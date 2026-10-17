class_name GearData
extends Resource
## One piece of gear (DESIGN.md 8), like a Picto in Clair Obscur: a passive effect for the
## character who wears it. Found as loot after a zone's guard, or bought in shops. Each item is
## worn by one character at a time; unworn gear waits in the party's bag.
## Rot-touched pieces (DESIGN.md 8.16) are strong but come with a price: a drawback, which is
## another effect worn as a loss (`drawback` / `drawback_amount`).

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
	# --- rot-touched effects (DESIGN.md 8.16). Appended, so saved gear files keep their numbers. ---
	## Healing this character receives +amount%.
	HEAL_TAKEN,
	## Each kill heals this character amount% of their max HP.
	KILL_HEAL,
	## Power +amount% while the HP is under tuning.rot_low_hp_percent.
	LOW_HP_POWER,
	## +amount AP on each dodge.
	DODGE_AP,
	## +amount AP on each parry (on top of the usual one).
	PARRY_AP,
	## Enemies whose hit lands on this character take amount% of the damage back.
	THORNS,
	## The team gauge this character's skills and follow-ups fill is amount% bigger.
	GAUGE,
	## Lose amount% of max HP at the start of each of this character's turns in a fight (never
	## below 1 HP). Only ever a drawback.
	ROT,
	## The campfire Rest heals this character amount% more (as a drawback: less).
	REST_HEAL,
	## Lose amount% of max HP for good after each fight won. Only ever a drawback.
	WIN_WOUND,
	## Critical hit chance +amount percent points (DESIGN.md 8.2).
	CRIT,
}

## Effect -> Passive key for the effects the fight engine runs ("" = folded into stats or the run).
const PASSIVE_KEYS := {
	Effect.START_AP: Passive.START_AP, Effect.AP_ON_COUNTER: Passive.AP_ON_COUNTER,
	Effect.HEAL_ON_JUMP: Passive.HEAL_ON_JUMP, Effect.COUNTER: Passive.COUNTER,
	Effect.SECOND_WIND: Passive.SECOND_WIND, Effect.PERFECT_PRESS: Passive.PERFECT_PRESS,
	Effect.EXPOSED: Passive.EXPOSED, Effect.TOUGH: Passive.TOUGH, Effect.HEAL: Passive.HEAL,
	Effect.HEAL_TAKEN: Passive.HEAL_TAKEN, Effect.KILL_HEAL: Passive.KILL_HEAL,
	Effect.LOW_HP_POWER: Passive.LOW_HP_POWER, Effect.DODGE_AP: Passive.DODGE_AP,
	Effect.PARRY_AP: Passive.PARRY_AP, Effect.THORNS: Passive.THORNS, Effect.GAUGE: Passive.GAUGE,
	Effect.ROT: Passive.ROT, Effect.CRIT: Passive.CRIT,
}

## Effects that only exist as a drawback: their amount is a loss, not a gain.
const LOSS_EFFECTS: Array[int] = [Effect.ROT, Effect.WIN_WOUND]

## A rot-touched piece's name colour, whatever its rarity: a bruised violet.
const ROT_TOUCHED_COLOR := Color(0.78, 0.4, 0.95)

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
## Rot-touched (DESIGN.md 8.16): strong, with a price. Shown in its own colour; spoils offer one.
@export var rot_touched: bool = false
## The price a rot-touched piece pays: this effect worn as a loss of `drawback_amount` (a Max HP
## drawback takes max HP away; a Tough drawback makes enemy hits hurt more). 0 = no drawback.
@export var drawback: Effect = Effect.MAX_HP
@export_range(0, 1000) var drawback_amount: int = 0


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
		Effect.HEAL_TAKEN:
			return "Healing received +%d%%" % amount
		Effect.KILL_HEAL:
			return "Each kill heals %d%%" % amount
		Effect.LOW_HP_POWER:
			return "Power +%d%% when low on HP" % amount
		Effect.DODGE_AP:
			return "+%d AP per dodge" % amount
		Effect.PARRY_AP:
			return "+%d AP per parry" % amount
		Effect.THORNS:
			return "Attackers take %d%% back" % amount
		Effect.GAUGE:
			return "Team gauge fills +%d%%" % amount
		Effect.ROT:
			return "Lose %d%% HP each turn" % amount
		Effect.REST_HEAL:
			return "Rest heals +%d%%" % amount
		Effect.WIN_WOUND:
			return "Lose %d%% max HP per win" % amount
		Effect.CRIT:
			return "Critical hits +%d%%" % amount
	return ""


## What a drawback of `amount` does, in a few words ("Max HP -15%"): the effect worn as a loss.
static func drawback_text(effect: Effect, amount: int) -> String:
	match effect:
		Effect.MAX_HP:
			return "Max HP -%d%%" % amount
		Effect.POWER:
			return "Power -%d%%" % amount
		Effect.SPEED:
			return "Speed -%d" % amount
		Effect.START_AP:
			return "-%d AP at fight start" % amount
		Effect.AP_ON_COUNTER:
			return "-%d AP per counter" % amount
		Effect.COUNTER:
			return "Counters -%d%%" % amount
		Effect.PERFECT_PRESS:
			return "Perfect presses -%d%%" % amount
		Effect.EXPOSED:
			return "Exposed -%d%%" % amount
		Effect.TOUGH:
			return "Enemy hits +%d%%" % amount
		Effect.HEAL:
			return "Heals you give -%d%%" % amount
		Effect.GOLD:
			return "Gold -%d%%" % amount
		Effect.HEAL_TAKEN:
			return "Healing received -%d%%" % amount
		Effect.PARRY_AP:
			return "Parries give %d less AP" % amount
		Effect.GAUGE:
			return "Team gauge fills -%d%%" % amount
		Effect.REST_HEAL:
			return "Rest heals %d%% less" % amount
		Effect.CRIT:
			return "Critical hits -%d%%" % amount
	# Effects that are only ever a loss read the same either way.
	return effect_text(effect, amount)


## True if this piece has a price to pay.
func has_drawback() -> bool:
	return drawback_amount > 0


## The piece's effect and drawback in one line ("Power +35%  |  Healing received -40%").
func effect_line() -> String:
	var line := effect_text(effect, amount)
	if has_drawback():
		line += "  |  " + drawback_text(drawback, drawback_amount)
	return line


## The Passive key this gear gives in fights, or "" if it only changes stats or gold.
func passive_key() -> String:
	return String(PASSIVE_KEYS.get(effect, ""))


## What this piece adds to `of` (an Effect), signed: its effect adds `amount`, its drawback takes
## `drawback_amount` away. The effects that are only ever a loss (LOSS_EFFECTS: ROT, WIN_WOUND) add
## the amount of the loss instead, so a positive total is always "more of that loss".
func contribution(of: Effect) -> int:
	var total := 0
	if effect == of:
		total += amount
	if has_drawback() and drawback == of:
		total += drawback_amount if LOSS_EFFECTS.has(of) else -drawback_amount
	return total
