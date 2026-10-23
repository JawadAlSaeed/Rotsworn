class_name WeatherFx
extends Node
## Lightning and thunder over a stormy zone visit (card #303, DESIGN.md 8.20). Every
## lightning_min_ms to lightning_max_ms the sky lights up for a moment (ambient light and the sky
## colour jump, with a second, weaker flicker), and thunder follows after a short delay with a low
## buzz on the pad. Presentation only, so its timing needs no seed. The Flashes setting scales the
## flash like every screen flash (combat_visuals screen_flash_scale: Reduced dims it, Off skips it;
## the thunder still comes). A zone's fights have no lightning, and a zone held behind the pause menu
## (its processing off), the backpack or a yes/no prompt (its own pause, `held`) or parked for a fight
## neither flashes nor thunders; after a hold the next strike is a whole gap away.

## The second flicker of a flash: when it comes (share of the flash) and how strong it is.
const FLICKER_AT: float = 0.45
const FLICKER_SHARE: float = 0.6

var _weather: WeatherData
var _visuals: CombatVisuals
var _env: Environment
var _base_energy: float = 0.0
var _base_sky: Color = Color.BLACK
var _next_ms: int = 0
var _tween: Tween
## True while the zone is paused by its own flag (ZoneController.is_paused: backpack, prompts).
var _held := Callable()


func setup(weather: WeatherData, world_env: WorldEnvironment, visuals: CombatVisuals,
		held: Callable = Callable()) -> WeatherFx:
	name = "WeatherFx"
	_weather = weather
	_visuals = visuals
	_held = held
	_env = world_env.environment if world_env != null else null
	if _env != null:
		_base_energy = _env.ambient_light_energy
		_base_sky = _env.background_color
	_next_ms = Time.get_ticks_msec() + _gap_ms()
	return self


## How long until the next flash (ms), somewhere in the weather's range.
func _gap_ms() -> int:
	return randi_range(_weather.lightning_min_ms, maxi(_weather.lightning_min_ms, _weather.lightning_max_ms))


func _process(_delta: float) -> void:
	if _weather == null or not _weather.has_lightning():
		return
	var now := Time.get_ticks_msec()
	if _is_held():
		# Behind the backpack or a prompt: no flash, and the next strike waits a whole gap after it.
		if _tween != null:
			_stop_flash()
		_next_ms = now + _gap_ms()
		return
	if now < _next_ms:
		return
	_next_ms = now + _gap_ms()
	strike()


## One lightning strike now: the flash (unless Flashes is Off), then the thunder.
func strike() -> void:
	var share := _visuals.screen_flash_scale(PlayerSettings.flash_mode()) if _visuals != null else 1.0
	if _env != null and share > 0.0:
		if _tween != null:
			_tween.kill()
		var peak := _base_energy + _weather.lightning_energy * share
		var sky := _base_sky.lerp(_weather.lightning_color, _weather.lightning_sky_mix * share)
		var flash_s := float(_weather.lightning_flash_ms) / 1000.0
		_set_flash(peak, sky)
		_tween = create_tween()
		_tween.tween_method(_fade_flash.bind(peak, sky), 1.0, 0.0, flash_s * FLICKER_AT)
		_tween.tween_callback(_set_flash.bind(_base_energy + (peak - _base_energy) * FLICKER_SHARE,
				_base_sky.lerp(sky, FLICKER_SHARE)))
		_tween.tween_method(_fade_flash.bind(peak, sky), FLICKER_SHARE, 0.0, flash_s * (1.0 - FLICKER_AT))
	var delay := randi_range(_weather.thunder_min_delay_ms, maxi(_weather.thunder_min_delay_ms, _weather.thunder_max_delay_ms))
	get_tree().create_timer(float(delay) / 1000.0).timeout.connect(_thunder)


func _thunder() -> void:
	# Held behind an overlay (its processing off or the zone's own pause) or parked for a fight: this
	# clap is skipped.
	if not is_inside_tree() or not can_process() or _is_held():
		return
	Sfx.play(_weather.thunder_sfx)
	PadRumble.everyone("thunder")


func _is_held() -> bool:
	return _held.is_valid() and bool(_held.call())


## `amount` of the way from the base light to the flash's peak.
func _fade_flash(amount: float, peak: float, sky: Color) -> void:
	_set_flash(lerpf(_base_energy, peak, amount), _base_sky.lerp(sky, amount))


func _set_flash(energy: float, sky: Color) -> void:
	if _env == null:
		return
	_env.ambient_light_energy = energy
	_env.background_color = sky


## Ends a flash at once: the light back to the zone's own.
func _stop_flash() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_set_flash(_base_energy, _base_sky)


func _notification(what: int) -> void:
	# The zone held behind the pause menu: never a lit sky frozen behind it, and no strike the moment
	# the menu closes.
	if what == NOTIFICATION_DISABLED:
		_stop_flash()
	elif what == NOTIFICATION_ENABLED and _weather != null:
		_next_ms = Time.get_ticks_msec() + _gap_ms()


func _enter_tree() -> void:
	# Back from a fight (the zone waits outside the tree): no strike the moment it returns.
	if _weather != null:
		_next_ms = Time.get_ticks_msec() + _gap_ms()


func _exit_tree() -> void:
	# Parked for a fight or freed mid-flash: the zone's own light, and no half flash left to replay.
	_stop_flash()
