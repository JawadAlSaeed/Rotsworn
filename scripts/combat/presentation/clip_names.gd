class_name ClipNames
extends RefCounted
## Clip names (DESIGN.md 5.5) and the fallback chain that lets a missing clip show the closest one
## the sheet has. When nothing fits, resolve() returns "" and the caller shows its legacy pose.
## Pure and static.

## Row 0 of a hero sheet, in FighterView.CharPose order.
const HERO_POSES: Array[String] = ["idle", "ready", "parry", "dodge", "jump", "hurt", "strike", "down"]
## Row 0 of an enemy sheet, in EnemyChoreography.Pose order.
const ENEMY_POSES: Array[String] = ["idle", "windup", "lunge", "contact", "hurt", "slam"]
## Poses that set_pose() loops (real time) when their clip has more than one cell.
const LOOPS: Array[String] = ["idle", "ready", "down"]
const STRIKE: String = "strike"
const STRIKE_WINDUP: String = "strike_windup"
const WINDUP_SUFFIX: String = "_windup"
## A second limb or variant of a clip: `<x>_b` falls back to `<x>`.
const ALT_SUFFIX: String = "_b"
## Named fallbacks, tried one after another.
const FALLBACK: Dictionary = {
	"stagger": "hurt",
	"strike_alt": "strike",
	"strike_big": "strike",
	"follow_up": "strike_alt",
	"follow_up_windup": "strike_alt_windup",
	"ultimate_1": "strike_alt",
	"ultimate_2": "strike_big",
	"cast": "strike",
	"cast_windup": "strike_windup",
	"run": "walk_side",
	"leap": "jump_up",
	"windup_ground": "windup",
	"windup_shoot": "windup",
	"shoot": "contact",
}
## The clip catalogue (DESIGN.md 5.5). These fall back only through FALLBACK (so jump_down never
## turns into down); any other name is a variant (`<prefix>_<x>` or `<x>_b`) of a catalogue clip.
const KNOWN: Array[String] = [
	# Heroes: row 0 poses, then the combat clips and the walks the zones used (walk_side is the run-up).
	"idle", "ready", "parry", "dodge", "jump", "hurt", "strike", "down",
	"draw", "parry_hit", "jump_up", "jump_down", "stagger", "strike_windup", "strike_alt_windup",
	"strike_alt", "strike_big_windup", "strike_big", "cast_windup", "cast", "leap", "fall",
	"get_up", "victory", "victory_hold", "follow_up", "follow_up_windup", "ultimate_1",
	"ultimate_2", "walk_side", "walk_front", "walk_back", "stand_front", "stand_back", "pickup",
	"run",
	# Enemies.
	"windup", "windup_hold", "windup_ground", "lunge", "contact", "recoil", "return", "slam",
	"slam_recover", "death", "walk", "chase", "rage", "windup_shoot", "shoot",
]
## Longest fallback chain followed (guards against a loop in the table).
const MAX_STEPS: int = 8


## The clip name of a legacy pose (a row-0 cell), "" when out of range.
static func pose_name(pose: int, party: bool) -> String:
	var names: Array[String] = HERO_POSES if party else ENEMY_POSES
	return names[pose] if pose >= 0 and pose < names.size() else ""


## The clip the sheet has for `clip`, trying in order: clip + suffix (a facing, zone only), clip,
## its fallbacks one after another, then strike_windup for any wind-up and strike for any other
## name outside the catalogue (a per-skill strike). "" when none fits.
static func resolve(clips: SpriteClips, clip: String, suffix: String = "") -> String:
	if clips == null or clip.is_empty():
		return ""
	if not suffix.is_empty() and clips.count(clip + suffix) > 0:
		return clip + suffix
	var name := clip
	for i: int in MAX_STEPS:
		if name.is_empty():
			break
		if clips.count(name) > 0:
			return name
		name = next(name)
	if clip.ends_with(WINDUP_SUFFIX):
		return STRIKE_WINDUP if clips.count(STRIKE_WINDUP) > 0 else ""
	if not KNOWN.has(clip) and clips.count(STRIKE) > 0:
		return STRIKE
	return ""


## The cells of resolve(clips, clip, suffix); empty when none fits.
static func cells(clips: SpriteClips, clip: String, suffix: String = "") -> PackedInt32Array:
	var found := resolve(clips, clip, suffix)
	return clips.frames(found) if not found.is_empty() else PackedInt32Array()


## The next name to try after `clip`: its FALLBACK entry; nothing for any other catalogue clip;
## `<x>` for a variant `<x>_b` or `<prefix>_<x>`.
static func next(clip: String) -> String:
	if FALLBACK.has(clip):
		return String(FALLBACK[clip])
	if KNOWN.has(clip):
		return ""
	if clip.length() > ALT_SUFFIX.length() and clip.ends_with(ALT_SUFFIX):
		return clip.left(clip.length() - ALT_SUFFIX.length())
	var cut := clip.find("_")
	if cut > 0 and cut < clip.length() - 1:
		return clip.substr(cut + 1)
	return ""
