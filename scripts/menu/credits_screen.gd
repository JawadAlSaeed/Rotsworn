class_name CreditsScreen
extends CanvasLayer
## The credits (DESIGN.md 7.7, card #87), from the main menu: the logo, the story, then who made
## the game and whose music, sounds and fonts it uses, rolling up the screen to their own song.
## They start again from the bottom once they have rolled past. Down rolls faster, Up rolls back,
## Back closes. Text and speeds live in data/branding/credits.tres.

signal closed

## Gap between blocks (a heading and its lines), and the space an empty line leaves.
const BLOCK_GAP_PX: float = 24.0
const LINE_GAP_PX: int = 6
const STORY_WIDTH_PX: float = 1100.0
const TEXT_WIDTH_PX: float = 1500.0
## Where the logo starts when the screen opens, as a share of the screen's height from the top.
const START_SHARE: float = 0.12

var _credits: CreditsData
var _view: Control
var _roll: VBoxContainer
var _offset: float = 0.0


func setup(credits: CreditsData, branding: BrandingData) -> void:
	_credits = credits
	add_child(MenuBackdrop.new())
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.clip_contents = true
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.offset_bottom = -ListMenu.FOOTER_STRIP_PX
	add_child(_view)
	_roll = VBoxContainer.new()
	_roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll.add_theme_constant_override("separation", LINE_GAP_PX)
	_view.add_child(_roll)
	# The living logo, as on the title screen and the main menu.
	var logo := AnimatedLogo.new()
	logo.setup(branding)
	logo.custom_minimum_size = Vector2(0.0, float(credits.logo_height_px))
	_roll.add_child(logo)
	if not branding.story.is_empty():
		var story := _line(branding.story, credits.line_size, HudStyle.TEXT_DIM)
		story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		story.custom_minimum_size.x = STORY_WIDTH_PX
		story.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_roll.add_child(story)
	_roll.add_child(_gap(BLOCK_GAP_PX * 2.0))
	for raw: String in credits.text.split("\n"):
		_roll.add_child(_entry(raw.strip_edges()))
	ListMenu.screen_footer(self, [[&"@updown", "Faster / back"], [&"menu_cancel", "Back"]])


func _ready() -> void:
	# The first time the logo is already on screen; later rolls come in from the bottom.
	_offset = _view.size.y * START_SHARE
	_place()


func _process(delta: float) -> void:
	var speed := _credits.scroll_px_per_s
	if Input.is_action_pressed(&"menu_down"):
		speed *= _credits.fast_multiplier
	elif Input.is_action_pressed(&"menu_up"):
		speed *= -_credits.fast_multiplier
	_offset -= speed * delta
	var height := _roll.get_combined_minimum_size().y
	if _offset < -height:
		_offset = _view.size.y
	elif _offset > _view.size.y:
		_offset = _view.size.y
	_place()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"menu_cancel", false, true) or MenuMouse.is_back(event):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_cancel")
		closed.emit()


func _place() -> void:
	var width := _view.size.x
	_roll.size = Vector2(width, _roll.get_combined_minimum_size().y)
	_roll.position = Vector2(0.0, roundf(_offset))


## One line of credits.text: "# heading", "~ small print", empty (a gap) or a normal line.
func _entry(line: String) -> Control:
	if line.is_empty():
		return _gap(BLOCK_GAP_PX)
	if line.begins_with("#"):
		var heading := HudStyle.make_worn_title(line.trim_prefix("#").strip_edges(), _credits.heading_size)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return heading
	if line.begins_with("~"):
		var small := _line(line.trim_prefix("~").strip_edges(), _credits.small_size, HudStyle.TEXT_DIM)
		small.custom_minimum_size.x = TEXT_WIDTH_PX
		small.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		return small
	var label := _line(line, _credits.line_size, HudStyle.TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = TEXT_WIDTH_PX
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return label


static func _line(text: String, size: int, color: Color) -> Label:
	var label := HudStyle.make_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size = Vector2(0.0, height)
	return gap
