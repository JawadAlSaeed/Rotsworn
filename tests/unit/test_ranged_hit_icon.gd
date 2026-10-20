extends GutTest
## Card #278: a thrown (ranged) hit has its own icon on the intent sign, the attack banner and the
## hit markers, so players see a throw coming before the wind-up. For the rules it stays the hit
## its kind says (a normal hit: parry or dodge). The intent carries which hits are thrown as plain
## data, like feints and marks.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const NORMAL: int = AttackHitData.Kind.NORMAL
const GROUND: int = AttackHitData.Kind.GROUND
const REND: int = AttackHitData.Kind.REND
const SWEEP: int = AttackHitData.Kind.SWEEP
const RANGED: int = HitRowView.RANGED_ICON
const FOE: int = Fx.ENEMY_ID
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const THROWN_ATTACK_PATH := "res://data/enemy_attacks/husk_rock_toss.tres"

var _visuals: CombatVisuals


func before_all() -> void:
	_visuals = load(VISUALS_PATH) as CombatVisuals


func _thrown(at_ms: int, kind: int = NORMAL) -> AttackHitData:
	var hit := Fx.hit(at_ms, kind)
	hit.projectile = ProjectileData.new()
	return hit


# --- the icon a hit shows ---------------------------------------------------------------------

func test_a_thrown_normal_hit_maps_to_the_ranged_icon() -> void:
	assert_eq(HitRowView.icon_key(NORMAL, true), RANGED, "a throw shows the ranged icon")
	assert_eq(HitRowView.icon_key(NORMAL, false), NORMAL, "a lunge keeps the sword")


func test_other_hits_keep_their_kinds_icon() -> void:
	assert_eq(HitRowView.icon_key(GROUND, false), GROUND)
	assert_eq(HitRowView.icon_key(REND, false), REND)
	assert_eq(HitRowView.icon_key(SWEEP, false), SWEEP)
	# A thrown rend or sweep keeps its own icon: its one right button matters more.
	assert_eq(HitRowView.icon_key(REND, true), REND)
	assert_eq(HitRowView.icon_key(SWEEP, true), SWEEP)
	assert_eq(HitRowView.icon_key(GROUND, true), GROUND)


func test_the_ranged_key_is_no_hit_kind() -> void:
	assert_false(AttackHitData.Kind.values().has(RANGED), "the ranged key never clashes with a kind")


# --- the art ----------------------------------------------------------------------------------

func test_the_ranged_icon_file_exists_and_is_its_own() -> void:
	var path := _visuals.hit_icon_ranged_path
	assert_true(path.begins_with("res://assets/"), "the path lives in data and points into assets/")
	assert_true(FileAccess.file_exists(path), "the ranged icon is drawn: %s" % path)
	for other: String in [_visuals.hit_icon_normal_path, _visuals.hit_icon_ground_path,
			_visuals.hit_icon_rend_path, _visuals.hit_icon_sweep_path]:
		assert_ne(path, other, "its own picture, not another kind's")
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	assert_not_null(image)
	assert_eq(image.get_size(), Vector2i(12, 12), "12x12 like the other hit icons")
	var opaque := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	assert_gt(opaque, 30, "a real picture, not an empty file")


func test_the_icon_set_gives_the_ranged_hit_its_own_texture() -> void:
	var icons := HitRowView.load_icons(_visuals)
	for key: int in [NORMAL, GROUND, REND, SWEEP, RANGED]:
		assert_true(icons.get(key) is Texture2D, "an icon for key %d" % key)
	var ranged := icons[RANGED] as Texture2D
	assert_ne(ranged, icons[NORMAL], "not the sword")
	assert_ne(ranged, AssetLoader.fallback_texture(Vector2i(12, 12)), "not the missing-art placeholder")
	assert_eq(Vector2i(ranged.get_size()), Vector2i(12, 12))


# --- the hit row (intent sign and banner) -----------------------------------------------------

func test_the_row_shows_the_ranged_icon_only_on_thrown_normal_hits() -> void:
	var sword := ImageTexture.create_from_image(Image.create(12, 12, false, Image.FORMAT_RGBA8))
	var wave := ImageTexture.create_from_image(Image.create(12, 12, false, Image.FORMAT_RGBA8))
	var rend := ImageTexture.create_from_image(Image.create(12, 12, false, Image.FORMAT_RGBA8))
	var orb := ImageTexture.create_from_image(Image.create(12, 12, false, Image.FORMAT_RGBA8))
	var icons := {NORMAL: sword, GROUND: wave, REND: rend, RANGED: orb}
	var row := HitRowView.new()
	add_child_autofree(row)
	row.setup(30.0, _visuals)
	row.set_hits([NORMAL, NORMAL, GROUND, REND, NORMAL], [0, 400, 800, 1200, 1600], icons, [], [],
			[false, true, false, true])
	assert_eq(row._textures, [sword, orb, wave, rend, sword] as Array[Texture2D],
			"thrown normal hits show the orb; a missing flag means not thrown")
	row.set_hits([NORMAL, GROUND], [0, 400], icons)
	assert_eq(row._textures, [sword, wave] as Array[Texture2D], "no ranged list: every hit its kind's icon")


# --- the engine's intent ----------------------------------------------------------------------

func test_the_intent_says_which_hits_are_thrown() -> void:
	var attack := Fx.attack("toss", [Fx.hit(900), _thrown(1300), _thrown(1800, GROUND)])
	var engine := CombatEngine.new(Fx.setup([attack]))
	var intent := Fx.first_of(engine.start(), "intent")
	assert_eq(intent.kinds, [NORMAL, NORMAL, GROUND])
	assert_eq(intent.ranged, [false, true, false], "only a thrown strike counts (a ground hit never flies)")


func test_an_intent_without_throws_carries_no_ranged_list() -> void:
	var engine := CombatEngine.new(Fx.setup([Fx.attack("swipe", [Fx.hit(900), Fx.hit(1300)])]))
	var intent := Fx.first_of(engine.start(), "intent")
	assert_false(intent.has("ranged"), "like marks: only when a hit is thrown")


func test_a_thrown_hit_is_still_a_normal_hit_for_the_rules() -> void:
	var engine := CombatEngine.new(Fx.setup([Fx.attack("toss", [_thrown(1300)])]))
	engine.start()
	# The fixture enemy is fast: it attacks first, so its hits are declared at once.
	var hits: Array = engine.sequence.hits
	assert_eq(hits.size(), 1)
	assert_eq(int(hits[0].kind), NORMAL, "the declared hit stays a normal hit")
	assert_true((engine.sequence.prompts[0].windows as Dictionary).has(Defense.Outcome.PARRY))
	assert_true((engine.sequence.prompts[0].windows as Dictionary).has(Defense.Outcome.DODGE))


func test_a_thrown_hit_forced_to_a_rend_keeps_the_rend_icon() -> void:
	var hit := _thrown(1300)
	hit.forced_kind = REND
	var setup := Fx.setup([Fx.attack("toss", [hit])])
	setup.forced_hits = true
	var intent := Fx.first_of(CombatEngine.new(setup).start(), "intent")
	assert_eq(intent.kinds, [REND])
	assert_eq(intent.ranged, [true], "it is still thrown")
	assert_eq(HitRowView.icon_key(int(intent.kinds[0]), bool(intent.ranged[0])), REND,
			"but it shows the rend icon: only a parry stops it")


func test_the_mirror_keeps_the_ranged_list_for_the_intent_sign() -> void:
	var attack := Fx.attack("toss", [_thrown(900), Fx.hit(1300)])
	var mirror := CombatMirror.new()
	# A slow enemy: the party acts first, so the intent is still waiting (an attack clears it).
	for event: Dictionary in CombatEngine.new(Fx.setup([attack], {"enemy_speed": 10})).start():
		mirror.apply(event)
	assert_true(mirror.intents.has(FOE), "the enemy has not attacked yet")
	assert_eq((mirror.intents.get(FOE, {}) as Dictionary).get("ranged"), [true, false])


func test_the_same_fight_gives_the_same_intent() -> void:
	var attack := Fx.attack("toss", [_thrown(900), Fx.hit(1300)])
	var a := Fx.first_of(CombatEngine.new(Fx.setup([attack])).start(), "intent")
	var b := Fx.first_of(CombatEngine.new(Fx.setup([attack])).start(), "intent")
	assert_eq(a, b, "plain data, deterministic")


# --- shipped data -----------------------------------------------------------------------------

func test_a_shipped_throw_reads_as_ranged() -> void:
	var attack := load(THROWN_ATTACK_PATH) as EnemyAttackData
	assert_not_null(attack)
	assert_true(attack.hits[0].projectile != null, "the rock toss throws a stone")
	assert_true(attack.hits[0].ranged_in(false))
	assert_true(attack.hits[0].ranged_in(true))
