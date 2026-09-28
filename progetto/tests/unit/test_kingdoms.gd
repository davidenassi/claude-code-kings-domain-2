extends KDTestCase

var wd: WorldData
var world: WorldState
var setup: StartSetup


func before_each() -> void:
	wd = WorldData.get_instance()
	world = WorldState.new()
	setup = StartSetup.apply(world)


func test_every_province_has_state() -> void:
	assert_eq(world.provinces.size(), wd.provinces.size())
	for i in world.provinces.size():
		assert_eq(world.provinces[i].id, i, "province state index")
	assert_eq(setup.warnings.size(), 0, "setup warnings: %s" % ", ".join(setup.warnings))


func test_player_starts_in_a_latin_frontier_valley() -> void:
	var player := world.player()
	assert_not_null(player, "player realm")
	if player == null:
		return
	assert_true(player.is_player)
	assert_eq(player.rank, KingdomState.Rank.SETTLEMENT)
	assert_eq(player.provinces.size(), 1, "one province at start")
	var g := wd.province_geo(player.capital)
	assert_eq(g.culture, &"latin")
	assert_eq(g.religion, &"catholic")
	assert_true(g.has_river, "river in the start valley")
	assert_true(g.forest >= 0.3 and g.fertility >= 0.45, "forest and fertile land")
	assert_eq(world.provinces[player.capital].population, 6, "six founders, no king (Phase 15)")
	# grace: no other realm within two steps
	for pid in setup.provinces_within_steps(player.capital, 2):
		if pid != player.capital:
			assert_true(world.provinces[pid].is_free(), "province %d near the start must be free" % pid)


func test_mixed_world_of_kingdoms_lordships_and_free_lands() -> void:
	var kingdoms := 0
	var lordships := 0
	var owned := 0
	for k in world.kingdoms:
		if k.is_player:
			continue
		if k.rank == KingdomState.Rank.KINGDOM:
			kingdoms += 1
			assert_true(k.provinces.size() >= 5 and k.provinces.size() <= 15, "%s size %d" % [k.name, k.provinces.size()])
		else:
			lordships += 1
			assert_true(k.provinces.size() >= 1 and k.provinces.size() <= 4, "%s size %d" % [k.name, k.provinces.size()])
		owned += k.provinces.size()
	assert_true(kingdoms >= 4 and kingdoms <= 6, "formed kingdoms: %d" % kingdoms)
	assert_true(lordships >= 8 and lordships <= 12, "lordships: %d" % lordships)
	assert_true(owned < wd.provinces.size() / 2, "most of the continent is free land")


func test_realms_are_contiguous_and_capital_owned() -> void:
	for k in world.kingdoms:
		assert_eq(world.provinces[k.capital].owner, k.id, "%s owns its capital" % k.name)
		var members := {}
		for pid in k.provinces:
			members[pid] = true
		var seen := {k.capital: true}
		var stack: Array[int] = [k.capital]
		while not stack.is_empty():
			var id: int = stack.pop_back()
			for n in wd.provinces[id].neighbors:
				var q := int(n["id"])
				if members.has(q) and not seen.has(q):
					seen[q] = true
					stack.append(q)
		assert_eq(seen.size(), k.provinces.size(), "%s is contiguous" % k.name)


func test_setup_is_deterministic() -> void:
	var other := WorldState.new()
	StartSetup.apply(other)
	assert_eq(JSON.stringify(other.to_dict()["provinces"]), JSON.stringify(world.to_dict()["provinces"]))
	assert_eq(JSON.stringify(other.to_dict()["kingdoms"]), JSON.stringify(world.to_dict()["kingdoms"]))


func test_no_degenerate_provinces() -> void:
	for g in wd.provinces:
		assert_true(g.area_km2 >= 2.0, "province %d too small" % g.id)
		assert_true(g.neighbors.size() >= 1, "province %d isolated" % g.id)
		assert_true(g.name != "", "province %d without name" % g.id)


func test_transfer_updates_owner_lists_and_emits() -> void:
	var s := GameSession.create_new({"campaign_seed": 3})
	var k := s.world.kingdoms[1]
	var target := -1
	for n in wd.provinces[k.capital].neighbors:
		if s.world.provinces[int(n["id"])].owner != k.id:
			target = int(n["id"])
			break
	if target < 0:
		for p in s.world.provinces:
			if p.is_free():
				target = p.id
				break
	var got := []
	var cb := func(pid: int, old: int, new_owner: int, _r: StringName) -> void: got.append([pid, old, new_owner])
	EventBus.province_owner_changed.connect(cb)
	var before := k.provinces.size()
	var old_owner := s.world.provinces[target].owner
	var res := s.submit(TransferProvinceCommand.create(target, k.id))
	EventBus.province_owner_changed.disconnect(cb)
	assert_true(res.success, res.reason)
	assert_eq(s.world.provinces[target].owner, k.id)
	assert_eq(k.provinces.size(), before + 1)
	assert_eq(got.size(), 1, "one owner change signal")
	if old_owner >= 0:
		assert_false(s.world.kingdoms[old_owner].provinces.has(target), "removed from the old owner")
	assert_false(s.submit(TransferProvinceCommand.create(target, k.id)).success, "same owner rejected")
	# borders between the two provinces are now internal to the realm
	for n in wd.provinces[target].neighbors:
		var q := int(n["id"])
		var expected := BorderClassifier.PROVINCE if s.world.provinces[q].owner == k.id else BorderClassifier.REALM
		assert_eq(BorderClassifier.classify(s.world, target, q), expected, "border %d-%d" % [target, q])


func test_save_roundtrip_keeps_political_map() -> void:
	var s := GameSession.create_new({"campaign_seed": 9})
	var data := SaveSystem.build_save_data(s)
	var loaded := SaveSystem.session_from_data(JSON.parse_string(JSON.stringify(data)))
	assert_not_null(loaded)
	if loaded == null:
		return
	assert_eq(loaded.world.kingdoms.size(), s.world.kingdoms.size())
	assert_eq(loaded.world.player_kingdom, s.world.player_kingdom)
	for i in s.world.kingdoms.size():
		assert_eq(loaded.world.kingdoms[i].provinces, s.world.kingdoms[i].provinces, "province list %d" % i)
		assert_eq(loaded.world.kingdoms[i].coat_of_arms.to_dict(), s.world.kingdoms[i].coat_of_arms.to_dict(), "arms %d" % i)


func test_v1_save_migrates_and_gets_political_map() -> void:
	var s := GameSession.create_new({"campaign_seed": 11})
	var data := SaveSystem.build_save_data(s)
	data["header"]["save_version"] = 1
	(data["world"] as Dictionary).erase("provinces")
	(data["world"] as Dictionary).erase("kingdoms")
	var loaded := SaveSystem.session_from_data(data)
	assert_not_null(loaded)
	if loaded:
		assert_eq(loaded.world.provinces.size(), wd.provinces.size(), "setup rebuilt for old saves")
		assert_true(loaded.world.player_kingdom >= 0)


func test_coat_of_arms_deterministic_and_tinctured() -> void:
	var a := CoatOfArms.generate("Casa Hohenrath", &"germanic")
	var b := CoatOfArms.generate("Casa Hohenrath", &"germanic")
	assert_eq(a.to_dict(), b.to_dict())
	assert_true(a.field != a.second, "two tinctures")
	var shapes := {}
	for c in [&"germanic", &"slavic", &"arab"]:
		var arms := CoatOfArms.generate("x", c)
		shapes[arms.shape] = true
		assert_true(arms.unit_shield().size() >= 6, "shield outline")
		assert_false(Geometry2D.triangulate_polygon(arms.unit_shield()).is_empty(), "shield %s triangulates" % arms.shape)
	assert_eq(shapes.size(), 3, "culture shapes")


func test_map_modes_color_every_province() -> void:
	var s := GameSession.create_new({"campaign_seed": 5})
	for mode in MapModes.ids():
		var img := MapModes.build_image(mode, s.world)
		assert_not_null(img, "mode %s" % mode)
		if img:
			assert_true(img.get_width() >= wd.provinces.size(), "lookup covers all provinces")
	var player := s.world.player()
	var pol := MapModes.province_color(&"political", s.world, player.capital)
	assert_true(pol.a > 0.0, "owned province tinted")
	var free_id := -1
	for p in s.world.provinces:
		if p.is_free():
			free_id = p.id
			break
	assert_eq(MapModes.province_color(&"political", s.world, free_id).a, 0.0, "free land not tinted")


func test_borders_oriented_and_outline_built() -> void:
	assert_true(wd.borders.size() > 500, "borders loaded")
	# on every border, points probed on the a side must mostly fall in province a
	var hits := 0
	var total := 0
	for b in wd.borders:
		var pts: PackedVector2Array = b["points"]
		for i in range(1, pts.size(), maxi(1, pts.size() / 6)):
			var dir := (pts[i] - pts[i - 1]).normalized()
			if dir == Vector2.ZERO:
				continue
			var probe := (pts[i] + pts[i - 1]) * 0.5 + Vector2(-dir.y, dir.x) * float(b["a_side"]) * 50.0
			total += 1
			var pid := wd.province_at(probe)
			if pid == int(b["a"]):
				hits += 1
			elif pid == int(b["b"]):
				hits -= 1
	assert_true(float(hits) / float(total) > 0.8, "border sides resolved (%d / %d)" % [hits, total])
	var sl := SelectionLayer.new()
	sl._wd = wd
	var mesh := sl.outline_mesh(world.player().capital, true)
	assert_not_null(mesh, "outline mesh")
	if mesh:
		assert_eq(mesh.get_surface_count(), 1)
	sl.free()


func test_inspector_shows_selected_province_facts() -> void:
	Session.start_new({"campaign_seed": 21})
	var world := Session.current.world
	var root := Engine.get_main_loop() as SceneTree
	var inspector := ProvinceInspector.new()
	root.root.add_child(inspector)
	var pid := world.kingdoms[1].capital
	inspector.show_province(pid)
	var texts := PackedStringArray()
	for c in inspector.find_children("*", "Label", true, false):
		texts.append((c as Label).text)
	var all := "\n".join(texts)
	assert_true(inspector.visible, "inspector visible")
	assert_true(all.contains(wd.province_geo(pid).name), "province name shown")
	assert_true(all.contains(world.kingdoms[1].name), "owner shown")
	assert_true(all.contains(ProvinceInspector.thousands(world.provinces[pid].population)), "population shown")
	inspector.show_province(-1)
	assert_false(inspector.visible, "hidden when nothing is selected")
	inspector.free()
	Session.end()

