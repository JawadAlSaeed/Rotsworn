class_name RestScreen
extends StopScreen
## A rest stop as a campfire (DESIGN.md 8.11, card #161): the heroes stand round a fire in the
## dark, and the player picks ONE thing to do: Rest (everyone heals rest_heal_percent(), less with oaths),
## Train (every hero gets tuning.rest_train_points attribute points) or Upgrade (one item in the
## backpack goes up a level). Then back to the map. The bot calls rest_now() (or train_now() /
## upgrade_now()) and leave().
## The choices are side-by-side cards with a picture and chips (card #288): Rest a heart and how
## much it heals, Train an arrow and the points, Upgrade an anvil (Keep watch and Sharpen at the
## campfire before the boss). Back shows (and works) only while picking the item to upgrade.

signal done
## Host: the choice was made (Main tells the clients what happened).
signal acted(text: String)

## An upgrade list of this many items or fewer shows as cards side by side.
const UPGRADE_CARDS_MAX: int = 3
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
var _look: StopVisuals
var _footer: HintBar
## The footer's hints now (tests read them).
var _footer_now: Array = []
var _fire: TextureRect
var _glow: TextureRect
var _done_once: bool = false
## The menu shows the items to upgrade (uids, in menu order) instead of the three choices.
var _picking: Array[int] = []
var _time: float = 0.0


## `result`: online clients show what the host did (empty: still choosing).
func setup(p_run: RunState, fire_path: String = FIRE_PATH, result: String = "") -> void:
	run = p_run
	_look = StopVisuals.load_default()
	var column := ListMenu.screen_column(self, "Campfire", TITLE_SIZE)
	_add_bar(column)
	column.add_child(_scene(fire_path))
	# Empty while choosing: what was done shows here afterwards.
	_text = ListMenu.centred_label("", TEXT_SIZE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(1000.0, 0.0)
	_text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_text.visible = false
	column.add_child(_text)
	_menu = ListMenu.new()
	column.add_child(_menu)
	_footer = ListMenu.screen_footer(self, [])
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
	if _done_once or _ask({"do": "rest"}):
		return
	var healed := run.rest()
	var parts := PackedStringArray()
	for slot: int in healed.size():
		parts.append("%s +%d" % [run.data.party[slot].display_name, healed[slot]])
	Sfx.play("heal")
	_act("Rested.   " + "   ".join(parts))


## Train: every hero gets attribute points to spend (the party screen, or the attributes screen).
func train_now() -> void:
	if _done_once or _ask({"do": "train"}):
		return
	run.train()
	Sfx.play("level_up")
	_act("Trained. Every hero has %d more attribute point%s to spend." % [run.tuning.rest_train_points,
			"" if run.tuning.rest_train_points == 1 else "s"])


## Keep Watch (the campfire before the boss, card #287): the team gauge is full.
func watch_now() -> void:
	if _done_once or _ask({"do": "watch"}):
		return
	run.keep_watch()
	Sfx.play("level_up")
	_act("You keep watch. The team gauge is full.")


## Sharpen (the campfire before the boss, card #287): every hero starts the boss fight with more AP.
func sharpen_now() -> void:
	if _done_once or _ask({"do": "sharpen"}):
		return
	run.sharpened = true
	Sfx.play("buff")
	_act("Blades sharpened. Every hero starts the boss fight with +%d AP." % run.tuning.sharpen_ap)


## Upgrade: item `uid` goes up a level.
func upgrade_now(uid: int) -> bool:
	if not _done_once and _ask({"do": "upgrade", "uid": uid}):
		return true
	if _done_once or not run.upgrade_item(uid):
		Sfx.play("locked")
		return false
	Sfx.play("item_combine")
	_act("The %s is stronger now." % RunState.entry_name(run.backpack.entry(uid)))
	return true


## Back to the map (once something was done here).
func leave() -> void:
	if _ask({"do": "leave"}):
		return
	done.emit()


## Online (card #314): the turn changed: the cards (or Back to the map) redraw, lit or greyed.
func _turn_changed() -> void:
	if _done_once:
		_finish(_text.text)
	elif _picking.is_empty():
		_show_choices()
	else:
		_show_upgrades()


func _act(text: String) -> void:
	print("Run campfire: %s" % text)
	_finish(text)
	acted.emit(text)


func _finish(text: String) -> void:
	_done_once = true
	_picking.clear()
	_text.text = text
	_text.visible = true
	var list: Array[Dictionary] = [{"text": "Back to the map", "enabled": not is_greyed()}]
	_menu.horizontal = false
	_menu.set_items(list)
	_set_footer([[&"menu_confirm", "Continue"]])
	_refresh_bar()


## The menu (tests).
func menu() -> ListMenu:
	return _menu


## The footer's hints now (tests): [[action, text], ...].
func footer_entries() -> Array:
	return _footer_now


func _set_footer(entries: Array) -> void:
	_footer_now = entries
	_footer.set_entries(entries)


func _show_choices() -> void:
	_picking.clear()
	_menu.horizontal = true
	_set_footer([[&"@leftright", "Choose"], [&"menu_confirm", "Select"]])
	var gift := _look.chip_gift_color
	var rest := {"text": "Rest", "enabled": not is_greyed(), "icon": _icon(_look.rest_icon_path), "chips": _rest_chips()}
	if run.is_watch_fire():
		_menu.set_items([rest,
			{"text": "Keep watch", "enabled": not is_greyed(), "icon": _icon(_look.watch_icon_path),
					"chips": [StopScreen.chip_entry(_look, "gauge", "Gauge full", gift)]},
			{"text": "Sharpen", "enabled": not is_greyed(), "icon": _icon(_look.sharpen_icon_path),
					"chips": [StopScreen.chip_entry(_look, "ap", "+%d AP" % run.tuning.sharpen_ap, gift)]},
		])
		return
	var up := upgradable()
	var list: Array[Dictionary] = [rest,
		{"text": "Train", "enabled": not is_greyed(), "icon": _icon(_look.train_icon_path),
				"chips": [StopScreen.chip_entry(_look, "up", "+%d points" % run.tuning.rest_train_points, gift)]},
		{"text": "Upgrade", "enabled": not is_greyed() and not up.is_empty(), "icon": _icon(_look.upgrade_icon_path),
				"chips": [StopScreen.chip_entry(_look, "item", "+1 Lv" if not up.is_empty() else "None",
						gift if not up.is_empty() else HudStyle.TEXT_DIM)]},
	]
	_menu.set_items(list)


func _icon(path: String) -> Texture2D:
	return AssetLoader.texture(path, Vector2i(24, 24))


## What Rest heals: everyone's percent, and any hero whose gear changes it (Hunger Charm, DESIGN.md
## 8.16) by name.
func _rest_chips() -> Array[Dictionary]:
	var chips: Array[Dictionary] = [StopScreen.chip_entry(_look, "heal", "+%d%% HP" % run.rest_heal_percent(),
			_look.chip_gift_color)]
	for slot: int in run.party_size():
		if run.rest_heal_percent_of(slot) != run.rest_heal_percent():
			chips.append(StopScreen.chip_entry(_look, "heal", "%s +%d%%" % [run.data.party[slot].display_name,
					run.rest_heal_percent_of(slot)], HudStyle.TEXT_DIM))
	return chips


func _show_upgrades() -> void:
	_picking = upgradable()
	var list: Array[Dictionary] = []
	for uid: int in _picking:
		var e := run.backpack.entry(uid)
		var after := RunState.entry_name(e) + "+"
		list.append({"text": RunState.entry_name(e), "value": "> %s" % after,
				"color": BackpackGrid.rarity_color(RunState.entry_rarity(e)),
				"icon": AssetLoader.texture((e.item as ItemData).icon_path, Vector2i(16, 16))})
	# Three items or fewer sit side by side as cards (owner, phase 22); more make a column. Back is
	# the cancel button either way.
	var cards := list.size() <= UPGRADE_CARDS_MAX
	_menu.horizontal = cards
	_menu.index = 0
	_menu.set_items(list)
	_set_footer([[&"@leftright" if cards else &"@updown", "Choose"], [&"menu_confirm", "Upgrade"],
			[&"menu_cancel", "Back"]])


func _unhandled_input(event: InputEvent) -> void:
	if is_greyed():
		return
	var answer := _menu.handle(event)
	if answer == &"cancel" and not _picking.is_empty():
		Sfx.play("menu_cancel")
		# Back on the Upgrade card.
		_menu.index = 2
		_show_choices()
		return
	if answer != &"confirm":
		return
	# A greyed card (Upgrade with nothing to upgrade) answers confirm too: refuse it here, or an
	# empty pick list would open and the next confirm would Rest.
	if not _menu.is_enabled(_menu.index):
		Sfx.play("locked")
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
				if run.is_watch_fire():
					watch_now()
				else:
					train_now()
			2:
				if run.is_watch_fire():
					sharpen_now()
				else:
					_show_upgrades()
