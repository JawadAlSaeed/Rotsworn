extends GutTest
## RelicIcon (DESIGN.md 8.17, card #271): one frame shape per category that always fills (no
## repeated points, triangulates at every size) and says its category by shape alone, sign colours
## that are no hero's, the level pips, the slot states, the hero tag and the cursor glow, the static
## painters for drawn grids, the old setup() for every shipped Relic, and the Relic pictures' square
## (snapped to whole screen pixels, drawn even at any scale, every shipped picture inside its frame and
## clear of its edge).

const GEAR_DIR := "res://data/gear/"
const HERO_DIR := "res://data/characters/"
const RADII: Array[float] = [6.0, 10.5, 21.0, 50.0]
## Every size the game shows a Relic at (map chips, lists, cards, the bag, the hero rows, the book).
const ICON_SIDES: Array[float] = [26.0, 36.0, 40.0, 44.0, 46.0, 48.0, 52.0, 64.0, 92.0, 96.0, 118.0, 168.0]
## tools/art_kit/kit/relic_frame.py SAFE_INSET: how far inside its frame's edge line (in frame radii) a
## picture's pixel centres stay, before the square is snapped (check.py enforces it on the art).
const SAFE_INSET: float = 0.07
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


## The icon still draws level pips when a caller passes a level (no screen does since Relics lost
## their levels in a run, DESIGN.md 8.24); three is any top level.
func test_level_pips() -> void:
	var top := 3
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
	var items := _shipped()
	var counters: Array[Dictionary] = []
	for px: float in [26.0, 46.0, 104.0]:
		var icon := RelicIcon.make(items[0], px, true, 2, 3)
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


## The old call, setup(item, px[, known]), as the spoils, the end screen and the main menu's Relic
## bag make it, for every shipped Relic: known, unknown, chosen, tagged, rot-touched.
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


## A Relic's picture (phase 27): a square over the frame's inside, its side snapped to a whole number
## of picture pixels when one is near (crisp pixels), left as is when none is, its corner on a pixel.
func test_picture_rect_snaps_to_whole_pixels() -> void:
	var c := Vector2(46.0, 46.0)
	# A 92 px icon: radius 42, a side of 70.56, so a 24 px picture shows at 3x.
	var big := RelicIcon.picture_rect(c, 42.0, 24.0)
	assert_eq(big.size, Vector2(72.0, 72.0), "near 3x: snapped up to 3x")
	assert_eq(big.position, big.position.round(), "the corner on a whole pixel")
	# A 168 px icon: radius 80, a side of 134.4: 5.6x, 6x is too far up, 5x near enough down.
	assert_eq(RelicIcon.picture_rect(c, 80.0, 24.0).size.x, 120.0, "5.6x: snapped down to 5x")
	# A 46 px list icon: radius about 20.5, a side of about 34.4: 1.43x, no whole number near.
	var listed := RelicIcon.picture_rect(c, 20.47, 24.0)
	assert_almost_eq(listed.size.x, 20.47 * RelicIcon.PICTURE_SHARE, 0.001, "1.43x: left as is")
	# A 26 px icon: under 1x, never snapped up to 1x from far below.
	assert_lt(RelicIcon.picture_rect(c, 11.25, 24.0).size.x, 24.0, "under 1x stays under")
	var centre := listed.get_center() - c
	assert_almost_eq(centre.y, RelicIcon.PICTURE_OFFSET.y * 20.47, 0.51, "centred at PICTURE_OFFSET")
	assert_almost_eq(centre.x, 0.0, 0.51, "centred across")


## The snapping counts screen pixels, not the canvas's: at 1280x720 (the 1920x1080 layout shown at
## 2/3) a 92 px icon's 24 px picture is 47 screen pixels, near 2x, so it snaps to 48 screen pixels; the
## corner lands on a whole screen pixel even where the canvas's pixel is not one.
func test_picture_rect_snaps_to_screen_pixels() -> void:
	var c := Vector2(46.0, 46.0)
	var small := Transform2D(0.0, Vector2(2.0, 2.0) / 3.0, 0.0, Vector2(100.3, 50.6))
	var pic := RelicIcon.picture_rect(c, 42.0, 24.0, small)
	var on_screen := Rect2(small * pic.position, pic.size * RelicIcon.screen_zoom(small))
	assert_almost_eq(on_screen.size.x, 48.0, 0.001, "2x in screen pixels")
	assert_almost_eq(on_screen.position.x, roundf(on_screen.position.x), 0.001, "the corner on a screen pixel")
	assert_almost_eq(on_screen.position.y, roundf(on_screen.position.y), 0.001, "the corner on a screen pixel")
	# A 46 px list icon at 1280x720: 1.43x in the canvas, under 1x on screen: not snapped up.
	var listed := RelicIcon.picture_rect(c, 20.47, 24.0, small)
	assert_lt(listed.size.x * RelicIcon.screen_zoom(small), 24.0, "under 1x on screen stays under")
	# Twice as big a screen (3840x2160): the same icon snaps to 6x on screen.
	var big := Transform2D(0.0, Vector2(2.0, 2.0), 0.0, Vector2.ZERO)
	assert_almost_eq(RelicIcon.picture_rect(c, 42.0, 24.0, big).size.x * 2.0, 144.0, 0.001, "6x on a 4K screen")


## A picture is blown up (nearest) to the next whole number of screen pixels, then drawn smooth: the
## same size for every picture pixel at any scale, and exact at a whole number.
func test_picture_prescale() -> void:
	assert_eq(RelicIcon.picture_prescale(0.7), 1, "under 1x: the plain smooth filter")
	assert_eq(RelicIcon.picture_prescale(1.0), 1, "1x: as it is")
	assert_eq(RelicIcon.picture_prescale(1.43), 2, "1.43x: from a 2x copy")
	assert_eq(RelicIcon.picture_prescale(3.0), 3, "a whole number: exactly that")
	assert_eq(RelicIcon.picture_prescale(2.0004), 2, "a hair over a whole number: that number")
	assert_eq(RelicIcon.picture_prescale(40.0), RelicIcon.PICTURE_PRESCALE_MAX, "never blown up past the cap")
	var item := _shipped()[0]
	var texture := load(item.icon_path) as Texture2D
	assert_not_null(texture, "the picture loads")
	var copy := RelicIcon._crisp(texture, 3)
	assert_not_null(copy, "a blown-up copy")
	assert_same(RelicIcon._crisp(texture, 3), copy, "kept, not made again")
	assert_ne(RelicIcon._crisp(texture, 1), copy, "one copy per scale")


## The hero tag and the Relic+ badge stick out past the icon's square, so they cover less of the
## picture, but stay mostly over it (a corner badge, not a mark beside the icon).
func test_tag_and_badge_stick_out_a_little() -> void:
	for side: float in [26.0, 92.0, 118.0]:
		var tag_r := clampf(side * RelicIcon.TAG_SHARE, RelicIcon.TAG_MIN, RelicIcon.TAG_MAX)
		var plus_r := clampf(side * RelicIcon.PLUS_SHARE, RelicIcon.PLUS_MIN, RelicIcon.PLUS_MAX)
		assert_gt(RelicIcon.TAG_OUT * tag_r, 0.0, "the tag sticks out")
		assert_lt(RelicIcon.TAG_OUT, 1.0, "the tag's centre stays inside the square")
		assert_gt(RelicIcon.PLUS_OUT * plus_r, 0.0, "the badge sticks out")
		assert_lt(RelicIcon.PLUS_OUT, 1.0, "the badge's centre stays inside the square")
	# The Relics tab's bag: a 92 px icon in a 116 px cell, so 12 px either side for the tag.
	var r := clampf(92.0 * RelicIcon.TAG_SHARE, RelicIcon.TAG_MIN, RelicIcon.TAG_MAX)
	assert_lt(RelicIcon.TAG_OUT * r, (RelicsTab.BAG_CELL - RelicsTab.BAG_ICON_PX) * 0.5, "the tag stays in its bag cell")


## Every shipped Relic's picture (assets/sprites/relics, drawn by tools/art_kit) is square and keeps
## every pixel inside its own frame at each size the game shows it, as the art kit's check promises
## (its kit/relic_frame.py mirrors frame_points and picture_rect).
func test_shipped_pictures_stay_inside_their_frames() -> void:
	var checked := 0
	for item: GearData in _shipped():
		if item.icon_path.is_empty() or not FileAccess.file_exists(item.icon_path):
			continue
		var image := Image.new()
		assert_eq(image.load_png_from_buffer(FileAccess.get_file_as_bytes(item.icon_path)), OK, item.id + " loads")
		var n := image.get_width()
		assert_eq(image.get_height(), n, item.id + ": a square picture")
		checked += 1
		# The art's own check (check.py): before snapping, every pixel centre at least SAFE_INSET frame
		# radii inside the frame's edge line, so the edge drawn over it covers at most the outer ink line.
		var unit := RelicIcon.frame_points(item.category(), Vector2.ZERO, 1.0)
		var near := 0
		for y: int in n:
			for x: int in n:
				if image.get_pixel(x, y).a > 0.0:
					var at := RelicIcon.PICTURE_OFFSET + ((Vector2(x, y) + Vector2(0.5, 0.5)) / float(n) - Vector2(0.5, 0.5)) * RelicIcon.PICTURE_SHARE
					if not Geometry2D.is_point_in_polygon(at, unit) or _edge_distance(at, unit) < SAFE_INSET - 0.0001:
						near += 1
		assert_eq(near, 0, "%s: every pixel %.2f frame radii inside its frame's edge" % [item.id, SAFE_INSET])
		for px: float in ICON_SIDES:
			var edge := clampf(px * RelicIcon.EDGE_SHARE, RelicIcon.EDGE_MIN, RelicIcon.EDGE_MAX)
			var radius := px * 0.5 - edge
			var c := Vector2(px, px) * 0.5
			var frame := RelicIcon.frame_points(item.category(), c, radius)
			var pic := RelicIcon.picture_rect(c, radius, float(n))
			var texel := pic.size.x / float(n)
			var outside := 0
			for y: int in n:
				for x: int in n:
					if image.get_pixel(x, y).a > 0.0:
						var at := pic.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * texel
						if not Geometry2D.is_point_in_polygon(at, frame):
							outside += 1
			assert_eq(outside, 0, "%s at %d px: every pixel inside its frame" % [item.id, int(px)])
	assert_gt(checked, 50, "the shipped Relics have pictures")


## The distance from `at` to the closed outline `points`.
func _edge_distance(at: Vector2, points: PackedVector2Array) -> float:
	var best := INF
	for i: int in points.size():
		var b := points[(i + 1) % points.size()]
		best = minf(best, at.distance_to(Geometry2D.get_closest_point_to_segment(at, points[i], b)))
	return best
