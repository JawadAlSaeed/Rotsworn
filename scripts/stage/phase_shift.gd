class_name PhaseShift
extends RefCounted
## The arena's phase-two shift (DESIGN.md 7.3), the pure part: which look values a room has at
## a point of the shift between its base look and its phase-two values. Presentation only; the
## engine never knows. ArenaMood applies the numbers to the live environment, sun and vignette.


## True if this look defines a phase-two shift.
static func has_shift(look: StageLook) -> bool:
	return look != null and look.phase_two_enabled


## Eased progress for a linear 0..1 `t` (slow start and end, no jolt).
static func ease_t(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## The look values `t` of the way (0 = base, 1 = phase two; ease it first) between the base look
## and the phase-two values. Keys: background, ambient_color, ambient_energy, light_color,
## light_energy, fog_color, fog_density, vignette_strength, vignette_color, lamp_scale. A look
## without a shift always gives its base values.
static func values(look: StageLook, t: float) -> Dictionary:
	var k := clampf(t, 0.0, 1.0) if has_shift(look) else 0.0
	var lamp := float(look.phase_lamp_percent) / 100.0
	return {
		"background": look.background_color.lerp(look.phase_background_color, k),
		"ambient_color": look.ambient_color.lerp(look.phase_ambient_color, k),
		"ambient_energy": lerpf(look.ambient_energy, look.phase_ambient_energy, k),
		"light_color": look.light_color.lerp(look.phase_light_color, k),
		"light_energy": lerpf(look.light_energy, look.phase_light_energy, k),
		"fog_color": look.fog_color.lerp(look.phase_fog_color, k),
		"fog_density": lerpf(look.fog_density, look.phase_fog_density, k),
		"vignette_strength": lerpf(look.vignette_strength, look.phase_vignette_strength, k),
		"vignette_color": look.vignette_color.lerp(look.phase_vignette_color, k),
		"lamp_scale": lerpf(1.0, lamp, k),
	}


## How long the shift takes under flash mode `mode` (PlayerSettings.FLASH_*): Reduced and Off
## stretch it (`calm_percent` of the base length) so the change of light is gentler.
static func duration_ms(base_ms: int, calm_percent: int, mode: int) -> int:
	if mode == PlayerSettings.FLASH_FULL:
		return base_ms
	return base_ms * calm_percent / 100


## The ambient particles thinned for a fight: `percent` of each one's amount (at least 1) and
## the box's depth cut to `depth_percent`, so the air stays behind and around the fighters.
## Returns copies; the zone's own data is untouched.
static func fight_air(list: Array[ZoneAmbientData], percent: int, depth_percent: int) -> Array[ZoneAmbientData]:
	var out: Array[ZoneAmbientData] = []
	for data: ZoneAmbientData in list:
		if data == null:
			continue
		var copy := data.duplicate() as ZoneAmbientData
		copy.amount = maxi(1, data.amount * percent / 100)
		copy.area = Vector3(data.area.x, data.area.y, data.area.z * float(depth_percent) / 100.0)
		out.append(copy)
	return out
