class_name GearData
extends Resource
## One Relic (DESIGN.md 8.17, 8.24, 8.25; "gear" in the code, from before phase 17), like a Picto in
## Clair Obscur: one ability for the hero who has it (no stat line since phase 27). Elite stops,
## bosses, chests and shops offer them; the player picks one and gives it to a hero, who keeps it
## until the run ends (no slots, no copies). A campfire can upgrade it once to Relic+ (the "+"
## numbers below; RunState.relics_plus). The collection remembers every Relic found
## (RelicCollection).
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
	## Counters deal amount% more (a multiplier, DESIGN.md 8.25).
	COUNTER,
	## Once per fight, downed during an enemy attack: back up at its end with amount% HP.
	SECOND_WIND,
	## Perfect skill presses deal amount% more (a multiplier, DESIGN.md 8.25).
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
	## Any foe falls (whoever downed it): this character heals amount% of their max HP.
	KILL_HEAL,
	## Power +amount% while the HP is under tuning.rot_low_hp_percent.
	LOW_HP_POWER,
	## +amount AP on each dodge.
	DODGE_AP,
	## +amount AP on each parry (on top of the usual one).
	PARRY_AP,
	## Each parry hurts the attacker for amount% of the hit's damage (Bramble Coat, DESIGN.md 8.25).
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
	# --- Relics against marks (phase 19, card #263). Appended like the rest. ---
	## Marks on this character last amount fewer turns (never under 1).
	MARK_SHORTEN,
	## Each parry lifts amount of this character's marks.
	PARRY_CLEANSE,
	## Every fight starts with this character Warded (no marks) for amount of their turns.
	WARD_START,
	# --- More Relics (phase 20, card #242). Appended like the rest. ---
	## Power +amount% while this character is at full HP.
	FULL_HP_POWER,
	## +amount AP for each enemy this character downs or Staggers (breaks its Doom).
	KILL_AP,
	## After each fight won, this character heals amount% of their max HP (a run effect).
	WIN_HEAL,
	## Every fight starts with this character Empowered (their first damaging skill hits harder).
	START_EMPOWERED,
	## Every fight starts with this character under Regen for amount of their turns.
	START_REGEN,
	## This character's damage to a Staggered enemy is amount% bigger.
	STAGGER_DAMAGE,
	## This character's critical hits deal amount% more.
	CRIT_DAMAGE,
	## Each perfect parry heals this character amount% of their max HP.
	PARRY_HEAL,
	# --- Relics reworked (phase 27, DESIGN.md 8.25). Appended like the rest. ---
	## Each counter this character makes puts their own turn next.
	COUNTER_TURN,
	## Each counter this character makes leaves them Empowered.
	COUNTER_EMPOWER,
	## Every fight starts with this character Guarded for amount of their turns.
	START_GUARDED,
	## +amount AP on each jump.
	JUMP_AP,
	## This character's first hit each fight leaves the foe Exposed for amount turns.
	FIRST_HIT_EXPOSE,
	## This character's first hit each fight makes the foe Bleed for amount turns.
	FIRST_HIT_BLEED,
	## Every third damaging skill of this character deals amount% more.
	THIRD_SKILL,
	## Each counter adds amount% to this character's damage for the rest of the fight (capped by tuning).
	COUNTER_STACK,
	## This character's counters always crit (the roll is still made).
	COUNTER_CRIT,
	## This character's critical counters deal amount% more.
	COUNTER_CRIT_DAMAGE,
	## This character's follow-ups deal amount% more.
	FOLLOW_UP_DAMAGE,
	## A First Strike won leaves every foe Exposed for amount turns.
	FIRST_STRIKE_EXPOSE,
	## A First Strike won leaves every foe Slowed for amount turns.
	FIRST_STRIKE_SLOW,
	## Ending a turn with AP left gives the next hero +amount AP.
	LEFTOVER_AP,
	## Power +amount% in elite, guard and boss fights (a run effect: folded into the fight's power).
	ELITE_POWER,
	## Each hit of a skill deals amount% more than the hit before.
	SKILL_HIT_RAMP,
	## Power +amount% while this character is the last hero standing.
	LAST_STANDING_POWER,
	## This character falls: every living ally gets +amount AP.
	FALL_TEAM_AP,
	## Dodging every hit of an enemy attack makes this character's next skill crit.
	DODGE_ALL_CRIT,
	## Jumping every hit of an enemy attack makes this character's next skill crit.
	JUMP_ALL_CRIT,
	## This character's parry, dodge and jump windows are amount% wider (bounded by tuning).
	DEFEND_WINDOW,
	## The first amount hits that land on this character each fight do nothing.
	NULL_HIT,
	## This character's dodges can counter (normal hits only).
	DODGE_COUNTER,
	## This character's damage to a Bleeding foe is amount% bigger.
	BLEED_DAMAGE,
	## Each counter leaves the foe Exposed for amount turns.
	COUNTER_EXPOSE,
	## Power +amount% until this character is first hit in the fight.
	NOT_HIT_POWER,
	## Each counter heals this character amount% of their max HP.
	COUNTER_HEAL,
	## This character's critical hits make the foe Bleed for amount turns.
	CRIT_BLEED,
	## An ally falls: this character heals amount% of their max HP.
	ALLY_FALL_HEAL,
	## An ally falls: this character gets +amount AP.
	ALLY_FALL_AP,
	## The team ultimate gives the whole party +amount AP.
	ULTIMATE_AP,
	## Each hit that lands on this character: pay tuning.relic_ap_guard_cost AP (if they have it) to
	## take amount% less.
	AP_GUARD,
	## This character's perfect press window grows amount% of the way toward the good one (bounded by tuning).
	PERFECT_WINDOW,
	## Healed: this character's lowest living ally heals amount% of that.
	HEALED_SHARE,
	## Backpack items this character uses work amount% better.
	ITEM_POWER,
	## Every fight starts with this character at full AP.
	FULL_START_AP,
	## Skill presses that are not perfect deal amount% more (as a drawback: less).
	OTHER_PRESS,
	## Each parry makes the attacker Bleed for amount turns.
	PARRY_BLEED,
	## Each dodge makes the attacker Bleed for amount turns.
	DODGE_BLEED,
	## A dodge moves this character's next turn amount% of a turn sooner (once per enemy attack).
	DODGE_HASTE,
	## Any campfire pick also heals this character amount% of their max HP (a run effect).
	CAMPFIRE_HEAL,
	## Each counter adds amount to the team gauge.
	COUNTER_GAUGE,
	## This character's skills cost amount AP less (never below 0).
	SKILL_COST_CUT,
	## This character takes the first turn of every fight.
	FIRST_TURN,
	## Once a fight, falling under half HP: Regen for amount of this character's turns.
	LOW_HP_REGEN,
	## The first hit of each enemy attack on this character deals amount% less.
	FIRST_HIT_GUARD,
	## Hit by an enemy attack: +amount AP (once per attack).
	HIT_AP,
	## Hit by an enemy attack: heal amount% of max HP (once per attack).
	HIT_HEAL,
	## +amount AP at the start of every fight for each act reached (a run effect: folded into START_AP).
	ACT_START_AP,
	## The basic attack gives amount more AP.
	BASIC_AP,
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
	Effect.MARK_SHORTEN: Passive.MARK_SHORTEN, Effect.PARRY_CLEANSE: Passive.PARRY_CLEANSE,
	Effect.WARD_START: Passive.WARD_START,
	Effect.FULL_HP_POWER: Passive.FULL_HP_POWER, Effect.KILL_AP: Passive.KILL_AP,
	Effect.START_EMPOWERED: Passive.START_EMPOWERED, Effect.START_REGEN: Passive.START_REGEN,
	Effect.STAGGER_DAMAGE: Passive.STAGGER_DAMAGE, Effect.CRIT_DAMAGE: Passive.CRIT_DAMAGE,
	Effect.PARRY_HEAL: Passive.PARRY_HEAL,
	Effect.COUNTER_TURN: Passive.COUNTER_TURN, Effect.COUNTER_EMPOWER: Passive.COUNTER_EMPOWER,
	Effect.START_GUARDED: Passive.START_GUARDED, Effect.JUMP_AP: Passive.JUMP_AP,
	Effect.FIRST_HIT_EXPOSE: Passive.FIRST_HIT_EXPOSE, Effect.FIRST_HIT_BLEED: Passive.FIRST_HIT_BLEED,
	Effect.THIRD_SKILL: Passive.THIRD_SKILL, Effect.COUNTER_STACK: Passive.COUNTER_STACK,
	Effect.COUNTER_CRIT: Passive.COUNTER_CRIT, Effect.COUNTER_CRIT_DAMAGE: Passive.COUNTER_CRIT_DAMAGE,
	Effect.FOLLOW_UP_DAMAGE: Passive.FOLLOW_UP_DAMAGE, Effect.FIRST_STRIKE_EXPOSE: Passive.FIRST_STRIKE_EXPOSE,
	Effect.FIRST_STRIKE_SLOW: Passive.FIRST_STRIKE_SLOW, Effect.LEFTOVER_AP: Passive.LEFTOVER_AP,
	Effect.SKILL_HIT_RAMP: Passive.SKILL_HIT_RAMP, Effect.LAST_STANDING_POWER: Passive.LAST_STANDING_POWER,
	Effect.FALL_TEAM_AP: Passive.FALL_TEAM_AP, Effect.DODGE_ALL_CRIT: Passive.DODGE_ALL_CRIT,
	Effect.JUMP_ALL_CRIT: Passive.JUMP_ALL_CRIT, Effect.DEFEND_WINDOW: Passive.DEFEND_WINDOW,
	Effect.NULL_HIT: Passive.NULL_HIT, Effect.DODGE_COUNTER: Passive.DODGE_COUNTER,
	Effect.BLEED_DAMAGE: Passive.BLEED_DAMAGE, Effect.COUNTER_EXPOSE: Passive.COUNTER_EXPOSE,
	Effect.NOT_HIT_POWER: Passive.NOT_HIT_POWER, Effect.COUNTER_HEAL: Passive.COUNTER_HEAL,
	Effect.CRIT_BLEED: Passive.CRIT_BLEED, Effect.ALLY_FALL_HEAL: Passive.ALLY_FALL_HEAL,
	Effect.ALLY_FALL_AP: Passive.ALLY_FALL_AP, Effect.ULTIMATE_AP: Passive.ULTIMATE_AP,
	Effect.AP_GUARD: Passive.AP_GUARD, Effect.PERFECT_WINDOW: Passive.PERFECT_WINDOW,
	Effect.HEALED_SHARE: Passive.HEALED_SHARE, Effect.ITEM_POWER: Passive.ITEM_POWER,
	Effect.FULL_START_AP: Passive.FULL_START_AP, Effect.OTHER_PRESS: Passive.OTHER_PRESS,
	Effect.PARRY_BLEED: Passive.PARRY_BLEED, Effect.DODGE_BLEED: Passive.DODGE_BLEED,
	Effect.DODGE_HASTE: Passive.DODGE_HASTE, Effect.COUNTER_GAUGE: Passive.COUNTER_GAUGE,
	Effect.SKILL_COST_CUT: Passive.SKILL_COST_CUT, Effect.FIRST_TURN: Passive.FIRST_TURN,
	Effect.LOW_HP_REGEN: Passive.LOW_HP_REGEN, Effect.FIRST_HIT_GUARD: Passive.FIRST_HIT_GUARD,
	Effect.HIT_AP: Passive.HIT_AP, Effect.HIT_HEAL: Passive.HIT_HEAL,
	Effect.BASIC_AP: Passive.BASIC_AP,
}

## What a Relic is for, as the Echoes screen's tabs group them (like Expedition 33's Lumina tabs).
enum Category { OFFENSIVE, DEFENSIVE, SUPPORT }
const CATEGORY_NAMES: Array[String] = ["Offensive", "Defensive", "Support"]
## Effect -> Category (an effect not listed is Support).
const CATEGORIES := {
	Effect.POWER: Category.OFFENSIVE, Effect.COUNTER: Category.OFFENSIVE, Effect.PERFECT_PRESS: Category.OFFENSIVE,
	Effect.EXPOSED: Category.OFFENSIVE, Effect.LOW_HP_POWER: Category.OFFENSIVE, Effect.CRIT: Category.OFFENSIVE,
	Effect.THORNS: Category.OFFENSIVE,
	Effect.MAX_HP: Category.DEFENSIVE, Effect.TOUGH: Category.DEFENSIVE, Effect.SECOND_WIND: Category.DEFENSIVE,
	Effect.HEAL_ON_JUMP: Category.DEFENSIVE, Effect.KILL_HEAL: Category.DEFENSIVE, Effect.SPEED: Category.DEFENSIVE,
	Effect.MARK_SHORTEN: Category.DEFENSIVE, Effect.PARRY_CLEANSE: Category.DEFENSIVE, Effect.WARD_START: Category.DEFENSIVE,
	Effect.FULL_HP_POWER: Category.OFFENSIVE, Effect.START_EMPOWERED: Category.OFFENSIVE,
	Effect.STAGGER_DAMAGE: Category.OFFENSIVE, Effect.CRIT_DAMAGE: Category.OFFENSIVE,
	Effect.WIN_HEAL: Category.DEFENSIVE, Effect.START_REGEN: Category.DEFENSIVE, Effect.PARRY_HEAL: Category.DEFENSIVE,
	Effect.HEAL_TAKEN: Category.DEFENSIVE, Effect.START_GUARDED: Category.DEFENSIVE, Effect.FIRST_HIT_EXPOSE: Category.OFFENSIVE,
	Effect.FIRST_HIT_BLEED: Category.OFFENSIVE, Effect.THIRD_SKILL: Category.OFFENSIVE, Effect.COUNTER_STACK: Category.OFFENSIVE,
	Effect.COUNTER_CRIT: Category.OFFENSIVE, Effect.COUNTER_CRIT_DAMAGE: Category.OFFENSIVE, Effect.FOLLOW_UP_DAMAGE: Category.OFFENSIVE,
	Effect.FIRST_STRIKE_EXPOSE: Category.OFFENSIVE, Effect.FIRST_STRIKE_SLOW: Category.OFFENSIVE, Effect.ELITE_POWER: Category.OFFENSIVE,
	Effect.SKILL_HIT_RAMP: Category.OFFENSIVE, Effect.LAST_STANDING_POWER: Category.OFFENSIVE, Effect.DODGE_ALL_CRIT: Category.OFFENSIVE,
	Effect.JUMP_ALL_CRIT: Category.OFFENSIVE, Effect.DEFEND_WINDOW: Category.DEFENSIVE, Effect.NULL_HIT: Category.DEFENSIVE,
	Effect.BLEED_DAMAGE: Category.OFFENSIVE, Effect.COUNTER_EXPOSE: Category.OFFENSIVE, Effect.NOT_HIT_POWER: Category.OFFENSIVE,
	Effect.COUNTER_HEAL: Category.DEFENSIVE, Effect.CRIT_BLEED: Category.OFFENSIVE, Effect.AP_GUARD: Category.DEFENSIVE,
	Effect.OTHER_PRESS: Category.OFFENSIVE, Effect.PARRY_BLEED: Category.OFFENSIVE, Effect.DODGE_BLEED: Category.OFFENSIVE,
	Effect.CAMPFIRE_HEAL: Category.DEFENSIVE, Effect.LOW_HP_REGEN: Category.DEFENSIVE, Effect.FIRST_HIT_GUARD: Category.DEFENSIVE,
}

## Effects that only exist as a drawback: their amount is a loss, not a gain.
const LOSS_EFFECTS: Array[int] = [Effect.ROT, Effect.WIN_WOUND]
## Where the shipped tuning lives (Hollow Mantle's chip names its AP price).
const TUNING_PATH := "res://data/tuning/tuning.tres"

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

@export_group("Relic+ (DESIGN.md 8.25)")
## The "+" line the player reads (the upgraded ability, "Twice a fight.").
@export var plus_text: String = ""
## `amount` once upgraded (0: unchanged).
@export_range(0, 1000) var amount_plus: int = 0
## `drawback_amount` once upgraded (0: unchanged; no Relic+ drops its drawback).
@export_range(0, 1000) var drawback_amount_plus: int = 0
## A second effect the "+" adds (First Light's is its amount; Bone Whistle's "counters also +30%"
## is COUNTER 30), worn only once upgraded. `plus_rider_amount` 0: none.
@export var plus_rider: Effect = Effect.MAX_HP
@export_range(0, 1000) var plus_rider_amount: int = 0

@export_group("Relic (DESIGN.md 8.17)")
## The Relic's picture inside its diamond on the Relics screens (empty or missing: a drawn sign for
## its category, RelicIcon).
@export_file_path("*.png") var icon_path: String = ""


## Hollow Mantle's AP price for its chip: the shipped tuning's (the fight reads the same number).
static func _ap_guard_cost() -> int:
	var tuning := load(TUNING_PATH) as Tuning
	return (tuning if tuning != null else Tuning.new()).relic_ap_guard_cost


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
			return "Jumps heal %d%%" % amount
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
			return "Any foe falls: heal %d%%" % amount
		Effect.LOW_HP_POWER:
			return "Power +%d%% when low on HP" % amount
		Effect.DODGE_AP:
			return "+%d AP per dodge" % amount
		Effect.PARRY_AP:
			return "+%d AP per parry" % amount
		Effect.THORNS:
			return "Parries: attacker takes %d%% back" % amount
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
		Effect.MARK_SHORTEN:
			return "Marks last %d turn%s less" % [amount, "" if amount == 1 else "s"]
		Effect.PARRY_CLEANSE:
			return "Each parry lifts %d mark%s" % [amount, "" if amount == 1 else "s"]
		Effect.WARD_START:
			return "Warded for %d turn%s at fight start" % [amount, "" if amount == 1 else "s"]
		Effect.FULL_HP_POWER:
			return "Power +%d%% at full HP" % amount
		Effect.KILL_AP:
			return "Down or Stagger: +%d AP" % amount
		Effect.WIN_HEAL:
			return "Heal %d%% after each win" % amount
		Effect.START_EMPOWERED:
			return "Empowered at fight start" if amount <= 1 else "Start Empowered, %d skills" % amount
		Effect.START_REGEN:
			return "Start with Regen, %d turn%s" % [amount, _s(amount)]
		Effect.STAGGER_DAMAGE:
			return "+%d%% damage to Staggered foes" % amount
		Effect.CRIT_DAMAGE:
			return "Critical hits deal +%d%%" % amount
		Effect.PARRY_HEAL:
			return "Parries heal %d%%" % amount
		Effect.COUNTER_TURN:
			return "Counters: your turn next"
		Effect.COUNTER_EMPOWER:
			return "Counters make you Empowered"
		Effect.START_GUARDED:
			return "Start Guarded, %d turn%s" % [amount, _s(amount)]
		Effect.JUMP_AP:
			return "+%d AP per jump" % amount
		Effect.FIRST_HIT_EXPOSE:
			return "First hit Exposes the foe"
		Effect.FIRST_HIT_BLEED:
			return "First hit Bleeds the foe"
		Effect.THIRD_SKILL:
			return "Every third skill +%d%%" % amount
		Effect.COUNTER_STACK:
			return "+%d%% damage per counter" % amount
		Effect.COUNTER_CRIT:
			return "Counters always crit"
		Effect.COUNTER_CRIT_DAMAGE:
			return "Counter crits +%d%%" % amount
		Effect.FOLLOW_UP_DAMAGE:
			return "Follow-ups +%d%%" % amount
		Effect.FIRST_STRIKE_EXPOSE:
			return "First Strike: foes Exposed"
		Effect.FIRST_STRIKE_SLOW:
			return "First Strike: foes Slowed"
		Effect.LEFTOVER_AP:
			return "Spare AP: next hero +%d" % amount
		Effect.ELITE_POWER:
			return "+%d%% vs elites, bosses" % amount
		Effect.SKILL_HIT_RAMP:
			return "Each skill hit +%d%% more" % amount
		Effect.LAST_STANDING_POWER:
			return "+%d%% damage when last standing" % amount
		Effect.FALL_TEAM_AP:
			return "You fall: allies +%d AP" % amount
		Effect.DODGE_ALL_CRIT:
			return "Whole attack dodged: crit next"
		Effect.JUMP_ALL_CRIT:
			return "Whole attack jumped: crit next"
		Effect.DEFEND_WINDOW:
			return "Defence windows +%d%%" % amount
		Effect.NULL_HIT:
			return "Ignore %d hit%s a fight" % [amount, _s(amount)]
		Effect.DODGE_COUNTER:
			return "Dodges can counter"
		Effect.BLEED_DAMAGE:
			return "+%d%% damage to Bleeding foes" % amount
		Effect.COUNTER_EXPOSE:
			return "Counters Expose the foe"
		Effect.NOT_HIT_POWER:
			return "+%d%% damage until hit" % amount
		Effect.COUNTER_HEAL:
			return "Counters heal %d%%" % amount
		Effect.CRIT_BLEED:
			return "Crits Bleed for %d turn%s" % [amount, _s(amount)]
		Effect.ALLY_FALL_HEAL:
			return "Ally falls: heal %d%%" % amount
		Effect.ALLY_FALL_AP:
			return "Ally falls: +%d AP" % amount
		Effect.ULTIMATE_AP:
			return "Team ultimate: party +%d AP" % amount
		Effect.AP_GUARD:
			return "Pay %d AP: hits -%d%%" % [_ap_guard_cost(), amount]
		Effect.PERFECT_WINDOW:
			return "Perfect presses +%d%% easier" % amount
		Effect.HEALED_SHARE:
			return "Healed: lowest ally gets %d%%" % amount
		Effect.ITEM_POWER:
			return "Items +%d%%" % amount
		Effect.FULL_START_AP:
			return "Full AP at fight start"
		Effect.OTHER_PRESS:
			return "Other presses +%d%%" % amount
		Effect.PARRY_BLEED:
			return "Parries Bleed for %d turn%s" % [amount, _s(amount)]
		Effect.DODGE_BLEED:
			return "Dodges Bleed for %d turn%s" % [amount, _s(amount)]
		Effect.DODGE_HASTE:
			return "Dodge: next turn %d%% sooner" % amount
		Effect.CAMPFIRE_HEAL:
			return "Campfire: heal %d%%" % amount
		Effect.COUNTER_GAUGE:
			return "Counters: +%d team gauge" % amount
		Effect.SKILL_COST_CUT:
			return "Skills cost %d AP less" % amount
		Effect.FIRST_TURN:
			return "First turn of every fight"
		Effect.LOW_HP_REGEN:
			return "Low HP: Regen %d turn%s" % [amount, _s(amount)]
		Effect.FIRST_HIT_GUARD:
			return "First hit per attack -%d%%" % amount
		Effect.HIT_AP:
			return "Attack lands: +%d AP" % amount
		Effect.HIT_HEAL:
			return "Attack lands: heal %d%%" % amount
		Effect.ACT_START_AP:
			return "+%d start AP per act" % amount
		Effect.BASIC_AP:
			return "Basic attack: +%d AP" % amount
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
		Effect.OTHER_PRESS:
			return "Other presses -%d%%" % amount
	# Effects that are only ever a loss read the same either way.
	return effect_text(effect, amount)


## "s" for a count other than one (the effect texts' plurals).
static func _s(count: int) -> String:
	return "" if count == 1 else "s"


## True if this piece has a price to pay.
func has_drawback() -> bool:
	return drawback_amount > 0


## True if the Relic has a "+" (every Relic of phase 27 does; a bare test Relic may not).
func has_plus() -> bool:
	return amount_plus > 0 or drawback_amount_plus > 0 or plus_rider_amount > 0


## The effect's amount, as Relic+ when `upgraded`.
func amount_of(upgraded: bool = false) -> int:
	return amount_plus if upgraded and amount_plus > 0 else amount


## The drawback's amount, as Relic+ when `upgraded`.
func drawback_amount_of(upgraded: bool = false) -> int:
	if not has_drawback():
		return 0
	return drawback_amount_plus if upgraded and drawback_amount_plus > 0 else drawback_amount


## True if Relic+ adds a second effect (plus_rider).
func has_rider() -> bool:
	return plus_rider_amount > 0


## The piece's effect and drawback in one line ("Power +35%  |  Healing received -40%"); as Relic+
## (`upgraded`) with its numbers and its rider.
func effect_line(upgraded: bool = false) -> String:
	var line := effect_text(effect, amount_of(upgraded))
	if upgraded and has_rider():
		line += "  |  " + effect_text(plus_rider, plus_rider_amount)
	if has_drawback():
		line += "  |  " + drawback_text(drawback, drawback_amount_of(upgraded))
	return line


## The Relic's name as shown: "Name+" once it is upgraded (DESIGN.md 8.25).
func shown_name(upgraded: bool = false) -> String:
	return display_name + "+" if upgraded else display_name


## The Relic+ line ("Relic+: Guarded for 2 turns."), "" when it has no "+" text.
func plus_line() -> String:
	return "" if plus_text.is_empty() else "Relic+: " + plus_text


## The Relic's line in words: its description, and its Relic+ line after it once upgraded (the "+"
## text says only what changes, so the first line stays).
func text_line(upgraded: bool = false) -> String:
	if not upgraded or plus_text.is_empty():
		return description
	return (description + "  " + plus_line()).strip_edges()


## What Relic+ changes, as short texts (chips): the new amount, the rider, the smaller price (last,
## as plus_price_text).
func plus_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	if amount_plus > 0 and amount_plus != amount:
		texts.append(effect_text(effect, amount_plus))
	if has_rider():
		texts.append(effect_text(plus_rider, plus_rider_amount))
	var price := plus_price_text()
	if not price.is_empty():
		texts.append(price)
	return texts


## The smaller price Relic+ leaves ("Price now: Enemy hits +15%"), "" when the "+" keeps the price.
## Said as the price now, so a lower number never reads as a new cost.
func plus_price_text() -> String:
	if not has_drawback() or drawback_amount_plus <= 0 or drawback_amount_plus == drawback_amount:
		return ""
	return "Price now: " + drawback_text(drawback, drawback_amount_plus)


## Offensive, defensive or support (a Category, by its effect).
func category() -> int:
	return int(CATEGORIES.get(effect, Category.SUPPORT))


## The Passive key this gear gives in fights, or "" if it only changes stats or gold.
func passive_key() -> String:
	return String(PASSIVE_KEYS.get(effect, ""))


## What this piece adds to `of` (an Effect), signed: its effect adds `amount`, its drawback takes
## `drawback_amount` away. The effects that are only ever a loss (LOSS_EFFECTS: ROT, WIN_WOUND) add
## the amount of the loss instead, so a positive total is always "more of that loss". `upgraded`:
## as Relic+ (DESIGN.md 8.25): the "+" amounts, and the rider adds too.
func contribution(of: Effect, upgraded: bool = false) -> int:
	var total := 0
	if effect == of:
		total += amount_of(upgraded)
	if upgraded and has_rider() and plus_rider == of:
		total += plus_rider_amount
	if has_drawback() and drawback == of:
		var loss := drawback_amount_of(upgraded)
		total += loss if LOSS_EFFECTS.has(of) else -loss
	return total
