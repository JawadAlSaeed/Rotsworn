class_name ShopScreen
extends CanvasLayer
## A shop stop (DESIGN.md 8): every item in the run's shop list, each once per visit, paid with
## gold. An item for one character asks who gets it. "Leave" goes back to the map.

signal done

const TITLE_SIZE: int = 72
const TEXT_SIZE: int = 30
const DETAIL_SIZE: int = 26
const HINT_SIZE: int = 24

var _run: RunState
var _bar: RunPartyBar
var _menu: ListMenu
var _prompt: Label
## Item index waiting for a character (-1: choosing an item).
var _picking: int = -1
var _bought: Dictionary = {}


func setup(run: RunState) -> void:
	_run = run
	var column := ListMenu.screen_column(self, "Shop", TITLE_SIZE)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(centre)
	_bar = RunPartyBar.new()
	centre.add_child(_bar)
	_bar.setup(run)
	_prompt = ListMenu.centred_label("", TEXT_SIZE)
	column.add_child(_prompt)
	_menu = ListMenu.new()
	column.add_child(_menu)
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	column.add_child(ListMenu.centred_label("Up/Down choose   %s buy   %s back" % [
			HudStyle.binding_text(&"menu_confirm"), HudStyle.binding_text(&"menu_cancel")], HINT_SIZE, HudStyle.TEXT_DIM))
	_menu.set_items([], detail)
	_show_items()


func items() -> Array[ShopItemData]:
	return _run.data.shop_items


## True if item `index` is still for sale and affordable.
func can_buy(index: int) -> bool:
	return index >= 0 and index < items().size() and not _bought.has(index) and _run.gold >= items()[index].price


## Buys item `index` for `slot` (the bot calls this; the player uses the menus).
func buy(index: int, slot: int) -> bool:
	if not can_buy(index) or not _run.buy(items()[index], slot):
		Sfx.play("locked")
		return false
	_bought[index] = true
	Sfx.play("heal")
	_bar.refresh(_run)
	_show_items()
	return true


func leave() -> void:
	done.emit()


func _unhandled_input(event: InputEvent) -> void:
	var answer := _menu.handle(event)
	if answer == &"cancel":
		Sfx.play("menu_cancel")
		if _picking >= 0:
			_show_items()
		else:
			leave()
		return
	if answer != &"confirm":
		return
	if _picking >= 0:
		var index := _picking
		buy(index, _menu.index)
		_show_items()
		return
	if _menu.index >= items().size():
		Sfx.play("menu_confirm")
		leave()
		return
	if not can_buy(_menu.index):
		Sfx.play("locked")
		return
	var item := items()[_menu.index]
	if item.needs_target():
		Sfx.play("menu_confirm")
		_show_targets(_menu.index)
	else:
		buy(_menu.index, -1)


func _show_items() -> void:
	var keep := _picking if _picking >= 0 else _menu.index
	_picking = -1
	_prompt.text = "What do you need?"
	var list: Array[Dictionary] = []
	for i: int in items().size():
		var item := items()[i]
		var text := "%s   %d gold" % [item.display_name, item.price]
		if _bought.has(i):
			text = "%s   SOLD" % item.display_name
		list.append({"text": text, "enabled": can_buy(i), "detail": item.description})
	list.append({"text": "Leave", "detail": "Back to the map."})
	_menu.index = keep
	_menu.set_items(list)


func _show_targets(index: int) -> void:
	_picking = index
	_prompt.text = "Who gets the %s?" % items()[index].display_name
	var list: Array[Dictionary] = []
	for slot: int in _run.party_size():
		list.append({"text": "%s   %d / %d HP" % [_run.data.party[slot].display_name, _run.hp[slot], _run.max_hp(slot)],
				"detail": items()[index].description})
	_menu.index = 0
	_menu.set_items(list)
