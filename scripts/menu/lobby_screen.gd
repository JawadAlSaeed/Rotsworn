class_name LobbyScreen
extends CanvasLayer
## The players screen before a run or practice (DESIGN.md 9.1), and the Players overlay in a run
## (9.3, see below). The device that opened it is P1.
## Another keyboard or pad presses Confirm to join (up to three players) and Back to leave. The
## heroes are dealt out in turn (P1 gets the extra one); left/right on a hero hands it to another
## player, as long as every player keeps a hero. Confirm starts with this roster; Back (P1's Cancel)
## returns to the main menu and leaves the old roster alone.
##
## Phase 22 layout, top to bottom, all centred: the players line (each player's tag and device; the
## first open seat shows the buttons that can join right now, the pad's and the keyboard's Confirm),
## the heroes as big painted portraits side by side (cards #140, #141; the one the cursor is on gets
## a gold frame, a name plate under each says who plays it), then the Oath picker and the big Start
## button side by side. The footer: Choose, Change, Start, Back.
##
## A run's screen (not practice) has the Oath picker (DESIGN.md 8.15): left/right picks how hard the
## run is, from none up to the highest oath this machine unlocked; what the picked oath and those
## below it change is shown in the picker as icon chips (oath_chips). Online only the host picks;
## the clients see its pick.
##
## The cursor (a ListMenu whose rows are all drawn by this screen instead) stops on each hero card,
## the Oath picker and Start. Confirm starts from any of them. The mouse points at a card, the picker
## or Start to choose it; a click on a card's or the picker's left or right half steps it that way,
## a click on Start starts, a right click goes back.
##
## Online (DESIGN.md 9.2) one player is one machine. The host's screen shows the address friends
## type in; players join over the network (Main calls add_peer / remove_peer) and the host hands
## heroes out and starts. A client's screen only shows the roster and oath the host sends
## (set_roster, set_oath) and waits, with no Start; its Back leaves the game.
##
## In a run (setup_in_run, DESIGN.md 9.3, cards #304, #311) the same screen is the Players overlay
## over the pause menu: no Oath picker, Start reads Play, the roster is the run's own (never dealt
## out again). A newcomer takes one hero at once (the usual deal's, nobody else's change); a joined
## P2 / P3 leaves with their own Back (their heroes go to P1) and shows its button and "leave";
## left/right hands a hero on, and an only hero trades places. It is modal: a device that has not
## joined can only join, and no press reaches what is under it.
##
## The host's screen with a saved online run (card #313, `continue_line`) has a Continue button after
## Start, side by side: the save picture, "Continue" and where the run is ("Act 2, Stop 5"). The
## cursor starts on it; Confirm there continues the saved run (its own seats come back, the hero
## cards are for a new run), Confirm anywhere else starts a new one; the footer's Confirm word says
## which ("Continue" or "Start"). `saved_note` is a dim line under the address (a saved run kept from
## another version).

## Confirmed: play with `players` at oath `oath` (0: none; always 0 in practice).
signal started(players: PlayerRoster, oath: int)
## Online host, Confirm on Continue: carry on the saved online run (card #313); `players` are the ones
## on this screen now.
signal continued(players: PlayerRoster)
signal back
## Online host: the roster changed (to send to the clients).
signal roster_changed(players: PlayerRoster)
## Online host: the oath pick changed (to send to the clients).
signal oath_changed(oath: int)

const TITLE_SIZE: int = 64
const PLAYER_SIZE: int = 34
## The host's address line.
const NOTE_SIZE: int = 26
const PLAYERS_GAP: int = 56
const DEVICE_GLYPH_PX: float = 34.0
## Hero cards: the big portrait's top CARD_ROWS rows (the face and shoulders), CARD_SCALE times
## its pixels, in a frame CARD_BORDER wide; the name plate under it.
const CARD_SCALE: float = 2.0
## With an Oath picker the cards are smaller, to make room for it under them. Bigger text (the
## Text size setting) makes the cards smaller still, so the screen always fits.
const CARD_SCALE_OATH: float = 1.5
const CARD_ROWS: int = 240
const CARD_BORDER: int = 4
const CARD_GAP: int = 28
const PLATE_SIZE: int = 34
const CARD_FRAME := Color(0.36, 0.33, 0.3)
const CARD_DIM := Color(0.55, 0.55, 0.55)
## The Oath picker and the Start button under the cards: their widths, text sizes and the gap.
const PICKER_WIDTH: float = 960.0
const PICKER_SIZE: int = 36
const EFFECT_SIZE: int = 22
const START_WIDTH: float = 320.0
const START_SIZE: int = 52
const BUTTONS_GAP: int = 40
## The picker's line when no oath is picked.
const NO_CHANGE := "Normal road"
## The big button's word before a run, and in a run (the Players overlay).
const START_WORD := "Start"
const PLAY_WORD := "Play"
## The Continue button (card #313): its word, the line under it and its picture's size.
const CONTINUE_WORD := "Continue"
const CONTINUE_LINE_SIZE: int = 26
const CONTINUE_GLYPH_PX: int = 40

## The heroes' big portraits, in hero order (set before setup).
var hero_portraits: Array[String] = []
## The oath ladder (set before setup; empty: no Oath picker, as in practice), the highest oath this
## machine may pick, and the oath to start on.
var oaths: Array[OathData] = []
var oath_unlocked: int = 0
var start_oath: int = 0
## Online host (set before setup_online): where the saved online run is ("Act 2, Stop 5"); not
## empty adds the Continue button (card #313). `saved_note`: a dim line under the address ("" : none).
var continue_line: String = ""
var saved_note: String = ""

var _roster: PlayerRoster
var _hero_names: Array[String] = []
## The cursor: one hidden row per hero, the Oath picker (if any) and Start.
var _menu: ListMenu
## Per player seat: its line (tag, device or join buttons).
var _slots: Array[HBoxContainer] = []
## Per hero: its card (portrait and name plate), the card's frame and its name plate's owner tag.
var _card_boxes: Array[Control] = []
var _cards: Array[PanelContainer] = []
var _card_tags: Array[Label] = []
var _online: bool = false
var _is_host: bool = true
## The Players overlay in a run (setup_in_run).
var _in_run: bool = false
var _oath: int = 0
## The Oath picker: its frame, its "<  Oath 2  >" line and the effect chips under it.
var _picker: PanelContainer
var _picker_body: VBoxContainer
var _picker_title: Label
var _picker_chips: Control
## The Start button, its word and its Confirm chip.
var _start_button: PanelContainer
var _start_label: Label
var _start_chip: Control
## The Continue button (a saved online run, card #313; null: none), its word and its Confirm chip.
var _continue_button: PanelContainer
var _continue_label: Label
var _continue_chip: Control
## The footer's hints, and the word its Confirm shows now: with a Continue button it follows the
## cursor ("Continue" on it, "Start" elsewhere), so it never says the other one (card #313).
var _footer: HintBar
var _footer_word: String = START_WORD


## `previous` is the last roster (its hero split is kept when the same players come back);
## `first_device` is the device that opened the screen (P1).
func setup(hero_names: Array[String], previous: PlayerRoster, first_device: int) -> void:
	_hero_names = hero_names
	_roster = previous.copy() if previous != null and not previous.is_online() \
			and previous.hero_count() == hero_names.size() else PlayerRoster.solo(hero_names.size(), first_device)
	if _roster.device_of_player(0) != first_device:
		# Someone else opened it: they are P1 now, alone.
		_roster = PlayerRoster.solo(hero_names.size(), first_device)
	_oath = clampi(start_oath, 0, mini(oath_unlocked, oaths.size()))
	_build("Players", "", hints(false, true))


## The online players screen. `roster` is the host's (online) roster; `is_host` false makes this
## a waiting client's screen. `addresses` and `port` are shown to the host for friends to type.
func setup_online(hero_names: Array[String], roster: PlayerRoster, is_host: bool, addresses: Array[String], port: int) -> void:
	_hero_names = hero_names
	_roster = roster.copy()
	_online = true
	_is_host = is_host
	_oath = clampi(start_oath, 0, mini(oath_unlocked, oaths.size())) if is_host else 0
	if is_host:
		_build("Host Online", address_line(addresses, port), hints(true, true))
	else:
		_build("Online Players", "Waiting for the host", hints(true, false))


## The Players overlay over the pause menu, mid-run (cards #304, #311). `roster` is the local
## roster (copied, never reset); `p1_device` is the device P1 really plays with: while solo it
## becomes P1's device (every device worked so far), in co-op it changes nothing. No Oath picker;
## Start reads Play. Modal: a free device can only join (Confirm, join_midrun); P2/P3 leave with
## their Back (leave_midrun; Esc counts, it is also Pause); left/right trades heroes; Confirm plays
## (started); P1's Back or anyone's Pause closes (back). Both keep the changes: Main reads
## roster() either way.
func setup_in_run(hero_names: Array[String], roster: PlayerRoster, p1_device: int) -> void:
	_hero_names = hero_names
	_roster = roster.copy()
	_in_run = true
	oaths = [] as Array[OathData]
	if not _roster.is_coop() and p1_device != PlayerRoster.ANY:
		# replace_device refuses the device P1 already has.
		_roster.replace_device(0, p1_device)
	_build("Players", "", hints_in_run())


## The footer's button hints (phase 22: a word each). A local screen or the host: Choose, Change (a
## hero's player or the oath), Start, Back; joining is shown on the first open seat instead. A
## waiting online client can only leave. Pure.
## `confirm_word`: what Confirm does where the cursor is (the host's Continue, card #313).
static func hints(online: bool, is_host: bool, confirm_word: String = START_WORD) -> Array:
	if online and not is_host:
		return [[&"menu_cancel", "Leave"]]
	return [[&"@updown", "Choose"], [&"@leftright", "Change"], [&"menu_confirm", confirm_word], [&"menu_cancel", "Back"]]


## The in-run overlay's footer (DESIGN.md 9.3): Choose, Change, Play, Back. Pure.
static func hints_in_run() -> Array:
	return [[&"@updown", "Choose"], [&"@leftright", "Change"], [&"menu_confirm", PLAY_WORD], [&"menu_cancel", "Back"]]


## "Address  1.2.3.4     Port  7777" (the host's players screen and the online pause menu); the
## address reads "no network" when there is none. Pure.
static func address_line(addresses: Array[String], port: int) -> String:
	var shown := ", ".join(addresses) if not addresses.is_empty() else "no network"
	return "Address  %s     Port  %d" % [shown, port]


## Which inputs can join right now: a pad that is plugged in and not playing yet ("pad"), the
## keyboard while it is not playing ("keys"). `devices`: the roster's; `pads`: the connected pads.
## Pure.
static func join_inputs(devices: Array[int], pads: Array[int]) -> Dictionary:
	var pad := false
	for device: int in pads:
		pad = pad or not devices.has(device)
	return {"pad": pad, "keys": not devices.has(PlayerRoster.KEYBOARD)}


## What oaths 1..`oath` change, as icon chips for the picker ({glyph, text}, see ListMenu.chip): a
## picture and a few words each, the numbers from the oath data. Empty for no oath. Pure.
static func oath_chips(ladder: Array[OathData], oath: int) -> Array:
	var chips: Array = []
	if oath <= 0 or ladder.is_empty():
		return chips
	_add_chip(chips, ladder, oath, &"enemy_power_percent_add", &"sword", "Foes hit %s%%")
	if OathData.total(ladder, oath, &"enemy_hp_row_add") != 0 or OathData.total(ladder, oath, &"enemy_power_row_add") != 0:
		chips.append({"glyph": &"up", "text": "Foes grow faster"})
	_add_chip(chips, ladder, oath, &"elite_hp_percent_add", &"skull", "Elite HP %s%%")
	_add_chip(chips, ladder, oath, &"elite_power_percent_add", &"skull", "Elite hit %s%%")
	_add_chip(chips, ladder, oath, &"boss_hp_percent_add", &"skull", "Boss HP %s%%")
	_add_chip(chips, ladder, oath, &"boss_power_percent_add", &"skull", "Boss hit %s%%")
	var start_hp := OathData.start_hp_for(ladder, oath)
	if start_hp < 100:
		chips.append({"glyph": &"heart", "text": "Start HP %d%%" % start_hp})
	_add_chip(chips, ladder, oath, &"rest_heal_percent_add", &"heart", "Rest heal %s%%")
	_add_chip(chips, ladder, oath, &"act_heal_percent_add", &"heart", "Act heal %s%%")
	_add_chip(chips, ladder, oath, &"start_gold_add", &"coin", "Start gold %s")
	_add_chip(chips, ladder, oath, &"shop_price_percent_add", &"coin", "Shops %s%%")
	_add_chip(chips, ladder, oath, &"gold_percent_add", &"coin", "Fight gold %s%%")
	_add_chip(chips, ladder, oath, &"loot_choices_add", &"bag", "Spoils %s")
	_add_chip(chips, ladder, oath, &"team_gauge_carry_percent_add", &"bolt", "Gauge kept %s%%")
	_add_chip(chips, ladder, oath, &"start_relics_add", &"gem", "Start Relics %s")
	_add_chip(chips, ladder, oath, &"attr_points_per_level_add", &"up", "Level points %s")
	return chips


## One chip for a field's total over oaths 1..`oath`, when it is not 0: `text` gets the signed number.
static func _add_chip(chips: Array, ladder: Array[OathData], oath: int, field: StringName, glyph: StringName,
		text: String) -> void:
	var sum := OathData.total(ladder, oath, field)
	if sum != 0:
		chips.append({"glyph": glyph, "text": text % ("+%d" % sum if sum > 0 else str(sum))})


## The roster as it is now (a copy).
func roster() -> PlayerRoster:
	return _roster.copy()


## The oath picked (0: none).
func oath() -> int:
	return _oath


## True for the Players overlay in a run (setup_in_run; for tests).
func is_in_run() -> bool:
	return _in_run


## Online client: the host picked oath `oath`.
func set_oath(oath: int) -> void:
	_oath = clampi(oath, 0, oaths.size())
	_refresh()


## Online client: the host sent a new roster.
func set_roster(roster: PlayerRoster) -> void:
	_roster = roster.copy()
	_refresh()


## Online host: a client joined. False if the game is full.
func add_peer(peer: int) -> bool:
	if _roster.join_peer(peer) < 0:
		return false
	Sfx.play("player_join")
	_refresh()
	roster_changed.emit(_roster.copy())
	return true


## Online host: a client left.
func remove_peer(peer: int) -> void:
	var player := _roster.player_of_peer(peer)
	if player > 0 and _roster.leave(player):
		Sfx.play("player_leave")
		_refresh()
		roster_changed.emit(_roster.copy())


func _build(title: String, note: String, footer: Array) -> void:
	var column := ListMenu.screen_column(self, title, TITLE_SIZE)
	if not note.is_empty():
		column.add_child(ListMenu.centred_label(note, NOTE_SIZE, HudStyle.GOLD))
	if not saved_note.is_empty():
		column.add_child(ListMenu.centred_label(saved_note, NOTE_SIZE, HudStyle.TEXT_DIM))
	# The players on one line, side by side.
	var players := HBoxContainer.new()
	players.mouse_filter = Control.MOUSE_FILTER_IGNORE
	players.alignment = BoxContainer.ALIGNMENT_CENTER
	players.add_theme_constant_override("separation", PLAYERS_GAP)
	column.add_child(players)
	for i: int in PlayerRoster.MAX_PLAYERS:
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 10)
		players.add_child(line)
		_slots.append(line)
	column.add_child(_build_cards())
	column.add_child(_build_buttons())
	# The cursor's list draws nothing (every row is drawn above), so it stays out of the column.
	_menu = ListMenu.new()
	add_child(_menu)
	_footer = ListMenu.screen_footer(self, footer)
	var blank: Array[Dictionary] = []
	for i: int in _last_row() + 1:
		blank.append({})
		# Every row is drawn by this screen (cards, picker, Start, Continue); the list is only the cursor.
		_menu.set_row_shown(i, false)
	# A saved online run is where the cursor rests (card #313), as the main menu's Continue.
	_menu.index = _continue_row() if _has_continue() else _start_row()
	_menu.set_items(blank)
	_refresh()
	ButtonPrompts.listen(_refresh)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _online:
		_online_input(event)
		return
	var device := PlayerRoster.device_of(event)
	if _in_run and is_inside_tree() and not event is InputEventMouseMotion:
		# Modal (cards #304, #311): nothing under the overlay (a party screen, the map)
		# sees a press, not even from a friend who has not joined.
		get_viewport().set_input_as_handled()
	if device == PlayerRoster.ANY or event.is_echo():
		return
	# The mouse works for P1 (it has no Confirm of its own to join with).
	var player := 0 if event is InputEventMouse else _roster.devices.find(device)
	if _in_run:
		_in_run_input(event, device, player)
		return
	if player < 0:
		# A device not in the game can only join.
		if event.is_action_pressed(&"menu_confirm", false, true):
			get_viewport().set_input_as_handled()
			if _roster.join(device) >= 0:
				Sfx.play("menu_confirm")
				_refresh()
		return
	_act(_answer(event), player)


## The Players overlay in a run (cards #304, #311): `player` is the press's player (-1: a device
## not in the game).
func _in_run_input(event: InputEvent, device: int, player: int) -> void:
	if player < 0:
		# A device not in the game can only join; it takes one hero at once.
		if event.is_action_pressed(&"menu_confirm", false, true):
			if _roster.join_midrun(device) >= 0:
				Sfx.play("player_join")
				_refresh()
			else:
				Sfx.play("locked")
		return
	# Before Pause: Esc is both, and a joined keyboard P2 / P3 leaves with it as with Backspace.
	if player > 0 and event.is_action_pressed(&"menu_cancel", false, true):
		if _roster.leave_midrun(player):
			Sfx.play("player_leave")
			_refresh()
		return
	if event.is_action_pressed(&"pause", false, true):
		# P1's Esc lands here too: it closes, as Back does.
		Sfx.play("menu_cancel")
		back.emit()
		return
	_act(_answer(event), player)


func _online_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if not _is_host:
		# A waiting client can only leave.
		if event.is_action_pressed(&"menu_cancel", false, true) or MenuMouse.is_back(event):
			get_viewport().set_input_as_handled()
			Sfx.play("menu_cancel")
			back.emit()
		return
	_act(_answer(event), 0)


## The menu answer for an event: the mouse on this screen's own cards, picker and Start first, then
## the cursor's list (keys, pad, the wheel and a right click).
func _answer(event: InputEvent) -> StringName:
	var answer := _mouse_answer(event)
	if answer == &"":
		answer = _menu.handle(event)
	_update_focus()
	return answer


## Pointing at a card, the picker or Start puts the cursor there; a click on Start is &"confirm", a
## click on a card or the picker is &"left" or &"right" by the half it lands on. &"" otherwise.
func _mouse_answer(event: InputEvent) -> StringName:
	if not event is InputEventMouse:
		return &""
	var point := (event as InputEventMouse).position
	var targets := _targets()
	for row: int in targets:
		var share := MenuMouse.share_across(targets[row] as Control, point)
		if share < 0.0:
			continue
		if row != _menu.index and (event is InputEventMouseMotion or MenuMouse.is_click(event)):
			_menu.index = row
			Sfx.play("menu_move")
			_menu.redraw()
		if not MenuMouse.is_click(event):
			return &""
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		if row == _start_row() or row == _continue_row():
			return &"confirm"
		return &"left" if MenuMouse.side_of(share) < 0 else &"right"
	return &""


## The cursor's rows and what is drawn for each: {row: Control}.
func _targets() -> Dictionary:
	var out := {}
	for slot: int in _card_boxes.size():
		out[slot] = _card_boxes[slot]
	if _picker != null and _oath_row() >= 0:
		out[_oath_row()] = _picker
	if _start_button != null and _start_button.visible:
		out[_start_row()] = _start_button
	if _continue_button != null:
		out[_continue_row()] = _continue_button
	return out


## Acts on a menu answer from `player` (local) or the host.
func _act(answer: StringName, player: int) -> void:
	if answer == &"":
		return
	var row := _menu.index
	match answer:
		&"cancel":
			if player > 0 and not _online:
				# In a run only the mouse gets here (it is P1's), so this is a guard.
				if _in_run:
					if _roster.leave_midrun(player):
						Sfx.play("player_leave")
				else:
					Sfx.play("menu_cancel")
					_roster.leave(player)
				_refresh()
			else:
				Sfx.play("menu_cancel")
				back.emit()
		&"confirm":
			# Confirm starts from anywhere: Start is the one main button, but on Continue it carries
			# the saved online run on (card #313).
			Sfx.play("menu_confirm")
			if _has_continue() and row == _continue_row():
				continued.emit(_roster.copy())
			else:
				started.emit(_roster.copy(), _oath)
		&"left", &"right":
			var step := -1 if answer == &"left" else 1
			if row == _oath_row():
				_step_oath(step, false)
			elif row < _hero_names.size() and _hand_on(row, step):
				Sfx.play("menu_move")
				_refresh()
				if _online:
					roster_changed.emit(_roster.copy())


## Hands hero `slot` to the next (`step` +1) or previous player. In a run an only hero trades places
## (#311); before a run it cannot move (the approved behaviour, DESIGN.md 9.1).
func _hand_on(slot: int, step: int) -> bool:
	return _roster.trade_hero(slot, step) if _in_run else _roster.move_hero(slot, step)


## How a player is shown: their device in a local game; host / online, and "(you)", online.
func _player_name(player: int) -> String:
	if not _online:
		return PlayerRoster.device_name(_roster.device_of_player(player))
	var text := "Host" if player == 0 else "Online"
	if _roster.is_local(player):
		text += " (you)"
	return text


func _refresh() -> void:
	_refresh_players()
	var coop := _roster.is_coop()
	for slot: int in _hero_names.size():
		var owner := _roster.owner_of(slot)
		var tag := HudStyle.player_tag(owner)
		_menu.set_item(slot, "%s   %s" % [_hero_names[slot], tag])
		if slot < _card_tags.size():
			_card_tags[slot].text = "<  %s  >" % tag if coop else tag
			_card_tags[slot].label_settings.font_color = HudStyle.player_color(owner)
	_menu.set_item(_start_row(), PLAY_WORD if _in_run else START_WORD, not _online or _is_host)
	if _has_continue():
		_menu.set_item(_continue_row(), CONTINUE_WORD)
	if _start_button != null:
		_start_button.visible = not _online or _is_host
	_refresh_oath()
	_update_focus()


## The players line: each seat's tag; a player's device picture and name (online: host / online),
## in a run a joined P2 / P3's own Back button and "leave"; the first open seat shows the buttons
## that can join now, the later ones only their dim tag.
func _refresh_players() -> void:
	var open_seat := _roster.player_count()
	for i: int in _slots.size():
		var line := _slots[i]
		for child: Node in line.get_children():
			line.remove_child(child)
			child.queue_free()
		var playing := i < _roster.player_count()
		var tag := HudStyle.make_title(HudStyle.player_tag(i), PLAYER_SIZE,
				HudStyle.player_color(i) if playing else HudStyle.TEXT_DIM)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(tag)
		if playing:
			if not _online:
				var device := _roster.device_of_player(i)
				var glyph := UiGlyph.make(&"keyboard" if device == PlayerRoster.KEYBOARD else &"pad",
						float(HudStyle.scaled(roundi(DEVICE_GLYPH_PX))), HudStyle.player_color(i))
				glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				line.add_child(glyph)
			line.add_child(_slot_label(_player_name(i), HudStyle.player_color(i)))
			if _in_run and i > 0:
				_add_leave_chip(line, _roster.device_of_player(i))
		elif _online:
			line.add_child(_slot_label("waiting", HudStyle.TEXT_DIM))
		elif i == open_seat:
			_add_join_chips(line, join_inputs(_roster.devices, Input.get_connected_joypads()))


## The Confirm button of each input that can join (the pad's, the keyboard's), then "join".
func _add_join_chips(line: HBoxContainer, ways: Dictionary) -> void:
	var parts := HudStyle.binding_parts(&"menu_confirm")
	var chips := 0
	for pad: bool in [true, false]:
		if not bool(ways.get("pad" if pad else "keys", false)):
			continue
		var button := parts[1] if pad else parts[0]
		if button.is_empty():
			continue
		if chips > 0:
			line.add_child(_slot_label(HintBar.OR_TEXT, HudStyle.TEXT_DIM))
		var chip := HudStyle.button_chip(button, pad, PLAYER_SIZE)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(chip)
		chips += 1
	if chips > 0:
		line.add_child(_slot_label("join", HudStyle.TEXT_DIM))


## A joined P2 / P3's own Back button (their pad's, or the keyboard's key), then a dim "leave"
## (the Players overlay in a run, #311).
func _add_leave_chip(line: HBoxContainer, device: int) -> void:
	var parts := HudStyle.binding_parts(&"menu_cancel")
	var pad := device != PlayerRoster.KEYBOARD
	var button := parts[1] if pad else parts[0]
	if button.is_empty():
		return
	var chip := HudStyle.button_chip(button, pad, PLAYER_SIZE)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.modulate = CARD_DIM
	line.add_child(chip)
	line.add_child(_slot_label("leave", HudStyle.TEXT_DIM))


static func _slot_label(text: String, color: Color) -> Label:
	var label := HudStyle.make_label(text, PLAYER_SIZE, color)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


# --- the cursor's rows: the heroes, the Oath picker (DESIGN.md 8.15), Start -----------------------

## The cursor row of the Oath picker (-1: this screen has none), then Start.
func _oath_row() -> int:
	return _hero_names.size() if not oaths.is_empty() else -1


func _start_row() -> int:
	return _hero_names.size() + (0 if oaths.is_empty() else 1)


## True when this screen has the Continue button: the online host's, with a saved online run.
func _has_continue() -> bool:
	return not continue_line.is_empty() and _online and _is_host and not _in_run


## The Continue button's cursor row, after Start (-1: none).
func _continue_row() -> int:
	return _start_row() + 1 if _has_continue() else -1


## The cursor's last row: Continue, else Start.
func _last_row() -> int:
	return _continue_row() if _has_continue() else _start_row()


## True when this screen offers to continue a saved online run (for tests).
func has_continue() -> bool:
	return _has_continue()


## The highest oath that can be picked on this screen.
func _oath_top() -> int:
	return mini(oath_unlocked, oaths.size())


## Moves the oath pick one step. `wrap`: from the top it goes back to none.
func _step_oath(step: int, wrap: bool) -> void:
	if oaths.is_empty() or (_online and not _is_host):
		Sfx.play("locked")
		return
	var next := _oath + step
	if wrap and next > _oath_top():
		next = 0
	next = clampi(next, 0, _oath_top())
	if next == _oath:
		Sfx.play("locked")
		return
	_oath = next
	Sfx.play("menu_move")
	_refresh()
	if _online:
		oath_changed.emit(_oath)


## The picker's line ("<  Oath 2  >", arrows only where it can still go and only for whoever picks)
## and its effect chips.
func _refresh_oath() -> void:
	if oaths.is_empty() or _picker == null:
		return
	var mine := not _online or _is_host
	var text := "%s%s%s" % ["<  " if mine and _oath > 0 else "", OathData.label(_oath),
			"  >" if mine and _oath < _oath_top() else ""]
	_picker_title.text = text
	_menu.set_item(_oath_row(), text)
	if _picker_chips != null:
		_picker_body.remove_child(_picker_chips)
		_picker_chips.queue_free()
	var chips := oath_chips(oaths, _oath)
	if chips.is_empty():
		chips = [{"text": NO_CHANGE, "color": HudStyle.TEXT_DIM}]
	_picker_chips = ListMenu.chip_lines(chips, PICKER_WIDTH - float(ListMenu.CARD_PAD * 2), EFFECT_SIZE)
	_picker_body.add_child(_picker_chips)


## The hero cards in a row, centred: each the hero's big portrait in a frame, a name plate under it.
func _build_cards() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", CARD_GAP)
	for slot: int in _hero_names.size():
		var card := VBoxContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_theme_constant_override("separation", 6)
		row.add_child(card)
		_card_boxes.append(card)
		var frame := PanelContainer.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(frame)
		var path := hero_portraits[slot] if slot < hero_portraits.size() else ""
		var full := AssetLoader.texture(path, Vector2i(192, 288))
		var face := AtlasTexture.new()
		face.atlas = full
		face.region = Rect2(0.0, 0.0, full.get_width(), mini(CARD_ROWS, full.get_height()))
		var picture := TextureRect.new()
		picture.texture = face
		picture.custom_minimum_size = (face.region.size * _card_scale()).round()
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(picture)
		_cards.append(frame)
		var plate := HBoxContainer.new()
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.alignment = BoxContainer.ALIGNMENT_CENTER
		plate.add_theme_constant_override("separation", 18)
		card.add_child(plate)
		plate.add_child(HudStyle.make_title(_hero_names[slot], PLATE_SIZE))
		var tag := HudStyle.make_title("", PLATE_SIZE)
		plate.add_child(tag)
		_card_tags.append(tag)
	return row


## How many times its pixels a portrait is drawn: smaller with an Oath picker and with bigger text.
func _card_scale() -> float:
	var scale := CARD_SCALE if oaths.is_empty() else CARD_SCALE_OATH
	return scale * 100.0 / float(maxi(100, HudStyle.text_scale_percent()))


## The Oath picker (a run's screen only) and the Start button, side by side under the cards.
func _build_buttons() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", BUTTONS_GAP)
	if not oaths.is_empty():
		_picker = PanelContainer.new()
		_picker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_picker.custom_minimum_size.x = PICKER_WIDTH
		_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_picker)
		_picker_body = VBoxContainer.new()
		_picker_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_picker_body.add_theme_constant_override("separation", 10)
		_picker.add_child(_picker_body)
		_picker_title = HudStyle.make_title("", PICKER_SIZE)
		_picker_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_picker_body.add_child(_picker_title)
	_start_button = PanelContainer.new()
	_start_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_button.custom_minimum_size.x = START_WIDTH
	_start_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_start_button)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 16)
	_start_button.add_child(line)
	var chip := HintBar.new([[&"menu_confirm", ""]], PLAYER_SIZE, HudStyle.TEXT)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(chip)
	_start_chip = chip
	_start_label = HudStyle.make_title(PLAY_WORD if _in_run else START_WORD, START_SIZE)
	_start_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(_start_label)
	if _has_continue():
		row.add_child(_build_continue())
	return row


## The Continue button (card #313): the Confirm chip (shown while the cursor is on it), the save
## picture, "Continue" and where the saved run is under it.
func _build_continue() -> PanelContainer:
	_continue_button = PanelContainer.new()
	_continue_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_continue_button.custom_minimum_size.x = START_WIDTH
	_continue_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 16)
	_continue_button.add_child(line)
	_continue_chip = HintBar.new([[&"menu_confirm", ""]], PLAYER_SIZE, HudStyle.TEXT)
	_continue_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(_continue_chip)
	var glyph := PauseMenu.RowGlyph.new()
	glyph.kind = &"save"
	var px := float(HudStyle.scaled(CONTINUE_GLYPH_PX))
	glyph.custom_minimum_size = Vector2(px, px)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.color = HudStyle.TEXT
	line.add_child(glyph)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_theme_constant_override("separation", 0)
	line.add_child(words)
	_continue_label = HudStyle.make_title(CONTINUE_WORD, START_SIZE)
	words.add_child(_continue_label)
	var where := HudStyle.make_label(continue_line, CONTINUE_LINE_SIZE, HudStyle.TEXT_DIM)
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_child(where)
	return _continue_button


## Lights what the cursor is on: a hero card's gold frame (the others dim), the picker's or Start's
## gold edge and word.
func _update_focus() -> void:
	if _menu == null:
		return
	var on_hero := _menu.index < _cards.size()
	for slot: int in _cards.size():
		var chosen := on_hero and _menu.index == slot
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.03, 0.02, 0.03)
		style.border_color = HudStyle.GOLD if chosen else CARD_FRAME
		style.set_border_width_all(CARD_BORDER)
		style.set_content_margin_all(CARD_BORDER)
		_cards[slot].add_theme_stylebox_override("panel", style)
		_card_boxes[slot].modulate = CARD_DIM if on_hero and not chosen else Color.WHITE
	# A waiting client's cursor never lights anything: it has nothing to pick.
	var mine := not _online or _is_host
	if _picker != null:
		var on_oath := mine and _menu.index == _oath_row()
		_picker.add_theme_stylebox_override("panel", ListMenu.card_style(on_oath))
		_picker_title.label_settings.font_color = HudStyle.GOLD if on_oath else HudStyle.TEXT
	if _start_button != null:
		var on_start := mine and _menu.index == _start_row()
		_start_button.add_theme_stylebox_override("panel", ListMenu.card_style(on_start))
		_start_label.label_settings.font_color = HudStyle.GOLD if on_start else HudStyle.TEXT
	if _continue_button != null:
		# Confirm continues only on Continue (card #313): its chip shows there, Start's everywhere else.
		var on_continue := mine and _menu.index == _continue_row()
		_continue_button.add_theme_stylebox_override("panel", ListMenu.card_style(on_continue))
		_continue_label.label_settings.font_color = HudStyle.GOLD if on_continue else HudStyle.TEXT
		_continue_chip.modulate.a = 1.0 if on_continue else 0.0
		if _start_chip != null:
			_start_chip.modulate.a = 0.0 if on_continue else 1.0
		var word := CONTINUE_WORD if on_continue else START_WORD
		if _footer != null and word != _footer_word:
			_footer_word = word
			_footer.set_entries(hints(true, true, word))


## True while the cursor's row `row` is lit (for tests): a hero card, the picker or Start.
func is_lit(row: int) -> bool:
	return _menu != null and _menu.index == row and (not _online or _is_host)
