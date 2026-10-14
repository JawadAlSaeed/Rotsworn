extends GutTest
## WalkFacing (DESIGN.md 5.5, card #59): the zone walker faces along the dominant axis of its walk,
## keeps its view on a diagonal so it never flickers, and its walk cycle follows the distance
## actually walked (no steps on the spot, one step per stride, feet down on cells 0 and n/2).

const F := WalkFacing.Facing
const MARGIN: float = 0.2


func test_dominant_axis_picks_the_view() -> void:
	assert_eq(WalkFacing.pick(Vector2(1.0, 0.0), F.BACK, MARGIN), F.SIDE_R, "right")
	assert_eq(WalkFacing.pick(Vector2(-1.0, 0.0), F.BACK, MARGIN), F.SIDE_L, "left")
	assert_eq(WalkFacing.pick(Vector2(0.0, 1.0), F.SIDE_R, MARGIN), F.FRONT, "toward the camera")
	assert_eq(WalkFacing.pick(Vector2(0.0, -1.0), F.SIDE_R, MARGIN), F.BACK, "screen up is the back")
	assert_eq(WalkFacing.pick(Vector2(3.0, -1.0), F.FRONT, MARGIN), F.SIDE_R, "mostly right")
	assert_eq(WalkFacing.pick(Vector2(-0.4, 2.0), F.SIDE_L, MARGIN), F.FRONT, "mostly down")
	assert_eq(WalkFacing.pick(Vector2(0.5, 0.0), F.BACK, MARGIN), F.SIDE_R, "length does not matter")


func test_a_diagonal_tie_keeps_the_facing() -> void:
	var diag := Vector2(1.0, -1.0)
	assert_eq(WalkFacing.pick(diag, F.SIDE_R, MARGIN), F.SIDE_R, "already facing right: stays")
	assert_eq(WalkFacing.pick(diag, F.BACK, MARGIN), F.BACK, "already facing back: stays")
	assert_eq(WalkFacing.pick(diag, F.SIDE_L, MARGIN), F.SIDE_R,
			"a view the diagonal is not between turns to the diagonal's side")
	assert_eq(WalkFacing.pick(Vector2(-1.0, 1.0), F.FRONT, MARGIN), F.FRONT)
	# Inside the margin (normalised axes about 0.62 / 0.78) and outside it (0.5 / 0.87).
	assert_eq(WalkFacing.pick(Vector2(0.62, 0.78), F.SIDE_R, MARGIN), F.SIDE_R, "inside the margin")
	assert_eq(WalkFacing.pick(Vector2(0.5, 0.866), F.SIDE_R, MARGIN), F.FRONT, "outside the margin")
	assert_eq(WalkFacing.pick(Vector2(1.0, -1.0), F.SIDE_R, 0.0), F.SIDE_R, "an exact diagonal with no margin")


func test_no_direction_keeps_the_facing() -> void:
	for f: int in [F.SIDE_R, F.SIDE_L, F.FRONT, F.BACK]:
		assert_eq(WalkFacing.pick(Vector2.ZERO, f as WalkFacing.Facing, MARGIN), f)


func test_only_side_views_are_side() -> void:
	assert_true(WalkFacing.is_side(F.SIDE_R))
	assert_true(WalkFacing.is_side(F.SIDE_L))
	assert_false(WalkFacing.is_side(F.FRONT))
	assert_false(WalkFacing.is_side(F.BACK))
	assert_eq(WalkFacing.SUFFIXES.size(), F.size(), "a clip suffix for every view")


func test_no_steps_without_moving() -> void:
	assert_eq(WalkFacing.advance(0.3, 0.0, 1.0), 0.3, "pushing into a wall: feet stay put")
	assert_eq(WalkFacing.advance(0.3, -0.5, 1.0), 0.3, "never backwards")
	assert_eq(WalkFacing.advance(0.3, 0.5, 0.0), 0.3, "stride 0 leaves it to the old timer")


func test_one_step_per_stride() -> void:
	assert_almost_eq(WalkFacing.advance(0.0, 1.0, 1.0), 1.0, 0.0001)
	assert_almost_eq(WalkFacing.advance(0.0, 0.9, 0.9), 1.0, 0.0001, "the roamers' stride")
	var phase := 0.0
	var steps := 0
	# 0.25 is exact in binary, so the sum lands on 5.0 itself.
	for i: int in 20:
		var before := floori(phase)
		phase = WalkFacing.advance(phase, 0.25, 1.0)
		if floori(phase) > before:
			steps += 1
	assert_eq(steps, 5, "5 world units at stride 1: five footsteps")


func test_cycle_index_puts_a_foot_down_every_step() -> void:
	assert_eq(WalkFacing.cycle_index(8, 0.0), 0, "first contact")
	assert_eq(WalkFacing.cycle_index(8, 0.49), 1)
	assert_eq(WalkFacing.cycle_index(8, 1.0), 4, "second contact after one step")
	assert_eq(WalkFacing.cycle_index(8, 1.99), 7)
	assert_eq(WalkFacing.cycle_index(8, 2.0), 0, "two steps make one cycle")
	assert_eq(WalkFacing.cycle_index(4, 1.0), 2, "a four-cell walk too")
	assert_eq(WalkFacing.cycle_index(1, 1.3), 0)
	assert_eq(WalkFacing.cycle_index(0, 1.3), 0)
