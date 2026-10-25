class_name StartRelicsScreen
extends RelicsScreen
## The starting Relics, before a run (DESIGN.md 8.24, card #328): each hero takes
## RunState.start_relic_count() Relics of the player's choice from their Relic book, hero by hero.
## The book page's grid holds the book's found Relics (one taken for another hero is dim, with that
## hero's face); the right side shows every hero with what they took, the one choosing now lit.
## Confirm takes the Relic under the cursor for that hero, Back skips them. Local co-op: only that
## hero's player's pad picks for them (any device while that pad is unplugged, so a dead pad never
## holds the step; the pause menu's Players row can drop that player). Online each machine picks for its own heroes from its own book:
## a friend's pick goes to the host (`remote`), which checks it, and shows "..." until the host's state
## has it (a Relic someone took first comes back to choose again). When this machine's heroes are all
## done the screen waits ("Waiting") until the run goes on.

## Hero `slot` took `item` (null: skipped). Local play and the host: already in the run. A friend
## (`remote`): Main sends it to the host.
signal picked(slot: int, item: GearData)
## Every hero this screen picks for is done (taken or skipped; a friend's: sent). Told again if a
## refused pick opens a hero once more.
signal finished

const HERO_FACE_PX := Vector2i(72, 72)
const HERO_NAME_SIZE: int = 32
const HERO_ROW_SIZE := Vector2(660.0, 100.0)
const HERO_RELIC_PX: float = 52.0
const TAG_SIZE: int = 24
const TITLE := "Starting Relics"
const WAITING := "Waiting"
const TAKEN := "Taken"
const SKIPPED := "Skip"
## A friend's pick on its way to the host.
const SENT := "..."

var run: RunState
## The heroes this machine picks for, in slot order (the others are another player's).
var heroes: Array[int] = []
## Online friend: picks go to the host (`picked`) and wait for its state (refresh).
var remote: bool = false
## Who plays which hero: the player tags on the rows (co-op), and with `check_pads` (local co-op) only
## the hero's own player's pad may pick for them.
var players: PlayerRoster = null
var check_pads: bool = false
## The Godot ids of the pads plugged in now (tests set it; default: Input's).
var connected_pads: Callable = Callable()
## The bot (autoplay) picks for this screen's heroes, and again whenever one opens once more (a
## friend's pick the host refused, or another hero got that Relic first).
var autopick: bool = false
## A friend's picks sent to the host and not in its state yet: slot -> Relic id ("" skipped).
var _sent: Dictionary = {}
var _finished_told: bool = false
var _bot_queued: bool = false
## Relic ids the host refused on this screen: the bot never sends one again.
var _refused: Dictionary = {}
## The device of the last press (local co-op: whose pad it was).
var _device: int = PlayerRoster.ANY


## `book`: this machine's Relic book; `p_heroes`: the hero slots this machine picks for.
func setup_pick(p_run: RunState, book: RelicCollection, p_heroes: Array[int]) -> void:
	run = p_run
	heroes = p_heroes.duplicate()
	setup(book, p_run.data.gear)


## The hero choosing now: the first of `heroes` still open and not waiting on the host (-1: none).
func chooser() -> int:
	for slot: int in heroes:
		if run.start_open(slot) and not _sent.has(slot):
			return slot
	return -1


## True once every hero this screen picks for is done (taken, skipped or sent to the host).
func is_done() -> bool:
	return chooser() < 0


## True while a friend's pick waits for the host's state.
func is_sending() -> bool:
	return not _sent.is_empty()


## The chooser takes `item` from the book (the player's Confirm; the bot). False if refused: nobody
## is choosing, not in the book, or taken for another hero.
func take(item: GearData) -> bool:
	var slot := chooser()
	if slot < 0 or item == null or not _owns(item) or not run.can_gain(item):
		_refuse(TAKEN if item != null and run.owns(item) else "")
		return false
	if remote:
		_sent[slot] = item.id
	elif run.take_start_relic(slot, item).is_empty():
		_refuse(TAKEN)
		return false
	Sfx.play("buff")
	picked.emit(slot, item)
	_changed()
	return true


## The chooser takes no (more) starting Relics (Back). False if nobody is choosing.
func skip() -> bool:
	var slot := chooser()
	if slot < 0:
		return false
	if remote:
		_sent[slot] = ""
	elif not run.skip_start_relic(slot):
		return false
	Sfx.play("menu_cancel")
	picked.emit(slot, null)
	_changed()
	return true


## The bot's picks (DESIGN.md 8.24): for each hero still to choose, in slot order, the free Relic of
## the book with the best GearBot.score (the first of equal scores; one the bot refuses, or the host
## refused here, is never taken), else Skip.
func bot_pick() -> void:
	while chooser() >= 0:
		var best := _bot_choice()
		if best == null or not take(best):
			skip()


## The run changed (the host's state came, or a friend's pick went in on the host): a friend's sent
## picks the state has are done, one whose Relic another hero got first opens that hero again.
func refresh() -> void:
	for key: Variant in _sent.keys():
		var slot := int(key)
		var id := String(_sent[key])
		var item := run.relic_by_id(id) if not id.is_empty() else null
		if not run.start_open(slot) or (item != null and run.holder_of(item) == slot):
			_sent.erase(key)
		elif item == null and not id.is_empty():
			_sent.erase(key)
		elif item != null and run.owns(item):
			_sent.erase(key)
			_warning = TAKEN
	_resort()
	_changed()


## Online friend: the host refused Relic `id` for hero `slot` (taken first, or not ours to pick): that
## hero chooses again. A refusal of an older pick (the hero chose again already, after the host's
## state said the Relic was gone) changes nothing, and so does a refused Skip ("": the hero is done on
## the host already, or goes without when its wait runs out).
func refused(slot: int, id: String) -> void:
	if not id.is_empty() and _sent.has(slot) and String(_sent[slot]) == id:
		_sent.erase(slot)
		_refused[id] = true
		_warning = TAKEN
		Sfx.play("locked")
	_changed()


func _changed() -> void:
	_redraw()
	if is_done():
		if not _finished_told:
			_finished_told = true
			finished.emit()
	else:
		_finished_told = false
		if autopick and not _bot_queued:
			_bot_queued = true
			_bot_again.call_deferred()


func _bot_again() -> void:
	_bot_queued = false
	if is_inside_tree():
		bot_pick()


func _refuse(why: String) -> void:
	_warning = why
	Sfx.play("locked")
	_redraw()


func _bot_choice() -> GearData:
	var sent_ids := _sent.values()
	var choices: Array[GearData] = []
	for item: GearData in run.start_choices(_collection):
		if GearBot.score(item) >= 0 and not sent_ids.has(item.id) and not _refused.has(item.id):
			choices.append(item)
	return choices[GearBot.pick(choices)] if not choices.is_empty() else null


## Local co-op: true if the last press may pick for the chooser (may_pick).
func _pad_ok() -> bool:
	if not check_pads:
		return true
	var pads: Array[int] = []
	if connected_pads.is_valid():
		pads.assign(connected_pads.call())
	else:
		pads.assign(Input.get_connected_joypads())
	return may_pick(players, _device, chooser(), pads)


## Local co-op: true if a press from `device` may pick for hero `slot`: their own player's pad, or any
## device while that player's pad is not among `connected` (the pads plugged in), so a pad that went
## flat or was unplugged never holds the step for good. Pure.
static func may_pick(roster: PlayerRoster, device: int, slot: int, connected: Array[int]) -> bool:
	if roster == null or slot < 0 or device == PlayerRoster.ANY or roster.may_control(device, slot):
		return true
	return roster.missing_players(connected).has(roster.owner_of(slot))


# --- RelicsScreen ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed():
		_device = PlayerRoster.device_of(event)
	super(event)


func _title_text() -> String:
	return TITLE


func _lists_unknown() -> bool:
	return false


func _card_dim(item: GearData) -> bool:
	return run != null and run.owns(item)


func _card_holder(item: GearData) -> int:
	return run.holder_of(item) if run != null else -1


func _confirm(item: GearData) -> bool:
	if not _pad_ok():
		_refuse(_tag_of(chooser()))
		return false
	return take(item)


func _back() -> void:
	if not _pad_ok():
		_refuse(_tag_of(chooser()))
		return
	skip()


func _closes_on_party_menu() -> bool:
	return false


## The chooser's name (and player tag in co-op) in the header; "Waiting" once this machine is done.
func found_text() -> String:
	var slot := chooser()
	if slot < 0:
		return WAITING
	var tag := _tag_of(slot)
	return "%s %s" % [tag, run.data.party[slot].display_name] if not tag.is_empty() else run.data.party[slot].display_name


func hints() -> Array:
	if is_done():
		return []
	return [[&"@arrows", "Move"], [&"menu_confirm", "Take"], [&"menu_cancel", SKIPPED], [&"item_move", "Sort"]]


## Every hero as a row: face, name (and player tag), and the Relics they took, or what they wait on.
func _redraw_side() -> void:
	if run == null:
		return
	for slot: int in run.party_size():
		_side.add_child(_hero_row(slot))


func _hero_row(slot: int) -> Control:
	var choosing := slot == chooser()
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = HERO_ROW_SIZE
	panel.add_theme_stylebox_override("panel", HudStyle.slant(CHOSEN_BG if choosing else HudStyle.INK,
			HudStyle.GOLD if choosing else HudStyle.EDGE_DIM, 3 if choosing else 2, 10, HERO_ROW_SIZE.y, HudStyle.SLANT * 0.4))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 16)
	panel.add_child(line)
	var face := _face(slot, HERO_FACE_PX)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(face)
	var names := VBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.custom_minimum_size.x = 200.0
	line.add_child(names)
	names.add_child(HudStyle.make_title(run.data.party[slot].display_name, HERO_NAME_SIZE,
			HudStyle.GOLD if choosing else HudStyle.TEXT))
	var tag := _tag_of(slot)
	if not tag.is_empty():
		names.add_child(HudStyle.make_label(tag, TAG_SIZE, HudStyle.player_color(players.owner_of(slot))))
	var relics := run.relics_of(slot)
	for item: GearData in relics:
		var icon := RelicIcon.make(item, HERO_RELIC_PX)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(icon)
	if relics.size() == 1:
		var name := HudStyle.make_title(relics[0].display_name, TEXT_SIZE, name_color(relics[0]))
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(name)
	var state := _row_state(slot)
	if not state.is_empty():
		var word := HudStyle.make_label(state, TEXT_SIZE, HudStyle.GOLD if choosing else HudStyle.TEXT_DIM)
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(word)
	return panel


## What hero `slot`'s row says after their Relics: "Pick" while choosing, "..." while a friend's pick
## is on its way, "Waiting" for another player's hero still open, "Skip" for one who took none.
func _row_state(slot: int) -> String:
	if slot == chooser():
		return "Pick"
	if _sent.has(slot):
		return SENT
	if run.start_open(slot):
		return WAITING
	return SKIPPED if run.relics_of(slot).is_empty() else ""


func _redraw_detail() -> void:
	if not _warning.is_empty() or (focused() != null and not is_done()):
		super()
		return
	if focused() == null:
		_detail.text = "No Relics yet"
		_detail_more.text = ""
		return
	_detail.text = WAITING
	_detail_more.text = ""


func _face(slot: int, px: Vector2i) -> Control:
	var hero := run.data.party[slot] if run != null and slot >= 0 and slot < run.party_size() else null
	if hero == null:
		return Control.new()
	return ListMenu.icon_rect(AssetLoader.texture(hero.portrait_path, px), float(px.x))


## Hero `slot`'s player tag in co-op ("P2"), else "".
func _tag_of(slot: int) -> String:
	if players == null or players.player_count() <= 1 or slot < 0:
		return ""
	return HudStyle.player_tag(players.owner_of(slot))
