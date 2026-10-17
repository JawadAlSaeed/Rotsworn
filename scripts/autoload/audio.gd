extends Node
## Global sound player (autoload "Audio"). Plays named cues from data/audio/sfx_library.tres.
## A missing or broken file prints one warning and stays silent; it never crashes the game.
## Usage: Audio.play("parry")
## Music: play_music(path) loops one song; asking for the song already playing lets it go on (no
## restart). A new song crossfades in (two players) with the fade times from data/audio/music.tres.

const LIBRARY_PATH := "res://data/audio/sfx_library.tres"
const POOL_SIZE := 24
const MUSIC_SET_PATH := "res://data/audio/music.tres"
const MIX_PATH := "res://data/audio/mix.tres"
## A fading song counts as silent here.
const SILENT_DB := -60.0

var _library: SfxLibrary
## cue name -> AudioStream (null if it failed to load)
var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _mix: AudioMix
## cue name -> when it last started (ms), for the per-cue cooldown.
var _last_start_ms: Dictionary = {}
var _warned: Dictionary = {}
## Two players so the old song can fade out while the new one fades in; _music is the current one.
var _music_players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music_path: String = ""
## The current song's fade-in (0 to 1) and how long fades take.
var _music_fade: float = 1.0
var _fade_in_s: float = 0.0
var _fade_out_s: float = 0.0
var _fade_in_tween: Tween
var _fade_out_tweens: Dictionary = {}
## The song's own volume and the dip on top of it (duck_music).
var _music_base_db: float = 0.0
var _music_duck_db: float = 0.0
var _duck_tween: Tween
## The place's background loop (zone ambience), on the Effects bus.
var _ambience: AudioStreamPlayer
var _ambience_path: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for channel: String in ["music", "effects", "voice"]:
		_ensure_bus(String(PlayerSettings.CHANNELS[channel].bus))
	PlayerSettings.apply_volume()
	_mix = load(MIX_PATH) as AudioMix if ResourceLoader.exists(MIX_PATH) else null
	if _mix == null:
		push_warning("Audio: no mix at %s, using defaults" % MIX_PATH)
		_mix = AudioMix.new()
	_add_master_limiter()
	_ensure_library()
	for i: int in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % i
		add_child(player)
		_pool.append(player)
	for i: int in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % i
		player.bus = String(PlayerSettings.CHANNELS.music.bus)
		add_child(player)
		# Loops any format the same way: when the song ends, it starts again.
		player.finished.connect(player.play)
		_music_players.append(player)
	_music = _music_players[0]
	var music_set := load(MUSIC_SET_PATH) as MusicSet if ResourceLoader.exists(MUSIC_SET_PATH) else null
	if music_set != null:
		_fade_in_s = float(music_set.fade_in_ms) / 1000.0
		_fade_out_s = float(music_set.fade_out_ms) / 1000.0
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "Ambience"
	_ambience.bus = String(PlayerSettings.CHANNELS.effects.bus)
	add_child(_ambience)
	_ambience.finished.connect(_ambience.play)


## Loops the song at `path` (empty: silence). The song already playing goes on untouched.
func play_music(path: String, volume_db: float = 0.0) -> void:
	_music_base_db = volume_db
	if path == _music_path and _music.playing:
		_update_music_volume()
		return
	# A new song starts without any dip left over from the last place.
	if _duck_tween != null:
		_duck_tween.kill()
	_music_duck_db = 0.0
	_fade_out(_music)
	_music_path = path
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
	_music = _music_players[1] if _music == _music_players[0] else _music_players[0]
	if _fade_out_tweens.has(_music):
		(_fade_out_tweens[_music] as Tween).kill()
		_fade_out_tweens.erase(_music)
	_music.stop()
	_music.stream = stream
	if _fade_in_tween != null:
		_fade_in_tween.kill()
	_set_music_fade(0.0 if _fade_in_s > 0.0 else 1.0)
	_music.play()
	if _fade_in_s > 0.0:
		_fade_in_tween = create_tween()
		_fade_in_tween.tween_method(_set_music_fade, 0.0, 1.0, _fade_in_s)


## Fades a song out over the fade-out time, then stops it.
func _fade_out(player: AudioStreamPlayer) -> void:
	if not player.playing:
		return
	if _fade_out_s <= 0.0:
		player.stop()
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", SILENT_DB, _fade_out_s)
	tween.tween_callback(player.stop)
	_fade_out_tweens[player] = tween


func _set_music_fade(fade: float) -> void:
	_music_fade = fade
	_update_music_volume()


func _update_music_volume() -> void:
	_music.volume_db = maxf(SILENT_DB, _music_base_db + _music_duck_db + linear_to_db(maxf(_music_fade, 0.001)))


## Dips the music by `db` (0: back to full) over `ms`, for example while an enemy attacks.
func duck_music(db: float, ms: int) -> void:
	if _duck_tween != null:
		_duck_tween.kill()
	if ms <= 0:
		_apply_music_volume(db)
		return
	_duck_tween = create_tween()
	_duck_tween.tween_method(_apply_music_volume, _music_duck_db, db, float(ms) / 1000.0)


func _apply_music_volume(duck_db: float) -> void:
	_music_duck_db = duck_db
	_update_music_volume()


## Loops the background sound at `path` (empty: silence). The loop already playing goes on.
func play_ambience(path: String, volume_db: float = 0.0) -> void:
	_ambience.volume_db = volume_db
	if path == _ambience_path and _ambience.playing:
		return
	_ambience_path = path
	_ambience.stop()
	_ambience.stream = null
	if path.is_empty():
		return
	var stream: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	if stream == null:
		_warn_once(path, "Audio: no playable ambience at '%s'" % path)
		return
	_ambience.stream = stream
	_ambience.play()


func stop_music() -> void:
	_music_path = ""
	for tween: Tween in _fade_out_tweens.values():
		tween.kill()
	_fade_out_tweens.clear()
	if _fade_in_tween != null:
		_fade_in_tween.kill()
	for player: AudioStreamPlayer in _music_players:
		player.stop()
		player.stream = null


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
	var now := Time.get_ticks_msec()
	if VoicePool.in_cooldown(int(_last_start_ms.get(cue_name, -1)), now, _mix.cue_cooldown_ms):
		return
	_last_start_ms[cue_name] = now
	var busy: Array[bool] = []
	var remaining: Array[float] = []
	for p: AudioStreamPlayer in _pool:
		busy.append(p.playing)
		var left := 0.0
		if p.playing and p.stream != null:
			left = maxf(0.0, p.stream.get_length() - p.get_playback_position())
		remaining.append(left)
	var player := _pool[VoicePool.pick(busy, remaining)]
	player.stream = stream
	player.bus = String(PlayerSettings.CHANNELS["voice" if cue.voice else "effects"].bus)
	player.volume_db = cue.volume_db + volume_offset_db
	var jitter := 1.0
	if cue.pitch_jitter > 0.0:
		jitter = randf_range(1.0 - cue.pitch_jitter, 1.0 + cue.pitch_jitter)
	player.pitch_scale = maxf(0.01, pitch_scale * jitter)
	player.play()


## How long a cue's sound lasts in ms (0 for an unknown cue or a missing file).
func cue_length_ms(cue_name: String) -> int:
	var cue := _ensure_library().find(cue_name)
	var stream := _stream_for(cue) if cue != null else null
	return roundi(stream.get_length() * 1000.0) if stream != null else 0


## A hard limiter on Master (with a little headroom before it), so stacked cues never clip.
func _add_master_limiter() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	for i: int in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.pre_gain_db = _mix.limiter_pre_gain_db
	limiter.ceiling_db = _mix.limiter_ceiling_db
	limiter.release = _mix.limiter_release_s
	AudioServer.add_bus_effect(master, limiter)


## Adds an audio bus (sent to Master) unless it exists, so the settings can turn it up or down.
static func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, &"Master")


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
	if _ambience != null:
		_ambience_path = ""
		_ambience.stop()
		_ambience.stream = null


func _exit_tree() -> void:
	stop_all()


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)
