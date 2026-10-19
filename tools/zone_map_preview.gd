extends SceneTree
## Dev tool: draws every long zone from above (one visit each, seed from --seed=N, default 1) to
## PNGs, so a layout can be checked without opening the game (DESIGN.md 8.12). Ground pieces in
## their texture's average colour (water blue), blocks grey, solid props as brown circles,
## walk-through props as small green dots, enemies red (champions purple, the guard crimson),
## seals bright green, shrines and wanderers yellow, glinting spots cyan, chests orange, the gate
## violet, the start white, critters small pink dots.
## Run: Godot --headless --path . -s tools/zone_map_preview.gd -- --out=DIR [--seed=N]

const PX: float = 8.0
const MARGIN: float = 3.0


func _init() -> void:
	var out := "user://zone_maps"
	var seed_value := 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--seed="):
			seed_value = arg.substr(7).to_int()
	DirAccess.make_dir_recursive_absolute(out)
	for zone: ZoneData in FightSelect.load_zones():
		var built := ZoneAssembler.assemble(zone, seed_value)
		var path := out.path_join("%s_%d.png" % [zone.id, seed_value])
		_draw(built).save_png(path)
		print("zone map: ", path)
	quit()


func _draw(zone: ZoneData) -> Image:
	var lo := zone.bounds_min - Vector2(MARGIN, MARGIN)
	var hi := zone.bounds_max + Vector2(MARGIN, MARGIN)
	var w := int((hi.x - lo.x) * PX)
	var h := int((hi.y - lo.y) * PX)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.1, 0.12))
	_rect(img, lo, zone.bounds_min, zone.bounds_max, Color(0.2, 0.2, 0.22))
	# Bottom step first, as the game stacks them (GroundStack, card #269).
	var levels := GroundStack.levels(zone.grounds)
	var order: Array[int] = []
	for i: int in zone.grounds.size():
		if zone.grounds[i] != null:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return levels[a] < levels[b] or (levels[a] == levels[b] and a < b))
	for i: int in order:
		var g := zone.grounds[i]
		var col := Color(0.15, 0.3, 0.45) if g.kind == ZoneGroundData.Kind.WATER else _avg(g.texture_path)
		_shape(img, lo, g, col)
	for b: ZoneBlockData in zone.blocks:
		_box(img, lo, Vector2(b.position.x, b.position.z), Vector2(b.size.x, b.size.z) * 0.5,
				deg_to_rad(b.rotation_y_degrees), Color(0.55, 0.55, 0.58))
	if zone.gate != null:
		var g := zone.gate
		_box(img, lo, Vector2(g.position.x, g.position.z), Vector2(g.size.x, g.size.z) * 0.5, 0.0, Color(0.6, 0.3, 0.8))
	for p: ZonePropData in zone.props:
		var at := Vector2(p.position.x, p.position.z)
		if p.solid_radius > 0.0:
			_disc(img, lo, at, p.solid_radius, Color(0.5, 0.35, 0.2))
		else:
			_disc(img, lo, at, 0.15, Color(0.35, 0.6, 0.3))
	for c: ZoneCritterData in zone.critters:
		_disc(img, lo, Vector2(c.position.x, c.position.z), 0.25, Color(1.0, 0.6, 0.8))
	for e: ZoneEnemyData in zone.enemies:
		var col := Color(0.6, 0.0, 0.1) if e.guard else (Color(0.7, 0.3, 1.0) if e.champion else Color(1.0, 0.25, 0.2))
		_disc(img, lo, Vector2(e.position.x, e.position.z), 0.6, col)
		if e.champion:
			_disc(img, lo, Vector2(e.prize_spot.x, e.prize_spot.z), 0.45, Color(1.0, 0.6, 0.1))
	for s: Vector3 in zone.seal_spots:
		_disc(img, lo, Vector2(s.x, s.z), 0.55, Color(0.3, 1.0, 0.3))
	for s: Vector3 in zone.offer_spots:
		_disc(img, lo, Vector2(s.x, s.z), 0.55, Color(1.0, 0.95, 0.2))
	for s: Vector3 in zone.item_spots:
		_disc(img, lo, Vector2(s.x, s.z), 0.4, Color(0.3, 1.0, 1.0))
	for s: Vector3 in zone.chests:
		_disc(img, lo, Vector2(s.x, s.z), 0.5, Color(1.0, 0.55, 0.1))
	_disc(img, lo, Vector2(zone.player_start.x, zone.player_start.z), 0.5, Color.WHITE)
	return img


func _avg(path: String) -> Color:
	var tex := load(path) as Texture2D
	if tex == null:
		return Color.MAGENTA
	var image := tex.get_image()
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), 2):
			var c := image.get_pixel(x, y)
			if c.a > 0.5:
				sum += c
				n += 1
	return Color(sum.r / n, sum.g / n, sum.b / n) if n > 0 else Color.MAGENTA


func _px(lo: Vector2, at: Vector2) -> Vector2i:
	return Vector2i(int((at.x - lo.x) * PX), int((at.y - lo.y) * PX))


func _rect(img: Image, lo: Vector2, a: Vector2, b: Vector2, col: Color) -> void:
	var p0 := _px(lo, a)
	var p1 := _px(lo, b)
	img.fill_rect(Rect2i(p0, p1 - p0), col)


func _disc(img: Image, lo: Vector2, at: Vector2, r: float, col: Color) -> void:
	var c := _px(lo, at)
	var rp := maxi(1, int(r * PX))
	for y: int in range(-rp, rp + 1):
		for x: int in range(-rp, rp + 1):
			if x * x + y * y <= rp * rp:
				_plot(img, c + Vector2i(x, y), col)


func _box(img: Image, lo: Vector2, centre: Vector2, half: Vector2, angle: float, col: Color) -> void:
	var reach := half.length()
	var p0 := _px(lo, centre - Vector2(reach, reach))
	var p1 := _px(lo, centre + Vector2(reach, reach))
	for y: int in range(p0.y, p1.y + 1):
		for x: int in range(p0.x, p1.x + 1):
			var world := lo + Vector2(x, y) / PX
			var local := (world - centre).rotated(angle)
			if absf(local.x) <= half.x and absf(local.y) <= half.y:
				_plot(img, Vector2i(x, y), col)


func _shape(img: Image, lo: Vector2, g: ZoneGroundData, col: Color) -> void:
	var centre := Vector2(g.position.x, g.position.z)
	var half := g.size * 0.5
	var angle := deg_to_rad(g.rotation_y_degrees)
	if not g.round:
		_box(img, lo, centre, half, angle, col)
		return
	var reach := maxf(half.x, half.y)
	var p0 := _px(lo, centre - Vector2(reach, reach))
	var p1 := _px(lo, centre + Vector2(reach, reach))
	for y: int in range(p0.y, p1.y + 1):
		for x: int in range(p0.x, p1.x + 1):
			var local := (lo + Vector2(x, y) / PX - centre).rotated(angle)
			if (local.x / half.x) * (local.x / half.x) + (local.y / half.y) * (local.y / half.y) <= 1.0:
				_plot(img, Vector2i(x, y), col)


func _plot(img: Image, p: Vector2i, col: Color) -> void:
	if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
		img.set_pixelv(p, col)
