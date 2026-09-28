class_name MapHud
extends CanvasLayer
## Screen-space layer of the map: names and shields, nothing else.
## Since Phase 12.5 the map modes live in the left column and the province inspector in the right one
## (`ui/shell/build_column.gd`), so this layer never covers the map with a bar of its own.

@export var camera_path: NodePath
@export var controller_path: NodePath
@export var interaction_path: NodePath

var labels: MapLabels


func _ready() -> void:
	layer = 10
	labels = MapLabels.new()
	labels.name = "MapLabels"
	labels.camera_path = get_node(camera_path).get_path() if has_node(camera_path) else NodePath()
	add_child(labels)

