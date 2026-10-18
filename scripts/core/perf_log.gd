class_name PerfLog
extends Node
## Dev tool (--perf-log=S, card #237): with vsync off and no frame cap, prints a PERF line every S
## seconds (frames a second on average and at the slowest frame, draw calls, objects and
## triangles drawn, process time) and a PERF_SUMMARY line when the game quits, so the cost of the
## 3D world pieces can be measured without a person watching. Does nothing in a headless run.

var _every_s: float = 2.0
var _left_s: float = 0.0
var _frames: int = 0
var _time_s: float = 0.0
var _worst_s: float = 0.0
var _all_frames: int = 0
var _all_time_s: float = 0.0
var _all_worst_s: float = 0.0
var _max_draws: int = 0
var _max_objects: int = 0
var _max_triangles: int = 0


func setup(every_s: float) -> void:
	_every_s = maxf(0.5, every_s)
	_left_s = _every_s
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	print("Perf log: every %.1f s" % _every_s)


func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_frames += 1
	_time_s += delta
	_worst_s = maxf(_worst_s, delta)
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var triangles := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_max_draws = maxi(_max_draws, draws)
	_max_objects = maxi(_max_objects, objects)
	_max_triangles = maxi(_max_triangles, triangles)
	_left_s -= delta
	if _left_s > 0.0:
		return
	_left_s = _every_s
	print("PERF fps=%d slowest_fps=%d draws=%d objects=%d triangles=%d process_ms=%.2f" % [
			roundi(_frames / maxf(_time_s, 0.001)), roundi(1.0 / maxf(_worst_s, 0.0001)), draws, objects, triangles,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	_all_frames += _frames
	_all_time_s += _time_s
	_all_worst_s = maxf(_all_worst_s, _worst_s)
	_frames = 0
	_time_s = 0.0
	_worst_s = 0.0


func _exit_tree() -> void:
	if _all_frames > 0:
		print("PERF_SUMMARY fps=%d slowest_fps=%d max_draws=%d max_objects=%d max_triangles=%d" % [
				roundi(_all_frames / maxf(_all_time_s, 0.001)), roundi(1.0 / maxf(_all_worst_s, 0.0001)),
				_max_draws, _max_objects, _max_triangles])
