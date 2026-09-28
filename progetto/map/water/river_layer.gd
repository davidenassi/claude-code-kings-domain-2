class_name RiverLayer
extends MeshInstance2D
## All rivers of the official map as one mesh of ribbons (see shaders/river.gdshader).

@export var camera_path: NodePath

var _camera: WorldCamera
var _material: ShaderMaterial


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/river.gdshader")
	material = _material
	mesh = build_mesh(WorldData.get_instance().rivers)


static func build_mesh(rivers: Array[Dictionary]) -> ArrayMesh:
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for r in rivers:
		var pts: PackedVector2Array = r["points"]
		var ws: PackedFloat32Array = r["widths"]
		var n := pts.size()
		if n < 2:
			continue
		var along := 0.0
		var base := verts.size()
		for i in n:
			var prev := pts[maxi(i - 1, 0)]
			var next := pts[mini(i + 1, n - 1)]
			var dir := (next - prev).normalized()
			var normal := Vector2(-dir.y, dir.x)
			if i > 0:
				along += pts[i].distance_to(pts[i - 1])
			var w := clampf(ws[i], 1.0, 254.0)
			# taper the first vertices so sources do not start with a blunt end
			if i < 3:
				w *= 0.4 + 0.2 * i
			var col := Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, w / 255.0, 1.0)
			for s in [-1.0, 1.0]:
				verts.append(pts[i])
				colors.append(col)
				uvs.append(Vector2(along, s))
		for i in n - 1:
			var a := base + i * 2
			indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _process(_delta: float) -> void:
	if _camera == null:
		return
	_material.set_shader_parameter("mpp", _camera.meters_per_pixel())

