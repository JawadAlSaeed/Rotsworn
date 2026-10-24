extends SceneTree
## Dev tool (DESIGN.md 5.6, phase 18 step 4, card #236): gives every fight arena its own 3D
## world pieces: the back closed by tall cliff walls in the arena's ground, then its own ruins,
## huts and rocks. Everything it adds is named DRESSED (resource_name), and a second run replaces
## the arena's blocks. (Until phase 26 it was tools/dress_zones.gd and also dressed the walkable
## zones' sections, DESIGN.md 8.22.)
## Run: Godot --headless --path . -s tools/dress_arenas.gd [-- --dry-run]

const PIECES_DIR := "res://data/pieces"
const DRESSED := "dressed"

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
	# The Leech Queen's lair (phase 26, card #323): a drowned bog court, sunken huts, a broken
	# arch half under the black water, bones on the bank, two swamp lanterns.
	"leech_lair": {"cliff": "cliff_wall_bog", "pieces": [
		["stilt_hut", -8.8, -8.0, 12.0, 1.0], ["ledge_rock_tall_bog", 9.2, -8.4, -6.0, 1.0],
		["arch_broken", 3.8, -9.2, 4.0, 1.0], ["log", 4.6, -6.0, 15.0, 1.0],
		["rock_mossy", -9.8, -4.8, 20.0, 1.1], ["bones", 1.0, -5.2, 25.0, 1.0],
		["stump_rotten", -3.4, -8.3, 0.0, 0.55], ["swamp_lantern", 6.3, -4.8, 0.0, 1.0],
		["swamp_lantern", -7.4, -5.4, 0.0, 1.0]]},
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


func _init() -> void:
	_dry = OS.get_cmdline_user_args().has("--dry-run")
	_dress_arenas()
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
				push_error("dress_arenas: could not save %s (%d)" % [path, err])


## One arena piece as a block at its own size times `scale` (an arena is not walked, so its
## blocks only need to stand there).
func _arena_block(piece_id: String, x: float, z: float, turn: float, scale: float) -> ZoneBlockData:
	var piece := _piece(piece_id)
	var mesh := AssetLoader.mesh(piece.model_path) if piece != null else null
	if mesh == null:
		push_error("dress_arenas: no piece %s" % piece_id)
		return null
	var block := ZoneBlockData.new()
	block.resource_name = DRESSED
	block.position = Vector3(x, 0.0, z)
	block.size = mesh.get_aabb().size * scale
	block.rotation_y_degrees = turn
	block.piece = piece
	return block


func _piece(id: String) -> WorldPieceData:
	return load(PIECES_DIR.path_join(id + ".tres")) as WorldPieceData
