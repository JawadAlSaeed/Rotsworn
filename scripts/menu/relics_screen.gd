class_name RelicsScreen
extends CanvasLayer
## The Relics page (DESIGN.md 8.17), laid out like Expedition 33's Pictos page. Left: every Relic as
## a slanted card in a two-column grid (its diamond, name, level, and the face of the hero who has
## it), sorted by level, name or rarity (X / R). Right: the hero shown (LB / RB changes hero) and
## their three Relic slots as big cards (diamond, name, stat line, level, what it does). Under the
## grid: everything about the Relic under the cursor.
## Up / down picks a slot; Confirm opens the grid to choose a Relic for it (a Relic another hero has
## moves over), X / R takes it off. In the grid Confirm puts the Relic on, Back goes back to the
## slots.
## Two uses: the main menu (setup), where the slots are the Relics each hero brings into the next
## run (RelicCollection picks; Relics not found yet show as "???" with the monsters that drop them),
## and a run (setup_run, from the party screen's Relic slots), where the slots are the ones the hero
## wears now (locked ones say what opens them) and each card shows its Echo's progress. In a run an
## online client's changes go to the host as RunState ops (op_requested).

signal closed
## Main menu: the picks changed (Main writes the collection to its file).
signal picks_changed(collection: RelicCollection)
## Online client in a run: a change for the host to make (RunState.apply_op data).
signal op_requested(op: Dictionary)

enum Zone { SLOTS, GRID }
enum Sort { LEVEL, NAME, RARITY }
const SORT_NAMES: Array[String] = ["Level", "Name", "Rarity"]

const TITLE_SIZE: int = 56
const NAME_SIZE: int = 24
const LEVEL_SIZE: int = 34
const SMALL_SIZE: int = 18
const TEXT_SIZE: int = 24
const HERO_SIZE: int = 42
const SLOT_NAME_SIZE: int = 30
const SLOT_LEVEL_SIZE: int = 44
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
const FACE_PX: float = 30.0
const SLOT_HEIGHT: float = 150.0
const SLOT_ICON_PX: float = 104.0
const HERO_FACE_PX: float = 72.0
## A Relic the shown hero has: the card's purple, like Expedition 33's equipped Pictos.
const ON_HERO_BG := Color(0.32, 0.12, 0.36, 0.9)
const CHOSEN_BG := Color(0.3, 0.24, 0.1, 0.9)
const UNKNOWN := "???"
## When each slot's Relic goes on in a run (main menu notes).
const SLOT_WHEN: Array[String] = ["Goes on at the start of a run.", "Goes on after the first guard.",
		"Goes on after act 1's boss."]

## Online client (run use): changes are asked of the host instead of made here.
var remote: bool = false
var _collection: RelicCollection
var _run: RunState
var _relics: Array[GearData] = []
var _party: Array[CharacterData] = []
var _tuning: Tuning
## Relic id -> names of the monsters that drop it.
var _droppers: Dictionary = {}
var _hero: int = 0
var _slot: int = 0
var _zone: Zone = Zone.SLOTS
var _sort: Sort = Sort.LEVEL
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
## The grid cards and slot cards on screen, and the grid index of each card (for the mouse).
var _card_nodes: Array = []
var _card_ids: Array[int] = []
var _slot_nodes: Array = []


## Main menu use: `collection` and its picks; `relics`: every Relic of the run (RunData.gear);
## `party`: the heroes; `enemies`: every monster (where a Relic not found yet drops).
func setup(collection: RelicCollection, relics: Array[GearData], party: Array[CharacterData], tuning: Tuning,
		enemies: Array[EnemyData]) -> void:
	_collection = collection
	_relics.assign(relics.filter(func(item: GearData) -> bool: return item != null))
	_party = party
	_tuning = tuning
	for enemy: EnemyData in enemies:
		for item: GearData in enemy.relic_drops:
			if item != null:
				var names: Array = _droppers.get(item.id, [])
				if not names.has(enemy.display_name):
					names.append(enemy.display_name)
				_droppers[item.id] = names
	_build()
	_resort()
	_redraw()


## Run use (the party screen): hero `hero`'s Relic slots; `gear_slot` >= 0 opens the grid at once
## to choose a Relic for that slot.
func setup_run(run: RunState, hero: int, gear_slot: int = -1) -> void:
	_run = run
	_relics.assign(run.data.gear.filter(func(item: GearData) -> bool: return item != null))
	_party = run.data.party
	_tuning = run.tuning
	_hero = clampi(hero, 0, run.party_size() - 1)
	_slot = clampi(gear_slot, 0, _slot_count() - 1)
	_build()
	_resort()
	if gear_slot >= 0:
		open_grid()
	_redraw()


## The run changed (online, another player's change arrived): redraw.
func refresh() -> void:
	_resort()
	_redraw()


func close() -> void:
	closed.emit()


# --- what the slots and the grid hold (main menu or run) ----------------------------------------

func _slot_count() -> int:
	return _tuning.run_gear_slots


## The Relic in hero `hero`'s slot `slot` (null: empty).
func slot_item(hero: int, slot: int) -> GearData:
	if _run != null:
		return _run.gear[hero][slot] as GearData if slot < (_run.gear[hero] as Array).size() else null
	var ids := _collection.picks_for(_party[hero].id)
	return _by_id(ids[slot]) if slot < ids.size() else null


func _slot_open(slot: int) -> bool:
	return _run == null or _run.slot_open(slot)


func _owns(item: GearData) -> bool:
	return _run.owns(item) if _run != null else _collection.owns(item.id)


func _level(item: GearData) -> int:
	return _run.relic_level(item) if _run != null else _collection.level_of(item.id)


## The hero who has the Relic (wears it in a run, brings it from the menu), or -1.
func _holder(item: GearData) -> int:
	if _run != null:
		return _run.wearer_of(item)
	var hero_id := _collection.picked_by(item.id)
	for i: int in _party.size():
		if _party[i].id == hero_id:
			return i
	return -1


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
		elif _run == null:
			unknown.append(item)
	found.sort_custom(_before)
	_listed = found
	_listed.append_array(unknown)
	_cursor = clampi(_listed.find(keep) if keep != null else _cursor, 0, maxi(0, _listed.size() - 1))


func _before(a: GearData, b: GearData) -> bool:
	match _sort:
		Sort.LEVEL:
			if _level(a) != _level(b):
				return _level(a) > _level(b)
		Sort.RARITY:
			if a.rarity != b.rarity:
				return a.rarity > b.rarity
	return a.display_name.naturalnocasecmp_to(b.display_name) < 0


# --- choosing (the player's buttons call these; tests and the bot can too) -----------------------

## Picks the slot the next Relic goes into.
func choose_slot(slot: int) -> void:
	_slot = clampi(slot, 0, _slot_count() - 1)
	_zone = Zone.SLOTS
	_redraw()


## Opens the grid for the chosen slot (false, with a reason shown, if the slot is shut or there is
## nothing to choose).
func open_grid() -> bool:
	if not _slot_open(_slot):
		_warning = "That slot is locked. " + _run.slot_lock_text(_slot)
		Sfx.play("locked")
		_redraw()
		return false
	if _found_count() == 0:
		_warning = "No Relics yet. Monsters, guards, shops and chests give them."
		Sfx.play("locked")
		_redraw()
		return false
	_zone = Zone.GRID
	var on := slot_item(_hero, _slot)
	_cursor = maxi(0, _listed.find(on)) if on != null else 0
	Sfx.play("menu_confirm")
	_redraw()
	return true


## Puts `item` in the shown hero's chosen slot (moving it from another hero or slot). False if it
## cannot be done (not found yet, the slot is locked).
func put(item: GearData) -> bool:
	if item == null or not _owns(item) or not _slot_open(_slot):
		_warning = "Not found yet: defeat the monsters that drop it." if item != null and not _owns(item) else ""
		Sfx.play("locked")
		_redraw()
		return false
	if slot_item(_hero, _slot) == item:
		_zone = Zone.SLOTS
		_redraw()
		return true
	if _run != null:
		# Worn elsewhere: the two slots swap. Else it goes on, and what was here goes back to the
		# run's Relics (RunState.wear).
		var holder := _run.wearer_of(item)
		if holder >= 0:
			_ask({"op": "swap_gear", "from": [holder, _run.wear_slot_of(item)], "to": [_hero, _slot]})
		else:
			_ask({"op": "wear", "slot": _hero, "gear_slot": _slot, "relic": item.id})
	else:
		# The picks are a list in slot order: the Relic takes this slot's place (one of the hero's
		# own picks swaps places; one another hero brings moves over: set_picks).
		var ids := _collection.picks_for(_party[_hero].id)
		var at := ids.find(item.id)
		if at >= 0 and _slot < ids.size():
			ids[at] = ids[_slot]
			ids[_slot] = item.id
		elif at >= 0:
			ids.remove_at(at)
			ids.append(item.id)
		elif _slot < ids.size():
			ids[_slot] = item.id
		else:
			ids.append(item.id)
		_collection.set_picks(_party[_hero].id, ids, _slot_count())
		picks_changed.emit(_collection)
	Sfx.play("buff")
	_zone = Zone.SLOTS
	_resort()
	_redraw()
	return true


## Takes the Relic off the chosen slot (it stays found).
func take_off() -> bool:
	var item := slot_item(_hero, _slot)
	if item == null:
		Sfx.play("locked")
		return false
	if _run != null:
		_ask({"op": "take_off", "slot": _hero, "gear_slot": _slot})
	else:
		var ids := _collection.picks_for(_party[_hero].id)
		ids.erase(item.id)
		_collection.set_picks(_party[_hero].id, ids, _slot_count())
		picks_changed.emit(_collection)
	Sfx.play("menu_cancel")
	_redraw()
	return true


func _ask(op: Dictionary) -> void:
	if remote:
		op_requested.emit(op)
	else:
		_run.apply_op(op)


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
	if _pressed(event, &"item_turn_left") or _pressed(event, &"item_turn_right"):
		_handled()
		_hero = wrapi(_hero + (-1 if event.is_action(&"item_turn_left") else 1), 0, maxi(1, _party.size()))
		Sfx.play("menu_move")
		_redraw()
		return
	if _zone == Zone.SLOTS:
		_slots_input(event)
	else:
		_grid_input(event)


## The mouse (card #202): pointing at a card or a slot picks it, a left click is Confirm on it, a
## right click (or the mouse's back button) is Back, the wheel moves the grid a row. True when used.
func _mouse_input(event: InputEvent) -> bool:
	if MenuMouse.is_back(event):
		_handled()
		Sfx.play("menu_cancel")
		if _zone == Zone.GRID:
			_zone = Zone.SLOTS
			_redraw()
		else:
			close()
		return true
	var mouse := event as InputEventMouse
	if mouse == null:
		return false
	var wheel := MenuMouse.wheel_step((event as InputEventMouseButton).button_index) \
			if MenuMouse.is_press(event) else 0
	if wheel != 0 and _zone == Zone.GRID:
		_handled()
		var to := _cursor + wheel * COLUMNS
		if to >= 0 and to < _listed.size():
			_cursor = to
			_redraw()
		return true
	var card := MenuMouse.control_at(_card_nodes, mouse.position)
	var slot := MenuMouse.control_at(_slot_nodes, mouse.position)
	if event is InputEventMouseMotion:
		if card >= 0 and _zone == Zone.GRID and _card_ids[card] != _cursor:
			_cursor = _card_ids[card]
		elif slot >= 0 and _zone == Zone.SLOTS and slot != _slot:
			_slot = slot
		else:
			return false
		Sfx.play("menu_move")
		_redraw()
		return true
	if MenuMouse.is_click(event):
		if card >= 0 and _zone == Zone.GRID:
			_handled()
			_cursor = _card_ids[card]
			put(_listed[_cursor])
			return true
		if slot >= 0:
			_handled()
			_slot = slot
			_zone = Zone.SLOTS
			open_grid()
			return true
	return false


func _slots_input(event: InputEvent) -> void:
	if _pressed(event, &"menu_up") or _pressed(event, &"menu_down"):
		_slot = wrapi(_slot + (-1 if event.is_action(&"menu_up") else 1), 0, _slot_count())
		Sfx.play("menu_move")
	elif _pressed(event, &"menu_confirm"):
		_handled()
		open_grid()
		return
	elif _pressed(event, &"item_move"):
		_handled()
		take_off()
		return
	elif _pressed(event, &"menu_cancel") or _pressed(event, &"party_menu"):
		_handled()
		Sfx.play("menu_cancel")
		close()
		return
	else:
		return
	_handled()
	_redraw()


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
		_zone = Zone.SLOTS
		_redraw()
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
	_hero_box.add_theme_constant_override("separation", 18)
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
	_redraw_hero()
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
		var card := _grid_card(_listed[i], i == _cursor and _zone == Zone.GRID)
		_grid.add_child(card)
		_card_nodes.append(card)
		_card_ids.append(i)


func _grid_card(item: GearData, chosen: bool) -> Control:
	var known := _owns(item)
	var holder := _holder(item) if known else -1
	var bg := CHOSEN_BG if chosen else (ON_HERO_BG if holder == _hero and holder >= 0 else HudStyle.INK)
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
	var fill := Control.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(fill)
	if known:
		line.add_child(_level_box(_level(item), SMALL_SIZE, LEVEL_SIZE))
	if holder >= 0:
		var c := _party[holder]
		line.add_child(HudStyle.portrait_frame(AssetLoader.texture(c.portrait_path, Vector2i(48, 48)), c.color, FACE_PX, 1))
	else:
		# Room for a face, so every card's level sits in the same place.
		var room := Control.new()
		room.mouse_filter = Control.MOUSE_FILTER_IGNORE
		room.custom_minimum_size = Vector2(FACE_PX + 6.0, FACE_PX)
		line.add_child(room)
	return panel


func _name_color(item: GearData) -> Color:
	if item.rot_touched:
		return GearData.ROT_TOUCHED_COLOR
	return BackpackGrid.rarity_color(BackpackGrid.gear_step(item)).lightened(0.15)


## "Lv" over the level, right-aligned.
func _level_box(level: int, small: int, big: int) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", -6)
	var lv := HudStyle.make_label("Lv", small, HudStyle.TEXT_DIM)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(lv)
	var number := HudStyle.make_number(str(level), big, HudStyle.TEXT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(number)
	return box


func _redraw_hero() -> void:
	for child: Node in _hero_box.get_children():
		_hero_box.remove_child(child)
		child.free()
	for child: Node in _slots_box.get_children():
		_slots_box.remove_child(child)
		child.free()
	_slot_nodes.clear()
	if _party.is_empty():
		return
	var c := _party[_hero]
	_hero_box.add_child(HudStyle.portrait_frame(AssetLoader.texture(c.portrait_path, Vector2i(48, 48)), c.color, HERO_FACE_PX))
	var names := VBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	_hero_box.add_child(names)
	names.add_child(HudStyle.make_title(c.display_name, HERO_SIZE, c.color.lightened(0.25)))
	names.add_child(HudStyle.make_label("Wears now" if _run != null else "Brings into the next run", SMALL_SIZE + 2,
			HudStyle.TEXT_DIM))
	if _party.size() > 1:
		var swap := HintBar.new([[&"item_turn_left", ""], [&"item_turn_right", "Hero"]], SMALL_SIZE)
		swap.alignment = BoxContainer.ALIGNMENT_BEGIN
		swap.add_theme_constant_override("separation", 8)
		names.add_child(swap)
	_slot_nodes.clear()
	for slot: int in _slot_count():
		var card := _slot_card(slot)
		_slots_box.add_child(card)
		_slot_nodes.append(card)


## A big card for slot `slot`: the diamond, name, stat line, level and what it does.
func _slot_card(slot: int) -> Control:
	var item := slot_item(_hero, slot)
	var open := _slot_open(slot)
	var chosen := slot == _slot
	var border := HudStyle.GOLD if chosen and _zone == Zone.SLOTS else (HudStyle.EDGE if chosen else HudStyle.EDGE_DIM)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(RIGHT_WIDTH, SLOT_HEIGHT)
	panel.add_theme_stylebox_override("panel", HudStyle.slant(CHOSEN_BG if chosen else HudStyle.INK, border,
			3 if chosen else 2, 12, SLOT_HEIGHT, HudStyle.SLANT * 0.35))
	panel.modulate = Color(1.0, 1.0, 1.0, 1.0 if open else 0.55)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 18)
	panel.add_child(line)
	var icon := RelicIcon.new()
	icon.setup(item, SLOT_ICON_PX, item != null)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	line.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var title := "Slot %d" % (slot + 1)
	if item != null:
		title = item.display_name
	elif not open:
		title = "Locked"
	var name := HudStyle.make_worn_title(title, SLOT_NAME_SIZE, _name_color(item) if item != null else HudStyle.TEXT_DIM)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	if item != null:
		top.add_child(_level_box(_level(item), SMALL_SIZE, SLOT_LEVEL_SIZE))
	var stat := HudStyle.make_label(_slot_stats(item), TEXT_SIZE - 2, HudStyle.TEXT)
	col.add_child(stat)
	var text := HudStyle.make_label(_slot_text(item, slot), SMALL_SIZE + 2, HudStyle.TEXT_DIM)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = RIGHT_WIDTH - SLOT_ICON_PX - 80.0
	col.add_child(text)
	return panel


## The stat line, Echo cost and (in a run) the Echo's progress of a slot's Relic.
func _slot_stats(item: GearData) -> String:
	if item == null:
		return ""
	var parts := PackedStringArray()
	var stat := item.stat_text(_level(item))
	if not stat.is_empty():
		parts.append(stat)
	if _run != null:
		parts.append("Echo learned" if _run.echo_learned(item) else "Echo %d / %d" % [_run.mastery_of(item),
				_tuning.mastery_needed])
	else:
		parts.append("Echo %d pt%s" % [item.echo_cost, "" if item.echo_cost == 1 else "s"])
	return "      ".join(parts)


func _slot_text(item: GearData, slot: int) -> String:
	if item != null:
		return item.description
	if not _slot_open(slot):
		return _run.slot_lock_text(slot)
	if _run == null:
		return "Empty. " + SLOT_WHEN[mini(slot, SLOT_WHEN.size() - 1)]
	return "Empty. Confirm to choose a Relic."


func _redraw_detail() -> void:
	if not _warning.is_empty():
		_detail.text = _warning
		_detail_more.text = ""
		return
	var item: GearData = null
	if _zone == Zone.GRID:
		item = _listed[_cursor] if _cursor < _listed.size() else null
	else:
		item = slot_item(_hero, _slot)
	if item == null:
		if _found_count() == 0:
			_detail.text = "No Relics yet"
			_detail_more.text = "Monsters, guards, shops and chests give Relics. You keep them forever."
		else:
			_detail.text = "Slot %d" % (_slot + 1)
			_detail_more.text = _slot_text(null, _slot)
		return
	if not _owns(item):
		_detail.text = "%s  (not found yet)" % UNKNOWN
		_detail_more.text = "Dropped by: %s." % ", ".join(PackedStringArray(_droppers.get(item.id, ["no one yet"])))
		return
	var head := PackedStringArray([item.display_name, "Lv %d" % _level(item)])
	if not item.stat_text(_level(item)).is_empty():
		head.append(item.stat_text(_level(item)))
	head.append("Echo %d pt%s" % [item.echo_cost, "" if item.echo_cost == 1 else "s"])
	var holder := _holder(item)
	if holder >= 0:
		head.append(("%s wears it" if _run != null else "%s brings it") % _party[holder].display_name)
	_detail.text = "    ".join(head)
	var more := item.description
	if _run != null:
		more += "\n" + ("Its Echo is learned this run: any hero can wear it." if _run.echo_learned(item)
				else "Wear it for %d more won fights to learn its Echo this run." % _run.fights_to_learn(item))
	elif _level(item) < _tuning.relic_max_level:
		more += "\nA copy raises it to level %d." % (_level(item) + 1)
	_detail_more.text = more


func _redraw_hint() -> void:
	if _zone == Zone.GRID:
		_hint.set_entries([[&"@arrows", "Move"], [&"menu_confirm", "Put on"], [&"item_move", "Sort"],
				[&"menu_cancel", "Back"]])
		return
	var entries: Array = [[&"@updown", "Slot"], [&"menu_confirm", "Choose Relic"], [&"item_move", "Take off"]]
	if _party.size() > 1:
		entries.append([&"item_turn_left", ""])
		entries.append([&"item_turn_right", "Hero"])
	entries.append([&"menu_cancel", "Back"])
	_hint.set_entries(entries)


func _handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, true, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)
