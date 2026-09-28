extends KDTestCase
## Rebirth, Phase 5: the scale of a town. A settlement grows through grades (nucleus → village → large village →
## borough → city → great capital) and from the large village on by QUARTERS: one building of the world that holds
## dozens of homes or workshops and grows by itself. A town of thousands is a few dozen quarters, not two thousand
## houses, and its people are not walked one by one.

const StressWorlds := preload("res://tests/stress/stress_worlds.gd")


func after_each() -> void:
	Session.end()


func test_the_grades_of_a_settlement() -> void:
	var expect := {6: &"nucleus", 19: &"nucleus", 20: &"village", 99: &"village", 100: &"large_village",
		499: &"large_village", 500: &"borough", 1999: &"borough", 2000: &"city", 7999: &"city", 8000: &"capital", 30000: &"capital"}
	for n: int in expect.keys():
		assert_eq(SettlementState.tier(n)["id"], expect[n], "%d people" % n)
	assert_eq(SettlementState.tier(6)["name"], "Nucleo")
	assert_eq(SettlementState.tier(600)["name"], "Borgo")


func test_quarters_come_with_the_town() -> void:
	var s := GameSession.create_new({"campaign_seed": 5101})
	var w := s.world
	var st := w.settlements[0]
	st.stock[&"wood"] = 900
	st.stock[&"stone"] = 900
	var quarter := Defs.building(&"district_residential")
	var r := Placement.check(w, st, quarter, st.center + Vector2(80, 60))
	assert_false(bool(r["ok"]), "six founders do not build a quarter")
	assert_true(String(r["reason"]).begins_with("Serve almeno"), String(r["reason"]))
	PopulationSystem.welcome(s, st, 110, w.day, "test")
	var spot := SettlementPlanner.site_for(s, st, &"district_residential")
	assert_true(spot != Vector2.INF, "a large village has room for a quarter")
	var res := s.submit(PlaceBuildingCommand.create(st.id, &"district_residential", spot))
	assert_true(res.success, res.reason)
	var church := Placement.check(w, st, Defs.building(&"district_religious"), spot + Vector2(0, 120), true)
	assert_true(String(church["reason"]).contains("Borgo"), "a church needs a borough: %s" % String(church["reason"]))
	if not res.success:
		return
	var b := w.building(int(res.data["building"]))
	var beds_before := PopulationSystem.free_beds(w, st)
	b.status = BuildingState.Status.ACTIVE
	w.buildings_changed()
	assert_eq(PopulationSystem.free_beds(w, st), beds_before + 60, "a quarter of houses: sixty beds at once")
	assert_false(Nucleus.rect_meets_circle(b.rect(), st.center, Nucleus.square_radius()), "not on the square of the fire")


func test_a_full_quarter_grows_when_its_town_does() -> void:
	var s := GameSession.create_new({"campaign_seed": 5102})
	var w := s.world
	var st := w.settlements[0]
	PopulationSystem.welcome(s, st, 110, w.day, "test")
	st.stock[&"wood"] = 900
	st.stock[&"stone"] = 900
	var spot := SettlementPlanner.site_for(s, st, &"district_residential")
	var b := SettlementSetup._add_building(w, st, &"district_residential", spot)
	assert_eq(b.level, 1)
	assert_false(DistrictSystem.try_grow(s, st, b), "an empty quarter does not grow")
	# fill it, and let the town become a borough
	var moved := 0
	for p in w.people_of(st.id):
		if moved >= 58:
			break
		p.home = b.id
		moved += 1
	assert_false(DistrictSystem.try_grow(s, st, b), "full, but a large village does not make a level-2 quarter")
	PopulationSystem.welcome(s, st, 420, w.day, "test")
	var wood := st.amount(&"wood")
	assert_true(DistrictSystem.try_grow(s, st, b), "full, in a borough, with the materials: it grows")
	assert_eq(b.level, 2)
	assert_eq(b.beds(), 140, "a hundred and forty beds")
	assert_eq(wood - st.amount(&"wood"), 180, "it took the wood of its growth")
	var back := SaveSystem.session_from_data(JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s))))
	assert_eq(back.world.building(b.id).level, 2, "the level travels with the save")


## Thousands of people as a few dozen quarters — and the hour-by-hour simulation does not walk them one by one.
func test_a_town_of_thousands_is_made_of_quarters() -> void:
	var s := GameSession.create_new({"campaign_seed": 5103})
	var w := s.world
	var st := w.settlements[0]
	var out: Dictionary = StressWorlds.grow_district_city(s, 3000)
	var people := w.people_of(st.id).size()
	assert_true(people >= 2900, "a town of about three thousand (%d)" % people)
	assert_eq(SettlementState.tier(people)["id"], &"city", "a city")
	var quarters := 0
	var houses := 0
	var kinds := {}
	for b in w.buildings_of(st.id):
		if b.is_district():
			quarters += 1
			kinds[b.def().district_kind()] = true
		elif b.def_id == &"house":
			houses += 1
	assert_true(quarters >= 12 and quarters <= 60, "%d quarters" % quarters)
	assert_true(houses < 40, "the houses of the old village, not seven hundred (%d)" % houses)
	assert_true(w.buildings_of(st.id).size() < 150, "%d buildings for %d people" % [w.buildings_of(st.id).size(), people])
	for k: StringName in [&"residential", &"farming", &"craft", &"market", &"religious"]:
		assert_true(kinds.has(k), "it has a %s quarter" % k)
	var in_quarters := 0
	for p in w.people_of(st.id):
		if SettlementSim.in_quarter(w, p):
			in_quarters += 1
	assert_true(in_quarters > people * 0.8, "most people live in the quarters (%d of %d)" % [in_quarters, people])
	# watched hour by hour: the people of the quarters stay where they are, the rest walk; the day still works
	SettlementSim.set_observed(s, {st.id: true})
	var t0 := Time.get_ticks_msec()
	var bread := st.amount(&"bread")
	s.advance_days(3)
	var ms := Time.get_ticks_msec() - t0
	assert_true(ms < 60000, "three watched days of a city in %d ms" % ms)
	var still := 0
	var checked := 0
	for p in w.people_of(st.id):
		if SettlementSim.in_quarter(w, p) and checked < 200:
			checked += 1
			if p.seg_from == p.seg_to:
				still += 1
	assert_eq(still, checked, "nobody of the quarters is walked hour by hour")
	assert_true(DistrictSystem.market_income(w, st) > 0.0, "the markets bring gold")
	assert_true(DistrictSystem.trust_bonus(w, st) > 0.0, "the church is felt")
	assert_true(st.amount(&"bread") != bread or st.amount(&"grain") > 0, "the town eats and works")
	var back := SaveSystem.session_from_data(JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s))))
	assert_not_null(back, "the city survives a save")
	if back:
		assert_eq(back.world.people_of(back.world.settlements[0].id).size(), w.people_of(st.id).size(), "with all its people")


func test_the_picture_of_a_quarter_is_its_block() -> void:
	var s := GameSession.create_new({"campaign_seed": 5104})
	var w := s.world
	var st := w.settlements[0]
	PopulationSystem.welcome(s, st, 110, w.day, "test")
	st.stock[&"wood"] = 900
	st.stock[&"stone"] = 900
	var spot := SettlementPlanner.site_for(s, st, &"district_residential")
	var b := SettlementSetup._add_building(w, st, &"district_residential", spot)
	var one := DistrictPainter.layout(b)
	assert_true((one["pieces"] as Array).size() >= 8, "a block of houses (%d)" % (one["pieces"] as Array).size())
	assert_eq((one["lanes"] as Array).size(), 4, "a street on every side of the block (shared with the next one)")
	assert_true((one["gardens"] as Array).size() > 0, "and gardens in its courtyard")
	for piece: Array in one["pieces"]:
		assert_true(b.rect().grow(1.0).has_point(piece[1]), "every house inside its block")
	b.level = 3
	var three := DistrictPainter.layout(b)
	assert_true((three["pieces"] as Array).size() > (one["pieces"] as Array).size(), "fuller as it grows (%d > %d)" % [
		(three["pieces"] as Array).size(), (one["pieces"] as Array).size()])
	assert_eq(DistrictPainter.layout(b), three, "the same picture every time")
