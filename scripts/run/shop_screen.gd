class_name ShopScreen
extends CanvasLayer
## A shop stop (DESIGN.md 8): every care item in the run's shop list, then a few pieces of gear
## (picked for this stop, ones the party does not own), each once per visit, paid with gold. A
## care item for one character asks who gets it; gear goes to the bag. "Leave" goes back to the map.

signal done

const TITLE_SIZE: int = 72
const TEXT_SIZE: int = 30
const DETAIL_SIZE: int = 26
const HINT_SIZE: int = 24

var _run: RunState
var _gear: Array[GearData] = []
var _bar: RunPartyBar
var _menu: ListMenu
var _prompt: Label
## Item index waiting for a character (-1: choosing an item).
var _picking: int = -1
var _bought: Dictionary = {}


## `gear`: the gear this shop sells (RunState.shop_gear for the stop).
func setup(run: RunState, gear: Array[GearData]) -> void:
	_run = run
	_gear = gear
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


## Care items (healing, tonics), in the shop's list order.
func items() -> Array[ShopItemData]:
	return _run.data.shop_items


## How many things are for sale: care items, then gear.
func count() -> int:
	return items().size() + _gear.size()


## The name, price and description of thing `index`.
func _info(index: int) -> Array:
	if index < items().size():
		var item := items()[index]
		return [item.display_name, item.price, item.description]
	var gear := _gear[index - items().size()]
	return ["%s (gear)" % gear.display_name, gear.price, gear.description]


func _needs_target(index: int) -> bool:
	return index < items().size() and items()[index].needs_target()


## True if thing `index` is still for sale and affordable.
func can_buy(index: int) -> bool:
	if index < 0 or index >= count() or _bought.has(index):
		return false
	if index < items().size():
		return _run.gold >= items()[index].price
	return _run.can_buy_gear(_gear[index - items().size()])


## Buys thing `index` (for character `slot` if it needs one). The bot calls this; the player
## uses the menus.
func buy(index: int, slot: int) -> bool:
	var ok := can_buy(index)
	if ok:
		ok = _run.buy(items()[index], slot) if index < items().size() else _run.buy_gear(_gear[index - items().size()])
	if not ok:
		Sfx.play("locked")
		return false
	_bought[index] = true
	Sfx.play("heal" if index < items().size() else "buff")
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
		buy(_picking, _menu.index)
		_show_items()
		return
	if _menu.index >= count():
		Sfx.play("menu_confirm")
		leave()
		return
	if not can_buy(_menu.index):
		Sfx.play("locked")
		return
	if _needs_target(_menu.index):
		Sfx.play("menu_confirm")
		_show_targets(_menu.index)
	else:
		buy(_menu.index, -1)


func _show_items() -> void:
	var keep := _picking if _picking >= 0 else _menu.index
	_picking = -1
	_prompt.text = "What do you need?"
	var list: Array[Dictionary] = []
	for i: int in count():
		var info := _info(i)
		var text := "%s   %d gold" % [info[0], info[1]]
		if _bought.has(i):
			text = "%s   SOLD" % info[0]
		list.append({"text": text, "enabled": can_buy(i), "detail": info[2]})
	list.append({"text": "Leave", "detail": "Back to the map."})
	_menu.index = keep
	_menu.set_items(list)


func _show_targets(index: int) -> void:
	_picking = index
	var item := items()[index]
	_prompt.text = "Who gets the %s?" % item.display_name
	var list: Array[Dictionary] = []
	for slot: int in _run.party_size():
		list.append({"text": "%s   %d / %d HP" % [_run.data.party[slot].display_name, _run.hp[slot], _run.max_hp(slot)],
				"detail": item.description})
	_menu.index = 0
	_menu.set_items(list)
