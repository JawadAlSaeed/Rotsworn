extends GutTest
## Phase 22 "Fewer words, more icons" on the fight screen: the defence and skill press corners
## without their sentences, every status as an icon with its turns (enemy and hero panels), a
## Doom's turns without break numbers, marks drawn on the hits instead of written after the
## attack, a slim target panel, and a locked skill shown with a lock and a red cost instead of a
## sentence.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const TUNING_PATH := "res://data/tuning/tuning.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const NORMAL: int = AttackHitData.Kind.NORMAL
const GROUND: int = AttackHitData.Kind.GROUND
const REND: int = AttackHitData.Kind.REND
const SWEEP: int = AttackHitData.Kind.SWEEP

var _visuals: CombatVisuals


func before_all() -> void:
	_visuals = load(VISUALS_PATH) as CombatVisuals


func _hud() -> CombatHud:
	var hud := CombatHud.new()
	add_child_autofree(hud)
	hud.setup(null, _visuals, load(TUNING_PATH) as Tuning)
	return hud


## Every Label text under `node`.
func _texts(node: Node) -> PackedStringArray:
	var list := PackedStringArray()
	for label: Node in node.find_children("*", "Label", true, false):
		list.append((label as Label).text)
	return list


func _any_contains(texts: PackedStringArray, word: String) -> bool:
	for text: String in texts:
		if text.contains(word):
			return true
	return false


# --- the art ------------------------------------------------------------------------------------

func test_every_status_and_the_stagger_has_a_drawn_icon() -> void:
	var ids: Array[String] = Status.ALL.duplicate()
	ids.append(CombatHud.STAGGER_BADGE_ID)
	for id: String in ids:
		var path := HudStyle.MARK_ICON_PATH % id
		assert_true(FileAccess.file_exists(path), "%s is drawn (tools/art_kit ui_marks)" % path)
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		assert_not_null(image, id)
		if image == null:
			continue
		assert_eq(image.get_size(), Vector2i(12, 12), "%s: 12x12 like the other marks" % id)
		var opaque := 0
		for y: int in image.get_height():
			for x: int in image.get_width():
				if image.get_pixel(x, y).a > 0.5:
					opaque += 1
		assert_gt(opaque, 20, "%s: a real picture" % id)


func test_a_status_icon_loads_even_before_it_is_imported() -> void:
	for id: String in ["exposed", "guarded", "taunted", "riposte", "bleeding", "regen", "marked", "empowered",
			CombatHud.STAGGER_BADGE_ID, Status.HUSHED]:
		var icon := HudStyle.mark_icon(id)
		assert_not_null(icon, id)
		if icon != null:
			assert_eq(Vector2i(icon.get_size()), Vector2i(12, 12), id)
			assert_ne(icon, AssetLoader.fallback_texture(Vector2i(32, 32)), "%s: not the placeholder" % id)
	assert_null(HudStyle.mark_icon("no_such_status"), "no file: no icon, so the word shows instead")


func test_the_icon_sizes_live_in_the_visuals() -> void:
	assert_gt(_visuals.status_icon_px, 0.0)
	assert_gt(_visuals.hit_mark_icon_share, 0.0)
	assert_gt(_visuals.defend_hit_icon_px, 0.0)
	assert_gt(_visuals.menu_lock_px, 0.0)
	assert_gt(_visuals.locked_cost_color.a, 0.0)


# --- status icons with their turns --------------------------------------------------------------

func test_status_badges_list_every_status_with_the_turns_that_show() -> void:
	var statuses := {"guarded": {"turns": 0}, "empowered": {"turns": 1}, "marked": {"turns": 3},
			"slowed": {"turns": 2}, "rotting": {"turns": 2}, "warded": {"turns": 1}}
	assert_eq(HudStyle.status_badges(statuses),
			[["rotting", 2], ["slowed", 2], ["warded", 1], ["guarded", 0], ["marked", 3], ["empowered", 0]],
			"marks first (cleanse order), the ward, then the rest; no number where none counts")
	assert_eq(HudStyle.status_badges({}), [])


func test_a_status_chip_is_its_icon_its_word_and_its_turns() -> void:
	var chip := HudStyle.status_chip("bleeding", 3, 24.0, 18)
	add_child_autofree(chip)
	assert_eq(chip.get_child_count(), 2)
	assert_true(chip.get_child(0) is TextureRect, "the icon first")
	assert_eq((chip.get_child(0) as TextureRect).texture, HudStyle.mark_icon("bleeding"))
	assert_eq((chip.get_child(1) as Label).text, "BLEEDING 3", "then its word and turns (owner: icons alone meant nothing)")
	var still := HudStyle.status_chip("guarded", 0, 24.0, 18)
	add_child_autofree(still)
	assert_eq(_texts(still), PackedStringArray(["GUARD"]), "no count: the icon and its word")
	var unknown := HudStyle.status_chip("no_such_status", 2, 24.0, 18)
	add_child_autofree(unknown)
	assert_eq(_texts(unknown), PackedStringArray(["NO_SUCH_STATUS 2"]), "no icon: the word")


func test_an_enemy_panel_shows_status_icons_with_their_words() -> void:
	var hud := _hud()
	var row: Dictionary = hud._make_enemy_panel(1, "Husk")
	var statuses := {"exposed": {"turns": 0}, "slowed": {"turns": 2}, "bleeding": {"turns": 3},
			"marked": {"turns": 1}, "shielded": {"turns": 2}, "taunted": {"turns": 0}}
	hud._show_badges(row, statuses, 2)
	var box := row.badges as HFlowContainer
	assert_true(box is HFlowContainer, "they still wrap (card #279)")
	assert_true(box.visible)
	var names := PackedStringArray()
	for chip: Node in box.get_children():
		names.append(String(chip.name))
		assert_true(chip.get_child(0) is TextureRect, "%s: an icon" % chip.name)
	assert_eq(names, PackedStringArray(["Status_slowed", "Status_exposed", "Status_taunted", "Status_bleeding",
			"Status_marked", "Status_shielded", "Status_staggered"]))
	assert_true(_texts(box).has("SLOWED 2"), "the word and its turns")
	assert_true(_texts(box).has("STAGGERED 2"), "the stagger's word and turns")
	hud._show_badges(row, {}, 0)
	assert_false(box.visible, "nothing to show: hidden")


func test_enemy_badges_add_the_stagger_with_its_turns() -> void:
	assert_eq(CombatHud.enemy_badges({"exposed": {"turns": 0}}, 2), [["exposed", 0], ["staggered", 2]])
	assert_eq(CombatHud.enemy_badges({}, 0), [])


func test_a_hero_card_shows_its_statuses_as_icons_with_words() -> void:
	var card := PartyPanel.new()
	add_child_autofree(card)
	card.setup(0, "Cass", Color(0.8, 0.3, 0.3), null, 4, _visuals)
	var statuses := {"guarded": {"turns": 0}, "riposte": {"turns": 0}, "regen": {"turns": 3},
			"rotting": {"turns": 2}, "warded": {"turns": 1}}
	card.refresh({"hp": 20, "max_hp": 40, "ap": 1, "alive": true, "statuses": statuses}, false)
	assert_eq(card.status_count(), 5, "one icon per status")
	var texts := _texts(card)
	for word: String in ["GUARD", "RIPOSTE", "RENEW", "ROT", "WARD"]:
		assert_true(_any_contains(texts, word), "the '%s' word sits by its icon" % word)
	card.refresh({"hp": 20, "max_hp": 40, "ap": 1, "alive": true, "statuses": {}}, false)
	assert_eq(card.status_count(), 0)


# --- Doom and the intent sign -------------------------------------------------------------------

func _dooming_mirror(id: int) -> CombatMirror:
	var mirror := CombatMirror.new()
	mirror.fighters[id] = {"alive": true, "hp": 500, "max_hp": 800, "charge_left": 2, "charge_damage": 120,
			"break_hp": 840, "statuses": {}, "staggered": 0, "display_name": "Lord"}
	mirror.enemy_ids.append(id)
	mirror.intents[id] = {"name": "Crown of Rot", "mode": EnemyAttackData.TargetMode.PARTY, "targets": [],
			"kinds": [NORMAL, GROUND, NORMAL], "times": [0, 600, 1200], "marks": ["", "burning", "dazed"]}
	return mirror


func test_a_doom_shows_its_turns_and_no_break_numbers() -> void:
	var hud := _hud()
	hud._make_enemy_panel(7, "Lord")
	hud._refresh_intent_sign(7, _dooming_mirror(7))
	var sign: Dictionary = hud._intent_signs[7]
	assert_true((sign.doom as Control).visible)
	assert_eq((sign.doom_label as Label).text, "DOOM 2")
	assert_false((sign.doom_label as Label).text.contains("BREAK"), "the break numbers are gone")
	assert_false(_any_contains(_texts(sign.doom as Node), "/"), "no 120 / 840")


func test_the_intent_names_the_attack_and_draws_marks_on_the_hits() -> void:
	var hud := _hud()
	hud._make_enemy_panel(7, "Lord")
	hud._refresh_intent_sign(7, _dooming_mirror(7))
	var sign: Dictionary = hud._intent_signs[7]
	var text := (sign.label as Label).text
	assert_eq(text, "Crown of Rot  >  WHOLE PARTY", "the attack's name and its targets")
	assert_false(text.contains("["), "no [BURN/DAZE] words")
	assert_false(text.contains("BURN"))
	var row := sign.row as HitRowView
	assert_eq(row.mark_textures(), [null, HudStyle.mark_icon("burning"), HudStyle.mark_icon("dazed")] as Array[Texture2D],
			"each marking hit wears its mark's icon")


func test_intent_text_is_name_and_targets() -> void:
	assert_eq(CombatHud.intent_text("Sting String", "CASS > ALDER"), "Sting String  >  CASS > ALDER")


func test_a_hit_row_draws_the_mark_icon_of_each_marking_hit() -> void:
	var row := HitRowView.new()
	add_child_autofree(row)
	row.setup(30.0, _visuals)
	row.set_hits([NORMAL, NORMAL, NORMAL], [0, 400, 800], HitRowView.load_icons(_visuals), [],
			["", Status.ROTTING, Status.MARK_AP_DRAIN])
	assert_eq(row.mark_textures(),
			[null, HudStyle.mark_icon(Status.ROTTING), HudStyle.mark_icon(Status.MARK_AP_DRAIN)] as Array[Texture2D])
	row.set_hits([NORMAL], [0], HitRowView.load_icons(_visuals))
	assert_eq(row.mark_textures(), [null] as Array[Texture2D], "no marks: nothing drawn")


# --- the bottom right corners -------------------------------------------------------------------

## The plate (PanelContainer) under `corner` whose word is `word`.
func _plate_with(corner: Node, word: String) -> Node:
	for plate: Node in corner.find_children("*", "PanelContainer", true, false):
		if _texts(plate).has(word):
			return plate
	return null


func test_the_defend_corner_has_no_sentence_and_shows_the_hits_each_button_answers() -> void:
	var hud := _hud()
	var corner := hud.find_child("ControlsHint", true, false)
	assert_not_null(corner)
	var texts := _texts(corner)
	assert_false(_any_contains(texts, "Ground wave"), "the rule note is gone")
	assert_false(_any_contains(texts, "counterattack"))
	var expected := {"PARRY": [NORMAL, REND], "DODGE": [NORMAL, SWEEP], "JUMP": [GROUND]}
	for word: String in expected:
		var plate := _plate_with(corner, word)
		assert_not_null(plate, word)
		if plate == null:
			continue
		var kinds: Array = []
		for icon: Node in plate.find_children("Hit*", "TextureRect", true, false):
			kinds.append(String(icon.name).trim_prefix("Hit").to_int())
			assert_eq((icon as TextureRect).texture, hud.hit_icon(int(kinds[-1])), "%s: the hit icon" % word)
		assert_eq(kinds, expected[word], "%s answers these hits" % word)


func test_the_skill_press_corner_is_one_plate_saying_press() -> void:
	var hud := _hud()
	var corner := hud.find_child("SkillPressHint", true, false)
	assert_not_null(corner)
	assert_eq(corner.get_child_count(), 1, "no title tag over the plate")
	var row := corner.get_child(0)
	assert_eq(row.get_child_count(), 1, "one plate")
	var texts := _texts(corner)
	assert_true(texts.has(CombatHud.SKILL_PRESS_TEXT), "the button chip and PRESS")
	assert_false(_any_contains(texts, "BEAT"), "no PRESS ON THE BEAT")
	assert_false(_any_contains(texts, "SKILL PRESS"))


# --- the action menu ----------------------------------------------------------------------------

func _ability(id: String, ap_cost: int, ap_gain: int = 0) -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	a.display_name = id.capitalize()
	a.description = "The long description of %s." % id
	a.ap_cost = ap_cost
	a.ap_gain = ap_gain
	a.target = AbilityData.Target.SINGLE_ENEMY
	return a


func _entry(ability: AbilityData, reason: String = "") -> Dictionary:
	return {"ability": ability, "usable": reason.is_empty(), "reason": reason, "targets": [3, 4],
			"pick_target": true}


func _menu(entries: Array[Dictionary]) -> ActionMenu:
	var menu := ActionMenu.new()
	menu.visuals = _visuals
	add_child_autofree(menu)
	menu.actor_ap = 1
	menu.max_ap = 9
	menu.open(Color(0.3, 0.5, 0.9), entries, {3: "Husk", 4: "Rat"})
	return menu


func test_the_target_panel_shows_the_skill_name_and_cost_only() -> void:
	var entries: Array[Dictionary] = [_entry(_ability("basic_attack", 0, 1)), _entry(_ability("fireball", 2))]
	var menu := _menu(entries)
	menu._pick_option(ActionMenu.Option.SKILLS)
	menu._use_entry(1)
	assert_true(menu._target.visible, "the target step is up")
	var texts := _texts(menu._target)
	assert_true(texts.has("Fireball"), "the skill's name")
	assert_true(texts.has("2 AP"), "its AP cost")
	assert_true(texts.has("◀   HUSK   ▶"), "who it is aimed at")
	assert_false(_any_contains(texts, "CHOOSE"), "no title")
	assert_false(_any_contains(texts, "description"), "no repeated description")


func test_a_locked_skill_shows_a_lock_and_a_red_cost_instead_of_a_sentence() -> void:
	var entries: Array[Dictionary] = [_entry(_ability("basic_attack", 0, 1)), _entry(_ability("fireball", 1)),
			_entry(_ability("meteor", 5), ActionMenu.LOCK_AP), _entry(_ability("smite", 1), ActionMenu.LOCK_HUSHED),
			_entry(_ability("lesson", 1), "Not in this lesson.")]
	var menu := _menu(entries)
	menu._pick_option(ActionMenu.Option.SKILLS)
	assert_true(menu.is_listing())
	var red := _visuals.locked_cost_color
	# Rows: fireball, meteor, smite, lesson.
	assert_false(menu._row_locks[0].visible, "a usable skill has no lock")
	assert_eq(menu._row_costs[0].label_settings.font_color, HudStyle.AP_TEXT)
	assert_true(menu._row_locks[1].visible, "short of AP: a lock")
	assert_eq(menu._row_locks[1].color, red)
	assert_eq(menu._row_costs[1].text, "5 AP")
	assert_eq(menu._row_costs[1].label_settings.font_color, red, "the cost turns red")
	assert_false(menu._row_hush[1].visible)
	assert_true(menu._row_locks[2].visible, "Hushed: a lock")
	assert_true(menu._row_hush[2].visible, "and the Hush icon")
	assert_eq(menu._row_hush[2].texture, HudStyle.mark_icon(Status.HUSHED))
	assert_ne(menu._row_costs[2].label_settings.font_color, red, "its AP is fine")
	assert_true(menu._row_locks[3].visible, "the tutorial's lock")
	assert_eq(menu._row_costs[3].label_settings.font_color, HudStyle.TEXT_DIM)
	menu._move_skill(1)
	assert_eq(menu._description.text, "The long description of meteor.", "what it does, no reason sentence")
	assert_false(_any_contains(_texts(menu), "Parry hits"), "the AP lesson is the tutorial's")


func test_the_controller_says_why_a_skill_is_locked_with_a_code() -> void:
	var setup := Fx.setup([Fx.attack("swipe", [Fx.hit(900)])], {"enemy_speed": 10})
	var engine := CombatEngine.new(setup)
	var fight := CombatController.new()
	for event: Dictionary in engine.start():
		fight.mirror.apply(event)
	fight._tuning = setup.tuning
	fight._setup = setup
	var actor := 0
	assert_eq(String(fight._menu_entry(actor, setup.party[0].basic_attack).reason), "", "usable")
	assert_eq(String(fight._menu_entry(actor, Fx.ability("meteor", 99, 0, 100)).reason), ActionMenu.LOCK_AP)
	var raise := Fx.skill("raise", AbilityData.Target.DOWNED_ALLY, 0, [])
	assert_eq(String(fight._menu_entry(actor, raise).reason), ActionMenu.LOCK_TARGET, "nobody is down")
	var ultimate := Fx.ability("finale", 0, 0, 100)
	ultimate.team_ultimate = true
	assert_eq(String(fight._menu_entry(actor, ultimate).reason), ActionMenu.LOCK_GAUGE)
	(fight.mirror.fighter(actor).statuses as Dictionary)[Status.HUSHED] = {"turns": 2, "source": Fx.ENEMY_ID}
	assert_eq(String(fight._menu_entry(actor, Fx.ability("heavy_strike", 0, 0, 100)).reason), ActionMenu.LOCK_HUSHED)
	assert_eq(String(fight._menu_entry(actor, setup.party[0].basic_attack).reason), "", "Attack still works")
	fight.free()
