class_name NucleusLayer
extends Node2D
## The nucleus of the community on the local map (Rebirth, Phase 3): the common fire with its stones, its tripod
## and its benches, the flames that move and the glow on the ground, the landing on the bank where the water is
## drawn with its buckets — and, drawn by a second node of the same script above the people and the roofs, the
## smoke that rises from the fire. The smoke is what says "somebody lives here" from the whole valley away: it
## never gets thinner than a few pixels, so the place of the community is found at a glance at any zoom.
##
## Only drawn: the fire and the water point are buildings of the world (Nucleus), placed by the founding.

const ATLAS_DIR := "res://assets/buildings"
## The props of the fire fade out with the sprites of the buildings (SettlementLayer.VISIBLE_MPP).
const PROPS_MPP := Vector2(2.4, 2.7)
## The smoke: how tall the plume is on the ground, and at least how tall on screen.
const SMOKE_M := 26.0
const SMOKE_MIN_PX := 46.0
const SMOKE_PUFFS := 26
## The pole of the community: how tall on the ground, and at least how tall on screen.
const BANNER_M := 6.0
const BANNER_MIN_PX := 30.0
const WIND := Vector2(0.9, -0.12)

## false: the fire, its props and the water point (under the people); true: only the smoke (over everything).
@export var smoke := false
@export var camera_path: NodePath

var _camera: WorldCamera
var _atlas: Texture2D
var _sprites: Dictionary = {}
var _ppm := 16.0
var _disk: Texture2D
var _people_atlas: Texture2D
var _people_sprites: Dictionary = {}
var _people_ppm := 22.0
var _time := 0.0
## [hearth position, water point position or Vector2.INF], rebuilt when the buildings change
var _nuclei: Array = []
var _version := -1
var _world_id := 0


static var _blob: Texture2D


## A soft round stain, opaque in the middle and fading to nothing at the rim: smoke, glow and trodden earth are
## stamped with it, so nothing on the ground has the hard edge of a polygon.
static func soft_blob() -> Texture2D:
	if _blob:
		return _blob
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
	_blob = ImageTexture.create_from_image(img)
	return _blob


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	var meta: Dictionary = Defs.read_json(ATLAS_DIR + "/props_atlas.json")
	if not meta.is_empty():
		_atlas = load(ATLAS_DIR + "/" + String(meta["atlas"]))
		_sprites = meta["sprites"]
		_ppm = float(meta.get("ppm", 16.0))
	_disk = soft_blob()
	var people: Dictionary = Defs.read_json("res://assets/people/people_atlas.json")
	if not people.is_empty():
		_people_atlas = load("res://assets/people/" + String(people["atlas"]))
		_people_sprites = people["sprites"]
		_people_ppm = float(people.get("ppm", 22.0))
	EventBus.session_started.connect(func(_s: GameSession) -> void: _version = -1)
	EventBus.session_loaded.connect(func(_s: GameSession) -> void: _version = -1)


func _process(delta: float) -> void:
	if _camera == null or not Session.has_game():
		visible = false
		return
	var world := Session.current.world
	if world.buildings_version != _version or world.get_instance_id() != _world_id:
		_version = world.buildings_version
		_world_id = world.get_instance_id()
		_nuclei = nuclei(world)
	visible = not _nuclei.is_empty()
	if not visible:
		return
	# the flames and the smoke move with the clock of the game, and stand still when it is paused
	var speed := 0.0 if Session.current.clock.is_paused() else 1.0
	_time += delta * speed
	queue_redraw()


## Every community fire, its water point, the colour of its realm and how the landing meets the water:
## [[hearth pos, water pos or Vector2.INF, colour, {dir, dist}], ...].
static func nuclei(world: WorldState) -> Array:
	var out: Array = []
	for s in world.settlements:
		var h := Nucleus.hearth_of(world, s)
		if h == null:
			continue
		var wp := Nucleus.water_point_of(world, s)
		var k := world.kingdom(s.kingdom)
		var reach := Nucleus.landing_reach(SettlementSim.ground(world), wp) if wp else {}
		out.append([h.pos, wp.pos if wp else Vector2.INF, k.color if k else Color(0.7, 0.2, 0.15), reach])
	return out


func _draw() -> void:
	var mpp := _camera.meters_per_pixel()
	var view := _camera.visible_world_rect()
	for n: Array in _nuclei:
		var fire: Vector2 = n[0]
		var water: Vector2 = n[1]
		if smoke:
			_draw_smoke(fire, mpp, view)
			_draw_banner(fire + Nucleus.BANNER, mpp, n[2])
			continue
		var props_a := 1.0 - smoothstep(PROPS_MPP.x, PROPS_MPP.y, mpp)
		if not view.grow(300.0).has_point(fire):
			continue
		if props_a > 0.01:
			if water != Vector2.INF:
				_draw_water_point(fire, water, n[3], props_a)
			_draw_fire(fire, mpp, props_a)
		else:
			# from afar the fire is a warm spark in the middle of the place
			var r := maxf(1.2, 2.2 * mpp)
			_disk_at(fire, r * 2.2, Color(1.0, 0.55, 0.15, 0.25))
			_disk_at(fire, r, Color(1.0, 0.72, 0.30, 0.9))


func _draw_fire(fire: Vector2, mpp: float, alpha: float) -> void:
	# the benches behind the fire first, then the fire, then the benches in front
	var benches := Nucleus.BENCHES.duplicate()
	benches.sort_custom(func(a: Array, b: Array) -> bool: return (a[1] as Vector2).y < (b[1] as Vector2).y)
	for b: Array in benches:
		if (b[1] as Vector2).y <= 0.0:
			_prop(String(b[0]), fire + b[1], alpha)
	# the glow on the ground round the stones
	var flicker := 0.85 + 0.15 * sin(_time * 7.3) * sin(_time * 3.1 + 1.3)
	_disk_at(fire, 5.0, Color(1.0, 0.55, 0.18, 0.22 * alpha * flicker))
	_prop("hearth_0", fire, alpha)
	_draw_flames(fire, mpp, alpha)
	for b: Array in benches:
		if (b[1] as Vector2).y > 0.0:
			_prop(String(b[0]), fire + b[1], alpha)


## Three tongues of flame between the logs, each with its own beat, a brighter core in each, sparks now and then.
func _draw_flames(fire: Vector2, mpp: float, alpha: float) -> void:
	var base := fire + Vector2(0.0, -0.05)
	draw_set_transform(base, 0.0, Vector2.ONE)
	for k in 3:
		var ph := float(k) * 2.1
		var h := 0.62 + 0.18 * sin(_time * (6.0 + k) + ph) + 0.08 * sin(_time * 13.0 + ph * 3.0)
		var w := 0.2 + 0.05 * sin(_time * 5.0 + ph)
		var x := (float(k) - 1.0) * 0.2
		var lean := 0.1 * sin(_time * 2.3 + ph) + 0.06
		var outer := PackedVector2Array([Vector2(x - w, 0.0), Vector2(x - w * 0.6, -h * 0.45), Vector2(x + lean, -h),
			Vector2(x + w * 0.6, -h * 0.4), Vector2(x + w, 0.0)])
		draw_colored_polygon(outer, Color(0.96, 0.46, 0.10, 0.85 * alpha))
		var inner := PackedVector2Array([Vector2(x - w * 0.5, 0.0), Vector2(x + lean * 0.6, -h * 0.62), Vector2(x + w * 0.5, 0.0)])
		draw_colored_polygon(inner, Color(1.0, 0.86, 0.38, 0.9 * alpha))
	# a spark that goes up and dies
	var t := fmod(_time * 0.9, 1.0)
	if mpp < 0.6:
		draw_circle(Vector2(0.15 * sin(_time * 3.0), -0.7 - t * 1.4), 0.04, Color(1.0, 0.8, 0.4, (1.0 - t) * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The landing: planks laid straight across the bank from a metre inland to a metre and a half over the water,
## a trodden patch where the path arrives, and the buckets beside it.
func _draw_water_point(fire: Vector2, water: Vector2, reach: Dictionary, alpha: float) -> void:
	var dir: Vector2 = reach.get("dir", (water - fire).normalized())
	var to_water := float(reach.get("dist", 2.0))
	_disk_at(water - dir * 1.4, 3.6, Color(0.46, 0.38, 0.25, 0.34 * alpha))
	var s: Dictionary = _sprites.get("landing_0", {})
	if not s.is_empty():
		var rect: Array = s["rect"]
		var pv: Array = s["pivot"]
		var src := Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
		var drawn_m := 3.0   # the planks of the sprite, from its pivot to the stakes
		var length := clampf(to_water + 1.0 + 1.5, 2.5, 9.0)
		draw_set_transform(water - dir * 1.0, dir.angle(), Vector2(length / drawn_m, 1.0))
		draw_texture_rect_region(_atlas, Rect2(-Vector2(float(pv[0]), float(pv[1])) / _ppm, src.size / _ppm), src,
			Color(1, 1, 1, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var side := Vector2(-dir.y, dir.x)
	if (fire - water).dot(side) < 0.0:
		side = -side   # the buckets wait on the side the path comes from
	_prop("buckets_0", water - dir * 1.2 + side * 1.8, alpha)


## The plume: puffs that leave the fire one after the other, drift with the wind, swell and thin out. Its size on
## the ground is that of a real campfire's smoke, but never less than a few dozen pixels tall: from the far zoom
## of the valley it is the sign of the community.
func _draw_smoke(fire: Vector2, mpp: float, view: Rect2) -> void:
	var height := maxf(SMOKE_M, SMOKE_MIN_PX * mpp)
	if not view.grow(height * 1.5).has_point(fire):
		return
	var far := smoothstep(1.5, 5.0, mpp)
	for i in SMOKE_PUFFS:
		var t := fmod(_time * 0.09 + float(i) / float(SMOKE_PUFFS), 1.0)
		var wob := sin(_time * 0.7 + float(i) * 1.7) * 0.05
		var at := fire + Vector2(0.0, -0.9) + (Vector2(0.0, -1.0) + WIND * t * 0.9 + Vector2(wob, 0.0)) * height * t
		var r := height * (0.06 + 0.2 * t)
		var a := (1.0 - t) * smoothstep(0.0, 0.1, t) * lerpf(0.30, 0.5, far)
		_disk_at(at, r * 2.0, Color(0.88, 0.88, 0.86, a))


## The banner of the community on its pole at the edge of the square, in the colour of the realm, waving: with the
## smoke it tells from any height where the community is and that it is the player's.
func _draw_banner(at: Vector2, mpp: float, colour: Color) -> void:
	var frame := "banner_%d" % (int(_time * 1.6) % 2)
	var s: Dictionary = _people_sprites.get(frame, {})
	if s.is_empty():
		return
	var rect: Array = s["rect"]
	var pv: Array = s["pivot"]
	var src := Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	var tall_m := src.size.y / _people_ppm
	var scale := maxf(BANNER_M, BANNER_MIN_PX * mpp) / tall_m
	var size := src.size / _people_ppm * scale
	var feet := Vector2(float(pv[0]), float(pv[1])) / _people_ppm * scale
	_disk_at(at + Vector2(0.3, 0.1) * scale, 0.9 * scale, Color(0.1, 0.08, 0.05, 0.35))
	draw_texture_rect_region(_people_atlas, Rect2(at - feet, size), src, colour.lerp(Color.WHITE, 0.12))


func _prop(id: String, feet: Vector2, alpha: float) -> void:
	var s: Dictionary = _sprites.get(id, {})
	if s.is_empty():
		return
	var rect: Array = s["rect"]
	var pv: Array = s["pivot"]
	var src := Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	draw_texture_rect_region(_atlas, Rect2(feet - Vector2(float(pv[0]), float(pv[1])) / _ppm, src.size / _ppm), src,
		Color(1, 1, 1, alpha))


func _disk_at(center: Vector2, diameter: float, color: Color) -> void:
	draw_texture_rect(_disk, Rect2(center - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter), false, color)
