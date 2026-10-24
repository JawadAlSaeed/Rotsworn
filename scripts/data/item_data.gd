class_name ItemData
extends Resource
## One thing that lives in the party's backpack (DESIGN.md 8.1): a consumable, a curse, a key or
## treasure. It has a shape on the backpack grid, a rarity and a price. Relics are not items: they
## are worn (GearData). Phase 17 took the charms out (their buffs are what Relics and Echoes do now,
## DESIGN.md 8.17); the old charm files stay as treasure so older saves still load.

enum Kind {
	## Used up: in a fight (Items) or on the map.
	CONSUMABLE,
	## Only hurts: rotten, every hero loses rot_percent HP each turn in fights while it is carried.
	## Events give them as a price; a shop's Cleanse throws one away. (Was CHARM before phase 17.)
	CURSE,
	## Opens one chest (phase 11 step 2). Phase 26 took it out of the shop, finds and drops (it goes
	## with the chests, DESIGN.md 8.22 G3); the slot keeps its number so item files stay valid.
	KEY,
	## Only worth gold at the shop.
	TREASURE,
	## Used the moment the party gets it (a bigger backpack); never kept in the backpack.
	UPGRADE,
}

enum Rarity { COMMON, RARE, LEGENDARY }

enum Effect {
	## No effect of its own (keys, treasure).
	NONE,
	## Heals one character by `amount_percent` of their max HP.
	HEAL_ONE,
	## Heals every character by `amount_percent` of their max HP.
	HEAL_ALL,
	## Raises one character's max HP by `amount_percent` for the rest of the run (and heals that
	## much too, so the new HP is not empty).
	MAX_HP_ONE,
	## In a fight: hits every enemy for `amount_percent` of tuning.base_party_damage.
	DAMAGE_ALL,
	## In a fight: brings a downed ally back with `amount_percent` of their max HP.
	REVIVE_ONE,
	## The pack gets one more pocket (up to tuning.backpack_max_pockets; the name is from the old
	## grid's rows).
	ADD_ROW,
	## In a fight: lifts `cleanse_count` marks from one hero (Antidote, card #254), then heals
	## `amount_percent` of their max HP (0 = no heal).
	CLEANSE_ONE,
	## In a fight: the same for every standing hero (Holy Water).
	CLEANSE_ALL,
}

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## A fight item's line in the fight's Items list, 3 to 6 plain words (card #292), shown over icon
## chips worked out from its effect. Empty: the list shows `description` instead.
@export var short_text: String = ""
@export var kind: Kind = Kind.CONSUMABLE
@export var rarity: Rarity = Rarity.COMMON
## Shop price (gold). Selling pays tuning.item_sell_percent of it.
@export_range(0, 10000) var price: int = 30
## The cells it covers on the backpack grid, unturned (x right, y down). The top-left is (0, 0).
@export var shape: Array[Vector2i] = [Vector2i.ZERO]
@export var effect: Effect = Effect.NONE
@export_range(0, 1000, 1, "suffix:%") var amount_percent: int = 0
## In a fight, a healing or cleansing item removes this many hero debuffs from each hero it reaches
## (card #194; see AbilityData.cleanse_count). Status.CLEANSE_ALL (9) clears all.
@export_range(0, 9) var cleanse_count: int = 0
## How often it turns up in glinting spots and monster drops, against the run's other found
## items (a weight, not a percent).
@export_range(0, 1000) var find_weight: int = 10
## Can it be used on the map (from the backpack screen)?
@export var use_on_map: bool = true
## Can it be used in a fight (Items, Y)? Using one is the hero's action and costs ap_cost AP.
@export var use_in_fight: bool = false
@export_range(0, 9) var ap_cost: int = 1
## Rotten (DESIGN.md 8.1): every hero loses rot_percent of their max HP at the start of each of
## their turns in a fight (never below 1 HP) while it is in the backpack. It cannot be sold.
@export var rotten: bool = false
@export_range(0, 100, 1, "suffix:%") var rot_percent: int = 0
## Its picture, drawn over its cells unturned (missing file: a placeholder).
@export_file_path("*.png") var icon_path: String = ""


## True if using it asks who gets it.
func needs_target() -> bool:
	return effect == Effect.HEAL_ONE or effect == Effect.MAX_HP_ONE or effect == Effect.REVIVE_ONE 			or effect == Effect.CLEANSE_ONE


## True if it can be used on the map (fight-only effects never are).
func usable_on_map() -> bool:
	return kind == Kind.CONSUMABLE and use_on_map and effect in [Effect.HEAL_ONE, Effect.HEAL_ALL, Effect.MAX_HP_ONE]


## True if it is a curse.
func is_curse() -> bool:
	return kind == Kind.CURSE


## True if two of it can be combined into a stronger one (consumables). Not the Tonic: a stronger
## Tonic would give more max HP per drink and get round tonic_max_per_hero (card #198).
func combinable() -> bool:
	return kind == Kind.CONSUMABLE and effect != Effect.MAX_HP_ONE


## True if it can be used in a fight.
func usable_in_fight() -> bool:
	return kind == Kind.CONSUMABLE and use_in_fight and effect in [Effect.HEAL_ONE, Effect.HEAL_ALL, Effect.DAMAGE_ALL,
			Effect.REVIVE_ONE, Effect.CLEANSE_ONE, Effect.CLEANSE_ALL]


## The width and height of its shape in 16 px icon cells (its picture's size; since phase 21 every
## item takes one pocket whatever its shape, card #282).
func size() -> Vector2i:
	var extent := Vector2i.ONE
	for c: Vector2i in shape:
		extent = Vector2i(maxi(extent.x, c.x + 1), maxi(extent.y, c.y + 1))
	return extent
