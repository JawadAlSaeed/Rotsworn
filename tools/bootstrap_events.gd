extends SceneTree
## Writes the "?" events (DESIGN.md 8.7, card #193) and fills the three acts' event lists and ambush
## pools (three acts since card #323, DESIGN.md 8.23: each act's events and ambushes fit its place). Every choice costs something scarce (max HP for good, a backpack item, a curse, gold, an
## ambush fight); gold and XP rewards grow with depth by tuning.event_reward_row_percent (RunState).
## Rewrites every event file; run it after tools/bootstrap_phase15.gd (it edits the act files that
## one writes). Phase 26 (DESIGN.md 8.22, G2 and G3) added the shrines and wanderers as events (the
## Healing Spring, the Blood Altar, the War Idol, the Grave Robber) and took the Key out of the
## Hanging Cage; the ambush pools below include the phase 19 fights, so a re-run keeps them.
## Run: Godot --headless --path . -s tools/bootstrap_events.gd

const ENC := "res://data/encounters/"
const EVENTS := "res://data/events/"
## Each event's painted picture (tools/art_kit/assets/event_art.py, card #199): <this folder>/<event id>.png.
const PICTURE_DIR := "res://assets/sprites/events/"

var _written: int = 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVENTS))
	var events := {}
	for event: EventData in _all_events():
		events[event.id] = _save(event, EVENTS + event.id + ".tres")

	# Each act shares a few events with the act before it; the rest fit its own place (the forest's
	# scarecrow and cage, the bog's chapel and well, the ruins' shrines and doors). Every event is in at
	# least one act. Every ambush fight has a deep version, which a deep act or row fights instead
	# (RunState.ambush_encounter).
	var act1 := load("res://data/runs/acts/rotten_road.tres") as ActData
	act1.events.assign(_pick(events, ["gamblers_bones", "wounded_pilgrim", "rot_blossom", "hanging_cage",
			"merchant_wreck", "whispering_mask", "bone_collector", "hungry_scarecrow", "tithe_collector",
			"healing_spring", "war_idol", "grave_robber"]))
	act1.ambushes.assign(_encs(["bloat_and_gnat", "shade_and_gnat", "fly_pair", "rat_pack", "husk_trio",
			"tick_nest"]))
	act1.ambush_title = "An Ambush!"
	act1.ambush_text = "The mark on the map was bait. Something on the Rotten Road was waiting for you."
	act1.ambush_picture_path = PICTURE_DIR + "ambush_rotten_road.png"
	var act2 := load("res://data/runs/acts/drowned_mire.tres") as ActData
	act2.events.assign(_pick(events, ["weeping_well", "drowned_chapel", "black_mirror", "widows_wager",
			"healing_spring", "rot_blossom", "wounded_pilgrim", "merchant_wreck", "whispering_mask",
			"gamblers_bones"]))
	act2.ambushes.assign(_encs(["toad_and_fly", "lantern_trio", "fly_pair", "tick_nest", "rat_pack", "husk_trio"]))
	act2.ambush_title = "An Ambush!"
	act2.ambush_text = ("The black water lay still around the mark on the map. It was not empty. Something "
			+ "in the Mire was waiting for you.")
	act2.ambush_picture_path = PICTURE_DIR + "ambush_drowned_mire.png"
	var act3 := load("res://data/runs/acts/ashen_deep.tres") as ActData
	act3.events.assign(_pick(events, ["shrine_of_kings", "buried_cairn", "sealed_door", "blood_altar",
			"black_mirror", "widows_wager", "weeping_well", "grave_robber", "healing_spring", "whispering_mask",
			"merchant_wreck", "gamblers_bones", "bone_collector"]))
	act3.ambushes.assign(_encs(["hyena_pack", "hyena_and_fly", "priest_and_hyenas", "brute_and_rat",
			"slinger_trio", "shade_and_gnat"]))
	act3.ambush_title = "An Ambush!"
	act3.ambush_text = "The ashes shifted. What was lying in them was only waiting for you."
	act3.ambush_picture_path = PICTURE_DIR + "ambush_ashen_deep.png"
	_save(act1, "res://data/runs/acts/rotten_road.tres")
	_save(act2, "res://data/runs/acts/drowned_mire.tres")
	_save(act3, "res://data/runs/acts/ashen_deep.tres")
	print("bootstrap_events: wrote %d files" % _written)
	quit()


func _pick(by_id: Dictionary, ids: Array) -> Array[EventData]:
	var list: Array[EventData] = []
	for id: String in ids:
		list.append(by_id[id] as EventData)
	return list


func _encs(ids: Array) -> Array[EncounterData]:
	var list: Array[EncounterData] = []
	for id: String in ids:
		list.append(load(ENC + id + ".tres") as EncounterData)
	return list


# --- the events -----------------------------------------------------------------------------------
# A deal is a dictionary of short keys (see _deal). Gold and XP numbers are for the first row; the
# game scales them with depth.

func _all_events() -> Array[EventData]:
	var list: Array[EventData] = []

	# --- the first eight, reworked: every choice costs something scarce --------------------------
	list.append(_event("weeping_well", "The Weeping Well",
			"A well of black water whispers your names. Something glints far below.", [
		_choice("Drink deep", "It is sweet, and it takes a little of you.",
				{"maxhp": 4, "heal": 35}, 30, {"hp": 15},
				"The water is cold and sweet. You feel lighter, in more ways than one.",
				"It burns going down."),
		_choice("Drop a coin in", "Wish for strength. Something may wish back.",
				{"cost": 30, "gauge": 50}, 25, {"ambush": "toad_and_fly"},
				"The whispers turn to cheers.", "Something answers from below. It climbs."),
	]))
	list.append(_event("gamblers_bones", "Gambler's Bones",
			"A skeleton sits at a table of rotten wood, dice in its hand. It waits for a player.", [
		_choice("Roll the bones", "Win big, or lose the stake and more.",
				{"cost": 25, "gold": 80}, 55, {"cost": 100},
				"The dice come up sixes.", "The dice turn in the air. The skeleton takes its winnings, and then some."),
		_choice("Take its purse", "The dead do not like thieves.",
				{"gold": 60}, 55, {"hp": 10, "curse": "grave_moss"},
				"The purse is heavy.", "A bony hand closes on yours. Something grey creeps into your pack."),
	]))
	list.append(_event("wounded_pilgrim", "A Wounded Pilgrim",
			"A pilgrim lies in the road, bleeding through his robe. He clutches a satchel.", [
		_choice("Give him something from the pack", "He blesses what you give.",
				{"item_pick": true, "xp": 60, "heal": 20}, 0, {},
				"He blesses you and limps on. The road is easier."),
		_choice("Take the satchel", "A salve and coin. He might not be alone.",
				{"gold": 45, "item": "salve"}, 55, {"ambush": "hyena_and_fly"},
				"He is too weak to stop you.", "His hounds were watching."),
	]))
	list.append(_event("rot_blossom", "Rot Blossom",
			"A huge violet flower grows from a corpse. Its fruit smells of honey and graves.", [
		_choice("One of you eats the fruit", "It feeds all of you. It is poison to one.",
				{"maxhp": 6, "maxhp_to": "pick", "heal": 35}, 30, {"hp": 15},
				"Sweet and filling.", "Your stomachs turn."),
		_choice("Cut the seed pod", "Something rare inside. Spores drift.",
				{"find": 1, "curse": "grave_moss"}, 0, {},
				"The pod splits open, and the spores settle in your pack."),
	]))
	# Phase 26: the Key left the run (G3), so the cage gives the dead man's pack instead.
	list.append(_event("hanging_cage", "The Hanging Cage",
			"An iron cage hangs from a dead tree. The body inside still holds the key to it.", [
		_choice("Climb up", "The branch is old.",
				{"find": 0}, 45, {"maxhp": 6, "maxhp_to": "random", "hp": 15},
				"You open the cage with its own key. His pack is still inside.", "The branch snaps."),
		_choice("Fell the tree", "His pack, his purse and what hangs with him. The noise carries.",
				{"find": 0, "gold": 60, "ambush": "bloat_and_gnat"}, 0, {},
				"The cage splits open on the ground."),
	]))
	list.append(_event("shrine_of_kings", "Shrine of Old Kings",
			"Crowned statues kneel around an altar of gold leaf. The gold is loose.", [
		_choice("Kneel with them", "An old king takes a tithe of blood.",
				{"maxhp": 8, "maxhp_to": "pick", "gauge": 70, "xp": 40}, 0, {},
				"For a moment you feel the old kings' strength."),
		_choice("Pry off the gold", "The kings may not allow it.",
				{"gold": 100}, 55, {"ambush": "elite_twin_husks", "spoils": true},
				"The gold comes away in sheets.", "The statues' eyes open. Two of them stand."),
	]))
	list.append(_event("merchant_wreck", "Merchant's Wreck",
			"A wagon lies on its side in the mud, its horses long gone. Crates spill from the back.", [
		_choice("Search the crates", "Something rare. Something else may have found it first.",
				{"find": 1}, 45, {"ambush": "hyena_pack"},
				"Under the straw: something good.", "Not rats. The hyenas were feeding here."),
		_choice("Pry open the strongbox", "Your tools will not survive it.",
				{"gold": 70, "item_random": true}, 0, {},
				"The lock gives, and something of yours gives with it."),
	]))
	list.append(_event("whispering_mask", "The Whispering Mask",
			"A golden mask lies in the moss. It whispers how strong you could be.", [
		_choice("One of you puts it on", "The mask takes its price from the wearer.",
				{"maxhp": 8, "maxhp_to": "pick", "xp": 90}, 40, {"hp": 25},
				"Visions of old battles fill your head.", "It screams."),
		_choice("Wrap it up to sell", "A golden idol for the shop. It does not stay quiet.",
				{"item": "golden_idol", "curse": "grave_moss"}, 0, {},
				"It goes quiet in the dark of the pack. Almost."),
	]))

	# --- eight new ----------------------------------------------------------------------------------
	list.append(_event("bone_collector", "The Bone Collector",
			"A man in a coat of knucklebones sits in a hollow tree. \"Trade, traveller? I buy what the road gave you.\"", [
		_choice("Trade an item and some coin", "He gives something older than what you offer.",
				{"item_pick": true, "cost": 20, "find": 1}, 0, {},
				"He turns your gift over, grinning, and hands you something stranger."),
		_choice("Sell him a rib", "One of you pays in bone.",
				{"maxhp": 7, "maxhp_to": "pick", "gold": 110}, 0, {},
				"It does not hurt. That is the worst of it."),
	]))
	list.append(_event("hungry_scarecrow", "The Hungry Scarecrow",
			"A scarecrow on a post, its sack head stuffed with grain. The mouth is stitched shut, and still it moans.", [
		_choice("Feed it", "It eats what it is given, and gives back.",
				{"item_random": true, "heal": 40, "xp": 40}, 0, {},
				"The stitches strain. It sighs, and something warm passes through you."),
		_choice("Cut the stitches", "Coins in the straw. Teeth, too.",
				{"gold": 80, "xp": 40, "ambush": "shade_and_gnat"}, 0, {},
				"What lived in it comes out screaming."),
	]))
	list.append(_event("tithe_collector", "The Tithe Collector",
			"A hooded figure stands in the road with a bowl. It does not speak. The bowl is bone-dry, and the road behind it is gone.", [
		_choice("Pay in coin", "The bowl fills. The road comes back.",
				{"cost": 70, "heal": 30, "gauge": 40}, 0, {},
				"The coins ring on the bone. The road remembers you."),
		_choice("Pay in blood", "Everyone gives a little, for good.",
				{"maxhp": 6, "gold": 90, "xp": 40}, 0, {},
				"The bowl drinks. It leaves something in return."),
	]))
	list.append(_event("black_mirror", "The Black Mirror",
			"A mirror of black glass leans against a drowned oak. Your reflections look back a moment too long.", [
		_choice("Touch the glass", "Your reflections know a great deal.",
				{"maxhp": 5, "xp": 100}, 40, {"ambush": "shade_and_gnat"},
				"Your hands go in to the wrist. You come back knowing more.", "Your reflections step out."),
		_choice("Smash it", "The shards cut into the pack, and something beats in there.",
				{"gold": 90, "curse": "rotting_heart"}, 0, {},
				"Seven years of bad luck, paid in advance."),
	]))
	list.append(_event("drowned_chapel", "The Drowned Chapel",
			"A chapel sunk to its roof in black water. A bell still hangs in the tower, and something below keeps time with it.", [
		_choice("Ring the bell", "It heals. It also calls.",
				{"heal": 45, "maxhp": 5}, 50, {"ambush": "toad_and_fly"},
				"The sound rolls over the water. The wounds close.", "The drowned come to the call."),
		_choice("Take the silver from the altar", "It was left for someone. It is cold.",
				{"gold": 120, "curse": "grave_moss"}, 0, {},
				"The silver is cold. So is the thing that follows it into the pack."),
	]))
	list.append(_event("buried_cairn", "The Buried Cairn",
			"A cairn of grey stones, a name scratched on it. Fresh earth lies beside it. Someone dug here, and stopped.", [
		_choice("Dig", "Gold and an old blade. The keeper does not like it.",
				{"gold": 120, "find": 1, "ambush": "hyena_pack"}, 0, {},
				"The spade rings on something that is not stone."),
		_choice("Say the name over the stones", "Leave something behind for them.",
				{"item_pick": true, "gauge": 40, "xp": 60}, 0, {},
				"The wind stops. The name sounds like a door closing gently."),
	]))
	list.append(_event("sealed_door", "The Sealed Door",
			"A door of black iron in the hillside, sealed with rust and wax. Behind it, something pounds the slow beat of a heart.", [
		_choice("Break the seal", "A guard stands behind it. A good guard guards something good.",
				{"gold": 60, "ambush": "elite_shade_coven", "spoils": true}, 0, {},
				"The wax cracks. The beat stops."),
		_choice("Pick the lock", "Your tools stay in the lock.",
				{"item_pick": true, "gold": 80, "find": 1}, 0, {},
				"The beat slows. The door gives."),
	]))
	list.append(_event("widows_wager", "The Widow's Wager",
			"A woman in black sits by a cold fire, shuffling bone chips. \"My husband lost everything at this table. Do you want his seat?\"", [
		_choice("Take his seat", "Buy in, and see what the chips are worth.",
				{"cost": 40, "xp": 110}, 50, {"maxhp": 8, "maxhp_to": "random", "hp": 15},
				"The chips fall your way, and the fire warms.", "She smiles. Someone is lighter by the end."),
		_choice("Stake a hero's strength", "A rare prize, if the hand is good.",
				{"maxhp": 10, "maxhp_to": "pick", "find": 2}, 40, {"hp": 25, "curse": "rotting_heart"},
				"The hand is good. Her smile is gone.", "The hand is hers. Something is dealt back into your pack."),
	]))

	# --- the shrines and wanderers, now "?" events (phase 26, DESIGN.md 8.22 G2) ------------------
	list.append(_event("healing_spring", "The Healing Spring",
			"Under a broken arch, a stone basin brims with water that glows like moonlight. Old coins shine on the bottom.", [
		_choice("Leave a coin and drink", "Pay the spring, and it mends you.",
				{"cost": 35, "heal": 30}, 0, {},
				"The water is cold and clean. Your wounds close."),
		_choice("Fish out the coins", "Others paid the spring. It may want them back.",
				{"gold": 60}, 50, {"maxhp": 5, "maxhp_to": "random", "hp": 10},
				"A fistful of old coins, cold as ice.", "The glow dims, and one of you feels it go out inside."),
	]))
	list.append(_event("blood_altar", "The Blood Altar",
			"A stone altar, black with old blood. Red candles burn around a bowl that is never quite dry.", [
		_choice("Bleed into the bowl", "All of you give a little, for good. The altar gives back.",
				{"maxhp": 4, "find": 1}, 0, {},
				"The blood sinks into the stone. Something rises from the bowl."),
		_choice("Drink from the bowl", "It closes any wound. What it leaves behind stays.",
				{"curse": "rotting_heart", "heal": 50, "gauge": 30}, 0, {},
				"It is hot and thick. Your wounds close, and something takes root."),
	]))
	list.append(_event("war_idol", "The War Idol",
			"A horned idol squats over a heap of rusted swords and skulls. Warriors once paid it for victory.", [
		_choice("Lay down an offering", "Gold at its feet. It shares what the fallen knew.",
				{"cost": 40, "xp": 50}, 0, {},
				"Its eyes flare. Old battles fill your heads."),
		_choice("Bleed on its horns", "One of you feeds it. It feeds the fury of all.",
				{"maxhp": 5, "maxhp_to": "pick", "gauge": 60}, 0, {},
				"Blood runs down the horns. The air hums with war."),
	]))
	list.append(_event("grave_robber", "The Grave Robber",
			"A hooded man digs by lantern light, a sack at his feet. \"Fresh from the ground, friend. Buy, or keep walking.\"", [
		_choice("Buy what he dug up", "He swears it is rare.",
				{"cost": 50, "find": 1}, 0, {},
				"He hands it over, still wet with grave dirt."),
		_choice("Help him dig", "Half of what you find is yours. The dead may mind.",
				{"gold": 45, "find": 0}, 40, {"ambush": "husk_trio"},
				"You split the take by lantern light.", "The earth heaves. The dead climb out to stop you."),
	]))
	return list


func _event(id: String, title: String, text: String, choices: Array) -> EventData:
	var event := EventData.new()
	event.id = id
	event.title = title
	event.text = text
	event.picture_path = PICTURE_DIR + id + ".png"
	event.choices.assign(choices)
	return event


## A choice: its deal, the risk (percent and the risk's deal, {} for none) and the lines.
func _choice(text: String, detail: String, deal: Dictionary, risk: int, risk_deal: Dictionary, done: String,
		risk_text: String = "") -> EventChoiceData:
	var choice := EventChoiceData.new()
	choice.text = text
	choice.detail = detail
	choice.deal = _deal(deal)
	choice.risk_percent = risk
	choice.risk_deal = _deal(risk_deal) if risk > 0 else null
	choice.done_text = done
	choice.risk_text = risk_text
	return choice


## A deal from short keys. Prices: cost (gold), hp (percent of everyone's HP), maxhp (percent of max HP
## for good) with maxhp_to ("all", "pick", "random"), item_pick / item_random (a backpack item is
## lost), curse (a rotten item id), ambush (an encounter id) with spoils. Gifts: heal, gold, xp,
## gauge, item (an item id), find (rarity).
func _deal(d: Dictionary) -> ZoneOfferData:
	var deal := ZoneOfferData.new()
	deal.cost_gold = int(d.get("cost", 0))
	deal.cost_hp_percent = int(d.get("hp", 0))
	deal.cost_max_hp_percent = int(d.get("maxhp", 0))
	match String(d.get("maxhp_to", "all")):
		"pick":
			deal.cost_max_hp_target = ZoneOfferData.HpTarget.CHOSEN
		"random":
			deal.cost_max_hp_target = ZoneOfferData.HpTarget.RANDOM
	if bool(d.get("item_pick", false)):
		deal.cost_item = ZoneOfferData.ItemCost.CHOSEN
	elif bool(d.get("item_random", false)):
		deal.cost_item = ZoneOfferData.ItemCost.RANDOM
	if d.has("curse"):
		deal.cost_rotten = load("res://data/items/%s.tres" % d.curse) as ItemData
	if d.has("ambush"):
		deal.ambush = load(ENC + String(d.ambush) + ".tres") as EncounterData
		deal.ambush_spoils = bool(d.get("spoils", false))
	deal.heal_percent = int(d.get("heal", 0))
	deal.gold = int(d.get("gold", 0))
	deal.xp = int(d.get("xp", 0))
	deal.team_gauge = int(d.get("gauge", 0))
	if d.has("item"):
		deal.item = load("res://data/items/%s.tres" % d.item) as ItemData
	deal.find_rarity = int(d.get("find", -1))
	return deal


func _save(res: Resource, path: String) -> Resource:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("bootstrap_events: could not save %s (%d)" % [path, err])
		return res
	_written += 1
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
