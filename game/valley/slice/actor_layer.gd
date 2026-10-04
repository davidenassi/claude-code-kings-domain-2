extends Node2D
## People and animals of the river quarter (Phase 1B): atlas animations in 8 directions (5 rendered + 3
## mirrored), modes walk / carry along a path, wander around a spot (with pauses), and static activities
## (work, talk, train, idle, graze). Only actors near the view are updated.

const DIRS := ["S", "SE", "E", "NE", "N", "NE", "E", "SE"]
const FLIP := [false, false, false, false, false, true, true, true]
const FPS := {"idle": 3.0, "walk": 9.0, "carry": 8.0, "work": 7.0, "talk": 5.0, "train": 7.0, "graze": 2.5}
const HIDE_BELOW_ZOOM := 0.07
const PEOPLE_SCALE := 1.15
const PEOPLE_SCALE_KINDS := ["farmer", "woodcutter", "builder", "artisan", "merchant", "guard", "soldier", "citizen", "woman"]

var metas := {}            # kind -> atlas meta (cell, anchor, rows, frames)
var textures := {}
var actors: Array = []
var surfaces: Array = []   # walkable decks above the terrain (bridges): {c, dir, half_len, half_w, z, hump}
var _rng := RandomNumberGenerator.new()
var blob: Texture2D


class Actor:
	var spr: Sprite2D
	var holder: Node2D
	var kind: String
	var meta: Dictionary
	var mode: String
	var anim := "idle"
	var base_anim := "idle"
	var path := PackedVector2Array()
	var cum := PackedFloat32Array()
	var s := 0.0
	var dirn := 1.0
	var speed := 1.1
	var pos := Vector2.ZERO
	var spot := Vector2.ZERO
	var radius := 5.0
	var target := Vector2.ZERO
	var wait := 0.0
	var heading := 0
	var t := 0.0
	var sc := 1.0


func _ready() -> void:
	_rng.seed = 1909
	var g := Gradient.new()
	g.set_color(0, Color(0.10, 0.09, 0.08, 0.42))
	g.set_color(1, Color(0.10, 0.09, 0.08, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	blob = gt


func load_atlas(dir: String, meta_file: String) -> void:
	var f := FileAccess.open(dir + meta_file, FileAccess.READ)
	if f == null:
		return
	var m: Dictionary = JSON.parse_string(f.get_as_text())
	for k in m:
		metas[k] = m[k]
		if ResourceLoader.exists(dir + k + ".png"):
			textures[k] = load(dir + k + ".png")


static func heading_of(v: Vector2) -> int:
	## world direction (y south) -> 0 S, 1 SE, 2 E, 3 NE, 4 N, 5 NW, 6 W, 7 SW
	var a := rad_to_deg(atan2(v.x, v.y))
	return posmod(int(round(a / 45.0)), 8)


static func heading_of_yaw(yaw: float) -> int:
	return posmod(int(round(yaw / 45.0)), 8)


func add_actor(kind: String, d: Dictionary) -> void:
	if not metas.has(kind) or not textures.has(kind):
		return
	var a := Actor.new()
	a.kind = kind
	a.meta = metas[kind]
	a.mode = d.get("mode", "idle")
	a.speed = float(d.get("speed", 1.1)) * (0.75 if kind in ["pig", "sheep", "cow", "chicken"] else 1.0)
	a.spr = Sprite2D.new()
	a.spr.texture = textures[kind]
	a.spr.region_enabled = true
	a.spr.centered = false
	var sh := Sprite2D.new()
	sh.texture = blob
	var cw: float = a.meta["cell"][0]
	sh.scale = Vector2(cw / 72.0 * 0.85, cw / 72.0 * 0.36)
	sh.show_behind_parent = true
	sh.position = Vector2(float(a.meta["anchor"][0]) + 3.0, float(a.meta["anchor"][1]) - 1.0)
	a.spr.add_child(sh)
	a.holder = Node2D.new()
	if kind in PEOPLE_SCALE_KINDS:
		# figures drawn larger than life, as in the references (scale the sprite, never the holder:
		# the holder's child offset includes the altitude, thousands of px)
		a.sc = PEOPLE_SCALE
		a.spr.scale = Vector2.ONE * a.sc
	a.holder.add_child(a.spr)
	add_child(a.holder)
	if d.has("path"):
		for q in d["path"]:
			a.path.append(Vector2(q[0], q[1]))
		a.cum.append(0.0)
		for i in range(1, a.path.size()):
			a.cum.append(a.cum[i - 1] + a.path[i].distance_to(a.path[i - 1]))
		a.s = float(d.get("start", _rng.randf())) * a.cum[a.cum.size() - 1]
		a.base_anim = "carry" if a.mode == "carry" else "walk"
		a.anim = a.base_anim
	else:
		a.spot = Vector2(d["spot"][0], d["spot"][1])
		a.pos = a.spot
		a.target = a.spot
		a.radius = float(d.get("radius", 5.0))
		a.base_anim = String(d.get("anim", {"work": "work", "train": "train", "graze": "graze"}.get(a.mode, "idle")))
		if not a.meta["frames"].has(a.base_anim):
			a.base_anim = "idle"
		a.anim = a.base_anim
		if d.has("face_yaw") and d["face_yaw"] != null:
			a.heading = heading_of_yaw(float(d["face_yaw"]))
		elif d.has("dir"):
			a.heading = ["S", "SE", "E", "NE", "N", "NW", "W", "SW"].find(String(d["dir"]))
			a.heading = maxi(a.heading, 0)
		else:
			a.heading = _rng.randi() % 8
		a.wait = _rng.randf_range(0.0, 4.0)
	a.t = float(d.get("start", _rng.randf())) * 4.0
	actors.append(a)
	_update(a, 0.0)


func _path_point(a: Actor) -> Vector2:
	var i := 1
	while i < a.cum.size() - 1 and a.cum[i] < a.s:
		i += 1
	var seg := maxf(a.cum[i] - a.cum[i - 1], 0.001)
	return a.path[i - 1].lerp(a.path[i], clampf((a.s - a.cum[i - 1]) / seg, 0.0, 1.0))


func _surface_z(p: Vector2) -> float:
	for sf in surfaces:
		var rel: Vector2 = p - sf["c"]
		var along: float = rel.dot(sf["dir"])
		var across: float = absf(rel.dot(Vector2(-sf["dir"].y, sf["dir"].x)))
		if absf(along) <= sf["half_len"] and across <= sf["half_w"]:
			var tt: float = along / sf["half_len"]
			return sf["z"] + sf["hump"] * (1.0 - tt * tt)
	return Proj.height_at(p.x, p.y)


func _update(a: Actor, delta: float) -> void:
	a.t += delta
	if a.path.size() > 1:
		var before := _path_point(a)
		a.s += a.dirn * a.speed * delta
		var L: float = a.cum[a.cum.size() - 1]
		if a.s >= L:
			a.s = L
			a.dirn = -1.0
		elif a.s <= 0.0:
			a.s = 0.0
			a.dirn = 1.0
		a.pos = _path_point(a)
		var mv := a.pos - before
		if mv.length() > 0.0005:
			a.heading = heading_of(mv)
	elif a.mode == "wander":
		if a.wait > 0.0:
			a.wait -= delta
			a.anim = a.base_anim if a.base_anim != "walk" else "idle"
			if a.kind in ["chicken", "pig", "sheep", "cow"] and a.meta["frames"].has("graze"):
				a.anim = "graze"
			elif a.kind in ["citizen", "woman", "merchant", "farmer", "artisan"] and int(a.t) % 7 < 4:
				a.anim = "talk"
			if a.wait <= 0.0:
				var ang := _rng.randf() * TAU
				a.target = a.spot + Vector2(cos(ang), sin(ang)) * _rng.randf_range(0.3, 1.0) * a.radius
		else:
			var d := a.target - a.pos
			if d.length() < 0.15:
				a.wait = _rng.randf_range(1.5, 6.0)
			else:
				var step := minf(d.length(), a.speed * 0.8 * delta)
				a.pos += d.normalized() * step
				a.heading = heading_of(d)
				a.anim = "walk"
	var m: Dictionary = a.meta
	var cell: Array = m["cell"]
	var dname: String = DIRS[a.heading]
	var key := a.anim + "_" + dname
	var rows: Dictionary = m["rows"]
	if not rows.has(key):
		key = "idle_" + dname
	var nf: int = int(m["frames"].get(a.anim, 1))
	var fr := int(a.t * FPS.get(a.anim, 6.0)) % maxi(nf, 1)
	a.spr.region_rect = Rect2(fr * cell[0], int(rows[key]) * cell[1], cell[0], cell[1])
	a.spr.flip_h = FLIP[a.heading]
	a.holder.position = Proj.ground_px(a.pos.x, a.pos.y)
	var z := _surface_z(a.pos)
	var ax: float = m["anchor"][0]
	var ay: float = m["anchor"][1]
	a.spr.position = Vector2((-ax if not a.spr.flip_h else -(float(cell[0]) - ax)) * a.sc, Proj.altitude_offset(z) - ay * a.sc)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	var zoom: float = cam.zoom.x if cam else 1.0
	visible = zoom >= HIDE_BELOW_ZOOM
	if not visible:
		return
	var view := Rect2()
	if cam:
		var size := get_viewport_rect().size / zoom
		view = Rect2(cam.get_screen_center_position() - size * 0.5, size).grow(256.0)
	for a in actors:
		if cam and not view.has_point(a.holder.position):
			continue
		_update(a, delta)
