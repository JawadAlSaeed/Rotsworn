class_name CalibrationScreen
extends CanvasLayer
## The lag calibration (CalibrationPanel) on a screen of its own, over the menu's background: what
## the first New Run's offer opens (DESIGN.md 3.2, card #204). Settings opens the same panel over
## itself. Confirm saves the measurement (for the kind of input pressed), Back leaves without
## saving; either way `closed` comes once.

signal closed

var _defense_input: DefenseInput
var _panel: CalibrationPanel


func setup(visuals: CombatVisuals, tuning: Tuning) -> void:
	add_child(MenuBackdrop.new())
	_defense_input = DefenseInput.new()
	_defense_input.name = "DefenseInput"
	add_child(_defense_input)
	_panel = CalibrationPanel.new()
	_panel.name = "Calibration"
	add_child(_panel)
	_panel.setup(visuals, tuning, _defense_input)
	_panel.closed.connect(closed.emit)


func _ready() -> void:
	_panel.open()


func _unhandled_input(event: InputEvent) -> void:
	if _panel.is_running():
		_panel.handle_input(event)
		get_viewport().set_input_as_handled()
