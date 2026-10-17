class_name DeviceInput
extends RefCounted
## Reads input actions for one device only (DESIGN.md 9.1). Godot's Input.get_vector() and
## is_action_pressed() mix every device, so in co-op a zone would walk for anyone; these read the
## same Input Map bindings (so remaps still work) but only on the given device.


## How hard `action` is held on `device` (a PlayerRoster device code), 0 to 1.
static func strength(action: StringName, device: int) -> float:
	if not InputMap.has_action(action):
		return 0.0
	var deadzone := InputMap.action_get_deadzone(action)
	var best := 0.0
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey and device == PlayerRoster.KEYBOARD:
			var key := ev as InputEventKey
			var held := false
			if key.physical_keycode != KEY_NONE:
				held = Input.is_physical_key_pressed(key.physical_keycode)
			elif key.keycode != KEY_NONE:
				held = Input.is_key_pressed(key.keycode)
			if held:
				best = 1.0
		elif ev is InputEventJoypadButton and device >= 0 and (ev.device < 0 or ev.device == device):
			if Input.is_joy_button_pressed(device, (ev as InputEventJoypadButton).button_index):
				best = 1.0
		elif ev is InputEventJoypadMotion and device >= 0 and (ev.device < 0 or ev.device == device):
			var motion := ev as InputEventJoypadMotion
			var value := Input.get_joy_axis(device, motion.axis) * signf(motion.axis_value)
			if value > deadzone:
				best = maxf(best, inverse_lerp(deadzone, 1.0, minf(value, 1.0)))
	return best


## Like Input.get_vector(), for one device; at most length 1. The stick is read as a vector with a
## radial deadzone (so a diagonal push does not snap to an axis); keys and buttons add on top.
static func vector(negative_x: StringName, positive_x: StringName, negative_y: StringName,
		positive_y: StringName, device: int) -> Vector2:
	var digital := Vector2(_digital(positive_x, device) - _digital(negative_x, device),
			_digital(positive_y, device) - _digital(negative_y, device))
	var raw := Vector2(_stick_axis(positive_x, device) - _stick_axis(negative_x, device),
			_stick_axis(positive_y, device) - _stick_axis(negative_y, device))
	var deadzone := InputMap.action_get_deadzone(positive_x) if InputMap.has_action(positive_x) else 0.2
	return (digital + radial_deadzone(raw, deadzone)).limit_length(1.0)


## A stick position with a radial deadzone: zero inside `deadzone`, then rescaled so it rises from
## 0 at the edge of the deadzone to 1 at full throw, keeping its direction.
static func radial_deadzone(raw: Vector2, deadzone: float) -> Vector2:
	var length := raw.length()
	if length <= deadzone or length <= 0.0:
		return Vector2.ZERO
	return raw / length * minf(1.0, inverse_lerp(deadzone, 1.0, length))


## Keys and pad buttons only (no stick) for `action` on `device`: 0 or 1.
static func _digital(action: StringName, device: int) -> float:
	if not InputMap.has_action(action):
		return 0.0
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey and device == PlayerRoster.KEYBOARD:
			var key := ev as InputEventKey
			var held := false
			if key.physical_keycode != KEY_NONE:
				held = Input.is_physical_key_pressed(key.physical_keycode)
			elif key.keycode != KEY_NONE:
				held = Input.is_key_pressed(key.keycode)
			if held:
				return 1.0
		elif ev is InputEventJoypadButton and device >= 0 and (ev.device < 0 or ev.device == device):
			if Input.is_joy_button_pressed(device, (ev as InputEventJoypadButton).button_index):
				return 1.0
	return 0.0


## The raw stick value (-1 to 1, in the direction `action` is bound to) on `device`, 0 if none.
static func _stick_axis(action: StringName, device: int) -> float:
	if not InputMap.has_action(action) or device < 0:
		return 0.0
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion and (ev.device < 0 or ev.device == device):
			var motion := ev as InputEventJoypadMotion
			return maxf(0.0, Input.get_joy_axis(device, motion.axis) * signf(motion.axis_value))
	return 0.0
