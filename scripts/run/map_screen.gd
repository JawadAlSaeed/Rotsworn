class_name MapScreen
extends CanvasLayer
## The run map (DESIGN.md 8): every stop from the bottom row to the final fight at the top, the
## paths between them, where the party has been and where it can go next. Left/right picks one of
## the next stops, confirm goes there, cancel asks to quit the run.

signal stop_chosen(id: int)
signal quit_requested

const TITLE_SIZE: int = 48
const DETAIL_SIZE: int = 28
const HINT_SIZE: int = 24
const STOP_LABEL_SIZE: int = 22
const ICON_SIZE: int = 30
## Space between the gold and HP strip and the top stop.
const TOP_GAP: float = 28.0
const BOTTOM_GAP: float = 175.0
const COLUMN_GAP: float = 330.0
const STOP_RADIUS: float = 32.0
const PATH_WIDTH: float = 4.0
const PULSE_HZ: float = 1.6
const TYPE_COLORS: Array[Color] = [Color(0.36, 0.62, 0.36), Color(0.36, 0.56, 0.9), Color(0.95, 0.75, 0.25),
		Color(0.85, 0.27, 0.22)]
const TYPE_ICONS: Array[String] = ["Z", "R", "$", "!"]
const PATH_DIM := Color(0.3, 0.3, 0.34)
const PATH_NEXT := Color(0.85, 0.85, 0.85)
const PAST_DIM: float = 0.55

var _run: RunState
var _canvas: Control
var _detail: Label
var _bar: RunPartyBar
var _choices: Array[int] = []
var _sel: int = 0
var _time: float = 0.0
## Stop id -> centre on screen (filled when drawn).
var _centres: Dictionary = {}


func setup(run: RunState) -> void:
	_run = run
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.06)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)

	var top := VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 20.0
	top.add_theme_constant_override("separation", 10)
	add_child(top)
	top.add_child(ListMenu.centred_label(run.data.display_name, TITLE_SIZE, HudStyle.GOLD))
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(centre)
	_bar = RunPartyBar.new()
	centre.add_child(_bar)
	_bar.setup(run)

	var bottom := VBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -24.0
	bottom.add_theme_constant_override("separation", 8)
	add_child(bottom)
	_detail = ListMenu.centred_label("", DETAIL_SIZE)
	bottom.add_child(_detail)
	bottom.add_child(ListMenu.centred_label("Left/Right choose   %s go   %s quit the run" % [
			HudStyle.binding_text(&"menu_confirm"), HudStyle.binding_text(&"menu_cancel")], HINT_SIZE, HudStyle.TEXT_DIM))

	_choices = run.choices()
	_choices.sort_custom(func(a: int, b: int) -> bool: return int(run.map.stop(a).col) < int(run.map.stop(b).col))
	_sel = 0
	_update_detail()


## The stops that can be chosen now, left to right (the bot reads them).
func choices() -> Array[int]:
	return _choices


## Goes to stop `id` (the bot calls this; the player uses confirm).
func choose(id: int) -> void:
	if _choices.has(id):
		Sfx.play("menu_confirm")
		stop_chosen.emit(id)


func _process(delta: float) -> void:
	_time += delta
	_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var step := 0
	if _pressed(event, &"menu_left") or _pressed(event, &"menu_up"):
		step = -1
	elif _pressed(event, &"menu_right") or _pressed(event, &"menu_down"):
		step = 1
	elif _pressed(event, &"menu_confirm"):
		get_viewport().set_input_as_handled()
		if not _choices.is_empty():
			choose(_choices[_sel])
		return
	elif _pressed(event, &"menu_cancel"):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_cancel")
		quit_requested.emit()
		return
	else:
		return
	get_viewport().set_input_as_handled()
	if _choices.size() > 1:
		_sel = wrapi(_sel + step, 0, _choices.size())
		Sfx.play("menu_move")
		_update_detail()


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)


## What the chosen stop is, in words.
static func describe(run: RunState, stop: Dictionary) -> String:
	match int(stop.get("type", -1)):
		RunMap.StopType.ZONE:
			var zone := run.zone_of(stop)
			return "Zone: %s. Explore, then beat the guard at the exit. Other enemies are optional (more gold)." % (
					zone.display_name if zone != null else "?")
		RunMap.StopType.REST:
			return "Rest: everyone heals %d%% of their max HP." % run.tuning.run_rest_heal_percent
		RunMap.StopType.SHOP:
			return "Shop: spend gold on healing and tonics."
		RunMap.StopType.FINAL:
			return "The final fight. Win it to clear the run."
	return ""


static func stop_name(run: RunState, stop: Dictionary) -> String:
	match int(stop.get("type", -1)):
		RunMap.StopType.ZONE:
			var zone := run.zone_of(stop)
			return zone.display_name if zone != null else "Zone"
		RunMap.StopType.REST:
			return "Rest"
		RunMap.StopType.SHOP:
			return "Shop"
		RunMap.StopType.FINAL:
			return "Final fight"
	return ""


func _update_detail() -> void:
	_detail.text = describe(_run, _run.map.stop(_choices[_sel])) if not _choices.is_empty() else ""


# --- drawing ----------------------------------------------------------------------------------

func _draw_map() -> void:
	var size := _canvas.size
	var map := _run.map
	var rows := map.row_count()
	var bottom := size.y - BOTTOM_GAP - STOP_RADIUS
	var top := _bar.get_global_rect().end.y + TOP_GAP + STOP_RADIUS * 1.25
	var row_h := (bottom - top) / float(maxi(1, rows - 1))
	_centres.clear()
	for s: Dictionary in map.stops:
		var x := size.x * 0.5 + (float(s.col) - float(int(s.width) - 1) * 0.5) * COLUMN_GAP
		_centres[int(s.id)] = Vector2(x, bottom - float(s.row) * row_h)
	var on_path := {}
	for i: int in _run.path.size() - 1:
		on_path[Vector2i(_run.path[i], _run.path[i + 1])] = true
	for s: Dictionary in map.stops:
		for n: int in s.next:
			var from: Vector2 = _centres[int(s.id)]
			var to: Vector2 = _centres[n]
			var color := PATH_DIM
			var width := PATH_WIDTH
			if on_path.has(Vector2i(int(s.id), n)):
				color = HudStyle.GOLD
				width = PATH_WIDTH * 1.5
			elif int(s.id) == _run.at and _choices.has(n):
				color = PATH_NEXT
			_canvas.draw_line(from, to, color, width, true)
	if _run.at < 0:
		# Before the first stop: short lines from the start to each first-row stop.
		var start := Vector2(size.x * 0.5, bottom + STOP_RADIUS * 2.2)
		for id: int in _choices:
			_canvas.draw_line(start, _centres[id], PATH_NEXT, PATH_WIDTH, true)
		_canvas.draw_circle(start, STOP_RADIUS * 0.3, HudStyle.GOLD)
	var font := ThemeDB.fallback_font
	var pulse := 0.5 + 0.5 * sin(_time * TAU * PULSE_HZ)
	for s: Dictionary in map.stops:
		var id := int(s.id)
		var c: Vector2 = _centres[id]
		var type := int(s.type)
		var color := TYPE_COLORS[type]
		var visited := _run.path.has(id)
		var choice := _choices.has(id)
		if not visited and not choice and int(s.row) <= _row_of(_run.at):
			color = color.darkened(PAST_DIM)
		var radius := STOP_RADIUS * (1.25 if type == RunMap.StopType.FINAL else 1.0)
		_canvas.draw_circle(c, radius, color.darkened(0.35) if not choice else color)
		var ring := HudStyle.PANEL_BORDER
		var ring_width := 3.0
		if id == _run.at:
			ring = HudStyle.GOLD
			ring_width = 5.0
		elif visited:
			ring = HudStyle.GOLD.darkened(0.3)
		elif choice:
			ring = HudStyle.TEXT
			if id == _choices[_sel]:
				ring = HudStyle.GOLD
				ring_width = 5.0 + 3.0 * pulse
		_canvas.draw_arc(c, radius + 2.0, 0.0, TAU, 48, ring, ring_width, true)
		_text(font, TYPE_ICONS[type], c + Vector2(0.0, ICON_SIZE * 0.35), ICON_SIZE, HudStyle.TEXT, true)
		var label_color := HudStyle.TEXT if choice or id == _run.at else HudStyle.TEXT_DIM
		_text(font, stop_name(_run, s), c + Vector2(radius + 12.0, STOP_LABEL_SIZE * 0.35), STOP_LABEL_SIZE, label_color, false)


func _row_of(id: int) -> int:
	return int(_run.map.stop(id).get("row", -1))


func _text(font: Font, text: String, at: Vector2, size: int, color: Color, centred: bool) -> void:
	var pos := at
	if centred:
		pos.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	_canvas.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, HudStyle.OUTLINE_COLOR)
	_canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
