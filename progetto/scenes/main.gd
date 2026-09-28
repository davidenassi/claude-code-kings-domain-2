extends Node2D
## Root of the game: one world view, one camera, one simulation.

@onready var camera: WorldCamera = $WorldCamera
@onready var world_view: WorldView = $WorldView
@onready var debug_overlay: DebugOverlay = $DebugOverlay

var _args: Dictionary = {}
var _frames_left: int = -1


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
	if _args.has("no-events"):
		sess.set_system_enabled(&"events", false)   # clean screenshots: no card in front of the lens
	if _args.has("speed"):
		sess.clock.set_speed(String(_args["speed"]).to_int())
	if _args.get("scenario", "").begins_with("village") and not sess.world.settlements.is_empty():
		SettlementPlanner.place_starter_village(sess, sess.world.settlements[0].id)
	if _args.get("scenario", "") == "village_grown" and not sess.world.settlements.is_empty():
		# a village that has had a few years: for looking at a street rather than at four buildings
		var home := sess.world.settlements[0]
		home.add(&"wood", 200)
		home.add(&"stone", 80)
		for i in 7:
			var spot := SettlementPlanner.find_spot(sess, home.id, &"house", home.center, 30.0 + i * 4.0)
			if spot != Vector2.INF:
				sess.submit(PlaceBuildingCommand.create(home.id, &"house", spot))
		sess.advance_days(160)
	var scenario := String(_args.get("scenario", ""))
	if scenario in ["community_ready", "coronation", "kingdom", "kingdom_grown"] and not sess.world.settlements.is_empty():
		# the six founders grown into a village that could choose its royal house (Phase 15): for trying the
		# choice at once and for the screenshots of the families and of the coronation
		SettlementPlanner.place_starter_village(sess, sess.world.settlements[0].id)
		for month in 12 * 10:
			sess.advance_days(30)
			SettlementPlanner.lord_month(sess, sess.world.settlements[0].id, 60)
			if CourtSystem.monarchy_blocker(sess, sess.world.player()) == "":
				break
		if scenario == "coronation":
			# crowned with the interface already open, so the moment is shown as the player would see it
			get_tree().create_timer(0.3).timeout.connect(_crown_first_family)
		elif scenario.begins_with("kingdom"):
			# a kingdom already standing when the interface opens: for the sheets of the realm (Phase 18 audit)
			_crown_first_family()
			if scenario == "kingdom_grown":
				# and twenty more years of a careful ruler (or --kd-years): lands, laws, a larger capital
				var pilot: GDScript = load("res://tests/campaign/campaign_pilot.gd")   # dev tooling, loaded only here
				for month in 12 * String(_args.get("years", "20")).to_int():
					sess.advance_days(30)
					pilot.month(sess)
	if _args.get("scenario", "") == "war" and not sess.world.settlements.is_empty():
		# a host of ours and an enemy one in front of the village: for screenshots and for trying the battle
		SettlementPlanner.place_starter_village(sess, sess.world.settlements[0].id)
		var home := sess.world.settlements[0]
		home.add(&"weapons", 40)
		var me := sess.world.player()
		me.treasury = 900.0
		sess.submit(RecruitUnitCommand.create(home.id, &"lancieri"))
		sess.advance_days(Military.unit(&"lancieri").train_days + 1)
		for other in sess.world.kingdoms:
			if other.id == me.id or not other.alive or other.provinces.is_empty():
				continue
			other.treasury = 2000.0
			Diplomacy.start_war(sess.world, other.id, me.id)
			var enemy := ArmyState.new()
			enemy.id = sess.world.new_id()
			enemy.kingdom = other.id
			enemy.name = Military.army_name(sess.world, other)
			enemy.province = home.province
			enemy.pos = home.center + Vector2(3400.0, 900.0)   # far enough to sit down and besiege, not to charge
			enemy.step_from = enemy.pos
			enemy.step_to = enemy.pos
			enemy.supplies = 20.0
			enemy.regiments.append({"unit": &"alabardieri", "men": 12, "max_men": 12, "morale": 70.0,
				"people": PackedInt32Array()})
			sess.world.armies.append(enemy)
			break
		sess.advance_days(12)
	if _args.get("scenario", "") == "army" and not sess.world.settlements.is_empty():
		# a village with a host already in the field: for screenshots and for trying the marches
		SettlementPlanner.place_starter_village(sess, sess.world.settlements[0].id)
		var village := sess.world.settlements[0]
		village.add(&"weapons", 40)
		sess.world.player().treasury = 900.0
		sess.submit(RecruitUnitCommand.create(village.id, &"lancieri"))
		sess.advance_days(Military.unit(&"lancieri").train_days + 1)
	if scenario.begins_with("stress_") and not sess.world.settlements.is_empty():
		# Phase 19: worlds pushed past a normal campaign, for the frame rate under load (dev tooling, loaded
		# only here): a town of --kd-people inhabitants, or every realm in arms and at war with its neighbours
		var stress: GDScript = load("res://tests/stress/stress_worlds.gd")
		if scenario == "stress_city":
			stress.grow_city(sess, String(_args.get("people", "1500")).to_int())
		elif scenario == "stress_war":
			SettlementPlanner.place_starter_village(sess, sess.world.settlements[0].id)
			stress.raise_wars(sess, 6)
			sess.advance_days(20)
	if _args.has("event"):
		# for screenshots and for trying a single event: put it in front of the king right away
		var wanted := Events.event(StringName(_args["event"]))
		if not wanted.is_empty() and sess.world.player():
			EventSystem.fire(sess, sess.world.player(), wanted, sess.world.day)
	if _args.has("days"):
		sess.advance_days(String(_args["days"]).to_int())
	if _args.has("hours"):
		for i in String(_args["hours"]).to_int():
			sess.step_tick()

	if _args.has("save-to"):
		SaveSystem.save_to_file(sess, String(_args["save-to"]), "scenario")   # see --kd-load
	camera.world_view = world_view
	camera.world_bounds = Rect2(Vector2.ZERO, WorldConstants.world_size())
	var cam := BootArgs.camera_from(_args)
	var cam_arg := String(_args.get("camera", ""))
	if (cam_arg == "" or cam_arg.begins_with("settlement")) and not sess.world.settlements.is_empty():
		# the game opens on the king's settlement: the kingdom is born here
		var zoom := cam_arg.get_slice(",", 1).to_float() if cam_arg.contains(",") else 0.35
		cam = {"pos": sess.world.settlements[0].center, "mpp": zoom}
	if String(_args.get("camera", "")).begins_with("player") and sess.world.player():
		var zoom := String(_args["camera"]).get_slice(",", 1).to_float()
		cam = {"pos": WorldData.get_instance().province_geo(sess.world.player().capital).center, "mpp": zoom if zoom > 0.0 else 4.0}
	if cam_arg.begins_with("home,") and not sess.world.settlements.is_empty():
		# home,dx,dy,mpp: a fixed spot relative to the player's settlement (the standard screenshots: the river,
		# the wood, the fields always framed the same way)
		var parts := cam_arg.split(",")
		cam = {"pos": sess.world.settlements[0].center + Vector2(parts[1].to_float(), parts[2].to_float()),
			"mpp": parts[3].to_float() if parts.size() > 3 else 1.0}
	if cam_arg.begins_with("army"):
		# screenshots of the host itself: the first army of the crown
		var zoom := cam_arg.get_slice(",", 1).to_float() if cam_arg.contains(",") else 0.2
		for a in sess.world.armies:
			if a.kingdom == sess.world.player_kingdom:
				cam = {"pos": a.pos, "mpp": zoom}
				break
	if cam.is_empty():
		camera.focus_on(WorldConstants.world_size() * 0.5, 62.0, true)
	else:
		camera.focus_on(cam["pos"], cam["mpp"], true)

	if _args.has("mapmode"):
		($MapModeController as MapModeController).set_mode(StringName(_args["mapmode"]))
	if _args.has("select"):
		var target := String(_args["select"])
		if target.begins_with("building:"):
			($MapInteraction as MapInteraction).select_building(target.get_slice(":", 1).to_int())
			target = ""
		if target != "":
			var pid := sess.world.player().capital if target == "player" else target.to_int()
			($MapInteraction as MapInteraction).select(pid)
	if _args.has("hide-debug"):
		debug_overlay.visible = false
	if _args.has("screenshot"):
		($MapInteraction as MapInteraction).hover_enabled = false
		_frames_left = String(_args.get("frames", "30")).to_int()
	if _args.has("hide-layers"):
		# profiling: --kd-hide-layers=VegetationLayer,SettlementMarks takes those layers out of the picture
		for n: String in String(_args["hide-layers"]).split(","):
			var layer := world_view.get_node_or_null(n)
			if layer:
				layer.process_mode = Node.PROCESS_MODE_DISABLED
				(layer as CanvasItem).visible = false
	if _args.has("benchmark"):
		_bench_total = String(_args["benchmark"]).to_float()
		_bench_active = true


## The coronation scenario: the first rooted family is chosen, its eldest adult crowned.
func _crown_first_family() -> void:
	if not Session.has_game():
		return
	var sess := Session.current
	var k := sess.world.player()
	var home := sess.world.settlements[0]
	for f in FamilySystem.consolidated_families(sess.world, home):
		var who := CourtSystem.eligible_rulers(sess.world, f)
		if not who.is_empty():
			var res := sess.submit(FoundMonarchyCommand.create(k.id, f.id, who[0].id))
			if not res.success:
				push_warning("coronation scenario: %s" % res.reason)
			return


# --- benchmark: flies the camera over the continent through every zoom band and reports fps ---
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
	var t := (_bench_time - 1.0) / _bench_total
	if t >= 1.0:
		var lines: PackedStringArray = []
		for k in _bench_samples.keys():
			var s: Array = _bench_samples[k]
			lines.append("%s: %.1f fps avg (%d frames)" % [k, s[1] / maxf(s[0], 0.001), int(s[1])])
		print("[KD:benchmark] avg %.1f fps, worst frame %.1f ms | %s" % [_bench_frames / _bench_total, _bench_worst * 1000.0, " | ".join(lines)])
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
		_bench_worst_at = "t=%.2fs mpp=%.1f day=%d" % [_bench_time, camera.meters_per_pixel(), Session.current.world.day]
	_bench_worst = maxf(_bench_worst, delta)
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_bench_draws += draws
	if draws > _bench_draws_max:
		_bench_draws_max_at = "t=%.2fs mpp=%.1f" % [_bench_time, camera.meters_per_pixel()]
	_bench_draws_max = maxf(_bench_draws_max, draws)
	_bench_objects_max = maxf(_bench_objects_max, Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var size := WorldConstants.world_size()
	var pos := Vector2(lerpf(size.x * 0.25, size.x * 0.75, t), size.y * (0.45 + 0.1 * sin(t * TAU)))
	var mpp := exp(lerpf(log(60.0), log(0.25), absf(sin(t * PI * 1.5))))
	if _args.has("bench-home") and not Session.current.world.settlements.is_empty():
		# over the player's own settlement: where the houses, the fields, the people and the woods all are
		var home := Session.current.world.settlements[0].center
		pos = home + Vector2(cos(t * TAU), sin(t * TAU)) * 180.0
		mpp = exp(lerpf(log(40.0), log(0.2), absf(sin(t * PI * 1.5))))
	camera.focus_on(pos, mpp, true)
	var band := "far>20" if mpp > 20.0 else ("strategic 5-20" if mpp > 5.0 else ("local 1-5" if mpp > 1.0 else "close<1"))
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

