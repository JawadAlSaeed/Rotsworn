extends GutTest
## PressNotes (DESIGN 2.10): a skill's press moments become separate numbered rings in a row, one
## per moment (one press answers every striker then), follow-ups left out; ring sizes and speeds.
## Uses the default Tuning and CombatVisuals so edits to the .tres files never break it.

const ABILITY_DIR := "res://data/abilities"
const EPS: float = 0.01

var _tuning := Tuning.new()
var _visuals := CombatVisuals.new()


func _prompt(hit: int, at_ms: int, role: String, character: int) -> Dictionary:
	return {"hit": hit, "at_ms": at_ms, "role": role, "character": character}


func test_one_note_per_press_moment_without_follow_ups() -> void:
	var press := CombatEngine.ROLE_PRESS
	# A team ultimate: three strikers press on two hits, then two follow-ups.
	var prompts := [
		_prompt(0, 900, press, 0), _prompt(0, 900, press, 1), _prompt(0, 900, press, 2),
		_prompt(1, 1400, press, 0), _prompt(1, 1400, press, 1), _prompt(1, 1400, press, 2),
		_prompt(2, 2100, CombatEngine.ROLE_FOLLOW_UP, 1), _prompt(3, 2550, CombatEngine.ROLE_FOLLOW_UP, 2),
	]
	var notes := PressNotes.notes(prompts)
	assert_eq(notes.size(), 2, "one ring per press moment, not one per striker")
	assert_eq(notes[0].at_ms, 900)
	assert_eq(notes[0].prompts, [0, 1, 2], "one press answers every striker at that moment")
	assert_eq(notes[1].at_ms, 1400)
	assert_eq(notes[1].prompts, [3, 4, 5])


func test_notes_are_in_press_order() -> void:
	var press := CombatEngine.ROLE_PRESS
	var notes := PressNotes.notes([_prompt(1, 1100, press, 0), _prompt(0, 800, press, 0), _prompt(2, 1400, press, 0)])
	assert_eq(notes.map(func(n: Dictionary) -> int: return int(n.at_ms)), [800, 1100, 1400])


func test_row_is_centred_left_to_right() -> void:
	assert_eq(PressNotes.offset(0, 1, 150.0), Vector2.ZERO, "a single press stays where the striker stands")
	assert_eq(PressNotes.offset(0, 2, 150.0), Vector2(-75.0, 0.0))
	assert_eq(PressNotes.offset(1, 2, 150.0), Vector2(75.0, 0.0))
	assert_eq(PressNotes.offset(0, 3, 150.0), Vector2(-150.0, 0.0))
	assert_eq(PressNotes.offset(2, 3, 150.0), Vector2(150.0, 0.0))
	assert_eq(PressNotes.scale(1, 0.65), 1.0, "a single press ring keeps its full size")
	assert_eq(PressNotes.scale(3, 0.65), 0.65)


func test_ring_closes_on_the_target_at_the_perfect_moment() -> void:
	assert_almost_eq(PressNotes.radius(-600000, 600000, 220.0, 70.0, 4.0), 220.0, EPS, "appears at the start size")
	assert_almost_eq(PressNotes.radius(-300000, 600000, 220.0, 70.0, 4.0), 145.0, EPS)
	assert_almost_eq(PressNotes.radius(0, 600000, 220.0, 70.0, 4.0), 70.0, EPS, "on the target circle at the perfect moment")
	assert_lt(PressNotes.radius(50000, 600000, 220.0, 70.0, 4.0), 70.0, "keeps shrinking after")
	assert_eq(PressNotes.radius(10000000, 600000, 220.0, 70.0, 4.0), 4.0, "never below the minimum")


func test_skills_set_their_own_ring_speed() -> void:
	var basic := load(ABILITY_DIR.path_join("basic_attack.tres")) as AbilityData
	var rend := load(ABILITY_DIR.path_join("rend.tres")) as AbilityData
	var mend := load(ABILITY_DIR.path_join("mend.tres")) as AbilityData
	assert_eq(basic.ring_lead_ms(_tuning), _tuning.ring_lead_ms, "the basic attack rings at the normal speed")
	assert_lt(mend.ring_lead_ms(_tuning), basic.ring_lead_ms(_tuning), "skills ring faster")
	assert_lt(rend.ring_lead_ms(_tuning), mend.ring_lead_ms(_tuning), "big hits ring fastest")
	var attack := EnemyAttackData.new()
	attack.ring_lead_percent = 50
	assert_eq(attack.ring_lead_ms(_tuning), CombatMath.percent(_tuning.ring_lead_ms, 50))


## At each press's perfect moment the next note's ring (if it shows yet) stays off the current
## note's target circle, so the press you are making now is never covered.
func test_next_ring_never_covers_the_current_target() -> void:
	var checked := 0
	for file: String in DirAccess.get_files_at(ABILITY_DIR):
		if not file.ends_with(".tres"):
			continue
		var ability := load(ABILITY_DIR.path_join(file)) as AbilityData
		var times := ability.press_times_ms
		if times.size() < 2:
			continue
		var lead_us := ability.ring_lead_ms(_tuning) * 1000
		var size := PressNotes.scale(times.size(), _visuals.press_note_scale)
		var start := _visuals.press_ring_start_radius_px * size
		var target := _visuals.press_ring_end_radius_px * size
		for i: int in range(1, times.size()):
			var gap_us := (times[i] - times[i - 1]) * 1000
			if gap_us >= lead_us:
				continue
			var next_radius := PressNotes.radius(-gap_us, lead_us, start, target, 0.0)
			assert_gte(_visuals.press_note_spacing_px - next_radius, target,
					"%s: ring %d covers ring %d's target circle" % [ability.id, i + 1, i])
			checked += 1
	assert_gt(checked, 0, "Quick Cuts and All In show overlapping-in-time rings")
