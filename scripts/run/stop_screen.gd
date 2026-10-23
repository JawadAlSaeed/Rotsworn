class_name StopScreen
extends CanvasLayer
## What the run's newer stop screens share (events, treasure, the campfire; DESIGN.md 8.7 to
## 8.11): the gold and HP strip, and handing out what the party got. An item goes into the backpack
## where it fits first; a bigger backpack is used at once; an item with no room, or a new Relic
## nobody wears (DESIGN.md 8.17), opens the backpack over the screen with it in hand. Several gifts
## go one after the other. Online, only the host hands things out (clients watch).

## Every gift is settled (the backpack closed again).
signal gifts_settled

const TITLE_SIZE: int = 72
const TEXT_SIZE: int = 30
const DETAIL_SIZE: int = 26
## The backpack over the screen draws above it.
const OVERLAY_LAYER: int = 20

var run: RunState
## Online client: shows only (the host's choices come back as a new screen).
var remote: bool = false

var _bar: RunPartyBar
var _overlay: PartyScreen
var _gifts: Array[Resource] = []
var _note: Label


## The backpack open over the screen (null: none). The bot settles it.
func overlay() -> PartyScreen:
	return _overlay


func is_settling() -> bool:
	return _overlay != null or not _gifts.is_empty()


## The gold and HP strip, centred, added to `column`.
func _add_bar(column: Control) -> void:
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(centre)
	_bar = RunPartyBar.new()
	centre.add_child(_bar)
	_bar.setup(run, run.shows_gold())


func _refresh_bar() -> void:
	if _bar != null:
		_bar.refresh(run)


## Hands out `things` (ItemData and GearData) in order; `note` says what happened (shown in the
## backpack when it opens). gifts_settled follows once all are settled.
func give(things: Array, note_label: Label = null) -> void:
	_note = note_label
	for thing: Variant in things:
		if thing is ItemData or thing is GearData:
			_gifts.append(thing)
	_next_gift()


func _next_gift() -> void:
	_refresh_bar()
	if _overlay != null:
		return
	while not _gifts.is_empty():
		var thing: Resource = _gifts.pop_front()
		if thing is GearData:
			# A Relic joins the run (a copy raises its level, DESIGN.md 8.17); a new or unworn one
			# then asks who wears it.
			var found := run.add_relic(thing as GearData)
			_say(RunState.relic_find_text(found))
			if not run.is_worn(thing as GearData):
				_open_backpack(RunState.relic_find_short(found), {"gear": thing})
				return
			Sfx.play("buff")
			continue
		var item := thing as ItemData
		if item.kind == ItemData.Kind.UPGRADE or item.kind == ItemData.Kind.TREASURE:
			run.add_item(item)
			Sfx.play("level_up" if item.kind == ItemData.Kind.UPGRADE else "gold_gain")
			_say(run.find_text(item))
		elif run.add_item(item) >= 0:
			Sfx.play("item_place")
		else:
			_open_backpack("No room", {"item": item})
			return
	_refresh_bar()
	gifts_settled.emit()


## RunState.offer_chips or choice_chips as ListMenu.chip() entries (card #288): each kind's icon from
## `look`, its text coloured as a price, a gift or what a risk may do. Main's shrine question uses
## it too.
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
	add_child(_overlay)
	_overlay.setup(run, note, held)
	_overlay.done.connect(_close_backpack)


func _close_backpack() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_next_gift.call_deferred()
