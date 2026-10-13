class_name HudStyle
extends RefCounted
## Shared HUD look: text colours for defence feedback, label and panel builders. Big text with
## dark outlines so it reads over any background.

const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.92)
const TEXT := Color(0.95, 0.94, 0.9)
const TEXT_DIM := Color(0.55, 0.55, 0.58)
const GOLD := Color(1.0, 0.82, 0.3)
const PANEL_BG := Color(0.05, 0.05, 0.08, 0.78)
const PANEL_BORDER := Color(0.25, 0.25, 0.3, 0.9)
const HP_FILL := Color(0.36, 0.8, 0.38)
const HP_LOW := Color(0.92, 0.32, 0.25)
const HP_BG := Color(0.12, 0.1, 0.1, 0.9)
const ENEMY_HP_FILL := Color(0.78, 0.25, 0.22)

## Defence feedback colours (DESIGN.md 3.6).
const PARRY := Color(1.0, 0.95, 0.55)
const DODGE := Color(0.62, 1.0, 0.7)
const JUMP := Color(0.55, 0.88, 1.0)
const EARLY := Color(0.38, 0.62, 1.0)
const LATE := Color(1.0, 0.36, 0.3)
const WRONG := Color(1.0, 0.6, 0.15)
const MISS := Color(0.86, 0.86, 0.86)
const DAMAGE_TAKEN := Color(1.0, 0.32, 0.27)
const DAMAGE_DEALT := Color(1.0, 1.0, 1.0)
const RING_NORMAL := Color(0.9, 0.95, 1.0)
const HEAL := Color(0.45, 1.0, 0.5)
const GAUGE_FILL := Color(0.95, 0.62, 0.2)
const AP_TEXT := Color(0.55, 0.88, 1.0)
## Co-op player tags P1, P2, P3 (DESIGN.md 9.1).
const PLAYER_COLORS: Array[Color] = [Color(0.4, 0.75, 1.0), Color(1.0, 0.5, 0.45), Color(0.55, 0.95, 0.5)]

## Status badges (DESIGN.md 2.10): short name and colour per Status id.
const STATUS_NAMES := {
	"exposed": "EXPOSED", "guarded": "GUARD", "taunted": "TAUNTED", "slowed": "SLOWED", "riposte": "RIPOSTE",
}
const STATUS_COLORS := {
	"exposed": Color(1.0, 0.55, 0.3), "guarded": Color(0.55, 0.8, 1.0), "taunted": Color(1.0, 0.4, 0.4),
	"slowed": Color(0.7, 0.6, 1.0), "riposte": Color(1.0, 0.85, 0.35),
}

const OUTLINE_RATIO: float = 0.2
## The fonts (UiFonts). load_fonts() reads them once at start-up.
const FONTS_PATH := "res://data/presentation/ui_fonts.tres"

static var _title_font: Font
static var _body_font: Font

## Xbox-style names for pad buttons in control hints.
const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Menu",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}

## Xbox names for the triggers (they are axes, not buttons, in Godot).
const PAD_AXIS_NAMES := {JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}

## Chip shape, as shares of the hint's font size or of the chip's height.
const CHIP_HEIGHT_SHARE: float = 1.25
const CHIP_TEXT_SHARE: float = 0.8
## Movement "buttons" for hints: token -> [keyboard, pad].
const NAV_TOKENS := {
	&"@updown": ["↑↓", "D-pad ↑↓"], &"@leftright": ["←→", "D-pad ←→"],
	&"@arrows": ["←↑→↓", "D-pad"], &"@move": ["WASD", "L-stick"],
}


## Loads the game's fonts (data/presentation/ui_fonts.tres) and makes the body font the default
## for every Label and control. Call once at start-up, before any UI is built.
static func load_fonts() -> void:
	var data := load(FONTS_PATH) as UiFonts
	if data == null:
		push_warning("HudStyle: could not load %s, using the built-in font" % FONTS_PATH)
		data = UiFonts.new()
	_body_font = _font_file(data.body_font_path)
	var title := _font_file(data.title_font_path)
	if title != null:
		var weighted := FontVariation.new()
		weighted.base_font = title
		weighted.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): data.title_weight}
		_title_font = weighted
	if _body_font != null:
		ThemeDB.get_default_theme().default_font = _body_font
		ThemeDB.fallback_font = _body_font


static func _font_file(path: String) -> Font:
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("HudStyle: font %s is missing, using the built-in font" % path)
		return null
	return load(path) as Font


## The text font (the built-in one until load_fonts() ran).
static func body_font() -> Font:
	return _body_font if _body_font != null else ThemeDB.fallback_font


## The title font: titles, hero and enemy names, banners.
static func title_font() -> Font:
	return _title_font if _title_font != null else body_font()


## Like label_settings() but in the title font.
static func title_settings(size: int, color: Color = TEXT) -> LabelSettings:
	var s := label_settings(size, color)
	s.font = title_font()
	return s


## Like make_label() but in the title font.
static func make_title(text: String, size: int, color: Color = TEXT) -> Label:
	var label := make_label(text, size, color)
	label.label_settings = title_settings(size, color)
	return label


## "P1", "P2", ... for co-op tags.
static func player_tag(player: int) -> String:
	return "P%d" % (player + 1)


static func player_color(player: int) -> Color:
	return PLAYER_COLORS[clampi(player, 0, PLAYER_COLORS.size() - 1)]


static func label_settings(size: int, color: Color = TEXT) -> LabelSettings:
	var s := LabelSettings.new()
	s.font_size = size
	s.font_color = color
	s.outline_size = maxi(2, roundi(float(size) * OUTLINE_RATIO))
	s.outline_color = OUTLINE_COLOR
	return s


static func make_label(text: String, size: int, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.label_settings = label_settings(size, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func panel(bg: Color = PANEL_BG, border: Color = PANEL_BORDER, border_px: int = 2, padding: int = 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_px)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(padding)
	return box


static func bar(fill: Color, height: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0.0, height)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = HP_BG
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


## Sets the fill colour of a bar made by bar().
static func set_bar_color(b: ProgressBar, fill: Color) -> void:
	var fg := b.get_theme_stylebox("fill") as StyleBoxFlat
	if fg != null:
		fg.bg_color = fill


## The first keyboard key and the first pad button of an input action: [key, pad] ("" when
## that kind is not bound), read from the Input Map so hints follow remaps made in Project
## Settings > Input Map. Also takes the NAV_TOKENS (moving in menus and zones).
static func binding_parts(action: StringName) -> Array[String]:
	if NAV_TOKENS.has(action):
		var pair: Array = NAV_TOKENS[action]
		return [String(pair[0]), String(pair[1])]
	var key := ""
	var pad := ""
	if InputMap.has_action(action):
		for ev: InputEvent in InputMap.action_get_events(action):
			if key.is_empty() and ev is InputEventKey:
				var k := ev as InputEventKey
				key = OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
			elif pad.is_empty() and ev is InputEventJoypadButton:
				var button := (ev as InputEventJoypadButton).button_index
				pad = String(PAD_BUTTON_NAMES.get(button, "Button %d" % button))
			elif pad.is_empty() and ev is InputEventJoypadMotion and PAD_AXIS_NAMES.has((ev as InputEventJoypadMotion).axis):
				pad = String(PAD_AXIS_NAMES[(ev as InputEventJoypadMotion).axis])
	return [key, pad]


## "Space", "RB" or "Space / RB": the action's button for the kind of hints shown now
## (ButtonPrompts: keyboard keys, pad buttons, or both in mixed local co-op).
static func binding_text(action: StringName) -> String:
	var parts_in := binding_parts(action)
	var parts := PackedStringArray()
	if ButtonPrompts.shows_keys() and not parts_in[0].is_empty():
		parts.append(parts_in[0])
	if ButtonPrompts.shows_pad() and not parts_in[1].is_empty():
		parts.append(parts_in[1])
	if parts.is_empty():
		# The kind shown has no binding: show whatever exists rather than nothing.
		for part: String in parts_in:
			if not part.is_empty():
				parts.append(part)
	return " / ".join(parts) if not parts.is_empty() else "(not bound)"


## A small button picture for hints (ButtonChip): round coloured A/B/X/Y, drawn Menu, View,
## D-pad and stick symbols, dark pills for other pad buttons, light key caps for the keyboard.
static func button_chip(button: String, pad: bool, font_size: int) -> ButtonChip:
	return ButtonChip.new(button, pad, font_size)


## "+12" / "-8" for a millisecond offset.
static func signed_ms(ms: int) -> String:
	return ("+%d" % ms) if ms >= 0 else str(ms)


## "GUARD  SLOWED 2" from a fighter's statuses (mirror format), in Status.ALL order.
static func status_text(statuses: Dictionary) -> String:
	var parts := PackedStringArray()
	for id: String in Status.ALL:
		if not statuses.has(id):
			continue
		var text := String(STATUS_NAMES.get(id, id.to_upper()))
		var turns := int((statuses[id] as Dictionary).get("turns", 0))
		if Status.counts_turns(id) and turns > 0:
			text += " %d" % turns
		parts.append(text)
	return "  ".join(parts)
