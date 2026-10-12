class_name IntroScreen
extends CanvasLayer
## The studio intro when the game starts (DESIGN.md 7.5): the video from BootData on black,
## scaled to fit. Any key, button or click skips it (after skip_guard_ms). `done` comes once,
## when it ends or is skipped. A missing video is skipped at once (with a warning).

signal done

var _player: VideoStreamPlayer
var _started_ms: int = 0
var _guard_ms: int = 0
var _finished: bool = false


func setup(boot: BootData) -> void:
	layer = 40
	_guard_ms = boot.skip_guard_ms
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stream: VideoStream = null
	if not boot.intro_video_path.is_empty() and ResourceLoader.exists(boot.intro_video_path):
		stream = load(boot.intro_video_path) as VideoStream
	if stream == null:
		if not boot.intro_video_path.is_empty():
			push_warning("IntroScreen: no playable video at '%s', skipping the intro" % boot.intro_video_path)
		_finish.call_deferred()
		return
	var frame := AspectRatioContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	_player = VideoStreamPlayer.new()
	_player.stream = stream
	_player.expand = true
	_player.volume_db = boot.intro_volume_db
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_player)
	_player.finished.connect(_finish)


func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	if _player != null:
		_player.play()
	set_process(_player != null)


## The frame takes the video's own shape once its first picture is known (black bars if the
## screen's shape differs).
func _process(_delta: float) -> void:
	var texture := _player.get_video_texture()
	if texture != null and texture.get_width() > 0 and texture.get_height() > 0:
		(_player.get_parent() as AspectRatioContainer).ratio = float(texture.get_width()) / float(texture.get_height())
		set_process(false)


func _input(event: InputEvent) -> void:
	if _finished or Time.get_ticks_msec() - _started_ms < _guard_ms:
		return
	var pressed := (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) \
			and event.is_pressed() and not event.is_echo()
	if pressed:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _player != null:
		_player.stop()
	done.emit()
