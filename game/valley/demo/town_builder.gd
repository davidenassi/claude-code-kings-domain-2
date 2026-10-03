extends RefCounted
## Instantiates the demonstration settlement (data/valley/demo_town.json): ground meshes, buildings,
## bridges, props, trees, fences and citizens. Phase 1 graphics test, not final gameplay.

const GroundBuilder := preload("res://valley/ground/ground_builder.gd")
const SpriteDB := preload("res://valley/buildings/sprite_db.gd")
const CitizenLayer := preload("res://valley/citizens/citizen_layer.gd")
const FrameAnim := preload("res://valley/buildings/frame_anim.gd")
const Smoke := preload("res://valley/fx/chimney_smoke.gd")

var smoke_layer: Node2D

var db: SpriteDB
var data: Dictionary
var citizens: Node2D
var counts := {}


func build(ground: Node2D, shadows: Node2D, bridges: Node2D, objects: Node2D) -> void:
	data = SpriteDB._json("res://data/valley/demo_town.json")
	if data.is_empty():
		return
	db = SpriteDB.new()
	# building shadows in their own node: hidden at far zoom, where they are 1-2 px (saves draw calls)
	var bsh := Node2D.new()
	bsh.name = "BuildingShadows"
	shadows.add_child(bsh)
	shadows = bsh
	smoke_layer = Node2D.new()
	smoke_layer.name = "Smoke"
	objects.get_parent().add_child.call_deferred(smoke_layer)
	var srng := RandomNumberGenerator.new()
	srng.seed = 11
	ground.add_child(GroundBuilder.build_plazas(data["plazas"], "earth"))
	ground.add_child(GroundBuilder.build_yards(data["yards"]))
	ground.add_child(GroundBuilder.build_fields(data["fields"]))
	var walls := PackedVector2Array()
	for q in data.get("walls", []):
		walls.append(Vector2(q[0], q[1]))
	var in_town := func(x: float, y: float) -> bool:
		return walls.size() > 2 and Geometry2D.is_point_in_polygon(Vector2(x, y), walls)
	ground.add_child(GroundBuilder.build_roads(data["roads"], in_town))
	ground.add_child(GroundBuilder.build_plazas(data["plazas"], "cobble"))
	var n := 0
	for b in data["buildings"]:
		var t: String = b["type"]
		var z: float = b.get("z", Proj.height_at(b["x"], b["y"]))
		if t == "castle":
			z = 136.0
		if t == "windmill" and db.buildings.has("windmill_base") and db.buildings.has("windmill_sails_7"):
			_windmill(b, z, shadows, objects)
			n += 1
			continue
		var parts := db.make(t, b["x"], b["y"], z)
		if parts.is_empty():
			continue
		if b.get("layer", "objects") == "bridge":
			bridges.add_child(parts["body"])
		else:
			objects.add_child(parts["body"])
		shadows.add_child(parts["shadow"])
		n += 1
		var chims: Array = db.buildings[t].get("chimneys", []) if db.buildings.has(t) else []
		if chims.size() > 0 and srng.randf() < 0.35:
			var c: Array = chims[srng.randi() % chims.size()]
			var base_pos: Vector2 = parts["body"].position + Vector2(0, Proj.altitude_offset(z))
			smoke_layer.add_child(Smoke.make(base_pos + Vector2(c[0], c[1])))
	counts["buildings"] = n
	n = 0
	for p in data["props"]:
		var parts := db.make(p["type"], p["x"], p["y"], Proj.height_at(p["x"], p["y"]))
		if parts.is_empty():
			continue
		objects.add_child(parts["body"])
		shadows.add_child(parts["shadow"])
		n += 1
	counts["props"] = n
	n = 0
	for t in data.get("trees", []):
		var parts := db.make(t["type"], t["x"], t["y"], Proj.height_at(t["x"], t["y"]), t.get("scale", 1.0))
		if parts.is_empty():
			continue
		objects.add_child(parts["body"])
		shadows.add_child(parts["shadow"])
		n += 1
	counts["trees"] = n
	citizens = CitizenLayer.new()
	citizens.name = "Citizens"
	objects.add_child(citizens)
	citizens.y_sort_enabled = true
	citizens.spawn(data["citizens"])
	counts["citizens"] = citizens.get_child_count()


func _windmill(b: Dictionary, z: float, shadows: Node2D, objects: Node2D) -> void:
	var base := db.make("windmill_base", b["x"], b["y"], z)
	objects.add_child(base["body"])
	shadows.add_child(base["shadow"])
	var frames := []
	for k in 8:
		var nm := "windmill_sails_%d" % k
		var m: Dictionary = db.buildings[nm]
		frames.append({"tex": load("res://assets/sprites/buildings/" + nm + ".png"),
			"sh": load("res://assets/sprites/buildings/" + nm + "_sh.png"),
			"anchor": Vector2(m["anchor"][0], m["anchor"][1])})
	var anim := FrameAnim.new()
	# the sails stand ~3 m in front (south) of the tower: sort them there, compensate the offset
	anim.position = Proj.ground_px(b["x"], b["y"] + 3.0)
	var sh := Sprite2D.new()
	sh.centered = false
	sh.material = base["shadow"].material
	shadows.add_child(sh)
	objects.add_child(anim)
	anim.setup(frames, sh, Proj.altitude_offset(z) - 3.0 * Proj.sin_el * Proj.px_per_m)
	anim.body.material = base["sprite"].material

