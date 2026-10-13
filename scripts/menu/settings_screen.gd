class_name SettingsScreen
extends CanvasLayer
## Settings (DESIGN.md 7.5): volume, fullscreen, lag calibration (the same
## beat test as F2 in a fight) and a list of the controls. Everything is saved per machine at once
## (PlayerSettings, user://settings.cfg). Left/right change a value, confirm toggles or opens.

signal closed

const TITLE_SIZE: int = 64
const CONTROLS_SIZE: int = 26
const DETAIL_SIZE: int = 26
const COLUMN_GAP: int = 120
const CONTROL_ROWS: Array[Array] = [
	["Attack", &"fight_attack"], ["Skills", &"fight_skills"], ["Items", &"fight_items"],
	["Ultimate", &"fight_ultimate"],
	["Parry", &"defend_parry"], ["Dodge", &"defend_dodge"], ["Jump", &"defend_jump"],
	["Skill press", &"skill_press"], ["Confirm", &"menu_confirm"], ["Back", &"menu_cancel"],
	["Strike (zone)", &"field_strike"], ["Move (zone)", &"@move"], ["Pause", &"pause"],
	["Stats overlay", &"debug_overlay"],
]
const CONTROLS_TITLE_SIZE: int = 24
const CONTROLS_GAP: int = 10

enum Row { VOLUME, FULLSCREEN, CALIBRATE, RESET_LAG, BACK }

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
	row.add_child(_controls_panel())
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	ListMenu.screen_footer(self, [[&"@updown", "Choose"], [&"@leftright", "Change"], [&"menu_confirm", "Select"],
			[&"menu_cancel", "Back"]])
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
	_menu.set_item(Row.VOLUME, "Volume", true, "Louder or quieter.", "<  %d%%  >" % PlayerSettings.volume_percent())
	_menu.set_item(Row.FULLSCREEN, "Fullscreen", true, "Fill the whole screen, or a normal window.",
			_on_off(PlayerSettings.fullscreen()))
	_menu.set_item(Row.CALIBRATE, "Lag calibration", true,
			"Press Parry with a beat to measure your screen and pad lag. Do this once per setup.",
			"%s ms%s" % [HudStyle.signed_ms(lag), "" if calibrated else " (default)"])
	_menu.set_item(Row.RESET_LAG, "Reset lag to default", calibrated,
			"Forget the measured lag and use the default (%d ms) again." % _tuning.input_latency_compensation_ms)
	_menu.set_item(Row.BACK, "Back", true, "")


static func _on_off(value: bool) -> String:
	return "ON" if value else "OFF"


## The controls, one button chip per action (keyboard keys or pad buttons, see ButtonPrompts).
static func _controls_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.PANEL_BG, HudStyle.PANEL_BORDER, 2, 22))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", CONTROLS_GAP)
	panel.add_child(box)
	box.add_child(HudStyle.make_label("CONTROLS", CONTROLS_TITLE_SIZE, HudStyle.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", CONTROLS_GAP)
	box.add_child(grid)
	for pair: Array in CONTROL_ROWS:
		grid.add_child(HudStyle.make_label(String(pair[0]), CONTROLS_SIZE, HudStyle.TEXT))
		var chips := HintBar.new([[StringName(pair[1]), ""]], CONTROLS_SIZE)
		chips.alignment = BoxContainer.ALIGNMENT_BEGIN
		grid.add_child(chips)
	box.add_child(HudStyle.make_label("Changing keys comes later.", CONTROLS_TITLE_SIZE, HudStyle.TEXT_DIM))
	return panel
