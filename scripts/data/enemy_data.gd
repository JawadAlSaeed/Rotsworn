class_name EnemyData
extends Resource
## An enemy type.

## Unique id used in events and save data.
@export var id: String = ""
@export var display_name: String = ""
## Accent colour for UI and placeholder tint.
@export var color: Color = Color.WHITE
## Battle sprite sheet: one row of equal frames in this order:
## idle, windup, lunge, contact, hurt, slam. Replace the file to change the art.
@export_file_path("*.png") var sprite_path: String = ""
## Number of frames in the sprite sheet row.
@export_range(1, 64) var sprite_hframes: int = 6
## Small picture for the timeline.
@export_file_path("*.png") var portrait_path: String = ""
## World units per sprite pixel (bigger = larger on screen).
@export_range(0.001, 0.2, 0.001) var sprite_pixel_size: float = 0.05
## HP, in percent of tuning base_enemy_hp.
@export_range(10, 10000, 5, "suffix:%") var hp_percent: int = 100
## Power (damage per hit), in percent of tuning base_enemy_hit_damage.
@export_range(10, 1000, 5, "suffix:%") var power_percent: int = 100
## Turn speed. 100 is average; 200 acts twice as often as 100.
@export_range(1, 1000) var speed: int = 100
@export var attacks: Array[EnemyAttackData] = []
## Gold and XP the party gets for beating it in a run (DESIGN.md 8).
@export_range(0, 10000) var gold: int = 10
@export_range(0, 10000) var xp: int = 20

@export_group("Phase two (bosses)")
## When its HP drops to this percent of max HP or lower, it enters phase two: it attacks with
## phase_two_attacks at phase_two_speed. 0 = no phase two.
@export_range(0, 99, 1, "suffix:%") var phase_two_hp_percent: int = 0
@export var phase_two_attacks: Array[EnemyAttackData] = []
## Speed in phase two (0 = unchanged).
@export_range(0, 1000) var phase_two_speed: int = 0
## Shown as a banner when phase two starts.
@export var phase_two_text: String = ""
