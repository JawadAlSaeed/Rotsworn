class_name AbilityData
extends Resource
## An action a party member can take on their turn: the basic attack, a class skill or the team
## ultimate (DESIGN.md 2.2 and 2.10).
##
## Timed presses: every time in press_times_ms is one hit with one press prompt for the user.
## Each press is PERFECT (the hit gets its press_damage_percent bonus), GOOD (normal damage) or a
## MISS (tuning skill_miss_damage_percent of normal damage). Effects other than damage apply when
## the ability lands (after its last press); their press_* bonus needs every press to be perfect.
## With no press times the ability resolves at once with its base effect and no follow-ups.

enum Target {
	SINGLE_ENEMY,
	ALL_ENEMIES,
	## The user only (no target step).
	SELF,
	## Any standing party member, the user included.
	ALLY,
	## A standing party member other than the user.
	OTHER_ALLY,
	## A party member who is down (revive).
	DOWNED_ALLY,
	## Every standing party member, the user included (no target step; DESIGN.md 8.4).
	ALL_ALLIES,
}

## Unique id used in commands and save data. Never change it once content uses it.
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var target: Target = Target.SINGLE_ENEMY
## AP spent to use it.
@export_range(0, 99) var ap_cost: int = 0
## Sound cue played on each hit (name from data/audio/sfx_library.tres).
@export var impact_sfx: String = "strike"

@export_group("Timed presses")
## When each press (and hit) lands, in milliseconds after the ability starts. Times must increase.
## Leave a gap of at least the ring's lead time (see ring_lead_percent) before the first one so
## the press ring can be read.
@export var press_times_ms: Array[int] = []
## How long this skill's press rings take to close, in percent of tuning ring_lead_ms: 100 is the
## normal speed, lower is a faster ring (harder), higher a slower one.
@export_range(20, 300, 1, "suffix:%") var ring_lead_percent: int = 100
## This skill's PERFECT window, in percent of tuning skill_perfect_window_ms (never wider than the
## GOOD window). 100 is the normal size; Run uses a little more.
@export_range(50, 300, 1, "suffix:%") var perfect_window_percent: int = 100
## Colour of this skill's press rings. A ring always turns gold while it is inside the PERFECT
## band, so avoid gold here.
@export var ring_color: Color = Color(0.95, 0.94, 0.9)
## After a good or perfect press, the other standing party members each get a follow-up press (damaging
## abilities that target enemies only).
@export var follow_ups: bool = false

@export_group("Damage")
## Damage of each hit, in percent of the user's power (0 = no damage).
@export_range(0, 2000, 5, "suffix:%") var damage_percent: int = 100
## Added to a hit's percent when its press is perfect.
@export_range(0, 2000, 5, "suffix:%") var press_damage_percent: int = 0
## Added to every hit's percent for each perfect defence (parry or jump) the user made since
## their last turn.
@export_range(0, 500, 5, "suffix:%") var per_perfect_defense_percent: int = 0
## Removes Exposed from the target for extra damage on every hit.
@export var consumes_exposed: bool = true
## Extra damage against an Exposed target, in percent. 0 = tuning exposed_bonus_percent.
@export_range(0, 1000, 5, "suffix:%") var exposed_bonus_percent: int = 0

@export_group("Effects when it lands")
## AP the user gains.
@export_range(0, 99) var ap_gain: int = 0
@export_range(0, 99) var press_ap_gain: int = 0
## AP given to the target ally.
@export_range(0, 99) var give_ap: int = 0
@export_range(0, 99) var press_give_ap: int = 0
## Healing, in percent of the target ally's max HP.
@export_range(0, 100, 1, "suffix:%") var heal_percent: int = 0
@export_range(0, 100, 1, "suffix:%") var press_heal_percent: int = 0
## Revives a downed ally with this percent of their max HP.
@export_range(0, 100, 1, "suffix:%") var revive_percent: int = 0
@export_range(0, 100, 1, "suffix:%") var press_revive_percent: int = 0
## Pushes the target enemy's next turn later by this percent of its turn cost.
@export_range(0, 500, 1, "suffix:%") var turn_delay_percent: int = 0
@export_range(0, 500, 1, "suffix:%") var press_turn_delay_percent: int = 0
## Brings the target ally's next turn closer by this percent of the wait left.
@export_range(0, 100, 1, "suffix:%") var turn_hasten_percent: int = 0
@export_range(0, 100, 1, "suffix:%") var press_turn_hasten_percent: int = 0
## Cleanse (card #194): removes this many hero debuffs (rotting, then blighted, then weakened) from
## each ally it heals, before the heal lands; the press_ amount is added on an all-perfect press.
## 3 or more clears all of them.
@export_range(0, 3) var cleanse_count: int = 0
@export_range(0, 3) var press_cleanse_count: int = 0
## Status put on the target: "" (none), "exposed", "guarded", "taunted", "slowed", "riposte",
## "bleeding", "regen", "marked", "empowered"
## (see scripts/combat/core/status.gd).
@export var status: String = ""
## How many of the holder's turns the status lasts ("slowed", "bleeding", "regen"), or how many
## skills it is good for ("marked").
@export_range(0, 20) var status_turns: int = 0
@export_range(0, 20) var press_status_turns: int = 0
## A perfect press also puts the status on the user (Guard).
@export var press_status_on_self: bool = false
## The status needs every press to be perfect (Twin Fangs: Exposed only on a perfect pair).
@export var status_needs_perfect: bool = false
## A status the user always gets, and one more on an all-perfect press (Unbreakable: guarded, and
## riposte when perfect; Shadowstep: empowered). Same ids as `status`.
@export var self_status: String = ""
@export_range(0, 20) var self_status_turns: int = 0
@export var press_self_status: String = ""
## Adds this much to the team gauge when it lands (Inspire).
@export_range(0, 1000) var gauge_gain: int = 0

@export_group("Team")
## The team ultimate: needs a full team gauge and empties it, every standing party member strikes
## (one press each per hit), and every downed ally is revived (tuning team_ultimate_revive_percent).
@export var team_ultimate: bool = false


## How long before each press its ring appears, in milliseconds.
func ring_lead_ms(tuning: Tuning) -> int:
	return CombatMath.percent(tuning.ring_lead_ms, ring_lead_percent)


## True if the ability targets one or all enemies.
func targets_enemies() -> bool:
	return target == Target.SINGLE_ENEMY or target == Target.ALL_ENEMIES


## True if the ability targets party members (or only its user).
func targets_party() -> bool:
	return not targets_enemies()

@export_group("Run")
## Run (DESIGN.md 2.13): if every press is PERFECT the party leaves the fight (result
## "escaped"); anything else and the turn is simply lost.
@export var escape: bool = false

@export_group("Animation")
## Clips the user plays for each press (presentation only, DESIGN.md 5.5): press k uses entry
## k % size. The wind-up plays before the press's hit, the strike when it lands. A missing clip
## falls back (strike_alt to strike, cast_windup to strike_windup, and so on); an empty list holds
## the combat stance.
@export var windup_clips: PackedStringArray = PackedStringArray(["strike_windup"])
@export var strike_clips: PackedStringArray = PackedStringArray(["strike"])
## Length of this ability's wind-ups, in percent of combat_visuals skill_windup_ms.
@export_range(10, 500, 1, "suffix:%") var windup_percent: int = 100
## A spell (card #81): the user stays where they stand and this flies to the target for each
## press (presentation only). It leaves the staff at the moment of the press, or at the end of the
## press window if none came, and the strike lands when it arrives (card #166, DESIGN.md 2.10).
## Null: the user walks up and strikes.
@export var projectile: ProjectileData
## How long it flies from the staff to the target, in milliseconds.
@export_range(50, 2000, 10, "suffix:ms") var projectile_flight_ms: int = 320
