class_name LobbyScreen
extends CanvasLayer
## The players screen before a run or practice (DESIGN.md 9.1). The device that opened it is P1.
## Another keyboard or pad presses Confirm to join (up to three players) and Back to leave. The
## heroes are dealt out in turn (P1 gets the extra one); left/right on a hero hands it to another
## player, as long as every player keeps a hero. Start begins with this roster; Back (or P1's
## Cancel) returns to the main menu and leaves the old roster alone.
##
## The heroes stand side by side as big painted portraits (cards #140, #141), like an arcade
## select screen: the one the cursor is on gets a gold frame, a name plate under each says who
## plays it.
##
## Online (DESIGN.md 9.2) one player is one machine. The host's screen shows the address friends
## type in; players join over the network (Main calls add_peer / remove_peer) and the host hands
## heroes out and starts. A client's screen only shows the roster the host sends (set_roster) and
## waits; its Back leaves the game.

## Confirmed: play with `players`.
signal started(players: PlayerRoster)
signal back
## Online host: the roster changed (to send to the clients).
signal roster_changed(players: PlayerRoster)

const TITLE_SIZE: int = 64
const PLAYER_SIZE: int = 34
const DETAIL_SIZE: int = 26
## Hero cards: the big portrait's top CARD_ROWS rows (the face and shoulders), CARD_SCALE times
## its pixels, in a frame CARD_BORDER wide; the name plate under it.
const CARD_SCALE: int = 2
const CARD_ROWS: int = 240
const CARD_BORDER: int = 4
const CARD_GAP: int = 28
const PLATE_SIZE: int = 34
const CARD_FRAME := Color(0.36, 0.33, 0.3)
const CARD_DIM := Color(0.55, 0.55, 0.55)

## The heroes' big portraits, in hero order (set before setup).
var hero_portraits: Array[String] = []

var _roster: PlayerRoster
var _hero_names: Array[String] = []
var _menu: ListMenu
var _player_labels: Array[Label] = []
## Per player line: "press [Confirm button] to join" with the button as a picture (empty slots).
var _join_hints: Array[HintBar] = []
## Per hero: its card's frame and its name plate's owner tag.
var _cards: Array[PanelContainer] = []
var _card_tags: Array[Label] = []
var _online: bool = false
var _is_host: bool = true


## `previous` is the last roster (its hero split is kept when the same players come back);
## `first_device` is the device that opened the screen (P1).
func setup(hero_names: Array[String], previous: PlayerRoster, first_device: int) -> void:
	_hero_names = hero_names
	_roster = previous.copy() if previous != null and not previous.is_online() \
			and previous.hero_count() == hero_names.size() else PlayerRoster.solo(hero_names.size(), first_device)
	if _roster.device_of_player(0) != first_device:
		# Someone else opened it: they are P1 now, alone.
		_roster = PlayerRoster.solo(hero_names.size(), first_device)
	_build("Players", "", [[&"@updown", "Choose"], [&"@leftright", "Give a hero"],
			[&"menu_confirm", "Join (another pad or keyboard)"], [&"menu_cancel", "Leave"]])


## The online players screen. `roster` is the host's (online) roster; `is_host` false makes this
## a waiting client's screen. `addresses` and `port` are shown to the host for friends to type.
func setup_online(hero_names: Array[String], roster: PlayerRoster, is_host: bool, addresses: Array[String], port: int) -> void:
	_hero_names = hero_names
	_roster = roster.copy()
	_online = true
	_is_host = is_host
	if is_host:
		var shown := ", ".join(addresses) if not addresses.is_empty() else "(no network found)"
		_build("Host Online", "Friends join with this address:  %s   (port %d)" % [shown, port],
				[[&"@updown", "Choose"], [&"@leftright", "Give a hero"], [&"menu_cancel", "Stop hosting"]])
	else:
		_build("Online Players", "Waiting for the host to start.", [[&"menu_cancel", "Leave"]])


## The roster as it is now (a copy).
func roster() -> PlayerRoster:
	return _roster.copy()


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


func _build(title: String, note: String, hints: Array) -> void:
	var column := ListMenu.screen_column(self, title, TITLE_SIZE)
	if not note.is_empty():
		column.add_child(ListMenu.centred_label(note, DETAIL_SIZE, HudStyle.GOLD))
	# The players on one line, side by side.
	var players := HBoxContainer.new()
	players.mouse_filter = Control.MOUSE_FILTER_IGNORE
	players.alignment = BoxContainer.ALIGNMENT_CENTER
	players.add_theme_constant_override("separation", 56)
	column.add_child(players)
	for i: int in PlayerRoster.MAX_PLAYERS:
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 10)
		players.add_child(line)
		var label := ListMenu.centred_label("", PLAYER_SIZE)
		line.add_child(label)
		_player_labels.append(label)
		var join := HintBar.new([[&"menu_confirm", "to join"]], PLAYER_SIZE, HudStyle.TEXT_DIM)
		join.visible = false
		line.add_child(join)
		_join_hints.append(join)
	column.add_child(_build_cards())
	_menu = ListMenu.new()
	column.add_child(_menu)
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	ListMenu.screen_footer(self, hints)
	var blank: Array[Dictionary] = []
	for i: int in _hero_names.size() + 2:
		blank.append({})
	_menu.index = _hero_names.size()
	for slot: int in _hero_names.size():
		_menu.set_row_shown(slot, false)
	_menu.set_items(blank, detail)
	_refresh()
	ButtonPrompts.listen(_refresh)


func _unhandled_input(event: InputEvent) -> void:
	if _online:
		_online_input(event)
		return
	var device := PlayerRoster.device_of(event)
	if device == PlayerRoster.ANY or event.is_echo():
		return
	var player := _roster.devices.find(device)
	if player < 0:
		# A device not in the game can only join.
		if event.is_action_pressed(&"menu_confirm", false, true):
			get_viewport().set_input_as_handled()
			if _roster.join(device) >= 0:
				Sfx.play("menu_confirm")
				_refresh()
		return
	var answer := _menu.handle(event)
	_update_cards()
	if answer == &"":
		return
	var hero := _menu.index if _menu.index < _hero_names.size() else -1
	match answer:
		&"cancel":
			Sfx.play("menu_cancel")
			if player > 0:
				_roster.leave(player)
				_refresh()
			else:
				back.emit()
		&"left", &"right":
			if hero >= 0 and _roster.move_hero(hero, -1 if answer == &"left" else 1):
				Sfx.play("menu_move")
				_refresh()
		&"confirm":
			if _menu.index == _hero_names.size():
				Sfx.play("menu_confirm")
				started.emit(_roster.copy())
			elif _menu.index == _hero_names.size() + 1:
				Sfx.play("menu_cancel")
				back.emit()
			elif hero >= 0 and _roster.move_hero(hero, 1):
				Sfx.play("menu_move")
				_refresh()


func _online_input(event: InputEvent) -> void:
	var answer := _menu.handle(event)
	_update_cards()
	if answer == &"cancel" or (answer == &"confirm" and _menu.index == _hero_names.size() + 1):
		Sfx.play("menu_cancel")
		back.emit()
		return
	if not _is_host:
		return
	var hero := _menu.index if _menu.index < _hero_names.size() else -1
	match answer:
		&"left", &"right":
			if hero >= 0 and _roster.move_hero(hero, -1 if answer == &"left" else 1):
				Sfx.play("menu_move")
				_refresh()
				roster_changed.emit(_roster.copy())
		&"confirm":
			if _menu.index == _hero_names.size():
				Sfx.play("menu_confirm")
				started.emit(_roster.copy())
			elif hero >= 0 and _roster.move_hero(hero, 1):
				Sfx.play("menu_move")
				_refresh()
				roster_changed.emit(_roster.copy())


## How a player is shown: their device in a local game; host / online, and "(you)", online.
func _player_name(player: int) -> String:
	if not _online:
		return PlayerRoster.device_name(_roster.device_of_player(player))
	var text := "Host" if player == 0 else "Online"
	if _roster.is_local(player):
		text += " (you)"
	return text


func _refresh() -> void:
	for i: int in _player_labels.size():
		var label := _player_labels[i]
		_join_hints[i].visible = false
		if i < _roster.player_count():
			var names := PackedStringArray()
			for slot: int in _roster.heroes_of(i):
				names.append(_hero_names[slot])
			label.text = "%s   %s" % [HudStyle.player_tag(i), _player_name(i)]
			label.label_settings.font_color = HudStyle.player_color(i)
		elif _online:
			label.text = "%s   waiting for a friend" % HudStyle.player_tag(i)
			label.label_settings.font_color = HudStyle.TEXT_DIM
		else:
			label.text = "%s   press" % HudStyle.player_tag(i)
			label.label_settings.font_color = HudStyle.TEXT_DIM
			_join_hints[i].visible = true
	var coop := _roster.is_coop()
	for slot: int in _hero_names.size():
		var owner := _roster.owner_of(slot)
		var text := "%s   %s" % [_hero_names[slot], HudStyle.player_tag(owner)]
		if coop:
			text = "%s   < %s >" % [_hero_names[slot], HudStyle.player_tag(owner)]
		var detail := "Left/Right: give %s to another player." % _hero_names[slot] if coop \
				else "Join with a second pad or the keyboard to share the heroes."
		if _online:
			detail = "The host hands out the heroes." if not _is_host else (detail if coop else "Friends who join share the heroes.")
		_menu.set_item(slot, text, true, detail)
		if slot < _card_tags.size():
			var tag := HudStyle.player_tag(owner)
			_card_tags[slot].text = "<  %s  >" % tag if coop else tag
			_card_tags[slot].label_settings.font_color = HudStyle.player_color(owner)
	var players := "alone" if not coop else "with %d players" % _roster.player_count()
	if _online and not _is_host:
		_menu.set_item(_hero_names.size(), "Start", false, "Only the host can start.")
		_menu.set_item(_hero_names.size() + 1, "Leave", true, "Leave the game.")
	elif _online:
		_menu.set_item(_hero_names.size(), "Start", true, "Start a run %s." % players)
		_menu.set_item(_hero_names.size() + 1, "Back", true, "Stop hosting.")
	else:
		_menu.set_item(_hero_names.size(), "Start", true, "Play %s." % players)
		_menu.set_item(_hero_names.size() + 1, "Back", true, "Back to the main menu.")
	_update_cards()


## The hero cards in a row: each the hero's big portrait in a frame, a name plate under it.
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
		picture.custom_minimum_size = face.region.size * float(CARD_SCALE)
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


## The card the cursor is on gets a gold frame; while the cursor is on a hero the others dim.
func _update_cards() -> void:
	var on_hero := _menu != null and _menu.index < _cards.size()
	for slot: int in _cards.size():
		var chosen := on_hero and _menu.index == slot
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.03, 0.02, 0.03)
		style.border_color = HudStyle.GOLD if chosen else CARD_FRAME
		style.set_border_width_all(CARD_BORDER)
		style.set_content_margin_all(CARD_BORDER)
		_cards[slot].add_theme_stylebox_override("panel", style)
		_cards[slot].get_parent().modulate = CARD_DIM if on_hero and not chosen else Color.WHITE
