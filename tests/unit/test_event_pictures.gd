extends GutTest
## The "?" pictures (card #199, DESIGN.md 5.4 and 8.7): every event and every act's ambush page has
## its own painted picture of the agreed size, the event screen draws it sharp inside its frame at
## the scale the data says, and a missing file falls back to the old question mark.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const EVENTS_DIR := "res://data/events"
const PICTURE_DIR := "res://assets/sprites/events/"
const PICTURE_SIZE := Vector2i(128, 64)

var _data: RunData
var _tuning: Tuning
var _look: StopVisuals


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning
	_look = StopVisuals.load_default()


func _run() -> RunState:
	return RunState.begin(_data, _tuning, 7)


func _screen(run: RunState, event: EventData) -> EventScreen:
	var screen := EventScreen.new()
	add_child_autofree(screen)
	screen.setup(run, event)
	return screen


## The picture the screen draws (the TextureRect inside its frame).
func _picture_of(screen: EventScreen) -> TextureRect:
	for node: Node in screen.find_children("*", "TextureRect", true, false):
		var rect := node as TextureRect
		if rect.texture != null and rect.get_parent() is PanelContainer:
			return rect
	return null


func _events() -> Array[EventData]:
	var list: Array[EventData] = []
	for file: String in DirAccess.get_files_at(EVENTS_DIR):
		if file.ends_with(".tres"):
			list.append(load("%s/%s" % [EVENTS_DIR, file]) as EventData)
	return list


func test_every_event_has_its_own_picture_file_of_the_agreed_size() -> void:
	var seen := {}
	var events := _events()
	assert_gte(events.size(), 20)
	for event: EventData in events:
		assert_eq(event.picture_path, "%s%s.png" % [PICTURE_DIR, event.id], "%s points at its own picture" % event.id)
		assert_true(AssetLoader.has_art(event.picture_path), "%s: the file exists" % event.id)
		assert_false(seen.has(event.picture_path), "%s: no two events share a picture" % event.id)
		seen[event.picture_path] = true
		var tex := AssetLoader.texture(event.picture_path)
		assert_eq(Vector2i(tex.get_size()), PICTURE_SIZE, "%s: %dx%d art pixels" % [event.id, PICTURE_SIZE.x, PICTURE_SIZE.y])


func test_every_act_has_its_own_ambush_picture() -> void:
	var run := _run()
	var seen := {}
	for act: ActData in run.acts():
		assert_true(act.ambush_picture_path.begins_with(PICTURE_DIR), "%s: ambush picture in the events folder" % act.id)
		assert_true(AssetLoader.has_art(act.ambush_picture_path), "%s: the ambush picture exists" % act.id)
		assert_false(seen.has(act.ambush_picture_path), "each act has its own")
		seen[act.ambush_picture_path] = true
		assert_eq(Vector2i(AssetLoader.texture(act.ambush_picture_path).get_size()), PICTURE_SIZE)


func test_the_pictures_are_opaque_and_stay_a_few_dozen_colours() -> void:
	var paths: Array[String] = []
	for event: EventData in _events():
		paths.append(event.picture_path)
	for act: ActData in _run().acts():
		paths.append(act.ambush_picture_path)
	for path: String in paths:
		var img := AssetLoader.texture(path).get_image()
		var colours := {}
		var clear := 0
		for y: int in img.get_height():
			for x: int in img.get_width():
				var c := img.get_pixel(x, y)
				colours[c.to_rgba32()] = true
				if c.a < 1.0:
					clear += 1
		assert_eq(clear, 0, "%s is fully opaque" % path)
		assert_lte(colours.size(), 96, "%s keeps to a few dozen colours" % path)


func test_the_screen_draws_the_picture_sharp_inside_a_frame_at_the_data_scale() -> void:
	var event := load("%s/weeping_well.tres" % EVENTS_DIR) as EventData
	var screen := _screen(_run(), event)
	var rect := _picture_of(screen)
	assert_not_null(rect, "a picture inside a frame")
	assert_eq(rect.texture.resource_path, event.picture_path)
	assert_eq(rect.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "never blurred")
	assert_eq(rect.custom_minimum_size, Vector2(PICTURE_SIZE * _look.event_picture_scale))
	var frame := rect.get_parent() as PanelContainer
	var style := frame.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(style.border_width_left, _look.frame_border)
	assert_eq(style.border_color, _look.frame_border_color)


func test_a_missing_picture_file_falls_back_to_the_question_mark() -> void:
	var event := EventData.new()
	event.id = "nowhere"
	event.title = "Nowhere"
	event.picture_path = "res://assets/sprites/events/does_not_exist.png"
	var rect := _picture_of(_screen(_run(), event))
	assert_not_null(rect)
	assert_eq(rect.texture.resource_path, _look.fallback_picture_path)
	assert_eq(rect.custom_minimum_size, rect.texture.get_size() * _look.fallback_picture_scale)


func test_an_event_with_no_picture_shows_the_acts_ambush_picture() -> void:
	var run := _run()
	var event := EventData.new()
	event.id = "plain"
	var rect := _picture_of(_screen(run, event))
	assert_eq(rect.texture.resource_path, run.act_data().ambush_picture_path)


func test_an_ambush_page_shows_the_acts_ambush_picture_not_an_events() -> void:
	var run := _run()
	run.ambush_id = "hyena_pack"
	var rect := _picture_of(_screen(run, null))
	assert_eq(rect.texture.resource_path, run.act_data().ambush_picture_path)
	assert_eq(rect.custom_minimum_size, Vector2(PICTURE_SIZE * _look.event_picture_scale))


func test_the_stop_visuals_data_is_sane() -> void:
	assert_true(ResourceLoader.exists(StopVisuals.PATH))
	assert_gte(_look.event_picture_scale, 1)
	assert_true(AssetLoader.has_art(_look.fallback_picture_path), "the question mark is still there")
	assert_gte(_look.frame_border, 0)
	# The picture and its frame must leave room for the title, the story and three choices on a
	# 1080p screen (the column is about 520 px of text and menu).
	var total := PICTURE_SIZE.y * _look.event_picture_scale + 2 * (_look.frame_border + _look.frame_padding)
	assert_lte(total, 330, "the framed picture is not taller than %d px" % 330)


func test_has_art_knows_a_missing_file() -> void:
	assert_true(AssetLoader.has_art("res://assets/sprites/ui/map_event.png"))
	assert_false(AssetLoader.has_art("res://assets/sprites/events/nope.png"))
	assert_false(AssetLoader.has_art(""))
