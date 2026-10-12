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


## Like Input.get_vector(), for one device; at most length 1.
static func vector(negative_x: StringName, positive_x: StringName, negative_y: StringName,
		positive_y: StringName, device: int) -> Vector2:
	var v := Vector2(strength(positive_x, device) - strength(negative_x, device),
			strength(positive_y, device) - strength(negative_y, device))
	return v.limit_length(1.0)
