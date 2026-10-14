extends GutTest
## SkillAnimPlan (card #58): the wind-up and strike frames a hero shows during a skill, on skill
## time. The strike's first cell shows exactly at the contact moment (max(press, at) for a good
## press, the window's close for a miss); a press's wind-up never overlaps the previous strike, even
## at All In's 250 ms spacing; and within a press the frames only move forward.

const WINDUP_US: int = 220_000
const STRIKE_US: int = 270_000
const GAP_US: int = 120_000
const WINDUPS: PackedStringArray = ["strike_windup"]
const STRIKES: PackedStringArray = ["strike", "strike_alt"]


func _pick(at: Array[int], contacts: Array[int], t: int) -> Dictionary:
	return SkillAnimPlan.pick(at, contacts, WINDUPS, STRIKES, WINDUP_US, STRIKE_US, GAP_US, t)


func test_before_the_wind_up_the_hero_holds_the_stance() -> void:
	var at: Array[int] = [800_000]
	var none: Array[int] = [SkillAnimPlan.NO_CONTACT]
	var p := _pick(at, none, 0)
	assert_eq(int(p.phase), SkillAnimPlan.Phase.READY)
	assert_eq(String(p.clip), "", "no clip: the combat stance")
	assert_eq(int(_pick(at, none, 579_999).phase), SkillAnimPlan.Phase.READY)
	var w := _pick(at, none, 580_000)
	assert_eq(int(w.phase), SkillAnimPlan.Phase.WINDUP, "the wind-up starts windup before the moment")
	assert_eq(String(w.clip), "strike_windup")
	assert_almost_eq(float(w.u), 0.0, 0.0001)
	assert_almost_eq(float(_pick(at, none, 690_000).u), 0.5, 0.0001)


func test_the_strike_starts_exactly_at_the_contact_for_early_perfect_and_late_presses() -> void:
	var at: Array[int] = [800_000]
	# Early and perfect presses contact at the moment; a late one at the press; a miss at the close.
	for contact: int in [800_000, 860_000, 950_000]:
		var contacts: Array[int] = [contact]
		var before := _pick(at, contacts, contact - 1)
		assert_eq(int(before.phase), SkillAnimPlan.Phase.WINDUP, "contact %d: wind-up just before" % contact)
		assert_almost_eq(float(before.u), 1.0, 0.0001, "a late press holds the wind-up's last cell")
		var hit := _pick(at, contacts, contact)
		assert_eq(int(hit.phase), SkillAnimPlan.Phase.STRIKE, "contact %d: strike at the contact" % contact)
		assert_eq(String(hit.clip), "strike")
		assert_eq(ClipMath.stretch(3, float(hit.u)), 0, "the strike's first cell at the contact")
		assert_eq(int(_pick(at, contacts, contact + STRIKE_US - 1).phase), SkillAnimPlan.Phase.STRIKE)
		assert_eq(int(_pick(at, contacts, contact + STRIKE_US).phase), SkillAnimPlan.Phase.READY,
				"back to the stance once the strike is over")


func test_a_contact_in_the_future_is_not_seen_yet() -> void:
	var at: Array[int] = [800_000]
	var contacts: Array[int] = [900_000]
	var p := _pick(at, contacts, 850_000)
	assert_eq(int(p.phase), SkillAnimPlan.Phase.WINDUP, "the pick never looks ahead")


func test_presses_cycle_through_the_clip_lists() -> void:
	var at: Array[int] = [800_000, 1_100_000, 1_400_000]
	var contacts: Array[int] = [800_000, 1_100_000, 1_400_000]
	assert_eq(String(_pick(at, contacts, 800_000).clip), "strike")
	assert_eq(String(_pick(at, contacts, 1_100_000).clip), "strike_alt")
	assert_eq(String(_pick(at, contacts, 1_400_000).clip), "strike", "press 2 wraps to the first name")
	var empty := PackedStringArray()
	var p := SkillAnimPlan.pick(at, contacts, empty, empty, WINDUP_US, STRIKE_US, GAP_US, 800_000)
	assert_eq(String(p.clip), "", "empty lists hold the stance (Run)")


func test_all_in_spacing_shrinks_the_wind_up_and_never_overlaps_the_previous_strike() -> void:
	var at: Array[int] = [800_000, 1_050_000, 1_300_000, 1_550_000, 1_800_000]
	# Some presses perfect, some a little late, one missed (contact at the close).
	var contacts: Array[int] = [800_000, 1_090_000, 1_300_000, 1_700_000, 1_800_000]
	for k: int in range(1, at.size()):
		var start := SkillAnimPlan.start_us(at, contacts, k, WINDUP_US, GAP_US, contacts[k - 1])
		assert_true(start >= contacts[k - 1] + GAP_US, "press %d winds up only after the gap" % k)
		assert_true(at[k] - start < WINDUP_US or start >= at[k], "press %d: a shorter wind-up" % k)
	for t: int in range(700_000, 2_200_000, 1000):
		var p := _pick(at, contacts, t)
		if int(p.phase) != SkillAnimPlan.Phase.WINDUP:
			continue
		var k := int(p.press)
		if k > 0:
			assert_true(t >= contacts[k - 1] + GAP_US, "t %d: press %d's wind-up overlaps the strike before" % [t, k])


func test_frames_never_go_backwards_within_a_press() -> void:
	var at: Array[int] = [800_000, 1_050_000, 1_300_000, 1_550_000, 1_800_000]
	var contacts: Array[int] = [800_000, 1_120_000, 1_300_000, 1_700_000, 1_830_000]
	var last_press := -1
	var last_rank := -1
	var last_u := 0.0
	for t: int in range(0, 2_400_000, 1000):
		var p := _pick(at, contacts, t)
		var k := int(p.press)
		if k < 0:
			continue
		# WINDUP then STRIKE, each with growing progress: rank them in one order.
		var rank := int(p.phase)
		assert_true(k >= last_press, "t %d: went back from press %d to %d" % [t, last_press, k])
		if k == last_press:
			assert_true(rank >= last_rank, "t %d: press %d went back to its wind-up" % [t, k])
			if rank == last_rank:
				assert_true(float(p.u) >= last_u, "t %d: press %d's progress went back" % [t, k])
		last_press = k
		last_rank = rank
		last_u = float(p.u)
	assert_eq(last_press, 4, "every press played")


func test_a_press_waiting_for_its_contact_holds_its_wind_up() -> void:
	var at: Array[int] = [800_000, 1_050_000]
	# Press 0 not resolved yet (a late press still allowed): press 1 must not start winding up.
	var contacts: Array[int] = [SkillAnimPlan.NO_CONTACT, SkillAnimPlan.NO_CONTACT]
	var p := _pick(at, contacts, 1_000_000)
	assert_eq(int(p.press), 0)
	assert_eq(int(p.phase), SkillAnimPlan.Phase.WINDUP)
	assert_almost_eq(float(p.u), 1.0, 0.0001)


func test_a_wind_up_with_no_room_goes_straight_to_its_last_cell() -> void:
	var at: Array[int] = [800_000, 1_050_000]
	# A missed first press closes late: the second press's wind-up starts after its own moment.
	var contacts: Array[int] = [1_000_000, SkillAnimPlan.NO_CONTACT]
	var start := SkillAnimPlan.start_us(at, contacts, 1, WINDUP_US, GAP_US, 1_200_000)
	assert_eq(start, 1_120_000)
	var p := _pick(at, contacts, 1_120_000)
	assert_eq(int(p.press), 1)
	assert_almost_eq(float(p.u), 1.0, 0.0001)
	assert_eq(int(_pick(at, contacts, 1_119_999).phase), SkillAnimPlan.Phase.STRIKE, "press 0 strikes until then")
