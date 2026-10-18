class_name SettingsScreen
extends CanvasLayer
## Settings (DESIGN.md 7.5, card #112) in four sections, changed with LB / RB (Z / C):
## Graphics (fullscreen, window size, vsync, frame limit, fog, bloom, shadows, soft shadows, depth
## of field), Sound (overall, music, effects, voices), Controls (every key and button can be
## rebound, card #190) and Game (screen shake, the training ring, lag calibration, Reset progress).
## Everything is saved per machine at once (PlayerSettings, user://settings.cfg) and graphics
## changes show at once, even over a fight. Left/right change a value, confirm toggles or opens.
## Reset progress (DESIGN.md 8.17) asks twice and then emits progress_reset for Main to wipe the
## Relics, the unlocked oaths and a saved run; it is only offered from the main menu, never in a run.
##
## Controls: one row per action with its key and its pad button. Left/Right pick the Key or the Pad
## column, Confirm waits for the new key or button (Escape or the pad's Menu button cancels, and so
## does waiting too long). A button an action in the same group already has asks to swap them;
## ControlBindings holds the rules. "Reset to defaults" is a row of the list (asks twice). A change
## applies to every pad: there are no per-pad bindings.

signal closed
## The player confirmed Reset progress twice (Main wipes the files).
signal progress_reset

const TITLE_SIZE: int = 56
const TAB_SIZE: int = 34
const TAB_GAP: int = 48
const CONTROLS_SIZE: int = 26
const DETAIL_SIZE: int = 26
const ROW_WIDTH: float = 760.0
## Smaller rows than other menus: the graphics section has ten.
const ITEM_SIZE: int = 32
## The Controls list is wider (a key and a button per row) and scrolls: this many rows show.
const CONTROLS_ROW_WIDTH: float = 1180.0
const CONTROLS_WINDOW: int = 10
const COLUMN_GAP := "      "

enum Section { GRAPHICS, SOUND, CONTROLS, GAME }
const SECTION_NAMES: Array[String] = ["Graphics", "Sound", "Controls", "Game"]

## The rows of each section, by id (Back closes the screen from any section).
const SECTION_ROWS := {
	Section.GRAPHICS: ["fullscreen", "window_size", "vsync", "fps_limit", "fog", "bloom", "shadows",
		"ambient_occlusion", "depth_of_field", "back"],
	Section.SOUND: ["master", "music", "effects", "voice", "back"],
	Section.CONTROLS: [],  # built by _rows_of: one row per action, then reset and back
	Section.GAME: ["screen_shake", "flashes", "timing_ring", "calibrate", "reset_lag", "reset_progress", "back"],
}
const SECTION_HINTS: Array = [[&"item_turn_left", "Section"], [&"item_turn_right", "Section"],
		[&"@updown", "Choose"], [&"@leftright", "Change"], [&"menu_confirm", "Select"], [&"menu_cancel", "Back"]]
const CONTROLS_HINTS: Array = [[&"item_turn_left", "Section"], [&"item_turn_right", "Section"],
		[&"@updown", "Choose"], [&"@leftright", "Key or pad"], [&"menu_confirm", "Change"], [&"menu_cancel", "Back"]]
const GRAPHICS_DETAIL := {
	"fog": "Mist over the zones and fights. Off is faster on slow PCs.",
	"bloom": "The soft glow around lights and bright things.",
	"shadows": "Shadows cast by the sun.",
	"ambient_occlusion": "Soft shading where things meet the ground.",
	"depth_of_field": "Blurs what is far from the action.",
}
const VOLUME_DETAIL := {
	"master": ["Volume", "Everything louder or quieter."],
	"music": ["Music", "The songs only."],
	"effects": ["Effects", "Hits, parries, steps and menu sounds."],
	"voice": ["Voices", "Heroes and enemies shouting and growling."],
}

var _tuning: Tuning
var _visuals: CombatVisuals
var _section: Section = Section.GRAPHICS
var _tabs: Array[Label] = []
var _menu: ListMenu
var _detail: Label
var _defense_input: DefenseInput
var _calibration: CalibrationPanel
var _page: Control
var _footer: HintBar
var _bindings: ControlBindings
## The column Left/Right chose in the Controls list: ControlBindings.KEY or PAD.
var _column: String = ControlBindings.KEY
## Waiting for the new input of this action and kind ("" kind: not waiting).
var _capture_action: StringName = &""
var _capture_kind: String = ""
var _capture_until_ms: int = 0
## A swap waiting for Confirm: {action, input, other}; empty when none.
var _swap: Dictionary = {}
## The message under the list (a refusal, a question) until the cursor moves.
var _note: String = ""
var _note_is_problem: bool = false
## When a second Confirm on "Reset to defaults" still counts (Time.get_ticks_msec).
var _reset_until_ms: int = 0
## Reset progress can be picked (the main menu's settings; not the pause menu's, mid-run).
var _allow_reset: bool = false
var _prompt: ConfirmPrompt


func setup(tuning: Tuning, visuals: CombatVisuals, allow_reset: bool = false) -> void:
	_tuning = tuning
	_visuals = visuals
	_allow_reset = allow_reset
	var column := ListMenu.screen_column(self, "Settings", TITLE_SIZE)
	_page = column
	var tabs := HBoxContainer.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", TAB_GAP)
	column.add_child(tabs)
	for name: String in SECTION_NAMES:
		var tab := HudStyle.make_title(name, TAB_SIZE, HudStyle.TEXT_DIM)
		tabs.add_child(tab)
		_tabs.append(tab)
	_menu = ListMenu.new()
	_menu.centred = false
	_menu.row_width = ROW_WIDTH
	_menu.item_size = ITEM_SIZE
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_menu)
	_bindings = ControlBindings.current()
	_detail = ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_detail)
	_footer = ListMenu.screen_footer(self, [])
	_show_section(Section.GRAPHICS)

	_defense_input = DefenseInput.new()
	_defense_input.name = "DefenseInput"
	add_child(_defense_input)
	_calibration = CalibrationPanel.new()
	_calibration.name = "Calibration"
	add_child(_calibration)
	_calibration.setup(_visuals, _tuning, _defense_input)
	_calibration.closed.connect(_on_calibration_closed)


func _process(_delta: float) -> void:
	if _capture_kind != "" and Time.get_ticks_msec() >= _capture_until_ms:
		_end_capture("Nothing pressed: the old button stays.", false)


## While the Controls list waits for a new key or button every key and pad press comes here first
## (so Escape and the Menu button can cancel, and Pause or Confirm cannot act meanwhile).
func _input(event: InputEvent) -> void:
	if _capture_kind == "" or _calibration.is_running():
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		get_viewport().set_input_as_handled()
		if ControlBindings.input_from_event(key).get("code", 0) == KEY_ESCAPE:
			_end_capture("Cancelled: the old button stays.", false)
		elif _capture_kind == ControlBindings.KEY:
			_try_assign(ControlBindings.input_from_event(key))
	elif event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if not button.pressed:
			return
		get_viewport().set_input_as_handled()
		if button.button_index == JOY_BUTTON_START:
			_end_capture("Cancelled: the old button stays.", false)
		elif _capture_kind == ControlBindings.PAD:
			_try_assign(ControlBindings.input_from_event(button))
	elif event is InputEventJoypadMotion and _capture_kind == ControlBindings.PAD:
		var motion := event as InputEventJoypadMotion
		if ControlBindings.TRIGGER_AXES.has(motion.axis) and motion.axis_value >= ControlBindings.TRIGGER_CAPTURE_VALUE:
			get_viewport().set_input_as_handled()
			_try_assign({"k": "axis", "code": int(motion.axis), "dir": 1})


func _unhandled_input(event: InputEvent) -> void:
	if _prompt != null:
		return
	if _calibration.is_running():
		_calibration.handle_input(event)
		get_viewport().set_input_as_handled()
		return
	if _capture_kind != "":
		# Waiting for a new key: nothing else may act (a stick must not move the cursor).
		get_viewport().set_input_as_handled()
		return
	if not _swap.is_empty():
		if event.is_action_pressed(&"menu_confirm", false, true):
			get_viewport().set_input_as_handled()
			_do_swap()
		elif event.is_action_pressed(&"menu_cancel", false, true) or event.is_action_pressed(&"pause", false, true):
			get_viewport().set_input_as_handled()
			_swap = {}
			_set_note("Not swapped: nothing changed.", false)
			_refresh()
		return
	if event.is_action_pressed(&"item_turn_left", false, true) or event.is_action_pressed(&"item_turn_right", false, true):
		get_viewport().set_input_as_handled()
		var step := -1 if event.is_action(&"item_turn_left") else 1
		_show_section(posmod(_section + step, Section.size()) as Section)
		Sfx.play("menu_move")
		return
	var answer := _menu.handle(event)
	if answer == &"":
		if _section == Section.CONTROLS and (event.is_action_pressed(&"menu_up", false, true)
				or event.is_action_pressed(&"menu_down", false, true)):
			_note = ""
			_reset_until_ms = 0
			_refresh()
		return
	if answer == &"cancel":
		Sfx.play("menu_cancel")
		closed.emit()
		return
	var step := -1 if answer == &"left" else 1
	var row := String(_rows_of(_section)[_menu.index])
	if row.begins_with("ctl:"):
		_controls_answer(StringName(row.substr(4)), answer)
		return
	match row:
		"master", "music", "effects", "voice":
			if answer != &"confirm":
				PlayerSettings.set_channel_percent(row, PlayerSettings.channel_percent(row) + step * PlayerSettings.VOLUME_STEP_PERCENT)
				Sfx.play("menu_move")
		"fullscreen":
			PlayerSettings.set_fullscreen(not PlayerSettings.fullscreen())
			Sfx.play("menu_confirm")
		"window_size":
			if PlayerSettings.fullscreen():
				Sfx.play("locked")
			else:
				PlayerSettings.set_window_size_index(PlayerSettings.window_size_index() + step)
				Sfx.play("menu_move")
		"vsync":
			PlayerSettings.set_vsync(not PlayerSettings.vsync())
			Sfx.play("menu_confirm")
		"fps_limit":
			PlayerSettings.set_fps_limit_index(PlayerSettings.fps_limit_index() + step)
			Sfx.play("menu_move")
		"fog", "bloom", "shadows", "ambient_occlusion", "depth_of_field":
			PlayerSettings.set_graphics(row, not PlayerSettings.graphics(row))
			StageBuilder.apply_settings(get_tree().root)
			Sfx.play("menu_confirm")
		"screen_shake":
			if answer == &"confirm":
				step = 1 if PlayerSettings.screen_shake_percent() < 100 else -4
			PlayerSettings.set_screen_shake_percent(PlayerSettings.screen_shake_percent() + step * PlayerSettings.SHAKE_STEP_PERCENT)
			Sfx.play("menu_move")
		"flashes":
			PlayerSettings.set_flash_mode(PlayerSettings.flash_mode() + (1 if answer == &"confirm" else step))
			Sfx.play("menu_move")
		"timing_ring":
			PlayerSettings.set_show_timing_ring(not PlayerSettings.show_timing_ring(_tuning))
			Sfx.play("menu_confirm")
		"calibrate":
			if answer == &"confirm":
				Sfx.play("menu_confirm")
				open_calibration()
		"reset_lag":
			if answer == &"confirm":
				if PlayerSettings.is_calibrated():
					PlayerSettings.reset_latency_compensation()
					Sfx.play("menu_confirm")
				else:
					Sfx.play("locked")
		"back":
			if answer == &"confirm":
				Sfx.play("menu_cancel")
				closed.emit()
				return
		"reset":
			if answer == &"confirm":
				_reset_controls()
				return
		"reset_progress":
			if answer == &"confirm":
				_ask_reset_progress()
				return
	_refresh()


## Reset progress: asks, then asks again, then emits progress_reset.
func _ask_reset_progress() -> void:
	if not _allow_reset:
		Sfx.play("locked")
		_set_note("Progress can only be reset from the main menu, not during a run.", true)
		_refresh()
		return
	Sfx.play("menu_confirm")
	_confirm("Reset all progress?", "Your Relics and their levels, the oaths you unlocked and a saved run are wiped. "
			+ "Settings, controls and the Journal stay.", "Reset", "Keep my progress", func() -> void:
				_confirm("Are you sure?", "This cannot be undone.", "Yes, wipe it", "No", func() -> void:
					progress_reset.emit()
					Sfx.play("menu_confirm")
					_set_note("Progress reset: a fresh start.", false)
					_refresh()))


func _confirm(question: String, detail: String, yes: String, no: String, on_yes: Callable) -> void:
	_prompt = ConfirmPrompt.new()
	add_child(_prompt)
	_prompt.setup(question, detail, yes, no)
	_prompt.answered.connect(func(answer: bool) -> void:
		get_viewport().set_input_as_handled()
		_prompt.queue_free()
		_prompt = null
		if answer:
			on_yes.call_deferred()
		else:
			Sfx.play("menu_cancel"))


## Opens the lag calibration over this screen (also for --screen=calibration pictures).
func open_calibration() -> void:
	_page.visible = false
	_footer.visible = false
	_calibration.open()


func _show_section(section: Section) -> void:
	_section = section
	for i: int in _tabs.size():
		_tabs[i].label_settings.font_color = HudStyle.GOLD if i == section else HudStyle.TEXT_DIM
	var rows := _rows_of(section)
	var controls := section == Section.CONTROLS
	_menu.row_width = CONTROLS_ROW_WIDTH if controls else ROW_WIDTH
	_menu.window_rows = CONTROLS_WINDOW if controls else 0
	var blank: Array[Dictionary] = []
	for i: int in rows.size():
		blank.append({})
	_menu.index = 0
	_menu.set_items(blank, _detail)
	_note = ""
	_reset_until_ms = 0
	_footer.set_entries(CONTROLS_HINTS if controls else SECTION_HINTS)
	_refresh()


func _on_calibration_closed() -> void:
	_page.visible = true
	_footer.visible = true
	_refresh()


func _refresh() -> void:
	var rows := _rows_of(_section)
	for i: int in rows.size():
		var row := String(rows[i])
		if row.begins_with("ctl:"):
			_refresh_control(i, StringName(row.substr(4)), rows.size())
			continue
		match row:
			"master", "music", "effects", "voice":
				_menu.set_item(i, String(VOLUME_DETAIL[row][0]), true, String(VOLUME_DETAIL[row][1]), _percent(row))
			"fullscreen":
				_menu.set_item(i, "Fullscreen", true, "Fill the whole screen, or a window.",
						_on_off(PlayerSettings.fullscreen()))
			"window_size":
				_menu.set_item(i, "Window size", not PlayerSettings.fullscreen(),
						"The window's size when not fullscreen.", "<  %s  >" % _window_text())
			"vsync":
				_menu.set_item(i, "VSync", true, "Matches the screen's refresh: no tearing. Off can feel a little quicker.",
						_on_off(PlayerSettings.vsync()))
			"fps_limit":
				var limit := PlayerSettings.fps_limit()
				_menu.set_item(i, "Frame limit", true, "The most frames a second the game draws.",
						"<  %s  >" % ("No limit" if limit <= 0 else str(limit)))
			"fog", "bloom", "shadows", "ambient_occlusion", "depth_of_field":
				_menu.set_item(i, String(PlayerSettings.GRAPHICS[row]), true, String(GRAPHICS_DETAIL[row]),
						_on_off(PlayerSettings.graphics(row)))
			"screen_shake":
				_menu.set_item(i, "Screen shake", true, "How much the camera shakes on hits and parries.",
						"<  %d%%  >" % PlayerSettings.screen_shake_percent())
			"flashes":
				_menu.set_item(i, "Flashes", true,
						"How bright the screen and hit flashes are. Reduced or Off helps if flashing bothers you.",
						"<  %s  >" % String(PlayerSettings.FLASH_NAMES[PlayerSettings.flash_mode()]))
			"timing_ring":
				_menu.set_item(i, "Training ring", true,
						"A shrinking ring shows when each enemy hit lands. Practice fights only; off by default.",
						_on_off(PlayerSettings.show_timing_ring(_tuning)))
			"calibrate":
				_menu.set_item(i, "Lag calibration", true,
						"Press Parry with a beat to measure your screen and pad lag. Do this once per setup.",
						"%s ms%s" % [HudStyle.signed_ms(PlayerSettings.latency_compensation_ms(_tuning)),
						"" if PlayerSettings.is_calibrated() else " (default)"])
			"reset_lag":
				_menu.set_item(i, "Reset lag to default", PlayerSettings.is_calibrated(),
						"Forget the measured lag and use the default (%d ms) again." % _tuning.input_latency_compensation_ms)
			"reset_progress":
				_menu.set_item(i, "Reset progress", _allow_reset,
						"Wipe your Relics, unlocked oaths and saved run for a fresh start. Asks twice."
						if _allow_reset else "Only from the main menu's settings, not during a run.")
			"reset":
				_menu.set_item(i, "Reset to defaults", true,
						"Put every key and button back as the game came. Press Confirm twice.",
						"" if _bindings.is_default() else "changed")
			"back":
				_menu.set_item(i, "Back", true, "")
	_show_note()


static func _window_text() -> String:
	var size := PlayerSettings.window_size()
	return "Maximised" if size == Vector2i.ZERO else "%d x %d" % [size.x, size.y]


static func _percent(channel: String) -> String:
	return "<  %d%%  >" % PlayerSettings.channel_percent(channel)


static func _on_off(value: bool) -> String:
	return "ON" if value else "OFF"


# --- controls (card #190) -------------------------------------------------------------------

## The rows of a section by id. Controls: "ctl:<action>" for each rebindable action, then reset and back.
func _rows_of(section: Section) -> Array:
	if section != Section.CONTROLS:
		return SECTION_ROWS[section]
	var rows: Array = []
	for action: StringName in ControlBindings.ACTIONS:
		rows.append("ctl:" + String(action))
	rows.append("reset")
	rows.append("back")
	return rows


## Opens the screen on a section (for pictures and tests).
func open_section(section: Section) -> void:
	_show_section(section)


func _refresh_control(i: int, action: StringName, total: int) -> void:
	var chosen := i == _menu.index
	var waiting := chosen and _capture_kind != "" and _capture_action == action
	var key_text := _column_text(action, ControlBindings.KEY, chosen, waiting)
	var pad_text := _column_text(action, ControlBindings.PAD, chosen, waiting)
	var also := _aliases(action)
	var detail := String(ControlBindings.DETAILS.get(action, ""))
	if not also.is_empty():
		detail += "  Also: " + also + "."
	detail += "   (%d of %d)" % [i + 1, total]
	_menu.set_item(i, String(ControlBindings.LABELS.get(action, String(action))), true, detail,
			"Key  %s%sPad  %s" % [key_text, COLUMN_GAP, pad_text])


## One column's text: the button's name, with arrows on the column Left/Right chose, or a prompt
## while the game waits for the new one.
func _column_text(action: StringName, kind: String, chosen: bool, waiting: bool) -> String:
	var text := HudStyle.input_name(_bindings.primary(action, kind))
	var picked := chosen and kind == _column
	if waiting and picked:
		return "press a %s ..." % ("key" if kind == ControlBindings.KEY else "button")
	if picked:
		return "<  %s  >" % text
	return text


## The other keys and buttons that still do the action's job ("E, Enter"; a stick is just "stick").
func _aliases(action: StringName) -> String:
	var names := PackedStringArray()
	var inputs := _bindings.inputs(action, _column)
	for i: int in range(1, inputs.size()):
		var label := HudStyle.input_name(inputs[i])
		if inputs[i].get("k", "") == "axis" and not ControlBindings.TRIGGER_AXES.has(int(inputs[i].get("code", -1))):
			label = "stick"
		if not names.has(label):
			names.append(label)
	return ", ".join(names)


## Confirm on a control row starts waiting for the new input; Left/Right pick the column.
func _controls_answer(action: StringName, answer: StringName) -> void:
	if answer == &"left" or answer == &"right":
		_column = ControlBindings.PAD if answer == &"right" else ControlBindings.KEY
		Sfx.play("menu_move")
		_note = ""
		_refresh()
		return
	_capture_action = action
	_capture_kind = _column
	_capture_until_ms = Time.get_ticks_msec() + _tuning.rebind_capture_ms
	_set_note("Press the new %s for %s.   Escape or the pad's Menu button: cancel."
			% ["key" if _column == ControlBindings.KEY else "pad button", ControlBindings.LABELS.get(action, String(action))], false)
	Sfx.play("menu_confirm")
	_refresh()


## A key or button arrived while waiting. Rebinds, or says why not and keeps waiting.
func _try_assign(input: Dictionary) -> void:
	var result := _bindings.assign(_capture_action, input)
	if bool(result.ok):
		_end_capture("%s is now %s." % [ControlBindings.LABELS.get(_capture_action, ""), HudStyle.input_name(input)], true)
		return
	_capture_until_ms = Time.get_ticks_msec() + _tuning.rebind_capture_ms
	Sfx.play("locked")
	match String(result.why):
		"reserved":
			_set_note("%s cannot be used (it cancels this step, or is the calibration key). Press another."
					% HudStyle.input_name(input), true)
		"conflict":
			var other: StringName = (result.with as Array)[0]
			var other_name := String(ControlBindings.LABELS.get(other, String(other)))
			if _bindings.can_swap(_capture_action, input):
				_swap = {"action": _capture_action, "input": input, "other": other}
				_capture_kind = ""
				_set_note("%s is already %s. Confirm: swap them.   Back: leave it." % [HudStyle.input_name(input), other_name], true)
			else:
				_set_note("%s is already %s, and they cannot trade places. Press another."
						% [HudStyle.input_name(input), other_name], true)
		_:
			_set_note("That cannot be used. Press another.", true)
	_refresh()


func _do_swap() -> void:
	var action: StringName = _swap.action
	var input: Dictionary = _swap.input
	_swap = {}
	var result := _bindings.assign(action, input, true)
	if bool(result.ok):
		_commit()
		Sfx.play("menu_confirm")
		_set_note("%s is now %s, and %s took the old button." % [ControlBindings.LABELS.get(action, ""),
				HudStyle.input_name(input), ControlBindings.LABELS.get(result.swapped, "")], false)
	else:
		Sfx.play("locked")
		_set_note("They cannot trade places.", true)
	_refresh()


func _end_capture(message: String, changed: bool) -> void:
	_capture_kind = ""
	_capture_action = &""
	if changed:
		_commit()
		Sfx.play("menu_confirm")
	else:
		Sfx.play("menu_cancel")
	_set_note(message, false)
	_refresh()


## Saves the bindings, puts them in the Input Map and redraws every button hint.
func _commit() -> void:
	PlayerSettings.set_control_overrides(_bindings.overrides())
	_bindings.apply_to_input_map(true)
	ButtonPrompts.refresh()


## "Reset to defaults": the first Confirm asks, a second one soon after does it.
func _reset_controls() -> void:
	var now := Time.get_ticks_msec()
	if _bindings.is_default():
		_set_note("Everything is already as the game came.", false)
		Sfx.play("locked")
	elif now <= _reset_until_ms:
		_bindings.reset_all()
		_commit()
		_reset_until_ms = 0
		_set_note("Every key and button is back to the default.", false)
		Sfx.play("menu_confirm")
	else:
		_reset_until_ms = now + _tuning.rebind_reset_confirm_ms
		_set_note("Press Confirm again to put every key and button back to the default.", true)
		Sfx.play("menu_move")
	_refresh()


func _set_note(text: String, problem: bool) -> void:
	_note = text
	_note_is_problem = problem


func _show_note() -> void:
	if _note.is_empty():
		_detail.label_settings.font_color = HudStyle.TEXT_DIM
		return
	_detail.text = _note
	_detail.label_settings.font_color = HudStyle.LATE if _note_is_problem else HudStyle.GOLD
