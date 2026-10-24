class_name WeatherData
extends Resource
## One kind of weather or time of day in a place (DESIGN.md 8.20, card #303): rain, fog, wind, dusk,
## a storm. A place lists the ones it can have (ZoneData.weathers); each run or Rush fight there rolls
## one or clear weather from the run's seed (RunState.weather_now, RushState.weather_now, DESIGN.md
## 8.21 and 8.22), so the same place feels different from fight to fight and every machine online
## sees the same sky. It changes only how the place looks and sounds: the light and fog (a copy of the
## place's StageLook), extra air (rain, mist, blowing leaves), how hard the plants sway and a sound
## loop. Its storm lightning lit the walkable zones only (WeatherFx, unused since phase 26, G6).
## Files live in data/weather/.

@export var id: String = ""
## Its name in the data ("Rain"). Never written on screen: the weather shows itself (owner,
## 2026-10-23).
@export var display_name: String = ""

@export_group("Light")
## The sun's and the ambient light's colours move this far toward the weather's (0: unchanged).
@export var light_color: Color = Color(1.0, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var light_color_mix: float = 0.0
@export_range(0, 300, 1, "suffix:%") var light_energy_percent: int = 100
@export var ambient_color: Color = Color(1.0, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var ambient_color_mix: float = 0.0
@export_range(0, 300, 1, "suffix:%") var ambient_energy_percent: int = 100
## The sun's height (its rotation's pitch, degrees; -90 straight down). 0: the place's own. Dusk
## lowers it, so shadows grow long.
@export_range(-90.0, 0.0, 0.5) var sun_pitch_degrees: float = 0.0
## How dark the sun's shadows are, in percent of the place's (a grey sky: fainter).
@export_range(0, 200, 1, "suffix:%") var sun_shadow_percent: int = 100

@export_group("Fog and sky")
@export var fog_color: Color = Color(1.0, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var fog_color_mix: float = 0.0
## Added to the place's fog and its ground fog.
@export_range(0.0, 0.3, 0.001) var fog_density_add: float = 0.0
@export_range(0.0, 2.0, 0.01) var fog_height_density_add: float = 0.0
@export var background_color: Color = Color(0.0, 0.0, 0.0)
@export_range(0.0, 1.0, 0.01) var background_color_mix: float = 0.0

@export_group("Colour")
@export_range(0, 300, 1, "suffix:%") var brightness_percent: int = 100
@export_range(0, 300, 1, "suffix:%") var saturation_percent: int = 100
@export_range(0, 300, 1, "suffix:%") var contrast_percent: int = 100
## Added to the place's dark screen edges.
@export_range(-1.0, 1.0, 0.01) var vignette_add: float = 0.0

@export_group("Air and wind")
## Drifting extras (rain streaks, splashes, mist banks, blowing leaves), on top of the place's own air.
@export var air: Array[ZoneAmbientData] = []
## The place's own air at this share (rain puts most fireflies out).
@export_range(0, 300, 1, "suffix:%") var zone_air_percent: int = 100
## How far and how fast the plants sway, in percent of the place's (wind: more).
@export_range(0, 500, 1, "suffix:%") var sway_percent: int = 100
@export_range(0, 500, 1, "suffix:%") var sway_speed_percent: int = 100

@export_group("Sound")
## A sound loop (rain, wind). Empty: none.
@export_file("*.wav", "*.ogg", "*.mp3") var ambience_path: String = ""
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var ambience_volume_db: float = 0.0
## In a fight the loop plays this much quieter (the fight's own sounds come first).
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var fight_volume_offset_db: float = -6.0

@export_group("Lightning")
## A storm: lightning lit the walkable zones now and then (never a fight, where it would hide an
## attack), and thunder followed (WeatherFx, unused since phase 26). 0: no lightning.
@export_range(0, 120000, 100, "suffix:ms") var lightning_min_ms: int = 0
@export_range(0, 120000, 100, "suffix:ms") var lightning_max_ms: int = 0
## A flash adds this much ambient light and lifts the sky this far toward lightning_color (the
## Flashes setting scales both like every screen flash).
@export_range(0.0, 8.0, 0.05) var lightning_energy: float = 1.5
@export var lightning_color: Color = Color(0.8, 0.85, 1.0)
@export_range(0.0, 1.0, 0.01) var lightning_sky_mix: float = 0.6
@export_range(20, 2000, 10, "suffix:ms") var lightning_flash_ms: int = 220
## Thunder (a sound cue) this long after the flash: far away, or close.
@export var thunder_sfx: String = "thunder"
@export_range(0, 6000, 50, "suffix:ms") var thunder_min_delay_ms: int = 400
@export_range(0, 6000, 50, "suffix:ms") var thunder_max_delay_ms: int = 1800


## True if this weather brings lightning.
func has_lightning() -> bool:
	return lightning_min_ms > 0 and lightning_max_ms >= lightning_min_ms


## A copy of `look` under this weather (the place's own look is shared and never changed).
func apply_to(look: StageLook) -> StageLook:
	var out := (look.duplicate() as StageLook) if look != null else StageLook.new()
	out.light_color = out.light_color.lerp(light_color, light_color_mix)
	out.light_energy = out.light_energy * float(light_energy_percent) / 100.0
	out.ambient_color = out.ambient_color.lerp(ambient_color, ambient_color_mix)
	out.ambient_energy = out.ambient_energy * float(ambient_energy_percent) / 100.0
	if sun_pitch_degrees < 0.0:
		out.light_rotation_degrees.x = sun_pitch_degrees
	out.sun_shadow_opacity = clampf(out.sun_shadow_opacity * float(sun_shadow_percent) / 100.0, 0.0, 1.0)
	out.fog_color = out.fog_color.lerp(fog_color, fog_color_mix)
	out.fog_density = out.fog_density + fog_density_add
	out.fog_height_density = out.fog_height_density + fog_height_density_add
	out.background_color = out.background_color.lerp(background_color, background_color_mix)
	out.brightness = out.brightness * float(brightness_percent) / 100.0
	out.saturation = out.saturation * float(saturation_percent) / 100.0
	out.contrast = out.contrast * float(contrast_percent) / 100.0
	out.vignette_strength = clampf(out.vignette_strength + vignette_add, 0.0, 1.0)
	out.sway_percent = roundi(float(out.sway_percent) * float(sway_percent) / 100.0)
	out.sway_speed_percent = roundi(float(out.sway_speed_percent) * float(sway_speed_percent) / 100.0)
	# The room's phase-two shift (a guard's rage, ArenaMood) goes from the weathered room to a
	# weathered rage: the same changes on its own values, so it never jumps back to clear weather.
	out.phase_light_color = out.phase_light_color.lerp(light_color, light_color_mix)
	out.phase_light_energy = out.phase_light_energy * float(light_energy_percent) / 100.0
	out.phase_ambient_color = out.phase_ambient_color.lerp(ambient_color, ambient_color_mix)
	out.phase_ambient_energy = out.phase_ambient_energy * float(ambient_energy_percent) / 100.0
	out.phase_fog_color = out.phase_fog_color.lerp(fog_color, fog_color_mix)
	out.phase_fog_density = out.phase_fog_density + fog_density_add
	out.phase_background_color = out.phase_background_color.lerp(background_color, background_color_mix)
	out.phase_vignette_strength = clampf(out.phase_vignette_strength + vignette_add, 0.0, 1.0)
	return out


## The zone's own air at zone_air_percent of its amount, then this weather's air.
func air_with(zone_air: Array[ZoneAmbientData]) -> Array[ZoneAmbientData]:
	var out: Array[ZoneAmbientData] = []
	for data: ZoneAmbientData in zone_air:
		if data == null:
			continue
		if zone_air_percent == 100:
			out.append(data)
		elif zone_air_percent > 0:
			var thinned := data.duplicate() as ZoneAmbientData
			thinned.amount = maxi(1, roundi(float(data.amount) * float(zone_air_percent) / 100.0))
			out.append(thinned)
	for data: ZoneAmbientData in air:
		if data != null:
			out.append(data)
	return out


## The weather of one visit: one of `weathers` by `weights` (missing weights count 1), or null
## (clear) by `clear_weight`. The same list and seed always give the same weather. Pure.
static func pick(weathers: Array[WeatherData], weights: Array[int], clear_weight: int, seed_value: int) -> WeatherData:
	var total := maxi(0, clear_weight)
	for i: int in weathers.size():
		total += _weight(weights, i) if weathers[i] != null else 0
	if total <= 0:
		return null
	var rng := CombatRng.new(maxi(1, absi(seed_value)))
	var roll := rng.range_int(0, total - 1)
	if roll < maxi(0, clear_weight):
		return null
	roll -= maxi(0, clear_weight)
	for i: int in weathers.size():
		if weathers[i] == null:
			continue
		roll -= _weight(weights, i)
		if roll < 0:
			return weathers[i]
	return null


static func _weight(weights: Array[int], i: int) -> int:
	return maxi(0, weights[i]) if i < weights.size() else 1
