class_name MainMenu
extends CanvasLayer
## The main menu (DESIGN.md 7.5), after the title screen: the logo, then Continue (only when a run
## is saved, DESIGN.md 8.14), start a run, play online (DESIGN.md 9.2), the Relics (8.17), Extras,
## settings, quit.
## Up/down picks, confirm opens it. No button bar here (card #130: the user found it clutter). Kept
## short (cards #150 and #208): Online and Extras open a second list in place (Host / Join; the
## tutorial, the Glossary (7.12), the Rot Journal (7.11), credits), cancel or Back goes back. Practice (any fight or zone
## on its own) is a test tool: its row shows in Extras only in debug builds. The version sits in the
## bottom-left corner and the studio's logo in the bottom-right.

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
const RELICS := &"relics"
const GLOSSARY := &"glossary"
const SETTINGS := &"settings"
const CREDITS := &"credits"
const QUIT := &"quit"
const ITEMS: Array[StringName] = [NEW_RUN, ONLINE, RELICS, EXTRAS, SETTINGS, QUIT]
## The Online list; Back follows it.
const ONLINE_ITEMS: Array[StringName] = [HOST_ONLINE, JOIN_ONLINE]
## The Extras list for players (user 2026-10-17: the menu felt cluttered); Back follows it.
const EXTRAS_ITEMS: Array[StringName] = [TUTORIAL, GLOSSARY, JOURNAL, CREDITS]
const LABELS: Dictionary = {
	CONTINUE: "Continue", NEW_RUN: "New Run", ONLINE: "Online", EXTRAS: "Extras", SETTINGS: "Settings",
	QUIT: "Quit", HOST_ONLINE: "Host Online", JOIN_ONLINE: "Join Online", TUTORIAL: "Tutorial",
	PRACTICE: "Practice", GLOSSARY: "Glossary", JOURNAL: "Journal", CREDITS: "Credits", RELICS: "Relics",
}
const SUBTITLE_SIZE: int = 30
const DETAIL_SIZE: int = 26
## How wide a notice (why the player is back here) may run before it wraps.
const NOTICE_WIDTH: float = 1100.0
## Room between the logo and the list (pixels, on top of the column's spacing; small since phase 17
## added the Relics row, so Quit keeps clear of the bottom edge with Continue shown).
const LOGO_GAP: float = 4.0

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
		# Wrapped in a centred block: a long notice ran off both sides of the screen (card #208).
		var note := ListMenu.centred_label(notice, DETAIL_SIZE, HudStyle.LATE)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = NOTICE_WIDTH
		note.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(note)
	var gap := Control.new()
	gap.custom_minimum_size.y = LOGO_GAP
	column.add_child(gap)
	_menu = ListMenu.new()
	column.add_child(_menu)
	# No description line under the list (user, 2026-10-17): the rows speak for themselves.
	_add_corners(branding)
	if _extras.has(start_item):
		_show_sub(EXTRAS, start_item)
	else:
		# Coming back from hosting or joining: the cursor rests on Online.
		_show_main(ONLINE if ONLINE_ITEMS.has(start_item) else start_item)


## The game's version (bottom left) and the studio's logo (bottom right), small and quiet, like
## most games' title menus (user, 2026-10-17, card #210).
func _add_corners(branding: BrandingData) -> void:
	var margin := branding.corner_margin_px
	var version := ListMenu.centred_label(version_text(), branding.version_size, HudStyle.TEXT_DIM)
	version.name = "Version"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	version.modulate.a = branding.corner_alpha
	add_child(version)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, margin)
	if branding.studio_logo_path.is_empty():
		return
	var logo := TextureRect.new()
	logo.name = "StudioLogo"
	logo.texture = AssetLoader.texture(branding.studio_logo_path)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Smooth, not the pixel-art nearest filter: the wordmark is drawn smaller than its file.
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var art := logo.texture.get_size()
	var height := float(branding.studio_logo_height_px)
	logo.custom_minimum_size = Vector2(height * art.x / maxf(1.0, art.y), height)
	logo.modulate.a = branding.corner_alpha
	add_child(logo)
	# Placed by hand from its known size: the preset's "minimum size" mode saw a size of 0 and put
	# the logo's top-left corner in the screen's corner, so it hung off the screen (card #210).
	var size := logo.custom_minimum_size
	logo.anchor_left = 1.0
	logo.anchor_top = 1.0
	logo.anchor_right = 1.0
	logo.anchor_bottom = 1.0
	logo.offset_left = -margin - size.x
	logo.offset_top = -margin - size.y
	logo.offset_right = -margin
	logo.offset_bottom = -margin


## "v0.17.0": the project's version (Project Settings > Application > Config > Version), the same
## one the online handshake and the save check use.
static func version_text() -> String:
	return "v" + str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


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
