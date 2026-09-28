class_name MapInteraction
extends Node
## Mouse on the map of the world (Rebirth, Phase 1): hover and click select provinces and hosts, the next click
## after an order is the host's destination, a double click on the homeland goes back to the valley (left
## button; right/middle drag pans the camera). Buildings are not picked here: they live on the map of the valley
## (LocalInteraction).

signal province_selected(province_id: int)
signal army_selected(army_id: int)
## Double click on the player's own province: back to the valley.
signal home_requested

const CLICK_SLOP_PX := 6.0

@export var camera_path: NodePath
@export var selection_path: NodePath
@export var terrain_path: NodePath

var _camera: WorldCamera
var _selection: SelectionLayer
var _terrain: TerrainLayer
var _wd: WorldData
var _press_pos := Vector2.INF
## Army waiting for a destination (-1 = none).
var army_order: int = -1
var selected := -1
## Off for automated screenshots, where the OS cursor position is meaningless.
var hover_enabled := true


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	_selection = get_node_or_null(selection_path) as SelectionLayer
	_terrain = get_node_or_null(terrain_path) as TerrainLayer
	_wd = WorldData.get_instance()


## The army under the cursor, if the player may see it.
func army_under(screen_pos: Vector2) -> int:
	if _camera == null or not Session.has_game():
		return -1
	var world := Session.current.world
	var me := world.player()
	if me == null:
		return -1
	var wp := _camera.screen_to_world(screen_pos)
	var slop := _camera.meters_per_pixel() * 26.0
	var best := -1
	var best_d := slop
	for a in Military.visible_armies(world, me.id):
		var d := ArmyLayer.army_position(Session.current, a).distance_to(wp)
		if d < best_d:
			best_d = d
			best = a.id
	return best


## While an army waits for orders, the next click on the map is its destination.
func order_army(army_id: int) -> void:
	army_order = army_id


func province_under(screen_pos: Vector2) -> int:
	if _camera == null:
		return -1
	return _wd.province_at(_camera.screen_to_world(screen_pos))


func select(province_id: int) -> void:
	selected = province_id
	if _selection:
		_selection.set_selected(province_id)
	if _terrain:
		_terrain.set_selected_province(province_id)
	province_selected.emit(province_id)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _selection and hover_enabled:
			_selection.set_hovered(province_under((event as InputEventMouseMotion).position))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and mb.double_click and army_order < 0 and _is_home(province_under(mb.position)):
			home_requested.emit()
			get_viewport().set_input_as_handled()
			return
		if mb.pressed:
			_press_pos = mb.position
		elif _press_pos != Vector2.INF and mb.position.distance_to(_press_pos) <= CLICK_SLOP_PX:
			_press_pos = Vector2.INF
			if army_order >= 0:
				var target := province_under(mb.position)
				if target >= 0:
					Session.current.submit(MoveArmyCommand.create(army_order, target))
				army_order = -1
				get_viewport().set_input_as_handled()
				return
			var aid := army_under(mb.position)
			if aid >= 0:
				army_selected.emit(aid)
				get_viewport().set_input_as_handled()
				return
			select(province_under(mb.position))
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"kd_cancel") and selected >= 0:
		select(-1)
		get_viewport().set_input_as_handled()


## The province of the valley (the player's first land).
func _is_home(province_id: int) -> bool:
	if province_id < 0 or not Session.has_game():
		return false
	var d := Session.current.world.domain
	return d != null and d.home_province == province_id

