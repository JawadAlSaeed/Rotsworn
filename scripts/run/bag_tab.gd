class_name BagTab
extends PartyTab
## The Y screen's Bag tab (DESIGN.md 8.1, 8.18, 8.19): Alder's pack in the middle, its pockets
## sewn on the lining (one item each, card #282), the heroes as small faces with their HP on the
## left (who an item is used on), and on the right how many pockets are free, the curses, and the
## item menu. Confirm on an item opens Use / Combine (with another of the same) / Sell (in a shop)
## / Throw away; Use on one hero moves the cursor to the faces to pick who. The screen can open
## with a new item in hand (a find with no free pocket): Confirm puts it in a free pocket, combines
## it with the same item, or swaps it for the item in that pocket (asked first: the old one is
## thrown away); Back leaves it behind (asked first).
## What used to be sentences in a note line are now toasts: an icon and a word or two.

## A new item in hand was left behind (it is not in the backpack).
signal left_behind(item: ItemData)
## An item was sold here (the shop saves the run then).
signal sold
## A new item in hand was placed, swapped or left.
signal settled

## Online (card #314): the op a friend's backpack sends for a new item the host handed them (a find
## with no room, made on their turn): {"op": HAND_OUT, "to": "pocket" | "combine" | "swap" | "fit" |
## "leave", "pocket": x, "uid": the item combined into or swapped out}; Main adds the find's number
## ("gift") on the way out. The host applies it with place_new().
const HAND_OUT := "hand_out"
## What place_new() did.
const PLACED := "placed"
const LEFT := "left"

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
## A new item in hand: {} or {item: ItemData, uid: -1, level: int}.
var _held: Dictionary = {}
var _warning: String = ""
var _grid: BackpackGrid
var _faces_box: Control
var _side_box: Control
var _menu: ListMenu
## Choices of the open item menu: "use", "combine", "sell", "drop" (cancel closes it: no Cancel row).
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
	_grid.setup(run.backpack, _visuals(), run.tuning.backpack_max_pockets)
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
	if _use_uid >= 0 and not run.backpack.has_uid(_use_uid):
		_use_uid = -1
	if _menu.visible and not run.backpack.has_uid(int(_menu.get_meta("uid", -1))):
		_menu.visible = false
	_grid.setup(run.backpack, _visuals(), run.tuning.backpack_max_pockets)
	_place_grid()
	_clamp_cursor()
	_redraw()


func shown() -> void:
	_redraw()


## A new item is in hand (a find that did not fit, a swap, loot). `refund`: a shop purchase,
## whose gold comes back if it is left.
func hold_new(item: ItemData, refund: bool = false) -> void:
	_held = {"item": item, "uid": -1, "level": 0}
	_refund_item = item if refund else null
	_grid.cursor = 0
	_clamp_cursor()
	_redraw()


## True while a new item (not yet in the backpack) is in hand.
func holding_new() -> bool:
	return not _held.is_empty() and int(_held.uid) < 0


## The bot (and tests): a new item goes wherever it fits, or is left behind. Online, a friend's bot
## asks the host to do so (an item the host handed them, card #314).
func auto_settle() -> void:
	if _held.is_empty():
		return
	if remote and holding_new():
		ask({"op": HAND_OUT, "to": "fit"})
	elif int(_held.uid) < 0 and run.add_item(_held.item as ItemData) < 0:
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
	var step := 0
	if pressed(event, &"menu_left"):
		step = -1
	elif pressed(event, &"menu_right"):
		step = 1
	elif pressed(event, &"menu_up"):
		step = -_grid.columns()
	elif pressed(event, &"menu_down"):
		step = _grid.columns()
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
	var to := _grid.cursor + step
	if to < 0 or to >= run.backpack.width:
		return true
	_grid.cursor = to
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
		var put := "Combine" if _combine_target() >= 0 else ("Put in" if _pocket_uid() < 0 else "Swap")
		return [[&"@arrows", ""], [&"menu_confirm", put], [&"menu_cancel", "Leave it"]]
	return [[&"@arrows", ""], [&"menu_confirm", "Choose"]]


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
		if _combine_target() >= 0:
			chips.append([&"up", "Combine", HudStyle.GOLD])
		elif _pocket_uid() >= 0:
			chips.append([&"", "Swap: " + RunState.entry_name(run.backpack.entry(_pocket_uid())), HudStyle.HP_LOW])
		else:
			chips.append([&"bag", "Free", HudStyle.TEXT])
		return {"icon": item, "title": item.display_name + "+".repeat(int(_held.get("level", 0))),
				"color": _item_color(item, int(item.rarity)), "chips": chips, "line": item.description}
	var uid := _pocket_uid()
	if uid < 0:
		var chips: Array = [[&"bag", "%d / %d" % [run.backpack.free_cells(), run.backpack.cell_count()], HudStyle.TEXT]]
		var line := ""
		if run.rot_percent() > 0:
			chips.append([&"skull", "-%d%% HP" % run.rot_percent(), BackpackGrid.ROTTEN_COLOR])
			line = "Curses hurt every hero each turn in fights. A shop's Cleanse throws one away."
		return {"icon": &"bag", "title": "Pocket", "color": HudStyle.GOLD, "chips": chips, "line": line}
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

## The mouse over the pockets (card #202) and, while choosing who, over the faces.
func _mouse_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var hovered := _grid.cell_at((event as InputEventMouse).position)
		if hovered >= 0 and hovered != _grid.cursor:
			_grid.cursor = hovered
			Sfx.play("menu_move")
			_redraw()
			changed.emit()
			return true
	elif MenuMouse.is_click(event):
		var clicked := _grid.cell_at((event as InputEventMouse).position)
		if clicked >= 0:
			_grid.cursor = clicked
			_confirm_grid()
			return true
	return false


## The uid of the item in the pocket under the cursor (-1: empty).
func _pocket_uid() -> int:
	return run.backpack.uid_at(Vector2i(_grid.cursor, 0))


## Confirm on a pocket: its item's menu; with a new item in hand, put it in, combine it, or swap
## it for the item there (asked first: that one is thrown away).
func _confirm_grid() -> void:
	var at := _pocket_uid()
	if _held.is_empty():
		if at < 0:
			Sfx.play("locked")
			return
		Sfx.play("menu_confirm")
		_open_menu(at)
		return
	var item := _held.item as ItemData
	var level := int(_held.get("level", 0))
	# Online, a find the host handed us (card #314): the host puts it where we chose.
	var hand_out := remote and holding_new()
	var into := _combine_target()
	if into >= 0:
		var name := RunState.entry_name(run.backpack.entry(into))
		if hand_out:
			ask({"op": HAND_OUT, "to": "combine", "uid": into})
		else:
			run.combine_new(item, into)
		_settle(name + "+", "item_combine")
		return
	if at < 0:
		if hand_out:
			ask({"op": HAND_OUT, "to": "pocket", "pocket": _grid.cursor})
		else:
			run.place_item(item, _grid.cursor, 0, 0, level)
		_settle("Packed", "item_place")
		return
	var old := run.backpack.entry(at)
	var old_name := RunState.entry_name(old)
	var pocket := _grid.cursor
	_confirm_prompt("Swap the %s for the %s?" % [old_name, item.display_name], "The %s is thrown away." % old_name,
			"Swap", "Keep it", func() -> void:
				if not run.backpack.has_uid(at):
					return
				if hand_out:
					ask({"op": HAND_OUT, "to": "swap", "uid": at, "pocket": pocket})
				else:
					run.drop_item(at)
					run.place_item(item, pocket, 0, 0, level)
				_settle("Swapped", "item_place"))


## Host (card #314): puts new item `item`, handed to a friend, where their HAND_OUT op `op` says.
## Returns PLACED, LEFT (left behind: not in the backpack) or "" (the op does not fit the backpack
## now; the item is still owed). Changes only `run`.
static func place_new(run: RunState, item: ItemData, op: Dictionary) -> String:
	if run == null or item == null:
		return ""
	var uid := int(op.get("uid", -1))
	var pocket := int(op.get("pocket", -1))
	match String(op.get("to", "")):
		"combine":
			if run.backpack.has_uid(uid) and run.combine_new(item, uid):
				return PLACED
		"pocket":
			if pocket >= 0 and pocket < run.backpack.width and run.backpack.uid_at(Vector2i(pocket, 0)) < 0 \
					and run.place_item(item, pocket, 0, 0, 0) >= 0:
				return PLACED
		"swap":
			if run.backpack.has_uid(uid) and run.backpack.uid_at(Vector2i(pocket, 0)) == uid:
				run.drop_item(uid)
				if run.place_item(item, pocket, 0, 0, 0) >= 0:
					return PLACED
				return PLACED if run.add_item(item) >= 0 else LEFT
		"fit":
			return PLACED if run.add_item(item) >= 0 else LEFT
		"leave":
			return LEFT
	return ""


## The new item in hand went into the pack.
func _settle(word: String, sound: String) -> void:
	var item := _held.item as ItemData
	_held = {}
	toast.emit(word, item)
	Sfx.play(sound)
	_redraw()
	changed.emit()
	settled.emit()


## The item the new one in hand would combine into if put down now (-1: none): the item in the
## pocket under the cursor, the same item at the same level, that can still go up a level.
func _combine_target() -> int:
	if _held.is_empty():
		return -1
	var into := _pocket_uid()
	if into < 0:
		return -1
	if int(_held.get("level", 0)) != RunState.level_of(run.backpack.entry(into)):
		return -1
	var target := run.backpack.entry(into)
	var ok: bool = target.item == _held.item and (_held.item as ItemData).combinable() \
			and RunState.entry_rarity(target) < ItemData.Rarity.LEGENDARY
	return into if ok else -1


## Another item in the pack that item `uid` can be combined with (-1: none): the same item at the
## same level.
func _combine_partner(uid: int) -> int:
	for e: Dictionary in run.backpack.entries:
		if int(e.uid) != uid and run.can_combine(int(e.uid), uid):
			return int(e.uid)
	return -1


## Back with a new item in hand: it is left behind (asked first).
func _cancel_held() -> void:
	var item := _held.item as ItemData
	var detail := "Your gold comes back." if item == _refund_item else "It does not go in the backpack."
	_confirm_prompt("Leave the %s behind?" % item.display_name, detail,
			"Leave it", "Keep it in hand", func() -> void:
				Sfx.play("item_drop")
				toast.emit("Left behind", item)
				if remote and holding_new():
					ask({"op": HAND_OUT, "to": "leave"})
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
	if _combine_partner(uid) >= 0:
		_menu_choices.append("combine")
		items.append({"text": "Combine", "value": RunState.entry_name(placed) + "+"})
	if shop_mode and item.price > 0 and not item.rotten:
		_menu_choices.append("sell")
		items.append({"text": "Sell", "value": "+%d" % run.sell_price(run.entry_price(placed))})
	_menu_choices.append("drop")
	items.append({"text": "Throw away"})
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
				"combine":
					var other := _combine_partner(uid)
					if other >= 0:
						ask({"op": "combine", "uid": other, "into": uid})
						Sfx.play("item_combine")
						toast.emit(RunState.entry_name(e) + "+", item)
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


## Centres the pack on the page, shrunk to fit its height.
func _place_grid() -> void:
	var art := _grid.custom_minimum_size
	var fit := minf(1.0, (PAGE_SIZE.y - 10.0) / maxf(1.0, art.y))
	_grid.scale = Vector2(fit, fit)
	_grid.size = art
	_grid.position = Vector2((PAGE_SIZE.x - art.x * fit) * 0.5, (PAGE_SIZE.y - art.y * fit) * 0.5)


func _clamp_cursor() -> void:
	_grid.cursor = clampi(_grid.cursor, 0, maxi(0, run.backpack.width - 1))


func _redraw() -> void:
	if _grid == null:
		return
	_grid.combine_into = _combine_target()
	_grid.show_cursor = not _menu.visible and _use_uid < 0
	_grid.held_item = _held.item if not _held.is_empty() else null
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


## The side column: free pockets, and the curses' rot when there are any.
func _side_rows() -> Array:
	var rows: Array = [[&"bag", "%d / %d" % [run.backpack.free_cells(), run.backpack.cell_count()], HudStyle.TEXT]]
	if run.rot_percent() > 0:
		rows.append([&"skull", "-%d%%" % run.rot_percent(), BackpackGrid.ROTTEN_COLOR])
	return rows
