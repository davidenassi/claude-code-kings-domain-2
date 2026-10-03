extends RefCounted
## Builds the valley vegetation (trees, bushes, rocks) from pre-computed MultiMesh buffers.
## One MultiMeshInstance2D per 32 m strip in the y-sorted object layer (instances pre-sorted by
## depth) + a twin in the shadow layer that reuses the same buffer with the shadow atlas.

const BODY_SHADER := preload("res://valley/vegetation/sprite_instance.gdshader")
const SHADOW_SHADER := preload("res://valley/vegetation/shadow_instance.gdshader")
const DIR := "res://assets/vegetation/"

var meta: Dictionary
var quad: ArrayMesh
var body_mat: ShaderMaterial
var shadow_mat: ShaderMaterial
var body_nodes: Array[MultiMeshInstance2D] = []
var shadow_nodes: Array[MultiMeshInstance2D] = []


static func unit_quad() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func build(objects: Node2D, shadows: Node2D) -> void:
	var f := FileAccess.open("res://data/valley/vegetation.json", FileAccess.READ)
	if f == null:
		return
	meta = JSON.parse_string(f.get_as_text())
	quad = unit_quad()
	var atlas: Texture2D = load(DIR + meta["atlas"])
	var shadow_atlas: Texture2D = load(DIR + meta["shadow_atlas"])
	body_mat = ShaderMaterial.new()
	body_mat.shader = BODY_SHADER
	shadow_mat = ShaderMaterial.new()
	shadow_mat.shader = SHADOW_SHADER
	for s in meta["strips"]:
		var buf := FileAccess.get_file_as_bytes(DIR + String(s["file"])).to_float32_array()
		var count: int = s["count"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = count
		mm.buffer = buf
		var b := MultiMeshInstance2D.new()
		b.multimesh = mm
		b.texture = atlas
		b.material = body_mat
		b.position = Vector2(0.0, float(s["node_y"]))
		objects.add_child(b)
		body_nodes.append(b)
		var sh := MultiMeshInstance2D.new()
		sh.multimesh = mm
		sh.texture = shadow_atlas
		sh.material = shadow_mat
		sh.position = b.position
		shadows.add_child(sh)
		shadow_nodes.append(sh)
