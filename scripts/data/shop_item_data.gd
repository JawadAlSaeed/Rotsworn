class_name ShopItemData
extends Resource
## Something a shop sells in a run (DESIGN.md 8). Part A sells care for the party; gear arrives
## with Part B.

enum Effect {
	## Heals one character by `amount_percent` of their max HP.
	HEAL_ONE,
	## Heals every character by `amount_percent` of their max HP.
	HEAL_ALL,
	## Raises one character's max HP by `amount_percent` for the rest of the run (and heals that
	## much too, so the new HP is not empty).
	MAX_HP_ONE,
}

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_range(0, 10000) var price: int = 30
@export var effect: Effect = Effect.HEAL_ONE
@export_range(1, 1000, 1, "suffix:%") var amount_percent: int = 50


## True if the buyer has to pick a character.
func needs_target() -> bool:
	return effect != Effect.HEAL_ALL
