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
## Speed of every enemy attack, in percent of its authored timing. 120 = 20% slower.
@export_range(25, 300, 1, "suffix:%") var attack_tempo_percent: int = 100
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
## When a hit's motion starts, its icon pops up beside each target (and a floor warning glows
## under them for a ground hit) until it lands. Toggle in a fight with F1 > H.
@export var show_hit_markers: bool = true
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
## Short pause between turns.
@export_range(0, 2000, 1, "suffix:ms") var turn_gap_ms: int = 200
## How long damage numbers and result popups stay up.
@export_range(100, 5000, 1, "suffix:ms") var popup_ms: int = 900
## Freeze on a good skill or follow-up press.
@export_range(0, 300, 1, "suffix:ms") var hitstop_press_ms: int = 60
## Time after a skill's last press (or follow-up) before the turn moves on.
@export_range(0, 3000, 1, "suffix:ms") var skill_recover_ms: int = 350

@export_group("Exploration")
## How fast the leader walks (world units per second).
@export_range(0.5, 20.0, 0.1) var explore_walk_speed: float = 4.5
## Roaming enemies wander this fast, and chase this fast (keep chasing below walking, so you can
## get away or turn around and strike first).
@export_range(0.1, 20.0, 0.1) var explore_wander_speed: float = 1.2
@export_range(0.1, 20.0, 0.1) var explore_chase_speed: float = 3.6
## A roaming enemy notices the leader within this distance, shows "!" for notice ms, then chases
## until the leader is further than give-up distance from it.
@export_range(0.5, 50.0, 0.1) var explore_notice_radius: float = 5.0
@export_range(0, 3000, 1, "suffix:ms") var explore_notice_ms: int = 450
@export_range(0.5, 80.0, 0.1) var explore_give_up_radius: float = 9.0
## Between wander walks a roaming enemy stands still for a random time in this range.
@export_range(0, 10000, 1, "suffix:ms") var explore_pause_min_ms: int = 800
@export_range(0, 10000, 1, "suffix:ms") var explore_pause_max_ms: int = 2200
## A roaming enemy closer than this to the leader touches them: the fight starts, no advantage.
@export_range(0.1, 5.0, 0.05) var explore_touch_radius: float = 0.9
## The field strike hits a roaming enemy within this reach and this arc in front of the leader:
## the fight starts with a FIRST STRIKE (DESIGN.md 2.12). One strike lasts strike ms.
@export_range(0.1, 10.0, 0.05) var explore_strike_reach: float = 1.8
@export_range(10.0, 360.0, 1.0) var explore_strike_arc_degrees: float = 140.0
@export_range(50, 2000, 1, "suffix:ms") var explore_strike_ms: int = 320
## After coming back from a fight, no roaming enemy can start a fight for this long.
@export_range(0, 10000, 1, "suffix:ms") var explore_return_grace_ms: int = 1500

@export_group("Run")
## Rows of stops on the run map before the final fight (the final fight is one more stop).
@export_range(2, 30) var run_map_rows: int = 7
## Each row has this many stops side by side, picked at random between the two numbers.
@export_range(1, 6) var run_map_min_width: int = 2
@export_range(1, 6) var run_map_max_width: int = 3
## Chance, per stop, of an extra path to a neighbouring stop in the next row (more choices).
@export_range(0, 100, 1, "suffix:%") var run_map_extra_path_percent: int = 40
## How often a middle row's stop is a zone, a shop or a rest (weights, not percents). The first
## row is always zones, the last row before the final fight always rests.
@export_range(0, 1000) var run_weight_zone: int = 60
@export_range(0, 1000) var run_weight_shop: int = 20
@export_range(0, 1000) var run_weight_rest: int = 20
## Gold the party starts a run with.
@export_range(0, 10000) var run_start_gold: int = 0
## A rest heals every character by this percent of their max HP.
@export_range(0, 100, 1, "suffix:%") var run_rest_heal_percent: int = 50
## After a won fight, a downed character gets back up with this much HP.
@export_range(1, 1000) var run_downed_revive_hp: int = 1
## Levels: the first level up needs this much XP, each next one this much more. The whole party
## levels together; each level adds these percents to max HP and power (DESIGN.md 8).
@export_range(1, 100000) var run_xp_first_level: int = 60
@export_range(0, 100000) var run_xp_level_step: int = 30
@export_range(1, 99) var run_max_level: int = 10
@export_range(0, 100, 1, "suffix:%") var run_level_hp_percent: int = 8
@export_range(0, 100, 1, "suffix:%") var run_level_power_percent: int = 8
## Gear: a guard's loot offers this many items to pick one from; a shop sells this many.
@export_range(1, 6) var run_loot_choices: int = 3
@export_range(0, 6) var run_shop_gear: int = 2
## Gear slots per character.
@export_range(1, 6) var run_gear_slots: int = 3

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
## Zones: the host sends the leader and roaming enemy positions this many times a second.
@export_range(1, 60) var net_zone_send_hz: int = 20

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
