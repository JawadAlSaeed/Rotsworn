class_name MainMenu
extends CanvasLayer
## The main menu (DESIGN.md 7.5), after the title screen: the logo, then Continue (only when a run
## is saved, DESIGN.md 8.14), start a run, play online
## (DESIGN.md 9.2), practice (the tutorial, fights and zones), settings, credits, quit. Up/down
## picks, confirm opens it. No button bar here (card #130: the user found it clutter). Kept short
## (card #150): Online opens a second list in place, Host or Join (cancel goes back), and the
## tutorial is the first card in Practice.

## One of ITEMS, or HOST_ONLINE / JOIN_ONLINE from the Online list.
signal chosen(item: StringName)

const CONTINUE := &"continue"
const NEW_RUN := &"new_run"
const ONLINE := &"online"
const HOST_ONLINE := &"host_online"
const JOIN_ONLINE := &"join_online"
const PRACTICE := &"practice"
const SETTINGS := &"settings"
const CREDITS := &"credits"
const QUIT := &"quit"
const ITEMS: Array[StringName] = [NEW_RUN, ONLINE, PRACTICE, SETTINGS, CREDITS, QUIT]
const CONTINUE_DETAIL := "Pick the saved run up where you left it."
## The Online list; the last row goes back.
const ONLINE_ITEMS: Array[StringName] = [HOST_ONLINE, JOIN_ONLINE]
const SUBTITLE_SIZE: int = 30
const DETAIL_SIZE: int = 26
## Room between the logo and the list (pixels, on top of the column's spacing).
const LOGO_GAP: float = 28.0

var _menu: ListMenu
var _detail: Label
## The Online list is showing.
var _online: bool = false
## The main list's rows in order (Continue is first when a run is saved).
var _items: Array[StringName] = []


## `start_item` is selected first (the last thing picked when coming back). `notice` says why
## the player is back here (an online game ended), if anything. `can_continue` adds the Continue row.
func setup(branding: BrandingData, start_item: StringName = NEW_RUN, notice: String = "",
		can_continue: bool = false) -> void:
	_items = ITEMS.duplicate()
	if can_continue:
		_items.push_front(CONTINUE)
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
	var gap := Control.new()
	gap.custom_minimum_size.y = LOGO_GAP
	column.add_child(gap)
	_menu = ListMenu.new()
	column.add_child(_menu)
	_detail = ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_detail)
	# Coming back from hosting or joining: the cursor rests on Online.
	_show_main(ONLINE if ONLINE_ITEMS.has(start_item) else start_item)


func _show_main(item: StringName) -> void:
	_online = false
	var items: Array[Dictionary] = []
	var rows: Array[Dictionary] = [
		{"text": "Continue", "detail": CONTINUE_DETAIL},
		{"text": "New Run", "detail": "About 8 stops: zones, shops and rests, then the final fight."},
		{"text": "Online", "detail": "Host a run friends join from their own PCs, or join theirs."},
		{"text": "Practice", "detail": "The tutorial, and any fight or zone on its own at full HP."},
		{"text": "Settings", "detail": "Graphics, sound, controls and lag calibration."},
		{"text": "Credits", "detail": "Who made the game, and whose music and sounds it uses."},
		{"text": "Quit", "detail": ""},
	]
	# Continue is the first row; without a save it is left out.
	items.assign(rows if _items.has(CONTINUE) else rows.slice(1))
	_menu.index = maxi(0, _items.find(item))
	_menu.set_items(items, _detail)


func _show_online() -> void:
	_online = true
	var items: Array[Dictionary] = [
		{"text": "Host Online", "detail": "Start a run friends can join from their own PCs."},
		{"text": "Join Online", "detail": "Join a friend's run: type the address their screen shows."},
		{"text": "Back", "detail": ""},
	]
	_menu.index = 0
	_menu.set_items(items, _detail)


func _unhandled_input(event: InputEvent) -> void:
	match _menu.handle(event):
		&"confirm":
			if not _online:
				Sfx.play("menu_confirm")
				if _items[_menu.index] == ONLINE:
					_show_online()
				else:
					chosen.emit(_items[_menu.index])
			elif _menu.index < ONLINE_ITEMS.size():
				Sfx.play("menu_confirm")
				chosen.emit(ONLINE_ITEMS[_menu.index])
			else:
				Sfx.play("menu_cancel")
				_show_main(ONLINE)
		&"cancel":
			if _online:
				Sfx.play("menu_cancel")
				_show_main(ONLINE)
