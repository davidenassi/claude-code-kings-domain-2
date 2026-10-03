extends Node2D
## Plays a sequence of pre-rendered sprite frames (e.g. windmill sails) with their own anchors.
## The matching shadow frames are swapped on a twin sprite in the shadow layer.

var frames: Array = []            # [{tex, sh, anchor}]
var fps := 5.0
var z_off := 0.0
var x_off := 0.0
var body: Sprite2D
var shadow: Sprite2D
var _t := 0.0
var _last := -1


func setup(p_frames: Array, p_shadow: Sprite2D, altitude_px: float, offset_x := 0.0) -> void:
	frames = p_frames
	shadow = p_shadow
	z_off = altitude_px
	x_off = offset_x
	body = Sprite2D.new()
	body.centered = false
	add_child(body)
	_apply(0)


func _apply(i: int) -> void:
	var f: Dictionary = frames[i]
	body.texture = f["tex"]
	body.position = Vector2(x_off - f["anchor"].x, z_off - f["anchor"].y)
	if shadow:
		shadow.texture = f["sh"]
		shadow.global_position = global_position + body.position
	_last = i


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var i := int(_t * fps) % frames.size()
	if i != _last:
		_apply(i)
