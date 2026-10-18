class_name MenuMouse
extends RefCounted
## Mouse help for the menus (DESIGN.md 6.2, card #202): which row a mouse point is over, what a
## button press means (left: confirm, right or the back button: go back, wheel: scroll), and
## whether an input event means the mouse or a key / pad is being used (the pointer hides itself
## for the latter). Everything here is pure, or only reads a Control's rectangle, so the maths is
## unit-tested; the menus (ListMenu and the screens with their own cards) call it.
## The mouse never triggers a fight action: no Input Map action has a mouse button (a test checks it),
## so DefenseInput, which only answers the defence actions, cannot hear it.

## What an input event says about who is playing (see activity()).
enum Activity { NONE, MOUSE, OTHER }

## A stick has to move this far to count as using a pad (drift never hides the pointer).
const STICK_THRESHOLD: float = 0.5


## The index of the first rectangle that has `point` in it, -1 for none. Empty rectangles (rows that
## are not shown) never match.
static func row_at(rects: Array[Rect2], point: Vector2) -> int:
	for i: int in rects.size():
		if rects[i].size.x > 0.0 and rects[i].size.y > 0.0 and rects[i].has_point(point):
			return i
	return -1


## `point` (a position the way mouse events report it: in the viewport) in `control`'s own
## coordinates. Works under a CanvasLayer and with the stretch scaling.
static func local_point(control: Control, point: Vector2) -> Vector2:
	return control.get_global_transform_with_canvas().affine_inverse() * point


## The index of the first Control in `controls` that is shown and has the viewport `point` over it
## (-1: none). Entries that are not Controls are skipped.
static func control_at(controls: Array, point: Vector2) -> int:
	for i: int in controls.size():
		var control := controls[i] as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if Rect2(Vector2.ZERO, control.size).has_point(local_point(control, point)):
			return i
	return -1


## How far across `control` the viewport `point` is, 0 (left edge) to 1 (right edge); -1 when the
## point is not over it.
static func share_across(control: Control, point: Vector2) -> float:
	if control == null or not control.is_visible_in_tree() or control.size.x <= 0.0:
		return -1.0
	var local := local_point(control, point)
	if not Rect2(Vector2.ZERO, control.size).has_point(local):
		return -1.0
	return clampf(local.x / control.size.x, 0.0, 1.0)


## The index of the point nearest to `at` within `radius` (-1: none): for stops drawn on a map.
static func nearest_within(points: Array[Vector2], at: Vector2, radius: float) -> int:
	var best := -1
	var best_distance := radius
	for i: int in points.size():
		var distance := points[i].distance_to(at)
		if distance <= best_distance:
			best_distance = distance
			best = i
	return best


## What a left click that landed `share` of the way across a row means for a row that is changed
## with Left and Right: the left half steps down (-1), the right half up (+1).
static func side_of(share: float) -> int:
	return -1 if share < 0.5 else 1


## The menu answer a pressed mouse button stands for: &"confirm" (left), &"cancel" (right, or the
## back button on the side of the mouse), &"" for the rest (the wheel, the middle button).
static func answer_for_button(button: int) -> StringName:
	match button:
		MOUSE_BUTTON_LEFT:
			return &"confirm"
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_XBUTTON1:
			return &"cancel"
	return &""


## How far the wheel moves a list: -1 up, +1 down, 0 for other buttons.
static func wheel_step(button: int) -> int:
	match button:
		MOUSE_BUTTON_WHEEL_UP:
			return -1
		MOUSE_BUTTON_WHEEL_DOWN:
			return 1
	return 0


## True for a mouse button press the menus read (the event, not the answer): left, right, back, wheel.
static func is_press(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	return button != null and button.pressed


## True when the event is a right click or the mouse's back button going down: "go back".
static func is_back(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	return button != null and button.pressed and answer_for_button(button.button_index) == &"cancel"


## True when the event is a left click going down.
static func is_click(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	return button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT


## Who an event says is playing: the mouse (it moved, or a button went down), another device (a
## key, a pad button, a stick pushed past STICK_THRESHOLD), or NONE (anything else: a release, an echo).
static func activity(event: InputEvent) -> Activity:
	if event is InputEventMouseMotion:
		return Activity.MOUSE if (event as InputEventMouseMotion).relative != Vector2.ZERO else Activity.NONE
	if event is InputEventMouseButton:
		return Activity.MOUSE
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		return Activity.OTHER
	if event is InputEventJoypadButton and event.is_pressed():
		return Activity.OTHER
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) >= STICK_THRESHOLD:
		return Activity.OTHER
	return Activity.NONE


## Whether the pointer shows: only while the mouse was the last thing used, and only on screens
## that are menus (fights and zones are keyboard / pad games).
static func pointer_visible(mouse_active: bool, menus_allowed: bool) -> bool:
	return mouse_active and menus_allowed
