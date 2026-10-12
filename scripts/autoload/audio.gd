extends Node
## Global sound player (autoload "Audio"). Plays named cues from data/audio/sfx_library.tres.
## A missing or broken file prints one warning and stays silent; it never crashes the game.
## Usage: Audio.play("parry")
## Music: play_music(path) loops one song on its own player; asking for the song already playing
## lets it go on (no restart). Paths come from data/audio/music.tres (MusicSet).

const LIBRARY_PATH := "res://data/audio/sfx_library.tres"
const POOL_SIZE := 24

var _library: SfxLibrary
## cue name -> AudioStream (null if it failed to load)
var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next_player := 0
var _warned: Dictionary = {}
var _music: AudioStreamPlayer
var _music_path: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_library()
	for i: int in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % i
		add_child(player)
		_pool.append(player)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	add_child(_music)
	# Loops any format the same way: when the song ends, it starts again.
	_music.finished.connect(_music.play)


## Loops the song at `path` (empty: silence). The song already playing goes on untouched.
func play_music(path: String, volume_db: float = 0.0) -> void:
	_music.volume_db = volume_db
	if path == _music_path and _music.playing:
		return
	_music_path = path
	_music.stop()
	_music.stream = null
	if path.is_empty():
		return
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	elif path.ends_with(".wav") and FileAccess.file_exists(path):
		stream = AudioStreamWAV.load_from_file(path)
	if stream == null:
		_warn_once(path, "Audio: no playable song at '%s'" % path)
		return
	_music.stream = stream
	_music.play()


func stop_music() -> void:
	_music_path = ""
	_music.stop()
	_music.stream = null


## Plays a cue. `volume_offset_db` is added to the cue's own volume.
func play(cue_name: String, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var cue := _ensure_library().find(cue_name)
	if cue == null:
		_warn_once(cue_name, "Audio: unknown cue '%s' (add it to %s)" % [cue_name, LIBRARY_PATH])
		return
	var stream := _stream_for(cue)
	if stream == null:
		return
	if _pool.is_empty():
		_warn_once("_no_pool", "Audio: play('%s') before the Audio node is ready" % cue_name)
		return
	var player := _pool[_next_player]
	_next_player = (_next_player + 1) % _pool.size()
	player.stream = stream
	player.volume_db = cue.volume_db + volume_offset_db
	var jitter := 1.0
	if cue.pitch_jitter > 0.0:
		jitter = randf_range(1.0 - cue.pitch_jitter, 1.0 + cue.pitch_jitter)
	player.pitch_scale = maxf(0.01, pitch_scale * jitter)
	player.play()


## Loads every cue now so the first parry sound has no loading hitch.
func preload_all() -> void:
	for cue: SfxCue in _ensure_library().cues:
		if cue != null:
			_stream_for(cue)


## True if the library defines `cue_name` (whether or not its file exists).
func has_cue(cue_name: String) -> bool:
	return _ensure_library().find(cue_name) != null


## Loads the library on first use, so calls made before _ready (for example from another
## autoload) work instead of crashing.
func _ensure_library() -> SfxLibrary:
	if _library != null:
		return _library
	if ResourceLoader.exists(LIBRARY_PATH):
		_library = load(LIBRARY_PATH) as SfxLibrary
	if _library == null:
		push_warning("Audio: no sound library at %s" % LIBRARY_PATH)
		_library = SfxLibrary.new()
	return _library


func _stream_for(cue: SfxCue) -> AudioStream:
	if _streams.has(cue.name):
		return _streams[cue.name]
	var stream: AudioStream = null
	if not cue.path.is_empty() and ResourceLoader.exists(cue.path):
		stream = load(cue.path) as AudioStream
	elif cue.path.ends_with(".wav") and FileAccess.file_exists(cue.path):
		# Dropped in but not imported yet: read the WAV straight from disk.
		stream = AudioStreamWAV.load_from_file(cue.path)
		if stream != null:
			_warn_once(cue.name, "Audio: '%s' is not imported yet; read the raw file" % cue.path)
	if stream == null:
		_warn_once(cue.name, "Audio: cue '%s' has no playable file at '%s'" % [cue.name, cue.path])
	_streams[cue.name] = stream
	return stream


## Stops every sound and releases the streams. Called on quit, because quitting while a sound
## still plays leaks its playback and Godot reports "resources still in use at exit".
func stop_all() -> void:
	for player: AudioStreamPlayer in _pool:
		player.stop()
		player.stream = null
	_streams.clear()
	if _music != null:
		stop_music()


func _exit_tree() -> void:
	stop_all()


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)
