class_name SkillsTab
extends PartyTab
## The Skills tab of the party screen (DESIGN.md 8.4 and 8.18; it replaces the old Skills page,
## SkillsScreen, with the same rules). Top left the shown hero's face, name and free skill points
## (LT / RT: the previous / next hero with a tree, heroes without one are skipped); along the top
## the sockets of the skills they bring into fights (tuning.skill_slots); below, the tree: its
## branches as columns of skill tiles joined by lines. A tile says its state by its frame, never
## by a word: gold = brought, lit = known, a green plus = can learn now, dim with a lock = locked.
## Confirm learns a skill (skill points), or brings / leaves behind a known one; a refusal goes to
## the info strip's line. Online, the changes go to the host as the old page's RunState ops
## ("unlock" and "loadout").

enum State { BROUGHT, KNOWN, LEARNABLE, LOCKED }

## The state chip's word in the info strip ("Learn: %d" takes the cost).
const STATE_WORDS: Array[String] = ["Brought", "Known", "Learn: %d", "Locked"]
## The confirm hint's word per state (a locked skill still answers Confirm, with its reason).
const CONFIRM_WORDS: Array[String] = ["Leave", "Bring", "Learn", "Learn"]
## The info strip's line is cut to this many characters (it holds one line).
const LINE_CHARS: int = 400

# Layout on the 1920 x 750 page.
const MARGIN: float = 40.0
const HEADER_TOP: float = 14.0
const FACE_PX: float = 72.0
const NAME_SIZE: int = 38
const BADGE_SIZE: int = 28
const BADGE_GLYPH_PX: float = 24.0
const CHIP_SIZE: int = 22
const SOCKET_LEFT: float = 660.0
const SOCKET_TOP: float = 24.0
const SOCKET_SIZE := Vector2(220.0, 68.0)
const SOCKET_GAP: float = 18.0
const TREE_TOP: float = 132.0
const HEAD_SIZE: int = 26
const HEAD_HEIGHT: float = 44.0
const TILE_SIZE := Vector2(380.0, 96.0)
const COLUMN_GAP: float = 90.0
const TIER_GAP: float = 38.0
const BOTTOM_PAD: float = 12.0
const LINE_WIDTH: float = 4.0

# The tiles' look.
const KNOWN_EDGE := Color(0.95, 0.94, 0.9, 0.8)
const LOCKED_EDGE := Color(0.42, 0.37, 0.3, 0.45)
const LOCKED_BG := Color(0.02, 0.02, 0.03, 0.8)
const CHOSEN_BG := Color(0.14, 0.11, 0.07, 0.94)
const GLOW := Color(1.0, 0.82, 0.3, 0.6)
const GLOW_SIZE: int = 14
const LEARN_LINE := Color(0.45, 1.0, 0.5, 0.55)
const DIM_LINE := Color(0.42, 0.37, 0.3, 0.45)
## The points badge with nothing to spend: still there (nothing jumps), only faint.
const DIM_ALPHA: float = 0.4

var _cursor := Vector2i.ZERO
## Why the last Confirm did nothing ("" when it worked or the cursor moved since).
var _refusal: String = ""
## The hero the tiles were built for (-1: none yet).
var _built_for: int = -1
## [branch] -> Array of SkillTile, top down.
var _cells: Array = []
var _sockets: Array[SkillTile] = []
var _tree_layer: Control
var _hero_box: HBoxContainer
var _face: PanelContainer
var _name: Label
var _badge: PanelContainer
var _points: Label
var _prev_chip: HintBar
var _next_chip: HintBar


func setup(p_run: RunState, p_remote: bool) -> void:
	super(p_run, p_remote)
	_build_header()
	_tree_layer = Control.new()
	_tree_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree_layer.size = PAGE_SIZE
	_tree_layer.draw.connect(_draw_lines)
	add_child(_tree_layer)
	_show_hero(hero)


func refresh() -> void:
	_sync()


func shown() -> void:
	_sync()


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouse:
		return _mouse_input(event)
	if pressed(event, &"menu_left"):
		move_cursor(Vector2i.LEFT)
	elif pressed(event, &"menu_right"):
		move_cursor(Vector2i.RIGHT)
	elif pressed(event, &"menu_up"):
		move_cursor(Vector2i.UP)
	elif pressed(event, &"menu_down"):
		move_cursor(Vector2i.DOWN)
	elif pressed(event, &"menu_confirm"):
		confirm()
	elif pressed(event, &"party_attributes"):
		_turn_hero(-1)
	elif pressed(event, &"party_skills"):
		_turn_hero(1)
	else:
		return false
	return true


func hints() -> Array:
	var entries: Array = [[&"@arrows", ""]]
	var skill := selected()
	if skill != null:
		entries.append([&"menu_confirm", CONFIRM_WORDS[_state_of(skill)]])
	if _heroes_with_tree() > 1:
		entries.append([&"party_attributes", ""])
		entries.append([&"party_skills", "Hero"])
	return entries


func info() -> Dictionary:
	if run == null:
		return {}
	if not run.has_tree(hero):
		return {"icon": &"lock", "title": "No skill tree", "color": HudStyle.TEXT_DIM, "chips": [],
				"line": "This hero has every skill already."}
	var skill := selected()
	if skill == null:
		return {}
	var state := _state_of(skill)
	var cost := run.skill_cost(hero, skill.id)
	var chips: Array = [["", "%d AP" % skill.ap_cost, HudStyle.AP_TEXT]]
	match state:
		State.BROUGHT:
			chips.append(["", STATE_WORDS[state], HudStyle.GOLD])
		State.KNOWN:
			chips.append(["", STATE_WORDS[state], HudStyle.TEXT])
		State.LEARNABLE:
			chips.append([&"plus", STATE_WORDS[state] % cost, HudStyle.HEAL])
		_:
			chips.append([&"lock", STATE_WORDS[state], HudStyle.TEXT_DIM])
			chips.append([&"up", str(cost), HudStyle.TEXT_DIM])
	return {"icon": &"branch", "title": skill.display_name, "color": name_color(state), "chips": chips,
			"line": _refusal if not _refusal.is_empty() else one_line(skill.description)}


## Free skill points over every hero with a tree (a hero without one has nothing to spend them on).
func badge() -> int:
	if run == null:
		return 0
	var total := 0
	for slot: int in run.party_size():
		if run.has_tree(slot):
			total += maxi(0, run.free_skill_points(slot))
	return total


## Shows hero `slot`'s tree, or the next hero's that has one if `slot` has none.
func set_hero(slot: int) -> void:
	_show_hero(slot)
	changed.emit()


## The skill under the cursor (null: none, for a hero without a tree).
func selected() -> AbilityData:
	if _cells.is_empty() or _cursor.x >= _cells.size() or (_cells[_cursor.x] as Array).is_empty():
		return null
	return (_cells[_cursor.x][_cursor.y] as SkillTile).skill


## Moves the cursor: across the branches (wrapping round) and up / down a branch (stopping at its
## ends), like the old page.
func move_cursor(step: Vector2i) -> void:
	if _cells.is_empty():
		return
	var before := _cursor
	_cursor.x = wrapi(_cursor.x + step.x, 0, _cells.size())
	_cursor.y += step.y
	_clamp_cursor()
	if _cursor == before:
		return
	_refusal = ""
	Sfx.play("menu_move")
	_redraw()
	changed.emit()


## Confirm on the skill under the cursor: learns it, or leaves it behind / brings it. False (and
## the reason on the info strip's line) when nothing could be done.
func confirm() -> bool:
	var skill := selected()
	if skill == null:
		return false
	var ids: Array = run.loadout[hero].duplicate()
	var ok := false
	_refusal = ""
	match _state_of(skill):
		State.LEARNABLE:
			ok = ask({"op": "unlock", "slot": hero, "ability": skill.id})
			if ok:
				toast.emit("Learned %s" % skill.display_name, &"plus")
				Sfx.play("level_up")
		State.BROUGHT:
			ids.erase(skill.id)
			ok = ask({"op": "loadout", "slot": hero, "abilities": ids})
			if ok:
				toast.emit("%s stays behind" % skill.display_name, &"branch")
				Sfx.play("menu_cancel")
		State.KNOWN:
			if ids.size() >= run.tuning.skill_slots:
				_refusal = "Already bringing %d skills: leave one behind first." % run.tuning.skill_slots
			else:
				ids.append(skill.id)
				ok = ask({"op": "loadout", "slot": hero, "abilities": ids})
				if ok:
					toast.emit("Bringing %s" % skill.display_name, &"branch")
					Sfx.play("menu_confirm")
		_:
			_refusal = _locked_reason(skill)
	if not ok:
		Sfx.play("locked")
		if _refusal.is_empty():
			_refusal = "Not possible any more."
		changed.emit()
	_redraw()
	return ok


## `text`'s first line, cut to `limit` characters at a word (for the info strip's one line).
static func one_line(text: String, limit: int = LINE_CHARS) -> String:
	var lines := text.strip_edges().split("\n", false)
	if lines.is_empty():
		return ""
	var line := lines[0].strip_edges()
	if line.length() <= limit:
		return line
	var cut := line.substr(0, limit - 1)
	var space := cut.rfind(" ")
	if space * 2 > limit:
		cut = cut.substr(0, space)
	return cut.strip_edges() + "…"


## A tile's slanted plate: the frame says the state, the gold glow the cursor.
static func plate(state: int, chosen: bool, height: float) -> StyleBoxFlat:
	var bg := HudStyle.INK
	var edge := KNOWN_EDGE
	var width := 2
	match state:
		State.BROUGHT:
			edge = HudStyle.GOLD
			width = 3
		State.LEARNABLE:
			edge = HudStyle.EDGE_DIM
		State.LOCKED:
			edge = LOCKED_EDGE
			bg = LOCKED_BG
	if chosen:
		bg = CHOSEN_BG
	var box := HudStyle.slant(bg, edge, width, 10, height)
	if chosen:
		box.shadow_color = GLOW
		box.shadow_size = GLOW_SIZE
		box.shadow_offset = Vector2.ZERO
	return box


## The colour of a skill's name (and the info strip's title) in `state`.
static func name_color(state: int) -> Color:
	match state:
		State.BROUGHT:
			return HudStyle.GOLD
		State.LOCKED:
			return HudStyle.TEXT_DIM
	return HudStyle.TEXT


## The colour of a tile's glyph and cost: green to learn, dim when locked.
static func glyph_color(state: int) -> Color:
	return HudStyle.HEAL if state == State.LEARNABLE else HudStyle.TEXT_DIM


# --- state ------------------------------------------------------------------------------------

func _state_of(skill: AbilityData) -> State:
	if run.loadout[hero].has(skill.id):
		return State.BROUGHT
	if run.unlocked[hero].has(skill.id):
		return State.KNOWN
	if run.can_unlock(hero, skill.id):
		return State.LEARNABLE
	return State.LOCKED


func _locked_reason(skill: AbilityData) -> String:
	var parent := run.tree(hero).parent_of(skill.id)
	if parent != null and not run.unlocked[hero].has(parent.id):
		return "Learn %s first." % parent.display_name
	var cost := run.skill_cost(hero, skill.id)
	return "Needs %d skill point%s, %d free." % [cost, "" if cost == 1 else "s", run.free_skill_points(hero)]


## The points a tile shows beside its plus or lock: only once the skill above is known (deeper
## locked skills show just the lock), -1 for none.
func _shown_cost(skill: AbilityData, state: State) -> int:
	if skill == null or (state != State.LEARNABLE and state != State.LOCKED):
		return -1
	var parent := run.tree(hero).parent_of(skill.id)
	if parent != null and not run.unlocked[hero].has(parent.id):
		return -1
	return run.skill_cost(hero, skill.id)


func _skill_by_id(id: String) -> AbilityData:
	var at := run.tree(hero).place_of(id)
	if at.x < 0:
		return null
	return run.tree(hero).branches[at.x].skills[at.y]


func _clamp_cursor() -> void:
	if _cells.is_empty():
		_cursor = Vector2i.ZERO
		return
	_cursor.x = clampi(_cursor.x, 0, _cells.size() - 1)
	_cursor.y = clampi(_cursor.y, 0, maxi(0, (_cells[_cursor.x] as Array).size() - 1))


## The next hero (in `step` direction) who has a skill tree (`from` itself if nobody else has one).
func _next_hero_with_tree(from: int, step: int) -> int:
	for i: int in range(1, run.party_size() + 1):
		var slot := posmod(from + i * step, run.party_size())
		if run.has_tree(slot):
			return slot
	return from


func _heroes_with_tree() -> int:
	var count := 0
	for slot: int in run.party_size():
		if run.has_tree(slot):
			count += 1
	return count


func _turn_hero(step: int) -> void:
	var next := _next_hero_with_tree(hero, step)
	if next == hero:
		return
	Sfx.play("menu_move")
	set_hero(next)


## The screen may have moved `hero` (the hero shared by the tabs), or the run changed: rebuild for
## a new hero, else redraw.
func _sync() -> void:
	if run == null:
		return
	if hero != _built_for or not run.has_tree(hero):
		_show_hero(hero)
	else:
		_redraw()


func _show_hero(slot: int) -> void:
	if run == null:
		return
	var shown_slot := clampi(slot, 0, run.party_size() - 1)
	if not run.has_tree(shown_slot):
		shown_slot = _next_hero_with_tree(shown_slot, 1)
	hero = shown_slot
	_refusal = ""
	_build()
	_redraw()


# --- input ------------------------------------------------------------------------------------

## The mouse: pointing at a tile (or a filled socket) picks it, a left click is Confirm.
func _mouse_input(event: InputEvent) -> bool:
	var point := (event as InputEventMouse).position
	if event is InputEventMouseMotion:
		var at := _tile_at(point)
		if at.x < 0 or at == _cursor:
			return false
		_cursor = at
		_refusal = ""
		Sfx.play("menu_move")
		_redraw()
		changed.emit()
		return true
	if MenuMouse.is_click(event):
		var at := _tile_at(point)
		if at.x < 0:
			return false
		if at != _cursor:
			_cursor = at
			_refusal = ""
			_redraw()
		confirm()
		return true
	return false


## The tree place (branch, tier) under the viewport `point`; (-1, -1) for none.
func _tile_at(point: Vector2) -> Vector2i:
	for b: int in _cells.size():
		var t := MenuMouse.control_at(_cells[b], point)
		if t >= 0:
			return Vector2i(b, t)
	var socket := MenuMouse.control_at(_sockets, point)
	if socket >= 0 and _sockets[socket].skill != null and run.has_tree(hero):
		var place := run.tree(hero).place_of(_sockets[socket].skill.id)
		if place.x >= 0:
			return place
	return Vector2i(-1, -1)


# --- building ---------------------------------------------------------------------------------

func _build_header() -> void:
	_hero_box = HBoxContainer.new()
	_hero_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_box.position = Vector2(MARGIN, HEADER_TOP)
	_hero_box.add_theme_constant_override("separation", 14)
	add_child(_hero_box)
	_prev_chip = HintBar.new([[&"party_attributes", ""]], CHIP_SIZE)
	_prev_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hero_box.add_child(_prev_chip)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_theme_constant_override("separation", 4)
	_hero_box.add_child(words)
	_name = HudStyle.make_title("", NAME_SIZE)
	words.add_child(_name)
	_badge = PanelContainer.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_badge.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.GOLD, 2, 4, 40.0))
	words.add_child(_badge)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	_badge.add_child(row)
	var up := UiGlyph.make(&"up", BADGE_GLYPH_PX, HudStyle.GOLD)
	up.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(up)
	_points = HudStyle.make_number("0", BADGE_SIZE, HudStyle.GOLD)
	row.add_child(_points)
	_next_chip = HintBar.new([[&"party_skills", ""]], CHIP_SIZE)
	_next_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hero_box.add_child(_next_chip)


func _build_face() -> void:
	if _face != null:
		# Freed at once (nothing else holds it), so a rebuild leaves no orphan nodes behind.
		_face.free()
	var c := run.data.party[hero]
	_face = HudStyle.portrait_frame(AssetLoader.texture(c.portrait_path, Vector2i(48, 48)), c.color, FACE_PX)
	_hero_box.add_child(_face)
	_hero_box.move_child(_face, 1)


func _build() -> void:
	# Freed at once: the tiles only draw (no input, no signals), and a rebuild leaves no orphans.
	for child: Node in _tree_layer.get_children():
		child.free()
	for socket: SkillTile in _sockets:
		socket.free()
	_cells.clear()
	_sockets.clear()
	_built_for = hero
	_build_face()
	var slots := maxi(1, run.tuning.skill_slots)
	var room := PAGE_SIZE.x - MARGIN - SOCKET_LEFT
	var socket_w := minf(SOCKET_SIZE.x, (room - SOCKET_GAP * float(slots - 1)) / float(slots))
	for i: int in slots:
		var socket := SkillTile.new(true)
		socket.position = Vector2(SOCKET_LEFT + float(i) * (socket_w + SOCKET_GAP), SOCKET_TOP)
		socket.size = Vector2(socket_w, SOCKET_SIZE.y)
		add_child(socket)
		_sockets.append(socket)
	var skill_tree := run.tree(hero)
	if skill_tree == null or skill_tree.branches.is_empty():
		_clamp_cursor()
		return
	var count := skill_tree.branches.size()
	var tiers := 1
	for branch: SkillBranchData in skill_tree.branches:
		if branch != null:
			tiers = maxi(tiers, branch.skills.size())
	var col_w := minf(TILE_SIZE.x, (PAGE_SIZE.x - MARGIN * 2.0 - COLUMN_GAP * float(count - 1)) / float(count))
	var left := (PAGE_SIZE.x - col_w * float(count) - COLUMN_GAP * float(count - 1)) * 0.5
	var top := TREE_TOP + HEAD_HEIGHT
	var tile_h := minf(TILE_SIZE.y, (PAGE_SIZE.y - BOTTOM_PAD - top - TIER_GAP * float(tiers - 1)) / float(tiers))
	for b: int in count:
		var branch := skill_tree.branches[b]
		var x := left + float(b) * (col_w + COLUMN_GAP)
		var head := HudStyle.make_title(branch.display_name if branch != null else "", HEAD_SIZE, HudStyle.TEXT_DIM)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		head.position = Vector2(x, TREE_TOP)
		head.size = Vector2(col_w, HEAD_HEIGHT)
		_tree_layer.add_child(head)
		var column: Array = []
		if branch != null:
			for t: int in branch.skills.size():
				var tile := SkillTile.new(false)
				tile.skill = branch.skills[t]
				tile.position = Vector2(x, top + float(t) * (tile_h + TIER_GAP))
				tile.size = Vector2(col_w, tile_h)
				_tree_layer.add_child(tile)
				column.append(tile)
		_cells.append(column)
	_clamp_cursor()


# --- drawing ----------------------------------------------------------------------------------

func _redraw() -> void:
	if run == null or _name == null:
		return
	var c := run.data.party[hero]
	_name.text = c.display_name
	_name.label_settings.font_color = c.color.lightened(0.25)
	var points := maxi(0, run.free_skill_points(hero)) if run.has_tree(hero) else 0
	_points.text = str(points)
	_badge.modulate.a = 1.0 if points > 0 else DIM_ALPHA
	var many := _heroes_with_tree() > 1
	_prev_chip.visible = many
	_next_chip.visible = many
	var picked := selected()
	for b: int in _cells.size():
		var column: Array = _cells[b]
		for t: int in column.size():
			var tile := column[t] as SkillTile
			var state := _state_of(tile.skill) if tile.skill != null else State.LOCKED
			tile.show_skill(tile.skill, state, _shown_cost(tile.skill, state), Vector2i(b, t) == _cursor)
	var ids: Array = run.loadout[hero] if run.has_tree(hero) else []
	for i: int in _sockets.size():
		var skill: AbilityData = _skill_by_id(String(ids[i])) if i < ids.size() else null
		_sockets[i].show_skill(skill, State.BROUGHT, -1, skill != null and skill == picked)
	_tree_layer.queue_redraw()


## The lines joining each skill to the one above it: gold once it is known, green when it can be
## learned, dim otherwise. Drawn on the tree layer, under its tiles.
func _draw_lines() -> void:
	for b: int in _cells.size():
		var column: Array = _cells[b]
		for t: int in range(1, column.size()):
			var upper := column[t - 1] as SkillTile
			var lower := column[t] as SkillTile
			var color := DIM_LINE
			if lower.skill != null and lower.state != State.LOCKED:
				color = LEARN_LINE if lower.state == State.LEARNABLE else HudStyle.EDGE
			_tree_layer.draw_line(upper.position + Vector2(upper.size.x * 0.5, upper.size.y),
					lower.position + Vector2(lower.size.x * 0.5, 0.0), color, LINE_WIDTH, true)


## One skill as a slanted plate: a tile of the tree or (compact) a loadout socket. Its name, its AP
## cost as blue pips, and on the right a green plus (can learn) or a lock, with the points it
## costs. With no skill it is an empty socket: a dashed outline.
class SkillTile extends Control:
	const PAD: float = 12.0
	const GLYPH_PX: float = 34.0
	const COMPACT_GLYPH_PX: float = 24.0
	const NAME_PX: int = 28
	const COMPACT_NAME_PX: int = 22
	const PIP_RADIUS: float = 7.0
	const COMPACT_PIP_RADIUS: float = 5.0
	## Pip spacing, in pip radii.
	const PIP_STEP: float = 2.7
	const MAX_PIPS: int = 10
	const COST_WIDTH: float = 36.0
	const GLYPH_GAP: float = 6.0
	const DASH: float = 10.0
	const EMPTY_EDGE := Color(0.42, 0.37, 0.3, 0.75)

	var skill: AbilityData
	var state: int = SkillsTab.State.LOCKED
	var chosen: bool = false
	## The points shown beside the plus or the lock (-1: none).
	var cost: int = -1
	var compact: bool = false
	var _name: Label
	var _cost: Label

	func _init(p_compact: bool = false) -> void:
		compact = p_compact
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name = HudStyle.make_label("", COMPACT_NAME_PX if compact else NAME_PX)
		_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_name)
		_cost = HudStyle.make_number("", COMPACT_NAME_PX if compact else NAME_PX)
		_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_cost)
		resized.connect(_layout)

	## Shows `p_skill` (null: an empty socket) in `p_state` (a SkillsTab.State).
	func show_skill(p_skill: AbilityData, p_state: int, p_cost: int, p_chosen: bool) -> void:
		skill = p_skill
		state = p_state
		cost = p_cost
		chosen = p_chosen
		_name.text = skill.display_name if skill != null else ""
		_name.label_settings.font_color = SkillsTab.name_color(state)
		_cost.text = str(cost) if cost >= 0 and _glyph() != &"" else ""
		_cost.label_settings.font_color = SkillsTab.glyph_color(state)
		_layout()
		queue_redraw()

	func _glyph() -> StringName:
		if skill == null:
			return &""
		match state:
			SkillsTab.State.LEARNABLE:
				return &"plus"
			SkillsTab.State.LOCKED:
				return &"lock"
		return &""

	func _glyph_px() -> float:
		return COMPACT_GLYPH_PX if compact else GLYPH_PX

	## The plate's inner left edge at height `y` (the slant leans it right towards the top).
	func _left_at(y: float) -> float:
		return HudStyle.SLANT * (size.y * 0.5 - y) + PAD

	func _layout() -> void:
		var glyph_room := 0.0
		if _glyph() != &"":
			glyph_room = _glyph_px() + GLYPH_GAP + (COST_WIDTH if not _cost.text.is_empty() else 0.0)
		var name_h := size.y * 0.6
		var left := _left_at(name_h * 0.5)
		_name.position = Vector2(left, 2.0)
		_name.size = Vector2(maxf(0.0, size.x - left - PAD - glyph_room), name_h)
		_cost.position = Vector2(size.x - PAD - _glyph_px() - GLYPH_GAP - COST_WIDTH, 0.0)
		_cost.size = Vector2(COST_WIDTH, size.y)

	func _draw() -> void:
		if skill == null:
			_draw_empty()
			return
		draw_style_box(SkillsTab.plate(state, chosen, size.y), Rect2(Vector2.ZERO, size))
		_draw_pips()
		var glyph := _glyph()
		if glyph != &"":
			var g := _glyph_px()
			UiGlyph.draw_glyph(self, glyph, Vector2(size.x - PAD - g * 0.5, size.y * 0.5), g, SkillsTab.glyph_color(state))

	## An empty socket: a dashed slanted outline, the plate's shape.
	func _draw_empty() -> void:
		var s := HudStyle.SLANT * size.y * 0.5
		var corners := [Vector2(s, 0.0), Vector2(size.x + s, 0.0), Vector2(size.x - s, size.y), Vector2(-s, size.y)]
		for i: int in corners.size():
			draw_dashed_line(corners[i], corners[(i + 1) % corners.size()], EMPTY_EDGE, 2.0, DASH, true, true)

	## The AP cost as blue pips along the bottom (a hollow ring for a free skill).
	func _draw_pips() -> void:
		var r := COMPACT_PIP_RADIUS if compact else PIP_RADIUS
		var y := size.y - r - (8.0 if compact else 12.0)
		var x := _left_at(y) + r
		var col := HudStyle.AP_TEXT if state != SkillsTab.State.LOCKED else Color(HudStyle.AP_TEXT, 0.4)
		if skill.ap_cost <= 0:
			draw_arc(Vector2(x, y), r, 0.0, TAU, 16, col, 1.5, true)
			return
		for i: int in mini(skill.ap_cost, MAX_PIPS):
			var at := Vector2(x + float(i) * r * PIP_STEP, y)
			draw_circle(at, r, col)
			draw_arc(at, r, 0.0, TAU, 16, HudStyle.OUTLINE_COLOR, 1.5, true)
