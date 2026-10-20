class_name JoinScreen
extends CanvasLayer
## Join Online (DESIGN.md 9.2): type the host's address (it is remembered) and press Enter. While
## connecting the screen says so; a refusal or failure is shown here. Esc (or the pad's Back)
## goes back. Main listens to Net for the welcome.
## Phase 22: the buttons are a hint bar along the bottom (Confirm: Connect, or Rejoin after a lost
## connection; Back), not key names written in the text.

## The player asked to connect to `address`.
signal connect_requested(address: String)
signal back

const TITLE_SIZE: int = 64
const FIELD_SIZE: int = 40
const TEXT_SIZE: int = 28
const FIELD_WIDTH: float = 520.0

var _field: LineEdit
var _status: Label
var _footer: HintBar
var _busy: bool = false
## After a lost connection: the Confirm hint says Rejoin (the address is the seat's).
var _rejoin: bool = false


## `rejoin`: the screen opened because the connection to the host was lost mid-run.
func setup(address: String, rejoin: bool = false) -> void:
	_rejoin = rejoin
	var column := ListMenu.screen_column(self, "Join Online", TITLE_SIZE)
	column.add_child(ListMenu.centred_label("Host address", TEXT_SIZE, HudStyle.TEXT_DIM))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	_field = LineEdit.new()
	_field.text = address
	_field.custom_minimum_size = Vector2(FIELD_WIDTH, 0.0)
	_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_field.add_theme_font_size_override("font_size", HudStyle.scaled(FIELD_SIZE))
	_field.add_theme_stylebox_override("normal", HudStyle.panel(HudStyle.PANEL_BG, HudStyle.PANEL_BORDER, 2, 14))
	_field.add_theme_stylebox_override("focus", HudStyle.panel(Color(0, 0, 0, 0), HudStyle.GOLD, 2, 14))
	_field.add_theme_stylebox_override("read_only", HudStyle.panel(HudStyle.PANEL_BG, HudStyle.TEXT_DIM, 2, 14))
	_field.text_submitted.connect(_on_submitted)
	row.add_child(_field)
	_status = ListMenu.centred_label("", TEXT_SIZE, HudStyle.TEXT)
	column.add_child(_status)
	_footer = ListMenu.screen_footer(self, footer_entries(_rejoin, ButtonPrompts.shows_pad(), ButtonPrompts.shows_keys()))
	ButtonPrompts.listen(_refresh_footer)
	_field.call_deferred("grab_focus")
	_field.call_deferred("select_all")


## The hint bar: Confirm (Connect, or Rejoin) and Back. The text field takes Backspace, so on the
## keyboard Back is Escape, the Pause key; a pad's Back is its usual button. Pure.
static func footer_entries(rejoin: bool, shows_pad: bool, shows_keys: bool) -> Array:
	var back_action := &"menu_cancel" if shows_pad and not shows_keys else &"pause"
	return [[&"menu_confirm", "Rejoin" if rejoin else "Connect"], [back_action, "Back"]]


func _refresh_footer() -> void:
	_footer.set_entries(footer_entries(_rejoin, ButtonPrompts.shows_pad(), ButtonPrompts.shows_keys()))


## Shows a message (a refusal, a failure) and lets the player try again.
func show_problem(text: String) -> void:
	_busy = false
	_field.editable = true
	_status.text = text
	_status.label_settings.font_color = HudStyle.LATE
	_field.grab_focus()


## Shows how things stand (not a problem): "Back in, catching up ..." while the host sends the game.
func show_status(text: String) -> void:
	_status.text = text
	_status.label_settings.font_color = HudStyle.TEXT


## Connects to `address` as if it had been typed and Enter pressed (the bot rejoining).
func submit(address: String) -> void:
	_field.text = address
	_on_submitted(address)


func _on_submitted(text: String) -> void:
	if _busy or text.strip_edges().is_empty():
		return
	_busy = true
	_field.editable = false
	_status.text = "Connecting to %s ..." % text.strip_edges()
	_status.label_settings.font_color = HudStyle.TEXT
	Sfx.play("menu_confirm")
	connect_requested.emit(text.strip_edges())


func _input(event: InputEvent) -> void:
	# The text field takes most keys, so Back is read here: Escape (the Pause key), or the pad's Back
	# or Menu button.
	var key := event as InputEventKey
	var escape := key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE
	# On a pad, Back and Menu (Pause) both leave; a key other than Escape types into the field.
	var pad_back := event is InputEventJoypadButton and (event.is_action_pressed(&"menu_cancel", false, true)
			or event.is_action_pressed(&"pause", false, true))
	if escape or pad_back or MenuMouse.is_back(event):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_cancel")
		back.emit()
	elif event is InputEventJoypadButton and event.is_action_pressed(&"menu_confirm", false, true):
		# A pad cannot press Enter in the text field: its confirm button connects (a remembered
		# address, or the one a dropped player's seat waits at).
		get_viewport().set_input_as_handled()
		_on_submitted(_field.text)
