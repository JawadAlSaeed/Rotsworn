extends GutTest
## RelicIcon (DESIGN.md 8.17, card #271): one frame shape per category that always fills (no
## repeated points, triangulates at every size) and says its category by shape alone, sign colours
## that are no hero's, the level pips, the slot states, the hero tag and the cursor glow, the static
## painters for drawn grids, and the old setup() for every shipped Relic.

const GEAR_DIR := "res://data/gear/"
const HERO_DIR := "res://data/characters/"
const RADII: Array[float] = [6.0, 10.5, 21.0, 50.0]
const SHAPES: Array[int] = [GearData.Category.OFFENSIVE, GearData.Category.DEFENSIVE, GearData.Category.SUPPORT,
	RelicIcon.NEUTRAL]


func _shipped() -> Array[GearData]:
	var items: Array[GearData] = []
	for file: String in DirAccess.get_files_at(GEAR_DIR):
		if not file.ends_with(".tres"):
			continue
		var item := load(GEAR_DIR + file) as GearData
		assert_not_null(item, "%s loads as a Relic" % file)
		if item != null:
			items.append(item)
	return items


## A counter the canvas's draw signal bumps (a Dictionary, so the lambda shares it).
func _count_draws(canvas: CanvasItem) -> Dictionary:
	var drawn := {"n": 0}
	canvas.draw.connect(func() -> void: drawn["n"] += 1)
	return drawn


## Adds `icon` to the tree at its own size and returns its draw counter.
func _show(icon: Control, px: float) -> Dictionary:
	var drawn := _count_draws(icon)
	add_child_autofree(icon)
	icon.size = Vector2(px, px)
	icon.queue_redraw()
	return drawn


func _differ(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return true
	for i: int in a.size():
		if a[i].distance_to(b[i]) > 0.5:
			return true
	return false


func test_frames_fill_at_every_size() -> void:
	var c := Vector2(40.0, 40.0)
	for radius: float in RADII:
		for shape: int in SHAPES:
			var points := RelicIcon.frame_points(shape, c, radius)
			var label := "shape %d at radius %.1f" % [shape, radius]
			assert_gte(points.size(), 3, label + " has a frame")
			var repeated := 0
			var outside := 0
			for i: int in points.size():
				if points[i].distance_to(points[(i + 1) % points.size()]) < 0.0001:
					repeated += 1
				var d := points[i] - c
				if absf(d.x) > radius + 0.001 or absf(d.y) > radius + 0.001:
					outside += 1
			assert_eq(repeated, 0, label + ": no repeated points (draw_colored_polygon fails on them)")
			assert_eq(outside, 0, label + ": inside its square")
			assert_gt(Geometry2D.triangulate_polygon(points).size(), 0, label + " triangulates")
			assert_eq(Geometry2D.is_polygon_clockwise(points),
					Geometry2D.is_polygon_clockwise(RelicIcon.frame_points(RelicIcon.NEUTRAL, c, radius)),
					label + ": wound the same way as every frame")


func test_the_three_frames_differ() -> void:
	var c := Vector2.ZERO
	for radius: float in RADII:
		for i: int in SHAPES.size():
			for j: int in range(i + 1, SHAPES.size()):
				assert_true(_differ(RelicIcon.frame_points(SHAPES[i], c, radius), RelicIcon.frame_points(SHAPES[j], c, radius)),
						"shapes %d and %d differ at radius %.1f" % [SHAPES[i], SHAPES[j], radius])


## The shape alone says the category: a pointed top and a notch (offensive), a flat top and a point
## below (defensive), a circle (support).
func test_each_frame_says_its_category() -> void:
	var r := 20.0
	var spear := RelicIcon.frame_points(GearData.Category.OFFENSIVE, Vector2.ZERO, r)
	var shield := RelicIcon.frame_points(GearData.Category.DEFENSIVE, Vector2.ZERO, r)
	var seal := RelicIcon.frame_points(GearData.Category.SUPPORT, Vector2.ZERO, r)
	assert_eq(_count_at(spear, _min_y(spear)), 1, "the spearhead has one tip on top")
	var notched := false
	for p: Vector2 in spear:
		if absf(p.x) < 0.01 and p.y > 0.0 and p.y < _max_y(spear) - r * 0.2:
			notched = true
	assert_true(notched, "the spearhead's base has a notch cut up into it")
	assert_eq(_count_at(shield, _min_y(shield)), 2, "the shield's top is flat")
	assert_eq(_count_at(shield, _max_y(shield)), 1, "the shield comes down to a point")
	var round_shape := true
	for p: Vector2 in seal:
		if absf(p.length() - seal[0].length()) > 0.01:
			round_shape = false
	assert_true(round_shape, "the seal is round")


func _min_y(points: PackedVector2Array) -> float:
	var y := INF
	for p: Vector2 in points:
		y = minf(y, p.y)
	return y


func _max_y(points: PackedVector2Array) -> float:
	var y := -INF
	for p: Vector2 in points:
		y = maxf(y, p.y)
	return y


func _count_at(points: PackedVector2Array, y: float) -> int:
	var n := 0
	for p: Vector2 in points:
		if absf(p.y - y) < 0.01:
			n += 1
	return n


func test_sign_colours_are_not_hero_colours() -> void:
	var heroes := 0
	for file: String in DirAccess.get_files_at(HERO_DIR):
		if not file.ends_with(".tres"):
			continue
		var hero := load(HERO_DIR + file) as CharacterData
		if hero == null:
			continue
		heroes += 1
		for color: Color in RelicIcon.CATEGORY_COLORS:
			var d := Vector3(color.r - hero.color.r, color.g - hero.color.g, color.b - hero.color.b).length()
			assert_gt(d, 0.25, "sign colour %s is far from %s's colour" % [color.to_html(false), file])
	assert_gt(heroes, 0, "the heroes load")
	assert_eq(RelicIcon.CATEGORY_COLORS.size(), 3, "one colour per category")
	for i: int in 3:
		for j: int in range(i + 1, 3):
			assert_ne(RelicIcon.CATEGORY_COLORS[i], RelicIcon.CATEGORY_COLORS[j], "categories %d and %d differ" % [i, j])


func test_level_pips() -> void:
	var tuning := load("res://data/tuning/tuning.tres") as Tuning
	var top := tuning.relic_max_level
	var item := _shipped()[0]
	var icon := RelicIcon.make(item, 46.0)
	assert_eq(icon.pip_count(), 0, "no level given: no pips")
	assert_eq(icon.pip_slots(), 0)
	icon.setup(item, 46.0, true, 3, top)
	assert_eq(icon.pip_count(), mini(3, top), "level 3: three gold pips")
	assert_eq(icon.pip_slots(), top, "out of the max level")
	icon.set_level(top + 4, top)
	assert_eq(icon.pip_count(), top, "never more than the max level")
	icon.set_level(2)
	assert_eq(icon.pip_count(), 2, "no max given: just the filled pips")
	assert_eq(icon.pip_slots(), 2)
	icon.set_level(0, top)
	assert_eq(icon.pip_slots(), 0, "level 0: no pips")
	icon.setup(item, 46.0, false, 3, top)
	assert_eq(icon.pip_count(), 0, "an unknown Relic shows no level")
	assert_eq(RelicIcon.pip_layout(4, 5), Vector2i(4, 5))
	assert_eq(RelicIcon.pip_layout(-1, 5), Vector2i.ZERO)
	icon.free()


func test_level_pips_draw() -> void:
	var tuning := load("res://data/tuning/tuning.tres") as Tuning
	var items := _shipped()
	var counters: Array[Dictionary] = []
	for px: float in [26.0, 46.0, 104.0]:
		var icon := RelicIcon.make(items[0], px, true, 2, tuning.relic_max_level)
		counters.append(_show(icon, px))
		assert_eq(icon.pip_count(), 2)
	await wait_process_frames(2)
	for drawn: Dictionary in counters:
		assert_gt(drawn["n"], 0, "a Relic with pips draws")


func test_slot_states_tag_and_cursor_draw() -> void:
	var counters: Array[Dictionary] = []
	var icons: Array[RelicIcon] = []
	for state: int in [RelicIcon.SlotState.EMPTY, RelicIcon.SlotState.LOCKED]:
		for px: float in [26.0, 60.0]:
			var icon := RelicIcon.make_slot(state, px)
			icon.set_tag("alder", Color(0.36, 0.5, 0.75))
			icon.chosen = px > 30.0
			counters.append(_show(icon, px))
			icons.append(icon)
			assert_eq(icon.slot_state(), state)
			assert_eq(icon.shape(), RelicIcon.NEUTRAL, "a slot has the neutral frame")
			assert_eq(icon.pip_count(), 0, "a slot has no level")
	assert_eq(icons[0].tag(), "A", "the tag keeps the first letter, upper case")
	await wait_process_frames(2)
	for drawn: Dictionary in counters:
		assert_gt(drawn["n"], 0, "the slot drew")
	for icon: RelicIcon in icons:
		assert_gte(icon.size.x, icon.custom_minimum_size.x - 0.01, "the icon is as big as asked")
	icons[0].set_tag("", Color.WHITE)
	assert_eq(icons[0].tag(), "", "an empty letter removes the tag")
	icons[0].setup(_shipped()[0], 26.0)
	assert_eq(icons[0].slot_state(), RelicIcon.SlotState.NONE, "setup() turns a slot back into a Relic")


func test_static_painters_draw_on_another_canvas() -> void:
	var items := _shipped()
	var canvas := Control.new()
	var calls := {"n": 0}
	canvas.draw.connect(func() -> void:
		RelicIcon.draw_relic(canvas, Rect2(0.0, 0.0, 46.0, 46.0), items[0], true, 3, 5, true)
		RelicIcon.draw_relic(canvas, Rect2(50.0, 0.0, 26.0, 40.0), items[1], false)
		RelicIcon.draw_slot(canvas, Rect2(0.0, 50.0, 30.0, 30.0), RelicIcon.SlotState.EMPTY, true)
		RelicIcon.draw_slot(canvas, Rect2(40.0, 50.0, 30.0, 30.0), RelicIcon.SlotState.LOCKED)
		RelicIcon.draw_tag(canvas, Rect2(0.0, 0.0, 46.0, 46.0), "Cass", Color(0.85, 0.72, 0.29))
		RelicIcon.draw_tag(canvas, Rect2(0.0, 0.0, 46.0, 46.0), "", Color.WHITE)
		calls["n"] += 1)
	add_child_autofree(canvas)
	canvas.size = Vector2(120.0, 120.0)
	canvas.queue_redraw()
	await wait_process_frames(2)
	assert_gt(calls["n"], 0, "the painters ran inside the canvas's draw")


## The old call, setup(item, px[, known]), as the Relics page, the Echoes page and the main menu's
## Relic bag make it, for every shipped Relic: known, unknown, chosen, tagged, rot-touched.
func test_old_setup_for_every_shipped_relic() -> void:
	var items := _shipped()
	assert_gt(items.size(), 0, "the shipped Relics load")
	var seen := {}
	var rot := 0
	var counters: Array[Dictionary] = []
	for item: GearData in items:
		seen[item.category()] = true
		if item.rot_touched:
			rot += 1
		var icon := RelicIcon.new()
		icon.setup(item, 46.0)
		assert_eq(icon.shape(), item.category(), "%s: its category's frame" % item.id)
		counters.append(_show(icon, 46.0))
		var unknown := RelicIcon.new()
		unknown.setup(item, 30.0, false)
		assert_eq(unknown.shape(), RelicIcon.NEUTRAL, "%s unknown: the neutral frame" % item.id)
		counters.append(_show(unknown, 30.0))
		var small := RelicIcon.make(item, 26.0, true, 1, 5)
		small.chosen = true
		small.set_tag("B", Color(0.76, 0.27, 0.24))
		counters.append(_show(small, 26.0))
	var empty := RelicIcon.new()
	empty.setup(null, 46.0, false)
	assert_eq(empty.shape(), RelicIcon.NEUTRAL, "no Relic: the neutral frame")
	counters.append(_show(empty, 46.0))
	var nothing := RelicIcon.new()
	nothing.setup(null, 46.0)
	counters.append(_show(nothing, 46.0))
	assert_eq(seen.size(), 3, "the shipped Relics cover all three categories")
	assert_gt(rot, 0, "some shipped Relic is rot-touched (the drip gets drawn)")
	await wait_process_frames(2)
	var silent := 0
	for drawn: Dictionary in counters:
		if drawn["n"] == 0:
			silent += 1
	assert_eq(silent, 0, "every icon drew")
