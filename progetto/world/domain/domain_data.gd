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

func _load_homeland() -> void:
	errors.append("homeland '%s': generated homelands arrive with Phase 2" % domain.homeland)
	loaded = false


# --- textures ---------------------------------------------------------------------------------------

## The far albedo of the continent, cut to the valley (the local camera never zooms out far enough to show it,
## but the terrain shader samples it: it must be the valley's, not the continent's).
func texture(tex_name: StringName) -> Texture2D:
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
