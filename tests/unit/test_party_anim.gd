extends GutTest
## PartyAnim (DESIGN 5.5, cards #61 and #62): a hero's defence, whiff, flinch and stagger clips on
## the runner's own spans (attack time). parry[0] shows at the press and parry_hit[0] at the
## contact moment; a jump splits at its apex; a dodge follows the slide shares; a heavy hit
## staggers; a whiff holds its way in; without clips the anim's legacy frame shows.

const OUT_SHARE: float = TimedSequenceRunner.DODGE_OUT_SHARE
const BACK_SHARE: float = TimedSequenceRunner.DODGE_BACK_SHARE


## A hero grid sheet whose clips use distinct cells: row 0 holds the eight legacy keys (0..7).
func _clips(extra: Dictionary = {}) -> SpriteClips:
	var c := SpriteClips.new()
	c.frame_size = Vector2i(8, 8)
	c.hframes = 8
	c.vframes = 8
	c.body_width_px = 8
	c.clips = {
		"parry": PackedInt32Array([8, 2]),
		"parry_hit": PackedInt32Array([9, 10, 2]),
		"dodge": PackedInt32Array([11, 3, 3, 12]),
		"jump_up": PackedInt32Array([13, 14, 4]),
		"jump_down": PackedInt32Array([4, 15, 16]),
		"hurt": PackedInt32Array([5, 5, 17, 18]),
		"stagger": PackedInt32Array([5, 19, 19, 20, 21, 18]),
	}
	c.clips.merge(extra, true)
	return c


func _pick(anim: Dictionary, t_us: int, clips: SpriteClips) -> Dictionary:
	return PartyAnim.pick(anim, t_us, EnemyAnim.counter(clips), OUT_SHARE, BACK_SHARE)


## The sheet cell a pick shows on `clips`; -1 for the anim's legacy frame.
func _cell(anim: Dictionary, t_us: int, clips: SpriteClips) -> int:
	var pick := _pick(anim, t_us, clips)
	var cells := ClipNames.cells(clips, String(pick.clip))
	return cells[clampi(int(pick.index), 0, cells.size() - 1)] if not cells.is_empty() else -1


func _anim(kind: int, frame: int, from_us: int, until_us: int, extra: Dictionary = {}) -> Dictionary:
	var anim := {"kind": kind, "frame": frame, "from_us": from_us, "until_us": until_us}
	anim.merge(extra, true)
	return anim


func test_parry_snaps_in_until_contact_then_plays_its_hit() -> void:
	var clips := _clips()
	# Pressed 60 ms early: the parry snaps in, contact at impact (1000 ms), held to 1150 ms.
	var anim := _anim(TimedSequenceRunner.Anim.PARRY, FighterView.CharPose.PARRY, 940_000, 1_150_000,
			{"contact_us": 1_000_000})
	assert_eq(_cell(anim, 940_000, clips), 8, "parry[0] at the press")
	assert_eq(_cell(anim, 999_999, clips), 2, "the parry key just before contact")
	assert_eq(_cell(anim, 1_000_000, clips), 9, "parry_hit[0] exactly at contact")
	assert_eq(_cell(anim, 1_149_000, clips), 2, "back on the parry key at the end")


func test_a_late_or_remote_parry_shows_its_hit_at_once() -> void:
	var clips := _clips()
	# Contact is the press itself (pressed after impact, or another player's result arriving).
	var anim := _anim(TimedSequenceRunner.Anim.PARRY, FighterView.CharPose.PARRY, 1_030_000, 1_180_000,
			{"contact_us": 1_030_000})
	assert_eq(_cell(anim, 1_030_000, clips), 9)


func test_a_jump_rises_to_its_apex_then_falls() -> void:
	var clips := _clips()
	var anim := _anim(TimedSequenceRunner.Anim.JUMP, FighterView.CharPose.JUMP, 800_000, 1_280_000,
			{"apex_us": 1_000_000, "land_us": 1_280_000})
	assert_eq(_cell(anim, 800_000, clips), 13, "jump_up[0] at the press")
	assert_eq(_cell(anim, 999_000, clips), 4, "the jump key at the apex")
	assert_eq(_cell(anim, 1_000_000, clips), 4, "jump_down[0] from the apex")
	assert_eq(_cell(anim, 1_279_000, clips), 16, "landing")


func test_a_dodge_follows_the_slide_shares() -> void:
	var clips := _clips()
	var anim := _anim(TimedSequenceRunner.Anim.DODGE, FighterView.CharPose.DODGE, 0, 1_000_000)
	var out_end := roundi(OUT_SHARE * 1_000_000.0)
	var back_from := roundi((1.0 - BACK_SHARE) * 1_000_000.0)
	assert_eq(_cell(anim, 0, clips), 11, "sliding out: the first cell")
	assert_eq(_cell(anim, out_end - 1, clips), 11)
	assert_eq(_cell(anim, out_end, clips), 3, "out: the dodge key")
	assert_eq(_cell(anim, back_from - 1, clips), 3)
	assert_eq(_cell(anim, back_from + 1, clips), 12, "coming back: the last cell")
	assert_eq(_cell(anim, 999_000, clips), 12)


func test_dodge_index_handles_short_clips() -> void:
	assert_eq(PartyAnim.dodge_index(1, 0.5, OUT_SHARE, BACK_SHARE), 0)
	assert_eq(PartyAnim.dodge_index(2, 0.1, OUT_SHARE, BACK_SHARE), 0)
	assert_eq(PartyAnim.dodge_index(2, 0.5, OUT_SHARE, BACK_SHARE), 0)
	assert_eq(PartyAnim.dodge_index(2, 0.9, OUT_SHARE, BACK_SHARE), 1)
	assert_eq(PartyAnim.dodge_index(3, 0.5, OUT_SHARE, BACK_SHARE), 1)
	for n: int in range(1, 9):
		var last := -1
		var u := 0.0
		while u <= 1.0:
			var i := PartyAnim.dodge_index(n, u, OUT_SHARE, BACK_SHARE)
			assert_between(i, 0, n - 1)
			assert_true(i >= last, "n %d never goes back at u %.2f" % [n, u])
			last = i
			u += 0.01


func test_a_heavy_hit_staggers_and_a_light_one_flinches() -> void:
	var clips := _clips()
	var light := _anim(TimedSequenceRunner.Anim.HURT, FighterView.CharPose.HURT, 0, 320_000, {"heavy": false})
	var heavy := _anim(TimedSequenceRunner.Anim.HURT, FighterView.CharPose.HURT, 0, 480_000, {"heavy": true})
	assert_eq(String(_pick(light, 100_000, clips).clip), "hurt")
	assert_eq(String(_pick(heavy, 100_000, clips).clip), "stagger")
	assert_eq(_cell(light, 0, clips), 5, "both start on the hurt key")
	assert_eq(_cell(heavy, 0, clips), 5)
	assert_eq(_cell(heavy, 479_000, clips), 18, "the stagger recovers")
	var no_stagger := _clips()
	no_stagger.clips.erase("stagger")
	assert_eq(_cell(heavy, 479_000, no_stagger), 18, "no stagger clip: the hurt clip over the stagger's length")


func test_a_whiff_plays_its_way_in_then_holds() -> void:
	var clips := _clips()
	var parry := _anim(TimedSequenceRunner.Anim.WHIFF, FighterView.CharPose.PARRY, 0, 260_000)
	assert_eq(_cell(parry, 0, clips), 8)
	assert_eq(_cell(parry, 130_000, clips), 2, "the parry key from half the whiff on")
	assert_eq(_cell(parry, 259_000, clips), 2)
	var dodge := _anim(TimedSequenceRunner.Anim.WHIFF, FighterView.CharPose.DODGE, 0, 260_000)
	for t: int in range(0, 260_000, 10_000):
		assert_ne(_cell(dodge, t, clips), 12, "a whiffed dodge never steps back out (%d us)" % t)
	assert_eq(_cell(dodge, 259_000, clips), 3)
	var jump := _anim(TimedSequenceRunner.Anim.WHIFF, FighterView.CharPose.JUMP, 0, 260_000)
	assert_eq(_cell(jump, 0, clips), 13)
	assert_eq(_cell(jump, 200_000, clips), 4)


func test_without_clips_the_legacy_frame_shows() -> void:
	var anims: Array[Dictionary] = [
		_anim(TimedSequenceRunner.Anim.PARRY, FighterView.CharPose.PARRY, 0, 200_000, {"contact_us": 50_000}),
		_anim(TimedSequenceRunner.Anim.DODGE, FighterView.CharPose.DODGE, 0, 250_000),
		_anim(TimedSequenceRunner.Anim.JUMP, FighterView.CharPose.JUMP, 0, 480_000, {"apex_us": 240_000, "land_us": 480_000}),
		_anim(TimedSequenceRunner.Anim.WHIFF, FighterView.CharPose.PARRY, 0, 260_000),
		_anim(TimedSequenceRunner.Anim.HURT, FighterView.CharPose.HURT, 0, 480_000, {"heavy": true}),
	]
	for clips: SpriteClips in [null, SpriteClips.new()]:
		for anim: Dictionary in anims:
			for t: int in range(0, 480_000, 20_000):
				assert_eq(String(_pick(anim, t, clips).clip), "", "kind %d at %d us" % [int(anim.kind), t])
