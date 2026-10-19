class_name HeroTab
extends PartyTab
## The Y screen's Hero tab (DESIGN.md 8.18): one hero's level, attribute points and combat stats,
## like Expedition 33's character page, and a small door to their Echoes. It replaces the old
## Attributes page (AttributesScreen, DESIGN.md 8.2) and keeps its rules: up / down picks an
## attribute, right or Confirm adds a point, left takes one back, X / R takes every point back (a
## free reset, asked first), and every change counts at once. The HP a hero is missing stays the
## same, so a reset never heals, and a hero too wounded to lose that max HP cannot take the points
## back (card #175).
## Left: the heroes' faces with their HP, a gold badge where points wait; LT / RT or a click changes
## hero. Centre: name, level, XP, the points to spend, the five attribute rows and, as a sixth
## cursor stop, the Echo box (Confirm there asks the screen to open the Echoes page). Right: the
## combat stats and the attribute radar. Online, changes go to the host as "attributes" ops.

## Confirm (or a click) on the Echo box: the screen opens hero `hero`'s Echoes page over the tab.
## The tab never opens it itself, so phase 21 can reshape Echoes without touching this page.
signal echoes_requested(hero: int)

## The cursor stop after the five attribute rows: the Echo box.
const ECHO_ROW: int = Attributes.COUNT
## Cursor stops: the attribute rows, then the Echo box.
const STOPS: int = Attributes.COUNT + 1

## Each attribute's glyph, and the glyph of the stat it raises (Attributes.Kind order).
const ATTR_GLYPHS: Array[StringName] = [&"heart", &"sword", &"chevrons", &"shield", &"star"]
const STAT_GLYPHS: Array[StringName] = [&"heart", &"sword", &"bolt", &"shield", &"star"]
## One word per stat for the stat column (Attributes.STATS is the long form).
const STAT_WORDS: Array[String] = ["Health", "Power", "Speed", "Defense", "Crit"]
## Each attribute's colour; the stat it raises shares it, so the eye links the two.
const ATTR_COLORS: Array[Color] = [Color(0.95, 0.4, 0.38), Color(1.0, 0.6, 0.3), Color(0.55, 0.92, 0.5),
		Color(0.5, 0.72, 1.0), Color(1.0, 0.85, 0.35)]
const ECHO_COLOR := Color(0.78, 0.55, 1.0)
## Pips for the points a worn Relic's stat line adds (not spent, not refundable).
const RELIC_PIP_COLOR := Color(0.62, 0.5, 0.95)
const CURSOR_BG := Color(0.3, 0.24, 0.1, 0.9)
const XP_COLOR := HudStyle.AP_TEXT
const FACE_BG := Color(0.0, 0.0, 0.0, 0.45)
## Faces of the heroes not shown are drawn this dim.
const FACE_DIM := Color(0.62, 0.62, 0.66)
## The rail's HP bar turns red at or under this share of max HP (as the run's party bar does).
const LOW_HP_PERCENT: int = 30

# Layout on the 1920 x 750 page.
const RAIL_X: float = 40.0
const RAIL_WIDTH: float = 210.0
const RAIL_TOP: float = 24.0
const FACE_PX: float = 96.0
const FACE_PAD: int = 3
const FACE_GAP: float = 30.0
const RAIL_BAR_GAP: float = 8.0
const RAIL_BAR_HEIGHT: float = 8.0
const FACE_BOX_HEIGHT: float = FACE_PX + 2.0 * FACE_PAD + RAIL_BAR_GAP + RAIL_BAR_HEIGHT
const BADGE_GLYPH_PX: float = 20.0
const BADGE_SIZE: int = 22
## How far the badge reaches in over the face's right edge and up over its top.
const BADGE_INSET: float = 22.0
const BADGE_LIFT: float = 10.0

const CENTRE_X: float = 300.0
const CENTRE_WIDTH: float = 900.0
const NAME_Y: float = 6.0
const NAME_SIZE: int = 52
const LEVEL_Y: float = 90.0
const LEVEL_SIZE: int = 26
const XP_BAR_WIDTH: float = 320.0
const XP_BAR_HEIGHT: float = 12.0
const XP_TEXT_SIZE: int = 22
const POINTS_Y: float = 18.0
const POINTS_PX: float = 60.0
const POINTS_SIZE: int = 64
const ROWS_TOP: float = 150.0
const ROW_HEIGHT: float = 78.0
const ROW_GAP: float = 12.0
const ROW_PART_GAP: int = 16
const PLATE_PAD: int = 8
const ROW_GLYPH_PX: float = 44.0
const ROW_NAME_SIZE: int = 32
const ROW_NAME_WIDTH: float = 180.0
const ROW_POINTS_SIZE: int = 40
const ROW_POINTS_WIDTH: float = 60.0
const STAT_GLYPH_PX: float = 32.0
const STAT_SIZE: int = 36
const STAT_VALUE_WIDTH: float = 120.0
## Pips: one per point, in groups of PIP_GROUP; past PIP_MAX only the number counts.
const PIP_MAX: int = 25
const PIP_GROUP: int = 5
const PIP_WIDTH: float = 6.0
const PIP_HEIGHT: float = 22.0
const PIP_STEP: float = 9.0
const PIP_GROUP_GAP: float = 5.0
const PIPS_WIDTH: float = 252.0
const ECHO_GAP: float = 6.0
const ECHO_TOP: float = ROWS_TOP + Attributes.COUNT * (ROW_HEIGHT + ROW_GAP) + ECHO_GAP
const ECHO_HEIGHT: float = 84.0
const ECHO_GLYPH_PX: float = 44.0
const ECHO_NUMBER_SIZE: int = 40
const ECHO_TOTAL_SIZE: int = 30
const ECHO_ICON_PX: float = 36.0
## Worn Echo icons the box shows; more show as "+N".
const ECHO_ICONS_MAX: int = 14

const RIGHT_X: float = 1260.0
const RIGHT_WIDTH: float = 620.0
const STATS_TOP: float = 20.0
const STATS_HEIGHT: float = 320.0
const STAT_ROW_HEIGHT: float = 56.0
const STAT_ROW_GAP: int = 4
const STAT_ROW_GLYPH_PX: float = 34.0
const STAT_WORD_SIZE: int = 26
const STAT_ROW_SIZE: int = 40
const RADAR_PX: float = 380.0
const RADAR_TOP: float = 356.0
## The radar's tip is at least this many points, so a fresh hero's shape is not all tips.
const RADAR_MIN_TOP: int = 10

var _row: int = 0
## The last refusal (the strip's line until the next press).
var _warning: String = ""
## The frame the reset prompt was answered in.
var _answered_frame: int = -1
## The reset question while it is open (busy).
var _prompt: ConfirmPrompt
## One per hero: {box: Control (click area), frame: PanelContainer, bar: ProgressBar, badge: Control,
## number: Label}.
var _faces: Array[Dictionary] = []
var _name: Label
var _level: Label
var _xp_bar: ProgressBar
var _xp_text: Label
var _points_glyph: UiGlyph
var _points: Label
## One per attribute: {panel: PanelContainer, title: Label, points: Label, pips: Control, value: Label}.
var _rows: Array[Dictionary] = []
var _echo_box: PanelContainer
var _echo_free: Label
var _echo_total: Label
var _echo_icons: HBoxContainer
var _echo_more: Label
var _stat_values: Array[Label] = []
var _radar: AttributeRadar


func setup(p_run: RunState, p_remote: bool) -> void:
	super.setup(p_run, p_remote)
	hero = clampi(hero, 0, run.party_size() - 1)
	_build_rail()
	_build_head()
	for kind: int in Attributes.COUNT:
		_build_row(kind)
	_build_echo_box()
	_build_stats()
	_radar = AttributeRadar.new()
	_radar.position = Vector2(RIGHT_X + (RIGHT_WIDTH - RADAR_PX) * 0.5, RADAR_TOP)
	_radar.size = Vector2(RADAR_PX, RADAR_PX)
	add_child(_radar)
	_redraw()


func refresh() -> void:
	_redraw()


func shown() -> void:
	# A refusal belongs to the hero and moment it was made.
	_warning = ""
	_redraw()


func busy() -> bool:
	return _prompt != null


func handle_input(event: InputEvent) -> bool:
	if run == null:
		return false
	if _prompt != null:
		# The prompt hears input only through here (its own input is off), so it works however the
		# screen passes input on, and nothing reaches it twice.
		_prompt._unhandled_input(event)
		return true
	if Engine.get_process_frames() == _answered_frame and event.is_pressed():
		# A second press in the frame that answered the prompt (another pad) goes nowhere.
		return true
	var cleared := false
	if event.is_pressed() and not event.is_echo() and not _warning.is_empty():
		_warning = ""
		cleared = true
	var used := _use(event)
	if cleared:
		changed.emit()
	return used


func hints() -> Array:
	if _prompt != null:
		return [[&"@updown", ""], [&"menu_confirm", "Pick"], [&"menu_cancel", "Keep"]]
	var many := run != null and run.party_size() > 1
	var entries: Array = []
	if _row == ECHO_ROW:
		entries = [[&"@updown", ""], [&"menu_confirm", "Echoes"]]
	else:
		entries = [[&"@leftright", "Points"], [&"item_move", "Reset"]]
		if not many:
			entries.push_front([&"@updown", ""])
	if many:
		entries.append([&"party_attributes", ""])
		entries.append([&"party_skills", "Hero"])
	return entries


func info() -> Dictionary:
	if run == null:
		return {}
	if _row == ECHO_ROW:
		return _echo_info()
	var kind := _row
	var chips: Array = [[STAT_GLYPHS[kind], stat_text(kind), HudStyle.TEXT],
			[&"up", Attributes.per_point_text(kind, run.tuning), HudStyle.GOLD]]
	var extra := run.relic_stat(hero, kind)
	if extra != 0:
		chips.append([&"gem", "%+d Relics" % extra, RELIC_PIP_COLOR])
	var line := _warning if not _warning.is_empty() else "Raises %s. Resetting is free." % Attributes.STATS[kind]
	return {"icon": ATTR_GLYPHS[kind], "title": Attributes.NAMES[kind], "color": ATTR_COLORS[kind],
			"chips": chips, "line": line}


## Every attribute point waiting to be spent, over the whole party.
func badge() -> int:
	if run == null:
		return 0
	var sum := 0
	for slot: int in run.party_size():
		sum += maxi(0, run.free_points(slot))
	return sum


# --- public helpers (the screen and tests) ------------------------------------------------------

## Shows hero `i` (party slot, clamped).
func set_hero(i: int) -> void:
	hero = clampi(i, 0, run.party_size() - 1)
	_warning = ""
	_redraw()
	changed.emit()


## Puts the cursor on stop `r`: an attribute (Attributes.Kind) or ECHO_ROW.
func choose_row(r: int) -> void:
	_row = clampi(r, 0, ECHO_ROW)
	_redraw()
	changed.emit()


## The cursor's stop: an attribute (Attributes.Kind) or ECHO_ROW.
func row() -> int:
	return _row


## Adds (step > 0) or takes back (step < 0) one point in the attribute under the cursor. True if a
## point moved (online: if the host was asked).
func change(step: int) -> bool:
	return _change(step, true)


## The value the stat raised by attribute `kind` has now, as the old Attributes page showed it.
func stat_text(kind: int) -> String:
	match kind:
		Attributes.Kind.VITALITY:
			return str(run.max_hp(hero))
		Attributes.Kind.MIGHT:
			return str(run.power(hero))
		Attributes.Kind.AGILITY:
			return str(run.speed(hero))
		Attributes.Kind.DEFENSE:
			return "%d%%" % run.defense_percent(hero)
		Attributes.Kind.LUCK:
			return "%d%%" % run.crit_percent(hero)
	return ""


# --- input --------------------------------------------------------------------------------------

func _use(event: InputEvent) -> bool:
	if event is InputEventMouse:
		return _mouse_input(event as InputEventMouse)
	var loud := not event.is_echo()
	if _repeats(event, &"menu_up"):
		_move_row(-1)
	elif _repeats(event, &"menu_down"):
		_move_row(1)
	elif PartyTab.pressed(event, &"menu_confirm"):
		if _row == ECHO_ROW:
			_open_echoes()
		else:
			_change(1, true)
	elif _repeats(event, &"menu_right"):
		if _row == ECHO_ROW:
			return false
		_change(1, loud)
	elif _repeats(event, &"menu_left"):
		if _row == ECHO_ROW:
			return false
		_change(-1, loud)
	elif PartyTab.pressed(event, &"item_move"):
		_ask_reset()
	elif PartyTab.pressed(event, &"party_attributes") or PartyTab.pressed(event, &"party_skills"):
		if run.party_size() <= 1:
			return false
		Sfx.play("menu_move")
		set_hero(wrapi(hero + (-1 if event.is_action(&"party_attributes") else 1), 0, run.party_size()))
	else:
		return false
	return true


## The mouse: the wheel moves the cursor, pointing at a row or the Echo box picks it, a left click
## on a row adds a point, on the Echo box opens the Echoes, on a face shows that hero. True when used.
func _mouse_input(event: InputEventMouse) -> bool:
	if MenuMouse.is_press(event):
		var wheel := MenuMouse.wheel_step((event as InputEventMouseButton).button_index)
		if wheel != 0:
			_move_row(wheel)
			return true
	var boxes: Array = []
	for face: Dictionary in _faces:
		boxes.append(face.box)
	var face_at := MenuMouse.control_at(boxes, event.position)
	if face_at >= 0:
		if not MenuMouse.is_click(event):
			return false
		if face_at != hero:
			Sfx.play("menu_move")
			set_hero(face_at)
		return true
	var stops: Array = []
	for r: Dictionary in _rows:
		stops.append(r.panel)
	stops.append(_echo_box)
	var stop := MenuMouse.control_at(stops, event.position)
	if stop < 0:
		return false
	if event is InputEventMouseMotion:
		if stop != _row:
			Sfx.play("menu_move")
			choose_row(stop)
		return true
	if not MenuMouse.is_click(event):
		return false
	if stop != _row:
		choose_row(stop)
	if stop == ECHO_ROW:
		_open_echoes()
	else:
		_change(1, true)
	return true


func _move_row(step: int) -> void:
	Sfx.play("menu_move")
	choose_row(wrapi(_row + step, 0, STOPS))


func _open_echoes() -> void:
	Sfx.play("menu_confirm")
	echoes_requested.emit(hero)


## change() with a toast on refusal only when `loud` (a held key repeating stays quiet).
func _change(step: int, loud: bool) -> bool:
	step = signi(step)
	if step == 0 or _row >= Attributes.COUNT:
		return false
	var values: Array[int] = []
	values.assign(run.attributes[hero])
	if step > 0 and run.free_points(hero) <= 0:
		Sfx.play("locked")
		if loud:
			toast.emit("No points", &"up")
		return false
	if step < 0 and values[_row] <= 0:
		Sfx.play("locked")
		return false
	values[_row] += step
	if _too_wounded(values, loud):
		return false
	var ok := ask({"op": "attributes", "slot": hero, "values": values})
	if ok:
		Sfx.play("buff" if step > 0 else "menu_cancel")
	_redraw()
	return ok


func _ask_reset() -> void:
	if Attributes.total(run.attributes[hero]) <= 0:
		Sfx.play("locked")
		return
	_prompt = ConfirmPrompt.new()
	# ConfirmPrompt turns its own input on when ready; it hears it from handle_input instead.
	_prompt.ready.connect(_prompt.set_process_unhandled_input.bind(false), CONNECT_ONE_SHOT)
	add_child(_prompt)
	_prompt.setup("Take back every point?", "%s gets all their points back to spend again." %
			run.data.party[hero].display_name, "Reset", "Keep them")
	_prompt.answered.connect(_on_reset_answered)
	changed.emit()


func _on_reset_answered(yes: bool) -> void:
	_answered_frame = Engine.get_process_frames()
	if _prompt != null:
		_prompt.queue_free()
		_prompt = null
	if yes and not _too_wounded(Attributes.empty(), true):
		if ask({"op": "attributes", "slot": hero, "values": Attributes.empty()}):
			Sfx.play("menu_confirm")
			toast.emit("Points back", &"up")
	_redraw()
	changed.emit()


## True (with a sound, a toast and the strip's line saying why) if the hero is too wounded to
## change their points to `values`.
func _too_wounded(values: Array[int], loud: bool) -> bool:
	_warning = ""
	if not run.attributes_wound_blocked(hero, values):
		return false
	_warning = "%s is too wounded to give up that max HP. Heal first." % run.data.party[hero].display_name
	Sfx.play("locked")
	if loud:
		toast.emit("Too wounded", &"heart")
	_redraw()
	changed.emit()
	return true


## A menu action pressed, held keys repeating (adding points by holding Right, as before).
static func _repeats(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, true, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)


# --- building -----------------------------------------------------------------------------------

func _build_rail() -> void:
	var side := FACE_PX + 2.0 * FACE_PAD
	var left := (RAIL_WIDTH - side) * 0.5
	for slot: int in run.party_size():
		var c := run.data.party[slot]
		var box := Control.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.position = Vector2(RAIL_X, RAIL_TOP + float(slot) * (FACE_BOX_HEIGHT + FACE_GAP))
		box.size = Vector2(RAIL_WIDTH, FACE_BOX_HEIGHT)
		add_child(box)
		var frame := HudStyle.portrait_frame(AssetLoader.texture(c.portrait_path, Vector2i(48, 48)), c.color,
				FACE_PX, FACE_PAD, FACE_BG)
		frame.position = Vector2(left, 0.0)
		frame.size = Vector2(side, side)
		box.add_child(frame)
		var bar := HudStyle.bar(HudStyle.HP_FILL, RAIL_BAR_HEIGHT)
		bar.position = Vector2(left, side + RAIL_BAR_GAP)
		bar.size = Vector2(side, RAIL_BAR_HEIGHT)
		box.add_child(bar)
		var badge := PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK_SOLID, HudStyle.GOLD, 2, 3, 32.0,
				HudStyle.SLANT, false))
		badge.position = Vector2(left + side - BADGE_INSET, -BADGE_LIFT)
		box.add_child(badge)
		var line := _hbox(4)
		badge.add_child(line)
		line.add_child(_centred(UiGlyph.make(&"up", BADGE_GLYPH_PX, HudStyle.GOLD)))
		var number := HudStyle.make_number("", BADGE_SIZE, HudStyle.GOLD)
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(number)
		_faces.append({"box": box, "frame": frame, "bar": bar, "badge": badge, "number": number})


func _build_head() -> void:
	_name = HudStyle.make_title("", NAME_SIZE)
	_name.position = Vector2(CENTRE_X, NAME_Y)
	add_child(_name)
	var level_line := _hbox(18)
	level_line.position = Vector2(CENTRE_X, LEVEL_Y)
	add_child(level_line)
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK_SOLID, HudStyle.EDGE, 2, 4, 36.0,
			HudStyle.SLANT, false))
	level_line.add_child(chip)
	_level = HudStyle.make_number("", LEVEL_SIZE, HudStyle.TEXT)
	chip.add_child(_level)
	_xp_bar = HudStyle.bar(XP_COLOR, XP_BAR_HEIGHT)
	_xp_bar.custom_minimum_size.x = XP_BAR_WIDTH
	level_line.add_child(_centred(_xp_bar))
	_xp_text = HudStyle.make_number("", XP_TEXT_SIZE, HudStyle.TEXT_DIM)
	level_line.add_child(_centred(_xp_text))
	var points := _hbox(10)
	points.alignment = BoxContainer.ALIGNMENT_END
	points.position = Vector2(CENTRE_X, POINTS_Y)
	points.size = Vector2(CENTRE_WIDTH, POINTS_PX)
	add_child(points)
	_points_glyph = UiGlyph.make(&"up", POINTS_PX, HudStyle.GOLD)
	points.add_child(_centred(_points_glyph))
	_points = HudStyle.make_number("", POINTS_SIZE, HudStyle.GOLD)
	points.add_child(_centred(_points))


func _build_row(kind: int) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(CENTRE_X, ROWS_TOP + float(kind) * (ROW_HEIGHT + ROW_GAP))
	panel.size = Vector2(CENTRE_WIDTH, ROW_HEIGHT)
	add_child(panel)
	var line := _hbox(ROW_PART_GAP)
	panel.add_child(line)
	line.add_child(_centred(UiGlyph.make(ATTR_GLYPHS[kind], ROW_GLYPH_PX, ATTR_COLORS[kind])))
	var title := HudStyle.make_title(Attributes.NAMES[kind], ROW_NAME_SIZE, HudStyle.TEXT)
	title.custom_minimum_size.x = ROW_NAME_WIDTH
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(title)
	var points := HudStyle.make_number("", ROW_POINTS_SIZE, HudStyle.GOLD)
	points.custom_minimum_size.x = ROW_POINTS_WIDTH
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(points)
	var pips := Control.new()
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.custom_minimum_size = Vector2(PIPS_WIDTH, PIP_HEIGHT)
	pips.draw.connect(_draw_pips.bind(pips, kind))
	line.add_child(_centred(pips))
	line.add_child(_spacer())
	line.add_child(_centred(UiGlyph.make(STAT_GLYPHS[kind], STAT_GLYPH_PX, ATTR_COLORS[kind])))
	var value := HudStyle.make_number("", STAT_SIZE, HudStyle.TEXT)
	value.custom_minimum_size.x = STAT_VALUE_WIDTH
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(value)
	_rows.append({"panel": panel, "title": title, "points": points, "pips": pips, "value": value})


## The Echo box (DESIGN.md 8.17): free / total Echo points and the Echoes worn, nothing else, so a
## change to Echoes only touches this and _echo_info().
func _build_echo_box() -> void:
	_echo_box = PanelContainer.new()
	_echo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_echo_box.position = Vector2(CENTRE_X, ECHO_TOP)
	_echo_box.size = Vector2(CENTRE_WIDTH, ECHO_HEIGHT)
	add_child(_echo_box)
	var line := _hbox(ROW_PART_GAP)
	_echo_box.add_child(line)
	line.add_child(_centred(UiGlyph.make(&"echo", ECHO_GLYPH_PX, ECHO_COLOR)))
	var numbers := _hbox(6)
	line.add_child(numbers)
	_echo_free = HudStyle.make_number("", ECHO_NUMBER_SIZE, HudStyle.GOLD)
	numbers.add_child(_centred(_echo_free))
	_echo_total = HudStyle.make_number("", ECHO_TOTAL_SIZE, HudStyle.TEXT_DIM)
	numbers.add_child(_centred(_echo_total))
	_echo_icons = _hbox(8)
	line.add_child(_centred(_echo_icons))
	_echo_more = HudStyle.make_number("", ECHO_TOTAL_SIZE, HudStyle.TEXT_DIM)
	line.add_child(_centred(_echo_more))


func _build_stats() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(RIGHT_X, STATS_TOP)
	panel.size = Vector2(RIGHT_WIDTH, 0.0)
	panel.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.EDGE_DIM, 2, 12, STATS_HEIGHT, 0.08))
	add_child(panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", STAT_ROW_GAP)
	panel.add_child(column)
	for kind: int in Attributes.COUNT:
		var line := _hbox(16)
		line.custom_minimum_size.y = STAT_ROW_HEIGHT
		column.add_child(line)
		line.add_child(_centred(UiGlyph.make(STAT_GLYPHS[kind], STAT_ROW_GLYPH_PX, ATTR_COLORS[kind])))
		var word := HudStyle.make_label(STAT_WORDS[kind], STAT_WORD_SIZE, HudStyle.TEXT_DIM)
		word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(word)
		var value := HudStyle.make_number("", STAT_ROW_SIZE, HudStyle.TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(value)
		_stat_values.append(value)


static func _hbox(gap: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", gap)
	return box


static func _centred(control: Control) -> Control:
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return control


static func _spacer() -> Control:
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return gap


# --- drawing ------------------------------------------------------------------------------------

func _redraw() -> void:
	if run == null or _name == null:
		return
	hero = clampi(hero, 0, run.party_size() - 1)
	var c := run.data.party[hero]
	_name.text = c.display_name
	_name.label_settings.font_color = c.color.lightened(0.25)
	_redraw_level()
	var free := run.free_points(hero)
	var points_color := HudStyle.GOLD if free > 0 else HudStyle.TEXT_DIM
	_points.text = str(free)
	_points.label_settings.font_color = points_color
	_points_glyph.color = points_color
	_points_glyph.queue_redraw()
	for kind: int in _rows.size():
		var r: Dictionary = _rows[kind]
		var on := kind == _row
		(r.panel as PanelContainer).add_theme_stylebox_override("panel", _plate(on, ROW_HEIGHT))
		(r.title as Label).label_settings.font_color = HudStyle.GOLD if on else HudStyle.TEXT
		(r.points as Label).text = str(run.attribute(hero, kind))
		(r.pips as Control).queue_redraw()
		(r.value as Label).text = stat_text(kind)
	_redraw_echo_box()
	for kind: int in _stat_values.size():
		_stat_values[kind].text = stat_text(kind)
	var values: Array[int] = []
	var top := RADAR_MIN_TOP
	for kind: int in Attributes.COUNT:
		values.append(run.attribute_total(hero, kind))
		top = maxi(top, values[kind])
	_radar.setup(values, top, c.color.lightened(0.2), RADAR_PX)
	_redraw_rail()


func _redraw_level() -> void:
	_level.text = "Lv %d" % run.levels[hero]
	if run.is_max_level(hero):
		_xp_bar.max_value = 1.0
		_xp_bar.value = 1.0
		_xp_text.text = "MAX"
		_xp_text.label_settings.font_color = HudStyle.GOLD
	else:
		_xp_bar.max_value = float(maxi(1, run.xp_to_next(hero)))
		_xp_bar.value = float(run.xps[hero])
		_xp_text.text = "%d / %d" % [run.xps[hero], run.xp_to_next(hero)]
		_xp_text.label_settings.font_color = HudStyle.TEXT_DIM


func _redraw_echo_box() -> void:
	_echo_box.add_theme_stylebox_override("panel", _plate(_row == ECHO_ROW, ECHO_HEIGHT))
	var free := run.free_echo_points(hero)
	_echo_free.text = str(free)
	_echo_free.label_settings.font_color = HudStyle.GOLD if free > 0 else HudStyle.TEXT_DIM
	_echo_total.text = "/ %d" % run.echo_points(hero)
	for child: Node in _echo_icons.get_children():
		_echo_icons.remove_child(child)
		child.queue_free()
	var worn := _worn_echoes()
	for i: int in mini(worn.size(), ECHO_ICONS_MAX):
		var icon := RelicIcon.new()
		icon.setup(worn[i], ECHO_ICON_PX)
		_echo_icons.add_child(icon)
	_echo_more.text = "+%d" % (worn.size() - ECHO_ICONS_MAX) if worn.size() > ECHO_ICONS_MAX else ""


func _redraw_rail() -> void:
	for slot: int in _faces.size():
		var face: Dictionary = _faces[slot]
		var on := slot == hero
		var frame := face.frame as PanelContainer
		frame.add_theme_stylebox_override("panel", HudStyle.panel(FACE_BG,
				HudStyle.GOLD if on else run.data.party[slot].color.darkened(0.3), FACE_PAD, FACE_PAD))
		frame.modulate = Color.WHITE if on else FACE_DIM
		var bar := face.bar as ProgressBar
		var top_hp := run.max_hp(slot)
		bar.max_value = float(maxi(1, top_hp))
		bar.value = float(run.hp[slot])
		HudStyle.set_bar_color(bar, HudStyle.HP_LOW if run.hp[slot] * 100 <= top_hp * LOW_HP_PERCENT else HudStyle.HP_FILL)
		var spare := run.free_points(slot)
		(face.badge as Control).visible = spare > 0
		(face.number as Label).text = str(spare)


## A row plate: gold edged on the cursor.
static func _plate(on: bool, height: float) -> StyleBoxFlat:
	return HudStyle.slant(CURSOR_BG if on else HudStyle.INK, HudStyle.GOLD if on else HudStyle.EDGE_DIM,
			3 if on else 2, PLATE_PAD, height)


## One pip per point: gold for the points spent, violet for a worn Relic's stat line; one hollow
## pip when there are none, so the row keeps its shape.
func _draw_pips(canvas: Control, kind: int) -> void:
	if run == null:
		return
	var spent := run.attribute(hero, kind)
	var count := mini(PIP_MAX, spent + maxi(0, run.relic_stat(hero, kind)))
	var top := (canvas.size.y - PIP_HEIGHT) * 0.5
	if count == 0:
		var hollow := _pip(0, top)
		hollow.append(hollow[0])
		canvas.draw_polyline(hollow, HudStyle.EDGE_DIM, 1.5, true)
		return
	for i: int in count:
		canvas.draw_colored_polygon(_pip(i, top), HudStyle.GOLD if i < spent else RELIC_PIP_COLOR)


## Pip `i`: a small slanted bar like the plates, a little gap after every PIP_GROUP.
static func _pip(i: int, top: float) -> PackedVector2Array:
	var lean := PIP_HEIGHT * HudStyle.SLANT * 0.5
	var x := float(i) * PIP_STEP + floorf(float(i) / float(PIP_GROUP)) * PIP_GROUP_GAP
	return PackedVector2Array([Vector2(x + lean, top), Vector2(x + lean + PIP_WIDTH, top),
			Vector2(x + PIP_WIDTH, top + PIP_HEIGHT), Vector2(x, top + PIP_HEIGHT)])


# --- Echoes (DESIGN.md 8.17) --------------------------------------------------------------------

func _worn_echoes() -> Array[GearData]:
	var worn: Array[GearData] = []
	if hero < run.echoes.size():
		for id: Variant in run.echoes[hero]:
			var item := run.relic_by_id(String(id))
			if item != null:
				worn.append(item)
	return worn


func _echo_info() -> Dictionary:
	var free := run.free_echo_points(hero)
	var learned := run.learned_echoes().size()
	var chips: Array = [[&"echo", "%d / %d" % [free, run.echo_points(hero)], HudStyle.GOLD if free > 0 else HudStyle.TEXT_DIM],
			[&"gem", "%d worn" % _worn_echoes().size(), HudStyle.TEXT],
			[&"star", "%d learned" % learned, HudStyle.TEXT_DIM]]
	var line := "Win fights wearing a Relic to learn its Echo." if learned == 0 else "Wear or take off Echoes."
	if not _warning.is_empty():
		line = _warning
	return {"icon": &"echo", "title": "Echoes", "color": ECHO_COLOR, "chips": chips, "line": line}
