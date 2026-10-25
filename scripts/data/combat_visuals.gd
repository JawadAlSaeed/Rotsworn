class_name CombatVisuals
extends Resource
## Presentation-only data for the combat scene: effect and UI art paths, the stage layout and its
## look (stage_look), the camera (depth of field, cinematic shots), animation and cue feel, and the
## lag calibration procedure. Rules, damage and the defence windows
## live in tuning.tres. The one link to judging: the calibration's result is saved per machine
## (user://settings.cfg) and replaces tuning's input_latency_compensation_ms, within tuning's
## calibration_min_ms .. calibration_max_ms.
## Edit data/presentation/combat_visuals.tres. Replace art by overwriting the file at a path.

@export_group("Effect art")
## Star burst for parries (16x16, transparent background).
@export_file_path("*.png") var spark_path: String = "res://assets/sprites/fx/spark.png"
## Crest of a ground wave (64x16, transparent background).
@export_file_path("*.png") var shockwave_path: String = "res://assets/sprites/fx/shockwave.png"
## Soft dark ellipse drawn under every fighter (32x12).
@export_file_path("*.png") var shadow_path: String = "res://assets/sprites/fx/shadow.png"
## White arc shown when a party member strikes (32x32).
@export_file_path("*.png") var slash_path: String = "res://assets/sprites/fx/slash.png"

@export_group("Stage")
## How the fight list's fights look (ground, light, fog, bloom, arena decoration). A run fight uses
## its place's look instead.
@export var stage_look: StageLook

@export_group("UI art")
## Padlock shown over the party during a whiff lockout (12x12).
@export_file_path("*.png") var lock_icon_path: String = "res://assets/sprites/ui/lock.png"
## Filled AP gem (10x10).
@export_file_path("*.png") var ap_pip_path: String = "res://assets/sprites/ui/ap_pip.png"
## Empty AP gem (10x10).
@export_file_path("*.png") var ap_pip_empty_path: String = "res://assets/sprites/ui/ap_pip_empty.png"
## Enemy intent icon for a normal hit: parry or dodge it (12x12).
@export_file_path("*.png") var hit_icon_normal_path: String = "res://assets/sprites/ui/hit_normal.png"
## Enemy intent icon for a ground hit: jump it (12x12).
@export_file_path("*.png") var hit_icon_ground_path: String = "res://assets/sprites/ui/hit_ground.png"
## Enemy intent icon for a rend: parry it, nothing else works (12x12, card #187).
@export_file_path("*.png") var hit_icon_rend_path: String = "res://assets/sprites/ui/hit_rend.png"
## Enemy intent icon for a sweep: dodge it, nothing else works (12x12, card #187).
@export_file_path("*.png") var hit_icon_sweep_path: String = "res://assets/sprites/ui/hit_sweep.png"
## Enemy intent icon for a thrown normal hit: still parry or dodge it, but it flies in (12x12,
## card #278).
@export_file_path("*.png") var hit_icon_ranged_path: String = "res://assets/sprites/ui/hit_ranged.png"

@export_group("Stage layout")
## Where each party slot stands (feet). Keep them on one straight line: ground waves travel with
## a front parallel to that line so they reach everyone at the same moment.
@export var party_positions: Array[Vector3] = [Vector3(-2.1, 0.0, -1.5), Vector3(-2.9, 0.0, 0.0), Vector3(-3.7, 0.0, 1.5)]
## Where each enemy slot stands (feet): a diagonal line, the heroes' mirror image (user, phase 19),
## so no monster stands straight behind another. The middle spot first (a lone monster stands
## there), then the front one, then the back one.
@export var enemy_positions: Array[Vector3] = [Vector3(2.9, 0.0, 0.0), Vector3(3.7, 0.0, 1.5), Vector3(2.1, 0.0, -1.5)]
## True if the character sheets are drawn facing right (the party faces right, toward the enemy).
@export var party_art_faces_right: bool = true
## True if the enemy sheets are drawn facing left (the enemy faces left, toward the party).
@export var enemy_art_faces_left: bool = true
@export var camera_position: Vector3 = Vector3(0.8, 3.4, 10.0)
@export var camera_target: Vector3 = Vector3(0.0, 1.0, 0.0)
## Vertical field of view in degrees.
@export_range(10.0, 100.0, 0.5) var camera_fov: float = 40.0
## World units per pixel for sparks, slashes and shockwaves.
@export_range(0.001, 0.2, 0.001) var fx_pixel_size: float = 0.045
## Width of the shadow blob under each fighter, as a fraction of the sprite frame width.
@export_range(0.05, 3.0, 0.05) var shadow_width_factor: float = 0.85
## How far over the floor the shadow blob lies (world units): over every stacked ground piece
## (StageLook ground_lift and ground_step, card #269), so a fighter on a road keeps its shadow.
@export_range(0.0, 0.5, 0.001) var shadow_lift: float = 0.06
## How far in front of the target an enemy lunge connects (world units).
@export_range(0.1, 6.0, 0.05) var contact_gap: float = 1.6
## How far in front of the enemy a party member strikes (world units).
@export_range(0.1, 6.0, 0.05) var strike_gap: float = 1.5
## Height of popups and lock icons above a fighter's feet, as a fraction of the visible height of
## its art (the opaque pixels of the first frame, so empty space at the top of a frame is ignored).
@export_range(0.0, 2.0, 0.05) var head_height_factor: float = 1.05

@export_group("Depth of field")
## The combat camera blurs what is further than far distance (fading in over far transition) and
## nearer than near distance: the HD-2D miniature look. World units from the camera.
@export var dof_far_enabled: bool = true
@export_range(0.1, 200.0, 0.1) var dof_far_distance: float = 14.0
@export_range(0.0, 100.0, 0.1) var dof_far_transition: float = 6.0
@export var dof_near_enabled: bool = true
@export_range(0.0, 50.0, 0.1) var dof_near_distance: float = 4.0
@export_range(0.0, 50.0, 0.1) var dof_near_transition: float = 2.0
@export_range(0.0, 1.0, 0.01) var dof_amount: float = 0.1

@export_group("Cinematic camera")
## The camera glides to each new shot with this time constant (it arrives after about four of
## them). Real time: a hit-stop does not freeze it. Toggle the moves in a fight with F1 > V.
@export_range(10, 2000, 1, "suffix:ms") var shot_glide_ms: int = 160
## Party turn: the view drifts this share of the way toward the party member whose turn it is and
## moves this much closer (world units).
@export_range(0.0, 1.0, 0.01) var turn_focus_share: float = 0.2
@export_range(0.0, 10.0, 0.05) var turn_push: float = 0.8
## Basic attacks and skills: the camera sits at this offset from the middle of the strikers and
## their target, with this field of view.
@export var skill_shot_offset: Vector3 = Vector3(-1.4, 2.0, 6.6)
@export_range(10.0, 100.0, 0.5) var skill_shot_fov: float = 36.0
## Team ultimate: a low shot that slowly circles the middle of the party and the target.
@export var ultimate_shot_offset: Vector3 = Vector3(0.6, 0.9, 5.4)
@export_range(10.0, 100.0, 0.5) var ultimate_shot_fov: float = 34.0
@export_range(-90.0, 90.0, 0.5) var ultimate_orbit_degrees_per_s: float = 9.0
## Enemy attack: the view's centre moves this share of the way to the middle of the attacker and
## its targets, and the camera moves this much closer. It glides there during the banner lead-in
## and then holds still while you defend.
@export_range(0.0, 1.0, 0.01) var attack_focus_share: float = 0.35
@export_range(0.0, 10.0, 0.05) var attack_push: float = 1.2
## Follow-ups: the camera pulls back until every ally pressing and the enemy fit inside this part
## of the screen (shares from the top left), clear of the banner and the party panels.
@export var follow_up_safe_area: Rect2 = Rect2(0.1, 0.24, 0.8, 0.5)
## Counter and team counter: a quick push toward the enemy (world units).
@export_range(0.0, 10.0, 0.05) var counter_push: float = 2.0
## Victory and defeat: the camera circles the arena at this offset from its middle.
@export var end_shot_offset: Vector3 = Vector3(0.0, 2.6, 8.5)
@export_range(-90.0, 90.0, 0.5) var end_orbit_degrees_per_s: float = 8.0

@export_group("Enemy choreography")
## A feint starts its false lunge this long before the real lunge.
@export_range(0, 2000, 1, "suffix:ms") var feint_lead_ms: int = 350
## How much of a normal lunge the false start plays before it stops, in percent of approach time.
@export_range(10, 90, 1, "suffix:%") var feint_portion_percent: int = 60
## The enemy holds its contact pose at least this long after a hit, and on an attack's last hit
## until the hit can no longer be defended (window late edge + lag compensation), so a missed
## hit's flinch and damage appear while the enemy is still in contact.
@export_range(0, 1000, 1, "suffix:ms") var contact_hold_ms: int = 90
## Between hits the enemy recoils back over this long.
@export_range(0, 1000, 1, "suffix:ms") var recoil_ms: int = 120
## Between hits the recoil always gets at least this long (the contact hold is shortened to fit).
@export_range(0, 1000, 1, "suffix:ms") var recoil_min_ms: int = 40
## On an attack's last hit the contact pose lasts this long past the moment the hit can no longer
## be defended (the hit lands on the next frame, then its hurt freeze plays). Keep it above
## tuning's hitstop_hurt_ms plus a frame.
@export_range(0, 1000, 1, "suffix:ms") var contact_after_close_ms: int = 70
## How far it recoils, in percent of the distance between home and the contact point.
@export_range(0, 100, 1, "suffix:%") var recoil_percent: int = 35
## After the last hit the enemy walks home over this long.
@export_range(0, 2000, 1, "suffix:ms") var return_ms: int = 260
## An attacker that ran up (DESIGN.md 3.12) stops this far short of the contact point (world units)
## and steps the rest of the way in as it swings.
@export_range(0.0, 6.0, 0.05) var swing_step: float = 1.0
## One cycle of its chase loop while it runs up.
@export_range(50, 2000, 1, "suffix:ms") var run_up_cycle_ms: int = 400
## Where a charging attacker winds up (card #310, DESIGN.md 3.12; which attacks charge is tuning
## charge_windup_min_ms): this share of the way from home to its first contact point (0 = where it
## stands, as the owner asked; never past where a run-up would stop). Above 0 it steps there during
## the wind-up's coil, gliding while its coil cells play, so its charge covers the rest of the way.
@export_range(0.0, 1.0, 0.01) var charge_windup_share: float = 0.15
## The slam pose is held this long when a ground wave is launched.
@export_range(0, 2000, 1, "suffix:ms") var slam_hold_ms: int = 260
## The throw pose is held this long when a ranged hit leaves (DESIGN.md 3.9).
@export_range(0, 2000, 1, "suffix:ms") var shoot_hold_ms: int = 220
## Length of the telegraph flash when a lunge starts.
@export_range(0, 1000, 1, "suffix:ms") var telegraph_flash_ms: int = 90
## Strength of the telegraph flash (0 to 1).
@export_range(0.0, 1.0, 0.05) var telegraph_flash_strength: float = 0.55
## Colour of the telegraph flash. Keep it different from white: white means "you parried".
@export var telegraph_flash_color: Color = Color(1.0, 0.3, 0.2)
## A ground wave stays fully visible until its hit can no longer be jumped, then fades out over
## this long while it travels on past the party.
@export_range(10, 2000, 1, "suffix:ms") var wave_fade_ms: int = 150
## Number of crest sprites that make up one wave front.
@export_range(1, 12) var wave_crest_count: int = 5
## Shortest distance a wave travels (world units), even if the enemy slams up close.
@export_range(0.1, 10.0, 0.05) var wave_min_travel: float = 2.0
## How far the wave front extends past the outer party members (world units).
@export_range(0.0, 5.0, 0.05) var wave_line_margin: float = 0.8
## A glowing band lies on the floor along the wave front, so you see exactly where the front is
## and when it reaches each hero (card #114): its depth (world units) and strength (0 to 1).
@export_range(0.05, 3.0, 0.05) var wave_band_depth: float = 0.45
@export_range(0.0, 1.0, 0.05) var wave_band_strength: float = 0.75
## When a ground hit arrives, the floor warning under each target flashes bright for this long.
@export_range(0, 1000, 1, "suffix:ms") var floor_flash_ms: int = 160
## Glow colour of the enemy wind-up.
@export var windup_glow_color: Color = Color(1.0, 0.45, 0.2)
## How strongly the wind-up glow is added on top of the sprite (0 to 1).
@export_range(0.0, 1.0, 0.05) var windup_glow_strength: float = 0.35
## While winding up, the enemy crouches: it gets this much shorter (and wider) at full glow, then
## springs back as the lunge or slam starts. Toggle in a fight with F1 > C.
@export_range(0, 50, 1, "suffix:%") var windup_squash_percent: int = 12

@export_group("Projectiles and rocks")
## A parried projectile flies back up toward the enemy and fades over this long, this far.
@export_range(10, 2000, 1, "suffix:ms") var projectile_deflect_ms: int = 280
@export_range(0.0, 10.0, 0.05) var projectile_deflect_distance: float = 2.4
@export_range(0.0, 5.0, 0.05) var projectile_deflect_rise: float = 1.6
## A dodged projectile flies on past the hero and fades over this long, this far.
@export_range(10, 2000, 1, "suffix:ms") var projectile_pass_ms: int = 220
@export_range(0.0, 10.0, 0.05) var projectile_pass_distance: float = 2.2
## Sparks in the projectile's colour when it hits.
@export_range(0, 40) var projectile_burst_sparks: int = 7
## Rock ground hits (AttackHitData.GroundLook.ROCKS): sheet of rock spikes (one row of
## rock_hframes shapes, feet on the bottom row), drawn at fx_pixel_size times rock_scale.
@export_file_path("*.png") var rock_path: String = "res://assets/sprites/fx/rock_spike.png"
@export_range(1, 16) var rock_hframes: int = 4
@export_range(0.1, 4.0, 0.05) var rock_scale: float = 1.0
## Rows of rocks along each lane, this far apart (world units); the last row bursts under the
## target exactly at impact, rock_final_count rocks rock_final_scale times bigger.
@export_range(0.1, 5.0, 0.05) var rock_row_spacing: float = 0.75
@export_range(1, 6) var rock_final_count: int = 3
@export_range(0.5, 4.0, 0.05) var rock_final_scale: float = 1.5
## Sideways scatter of the rocks in a lane (world units).
@export_range(0.0, 2.0, 0.05) var rock_scatter: float = 0.18
## Each rock rises over rock_rise_ms, stands rock_hold_ms, then sinks over rock_sink_ms (attack
## time). The last row stands until the hit can no longer be jumped.
@export_range(10, 1000, 1, "suffix:ms") var rock_rise_ms: int = 80
@export_range(0, 2000, 1, "suffix:ms") var rock_hold_ms: int = 220
@export_range(10, 2000, 1, "suffix:ms") var rock_sink_ms: int = 220

@export_group("Reading attacks")
## Colour of a ground hit (jump it) everywhere: wind-up glow and flash before a slam, the hit
## marker, the floor warning and the training ring. Keep it apart from red-orange (normal hits,
## the telegraph) and white (a parry).
@export var ground_hit_color: Color = Color(0.78, 0.4, 1.0)
## Border colour of a normal hit's marker (parry or dodge it).
@export var normal_hit_color: Color = Color(1.0, 0.3, 0.2)
## Colour of a rend (parry only, card #187) everywhere a hit shows its kind: the wind-up glow and
## telegraph flash before it, its marker and ring. Bone, near the PARRY readout's yellow, never
## pure white (white means "you parried").
@export var rend_hit_color: Color = Color(0.96, 0.86, 0.58)
## Colour of a sweep (dodge only, card #187): sickly green, near the DODGE readout's green.
@export var sweep_hit_color: Color = Color(0.6, 0.86, 0.22)
## Rhythm rows (intent sign and attack banner): icon centres are this many pixels apart per
## millisecond between impacts, so the beat and the pauses of a string show.
@export_range(0.01, 2.0, 0.01) var rhythm_px_per_ms: float = 0.2
## Icons in a rhythm row are never closer than their size plus this gap (pixels at 1080p).
@export_range(0.0, 64.0, 1.0) var rhythm_min_gap_px: float = 4.0
## A longer row is squeezed to this width (pixels at 1080p).
@export_range(32.0, 1600.0, 1.0) var rhythm_max_width_px: float = 420.0
## The hit whose motion is playing grows to this scale in the banner row; landed hits fade to
## this opacity.
@export_range(1.0, 3.0, 0.05) var rhythm_active_scale: float = 1.4
@export_range(0.0, 1.0, 0.05) var rhythm_done_alpha: float = 0.3
## Faint line joining the icons of a rhythm row.
@export var rhythm_line_color: Color = Color(1.0, 1.0, 1.0, 0.3)
## A feint's hit icon wears a dashed ring (card #129): its colour, size (times the icon), line
## width and number of dashes.
@export var rhythm_feint_color: Color = Color(1.0, 0.6, 0.15, 1.0)
@export_range(1.0, 3.0, 0.05) var rhythm_feint_ring_scale: float = 1.3
@export_range(1.0, 8.0, 0.5) var rhythm_feint_ring_px: float = 3.0
@export_range(2, 24) var rhythm_feint_dashes: int = 8
## Size of the hit icons in the attack banner (pixels at 1080p).
@export_range(8.0, 128.0, 1.0) var banner_icon_px: float = 40.0
## Hit marker: when a hit's motion starts, its icon pops up beside each target, on the side the
## hit comes from, until it lands. Toggle in a fight with F1 > H.
@export_range(8.0, 200.0, 1.0) var hit_marker_px: float = 52.0
## Marker position from the target's middle on screen (pixels at 1080p); x points toward the
## attacking enemy.
@export var hit_marker_offset_px: Vector2 = Vector2(95.0, -20.0)
## The marker pops in from this scale over this long (attack time, so hit-stop freezes it).
@export_range(1.0, 4.0, 0.05) var hit_marker_pop_scale: float = 1.6
@export_range(0, 1000, 1, "suffix:ms") var hit_marker_pop_ms: int = 120
## Ranged-hit indicator (DESIGN.md 3.9, card #165): on every hero a thrown projectile flies at,
## four corner brackets close in from ranged_aim_start_px to ranged_aim_end_px (half size, pixels
## at 1080p) and meet exactly at the hit's impact, with a dashed path (ranged_aim_dash_px dashes,
## ranged_aim_gap_px apart, ranged_aim_path_points samples of the flight arc) from the projectile
## to the hero. It shows ranged_aim_lead_ms before the throw, fades in and out over
## ranged_aim_fade_ms and, when the bracket locks, brightens for ranged_aim_pulse_ms (scaled by
## the Flashes setting). A rend or a sweep names its button under the bracket.
@export_range(0, 2000, 10, "suffix:ms") var ranged_aim_lead_ms: int = 300
@export_range(1, 1000, 1, "suffix:ms") var ranged_aim_fade_ms: int = 140
@export_range(8.0, 400.0, 1.0) var ranged_aim_start_px: float = 120.0
@export_range(8.0, 400.0, 1.0) var ranged_aim_end_px: float = 46.0
@export_range(1.0, 16.0, 0.5) var ranged_aim_line_px: float = 5.0
@export_range(2.0, 60.0, 1.0) var ranged_aim_dash_px: float = 16.0
@export_range(2.0, 60.0, 1.0) var ranged_aim_gap_px: float = 10.0
@export_range(2, 40) var ranged_aim_path_points: int = 14
@export_range(0.0, 1.0, 0.05) var ranged_aim_path_strength: float = 0.7
@export_range(0, 1000, 1, "suffix:ms") var ranged_aim_pulse_ms: int = 180
@export var ranged_aim_label: bool = true
## Floor warning under each target of a ground hit, from the slam until the wave arrives: its
## diameter (world units) and its strength when the wave arrives (it starts fainter).
@export_range(0.1, 6.0, 0.05) var floor_warning_size: float = 1.9
@export_range(0.0, 1.0, 0.05) var floor_warning_strength: float = 0.85

@export_group("Party defence poses")
## Parry stance lasts at least this long (and at least until the parry window closes).
@export_range(0, 2000, 1, "suffix:ms") var parry_pose_min_ms: int = 150
## Dodge pose lasts at least this long (and at least until the dodge window closes).
@export_range(0, 2000, 1, "suffix:ms") var dodge_pose_min_ms: int = 250
## How far a dodge slides back (world units).
@export_range(0.0, 3.0, 0.05) var dodge_slide_distance: float = 0.75
## Total time in the air for a jump.
@export_range(100, 2000, 1, "suffix:ms") var jump_airtime_ms: int = 480
## Fastest rise from take-off to the apex. The apex sits at impact when the press leaves time;
## a press close to (or after) impact rises this fast, and its contact moment (sound, popup,
## freeze) waits until the body is clear of the wave.
@export_range(20, 1000, 1, "suffix:ms") var jump_rise_fast_ms: int = 60
## Jump height (world units).
@export_range(0.1, 5.0, 0.05) var jump_height: float = 1.3
## A failed press shows its pose for this long.
@export_range(0, 2000, 1, "suffix:ms") var whiff_pose_ms: int = 260
## Flinch after a hit lands.
@export_range(0, 2000, 1, "suffix:ms") var hurt_pose_ms: int = 320
## Flinch knock-back distance (world units).
@export_range(0.0, 2.0, 0.05) var hurt_knockback: float = 0.35
## White flash length on parries and hits.
@export_range(0, 1000, 1, "suffix:ms") var flash_ms: int = 120
## How strongly a beaten enemy flashes its death colour (0 to 1).
@export_range(0.0, 1.0, 0.05) var death_flash_strength: float = 0.8
## Flash strengths (0 to 1): a failed press, the enemy on a parry, a jump, a hit taken.
@export_range(0.0, 1.0, 0.05) var whiff_flash_strength: float = 0.35
@export_range(0.0, 1.0, 0.05) var parry_enemy_flash_strength: float = 0.6
@export_range(0.0, 1.0, 0.05) var jump_flash_strength: float = 0.5
@export_range(0.0, 1.0, 0.05) var dodge_flash_strength: float = 0.3
@export_range(0.0, 1.0, 0.05) var hurt_flash_strength: float = 0.8
## During a single-target attack the other party members step back this far (world units) and
## take this tint, so the lunge lane and the target are clear.
@export_range(0.0, 3.0, 0.05) var bystander_step_back: float = 0.8
@export var bystander_tint: Color = Color(0.55, 0.55, 0.62)
## Volume change of the muted click for a press during lockout.
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var locked_click_volume_db: float = -10.0

@export_group("Effects")
@export_range(0, 32) var sparks_per_parry: int = 8
## How far sparks fly (world units).
@export_range(0.0, 5.0, 0.05) var spark_spread: float = 1.1
@export_range(10, 2000, 1, "suffix:ms") var spark_ms: int = 280
## Sparks appear this far from the defender's centre toward the attacker, as a share of the gap.
@export_range(0.0, 1.0, 0.01) var spark_toward_enemy: float = 0.12
@export_range(10, 2000, 1, "suffix:ms") var slash_ms: int = 220
## Scale of the slash sprite.
@export_range(0.1, 10.0, 0.05) var slash_scale: float = 1.0
## Team counter: attackers keep this share of their formation spacing at the strike point, and
## their slashes land this far apart.
@export_range(0.0, 2.0, 0.05) var team_strike_spread: float = 0.7
@export_range(0, 500, 1, "suffix:ms") var team_slash_gap_ms: int = 70

@export_group("Camera feel")
## Camera shake is a trauma model (CameraTrauma, card #179). Every impact below adds trauma (0 to
## 1, clamped; they stack, so a string of parries builds up). Trauma drains by shake_decay_per_s a
## second, and the shown shake is trauma SQUARED times shake_max_offset (world units) plus a roll of
## up to shake_max_roll_deg degrees, wobbling at shake_hz (the base frequency of three sines; keep
## it under about 7 so the top layer stays under half of a 60 fps frame rate).
@export_range(1.0, 12.0, 0.5, "suffix:Hz") var shake_hz: float = 6.0
@export_range(0.1, 10.0, 0.05, "suffix:/s") var shake_decay_per_s: float = 1.5
@export_range(0.0, 2.0, 0.01) var shake_max_offset: float = 0.32
@export_range(0.0, 10.0, 0.1, "suffix:deg") var shake_max_roll_deg: float = 1.6
## Trauma when a hit lands on the party, and when it is a heavy hit (big_hit_percent of max HP).
@export_range(0.0, 1.0, 0.01) var shake_hurt: float = 0.3
@export_range(0.0, 1.0, 0.01) var shake_hurt_heavy: float = 0.7
## Trauma on a parry, and on the parry of the last hit; a dodge only nudges.
@export_range(0.0, 1.0, 0.01) var shake_parry: float = 0.4
@export_range(0.0, 1.0, 0.01) var shake_parry_final: float = 0.7
@export_range(0.0, 1.0, 0.01) var shake_dodge: float = 0.1
## Camera punch-in on a parry (world units toward the target).
@export_range(0.0, 5.0, 0.05) var punch_parry: float = 0.35
## Bigger punch-in on the parry of the last hit.
@export_range(0.0, 5.0, 0.05) var punch_parry_final: float = 0.8
## A heavy hit on the party punches in a little.
@export_range(0.0, 5.0, 0.05) var punch_hurt_heavy: float = 0.4
## Party strikes: a graze or good press, a perfect press, a critical hit, one hit of the Team
## Ultimate. Each also has its own punch-in. Sparks grow with the tier (a share of sparks_per_strike).
@export_range(0.0, 1.0, 0.01) var shake_strike: float = 0.2
@export_range(0.0, 1.0, 0.01) var shake_strike_perfect: float = 0.4
@export_range(0.0, 5.0, 0.05) var punch_strike_perfect: float = 0.3
@export_range(0.0, 1.0, 0.01) var shake_crit: float = 0.55
@export_range(0.0, 5.0, 0.05) var punch_crit: float = 0.5
@export_range(0.0, 1.0, 0.01) var shake_ultimate_hit: float = 0.5
@export_range(0.0, 5.0, 0.05) var punch_ultimate_hit: float = 0.35
@export_range(100, 400, 5, "suffix:%") var spark_tier_medium_percent: int = 150
@export_range(100, 600, 5, "suffix:%") var spark_tier_large_percent: int = 220
## Counters: trauma and punch-in for a counter and a team counter.
@export_range(0.0, 1.0, 0.01) var shake_counter: float = 0.7
@export_range(0.0, 5.0, 0.05) var punch_counter: float = 0.9
@export_range(0.0, 1.0, 0.01) var shake_team_counter: float = 0.9
@export_range(0.0, 5.0, 0.05) var punch_team_counter: float = 1.2
## How long a punch-in takes to settle back.
@export_range(10, 2000, 1, "suffix:ms") var punch_ms: int = 220
## The large tier (card #179): the last enemy falling, and a boss or guard falling. The body holds
## on its hurt pose for the freeze (kept short), while the camera shakes and punches in and the
## screen flashes, before the end shot starts. Shake is trauma; flash is screen flash strength.
@export_range(0, 400, 5, "suffix:ms") var kill_hitstop_ms: int = 110
@export_range(0.0, 1.0, 0.01) var kill_shake: float = 0.8
@export_range(0.0, 5.0, 0.05) var kill_punch: float = 0.9
@export_range(0.0, 1.0, 0.01) var kill_flash: float = 0.25
@export_range(0, 400, 5, "suffix:ms") var boss_kill_hitstop_ms: int = 170
@export_range(0.0, 1.0, 0.01) var boss_kill_shake: float = 1.0
@export_range(0.0, 5.0, 0.05) var boss_kill_punch: float = 1.4
@export_range(0.0, 1.0, 0.01) var boss_kill_flash: float = 0.45
## A boss entering its next phase: trauma, a punch-in that settles over phase_punch_ms.
@export_range(0.0, 1.0, 0.01) var phase_shake: float = 0.9
@export_range(0.0, 5.0, 0.05) var phase_punch: float = 1.0
@export_range(10, 2000, 1, "suffix:ms") var phase_punch_ms: int = 500
## A hero going down: trauma.
@export_range(0.0, 1.0, 0.01) var downed_shake: float = 0.65
## A boss or guard fight opens with the camera pulled back this far (world units) and gliding in
## over intro_push_ms, with a little trauma.
@export_range(0.0, 5.0, 0.05) var intro_push: float = 1.2
@export_range(10, 3000, 1, "suffix:ms") var intro_push_ms: int = 900
@export_range(0.0, 1.0, 0.01) var intro_shake: float = 0.3
## A struck enemy recoils away from the heroes this far (world units) and comes back: a normal
## hit, and a critical hit, counter or heavy hit. It is out for recoil_out_ms, back over recoil_back_ms.
@export_range(0.0, 2.0, 0.01) var enemy_hit_knockback: float = 0.16
@export_range(0.0, 2.0, 0.01) var enemy_heavy_knockback: float = 0.4
@export_range(10, 1000, 1, "suffix:ms") var recoil_out_ms: int = 70
@export_range(10, 1000, 1, "suffix:ms") var recoil_back_ms: int = 220

@export_group("HUD")
## How far popups float up while fading (pixels at 1080p).
@export_range(0.0, 400.0, 1.0) var popup_rise_px: float = 70.0
## Training ring radius when it appears and when it closes (pixels at 1080p).
@export_range(4.0, 600.0, 1.0) var ring_start_radius_px: float = 150.0
@export_range(0.0, 200.0, 1.0) var ring_end_radius_px: float = 22.0
@export_range(1.0, 30.0, 0.5) var ring_width_px: float = 6.0
## Portrait size on the timeline (pixels at 1080p).
@export_range(8.0, 256.0, 1.0) var portrait_px: float = 56.0
## AP gem size (pixels at 1080p).
@export_range(4.0, 64.0, 1.0) var ap_pip_px: float = 22.0
## Lock icon size (pixels at 1080p).
@export_range(4.0, 128.0, 1.0) var lock_icon_px: float = 56.0
## Lock icon position relative to the defenders' feet on screen (pixels at 1080p): below them,
## clear of the readouts above their heads.
@export var lock_icon_offset_px: Vector2 = Vector2(0.0, 40.0)
## The MISS label sits this share of the sprite height above the head.
@export_range(0.0, 2.0, 0.05) var miss_label_rise_factor: float = 0.3
## Popups start at this scale and settle to 1 (the "punch").
@export_range(1.0, 3.0, 0.05) var popup_punch_scale: float = 1.25
## How long the FIRST STRIKE banner stays up at the start of a fight.
@export_range(0, 5000, 1, "suffix:ms") var first_strike_banner_ms: int = 1300
## How long the TEAM COUNTER banner stays up.
@export_range(0, 5000, 1, "suffix:ms") var team_banner_ms: int = 1100
## After the victory sound in a run, the gold sound waits this long so the two do not pile up.
@export_range(0, 5000, 1, "suffix:ms") var reward_sound_delay_ms: int = 700
## Then the level-up sound (when the party levels) waits this long after the gold sound.
@export_range(0, 5000, 1, "suffix:ms") var level_up_sound_gap_ms: int = 600
## Font size of the LEVEL UP! popup over a hero who levels after a fight.
@export_range(8, 200) var level_up_popup_size: int = 44
## A critical hit shows its damage as a big hit, with CRITICAL! over it in this size.
@export_range(8, 200) var crit_popup_size: int = 34
## Each parry in a row within one enemy attack rings this many semitones higher (card #93).
@export_range(0.0, 12.0, 0.5) var parry_ring_step_semitones: float = 2.0
## The ring stops climbing after this many steps.
@export_range(0, 24, 1) var parry_ring_max_steps: int = 6
## The music dips this much while an enemy attack plays, so the defence sounds stand out (card #98).
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var music_duck_db: float = -6.0
## How long the music takes to dip and to come back.
@export_range(0, 3000, 1, "suffix:ms") var music_duck_ms: int = 300
## An enemy's voice when it is hit: this much quieter than its attack voice ...
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var voice_hurt_volume_db: float = -6.0
## ... and this much higher (1.15 = 15% faster and higher).
@export_range(0.5, 2.0, 0.01) var voice_hurt_pitch: float = 1.15
## The victory or defeat screen fades in over this long.
@export_range(0, 5000, 1, "suffix:ms") var end_fade_ms: int = 400
## Presses are ignored on the victory or defeat screen for this long (so a late defence press
## does not skip it).
@export_range(0, 5000, 1, "suffix:ms") var end_input_guard_ms: int = 800
## Size of the hit icons on the enemy intent sign and the timeline (pixels at 1080p).
@export_range(8.0, 96.0, 1.0) var intent_icon_px: float = 30.0
## The intent sign sits this far below the enemy's feet on screen (pixels at 1080p).
@export_range(0.0, 400.0, 1.0) var intent_sign_gap_px: float = 12.0
## The defence controls (bottom left) show only while an enemy attack plays; they fade in and out
## over this long.
@export_range(0, 2000, 1, "suffix:ms") var controls_fade_ms: int = 140
## The enemy panels (top right, their HP bars) step back to this see-through while an enemy
## attack plays, so they do not cover its hits (card #268) ...
@export_range(0.0, 1.0, 0.05) var enemy_panels_attack_alpha: float = 0.3
## ... and fade there and back over this long (a parry or a counter skips the fade).
@export_range(0, 2000, 1, "suffix:ms") var enemy_panels_fade_ms: int = 200
## A parry brings them back to full at once and keeps them there this long; then they step back
## again while hits are still coming. A parried last hit keeps them full to the counter.
@export_range(0, 5000, 1, "suffix:ms") var enemy_panels_parry_hold_ms: int = 600

@export_group("Feedback")
## HP bars: the part a hit took stays lit in this colour, then drains away (card #38).
@export var hp_trail_color: Color = Color(1.0, 0.92, 0.6)
@export_range(0, 3000, 1, "suffix:ms") var hp_trail_hold_ms: int = 350
@export_range(0, 3000, 1, "suffix:ms") var hp_trail_drain_ms: int = 450
## A heal fills the bar over this long.
@export_range(0, 3000, 1, "suffix:ms") var heal_fill_ms: int = 300
## Sparks when a party strike lands, and when a counter lands.
@export_range(0, 32) var sparks_per_strike: int = 5
@export_range(0, 48) var sparks_per_counter: int = 12
@export var strike_spark_color: Color = Color(1.0, 0.95, 0.8)
## A full-screen flash that fades over screen_flash_ms: its strength (0 to 1) on a counter, the
## team ultimate, a hero going down and an enemy's phase change.
@export_range(0, 2000, 1, "suffix:ms") var screen_flash_ms: int = 180
@export_range(0.0, 1.0, 0.01) var screen_flash_counter: float = 0.18
@export_range(0.0, 1.0, 0.01) var screen_flash_ultimate: float = 0.35
@export_range(0.0, 1.0, 0.01) var screen_flash_downed: float = 0.25
@export_range(0.0, 1.0, 0.01) var screen_flash_phase: float = 0.3
## The "Flashes" setting (card #185): at Reduced a screen flash keeps this percent of its strength
## and a flash on a fighter keeps flash_reduced_fighter_percent; at Off screen flashes are gone
## and a fighter flash keeps only flash_off_fighter_percent (a faint tint, so a hit still reads).
@export_range(0, 100, 1, "suffix:%") var flash_reduced_screen_percent: int = 40
@export_range(0, 100, 1, "suffix:%") var flash_reduced_fighter_percent: int = 50
@export_range(0, 100, 1, "suffix:%") var flash_off_fighter_percent: int = 15
## A beaten enemy dissolves into rot over this long, with a burst of motes in this colour; the
## dissolving edge glows in death_edge_color.
@export_range(0, 5000, 1, "suffix:ms") var death_dissolve_ms: int = 800
@export_range(0, 64) var death_sparks: int = 16
@export var death_spark_color: Color = Color(0.72, 0.88, 0.36)
@export var death_edge_color: Color = Color(0.85, 1.0, 0.45)
## Damage of at least this percent of the target's max HP shows a bigger number.
@export_range(0, 100, 1, "suffix:%") var big_hit_percent: int = 15
@export_range(1.0, 3.0, 0.05) var big_hit_scale: float = 1.4
## When a standing hero is at or under this percent of max HP, the screen edges pulse red.
@export_range(0, 100, 1, "suffix:%") var danger_hp_percent: int = 25
@export_range(0.0, 1.0, 0.01) var danger_vignette_alpha: float = 0.35
@export_range(0.1, 5.0, 0.05, "suffix:Hz") var danger_pulse_hz: float = 1.1
## The team gauge glows in and out this fast while the ultimate is ready.
@export_range(0.1, 5.0, 0.05, "suffix:Hz") var gauge_ready_pulse_hz: float = 1.5
## A hero who runs (DESIGN.md 2.13) dashes this far back (world units) while fading out over
## escape_run_ms.
@export_range(0.0, 20.0, 0.1) var escape_run_distance: float = 5.0
@export_range(0, 3000, 1, "suffix:ms") var escape_run_ms: int = 600
## At the top of each pulse the ready gauge's gold glow reaches this far out of its frame
## (pixels at 1080p).
@export_range(0.0, 64.0, 1.0) var gauge_ready_glow_px: float = 16.0

@export_group("Skills")
## A party member steps this far toward the enemy before a skill's first press (share of the way
## to the strike point), then lunges in on each hit.
@export_range(0.0, 1.0, 0.05) var skill_approach_share: float = 0.55
## How long the lunge into a skill hit and the step back take.
@export_range(10, 1000, 1, "suffix:ms") var skill_lunge_ms: int = 90
## A hero who runs up (DESIGN.md 3.12) stops this far short of the strike point (world units) and
## steps the rest of the way in on each hit.
@export_range(0.0, 6.0, 0.05) var hero_swing_step: float = 1.0
## One cycle of the hero's run loop while running up.
@export_range(50, 2000, 1, "suffix:ms") var hero_run_cycle_ms: int = 360
## The skill press ring (osu-style): radius when it appears and when it reaches the target circle
## (pixels at 1080p). It reaches the target circle at the perfect moment; the GOOD and PERFECT
## bands around the target show the press windows at this scale, so a bigger shrink makes the
## bands wider. Always shown for skill presses.
@export_range(4.0, 800.0, 1.0) var press_ring_start_radius_px: float = 220.0
@export_range(4.0, 400.0, 1.0) var press_ring_end_radius_px: float = 70.0
## Colours of the GOOD band, the PERFECT band and the faint target circle.
@export var press_good_band_color: Color = Color(1.0, 1.0, 1.0, 0.22)
@export var press_perfect_band_color: Color = Color(1.0, 0.82, 0.3, 0.75)
@export var press_target_color: Color = Color(1.0, 1.0, 1.0, 0.08)
## A skill with several presses shows each press as its own numbered ring (a "note") at its own
## spot, in a row from left to right in press order, centred where the striker stands (osu-style).
## Note centres are this far apart (pixels at 1080p).
@export_range(20.0, 600.0, 1.0) var press_note_spacing_px: float = 150.0
## Note rings are this share of a single press ring's size, so a row stays compact.
@export_range(0.2, 1.0, 0.05) var press_note_scale: float = 0.65

@export_group("Calibration")
## Time between calibration beats.
@export_range(200, 3000, 1, "suffix:ms") var calibration_interval_ms: int = 750
@export_range(2, 64) var calibration_beats: int = 12
## The result is the median of this many of the last presses.
@export_range(1, 64) var calibration_sample_count: int = 8
## Fewest presses needed before a calibration can be saved.
@export_range(1, 64) var calibration_min_presses: int = 4
## Pause before the first beat.
@export_range(0, 5000, 1, "suffix:ms") var calibration_lead_ms: int = 1500
## How long the circle stays lit on each beat.
@export_range(10, 1000, 1, "suffix:ms") var calibration_flash_ms: int = 120
## Refuse to save when the middle half of the last presses spreads wider than this: it means
## pressing by reaction instead of with the beat.
@export_range(5, 500, 1, "suffix:ms") var calibration_max_spread_ms: int = 60

@export_group("Animation")
## Breathing loops (real time; each fighter a little out of step with the others): one idle,
## combat-stance (ready) and downed cycle of a hero, and one idle cycle of an enemy (times the
## enemy's idle_cycle_percent). A sheet without these clips shows its still pose (DESIGN.md 5.5).
@export_range(100, 10000, 1, "suffix:ms") var idle_cycle_ms: int = 1600
@export_range(100, 10000, 1, "suffix:ms") var ready_cycle_ms: int = 900
@export_range(100, 10000, 1, "suffix:ms") var down_cycle_ms: int = 2400
@export_range(100, 10000, 1, "suffix:ms") var enemy_idle_cycle_ms: int = 1800
## Enemy wind-up (attack time, so a hit-stop freezes it): the coil plays over this long from the
## wind-up's start (never longer than the wind-up), then the held wind-up shivers, one shiver
## cycle every enemy_windup_shiver_ms.
@export_range(10, 2000, 1, "suffix:ms") var enemy_windup_coil_ms: int = 240
@export_range(10, 2000, 1, "suffix:ms") var enemy_windup_shiver_ms: int = 160
## A heavy hit (at least big_hit_percent of max HP), a counter or a team counter staggers instead
## of flinching: the stagger plays over this long and knocks a hero back this far (world units).
@export_range(0, 3000, 1, "suffix:ms") var stagger_pose_ms: int = 480
@export_range(0.0, 3.0, 0.05) var stagger_knockback: float = 0.6
## Skills (skill time): the wind-up before each press plays over up to this long (times the
## ability's windup_percent). The next press's wind-up starts no sooner than skill_strike_min_ms
## after the previous strike lands, and a strike plays over skill_strike_pose_ms (cut short by
## the next wind-up).
@export_range(0, 2000, 1, "suffix:ms") var skill_windup_ms: int = 220
@export_range(0, 2000, 1, "suffix:ms") var skill_strike_min_ms: int = 120
@export_range(0, 2000, 1, "suffix:ms") var skill_strike_pose_ms: int = 270
## A follow-up ally hops in to their spot (and back home) over this long, this high (world units).
@export_range(10, 2000, 1, "suffix:ms") var follow_up_hop_ms: int = 220
@export_range(0.0, 5.0, 0.05) var follow_up_hop_height: float = 0.8
## A hero who goes down falls over fall_ms; a revived hero gets up over revive_pose_ms.
@export_range(0, 3000, 1, "suffix:ms") var fall_ms: int = 360
@export_range(0, 3000, 1, "suffix:ms") var revive_pose_ms: int = 420
## An enemy with a death clip plays it over death_pose_ms and holds its last cell. A rotting one
## (EnemyData.death_style ROT) starts dissolving death_dissolve_delay_ms into it, over
## death_dissolve_ms. A bursting one (BURST) bursts into death_burst_sparks sparks of
## death_burst_color when the clip ends and dissolves over death_burst_dissolve_ms.
@export_range(0, 3000, 1, "suffix:ms") var death_pose_ms: int = 400
@export_range(0, 3000, 1, "suffix:ms") var death_dissolve_delay_ms: int = 200
@export_range(0, 96) var death_burst_sparks: int = 28
@export_range(0, 3000, 1, "suffix:ms") var death_burst_dissolve_ms: int = 160
@export var death_burst_color: Color = Color(0.9, 0.84, 0.52)
## Victory: victory_pose_delay_ms after the end (plus victory_stagger_ms per party slot) each
## standing hero plays the victory clip over victory_pose_ms, then loops the victory hold, one
## cycle every victory_cycle_ms.
@export_range(0, 5000, 1, "suffix:ms") var victory_pose_delay_ms: int = 300
@export_range(0, 2000, 1, "suffix:ms") var victory_stagger_ms: int = 120
@export_range(0, 5000, 1, "suffix:ms") var victory_pose_ms: int = 600
@export_range(100, 10000, 1, "suffix:ms") var victory_cycle_ms: int = 1200
## Fight start: draw_delay_ms after the fighters appear (plus draw_stagger_ms per party slot)
## each hero draws their weapon over draw_pose_ms.
@export_range(0, 5000, 1, "suffix:ms") var draw_delay_ms: int = 300
@export_range(0, 2000, 1, "suffix:ms") var draw_stagger_ms: int = 90
@export_range(0, 3000, 1, "suffix:ms") var draw_pose_ms: int = 450
## A hero who runs away loops their run, one cycle every escape_run_cycle_ms.
@export_range(50, 3000, 1, "suffix:ms") var escape_run_cycle_ms: int = 400
## A boss entering phase two plays its rage clip over this long.
@export_range(0, 5000, 1, "suffix:ms") var rage_pose_ms: int = 700

@export_group("Backpack")
## A hero using a fight item: the item's name shows and the hero holds still this long before
## its effect plays.
@export_range(0, 3000, 1, "suffix:ms") var item_use_ms: int = 600
## Alder's open pack behind the pockets (DESIGN.md 8.1, 8.19). Drawn by
## tools/art_kit/assets/items.py (ui/backpack_5.png, the one pack picture since card #332); these
## numbers must match it.
@export var backpack_art_path: String = "res://assets/sprites/ui/backpack_5.png"
## Screen pixels per art pixel.
@export_range(1, 8) var backpack_art_scale: int = 4
## The lining's top-left in the art and its size (art pixels): the pockets fill it.
@export var backpack_grid_origin: Vector2i = Vector2i(14, 23)
@export var backpack_lining_art_px: Vector2i = Vector2i(95, 119)
## Pockets per row (the rows follow from tuning.backpack_pockets: 4 pockets make two rows of two,
## card #332) and the gap between pockets (art pixels).
@export_range(1, 8) var backpack_pocket_columns: int = 2
@export_range(0, 16) var backpack_pocket_gap_art_px: int = 3

@export_group("Charged Dooms")
## An enemy gathering a Doom (card #195, DESIGN.md 2.3): its body holds the wind-up crouch
## (doom_squash_percent) and glows doom_glow_color, pulsing between doom_glow_min and doom_glow_max
## once per doom_pulse_ms; with one turn left the pulse runs at doom_pulse_last_percent of that
## time (quicker). Banner and HUD text use doom_text_color; the break bar break_bar_color.
@export var doom_glow_color: Color = Color(0.9, 0.12, 0.3)
@export_range(0.0, 1.0, 0.01) var doom_glow_min: float = 0.3
@export_range(0.0, 1.0, 0.01) var doom_glow_max: float = 0.9
@export_range(100, 5000, 1, "suffix:ms") var doom_pulse_ms: int = 1200
@export_range(10, 100, 1, "suffix:%") var doom_pulse_last_percent: int = 50
@export_range(0, 50, 1, "suffix:%") var doom_squash_percent: int = 10
@export var doom_text_color: Color = Color(1.0, 0.3, 0.25)
@export var break_bar_color: Color = Color(1.0, 0.82, 0.3)
## The enemy spends a turn gathering: its banner (name and countdown) for doom_gather_banner_ms,
## a rumble of trauma and a screen flash, and the turn waits doom_gather_beat_ms.
@export_range(0, 5000, 1, "suffix:ms") var doom_gather_banner_ms: int = 1500
@export_range(0.0, 1.0, 0.01) var doom_gather_shake: float = 0.35
@export_range(0.0, 1.0, 0.01) var doom_gather_flash: float = 0.12
@export_range(0, 3000, 1, "suffix:ms") var doom_gather_beat_ms: int = 450
## Phase 19 (cards #252, #259). A Dazed hero's lost turn holds this long (the DAZED popup); a
## monster's heal or shield on a fellow monster: its wind-up lasts support_cast_ms, then half that
## again while the helped one glows.
@export_range(0, 3000, 1, "suffix:ms") var turn_lost_beat_ms: int = 650
@export_range(100, 3000, 1, "suffix:ms") var support_cast_ms: int = 700
@export var doom_gather_sfx: String = "alert"
## The Doom unleashes (before its attack banner): trauma, punch-in, flash, a beat.
@export_range(0, 5000, 1, "suffix:ms") var doom_unleash_banner_ms: int = 1000
@export_range(0.0, 1.0, 0.01) var doom_unleash_shake: float = 0.7
@export_range(0.0, 5.0, 0.05) var doom_unleash_punch: float = 0.8
@export_range(0.0, 1.0, 0.01) var doom_unleash_flash: float = 0.3
@export_range(0, 3000, 1, "suffix:ms") var doom_unleash_beat_ms: int = 600
@export var doom_unleash_sfx: String = "boss_rage"
## BROKEN! is the large tier (card #179): a held freeze, trauma, a punch-in and a flash in
## broken_flash_color, the banner, and the sound. The staggered enemy then holds its stagger pose,
## glowing stagger_glow_color at stagger_glow strength, until it has lost its turn.
@export_range(0, 5000, 1, "suffix:ms") var broken_banner_ms: int = 1600
@export_range(0, 400, 5, "suffix:ms") var broken_hitstop_ms: int = 170
@export_range(0.0, 1.0, 0.01) var broken_shake: float = 1.0
@export_range(0.0, 5.0, 0.05) var broken_punch: float = 1.4
@export_range(0.0, 1.0, 0.01) var broken_flash: float = 0.45
@export var broken_flash_color: Color = Color(1.0, 0.95, 0.7)
@export var broken_sfx: String = "team_counter"
@export var stagger_sfx: String = "guard_block"
@export var stagger_glow_color: Color = Color(0.55, 0.8, 1.0)
@export_range(0.0, 1.0, 0.01) var stagger_glow: float = 0.5
@export var stagger_text_color: Color = Color(0.6, 0.85, 1.0)

@export_group("Turn spotlight")
## On a hero's turn (card #154) the acting hero steps turn_step (world units: toward the enemies
## and the camera) onto a gold ring, and the other heroes step turn_step_away back and out to their
## own side and dim to bystander_tint, over turn_spot_ms; everyone steps home when the choice is made.
@export var turn_step: Vector3 = Vector3(0.35, 0.0, 0.3)
@export_range(0.0, 3.0, 0.05) var turn_step_away: float = 1.1
@export_range(0, 1000, 10, "suffix:ms") var turn_spot_ms: int = 200
@export var turn_ring_color: Color = Color(1.0, 0.82, 0.3)
@export_range(0.0, 1.0, 0.05) var turn_ring_alpha: float = 0.55


## Multiplier for a full-screen flash under flash mode `mode` (PlayerSettings.FLASH_*).
func screen_flash_scale(mode: int) -> float:
	match mode:
		PlayerSettings.FLASH_REDUCED:
			return float(flash_reduced_screen_percent) / 100.0
		PlayerSettings.FLASH_OFF:
			return 0.0
	return 1.0


## Multiplier for a flash on a fighter (white hit flashes, the telegraph flash) under `mode`.
func fighter_flash_scale(mode: int) -> float:
	match mode:
		PlayerSettings.FLASH_REDUCED:
			return float(flash_reduced_fighter_percent) / 100.0
		PlayerSettings.FLASH_OFF:
			return float(flash_off_fighter_percent) / 100.0
	return 1.0


## The colour that says which defence a hit kind needs (DESIGN.md 3.8): `strike_color` for a
## normal hit (the telegraph or the marker colour, by use), the ground purple, the rend bone or
## the sweep green.
func kind_color(kind: int, strike_color: Color) -> Color:
	match kind:
		AttackHitData.Kind.GROUND:
			return ground_hit_color
		AttackHitData.Kind.REND:
			return rend_hit_color
		AttackHitData.Kind.SWEEP:
			return sweep_hit_color
	return strike_color


@export_group("Arena mood")
## How long the room takes to shift to its phase-two look when a boss or guard rages (StageLook
## phase_*; DESIGN.md 7.3).
@export_range(100, 5000, 50, "suffix:ms") var phase_look_ms: int = 1100
## With the Flashes setting on Reduced or Off the shift takes this share of that time (slower,
## so the change of light is gentler).
@export_range(100, 400, 10, "suffix:%") var phase_look_calm_percent: int = 200
## The place's drifting particles play in its fights at this share of each one's amount (a fight
## is a busy picture; 0 = none).
@export_range(0, 100, 5, "suffix:%") var fight_air_percent: int = 50
## The fight's air box is this deep as a share of the place's, and sits this far from the arena's
## middle (world units; negative z is away from the camera), so it hangs behind and around the
## fighters and never between the camera and the hit markers.
@export_range(10, 100, 5, "suffix:%") var fight_air_depth_percent: int = 60
@export var fight_air_offset: Vector3 = Vector3(0.0, 0.0, -2.0)

@export_group("Party screen")
## The Y screen's toasts (DESIGN.md 8.18): an icon and a word or two under the tab bar, shown for
## this long, then faded out over party_toast_fade_s.
@export_range(0.5, 10.0, 0.1, "suffix:s") var party_toast_s: float = 2.2
@export_range(0.0, 2.0, 0.05, "suffix:s") var party_toast_fade_s: float = 0.35

@export_group("End screen")
## A won run fight's end screen as icon rows (phase 22, cards #273 and #274): the gold icon, how
## big the reward icons and the heroes' portraits are drawn, and how dim a downed hero's portrait is.
@export var gold_icon_path: String = "res://assets/sprites/ui/gold_coin.png"
@export_range(16, 200, 1) var end_icon_px: int = 48
@export_range(16, 300, 1) var end_portrait_px: int = 88
@export var end_down_tint: Color = Color(0.45, 0.45, 0.5, 0.8)

@export_group("Fight HUD icons")
## Phase 22 (fewer words, more icons): every status on an enemy or a hero panel is its icon
## (HudStyle.mark_icon) with the turns left, drawn this big.
@export_range(8.0, 96.0, 1.0) var status_icon_px: float = 24.0
## A hit that leaves a mark shows that mark's icon on its corner in a hit row (the intent sign, the
## attack banner), this share of the hit icon's size.
@export_range(0.2, 1.0, 0.01) var hit_mark_icon_share: float = 0.6
## The hit icons on the defence buttons (which hits each button answers), this big.
@export_range(8.0, 96.0, 1.0) var defend_hit_icon_px: float = 26.0
## A skill or item that cannot be used now: a lock this big on its row; its AP cost turns
## locked_cost_color when the hero is short of AP.
@export_range(8.0, 96.0, 1.0) var menu_lock_px: float = 22.0
@export var locked_cost_color: Color = Color(1.0, 0.36, 0.3)

@export_group("Defence streak")
## The streak chip over the team gauge (card #300): a shield and "STREAK n", shown from this many
## perfect defences in a row. Each new one pops it to streak_pop_scale; every tuning
## defence_streak_step in a row (the gauge fills) pops it to streak_milestone_scale, plays
## streak_milestone_sfx and swells the music streak_music_lift_db louder per step reached (at most
## streak_music_lift_max_db) until a hit ends the streak. A broken streak turns red and fades.
@export_range(1, 50) var streak_show_from: int = 3
@export_range(1.0, 3.0, 0.05) var streak_pop_scale: float = 1.2
@export_range(1.0, 3.0, 0.05) var streak_milestone_scale: float = 1.6
@export_range(50, 2000, 10, "suffix:ms") var streak_pop_ms: int = 260
@export_range(100, 3000, 10, "suffix:ms") var streak_lost_ms: int = 900
@export var streak_milestone_sfx: String = "streak_swell"
## The best streak on a won run fight's end screen: this icon and "Streak n" (it filled the gauge).
@export var streak_chip_icon_path: String = "res://assets/sprites/ui/chip_gauge.png"
@export_range(0.0, 12.0, 0.1, "suffix:dB") var streak_music_lift_db: float = 1.5
@export_range(0.0, 12.0, 0.1, "suffix:dB") var streak_music_lift_max_db: float = 4.5
@export_range(0, 5000, 10, "suffix:ms") var streak_music_fade_ms: int = 800

@export_group("Press ladder")
## Skill presses climb (card #307): each perfect press in a row in one skill plays the press sound
## press_ladder_step_semitones higher (up to press_ladder_max_steps); a good press or a miss starts
## it over. A skill (or the Team Ultimate) of at least press_finish_min_presses presses, every one
## perfect, ends with a finish on its target: a burst of press_finish_sparks in press_finish_color,
## a punch-in, a little shake, a flash on the target, press_finish_sfx (empty: none) and the
## "press_finish" pad buzz.
@export_range(0.0, 12.0, 0.5) var press_ladder_step_semitones: float = 1.5
@export_range(0, 24, 1) var press_ladder_max_steps: int = 5
@export_range(1, 20, 1) var press_finish_min_presses: int = 2
@export_range(0, 200, 1) var press_finish_sparks: int = 30
@export var press_finish_color: Color = Color(1.0, 0.82, 0.3)
@export_range(0.0, 5.0, 0.05) var press_finish_punch: float = 0.55
@export_range(0.0, 1.0, 0.01) var press_finish_shake: float = 0.35
@export var press_finish_sfx: String = ""

@export_group("Killing blow")
## The blow that ends a fight (card #308): the last enemy falling (or the boss), or the last hero
## down. The music cuts to silence over kill_silence_fade_ms and stays silent until the end song
## (so only the hit and the crumble are heard), and the screen holds a dark impact frame for
## impact_frame_ms (impact_frame_color; the Flashes setting scales it like a screen flash).
@export var kill_silence: bool = true
@export_range(0, 2000, 10, "suffix:ms") var kill_silence_fade_ms: int = 60
@export_range(0, 500, 5, "suffix:ms") var impact_frame_ms: int = 70
@export var impact_frame_color: Color = Color(0.0, 0.0, 0.0, 0.55)

@export_group("Screen transitions")
## Into a fight: the screen swirls and fades to black over transition_out_ms, then the fight fades
## in over transition_in_ms. Between other screens: fade to black, then fade in, each over
## transition_in_ms (ScreenTransition).
@export_range(50, 5000, 1, "suffix:ms") var transition_out_ms: int = 850
@export_range(50, 5000, 1, "suffix:ms") var transition_in_ms: int = 450
## How far the screen twists (radians at the middle) by the end of the swirl.
@export_range(0.0, 30.0, 0.1) var swirl_turns: float = 7.0
## White flash at the start of the swirl (0 = none).
@export_range(0.0, 1.0, 0.05) var transition_flash: float = 0.6

@export_group("First Strike press")
## The First Strike ring on a Fight stop's name card (DESIGN.md 8.22, card #320), drawn like a skill
## press ring (the Skills group's radii, bands and colours) at this share of its size, with the
## skill press button and "First Strike" under it (first_strike_chip_size) and the press's word
## over it (first_strike_word_size: PERFECT, GOOD, EARLY, LATE, MISS). The card holds the result
## this long before the fight (and never before a late press could still say LATE). An online friend watches the host's ring this dim (they cannot press it).
@export_range(0.2, 2.0, 0.05) var first_strike_ring_scale: float = 0.8
@export_range(12, 96, 1) var first_strike_chip_size: int = 30
@export_range(12, 120, 1) var first_strike_word_size: int = 44
@export_range(0, 3000, 10, "suffix:ms") var first_strike_result_ms: int = 800
@export_range(0.05, 1.0, 0.05) var first_strike_watch_alpha: float = 0.45
