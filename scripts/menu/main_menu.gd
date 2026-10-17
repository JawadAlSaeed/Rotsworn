class_name MainMenu
extends CanvasLayer
## The main menu (DESIGN.md 7.5), after the title screen: the logo, then Continue (only when a run
## is saved, DESIGN.md 8.14), start a run, play online (DESIGN.md 9.2), Extras, settings, quit.
## Up/down picks, confirm opens it. No button bar here (card #130: the user found it clutter). Kept
## short (cards #150 and #208): Online and Extras open a second list in place (Host / Join; the
## tutorial, the Rot Journal (7.11), credits), cancel or Back goes back. Practice (any fight or zone
## on its own) is a test tool: its row shows in Extras only in debug builds.

## One of ITEMS (not the rows that open a list), or a row of a second list.
signal chosen(item: StringName)

const CONTINUE := &"continue"
const NEW_RUN := &"new_run"
const ONLINE := &"online"
const HOST_ONLINE := &"host_online"
const JOIN_ONLINE := &"join_online"
const EXTRAS := &"extras"
const TUTORIAL := &"tutorial"
const PRACTICE := &"practice"
const JOURNAL := &"journal"
const SETTINGS := &"settings"
const CREDITS := &"credits"
const QUIT := &"quit"
const ITEMS: Array[StringName] = [NEW_RUN, ONLINE, EXTRAS, SETTINGS, QUIT]
## The Online list; Back follows it.
const ONLINE_ITEMS: Array[StringName] = [HOST_ONLINE, JOIN_ONLINE]
## The Extras list for players (user 2026-10-17: the menu felt cluttered); Back follows it.
const EXTRAS_ITEMS: Array[StringName] = [TUTORIAL, JOURNAL, CREDITS]
const LABELS: Dictionary = {
	CONTINUE: "Continue", NEW_RUN: "New Run", ONLINE: "Online", EXTRAS: "Extras", SETTINGS: "Settings",
	QUIT: "Quit", HOST_ONLINE: "Host Online", JOIN_ONLINE: "Join Online", TUTORIAL: "Tutorial",
	PRACTICE: "Practice", JOURNAL: "Journal", CREDITS: "Credits",
}
const SUBTITLE_SIZE: int = 30
const DETAIL_SIZE: int = 26
## Room between the logo and the list (pixels, on top of the column's spacing).
const LOGO_GAP: float = 28.0

var _menu: ListMenu
## The main row whose second list is showing (ONLINE or EXTRAS), or empty for the main list.
var _sub: StringName = &""
## The main list's rows in order (Continue is first when a run is saved).
var _items: Array[StringName] = []
## The Extras list's rows (Practice after the tutorial in debug builds).
var _extras: Array[StringName] = []


## `start_item` is selected first (the last thing picked when coming back: a row of Extras reopens
## that list). `notice` says why the player is back here (an online game ended), if anything.
## `can_continue` adds the Continue row; `show_practice` adds Practice to Extras (debug builds).
func setup(branding: BrandingData, start_item: StringName = NEW_RUN, notice: String = "",
		can_continue: bool = false, show_practice: bool = false) -> void:
	_items = ITEMS.duplicate()
	if can_continue:
		_items.push_front(CONTINUE)
	_extras = EXTRAS_ITEMS.duplicate()
	if show_practice:
		_extras.insert(1, PRACTICE)
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
	# No description line under the list (user, 2026-10-17): the rows speak for themselves.
	if _extras.has(start_item):
		_show_sub(EXTRAS, start_item)
	else:
		# Coming back from hosting or joining: the cursor rests on Online.
		_show_main(ONLINE if ONLINE_ITEMS.has(start_item) else start_item)


func _show_main(item: StringName) -> void:
	_sub = &""
	_menu.index = maxi(0, _items.find(item))
	_menu.set_items(_rows(_items))


## A second list in place of the main one, with Back last.
func _show_sub(parent: StringName, item: StringName = &"") -> void:
	_sub = parent
	var list := _sub_items()
	var rows := _rows(list)
	rows.append({"text": "Back"})
	_menu.index = maxi(0, list.find(item))
	_menu.set_items(rows)


func _sub_items() -> Array[StringName]:
	return ONLINE_ITEMS if _sub == ONLINE else _extras


static func _rows(ids: Array[StringName]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: StringName in ids:
		rows.append({"text": String(LABELS[id])})
	return rows


func _unhandled_input(event: InputEvent) -> void:
	match _menu.handle(event):
		&"confirm":
			if _sub.is_empty():
				var item := _items[_menu.index]
				Sfx.play("menu_confirm")
				if item == ONLINE or item == EXTRAS:
					_show_sub(item)
				else:
					chosen.emit(item)
				return
			var list := _sub_items()
			if _menu.index < list.size():
				Sfx.play("menu_confirm")
				chosen.emit(list[_menu.index])
			else:
				Sfx.play("menu_cancel")
				_show_main(_sub)
		&"cancel":
			if not _sub.is_empty():
				Sfx.play("menu_cancel")
				_show_main(_sub)
