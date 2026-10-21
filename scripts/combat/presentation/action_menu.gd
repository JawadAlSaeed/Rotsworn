class_name ActionMenu
extends Control
## The party member's action menu (card #154): Expedition 33's command diamond, floating beside
## the acting hero like Persona 5's (CombatHud calls follow() every frame with the hero's box on
## screen), drawn as Persona 5's layered slanted plates (a black plate over one in the hero's
## colour) around a thin gold ring with the hero's AP in its middle.
## - Main layer (user layout, 2026-10-13): every option has its own button and there is no cursor.
##   The four face buttons sit in a diamond, each with its plate beside it: A Attack (bottom; gains
##   AP; Confirm too), X Skills (left), Y Items (top), B Run (right). An option that cannot be used
##   now fades out. RT uses the Team Ultimate: its button is not in the diamond but on the team
##   gauge (CombatHud shows it there while ultimate_ready(); user, 2026-10-16). Keyboard keys show instead on the keyboard. No name tag: the gold light
##   under the hero and their lit card already say whose turn it is (user, 2026-10-15). Run must be HELD (run_hold_ms) so a tap never runs; a ring fills around its button while
##   held (DESIGN.md 2.13).
## - Skills and Items layers: the class skills, or the backpack items usable in fights (DESIGN.md
##   8.1), open beside the hero as a list of slanted rows (name and AP cost; one that cannot be used
##   now is greyed with a lock, its cost red when the hero is short of AP and the Hush icon when
##   Hushed, phase 22: the rules are in the tutorial and the Glossary, not on the row; at most
##   VISIBLE_ROWS at once, the list scrolls). Up/down
##   choose, confirm uses, cancel (or the same button) goes back. An item entry is flagged "item"
##   and its ability is a stand-in made by the controller.
##   Under the list, the chosen row in a few words (card #292): its short_text (the description
##   when it has none) over labelled icon chips worked out from its data (AP, who it reaches, hits,
##   damage, heal, cleanse, the mark it leaves...; ability_chips(), item_chips()). The full
##   description stays on the Y screen's Skills tab and in the Glossary.
## - Target step: if the ability needs a choice of target (an enemy, an ally, a downed ally) and
##   there is more than one, left/right or up/down cycles, confirm picks, cancel goes back to the
##   layer the ability came from. Its panel shows the skill's name and AP cost and the target's
##   name (phase 22: no title, no description; the lock-on frame shows the target too).
## Driven only by input actions (no focus-driven buttons, so the parry key can never click it).
## - Tutorial guide: with `guide` set (an ability id) only that choice can be made; its plate or
##   row (and the Skills plate that leads to it) glows, everything else is locked (DESIGN.md 7.8).
## The basic attack is the first entry that is not the team ultimate (CharacterData.all_abilities()
## puts it first), the ultimate is the entry flagged team_ultimate, the skills are the rest.

signal chosen(ability_id: String, target_id: int)
## The target being pointed at during the target step, or -1 when the step ends.
signal target_changed(target_id: int)
## The ultimate's button was pressed and it is being used (the gauge flashes).
signal ultimate_pressed

## The main options.
enum Option { ATTACK, SKILLS, ITEMS, RUN, ULTIMATE }

## The options drawn in the diamond (the ultimate's button lives on the team gauge).
const DIAMOND: Array[int] = [Option.ATTACK, Option.SKILLS, Option.ITEMS, Option.RUN]
## The button that picks each Option. Run is the Back button (B), which has nothing else to do on
## the main layer.
const OPTION_ACTIONS: Array[StringName] = [&"fight_attack", &"fight_skills", &"fight_items", &"menu_cancel",
		&"fight_ultimate"]
## Options shown but not in the game yet (cards on the board).
const SOON_OPTIONS: Array[int] = []
const HOLD_TAG := "HOLD"
const OPTION_NAMES: Array[String] = ["ATTACK", "SKILLS", "ITEMS", "RUN", ""]
const SOON_TAG := "SOON"
const SKILLS_TEXT := "Your class skills. They cost AP: attack and parry hits to gain it."
const ITEMS_TEXT := "Backpack items. Using one is your turn."
## Why an entry cannot be used now (its `reason`, set by the controller): short of AP, Hushed, the
## team gauge not full, nobody to target. Any other reason (the tutorial's) is a plain lock.
const LOCK_AP := "ap"
const LOCK_HUSHED := "hushed"
const LOCK_GAUGE := "gauge"
const LOCK_TARGET := "target"

## The diamond cluster (name tag, ring, sockets, plates), in its own coordinates.
const CLUSTER := Vector2(640.0, 370.0)
const DIAMOND_CENTRE := Vector2(310.0, 124.0)
## How far each button sits from the centre, and the socket size.
const ARM: float = 86.0
const SOCKET_PX: float = 66.0
## The ring's centre disc (the hero's AP).
const HUB_RADIUS: float = 40.0
const AP_SIZE: int = 40
const AP_LABEL_SIZE: int = 14
## Plates start this far beyond a socket's edge; the hero's coloured plate shows this far under
## the black one.
const PLATE_GAP: float = 8.0
const PLATE_HEIGHT: float = 50.0
const BACK_PLATE := Vector2(7.0, 6.0)
const PLATE_SIZE: int = 30
const TAG_SIZE: int = 19
const CHIP_SIZE: int = 32
## The diamond's centre sits this far right of the hero's box (room for the Skills plate).
const BESIDE_PX: float = 320.0
## Lists (skills, items) and the target panel open this far right of the hero.
const LIST_GAP: float = 48.0
const LIST_WIDTH: float = 500.0
const LIST_TITLE_SIZE: int = 30
const ROW_SIZE: int = 26
const ROW_HEIGHT: float = 40.0
const VISIBLE_ROWS: int = 6
const DESCRIPTION_SIZE: int = 21
## The chosen row's chips (card #292): their words' size, the gap between them, and how wide a
## line of them (and the short line over them) may grow inside the list panel before wrapping.
## Their pictures are visuals status_icon_px.
const DETAIL_CHIP_SIZE: int = 19
const DETAIL_CHIP_GAP: int = 6
const DETAIL_WIDTH: float = LIST_WIDTH - 60.0
## Who a skill reaches, by AbilityData.Target, and who a fight item reaches, by
## CombatEngine.item_target().
const TARGET_WORDS: Array[String] = ["One foe", "All foes", "Self", "One ally", "Other ally", "Downed ally",
		"Party"]
const ITEM_TARGET_WORDS := {"ally": "One ally", "party": "Party", "enemies": "All foes", "downed": "Downed ally"}
const HINT_SIZE: int = 19
const TARGET_NAME_SIZE: int = 40
## Spots tried beside the hero, in order (the first that covers no enemy wins): as planned, lower
## (onto the floor in front), closer, higher.
const CLUSTER_TRIES: Array[Vector2] = [Vector2(0, 0), Vector2(0, 90), Vector2(0, 180), Vector2(-60, 90),
		Vector2(-60, 180), Vector2(-90, 0), Vector2(0, -90), Vector2(60, 180), Vector2(-150, 180)]
const PANEL_TRIES: Array[Vector2] = [Vector2(0, 0), Vector2(0, 90), Vector2(0, 180), Vector2(0, -90),
		Vector2(-80, 120), Vector2(0, 260)]
## Following the hero as the camera moves: how fast (per second) the cluster catches up.
const FOLLOW_RATE: float = 14.0
## The entrance: the cluster pops from small and tilted, the buttons fly out of the centre, the
## plates slide out after them.
const POP_S: float = 0.26
const POP_SCALE: float = 0.55
const POP_TILT: float = -0.14
const STAGGER_S: float = 0.035
const SLIDE_PX: float = 46.0
## A plate that cannot be used fades to this.
const LOCKED_TINT := Color(0.62, 0.62, 0.66, 0.5)
const LOCKED_BACK := Color(0.35, 0.35, 0.38, 0.6)
## The ring around the Run button that fills while Back is held: size as a share of the socket,
## line width in pixels.
const HOLD_RING_SHARE: float = 1.2
const HOLD_RING_WIDTH: float = 5.0
const HOLD_RING_TRACK := Color(1.0, 1.0, 1.0, 0.18)
## The gold ring's slowly turning ticks.
const TICKS: int = 16
const TICK_SPIN: float = 0.25
## The tutorial's guided plate pulses between white and this, once per GUIDE_PULSE_S.
const GUIDE_GLOW := Color(1.6, 1.45, 0.9)
const GUIDE_PULSE_S: float = 0.9
## A pressed plate flashes this bright.
const PRESS_FLASH := Color(1.8, 1.7, 1.4)
const PRESS_FLASH_S: float = 0.16

## The tutorial's one allowed choice (an ability id; "" = any). The controller also marks every
## other entry unusable; this only lights the way to it.
var guide: String = ""
## How long Back must be held to run (ms; the controller sets it from tuning run_hold_ms).
var run_hold_ms: int = 500
## The look numbers (the lock's size and colour, status icon size); CombatHud sets them. Unset:
## the CombatVisuals defaults.
var visuals: CombatVisuals = null
## The acting hero, their AP and the most they can have (the controller sets them before open).
var actor_id: int = -1
var actor_ap: int = 0
var max_ap: int = 0

var _accent: Color = HudStyle.GOLD
## The diamond cluster: the name tag, the ring, a socket and a plate per Option.
var _cluster: Cluster
var _ap_label: Label
var _ap_caption: Label
var _sockets: Array[Socket] = []
var _plates: Array[PanelContainer] = []
var _plate_names: Array[Label] = []
var _plate_tags: Array[Label] = []
## Each plate's look when it is in place (the entrance animates to it).
var _plate_rest: Array[Color] = []
var _hold_ring: HoldRing
## The list layer.
var _list: PanelContainer
var _list_title: Label
var _list_ap: Label
var _rows_box: VBoxContainer
var _more_above: Label
var _more_below: Label
## The chosen row's short line and its chips (lines of chips, card #292).
var _description: Label
var _chip_box: VBoxContainer
var _hint: HintBar
var _row_panels: Array[PanelContainer] = []
var _row_names: Array[Label] = []
var _row_costs: Array[Label] = []
var _row_marks: Array[Label] = []
## Each row's lock (it cannot be used now) and Hush icon (the hero is Hushed).
var _row_locks: Array[UiGlyph] = []
var _row_hush: Array[TextureRect] = []
## The target layer: the skill's name and AP cost over the target's name.
var _target: PanelContainer
var _target_skill: Label
var _target_cost: Label
var _target_name: Label
var _target_hint: HintBar
## Where the hero is on screen, the area the menu must stay in, and whether the cluster has been
## placed since it opened (the first placement snaps, later ones glide).
var _body: Rect2 = Rect2()
var _safe: Rect2 = Rect2()
var _avoid: Array[Rect2] = []
## The cluster's drawn parts (plates, sockets, ring, name tag) in its own coordinates.
var _content: Rect2 = Rect2(Vector2.ZERO, CLUSTER)
var _placed: bool = false
## Each: {ability: AbilityData, usable: bool, reason: String (a LOCK_* code, "" when usable),
## targets: Array[int], pick_target: bool}.
var _entries: Array[Dictionary] = []
var _names: Dictionary = {}
## Indexes into _entries (-1: not offered).
var _attack_entry: int = -1
var _ultimate_entry: int = -1
var _run_entry: int = -1
## When the Back hold started (Time ticks, ms), or -1 when Back is not held.
var _hold_started_ms: int = -1
## The list open (the skills or the items), and both lists.
var _skill_entries: Array[int] = []
var _skills_all: Array[int] = []
var _items_all: Array[int] = []
## Which list is open (Option.SKILLS or Option.ITEMS).
var _listing: int = Option.SKILLS
## The option last used (Attack until something else is picked).
var _option: int = Option.ATTACK
var _in_skills: bool = false
## The chosen row (index into _skill_entries) and the first row shown.
var _skill_cursor: int = 0
var _scroll: int = 0
var _choosing_target: bool = false
## The entry whose target is being chosen.
var _target_entry: int = -1
var _target_index: int = 0
## Which layer was shown last (so only a change animates in): "main", "list" or "target".
var _shown_layer: String = ""
## Process frame of the last stick move (a held stick sends many motion events).
var _stick_frame: int = -1
## The guided plate or row and its glow.
var _guide_node: Control = null
var _guide_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_main()
	_build_list()
	_build_target()
	visible = false
	ButtonPrompts.listen(_relayout_later)


## The button pictures changed (keyboard or pad): their widths too, so the plates move.
func _relayout_later() -> void:
	if visible:
		_layout_plates.call_deferred()


## Opens the menu for one actor (`accent`: their colour). `entries` as described on _entries;
## `names` maps fighter id -> display name (for the target step).
func open(accent: Color, entries: Array[Dictionary], names: Dictionary) -> void:
	if _choosing_target:
		target_changed.emit(-1)
	_accent = accent
	_ap_label.text = str(actor_ap)
	_cluster.accent = accent
	_entries = entries
	_names = names
	_sort_entries()
	_choosing_target = false
	_target_entry = -1
	_in_skills = false
	_hold_started_ms = -1
	_option = _home_option()
	_skill_cursor = 0
	_scroll = 0
	_shown_layer = ""
	_placed = false
	_build_rows()
	visible = true
	_redraw()


func close() -> void:
	visible = false
	_shown_layer = ""
	_redraw_guide()
	if _choosing_target:
		_choosing_target = false
		target_changed.emit(-1)


func is_open() -> bool:
	return visible


## True while the Team Ultimate can be used now (the gauge shows its button then).
func ultimate_ready() -> bool:
	return visible and not _in_skills and not _choosing_target and _ultimate_entry >= 0 \
			and bool(_entries[_ultimate_entry].usable)


## True while the skills or items list is up.
func is_listing() -> bool:
	return visible and _in_skills and not _choosing_target


## Places the menu beside the hero (`body`: their box on screen), inside `safe` (the screen minus
## the turn order strip and the party cards). CombatHud calls it every frame while the menu is
## open, so the menu follows the camera.
## `avoid` are boxes it should not cover (the enemies and their panels): of a few spots beside the
## hero it takes the first that covers the least of them.
func follow(body: Rect2, safe: Rect2, avoid: Array[Rect2], delta: float) -> void:
	_body = body
	_safe = safe
	_avoid = avoid
	if not visible:
		return
	var wanted := _cluster_spot()
	if not _placed:
		_cluster.position = wanted
		_placed = true
	else:
		_cluster.position = _cluster.position.lerp(wanted, 1.0 - exp(-FOLLOW_RATE * delta))
	if _list.visible:
		_place_panel(_list)
	if _target.visible:
		_place_panel(_target)


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
		_shown_layer = ""
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


## The option a layer goes back to: Attack, so the attack button (also a confirm button) always
## means Attack until the player picks something else.
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


## Skills, Items and Run are always shown (faded when not usable); Attack only when offered. The
## ultimate is never drawn here (its button is on the team gauge).
func _option_shown(option: int) -> bool:
	return option in [Option.SKILLS, Option.ITEMS, Option.RUN] or (option == Option.ATTACK and _attack_entry >= 0)


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
	if option == Option.ULTIMATE:
		if _ultimate_entry < 0 or not bool(_entries[_ultimate_entry].usable):
			Sfx.play("locked")
			return
		_option = option
		ultimate_pressed.emit()
		_use_entry(_ultimate_entry)
		return
	if not _option_shown(option) or option in SOON_OPTIONS:
		Sfx.play("locked")
		return
	_option = option
	if option != Option.SKILLS and option != Option.ITEMS:
		_flash(_plates[option])
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
		_scroll = 0
		_build_rows()
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
	if not visible:
		return
	_cluster.queue_redraw()
	if _hold_started_ms < 0:
		return
	if _in_skills or _choosing_target:
		_stop_hold()
		return
	var held := Time.get_ticks_msec() - _hold_started_ms
	_hold_ring.set_progress(clampf(float(held) / float(maxi(1, run_hold_ms)), 0.0, 1.0))
	if held >= run_hold_ms:
		_hold_started_ms = -1
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
	_shown_layer = ""
	chosen.emit((entry.ability as AbilityData).id, _default_target(entry))


## Lights the plate or row of an entry (the bot's picks show like a player's).
func _show_entry(index: int) -> void:
	if index == _attack_entry:
		_in_skills = false
		_option = Option.ATTACK
	elif index == _ultimate_entry:
		_in_skills = false
		_option = Option.ULTIMATE
	elif index == _run_entry:
		_in_skills = false
		_option = Option.RUN
	else:
		var listing := Option.ITEMS if _items_all.has(index) else Option.SKILLS
		if _listing != listing:
			_listing = listing
			_skill_entries = (_items_all if listing == Option.ITEMS else _skills_all).duplicate()
			_build_rows()
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


# --- building -----------------------------------------------------------------------------------

## A slanted black plate over a plate in `back` (Persona 5's layered print look).
static func _plate_style(back: Color, border_px: int = 2, height: float = PLATE_HEIGHT) -> StyleBoxFlat:
	var style := HudStyle.slant(HudStyle.INK_SOLID, HudStyle.EDGE, border_px, 6, height)
	style.shadow_color = back
	style.shadow_size = 1
	style.shadow_offset = BACK_PLATE
	return style


## Where each Option's socket sits in the cluster (the diamond: Y top, X left, B right, A
## bottom). The ultimate has no socket in the diamond: its button sits on its own plate.
static func _socket_spot(option: int) -> Vector2:
	match option:
		Option.ATTACK:
			return DIAMOND_CENTRE + Vector2(0.0, ARM)
		Option.SKILLS:
			return DIAMOND_CENTRE + Vector2(-ARM, 0.0)
		Option.ITEMS:
			return DIAMOND_CENTRE + Vector2(0.0, -ARM)
		Option.RUN:
			return DIAMOND_CENTRE + Vector2(ARM, 0.0)
	return DIAMOND_CENTRE


func _build_main() -> void:
	_cluster = Cluster.new()
	_cluster.size = CLUSTER
	_cluster.pivot_offset = DIAMOND_CENTRE
	add_child(_cluster)
	# The hub: the hero's AP in the middle of the ring.
	_ap_label = HudStyle.make_number("", AP_SIZE, HudStyle.AP_TEXT)
	_ap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cluster.add_child(_ap_label)
	_ap_caption = HudStyle.make_title("AP", AP_LABEL_SIZE, HudStyle.AP_TEXT)
	_ap_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cluster.add_child(_ap_caption)
	for option: int in Option.size():
		if not DIAMOND.has(option):
			_sockets.append(null)
			_plates.append(null)
			_plate_names.append(null)
			_plate_tags.append(null)
			_plate_rest.append(Color.WHITE)
			continue
		var socket := Socket.new()
		socket.diameter = SOCKET_PX
		socket.add_child(_chip(OPTION_ACTIONS[option]))
		_sockets.append(socket)
		var plate := PanelContainer.new()
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_theme_stylebox_override("panel", _plate_style(_accent))
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 10)
		plate.add_child(line)
		var label := HudStyle.make_title(OPTION_NAMES[option], PLATE_SIZE)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(label)
		var tag := HudStyle.make_title("", TAG_SIZE)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(tag)
		_cluster.add_child(plate)
		_cluster.add_child(socket)
		_plates.append(plate)
		_plate_names.append(label)
		_plate_tags.append(tag)
		_plate_rest.append(Color.WHITE)
	# A ring around the Run button fills up while Back is held.
	_hold_ring = HoldRing.new()
	_hold_ring.radius = SOCKET_PX * HOLD_RING_SHARE * 0.5
	_sockets[Option.RUN].add_child(_hold_ring)
	_hold_ring.position = Vector2(SOCKET_PX, SOCKET_PX) * 0.5


## A button picture that follows keyboard or pad.
func _chip(action: StringName) -> HintBar:
	return HintBar.new([[action, ""]], CHIP_SIZE, HudStyle.TEXT)


func _build_list() -> void:
	_list = PanelContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.custom_minimum_size = Vector2(LIST_WIDTH, 0.0)
	_list.visible = false
	add_child(_list)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	_list.add_child(column)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	_list_title = HudStyle.make_title("", LIST_TITLE_SIZE, HudStyle.GOLD)
	_list_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_list_title)
	_list_ap = HudStyle.make_title("", LIST_TITLE_SIZE - 6, HudStyle.AP_TEXT)
	_list_ap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_list_ap)
	_more_above = HudStyle.make_label("▲", 16, HudStyle.EDGE)
	_more_above.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_more_above)
	_rows_box = VBoxContainer.new()
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_box.add_theme_constant_override("separation", 4)
	column.add_child(_rows_box)
	_more_below = HudStyle.make_label("▼", 16, HudStyle.EDGE)
	_more_below.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_more_below)
	column.add_child(ListMenu.divider(LIST_WIDTH - 60.0))
	_description = HudStyle.make_label("", DESCRIPTION_SIZE)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(DETAIL_WIDTH, 0.0)
	column.add_child(_description)
	_chip_box = VBoxContainer.new()
	_chip_box.name = "SkillChips"
	_chip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_box.add_theme_constant_override("separation", DETAIL_CHIP_GAP)
	column.add_child(_chip_box)
	_hint =HintBar.new([[&"@updown", "Choose"], [&"menu_confirm", "Use"], [&"menu_cancel", "Back"]], HINT_SIZE)
	_hint.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(_hint)


func _build_target() -> void:
	_target = PanelContainer.new()
	_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target.custom_minimum_size = Vector2(LIST_WIDTH, 0.0)
	_target.visible = false
	add_child(_target)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	_target.add_child(column)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	_target_skill = HudStyle.make_title("", LIST_TITLE_SIZE, HudStyle.GOLD)
	_target_skill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_skill.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_target_skill)
	_target_cost = HudStyle.make_title("", LIST_TITLE_SIZE - 6, HudStyle.AP_TEXT)
	_target_cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_target_cost)
	_target_name = HudStyle.make_title("", TARGET_NAME_SIZE)
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_target_name)
	_target_hint = HintBar.new([[&"@leftright", "Target"], [&"menu_confirm", "Go"], [&"menu_cancel", "Back"]], HINT_SIZE)
	_target_hint.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(_target_hint)


func _build_rows() -> void:
	for row: PanelContainer in _row_panels:
		_rows_box.remove_child(row)
		row.queue_free()
	_row_panels.clear()
	_row_names.clear()
	_row_costs.clear()
	_row_marks.clear()
	_row_locks.clear()
	_row_hush.clear()
	var look := _look()
	for i: int in mini(VISIBLE_ROWS, _skill_entries.size()):
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 10)
		row.add_child(line)
		var mark := HudStyle.make_title("▶", ROW_SIZE - 8, HudStyle.GOLD)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(mark)
		var label := HudStyle.make_title("", ROW_SIZE)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(label)
		var hush := HudStyle.icon(HudStyle.mark_icon(Status.HUSHED), look.status_icon_px)
		hush.visible = false
		line.add_child(hush)
		var lock := UiGlyph.make(&"lock", look.menu_lock_px, HudStyle.TEXT_DIM)
		lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lock.visible = false
		line.add_child(lock)
		var cost := HudStyle.make_title("", ROW_SIZE - 4)
		cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(cost)
		_rows_box.add_child(row)
		_row_panels.append(row)
		_row_names.append(label)
		_row_costs.append(cost)
		_row_marks.append(mark)
		_row_locks.append(lock)
		_row_hush.append(hush)


# --- placing ------------------------------------------------------------------------------------

## The cluster's top-left: the diamond's centre BESIDE_PX right of the hero, at their middle,
## kept inside the safe area (without a hero box: the bottom-right corner of it).
func _cluster_spot() -> Vector2:
	var safe := _safe if _safe.size.x > 0.0 else Rect2(Vector2.ZERO, size)
	if _body.size.x <= 0.0:
		return _fit(safe.end - _content.end, _content, safe)
	var home := Vector2(_body.end.x + BESIDE_PX, _body.get_center().y) - DIAMOND_CENTRE
	return _best_spot(home, _content, safe, CLUSTER_TRIES)


## Moves `spot` so `content` (offset by it) stays inside `safe`.
static func _fit(spot: Vector2, content: Rect2, safe: Rect2) -> Vector2:
	spot.x = clampf(spot.x, safe.position.x - content.position.x, maxf(safe.position.x - content.position.x,
			safe.end.x - content.end.x))
	spot.y = clampf(spot.y, safe.position.y - content.position.y, maxf(safe.position.y - content.position.y,
			safe.end.y - content.end.y))
	return spot.round()


## Of `home` moved by each of `tries` (kept inside `safe`), the first spot where `content` covers
## the least of the boxes to avoid.
func _best_spot(home: Vector2, content: Rect2, safe: Rect2, tries: Array[Vector2]) -> Vector2:
	var best := _fit(home, content, safe)
	var best_cover := INF
	for offset: Vector2 in tries:
		var spot := _fit(home + offset, content, safe)
		var box := Rect2(content.position + spot, content.size)
		# The acting hero counts double: the menu stands beside them, never on them.
		var cover := box.intersection(_body.grow(12.0)).get_area() * 2.0
		for other: Rect2 in _avoid:
			cover += box.intersection(other).get_area()
		if cover < best_cover - 1.0:
			best_cover = cover
			best = spot
	return best


## A list or the target panel beside the hero (or where the cluster is), inside the safe area.
func _place_panel(panel: Control) -> void:
	panel.reset_size()
	var safe := _safe if _safe.size.x > 0.0 else Rect2(Vector2.ZERO, size)
	var box := Rect2(Vector2.ZERO, panel.size)
	if _body.size.x <= 0.0:
		panel.position = _fit(safe.end - panel.size, box, safe)
		return
	var home := Vector2(_body.end.x + LIST_GAP, _body.get_center().y - panel.size.y * 0.5)
	panel.position = _best_spot(home, box, safe, PANEL_TRIES)


## Every plate beside its socket (a long keyboard key makes its socket wider), the AP in the hub.
func _layout_plates() -> void:
	_ap_label.reset_size()
	_ap_label.position = DIAMOND_CENTRE - Vector2(_ap_label.size.x * 0.5, _ap_label.size.y * 0.62)
	_ap_caption.reset_size()
	_ap_caption.position = DIAMOND_CENTRE + Vector2(-_ap_caption.size.x * 0.5, HUB_RADIUS * 0.3)
	for option: int in DIAMOND:
		var plate := _plates[option]
		if not plate.visible:
			continue
		var socket := _sockets[option]
		socket.outward = -1.0 if option == Option.SKILLS else (1.0 if option == Option.RUN else 0.0)
		socket.position = _socket_spot(option) - Vector2(socket.diameter, socket.diameter) * 0.5
		plate.reset_size()
		var spot := _socket_spot(option)
		var y := spot.y - plate.size.y * 0.5
		match option:
			Option.SKILLS:
				plate.position = Vector2(spot.x - socket.reach(-1.0) - PLATE_GAP - plate.size.x, y)
			_:
				plate.position = Vector2(spot.x + socket.reach(1.0) + PLATE_GAP, y)
		plate.position = plate.position.round()
	var ring := ARM + 16.0
	_content = Rect2(DIAMOND_CENTRE - Vector2(ring, ring), Vector2(ring, ring) * 2.0)
	for option: int in DIAMOND:
		if _plates[option].visible:
			_content = _content.merge(Rect2(_plates[option].position, _plates[option].size + BACK_PLATE))


# --- drawing ------------------------------------------------------------------------------------

func _redraw() -> void:
	var layer := "main"
	if _choosing_target:
		layer = "target"
	elif _in_skills:
		layer = "list"
	_cluster.visible = layer == "main"
	_list.visible = layer == "list"
	_target.visible = layer == "target"
	match layer:
		"main":
			_redraw_main()
		"list":
			_redraw_list()
		"target":
			_redraw_target()
	if not _placed:
		_cluster.position = _cluster_spot()
		_placed = true
	_layout_plates()
	if _list.visible:
		_place_panel(_list)
	if _target.visible:
		_place_panel(_target)
	if layer != _shown_layer and visible:
		_shown_layer = layer
		_animate_in(layer)
	_redraw_guide()


## The diamond's plates: usable ones black over the hero's colour, the rest faded and grey.
func _redraw_main() -> void:
	_ap_label.text = str(actor_ap)
	for option: int in DIAMOND:
		var plate := _plates[option]
		var socket := _sockets[option]
		var shown := _option_shown(option)
		plate.visible = shown
		socket.visible = shown
		if not shown:
			continue
		var usable := _option_usable(option)
		var entry := _option_entry(option)
		var ability: AbilityData = (_entries[entry].ability as AbilityData) if entry >= 0 else null
		var tag := ""
		var tag_color := HudStyle.AP_TEXT
		if usable:
			match option:
				Option.RUN:
					tag = HOLD_TAG
					tag_color = HudStyle.JUMP
				Option.ITEMS:
					tag = str(_items_all.size())
				Option.ATTACK:
					tag = _cost_text(ability) if ability != null else ""
		if option in SOON_OPTIONS:
			tag = SOON_TAG
		_plate_names[option].label_settings.font_color = HudStyle.TEXT if usable else HudStyle.TEXT_DIM
		_plate_tags[option].text = tag
		_plate_tags[option].visible = not tag.is_empty()
		_plate_tags[option].label_settings.font_color = tag_color
		var back := _accent if usable else LOCKED_BACK
		var style := _plate_style(back)
		style.border_color = HudStyle.EDGE if usable else HudStyle.EDGE_DIM
		plate.add_theme_stylebox_override("panel", style)
		_plate_rest[option] = Color.WHITE if usable else LOCKED_TINT
		plate.modulate = _plate_rest[option]
		socket.modulate = _plate_rest[option]
		socket.ring = _accent.lightened(0.2) if usable else HudStyle.EDGE_DIM
		socket.queue_redraw()


## The skills or items list: the rows in view, the chosen one lit, the description under them.
func _redraw_list() -> void:
	_list.add_theme_stylebox_override("panel", _list_style())
	_list_title.text = "SKILLS" if _listing == Option.SKILLS else "ITEMS"
	_list_ap.text = "AP  %d / %d" % [actor_ap, max_ap] if max_ap > 0 else ""
	if _skill_cursor < _scroll:
		_scroll = _skill_cursor
	elif _skill_cursor >= _scroll + VISIBLE_ROWS:
		_scroll = _skill_cursor - VISIBLE_ROWS + 1
	_scroll = clampi(_scroll, 0, maxi(0, _skill_entries.size() - VISIBLE_ROWS))
	_more_above.modulate.a = 1.0 if _scroll > 0 else 0.0
	_more_below.modulate.a = 1.0 if _scroll + VISIBLE_ROWS < _skill_entries.size() else 0.0
	for i: int in _row_panels.size():
		var index := _scroll + i
		var row := _row_panels[i]
		row.visible = index < _skill_entries.size()
		if not row.visible:
			continue
		var entry: Dictionary = _entries[_skill_entries[index]]
		var ability := entry.ability as AbilityData
		var lit := index == _skill_cursor
		var usable := bool(entry.usable)
		_row_names[i].text = ability.display_name
		_row_costs[i].text = _cost_text(ability)
		var color := HudStyle.TEXT if usable else HudStyle.TEXT_DIM
		if lit and usable:
			color = Color.WHITE
		_row_names[i].label_settings.font_color = color
		# A row that cannot be used: a lock, red (with its cost) when AP or Hush is the reason, and
		# the Hush icon when Hushed. Why and how to fix it is the tutorial's and the Glossary's job.
		var lock := "" if usable else String(entry.get("reason", ""))
		var red := _look().locked_cost_color
		var cost_color := HudStyle.AP_TEXT
		if not usable:
			cost_color = red if lock == LOCK_AP else HudStyle.TEXT_DIM
		_row_costs[i].label_settings.font_color = cost_color
		_row_locks[i].visible = not usable
		_row_locks[i].color = red if lock == LOCK_AP or lock == LOCK_HUSHED else HudStyle.TEXT_DIM
		_row_locks[i].queue_redraw()
		_row_hush[i].visible = lock == LOCK_HUSHED
		_row_marks[i].modulate.a = 1.0 if lit else 0.0
		var style: StyleBoxFlat
		if lit:
			style = _plate_style(_accent if usable else LOCKED_BACK, 2, ROW_HEIGHT)
			style.bg_color = Color(_accent.darkened(0.55), 0.97) if usable else HudStyle.INK_SOLID
			style.border_color = HudStyle.GOLD if usable else HudStyle.EDGE_DIM
		else:
			style = HudStyle.slant(Color(1.0, 1.0, 1.0, 0.04), Color(0, 0, 0, 0), 0, 4, ROW_HEIGHT, HudStyle.SLANT, false)
		row.add_theme_stylebox_override("panel", style)
	var focus := _skill_entries[_skill_cursor] if not _skill_entries.is_empty() else -1
	if focus >= 0:
		_description.text = short_line(_entries[focus])
		_show_chips(entry_chips(_entries[focus], _look().ap_pip_path))
	else:
		_description.text = ITEMS_TEXT if _listing == Option.ITEMS else SKILLS_TEXT
		_show_chips([])


## Lays `chips` out under the short line: each an icon with its word, packed in lines at most
## DETAIL_WIDTH wide (a bigger text size makes more lines, never a wider panel).
func _show_chips(chips: Array[Dictionary]) -> void:
	for line: Node in _chip_box.get_children():
		_chip_box.remove_child(line)
		line.queue_free()
	var icon_px := _look().status_icon_px
	var line: HBoxContainer = null
	for i: int in chips.size():
		var chip := chips[i]
		var node := MapScreen.icon_chip(chip.icon, String(chip.text), chip.color as Color, icon_px, DETAIL_CHIP_SIZE)
		node.name = "Chip%d" % i
		if line == null:
			line = _chip_line()
		# Measured on the line, in the tree: a chip's plate margins and the gaps only count once
		# their theme overrides apply, so a chip measured on its own comes out too narrow.
		line.add_child(node)
		if line.get_child_count() > 1 and line.get_combined_minimum_size().x > DETAIL_WIDTH:
			line.remove_child(node)
			line = _chip_line()
			line.add_child(node)
	_chip_box.visible = not chips.is_empty()


## A new, empty line of chips at the bottom of the chip box.
func _chip_line() -> HBoxContainer:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", DETAIL_CHIP_GAP)
	_chip_box.add_child(line)
	return line


## The chosen row's line: the item's or the skill's short_text, or its description when it has
## none (so the line is never blank).
static func short_line(entry: Dictionary) -> String:
	var item := entry.get("item_data") as ItemData
	if item != null and not item.short_text.is_empty():
		return item.short_text
	var ability := entry.ability as AbilityData
	if not ability.short_text.is_empty():
		return ability.short_text
	if item != null and not item.description.is_empty():
		return item.description
	return ability.description


## The chips of a menu entry: a fight item's from the item itself when the controller gave it
## ("item_data", "amount"), else from its ability (a stand-in item's: who it reaches and its cost).
static func entry_chips(entry: Dictionary, ap_icon: Variant) -> Array[Dictionary]:
	var item := entry.get("item_data") as ItemData
	if item != null:
		return item_chips(item, int(entry.get("amount", item.amount_percent)), ap_icon)
	return ability_chips(entry.ability as AbilityData, ap_icon, bool(entry.get("item", false)))


## One chip: {icon (a Texture2D, a UiGlyph kind or a picture path; see MapScreen.icon_picture), text,
## color}.
static func _chip_data(icon: Variant, text: String, color: Color = HudStyle.TEXT) -> Dictionary:
	return {"icon": icon, "text": text, "color": color}


## A status's chip: its icon and its word ("SLOWED 2"), "if perfect" when only an all-perfect press
## puts it on.
static func _status_chip_data(id: String, turns: int, needs_perfect: bool = false) -> Dictionary:
	var word := String(HudStyle.STATUS_NAMES.get(id, id.to_upper()))
	if turns > 0:
		word += " %d" % turns
	if needs_perfect:
		word += " if perfect"
	var texture := HudStyle.mark_icon(id)
	return _chip_data(texture if texture != null else &"star", word, HudStyle.STATUS_COLORS.get(id, HudStyle.TEXT) as Color)


## "Cleanse 1", or "Cleanse all" for Status.CLEANSE_ALL.
static func _cleanse_chip_data(count: int) -> Dictionary:
	var text := "Cleanse all" if count >= Status.CLEANSE_ALL else "Cleanse %d" % count
	return _chip_data(&"leaf", text, HudStyle.HEAL)


## A skill's chips, in reading order, from its data (card #292): its AP cost or gain, who it
## reaches, its hits and damage, what it heals or lifts, the marks it leaves, what it does to turns
## and AP. The perfect-press bonuses stay in the description. `as_item`: a fight item's stand-in
## (it reaches the party when it targets SELF, and its damage is not the user's).
static func ability_chips(ability: AbilityData, ap_icon: Variant, as_item: bool = false) -> Array[Dictionary]:
	var chips: Array[Dictionary] = []
	if ability.ap_cost > 0:
		chips.append(_chip_data(ap_icon, "%d AP" % ability.ap_cost, HudStyle.AP_TEXT))
	if ability.ap_gain > 0:
		chips.append(_chip_data(ap_icon, "+%d AP" % ability.ap_gain, HudStyle.AP_TEXT))
	if ability.team_ultimate:
		chips.append(_chip_data(&"person", "All heroes", HudStyle.GOLD))
	var reach := TARGET_WORDS[clampi(ability.target, 0, TARGET_WORDS.size() - 1)]
	if as_item and ability.target == AbilityData.Target.SELF:
		reach = TARGET_WORDS[AbilityData.Target.ALL_ALLIES]
	chips.append(_chip_data(&"skull" if ability.targets_enemies() else &"person", reach))
	if as_item:
		if ability.cleanse_count > 0:
			chips.append(_cleanse_chip_data(ability.cleanse_count))
		return chips
	var hits := ability.press_times_ms.size()
	if ability.damage_percent > 0 and ability.targets_enemies():
		if hits > 1:
			chips.append(_chip_data(&"chevrons", "Hits %d" % hits))
		chips.append(_chip_data(&"sword", "%d%% dmg" % ability.damage_percent, HudStyle.DAMAGE_DEALT))
	if ability.per_perfect_defense_percent > 0:
		chips.append(_chip_data(&"shield", "+%d%% per parry" % ability.per_perfect_defense_percent, HudStyle.PARRY))
	if ability.exposed_bonus_percent > 0:
		var exposed := _status_chip_data(Status.EXPOSED, 0)
		exposed.text = "+%d%% vs %s" % [ability.exposed_bonus_percent, exposed.text]
		chips.append(exposed)
	if ability.heal_percent > 0:
		chips.append(_chip_data(&"heart", "Heal %d%%" % ability.heal_percent, HudStyle.HEAL))
	if ability.revive_percent > 0:
		chips.append(_chip_data(&"heart", "Revive %d%%" % ability.revive_percent, HudStyle.HEAL))
	if ability.team_ultimate:
		chips.append(_chip_data(&"heart", "Revive all", HudStyle.HEAL))
	if ability.cleanse_count > 0:
		chips.append(_cleanse_chip_data(ability.cleanse_count))
	if not ability.status.is_empty():
		chips.append(_status_chip_data(ability.status, ability.status_turns, ability.status_needs_perfect))
	if not ability.self_status.is_empty() and ability.self_status != ability.status:
		chips.append(_status_chip_data(ability.self_status, ability.self_status_turns))
	if ability.turn_delay_percent > 0:
		chips.append(_chip_data(&"bolt", "Turn later", HudStyle.STATUS_COLORS.get(Status.SLOWED, HudStyle.TEXT) as Color))
	if ability.turn_hasten_percent > 0:
		chips.append(_chip_data(&"bolt", "Turn sooner", HudStyle.JUMP))
	if ability.give_ap > 0:
		chips.append(_chip_data(ap_icon, "Give %d AP" % ability.give_ap, HudStyle.AP_TEXT))
	if ability.gauge_gain > 0:
		chips.append(_chip_data(&"up", "Gauge +%d" % ability.gauge_gain, HudStyle.GAUGE_FILL))
	if ability.escape:
		chips.append(_chip_data(&"star", "Perfect only", HudStyle.GOLD))
	return chips


## A fight item's chips (card #292): its AP cost, who it reaches, and what it does with `amount`
## (its percent at the item's level).
static func item_chips(item: ItemData, amount: int, ap_icon: Variant) -> Array[Dictionary]:
	var chips: Array[Dictionary] = []
	if item.ap_cost > 0:
		chips.append(_chip_data(ap_icon, "%d AP" % item.ap_cost, HudStyle.AP_TEXT))
	var reach := CombatEngine.item_target(item)
	chips.append(_chip_data(&"skull" if reach == CombatEngine.ITEM_ENEMIES else &"person",
			String(ITEM_TARGET_WORDS.get(reach, TARGET_WORDS[AbilityData.Target.ALL_ALLIES]))))
	match item.effect:
		ItemData.Effect.DAMAGE_ALL:
			chips.append(_chip_data(&"sword", "%d%% dmg" % amount, HudStyle.DAMAGE_DEALT))
		ItemData.Effect.HEAL_ONE, ItemData.Effect.HEAL_ALL:
			chips.append(_chip_data(&"heart", "Heal %d%%" % amount, HudStyle.HEAL))
		ItemData.Effect.REVIVE_ONE:
			chips.append(_chip_data(&"heart", "Revive %d%%" % amount, HudStyle.HEAL))
		ItemData.Effect.CLEANSE_ONE, ItemData.Effect.CLEANSE_ALL:
			if item.cleanse_count > 0:
				chips.append(_cleanse_chip_data(item.cleanse_count))
			if amount > 0:
				chips.append(_chip_data(&"heart", "Heal %d%%" % amount, HudStyle.HEAL))
	if item.cleanse_count > 0 and item.effect in [ItemData.Effect.HEAL_ONE, ItemData.Effect.HEAL_ALL]:
		chips.append(_cleanse_chip_data(item.cleanse_count))
	return chips


func _redraw_target() -> void:
	_target.add_theme_stylebox_override("panel", _list_style())
	var entry: Dictionary = _entries[_target_entry]
	var targets: Array = entry.targets
	var target := int(targets[_target_index])
	var arrows := targets.size() > 1
	_target_name.text = ("◀   %s   ▶" if arrows else "%s") % String(_names.get(target, "?")).to_upper()
	var ability := entry.ability as AbilityData
	_target_skill.text = ability.display_name
	_target_cost.text = _cost_text(ability)
	_target_cost.visible = not _target_cost.text.is_empty()


## The look numbers: `visuals`, or the CombatVisuals defaults when the HUD has not set them.
func _look() -> CombatVisuals:
	if visuals == null:
		visuals = CombatVisuals.new()
	return visuals


## The list and target panels: black, gold edge, the hero's colour showing under them.
func _list_style() -> StyleBoxFlat:
	var style := HudStyle.slant(HudStyle.INK_SOLID, HudStyle.EDGE, 2, 16, 400.0, 0.06)
	style.shadow_color = Color(_accent, 0.9)
	style.shadow_size = 1
	style.shadow_offset = BACK_PLATE * 1.4
	return style


## A layer arrives: the diamond pops in small and tilted, its buttons fly out of the centre and
## the plates slide out after them; a list or the target panel slides in from the side.
func _animate_in(layer: String) -> void:
	if layer == "main":
		_cluster.scale = Vector2.ONE * POP_SCALE
		_cluster.rotation = POP_TILT
		_cluster.modulate.a = 0.0
		var pop := _cluster.create_tween().set_parallel(true)
		pop.tween_property(_cluster, "scale", Vector2.ONE, POP_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(_cluster, "rotation", 0.0, POP_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(_cluster, "modulate:a", 1.0, POP_S * 0.5)
		var order: Array[int] = [Option.ATTACK, Option.SKILLS, Option.ITEMS, Option.RUN]
		for i: int in order.size():
			var option := order[i]
			var socket := _sockets[option]
			if socket.visible:
				var home := socket.position
				socket.position = DIAMOND_CENTRE - socket.size * 0.5
				var fly := socket.create_tween()
				fly.tween_property(socket, "position", home, POP_S).set_delay(STAGGER_S * i) \
						.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			var plate := _plates[option]
			if plate.visible:
				var rest := plate.position
				var from := DIAMOND_CENTRE.x - plate.size.x * 0.5
				plate.position = Vector2(lerpf(rest.x, from, 0.35), rest.y)
				plate.modulate = Color(_plate_rest[option], 0.0)
				var slide := plate.create_tween().set_parallel(true)
				slide.tween_property(plate, "position", rest, POP_S).set_delay(STAGGER_S * (i + 2)) \
						.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				slide.tween_property(plate, "modulate", _plate_rest[option], POP_S * 0.6).set_delay(STAGGER_S * (i + 2))
		return
	var panel := _list if layer == "list" else _target
	var home := panel.position
	panel.position = home + Vector2(-SLIDE_PX, 0.0)
	panel.modulate.a = 0.0
	var tween := panel.create_tween().set_parallel(true)
	tween.tween_property(panel, "position", home, POP_S * 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, POP_S * 0.5)


## A plate flashes bright for a moment when its button is pressed.
func _flash(node: Control) -> void:
	node.modulate = PRESS_FLASH
	node.create_tween().tween_property(node, "modulate", Color.WHITE, PRESS_FLASH_S)


## The tutorial's guided plate or row pulses: the option leading to it, or the skill in the open
## list.
func _redraw_guide() -> void:
	var node: Control = null
	if not guide.is_empty() and visible and not _choosing_target:
		var index := _guide_entry()
		if _in_skills and _skill_entries.has(index):
			var row := _skill_entries.find(index) - _scroll
			if row >= 0 and row < _row_panels.size():
				node = _row_panels[row]
		elif not _in_skills and _guide_option() >= 0:
			node = _plates[_guide_option()]
	if node == _guide_node:
		return
	if _guide_tween != null:
		_guide_tween.kill()
		_guide_tween = null
	if is_instance_valid(_guide_node):
		# Back to its own look now (a plate that got locked since stays faded).
		var plate := _plates.find(_guide_node)
		_guide_node.modulate = _plate_rest[plate] if plate >= 0 else Color.WHITE
	_guide_node = node
	if node == null:
		return
	_guide_tween = node.create_tween().set_loops()
	_guide_tween.tween_property(node, "modulate", GUIDE_GLOW, GUIDE_PULSE_S * 0.5).set_trans(Tween.TRANS_SINE)
	_guide_tween.tween_property(node, "modulate", Color.WHITE, GUIDE_PULSE_S * 0.5).set_trans(Tween.TRANS_SINE)


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


## "2 AP" for a skill that costs AP, "+1 AP" for one that gives it, else "".
func _cost_text(ability: AbilityData) -> String:
	if ability.ap_cost > 0:
		return "%d AP" % ability.ap_cost
	if ability.ap_gain > 0:
		return "+%d AP" % ability.ap_gain
	return ""


## The diamond's backdrop: a thin gold ring through the four buttons with slowly turning ticks,
## and a dark hub ringed in the hero's colour (the AP sits on it).
class Cluster extends Control:
	var accent: Color = HudStyle.GOLD

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := ActionMenu.DIAMOND_CENTRE
		var r := ActionMenu.ARM
		draw_circle(c + ActionMenu.BACK_PLATE, r + 6.0, Color(0.0, 0.0, 0.0, 0.35))
		draw_circle(c, r + 6.0, Color(0.02, 0.015, 0.03, 0.55))
		draw_arc(c, r, 0.0, TAU, 72, Color(HudStyle.EDGE, 0.85), 3.0, true)
		draw_arc(c, r + 10.0, 0.0, TAU, 72, Color(HudStyle.EDGE, 0.3), 1.5, true)
		var spin := float(Time.get_ticks_msec()) * 0.001 * ActionMenu.TICK_SPIN
		for i: int in ActionMenu.TICKS:
			var a := spin + TAU * float(i) / float(ActionMenu.TICKS)
			var dir := Vector2(cos(a), sin(a))
			draw_line(c + dir * (r + 6.0), c + dir * (r + 14.0), Color(HudStyle.EDGE, 0.6), 2.0, true)
		draw_circle(c + ActionMenu.BACK_PLATE * 0.6, ActionMenu.HUB_RADIUS, Color(accent, 0.9))
		draw_circle(c, ActionMenu.HUB_RADIUS, HudStyle.INK_SOLID)
		draw_arc(c, ActionMenu.HUB_RADIUS, 0.0, TAU, 48, HudStyle.EDGE, 2.0, true)


## A round dark socket with a thin ring in the hero's colour, holding a button picture in its
## middle (or, for a wide keyboard key, a slab as wide as the key).
class Socket extends Control:
	var diameter: float = 60.0
	var ring: Color = HudStyle.EDGE
	## Which way a wide key's slab grows: -1 left, 1 right (away from the hub, so it never covers
	## the AP), 0 both ways.
	var outward: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		size = Vector2(diameter, diameter)
		for child: Node in get_children():
			if child is HintBar:
				var chip := child as Control
				chip.reset_size()
				chip.position = (size - chip.size) * 0.5 + Vector2(_shift(), 0.0)

	## How far a wide slab's middle sits from the socket's middle.
	func _shift() -> float:
		return (visual_width() - diameter) * 0.5 * outward

	## How far the socket reaches to the left and the right of its middle.
	func reach(side: float) -> float:
		return visual_width() * 0.5 + _shift() * side

	## How wide the socket draws (a long keyboard key makes it a slab wider than the circle).
	func visual_width() -> float:
		return maxf(diameter, _chip_width() + 20.0)

	## The widest button picture inside (read from the chips themselves, so it is right before the
	## hint row has been laid out).
	func _chip_width() -> float:
		return _widest_chip(self)

	static func _widest_chip(node: Node) -> float:
		var widest := 0.0
		for child: Node in node.get_children():
			if child is ButtonChip:
				widest = maxf(widest, (child as Control).custom_minimum_size.x)
			else:
				widest = maxf(widest, _widest_chip(child))
		return widest

	func _draw() -> void:
		if diameter <= 0.0:
			return
		var centre := Vector2(diameter, diameter) * 0.5
		var r := diameter * 0.5
		var wide := visual_width() - diameter
		if wide > 0.0:
			var rect := Rect2(centre - Vector2(r + wide * 0.5 - _shift(), r), Vector2(diameter + wide, diameter))
			var box := StyleBoxFlat.new()
			box.bg_color = HudStyle.INK_SOLID
			box.border_color = ring
			box.set_border_width_all(3)
			box.set_corner_radius_all(int(r))
			box.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
			box.shadow_size = 1
			box.shadow_offset = ActionMenu.BACK_PLATE * 0.6
			draw_style_box(box, rect)
			return
		draw_circle(centre + ActionMenu.BACK_PLATE * 0.6, r, Color(0.0, 0.0, 0.0, 0.55))
		draw_circle(centre, r, HudStyle.INK_SOLID)
		draw_arc(centre, r - 1.5, 0.0, TAU, 48, ring, 3.0, true)


## A ring around the Run button that fills clockwise from the top while Back is held.
class HoldRing extends Control:
	## Drawn around this control's position; the control itself has no size.
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
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, ActionMenu.HOLD_RING_TRACK, ActionMenu.HOLD_RING_WIDTH, true)
		var start := -PI * 0.5
		draw_arc(Vector2.ZERO, radius, start, start + TAU * _progress, 48, HudStyle.JUMP, ActionMenu.HOLD_RING_WIDTH, true)
