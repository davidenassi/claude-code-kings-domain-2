class_name TerrainLayer
extends Node2D
## Draws the whole visible terrain with a single quad and the terrain shader.
## The node sits at a snapped position near the camera so local vertex coordinates stay small.

const SNAP_M := 256.0
const NOISE_TEXTURE := "res://assets/environment/terrain/noise_tile.png"
const STYLE_PATH := "res://data/defs/map_style.json"

@export var camera_path: NodePath
## Which map this terrain belongs to (MapSpace.GLOBAL: the continent; MapSpace.LOCAL: the valley of the homeland).
@export var space: StringName = MapSpace.GLOBAL

var _camera: WorldCamera
var _material: ShaderMaterial
var _rect: Rect2 = Rect2()
var _data: WorldData


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/terrain.gdshader")
	material = _material
	_use(MapSpace.data(space))
	if MapSpace.is_local(space):
		# another campaign is another valley
		EventBus.session_started.connect(func(_s: GameSession) -> void: _use(MapSpace.data(space)))
		EventBus.session_loaded.connect(func(_s: GameSession) -> void: _use(MapSpace.data(space)))


func _use(data: WorldData) -> void:
	if data == null or data == _data:
		return
	_data = data
	_setup_uniforms()
	queue_redraw()


func _setup_uniforms() -> void:
	_material.set_shader_parameter("world_size", _data.size_m)
	_material.set_shader_parameter("height_tex", _data.texture(&"height"))
	_material.set_shader_parameter("biome_tex", _data.texture(&"biome"))
	_material.set_shader_parameter("forest_tex", _data.texture(&"canopy"))
	_material.set_shader_parameter("moisture_tex", _data.texture(&"moisture"))
	_material.set_shader_parameter("coast_tex", _data.texture(&"coast"))
	_material.set_shader_parameter("water_tex", _data.texture(&"water"))
	_material.set_shader_parameter("albedo_far_tex", _data.texture(&"albedo_far"))
	_material.set_shader_parameter("noise_tex", load(NOISE_TEXTURE))
	_material.set_shader_parameter("palette_tex", _build_palette())
	_material.set_shader_parameter("province_tex", _data.texture(&"province"))
	apply_style(_material, Defs.read_json(STYLE_PATH))
	# a generated homeland has relief fine enough for cliffs and scree (0 on the continent and on crops)
	_material.set_shader_parameter("slope_rock", 0.85 if _data.designed_woods else 0.0)
	if _data.designed_woods:
		_material.set_shader_parameter("relief", 0.62)   # the rim of a valley is read by its light and shade


## Shared colour rules (data/defs/map_style.json) -> shader uniforms of the same name.
static func apply_style(mat: ShaderMaterial, style: Variant) -> void:
	if not (style is Dictionary):
		return
	for key: String in (style as Dictionary).keys():
		var v: Variant = style[key]
		if v is float or v is int:
			mat.set_shader_parameter(key, float(v))
		elif v is Array and (v as Array).size() == 3:
			mat.set_shader_parameter(key, Vector3(float(v[0]), float(v[1]), float(v[2])))


## Map mode overlay: per-province colour lookup (x = province id) and its maximum opacity.
func set_overlay(lookup: Texture2D, strength: float, fade_mpp: Vector2 = Vector2.ZERO) -> void:
	_material.set_shader_parameter("overlay_fade_mpp", fade_mpp)
	_material.set_shader_parameter("overlay_tex", lookup)
	_material.set_shader_parameter("overlay_strength", strength if lookup else 0.0)


func set_selected_province(province_id: int) -> void:
	_material.set_shader_parameter("selected_id", province_id)


func _build_palette() -> ImageTexture:
	var img := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	for b: BiomeDef in Defs.all("biomes"):
		img.set_pixel(b.index, 0, b.color)
	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> void:
	if _camera == null or _data == null:
		return
	var view := _camera.visible_world_rect()
	var center := view.get_center().snapped(Vector2(SNAP_M, SNAP_M))
	var margin := view.size * 0.15 + Vector2(SNAP_M, SNAP_M) * 2.0
	var local_rect := Rect2(view.position - center - margin, view.size + margin * 2.0)
	if center != position:
		position = center
	# the painted noises are read in the continent's metres: a valley cut out of it keeps the same brush strokes
	var brush := center + _data.feature_origin
	var origin_mod := Vector2(fposmod(brush.x, 1024.0), fposmod(brush.y, 1024.0))
	_material.set_shader_parameter("node_origin", center)
	_material.set_shader_parameter("origin_mod", origin_mod)
	_material.set_shader_parameter("mpp", _camera.meters_per_pixel())
	if not local_rect.encloses(_rect) or local_rect.size.x < _rect.size.x * 0.5 or not _rect.encloses(Rect2(view.position - center, view.size)):
		_rect = local_rect
		queue_redraw()


func _draw() -> void:
	draw_rect(_rect, Color.WHITE)

