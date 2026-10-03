extends Camera2D
## Valley camera: smooth exponential zoom towards the cursor, keyboard / drag panning, bounds.
##
## zoom 1.0 = closest (32 px per metre: citizens and building details)
## zoom ~0.25 = villages and districts,  zoom ~0.02 = the whole valley.

signal zoom_changed(value: float)

@export var min_zoom := 0.02
@export var max_zoom := 1.0
@export var zoom_step := 1.18
@export var zoom_smooth := 10.0
@export var pan_speed := 900.0          # screen px per second
@export var pan_smooth := 12.0

var target_zoom := 0.1
var target_pos := Vector2.ZERO
var bounds := Rect2()
var _dragging := false
var _zoom_anchor_screen := Vector2.ZERO
var _zoom_anchor_world := Vector2.ZERO
var _anchor_active := false


func _ready() -> void:
	bounds = Proj.terrain_rect()
	min_zoom = max(min_zoom, get_viewport_rect().size.x / bounds.size.x)
	target_pos = position
	target_zoom = zoom.x
	_publish()


func jump_to(world_pos: Vector2, z: float) -> void:
	target_zoom = clampf(z, min_zoom, max_zoom)
	zoom = Vector2.ONE * target_zoom
	target_pos = _clamp_pos(world_pos, target_zoom)
	position = target_pos
	_anchor_active = false
	_publish()


func jump_to_ground(x_m: float, y_m: float, z: float) -> void:
	jump_to(Proj.project(x_m, y_m), z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var f := zoom_step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / zoom_step
			target_zoom = clampf(target_zoom * f, min_zoom, max_zoom)
			_zoom_anchor_screen = mb.position
			_zoom_anchor_world = get_canvas_transform().affine_inverse() * mb.position
			_anchor_active = true
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		target_pos -= mm.relative / zoom.x
		position = target_pos
		_anchor_active = false


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if dir != Vector2.ZERO:
		target_pos += dir.normalized() * pan_speed * delta / zoom.x
		_anchor_active = false

	var z := zoom.x
	var nz := exp(lerpf(log(z), log(target_zoom), 1.0 - exp(-zoom_smooth * delta)))
	if abs(nz - target_zoom) < 0.0005 * target_zoom:
		nz = target_zoom
	if nz != z:
		zoom = Vector2.ONE * nz
		if _anchor_active:
			# keep the world point under the cursor fixed while zooming
			var vp := get_viewport_rect().size
			target_pos = _zoom_anchor_world - (_zoom_anchor_screen - vp * 0.5) / nz
			position = target_pos
		_publish()
	target_pos = _clamp_pos(target_pos, nz)
	position = position.lerp(target_pos, 1.0 - exp(-pan_smooth * delta))


func _clamp_pos(p: Vector2, z: float) -> Vector2:
	var half := get_viewport_rect().size * 0.5 / z
	var r := bounds
	var out := p
	out.x = r.get_center().x if half.x * 2.0 >= r.size.x else clampf(p.x, r.position.x + half.x, r.end.x - half.x)
	out.y = r.get_center().y if half.y * 2.0 >= r.size.y else clampf(p.y, r.position.y + half.y, r.end.y - half.y)
	return out


func _publish() -> void:
	RenderingServer.global_shader_parameter_set("cam_zoom", zoom.x)
	zoom_changed.emit(zoom.x)
