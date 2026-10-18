class_name RunEndScreen
extends CanvasLayer
## The end of a run (DESIGN.md 8): cleared or over, how far the party got, the Relics it keeps
## (8.17), then the main menu.

signal done

const TITLE_SIZE: int = 96
const TEXT_SIZE: int = 32
const OATH_SIZE: int = 44
const RECAP_SIZE: int = 28
var _age: float = 0.0
## Presses this soon after the screen appears are ignored, so a late press never skips it.
var _guard_s: float = 0.0


## `input_guard_ms`: combat_visuals.tres end_input_guard_ms, like the fight's end screen.
## `unlocked_oath`: the oath this win opened on this machine (0: none), see DESIGN.md 8.15.
## `recap_lines`: how the last fight went (FightRecap.lines), shown on a defeat; empty: none.
func setup(run: RunState, input_guard_ms: int, unlocked_oath: int = 0, recap_lines: Array[String] = []) -> void:
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
	# What the run found stays, won or lost (DESIGN.md 8.17).
	column.add_child(ListMenu.centred_label(run.relic_gain_line(), RECAP_SIZE, HudStyle.GOLD))
	for line: String in recap_lines:
		column.add_child(ListMenu.centred_label(line, RECAP_SIZE))
	if unlocked_oath > 0:
		column.add_child(ListMenu.centred_title("Oath %d unlocked" % unlocked_oath, OATH_SIZE, HudStyle.GOLD))
	ListMenu.screen_footer(self, [[&"menu_confirm", "Main menu"]])


## "Act 2 of 2   Stops 11   Fights won 14   Levels 7 / 6 / 7   Gold earned 540".
static func summary(run: RunState) -> String:
	var levels := PackedStringArray()
	for lv: int in run.levels:
		levels.append(str(lv))
	return "Act  %d of %d      Stops  %d      Fights won  %d      Level%s  %s      Gold earned  %d" % [run.act + 1,
			run.acts().size(), run.visited, run.fights_won, "s" if levels.size() > 1 else "", " / ".join(levels),
			run.gold_earned]


func _process(delta: float) -> void:
	_age += delta


func _unhandled_input(event: InputEvent) -> void:
	if _age < _guard_s:
		return
	if event.is_action_pressed(&"menu_confirm", false, true) or event.is_action_pressed(&"menu_cancel", false, true):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_confirm")
		done.emit()
