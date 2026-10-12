class_name SettingsScreen
extends CanvasLayer
## Settings (DESIGN.md 7.5): volume, fullscreen, the training ring, lag calibration (the same
## beat test as F2 in a fight) and a list of the controls. Everything is saved per machine at once
## (PlayerSettings, user://settings.cfg). Left/right change a value, confirm toggles or opens.

signal closed

const TITLE_SIZE: int = 64
const CONTROLS_SIZE: int = 26
const DETAIL_SIZE: int = 26
const HINT_SIZE: int = 24
const COLUMN_GAP: int = 120
const CONTROL_ROWS: Array[Array] = [
	["Parry", &"defend_parry"], ["Dodge", &"defend_dodge"], ["Jump", &"defend_jump"],
	["Skill press", &"skill_press"], ["Confirm", &"menu_confirm"], ["Back", &"menu_cancel"],
	["Strike (zone)", &"field_strike"], ["Stats overlay", &"debug_overlay"],
]

enum Row { VOLUME, FULLSCREEN, RING, CALIBRATE, RESET_LAG, BACK }

var _tuning: Tuning
var _visuals: CombatVisuals
var _menu: ListMenu
var _input: DefenseInput
var _calibration: CalibrationPanel
var _page: Control


func setup(tuning: Tuning, visuals: CombatVisuals) -> void:
	_tuning = tuning
	_visuals = visuals
	var column := ListMenu.screen_column(self, "Settings", TITLE_SIZE)
	_page = column
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", COLUMN_GAP)
	column.add_child(row)
	_menu = ListMenu.new()
	_menu.centred = false
	row.add_child(_menu)
	row.add_child(HudStyle.make_label(_controls_text(), CONTROLS_SIZE, HudStyle.TEXT))
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	column.add_child(ListMenu.centred_label("Up/Down choose   Left/Right change   %s select   %s back" % [
			HudStyle.binding_text(&"menu_confirm"), HudStyle.binding_text(&"menu_cancel")], HINT_SIZE, HudStyle.TEXT_DIM))
	var blank: Array[Dictionary] = []
	for i: int in Row.size():
		blank.append({})
	_menu.set_items(blank, detail)
	_refresh()

	_input = DefenseInput.new()
	_input.name = "DefenseInput"
	add_child(_input)
	_calibration = CalibrationPanel.new()
	_calibration.name = "Calibration"
	add_child(_calibration)
	_calibration.setup(_visuals, _tuning, _input)
	_calibration.closed.connect(_on_calibration_closed)


func _unhandled_input(event: InputEvent) -> void:
	if _calibration.is_running():
		_calibration.handle_input(event)
		get_viewport().set_input_as_handled()
		return
	var answer := _menu.handle(event)
	if answer == &"":
		return
	if answer == &"cancel":
		Sfx.play("menu_cancel")
		closed.emit()
		return
	var step := -1 if answer == &"left" else 1
	match _menu.index:
		Row.VOLUME:
			if answer != &"confirm":
				PlayerSettings.set_volume_percent(PlayerSettings.volume_percent() + step * PlayerSettings.VOLUME_STEP_PERCENT)
				Sfx.play("menu_move")
		Row.FULLSCREEN:
			PlayerSettings.set_fullscreen(not PlayerSettings.fullscreen())
			Sfx.play("menu_confirm")
		Row.RING:
			PlayerSettings.set_show_timing_ring(not PlayerSettings.show_timing_ring(_tuning))
			Sfx.play("menu_confirm")
		Row.CALIBRATE:
			if answer == &"confirm":
				Sfx.play("menu_confirm")
				_page.visible = false
				_calibration.open()
		Row.RESET_LAG:
			if answer == &"confirm":
				if PlayerSettings.is_calibrated():
					PlayerSettings.reset_latency_compensation()
					Sfx.play("menu_confirm")
				else:
					Sfx.play("locked")
		Row.BACK:
			if answer == &"confirm":
				Sfx.play("menu_cancel")
				closed.emit()
				return
	_refresh()


func _on_calibration_closed() -> void:
	_page.visible = true
	_refresh()


func _refresh() -> void:
	var lag := PlayerSettings.latency_compensation_ms(_tuning)
	var calibrated := PlayerSettings.is_calibrated()
	_menu.set_item(Row.VOLUME, "Volume:  < %d%% >" % PlayerSettings.volume_percent(), true,
			"Left/Right: louder or quieter.")
	_menu.set_item(Row.FULLSCREEN, "Fullscreen:  %s" % _on_off(PlayerSettings.fullscreen()), true,
			"Fill the whole screen, or a normal window.")
	_menu.set_item(Row.RING, "Training ring:  %s" % _on_off(PlayerSettings.show_timing_ring(_tuning)), true,
			"A shrinking ring that shows when each enemy hit lands. Off is the real game.")
	_menu.set_item(Row.CALIBRATE, "Lag calibration:  %s ms%s" % [HudStyle.signed_ms(lag), "" if calibrated else " (default)"],
			true, "Press Parry with a beat to measure your screen and pad lag. Do this once per setup.")
	_menu.set_item(Row.RESET_LAG, "Reset lag to default", calibrated,
			"Forget the measured lag and use the default (%d ms) again." % _tuning.input_latency_compensation_ms)
	_menu.set_item(Row.BACK, "Back", true, "")


static func _on_off(value: bool) -> String:
	return "ON" if value else "OFF"


static func _controls_text() -> String:
	var lines := PackedStringArray(["CONTROLS", ""])
	for pair: Array in CONTROL_ROWS:
		lines.append("%s:  %s" % [pair[0], HudStyle.binding_text(pair[1])])
	lines.append("Move:  WASD / arrows / left stick")
	lines.append("")
	lines.append("Change keys: coming later.")
	return "\n".join(lines)
