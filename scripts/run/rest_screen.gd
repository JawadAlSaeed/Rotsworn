class_name RestScreen
extends CanvasLayer
## A rest stop (DESIGN.md 8): rest once (everyone heals tuning.run_rest_heal_percent of their max
## HP), then go back to the map.

signal done

const TITLE_SIZE: int = 72
const TEXT_SIZE: int = 30
const DETAIL_SIZE: int = 26

var _run: RunState
var _menu: ListMenu
var _bar: RunPartyBar
var _text: Label
var _rested: bool = false


func setup(run: RunState) -> void:
	_run = run
	var column := ListMenu.screen_column(self, "Rest", TITLE_SIZE)
	_text = ListMenu.centred_label("A quiet fire away from the rot. Rest heals everyone %d%% of their max HP." %
			run.tuning.run_rest_heal_percent, TEXT_SIZE)
	column.add_child(_text)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(centre)
	_bar = RunPartyBar.new()
	centre.add_child(_bar)
	_bar.setup(run)
	_menu = ListMenu.new()
	column.add_child(_menu)
	var items: Array[Dictionary] = [{"text": "Rest"}]
	_menu.set_items(items)


## Rests (once) and offers to go on. The bot calls this; the player uses confirm.
func rest_now() -> void:
	if _rested:
		return
	_rested = true
	var healed := _run.rest()
	var parts := PackedStringArray()
	for slot: int in healed.size():
		parts.append("%s +%d" % [_run.data.party[slot].display_name, healed[slot]])
	_text.text = "Rested.   " + "   ".join(parts)
	_bar.refresh(_run)
	Sfx.play("heal")
	var items: Array[Dictionary] = [{"text": "Back to the map"}]
	_menu.set_items(items)


func leave() -> void:
	done.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _menu.handle(event) != &"confirm":
		return
	Sfx.play("menu_confirm")
	if _rested:
		leave()
	else:
		rest_now()
