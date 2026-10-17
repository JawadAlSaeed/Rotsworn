class_name PartyScreen
extends CanvasLayer
## The party screen and the shared backpack (DESIGN.md 8.1), opened with Tab / Y from the map or a
## zone, after a guard's loot, and from a shop. Left: every hero, one card each (stats and the
## gear they wear), and what the cursor is on. Right: the backpack. The cursor moves between the
## gear slots and the grid. Confirm on gear picks it up to put on another slot or hero (swapping);
## Confirm on an item opens Use / Move / Sell (in a shop) / Throw away; Use on one hero moves the
## cursor to the hero cards to pick who. X / R picks an item straight up to move it and puts it
## down again; LB / RB (Z / C) turn the item in hand. It goes down where it fits, or onto the same item to combine them into a
## stronger one. Charms that boost each other show a gold link where they touch. Gear never goes
## into the backpack.
## The screen can open with something new in hand (loot, a find that did not fit): new gear must
## be worn (a full slot sells what was there) or sold; a new item placed, swapped with the one item
## it covers, or left behind. Online, a client's changes go to the host as RunState ops
## (op_requested); the host's run state comes back and refresh() redraws.
## Each hero card ends in two buttons after the gear slots (user request 2026-10-15): Attributes
## (DESIGN.md 8.2) and Skills (8.4, heroes with a tree), each showing the points left to spend;
## Confirm on one opens that screen for the hero (T / K still work as shortcuts). The info box
## under the cards only shows while it has something to say: an item menu, picking who to use an
## item on, something in hand, or the backpack item under the cursor.

signal done
## A new item in hand was left behind (it is not in the backpack).
signal left_behind(item: ItemData)
## Online client: a change for the host to make (RunState.apply_op data).
signal op_requested(op: Dictionary)

enum Focus { GEAR, GRID }

const TITLE_SIZE: int = 52
const TEXT_SIZE: int = 28
const SMALL_SIZE: int = 24
const NAME_SIZE: int = 40
## Gear slot and button text on the hero cards (a little bigger than the rest of the screen).
const CARD_TEXT_SIZE: int = 27
const LEFT_WIDTH: float = 1060.0
const PORTRAIT_PX: float = 112.0
const PORTRAIT_GAP: int = 14
const COLUMN_GAP: int = 48
const SLOT_WIDTH: float = 200.0
## A hero card that cannot take the item in hand is drawn this see-through.
const GREYED_ALPHA: float = 0.5
## The Attributes and Skills buttons at the end of a card.
const BUTTON_WIDTH: float = 175.0
const BUTTON_GAP: int = 18
const SLOT_PAD_X: int = 6
const EMPTY_TEXT := "(empty)"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const CHARM_LINE_WIDTH: float = 520.0

## Choosing who gets an item (the uid; -1: not choosing): the cursor is on the hero cards.
var _use_uid: int = -1
## Online client: changes are asked of the host instead of made here.
var remote: bool = false
## Close by itself once the new thing in hand is placed, worn or left (shop and zone finds).
var close_when_settled: bool = false
## Opened from a shop: items can be sold (DESIGN.md 8.1).
var shop_mode: bool = false
var _run: RunState
var _hero: int = 0
var _focus: Focus = Focus.GEAR
var _slot: int = 0
## In hand: {} or {kind: "gear", item: GearData, from: [hero, gear slot] or [] (new)}
## or {kind: "item", item: ItemData, uid: int (-1: new), turn: int, level: int}.
var _held: Dictionary = {}
var _note_text: String = ""
var _level: Label
var _note: Label
## One card per hero: {panel: PanelContainer, stats: Label, slots: Array[Label]}.
var _cards: Array[Dictionary] = []
var _info_panel: PanelContainer
var _info_title: Label
var _info: Label
var _pack_label: Label
## What the charms in the backpack add up to (and the rot), under the backpack's title.
var _charm_label: Label
var _grid: BackpackGrid
var _menu: ListMenu
## Choices of the open item menu: [kind, slot] pairs ("use", "move", "drop", "cancel").
var _menu_choices: Array = []
var _prompt: ConfirmPrompt
var _hint: HintBar
## The attributes screen while it is open over this one.
var _attrs: AttributesScreen
## The skills screen (heroes with a skill tree, DESIGN.md 8.4) while it is open over this one.
var _skills: SkillsScreen


## `note`: a line at the top (for example what was just found). `held`: something new in hand,
## {gear: GearData} or {item: ItemData}.
func setup(run: RunState, note: String = "", held: Dictionary = {}) -> void:
	_run = run
	_note_text = note
	var column := ListMenu.screen_column(self, "Party", TITLE_SIZE)
	_level = ListMenu.centred_label("", TEXT_SIZE, HudStyle.GOLD)
	column.add_child(_level)
	_note = ListMenu.centred_label("", TEXT_SIZE)
	column.add_child(_note)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", COLUMN_GAP)
	column.add_child(row)
	row.add_child(_build_hero_side())
	row.add_child(_build_pack_side())
	_hint = ListMenu.screen_footer(self, [])
	if held.get("gear") is GearData:
		_held = {"kind": "gear", "item": held.gear, "from": []}
	elif held.get("item") is ItemData:
		_held = {"kind": "item", "item": held.item, "uid": -1, "turn": 0, "level": 0}
		_focus = Focus.GRID
		_grid.cursor = Vector2i.ZERO
		_clamp_cursor()
	if not _held.is_empty() and _held.kind == "gear":
		# New gear goes on whoever has room first.
		for slot: int in run.party_size():
			if run.free_gear_slot(slot) >= 0:
				_hero = slot
				_slot = run.free_gear_slot(slot)
				break
	_redraw()


## The run changed (online, another player's change arrived): redraw. Something in hand that is
## no longer where it was (someone else moved or used it) is let go.
func refresh() -> void:
	if not _held.is_empty() and _held.kind == "item" and int(_held.uid) >= 0 and not _run.backpack.has_uid(int(_held.uid)):
		_held = {}
	if not _held.is_empty() and _held.kind == "gear" and not (_held.from as Array).is_empty():
		var from: Array = _held.from
		if _run.gear[int(from[0])][int(from[1])] != _held.item:
			_held = {}
	_grid.setup(_run.backpack, _visuals())
	_clamp_cursor()
	_redraw()
	if _attrs != null:
		_attrs.refresh()
	if _skills != null:
		_skills.refresh()


## Something new is in hand (loot, a find, a swap).
func holding_new() -> bool:
	return not _held.is_empty() and ((_held.kind == "gear" and (_held.from as Array).is_empty())
			or (_held.kind == "item" and int(_held.uid) < 0))


## The bot (and tests): settles what is in hand the simple way. New gear goes on whoever has the
## most free slots (or is sold when nobody has room); a new item goes wherever it fits (or is left).
func auto_settle() -> void:
	if _held.is_empty():
		return
	if _held.kind == "gear":
		var best := -1
		var free := 0
		for slot: int in _run.party_size():
			var empty := _run.gear[slot].count(null)
			if empty > free:
				best = slot
				free = empty
		if best >= 0:
			_run.wear(best, _run.free_gear_slot(best), _held.item as GearData)
		else:
			_run.sell_new_gear(_held.item as GearData)
	elif int(_held.uid) < 0 and _run.add_item(_held.item as ItemData) < 0:
		left_behind.emit(_held.item as ItemData)
	_held = {}
	_redraw()
	_settled()


func close() -> void:
	done.emit()


# --- building ---------------------------------------------------------------------------------

func _build_hero_side() -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size.x = LEFT_WIDTH
	# Top-aligned, so the cards never move when the info box shows or hides under them.
	box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_theme_constant_override("separation", 12)
	for slot: int in _run.party_size():
		box.add_child(_build_card(slot))
	_info_panel = PanelContainer.new()
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.PANEL_BG, HudStyle.PANEL_BORDER, 2, 14))
	box.add_child(_info_panel)
	var info_box := VBoxContainer.new()
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_theme_constant_override("separation", 6)
	_info_panel.add_child(info_box)
	_info_title = HudStyle.make_label("", TEXT_SIZE, HudStyle.GOLD)
	info_box.add_child(_info_title)
	_info = HudStyle.make_label("", SMALL_SIZE, HudStyle.TEXT_DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(LEFT_WIDTH - 40.0, SMALL_SIZE * 3)
	info_box.add_child(_info)
	_menu = ListMenu.new()
	_menu.item_size = TEXT_SIZE
	_menu.centred = false
	_menu.row_width = LEFT_WIDTH - 40.0
	_menu.visible = false
	info_box.add_child(_menu)
	return box


## A hero's card: portrait, name and stats, then their gear slots side by side and the
## Attributes and Skills buttons.
func _build_card(slot: int) -> Control:
	var c := _run.data.party[slot]
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", PORTRAIT_GAP)
	panel.add_child(row)
	var face := AssetLoader.texture(c.portrait_path, Vector2i(48, 48))
	var portrait := HudStyle.portrait_frame(face, c.color, PORTRAIT_PX)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(portrait)
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 16)
	right.add_child(head)
	var name_label := HudStyle.make_title(c.display_name, NAME_SIZE, c.color.lightened(0.25))
	head.add_child(name_label)
	var stats := HudStyle.make_label("", SMALL_SIZE, HudStyle.TEXT_DIM)
	stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(stats)
	var slots_row := HBoxContainer.new()
	slots_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots_row.add_theme_constant_override("separation", 6)
	right.add_child(slots_row)
	var labels: Array[Label] = []
	for g: int in _run.tuning.run_gear_slots:
		var label := HudStyle.make_label("", CARD_TEXT_SIZE)
		label.custom_minimum_size.x = SLOT_WIDTH
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		slots_row.add_child(label)
		labels.append(label)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size.x = BUTTON_GAP
	slots_row.add_child(gap)
	var buttons: Array[Label] = []
	for i: int in (2 if _run.has_tree(slot) else 1):
		var button := HudStyle.make_label("", CARD_TEXT_SIZE)
		button.custom_minimum_size.x = BUTTON_WIDTH
		button.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slots_row.add_child(button)
		buttons.append(button)
	_cards.append({"panel": panel, "stats": stats, "slots": labels, "buttons": buttons})
	return panel


## The card cursor's place of the Attributes button (the Skills button is the next one).
func _attributes_slot() -> int:
	return _run.tuning.run_gear_slots


## The last place on hero `hero`'s card: their Skills button, or Attributes without a tree.
func _last_slot(hero: int) -> int:
	return _attributes_slot() + (1 if _run.has_tree(hero) else 0)


func _on_button() -> bool:
	return _slot >= _attributes_slot()


func _build_pack_side() -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 10)
	_pack_label = HudStyle.make_label("", TEXT_SIZE, HudStyle.GOLD)
	box.add_child(_pack_label)
	_charm_label = HudStyle.make_label("", SMALL_SIZE, HudStyle.TEXT_DIM)
	_charm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_charm_label.custom_minimum_size.x = CHARM_LINE_WIDTH
	box.add_child(_charm_label)
	_grid = BackpackGrid.new()
	box.add_child(_grid)
	_grid.setup(_run.backpack, _visuals())
	return box


func _visuals() -> CombatVisuals:
	var visuals := load(VISUALS_PATH) as CombatVisuals
	return visuals if visuals != null else CombatVisuals.new()


# --- input ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _prompt != null or _attrs != null or _skills != null:
		return
	if _menu.visible:
		_menu_input(event)
		return
	if _use_uid >= 0:
		_target_input(event)
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
	elif _pressed(event, &"item_move"):
		_handled()
		_move_button()
		return
	elif _pressed(event, &"item_turn_left") or _pressed(event, &"item_turn_right"):
		_handled()
		_turn_held(-1 if event.is_action(&"item_turn_left") else 1)
		return
	elif _pressed(event, &"party_attributes"):
		_handled()
		open_attributes()
		return
	elif _pressed(event, &"party_skills") and _any_tree():
		_handled()
		open_skills()
		return
	elif _pressed(event, &"menu_confirm"):
		_handled()
		_confirm()
		return
	elif _pressed(event, &"menu_cancel") or _pressed(event, &"party_menu"):
		_handled()
		_cancel()
		return
	else:
		return
	_handled()
	_move(step)


func _move(step: Vector2i) -> void:
	var last_slot := _last_slot(_hero)
	if _focus == Focus.GEAR:
		if step.x > 0 and _slot >= last_slot:
			if not _held.is_empty() and _held.kind == "gear":
				Sfx.play("item_no_room")
				_note_text = "Gear is worn, never carried in the backpack."
				_redraw()
				return
			_focus = Focus.GRID
			_grid.cursor = Vector2i(0, _hero_row(_hero))
			_clamp_cursor()
		elif step.x != 0:
			if _slot + step.x < 0:
				return
			_slot += step.x
		else:
			_hero = wrapi(_hero + step.y, 0, _run.party_size())
			_slot = mini(_slot, _last_slot(_hero))
	else:
		var to := _grid.cursor + step
		if to.x < 0:
			if not _held.is_empty():
				return
			_focus = Focus.GEAR
			_hero = _row_hero(_grid.cursor.y)
			_slot = _last_slot(_hero)
		else:
			_grid.cursor = to
			_clamp_cursor()
	Sfx.play("menu_move")
	_redraw()


## The grid row level with a hero's card, and the hero level with a grid row (moving across).
func _hero_row(hero: int) -> int:
	if _run.party_size() <= 1:
		return 0
	return roundi(float(hero) * float(_run.backpack.rows - 1) / float(_run.party_size() - 1))


func _row_hero(row: int) -> int:
	if _run.backpack.rows <= 1:
		return 0
	return clampi(roundi(float(row) * float(_run.party_size() - 1) / float(_run.backpack.rows - 1)), 0,
			_run.party_size() - 1)


## X / R: with nothing in hand it picks up the item (or gear) under the cursor to move it, no
## menu; with something in hand it puts it down (like Confirm).
func _move_button() -> void:
	if _held.is_empty():
		_lift_here()
	else:
		_confirm()


## LB / RB (Z / C): turns the item in hand a quarter turn left or right.
func _turn_held(step: int) -> void:
	if _held.is_empty() or _held.kind != "item":
		return
	_held.turn = posmod(int(_held.turn) + step, 4)
	_clamp_cursor()
	Sfx.play("item_turn")
	_redraw()


func _lift_here() -> void:
	if _focus == Focus.GEAR:
		_confirm_gear()
		return
	var uid := _run.backpack.uid_at(_grid.cursor)
	if uid < 0:
		Sfx.play("locked")
		return
	var e := _run.backpack.entry(uid)
	_held = {"kind": "item", "item": e.item, "uid": uid, "turn": int(e.turn), "level": RunState.level_of(e)}
	_grid.cursor = Vector2i(int(e.x), int(e.y))
	Sfx.play("item_lift")
	_redraw()


func _confirm() -> void:
	if _focus == Focus.GEAR:
		_confirm_gear()
	else:
		_confirm_grid()


func _confirm_gear() -> void:
	if _on_button():
		if not _held.is_empty():
			Sfx.play("locked")
		elif _slot == _attributes_slot():
			open_attributes()
		else:
			open_skills()
		return
	var worn: Variant = _run.gear[_hero][_slot]
	if _held.is_empty():
		if worn == null:
			Sfx.play("locked")
			return
		_held = {"kind": "gear", "item": worn, "from": [_hero, _slot]}
		Sfx.play("item_lift")
	elif _held.kind == "gear":
		var from: Array = _held.from
		if from.is_empty():
			var sold := _run.wear(_hero, _slot, _held.item as GearData)
			if sold < 0:
				Sfx.play("locked")
				return
			_note_text = "%s wears the %s." % [_run.data.party[_hero].display_name, (_held.item as GearData).display_name]
			if worn != null:
				_note_text += " Sold the %s for %d gold." % [(worn as GearData).display_name, sold]
				Sfx.play("gold_gain")
			Sfx.play("buff")
			_held = {}
			_redraw()
			_settled()
			return
		if int(from[0]) != _hero or int(from[1]) != _slot:
			_ask({"op": "swap_gear", "from": [int(from[0]), int(from[1])], "to": [_hero, _slot]})
		Sfx.play("item_place")
		_held = {}
	else:
		Sfx.play("item_no_room")
		return
	_redraw()


func _confirm_grid() -> void:
	var pack := _run.backpack
	var cell := _grid.cursor
	if _held.is_empty():
		var uid := pack.uid_at(cell)
		if uid < 0:
			Sfx.play("locked")
			return
		Sfx.play("menu_confirm")
		_open_menu(uid)
		return
	if _held.kind != "item":
		return
	var item := _held.item as ItemData
	var turn := int(_held.turn)
	var uid := int(_held.uid)
	var into := _combine_target()
	if into >= 0:
		var name := RunState.entry_name(pack.entry(into))
		if uid >= 0:
			_ask({"op": "combine", "uid": uid, "into": into})
		else:
			_run.combine_new(item, into)
		_held = {}
		_note_text = "Combined: %s+." % name
		Sfx.play("item_combine")
		_redraw()
		if uid < 0:
			_settled()
		return
	if uid >= 0:
		var e := pack.entry(uid)
		if int(e.x) == cell.x and int(e.y) == cell.y and int(e.turn) == turn:
			_held = {}
		elif pack.fits(item, cell.x, cell.y, turn, uid):
			_ask({"op": "move", "uid": uid, "x": cell.x, "y": cell.y, "turn": turn})
			_held = {}
		else:
			Sfx.play("item_no_room")
			return
		Sfx.play("item_place")
		_redraw()
		return
	# Something new in hand (host only): place it, or swap it with the one item it covers.
	if pack.fits(item, cell.x, cell.y, turn):
		_run.place_item(item, cell.x, cell.y, turn, int(_held.get("level", 0)))
		_note_text = "The %s is in the backpack." % item.display_name
		_held = {}
		Sfx.play("item_place")
		_redraw()
		_settled()
		return
	var covered := _covered(item, cell, turn)
	if covered.size() == 1:
		var other := pack.entry(covered[0])
		if pack.fits(item, cell.x, cell.y, turn, covered[0]):
			var other_level := RunState.level_of(other)
			var other_item := pack.remove(covered[0])
			_run.place_item(item, cell.x, cell.y, turn, int(_held.get("level", 0)))
			_held = {"kind": "item", "item": other_item, "uid": -1, "turn": int(other.turn), "level": other_level}
			_note_text = "Swapped: now the %s is in hand." % other_item.display_name
			Sfx.play("item_lift")
			_clamp_cursor()
			_redraw()
			return
	Sfx.play("item_no_room")


## The item the one in hand would combine into if put down now (-1: none): the item under the
## cursor, the same item at the same level, that can still go up a level.
func _combine_target() -> int:
	if _held.is_empty() or _held.kind != "item":
		return -1
	var into := _run.backpack.uid_at(_grid.cursor)
	if into < 0:
		return -1
	if int(_held.uid) >= 0:
		return into if _run.can_combine(int(_held.uid), into) else -1
	if int(_held.get("level", 0)) != RunState.level_of(_run.backpack.entry(into)):
		return -1
	var target := _run.backpack.entry(into)
	var ok: bool = target.item == _held.item and (_held.item as ItemData).combinable() \
			and RunState.entry_rarity(target) < ItemData.Rarity.LEGENDARY
	return into if ok else -1


## The uids of the items `item` would overlap at `cell` turned `turn` times.
func _covered(item: ItemData, cell: Vector2i, turn: int) -> Array[int]:
	var found: Array[int] = []
	for c: Vector2i in Backpack.cells_at(item, cell.x, cell.y, turn):
		var uid := _run.backpack.uid_at(c)
		if uid >= 0 and not found.has(uid):
			found.append(uid)
	return found


func _cancel() -> void:
	if _held.is_empty():
		Sfx.play("menu_cancel")
		close()
		return
	if not holding_new():
		# Put back where it was.
		_held = {}
		Sfx.play("menu_cancel")
		_redraw()
		return
	if _held.kind == "gear":
		var gear := _held.item as GearData
		_confirm_prompt("Sell the %s?" % gear.display_name, "Nobody wears it. It sells for %d gold." % _run.gear_sell_price(gear),
				"Sell it", "Keep it in hand", func() -> void:
					_run.sell_new_gear(gear)
					Sfx.play("gold_gain")
					_note_text = "Sold the %s." % gear.display_name
					_held = {}
					_redraw()
					_settled())
	else:
		var item := _held.item as ItemData
		_confirm_prompt("Leave the %s behind?" % item.display_name, "It does not go in the backpack.",
				"Leave it", "Keep it in hand", func() -> void:
					Sfx.play("item_drop")
					_note_text = "Left the %s behind." % item.display_name
					_held = {}
					_redraw()
					left_behind.emit(item)
					_settled())


## The attributes screen over this one, for the hero under the cursor (not while holding
## something).
func open_attributes() -> void:
	if not _held.is_empty():
		Sfx.play("locked")
		return
	var hero := _hero if _focus == Focus.GEAR else _row_hero(_grid.cursor.y)
	_attrs = AttributesScreen.new()
	_attrs.name = "Attributes"
	_attrs.layer = layer + 1
	_attrs.remote = remote
	add_child(_attrs)
	_attrs.setup(_run, hero)
	_attrs.op_requested.connect(func(op: Dictionary) -> void: op_requested.emit(op))
	_attrs.done.connect(_close_attributes)
	Sfx.play("menu_confirm")


## The skills screen over this one, for the hero under the cursor (or the next with a tree).
func open_skills() -> void:
	if not _held.is_empty():
		Sfx.play("locked")
		return
	var hero := _hero if _focus == Focus.GEAR else _row_hero(_grid.cursor.y)
	_skills = SkillsScreen.new()
	_skills.name = "Skills"
	_skills.layer = layer + 1
	_skills.remote = remote
	add_child(_skills)
	_skills.setup(_run, hero)
	_skills.op_requested.connect(func(op: Dictionary) -> void: op_requested.emit(op))
	_skills.done.connect(func() -> void:
		_skills.queue_free()
		_skills = null
		_redraw())
	Sfx.play("menu_confirm")


func _any_tree() -> bool:
	for slot: int in _run.party_size():
		if _run.has_tree(slot):
			return true
	return false


func _close_attributes() -> void:
	if _attrs == null:
		return
	_attrs.queue_free()
	_attrs = null
	_redraw()


## The new thing in hand is dealt with.
func _settled() -> void:
	if close_when_settled:
		close()


# --- the item menu ----------------------------------------------------------------------------

func _open_menu(uid: int) -> void:
	var placed := _run.backpack.entry(uid)
	var item := placed.item as ItemData
	_menu_choices.clear()
	var items: Array[Dictionary] = []
	if item.usable_on_map():
		_menu_choices.append(["use", -1])
		items.append({"text": "Use"})
	if shop_mode and item.price > 0 and not item.rotten:
		_menu_choices.append(["sell", -1])
		items.append({"text": "Sell for %d gold" % _run.sell_price(_run.entry_price(placed))})
	_menu_choices.append(["move", -1])
	items.append({"text": "Move"})
	_menu_choices.append(["drop", -1])
	items.append({"text": "Throw away"})
	_menu_choices.append(["cancel", -1])
	items.append({"text": "Cancel"})
	_menu.index = 0
	_menu.set_items(items)
	_menu.set_meta("uid", uid)
	_menu.visible = true
	_redraw_hint()


func _menu_input(event: InputEvent) -> void:
	match _menu.handle(event):
		&"cancel":
			Sfx.play("menu_cancel")
			_close_menu()
		&"confirm":
			var uid := int(_menu.get_meta("uid"))
			var choice: Array = _menu_choices[_menu.index]
			var e := _run.backpack.entry(uid)
			_close_menu()
			if e.is_empty():
				return
			var item := e.item as ItemData
			match String(choice[0]):
				"use":
					if item.needs_target():
						# Pick the hero on their card (the cards are already on screen).
						_use_uid = uid
						_hero = _lowest_hero()
						Sfx.play("menu_confirm")
					else:
						_use_on(uid, -1)
				"sell":
					var gold := _run.sell_price(_run.entry_price(e))
					_ask({"op": "sell", "uid": uid})
					Sfx.play("gold_gain")
					_note_text = "Sold the %s for %d gold." % [item.display_name, gold]
				"move":
					_held = {"kind": "item", "item": item, "uid": uid, "turn": int(e.turn)}
					_grid.cursor = Vector2i(int(e.x), int(e.y))
					Sfx.play("item_lift")
				"drop":
					_confirm_prompt("Throw away the %s?" % item.display_name, "It is gone for good.", "Throw it away",
							"Keep it", func() -> void:
								_ask({"op": "drop", "uid": uid})
								Sfx.play("item_drop")
								_note_text = "Threw away the %s." % item.display_name
								_redraw())
				_:
					Sfx.play("menu_cancel")
			_redraw()


## Choosing who gets an item: up/down (or left/right) picks a hero card, Confirm uses it on them,
## Cancel goes back.
func _target_input(event: InputEvent) -> void:
	if _pressed(event, &"menu_up") or _pressed(event, &"menu_left"):
		_hero = wrapi(_hero - 1, 0, _run.party_size())
		Sfx.play("menu_move")
	elif _pressed(event, &"menu_down") or _pressed(event, &"menu_right"):
		_hero = wrapi(_hero + 1, 0, _run.party_size())
		Sfx.play("menu_move")
	elif _pressed(event, &"menu_confirm") or _pressed(event, &"item_move"):
		if not remote and not _run.can_use_item(_use_uid, _hero):
			# Stay on the hero cards: the info line says why this hero cannot (a capped Tonic).
			Sfx.play("locked")
		else:
			var uid := _use_uid
			_use_uid = -1
			_use_on(uid, _hero)
	elif _pressed(event, &"menu_cancel") or _pressed(event, &"party_menu"):
		_use_uid = -1
		Sfx.play("menu_cancel")
	else:
		return
	_handled()
	_redraw()


## Uses item `uid` on the map (on hero `slot` if it needs one).
func _use_on(uid: int, slot: int) -> void:
	var e := _run.backpack.entry(uid)
	if e.is_empty():
		return
	if remote or _run.can_use_item(uid, slot):
		var name := RunState.entry_name(e)
		_ask({"op": "use", "uid": uid, "slot": slot})
		Sfx.play("heal")
		_note_text = "Used the %s%s." % [name, " on " + _run.data.party[slot].display_name if slot >= 0 else ""]
	else:
		Sfx.play("locked")
		_note_text = _run.use_blocked_reason(uid, slot)
	_redraw()


## The hero with the least HP for their max (the likely one to heal).
func _lowest_hero() -> int:
	var low := 0
	for slot: int in _run.party_size():
		if _run.hp[slot] * _run.max_hp(low) < _run.hp[low] * _run.max_hp(slot):
			low = slot
	return low


func _close_menu() -> void:
	_menu.visible = false
	_redraw()


func _confirm_prompt(question: String, detail: String, yes: String, no: String, on_yes: Callable) -> void:
	_prompt = ConfirmPrompt.new()
	add_child(_prompt)
	_prompt.setup(question, detail, yes, no)
	_prompt.answered.connect(func(answer: bool) -> void:
		# The answer's press must not also reach this screen.
		_handled()
		_prompt.queue_free()
		_prompt = null
		if answer:
			on_yes.call())


## Makes a change: here, or (online client) by asking the host.
func _ask(op: Dictionary) -> void:
	if remote:
		op_requested.emit(op)
	else:
		_run.apply_op(op)


# --- drawing ----------------------------------------------------------------------------------

func _clamp_cursor() -> void:
	var pack := _run.backpack
	var ext := Vector2i.ONE
	if not _held.is_empty() and _held.kind == "item":
		ext = Backpack.extent(Backpack.turned((_held.item as ItemData).shape, int(_held.turn)))
	_grid.cursor = Vector2i(clampi(_grid.cursor.x, 0, maxi(0, pack.width - ext.x)),
			clampi(_grid.cursor.y, 0, maxi(0, pack.rows - ext.y)))


func _redraw() -> void:
	_level.text = "Gold %d" % _run.gold
	_note.text = _note_text
	_note.visible = not _note_text.is_empty()
	var from: Array = _held.from if not _held.is_empty() and _held.kind == "gear" else []
	for slot: int in _cards.size():
		var card: Dictionary = _cards[slot]
		var chosen := (_focus == Focus.GEAR or _use_uid >= 0) and slot == _hero
		# While choosing who gets an item, a hero who cannot have it (a full Tonic drinker) is greyed.
		var greyed := _use_uid >= 0 and not _run.can_use_item(_use_uid, slot)
		(card.panel as PanelContainer).modulate = Color(1.0, 1.0, 1.0, GREYED_ALPHA if greyed else 1.0)
		(card.panel as PanelContainer).add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.PANEL_BG,
				HudStyle.GOLD if chosen else HudStyle.PANEL_BORDER, 3 if chosen else 2, 16))
		(card.stats as Label).text = "Lv %d   HP %d / %d   Power %d   Speed %d" % [_run.levels[slot], _run.hp[slot],
				_run.max_hp(slot), _run.power(slot), _run.speed(slot)]
		var buttons: Array = card.buttons
		for b: int in buttons.size():
			var button := buttons[b] as Label
			var free := _run.free_points(slot) if b == 0 else _run.free_skill_points(slot)
			button.text = ("Attributes" if b == 0 else "Skills") + ("  +%d" % free if free > 0 else "")
			var on_it := chosen and _slot == _attributes_slot() + b and _use_uid < 0
			# Framed like a button; gold when the cursor is on it.
			var lit := on_it and not _menu.visible
			button.add_theme_stylebox_override("normal", HudStyle.panel(Color(0.3, 0.25, 0.1, 0.5) if lit else HudStyle.PANEL_BG,
					HudStyle.GOLD if lit else HudStyle.PANEL_BORDER, 2, 6))
			button.label_settings.font_color = HudStyle.GOLD if on_it or free > 0 else HudStyle.TEXT
		var labels: Array = card.slots
		for g: int in labels.size():
			var item: Variant = _run.gear[slot][g]
			var selected := chosen and g == _slot
			var label := labels[g] as Label
			var lifted := not from.is_empty() and int(from[0]) == slot and int(from[1]) == g
			label.text = "(in hand)" if lifted else ((item as GearData).display_name if item != null else EMPTY_TEXT)
			label.add_theme_stylebox_override("normal", ListMenu.row_style(selected and not _menu.visible, SLOT_PAD_X))
			var color := HudStyle.TEXT_DIM
			if selected:
				color = HudStyle.GOLD
			elif item != null and not lifted:
				color = BackpackGrid.rarity_color(int((item as GearData).rarity))
			label.label_settings.font_color = color
	_pack_label.text = "Backpack   %d of %d cells free" % [_run.backpack.free_cells(), _run.backpack.cell_count()]
	_charm_label.text = _charm_summary()
	_grid.links = _boost_links()
	_grid.combine_into = _combine_target()
	_grid.show_cursor = _focus == Focus.GRID and not _menu.visible
	if not _held.is_empty() and _held.kind == "item":
		_grid.held_item = _held.item
		_grid.held_turn = int(_held.turn)
		_grid.held_uid = int(_held.uid)
	else:
		_grid.held_item = null
		_grid.held_uid = -1
	_grid.queue_redraw()
	_redraw_info()
	_redraw_hint()


func _redraw_info() -> void:
	_info_title.label_settings.font_color = HudStyle.GOLD
	_info_panel.visible = _use_uid >= 0 or _menu.visible or not _held.is_empty() \
			or (_focus == Focus.GRID and _run.backpack.uid_at(_grid.cursor) >= 0)
	if _use_uid >= 0:
		var e := _run.backpack.entry(_use_uid)
		_info_title.text = "Use the %s on whom?" % RunState.entry_name(e)
		_info.text = "%s: HP %d / %d. Pick a hero card above." % [_run.data.party[_hero].display_name, _run.hp[_hero],
				_run.max_hp(_hero)]
		var blocked := _run.use_blocked_reason(_use_uid, _hero)
		if not blocked.is_empty():
			_info.text = blocked + " Pick another hero."
		return
	if not _held.is_empty():
		var thing: Resource = _held.item
		var title := String(thing.get("display_name"))
		var text := String(thing.get("description"))
		if _held.kind == "gear":
			_info_title.text = "In hand: %s (gear)" % title
			var worn: Variant = _run.gear[_hero][_slot] if not _on_button() else null
			if _focus == Focus.GEAR and holding_new() and worn != null:
				text += "\nPut on here: sells the %s for %d gold." % [(worn as GearData).display_name,
						_run.gear_sell_price(worn as GearData)]
			elif _focus == Focus.GEAR and worn != null and not holding_new():
				text += "\nPut down here: swaps with the %s." % (worn as GearData).display_name
		else:
			_info_title.text = "In hand: %s%s" % [title, "+".repeat(int(_held.get("level", 0)))]
			var fits := _run.backpack.fits(thing as ItemData, _grid.cursor.x, _grid.cursor.y, int(_held.turn), int(_held.uid))
			if _combine_target() >= 0:
				text += "\nPut down here: combines into %s+." % RunState.entry_name(_run.backpack.entry(_combine_target()))
			elif not fits and holding_new() and _covered(thing as ItemData, _grid.cursor, int(_held.turn)).size() == 1:
				text += "\nPut down here: swaps with the item under it."
			elif not fits:
				text += "\nDoes not fit here."
		_info.text = text
		return
	if _focus == Focus.GEAR:
		if _on_button():
			return
		var worn: Variant = _run.gear[_hero][_slot]
		_info_title.text = (worn as GearData).display_name if worn != null else "Empty slot"
		if worn != null:
			_info_title.text += "   (%s)" % BackpackGrid.rarity_name(int((worn as GearData).rarity))
			_info_title.label_settings.font_color = BackpackGrid.rarity_color(int((worn as GearData).rarity))
		_info.text = (worn as GearData).description if worn != null else "New gear can go here."
		return
	var uid := _run.backpack.uid_at(_grid.cursor)
	if uid < 0:
		_info_title.text = "Empty"
		_info.text = "Room for something."
		return
	var placed := _run.backpack.entry(uid)
	var item := placed.item as ItemData
	var rarity := RunState.entry_rarity(placed)
	_info_title.text = "%s   (%s%s)" % [RunState.entry_name(placed), "rotten, " if item.rotten else "",
			BackpackGrid.rarity_name(rarity)]
	_info_title.label_settings.font_color = BackpackGrid.ROTTEN_COLOR if item.rotten else BackpackGrid.rarity_color(rarity)
	var uses := PackedStringArray()
	if item.usable_on_map():
		uses.append("on the map")
	if item.usable_in_fight():
		uses.append("in fights (%d AP)" % item.ap_cost)
	var text := item.description
	if item.is_charm():
		text += "\n" + _charm_line(uid)
	elif RunState.level_of(placed) > 0:
		text += "\nCombined: %d%% instead of %d%%." % [_run.entry_amount(placed), item.amount_percent]
	if not uses.is_empty():
		text += "\nUse it " + " and ".join(uses) + "."
	if item.combinable() and rarity < ItemData.Rarity.LEGENDARY:
		text += "\nPut another %s on it to combine them." % RunState.entry_name(placed)
	if item.rotten:
		text += "\nNobody buys rot."
	elif item.price > 0:
		text += "\nSells for %d gold." % _run.sell_price(_run.entry_price(placed))
	_info.text = text


## A charm's line in the info box: what it gives now, and what boosts it.
func _charm_line(uid: int) -> String:
	var item := _run.backpack.entry(uid).item as ItemData
	var families: Array[String] = ["", "Stone", "Bone", "Herb"]
	var line := ""
	if item.family != ItemData.Family.NONE:
		line = "%s charm. " % families[item.family]
	if item.charm_amount > 0:
		line += "Now: %s for every hero" % GearData.effect_text(item.charm_effect, _run.charm_value(uid))
		var boost := _run.charm_boost(uid)
		line += " (boosted %d%%)." % boost if boost > 0 else "."
	if item.boost_family != ItemData.Family.NONE:
		line += " Boosts touching %s charms by %d%%." % [families[item.boost_family].to_lower(), item.boost_percent]
	return line.strip_edges()


## Everything the charms give, and the rot, in one line.
func _charm_summary() -> String:
	var totals := _run.charm_totals()
	var parts := PackedStringArray()
	for effect: int in totals:
		if int(totals[effect]) > 0:
			parts.append(GearData.effect_text(effect as GearData.Effect, int(totals[effect])))
	var text := ("Charms: " + ", ".join(parts)) if not parts.is_empty() else "No charms working."
	if _run.rot_percent() > 0:
		text += "   Rot: -%d%% HP a turn" % _run.rot_percent()
	return text


## Where a booster charm touches a charm it boosts: pairs of cells side by side, for the grid's
## gold links.
func _boost_links() -> Array:
	var links: Array = []
	var pack := _run.backpack
	for e: Dictionary in pack.entries:
		var booster := e.item as ItemData
		if not booster.is_charm() or booster.boost_family == ItemData.Family.NONE:
			continue
		var mine := Backpack.cells_at(booster, int(e.x), int(e.y), int(e.turn))
		for other: int in pack.touching(int(e.uid)):
			var o := pack.entry(other)
			if not (o.item as ItemData).is_charm() or (o.item as ItemData).family != booster.boost_family:
				continue
			for c: Vector2i in Backpack.cells_at(o.item as ItemData, int(o.x), int(o.y), int(o.turn)):
				for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					if mine.has(c + step):
						links.append([c, c + step])
	return links


func _redraw_hint() -> void:
	if _use_uid >= 0:
		_hint.set_entries([[&"@updown", "Hero"], [&"menu_confirm", "Use"], [&"menu_cancel", "Back"]])
		return
	if _menu.visible:
		_hint.set_entries([[&"@updown", "Choose"], [&"menu_confirm", "Select"], [&"menu_cancel", "Back"]])
		return
	var entries: Array = [[&"@arrows", "Move"]]
	if _held.is_empty():
		var confirm := "Choose"
		if _focus == Focus.GEAR:
			confirm = "Open" if _on_button() else "Pick up"
		entries.append([&"menu_confirm", confirm])
		if _focus == Focus.GRID:
			entries.append([&"item_move", "Move"])
	elif _held.kind == "item":
		entries.append([&"item_move", "Put down"])
		entries.append([&"item_turn_left", "Turn"])
		entries.append([&"item_turn_right", "Turn"])
	else:
		entries.append([&"menu_confirm", "Put on"])
	if not _held.is_empty():
		entries.append([&"menu_cancel", "Leave it" if holding_new() else "Put back"])
	else:
		entries.append([&"menu_cancel", "Done"])
	_hint.set_entries(entries)


func _handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)
