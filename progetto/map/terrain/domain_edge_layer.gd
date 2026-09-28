class_name DomainEdgeLayer
extends Node2D
## The rim of the valley on the local map (Rebirth, Phase 1): mist and clouds over the edge of the homeland and
## beyond it, where the world is not known yet (Phase 8 turns this into real exploration). One quad over the view,
## drawn by shaders/domain_edge.gdshader; nothing past the valley is ever drawn as map.

const SNAP_M := 256.0
const NOISE_TEXTURE := "res://assets/environment/terrain/noise_tile.png"

@export var camera_path: NodePath

var _camera: WorldCamera
var _material: ShaderMaterial
var _rect := Rect2()
var _time := 0.0


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/domain_edge.gdshader")
	_material.set_shader_parameter("noise_tex", load(NOISE_TEXTURE))
	material = _material


func _process(delta: float) -> void:
	if _camera == null or not Session.has_game() or Session.current.world.domain == null:
		visible = false
		return
	visible = true
	_time += delta
	var d := Session.current.world.domain
	_material.set_shader_parameter("domain_size", d.size_m)
	_material.set_shader_parameter("drift", _time)
	var view := _camera.visible_world_rect()
	var center := view.get_center().snapped(Vector2(SNAP_M, SNAP_M))
	if center != position:
		position = center
	_material.set_shader_parameter("node_origin", center)
	var local_rect := Rect2(view.position - center, view.size).grow(SNAP_M * 2.0)
	if not _rect.encloses(Rect2(view.position - center, view.size)) or local_rect.size.x < _rect.size.x * 0.5:
		_rect = local_rect
		queue_redraw()


func _draw() -> void:
	draw_rect(_rect, Color.WHITE)
