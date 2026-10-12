class_name LobbyScreen
extends CanvasLayer
## The players screen before a run or practice (DESIGN.md 9.1). The device that opened it is P1.
## Another keyboard or pad presses Confirm to join (up to three players) and Back to leave. The
## heroes are dealt out in turn (P1 gets the extra one); left/right on a hero hands it to another
## player, as long as every player keeps a hero. Start begins with this roster; Back (or P1's
## Cancel) returns to the main menu and leaves the old roster alone.

## Confirmed: play with `players`.
signal started(players: PlayerRoster)
signal back

const TITLE_SIZE: int = 64
const PLAYER_SIZE: int = 34
const DETAIL_SIZE: int = 26
const HINT_SIZE: int = 24

var _roster: PlayerRoster
var _hero_names: Array[String] = []
var _menu: ListMenu
var _player_labels: Array[Label] = []


## `previous` is the last roster (its hero split is kept when the same players come back);
## `first_device` is the device that opened the screen (P1).
func setup(hero_names: Array[String], previous: PlayerRoster, first_device: int) -> void:
	_hero_names = hero_names
	_roster = previous.copy() if previous != null and previous.hero_count() == hero_names.size() \
			else PlayerRoster.solo(hero_names.size(), first_device)
	if _roster.device_of_player(0) != first_device:
		# Someone else opened it: they are P1 now, alone.
		_roster = PlayerRoster.solo(hero_names.size(), first_device)
	var column := ListMenu.screen_column(self, "Players", TITLE_SIZE)
	for i: int in PlayerRoster.MAX_PLAYERS:
		var label := ListMenu.centred_label("", PLAYER_SIZE)
		column.add_child(label)
		_player_labels.append(label)
	column.add_child(Control.new())
	_menu = ListMenu.new()
	column.add_child(_menu)
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	var confirm := HudStyle.binding_text(&"menu_confirm")
	var cancel := HudStyle.binding_text(&"menu_cancel")
	column.add_child(ListMenu.centred_label(
			"Join: %s on another pad or keyboard   Leave: %s\nUp/Down choose   Left/Right give a hero to another player" % [
			confirm, cancel], HINT_SIZE, HudStyle.TEXT_DIM))
	var blank: Array[Dictionary] = []
	for i: int in hero_names.size() + 2:
		blank.append({})
	_menu.index = hero_names.size()
	_menu.set_items(blank, detail)
	_refresh()


## The roster as it is now (a copy).
func roster() -> PlayerRoster:
	return _roster.copy()


func _unhandled_input(event: InputEvent) -> void:
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
	if answer == &"":
		return
	var hero := _menu.index if _menu.index < _hero_names.size() else -1
	match answer:
		&"cancel":
			if player > 0:
				Sfx.play("menu_cancel")
				_roster.leave(player)
				_refresh()
			else:
				Sfx.play("menu_cancel")
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


func _refresh() -> void:
	for i: int in _player_labels.size():
		var label := _player_labels[i]
		if i < _roster.player_count():
			var names := PackedStringArray()
			for slot: int in _roster.heroes_of(i):
				names.append(_hero_names[slot])
			label.text = "%s   %s   %s" % [HudStyle.player_tag(i), PlayerRoster.device_name(_roster.device_of_player(i)),
					", ".join(names)]
			label.label_settings.font_color = HudStyle.player_color(i)
		else:
			label.text = "%s   press %s to join" % [HudStyle.player_tag(i), HudStyle.binding_text(&"menu_confirm")]
			label.label_settings.font_color = HudStyle.TEXT_DIM
	var coop := _roster.is_coop()
	for slot: int in _hero_names.size():
		var owner := _roster.owner_of(slot)
		var text := "%s   %s" % [_hero_names[slot], HudStyle.player_tag(owner)]
		if coop:
			text = "%s   < %s >" % [_hero_names[slot], HudStyle.player_tag(owner)]
		var detail := "Left/Right: give %s to another player." % _hero_names[slot] if coop \
				else "Join with a second pad or the keyboard to share the heroes."
		_menu.set_item(slot, text, true, detail)
	var players := "alone" if not coop else "with %d players" % _roster.player_count()
	_menu.set_item(_hero_names.size(), "Start", true, "Play %s." % players)
	_menu.set_item(_hero_names.size() + 1, "Back", true, "Back to the main menu.")
