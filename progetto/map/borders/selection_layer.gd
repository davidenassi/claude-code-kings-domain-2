class_name SelectionLayer
extends Node2D
## Outlines of the hovered and selected provinces (gold ink with a soft inner glow).

const SELECTED := Color(0.96, 0.80, 0.36, 0.95)
const HOVER := Color(1.0, 0.96, 0.84, 0.75)

@export var camera_path: NodePath

var _camera: WorldCamera
var _wd: WorldData
var _hover_mesh: MeshInstance2D
var _selected_mesh: MeshInstance2D
var _material: ShaderMaterial
var hovered := -1
var selected := -1


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	_wd = WorldData.get_instance()
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/border.gdshader")
	_hover_mesh = MeshInstance2D.new()
	_hover_mesh.material = _material
	add_child(_hover_mesh)
	_selected_mesh = MeshInstance2D.new()
	_selected_mesh.material = _material
	add_child(_selected_mesh)


func set_hovered(province_id: int) -> void:
	if province_id == hovered:
		return
	hovered = province_id
	_hover_mesh.mesh = outline_mesh(province_id, false) if province_id != selected else null


func set_selected(province_id: int) -> void:
	if province_id == selected:
		return
	selected = province_id
	_selected_mesh.mesh = outline_mesh(province_id, true)
	_hover_mesh.mesh = outline_mesh(hovered, false) if hovered != selected else null


## Selected: dark outline + gold line + soft gold glow inside. Hover: light line over a faint dark outline.
func outline_mesh(province_id: int, is_selected: bool) -> ArrayMesh:
	if province_id < 0 or not _wd.borders_by_province.has(province_id):
		return null
	var bm := BorderMesh.new()
	for bi in _wd.borders_by_province[province_id]:
		var b: Dictionary = _wd.borders[bi]
		var pts: PackedVector2Array = b["points"]
		var normals := BorderMesh.vertex_normals(pts)
		var side := float(b["a_side"]) if int(b["a"]) == province_id else -float(b["a_side"])
		if is_selected:
			bm.add_soft_band(pts, normals, side, Color(SELECTED, 0.42), 14.0)
			bm.add_line(pts, normals, Color(0.10, 0.06, 0.02, 0.6), 4.6)
			bm.add_line(pts, normals, SELECTED, 2.4)
		else:
			bm.add_line(pts, normals, Color(0.10, 0.06, 0.02, 0.28), 3.2)
			bm.add_line(pts, normals, HOVER, 1.5)
	return bm.commit()


func _process(_delta: float) -> void:
	if _camera:
		_material.set_shader_parameter("mpp", _camera.meters_per_pixel())

