class_name MainMenu
extends CanvasLayer
## The first screen (DESIGN.md 7.5): start a run, practice (the fight and zone list), settings,
## quit. Up/down picks, confirm opens it.

## One of NEW_RUN, PRACTICE, SETTINGS, QUIT.
signal chosen(item: StringName)

const NEW_RUN := &"new_run"
const PRACTICE := &"practice"
const SETTINGS := &"settings"
const QUIT := &"quit"
const ITEMS: Array[StringName] = [NEW_RUN, PRACTICE, SETTINGS, QUIT]
const TITLE_SIZE: int = 96
const SUBTITLE_SIZE: int = 30
const DETAIL_SIZE: int = 26
const HINT_SIZE: int = 24

var _menu: ListMenu


## `start_item` is selected first (the last thing picked when coming back).
func setup(start_item: StringName = NEW_RUN) -> void:
	var column := ListMenu.screen_column(self, "Rotten Lands", TITLE_SIZE)
	column.add_child(ListMenu.centred_label("a short run through the rot", SUBTITLE_SIZE, HudStyle.TEXT_DIM))
	column.add_child(Control.new())
	_menu = ListMenu.new()
	column.add_child(_menu)
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	column.add_child(ListMenu.centred_label("Up/Down choose   %s select" % HudStyle.binding_text(&"menu_confirm"),
			HINT_SIZE, HudStyle.TEXT_DIM))
	var items: Array[Dictionary] = [
		{"text": "New Run", "detail": "About 8 stops: zones, shops and rests, then the final fight."},
		{"text": "Practice", "detail": "Any fight or zone on its own, at full HP."},
		{"text": "Settings", "detail": "Volume, fullscreen, training ring, lag calibration, controls."},
		{"text": "Quit", "detail": ""},
	]
	_menu.index = maxi(0, ITEMS.find(start_item))
	_menu.set_items(items, detail)


func _unhandled_input(event: InputEvent) -> void:
	if _menu.handle(event) == &"confirm":
		Sfx.play("menu_confirm")
		chosen.emit(ITEMS[_menu.index])
