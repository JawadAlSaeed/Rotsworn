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
## heal), then the one with the fewest Relics, then the first. Only heroes of `allowed` (empty: any).
static func best_hero(run: RunState, item: GearData, allowed: Array[int] = []) -> int:
	var best := -1
	var best_fit := -1
	for slot: int in run.party_size():
		if not allowed.is_empty() and not allowed.has(slot):
			continue
		var fit := fit_of(run.data.party[slot], item)
		var fewer := best >= 0 and run.relics_of(slot).size() < run.relics_of(best).size()
		if best < 0 or fit > best_fit or (fit == best_fit and fewer):
			best = slot
			best_fit = fit
	return maxi(best, 0)


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
