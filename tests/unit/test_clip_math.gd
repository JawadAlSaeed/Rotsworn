extends GutTest
## ClipMath (DESIGN.md 5.5): the pure cell-index maths behind every sprite clip. Progress maps
## evenly onto the cells and clamps at both ends, a one-shot holds its last cell, a loop wraps
## (also for negative times), and each fighter id gets its own fixed loop phase.


func test_stretch_shares_progress_evenly_and_clamps() -> void:
	assert_eq(ClipMath.stretch(4, -0.5), 0, "before the start: first cell")
	assert_eq(ClipMath.stretch(4, 0.0), 0, "u 0: first cell")
	assert_eq(ClipMath.stretch(4, 0.24), 0)
	assert_eq(ClipMath.stretch(4, 0.25), 1, "each cell gets a quarter")
	assert_eq(ClipMath.stretch(4, 0.5), 2)
	assert_eq(ClipMath.stretch(4, 0.999), 3)
	assert_eq(ClipMath.stretch(4, 1.0), 3, "u 1: last cell")
	assert_eq(ClipMath.stretch(4, 2.0), 3, "after the end: last cell")
	assert_eq(ClipMath.stretch(1, 0.7), 0, "one cell")
	assert_eq(ClipMath.stretch(0, 0.7), 0, "an empty clip never indexes past 0")


func test_once_spreads_over_the_length_and_holds_the_last_cell() -> void:
	assert_eq(ClipMath.once(3, -10.0, 300.0), 0, "not started yet")
	assert_eq(ClipMath.once(3, 0.0, 300.0), 0)
	assert_eq(ClipMath.once(3, 99.9, 300.0), 0)
	assert_eq(ClipMath.once(3, 100.0, 300.0), 1, "exact on the cell boundary")
	assert_eq(ClipMath.once(3, 200.0, 300.0), 2)
	assert_eq(ClipMath.once(3, 299.0, 300.0), 2)
	assert_eq(ClipMath.once(3, 1000.0, 300.0), 2, "holds the last cell")
	assert_eq(ClipMath.once(3, 5.0, 0.0), 2, "no length: straight to the last cell")
	assert_eq(ClipMath.once(1, 150.0, 300.0), 0)


func test_loop_wraps() -> void:
	assert_eq(ClipMath.loop(4, 0.0, 400.0), 0)
	assert_eq(ClipMath.loop(4, 100.0, 400.0), 1)
	assert_eq(ClipMath.loop(4, 399.0, 400.0), 3)
	assert_eq(ClipMath.loop(4, 400.0, 400.0), 0, "a new cycle starts")
	assert_eq(ClipMath.loop(4, 1250.0, 400.0), 0, "three cycles and 50 ms in")
	assert_eq(ClipMath.loop(4, -1.0, 400.0), 3, "negative times wrap too")
	assert_eq(ClipMath.loop(4, 0.0, 400.0, 100.0), 1, "the phase shifts the cycle")
	assert_eq(ClipMath.loop(4, 350.0, 400.0, 100.0), 0, "and wraps with it")
	assert_eq(ClipMath.loop(4, 123.0, 0.0), 0, "no period: first cell")
	assert_eq(ClipMath.loop(1, 123.0, 400.0), 0, "one cell")


func test_loop_shows_every_cell_once_per_period() -> void:
	var seen: Array[int] = []
	for t: int in range(0, 800, 10):
		var cell := ClipMath.loop(4, float(t), 800.0, 0.0)
		if seen.is_empty() or seen[seen.size() - 1] != cell:
			seen.append(cell)
	var expected: Array[int] = [0, 1, 2, 3]
	assert_eq(seen, expected, "in order, each once")


func test_phase_differs_per_fighter_and_is_fixed() -> void:
	var period := 1600.0
	assert_eq(ClipMath.phase_for(0, period), 0.0, "fighter 0 starts at the top of the cycle")
	assert_eq(ClipMath.phase_for(5, period), ClipMath.phase_for(5, period), "the same id, the same phase")
	var phases: Array[float] = []
	for id: int in range(-5, 7):
		var phase := ClipMath.phase_for(id, period)
		assert_true(phase >= 0.0 and phase < period, "id %d: phase %f inside the period" % [id, phase])
		for other: float in phases:
			assert_gt(absf(phase - other), 1.0, "id %d does not breathe in step with another fighter" % id)
		phases.append(phase)
