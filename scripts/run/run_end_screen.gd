class_name RunEndScreen
extends CanvasLayer
## The end of a run (DESIGN.md 8): cleared or over, how far the party got, then the main menu.

signal done

const TITLE_SIZE: int = 96
const TEXT_SIZE: int = 32
const HINT_SIZE: int = 26
var _age: float = 0.0
## Presses this soon after the screen appears are ignored, so a late press never skips it.
var _guard_s: float = 0.0


## `input_guard_ms`: combat_visuals.tres end_input_guard_ms, like the fight's end screen.
func setup(run: RunState, input_guard_ms: int) -> void:
	_guard_s = float(input_guard_ms) / 1000.0
	var won := run.result == RunState.VICTORY
	var column := ListMenu.screen_column(self, "RUN CLEARED" if won else "RUN OVER", TITLE_SIZE)
	if not won:
		(column.get_child(0) as Label).label_settings.font_color = HudStyle.LATE
	column.add_child(ListMenu.centred_label(summary(run), TEXT_SIZE))
	column.add_child(ListMenu.centred_label("%s:  main menu" % HudStyle.binding_text(&"menu_confirm"), HINT_SIZE,
			HudStyle.TEXT_DIM))


## "Stops 5 of 8   Fights won 6   Gold earned 140".
static func summary(run: RunState) -> String:
	return "Stops reached  %d of %d      Fights won  %d      Gold earned  %d" % [run.path.size(),
			run.map.row_count(), run.fights_won, run.gold_earned]


func _process(delta: float) -> void:
	_age += delta


func _unhandled_input(event: InputEvent) -> void:
	if _age < _guard_s:
		return
	if event.is_action_pressed(&"menu_confirm", false, true) or event.is_action_pressed(&"menu_cancel", false, true):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_confirm")
		done.emit()
