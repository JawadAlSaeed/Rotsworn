class_name PadLostOverlay
extends CanvasLayer
## Local co-op: a player's pad dropped. The game is held under this card until that player is back:
## the pad returns (Main sees it and closes the card), or a button on another pad or the keyboard's
## Confirm takes the seat over, or Pause gives the seat up (their heroes go to the others).
## Phase 22: a crossed-out pad, the player's tag ("P2") and two button hints ("[any button] Take
## over", "[Pause] Give heroes"), no sentences.

## A device that is not in the roster pressed Confirm / any pad button: it takes the seat.
signal claimed(device: int)
## Pause: the player is dropped from the game.
signal dropped

const TAG_SIZE: int = 64
const HINT_SIZE: int = 30
const PAD_PX: float = 180.0
const DIM := Color(0.0, 0.0, 0.0, 0.8)
## The words on the chip of the take-over hint (any pad button, or the keyboard's Confirm).
const ANY_BUTTON := "Any button"

var _roster: PlayerRoster
var _pad: CrossedPad
var _tag: Label


func setup(roster: PlayerRoster) -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_roster = roster
	var bg := ColorRect.new()
	bg.color = DIM
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 22)
	add_child(column)
	_pad = CrossedPad.new()
	_pad.custom_minimum_size = Vector2(PAD_PX, PAD_PX)
	_pad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_pad)
	_tag = ListMenu.centred_title("", TAG_SIZE)
	column.add_child(_tag)
	column.add_child(ListMenu.divider())
	var hints := HBoxContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	hints.add_theme_constant_override("separation", 56)
	column.add_child(hints)
	var take := HBoxContainer.new()
	take.mouse_filter = Control.MOUSE_FILTER_IGNORE
	take.add_theme_constant_override("separation", HintBar.CHIP_GAP)
	var chip := HudStyle.button_chip(ANY_BUTTON, true, HINT_SIZE)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	take.add_child(chip)
	var word := HudStyle.make_label("Take over", HINT_SIZE, HudStyle.TEXT)
	word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	take.add_child(word)
	hints.add_child(take)
	hints.add_child(HintBar.new([[&"pause", "Give heroes"]], HINT_SIZE, HudStyle.TEXT))


## Shows which player lost their pad: their tag in their colour.
func show_player(player: int) -> void:
	_tag.text = HudStyle.player_tag(player)
	_tag.label_settings.font_color = HudStyle.player_color(player)
	_pad.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse or not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed(&"pause", false, true):
		dropped.emit()
		return
	var device := PlayerRoster.device_of(event)
	if _roster.devices.has(device) or device == PlayerRoster.ANY:
		return
	if event is InputEventJoypadButton or event.is_action_pressed(&"menu_confirm", false, true):
		claimed.emit(device)


## The pad picture (UiGlyph's) with a red line struck across it.
class CrossedPad:
	extends Control

	const PAD_COLOR := Color(0.75, 0.74, 0.72)
	const CROSS_COLOR := HudStyle.LATE
	const CROSS_EDGE := Color(0.0, 0.0, 0.0, 0.85)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var side := minf(size.x, size.y)
		var c := size * 0.5
		UiGlyph.draw_glyph(self, &"pad", c, side, PAD_COLOR)
		var reach := Vector2(side, -side) * 0.42
		var width := maxf(4.0, side * 0.07)
		draw_line(c - reach, c + reach, CROSS_EDGE, width + 6.0, true)
		draw_line(c - reach, c + reach, CROSS_COLOR, width, true)
