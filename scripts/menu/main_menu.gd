class_name MainMenu
extends CanvasLayer
## The main menu (DESIGN.md 7.5), after the title screen: the logo, then start a run, host or join
## an online run (DESIGN.md 9.2), practice (the fight and zone list), settings, credits, quit.
## Up/down picks, confirm opens it. No button bar here (card #130: the user found it clutter).

## One of ITEMS.
signal chosen(item: StringName)

const NEW_RUN := &"new_run"
const HOST_ONLINE := &"host_online"
const JOIN_ONLINE := &"join_online"
const PRACTICE := &"practice"
const SETTINGS := &"settings"
const CREDITS := &"credits"
const QUIT := &"quit"
const ITEMS: Array[StringName] = [NEW_RUN, HOST_ONLINE, JOIN_ONLINE, PRACTICE, SETTINGS, CREDITS, QUIT]
const SUBTITLE_SIZE: int = 30
const DETAIL_SIZE: int = 26

var _menu: ListMenu


## `start_item` is selected first (the last thing picked when coming back). `notice` says why
## the player is back here (an online game ended), if anything.
func setup(branding: BrandingData, start_item: StringName = NEW_RUN, notice: String = "") -> void:
	var column := ListMenu.screen_column(self, "")
	# The same living logo as the title screen: the ribbon sways, the letters' edges flicker.
	var logo := AnimatedLogo.new()
	logo.setup(branding)
	logo.custom_minimum_size = Vector2(0.0, float(branding.menu_logo_height_px))
	column.add_child(logo)
	if not branding.tagline.is_empty():
		column.add_child(ListMenu.centred_label(branding.tagline, SUBTITLE_SIZE, HudStyle.TEXT_DIM))
	if not notice.is_empty():
		column.add_child(ListMenu.centred_label(notice, DETAIL_SIZE, HudStyle.LATE))
	column.add_child(Control.new())
	_menu = ListMenu.new()
	column.add_child(_menu)
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	var items: Array[Dictionary] = [
		{"text": "New Run", "detail": "About 8 stops: zones, shops and rests, then the final fight."},
		{"text": "Host Online", "detail": "Start a run friends can join from their own PCs."},
		{"text": "Join Online", "detail": "Join a friend's run: type the address their screen shows."},
		{"text": "Practice", "detail": "Any fight or zone on its own, at full HP."},
		{"text": "Settings", "detail": "Graphics, sound, controls and lag calibration."},
		{"text": "Credits", "detail": "Who made the game, and whose music and sounds it uses."},
		{"text": "Quit", "detail": ""},
	]
	_menu.index = maxi(0, ITEMS.find(start_item))
	_menu.set_items(items, detail)


func _unhandled_input(event: InputEvent) -> void:
	if _menu.handle(event) == &"confirm":
		Sfx.play("menu_confirm")
		chosen.emit(ITEMS[_menu.index])
