class_name RunEndScreen
extends CanvasLayer
## The end of a run (DESIGN.md 8): cleared or over, how far the party got, each hero's defence,
## what it keeps (8.17, 8.24), then Again (the players screen with the same seats, bag and oath,
## card #284) or the main menu.
## Phase 22: icons, not lines of text. One row of stat chips (the flag and the stops, a sword and
## the fights won, the coin and the gold, each hero's face with their level), each hero's defence
## row (card #283), the Relics kept as their icons tagged New, and on a defeat the killer's
## portrait with the attack's name and its hit icons.
## A Fight Rush ends here too (setup_rush, DESIGN.md 8.21): RUSH OVER, the fight reached and the
## record, no Kept row.

## Back to the main menu.
signal done
## Again: another run with the same players.
signal again

const TITLE_SIZE: int = 96
const TEXT_SIZE: int = 32
const OATH_SIZE: int = 44
const RECAP_SIZE: int = 28
const DEFENCE_SIZE: int = 30
const DEFENCE_FACE_PX: float = 56.0
const DEFENCE_GLYPH_PX: float = 30.0
## The stat chips' pictures and the heroes' faces in that row.
const STAT_ICON_PX: float = 48.0
const STAT_FACE_PX: float = 56.0
const ROW_GAP: int = 22
## A Rush record's day sits this close after its Best chip.
const RUSH_DETAIL_GAP: int = 10
## The Relics kept: their icons and the tag under each.
const KEPT_ICON_PX: float = 64.0
const KEPT_TAG_SIZE: int = 24
## At most this many kept Relics side by side; the rest are counted ("+3").
const KEPT_MAX: int = 8
## The kept Relics' row wraps at this width.
const KEPT_ROW_WIDTH: float = 1500.0
## The killer's portrait and its attack's hit icons on a defeat.
const KILLER_FACE_PX: float = 96.0
const KILLER_HIT_PX: float = 36.0
const MAP_VISUALS_PATH := "res://data/presentation/map_visuals.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"

var _age: float = 0.0
## Presses this soon after the screen appears are ignored, so a late press never skips it.
var _guard_s: float = 0.0


## `input_guard_ms`: combat_visuals.tres end_input_guard_ms, like the fight's end screen.
## `unlocked_oath`: the oath this win opened on this machine (0: none), see DESIGN.md 8.15.
## `recap_lines`: how the last fight went (FightRecap.lines), shown on a defeat only when no `recap`
## is given (empty: none).
## `keep_line`: what this machine keeps (an online friend's own, card #281); shown as words only when
## no `own_start` is given; empty: the run's (as icons).
## `players`: the player number of each hero in co-op (empty: one player), for the defence rows.
## `recap`: the last fight (FightRecap.to_dict) on a defeat: the killer's row; empty: none.
## `own_start`: an online friend's own collection at the start (card #281): what they keep is
## measured from it; null: the run's own start.
## `own_since`: {relics} when the friend joined mid-run (card #304): only later finds are
## theirs; empty: from the start.
func setup(run: RunState, input_guard_ms: int, unlocked_oath: int = 0, recap_lines: Array[String] = [],
		keep_line: String = "", players: Array[int] = [], recap: Dictionary = {},
		own_start: RelicCollection = null, own_since: Dictionary = {}) -> void:
	_guard_s = float(input_guard_ms) / 1000.0
	var won := run.result == RunState.VICTORY
	Sfx.play("run_cleared" if won else "run_over")
	var column := ListMenu.screen_column(self, "RUN CLEARED" if won else "RUN OVER", TITLE_SIZE)
	if not won:
		(column.get_child(0) as Label).label_settings.font_color = HudStyle.LATE
	if run.oath > 0:
		var kept := ListMenu.centred_title("OATH %d %s" % [run.oath, "KEPT" if won else "BROKEN"], OATH_SIZE,
				HudStyle.GOLD if won else HudStyle.LATE)
		column.add_child(kept)
	column.add_child(_stat_row(run))
	if not won:
		var killer := killer_of(recap)
		if not killer.is_empty():
			column.add_child(_killer_row(killer))
		else:
			for line: String in recap_lines:
				column.add_child(ListMenu.centred_label(line, RECAP_SIZE))
	column.add_child(_defence_rows(run, players))
	# What the run found stays, won or lost (DESIGN.md 8.17, 8.19).
	if own_start != null:
		column.add_child(_kept_row(own_kept(run, own_start, own_since)))
	elif not keep_line.is_empty():
		column.add_child(ListMenu.centred_label(keep_line, RECAP_SIZE, HudStyle.GOLD))
	else:
		column.add_child(_kept_row(kept_relics(run, run.relics_at_start)))
	if unlocked_oath > 0:
		column.add_child(ListMenu.centred_title("Oath %d unlocked" % unlocked_oath, OATH_SIZE, HudStyle.GOLD))
	ListMenu.screen_footer(self, [[&"menu_confirm", "Again"], [&"menu_cancel", "Main menu"]])


## The end of a Fight Rush (DESIGN.md 8.21): RUSH OVER, NEW RECORD when this Rush beat its party
## size's record, the fight reached, the record with its day, the party size and the heroes' levels,
## the killer after a loss (not after Give up) and each hero's defence. Nothing from a Rush is kept,
## so there is no Kept row. Again opens the Fight Rush players screen.
## `best`: the party size's record after this Rush (RushRecords.entry; {} leaves the Best chip out).
## `players` and `recap` as in setup.
func setup_rush(run: RushState, input_guard_ms: int, best: Dictionary, new_record: bool, players: Array[int],
		recap: Dictionary) -> void:
	_guard_s = float(input_guard_ms) / 1000.0
	Sfx.play("run_over")
	var column := ListMenu.screen_column(self, "RUSH OVER", TITLE_SIZE)
	(column.get_child(0) as Label).label_settings.font_color = HudStyle.LATE
	if new_record:
		column.add_child(ListMenu.centred_title("NEW RECORD", OATH_SIZE, HudStyle.GOLD))
	column.add_child(_rush_stat_row(run, best))
	if run.result == RunState.DEFEAT:
		var killer := killer_of(recap)
		if not killer.is_empty():
			column.add_child(_killer_row(killer))
	column.add_child(_defence_rows(run, players))
	ListMenu.screen_footer(self, [[&"menu_confirm", "Again"], [&"menu_cancel", "Main menu"]])


## The Rush's stat chips: [{icon, text, color, detail}] for the fight reached (a sword; left out when
## the Rush was given up before its first fight), the record (a star; `detail` is its day, drawn dim
## after it; left out when `best` is not an entry) and the party size the record counts for (a
## person: Solo, Duo, Trio).
static func rush_chips(run: RushState, best: Dictionary) -> Array[Dictionary]:
	var chips: Array[Dictionary] = []
	if not run.reached_text().is_empty():
		chips.append({"icon": &"sword", "text": run.reached_text(), "color": HudStyle.TEXT})
	if RushRecords.is_valid(best):
		chips.append({"icon": &"star", "text": "Best %d" % int(best.fight), "color": HudStyle.GOLD,
				"detail": String(best.date)})
	chips.append({"icon": &"person", "text": RushRecords.label(run.most_players), "color": HudStyle.TEXT})
	return chips


func _rush_stat_row(run: RushState, best: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", ROW_GAP)
	for chip: Dictionary in rush_chips(run, best):
		var chip_row := MapScreen.icon_chip(chip.icon, String(chip.text), chip.color as Color, STAT_ICON_PX, TEXT_SIZE)
		var detail := String(chip.get("detail", ""))
		if detail.is_empty():
			row.add_child(chip_row)
			continue
		# The record's day sits right after its chip, dim, so the two read as one.
		var pair := HBoxContainer.new()
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_theme_constant_override("separation", RUSH_DETAIL_GAP)
		pair.add_child(chip_row)
		var day := HudStyle.make_label(detail, RECAP_SIZE, HudStyle.TEXT_DIM)
		day.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		day.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pair.add_child(day)
		row.add_child(pair)
	_add_hero_levels(row, run)
	return row


## The stat chips: [{icon, text, color}] for the act reached (its boss's lair, "1/2"), the stops
## (the map's flag), the fights won (a sword) and the gold earned (the coin). The heroes' faces and
## levels follow them in the row.
static func stat_chips(run: RunState, look: MapVisuals, gold_icon: String) -> Array[Dictionary]:
	var acts := maxi(1, run.data.acts.size())
	var act := run.act_data()
	var lair: Variant = act.final_map_icon_path if act != null and not act.final_map_icon_path.is_empty() else &"skull"
	# Each icon with its word (owner 2026-10-20: icons alone meant nothing to a new player).
	return [{"icon": lair, "text": "Act %d/%d" % [mini(run.act + 1, acts), acts], "color": HudStyle.TEXT},
			{"icon": look.flag_path, "text": "Stops %d" % run.visited, "color": HudStyle.TEXT},
			{"icon": &"sword", "text": "Wins %d" % run.fights_won, "color": HudStyle.TEXT},
			{"icon": gold_icon, "text": "Gold %d" % run.gold_earned, "color": HudStyle.GOLD}]


func _stat_row(run: RunState) -> Control:
	var look := load(MAP_VISUALS_PATH) as MapVisuals
	if look == null:
		look = MapVisuals.new()
	var visuals := load(VISUALS_PATH) as CombatVisuals
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", ROW_GAP)
	for chip: Dictionary in stat_chips(run, look, visuals.gold_icon_path if visuals != null else ""):
		row.add_child(MapScreen.icon_chip(chip.icon, String(chip.text), chip.color as Color, STAT_ICON_PX, TEXT_SIZE))
	_add_hero_levels(row, run)
	return row


## Each hero's face and level, at the end of the stat row.
static func _add_hero_levels(row: HBoxContainer, run: RunState) -> void:
	for slot: int in mini(run.party_size(), run.levels.size()):
		var c := run.data.party[slot]
		var hero := HBoxContainer.new()
		hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hero.add_theme_constant_override("separation", 8)
		hero.add_child(HudStyle.portrait_frame(AssetLoader.texture(c.portrait_path, Vector2i(48, 48)), c.color, STAT_FACE_PX))
		var level := HudStyle.make_number("Lv %d" % run.levels[slot], TEXT_SIZE, c.color.lightened(0.25))
		level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		level.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hero.add_child(level)
		row.add_child(hero)


## The Relics a run keeps, measured from `found_before` (id -> any): [{item, new}] for each Relic
## found for the first time, in the run's Relic order. The same rule as
## RunState.relic_gain_line_since (a late joiner's end screen shows this row, own_kept, never words).
static func kept_relics(run: RunState, found_before: Dictionary) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for item: GearData in run.data.gear:
		if item != null and run.owns(item) and not found_before.has(item.id):
			kept.append({"item": item, "new": true})
	return kept


## What an online friend keeps (card #281), measured from their own collection at the start.
## `own_since` {relics}: the run's Relics when they joined mid-run (card #304), so only later finds
## count; empty: from the start. A Relic the run had before they joined is never New.
static func own_kept(run: RunState, own_start: RelicCollection, own_since: Dictionary = {}) -> Array[Dictionary]:
	var found := own_start.found.duplicate()
	found.merge(own_since.get("relics", {}) as Dictionary)
	return kept_relics(run, found)


## The Relics kept: a "Kept" word, then each Relic's icon with its name, tagged New; an empty row
## when none (no "Nothing new" words, owner 2026-10-20).
func _kept_row(kept: Array[Dictionary]) -> Control:
	# Named Relics take room: the row wraps onto more lines instead of running off the screen.
	var row := HFlowContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.custom_minimum_size.x = KEPT_ROW_WIDTH
	row.add_theme_constant_override("h_separation", ROW_GAP)
	row.add_theme_constant_override("v_separation", ROW_GAP)
	if kept.is_empty():
		row.visible = false
		return row
	var head := HudStyle.make_title("Kept", TEXT_SIZE, HudStyle.GOLD)
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(head)
	for entry: Dictionary in kept.slice(0, KEPT_MAX):
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 2)
		var icon := RelicIcon.make(entry.item as GearData, KEPT_ICON_PX)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
		var name := HudStyle.make_label((entry.item as GearData).display_name, KEPT_TAG_SIZE)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(name)
		var tags := HBoxContainer.new()
		tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tags.alignment = BoxContainer.ALIGNMENT_CENTER
		tags.add_theme_constant_override("separation", 6)
		if bool(entry.new):
			tags.add_child(MapScreen.icon_chip(null, "New", HudStyle.GOLD, 0.0, KEPT_TAG_SIZE, false))
		box.add_child(tags)
		row.add_child(box)
	if kept.size() > KEPT_MAX:
		row.add_child(MapScreen.icon_chip(null, "+%d" % (kept.size() - KEPT_MAX), HudStyle.GOLD, 0.0, TEXT_SIZE, false))
	return row


## Who finished the run, from the last fight's recap (FightRecap.to_dict): {enemy (EnemyData or null),
## source (its name), attack (the attack's name), attack_data (EnemyAttackData or null), amount}.
## The last blow, else the hardest hit; empty when the recap has neither. Two of the same enemy in a
## fight are lettered ("Rotten Husk B", CombatEngine), so the name without its letter finds it too.
static func killer_of(recap: Dictionary) -> Dictionary:
	var blow: Dictionary = recap.get("last_blow", {})
	if blow.is_empty():
		blow = recap.get("top_attack", {})
	if blow.is_empty():
		return {}
	var source := String(blow.get("source", ""))
	var attack := String(blow.get("name", ""))
	var base := source
	var letter := source.right(1)
	if source.length() > 2 and source[source.length() - 2] == " " and letter >= "A" and letter <= "Z":
		base = source.left(source.length() - 2)
	var enemy: EnemyData = null
	for data: EnemyData in JournalScreen.load_enemies():
		if data.display_name == source:
			enemy = data
			break
		if enemy == null and data.display_name == base:
			enemy = data
	var attack_data: EnemyAttackData = null
	if enemy != null:
		for a: EnemyAttackData in enemy.all_attacks():
			if a.display_name == attack:
				attack_data = a
	return {"enemy": enemy, "source": source, "attack": attack, "attack_data": attack_data,
			"amount": int(blow.get("amount", 0))}


## The hit icons of an attack, each kind once in the order its hits come (a thrown normal hit shows
## the ranged icon, card #278): texture paths from combat_visuals.tres.
static func hit_icon_paths(attack: EnemyAttackData, visuals: CombatVisuals) -> Array[String]:
	var paths: Array[String] = []
	if attack == null or visuals == null:
		return paths
	for hit: AttackHitData in attack.hits:
		if hit == null:
			continue
		var path := visuals.hit_icon_normal_path
		match hit.kind:
			AttackHitData.Kind.GROUND:
				path = visuals.hit_icon_ground_path
			AttackHitData.Kind.REND:
				path = visuals.hit_icon_rend_path
			AttackHitData.Kind.SWEEP:
				path = visuals.hit_icon_sweep_path
			_:
				if hit.projectile != null:
					path = visuals.hit_icon_ranged_path
		if not paths.has(path):
			paths.append(path)
	return paths


## The killer: its portrait, the attack's name and its hit icons (or the mark that wore the hero
## down), and the damage it dealt.
func _killer_row(killer: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", ROW_GAP)
	var enemy := killer.get("enemy") as EnemyData
	if enemy != null:
		row.add_child(HudStyle.portrait_frame(AssetLoader.texture(enemy.portrait_path), enemy.color, KILLER_FACE_PX))
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 4)
	row.add_child(words)
	words.add_child(HudStyle.make_label("Killed by", RECAP_SIZE, HudStyle.TEXT_DIM))
	var source := String(killer.get("source", ""))
	if not source.is_empty():
		words.add_child(HudStyle.make_title(source, TEXT_SIZE, enemy.color.lightened(0.25) if enemy != null else HudStyle.TEXT))
	var attack_line := HBoxContainer.new()
	attack_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	attack_line.add_theme_constant_override("separation", 10)
	words.add_child(attack_line)
	attack_line.add_child(HudStyle.make_label(String(killer.get("attack", "")), RECAP_SIZE, HudStyle.GOLD))
	var visuals := load(VISUALS_PATH) as CombatVisuals
	var icons := hit_icon_paths(killer.get("attack_data") as EnemyAttackData, visuals)
	if icons.is_empty():
		# A mark that wore the hero down ("Rotting") shows its own icon.
		var mark := HudStyle.mark_icon(String(killer.get("attack", "")).to_lower())
		if mark != null:
			attack_line.add_child(MapScreen.icon_picture(mark, KILLER_HIT_PX))
	for path: String in icons:
		attack_line.add_child(MapScreen.icon_picture(path, KILLER_HIT_PX))
	var amount := int(killer.get("amount", 0))
	if amount > 0:
		row.add_child(MapScreen.icon_chip(&"sword", "%d damage" % amount, HudStyle.DAMAGE_TAKEN, STAT_ICON_PX, TEXT_SIZE))
	return row


## Each hero's defence this run (card #283): each count as its icon and word ("Parry 3", "Dodge 0",
## "Jump 0", "Hit 4"), a star with "Best" on the best defender; in co-op each row says whose hero.
static func _defence_rows(run: RunState, players: Array[int]) -> Control:
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 6)
	var best := run.best_defender()
	for slot: int in mini(run.party_size(), run.defence.size()):
		var c := run.data.party[slot]
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		rows.add_child(row)
		row.add_child(HudStyle.portrait_frame(AssetLoader.texture(c.portrait_path, Vector2i(48, 48)), c.color, DEFENCE_FACE_PX))
		if slot < players.size():
			row.add_child(HudStyle.make_number("P%d" % players[slot], DEFENCE_SIZE, c.color.lightened(0.25)))
		var counts: Array = run.defence[slot]
		for part: Array in [[&"shield", 0, HudStyle.TEXT, "Parry"], [&"chevrons", 1, HudStyle.TEXT, "Dodge"],
				[&"up", 2, HudStyle.TEXT, "Jump"], [&"sword", 3, HudStyle.HP_LOW, "Hit"]]:
			row.add_child(UiGlyph.make(part[0], DEFENCE_GLYPH_PX, part[2]))
			row.add_child(HudStyle.make_number("%s %d" % [part[3], int(counts[int(part[1])])], DEFENCE_SIZE, part[2]))
		var star := MapScreen.icon_chip(&"star", "Best", HudStyle.GOLD, DEFENCE_GLYPH_PX + 8.0, DEFENCE_SIZE, false)
		star.modulate.a = 1.0 if slot == best else 0.0
		row.add_child(star)
	return rows


func _process(delta: float) -> void:
	_age += delta


func _unhandled_input(event: InputEvent) -> void:
	if _age < _guard_s:
		return
	var answer := MenuMouse.answer_for_button((event as InputEventMouseButton).button_index) \
			if MenuMouse.is_press(event) else &""
	if event.is_action_pressed(&"menu_confirm", false, true) or answer == &"confirm":
		get_viewport().set_input_as_handled()
		Sfx.play("menu_confirm")
		again.emit()
	elif event.is_action_pressed(&"menu_cancel", false, true) or answer == &"cancel":
		get_viewport().set_input_as_handled()
		Sfx.play("menu_cancel")
		done.emit()
