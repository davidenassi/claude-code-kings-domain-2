extends Polygon2D
## Full-screen quad that follows the camera and multiplies soft cloud shadows over the world.

func _ready() -> void:
	var m := ShaderMaterial.new()
	m.shader = preload("res://valley/fx/cloud_shadows.gdshader")
	material = m


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var half := get_viewport_rect().size * 0.5 / cam.zoom.x * 1.05
	var c := cam.get_screen_center_position()
	polygon = PackedVector2Array([c - half, Vector2(c.x + half.x, c.y - half.y), c + half, Vector2(c.x - half.x, c.y + half.y)])
	visible = cam.zoom.x < 0.4
