class_name WorldData
extends RefCounted
## The official, static map loaded from res://data/world/. One shared instance.
## Provides point queries for the simulation and GPU textures for the renderers.

const DIR := "res://data/world"
const WATER_LAND := 0
const WATER_SEA := 1
const WATER_LAKE := 2
const WATER_RIVER := 3
const PROVINCE_NONE := 65535

static var _instance: WorldData = null

var loaded: bool = false
var errors: PackedStringArray = PackedStringArray()
var meta: Dictionary = {}
var size_m: Vector2 = Vector2(112000, 72000)
var cell_m: float = 64.0
var fine_cell_m: float = 32.0
var grid_w: int = 0
var grid_h: int = 0
var fine_w: int = 0
var fine_h: int = 0

var height_bytes: PackedByteArray
var height: PackedFloat32Array
var biome: PackedByteArray
var forest: PackedByteArray
## Where trees actually stand (forest with clearings and open stands, tools/worldgen/canopy.py); falls back to forest.
var canopy: PackedByteArray
var moisture: PackedByteArray
var temperature: PackedByteArray
var water: PackedByteArray
var coast: PackedByteArray
var province_raster: PackedByteArray   ## uint16 little endian per 64 m cell

## Continent metres of this data's (0, 0): zero for the continent itself; for a valley cut out of it (DomainData)
## the corner of the window, so that trees, woods and rocks are drawn from the same hashes and noises as the
## continent would draw them there (the same trees after the Rebirth migration).
var feature_origin: Vector2 = Vector2.ZERO
## The woods of this data are drawn tree by tree in its canopy raster (a generated homeland, 8 m): glades, cores and
## ragged margins are already there, and the noises that give the continent's 64 m woods a shape are not added.
var designed_woods := false

var provinces: Array[ProvinceGeo] = []
## [{id, length_m, max_width_m, points: PackedVector2Array, widths: PackedFloat32Array}]
var rivers: Array[Dictionary] = []
## Province borders: {a, b, type: StringName, points: PackedVector2Array, a_side: +1/-1}
## a_side tells on which side of the polyline's left normal (-dir.y, dir.x) province `a` lies.
var borders: Array[Dictionary] = []
const BORDER_SIMPLIFY_M := 45.0
## province id -> PackedInt32Array of indices into `borders`
var borders_by_province: Dictionary = {}

var _textures: Dictionary = {}


static func get_instance() -> WorldData:
	if _instance == null:
		_instance = WorldData.new()
		_instance.load_all()
	return _instance


static func is_available() -> bool:
	return FileAccess.file_exists(DIR + "/world_meta.json")


func load_all() -> bool:
	var t0 := Time.get_ticks_msec()
	var m: Variant = Defs.read_json(DIR + "/world_meta.json")
	if not (m is Dictionary):
		errors.append("world_meta.json missing")
		return false
	meta = m
	size_m = Vector2(float(meta["world_width_m"]), float(meta["world_height_m"]))
	cell_m = float(meta["cell_m"])
	fine_cell_m = float(meta["fine_cell_m"])
	grid_w = int(meta["grid_width"])
	grid_h = int(meta["grid_height"])
	fine_w = int(meta["fine_grid_width"])
	fine_h = int(meta["fine_grid_height"])

	height_bytes = _raster("height")
	height = height_bytes.to_float32_array()
	biome = _raster("biome")
	forest = _raster("forest")
	canopy = _raster("canopy") if (meta.get("rasters", {}) as Dictionary).has("canopy") else forest
	moisture = _raster("moisture")
	temperature = _raster("temperature")
	water = _raster("water")
	coast = _raster("coast")
	province_raster = _raster("province")
	_check_size("height", height.size(), grid_w * grid_h)
	_check_size("biome", biome.size(), grid_w * grid_h)
	_check_size("water", water.size(), fine_w * fine_h)
	_check_size("province", province_raster.size(), grid_w * grid_h * 2)

	var pj: Variant = Defs.read_json(DIR + "/provinces.json")
	if pj is Dictionary:
		for d in (pj as Dictionary).get("provinces", []):
			provinces.append(ProvinceGeo.from_dict(d))
	else:
		errors.append("provinces.json missing")
	var rj: Variant = Defs.read_json(DIR + "/rivers.json")
	if rj is Dictionary:
		for r in (rj as Dictionary).get("rivers", []):
			var xyw: Array = r["xyw"]
			var pts := PackedVector2Array()
			var ws := PackedFloat32Array()
			var i := 0
			while i + 2 < xyw.size():
				pts.append(Vector2(float(xyw[i]), float(xyw[i + 1])))
				ws.append(float(xyw[i + 2]))
				i += 3
			rivers.append({"id": int(r["id"]), "length_m": float(r["length_m"]), "max_width_m": float(r["max_width_m"]),
				"points": pts, "widths": ws})
	_load_borders()
	loaded = errors.is_empty()
	for e in errors:
		KDLog.error("world", e)
	KDLog.info("world", "official map loaded: %d provinces, %d rivers in %d ms" % [provinces.size(), rivers.size(), Time.get_ticks_msec() - t0])
	return loaded


func _raster(raster_name: String) -> PackedByteArray:
	var info: Dictionary = (meta.get("rasters", {}) as Dictionary).get(raster_name, {})
	if info.is_empty():
		errors.append("raster %s not described in meta" % raster_name)
		return PackedByteArray()
	var path := DIR + "/" + String(info["file"])
	if not FileAccess.file_exists(path):
		errors.append("raster file missing: %s" % path)
		return PackedByteArray()
	var comp := FileAccess.get_file_as_bytes(path)
	var raw := comp.decompress(int(info["uncompressed_bytes"]), FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != int(info["uncompressed_bytes"]):
		errors.append("raster %s: decompressed %d bytes, expected %d" % [raster_name, raw.size(), int(info["uncompressed_bytes"])])
	return raw


func _check_size(raster_name: String, actual: int, expected: int) -> void:
	if actual != expected:
		errors.append("raster %s has %d values, expected %d" % [raster_name, actual, expected])


# --- point queries -----------------------------------------------------------

func in_world(pos: Vector2) -> bool:
	return pos.x >= 0.0 and pos.y >= 0.0 and pos.x < size_m.x and pos.y < size_m.y


func _cell(pos: Vector2) -> int:
	var cx := clampi(int(pos.x / cell_m), 0, grid_w - 1)
	var cy := clampi(int(pos.y / cell_m), 0, grid_h - 1)
	return cy * grid_w + cx


func _fine_cell(pos: Vector2) -> int:
	var cx := clampi(int(pos.x / fine_cell_m), 0, fine_w - 1)
	var cy := clampi(int(pos.y / fine_cell_m), 0, fine_h - 1)
	return cy * fine_w + cx


## Bilinear elevation in metres.
func height_at(pos: Vector2) -> float:
	var fx := clampf(pos.x / cell_m - 0.5, 0.0, grid_w - 1.001)
	var fy := clampf(pos.y / cell_m - 0.5, 0.0, grid_h - 1.001)
	var x0 := int(fx)
	var y0 := int(fy)
	var tx := fx - x0
	var ty := fy - y0
	var i := y0 * grid_w + x0
	var a := lerpf(height[i], height[i + 1], tx)
	var b := lerpf(height[i + grid_w], height[i + grid_w + 1], tx)
	return lerpf(a, b, ty)


func biome_at(pos: Vector2) -> int:
	return biome[_cell(pos)]


func forest_at(pos: Vector2) -> float:
	return forest[_cell(pos)] / 255.0


## Bilinear tree cover 0..1 (canopy raster: what the map draws).
func canopy_smooth(pos: Vector2) -> float:
	return _bilinear_u8(canopy, pos)


## Bilinear moisture 0..1.
func moisture_smooth(pos: Vector2) -> float:
	return _bilinear_u8(moisture, pos)


## Bilinear forest density 0..1.
func forest_smooth(pos: Vector2) -> float:
	return _bilinear_u8(forest, pos)


func _bilinear_u8(src: PackedByteArray, pos: Vector2) -> float:
	var fx := clampf(pos.x / cell_m - 0.5, 0.0, grid_w - 1.001)
	var fy := clampf(pos.y / cell_m - 0.5, 0.0, grid_h - 1.001)
	var x0 := int(fx)
	var y0 := int(fy)
	var tx := fx - x0
	var ty := fy - y0
	var i := y0 * grid_w + x0
	var a := lerpf(src[i], src[i + 1], tx)
	var b := lerpf(src[i + grid_w], src[i + grid_w + 1], tx)
	return lerpf(a, b, ty) / 255.0


## The rivers as they are drawn close up, water and bank (keep equal to bank_widen in shaders/river.gdshader).
const RIVER_BANK_WIDEN := 1.34
const RIVER_GRID_M := 128.0
var _river_grid: Dictionary = {}          # Vector2i -> PackedInt32Array of segment ids
var _seg_a := PackedVector2Array()
var _seg_b := PackedVector2Array()
var _seg_ha := PackedFloat32Array()      # half width of the drawn ribbon at a, bank included
var _seg_hb := PackedFloat32Array()
var _rivers_indexed := false


## How far a point is from the edge of the nearest river ribbon, bank included: negative inside, INF when no river
## runs nearby. The water mask is made of 32 m cells and a river ten metres wide can fall between them: wells,
## roads and trees were placed in the river (Phase 17 check). This measures the river as the player sees it.
func river_clearance(pos: Vector2) -> float:
	if not _rivers_indexed:
		_index_rivers()
	var ids: Variant = _river_grid.get(Vector2i(int(floor(pos.x / RIVER_GRID_M)), int(floor(pos.y / RIVER_GRID_M))))
	if ids == null:
		return INF
	var best := INF
	for id: int in ids:
		var a := _seg_a[id]
		var b := _seg_b[id]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := pos.distance_to(a + ab * t) - lerpf(_seg_ha[id], _seg_hb[id], t)
		best = minf(best, d)
	return best


func _index_rivers() -> void:
	_rivers_indexed = true
	var margin := 12.0   # a cell also knows the rivers that pass just outside it
	for r in rivers:
		var pts: PackedVector2Array = r["points"]
		var ws: PackedFloat32Array = r["widths"]
		for i in pts.size() - 1:
			var id := _seg_a.size()
			_seg_a.append(pts[i])
			_seg_b.append(pts[i + 1])
			_seg_ha.append(_river_half(ws, i))
			_seg_hb.append(_river_half(ws, i + 1))
			var grow := maxf(_seg_ha[id], _seg_hb[id]) + margin
			var box := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(grow)
			for cy in range(int(floor(box.position.y / RIVER_GRID_M)), int(floor(box.end.y / RIVER_GRID_M)) + 1):
				for cx in range(int(floor(box.position.x / RIVER_GRID_M)), int(floor(box.end.x / RIVER_GRID_M)) + 1):
					var key := Vector2i(cx, cy)
					var list: PackedInt32Array = _river_grid.get(key, PackedInt32Array())
					list.append(id)
					_river_grid[key] = list


## The half width of the ribbon at a vertex, as RiverLayer builds it (tapered at the source), bank included.
static func _river_half(ws: PackedFloat32Array, i: int) -> float:
	var w := clampf(ws[i], 1.0, 254.0)
	if i < 3:
		w *= 0.4 + 0.2 * i
	return w * 0.5 * RIVER_BANK_WIDEN


func water_at(pos: Vector2) -> int:
	if not in_world(pos):
		return WATER_SEA
	return water[_fine_cell(pos)]


func is_land(pos: Vector2) -> bool:
	return water_at(pos) == WATER_LAND


## Province id at a position, or -1 over sea, lakes or outside the map.
func province_at(pos: Vector2) -> int:
	if not in_world(pos):
		return -1
	var w := water_at(pos)
	if w == WATER_SEA or w == WATER_LAKE:
		return -1
	var v := province_raster.decode_u16(_cell(pos) * 2)
	return -1 if v == PROVINCE_NONE else v


func province_geo(province_id: int) -> ProvinceGeo:
	if province_id < 0 or province_id >= provinces.size():
		return null
	return provinces[province_id]


func _load_borders() -> void:
	var bj: Variant = Defs.read_json(DIR + "/borders.json")
	if not (bj is Dictionary):
		errors.append("borders.json missing")
		return
	for b: Dictionary in (bj as Dictionary).get("borders", []):
		var flat: Array = b["pts"]
		var pts := PackedVector2Array()
		for i in range(0, flat.size() - 1, 2):
			pts.append(Vector2(float(flat[i]), float(flat[i + 1])))
		if pts.size() < 2:
			continue
		# the generator traces 64 m raster edges: straighten the stair steps, then round the corners
		pts = chaikin(simplify(pts, BORDER_SIMPLIFY_M), 2)
		var entry := {"a": int(b["a"]), "b": int(b["b"]), "type": StringName(b["type"]), "points": pts,
			"a_side": _side_of(pts, int(b["a"]), int(b["b"]))}
		var idx := borders.size()
		borders.append(entry)
		for pid: int in [entry["a"], entry["b"]]:
			if pid < 0:
				continue
			var list: PackedInt32Array = borders_by_province.get(pid, PackedInt32Array())
			list.append(idx)  # packed arrays are values: store the updated copy back
			borders_by_province[pid] = list


## Ramer–Douglas–Peucker simplification (iterative), end points kept.
static func simplify(pts: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return pts
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var seg: Vector2i = stack.pop_back()
		var a := pts[seg.x]
		var b := pts[seg.y]
		var best := -1
		var best_d := epsilon
		for i in range(seg.x + 1, seg.y):
			var d := Geometry2D.get_closest_point_to_segment(pts[i], a, b).distance_to(pts[i])
			if d > best_d:
				best_d = d
				best = i
		if best >= 0:
			keep[best] = 1
			stack.append(Vector2i(seg.x, best))
			stack.append(Vector2i(best, seg.y))
	var out := PackedVector2Array()
	for i in n:
		if keep[i] == 1:
			out.append(pts[i])
	return out


## Corner cutting that keeps the end points (junctions between three provinces stay shared).
static func chaikin(pts: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var cur := pts
	for it in iterations:
		if cur.size() < 3:
			return cur
		var out := PackedVector2Array([cur[0]])
		for i in cur.size() - 1:
			var p := cur[i]
			var q := cur[i + 1]
			if i > 0:
				out.append(p.lerp(q, 0.25))
			if i < cur.size() - 2:
				out.append(p.lerp(q, 0.75))
		out.append(cur[cur.size() - 1])
		cur = out
	return cur


func _side_of(pts: PackedVector2Array, a: int, b: int) -> int:
	# vote along the whole polyline: single probes near junctions or thin necks can land in a third province
	var votes := 0
	var n := pts.size()
	var step := maxi(1, (n - 1) / 16)
	for probe_m: float in [40.0, 100.0]:
		for i in range(1, n, step):
			var dir := (pts[i] - pts[i - 1]).normalized()
			if dir == Vector2.ZERO:
				continue
			var mid := (pts[i] + pts[i - 1]) * 0.5
			var nrm := Vector2(-dir.y, dir.x)
			var left := province_at(mid + nrm * probe_m)
			var right := province_at(mid - nrm * probe_m)
			if left == a or right == b:
				votes += 1
			if left == b or right == a:
				votes -= 1
	return 1 if votes >= 0 else -1


# --- GPU textures ------------------------------------------------------------

func texture(tex_name: StringName) -> Texture2D:
	if _textures.has(tex_name):
		return _textures[tex_name]
	var img: Image = null
	match tex_name:
		&"height":
			img = Image.create_from_data(grid_w, grid_h, false, Image.FORMAT_RF, height_bytes)
			img.generate_mipmaps()  # blurred levels give the shader valleys and crests
		&"canopy":
			img = Image.create_from_data(grid_w, grid_h, false, Image.FORMAT_R8, canopy)
		&"moisture":
			img = Image.create_from_data(grid_w, grid_h, false, Image.FORMAT_R8, moisture)
		&"biome":
			img = Image.create_from_data(grid_w, grid_h, false, Image.FORMAT_R8, biome)
		&"forest":
			img = Image.create_from_data(grid_w, grid_h, false, Image.FORMAT_R8, forest)
		&"water":
			img = Image.create_from_data(fine_w, fine_h, false, Image.FORMAT_R8, water)
		&"coast":
			img = Image.create_from_data(fine_w, fine_h, false, Image.FORMAT_R8, coast)
		&"province":
			img = Image.create_from_data(grid_w, grid_h, false, Image.FORMAT_RG8, province_raster)
		&"albedo_far":
			var t: Texture2D = load(DIR + "/albedo_far.png")
			_textures[tex_name] = t
			return t
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	_textures[tex_name] = tex
	return tex

