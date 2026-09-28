class_name BorderLayer
extends Node2D
## Province lines and realm borders, drawn over the illustrated map at constant screen width.
## Hierarchy: kingdom borders (light halo, ink line in the owner's dark colour, wide soft colour band on each owned
## side) > lordship/settlement borders (same, thinner) > province lines (thin, tinted by the owner inside a realm,
## faded out at continental zoom). Everything is rebuilt when ownership changes.

const HALO := Color(0.96, 0.92, 0.80, 0.30)
const NEUTRAL_INK := Color(0.20, 0.14, 0.09, 0.85)
const PROVINCE_FREE := Color(0.30, 0.22, 0.14, 0.24)
const PROVINCE_LINE_PX := 1.0
const PROVINCE_FADE_MPP := Vector4(0.8, 1.6, 30.0, 48.0)  # fade in from x to y, fade out from z to w
## [line px, halo px, band px, band alpha] by rank: settlement, lordship, kingdom
const RANK_STYLE := [[1.4, 3.2, 7.0, 0.50], [1.5, 3.4, 8.0, 0.52], [2.1, 4.4, 11.0, 0.58]]

@export var camera_path: NodePath

var _camera: WorldCamera
var _wd: WorldData
var _province_lines: MeshInstance2D
var _realm_borders: MeshInstance2D
var _province_mat: ShaderMaterial
var _realm_mat: ShaderMaterial
var _normals: Array[PackedVector2Array] = []
var _dirty := true
var realm_segments := 0


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	_wd = WorldData.get_instance()
	var shader: Shader = load("res://shaders/border.gdshader")
	_province_mat = ShaderMaterial.new()
	_province_mat.shader = shader
	_realm_mat = ShaderMaterial.new()
	_realm_mat.shader = shader
	_province_lines = MeshInstance2D.new()
	_province_lines.name = "ProvinceLines"
	_province_lines.material = _province_mat
	add_child(_province_lines)
	_realm_borders = MeshInstance2D.new()
	_realm_borders.name = "RealmBorders"
	_realm_borders.material = _realm_mat
	add_child(_realm_borders)
	for b in _wd.borders:
		_normals.append(BorderMesh.vertex_normals(b["points"]))
	EventBus.province_owner_changed.connect(func(_p: int, _o: int, _n: int, _r: StringName) -> void: _dirty = true)
	EventBus.session_started.connect(func(_s: GameSession) -> void: _dirty = true)
	EventBus.session_loaded.connect(func(_s: GameSession) -> void: _dirty = true)


static func ink_of(k: KingdomState) -> Color:
	return Color(k.color.darkened(0.45), 0.95)


static func band_of(k: KingdomState, alpha: float) -> Color:
	return Color(k.color.lightened(0.08), alpha)


func rebuild(world: WorldState) -> void:
	var lines := BorderMesh.new()
	var realms := BorderMesh.new()
	realm_segments = 0
	for i in _wd.borders.size():
		var b: Dictionary = _wd.borders[i]
		var a: int = b["a"]
		var c: int = b["b"]
		var pts: PackedVector2Array = b["points"]
		var ka := world.owner_of(a)
		var kc := world.owner_of(c)
		if BorderClassifier.classify(world, a, c) != BorderClassifier.REALM:
			var col := PROVINCE_FREE if ka == null else Color(ka.color.darkened(0.5), 0.34)
			lines.add_line(pts, _normals[i], col, PROVINCE_LINE_PX)
			continue
		realm_segments += 1
		var rank := maxi(int(ka.rank) if ka else 0, int(kc.rank) if kc else 0)
		var style: Array = RANK_STYLE[rank]
		var side_a := float(b["a_side"])
		realms.add_line(pts, _normals[i], HALO, float(style[1]))
		if ka:
			realms.add_soft_band(pts, _normals[i], side_a, band_of(ka, float(style[3])), float(style[2]))
		if kc:
			realms.add_soft_band(pts, _normals[i], -side_a, band_of(kc, float(style[3])), float(style[2]))
		var ink := NEUTRAL_INK
		if ka == null or kc == null:
			ink = ink_of(ka if ka else kc)
		realms.add_line(pts, _normals[i], ink, float(style[0]))
	_province_lines.mesh = lines.commit()
	_realm_borders.mesh = realms.commit()


func _process(_delta: float) -> void:
	if _dirty and Session.has_game():
		_dirty = false
		rebuild(Session.current.world)
	if _camera == null:
		return
	var mpp := _camera.meters_per_pixel()
	_province_mat.set_shader_parameter("mpp", mpp)
	_realm_mat.set_shader_parameter("mpp", mpp)
	var f := smoothstep(PROVINCE_FADE_MPP.x, PROVINCE_FADE_MPP.y, mpp) * (1.0 - smoothstep(PROVINCE_FADE_MPP.z, PROVINCE_FADE_MPP.w, mpp))
	_province_mat.set_shader_parameter("fade", f)
	_province_lines.visible = f > 0.001

