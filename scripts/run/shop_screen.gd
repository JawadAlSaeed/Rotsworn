class_name ShopScreen
extends CanvasLayer
## A shop stop as a place (DESIGN.md 8.10, card #160): the shopkeeper on the left with a line to say,
## the shelves on the right with this stop's stock (a few items and a few Relics;
## user 2026-10-16: the whole list was too crowded), each with its picture, name and price, and
## under them the services: Cleanse (a curse off the party, card #332), Restock (new wares), Sell
## (the backpack opens to sell) and Leave (no Upgrade since card #332: items have no levels). Healing
## is bought as items. Arrows
## move over the shelves and services, Confirm buys or uses, Tab / Y opens the backpack to sell,
## Back leaves. A bought item goes into the backpack where it fits first; with no room the backpack
## opens with it in hand (leaving it gives the gold back). Buying a Relic first asks who gets it
## ("Who gets it?", RelicGift, DESIGN.md 8.24; skipped when only one hero may); the shop sells only
## Relics the party does not have.
## Phase 22: pictures and a word, not sentences: each service has its picture (a skull Cleanse,
## arrows Restock, the coin Sell with its button, a door Leave), prices are the coin and
## a number, and the line under the shelves shows a Relic as its icon, a New chip (a Relic the book
## lacks) and its effect chips (detail(); no stat line since DESIGN.md 8.25). Card #295: an item there is its picture, its name and a few icon chips
## for what it does, the same chips as the fight's Items list (item_chips: "1 AP", "All foes",
## "120% dmg"), never its sentence. The rules are in the Glossary.
## The bot uses count(), can_buy(), buy(), cleanse(), overlay() and leave().
## Online the choices go in turns (card #314, DESIGN.md 9.2), as on the StopScreen screens: on another
## player's turn the shop takes no input (`watching`); on a friend's own turn their copy `asks` the
## host for each purchase and service, and the host hands a purchase with no room to them (hand_off,
## settle_owed). Their Sell backpack asks the host too (`remote`).

signal done
## Host: the shelves changed (a restock): Main tells the clients the new wares.
signal restocked
## Something irreversible happened (a purchase, a restock, a sale or a cleanse): Main
## saves the run now, so Continue does not take it back (card #197).
signal acted
## Online friend: a change made in the backpack open over the shop (Main sends it to the host).
signal op_requested(op: Dictionary)

## The Cleanse pick list of this many curses or fewer shows as cards side by side.
const PICK_CARDS_MAX: int = 3
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
const SERVICES: Array[String] = ["cleanse", "restock", "sell", "leave"]
const SHELF_BG := Color(0.16, 0.11, 0.08, 0.92)
const SHELF_EDGE := Color(0.42, 0.3, 0.18)
const SOLD_DIM := Color(1.0, 1.0, 1.0, 0.35)
## A service card's picture, a price's coin and the Relic detail's icon (phase 22: icons, not words).
const SERVICE_ICON_PX: float = 48.0
const COIN_PX: float = 24.0
const DETAIL_ICON_PX: float = 44.0
const DETAIL_HEIGHT: float = 52.0
## The widest a service's few words under the shelves get before they wrap.
const DETAIL_LINE_MAX: float = 900.0
const MAP_VISUALS_PATH := "res://data/presentation/map_visuals.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"

var _run: RunState
var _gear: Array[GearData] = []
## The items this shop sells: the stop's stock (RunState.shop_stock).
var _items: Array[ItemData] = []
var _bar: RunPartyBar
var _say: Label
## Under the shelves: what the thing picked is (detail()): an item's line, or a Relic's icon, name
## and chips, or a service's word.
var _detail: HBoxContainer
var _look: MapVisuals
var _coin: String = ""
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
## The backpack is open with a purchase in hand (an item with no room yet).
var _holding: bool = false
## Picking a curse for Cleanse: a list over the shelves (the curses' places in RunState.curses, in
## menu order).
var _pick_menu: ListMenu
var _pick_panel: PanelContainer
var _pick_ids: Array[int] = []
var _pick_kind: String = ""
## Online client: its backpack asks the host for every change.
var remote: bool = false
## Online (card #314): another player's turn: no input here.
var watching: bool = false
## Online friend whose turn it is (card #314): each purchase or service goes to the host as a request.
var asks: Callable = Callable()
## Host, a friend's turn (card #314): hand_off.call(self) sends them the purchase owed() (no room).
var hand_off: Callable = Callable()
## Who may get a Relic bought here (RelicGift.allowed; Main sets it): heroes.call(device) -> slots.
var give_heroes: Callable = Callable()
## The shelf whose Relic waits for its hero (the "Who gets it?" pick), and the pad that bought it
## (local co-op: that player's heroes get it).
var _give_index: int = -1
var _device: int = PlayerRoster.ANY
## Host: the purchase handed to a friend to place: {"note", "item"}; {} when none.
var _owed: Dictionary = {}


## `gear`: the Relics this shop sells (RunState.shop_gear for the stop).
func setup(run: RunState, gear: Array[GearData],
		keeper_path: String = "res://assets/sprites/env/shopkeeper.png") -> void:
	_run = run
	_gear = gear
	_items = run.shop_stock(run.at)
	# Things bought before a Continue stay sold (items, then Relics, by shelf index).
	for index: int in run.shop_sold:
		if index < count():
			_bought[index] = true
	_look = load(MAP_VISUALS_PATH) as MapVisuals
	if _look == null:
		_look = MapVisuals.new()
	var visuals := load(VISUALS_PATH) as CombatVisuals
	_coin = visuals.gold_icon_path if visuals != null else ""
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

	_detail = HBoxContainer.new()
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.alignment = BoxContainer.ALIGNMENT_CENTER
	_detail.custom_minimum_size = Vector2(1200.0, DETAIL_HEIGHT)
	_detail.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail.add_theme_constant_override("separation", 14)
	column.add_child(_detail)
	# Sell is a service card (with its button on it), so the footer does not say it again. The
	# cursor moves with the menu directions (_unhandled_input), so the chip shows those.
	ListMenu.screen_footer(self, [[&"@arrows", "Choose"], [&"menu_confirm", "Buy"], [&"menu_cancel", "Leave"]])
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


## Items for sale: the stop's stock.
func items() -> Array[ItemData]:
	return _items


## How many things are on the shelves: items, then gear.
func count() -> int:
	return items().size() + _gear.size()


## The backpack screen open over the shop (null: none). The bot settles it.
func overlay() -> PartyScreen:
	return _overlay


## The name, price, description, rarity and picture of thing `index` (a Relic's picture is the
## Relic itself: its RelicIcon).
func _info(index: int) -> Array:
	if index < items().size():
		var item := items()[index]
		return [item.display_name, _run.item_price(item), item.description, int(item.rarity),
				AssetLoader.texture(item.icon_path, item.size() * 16)]
	var gear := _gear[index - items().size()]
	return [gear.display_name, _run.gear_price(gear), gear.description, BackpackGrid.gear_step(gear), gear]


## What the line under the shelves shows for thing `index` or a service (phase 22: icons and a word
## or two, never a rules sentence): {icon, title, color, chips: [[icon, text, color]], line}. A
## Relic shows its icon, name, a New chip (a Relic the book lacks) and its effect chips;
## an item its picture, name and what it does as chips (item_chips); a service its picture, name
## and a few words.
func detail(index: int) -> Dictionary:
	if index >= count():
		var kind := SERVICES[clampi(index - count(), 0, SERVICES.size() - 1)]
		var service := _service_info(kind)
		return {"icon": service[4], "title": String(service[0]), "color": HudStyle.TEXT, "chips": [],
				"line": String(service[2])}
	var info := _info(index)
	if index < items().size():
		return {"icon": info[4], "title": String(info[0]), "color": BackpackGrid.rarity_color(int(info[3])),
				"chips": item_chips(items()[index], _look, _coin), "line": ""}
	return {"icon": info[4], "title": String(info[0]), "color": BackpackGrid.rarity_color(int(info[3])),
			"chips": relic_chips(_run, info[4] as GearData), "line": ""}


## What an item does, as icon chips for the line under the shelves (card #295: never its sentence):
## [[icon, text, color]]. One mapping for the shop and the fight: a heal, damage, a revive or a
## cleanse gets the fight's Items-list chips (ActionMenu.item_chips: its AP, who it reaches, what it
## does, with the same words, pictures, colours and order), less the AP chip when it cannot be used
## in a fight. Only the kinds a fight never shows get chips of their own here: a curse and treasure.
## At most
## look.item_chips_max chips and look.item_words_max words in all; a chip that would go over is left
## out. `coin`: the gold coin's path (treasure).
static func item_chips(item: ItemData, look: MapVisuals, coin: String) -> Array:
	var chips: Array = []
	if item.is_curse() or item.rotten:
		chips.append([look.item_curse_icon_path, "Curse", HudStyle.HP_LOW])
		if item.rot_percent > 0:
			chips.append([&"heart", "-%d%% a turn" % item.rot_percent, HudStyle.HP_LOW])
		return _cap_chips(chips, look)
	if item.kind == ItemData.Kind.TREASURE:
		chips.append([coin, "To gold", HudStyle.GOLD])
	match item.effect:
		ItemData.Effect.NONE:
			pass
		_:
			var in_fight := item.usable_in_fight()
			for chip: Dictionary in ActionMenu.item_chips(item, item.amount_percent, look.ap_icon_path):
				# The AP chip is the only one drawn with the AP picture passed in.
				if not in_fight and typeof(chip.icon) == TYPE_STRING and String(chip.icon) == look.ap_icon_path:
					continue
				chips.append([chip.icon, String(chip.text), chip.color as Color])
	return _cap_chips(chips, look)


## The first chips that keep within look.item_chips_max chips and look.item_words_max words.
static func _cap_chips(chips: Array, look: MapVisuals) -> Array:
	var kept: Array = []
	var words := 0
	for chip: Array in chips:
		var chip_words := String(chip[1]).split(" ", false).size()
		if kept.size() >= look.item_chips_max or words + chip_words > look.item_words_max:
			continue
		kept.append(chip)
		words += chip_words
	return kept


## A shop Relic's chips: "New" when the Relic book lacks it (LootScreen.new_tag), its effect and any
## drawback.
static func relic_chips(run: RunState, gear: GearData) -> Array:
	var chips: Array = []
	var tag := LootScreen.new_tag(run, gear)
	if not tag.is_empty():
		chips.append([&"star", tag, HudStyle.GOLD])
	var effect := GearData.effect_text(gear.effect, gear.amount)
	if not effect.is_empty():
		chips.append([&"", effect, HudStyle.TEXT])
	if gear.has_drawback():
		chips.append([&"", GearData.drawback_text(gear.drawback, gear.drawback_amount), GearData.ROT_TOUCHED_COLOR])
	return chips


## What is selected (a shelf card or a service), kept when the shop is drawn again online.
func selection() -> int:
	return _sel


func set_selection(index: int) -> void:
	_sel = clampi(index, 0, count() + SERVICES.size() - 1)
	_show_selection()


## True if thing `index` is still for sale and affordable.
func can_buy(index: int) -> bool:
	if index < 0 or index >= count() or _bought.has(index):
		return false
	if index < items().size():
		return _run.can_afford(items()[index])
	return _run.can_buy_gear(_gear[index - items().size()])


## True if shelf `index` holds a Relic.
func is_relic(index: int) -> bool:
	return index >= items().size() and index < count()


## The Relic on shelf `index` (null: an item or nothing).
func relic_at(index: int) -> GearData:
	return _gear[index - items().size()] if is_relic(index) else null


## The heroes who may get a Relic bought here now (RelicGift.allowed).
func relic_heroes() -> Array[int]:
	return RelicGift.allowed(give_heroes, _run, _device)


## True while a Relic on a shelf waits for its hero ("Who gets it?" over the shop).
func is_giving() -> bool:
	return _pick_panel != null and _pick_kind == "give"


## Buys thing `index`; a Relic goes to hero `hero` (one of relic_heroes()). The bot calls this; the
## player uses the shelves.
func buy(index: int, hero: int = -1) -> bool:
	if not can_buy(index):
		Sfx.play("locked")
		_say.text = "\"Not for that purse.\"" if index < count() and not _bought.has(index) else "\"Sold already.\""
		return false
	if is_relic(index) and not relic_heroes().has(hero):
		Sfx.play("locked")
		return false
	if _ask({"do": "buy", "index": index, "hero": hero}):
		return true
	_bought[index] = true
	if index < items().size():
		_run.mark_sold(index)
		var item := items()[index]
		_run.pay_for(item)
		Sfx.play("gold_gain")
		if _run.add_item(item) >= 0:
			Sfx.play("item_place")
			_say.text = "\"The %s. Good choice.\"" % item.display_name
			acted.emit()
		elif hand_off.is_valid():
			# A friend's turn: they put it in their backpack (its gold comes back if they leave it).
			_pending = item
			_owed = {"note": "No room", "item": item}
			hand_off.call(self)
		else:
			_pending = item
			_open_backpack("No room", {"item": item, "refund": true})
	else:
		var gear := _gear[index - items().size()]
		_run.mark_sold(index)
		var found := _run.buy_gear(gear, hero)
		Sfx.play("gold_gain")
		Sfx.play("buff")
		_say.text = "\"%s.\"" % _run.relic_given_text(found, hero)
		_device = PlayerRoster.ANY
		acted.emit()
	_rebuild()
	return true


## Restock service: new items and Relics (Main gives the new wares with set_wares()).
func restock() -> bool:
	if _ask({"do": "restock"}):
		return true
	if not _run.restock():
		Sfx.play("locked")
		return false
	Sfx.play("gold_gain")
	_say.text = "\"Let me see what is in the back.\""
	set_wares(_run.shop_gear(_run.at))
	restocked.emit()
	acted.emit()
	return true


## New wares on the shelves (after a restock; online clients get them from the host).
func set_wares(gear: Array[GearData]) -> void:
	_gear = gear
	_items = _run.shop_stock(_run.at)
	_bought.clear()
	_rebuild()


func leave() -> void:
	if _ask({"do": "leave"}):
		return
	done.emit()


## Cleanse: curse `index` (its place in RunState.curses) comes off the party, paid from the run's
## gold. The bot calls this; the player uses the service. `id` and `seen` (the curse there and how
## many there are, as this machine sees them; filled in when left out) go with a friend's ask, and
## the host refuses it if its list is not the same (RunState.cleanse). False if it cannot be done.
func cleanse(index: int, id: String = "", seen: int = -1) -> bool:
	if id.is_empty():
		id = _run.curses[index] if index >= 0 and index < _run.curses.size() else ""
		seen = _run.curses.size()
	if _ask({"do": "cleanse", "index": index, "id": id, "seen": seen}):
		return true
	var ok := _run.cleanse(index, id, seen)
	if ok:
		Sfx.play("item_drop")
		_say.text = "\"Gone. Good riddance.\""
		acted.emit()
	else:
		Sfx.play("locked")
	_rebuild()
	return ok


## True while a purchase waits on a backpack (open here, or handed to a friend).
func is_settling() -> bool:
	return _overlay != null or not _owed.is_empty()


## Online (card #314): whose turn it is changed; the shelves redraw (an open "Who gets it?" closes).
func set_turn(p_watching: bool, p_asks: Callable = Callable()) -> void:
	watching = p_watching
	asks = p_asks
	if _pick_kind == "give":
		_close_pick()
	_device = PlayerRoster.ANY
	_rebuild()


## True when nothing can be bought here: another player's turn, or a client that only shows.
func is_greyed() -> bool:
	return watching or (remote and not asks.is_valid())


## Host: the purchase a friend was handed to place ({"note", "item"}; {} when none).
func owed() -> Dictionary:
	return _owed


## Host: the friend put the owed purchase where their HAND_OUT op says (BagTab.place_new); left
## behind, its gold comes back. False if that does not fit the backpack now (still owed).
func settle_owed(op: Dictionary) -> bool:
	if _owed.is_empty():
		return false
	var item := _owed.item as ItemData
	var placed := BagTab.place_new(_run, item, op)
	if placed.is_empty():
		return false
	_owed = {}
	if placed == BagTab.LEFT:
		Sfx.play("item_drop")
		_on_left_behind(item)
	else:
		Sfx.play("item_place")
		_say.text = "\"The %s. Good choice.\"" % item.display_name
	_pending = null
	_rebuild()
	acted.emit()
	return true


## Host: the turn came back to this machine while a purchase was owed: its backpack opens with it.
func take_back_owed() -> void:
	if _owed.is_empty() or _overlay != null:
		return
	var owed_now := _owed
	_owed = {}
	_pending = owed_now.item as ItemData
	_open_backpack(String(owed_now.get("note", "")), {"item": owed_now.item, "refund": true})


## Online friend (card #314): the host handed us a purchase to place: the backpack opens with it in
## hand (its changes go to the host). `held`: {"item", "refund"}.
func hold_gift(note: String, held: Dictionary) -> void:
	if _overlay != null:
		return
	_open_backpack(note, held)


## Online friend whose turn it is: sends `choice` to the host and returns true.
func _ask(choice: Dictionary) -> bool:
	if not asks.is_valid():
		return false
	asks.call(choice)
	return true


## A service: [name, price (0: free), a few words, usable now, picture (a texture path or a UiGlyph
## kind)]. The words say what it does, or why it cannot be used now; the rules are in the Glossary.
func _service_info(kind: String) -> Array:
	var t := _run.tuning
	match kind:
		"cleanse":
			var cursed := not _run.curses.is_empty()
			var price := _run.cleanse_price()
			return ["Cleanse", price, _service_words("Lift a curse", "No curse", cursed, price),
					cursed and _run.gold >= price, &"skull"]
		"restock":
			var restock := _run.restock_price()
			return ["Restock", restock, _service_words("New wares", "", true, restock), _run.gold >= restock,
					_look.restock_icon_path]
		"sell":
			return ["Sell", 0, "Pack items for %d%%" % t.item_sell_percent, true, _coin]
	return ["Leave", 0, "Back to the map", true, _look.leave_icon_path]


## A service's few words: what it does, `none` when there is nothing to use it on, or the gold short.
func _service_words(does: String, none: String, has_target: bool, price: int) -> String:
	if not has_target:
		return none
	if _run.gold < price:
		return "Need %d more gold" % (price - _run.gold)
	return does


# --- drawing ----------------------------------------------------------------------------------

func _rebuild() -> void:
	for card: PanelContainer in _cards + _service_cards:
		card.queue_free()
	_cards.clear()
	_service_cards.clear()
	for i: int in count():
		var info := _info(i)
		var sold := _bought.has(i)
		var card := _card(info[4], String(info[0]), int(info[1]), BackpackGrid.rarity_color(int(info[3])), can_buy(i), sold)
		_shelf.add_child(card)
		_cards.append(card)
	for kind: String in SERVICES:
		var info := _service_info(kind)
		var card := _card(info[4], String(info[0]), int(info[1]), HudStyle.TEXT, bool(info[3]), false, true)
		if kind == "sell":
			# Its button (Tab / Y) opens the backpack to sell from anywhere in the shop.
			var chip := HintBar.entry_row(&"party_menu", "", CARD_TEXT - 4)
			chip.alignment = BoxContainer.ALIGNMENT_CENTER
			(card.get_child(0) as VBoxContainer).add_child(chip)
		_services.add_child(card)
		_service_cards.append(card)
	_sel = clampi(_sel, 0, count() + SERVICES.size() - 1)
	_bar.refresh(_run)
	_show_selection()


## A shelf card (or a `small` service card): its picture (MapScreen.icon_picture), name and price as
## the coin and a number (`price` 0: none); SOLD once bought.
func _card(icon: Variant, title: String, price: int, color: Color, enabled: bool, sold: bool,
		small: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(CARD_SIZE.x * (0.75 if small else 1.0), CARD_SIZE.y * (0.5 if small else 1.0))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)
	var art := MapScreen.icon_picture(icon, SERVICE_ICON_PX if small else 16.0 * ICON_SCALE, HudStyle.TEXT,
			small or not icon is Texture2D)
	if art != null:
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(art)
	var name := HudStyle.make_label(title, CARD_TEXT, color)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(name)
	if sold:
		var tag := HudStyle.make_label("SOLD", CARD_TEXT, HudStyle.TEXT_DIM)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(tag)
	elif price > 0:
		var tag := MapScreen.icon_chip(_coin, str(price), HudStyle.GOLD if enabled else HudStyle.TEXT_DIM, COIN_PX,
				CARD_TEXT, false)
		(tag as BoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
		tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
	_show_detail(detail(_sel))


## Fills the line under the shelves from detail().
func _show_detail(data: Dictionary) -> void:
	for child: Node in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	_detail.add_child(MapScreen.icon_chip(data.get("icon"), String(data.get("title", "")),
			data.get("color", HudStyle.TEXT) as Color, DETAIL_ICON_PX, DETAIL_SIZE, false))
	for chip: Variant in data.get("chips", []):
		var parts := chip as Array
		_detail.add_child(MapScreen.icon_chip(parts[0], String(parts[1]), parts[2] as Color))
	var line := String(data.get("line", ""))
	if not line.is_empty():
		var label := HudStyle.make_label(line, DETAIL_SIZE, HudStyle.TEXT_DIM)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if label.get_minimum_size().x > DETAIL_LINE_MAX:
			# A long item line wraps instead of pushing the row off the screen.
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = DETAIL_LINE_MAX
		_detail.add_child(label)


# --- input ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _overlay != null or is_greyed():
		return
	if _pick_menu != null:
		_pick_input(event)
		return
	if event is InputEventMouse and _mouse_input(event):
		return
	if event.is_action_pressed(&"party_menu", false, true):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_confirm")
		_open_backpack("Sell", {"icon": &"coin"})
		return
	if event.is_action_pressed(&"menu_cancel", false, true):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_cancel")
		leave()
		return
	if event.is_action_pressed(&"menu_confirm", false, true):
		get_viewport().set_input_as_handled()
		_use_selected(event)
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


## The mouse (card #202): pointing at a shelf card or a service chooses it, a left click buys or
## uses it, a right click or the back button leaves. True when the event was used.
func _mouse_input(event: InputEvent) -> bool:
	var all: Array = _cards + _service_cards
	if event is InputEventMouseMotion:
		var hovered := MenuMouse.control_at(all, (event as InputEventMouse).position)
		if hovered >= 0 and hovered != _sel:
			_sel = hovered
			Sfx.play("menu_move")
			_show_selection()
			get_viewport().set_input_as_handled()
			return true
	elif MenuMouse.is_click(event):
		var clicked := MenuMouse.control_at(all, (event as InputEventMouse).position)
		if clicked >= 0:
			_sel = clicked
			_show_selection()
			get_viewport().set_input_as_handled()
			_use_selected(event)
			return true
	elif MenuMouse.is_back(event):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_cancel")
		leave()
		return true
	return false


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


func _use_selected(event: InputEvent = null) -> void:
	if _sel < count():
		if not is_relic(_sel) or not can_buy(_sel):
			buy(_sel)
			return
		# Who gets it: straight to the one hero who may, else a hero pick over the shop.
		_device = PlayerRoster.device_of(event) if event != null else PlayerRoster.ANY
		var heroes := relic_heroes()
		if heroes.size() == 1:
			buy(_sel, heroes[0])
		else:
			Sfx.play("menu_confirm")
			_open_give_pick(_sel)
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
			_open_backpack("Sell", {"icon": &"coin"})
		"leave":
			leave()
		"cleanse":
			_open_pick()


## A list of the party's curses to cleanse, over the shop (card #332).
func _open_pick() -> void:
	_pick_kind = "cleanse"
	_pick_ids.clear()
	var cursed := _run.curse_items()
	for i: int in cursed.size():
		_pick_ids.append(i)
	_pick_panel = PanelContainer.new()
	_pick_panel.add_theme_stylebox_override("panel", _box(Color(0.04, 0.03, 0.03, 0.95), HudStyle.GOLD, 2, 24))
	_pick_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pick_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pick_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_pick_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_pick_panel.add_child(column)
	column.add_child(ListMenu.centred_title("Which curse?", 40))
	_pick_menu = ListMenu.new()
	column.add_child(_pick_menu)
	var list: Array[Dictionary] = []
	for curse: ItemData in cursed:
		list.append({"text": curse.display_name, "color": BackpackGrid.ROTTEN_COLOR,
				"icon": AssetLoader.texture(curse.icon_path, Vector2i(16, 16))})
	# Three items or fewer sit side by side as cards (owner, phase 22); Back is the cancel button.
	var cards := list.size() <= PICK_CARDS_MAX
	_pick_menu.horizontal = cards
	_pick_menu.set_items(list)
	column.add_child(HintBar.new([[&"@leftright" if cards else &"@updown", "Choose"],
			[&"menu_confirm", "Cleanse"], [&"menu_cancel", "Back"]], ListMenu.FOOTER_SIZE))


## "Who gets it?" over the shop for the Relic on shelf `index`: a card per hero, the ones who may get
## it lit (RelicGift). Back closes it, buying nothing.
func _open_give_pick(index: int) -> void:
	_give_index = index
	_pick_kind = "give"
	_pick_ids.clear()
	_pick_panel = PanelContainer.new()
	_pick_panel.add_theme_stylebox_override("panel", _box(Color(0.04, 0.03, 0.03, 0.95), HudStyle.GOLD, 2, 24))
	_pick_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pick_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pick_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_pick_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_pick_panel.add_child(column)
	column.add_child(ListMenu.centred_title(RelicGift.ASK, 40))
	_pick_menu = ListMenu.new()
	_pick_menu.horizontal = true
	column.add_child(_pick_menu)
	var list := RelicGift.hero_cards(_run, relic_heroes(), is_greyed())
	_pick_menu.set_items(list)
	_pick_menu.index = RelicGift.first_lit(list)
	column.add_child(HintBar.new([[&"@leftright", "Choose"], [&"menu_confirm", "Give"], [&"menu_cancel", "Back"]],
			ListMenu.FOOTER_SIZE))


func _close_pick() -> void:
	if _pick_panel != null:
		_pick_panel.queue_free()
	_pick_panel = null
	_pick_menu = null
	_pick_ids.clear()
	_give_index = -1


func _pick_input(event: InputEvent) -> void:
	var answer := _pick_menu.handle(event)
	if answer == &"cancel":
		Sfx.play("menu_cancel")
		_device = PlayerRoster.ANY
		_close_pick()
	elif answer == &"confirm" and _pick_kind == "give":
		var index := _give_index
		var slot := int(_pick_menu.items[_pick_menu.index].get("slot", -1)) if _pick_menu.index < _pick_menu.items.size() else -1
		if not relic_heroes().has(slot):
			Sfx.play("locked")
			return
		_close_pick()
		buy(index, slot)
	elif answer == &"confirm" and not _pick_ids.is_empty():
		var index := _pick_ids[_pick_menu.index]
		_close_pick()
		cleanse(index)


func _open_backpack(note: String, held: Dictionary) -> void:
	_overlay = PartyScreen.new()
	_overlay.layer = OVERLAY_LAYER
	_overlay.close_when_settled = held.has("item")
	_overlay.shop_mode = true
	# A friend's copy (card #314): what they do there is asked of the host.
	_overlay.remote = remote
	add_child(_overlay)
	_overlay.setup(_run, note, held)
	_overlay.op_requested.connect(op_requested.emit)
	_overlay.left_behind.connect(_on_left_behind)
	_overlay.done.connect(_close_backpack)
	# A sale is final at once, unless a purchase is still in hand (it is saved when the backpack closes).
	_holding = held.has("item")
	_overlay.sold.connect(func() -> void:
		if not _holding:
			acted.emit())


func _on_left_behind(thing: Resource) -> void:
	if _pending != null and thing == _pending:
		_run.gold += _run.item_price(_pending)
		_say.text = "\"Changed your mind? Here is your gold.\""
		_bought.erase(items().find(_pending))
		_run.unmark_sold(items().find(_pending))
	_pending = null


func _close_backpack() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_pending = null
	_holding = false
	_rebuild()
	# Whatever was bought, worn, sold or given back while the backpack was open is settled now.
	acted.emit()
