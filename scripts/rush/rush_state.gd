class_name RushState
extends RunState
## A Fight Rush in progress (DESIGN.md 8.21): fight after fight, each one a step deeper, with a
## reward pick (1 of 3 cards) after every win, until the party falls or gives up. Every 5th fight is
## an elite and every 10th the next boss of the cycle (tuning rush_elite_every, rush_boss_every).
## It shares a run's party, levels, Relics and backpack rules, so it is a RunState with no map and no
## gold; nothing from it is banked. Pure, like RunState: screens and Main
## only call these functions and show the result.

## What kind of fight a fight number is (kind_of).
enum Kind { NORMAL, ELITE, BOSS }

## The result of a Rush given up from the pause menu (a defeat uses RunState.DEFEAT).
const GAVE_UP := "gave_up"
## The result of a Rush stopped by the dev cap (--rush-fights).
const CAPPED := "capped"
## Salts for the seeded picks of each fight (apart from every RunState salt).
const RUSH_FIGHT_SALT: int = 319993813
const RUSH_LOOK_SALT: int = 341027533
const RUSH_OFFER_SALT: int = 362880011
const RUSH_WEATHER_SALT: int = 384160007
## The kinds of reward card in `offer`.
const CARD_HEAL := "heal"
const CARD_POINT := "point"
const CARD_ITEM := "item"
const CARD_RELIC := "relic"

## The data (not in to_dict: every machine has it).
var rush: RushData
## The last fight entered: 0 before the first. During a fight and on the reward picks after it, the
## fight it is; the ready screen shows fight + 1.
var fight: int = 0
## The first fight played (above 1 only for the dev head start, --rush-start).
var start_fight: int = 1
## The id of `fight`'s encounter: the base pool entry or the boss's (its deep version is looked up by
## encounter_now). "" at fight 0. Fixed by next_fight, so the next roll can skip it.
var encounter_id: String = ""
## Reward picks still to take after the last win.
var picks_left: int = 0
## Picks taken in this Rush (seeds each offer).
var pick_no: int = 0
## pick_no at the last win's first roll: that pick shows the fight's card set, later ones the normal set.
var first_pick_no: int = 0
## XP earned past the top level toward the next extra pick (tuning rush_spare_pick_xp).
var spare_xp: int = 0
## The most players seen in this Rush (the record it counts toward, RushRecords).
var most_players: int = 1
## The cards on show: {"kind": CARD_HEAL or CARD_POINT, "amount": int} or {"kind": CARD_ITEM or
## CARD_RELIC, "id": String}. Empty between a take and the next roll.
var offer: Array[Dictionary] = []

## Encounter id -> EncounterData over every tier pool and boss (built once, _encounter_by_id).
var _encounters: Dictionary = {}


## A new Rush of `rush_data` with this seed: level 1, the Relic bag of `collection` (no pact), no
## fight entered yet. `p_start_fight` above 1 replays the fights before it (head_start, dev only).
static func begin_rush(rush_data: RushData, p_tuning: Tuning, p_seed: int,
		collection: RelicCollection = null, p_start_fight: int = 1) -> RushState:
	var r := RushState.new()
	r.rush = rush_data
	r._start(rush_data.run, p_tuning, p_seed, 0, collection)
	r.pact_pending = false
	# No gold in a Rush (DESIGN.md 8.21), whatever purse a run starts with (run_start_gold, #321).
	r.gold = 0
	if p_start_fight > 1:
		r.head_start(p_start_fight)
	return r


## A Rush of `rush_data` set to to_dict() data. Null if the data does not fit (a run's, malformed).
static func from_rush_dict(rush_data: RushData, p_tuning: Tuning, d: Dictionary) -> RushState:
	if typeof(d.get("seed")) != TYPE_INT:
		return null
	var r := begin_rush(rush_data, p_tuning, int(d.seed))
	return r if r.apply_dict(d) else null


# --- RunState rules a Rush changes ----------------------------------------------------------------

func mode() -> String:
	return "rush"


## No map: current() is always {} and `at` stays -1.
func _make_map(_index: int, _rules: int = -1) -> RunMap:
	return RunMap.new()


## Fight n grows like map row n - 1 of a run (at rush_depth_per_fight_percent 100).
func _depth() -> int:
	@warning_ignore("integer_division")
	return maxi(0, fight - 1) * maxi(0, tuning.rush_depth_per_fight_percent) / 100


## A boss grows only by the depth past where a run meets it (RushBoss.home_depth).
func _fight_depth(_encounter: EncounterData) -> int:
	if kind_of(fight) == Kind.BOSS:
		var boss := boss_entry(fight)
		return maxi(0, _depth() - (boss.home_depth if boss != null else 0))
	return _depth()


## No oaths in a Rush; rush_enemy_hp_step_add grows HP on top of the run's per-row growth.
func enemy_hp_percent(encounter: EncounterData = null) -> int:
	return 100 + _fight_depth(encounter) * maxi(0, tuning.run_enemy_hp_row_percent + tuning.rush_enemy_hp_step_add)


func enemy_power_percent(encounter: EncounterData = null) -> int:
	return 100 + _fight_depth(encounter) * maxi(0, tuning.run_enemy_power_row_percent + tuning.rush_enemy_power_step_add)


## Boss fights (guards fought as bosses too) grow only with rush_scale_bosses.
func _scales(_encounter: EncounterData) -> bool:
	return kind_of(fight) != Kind.BOSS or tuning.rush_scale_bosses


func is_deep() -> bool:
	var tier := tier_of(fight)
	return tier != null and tier.deep


## Rarity grows with the Rush's depth.
func _row_of(_stop_id: int) -> int:
	return _depth()


## The run's setup, with no running away and the Rush's flat enemy multipliers.
func fight_setup(encounter: EncounterData, p_seed: int, opening: CombatSetup.Opening) -> CombatSetup:
	var setup := super(encounter, p_seed, opening)
	setup.can_run = false
	setup.enemy_hp_percent = CombatMath.percent(setup.enemy_hp_percent, tuning.rush_enemy_hp_percent)
	setup.enemy_power_percent = CombatMath.percent(setup.enemy_power_percent, tuning.rush_enemy_power_percent)
	return setup


## A boss fight pays at least rush_boss_min_xp; everything takes rush_xp_percent.
func xp_full(encounter: EncounterData) -> int:
	var least := tuning.rush_boss_min_xp if kind_of(fight) == Kind.BOSS else 0
	var own := RunState.encounter_xp(encounter) if encounter != null else 0
	return CombatMath.percent(maxi(own, least), tuning.rush_xp_percent)


func gold_for(_encounter: EncounterData) -> int:
	return 0


func shows_gold() -> bool:
	return false


## Any loss ends the Rush; a win never does.
func decides_run(fight_result: String) -> bool:
	return not is_over() and fight_result != VICTORY and fight_result != ESCAPED


## The run's fight end (XP, levels, the downed back up, a loss ends it), then the Rush's: the boss
## heal, the XP past the top level toward extra picks, and the first offer.
## Returns RunState.finish_fight's dictionary plus "picks" after a win.
func finish_fight(fight_result: String, party_hp: Array[int], encounter: EncounterData,
		recap: Dictionary = {}) -> Dictionary:
	var gained := fight_xp(encounter, party_hp) if fight_result == VICTORY else _zeros()
	# Measured before the XP goes in: add_xp drops what passes the top level.
	var spill := 0
	for slot: int in party_size():
		spill = maxi(spill, gained[slot] - xp_to_cap(slot))
	var out := super(fight_result, party_hp, encounter, recap)
	if fight_result != VICTORY:
		return out
	if kind_of(fight) == Kind.BOSS and tuning.rush_boss_heal_percent > 0:
		for slot: int in party_size():
			heal(slot, CombatMath.percent_min1(max_hp(slot), tuning.rush_boss_heal_percent), false)
	picks_left = 1
	spare_xp += spill
	var per_pick := maxi(1, tuning.rush_spare_pick_xp)
	while spare_xp >= per_pick:
		spare_xp -= per_pick
		picks_left += 1
	first_pick_no = pick_no
	roll_offer()
	out["picks"] = picks_left
	return out


func to_dict() -> Dictionary:
	var d := super()
	var cards: Array = []
	for card: Dictionary in offer:
		cards.append(card.duplicate())
	d["rush"] = {
		"fight": fight, "start": start_fight, "encounter_id": encounter_id,
		"picks": picks_left, "pick_no": pick_no, "first_pick_no": first_pick_no,
		"spare_xp": spare_xp, "most_players": most_players, "offer": cards,
	}
	return d


## The run's state and the "rush" block; a refusal changes nothing.
func apply_dict(d: Dictionary) -> bool:
	var block: Variant = d.get("rush")
	if not block is Dictionary or not _rush_block_fits(block as Dictionary):
		return false
	var b := block as Dictionary
	if not super(d):
		return false
	fight = int(b.fight)
	start_fight = int(b.start)
	encounter_id = String(b.encounter_id)
	picks_left = int(b.picks)
	pick_no = int(b.pick_no)
	first_pick_no = int(b.first_pick_no)
	spare_xp = int(b.spare_xp)
	most_players = int(b.most_players)
	var cards: Array[Dictionary] = []
	for card: Variant in b.offer:
		cards.append((card as Dictionary).duplicate())
	offer = cards
	return true


func _rush_block_fits(b: Dictionary) -> bool:
	for key: String in ["fight", "start", "picks", "pick_no", "first_pick_no", "spare_xp", "most_players"]:
		if typeof(b.get(key)) != TYPE_INT or int(b[key]) < 0:
			return false
	if int(b.start) < 1 or int(b.fight) < int(b.start) - 1 or int(b.first_pick_no) > int(b.pick_no):
		return false
	if int(b.most_players) < 1 or int(b.most_players) > PlayerRoster.MAX_PLAYERS:
		return false
	if typeof(b.get("encounter_id")) != TYPE_STRING:
		return false
	var id := String(b.encounter_id)
	if (int(b.fight) == 0) != id.is_empty() or (not id.is_empty() and _encounter_by_id(id) == null):
		return false
	if not b.get("offer") is Array:
		return false
	for card: Variant in b.offer:
		if not _card_fits(card):
			return false
	return true


func _card_fits(card: Variant) -> bool:
	if not card is Dictionary or typeof((card as Dictionary).get("kind")) != TYPE_STRING:
		return false
	var c := card as Dictionary
	match String(c.kind):
		CARD_HEAL, CARD_POINT:
			return typeof(c.get("amount")) == TYPE_INT and int(c.amount) >= 0
		CARD_ITEM:
			return typeof(c.get("id")) == TYPE_STRING and _rush_item(String(c.id)) != null
		CARD_RELIC:
			return typeof(c.get("id")) == TYPE_STRING and relic_by_id(String(c.id)) != null
	return false


# --- the fights ---------------------------------------------------------------------------------

## What kind of fight fight `n` is (n below 1: NORMAL).
func kind_of(n: int) -> Kind:
	if n < 1:
		return Kind.NORMAL
	if n % maxi(2, tuning.rush_boss_every) == 0:
		return Kind.BOSS
	if n % maxi(2, tuning.rush_elite_every) == 0:
		return Kind.ELITE
	return Kind.NORMAL


## The tier fight `n` draws from: the last one starting at or before it (null: no tiers).
func tier_of(n: int) -> RushTier:
	var found: RushTier = null
	if rush == null:
		return found
	for tier: RushTier in rush.tiers:
		if tier != null and tier.from_fight <= maxi(1, n):
			found = tier
	return found


## The boss of boss fight `n` (the cycle comes round again after the last); null for other fights.
func boss_entry(n: int) -> RushBoss:
	if kind_of(n) != Kind.BOSS or rush == null or rush.bosses.is_empty():
		return null
	@warning_ignore("integer_division")
	var index := (n / maxi(2, tuning.rush_boss_every) - 1) % rush.bosses.size()
	return rush.bosses[index]


## On to the next fight (only from the ready screen: no picks left, not over). Its encounter is
## rolled here, never the one just fought while its pool has another.
func next_fight() -> void:
	if picks_left > 0 or is_over():
		return
	var prev := encounter_id
	fight += 1
	var e := _roll_encounter(fight, prev)
	encounter_id = e.id if e != null else ""


## The fight `fight` is: its encounter, in its deep version in a deep tier when that has enemies
## (null at fight 0).
func encounter_now() -> EncounterData:
	if fight < 1:
		return null
	var base := _encounter_by_id(encounter_id)
	if base == null:
		return null
	var tier := tier_of(fight)
	if tier != null and tier.deep and base.deep != null and not base.deep.enemies.is_empty():
		return base.deep
	return base


## The place whose look, air and weather `fight` has: one of its tier's (seeded), or the boss's own
## (null: a boss fought in its own look only).
func zone_now() -> ZoneData:
	if kind_of(fight) == Kind.BOSS:
		var boss := boss_entry(fight)
		return boss.zone if boss != null else null
	var tier := tier_of(fight)
	if tier == null or tier.zones.is_empty():
		return null
	var rng := CombatRng.new(_salted(fight * RUSH_LOOK_SALT))
	return tier.zones[rng.range_int(0, tier.zones.size() - 1)]


## The look of `fight` before weather: the boss's own, else its place's.
func look_now() -> StageLook:
	var boss := boss_entry(fight)
	if boss != null and boss.look != null:
		return boss.look
	var zone := zone_now()
	return zone.look if zone != null else null


## The air (drifting motes and the like) of `fight`'s place (none without a place).
func air_now() -> Array[ZoneAmbientData]:
	var air: Array[ZoneAmbientData] = []
	var zone := zone_now()
	if zone != null:
		air.assign(zone.ambient)
	return air


## The weather of `fight`, rolled from its place's (seeded; null: clear, or no place).
func weather_now() -> WeatherData:
	var zone := zone_now()
	if zone == null:
		return null
	return WeatherData.pick(zone.weathers, zone.weather_weights, zone.clear_weight, _salted(fight * RUSH_WEATHER_SALT))


## The enemy numbers of `encounter` at `fight` (for the bots' AUTOPLAY_RUSH line and tests):
## {depth, hp, power, tempo}, the last three in percent as the fight gets them.
func fight_numbers(encounter: EncounterData) -> Dictionary:
	if encounter == null:
		return {"depth": _depth(), "hp": 0, "power": 0, "tempo": 0}
	var setup := fight_setup(encounter, 1, CombatSetup.Opening.NORMAL)
	return {"depth": _fight_depth(encounter), "hp": setup.enemy_hp_percent, "power": setup.enemy_power_percent,
			"tempo": setup.attack_tempo_percent}


func _roll_encounter(n: int, prev: String) -> EncounterData:
	if kind_of(n) == Kind.BOSS:
		var boss := boss_entry(n)
		return boss.encounter if boss != null else null
	var tier := tier_of(n)
	if tier == null:
		return null
	var pool := tier.elites if kind_of(n) == Kind.ELITE and not tier.elites.is_empty() else tier.fights
	var candidates: Array[EncounterData] = []
	for e: EncounterData in pool:
		if e != null and e.id != prev:
			candidates.append(e)
	if candidates.is_empty():
		for e: EncounterData in pool:
			if e != null:
				candidates.append(e)
	if candidates.is_empty():
		return null
	var rng := CombatRng.new(_salted(n * RUSH_FIGHT_SALT))
	return candidates[rng.range_int(0, candidates.size() - 1)]


func _encounter_by_id(id: String) -> EncounterData:
	if _encounters.is_empty() and rush != null:
		for tier: RushTier in rush.tiers:
			if tier == null:
				continue
			for list: Array[EncounterData] in [tier.fights, tier.elites]:
				for e: EncounterData in list:
					if e != null and not _encounters.has(e.id):
						_encounters[e.id] = e
		for boss: RushBoss in rush.bosses:
			if boss != null and boss.encounter != null and not _encounters.has(boss.encounter.id):
				_encounters[boss.encounter.id] = boss.encounter
	return _encounters.get(id) as EncounterData


# --- reward picks -------------------------------------------------------------------------------

## True while reward picks are left to take.
func picking() -> bool:
	return picks_left > 0


## Fills `offer` with the cards of the fight just won (its first pick: normal Heal, Train, Item;
## elite Heal, Train, Relic; boss Train, Relic, Relic) or of an extra pick (Heal, Train, Item),
## seeded by the fight and the pick. A Relic card offers one the party does not have (no copies,
## DESIGN.md 8.24). A card that cannot be filled is left out; no card at all ends the picks.
func roll_offer() -> void:
	offer.clear()
	var set_kind := kind_of(fight) if pick_no == first_pick_no else Kind.NORMAL
	var cards: Array[String] = [CARD_HEAL, CARD_POINT, CARD_ITEM]
	if set_kind == Kind.ELITE:
		cards = [CARD_HEAL, CARD_POINT, CARD_RELIC]
	elif set_kind == Kind.BOSS:
		cards = [CARD_POINT, CARD_RELIC, CARD_RELIC]
	var salt := fight * RUSH_OFFER_SALT + pick_no * 101
	var found_relics := _pick_gear(salt + 7, cards.count(CARD_RELIC), _depth(), tuning.rush_relic_min_rarity,
			GearPool.NORMAL, _dead_relics())
	for card: String in cards:
		match card:
			CARD_HEAL:
				offer.append({"kind": CARD_HEAL, "amount": tuning.rush_heal_card_percent})
			CARD_POINT:
				offer.append({"kind": CARD_POINT, "amount": tuning.rush_point_card_points})
			CARD_ITEM:
				var item := _offer_item(salt)
				if item != null:
					offer.append({"kind": CARD_ITEM, "id": item.id})
			CARD_RELIC:
				if not found_relics.is_empty():
					offer.append({"kind": CARD_RELIC, "id": (found_relics.pop_front() as GearData).id})
	if offer.is_empty():
		picks_left = 0


## After the last pick's gift settled (the item or Relic is in): the next pick's cards, if any.
func next_offer() -> void:
	if picks_left > 0:
		roll_offer()


## True if card `i` can be taken (Heal only while some hero would gain HP).
func card_enabled(i: int) -> bool:
	if i < 0 or i >= offer.size():
		return false
	if String(offer[i].get("kind", "")) == CARD_HEAL:
		var total := 0
		for slot: int in party_size():
			total += heal_card_gain(slot)
		return total > 0
	return true


## The percent of max HP the Heal card heals hero `slot`: rush_heal_card_percent changed by their Rest
## Relics, as the campfire's Rest is (Rain Pouch more, Hunger Charm nothing).
func card_heal_percent_of(slot: int) -> int:
	return CombatMath.percent(tuning.rush_heal_card_percent,
			clampi(100 + gear_amount(slot, GearData.Effect.REST_HEAL), 0, 1000))


## The HP the Heal card would give hero `slot` (after the healing they receive, never past max HP).
## Changes nothing.
func heal_card_gain(slot: int) -> int:
	if slot < 0 or slot >= hp.size():
		return 0
	var amount := CombatMath.percent(max_hp(slot), card_heal_percent_of(slot))
	amount = CombatMath.percent(maxi(amount, 0), maxi(0, 100 + gear_amount(slot, GearData.Effect.HEAL_TAKEN)))
	return clampi(hp[slot] + amount, 1, max_hp(slot)) - hp[slot]


## Takes card `i`: Heal heals everyone, Train gives everyone its points, a Relic goes to hero `hero`
## (DESIGN.md 8.24: the card cannot be taken without one); an item comes back in "give" for the caller
## to hand out (StopScreen.give adds it). One pick is used and the cards go; next_offer rolls the next
## ones once the gift settled. Returns {kind, give: ItemData or null, relic: the find (relic_find) or
## {}, hero, healed: HP per hero, points}, or {} if the card cannot be taken.
func take_card(i: int, hero: int = -1) -> Dictionary:
	if not picking() or is_over() or not card_enabled(i):
		return {}
	var card: Dictionary = offer[i]
	var healed: Array[int] = []
	var points := 0
	var give: Resource = null
	var relic := {}
	if String(card.kind) == CARD_RELIC:
		relic = give_relic(relic_by_id(String(card.id)), hero)
		if relic.is_empty():
			return {}
	match String(card.kind):
		CARD_HEAL:
			for slot: int in party_size():
				healed.append(heal(slot, CombatMath.percent(max_hp(slot), card_heal_percent_of(slot))))
		CARD_POINT:
			points = int(card.amount)
			for slot: int in bonus_points.size():
				bonus_points[slot] += points
		CARD_ITEM:
			give = _rush_item(String(card.id))
	picks_left -= 1
	pick_no += 1
	offer.clear()
	return {"kind": String(card.kind), "give": give, "relic": relic, "hero": hero if not relic.is_empty() else -1,
			"healed": healed, "points": points}


## The item or Relic card `i` offers (null: a Heal or Train card, or no such card). Changes nothing.
func card_thing(i: int) -> Resource:
	if i < 0 or i >= offer.size():
		return null
	match String(offer[i].get("kind", "")):
		CARD_ITEM:
			return _rush_item(String(offer[i].get("id", "")))
		CARD_RELIC:
			return relic_by_id(String(offer[i].get("id", "")))
	return null


func _rush_item(id: String) -> ItemData:
	if rush != null:
		for item: ItemData in rush.items:
			if item != null and item.id == id:
				return item
	return null


## An item for the item card: one the party wants, by find weight and rarity at this depth (null: none).
func _offer_item(salt: int) -> ItemData:
	var pool: Array[ItemData] = []
	var weights: Array = []
	if rush != null:
		for item: ItemData in rush.items:
			if RushData.offerable(item) and wants(item):
				pool.append(item)
				weights.append(rarity_weight(item.find_weight, item.rarity, _depth()))
	var index := RunState._weighted_index(CombatRng.new(_salted(salt)), weights)
	return pool[index] if index >= 0 else null


## Relics a card never offers: the gold ones (a Rush has no gold).
func _dead_relics() -> Array[GearData]:
	var dead: Array[GearData] = []
	for item: GearData in data.gear:
		if item != null and item.effect == GearData.Effect.GOLD:
			dead.append(item)
	return dead


# --- the Rush as a whole --------------------------------------------------------------------------

## Given up from the pause menu: the Rush ends where it is (HP kept, no defeat).
func give_up() -> void:
	if not is_over():
		result = GAVE_UP


## Stopped by the dev cap (--rush-fights).
func cap() -> void:
	if not is_over():
		result = CAPPED


## `count` players are in the party now: the record goes to the most seen.
func note_players(count: int) -> void:
	most_players = maxi(most_players, clampi(count, 1, PlayerRoster.MAX_PLAYERS))


## The fight the party reached (0: none entered yet).
func reached() -> int:
	return fight


## The fight reached in words, as the pause menu and the Rush end show it ("Fight 7"), or "" while
## no fight was entered yet (Give up on the first ready screen), so no "Fight 0" is ever shown.
func reached_text() -> String:
	return "Fight %d" % reached() if reached() > 0 else ""


## XP hero `slot` still needs to reach the top level (0 at it).
func xp_to_cap(slot: int) -> int:
	var need := 0
	for lv: int in range(levels[slot], tuning.run_max_level):
		need += tuning.run_xp_first_level + (lv - 1) * tuning.run_xp_level_step
	return maxi(0, need - xps[slot])


## Attribute and skill points the party has not spent (skill points only for heroes with a tree).
func unspent_points() -> int:
	var total := 0
	for slot: int in party_size():
		total += maxi(0, free_points(slot))
		if has_tree(slot):
			total += maxi(0, free_skill_points(slot))
	return total


## Dev only (--rush-start=N): plays fights 1 to n - 1 as perfect wins with the bot's picks (a Relic
## card first, given to the hero GearBot picks, else Train), through the same code real play uses, so
## the party has the XP, points and Relics a played Rush would have (no Heal or item picks). Everyone ends at full HP, fight n - 1.
func head_start(n: int) -> void:
	start_fight = maxi(1, n)
	for _k: int in range(1, start_fight):
		next_fight()
		var e := encounter_now()
		if e == null:
			break
		var full: Array[int] = []
		for slot: int in party_size():
			full.append(max_hp(slot))
		finish_fight(VICTORY, full, e, {})
		while picking():
			var pick := _bot_card()
			var thing := card_thing(pick)
			var to := GearBot.best_hero(self, thing as GearData) if thing is GearData else -1
			var got := take_card(pick, to)
			if got.is_empty():
				picks_left = 0
				break
			if got.give is ItemData:
				add_item(got.give as ItemData)
			next_offer()
	for slot: int in hp.size():
		hp[slot] = max_hp(slot)


## The head start's pick: the first Relic card, else the first Train card, else the first that can be taken.
func _bot_card() -> int:
	for wanted: String in [CARD_RELIC, CARD_POINT]:
		for i: int in offer.size():
			if String(offer[i].get("kind", "")) == wanted and card_enabled(i):
				return i
	for i: int in offer.size():
		if card_enabled(i):
			return i
	return -1
