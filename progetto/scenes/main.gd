extends Node2D
## Root of the game (Rebirth, Phase 1): ONE simulation, TWO maps.
##   LocalView  — the valley of the homeland: build, watch, live (scenes/local/local_view.tscn);
##   GlobalView — the continent: explore, understand, expand (scenes/global/global_view.tscn).
## They share the same GameSession (Session.current); only one of them is on the table at a time, and no zoom
## ever turns one into the other: the way across is Tab, the buttons of the HUD, or a double click on the
## homeland on the map of the world.

signal view_changed(space: StringName)

@onready var local_view: LocalView = $LocalView
@onready var global_view: GlobalView = $GlobalView
@onready var hud: SettlementHud = $SettlementHud
@onready var debug_overlay: DebugOverlay = $DebugOverlay

## The map on the table (MapSpace.LOCAL or MapSpace.GLOBAL).
var view: StringName = &""
var _args: Dictionary = {}
var _frames_left: int = -1
## Where each map's camera was when the player left it: coming back finds it where it was.
var _global_seen := false


func _ready() -> void:
	InputSetup.register()
	_args = BootArgs.parse()
	if _args.has("load"):
		# a saved world for the standard screenshots: a capital of forty years is made once, not every time
		var loaded := SaveSystem.load_from_file(String(_args["load"]))
		if loaded:
			Session.adopt_loaded(loaded)
	if not Session.has_game():
		Session.start_new()
	var sess := Session.current
	Scenarios.apply(sess, _args, func() -> void: Scenarios.crown_first_family(Session.current))
	if _args.has("save-to"):
		SaveSystem.save_to_file(sess, String(_args["save-to"]), "scenario")   # see --kd-load
	# the double click on the homeland, on the map of the world, goes back to the valley
	global_view.interaction.home_requested.connect(show_local)
	local_view.configure()
	global_view.focus_home(GlobalView.HOME_MPP, true)
	local_view.focus_home(LocalView.HOME_MPP, true)
	var cam_arg := String(_args.get("camera", ""))
	var wanted := String(_args.get("view", ""))
	if wanted == "" and (cam_arg.begins_with("player") or cam_arg.begins_with("global")):
		wanted = "global"
	_set_view(MapSpace.GLOBAL if wanted == "global" else MapSpace.LOCAL)
	_place_camera(cam_arg)

	if _args.has("mapmode"):
		global_view.modes.set_mode(StringName(_args["mapmode"]))
	if _args.has("select"):
		var target := String(_args["select"])
		if target.begins_with("building:"):
			local_view.interaction.select_building(target.get_slice(":", 1).to_int())
		elif Session.current.world.player():
			show_global()
			var pid := Session.current.world.player().capital if target == "player" else target.to_int()
			global_view.interaction.select(pid)
	# the developer's box (FPS, zoom, coordinates) is for the developer: F3 opens it (known problem #1)
	debug_overlay.visible = _args.has("debug") and not _args.has("hide-debug")
	if _args.has("screenshot"):
		global_view.interaction.hover_enabled = false
		_frames_left = String(_args.get("frames", "30")).to_int()
	if _args.has("hide-layers"):
		# profiling: --kd-hide-layers=VegetationLayer,SettlementMarks takes those layers out of the picture
		for n: String in String(_args["hide-layers"]).split(","):
			for v: Node in [local_view, global_view]:
				var layer := v.get_node_or_null("WorldView/" + n)
				if layer:
					layer.process_mode = Node.PROCESS_MODE_DISABLED
					(layer as CanvasItem).visible = false
	if _args.has("benchmark"):
		_bench_total = String(_args["benchmark"]).to_float()
		_bench_active = true


# --- the two maps ------------------------------------------------------------------------------------

func active_camera() -> WorldCamera:
	return global_view.camera if view == MapSpace.GLOBAL else local_view.camera


func is_local() -> bool:
	return view == MapSpace.LOCAL


func show_local() -> void:
	_set_view(MapSpace.LOCAL)


func show_global() -> void:
	if not _global_seen:
		global_view.focus_home(GlobalView.HOME_MPP, true)
	_set_view(MapSpace.GLOBAL)


func toggle_map() -> void:
	if view == MapSpace.GLOBAL:
		show_local()
	else:
		show_global()


## Takes the player to a place on the map it belongs to (a piece of news: "Vai sul posto").
func go_to(pos: Vector2, space: StringName) -> void:
	if space == MapSpace.LOCAL or space == EventBus.SPACE_LOCAL:
		show_local()
		local_view.camera.focus_on(pos, minf(local_view.camera.meters_per_pixel(), 1.2), false)
	else:
		var world := Session.current.world if Session.has_game() else null
		if world and world.domain and world.domain.contains_global(pos) and view == MapSpace.LOCAL:
			# something that happened in the valley itself is shown in the valley
			local_view.camera.focus_on(world.global_to_local(pos), local_view.camera.meters_per_pixel(), false)
			return
		show_global()
		global_view.camera.focus_on(pos, global_view.camera.meters_per_pixel(), false)


func _set_view(space: StringName) -> void:
	if space == view:
		return
	view = space
	if space == MapSpace.GLOBAL:
		local_view.deactivate()
		global_view.activate()
		_global_seen = true
	else:
		global_view.deactivate()
		local_view.activate()
	debug_overlay.set_camera(active_camera())
	hud.set_view(space, active_camera())
	view_changed.emit(space)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"kd_toggle_map"):
		toggle_map()
		get_viewport().set_input_as_handled()


# --- where the cameras start (screenshots, trials) --------------------------------------------------

## --kd-camera: `x,y,mpp` in the metres of the map on the table; `settlement,mpp` / `home,dx,dy,mpp` /
## `domain,mpp` on the valley; `player,mpp` on the homeland seen on the map of the world; `army,mpp` on the first
## host of the crown, on whichever map is on the table.
func _place_camera(cam_arg: String) -> void:
	if cam_arg == "" or not Session.has_game():
		return
	var sess := Session.current
	var parts := cam_arg.split(",")
	var cam := active_camera()
	if cam_arg.begins_with("settlement"):
		local_view.focus_home(parts[1].to_float() if parts.size() > 1 else LocalView.HOME_MPP)
	elif cam_arg.begins_with("home,"):
		cam.focus_on(local_view.home_point() + Vector2(parts[1].to_float(), parts[2].to_float()),
			parts[3].to_float() if parts.size() > 3 else 1.0, true)
	elif cam_arg.begins_with("domain"):
		var d := sess.world.domain
		if d:
			local_view.camera.focus_on(d.center(), parts[1].to_float() if parts.size() > 1 else local_view.max_mpp(), true)
	elif cam_arg.begins_with("player") or cam_arg.begins_with("global"):
		global_view.focus_home(parts[1].to_float() if parts.size() > 1 and parts[1].to_float() > 0.0 else GlobalView.HOME_MPP)
	elif cam_arg.begins_with("army"):
		var zoom := parts[1].to_float() if parts.size() > 1 else 0.2
		for a in sess.world.armies:
			if a.kingdom == sess.world.player_kingdom:
				var pos := a.pos if view == MapSpace.GLOBAL else sess.world.global_to_local(a.pos)
				cam.focus_on(pos, zoom, true)
				break
	else:
		var c := BootArgs.camera_from(_args)
		if not c.is_empty():
			cam.focus_on(c["pos"], c["mpp"], true)


# --- benchmark: flies the camera over the map on the table and reports fps ---
var _bench_active: bool = false
var _bench_total: float = 20.0
var _bench_time: float = 0.0
var _bench_frames: int = 0
var _bench_worst: float = 0.0
var _bench_samples: Dictionary = {}
var _bench_draws := 0.0
var _bench_worst_at := ""
var _bench_draws_max := 0.0
var _bench_draws_max_at := ""
var _bench_objects_max := 0.0


func _bench_step(delta: float) -> void:
	_bench_time += delta
	if _bench_time < 1.0:
		return  # warm-up
	var camera := active_camera()
	var t := (_bench_time - 1.0) / _bench_total
	if t >= 1.0:
		var lines: PackedStringArray = []
		for k in _bench_samples.keys():
			var s: Array = _bench_samples[k]
			lines.append("%s: %.1f fps avg (%d frames)" % [k, s[1] / maxf(s[0], 0.001), int(s[1])])
		print("[KD:benchmark] map %s · avg %.1f fps, worst frame %.1f ms | %s" % [view, _bench_frames / _bench_total, _bench_worst * 1000.0, " | ".join(lines)])
		print("[KD:benchmark] worst frame at %s · most draw calls at %s" % [_bench_worst_at, _bench_draws_max_at])
		print("[KD:benchmark] systems: ", Session.current.scheduler.profile_report().replace("\n", " | ") if "scheduler" in Session.current else "")
		print("[KD:benchmark] draw calls avg %.0f max %.0f · objects max %.0f · nodes %d (orphans %d) · static memory %.0f MB · video memory %.0f MB" % [
			_bench_draws / maxf(float(_bench_frames), 1.0), _bench_draws_max, _bench_objects_max,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
		get_tree().quit(0)
		return
	_bench_frames += 1
	if delta > _bench_worst:
		_bench_worst_at = "t=%.2fs mpp=%.2f day=%d" % [_bench_time, camera.meters_per_pixel(), Session.current.world.day]
	_bench_worst = maxf(_bench_worst, delta)
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_bench_draws += draws
	if draws > _bench_draws_max:
		_bench_draws_max_at = "t=%.2fs mpp=%.2f" % [_bench_time, camera.meters_per_pixel()]
	_bench_draws_max = maxf(_bench_draws_max, draws)
	_bench_objects_max = maxf(_bench_objects_max, Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var pos: Vector2
	var mpp: float
	var band: String
	if view == MapSpace.GLOBAL:
		# across the continent, from the whole of it down to the provinces
		var size := WorldConstants.world_size()
		pos = Vector2(lerpf(size.x * 0.25, size.x * 0.75, t), size.y * (0.45 + 0.1 * sin(t * TAU)))
		mpp = exp(lerpf(log(GlobalView.MAX_MPP * 0.75), log(GlobalView.MIN_MPP), absf(sin(t * PI * 1.5))))
		band = "continent>30" if mpp > 30.0 else ("realms 12-30" if mpp > 12.0 else "provinces<12")
	else:
		# around the community: where the houses, the fields, the people and the woods all are
		pos = local_view.home_point() + Vector2(cos(t * TAU), sin(t * TAU)) * 180.0
		mpp = exp(lerpf(log(local_view.max_mpp()), log(0.2), absf(sin(t * PI * 1.5))))
		band = "valley>2.7" if mpp > 2.7 else ("village 1-2.7" if mpp > 1.0 else "close<1")
	camera.focus_on(pos, mpp, true)
	var s: Array = _bench_samples.get(band, [0.0, 0.0])
	s[0] += delta
	s[1] += 1.0
	_bench_samples[band] = s


func _process(delta: float) -> void:
	if _bench_active:
		_bench_step(delta)
	if _frames_left < 0:
		return
	_frames_left -= 1
	if _frames_left == 0:
		_take_screenshot(String(_args["screenshot"]))


func _take_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var abs_path := path
	if not path.is_absolute_path() and not path.begins_with("res://") and not path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path("res://").path_join(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := img.save_png(abs_path)
	print("[KD:screenshot] %s -> %s" % [abs_path, error_string(err)])
	get_tree().quit(0 if err == OK else 1)
