class_name MapScreen
extends CanvasLayer
## The run map (DESIGN.md 8, card #111): a tall old paper map held open between two rolled ends,
## scrolled up and down like Slay the Spire's. Every stop is painted on it from the bottom row to
## the boss's lair at the top, with ink paths between them, the walked path in red and the
## party's flag where the party is. Left/right picks one of the next stops (the map scrolls to
## it), up/down or the mouse wheel scroll, confirm goes there, cancel opens the pause menu,
## party_menu the party screen. Confirm, cancel or party_menu pressed while the map opens only
## finishes the opening.

signal stop_chosen(id: int)
## Back (B): Main opens the pause menu (Esc / Menu reach Main directly).
signal quit_requested
signal party_requested

const TITLE_SIZE: int = 48
const DETAIL_SIZE: int = 28
## How far (art pixels) an ink path stays clear of a stop's centre, so the dots end at the picture.
const STOP_CLEAR: float = 14.0
const START_CLEAR: float = 6.0
## Half the start cross (art pixels).
const START_MARK: int = 3
## How far past a stop's picture the pointer still counts as on it (screen pixels).
const STOP_POINT_SLACK: int = 12

var _run: RunState
var _look: MapVisuals
## Clips the paper to the open part between the rollers; _canvas inside draws the paper and ink,
## _frame on top draws the rollers.
var _view: Control
var _canvas: Control
var _frame: Control
var _detail: Label
var _bar: RunPartyBar
var _choices: Array[int] = []
var _sel: int = 0
## Milliseconds since the map opened; it is opening while this is below _intro_ms().
var _time_ms: float = 0.0
var _paper: Texture2D
var _roller: Texture2D
var _flag: Texture2D
var _ring: Texture2D
var _ring_big: Texture2D
var _font: Font
## Stop id -> its picture, and its centre in art pixels from the paper's top-left.
var _icons: Dictionary = {}
var _centres: Dictionary = {}
var _start: Vector2i
## Art pixels from the paper's top to the top of the part on screen, and where it is heading.
var _scroll: float = 0.0
var _target: float = 0.0
## The map keeps the picked stop in the middle until the player scrolls by hand.
var _follow_focus: bool = true
## At a run's start the map opens on the boss's lair and pans down to the start (-1: no pan).
var _pan_from: float = -1.0
## Which row the ink soaks into first (rows further from it follow).
var _ink_row: int = 0
## The part of the paper on screen: art pixels tall, and its top on screen (set every frame).
var _window_h: int = 0
var _window_top: float = 0.0
## Stops the picked choice can lead to (planning, card #162): id -> true.
var _ahead: Dictionary = {}


## `unroll` false shows the map already open (back from the party screen, or redrawn online).
func setup(run: RunState, look: MapVisuals = null, unroll: bool = true) -> void:
	_run = run
	_look = look if look != null else MapVisuals.new()
	_paper = AssetLoader.texture(_look.paper_path, Vector2i(440, 520))
	_roller = AssetLoader.texture(_look.roller_path, Vector2i(450, 16))
	_flag = AssetLoader.texture(_look.flag_path, Vector2i(14, 22))
	_ring = AssetLoader.texture(_look.ring_path, Vector2i(30, 30))
	_ring_big = AssetLoader.texture(_look.ring_big_path, Vector2i(40, 40))
	_font = HudStyle.title_font()
	_layout()
	add_child(MenuBackdrop.new())
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.clip_contents = true
	add_child(_view)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_map)
	_view.add_child(_canvas)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.draw.connect(_draw_rollers)
	add_child(_frame)

	var top := VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 20.0
	top.add_theme_constant_override("separation", 10)
	add_child(top)
	var title := run.data.display_name
	if run.acts().size() > 1:
		title = "Act %d: %s" % [run.act + 1, run.act_data().display_name]
	if run.oath > 0:
		title += "   |   Oath %d" % run.oath
	top.add_child(ListMenu.centred_title(title, TITLE_SIZE))
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
	bottom.offset_bottom = -ListMenu.FOOTER_STRIP_PX - 12.0
	bottom.add_theme_constant_override("separation", 8)
	add_child(bottom)
	_detail = ListMenu.centred_label("", DETAIL_SIZE)
	bottom.add_child(_detail)
	ListMenu.screen_footer(self, [[&"@leftright", "Choose"], [&"@updown", "Scroll"], [&"menu_confirm", "Go"],
			[&"party_menu", "Party"], [&"pause", "Pause"]])

	add_child(_legend())
	_choices = run.choices()
	_choices.sort_custom(func(a: int, b: int) -> bool: return int(run.map.stop(a).col) < int(run.map.stop(b).col))
	_sel = 0
	_update_detail()
	_ink_row = _focus_row()
	if unroll and run.at < 0:
		_pan_from = 0.0
		_ink_row = run.map.row_count() - 1
	if not unroll:
		_time_ms = _intro_ms()
	_scroll = -1.0  # placed on the first frame, once the window's size is known


## The stops that can be chosen now, left to right (the bot reads them).
func choices() -> Array[int]:
	return _choices


## Goes to stop `id` (the bot calls this; the player uses confirm).
func choose(id: int) -> void:
	if _choices.has(id):
		Sfx.play("menu_confirm")
		stop_chosen.emit(id)


## True while the paper unrolls, the ink soaks in and (at a run's start) the map pans down.
func is_unrolling() -> bool:
	return _time_ms < _intro_ms()


func _process(delta: float) -> void:
	_time_ms += delta * 1000.0
	_place_window()
	if _follow_focus:
		_target = _focus_scroll()
	if _scroll < 0.0 and _window_h > 0:
		_scroll = _pan_from if _pan_from >= 0.0 and is_unrolling() else _target
	if is_unrolling():
		var pan_start := _pan_start_ms()
		if _pan_from >= 0.0 and _time_ms >= pan_start:
			var t := clampf((_time_ms - pan_start) / float(maxi(1, _look.start_pan_ms)), 0.0, 1.0)
			_scroll = lerpf(_pan_from, _target, smoothstep(0.0, 1.0, t))
	else:
		var axis := Input.get_axis(&"menu_up", &"menu_down")
		if absf(axis) > 0.2:
			_follow_focus = false
			_target = _clamp_scroll(_target + axis * float(_look.scroll_speed) * delta)
		var follow := 1.0 - exp(-delta * 1000.0 / float(maxi(1, _look.scroll_follow_ms)))
		_scroll = lerpf(_scroll, _target, follow)
	_canvas.queue_redraw()
	_frame.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if is_unrolling():
		for action: StringName in [&"menu_confirm", &"menu_cancel", &"party_menu"]:
			if _pressed(event, action):
				get_viewport().set_input_as_handled()
				_time_ms = _intro_ms()
				_scroll = _target
				return
	if event is InputEventMouse and not is_unrolling() and _mouse_input(event):
		return
	if event is InputEventMouseButton and event.pressed and not is_unrolling():
		var wheel := 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel = -1.0
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel = 1.0
		if wheel != 0.0:
			get_viewport().set_input_as_handled()
			_follow_focus = false
			_target = _clamp_scroll(_target + wheel * float(_look.wheel_step))
		return
	var step := 0
	if _pressed(event, &"menu_left"):
		step = -1
	elif _pressed(event, &"menu_right"):
		step = 1
	elif _pressed(event, &"menu_up") or _pressed(event, &"menu_down"):
		get_viewport().set_input_as_handled()  # held up/down scroll in _process
		return
	elif _pressed(event, &"menu_confirm"):
		get_viewport().set_input_as_handled()
		if not _choices.is_empty():
			choose(_choices[_sel])
		return
	elif _pressed(event, &"party_menu"):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_confirm")
		party_requested.emit()
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
	_follow_focus = true


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)


## The mouse (card #202): pointing at one of the next stops picks it (the map does not scroll
## under the pointer), a left click goes there, a right click or the back button opens the pause
## menu. The wheel scrolls (below). True when the event was used.
func _mouse_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var hovered := _choice_at((event as InputEventMouse).position)
		if hovered >= 0 and hovered != _sel:
			_sel = hovered
			_follow_focus = false
			Sfx.play("menu_move")
			_update_detail()
			get_viewport().set_input_as_handled()
			return true
	elif MenuMouse.is_click(event):
		var clicked := _choice_at((event as InputEventMouse).position)
		if clicked >= 0:
			get_viewport().set_input_as_handled()
			choose(_choices[clicked])
			return true
	elif MenuMouse.is_back(event):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_cancel")
		quit_requested.emit()
		return true
	return false


## The next stop (index into the choices) whose picture is under the viewport `point`, -1 for none.
## Stops scrolled out of the open part of the paper cannot be pointed at.
func _choice_at(point: Vector2) -> int:
	if _choices.is_empty() or MenuMouse.control_at([_view], point) < 0:
		return -1
	var origin := _origin()
	var to_screen := _canvas.get_global_transform_with_canvas()
	var centres: Array[Vector2] = []
	var radius := 0.0
	for id: int in _choices:
		var icon: Texture2D = _icons[id]
		radius = maxf(radius, maxf(icon.get_size().x, icon.get_size().y) * 0.5 * float(_look.pixel_scale))
		centres.append(to_screen * _at(origin, Vector2(_centres[id])))
	return MenuMouse.nearest_within(centres, point, radius + float(STOP_POINT_SLACK))


## What the chosen stop is, in words.
static func describe(run: RunState, stop: Dictionary) -> String:
	match int(stop.get("type", -1)):
		RunMap.StopType.ZONE:
			var zone := run.zone_of(stop)
			return "Zone: %s. Explore, then beat the guard at the exit. Other enemies are optional (more gold)." % (
					zone.display_name if zone != null else "?")
		RunMap.StopType.REST:
			return "Campfire: pick one: rest (heal %d%%), train (attribute points) or upgrade an item." % run.rest_heal_percent()
		RunMap.StopType.SHOP:
			return "Shop: items, charms and gear; healing, upgrades; sell what you do not need."
		RunMap.StopType.FINAL:
			if not run.is_last_act():
				return "The boss of this act. Win to go on to the next act."
			return "The final fight. Win it to clear the run."
		RunMap.StopType.ELITE:
			return "Elite fight: a much tougher fight. Better spoils: rare gear and more gold."
		RunMap.StopType.EVENT:
			return "Something strange: a choice to make, a risk or a reward."
		RunMap.StopType.TREASURE:
			return "Treasure: a chest with something rare inside, and gold."
	return ""


static func stop_name(run: RunState, stop: Dictionary) -> String:
	match int(stop.get("type", -1)):
		RunMap.StopType.ZONE:
			var zone := run.zone_of(stop)
			return zone.display_name if zone != null else "Zone"
		RunMap.StopType.REST:
			return "Campfire"
		RunMap.StopType.SHOP:
			return "Shop"
		RunMap.StopType.FINAL:
			return "Boss" if not run.is_last_act() else "Final fight"
		RunMap.StopType.ELITE:
			return "Crowned elite" if bool(stop.get("crown", false)) else "Elite"
		RunMap.StopType.EVENT:
			return "?"
		RunMap.StopType.TREASURE:
			return "Treasure"
	return ""


func _update_detail() -> void:
	_detail.text = describe(_run, _run.map.stop(_choices[_sel])) if not _choices.is_empty() else ""
	_ahead = reachable_from(_run.map, _choices[_sel]) if not _choices.is_empty() else {}


## Every stop `from_id` can lead to, itself included (id -> true).
static func reachable_from(map: RunMap, from_id: int) -> Dictionary:
	var found := {}
	var todo: Array[int] = [from_id]
	while not todo.is_empty():
		var id: int = todo.pop_back()
		if found.has(id):
			continue
		found[id] = true
		todo.append_array(map.stop(id).get("next", []))
	return found


## The legend: every kind of stop's picture and name, down the left side.
func _legend() -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	box.offset_left = 40.0
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 8)
	var zone_icon := ""
	if not _run.act_data().zones.is_empty():
		zone_icon = _run.act_data().zones[0].map_icon_path
	for entry: Array in [[zone_icon, "Zone"], [_look.elite_icon_path, "Elite"], [_look.event_icon_path, "Event"],
			[_look.treasure_icon_path, "Treasure"], [_look.shop_icon_path, "Shop"], [_look.rest_icon_path, "Campfire"],
			[_run.act_data().final_map_icon_path, "Boss"]]:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		var icon := TextureRect.new()
		icon.texture = AssetLoader.texture(String(entry[0]), Vector2i(24, 24))
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(48.0, 48.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var label := HudStyle.make_label(String(entry[1]), _look.legend_size, HudStyle.TEXT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		box.add_child(row)
	return box


# --- timing -----------------------------------------------------------------------------------

func _intro_ms() -> float:
	var pan := float(_look.start_pan_ms) if _pan_from >= 0.0 else 0.0
	return _pan_start_ms() + pan + float(_look.flag_drop_ms)


## The ink soaks in from _ink_row outward, one row every row_stagger_ms.
func _row_start_ms(row: int) -> float:
	return float(_look.unroll_ms + absi(row - _ink_row) * _look.row_stagger_ms)


## When the last row's ink is in (and the pan down, if any, starts).
func _pan_start_ms() -> float:
	var furthest := maxi(absi(-1 - _ink_row), absi(_run.map.row_count() - 1 - _ink_row))
	return float(_look.unroll_ms + furthest * _look.row_stagger_ms + _look.ink_ms)


## How much of row `row` (-1: the start mark) has soaked in (0 to 1).
func _row_ink(row: int) -> float:
	return clampf((_time_ms - _row_start_ms(row)) / float(maxi(1, _look.ink_ms)), 0.0, 1.0)


# --- layout and scrolling ---------------------------------------------------------------------

## Where every stop sits on the paper (art pixels): rows evenly from the bottom margin up to the
## top margin, each row's stops centred column_gap apart.
func _layout() -> void:
	var map := _run.map
	var rows := map.row_count()
	var paper := Vector2i(_paper.get_size())
	var bottom := paper.y - _look.bottom_margin
	var row_h := float(bottom - _look.top_margin) / float(maxi(1, rows - 1))
	for s: Dictionary in map.stops:
		var x := float(paper.x) * 0.5 + (float(s.col) - float(int(s.width) - 1) * 0.5) * float(_look.column_gap)
		_centres[int(s.id)] = Vector2i(roundi(x), roundi(float(bottom) - float(s.row) * row_h))
		_icons[int(s.id)] = _icon_for(s)
	@warning_ignore("integer_division")
	_start = Vector2i(paper.x / 2, bottom + _look.start_gap)


func _icon_for(stop: Dictionary) -> Texture2D:
	var path := ""
	match int(stop.get("type", -1)):
		RunMap.StopType.ZONE:
			var zone := _run.zone_of(stop)
			path = zone.map_icon_path if zone != null else ""
		RunMap.StopType.REST:
			path = _look.rest_icon_path
		RunMap.StopType.SHOP:
			path = _look.shop_icon_path
		RunMap.StopType.FINAL:
			path = _run.act_data().final_map_icon_path
		RunMap.StopType.ELITE:
			path = _look.elite_icon_path
		RunMap.StopType.EVENT:
			path = _look.event_icon_path
		RunMap.StopType.TREASURE:
			path = _look.treasure_icon_path
	return AssetLoader.texture(path, Vector2i(24, 24))


## The window between the gold and HP strip and the line of text under the map, and the open
## part of it (all of it once the paper has unrolled, which it does from the middle).
func _place_window() -> void:
	var px := float(_look.pixel_scale)
	var top := _bar.get_global_rect().end.y + float(_look.paper_top_gap)
	var bottom := _detail.get_global_rect().position.y - float(_look.paper_bottom_gap)
	_window_h = mini(int(_paper.get_size().y), maxi(0, int((bottom - top) / px)))
	_window_top = floorf(top)
	var open := clampf(_time_ms / float(maxi(1, _look.unroll_ms)), 0.0, 1.0)
	open = 1.0 - pow(1.0 - open, 3.0)
	@warning_ignore("integer_division")
	var half := int(floorf(float(_window_h / 2) * open))
	@warning_ignore("integer_division")
	var mid := _window_h / 2
	var paper_w := _paper.get_size().x * px
	_view.position = Vector2(floorf((_frame.size.x - paper_w) * 0.5), _window_top + float(mid - half) * px)
	_view.size = Vector2(paper_w, float(half * 2) * px)


func _clamp_scroll(value: float) -> float:
	return clampf(value, 0.0, maxf(0.0, _paper.get_size().y - float(_window_h)))


## The row the map centres on: the picked next stop's, else where the party is.
func _focus_row() -> int:
	if not _choices.is_empty():
		return _row_of(_choices[_sel])
	return maxi(0, _row_of(_run.at))


## The scroll that puts the picked next stop (else the party's stop) in the middle of the window.
func _focus_scroll() -> float:
	var y := float(_start.y)
	if not _choices.is_empty():
		y = float(_centres[_choices[_sel]].y)
	elif _run.at >= 0:
		y = float(_centres[_run.at].y)
	return _clamp_scroll(roundf(y - float(_window_h) * 0.5))


# --- drawing ----------------------------------------------------------------------------------

## The paper's top-left in _canvas's own coordinates (it scrolls; the window clips it).
func _origin() -> Vector2:
	var px := float(_look.pixel_scale)
	return Vector2(0.0, _window_top - roundf(maxf(_scroll, 0.0)) * px - _view.position.y)


## Art pixel -> _canvas coordinates.
func _at(origin: Vector2, art: Vector2) -> Vector2:
	return origin + art.floor() * float(_look.pixel_scale)


func _draw_map() -> void:
	var origin := _origin()
	_canvas.draw_texture_rect(_paper, Rect2(origin, _paper.get_size() * float(_look.pixel_scale)), false)
	_draw_routes(origin)
	_draw_stops(origin)
	_draw_flag(origin)


## A rolled end lying across the top and the bottom of the open part.
func _draw_rollers() -> void:
	var px := float(_look.pixel_scale)
	var size := _roller.get_size() * px
	var x := floorf((_frame.size.x - size.x) * 0.5)
	for y: float in [_view.position.y, _view.position.y + _view.size.y]:
		_frame.draw_texture_rect(_roller, Rect2(Vector2(x, y - floorf(_roller.get_size().y * 0.5) * px), size), false)


func _draw_routes(origin: Vector2) -> void:
	var map := _run.map
	var here := _row_of(_run.at)
	var walked := {}
	for i: int in _run.path.size() - 1:
		walked[Vector2i(_run.path[i], _run.path[i + 1])] = true
	for s: Dictionary in map.stops:
		var from_id := int(s.id)
		for n: int in s.next:
			var color := _look.ink_color
			var size := 1
			if walked.has(Vector2i(from_id, n)):
				color = _look.walked_color
				size = _look.walked_dot_size
			elif from_id == _run.at and _choices.has(n):
				pass
			elif int(s.row) <= here:
				color.a = _look.faded_alpha
			else:
				color.a = _look.route_alpha
				if not _ahead.is_empty() and not (_ahead.has(from_id) and _ahead.has(n)):
					color.a *= _look.unreachable_alpha
			color.a *= minf(_row_ink(int(s.row)), _row_ink(int(map.stop(n).row)))
			_dots(origin, _centres[from_id], _centres[n], STOP_CLEAR, STOP_CLEAR, color, size)
	# The start mark (a small ink cross) and the routes from it.
	var mark := _look.ink_color
	mark.a *= _row_ink(-1)
	for d: int in range(-START_MARK, START_MARK + 1):
		_dot(origin, Vector2(_start) + Vector2(d, d), mark, 1)
		_dot(origin, Vector2(_start) + Vector2(d, -d), mark, 1)
	if _run.at < 0:
		var next := _look.ink_color
		next.a *= minf(_row_ink(-1), _row_ink(0))
		for id: int in _choices:
			_dots(origin, _start, _centres[id], START_CLEAR, STOP_CLEAR, next, 1)
	elif not _run.path.is_empty():
		var walked_ink := _look.walked_color
		walked_ink.a *= minf(_row_ink(-1), _row_ink(0))
		_dots(origin, _start, _centres[_run.path[0]], START_CLEAR, STOP_CLEAR, walked_ink, _look.walked_dot_size)


## Ink dots from `a` to `b` (art pixels), leaving `clear_a` and `clear_b` free at the ends.
func _dots(origin: Vector2, a: Vector2i, b: Vector2i, clear_a: float, clear_b: float, color: Color,
		size: int) -> void:
	if color.a <= 0.0:
		return
	var dir := Vector2(b - a)
	var length := dir.length()
	if length <= clear_a + clear_b:
		return
	dir /= length
	var d := clear_a
	while d <= length - clear_b:
		_dot(origin, Vector2(a) + dir * d, color, size)
		d += float(_look.dot_spacing)


func _dot(origin: Vector2, art: Vector2, color: Color, size: int) -> void:
	var corner := (art - Vector2(size - 1, size - 1) * 0.5).round()
	_canvas.draw_rect(Rect2(_at(origin, corner), Vector2(size, size) * float(_look.pixel_scale)), color)


func _draw_stops(origin: Vector2) -> void:
	var px := float(_look.pixel_scale)
	var here := _row_of(_run.at)
	var pulse := 0.5 + 0.5 * sin(_time_ms * 0.001 * TAU * _look.pulse_hz)
	for s: Dictionary in _run.map.stops:
		var id := int(s.id)
		var ink := _row_ink(int(s.row))
		if ink <= 0.0:
			continue
		var centre := Vector2(_centres[id])
		var choice := _choices.has(id)
		var alpha := ink
		if not _run.path.has(id) and not choice and int(s.row) <= here:
			alpha *= _look.faded_alpha
		elif int(s.row) > here and not _ahead.is_empty() and not _ahead.has(id):
			alpha *= _look.unreachable_alpha
		var icon: Texture2D = _icons[id]
		var size := icon.get_size()
		_canvas.draw_texture_rect(icon, Rect2(_at(origin, centre - (size * 0.5).floor()), size * px), false,
				Color(1.0, 1.0, 1.0, alpha))
		if bool(s.get("crown", false)):
			_draw_crown(_at(origin, centre - Vector2(0.0, floorf(size.y * 0.5) + 3.0)), px, alpha)
		if choice and id == _choices[_sel]:
			var ring := _ring_big if int(s.type) == RunMap.StopType.FINAL else _ring
			var ring_size := ring.get_size()
			_canvas.draw_texture_rect(ring, Rect2(_at(origin, centre - (ring_size * 0.5).floor()), ring_size * px),
					false, Color(1.0, 1.0, 1.0, ink * (0.6 + 0.4 * pulse)))
		var label := _look.ink_color
		label.a = alpha if (choice or id == _run.at) else alpha * _look.route_alpha
		var at := _at(origin, centre + Vector2(floorf(size.x * 0.5) + float(_look.label_gap), 0.0))
		at.y += float(_look.label_size) * 0.35
		_canvas.draw_string(_font, at, stop_name(_run, s), HORIZONTAL_ALIGNMENT_LEFT, -1, _look.label_size, label)


## The rot crown over the crowned elite (card #286): a small gold crown, three points, in ink.
func _draw_crown(bottom_centre: Vector2, px: float, alpha: float) -> void:
	var w := 9.0 * px
	var h := 5.0 * px
	var left := bottom_centre.x - w * 0.5
	var points := PackedVector2Array([
		Vector2(left, bottom_centre.y), Vector2(left, bottom_centre.y - h),
		Vector2(left + w * 0.25, bottom_centre.y - h * 0.45), Vector2(left + w * 0.5, bottom_centre.y - h),
		Vector2(left + w * 0.75, bottom_centre.y - h * 0.45), Vector2(left + w, bottom_centre.y - h),
		Vector2(left + w, bottom_centre.y)])
	_canvas.draw_colored_polygon(points, Color(_look.crown_color, alpha))
	var outline := points.duplicate()
	outline.append(points[0])
	_canvas.draw_polyline(outline, Color(_look.ink_color, alpha), maxf(1.0, px * 0.5))


## The party's flag, dropping onto its spot once the ink is in (and the map has panned down).
func _draw_flag(origin: Vector2) -> void:
	var drop_start := _intro_ms() - float(_look.flag_drop_ms)
	var t := clampf((_time_ms - drop_start) / float(maxi(1, _look.flag_drop_ms)), 0.0, 1.0)
	if t <= 0.0:
		return
	var corner := Vector2(_start + _look.flag_start_offset)
	if _run.at >= 0:
		corner = Vector2(_centres[_run.at] + _look.flag_offset)
	corner.y -= roundf(float(_look.flag_drop_height) * (1.0 - t * t))
	_canvas.draw_texture_rect(_flag, Rect2(_at(origin, corner), _flag.get_size() * float(_look.pixel_scale)), false,
			Color(1.0, 1.0, 1.0, t))


func _row_of(id: int) -> int:
	return int(_run.map.stop(id).get("row", -1))
