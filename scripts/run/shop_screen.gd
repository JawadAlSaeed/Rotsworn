class_name ShopScreen
extends CanvasLayer
## A shop stop (DESIGN.md 8, 8.1): every item in the run's shop list, then a few pieces of gear
## (picked for this stop, ones the party does not own), each once per visit, paid with gold. A
## bought item goes into the backpack where it fits first; if there is no room the backpack opens
## with it in hand (leaving it behind gives the gold back). Bought gear goes on a hero at once:
## the backpack screen opens with it in hand. "Sell from the backpack" (or Tab / Y) opens the
## backpack where items sell for tuning.item_sell_percent of their price; "Leave" goes back to the
## map. Names show their rarity colour.

signal done

const TITLE_SIZE: int = 72
const TEXT_SIZE: int = 30
const DETAIL_SIZE: int = 26
## The backpack over the shop draws above it.
const OVERLAY_LAYER: int = 20

var _run: RunState
var _gear: Array[GearData] = []
## The items this shop sells: the run's shop list, then this stop's charms.
var _items: Array[ItemData] = []
var _bar: RunPartyBar
var _menu: ListMenu
var _prompt: Label
var _bought: Dictionary = {}
var _overlay: PartyScreen
## The item whose purchase waits on the backpack (refunded if it is left behind).
var _pending: ItemData


## `gear`: the gear this shop sells (RunState.shop_gear for the stop); `charms`: its charms
## (RunState.shop_charms).
func setup(run: RunState, gear: Array[GearData], charms: Array[ItemData] = []) -> void:
	_run = run
	_gear = gear
	_items = run.data.shop_items.duplicate()
	_items.append_array(charms)
	var column := ListMenu.screen_column(self, "Shop", TITLE_SIZE)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(centre)
	_bar = RunPartyBar.new()
	centre.add_child(_bar)
	_bar.setup(run)
	_prompt = ListMenu.centred_label("What do you need?", TEXT_SIZE)
	column.add_child(_prompt)
	_menu = ListMenu.new()
	column.add_child(_menu)
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	ListMenu.screen_footer(self, [[&"@updown", "Choose"], [&"menu_confirm", "Buy"], [&"party_menu", "Backpack"],
			[&"menu_cancel", "Back"]])
	_menu.set_items([], detail)
	_show_items()


## Items for sale, in the shop's list order (the run's shop list, then the stop's charms).
func items() -> Array[ItemData]:
	return _items


## How many things are for sale: items, then gear.
func count() -> int:
	return items().size() + _gear.size()


## The backpack screen open over the shop (null: none). The bot settles it.
func overlay() -> PartyScreen:
	return _overlay


## The name, price, description and rarity of thing `index`.
func _info(index: int) -> Array:
	if index < items().size():
		var item := items()[index]
		return [item.display_name, item.price, item.description, int(item.rarity)]
	var gear := _gear[index - items().size()]
	return ["%s (gear)" % gear.display_name, gear.price, gear.description, int(gear.rarity)]


## True if thing `index` is still for sale and affordable.
func can_buy(index: int) -> bool:
	if index < 0 or index >= count() or _bought.has(index):
		return false
	if index < items().size():
		return _run.can_afford(items()[index]) and _run.wants(items()[index])
	return _run.can_buy_gear(_gear[index - items().size()])


## Buys thing `index`. The bot calls this; the player uses the menu.
func buy(index: int) -> bool:
	if not can_buy(index):
		Sfx.play("locked")
		return false
	_bought[index] = true
	if index < items().size():
		var item := items()[index]
		_run.pay_for(item)
		Sfx.play("gold_gain")
		if item.kind == ItemData.Kind.UPGRADE:
			_run.add_item(item)
			Sfx.play("level_up")
			_prompt.text = "The backpack has %d rows now." % _run.backpack.rows
		elif _run.add_item(item) >= 0:
			Sfx.play("item_place")
			_prompt.text = "The %s is in the backpack." % item.display_name
		else:
			_pending = item
			_open_backpack("No room for the %s. Make room, or leave it (your gold comes back)." % item.display_name,
					{"item": item})
	else:
		var gear := _gear[index - items().size()]
		_run.buy_gear(gear)
		Sfx.play("gold_gain")
		_open_backpack("Bought the %s. Who wears it?" % gear.display_name, {"gear": gear})
	_bar.refresh(_run)
	_show_items()
	return true


func leave() -> void:
	done.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _overlay != null:
		return
	if event.is_action_pressed(&"party_menu", false, true):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_confirm")
		_open_backpack("Sell: pick an item, then Sell.", {})
		return
	var answer := _menu.handle(event)
	if answer == &"cancel":
		Sfx.play("menu_cancel")
		leave()
		return
	if answer != &"confirm":
		return
	if _menu.index == count():
		Sfx.play("menu_confirm")
		_open_backpack("Sell: pick an item, then Sell.", {})
		return
	if _menu.index > count():
		Sfx.play("menu_confirm")
		leave()
		return
	buy(_menu.index)


func _open_backpack(note: String, held: Dictionary) -> void:
	_overlay = PartyScreen.new()
	_overlay.layer = OVERLAY_LAYER
	_overlay.close_when_settled = not held.is_empty()
	_overlay.shop_mode = true
	add_child(_overlay)
	_overlay.setup(_run, note, held)
	_overlay.left_behind.connect(_on_left_behind)
	_overlay.done.connect(_close_backpack)


func _on_left_behind(thing: Resource) -> void:
	if _pending != null and thing == _pending:
		_run.gold += _pending.price
		_prompt.text = "You left the %s. Your gold is back." % _pending.display_name
		_bought.erase(items().find(_pending))
	_pending = null


func _close_backpack() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_pending = null
	_bar.refresh(_run)
	_show_items()


func _show_items() -> void:
	var list: Array[Dictionary] = []
	for i: int in count():
		var info := _info(i)
		var text := "%s   %d gold" % [info[0], info[1]]
		if _bought.has(i):
			text = "%s   SOLD" % info[0]
		list.append({"text": text, "enabled": can_buy(i), "detail": "%s (%s)" % [info[2], BackpackGrid.rarity_name(info[3])],
				"color": BackpackGrid.rarity_color(info[3])})
	list.append({"text": "Sell from the backpack", "detail": "Items sell for %d%% of their price." % _run.tuning.item_sell_percent})
	list.append({"text": "Leave", "detail": "Back to the map."})
	_menu.set_items(list)
