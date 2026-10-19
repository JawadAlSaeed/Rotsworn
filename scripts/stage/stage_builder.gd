class_name StageBuilder
extends RefCounted
## Builds a place from data (DESIGN.md 7.3): the HD-2D environment (sun, ambient light, fog,
## bloom, colour grading, ambient occlusion) from a StageLook, depth of field for a camera, the
## ground and backdrop, solid blocks, lit sprite props and point lights, and the screen vignette.
## Shared by the combat stage and the zones, so a fight looks like the place it started in.

const PROP_SHADER := preload("res://scripts/combat/presentation/fighter_sprite.gdshader")
const VIGNETTE_SHADER := preload("res://scripts/stage/vignette.gdshader")
const GROUND_SHADER := preload("res://scripts/stage/ground_patch.gdshader")
const FLOOR_SHADER := preload("res://scripts/stage/floor_ground.gdshader")
## The footprints measured so far (texture key -> width in art pixels).
static var _footprints: Dictionary = {}
## The materials of 3D pieces made so far ("piece|surface index|glow share" -> material), shared
## by copies.
static var _piece_materials: Dictionary = {}
## A built 3D piece remembers its WorldPieceData here (dim_glow needs it).
const META_PIECE := &"world_piece"
## The vignette draws above the 3D view and below every HUD (layer 10 and up).
const VIGNETTE_LAYER: int = 5
## Shadows reach this far from the camera (world units).
const SHADOW_DISTANCE: float = 45.0


## Meta key holding what a look wants, so the player's graphics options (card #112) can turn
## parts off and back on later (apply_settings).
const META_LOOK := "stage_look_wants"


## The WorldEnvironment for a look (with the player's graphics options applied).
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
	world_env.set_meta(META_LOOK, {"fog": env.fog_enabled, "volumetric": env.volumetric_fog_enabled,
			"glow": env.glow_enabled, "ssao": env.ssao_enabled})
	_apply_environment(world_env)
	return world_env


## The sun for a look.
static func sun(look: StageLook) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.light_color = look.light_color
	light.light_energy = look.light_energy
	light.rotation_degrees = look.light_rotation_degrees
	light.shadow_opacity = look.sun_shadow_opacity
	light.directional_shadow_max_distance = SHADOW_DISTANCE
	light.set_meta(META_LOOK, {"shadows": look.sun_shadows})
	_apply_sun(light)
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
	attributes.set_meta(META_LOOK, {"far": far_enabled, "near": near_enabled})
	_apply_camera_attributes(attributes)
	return attributes


## Applies the player's graphics options to every built place under `root` (after a change in
## the settings, which can open over a fight or a zone).
static func apply_settings(root: Node) -> void:
	if root == null:
		return
	for node: Node in root.find_children("*", "WorldEnvironment", true, false):
		_apply_environment(node as WorldEnvironment)
	for node: Node in root.find_children("*", "DirectionalLight3D", true, false):
		_apply_sun(node as DirectionalLight3D)
	for node: Node in root.find_children("*", "Camera3D", true, false):
		var attributes := (node as Camera3D).attributes as CameraAttributesPractical
		if attributes != null:
			_apply_camera_attributes(attributes)


static func _apply_environment(world_env: WorldEnvironment) -> void:
	if not world_env.has_meta(META_LOOK) or world_env.environment == null:
		return
	var wants: Dictionary = world_env.get_meta(META_LOOK)
	var env := world_env.environment
	env.fog_enabled = bool(wants.fog) and PlayerSettings.graphics("fog")
	env.volumetric_fog_enabled = bool(wants.volumetric) and PlayerSettings.graphics("fog")
	env.glow_enabled = bool(wants.glow) and PlayerSettings.graphics("bloom")
	env.ssao_enabled = bool(wants.ssao) and PlayerSettings.graphics("ambient_occlusion")


static func _apply_sun(light: DirectionalLight3D) -> void:
	if light.has_meta(META_LOOK):
		light.shadow_enabled = bool((light.get_meta(META_LOOK) as Dictionary).shadows) and PlayerSettings.graphics("shadows")


static func _apply_camera_attributes(attributes: CameraAttributesPractical) -> void:
	if not attributes.has_meta(META_LOOK):
		return
	var wants: Dictionary = attributes.get_meta(META_LOOK)
	var on := PlayerSettings.graphics("depth_of_field")
	attributes.dof_blur_far_enabled = bool(wants.far) and on
	attributes.dof_blur_near_enabled = bool(wants.near) and on


## The tiled ground plane, centred at `centre`: the look's tile and its variants, mixed region by
## region with tone drift by floor_ground.gdshader (card #186), all in world space so the pattern
## does not move when the plane is centred elsewhere.
## `cover`: the floor reaches at least this far (x, z), for a long zone (DESIGN.md 8.5).
static func ground(look: StageLook, centre: Vector3 = Vector3.ZERO, cover: Vector2 = Vector2.ZERO) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(maxf(look.floor_size, cover.x), maxf(look.floor_size, cover.y))
	var tile_a := AssetLoader.texture(look.floor_tile_path, Vector2i(32, 32))
	var tiles: Array[Texture2D] = [tile_a]
	for path: String in look.floor_variant_paths:
		if tiles.size() < 3 and not path.is_empty():
			tiles.append(AssetLoader.texture(path, Vector2i(32, 32)))
	var mat := ShaderMaterial.new()
	mat.shader = FLOOR_SHADER
	mat.set_shader_parameter("tile_a", tiles[0])
	mat.set_shader_parameter("tile_b", tiles[mini(1, tiles.size() - 1)])
	mat.set_shader_parameter("tile_c", tiles[mini(2, tiles.size() - 1)])
	mat.set_shader_parameter("variants", tiles.size())
	mat.set_shader_parameter("tile_world", maxf(0.01, look.floor_tile_world_size))
	mat.set_shader_parameter("tile_px", float(tile_a.get_width()))
	mat.set_shader_parameter("region_world", look.floor_region_world_size)
	mat.set_shader_parameter("region_warp", look.floor_region_warp)
	mat.set_shader_parameter("mirror", look.floor_mirror)
	mat.set_shader_parameter("tone_world", look.floor_tone_world_size)
	mat.set_shader_parameter("tone_strength", look.floor_tone_strength)
	mat.set_shader_parameter("tone_steps", float(look.floor_tone_steps))
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


## A solid textured block (the texture tiles in world space on every side). With a piece
## (DESIGN.md 5.6) it shows the piece instead of the box, stretched to fill the same size (the
## textures are in world space, so they never stretch).
static func block(data: ZoneBlockData) -> MeshInstance3D:
	if data.piece != null:
		var view := piece_view(data.piece)
		view.rotation_degrees = Vector3(0.0, data.rotation_y_degrees, 0.0)
		view.scale = data.size / view.mesh.get_aabb().size.max(Vector3.ONE * 0.001)
		_stand(view, data.position)
		return view
	var box := BoxMesh.new()
	box.size = data.size
	var node := MeshInstance3D.new()
	node.mesh = box
	node.material_override = _world_material(AssetLoader.texture(data.texture_path, Vector2i(32, 32)),
			data.texture_world_size)
	node.position = data.position + Vector3(0.0, data.size.y * 0.5, 0.0)
	node.rotation_degrees = Vector3(0.0, data.rotation_y_degrees, 0.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return node


## A prop as the game shows it: its 3D piece when it has one (DESIGN.md 5.6), else its sprite.
static func prop_view(data: ZonePropData, look: StageLook = null) -> Node3D:
	if data.piece == null:
		return prop(data, look)
	var view := piece_view(data.piece)
	view.rotation_degrees = Vector3(0.0, data.rotation_y_degrees, 0.0)
	view.scale = Vector3(-data.scale if data.flip else data.scale, data.scale, data.scale)
	_stand(view, data.position)
	return view


## A 3D world piece (DESIGN.md 5.6) at the origin: each of the model's surfaces wears the piece
## surface of the same name (else the one at its index): its texture laid in world space, tinted
## by the model's vertex colours, glowing if it says so. A surface with no match, or a missing
## model (then a 1 m box), shows the checkerboard placeholder, with one warning.
static func piece_view(piece: WorldPieceData) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var model := AssetLoader.mesh(piece.model_path)
	if model == null:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		node.mesh = box
		node.material_override = _world_material(AssetLoader.fallback_texture(Vector2i(32, 32)), 1.6)
		return node
	node.mesh = model
	node.set_meta(META_PIECE, piece)
	for i: int in model.get_surface_count():
		node.set_surface_override_material(i, _piece_material(piece, model, i))
	for carried: PieceSpriteData in piece.sprites:
		if carried == null:
			continue
		var flat := ZonePropData.new()
		flat.sprite_path = carried.sprite_path
		flat.pixel_size = carried.pixel_size
		flat.position = carried.offset
		flat.glow = carried.glow
		flat.glow_color = carried.glow_color
		flat.sway = carried.sway
		node.add_child(prop(flat))
	return node


## Dims a built prop's glow to `share` (a used shrine): a sprite's self glow to share of `glow`,
## or every glowing surface of a 3D piece and the sprites it carries to share of their own (the
## piece takes the dimmed copy of its shared materials, so other copies keep their glow).
static func dim_glow(view: Node3D, glow: float, share: float) -> void:
	var sprite := view as Sprite3D
	if sprite != null:
		(sprite.material_override as ShaderMaterial).set_shader_parameter("self_glow", glow * share)
		return
	var node := view as MeshInstance3D
	if node == null or node.mesh == null or not node.has_meta(META_PIECE):
		return
	var piece := node.get_meta(META_PIECE) as WorldPieceData
	for i: int in node.mesh.get_surface_count():
		var surface := piece_surface(piece, node.mesh, i)
		if surface != null and surface.glow > 0.0:
			node.set_surface_override_material(i, _piece_material(piece, node.mesh, i, share))
	for child: Node in node.get_children():
		var carried := child as Sprite3D
		if carried != null and carried.material_override is ShaderMaterial:
			var mat := carried.material_override as ShaderMaterial
			mat.set_shader_parameter("self_glow", float(mat.get_shader_parameter("self_glow")) * share)


## Moves a placed view (already turned and scaled) so the middle of its mesh's footprint, at the
## mesh's lowest point, lands on `foot`.
static func _stand(view: MeshInstance3D, foot: Vector3) -> void:
	var bounds := view.mesh.get_aabb()
	var own_foot := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	view.position = foot - view.basis * own_foot


## A texture tiled in world space on every side (blocks and pieces).
static func _world_material(tex: Texture2D, world_size: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.texture_repeat = true
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / maxf(0.01, world_size)
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	return mat


## The material of surface `index` of a piece's model with its glow times `glow_share`, shared by
## every copy (fewer materials draw faster). The cache keeps every one alive: a material owned by a
## node alone errors in the renderer when the node is freed.
static func _piece_material(piece: WorldPieceData, model: Mesh, index: int,
		glow_share: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%d|%.3f" % [piece.resource_path if not piece.resource_path.is_empty()
			else str(piece.get_instance_id()), index, glow_share]
	if _piece_materials.has(key):
		return _piece_materials[key]
	var surface := piece_surface(piece, model, index)
	if surface == null:
		push_warning("StageBuilder: piece '%s' has no surface for the model's surface %d" % [piece.id, index])
	var mat := _make_piece_material(piece, surface, glow_share)
	_piece_materials[key] = mat
	return mat


## A new material for one piece surface (null: the checkerboard), its glow times `glow_share`.
static func _make_piece_material(piece: WorldPieceData, surface: PieceSurfaceData,
		glow_share: float = 1.0) -> StandardMaterial3D:
	var mat: StandardMaterial3D
	if surface == null:
		mat = _world_material(AssetLoader.fallback_texture(Vector2i(32, 32)), 1.6)
	else:
		var tex := AssetLoader.texture(surface.texture_path, Vector2i(32, 32))
		mat = _world_material(tex, surface.texture_world_size)
		if surface.glow > 0.0:
			mat.emission_enabled = true
			mat.emission = surface.glow_color
			mat.emission_energy_multiplier = surface.glow * glow_share
			mat.emission_texture = tex
	mat.vertex_color_use_as_albedo = true
	mat.uv1_triplanar_sharpness = piece.texture_sharpness
	return mat


## The piece surface that paints surface `index` of the model: the one named like the model's
## material there, else the one at the same index, else null.
static func piece_surface(piece: WorldPieceData, model: Mesh, index: int) -> PieceSurfaceData:
	var own := model.surface_get_material(index)
	if own != null:
		for surface: PieceSurfaceData in piece.surfaces:
			if surface != null and surface.name == own.resource_name:
				return surface
	return piece.surfaces[index] if index < piece.surfaces.size() else null


## A lit billboard sprite standing at its feet (trees, rocks, lamps). With a `look`, it gets a
## soft contact shadow blob on the ground under it (card #186), a child that moves with it.
static func prop(data: ZonePropData, look: StageLook = null) -> Sprite3D:
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
	mat.set_shader_parameter("sway", data.sway)
	sprite.material_override = mat
	if look != null and data.contact_shadow and data.glow <= 0.0:
		var shadow := contact_shadow(data, tex, look)
		if shadow != null:
			sprite.add_child(shadow)
	return sprite


## The ground blob under a prop (null if its footprint is too thin). Wide as the prop's footprint
## times the look's width share, slid away from the sun, lying flat just over the floor. A child
## of the prop sprite, so it takes the prop's place (its y is taken off to land on the floor).
static func contact_shadow(data: ZonePropData, tex: Texture2D, look: StageLook) -> Sprite3D:
	if look.prop_shadow_opacity <= 0.0 or tex == null:
		return null
	var footprint := footprint_width_px(tex, look.prop_shadow_footprint_percent)
	if footprint < look.prop_shadow_min_footprint_px:
		return null
	var blob := AssetLoader.texture(look.prop_shadow_path, Vector2i(32, 12))
	var width := float(footprint) * data.pixel_size * float(look.prop_shadow_width_percent) / 100.0
	var shadow := Sprite3D.new()
	shadow.name = "ContactShadow"
	shadow.texture = blob
	shadow.pixel_size = width / float(maxi(1, blob.get_width()))
	shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	shadow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.modulate = Color(1.0, 1.0, 1.0, look.prop_shadow_opacity)
	var away := sun_direction_on_ground(look.light_rotation_degrees) * width * float(look.prop_shadow_shift_percent) / 100.0
	shadow.position = Vector3(away.x, look.prop_shadow_lift - data.position.y, away.y)
	return shadow


## Which way a shadow falls on the ground (unit vector on x, z) for a sun turned by
## `rotation_degrees` (a directional light shines along its own -z).
static func sun_direction_on_ground(rotation_degrees: Vector3) -> Vector2:
	var shine := Basis.from_euler(Vector3(deg_to_rad(rotation_degrees.x), deg_to_rad(rotation_degrees.y),
			deg_to_rad(rotation_degrees.z))) * Vector3.FORWARD
	var flat := Vector2(shine.x, shine.z)
	return flat.normalized() if flat.length() > 0.0001 else Vector2.ZERO


## The widest run of opaque pixels in the lowest `rows_percent` of the texture's height (at least
## two rows), in art pixels: what a prop stands on. Cached per texture.
static func footprint_width_px(tex: Texture2D, rows_percent: int) -> int:
	var id := tex.resource_path if not tex.resource_path.is_empty() else str(tex.get_instance_id())
	var key := "%s|%d" % [id, rows_percent]
	if _footprints.has(key):
		return _footprints[key]
	var width := tex.get_width()
	var image := tex.get_image()
	if image != null and not image.is_empty():
		if image.is_compressed():
			image.decompress()
		width = footprint_of_image(image, rows_percent)
	_footprints[key] = width
	return width


## The pure part of footprint_width_px, for an image.
static func footprint_of_image(image: Image, rows_percent: int) -> int:
	var h := image.get_height()
	var rows := maxi(2, int(ceil(float(h) * float(rows_percent) / 100.0)))
	var best := 0
	for y: int in range(maxi(0, h - rows), h):
		var first := -1
		var last := -1
		for x: int in image.get_width():
			if image.get_pixel(x, y).a >= 0.5:
				if first < 0:
					first = x
				last = x
		if first >= 0:
			best = maxi(best, last - first + 1)
	return best


## A piece of ground on the floor (DESIGN.md 8.12): a road, mud, planks or water, lying `lift`
## over the floor (GroundStack gives every overlapping piece its own height).
static func ground_patch(data: ZoneGroundData, lift: float) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = data.size
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	var tex := AssetLoader.texture(data.texture_path, Vector2i(32, 32))
	mat.set_shader_parameter("ground_texture", tex)
	mat.set_shader_parameter("tile_world", data.texture_world_size)
	mat.set_shader_parameter("tile_px", float(tex.get_width()) if tex != null else 32.0)
	mat.set_shader_parameter("tint", data.tint)
	mat.set_shader_parameter("half_size", data.size * 0.5)
	mat.set_shader_parameter("round_shape", data.round)
	mat.set_shader_parameter("edge_noise", data.edge_noise)
	mat.set_shader_parameter("water", data.kind == ZoneGroundData.Kind.WATER)
	mat.set_shader_parameter("deep_color", data.deep_color)
	mat.set_shader_parameter("fringe_px", float(data.fringe_pixels))
	mat.set_shader_parameter("edge_shade", data.edge_shade)
	mat.set_shader_parameter("flow_dir", water_flow(data))
	mat.set_shader_parameter("ripple", data.ripples)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = Vector3(data.position.x, lift, data.position.z)
	node.rotation_degrees = Vector3(0.0, data.rotation_y_degrees, 0.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## A stream's flow for the water shader: the piece's flow turned with the piece into world x and z,
## in texture tiles a second (zero: still water).
static func water_flow(data: ZoneGroundData) -> Vector2:
	var turned := Vector3(data.flow.x, 0.0, data.flow.y).rotated(Vector3.UP, deg_to_rad(data.rotation_y_degrees))
	return Vector2(turned.x, turned.z) / maxf(0.01, data.texture_world_size)


## Particles always drifting through a place (DESIGN.md 8.12), in a box around the node's spot
## (move the node with the camera; the particles stay where they are in the world).
static func ambient(data: ZoneAmbientData) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = data.area
	var speed := data.velocity.length()
	process.direction = data.velocity.normalized() if speed > 0.0001 else Vector3.UP
	process.spread = data.spread
	process.initial_velocity_min = speed * 0.6
	process.initial_velocity_max = speed * 1.4
	process.gravity = Vector3.ZERO
	process.scale_min = 0.7
	process.scale_max = 1.3
	if data.wobble > 0.0:
		process.turbulence_enabled = true
		process.turbulence_noise_strength = data.wobble
		process.turbulence_noise_scale = 2.5
		process.turbulence_influence_min = 0.05
		process.turbulence_influence_max = 0.15
	if data.spin:
		process.angle_min = -180.0
		process.angle_max = 180.0
		process.angular_velocity_min = -90.0
		process.angular_velocity_max = 90.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	process.color = data.color
	var quad := QuadMesh.new()
	quad.size = Vector2(data.size, data.size)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = AssetLoader.texture(data.texture_path, Vector2i(4, 4))
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if data.glow > 0.0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if data.soft else BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	if data.glow > 0.0:
		mat.emission_enabled = true
		mat.emission = data.color
		mat.emission_energy_multiplier = data.glow
		mat.emission_texture = mat.albedo_texture
	quad.material = mat
	var particles := GPUParticles3D.new()
	particles.name = "Ambient_" + data.id
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.amount = data.amount
	particles.lifetime = data.lifetime
	particles.preprocess = data.lifetime
	particles.local_coords = false
	particles.visibility_aabb = AABB(-data.area - Vector3(20, 10, 20), (data.area + Vector3(20, 10, 20)) * 2.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


## A one-time puff of the same particles (a boss's rage): all at once, then they drift off and the
## node removes itself.
static func burst(data: ZoneAmbientData) -> GPUParticles3D:
	var particles := ambient(data)
	particles.name = "Burst_" + data.id
	particles.preprocess = 0.0
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	return particles


## A point light, flickering if the data says so.
static func light(data: ZoneLightData) -> OmniLight3D:
	var lamp := FlickerLight.new()
	lamp.position = data.position
	lamp.light_color = data.color
	lamp.omni_range = data.reach
	lamp.shadow_enabled = data.shadows
	lamp.setup(data.energy, data.flicker_percent, data.flicker_hz)
	return lamp


## Adds every block, prop and light (and ground piece) under `parent`. With a `look`, props get
## contact shadows; ground pieces take their heights from it (the StageLook defaults without one).
static func add_contents(parent: Node3D, blocks: Array[ZoneBlockData], props: Array[ZonePropData],
		lights: Array[ZoneLightData], grounds: Array[ZoneGroundData] = [], look: StageLook = null) -> void:
	var levels := GroundStack.levels(grounds)
	var heights := look if look != null else StageLook.new()
	for i: int in grounds.size():
		if grounds[i] != null:
			parent.add_child(ground_patch(grounds[i], GroundStack.lift(heights, levels[i])))
	for data: ZoneBlockData in blocks:
		if data != null:
			parent.add_child(block(data))
	for data: ZonePropData in props:
		if data != null:
			parent.add_child(prop_view(data, look))
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
