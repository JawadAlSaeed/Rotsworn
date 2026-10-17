extends GutTest
## FreezeLedger (DESIGN 3.3, card #180): a success freeze ignores only its owner's double taps;
## another local player's press inside it is judged as if the freeze had not happened.

const NOW: int = 5000000
const PARRY_MS: int = 45000


func _owned(players: Array[int]) -> FreezeLedger:
	var ledger := FreezeLedger.new()
	ledger.add(NOW, PARRY_MS, players)
	return ledger


func test_owner_double_tap_is_ignored() -> void:
	var ledger := _owned([0])
	assert_eq(ledger.press_shift_us(NOW + 20000, 0), FreezeLedger.IGNORE)


func test_other_player_press_inside_freeze_is_judged_later_by_the_elapsed_freeze() -> void:
	var ledger := _owned([0])
	# P2 presses 20 ms into P1's freeze: judged 20 ms after the freeze began.
	assert_eq(ledger.press_shift_us(NOW + 20000, 1), 20000)


func test_press_outside_any_freeze_is_not_shifted() -> void:
	var ledger := _owned([0])
	assert_eq(ledger.press_shift_us(NOW - 1, 0), 0)
	assert_eq(ledger.press_shift_us(NOW + PARRY_MS, 1), 0, "the freeze ends exactly at from + length")
	assert_eq(ledger.press_shift_us(NOW + PARRY_MS + 5000, 0), 0)


func test_unowned_hurt_freeze_ignores_nobody() -> void:
	var ledger := FreezeLedger.new()
	var nobody: Array[int] = []
	ledger.add(NOW, 120000, nobody)
	assert_eq(ledger.press_shift_us(NOW + 50000, 0), 50000)
	assert_eq(ledger.press_shift_us(NOW + 50000, 1), 50000)


func test_touching_freezes_shift_from_the_start_of_the_chain() -> void:
	var ledger := FreezeLedger.new()
	ledger.add(NOW, PARRY_MS, [0] as Array[int])
	ledger.add(NOW + 30000, PARRY_MS, [0] as Array[int])
	# P2 at +50 ms is inside only the second freeze, which began inside the first: the clock has
	# been frozen since NOW, so the shift counts from NOW.
	assert_eq(ledger.press_shift_us(NOW + 50000, 1), 50000)


func test_a_player_owning_one_of_two_overlapping_freezes_is_ignored_inside_it() -> void:
	var ledger := FreezeLedger.new()
	ledger.add(NOW, PARRY_MS, [0] as Array[int])
	ledger.add(NOW + 30000, PARRY_MS, [1] as Array[int])
	assert_eq(ledger.press_shift_us(NOW + 40000, 1), FreezeLedger.IGNORE)
	assert_eq(ledger.press_shift_us(NOW + 20000, 1), 20000, "inside only P1's freeze: judged")
	assert_eq(ledger.press_shift_us(NOW + 20000, 0), FreezeLedger.IGNORE)


func test_clear_forgets_old_freezes() -> void:
	var ledger := _owned([0])
	ledger.clear()
	assert_eq(ledger.press_shift_us(NOW + 20000, 0), 0)


func test_p2_press_in_freeze_succeeds_in_the_judge() -> void:
	# Whole path: both players are hit at 1000 ms. P1 parries at the impact and the shared clock
	# freezes; P2 presses 20 ms into the freeze. Judged at the shifted time the press is on the
	# hit (inside the late half of the window), so it is a SUCCESS; P1's double tap is ignored.
	var tuning := Tuning.new()
	var prompts: Array = []
	for who: int in 2:
		prompts.append({"idx": who, "hit": 0, "character": who, "at_ms": 1000,
				"kind": AttackHitData.Kind.NORMAL,
				"windows": Defense.build_windows(AttackHitData.Kind.NORMAL, tuning),
				"perfect": Defense.perfect_outcomes(AttackHitData.Kind.NORMAL), "damage": 10})
	var judges := JudgeSet.new(tuning.whiff_lockout_ms, 0, tuning.press_reach_back_max_ms, tuning.late_press_report_ms)
	judges.set_prompts(prompts, {0: 0, 1: 1})
	var clock := AttackClock.new()
	clock.start(NOW - 1000000)
	var ledger := FreezeLedger.new()
	clock.pause_for(NOW, PARRY_MS)
	ledger.add(NOW, PARRY_MS, [0] as Array[int])
	var stamp := NOW + 20000
	assert_true(clock.is_paused(stamp))
	assert_eq(ledger.press_shift_us(stamp, 0), FreezeLedger.IGNORE, "P1's double tap is still ignored")
	var t := clock.attack_time_us(stamp) + ledger.press_shift_us(stamp, 1)
	assert_eq(t, 1020000, "20 ms after the impact, as if no freeze had happened")
	var report := judges.press(1, Defense.Outcome.PARRY, t)
	assert_eq(int(report.result), DefenseJudge.Result.SUCCESS)


