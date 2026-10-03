extends Node
## Automated screenshots: run Godot with
##   -- --capture=res://data/capture/phase1_views.json --out=/abs/dir
## Each view moves the camera, waits for a few frames (textures, animations), saves a PNG and a
## line of performance data. Quits when done. Inactive without --capture.

var views: Array = []
var out_dir := ""
var camera: Node
var perf_log: Array = []


func _ready() -> void:
	var cap := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			cap = a.substr(10)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
	if cap == "":
		return
	var f := FileAccess.open(cap, FileAccess.READ)
	views = JSON.parse_string(f.get_as_text())
	DirAccess.make_dir_recursive_absolute(out_dir)
	camera = get_tree().get_first_node_in_group("valley_camera")
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	for v in views:
		if v.has("call"):
			var target := get_tree().current_scene
			if target.has_method(v["call"]):
				target.call(v["call"])
		if v.has("x"):
			camera.jump_to_ground(v["x"], v["y"], v["zoom"])
		elif v.has("px"):
			camera.jump_to(Vector2(v["px"], v["py"]), v["zoom"])
		var wait: int = v.get("wait", 6)
		var t0 := Time.get_ticks_usec()
		for i in wait:
			await get_tree().process_frame
		var dt := float(Time.get_ticks_usec() - t0) / 1000.0 / float(wait)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path: String = out_dir.path_join(String(v["name"]) + ".png")
		img.save_png(path)
		var rec := {
			"view": v["name"],
			"frame_ms_cpu_render": snappedf(dt, 0.1),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
			"vram_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
			"texture_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		}
		perf_log.append(rec)
		print("captured ", path, " ", rec)
	var pf := FileAccess.open(out_dir.path_join("perf.json"), FileAccess.WRITE)
	pf.store_string(JSON.stringify(perf_log, "  "))
	get_tree().quit()
