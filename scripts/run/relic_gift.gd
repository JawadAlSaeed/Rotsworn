class_name RelicGift
extends RefCounted
## Giving a picked Relic to a hero (DESIGN.md 8.24), shared by the screens that offer Relics (spoils,
## the rotten chest, the shop, a pact, a Fight Rush card): which heroes may get it on this machine and
## the hero cards of the "Who gets it?" step. Solo every hero; local co-op the heroes of the player
## whose pad picked; online the heroes of the player whose turn it is (Main's give_heroes callable).

## The step's line over the hero cards.
const ASK := "Who gets it?"
## The hero's face on a card.
const PORTRAIT_PX := Vector2i(48, 48)


## Every hero slot of `run`, in order.
static func every_hero(run: RunState) -> Array[int]:
	var all: Array[int] = []
	if run != null:
		for slot: int in run.party_size():
			all.append(slot)
	return all


## The heroes who may get a Relic picked with `device` (a pad, PlayerRoster.KEYBOARD or
## PlayerRoster.ANY): `heroes.call(device)` when it is set and names any hero of the run, else every
## hero.
static func allowed(heroes: Callable, run: RunState, device: int = PlayerRoster.ANY) -> Array[int]:
	var all := every_hero(run)
	if not heroes.is_valid():
		return all
	var got: Array[int] = []
	var named: Variant = heroes.call(device)
	if named is Array:
		for slot: Variant in named:
			if typeof(slot) == TYPE_INT and all.has(int(slot)) and not got.has(int(slot)):
				got.append(int(slot))
	return got if not got.is_empty() else all


## One card per hero for giving a Relic (ListMenu items): the hero's face and name, and how many
## Relics they have. Only the heroes in `allowed_heroes` are lit (none while `watching`); "slot" is
## the hero's slot on every card.
static func hero_cards(run: RunState, allowed_heroes: Array[int], watching: bool = false) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	if run == null:
		return cards
	for slot: int in run.party_size():
		var hero := run.data.party[slot]
		var count := run.relics_of(slot).size()
		cards.append({"text": hero.display_name, "enabled": not watching and allowed_heroes.has(slot),
				"icon": AssetLoader.texture(hero.portrait_path, PORTRAIT_PX), "slot": slot,
				"chips": [{"glyph": &"gem", "text": str(count), "color": HudStyle.TEXT if count > 0 else HudStyle.TEXT_DIM}]})
	return cards


## The first lit card of hero_cards (the cursor's start), else 0.
static func first_lit(cards: Array[Dictionary]) -> int:
	for i: int in cards.size():
		if bool(cards[i].get("enabled", false)):
			return i
	return 0


## The bot's hero for `item` among `allowed_heroes` (GearBot.best_hero).
static func bot_hero(run: RunState, item: GearData, allowed_heroes: Array[int]) -> int:
	return GearBot.best_hero(run, item, allowed_heroes)
