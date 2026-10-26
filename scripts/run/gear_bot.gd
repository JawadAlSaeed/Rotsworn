class_name GearBot
extends RefCounted
## The --run bot's rule for picking Relics and giving them out (DESIGN.md 8.16, 8.24). Pure, so
## tests can run it. It prefers the rarest piece, and takes a rot-touched one when its price is
## something the bot's careful play can live with (a drawback on Max HP, Power, Tough, healing, rot
## or Rest would hurt it, so those pieces are passed over). A Relic goes to the hero it helps most.

## Drawbacks the bot will not pay.
const COSTLY_DRAWBACKS: Array[int] = [
	GearData.Effect.MAX_HP, GearData.Effect.POWER, GearData.Effect.TOUGH, GearData.Effect.HEAL_TAKEN,
	GearData.Effect.ROT, GearData.Effect.WIN_WOUND, GearData.Effect.REST_HEAL,
]

## A worthwhile rot-touched piece scores this much above its rarity step.
const ROT_TOUCHED_BONUS: int = 15
## Each Relic a hero has already makes a new one suit them this many percent less (best_hero), so
## with no slot limit the finds still spread over the party, as a player would share them.
const HELD_SHARE_PERCENT: int = 15


## The score of one piece of spoils (-1: the bot refuses it).
static func score(item: GearData) -> int:
	var points := int(item.rarity) * 10
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


## The hero the bot gives Relic `item` to (DESIGN.md 8.24): the one it helps most (an offensive
## Relic the hardest hitter, a defensive one the toughest hero, a healing one a hero whose skills
## heal), each Relic they hold already counting HELD_SHARE_PERCENT against them, then the one with
## the fewest Relics, then the first. Only heroes of `allowed` (empty: any).
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
static func fit_of(hero: CharacterData, item: GearData) -> int:
	if hero == null or item == null:
		return 0
	if item.effect == GearData.Effect.HEAL:
		var heals := 0
		for skill: AbilityData in hero.skills:
			if skill != null and (skill.heal_percent > 0 or skill.revive_percent > 0):
				heals += 1
		return heals
	match item.category():
		GearData.Category.OFFENSIVE:
			return hero.power_percent
		GearData.Category.DEFENSIVE:
			return hero.hp_percent
	return 0
