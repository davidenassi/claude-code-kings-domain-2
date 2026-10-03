extends Node2D
## Cumulus clouds around the edges of the map (far view only, as in the illustrated valley reference):
## they frame the valley and fade out as the camera zooms in.

const FADE_START := 0.05
const FADE_END := 0.028


func _ready() -> void:
	z_index = 50
	var r: Rect2 = Proj.terrain_rect()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var texs := []
	for k in 6:
		var p := "res://assets/fx/cloud_%d.png" % k
		if ResourceLoader.exists(p):
			texs.append(load(p))
	if texs.is_empty():
		return
	var perim := 2.0 * (r.size.x + r.size.y)
	var n := 34
	for i in n:
		var t := (float(i) + rng.randf() * 0.6) / n * perim
		var pos: Vector2
		var inward: Vector2
		if t < r.size.x:
			pos = r.position + Vector2(t, 0)
			inward = Vector2(0, 1)
		elif t < r.size.x + r.size.y:
			pos = r.position + Vector2(r.size.x, t - r.size.x)
			inward = Vector2(-1, 0)
		elif t < 2.0 * r.size.x + r.size.y:
			pos = r.end - Vector2(t - r.size.x - r.size.y, 0)
			inward = Vector2(0, -1)
		else:
			pos = r.position + Vector2(0, r.size.y - (t - 2.0 * r.size.x - r.size.y))
			inward = Vector2(1, 0)
		var s := Sprite2D.new()
		s.texture = texs[rng.randi() % texs.size()]
		var sc := rng.randf_range(16.0, 30.0)
		s.scale = Vector2(sc, sc * rng.randf_range(0.8, 1.0))
		s.flip_h = rng.randf() < 0.5
		s.position = pos + inward * rng.randf_range(-2500.0, 6500.0)
		add_child(s)
	modulate.a = 0.0


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var z := cam.zoom.x
	modulate.a = clampf((FADE_START - z) / (FADE_START - FADE_END), 0.0, 1.0)
	visible = modulate.a > 0.01
