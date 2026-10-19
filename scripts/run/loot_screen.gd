class_name LootScreen
extends CanvasLayer
## Spoils after a zone's guard, an elite or an act's boss (DESIGN.md 8, 8.6): pick one of a few
## Relics (8.17) that are new or that a copy would still level up (rare or better while the run has
## them). It joins the Relics for good; the party screen comes next to put it on someone.

## The item picked (null: the party took nothing).
signal chosen(item: GearData)

const TITLE_SIZE: int = 72
const TEXT_SIZE: int = 30
const DETAIL_SIZE: int = 28

var _items: Array[GearData] = []
var _menu: ListMenu


## `text`: the line under the title (empty: the guard's). `run`: to say which Relics are new and
## which a copy would level up.
func setup(items: Array[GearData], text: String = "", run: RunState = null) -> void:
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
		var level := run.known_level(item) if run != null else 0
		var tag := "New" if level <= 0 else "Lv %d > %d" % [level, level + 1]
		list.append({"text": item.display_name, "value": tag,
				"detail": "%s (%s)  %s" % [item.description, BackpackGrid.rarity_name(step), item.stat_text(maxi(1, level + 1))],
				"color": GearData.ROT_TOUCHED_COLOR if item.rot_touched else BackpackGrid.rarity_color(step)})
	if items.is_empty():
		list.append({"text": "Nothing left to find", "detail": "Every Relic is at its top level."})
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
