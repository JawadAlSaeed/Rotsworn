extends GutTest
## 3D world pieces made in Blender (DESIGN 5.6): a block with a piece shows it stretched to the
## block's size with its footprint centred on the block's position (turned too); a prop with a
## piece stands at its own size times its scale, turned and mirrored, solid as a circle; each model
## surface wears the piece surface of the same name (texture in world space, vertex colours,
## glow); a missing model or an unmatched surface shows the placeholder. Every model and piece file
## keeps the contract.

const MODELS_DIR := "res://assets/models"
const PIECES_DIR := "res://data/pieces"
const WALL := "res://data/pieces/ruin_wall_broken.tres"
const STUMP := "res://data/pieces/stump_rotten.tres"
const EPS: float = 0.01


func _files(dir_path: String, suffix: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir != null:
		for file: String in dir.get_files():
			if file.ends_with(suffix):
				found.append(dir_path.path_join(file))
	return found


func _piece(path: String) -> WorldPieceData:
	return load(path) as WorldPieceData if ResourceLoader.exists(path) else null


func _block(piece: WorldPieceData, size: Vector3, pos: Vector3, degrees: float = 0.0) -> ZoneBlockData:
	var data := ZoneBlockData.new()
	data.piece = piece
	data.size = size
	data.position = pos
	data.rotation_y_degrees = degrees
	return data


## The node's mesh bounds in its parent's space (corners moved by its transform).
func _placed_bounds(node: MeshInstance3D) -> AABB:
	var box := node.mesh.get_aabb()
	var out := AABB(node.transform * box.position, Vector3.ZERO)
	for i: int in 8:
		out = out.expand(node.transform * box.get_endpoint(i))
	return out


func _material(node: MeshInstance3D, surface: int) -> StandardMaterial3D:
	var mat := node.get_surface_override_material(surface)
	return (mat if mat != null else node.material_override) as StandardMaterial3D


# --- blocks -------------------------------------------------------------------------------------

func test_a_block_without_a_piece_is_the_plain_box() -> void:
	var node := StageBuilder.block(_block(null, Vector3(2, 3, 4), Vector3(1, 0, 2)))
	assert_true(node.mesh is BoxMesh, "a box")
	assert_almost_eq(node.position, Vector3(1, 1.5, 2), Vector3(EPS, EPS, EPS), "standing on its position")
	node.free()


func test_a_piece_with_a_missing_model_is_a_placeholder_box_of_the_block_size() -> void:
	var piece := WorldPieceData.new()
	piece.model_path = "res://assets/models/no_such_piece.glb"
	var node := StageBuilder.block(_block(piece, Vector3(2, 3, 4), Vector3(1, 0, 2)))
	assert_true(node.mesh is BoxMesh, "the placeholder box, not a crash")
	var placed := _placed_bounds(node)
	assert_almost_eq(placed.size, Vector3(2, 3, 4), Vector3(EPS, EPS, EPS), "as big as the block")
	assert_almost_eq(placed.position.y, 0.0, EPS, "standing on the ground")
	node.free()


func test_a_block_piece_fills_the_block_and_stands_on_its_position() -> void:
	var wall := _piece(WALL)
	if wall == null:
		pending("%s not made yet" % WALL)
		return
	var size := Vector3(3.0, 2.0, 1.5)
	var node := StageBuilder.block(_block(wall, size, Vector3(5, 0, -6)))
	assert_false(node.mesh is BoxMesh, "the model's mesh")
	var placed := _placed_bounds(node)
	assert_almost_eq(placed.size, size, Vector3(EPS, EPS, EPS), "stretched to the block's size")
	assert_almost_eq(placed.position.y, 0.0, EPS, "foot on the ground")
	assert_almost_eq(placed.get_center().x, 5.0, EPS, "footprint centred on x")
	assert_almost_eq(placed.get_center().z, -6.0, EPS, "footprint centred on z")
	var mat := _material(node, 0)
	assert_true(mat.vertex_color_use_as_albedo, "vertex colours tint the texture")
	assert_true(mat.uv1_world_triplanar, "the texture is laid in world space")
	node.free()


func test_a_turned_block_piece_keeps_its_footprint_centred() -> void:
	var wall := _piece(WALL)
	if wall == null:
		pending("%s not made yet" % WALL)
		return
	var node := StageBuilder.block(_block(wall, Vector3(4, 2, 1), Vector3(2, 0, 3), 90.0))
	var placed := _placed_bounds(node)
	assert_almost_eq(placed.size.x, 1.0, EPS, "a quarter turn swaps length and depth")
	assert_almost_eq(placed.size.z, 4.0, EPS)
	assert_almost_eq(placed.get_center().x, 2.0, EPS)
	assert_almost_eq(placed.get_center().z, 3.0, EPS)
	assert_almost_eq(placed.position.y, 0.0, EPS)
	node.free()


# --- props --------------------------------------------------------------------------------------

func test_a_prop_without_a_piece_is_still_a_sprite() -> void:
	var data := ZonePropData.new()
	data.position = Vector3(1, 0, 1)
	var view := StageBuilder.prop_view(data)
	assert_true(view is Sprite3D, "the sprite")
	view.free()


func test_a_prop_piece_stands_at_its_own_size_times_its_scale() -> void:
	var stump := _piece(STUMP)
	if stump == null:
		pending("%s not made yet" % STUMP)
		return
	var natural := AssetLoader.mesh(stump.model_path).get_aabb().size
	var data := ZonePropData.new()
	data.piece = stump
	data.position = Vector3(3, 0, -2)
	data.scale = 0.5
	var view := StageBuilder.prop_view(data) as MeshInstance3D
	assert_not_null(view, "a 3D piece")
	var placed := _placed_bounds(view)
	assert_almost_eq(placed.size, natural * 0.5, Vector3(EPS, EPS, EPS), "half its own size")
	assert_almost_eq(placed.position.y, 0.0, EPS, "foot on the ground")
	assert_almost_eq(placed.get_center().x, 3.0, EPS, "footprint on its position (x)")
	assert_almost_eq(placed.get_center().z, -2.0, EPS, "footprint on its position (z)")
	view.free()


func test_a_flipped_prop_piece_is_mirrored_and_a_turned_one_turns() -> void:
	var stump := _piece(STUMP)
	if stump == null:
		pending("%s not made yet" % STUMP)
		return
	var data := ZonePropData.new()
	data.piece = stump
	data.flip = true
	data.rotation_y_degrees = 30.0
	var view := StageBuilder.prop_view(data) as MeshInstance3D
	assert_lt(view.transform.basis.determinant(), 0.0, "mirrored")
	assert_almost_eq(view.rotation_degrees.y, 30.0, 0.1, "turned")
	view.free()


func test_a_solid_prop_piece_blocks_walking_as_a_circle() -> void:
	var zone := ZoneData.new()
	var data := ZonePropData.new()
	data.piece = WorldPieceData.new()
	data.position = Vector3(4, 0, 0)
	data.solid_radius = 0.6
	zone.props.append(data)
	var obstacles := ZoneMotion.obstacles(zone)
	assert_eq(obstacles.size(), 1, "one obstacle")
	assert_almost_eq(float(obstacles[0].radius), 0.6, EPS, "a circle of its solid radius")


# --- surfaces -----------------------------------------------------------------------------------

func test_each_surface_wears_the_piece_surface_of_its_name() -> void:
	var stump := _piece(STUMP)
	if stump == null:
		pending("%s not made yet" % STUMP)
		return
	var model := AssetLoader.mesh(stump.model_path)
	var view := StageBuilder.piece_view(stump)
	assert_eq(model.get_surface_count(), 2, "bark and rot")
	for i: int in model.get_surface_count():
		var own := model.surface_get_material(i).resource_name
		var surface := StageBuilder.piece_surface(stump, model, i)
		assert_eq(surface.name, own, "surface %d is matched by name" % i)
		var tex := _material(view, i).albedo_texture
		assert_eq(tex.resource_path, surface.texture_path, "surface %d wears its texture" % i)
	view.free()


func test_a_glowing_surface_lights_up() -> void:
	var piece := (load(STUMP) as WorldPieceData).duplicate(true) if ResourceLoader.exists(STUMP) else null
	if piece == null:
		pending("%s not made yet" % STUMP)
		return
	piece.surfaces[0].glow = 2.5
	piece.surfaces[0].glow_color = Color(1.0, 0.6, 0.2)
	var view := StageBuilder.piece_view(piece)
	var model := view.mesh
	for i: int in model.get_surface_count():
		var mat := _material(view, i)
		var surface := StageBuilder.piece_surface(piece, model, i)
		if surface == piece.surfaces[0]:
			assert_true(mat.emission_enabled, "the glowing surface emits")
			assert_almost_eq(mat.emission_energy_multiplier, 2.5, EPS)
			assert_eq(mat.emission, Color(1.0, 0.6, 0.2))
		else:
			assert_false(mat.emission_enabled, "the other surface does not")
	view.free()


func test_a_surface_with_no_match_shows_the_placeholder() -> void:
	var stump := _piece(STUMP)
	if stump == null:
		pending("%s not made yet" % STUMP)
		return
	var bare := WorldPieceData.new()
	bare.model_path = stump.model_path
	var view := StageBuilder.piece_view(bare)
	assert_eq(_material(view, 0).albedo_texture, AssetLoader.fallback_texture(Vector2i(32, 32)), "the checkerboard")
	view.free()


# --- the files ----------------------------------------------------------------------------------

func test_every_piece_file_matches_its_model() -> void:
	var files := _files(PIECES_DIR, ".tres")
	if files.is_empty():
		pending("no pieces in %s yet" % PIECES_DIR)
		return
	for file: String in files:
		var piece := load(file) as WorldPieceData
		assert_not_null(piece, "%s is a WorldPieceData" % file)
		if piece == null:
			continue
		assert_eq(piece.id, file.get_file().get_basename(), "%s: id is its file name" % file)
		var model := AssetLoader.mesh(piece.model_path)
		assert_not_null(model, "%s: its model loads" % file)
		if model == null:
			continue
		assert_eq(model.get_surface_count(), piece.surfaces.size(), "%s: one surface per model surface" % file)
		for i: int in model.get_surface_count():
			var own := model.surface_get_material(i)
			assert_not_null(own, "%s: model surface %d has a named material" % [file, i])
			if own == null:
				continue
			var named := piece.surfaces.filter(func(s: PieceSurfaceData) -> bool: return s.name == own.resource_name)
			assert_eq(named.size(), 1, "%s: one surface named '%s'" % [file, own.resource_name])


func test_every_model_file_holds_a_mesh_on_the_ground_with_vertex_colours() -> void:
	var files := _files(MODELS_DIR, ".glb")
	if files.is_empty():
		pending("no models in %s yet" % MODELS_DIR)
		return
	for file: String in files:
		var mesh := AssetLoader.mesh(file)
		assert_not_null(mesh, "%s holds a mesh" % file)
		if mesh == null:
			continue
		for i: int in mesh.get_surface_count():
			assert_not_null(mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR], "%s surface %d has vertex colours" % [file, i])
		var box := mesh.get_aabb()
		assert_almost_eq(box.position.y, 0.0, EPS, "%s: foot on the ground" % file)
		assert_almost_eq(box.get_center().x, 0.0, EPS, "%s: footprint centred (x)" % file)
		assert_almost_eq(box.get_center().z, 0.0, EPS, "%s: footprint centred (z)" % file)


# --- fire and shrines ---------------------------------------------------------------------------

const BRAZIER := "res://data/pieces/brazier.tres"
const IDOL := "res://data/pieces/shrine_idol.tres"


func test_a_piece_carries_its_flat_sprites() -> void:
	var brazier := _piece(BRAZIER)
	if brazier == null:
		pending("%s not made yet" % BRAZIER)
		return
	var view := StageBuilder.piece_view(brazier)
	var flames := view.get_children().filter(func(n: Node) -> bool: return n is Sprite3D)
	assert_eq(flames.size(), brazier.sprites.size(), "one sprite per carried sprite")
	var flame := flames[0] as Sprite3D
	assert_almost_eq(flame.position, brazier.sprites[0].offset, Vector3(EPS, EPS, EPS), "at its offset")
	var mat := flame.material_override as ShaderMaterial
	assert_almost_eq(float(mat.get_shader_parameter("self_glow")), brazier.sprites[0].glow, EPS, "it glows")
	view.free()


func test_dimming_a_used_shrine_leaves_its_other_copies_lit() -> void:
	var idol := _piece(IDOL)
	if idol == null:
		pending("%s not made yet" % IDOL)
		return
	var used := StageBuilder.piece_view(idol)
	var other := StageBuilder.piece_view(idol)
	var lit := -1
	for i: int in used.mesh.get_surface_count():
		if _material(used, i).emission_enabled:
			lit = i
	assert_gt(lit, -1, "the idol has a glowing surface")
	var before := _material(other, lit).emission_energy_multiplier
	StageBuilder.dim_glow(used, 0.0, 0.25)
	assert_almost_eq(_material(used, lit).emission_energy_multiplier, before * 0.25, EPS, "the used one dims")
	assert_almost_eq(_material(other, lit).emission_energy_multiplier, before, EPS, "the other copy stays lit")
	used.free()
	other.free()


# --- water and dressing (cards #232 to #236) ----------------------------------------------------

const SECTIONS_DIR := "res://data/zones/sections"
const PATH_GROUNDS := ["dirt_trail", "road_cobble", "paving", "planks"]


func test_a_stream_flows_along_its_own_length_when_turned() -> void:
	var data := ZoneGroundData.new()
	data.kind = ZoneGroundData.Kind.WATER
	data.flow = Vector2(1.6, 0.0)
	data.texture_world_size = 1.6
	data.rotation_y_degrees = 90.0
	var flow := StageBuilder.water_flow(data)
	assert_almost_eq(flow, Vector2(0.0, -1.0), Vector2(EPS, EPS), "a quarter turn sends it along -z, one tile a second")
	data.flow = Vector2.ZERO
	assert_eq(StageBuilder.water_flow(data), Vector2.ZERO, "still water does not flow")


func test_nothing_dressed_stands_on_a_trail_road_or_in_water() -> void:
	var dressed := 0
	for file: String in _files(SECTIONS_DIR, ".tres"):
		var section := load(file) as ZoneSectionData
		var path: Array[Dictionary] = []
		for g: ZoneGroundData in section.grounds:
			if g.resource_name == "dressed":
				continue  # the stream's own water and the bridge over it
			if g.kind == ZoneGroundData.Kind.WATER or PATH_GROUNDS.has(g.texture_path.get_file().get_basename()):
				path.append({"centre": Vector2(g.position.x, g.position.z), "half": g.size * 0.5,
						"angle": deg_to_rad(g.rotation_y_degrees)})
		for p: ZonePropData in section.props:
			if p.resource_name != "dressed" or p.sprite_path.ends_with("reeds.png") or p.piece != null \
					and p.piece.id == "bridge_planks":
				continue
			dressed += 1
			for o: Dictionary in path:
				assert_false(ZonePath._overlaps(Vector2(p.position.x, p.position.z), 0.1, o),
						"%s: dressed %s at %s is on the path or in water" % [section.id,
						p.piece.id if p.piece != null else p.sprite_path.get_file(), p.position])
	assert_gt(dressed, 300, "the zones are dressed")
