extends GutTest
## Phase 22, the run's info screens (DESIGN.md 8): an icon and a word or two instead of rules
## sentences. The line under the map (the stop's picture and name, then 2 or 3 icon chips), the
## shop (service pictures, coin prices, a Relic as its icon and chips, Sell only once), the run's end
## (a row of stat chips, the Relics kept as icons, the killer's portrait on a defeat), the Echoes page
## (pips bars instead of the learning sentence) and the Rot Journal (hit kinds, marks and records as
## icons). The rules moved to the Glossary. Uses the shipped run; never touches the player's files.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const MAP_VISUALS_PATH := "res://data/presentation/map_visuals.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const ROCK_TOSS_PATH := "res://data/enemy_attacks/husk_rock_toss.tres"
const SEEDS: int = 20
## A chip says a word or two; never a sentence.
const MAX_CHIP_WORDS: int = 2

var _data: RunData
var _tuning: Tuning
var _look: MapVisuals
var _visuals: CombatVisuals


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning
	_look = load(MAP_VISUALS_PATH) as MapVisuals
	_visuals = load(VISUALS_PATH) as CombatVisuals


func _run(seed_value: int = 7) -> RunState:
	return RunState.begin(_data, _tuning.duplicate(true) as Tuning, seed_value)


func _relic(id: String) -> GearData:
	for item: GearData in _data.gear:
		if item != null and item.id == id:
			return item
	fail_test("no Relic %s" % id)
	return null


## Every Label's text under `node`.
func _texts(node: Node) -> Array[String]:
	var found: Array[String] = []
	if node is Label:
		found.append((node as Label).text)
	for child: Node in node.get_children():
		found.append_array(_texts(child))
	return found


func _count_of(node: Node, type_name: String) -> int:
	var n := 1 if node.is_class(type_name) or (node.get_script() != null and node.get_script().get_global_name() == type_name) else 0
	for child: Node in node.get_children():
		n += _count_of(child, type_name)
	return n


func _icon_exists(icon: Variant) -> bool:
	if icon is StringName:
		return UiGlyph.KINDS.has(icon)
	var path := String(icon)
	return not path.is_empty() and (ResourceLoader.exists(path) or FileAccess.file_exists(path))


# --- the line under the map ------------------------------------------------------------------------

func test_every_kind_of_stop_shows_two_or_three_icon_chips_not_a_sentence() -> void:
	var seen := {}
	for s: int in range(1, SEEDS):
		var run := _run(s)
		for stop: Dictionary in run.map.stops:
			var type := int(stop.type)
			var chips := MapScreen.detail_chips(run, stop, _look, _visuals.gold_icon_path)
			assert_between(chips.size(), 2, 3, "%s: 2 or 3 chips" % RunMap.TYPE_NAMES[type])
			for chip: Dictionary in chips:
				assert_true(_icon_exists(chip.icon), "%s: the chip's icon %s exists" % [RunMap.TYPE_NAMES[type], chip.icon])
				var words := String(chip.text).split(" ", false).size()
				assert_between(words, 1, MAX_CHIP_WORDS, "%s: '%s' is a word or two" % [RunMap.TYPE_NAMES[type], chip.text])
			seen[type] = true
		if is_failing():
			return
	for type: int in [RunMap.StopType.ZONE, RunMap.StopType.REST, RunMap.StopType.SHOP, RunMap.StopType.ELITE,
			RunMap.StopType.EVENT, RunMap.StopType.TREASURE, RunMap.StopType.FINAL]:
		assert_true(seen.has(type), "%s stops were checked" % RunMap.TYPE_NAMES[type])


func test_a_zone_shows_the_guard_the_optional_foes_and_gold() -> void:
	var run := _run()
	var zone: Dictionary = {}
	for stop: Dictionary in run.map.stops:
		if int(stop.type) == RunMap.StopType.ZONE:
			zone = stop
			break
	var chips := MapScreen.detail_chips(run, zone, _look, _visuals.gold_icon_path)
	assert_eq(chips.size(), 3)
	assert_eq(String(chips[0].icon), _look.guard_icon_path, "the guard at the exit")
	assert_eq(String(chips[1].icon), _look.foe_icon_path, "the roaming enemies, optional")
	assert_eq(String(chips[2].icon), _visuals.gold_icon_path, "they pay gold")


func test_a_campfire_shows_rest_train_and_upgrade() -> void:
	var run := _run()
	var chips := MapScreen.detail_chips(run, {"type": RunMap.StopType.REST}, _look, _visuals.gold_icon_path)
	assert_eq(chips.size(), 3)
	assert_eq(chips[0].icon, &"heart", "rest: a heart")
	assert_eq(String(chips[0].text), "Heal %d%%" % run.rest_heal_percent(), "with how much it heals")
	assert_eq(chips[1].icon, &"up", "train: the up arrow")
	assert_eq(String(chips[2].icon), _look.upgrade_icon_path, "upgrade: its own picture")


## The campfire row before each boss offers Keep watch and Sharpen (card #287), so its chips name
## those, never Train or Upgrade; the map agrees with the campfire screen at every campfire.
func test_the_campfire_before_the_boss_shows_watch_and_sharpen_not_train() -> void:
	var watch_fires := 0
	for s: int in range(1, SEEDS):
		var run := _run(s)
		for stop: Dictionary in run.map.stops:
			if int(stop.type) != RunMap.StopType.REST:
				continue
			run.at = int(stop.id)
			var watch := MapScreen.is_watch_row(run, stop)
			assert_eq(watch, run.is_watch_fire(), "seed %d stop %d: the map agrees with the campfire" % [s, stop.id])
			var chips := MapScreen.detail_chips(run, stop, _look, _visuals.gold_icon_path)
			var texts: Array[String] = []
			for chip: Dictionary in chips:
				texts.append(String(chip.text))
			if not watch:
				assert_true(texts.has("Train"), "other campfires keep Train")
				continue
			watch_fires += 1
			assert_false(texts.has("Train"), "seed %d stop %d: no Train before the boss" % [s, stop.id])
			assert_false(texts.has("Upgrade"), "seed %d stop %d: no Upgrade before the boss" % [s, stop.id])
			assert_eq(chips.size(), 3)
			assert_eq(chips[0].icon, &"heart", "rest still heals")
			assert_eq(String(chips[1].icon), _look.gauge_icon_path, "keep watch: the gauge")
			assert_eq(String(chips[1].text), "Gauge full")
			assert_eq(String(chips[2].icon), _look.ap_icon_path, "sharpen: AP")
			assert_eq(String(chips[2].text), "+%d AP" % run.tuning.sharpen_ap)
		if is_failing():
			return
	assert_gt(watch_fires, 0, "every map has a campfire row before the boss")


func test_the_map_screen_shows_the_stops_picture_and_name_then_chips() -> void:
	var run := _run()
	var map := MapScreen.new()
	add_child_autofree(map)
	map.setup(run, _look, false)
	assert_false(map.has_method("describe"), "no sentence describing the stop")
	var stop := run.map.stop(map.choices()[0])
	var chips := MapScreen.detail_chips(run, stop, _look, _visuals.gold_icon_path)
	assert_eq(map._detail.get_child_count(), 1 + chips.size(), "the stop, then its chips")
	var head_texts := _texts(map._detail.get_child(0))
	assert_eq(head_texts, [MapScreen.detail_name(run, stop)] as Array[String], "the head is the stop's name")
	assert_eq(_count_of(map._detail.get_child(0), "TextureRect"), 1, "with its picture")
	for text: String in _texts(map._detail):
		assert_lte(text.split(" ", false).size(), 3, "'%s' is a word or two, not a rule" % text)


func test_an_icon_chip_shows_a_picture_and_a_word() -> void:
	var chip := MapScreen.icon_chip(_visuals.gold_icon_path, "12", HudStyle.GOLD)
	add_child_autofree(chip)
	assert_eq(_texts(chip), ["12"] as Array[String])
	assert_eq(_count_of(chip, "TextureRect"), 1)
	var glyph := MapScreen.icon_chip(&"heart", "", HudStyle.HEAL, 40.0, 26, false)
	add_child_autofree(glyph)
	assert_eq(_texts(glyph).size(), 0, "a picture alone")
	assert_eq(_count_of(glyph, "UiGlyph"), 1)
	var relic := MapScreen.icon_picture(_relic("iron_charm"), 40.0)
	add_child_autofree(relic)
	assert_true(relic is RelicIcon, "a Relic's picture is its icon")
	var coin := MapScreen.icon_picture(_visuals.gold_icon_path, 48.0) as TextureRect
	add_child_autofree(coin)
	var side := coin.texture.get_size().x
	assert_eq(int(coin.custom_minimum_size.x) % int(side), 0, "pixel art grows by a whole number")


func test_the_run_info_icons_exist() -> void:
	for path: String in [_look.guard_icon_path, _look.foe_icon_path, _look.upgrade_icon_path, _look.restock_icon_path,
			_look.leave_icon_path, _look.flag_path, _visuals.gold_icon_path]:
		assert_true(path.begins_with("res://assets/"), "%s lives in assets/" % path)
		assert_true(FileAccess.file_exists(path), "%s is drawn" % path)


# --- the shop ---------------------------------------------------------------------------------------

func _shop(run: RunState) -> ShopScreen:
	var shop := ShopScreen.new()
	add_child_autofree(shop)
	shop.setup(run, run.shop_gear(run.at))
	return shop


func _shop_run() -> RunState:
	var run := _run()
	run.go(run.choices()[0])
	run.gold = 999
	return run


func test_sell_shows_once_and_prices_are_coins() -> void:
	var shop := _shop(_shop_run())
	var footer: HintBar = null
	for child: Node in shop.get_children():
		if child is HintBar:
			footer = child
	assert_not_null(footer, "a footer")
	for entry: Array in footer._entries:
		assert_ne(String(entry[1]), "Sell", "the footer does not say Sell")
	assert_eq(_texts(shop).count("Sell"), 1, "Sell once: its service card")
	for text: String in _texts(shop):
		assert_false(text.ends_with(" gold"), "'%s': a price is the coin and a number" % text)


func test_every_service_card_has_a_picture_and_a_price_has_the_coin() -> void:
	var run := _shop_run()
	var shop := _shop(run)
	assert_eq(shop._service_cards.size(), ShopScreen.SERVICES.size())
	for i: int in shop._service_cards.size():
		var column := shop._service_cards[i].get_child(0)
		var picture := column.get_child(0)
		assert_true(picture is TextureRect or picture is UiGlyph, "%s has a picture" % ShopScreen.SERVICES[i])
	var cleanse := shop._service_cards[0]
	var coins := 0
	for node: Node in cleanse.find_children("*", "TextureRect", true, false):
		if (node as TextureRect).texture == AssetLoader.texture(_visuals.gold_icon_path):
			coins += 1
	assert_eq(coins, 1, "Cleanse's price is the coin and a number")
	assert_true(_texts(cleanse).has(str(run.cleanse_price())))


func test_a_relic_on_the_shelf_shows_its_icon_and_level_chip_not_a_sentence() -> void:
	var run := _shop_run()
	var shop := _shop(run)
	var first := shop.items().size()
	assert_lt(first, shop.count(), "the shop sells Relics")
	var gear := run.shop_gear(run.at)[0]
	var detail := shop.detail(first)
	assert_eq(detail.icon, gear, "the Relic's own icon")
	assert_eq(String(detail.line), "", "no sentence")
	var chips: Array = detail.chips
	assert_eq(String(chips[0][1]), "Home" if run.is_home(gear) else ("New" if run.relic_level(gear) <= 0
			else "Lv %d > %d" % [run.relic_level(gear), run.relic_level(gear) + 1]))
	run.add_relic(gear)
	if run.can_gain(gear):
		assert_eq(String(ShopScreen.relic_chips(run, gear)[0][1]), "Lv 1 > 2", "a copy raises the run's level")
	var stat := gear.stat_text(2)
	if not stat.is_empty():
		assert_eq(String(ShopScreen.relic_chips(run, gear)[1][1]), stat, "the stat line at the level it will reach")
	for chip: Array in ShopScreen.relic_chips(run, gear):
		assert_false(String(chip[1]).contains("."), "'%s' is a chip, not a sentence" % chip[1])


func test_the_shop_bot_api_still_works() -> void:
	var run := _shop_run()
	var shop := _shop(run)
	var bought := -1
	for i: int in shop.items().size():
		if shop.can_buy(i):
			bought = i
			break
	if bought >= 0:
		assert_true(shop.buy(bought))
		assert_false(shop.can_buy(bought), "sold")
	var left: Array[bool] = []
	shop.done.connect(func() -> void: left.append(true))
	if shop.overlay() == null:
		shop.leave()
		assert_eq(left.size(), 1, "leave() ends the stop")


# --- the run's end ---------------------------------------------------------------------------------

func test_the_end_screen_stat_chips_are_icons_and_numbers() -> void:
	var run := _run()
	run.visited = 11
	run.fights_won = 14
	run.gold_earned = 540
	var chips := RunEndScreen.stat_chips(run, _look, _visuals.gold_icon_path)
	assert_eq(chips.size(), 4)
	assert_eq(String(chips[0].icon), run.act_data().final_map_icon_path, "the act reached: its boss's lair")
	assert_eq(String(chips[0].text), "Act 1/%d" % maxi(1, run.data.acts.size()))
	assert_eq(String(chips[1].icon), _look.flag_path, "stops: the party's flag")
	assert_eq(chips[2].icon, &"sword", "fights won: a sword")
	assert_eq(String(chips[3].icon), _visuals.gold_icon_path, "gold: the coin")
	assert_eq([String(chips[1].text), String(chips[2].text), String(chips[3].text)], ["Stops 11", "Wins 14", "Gold 540"],
			"each icon with its word")


func test_a_won_run_ends_with_icon_rows_and_no_lines_of_text() -> void:
	var run := _run()
	run.result = RunState.VICTORY
	var end := RunEndScreen.new()
	add_child_autofree(end)
	end.setup(run, 0)
	for text: String in _texts(end):
		assert_lte(text.split(" ", false).size(), 4, "'%s' is a few words" % text)
		assert_false(text.contains("Gold earned") or text.contains("Fights won"), "the stats are chips")
	var faces := 0
	for slot: int in run.party_size():
		for node: Node in end.find_children("*", "TextureRect", true, false):
			if (node as TextureRect).texture == AssetLoader.texture(run.data.party[slot].portrait_path, Vector2i(48, 48)):
				faces += 1
	assert_gte(faces, run.party_size() * 2, "each face in the stat row and on its defence row")


func test_the_relics_kept_are_icons_tagged_new_or_echo() -> void:
	var run := _run()
	var charm := _relic("iron_charm")
	assert_eq(RunEndScreen.kept_relics(run, run.relics_at_start, run.pips_at_start).size(), 0, "nothing new yet")
	run.add_relic(charm)
	run.mastery[charm.id] = run.tuning.mastery_needed
	var kept := RunEndScreen.kept_relics(run, run.relics_at_start, run.pips_at_start)
	assert_eq(kept.size(), 1)
	assert_eq(kept[0].item, charm)
	assert_true(bool(kept[0].new), "found for the first time")
	assert_true(bool(kept[0].echo), "and its Echo learned")
	var again := RunEndScreen.kept_relics(run, {charm.id: true}, {charm.id: run.tuning.mastery_needed})
	assert_eq(again.size(), 0, "a friend who had it already keeps nothing new")
	run.result = RunState.VICTORY
	var end := RunEndScreen.new()
	add_child_autofree(end)
	end.setup(run, 0)
	assert_eq(_count_of(end, "RelicIcon"), 1, "the kept Relic as its icon")
	assert_true(_texts(end).has("New"), "tagged New")
	var echo_marks := 0
	for node: Node in end.find_children("*", "UiGlyph", true, false):
		if (node as UiGlyph).kind == &"echo":
			echo_marks += 1
	assert_eq(echo_marks, 1, "and the Echo mark")


func test_kept_row_counts_only_after_a_late_join() -> void:
	# Card #304: a friend who dropped in mid-run keeps only what the run found after they joined.
	var run := _run()
	var needed := run.tuning.mastery_needed
	var drum := _relic("war_drum")
	var charm := _relic("iron_charm")
	run.add_relic(drum)
	run.mastery[drum.id] = 4
	var relics_before := run.relics.duplicate()
	var mastery_before := run.mastery.duplicate()
	run.add_relic(charm)
	run.mastery[drum.id] = needed
	assert_eq(RunEndScreen.kept_relics(run, {}, {}).size(), 2, "there from the start: both Relics")
	var kept := RunEndScreen.kept_relics(run, relics_before, {}, mastery_before)
	assert_eq(kept.size(), 1, "joined late: only the later find")
	assert_eq(kept[0].item, charm)
	assert_true(bool(kept[0].new))
	assert_false(bool(kept[0].echo))
	var drum_kept := RunEndScreen.kept_relics(run, relics_before, {drum.id: 4}, mastery_before)
	assert_eq(drum_kept.size(), 2, "the 8 pips since fill their own 4 to an Echo")
	for entry: Dictionary in drum_kept:
		if entry.item == drum:
			assert_true(bool(entry.echo) and not bool(entry.new), "the drum: an Echo, not new")
	# own_kept: their collection plus the run's Relics when they joined.
	var stranger := RelicCollection.new()
	var since := {"relics": relics_before, "mastery": {}}
	var shown := RunEndScreen.own_kept(run, stranger, since)
	assert_eq(shown.size(), 1, "a Relic they never found shows no Echo: their file keeps no pips for it")
	assert_eq(shown[0].item, charm)
	var owner := RelicCollection.new()
	owner.merge([drum.id], {})
	assert_eq(RunEndScreen.own_kept(run, owner, since).size(), 2, "their own drum's Echo is kept")
	assert_eq(RunEndScreen.own_kept(run, stranger).size(), 2, "no join: everything, as before")
	run.result = RunState.VICTORY
	var end := RunEndScreen.new()
	add_child_autofree(end)
	end.setup(run, 0, 0, [], "", [], {}, stranger, {"relics": relics_before, "mastery": mastery_before})
	assert_eq(_count_of(end, "RelicIcon"), 1, "the end screen shows the later find only")


func test_a_defeat_shows_the_killer_with_the_attack_and_its_hit_icon() -> void:
	var toss := load(ROCK_TOSS_PATH) as EnemyAttackData
	var recap := {"enemies": ["Rotten Husk"], "last_blow": {"name": toss.display_name, "source": "Rotten Husk",
			"target": "Alder", "amount": 23}}
	var killer := RunEndScreen.killer_of(recap)
	assert_not_null(killer.enemy, "the killer's data, for its portrait")
	assert_eq((killer.enemy as EnemyData).id, "rotten_husk")
	assert_eq(killer.attack_data, toss)
	assert_true(RunEndScreen.hit_icon_paths(toss, _visuals).has(_visuals.hit_icon_ranged_path), "a throw shows its own icon")
	assert_true(RunEndScreen.killer_of({}).is_empty(), "no recap, no killer")
	var run := _run()
	run.result = RunState.DEFEAT
	var end := RunEndScreen.new()
	add_child_autofree(end)
	var lines: Array[String] = ["Finished by  Rotten Husk", "Hardest hit  Rock Toss, Rotten Husk   23 damage"]
	end.setup(run, 0, 0, lines, "", [], recap)
	var texts := _texts(end)
	assert_true(texts.has(toss.display_name), "the attack's name")
	assert_true(texts.has("23 damage"), "and its damage, with the word")
	for text: String in texts:
		assert_false(text.begins_with("Finished by") or text.begins_with("Hardest hit"), "no lines of text")
	var ranged := 0
	for node: Node in end.find_children("*", "TextureRect", true, false):
		if (node as TextureRect).texture == AssetLoader.texture(_visuals.hit_icon_ranged_path):
			ranged += 1
	assert_eq(ranged, 1, "the throw's hit icon")


## Two of the same enemy are lettered in a fight ("Rotten Husk B"): the killer is still found, so the
## defeat shows its portrait and the attack's hit icons.
func test_a_lettered_killer_is_still_found() -> void:
	var toss := load(ROCK_TOSS_PATH) as EnemyAttackData
	var recap := {"enemies": ["Rotten Husk A", "Rotten Husk B"], "last_blow": {"name": toss.display_name,
			"source": "Rotten Husk B", "target": "Alder", "amount": 23}}
	var killer := RunEndScreen.killer_of(recap)
	assert_not_null(killer.enemy, "the killer's data, for its portrait")
	if killer.enemy == null:
		return
	assert_eq((killer.enemy as EnemyData).id, "rotten_husk")
	assert_eq(killer.attack_data, toss)
	assert_eq(String(killer.source), "Rotten Husk B", "the name as the fight showed it")


func _column(screen: Node) -> VBoxContainer:
	for child: Node in screen.get_children():
		if child is VBoxContainer:
			return child
	return null


## The fullest end screen (an oath broken, the killer, three heroes, many Relics kept) fits a
## 1080p screen above the footer.
func test_the_fullest_end_screen_fits() -> void:
	var run := RunState.begin(_data, _tuning.duplicate(true) as Tuning, 7, 3)
	run.result = RunState.DEFEAT
	for item: GearData in _data.gear:
		if item != null:
			run.add_relic(item)
			run.mastery[item.id] = run.tuning.mastery_needed
	var toss := load(ROCK_TOSS_PATH) as EnemyAttackData
	var recap := {"last_blow": {"name": toss.display_name, "source": "Rotten Husk", "amount": 123}}
	var end := RunEndScreen.new()
	add_child_autofree(end)
	end.setup(run, 0, 4, [] as Array[String], "", [1, 2, 3] as Array[int], recap)
	# Wrapped labels know their height once laid out.
	await get_tree().process_frame
	await get_tree().process_frame
	var size := _column(end).get_combined_minimum_size()
	assert_lte(size.y, 1080.0 - ListMenu.FOOTER_STRIP_PX, "it fits the height (it is %d)" % int(size.y))
	assert_lte(size.x, 1920.0 - 40.0, "and the width (it is %d)" % int(size.x))


func test_the_shop_fits_the_screen() -> void:
	var run := _shop_run()
	var shop := _shop(run)
	for i: int in shop.count() + ShopScreen.SERVICES.size():
		shop._sel = i
		shop._show_selection()
		assert_lte(shop._detail.get_combined_minimum_size().x, 1920.0 - 40.0, "line %d fits the width" % i)
	# Wrapped labels (card names) know their height once laid out.
	await get_tree().process_frame
	await get_tree().process_frame
	var size := _column(shop).get_combined_minimum_size()
	assert_lte(size.y, 1080.0 - ListMenu.FOOTER_STRIP_PX, "the shop fits the height (it is %d)" % int(size.y))


func test_without_a_recap_a_defeat_still_shows_its_lines() -> void:
	var run := _run()
	run.result = RunState.DEFEAT
	var end := RunEndScreen.new()
	add_child_autofree(end)
	end.setup(run, 0, 0, ["Finished by  Rotten Husk"] as Array[String])
	assert_true(_texts(end).has("Finished by  Rotten Husk"), "an older caller keeps the words")


# --- the Echoes page --------------------------------------------------------------------------------

func test_the_echoes_page_shows_pips_bars_not_the_learning_sentence() -> void:
	var run := _run()
	var drum := _relic("war_drum")
	run.add_relic(drum)
	run.wear(0, 0, drum)
	run.mastery[drum.id] = 5
	var screen := EchoesScreen.new()
	add_child_autofree(screen)
	screen.setup(run, 0)
	var learning := screen.learning()
	assert_eq(learning.size(), 1, "the worn Relic being learned")
	assert_eq(learning[0][0], drum)
	assert_eq(int(learning[0][1]), run.mastery_of(drum))
	assert_eq(int(learning[0][2]), run.tuning.mastery_needed)
	assert_eq(_count_of(screen._learning, "RelicIcon"), 1, "its icon")
	for text: String in _texts(screen):
		assert_false(text.contains("Learning") or text.contains("pips") or text.contains("kept for good"),
				"'%s': the rules are in the Glossary" % text)
	var bar := EchoesScreen.pips_bar(5, 12)
	add_child_autofree(bar)
	assert_eq(bar.get_child_count(), 12, "one pip per Echo pip needed")
	var full := 0
	for pip: Node in bar.get_children():
		if (pip as ColorRect).color == EchoesScreen.PIP_FULL:
			full += 1
	assert_eq(full, 5, "the filled ones")


func test_the_echoes_page_fits_with_a_relic_learning_on_every_hero() -> void:
	var run := _run()
	var ids: Array[String] = ["war_drum", "iron_charm", "whetstone"]
	for slot: int in run.party_size():
		var item := _relic(ids[slot % ids.size()])
		run.add_relic(item)
		run.wear(slot, 0, item)
		run.mastery[item.id] = 3
	var screen := EchoesScreen.new()
	add_child_autofree(screen)
	screen.setup(run, 0)
	assert_eq(screen.learning().size(), run.party_size(), "one Relic learning per hero")
	await get_tree().process_frame
	await get_tree().process_frame
	var row: Control = null
	for child: Node in screen.get_children():
		if child is HBoxContainer:
			row = child
	var size := row.get_combined_minimum_size()
	assert_lte(size.y, 1080.0 - ListMenu.FOOTER_STRIP_PX - EchoesScreen.MARGIN_TOP, "it fits (it is %d)" % int(size.y))
	assert_lte(size.x, 1920.0 - 2.0 * EchoesScreen.MARGIN_X, "and its width (it is %d)" % int(size.x))


# --- the Rot Journal --------------------------------------------------------------------------------

func test_the_journal_shows_hit_kinds_and_marks_as_icons() -> void:
	var toss := load(ROCK_TOSS_PATH) as EnemyAttackData
	var paths := JournalScreen.kind_icon_paths({"normal": 2, "ground": 1}, toss, _visuals)
	assert_true(paths.has(_visuals.hit_icon_ranged_path), "a throw shows the ranged icon")
	assert_true(paths.has(_visuals.hit_icon_ground_path))
	var swipe := load("res://data/enemy_attacks/husk_swipe.tres") as EnemyAttackData
	assert_eq(JournalScreen.kind_icon_paths({"normal": 1}, swipe, _visuals), [_visuals.hit_icon_normal_path] as Array[String],
			"a lunge keeps the sword")
	assert_eq(JournalScreen.kind_icon_paths({}, swipe, _visuals).size(), 0, "nothing seen, no icon")


func test_the_journal_record_is_glyphs_in_the_defence_colours() -> void:
	var parts := JournalScreen.record_parts({"parried": 3, "dodged": 2, "jumped": 0, "hit": 4})
	assert_eq(parts.size(), 4)
	assert_eq(parts[0], [&"shield", 3, HudStyle.PARRY])
	assert_eq(parts[1], [&"chevrons", 2, HudStyle.DODGE])
	assert_eq(parts[2], [&"up", 0, HudStyle.JUMP])
	assert_eq(parts[3], [&"sword", 4, HudStyle.HP_LOW])
	assert_eq(JournalScreen.record_parts({"broken": 2}).size(), 5, "a Doom broken adds its count")


func test_the_journal_page_has_icons_and_no_legend() -> void:
	var enemies := JournalScreen.load_enemies()
	var husk: EnemyData = null
	for data: EnemyData in enemies:
		if data.id == "rotten_husk":
			husk = data
	var attacks := {}
	for attack: EnemyAttackData in husk.all_attacks():
		attacks[attack.id] = {"name": attack.display_name, "seen": 2, "parried": 1, "dodged": 1, "jumped": 0, "hit": 1,
				"kinds": {"normal": 2}, "marks": {"rotting": 1}}
	var journal := RotJournal.new()
	journal.record_fight({"enemies": {husk.id: {"name": husk.display_name, "met": 1, "beaten": 1, "attacks": attacks}}})
	var screen := JournalScreen.new()
	add_child_autofree(screen)
	screen.setup(journal, enemies)
	screen._menu.index = enemies.find(husk)
	screen._refresh()
	for text: String in _texts(screen._panel):
		assert_false(text.contains("parry or dodge"), "no legend line")
		assert_false(text.begins_with("parried") or text == "Normal" or text == "ROT", "'%s': icons, not words" % text)
	var rot := 0
	for node: Node in screen._panel.find_children("*", "TextureRect", true, false):
		if (node as TextureRect).texture == HudStyle.mark_icon("rotting"):
			rot += 1
	assert_eq(rot, husk.all_attacks().size(), "each attack's mark as its icon")
	assert_gt(_count_of(screen._panel, "UiGlyph"), husk.all_attacks().size() * 3, "the records as glyphs")
