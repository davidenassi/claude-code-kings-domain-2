class_name DomainData
extends WorldData
## The static ground of the player's valley in LOCAL metres (Rebirth, Phase 1): the same queries as the continent
## (height, water, biome, canopy, rivers, deposits, province under a point), so the settlement, the placement rules
## and the renderers of the local map work on it unchanged — but they never see the continent.
##
## `continent_crop` valleys are cut out of the official rasters (aligned so every cell stays in place). Generated
## homelands (Phase 2) load their own high-resolution rasters from data/domains/<id>/ through `_load_homeland`.
##
## One valley is kept in memory: `of(world)` returns it and rebuilds it only when the valley changes (a new
## campaign in another place, a loaded save).

static var _cached: DomainData = null
static var _cached_key: String = ""

var domain: DomainState = null
## Continent province ids that have ground inside the valley (the home province first).
var provinces_inside: PackedInt32Array = PackedInt32Array()


## The ground of the world's valley, or null if the world has no valley (a world that never had a settlement).
static func of(world: WorldState) -> DomainData:
	if world == null or world.domain == null:
		return null
	return for_domain(world.domain)


static func for_domain(d: DomainState) -> DomainData:
	var key := d.key()
	if _cached != null and _cached_key == key:
		return _cached
	var dd := DomainData.new()
	dd.domain = d
	if d.is_crop():
		dd._build_crop(WorldData.get_instance())
	else:
		dd._load_homeland()
	_cached = dd
	_cached_key = key
	return dd


## Forgets the cached valley (tests that regenerate homelands).
static func clear_cache() -> void:
	_cached = null
	_cached_key = ""


# --- continent crop ---------------------------------------------------------------------------------

func _build_crop(wd: WorldData) -> void:
	var t0 := Time.get_ticks_msec()
	meta = {}
	size_m = domain.size_m
	cell_m = wd.cell_m
	fine_cell_m = wd.fine_cell_m
	feature_origin = domain.origin_global
	var cx0 := int(round(domain.origin_global.x / cell_m))
	var cy0 := int(round(domain.origin_global.y / cell_m))
	grid_w = int(round(size_m.x / cell_m))
	grid_h = int(round(size_m.y / cell_m))
	var fx0 := int(round(domain.origin_global.x / fine_cell_m))
	var fy0 := int(round(domain.origin_global.y / fine_cell_m))
	fine_w = int(round(size_m.x / fine_cell_m))
	fine_h = int(round(size_m.y / fine_cell_m))
	height_bytes = _crop(wd.height_bytes, wd.grid_w, wd.grid_h, cx0, cy0, grid_w, grid_h, 4)
	height = height_bytes.to_float32_array()
	biome = _crop(wd.biome, wd.grid_w, wd.grid_h, cx0, cy0, grid_w, grid_h, 1)
	forest = _crop(wd.forest, wd.grid_w, wd.grid_h, cx0, cy0, grid_w, grid_h, 1)
	canopy = _crop(wd.canopy, wd.grid_w, wd.grid_h, cx0, cy0, grid_w, grid_h, 1)
	moisture = _crop(wd.moisture, wd.grid_w, wd.grid_h, cx0, cy0, grid_w, grid_h, 1)
	temperature = _crop(wd.temperature, wd.grid_w, wd.grid_h, cx0, cy0, grid_w, grid_h, 1)
	province_raster = _crop(wd.province_raster, wd.grid_w, wd.grid_h, cx0, cy0, grid_w, grid_h, 2)
	water = _crop(wd.water, wd.fine_w, wd.fine_h, fx0, fy0, fine_w, fine_h, 1)
	coast = _crop(wd.coast, wd.fine_w, wd.fine_h, fx0, fy0, fine_w, fine_h, 1)
	# provinces: the same list (ids index it), every position moved into the valley
	var shift := -domain.origin_global
	var inside := {}
	for i in range(0, province_raster.size(), 2):
		var v := province_raster.decode_u16(i)
		if v != PROVINCE_NONE:
			inside[v] = true
	provinces_inside = PackedInt32Array([domain.home_province]) if domain.home_province >= 0 else PackedInt32Array()
	var ids := inside.keys()
	ids.sort()
	for pid: int in ids:
		if pid != domain.home_province:
			provinces_inside.append(pid)
	for g in wd.provinces:
		provinces.append(_moved_province(g, shift))
	# rivers: the ones that come near the valley, in local metres
	var box := Rect2(domain.origin_global, size_m).grow(600.0)
	for r in wd.rivers:
		var pts: PackedVector2Array = r["points"]
		var near := false
		for p in pts:
			if box.has_point(p):
				near = true
				break
		if not near:
			continue
		var moved := PackedVector2Array()
		for p in pts:
			moved.append(p + shift)
		rivers.append({"id": r["id"], "length_m": r["length_m"], "max_width_m": r["max_width_m"], "points": moved,
			"widths": (r["widths"] as PackedFloat32Array).duplicate()})
	loaded = true
	KDLog.info("world", "valley cut out of the continent at %s: %d x %d m, %d provinces, %d rivers in %d ms" % [
		str(domain.origin_global), int(size_m.x), int(size_m.y), provinces_inside.size(), rivers.size(),
		Time.get_ticks_msec() - t0])


## A rectangle of a row-major raster, `bpp` bytes per cell; cells outside the source read as zero
## (water/province rasters give "land"/"province 0" there: callers never ask outside the valley, see in_world).
static func _crop(src: PackedByteArray, sw: int, sh: int, x0: int, y0: int, w: int, h: int, bpp: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h * bpp)
	for y in h:
		var sy := y0 + y
		if sy < 0 or sy >= sh:
			continue
		var from_x := clampi(x0, 0, sw)
		var to_x := clampi(x0 + w, 0, sw)
		if to_x <= from_x:
			continue
		var row := src.slice((sy * sw + from_x) * bpp, (sy * sw + to_x) * bpp)
		var at := (y * w + (from_x - x0)) * bpp
		for i in row.size():
			out[at + i] = row[i]
	return out


static func _moved_province(g: ProvinceGeo, shift: Vector2) -> ProvinceGeo:
	var p := ProvinceGeo.new()
	p.id = g.id
	p.name = g.name
	p.center = g.center + shift
	p.centroid = g.centroid + shift
	p.area_km2 = g.area_km2
	p.inner_radius_m = g.inner_radius_m
	p.terrain = g.terrain
	p.biomes = g.biomes
	p.elevation_mean = g.elevation_mean
	p.elevation_max = g.elevation_max
	p.forest = g.forest
	p.fertility = g.fertility
	p.moisture = g.moisture
	p.temperature = g.temperature
	p.coastal = g.coastal
	p.has_river = g.has_river
	p.has_lake = g.has_lake
	p.culture = g.culture
	p.religion = g.religion
	p.neighbors = g.neighbors
	for dep in g.deposits:
		p.deposits.append({"type": dep["type"], "pos": (dep["pos"] as Vector2) + shift, "richness": dep["richness"]})
	return p


# --- generated homelands (Phase 2) -------------------------------------------------------------------

const HOMELANDS_DIR := "res://data/domains"


## The directory of a generated homeland (tools/domaingen/generate_domains.py).
static func homeland_dir(homeland_id: String) -> String:
	return "%s/%s" % [HOMELANDS_DIR, homeland_id]


## The meta of a generated homeland, or {} when it has not been generated.
static func homeland_meta(homeland_id: String) -> Dictionary:
	var path := homeland_dir(homeland_id) + "/domain_meta.json"
	if homeland_id == "" or not FileAccess.file_exists(path):
		return {}
	var m: Variant = Defs.read_json(path)
	return m if m is Dictionary else {}


## The homeland's own ground, at its own resolution (8 m relief, woods and biomes; 4 m water), in its own metres.
## Its trees are its own (no continent behind them: feature_origin stays zero).
func _load_homeland() -> void:
	var t0 := Time.get_ticks_msec()
	var dir := homeland_dir(domain.homeland)
	meta = homeland_meta(domain.homeland)
	if meta.is_empty():
		errors.append("homeland '%s' not generated (tools/domaingen/generate_domains.py)" % domain.homeland)
		loaded = false
		return
	size_m = Vector2(float(meta["world_width_m"]), float(meta["world_height_m"]))
	cell_m = float(meta["cell_m"])
	fine_cell_m = float(meta["fine_cell_m"])
	grid_w = int(meta["grid_width"])
	grid_h = int(meta["grid_height"])
	fine_w = int(meta["fine_grid_width"])
	fine_h = int(meta["fine_grid_height"])
	height_bytes = _raster_at(dir, "height")
	height = height_bytes.to_float32_array()
	designed_woods = true
	biome = _raster_at(dir, "biome")
	canopy = _raster_at(dir, "canopy")
	forest = canopy
	moisture = _raster_at(dir, "moisture")
	temperature = _raster_at(dir, "temperature")
	water = _raster_at(dir, "water")
	coast = _raster_at(dir, "coast")
	_check_size("height", height.size(), grid_w * grid_h)
	_check_size("water", water.size(), fine_w * fine_h)
	for r: Dictionary in meta.get("rivers", []):
		var xyw: Array = r["xyw"]
		var pts := PackedVector2Array()
		var ws := PackedFloat32Array()
		var i := 0
		while i + 2 < xyw.size():
			pts.append(Vector2(float(xyw[i]), float(xyw[i + 1])))
			ws.append(float(xyw[i + 2]))
			i += 3
		rivers.append({"id": int(r["id"]), "name": String(r.get("name", "")), "length_m": float(r["length_m"]),
			"max_width_m": float(r["max_width_m"]), "points": pts, "widths": ws})
	# the provinces of the continent keep their ids (the table is indexed by them) but have no ground here,
	# except the home province: the whole valley, with the homeland's own deposits
	var wd := WorldData.get_instance()
	for g in wd.provinces:
		var p := _moved_province(g, Vector2(-1.0e7, -1.0e7))
		p.deposits = []
		if g.id == domain.home_province:
			p.center = size_m * 0.5
			p.centroid = size_m * 0.5
			p.inner_radius_m = minf(size_m.x, size_m.y) * 0.35
			p.has_river = not rivers.is_empty()
			p.has_lake = not (meta.get("lakes", []) as Array).is_empty()
			for d: Dictionary in meta.get("deposits", []):
				p.deposits.append({"type": StringName(d["type"]), "pos": Vector2(float(d["x"]), float(d["y"])),
					"richness": float(d.get("richness", 1.0))})
		provinces.append(p)
	provinces_inside = PackedInt32Array([domain.home_province])
	loaded = errors.is_empty()
	for e in errors:
		KDLog.error("world", e)
	KDLog.info("world", "homeland %s loaded: %d x %d m, %d rivers, %d deposits in %d ms" % [domain.homeland,
		int(size_m.x), int(size_m.y), rivers.size(), (meta.get("deposits", []) as Array).size(), Time.get_ticks_msec() - t0])


func _raster_at(dir: String, raster_name: String) -> PackedByteArray:
	var info: Dictionary = (meta.get("rasters", {}) as Dictionary).get(raster_name, {})
	if info.is_empty():
		errors.append("homeland raster %s not described" % raster_name)
		return PackedByteArray()
	var path := dir + "/" + String(info["file"])
	if not FileAccess.file_exists(path):
		errors.append("homeland raster missing: %s" % path)
		return PackedByteArray()
	var raw := FileAccess.get_file_as_bytes(path).decompress(int(info["uncompressed_bytes"]), FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != int(info["uncompressed_bytes"]):
		errors.append("homeland raster %s: %d bytes, expected %d" % [raster_name, raw.size(), int(info["uncompressed_bytes"])])
	return raw


## A homeland is one province: every piece of dry ground of the valley belongs to the home province.
func province_at(pos: Vector2) -> int:
	if domain.is_crop():
		return super.province_at(pos)
	if not in_world(pos):
		return -1
	var w := water_at(pos)
	if w == WATER_SEA or w == WATER_LAKE:
		return -1
	return domain.home_province


## The founding site designed with the homeland (valley metres), or Vector2.INF for a crop.
func founding_site() -> Vector2:
	var s: Array = meta.get("founding_site", [])
	return Vector2(float(s[0]), float(s[1])) if s.size() == 2 else Vector2.INF


# --- textures ---------------------------------------------------------------------------------------

## The far albedo of the continent, cut to the valley (the local camera never zooms out far enough to show it,
## but the terrain shader samples it: it must be the valley's, not the continent's).
func texture(tex_name: StringName) -> Texture2D:
	if not domain.is_crop() and (tex_name == &"albedo_far" or tex_name == &"province") and not _textures.has(tex_name):
		# a homeland has no painted far albedo (the local camera never goes that far) and one province only
		var img := Image.create(1, 1, false, Image.FORMAT_RGB8 if tex_name == &"albedo_far" else Image.FORMAT_RG8)
		img.fill(Color(0.5, 0.55, 0.35) if tex_name == &"albedo_far" else Color(1.0, 1.0, 0.0))
		_textures[tex_name] = ImageTexture.create_from_image(img)
		return _textures[tex_name]
	if tex_name == &"albedo_far" and not _textures.has(tex_name):
		var src: Texture2D = WorldData.get_instance().texture(&"albedo_far")
		var tex: Texture2D = null
		if src and domain.is_crop():
			var img := src.get_image()
			if img:
				var wd := WorldData.get_instance()
				var ppm := img.get_width() / wd.size_m.x
				var region := Rect2i(Vector2i(domain.origin_global * ppm), Vector2i(size_m * ppm))
				tex = ImageTexture.create_from_image(img.get_region(region))
		_textures[tex_name] = tex
		return tex
	return super.texture(tex_name)
