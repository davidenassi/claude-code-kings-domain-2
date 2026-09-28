class_name PeopleLayer
extends Node2D
## The inhabitants near the camera: position interpolated along their current action (simulation hours + the
## clock's fraction of the next tick), a few frames per action, flipped to face where they go. Figures are drawn a
## little larger than life when zoomed out, then hidden (the settlement is still simulated).

const ATLAS_DIR := "res://assets/people"
const MAX_MPP := 2.4
## A person is drawn at least this tall on screen, but never more than MAX_SCALE times the real size (Phase 18:
## at 26 px and no limit the villagers in the fields stood as tall as the houses). Smaller than DOT_PX on
## screen a person is a dot of the colour of the work: a painted figure of four pixels is only noise.
const MIN_FIGURE_PX := 12.0
const MAX_SCALE := 2.6
const DOT_PX := 7.0
const FIGURE_M := 1.9
const JOB_DOTS := {&"farmer": Color(0.85, 0.72, 0.35), &"woodcutter": Color(0.50, 0.36, 0.22),
	&"builder": Color(0.80, 0.55, 0.30), &"quarrier": Color(0.66, 0.64, 0.60), &"child": Color(0.93, 0.86, 0.72)}

@export var camera_path: NodePath

var _camera: WorldCamera
var _atlas: Texture2D
var _sprites: Dictionary = {}
var _ppm := 22.0
var _facing: Dictionary = {}   # person id -> -1/1
var _anim_time := 0.0
var _src: Dictionary = {}          # sprite id -> Rect2 in the atlas
var _pivot: Dictionary = {}        # sprite id -> Vector2
var _look_cache: Dictionary = {}   # job -> the names of its frames
var _tints: Dictionary = {}        # person id -> Color (clothes_of)
var _disk: Texture2D


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	var meta: Dictionary = Defs.read_json(ATLAS_DIR + "/people_atlas.json")
	_atlas = load(ATLAS_DIR + "/" + String(meta["atlas"]))
	_sprites = meta["sprites"]
	_ppm = float(meta.get("ppm", 22.0))
	# the regions of the atlas read once, not parsed from the JSON arrays for every figure of every frame
	for id: String in _sprites.keys():
		var s: Dictionary = _sprites[id]
		var r: Array = s["rect"]
		var pv: Array = s["pivot"]
		_src[id] = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		_pivot[id] = Vector2(float(pv[0]), float(pv[1]))
	_disk = _make_disk(32)


## A white disk with a soft rim: the shadow under the feet and the dot of a person seen from afar are this one
## texture tinted, so all of them are drawn in one batch (Phase 19: a circle under a transform for each person
## broke the batching — some three thousand draw calls in a town of 1500).
static func _make_disk(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / (size * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) * size * 0.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if _camera == null or not Session.has_game():
		visible = false
		return
	var mpp := _camera.meters_per_pixel()
	visible = mpp < MAX_MPP
	if not visible:
		return
	modulate.a = 1.0 - smoothstep(MAX_MPP * 0.7, MAX_MPP, mpp)
	_anim_time += delta
	queue_redraw()


## The names of the frames of a trade, built once: no string is formatted for a figure in a frame.
func _looks(job: StringName) -> Dictionary:
	var known: Dictionary = _look_cache.get(job, {})
	if not known.is_empty():
		return known
	var look := String(job) if _sprites.has("%s_idle_0" % job) else "idle"
	known = {"walk": ["%s_walk_0" % look, "%s_walk_1" % look], "carry": ["%s_carry_0" % look, "%s_carry_1" % look],
		"work": ["%s_work_0" % look, "%s_work_1" % look], "idle": "%s_idle_0" % look}
	_look_cache[job] = known
	return known


func sprite_id(p: PersonState, _hours: float) -> String:
	var looks := _looks(p.job)
	match p.action:
		&"walk":
			return looks["walk"][int(_anim_time * 5.0 + p.id) % 2]
		&"carry":
			return looks["carry"][int(_anim_time * 5.0 + p.id) % 2]
		&"chop", &"quarry", &"build", &"farm":
			return looks["work"][int(_anim_time * 2.2 + p.id) % 2]
		_:
			return looks["idle"]


func _draw() -> void:
	var sess := Session.current
	var world := sess.world
	var hours := float(world.tick) + sess.clock.tick_alpha()
	var mpp := _camera.meters_per_pixel()
	var scale := clampf(MIN_FIGURE_PX * mpp / FIGURE_M, 1.0, MAX_SCALE)
	var as_dots := FIGURE_M * scale / mpp < DOT_PX
	var view := _camera.visible_world_rect().grow(20.0)
	# the figures in view, nearest to the bottom of the screen last: [y, id, index] sorted natively (a GDScript
	# comparator on a thousand figures a frame was a good part of the cost of the layer)
	var order: Array = []
	var people: Array[PersonState] = []
	var spots: PackedVector2Array = PackedVector2Array()
	for p: PersonState in world.people.values():
		if p.action == &"sleep" or p.action == &"bake":
			continue   # indoors
		if p.settlement < 0:
			continue   # marching with an army: the ArmyLayer draws him
		var pos := p.position_at(hours)
		if view.has_point(pos):
			order.append([pos.y, p.id, people.size()])
			people.append(p)
			spots.append(pos)
	order.sort()
	if as_dots:
		for item: Array in order:
			var i: int = item[2]
			var pos := spots[i]
			draw_texture_rect(_disk, Rect2(pos - Vector2(1.4, 1.4) * mpp, Vector2(2.8, 2.8) * mpp), false, Color(0.12, 0.09, 0.06, 0.5))
			draw_texture_rect(_disk, Rect2(pos - Vector2(1.0, 1.0) * mpp, Vector2(2.0, 2.0) * mpp), false,
				JOB_DOTS.get(people[i].job, Color(0.78, 0.30, 0.24)))
		return
	# every shadow first, then every figure: two batches instead of two per person
	var shadow_size := Vector2(1.04, 0.40) * scale
	for item: Array in order:
		var feet := spots[int(item[2])] + Vector2(0.28, 0.06) * scale
		draw_texture_rect(_disk, Rect2(feet - shadow_size * 0.5, shadow_size), false, Color(0.10, 0.09, 0.06, 0.22))
	for item: Array in order:
		var i: int = item[2]
		var p := people[i]
		var pos := spots[i]
		var dx := p.seg_to.x - p.seg_from.x
		if absf(dx) > 0.3 and (p.action == &"walk" or p.action == &"carry"):
			_facing[p.id] = 1.0 if dx > 0.0 else -1.0
		var face := float(_facing.get(p.id, 1.0))
		_draw_one(sprite_id(p, hours), pos, scale, face, _tint_of(p))
		if p.action == &"carry" and not p.carrying.is_empty():
			var load_id := "load_%s" % p.carrying["res"]
			if _src.has(load_id):
				_draw_one(load_id, pos + Vector2(0.15 * face, -1.45) * scale, scale * 0.9, face)


func _tint_of(p: PersonState) -> Color:
	if _tints.size() > 4096:
		_tints.clear()   # people come and go: the table never grows beyond a large town
	var c: Variant = _tints.get(p.id)
	if c == null:
		c = clothes_of(p)
		_tints[p.id] = c
	return c


## Nobody in a village dresses exactly like the neighbour (world art pass): a slight tint of the whole figure
## per person — warmer, cooler, faded, darker — the same person always the same way (from the id).
static func clothes_of(p: PersonState) -> Color:
	var h := KDRng.hash01(p.id, 3, 6101)
	var v := 0.88 + 0.2 * KDRng.hash01(p.id, 4, 6101)
	var warm := Color(1.06, 0.98, 0.90)
	var cool := Color(0.92, 0.97, 1.05)
	var tint := warm.lerp(cool, h)
	return Color(tint.r * v, tint.g * v, tint.b * v, 1.0)


func _draw_one(id: String, feet: Vector2, scale: float, face: float, tint: Color = Color.WHITE) -> void:
	var src: Variant = _src.get(id)
	if src == null:
		return
	var region: Rect2 = src
	var size := region.size / _ppm * scale
	var offset := (_pivot[id] as Vector2) / _ppm * scale
	var dst: Rect2
	if face >= 0.0:
		dst = Rect2(feet - offset, size)
	else:
		# mirrored: negative width flips the texture region
		dst = Rect2(Vector2(feet.x + offset.x, feet.y - offset.y), Vector2(-size.x, size.y))
	draw_texture_rect_region(_atlas, dst, region, tint)

