class_name RestScreen
extends StopScreen
## A rest stop as a campfire (DESIGN.md 8.11, card #161): the heroes stand round a fire in the
## dark, and the player picks ONE thing to do: Rest (everyone heals rest_heal_percent(), less with oaths),
## Train (every hero gets tuning.rest_train_points attribute points) or Upgrade (one Relic of the
## party becomes Relic+, DESIGN.md 8.25). At the campfire before the boss Keep watch takes Train's
## place (Sharpen went in phase 27). Then back to the map. The bot calls rest_now(), train_now(),
## watch_now() or upgrade_now() and leave().
## The choices are side-by-side cards with a picture and chips (card #288): Rest a heart and how
## much it heals, Train an arrow and the points, Upgrade a hammer and "Relic+" (dim when no Relic of
## the chooser's heroes can be). Upgrade opens the pick: one card per Relic that can be (its icon, name,
## who holds it, what it does and, in gold, what its "+" changes; no line under the cards, the chips
## say it, as on the Spoils). The cards take the fire's place, in a stage of a fixed height, so the
## title and the party bar never move. Back steps back to the three cards (DESIGN.md 8.24: Back never
## skips).

signal done
## Host: the choice was made (Main tells the clients what happened).
signal acted(text: String)

## Screen pixels per art pixel for the fire and the heroes.
const SCENE_SCALE: int = 4
const SCENE_SIZE := Vector2(900.0, 300.0)
## The room under the party bar: the fire and the three cards, or the pick's question and its Relic
## cards (the tallest, a lone Relic with a drawback on a narrow card, is about 590). Fixed, so the
## page keeps its height whatever shows (a test checks every Relic fits).
const STAGE_PX: float = 660.0
## The fire flickers this often (a second) by this much.
const FLICKER_HZ: float = 7.0
const FLICKER_SHARE: float = 0.12
const FIRE_PATH := "res://assets/sprites/env/campfire.png"
## The glow under the fire.
const GLOW_COLOR := Color(1.0, 0.55, 0.2, 0.35)
## The Upgrade card's chip and the map's campfire chip (DESIGN.md 8.25).
const UPGRADE_CHIP := "Relic+"
## The line over the Relic cards, and how many of them share the row (more slide in, ListMenu).
const PICK_ASK := "Which Relic?"
const PICK_SHOWN: int = 3
## A Relic's icon on its card in the pick.
const PICK_ICON_PX: float = 96.0
## Where the cards sit (the menu's items) at a normal fire and at the one before the boss.
const CARD_REST: int = 0
const CARD_TRAIN: int = 1
const CARD_UPGRADE: int = 2

var _text: Label
var _menu: ListMenu
var _look: StopVisuals
var _footer: HintBar
## The footer's hints now (tests read them).
var _footer_now: Array = []
var _fire: TextureRect
var _glow: TextureRect
var _done_once: bool = false
var _time: float = 0.0
## The Upgrade pick is open: its Relics (in the run's order) and the pad that opened it (local co-op:
## that player's heroes' Relics only).
var _picking: bool = false
var _picks: Array[GearData] = []
var _pick_device: int = PlayerRoster.ANY
var _ask_label: Label
## The fire and the heroes round it (hidden while the pick's cards take its place).
var _scene_box: Control


## `result`: online clients show what the host did (empty: still choosing).
func setup(p_run: RunState, fire_path: String = FIRE_PATH, result: String = "") -> void:
	run = p_run
	_look = StopVisuals.load_default()
	var column := ListMenu.screen_column(self, "Campfire", TITLE_SIZE)
	_add_bar(column)
	# Everything under the bar sits at the stage's top; the stage keeps its height (STAGE_PX).
	var stage := VBoxContainer.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.custom_minimum_size.y = STAGE_PX
	stage.add_theme_constant_override("separation", column.get_theme_constant(&"separation"))
	column.add_child(stage)
	_scene_box = _scene(fire_path)
	stage.add_child(_scene_box)
	# Empty while choosing: what was done shows here afterwards.
	_text = ListMenu.centred_label("", TEXT_SIZE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(1000.0, 0.0)
	_text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_text.visible = false
	stage.add_child(_text)
	_ask_label = ListMenu.centred_label(PICK_ASK, TEXT_SIZE, HudStyle.GOLD)
	_ask_label.visible = false
	stage.add_child(_ask_label)
	_menu = ListMenu.new()
	stage.add_child(_menu)
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


## Upgrade (DESIGN.md 8.25, card #333): the party's Relic `id` becomes Relic+ for the rest of the run.
## Only a Relic that can be upgraded (RunState.can_upgrade) of a hero the chooser may give to
## (RelicGift.allowed, as for "Who gets it?"; `device` is who chose). True if it was done (online
## friend: asked; the host checks it again in Main._make_rest_choice).
func upgrade_now(id: String, device: int = PlayerRoster.ANY) -> bool:
	if _done_once:
		return false
	var item := run.relic_by_id(id)
	if not run.can_upgrade(item) or not RelicGift.allowed(give_heroes, run, device).has(run.holder_of(item)):
		return false
	if _ask({"do": "upgrade", "relic": id}):
		return true
	var holder := run.holder_of(item)
	run.upgrade_relic(id)
	print("Run upgrade: %s for %s" % [id, run.data.party[holder].id])
	Sfx.play("level_up")
	_act("%s is now %s." % [item.display_name, item.shown_name(true)])
	return true


## The Relics the player on `device` may upgrade here (their heroes' Relics that are not "+" yet).
func upgradable_for(device: int = PlayerRoster.ANY) -> Array[GearData]:
	return run.upgradable(RelicGift.allowed(give_heroes, run, device))


## True while the Upgrade pick is open.
func is_picking() -> bool:
	return _picking


## The Relics on the Upgrade pick's cards (tests).
func picks() -> Array[GearData]:
	return _picks


## Opens the Upgrade pick for the player on `device`. False (nothing opens) when none of their
## heroes' Relics can be upgraded, or the choices cannot be made here.
func open_upgrade(device: int = PlayerRoster.ANY) -> bool:
	if _done_once or is_greyed():
		return false
	var found := upgradable_for(device)
	if found.is_empty():
		return false
	_picks = found
	_pick_device = device
	_picking = true
	_show_picks()
	_menu.index = 0
	_menu.redraw()
	return true


## Back from the Upgrade pick to the three cards, the cursor on Upgrade.
func close_upgrade() -> void:
	if not _picking:
		return
	_picking = false
	_picks = []
	_pick_device = PlayerRoster.ANY
	_show_choices()
	_menu.index = CARD_UPGRADE
	_menu.redraw()


## Back to the map (once something was done here).
func leave() -> void:
	if _ask({"do": "leave"}):
		return
	done.emit()


## Online (card #314): the turn changed: the cards (or Back to the map) redraw, lit or greyed. An open
## Upgrade pick closes (the new turn's player picks afresh).
func _turn_changed() -> void:
	if _done_once:
		_finish(_text.text)
	else:
		_picking = false
		_picks = []
		_show_choices()


func _act(text: String) -> void:
	text += _pouch_text(run.campfire_heal())
	print("Run campfire: %s" % text)
	_finish(text)
	acted.emit(text)


func _finish(text: String) -> void:
	_done_once = true
	_picking = false
	_text.text = text
	_text.visible = true
	_scene_box.visible = true
	_ask_label.visible = false
	var list: Array[Dictionary] = [{"text": "Back to the map", "enabled": not is_greyed()}]
	_menu.horizontal = false
	_menu.window_rows = 0
	_menu.set_items(list)
	_set_footer([[&"menu_confirm", "Continue"]])
	_refresh_bar()


## What Rain Pouch healed at this pick (DESIGN.md 8.25), as "   Alder +12" per hero, or "".
func _pouch_text(healed: Array[int]) -> String:
	var parts := PackedStringArray()
	for slot: int in healed.size():
		if healed[slot] > 0:
			parts.append("%s +%d" % [run.data.party[slot].display_name, healed[slot]])
	return "" if parts.is_empty() else "   Rain Pouch: " + "   ".join(parts)


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
	_menu.horizontal = true
	_menu.window_rows = 0
	_scene_box.visible = true
	_ask_label.visible = false
	_set_footer([[&"@leftright", "Choose"], [&"menu_confirm", "Select"]])
	var gift := _look.chip_gift_color
	var rest := {"text": "Rest", "enabled": not is_greyed(), "icon": _icon(_look.rest_icon_path), "chips": _rest_chips()}
	var middle := {"text": "Train", "enabled": not is_greyed(), "icon": _icon(_look.train_icon_path),
			"chips": [StopScreen.chip_entry(_look, "up", "+%d point%s" % [run.tuning.rest_train_points,
					"" if run.tuning.rest_train_points == 1 else "s"], gift)]}
	if run.is_watch_fire():
		middle = {"text": "Keep watch", "enabled": not is_greyed(), "icon": _icon(_look.watch_icon_path),
				"chips": [StopScreen.chip_entry(_look, "gauge", "Gauge full", gift)]}
	# Dim when no Relic can become Relic+ (on this machine's turn: the turn player's heroes').
	var upgrade := {"text": "Upgrade", "enabled": not is_greyed() and not upgradable_for().is_empty(),
			"icon": _icon(_look.upgrade_icon_path), "chips": [StopScreen.chip_entry(_look, "relic", UPGRADE_CHIP, gift)]}
	var list: Array[Dictionary] = [rest, middle, upgrade]
	_menu.set_items(list)


## The Upgrade pick: a card per Relic (_picks), three at a time, in the fire's place (the page is too
## short for the fire, the question and the tallest Relic cards at once).
func _show_picks() -> void:
	_menu.horizontal = true
	_menu.window_rows = PICK_SHOWN
	_scene_box.visible = false
	_ask_label.visible = true
	_set_footer([[&"@leftright", "Choose"], [&"menu_confirm", "Upgrade"], [&"menu_cancel", "Back"]])
	_menu.set_items(pick_cards(run, _picks, is_greyed()))
	_ask_label.text = pick_ask(_menu.index, _menu.items.size())


## "Which Relic?", and "(2 of 7)" while the row has more cards than it shows at once, so the player
## knows more wait to the sides.
static func pick_ask(index: int, count: int) -> String:
	if count <= PICK_SHOWN:
		return PICK_ASK
	return "%s  (%d of %d)" % [PICK_ASK, index + 1, count]


## One card per Relic in `items` for the Upgrade pick (ListMenu items): its icon, its name in its
## rarity's colour, chips for who holds it and what it does, then in gold what its "+" changes
## (LootScreen.plus_chips). No "detail" line: the chips say it, as on the Spoils. "relic" is the
## Relic's id.
static func pick_cards(p_run: RunState, items: Array[GearData], greyed: bool = false) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for item: GearData in items:
		var chips: Array[Dictionary] = []
		var holder := p_run.holder_of(item)
		if holder >= 0:
			var hero := p_run.data.party[holder]
			chips.append({"glyph": &"person", "text": hero.display_name, "color": hero.color.lightened(0.25)})
		for chip: Dictionary in LootScreen.relic_chips(item):
			if chips.size() == 1:
				chip["newline"] = true
			chips.append(chip)
		chips.append_array(LootScreen.plus_chips(item))
		var make := func() -> Control: return RelicIcon.make(item, PICK_ICON_PX)
		cards.append({"text": item.display_name, "enabled": not greyed, "chips": chips, "icon_make": make,
				"relic": item.id,
				"color": GearData.ROT_TOUCHED_COLOR if item.rot_touched else BackpackGrid.rarity_color(BackpackGrid.gear_step(item))})
	return cards


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


func _unhandled_input(event: InputEvent) -> void:
	if is_greyed():
		return
	var answer := _menu.handle(event)
	if _picking:
		_ask_label.text = pick_ask(_menu.index, _menu.items.size())
		_pick_input(answer)
		return
	if answer != &"confirm":
		return
	# A greyed card answers confirm too: refuse it here.
	if not _menu.is_enabled(_menu.index):
		Sfx.play("locked")
		return
	Sfx.play("menu_confirm")
	if _done_once:
		leave()
	else:
		match _menu.index:
			CARD_REST:
				rest_now()
			CARD_TRAIN:
				if run.is_watch_fire():
					watch_now()
				else:
					train_now()
			CARD_UPGRADE:
				if not open_upgrade(PlayerRoster.device_of(event)):
					# Local co-op: none of this player's heroes' Relics can be.
					Sfx.play("locked")


## The Upgrade pick's answer: Back to the three cards, or upgrade the chosen Relic.
func _pick_input(answer: StringName) -> void:
	if answer == &"cancel":
		Sfx.play("menu_cancel")
		close_upgrade()
	elif answer == &"confirm":
		var i := _menu.index
		var id := String(_menu.items[i].get("relic", "")) if i < _menu.items.size() else ""
		if id.is_empty() or not upgrade_now(id, _pick_device):
			Sfx.play("locked")
