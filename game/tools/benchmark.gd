extends Node
## Benchmark for real hardware:  godot --path game -- --benchmark [--views=res://data/capture/slice_views.json]
## Visits every view of the list (Phase 1 views by default), holds it for 5 s, records FPS / frame time / draw calls, prints a table
## and writes user://benchmark.json. Quits when done.

const VIEWS := "res://data/capture/phase1_views.json"
const HOLD := 5.0

var _views: Array = []
var _i := -1
var _t := 0.0
var _frames := 0
var _worst := 0.0
var _results: Array = []
var _cam: Node


func _ready() -> void:
	if not "--benchmark" in OS.get_cmdline_user_args():
		queue_free()
		return
	var views_file := VIEWS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--views="):
			views_file = a.substr(8)
	_views = JSON.parse_string(FileAccess.get_file_as_string(views_file))
	_cam = get_tree().get_first_node_in_group("valley_camera")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_next()


func _next() -> void:
	if _i >= 0:
		var v: Dictionary = _views[_i]
		_results.append({"view": v["name"], "avg_fps": snappedf(_frames / HOLD, 0.1),
			"worst_frame_ms": snappedf(_worst * 1000.0, 0.1),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"vram_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)})
		print(_results[-1])
	_i += 1
	if _i >= _views.size():
		var f := FileAccess.open("user://benchmark.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "results": _results}, "  "))
		print("benchmark written to ", ProjectSettings.globalize_path("user://benchmark.json"))
		get_tree().quit()
		return
	var v: Dictionary = _views[_i]
	if v.has("x"):
		_cam.jump_to_ground(v["x"], v["y"], v["zoom"])
	_t = -1.0          # 1 s warm-up
	_frames = 0
	_worst = 0.0


func _process(delta: float) -> void:
	if _i < 0:
		return
	_t += delta
	if _t < 0.0:
		return
	_frames += 1
	_worst = maxf(_worst, delta)
	if _t >= HOLD:
		_next()
