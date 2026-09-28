class_name MapInteraction
extends Node
## Mouse on the map: hover and click select provinces, or buildings when zoomed in close enough to see them
## (left button; right/middle drag pans the camera). Silent while the build mode is active.

signal province_selected(province_id: int)
signal army_selected(army_id: int)
signal building_selected(building_id: int)

const BUILDING_PICK_MPP := 14.0

const CLICK_SLOP_PX := 6.0

@export var camera_path: NodePath
@export var selection_path: NodePath
@export var terrain_path: NodePath
@export var build_path: NodePath

var _camera: WorldCamera
var _selection: SelectionLayer
var _terrain: TerrainLayer
var _wd: WorldData
var _press_pos := Vector2.INF
## Army waiting for a destination (-1 = none).
var army_order: int = -1
var selected := -1
var selected_building := -1
var _build: BuildController
## Off for automated screenshots, where the OS cursor position is meaningless.
var hover_enabled := true


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	_selection = get_node_or_null(selection_path) as SelectionLayer
	_terrain = get_node_or_null(terrain_path) as TerrainLayer
	_build = get_node_or_null(build_path) as BuildController
	EventBus.building_removed.connect(func(id: int) -> void:
		if id == selected_building:
			select_building(-1))
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


func building_under(screen_pos: Vector2) -> int:
	if _camera == null or not Session.has_game() or _camera.meters_per_pixel() > BUILDING_PICK_MPP:
		return -1
	var wp := _camera.screen_to_world(screen_pos)
	var slop := _camera.meters_per_pixel() * 4.0
	for b: BuildingState in Session.current.world.buildings.values():
		if b.covers(wp, slop):
			return b.id
	return -1


func select_building(building_id: int) -> void:
	selected_building = building_id
	building_selected.emit(building_id)


func select(province_id: int) -> void:
	selected = province_id
	if _selection:
		_selection.set_selected(province_id)
	if _terrain:
		_terrain.set_selected_province(province_id)
	province_selected.emit(province_id)


func _unhandled_input(event: InputEvent) -> void:
	if _build and _build.active():
		return
	if event is InputEventMouseMotion:
		if _selection and hover_enabled:
			_selection.set_hovered(province_under((event as InputEventMouseMotion).position))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
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
			var bid := building_under(mb.position)
			if bid >= 0:
				select(-1)
				select_building(bid)
			else:
				select_building(-1)
				select(province_under(mb.position))
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"kd_cancel") and (selected >= 0 or selected_building >= 0):
		select(-1)
		select_building(-1)
		get_viewport().set_input_as_handled()

