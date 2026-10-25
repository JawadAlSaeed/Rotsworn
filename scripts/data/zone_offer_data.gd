class_name ZoneOfferData
extends Resource
## A deal: pay this, get that. Every "?" event choice (EventChoiceData.deal and risk_deal, DESIGN.md
## 8.7) and every starting pact (8.19) is one. Paying and giving are done by RunState.take_offer
## (pure, tested); only in a run. The name is from the walkable zones' shrines and wanderers, which
## phase 26 turned into events (8.22, G7: the class name stays).

## Who loses max HP in a deal with cost_max_hp_percent (events, DESIGN.md 8.7).
enum HpTarget {
	## Every hero.
	EVERYONE,
	## The player picks the hero who pays (a risk, which asks nobody, picks one at random).
	CHOSEN,
	## One hero, picked by the run's seed (the same on every machine).
	RANDOM,
}

## Which backpack item a deal with cost_item takes.
enum ItemCost {
	NONE,
	## One at random (seeded).
	RANDOM,
	## The player picks it (a risk picks at random).
	CHOSEN,
}

## What a deal needs the player to pick before it can be taken.
enum Pick { NONE, HERO, ITEM }

@export var id: String = ""
@export var display_name: String = ""

@export_group("Price")
@export_range(0, 10000) var cost_gold: int = 0
## Every standing hero loses this percent of their max HP (never below 1 HP).
@export_range(0, 100, 1, "suffix:%") var cost_hp_percent: int = 0

@export_group("Price (events)")
## Permanent: the hero(es) lose this percent of their max HP for the rest of the run (never
## below tuning.event_max_hp_floor_percent of their normal max HP). A choice with this price is
## greyed out when every hero is already at the floor.
@export_range(0, 100, 1, "suffix:%") var cost_max_hp_percent: int = 0
@export var cost_max_hp_target: HpTarget = HpTarget.EVERYONE
## A backpack item is lost. Greyed out while the backpack has nothing to lose.
@export var cost_item: ItemCost = ItemCost.NONE
## A curse: this rotten item (rotting_heart, grave_moss) goes on the party at once (RunState.curses,
## card #332: never in the pack), where only the shop's Cleanse removes it. Never greyed: it needs no
## room.
@export var cost_rotten: ItemData

@export_group("Fight (events)")
## An ambush: after the story the party fights this encounter, through the run's own fight path
## (HP carries on, gold and XP as for any fight, the deep version in a deep act).
@export var ambush: EncounterData
## Beating the ambush also gives spoils (one piece of gear, like an elite's). Off: gold and XP only.
@export var ambush_spoils: bool = false

@export_group("Gift")
## Every hero heals this percent of their max HP (downed heroes too).
@export_range(0, 100, 1, "suffix:%") var heal_percent: int = 0
@export_range(0, 10000) var gold: int = 0
## Every hero gets this much XP.
@export_range(0, 10000) var xp: int = 0
## Added to the team gauge (up to its max).
@export_range(0, 1000) var team_gauge: int = 0
## A fixed item (for example a Salve).
@export var item: ItemData
## A found item of at least this rarity, picked by the run's seed (-1: none).
@export_range(-1, 2) var find_rarity: int = -1
## A Relic of at least this rarity, one the run lacks or can still level, picked by the run's seed
## (-1: none). The starting pacts give these (card #285).
@export_range(-1, 2) var relic_rarity: int = -1


## What the player must pick before this deal can be taken (nothing, a hero or a backpack item).
func pick_kind() -> Pick:
	if cost_item == ItemCost.CHOSEN:
		return Pick.ITEM
	if cost_max_hp_percent > 0 and cost_max_hp_target == HpTarget.CHOSEN:
		return Pick.HERO
	return Pick.NONE
