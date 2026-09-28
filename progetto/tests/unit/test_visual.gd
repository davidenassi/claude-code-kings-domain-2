extends KDTestCase
## Phase 18: what the map draws must stay true to the world. Gardens and paths are only drawings, but a garden
## over a house or a path through the river would be a lie told by the picture.


func after_each() -> void:
	Session.end()


func _grown_village() -> GameSession:
	var s := Session.start_new({"campaign_seed": 1818})
	var id := s.world.settlements[0].id
	SettlementPlanner.place_starter_village(s, id)
	for month in 18:
		SettlementPlanner.lord_month(s, id)
		s.advance_days(30)
	return s


func test_gardens_stand_beside_the_houses_and_never_on_anything_else() -> void:
	var s := _grown_village()
	var world := s.world
	var wd := WorldData.get_instance()
	var yards := SettlementLayer.yards(world)
	var houses := 0
	for b: BuildingState in world.buildings.values():
		if b.def_id == &"house" and b.is_active():
			houses += 1
	assert_true(houses > 0, "the village has houses (%d)" % houses)
	assert_true(yards.size() > 0, "and some of them have a garden (%d of %d)" % [yards.size(), houses])
	for r in yards:
		for b: BuildingState in world.buildings.values():
			if b.is_road():
				assert_false(b.covers(r.get_center(), 0.5), "a garden is never on a road")
			else:
				assert_false(b.rect().intersects(r), "a garden never covers a building (%s)" % b.def().display_name)
		assert_eq(wd.water_at(r.get_center()), WorldData.WATER_LAND, "a garden is on dry land")
		assert_true(wd.river_clearance(r.get_center()) >= 1.5, "and not on the river bank")
	for i in yards.size():
		for j in range(i + 1, yards.size()):
			assert_false(yards[i].intersects(yards[j]), "two gardens never overlap")


func test_the_worn_paths_link_the_doors_and_never_cross_the_river() -> void:
	var s := _grown_village()
	var world := s.world
	var wd := WorldData.get_instance()
	var st := world.settlements[0]
	var paths := SettlementLayer.footpaths(world, st)
	assert_true(paths.size() > 0, "the doors are linked by paths (%d)" % paths.size())
	for edge: Array in paths:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		assert_true(a.distance_to(b) < 140.0, "a path is never longer than a short walk")
		for k in 11:
			assert_true(wd.river_clearance(a.lerp(b, float(k) / 10.0)) >= 0.5, "a path never crosses the river")
	assert_eq(SettlementLayer.road_level(10), 0, "a hamlet has tracks")
	assert_eq(SettlementLayer.road_level(80), 1, "a village dirt roads")
	assert_eq(SettlementLayer.road_level(400), 2, "a town gravel roads")


func test_settlements_seen_from_afar_have_their_own_band_and_their_names_step_aside() -> void:
	var s := _grown_village()
	assert_true(SettlementMarks.fade_at(0.5) < 0.01, "among the houses the real sprites are drawn, not the marks")
	assert_true(SettlementMarks.fade_at(6.0) > 0.99, "at the height of a province the marks carry the village")
	assert_true(SettlementMarks.fade_at(60.0) < 0.01, "and at the height of the continent the pins take over")
	var st := s.world.settlements[0]
	var r := MapLabels.built_radius(s.world, st)
	var far := 0.0
	for b in s.world.buildings_of(st.id):
		far = maxf(far, b.pos.distance_to(st.center) + maxf(b.def().footprint.x, b.def().footprint.y))
	assert_true(r > 5.0 and r <= far, "the pin and the name keep to the edge of the houses (%.0f m of %.0f)" % [r, far])


func test_the_woods_have_glades_that_are_always_the_same() -> void:
	var lo := 1.0
	var hi := 0.0
	for i in 400:
		var p := Vector2(1000.0 + i * 97.0, 2000.0 + (i % 23) * 131.0)
		var v := VegetationLayer.value_noise(p, 470.0, 913)
		assert_true(v >= 0.0 and v <= 1.0, "the noise stays between 0 and 1")
		assert_eq(v, VegetationLayer.value_noise(p, 470.0, 913), "and gives the same wood every time")
		lo = minf(lo, v)
		hi = maxf(hi, v)
	assert_true(hi - lo > 0.5, "it really varies: thick woods and glades (%.2f..%.2f)" % [lo, hi])


func test_the_news_is_one_line_and_opens_with_a_click() -> void:
	Session.start_new({"campaign_seed": 1819})
	var stack := NotificationStack.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(stack)
	EventBus.notify("Un nuovo abitante", "Lucia è nata a Valverde.", &"birth")
	EventBus.notify("Guerra", "Il Regno di Waldmark ci dichiara guerra.", &"war")
	var card := stack.get_child(0) as Control
	var detail := card.find_child("Detail", true, false) as Control
	assert_false(detail.visible, "a piece of news is one line: icon, title, how long ago")
	assert_true(card.tooltip_text.contains("Waldmark"), "the whole text is in the tooltip")
	assert_true(card.find_children("*", "TextureRect", true, false).size() > 0, "with the painted icon of its kind")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	card.gui_input.emit(click)
	assert_true(detail.visible, "a click opens the text under the title")
	assert_eq(NotificationStack.when_text(0), "oggi", "news of today says so")
	assert_eq(NotificationStack.when_text(5), "5 giorni fa", "and older news how long ago")
	(Engine.get_main_loop() as SceneTree).root.remove_child(stack)
	stack.free()


## World art pass: the picture departs from the simulation (a building nudged and turned, a field in strips, props
## around the doors) but always the same way — nothing moves or changes after a save and a load.
func test_the_picture_of_the_world_is_the_same_after_a_reload() -> void:
	var s := _grown_village()
	var world := s.world
	var before := {}
	var fields := {}
	for b: BuildingState in world.buildings.values():
		if b.is_road():
			continue
		before[b.id] = SettlementLayer.visual_of(b)
		if b.def().work_type() == &"farm":
			fields[b.id] = FieldPainter.layout(b)["strips"].size()
	var props_before := SettlementProps.props(world)
	var back := WorldState.from_dict(world.to_dict())
	FieldPainter.clear_cache()
	for id: int in before.keys():
		var b := back.building(id)
		assert_true(b != null, "the building %d is still there" % id)
		var look := SettlementLayer.visual_of(b)
		assert_eq(look["offset"], before[id]["offset"], "the same small shift after a reload")
		assert_eq(look["turn"], before[id]["turn"], "the same turn")
		assert_eq(look["scale"], before[id]["scale"], "the same scale")
		var fp := b.def().footprint
		assert_true((look["offset"] as Vector2).length() <= minf(fp.x, fp.y) * 0.06, "the shift stays small")
		assert_true(absf(float(look["turn"])) <= deg_to_rad(2.6), "a couple of degrees at most")
		assert_true(absf(float(look["scale"]) - 1.0) <= 0.051, "the scale within five per cent")
	for id: int in fields.keys():
		assert_eq(FieldPainter.layout(back.building(id))["strips"].size(), fields[id], "the same strips in the field")
	var props_after := SettlementProps.props(back)
	assert_eq(props_after.size(), props_before.size(), "the same props around the buildings (%d)" % props_before.size())
	for i in props_before.size():
		assert_eq(props_after[i][1], props_before[i][1], "the same prop")
		assert_eq(props_after[i][2], props_before[i][2], "in the same place")
	# the props never stand on a building, a garden or a road
	for p: Array in props_before:
		for b: BuildingState in world.buildings.values():
			if b.is_road():
				assert_false(b.covers(p[2], 0.3), "a prop is never on a road")
			else:
				assert_false(b.rect().has_point(p[2]), "a prop is never inside a building (%s)" % b.def().display_name)


## The woods keep their trees on average (the shape of glades and cores only moves them around): the wood a
## village can cut does not change with the art.
func test_the_woods_have_a_shape_and_keep_their_trees() -> void:
	var s := Session.start_new({"campaign_seed": 1})
	var wd := WorldData.get_instance()
	var home := s.world.settlements[0].center
	var total := 0
	for off: Vector2 in [Vector2(-600, -600), Vector2(-2000, -1300), Vector2(1500, -600), Vector2(-600, 1500)]:
		for f in LocalFeatures.trees_in_rect(wd, Rect2(home + off, Vector2(1200, 1200))):
			if f["kind"] == LocalFeatures.KIND_TREE:
				total += 1
	# before the world art pass these four squares held 24099 trees
	assert_true(absf(float(total) - 24099.0) / 24099.0 < 0.08, "the woods keep their trees within 8%% (%d)" % total)
	var lo := INF
	var hi := 0.0
	for i in 60:
		var g := LocalFeatures.glade_factor(home + Vector2(i * 173.0, i * 97.0))
		lo = minf(lo, g)
		hi = maxf(hi, g)
	assert_true(hi / maxf(lo, 0.01) > 2.5, "and they have glades and thick cores (%.2f..%.2f)" % [lo, hi])

