extends Node2D
## Visual citizens of the valley (Phase 1: representation only, no simulation).
## Modes: walk / carry along a path (ping-pong), wander around a spot, work / idle on a spot.
## Animations come from per-role atlases: rows "anim_dir", 5 rendered directions + 3 mirrored.

const DIR := "res://assets/sprites/citizens/"
const DIRS := ["S", "SE", "E", "NE", "N", "NE", "E", "SE"]      # index 0..7 from heading
const FLIP := [false, false, false, false, false, true, true, true]
const HIDE_BELOW_ZOOM := 0.07

var meta: Dictionary
var atlases: Dictionary = {}
var blob: Texture2D
var people: Array = []
var _rng := RandomNumberGenerator.new()


class Person:
	var sprite: Sprite2D
	var role: String
	var mode: String
	var path := PackedVector2Array()
	var cum := PackedFloat32Array()
	var s := 0.0
	var dirn := 1.0
	var speed := 1.2
	var pos := Vector2.ZERO
	var spot := Vector2.ZERO
	var radius := 10.0
	var target := Vector2.ZERO
	var wait := 0.0
	var heading := 0
	var anim := "idle"
	var t := 0.0


func _ready() -> void:
	_rng.seed = 99


func spawn(list: Array) -> void:
	var f := FileAccess.open(DIR + "citizens.json", FileAccess.READ)
	if f == null:
		return
	meta = JSON.parse_string(f.get_as_text())
	var g := Gradient.new()
	g.set_color(0, Color(0.08, 0.10, 0.16, 0.45))
	g.set_color(1, Color(0.08, 0.10, 0.16, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	blob = gt
	for c in list:
		var role: String = c["role"]
		if not meta.has(role):
			continue
		if not atlases.has(role):
			atlases[role] = load(DIR + role + ".png")
		var p := Person.new()
		p.role = role
		p.mode = c["mode"]
		p.speed = c.get("speed", 1.2)
		var spr := Sprite2D.new()
		spr.texture = atlases[role]
		spr.region_enabled = true
		spr.centered = false
		var sh := Sprite2D.new()
		sh.texture = blob
		sh.scale = Vector2(0.75, 0.32)
		sh.show_behind_parent = true
		sh.position = Vector2(float(meta[role]["anchor"][0]) + 3.0, float(meta[role]["anchor"][1]) - 1.0)
		spr.add_child(sh)
		var holder := Node2D.new()
		holder.add_child(spr)
		add_child(holder)
		p.sprite = spr
		if c.has("path"):
			for q in c["path"]:
				p.path.append(Vector2(q[0], q[1]))
			p.cum.append(0.0)
			for i in range(1, p.path.size()):
				p.cum.append(p.cum[i - 1] + p.path[i].distance_to(p.path[i - 1]))
			p.s = c.get("start", 0.0) * p.cum[p.cum.size() - 1]
			p.anim = "carry" if p.mode == "carry" else "walk"
		else:
			p.spot = Vector2(c["spot"][0], c["spot"][1])
			p.pos = p.spot
			p.radius = c.get("radius", 10.0)
			p.target = p.pos
			p.anim = "work" if p.mode == "work" else "idle"
			p.heading = DIRS.find(c.get("dir", "S")) if c.has("dir") else 0
			if c.get("dir", "S") in ["SW", "W", "NW"]:
				p.heading = {"SW": 7, "W": 6, "NW": 5}[c["dir"]]
		p.t = _rng.randf() * 4.0
		people.append(p)
		_update_person(p, 0.0)


func _path_point(p: Person) -> Vector2:
	var total := p.cum[p.cum.size() - 1]
	p.s = clampf(p.s, 0.0, total)
	var i := p.cum.bsearch(p.s)
	i = clampi(i, 1, p.cum.size() - 1)
	var seg := p.cum[i] - p.cum[i - 1]
	var t := 0.0 if seg <= 0.0 else (p.s - p.cum[i - 1]) / seg
	return p.path[i - 1].lerp(p.path[i], t)


static func heading_of(v: Vector2) -> int:
	var ang := rad_to_deg(atan2(v.x, v.y))          # 0 = south (towards the camera), 90 = east
	return int(round(fposmod(ang, 360.0) / 45.0)) % 8


func _update_person(p: Person, delta: float) -> void:
	p.t += delta
	var moving := false
	if p.path.size() > 1:
		var before := _path_point(p)
		p.s += p.dirn * p.speed * delta
		var total := p.cum[p.cum.size() - 1]
		if p.s >= total or p.s <= 0.0:
			p.dirn = -p.dirn
		p.pos = _path_point(p)
		var v := p.pos - before
		if v.length() > 0.0001:
			p.heading = heading_of(v)
		moving = true
	elif p.mode == "wander":
		if p.wait > 0.0:
			p.wait -= delta
			p.anim = "idle"
		else:
			var v := p.target - p.pos
			if v.length() < 0.3:
				p.wait = _rng.randf_range(1.0, 4.0)
				var a := _rng.randf() * TAU
				p.target = p.spot + Vector2(cos(a), sin(a)) * _rng.randf() * p.radius
			else:
				p.pos += v.normalized() * minf(p.speed * delta, v.length())
				p.heading = heading_of(v)
				p.anim = "walk"
				moving = true
	var m: Dictionary = meta[p.role]
	var cell := Vector2(m["cell"][0], m["cell"][1])
	var nframes: int = m["frames"][p.anim]
	var fps := 6.0
	if moving:
		fps = p.speed / 1.4 * 8.0
	elif p.anim == "work":
		fps = 7.0
	elif p.anim == "idle":
		fps = 2.5
	var frame := int(p.t * fps) % nframes
	var key: String = p.anim + "_" + String(DIRS[p.heading])
	var rows: Dictionary = m["rows"]
	var row: int = rows[key] if rows.has(key) else rows.get(p.anim + "_S", 0)
	p.sprite.region_rect = Rect2(frame * cell.x, row * cell.y, cell.x, cell.y)
	p.sprite.flip_h = FLIP[p.heading]
	var holder := p.sprite.get_parent() as Node2D
	holder.position = Proj.ground_px(p.pos.x, p.pos.y)
	var z := Proj.height_at(p.pos.x, p.pos.y)
	var ax: float = m["anchor"][0]
	var ay: float = m["anchor"][1]
	p.sprite.position = Vector2(-ax if not p.sprite.flip_h else -(cell.x - ax), Proj.altitude_offset(z) - ay)


func _process(delta: float) -> void:
	var zoom: float = get_viewport().get_camera_2d().zoom.x if get_viewport().get_camera_2d() else 1.0
	visible = zoom >= HIDE_BELOW_ZOOM
	if not visible:
		return
	for p in people:
		_update_person(p, delta)
