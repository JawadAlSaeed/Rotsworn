class_name ShopScreen
extends CanvasLayer
## A shop stop as a place (DESIGN.md 8.10, card #160): the shopkeeper on the left with a line to say,
## the shelves on the right with this stop's stock (a few items, a few charms, a few pieces of gear;
## user 2026-10-16: the whole list was too crowded), each with its picture, name and price, and
## under them the services: Cleanse (throw away a rotten item), Upgrade (an item up a level),
## Restock (new wares), Sell (the backpack opens to sell) and Leave. Healing is bought as items. Arrows
## move over the shelves and services, Confirm buys or uses, Tab / Y opens the backpack to sell,
## Back leaves. A bought item goes into the backpack where it fits first; with no room the backpack
## opens with it in hand (leaving it gives the gold back). Bought gear goes on a hero at once.
## The bot uses count(), can_buy(), buy(), overlay() and leave().

signal done
## Host: the shelves changed (a restock): Main tells the clients the new wares.
signal restocked

const TITLE_SIZE: int = 64
const TEXT_SIZE: int = 28
const DETAIL_SIZE: int = 26
const CARD_TEXT: int = 22
## The backpack over the shop draws above it.
const OVERLAY_LAYER: int = 20
const SHELF_COLUMNS: int = 4
const CARD_SIZE := Vector2(190.0, 150.0)
const ICON_SCALE: int = 3
const KEEPER_SCALE: int = 7
const SERVICES: Array[String] = ["cleanse", "upgrade", "restock", "sell", "leave"]
const SHELF_BG := Color(0.16, 0.11, 0.08, 0.92)
const SHELF_EDGE := Color(0.42, 0.3, 0.18)
const SOLD_DIM := Color(1.0, 1.0, 1.0, 0.35)

var _run: RunState
var _gear: Array[GearData] = []
## The items this shop sells: the stop's stock (RunState.shop_stock), then its charms.
var _items: Array[ItemData] = []
var _bar: RunPartyBar
var _say: Label
var _detail: Label
var _shelf: GridContainer
var _services: HBoxContainer
var _cards: Array[PanelContainer] = []
var _service_cards: Array[PanelContainer] = []
## Selected: a shelf card (0 .. count()-1) or a service (count() + service index).
var _sel: int = 0
var _bought: Dictionary = {}
var _overlay: PartyScreen
## The item whose purchase waits on the backpack (refunded if it is left behind).
var _pending: ItemData
## Picking an item for Cleanse or Upgrade: a list over the shelves (uids in menu order).
var _pick_menu: ListMenu
var _pick_panel: PanelContainer
var _pick_uids: Array[int] = []
var _pick_kind: String = ""
var _gear_icon: Texture2D


## `gear`: the gear this shop sells (RunState.shop_gear for the stop); `charms`: its charms
## (RunState.shop_charms).
func setup(run: RunState, gear: Array[GearData], charms: Array[ItemData] = [],
		keeper_path: String = "res://assets/sprites/env/shopkeeper.png") -> void:
	_run = run
	_gear = gear
	_items = run.shop_stock(run.at)
	_items.append_array(charms)
	_gear_icon = AssetLoader.texture("res://assets/sprites/ui/gear_icon.png", Vector2i(16, 16))
	var column := ListMenu.screen_column(self, "The Rag Merchant", TITLE_SIZE)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(centre)
	_bar = RunPartyBar.new()
	centre.add_child(_bar)
	_bar.setup(run)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	column.add_child(row)
	row.add_child(_keeper(keeper_path))

	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 14)
	row.add_child(right)
	var shelf_panel := PanelContainer.new()
	shelf_panel.add_theme_stylebox_override("panel", _box(SHELF_BG, SHELF_EDGE, 3, 14))
	shelf_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(shelf_panel)
	_shelf = GridContainer.new()
	_shelf.columns = SHELF_COLUMNS
	_shelf.add_theme_constant_override("h_separation", 10)
	_shelf.add_theme_constant_override("v_separation", 10)
	_shelf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shelf_panel.add_child(_shelf)
	_services = HBoxContainer.new()
	_services.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_services.add_theme_constant_override("separation", 10)
	right.add_child(_services)

	_detail = ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(1200.0, 0.0)
	_detail.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_detail)
	ListMenu.screen_footer(self, [[&"@move", "Choose"], [&"menu_confirm", "Buy"], [&"party_menu", "Sell"],
			[&"menu_cancel", "Leave"]])
	_rebuild()


## The shopkeeper, standing behind the corner of the counter, and what he says.
func _keeper(path: String) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	var art := TextureRect.new()
	art.texture = AssetLoader.texture(path, Vector2i(32, 48))
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = art.texture.get_size() * KEEPER_SCALE
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(art)
	_say = HudStyle.make_label("\"Coin for comfort. Have a look.\"", TEXT_SIZE, HudStyle.GOLD)
	_say.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_say.custom_minimum_size = Vector2(320.0, 0.0)
	box.add_child(_say)
	return box


## Items for sale: the stop's stock, then its charms.
func items() -> Array[ItemData]:
	return _items


## How many things are on the shelves: items, then gear.
func count() -> int:
	return items().size() + _gear.size()


## The backpack screen open over the shop (null: none). The bot settles it.
func overlay() -> PartyScreen:
	return _overlay


## The name, price, description, rarity and picture of thing `index`.
func _info(index: int) -> Array:
	if index < items().size():
		var item := items()[index]
		return [item.display_name, _run.item_price(item), item.description, int(item.rarity),
				AssetLoader.texture(item.icon_path, item.size() * 16)]
	var gear := _gear[index - items().size()]
	return [gear.display_name, _run.gear_price(gear), "Gear: " + gear.description, int(gear.rarity), _gear_icon]


## True if thing `index` is still for sale and affordable.
func can_buy(index: int) -> bool:
	if index < 0 or index >= count() or _bought.has(index):
		return false
	if index < items().size():
		return _run.can_afford(items()[index]) and _run.wants(items()[index])
	return _run.can_buy_gear(_gear[index - items().size()])


## Buys thing `index`. The bot calls this; the player uses the shelves.
func buy(index: int) -> bool:
	if not can_buy(index):
		Sfx.play("locked")
		_say.text = "\"Not for that purse.\"" if index < count() and not _bought.has(index) else "\"Sold already.\""
		return false
	_bought[index] = true
	if index < items().size():
		var item := items()[index]
		_run.pay_for(item)
		Sfx.play("gold_gain")
		if item.kind == ItemData.Kind.UPGRADE:
			_run.add_item(item)
			Sfx.play("level_up")
			_say.text = "\"A bigger pack. %d rows now.\"" % _run.backpack.rows
		elif _run.add_item(item) >= 0:
			Sfx.play("item_place")
			_say.text = "\"The %s. Good choice.\"" % item.display_name
		else:
			_pending = item
			_open_backpack("No room for the %s. Make room, or leave it (your gold comes back)." % item.display_name,
					{"item": item})
	else:
		var gear := _gear[index - items().size()]
		_run.buy_gear(gear)
		Sfx.play("gold_gain")
		_say.text = "\"Wear it well.\""
		_open_backpack("Bought the %s. Who wears it?" % gear.display_name, {"gear": gear})
	_rebuild()
	return true


## Restock service: new charms and gear (Main gives the new wares with set_wares()).
func restock() -> bool:
	if not _run.restock():
		Sfx.play("locked")
		return false
	Sfx.play("gold_gain")
	_say.text = "\"Let me see what is in the back.\""
	set_wares(_run.shop_gear(_run.at), _run.shop_charms(_run.at))
	restocked.emit()
	return true


## New wares on the shelves (after a restock; online clients get them from the host).
func set_wares(gear: Array[GearData], charms: Array[ItemData]) -> void:
	_gear = gear
	_items = _run.shop_stock(_run.at)
	_items.append_array(charms)
	_bought.clear()
	_rebuild()


func leave() -> void:
	done.emit()


func _service_info(kind: String) -> Array:
	var t := _run.tuning
	match kind:
		"cleanse":
			var rotten := not _run.rotten_uids().is_empty()
			return ["Cleanse", "%d gold" % _run.cleanse_price(), "Throw away one rotten item from the backpack." if rotten
					else "Nothing rotten in the backpack.", rotten and _run.gold >= _run.cleanse_price()]
		"upgrade":
			var any := false
			for e: Dictionary in _run.backpack.entries:
				any = any or _run.can_upgrade(int(e.uid))
			return ["Upgrade", "%d gold" % _run.upgrade_price(), "One item in the backpack goes up a level." if any
					else "Nothing in the backpack can be upgraded.", any and _run.gold >= _run.upgrade_price()]
		"restock":
			return ["Restock", "%d gold" % _run.restock_price(), "New charms and gear on the shelves. Costs more each time.",
					_run.gold >= _run.restock_price()]
		"sell":
			return ["Sell", "", "Open the backpack: items sell for %d%% of their price." % t.item_sell_percent, true]
	return ["Leave", "", "Back to the map.", true]


# --- drawing ----------------------------------------------------------------------------------

func _rebuild() -> void:
	for card: PanelContainer in _cards + _service_cards:
		card.queue_free()
	_cards.clear()
	_service_cards.clear()
	for i: int in count():
		var info := _info(i)
		var sold := _bought.has(i)
		var price := "SOLD" if sold else "%d gold" % int(info[1])
		var card := _card(info[4], String(info[0]), price, BackpackGrid.rarity_color(int(info[3])), can_buy(i), sold)
		_shelf.add_child(card)
		_cards.append(card)
	for kind: String in SERVICES:
		var info := _service_info(kind)
		var card := _card(null, String(info[0]), String(info[1]), HudStyle.TEXT, bool(info[3]), false, true)
		_services.add_child(card)
		_service_cards.append(card)
	_sel = clampi(_sel, 0, count() + SERVICES.size() - 1)
	_bar.refresh(_run)
	_show_selection()


func _card(icon: Texture2D, title: String, price: String, color: Color, enabled: bool, sold: bool,
		small: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(CARD_SIZE.x * (0.75 if small else 1.0), CARD_SIZE.y * (0.5 if small else 1.0))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)
	if icon != null:
		var art := TextureRect.new()
		art.texture = icon
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = Vector2(16, 16) * ICON_SCALE
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(art)
	var name := HudStyle.make_label(title, CARD_TEXT, color)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(name)
	if not price.is_empty():
		var tag := HudStyle.make_label(price, CARD_TEXT, HudStyle.GOLD if enabled else HudStyle.TEXT_DIM)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(tag)
	card.modulate = SOLD_DIM if sold else (Color.WHITE if enabled else Color(1, 1, 1, 0.6))
	return card


func _box(bg: Color, edge: Color, width: int, pad: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = edge
	box.set_border_width_all(width)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(pad)
	return box


func _show_selection() -> void:
	var all := _cards + _service_cards
	for i: int in all.size():
		var on := i == _sel
		all[i].add_theme_stylebox_override("panel", _box(ListMenu.SELECTED_BG if on else Color(0.05, 0.04, 0.04, 0.7),
				HudStyle.GOLD if on else Color(0.3, 0.24, 0.18), 3 if on else 1, 8))
	if _sel < count():
		var info := _info(_sel)
		_detail.text = "%s (%s)" % [info[2], BackpackGrid.rarity_name(int(info[3]))]
	else:
		_detail.text = String(_service_info(SERVICES[_sel - count()])[2])


# --- input ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _overlay != null:
		return
	if _pick_menu != null:
		_pick_input(event)
		return
	if event.is_action_pressed(&"party_menu", false, true):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_confirm")
		_open_backpack("Sell: pick an item, then Sell.", {})
		return
	if event.is_action_pressed(&"menu_cancel", false, true):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_cancel")
		leave()
		return
	if event.is_action_pressed(&"menu_confirm", false, true):
		get_viewport().set_input_as_handled()
		_use_selected()
		return
	var step := Vector2i.ZERO
	if _pressed(event, &"menu_left"):
		step.x = -1
	elif _pressed(event, &"menu_right"):
		step.x = 1
	elif _pressed(event, &"menu_up"):
		step.y = -1
	elif _pressed(event, &"menu_down"):
		step.y = 1
	if step != Vector2i.ZERO:
		get_viewport().set_input_as_handled()
		_move(step)


## A held key repeats; a stick counts once per push (it sends many motion events).
func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, true, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)


## Moves over the shelf grid; down from the last shelf row (or up from the services) crosses over.
func _move(step: Vector2i) -> void:
	var before := _sel
	if _sel >= count():
		var s := _sel - count()
		if step.x != 0:
			_sel = count() + clampi(s + step.x, 0, SERVICES.size() - 1)
		elif step.y < 0 and count() > 0:
			var col := mini(s, SHELF_COLUMNS - 1)
			@warning_ignore("integer_division")
			var last_row := (count() - 1) / SHELF_COLUMNS
			_sel = mini(last_row * SHELF_COLUMNS + col, count() - 1)
	else:
		if step.x != 0:
			_sel = clampi(_sel + step.x, 0, count() - 1)
		elif step.y < 0:
			_sel = _sel - SHELF_COLUMNS if _sel >= SHELF_COLUMNS else _sel
		else:
			var down := _sel + SHELF_COLUMNS
			_sel = down if down < count() else count() + mini(_sel % SHELF_COLUMNS, SERVICES.size() - 1)
	if _sel != before:
		Sfx.play("menu_move")
		_show_selection()


func _use_selected() -> void:
	if _sel < count():
		buy(_sel)
		return
	var kind := SERVICES[_sel - count()]
	if not bool(_service_info(kind)[3]):
		Sfx.play("locked")
		return
	Sfx.play("menu_confirm")
	match kind:
		"restock":
			restock()
		"sell":
			_open_backpack("Sell: pick an item, then Sell.", {})
		"leave":
			leave()
		"cleanse", "upgrade":
			_open_pick(kind)


## A list of the backpack's items to cleanse or upgrade, over the shop.
func _open_pick(kind: String) -> void:
	_pick_kind = kind
	_pick_uids = _run.rotten_uids() if kind == "cleanse" else []
	if kind == "upgrade":
		for e: Dictionary in _run.backpack.entries:
			if _run.can_upgrade(int(e.uid)):
				_pick_uids.append(int(e.uid))
	_pick_panel = PanelContainer.new()
	_pick_panel.add_theme_stylebox_override("panel", _box(Color(0.04, 0.03, 0.03, 0.95), HudStyle.GOLD, 2, 24))
	_pick_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pick_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pick_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_pick_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_pick_panel.add_child(column)
	column.add_child(ListMenu.centred_title("Which item?" if kind == "upgrade" else "Throw away which?", 40))
	_pick_menu = ListMenu.new()
	column.add_child(_pick_menu)
	var list: Array[Dictionary] = []
	for uid: int in _pick_uids:
		var e := _run.backpack.entry(uid)
		list.append({"text": RunState.entry_name(e), "color": BackpackGrid.rarity_color(RunState.entry_rarity(e))})
	_pick_menu.set_items(list)


func _close_pick() -> void:
	if _pick_panel != null:
		_pick_panel.queue_free()
	_pick_panel = null
	_pick_menu = null
	_pick_uids.clear()


func _pick_input(event: InputEvent) -> void:
	var answer := _pick_menu.handle(event)
	if answer == &"cancel":
		Sfx.play("menu_cancel")
		_close_pick()
	elif answer == &"confirm" and not _pick_uids.is_empty():
		var uid := _pick_uids[_pick_menu.index]
		var name := RunState.entry_name(_run.backpack.entry(uid))
		var ok := _run.cleanse(uid) if _pick_kind == "cleanse" else _run.upgrade_item(uid, _run.upgrade_price())
		if ok:
			Sfx.play("item_drop" if _pick_kind == "cleanse" else "item_combine")
			_say.text = "\"Gone. Good riddance.\"" if _pick_kind == "cleanse" else "\"Your %s, better than new.\"" % name
		else:
			Sfx.play("locked")
		_close_pick()
		_rebuild()


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
		_run.gold += _run.item_price(_pending)
		_say.text = "\"Changed your mind? Here is your gold.\""
		_bought.erase(items().find(_pending))
	_pending = null


func _close_backpack() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_pending = null
	_rebuild()
