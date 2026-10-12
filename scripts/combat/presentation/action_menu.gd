class_name ActionMenu
extends PanelContainer
## The party member's action menu, driven only by the menu_* input actions (no focus-driven
## buttons, so the parry key can never click it). Up/down picks an ability, confirm uses it;
## abilities that cannot be used now are greyed out with the reason. If the ability needs a
## choice of target (an enemy, an ally, a downed ally) and there is more than one, a target step
## follows (left/right or up/down cycles, cancel goes back).

signal chosen(ability_id: String, target_id: int)
## The target being pointed at during the target step, or -1 when the step ends.
signal target_changed(target_id: int)

const TITLE_SIZE: int = 30
const ITEM_SIZE: int = 30
const HINT_SIZE: int = 20
const DESCRIPTION_SIZE: int = 22
const MENU_WIDTH: float = 460.0
const CURSOR := "> "

var _title: Label
var _items_box: VBoxContainer
var _hint: Label
var _description: Label
var _labels: Array[Label] = []
## Each: {ability: AbilityData, usable: bool, reason: String, targets: Array[int],
## pick_target: bool}.
var _entries: Array[Dictionary] = []
var _names: Dictionary = {}
var _index: int = 0
var _target_index: int = 0
var _choosing_target: bool = false
## Process frame of the last stick move (a held stick sends many motion events).
var _stick_frame: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(MENU_WIDTH, 0.0)
	add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.PANEL_BG, HudStyle.GOLD, 2, 16))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_title = HudStyle.make_label("", TITLE_SIZE)
	column.add_child(_title)
	_items_box = VBoxContainer.new()
	_items_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_items_box)
	_description = HudStyle.make_label("", DESCRIPTION_SIZE)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(MENU_WIDTH, 0.0)
	column.add_child(_description)
	_hint = HudStyle.make_label("", HINT_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_hint)
	visible = false


## Opens the menu for one actor. `entries` as described on _entries; `names` maps fighter id ->
## display name (for the target step).
## `player` is the co-op player whose turn it is (-1 in solo: no tag).
func open(actor_name: String, accent: Color, entries: Array[Dictionary], names: Dictionary, player: int = -1) -> void:
	_title.text = "%s's turn" % actor_name
	if player >= 0:
		_title.text += "  (%s)" % HudStyle.player_tag(player)
	_title.label_settings.font_color = accent.lightened(0.25)
	_entries = entries
	_names = names
	_choosing_target = false
	_index = 0
	for label: Label in _labels:
		label.queue_free()
	_labels.clear()
	for entry: Dictionary in _entries:
		var label := HudStyle.make_label("", ITEM_SIZE)
		_items_box.add_child(label)
		_labels.append(label)
	_redraw()
	visible = true


func close() -> void:
	visible = false
	if _choosing_target:
		_choosing_target = false
		target_changed.emit(-1)


func is_open() -> bool:
	return visible


## The abilities currently offered (empty when closed).
func abilities() -> Array[AbilityData]:
	var list: Array[AbilityData] = []
	if visible:
		for entry: Dictionary in _entries:
			list.append(entry.ability as AbilityData)
	return list


## True if the ability is offered and can be used now.
func is_usable(ability_id: String) -> bool:
	for entry: Dictionary in _entries:
		if (entry.ability as AbilityData).id == ability_id:
			return visible and bool(entry.usable)
	return false


## The targets offered for this ability (empty if none or not offered).
func targets_of(ability_id: String) -> Array[int]:
	var list: Array[int] = []
	for entry: Dictionary in _entries:
		if (entry.ability as AbilityData).id == ability_id:
			list.assign(entry.targets)
	return list


## Handles one input event. Returns true if it was used.
func handle_input(event: InputEvent) -> bool:
	if not visible or _entries.is_empty():
		return false
	if _choosing_target:
		return _handle_target_input(event)
	if _pressed(event, &"menu_up"):
		_move(-1)
	elif _pressed(event, &"menu_down"):
		_move(1)
	elif _pressed(event, &"menu_confirm"):
		_confirm_ability()
	else:
		return false
	return true


## Picks an ability and target directly, for the autoplay bot (target -1: the first offered).
## Same usability check as a confirm press.
func choose(ability_id: String, target_id: int = -1) -> bool:
	if not visible:
		return false
	for i: int in _entries.size():
		var entry: Dictionary = _entries[i]
		if (entry.ability as AbilityData).id != ability_id or not bool(entry.usable):
			continue
		var targets: Array = entry.targets
		if target_id >= 0 and not targets.has(target_id):
			return false
		_index = i
		_redraw()
		Sfx.play("menu_confirm")
		close()
		chosen.emit(ability_id, target_id if target_id >= 0 else _default_target(entry))
		return true
	return false


## True for a fresh press of `action`. Sticks only count when they cross the deadzone.
func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	if event is InputEventJoypadMotion:
		var frame := Engine.get_process_frames()
		if not Input.is_action_just_pressed(action) or frame == _stick_frame:
			return false
		_stick_frame = frame
	return true


func _handle_target_input(event: InputEvent) -> bool:
	var targets: Array = _entries[_index].targets
	if _pressed(event, &"menu_left") or _pressed(event, &"menu_up"):
		_cycle_target(-1)
	elif _pressed(event, &"menu_right") or _pressed(event, &"menu_down"):
		_cycle_target(1)
	elif _pressed(event, &"menu_confirm"):
		Sfx.play("menu_confirm")
		var target := int(targets[_target_index])
		_choosing_target = false
		target_changed.emit(-1)
		visible = false
		chosen.emit((_entries[_index].ability as AbilityData).id, target)
	elif _pressed(event, &"menu_cancel"):
		Sfx.play("menu_cancel")
		_choosing_target = false
		target_changed.emit(-1)
		_redraw()
	else:
		return false
	return true


func _move(step: int) -> void:
	_index = wrapi(_index + step, 0, _entries.size())
	Sfx.play("menu_move")
	_redraw()


func _confirm_ability() -> void:
	var entry: Dictionary = _entries[_index]
	if not bool(entry.usable):
		Sfx.play("locked")
		return
	var targets: Array = entry.targets
	if bool(entry.pick_target) and targets.size() > 1:
		Sfx.play("menu_move")
		_choosing_target = true
		_target_index = 0
		_redraw()
		target_changed.emit(int(targets[_target_index]))
		return
	Sfx.play("menu_confirm")
	visible = false
	chosen.emit((entry.ability as AbilityData).id, _default_target(entry))


func _default_target(entry: Dictionary) -> int:
	var targets: Array = entry.targets
	if not bool(entry.pick_target) or targets.is_empty():
		return -1
	return int(targets[0])


func _cycle_target(step: int) -> void:
	var targets: Array = _entries[_index].targets
	_target_index = wrapi(_target_index + step, 0, targets.size())
	Sfx.play("menu_move")
	_redraw()
	target_changed.emit(int(targets[_target_index]))


func _redraw() -> void:
	for i: int in _labels.size():
		var entry: Dictionary = _entries[i]
		var ability := entry.ability as AbilityData
		var text := ability.display_name
		if ability.team_ultimate:
			text = ability.display_name.to_upper()
		elif ability.ap_cost > 0:
			text += "   %d AP" % ability.ap_cost
		elif ability.ap_gain > 0:
			text += "   +%d AP" % ability.ap_gain
		var selected := i == _index
		_labels[i].text = (CURSOR if selected else "  ") + text
		var color := HudStyle.TEXT
		if not bool(entry.usable):
			color = HudStyle.TEXT_DIM
		elif selected:
			color = HudStyle.GOLD
		elif ability.team_ultimate:
			color = HudStyle.GAUGE_FILL
		_labels[i].label_settings.font_color = color
	var current: Dictionary = _entries[_index]
	var description := (current.ability as AbilityData).description
	if not bool(current.usable):
		description += "\n" + String(current.reason)
	_description.text = description
	if _choosing_target:
		var target := int((current.targets as Array)[_target_index])
		_hint.text = "Target: %s   (left/right, %s back)" % [String(_names.get(target, "?")),
				HudStyle.binding_text(&"menu_cancel")]
	else:
		_hint.text = "Up/Down choose   %s confirm" % HudStyle.binding_text(&"menu_confirm")
