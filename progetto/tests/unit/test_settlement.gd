extends KDTestCase

var wd: WorldData


func before_each() -> void:
	wd = WorldData.get_instance()


static func find_spot(session: GameSession, def_id: StringName, near: Vector2, min_r: float = 30.0, prefer_cleared: bool = false) -> Vector2:
	return SettlementPlanner.find_spot(session, session.world.settlements[0].id, def_id, near, min_r, prefer_cleared)


func _felled_standing_trees_near(session: GameSession, center: Vector2, radius: float) -> int:
	var n := 0
	for t in LocalFeatures.trees_in_rect(wd, Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false):
		if session.world.terrain.has_stump(t["key"]):
			n += 1
	return n


func test_start_settlement_six_founders_and_no_king() -> void:
	var s := GameSession.create_new({"campaign_seed": 101})
	var w := s.world
	assert_eq(w.settlements.size(), 1, "one settlement")
	var st := w.settlements[0]
	assert_eq(st.kingdom, w.player_kingdom)
	assert_eq(wd.province_at(st.center), w.player().capital, "settlement in the start valley")
	var people := w.people_of(st.id)
	assert_eq(people.size(), 6, "six founders")
	assert_eq(people.filter(func(p: PersonState) -> bool: return p.female).size(), 3, "three women")
	assert_eq(people.filter(func(p: PersonState) -> bool: return not p.female).size(), 3, "three men")
	assert_eq(people.filter(func(p: PersonState) -> bool: return p.is_king).size(), 0, "no king")
	var surnames := {}
	for p in people:
		assert_true(p.name != "", "named")
		assert_true(p.age_years(0) >= 16, "adult")
		assert_true(p.spouse < 0, "%s arrives alone" % p.name)
		var f := w.family(p.family)
		assert_not_null(f, "%s has a family" % p.name)
		if f:
			assert_true(f.founding, "a founding family")
			surnames[f.name] = true
	assert_eq(surnames.size(), 6, "six surnames: six founding families")
	var k := w.player()
	assert_false(k.monarchy_founded, "no monarchy yet")
	assert_null(w.ruler_of(k.id), "no sovereign")
	assert_eq(k.house, "", "no dynasty")
	assert_eq(k.rank, KingdomState.Rank.SETTLEMENT, "a settlement, not a kingdom")
	assert_true(k.name.begins_with("Comunità"), "the community is called %s" % k.name)
	var defs := w.buildings_of(st.id).map(func(b: BuildingState) -> StringName: return b.def_id)
	assert_false(defs.has(&"keep"), "no keep: nobody to live in it")
	assert_true(defs.has(&"camp_store") and defs.has(&"shelter"), "a common fire and a shelter")
	assert_eq(st.amount(&"wood"), int(Defs.balance("settlement")["start_stock"]["wood"]))
	assert_eq(st.amount(&"bread"), int(Defs.balance("settlement")["start_stock"]["bread"]))
	assert_true(w.chronicle.any(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "founding_arrival"),
		"the chronicle opens with the arrival of the founders")
	for b in w.buildings_of(st.id):
		for t in LocalFeatures.trees_in_rect(wd, b.rect()):
			assert_true(w.terrain.is_felled(t["key"]), "no tree inside %s" % b.def_id)


func test_placement_reasons() -> void:
	var s := GameSession.create_new({"campaign_seed": 102})
	var w := s.world
	var st := w.settlements[0]
	var house := Defs.building(&"house")
	var keep := w.buildings_of(st.id)[0]
	var r := Placement.check(w, st, house, keep.pos)
	assert_false(bool(r["ok"]), "overlap refused")
	assert_true(String(r["reason"]).contains("occupato"), String(r["reason"]))
	var far := wd.province_geo(w.kingdoms[1].capital).center
	r = Placement.check(w, st, house, far)
	assert_false(bool(r["ok"]))
	assert_true(String(r["reason"]).contains("territorio") or String(r["reason"]).contains("acqua"), String(r["reason"]))
	var spot := find_spot(s, &"house", keep.pos)
	assert_true(spot != Vector2.INF, "a house fits near the keep")
	st.stock[&"wood"] = 3
	r = Placement.check(w, st, house, spot)
	assert_false(bool(r["ok"]))
	assert_true(String(r["reason"]).begins_with("Mancano materiali"), String(r["reason"]))
	var cmd := PlaceBuildingCommand.create(st.id, &"house", spot)
	assert_false(s.submit(cmd).success, "command refused with the same reason")
	assert_false(Placement.check(w, st, Defs.building(&"keep"), spot)["ok"], "keep not buildable")


func test_woodcutter_fells_visible_trees_and_house_rises_on_cleared_land() -> void:
	var s := GameSession.create_new({"campaign_seed": 103})
	var w := s.world
	var st := w.settlements[0]
	var keep := w.buildings_of(st.id)[0]
	var spot := find_spot(s, &"woodcutter", keep.pos, 40.0)
	assert_true(spot != Vector2.INF, "woodcutter spot")
	var res := s.submit(PlaceBuildingCommand.create(st.id, &"woodcutter", spot))
	assert_true(res.success, res.reason)
	var wc := w.building(int(res.data["building"]))
	var days := 0
	while not wc.is_active() and days < 40:
		s.advance_days(1)
		days += 1
	assert_true(wc.is_active(), "woodcutter built within 40 days (took %d)" % days)
	assert_eq(int(wc.delivered.get(&"wood", 0)), 16, "materials delivered")
	var wood_before := st.amount(&"wood")
	var stumps_before := _felled_standing_trees_near(s, wc.pos, 110.0)
	s.advance_days(12)
	var stumps_after := _felled_standing_trees_near(s, wc.pos, 110.0)
	assert_true(stumps_after > stumps_before + 5, "trees felled around the woodcutter (%d -> %d)" % [stumps_before, stumps_after])
	assert_true(st.amount(&"wood") > wood_before + 15, "wood reaches the stores (%d -> %d)" % [wood_before, st.amount(&"wood")])
	var cutters := w.people_of(st.id).filter(func(p: PersonState) -> bool: return p.job == &"woodcutter")
	assert_eq(cutters.size(), 2, "two woodcutters")

	# a house on land the woodcutters cleared
	var house_spot := find_spot(s, &"house", wc.pos, 12.0, true)
	assert_true(house_spot != Vector2.INF, "house spot")
	res = s.submit(PlaceBuildingCommand.create(st.id, &"house", house_spot))
	assert_true(res.success, res.reason)
	var house := w.building(int(res.data["building"]))
	days = 0
	while not house.is_active() and days < 40:
		s.advance_days(1)
		days += 1
	assert_true(house.is_active(), "house built (%d days)" % days)
	for t in LocalFeatures.trees_in_rect(wd, house.rect()):
		assert_eq(int(w.terrain.felled.get(t["key"], 99)), TerrainDeltas.CLEARED_FOR_GOOD, "ground under the house cleared for good")
	for p: PersonState in w.people.values():
		assert_true(p.carrying.is_empty() or int(p.carrying["amount"]) > 0, "no empty loads")


func test_save_load_keeps_felled_trees_buildings_and_continues_identically() -> void:
	var s := GameSession.create_new({"campaign_seed": 104})
	var st := s.world.settlements[0]
	var keep := s.world.buildings_of(st.id)[0]
	s.submit(PlaceBuildingCommand.create(st.id, &"woodcutter", find_spot(s, &"woodcutter", keep.pos, 40.0)))
	s.advance_days(25)
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s)))
	var loaded := SaveSystem.session_from_data(data)
	assert_not_null(loaded)
	if loaded == null:
		return
	assert_eq(loaded.world.terrain.felled.size(), s.world.terrain.felled.size(), "felled trees kept")
	assert_eq(loaded.world.buildings.size(), s.world.buildings.size(), "buildings kept")
	assert_eq(loaded.world.people.size(), s.world.people.size(), "the founders cross the save")
	assert_eq(loaded.world.families.size(), s.world.families.size(), "and so do their families")
	s.advance_days(6)
	loaded.advance_days(6)
	var a := s.world.settlements[0]
	var b := loaded.world.settlements[0]
	assert_eq(b.stock, a.stock, "same stores after continuing")
	assert_eq(loaded.world.terrain.felled.size(), s.world.terrain.felled.size(), "same felling after continuing")
	for pid: int in s.world.people.keys():
		assert_true(loaded.world.people[pid].seg_to.distance_to(s.world.people[pid].seg_to) < 0.01, "same position of %d" % pid)


func test_two_years_of_settlement_life() -> void:
	var s := GameSession.create_new({"campaign_seed": 105})
	var w := s.world
	var st := w.settlements[0]
	var keep := w.buildings_of(st.id)[0]
	var placed := []
	for def_id: StringName in [&"farm", &"woodcutter", &"bakery", &"house"]:
		var spot := find_spot(s, def_id, keep.pos, 40.0)
		if spot == Vector2.INF:
			fail("no spot for %s" % def_id)
			continue
		var res := s.submit(PlaceBuildingCommand.create(st.id, def_id, spot))
		assert_true(res.success, "%s: %s" % [def_id, res.reason])
		if res.success:
			placed.append(int(res.data["building"]))
	var t0 := Time.get_ticks_msec()
	var max_hunger := 0.0
	var bread_seen := 0
	for d in 720:
		s.advance_days(1)
		for res: StringName in st.stock.keys():
			if st.amount(res) < 0:
				fail("negative stock %s on day %d" % [res, d])
		for p in w.people_of(st.id):
			max_hunger = maxf(max_hunger, p.hunger)
		bread_seen = maxi(bread_seen, st.amount(&"bread"))
	var ms := Time.get_ticks_msec() - t0
	assert_true(ms < 20000, "two years simulated in %d ms" % ms)
	for bid: int in placed:
		assert_true(w.building(bid).is_active(), "%s finished" % w.building(bid).def_id)
	var people := w.people_of(st.id).size()
	assert_true(people >= 5 and people <= 25, "the village lives on: %d people (births, deaths and newcomers are Phase 5)" % people)
	assert_true(st.reserved.size() <= 7, "no leaked reservations (%d)" % st.reserved.size())
	var total_food := st.amount(&"grain") + st.amount(&"bread")
	assert_true(total_food > 0, "the farm and the bakery keep food in the stores (%d)" % total_food)
	assert_true(max_hunger <= float(Defs.balance("settlement")["hunger_max_days"]), "hunger stays bounded (%.1f)" % max_hunger)
	var stumps := 0
	for key: String in w.terrain.felled.keys():
		if int(w.terrain.felled[key]) >= 0:
			stumps += 1
	assert_true(w.terrain.felled.size() > 60, "the woods around the village were worked (%d)" % w.terrain.felled.size())
	print("  2y: felled %d (stumps %d), stock %s, max hunger %.1f, %d ms" % [w.terrain.felled.size(), stumps, str(st.stock), max_hunger, ms])


func test_road_is_built_and_speeds_up_walking() -> void:
	var s := GameSession.create_new({"campaign_seed": 106})
	var w := s.world
	var st := w.settlements[0]
	var keep := w.buildings_of(st.id)[0]
	var a := keep.pos + Vector2(-10, 22)
	# the first direction that stays on dry, free ground: where the river runs depends on where the fire was lit
	var b := a + Vector2(70, 0)
	for dir: Vector2 in [Vector2(70, 0), Vector2(-70, 0), Vector2(0, 70), Vector2(0, -70), Vector2(50, 50), Vector2(-50, 50)]:
		if bool(Placement.check_road(w, st, a, a + dir)["ok"]):
			b = a + dir
			break
	assert_false(bool(Placement.check_road(w, st, a, a + Vector2(2, 0))["ok"]), "too short refused")
	assert_false(bool(Placement.check_road(w, st, a, a + Vector2(-400, 0))["ok"]), "too long refused")
	assert_false(bool(Placement.check_road(w, st, keep.pos + Vector2(-30, 0), keep.pos + Vector2(30, 0))["ok"]), "no road under a building")
	var check := Placement.check_road(w, st, a, b)
	assert_true(bool(check["ok"]), String(check["reason"]))
	var res := s.submit(PlaceRoadCommand.create(st.id, a, b))
	assert_true(res.success, res.reason)
	var road := w.building(int(res.data["building"]))
	assert_true(road.is_road())
	assert_true(road.required_hours() > 5.0, "work grows with the length")
	var days := 0
	while not road.is_active() and days < 30:
		s.advance_days(1)
		days += 1
	assert_true(road.is_active(), "road finished in %d days" % days)
	for t in road.trees_on_ground(wd):
		assert_true(w.terrain.is_felled(t["key"]), "the road is clear of trees")
	var mid := (a + b) * 0.5
	assert_true(road.covers(mid, 0.0), "the road covers its own middle")
	assert_true(SettlementSim.road_speed_factor(w, a, b) > 1.3, "walking along the road is faster")
	assert_true(is_equal_approx(SettlementSim.road_speed_factor(w, a + Vector2(0, 300), b + Vector2(0, 300)), 1.0), "away from roads nothing changes")
	# a building cannot be placed on the road either
	assert_false(bool(Placement.check(w, st, Defs.building(&"house"), mid)["ok"]), "no building on the road")


## Phase 14B: the houses of a village are not all the same house. Every building keeps one drawing for good
## (chosen by its id, so a save and a load show the same street), and every drawing it can pick exists.
func test_the_houses_of_a_village_are_not_all_the_same() -> void:
	var layer := SettlementLayer.new()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(layer)
	var s := GameSession.create_new({"campaign_seed": 1501})
	var st := s.world.settlements[0]
	var houses: Array[BuildingState] = []
	for i in 12:
		var b := BuildingState.new()
		b.id = 1000 + i * 3
		b.def_id = &"house"
		b.settlement = st.id
		b.status = BuildingState.Status.ACTIVE
		houses.append(b)
	var seen := {}
	for b in houses:
		var sprite := layer.sprite_for(b, 5)
		assert_true(layer._sprites.has(String(sprite)), "the drawing %s exists in the atlas" % sprite)
		assert_eq(layer.sprite_for(b, 5), sprite, "and the same house always wears the same one")
		seen[sprite] = true
	assert_true(seen.size() >= 2, "a dozen houses do not all look alike (%d disegni)" % seen.size())
	var well := BuildingState.new()
	well.id = 77
	well.def_id = &"well"
	assert_eq(layer.sprite_for(well, 5), &"well", "a building drawn only one way keeps its one drawing")
	tree.root.remove_child(layer)
	layer.free()


## Phase 19: full stores were told every day of the hourly simulation, and never while the village was resolved
## by the day (not watched). Now once a month per settlement, from both.
func test_full_stores_are_told_once_a_month_not_every_day() -> void:
	var s := GameSession.create_new({"campaign_seed": 1901})
	var st := s.world.settlements[0]
	assert_false(SettlementSim.is_detailed(s, st.id), "nobody is watching: the village is resolved by the day")
	var told: Array[String] = []
	var listen := func(title: String, _text: String, _kind: StringName, _pos: Vector2) -> void:
		if title.begins_with("Depositi pieni"):
			told.append(title)
	EventBus.notification.connect(listen)
	var space := st.space_for(s.world, &"wood")
	st.add(&"wood", space, &"other")   # the stores of the village are full
	for d in 45:
		SettlementSim.produce(s, st, &"wood", 4.0)
		s.world.tick += s.world.ticks_per_day   # a day passes (only the clock: nothing else moves)
	EventBus.notification.disconnect(listen)
	assert_eq(st.space_for(s.world, &"wood"), 0, "nothing more fits in the stores")
	assert_eq(told.size(), 2, "the ruler hears of it on the first day and a month later, not every day (%d)" % told.size())
	s.dispose()

