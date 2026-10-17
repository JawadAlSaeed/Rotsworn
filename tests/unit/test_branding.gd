extends GutTest
## Branding data (DESIGN 7.7): the branding, credits and tips files load, every song in the game is
## credited on the credits screen (CC-BY licences require it), and tips fit on a loading card.

const BRANDING_PATH := "res://data/branding/branding.tres"
const CREDITS_PATH := "res://data/branding/credits.tres"
const TIPS_PATH := "res://data/branding/tips.tres"
const MUSIC_CREDITS := "res://assets/audio/music/CREDITS.md"
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
	assert_has(MainMenu.ITEMS, MainMenu.CREDITS)
	assert_eq(MainMenu.ITEMS.back(), MainMenu.QUIT, "Quit stays last")


func test_main_menu_is_short() -> void:
	# Card #150: Host and Join sit under one Online row; the tutorial lives in Practice.
	assert_eq(MainMenu.ITEMS.size(), 7)
	assert_has(MainMenu.ITEMS, MainMenu.ONLINE)
	assert_does_not_have(MainMenu.ITEMS, MainMenu.HOST_ONLINE)
	assert_eq(MainMenu.ONLINE_ITEMS, [MainMenu.HOST_ONLINE, MainMenu.JOIN_ONLINE])
