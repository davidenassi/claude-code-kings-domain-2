extends RefCounted
## Phase 1B vertical slice — the river quarter of Altavera (data/valley/slice.json).
## Painted ground overlay (projected chunks), buildings and props with ground shadows, animated mill wheel,
## splashing water, chimney and forge smoke, people and animals.

const SHADOW_SHADER := preload("res://valley/buildings/shadow_sprite.gdshader")
const ActorLayer := preload("res://valley/slice/actor_layer.gd")
const Smoke := preload("res://valley/fx/chimney_smoke.gd")
const FrameAnim := preload("res://valley/buildings/frame_anim.gd")
const SDIR := "res://assets/sprites/slice/"
const BANNER_SHADER := preload("res://valley/slice/banner_wave.gdshader")

var data: Dictionary
var meta: Dictionary
var actors: Node2D
var counts := {}
var _tex := {}
var _shadow_mat: ShaderMaterial


static func _json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _texture(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


func build(ground: Node2D, shadows: Node2D, bridges: Node2D, objects: Node2D, fx: Node2D) -> void:
	var d = _json("res://data/valley/slice.json")
	var m = _json(SDIR + "slice.json")
	if d == null or m == null:
		return
	data = d
	meta = m
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = SHADOW_SHADER
	_shadow_mat.set_shader_parameter("use_red", true)
	_shadow_mat.set_shader_parameter("strength", 0.66)
	_shadow_mat.set_shader_parameter("shade", Vector3(0.12, 0.10, 0.14))
	_build_ground(ground)
	var sh_root := Node2D.new()
	sh_root.name = "SliceShadows"
	shadows.add_child(sh_root)
	var smoke := Node2D.new()
	smoke.name = "SliceSmoke"
	fx.add_child(smoke)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var n := 0
	var surfaces: Array = []
	for o in data["objects"]:
		var name: String = o["sprite"]
		if not meta.has(name):
			continue
		var sm: Dictionary = meta[name]
		var x: float = o["x"]
		var y: float = o["y"]
		var z: float = o.get("z", Proj.height_at(x, y))
		var layer := bridges if o.get("kind", "") == "bridge" else objects
		var body := _sprite_node(name, sm, x, y, z, sh_root)
		layer.add_child(body)
		n += 1
		if o.get("kind", "") == "bridge":
			var yaw := deg_to_rad(float(sm.get("yaw", 0)))
			surfaces.append({"c": Vector2(x, y), "dir": Vector2(cos(yaw), -sin(yaw)), "half_len": 19.5,
				"half_w": 2.6, "z": z, "hump": 1.45})
		# smoke from chimneys (most houses) and from the forge
		var chims: Array = sm.get("chimneys", [])
		for c in chims:
			var forge := name.begins_with("smithy")
			if not forge and rng.randf() > 0.7:
				continue
			var p := Proj.ground_px(x, y) + Vector2(0, Proj.altitude_offset(z)) + Vector2(c[0], c[1])
			var s := Smoke.make(p)
			if forge:
				s.tint = Color(0.5, 0.48, 0.47)
				s.alpha = 0.62
				s.grow = 1.4
				s.life = 5.0
			smoke.add_child(s)
		if o.has("wheel"):
			_mill_wheel(o, sm, x, y, z, objects, sh_root, fx)
	counts["slice_objects"] = n
	# people and animals
	actors = ActorLayer.new()
	actors.name = "SliceActors"
	actors.y_sort_enabled = true
	objects.add_child(actors)
	actors.load_atlas("res://assets/sprites/people/", "people.json")
	actors.load_atlas("res://assets/sprites/animals/", "animals.json")
	actors.surfaces = surfaces
	for p in data["people"]:
		actors.add_actor(p["role"], p)
	for a in data["animals"]:
		actors.add_actor(a["kind"], a)
	counts["slice_actors"] = actors.actors.size()


func _sprite_node(name: String, sm: Dictionary, x: float, y: float, z: float, sh_root: Node2D) -> Node2D:
	var root := Node2D.new()
	root.name = name.replace("@", "_")
	root.position = Proj.ground_px(x, y)
	var spr := Sprite2D.new()
	spr.texture = _texture(SDIR + name + ".png")
	spr.centered = false
	var anc := Vector2(sm["anchor"][0], sm["anchor"][1])
	spr.position = Vector2(-anc.x, Proj.altitude_offset(z) - anc.y)
	root.add_child(spr)
	if name.begins_with("banner_pole") and spr.texture:
		var bm := ShaderMaterial.new()
		bm.shader = BANNER_SHADER
		bm.set_shader_parameter("pole_u", anc.x / float(spr.texture.get_width()))
		spr.material = bm
	var stex := _texture(SDIR + name + "_sh.png")
	if stex:
		var sh := Sprite2D.new()
		sh.texture = stex
		sh.centered = false
		sh.position = root.position + spr.position
		sh.material = _shadow_mat
		sh_root.add_child(sh)
	return root


func _mill_wheel(o: Dictionary, sm: Dictionary, x: float, y: float, z: float, objects: Node2D, sh_root: Node2D,
		fx: Node2D) -> void:
	var frames := []
	for nm in o["wheel"]:
		if not meta.has(nm):
			return
		var wm: Dictionary = meta[nm]
		frames.append({"tex": _texture(SDIR + nm + ".png"), "sh": _texture(SDIR + nm + "_sh.png"),
			"anchor": Vector2(wm["anchor"][0], wm["anchor"][1])})
	var w0: Dictionary = meta[o["wheel"][0]]
	var sp: Array = w0.get("sort_point", [0.0, 0.0, 0.0])
	var anim := FrameAnim.new()
	anim.fps = 8.0
	# sort the wheel at its own ground position (in front of the mill wall), compensate the offset
	anim.position = Proj.ground_px(x + sp[0], y + sp[1])
	var sh := Sprite2D.new()
	sh.centered = false
	sh.material = _shadow_mat
	sh_root.add_child(sh)
	objects.add_child(anim)
	anim.setup(frames, sh, Proj.altitude_offset(z) - sp[1] * Proj.sin_el * Proj.px_per_m, -sp[0] * Proj.px_per_m)
	# white water churned by the paddles
	var att: Array = sm.get("attach", {}).get("wheel", [0, 0, 0])
	var foam := CPUParticles2D.new()
	foam.position = Proj.ground_px(x + att[0], y + att[1]) + Vector2(0, Proj.altitude_offset(z - 1.5))
	foam.amount = 70
	foam.lifetime = 1.1
	foam.preprocess = 1.0
	foam.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	foam.emission_rect_extents = Vector2(40, 10)
	foam.direction = Vector2(0.3, -1.0)
	foam.spread = 55.0
	foam.initial_velocity_min = 25.0
	foam.initial_velocity_max = 70.0
	foam.gravity = Vector2(0, 160)
	foam.texture = preload("res://valley/fx/smoke_plume.gd").puff_texture()     # soft drops, not square pixels
	foam.scale_amount_min = 0.06
	foam.scale_amount_max = 0.16
	foam.color = Color(0.92, 0.96, 1.0, 0.75)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	foam.color_ramp = ramp
	fx.add_child(foam)


func _build_ground(ground: Node2D) -> void:
	var g = _json("res://data/valley/slice_ground.json")
	if g == null:
		return
	var node := Node2D.new()
	node.name = "SliceGround"
	ground.add_child(node)
	for c in g["chunks"]:
		var s := Sprite2D.new()
		s.texture = load("res://assets/slice_ground/" + String(c["file"]))
		s.centered = false
		s.position = Vector2(c["x"], c["y"])
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		node.add_child(s)
