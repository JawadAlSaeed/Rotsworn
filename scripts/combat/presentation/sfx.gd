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
