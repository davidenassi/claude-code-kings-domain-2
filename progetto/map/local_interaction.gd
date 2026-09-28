class_name LocalInteraction
extends Node
## Mouse on the map of the valley (Rebirth, Phase 1): a click picks a building (its inspector opens) or a host
## standing in the valley; right/middle drag pans the camera. Provinces are not chosen here: they belong to the
## map of the world. Silent while the build mode is active.

signal building_selected(building_id: int)
signal army_selected(army_id: int)

const CLICK_SLOP_PX := 6.0

@export var camera_path: NodePath
@export var build_path: NodePath

var _camera: WorldCamera
var _build: BuildController
var _press_pos := Vector2.INF
var selected_building := -1


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	_build = get_node_or_null(build_path) as BuildController
	EventBus.building_removed.connect(func(id: int) -> void:
		if id == selected_building:
			select_building(-1))


func building_under(screen_pos: Vector2) -> int:
	if _camera == null or not Session.has_game():
		return -1
	var wp := _camera.screen_to_world(screen_pos)
	var slop := _camera.meters_per_pixel() * 4.0
	for b: BuildingState in Session.current.world.buildings.values():
		if b.covers(wp, slop):
			return b.id
	return -1


## A host standing in the valley under the cursor, if the player may see it.
func army_under(screen_pos: Vector2) -> int:
	if _camera == null or not Session.has_game():
		return -1
	var world := Session.current.world
	var me := world.player()
	if me == null:
		return -1
	var wp := _camera.screen_to_world(screen_pos)
	var best := -1
	var best_d := _camera.meters_per_pixel() * 26.0
	for a in Military.visible_armies(world, me.id):
		var d := world.global_to_local(ArmyLayer.army_position(Session.current, a)).distance_to(wp)
		if d < best_d:
			best_d = d
			best = a.id
	return best


func select_building(building_id: int) -> void:
	selected_building = building_id
	building_selected.emit(building_id)


func _unhandled_input(event: InputEvent) -> void:
	if _build and _build.active():
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press_pos = mb.position
		elif _press_pos != Vector2.INF and mb.position.distance_to(_press_pos) <= CLICK_SLOP_PX:
			_press_pos = Vector2.INF
			var aid := army_under(mb.position)
			if aid >= 0:
				army_selected.emit(aid)
			else:
				select_building(building_under(mb.position))
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"kd_cancel") and selected_building >= 0:
		select_building(-1)
		get_viewport().set_input_as_handled()
