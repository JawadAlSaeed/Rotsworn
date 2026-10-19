class_name BagTab
extends PartyTab
## The Y screen's Bag tab (DESIGN.md 8.1, 8.18): the shared backpack in the middle, the heroes as
## small faces with their HP on the left (who an item is used on), and on the right how full the
## pack is, the curses, and the item menu. The rules are the old party screen's: Confirm on an item
## opens Use / Sell (in a shop) / Move / Throw away; Use on one hero moves the cursor to the faces
## to pick who. X / R picks an item straight up to move it and puts it down again; LB / RB (Z / C)
## turn the item in hand. It goes down where it fits, or onto the same item to combine them into a
## stronger one. The screen can open with a new item in hand (a find that did not fit): it is
## placed, swapped with the one item it covers, or left behind (asked first).
## What used to be sentences in a note line are now toasts: an icon and a word or two.

## A new item in hand was left behind (it is not in the backpack).
signal left_behind(item: ItemData)
## An item was sold here (the shop saves the run then).
signal sold
## A new item in hand was placed, swapped or left.
signal settled

const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const FACES_LEFT: float = 60.0
const FACE_ROW_WIDTH: float = 440.0
const FACE_ROW_HEIGHT: float = 150.0
const FACE_ROW_GAP: float = 16.0
const FACE_PX: float = 84.0
const NAME_SIZE: int = 30
const TEXT_SIZE: int = 26
const SMALL_SIZE: int = 22
const HP_BAR_WIDTH: float = 170.0
const SIDE_LEFT: float = 1480.0
const SIDE_WIDTH: float = 380.0
## A hero who cannot take the item being used is drawn this see-through.
const GREYED_ALPHA: float = 0.45

## Shop: items can be sold (DESIGN.md 8.1).
var shop_mode: bool = false
## Choosing who gets an item (its uid; -1: not choosing): the cursor is on the faces.
var _use_uid: int = -1
## In hand: {} or {item: ItemData, uid: int (-1: new), turn: int, level: int}.
var _held: Dictionary = {}
var _warning: String = ""
var _grid: BackpackGrid
var _faces_box: Control
var _side_box: Control
var _menu: ListMenu
## Choices of the open item menu: "use", "sell", "move", "drop", "cancel".
var _menu_choices: Array[String] = []
var _prompt: ConfirmPrompt
## The frame a prompt was answered in: a second press in that frame (another pad) is dropped.
var _answered_frame: int = -1
## A shop purchase in hand: leaving it gives the gold back (the shop refunds it, left_behind).
var _refund_item: ItemData
## The faces' rectangles (page coordinates) for the mouse.
var _face_rects: Array[Rect2] = []


func setup(p_run: RunState, p_remote: bool) -> void:
	super.setup(p_run, p_remote)
	_faces_box = Control.new()
	_faces_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_faces_box)
	_grid = BackpackGrid.new()
	add_child(_grid)
	_grid.setup(run.backpack, _visuals())
	_place_grid()
	_side_box = Control.new()
	_side_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side_box.position = Vector2(SIDE_LEFT, 0.0)
	add_child(_side_box)
	_menu = ListMenu.new()
	_menu.item_size = TEXT_SIZE
	_menu.centred = false
	_menu.row_width = SIDE_WIDTH - 20.0
	_menu.visible = false
	_menu.position = Vector2(SIDE_LEFT, 300.0)
	add_child(_menu)
	_redraw()


func refresh() -> void:
	if not _held.is_empty() and int(_held.uid) >= 0 and not run.backpack.has_uid(int(_held.uid)):
		# Someone else (online) moved or used it meanwhile: let go.
		_held = {}
	if _use_uid >= 0 and not run.backpack.has_uid(_use_uid):
		_use_uid = -1
	if _menu.visible and not run.backpack.has_uid(int(_menu.get_meta("uid", -1))):
		_menu.visible = false
	_grid.setup(run.backpack, _visuals())
	_place_grid()
	_clamp_cursor()
	_redraw()


func shown() -> void:
	_redraw()


## A new item is in hand (a find that did not fit, a swap, loot). `refund`: a shop purchase,
## whose gold comes back if it is left.
func hold_new(item: ItemData, refund: bool = false) -> void:
	_held = {"item": item, "uid": -1, "turn": 0, "level": 0}
	_refund_item = item if refund else null
	_grid.cursor = Vector2i.ZERO
	_clamp_cursor()
	_redraw()


## True while a new item (not yet in the backpack) is in hand.
func holding_new() -> bool:
	return not _held.is_empty() and int(_held.uid) < 0


## The bot (and tests): a new item goes wherever it fits, or is left behind.
func auto_settle() -> void:
	if _held.is_empty():
		return
	if int(_held.uid) < 0 and run.add_item(_held.item as ItemData) < 0:
		left_behind.emit(_held.item as ItemData)
	var was_new := holding_new()
	_held = {}
	_redraw()
	if was_new:
		settled.emit()


# --- PartyTab -----------------------------------------------------------------------------------

func busy() -> bool:
	return not _held.is_empty() or _menu.visible or _use_uid >= 0 or _prompt != null


func handle_input(event: InputEvent) -> bool:
	if _prompt != null:
		_prompt._unhandled_input(event)
		return true
	if Engine.get_process_frames() == _answered_frame and event.is_pressed():
		return true
	if event.is_pressed() and not event.is_echo():
		_warning = ""
	if _menu.visible:
		_menu_input(event)
		return true
	if _use_uid >= 0:
		return _target_input(event)
	if event is InputEventMouse and _mouse_input(event):
		return true
	var step := Vector2i.ZERO
	if pressed(event, &"menu_left"):
		step.x = -1
	elif pressed(event, &"menu_right"):
		step.x = 1
	elif pressed(event, &"menu_up"):
		step.y = -1
	elif pressed(event, &"menu_down"):
		step.y = 1
	elif pressed(event, &"item_move"):
		if _held.is_empty():
			_lift_here()
		else:
			_confirm_grid()
		return true
	elif pressed(event, &"item_turn_left") or pressed(event, &"item_turn_right"):
		if _held.is_empty():
			return false
		_held.turn = posmod(int(_held.turn) + (-1 if event.is_action(&"item_turn_left") else 1), 4)
		_clamp_cursor()
		Sfx.play("item_turn")
		_redraw()
		changed.emit()
		return true
	elif pressed(event, &"menu_confirm"):
		_confirm_grid()
		return true
	elif pressed(event, &"menu_cancel") or pressed(event, &"party_menu") or MenuMouse.is_back(event):
		if _held.is_empty():
			return false
		_cancel_held()
		return true
	else:
		return false
	_grid.cursor += step
	_clamp_cursor()
	Sfx.play("menu_move")
	_redraw()
	changed.emit()
	return true


func hints() -> Array:
	if _use_uid >= 0:
		return [[&"@updown", "Hero"], [&"menu_confirm", "Use"], [&"menu_cancel", "Back"]]
	if _menu.visible:
		return [[&"@updown", ""], [&"menu_confirm", "Select"], [&"menu_cancel", "Back"]]
	if not _held.is_empty():
		return [[&"item_move", "Put down"], [&"item_turn_left", ""], [&"item_turn_right", "Turn"],
				[&"menu_cancel", "Leave it" if holding_new() else "Put back"]]
	var entries: Array = [[&"@arrows", ""], [&"menu_confirm", "Choose"]]
	if run.backpack.uid_at(_grid.cursor) >= 0:
		entries.append([&"item_move", "Move"])
	return entries


func info() -> Dictionary:
	if _use_uid >= 0 and not run.backpack.entry(_use_uid).is_empty():
		var e := run.backpack.entry(_use_uid)
		var blocked := run.use_blocked_reason(_use_uid, hero)
		return {"icon": e.item, "title": run.data.party[hero].display_name,
				"color": run.data.party[hero].color.lightened(0.25),
				"chips": [[&"heart", "%d / %d" % [run.hp[hero], run.max_hp(hero)], HudStyle.HP_FILL]], "line": blocked}
	if not _held.is_empty():
		var item := _held.item as ItemData
		var chips: Array = [[&"", "In hand", HudStyle.GOLD]]
		if item == _refund_item:
			chips.append([&"coin", "Refund", HudStyle.GOLD])
		var fits := run.backpack.fits(item, _grid.cursor.x, _grid.cursor.y, int(_held.turn), int(_held.uid))
		if _combine_target() >= 0:
			chips.append([&"up", "Combine", HudStyle.GOLD])
		elif not fits and holding_new() and _covered(item, _grid.cursor, int(_held.turn)).size() == 1:
			chips.append([&"", "Swap", HudStyle.TEXT])
		elif not fits:
			chips.append([&"", "No room", HudStyle.HP_LOW])
		return {"icon": item, "title": item.display_name + "+".repeat(int(_held.get("level", 0))),
				"color": _item_color(item, int(item.rarity)), "chips": chips, "line": item.description}
	var uid := run.backpack.uid_at(_grid.cursor)
	if uid < 0:
		var chips: Array = [[&"bag", "%d / %d" % [run.backpack.free_cells(), run.backpack.cell_count()], HudStyle.TEXT]]
		var line := ""
		if run.rot_percent() > 0:
			chips.append([&"skull", "-%d%% HP" % run.rot_percent(), BackpackGrid.ROTTEN_COLOR])
			line = "Curses hurt every hero each turn in fights. A shop's Cleanse throws one away."
		return {"icon": &"bag", "title": "Backpack", "color": HudStyle.GOLD, "chips": chips, "line": line}
	var placed := run.backpack.entry(uid)
	var it := placed.item as ItemData
	var rarity := RunState.entry_rarity(placed)
	var item_chips: Array = []
	if RunState.level_of(placed) > 0:
		item_chips.append([&"up", "%d%%" % run.entry_amount(placed), HudStyle.GOLD])
	if it.usable_on_map():
		item_chips.append([&"", "Map", HudStyle.TEXT])
	if it.usable_in_fight():
		item_chips.append([&"", "Fight  %d AP" % it.ap_cost, HudStyle.AP_TEXT])
	if it.rotten:
		item_chips.append([&"skull", "Rotten", BackpackGrid.ROTTEN_COLOR])
	elif it.price > 0:
		item_chips.append([&"coin", str(run.sell_price(run.entry_price(placed))), HudStyle.GOLD])
	return {"icon": it, "title": RunState.entry_name(placed), "color": _item_color(it, rarity), "chips": item_chips,
			"line": _warning if not _warning.is_empty() else it.description}


func _item_color(item: ItemData, rarity: int) -> Color:
	return BackpackGrid.ROTTEN_COLOR if item.rotten else BackpackGrid.rarity_color(rarity)


# --- input --------------------------------------------------------------------------------------

## The mouse over the backpack grid (card #202) and, while choosing who, over the faces.
func _mouse_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var hovered := _grid.cell_at((event as InputEventMouse).position)
		if hovered.x >= 0:
			var before := _grid.cursor
			_grid.cursor = hovered
			_clamp_cursor()
			if _grid.cursor == before:
				return false
			Sfx.play("menu_move")
			_redraw()
			changed.emit()
			return true
	elif MenuMouse.is_click(event):
		var clicked := _grid.cell_at((event as InputEventMouse).position)
		if clicked.x >= 0:
			_grid.cursor = clicked
			_clamp_cursor()
			_confirm_grid()
			return true
	return false


func _lift_here() -> void:
	var uid := run.backpack.uid_at(_grid.cursor)
	if uid < 0:
		Sfx.play("locked")
		return
	var e := run.backpack.entry(uid)
	_held = {"item": e.item, "uid": uid, "turn": int(e.turn), "level": RunState.level_of(e)}
	_grid.cursor = Vector2i(int(e.x), int(e.y))
	Sfx.play("item_lift")
	_redraw()
	changed.emit()


func _confirm_grid() -> void:
	var pack := run.backpack
	var cell := _grid.cursor
	if _held.is_empty():
		var at := pack.uid_at(cell)
		if at < 0:
			Sfx.play("locked")
			return
		Sfx.play("menu_confirm")
		_open_menu(at)
		return
	var item := _held.item as ItemData
	var turn := int(_held.turn)
	var uid := int(_held.uid)
	var into := _combine_target()
	if into >= 0:
		var name := RunState.entry_name(pack.entry(into))
		if uid >= 0:
			ask({"op": "combine", "uid": uid, "into": into})
		else:
			run.combine_new(item, into)
		_held = {}
		toast.emit(name + "+", item)
		Sfx.play("item_combine")
		_redraw()
		changed.emit()
		if uid < 0:
			settled.emit()
		return
	if uid >= 0:
		var e := pack.entry(uid)
		if int(e.x) == cell.x and int(e.y) == cell.y and int(e.turn) == turn:
			_held = {}
		elif pack.fits(item, cell.x, cell.y, turn, uid):
			ask({"op": "move", "uid": uid, "x": cell.x, "y": cell.y, "turn": turn})
			_held = {}
		else:
			Sfx.play("item_no_room")
			return
		Sfx.play("item_place")
		_redraw()
		changed.emit()
		return
	# Something new in hand (host only): place it, or swap it with the one item it covers.
	if pack.fits(item, cell.x, cell.y, turn):
		run.place_item(item, cell.x, cell.y, turn, int(_held.get("level", 0)))
		toast.emit("Packed", item)
		_held = {}
		Sfx.play("item_place")
		_redraw()
		changed.emit()
		settled.emit()
		return
	var covered := _covered(item, cell, turn)
	if covered.size() == 1 and pack.fits(item, cell.x, cell.y, turn, covered[0]):
		var other := pack.entry(covered[0])
		var other_level := RunState.level_of(other)
		var other_item := pack.remove(covered[0])
		run.place_item(item, cell.x, cell.y, turn, int(_held.get("level", 0)))
		_held = {"item": other_item, "uid": -1, "turn": int(other.turn), "level": other_level}
		toast.emit("Swapped", other_item)
		Sfx.play("item_lift")
		_clamp_cursor()
		_redraw()
		changed.emit()
		return
	Sfx.play("item_no_room")


## The item the one in hand would combine into if put down now (-1: none): the item under the
## cursor, the same item at the same level, that can still go up a level.
func _combine_target() -> int:
	if _held.is_empty():
		return -1
	var into := run.backpack.uid_at(_grid.cursor)
	if into < 0:
		return -1
	if int(_held.uid) >= 0:
		return into if run.can_combine(int(_held.uid), into) else -1
	if int(_held.get("level", 0)) != RunState.level_of(run.backpack.entry(into)):
		return -1
	var target := run.backpack.entry(into)
	var ok: bool = target.item == _held.item and (_held.item as ItemData).combinable() \
			and RunState.entry_rarity(target) < ItemData.Rarity.LEGENDARY
	return into if ok else -1


## The uids of the items `item` would overlap at `cell` turned `turn` times.
func _covered(item: ItemData, cell: Vector2i, turn: int) -> Array[int]:
	var found: Array[int] = []
	for c: Vector2i in Backpack.cells_at(item, cell.x, cell.y, turn):
		var uid := run.backpack.uid_at(c)
		if uid >= 0 and not found.has(uid):
			found.append(uid)
	return found


## Back with an item in hand: a moved one goes back; a new one is left behind (asked first).
func _cancel_held() -> void:
	if not holding_new():
		_held = {}
		Sfx.play("menu_cancel")
		_redraw()
		changed.emit()
		return
	var item := _held.item as ItemData
	var detail := "Your gold comes back." if item == _refund_item else "It does not go in the backpack."
	_confirm_prompt("Leave the %s behind?" % item.display_name, detail,
			"Leave it", "Keep it in hand", func() -> void:
				Sfx.play("item_drop")
				toast.emit("Left behind", item)
				_held = {}
				_redraw()
				changed.emit()
				left_behind.emit(item)
				settled.emit())


# --- the item menu ------------------------------------------------------------------------------

func _open_menu(uid: int) -> void:
	var placed := run.backpack.entry(uid)
	var item := placed.item as ItemData
	_menu_choices.clear()
	var items: Array[Dictionary] = []
	if item.usable_on_map():
		_menu_choices.append("use")
		items.append({"text": "Use"})
	if shop_mode and item.price > 0 and not item.rotten:
		_menu_choices.append("sell")
		items.append({"text": "Sell", "value": "+%d" % run.sell_price(run.entry_price(placed))})
	_menu_choices.append("move")
	items.append({"text": "Move"})
	_menu_choices.append("drop")
	items.append({"text": "Throw away"})
	_menu_choices.append("cancel")
	items.append({"text": "Cancel"})
	_menu.index = 0
	_menu.window_rows = 0
	_menu.set_items(items)
	_menu.set_meta("uid", uid)
	_menu.visible = true
	_redraw()
	changed.emit()


func _menu_input(event: InputEvent) -> void:
	match _menu.handle(event):
		&"cancel":
			Sfx.play("menu_cancel")
			_close_menu()
		&"confirm":
			var uid := int(_menu.get_meta("uid"))
			var choice := _menu_choices[_menu.index]
			var e := run.backpack.entry(uid)
			_close_menu()
			if e.is_empty():
				return
			var item := e.item as ItemData
			match choice:
				"use":
					if item.needs_target():
						_use_uid = uid
						hero = _lowest_hero()
						Sfx.play("menu_confirm")
					else:
						_use_on(uid, -1)
				"sell":
					var gold := run.sell_price(run.entry_price(e))
					ask({"op": "sell", "uid": uid})
					if not remote:
						sold.emit()
					Sfx.play("gold_gain")
					toast.emit("+%d" % gold, &"coin")
				"move":
					_held = {"item": item, "uid": uid, "turn": int(e.turn), "level": RunState.level_of(e)}
					_grid.cursor = Vector2i(int(e.x), int(e.y))
					Sfx.play("item_lift")
				"drop":
					_confirm_prompt("Throw away the %s?" % item.display_name, "It is gone for good.", "Throw it away",
							"Keep it", func() -> void:
								ask({"op": "drop", "uid": uid})
								Sfx.play("item_drop")
								toast.emit("Gone", item)
								_redraw())
				_:
					Sfx.play("menu_cancel")
			_redraw()
			changed.emit()


## Choosing who gets an item: up / down (or left / right) picks a face, Confirm uses it on them,
## Back goes back.
func _target_input(event: InputEvent) -> bool:
	if event is InputEventMouse:
		var point := MenuMouse.local_point(self, (event as InputEventMouse).position)
		for i: int in _face_rects.size():
			if _face_rects[i].has_point(point):
				if event is InputEventMouseMotion and hero != i:
					hero = i
					Sfx.play("menu_move")
				elif MenuMouse.is_click(event):
					hero = i
					_use_chosen()
				_redraw()
				changed.emit()
				return true
		if not MenuMouse.is_back(event):
			return false
	if pressed(event, &"menu_up") or pressed(event, &"menu_left"):
		hero = wrapi(hero - 1, 0, run.party_size())
		Sfx.play("menu_move")
	elif pressed(event, &"menu_down") or pressed(event, &"menu_right"):
		hero = wrapi(hero + 1, 0, run.party_size())
		Sfx.play("menu_move")
	elif pressed(event, &"menu_confirm") or pressed(event, &"item_move"):
		_use_chosen()
	elif pressed(event, &"menu_cancel") or pressed(event, &"party_menu") or MenuMouse.is_back(event):
		_use_uid = -1
		Sfx.play("menu_cancel")
	else:
		return false
	_redraw()
	changed.emit()
	return true


func _use_chosen() -> void:
	if not remote and not run.can_use_item(_use_uid, hero):
		# Stay on the faces: the strip says why this hero cannot (a capped Tonic).
		Sfx.play("locked")
		return
	var uid := _use_uid
	_use_uid = -1
	_use_on(uid, hero)


## Uses item `uid` on the map (on hero `slot` if it needs one).
func _use_on(uid: int, slot: int) -> void:
	var e := run.backpack.entry(uid)
	if e.is_empty():
		return
	if remote or run.can_use_item(uid, slot):
		var item := e.item as ItemData
		ask({"op": "use", "uid": uid, "slot": slot})
		Sfx.play("heal")
		toast.emit(run.data.party[slot].display_name if slot >= 0 else "Used", item)
	else:
		Sfx.play("locked")
		_warning = run.use_blocked_reason(uid, slot)
	_redraw()
	changed.emit()


## The hero with the least HP for their max (the likely one to heal).
func _lowest_hero() -> int:
	var low := 0
	for slot: int in run.party_size():
		if run.hp[slot] * run.max_hp(low) < run.hp[low] * run.max_hp(slot):
			low = slot
	return low


func _close_menu() -> void:
	_menu.visible = false
	_redraw()
	changed.emit()


func _confirm_prompt(question: String, detail: String, yes: String, no: String, on_yes: Callable) -> void:
	_prompt = ConfirmPrompt.new()
	# Its input comes only through handle_input, so nothing reaches it twice.
	_prompt.ready.connect(_prompt.set_process_unhandled_input.bind(false), CONNECT_ONE_SHOT)
	add_child(_prompt)
	_prompt.setup(question, detail, yes, no)
	_prompt.answered.connect(func(answer: bool) -> void:
		if _prompt == null:
			return
		_answered_frame = Engine.get_process_frames()
		_prompt.queue_free()
		_prompt = null
		changed.emit()
		if answer:
			on_yes.call())
	changed.emit()


# --- drawing ------------------------------------------------------------------------------------

func _visuals() -> CombatVisuals:
	var visuals := load(VISUALS_PATH) as CombatVisuals
	return visuals if visuals != null else CombatVisuals.new()


## Centres the backpack on the page, shrunk to fit its height (a 7-row pack is taller than it).
func _place_grid() -> void:
	var art := _grid.custom_minimum_size
	var fit := minf(1.0, (PAGE_SIZE.y - 10.0) / maxf(1.0, art.y))
	_grid.scale = Vector2(fit, fit)
	_grid.size = art
	_grid.position = Vector2((PAGE_SIZE.x - art.x * fit) * 0.5, (PAGE_SIZE.y - art.y * fit) * 0.5)


func _clamp_cursor() -> void:
	var pack := run.backpack
	var ext := Vector2i.ONE
	if not _held.is_empty():
		ext = Backpack.extent(Backpack.turned((_held.item as ItemData).shape, int(_held.turn)))
	_grid.cursor = Vector2i(clampi(_grid.cursor.x, 0, maxi(0, pack.width - ext.x)),
			clampi(_grid.cursor.y, 0, maxi(0, pack.rows - ext.y)))


func _redraw() -> void:
	if _grid == null:
		return
	_grid.combine_into = _combine_target()
	_grid.show_cursor = not _menu.visible and _use_uid < 0
	if not _held.is_empty():
		_grid.held_item = _held.item
		_grid.held_turn = int(_held.turn)
		_grid.held_uid = int(_held.uid)
	else:
		_grid.held_item = null
		_grid.held_uid = -1
	_grid.queue_redraw()
	_draw_faces()
	_draw_side()


func _draw_faces() -> void:
	RelicsTab._clear(_faces_box)
	_face_rects.clear()
	var count := run.party_size()
	var total := float(count) * FACE_ROW_HEIGHT + float(count - 1) * FACE_ROW_GAP
	var top := (PAGE_SIZE.y - total) * 0.5
	for slot: int in count:
		var c := run.data.party[slot]
		var rect := Rect2(Vector2(FACES_LEFT, top + float(slot) * (FACE_ROW_HEIGHT + FACE_ROW_GAP)),
				Vector2(FACE_ROW_WIDTH, FACE_ROW_HEIGHT))
		_face_rects.append(rect)
		var chosen := _use_uid >= 0 and slot == hero
		var plate := Panel.new()
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.position = rect.position
		plate.size = rect.size
		plate.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.GOLD if chosen else HudStyle.EDGE_DIM,
				3 if chosen else 2, 8, FACE_ROW_HEIGHT, HudStyle.SLANT * 0.15))
		plate.modulate = Color(1.0, 1.0, 1.0, GREYED_ALPHA if _use_uid >= 0 and not run.can_use_item(_use_uid, slot) else 1.0)
		_faces_box.add_child(plate)
		var face := HudStyle.portrait_frame(AssetLoader.texture(c.portrait_path, Vector2i(48, 48)), c.color, FACE_PX)
		face.position = Vector2(26.0, (FACE_ROW_HEIGHT - FACE_PX) * 0.5 - 2.0)
		plate.add_child(face)
		var name := HudStyle.make_title(c.display_name, NAME_SIZE, c.color.lightened(0.25))
		name.position = Vector2(136.0, 26.0)
		plate.add_child(name)
		var bar := HudStyle.bar(HudStyle.HP_FILL if run.hp[slot] * 100 > run.max_hp(slot) * 30 else HudStyle.HP_LOW, 12.0)
		bar.position = Vector2(136.0, 84.0)
		bar.size = Vector2(HP_BAR_WIDTH, 12.0)
		bar.max_value = run.max_hp(slot)
		bar.value = run.hp[slot]
		plate.add_child(bar)
		var hp := HudStyle.make_number("%d / %d" % [run.hp[slot], run.max_hp(slot)], SMALL_SIZE, HudStyle.TEXT)
		hp.position = Vector2(136.0 + HP_BAR_WIDTH + 10.0, 74.0)
		plate.add_child(hp)


func _draw_side() -> void:
	RelicsTab._clear(_side_box)
	var y := 40.0
	for row: Array in _side_rows():
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 12)
		line.position = Vector2(0.0, y)
		line.add_child(UiGlyph.make(row[0], 34.0, row[2]))
		line.add_child(HudStyle.make_number(String(row[1]), TEXT_SIZE + 4, row[2]))
		_side_box.add_child(line)
		y += 56.0


## The side column: free cells, and the curses' rot when there are any.
func _side_rows() -> Array:
	var rows: Array = [[&"bag", "%d / %d" % [run.backpack.free_cells(), run.backpack.cell_count()], HudStyle.TEXT]]
	if run.rot_percent() > 0:
		rows.append([&"skull", "-%d%%" % run.rot_percent(), BackpackGrid.ROTTEN_COLOR])
	return rows
