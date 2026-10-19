extends GutTest
## Ground pieces never share a height with a piece they overlap (card #269): GroundStack puts
## each one a step over every earlier piece it touches, higher layers over lower ones, and every
## shipped zone, on many visits, keeps its whole stack under the props' shadow blobs.

const SEEDS: int = 12


func _piece(x: float, z: float, size: Vector2, layer: int = 0, turn: float = 0.0) -> ZoneGroundData:
	var g := ZoneGroundData.new()
	g.position = Vector3(x, 0.0, z)
	g.size = size
	g.layer = layer
	g.rotation_y_degrees = turn
	return g


## Pairs of overlapping pieces lying on the same step ("i/j"), empty when there are none.
func _clashes(grounds: Array[ZoneGroundData], levels: PackedInt32Array) -> Array[String]:
	var out: Array[String] = []
	for i: int in grounds.size():
		for j: int in range(i + 1, grounds.size()):
			if levels[i] == levels[j] and GroundStack.footprint(grounds[i]).intersects(GroundStack.footprint(grounds[j]), true):
				out.append("%d/%d" % [i, j])
	return out


func test_pieces_apart_share_the_bottom_step() -> void:
	var grounds: Array[ZoneGroundData] = [_piece(0, 0, Vector2(2, 2)), _piece(10, 0, Vector2(2, 2))]
	assert_eq(GroundStack.levels(grounds), PackedInt32Array([0, 0]))


func test_overlapping_pieces_on_one_layer_never_share_a_step() -> void:
	# Two pools and a road across both, all on layer 0: the road went down at the same height as
	# the water and flickered through it.
	var grounds: Array[ZoneGroundData] = [_piece(0, 0, Vector2(6, 6)), _piece(5, 0, Vector2(6, 6)),
			_piece(2.5, 0, Vector2(12, 2))]
	var levels := GroundStack.levels(grounds)
	assert_eq(levels, PackedInt32Array([0, 1, 2]), "each lies over the earlier ones it touches")
	assert_eq(_clashes(grounds, levels).size(), 0)


func test_a_higher_layer_always_lies_over_a_lower_one() -> void:
	# The road comes first in the list but is on a higher layer than the clearing under it.
	var grounds: Array[ZoneGroundData] = [_piece(0, 0, Vector2(8, 2), 2), _piece(0, 0, Vector2(4, 4), 0),
			_piece(0, 0, Vector2(3, 3), 1)]
	var levels := GroundStack.levels(grounds)
	assert_gt(levels[0], levels[2], "the layer 2 road over the layer 1 patch")
	assert_gt(levels[2], levels[1], "the layer 1 patch over the layer 0 clearing")


func test_a_turned_piece_covers_its_turned_box() -> void:
	# A long thin road turned 90 degrees reaches along z, not x.
	var road := _piece(0, 0, Vector2(10, 1), 0, 90.0)
	var box := GroundStack.footprint(road)
	assert_almost_eq(box.size.x, 1.0, 0.001)
	assert_almost_eq(box.size.y, 10.0, 0.001)
	var grounds: Array[ZoneGroundData] = [road, _piece(0, 4, Vector2(1, 1)), _piece(4, 0, Vector2(1, 1))]
	assert_eq(GroundStack.levels(grounds), PackedInt32Array([0, 1, 0]))


func test_lift_follows_the_look() -> void:
	var look := StageLook.new()
	look.ground_lift = 0.01
	look.ground_step = 0.005
	assert_almost_eq(GroundStack.lift(look, 0), 0.01, 0.00001)
	assert_almost_eq(GroundStack.lift(look, 3), 0.025, 0.00001)


func test_built_pieces_lie_on_their_steps() -> void:
	var look := StageLook.new()
	var grounds: Array[ZoneGroundData] = [_piece(0, 0, Vector2(6, 6)), _piece(2, 0, Vector2(6, 6))]
	var parent := Node3D.new()
	StageBuilder.add_contents(parent, [], [], [], grounds, look)
	assert_eq(parent.get_child_count(), 2)
	var a := (parent.get_child(0) as Node3D).position.y
	var b := (parent.get_child(1) as Node3D).position.y
	assert_almost_eq(a, look.ground_lift, 0.00001)
	assert_almost_eq(b - a, look.ground_step, 0.00001, "the second lies one step over the first")
	parent.free()


func test_every_shipped_zone_stacks_cleanly_under_the_shadows() -> void:
	var visuals := load("res://data/presentation/combat_visuals.tres") as CombatVisuals
	var checked := 0
	for zone: ZoneData in FightSelect.load_zones():
		var look := zone.look if zone.look != null else StageLook.new()
		for seed_value: int in range(1, SEEDS + 1):
			var built := ZoneAssembler.assemble(zone, seed_value)
			var levels := GroundStack.levels(built.grounds)
			var clashes := _clashes(built.grounds, levels)
			assert_eq(clashes.size(), 0, "%s seed %d: overlapping pieces on one step %s" % [zone.id, seed_value, clashes])
			var top := GroundStack.lift(look, GroundStack.top_level(built.grounds))
			assert_lt(top, look.prop_shadow_lift,
					"%s seed %d: the top ground piece (%.3f) stays under the shadow blobs" % [zone.id, seed_value, top])
			assert_lt(top, visuals.shadow_lift,
					"%s seed %d: the top ground piece (%.3f) stays under the walkers' shadows" % [zone.id, seed_value, top])
			checked += 1
			if not ZoneAssembler.is_sectioned(zone):
				break
	assert_gt(checked, 3, "found the zones")
