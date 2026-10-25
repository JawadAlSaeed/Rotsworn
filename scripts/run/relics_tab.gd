class_name RelicsTab
extends PartyTab
## The Y screen's Relics tab (DESIGN.md 8.18, 8.24): every hero as a row (face, name, level, HP,
## power, speed and the Relics given to them) on the left, and the run's Relics as a grid of Relic
## icons on the right, each with the initial of the hero who has it. A Relic is given to one hero for
## the rest of the run (no slots, no limit); any still waiting for a hero (none since the Relic bag
## went, card #328; an old save may hold some) are bright and untagged in the grid.
## Rows: up / down picks a hero, left / right their Relics; right past the last goes into the grid.
## Confirm on a hero opens the grid to give them a waiting Relic; Confirm on a waiting Relic there
## gives it to that hero. In the grid X / R changes which kind of Relic shows (all, offensive,
## defensive, support). Back steps back from the grid to the rows.

enum Zone { HEROES, GRID }
## The grid's filter: everything, or one category (GearData.Category + 1).
enum Filter { ALL, OFFENSIVE, DEFENSIVE, SUPPORT }
const FILTER_GLYPHS: Array[StringName] = [&"gem", &"sword", &"shield", &"leaf"]

const ROW_LEFT: float = 60.0
const ROW_WIDTH: float = 1000.0
const ROW_HEIGHT: float = 228.0
const ROW_GAP: float = 14.0
const FACE_PX: float = 112.0
const NAME_SIZE: int = 36
const TEXT_SIZE: int = 24
const SMALL_SIZE: int = 20
## A hero's Relics: the biggest icon and its step, where they start and how wide they may spread.
const SLOT_PX: float = 118.0
const SLOT_LEFT: float = 548.0
const SLOT_STEP: float = 150.0
const SLOT_AREA: Vector2 = Vector2(428.0, 188.0)
const SLOT_GAP: float = 12.0
## Up to this many Relics sit in one row with their names under them; more go in two rows, smaller.
const NAMED_MAX: int = 3
const SLOT_NAME_WIDTH: float = 140.0
const HP_BAR_WIDTH: float = 230.0
const BAG_LEFT: float = 1110.0
const BAG_WIDTH: float = 760.0
const BAG_COLUMNS: int = 6
const BAG_ROWS: int = 4
const BAG_CELL: float = 116.0
const BAG_ICON_PX: float = 92.0
const BAG_ROW_GAP: float = 14.0
const CHIP_SIZE: int = 22
## A hero row with no Relics while nothing waits to be given.
const NO_RELICS := "No Relics"

var _zone: Zone = Zone.HEROES
## The Relic under the cursor in the hero's row (its index in run.relics_of(hero)).
var _slot: int = 0
## The hero a Relic picked in the grid goes to.
var _target: int = 0
var _filter: Filter = Filter.ALL
## The grid's Relics in the order shown (the filter applied).
var _listed: Array[GearData] = []
var _cursor: int = 0
var _top_row: int = 0
## The last refusal (shown on the strip until the next press).
var _warning: String = ""
var _rows_box: Control
var _bag_box: Control
## Hit areas for the mouse: [Rect2, zone, a, b] (heroes: hero, Relic index; grid: index).
var _hits: Array = []


func setup(p_run: RunState, p_remote: bool) -> void:
	super.setup(p_run, p_remote)
	_rows_box = Control.new()
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows_box)
	_bag_box = Control.new()
	_bag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bag_box)
	_relist()
	_redraw()


func refresh() -> void:
	_relist()
	_redraw()


func shown() -> void:
	_warning = ""
	if _zone == Zone.GRID and hero != _target:
		_zone = Zone.HEROES
	_relist()
	_redraw()


## Puts the cursor on hero `p_hero`; `pick` true opens the grid to give them a waiting Relic (the
## party screen's open_relics).
func focus_hero(p_hero: int, pick: bool = false) -> void:
	hero = clampi(p_hero, 0, run.party_size() - 1)
	_slot = 0
	_zone = Zone.HEROES
	if pick:
		open_bag()
	_redraw()


## Confirm on a hero: the grid opens to pick a waiting Relic for them. False (and the reason on the
## strip) if none waits.
func open_bag() -> bool:
	if run.waiting_relics().is_empty():
		_refuse("Nothing to give")
		return false
	_target = hero
	_zone = Zone.GRID
	_filter = Filter.ALL
	_relist()
	_cursor = maxi(0, _listed.find(run.waiting_relics()[0]))
	Sfx.play("menu_confirm")
	_redraw()
	return true


## Gives `item` (a Relic waiting for a hero) to the target hero. False if it cannot be given.
func put(item: GearData) -> bool:
	if item == null or not run.owns(item):
		Sfx.play("locked")
		return false
	if run.is_given(item):
		_refuse("Given")
		return false
	ask({"op": "give", "slot": _target, "relic": item.id})
	toast.emit(run.data.party[_target].display_name, item)
	Sfx.play("buff")
	hero = _target
	_slot = maxi(0, run.relics_of(hero).size() - 1)
	_zone = Zone.HEROES
	_relist()
	_redraw()
	changed.emit()
	return true


# --- PartyTab -----------------------------------------------------------------------------------

func handle_input(event: InputEvent) -> bool:
	if event.is_pressed() and not event.is_echo():
		_warning = ""
	if event is InputEventMouse and _mouse_input(event):
		return true
	if _zone == Zone.HEROES:
		return _rows_input(event)
	return _grid_input(event)


## Give only while a Relic waits for a hero (none in a new run since card #328: an old save's).
func hints() -> Array:
	var waiting := not run.waiting_relics().is_empty()
	if _zone == Zone.GRID:
		if waiting:
			return [[&"@arrows", ""], [&"menu_confirm", "Give"], [&"item_move", "Kind"]]
		return [[&"@arrows", ""], [&"item_move", "Kind"]]
	return [[&"@arrows", ""], [&"menu_confirm", "Give"]] if waiting else [[&"@arrows", ""]]


func info() -> Dictionary:
	if not _warning.is_empty():
		var focus := _focused()
		return {"icon": &"lock", "title": focus.display_name if focus != null else _warning,
				"color": HudStyle.TEXT_DIM, "chips": [], "line": _warning if focus != null else ""}
	var item := _focused()
	if item != null:
		return _relic_info(item)
	if _zone == Zone.HEROES:
		var waiting := not run.waiting_relics().is_empty()
		return {"icon": &"plus" if waiting else &"gem", "title": NO_RELICS, "color": HudStyle.TEXT_DIM,
				"chips": [], "line": ""}
	return {"icon": &"pouch", "title": "Empty", "color": HudStyle.TEXT_DIM, "chips": [], "line": ""}


## The Relics waiting for a hero (something to give).
func badge() -> int:
	return run.waiting_relics().size()


# --- input --------------------------------------------------------------------------------------

func _rows_input(event: InputEvent) -> bool:
	var count := run.relics_of(hero).size()
	if pressed(event, &"menu_up"):
		hero = wrapi(hero - 1, 0, run.party_size())
		_slot = clampi(_slot, 0, maxi(0, run.relics_of(hero).size() - 1))
	elif pressed(event, &"menu_down"):
		hero = wrapi(hero + 1, 0, run.party_size())
		_slot = clampi(_slot, 0, maxi(0, run.relics_of(hero).size() - 1))
	elif pressed(event, &"menu_left"):
		if _slot <= 0:
			return true
		_slot -= 1
	elif pressed(event, &"menu_right"):
		if _slot >= count - 1:
			if run.owned_relics().is_empty():
				return true
			# Into the grid at the same height, giving to the hero just left.
			_target = hero
			_zone = Zone.GRID
			_relist()
			_cursor = clampi(_row_for_hero(hero) * BAG_COLUMNS, 0, maxi(0, _listed.size() - 1))
		else:
			_slot += 1
	elif pressed(event, &"menu_confirm"):
		open_bag()
		return true
	else:
		return false
	Sfx.play("menu_move")
	_redraw()
	changed.emit()
	return true


func _grid_input(event: InputEvent) -> bool:
	var step := 0
	if pressed(event, &"menu_left"):
		if _cursor % BAG_COLUMNS == 0:
			_back_to_rows()
			return true
		step = -1
	elif pressed(event, &"menu_right"):
		step = 1
	elif pressed(event, &"menu_up"):
		step = -BAG_COLUMNS
	elif pressed(event, &"menu_down"):
		step = BAG_COLUMNS
	elif pressed(event, &"menu_confirm"):
		put(_listed[_cursor] if _cursor < _listed.size() else null)
		return true
	elif pressed(event, &"item_move"):
		_filter = ((_filter + 1) % Filter.size()) as Filter
		_relist()
		_cursor = 0
		Sfx.play("menu_move")
		_redraw()
		changed.emit()
		return true
	elif pressed(event, &"menu_cancel") or pressed(event, &"party_menu") or MenuMouse.is_back(event):
		Sfx.play("menu_cancel")
		_back_to_rows()
		return true
	else:
		return false
	var to := _cursor + step
	if to >= 0 and to < _listed.size():
		_cursor = to
		Sfx.play("menu_move")
	_redraw()
	changed.emit()
	return true


func _mouse_input(event: InputEvent) -> bool:
	var mouse := event as InputEventMouse
	var point := MenuMouse.local_point(self, mouse.position)
	var hit: Array = []
	for h: Array in _hits:
		if (h[0] as Rect2).has_point(point):
			hit = h
	if MenuMouse.is_press(event):
		var wheel := MenuMouse.wheel_step((event as InputEventMouseButton).button_index)
		if wheel != 0 and _zone == Zone.GRID:
			var to := _cursor + wheel * BAG_COLUMNS
			if to >= 0 and to < _listed.size():
				_cursor = to
				_redraw()
				changed.emit()
			return true
	if hit.is_empty():
		return false
	if event is InputEventMouseMotion:
		var moved := false
		if int(hit[1]) == Zone.HEROES and (_zone != Zone.HEROES or hero != int(hit[2]) or _slot != int(hit[3])):
			if _zone == Zone.GRID:
				return false  # picking in the grid: pointing at heroes does not leave it
			hero = int(hit[2])
			_slot = int(hit[3])
			moved = true
		elif int(hit[1]) == Zone.GRID and _zone == Zone.GRID and _cursor != int(hit[2]):
			_cursor = int(hit[2])
			moved = true
		if moved:
			Sfx.play("menu_move")
			_redraw()
			changed.emit()
		return moved
	if MenuMouse.is_click(event):
		if int(hit[1]) == Zone.HEROES:
			hero = int(hit[2])
			_slot = int(hit[3])
			_zone = Zone.HEROES
			open_bag()
		else:
			if _zone != Zone.GRID:
				_target = hero
				_zone = Zone.GRID
				_relist()
			_cursor = int(hit[2])
			put(_listed[_cursor] if _cursor < _listed.size() else null)
		return true
	return false


func _back_to_rows() -> void:
	_zone = Zone.HEROES
	hero = _target
	_slot = clampi(_slot, 0, maxi(0, run.relics_of(hero).size() - 1))
	Sfx.play("menu_move")
	_redraw()
	changed.emit()


func _refuse(reason: String) -> void:
	_warning = reason
	Sfx.play("locked")
	_redraw()
	changed.emit()


# --- what is shown --------------------------------------------------------------------------------

## The grid's Relics through the filter: the ones waiting for a hero first, then by category, rarity
## (rarest first) and name.
func _relist() -> void:
	var keep := _listed[_cursor] if _cursor >= 0 and _cursor < _listed.size() else null
	_listed.clear()
	for item: GearData in run.owned_relics():
		if _filter == Filter.ALL or item.category() == int(_filter) - 1:
			_listed.append(item)
	_listed.sort_custom(func(a: GearData, b: GearData) -> bool:
		var ag := run.is_given(a)
		var bg := run.is_given(b)
		if ag != bg:
			return not ag
		if a.category() != b.category():
			return a.category() < b.category()
		if a.rarity != b.rarity:
			return a.rarity > b.rarity
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	if keep != null and _listed.has(keep):
		_cursor = _listed.find(keep)
	_cursor = clampi(_cursor, 0, maxi(0, _listed.size() - 1))


func _focused() -> GearData:
	if _zone == Zone.GRID:
		return _listed[_cursor] if _cursor < _listed.size() else null
	var mine := run.relics_of(hero)
	return mine[_slot] if _slot >= 0 and _slot < mine.size() else null


## The strip for a Relic: its icon and name, stat line, who has it (or Waiting), and what it does.
func _relic_info(item: GearData) -> Dictionary:
	var color := GearData.ROT_TOUCHED_COLOR if item.rot_touched else BackpackGrid.rarity_color(BackpackGrid.gear_step(item))
	var chips: Array = []
	var stat := item.stat_text()
	if not stat.is_empty():
		chips.append([UiGlyph.attribute_glyph(item.stat), stat, HudStyle.TEXT])
	var holder := run.holder_of(item)
	if holder >= 0:
		chips.append([&"person", run.data.party[holder].display_name, run.data.party[holder].color.lightened(0.25)])
	else:
		chips.append([&"pouch", "Waiting", HudStyle.GOLD])
	return {"icon": item, "title": item.display_name, "color": color, "chips": chips, "line": item.description}


## The grid row level with hero `slot`'s row (moving across).
func _row_for_hero(slot: int) -> int:
	var rows := maxi(1, ceili(float(_listed.size()) / float(BAG_COLUMNS)))
	if run.party_size() <= 1:
		return 0
	return clampi(roundi(float(slot) * float(rows - 1) / float(run.party_size() - 1)), 0, rows - 1)


## Where a hero's `count` Relics sit in their row: [columns, rows, icon px, step px]. Up to NAMED_MAX
## in one row at full size (names under them), more in two rows, as big as fits SLOT_AREA.
static func relic_layout(count: int) -> Array:
	if count <= NAMED_MAX:
		return [maxi(1, count), 1, SLOT_PX, SLOT_STEP]
	var columns := ceili(float(count) / 2.0)
	var step := minf(SLOT_AREA.x / float(columns), SLOT_AREA.y / 2.0)
	return [columns, 2, minf(SLOT_PX, step - SLOT_GAP), step]


# --- drawing --------------------------------------------------------------------------------------

func _redraw() -> void:
	if _rows_box == null:
		return
	_hits.clear()
	_clear(_rows_box)
	_clear(_bag_box)
	var count := run.party_size()
	var total := float(count) * ROW_HEIGHT + float(count - 1) * ROW_GAP
	var top := maxf(0.0, (PAGE_SIZE.y - total) * 0.5)
	for slot: int in count:
		_draw_row(slot, Vector2(ROW_LEFT, top + float(slot) * (ROW_HEIGHT + ROW_GAP)))
	_draw_bag()


func _draw_row(slot: int, at: Vector2) -> void:
	var c := run.data.party[slot]
	# In the grid the hero a waiting Relic would go to stays lit; with nothing to give, none is.
	var giving := _zone == Zone.GRID and slot == _target and not run.waiting_relics().is_empty()
	var on_row := (_zone == Zone.HEROES and slot == hero) or giving
	var plate := Panel.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = at
	plate.size = Vector2(ROW_WIDTH, ROW_HEIGHT)
	plate.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.GOLD if on_row else HudStyle.EDGE_DIM,
			3 if on_row else 2, 10, ROW_HEIGHT, HudStyle.SLANT * 0.12))
	_rows_box.add_child(plate)
	var face := HudStyle.portrait_frame(AssetLoader.texture(c.portrait_path, Vector2i(48, 48)), c.color, FACE_PX)
	face.position = Vector2(34.0, (ROW_HEIGHT - FACE_PX) * 0.5 - 4.0)
	plate.add_child(face)
	var name := HudStyle.make_title(c.display_name, NAME_SIZE, c.color.lightened(0.25))
	name.position = Vector2(176.0, 30.0)
	plate.add_child(name)
	var level := HudStyle.make_number("Lv %d" % run.levels[slot], TEXT_SIZE, HudStyle.TEXT_DIM)
	level.position = Vector2(176.0 + name.get_minimum_size().x + 16.0, 40.0)
	plate.add_child(level)
	# HP: a bar and its numbers.
	var heart := UiGlyph.make(&"heart", 24.0, HudStyle.HP_FILL)
	heart.position = Vector2(176.0, 100.0)
	plate.add_child(heart)
	var bar := HudStyle.bar(HudStyle.HP_FILL if run.hp[slot] * 100 > run.max_hp(slot) * 30 else HudStyle.HP_LOW, 14.0)
	bar.position = Vector2(210.0, 105.0)
	bar.size = Vector2(HP_BAR_WIDTH, 14.0)
	bar.max_value = run.max_hp(slot)
	bar.value = run.hp[slot]
	plate.add_child(bar)
	var hp := HudStyle.make_number("%d / %d" % [run.hp[slot], run.max_hp(slot)], SMALL_SIZE, HudStyle.TEXT)
	hp.position = Vector2(210.0 + HP_BAR_WIDTH + 12.0, 96.0)
	plate.add_child(hp)
	# Power and speed as glyph + number.
	var x := 176.0
	for pair: Array in [[&"sword", run.power(slot)], [&"bolt", run.speed(slot)]]:
		var glyph := UiGlyph.make(pair[0], 22.0, HudStyle.TEXT_DIM)
		glyph.position = Vector2(x, 152.0)
		plate.add_child(glyph)
		var number := HudStyle.make_number(str(pair[1]), SMALL_SIZE, HudStyle.TEXT)
		number.position = Vector2(x + 30.0, 146.0)
		plate.add_child(number)
		x += 110.0
	_draw_relics(slot, plate, at, _zone == Zone.HEROES and slot == hero)


## Hero `slot`'s Relics on their row. With none: an empty frame with a plus while a Relic waits to
## be given, else a dim "No Relics".
func _draw_relics(slot: int, plate: Control, at: Vector2, on_row: bool) -> void:
	var mine := run.relics_of(slot)
	if mine.is_empty() and run.waiting_relics().is_empty():
		var none := HudStyle.make_label(NO_RELICS, TEXT_SIZE, HudStyle.GOLD if on_row else HudStyle.TEXT_DIM)
		none.position = Vector2(SLOT_LEFT, (ROW_HEIGHT - none.get_minimum_size().y) * 0.5)
		plate.add_child(none)
		_hits.append([Rect2(at + Vector2(SLOT_LEFT, 20.0), Vector2(SLOT_PX, SLOT_PX)), Zone.HEROES, slot, 0])
		return
	var layout := relic_layout(mine.size())
	var columns := int(layout[0])
	var px := float(layout[2])
	var step := float(layout[3])
	var rows := int(layout[1])
	var top := (ROW_HEIGHT - (float(rows) * step - (step - px))) * 0.5 if rows > 1 else 20.0
	for i: int in maxi(1, mine.size()):
		var col := i % columns
		var r := floori(float(i) / float(columns))
		var cell := Rect2(Vector2(SLOT_LEFT + float(col) * step, top + float(r) * step), Vector2(px, px))
		var icon := RelicIcon.new()
		if mine.is_empty():
			icon.setup_slot(RelicIcon.SlotState.EMPTY, px)
		else:
			icon.setup(mine[i], px)
		icon.chosen = on_row and i == _slot
		icon.position = cell.position
		plate.add_child(icon)
		_hits.append([Rect2(at + cell.position, cell.size), Zone.HEROES, slot, i])
		if rows == 1 and not mine.is_empty():
			var label := HudStyle.make_label(mine[i].display_name, SMALL_SIZE - 2,
					HudStyle.GOLD if icon.chosen else HudStyle.TEXT_DIM)
			label.position = Vector2(cell.position.x + (px - SLOT_NAME_WIDTH) * 0.5, 20.0 + px + 26.0)
			label.custom_minimum_size.x = SLOT_NAME_WIDTH
			label.size.x = SLOT_NAME_WIDTH
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.clip_text = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			plate.add_child(label)


func _draw_bag() -> void:
	var plate := Panel.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = Vector2(BAG_LEFT, 0.0)
	plate.size = Vector2(BAG_WIDTH, PAGE_SIZE.y)
	var in_grid := _zone == Zone.GRID
	plate.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.GOLD if in_grid else HudStyle.EDGE_DIM,
			3 if in_grid else 2, 10, PAGE_SIZE.y, HudStyle.SLANT * 0.05))
	_bag_box.add_child(plate)
	# Head: the gem and how many Relics the run has, then the kind filter chips.
	var gem := UiGlyph.make(&"gem", 36.0, HudStyle.GOLD)
	gem.position = Vector2(30.0, 24.0)
	plate.add_child(gem)
	var count := HudStyle.make_number(str(run.owned_relics().size()), TEXT_SIZE + 4, HudStyle.TEXT)
	count.position = Vector2(76.0, 22.0)
	plate.add_child(count)
	var x := 170.0
	for f: int in Filter.size():
		var chip := _filter_chip(f)
		chip.position = Vector2(x, 24.0)
		plate.add_child(chip)
		x += chip.get_combined_minimum_size().x + 12.0
	var grid_top := 92.0
	var rows := ceili(float(_listed.size()) / float(BAG_COLUMNS))
	var row := floori(float(_cursor) / float(BAG_COLUMNS))
	if row < _top_row:
		_top_row = row
	elif row >= _top_row + BAG_ROWS:
		_top_row = row - BAG_ROWS + 1
	_top_row = clampi(_top_row, 0, maxi(0, rows - BAG_ROWS))
	if _listed.is_empty():
		var empty := UiGlyph.make(&"gem", 80.0, Color(HudStyle.TEXT_DIM, 0.5))
		empty.position = Vector2((BAG_WIDTH - 80.0) * 0.5, 280.0)
		plate.add_child(empty)
		return
	for i: int in range(_top_row * BAG_COLUMNS, mini(_listed.size(), (_top_row + BAG_ROWS) * BAG_COLUMNS)):
		var item := _listed[i]
		var col := i % BAG_COLUMNS
		var r := floori(float(i) / float(BAG_COLUMNS)) - _top_row
		var cell := Rect2(Vector2(28.0 + float(col) * BAG_CELL, grid_top + float(r) * (BAG_CELL + BAG_ROW_GAP)),
				Vector2(BAG_CELL, BAG_CELL))
		var icon := RelicIcon.new()
		icon.setup(item, BAG_ICON_PX)
		icon.chosen = in_grid and i == _cursor
		var holder := run.holder_of(item)
		if holder >= 0:
			var c := run.data.party[holder]
			icon.set_tag(c.display_name.left(1), c.color)
		icon.modulate = Color(1.0, 1.0, 1.0, 0.6 if holder >= 0 and not icon.chosen else 1.0)
		icon.position = cell.position + (cell.size - Vector2(BAG_ICON_PX, BAG_ICON_PX)) * 0.5
		plate.add_child(icon)
		_hits.append([Rect2(plate.position + cell.position, cell.size), Zone.GRID, i, 0])
	if rows > BAG_ROWS:
		# More below or above: a thin scroll mark on the right edge.
		var track := ColorRect.new()
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.color = Color(HudStyle.EDGE_DIM, 0.5)
		track.position = Vector2(BAG_WIDTH - 22.0, grid_top)
		track.size = Vector2(4.0, float(BAG_ROWS) * (BAG_CELL + BAG_ROW_GAP))
		plate.add_child(track)
		var thumb := ColorRect.new()
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.color = HudStyle.GOLD
		thumb.size = Vector2(4.0, track.size.y * float(BAG_ROWS) / float(rows))
		thumb.position = track.position + Vector2(0.0, track.size.y * float(_top_row) / float(rows))
		plate.add_child(thumb)


## A filter chip: its glyph and how many Relics of that kind the run has; gold when chosen.
func _filter_chip(f: int) -> Control:
	var on := f == int(_filter)
	var n := 0
	for item: GearData in run.owned_relics():
		if f == Filter.ALL or item.category() == f - 1:
			n += 1
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK_SOLID, HudStyle.GOLD if on else HudStyle.EDGE_DIM,
			2, 6, 34.0, HudStyle.SLANT, false))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	box.add_child(line)
	var tint := HudStyle.GOLD if on else HudStyle.TEXT_DIM
	if f != Filter.ALL:
		tint = RelicIcon.category_color(f - 1) if on else Color(RelicIcon.category_color(f - 1), 0.7)
	line.add_child(UiGlyph.make(FILTER_GLYPHS[f], 22.0, tint))
	line.add_child(HudStyle.make_number(str(n), CHIP_SIZE, HudStyle.GOLD if on else HudStyle.TEXT))
	return box


static func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.free()
