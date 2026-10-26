class_name PadRumble
extends Node
## Controller buzz (autoload "Rumble", DESIGN.md 7.14, card #299). Patterns live in
## data/presentation/rumble.tres; the player's Vibration setting (Settings > Controls > Controller)
## scales them, 0 is off. In co-op each pad buzzes only for its own player's heroes (set_party);
## a moment for the whole party (the Team Ultimate, a boss's rage) buzzes every pad on this machine.
## The state is static like ButtonPrompts, so presentation calls PadRumble.hero(...) without the
## autoload's name; with no autoload (unit tests, --check-only) every call does nothing.
## Bot and picture runs (--autoplay, --shots, --screen) never buzz: the owner may be playing
## something else with that pad while one runs.

const SET_PATH := "res://data/presentation/rumble.tres"

static var _node: PadRumble

var _set: RumbleSet
var _mixer := RumbleMixer.new()
## The joypad that sent the last input (-1: none yet) and whether a pad, not a key, was last used.
var _last_pad: int = -1
var _pad_in_use: bool = false
## Who plays which hero in the fight on screen (null: everything goes to the pad in use).
var _roster: PlayerRoster
var _owners: Dictionary = {}
## Device -> what it was last told: {motors: Vector2(weak, strong), until_ms}, so a pad is only told
## again when that changes or runs out.
var _sent: Dictionary = {}
var _quiet: bool = false
## False while the game window is not in front: the owner may be using the pad in another game.
var _focused: bool = true


func _ready() -> void:
	_node = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := DevArgs.user_args()
	for arg: String in args:
		if arg.begins_with("--autoplay") or arg.begins_with("--shots") or arg.begins_with("--screen") or arg == "--no-rumble":
			_quiet = true
	_quiet = _quiet or DisplayServer.get_name() == "headless"
	_set = load(SET_PATH) as RumbleSet if ResourceLoader.exists(SET_PATH) else null
	if _set == null:
		push_warning("PadRumble: no buzz patterns at %s; the controller stays still" % SET_PATH)
		_set = RumbleSet.new()
	# A pad plugged in at the start counts as the pad in use until a key is pressed (as the hints do).
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		_last_pad = pads[0]
		_pad_in_use = true
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	get_window().window_input.connect(_on_window_input)


func _exit_tree() -> void:
	_stop_all()
	if _node == self:
		_node = null


func _notification(what: int) -> void:
	# Out of focus the pad stays still (the owner may be playing something else with it): the buzz
	# playing stops, and none starts until the window is in front again.
	# Both kinds, like Main's pause: on Windows the first focus-in may come only as the window's (the
	# app's can arrive before any main loop), so focus is never read at start (it starts true).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_focused = false
		_stop_all()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_focused = true


## The fight's players: `owners` maps a party member id to its player of `roster`.
static func set_party(roster: PlayerRoster, owners: Dictionary) -> void:
	if _node != null:
		_node._roster = roster
		_node._owners = owners.duplicate()


## No fight on screen: a buzz goes to the pad in use.
static func clear_party() -> void:
	if _node != null:
		_node._roster = null
		_node._owners = {}


## Buzzes `pattern` for the player who plays hero `id`.
static func hero(pattern: String, id: int) -> void:
	heroes(pattern, [id] as Array[int])


## Buzzes `pattern` once on each pad behind `ids` (two heroes of one player buzz their pad once).
static func heroes(pattern: String, ids: Array[int]) -> void:
	if _node == null:
		return
	var pads: Array[int] = []
	for id: int in ids:
		for pad: int in _node._pads_of_player(int(_node._owners.get(id, 0))):
			if not pads.has(pad):
				pads.append(pad)
	_node._play(pattern, pads)


## Buzzes `pattern` for player `player` of `roster` where no fight party is set (the First Strike
## ring on a name card, DESIGN.md 8.22): that player's pad only, as a skill press in a fight.
static func for_player(pattern: String, roster: PlayerRoster, player: int) -> void:
	if _node == null:
		return
	_node._play(pattern, RumbleMixer.pads_of_player(roster, player, _node._last_pad, _node._pad_in_use))


## Buzzes `pattern` on every pad playing on this machine.
static func everyone(pattern: String) -> void:
	if _node == null:
		return
	var pads: Array[int] = []
	var players: Array[int] = [0]
	if _node._roster != null:
		players = _node._roster.local_players()
	for player: int in players:
		for pad: int in _node._pads_of_player(player):
			if not pads.has(pad):
				pads.append(pad)
	_node._play(pattern, pads)


## The Vibration setting changed: buzz the pad in use once at the new strength.
static func test() -> void:
	if _node != null and _node._last_pad >= 0:
		_node._play(_node._set.test_pattern, [_node._last_pad] as Array[int])


func _pads_of_player(player: int) -> Array[int]:
	return RumbleMixer.pads_of_player(_roster, player, _last_pad, _pad_in_use)


func _play(pattern_name: String, pads: Array[int]) -> void:
	if _quiet or not _focused or pads.is_empty():
		return
	var pattern := _set.find(pattern_name)
	if pattern == null:
		push_warning("PadRumble: unknown buzz '%s' (add it to %s)" % [pattern_name, SET_PATH])
		return
	var scale := float(PlayerSettings.rumble_percent()) / 100.0 * float(_set.strength_percent) / 100.0
	var now := Time.get_ticks_msec()
	for pad: int in pads:
		_mixer.play(pad, pattern.steps, now, scale, _set.max_per_pad)
	# Told at once: a short buzz (35 ms) asked for from a scene's _process would otherwise wait for
	# the next frame, start late, and be gone entirely after a slow frame.
	_flush()


func _process(_delta: float) -> void:
	_flush()


## Tells each pad its motor levels when they change (or what it was told runs out).
func _flush() -> void:
	if _mixer.is_idle():
		return
	var now := Time.get_ticks_msec()
	var levels := _mixer.levels(now)
	for device: int in levels:
		var level: Vector3 = levels[device]
		var motors := Vector2(level.x, level.y)
		var sent: Dictionary = _sent.get(device, {})
		# Told again when the levels change, or when what it was told runs out (a step that repeats).
		if not sent.is_empty() and motors == sent.motors and now < int(sent.until_ms):
			continue
		if motors == Vector2.ZERO:
			Input.stop_joy_vibration(device)
			_sent.erase(device)
		else:
			# The pad stops by itself when this step ends, even if the game hitches.
			var seconds := maxf(level.z, 0.02)
			Input.start_joy_vibration(device, motors.x, motors.y, seconds + 0.05)
			_sent[device] = {"motors": motors, "until_ms": now + roundi(seconds * 1000.0)}


func _stop_all() -> void:
	for device: int in _mixer.stop_all():
		Input.stop_joy_vibration(device)
	_sent.clear()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_last_pad = device
		_pad_in_use = true
	elif device == _last_pad:
		Input.stop_joy_vibration(device)
		var pads := Input.get_connected_joypads()
		_last_pad = pads[0] if not pads.is_empty() else -1
		_pad_in_use = _last_pad >= 0


func _on_window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed():
		_pad_in_use = false
	elif event is InputEventJoypadButton and event.is_pressed():
		_pad_in_use = true
		_last_pad = event.device
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) >= ButtonPrompts.STICK_THRESHOLD:
		_pad_in_use = true
		_last_pad = event.device
