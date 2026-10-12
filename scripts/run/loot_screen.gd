class_name LootScreen
extends CanvasLayer
## Loot after a zone's guard (DESIGN.md 8): pick one of a few pieces of gear the party does not
## own yet. It goes to the bag; the party screen comes next to put it on someone.

## The item picked (null: the party took nothing).
signal chosen(item: GearData)

const TITLE_SIZE: int = 72
const TEXT_SIZE: int = 30
const DETAIL_SIZE: int = 28
const HINT_SIZE: int = 24

var _items: Array[GearData] = []
var _menu: ListMenu


func setup(items: Array[GearData]) -> void:
	_items = items
	var column := ListMenu.screen_column(self, "Spoils", TITLE_SIZE)
	column.add_child(ListMenu.centred_label("The guard left something behind. Take one.", TEXT_SIZE))
	_menu = ListMenu.new()
	column.add_child(_menu)
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	column.add_child(ListMenu.centred_label("Up/Down choose   %s take" % HudStyle.binding_text(&"menu_confirm"),
			HINT_SIZE, HudStyle.TEXT_DIM))
	var list: Array[Dictionary] = []
	for item: GearData in items:
		list.append({"text": item.display_name, "detail": item.description})
	if items.is_empty():
		list.append({"text": "Nothing left to find", "detail": "The party already has every piece of gear."})
	_menu.set_items(list, detail)


## Takes item `index` (the bot calls this; the player uses confirm).
func take(index: int) -> void:
	Sfx.play("buff")
	chosen.emit(_items[index] if index >= 0 and index < _items.size() else null)


func _unhandled_input(event: InputEvent) -> void:
	if _menu.handle(event) == &"confirm":
		take(_menu.index)
