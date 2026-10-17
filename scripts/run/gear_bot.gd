class_name GearBot
extends RefCounted
## The --run bot's rule for picking spoils (DESIGN.md 8.16). Pure, so tests can run it.
## It prefers the rarest piece, and takes a rot-touched one when its price is something the bot's
## careful play can live with (a drawback on Max HP, Power, Tough, healing, rot or Rest would hurt
## it, so those pieces are passed over).

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
