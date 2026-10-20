class_name RunEndScreen
extends CanvasLayer
## The end of a run (DESIGN.md 8): cleared or over, how far the party got, each hero's defence,
## what it keeps (8.17, 8.19), then Again (the players screen with the same seats, bag and oath,
## card #284) or the main menu.

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
var _age: float = 0.0
## Presses this soon after the screen appears are ignored, so a late press never skips it.
var _guard_s: float = 0.0


## `input_guard_ms`: combat_visuals.tres end_input_guard_ms, like the fight's end screen.
## `unlocked_oath`: the oath this win opened on this machine (0: none), see DESIGN.md 8.15.
## `recap_lines`: how the last fight went (FightRecap.lines), shown on a defeat; empty: none.
## `keep_line`: what this machine keeps (an online friend's own, card #281); empty: the run's.
## `players`: the player number of each hero in co-op (empty: one player), for the defence rows.
func setup(run: RunState, input_guard_ms: int, unlocked_oath: int = 0, recap_lines: Array[String] = [],
		keep_line: String = "", players: Array[int] = []) -> void:
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
	column.add_child(ListMenu.centred_label(summary(run), TEXT_SIZE))
	column.add_child(_defence_rows(run, players))
	# What the run found stays, won or lost (DESIGN.md 8.17, 8.19).
	column.add_child(ListMenu.centred_label(keep_line if not keep_line.is_empty() else run.relic_gain_line(),
			RECAP_SIZE, HudStyle.GOLD))
	for line: String in recap_lines:
		column.add_child(ListMenu.centred_label(line, RECAP_SIZE))
	if unlocked_oath > 0:
		column.add_child(ListMenu.centred_title("Oath %d unlocked" % unlocked_oath, OATH_SIZE, HudStyle.GOLD))
	ListMenu.screen_footer(self, [[&"menu_confirm", "Again"], [&"menu_cancel", "Main menu"]])


## "Act 2 of 2   Stops 11   Fights won 14   Levels 7 / 6 / 7   Gold earned 540".
static func summary(run: RunState) -> String:
	var levels := PackedStringArray()
	for lv: int in run.levels:
		levels.append(str(lv))
	return "Act  %d of %d      Stops  %d      Fights won  %d      Level%s  %s      Gold earned  %d" % [run.act + 1,
			run.acts().size(), run.visited, run.fights_won, "s" if levels.size() > 1 else "", " / ".join(levels),
			run.gold_earned]


## Each hero's defence this run as icons (card #283): parries, dodges, jumps and hits taken, a star
## on the best defender; in co-op each row says whose hero it is.
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
		for part: Array in [[&"shield", 0, HudStyle.TEXT], [&"chevrons", 1, HudStyle.TEXT], [&"up", 2, HudStyle.TEXT],
				[&"sword", 3, HudStyle.HP_LOW]]:
			row.add_child(UiGlyph.make(part[0], DEFENCE_GLYPH_PX, part[2]))
			row.add_child(HudStyle.make_number(str(int(counts[int(part[1])])), DEFENCE_SIZE, part[2]))
		var star := UiGlyph.make(&"star", DEFENCE_GLYPH_PX + 8.0, HudStyle.GOLD)
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
