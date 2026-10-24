class_name EventAutoplay
extends RefCounted
## What the test bot does at a "?" stop (`-- --autoplay --run`, card #193). It plays like a careful
## player, not like the rules: it takes a choice only if the reward is worth the price, never
## pays permanent max HP while any hero is hurt, walks into a possible ambush only while the party is
## fit for an elite fight (RunAutoplay.is_ready), takes a curse only for a big reward and values a
## heal only as far as the party is hurt (a spring is not worth gold at full HP). Pure, so a test can
## check its habits. These numbers are the bot's, not game rules.

## No permanent max-HP price while the weakest hero is under this percent of their HP.
const MAX_HP_MIN_LOWEST_PERCENT: int = 70
## A curse (a rotten item) is worth taking only for a reward worth at least this much (gold).
const CURSE_MIN_REWARD: int = 120
## Gold worth of one XP each, per hero, and of each healed percent (only up to what the party is
## missing on average), gauge point and found rarity step.
const XP_VALUE: int = 1
const HEAL_PERCENT_VALUE: int = 2
const GAUGE_VALUE: int = 1
const FIND_VALUES: Array[int] = [40, 110, 220]
const ITEM_VALUE: int = 60
## What the prices are worth to it, in gold.
const HP_PERCENT_VALUE: int = 2
const MAX_HP_PERCENT_VALUE: int = 8
const ITEM_COST_VALUE: int = 45
const CURSE_VALUE: int = 90
const AMBUSH_VALUE: int = 60
const SPOILS_VALUE: int = 120


## The choice to take: {index: int (-1: leave), pick: int (the hero slot or item uid it asks for,
## else -1)}. `health` is Main's reading: x the weakest hero's HP percent, y the average, z the
## lowest level.
static func decide(run: RunState, event: EventData, health: Vector3i) -> Dictionary:
	var best := {"index": -1, "pick": -1}
	if event == null:
		return best
	var best_net := -1
	for i: int in event.choices.size():
		var choice := event.choices[i]
		if choice.deal == null or not run.can_choose(choice, run.at):
			continue
		var pick := pick_for(run, choice.deal)
		if choice.deal.pick_kind() != ZoneOfferData.Pick.NONE and pick < 0:
			continue
		var net := net_worth(run, choice, health)
		if net >= 0 and net > best_net:
			best_net = net
			best = {"index": i, "pick": pick}
	return best


## The reward minus the price of a choice in gold, or -1 if the bot's habits forbid it.
static func net_worth(run: RunState, choice: EventChoiceData, health: Vector3i) -> int:
	var scale := run.event_scale(run.at)
	var reward := _reward_value(run, choice.deal, scale, health)
	var price := _price_value(choice.deal, scale, run.party_size())
	if not _habits_allow(choice.deal, reward, health, 100):
		return -1
	if choice.risk_percent > 0 and choice.risk_deal != null:
		if not _habits_allow(choice.risk_deal, reward, health, choice.risk_percent):
			return -1
		price += CombatMath.percent(_price_value(choice.risk_deal, scale, run.party_size()), choice.risk_percent)
	return reward - price if reward >= price else -1


## Whom or what a deal's pick should be: the healthiest hero for max HP (they have the most to
## spare), the cheapest item for an item. -1 if there is nothing to pick or nothing to ask.
static func pick_for(run: RunState, offer: ZoneOfferData) -> int:
	match offer.pick_kind():
		ZoneOfferData.Pick.HERO:
			var best := -1
			for slot: int in run.party_size():
				if not run.hero_can_lose_max_hp(slot):
					continue
				# The larger share of max HP left wins (cross-multiplied: no division).
				if best < 0 or run.hp[slot] * run.max_hp(best) > run.hp[best] * run.max_hp(slot):
					best = slot
			return best
		ZoneOfferData.Pick.ITEM:
			var cheapest := -1
			var cheapest_price := 1 << 30
			for uid: int in run.losable_uids():
				var price := run.entry_price(run.backpack.entry(uid))
				if price < cheapest_price:
					cheapest = uid
					cheapest_price = price
			return cheapest
	return -1


## The habits: curses only for big rewards, no max HP while hurt, no fight while unfit. `chance` is
## the percent the deal happens (100 for the choice itself, a risk's for its risk deal).
static func _habits_allow(offer: ZoneOfferData, reward: int, health: Vector3i, chance: int) -> bool:
	if offer.cost_rotten != null and chance >= 30 and reward < CURSE_MIN_REWARD:
		return false
	if offer.cost_max_hp_percent > 0 and chance >= 30 and health.x < MAX_HP_MIN_LOWEST_PERCENT:
		return false
	if offer.ambush != null and chance >= 30 and not RunAutoplay.is_ready(health):
		return false
	return true


## What a deal's reward is worth in gold. A heal counts only the percent the party is missing on
## average (health.y), so a full party does not pay for one.
static func _reward_value(run: RunState, offer: ZoneOfferData, scale: int, health: Vector3i) -> int:
	var total := CombatMath.percent(offer.gold, scale)
	total += CombatMath.percent(offer.xp, scale) * run.party_size() * XP_VALUE
	var missing := clampi(100 - health.y, 0, 100)
	total += mini(offer.heal_percent, missing) * HEAL_PERCENT_VALUE + offer.team_gauge * GAUGE_VALUE
	if offer.item != null:
		total += maxi(ITEM_VALUE, CombatMath.percent(offer.item.price, run.tuning.item_sell_percent))
	elif offer.find_rarity >= 0:
		total += FIND_VALUES[clampi(offer.find_rarity, 0, FIND_VALUES.size() - 1)]
	return total


static func _price_value(offer: ZoneOfferData, scale: int, party: int) -> int:
	var total := CombatMath.percent(offer.cost_gold, scale) + offer.cost_hp_percent * HP_PERCENT_VALUE
	if offer.cost_max_hp_percent > 0:
		var heroes := party if offer.cost_max_hp_target == ZoneOfferData.HpTarget.EVERYONE else 1
		total += offer.cost_max_hp_percent * MAX_HP_PERCENT_VALUE * heroes
	if offer.cost_item != ZoneOfferData.ItemCost.NONE:
		total += ITEM_COST_VALUE
	if offer.cost_rotten != null:
		total += CURSE_VALUE
	if offer.ambush != null:
		total += AMBUSH_VALUE - (SPOILS_VALUE if offer.ambush_spoils else 0)
		total = maxi(total, 0)
	return total
