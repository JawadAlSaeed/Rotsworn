class_name ButtonPrompts
extends Node
## Which buttons the on-screen hints show (DESIGN.md 6, card #45). Registered as the autoload
## "Prompts". Pad buttons while a pad is plugged in and was the last thing used (or was just
## plugged in); keyboard keys once a key is pressed or the last pad is unplugged. Local co-op with
## the keyboard and a pad both playing shows both ("Space / RB").
## The state is static (like PlayerSettings) so HudStyle can read it without the autoload's name;
## with no autoload (unit tests) hints show the keyboard.
## Hints that must follow a change listen with listen() (HintBar, PromptLabel do this).

signal changed

enum Mode { KEYBOARD, PAD, BOTH }

## A stick has to move this far to count as using the pad (drift never switches the hints).
const STICK_THRESHOLD: float = 0.5

static var _pad: bool = false
static var _both: bool = false
static var _node: ButtonPrompts
## --key-prompts: keys stay shown even when a pad moves (pictures on a machine with a pad).
static var _keys_only: bool = false


func _ready() -> void:
	_node = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	# --pad-prompts / --key-prompts (dev tools, for pictures): start with pad buttons or keys shown.
	var args := DevArgs.user_args()
	_keys_only = args.has("--key-prompts")
	_pad = (not Input.get_connected_joypads().is_empty() or args.has("--pad-prompts")) and not _keys_only
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# window_input sees every event before any node can mark it handled (DefenseInput does).
	get_window().window_input.connect(_on_window_input)


func _exit_tree() -> void:
	if _node == self:
		_node = null


static func mode() -> Mode:
	if _both:
		return Mode.BOTH
	return Mode.PAD if _pad else Mode.KEYBOARD


static func shows_pad() -> bool:
	return mode() != Mode.KEYBOARD


static func shows_keys() -> bool:
	return mode() != Mode.PAD


## Local co-op with the keyboard and at least one pad playing: show both kinds of buttons.
static func set_both(on: bool) -> void:
	if on == _both:
		return
	_both = on
	_emit()


## Calls `method` (a method of a node or object, so it is dropped when that is freed) whenever
## the hints change.
static func listen(method: Callable) -> void:
	if _node != null and not _node.changed.is_connected(method):
		_node.changed.connect(method)


## Redraws every hint (a key or button was rebound, card #190).
static func refresh() -> void:
	_emit()


static func _set_pad(on: bool) -> void:
	if on == _pad or (on and _keys_only):
		return
	_pad = on
	if not _both:
		_emit()


static func _emit() -> void:
	if _node != null:
		_node.changed.emit()


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if connected:
		_set_pad(true)
	elif Input.get_connected_joypads().is_empty():
		_set_pad(false)


func _on_window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed():
		_set_pad(false)
	elif event is InputEventJoypadButton and event.is_pressed():
		_set_pad(true)
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) >= STICK_THRESHOLD:
		_set_pad(true)
