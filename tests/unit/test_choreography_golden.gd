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
const EXPECTED_ATTACKS: int = 84

## Recorded 2026-10-14 on the phase 9 tree, before any phase 10 lane; phase 12 added its attacks
## (every older hash unchanged); phase 16 (card #195) added the five Charged Dooms, again with
## every older hash unchanged; phase 19 (cards #255 to #260) added the new monsters' attacks, the same. Some attacks share a hash
## because their hits are timed the same (for example husk_flurry, gnat_swarm_sweep and
## king_crown_sweep).
const EXPECTED_HASH := "68fa4a93059e2f6bf06e16e3a156adea46b5f3597e3f61c42a7e52032a123615"
const EXPECTED_BY_ATTACK: Dictionary = {
	"ashen_cinder_hail": "097a20436142decf6db61d60b9ef529c05f0cec1b9754c8987b09927f4037a5c",
	"bile_tick_spit": "c524d334549459ed7c6fd831be709d04c67e99f78700ad12b009f1372230249e",
	"blight_bile_flood": "d8add67a45208428173f0e21e722f6ac466ef2b02fc430dfc693b36a40a9f2a8",
	"bloat_belly_slam": "52f89f0c3d65565e06ab28ab09837edd3795c3f8401b79a5a6d7d448fc9ddf86",
	"bloat_bile_rain": "5f2f84fec47fbc20136b1f50963ae75a8b639e150794f97fa0823f971171031b",
	"bloat_bile_spit": "84f4506da756d3862c45ca188725b66407bf51a4fcfbfec69b11494eacde8ae3",
	"bloat_crush": "bc3d1c6d433867c71a7a66cc99c9cc7e00e400b18ba56837dbb3e89a646ceeed",
	"bloat_double_wave": "e9c810f664019396017f4274cd004776317991995d56641efaebf189cf1b094a",
	"bloat_gorge_burst": "78dfde073c0f39b6345a51eb989d8fba69741e073286994681b689c8eeaab032",
	"bloat_quake": "889c7c8d81106fe3198577fb81c6d41463d929de8d9d866ea8f2bf7f6a5a1f92",
	"bloat_rot_wave": "0693fd1225095ddd62ca9e5a53ed3829c09a7dda351dcf60e978e717d6dfce0f",
	"blood_rush": "8bd3f4d099e7ef5eef335986d622c95b4446291c7b61a720e64480bf383f5284",
	"bone_frenzy": "33334f35791a55b90437dcce5c2d0b4a965dd73e05b5be6319a742b0249d81cd",
	"brute_double": "e435a3783192bb8e2ea776070baa8ed777b66be78fdbd5fb2e6c8a12c5d2663f",
	"brute_maul": "57274724ba631a6b3540f3b960d3cabde4fdff6b1961d35e28fb387710cc0b03",
	"brute_quake": "965a87313f4fc7b70f44f2626ea394ceb5fef4e33400bf00fdb0ec166d4e8c52",
	"brute_slam": "fa89e3afbee44a1cda20bcb14af79fd307e757b989965b0c8001f41619ea1e22",
	"brute_sweep": "5699873a2274972ff3777ff2d54bcec49332511894d9f2f1cbb81278f175c3f8",
	"cinder_fire_rain": "88c5b8c5c76aedf765a29a1d4c75f0bf3a0270ca82d1e7b11632fee0fd0935b8",
	"elder_quake_hop": "1aea2f5bd84d2d9f9b97fe05fb278f7c27dbdfb555d01655caf9b6c260c4effb",
	"fly_buzz_dive": "a74f73cd58c049235629b02e63b84f7a22987b9fabbe0e05a5cf01a0b417ed00",
	"fly_dive": "9a314b854bc0c5d4b661e49dd56fff6d51ea19e26146d07bf327703142074039",
	"fly_maggot_spit": "c1f847cef1fae134c8d0c9a27670e9ade637488884aeac54e2f1c4b78ee13584",
	"fly_strafe": "32023bcc8e3f0e723cb21b439c5426cc0909765c96a5b2d764395df3f2d642b9",
	"gnat_buzz": "7584fb10faa8c13812a8b74375c6ffd9c4aa4edd9eaebbeb02682e8139273f7b",
	"gnat_sting_string": "81b4073798fe3237d1ab6bbb5690f91658ec2dd0c4fc9be9bc1c9a5e57b780e4",
	"gnat_swarm_round": "a0ee6d7d0a07b7a56e6b89638c7ac83ccff0ce9ddf2a7dcd6d6eb66e9b28da18",
	"gnat_swarm_sweep": "2830da980206154f27db6c0880b170f97e3bbe911a6bd3d42226b66f732e003e",
	"grave_rat_frenzy": "31a9161f31a09d1aae8a578a8bd853a726b8d171cfb8278fbb115165251c1878",
	"hollow_bolt_storm": "f7aa6e6315a57caddbba9d0d1372073ed9957bb3c0267762332e659926364302",
	"hollow_litany": "97806ee2c097770039debb935dfc420e9ddf1d5728d918a2d82c0e183d56ab66",
	"husk_flurry": "2830da980206154f27db6c0880b170f97e3bbe911a6bd3d42226b66f732e003e",
	"husk_ground_slam": "508098f96d4ee3080b459cc45643ec667cfb9133c10b2490098c938009ae7f05",
	"husk_lingering_claw": "1ba38e49edf1d2addf74430ab8ea77d2bf69cce9f14b595652336e2baf92bdda",
	"husk_rock_toss": "ee7a61b0a41e314c9e8e935daa4b115992b8321f22f8b8909ae1a85d59791531",
	"husk_rot_combo": "3233fe26784ec9f2f068a6bd18db3fb9837d45d4fedb77d366b6078df3894f3d",
	"husk_stone_spikes": "adc41b271189e379cb86fca9e5e2e8b73917a05318bb95b352f6cd80acc3b3ca",
	"husk_swipe": "e8b8d6f1ae174efa61f79affdee2cf7e3e72d177f5ae6a272c7c31c31be1adc0",
	"husk_timber_fall": "1fdf3e15039046b6a3d800f388e59c4ada52b276dffec03222e0079aa3fee5c6",
	"hyena_cackle": "d2dbb84fe278e3f1b4254340a14948db88ae680b97c928592a0328b6c6930d8f",
	"hyena_pack_bite": "8c628aea38bb8e4adeac32298403918e5a108d5bb23f013ce9e90e9aa5bb9919",
	"hyena_pounce": "7fe2ac8c44e1d0966ad3f388a21eb788287762a90786bb4789e0091b6522457e",
	"hyena_snap": "862126dd65f322a02531e9e5f3c8901a6a48ed547fcc227f433e0a70b0d46bdd",
	"king_cleave": "0a4b5285af56c888a2cc00850a501a5ee4980aca93c22be88dbabe2b9965a5b2",
	"king_crown_of_rot": "e963a7094bfc96584d7b2f394786f2a754f60f278610b685882d564dbba01798",
	"king_crown_sweep": "bbfdba01625527f1545c2a17d2a22e74a7994eb4daa25ebbdbc94322441955cf",
	"king_false_crown": "33ed73490e4eae9fae29ae9bde43e46d17213f8a0b9782eee92dcf1fdaddf754",
	"king_grave_stomp": "2baf7e17b713227bb22d996263131e7b070d62001eb65fb23ce614e286d3e017",
	"king_hollow_wave": "0693fd1225095ddd62ca9e5a53ed3829c09a7dda351dcf60e978e717d6dfce0f",
	"king_kingsfall": "aa24ac483cbc48a612bd752bf716c3875943c559eeaa7c4dbe4c03f55c9d148b",
	"king_rot_cascade": "261fa15c7a19bdbaa1fdc888eceac4b758d7f5fbeef1b25283232778c781c0a3",
	"lantern_burst": "ac9ea801ed5947a0dd764434cb03d119e87773da48600b33d935599381afab78",
	"lantern_chain": "1348b80f2ed849fded79a9700d9a2ebec43525192caa04e3192e32bdfc7847e1",
	"lantern_spark": "a1bed318f2196449d6e002736aceb7eceb7e4fc2cdd4c773aa74114d6fa7f7b9",
	"lantern_zigzag": "f8090cc8d0a7a6ffa8e0a86f5d1af2510ca043da0a2f2cc7d6e6f8fe7f05abb6",
	"plague_spit": "b8518ed292a2d6b50b1b5f8f43211b8ad1a9c5f222eaedc4f26354297fb99745",
	"priest_censer": "c3169ed59a46287083a936e723829ef45480ae75ead81660f9d62a04fe61cc6c",
	"priest_hush": "b8518ed292a2d6b50b1b5f8f43211b8ad1a9c5f222eaedc4f26354297fb99745",
	"rat_gnaw": "14c6e2f25e364e28c35ffbd2016255c0e69e4b8054f1c2a14e6bf4f91abac5a8",
	"rat_nibble": "49a7f93b2cf25f8059b6ec5b678aa73fb46d42185408c841dd81a4176679228f",
	"rat_scurry": "46a1d228a17c24b84b6f195cc5f3b0db96bbc3ae8d56d1584c24452296efc609",
	"rat_tide": "0ab888b71eab228bddebba15e2688487e4f4d62eff8043183e2e5b0b4d24b69d",
	"shade_ashfall": "911a45a1e3278c727859151249525da7864c21eff46e6ac06bbde947185f70a5",
	"shade_bolts": "c7f48d42abbaf5ec740a7c66e4179f8ab8c607b4164c6c76bddb3467a871fa20",
	"shade_cross_step": "e6f9380b81cfa79e15827e471f9e11f1c627bb07f510dbee750add226fbe027d",
	"shade_delayed_rake": "34d5b1cccffe39e290ccb3960d76617d8ed416206a1df551d66cbd11f0460bab",
	"shade_grave_spikes": "ce2d6d23f4cf360d813bf913e38ebdcf40ae747730e6cf7a62999636d6bc1657",
	"shade_nightfall": "7f2ea6fde7188923c99357436597db2a63733a96f78ebb787a3e0918ffcd159e",
	"shade_stutter": "bfe1f10569984d764d810fc11b2e866c10b2747cffb55ea20b1676791a0c5f15",
	"slinger_firepot": "84f4506da756d3862c45ca188725b66407bf51a4fcfbfec69b11494eacde8ae3",
	"slinger_pitch": "55299436fc7947ce97ebbab199b8314c75a14453e794cba13d072230ac808b3c",
	"slinger_scatter": "633f1a9da42bdd6ece711df903548184469d476e7c0eb1d0f999c77343e139a0",
	"slinger_volley": "8602e02db1c7ff6f4c6f25732adba0e96323e9566be85fc2e257856167f482cd",
	"storm_thunderhead": "6d89e5b6093c671ce95459de9a2184e458fa27ba923f75122b59ebe3d74cd6b4",
	"tick_burst": "83c0641e2e3d67d0a5cb65130546b5ce3110fef6e9cd086cbcf82db179d66494",
	"tick_latch": "e8b8d6f1ae174efa61f79affdee2cf7e3e72d177f5ae6a272c7c31c31be1adc0",
	"toad_belly_flop": "b6834808c0ebe71755aa71e7fd9e35eaa3addb7101b7bbd2c8a6182acddc8617",
	"toad_brood_tide": "a1949266a6aaf0573c50a51202005f81d914c4e45fd910fc188b1616fefc6222",
	"toad_hop_hop": "3d2b03f62f912c0fd4945f7c7de7a1537cf3c14a675b7bd23ab73e2c5f896106",
	"toad_mud_spit": "d30e7b3d9d1c7a9a21a8dbd0ea6b29a57f4c10549a5986fffae3f0885412b6b1",
	"toad_tongue": "8e714f9f82f632895a2df76b0a9217452445897624ff6bb6d771836f9e42dec1",
	"tomb_grave_quake": "3b9e333036646f9ab7194c1b42b7a2c9f3e03de6ae7a1eaf4533efce5b542c2e",
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
		if attack.is_support():
			continue  # A support move (card #259) has no hits to play.
		var declared := Fx.declared_attack(attack, {"tuning": tuning})
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
	var support := 0
	for file: String in DirAccess.get_files_at(ATTACK_DIR):
		if file.ends_with(".tres"):
			files += 1
			if (load(ATTACK_DIR.path_join(file)) as EnemyAttackData).is_support():
				support += 1
	# Support moves (card #259) heal or shield and play no hits.
	assert_eq(_shipped_attacks().size(), files - support, "every attack file loads and is declared")
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
