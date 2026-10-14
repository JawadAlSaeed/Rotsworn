extends GutTest
## Golden hash of the enemy attack choreography (phase 10 plan, step 1C). Phase 10 draws animation
## frames on top of EnemyChoreography, but what it already returns must not move: the defence judge
## is synced to it (what you see is what is judged, DESIGN 3.3). For every shipped enemy attack,
## built exactly as TimedSequenceRunner.start builds it (engine-declared hits, with_close_times at
## the shipped lag compensation), this samples sample() (pose, approach, glow, hit) at 1 ms steps
## from LEAD_MS before the clock starts to TAIL_MS after the attack settles, adds cues(), and
## compares SHA-256 hashes with the stored ones. Uses the shipped tuning.tres and
## combat_visuals.tres, because that is what the game plays.
##
## A failure prints the new values between GOLDEN_REGEN_BEGIN and GOLDEN_REGEN_END (run
## run_tests.bat and search its output for those words). Paste them over the two consts below ONLY
## for a deliberate change: a retuned choreography or window number in combat_visuals.tres or
## tuning.tres, or an attack added or retimed in data/enemy_attacks/. Any other failure means a
## change moved the enemy's motion: fix the change instead.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const ATTACK_DIR := "res://data/enemy_attacks"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
## Sampling starts this many ms before the attack clock starts...
const LEAD_MS: int = 100
## ...and ends this many ms after the last hit has fully settled.
const TAIL_MS: int = 300
## approach and glow (0..1) are hashed as integers in units of 1 / FRACTION_SCALE.
const FRACTION_SCALE: float = 10000.0
## Cue times are hashed in microseconds.
const CUE_TIME_SCALE: float = 1000.0
## Separates the sample stream from the cue stream in the hashed integers.
const SECTION_MARK: int = -2147483647
## Shipped enemy attacks when this golden was recorded (a guard against files silently skipped).
const EXPECTED_ATTACKS: int = 50

## Recorded 2026-10-14 on the phase 9 tree, before any phase 10 lane; phase 12 added its attacks
## (every older hash unchanged). Some attacks share a hash
## because their hits are timed the same (for example husk_flurry, gnat_swarm_sweep and
## king_crown_sweep).
const EXPECTED_HASH := "3c119aa86ee20e9a3fc3c70f7499387f06e5cac29e445c368c65fcfab0b59c83"
const EXPECTED_BY_ATTACK: Dictionary = {
	"ashen_cinder_hail": "097a20436142decf6db61d60b9ef529c05f0cec1b9754c8987b09927f4037a5c",
	"blight_bile_flood": "0209855b3d73ae58f78c3c61941534c458ef1906127df041eff7b226b27d03f9",
	"bloat_belly_slam": "52f89f0c3d65565e06ab28ab09837edd3795c3f8401b79a5a6d7d448fc9ddf86",
	"bloat_bile_rain": "5f2f84fec47fbc20136b1f50963ae75a8b639e150794f97fa0823f971171031b",
	"bloat_bile_spit": "84f4506da756d3862c45ca188725b66407bf51a4fcfbfec69b11494eacde8ae3",
	"bloat_crush": "bc3d1c6d433867c71a7a66cc99c9cc7e00e400b18ba56837dbb3e89a646ceeed",
	"bloat_double_wave": "e9c810f664019396017f4274cd004776317991995d56641efaebf189cf1b094a",
	"bloat_quake": "889c7c8d81106fe3198577fb81c6d41463d929de8d9d866ea8f2bf7f6a5a1f92",
	"bloat_rot_wave": "0693fd1225095ddd62ca9e5a53ed3829c09a7dda351dcf60e978e717d6dfce0f",
	"blood_rush": "f67a1505d136f47ce9f3a09fdd3ffb68cfd996b41a6013134af859b2f765d177",
	"bone_frenzy": "eaab15cf11111a2fe3d2981a7fa01fb99fd1aa3948ac7616b8b9ed5dd1600b7b",
	"elder_quake_hop": "4f845179021df70d51b95325cc3bfec83d13cf25e34e986a38f72c0db1ce7a62",
	"fly_buzz_dive": "d483dfefddf96532a4513697aba47b97919cf444feb031ba9071f5ea18fce573",
	"fly_dive": "9a314b854bc0c5d4b661e49dd56fff6d51ea19e26146d07bf327703142074039",
	"fly_maggot_spit": "c1f847cef1fae134c8d0c9a27670e9ade637488884aeac54e2f1c4b78ee13584",
	"fly_strafe": "aa8ba10b19b38252b8305b8989b20a6c6557fefcacdae84b713f9e326d042a1b",
	"gnat_buzz": "06f261e6edd36daad4af03d7896512f1a94e1a277692a3b9959756d97a912fd7",
	"gnat_sting_string": "a52c702e5638d25bfa156f9ccae142e4e559fc582ee232b9c5c56904945454d4",
	"gnat_swarm_round": "7c86ffe79dfcc24a17ae76a1d192d4efc8dce77b245e85a60998f01a304cab7a",
	"gnat_swarm_sweep": "8ee5ddfeb49818d43bea7d0600888ba5b2dcd81f618cec5ca33273258a951c2b",
	"hollow_bolt_storm": "f7aa6e6315a57caddbba9d0d1372073ed9957bb3c0267762332e659926364302",
	"husk_flurry": "8ee5ddfeb49818d43bea7d0600888ba5b2dcd81f618cec5ca33273258a951c2b",
	"husk_ground_slam": "508098f96d4ee3080b459cc45643ec667cfb9133c10b2490098c938009ae7f05",
	"husk_lingering_claw": "1ba38e49edf1d2addf74430ab8ea77d2bf69cce9f14b595652336e2baf92bdda",
	"husk_rock_toss": "ee7a61b0a41e314c9e8e935daa4b115992b8321f22f8b8909ae1a85d59791531",
	"husk_rot_combo": "3233fe26784ec9f2f068a6bd18db3fb9837d45d4fedb77d366b6078df3894f3d",
	"husk_stone_spikes": "adc41b271189e379cb86fca9e5e2e8b73917a05318bb95b352f6cd80acc3b3ca",
	"husk_swipe": "e8b8d6f1ae174efa61f79affdee2cf7e3e72d177f5ae6a272c7c31c31be1adc0",
	"hyena_cackle": "d2dbb84fe278e3f1b4254340a14948db88ae680b97c928592a0328b6c6930d8f",
	"hyena_pack_bite": "d42924a596daa34e648eff7330e0094d223e6413c92bd2bf8d7c37246c3af34e",
	"hyena_pounce": "7fe2ac8c44e1d0966ad3f388a21eb788287762a90786bb4789e0091b6522457e",
	"hyena_snap": "862126dd65f322a02531e9e5f3c8901a6a48ed547fcc227f433e0a70b0d46bdd",
	"king_cleave": "0a4b5285af56c888a2cc00850a501a5ee4980aca93c22be88dbabe2b9965a5b2",
	"king_crown_sweep": "8ee5ddfeb49818d43bea7d0600888ba5b2dcd81f618cec5ca33273258a951c2b",
	"king_false_crown": "33ed73490e4eae9fae29ae9bde43e46d17213f8a0b9782eee92dcf1fdaddf754",
	"king_grave_stomp": "2baf7e17b713227bb22d996263131e7b070d62001eb65fb23ce614e286d3e017",
	"king_hollow_wave": "0693fd1225095ddd62ca9e5a53ed3829c09a7dda351dcf60e978e717d6dfce0f",
	"king_kingsfall": "183c9d73f81aa9c6e1104b2cd36199186c13e20c493c7419bc16e68cd5a41368",
	"king_rot_cascade": "23c2eb6bb9bc129b962b70c04818912557e6d4e3a75cd1521e411c7d45b7ec62",
	"plague_spit": "b8518ed292a2d6b50b1b5f8f43211b8ad1a9c5f222eaedc4f26354297fb99745",
	"shade_bolts": "c7f48d42abbaf5ec740a7c66e4179f8ab8c607b4164c6c76bddb3467a871fa20",
	"shade_cross_step": "e6f9380b81cfa79e15827e471f9e11f1c627bb07f510dbee750add226fbe027d",
	"shade_delayed_rake": "34d5b1cccffe39e290ccb3960d76617d8ed416206a1df551d66cbd11f0460bab",
	"shade_grave_spikes": "ce2d6d23f4cf360d813bf913e38ebdcf40ae747730e6cf7a62999636d6bc1657",
	"shade_nightfall": "7f2ea6fde7188923c99357436597db2a63733a96f78ebb787a3e0918ffcd159e",
	"shade_stutter": "bfe1f10569984d764d810fc11b2e866c10b2747cffb55ea20b1676791a0c5f15",
	"toad_belly_flop": "b6834808c0ebe71755aa71e7fd9e35eaa3addb7101b7bbd2c8a6182acddc8617",
	"toad_hop_hop": "31a91f740fae7f0fdc8f8d629f389722ebbf1b8ac5133a72057a6ddc5f710e54",
	"toad_mud_spit": "d30e7b3d9d1c7a9a21a8dbd0ea6b29a57f4c10549a5986fffae3f0885412b6b1",
	"toad_tongue": "8e714f9f82f632895a2df76b0a9217452445897624ff6bb6d771836f9e42dec1",
}


## {id: {hits, end_ms}} for every shipped attack, declared by the engine with the shipped tuning.
func _shipped_attacks() -> Dictionary:
	var tuning := Fx.shipped_tuning()
	var list: Dictionary = {}
	for file: String in DirAccess.get_files_at(ATTACK_DIR):
		if not file.ends_with(".tres"):
			continue
		var attack := load(ATTACK_DIR.path_join(file)) as EnemyAttackData
		assert_not_null(attack, file)
		if attack == null:
			continue
		var engine := CombatEngine.new(Fx.setup([attack], {"tuning": tuning}))
		var declared := Fx.first_of(engine.start(), "timed_sequence_declared")
		assert_false(declared.is_empty(), attack.id + ": the engine declares the attack at start")
		if declared.is_empty():
			continue
		# The runner uses PlayerSettings.latency_compensation_ms: the tuning value until calibrated.
		var hits := EnemyChoreography.with_close_times(declared.hits as Array, declared.prompts as Array,
				tuning.input_latency_compensation_ms)
		EnemyChoreography.add_hit_data(hits, attack)
		list[attack.id] = {"hits": hits, "end_ms": _settled_ms(hits, _visuals())}
	return list


func _visuals() -> CombatVisuals:
	return load(VISUALS_PATH) as CombatVisuals


## A time by which the enemy is surely back home and idle: the last impact, the longest hold
## after it (contact until close, or a slam), then the walk home.
static func _settled_ms(hits: Array, v: CombatVisuals) -> float:
	var last_at := 0.0
	var last_close := 0.0
	for hit: Dictionary in hits:
		if float(hit.at_ms) >= last_at:
			last_at = float(hit.at_ms)
			last_close = float(hit.close_ms)
	var hold := maxf(float(v.contact_hold_ms), last_close + float(v.contact_after_close_ms))
	hold = maxf(hold, float(v.slam_hold_ms))
	return last_at + hold + float(v.return_ms)


## SHA-256 (hex) of one attack's sampled choreography and cues.
static func _attack_hash(hits: Array, end_ms: float, v: CombatVisuals) -> String:
	var ints := PackedInt32Array()
	for t: int in range(-LEAD_MS, ceili(end_ms) + TAIL_MS + 1):
		var s := EnemyChoreography.sample(hits, float(t), v)
		ints.append(t)
		ints.append(int(s.pose))
		ints.append(roundi(float(s.approach) * FRACTION_SCALE))
		ints.append(roundi(float(s.glow) * FRACTION_SCALE))
		ints.append(int(s.hit))
	ints.append(SECTION_MARK)
	var cue_types: Array[String] = [EnemyChoreography.CUE_LUNGE, EnemyChoreography.CUE_FEINT,
			EnemyChoreography.CUE_SLAM, EnemyChoreography.CUE_SHOOT]
	for cue: Dictionary in EnemyChoreography.cues(hits, v):
		ints.append(roundi(float(cue.at_ms) * CUE_TIME_SCALE))
		ints.append(cue_types.find(String(cue.type)))
		ints.append(int(cue.hit))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(ints.to_byte_array())
	return ctx.finish().hex_encode()


## One hash over every attack's hash, in id order.
static func _combined_hash(by_attack: Dictionary) -> String:
	var ids: Array = by_attack.keys()
	ids.sort()
	var lines := PackedStringArray()
	for id: String in ids:
		lines.append("%s=%s" % [id, by_attack[id]])
	return "\n".join(lines).sha256_text()


## The two consts to paste into this file, ready to copy.
static func _regen_text(combined: String, by_attack: Dictionary) -> String:
	var ids: Array = by_attack.keys()
	ids.sort()
	var lines := PackedStringArray()
	lines.append("GOLDEN_REGEN_BEGIN (paste over the consts in tests/unit/test_choreography_golden.gd)")
	lines.append("const EXPECTED_HASH := \"%s\"" % combined)
	lines.append("const EXPECTED_BY_ATTACK: Dictionary = {")
	for id: String in ids:
		lines.append("\t\"%s\": \"%s\"," % [id, by_attack[id]])
	lines.append("}")
	lines.append("GOLDEN_REGEN_END")
	return "\n".join(lines)


## Attack ids whose hash differs from the stored one (or that were added or removed).
static func _changed_attacks(by_attack: Dictionary) -> PackedStringArray:
	var changed := PackedStringArray()
	for id: String in by_attack:
		if String(EXPECTED_BY_ATTACK.get(id, "")) != String(by_attack[id]):
			changed.append(id)
	for id: String in EXPECTED_BY_ATTACK:
		if not by_attack.has(id):
			changed.append(id + " (removed)")
	changed.sort()
	return changed


func test_every_shipped_attack_is_sampled() -> void:
	var files := 0
	for file: String in DirAccess.get_files_at(ATTACK_DIR):
		if file.ends_with(".tres"):
			files += 1
	assert_eq(_shipped_attacks().size(), files, "every attack file loads and is declared")
	assert_eq(files, EXPECTED_ATTACKS, "an attack was added or removed: regenerate the golden hash")


func test_the_sweep_ends_with_the_enemy_home_and_idle() -> void:
	var v := _visuals()
	var attacks := _shipped_attacks()
	for id: String in attacks:
		var a: Dictionary = attacks[id]
		var last := EnemyChoreography.sample(a.hits as Array, float(ceili(float(a.end_ms)) + TAIL_MS), v)
		assert_eq(int(last.pose), EnemyChoreography.Pose.IDLE, id + ": idle at the end of the sweep")
		assert_eq(float(last.approach), 0.0, id + ": home at the end of the sweep")
		assert_eq(float(last.glow), 0.0, id + ": no glow at the end of the sweep")


func test_choreography_matches_the_golden_hash() -> void:
	var v := _visuals()
	assert_not_null(v, VISUALS_PATH)
	var attacks := _shipped_attacks()
	var by_attack: Dictionary = {}
	for id: String in attacks:
		var a: Dictionary = attacks[id]
		by_attack[id] = _attack_hash(a.hits as Array, float(a.end_ms), v)
	var combined := _combined_hash(by_attack)
	var same := combined == EXPECTED_HASH and by_attack == EXPECTED_BY_ATTACK
	if not same:
		var changed := _changed_attacks(by_attack)
		var hint := ("Enemy choreography changed for: %s. If that was NOT a deliberate retune of"
				+ " combat_visuals.tres / tuning.tres or of data/enemy_attacks/, fix the change: the"
				+ " defence timing is synced to these frames. If it was deliberate, copy the lines"
				+ " between GOLDEN_REGEN_BEGIN and GOLDEN_REGEN_END from the test output into this"
				+ " file.") % ", ".join(changed)
		print(_regen_text(combined, by_attack))
		gut.p(_regen_text(combined, by_attack))
		fail_test(hint)
		return
	pass_test("choreography unchanged (%d attacks)" % by_attack.size())
