class_name RestScreen
extends StopScreen
## A rest stop as a campfire (DESIGN.md 8.11, card #161): the heroes stand round a fire in the
## dark, and the player picks ONE thing to do: Rest (everyone heals tuning.run_rest_heal_percent),
## Train (every hero gets tuning.rest_train_points attribute points) or Upgrade (one item in the
## backpack goes up a level). Then back to the map. The bot calls rest_now() (or train_now() /
## upgrade_now()) and leave().

signal done
## Host: the choice was made (Main tells the clients what happened).
signal acted(text: String)

## Screen pixels per art pixel for the fire and the heroes.
const SCENE_SCALE: int = 4
const SCENE_SIZE := Vector2(900.0, 300.0)
## The fire flickers this often (a second) by this much.
const FLICKER_HZ: float = 7.0
const FLICKER_SHARE: float = 0.12
const FIRE_PATH := "res://assets/sprites/env/campfire.png"
## The glow under the fire.
const GLOW_COLOR := Color(1.0, 0.55, 0.2, 0.35)

var _text: Label
var _menu: ListMenu
var _fire: TextureRect
var _glow: TextureRect
var _done_once: bool = false
## The menu shows the items to upgrade (uids, in menu order) instead of the three choices.
var _picking: Array[int] = []
var _time: float = 0.0


## `result`: online clients show what the host did (empty: still choosing).
func setup(p_run: RunState, fire_path: String = FIRE_PATH, result: String = "") -> void:
	run = p_run
	var column := ListMenu.screen_column(self, "Campfire", TITLE_SIZE)
	_add_bar(column)
	column.add_child(_scene(fire_path))
	_text = ListMenu.centred_label("A fire away from the rot. There is time for one thing before the road.", TEXT_SIZE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(1000.0, 0.0)
	_text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_text)
	_menu = ListMenu.new()
	column.add_child(_menu)
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	ListMenu.screen_footer(self, [[&"@updown", "Choose"], [&"menu_confirm", "Select"], [&"menu_cancel", "Back"]])
	_menu.set_items([], detail)
	if result.is_empty():
		_show_choices()
	else:
		_finish(result)


func _process(delta: float) -> void:
	_time += delta
	if _fire != null:
		var f := 1.0 + FLICKER_SHARE * sin(_time * TAU * FLICKER_HZ) * sin(_time * TAU * FLICKER_HZ * 0.37)
		_fire.modulate = Color(f, f, f)
		_glow.modulate.a = 0.8 + 0.2 * sin(_time * TAU * FLICKER_HZ * 0.5)


## The fire on the ground with its glow, and the heroes round it (their first idle frame).
func _scene(fire_path: String) -> Control:
	var box := Control.new()
	box.custom_minimum_size = SCENE_SIZE
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.set_color(0, GLOW_COLOR)
	gradient.set_color(1, Color(GLOW_COLOR, 0.0))
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = gradient
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow = TextureRect.new()
	_glow.texture = glow_tex
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.size = Vector2(SCENE_SIZE.x * 0.8, SCENE_SIZE.y * 0.9)
	_glow.position = Vector2(SCENE_SIZE.x * 0.1, SCENE_SIZE.y * 0.15)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_glow)
	var ground := SCENE_SIZE.y - 20.0
	var heroes := run.data.party
	# Round the fire: left, right, and one a step back on the left (a little further up).
	var spots: Array[Vector2] = [Vector2(-250.0, 0.0), Vector2(240.0, 0.0), Vector2(-120.0, -28.0), Vector2(120.0, -28.0)]
	for i: int in heroes.size():
		var hero := heroes[i]
		var frame := _first_frame(hero)
		if frame == null:
			continue
		var spot := spots[i % spots.size()]
		var view := TextureRect.new()
		view.texture = frame
		view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.size = frame.get_size() * SCENE_SCALE
		# Heroes on the right face the fire (the art faces right).
		view.flip_h = spot.x > 0.0
		view.position = Vector2(SCENE_SIZE.x * 0.5 + spot.x - view.size.x * 0.5, ground + spot.y - view.size.y)
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(view)
	_fire = TextureRect.new()
	_fire.texture = AssetLoader.texture(fire_path, Vector2i(32, 32))
	_fire.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fire.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fire.size = _fire.texture.get_size() * SCENE_SCALE
	_fire.position = Vector2((SCENE_SIZE.x - _fire.size.x) * 0.5, ground - _fire.size.y)
	_fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_fire)
	return box


## A hero's first frame (the idle pose, top-left cell of the sheet).
static func _first_frame(hero: CharacterData) -> Texture2D:
	var sheet := AssetLoader.texture(hero.sprite_path, Vector2i(32, 48))
	if sheet == null:
		return null
	var size := SpriteClips.frame_px(hero.sprite_clips, sheet, hero.sprite_hframes)
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(Vector2.ZERO, Vector2(size))
	return atlas


## Items that can go up a level (uids).
func upgradable() -> Array[int]:
	var found: Array[int] = []
	for e: Dictionary in run.backpack.entries:
		if run.can_upgrade(int(e.uid)):
			found.append(int(e.uid))
	return found


func has_acted() -> bool:
	return _done_once


## Rest: everyone heals. The bot calls this; the player uses the menu.
func rest_now() -> void:
	if _done_once:
		return
	var healed := run.rest()
	var parts := PackedStringArray()
	for slot: int in healed.size():
		parts.append("%s +%d" % [run.data.party[slot].display_name, healed[slot]])
	Sfx.play("heal")
	_act("Rested.   " + "   ".join(parts))


## Train: every hero gets attribute points to spend (the party screen, or the attributes screen).
func train_now() -> void:
	if _done_once:
		return
	run.train()
	Sfx.play("level_up")
	_act("Trained. Every hero has %d more attribute point%s to spend." % [run.tuning.rest_train_points,
			"" if run.tuning.rest_train_points == 1 else "s"])


## Upgrade: item `uid` goes up a level.
func upgrade_now(uid: int) -> bool:
	if _done_once or not run.upgrade_item(uid):
		Sfx.play("locked")
		return false
	Sfx.play("item_combine")
	_act("The %s is stronger now." % RunState.entry_name(run.backpack.entry(uid)))
	return true


func leave() -> void:
	done.emit()


func _act(text: String) -> void:
	print("Run campfire: %s" % text)
	_finish(text)
	acted.emit(text)


func _finish(text: String) -> void:
	_done_once = true
	_picking.clear()
	_text.text = text
	var list: Array[Dictionary] = [{"text": "Back to the map", "enabled": not remote}]
	_menu.set_items(list)
	_refresh_bar()


func _show_choices() -> void:
	_picking.clear()
	var up := upgradable()
	var list: Array[Dictionary] = [
		{"text": "Rest", "enabled": not remote, "detail": "Everyone heals %d%% of their max HP." % run.tuning.run_rest_heal_percent},
		{"text": "Train", "enabled": not remote, "detail": "Every hero gets %d attribute point%s." % [
				run.tuning.rest_train_points, "" if run.tuning.rest_train_points == 1 else "s"]},
		{"text": "Upgrade an item", "enabled": not remote and not up.is_empty(),
				"detail": "One item in the backpack goes up a level (stronger, rarer)." if not up.is_empty()
				else "Nothing in the backpack can be upgraded."},
	]
	_menu.set_items(list)


func _show_upgrades() -> void:
	_picking = upgradable()
	var list: Array[Dictionary] = []
	for uid: int in _picking:
		var e := run.backpack.entry(uid)
		var after := RunState.entry_name(e) + "+"
		list.append({"text": RunState.entry_name(e), "detail": "Becomes %s (%s)." % [after,
				BackpackGrid.rarity_name(mini(RunState.entry_rarity(e) + 1, ItemData.Rarity.LEGENDARY))],
				"color": BackpackGrid.rarity_color(RunState.entry_rarity(e))})
	_menu.set_items(list)


func _unhandled_input(event: InputEvent) -> void:
	if remote:
		return
	var answer := _menu.handle(event)
	if answer == &"cancel" and not _picking.is_empty():
		Sfx.play("menu_cancel")
		_show_choices()
		return
	if answer != &"confirm":
		return
	Sfx.play("menu_confirm")
	if _done_once:
		leave()
	elif not _picking.is_empty():
		upgrade_now(_picking[_menu.index])
	else:
		match _menu.index:
			0:
				rest_now()
			1:
				train_now()
			2:
				_show_upgrades()
