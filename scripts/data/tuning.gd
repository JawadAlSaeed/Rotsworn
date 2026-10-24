class_name Tuning
extends Resource
## Every global rules, timing-window and balance number in the game (what the engine and the
## defence judge use). Presentation-only feel (stage layout, animation, flash strengths, camera,
## the calibration procedure) lives in data/presentation/combat_visuals.tres instead.
## Edit the values in data/tuning/tuning.tres (double-click it in the editor's FileSystem panel;
## the values appear in the Inspector, each with a tooltip).
## Per-move numbers (how many hits, when they land, percentages) live in each move's own file and
## are percentages of the values below. Change balance in tuning.tres, not the defaults here.

@export_group("Defence windows")
## Total time you have to land a parry, in milliseconds. Smaller is harder.
@export_range(20, 600, 1, "suffix:ms") var parry_window_ms: int = 150
## Total time you have to land a dodge, in milliseconds. Wider and safer than a parry.
@export_range(20, 800, 1, "suffix:ms") var dodge_window_ms: int = 250
## Total time you have to land a jump over a ground attack, in milliseconds.
@export_range(20, 800, 1, "suffix:ms") var jump_window_ms: int = 220
## How much of each window comes after the moment of impact, in percent.
## 0 = the whole window is before impact, 100 = the whole window is after it.
@export_range(0, 100, 1, "suffix:%") var window_late_percent: int = 35
## After a press that matches nothing (too early, too late, wrong button), your defence buttons
## stop working for this long. Pressing again while locked restarts the lock (stops mashing).
@export_range(0, 2000, 1, "suffix:ms") var whiff_lockout_ms: int = 300
## Default lag compensation, subtracted from every press time to cancel screen and pad lag.
## The calibration (F2 in a fight) measures your own value and overrides this one.
@export_range(-200, 200, 1, "suffix:ms") var input_latency_compensation_ms: int = 30
## Smallest and largest lag compensation the calibration may save (and the game will use).
## Keeps a reaction-based calibration (pressing after the flash) from shifting every window.
@export_range(-200, 0, 1, "suffix:ms") var calibration_min_ms: int = -50
@export_range(0, 300, 1, "suffix:ms") var calibration_max_ms: int = 150
## A press is judged over the time since the previous frame (so a slow frame never costs you a
## parry). This caps how far back that reaches, in milliseconds.
@export_range(0, 250, 1, "suffix:ms") var press_reach_back_max_ms: int = 100
## A press this long after a hit already landed is shown as LATE for that hit (when it is nearer
## than the next hit) instead of being ignored.
@export_range(0, 1000, 1, "suffix:ms") var late_press_report_ms: int = 400

@export_group("Enemy attack pacing")
## Pause between the attack banner appearing and the attack starting.
@export_range(0, 3000, 1, "suffix:ms") var attack_lead_in_ms: int = 700
## An attacker that runs up (EnemyData.runs_up) runs to its target over this long before an attack
## that opens with a melee hit. It is added to the lead-in, so the wind-up and every window stay as
## authored (DESIGN.md 3.12). A wind-up attack charges in from home instead (card #310,
## charge_windup_min_ms) and keeps the plain lead-in.
@export_range(0, 2000, 1, "suffix:ms") var run_up_ms: int = 450
## Wind-up attacks charge in (card #310, DESIGN.md 3.12): an attacker that runs up skips the run
## (and run_up_ms with it) when its attack's first hit winds up at least this long (that hit's
## impact_ms minus approach_ms as authored). It winds up at home instead and its lunge charges all
## the way in. It decides the lead-in, so the online host's arbiter waits by it too: pacing, not
## looks.
@export_range(0, 5000, 1, "suffix:ms") var charge_windup_min_ms: int = 850
## Speed of every enemy attack, in percent of its authored timing. 120 = 20% slower.
@export_range(25, 300, 1, "suffix:%") var attack_tempo_percent: int = 100
## Enemy attacks never play faster than this percent of their authored timing, whatever depth,
## elites, bosses and phase two add up to (card #188): the windows stay the same size, so the
## lunges must stay readable.
@export_range(25, 100, 1, "suffix:%") var attack_tempo_floor_percent: int = 70
## Time after an attack's last hit before the turn moves on (when there is no counter).
@export_range(0, 3000, 1, "suffix:ms") var attack_recover_ms: int = 450
## Freeze on a parry that is not the attack's last hit. Keep it well under the early part of
## the parry window (about 97 ms by default) or rhythm parries on fast strings start failing.
@export_range(0, 200, 1, "suffix:ms") var hitstop_parry_ms: int = 45
## Freeze on a parry of the attack's last hit (right before the counter).
@export_range(0, 500, 1, "suffix:ms") var hitstop_parry_final_ms: int = 110
## Freeze on a successful jump.
@export_range(0, 200, 1, "suffix:ms") var hitstop_jump_ms: int = 40
## Freeze when the last hit of an attack lands on you. Earlier hits of a string do not freeze:
## by the time a missed hit is judged, the next lunge has often started.
@export_range(0, 200, 1, "suffix:ms") var hitstop_hurt_ms: int = 50
## Freeze when a counterattack lands.
@export_range(0, 500, 1, "suffix:ms") var hitstop_counter_ms: int = 120
## Delay between the end of the final hit-stop and the counterattack starting.
@export_range(0, 1000, 1, "suffix:ms") var counter_delay_ms: int = 220

@export_group("Timing cues")
## Training aid: a ring that shrinks onto the target and closes exactly at impact.
## Off by default so you learn to read the enemy. Toggle in a fight with F1 > R.
@export var show_timing_ring: bool = false
## How long before impact the ring appears.
@export_range(100, 3000, 1, "suffix:ms") var ring_lead_ms: int = 700
## The enemy flashes when it starts each lunge (a visual cue, not a beat).
@export var show_telegraph_flash: bool = true
## After each defence press, show how early or late it was (for example "LATE +23").
@export var show_timing_feedback: bool = true
## A whoosh when the enemy starts each lunge or slam (the sound of the motion). Toggle in a fight
## with F1 > L.
@export var play_motion_sounds: bool = true
## When a hit's motion starts, its icon pops up in a circle beside each target (and a floor warning
## glows under them for a ground hit) until it lands. Off since phase 6 (user: the circle made the
## game easier); the floor warning then still shows. Toggle in a practice fight with F1 > H.
@export var show_hit_markers: bool = true
## Ranged-hit indicator (DESIGN.md 3.9, card #165): while a thrown projectile flies, brackets on
## the hero it flies at close in and meet at the moment the defence is judged on, with a dashed
## path from the projectile. It is the projectile's own flight made readable, so it stays on in
## run fights (unlike the hit markers).
@export var show_ranged_aim: bool = true
## Harder reading (phase 6): the attack's hits (how many, which kind) show on the intent sign and
## the attack banner until the first hit lands; from then on the banner's hit row and the hit
## markers are hidden, so the rest of the string must be remembered. The enemy's own motion
## (wind-up glow, crouch, floor warning) still shows each hit.
@export var hide_intent_after_first_hit: bool = true
## Run (DESIGN.md 2.13): hold Back (B / Backspace) this long on the action menu to try to run,
## so a tap never runs by accident.
@export_range(0, 3000, 10, "suffix:ms") var run_hold_ms: int = 500
## The enemy crouches while it winds up and springs out of it as the lunge or slam starts.
## Toggle in a fight with F1 > C.
@export var show_windup_crouch: bool = true
## The combat camera moves for turns, skills, enemy attacks and the ultimate (DESIGN.md 7.3). It
## settles before an enemy attack's first motion and holds still while you defend. Toggle in a
## fight with F1 > V.
@export var cinematic_camera: bool = true

@export_group("HP and damage")
## HP of a character at 100% hp.
@export_range(1, 99999) var base_character_hp: int = 100
## HP of an enemy at 100% hp.
@export_range(1, 999999) var base_enemy_hp: int = 1500
## Damage of a party attack when every percentage is 100.
@export_range(1, 99999) var base_party_damage: int = 40
## Damage of one enemy hit when every percentage is 100.
## With 100 HP characters, 28 means 4 normal hits kill and 3 heavy (130%) hits kill.
@export_range(1, 99999) var base_enemy_hit_damage: int = 28
## Random spread on every damage roll, in percent (0 = always the same number).
@export_range(0, 50, 1, "suffix:%") var damage_variance_percent: int = 0
## Counterattack damage, in percent of the countering character's power.
@export_range(0, 1000, 5, "suffix:%") var counter_percent: int = 150
## Team counter: every character strikes together as one hit. Its damage is this percent of
## each character's power, added up. (Raised again for online co-op in phase 5.)
@export_range(0, 1000, 5, "suffix:%") var team_counter_percent: int = 120

@export_group("AP")
## AP each character has when a fight starts.
@export_range(0, 99) var start_ap: int = 1
## Most AP a character can hold.
@export_range(1, 99) var max_ap: int = 9
## AP gained for each successful parry.
@export_range(0, 9) var ap_per_parry: int = 1
## AP gained for each successful jump over a ground attack.
@export_range(0, 9) var ap_per_jump: int = 0

@export_group("Skills and co-op")
## Total time you have to land a good skill press (normal damage), in milliseconds (split like the
## defence windows). Outside it the press is EARLY or LATE.
@export_range(20, 800, 1, "suffix:ms") var skill_press_window_ms: int = 200
## The perfect part in the middle of it (extra damage and the skill's bonus), in milliseconds.
@export_range(10, 400, 1, "suffix:ms") var skill_perfect_window_ms: int = 70
## A skill hit with no good press still lands, for this percent of its normal damage.
@export_range(0, 100, 1, "suffix:%") var skill_miss_damage_percent: int = 50
## Total time an ally has to land a good follow-up press, in milliseconds.
@export_range(20, 800, 1, "suffix:ms") var follow_up_window_ms: int = 200
## The perfect part of a follow-up window, in milliseconds.
@export_range(10, 400, 1, "suffix:ms") var follow_up_perfect_window_ms: int = 70
## The first follow-up press comes this long after the skill's last press.
@export_range(100, 3000, 1, "suffix:ms") var follow_up_delay_ms: int = 700
## Time between one ally's follow-up press and the next one's. Keep it above follow_up_window_ms
## so one press can never answer two follow-ups.
@export_range(100, 3000, 1, "suffix:ms") var follow_up_gap_ms: int = 450
## Follow-up strike damage, in percent of the ally's power (good press, and perfect press).
@export_range(0, 1000, 5, "suffix:%") var follow_up_percent: int = 30
@export_range(0, 1000, 5, "suffix:%") var follow_up_perfect_percent: int = 45
## Size of the shared team gauge. Full = the team ultimate can be used.
@export_range(1, 1000) var team_gauge_max: int = 100
## Team gauge gained for each good follow-up press.
@export_range(0, 1000) var team_gauge_per_follow_up: int = 10
## The defence streak (card #300): perfect parries and jumps in a row across a fight (a dodge keeps
## it, a hit taken ends it). Every defence_streak_step in a row fills the team gauge by
## defence_streak_gauge (0: no gauge).
@export_range(1, 50) var defence_streak_step: int = 5
@export_range(0, 1000) var defence_streak_gauge: int = 10
## The team ultimate revives every downed ally with this percent of their max HP.
@export_range(1, 100, 1, "suffix:%") var team_ultimate_revive_percent: int = 25
## Extra damage of a skill that removes Exposed, in percent (a skill can set its own).
@export_range(0, 1000, 5, "suffix:%") var exposed_bonus_percent: int = 50
## Damage a Guarded character takes, in percent of the hit.
@export_range(0, 100, 1, "suffix:%") var guard_damage_percent: int = 50
## Speed of a Slowed fighter, in percent of its normal speed.
@export_range(10, 100, 1, "suffix:%") var slow_speed_percent: int = 75
## A counter grows with the string it answers (card #52): this many points of counter percent
## for each perfectly defended hit after the first, and this many more when the string mixed
## parries and jumps. Team counters too.
@export_range(0, 500, 5, "suffix:%") var counter_per_extra_hit_percent: int = 25
@export_range(0, 500, 5, "suffix:%") var counter_mixed_bonus_percent: int = 50
## Counter damage while Riposte Stance is up, in percent of the normal counter (200 = x2).
@export_range(100, 1000, 5, "suffix:%") var riposte_counter_percent: int = 200
## Charged Dooms (card #195): breaking one staggers the enemy. It loses this many of its next turns
## (the stagger ends when the last is lost), and takes this much extra damage from every source
## while it lasts (50 = x1.5).
@export_range(1, 4) var stagger_turns: int = 1
@export_range(0, 500, 5, "suffix:%") var stagger_damage_taken_percent: int = 50

@export_group("Timeline")
## One turn costs timeline_base / speed. Only the ratio between speeds matters.
@export_range(100, 1000000) var timeline_base: int = 10000
## How many upcoming turns the timeline shows.
@export_range(1, 20) var turn_order_preview: int = 8

@export_group("Presentation pacing")
## A character dashing to the enemy before striking.
@export_range(0, 2000, 1, "suffix:ms") var action_dash_ms: int = 180
## Pause on the strike before returning.
@export_range(0, 2000, 1, "suffix:ms") var action_hold_ms: int = 150
## A character returning to their spot.
@export_range(0, 2000, 1, "suffix:ms") var action_return_ms: int = 220
## A hero who runs up (CharacterData.runs_up, DESIGN.md 3.12) runs to the enemy over this long at
## the start of a melee skill. Keep it under the earliest press minus the wind-up (about 460 ms
## today), so the hero arrives before the wind-up frames start.
@export_range(0, 2000, 1, "suffix:ms") var hero_run_up_ms: int = 380
## Short pause between turns.
@export_range(0, 2000, 1, "suffix:ms") var turn_gap_ms: int = 200
## How long damage numbers and result popups stay up.
@export_range(100, 5000, 1, "suffix:ms") var popup_ms: int = 900
## Freeze on a good skill or follow-up press.
@export_range(0, 300, 1, "suffix:ms") var hitstop_press_ms: int = 60
## Time after a skill's last press (or follow-up) before the turn moves on.
@export_range(0, 3000, 1, "suffix:ms") var skill_recover_ms: int = 350

@export_group("Run")
## Rows of stops on the run map before the final fight (the final fight is one more stop).
@export_range(2, 30) var run_map_rows: int = 7
## From this map row on (0 = the first), Fight and Guard stops hold their fights' deep versions:
## variant monsters (EncounterData.deep, DESIGN.md 2.16).
@export_range(0, 30) var run_deep_row: int = 4
## Each row has this many stops side by side, picked at random between the two numbers.
@export_range(1, 6) var run_map_min_width: int = 2
@export_range(1, 6) var run_map_max_width: int = 3
## Chance, per stop, of an extra path to a neighbouring stop in the next row (more choices).
@export_range(0, 100, 1, "suffix:%") var run_map_extra_path_percent: int = 40
## How often a middle row's stop is a fight, a shop or a rest (weights, not percents). The first
## row is always fights, the last row before the final fight always rests.
@export_range(0, 1000) var run_weight_fight: int = 60
@export_range(0, 1000) var run_weight_shop: int = 20
@export_range(0, 1000) var run_weight_rest: int = 20
## Gold the party starts a run with.
@export_range(0, 10000) var run_start_gold: int = 0
## A rest heals every character by this percent of their max HP.
@export_range(0, 100, 1, "suffix:%") var run_rest_heal_percent: int = 50
## After a won fight, a downed character gets back up with this much HP.
@export_range(1, 1000) var run_downed_revive_hp: int = 1
## Levels: the first level up needs this much XP, each next one this much more. Each hero has
## their own level (DESIGN.md 8.2); each level adds these percents to max HP and power on top of
## the attribute points it gives.
@export_range(1, 100000) var run_xp_first_level: int = 60
@export_range(0, 100000) var run_xp_level_step: int = 30
@export_range(1, 99) var run_max_level: int = 10
@export_range(0, 100, 1, "suffix:%") var run_level_hp_percent: int = 4
@export_range(0, 100, 1, "suffix:%") var run_level_power_percent: int = 4
## A hero who is down when a fight is won gets this share of its XP (standing heroes get all).
@export_range(0, 100, 1, "suffix:%") var run_xp_downed_percent: int = 50
## Enemies grow with depth (DESIGN.md 8.3): each map row adds these percents to their HP and
## power (row 0: as in their data). Bosses only grow when run_enemy_scale_bosses is on.
@export_range(0, 100, 1, "suffix:%") var run_enemy_hp_row_percent: int = 5
@export_range(0, 100, 1, "suffix:%") var run_enemy_power_row_percent: int = 3
@export var run_enemy_scale_bosses: bool = false
## The team gauge carries over from fight to fight in a run (card #146): this share of what was
## left at the end of a fight starts the next one (0 = every fight starts empty).
@export_range(0, 100, 1, "suffix:%") var run_team_gauge_carry_percent: int = 100

@export_group("Run stops (phase 15)")
## How often a middle row's stop is an elite fight or a "?" event (weights beside run_weight_fight,
## _shop and _rest; DESIGN.md 8.6, 8.7). Elites never come before run_elite_min_row.
@export_range(0, 1000) var run_weight_elite: int = 12
@export_range(0, 1000) var run_weight_event: int = 25
@export_range(0, 30) var run_elite_min_row: int = 2
## Every stop of this row of an act's map is a treasure chest (DESIGN.md 8.8; -1: none).
@export_range(-1, 30) var run_treasure_row: int = 3
## Every stop of this row of an act's map is a Guard stop: the guard of that stop's place, fought
## before the run goes deeper (DESIGN.md 8.22; 0: none, row 0 always stays all Fight stops). It
## never moves, and it is never the campfire row before the final fight (a row that high: none).
## On run_treasure_row it keeps the row, and the chests stand on the row before it (after it when
## that is row 0).
@export_range(0, 30) var run_guard_row: int = 1
## Elite fights (elite map stops): enemies get these percents of their HP,
## power and gold.
@export_range(10, 1000, 1, "suffix:%") var elite_hp_percent: int = 140
@export_range(10, 1000, 1, "suffix:%") var elite_power_percent: int = 115
@export_range(10, 1000, 1, "suffix:%") var elite_gold_percent: int = 150
## Enemies get faster deeper in a run (card #188): each map row of depth takes this many percent
## off the fight's attack tempo (lower tempo = faster strings). Then elite, guard and boss fights
## take their own percent of that. Floored by attack_tempo_floor_percent. Practice fights keep
## the authored timing.
@export_range(0, 10, 1, "suffix:%") var run_enemy_tempo_row_percent: int = 1
@export_range(50, 100, 1, "suffix:%") var elite_tempo_percent: int = 94
@export_range(50, 100, 1, "suffix:%") var guard_tempo_percent: int = 94
@export_range(50, 100, 1, "suffix:%") var boss_tempo_percent: int = 92
## Spoils after a guard or an elite are gear of at least this rarity (0 common, 1 rare, 2
## legendary), when the run still has some.
@export_range(0, 2) var run_spoils_min_rarity: int = 1
## "?" stops (DESIGN.md 8.7). The chance (percent) that a "?" stop is an ambush fight instead of an
## event is unknown_fight_percent_base, plus unknown_fight_percent_step for every "?" stop passed
## without a fight since the last one (the count starts over after any ambush). Seeded per stop.
@export_range(0, 100, 1, "suffix:%") var unknown_fight_percent_base: int = 15
@export_range(0, 100, 1, "suffix:%") var unknown_fight_percent_step: int = 15
## Events pay (and charge) gold and XP grown by this percent per map row of depth (acts count the
## rows before them), so the same event stays a trade late in the run.
@export_range(0, 100, 1, "suffix:%") var event_reward_row_percent: int = 6
## An event cannot take a hero below this percent of their normal max HP (before levels and gear).
@export_range(1, 100, 1, "suffix:%") var event_max_hp_floor_percent: int = 40
## An ambush fight can be run from (DESIGN.md 2.13). Off: it is a commitment like an elite.
@export var ambush_can_run: bool = false
## A treasure stop also gives this much gold.
@export_range(0, 10000) var run_treasure_gold: int = 30
## Between acts (DESIGN.md 8.9) everyone heals this percent of their max HP.
@export_range(0, 100, 1, "suffix:%") var run_act_heal_percent: int = 50
## The shop (DESIGN.md 8.10): this many items on its shelves (picked from the run's shop list),
## and its services: throw away one rotten item, raise one item a level, new wares on the shelves.
@export_range(0, 30) var run_shop_items: int = 4
@export_range(0, 10000) var shop_cleanse_price: int = 35
@export_range(0, 10000) var shop_upgrade_price: int = 45
@export_range(0, 10000) var shop_restock_price: int = 20
## Each restock in one shop visit costs this much more than the last (card #175: stops gold from
## turning into endless Tonics by re-rolling the shelves).
@export_range(0, 10000) var shop_restock_step: int = 20
## A hero can drink at most this many Tonics (permanent max HP) in a run (card #175).
@export_range(0, 99) var tonic_max_per_hero: int = 2
## Campfire (DESIGN.md 8.11): Train gives every hero this many attribute points.
@export_range(0, 10) var rest_train_points: int = 1

@export_group("Attributes and critical hits")
## Attribute points (DESIGN.md 8.2): each level up gives this many to spend; a hero starts a run
## with attr_start_points.
@export_range(0, 20) var attr_points_per_level: int = 3
@export_range(0, 100) var attr_start_points: int = 0
## What one point in each attribute gives. Vitality: max HP percent. Might: power percent.
## Agility: speed. Defense: enemy hits deal this percent less. Luck: critical rate percent.
@export_range(0, 100, 1, "suffix:%") var attr_vitality_hp_percent: int = 3
@export_range(0, 100, 1, "suffix:%") var attr_might_power_percent: int = 3
@export_range(0, 100) var attr_agility_speed: int = 2
@export_range(0, 100, 1, "suffix:%") var attr_defense_percent: int = 2
@export_range(0, 100, 1, "suffix:%") var attr_luck_crit_percent: int = 2
## Every hero's chance that a hit is a critical hit, before Luck.
@export_range(0, 100, 1, "suffix:%") var crit_base_percent: int = 5
## A critical hit deals this percent of the normal damage.
@export_range(100, 1000, 1, "suffix:%") var crit_damage_percent: int = 150
## Enemy hits never lose more than this percent to Defense and gear together.
@export_range(0, 100, 1, "suffix:%") var tough_max_percent: int = 60

@export_group("Skill statuses")
## Bleeding (Open Vein): the enemy loses this percent of the source's power at the start of each of
## its turns. Renew: the hero heals this percent of max HP at the start of each of their turns.
@export_range(0, 500, 1, "suffix:%") var bleed_power_percent: int = 25
@export_range(0, 100, 1, "suffix:%") var regen_percent: int = 12
## Marked (Death Mark): skills on a marked enemy deal this percent more. Empowered (Shadowstep):
## the hero's next damaging skill deals this percent more.
@export_range(0, 500, 1, "suffix:%") var marked_bonus_percent: int = 40
@export_range(0, 500, 1, "suffix:%") var empowered_bonus_percent: int = 30
## Hero debuffs left by enemy hits (card #194). Rotting: the hero loses this percent of max HP at
## the start of each of their turns, never below 1 HP from rot alone. Blighted: healing they
## receive is cut by this percent. Weakened: their power is cut by this percent.
@export_range(0, 100, 1, "suffix:%") var rotting_percent: int = 6
@export_range(0, 100, 1, "suffix:%") var blighted_heal_cut_percent: int = 50
@export_range(0, 100, 1, "suffix:%") var weakened_power_cut_percent: int = 25
## Phase 19 marks (card #252). Burning: the hero loses this percent of max HP at the start of each
## of their turns (never below 1 HP from fire alone); it burns hotter than rot for fewer turns.
## Shocked: their timing windows (defence, skill presses, follow-ups) are this percent of normal.
@export_range(0, 100, 1, "suffix:%") var burning_percent: int = 10
@export_range(10, 100, 1, "suffix:%") var shocked_window_percent: int = 65
## Shielded (a Rot Priest's ward on a monster, card #259): it takes this percent less damage.
@export_range(0, 100, 1, "suffix:%") var shielded_damage_cut_percent: int = 40

@export_group("Skill trees")
## Skill trees (DESIGN.md 8.4, card #136): each level up gives this many skill points; the
## skill at place 0, 1, 2... of a branch costs skill_tier_costs at that place (0: known from the
## start); a hero brings at most skill_slots skills into a fight (the basic attack is extra).
@export_range(0, 10) var skill_points_per_level: int = 1
@export var skill_tier_costs: Array[int] = [0, 1, 2]
@export_range(1, 12) var skill_slots: int = 5

@export_group("Run gear")
## Relics: a guard's loot offers this many to pick one from; a shop sells this many (phase 17:
## the shelves' charms are gone, DESIGN.md 8.17).
@export_range(1, 6) var run_loot_choices: int = 3
## The map's campfire row is one row earlier this often, and its treasure row moves up to this many
## rows either way (card #286).
@export_range(0, 100, 1, "suffix:%") var run_rest_row_shift_percent: int = 50
@export_range(0, 4) var run_treasure_row_spread: int = 1
## The crowned elite (card #286): its enemies' HP and power on top of the elite numbers, in percent.
@export_range(100, 400, 1, "suffix:%") var crown_elite_hp_percent: int = 130
@export_range(100, 400, 1, "suffix:%") var crown_elite_power_percent: int = 115
## The rotten chest of a treasure stop (card #287): a better Relic, but this often a curse, and this
## often (on top) an ambush from the act's pool.
@export_range(0, 100, 1, "suffix:%") var rotten_chest_curse_percent: int = 30
@export_range(0, 100, 1, "suffix:%") var rotten_chest_fight_percent: int = 20
## The campfire before the boss (card #287): Sharpen gives every hero this much more AP at the start
## of the boss fight.
@export_range(0, 5) var sharpen_ap: int = 1
## How many starting pacts a run offers (card #285; RunData.pacts).
@export_range(0, 6) var run_pact_choices: int = 3
@export_range(0, 6) var run_shop_gear: int = 3
## Gear slots per character.
@export_range(1, 6) var run_gear_slots: int = 3
## Rot-touched gear (DESIGN.md 8.16): strong pieces with a price. Spoils (elite, boss) offer this
## many of them among their choices when the run has some left (never the only choice).
@export_range(0, 3) var rot_gear_spoils_count: int = 1
## Where rot-touched gear competes with the rest (shop shelves, chest prizes) its weight is this
## percent of a normal piece's, so shops sell it rarely.
@export_range(0, 100, 1, "suffix:%") var rot_gear_weight_percent: int = 35
## Last Ember style gear (Passive.LOW_HP_POWER) works while the wearer's HP is under this percent
## of their max.
@export_range(1, 99, 1, "suffix:%") var rot_low_hp_percent: int = 30

@export_group("Relics and Echoes")
## Relic slots open during a run (DESIGN.md 8.17): this many at the start, one more after the first
## guard is beaten and one more after act 1's boss, never more than run_gear_slots.
@export_range(1, 6) var relic_slots_start: int = 1
## The Relic bag (cards #265, #266): how many Relics the team can bring into a run (picked on the
## main menu's Relics page). It holds this many at first, one more for every
## relic_bag_echoes_per_slot Echoes learned for good, never more than relic_bag_max (DESIGN.md 8.19).
@export_range(1, 60) var relic_bag_start: int = 3
@export_range(1, 60) var relic_bag_echoes_per_slot: int = 5
@export_range(1, 60) var relic_bag_max: int = 6
## Relic levels last one run (phase 21, #280): a Relic joins a run at level 1 and a copy found in the
## run raises it, up to this one; a copy past it turns into relic_spare_gold.
@export_range(1, 10) var relic_max_level: int = 3
@export_range(0, 1000) var relic_spare_gold: int = 30
## Chance, per enemy beaten in a won run fight, that it drops one of its Relics.
@export_range(0, 100, 1, "suffix:%") var relic_drop_percent: int = 10
## In spoils, shops and chests a Relic the player already has (a copy) weighs this percent of a
## new one, so new Relics turn up more.
@export_range(0, 100, 1, "suffix:%") var relic_copy_weight_percent: int = 50
## Echo pips (DESIGN.md 8.19, #280): a worn Relic gets this many per won fight (by the fight's kind),
## kept from run to run; at mastery_needed its Echo is learned for good.
@export_range(0, 20) var mastery_fight: int = 1
@export_range(0, 20) var mastery_elite: int = 2
@export_range(0, 20) var mastery_guard: int = 3
@export_range(0, 20) var mastery_boss: int = 5
@export_range(1, 100) var mastery_needed: int = 4
## Echo points a hero has to wear Echoes: this many at level 1, plus this many per level up.
@export_range(0, 20) var echo_start_points: int = 0
@export_range(0, 10) var echo_points_per_level: int = 1
## Every enemy's power in run fights, in percent (phase 17: Relics stay between runs, so the base
## run is a little harder; practice fights keep their data).
@export_range(50, 300, 1, "suffix:%") var enemy_power_base_percent: int = 105

@export_group("Fight Rush")
## Fight Rush (DESIGN.md 8.21): map rows of depth each fight adds, in percent (100 = one row per
## fight, so fight n grows like map row n - 1 of a run).
@export_range(0, 400, 1, "suffix:%") var rush_depth_per_fight_percent: int = 100
## Extra enemy HP percent points per depth step in a Fight Rush, on top of run_enemy_hp_row_percent
## (lets HP keep climbing once the attack speed has reached attack_tempo_floor_percent).
@export_range(0, 50, 1, "suffix:%") var rush_enemy_hp_step_add: int = 0
## The same for enemy power, on top of run_enemy_power_row_percent.
@export_range(0, 50, 1, "suffix:%") var rush_enemy_power_step_add: int = 0
## Every Fight Rush enemy's HP, in percent, after the depth growth.
@export_range(1, 400, 1, "suffix:%") var rush_enemy_hp_percent: int = 100
## Every Fight Rush enemy's power, in percent, after the depth growth.
@export_range(1, 400, 1, "suffix:%") var rush_enemy_power_percent: int = 100
## Boss fights (guards too) grow with the depth past the depth a run meets them at (RushBoss.home_depth).
@export var rush_scale_bosses: bool = true
## Every Nth fight is an elite (unless it is a boss fight).
@export_range(2, 50) var rush_elite_every: int = 5
## Every Nth fight is the next boss of the cycle (RushData.bosses).
@export_range(2, 100) var rush_boss_every: int = 10
## The Heal card heals each hero this share of their max HP, before their Rest Relics change it.
@export_range(1, 100, 1, "suffix:%") var rush_heal_card_percent: int = 40
## Attribute points the Train card gives each hero.
@export_range(1, 5) var rush_point_card_points: int = 1
## The lowest rarity (0 common, 1 rare, 2 legendary) a Relic card offers while the pool still has some.
@export_range(0, 2) var rush_relic_min_rarity: int = 1
## A boss fight pays at least this much XP (the Hollow King's own data pays only 60).
@export_range(0, 2000) var rush_boss_min_xp: int = 260
## Every Fight Rush XP gain, in percent.
@export_range(1, 400, 1, "suffix:%") var rush_xp_percent: int = 100
## XP a hero earns past the top level builds toward one more reward pick per this much (the most any
## one hero earned in a fight counts).
@export_range(1, 5000) var rush_spare_pick_xp: int = 300
## After a boss fight everyone heals this share of their max HP (100 = full).
@export_range(0, 100, 1, "suffix:%") var rush_boss_heal_percent: int = 100

@export_group("Backpack")
## Alder's pack (DESIGN.md 8.1, 8.19, card #282): this many pockets at the start of a run, one
## item each; a Bigger Pack adds one, up to the max.
@export_range(1, 20) var backpack_pockets: int = 6
@export_range(1, 20) var backpack_max_pockets: int = 8
## A won Fight stop's fight drops a small item this often (DESIGN.md 8.22).
@export_range(0, 100, 1, "suffix:%") var item_drop_percent: int = 35
## Selling (an item at the shop, or gear swapped out for new gear) pays this share of its price.
@export_range(0, 100, 1, "suffix:%") var item_sell_percent: int = 50
## Rarity odds (DESIGN.md 8.1): when the run picks a find, a drop, a treasure chest or loot gear,
## each thing's chance is its weight times a rarity share: common 100%, rare item_rare_percent plus
## item_rare_row_percent per map row, legendary the same with its own numbers. So deeper stops
## turn up rarer things.
@export_range(0, 1000, 1, "suffix:%") var item_rare_percent: int = 50
@export_range(0, 1000, 1, "suffix:%") var item_rare_row_percent: int = 15
@export_range(0, 1000, 1, "suffix:%") var item_legendary_percent: int = 10
@export_range(0, 1000, 1, "suffix:%") var item_legendary_row_percent: int = 10
## Combining two of the same item (DESIGN.md 8.1) makes one a level higher: each level makes its
## effect (heal, damage, charm bonus) this percent stronger and its price that much higher.
@export_range(0, 1000, 1, "suffix:%") var combine_bonus_percent: int = 60

@export_group("Online")
## The port a host listens on and a client connects to (DESIGN.md 9.2).
@export_range(1024, 65535) var net_port: int = 7777
## A client gives up connecting (and a joiner gives up waiting for the host's welcome) after this.
@export_range(500, 60000, 1, "suffix:ms") var net_connect_timeout_ms: int = 6000
## Defence arbiter (host): a client that has not said it started playing an attack within this
## long after the attack was declared is treated as having started then.
@export_range(0, 30000, 1, "suffix:ms") var net_ack_timeout_ms: int = 3000
## Defence arbiter (host): a remote player's prompt is resolved as a hit (NONE) this long after it
## should have closed on their machine (plus hit-stops) if no result arrived.
@export_range(0, 30000, 1, "suffix:ms") var net_deadline_grace_ms: int = 1500
## Heartbeat (card #205): a connection that answers nothing (a pulled cable, a crash, Wi-Fi gone)
## counts as lost after at least the first and at most the second of these. Both ends keep pinging
## each other, so a silent drop never freezes a fight longer than this.
@export_range(500, 60000, 1, "suffix:ms") var net_drop_min_ms: int = 3000
@export_range(500, 60000, 1, "suffix:ms") var net_drop_max_ms: int = 6000
## A client that dropped mid-run keeps its seat this long (the host plays its heroes meanwhile); it
## can join again with the host's address and play on. After this the seat is given up (0: never kept).
@export_range(0, 1800000, 1, "suffix:ms") var net_rejoin_grace_ms: int = 120000
## A newcomer may take the seat of a player away at least this long (a friend whose game crashed
## comes back this way, card #304); a fresher away seat is held for its own token (a quick rejoin).
@export_range(0, 1800000, 1, "suffix:ms") var net_takeover_after_ms: int = 15000

@export_group("Controls")
## Settings > Controls (card #190): after picking a key or button to change, the game waits this
## long for the new one, then gives up and leaves the old one.
@export_range(1000, 30000, 100, "suffix:ms") var rebind_capture_ms: int = 6000
## Picking Reset to defaults asks twice; the second press must come within this long.
@export_range(500, 10000, 100, "suffix:ms") var rebind_reset_confirm_ms: int = 4000

@export_group("Practice and debug")
## Phase 1 practice keys: 1-5 force an enemy attack, I = party cannot die,
## O = enemy cannot die, R = restart, F1 = stats overlay, F2 = lag calibration.
@export var practice_tools_enabled: bool = true
## 0 = a new random fight every time. Any other number replays the same enemy choices.
@export var fixed_seed: int = 0


## Window edges in microseconds relative to impact: Vector2i(early (negative), late (positive)).
@warning_ignore("integer_division")
func window_edges_us(window_ms: int) -> Vector2i:
	var total_us: int = window_ms * 1000
	var late_us: int = (total_us * window_late_percent + 50) / 100
	return Vector2i(late_us - total_us, late_us)
