class_name ExploreVisuals
extends Resource
## Presentation-only data for walking around a zone (DESIGN.md 7.4): the follow camera and its
## depth of field, walking animation, the notice "!", the field strike, and the transition into a
## fight and back. Rules (speeds, reach, radii) live in tuning.tres, the zone's look in its
## StageLook. Edit data/presentation/explore_visuals.tres.

@export_group("Camera")
## The camera sits at this offset from the leader's feet and looks at the leader's feet plus
## look_offset, with this vertical field of view (a long, narrow lens gives the HD-2D diorama).
@export var camera_offset: Vector3 = Vector3(0.0, 7.0, 11.0)
@export var look_offset: Vector3 = Vector3(0.0, 1.0, -1.0)
@export_range(10.0, 100.0, 0.5) var camera_fov: float = 30.0
## It follows the leader with this time constant (it catches up after about four of them).
@export_range(10, 3000, 1, "suffix:ms") var camera_follow_ms: int = 220

@export_group("Depth of field")
## Blur further than far distance and nearer than near distance (world units from the camera):
## the tilt-shift miniature look.
@export var dof_far_enabled: bool = true
@export_range(0.1, 200.0, 0.1) var dof_far_distance: float = 16.0
@export_range(0.0, 100.0, 0.1) var dof_far_transition: float = 8.0
@export var dof_near_enabled: bool = true
@export_range(0.0, 50.0, 0.1) var dof_near_distance: float = 9.0
@export_range(0.0, 50.0, 0.1) var dof_near_transition: float = 3.0
@export_range(0.0, 1.0, 0.01) var dof_amount: float = 0.12

@export_group("Walking")
## Walking bob: the sprite hops this high (world units), this many steps a second.
@export_range(0.0, 1.0, 0.01) var walk_bob_height: float = 0.07
@export_range(0.1, 10.0, 0.1) var walk_bob_hz: float = 3.4
## Roaming enemies bob more slowly while they wander.
@export_range(0.1, 10.0, 0.1) var roam_bob_hz: float = 1.6
## World units the leader walks per step (about 22 art pixels): the walk cycle and the footsteps
## follow the distance actually moved, so feet stay planted against a wall or on a light tilt.
## 0 = the old time-based steps (walk_bob_hz).
@export_range(0.0, 5.0, 0.05) var walk_stride: float = 1.0
## The same for roaming enemies.
@export_range(0.0, 5.0, 0.05) var roam_stride: float = 0.9
## When the stick points almost diagonally (its two axes within this of each other), the leader
## keeps facing the way they already face, so the view does not flicker between side and front.
@export_range(0.0, 1.0, 0.01) var walk_turn_margin: float = 0.2

## Online, the other players see the walkers glide to the host's positions with this time
## constant (smooths the position updates; DESIGN.md 9.2).
@export_range(10, 1000, 1, "suffix:ms") var net_follow_ms: int = 90

@export_group("Notice and strike")
## The "!" above a roaming enemy that has noticed the leader.
@export_range(8, 200, 1) var notice_size: int = 52
@export var notice_color: Color = Color(1.0, 0.3, 0.2)
## Name roaming enemies over their heads when the leader is near (card #127: off, names show
## once the fight starts). The guard keeps its gold GUARD tag either way, without its name.
@export var show_roamer_names: bool = false
## The field strike's slash sits this far in front of the leader (world units).
@export_range(0.0, 5.0, 0.05) var strike_slash_distance: float = 0.9
## Size of the "FIRST STRIKE!" text when a strike starts a fight.
@export_range(8, 200, 1) var first_strike_size: int = 64

@export_group("Transition")
## Into a fight: the screen swirls and fades to black over transition_out_ms, then the fight fades
## in over transition_in_ms. Back to the zone: fade to black, then fade in.
@export_range(50, 5000, 1, "suffix:ms") var transition_out_ms: int = 850
@export_range(50, 5000, 1, "suffix:ms") var transition_in_ms: int = 450
## How far the screen twists (radians at the middle) by the end of the swirl.
@export_range(0.0, 30.0, 0.1) var swirl_turns: float = 7.0
## White flash at the start of the transition (0 = none).
@export_range(0.0, 1.0, 0.05) var transition_flash: float = 0.6
## The zone's name is shown when you arrive, for this long.
@export_range(0, 10000, 1, "suffix:ms") var zone_title_ms: int = 2200

@export_group("Item pickup")
## When the zone's guard falls, the leader picks up the loot: the pickup clip starts this long
## after the fight hands back and plays over pickup_ms.
@export_range(0, 5000, 1, "suffix:ms") var pickup_delay_ms: int = 600
@export_range(0, 5000, 1, "suffix:ms") var pickup_ms: int = 700
## A glinting spot (DESIGN.md 8.1): a glowing sparkle standing this high over the ground, pulsing
## in size once per glint_pulse_ms by up to glint_pulse_share.
@export_file_path("*.png") var glint_path: String = "res://assets/sprites/fx/glint.png"
@export_range(0.005, 1.0, 0.001) var glint_pixel_size: float = 0.045
@export_range(0.0, 5.0, 0.01) var glint_height: float = 0.25
@export_range(0.0, 8.0, 0.05) var glint_glow: float = 2.5
@export var glint_color: Color = Color(1.0, 0.85, 0.4)
@export_range(100, 10000, 1, "suffix:ms") var glint_pulse_ms: int = 1400
@export_range(0.0, 1.0, 0.01) var glint_pulse_share: float = 0.3
## A zone's locked chest (DESIGN.md 8.1), closed and opened, standing at its feet.
@export_file_path("*.png") var chest_closed_path: String = "res://assets/sprites/env/chest_closed.png"
@export_file_path("*.png") var chest_open_path: String = "res://assets/sprites/env/chest_open.png"
@export_range(0.005, 1.0, 0.001) var chest_pixel_size: float = 0.05
## The chests as 3D pieces (DESIGN.md 5.6), shown instead of the sprites above (null: the sprites).
@export var chest_piece: WorldPieceData
@export var chest_open_piece: WorldPieceData

@export_group("Long zones")
## A rot seal (DESIGN.md 8.5): a glowing standing stone, bobbing slowly, and the light beside it.
@export_file_path("*.png") var seal_path: String = "res://assets/sprites/env/seal_stone.png"
@export_range(0.005, 1.0, 0.001) var seal_pixel_size: float = 0.05
@export_range(0.0, 8.0, 0.05) var seal_glow: float = 1.6
@export var seal_color: Color = Color(0.55, 1.0, 0.45)
## The seal as a 3D piece (DESIGN.md 5.6), shown instead of the sprite (null: the sprite).
@export var seal_piece: WorldPieceData
@export_range(0.0, 16.0, 0.05) var seal_light_energy: float = 1.6
@export_range(0.1, 50.0, 0.1) var seal_light_reach: float = 4.0
## The gate sinks into the ground over this long when the last seal needed is taken.
@export_range(0, 10000, 1, "suffix:ms") var gate_open_ms: int = 1400
## A shrine or wanderer's small light (its glow colour), this strong and far.
@export_range(0.0, 16.0, 0.05) var offer_light_energy: float = 1.4
@export_range(0.1, 50.0, 0.1) var offer_light_reach: float = 4.5
## A used shrine dims to this share of its glow; a wanderer that dealt walks off (fades) over
## offer_fade_ms.
@export_range(0.0, 1.0, 0.01) var offer_used_glow_share: float = 0.25
@export_range(0, 10000, 1, "suffix:ms") var offer_fade_ms: int = 900
## A champion's tag (shown near it, like a name) and its colour.
@export var champion_color: Color = Color(0.85, 0.45, 1.0)
## Champion tags show this many notice radii away or closer.
@export_range(0.5, 10.0, 0.1) var champion_tag_range: float = 2.0
## The zone's exit (DESIGN.md 8.5): a signpost at the far end. Dark while the guard stands; once it
## is beaten a light comes on beside it and an "EXIT" tag marks it on screen, in exit_color.
@export_file_path("*.png") var exit_path: String = "res://assets/sprites/env/signpost.png"
@export_range(0.005, 1.0, 0.001) var exit_pixel_size: float = 0.05
## The exit as a 3D piece (DESIGN.md 5.6), shown instead of the sprite (null: the sprite).
@export var exit_piece: WorldPieceData
@export_range(0.1, 4.0, 0.01) var exit_scale: float = 1.2
## The signpost blocks walking this far around its foot (0: walk through it).
@export_range(0.0, 10.0, 0.05) var exit_solid_radius: float = 0.3
## The signpost's arms point toward +x (the far end) at this turn.
@export_range(-180.0, 180.0, 0.5) var exit_rotation_y_degrees: float = 0.0
@export var exit_color: Color = Color(1.0, 0.82, 0.4)
@export_range(0.0, 16.0, 0.05) var exit_light_energy: float = 3.0
@export_range(0.1, 50.0, 0.1) var exit_light_reach: float = 6.0
## The light stands this high over the exit spot (world units).
@export_range(0.0, 10.0, 0.05) var exit_light_height: float = 1.6

@export_group("Life")
## Critters (DESIGN.md 8.12): they get away when the leader comes this close, play their move
## frames this fast and are gone after critter_away_s.
@export_range(0.5, 20.0, 0.1) var critter_flee_radius: float = 3.2
@export_range(0.02, 1.0, 0.01) var critter_frame_s: float = 0.12
@export_range(0.2, 10.0, 0.1) var critter_away_s: float = 2.4
## A crow flies off this fast (sideways, world units a second) while climbing this fast.
@export_range(0.1, 20.0, 0.1) var crow_speed: float = 4.0
@export_range(0.0, 20.0, 0.1) var crow_climb: float = 2.6
## A frog hops away: its speed, one hop's length in seconds and how high it hops.
@export_range(0.1, 20.0, 0.1) var frog_speed: float = 2.2
@export_range(0.05, 2.0, 0.01) var frog_hop_s: float = 0.35
@export_range(0.0, 3.0, 0.01) var frog_hop_height: float = 0.35
## A rat scurries off this fast.
@export_range(0.1, 20.0, 0.1) var rat_speed: float = 4.5
