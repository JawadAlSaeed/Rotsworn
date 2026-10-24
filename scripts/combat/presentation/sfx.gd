class_name Sfx
extends RefCounted
## Plays sound cues through the Audio autoload (scripts/autoload/audio.gd). Presentation scripts
## call this instead of the global `Audio` name so they still pass `--check-only`, which does not
## register autoload names. Silent if the autoload is missing (for example in unit tests).

const AUTOLOAD_PATH := ^"/root/Audio"


static func play(cue: String, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var audio := _audio()
	if audio != null:
		audio.call(&"play", cue, volume_offset_db, pitch_scale)


## How long a cue's sound lasts in ms (0 if it has none), to time a sound that must end on a beat.
static func cue_length_ms(cue: String) -> int:
	var audio := _audio()
	return int(audio.call(&"cue_length_ms", cue)) if audio != null else 0


## Stops every sound (before quitting, so no playback is left running at exit).
static func stop_all() -> void:
	var audio := _audio()
	if audio != null:
		audio.call(&"stop_all")


## Loops a song (see MusicSet); the song already playing goes on.
static func play_music(path: String, volume_db: float = 0.0) -> void:
	var audio := _audio()
	if audio != null:
		audio.call(&"play_music", path, volume_db)


## Loops the weather's sound (empty path: silence; card #303).
static func play_weather(path: String, volume_db: float = 0.0) -> void:
	var audio := _audio()
	if audio != null:
		audio.call(&"play_weather", path, volume_db)


## Dips the music by `db` (0: back to full) over `ms`.
static func duck_music(db: float, ms: int) -> void:
	var audio := _audio()
	if audio != null:
		audio.call(&"duck_music", db, ms)


## Cuts the song to silence over `ms` (`on`) or brings it back at once (card #308).
static func hush_music(on: bool, ms: int = 0) -> void:
	var audio := _audio()
	if audio != null:
		audio.call(&"hush_music", on, ms)


## Swells the music `db` louder over `ms` (0: back to normal), on top of any dip (card #300).
static func lift_music(db: float, ms: int) -> void:
	var audio := _audio()
	if audio != null:
		audio.call(&"lift_music", db, ms)


## Loads every cue now so the first parry sound has no loading hitch.
static func preload_all() -> void:
	var audio := _audio()
	if audio != null:
		audio.call(&"preload_all")


static func _audio() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(AUTOLOAD_PATH)
