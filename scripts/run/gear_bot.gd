class_name GearBot
extends RefCounted
## The --run bot's rule for picking Relics, giving them out and upgrading them (DESIGN.md 8.16, 8.24,
## 8.25). Pure, so tests can run it. It prefers the rarest piece, and takes a rot-touched one when its
## price is something the bot's careful play can live with (a drawback on Max HP, Power, Tough,
## healing, rot, Rest or parry AP would hurt it, so those pieces are passed over). The bot parries
## every normal hit it can (Autoplay), so a Relic that answers a parry or a counter suits it a little
## more, and one that only answers a dodge a lot less. A Relic goes to the hero it helps most. At a
## campfire it upgrades the Relic whose "+" helps most (upgrade_pick).

## Drawbacks the bot will not pay.
const COSTLY_DRAWBACKS: Array[int] = [
	GearData.Effect.MAX_HP, GearData.Effect.POWER, GearData.Effect.TOUGH, GearData.Effect.HEAL_TAKEN,
	GearData.Effect.ROT, GearData.Effect.WIN_WOUND, GearData.Effect.REST_HEAL, GearData.Effect.PARRY_AP,
]
## Effects that answer a parry or a counter: the bot's own play, so they score LIKED_BONUS more.
const PARRY_HOOKS: Array[int] = [
	GearData.Effect.THORNS, GearData.Effect.PARRY_AP, GearData.Effect.PARRY_HEAL, GearData.Effect.PARRY_CLEANSE,
	GearData.Effect.PARRY_BLEED, GearData.Effect.COUNTER, GearData.Effect.AP_ON_COUNTER, GearData.Effect.COUNTER_TURN,
	GearData.Effect.COUNTER_EMPOWER, GearData.Effect.COUNTER_STACK, GearData.Effect.COUNTER_CRIT,
	GearData.Effect.COUNTER_CRIT_DAMAGE, GearData.Effect.COUNTER_EXPOSE, GearData.Effect.COUNTER_HEAL,
	GearData.Effect.COUNTER_GAUGE,
]
## Effects that only answer a dodge (the bot dodges little): they score DODGE_PENALTY less, and a
## Relic+ rider of this kind is worth nothing to it.
const DODGE_HOOKS: Array[int] = [
	GearData.Effect.DODGE_AP, GearData.Effect.DODGE_HASTE, GearData.Effect.DODGE_ALL_CRIT,
	GearData.Effect.DODGE_COUNTER, GearData.Effect.DODGE_BLEED,
]

## Every piece starts at this score, so even a dodge-only common one stays welcome (score >= 0).
const BASE_SCORE: int = 10
## A worthwhile rot-touched piece scores this much above its rarity step.
const ROT_TOUCHED_BONUS: int = 15
const LIKED_BONUS: int = 5
const DODGE_PENALTY: int = 8
## Each Relic a hero has already makes a new one suit them this many percent less (best_hero), so
## with no slot limit the finds still spread over the party, as a player would share them.
const HELD_SHARE_PERCENT: int = 15
## What a Relic+ rider (a second effect) is worth to upgrade_gain, against a bigger number's percent.
const RIDER_GAIN: int = 60
## fit_of for "the frailest hero suits it most" (Martyr's Ash): this minus the hero's HP percent.
const FRAIL_FIT_BASE: int = 300


## The score of one piece of spoils (-1: the bot refuses it).
static func score(item: GearData) -> int:
	var points := BASE_SCORE + int(item.rarity) * 10 + _worth(int(item.effect))
	if item.rot_touched:
		if item.has_drawback() and COSTLY_DRAWBACKS.has(int(item.drawback)):
			return -1
		points += ROT_TOUCHED_BONUS
	return points


## The index of the piece the bot takes (the first of equal scores); 0 if it refuses all or the
## list is empty.
static func pick(items: Array[GearData]) -> int:
	var best := 0
	var best_score := -1
	for i: int in items.size():
		var points := score(items[i])
		if points > best_score:
			best = i
			best_score = points
	return best


## How much the bot likes effect `effect` for its own play: LIKED_BONUS for a parry or counter
## hook, -DODGE_PENALTY for a dodge-only one, else 0.
static func _worth(effect: int) -> int:
	if PARRY_HOOKS.has(effect):
		return LIKED_BONUS
	if DODGE_HOOKS.has(effect):
		return -DODGE_PENALTY
	return 0


## How much Relic+ helps `item` for the bot (higher: more; -1: it has no "+"): the percent its
## number grows, RIDER_GAIN for a rider the bot can use, the percent its price shrinks, plus the
## Relic's own worth to the bot and its rarity step, so a stronger Relic's "+" wins a tie.
static func upgrade_gain(item: GearData) -> int:
	if item == null or not item.has_plus():
		return -1
	var gain := 0
	if item.amount > 0 and item.amount_plus > item.amount:
		@warning_ignore("integer_division")
		gain += (item.amount_plus - item.amount) * 100 / item.amount
	if item.has_rider() and not DODGE_HOOKS.has(int(item.plus_rider)):
		gain += RIDER_GAIN
	var price := item.drawback_amount
	if item.has_drawback() and item.drawback_amount_plus > 0 and item.drawback_amount_plus < price:
		@warning_ignore("integer_division")
		gain += (price - item.drawback_amount_plus) * 100 / price
	return gain + _worth(int(item.effect)) + int(item.rarity) * 10


## The Relic the bot upgrades at a campfire among `items` (RunState.upgradable): the one whose "+"
## helps most (upgrade_gain), the first of equal ones; null when there is none.
static func upgrade_pick(_run: RunState, items: Array[GearData]) -> GearData:
	var best: GearData = null
	var best_gain := -1
	for item: GearData in items:
		var gain := upgrade_gain(item)
		if gain > best_gain:
			best = item
			best_gain = gain
	return best


## The hero the bot gives Relic `item` to (DESIGN.md 8.24): the one it helps most (an offensive
## Relic the hardest hitter, a defensive one the toughest hero, a healing one a hero whose skills
## heal; see fit_of), each Relic they hold already counting HELD_SHARE_PERCENT against them, then the
## one with the fewest Relics, then the first. Only heroes of `allowed` (empty: any).
static func best_hero(run: RunState, item: GearData, allowed: Array[int] = []) -> int:
	var best := -1
	for slot: int in run.party_size():
		if not allowed.is_empty() and not allowed.has(slot):
			continue
		if best < 0 or _suits_more(run, item, slot, best):
			best = slot
	return maxi(best, 0)


## True if `item` suits hero `a` more than hero `b` (best_hero): fit over (100 + held share), compared
## cross-multiplied to stay in integers; a tie goes to the one with fewer Relics.
static func _suits_more(run: RunState, item: GearData, a: int, b: int) -> bool:
	var held_a := run.relics_of(a).size()
	var held_b := run.relics_of(b).size()
	var left := fit_of(run.data.party[a], item) * (100 + held_b * HELD_SHARE_PERCENT)
	var right := fit_of(run.data.party[b], item) * (100 + held_a * HELD_SHARE_PERCENT)
	if left != right:
		return left > right
	return held_a < held_b


## How well Relic `item` suits hero `hero` (higher: better; 0: no hero suits it more than another).
## Healing given: a hero whose skills heal. Cheaper skills: the hero whose skills cost most. The last
## one standing and an ally's fall: the toughest. Help when you fall: the frailest. Then by category:
## offensive the hardest hitter, defensive the toughest, support anyone.
static func fit_of(hero: CharacterData, item: GearData) -> int:
	if hero == null or item == null:
		return 0
	match item.effect:
		GearData.Effect.HEAL:
			var heals := 0
			for skill: AbilityData in hero.skills:
				if skill != null and (skill.heal_percent > 0 or skill.revive_percent > 0):
					heals += 1
			return heals
		GearData.Effect.SKILL_COST_CUT:
			var cost := 0
			for skill: AbilityData in hero.skills:
				if skill != null:
					cost += maxi(0, skill.ap_cost)
			return cost
		GearData.Effect.LAST_STANDING_POWER, GearData.Effect.ALLY_FALL_HEAL, GearData.Effect.ALLY_FALL_AP:
			return hero.hp_percent
		GearData.Effect.FALL_TEAM_AP:
			return maxi(1, FRAIL_FIT_BASE - hero.hp_percent)
	match item.category():
		GearData.Category.OFFENSIVE:
			return hero.power_percent
		GearData.Category.DEFENSIVE:
			return hero.hp_percent
	return 0
