extends SceneTree
## Writes the glossary (DESIGN.md 7.12, card #207): the topics and every term, into
## data/glossary/glossary.tres. Colours and words that the game already draws (hit kinds, defence
## readouts, status badges) are read from their one source (combat_visuals.tres, HudStyle) so the
## book can never disagree with the screen; tests/unit/test_glossary.gd keeps it so.
## Rewrites the whole file: after the first run, edit the .tres (or this list) by hand, not both.
## Run: Godot --headless --path . -s tools/bootstrap_glossary.gd

const PATH := "res://data/glossary/glossary.tres"
const UI := "res://assets/sprites/ui/"
const ENV := "res://assets/sprites/env/"
const ITEMS := "res://assets/sprites/items/"
const FX := "res://assets/sprites/fx/"
const NONE := Color(0.0, 0.0, 0.0, 0.0)

var _entries: Array[GlossaryEntry] = []
var _visuals: CombatVisuals


func _init() -> void:
	_visuals = load("res://data/presentation/combat_visuals.tres") as CombatVisuals
	var data := GlossaryData.new()
	data.topic_ids = PackedStringArray(["fight", "reading", "defence", "skills", "team", "foe_marks", "hero_marks",
			"hero_help", "dooms", "enemies", "map", "zones", "gear", "shops", "run"])
	data.topic_names = PackedStringArray(["The fight", "Reading attacks", "Defence", "Skills and AP", "Counters and team",
			"Marks on enemies", "Marks on heroes", "Help on heroes", "Dooms", "Enemies", "The map", "In a zone",
			"Gear and items", "Shops and camps", "The run"])
	_fight()
	_reading()
	_defence()
	_skills()
	_team()
	_foe_marks()
	_hero_marks()
	_dooms()
	_enemies()
	_map()
	_zones()
	_gear()
	_shops()
	_run()
	data.entries = _entries
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/glossary"))
	var err := ResourceSaver.save(data, PATH)
	print("bootstrap_glossary: %d terms in %d topics, saved (%d)" % [_entries.size(), data.topic_ids.size(), err])
	quit(0 if err == OK else 1)


func _e(topic: String, id: String, term: String, text: String, tag: String = "", icon: String = "", color: Color = NONE) -> void:
	var entry := GlossaryEntry.new()
	entry.id = id
	entry.topic = topic
	entry.term = term
	entry.text = text
	entry.tag = tag
	entry.icon_path = icon
	entry.color = color
	_entries.append(entry)


## A status term: the word and colour are the HUD's own, and so is its icon when it has one (the
## mark icons the hero panels draw, card #262).
func _status(topic: String, status: String, term: String, text: String) -> void:
	var icon := HudStyle.MARK_ICON_PATH % status
	_e(topic, "status_" + status, term, text, String(HudStyle.STATUS_NAMES[status]), icon if ResourceLoader.exists(icon) else "",
			HudStyle.STATUS_COLORS[status] as Color)


func _fight() -> void:
	_e("fight", "turn_order", "Turn order", "The row of portraits at the top shows who acts next. Speed decides it, so a quick enemy can act twice before a slow hero acts once.")
	_e("fight", "basic_attack", "Attack", "Always on the menu and always gives 1 AP. Press its ring for a bonus. Save your AP for skills.")
	_e("fight", "first_strike", "First strike", "In a zone, hit a roaming enemy before it touches you. Your whole party then acts before any enemy in that fight.",
			"FIRST STRIKE!", "", HudStyle.GOLD)
	_e("fight", "run_away", "Running away", "Hold the Run button until its ring fills, then make one slow press. Only a PERFECT press gets that hero out. Not against bosses, guards, elites or ambushes.")
	_e("fight", "downed", "Downed", "At 0 HP a hero is downed: no turns, cannot be targeted. Revive, Smelling Salts and the Team Ultimate bring them back. All three down ends the run.")
	_e("fight", "fight_items", "Items in a fight", "The Items button lists the backpack's usable things. Using one is the hero's action and costs AP. Used items are gone when the fight ends.")
	_e("fight", "whole_party", "Whole party", "The sign says WHOLE PARTY when an attack hits every hero. Every hero defends. If all of them defend perfectly, you strike back together.",
			"WHOLE PARTY")


func _reading() -> void:
	_e("reading", "hit_normal", "Normal hit", "A plain strike, drawn as a sword. Parry it or dodge it. A parry earns AP and keeps a counter alive; a dodge only saves you the damage.",
			"", UI + "hit_normal.png", _visuals.normal_hit_color)
	_e("reading", "hit_ground", "Ground hit", "A shockwave or rock spikes along the floor, with a purple glow under you. Only a jump avoids it. A dodge or a parry fails.",
			"", UI + "hit_ground.png", _visuals.ground_hit_color)
	_e("reading", "hit_rend", "Rend", "Bone-coloured claw marks. Only a parry stops it; a dodge or a jump fails. Rends come in hard fights.",
			"MUST PARRY", UI + "hit_rend.png", _visuals.rend_hit_color)
	_e("reading", "hit_sweep", "Sweep", "A green crescent. Only a dodge avoids it. A sweep has no perfect answer, so an attack with a sweep in it can never be countered.",
			"MUST DODGE", UI + "hit_sweep.png", _visuals.sweep_hit_color)
	_e("reading", "feint", "Feint", "A hit wearing a dashed orange ring. The enemy lunges, stops, holds, then really strikes. Wait for the real lunge.",
			"", "", _visuals.rhythm_feint_color)
	_e("reading", "thrown", "Thrown hit", "Spit, stones and bolts. The enemy throws from where it stands and the shot flies to you. It is still a normal hit: parry or dodge it as it arrives.",
			"", UI + "hit_normal.png", _visuals.normal_hit_color)
	_e("reading", "intent_sign", "The sign", "The sign under an enemy shows its next attack: name, who it targets and one icon per hit, spaced like the real rhythm. After the first hit lands, the icons hide.")
	_e("reading", "each_in_turn", "Each in turn", "Some attacks strike one hero per hit, in the order the sign shows (SWARM ROUND -> CASS > ALDER > BRIN). In co-op each player defends their own hits.")
	_e("reading", "marking_hit", "Marking hit", "A hit with a small coloured dot carries a mark. The sign adds [ROT], [BLIGHT], [WEAK] or [AP DRAIN]. It lands only if you fail to defend that hit and survive it.",
			"[ROT]", "", HudStyle.STATUS_COLORS["rotting"] as Color)


func _defence() -> void:
	_e("defence", "parry", "Parry", "Press as the hit lands. It stops normal hits and rends, and earns 1 AP. Parry every hit of an attack and that hero strikes back. The tightest timing.",
			"PARRY", "", HudStyle.PARRY)
	_e("defence", "dodge", "Dodge", "Stops normal hits and sweeps, and is the most forgiving timing. It earns nothing and cannot answer a rend or a ground hit.",
			"DODGE", "", HudStyle.DODGE)
	_e("defence", "jump", "Jump", "The only answer to a ground hit. Jump as the wave arrives; jumping into a normal hit fails. A jump counts as a perfect defence for counters.",
			"JUMP", "", HudStyle.JUMP)
	_e("defence", "wrong_button", "Wrong button", "Pressing the wrong defence still lets the hit land. The orange hint says which one it wanted: MUST PARRY on a rend, MUST DODGE on a sweep.",
			"JUMP!", "", HudStyle.WRONG)
	_e("defence", "early", "EARLY", "You pressed before the window opened. It shows how many milliseconds early, counts as a whiff, and locks your defence buttons for a moment.",
			"EARLY", "", HudStyle.EARLY)
	_e("defence", "late", "LATE", "You pressed after the window closed, and the hit landed. It shows how many milliseconds late. Like EARLY it is a whiff.",
			"LATE", "", HudStyle.LATE)
	_e("defence", "lockout", "Lockout", "A press that matches nothing locks your defence buttons, and pressing while locked restarts the lock. Mashing never works: one calm press per hit.",
			"", UI + "lock.png")
	_e("defence", "no_press", "MISS (defence)", "If you press nothing for a hit, it lands and MISS shows. A single miss costs only that hit, so keep calm and read the next one.",
			"MISS", "", HudStyle.MISS)


func _skills() -> void:
	_e("skills", "ap", "AP", "Action points, the blue pips under each hero. Skills cost AP. Attacks, parries and some skills give it. Each hero has their own, up to 9.",
			"", UI + "ap_pip.png", HudStyle.AP_TEXT)
	_e("skills", "skill_press", "Skill press", "Every skill has a ring to press as it closes, one per hit. How close you press decides PERFECT, GOOD or MISS for that hit.")
	_e("skills", "press_perfect", "PERFECT", "Pressed in the narrow gold band: extra damage, and if every press of the skill is PERFECT, the skill's bonus too.",
			"PERFECT", "", HudStyle.GOLD)
	_e("skills", "press_good", "GOOD", "Pressed inside the wider ring: normal damage, and the skill still works in full. It is also enough to start a follow-up.",
			"GOOD", "", HudStyle.TEXT)
	_e("skills", "press_miss", "MISS", "Too early, too late or no press: the hit still lands, but for half damage. A press that is too early uses that ring up.",
			"MISS", "", HudStyle.MISS)
	_e("skills", "follow_up", "Follow-up strike", "When a hero's skill lands, the others get a quick press. GOOD adds a small hit, PERFECT a bigger one, and both fill the team gauge. A miss does nothing.")
	_e("skills", "critical", "Critical hit", "A lucky hit for 150% damage, shown big and gold. Every hero has a small chance; Luck and some gear raise it. Enemies never crit.",
			"CRITICAL!", "", HudStyle.GOLD)
	_e("skills", "skill_tree", "Skill tree", "Each hero has three branches. The top skill of each is known from the start; deeper ones cost skill points. A hero brings five known skills into a fight.")


func _team() -> void:
	_e("team", "counter", "Counter", "Defend every hit of an attack perfectly (parries, and jumps on ground hits) and that hero strikes back hard. One dodge or one mistake and there is none.",
			"COUNTER!", "", HudStyle.GOLD)
	_e("team", "counter_chain", "Longer strings", "Every extra perfect hit in one attack makes the counter stronger, and mixing parries with jumps adds a bonus. The text says why: COUNTER x5, MIXED.",
			"COUNTER x5!", "", HudStyle.GOLD)
	_e("team", "team_counter", "Team counter", "When an attack hits the whole party and every hero defends every hit perfectly, you all strike as one. Heroes who fell cannot join.",
			"TEAM COUNTER!", "", HudStyle.GOLD)
	_e("team", "team_gauge", "Team gauge", "Fills when follow-ups land and with some skills. In a run it carries over to the next fight. When it is full the Team Ultimate is ready.",
			"", "", HudStyle.GAUGE_FILL)
	_e("team", "team_ultimate", "Team Ultimate", "With a full gauge, any hero can call it on their turn. All heroes strike together for big damage and downed allies stand up again. It costs no AP.",
			"", "", HudStyle.GAUGE_FILL)
	_e("team", "taunt", "Taunt", "Alder's Taunt forces the enemy's next single-target attack onto him. He then parries it and counters, so it is how a tank is made.",
			"TAUNTED", "", HudStyle.STATUS_COLORS["taunted"] as Color)


func _foe_marks() -> void:
	_status("foe_marks", "exposed", "Exposed", "Cass's Reveal leaves it. The next damaging skill on that enemy removes it for 50% more damage (Rend: 150% more). It does not stack.")
	_status("foe_marks", "marked", "Marked", "Brin's Death Mark. The next few damaging skills on that one enemy deal 40% more, and each skill that lands uses one up.")
	_status("foe_marks", "bleeding", "Bleeding", "At the start of each of its turns the enemy loses a share of the hero's power, for a few turns. Weakened heroes make it bleed less.")
	_status("foe_marks", "slowed", "Slowed", "Its turns come later. Hamstring slows an enemy, so your party acts more between its attacks; a toad's mud or a shade's cold slows a hero the same way.")
	_status("foe_marks", "shielded", "Shielded", "A Rot Priest's ward on a fellow monster: it takes much less damage for a few of its turns. Kill the priest first, or hit someone else.")


func _hero_marks() -> void:
	_e("hero_marks", "mark", "Marks", "A hit with a coloured dot leaves its mark if you fail to defend it. In a run they start after the first zone; elites, guards and bosses mark everywhere. Defend the dot!")
	_status("hero_marks", "rotting", "Rot", "At the start of each of the hero's turns they lose a share of max HP, though never below 1 HP from rot alone. It counts down.")
	_status("hero_marks", "burning", "Burn", "Fire: at the start of each of the hero's turns they lose a big share of max HP, for fewer turns than rot. Never below 1 HP from fire alone.")
	_status("hero_marks", "shocked", "Shock", "The hero's timing windows shrink: parries, dodges, jumps, skill presses and follow-ups all need a sharper press while it lasts.")
	_status("hero_marks", "dazed", "Daze", "The hero loses their next turn. Only big must-parry slams daze, so a parry saves the turn.")
	_status("hero_marks", "hushed", "Hush", "The hero can use no skills, only Attack, items, Run and the team ultimate, until it wears off.")
	_status("hero_marks", "blighted", "Blight", "Healing the hero receives is cut in half for a few turns. Skills, Renew, items and gear all count.")
	_status("hero_marks", "weakened", "Weakened", "The hero's power is cut by a quarter for a few turns: skills, follow-ups, counters and the bleed they cause.")
	_e("hero_marks", "ap_drain", "AP drain", "A hit that drains takes AP from the hero when you fail to defend it. They never go below 0, but a planned skill may become too dear.",
			String(HudStyle.STATUS_NAMES["ap_drain"]), "", HudStyle.STATUS_COLORS["ap_drain"] as Color)
	_e("hero_marks", "cleanse", "Cleanse", "Mend and Sanctuary lift one mark, every mark on a PERFECT press. Purify lifts them all. A Salve lifts one, an Antidote all of one hero's, Holy Water everyone's. Marks end with the fight.")
	_status("hero_help", "warded", "Ward", "Cass's Purify: no mark can land on the hero for a few of their turns. Some Relics ward a hero at the start of a fight.")
	_status("hero_help", "guarded", "Guarded", "A guarded hero takes half damage until their next turn. Alder's Guard and Shield Wall give it.")
	_status("hero_help", "riposte", "Riposte", "Alder's Riposte Stance: until his next turn his counters hit twice as hard.")
	_status("hero_help", "regen", "Renew", "Cass's Renew heals the hero a share of max HP at the start of each of their turns, for a few turns.")
	_status("hero_help", "empowered", "Empowered", "The hero's next damaging skill on an enemy deals 30% more, then the bonus is gone.")


func _dooms() -> void:
	_e("dooms", "doom", "Doom", "A huge party-wide string that a guard or boss announces ahead of time. It gathers for a few of its turns, then unleashes. The sign counts the turns down.",
			"DOOM IN 2", "", _visuals.doom_text_color)
	_e("dooms", "break", "Break", "While a Doom gathers, all the damage the party deals fills its BREAK bar. Fill it and the Doom is cancelled. Skills, counters and bleed all count.",
			"BREAK", "", _visuals.break_bar_color)
	_e("dooms", "broken", "Broken", "A broken Doom is cancelled and goes on cooldown. The enemy is staggered and announces a new move at once.",
			"BROKEN!", "", _visuals.break_bar_color)
	_e("dooms", "stagger", "Stagger", "A staggered enemy loses its next turn and takes extra damage from everything until then. TURN LOST shows when the stagger ends.",
			"STAGGERED", "", _visuals.stagger_text_color)
	_e("dooms", "buying_turns", "Buying turns", "Slowing or pushing back a gathering enemy never cancels its Doom, but it gives your party more turns inside the window to break it.")


func _enemies() -> void:
	_e("enemies", "roaming", "Roaming enemy", "Seen walking in a zone. Touch one and the fight begins; strike it first for FIRST STRIKE. All but the guard are optional: more gold and XP, more risk.")
	_e("enemies", "elite", "Elite", "A tougher fight: more health, harder hits and better pay, with the hard-fight rends and sweeps. Met on skull stops and as zone champions. You cannot run.",
			"ELITE", "", Color(0.85, 0.45, 1.0))
	_e("enemies", "guard", "Guard", "Each zone's mini-boss at the far end, with a second phase at half health and a Doom of its own. Beating it clears the zone and gives spoils.",
			"GUARD", "", HudStyle.GOLD)
	_e("enemies", "champion", "Champion", "An elite that stands still beside a prize chest and never chases you. Beat it and the chest opens with no key. Optional.",
			"ELITE", "", Color(0.85, 0.45, 1.0))
	_e("enemies", "boss", "Boss", "An act's last fight: The Husk Lord, then The Hollow King. Its name is announced, it has a second phase and a Doom, and you cannot run.")
	_e("enemies", "phase_two", "Phase two", "At half health a guard or boss rages: a banner, new attacks and faster strings. It picks a new move at once.")
	_e("enemies", "deep_variant", "Deep variant", "A tougher, recoloured kin met in the second half of a run (Ashen Husk, Blight Bloat and so on). Same body, one new move, and rends and sweeps everywhere.")
	_e("enemies", "hard_fight", "Hard fight", "Elites, guards, bosses and deep variants add forced hits (rends, sweeps and feints) and marks that ordinary early fights do not have.")
	_e("enemies", "depth", "Depth", "Every map row deeper, enemies gain health and power and their strings come faster. The sign still tells the truth about each one.")
	_e("enemies", "support", "Helpers", "Some monsters help instead of striking: a Rot Priest heals a wounded fellow or shields one. Its sign names the monster it will help. Kill helpers first.",
			"", "", HudStyle.HEAL)
	_e("enemies", "burst", "Burst", "A Pus Tick announces its Burst like a Doom: a few turns later it bursts on the whole party and is gone. Kill it first, or jump the burst.",
			"DOOM IN 3", "", _visuals.doom_text_color)
	_e("enemies", "targeting", "Who they pick", "Hunters such as hyenas and shades favour wounded heroes, guards and bosses the weakest. Nobody is ever safe, and Taunt overrides it all.")


func _map() -> void:
	_e("map", "stop_zone", "Zone stop", "A place to explore, left to right. Beat the guard at the far end to move on; everything else is optional. Each zone stop is a different place.",
			"", UI + "map_zone_rotten_hollow.png")
	_e("map", "stop_elite", "Elite stop", "A skull over crossed blades: one hard fight, then spoils of rare gear or better. It cannot be run from.",
			"", UI + "map_elite.png")
	_e("map", "stop_event", "Event stop", "A red question mark: a story with a choice. Every choice has a price, and some turn into a fight. Leave is always there.",
			"", UI + "map_event.png")
	_e("map", "stop_treasure", "Treasure stop", "A gold-banded chest. Open it for some gold and a prize: a piece of gear or an item.",
			"", UI + "map_treasure.png")
	_e("map", "stop_rest", "Campfire stop", "A fire to gather round. Pick one thing: Rest, Train or Upgrade.",
			"", UI + "map_rest.png")
	_e("map", "stop_shop", "Shop stop", "The Rag Merchant sells items, charms and gear, and buys what your backpack holds.",
			"", UI + "map_shop.png")
	_e("map", "stop_lair", "Boss lair", "The last stop of an act. Beat the boss for spoils and a heal for everyone, then the next act's map opens.",
			"", UI + "map_lair_husk_lord.png")
	_e("map", "party_flag", "Flag and circle", "The flag marks where your party is. A red pen circle marks the stop you have picked; left and right choose the next one.",
			"", UI + "map_flag.png")
	_e("map", "planning", "Planning a road", "Once a next stop is picked, every stop and road it cannot lead to fades. Look up the map: a shop or a fire often matters more than one more fight.")


func _zones() -> void:
	_e("zones", "seal", "Rot seal", "A glowing standing stone, one in each middle part of a zone, often down a side path or past enemies. Walk up and use Confirm to take it.",
			"", ENV + "seal_stone.png")
	_e("zones", "gate", "Rot gate", "A wall of rotten roots in front of the guard. It stays shut until the party has two of the zone's three seals.",
			"", ENV + "rot_gate.png")
	_e("zones", "shrine", "Shrine", "Walk up and pray: a yes or no with the price and the gift written out. Springs heal, altars take blood for a find, idols fill the gauge. Each works once.",
			"", ENV + "shrine_altar.png")
	_e("zones", "wanderer", "Wanderer", "A traveller who turns up in some visits. Talk to them for a deal: the Key Peddler sells keys, the Grave Robber rare finds, the Old Pilgrim heals for free.",
			"", ENV + "wanderer_peddler.png")
	_e("zones", "glint", "Glinting spot", "A sparkle on the ground. Walk up and pick it up for an item or some treasure. With no room, the backpack opens so you can make some.",
			"", FX + "glint.png")
	_e("zones", "chest", "Locked chest", "Holds a rare or better prize, and uses up one Key from the backpack. A champion's prize chest needs no key.",
			"", ENV + "chest_closed.png")
	_e("zones", "shuffled", "A new zone each time", "Every visit builds the zone from shuffled parts, so seals, shrines, wanderers and enemies stand somewhere new.")


func _gear() -> void:
	_e("gear", "gear", "Gear", "Worn by one hero: three slots each, one effect per piece (power, a counter bonus, AP at the start). Gear never goes in the backpack.",
			"", UI + "gear_icon.png")
	_e("gear", "rarity", "Rarity", "Grey is common, blue is rare, gold is legendary. Rarer pieces are stronger and cost more, and deeper map rows turn them up more often.",
			"", "", Color(1.0, 0.8, 0.3))
	_e("gear", "rot_touched", "Rot-touched gear", "Strong gear with a price: a clear gain and a clear loss, written in plain words. Spoils from elites and bosses offer one. Take it with open eyes.",
			"rot-touched", "", GearData.ROT_TOUCHED_COLOR)
	_e("gear", "backpack", "Backpack", "A grid that holds consumables, charms, keys and treasure. Items have shapes you can turn, so where they sit matters. Open it from the party screen.",
			"", ITEMS + "bigger_pack.png")
	_e("gear", "charm", "Charm", "Works just by sitting in the backpack, for the whole party. Charms belong to a family (Stone, Bone, Herb), and booster charms strengthen the family charms touching them.",
			"", ITEMS + "ember_stone.png")
	_e("gear", "rotten_item", "Rotten item", "A very strong charm with a price: every hero loses a little HP at the start of each turn in a fight. It cannot be sold. Cleanse at a shop throws one away.",
			"", ITEMS + "rotting_heart.png", Color(0.55, 0.85, 0.3))
	_e("gear", "consumable", "Consumable", "Used up. A Salve heals one hero, a Feast the party, a Bomb hurts every enemy, Smelling Salts lift a downed hero, an Antidote or Holy Water lifts marks. In a fight they cost AP.",
			"", ITEMS + "salve.png")
	_e("gear", "tonic", "Tonic", "Gives one hero more max HP for the rest of the run. A hero can drink only two, and Tonics cannot be combined or upgraded.",
			"", ITEMS + "tonic.png")
	_e("gear", "key_treasure", "Keys and treasure", "A Key opens one locked chest. Treasure (rings, gems, idols) does nothing but sell for gold, and it takes up room.",
			"", ITEMS + "key.png")
	_e("gear", "combine", "Combine", "Put an item onto the same item at the same level and it goes up a level (Salve+), with a stronger effect. Consumables and charms only.")


func _shops() -> void:
	_e("shops", "shop", "The Rag Merchant", "Sells items, charms and gear for gold, and buys backpack items for half their price. The shelves change at every shop.",
			"", ENV + "shopkeeper.png")
	_e("shops", "shop_cleanse", "Cleanse", "A shop service: throw away one rotten item for good.")
	_e("shops", "shop_upgrade", "Upgrade", "Pay to raise one backpack item by a level. At a campfire the same upgrade is free, but it is your one choice there.")
	_e("shops", "shop_restock", "Restock", "Pay for fresh stock on the shelves. Each restock at the same shop costs more than the last.")
	_e("shops", "camp_rest", "Rest", "Everyone heals half of their max HP. It works once, and it is the one choice you make at that fire.",
			"", UI + "map_rest.png")
	_e("shops", "camp_train", "Train", "Every hero gets one attribute point to spend.")
	_e("shops", "event_choice", "Event choices", "A choice spells out its price and reward. Prices can be gold, max HP for good, a backpack item or a curse. Some carry a risk, and some start an ambush.",
			"", UI + "map_event.png")
	_e("shops", "spoils", "Spoils", "The prize after a guard, an elite or an act's boss: pick one of three pieces of gear, rare or better. One of the three is usually rot-touched.")


func _run() -> void:
	_e("run", "the_run", "The run", "A road through the map to the last boss, over two acts: The Rotten Road and The Ashen Deep. If the whole party falls it is over. Only your oaths and Journal carry on.")
	_e("run", "oath", "Oath", "A difficulty you pick before a run. Each oath adds a hardship to those before it and nothing ever makes the run easier. Win at Oath N to unlock N + 1.")
	_e("run", "oath_list", "The ten oaths", "Thorns, Want, Embers, the Deep, Crowns, Wounds, Scarcity, Silence, the Long Road, Rot. The players screen lists what each one does.")
	_e("run", "gold", "Gold", "Earned from fights and chests, spent in shops and at some shrines. Elites pay more, and the Oath of Want pays less.")
	_e("run", "level", "Level and XP", "Each hero levels on their own from fights. A level gives attribute points, a skill point and a little HP and power.")
	_e("run", "attributes", "Attributes", "Vitality raises max HP, Might power, Agility speed, Defense cuts enemy hits and Luck critical chance. Points can be taken back and a reset is free.")
	_e("run", "hp_carries", "HP carries over", "Health does not refill between fights. Campfires, shops and shrines are where you mend. Marks and AP start fresh each fight.")
	_e("run", "save_quit", "Save and Quit", "In the pause menu: keeps the run for later and goes to the main menu. Abandon run loses it for good.")
	_e("run", "journal", "Rot Journal", "In Extras: a book of every enemy and attack you meet in a run, with your record against each. Nothing in it changes a fight.")
