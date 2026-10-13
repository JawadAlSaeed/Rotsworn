class_name ScreenShooter
extends Node
## Dev tool (--shots=S): saves a picture of the window every S seconds to user://shots/<name>/,
## so the look can be checked without a person watching. Does nothing in a headless run.

const ROOT := "user://shots"

var _every_s: float = 1.0
var _left_s: float = 0.0
var _count: int = 0
var _dir: String = ROOT


func setup(every_s: float, folder: String) -> void:
	_every_s = maxf(0.1, every_s)
	_left_s = _every_s
	_dir = "%s/%s" % [ROOT, folder]
	DirAccess.make_dir_recursive_absolute(_dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("Shots: every %.1f s to %s" % [_every_s, ProjectSettings.globalize_path(_dir)])


func _process(delta: float) -> void:
	_left_s -= delta
	if _left_s > 0.0:
		return
	_left_s = _every_s
	if DisplayServer.get_name() == "headless":
		return
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return
	_count += 1
	image.save_png("%s/%04d.png" % [_dir, _count])
