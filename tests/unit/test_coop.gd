extends GutTest
## Local co-op (DESIGN.md 9.1): the player roster (solo controls everything, joining, leaving,
## the even split, handing heroes over, device codes) and per-player judging (JudgeSet: a press
## answers only its player's heroes, lockout per player, released results the engine accepts).

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const NONE: int = Defense.Outcome.NONE
const PARRY: int = Defense.Outcome.PARRY
const JUMP: int = Defense.Outcome.JUMP
const SUCCESS: int = DefenseJudge.Result.SUCCESS
const WHIFF: int = DefenseJudge.Result.WHIFF
const DONE: int = DefenseJudge.Result.DONE
const KEYBOARD: int = PlayerRoster.KEYBOARD

var _tuning := Tuning.new()


func _judges(prompts: Array, owners: Dictionary) -> JudgeSet:
	var judges := JudgeSet.new(_tuning.whiff_lockout_ms, 0, _tuning.press_reach_back_max_ms, _tuning.late_press_report_ms)
	judges.set_prompts(prompts, owners)
	return judges


## Party-wide: normal hit at 900 ms, ground hit at 1500 ms (prompts 0-2 hit 0, 3-5 hit 1).
func _party_attack_engine() -> CombatEngine:
	var attack := Fx.attack("combo", [Fx.hit(900, Fx.NORMAL, 50), Fx.hit(1500, Fx.GROUND, 80)], Fx.PARTY)
	return Fx.started([attack])


func _submit_ready(engine: CombatEngine, judges: JudgeSet) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for r: Dictionary in judges.pop_ready():
		results.append(CombatCommands.prompt_result(int(r.prompt), int(r.outcome), int(r.offset_us)))
	if results.is_empty():
		return []
	return engine.submit(CombatCommands.resolve_prompts(int(engine.sequence.seq), results))


# --- roster -----------------------------------------------------------------------------------

func test_solo_controls_everything_from_any_device() -> void:
	var roster := PlayerRoster.solo(3)
	assert_false(roster.is_coop())
	assert_eq(roster.owners, [0, 0, 0] as Array[int])
	for device: int in [KEYBOARD, 0, 1, 5, PlayerRoster.ANY]:
		assert_eq(roster.player_of_device(device), 0, "solo: device %d is player 1" % device)
		assert_true(roster.may_control(device, 2))
	assert_eq(roster.validate(), [] as Array[String])


func test_join_splits_heroes_evenly_with_the_extra_to_p1() -> void:
	var roster := PlayerRoster.solo(3, KEYBOARD)
	assert_eq(roster.join(0), 1)
	assert_true(roster.is_coop())
	assert_eq(roster.owners, [0, 1, 0] as Array[int], "two players: P1 gets heroes 1 and 3")
	assert_eq(roster.heroes_of(0), [0, 2] as Array[int])
	assert_eq(roster.join(1), 2)
	assert_eq(roster.owners, [0, 1, 2] as Array[int], "three players: one hero each")
	assert_eq(roster.join(2), -1, "at most three players")
	assert_eq(roster.join(KEYBOARD), -1, "a device joins once")
	assert_eq(roster.validate(), [] as Array[String])


func test_coop_devices_are_told_apart() -> void:
	var roster := PlayerRoster.solo(3, KEYBOARD)
	roster.join(0)
	assert_eq(roster.player_of_device(KEYBOARD), 0)
	assert_eq(roster.player_of_device(0), 1)
	assert_eq(roster.player_of_device(1), -1, "a pad that did not join plays nobody")
	assert_eq(roster.device_of_player(1), 0)
	assert_true(roster.may_control(KEYBOARD, 0))
	assert_false(roster.may_control(KEYBOARD, 1), "P1 cannot drive P2's hero")
	assert_true(roster.may_control(0, 1))
	assert_false(roster.may_control(1, 0))


func test_leave_moves_later_players_up_and_resplits() -> void:
	var roster := PlayerRoster.solo(3, KEYBOARD)
	roster.join(0)
	roster.join(1)
	assert_true(roster.leave(1))
	assert_eq(roster.devices, [KEYBOARD, 1] as Array[int], "P3 becomes P2")
	assert_eq(roster.owners, [0, 1, 0] as Array[int])
	assert_true(roster.leave(1))
	assert_false(roster.is_coop())
	assert_eq(roster.owners, [0, 0, 0] as Array[int])
	assert_false(roster.leave(0), "the last player never leaves")


func test_move_hero_keeps_a_hero_for_every_player() -> void:
	var roster := PlayerRoster.solo(3, KEYBOARD)
	assert_false(roster.move_hero(0, 1), "solo: nothing to hand over")
	roster.join(0)
	# [P1, P2, P1]: P2's only hero cannot leave them.
	assert_false(roster.move_hero(1, 1))
	assert_true(roster.move_hero(2, 1))
	assert_eq(roster.owners, [0, 1, 1] as Array[int])
	assert_false(roster.move_hero(0, -1), "P1's last hero stays")
	assert_true(roster.move_hero(2, -1), "left goes back to the previous player (wrapping)")
	assert_eq(roster.owners, [0, 1, 0] as Array[int])
	assert_eq(roster.validate(), [] as Array[String])


func test_copy_is_independent() -> void:
	var roster := PlayerRoster.solo(3, KEYBOARD)
	var other := roster.copy()
	other.join(0)
	assert_false(roster.is_coop(), "editing a copy leaves the original alone")
	assert_eq(roster.owners, [0, 0, 0] as Array[int])


func test_validate_finds_problems() -> void:
	var roster := PlayerRoster.solo(3, KEYBOARD)
	roster.devices = [KEYBOARD, KEYBOARD] as Array[int]
	roster.owners = [0, 0, 5] as Array[int]
	var problems := roster.validate()
	assert_true(problems.size() >= 3, "shared device, hero without a player, player without a hero: %s" % [problems])


func test_unknown_slot_belongs_to_p1() -> void:
	var roster := PlayerRoster.solo(2, KEYBOARD)
	roster.join(0)
	assert_eq(roster.owner_of(7), 0)
	assert_eq(roster.owner_of(-1), 0)


func test_device_codes_of_events() -> void:
	var key := InputEventKey.new()
	key.device = 16
	assert_eq(PlayerRoster.device_of(key), KEYBOARD, "every keyboard is one device")
	var button := InputEventJoypadButton.new()
	button.device = 2
	assert_eq(PlayerRoster.device_of(button), 2)
	var motion := InputEventJoypadMotion.new()
	motion.device = 1
	assert_eq(PlayerRoster.device_of(motion), 1)
	assert_eq(PlayerRoster.device_of(InputEventMouseButton.new()), KEYBOARD)
	assert_eq(PlayerRoster.device_name(KEYBOARD), "Keyboard")
	assert_eq(PlayerRoster.device_name(0), "Pad 1")


func test_shipped_party_fits_a_full_roster() -> void:
	var run := load("res://data/runs/rotten_road.tres") as RunData
	assert_not_null(run)
	var roster := PlayerRoster.solo(run.party.size(), KEYBOARD)
	roster.join(0)
	roster.join(1)
	assert_eq(roster.validate(), [] as Array[String], "three players get a hero each")


# --- per-player judging -----------------------------------------------------------------------

func test_a_press_answers_only_its_players_heroes() -> void:
	var engine := _party_attack_engine()
	var prompts: Array = engine.sequence.prompts
	var judges := _judges(prompts, {0: 0, 1: 1, 2: 0})
	assert_eq(judges.players(), [0, 1] as Array[int])
	assert_eq(judges.player_of_prompt(1), 1)
	var report := judges.press(1, PARRY, 900000)
	assert_eq(int(report.result), SUCCESS)
	assert_eq(report.prompts, [1] as Array[int], "P2's parry defends only P2's hero")
	var ready := judges.pop_ready()
	assert_eq(ready.size(), 1, "P2's result is released at once, ahead of P1's open prompts")
	assert_eq(int(ready[0].prompt), 1)


func test_lockout_is_per_player() -> void:
	var engine := _party_attack_engine()
	var judges := _judges(engine.sequence.prompts, {0: 0, 1: 1, 2: 0})
	assert_eq(int(judges.press(0, PARRY, 300000).result), WHIFF, "P1 presses far too early")
	assert_true(judges.is_locked_out(0, 350000))
	assert_false(judges.is_locked_out(1, 350000), "P2 is not locked by P1's whiff")
	assert_eq(int(judges.press(0, PARRY, 350000).result), DefenseJudge.Result.LOCKED, "P1 presses again while locked")
	assert_eq(int(judges.press(1, PARRY, 900000).result), SUCCESS, "P2 defends normally")


func test_a_player_with_no_prompt_is_ignored() -> void:
	var engine := _party_attack_engine()
	var judges := _judges(engine.sequence.prompts, {0: 0, 1: 0, 2: 0})
	var report := judges.press(2, PARRY, 900000)
	assert_eq(int(report.result), DONE, "P3 has no hero in this attack")
	assert_false(judges.is_locked_out(2, 900000))
	assert_eq(judges.pop_ready().size(), 0)


func test_solo_judges_like_one_judge() -> void:
	var engine := _party_attack_engine()
	var judges := _judges(engine.sequence.prompts, {})
	assert_eq(judges.players(), [0] as Array[int])
	var report := judges.press(0, PARRY, 900000)
	assert_eq(report.prompts, [0, 1, 2] as Array[int], "one press answers every hero")


func test_engine_accepts_per_player_results_in_release_order() -> void:
	var engine := _party_attack_engine()
	var judges := _judges(engine.sequence.prompts, {0: 0, 1: 1, 2: 2})
	# P3 parries hit 0, then everyone jumps hit 1; P1 and P2 miss hit 0.
	judges.press(2, PARRY, 900000)
	var events := _submit_ready(engine, judges)
	assert_eq(Fx.of_type(events, "command_rejected").size(), 0, "P3's early result is accepted")
	for player: int in 3:
		judges.press(player, JUMP, 1500000)
	judges.advance(3000000)
	events = _submit_ready(engine, judges)
	assert_eq(Fx.of_type(events, "command_rejected").size(), 0, "the rest is accepted: %s" % [events])
	assert_false(Fx.first_of(events, "sequence_resolved").is_empty(), "every prompt resolved")
	assert_true(judges.is_complete())
	var outcomes: Dictionary = {}
	for ev: Dictionary in Fx.of_type(events, "prompt_resolved"):
		outcomes[int(ev.prompt)] = int(ev.outcome)
	assert_eq(outcomes.get(0), NONE, "P1 took hit 0")
	assert_eq(outcomes.get(1), NONE, "P2 took hit 0")
	assert_eq(outcomes.get(3), JUMP)


func test_void_and_resolve_all_reach_every_judge() -> void:
	var engine := _party_attack_engine()
	var judges := _judges(engine.sequence.prompts, {0: 0, 1: 1, 2: 2})
	judges.void_prompts([1, 4])
	assert_eq(int(judges.press(1, PARRY, 900000).result), DONE, "P2's hero is down: nothing to defend")
	judges.resolve_all_remaining()
	assert_eq(judges.pop_ready().size(), 6)
	assert_true(judges.is_complete(), "complete once everything is released")


# --- players screen ---------------------------------------------------------------------------

## A press of `action` on `device`, made from its own Input Map binding (KEYBOARD: its key).
func _press(action: StringName, device: int) -> InputEvent:
	for ev: InputEvent in InputMap.action_get_events(action):
		if device == KEYBOARD and ev is InputEventKey:
			var key := ev.duplicate() as InputEventKey
			key.pressed = true
			return key
		if device >= 0 and ev is InputEventJoypadButton:
			var button := ev.duplicate() as InputEventJoypadButton
			button.device = device
			button.pressed = true
			return button
	fail_test("no binding for %s on device %d" % [action, device])
	return InputEventKey.new()


func _lobby(previous: PlayerRoster = null) -> LobbyScreen:
	var lobby := LobbyScreen.new()
	lobby.setup(["Alder", "Brin", "Cass"] as Array[String], previous, KEYBOARD)
	add_child_autofree(lobby)
	return lobby


func test_lobby_join_hand_over_and_leave() -> void:
	var lobby := _lobby()
	assert_false(lobby.roster().is_coop(), "opens with P1 alone")
	lobby._unhandled_input(_press(&"menu_down", 0))
	assert_eq(lobby.roster().player_count(), 1, "a pad that has not joined cannot move the cursor")
	lobby._unhandled_input(_press(&"menu_confirm", 0))
	assert_eq(lobby.roster().devices, [KEYBOARD, 0] as Array[int], "pad 1 joins as P2")
	assert_eq(lobby.roster().owners, [0, 1, 0] as Array[int])
	# The cursor starts on Start: go up to Cass and hand her to P2.
	lobby._unhandled_input(_press(&"menu_up", 0))
	lobby._unhandled_input(_press(&"menu_right", 0))
	assert_eq(lobby.roster().owners, [0, 1, 1] as Array[int], "Cass goes to P2")
	lobby._unhandled_input(_press(&"menu_cancel", 0))
	assert_false(lobby.roster().is_coop(), "P2 leaves with Back")
	assert_eq(lobby.roster().owners, [0, 0, 0] as Array[int])


func test_lobby_start_and_back() -> void:
	var lobby := _lobby()
	watch_signals(lobby)
	lobby._unhandled_input(_press(&"menu_confirm", 1))
	lobby._unhandled_input(_press(&"menu_confirm", KEYBOARD))
	assert_signal_emitted(lobby, "started", "Start is selected first")
	var players := get_signal_parameters(lobby, "started")[0] as PlayerRoster
	assert_eq(players.devices, [KEYBOARD, 1] as Array[int])
	lobby._unhandled_input(_press(&"menu_cancel", KEYBOARD))
	assert_signal_emitted(lobby, "back", "P1's Back leaves the screen")


func test_lobby_keeps_the_last_split_for_the_same_p1() -> void:
	var previous := PlayerRoster.solo(3, KEYBOARD)
	previous.join(0)
	previous.move_hero(2, 1)
	assert_eq(_lobby(previous).roster().owners, [0, 1, 1] as Array[int])
	var other := PlayerRoster.solo(3, 3)
	other.join(0)
	assert_false(_lobby(other).roster().is_coop(), "someone else opened it: they start alone")


# --- in-run players (cards #304, #311) ------------------------------------------------------------

## A roster of `devices` (P1 first), the heroes dealt out as the players screen does.
func _roster_of(devices: Array[int]) -> PlayerRoster:
	var roster := PlayerRoster.solo(3, devices[0])
	for i: int in range(1, devices.size()):
		roster.join(devices[i])
	return roster


## The Players overlay over the pause menu, mid-run (DESIGN.md 9.3).
func _in_run(roster: PlayerRoster, p1: int) -> LobbyScreen:
	var lobby := LobbyScreen.new()
	lobby.setup_in_run(["Alder", "Brin", "Cass"] as Array[String], roster, p1)
	add_child_autofree(lobby)
	return lobby


## Every Label under `node` (its text), deep.
static func _texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for label: Node in node.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func test_in_run_never_resets_the_roster() -> void:
	var roster := _roster_of([KEYBOARD, 0] as Array[int])
	roster.move_hero(2, 1)
	var lobby := _in_run(roster, 0)
	assert_true(lobby.is_in_run())
	assert_eq(lobby.roster().devices, [KEYBOARD, 0] as Array[int], "co-op: P1's device stays")
	assert_eq(lobby.roster().owners, [0, 1, 1] as Array[int], "the run's split is kept, not dealt again")
	assert_eq(roster.devices, [KEYBOARD, 0] as Array[int], "the overlay works on a copy")


func test_in_run_solo_takes_p1s_real_device() -> void:
	var lobby := _in_run(PlayerRoster.solo(3, KEYBOARD), 0)
	assert_eq(lobby.roster().devices, [0] as Array[int], "solo: P1 is the pad they really play with")
	var any := _in_run(PlayerRoster.solo(3, KEYBOARD), PlayerRoster.ANY)
	assert_eq(any.roster().devices, [KEYBOARD] as Array[int], "no known device: the roster's stays")


func test_in_run_join_takes_brin_and_does_not_start() -> void:
	var lobby := _in_run(PlayerRoster.solo(3, KEYBOARD), KEYBOARD)
	watch_signals(lobby)
	lobby._unhandled_input(_press(&"menu_down", 0))
	assert_eq(lobby.roster().player_count(), 1, "a pad that has not joined can only join")
	lobby._unhandled_input(_press(&"menu_confirm", 0))
	assert_eq(lobby.roster().devices, [KEYBOARD, 0] as Array[int], "pad 1 joins as P2")
	assert_eq(lobby.roster().owners, [0, 1, 0] as Array[int], "P2 takes Brin, P1 keeps the others")
	assert_signal_not_emitted(lobby, "started", "joining never starts")
	assert_signal_not_emitted(lobby, "back")


func test_in_run_p2_back_leaves_and_p1_back_closes() -> void:
	var lobby := _in_run(_roster_of([KEYBOARD, 0, 1] as Array[int]), KEYBOARD)
	assert_eq(lobby.roster().owners, [0, 1, 2] as Array[int])
	watch_signals(lobby)
	lobby._unhandled_input(_press(&"menu_cancel", 0))
	assert_eq(lobby.roster().devices, [KEYBOARD, 1] as Array[int], "P2 leaves, P3 moves up")
	assert_eq(lobby.roster().owners, [0, 0, 1] as Array[int], "Brin goes to P1, Cass stays with her player")
	assert_signal_not_emitted(lobby, "back")
	lobby._unhandled_input(_press(&"menu_cancel", KEYBOARD))
	assert_signal_emitted(lobby, "back", "P1's Back closes the overlay")
	assert_eq(lobby.roster().devices, [KEYBOARD, 1] as Array[int], "P1 never leaves")


func test_in_run_keyboard_p2_esc_leaves_and_p1_esc_closes() -> void:
	var lobby := _in_run(_roster_of([0, KEYBOARD] as Array[int]), 0)
	watch_signals(lobby)
	lobby._unhandled_input(_press(&"pause", KEYBOARD))
	assert_eq(lobby.roster().devices, [0] as Array[int], "a keyboard P2's Esc leaves, like Backspace")
	assert_eq(lobby.roster().owners, [0, 0, 0] as Array[int])
	assert_signal_not_emitted(lobby, "back")
	var keys_p1 := _in_run(_roster_of([KEYBOARD, 0] as Array[int]), KEYBOARD)
	watch_signals(keys_p1)
	keys_p1._unhandled_input(_press(&"pause", KEYBOARD))
	assert_signal_emitted(keys_p1, "back", "a keyboard P1's Esc closes")
	assert_eq(keys_p1.roster().devices, [KEYBOARD, 0] as Array[int])


func test_in_run_confirm_plays_and_pause_closes() -> void:
	var lobby := _in_run(_roster_of([KEYBOARD, 0] as Array[int]), KEYBOARD)
	watch_signals(lobby)
	lobby._unhandled_input(_press(&"menu_confirm", KEYBOARD))
	assert_signal_emitted(lobby, "started", "Confirm plays")
	var fresh := _in_run(_roster_of([KEYBOARD, 0] as Array[int]), KEYBOARD)
	watch_signals(fresh)
	fresh._unhandled_input(_press(&"pause", 0))
	assert_signal_emitted(fresh, "back", "P2's Menu closes the overlay")
	assert_signal_not_emitted(fresh, "started")
	assert_eq(fresh.roster().player_count(), 2, "Pause is not a leave")


func test_in_run_has_no_oath_and_says_play() -> void:
	var lobby := _in_run(PlayerRoster.solo(3, KEYBOARD), KEYBOARD)
	assert_null(lobby._picker, "no Oath picker in a run")
	assert_eq(lobby._start_label.text, "Play")
	assert_eq(LobbyScreen.hints_in_run(), [[&"@updown", "Choose"], [&"@leftright", "Change"],
			[&"menu_confirm", "Play"], [&"menu_cancel", "Back"]])
	assert_eq(_lobby()._start_label.text, "Start", "the players screen before a run keeps Start")


func test_three_players_trade_heroes() -> void:
	var lobby := _in_run(_roster_of([KEYBOARD, 0, 1] as Array[int]), KEYBOARD)
	# The cursor starts on Play: go up to Alder.
	for i: int in 3:
		lobby._unhandled_input(_press(&"menu_up", KEYBOARD))
	assert_true(lobby.is_lit(0), "on Alder")
	lobby._unhandled_input(_press(&"menu_right", KEYBOARD))
	assert_eq(lobby.roster().owners, [1, 0, 2] as Array[int], "P1 and P2 trade their only heroes")


func test_pre_run_keeps_its_left_right() -> void:
	var lobby := _lobby(_roster_of([KEYBOARD, 0] as Array[int]))
	assert_false(lobby.is_in_run())
	for i: int in 2:
		lobby._unhandled_input(_press(&"menu_up", KEYBOARD))
	assert_true(lobby.is_lit(1), "on Brin")
	lobby._unhandled_input(_press(&"menu_right", KEYBOARD))
	assert_eq(lobby.roster().owners, [0, 1, 0] as Array[int], "before a run an only hero cannot move (9.1)")


func test_in_run_shows_a_leave_chip_for_p2() -> void:
	var lobby := _in_run(_roster_of([KEYBOARD, 0] as Array[int]), KEYBOARD)
	assert_true(_texts(lobby).has("leave"), "P2's own Back button and leave")
	var solo := _in_run(PlayerRoster.solo(3, KEYBOARD), KEYBOARD)
	assert_false(_texts(solo).has("leave"), "P1 never shows it")
	assert_false(_texts(_lobby(_roster_of([KEYBOARD, 0] as Array[int]))).has("leave"),
			"not on the players screen before a run")


func test_in_run_overlay_is_modal() -> void:
	# A pushed press must not leave the button hints on the pad for later tests.
	var pad_before := ButtonPrompts._pad
	var probe := InputProbe.new()
	add_child_autofree(probe)
	get_viewport().push_input(_press(&"menu_down", 1))
	assert_eq(probe.count, 1, "control: with nothing over it the probe sees the press")
	var lobby := _in_run(PlayerRoster.solo(3, KEYBOARD), KEYBOARD)
	get_viewport().push_input(_press(&"menu_down", 1))
	assert_eq(probe.count, 1, "an unjoined pad's press stops at the overlay")
	get_viewport().push_input(_press(&"menu_down", KEYBOARD))
	assert_eq(probe.count, 1, "so does P1's")
	assert_eq(lobby.roster().player_count(), 1)
	ButtonPrompts._pad = pad_before


func test_closing_with_no_change_is_the_same_roster() -> void:
	var original := _roster_of([KEYBOARD, 0] as Array[int])
	var lobby := _in_run(original, KEYBOARD)
	watch_signals(lobby)
	lobby._unhandled_input(_press(&"menu_down", KEYBOARD))
	lobby._unhandled_input(_press(&"pause", KEYBOARD))
	assert_signal_emitted(lobby, "back")
	assert_true(lobby.roster().same_as(original), "a look and close changes nothing")


## Counts the presses that reach it (an overlay over it should leave it none).
class InputProbe:
	extends Node

	var count: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_pressed():
			count += 1


# --- a pad drops (card #181) --------------------------------------------------------------------

func _pair() -> PlayerRoster:
	var roster := PlayerRoster.solo(3, 0)
	roster.join(1)
	return roster


func test_missing_players_sees_a_pad_that_is_gone() -> void:
	var roster := _pair()
	assert_eq(roster.missing_players([0, 1] as Array[int]), [] as Array[int])
	assert_eq(roster.missing_players([0] as Array[int]), [1] as Array[int])
	assert_eq(roster.missing_players([] as Array[int]), [0, 1] as Array[int])
	var with_keys := PlayerRoster.solo(3, KEYBOARD)
	with_keys.join(2)
	assert_eq(with_keys.missing_players([] as Array[int]), [1] as Array[int], "the keyboard never goes missing")


func test_replace_device_takes_over_a_seat() -> void:
	var roster := _pair()
	assert_true(roster.replace_device(1, 5))
	assert_eq(roster.devices, [0, 5] as Array[int])
	assert_eq(roster.player_of_device(5), 1)
	assert_true(roster.may_control(5, 1), "the new pad controls P2's hero")
	assert_false(roster.may_control(1, 1), "the old id no longer does")
	assert_false(roster.replace_device(1, 0), "a device already in the roster is refused")
	assert_false(roster.replace_device(4, 7), "no such player")
	assert_false(roster.replace_device(0, PlayerRoster.ANY))


func test_drop_missing_before_a_run() -> void:
	var roster := _pair()
	assert_eq(roster.drop_missing([0, 1] as Array[int]), 0)
	assert_eq(roster.drop_missing([0] as Array[int]), 1)
	assert_eq(roster.devices, [0] as Array[int])
	assert_eq(roster.owners, [0, 0, 0] as Array[int], "the dropped player's heroes are dealt out again")
	assert_true(roster.validate().is_empty())
	var all_gone := _pair()
	all_gone.drop_missing([] as Array[int])
	assert_eq(all_gone.devices, [KEYBOARD] as Array[int], "P1 falls back to the keyboard")
	assert_true(all_gone.validate().is_empty())


func test_stick_diagonal_is_not_snapped_to_an_axis() -> void:
	# A push at about 25 degrees: the old per-axis deadzone zeroed y.
	var v := DeviceInput.radial_deadzone(Vector2(0.9, 0.42), 0.2)
	assert_gt(v.x, 0.0)
	assert_gt(v.y, 0.0, "the vertical part survives")
	assert_almost_eq(v.angle(), Vector2(0.9, 0.42).angle(), 0.001, "direction is kept")
	assert_eq(DeviceInput.radial_deadzone(Vector2(0.15, 0.1), 0.2), Vector2.ZERO, "inside the deadzone")
	assert_almost_eq(DeviceInput.radial_deadzone(Vector2(1.0, 0.0), 0.2).length(), 1.0, 0.001)
	assert_lt(DeviceInput.radial_deadzone(Vector2(0.3, 0.0), 0.2).length(), 0.3, "rises from zero at the edge")
