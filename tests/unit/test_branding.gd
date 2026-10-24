extends GutTest
## Branding data (DESIGN 7.7): the branding, credits and tips files load, every song in the game is
## credited on the credits screen (CC-BY licences require it), and tips fit on a loading card.

const BRANDING_PATH := "res://data/branding/branding.tres"
const CREDITS_PATH := "res://data/branding/credits.tres"
const TIPS_PATH := "res://data/branding/tips.tres"
const MUSIC_CREDITS := "res://assets/audio/music/CREDITS.md"
const SOUND_CREDITS: Array[String] = ["res://assets/audio/sfx/CREDITS.md", "res://assets/audio/ambience/CREDITS.md"]
## A tip longer than this wraps onto a third line on the card.
const TIP_MAX_CHARS: int = 110


func test_branding_loads_with_logo_and_story() -> void:
	var branding := load(BRANDING_PATH) as BrandingData
	assert_not_null(branding, "branding.tres loads as BrandingData")
	if branding == null:
		return
	assert_true(ResourceLoader.exists(branding.logo_path), "the logo exists: %s" % branding.logo_path)
	assert_false(branding.story.strip_edges().is_empty(), "the story blurb is written")
	assert_gt(branding.glow_pulse_ms, 0)
	assert_gt(branding.prompt_blink_ms, 0)


## The title screen's swaying ribbon needs the logo's three layers, all the size of the logo, or
## the tails would slide off their knot.
func test_title_logo_layers_line_up() -> void:
	var branding := load(BRANDING_PATH) as BrandingData
	if branding == null:
		return
	var logo := load(branding.logo_path) as Texture2D
	for path: String in [branding.title_logo_back_path, branding.title_logo_tails_path, branding.title_logo_front_path,
			branding.title_logo_front_edge_path]:
		assert_true(ResourceLoader.exists(path), "layer exists: %s" % path)
		var layer := load(path) as Texture2D
		if logo != null and layer != null:
			assert_eq(layer.get_size(), logo.get_size(), "layer is the logo's size: %s" % path)
	assert_between(branding.ribbon_root.x, 0.0, 1.0)
	assert_between(branding.ribbon_root.y, 0.0, 1.0)
	assert_gt(branding.ribbon_sway_ms, 0)


func test_every_song_is_credited() -> void:
	var credits := load(CREDITS_PATH) as CreditsData
	assert_not_null(credits, "credits.tres loads as CreditsData")
	if credits == null:
		return
	var file := FileAccess.open(MUSIC_CREDITS, FileAccess.READ)
	assert_not_null(file, "the music credits list exists")
	if file == null:
		return
	var songs := 0
	var line_re := RegEx.create_from_string("^- \\*\\*[^*]+\\*\\*: \"([^\"]+)\" by ([^,]+),")
	for line: String in file.get_as_text().split("\n"):
		var m := line_re.search(line)
		if m == null:
			continue
		songs += 1
		var credit := "\"%s\" by %s" % [m.get_string(1), m.get_string(2)]
		assert_true(credits.text.contains(credit), "the credits name %s" % credit)
	assert_gt(songs, 0, "the music credits list has songs")


## Every author of a sound effect or ambience recording is on the credits screen (card #249): the
## CC BY ones need it, the CC0 ones get it anyway. A deleted Freesound account is "an anonymous
## Freesound user" there.
func test_every_sound_author_is_credited() -> void:
	var credits := load(CREDITS_PATH) as CreditsData
	if credits == null:
		return
	var by_re := RegEx.create_from_string("\" by ([^,\"]+?), CC")
	var authors := 0
	for path: String in SOUND_CREDITS:
		var file := FileAccess.open(path, FileAccess.READ)
		assert_not_null(file, "the sound credits list exists: %s" % path)
		if file == null:
			continue
		for m: RegExMatch in by_re.search_all(file.get_as_text()):
			var author := m.get_string(1).strip_edges()
			authors += 1
			if author.begins_with("deleted_user"):
				assert_true(credits.text.contains("an anonymous Freesound user"), "the credits thank %s" % author)
			else:
				assert_true(credits.text.contains(author), "the credits name %s (%s)" % [author, path.get_file()])
	assert_gt(authors, 0, "the sound credits lists name authors")


func test_tips_fit_on_a_card() -> void:
	var tips := load(TIPS_PATH) as TipSet
	assert_not_null(tips, "tips.tres loads as TipSet")
	if tips == null:
		return
	assert_gt(tips.tips.size(), 1, "more than one tip (no tip shows twice in a row)")
	for tip: String in tips.tips:
		assert_false(tip.strip_edges().is_empty(), "no empty tip")
		assert_lte(tip.length(), TIP_MAX_CHARS, "tip fits on the card: %s" % tip)


func test_main_menu_has_credits() -> void:
	assert_has(MainMenu.EXTRAS_ITEMS, MainMenu.CREDITS, "Credits sits in Extras")
	assert_eq(MainMenu.ITEMS.back(), MainMenu.QUIT, "Quit stays last")


func test_main_menu_is_short() -> void:
	# Cards #150 and #208: Host and Join sit under one Online row; the tutorial, the glossary, the
	# journal and the credits under Extras; Practice is a test tool, not a player row. Phase 17 adds Relics.
	assert_eq(MainMenu.ITEMS, [MainMenu.NEW_RUN, MainMenu.ONLINE, MainMenu.RELICS, MainMenu.EXTRAS, MainMenu.SETTINGS,
			MainMenu.QUIT])
	assert_does_not_have(MainMenu.ITEMS, MainMenu.HOST_ONLINE)
	assert_eq(MainMenu.EXTRAS_ITEMS, [MainMenu.TUTORIAL, MainMenu.GLOSSARY, MainMenu.JOURNAL, MainMenu.CREDITS])
	assert_does_not_have(MainMenu.EXTRAS_ITEMS, MainMenu.PRACTICE)
	assert_eq(MainMenu.ONLINE_ITEMS, [MainMenu.HOST_ONLINE, MainMenu.JOIN_ONLINE])
	# Fight Rush (DESIGN.md 8.21) hides under New Run as a second card, not a row of its own.
	assert_eq(MainMenu.MODE_ITEMS, [MainMenu.PLAY_RUN, MainMenu.PLAY_RUSH])
	assert_does_not_have(MainMenu.ITEMS, MainMenu.PLAY_RUSH)


func test_main_menu_shows_the_version_and_the_studio_logo() -> void:
	# Card #210: v and Project Settings' version bottom left, the DragonRot wordmark bottom right.
	assert_eq(MainMenu.version_text(), "v" + str(ProjectSettings.get_setting("application/config/version")))
	var branding := load("res://data/branding/branding.tres") as BrandingData
	assert_true(AssetLoader.has_art(branding.studio_logo_path), "the studio logo file exists")
	var menu := MainMenu.new()
	add_child_autofree(menu)
	menu.setup(branding)
	var version := menu.get_node_or_null("Version") as Label
	assert_not_null(version)
	if version != null:
		assert_eq(version.text, MainMenu.version_text())
	var logo := menu.get_node_or_null("StudioLogo") as TextureRect
	assert_not_null(logo)
	if logo != null:
		assert_eq(int(logo.custom_minimum_size.y), branding.studio_logo_height_px)
		# Fully on screen, its bottom-right corner a margin from the screen's (it once hung off).
		assert_eq(logo.anchor_left, 1.0)
		assert_eq(logo.anchor_top, 1.0)
		assert_eq(int(logo.offset_right), -branding.corner_margin_px)
		assert_eq(int(logo.offset_bottom), -branding.corner_margin_px)
		assert_almost_eq(logo.offset_right - logo.offset_left, logo.custom_minimum_size.x, 0.5)
		assert_almost_eq(logo.offset_bottom - logo.offset_top, logo.custom_minimum_size.y, 0.5)

