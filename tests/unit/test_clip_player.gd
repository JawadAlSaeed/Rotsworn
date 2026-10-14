extends GutTest
## ClipPlayer (DESIGN.md 5.5): the pure base-plus-override state behind FighterView. A timed
## override shows over the base and expires back to it; priorities decide which override wins;
## delays, holds and cycles; a base loop indexed from the clock never restarts when set again,
## and a delayed loop shows the previous base until it starts. Times are plain numbers (ms).

const REACT := ClipPlayer.PRIO_REACT
const BIG := ClipPlayer.PRIO_BIG
const FINAL := ClipPlayer.PRIO_FINAL


func _cells(list: Array[int]) -> PackedInt32Array:
	return PackedInt32Array(list)


func test_base_cell_shows_when_nothing_plays() -> void:
	var p := ClipPlayer.new()
	assert_eq(p.cell_at(0.0), 0, "starts on cell 0")
	p.set_base_cell(5)
	assert_eq(p.cell_at(1000.0), 5)
	assert_false(p.busy(1000.0), "no override")


func test_override_beats_base_and_expires_back_to_it() -> void:
	var p := ClipPlayer.new()
	p.set_base_cell(1)
	assert_true(p.play(_cells([10, 11, 12, 13]), 1000.0, 400.0, REACT))
	assert_eq(p.cell_at(1000.0), 10, "first cell at once")
	assert_eq(p.cell_at(1100.0), 11, "spread evenly over the length")
	assert_eq(p.cell_at(1399.0), 13)
	assert_true(p.busy(1399.0))
	assert_eq(p.cell_at(1400.0), 1, "expired: back to the base")
	assert_false(p.busy(1400.0))
	p.set_base_cell(2)
	assert_eq(p.cell_at(1200.0), 12, "a new base does not show through a playing override")
	assert_eq(p.cell_at(1500.0), 2)


func test_equal_priority_replaces() -> void:
	var p := ClipPlayer.new()
	p.play(_cells([10]), 0.0, 500.0, REACT)
	assert_true(p.play(_cells([20]), 100.0, 500.0, REACT), "equal priority is accepted")
	assert_eq(p.cell_at(150.0), 20)
	assert_eq(p.cell_at(550.0), 20, "and runs its own length")


func test_lower_priority_is_refused_while_a_higher_one_plays() -> void:
	var p := ClipPlayer.new()
	p.play(_cells([30]), 0.0, 500.0, BIG)
	assert_false(p.play(_cells([10]), 100.0, 500.0, REACT), "refused")
	assert_eq(p.cell_at(200.0), 30)
	assert_true(p.play(_cells([10]), 600.0, 500.0, REACT), "accepted once the higher one is over")
	assert_eq(p.cell_at(650.0), 10)
	assert_true(p.play(_cells([40]), 700.0, 500.0, FINAL), "a higher priority replaces a lower one")
	assert_eq(p.cell_at(750.0), 40)


func test_cancel_below() -> void:
	var p := ClipPlayer.new()
	p.set_base_cell(1)
	p.play(_cells([30]), 0.0, 500.0, BIG)
	p.cancel_below(BIG)
	assert_eq(p.cell_at(100.0), 30, "a BIG override survives cancel_below(BIG)")
	p.cancel_below(FINAL)
	assert_eq(p.cell_at(100.0), 1, "cancel_below(FINAL) drops it")
	p.play(_cells([10]), 0.0, 500.0, REACT, 200.0)
	p.cancel_below(BIG)
	assert_false(p.busy(0.0), "a pending override is cancelled too")
	assert_eq(p.cell_at(300.0), 1)
	p.play(_cells([40]), 0.0, 500.0, FINAL)
	p.clear()
	assert_eq(p.cell_at(100.0), 1, "clear drops any override")


func test_delay_keeps_it_inactive_until_it_starts() -> void:
	var p := ClipPlayer.new()
	p.set_base_cell(1)
	assert_true(p.play(_cells([10, 11]), 1000.0, 200.0, REACT, 300.0))
	assert_eq(p.cell_at(1000.0), 1, "the base shows during the delay")
	assert_eq(p.cell_at(1299.0), 1)
	assert_eq(p.cell_at(1300.0), 10, "starts after the delay")
	assert_eq(p.cell_at(1400.0), 11)
	assert_eq(p.cell_at(1500.0), 1, "and runs its full length after the delay")
	assert_true(p.busy(1000.0), "a pending override counts as busy")


func test_a_pending_higher_override_refuses_a_lower_one() -> void:
	var p := ClipPlayer.new()
	p.play(_cells([40]), 0.0, 600.0, FINAL, 300.0)
	assert_false(p.play(_cells([10]), 100.0, 300.0, REACT), "the victory waiting to start is kept")
	assert_eq(p.cell_at(400.0), 40)


func test_hold_keeps_the_last_cell() -> void:
	var p := ClipPlayer.new()
	p.set_base_cell(1)
	p.play(_cells([50, 51, 52]), 0.0, 300.0, FINAL, 0.0, true)
	assert_eq(p.cell_at(150.0), 51)
	assert_eq(p.cell_at(5000.0), 52, "held long after its length")
	assert_true(p.busy(5000.0, FINAL))
	assert_false(p.play(_cells([10]), 6000.0, 300.0, BIG), "a held FINAL override keeps refusing")
	p.clear()
	assert_eq(p.cell_at(6000.0), 1)


func test_cycle_loops_the_cells_for_the_whole_length() -> void:
	var p := ClipPlayer.new()
	p.set_base_cell(1)
	p.play(_cells([60, 61]), 0.0, 1000.0, BIG, 0.0, false, 200.0)
	assert_eq(p.cell_at(0.0), 60)
	assert_eq(p.cell_at(100.0), 61)
	assert_eq(p.cell_at(200.0), 60, "cycles every 200 ms")
	assert_eq(p.cell_at(950.0), 61)
	assert_eq(p.cell_at(1000.0), 1, "then ends like any override")


func test_base_loop_is_indexed_from_the_clock() -> void:
	var p := ClipPlayer.new()
	var cells := _cells([0, 8, 9, 8])
	p.set_base_loop(cells, 400.0, 0.0)
	assert_eq(p.cell_at(0.0), 0)
	assert_eq(p.cell_at(100.0), 8)
	assert_eq(p.cell_at(250.0), 9)
	assert_eq(p.cell_at(450.0), 0, "wraps")
	# Set again every frame (as set_pose(IDLE) is): it never restarts.
	var shown: Array[int] = []
	for t: int in range(1000, 1400, 50):
		p.set_base_loop(cells, 400.0, 0.0)
		shown.append(p.cell_at(float(t)))
	# 1000 ms is half way through the third cycle (cell 2).
	var expected: Array[int] = [9, 9, 8, 8, 0, 0, 8, 8]
	assert_eq(shown, expected, "the same loop set every frame keeps running")


func test_base_loop_phase_shifts_it() -> void:
	var p := ClipPlayer.new()
	p.set_base_loop(_cells([0, 8, 9, 8]), 400.0, 100.0)
	assert_eq(p.cell_at(0.0), 8, "100 ms ahead")


func test_a_delayed_base_loop_shows_the_previous_base_until_it_starts() -> void:
	var p := ClipPlayer.new()
	p.set_base_cell(3)
	p.set_base_loop(_cells([70, 71]), 200.0, 0.0, 1000.0)
	assert_eq(p.cell_at(500.0), 3, "the previous base until the loop starts")
	assert_eq(p.cell_at(999.0), 3)
	assert_eq(p.cell_at(1000.0), 70, "starts on its first cell")
	assert_eq(p.cell_at(1100.0), 71)
	assert_eq(p.cell_at(1200.0), 70)
	p.set_base_cell(4)
	assert_eq(p.cell_at(500.0), 4, "a new base replaces the pending loop")
	assert_eq(p.cell_at(1100.0), 4)


func test_a_delayed_loop_behind_a_delayed_override() -> void:
	# Victory: the pose plays after a delay, then the hold loop takes over as the base.
	var p := ClipPlayer.new()
	p.set_base_cell(0)
	p.play(_cells([80, 81]), 0.0, 400.0, FINAL, 300.0)
	p.set_base_loop(_cells([90, 91]), 200.0, 0.0, 700.0)
	assert_eq(p.cell_at(100.0), 0, "idle before the victory")
	assert_eq(p.cell_at(300.0), 80, "the victory pose")
	assert_eq(p.cell_at(600.0), 81)
	assert_eq(p.cell_at(700.0), 90, "then the hold loop")
	assert_eq(p.cell_at(800.0), 91)


func test_busy_respects_the_priority() -> void:
	var p := ClipPlayer.new()
	p.play(_cells([10]), 0.0, 500.0, BIG)
	assert_true(p.busy(100.0))
	assert_true(p.busy(100.0, BIG))
	assert_false(p.busy(100.0, FINAL))
	assert_false(p.busy(600.0), "over")


func test_empty_cells_are_refused() -> void:
	var p := ClipPlayer.new()
	p.set_base_cell(2)
	assert_false(p.play(PackedInt32Array(), 0.0, 500.0, REACT))
	assert_eq(p.cell_at(100.0), 2)
	p.set_base_loop(PackedInt32Array(), 400.0, 0.0)
	assert_eq(p.cell_at(100.0), 2, "an empty loop keeps the base")
