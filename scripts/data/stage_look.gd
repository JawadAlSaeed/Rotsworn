class_name StageLook
extends Resource
## How a place looks (DESIGN.md 7.3): the HD-2D lighting and post-processing (sun, ambient light,
## fog, bloom, colour grading, vignette), the ground and backdrop art, and the decoration around
## the combat arena. A zone and the fights that start in it share one look; the fight list uses
## combat_visuals.tres stage_look. Depth of field belongs to each camera (combat_visuals,
## explore_visuals), since it depends on how far the camera is.

@export_group("Ground and backdrop")
## Seamlessly tileable ground (32x32).
@export_file_path("*.png") var floor_tile_path: String = "res://assets/sprites/env/floor_tile.png"
## World size of one ground tile.
@export_range(0.1, 10.0, 0.05) var floor_tile_world_size: float = 1.6
## Extra drawn variants of the ground tile (same palette, other pattern; up to two). The floor
## shader gives each ragged region of the floor one of the tiles, so the pattern never repeats
## across the screen like wallpaper. Empty: only floor_tile_path.
@export_file_path("*.png") var floor_variant_paths: Array[String] = []
## Width of one region of the floor (world units) that has its own variant and mirroring.
## 0 = no regions, one even tile.
@export_range(0.0, 40.0, 0.5) var floor_region_world_size: float = 7.0
## How much the noise bends the edge of a region (share of its size).
@export_range(0.0, 1.0, 0.05) var floor_region_warp: float = 0.5
## Regions also mirror the tile (left-right, up-down) at random: more patterns from the same art.
## Turn it off for a floor whose lighting is drawn into the tile and must keep its direction.
@export var floor_mirror: bool = true
## The floor drifts lighter and darker in a few steps over areas this wide (world units).
@export_range(0.0, 60.0, 0.5) var floor_tone_world_size: float = 9.0
## How far it drifts (share of the brightness each way; 0 = no drift) and in how many steps.
@export_range(0.0, 0.5, 0.01) var floor_tone_strength: float = 0.12
@export_range(2, 8) var floor_tone_steps: int = 4
## Width and depth of the ground plane in world units.
@export_range(4.0, 400.0, 0.5) var floor_size: float = 48.0
## Far background silhouettes (320x120, transparent background), drawn behind the combat arena.
@export_file_path("*.png") var backdrop_path: String = "res://assets/sprites/env/backdrop.png"
@export var backdrop_position: Vector3 = Vector3(0.0, 0.0, -13.0)
## World units per backdrop pixel.
@export_range(0.001, 1.0, 0.001) var backdrop_pixel_size: float = 0.1
## Sky colour behind everything.
@export var background_color: Color = Color(0.05, 0.055, 0.075)

@export_group("Light")
@export var ambient_color: Color = Color(0.32, 0.34, 0.42)
@export_range(0.0, 4.0, 0.05) var ambient_energy: float = 0.7
@export var light_color: Color = Color(1.0, 0.92, 0.82)
@export_range(0.0, 8.0, 0.05) var light_energy: float = 1.1
## Sun rotation (pitch, yaw, roll) in degrees.
@export var light_rotation_degrees: Vector3 = Vector3(-55.0, -30.0, 0.0)
## The sun casts shadows from blocks (cliffs, walls). Sprites keep their soft blob shadow.
@export var sun_shadows: bool = true
@export_range(0.0, 1.0, 0.05) var sun_shadow_opacity: float = 0.75

@export_group("Fog")
@export var fog_color: Color = Color(0.16, 0.18, 0.24)
@export_range(0.0, 0.3, 0.001) var fog_density: float = 0.025
## Extra fog that thickens toward the ground below fog_height (0 = none).
@export_range(0.0, 2.0, 0.01) var fog_height_density: float = 0.0
@export_range(-20.0, 20.0, 0.1) var fog_height: float = 0.0
## Volumetric fog: light shafts from lamps and the sun. Costly on weak machines.
@export var volumetric_fog: bool = false
@export_range(0.0, 0.5, 0.001) var volumetric_fog_density: float = 0.02
@export var volumetric_fog_albedo: Color = Color(0.8, 0.8, 0.9)

@export_group("Bloom")
@export var glow_enabled: bool = true
@export_range(0.0, 8.0, 0.05) var glow_intensity: float = 0.8
@export_range(0.0, 2.0, 0.05) var glow_strength: float = 1.0
## How much of the whole picture glows (not just the bright parts).
@export_range(0.0, 1.0, 0.01) var glow_bloom: float = 0.05
## Brightness above which things glow.
@export_range(0.0, 4.0, 0.05) var glow_hdr_threshold: float = 0.9

@export_group("Colour")
## Environment.ToneMapper: 0 linear, 1 Reinhard, 2 filmic, 3 ACES, 4 AgX.
@export_range(0, 4) var tonemap_mode: int = 2
@export_range(0.1, 8.0, 0.05) var tonemap_exposure: float = 1.0
@export_range(0.5, 16.0, 0.1) var tonemap_white: float = 6.0
@export_range(0.0, 3.0, 0.01) var brightness: float = 1.0
@export_range(0.0, 3.0, 0.01) var contrast: float = 1.1
@export_range(0.0, 3.0, 0.01) var saturation: float = 1.1
## Ambient occlusion: soft contact shadows where blocks meet the ground.
@export var ssao: bool = true
@export_range(0.0, 16.0, 0.1) var ssao_intensity: float = 2.0
## Dark edges of the screen (0 = none, 1 = strong).
@export_range(0.0, 1.0, 0.01) var vignette_strength: float = 0.45
@export var vignette_color: Color = Color(0.0, 0.0, 0.02)

@export_group("Contact shadows")
## Props, trees, shrines and walkers-by get a soft dark blob on the ground under them (the same
## blob the fighters stand on). How dark it is (0 = none).
@export_range(0.0, 1.0, 0.05) var prop_shadow_opacity: float = 1.0
## Blob width as a share of the prop's footprint (the opaque width of its lowest rows).
@export_range(20, 400, 5, "suffix:%") var prop_shadow_width_percent: int = 210
## The lowest rows measured for the footprint, as a share of the sprite's height.
@export_range(5, 60, 1, "suffix:%") var prop_shadow_footprint_percent: int = 16
## Footprints narrower than this (art pixels) get no blob (a thin twig does not need one).
@export_range(0, 40, 1) var prop_shadow_min_footprint_px: int = 6
## The blob slides away from the sun by this share of its width, so it reads as the sun's shadow.
@export_range(0, 100, 1, "suffix:%") var prop_shadow_shift_percent: int = 20
@export_file_path("*.png") var prop_shadow_path: String = "res://assets/sprites/fx/shadow.png"

@export_group("Combat arena")
## Decoration around a fight that happens in this place (kept clear of the fighters' spots).
@export var arena_blocks: Array[ZoneBlockData] = []
@export var arena_props: Array[ZonePropData] = []
@export var arena_lights: Array[ZoneLightData] = []
## Air that drifts in a fight in this place when the fight's zone has none of its own (the
## Hollow King's throne: embers). A zone's fights use the zone's own ambient list instead
## (DESIGN.md 8.12, 7.3). Thinned by combat_visuals fight_air_percent.
@export var arena_air: Array[ZoneAmbientData] = []

@export_group("Phase two")
## The room shifts when a boss or guard enters phase two (DESIGN.md 7.3): the light, fog and
## vignette tween to the values below over combat_visuals phase_look_ms. Off: the room stays.
@export var phase_two_enabled: bool = false
@export var phase_background_color: Color = Color(0.07, 0.03, 0.04)
@export var phase_ambient_color: Color = Color(0.32, 0.34, 0.42)
@export_range(0.0, 4.0, 0.05) var phase_ambient_energy: float = 0.7
@export var phase_light_color: Color = Color(1.0, 0.92, 0.82)
@export_range(0.0, 8.0, 0.05) var phase_light_energy: float = 1.1
@export var phase_fog_color: Color = Color(0.16, 0.18, 0.24)
@export_range(0.0, 0.3, 0.001) var phase_fog_density: float = 0.025
@export_range(0.0, 1.0, 0.01) var phase_vignette_strength: float = 0.45
@export var phase_vignette_color: Color = Color(0.0, 0.0, 0.02)
## The arena's lamps and braziers burn at this share of their strength (100 = unchanged; above
## 100 they roar).
@export_range(0, 300, 5, "suffix:%") var phase_lamp_percent: int = 100
## A one-time puff of particles when the shift starts (embers, ash); null: none.
@export var phase_burst: ZoneAmbientData
