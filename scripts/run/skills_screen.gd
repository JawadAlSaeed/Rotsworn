class_name SkillsScreen
extends CanvasLayer
## A hero's skill tree (DESIGN.md 8.4, card #136), opened from the party screen (K / RT). The
## branches stand side by side, each a column of skills from the top down. A skill is brought
## into fights (gold), known, ready to learn (its cost in skill points) or locked (the one above
## it is not known yet). Arrows move; Confirm learns the skill, or brings / leaves a known one
## (at most tuning.skill_slots); LB / RB (Z / C) changes hero; Back closes. Online, a client's
## changes go to the host as RunState ops (op_requested).

signal done
## Online client: a change for the host to make (RunState.apply_op data).
signal op_requested(op: Dictionary)

const TITLE_SIZE: int = 52
const NAME_SIZE: int = 40
const TEXT_SIZE: int = 28
const SMALL_SIZE: int = 24
const CELL_WIDTH: float = 330.0
const COLUMN_GAP: int = 22
const INFO_WIDTH: float = 1050.0

enum State { BRINGING, KNOWN, LEARNABLE, LOCKED }
const STATE_TEXT: Array[String] = ["Bringing", "Known", "Learn: %d pt", "Locked"]

## Online client: changes are asked of the host instead of made here.
var remote: bool = false
var _run: RunState
var _hero: int = 0
var _cursor := Vector2i.ZERO
var _name: Label
var _status: Label
var _columns: HBoxContainer
## [branch][tier] -> {panel, name, state}.
var _cells: Array = []
var _info_title: Label
var _info: Label
var _note: Label
var _hint: HintBar


func setup(run: RunState, hero: int) -> void:
	_run = run
	_hero = clampi(hero, 0, run.party_size() - 1)
	if not run.has_tree(_hero):
		_hero = _next_hero_with_tree(_hero, 1)
	var column := ListMenu.screen_column(self, "Skills", TITLE_SIZE)
	_name = HudStyle.make_title("", NAME_SIZE)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_name)
	_status = ListMenu.centred_label("", TEXT_SIZE, HudStyle.GOLD)
	column.add_child(_status)
	_columns = HBoxContainer.new()
	_columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_columns.alignment = BoxContainer.ALIGNMENT_CENTER
	_columns.add_theme_constant_override("separation", COLUMN_GAP)
	column.add_child(_columns)
	var info_panel := PanelContainer.new()
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	info_panel.custom_minimum_size.x = INFO_WIDTH
	info_panel.add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.PANEL_BG, HudStyle.PANEL_BORDER, 2, 14))
	column.add_child(info_panel)
	var info_box := VBoxContainer.new()
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.add_child(info_box)
	_info_title = HudStyle.make_label("", TEXT_SIZE, HudStyle.GOLD)
	info_box.add_child(_info_title)
	_info = HudStyle.make_label("", SMALL_SIZE, HudStyle.TEXT_DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = INFO_WIDTH - 40.0
	info_box.add_child(_info)
	_note = ListMenu.centred_label("", SMALL_SIZE, HudStyle.TEXT)
	column.add_child(_note)
	_hint = ListMenu.screen_footer(self, [])
	_build_tree()
	_redraw()


## The run changed (online, another player's change arrived): redraw.
func refresh() -> void:
	_redraw()


func close() -> void:
	done.emit()


# --- building ---------------------------------------------------------------------------------

func _build_tree() -> void:
	for child: Node in _columns.get_children():
		child.queue_free()
	_cells.clear()
	var tree := _run.tree(_hero)
	if tree == null:
		return
	for branch: SkillBranchData in tree.branches:
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 8)
		_columns.add_child(box)
		var head := HudStyle.make_title(branch.display_name if branch != null else "", TEXT_SIZE, HudStyle.TEXT_DIM)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(head)
		var cells: Array = []
		if branch != null:
			for skill: AbilityData in branch.skills:
				var panel := PanelContainer.new()
				panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
				panel.custom_minimum_size.x = CELL_WIDTH
				var inner := VBoxContainer.new()
				inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
				panel.add_child(inner)
				var name := HudStyle.make_label(skill.display_name if skill != null else "?", TEXT_SIZE)
				inner.add_child(name)
				var state := HudStyle.make_label("", SMALL_SIZE, HudStyle.TEXT_DIM)
				inner.add_child(state)
				box.add_child(panel)
				cells.append({"panel": panel, "name": name, "state": state, "skill": skill})
		_cells.append(cells)
	_clamp_cursor()


# --- input ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
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
		_handled()
		_confirm()
		return
	elif _pressed(event, &"item_turn_left") or _pressed(event, &"item_turn_right"):
		_handled()
		var next := _next_hero_with_tree(_hero, -1 if event.is_action(&"item_turn_left") else 1)
		if next != _hero:
			_hero = next
			_note.text = ""
			Sfx.play("menu_move")
			_build_tree()
			_redraw()
		return
	elif _pressed(event, &"menu_cancel") or _pressed(event, &"party_menu") or _pressed(event, &"party_skills"):
		_handled()
		Sfx.play("menu_cancel")
		close()
		return
	else:
		return
	_handled()
	if _cells.is_empty():
		return
	_cursor.x = wrapi(_cursor.x + step.x, 0, _cells.size())
	_cursor.y += step.y
	_clamp_cursor()
	Sfx.play("menu_move")
	_redraw()


func _confirm() -> void:
	var skill := _selected()
	if skill == null:
		return
	match _state_of(skill):
		State.LEARNABLE:
			_ask({"op": "unlock", "slot": _hero, "ability": skill.id})
			_note.text = "%s learned %s." % [_run.data.party[_hero].display_name, skill.display_name]
			Sfx.play("level_up")
		State.BRINGING:
			var ids: Array = _run.loadout[_hero].duplicate()
			ids.erase(skill.id)
			_ask({"op": "loadout", "slot": _hero, "abilities": ids})
			_note.text = "%s stays behind." % skill.display_name
			Sfx.play("menu_cancel")
		State.KNOWN:
			if _run.loadout[_hero].size() >= _run.tuning.skill_slots:
				_note.text = "Already bringing %d skills: leave one behind first." % _run.tuning.skill_slots
				Sfx.play("locked")
			else:
				var ids: Array = _run.loadout[_hero].duplicate()
				ids.append(skill.id)
				_ask({"op": "loadout", "slot": _hero, "abilities": ids})
				_note.text = "Bringing %s." % skill.display_name
				Sfx.play("menu_confirm")
		_:
			Sfx.play("locked")
	_redraw()


## Makes a change: here, or (online client) by asking the host.
func _ask(op: Dictionary) -> void:
	if remote:
		op_requested.emit(op)
	else:
		_run.apply_op(op)


# --- state ------------------------------------------------------------------------------------

func _state_of(skill: AbilityData) -> State:
	if _run.loadout[_hero].has(skill.id):
		return State.BRINGING
	if _run.unlocked[_hero].has(skill.id):
		return State.KNOWN
	if _run.can_unlock(_hero, skill.id):
		return State.LEARNABLE
	return State.LOCKED


func _selected() -> AbilityData:
	if _cells.is_empty() or _cursor.x >= _cells.size() or (_cells[_cursor.x] as Array).is_empty():
		return null
	return (_cells[_cursor.x][_cursor.y] as Dictionary).skill as AbilityData


func _clamp_cursor() -> void:
	if _cells.is_empty():
		_cursor = Vector2i.ZERO
		return
	_cursor.x = clampi(_cursor.x, 0, _cells.size() - 1)
	_cursor.y = clampi(_cursor.y, 0, maxi(0, (_cells[_cursor.x] as Array).size() - 1))


## The next hero (in `step` direction) who has a skill tree (`from` itself if nobody else has one).
func _next_hero_with_tree(from: int, step: int) -> int:
	for i: int in range(1, _run.party_size() + 1):
		var slot := posmod(from + i * step, _run.party_size())
		if _run.has_tree(slot):
			return slot
	return from


# --- drawing ----------------------------------------------------------------------------------

func _redraw() -> void:
	var c := _run.data.party[_hero]
	_name.text = c.display_name
	_name.label_settings.font_color = c.color.lightened(0.25)
	_status.text = "Level %d    Skill points: %d    Bringing %d of %d" % [_run.levels[_hero], _run.free_skill_points(_hero),
			_run.loadout[_hero].size(), _run.tuning.skill_slots]
	for b: int in _cells.size():
		for t: int in (_cells[b] as Array).size():
			var cell: Dictionary = _cells[b][t]
			var skill := cell.skill as AbilityData
			var state := _state_of(skill) if skill != null else State.LOCKED
			var chosen := Vector2i(b, t) == _cursor
			var border := HudStyle.GOLD if chosen else HudStyle.PANEL_BORDER
			(cell.panel as PanelContainer).add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.PANEL_BG, border,
					3 if chosen else 2, 10))
			var text := STATE_TEXT[state]
			if state == State.LEARNABLE:
				text = text % _run.skill_cost(_hero, skill.id) + ("s" if _run.skill_cost(_hero, skill.id) != 1 else "")
			elif state == State.LOCKED and skill != null and _run.tree(_hero).parent_of(skill.id) != null \
					and _run.unlocked[_hero].has(_run.tree(_hero).parent_of(skill.id).id):
				text = "Needs %d pt" % _run.skill_cost(_hero, skill.id)
			(cell.state as Label).text = text
			var colors := [HudStyle.GOLD, HudStyle.TEXT, HudStyle.HEAL, HudStyle.TEXT_DIM]
			(cell.name as Label).label_settings.font_color = colors[state] if state != State.LOCKED else HudStyle.TEXT_DIM
			(cell.state as Label).label_settings.font_color = colors[state]
	var skill := _selected()
	if skill == null:
		_info_title.text = "No skill tree"
		_info.text = "This hero has every skill already."
	else:
		_info_title.text = "%s   (%d AP)" % [skill.display_name, skill.ap_cost]
		_info.text = skill.description
	var entries: Array = [[&"@arrows", "Move"], [&"menu_confirm", _confirm_text(skill)]]
	if _run.party_size() > 1:
		entries.append([&"item_turn_left", "Hero"])
		entries.append([&"item_turn_right", "Hero"])
	entries.append([&"menu_cancel", "Done"])
	_hint.set_entries(entries)


func _confirm_text(skill: AbilityData) -> String:
	if skill == null:
		return "Select"
	match _state_of(skill):
		State.LEARNABLE:
			return "Learn"
		State.BRINGING:
			return "Leave behind"
		State.KNOWN:
			return "Bring"
	return "Select"


func _handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)
