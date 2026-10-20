class_name BackpackGrid
extends Control
## Draws Alder's open pack (DESIGN.md 8.1, 8.19, card #282): the pack art, its pockets sewn on the
## lining in rows of `backpack_pocket_columns`, every item's icon in its pocket inside a border in
## its rarity colour, the pockets a Bigger Pack would still add stitched shut, and the cursor. A
## new item in hand is drawn by the Bag tab's strip; here its pocket gets a gold or a red edge. It
## only draws: the Bag tab moves the cursor and changes the pack.
## The art and its numbers come from CombatVisuals ("Backpack").

const POCKET_FILL := Color(0.34, 0.24, 0.16, 0.92)
const POCKET_FLAP := Color(0.23, 0.15, 0.1, 0.95)
const POCKET_STITCH := Color(0.86, 0.76, 0.52, 0.55)
## A pocket the pack does not have yet: dark, sewn shut.
const SHUT_FILL := Color(0.12, 0.1, 0.1, 0.75)
const SHUT_STITCH := Color(0.55, 0.48, 0.36, 0.5)
const ITEM_BG_ALPHA: float = 0.18
const BORDER_PX: float = 3.0
const CURSOR_PX: float = 4.0
## The flap across a pocket's top, as a share of its height.
const FLAP_SHARE: float = 0.16
const STITCH_STEP: float = 10.0
## The item icon's share of the pocket below its flap.
const ICON_SHARE: float = 0.78
## The pocket a new item in hand would go into: green when free, gold to combine, red to replace.
const FITS := Color(0.55, 1.0, 0.6)
const NO_FIT := Color(1.0, 0.36, 0.3)
## Rarity colours (borders here, names in the shop and the item info).
## The last step is not a rarity but the rot-touched tag of gear (DESIGN.md 8.16): its own colour.
const RARITY_COLORS: Array[Color] = [Color(0.75, 0.75, 0.77), Color(0.38, 0.62, 1.0), Color(1.0, 0.8, 0.3),
		GearData.ROT_TOUCHED_COLOR]
const RARITY_NAMES: Array[String] = ["common", "rare", "legendary", "rot-touched"]
const ROT_TOUCHED_STEP: int = 3
## Rotten items: a sickly green border, whatever their rarity.
const ROTTEN_COLOR := Color(0.55, 0.85, 0.3)
## The item a new one would combine into, and level marks: gold.
const LINK_COLOR := Color(1.0, 0.82, 0.3)
const LEVEL_FONT_SIZE: int = 26
## With no art: a plain frame this many pixels around the pockets.
const NO_ART_MARGIN: float = 24.0

var pack: Backpack
## The pocket under the cursor.
var cursor: int = 0
var show_cursor: bool = true
## A new item in hand (null: none): its pocket's edge says what Confirm would do.
var held_item: ItemData
## The item the one in hand would combine into (-1: none): drawn with a gold outline.
var combine_into: int = -1
var _visuals: CombatVisuals
var _art: Texture2D
var _origin: Vector2 = Vector2.ZERO
var _pocket: Vector2 = Vector2(184.0, 110.0)
var _gap: float = 12.0
var _columns: int = 2
## Pockets drawn: the most the pack can have (the ones it lacks are sewn shut).
var _slots: int = 8
var _icons: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## `max_pockets`: tuning.backpack_max_pockets (0: just the pack's own).
func setup(p_pack: Backpack, visuals: CombatVisuals, max_pockets: int = 0) -> void:
	pack = p_pack
	_visuals = visuals
	_slots = maxi(pack.width, max_pockets)
	_columns = maxi(1, visuals.backpack_pocket_columns)
	var rows := ceili(float(_slots) / float(_columns))
	var scale := float(visuals.backpack_art_scale)
	_gap = float(visuals.backpack_pocket_gap_art_px) * scale
	var lining := Vector2(visuals.backpack_lining_art_px) * scale
	_pocket = Vector2((lining.x - _gap * float(_columns - 1)) / float(_columns),
			(lining.y - _gap * float(rows - 1)) / float(maxi(1, rows)))
	var path := visuals.backpack_art_path % 5 if visuals.backpack_art_path.contains("%d") else visuals.backpack_art_path
	_art = load(path) as Texture2D if ResourceLoader.exists(path) else null
	if _art != null:
		_origin = Vector2(visuals.backpack_grid_origin) * scale
		custom_minimum_size = _art.get_size() * scale
	else:
		push_warning("BackpackGrid: no pack art at %s, drawing a plain frame" % path)
		_origin = Vector2(NO_ART_MARGIN, NO_ART_MARGIN)
		custom_minimum_size = lining + _origin * 2.0
	queue_redraw()


## Pocket `index`'s rectangle, rows of `backpack_pocket_columns` from the top left.
func pocket_rect(index: int) -> Rect2:
	var col := index % _columns
	var row := index / _columns
	return Rect2(_origin + Vector2(float(col) * (_pocket.x + _gap), float(row) * (_pocket.y + _gap)), _pocket)


## How many pockets sit in a row (up / down moves by this many).
func columns() -> int:
	return _columns


## The pack's pocket under a viewport point (the way mouse events report it), -1 for none (card
## #202). Pockets sewn shut do not count.
func cell_at(point: Vector2) -> int:
	if pack == null:
		return -1
	var local := MenuMouse.local_point(self, point)
	for i: int in pack.width:
		if pocket_rect(i).has_point(local):
			return i
	return -1


static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]


## The colour/name step of a piece of gear: its rarity, or the rot-touched tag.
static func gear_step(item: GearData) -> int:
	return ROT_TOUCHED_STEP if item.rot_touched else int(item.rarity)


static func rarity_name(rarity: int) -> String:
	return RARITY_NAMES[clampi(rarity, 0, RARITY_NAMES.size() - 1)]


func _draw() -> void:
	if pack == null:
		return
	if _art != null:
		draw_texture_rect(_art, Rect2(Vector2.ZERO, custom_minimum_size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), HudStyle.PANEL_BG)
	for i: int in _slots:
		_draw_pocket(pocket_rect(i), i < pack.width)
	for e: Dictionary in pack.entries:
		var item := e.item as ItemData
		var border := ROTTEN_COLOR if item.rotten else rarity_color(RunState.entry_rarity(e))
		if int(e.uid) == combine_into:
			border = LINK_COLOR
		_draw_item(item, pocket_rect(int(e.x)), border, RunState.level_of(e))
	if not show_cursor or cursor < 0 or cursor >= pack.width:
		return
	var edge := HudStyle.GOLD
	if held_item != null:
		edge = LINK_COLOR if combine_into >= 0 else (FITS if pack.uid_at(Vector2i(cursor, 0)) < 0 else NO_FIT)
	draw_rect(pocket_rect(cursor).grow(CURSOR_PX * 0.5), edge, false, CURSOR_PX)


## A pocket sewn on the lining: leather with a flap and a stitched edge; one the pack lacks yet is
## dark and sewn shut with a cross.
func _draw_pocket(rect: Rect2, open: bool) -> void:
	if not open:
		draw_rect(rect, SHUT_FILL)
		draw_line(rect.position, rect.end, SHUT_STITCH, 2.0)
		draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), SHUT_STITCH, 2.0)
		return
	draw_rect(rect, POCKET_FILL)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * FLAP_SHARE)), POCKET_FLAP)
	var inner := rect.grow(-5.0)
	var x := inner.position.x
	while x < inner.end.x:
		draw_line(Vector2(x, inner.end.y), Vector2(minf(x + STITCH_STEP * 0.5, inner.end.x), inner.end.y), POCKET_STITCH, 2.0)
		x += STITCH_STEP
	var y := inner.position.y + rect.size.y * FLAP_SHARE
	while y < inner.end.y:
		for side: float in [inner.position.x, inner.end.x]:
			draw_line(Vector2(side, y), Vector2(side, minf(y + STITCH_STEP * 0.5, inner.end.y)), POCKET_STITCH, 2.0)
		y += STITCH_STEP


## One item in its pocket: a tinted backing, its icon (kept to its own shape, fitted below the
## flap), a border in `border`, and "+" marks for a combined one.
func _draw_item(item: ItemData, rect: Rect2, border: Color, level: int = 0) -> void:
	draw_rect(rect, Color(border, ITEM_BG_ALPHA))
	var body := Rect2(rect.position + Vector2(0.0, rect.size.y * FLAP_SHARE), rect.size * Vector2(1.0, 1.0 - FLAP_SHARE))
	var tex := _icon(item)
	var art := Vector2(tex.get_size()) if tex != null else Vector2.ONE
	var fit := minf(body.size.x * ICON_SHARE / maxf(1.0, art.x), body.size.y * ICON_SHARE / maxf(1.0, art.y))
	var size := art * fit
	if tex != null:
		draw_texture_rect(tex, Rect2(body.get_center() - size * 0.5, size), false)
	draw_rect(rect, border, false, BORDER_PX)
	if level > 0:
		var corner := rect.position + Vector2(8.0, rect.size.y * FLAP_SHARE + float(LEVEL_FONT_SIZE))
		draw_string_outline(HudStyle.body_font(), corner, "+".repeat(level), HORIZONTAL_ALIGNMENT_LEFT, -1,
				LEVEL_FONT_SIZE, 6, Color.BLACK)
		draw_string(HudStyle.body_font(), corner, "+".repeat(level), HORIZONTAL_ALIGNMENT_LEFT, -1, LEVEL_FONT_SIZE,
				LINK_COLOR)


func _icon(item: ItemData) -> Texture2D:
	if not _icons.has(item.icon_path):
		_icons[item.icon_path] = AssetLoader.texture(item.icon_path, item.size() * 16)
	return _icons[item.icon_path]
