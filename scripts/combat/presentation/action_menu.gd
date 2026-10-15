class_name ActionMenu
extends PanelContainer
## The party member's action menu, Expedition 33 style: every pad button picks one thing. It sits
## in the bottom-left corner and grows upwards.
## - Main layer (user layout, 2026-10-13): every option has its own button and there is no cursor:
##   A Attack (gains AP; Confirm too), X Skills, Y Items, B Run, RT Team Ultimate (dim until it
##   can be used). Run must be HELD (run_hold_ms) so a tap never runs; its row fills up while held
##   (DESIGN.md 2.13).
## - Skills and Items layers: the class skills, or the backpack items usable in fights (DESIGN.md
##   8.1), open above the main options (name and AP cost, greyed with the reason when they cannot
##   be used now). Up/down choose, confirm uses, cancel (or the same button) goes back. An item
##   entry is flagged "item" and its ability is a stand-in made by the controller.
## - Target step: if the ability needs a choice of target (an enemy, an ally, a downed ally) and
##   there is more than one, left/right or up/down cycles, confirm picks, cancel goes back to the
##   layer the ability came from.
## Driven only by input actions (no focus-driven buttons, so the parry key can never click it).
## - Tutorial guide: with `guide` set (an ability id) only that choice can be made; its row (and
##   the Skills option that leads to it) glows, everything else is locked (DESIGN.md 7.8).
## The basic attack is the first entry that is not the team ultimate (CharacterData.all_abilities()
## puts it first), the ultimate is the entry flagged team_ultimate, the skills are the rest.

signal chosen(ability_id: String, target_id: int)
## The target being pointed at during the target step, or -1 when the step ends.
signal target_changed(target_id: int)

## The main options, in the order they are listed.
enum Option { ATTACK, SKILLS, ITEMS, RUN, ULTIMATE }

## The button that picks each Option. Run is the Back button (B), which has nothing else to do on
## the main layer.
const OPTION_ACTIONS: Array[StringName] = [&"fight_attack", &"fight_skills", &"fight_items", &"menu_cancel",
		&"fight_ultimate"]
## Options shown but not in the game yet (cards on the board).
const SOON_OPTIONS: Array[int] = []
const HOLD_TAG := "HOLD"
const NO_RUN_TAG := "CAN'T RUN"
## The ring around the Run button that fills while Back is held: size as a share of the button,
## line width in pixels.
const HOLD_RING_SHARE: float = 1.45
const HOLD_RING_WIDTH: float = 4.0
const HOLD_RING_TRACK := Color(1.0, 1.0, 1.0, 0.18)
const OPTION_NAMES: Array[String] = ["", "Skills", "Items", "Run", ""]
const SOON_TAG := "SOON"
const SKILLS_NAME := "Skills"
const SKILLS_TEXT := "Your class skills. They cost AP: attack and parry hits to gain it."
const NO_SKILLS_TEXT := "No class skills."
const ITEMS_TEXT := "Backpack items. Using one is your turn."
const NO_ITEMS_TEXT := "No items for fights in the backpack."
const READY_TAG := "READY"
const LOCKED_TAG := "LOCKED"

const TITLE_SIZE: int = 34
const OPTION_SIZE: int = 30
const TAG_SIZE: int = 20
const SKILL_SIZE: int = 28
const DESCRIPTION_SIZE: int = 22
const HINT_SIZE: int = 20
## Outer width. With MARGIN it ends near x = 484 on the 1920 canvas, clear of the party panels
## (from about x = 560).
const MENU_WIDTH: float = 460.0
const PADDING: int = 16
## Gap to the left and bottom edges of the screen.
const MARGIN: float = 24.0
## Side padding of each row (the gold bar's room).
const ROW_PAD_X: int = 10
const ROW_GAP: int = 12
## The button pictures sit in a column this wide so the option names line up.
const CHIP_COLUMN_WIDTH: float = 72.0
## A locked option's button picture fades to this.
const LOCKED_CHIP := Color(1.0, 1.0, 1.0, 0.4)
## While the skills list is open the main options step back to this.
const RESTING_OPTIONS := Color(1.0, 1.0, 1.0, 0.55)
## The tutorial's guided row pulses between white and this, once per GUIDE_PULSE_S.
const GUIDE_GLOW := Color(1.6, 1.45, 0.9)
const GUIDE_PULSE_S: float = 0.9

## The tutorial's one allowed choice (an ability id; "" = any). The controller also marks every
## other entry unusable; this only lights the way to it.
var guide: String = ""

var _title: Label
var _skills_box: VBoxContainer
var _skills_divider: Control
var _options_box: VBoxContainer
var _target_label: Label
var _description: Label
var _hint: HintBar
## Per Option: its row, the box holding its button picture, its name and its tag (AP, READY...).
var _option_rows: Array[PanelContainer] = []
var _option_chips: Array[Control] = []
var _option_names: Array[Label] = []
var _option_tags: Array[Label] = []
## Per skill (in _skill_entries order): its row, name and AP cost.
var _skill_rows: Array[PanelContainer] = []
var _skill_names: Array[Label] = []
var _skill_costs: Array[Label] = []
## Each: {ability: AbilityData, usable: bool, reason: String, targets: Array[int],
## pick_target: bool}.
var _entries: Array[Dictionary] = []
var _names: Dictionary = {}
## Indexes into _entries (-1: not offered).
var _attack_entry: int = -1
var _ultimate_entry: int = -1
var _run_entry: int = -1
## How long Back must be held to run (ms; the controller sets it from tuning run_hold_ms).
var run_hold_ms: int = 500
## When the Back hold started (Time ticks, ms), or -1 when Back is not held.
var _hold_started_ms: int = -1
var _hold_ring: HoldRing
## The list open in the skills box (the skills or the items), and both lists.
var _skill_entries: Array[int] = []
var _skills_all: Array[int] = []
var _items_all: Array[int] = []
## Which list is open (Option.SKILLS or Option.ITEMS).
var _listing: int = Option.SKILLS
## The highlighted main option (an Option).
var _option: int = Option.ATTACK
var _in_skills: bool = false
## The chosen skill (index into _skill_entries).
var _skill_cursor: int = 0
var _choosing_target: bool = false
## The entry whose target is being chosen.
var _target_entry: int = -1
var _target_index: int = 0
## The row last lit, so a newly lit row flashes once like the menus outside fights.
var _lit_row: Control = null
## Process frame of the last stick move (a held stick sends many motion events).
var _stick_frame: int = -1
## The guided row and its glow.
var _guide_row: Control = null
var _guide_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin_bottom_left()
	custom_minimum_size = Vector2(MENU_WIDTH, 0.0)
	add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.PANEL_BG, HudStyle.GOLD, 2, PADDING))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_title = HudStyle.make_title("", TITLE_SIZE)
	column.add_child(_title)
	_skills_box = VBoxContainer.new()
	_skills_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skills_box.add_theme_constant_override("separation", 2)
	column.add_child(_skills_box)
	_skills_divider = ListMenu.divider(_inner_width())
	column.add_child(_skills_divider)
	_options_box = VBoxContainer.new()
	_options_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_options_box.add_theme_constant_override("separation", 4)
	column.add_child(_options_box)
	for option: int in Option.size():
		_add_option_row(option)
	# A ring around the Run button fills up while Back is held (centred on the button).
	# It takes no room (size zero, centred by the chip column), so the row keeps its height.
	_hold_ring = HoldRing.new()
	_hold_ring.radius = float(OPTION_SIZE) * HudStyle.CHIP_HEIGHT_SHARE * HOLD_RING_SHARE * 0.5
	_option_chips[Option.RUN].add_child(_hold_ring)
	set_process(false)
	_target_label = HudStyle.make_label("", DESCRIPTION_SIZE, HudStyle.GOLD)
	column.add_child(_target_label)
	_description = HudStyle.make_label("", DESCRIPTION_SIZE)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(_inner_width(), 0.0)
	column.add_child(_description)
	_hint = HintBar.new([], HINT_SIZE)
	_hint.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_child(_hint)
	visible = false


## Opens the menu for one actor. `entries` as described on _entries; `names` maps fighter id ->
## display name (for the target step).
## `player` is the co-op player whose turn it is (-1 in solo: no tag).
func open(actor_name: String, accent: Color, entries: Array[Dictionary], names: Dictionary, player: int = -1) -> void:
	if _choosing_target:
		target_changed.emit(-1)
	_title.text = "%s's turn" % actor_name
	if player >= 0:
		_title.text += "  (%s)" % HudStyle.player_tag(player)
	_title.label_settings.font_color = accent.lightened(0.25)
	_entries = entries
	_names = names
	_sort_entries()
	_choosing_target = false
	_target_entry = -1
	_in_skills = false
	_hold_started_ms = -1
	_option = _home_option()
	_skill_cursor = 0
	_lit_row = null
	_build_skill_rows()
	_redraw()
	visible = true
	_redraw_guide()


func close() -> void:
	visible = false
	_redraw_guide()
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
	if _in_skills:
		return _handle_skills_input(event)
	return _handle_main_input(event)


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
		_show_entry(i)
		Sfx.play("menu_confirm")
		close()
		chosen.emit(ability_id, target_id if target_id >= 0 else _default_target(entry))
		return true
	return false


# --- input --------------------------------------------------------------------------------------

func _handle_main_input(event: InputEvent) -> bool:
	if _pressed(event, &"fight_skills"):
		_pick_option(Option.SKILLS)
	elif _pressed(event, &"fight_items"):
		_pick_option(Option.ITEMS)
	elif _pressed(event, &"fight_ultimate"):
		_pick_option(Option.ULTIMATE)
	elif _pressed(event, &"menu_cancel"):
		_start_hold()
	elif event.is_action_released(&"menu_cancel", true):
		_stop_hold()
	elif _pressed(event, &"fight_attack") or _pressed(event, &"menu_confirm"):
		# A is both Attack and Confirm: on this layer it always attacks.
		_pick_option(Option.ATTACK)
	else:
		return false
	return true


func _handle_skills_input(event: InputEvent) -> bool:
	if _pressed(event, &"menu_up"):
		_move_skill(-1)
	elif _pressed(event, &"menu_down"):
		_move_skill(1)
	elif _pressed(event, &"menu_confirm"):
		_use_entry(_skill_entries[_skill_cursor])
	elif _pressed(event, &"menu_cancel") or _pressed(event, OPTION_ACTIONS[_listing]):
		# The button that opened the list closes it.
		Sfx.play("menu_cancel")
		_in_skills = false
		_option = _home_option()
		_redraw()
	else:
		return false
	return true


func _handle_target_input(event: InputEvent) -> bool:
	var entry: Dictionary = _entries[_target_entry]
	var targets: Array = entry.targets
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
		chosen.emit((entry.ability as AbilityData).id, target)
	elif _pressed(event, &"menu_cancel"):
		Sfx.play("menu_cancel")
		_choosing_target = false
		target_changed.emit(-1)
		if not _in_skills:
			_option = _home_option()
		_redraw()
	else:
		return false
	return true


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


# --- choosing -----------------------------------------------------------------------------------

## Splits the entries into the basic attack, the team ultimate and the skills.
func _sort_entries() -> void:
	_attack_entry = -1
	_ultimate_entry = -1
	_run_entry = -1
	_skill_entries.clear()
	_skills_all.clear()
	_items_all.clear()
	for i: int in _entries.size():
		var ability := _entries[i].ability as AbilityData
		if bool(_entries[i].get("item", false)):
			_items_all.append(i)
		elif ability.escape:
			if _run_entry < 0:
				_run_entry = i
		elif ability.team_ultimate and _ultimate_entry < 0:
			_ultimate_entry = i
		elif not ability.team_ultimate and _attack_entry < 0:
			_attack_entry = i
		elif not ability.team_ultimate:
			_skills_all.append(i)
	_skill_entries = _skills_all.duplicate()
	_listing = Option.SKILLS


## Where the highlight rests when a layer opens or a step is backed out of: Attack, so the attack
## button (also a confirm button) always means Attack until the player moves the highlight.
func _home_option() -> int:
	return Option.ATTACK if _attack_entry >= 0 else Option.SKILLS


## The entry an option uses (-1 for Skills, which opens a list, or an option not offered).
func _option_entry(option: int) -> int:
	match option:
		Option.ATTACK:
			return _attack_entry
		Option.ULTIMATE:
			return _ultimate_entry
		Option.RUN:
			return _run_entry
	return -1


## Skills, Items and Run are always listed (dim when not usable); Attack and the ultimate only
## when offered.
func _option_shown(option: int) -> bool:
	return option in [Option.SKILLS, Option.ITEMS, Option.RUN] or _option_entry(option) >= 0


func _option_usable(option: int) -> bool:
	if option in SOON_OPTIONS:
		return false
	if option == Option.SKILLS:
		return not _skills_all.is_empty() and (guide.is_empty() or _skills_all.has(_guide_entry()))
	if option == Option.ITEMS:
		return not _items_all.is_empty() and (guide.is_empty() or _items_all.has(_guide_entry()))
	var entry := _option_entry(option)
	return entry >= 0 and bool(_entries[entry].usable)


func _pick_option(option: int) -> void:
	if not _option_shown(option) or option in SOON_OPTIONS:
		Sfx.play("locked")
		return
	_option = option
	if option != Option.SKILLS and option != Option.ITEMS:
		_use_entry(_option_entry(option))
		return
	var list := _skills_all if option == Option.SKILLS else _items_all
	if not _option_usable(option):
		Sfx.play("locked")
		_redraw()
		return
	Sfx.play("menu_move")
	if _listing != option or _skill_entries != list:
		_listing = option
		_skill_entries = list.duplicate()
		_skill_cursor = 0
		_build_skill_rows()
	_in_skills = true
	_skill_cursor = clampi(_skill_cursor, 0, _skill_entries.size() - 1)
	if not guide.is_empty():
		_skill_cursor = maxi(0, _skill_entries.find(_guide_entry()))
	_redraw()


## Starts holding Back as if the button went down (the autoplay bot runs this way).
func hold_run() -> void:
	if visible and not _in_skills and not _choosing_target:
		_start_hold()


## Back went down on the main layer: start filling the ring around the Run button (or refuse at
## once).
func _start_hold() -> void:
	if not _option_usable(Option.RUN):
		Sfx.play("locked")
		return
	_hold_started_ms = Time.get_ticks_msec()
	set_process(true)


## Drops a Back hold (the controller calls it before the lag calibration covers the menu).
func cancel_hold() -> void:
	if _hold_started_ms >= 0:
		_stop_hold()


func _notification(what: int) -> void:
	# Main stops the fight under the pause menu, so the Back release would never arrive here.
	if what == NOTIFICATION_DISABLED and _hold_started_ms >= 0:
		_stop_hold()


func _stop_hold() -> void:
	_hold_started_ms = -1
	if _hold_ring != null:
		_hold_ring.set_progress(0.0)


func _process(_delta: float) -> void:
	if _hold_started_ms < 0 or not visible or _in_skills or _choosing_target:
		if _hold_started_ms >= 0:
			_stop_hold()
		set_process(false)
		return
	var held := Time.get_ticks_msec() - _hold_started_ms
	_hold_ring.set_progress(clampf(float(held) / float(maxi(1, run_hold_ms)), 0.0, 1.0))
	if held >= run_hold_ms:
		_hold_started_ms = -1
		set_process(false)
		_hold_ring.set_progress(0.0)
		_pick_option(Option.RUN)


## Uses an entry: a target step if it needs a choice, else it is chosen at once.
func _use_entry(index: int) -> void:
	var entry: Dictionary = _entries[index]
	if not bool(entry.usable):
		Sfx.play("locked")
		_redraw()
		return
	var targets: Array = entry.targets
	if bool(entry.pick_target) and targets.size() > 1:
		Sfx.play("menu_move")
		_choosing_target = true
		_target_entry = index
		_target_index = 0
		_redraw()
		target_changed.emit(int(targets[_target_index]))
		return
	Sfx.play("menu_confirm")
	visible = false
	chosen.emit((entry.ability as AbilityData).id, _default_target(entry))


## Lights the option or skill row of an entry (the bot's picks show like a player's).
func _show_entry(index: int) -> void:
	if index == _attack_entry:
		_in_skills = false
		_option = Option.ATTACK
	elif index == _ultimate_entry:
		_in_skills = false
		_option = Option.ULTIMATE
	else:
		var listing := Option.ITEMS if _items_all.has(index) else Option.SKILLS
		if _listing != listing:
			_listing = listing
			_skill_entries = (_items_all if listing == Option.ITEMS else _skills_all).duplicate()
			_build_skill_rows()
		_in_skills = true
		_option = listing
		_skill_cursor = maxi(0, _skill_entries.find(index))
	_redraw()


func _default_target(entry: Dictionary) -> int:
	var targets: Array = entry.targets
	if not bool(entry.pick_target) or targets.is_empty():
		return -1
	return int(targets[0])


func _move_skill(step: int) -> void:
	if not guide.is_empty():
		# The tutorial allows one skill: the cursor stays on it.
		Sfx.play("locked")
		return
	_skill_cursor = wrapi(_skill_cursor + step, 0, _skill_entries.size())
	Sfx.play("menu_move")
	_redraw()


func _cycle_target(step: int) -> void:
	var targets: Array = _entries[_target_entry].targets
	_target_index = wrapi(_target_index + step, 0, targets.size())
	Sfx.play("menu_move")
	_redraw()
	target_changed.emit(int(targets[_target_index]))


# --- building and drawing -----------------------------------------------------------------------

## Bottom-left corner, growing up and right. CombatHud sets other anchors before adding the menu;
## this runs when it is added, so it wins. The offsets make a zero-size box at the corner, so the
## panel always takes exactly its content's size and shrinks again when the skills list closes.
func _pin_bottom_left() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = MARGIN
	offset_right = MARGIN
	offset_top = -MARGIN
	offset_bottom = -MARGIN


func _inner_width() -> float:
	return MENU_WIDTH - 2.0 * float(PADDING)


## One main option: its button picture (follows keyboard or pad), its name and a tag on the right.
func _add_option_row(option: int) -> void:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", ROW_GAP)
	row.add_child(line)
	var chips := CenterContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.custom_minimum_size = Vector2(CHIP_COLUMN_WIDTH, 0.0)
	chips.add_child(HintBar.new([[OPTION_ACTIONS[option], ""]], OPTION_SIZE, HudStyle.TEXT))
	line.add_child(chips)
	var label := HudStyle.make_label("", OPTION_SIZE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(label)
	var tag := HudStyle.make_label("", TAG_SIZE)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(tag)
	_options_box.add_child(row)
	_option_rows.append(row)
	_option_chips.append(chips)
	_option_names.append(label)
	_option_tags.append(tag)


func _build_skill_rows() -> void:
	for row: PanelContainer in _skill_rows:
		_skills_box.remove_child(row)
		row.queue_free()
	_skill_rows.clear()
	_skill_names.clear()
	_skill_costs.clear()
	for i: int in _skill_entries.size():
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", ROW_GAP)
		row.add_child(line)
		var label := HudStyle.make_label("", SKILL_SIZE)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		var cost := HudStyle.make_label("", SKILL_SIZE)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(cost)
		_skills_box.add_child(row)
		_skill_rows.append(row)
		_skill_names.append(label)
		_skill_costs.append(cost)


func _redraw() -> void:
	var lit := _redraw_options()
	var lit_skill := _redraw_skills()
	if lit_skill != null:
		lit = lit_skill
	if lit != _lit_row:
		_lit_row = lit
		if lit != null and visible:
			# The newly chosen row lights up for a moment, like ListMenu's rows.
			lit.modulate = ListMenu.SELECTED_FLASH
			lit.create_tween().tween_property(lit, "modulate", Color.WHITE, ListMenu.SELECTED_FLASH_S)
	_redraw_footer()
	_redraw_guide()


## The tutorial's guided row pulses: the option leading to it, or the skill in the open list.
func _redraw_guide() -> void:
	var row: Control = null
	if not guide.is_empty() and visible and not _choosing_target:
		var index := _guide_entry()
		if _in_skills and _skill_entries.has(index):
			row = _skill_rows[_skill_entries.find(index)]
		elif not _in_skills and _guide_option() >= 0:
			row = _option_rows[_guide_option()]
	if row == _guide_row:
		return
	if _guide_tween != null:
		_guide_tween.kill()
		_guide_tween = null
	if is_instance_valid(_guide_row):
		_guide_row.modulate = Color.WHITE
	_guide_row = row
	if row == null:
		return
	_guide_tween = row.create_tween().set_loops()
	_guide_tween.tween_property(row, "modulate", GUIDE_GLOW, GUIDE_PULSE_S * 0.5).set_trans(Tween.TRANS_SINE)
	_guide_tween.tween_property(row, "modulate", Color.WHITE, GUIDE_PULSE_S * 0.5).set_trans(Tween.TRANS_SINE)


## The entry the tutorial allows (-1: none).
func _guide_entry() -> int:
	if guide.is_empty():
		return -1
	for i: int in _entries.size():
		if (_entries[i].ability as AbilityData).id == guide:
			return i
	return -1


## The main option that leads to the tutorial's choice (-1: none).
func _guide_option() -> int:
	var index := _guide_entry()
	if index < 0:
		return -1
	if index == _attack_entry:
		return Option.ATTACK
	if index == _ultimate_entry:
		return Option.ULTIMATE
	if index == _run_entry:
		return Option.RUN
	return Option.ITEMS if _items_all.has(index) else Option.SKILLS


## Draws the main options; returns the lit row.
func _redraw_options() -> Control:
	_options_box.modulate = RESTING_OPTIONS if _in_skills else Color.WHITE
	var lit_row: Control = null
	for option: int in Option.size():
		var row := _option_rows[option]
		row.visible = _option_shown(option)
		if not row.visible:
			continue
		# No cursor on this layer: each option has its own button. The tutorial lights its choice.
		var lit := option == _guide_option()
		var usable := _option_usable(option)
		var entry := _option_entry(option)
		var ability: AbilityData = (_entries[entry].ability as AbilityData) if entry >= 0 else null
		_option_names[option].text = ability.display_name if ability != null else OPTION_NAMES[option]

		var tag := ""
		var tag_color := HudStyle.AP_TEXT
		if option == Option.ULTIMATE:
			tag = READY_TAG if usable else LOCKED_TAG
			tag_color = HudStyle.GAUGE_FILL
		elif option in SOON_OPTIONS:
			tag = SOON_TAG
		elif option == Option.RUN:
			tag = HOLD_TAG if usable else NO_RUN_TAG
		elif option == Option.ITEMS:
			tag = str(_items_all.size()) if usable else ""
		elif ability != null:
			tag = _cost_text(ability)
		var color := HudStyle.TEXT
		if not usable:
			color = HudStyle.TEXT_DIM.lightened(0.15) if lit else HudStyle.TEXT_DIM
			tag_color = HudStyle.TEXT_DIM
		elif lit:
			color = HudStyle.GOLD
		elif option == Option.ULTIMATE:
			color = HudStyle.GAUGE_FILL
		_option_names[option].label_settings.font_color = color
		_option_tags[option].text = tag
		_option_tags[option].label_settings.font_color = tag_color
		_option_chips[option].modulate = Color.WHITE if usable else LOCKED_CHIP
		# The chosen option is lit with the same gold bar as the menus outside fights.
		row.add_theme_stylebox_override("panel", ListMenu.row_style(lit, ROW_PAD_X))
		if lit:
			lit_row = row
	return lit_row


## Draws the skills list (shown only in the skills layer); returns the lit row, or null.
func _redraw_skills() -> Control:
	_skills_box.visible = _in_skills
	_skills_divider.visible = _in_skills
	if not _in_skills:
		return null
	var lit_row: Control = null
	for i: int in _skill_rows.size():
		var entry: Dictionary = _entries[_skill_entries[i]]
		var ability := entry.ability as AbilityData
		var lit := i == _skill_cursor
		var usable := bool(entry.usable)
		_skill_names[i].text = ability.display_name
		_skill_costs[i].text = _cost_text(ability)
		var color := HudStyle.TEXT
		if not usable:
			color = HudStyle.TEXT_DIM.lightened(0.15) if lit else HudStyle.TEXT_DIM
		elif lit:
			color = HudStyle.GOLD
		_skill_names[i].label_settings.font_color = color
		_skill_costs[i].label_settings.font_color = HudStyle.AP_TEXT if usable else color
		_skill_rows[i].add_theme_stylebox_override("panel", ListMenu.row_style(lit, ROW_PAD_X))
		if lit:
			lit_row = _skill_rows[i]
	return lit_row


## The description of what is highlighted, the target being chosen and the button hints.
func _redraw_footer() -> void:
	var entry_index := _focused_entry()
	if entry_index >= 0:
		var entry: Dictionary = _entries[entry_index]
		var text := (entry.ability as AbilityData).description
		if not bool(entry.usable):
			text += "\n" + String(entry.reason)
		_description.text = text
	elif _listing == Option.ITEMS:
		_description.text = ITEMS_TEXT if not _items_all.is_empty() else NO_ITEMS_TEXT
	else:
		_description.text = SKILLS_TEXT if not _skills_all.is_empty() else NO_SKILLS_TEXT
	_target_label.visible = _choosing_target
	if _choosing_target:
		var target := int((_entries[_target_entry].targets as Array)[_target_index])
		_target_label.text = "Target: %s" % String(_names.get(target, "?"))
		# Kept to two hints so the row fits the panel's width with keyboard key names.
		_hint.set_entries([[&"@leftright", "Target"], [&"menu_cancel", "Back"]])
	elif _in_skills:
		_hint.set_entries([[&"@updown", "Choose"], [&"menu_confirm", "Use"], [&"menu_cancel", "Back"]])
	else:
		# Each option shows its own button: no extra hints.
		_hint.set_entries([])
	_hint.visible = _choosing_target or _in_skills
	# The main layer has no cursor, so nothing to describe until a skill or target is chosen.
	_description.visible = _choosing_target or _in_skills


## The entry whose description shows (-1: the Skills option itself is highlighted).
func _focused_entry() -> int:
	if _choosing_target:
		return _target_entry
	if _in_skills:
		return _skill_entries[_skill_cursor] if not _skill_entries.is_empty() else -1
	return _option_entry(_option)


## "2 AP" for a skill that costs AP, "+1 AP" for one that gives it, else "".
func _cost_text(ability: AbilityData) -> String:
	if ability.ap_cost > 0:
		return "%d AP" % ability.ap_cost
	if ability.ap_gain > 0:
		return "+%d AP" % ability.ap_gain
	return ""


## A ring around the Run button that fills clockwise from the top while Back is held.
class HoldRing extends Control:
	## Drawn around this control's middle; the control itself has no size.
	var radius: float = 24.0
	var _progress: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_progress(value: float) -> void:
		if is_equal_approx(value, _progress):
			return
		_progress = value
		queue_redraw()

	func _draw() -> void:
		if _progress <= 0.0:
			return
		var centre := size * 0.5
		draw_arc(centre, radius, 0.0, TAU, 48, ActionMenu.HOLD_RING_TRACK, ActionMenu.HOLD_RING_WIDTH, true)
		var start := -PI * 0.5
		draw_arc(centre, radius, start, start + TAU * _progress, 48, HudStyle.JUMP, ActionMenu.HOLD_RING_WIDTH, true)
