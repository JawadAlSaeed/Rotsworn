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
	"bleeding": "BLEEDING", "regen": "RENEW", "marked": "MARKED", "empowered": "EMPOWERED",
}
const STATUS_COLORS := {
	"exposed": Color(1.0, 0.55, 0.3), "guarded": Color(0.55, 0.8, 1.0), "taunted": Color(1.0, 0.4, 0.4),
	"slowed": Color(0.7, 0.6, 1.0), "riposte": Color(1.0, 0.85, 0.35),
	"bleeding": Color(0.9, 0.2, 0.25), "regen": Color(0.45, 1.0, 0.5), "marked": Color(1.0, 0.3, 0.7),
	"empowered": Color(1.0, 0.75, 0.3),
}

## The fight HUD's look (card #154): dark ink plates slanted like Persona 5's, edged in a calm
## worn gold like Expedition 33's. SLANT is the stylebox skew (how far the top edge leans right,
## as a share of the plate's height).
const SLANT: float = 0.28
const INK := Color(0.035, 0.03, 0.045, 0.86)
const INK_SOLID := Color(0.03, 0.025, 0.04, 0.95)
const EDGE := Color(0.72, 0.6, 0.38, 0.9)
const EDGE_DIM := Color(0.42, 0.37, 0.3, 0.75)
## The hard ink shadow under every plate (Persona 5's offset print shadow).
const PLATE_SHADOW := Color(0.0, 0.0, 0.0, 0.55)
const PLATE_SHADOW_OFFSET := Vector2(5.0, 5.0)

const OUTLINE_RATIO: float = 0.2
## The fonts (UiFonts). load_fonts() reads them once at start-up.
const FONTS_PATH := "res://data/presentation/ui_fonts.tres"
const TEXT_STATIC_SHADER := preload("res://scripts/menu/text_static.gdshader")
## Worn titles' dark edge, as a share of their size (thinner than OUTLINE_RATIO).
const WORN_OUTLINE_RATIO: float = 0.06

static var _title_font: Font
static var _body_font: Font
static var _select_font: Font
static var _number_font: Font
static var _punch_font: Font
static var _fonts: UiFonts
static var _worn_material: ShaderMaterial

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
	_fonts = data
	_body_font = _lining(_font_file(data.body_font_path))
	var bold := _font_file(data.number_font_path)
	if bold != null:
		_number_font = _lining(bold)
		var slanted := _lining(bold)
		slanted.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-data.popup_slant, 1.0), Vector2.ZERO)
		_punch_font = slanted
	var title := _font_file(data.title_font_path)
	if title != null:
		_title_font = _weighted(title, data.title_weight)
		_select_font = _weighted(title, data.select_weight)
	if _body_font != null:
		ThemeDB.get_default_theme().default_font = _body_font
		ThemeDB.fallback_font = _body_font


## The font with lining, tabular figures (every digit as tall and as wide as the others), so
## numbers that change in place never jitter or look uneven.
static func _lining(font: Font) -> FontVariation:
	if font == null:
		return null
	var server := TextServerManager.get_primary_interface()
	var lined := FontVariation.new()
	lined.base_font = font
	lined.opentype_features = {server.name_to_tag("lnum"): 1, server.name_to_tag("tnum"): 1}
	return lined


static func _weighted(font: Font, weight: int) -> FontVariation:
	var weighted := FontVariation.new()
	weighted.base_font = font
	weighted.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return weighted


## The font data (defaults until load_fonts() ran): the menu choices' look lives there too.
static func fonts() -> UiFonts:
	if _fonts == null:
		_fonts = UiFonts.new()
	return _fonts


## The chosen menu choice's font: the title font at the logo's weight.
static func select_font() -> Font:
	return _select_font if _select_font != null else title_font()


## The logo's worn gold (DESIGN.md 7.7).
static func worn_gold() -> Color:
	return fonts().select_color


## Titles and big words that ask for GOLD get the logo's worn gold; other colours keep theirs.
static func worn_color(color: Color) -> Color:
	return worn_gold() if color == GOLD else color


## Titles and big words like the logo's letters: the logo's weight, brushed, worn edges
## flickering like static (text_static.gdshader), a thin dark edge and a soft shadow so they read
## over a fight too. GOLD becomes the logo's worn gold.
static func worn_settings(size: int, color: Color = GOLD) -> LabelSettings:
	var s := LabelSettings.new()
	s.font = select_font()
	s.font_size = size
	s.font_color = worn_color(color)
	s.outline_size = maxi(2, roundi(float(size) * WORN_OUTLINE_RATIO))
	s.outline_color = OUTLINE_COLOR
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	s.shadow_offset = Vector2(0.0, maxf(2.0, float(size) * 0.05))
	return s


static func make_worn_title(text: String, size: int, color: Color = GOLD) -> Label:
	var label := make_label(text, size, color)
	label.label_settings = worn_settings(size, color)
	label.material = worn_material()
	return label


## The flickering worn-gold look, shared by every title and the chosen menu choices. Null (plain
## gold letters, no static and no brushed streaks) when ui_fonts select_static_percent is 0.
static func worn_material() -> ShaderMaterial:
	if fonts().select_static_percent <= 0:
		return null
	if _worn_material == null:
		var look := fonts()
		_worn_material = ShaderMaterial.new()
		_worn_material.shader = TEXT_STATIC_SHADER
		_worn_material.set_shader_parameter("fps", look.select_static_fps)
		_worn_material.set_shader_parameter("motion", look.select_static_motion)
		_worn_material.set_shader_parameter("wear", look.select_wear)
		_worn_material.set_shader_parameter("strength", float(look.select_static_percent) / 100.0)
	return _worn_material


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


## Numbers on bars and counters (HP, AP, the team gauge): bold lining figures, a thin dark edge
## and a soft drop shadow instead of the thick outline, so they read crisp.
static func number_settings(size: int, color: Color = TEXT) -> LabelSettings:
	var s := LabelSettings.new()
	s.font = _number_font if _number_font != null else body_font()
	s.font_size = size
	s.font_color = color
	s.outline_size = maxi(2, roundi(float(size) * 0.14))
	s.outline_color = OUTLINE_COLOR
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	s.shadow_offset = Vector2(0.0, maxf(1.0, float(size) * 0.08))
	return s


static func make_number(text: String, size: int, color: Color = TEXT) -> Label:
	var label := make_label(text, size, color)
	label.label_settings = number_settings(size, color)
	return label


## The fight's floating words and damage numbers: like number_settings but slanted (Persona 5) and
## with a heavier edge, since they fly over the scene.
static func punch_settings(size: int, color: Color = TEXT) -> LabelSettings:
	var s := number_settings(size, color)
	if _punch_font != null:
		s.font = _punch_font
	s.outline_size = maxi(3, roundi(float(size) * 0.17))
	s.shadow_offset = Vector2(maxf(2.0, float(size) * 0.06), maxf(2.0, float(size) * 0.08))
	return s


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


## A slanted fight plate (card #154): `bg` with a `border` edge, `pad` inside (more at the sides,
## where the slant eats room: `slant` times the expected `height`), and the hard offset shadow.
static func slant(bg: Color = INK, border: Color = EDGE, border_px: int = 2, pad: int = 10,
		height: float = 48.0, slant_share: float = SLANT, shadow: bool = true) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_px)
	box.skew = Vector2(slant_share, 0.0)
	box.anti_aliasing = true
	box.set_content_margin_all(pad)
	var side := float(pad) + slant_share * height * 0.5
	box.content_margin_left = side
	box.content_margin_right = side
	if shadow:
		box.shadow_color = PLATE_SHADOW
		box.shadow_size = 1
		box.shadow_offset = PLATE_SHADOW_OFFSET
	return box


## A face picture in a frame bordered in `accent` (party panels, the party screen).
static func portrait_frame(texture: Texture2D, accent: Color, px: float, pad: int = 2,
		bg: Color = Color(0.0, 0.0, 0.0, 0.45)) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.add_theme_stylebox_override("panel", panel(bg, accent, pad, pad))
	var face := TextureRect.new()
	face.texture = texture
	face.custom_minimum_size = Vector2(px, px)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(face)
	return frame


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
		if Status.shows_count(id) and turns > 0:
			text += " %d" % turns
		parts.append(text)
	return "  ".join(parts)
