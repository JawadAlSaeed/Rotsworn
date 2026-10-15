class_name AttributesScreen
extends CanvasLayer
## A hero's attributes (DESIGN.md 8.2), like Expedition 33's attributes page. Opened from the party
## screen (T / LT). Top: the hero, their level and XP, and the points left to spend. Left: the five
## attributes with the points in each; right of each, the stat it raises, its value now and what
## one more point gives. Up / down picks an attribute, right adds a point, left takes one back,
## X / R takes every point back (a free reset), LB / RB (Z / C) changes hero. Every change counts
## at once (no confirm step); the HP a hero is missing stays the same, so a reset never heals.
## Online, a client's changes go to the host as RunState ops (op_requested).

signal done
## Online client: a change for the host to make (RunState.apply_op data).
signal op_requested(op: Dictionary)

const TITLE_SIZE: int = 52
const TEXT_SIZE: int = 30
const SMALL_SIZE: int = 24
const NAME_SIZE: int = 40
const NAME_WIDTH: float = 230.0
const POINTS_WIDTH: float = 90.0
const STAT_WIDTH: float = 250.0
const VALUE_WIDTH: float = 170.0
const PER_POINT_WIDTH: float = 290.0
const ROW_GAP: int = 6

## Online client: changes are asked of the host instead of made here.
var remote: bool = false
var _run: RunState
var _hero: int = 0
var _row: int = 0
var _name: Label
var _level: Label
var _points: Label
## One per attribute: {panel: PanelContainer, points: Label, value: Label}.
var _rows: Array[Dictionary] = []
var _info: Label
var _hint: HintBar
var _prompt: ConfirmPrompt


func setup(run: RunState, hero: int) -> void:
	_run = run
	_hero = clampi(hero, 0, run.party_size() - 1)
	var column := ListMenu.screen_column(self, "Attributes", TITLE_SIZE)
	_name = HudStyle.make_title("", NAME_SIZE)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_name)
	_level = ListMenu.centred_label("", TEXT_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_level)
	_points = ListMenu.centred_label("", TEXT_SIZE, HudStyle.GOLD)
	column.add_child(_points)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.PANEL_BG, HudStyle.PANEL_BORDER, 2, 18))
	column.add_child(panel)
	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", ROW_GAP)
	panel.add_child(list)
	list.add_child(_header())
	for kind: int in Attributes.COUNT:
		list.add_child(_build_row(kind))
	_info = ListMenu.centred_label("", SMALL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_info)
	_hint = ListMenu.screen_footer(self, [])
	_redraw()


## The run changed (online, another player's change arrived): redraw.
func refresh() -> void:
	_redraw()


func close() -> void:
	done.emit()


# --- building ---------------------------------------------------------------------------------

func _header() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part: Array in [["Attribute", NAME_WIDTH], ["Points", POINTS_WIDTH], ["Raises", STAT_WIDTH],
			["Now", VALUE_WIDTH], ["Each point", PER_POINT_WIDTH]]:
		row.add_child(_cell(String(part[0]), float(part[1]), SMALL_SIZE, HudStyle.TEXT_DIM))
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", ListMenu.row_style(false))
	box.add_child(row)
	return box


func _build_row(kind: int) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	row.add_child(_cell(Attributes.NAMES[kind], NAME_WIDTH, TEXT_SIZE, HudStyle.TEXT))
	var points := _cell("", POINTS_WIDTH, TEXT_SIZE, HudStyle.GOLD)
	row.add_child(points)
	row.add_child(_cell(Attributes.STATS[kind], STAT_WIDTH, TEXT_SIZE, HudStyle.TEXT_DIM))
	var value := _cell("", VALUE_WIDTH, TEXT_SIZE, HudStyle.TEXT)
	row.add_child(value)
	row.add_child(_cell(Attributes.per_point_text(kind, _run.tuning), PER_POINT_WIDTH, SMALL_SIZE, HudStyle.TEXT_DIM))
	_rows.append({"panel": panel, "points": points, "value": value})
	return panel


func _cell(text: String, width: float, font_size: int, color: Color) -> Label:
	var label := HudStyle.make_label(text, font_size, color)
	label.custom_minimum_size.x = width
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


# --- input ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _prompt != null:
		return
	if _pressed(event, &"menu_up"):
		_row = wrapi(_row - 1, 0, Attributes.COUNT)
		Sfx.play("menu_move")
	elif _pressed(event, &"menu_down"):
		_row = wrapi(_row + 1, 0, Attributes.COUNT)
		Sfx.play("menu_move")
	elif _pressed(event, &"menu_right") or _pressed(event, &"menu_confirm"):
		_change(1)
	elif _pressed(event, &"menu_left"):
		_change(-1)
	elif _pressed(event, &"item_move"):
		_handled()
		_ask_reset()
		return
	elif _pressed(event, &"item_turn_left") or _pressed(event, &"item_turn_right"):
		_hero = wrapi(_hero + (-1 if event.is_action(&"item_turn_left") else 1), 0, _run.party_size())
		Sfx.play("menu_move")
	elif _pressed(event, &"menu_cancel") or _pressed(event, &"party_menu") or _pressed(event, &"party_attributes"):
		_handled()
		Sfx.play("menu_cancel")
		close()
		return
	else:
		return
	_handled()
	_redraw()


## Adds (step 1) or takes back (step -1) a point in the chosen attribute.
func _change(step: int) -> void:
	var values: Array[int] = []
	values.assign(_run.attributes[_hero])
	if step > 0 and _run.free_points(_hero) <= 0:
		Sfx.play("locked")
		return
	if step < 0 and values[_row] <= 0:
		Sfx.play("locked")
		return
	values[_row] += step
	_ask({"op": "attributes", "slot": _hero, "values": values})
	Sfx.play("buff" if step > 0 else "menu_cancel")


func _ask_reset() -> void:
	if Attributes.total(_run.attributes[_hero]) <= 0:
		Sfx.play("locked")
		return
	_prompt = ConfirmPrompt.new()
	add_child(_prompt)
	_prompt.setup("Take back every point?", "%s gets all their points back to spend again." %
			_run.data.party[_hero].display_name, "Reset", "Keep them")
	_prompt.answered.connect(func(yes: bool) -> void:
		_handled()
		_prompt.queue_free()
		_prompt = null
		if yes:
			_ask({"op": "attributes", "slot": _hero, "values": Attributes.empty()})
			Sfx.play("menu_confirm")
		_redraw())


## Makes a change: here, or (online client) by asking the host.
func _ask(op: Dictionary) -> void:
	if remote:
		op_requested.emit(op)
	else:
		_run.apply_op(op)


# --- drawing ----------------------------------------------------------------------------------

func _redraw() -> void:
	var c := _run.data.party[_hero]
	_name.text = c.display_name
	_name.label_settings.font_color = c.color.lightened(0.25)
	if _run.is_max_level(_hero):
		_level.text = "Level %d (max)" % _run.levels[_hero]
	else:
		_level.text = "Level %d    XP %d / %d" % [_run.levels[_hero], _run.xps[_hero], _run.xp_to_next(_hero)]
	var free := _run.free_points(_hero)
	_points.text = "Points to spend: %d" % free
	_points.label_settings.font_color = HudStyle.GOLD if free > 0 else HudStyle.TEXT_DIM
	var values: Array[String] = [
		"%d HP" % _run.max_hp(_hero),
		"%d" % _run.power(_hero),
		"%d" % _run.speed(_hero),
		"%d%% less hurt" % _run.defense_percent(_hero),
		"%d%%" % _run.crit_percent(_hero),
	]
	for kind: int in _rows.size():
		var row: Dictionary = _rows[kind]
		(row.panel as PanelContainer).add_theme_stylebox_override("panel", ListMenu.row_style(kind == _row))
		(row.points as Label).text = str(_run.attribute(_hero, kind))
		(row.value as Label).text = values[kind]
	_info.text = "Each level up gives %d points. Resetting is free." % _run.tuning.attr_points_per_level
	var entries: Array = [[&"@updown", "Attribute"], [&"menu_right", "Add"], [&"menu_left", "Take back"],
			[&"item_move", "Reset"]]
	if _run.party_size() > 1:
		entries.append([&"item_turn_left", "Hero"])
		entries.append([&"item_turn_right", "Hero"])
	entries.append([&"menu_cancel", "Done"])
	_hint.set_entries(entries)


func _handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, true, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)
