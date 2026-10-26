class_name RelicsScreen
extends CanvasLayer
## The Relic book on the main menu (DESIGN.md 8.17, 8.24, card #328), laid out like Expedition 33's
## Pictos page. Left: every Relic as a slanted card in a two-column grid (its icon and name), sorted
## by name or rarity (LT / RT, keys 1 / 3: the switch inside a screen, card #336), with "Found N of
## 50"; a Relic not found yet shows as "???". Right: the
## Relic under the cursor, big: its icon, name, rarity and chips (what it does, its price, its stat
## line), or for one not found yet the places Relics come from. Under the grid: its text.
## StartRelicsScreen (the starting pick before a run) is this page with the heroes on the right.

signal closed

enum Sort { NAME, RARITY }
const SORT_NAMES: Array[String] = ["Name", "Rarity"]
## The footer's sort hint: LT / RT (card #336).
const SORT_HINTS: Array = [[ControlBindings.SWITCH_PREV, ""], [ControlBindings.SWITCH_NEXT, "Sort"]]

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
## The face of the hero who has a Relic, on its card (the starting pick).
const CARD_FACE_PX := Vector2i(40, 40)
## The cursor's card.
const CHOSEN_BG := Color(0.3, 0.24, 0.1, 0.9)
## A card of a Relic that cannot be taken (not found yet, or taken for another hero).
const DIM_CARD_ALPHA: float = 0.5
const UNKNOWN := "???"
const NOT_FOUND := "Not found yet"
## The big Relic on the right.
const FOCUS_ICON_PX: float = 168.0
const FOCUS_NAME_SIZE: int = 44
## Where Relics come from (DESIGN.md 8.24), for a Relic not found yet: icon chips, no sentence.
const SOURCES: Array[Dictionary] = [
	{"glyph": &"sword", "text": "Elite"}, {"glyph": &"skull", "text": "Boss"},
	{"glyph": &"pouch", "text": "Chest"}, {"glyph": &"coin", "text": "Shop"},
]

var _collection: RelicCollection
var _relics: Array[GearData] = []
var _sort: Sort = Sort.NAME
## The grid's Relics in order (the book: the ones not found yet last).
var _listed: Array[GearData] = []
var _cursor: int = 0
var _top_row: int = 0
var _warning: String = ""
var _title: Label
var _grid: GridContainer
var _found: Label
## The sort button and what it sorts by, like Expedition 33's "X Level" chip.
var _sort_box: PanelContainer
var _detail: Label
var _detail_more: Label
## The right side (the big Relic; the starting pick's heroes).
var _side: VBoxContainer
var _hint: HintBar
## The grid cards on screen, and the grid index of each card (for the mouse).
var _card_nodes: Array = []
var _card_ids: Array[int] = []


## `collection`: the Relic book; `relics`: every Relic of the run (RunData.gear).
func setup(collection: RelicCollection, relics: Array[GearData]) -> void:
	_collection = collection if collection != null else RelicCollection.new()
	_relics.assign(relics.filter(func(item: GearData) -> bool: return item != null))
	_build()
	_resort()
	_redraw()


func close() -> void:
	closed.emit()


## The grid's Relics in the order shown (tests).
func listed() -> Array[GearData]:
	return _listed


## The Relic under the cursor (null: none).
func focused() -> GearData:
	return _listed[_cursor] if _cursor >= 0 and _cursor < _listed.size() else null


## Puts the cursor on `item` (tests, pictures). False if it is not in the grid.
func focus(item: GearData) -> bool:
	var i := _listed.find(item)
	if i < 0:
		return false
	_cursor = i
	_redraw()
	return true


## "Found N of M" (the header).
func found_text() -> String:
	return "Found %d of %d" % [_found_count(), _relics.size()]


# --- what the grid holds (StartRelicsScreen changes these) ---------------------------------------

func _owns(item: GearData) -> bool:
	return _collection.owns(item.id)


## The page's title.
func _title_text() -> String:
	return "Relics"


## True if the grid lists the Relics not found yet too ("???", last).
func _lists_unknown() -> bool:
	return true


## True if `item`'s card is dim (it cannot be had here).
func _card_dim(item: GearData) -> bool:
	return not _owns(item)


## The hero slot whose face goes on `item`'s card (-1: none).
func _card_holder(_item: GearData) -> int:
	return -1


## Confirm (or a click) on `item`: the book only shows. True if something was done.
func _confirm(_item: GearData) -> bool:
	return false


## Back: the book closes.
func _back() -> void:
	Sfx.play("menu_cancel")
	close()


## X / R: nothing on the book (the starting Relics: Skip).
func _alt() -> void:
	pass


## The sort `step` on (LT -1, RT +1), wrapping round.
func step_sort(step: int) -> void:
	_sort = wrapi(_sort + step, 0, Sort.size()) as Sort
	_resort()
	Sfx.play("menu_move")
	_redraw()


## The sort shown now.
func sort() -> Sort:
	return _sort


## True if party_menu (Y) works as Back too.
func _closes_on_party_menu() -> bool:
	return true


func _by_id(id: String) -> GearData:
	for item: GearData in _relics:
		if item.id == id:
			return item
	return null


## The grid's order: found Relics by the sort, then (the book) the ones not found yet.
func _resort() -> void:
	var keep := focused()
	var found: Array[GearData] = []
	var unknown: Array[GearData] = []
	for item: GearData in _relics:
		if _owns(item):
			found.append(item)
		else:
			unknown.append(item)
	found.sort_custom(_before)
	_listed = found
	if _lists_unknown():
		_listed.append_array(unknown)
	_cursor = clampi(_listed.find(keep) if keep != null else _cursor, 0, maxi(0, _listed.size() - 1))


func _before(a: GearData, b: GearData) -> bool:
	if _sort == Sort.RARITY and a.rarity != b.rarity:
		return a.rarity > b.rarity
	return a.display_name.naturalnocasecmp_to(b.display_name) < 0


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
		_back()
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
		_confirm(_listed[_cursor])
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
		_confirm(focused())
		return
	elif not event.is_echo() and (_pressed(event, ControlBindings.SWITCH_PREV) or _pressed(event, ControlBindings.SWITCH_NEXT)):
		_handled()
		step_sort(-1 if event.is_action(ControlBindings.SWITCH_PREV) else 1)
		return
	elif _pressed(event, &"item_move"):
		_handled()
		_alt()
		return
	elif _pressed(event, &"menu_cancel") or (_closes_on_party_menu() and _pressed(event, &"party_menu")):
		_handled()
		_back()
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
	_side = VBoxContainer.new()
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.custom_minimum_size.x = RIGHT_WIDTH
	_side.alignment = BoxContainer.ALIGNMENT_CENTER
	_side.add_theme_constant_override("separation", 16)
	row.add_child(_side)
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
	_title = HudStyle.make_worn_title(_title_text(), TITLE_SIZE)
	head.add_child(_title)
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


# --- drawing ----------------------------------------------------------------------------------

func _redraw() -> void:
	if _grid == null:
		return
	for child: Node in _sort_box.get_children():
		_sort_box.remove_child(child)
		child.free()
	# LT, "Sort: Name", RT: the switch's two buttons round what it switches (card #336).
	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("separation", HintBar.CHIP_GAP)
	chips.add_child(HintBar.entry_row(ControlBindings.SWITCH_PREV, "Sort: %s" % SORT_NAMES[_sort], TEXT_SIZE, HudStyle.TEXT))
	chips.add_child(HintBar.entry_row(ControlBindings.SWITCH_NEXT, "", TEXT_SIZE, HudStyle.TEXT))
	_sort_box.add_child(chips)
	_found.text = found_text()
	_redraw_grid()
	_clear(_side)
	_redraw_side()
	_redraw_detail()
	_hint.set_entries(hints())


## The footer's hints now (tests read them).
func hints() -> Array:
	var entries: Array = [[&"@arrows", "Move"]]
	entries.append_array(SORT_HINTS)
	entries.append([&"menu_cancel", "Back"])
	return entries


func _redraw_grid() -> void:
	_clear(_grid)
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
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = CARD_SIZE
	panel.add_theme_stylebox_override("panel", HudStyle.slant(CHOSEN_BG if chosen else HudStyle.INK,
			HudStyle.GOLD if chosen else HudStyle.EDGE_DIM, 3 if chosen else 2, 6, CARD_SIZE.y, HudStyle.SLANT * 0.6))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 12)
	panel.add_child(line)
	var icon := RelicIcon.new()
	icon.setup(item, CARD_ICON_PX, known)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var name := HudStyle.make_title(item.display_name if known else UNKNOWN, NAME_SIZE,
			name_color(item) if known else HudStyle.TEXT_DIM)
	name.custom_minimum_size.x = CARD_NAME_WIDTH
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.add_child(name)
	var holder := _card_holder(item)
	if holder >= 0:
		line.add_child(_face(holder, CARD_FACE_PX))
	if _card_dim(item) and not chosen:
		panel.modulate = Color(1.0, 1.0, 1.0, DIM_CARD_ALPHA)
	return panel


## A Relic's name colour: its rarity's, violet for a rot-touched one.
static func name_color(item: GearData) -> Color:
	if item.rot_touched:
		return GearData.ROT_TOUCHED_COLOR
	return BackpackGrid.rarity_color(BackpackGrid.gear_step(item)).lightened(0.15)


## The book's right side: the Relic under the cursor, big.
func _redraw_side() -> void:
	var item := focused()
	if item == null:
		return
	var known := _owns(item)
	var icon := RelicIcon.make(item, FOCUS_ICON_PX, known)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_side.add_child(icon)
	var name := HudStyle.make_worn_title(item.display_name if known else UNKNOWN, FOCUS_NAME_SIZE,
			name_color(item) if known else HudStyle.TEXT_DIM)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_side.add_child(name)
	_side.add_child(ListMenu.chip_lines(focus_chips(item, known), RIGHT_WIDTH - 40.0))


## The big Relic's chips: found or not; a found one's rarity, what it does, its price and its stat
## line; one not found yet where Relics come from.
static func focus_chips(item: GearData, known: bool) -> Array[Dictionary]:
	var chips: Array[Dictionary] = []
	if not known:
		chips.append({"glyph": &"lock", "text": NOT_FOUND, "color": HudStyle.TEXT_DIM})
		for source: Dictionary in SOURCES:
			var chip := source.duplicate()
			chip["color"] = HudStyle.TEXT
			if chips.size() == 1:
				chip["newline"] = true
			chips.append(chip)
		return chips
	chips.append({"glyph": &"gem", "text": BackpackGrid.rarity_name(BackpackGrid.gear_step(item)).capitalize(),
			"color": name_color(item)})
	var first := true
	for chip: Dictionary in LootScreen.relic_chips(item):
		if first:
			chip["newline"] = true
			first = false
		chips.append(chip)
	return chips


func _redraw_detail() -> void:
	if not _warning.is_empty():
		_detail.text = _warning
		_detail_more.text = ""
		return
	var item := focused()
	if item == null or _found_count() == 0:
		_detail.text = "No Relics yet"
		_detail_more.text = "Elite, Boss, Chest, Shop"
		return
	if not _owns(item):
		_detail.text = "%s  (%s)" % [UNKNOWN, NOT_FOUND.to_lower()]
		_detail_more.text = ""
		return
	var head := PackedStringArray([item.display_name])
	if not item.stat_text().is_empty():
		head.append(item.stat_text())
	_detail.text = "    ".join(head)
	_detail_more.text = item.description


## A hero's small face (the starting pick).
func _face(_slot: int, _px: Vector2i) -> Control:
	return Control.new()


static func _clear(box: Node) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.free()


func _handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, true, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)
