class_name RiverBankProps
extends Node2D
## Reeds, stones and patches of mud along the rivers, close to the ground (world art pass): the banks are not the
## same clean line from source to sea. Only drawn, deterministic (from the position along the course), computed
## per chunk of 512 m for the chunks the camera sees, and forgotten when it looks elsewhere.

const ATLAS_DIR := "res://assets/buildings"
const SHOW_MPP := Vector2(1.2, 1.8)   ## fully visible below x, gone above y
const CHUNK_M := 512.0
const STEP_M := 5.0                   ## one chance of something every few metres of bank

@export var camera_path: NodePath

var _camera: WorldCamera
var _atlas: Texture2D
var _sprites: Dictionary = {}
var _ppm := 16.0
var _chunks: Dictionary = {}          # Vector2i -> Array of [y, sprite, pos, flip, scale]
var _drawn: Rect2i = Rect2i()
## chunk key -> PackedInt32Array of [river, segment] pairs that cross it: built once, so a chunk looks only at
## its own stretch of river (walking every segment of every river for each chunk cost a hitch of a tenth of a
## second when the camera came down over a new place)
static var _index: Dictionary = {}


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as WorldCamera
	var meta: Dictionary = Defs.read_json(ATLAS_DIR + "/props_atlas.json")
	if meta.is_empty():
		return
	_atlas = load(ATLAS_DIR + "/" + String(meta["atlas"]))
	_sprites = meta["sprites"]
	_ppm = float(meta.get("ppm", 16.0))
	if _index.is_empty():
		_build_index(WorldData.get_instance())   # at the start, not as a hitch the first time the camera comes down


func _process(_delta: float) -> void:
	if _camera == null or _atlas == null:
		visible = false
		return
	var mpp := _camera.meters_per_pixel()
	var fade := 1.0 - smoothstep(SHOW_MPP.x, SHOW_MPP.y, mpp)
	visible = fade > 0.01
	if not visible:
		return
	modulate.a = fade
	var view := _camera.visible_world_rect().grow(40.0)
	var keys := Rect2i(Vector2i(floor(view.position.x / CHUNK_M), floor(view.position.y / CHUNK_M)),
		Vector2i.ONE)
	keys = keys.expand(Vector2i(floor(view.end.x / CHUNK_M), floor(view.end.y / CHUNK_M)))
	if keys != _drawn:
		_drawn = keys
		for y in range(keys.position.y, keys.end.y + 1):
			for x in range(keys.position.x, keys.end.x + 1):
				var k := Vector2i(x, y)
				if not _chunks.has(k):
					_chunks[k] = chunk_items(k)
		for k: Vector2i in _chunks.keys():
			if not keys.grow(2).has_point(k):
				_chunks.erase(k)
		queue_redraw()


## What grows on the banks inside one chunk: reeds where the water is slow (wide rivers, inner bends),
## stones here and there, both just outside the water on either side.
static func _build_index(wd: WorldData) -> void:
	for ri in wd.rivers.size():
		var pts: PackedVector2Array = wd.rivers[ri]["points"]
		for i in pts.size() - 1:
			var box := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(24.0)
			for cy in range(int(floor(box.position.y / CHUNK_M)), int(floor(box.end.y / CHUNK_M)) + 1):
				for cx in range(int(floor(box.position.x / CHUNK_M)), int(floor(box.end.x / CHUNK_M)) + 1):
					var k := Vector2i(cx, cy)
					var list: PackedInt32Array = _index.get(k, PackedInt32Array())
					list.append(ri)
					list.append(i)
					_index[k] = list


static func chunk_items(key: Vector2i) -> Array:
	var wd := WorldData.get_instance()
	if _index.is_empty():
		_build_index(wd)
	var rect := Rect2(Vector2(key) * CHUNK_M, Vector2(CHUNK_M, CHUNK_M))
	var out: Array = []
	var pairs: PackedInt32Array = _index.get(key, PackedInt32Array())
	for n in range(0, pairs.size(), 2):
		var ri := pairs[n]
		var i := pairs[n + 1]
		var r: Dictionary = wd.rivers[ri]
		var pts: PackedVector2Array = r["points"]
		var ws: PackedFloat32Array = r["widths"]
		var a := pts[i]
		var b := pts[i + 1]
		var seg := b - a
		var length := seg.length()
		if length < 0.5:
			continue
		var dir := seg / length
		var normal := Vector2(-dir.y, dir.x)
		var steps := int(length / STEP_M)
		for s in steps:
			var t := (float(s) + 0.5) / float(maxi(steps, 1))
			var p := a.lerp(b, t)
			if not rect.has_point(p):
				continue
			var half := lerpf(ws[i], ws[i + 1], t) * 0.5
			var h1 := KDRng.hash01(ri * 7919 + i, s, 8101)
			var h2 := KDRng.hash01(ri * 7919 + i, s, 8102)
			var side := -1.0 if h2 < 0.5 else 1.0
			# the reeds come in beds: a slow wave along the river decides where they grow
			var bed := 0.5 + 0.5 * sin(float(i) * 0.9 + float(s) * 0.35 + float(ri))
			var off := half * (0.98 + 0.30 * KDRng.hash01(ri, i * 131 + s, 8103))
			var base := p + normal * side * off
			var w := wd.water_at(base)
			if w == WorldData.WATER_SEA or w == WorldData.WATER_LAKE:
				continue
			if h1 < 0.42 * bed:
				# a bed of reeds: a few clumps along the water's edge, the tallest nearest the water
				var clumps := 3 + int(KDRng.hash01(ri, i * 131 + s, 8105) * 4.0)
				for c in clumps:
					var along_off := (float(c) - float(clumps) * 0.5) * 1.3 + (KDRng.hash01(ri, c, 8106 + s) - 0.5)
					var out_off := KDRng.hash01(ri, c, 8107 + s) * 1.6
					var pos := base + dir * along_off + normal * side * out_off
					out.append([pos.y, "reeds_%d" % (0 if KDRng.hash01(ri, c, 8108 + s) < 0.7 else 1), pos,
						KDRng.hash01(ri, c, 8109 + s) < 0.5, 1.3 + 0.6 * KDRng.hash01(ri, c, 8110 + s) - out_off * 0.2])
			elif h1 > 0.93:
				out.append([base.y, "stone_%d" % (0 if h2 < 0.5 else 1), base, h2 > 0.5,
					1.4 + 1.2 * KDRng.hash01(ri, i * 131 + s, 8104)])
	out.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	return out


func _draw() -> void:
	var view := _camera.visible_world_rect().grow(20.0) if _camera else Rect2()
	for k: Vector2i in _chunks.keys():
		for it: Array in _chunks[k]:
			var feet: Vector2 = it[2]
			if not view.has_point(feet):
				continue
			var s: Dictionary = _sprites.get(String(it[1]), {})
			if s.is_empty():
				continue
			var rect: Array = s["rect"]
			var pv: Array = s["pivot"]
			var src := Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
			var scale := float(it[4])
			var size := src.size / _ppm * scale
			var offset := Vector2(float(pv[0]), float(pv[1])) / _ppm * scale
			if bool(it[3]):
				draw_texture_rect_region(_atlas, Rect2(Vector2(feet.x + offset.x, feet.y - offset.y), Vector2(-size.x, size.y)), src)
			else:
				draw_texture_rect_region(_atlas, Rect2(feet - offset, size), src)

