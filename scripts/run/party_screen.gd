class_name PartyScreen
extends CanvasLayer
## The party screen (DESIGN.md 8), from the map (Tab / Y) and after picking loot: the party level,
## each character's stats and gear slots, and the bag. Left/right picks a character, up/down a
## slot; confirm opens a list to put a bag item on, swap it, or take it off. Back closes.

signal done

const TITLE_SIZE: int = 64
const TEXT_SIZE: int = 30
const SMALL_SIZE: int = 26
const NAME_SIZE: int = 34
const HINT_SIZE: int = 24
const PANEL_WIDTH: float = 430.0
const EMPTY_TEXT := "(empty)"

var _run: RunState
var _level: Label
var _panels: Array[PanelContainer] = []
## Per character: {stats: Label, slots: Array[Label]}.
var _rows: Array[Dictionary] = []
var _detail: Label
var _bag: Label
var _hint: Label
var _picker: ListMenu
var _char: int = 0
var _slot: int = 0
## Picker entries: GearData to put on, or the strings "off" / "cancel".
var _choices: Array = []


## `note`: an extra line at the top (for example what was just found).
func setup(run: RunState, note: String = "") -> void:
	_run = run
	var column := ListMenu.screen_column(self, "Party", TITLE_SIZE)
	_level = ListMenu.centred_label("", TEXT_SIZE, HudStyle.GOLD)
	column.add_child(_level)
	if not note.is_empty():
		column.add_child(ListMenu.centred_label(note, TEXT_SIZE))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	for slot: int in run.party_size():
		var c := run.data.party[slot]
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.custom_minimum_size.x = PANEL_WIDTH
		row.add_child(panel)
		_panels.append(panel)
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 6)
		panel.add_child(box)
		box.add_child(HudStyle.make_label(c.display_name, NAME_SIZE, c.color.lightened(0.25)))
		var stats := HudStyle.make_label("", SMALL_SIZE, HudStyle.TEXT_DIM)
		box.add_child(stats)
		var labels: Array[Label] = []
		for g: int in run.gear[slot].size():
			var label := HudStyle.make_label("", TEXT_SIZE)
			box.add_child(label)
			labels.append(label)
		_rows.append({"stats": stats, "slots": labels})
	_detail = ListMenu.centred_label("", SMALL_SIZE, HudStyle.TEXT_DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size.x = PANEL_WIDTH * 3.0
	column.add_child(_detail)
	_bag = ListMenu.centred_label("", SMALL_SIZE)
	_bag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bag.custom_minimum_size.x = PANEL_WIDTH * 3.0
	column.add_child(_bag)
	_picker = ListMenu.new()
	_picker.item_size = TEXT_SIZE
	_picker.visible = false
	column.add_child(_picker)
	_hint = ListMenu.centred_label("", HINT_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_hint)
	_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _picker.visible:
		_picker_input(event)
		return
	var step := Vector2i.ZERO
	if _pressed(event, &"menu_left"):
		step.x = -1
	elif _pressed(event, &"menu_right"):
		step.x = 1
	elif _pressed(event, &"menu_up"):
		step.y = -1
	elif _pressed(event, &"menu_down"):
		step.y = 1
	elif _pressed(event, &"menu_confirm"):
		get_viewport().set_input_as_handled()
		_open_picker()
		return
	elif _pressed(event, &"menu_cancel") or _pressed(event, &"party_menu"):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_cancel")
		done.emit()
		return
	else:
		return
	get_viewport().set_input_as_handled()
	_char = wrapi(_char + step.x, 0, _run.party_size())
	_slot = wrapi(_slot + step.y, 0, _run.gear[_char].size())
	Sfx.play("menu_move")
	_redraw()


func _picker_input(event: InputEvent) -> void:
	match _picker.handle(event):
		&"cancel":
			Sfx.play("menu_cancel")
			_close_picker()
		&"confirm":
			var choice: Variant = _choices[_picker.index]
			if choice is GearData:
				_run.equip(_char, _slot, choice as GearData)
				Sfx.play("buff")
			elif String(choice) == "off":
				_run.unequip(_char, _slot)
				Sfx.play("menu_confirm")
			else:
				Sfx.play("menu_cancel")
			_close_picker()


func _open_picker() -> void:
	var worn: Variant = _run.gear[_char][_slot]
	_choices.clear()
	var items: Array[Dictionary] = []
	for item: GearData in _run.bag:
		_choices.append(item)
		items.append({"text": ("Swap for %s" if worn != null else "Put on %s") % item.display_name,
				"detail": item.description})
	if worn != null:
		_choices.append("off")
		items.append({"text": "Take off %s" % (worn as GearData).display_name, "detail": "It goes back to the bag."})
	if _choices.is_empty():
		Sfx.play("locked")
		return
	_choices.append("cancel")
	items.append({"text": "Cancel", "detail": ""})
	Sfx.play("menu_confirm")
	_picker.index = 0
	_picker.set_items(items, _detail)
	_picker.visible = true
	_bag.visible = false
	_redraw_hint()


func _close_picker() -> void:
	_picker.visible = false
	_bag.visible = true
	_redraw()


func _redraw() -> void:
	if _run.level >= _run.tuning.run_max_level:
		_level.text = "Level %d (max)" % _run.level
	else:
		_level.text = "Level %d    XP %d / %d" % [_run.level, _run.xp, _run.xp_to_next()]
	for slot: int in _rows.size():
		var selected_char := slot == _char
		_panels[slot].add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.PANEL_BG,
				HudStyle.GOLD if selected_char else HudStyle.PANEL_BORDER, 3 if selected_char else 2, 14))
		(_rows[slot].stats as Label).text = "HP %d / %d   Power %d   Speed %d" % [_run.hp[slot], _run.max_hp(slot),
				_run.power(slot), _run.speed(slot)]
		var labels: Array = _rows[slot].slots
		for g: int in labels.size():
			var item: Variant = _run.gear[slot][g]
			var selected := selected_char and g == _slot
			var label := labels[g] as Label
			label.text = ("> " if selected else "  ") + (item as GearData).display_name if item != null \
					else ("> " if selected else "  ") + EMPTY_TEXT
			label.label_settings.font_color = HudStyle.GOLD if selected else (HudStyle.TEXT if item != null else HudStyle.TEXT_DIM)
	var worn: Variant = _run.gear[_char][_slot]
	_detail.text = (worn as GearData).description if worn != null else "Empty slot."
	var names := PackedStringArray()
	for item: GearData in _run.bag:
		names.append(item.display_name)
	_bag.text = "Bag:  " + (", ".join(names) if not names.is_empty() else "empty")
	_redraw_hint()


func _redraw_hint() -> void:
	if _picker.visible:
		_hint.text = "Up/Down choose   %s select   %s back" % [HudStyle.binding_text(&"menu_confirm"),
				HudStyle.binding_text(&"menu_cancel")]
	else:
		_hint.text = "Left/Right character   Up/Down slot   %s change   %s done" % [
				HudStyle.binding_text(&"menu_confirm"), HudStyle.binding_text(&"menu_cancel")]


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)
