extends KDTestCase

var wd: WorldData


func before_each() -> void:
	wd = WorldData.get_instance()


func test_loads_without_errors() -> void:
	assert_true(wd.loaded, "world data not loaded: %s" % ", ".join(wd.errors))
	assert_eq(wd.grid_w * int(wd.cell_m), int(wd.size_m.x), "grid width matches world size")
	assert_eq(wd.fine_w, wd.grid_w * 2)
	assert_eq(wd.height.size(), wd.grid_w * wd.grid_h)


func test_province_ids_sequential_and_counted() -> void:
	assert_eq(wd.provinces.size(), int(wd.meta.get("province_count", -1)))
	assert_true(wd.provinces.size() >= 300, "the continent needs several hundred provinces")
	for i in wd.provinces.size():
		assert_eq(wd.provinces[i].id, i, "province index")


func test_neighbors_are_symmetric() -> void:
	var bad := 0
	for p in wd.provinces:
		for n in p.neighbors:
			var q := wd.province_geo(int(n["id"]))
			if q == null or not q.neighbor_ids().has(p.id):
				bad += 1
	assert_eq(bad, 0, "asymmetric neighbours")


func test_every_province_reachable_by_land() -> void:
	var seen := {0: true}
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var id: int = stack.pop_back()
		for n in wd.provinces[id].neighbors:
			var q := int(n["id"])
			if not seen.has(q):
				seen[q] = true
				stack.append(q)
	assert_eq(seen.size(), wd.provinces.size(), "one continent: every province reachable over land")


func test_province_centers_lie_in_their_province() -> void:
	var ok := 0
	for p in wd.provinces:
		if wd.province_at(p.center) == p.id:
			ok += 1
	assert_true(ok >= int(wd.provinces.size() * 0.98), "centres inside own province: %d/%d" % [ok, wd.provinces.size()])


func test_sea_surrounds_the_continent() -> void:
	for pos in [Vector2(10, 10), Vector2(wd.size_m.x - 10, 10), Vector2(10, wd.size_m.y - 10), wd.size_m - Vector2(10, 10)]:
		assert_eq(wd.water_at(pos), WorldData.WATER_SEA, "corner %s is sea" % pos)
		assert_true(wd.height_at(pos) < 0.0, "sea floor below zero at %s" % pos)
		assert_eq(wd.province_at(pos), -1)


func test_mountain_provinces_are_high() -> void:
	var mountains := 0
	for p in wd.provinces:
		if p.terrain == &"mountains":
			mountains += 1
			assert_true(p.elevation_max > 900.0, "mountain province %s max elevation %f" % [p.name, p.elevation_max])
	assert_true(mountains > 0, "the map has mountain provinces")


func test_cultures_religions_names_valid() -> void:
	var names := {}
	for p in wd.provinces:
		assert_true(Defs.has_def("cultures", p.culture), "culture %s of %s" % [p.culture, p.name])
		assert_true(Defs.has_def("religions", p.religion), "religion %s of %s" % [p.religion, p.name])
		assert_false(names.has(p.name), "duplicate province name %s" % p.name)
		names[p.name] = true
	var cultures := {}
	var religions := {}
	for p in wd.provinces:
		cultures[p.culture] = true
		religions[p.religion] = true
	assert_eq(cultures.size(), 6, "all six cultures on the map")
	assert_eq(religions.size(), 4, "all four religions on the map")


func test_rivers_inside_world() -> void:
	assert_true(wd.rivers.size() > 50, "rivers present")
	for r in wd.rivers:
		for pt: Vector2 in r["points"]:
			if not wd.in_world(pt):
				fail("river %d leaves the world at %s" % [r["id"], pt])
				return


func test_textures_build() -> void:
	for t in [&"height", &"biome", &"forest", &"water", &"coast", &"province"]:
		var tex := wd.texture(t)
		assert_not_null(tex, "texture %s" % t)
	assert_not_null(wd.texture(&"albedo_far"), "albedo")


func test_mountain_sprites_placed_on_high_land() -> void:
	var meta: Variant = Defs.read_json(MountainLayer.ATLAS_DIR + "/mountain_atlas.json")
	var placement: Variant = Defs.read_json(MountainLayer.PLACEMENT)
	assert_true(meta is Dictionary and placement is Dictionary, "mountain atlas and placement exist")
	if not (meta is Dictionary and placement is Dictionary):
		return
	var items: Array = placement["items"]
	assert_true(items.size() >= 50, "the official map has mountain ranges")
	var bad := 0
	var last_y := -INF
	for it: Array in items:
		var pos := Vector2(float(it[0]), float(it[1]))
		if not wd.is_land(pos) or wd.height_at(pos) < 600.0 or pos.y < last_y:
			bad += 1
		last_y = pos.y
	assert_eq(bad, 0, "mountains on high land, sorted by y")
	var mm := MountainLayer.build_multimesh(meta, items)
	assert_eq(mm.instance_count, items.size(), "every placement has a sprite class")


func test_canopy_has_clearings_and_follows_forests() -> void:
	assert_eq(wd.canopy.size(), wd.grid_w * wd.grid_h, "canopy raster size")
	var forest_cells := 0
	var cleared := 0
	var outside := 0
	for i in range(0, wd.forest.size(), 7):
		if wd.forest[i] > 150:
			forest_cells += 1
			if wd.canopy[i] < 40:
				cleared += 1
		elif wd.forest[i] == 0 and wd.canopy[i] > 0:
			outside += 1
	assert_true(forest_cells > 1000, "sampled forests")
	var share := float(cleared) / float(forest_cells)
	assert_true(share > 0.03 and share < 0.35, "clearings inside dense forests: %.2f" % share)
	assert_eq(outside, 0, "no trees where the forest density is zero")

