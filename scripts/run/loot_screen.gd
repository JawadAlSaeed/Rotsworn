class_name LootScreen
extends CanvasLayer
## Spoils after a zone's guard, an elite or an act's boss (DESIGN.md 8, 8.6): pick one of a few
## pieces of gear the party does not own yet (rare or better while the run has them). The party screen comes next, with it in hand, to put it on someone (gear is always worn,
## DESIGN.md 8.1).

## The item picked (null: the party took nothing).
signal chosen(item: GearData)

const TITLE_SIZE: int = 72
const TEXT_SIZE: int = 30
const DETAIL_SIZE: int = 28

var _items: Array[GearData] = []
var _menu: ListMenu


## `text`: the line under the title (empty: the guard's).
func setup(items: Array[GearData], text: String = "") -> void:
	_items = items
	var column := ListMenu.screen_column(self, "Spoils", TITLE_SIZE)
	column.add_child(ListMenu.centred_label(text if not text.is_empty() else "The guard left something behind. Take one.",
			TEXT_SIZE))
	_menu = ListMenu.new()
	column.add_child(_menu)
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	ListMenu.screen_footer(self, [[&"@updown", "Choose"], [&"menu_confirm", "Take"]])
	var list: Array[Dictionary] = []
	for item: GearData in items:
		var step := BackpackGrid.gear_step(item)
		list.append({"text": item.display_name, "detail": "%s (%s)" % [item.description, BackpackGrid.rarity_name(step)],
				"color": BackpackGrid.rarity_color(step)})
	if items.is_empty():
		list.append({"text": "Nothing left to find", "detail": "The party already has every piece of gear."})
	_menu.set_items(list, detail)


## The pieces on offer, in the order shown.
func choices() -> Array[GearData]:
	return _items


## Takes item `index` (the bot calls this; the player uses confirm).
func take(index: int) -> void:
	Sfx.play("buff")
	chosen.emit(_items[index] if index >= 0 and index < _items.size() else null)


func _unhandled_input(event: InputEvent) -> void:
	if _menu.handle(event) == &"confirm":
		take(_menu.index)
