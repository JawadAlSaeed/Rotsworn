extends GutTest
## Backpack items in fights (DESIGN.md 8.1): the run hands the fight its usable items; a hero uses
## one as the turn's action (AP spent, the turn ends); heals, revives and bombs do what they say;
## a used item is gone and cannot be used twice; wrong targets are refused; the mirror and a
## restored engine agree; the run takes the used items out of the backpack afterwards.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const HUSKS := "res://data/encounters/husk_fight.tres"

var _tuning := Tuning.new()
var _data: RunData


func before_all() -> void:
	_data = load(RUN_PATH) as RunData


## A run with the given items in its backpack, and its fight against husks (party first).
func _fight(ids: Array[String]) -> Dictionary:
	var run := RunState.begin(_data, _tuning, 5)
	var uids: Array[int] = []
	for id: String in ids:
		uids.append(run.add_item(run.items_by_id()[id] as ItemData))
	var setup := run.fight_setup(load(HUSKS) as EncounterData, 9, CombatSetup.Opening.FIRST_STRIKE)
	var engine := CombatEngine.new(setup)
	var mirror := CombatMirror.new()
	for ev: Dictionary in engine.start():
		mirror.apply(ev)
	return {"run": run, "engine": engine, "mirror": mirror, "uids": uids, "setup": setup}


func _use(f: Dictionary, uid: int, targets: Array[int]) -> Array[Dictionary]:
	var engine := f.engine as CombatEngine
	var events := engine.submit(CombatCommands.use_item(engine.turn_number, engine.active_actor, uid, targets))
	for ev: Dictionary in events:
		(f.mirror as CombatMirror).apply(ev)
	return events


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(ev: Dictionary) -> String: return String(ev.type))


func test_only_fight_items_reach_the_fight() -> void:
	var f := _fight(["salve", "bomb", "grave_moss", "silver_ring"])
	var setup := f.setup as CombatSetup
	assert_eq(setup.items.size(), 2, "the salve and the bomb; the curse and the ring never sit in the pack")
	assert_eq((f.engine as CombatEngine).items_left.size(), 2)
	assert_eq((f.mirror as CombatMirror).items.size(), 2, "the menu knows them from combat_started")


func test_a_salve_heals_one_ally_spends_ap_and_ends_the_turn() -> void:
	var f := _fight(["salve"])
	var engine := f.engine as CombatEngine
	var actor := engine.get_combatant(engine.active_actor)
	actor.ap = 3
	var target := engine.get_combatant(engine.party_ids()[1])
	target.hp = 1
	var turn := engine.turn_number
	var events := _use(f, f.uids[0], [target.id])
	assert_has(_types(events), "item_used")
	assert_eq(target.hp, 1 + CombatMath.percent_min1(target.max_hp, 50))
	assert_eq(actor.ap, 2, "1 AP spent")
	assert_gt(engine.turn_number, turn, "the turn ended")
	assert_eq(engine.items_left.size(), 0)
	assert_eq((f.mirror as CombatMirror).used_items, [f.uids[0]] as Array[int])


func test_an_item_cannot_be_used_twice_or_on_a_wrong_target() -> void:
	var f := _fight(["salve", "smelling_salts"])
	var engine := f.engine as CombatEngine
	engine.get_combatant(engine.active_actor).ap = 3
	var events := _use(f, f.uids[1], [engine.party_ids()[0]])
	assert_eq(String(events[0].type), "command_rejected", "salts need someone downed")
	events = _use(f, 999, [engine.party_ids()[0]])
	assert_eq(String(events[0].reason), "unknown_item")
	_use(f, f.uids[0], [engine.party_ids()[0]])
	engine.get_combatant(engine.active_actor).ap = 3
	if engine.phase == CombatEngine.Phase.AWAITING_ACTION:
		events = _use(f, f.uids[0], [engine.party_ids()[0]])
		assert_eq(String(events[0].reason), "unknown_item", "used up")


func test_smelling_salts_bring_a_downed_hero_back() -> void:
	var f := _fight(["smelling_salts"])
	var engine := f.engine as CombatEngine
	engine.get_combatant(engine.active_actor).ap = 3
	var down := engine.get_combatant(engine.party_ids()[2])
	if down.id == engine.active_actor:
		down = engine.get_combatant(engine.party_ids()[1])
	down.hp = 0
	_use(f, f.uids[0], [down.id])
	assert_eq(down.hp, CombatMath.percent_min1(down.max_hp, 40))


func test_a_bomb_hits_every_enemy() -> void:
	var f := _fight(["bomb"])
	var engine := f.engine as CombatEngine
	engine.get_combatant(engine.active_actor).ap = 3
	var before: Array[int] = []
	for id: int in engine.enemy_ids():
		before.append(engine.get_combatant(id).hp)
	var events := _use(f, f.uids[0], [])
	var hits := events.filter(func(ev: Dictionary) -> bool: return String(ev.type) == "damage" and String(ev.cause) == "item")
	assert_eq(hits.size(), engine.enemy_ids().size(), "one hit per enemy")
	for i: int in engine.enemy_ids().size():
		assert_lt(engine.get_combatant(engine.enemy_ids()[i]).hp, before[i])


func test_items_need_their_ap() -> void:
	var f := _fight(["salve"])
	var engine := f.engine as CombatEngine
	engine.get_combatant(engine.active_actor).ap = 0
	var events := _use(f, f.uids[0], [engine.active_actor])
	assert_eq(String(events[0].reason), "not_enough_ap")


func test_mirror_and_restore_agree_after_an_item() -> void:
	var f := _fight(["feast", "salve"])
	var engine := f.engine as CombatEngine
	engine.get_combatant(engine.active_actor).ap = 3
	_use(f, f.uids[0], [])
	var snap := engine.snapshot()
	assert_eq((f.mirror as CombatMirror).projection().items_left, CombatMirror.project_snapshot(snap).items_left)
	var copy := CombatEngine.restore(f.setup as CombatSetup, snap)
	assert_eq(copy.items_left, engine.items_left, "a restored engine keeps the items left")


func test_the_run_spends_used_items() -> void:
	var f := _fight(["salve", "bomb"])
	var run := f.run as RunState
	run.spend_items([f.uids[0]] as Array[int])
	assert_false(run.backpack.has_uid(f.uids[0]))
	assert_true(run.backpack.has_uid(f.uids[1]))
