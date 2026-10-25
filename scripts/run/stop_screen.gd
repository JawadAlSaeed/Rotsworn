class_name StopScreen
extends CanvasLayer
## What the run's newer stop screens share (events, treasure, the campfire; DESIGN.md 8.7 to
## 8.11): the gold and HP strip, and handing out what the party got. An item goes into the backpack
## where it fits first; a bigger backpack is used at once; an item with no room opens the backpack
## over the screen with it in hand. Several gifts go one after the other. Online, only the host hands
## things out (clients watch). A Relic is never handed out here: the screen that offers it asks who
## gets it first (RelicGift, DESIGN.md 8.24; `give_heroes`).
## Online the choices go in turns (card #314, DESIGN.md 9.2): on another player's turn the screen is
## `watching` (greyed, no input); on a friend's own turn their copy `asks` the host for each choice,
## and the host's copy hands an item with no room to that friend (hand_off): their backpack opens
## over their screen with it in hand, and settle_owed() puts it where they chose.

## Every gift is settled (the backpack closed again).
signal gifts_settled
## Online friend: a change made in the backpack open over this screen (Main sends it to the host).
signal op_requested(op: Dictionary)

const TITLE_SIZE: int = 72
const TEXT_SIZE: int = 30
const DETAIL_SIZE: int = 26
## The backpack over the screen draws above it.
const OVERLAY_LAYER: int = 20

var run: RunState
## Online client: shows only (the host's choices come back as a new screen).
var remote: bool = false
## Online (card #314): another player's turn: the choices are greyed and take no input.
var watching: bool = false
## Online friend whose turn it is (card #314): each choice goes to the host as a request,
## asks.call({"do": ...}); the host's next screen shows what came of it.
var asks: Callable = Callable()
## Host, a friend's turn (card #314): hand_off.call(self) sends them the item owed() (no room).
var hand_off: Callable = Callable()
## Who may get a Relic offered here (RelicGift.allowed; Main sets it): heroes.call(device) -> slots.
var give_heroes: Callable = Callable()

var _bar: RunPartyBar
var _overlay: PartyScreen
var _gifts: Array[Resource] = []
var _note: Label
## Host: the item handed to a friend to place (card #314): {"note", "item"}; {} when none.
var _owed: Dictionary = {}


## The backpack open over the screen (null: none). The bot settles it.
func overlay() -> PartyScreen:
	return _overlay


func is_settling() -> bool:
	return _overlay != null or not _gifts.is_empty() or not _owed.is_empty()


## Online (card #314): whose turn it is changed. `p_watching` greys the choices; `p_asks` sends
## them to the host (a friend's own turn). The screen redraws.
func set_turn(p_watching: bool, p_asks: Callable = Callable()) -> void:
	watching = p_watching
	asks = p_asks
	_turn_changed()


## True when the choices cannot be made here: another player's turn, or a client that only shows.
func is_greyed() -> bool:
	return watching or (remote and not asks.is_valid())


## Redraws the choices after set_turn (each screen its own way).
func _turn_changed() -> void:
	_refresh_bar()


## Online friend whose turn it is: sends `choice` to the host and returns true; false when this
## machine makes its choices itself.
func _ask(choice: Dictionary) -> bool:
	if not asks.is_valid():
		return false
	asks.call(choice)
	return true


## Host: the item a friend was handed to place ({"note", "item"}; {} when none).
func owed() -> Dictionary:
	return _owed


## Host: the friend put the owed item where their HAND_OUT op says (BagTab.place_new). False if
## that does not fit the backpack now (it is still owed: Main hands it out again).
func settle_owed(op: Dictionary) -> bool:
	if _owed.is_empty():
		return false
	var item := _owed.item as ItemData
	var placed := BagTab.place_new(run, item, op)
	if placed.is_empty():
		return false
	_owed = {}
	Sfx.play("item_drop" if placed == BagTab.LEFT else "item_place")
	_on_owed_settled(item, placed == BagTab.LEFT)
	_next_gift()
	return true


## Host: the turn came back to this machine while an item was owed: its backpack opens with it.
func take_back_owed() -> void:
	if _owed.is_empty() or _overlay != null:
		return
	var owed_now := _owed
	_owed = {}
	_open_backpack(String(owed_now.get("note", "")), {"item": owed_now.item})


## Online friend (card #314): the host handed us an item to place: the backpack opens over the
## screen with it in hand (its changes go to the host). `held`: {"item", "refund"}.
func hold_gift(note: String, held: Dictionary) -> void:
	if _overlay != null:
		return
	_open_backpack(note, held)


## An owed item was placed (or left behind: `left`). The shop gives a purchase's gold back.
func _on_owed_settled(_item: ItemData, _left: bool) -> void:
	pass


## The gold and HP strip, centred, added to `column`.
func _add_bar(column: Control) -> void:
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(centre)
	_bar = RunPartyBar.new()
	centre.add_child(_bar)
	_bar.setup(run)


func _refresh_bar() -> void:
	if _bar != null:
		_bar.refresh(run)


## Hands out `things` (ItemData) in order; `note` says what happened (shown in the backpack when it
## opens). gifts_settled follows once all are settled.
func give(things: Array, note_label: Label = null) -> void:
	_note = note_label
	for thing: Variant in things:
		if thing is ItemData:
			_gifts.append(thing)
	_next_gift()


func _next_gift() -> void:
	_refresh_bar()
	if _overlay != null:
		return
	while not _gifts.is_empty():
		var item := _gifts.pop_front() as ItemData
		if item.kind == ItemData.Kind.UPGRADE or item.kind == ItemData.Kind.TREASURE:
			run.add_item(item)
			Sfx.play("level_up" if item.kind == ItemData.Kind.UPGRADE else "gold_gain")
			_say(run.find_text(item))
		elif run.add_item(item) >= 0:
			Sfx.play("item_place")
		elif hand_off.is_valid():
			_owed = {"note": "No room", "item": item}
			hand_off.call(self)
			return
		else:
			_open_backpack("No room", {"item": item})
			return
	_refresh_bar()
	gifts_settled.emit()


## RunState.offer_chips or choice_chips as ListMenu.chip() entries (card #288): each kind's icon from
## `look`, its text coloured as a price, a gift or what a risk may do.
static func chip_entries(chips: Array[Dictionary], look: StopVisuals) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for chip: Dictionary in chips:
		var path := look.chip_icon_path(String(chip.get("kind", "")))
		var color := look.chip_gift_color
		if bool(chip.get("risk", false)):
			color = look.chip_risk_color
		elif bool(chip.get("cost", false)):
			color = look.chip_cost_color
		entries.append({"icon": AssetLoader.texture(path, Vector2i(12, 12)) if not path.is_empty() else null,
				"text": String(chip.get("text", "")), "color": color, "kind": String(chip.get("kind", "")),
				"newline": bool(chip.get("newline", false))})
	return entries


## One chip of kind `kind` (StopVisuals.chip_icon_path) with `text` in `color`.
static func chip_entry(look: StopVisuals, kind: String, text: String, color: Color) -> Dictionary:
	return {"icon": AssetLoader.texture(look.chip_icon_path(kind), Vector2i(12, 12)), "text": text, "color": color,
			"kind": kind}


func _say(text: String) -> void:
	if _note != null:
		_note.text = (_note.text + "\n" + text).strip_edges()


func _open_backpack(note: String, held: Dictionary) -> void:
	_overlay = PartyScreen.new()
	_overlay.layer = OVERLAY_LAYER
	_overlay.close_when_settled = true
	# A friend's copy (card #314): what they do there is asked of the host.
	_overlay.remote = remote
	add_child(_overlay)
	_overlay.setup(run, note, held)
	_overlay.op_requested.connect(op_requested.emit)
	_overlay.done.connect(_close_backpack)


func _close_backpack() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_next_gift.call_deferred()
