class_name ControlBindings
extends RefCounted
## What every player action is bound to, and the rules for changing it (card #190, DESIGN.md 6).
## Pure: it holds plain Dictionaries and never touches a window, so it is tested without one.
## The Input Map is only read when a model is built from it (from_input_map) and written by
## apply_to_input_map(); everything else works on the model.
##
## Each action has an ordered list of keys and an ordered list of pad inputs (buttons, triggers and
## the stick directions the project binds). The FIRST of each list is the one the player rebinds
## and the one the button hints show (HudStyle.binding_parts reads the first key and the first pad
## button). The rest are aliases that keep working (arrows next to WASD, the stick next to the
## D-pad). An input is a Dictionary: {"k": "key", "code": physical keycode}, {"k": "btn", "code":
## button index} or {"k": "axis", "code": axis, "dir": 1 or -1}.
##
## Rebinding never leaves an action without a key or a pad input (it replaces, it does not clear),
## so Confirm, Back and Pause always stay reachable. Two actions that can be needed at the same
## moment (a GROUP) never share an input; Parry, Dodge and Jump, for example. Pads are not told
## apart: a rebinding applies to every pad (per-device rebinding is out of scope).

const KEY := "key"
const PAD := "pad"

## The actions the player can rebind, in the order the Controls list shows them.
const ACTIONS: Array[StringName] = [
	&"fight_attack", &"fight_skills", &"fight_items", &"fight_ultimate",
	&"defend_parry", &"defend_dodge", &"defend_jump", &"skill_press",
	&"move_up", &"move_down", &"move_left", &"move_right",
	&"field_strike", &"field_pickup", &"party_menu",
	&"menu_up", &"menu_down", &"menu_left", &"menu_right",
	&"menu_confirm", &"menu_cancel", &"pause",
	&"party_attributes", &"party_skills", &"item_move", &"item_turn_left", &"item_turn_right",
	&"debug_overlay",
]

const LABELS := {
	&"fight_attack": "Attack", &"fight_skills": "Skills (fight)", &"fight_items": "Items (fight)",
	&"fight_ultimate": "Ultimate", &"defend_parry": "Parry", &"defend_dodge": "Dodge",
	&"defend_jump": "Jump", &"skill_press": "Skill press", &"move_up": "Walk up",
	&"move_down": "Walk down", &"move_left": "Walk left", &"move_right": "Walk right",
	&"field_strike": "Strike (zone)", &"field_pickup": "Pick up (zone)", &"party_menu": "Backpack",
	&"menu_up": "Menu up", &"menu_down": "Menu down", &"menu_left": "Menu left",
	&"menu_right": "Menu right", &"menu_confirm": "Confirm", &"menu_cancel": "Back / run",
	&"pause": "Pause", &"party_attributes": "Attributes screen", &"party_skills": "Skills screen",
	&"item_move": "Move item", &"item_turn_left": "Turn item left", &"item_turn_right": "Turn item right",
	&"debug_overlay": "Stats overlay",
}

## One line for the list's footer: where the button is used.
const DETAILS := {
	&"fight_attack": "On your turn in a fight: a basic attack.",
	&"fight_skills": "On your turn in a fight: open the skills.",
	&"fight_items": "On your turn in a fight: open the backpack items.",
	&"fight_ultimate": "On your turn in a fight: the ultimate, when it is ready.",
	&"defend_parry": "While an enemy attacks: parry the hit.",
	&"defend_dodge": "While an enemy attacks: dodge the hit.",
	&"defend_jump": "While an enemy attacks: jump over a low hit.",
	&"skill_press": "During your own skills: the timed presses.",
	&"move_up": "In a zone: walk up.", &"move_down": "In a zone: walk down.",
	&"move_left": "In a zone: walk left.", &"move_right": "In a zone: walk right.",
	&"field_strike": "In a zone: strike a roaming enemy to start the fight with the advantage.",
	&"field_pickup": "In a zone: pick up what glints nearby.",
	&"party_menu": "On the map, in a zone and in a shop: open the party and the backpack.",
	&"menu_up": "In every menu: move up.", &"menu_down": "In every menu: move down.",
	&"menu_left": "In every menu: left, or change a setting.",
	&"menu_right": "In every menu: right, or change a setting.",
	&"menu_confirm": "In every menu: choose. Cannot be left without a key and a button.",
	&"menu_cancel": "In every menu: go back. In a fight, hold it on your turn to run.",
	&"pause": "In a fight, a zone and on the map: open the pause menu.",
	&"party_attributes": "On the party screen: open the attributes screen.",
	&"party_skills": "On the party screen: open the skills screen.",
	&"item_move": "In the backpack: pick an item up and put it down.",
	&"item_turn_left": "In the backpack: turn the item in hand. In settings: the section before.",
	&"item_turn_right": "In the backpack: turn the item in hand. In settings: the next section.",
	&"debug_overlay": "In a fight: the stats overlay.",
}

## Actions needed at the same moment. An input given to one of them is refused (or swapped) when
## another in the same group already has it. Menus, defence and skill presses never run together,
## so the same button may do different things in different groups (W jumps in a fight and walks
## up a menu). Pause and the stats overlay are live almost everywhere, so they are in every group.
const GROUPS: Array = [
	[&"defend_parry", &"defend_dodge", &"defend_jump", &"pause", &"debug_overlay"],
	[&"skill_press", &"pause", &"debug_overlay"],
	[&"fight_attack", &"fight_skills", &"fight_items", &"fight_ultimate", &"menu_up", &"menu_down",
			&"menu_left", &"menu_right", &"menu_confirm", &"menu_cancel", &"pause", &"debug_overlay"],
	[&"move_up", &"move_down", &"move_left", &"move_right", &"field_strike", &"field_pickup",
			&"party_menu", &"pause", &"debug_overlay"],
	[&"menu_up", &"menu_down", &"menu_left", &"menu_right", &"menu_confirm", &"menu_cancel",
			&"pause", &"party_menu", &"party_attributes", &"party_skills", &"item_move",
			&"item_turn_left", &"item_turn_right", &"debug_overlay"],
]

## Pairs that are meant to share a button: Confirm is also Attack on the action menu, and Escape
## is both Back and Pause (Main reads Pause first).
const SHARED: Array = [[&"fight_attack", &"menu_confirm"], [&"menu_cancel", &"pause"]]

## These always keep a key and a pad input.
const REQUIRED: Array[StringName] = [&"menu_confirm", &"menu_cancel", &"pause"]

## Escape and the pad's Menu button cancel the "press the new button" step, and F2 is the lag
## calibration key, so none of them can be given to an action. They keep their default jobs
## (Pause) until "Reset to defaults".
const RESERVED_KEYS: Array[int] = [KEY_ESCAPE, KEY_F2]
const RESERVED_BUTTONS: Array[int] = [JOY_BUTTON_START]
## The pad inputs that can be captured besides buttons: the two triggers (sticks drift).
const TRIGGER_AXES: Array[int] = [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
## How far a trigger has to be pushed to count as the press being captured.
const TRIGGER_CAPTURE_VALUE: float = 0.6

## The model in use by the game (set by install()).
static var shared: ControlBindings

var _defaults: Dictionary = {}
var _current: Dictionary = {}


## `defaults`: {action: {"key": [inputs], "pad": [inputs]}} (see from_input_map).
func _init(defaults: Dictionary = {}) -> void:
	_defaults = _copy(defaults)
	_current = _copy(defaults)


## The model for the game as defined in project.godot, from the Input Map as it is right now:
## call it before anything has been rebound.
static func from_input_map() -> ControlBindings:
	var defaults := {}
	for action: StringName in ACTIONS:
		var lists := {KEY: [] as Array[Dictionary], PAD: [] as Array[Dictionary]}
		if InputMap.has_action(action):
			for ev: InputEvent in InputMap.action_get_events(action):
				var input := input_from_event(ev)
				if not input.is_empty():
					(lists[kind_of(input)] as Array[Dictionary]).append(input)
		defaults[String(action)] = lists
	return ControlBindings.new(defaults)


## Builds `shared` from the Input Map, puts the saved changes on it and applies them. Called once
## at start-up (PlayerSettings) before any screen reads the Input Map.
static func install(saved: Dictionary) -> ControlBindings:
	shared = from_input_map()
	shared.load_overrides(saved)
	shared.apply_to_input_map()
	return shared


## The model the game uses (built from the Input Map on first use).
static func current() -> ControlBindings:
	if shared == null:
		shared = from_input_map()
	return shared


# --- inputs ---------------------------------------------------------------------------------

## The input an Input Map event stands for ({} for a kind of event the game does not rebind).
static func input_from_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var key := ev as InputEventKey
		var code := int(key.physical_keycode) if key.physical_keycode != KEY_NONE else int(key.keycode)
		return {} if code == KEY_NONE else {"k": "key", "code": code}
	if ev is InputEventJoypadButton:
		return {"k": "btn", "code": int((ev as InputEventJoypadButton).button_index)}
	if ev is InputEventJoypadMotion:
		var motion := ev as InputEventJoypadMotion
		return {"k": "axis", "code": int(motion.axis), "dir": 1 if motion.axis_value >= 0.0 else -1}
	return {}


## The Input Map event for an input. Pad events match every pad (device -1: a new event would
## otherwise only match pad 0).
static func event_from_input(input: Dictionary) -> InputEvent:
	match String(input.get("k", "")):
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(input.get("code", 0)) as Key
			key.device = -1
			return key
		"btn":
			var button := InputEventJoypadButton.new()
			button.button_index = int(input.get("code", 0)) as JoyButton
			button.device = -1
			return button
		"axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(input.get("code", 0)) as JoyAxis
			motion.axis_value = float(input.get("dir", 1))
			motion.device = -1
			return motion
	return null


## KEY or PAD (whichever list the input belongs in), "" for a bad input.
static func kind_of(input: Dictionary) -> String:
	match String(input.get("k", "")):
		"key":
			return KEY
		"btn", "axis":
			return PAD
	return ""


static func same(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("k", "")) == String(b.get("k", "")) and int(a.get("code", -1)) == int(b.get("code", -2)) \
			and int(a.get("dir", 0)) == int(b.get("dir", 0))


## "" when the input can be given to an action, else why not: "unsupported" (not a key, a pad
## button or a trigger) or "reserved" (Escape, F2 and the pad's Menu button).
static func capture_problem(input: Dictionary) -> String:
	var code := int(input.get("code", -1))
	match String(input.get("k", "")):
		"key":
			if code <= 0:
				return "unsupported"
			return "reserved" if RESERVED_KEYS.has(code) else ""
		"btn":
			if code < 0 or code >= JOY_BUTTON_SDL_MAX:
				return "unsupported"
			return "reserved" if RESERVED_BUTTONS.has(code) else ""
		"axis":
			return "" if TRIGGER_AXES.has(code) and int(input.get("dir", 0)) == 1 else "unsupported"
	return "unsupported"


# --- reading --------------------------------------------------------------------------------

## The action's inputs of one kind (KEY or PAD), the one the player rebinds first.
func inputs(action: StringName, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var entry: Dictionary = _current.get(String(action), {})
	for input: Dictionary in entry.get(kind, []):
		out.append(input)
	return out


## The first input of a kind ({} if none): what the hints show and what a rebinding replaces.
func primary(action: StringName, kind: String) -> Dictionary:
	var list := inputs(action, kind)
	return list[0] if not list.is_empty() else {}


## The default first input of a kind.
func default_primary(action: StringName, kind: String) -> Dictionary:
	var entry: Dictionary = _defaults.get(String(action), {})
	var list: Array = entry.get(kind, [])
	return list[0] if not list.is_empty() else {}


## True while nothing is changed from project.godot.
func is_default() -> bool:
	return overrides().is_empty()


## True when `action` is not changed from its default.
func is_action_default(action: StringName) -> bool:
	return _same_entry(_current.get(String(action), {}), _defaults.get(String(action), {}))


## The actions (other than `action`) in a group with it that already hold `input` in this kind of
## list. Pairs meant to share a button (SHARED) are left out.
func conflicts(action: StringName, input: Dictionary) -> Array[StringName]:
	var kind := kind_of(input)
	var out: Array[StringName] = []
	for group: Array in GROUPS:
		if not group.has(action):
			continue
		for other: StringName in group:
			if other == action or out.has(other) or _may_share(action, other):
				continue
			for held: Dictionary in inputs(other, kind):
				if same(held, input):
					out.append(other)
					break
	return out


## Every pair of actions in a group that hold the same input (empty for the defaults and after any
## successful rebinding).
func conflict_pairs() -> Array:
	var out: Array = []
	for action: StringName in ACTIONS:
		for kind: String in [KEY, PAD]:
			for input: Dictionary in inputs(action, kind):
				for other: StringName in conflicts(action, input):
					if ACTIONS.find(other) > ACTIONS.find(action):
						out.append([action, other])
	return out


## True while Confirm, Back and Pause each still have a key and a pad input.
func reachable() -> bool:
	for action: StringName in REQUIRED:
		if inputs(action, KEY).is_empty() or inputs(action, PAD).is_empty():
			return false
	return true


# --- changing -------------------------------------------------------------------------------

## Gives `input` to `action` as its first input of that kind. Returns {ok: bool, why: String,
## with: Array[StringName], swapped: StringName}. `why` when not ok: "unsupported" / "reserved"
## (see capture_problem), "conflict" (`with` holds the actions that have it; call again with
## swap = true to trade places when there is exactly one), "no_swap" (the trade would leave the
## other action without its button or clash again), "unknown" (not a rebindable action).
func assign(action: StringName, input: Dictionary, swap: bool = false) -> Dictionary:
	if not ACTIONS.has(action):
		return {"ok": false, "why": "unknown", "with": [] as Array[StringName], "swapped": &""}
	var problem := capture_problem(input)
	if problem != "":
		return {"ok": false, "why": problem, "with": [] as Array[StringName], "swapped": &""}
	var kind := kind_of(input)
	var held := conflicts(action, input)
	var swapped: StringName = &""
	if not held.is_empty():
		if not swap:
			return {"ok": false, "why": "conflict", "with": held, "swapped": &""}
		var old := primary(action, kind)
		if held.size() != 1 or old.is_empty() or same(old, input) or not _can_trade(held[0], action, input, old):
			return {"ok": false, "why": "no_swap", "with": held, "swapped": &""}
		swapped = held[0]
		_replace(swapped, kind, input, old)
	var list := inputs(action, kind)
	var fresh: Array[Dictionary] = [input]
	for i: int in range(1, list.size()):
		if not same(list[i], input):
			fresh.append(list[i])
	_set_inputs(action, kind, fresh)
	return {"ok": true, "why": "", "with": [] as Array[StringName], "swapped": swapped}


## True when `assign(action, input, true)` would work, found by trying it on a copy.
func can_swap(action: StringName, input: Dictionary) -> bool:
	var copy := ControlBindings.new(_defaults)
	copy._current = _copy(_current)
	return bool(copy.assign(action, input, true).ok)


func reset_action(action: StringName) -> void:
	if _defaults.has(String(action)):
		_current[String(action)] = _copy_entry(_defaults[String(action)])


func reset_all() -> void:
	_current = _copy(_defaults)


## The changes from the defaults only, for the settings file: {action: {"key": [...], "pad": [...]}}.
func overrides() -> Dictionary:
	var out := {}
	for action: StringName in ACTIONS:
		if not is_action_default(action):
			out[String(action)] = _copy_entry(_current[String(action)])
	return out


## Takes saved changes (see overrides). Anything unknown or broken is skipped; if the result
## would leave two live actions on one button or lose Confirm, Back or Pause, every change is
## dropped (a hand-edited file can never lock a player out).
func load_overrides(saved: Dictionary) -> void:
	for action: StringName in ACTIONS:
		var entry: Variant = saved.get(String(action))
		if not entry is Dictionary:
			continue
		for kind: String in [KEY, PAD]:
			var raw: Variant = (entry as Dictionary).get(kind)
			if not raw is Array:
				continue
			var list: Array[Dictionary] = []
			for item: Variant in raw:
				if item is Dictionary and kind_of(item as Dictionary) == kind and capture_problem_loaded(item as Dictionary) == "":
					var already := false
					for other: Dictionary in list:
						already = already or same(other, item as Dictionary)
					if not already:
						list.append(_clean(item as Dictionary))
			if not list.is_empty():
				_set_inputs(action, kind, list)
	if not conflict_pairs().is_empty() or not reachable():
		push_warning("ControlBindings: saved controls clash or lose Confirm, Back or Pause; using the defaults")
		reset_all()


## Like capture_problem, but Escape and the Menu button are fine in a saved list (they are the
## defaults of Back and Pause).
static func capture_problem_loaded(input: Dictionary) -> String:
	var problem := capture_problem(input)
	return "" if problem == "reserved" else problem


## Writes the changed actions into the Input Map (untouched actions keep the project's own
## events). `everything`: write every action, so a model of the defaults puts the whole Input Map
## back (used by tests that restore what they changed).
func apply_to_input_map(everything: bool = false) -> void:
	for action: StringName in ACTIONS:
		if (is_action_default(action) and not everything) or not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for kind: String in [KEY, PAD]:
			for input: Dictionary in inputs(action, kind):
				var ev := event_from_input(input)
				if ev != null:
					InputMap.action_add_event(action, ev)


# --- internals ------------------------------------------------------------------------------

static func _may_share(a: StringName, b: StringName) -> bool:
	for pair: Array in SHARED:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


## Can `other` take `old` (the first input `action` is giving up) in place of `input`?
func _can_trade(other: StringName, action: StringName, input: Dictionary, old: Dictionary) -> bool:
	var kind := kind_of(input)
	# `action` stops holding `old`, so it does not count against the trade.
	for clash: StringName in conflicts(other, old):
		if clash != action:
			return false
	return not inputs(other, kind).is_empty() and not old.is_empty()


## `other` swaps `input` for `old` in its list (where it was), without doubles.
func _replace(other: StringName, kind: String, input: Dictionary, old: Dictionary) -> void:
	var list: Array[Dictionary] = []
	for held: Dictionary in inputs(other, kind):
		var put := old if same(held, input) else held
		var already := false
		for kept: Dictionary in list:
			already = already or same(kept, put)
		if not already:
			list.append(put)
	_set_inputs(other, kind, list)


func _set_inputs(action: StringName, kind: String, list: Array[Dictionary]) -> void:
	if not _current.has(String(action)):
		_current[String(action)] = {KEY: [] as Array[Dictionary], PAD: [] as Array[Dictionary]}
	var copy: Array[Dictionary] = []
	for input: Dictionary in list:
		copy.append(_clean(input))
	(_current[String(action)] as Dictionary)[kind] = copy


static func _clean(input: Dictionary) -> Dictionary:
	var out := {"k": String(input.get("k", "")), "code": int(input.get("code", 0))}
	if out.k == "axis":
		out["dir"] = int(input.get("dir", 1))
	return out


static func _same_entry(a: Dictionary, b: Dictionary) -> bool:
	for kind: String in [KEY, PAD]:
		var la: Array = a.get(kind, [])
		var lb: Array = b.get(kind, [])
		if la.size() != lb.size():
			return false
		for i: int in la.size():
			if not same(la[i], lb[i]):
				return false
	return true


static func _copy_entry(entry: Dictionary) -> Dictionary:
	var out := {}
	for kind: String in [KEY, PAD]:
		var list: Array[Dictionary] = []
		for input: Dictionary in entry.get(kind, []):
			list.append(_clean(input))
		out[kind] = list
	return out


static func _copy(all: Dictionary) -> Dictionary:
	var out := {}
	for action: Variant in all:
		out[String(action)] = _copy_entry(all[action])
	return out
