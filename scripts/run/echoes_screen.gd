class_name EchoesScreen
extends CanvasLayer
## A hero's Echoes (DESIGN.md 8.17), laid out like Expedition 33's Lumina page. Left: tabs (All,
## Offensive, Defensive, Support; LT / RT), the sort (X / R: name or cost), and every Echo learned
## for good (DESIGN.md 8.19: any of them can be worn, Relic or none) in three columns, each with its cost in Echo points (the ones this hero wears in
## purple). Under them: the Echo under the cursor, and the worn Relics still being learned. Right:
## the hero (LB / RB changes hero), their combat stats, their attributes as a radar, the Echoes they
## wear and their free Echo points. Confirm puts the Echo under the cursor on or takes it off.
## Phase 22: the worn Relics still being learned show as their icons with a small bar of Echo pips
## under each; the rules (pips, Echo points) are in the Glossary, not on this page.
## Each Echo goes on one hero at a time. The worn Echoes and the points start over every run; the
## learned Echoes stay. Opened from the party screen (the
## Echoes button on a hero card). Online, a client's changes go to the host as RunState ops.

signal done
## Online client: a change for the host to make (RunState.apply_op data).
signal op_requested(op: Dictionary)

enum Sort { NAME, COST }
const SORT_NAMES: Array[String] = ["Name", "Cost"]
## Tab 0 is every Echo; tab N is GearData.Category N - 1.
const TAB_NAMES: Array[String] = ["All", "Offensive", "Defensive", "Support"]

const TITLE_SIZE: int = 56
const TAB_SIZE: int = 22
const NAME_SIZE: int = 22
const COST_SIZE: int = 26
const TEXT_SIZE: int = 22
const SMALL_SIZE: int = 18
const HERO_SIZE: int = 42
const POINTS_SIZE: int = 56
const MARGIN_X: float = 70.0
const MARGIN_TOP: float = 30.0
const COLUMN_GAP: int = 50
const LEFT_WIDTH: float = 1150.0
const RIGHT_WIDTH: float = 560.0
const COLUMNS: int = 3
const ROWS: int = 11
const ROW_SIZE := Vector2(370.0, 46.0)
const ICON_PX: float = 30.0
const HERO_FACE_PX: float = 72.0
const RADAR_PX: float = 250.0
## The worn Relics being learned: icon size, and each Echo pip of the bar under it.
const LEARN_ICON_PX: float = 44.0
const PIP_SIZE := Vector2(5.0, 8.0)
const PIP_GAP: int = 2
## Echo pips: filled (the Relics tab's colour) and still to fill.
const PIP_FULL := Color(0.62, 0.32, 0.72)
const PIP_EMPTY := Color(0.42, 0.37, 0.3, 0.5)
const ON_HERO_BG := Color(0.32, 0.12, 0.36, 0.9)
const CHOSEN_BG := Color(0.3, 0.24, 0.1, 0.9)

## Online client: changes are asked of the host instead of made here.
var remote: bool = false
var _run: RunState
var _hero: int = 0
var _tab: int = 0
var _sort: Sort = Sort.NAME
## The Echoes shown (this tab, sorted).
var _listed: Array[GearData] = []
var _cursor: int = 0
var _top_row: int = 0
## Why the last change was refused (shown until the next press).
var _warning: String = ""
var _tabs_box: HBoxContainer
var _sort_box: PanelContainer
var _grid: GridContainer
var _detail: Label
var _detail_more: Label
## The worn Relics whose Echo is still being learned: icon and pips bar each (learning()).
var _learning: HBoxContainer
var _right: VBoxContainer
var _hint: HintBar
## The Echo rows on screen and the list index of each (for the mouse).
var _row_nodes: Array = []
var _row_ids: Array[int] = []


func setup(run: RunState, hero: int) -> void:
	_run = run
	_hero = clampi(hero, 0, run.party_size() - 1)
	_build()
	_relist()
	_redraw()


## The run changed (online, another player's change arrived): redraw.
func refresh() -> void:
	_relist()
	_redraw()


func close() -> void:
	done.emit()


## The Echo under the cursor (null: none).
func chosen() -> GearData:
	return _listed[_cursor] if _cursor >= 0 and _cursor < _listed.size() else null


## Shows tab `tab` (0 All, then the categories).
func set_tab(tab: int) -> void:
	_tab = wrapi(tab, 0, TAB_NAMES.size())
	_cursor = 0
	_top_row = 0
	_relist()
	_redraw()


## Puts the Echo under the cursor on the hero or takes it off (the player presses Confirm).
func toggle() -> void:
	var item := chosen()
	if item == null:
		Sfx.play("locked")
		return
	var on := not _run.wears_echo(_hero, item)
	if on:
		var reason := _run.echo_blocked_reason(_hero, item)
		if not reason.is_empty():
			_warning = reason
			Sfx.play("locked")
			_redraw()
			return
	_ask({"op": "echo", "slot": _hero, "relic": item.id, "on": on})
	Sfx.play("buff" if on else "menu_cancel")
	_redraw()


func _relist() -> void:
	var keep := chosen()
	_listed.clear()
	for item: GearData in _run.learned_echoes():
		if _tab == 0 or item.category() == _tab - 1:
			_listed.append(item)
	_listed.sort_custom(func(a: GearData, b: GearData) -> bool:
		if _sort == Sort.COST and a.echo_cost != b.echo_cost:
			return a.echo_cost > b.echo_cost
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	_cursor = clampi(_listed.find(keep) if keep != null and _listed.has(keep) else _cursor, 0, maxi(0, _listed.size() - 1))


## The mouse (card #202): pointing at an Echo picks it, a left click puts it on or takes it off, a
## right click (or the mouse's back button) closes, the wheel moves a row. True when used.
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
	var row := MenuMouse.control_at(_row_nodes, mouse.position)
	if row < 0:
		return false
	if event is InputEventMouseMotion and _row_ids[row] != _cursor:
		_cursor = _row_ids[row]
		Sfx.play("menu_move")
		_redraw()
		return true
	if MenuMouse.is_click(event):
		_handled()
		_cursor = _row_ids[row]
		toggle()
		return true
	return false


## Makes a change: here, or (online client) by asking the host.
func _ask(op: Dictionary) -> void:
	if remote:
		op_requested.emit(op)
	else:
		_run.apply_op(op)


# --- input ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo():
		_warning = ""
	if _mouse_input(event):
		return
	var step := 0
	if _pressed(event, &"item_turn_left") or _pressed(event, &"item_turn_right"):
		_hero = wrapi(_hero + (-1 if event.is_action(&"item_turn_left") else 1), 0, _run.party_size())
		Sfx.play("menu_move")
	elif _pressed(event, &"party_attributes") or _pressed(event, &"party_skills"):
		set_tab(_tab + (-1 if event.is_action(&"party_attributes") else 1))
		Sfx.play("menu_move")
	elif _pressed(event, &"item_move"):
		_sort = ((_sort + 1) % Sort.size()) as Sort
		_relist()
		Sfx.play("menu_move")
	elif _pressed(event, &"menu_confirm"):
		_handled()
		toggle()
		return
	elif _pressed(event, &"menu_cancel") or _pressed(event, &"party_menu"):
		_handled()
		Sfx.play("menu_cancel")
		close()
		return
	elif _pressed(event, &"menu_left"):
		step = -1
	elif _pressed(event, &"menu_right"):
		step = 1
	elif _pressed(event, &"menu_up"):
		step = -COLUMNS
	elif _pressed(event, &"menu_down"):
		step = COLUMNS
	else:
		return
	_handled()
	if step != 0 and _cursor + step >= 0 and _cursor + step < _listed.size():
		_cursor += step
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
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.custom_minimum_size.x = LEFT_WIDTH
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 28)
	left.add_child(head)
	head.add_child(HudStyle.make_worn_title("Echoes", TITLE_SIZE))
	_sort_box = PanelContainer.new()
	_sort_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sort_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sort_box.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.EDGE_DIM, 2, 6, 40.0, HudStyle.SLANT, false))
	head.add_child(_sort_box)
	_tabs_box = HBoxContainer.new()
	_tabs_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tabs_box.add_theme_constant_override("separation", 14)
	left.add_child(_tabs_box)
	left.add_child(ListMenu.divider(LEFT_WIDTH))
	_grid = GridContainer.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.custom_minimum_size.y = ROWS * (ROW_SIZE.y + 8.0)
	left.add_child(_grid)
	var detail_box := PanelContainer.new()
	detail_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_box.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.EDGE_DIM, 2, 12, 90.0, 0.08, false))
	left.add_child(detail_box)
	var detail_col := VBoxContainer.new()
	detail_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_box.add_child(detail_col)
	_detail = HudStyle.make_label("", TEXT_SIZE + 2, HudStyle.GOLD)
	detail_col.add_child(_detail)
	_detail_more = HudStyle.make_label("", TEXT_SIZE, HudStyle.TEXT)
	_detail_more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_more.custom_minimum_size.x = LEFT_WIDTH - 40.0
	detail_col.add_child(_detail_more)
	_learning = HBoxContainer.new()
	_learning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_learning.add_theme_constant_override("separation", 16)
	detail_col.add_child(_learning)
	_right = VBoxContainer.new()
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.custom_minimum_size.x = RIGHT_WIDTH
	_right.alignment = BoxContainer.ALIGNMENT_CENTER
	_right.add_theme_constant_override("separation", 14)
	row.add_child(_right)
	_hint = ListMenu.screen_footer(self, [])


# --- drawing ----------------------------------------------------------------------------------

func _redraw() -> void:
	if _grid == null:
		return
	_clear(_sort_box)
	_sort_box.add_child(HintBar.entry_row(&"item_move", "Sort: %s" % SORT_NAMES[_sort], TEXT_SIZE, HudStyle.TEXT))
	_redraw_tabs()
	_redraw_grid()
	_redraw_detail()
	_redraw_hero()
	var entries: Array = [[&"@arrows", "Move"], [&"menu_confirm", "Wear / take off"]]
	if _run.party_size() > 1:
		entries.append([&"item_turn_left", ""])
		entries.append([&"item_turn_right", "Hero"])
	entries.append([&"menu_cancel", "Done"])
	_hint.set_entries(entries)


func _redraw_tabs() -> void:
	_clear(_tabs_box)
	_tabs_box.add_child(HintBar.entry_row(&"party_attributes", "", TAB_SIZE))
	for i: int in TAB_NAMES.size():
		var on := i == _tab
		var tab := HudStyle.make_title(TAB_NAMES[i], TAB_SIZE, HudStyle.GOLD if on else HudStyle.TEXT_DIM)
		tab.custom_minimum_size.x = 150.0
		tab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab.add_theme_stylebox_override("normal", HudStyle.slant(ON_HERO_BG if on else HudStyle.INK,
				HudStyle.GOLD if on else HudStyle.EDGE_DIM, 2, 4, 34.0, HudStyle.SLANT, false))
		_tabs_box.add_child(tab)
	_tabs_box.add_child(HintBar.entry_row(&"party_skills", "", TAB_SIZE))


func _redraw_grid() -> void:
	_clear(_grid)
	var row := floori(float(_cursor) / float(COLUMNS))
	if row < _top_row:
		_top_row = row
	elif row >= _top_row + ROWS:
		_top_row = row - ROWS + 1
	_row_nodes.clear()
	_row_ids.clear()
	for i: int in range(_top_row * COLUMNS, mini(_listed.size(), (_top_row + ROWS) * COLUMNS)):
		var card := _row_card(_listed[i], i == _cursor)
		_grid.add_child(card)
		_row_nodes.append(card)
		_row_ids.append(i)


## One Echo: its diamond, name and cost; purple while this hero wears it, dim while they cannot.
func _row_card(item: GearData, on_cursor: bool) -> Control:
	var mine := _run.wears_echo(_hero, item)
	var can := mine or _run.echo_blocked_reason(_hero, item).is_empty()
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = ROW_SIZE
	panel.add_theme_stylebox_override("panel", HudStyle.slant(CHOSEN_BG if on_cursor else (ON_HERO_BG if mine else HudStyle.INK),
			HudStyle.GOLD if on_cursor else (HudStyle.EDGE if mine else HudStyle.EDGE_DIM), 3 if on_cursor else 2, 4,
			ROW_SIZE.y, HudStyle.SLANT * 0.5, false))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 10)
	panel.add_child(line)
	var icon := RelicIcon.new()
	icon.setup(item, ICON_PX)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var color := HudStyle.GOLD if mine else (HudStyle.TEXT if can else HudStyle.TEXT_DIM)
	var name := HudStyle.make_title(item.display_name, NAME_SIZE, color)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(name)
	var cost := HudStyle.make_number(str(item.echo_cost), COST_SIZE, color)
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(cost)
	return panel


func _redraw_detail() -> void:
	_redraw_learning()
	var item := chosen()
	if not _warning.is_empty():
		_detail.text = _warning
		_detail_more.text = ""
		return
	if item == null:
		_detail.text = "No Echoes learned yet" if _run.learned_echoes().is_empty() else "Nothing in this tab"
		_detail_more.text = ""
		return
	var head := PackedStringArray([item.display_name, "%d pt%s" % [item.echo_cost, "" if item.echo_cost == 1 else "s"],
			GearData.CATEGORY_NAMES[item.category()]])
	var wearers := PackedStringArray()
	for slot: int in _run.party_size():
		if _run.wears_echo(slot, item):
			wearers.append(_run.data.party[slot].display_name)
	if not wearers.is_empty():
		head.append("Worn by " + ", ".join(wearers))
	_detail.text = "    ".join(head)
	_detail_more.text = item.description
	var reason := _run.echo_blocked_reason(_hero, item)
	if not reason.is_empty() and not _run.wears_echo(_hero, item):
		_detail_more.text += "\n" + reason


## The worn Relics whose Echo is still being learned, and how far along: [[GearData, pips, needed]].
func learning() -> Array[Array]:
	var list: Array[Array] = []
	# Nothing is learned where Relics earn no pips (a Fight Rush, DESIGN.md 8.21).
	if not _run.teaches_echoes():
		return list
	for slots: Array in _run.gear:
		for item: Variant in slots:
			if item != null and not _run.echo_learned(item as GearData):
				list.append([item as GearData, _run.mastery_of(item as GearData), _run.tuning.mastery_needed])
	return list


## The learning row: the Echo mark, then each Relic being learned as its icon over its pips bar.
func _redraw_learning() -> void:
	_clear(_learning)
	var list := learning()
	if list.is_empty():
		return
	var mark := UiGlyph.make(&"echo", LEARN_ICON_PX * 0.6, HudStyle.TEXT_DIM)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_learning.add_child(mark)
	for entry: Array in list:
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 4)
		var icon := RelicIcon.make(entry[0] as GearData, LEARN_ICON_PX)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
		box.add_child(pips_bar(int(entry[1]), int(entry[2])))
		_learning.add_child(box)


## A small bar of Echo pips: `pips` of `needed` filled.
static func pips_bar(pips: int, needed: int) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", PIP_GAP)
	for i: int in needed:
		var pip := ColorRect.new()
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.custom_minimum_size = PIP_SIZE
		pip.color = PIP_FULL if i < pips else PIP_EMPTY
		bar.add_child(pip)
	return bar


## The right side: the hero, their stats, attributes, worn Echoes and free Echo points.
func _redraw_hero() -> void:
	_clear(_right)
	var c := _run.data.party[_hero]
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 16)
	_right.add_child(head)
	head.add_child(HudStyle.portrait_frame(AssetLoader.texture(c.portrait_path, Vector2i(48, 48)), c.color, HERO_FACE_PX))
	var names := VBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(names)
	names.add_child(HudStyle.make_title(c.display_name, HERO_SIZE, c.color.lightened(0.25)))
	names.add_child(HudStyle.make_label("Level %d" % _run.levels[_hero], SMALL_SIZE + 2, HudStyle.TEXT_DIM))
	_right.add_child(_stats_panel())
	var values: Array[int] = []
	var top := 10
	for kind: int in Attributes.COUNT:
		values.append(_run.attribute_total(_hero, kind))
		top = maxi(top, values[kind])
	var radar := AttributeRadar.new()
	radar.setup(values, top, c.color.lightened(0.2), RADAR_PX)
	radar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_right.add_child(radar)
	_right.add_child(HudStyle.make_title("Echoes worn", TEXT_SIZE, HudStyle.GOLD))
	var worn := PackedStringArray()
	for id: Variant in _run.echoes[_hero]:
		var item := _run.relic_by_id(String(id))
		if item != null:
			worn.append("%s (%d)" % [item.display_name, item.echo_cost])
	var worn_label := HudStyle.make_label(", ".join(worn) if not worn.is_empty() else "None yet", SMALL_SIZE + 2, HudStyle.TEXT)
	worn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	worn_label.custom_minimum_size.x = RIGHT_WIDTH
	_right.add_child(worn_label)
	var points := PanelContainer.new()
	points.mouse_filter = Control.MOUSE_FILTER_IGNORE
	points.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.EDGE, 2, 10, 90.0, 0.1))
	_right.add_child(points)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", -4)
	points.add_child(box)
	var label := HudStyle.make_label("Available Echo Points", SMALL_SIZE + 2, HudStyle.TEXT_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var free := _run.free_echo_points(_hero)
	var number := HudStyle.make_number("%d / %d" % [free, _run.echo_points(_hero)], POINTS_SIZE,
			HudStyle.GOLD if free > 0 else HudStyle.TEXT_DIM)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(number)


## Health, Attack Power, Speed, Defense and Critical Rate, two to a row.
func _stats_panel() -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.EDGE_DIM, 2, 10, 120.0, 0.1, false))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	col.add_child(HudStyle.make_title("Combat stats", TEXT_SIZE, HudStyle.GOLD))
	var grid := GridContainer.new()
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	col.add_child(grid)
	var stats := [["Health", str(_run.max_hp(_hero))], ["Speed", str(_run.speed(_hero))],
			["Attack Power", str(_run.power(_hero))], ["Critical Rate", "%d%%" % _run.crit_percent(_hero)],
			["Defense", "%d%%" % _run.defense_percent(_hero)]]
	for pair: Array in stats:
		grid.add_child(HudStyle.make_label(String(pair[0]), SMALL_SIZE + 2, HudStyle.TEXT_DIM))
		var value := HudStyle.make_number(String(pair[1]), SMALL_SIZE + 4, HudStyle.TEXT)
		value.custom_minimum_size.x = 70.0
		grid.add_child(value)
	return panel


static func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.free()


func _handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, true, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)
