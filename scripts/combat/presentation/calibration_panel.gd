class_name CalibrationPanel
extends Control
## Lag calibration (F2, DESIGN.md 3.2): a big circle flashes with the "metronome" sound on a fixed
## beat; the player presses Parry on each beat. Presses are stamped by the same DefenseInput as in
## combat (the midpoint of the press interval). The median offset of the last presses becomes the
## player's lag compensation when they confirm (saved by UserSettings, clamped to tuning's
## calibration bounds); cancel discards it. The first press decides which kind of input is being
## measured (keyboard or pad, card #204): the result is saved for that kind only, and presses from
## the other kind are ignored, because a pad and a keyboard lag differently. Presses that spread too widely (pressing by reaction
## instead of with the beat) cannot be saved. Laid out like the other pages (card #113): the title,
## the line under it, the circle in the middle, the measuring under it, all centred.
## Phase 22, no milliseconds for players: under the circle a row of beat pips fills as the beats go
## by (a beat with a counted press lights up), the picture of the device being measured (keyboard
## or pad) stands beside a steadiness meter that turns green once the measure can be saved, and a
## "Too uneven" chip says when the presses are too spread out. The numbers (median, spread) only
## show with `show_numbers`, or in a fight while the F1 stats overlay is open (a practice tool).

signal closed

const TITLE_SIZE: int = 44
const TEXT_SIZE: int = 30
const NUMBERS_SIZE: int = 24
const CIRCLE_RADIUS: float = 150.0
const CIRCLE_RING_WIDTH: float = 8.0
const SEGMENTS: int = 96
const KIND_GLYPHS := {PlayerSettings.INPUT_KEYBOARD: &"keyboard", PlayerSettings.INPUT_PAD: &"pad"}
const DIM := Color(0.0, 0.0, 0.0, 0.8)
const CIRCLE_IDLE := Color(0.3, 0.32, 0.38)
const CIRCLE_LIT := Color(1.0, 0.95, 0.7)
## Layout of the measuring row: pip size and gap, device picture size, meter size (pixels on the
## 1920x1080 canvas).
const PIP_PX: float = 26.0
const PIP_GAP: float = 12.0
const DEVICE_PX: float = 64.0
const METER_SIZE := Vector2(360.0, 26.0)
## The meter's fill share where saving starts (percent; see meter_percent).
const METER_SAVE_LINE: int = 50
const STEADY := Color(0.45, 0.9, 0.45)
const TOO_UNEVEN := "Too uneven"

## Show the median and spread in milliseconds under the meter (off for players; a fight's panel
## also shows them while the F1 stats overlay beside it is open, see _numbers_wanted).
var show_numbers: bool = false

var _visuals: CombatVisuals
var _tuning: Tuning
var _input: DefenseInput
var _running: bool = false
var _first_beat_us: int = 0
var _next_beat: int = 0
var _lit_until_us: int = 0
var _offsets_us: Array[int] = []
## The beats a press was counted on (beat index -> true).
var _hit_beats: Dictionary = {}
## The kind of input being measured (PlayerSettings.INPUT_KEYBOARD or INPUT_PAD); "" until the
## first press.
var _kind: String = ""
var _title: Label
## The beat pips, the device pictures (keyboard, pad), the steadiness meter and the warning chip.
var _pips: BeatPips
var _devices: Dictionary = {}
var _meter: SteadyMeter
var _uneven: PanelContainer
## The milliseconds (only with show_numbers).
var _numbers: Label
## The button hints (save, cancel) as button pictures.
var _hints: HintBar
## Room in the column where the circle is drawn.
var _circle_space: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	add_child(column)
	_title = HudStyle.make_worn_title("Lag Calibration", TITLE_SIZE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	column.add_child(ListMenu.divider())
	# "[Parry button] on each flash", the button as a picture.
	var how := HBoxContainer.new()
	how.mouse_filter = Control.MOUSE_FILTER_IGNORE
	how.alignment = BoxContainer.ALIGNMENT_CENTER
	how.add_theme_constant_override("separation", 10)
	how.add_child(HintBar.new([[&"defend_parry", "on each flash"]], TEXT_SIZE, HudStyle.TEXT))
	column.add_child(how)
	_circle_space = Control.new()
	_circle_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_circle_space.custom_minimum_size = Vector2(0.0, CIRCLE_RADIUS * 2.0 + CIRCLE_RING_WIDTH * 4.0)
	column.add_child(_circle_space)
	_pips = BeatPips.new()
	_pips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_pips)
	column.add_child(_build_measure_row())
	_numbers = HudStyle.make_label("", NUMBERS_SIZE, HudStyle.TEXT_DIM)
	_numbers.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_numbers)
	_hints = HintBar.new([], TEXT_SIZE, HudStyle.TEXT)
	_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_hints)
	visible = false


## The device pictures, the steadiness meter and the "Too uneven" chip, on one line.
func _build_measure_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	for kind: String in PlayerSettings.INPUT_KINDS:
		var glyph := UiGlyph.make(KIND_GLYPHS[kind], DEVICE_PX, HudStyle.TEXT_DIM)
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(glyph)
		_devices[kind] = glyph
	_meter = SteadyMeter.new()
	_meter.custom_minimum_size = METER_SIZE
	_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_meter)
	_uneven = PanelContainer.new()
	_uneven.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_uneven.add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.PANEL_BG, HudStyle.LATE, 2, 8))
	_uneven.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_uneven.add_child(HudStyle.make_label(TOO_UNEVEN, NUMBERS_SIZE, HudStyle.LATE))
	row.add_child(_uneven)
	return row


func setup(visuals: CombatVisuals, tuning: Tuning, input: DefenseInput) -> void:
	_visuals = visuals
	_tuning = tuning
	_input = input
	_input.pressed.connect(_on_pressed)


func is_running() -> bool:
	return _running


func open() -> void:
	_fill_screen()
	_running = true
	visible = true
	_offsets_us.clear()
	_hit_beats.clear()
	_kind = ""
	_next_beat = 0
	_lit_until_us = 0
	_first_beat_us = Time.get_ticks_usec() + _visuals.calibration_lead_ms * 1000
	var parry: Array[int] = [Defense.Outcome.PARRY]
	_input.arm(parry)
	_update_text()


## Confirm saves (once enough presses were made), cancel discards. Returns true if used.
func handle_input(event: InputEvent) -> bool:
	if not _running:
		return false
	if event.is_action_pressed("menu_confirm", false, true):
		if _can_save():
			PlayerSettings.set_latency_compensation_ms(roundi(_median_us() / 1000.0), _tuning, _kind)
			Sfx.play("menu_confirm")
			_close()
		else:
			Sfx.play("locked")
		return true
	if event.is_action_pressed("menu_cancel", false, true):
		Sfx.play("menu_cancel")
		_close()
		return true
	return true


func _process(_delta: float) -> void:
	if not _running:
		return
	var now := Time.get_ticks_usec()
	while _next_beat < _visuals.calibration_beats and now >= _beat_time_us(_next_beat):
		Sfx.play("metronome")
		_lit_until_us = now + _visuals.calibration_flash_ms * 1000
		_next_beat += 1
		_update_text()
	queue_redraw()


func _draw() -> void:
	if not _running:
		return
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var centre := _circle_space.get_global_rect().get_center() - global_position
	var lit := Time.get_ticks_usec() < _lit_until_us
	if lit:
		draw_circle(centre, CIRCLE_RADIUS, CIRCLE_LIT)
	draw_arc(centre, CIRCLE_RADIUS, 0.0, TAU, SEGMENTS, CIRCLE_LIT if lit else CIRCLE_IDLE, CIRCLE_RING_WIDTH, true)


## Covers the whole screen, inside a fight's HUD or straight under a CanvasLayer (the settings
## screen), where a full-rect anchor alone left it at size zero in the top left.
func _fill_screen() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not get_parent() is Control and is_inside_tree():
		set_deferred("position", Vector2.ZERO)
		set_deferred("size", get_viewport_rect().size)


func _on_pressed(action: int, stamp_us: int, previous_pump_us: int, device: int) -> void:
	if not _running or action != Defense.Outcome.PARRY:
		return
	var kind := PlayerSettings.input_kind_of_device(device)
	if _kind.is_empty():
		_kind = kind
	elif kind != _kind:
		Sfx.play("locked")
		return
	var mid := stamp_us
	if previous_pump_us > 0 and previous_pump_us < stamp_us:
		@warning_ignore("integer_division")
		mid = previous_pump_us + (stamp_us - previous_pump_us) / 2
	var interval_us := _visuals.calibration_interval_ms * 1000
	var beat := clampi(roundi(float(mid - _first_beat_us) / float(interval_us)), 0, _visuals.calibration_beats - 1)
	var offset := mid - _beat_time_us(beat)
	@warning_ignore("integer_division")
	var half_us := interval_us / 2
	if absi(offset) <= half_us:
		_offsets_us.append(offset)
		_hit_beats[beat] = true
		Sfx.play("menu_move")
	_update_text()


func _beat_time_us(beat: int) -> int:
	return _first_beat_us + beat * _visuals.calibration_interval_ms * 1000


func _recent() -> Array[int]:
	var count := mini(_visuals.calibration_sample_count, _offsets_us.size())
	var recent: Array[int] = []
	recent.assign(_offsets_us.slice(_offsets_us.size() - count))
	return recent


func _median_us() -> float:
	return DefenseStats.median_us(_recent())


func _spread_ms() -> int:
	return roundi(DefenseStats.spread_us(_recent()) / 1000.0)


func _can_save() -> bool:
	return _offsets_us.size() >= _visuals.calibration_min_presses and _spread_ms() <= _visuals.calibration_max_spread_ms


## True once enough presses came in but they are spread too widely to save.
func _too_uneven() -> bool:
	return _offsets_us.size() >= _visuals.calibration_min_presses and not _can_save()


## How full the steadiness meter is (0 to 100). Until `min_presses` presses came in it only fills up
## to METER_SAVE_LINE, a step per press; from then on it shows how steady the presses are: 100 for
## no spread, METER_SAVE_LINE at exactly `max_spread_ms` and empty at twice that. So the meter
## reaches the save line exactly when the measure can be saved. Pure, integers only.
static func meter_percent(presses: int, min_presses: int, spread_ms: int, max_spread_ms: int) -> int:
	if presses <= 0:
		return 0
	if presses < min_presses:
		@warning_ignore("integer_division")
		return presses * METER_SAVE_LINE / maxi(1, min_presses)
	var top := maxi(1, max_spread_ms)
	# Rounded up, so one millisecond over the limit is already under the line.
	@warning_ignore("integer_division")
	var lost := (maxi(0, spread_ms) * (100 - METER_SAVE_LINE) + top - 1) / top
	return clampi(100 - lost, 0, 100)


func _update_text() -> void:
	var can_save := _can_save()
	_pips.set_state(_visuals.calibration_beats, _next_beat, _hit_beats)
	for kind: String in _devices:
		var glyph := _devices[kind] as UiGlyph
		# Before the first press both pictures say "either"; then only the one being measured shows.
		glyph.visible = _kind.is_empty() or kind == _kind
		glyph.color = HudStyle.TEXT_DIM if _kind.is_empty() else (STEADY if can_save else HudStyle.GOLD)
		glyph.queue_redraw()
	var fill := meter_percent(_offsets_us.size(), _visuals.calibration_min_presses, _spread_ms(),
			_visuals.calibration_max_spread_ms)
	_meter.set_state(fill, METER_SAVE_LINE, STEADY if can_save else (HudStyle.LATE if _too_uneven() else HudStyle.GOLD))
	_uneven.visible = _too_uneven()
	_numbers.visible = _numbers_wanted()
	if _numbers.visible:
		_numbers.text = _numbers_text()
	if can_save:
		_hints.set_entries([[&"menu_confirm", "Save"], [&"menu_cancel", "Cancel"]])
	else:
		_hints.set_entries([[&"menu_cancel", "Cancel"]])


## True when the milliseconds show: `show_numbers`, or the fight HUD's F1 stats overlay (a sibling
## named DebugOverlay, only open in practice fights) is open.
func _numbers_wanted() -> bool:
	if show_numbers:
		return true
	var stats := get_parent().get_node_or_null(^"DebugOverlay") as CanvasItem if get_parent() != null else null
	return stats != null and stats.visible


## The milliseconds for a practice look (the median of the last presses and their spread).
func _numbers_text() -> String:
	if _offsets_us.is_empty():
		return "Median -"
	var median := roundi(_median_us() / 1000.0)
	var saved := PlayerSettings.clamp_latency(median, _tuning)
	var line := "Median (last %d) %+d ms   spread %d ms" % [_recent().size(), median, _spread_ms()]
	if saved != median:
		line += "   (saves %+d, the limit)" % saved
	return line


func _close() -> void:
	_running = false
	visible = false
	_input.disarm()
	closed.emit()


## A row of beat pips: a ring for a beat still to come, a dim dot for one gone by without a counted
## press, a gold dot for one with a counted press.
class BeatPips:
	extends Control

	var count: int = 0
	var passed: int = 0
	var hits: Dictionary = {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(p_count: int, p_passed: int, p_hits: Dictionary) -> void:
		count = p_count
		passed = p_passed
		hits = p_hits.duplicate()
		custom_minimum_size = Vector2(float(count) * PIP_PX + float(maxi(0, count - 1)) * PIP_GAP, PIP_PX)
		queue_redraw()

	## How many pips are filled (beats gone by).
	func filled() -> int:
		return mini(passed, count)

	func _draw() -> void:
		var r := PIP_PX * 0.5
		for i: int in count:
			var c := Vector2(r + float(i) * (PIP_PX + PIP_GAP), size.y * 0.5)
			if hits.has(i):
				draw_circle(c, r, HudStyle.GOLD)
			elif i < passed:
				draw_circle(c, r * 0.8, HudStyle.TEXT_DIM)
			else:
				draw_arc(c, r * 0.8, 0.0, TAU, 24, HudStyle.TEXT_DIM, 2.0, true)


## A bar that fills (0 to 100) with a tick at the save line, in the colour it is given.
class SteadyMeter:
	extends Control

	const BACK := Color(0.08, 0.08, 0.1, 0.9)
	const EDGE := Color(0.42, 0.37, 0.3, 0.9)

	var percent: int = 0
	var line: int = 50
	var color: Color = HudStyle.GOLD

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(p_percent: int, p_line: int, p_color: Color) -> void:
		percent = clampi(p_percent, 0, 100)
		line = p_line
		color = p_color
		queue_redraw()

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		draw_rect(box, BACK)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * float(percent) / 100.0, size.y)), color)
		var x := size.x * float(line) / 100.0
		draw_line(Vector2(x, -4.0), Vector2(x, size.y + 4.0), HudStyle.TEXT, 2.0)
		draw_rect(box, EDGE, false, 2.0)
