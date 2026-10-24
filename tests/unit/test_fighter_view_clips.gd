extends GutTest
## FighterView with sprite clips (DESIGN.md 5.5), on real nodes (headless) and small sheets drawn
## here: a 3x2 grid of 4x6 cells whose cell 0 has 5 px of art and whose row 1 is fully opaque.
## Checks the grid layout, that the head and centre are measured on cell 0 only, that without
## clips every legacy call shows exactly its pose (as before phase 10), the idle and ready loops,
## driven clips, overrides over the base, the fallbacks, a sheet whose size does not match its
## clips, the clamp to the grid, a flip, death and delayed dissolves, hops, and the
## ClipNames fallback chain.

const CELL := Vector2i(4, 6)
const COLS: int = 3
const ROWS: int = 2
const PIXEL: float = 0.05
const EPS: float = 0.0001
## Sheets drawn by the tests are saved here (AssetLoader reads a file that is not imported).
const FILE_PREFIX := "user://test_fighter_view_clips_"

const IDLE := FighterView.CharPose.IDLE
const READY := FighterView.CharPose.READY
const PARRY := FighterView.CharPose.PARRY
const DODGE := FighterView.CharPose.DODGE
const JUMP := FighterView.CharPose.JUMP
const HURT := FighterView.CharPose.HURT
const STRIKE := FighterView.CharPose.STRIKE
const DOWN := FighterView.CharPose.DOWN
const E_IDLE := EnemyChoreography.Pose.IDLE
const E_WINDUP := EnemyChoreography.Pose.WINDUP
const E_LUNGE := EnemyChoreography.Pose.LUNGE
const E_HURT := EnemyChoreography.Pose.HURT

var _visuals: CombatVisuals
var _files: Array[String] = []


func before_each() -> void:
	_visuals = CombatVisuals.new()


func after_all() -> void:
	for path: String in _files:
		DirAccess.remove_absolute(path)


# --- helpers ----------------------------------------------------------------------------------

## Saves `img` once per run under `tag` (AssetLoader caches a raw file by path, and warns once
## per path that it is not imported, so every test of a kind shares one file).
func _save(img: Image, tag: String) -> String:
	var path := FILE_PREFIX + tag + ".png"
	if not _files.has(path):
		assert_eq(img.save_png(path), OK, "saved %s" % path)
		_files.append(path)
	return path


## The 3x2 grid: cell 0 is opaque on its rows 1..4 (5 px of art, 1 px above the feet); all of
## row 1 is opaque, so a measure that read past row 0 would come out wrong.
func _grid_sheet() -> String:
	var img := Image.create(CELL.x * COLS, CELL.y * ROWS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y: int in range(1, 5):
		for x: int in CELL.x:
			img.set_pixel(x, y, Color.WHITE)
	for y: int in range(CELL.y, CELL.y * ROWS):
		for x: int in CELL.x * COLS:
			img.set_pixel(x, y, Color.WHITE)
	return _save(img, "grid")


## A legacy one-row strip of `frames` opaque cells (not the grid's size).
func _strip_sheet(tag: String, frames: int) -> String:
	var img := Image.create(CELL.x * frames, CELL.y, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return _save(img, tag)


func _clips(clip_map: Dictionary) -> SpriteClips:
	var c := SpriteClips.new()
	c.frame_size = CELL
	c.hframes = COLS
	c.vframes = ROWS
	c.body_width_px = 3
	for clip: String in clip_map:
		c.clips[clip] = PackedInt32Array(clip_map[clip] as Array)
	return c


func _view(party: bool, path: String, clips: SpriteClips, hframes: int = 6, idle_percent: int = 100,
		id: int = 0) -> FighterView:
	var view := FighterView.new()
	add_child_autofree(view)
	view.setup(id, party, path, hframes, CELL, PIXEL, false, _visuals, clips, idle_percent)
	return view


func _body(view: FighterView) -> Sprite3D:
	return view.get_node("Body") as Sprite3D


func _frame(view: FighterView) -> int:
	return _body(view).frame


## Every cell the view shows over `span_ms` from now (sampled every `step_ms`).
func _cells_over(view: FighterView, span_ms: int, step_ms: int = 10) -> Dictionary:
	var seen := {}
	var now := FighterView.now_ms()
	for t: int in range(0, span_ms, step_ms):
		seen[view.cell_at(now + float(t))] = true
	return seen


# --- layout -----------------------------------------------------------------------------------

func test_grid_layout_comes_from_the_clips() -> void:
	var view := _view(false, _grid_sheet(), _clips({}))
	assert_eq(_body(view).hframes, COLS)
	assert_eq(_body(view).vframes, ROWS)
	assert_almost_eq(view.sprite_height(), CELL.y * PIXEL, EPS, "one cell tall, not the whole sheet")
	assert_almost_eq(_body(view).offset.y, CELL.y * 0.5, EPS, "feet at the node")
	var material := _body(view).material_override as ShaderMaterial
	assert_almost_eq(float(material.get_shader_parameter("sheet_rows")), float(ROWS), EPS, "dissolve bias per cell")
	var shadow := view.get_node("Shadow") as Sprite3D
	assert_almost_eq(shadow.pixel_size * shadow.texture.get_width(), 3 * PIXEL * _visuals.shadow_width_factor, EPS,
			"the shadow follows body_width_px")


func test_head_and_centre_are_measured_on_cell_zero_only() -> void:
	var view := _view(false, _grid_sheet(), _clips({}))
	assert_almost_eq(view.visible_height(), 5 * PIXEL, EPS, "5 px of art in cell 0")
	assert_almost_eq(view.centre_position().y, 3 * PIXEL, EPS, "middle of rows 1 px .. 6 px above the feet")
	assert_almost_eq(view.head_position().y, 5 * PIXEL * _visuals.head_height_factor, EPS)


func test_missing_png_with_clips_uses_a_grid_placeholder() -> void:
	var view := _view(false, "", _clips({"idle": [0, 3]}))
	assert_eq(_body(view).hframes, COLS, "the placeholder has the grid's size")
	assert_eq(_body(view).vframes, ROWS)
	assert_true(view.has_clip("idle"))


func test_size_mismatch_uses_the_legacy_row() -> void:
	var view := _view(false, _strip_sheet("mismatch", 6), _clips({"idle": [0, 3, 4]}), 6)
	assert_eq(_body(view).hframes, 6, "sprite_hframes frames")
	assert_eq(_body(view).vframes, 1, "one row")
	assert_almost_eq(view.sprite_height(), CELL.y * PIXEL, EPS)
	var material := _body(view).material_override as ShaderMaterial
	assert_almost_eq(float(material.get_shader_parameter("sheet_rows")), 1.0, EPS)
	assert_false(view.has_clip("idle"), "the clips are ignored")
	view.set_pose(E_IDLE)
	assert_eq(_cells_over(view, 3000, 50).keys(), [0], "idle does not loop")
	view.set_pose(5)
	assert_eq(_frame(view), 5)


# --- legacy (no clips) ------------------------------------------------------------------------

func test_without_clips_every_legacy_call_shows_the_pose() -> void:
	var view := _view(true, "", null, 8)
	assert_eq(_body(view).hframes, 8)
	assert_eq(_body(view).vframes, 1)
	assert_eq(_frame(view), IDLE, "starts idle")
	for pose: int in 8:
		view.set_pose(pose)
		assert_eq(_frame(view), pose, "set_pose(%d)" % pose)
		assert_eq(_cells_over(view, 2000, 100).keys(), [pose], "pose %d holds still" % pose)
	view.set_pose(READY)
	view.play_pose(STRIKE, 60000)
	assert_eq(_frame(view), STRIKE, "play_pose shows at once")
	view.set_pose(DOWN)
	assert_eq(_frame(view), STRIKE, "the timed pose stays over a new base pose")
	view.clear_timed_pose()
	assert_eq(_frame(view), DOWN, "clear_timed_pose goes back to the base")
	view.play_pose(HURT, 100)
	assert_eq(view.cell_at(FighterView.now_ms() + 150.0), DOWN, "the timed pose runs out")
	view.clear_timed_pose()
	view.show_clip("parry", 0, PARRY)
	assert_eq(_frame(view), PARRY, "show_clip falls back to the pose")
	assert_true(view.play("stagger", 1000, FighterView.PRIO_BIG, HURT), "play falls back to the pose")
	assert_eq(_frame(view), HURT)
	view.clear_timed_pose()
	assert_false(view.play("death", 1000, FighterView.PRIO_FINAL), "nothing to play without a fallback")
	assert_eq(_frame(view), PARRY)
	assert_false(view.has_clip("idle"))
	assert_eq(view.clip_count("strike"), 0)


# --- loops, driven clips, overrides -----------------------------------------------------------

func test_set_pose_idle_and_ready_loop_with_clips() -> void:
	var view := _view(true, _grid_sheet(), _clips({"idle": [0, 3, 4, 3], "ready": [1, 5]}), 8, 100, 1)
	view.set_pose(IDLE)
	assert_eq(_cells_over(view, _visuals.idle_cycle_ms).size(), 3, "idle shows its three cells over one cycle")
	assert_true(_cells_over(view, _visuals.idle_cycle_ms).has(4))
	var now := FighterView.now_ms()
	for t: int in range(0, 1600, 70):
		assert_eq(view.cell_at(now + t), view.cell_at(now + t + _visuals.idle_cycle_ms), "idle repeats every idle_cycle_ms")
	view.set_pose(READY)
	var ready := _cells_over(view, _visuals.ready_cycle_ms)
	assert_eq(ready.size(), 2, "ready loops its own clip")
	assert_true(ready.has(1) and ready.has(5))
	for t: int in range(0, 900, 70):
		assert_eq(view.cell_at(now + t), view.cell_at(now + t + _visuals.ready_cycle_ms), "ready repeats every ready_cycle_ms")
	view.set_pose(PARRY)
	assert_eq(_cells_over(view, 2000, 50).keys(), [PARRY], "other poses show their row-0 key")


func test_enemy_idle_loop_uses_its_idle_percent() -> void:
	var view := _view(false, _grid_sheet(), _clips({"idle": [0, 3, 4, 3]}), 6, 50, 4)
	view.set_pose(E_IDLE)
	var period := CombatMath.percent(_visuals.enemy_idle_cycle_ms, 50)
	assert_eq(_cells_over(view, period).size(), 3)
	var now := FighterView.now_ms()
	for t: int in range(0, period, 37):
		assert_eq(view.cell_at(now + t), view.cell_at(now + t + period), "half the enemy idle cycle")


func test_show_clip_drives_the_base() -> void:
	var view := _view(false, _grid_sheet(), _clips({"lunge": [3, 4, 2]}))
	view.show_clip("lunge", 1, E_LUNGE)
	assert_eq(_frame(view), 4)
	assert_eq(_cells_over(view, 2000, 100).keys(), [4], "a driven cell stays until the caller moves it")
	view.show_clip("lunge", 99, E_LUNGE)
	assert_eq(_frame(view), 2, "clamped to the clip")
	view.show_clip("lunge", -3, E_LUNGE)
	assert_eq(_frame(view), 3)
	view.show_clip_u("lunge", 0.0, E_LUNGE)
	assert_eq(_frame(view), 3)
	view.show_clip_u("lunge", 0.5, E_LUNGE)
	assert_eq(_frame(view), 4)
	view.show_clip_u("lunge", 1.0, E_LUNGE)
	assert_eq(_frame(view), 2)


func test_override_beats_base_and_expires_back_to_it() -> void:
	var view := _view(false, _grid_sheet(), _clips({"hurt": [4, 5]}))
	view.set_pose(E_LUNGE)
	view.play_pose(E_HURT, 200)
	var now := FighterView.now_ms()
	assert_eq(_frame(view), 4, "the hurt clip shows at once")
	assert_eq(view.cell_at(now + 150.0), 5, "spread over the length")
	assert_eq(view.cell_at(now + 250.0), E_LUNGE, "then back to the base")
	assert_true(view.is_busy())
	view.set_pose(E_WINDUP)
	assert_eq(_frame(view), 4, "a new base waits under the override")
	view.clear_timed_pose()
	assert_eq(_frame(view), E_WINDUP)
	assert_false(view.is_busy())


func test_clear_timed_pose_below_a_priority() -> void:
	var view := _view(true, _grid_sheet(), _clips({"fall": [3, 4], "hurt": [2]}), 8)
	assert_true(view.play("fall", 1000, FighterView.PRIO_BIG))
	assert_eq(_frame(view), 3)
	view.play_pose(HURT, 1000)
	assert_eq(_frame(view), 3, "a hurt does not cut a fall short")
	view.clear_timed_pose(FighterView.PRIO_BIG)
	assert_eq(_frame(view), 3, "a BIG pose survives clear_timed_pose(PRIO_BIG)")
	assert_true(view.play("hurt", 1000, FighterView.PRIO_BIG), "equal priority replaces")
	assert_eq(_frame(view), 2)
	view.clear_timed_pose(FighterView.PRIO_FINAL)
	assert_eq(_frame(view), IDLE)


func test_missing_clips_fall_back() -> void:
	var view := _view(true, _grid_sheet(), _clips({"hurt": [2], "strike": [3]}), 8)
	view.play("stagger", 400, FighterView.PRIO_BIG, HURT)
	assert_eq(_frame(view), 2, "stagger falls back to the hurt clip")
	view.clear_timed_pose()
	view.play("strike_big", 400, FighterView.PRIO_REACT, STRIKE)
	assert_eq(_frame(view), 3, "strike_big falls back to strike")
	view.clear_timed_pose()
	view.play("fall", 400, FighterView.PRIO_BIG, JUMP)
	assert_eq(_frame(view), JUMP, "no clip: the caller's pose")
	view.clear_timed_pose()
	view.play("rend", 400, FighterView.PRIO_REACT)
	assert_eq(_frame(view), 3, "an unknown strike name plays strike")
	view.clear_timed_pose()
	view.show_clip("rend_windup", 0, READY)
	assert_eq(_frame(view), READY, "no wind-up clip: the caller's pose")
	assert_false(view.play("victory", 400, FighterView.PRIO_FINAL), "missing and no fallback: nothing")
	assert_eq(_frame(view), READY)
	view.set_loop("victory_hold", 400, IDLE)
	assert_eq(_frame(view), IDLE, "a missing loop shows the fallback pose")


func test_frame_is_clamped_to_the_grid() -> void:
	var view := _view(true, _grid_sheet(), _clips({"hurt": [99]}), 8)
	view.set_pose(DOWN)
	assert_eq(_frame(view), COLS * ROWS - 1, "pose 7 on a 6-cell grid")
	view.play_pose(HURT, 1000)
	assert_eq(_frame(view), COLS * ROWS - 1, "a cell past the grid")
	for cell: int in _cells_over(view, 2000, 50):
		assert_lt(cell, COLS * ROWS)


func test_flip_keeps_the_frame() -> void:
	var view := _view(true, _grid_sheet(), _clips({"strike": [3], "strike_front": [4]}), 8, 100, -1)
	view.play_pose(STRIKE, 1000)
	assert_eq(_frame(view), 3, "the side clip (a fight never faces front)")
	view.set_flip(true)
	assert_true(_body(view).flip_h)
	assert_eq(_frame(view), 3, "flipping keeps the frame")


func test_delayed_victory_then_hold_loop() -> void:
	var view := _view(true, _grid_sheet(), _clips({"victory": [3, 4], "victory_hold": [5, 2]}), 8)
	view.set_pose(IDLE)
	var now := FighterView.now_ms()
	assert_true(view.play("victory", 400, FighterView.PRIO_FINAL, -1, 300))
	view.set_loop("victory_hold", 200, IDLE, 700)
	assert_eq(_frame(view), IDLE, "nothing changes during the delay")
	assert_true(view.is_busy(FighterView.PRIO_FINAL), "a pending final pose counts")
	assert_eq(view.cell_at(now + 100.0), IDLE)
	assert_eq(view.cell_at(now + 350.0), 3, "the victory pose")
	assert_eq(view.cell_at(now + 600.0), 4)
	assert_eq(view.cell_at(now + 750.0), 5, "then the hold loop from its first cell")
	assert_eq(view.cell_at(now + 860.0), 2)


func test_is_dying_with_a_delayed_dissolve_or_a_death_clip() -> void:
	var rot := _view(false, _grid_sheet(), _clips({}))
	assert_false(rot.is_dying())
	rot.set_dissolve(0.0)
	rot.dissolve(500, Color.RED, 300)
	assert_true(rot.is_dissolving(), "dissolving from the call on, delay included")
	assert_true(rot.is_dying())
	var material := _body(rot).material_override as ShaderMaterial
	assert_almost_eq(float(material.get_shader_parameter("dissolve")), 0.0, EPS, "still whole during the delay")

	var dead := _view(false, _grid_sheet(), _clips({"death": [3, 4, 5], "hurt": [2]}))
	assert_true(dead.play("death", 300, FighterView.PRIO_FINAL, E_HURT, 0, true))
	assert_true(dead.is_dying())
	assert_eq(_frame(dead), 3)
	dead.play_pose(E_HURT, 1000)
	assert_eq(_frame(dead), 3, "a hurt never interrupts a death")
	assert_eq(dead.cell_at(FighterView.now_ms() + 10000.0), 5, "held on its last cell")
	dead.clear_timed_pose(FighterView.PRIO_FINAL)
	assert_true(dead.is_dying(), "only a full clear drops it")
	dead.clear_timed_pose()
	assert_false(dead.is_dying())

	var gone := _view(false, "", null)
	gone.dissolve(0, Color.RED)
	assert_false(gone.is_dissolving(), "ms 0: gone at once")
	var gone_material := _body(gone).material_override as ShaderMaterial
	assert_almost_eq(float(gone_material.get_shader_parameter("dissolve")), 1.0, EPS)


func test_hop_follows_an_arc() -> void:
	var from := Vector3(-1.0, 0.0, 0.5)
	var to := Vector3(1.0, 0.0, 0.5)
	assert_almost_eq(FighterView.hop_point(from, to, 0.0, 0.8), from, Vector3.ONE * EPS)
	assert_almost_eq(FighterView.hop_point(from, to, 0.5, 0.8), Vector3(0.0, 0.8, 0.5), Vector3.ONE * EPS, "top of the arc half way")
	assert_almost_eq(FighterView.hop_point(from, to, 1.0, 0.8), to, Vector3.ONE * EPS)
	var view := _view(true, "", null, 8)
	view.hop_body(to, 0.0, 0.8)
	assert_almost_eq(view.body_offset, to, Vector3.ONE * EPS, "0 seconds snaps")
	view.hop_body(from, 0.1, 0.8)
	await wait_seconds(0.3)
	assert_almost_eq(view.body_offset, from, Vector3.ONE * EPS, "lands on the target")


# --- clip names -------------------------------------------------------------------------------

func test_clip_names_variants_fall_back_to_their_base_clip() -> void:
	var clips := _clips({"lunge": [1], "windup": [2]})
	assert_eq(ClipNames.resolve(clips, "cleave_lunge"), "lunge", "an attack's prefix")
	assert_eq(ClipNames.resolve(clips, "lunge_b"), "lunge", "a second limb")
	assert_eq(ClipNames.resolve(clips, "cleave_lunge_b"), "lunge")
	assert_eq(ClipNames.resolve(clips, "belly_windup"), "windup")
	assert_eq(ClipNames.resolve(clips, "windup_ground"), "windup")
	assert_eq(ClipNames.resolve(clips, "contact"), "", "a missing catalogue clip: the caller's pose")
	assert_eq(ClipNames.resolve(null, "lunge"), "", "no clips")


func test_clip_names_catalogue_clips_follow_only_the_table() -> void:
	var clips := _clips({"down": [7], "strike": [6], "strike_windup": [5], "walk_side": [3]})
	assert_eq(ClipNames.resolve(clips, "jump_down"), "", "never the downed pose")
	assert_eq(ClipNames.resolve(clips, "ultimate_2"), "strike", "ultimate_2 > strike_big > strike")
	assert_eq(ClipNames.resolve(clips, "follow_up"), "strike")
	assert_eq(ClipNames.resolve(clips, "cast"), "strike")
	assert_eq(ClipNames.resolve(clips, "run"), "walk_side")
	assert_eq(ClipNames.resolve(clips, "follow_up_windup"), "strike_windup")
	assert_eq(ClipNames.resolve(clips, "strike_big_windup"), "strike_windup", "any wind-up")
	assert_eq(ClipNames.resolve(clips, "rend_windup"), "strike_windup")
	assert_eq(ClipNames.resolve(clips, "quick_cuts_3"), "strike", "a per-skill strike name")
	assert_eq(ClipNames.resolve(clips, "walk_front"), "", "a catalogue clip never turns into strike")


func test_clip_names_poses_and_table_are_consistent() -> void:
	assert_eq(ClipNames.pose_name(FighterView.CharPose.JUMP, true), "jump")
	assert_eq(ClipNames.pose_name(EnemyChoreography.Pose.HURT, false), "hurt")
	assert_eq(ClipNames.pose_name(FighterView.CharPose.DOWN, true), "down")
	assert_eq(ClipNames.pose_name(8, true), "", "past the row")
	assert_eq(ClipNames.pose_name(-1, false), "")
	assert_eq(ClipNames.HERO_POSES.size(), FighterView.CharPose.size())
	assert_eq(ClipNames.ENEMY_POSES.size(), EnemyChoreography.Pose.size())
	for clip: String in ClipNames.FALLBACK:
		assert_true(ClipNames.KNOWN.has(clip), "%s is in the catalogue" % clip)
		assert_true(ClipNames.KNOWN.has(String(ClipNames.FALLBACK[clip])), "%s falls back to a catalogue clip" % clip)
	for clip: String in ClipNames.HERO_POSES + ClipNames.ENEMY_POSES:
		assert_true(ClipNames.KNOWN.has(clip), "pose %s is in the catalogue" % clip)
