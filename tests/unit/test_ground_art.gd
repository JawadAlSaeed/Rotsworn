extends GutTest
## Ground art (card #186): the floor mixes tile variants with a shader, props get contact shadow
## blobs sized from their footprint, and pixels stay one size (props at the fighters' density,
## ground pieces at the floor's tile size).

const LOOK_DIR := "res://data/looks/"
## Fighters are drawn at 0.045 a pixel; scenery may be a hair chunkier, never more.
const MAX_PROP_PIXEL := 0.0501
const MIN_PROP_PIXEL := 0.0449


func _image(rows: Array[String]) -> Image:
	# '#' is an opaque pixel, anything else is clear.
	var img := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	for y: int in rows.size():
		for x: int in rows[y].length():
			img.set_pixel(x, y, Color(1, 1, 1, 1) if rows[y][x] == "#" else Color(0, 0, 0, 0))
	return img


func _list(dir: String) -> Array[Resource]:
	var out: Array[Resource] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			out.append(load(dir + file))
	return out


func _looks() -> Array[StageLook]:
	var out: Array[StageLook] = []
	for res: Resource in _list(LOOK_DIR):
		if res is StageLook:
			out.append(res)
	return out


# --- footprint and shadow ---------------------------------------------------------------------

func test_footprint_is_the_widest_opaque_run_in_the_lowest_rows() -> void:
	var img := _image([
		"..####..",
		"..####..",
		"...##...",
		"..#..#..",
		".#....#.",
	])
	# 40 percent of 5 rows = 2 rows: the last two, whose widest runs are 4 and 6 wide.
	assert_eq(StageBuilder.footprint_of_image(img, 40), 6, "the roots: 6 pixels across")
	# A tiny share still measures two rows at least.
	assert_eq(StageBuilder.footprint_of_image(img, 1), 6)
	assert_eq(StageBuilder.footprint_of_image(_image(["......", "......"]), 50), 0, "clear bottom rows: no footprint")


func test_sun_direction_follows_the_light_yaw_and_is_flat() -> void:
	var d := StageBuilder.sun_direction_on_ground(Vector3(-55.0, -30.0, 0.0))
	assert_almost_eq(d.length(), 1.0, 0.001, "a unit vector on the ground")
	# A light turned -30 degrees about y shines toward -z and a little toward +x.
	assert_lt(d.y, 0.0, "shines away from the camera side")
	assert_almost_eq(d.x, 0.5, 0.01)
	var straight := StageBuilder.sun_direction_on_ground(Vector3(-90.0, 0.0, 0.0))
	assert_eq(straight, Vector2.ZERO, "a sun straight above casts no direction")


func test_prop_gets_a_contact_shadow_sized_from_its_footprint() -> void:
	var look := StageLook.new()
	look.prop_shadow_width_percent = 200
	look.prop_shadow_footprint_percent = 30
	var data := ZonePropData.new()
	data.sprite_path = "res://assets/sprites/env/rotten_tree.png"
	data.pixel_size = 0.05
	data.position = Vector3(2.0, 0.0, -3.0)
	var sprite := StageBuilder.prop(data, look)
	var shadow := sprite.get_node_or_null("ContactShadow") as Sprite3D
	assert_not_null(shadow, "a tree stands on a blob")
	if shadow == null:
		return
	var tex := sprite.texture
	var feet := StageBuilder.footprint_width_px(tex, 30)
	assert_gt(feet, look.prop_shadow_min_footprint_px, "the trunk and roots are wider than the minimum")
	var width := float(shadow.texture.get_width()) * shadow.pixel_size
	assert_almost_eq(width, float(feet) * 0.05 * 2.0, 0.001, "width = footprint x pixel size x width share")
	assert_almost_eq(shadow.position.y, look.prop_shadow_lift, 0.0001, "lies just over the floor")
	assert_eq(shadow.rotation_degrees, Vector3(-90.0, 0.0, 0.0), "lies flat")
	sprite.free()


func test_shadow_lands_on_the_floor_when_the_prop_is_raised() -> void:
	var look := StageLook.new()
	var data := ZonePropData.new()
	data.sprite_path = "res://assets/sprites/env/rotten_tree.png"
	data.position = Vector3(0.0, 0.5, 0.0)
	var sprite := StageBuilder.prop(data, look)
	var shadow := sprite.get_node("ContactShadow") as Sprite3D
	assert_almost_eq(shadow.position.y + data.position.y, look.prop_shadow_lift, 0.0001,
			"local y cancels the prop's own height")
	sprite.free()


func test_no_shadow_without_a_look_or_for_glowing_or_flat_props() -> void:
	var look := StageLook.new()
	var data := ZonePropData.new()
	data.sprite_path = "res://assets/sprites/env/rotten_tree.png"
	var plain := StageBuilder.prop(data)
	assert_null(plain.get_node_or_null("ContactShadow"), "no look, no blob")
	plain.free()
	data.glow = 1.0
	var glowing := StageBuilder.prop(data, look)
	assert_null(glowing.get_node_or_null("ContactShadow"), "light sources do not cast a blob")
	glowing.free()
	data.glow = 0.0
	data.contact_shadow = false
	var flat := StageBuilder.prop(data, look)
	assert_null(flat.get_node_or_null("ContactShadow"), "ground cover opts out")
	flat.free()
	data.contact_shadow = true
	look.prop_shadow_opacity = 0.0
	var off := StageBuilder.prop(data, look)
	assert_null(off.get_node_or_null("ContactShadow"), "opacity 0 turns them off")
	off.free()


# --- the floor ---------------------------------------------------------------------------------

func test_floor_uses_the_look_s_variants_and_numbers() -> void:
	var look := StageLook.new()
	look.floor_tile_path = "res://assets/sprites/env/hollow_floor.png"
	look.floor_variant_paths = ["res://assets/sprites/env/hollow_floor_b.png", "res://assets/sprites/env/hollow_floor_c.png"]
	look.floor_region_world_size = 5.0
	look.floor_tone_strength = 0.2
	var floor_mesh := StageBuilder.ground(look)
	var mat := floor_mesh.material_override as ShaderMaterial
	assert_not_null(mat, "the floor is a shader now")
	assert_eq(mat.get_shader_parameter("variants"), 3)
	assert_eq(mat.get_shader_parameter("region_world"), 5.0)
	assert_almost_eq(float(mat.get_shader_parameter("tone_strength")), 0.2, 0.0001)
	var bare := StageLook.new()
	bare.floor_tile_path = look.floor_tile_path
	var single_mesh := StageBuilder.ground(bare)
	var single := single_mesh.material_override as ShaderMaterial
	assert_eq(single.get_shader_parameter("variants"), 1, "no variants listed: one tile")
	single_mesh.free()
	floor_mesh.free()


func test_every_look_ships_three_floor_tiles_and_regions_on() -> void:
	var looks := _looks()
	assert_eq(looks.size(), 5, "five places: the three zones and two lairs (the throne, the Leech Queen's)")
	for look: StageLook in looks:
		assert_eq(look.floor_variant_paths.size(), 2, "%s: two variants beside the base tile" % look.floor_tile_path)
		assert_gt(look.floor_region_world_size, 0.0, "%s: regions on" % look.floor_tile_path)
		assert_gt(look.prop_shadow_opacity, 0.0, "%s: contact shadows on" % look.floor_tile_path)
		for path: String in [look.floor_tile_path] + look.floor_variant_paths:
			assert_true(ResourceLoader.exists(path), "%s exists" % path)
	var bases := {}
	for look: StageLook in looks:
		bases[look.floor_tile_path] = true
	assert_eq(bases.size(), 5, "every place has its own floor (the boss halls reuse no zone's)")


# --- pixel density -----------------------------------------------------------------------------

func test_scenery_pixels_match_the_fighters() -> void:
	# Since phase 26 (DESIGN.md 8.22) the arenas are the only scenery: the zones' sections are gone.
	var props: Array[ZonePropData] = []
	for look: StageLook in _looks():
		props.append_array(look.arena_props)
	assert_gt(props.size(), 5, "found the arenas' props")
	var bad: Array[String] = []
	for p: ZonePropData in props:
		if p.pixel_size > MAX_PROP_PIXEL or p.pixel_size < MIN_PROP_PIXEL:
			bad.append("%s %.3f" % [p.sprite_path.get_file(), p.pixel_size])
	assert_eq(bad.size(), 0, "props outside 0.045 to 0.05 a pixel: %s" % ", ".join(bad.slice(0, 6)))
