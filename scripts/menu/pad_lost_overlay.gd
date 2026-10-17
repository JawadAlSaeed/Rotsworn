class_name PadLostOverlay
extends CanvasLayer
## Local co-op: a player's pad dropped. The game is held under this card until that player is back:
## the pad returns (Main sees it and closes the card), or a button on another pad or the keyboard's
## Confirm takes the seat over, or Pause gives the seat up (their heroes go to the others).

## A device that is not in the roster pressed Confirm / any pad button: it takes the seat.
signal claimed(device: int)
## Pause: the player is dropped from the game.
signal dropped

const TITLE_SIZE: int = 52
const DETAIL_SIZE: int = 30
const DIM := Color(0.0, 0.0, 0.0, 0.8)

var _roster: PlayerRoster
var _title: Label
var _detail: Label


func setup(roster: PlayerRoster) -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_roster = roster
	var bg := ColorRect.new()
	bg.color = DIM
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	add_child(column)
	_title = ListMenu.centred_title("", TITLE_SIZE)
	column.add_child(_title)
	column.add_child(ListMenu.divider())
	_detail = ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_detail)


## Shows which player lost their pad.
func show_player(player: int) -> void:
	_title.text = "P%d: controller disconnected" % (player + 1)
	_detail.text = ("Reconnect it, or press a button on another controller to take over.\n"
			+ "Pause gives P%d's heroes to the others.") % (player + 1)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse or not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed(&"pause", false, true):
		dropped.emit()
		return
	var device := PlayerRoster.device_of(event)
	if _roster.devices.has(device) or device == PlayerRoster.ANY:
		return
	if event is InputEventJoypadButton or event.is_action_pressed(&"menu_confirm", false, true):
		claimed.emit(device)
