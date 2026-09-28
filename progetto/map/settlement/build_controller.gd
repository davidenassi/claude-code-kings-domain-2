class_name BuildController
extends Node2D
## Build mode: a ghost of the chosen building follows the mouse (snapped to 1 m), green when it can stand there,
## red with the reason when it cannot. Left click opens the construction site (Shift keeps the mode on),
## right click or Esc leaves build mode. Lives inside WorldView so it draws in world coordinates.

signal mode_changed(def_id: StringName)
signal hint_changed(text: String, ok: bool, screen_pos: Vector2)

const CLICK_SLOP_PX := 6.0

@export var camera_path: NodePath

var def_id: StringName = &""
var _camera: WorldCamera
var _pos := Vector2.INF
var _check: Dictionary = {}
var _right_press := Vector2.INF
## Road mode: first end already chosen (INF while waiting for it).
var _road_start := Vector2.INF
var _atlas: Texture2D
var _sprites: Dictionary = {}
var _ppm := 8.0


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	var meta: Dictionary = Defs.read_json(SettlementLayer.ATLAS_DIR + "/building_atlas.json")
	_atlas = load(SettlementLayer.ATLAS_DIR + "/" + String(meta["atlas"]))
	_sprites = meta["sprites"]
	_ppm = float(meta.get("ppm", 8.0))
	EventBus.settlement_changed.connect(func(_id: int) -> void: _recheck())


func active() -> bool:
	return def_id != &""


func start(new_def: StringName) -> void:
	def_id = new_def
	_pos = Vector2.INF
	_road_start = Vector2.INF
	_check = {}
	mode_changed.emit(def_id)
	queue_redraw()


func stop() -> void:
	if def_id == &"":
		return
	def_id = &""
	_check = {}
	_road_start = Vector2.INF
	mode_changed.emit(def_id)
	hint_changed.emit("", true, Vector2.ZERO)
	queue_redraw()


func player_settlement() -> SettlementState:
	if not Session.has_game():
		return null
	var world := Session.current.world
	for s in world.settlements:
		if s.kingdom == world.player_kingdom:
			return s
	return null


func _recheck() -> void:
	if active() and _pos != Vector2.INF:
		_update(_pos, _camera.world_to_screen(_pos))


func is_road_mode() -> bool:
	var def := Defs.building(def_id)
	return def != null and def.is_line


func _update(world_pos: Vector2, screen_pos: Vector2) -> void:
	_pos = world_pos.snapped(Vector2.ONE)
	var s := player_settlement()
	var def := Defs.building(def_id)
	var text := ""
	if is_road_mode():
		if _road_start == Vector2.INF:
			_check = {"ok": true, "reason": "", "trees": 0, "rocks": 0}
			text = "Strada: clicca il punto di partenza"
		else:
			_check = Placement.check_road(Session.current.world, s, _road_start, _pos)
			text = "Strada di %d m" % int(_road_start.distance_to(_pos)) if bool(_check["ok"]) else String(_check["reason"])
			if bool(_check["ok"]) and int(_check["trees"]) > 0:
				text += " — alberi da abbattere: %d" % int(_check["trees"])
	else:
		_check = Placement.check(Session.current.world, s, def, _pos)
		if bool(_check["ok"]):
			text = def.display_name
			if int(_check["trees"]) > 0:
				text += " — alberi da abbattere: %d" % int(_check["trees"])
		else:
			text = String(_check["reason"])
	hint_changed.emit(text, bool(_check["ok"]), screen_pos)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not active() or not Session.has_game():
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_update(_camera.screen_to_world(mm.position), mm.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_update(_camera.screen_to_world(mb.position), mb.position)
			var s := player_settlement()
			if is_road_mode():
				if _road_start == Vector2.INF:
					_road_start = _pos
					_update(_camera.screen_to_world(mb.position), mb.position)
				else:
					var road := Session.current.submit(PlaceRoadCommand.create(s.id, _road_start, _pos))
					if road.success:
						# chain: the next stretch starts where this one ended
						_road_start = _pos if mb.shift_pressed else Vector2.INF
						if not mb.shift_pressed:
							stop()
					else:
						EventBus.notify("Non si può tracciare qui", road.reason, &"warning", _pos)
			else:
				var res := Session.current.submit(PlaceBuildingCommand.create(s.id, def_id, _pos))
				if res.success:
					if not mb.shift_pressed:
						stop()
				else:
					EventBus.notify("Non si può costruire qui", res.reason, &"warning", _pos)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_right_press = mb.position
			elif _right_press != Vector2.INF and mb.position.distance_to(_right_press) <= CLICK_SLOP_PX:
				if is_road_mode() and _road_start != Vector2.INF:
					_road_start = Vector2.INF   # cancel just the stretch being traced
					_update(_camera.screen_to_world(mb.position), mb.position)
				else:
					stop()
				get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"kd_cancel"):
		stop()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if not active() or _pos == Vector2.INF or _check.is_empty():
		return
	var def := Defs.building(def_id)
	var ok := bool(_check["ok"])
	if is_road_mode():
		var w := BuildingState.road_width()
		var col := Color(0.45, 0.85, 0.35) if ok else Color(0.9, 0.3, 0.2)
		if _road_start == Vector2.INF:
			draw_circle(_pos, w * 0.6, Color(col, 0.5))
		else:
			draw_line(_road_start, _pos, Color(col, 0.45), w)
			draw_circle(_road_start, w * 0.5, Color(col, 0.7))
			draw_circle(_pos, w * 0.5, Color(col, 0.7))
		return
	var rect := Rect2(_pos - def.footprint * 0.5, def.footprint)
	var col := Color(0.45, 0.85, 0.35) if ok else Color(0.9, 0.3, 0.2)
	draw_rect(rect, Color(col, 0.22))
	var s: Dictionary = _sprites.get(String(def.sprite if def.work_type() != &"farm" else &"farm_green"), {})
	if not s.is_empty():
		var r: Array = s["rect"]
		var pv: Array = s["pivot"]
		var src := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		draw_texture_rect_region(_atlas, Rect2(_pos - Vector2(float(pv[0]), float(pv[1])) / _ppm, src.size / _ppm), src,
			Color(1, 1, 1, 0.55) if ok else Color(1, 0.6, 0.6, 0.45))
	var w := maxf(_camera.meters_per_pixel() * 2.0, 0.15)
	draw_rect(rect, Color(col, 0.95), false, w)

