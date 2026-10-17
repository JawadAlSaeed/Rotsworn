class_name BackpackGrid
extends Control
## Draws the party's backpack (DESIGN.md 8.1): the backpack art, the grid's cells on its lining,
## every item's icon over the cells its shape covers (turned with it) inside a border in its
## rarity colour, the cursor, and the item in hand at the cursor (tinted by whether it fits
## there). It only draws: the party screen moves the cursor and changes the backpack.
## The art and its grid numbers come from CombatVisuals ("Backpack").

const CELL_BG := Color(0.0, 0.0, 0.0, 0.28)
const CELL_EDGE := Color(0.55, 0.5, 0.62, 0.35)
const ITEM_BG_ALPHA: float = 0.22
const BORDER_PX: float = 3.0
const CURSOR_PX: float = 4.0
## The item in hand: drawn over everything, this see-through; its outline says if it fits.
const HELD_ALPHA: float = 0.85
const FITS := Color(0.55, 1.0, 0.6)
const NO_FIT := Color(1.0, 0.36, 0.3)
## Where the item in hand came from stays as a faint shape.
const ORIGIN_ALPHA: float = 0.25
## Rarity colours (borders here, names in the shop and the item info).
## The last step is not a rarity but the rot-touched tag of gear (DESIGN.md 8.16): its own colour.
const RARITY_COLORS: Array[Color] = [Color(0.75, 0.75, 0.77), Color(0.38, 0.62, 1.0), Color(1.0, 0.8, 0.3),
		GearData.ROT_TOUCHED_COLOR]
const RARITY_NAMES: Array[String] = ["common", "rare", "legendary", "rot-touched"]
const ROT_TOUCHED_STEP: int = 3
## Rotten items: a sickly green border, whatever their rarity.
const ROTTEN_COLOR := Color(0.55, 0.85, 0.3)
const LINK_COLOR := Color(1.0, 0.82, 0.3)
const LINK_PX: float = 7.0
const LEVEL_FONT_SIZE: int = 26
## With no art: a plain frame this many pixels around the grid.
const NO_ART_MARGIN: float = 24.0

var pack: Backpack
var cursor: Vector2i = Vector2i.ZERO
var show_cursor: bool = true
## The item in hand (null: none), its turn, and its uid if it came from the backpack (-1: new).
var held_item: ItemData
var held_turn: int = 0
var held_uid: int = -1
## Gold links between charms that boost each other: [cell, cell] pairs side by side.
var links: Array = []
## The item the one in hand would combine into (-1: none): drawn with a gold outline.
var combine_into: int = -1
var _visuals: CombatVisuals
var _art: Texture2D
var _cell: float = 92.0
var _gap: float = 4.0
var _origin: Vector2 = Vector2.ZERO
var _icons: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup(p_pack: Backpack, visuals: CombatVisuals) -> void:
	pack = p_pack
	_visuals = visuals
	var scale := float(visuals.backpack_art_scale)
	_cell = float(visuals.backpack_cell_art_px) * scale
	_gap = float(visuals.backpack_gap_art_px) * scale
	var path := visuals.backpack_art_path % pack.rows if visuals.backpack_art_path.contains("%d") \
			else visuals.backpack_art_path
	_art = load(path) as Texture2D if ResourceLoader.exists(path) else null
	if _art != null:
		_origin = Vector2(visuals.backpack_grid_origin) * scale
		custom_minimum_size = _art.get_size() * scale
	else:
		push_warning("BackpackGrid: no backpack art at %s, drawing a plain frame" % path)
		_origin = Vector2(NO_ART_MARGIN, NO_ART_MARGIN)
		custom_minimum_size = grid_px(Vector2i(pack.width, pack.rows)) + _origin * 2.0
	queue_redraw()


## The size in pixels of `cells` cells side by side (gaps between them).
func grid_px(cells: Vector2i) -> Vector2:
	return Vector2(cells) * _cell + Vector2(maxi(0, cells.x - 1), maxi(0, cells.y - 1)) * _gap


func cell_pos(cell: Vector2i) -> Vector2:
	return _origin + Vector2(cell) * (_cell + _gap)


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
	for y: int in pack.rows:
		for x: int in pack.width:
			var rect := Rect2(cell_pos(Vector2i(x, y)), Vector2(_cell, _cell))
			draw_rect(rect, CELL_BG)
			draw_rect(rect, CELL_EDGE, false, 1.0)
	for e: Dictionary in pack.entries:
		var lifted := held_item != null and int(e.uid) == held_uid
		var item := e.item as ItemData
		var border := ROTTEN_COLOR if item.rotten else rarity_color(RunState.entry_rarity(e))
		if int(e.uid) == combine_into:
			border = LINK_COLOR
		_draw_item(item, int(e.x), int(e.y), int(e.turn), ORIGIN_ALPHA if lifted else 1.0, border, RunState.level_of(e))
	for pair: Array in links:
		# A gold bead on the shared edge of two cells.
		var a := cell_pos(pair[0]) + Vector2(_cell, _cell) * 0.5
		var b := cell_pos(pair[1]) + Vector2(_cell, _cell) * 0.5
		draw_circle((a + b) * 0.5, LINK_PX, LINK_COLOR)
		draw_circle((a + b) * 0.5, LINK_PX * 0.5, Color(1.0, 0.97, 0.8))
	if held_item != null:
		var fits := pack.fits(held_item, cursor.x, cursor.y, held_turn, held_uid) or combine_into >= 0
		_draw_item(held_item, cursor.x, cursor.y, held_turn, HELD_ALPHA, FITS if fits else NO_FIT)
	elif show_cursor:
		var rect := Rect2(cell_pos(cursor), Vector2(_cell, _cell)).grow(CURSOR_PX * 0.5)
		draw_rect(rect, HudStyle.GOLD, false, CURSOR_PX)


## One item: a tinted backing on each of its cells, its icon turned with it, and a border around
## its shape (only the outer edges, so an L reads as one piece).
func _draw_item(item: ItemData, x: int, y: int, turn: int, alpha: float, border: Color, level: int = 0) -> void:
	var cells := Backpack.cells_at(item, x, y, turn)
	for c: Vector2i in cells:
		draw_rect(Rect2(cell_pos(c), Vector2(_cell, _cell)), Color(border, ITEM_BG_ALPHA * alpha))
	var size := item.size()
	var unturned := grid_px(size)
	var box := grid_px(Vector2i(size.y, size.x) if turn % 2 == 1 else size)
	var centre := cell_pos(Vector2i(x, y)) + box * 0.5
	draw_set_transform(centre, float(turn) * PI * 0.5, Vector2.ONE)
	draw_texture_rect(_icon(item), Rect2(-unturned * 0.5, unturned), false, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var edge := Color(border, alpha)
	var half := _gap * 0.5
	for c: Vector2i in cells:
		var p := cell_pos(c)
		var a := p - Vector2(half, half)
		var b := p + Vector2(_cell, _cell) + Vector2(half, half)
		if not cells.has(c + Vector2i.UP):
			draw_line(Vector2(a.x, a.y), Vector2(b.x, a.y), edge, BORDER_PX)
		if not cells.has(c + Vector2i.DOWN):
			draw_line(Vector2(a.x, b.y), Vector2(b.x, b.y), edge, BORDER_PX)
		if not cells.has(c + Vector2i.LEFT):
			draw_line(Vector2(a.x, a.y), Vector2(a.x, b.y), edge, BORDER_PX)
		if not cells.has(c + Vector2i.RIGHT):
			draw_line(Vector2(b.x, a.y), Vector2(b.x, b.y), edge, BORDER_PX)
	if level > 0:
		# "+" or "++" in the top-left cell's corner: a combined item.
		var corner := cell_pos(cells[0]) + Vector2(6.0, float(LEVEL_FONT_SIZE))
		for c: Vector2i in cells:
			if c.y < cells[0].y or (c.y == cells[0].y and c.x < cells[0].x):
				corner = cell_pos(c) + Vector2(6.0, float(LEVEL_FONT_SIZE))
		draw_string_outline(HudStyle.body_font(), corner, "+".repeat(level), HORIZONTAL_ALIGNMENT_LEFT, -1,
				LEVEL_FONT_SIZE, 6, Color(0, 0, 0, alpha))
		draw_string(HudStyle.body_font(), corner, "+".repeat(level), HORIZONTAL_ALIGNMENT_LEFT, -1, LEVEL_FONT_SIZE,
				Color(LINK_COLOR, alpha))


func _icon(item: ItemData) -> Texture2D:
	if not _icons.has(item.icon_path):
		_icons[item.icon_path] = AssetLoader.texture(item.icon_path, item.size() * 16)
	return _icons[item.icon_path]
