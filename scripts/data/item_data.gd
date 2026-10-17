class_name ItemData
extends Resource
## One thing that lives in the party's backpack (DESIGN.md 8.1): a consumable, a charm, a key or
## treasure. It has a shape on the backpack grid, a rarity and a price. Gear is not an item: it is
## always worn (GearData).

enum Kind {
	## Used up: in a fight (Items) or on the map.
	CONSUMABLE,
	## Works just by sitting in the backpack (phase 11 step 3).
	CHARM,
	## Opens one chest (phase 11 step 2).
	KEY,
	## Only worth gold at the shop.
	TREASURE,
	## Used the moment the party gets it (a bigger backpack); never kept in the backpack.
	UPGRADE,
}

## Charm families (DESIGN.md 8.1): some charms boost the charms of a family that touch them.
enum Family { NONE, STONE, BONE, HERB }

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
	## The backpack gets one more row (up to tuning.backpack_max_rows).
	ADD_ROW,
}

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.CONSUMABLE
@export var rarity: Rarity = Rarity.COMMON
## Shop price (gold). Selling pays tuning.item_sell_percent of it.
@export_range(0, 10000) var price: int = 30
## The cells it covers on the backpack grid, unturned (x right, y down). The top-left is (0, 0).
@export var shape: Array[Vector2i] = [Vector2i.ZERO]
@export var effect: Effect = Effect.NONE
@export_range(0, 1000, 1, "suffix:%") var amount_percent: int = 0
## In a fight, a healing item also removes this many hero debuffs from each hero it heals (card
## #194; see AbilityData.cleanse_count). 3 clears all.
@export_range(0, 3) var cleanse_count: int = 0
## How often it turns up in glinting spots and monster drops, against the run's other found
## items (a weight, not a percent).
@export_range(0, 1000) var find_weight: int = 10
## Can it be used on the map (from the backpack screen)?
@export var use_on_map: bool = true
## Can it be used in a fight (Items, Y)? Using one is the hero's action and costs ap_cost AP.
@export var use_in_fight: bool = false
@export_range(0, 9) var ap_cost: int = 1
## A charm's family, what it gives every hero while it is in the backpack (a gear effect and its
## amount), and the family whose touching charms it boosts by boost_percent (DESIGN.md 8.1).
@export var family: Family = Family.NONE
@export var charm_effect: GearData.Effect = GearData.Effect.POWER
@export_range(0, 1000) var charm_amount: int = 0
@export var boost_family: Family = Family.NONE
@export_range(0, 1000, 1, "suffix:%") var boost_percent: int = 0
## Rotten (DESIGN.md 8.1): very strong, but every hero loses rot_percent of their max HP at the
## start of each of their turns in a fight (never below 1 HP) while it is in the backpack. It
## cannot be sold.
@export var rotten: bool = false
@export_range(0, 100, 1, "suffix:%") var rot_percent: int = 0
## Its picture, drawn over its cells unturned (missing file: a placeholder).
@export_file_path("*.png") var icon_path: String = ""


## True if using it asks who gets it.
func needs_target() -> bool:
	return effect == Effect.HEAL_ONE or effect == Effect.MAX_HP_ONE or effect == Effect.REVIVE_ONE


## True if it can be used on the map (fight-only effects never are).
func usable_on_map() -> bool:
	return kind == Kind.CONSUMABLE and use_on_map and effect in [Effect.HEAL_ONE, Effect.HEAL_ALL, Effect.MAX_HP_ONE]


## True if it is a charm.
func is_charm() -> bool:
	return kind == Kind.CHARM


## True if two of it can be combined into a stronger one (consumables and charms). Not the Tonic: a
## stronger Tonic would give more max HP per drink and get round tonic_max_per_hero (card #198).
func combinable() -> bool:
	return (kind == Kind.CONSUMABLE and effect != Effect.MAX_HP_ONE) or kind == Kind.CHARM


## True if it can be used in a fight.
func usable_in_fight() -> bool:
	return kind == Kind.CONSUMABLE and use_in_fight and effect in [Effect.HEAL_ONE, Effect.HEAL_ALL, Effect.DAMAGE_ALL,
			Effect.REVIVE_ONE]


## The width and height of its unturned shape in cells.
func size() -> Vector2i:
	return Backpack.extent(shape)
