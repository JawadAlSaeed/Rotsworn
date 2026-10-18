class_name JoinScreen
extends CanvasLayer
## Join Online (DESIGN.md 9.2): type the host's address (it is remembered) and press Enter. While
## connecting the screen says so; a refusal or failure is shown here. Esc (or the pad's Back)
## goes back. Main listens to Net for the welcome.

## The player asked to connect to `address`.
signal connect_requested(address: String)
signal back

const TITLE_SIZE: int = 64
const FIELD_SIZE: int = 40
const TEXT_SIZE: int = 28
const HINT_SIZE: int = 24
const FIELD_WIDTH: float = 520.0

var _field: LineEdit
var _status: Label
var _busy: bool = false


func setup(address: String) -> void:
	var column := ListMenu.screen_column(self, "Join Online", TITLE_SIZE)
	column.add_child(ListMenu.centred_label("Host address", TEXT_SIZE, HudStyle.TEXT_DIM))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	_field = LineEdit.new()
	_field.text = address
	_field.custom_minimum_size = Vector2(FIELD_WIDTH, 0.0)
	_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_field.add_theme_font_size_override("font_size", FIELD_SIZE)
	_field.add_theme_stylebox_override("normal", HudStyle.panel(HudStyle.PANEL_BG, HudStyle.PANEL_BORDER, 2, 14))
	_field.add_theme_stylebox_override("focus", HudStyle.panel(Color(0, 0, 0, 0), HudStyle.GOLD, 2, 14))
	_field.add_theme_stylebox_override("read_only", HudStyle.panel(HudStyle.PANEL_BG, HudStyle.TEXT_DIM, 2, 14))
	_field.text_submitted.connect(_on_submitted)
	row.add_child(_field)
	_status = ListMenu.centred_label("", TEXT_SIZE, HudStyle.TEXT)
	column.add_child(_status)
	column.add_child(ListMenu.centred_label(
			"Type the address the host's screen shows, then Enter (A on a pad).   Esc (B): back\n"
			+ "Same Wi-Fi: it just works. Over the internet: both use Tailscale (or the host opens the port).",
			HINT_SIZE, HudStyle.TEXT_DIM))
	_field.call_deferred("grab_focus")
	_field.call_deferred("select_all")


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
	# The text field takes most keys, so Back is read here: Esc, or the pad's Back button.
	var key := event as InputEventKey
	var pad_back := event is InputEventJoypadButton and event.is_action_pressed(&"menu_cancel", false, true)
	if (key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE) or pad_back:
		get_viewport().set_input_as_handled()
		Sfx.play("menu_cancel")
		back.emit()
	elif event is InputEventJoypadButton and event.is_action_pressed(&"menu_confirm", false, true):
		# A pad cannot press Enter in the text field: its confirm button connects (a remembered
		# address, or the one a dropped player's seat waits at).
		get_viewport().set_input_as_handled()
		_on_submitted(_field.text)
