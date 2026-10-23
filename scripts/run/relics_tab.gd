class_name RelicsTab
extends PartyTab
## The Y screen's Relics tab (DESIGN.md 8.18, card #270): every hero as a row (face, name, level,
## HP, power, speed and their Relic slots) on the left, and the team's shared Relic bag (card #265)
## as a grid of Relic icons on the right, each with its level pips and the initial of the hero who
## wears it. One view to equip the whole team.
## Slots: up / down picks a hero, left / right a slot; right past the last slot goes into the bag.
## Confirm on an open slot jumps into the bag to pick a Relic for it; Confirm on a Relic there puts
## it on that slot (one another hero wears swaps over). X / R on a worn Relic lifts it to move it to
## another slot or hero; carried into the bag and put down, it comes off. In the bag X / R changes
## which kind of Relic shows (all, offensive, defensive, support). Back steps back (the bag to the
## slot, a Relic in hand back where it was); with nothing to undo the screen closes.
## The screen can open with a new Relic in hand (loot): it goes on the slot it is put down on, or
## Back leaves it in the bag.

## A new Relic in hand was put on or left in the bag.
signal settled

enum Zone { SLOTS, BAG }
## The bag's filter: everything, or one category (GearData.Category + 1).
enum Filter { ALL, OFFENSIVE, DEFENSIVE, SUPPORT }
const FILTER_GLYPHS: Array[StringName] = [&"gem", &"sword", &"shield", &"leaf"]

const ROW_LEFT: float = 60.0
const ROW_WIDTH: float = 1000.0
const ROW_HEIGHT: float = 228.0
const ROW_GAP: float = 14.0
const FACE_PX: float = 112.0
const NAME_SIZE: int = 36
const TEXT_SIZE: int = 24
const SMALL_SIZE: int = 20
const SLOT_PX: float = 118.0
const SLOT_LEFT: float = 548.0
const SLOT_STEP: float = 150.0
const SLOT_NAME_WIDTH: float = 140.0
const HP_BAR_WIDTH: float = 230.0
const BAG_LEFT: float = 1110.0
const BAG_WIDTH: float = 760.0
const BAG_COLUMNS: int = 6
const BAG_ROWS: int = 4
const BAG_CELL: float = 116.0
const BAG_ICON_PX: float = 92.0
## The gap between bag rows (room for the level pips under each icon).
const BAG_ROW_GAP: float = 14.0
const CHIP_SIZE: int = 22

var _zone: Zone = Zone.SLOTS
var _slot: int = 0
## The slot a Relic picked in the bag goes onto: [hero, gear slot].
var _target: Array[int] = [0, 0]
var _filter: Filter = Filter.ALL
## The bag's Relics in the order shown (the filter applied).
var _listed: Array[GearData] = []
var _cursor: int = 0
var _top_row: int = 0
## In hand: {} or {item: GearData, from: [hero, gear slot] or [] (new, from loot)}.
var _held: Dictionary = {}
## The last refusal (shown on the strip until the next press).
var _warning: String = ""
var _rows_box: Control
var _bag_box: Control
## Hit areas for the mouse: [Rect2, zone, a, b] (slots: hero, slot; bag: index).
var _hits: Array = []


func setup(p_run: RunState, p_remote: bool) -> void:
	super.setup(p_run, p_remote)
	_rows_box = Control.new()
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rows_box)
	_bag_box = Control.new()
	_bag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bag_box)
	_relist()
	_redraw()


func refresh() -> void:
	if not _held.is_empty() and not (_held.from as Array).is_empty():
		var from: Array = _held.from
		if run.gear[int(from[0])][int(from[1])] != _held.item:
			# Someone else (online) moved it meanwhile: let go.
			_held = {}
	_relist()
	_redraw()


func shown() -> void:
	_warning = ""
	if _zone == Zone.BAG and hero != _target[0]:
		_zone = Zone.SLOTS
		_slot = _target[1]
	_relist()
	_redraw()


## A new Relic from loot is in hand: the cursor goes to the first free open slot.
func hold_new(item: GearData) -> void:
	_held = {"item": item, "from": []}
	_zone = Zone.SLOTS
	for slot: int in run.party_size():
		if run.free_gear_slot(slot) >= 0:
			hero = slot
			_slot = run.free_gear_slot(slot)
			break
	_redraw()


## True while a new Relic (from loot) is in hand.
func holding_new() -> bool:
	return not _held.is_empty() and (_held.from as Array).is_empty()


## The bot (and tests): a new Relic in hand goes on whoever has the most free open slots, unless
## GearBot refuses its price; else it waits in the bag.
func auto_settle() -> void:
	if _held.is_empty():
		return
	var best := -1
	var free := 0
	for slot: int in run.party_size():
		var empty := 0
		for g: int in run.open_relic_slots():
			if run.gear[slot][g] == null:
				empty += 1
		if empty > free:
			best = slot
			free = empty
	if holding_new() and best >= 0 and GearBot.score(_held.item as GearData) >= 0:
		run.wear(best, run.free_gear_slot(best), _held.item as GearData)
	var was_new := holding_new()
	_held = {}
	_redraw()
	if was_new:
		settled.emit()


## Puts the cursor on hero `p_hero`'s slot `gear_slot`; `pick` true jumps into the bag to choose a
## Relic for it (the party screen's open_relics).
func focus_slot(p_hero: int, gear_slot: int, pick: bool = false) -> void:
	hero = clampi(p_hero, 0, run.party_size() - 1)
	_slot = clampi(gear_slot, 0, run.tuning.run_gear_slots - 1)
	_zone = Zone.SLOTS
	if pick:
		open_bag()
	_redraw()


## Confirm on the slot under the cursor: jumps into the bag to pick a Relic for it. False (and the
## reason on the strip) if the slot is shut or the bag is empty.
func open_bag() -> bool:
	if not run.slot_open(_slot):
		_refuse(run.slot_lock_text(_slot))
		return false
	if run.owned_relics().is_empty():
		_refuse("The bag is empty.")
		return false
	_target = [hero, _slot]
	_zone = Zone.BAG
	_filter = Filter.ALL
	_relist()
	var worn: Variant = run.gear[hero][_slot]
	_cursor = maxi(0, _listed.find(worn)) if worn != null else 0
	Sfx.play("menu_confirm")
	_redraw()
	return true


## Puts `item` from the bag on the target slot (swapping it over if another hero wears it). False
## if it cannot go there.
func put(item: GearData) -> bool:
	var to_hero := _target[0]
	var to_slot := _target[1]
	if item == null or not run.owns(item):
		Sfx.play("locked")
		return false
	if not run.slot_open(to_slot):
		_refuse(run.slot_lock_text(to_slot))
		return false
	if run.gear[to_hero][to_slot] != item:
		var wearer := run.wearer_of(item)
		if wearer >= 0:
			ask({"op": "swap_gear", "from": [wearer, run.wear_slot_of(item)], "to": [to_hero, to_slot]})
		else:
			ask({"op": "wear", "slot": to_hero, "gear_slot": to_slot, "relic": item.id})
		toast.emit(run.data.party[to_hero].display_name, item)
	Sfx.play("buff")
	hero = to_hero
	_slot = to_slot
	_zone = Zone.SLOTS
	_relist()
	_redraw()
	changed.emit()
	return true


# --- PartyTab -----------------------------------------------------------------------------------

func busy() -> bool:
	return not _held.is_empty()


func handle_input(event: InputEvent) -> bool:
	if event.is_pressed() and not event.is_echo():
		_warning = ""
	if event is InputEventMouse and _mouse_input(event):
		return true
	if _zone == Zone.SLOTS:
		return _slots_input(event)
	return _bag_input(event)


func hints() -> Array:
	if not _held.is_empty():
		var put_text := "Put on"
		if _zone == Zone.BAG:
			put_text = "Take off"
		return [[&"@arrows", ""], [&"menu_confirm", put_text], [&"menu_cancel", "Leave it" if holding_new() else "Put back"]]
	if _zone == Zone.BAG:
		return [[&"@arrows", ""], [&"menu_confirm", "Put on"], [&"item_move", "Kind"]]
	var entries: Array = [[&"@arrows", ""], [&"menu_confirm", "Choose"]]
	if run.slot_open(_slot) and run.gear[hero][_slot] != null:
		entries.append([&"item_move", "Move"])
	return entries


func info() -> Dictionary:
	if not _warning.is_empty() and _held.is_empty():
		var focus := _focused()
		return {"icon": &"lock", "title": focus.display_name if focus != null else "Locked",
				"color": HudStyle.TEXT_DIM, "chips": [], "line": _warning}
	if not _held.is_empty():
		var item := _held.item as GearData
		var data := _relic_info(item)
		data.chips = [[&"", "In hand", HudStyle.GOLD]] + (data.chips as Array)
		if not _warning.is_empty():
			data.line = _warning
		elif _zone == Zone.SLOTS and not run.slot_open(_slot):
			data.line = run.slot_lock_text(_slot)
			(data.chips as Array).append([&"lock", "Locked", HudStyle.TEXT_DIM])
		return data
	if _zone == Zone.SLOTS:
		if not run.slot_open(_slot):
			return {"icon": &"lock", "title": "Locked", "color": HudStyle.TEXT_DIM, "chips": [],
					"line": run.slot_lock_text(_slot)}
		var worn: Variant = run.gear[hero][_slot]
		if worn == null:
			return {"icon": &"plus", "title": "Empty", "color": HudStyle.TEXT_DIM, "chips": [], "line": ""}
		return _relic_info(worn as GearData)
	var picked := _listed[_cursor] if _cursor < _listed.size() else null
	if picked == null:
		return {"icon": &"pouch", "title": "Empty", "color": HudStyle.TEXT_DIM, "chips": [], "line": ""}
	return _relic_info(picked)


## Open empty slots while the bag holds Relics nobody wears (something to put on).
func badge() -> int:
	if run.unworn_relics().is_empty():
		return 0
	var empty := 0
	for slot: int in run.party_size():
		for g: int in run.open_relic_slots():
			if run.gear[slot][g] == null:
				empty += 1
	return mini(empty, run.unworn_relics().size())


# --- input --------------------------------------------------------------------------------------

func _slots_input(event: InputEvent) -> bool:
	if pressed(event, &"menu_up"):
		hero = wrapi(hero - 1, 0, run.party_size())
	elif pressed(event, &"menu_down"):
		hero = wrapi(hero + 1, 0, run.party_size())
	elif pressed(event, &"menu_left"):
		if _slot <= 0:
			return true
		_slot -= 1
	elif pressed(event, &"menu_right"):
		if _slot >= run.tuning.run_gear_slots - 1:
			if holding_new() or run.owned_relics().is_empty():
				return true
			# Into the bag at the same height, picking for the slot just left (or an open one).
			_enter_bag()
			_relist()
			_cursor = clampi(_row_for_hero(hero) * BAG_COLUMNS, 0, maxi(0, _listed.size() - 1))
		else:
			_slot += 1
	elif pressed(event, &"menu_confirm"):
		_confirm_slot()
		return true
	elif pressed(event, &"item_move"):
		if _held.is_empty():
			_lift()
		else:
			_confirm_slot()
		return true
	elif pressed(event, &"menu_cancel") or pressed(event, &"party_menu") or MenuMouse.is_back(event):
		if _held.is_empty():
			return false
		_let_go()
		return true
	else:
		return false
	Sfx.play("menu_move")
	_redraw()
	changed.emit()
	return true


func _bag_input(event: InputEvent) -> bool:
	var step := 0
	if pressed(event, &"menu_left"):
		if _cursor % BAG_COLUMNS == 0:
			_back_to_slots()
			return true
		step = -1
	elif pressed(event, &"menu_right"):
		step = 1
	elif pressed(event, &"menu_up"):
		step = -BAG_COLUMNS
	elif pressed(event, &"menu_down"):
		step = BAG_COLUMNS
	elif pressed(event, &"menu_confirm"):
		_confirm_bag()
		return true
	elif pressed(event, &"item_move"):
		if not _held.is_empty():
			_confirm_bag()
			return true
		_filter = ((_filter + 1) % Filter.size()) as Filter
		_relist()
		_cursor = 0
		Sfx.play("menu_move")
		_redraw()
		changed.emit()
		return true
	elif pressed(event, &"menu_cancel") or pressed(event, &"party_menu") or MenuMouse.is_back(event):
		if not _held.is_empty():
			_let_go()
		else:
			Sfx.play("menu_cancel")
			_back_to_slots()
		return true
	else:
		return false
	var to := _cursor + step
	if to >= 0 and to < _listed.size():
		_cursor = to
		Sfx.play("menu_move")
	_redraw()
	changed.emit()
	return true


func _mouse_input(event: InputEvent) -> bool:
	var mouse := event as InputEventMouse
	var point := MenuMouse.local_point(self, mouse.position)
	var hit: Array = []
	for h: Array in _hits:
		if (h[0] as Rect2).has_point(point):
			hit = h
	if MenuMouse.is_press(event):
		var wheel := MenuMouse.wheel_step((event as InputEventMouseButton).button_index)
		if wheel != 0 and _zone == Zone.BAG:
			var to := _cursor + wheel * BAG_COLUMNS
			if to >= 0 and to < _listed.size():
				_cursor = to
				_redraw()
				changed.emit()
			return true
	if hit.is_empty():
		return false
	if event is InputEventMouseMotion:
		var moved := false
		if int(hit[1]) == Zone.SLOTS and (_zone != Zone.SLOTS or hero != int(hit[2]) or _slot != int(hit[3])):
			if _zone == Zone.BAG and _held.is_empty():
				return false  # picking in the bag: pointing at slots does not leave it
			hero = int(hit[2])
			_slot = int(hit[3])
			_zone = Zone.SLOTS
			moved = true
		elif int(hit[1]) == Zone.BAG and _zone == Zone.BAG and _cursor != int(hit[2]):
			_cursor = int(hit[2])
			moved = true
		if moved:
			Sfx.play("menu_move")
			_redraw()
			changed.emit()
		return moved
	if MenuMouse.is_click(event):
		if int(hit[1]) == Zone.SLOTS:
			hero = int(hit[2])
			_slot = int(hit[3])
			_zone = Zone.SLOTS
			_confirm_slot()
		else:
			if _zone != Zone.BAG:
				_enter_bag()
				_relist()
			_cursor = int(hit[2])
			_confirm_bag()
		return true
	return false


func _confirm_slot() -> void:
	if _held.is_empty():
		open_bag()
		return
	if not run.slot_open(_slot):
		_refuse(run.slot_lock_text(_slot))
		return
	var item := _held.item as GearData
	var from: Array = _held.from
	var name := run.data.party[hero].display_name
	if from.is_empty():
		# A new Relic from loot (host only, like before): it goes on; what was here goes back to the bag.
		if run.wear(hero, _slot, item) < 0:
			Sfx.play("locked")
			return
		_held = {}
		Sfx.play("buff")
		toast.emit(name, item)
		_relist()
		_redraw()
		changed.emit()
		settled.emit()
		return
	if int(from[0]) != hero or int(from[1]) != _slot:
		ask({"op": "swap_gear", "from": [int(from[0]), int(from[1])], "to": [hero, _slot]})
		toast.emit(name, item)
	Sfx.play("item_place")
	_held = {}
	_relist()
	_redraw()
	changed.emit()


func _confirm_bag() -> void:
	if not _held.is_empty():
		var from: Array = _held.from
		if from.is_empty():
			# A new Relic dropped in the bag just waits there.
			_let_go()
			return
		ask({"op": "take_off", "slot": int(from[0]), "gear_slot": int(from[1])})
		_held = {}
		Sfx.play("menu_cancel")
		toast.emit("In the bag", &"pouch")
		_relist()
		_redraw()
		changed.emit()
		return
	put(_listed[_cursor] if _cursor < _listed.size() else null)


func _lift() -> void:
	if not run.slot_open(_slot) or run.gear[hero][_slot] == null:
		Sfx.play("locked")
		return
	_held = {"item": run.gear[hero][_slot], "from": [hero, _slot]}
	Sfx.play("item_lift")
	_redraw()
	changed.emit()


## Back with a Relic in hand: a lifted one goes back; a new one waits in the bag.
func _let_go() -> void:
	var was_new := holding_new()
	_held = {}
	Sfx.play("menu_cancel")
	if was_new:
		toast.emit("In the bag", &"pouch")
	_relist()
	_redraw()
	changed.emit()
	if was_new:
		settled.emit()


## Into the bag from the slots: a pick goes onto the slot the cursor was on, or, when that one is
## shut, the hero's first free open slot (else their last open one).
func _enter_bag() -> void:
	var g := _slot
	if not run.slot_open(g):
		var free := run.free_gear_slot(hero)
		g = free if free >= 0 else run.open_relic_slots() - 1
	_target = [hero, g]
	_zone = Zone.BAG


func _back_to_slots() -> void:
	_zone = Zone.SLOTS
	hero = _target[0]
	_slot = _target[1]
	Sfx.play("menu_move")
	_redraw()
	changed.emit()


func _refuse(reason: String) -> void:
	_warning = reason
	Sfx.play("locked")
	_redraw()
	changed.emit()


# --- what is shown --------------------------------------------------------------------------------

## The bag's Relics through the filter: the ones nobody wears first, then by category, rarity
## (rarest first) and name, so what is free to put on comes first.
func _relist() -> void:
	var keep := _listed[_cursor] if _cursor >= 0 and _cursor < _listed.size() else null
	_listed.clear()
	for item: GearData in run.owned_relics():
		if _filter == Filter.ALL or item.category() == int(_filter) - 1:
			_listed.append(item)
	_listed.sort_custom(func(a: GearData, b: GearData) -> bool:
		var aw := run.is_worn(a)
		var bw := run.is_worn(b)
		if aw != bw:
			return not aw
		if a.category() != b.category():
			return a.category() < b.category()
		if a.rarity != b.rarity:
			return a.rarity > b.rarity
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	if keep != null and _listed.has(keep):
		_cursor = _listed.find(keep)
	_cursor = clampi(_cursor, 0, maxi(0, _listed.size() - 1))


func _focused() -> GearData:
	if _zone == Zone.BAG:
		return _listed[_cursor] if _cursor < _listed.size() else null
	if not run.slot_open(_slot):
		return null
	return run.gear[hero][_slot] as GearData


## The strip for a Relic: its icon and name, level, stat line, Echo progress, and what it does.
func _relic_info(item: GearData) -> Dictionary:
	var color := GearData.ROT_TOUCHED_COLOR if item.rot_touched else BackpackGrid.rarity_color(BackpackGrid.gear_step(item))
	var chips: Array = [[&"", "Lv %d" % run.relic_level(item), HudStyle.TEXT]]
	var stat := item.stat_text(run.relic_level(item))
	if not stat.is_empty():
		chips.append([UiGlyph.attribute_glyph(item.stat), stat, HudStyle.TEXT])
	var wearer := run.wearer_of(item)
	if wearer >= 0:
		chips.append([&"person", run.data.party[wearer].display_name, run.data.party[wearer].color.lightened(0.25)])
	var data := {"icon": item, "title": item.display_name, "color": color, "chips": chips, "line": item.description}
	if run.echo_learned(item):
		chips.append([&"echo", "Learned", HudStyle.GOLD])
	elif run.teaches_echoes():
		data.bar = [run.mastery_of(item), run.tuning.mastery_needed]
	return data


## The bag's grid row level with hero `slot`'s row (moving across).
func _row_for_hero(slot: int) -> int:
	var rows := maxi(1, ceili(float(_listed.size()) / float(BAG_COLUMNS)))
	if run.party_size() <= 1:
		return 0
	return clampi(roundi(float(slot) * float(rows - 1) / float(run.party_size() - 1)), 0, rows - 1)


# --- drawing --------------------------------------------------------------------------------------

func _redraw() -> void:
	if _rows_box == null:
		return
	_hits.clear()
	_clear(_rows_box)
	_clear(_bag_box)
	var count := run.party_size()
	var total := float(count) * ROW_HEIGHT + float(count - 1) * ROW_GAP
	var top := maxf(0.0, (PAGE_SIZE.y - total) * 0.5)
	for slot: int in count:
		_draw_row(slot, Vector2(ROW_LEFT, top + float(slot) * (ROW_HEIGHT + ROW_GAP)))
	_draw_bag()


func _draw_row(slot: int, at: Vector2) -> void:
	var c := run.data.party[slot]
	var on_row := _zone == Zone.SLOTS and slot == hero
	var plate := Panel.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = at
	plate.size = Vector2(ROW_WIDTH, ROW_HEIGHT)
	plate.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.GOLD if on_row else HudStyle.EDGE_DIM,
			3 if on_row else 2, 10, ROW_HEIGHT, HudStyle.SLANT * 0.12))
	_rows_box.add_child(plate)
	var face := HudStyle.portrait_frame(AssetLoader.texture(c.portrait_path, Vector2i(48, 48)), c.color, FACE_PX)
	face.position = Vector2(34.0, (ROW_HEIGHT - FACE_PX) * 0.5 - 4.0)
	plate.add_child(face)
	var name := HudStyle.make_title(c.display_name, NAME_SIZE, c.color.lightened(0.25))
	name.position = Vector2(176.0, 30.0)
	plate.add_child(name)
	var level := HudStyle.make_number("Lv %d" % run.levels[slot], TEXT_SIZE, HudStyle.TEXT_DIM)
	level.position = Vector2(176.0 + name.get_minimum_size().x + 16.0, 40.0)
	plate.add_child(level)
	# HP: a bar and its numbers.
	var heart := UiGlyph.make(&"heart", 24.0, HudStyle.HP_FILL)
	heart.position = Vector2(176.0, 100.0)
	plate.add_child(heart)
	var bar := HudStyle.bar(HudStyle.HP_FILL if run.hp[slot] * 100 > run.max_hp(slot) * 30 else HudStyle.HP_LOW, 14.0)
	bar.position = Vector2(210.0, 105.0)
	bar.size = Vector2(HP_BAR_WIDTH, 14.0)
	bar.max_value = run.max_hp(slot)
	bar.value = run.hp[slot]
	plate.add_child(bar)
	var hp := HudStyle.make_number("%d / %d" % [run.hp[slot], run.max_hp(slot)], SMALL_SIZE, HudStyle.TEXT)
	hp.position = Vector2(210.0 + HP_BAR_WIDTH + 12.0, 96.0)
	plate.add_child(hp)
	# Power and speed as glyph + number.
	var x := 176.0
	for pair: Array in [[&"sword", run.power(slot)], [&"bolt", run.speed(slot)]]:
		var glyph := UiGlyph.make(pair[0], 22.0, HudStyle.TEXT_DIM)
		glyph.position = Vector2(x, 152.0)
		plate.add_child(glyph)
		var number := HudStyle.make_number(str(pair[1]), SMALL_SIZE, HudStyle.TEXT)
		number.position = Vector2(x + 30.0, 146.0)
		plate.add_child(number)
		x += 110.0
	var lifted: Array = _held.from if not _held.is_empty() else []
	for g: int in run.tuning.run_gear_slots:
		var cx := SLOT_LEFT + float(g) * SLOT_STEP
		var cell := Rect2(Vector2(cx, 20.0), Vector2(SLOT_PX, SLOT_PX))
		var chosen := on_row and g == _slot
		var worn: Variant = run.gear[slot][g]
		var is_lifted := not lifted.is_empty() and int(lifted[0]) == slot and int(lifted[1]) == g
		var icon := RelicIcon.new()
		if not run.slot_open(g):
			icon.setup_slot(RelicIcon.SlotState.LOCKED, SLOT_PX)
		elif worn == null or is_lifted:
			icon.setup_slot(RelicIcon.SlotState.EMPTY, SLOT_PX)
		else:
			icon.setup(worn as GearData, SLOT_PX, true, run.relic_level(worn as GearData), run.tuning.relic_max_level)
		icon.chosen = chosen
		icon.position = cell.position
		plate.add_child(icon)
		_hits.append([Rect2(at + cell.position, cell.size), Zone.SLOTS, slot, g])
		var label_text := ""
		if worn != null and run.slot_open(g) and not is_lifted:
			label_text = (worn as GearData).display_name
		var label := HudStyle.make_label(label_text, SMALL_SIZE - 2, HudStyle.GOLD if chosen else HudStyle.TEXT_DIM)
		label.position = Vector2(cx + (SLOT_PX - SLOT_NAME_WIDTH) * 0.5, 20.0 + SLOT_PX + 26.0)
		label.custom_minimum_size.x = SLOT_NAME_WIDTH
		label.size.x = SLOT_NAME_WIDTH
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		plate.add_child(label)
	if not _held.is_empty() and on_row:
		# The Relic in hand floats over the slot under the cursor.
		var held := RelicIcon.new()
		held.setup(_held.item as GearData, SLOT_PX * 0.72, true, run.relic_level(_held.item as GearData),
				run.tuning.relic_max_level)
		held.chosen = true
		held.position = Vector2(SLOT_LEFT + float(_slot) * SLOT_STEP + SLOT_PX * 0.55, -6.0)
		plate.add_child(held)


func _draw_bag() -> void:
	var plate := Panel.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = Vector2(BAG_LEFT, 0.0)
	plate.size = Vector2(BAG_WIDTH, PAGE_SIZE.y)
	var in_bag := _zone == Zone.BAG
	plate.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.GOLD if in_bag else HudStyle.EDGE_DIM,
			3 if in_bag else 2, 10, PAGE_SIZE.y, HudStyle.SLANT * 0.05))
	_bag_box.add_child(plate)
	# Head: the pouch and how many Relics the run has, then the kind filter chips.
	var pouch := UiGlyph.make(&"pouch", 36.0, HudStyle.GOLD)
	pouch.position = Vector2(30.0, 24.0)
	plate.add_child(pouch)
	var count := HudStyle.make_number(str(run.owned_relics().size()), TEXT_SIZE + 4, HudStyle.TEXT)
	count.position = Vector2(76.0, 22.0)
	plate.add_child(count)
	var x := 170.0
	for f: int in Filter.size():
		var chip := _filter_chip(f)
		chip.position = Vector2(x, 24.0)
		plate.add_child(chip)
		x += chip.get_combined_minimum_size().x + 12.0
	var grid_top := 92.0
	var rows := ceili(float(_listed.size()) / float(BAG_COLUMNS))
	var row := floori(float(_cursor) / float(BAG_COLUMNS))
	if row < _top_row:
		_top_row = row
	elif row >= _top_row + BAG_ROWS:
		_top_row = row - BAG_ROWS + 1
	_top_row = clampi(_top_row, 0, maxi(0, rows - BAG_ROWS))
	if _listed.is_empty():
		var empty := UiGlyph.make(&"pouch", 80.0, Color(HudStyle.TEXT_DIM, 0.5))
		empty.position = Vector2((BAG_WIDTH - 80.0) * 0.5, 280.0)
		plate.add_child(empty)
		return
	for i: int in range(_top_row * BAG_COLUMNS, mini(_listed.size(), (_top_row + BAG_ROWS) * BAG_COLUMNS)):
		var item := _listed[i]
		var col := i % BAG_COLUMNS
		var r := floori(float(i) / float(BAG_COLUMNS)) - _top_row
		var cell := Rect2(Vector2(28.0 + float(col) * BAG_CELL, grid_top + float(r) * (BAG_CELL + BAG_ROW_GAP)),
				Vector2(BAG_CELL, BAG_CELL))
		var icon := RelicIcon.new()
		icon.setup(item, BAG_ICON_PX, true, run.relic_level(item), run.tuning.relic_max_level)
		icon.chosen = in_bag and i == _cursor
		var wearer := run.wearer_of(item)
		if wearer >= 0:
			var c := run.data.party[wearer]
			icon.set_tag(c.display_name.left(1), c.color)
		icon.modulate = Color(1.0, 1.0, 1.0, 0.6 if wearer >= 0 and not icon.chosen else 1.0)
		icon.position = cell.position + (cell.size - Vector2(BAG_ICON_PX, BAG_ICON_PX)) * 0.5
		plate.add_child(icon)
		_hits.append([Rect2(plate.position + cell.position, cell.size), Zone.BAG, i, 0])
	if rows > BAG_ROWS:
		# More below or above: a thin scroll mark on the right edge.
		var track := ColorRect.new()
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.color = Color(HudStyle.EDGE_DIM, 0.5)
		track.position = Vector2(BAG_WIDTH - 22.0, grid_top)
		track.size = Vector2(4.0, float(BAG_ROWS) * (BAG_CELL + BAG_ROW_GAP))
		plate.add_child(track)
		var thumb := ColorRect.new()
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.color = HudStyle.GOLD
		thumb.size = Vector2(4.0, track.size.y * float(BAG_ROWS) / float(rows))
		thumb.position = track.position + Vector2(0.0, track.size.y * float(_top_row) / float(rows))
		plate.add_child(thumb)


## A filter chip: its glyph and how many Relics of that kind the run has; gold when chosen.
func _filter_chip(f: int) -> Control:
	var on := f == int(_filter)
	var n := 0
	for item: GearData in run.owned_relics():
		if f == Filter.ALL or item.category() == f - 1:
			n += 1
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK_SOLID, HudStyle.GOLD if on else HudStyle.EDGE_DIM,
			2, 6, 34.0, HudStyle.SLANT, false))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	box.add_child(line)
	var tint := HudStyle.GOLD if on else HudStyle.TEXT_DIM
	if f != Filter.ALL:
		tint = RelicIcon.category_color(f - 1) if on else Color(RelicIcon.category_color(f - 1), 0.7)
	line.add_child(UiGlyph.make(FILTER_GLYPHS[f], 22.0, tint))
	line.add_child(HudStyle.make_number(str(n), CHIP_SIZE, HudStyle.GOLD if on else HudStyle.TEXT))
	return box


static func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.free()
