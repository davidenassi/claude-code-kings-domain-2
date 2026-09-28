class_name WorldCamera
extends Camera2D
## Continuous-zoom camera over one map. Zoom is expressed in metres per screen pixel.
## Rebirth: each map has its own camera and its own limits (LocalView: from the people to the whole valley, never
## the continent; GlobalView: from the provinces to the continent, never the houses). With `keep_view_inside` the
## whole visible rectangle stays inside `world_bounds` (plus `edge_margin_m`), not only its centre.
## Wheel zooms towards the cursor; WASD/arrows pan; middle or right mouse button drags.
## Positions exposed by this class are WORLD coordinates; the node itself is placed relative to the
## WorldView floating origin.

signal view_changed
## The player asked for more distance than this map allows (the local map never becomes the world map).
signal zoom_out_blocked

@export var min_meters_per_pixel: float = 0.04
@export var max_meters_per_pixel: float = 80.0
@export var wheel_step: float = 1.18
@export var zoom_smoothing: float = 14.0
@export var pan_speed_screens_per_second: float = 0.9

## World rectangle the camera centre is kept inside (metres).
var world_bounds: Rect2 = Rect2(0, 0, 112000, 72000)
var world_view: WorldView = null
## Keep the whole view inside world_bounds (grown by edge_margin_m) instead of only its centre.
var keep_view_inside := false
var edge_margin_m := 0.0


## The zoom range of this map (metres per pixel).
func set_limits(min_mpp: float, max_mpp: float) -> void:
	min_meters_per_pixel = min_mpp
	max_meters_per_pixel = max_mpp
	_target_mpp = clampf(_target_mpp, min_mpp, max_mpp)
	_mpp = clampf(_mpp, min_mpp, max_mpp)

var _target_mpp: float = 30.0
var _mpp: float = 30.0
var _pos: Vector2 = Vector2.ZERO
var _target_pos: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _zoom_anchor_world: Vector2 = Vector2.INF
var _zoom_anchor_screen: Vector2 = Vector2.ZERO


func _ready() -> void:
	_apply()


func meters_per_pixel() -> float:
	return _mpp


func target_meters_per_pixel() -> float:
	return _target_mpp


func world_position() -> Vector2:
	return _pos


func focus_on(world_pos: Vector2, mpp: float = -1.0, instant: bool = false) -> void:
	_target_pos = world_pos
	if mpp > 0.0:
		_target_mpp = clampf(mpp, min_meters_per_pixel, max_meters_per_pixel)
	_zoom_anchor_world = Vector2.INF
	if instant:
		_mpp = _target_mpp
		_target_pos = _clamp_center(_target_pos)
		_pos = _target_pos
		_apply()
		view_changed.emit()


## Visible rectangle in world coordinates.
func visible_world_rect() -> Rect2:
	var vp := get_viewport_rect().size * _mpp
	return Rect2(_pos - vp * 0.5, vp)


func screen_to_world(screen_pos: Vector2) -> Vector2:
	var vp_size := get_viewport_rect().size
	return _pos + (screen_pos - vp_size * 0.5) * _mpp


func world_to_screen(world_pos: Vector2) -> Vector2:
	var vp_size := get_viewport_rect().size
	return (world_pos - _pos) / _mpp + vp_size * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var factor := 1.0 / wheel_step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else wheel_step
			if factor > 1.0 and _target_mpp >= max_meters_per_pixel * 0.999:
				zoom_out_blocked.emit()
			_zoom_by(factor, mb.position)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_target_pos -= mm.relative * _mpp
		_pos = _target_pos
		_zoom_anchor_world = Vector2.INF
		_apply()
		view_changed.emit()
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		_zoom_by(1.0 / g.factor, g.position)


func _zoom_by(factor: float, screen_pos: Vector2) -> void:
	_target_mpp = clampf(_target_mpp * factor, min_meters_per_pixel, max_meters_per_pixel)
	_zoom_anchor_screen = screen_pos
	_zoom_anchor_world = screen_to_world(screen_pos)


func _process(delta: float) -> void:
	var pan := Vector2(
		Input.get_axis(&"kd_pan_left", &"kd_pan_right"),
		Input.get_axis(&"kd_pan_up", &"kd_pan_down"))
	if Input.is_action_pressed(&"kd_zoom_in"):
		_zoom_by(pow(1.0 / wheel_step, delta * 8.0), get_viewport_rect().size * 0.5)
	if Input.is_action_pressed(&"kd_zoom_out"):
		_zoom_by(pow(wheel_step, delta * 8.0), get_viewport_rect().size * 0.5)
	var moved := false
	if pan != Vector2.ZERO:
		var screen := get_viewport_rect().size
		_target_pos += pan.normalized() * screen.length() * 0.5 * pan_speed_screens_per_second * _mpp * delta
		_zoom_anchor_world = Vector2.INF
		moved = true

	if not is_equal_approx(_mpp, _target_mpp):
		var t := 1.0 - exp(-zoom_smoothing * delta)
		_mpp = exp(lerpf(log(_mpp), log(_target_mpp), t))
		if absf(_mpp - _target_mpp) / _target_mpp < 0.002:
			_mpp = _target_mpp
		if _zoom_anchor_world != Vector2.INF:
			# keep the world point under the cursor fixed while zooming
			var vp_size := get_viewport_rect().size
			_target_pos = _zoom_anchor_world - (_zoom_anchor_screen - vp_size * 0.5) * _mpp
			_pos = _target_pos
		moved = true

	if _pos != _target_pos:
		var tp := 1.0 - exp(-zoom_smoothing * delta)
		_pos = _pos.lerp(_target_pos, tp)
		if _pos.distance_to(_target_pos) < _mpp * 0.25:
			_pos = _target_pos
		moved = true

	var clamped := _clamp_center(_pos)
	if clamped != _pos:
		_pos = clamped
		_target_pos = _clamp_center(_target_pos)
	if moved:
		_apply()
		view_changed.emit()


## Where the centre may be: inside the bounds, or — keeping the view inside — far enough from their edges.
func _clamp_center(p: Vector2) -> Vector2:
	if not keep_view_inside:
		return p.clamp(world_bounds.position, world_bounds.end)
	var half := get_viewport_rect().size * _mpp * 0.5
	var area := world_bounds.grow(edge_margin_m)
	var out := p
	for axis in 2:
		var lo := area.position[axis] + half[axis]
		var hi := area.end[axis] - half[axis]
		out[axis] = (area.position[axis] + area.end[axis]) * 0.5 if lo > hi else clampf(p[axis], lo, hi)
	return out


func _apply() -> void:
	var z := 1.0 / _mpp
	zoom = Vector2(z, z)
	if world_view != null:
		world_view.track(_pos)
		global_position = _pos - world_view.origin
	else:
		global_position = _pos

