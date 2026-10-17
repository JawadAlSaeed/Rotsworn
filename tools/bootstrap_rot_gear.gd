extends SceneTree
## Writes the rot-touched gear (DESIGN.md 8.16, card #198): strong pieces that cost something. One
## file each in data/gear/, then added to the run's gear list (pieces already listed are kept).
## Run: Godot --headless --path . -s tools/bootstrap_rot_gear.gd

const RUN_PATH := "res://data/runs/rotten_road.tres"
const G := GearData.Effect
const RARE := ItemData.Rarity.RARE
const LEGENDARY := ItemData.Rarity.LEGENDARY


func _init() -> void:
	var pieces: Array[GearData] = [
		_piece("rotten_crown", "Rotten Crown", "Power +35%, but the healing you receive is 40% weaker.",
				120, LEGENDARY, G.POWER, 35, G.HEAL_TAKEN, 40),
		_piece("gravebound_ring", "Gravebound Ring", "Counters hit 80% harder, but your max HP is 15% lower.",
				100, RARE, G.COUNTER, 80, G.MAX_HP, 15),
		_piece("hunger_charm", "Hunger Charm", "Each kill heals you 8% of your max HP, but the campfire's Rest heals you nothing.",
				90, RARE, G.KILL_HEAL, 8, G.REST_HEAL, 100),
		_piece("last_ember", "Last Ember", "Power +40% while your HP is under 30%.",
				90, RARE, G.LOW_HP_POWER, 40),
		_piece("ash_veil", "Ash Veil", "Each dodge gives +1 AP, but a parry gives no AP.",
				80, RARE, G.DODGE_AP, 1, G.PARRY_AP, 1),
		_piece("thorned_gauntlet", "Thorned Gauntlet", "Enemies that hit you take 30% of the damage back, but you take 10% more.",
				100, RARE, G.THORNS, 30, G.TOUGH, 10),
		_piece("oathbreakers_band", "Oathbreaker's Band", "+2 AP at the start of every fight, but you lose 5% max HP after each fight won.",
				110, LEGENDARY, G.START_AP, 2, G.WIN_WOUND, 5),
		_piece("chain_of_silence", "Chain of Silence", "Your skills and follow-ups fill the team gauge 50% more, but you start fights with 1 AP less.",
				80, RARE, G.GAUGE, 50, G.START_AP, 1),
		_piece("bloodletters_fang", "Bloodletter's Fang", "Critical hit chance +25%, but you lose 4% max HP at the start of each of your turns.",
				90, RARE, G.CRIT, 25, G.ROT, 4),
		_piece("hollow_mantle", "Hollow Mantle", "Enemy hits deal 25% less, but you are 10 slower.",
				90, RARE, G.TOUGH, 25, G.SPEED, 10),
		_piece("pale_tithe", "Pale Tithe", "Perfect skill presses deal +40%, but the heals you give are 50% weaker.",
				80, RARE, G.PERFECT_PRESS, 40, G.HEAL, 50),
		_piece("plague_bell", "Plague Bell", "Hits on Exposed enemies deal +90% more, but your Power is 10% lower.",
				90, RARE, G.EXPOSED, 90, G.POWER, 10),
	]
	var run := load(RUN_PATH) as RunData
	var have := {}
	for item: GearData in run.gear:
		have[item.id] = true
	var added := 0
	for piece: GearData in pieces:
		if not have.has(piece.id):
			run.gear.append(piece)
			added += 1
	var err := ResourceSaver.save(run, RUN_PATH)
	if err != OK:
		push_error("bootstrap_rot_gear: could not save %s (%d)" % [RUN_PATH, err])
	print("bootstrap_rot_gear: wrote %d pieces, %d new in the run (%d gear in all)" % [pieces.size(), added, run.gear.size()])
	quit()


## One piece saved to disk (and loaded back, so the run points at the file). `drawback_amount` 0:
## no drawback.
func _piece(id: String, title: String, desc: String, price: int, rarity: ItemData.Rarity, effect: GearData.Effect,
		amount: int, drawback: GearData.Effect = GearData.Effect.MAX_HP, drawback_amount: int = 0) -> GearData:
	var item := GearData.new()
	item.id = id
	item.display_name = title
	item.description = desc
	item.price = price
	item.rarity = rarity
	item.effect = effect
	item.amount = amount
	item.rot_touched = true
	item.drawback = drawback
	item.drawback_amount = drawback_amount
	var path := "res://data/gear/%s.tres" % id
	var err := ResourceSaver.save(item, path)
	if err != OK:
		push_error("bootstrap_rot_gear: could not save %s (%d)" % [path, err])
		return item
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as GearData
