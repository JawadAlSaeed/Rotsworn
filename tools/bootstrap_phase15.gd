extends SceneTree
## Writes the phase 15 run content (DESIGN.md 8.6 to 8.9): the zones' mini-boss guards (DESIGN.md
## 8.6), the first act's boss, the elite fights, the "?" events and the two acts of the run. The
## mini-bosses and the boss are recoloured kin of the monsters (tools/art_kit/assets/
## enemy_variants.py draws their sheets) with a phase two. Rewrites every file it owns; run
## tools/bootstrap_zones.gd after it (the zones' guards and champions point here).
## Run: Godot --headless --path . -s tools/bootstrap_phase15.gd

const EN := "res://data/enemies/"
const ENC := "res://data/encounters/"
const ATK := "res://data/enemy_attacks/"

var _written: int = 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/events"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/runs/acts"))
	var party: Array = (load(ENC + "husk_fight.tres") as EncounterData).party
	var ultimate := (load(ENC + "husk_fight.tres") as EncounterData).team_ultimate

	# --- mini-boss guards: a named kin of the zone's monster, with a phase two -----------------
	var gorged := _boss_kin("gorged_one", "The Gorged One", "bloat", "blight_bloat", Color(0.7, 0.25, 0.35),
			280, 150, 85, 60, 130, "THE GORGED ONE SPLITS ITS SKIN!")
	var mother := _boss_kin("mire_mother", "Mire Mother", "mire_toad", "elder_toad", Color(0.3, 0.55, 0.45),
			270, 145, 105, 60, 130, "THE MIRE MOTHER CALLS THE MUD!")
	var warden := _boss_kin("ash_warden", "Ash Warden", "shade", "hollow_shade", Color(0.85, 0.45, 0.2),
			250, 150, 115, 60, 130, "THE ASH WARDEN BURNS!")
	var gnats := load(EN + "gnat_swarm.tres") as EnemyData
	var blood := load(EN + "blood_gnats.tres") as EnemyData
	var fly := load(EN + "carrion_fly.tres") as EnemyData
	var plague := load(EN + "plague_fly.tres") as EnemyData
	_guard("guard_gorged_one", "The Gorged One", [gorged, gnats], [gorged, blood], party, ultimate)
	_guard("guard_mire_mother", "Mire Mother", [mother, fly], [mother, plague], party, ultimate)
	_guard("guard_ash_warden", "Ash Warden", [warden, gnats], [warden, blood], party, ultimate)

	# --- the first act's boss --------------------------------------------------------------------
	var lord := _boss_kin("husk_lord", "The Husk Lord", "rotten_husk", "ashen_husk", Color(0.75, 0.6, 0.25),
			420, 140, 120, 120, 260, "THE HUSK LORD TEARS FREE OF ITS BARK!")
	lord.phase_two_speed = 165
	_save(lord, EN + "husk_lord.tres")
	var boss := _encounter("husk_lord_fight", "The Husk Lord", [lord, load(EN + "rotten_husk.tres")], party, ultimate)
	boss.boss = true
	boss.can_run = false
	_save(boss, ENC + "husk_lord_fight.tres")

	# --- elite fights (DESIGN.md 8.6) -------------------------------------------------------------
	var husk := load(EN + "rotten_husk.tres") as EnemyData
	var ashen := load(EN + "ashen_husk.tres") as EnemyData
	var hyena := load(EN + "rot_hyena.tres") as EnemyData
	var bone := load(EN + "bone_hyena.tres") as EnemyData
	var toad := load(EN + "mire_toad.tres") as EnemyData
	var elder := load(EN + "elder_toad.tres") as EnemyData
	var shade := load(EN + "shade.tres") as EnemyData
	var hollow := load(EN + "hollow_shade.tres") as EnemyData
	_elite("elite_twin_husks", "Twin Husks", [husk, husk], [ashen, ashen], party, ultimate)
	_elite("elite_hyena_pack", "The Laughing Pack", [hyena, hyena, fly], [bone, bone, plague], party, ultimate)
	_elite("elite_toad_court", "Toad Court", [toad, toad], [elder, elder], party, ultimate)
	_elite("elite_shade_coven", "Shade Coven", [shade, shade, gnats], [hollow, hollow, blood], party, ultimate)

	# --- events and acts -------------------------------------------------------------------------
	var events := _events()
	var run := load("res://data/runs/rotten_road.tres") as RunData
	var zones := {}
	for zone: ZoneData in run.zones:
		zones[zone.id] = zone
	var act1 := ActData.new()
	act1.id = "rotten_road"
	act1.display_name = "The Rotten Road"
	act1.zones.assign([zones.rotten_hollow, zones.sunken_bog])
	act1.final_encounter = load(ENC + "husk_lord_fight.tres") as EncounterData
	act1.final_look = load("res://data/looks/rotten_hollow.tres") as StageLook
	act1.final_map_icon_path = "res://assets/sprites/ui/map_lair_husk_lord.png"
	act1.elites.assign([_enc("elite_twin_husks"), _enc("elite_toad_court"), _enc("elite_hyena_pack")])
	act1.events.assign(events)
	var act2 := ActData.new()
	act2.id = "ashen_deep"
	act2.display_name = "The Ashen Deep"
	act2.zones.assign([zones.ashen_ruins, zones.sunken_bog, zones.rotten_hollow])
	act2.final_encounter = run.final_encounter
	act2.final_look = run.final_look
	act2.final_map_icon_path = run.final_map_icon_path
	act2.elites.assign([_enc("elite_shade_coven"), _enc("elite_hyena_pack"), _enc("elite_twin_husks")])
	act2.events.assign(events)
	act2.deep = true
	run.acts.assign([_save(act1, "res://data/runs/acts/rotten_road.tres"), _save(act2, "res://data/runs/acts/ashen_deep.tres")])
	_save(run, "res://data/runs/rotten_road.tres")
	print("bootstrap_phase15: wrote %d files" % _written)
	quit()


## A mini-boss or boss: `base`'s look and moves recoloured (sheet `id`.png from enemy_variants.py),
## `variant`'s moves in phase two at half HP.
func _boss_kin(id: String, title: String, base_id: String, variant_id: String, color: Color, hp: int, power: int,
		speed: int, gold: int, xp: int, rage: String) -> EnemyData:
	var base := load(EN + base_id + ".tres") as EnemyData
	var variant := load(EN + variant_id + ".tres") as EnemyData
	var kin := base.duplicate() as EnemyData
	kin.id = id
	kin.display_name = title
	kin.color = color
	kin.sprite_path = "res://assets/sprites/enemies/%s.png" % id
	kin.portrait_path = "res://assets/sprites/portraits/%s.png" % id
	kin.hp_percent = hp
	kin.power_percent = power
	kin.speed = speed
	kin.gold = gold
	kin.xp = xp
	kin.attacks = base.attacks.duplicate()
	kin.phase_two_hp_percent = 50
	kin.phase_two_attacks = variant.attacks.duplicate()
	kin.phase_two_speed = speed + 40
	kin.phase_two_text = rage
	return _save(kin, EN + id + ".tres") as EnemyData


func _encounter(id: String, title: String, enemies: Array, party: Array, ultimate: AbilityData) -> EncounterData:
	var encounter := EncounterData.new()
	encounter.id = id
	encounter.display_name = title
	encounter.party.assign(party)
	encounter.enemies.assign(enemies)
	encounter.team_ultimate = ultimate
	return encounter


## A zone's guard: a mini-boss fight (no running), with a deep version (variant helpers).
func _guard(id: String, title: String, enemies: Array, deep_enemies: Array, party: Array, ultimate: AbilityData) -> void:
	var deep := _encounter("deep_" + id, title, deep_enemies, party, ultimate)
	deep.mini_boss = true
	deep.can_run = false
	var guard := _encounter(id, title, enemies, party, ultimate)
	guard.mini_boss = true
	guard.can_run = false
	guard.deep = _save(deep, ENC + "deep_%s.tres" % id) as EncounterData
	_save(guard, ENC + id + ".tres")


func _elite(id: String, title: String, enemies: Array, deep_enemies: Array, party: Array, ultimate: AbilityData) -> void:
	var deep := _encounter("deep_" + id, title, deep_enemies, party, ultimate)
	deep.elite = true
	var elite := _encounter(id, title, enemies, party, ultimate)
	elite.elite = true
	elite.deep = _save(deep, ENC + "deep_%s.tres" % id) as EncounterData
	_save(elite, ENC + id + ".tres")


func _enc(id: String) -> EncounterData:
	return load(ENC + id + ".tres") as EncounterData


# --- events (DESIGN.md 8.7) ---------------------------------------------------------------------

func _events() -> Array[EventData]:
	var key := load("res://data/items/key.tres") as ItemData
	var idol := load("res://data/items/golden_idol.tres") as ItemData
	var salve := load("res://data/items/salve.tres") as ItemData
	var list: Array[EventData] = []
	list.append(_event("weeping_well", "The Weeping Well",
			"A well of black water whispers your names. Something glints far below.", [
		_choice("Drink", "Everyone heals 40%. The water may bite back.", _deal({"heal": 40}), 30,
				_deal({"hp": 15}), "The water is cold and sweet.", "It burns going down. Everyone loses 15% HP."),
		_choice("Drop a coin in (10 gold)", "Wish for strength: the team gauge fills by 40.",
				_deal({"cost": 10, "gauge": 40}), 0, null, "The whispers turn to cheers."),
	]))
	list.append(_event("gamblers_bones", "Gambler's Bones",
			"A skeleton sits at a table of rotten wood, dice in its hand. It waits for a player.", [
		_choice("Roll the bones (20 gold)", "Win 60 gold. Or lose it all.", _deal({"cost": 20, "gold": 60}), 50,
				_deal({"cost": 60}), "The dice come up sixes.", "The dice turn in the air. The skeleton takes its winnings."),
		_choice("Take its purse", "15 gold. The dead do not like thieves.", _deal({"gold": 15}), 40,
				_deal({"hp": 10}), "The purse is light.", "A bony hand snaps at you. Everyone loses 10% HP."),
	]))
	list.append(_event("wounded_pilgrim", "A Wounded Pilgrim",
			"A pilgrim lies in the road, bleeding through his robe. He clutches a satchel.", [
		_choice("Bind his wounds", "Everyone loses 10% HP. Every hero gets 40 XP.",
				_deal({"hp": 10, "xp": 40}), 0, null, "He blesses you and limps on."),
		_choice("Take the satchel", "A salve and 30 gold. He might not be alone.", _deal({"gold": 30, "item": salve}), 50,
				_deal({"hp": 20}), "He is too weak to stop you.", "His friends were watching. Everyone loses 20% HP."),
	]))
	list.append(_event("rot_blossom", "Rot Blossom",
			"A huge violet flower grows from a corpse. Its fruit smells of honey and graves.", [
		_choice("Eat the fruit", "Everyone heals 25%. It might be poison.", _deal({"heal": 25}), 35,
				_deal({"hp": 15}), "Sweet and filling.", "Your stomachs turn. Everyone loses 15% HP."),
		_choice("Cut the seed pod", "Something you can use, found inside.", _deal({"find": 0}), 0, null,
				"The pod splits open."),
	]))
	list.append(_event("hanging_cage", "The Hanging Cage",
			"An iron cage hangs from a dead tree. The body inside still holds a key.", [
		_choice("Climb up", "Get the key. The branch is old.", _deal({"item": key}), 35, _deal({"hp": 20}),
				"You pry the key from cold fingers.", "The branch snaps. Everyone loses 20% HP."),
	]))
	list.append(_event("shrine_of_kings", "Shrine of Old Kings",
			"Crowned statues kneel around an altar of gold leaf. The gold is loose.", [
		_choice("Kneel with them", "The team gauge fills by 50.", _deal({"gauge": 50}), 0, null,
				"For a moment you feel the old kings' strength."),
		_choice("Pry off the gold", "70 gold. The kings may not allow it.", _deal({"gold": 70}), 60,
				_deal({"hp": 25}), "The gold comes away in sheets.", "The statues' eyes open. Everyone loses 25% HP."),
	]))
	list.append(_event("merchant_wreck", "Merchant's Wreck",
			"A wagon lies on its side in the mud, its horses long gone. Crates spill from the back.", [
		_choice("Search the crates", "Something rare. Something may live in there.", _deal({"find": 1}), 40,
				_deal({"hp": 15}), "Under the straw: something good.", "Rats! Everyone loses 15% HP."),
		_choice("Take the strongbox", "30 gold, quick and safe.", _deal({"gold": 30}), 0, null, "Heavy and full."),
	]))
	list.append(_event("whispering_mask", "The Whispering Mask",
			"A golden mask lies in the moss. It whispers how strong you could be.", [
		_choice("Put it on", "Every hero gets 70 XP. Its voice may be too much.", _deal({"xp": 70}), 50,
				_deal({"hp": 20}), "Visions of old battles fill your heads.", "It screams. Everyone loses 20% HP."),
		_choice("Wrap it up to sell", "A golden idol for the shop.", _deal({"item": idol}), 0, null,
				"It goes quiet in the dark of the pack."),
	]))
	for i: int in list.size():
		list[i] = _save(list[i], "res://data/events/%s.tres" % list[i].id) as EventData
	return list


func _event(id: String, title: String, text: String, choices: Array) -> EventData:
	var event := EventData.new()
	event.id = id
	event.title = title
	event.text = text
	event.picture_path = "res://assets/sprites/ui/map_event.png"
	event.choices.assign(choices)
	return event


func _choice(text: String, detail: String, deal: ZoneOfferData, risk: int, risk_deal: ZoneOfferData, done: String,
		risk_text: String = "") -> EventChoiceData:
	var choice := EventChoiceData.new()
	choice.text = text
	choice.detail = detail
	choice.deal = deal
	choice.risk_percent = risk
	choice.risk_deal = risk_deal
	choice.done_text = done
	choice.risk_text = risk_text
	return choice


## A deal from short keys: cost (gold), hp (percent lost), heal, gold, xp, gauge, item, find (rarity).
func _deal(d: Dictionary) -> ZoneOfferData:
	var deal := ZoneOfferData.new()
	deal.cost_gold = int(d.get("cost", 0))
	deal.cost_hp_percent = int(d.get("hp", 0))
	deal.heal_percent = int(d.get("heal", 0))
	deal.gold = int(d.get("gold", 0))
	deal.xp = int(d.get("xp", 0))
	deal.team_gauge = int(d.get("gauge", 0))
	deal.item = d.get("item") as ItemData
	deal.find_rarity = int(d.get("find", -1))
	return deal


func _save(res: Resource, path: String) -> Resource:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("bootstrap_phase15: could not save %s (%d)" % [path, err])
		return res
	_written += 1
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
