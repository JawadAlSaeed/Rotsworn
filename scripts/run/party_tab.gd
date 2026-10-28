class_name PartyTab
extends Control
## One tab of the party screen, the Y screen (DESIGN.md 8.18): Relics, Bag, Hero or Skills. The
## party screen draws everything around the tabs: the tab bar (LB / RB, gold), the info strip
## along the bottom, toasts and the button hints. A tab draws only its own page in the rectangle
## the screen gives it (1920 x 750 at y 110 on the 1920 x 1080 canvas), takes the input the screen
## passes on (handle_input), and says what the strip, the footer and its tab badge show.
## Online, a tab's changes go to the host as RunState ops (op_requested), like every run screen.

## Something the strip, footer or tab badges show changed: the screen redraws them.
signal changed
## Online client: a change for the host to make (RunState.apply_op data).
signal op_requested(op: Dictionary)
## A short message (a toast under the tab bar): a few words and an optional icon (a GearData, an
## ItemData, a Texture2D or a UiGlyph kind as a StringName).
signal toast(text: String, icon: Variant)

## The page's size on the 1920 x 1080 canvas.
const PAGE_SIZE := Vector2(1920.0, 750.0)

var run: RunState
## Online client: changes are asked of the host instead of made here.
var remote: bool = false
## The hero the tab shows or the cursor is on (party slot).
var hero: int = 0


## Builds the page for `p_run`. Called once, before the tab is first shown.
func setup(p_run: RunState, p_remote: bool) -> void:
	run = p_run
	remote = p_remote
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = PAGE_SIZE
	size = PAGE_SIZE


## The run changed (online, another player's change arrived): redraw.
func refresh() -> void:
	pass


## The tab just came on screen (from another tab or at open).
func shown() -> void:
	pass


## One input event while this tab is on screen. True when the tab used it. The screen handles
## LB / RB (tabs) and Back itself unless busy() is true, so a tab only sees those while busy.
func handle_input(_event: InputEvent) -> bool:
	return false


## True while the tab is in the middle of something (holding an item, a menu open, choosing who):
## LB / RB and Back go to the tab, and the screen does not switch tabs or close.
func busy() -> bool:
	return false


## The footer's button hints for the tab now, at most four ([[action, label], ...]). The screen
## adds LB / RB "Tabs" itself when it is not busy.
func hints() -> Array:
	return []


## What the info strip shows for the thing under the cursor ({} for nothing): {icon: GearData,
## ItemData, Texture2D or a UiGlyph kind (StringName), plus: bool (a Relic+: its icon's gold badge),
## title: String, color: Color (the title's),
## chips: Array of [glyph kind (StringName or ""), text, Color] small boxes, line: String (one
## line at most), bar: [have, need] (optional: a small segment bar, like an Echo's progress)}.
func info() -> Dictionary:
	return {}


## The number on the tab's badge (points waiting there), 0 for none.
func badge() -> int:
	return 0


## Makes a change: here, or (online client) by asking the host.
func ask(op: Dictionary) -> bool:
	if remote:
		op_requested.emit(op)
		return true
	var ok := run.apply_op(op)
	changed.emit()
	return ok


## True if `event` presses `action` (no echo; a stick only past its first push).
static func pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)
