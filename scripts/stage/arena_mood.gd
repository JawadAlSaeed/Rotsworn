class_name ArenaMood
extends Node
## Tweens a fight's room to its phase-two look (DESIGN.md 7.3) when a boss or guard rages: the
## sun and ambient light, fog, background, vignette and the arena's lamps. Presentation only;
## the numbers come from the StageLook (PhaseShift.values), the length from combat_visuals.

var _look: StageLook
var _env: Environment
var _sun: DirectionalLight3D
var _vignette_material: ShaderMaterial
var _lamps: Array[FlickerLight] = []
var _duration_s: float = 0.0
var _elapsed_s: float = 0.0
var _active: bool = false
var _done: bool = false


func setup(look: StageLook, env: Environment, sun: DirectionalLight3D, vignette_material: ShaderMaterial,
		lamps: Array[FlickerLight]) -> void:
	_look = look
	_env = env
	_sun = sun
	_vignette_material = vignette_material
	_lamps = lamps
	set_process(false)


## True once the room has started shifting (a second phase event does nothing more).
func shifted() -> bool:
	return _active or _done


## Starts the shift over `duration_ms`. Without a phase-two look, or if already shifting, nothing.
func begin(duration_ms: int) -> void:
	if not PhaseShift.has_shift(_look) or shifted():
		return
	_duration_s = maxf(0.001, float(duration_ms) / 1000.0)
	_elapsed_s = 0.0
	_active = true
	set_process(true)


func _process(delta: float) -> void:
	_elapsed_s += delta
	var t := _elapsed_s / _duration_s
	_apply(PhaseShift.ease_t(t))
	if t >= 1.0:
		_active = false
		_done = true
		set_process(false)


func _apply(t: float) -> void:
	var v := PhaseShift.values(_look, t)
	if _env != null:
		_env.background_color = v.background
		_env.ambient_light_color = v.ambient_color
		_env.ambient_light_energy = v.ambient_energy
		_env.fog_light_color = v.fog_color
		_env.fog_density = v.fog_density
	if _sun != null:
		_sun.light_color = v.light_color
		_sun.light_energy = v.light_energy
	if _vignette_material != null:
		_vignette_material.set_shader_parameter("strength", v.vignette_strength)
		_vignette_material.set_shader_parameter("tint", v.vignette_color)
	for lamp: FlickerLight in _lamps:
		if is_instance_valid(lamp):
			lamp.set_energy_scale(v.lamp_scale)
