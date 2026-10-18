extends SceneTree
## Dev tool (DESIGN.md 5.6, phase 18 step 4, cards #233 to #235): dresses every zone section
## with the 3D world pieces and the new plants. Per section, picked by a seed from its id:
## - big pieces (ledges, ruins, houses, towers) in the back band behind the path, as blocks with
##   a piece (solid as their box);
## - small 3D props (rocks, rubble, stumps, logs, bones) off the path, solid as a circle;
## - clusters of flat plants (grass, flowers, ferns, dead bushes, mushrooms) that sway, never on a
##   trail, road or boardwalk.
## Nothing goes where it would block the way: clear of every solid thing, spot (items, chests,
## seals, shrines, wanderers), enemy home and the lane at both ends, and never on the path ground.
## Everything it adds is named DRESSED (resource_name), so a second run replaces it.
## Rotten Hollow's "fallen" section also gets a stream crossed by a plank bridge; every water
## piece gets ripples (card #232). The fight arenas get cliff ledges (card #236).
## Run: Godot --headless --path . -s tools/dress_zones.gd [-- --only=SECTION_ID|arenas] [--dry-run]

const SECTIONS_DIR := "res://data/zones/sections"
const PIECES_DIR := "res://data/pieces"
const DRESSED := "dressed"
## Ground textures that are the way through: nothing solid or growing goes on them.
const PATH_GROUNDS := ["dirt_trail", "road_cobble", "paving", "planks"]
## How far the back band (big pieces) and the plants reach, on the zone's depth (z).
const BACK_BAND := Vector2(-12.5, -6.5)
const PLANT_BAND := Vector2(-13.0, 9.0)
const SMALL_BAND := Vector2(-6.0, 8.5)
## Keep this much room round spots, enemy homes and the start.
const SPOT_CLEAR: float = 1.4
const START_CLEAR: float = 2.4
## The lane kept free at both ends of a section (ZoneAssembler.LANE plus a margin).
const LANE_X: float = 2.6
const LANE_Z: float = 3.8
const WATER_RIPPLES: float = 0.3

## Per zone: plants [sprite, pixel size, sway, weight], small pieces [piece, min scale, max scale,
## solid radius at scale 1, turn, weight], big pieces [piece, turn, weight]; how many of each per
## metre of section.
const THEMES := {
	"rotten_hollow": {
		"plants": [["grass_tall", 0.045, 0.03, 3], ["flowers_pale", 0.045, 0.02, 2], ["flowers_violet", 0.045, 0.02, 1],
				["fern_big", 0.045, 0.03, 2], ["bush_dead", 0.05, 0.02, 1], ["mushrooms_small", 0.045, 0.0, 1],
				["grass", 0.045, 0.03, 2]],
		"small": [["rock", 0.5, 0.8, 0.6, 180.0, 2], ["rubble", 0.6, 0.9, 0.0, 180.0, 1],
				["stump_rotten", 0.4, 0.6, 0.55, 180.0, 2], ["log", 0.8, 1.0, 0.0, 25.0, 1]],
		"big": [["ledge_rock", 8.0, 3], ["rock_mossy", 30.0, 2], ["house_broken", 6.0, 1], ["ledge_rock_tall", 6.0, 1]],
		"plants_per_m": 1.1, "small_per_m": 0.14, "big_count": 2,
	},
	"ashen_ruins": {
		"plants": [["grass_ash", 0.045, 0.025, 4], ["mushrooms_small", 0.045, 0.0, 1], ["bush_dead", 0.05, 0.02, 2],
				["flowers_violet", 0.045, 0.02, 1]],
		"small": [["rubble", 0.6, 1.0, 0.0, 180.0, 3], ["bones", 0.8, 1.0, 0.0, 180.0, 1],
				["column_fallen", 0.7, 0.9, 0.0, 20.0, 1], ["rock", 0.5, 0.7, 0.6, 180.0, 1]],
		"big": [["tower_ruined", 20.0, 2], ["gate_ruined", 6.0, 1], ["stairs_broken", 10.0, 2], ["house_broken", 6.0, 1],
				["ledge_rock_ash", 6.0, 2]],
		"plants_per_m": 0.8, "small_per_m": 0.16, "big_count": 2,
	},
	"sunken_bog": {
		"plants": [["grass_tall", 0.045, 0.03, 3], ["fern_big", 0.045, 0.03, 2], ["flowers_violet", 0.045, 0.02, 1],
				["mushrooms_small", 0.045, 0.0, 2], ["reeds", 0.045, 0.04, 2]],
		"small": [["log", 0.8, 1.0, 0.0, 25.0, 2], ["stump_rotten", 0.4, 0.6, 0.55, 180.0, 2], ["rock", 0.5, 0.7, 0.6, 180.0, 1]],
		"big": [["ledge_rock_bog", 8.0, 3], ["stilt_hut", 10.0, 1], ["ledge_rock_tall_bog", 6.0, 1]],
		"plants_per_m": 1.0, "small_per_m": 0.12, "big_count": 2,
	},
}

## Each fight arena's own layout (card #236): its back closed by four tall cliff walls in its
## own ground, then its own pieces, all as blocks [piece, x, z, turn in degrees, scale]. The
## fighters stand between x -4 and 4 near z 0 and the camera looks from z 10, so everything here
## stands behind them (z -4.5 and further back) or out at the sides. The looks' shared props
## (trees, pillars, rocks, the lamp, mushrooms, grass) stay.
const ARENA_LAYOUTS := {
	"rotten_hollow": {"cliff": "cliff_wall", "pieces": [
		["ledge_rock_tall", -8.6, -8.4, 6.0, 1.0], ["house_broken", 8.0, -7.9, -8.0, 1.0],
		["rock_mossy", -9.8, -4.8, 20.0, 1.15], ["stump_rotten", 4.9, -5.4, 30.0, 0.55],
		["fence", 3.2, -8.6, 4.0, 1.0], ["log", -3.6, -8.6, 8.0, 1.0]]},
	"ashen_ruins": {"cliff": "cliff_wall_ash", "pieces": [
		["tower_ruined", -8.8, -8.0, 30.0, 1.0], ["gate_ruined", 6.6, -8.1, -6.0, 1.0],
		["stairs_broken", -4.1, -8.7, 8.0, 1.0], ["ledge_rock_tall_ash", 12.2, -8.6, 8.0, 1.0],
		["rubble", 9.6, -4.8, 40.0, 1.0], ["bones", 5.2, -4.7, 30.0, 1.0]]},
	"sunken_bog": {"cliff": "cliff_wall_bog", "pieces": [
		["ledge_rock_tall_bog", -8.8, -8.5, 6.0, 1.0], ["stilt_hut", 8.4, -7.6, -10.0, 1.0],
		["rock_mossy", -9.8, -4.8, 20.0, 1.1], ["log", 4.6, -6.0, 15.0, 1.0],
		["stump_rotten", -3.4, -8.3, 0.0, 0.55], ["swamp_lantern", 6.3, -4.8, 0.0, 1.0]]},
	"hollow_throne": {"cliff": "cliff_wall_ash", "pieces": [
		["stairs_broken", 0.4, -8.9, 0.0, 1.3], ["statue_headless", -8.2, -7.6, 10.0, 1.2],
		["statue_headless", 7.4, -7.4, -12.0, 1.2], ["pillar", 4.3, -8.4, 30.0, 1.0],
		["pillar", -4.6, -8.5, 70.0, 1.0], ["column_fallen", 9.8, -4.6, 70.0, 1.0],
		["rubble", -9.6, -4.6, 20.0, 1.0]]},
}
## Where the four back walls stand (x, z, turn): overlapping a little so their rims join.
const ARENA_CLIFFS: Array[Vector3] = [Vector3(-11.6, 4.0, -10.7), Vector3(-4.2, -3.0, -10.3),
		Vector3(3.3, 2.0, -10.8), Vector3(10.8, -5.0, -10.4)]

var _dry := false
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	var only := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
		elif arg == "--dry-run":
			_dry = true
	var dir := DirAccess.open(SECTIONS_DIR)
	var files := Array(dir.get_files()).filter(func(f: String) -> bool: return f.ends_with(".tres"))
	files.sort()
	if only.is_empty() or only == "arenas":
		_dress_arenas()
	for file: String in files:
		var path := SECTIONS_DIR.path_join(file)
		var section := load(path) as ZoneSectionData
		if section == null or (not only.is_empty() and section.id != only):
			continue
		var zone := _zone_of(section.id)
		if not THEMES.has(zone):
			continue
		_dress(section, THEMES[zone])
		if not _dry:
			var err := ResourceSaver.save(section, path)
			if err != OK:
				push_error("dress_zones: could not save %s (%d)" % [path, err])
	quit()


## The fight arenas (card #236): every block of each look's arena is replaced by its layout:
## four tall cliff walls closing the back (in place of the flat back box), and the arena's own
## ruins, huts and rocks (in place of the side box and the low wall box).
func _dress_arenas() -> void:
	for look_id: String in ARENA_LAYOUTS:
		var path := "res://data/looks/%s.tres" % look_id
		var look := load(path) as StageLook
		if look == null:
			continue
		var layout: Dictionary = ARENA_LAYOUTS[look_id]
		var blocks: Array[ZoneBlockData] = []
		for spot: Vector3 in ARENA_CLIFFS:
			var cliff := _arena_block(String(layout.cliff), spot.x, spot.z, spot.y, 1.0)
			if cliff != null:
				blocks.append(cliff)
		for row: Array in layout.pieces:
			var block := _arena_block(String(row[0]), float(row[1]), float(row[2]), float(row[3]), float(row[4]))
			if block != null:
				blocks.append(block)
		look.arena_blocks = blocks
		print("dressed arena %s: %d pieces%s" % [look_id, blocks.size(), " (dry run)" if _dry else ""])
		if not _dry:
			var err := ResourceSaver.save(look, path)
			if err != OK:
				push_error("dress_zones: could not save %s (%d)" % [path, err])


## One arena piece as a block at its own size times `scale` (an arena is not walked, so its
## blocks only need to stand there).
func _arena_block(piece_id: String, x: float, z: float, turn: float, scale: float) -> ZoneBlockData:
	var piece := _piece(piece_id)
	var mesh := AssetLoader.mesh(piece.model_path) if piece != null else null
	if mesh == null:
		push_error("dress_zones: no piece %s" % piece_id)
		return null
	var block := ZoneBlockData.new()
	block.resource_name = DRESSED
	block.position = Vector3(x, 0.0, z)
	block.size = mesh.get_aabb().size * scale
	block.rotation_y_degrees = turn
	block.piece = piece
	return block


func _zone_of(section_id: String) -> String:
	for zone: String in THEMES:
		if section_id.begins_with(zone):
			return zone
	return ""


func _dress(section: ZoneSectionData, theme: Dictionary) -> void:
	_rng.seed = hash(section.id) & 0x7fffffff
	_undress(section)
	for g: ZoneGroundData in section.grounds:
		if g.kind == ZoneGroundData.Kind.WATER:
			g.ripples = WATER_RIPPLES
	if section.id == "rotten_hollow_fallen":
		_add_stream(section)
	var counts := [0, 0, 0]
	var bigs := 0
	for i: int in 60:
		if bigs >= int(theme.big_count):
			break
		if _place_big(section, _pick(theme.big)):
			bigs += 1
	counts[0] = bigs
	var small_target := int(round(section.width * float(theme.small_per_m)))
	for i: int in small_target * 12:
		if counts[1] >= small_target:
			break
		if _place_small(section, _pick(theme.small)):
			counts[1] += 1
	var plant_target := int(round(section.width * float(theme.plants_per_m)))
	for i: int in plant_target * 4:
		if counts[2] >= plant_target:
			break
		counts[2] += _place_cluster(section, theme.plants, plant_target - counts[2])
	print("dressed %s: %d big, %d small, %d plants%s" % [section.id, counts[0], counts[1], counts[2],
			" (dry run)" if _dry else ""])


## Takes out what an earlier run added.
func _undress(section: ZoneSectionData) -> void:
	section.props = _keep(section.props)
	section.blocks = _keep(section.blocks)
	section.grounds = _keep(section.grounds)


func _keep(list: Array) -> Array:
	return list.filter(func(r: Resource) -> bool: return r != null and r.resource_name != DRESSED)


## A weighted pick from rows whose last column is the weight.
func _pick(rows: Array) -> Array:
	var total := 0.0
	for row: Array in rows:
		total += float(row[-1])
	var at := _rng.randf() * total
	for row: Array in rows:
		at -= float(row[-1])
		if at <= 0.0:
			return row
	return rows[-1]


# --- Room ------------------------------------------------------------------------------------------

## The solid things and the places to keep clear in a section, as ZoneMotion obstacles.
func _obstacles(section: ZoneSectionData) -> Array[Dictionary]:
	var zone := ZoneData.new()
	zone.props = section.props
	zone.blocks = section.blocks
	zone.grounds = section.grounds
	var list := ZoneMotion.obstacles(zone)
	var spots: Array[Vector3] = []
	spots.append_array(section.item_spots)
	spots.append_array(section.chests)
	spots.append_array(section.seal_spots)
	spots.append_array(section.shrine_spots)
	spots.append_array(section.wanderer_spots)
	for s: Vector3 in spots:
		list.append({"centre": Vector2(s.x, s.z), "radius": SPOT_CLEAR})
	for e: ZoneEnemyData in section.enemies:
		if e != null:
			list.append({"centre": Vector2(e.position.x, e.position.z), "radius": e.wander_radius + SPOT_CLEAR})
			if e.champion:
				list.append({"centre": Vector2(e.prize_spot.x, e.prize_spot.z), "radius": SPOT_CLEAR})
	if section.gate != null:
		var g := section.gate
		list.append({"centre": Vector2(g.position.x, g.position.z), "half": Vector2(g.size.x * 0.5 + 1.5, g.size.z * 0.5),
				"angle": deg_to_rad(g.rotation_y_degrees)})
	list.append({"centre": Vector2(section.player_start.x, section.player_start.z), "radius": START_CLEAR})
	for x: float in [LANE_X * 0.5, section.width - LANE_X * 0.5]:
		list.append({"centre": Vector2(x, 0.0), "half": Vector2(LANE_X * 0.5, LANE_Z), "angle": 0.0})
	return list


## The path ground (trails, roads, boardwalks) and all water, as obstacles for things placed on it.
func _path_ground(section: ZoneSectionData) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for g: ZoneGroundData in section.grounds:
		if g == null:
			continue
		var name := g.texture_path.get_file().get_basename()
		if g.kind == ZoneGroundData.Kind.WATER or PATH_GROUNDS.has(name):
			var half := g.size * 0.5
			list.append({"centre": Vector2(g.position.x, g.position.z), "half": half,
					"angle": deg_to_rad(g.rotation_y_degrees)})
	return list


func _clear(pos: Vector2, radius: float, lists: Array) -> bool:
	for list: Array in lists:
		for o: Dictionary in list:
			if ZonePath._overlaps(pos, radius, o):
				return false
	return true


func _random_spot(section: ZoneSectionData, band: Vector2, margin: float) -> Vector2:
	return Vector2(_rng.randf_range(margin, section.width - margin), _rng.randf_range(band.x, band.y))


func _piece(id: String) -> WorldPieceData:
	return load(PIECES_DIR.path_join(id + ".tres")) as WorldPieceData


# --- Placing ---------------------------------------------------------------------------------------

## A big piece in the back band, as a block (solid as its box), if it fits.
func _place_big(section: ZoneSectionData, row: Array) -> bool:
	var piece := _piece(String(row[0]))
	var mesh := AssetLoader.mesh(piece.model_path) if piece != null else null
	if mesh == null:
		return false
	var size := mesh.get_aabb().size
	var turn := _rng.randf_range(-float(row[1]), float(row[1]))
	var pos := _random_spot(section, BACK_BAND, size.x * 0.5 + 1.0)
	var box := {"centre": pos, "half": Vector2(size.x, size.z) * 0.5 + Vector2(0.4, 0.4), "angle": deg_to_rad(turn)}
	for list: Array in [_obstacles(section), _path_ground(section)]:
		for o: Dictionary in list:
			if _boxes_touch(box, o):
				return false
	var block := ZoneBlockData.new()
	block.resource_name = DRESSED
	block.position = Vector3(pos.x, 0.0, pos.y)
	block.size = size
	block.rotation_y_degrees = turn
	block.piece = piece
	section.blocks.append(block)
	return true


## Do a box and an obstacle overlap? Sampled: the box's corners, edge middles and centre against
## the obstacle, and the obstacle's centre against the box (good enough for laying out scenery).
func _boxes_touch(box: Dictionary, o: Dictionary) -> bool:
	var half: Vector2 = box.half
	var angle: float = box.angle
	for fx: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for fz: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var p: Vector2 = box.centre + Vector2(half.x * fx, half.y * fz).rotated(-angle)
			if ZonePath._overlaps(p, 0.05, o):
				return true
	return ZonePath._overlaps(o.centre, 0.05, box)


## A small 3D prop off the path, solid as a circle (or walk-through), if it fits.
func _place_small(section: ZoneSectionData, row: Array) -> bool:
	var piece := _piece(String(row[0]))
	if piece == null:
		return false
	var scale := _rng.randf_range(float(row[1]), float(row[2]))
	var radius := float(row[3]) * scale
	var mesh := AssetLoader.mesh(piece.model_path)
	var reach := maxf(radius, (Vector2(mesh.get_aabb().size.x, mesh.get_aabb().size.z) * 0.5 * scale).length()) \
			if mesh != null else radius
	var pos := _random_spot(section, SMALL_BAND, 1.0)
	if not _clear(pos, reach + 0.3, [_obstacles(section), _path_ground(section)]):
		return false
	var prop := ZonePropData.new()
	prop.resource_name = DRESSED
	prop.position = Vector3(pos.x, 0.0, pos.y)
	prop.piece = piece
	prop.scale = snappedf(scale, 0.01)
	prop.rotation_y_degrees = snappedf(_rng.randf_range(-float(row[4]), float(row[4])), 0.5)
	prop.flip = _rng.randf() < 0.5
	prop.solid_radius = snappedf(radius, 0.05)
	section.props.append(prop)
	return true


## A cluster of 2 to 6 plants round a free spot (never on the path or in water). Returns how many.
func _place_cluster(section: ZoneSectionData, plants: Array, left: int) -> int:
	var centre := _random_spot(section, PLANT_BAND, 0.8)
	var blockers := [_solid_only(_obstacles(section)), _path_ground(section)]
	if not _clear(centre, 0.4, blockers):
		return 0
	var kind := _pick(plants)
	var n := mini(left, _rng.randi_range(2, 6))
	var made := 0
	for i: int in n:
		var row := kind if _rng.randf() < 0.7 else _pick(plants)
		var pos := centre + Vector2(_rng.randf_range(-1.4, 1.4), _rng.randf_range(-0.9, 0.9))
		if not _clear(pos, 0.3, blockers):
			continue
		var prop := ZonePropData.new()
		prop.resource_name = DRESSED
		prop.sprite_path = "res://assets/sprites/env/%s.png" % String(row[0])
		prop.pixel_size = float(row[1])
		prop.sway = float(row[2])
		prop.position = Vector3(snappedf(pos.x, 0.01), 0.0, snappedf(pos.y, 0.01))
		prop.flip = _rng.randf() < 0.5
		prop.contact_shadow = false
		section.props.append(prop)
		made += 1
	return made


## Plants may grow round spots and enemy homes; only solid things and the lane keep them away.
func _solid_only(list: Array[Dictionary]) -> Array[Dictionary]:
	return list.filter(func(o: Dictionary) -> bool: return not (o.has("radius") and is_equal_approx(float(o.radius), SPOT_CLEAR)))


# --- The stream ------------------------------------------------------------------------------------

## A stream across the section from back to front, flowing toward the camera, crossed by a plank
## bridge where the trail meets it; reeds along its banks. Placed where it hits fewest things;
## plants and props in its bed are cleared.
func _add_stream(section: ZoneSectionData) -> void:
	var best_x := section.width * 0.5
	var best := 1 << 30
	for i: int in 13:
		var x := 7.0 + float(i) * (section.width - 14.0) / 12.0
		var hits := 0
		for p: ZonePropData in section.props:
			if absf(p.position.x - x) < 1.8:
				hits += 3 if p.solid_radius > 0.0 else 1
		for e: ZoneEnemyData in section.enemies:
			if e != null and absf(e.position.x - x) < e.wander_radius + 2.0:
				hits += 50
		for s: Vector3 in section.item_spots + section.chests + section.seal_spots + section.shrine_spots \
				+ section.wanderer_spots:
			if absf(s.x - x) < 2.4:
				hits += 50
		if hits < best:
			best = hits
			best_x = x
	section.props = section.props.filter(func(p: ZonePropData) -> bool: return absf(p.position.x - best_x) >= 1.6)
	var gap := 0.8  # half the bridge's width: the trail crosses dry-shod here
	for part: Array in [[-20.0, -gap, true], [-gap, gap, false], [gap, 10.0, true]]:
		var water := ZoneGroundData.new()
		water.resource_name = DRESSED
		water.kind = ZoneGroundData.Kind.WATER
		water.position = Vector3(best_x, 0.0, (float(part[0]) + float(part[1])) * 0.5)
		water.size = Vector2(2.4, float(part[1]) - float(part[0]))
		water.texture_path = "res://assets/sprites/env/water.png"
		water.edge_noise = 0.35 if bool(part[2]) else 0.0
		water.tint = Color(0.72, 0.88, 0.8)
		water.deep_color = Color(0.04, 0.08, 0.07)
		water.solid = bool(part[2])
		water.flow = Vector2(0.0, 0.45)
		water.ripples = WATER_RIPPLES
		section.grounds.append(water)
	var bridge := ZonePropData.new()
	bridge.resource_name = DRESSED
	bridge.position = Vector3(best_x, -0.24, 0.0)
	bridge.piece = _piece("bridge_planks")
	section.props.append(bridge)
	for i: int in 10:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := _rng.randf_range(-15.0, 8.0)
		if absf(z) < 2.4:
			continue
		var reed := ZonePropData.new()
		reed.resource_name = DRESSED
		reed.sprite_path = "res://assets/sprites/env/reeds.png"
		reed.pixel_size = 0.045
		reed.sway = 0.04
		reed.contact_shadow = false
		reed.position = Vector3(snappedf(best_x + side * 1.35, 0.01), 0.0, snappedf(z, 0.01))
		reed.flip = _rng.randf() < 0.5
		section.props.append(reed)
	print("stream in %s at x = %.1f" % [section.id, best_x])
