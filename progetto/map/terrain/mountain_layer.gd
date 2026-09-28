class_name MountainLayer
extends MultiMeshInstance2D
## Illustrated mountains and hills: prerendered sprites (tools/art/draw_mountains.py) placed on the official map by
## tools/worldgen/place_mountains.py. A few hundred instances in one y-sorted MultiMesh (a single draw call).
## Up close the sprites fade out and the painted terrain relief takes over.

const ATLAS_DIR := "res://assets/environment/mountains"
const PLACEMENT := "res://data/world/mountains.json"
const FADE_MPP := Vector2(5.0, 8.0)   # fully hidden below x, fully visible above y

@export var camera_path: NodePath
## Which map the peaks belong to (Rebirth): the continent's ranges, or the rim of a generated homeland
## (DomainData meta "mountains", in the valley's metres, seen from nearer: they fade out sooner).
@export var space: StringName = MapSpace.GLOBAL

var _camera: WorldCamera
var _fade_mpp := FADE_MPP
var _material: ShaderMaterial
var instance_total := 0


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	_build()
	if MapSpace.is_local(space):
		# another campaign is another valley, with its own rim
		EventBus.session_started.connect(func(_s: GameSession) -> void: _build())
		EventBus.session_loaded.connect(func(_s: GameSession) -> void: _build())


func _build() -> void:
	var meta: Variant = Defs.read_json(ATLAS_DIR + "/mountain_atlas.json")
	var placement: Variant = Defs.read_json(PLACEMENT)
	if MapSpace.is_local(space):
		var dd := MapSpace.data(space) as DomainData
		placement = {"items": dd.meta.get("mountains", [])} if dd else {"items": []}
		_fade_mpp = Vector2(2.2, 3.6)
	if not (meta is Dictionary and placement is Dictionary):
		KDLog.error("map", "MountainLayer: missing atlas or placement data")
		return
	texture = load(ATLAS_DIR + "/" + String(meta["atlas"]))
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/vegetation.gdshader")
		_material.set_shader_parameter("tone_amount", 0.0)
		material = _material
	multimesh = build_multimesh(meta, placement["items"])
	instance_total = multimesh.instance_count


static func build_multimesh(meta: Dictionary, items: Array) -> MultiMesh:
	var atlas_size := Vector2(float(meta["width"]), float(meta["height"]))
	var by_class := {}
	for s: Dictionary in meta["sprites"]:
		var key := String(s["class"])
		if not by_class.has(key):
			by_class[key] = []
		(by_class[key] as Array).append(s)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = VegetationLayer.make_quad()
	var valid: Array = []
	for it: Array in items:
		var variants: Array = by_class.get(String(it[3]), [])
		if not variants.is_empty():
			valid.append([it, variants[int(it[4]) % variants.size()]])
	# placement data is sorted by y, so later (nearer) mountains draw over farther ones
	mm.instance_count = valid.size()
	for k in valid.size():
		var it: Array = valid[k][0]
		var s: Dictionary = valid[k][1]
		var rect: Array = s["rect"]
		var size_rel: Array = s["size_rel"]
		var pv: Array = s["pivot"]
		var w_m := float(it[2])
		var size := Vector2(float(size_rel[0]), float(size_rel[1])) * w_m
		mm.set_instance_transform_2d(k, Transform2D(Vector2(size.x, 0), Vector2(0, size.y), Vector2(float(it[0]), float(it[1]))))
		var tint := fposmod(float(it[0]) * 0.00137 + float(it[1]) * 0.00071, 1.0)
		mm.set_instance_color(k, Color(float(pv[0]) / float(rect[2]), float(pv[1]) / float(rect[3]), tint, 1.0))
		mm.set_instance_custom_data(k, Color(float(rect[0]) / atlas_size.x, float(rect[1]) / atlas_size.y,
			float(rect[2]) / atlas_size.x, float(rect[3]) / atlas_size.y))
	return mm


func _process(_delta: float) -> void:
	if _camera == null or _material == null:
		return
	var fade := smoothstep(_fade_mpp.x, _fade_mpp.y, _camera.meters_per_pixel())
	visible = fade > 0.001
	_material.set_shader_parameter("fade", fade)

