class_name RelicsScreen
extends CanvasLayer
## The Relics page on the main menu (DESIGN.md 8.17, 8.24), laid out like Expedition 33's Pictos
## page. Left: every Relic as a slanted card in a two-column grid (its diamond and name), sorted by
## name or rarity (X / R); Relics not found yet show as "???". Right: the Relic bag (card #265): the
## Relics the team brings into the next run; Confirm on a card puts it in or takes it out. Under the
## grid: everything about the Relic under the cursor. (In a run, Relics are given to heroes on the
## party screen's Relics tab, RelicsTab; the run use of this page went with the slots, #326.)

signal closed
## Main menu: the bag changed (Main writes the collection to its file).
signal bag_changed(collection: RelicCollection)

enum Sort { NAME, RARITY }
const SORT_NAMES: Array[String] = ["Name", "Rarity"]

const TITLE_SIZE: int = 56
const NAME_SIZE: int = 24
const SMALL_SIZE: int = 18
const TEXT_SIZE: int = 24
const HERO_SIZE: int = 42
const DETAIL_SIZE: int = 24
const MARGIN_X: float = 70.0
const MARGIN_TOP: float = 30.0
const COLUMN_GAP: int = 50
const LEFT_WIDTH: float = 1010.0
const RIGHT_WIDTH: float = 700.0
const COLUMNS: int = 2
const ROWS: int = 9
const CARD_SIZE := Vector2(490.0, 62.0)
const CARD_ICON_PX: float = 46.0
const CARD_NAME_WIDTH: float = 250.0
## A Relic in the bag: the card's purple, like Expedition 33's equipped Pictos.
const ON_HERO_BG := Color(0.32, 0.12, 0.36, 0.9)
const CHOSEN_BG := Color(0.3, 0.24, 0.1, 0.9)
const UNKNOWN := "???"
const NOT_FOUND := "Not found yet. Elite fights, bosses, chests, shops and events give Relics."
## The bag's cards on the main menu: two columns.
const BAG_COLUMNS: int = 2
const BAG_CARD_SIZE := Vector2(342.0, 62.0)

var _collection: RelicCollection
var _relics: Array[GearData] = []
var _party: Array[CharacterData] = []
var _tuning: Tuning
var _sort: Sort = Sort.NAME
## The grid's Relics in order (main menu: the ones not found yet last).
var _listed: Array[GearData] = []
var _cursor: int = 0
var _top_row: int = 0
var _warning: String = ""
var _grid: GridContainer
var _found: Label
## The sort button and what it sorts by, like Expedition 33's "X Level" chip.
var _sort_box: PanelContainer
var _detail: Label
var _detail_more: Label
var _hero_box: HBoxContainer
var _slots_box: VBoxContainer
var _hint: HintBar
## The grid cards on screen, and the grid index of each card (for the mouse).
var _card_nodes: Array = []
var _card_ids: Array[int] = []


## `collection` and its bag; `relics`: every Relic of the run (RunData.gear); `party`: the heroes.
func setup(collection: RelicCollection, relics: Array[GearData], party: Array[CharacterData], tuning: Tuning) -> void:
	_collection = collection
	_relics.assign(relics.filter(func(item: GearData) -> bool: return item != null))
	_party = party
	_tuning = tuning
	_build()
	_resort()
	_redraw()


func close() -> void:
	closed.emit()


# --- what the grid and the bag hold -------------------------------------------------------------

func _owns(item: GearData) -> bool:
	return _collection.owns(item.id)


## Main menu: how many Relics the bag holds now (card #266).
func _bag_size() -> int:
	return _collection.bag_size(_tuning) if _collection != null else 0


## Main menu: true if the Relic is in the bag.
func _bagged(item: GearData) -> bool:
	return item != null and _collection.in_bag(item.id)


func _by_id(id: String) -> GearData:
	for item: GearData in _relics:
		if item.id == id:
			return item
	return null


## The grid's order: found Relics by the sort, then (main menu) the ones not found yet.
func _resort() -> void:
	var keep := _listed[_cursor] if _cursor >= 0 and _cursor < _listed.size() else null
	var found: Array[GearData] = []
	var unknown: Array[GearData] = []
	for item: GearData in _relics:
		if _owns(item):
			found.append(item)
		else:
			unknown.append(item)
	found.sort_custom(_before)
	_listed = found
	_listed.append_array(unknown)
	_cursor = clampi(_listed.find(keep) if keep != null else _cursor, 0, maxi(0, _listed.size() - 1))


func _before(a: GearData, b: GearData) -> bool:
	if _sort == Sort.RARITY and a.rarity != b.rarity:
		return a.rarity > b.rarity
	return a.display_name.naturalnocasecmp_to(b.display_name) < 0


# --- choosing (the player's buttons call these; tests and the bot can too) -----------------------

## Puts `item` in the bag, or takes it out if it is in. False if it cannot be done (not found yet,
## the bag is full).
func put(item: GearData) -> bool:
	return _toggle_bag(item)


## Main menu: the Relic goes into the bag, or comes out if it is in.
func _toggle_bag(item: GearData) -> bool:
	if item == null or not _owns(item):
		_warning = NOT_FOUND if item != null else ""
		Sfx.play("locked")
		_redraw()
		return false
	var was_in := _collection.in_bag(item.id)
	if not _collection.toggle_bag(item.id, _bag_size()):
		_warning = "The bag is full. Take a Relic out first."
		Sfx.play("locked")
		_redraw()
		return false
	bag_changed.emit(_collection)
	Sfx.play("menu_cancel" if was_in else "buff")
	_redraw()
	return true


func _found_count() -> int:
	var found := 0
	for item: GearData in _relics:
		if _owns(item):
			found += 1
	return found


# --- input ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo():
		_warning = ""
	if _mouse_input(event):
		return
	_grid_input(event)


## The mouse (card #202): pointing at a card picks it, a left click is Confirm on it, a
## right click (or the mouse's back button) is Back, the wheel moves the grid a row. True when used.
func _mouse_input(event: InputEvent) -> bool:
	if MenuMouse.is_back(event):
		_handled()
		Sfx.play("menu_cancel")
		close()
		return true
	var mouse := event as InputEventMouse
	if mouse == null:
		return false
	var wheel := MenuMouse.wheel_step((event as InputEventMouseButton).button_index) \
			if MenuMouse.is_press(event) else 0
	if wheel != 0:
		_handled()
		var to := _cursor + wheel * COLUMNS
		if to >= 0 and to < _listed.size():
			_cursor = to
			_redraw()
		return true
	var card := MenuMouse.control_at(_card_nodes, mouse.position)
	if event is InputEventMouseMotion:
		if card >= 0 and _card_ids[card] != _cursor:
			_cursor = _card_ids[card]
		else:
			return false
		Sfx.play("menu_move")
		_redraw()
		return true
	if MenuMouse.is_click(event) and card >= 0:
		_handled()
		_cursor = _card_ids[card]
		put(_listed[_cursor])
		return true
	return false


func _grid_input(event: InputEvent) -> void:
	var step := 0
	if _pressed(event, &"menu_left"):
		step = -1
	elif _pressed(event, &"menu_right"):
		step = 1
	elif _pressed(event, &"menu_up"):
		step = -COLUMNS
	elif _pressed(event, &"menu_down"):
		step = COLUMNS
	elif _pressed(event, &"menu_confirm"):
		_handled()
		put(_listed[_cursor] if _cursor < _listed.size() else null)
		return
	elif _pressed(event, &"item_move"):
		_handled()
		_sort = ((_sort + 1) % Sort.size()) as Sort
		_resort()
		Sfx.play("menu_move")
		_redraw()
		return
	elif _pressed(event, &"menu_cancel") or _pressed(event, &"party_menu"):
		_handled()
		Sfx.play("menu_cancel")
		close()
		return
	else:
		return
	_handled()
	var to := _cursor + step
	if to >= 0 and to < _listed.size():
		_cursor = to
		Sfx.play("menu_move")
	_redraw()


# --- building -----------------------------------------------------------------------------------

func _build() -> void:
	add_child(MenuBackdrop.new())
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = MARGIN_X
	row.offset_right = -MARGIN_X
	row.offset_top = MARGIN_TOP
	row.offset_bottom = -ListMenu.FOOTER_STRIP_PX
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", COLUMN_GAP)
	add_child(row)
	row.add_child(_build_left())
	row.add_child(_build_right())
	_hint = ListMenu.screen_footer(self, [])


func _build_left() -> Control:
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.custom_minimum_size.x = LEFT_WIDTH
	left.add_theme_constant_override("separation", 12)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 28)
	left.add_child(head)
	var title := HudStyle.make_worn_title("Relics", TITLE_SIZE)
	head.add_child(title)
	_sort_box = PanelContainer.new()
	_sort_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sort_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sort_box.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.EDGE_DIM, 2, 6, 40.0, HudStyle.SLANT, false))
	head.add_child(_sort_box)
	_found = HudStyle.make_label("", TEXT_SIZE, HudStyle.TEXT_DIM)
	_found.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_found)
	left.add_child(ListMenu.divider(LEFT_WIDTH))
	_grid = GridContainer.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.custom_minimum_size.y = ROWS * (CARD_SIZE.y + 8.0)
	left.add_child(_grid)
	var detail_box := PanelContainer.new()
	detail_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_box.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.EDGE_DIM, 2, 12, 90.0, 0.08, false))
	left.add_child(detail_box)
	var detail_col := VBoxContainer.new()
	detail_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_box.add_child(detail_col)
	_detail = HudStyle.make_label("", DETAIL_SIZE, HudStyle.GOLD)
	detail_col.add_child(_detail)
	_detail_more = HudStyle.make_label("", SMALL_SIZE + 4, HudStyle.TEXT)
	_detail_more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_more.custom_minimum_size = Vector2(LEFT_WIDTH - 40.0, SMALL_SIZE * 3)
	detail_col.add_child(_detail_more)
	return left


func _build_right() -> Control:
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.custom_minimum_size.x = RIGHT_WIDTH
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 16)
	_hero_box = HBoxContainer.new()
	_hero_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_hero_box)
	_slots_box = VBoxContainer.new()
	_slots_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots_box.add_theme_constant_override("separation", 14)
	right.add_child(_slots_box)
	return right


# --- drawing ----------------------------------------------------------------------------------

func _redraw() -> void:
	if _grid == null:
		return
	for child: Node in _sort_box.get_children():
		_sort_box.remove_child(child)
		child.free()
	_sort_box.add_child(HintBar.entry_row(&"item_move", "Sort: %s" % SORT_NAMES[_sort], TEXT_SIZE, HudStyle.TEXT))
	_found.text = "Found %d of %d" % [_found_count(), _relics.size()]
	_redraw_grid()
	_redraw_bag()
	_redraw_detail()
	_redraw_hint()


func _redraw_grid() -> void:
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.free()
	var row := floori(float(_cursor) / float(COLUMNS))
	if row < _top_row:
		_top_row = row
	elif row >= _top_row + ROWS:
		_top_row = row - ROWS + 1
	_top_row = clampi(_top_row, 0, maxi(0, ceili(float(_listed.size()) / float(COLUMNS)) - ROWS))
	_card_nodes.clear()
	_card_ids.clear()
	for i: int in range(_top_row * COLUMNS, mini(_listed.size(), (_top_row + ROWS) * COLUMNS)):
		var card := _grid_card(_listed[i], i == _cursor)
		_grid.add_child(card)
		_card_nodes.append(card)
		_card_ids.append(i)


func _grid_card(item: GearData, chosen: bool) -> Control:
	var known := _owns(item)
	var bg := CHOSEN_BG if chosen else (ON_HERO_BG if _bagged(item) else HudStyle.INK)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = CARD_SIZE
	panel.add_theme_stylebox_override("panel", HudStyle.slant(bg, HudStyle.GOLD if chosen else HudStyle.EDGE_DIM,
			3 if chosen else 2, 6, CARD_SIZE.y, HudStyle.SLANT * 0.6))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 12)
	panel.add_child(line)
	var icon := RelicIcon.new()
	icon.setup(item, CARD_ICON_PX, known)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var name := HudStyle.make_title(item.display_name if known else UNKNOWN, NAME_SIZE,
			_name_color(item) if known else HudStyle.TEXT_DIM)
	name.custom_minimum_size.x = CARD_NAME_WIDTH
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.add_child(name)
	return panel


func _name_color(item: GearData) -> Color:
	if item.rot_touched:
		return GearData.ROT_TOUCHED_COLOR
	return BackpackGrid.rarity_color(BackpackGrid.gear_step(item)).lightened(0.15)


## The Relic bag (card #265): its count and its Relics as small cards, two columns, the free room
## as dim empty cards.
func _redraw_bag() -> void:
	for child: Node in _hero_box.get_children():
		_hero_box.remove_child(child)
		child.free()
	for child: Node in _slots_box.get_children():
		_slots_box.remove_child(child)
		child.free()
	var names := VBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_box.add_child(names)
	var ids := _collection.bag_ids()
	names.add_child(HudStyle.make_worn_title("Relic bag", HERO_SIZE, HudStyle.GOLD))
	names.add_child(HudStyle.make_number("%d / %d" % [ids.size(), _bag_size()], TEXT_SIZE, HudStyle.TEXT))
	var grid := GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = BAG_COLUMNS
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	_slots_box.add_child(grid)
	for i: int in _bag_size():
		grid.add_child(_bag_card(_by_id(ids[i]) if i < ids.size() else null))


func _bag_card(item: GearData) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = BAG_CARD_SIZE
	panel.add_theme_stylebox_override("panel", HudStyle.slant(ON_HERO_BG if item != null else HudStyle.INK,
			HudStyle.EDGE_DIM, 2, 6, BAG_CARD_SIZE.y, HudStyle.SLANT * 0.6))
	panel.modulate = Color(1.0, 1.0, 1.0, 1.0 if item != null else 0.45)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 10)
	panel.add_child(line)
	var icon := RelicIcon.new()
	if item != null:
		icon.setup(item, CARD_ICON_PX, true)
	else:
		icon.setup_slot(RelicIcon.SlotState.EMPTY, CARD_ICON_PX)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var name := HudStyle.make_title(item.display_name if item != null else "", NAME_SIZE - 2,
			_name_color(item) if item != null else HudStyle.TEXT_DIM)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	line.add_child(name)
	return panel


func _redraw_detail() -> void:
	if not _warning.is_empty():
		_detail.text = _warning
		_detail_more.text = ""
		return
	var item: GearData = _listed[_cursor] if _cursor < _listed.size() else null
	if item == null or _found_count() == 0:
		_detail.text = "No Relics yet"
		_detail_more.text = "Elite fights, bosses, chests, shops and events give Relics. You keep them forever."
		return
	if not _owns(item):
		_detail.text = "%s  (not found yet)" % UNKNOWN
		_detail_more.text = NOT_FOUND
		return
	var head := PackedStringArray([item.display_name])
	if not item.stat_text().is_empty():
		head.append(item.stat_text())
	if _bagged(item):
		head.append("In the bag")
	_detail.text = "    ".join(head)
	_detail_more.text = item.description


func _redraw_hint() -> void:
	_hint.set_entries([[&"@arrows", "Move"], [&"menu_confirm", "In / out of bag"], [&"item_move", "Sort"],
			[&"menu_cancel", "Back"]])


func _handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, true, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)
