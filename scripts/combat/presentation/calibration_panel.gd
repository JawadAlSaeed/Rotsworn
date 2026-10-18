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
## the line under it, the circle in the middle, the numbers and buttons under it, all centred.

signal closed

const TITLE_SIZE: int = 44
const TEXT_SIZE: int = 30
const CIRCLE_RADIUS: float = 150.0
const CIRCLE_RING_WIDTH: float = 8.0
const SEGMENTS: int = 96
const KIND_NAMES := {PlayerSettings.INPUT_KEYBOARD: "keyboard", PlayerSettings.INPUT_PAD: "controller"}
const DIM := Color(0.0, 0.0, 0.0, 0.8)
const CIRCLE_IDLE := Color(0.3, 0.32, 0.38)
const CIRCLE_LIT := Color(1.0, 0.95, 0.7)

var _visuals: CombatVisuals
var _tuning: Tuning
var _input: DefenseInput
var _running: bool = false
var _first_beat_us: int = 0
var _next_beat: int = 0
var _lit_until_us: int = 0
var _offsets_us: Array[int] = []
## The kind of input being measured (PlayerSettings.INPUT_KEYBOARD or INPUT_PAD); "" until the
## first press.
var _kind: String = ""
var _title: Label
var _text: Label
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
	# "Press [Parry button] exactly when the circle flashes." with the button as a picture.
	var how := HBoxContainer.new()
	how.mouse_filter = Control.MOUSE_FILTER_IGNORE
	how.alignment = BoxContainer.ALIGNMENT_CENTER
	how.add_theme_constant_override("separation", 10)
	how.add_child(HudStyle.make_label("Press", TEXT_SIZE))
	how.add_child(HintBar.new([[&"defend_parry", ""]], TEXT_SIZE, HudStyle.TEXT))
	how.add_child(HudStyle.make_label("exactly when the circle flashes.", TEXT_SIZE))
	column.add_child(how)
	_circle_space = Control.new()
	_circle_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_circle_space.custom_minimum_size = Vector2(0.0, CIRCLE_RADIUS * 2.0 + CIRCLE_RING_WIDTH * 4.0)
	column.add_child(_circle_space)
	_text = HudStyle.make_label("", TEXT_SIZE)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_text)
	_hints = HintBar.new([], TEXT_SIZE, HudStyle.TEXT)
	_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_hints)
	visible = false


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


func _update_text() -> void:
	var lines := PackedStringArray()
	lines.append("Beat %d / %d   presses counted: %d" % [_next_beat, _visuals.calibration_beats, _offsets_us.size()])
	if _kind.is_empty():
		lines.append("Press with the keyboard or the pad you will play with.")
	else:
		lines.append("Measuring: %s" % KIND_NAMES[_kind])
	if _offsets_us.is_empty():
		lines.append("Median offset: -")
	else:
		var median := roundi(_median_us() / 1000.0)
		var saved := PlayerSettings.clamp_latency(median, _tuning)
		var line := "Median offset (last %d): %+d ms   spread %d ms" % [_recent().size(), median, _spread_ms()]
		if saved != median:
			line += "   (saves %+d, the limit)" % saved
		lines.append(line)
	if _can_save():
		_hints.set_entries([[&"menu_confirm", "Save for the %s" % KIND_NAMES[_kind]], [&"menu_cancel", "Cancel"]])
	else:
		if _offsets_us.size() >= _visuals.calibration_min_presses:
			lines.append("Too uneven to save: press WITH the beat, not after the flash.")
		_hints.set_entries([[&"menu_cancel", "Cancel"]])
	_text.text = "\n".join(lines)


func _close() -> void:
	_running = false
	visible = false
	_input.disarm()
	closed.emit()
