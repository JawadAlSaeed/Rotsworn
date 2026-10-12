class_name StageBuilder
extends RefCounted
## Builds a place from data (DESIGN.md 7.3): the HD-2D environment (sun, ambient light, fog,
## bloom, colour grading, ambient occlusion) from a StageLook, depth of field for a camera, the
## ground and backdrop, solid blocks, lit sprite props and point lights, and the screen vignette.
## Shared by the combat stage and the zones, so a fight looks like the place it started in.

const PROP_SHADER := preload("res://scripts/combat/presentation/fighter_sprite.gdshader")
const VIGNETTE_SHADER := preload("res://scripts/stage/vignette.gdshader")
## The vignette draws above the 3D view and below every HUD (layer 10 and up).
const VIGNETTE_LAYER: int = 5
## Shadows reach this far from the camera (world units).
const SHADOW_DISTANCE: float = 45.0


## The WorldEnvironment for a look.
static func environment(look: StageLook) -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = look.background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = look.ambient_color
	env.ambient_light_energy = look.ambient_energy
	env.fog_enabled = look.fog_density > 0.0 or look.fog_height_density > 0.0
	env.fog_light_color = look.fog_color
	env.fog_density = look.fog_density
	env.fog_height = look.fog_height
	env.fog_height_density = look.fog_height_density
	env.volumetric_fog_enabled = look.volumetric_fog
	env.volumetric_fog_density = look.volumetric_fog_density
	env.volumetric_fog_albedo = look.volumetric_fog_albedo
	env.glow_enabled = look.glow_enabled
	env.glow_intensity = look.glow_intensity
	env.glow_strength = look.glow_strength
	env.glow_bloom = look.glow_bloom
	env.glow_hdr_threshold = look.glow_hdr_threshold
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.tonemap_mode = clampi(look.tonemap_mode, 0, 4) as Environment.ToneMapper
	env.tonemap_exposure = look.tonemap_exposure
	env.tonemap_white = look.tonemap_white
	env.adjustment_enabled = true
	env.adjustment_brightness = look.brightness
	env.adjustment_contrast = look.contrast
	env.adjustment_saturation = look.saturation
	env.ssao_enabled = look.ssao
	env.ssao_intensity = look.ssao_intensity
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	return world_env


## The sun for a look.
static func sun(look: StageLook) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.light_color = look.light_color
	light.light_energy = look.light_energy
	light.rotation_degrees = look.light_rotation_degrees
	light.shadow_enabled = look.sun_shadows
	light.shadow_opacity = look.sun_shadow_opacity
	light.directional_shadow_max_distance = SHADOW_DISTANCE
	return light


## Depth of field for a camera: blur beyond far distance and nearer than near distance.
static func camera_attributes(far_enabled: bool, far_distance: float, far_transition: float,
		near_enabled: bool, near_distance: float, near_transition: float, amount: float) -> CameraAttributesPractical:
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = far_enabled
	attributes.dof_blur_far_distance = far_distance
	attributes.dof_blur_far_transition = far_transition
	attributes.dof_blur_near_enabled = near_enabled
	attributes.dof_blur_near_distance = near_distance
	attributes.dof_blur_near_transition = near_transition
	attributes.dof_blur_amount = amount
	return attributes


## The tiled ground plane, centred at `centre`.
static func ground(look: StageLook, centre: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(look.floor_size, look.floor_size)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = AssetLoader.texture(look.floor_tile_path, Vector2i(32, 32))
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.texture_repeat = true
	# World-space tiling, so the pattern does not move when the plane is centred elsewhere.
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / maxf(0.01, look.floor_tile_world_size)
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	floor_mesh.mesh = mesh
	floor_mesh.material_override = mat
	floor_mesh.position = Vector3(centre.x, 0.0, centre.z)
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return floor_mesh


## The far backdrop sprite of a look.
static func backdrop(look: StageLook) -> Sprite3D:
	var tex := AssetLoader.texture(look.backdrop_path, Vector2i(320, 120))
	var sprite := Sprite3D.new()
	sprite.name = "Backdrop"
	sprite.texture = tex
	sprite.pixel_size = look.backdrop_pixel_size
	sprite.centered = true
	sprite.offset = Vector2(0.0, float(tex.get_height()) * 0.5)
	sprite.position = look.backdrop_position
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sprite


## A solid textured block (the texture tiles in world space on every side).
static func block(data: ZoneBlockData) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = data.size
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = AssetLoader.texture(data.texture_path, Vector2i(32, 32))
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.texture_repeat = true
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / maxf(0.01, data.texture_world_size)
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = data.position + Vector3(0.0, data.size.y * 0.5, 0.0)
	node.rotation_degrees = Vector3(0.0, data.rotation_y_degrees, 0.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return node


## A lit billboard sprite standing at its feet (trees, rocks, lamps).
static func prop(data: ZonePropData) -> Sprite3D:
	var tex := AssetLoader.texture(data.sprite_path, Vector2i(32, 32))
	var sprite := Sprite3D.new()
	sprite.texture = tex
	sprite.pixel_size = data.pixel_size
	sprite.centered = true
	sprite.offset = Vector2(0.0, float(tex.get_height()) * 0.5)
	sprite.flip_h = data.flip
	sprite.position = data.position
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = PROP_SHADER
	mat.set_shader_parameter("sprite_texture", tex)
	mat.set_shader_parameter("self_glow", data.glow)
	mat.set_shader_parameter("self_glow_color", data.glow_color)
	sprite.material_override = mat
	return sprite


## A point light, flickering if the data says so.
static func light(data: ZoneLightData) -> OmniLight3D:
	var lamp := FlickerLight.new()
	lamp.position = data.position
	lamp.light_color = data.color
	lamp.omni_range = data.reach
	lamp.shadow_enabled = data.shadows
	lamp.setup(data.energy, data.flicker_percent, data.flicker_hz)
	return lamp


## Adds every block, prop and light under `parent`.
static func add_contents(parent: Node3D, blocks: Array[ZoneBlockData], props: Array[ZonePropData],
		lights: Array[ZoneLightData]) -> void:
	for data: ZoneBlockData in blocks:
		if data != null:
			parent.add_child(block(data))
	for data: ZonePropData in props:
		if data != null:
			parent.add_child(prop(data))
	for data: ZoneLightData in lights:
		if data != null:
			parent.add_child(light(data))


## Dark screen edges (a full-screen overlay above the 3D view, below the HUD).
static func vignette(look: StageLook) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "Vignette"
	layer.layer = VIGNETTE_LAYER
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = VIGNETTE_SHADER
	mat.set_shader_parameter("strength", look.vignette_strength)
	mat.set_shader_parameter("tint", look.vignette_color)
	rect.material = mat
	layer.add_child(rect)
	layer.visible = look.vignette_strength > 0.0
	return layer
