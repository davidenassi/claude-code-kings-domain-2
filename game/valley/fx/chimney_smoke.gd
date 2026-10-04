extends RefCounted
## Light chimney smoke (CPUParticles2D) for a share of the houses. Hidden when zoomed far out.

static var _puff: Texture2D


static func puff() -> Texture2D:
	if _puff == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.92, 0.92, 0.90, 0.55))
		g.set_color(1, Color(0.92, 0.92, 0.90, 0.0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 48
		t.height = 48
		_puff = t
	return _puff


static func make(pos: Vector2) -> Node2D:
	## A puff plume (smoke_plume.gd): the CPUParticles2D emitter below was never drawn by the
	## compatibility renderer in the captures, so smoke is now a small deterministic sprite loop.
	var plume: Node2D = preload("res://valley/fx/smoke_plume.gd").new()
	plume.position = pos
	return plume


static func make_particles(pos: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = puff()
	p.position = pos
	p.amount = 10
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.direction = Vector2(0.35, -1.0)
	p.spread = 12.0
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 22.0
	p.gravity = Vector2(6.0, -2.0)
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 2.2))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.15, Color(1, 1, 1, 0.55))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	p.color_ramp = ramp
	p.z_index = 1
	return p
