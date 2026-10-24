class_name MouseCursor
extends Node
## Shows the mouse pointer only when it is useful (DESIGN.md 6.2, card #202). Registered as the
## autoload "Pointer". It hides while a key or a pad is being used and shows again the moment the
## mouse moves or clicks; it stays hidden in fights, which are keyboard and pad games
## (Main tells it with set_menus_allowed()). The state is static (like ButtonPrompts) so tests can
## read it without the autoload; nothing is done without a window (headless).

static var _mouse_active: bool = true
static var _menus_allowed: bool = true
static var _shown: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# window_input sees every event before any node can mark it handled (like ButtonPrompts).
	get_window().window_input.connect(_on_window_input)


func _exit_tree() -> void:
	# Never leave the pointer hidden behind a closed game.
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Main: true on the menu screens, the pause menu, the backpack and the map; false while a fight
## is being played.
static func set_menus_allowed(allowed: bool) -> void:
	if allowed == _menus_allowed:
		return
	_menus_allowed = allowed
	_apply()


## True while the pointer is shown.
static func is_shown() -> bool:
	return _shown


## What the last event changed: the mouse was used, or another device was.
static func note_event(event: InputEvent) -> void:
	var activity := MenuMouse.activity(event)
	if activity == MenuMouse.Activity.NONE:
		return
	var mouse := activity == MenuMouse.Activity.MOUSE
	if mouse == _mouse_active:
		return
	_mouse_active = mouse
	_apply()


static func _apply() -> void:
	var want := MenuMouse.pointer_visible(_mouse_active, _menus_allowed)
	if want == _shown:
		return
	_shown = want
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if want else Input.MOUSE_MODE_HIDDEN


func _on_window_input(event: InputEvent) -> void:
	note_event(event)
