extends SceneTree
## Writes the long zones of phase 15 (DESIGN.md 8.5): the shrines and wanderers (data/offers/), the
## sections of each zone (data/zones/sections/) and the zones themselves (data/zones/), which keep
## their id, name, look, leader, map picture, sounds and fights but are now built from sections.
## Every zone gets the same five kinds of middle section, dressed in its own props and walls (some
## mirrored left to right): Fork (a wall splits off a back path), Yard (a champion's walled yard),
## Pass (cliffs squeeze the way), Court (pillars and ruins), Loop (a rock mass to walk around).
## Run: Godot --headless --path . -s tools/bootstrap_zones.gd   (rewrites every file it owns)

const ENV := "res://assets/sprites/env/"
const SHROOM_GLOW := Color(0.35, 1.0, 0.85)
const LAMP_LIGHT := Color(1.0, 0.68, 0.38)
const BOG_LIGHT := Color(0.55, 1.0, 0.6)
## The depth of every long zone (z), the same frame every section is drawn in.
const Z_BACK: float = -20.0
const Z_FRONT: float = 10.0
## Solid decoration keeps this far from every spot that matters and out of the main lane.
const KEEP_OUT: float = 2.2
const LANE_KEEP: float = 3.6
## A block in front of the lane (toward the camera) is never taller than this, so it never hides
## the leader.
const FRONT_HEIGHT: float = 1.3

var _written: int = 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/offers"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/zones/sections"))
	var offers := _offers()
	_zone("rotten_hollow", offers, {
		"edge": "cliff", "wall": "ruin_wall", "rock_block": "cliff",
		"trees": [["rotten_tree", 0.06, 0.6], ["dead_tree", 0.06, 0.4]],
		"glow": SHROOM_GLOW, "light": LAMP_LIGHT, "grass": 18, "shrooms": 2, "lamps": true,
		"champion": "res://data/encounters/elite_twin_husks.tres", "flip": [],
		"guard": "res://data/encounters/guard_gorged_one.tres",
	})
	_zone("sunken_bog", offers, {
		"edge": "cliff", "wall": "ruin_wall", "rock_block": "cliff",
		"trees": [["rotten_tree", 0.06, 0.6], ["rotten_tree", 0.06, 0.6], ["dead_tree", 0.06, 0.4]],
		"glow": BOG_LIGHT, "light": BOG_LIGHT, "grass": 14, "shrooms": 5, "lamps": false,
		"champion": "res://data/encounters/elite_toad_court.tres", "flip": ["fork", "pass"],
		"guard": "res://data/encounters/guard_mire_mother.tres",
	})
	_zone("ashen_ruins", offers, {
		"edge": "ruin_wall", "wall": "ruin_wall", "rock_block": "cliff",
		"trees": [["dead_tree", 0.06, 0.4], ["pillar", 0.055, 0.45]],
		"glow": SHROOM_GLOW, "light": LAMP_LIGHT, "grass": 10, "shrooms": 1, "lamps": true,
		"champion": "res://data/encounters/elite_shade_coven.tres", "flip": ["yard", "loop"],
		"guard": "res://data/encounters/guard_ash_warden.tres",
	})
	print("bootstrap_zones: wrote %d files" % _written)
	quit()


# --- shrines and wanderers --------------------------------------------------------------------

func _offers() -> Dictionary:
	var key := load("res://data/items/key.tres") as ItemData
	var list := {}
	list.spring = _offer("healing_spring", "Healing Spring", ZoneOfferData.Kind.SHRINE, "shrine_spring",
			"Drink from the Healing Spring?", "Free. Everyone heals 30% of their HP.", "Drink", SHROOM_GLOW)
	list.spring.heal_percent = 30
	list.altar = _offer("blood_altar", "Blood Altar", ZoneOfferData.Kind.SHRINE, "shrine_altar",
			"Bleed on the Blood Altar?", "Everyone loses 20% of their max HP (never below 1).\nThe altar gives something rare.",
			"Bleed", Color(1.0, 0.3, 0.25))
	list.altar.cost_hp_percent = 20
	list.altar.find_rarity = ItemData.Rarity.RARE
	list.idol = _offer("war_idol", "War Idol", ZoneOfferData.Kind.SHRINE, "shrine_idol",
			"Pray to the War Idol?", "Free. The team gauge fills by 50.", "Pray", Color(1.0, 0.7, 0.3))
	list.idol.team_gauge = 50
	list.plenty = _offer("shrine_of_plenty", "Shrine of Plenty", ZoneOfferData.Kind.SHRINE, "shrine_plenty",
			"Leave 40 gold at the Shrine of Plenty?", "Every hero gets 40 XP.", "Leave the gold", Color(1.0, 0.85, 0.4))
	list.plenty.cost_gold = 40
	list.plenty.xp = 40
	list.peddler = _offer("key_peddler", "Key Peddler", ZoneOfferData.Kind.WANDERER, "wanderer_peddler",
			"\"A key for 30 gold?\"", "The Key Peddler sells one key. Keys open locked chests.", "Buy the key",
			LAMP_LIGHT)
	list.peddler.cost_gold = 30
	list.peddler.item = key
	list.robber = _offer("grave_robber", "Grave Robber", ZoneOfferData.Kind.WANDERER, "wanderer_robber",
			"\"Something rare, 45 gold. No questions.\"", "The Grave Robber sells one rare or better find.",
			"Pay 45 gold", Color(0.75, 0.6, 1.0))
	list.robber.cost_gold = 45
	list.robber.find_rarity = ItemData.Rarity.RARE
	list.pilgrim = _offer("old_pilgrim", "Old Pilgrim", ZoneOfferData.Kind.WANDERER, "wanderer_pilgrim",
			"\"Rest by my fire a while?\"", "Free. Everyone heals 15% and gets 20 XP.", "Rest", LAMP_LIGHT)
	list.pilgrim.heal_percent = 15
	list.pilgrim.xp = 20
	for name: String in list:
		var offer := list[name] as ZoneOfferData
		list[name] = _save(offer, "res://data/offers/%s.tres" % offer.id)
	return list


func _offer(id: String, title: String, kind: ZoneOfferData.Kind, sprite: String, question: String, detail: String,
		yes: String, color: Color) -> ZoneOfferData:
	var offer := ZoneOfferData.new()
	offer.id = id
	offer.display_name = title
	offer.kind = kind
	offer.sprite_path = ENV + sprite + ".png"
	offer.pixel_size = 0.05 if kind == ZoneOfferData.Kind.SHRINE else 0.045
	offer.question = question
	offer.detail = detail
	offer.yes_text = yes
	offer.no_text = "Not now"
	offer.glow = 1.2 if kind == ZoneOfferData.Kind.SHRINE else 0.0
	offer.glow_color = color
	offer.solid_radius = 0.5 if kind == ZoneOfferData.Kind.SHRINE else 0.35
	return offer


# --- a zone -----------------------------------------------------------------------------------

func _zone(id: String, offers: Dictionary, theme: Dictionary) -> void:
	var path := "res://data/zones/%s.tres" % id
	var zone := load(path) as ZoneData
	# The roaming fights: the zone's pool once it is a long zone, else its old roaming enemies.
	var pool: Array[EncounterData] = []
	pool.assign(zone.roamer_pool)
	for e: ZoneEnemyData in zone.enemies:
		if e != null and e.encounter != null and not e.guard and not pool.has(e.encounter):
			pool.append(e.encounter)
	var guard := load(String(theme.guard)) as EncounterData
	if guard == null:
		push_error("bootstrap_zones: %s has no guard (run tools/bootstrap_phase15.gd first)" % id)
		return
	theme["id"] = id
	theme["guard"] = guard
	zone.blocks.clear()
	zone.props.clear()
	zone.lights.clear()
	zone.enemies.clear()
	zone.item_spots.clear()
	zone.chests.clear()
	zone.seal_spots.clear()
	zone.gate = null
	zone.offers.clear()
	zone.offer_spots.clear()
	zone.bounds_min = Vector2(0.0, Z_BACK)
	zone.bounds_max = Vector2(1.0, Z_FRONT)
	zone.player_start = Vector3.ZERO
	zone.roamer_pool.assign(pool)
	zone.shrines.assign([offers.spring, offers.altar, offers.idol, offers.plenty])
	zone.wanderers.assign([offers.peddler, offers.robber, offers.pilgrim])
	zone.wanderer_percent = 60
	zone.middle_count = 3
	zone.edge_texture_path = ENV + String(theme.edge) + ".png"
	zone.edge_height = 4.5
	zone.start_section = _section(_start(theme), theme)
	zone.middle_sections.assign([
		_section(_fork(theme), theme),
		_section(_yard(theme), theme),
		_section(_pass(theme), theme),
		_section(_court(theme), theme),
		_section(_loop(theme), theme),
	])
	zone.end_section = _section(_end(theme), theme)
	_save(zone, path)


## Mirrors a section left to right when its zone asks, adds the decoration, saves it.
func _section(sec: ZoneSectionData, theme: Dictionary) -> ZoneSectionData:
	var kind := sec.id
	sec.id = "%s_%s" % [theme.id, kind]
	if (theme.flip as Array).has(kind):
		_mirror(sec)
	_decorate(sec, theme)
	return _save(sec, "res://data/zones/sections/%s.tres" % sec.id) as ZoneSectionData


func _mirror(sec: ZoneSectionData) -> void:
	var w := sec.width
	var flip := func(v: Vector3) -> Vector3: return Vector3(w - v.x, v.y, v.z)
	for b: ZoneBlockData in sec.blocks:
		b.position = flip.call(b.position)
		b.rotation_y_degrees = -b.rotation_y_degrees
	for p: ZonePropData in sec.props:
		p.position = flip.call(p.position)
		p.flip = not p.flip
	for l: ZoneLightData in sec.lights:
		l.position = flip.call(l.position)
	for e: ZoneEnemyData in sec.enemies:
		e.position = flip.call(e.position)
		e.prize_spot = flip.call(e.prize_spot)
	for list: Array[Vector3] in [sec.item_spots, sec.chests, sec.seal_spots, sec.shrine_spots, sec.wanderer_spots]:
		for i: int in list.size():
			list[i] = flip.call(list[i])
	if sec.gate != null:
		sec.gate.position = flip.call(sec.gate.position)


# --- the sections -----------------------------------------------------------------------------

## The way in: the party arrives at the left. A lamp and a glinting spot by the back wall.
func _start(theme: Dictionary) -> ZoneSectionData:
	var sec := _new("start", 16.0)
	sec.player_start = Vector3(3.0, 0.0, 1.0)
	sec.item_spots.append(Vector3(9.0, 0.0, -14.0))
	_lamp(sec, theme, Vector3(6.0, 0.0, -4.5))
	_lamp(sec, theme, Vector3(12.0, 0.0, 4.5))
	return sec


## A long wall splits the way: the main lane in front, a back path behind it that runs the whole
## section, with the seal and a find at its far end.
func _fork(theme: Dictionary) -> ZoneSectionData:
	var sec := _new("fork", 30.0)
	sec.blocks.append(_block(Vector3(15.0, 0.0, -6.0), Vector3(18.0, 1.8, 0.9), theme.wall))
	sec.blocks.append(_block(Vector3(15.0, 0.0, -13.0), Vector3(10.0, 3.0, 3.0), theme.rock_block))
	sec.seal_spots.assign([Vector3(15.0, 0.0, -16.5), Vector3(15.0, 0.0, -9.0)])
	sec.item_spots.append(Vector3(26.0, 0.0, -15.0))
	sec.shrine_spots.append(Vector3(15.0, 0.0, 6.5))
	sec.enemies.append(_roamer(Vector3(10.0, 0.0, 1.0), 2.5, 80))
	sec.enemies.append(_roamer(Vector3(22.0, 0.0, -10.0), 2.0, 70))
	sec.enemies.append(_roamer(Vector3(24.0, 0.0, 5.0), 2.0, 40))
	_lamp(sec, theme, Vector3(5.0, 0.0, -4.5))
	_lamp(sec, theme, Vector3(25.0, 0.0, -4.5))
	return sec


## A walled yard at the back with one way in: a champion stands guard over its prize chest.
func _yard(theme: Dictionary) -> ZoneSectionData:
	var sec := _new("yard", 30.0)
	sec.blocks.append(_block(Vector3(8.0, 0.0, -14.5), Vector3(0.9, 2.2, 11.0), theme.wall))
	sec.blocks.append(_block(Vector3(22.0, 0.0, -14.5), Vector3(0.9, 2.2, 11.0), theme.wall))
	sec.blocks.append(_block(Vector3(10.25, 0.0, -9.0), Vector3(4.5, 2.2, 0.9), theme.wall))
	sec.blocks.append(_block(Vector3(19.75, 0.0, -9.0), Vector3(4.5, 2.2, 0.9), theme.wall))
	var champion := _roamer(Vector3(15.0, 0.0, -14.0), 0.0, 100)
	champion.encounter = load(String(theme.champion)) as EncounterData
	champion.champion = true
	champion.prize_spot = Vector3(15.0, 0.0, -18.0)
	sec.enemies.append(champion)
	sec.seal_spots.assign([Vector3(4.0, 0.0, -16.0), Vector3(26.5, 0.0, -16.0)])
	sec.item_spots.append(Vector3(5.0, 0.0, 7.5))
	sec.wanderer_spots.append(Vector3(26.0, 0.0, -5.0))
	sec.enemies.append(_roamer(Vector3(9.0, 0.0, 2.0), 2.5, 80))
	sec.enemies.append(_roamer(Vector3(24.0, 0.0, -1.0), 2.5, 60))
	_lamp(sec, theme, Vector3(12.0, 0.0, -7.5))
	_lamp(sec, theme, Vector3(18.0, 0.0, -7.5))
	return sec


## Cliffs squeeze the way into a narrow pass with an enemy in it. A locked chest waits at the back.
func _pass(theme: Dictionary) -> ZoneSectionData:
	var sec := _new("pass", 28.0)
	sec.blocks.append(_block(Vector3(14.0, 0.0, -11.75), Vector3(4.0, 3.5, 16.5), theme.rock_block))
	sec.blocks.append(_block(Vector3(14.0, 0.0, 7.0), Vector3(4.0, FRONT_HEIGHT, 6.0), theme.rock_block))
	sec.seal_spots.assign([Vector3(6.0, 0.0, -16.0), Vector3(22.0, 0.0, -16.0)])
	sec.chests.append(Vector3(25.0, 0.0, -18.0))
	sec.item_spots.append(Vector3(22.0, 0.0, 8.0))
	sec.shrine_spots.append(Vector3(5.0, 0.0, 6.0))
	sec.enemies.append(_roamer(Vector3(19.0, 0.0, 0.0), 1.5, 90))
	sec.enemies.append(_roamer(Vector3(7.0, 0.0, -9.0), 2.5, 60))
	sec.enemies.append(_roamer(Vector3(22.0, 0.0, -10.0), 2.5, 50))
	_glow(sec, theme, Vector3(11.0, 0.0, -2.8))
	_glow(sec, theme, Vector3(17.0, 0.0, 3.6))
	return sec


## A ruined court: rows of pillars and broken walls, a wanderer's corner, a locked chest.
func _court(theme: Dictionary) -> ZoneSectionData:
	var sec := _new("court", 32.0)
	for x: float in [8.0, 14.0, 20.0, 26.0]:
		for z: float in [-13.0, -7.0]:
			sec.props.append(_prop("pillar", Vector3(x, 0.0, z), 0.055, 0.45, x > 16.0))
	sec.blocks.append(_block(Vector3(11.0, 0.0, -17.0), Vector3(6.0, 1.6, 0.8), theme.wall))
	sec.blocks.append(_block(Vector3(23.0, 0.0, -10.0), Vector3(0.8, 1.6, 4.0), theme.wall))
	sec.seal_spots.assign([Vector3(17.0, 0.0, -17.5), Vector3(29.0, 0.0, -10.0)])
	sec.chests.append(Vector3(3.0, 0.0, -18.0))
	sec.item_spots.append(Vector3(20.0, 0.0, 7.5))
	sec.shrine_spots.append(Vector3(17.0, 0.0, -10.0))
	sec.wanderer_spots.append(Vector3(6.0, 0.0, 5.5))
	sec.enemies.append(_roamer(Vector3(11.0, 0.0, -10.0), 2.0, 80))
	sec.enemies.append(_roamer(Vector3(24.0, 0.0, -2.0), 2.5, 70))
	sec.enemies.append(_roamer(Vector3(28.0, 0.0, 5.0), 2.0, 50))
	_lamp(sec, theme, Vector3(14.0, 0.0, -4.0))
	_lamp(sec, theme, Vector3(26.0, 0.0, -4.0))
	return sec


## A big rock mass to walk around: the seal waits behind it, watched by an enemy.
func _loop(theme: Dictionary) -> ZoneSectionData:
	var sec := _new("loop", 30.0)
	sec.blocks.append(_block(Vector3(15.0, 0.0, -9.0), Vector3(12.0, 3.5, 7.0), theme.rock_block))
	sec.seal_spots.assign([Vector3(15.0, 0.0, -16.5), Vector3(24.0, 0.0, -16.0)])
	sec.item_spots.append(Vector3(6.0, 0.0, -16.0))
	sec.shrine_spots.append(Vector3(4.0, 0.0, -11.0))
	sec.wanderer_spots.append(Vector3(25.0, 0.0, 6.0))
	sec.enemies.append(_roamer(Vector3(15.0, 0.0, -15.0), 4.0, 85))
	sec.enemies.append(_roamer(Vector3(10.0, 0.0, 3.0), 2.5, 70))
	sec.enemies.append(_roamer(Vector3(21.0, 0.0, 1.0), 2.5, 50))
	_glow(sec, theme, Vector3(8.5, 0.0, -5.0))
	_glow(sec, theme, Vector3(21.5, 0.0, -13.0))
	return sec


## The end: a gate of rotten roots across the whole depth, then the guard's ground.
func _end(theme: Dictionary) -> ZoneSectionData:
	var sec := _new("end", 26.0)
	var gate := _block(Vector3(4.0, 0.0, (Z_BACK + Z_FRONT) * 0.5), Vector3(1.2, 2.6, Z_FRONT - Z_BACK), "rot_gate")
	gate.texture_world_size = 2.4
	sec.gate = gate
	var guard := ZoneEnemyData.new()
	guard.encounter = theme.guard as EncounterData
	guard.position = Vector3(18.0, 0.0, -1.0)
	guard.wander_radius = 1.0
	guard.guard = true
	sec.enemies.append(guard)
	for z: float in [-6.0, 4.0]:
		sec.props.append(_prop("pillar", Vector3(14.0, 0.0, z), 0.055, 0.45, z > 0.0))
		sec.props.append(_prop("pillar", Vector3(22.0, 0.0, z), 0.055, 0.45, z > 0.0))
	_lamp(sec, theme, Vector3(8.0, 0.0, -4.5))
	_lamp(sec, theme, Vector3(8.0, 0.0, 4.5))
	sec.lights.append(_light(Vector3(18.0, 2.0, -1.0), theme.light, 2.6, 8.0, 10))
	return sec


func _new(kind: String, width: float) -> ZoneSectionData:
	var sec := ZoneSectionData.new()
	sec.id = kind
	sec.width = width
	return sec


# --- decoration -------------------------------------------------------------------------------

## Trees, rocks, glowing fungus and grass at seeded random spots that keep clear of the lane, the
## blocks and every spot that matters (so nothing that counts is ever walled in).
func _decorate(sec: ZoneSectionData, theme: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sec.id)
	var keep: Array[Vector3] = []
	keep.append_array(sec.item_spots)
	keep.append_array(sec.chests)
	keep.append_array(sec.seal_spots)
	keep.append_array(sec.shrine_spots)
	keep.append_array(sec.wanderer_spots)
	keep.append(sec.player_start)
	for e: ZoneEnemyData in sec.enemies:
		keep.append(e.position)
		if e.champion:
			keep.append(e.prize_spot)
	for p: ZonePropData in sec.props:
		keep.append(p.position)
	var trees: Array = theme.trees
	var placed := 0
	var tries := 0
	while placed < int(sec.width / 5.0) and tries < 400:
		tries += 1
		var kind: Array = trees[rng.randi_range(0, trees.size() - 1)]
		var spot := Vector3(rng.randf_range(1.0, sec.width - 1.0), 0.0, rng.randf_range(Z_BACK + 1.0, Z_FRONT - 1.0))
		# Trees stand along the back, never in the walkways or in front of the camera's view.
		if spot.z > -LANE_KEEP - 10.0:
			continue
		if _clear(sec, keep, spot, float(kind[2])):
			sec.props.append(_prop(String(kind[0]), _snap(spot), float(kind[1]), float(kind[2]), rng.randf() < 0.5))
			keep.append(spot)
			placed += 1
	placed = 0
	tries = 0
	while placed < 2 and tries < 200:
		tries += 1
		var spot := Vector3(rng.randf_range(1.0, sec.width - 1.0), 0.0, rng.randf_range(Z_BACK + 1.0, Z_FRONT - 1.0))
		if absf(spot.z) < LANE_KEEP:
			continue
		if _clear(sec, keep, spot, 0.7):
			sec.props.append(_prop("rock", _snap(spot), 0.05, 0.7, rng.randf() < 0.5))
			keep.append(spot)
			placed += 1
	for i: int in int(theme.shrooms):
		var spot := Vector3(rng.randf_range(1.0, sec.width - 1.0), 0.0, rng.randf_range(Z_BACK + 1.0, Z_FRONT - 1.0))
		sec.props.append(_glow_prop("glow_shroom", _snap(spot), 0.05, 1.5, theme.glow))
	for i: int in int(theme.grass):
		var spot := Vector3(rng.randf_range(0.5, sec.width - 0.5), 0.0, rng.randf_range(Z_BACK + 0.5, Z_FRONT - 0.5))
		sec.props.append(_prop("grass", _snap(spot), 0.045, 0.0, rng.randf() < 0.5))


## True if a solid prop of `radius` at `spot` stays clear of the blocks and the kept spots.
func _clear(sec: ZoneSectionData, keep: Array[Vector3], spot: Vector3, radius: float) -> bool:
	for k: Vector3 in keep:
		if Vector2(k.x, k.z).distance_to(Vector2(spot.x, spot.z)) < KEEP_OUT + radius:
			return false
	var at := Vector2(spot.x, spot.z)
	for b: ZoneBlockData in sec.blocks:
		var o := {"centre": Vector2(b.position.x, b.position.z), "half": Vector2(b.size.x, b.size.z) * 0.5,
				"angle": deg_to_rad(b.rotation_y_degrees)}
		if ZonePath._overlaps(at, radius + 1.2, o):
			return false
	return true


func _snap(v: Vector3) -> Vector3:
	return Vector3(snappedf(v.x, 0.01), 0.0, snappedf(v.z, 0.01))


func _lamp(sec: ZoneSectionData, theme: Dictionary, at: Vector3) -> void:
	if bool(theme.lamps):
		sec.props.append(_prop("lamp", at, 0.05, 0.3))
		sec.lights.append(_light(at + Vector3(0.0, 1.9, 0.3), LAMP_LIGHT, 2.4, 7.0, 12))
	else:
		_glow(sec, theme, at)


func _glow(sec: ZoneSectionData, theme: Dictionary, at: Vector3) -> void:
	sec.props.append(_glow_prop("glow_shroom", at, 0.05, 1.5, theme.glow))
	sec.lights.append(_light(at + Vector3(0.0, 1.2, 0.3), theme.glow, 1.8, 6.0, 0))


# --- small builders (as in bootstrap_run.gd) --------------------------------------------------

func _roamer(pos: Vector3, wander: float, chance: int) -> ZoneEnemyData:
	var roamer := ZoneEnemyData.new()
	roamer.position = pos
	roamer.wander_radius = wander
	roamer.chance_percent = chance
	return roamer


func _block(pos: Vector3, size: Vector3, texture: String, turn: float = 0.0) -> ZoneBlockData:
	var block := ZoneBlockData.new()
	block.position = pos
	block.size = size
	block.texture_path = ENV + texture + ".png"
	block.rotation_y_degrees = turn
	return block


func _prop(sprite: String, pos: Vector3, pixel: float, solid: float, flip: bool = false) -> ZonePropData:
	var prop := ZonePropData.new()
	prop.sprite_path = ENV + sprite + ".png"
	prop.position = pos
	prop.pixel_size = pixel
	prop.solid_radius = solid
	prop.flip = flip
	return prop


func _glow_prop(sprite: String, pos: Vector3, pixel: float, glow: float, color: Color) -> ZonePropData:
	var prop := _prop(sprite, pos, pixel, 0.0)
	prop.glow = glow
	prop.glow_color = color
	return prop


func _light(pos: Vector3, color: Color, energy: float, reach: float, flicker: int) -> ZoneLightData:
	var light := ZoneLightData.new()
	light.position = pos
	light.color = color
	light.energy = energy
	light.reach = reach
	light.flicker_percent = flicker
	return light


func _save(res: Resource, path: String) -> Resource:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("bootstrap_zones: could not save %s (%d)" % [path, err])
		return res
	_written += 1
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
