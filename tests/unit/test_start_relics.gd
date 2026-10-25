extends GutTest
## The Relic book and the starting Relics (DESIGN.md 8.24, card #328): the main menu's Relics page
## as the book (found Relics first, the rest "???" with where Relics come from), each hero taking a
## starting Relic from the book before a run (RunState: take, skip, never banked, saved), the pick
## screen (hero by hero, one Relic per hero, the bot's picks, a friend's picks on their way to the
## host, local co-op pads) and the host's check of a friend's pick. Uses the shipped run and tuning;
## never touches the player's real files.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const RUN_PATH := "res://data/runs/rotten_road.tres"
const MAIN_PATH := "res://scenes/main.gd"
const PEER_A: int = 1001
const PEER_B: int = 2002

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func _run(collection: RelicCollection = null, oath: int = 0) -> RunState:
	return RunState.begin(_data, Fx.run_tuning(_tuning), 7, oath, collection)


func _relic(id: String) -> GearData:
	for item: GearData in _data.gear:
		if item != null and item.id == id:
			return item
	fail_test("the shipped run has the Relic %s" % id)
	return GearData.new()


func _book(ids: Array) -> RelicCollection:
	var c := RelicCollection.new()
	c.merge(ids)
	return c


func _relics() -> Array[GearData]:
	var list: Array[GearData] = []
	for item: GearData in _data.gear:
		if item != null:
			list.append(item)
	return list


func _screen(run: RunState, book: RelicCollection, heroes: Array[int] = [0, 1, 2]) -> StartRelicsScreen:
	var screen := StartRelicsScreen.new()
	add_child_autofree(screen)
	screen.setup_pick(run, book, heroes)
	return screen


func _texts(chips: Array[Dictionary]) -> Array:
	return chips.map(func(chip: Dictionary) -> String: return String(chip.get("text", "")))


## The words of a hint bar's chips ([action, word] pairs).
func _words(hints: Array) -> Array:
	return hints.map(func(hint: Array) -> String: return String(hint[1]))


# --- the book -------------------------------------------------------------------------------------

func test_the_book_shows_every_relic_found_ones_first() -> void:
	var screen := RelicsScreen.new()
	add_child_autofree(screen)
	screen.setup(_book(["whetstone", "iron_charm"]), _data.gear)
	var all := _relics()
	assert_eq(screen.found_text(), "Found 2 of %d" % all.size())
	assert_eq(screen.listed().size(), all.size(), "every Relic of the run is in the book")
	assert_eq(screen.listed().slice(0, 2), [_relic("iron_charm"), _relic("whetstone")],
			"the found ones first, by name")
	for item: GearData in screen.listed().slice(2):
		assert_false(["iron_charm", "whetstone"].has(item.id), "%s: not found yet, after them" % item.id)
	assert_false(screen.call("_confirm", _relic("iron_charm")), "the book only shows: no bag to fill")
	assert_true(screen.call("_card_dim", screen.listed()[2]), "a Relic not found yet is dim")
	assert_eq(_words(screen.hints()), ["Move", "", "Sort", "Back"], "LT / RT sort (card #336)")
	assert_eq(screen.hints()[1][0], ControlBindings.SWITCH_PREV)
	assert_eq(screen.hints()[2][0], ControlBindings.SWITCH_NEXT)


func test_a_relic_not_found_yet_says_where_relics_come_from() -> void:
	var drum := _relic("war_drum")
	var unknown := RelicsScreen.focus_chips(drum, false)
	assert_eq(String(unknown[0].text), RelicsScreen.NOT_FOUND)
	for source: Dictionary in RelicsScreen.SOURCES:
		assert_true(_texts(unknown).has(String(source.text)), "names %s" % source.text)
	assert_false(_texts(unknown).has(drum.display_name), "its name stays hidden")
	var known := RelicsScreen.focus_chips(drum, true)
	assert_false(_texts(known).has(RelicsScreen.NOT_FOUND))
	for chip: Dictionary in unknown + known:
		assert_lt(String(chip.text).split(" ").size(), 6, "a few words, never a sentence: %s" % chip.text)
	var empty := RelicsScreen.new()
	add_child_autofree(empty)
	empty.setup(RelicCollection.new(), _data.gear)
	assert_eq(empty.found_text(), "Found 0 of %d" % _relics().size(), "a first run's empty book")


# --- the run's starting Relics -------------------------------------------------------------------

func test_each_hero_takes_one_starting_relic_from_the_book() -> void:
	var book := _book(["iron_charm", "whetstone", "war_drum"])
	var run := _run(book)
	assert_eq(run.start_left, [1, 1, 1] as Array[int])
	assert_true(run.start_pending())
	assert_eq(run.start_choices(book).size(), 3)
	var charm := _relic("iron_charm")
	assert_false(run.take_start_relic(0, charm).is_empty())
	assert_eq(run.holder_of(charm), 0)
	assert_false(run.start_open(0), "one each")
	assert_true(run.take_start_relic(0, _relic("whetstone")).is_empty(), "no second one")
	assert_true(run.take_start_relic(1, charm).is_empty(), "a Relic taken for one hero is gone for the others")
	assert_false(run.start_choices(book).has(charm))
	assert_true(run.take_start_relic(1, null).is_empty())
	assert_true(run.skip_start_relic(1))
	assert_false(run.skip_start_relic(1), "skipped already")
	assert_eq(run.start_open_of([0, 1, 2] as Array[int]), [2] as Array[int])
	assert_eq(run.skip_start_relics([0, 1, 2] as Array[int]), 1)
	assert_false(run.start_pending())
	assert_eq(run.start_relics, {"iron_charm": 1})


func test_the_choices_are_the_book_in_the_runs_order() -> void:
	var book := _book(["war_drum", "iron_charm", "whetstone", "not_a_relic"])
	var run := _run(book)
	var expected: Array[GearData] = []
	for item: GearData in _data.gear:
		if item != null and ["war_drum", "iron_charm", "whetstone"].has(item.id):
			expected.append(item)
	assert_eq(run.start_choices(book), expected, "found in the book, known to the run, in the run's order")
	assert_true(run.start_choices(RelicCollection.new()).is_empty(), "a first run: nothing to take")
	assert_true(run.start_choices(null).is_empty())


func test_starting_relics_are_never_banked_or_new() -> void:
	var book := _book(["iron_charm"])
	var run := _run(book)
	run.take_start_relic(0, _relic("iron_charm"))
	run.end_start_picks()
	assert_true(run.relic_ids_since({}).is_empty(), "taken from the book: nothing to bank")
	assert_false(run.relic_gain_line_since({}).contains(_relic("iron_charm").display_name), "and no find line")
	assert_true(RunEndScreen.kept_relics(run, {}).is_empty(), "nor a kept Relic on the end screen")
	run.give_relic(_relic("whetstone"), 1)
	assert_eq(run.relic_ids_since({}), ["whetstone"], "a Relic found in the run is banked")
	assert_eq(run.found_relics(), [_relic("whetstone")] as Array[GearData])
	assert_eq(run.owned_relics().size(), 2, "both play in the run")


func test_the_empty_hand_and_the_tuning_set_how_many() -> void:
	var book := _book(["iron_charm", "whetstone"])
	assert_eq(_run(book).start_relic_count(), _tuning.start_relics_per_hero)
	var none := _run(book, 11)
	assert_eq(none.start_relic_count(), 0, "Oath 11: none")
	assert_eq(none.start_left, [0, 0, 0] as Array[int])
	var tuning := Fx.run_tuning(_tuning)
	tuning.start_relics_per_hero = 2
	var two := RunState.begin(_data, tuning, 7, 0, book)
	assert_false(two.take_start_relic(0, _relic("iron_charm")).is_empty())
	assert_true(two.start_open(0), "a second one to take")
	assert_false(two.take_start_relic(0, _relic("whetstone")).is_empty())
	assert_false(two.start_open(0))
	assert_eq(two.relics_of(0).size(), 2)


func test_the_pick_step_survives_a_save_and_refuses_junk() -> void:
	var book := _book(["iron_charm", "whetstone"])
	var run := _run(book)
	run.take_start_relic(1, _relic("whetstone"))
	var d := run.to_dict()
	var copy := RunState.from_dict(_data, run.tuning, d)
	assert_not_null(copy)
	assert_eq(copy.start_left, [1, 0, 1] as Array[int])
	assert_eq(copy.start_relics, {"whetstone": 1})
	assert_eq(copy.holder_of(_relic("whetstone")), 1)
	var old := d.duplicate(true)
	old.erase("start_left")
	old.erase("start_relics")
	var older := RunState.from_dict(_data, run.tuning, old)
	assert_not_null(older, "a save from before #328 loads")
	assert_false(older.start_pending(), "with no pick waiting")
	for bad: Array in [["start_left", [1, 1]], ["start_left", [1, -1, 1]], ["start_left", "x"],
			["start_relics", {"rotten_crown_not_in_run": 1}], ["start_relics", [1]]]:
		var junk := d.duplicate(true)
		junk[bad[0]] = bad[1]
		assert_null(RunState.from_dict(_data, run.tuning, junk), "%s = %s is refused" % bad)


# --- the pick screen ------------------------------------------------------------------------------

func test_the_screen_goes_hero_by_hero_one_relic_each() -> void:
	var book := _book(["iron_charm", "whetstone", "war_drum"])
	var run := _run(book)
	var screen := _screen(run, book)
	watch_signals(screen)
	assert_eq(screen.chooser(), 0)
	assert_eq(screen.found_text(), run.data.party[0].display_name, "solo: the hero choosing, no tag")
	assert_eq(screen.listed().size(), 3, "only the book's found Relics, no \"???\"")
	assert_true(screen.take(_relic("iron_charm")))
	assert_signal_emitted_with_parameters(screen, "picked", [0, _relic("iron_charm")])
	assert_eq(run.holder_of(_relic("iron_charm")), 0)
	assert_eq(screen.chooser(), 1)
	assert_true(screen.call("_card_dim", _relic("iron_charm")), "taken: dim")
	assert_eq(screen.call("_card_holder", _relic("iron_charm")), 0, "with the face of the hero who has it")
	assert_false(screen.take(_relic("iron_charm")), "taken for another hero")
	assert_eq(screen.chooser(), 1, "still choosing")
	assert_false(screen.take(_relic("rotten_crown")), "not in the book")
	assert_true(screen.skip())
	assert_signal_emitted_with_parameters(screen, "picked", [1, null])
	assert_signal_not_emitted(screen, "finished")
	assert_eq(_words(screen.hints()), ["Move", "Take", StartRelicsScreen.SKIPPED, "Back", "", "Sort"])
	assert_has(screen.hints(), [&"item_move", StartRelicsScreen.SKIPPED], "Skip is X / R, its own button (card #334)")
	assert_true(screen.take(_relic("war_drum")))
	assert_signal_emit_count(screen, "finished", 1)
	assert_true(screen.is_done())
	assert_eq(screen.found_text(), StartRelicsScreen.WAITING)
	assert_eq(screen.hints(), [[&"menu_cancel", "Back"]], "done: only Back, while the step is open")
	screen.open = false
	assert_true(screen.hints().is_empty())
	assert_false(screen.skip(), "nobody left to choose")
	assert_false(run.start_pending())
	assert_eq(run.relics_of(1).size(), 0, "the skipped hero has none")


func test_the_bot_takes_the_best_free_relic_for_each_hero() -> void:
	var ids: Array = []
	for item: GearData in _relics().slice(0, 6):
		ids.append(item.id)
	var book := _book(ids)
	var run := _run(book)
	var choices: Array[GearData] = []
	for item: GearData in run.start_choices(book):
		if GearBot.score(item) >= 0:
			choices.append(item)
	var first := choices[GearBot.pick(choices)]
	var screen := _screen(run, book)
	screen.bot_pick()
	assert_true(screen.is_done())
	assert_eq(run.holder_of(first), 0, "the first hero gets the best by GearBot's score")
	var seen := {}
	for slot: int in run.party_size():
		assert_eq(run.relics_of(slot).size(), 1, "every hero takes one")
		seen[run.relics_of(slot)[0].id] = true
	assert_eq(seen.size(), 3, "never the same Relic twice")
	var empty_run := _run()
	var empty := _screen(empty_run, RelicCollection.new())
	empty.bot_pick()
	assert_true(empty.is_done(), "an empty book: every hero skips")
	assert_true(empty_run.relics.is_empty())


func test_a_friends_pick_waits_for_the_host() -> void:
	var book := _book(["iron_charm", "whetstone", "war_drum"])
	var run := _run(book)
	var screen := _screen(run, book, [1, 2] as Array[int])
	screen.remote = true
	watch_signals(screen)
	assert_eq(screen.chooser(), 1, "only this machine's heroes")
	assert_true(screen.take(_relic("iron_charm")))
	assert_eq(run.holder_of(_relic("iron_charm")), -1, "a friend's screen never changes the run")
	assert_true(screen.is_sending())
	assert_eq(screen.call("_row_state", 1), StartRelicsScreen.SENT)
	assert_eq(screen.chooser(), 2, "the next hero chooses meanwhile")
	screen.bot_pick()
	assert_signal_emit_count(screen, "finished", 1)
	assert_ne(screen._sent.get(2), "iron_charm", "the bot never sends one already on its way")
	# The host's state comes: hero 1's pick went in, and someone took hero 2's first.
	run.take_start_relic(1, _relic("iron_charm"))
	var other := run.relic_by_id(String(screen._sent[2]))
	run.take_start_relic(0, other)
	screen.refresh()
	assert_false(screen._sent.has(1), "hero 1's pick is in")
	assert_eq(screen.chooser(), 2, "hero 2 chooses again")
	assert_eq(screen._warning, StartRelicsScreen.TAKEN)
	assert_true(screen.take(_relic("war_drum")) or screen.take(_relic("whetstone")))
	var again := String(screen._sent[2])
	screen.refused(2, other.id)
	assert_eq(screen._sent.get(2), again, "the refusal of the older pick changes nothing")
	screen.refused(2, again)
	assert_eq(screen.chooser(), 2, "a refused pick opens the hero again")
	assert_true(screen.skip())
	run.skip_start_relic(2)
	screen.refresh()
	assert_false(screen.is_sending())
	assert_true(screen.is_done())


func test_the_bot_picks_again_when_its_pick_comes_back() -> void:
	var book := _book(["iron_charm", "whetstone", "war_drum"])
	var run := _run(book)
	var screen := _screen(run, book, [1] as Array[int])
	screen.remote = true
	screen.autopick = true
	screen.bot_pick()
	var first := String(screen._sent[1])
	run.take_start_relic(0, run.relic_by_id(first))
	screen.refresh()
	await wait_process_frames(2)
	assert_true(screen._sent.has(1), "another hero got it first: the bot chose again")
	assert_ne(String(screen._sent.get(1, first)), first)
	var second := String(screen._sent[1])
	screen.refused(1, first)
	assert_eq(screen._sent.get(1), second, "the first pick's refusal leaves the new one")
	screen.refused(1, second)
	await wait_process_frames(2)
	assert_true(screen._sent.has(1), "refused: the bot chooses once more")
	assert_ne(String(screen._sent[1]), second)


func test_local_coop_only_the_heroes_player_picks() -> void:
	var book := _book(["iron_charm", "whetstone"])
	var run := _run(book)
	var players := PlayerRoster.new()
	players.devices.assign([PlayerRoster.KEYBOARD, 0])
	players.owners.assign([0, 1, 1])
	var screen := _screen(run, book)
	screen.players = players
	screen.check_pads = true
	screen.connected_pads = func() -> Array[int]: return [0] as Array[int]
	screen.focus(_relic("iron_charm"))
	screen._device = 0
	assert_false(screen.call("_confirm", _relic("iron_charm")), "P2's pad cannot pick for P1's hero")
	assert_eq(screen._warning, "P1", "the tag of the player whose turn it is")
	assert_true(screen.found_text().begins_with("P1 "), "the header names the player too")
	screen._device = PlayerRoster.KEYBOARD
	assert_true(screen.call("_confirm", _relic("iron_charm")))
	assert_eq(screen.chooser(), 1)
	screen.call("_alt")
	assert_eq(screen.chooser(), 1, "P1 cannot skip for P2's hero")
	screen._device = 0
	screen.call("_alt")
	assert_eq(screen.chooser(), 2, "P2 skips their own")
	# Back (card #334): only the player whose hero it was takes a pick back.
	screen._device = PlayerRoster.KEYBOARD
	screen.call("_back")
	assert_eq(screen.chooser(), 2, "P1 cannot take P2's Skip back")
	assert_eq(screen._warning, "P2")
	screen._device = 0
	screen.call("_back")
	assert_eq(screen.chooser(), 1, "P2 takes their own Skip back")
	screen.call("_back")
	assert_eq(run.holder_of(_relic("iron_charm")), 0, "P2 cannot take P1's pick back")
	screen._device = PlayerRoster.KEYBOARD
	screen.call("_back")
	assert_eq(screen.chooser(), 0, "P1 takes theirs back")
	assert_eq(run.holder_of(_relic("iron_charm")), -1)


func test_local_coop_a_lost_pad_never_holds_the_step() -> void:
	var book := _book(["iron_charm", "whetstone"])
	var run := _run(book)
	var players := PlayerRoster.new()
	players.devices.assign([PlayerRoster.KEYBOARD, 0])
	players.owners.assign([1, 0, 0])
	var screen := _screen(run, book)
	screen.players = players
	screen.check_pads = true
	var plugged: Array[int] = []
	screen.connected_pads = func() -> Array[int]: return plugged
	screen.focus(_relic("iron_charm"))
	screen._device = PlayerRoster.KEYBOARD
	assert_eq(screen.chooser(), 0, "P2's hero chooses first")
	assert_true(screen.call("_confirm", _relic("iron_charm")), "P2's pad is gone: the keyboard picks for them")
	assert_eq(run.holder_of(_relic("iron_charm")), 0)
	assert_true(StartRelicsScreen.may_pick(players, PlayerRoster.KEYBOARD, 0, plugged))
	assert_false(StartRelicsScreen.may_pick(players, PlayerRoster.KEYBOARD, 0, [0] as Array[int]),
			"with the pad back, only it picks for P2's heroes")
	assert_true(StartRelicsScreen.may_pick(players, 0, 0, [0] as Array[int]))
	assert_false(StartRelicsScreen.may_pick(players, 0, 1, plugged), "P1's keyboard never goes missing")
	assert_true(StartRelicsScreen.may_pick(null, 0, 0, plugged), "solo: anyone")


## Card #334: Back takes the last pick back (a Relic or a Skip) and that hero chooses again; on the
## first hero it does nothing. Skip is its own button.
func test_back_takes_the_last_pick_back_and_never_skips() -> void:
	var book := _book(["iron_charm", "whetstone", "war_drum"])
	var run := _run(book)
	var screen := _screen(run, book)
	watch_signals(screen)
	assert_false(screen.can_go_back(), "the first hero: nothing to take back")
	screen.call("_back")
	assert_eq(screen.chooser(), 0, "Back on the first hero does nothing")
	assert_true(run.start_open(0), "and never skips")
	assert_false(_words(screen.hints()).has("Back"), "so no Back hint yet")
	var charm := _relic("iron_charm")
	run.hp[1] -= 5
	var wounded := run.hp[1]
	assert_true(screen.take(charm))
	assert_true(screen.skip())
	assert_eq(screen.chooser(), 2)
	assert_true(screen.back())
	assert_signal_emitted_with_parameters(screen, "withdrawn", [1, ""])
	assert_eq(screen.chooser(), 1, "the Skip is taken back: hero 1 chooses again")
	assert_true(run.start_open(1))
	screen.call("_back")
	assert_signal_emitted_with_parameters(screen, "withdrawn", [0, "iron_charm"])
	assert_eq(screen.chooser(), 0, "back to the first hero")
	assert_eq(run.holder_of(charm), -1, "the Relic is free again")
	assert_false(run.relics.has("iron_charm"))
	assert_false(run.start_relics.has("iron_charm"))
	assert_eq(run.hp[0], run.max_hp(0), "the hero is still full at the lower max HP")
	assert_eq(run.hp[1], wounded, "the others keep their wounds")
	assert_false(screen.call("_card_dim", charm), "lit again for everyone")
	assert_false(screen.back(), "nothing more to take back")
	screen.call("_alt")
	assert_eq(screen.chooser(), 1, "X / R skips")
	assert_eq(run.relics_of(0).size(), 0)


func test_undo_start_relic_takes_back_only_a_starting_pick() -> void:
	var book := _book(["iron_charm", "whetstone"])
	var run := _run(book)
	var charm := _relic("iron_charm")
	assert_false(run.undo_start_relic(0, ""), "nothing skipped yet")
	assert_false(run.undo_start_relic(0, "iron_charm"), "nothing taken yet")
	run.take_start_relic(0, charm)
	assert_false(run.undo_start_relic(1, "iron_charm"), "another hero has it")
	assert_false(run.undo_start_relic(7, "iron_charm"), "no such hero")
	assert_false(run.undo_start_relic(0, "not_a_relic"))
	run.give_relic(_relic("whetstone"), 1)
	assert_false(run.undo_start_relic(1, "whetstone"), "found in the run, not a starting pick")
	assert_true(run.undo_start_relic(0, "iron_charm"))
	assert_eq(run.start_left[0], run.start_relic_count())
	var tuning := Fx.run_tuning(_tuning)
	tuning.start_relics_per_hero = 2
	var two := RunState.begin(_data, tuning, 7, 0, book)
	two.take_start_relic(0, charm)
	assert_true(two.skip_start_relic(0), "one taken, the second skipped")
	assert_true(two.undo_start_relic(0, ""))
	assert_eq(two.start_left[0], 1, "the Skip back: one more to take")
	assert_eq(two.holder_of(charm), 0, "the first stays")


func test_a_friends_back_asks_the_host_and_waits_for_it() -> void:
	var book := _book(["iron_charm", "whetstone", "war_drum"])
	var run := _run(book)
	var screen := _screen(run, book, [1, 2] as Array[int])
	screen.remote = true
	watch_signals(screen)
	var charm := _relic("iron_charm")
	assert_true(screen.take(charm))
	assert_false(screen.back(), "a pick still on its way to the host cannot be taken back")
	run.take_start_relic(1, charm)
	screen.refresh()
	assert_true(screen.back())
	assert_signal_emitted_with_parameters(screen, "withdrawn", [1, "iron_charm"])
	assert_eq(run.holder_of(charm), 1, "a friend's screen never changes the run")
	assert_eq(screen.chooser(), -1, "nobody chooses while the host answers")
	assert_false(screen.is_done())
	assert_eq(screen.call("_row_state", 1), StartRelicsScreen.SENT)
	screen.withdraw_answered(1, "iron_charm", false)
	assert_eq(screen._warning, StartRelicsScreen.TAKEN, "refused: the pick stands")
	assert_eq(screen.chooser(), 2)
	assert_true(screen.can_go_back(), "it can be asked again")
	assert_true(screen.back())
	# The host took it back: its state reopens hero 1, then its answer comes.
	run.undo_start_relic(1, "iron_charm")
	screen.refresh()
	assert_eq(screen.chooser(), 1, "hero 1 chooses again")
	screen.withdraw_answered(1, "iron_charm", true)
	assert_eq(screen.chooser(), 1, "the late answer changes nothing")
	assert_false(screen.can_go_back())


func test_the_host_takes_a_friends_pick_back_only_while_the_step_is_open() -> void:
	var main_script := load(MAIN_PATH) as GDScript
	var pickers := {PEER_A: [1], PEER_B: [2]}
	assert_true(main_script.call("_start_back_allowed", pickers, PEER_A, 1, true))
	assert_false(main_script.call("_start_back_allowed", pickers, PEER_A, 2, true), "another player's hero")
	assert_false(main_script.call("_start_back_allowed", pickers, PEER_A, 0, true), "the host's own hero")
	assert_false(main_script.call("_start_back_allowed", pickers, 3003, 1, true), "a peer not on the step")
	assert_false(main_script.call("_start_back_allowed", pickers, PEER_A, 1, false), "the run went on")
	assert_false(main_script.call("_start_back_allowed", {}, PEER_A, 1, true), "the wait ran out")


func test_a_starting_relic_raises_max_hp_full_and_pause_opens_over_the_step() -> void:
	var book := _book(["iron_charm", "gravebound_ring"])
	var run := _run(book)
	var before := run.max_hp(0)
	assert_false(run.take_start_relic(0, _relic("iron_charm")).is_empty())
	assert_gt(run.max_hp(0), before, "the Iron Charm raises max HP")
	assert_eq(run.hp[0], run.max_hp(0), "the hero starts the run full, not wounded")
	assert_false(run.take_start_relic(1, _relic("gravebound_ring")).is_empty())
	assert_eq(run.hp[1], run.max_hp(1), "a lower max HP cuts it")
	assert_eq(run.hp[2], run.max_hp(2), "the others are untouched")
	# Esc is Pause before it is Back: offline the pause menu opens over the step (Abandon, Players).
	var source := FileAccess.get_file_as_string(MAIN_PATH)
	assert_string_contains(source, "if _screen is MapScreen or _screen is StartRelicsScreen:")


func test_every_machine_logs_the_starting_relics_once() -> void:
	var main_script := load(MAIN_PATH) as GDScript
	assert_true(main_script.call("_logs_start_relics", true, false, "map"), "after the step")
	assert_true(main_script.call("_logs_start_relics", false, true, "map"), "the host skipped the step")
	assert_false(main_script.call("_logs_start_relics", false, true, "start_relics"), "the step itself")
	assert_false(main_script.call("_logs_start_relics", true, true, "menu"), "a game ended in the step")
	assert_false(main_script.call("_logs_start_relics", false, false, "map"), "logged already, or dropped in")


# --- online: the host's check ---------------------------------------------------------------------

func test_the_host_takes_a_pick_only_for_a_hero_that_player_owns() -> void:
	var main_script := load(MAIN_PATH) as GDScript
	var run := _run(_book(["iron_charm"]))
	var pickers := {PEER_A: [1], PEER_B: [2]}
	assert_true(main_script.call("_start_pick_allowed", pickers, PEER_A, 1, run))
	assert_false(main_script.call("_start_pick_allowed", pickers, PEER_A, 2, run), "another player's hero")
	assert_false(main_script.call("_start_pick_allowed", pickers, PEER_A, 0, run), "the host's own hero")
	assert_false(main_script.call("_start_pick_allowed", pickers, 3003, 1, run), "a peer not on the step")
	run.skip_start_relic(1)
	assert_false(main_script.call("_start_pick_allowed", pickers, PEER_A, 1, run), "done already")
	assert_false(main_script.call("_start_pick_allowed", pickers, PEER_B, 2, null))


func test_a_run_opens_with_the_pick_step() -> void:
	var source := FileAccess.get_file_as_string(MAIN_PATH)
	assert_string_contains(source, "\t_begin_start_relics()", "a new run picks first")
	assert_string_contains(source, "_fade_to(_begin_start_relics)", "a continued run picks first too")
	assert_string_contains(source, "_fade_to(_after_start_relics)", "then the pact or the map")
	assert_false(source.contains("_begin_start_relics(next"), "the step always goes on to the run")
	assert_string_contains(source, "_on_friend_start_relic(from_peer, payload)", "the host hears a friend's pick")
	assert_string_contains(source, "\"start_refused\"", "and can send it back")
	assert_gt(_tuning.start_relic_wait_ms, 0, "the host waits for friends only so long")
