extends GutTest
## Sprite clips data (DESIGN.md 5.3 and 5.5): every character and enemy whose sprite_clips is set
## has a sheet of exactly the clips' grid size (at most MAX_SHEET pixels a side), row 0 is wide
## enough for the legacy poses, sprite_hframes stays the legacy pose count (the one-row fallback),
## the shadow width is set, and every clip lists cells inside the grid under a String name. With
## no clips wired yet it passes trivially. REQUIRE_TIER1 also checks the Tier 1 clip names; it is
## switched on at phase 10 integration, once the art is in.

const CHARACTER_DIR := "res://data/characters"
const ENEMY_DIR := "res://data/enemies"
const MAX_SHEET: int = 4096
## Legacy poses in row 0 (FighterView.CharPose and EnemyChoreography.Pose).
const HERO_LEGACY: int = 8
const ENEMY_LEGACY: int = 6
## Phase 10 integration switches this on.
const REQUIRE_TIER1: bool = false
const HERO_TIER1: Array[String] = [
	"idle", "ready", "draw", "parry", "parry_hit", "dodge", "jump_up", "jump_down", "hurt", "stagger",
	"strike_windup", "strike", "strike_alt_windup", "strike_alt", "strike_big_windup", "strike_big",
	"cast_windup", "cast", "leap", "fall", "get_up", "victory", "victory_hold",
]
const ENEMY_TIER1: Array[String] = [
	"idle", "windup", "windup_hold", "lunge", "contact", "recoil", "return", "slam", "slam_recover",
	"hurt", "stagger", "death", "walk", "chase",
]


func _load_all(dir: String) -> Array[Resource]:
	var list: Array[Resource] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			list.append(load(dir.path_join(file)))
	return list


func _check(who: String, clips: SpriteClips, sheet_path: String, hframes: int, legacy: int,
		required: Array[String]) -> void:
	assert_eq(hframes, legacy, "%s: sprite_hframes stays the legacy pose count" % who)
	assert_gte(clips.hframes, legacy, "%s: row 0 holds the %d legacy poses" % [who, legacy])
	assert_gt(clips.body_width_px, 0, "%s: body_width_px sizes the shadow" % who)
	assert_gt(clips.frame_size.x, 0, "%s: cell width" % who)
	assert_gt(clips.frame_size.y, 0, "%s: cell height" % who)
	var size := clips.sheet_size()
	assert_lte(size.x, MAX_SHEET, "%s: sheet width %d" % [who, size.x])
	assert_lte(size.y, MAX_SHEET, "%s: sheet height %d" % [who, size.y])
	assert_true(ResourceLoader.exists(sheet_path), "%s: %s exists" % [who, sheet_path])
	var texture := AssetLoader.texture(sheet_path, size)
	assert_eq(Vector2i(texture.get_width(), texture.get_height()), size,
			"%s: %s is the clips' grid size (otherwise it shows as one row)" % [who, sheet_path])
	for key: Variant in clips.clips:
		assert_eq(typeof(key), TYPE_STRING, "%s: clip name %s is a String" % [who, key])
		var clip := String(key)
		var cells := clips.frames(clip)
		assert_gt(cells.size(), 0, "%s: clip %s has cells" % [who, clip])
		for cell: int in cells:
			assert_true(cell >= 0 and cell < clips.cell_count(), "%s: clip %s cell %d inside the %d cells" % [who, clip, cell, clips.cell_count()])
	if REQUIRE_TIER1:
		for clip: String in required:
			assert_gt(clips.count(clip), 0, "%s: Tier 1 clip %s" % [who, clip])


func test_every_sheet_with_clips_matches_them() -> void:
	var characters := _load_all(CHARACTER_DIR)
	var enemies := _load_all(ENEMY_DIR)
	assert_gt(characters.size(), 0, "found the characters")
	assert_gt(enemies.size(), 0, "found the enemies")
	var checked := 0
	for res: Resource in characters:
		var c := res as CharacterData
		if c == null or c.sprite_clips == null:
			continue
		_check(c.id, c.sprite_clips, c.sprite_path, c.sprite_hframes, HERO_LEGACY, HERO_TIER1)
		checked += 1
	for res: Resource in enemies:
		var e := res as EnemyData
		if e == null or e.sprite_clips == null:
			continue
		_check(e.id, e.sprite_clips, e.sprite_path, e.sprite_hframes, ENEMY_LEGACY, ENEMY_TIER1)
		checked += 1
	gut.p("sprite clips checked for %d fighters" % checked)
