extends KDTestCase

var wd: WorldData


func before_each() -> void:
	wd = WorldData.get_instance()


static func village(seed_value: int, with_farm: bool = true) -> GameSession:
	var s := GameSession.create_new({"campaign_seed": seed_value})
	s.set_system_enabled(&"events", false)   # a test that weighs the economy keeps the weather out
	var st := s.world.settlements[0]
	var keep := s.world.buildings_of(st.id)[0]
	var wanted: Array[StringName] = [&"woodcutter", &"house", &"granary"]
	if with_farm:
		wanted = [&"farm", &"woodcutter", &"bakery", &"house", &"granary", &"house"]
	for def_id in wanted:
		# the woodcutter at the edge of the wood (Rebirth: the valley's woods are masses, not a stipple)
		var near := keep.pos if def_id != &"woodcutter" else st.center + SettlementPlanner.wood_direction(s.world, st) * 110.0
		var spot := SettlementPlanner.find_spot(s, st.id, def_id, near, 36.0 if def_id != &"woodcutter" else 0.0)
		if spot != Vector2.INF:
			s.submit(PlaceBuildingCommand.create(st.id, def_id, spot))
	return s


func test_stores_have_a_capacity_and_overflow_is_lost() -> void:
	var s := village(201)
	var w := s.world
	var st := w.settlements[0]
	var store := Defs.building(&"camp_store").storage
	assert_eq(st.capacity(w, &"material"), store, "the common fire holds everything at the start")
	assert_eq(st.space_for(w, &"gold"), 1 << 30, "gold is not stored in the barns")
	st.stock[&"wood"] = store - 150
	st.stock[&"stone"] = 100
	assert_eq(st.used(&"material"), store - 50)
	assert_eq(st.space_for(w, &"wood"), 50)
	s.advance_days(60)
	assert_true(st.used(&"material") <= st.capacity(w, &"material"), "the stores never go over capacity")
	var granary := w.buildings_of(st.id).filter(func(b: BuildingState) -> bool: return b.def_id == &"granary")
	if not granary.is_empty() and granary[0].is_active():
		assert_true(st.capacity(w, &"food") >= 1000, "the granary adds food capacity")


func test_treasury_taxes_wages_and_province_rents() -> void:
	var s := village(202)
	var w := s.world
	var player := w.player()
	assert_eq(int(player.treasury), int(Defs.balance("settlement")["start_stock"]["gold"]), "the founders arrive with a few coins")
	assert_eq(w.settlements[0].amount(&"gold"), 0, "gold is not a good in store")
	var before := player.treasury
	s.advance_days(31)
	assert_false(player.last_balance.is_empty(), "the month closes with a balance")
	var bl := player.last_balance
	assert_true(float(bl["taxes"]) > 0.0, "the people pay taxes")
	assert_true(float(bl["wages"]) > 0.0, "the workers are paid")
	assert_true(is_equal_approx(player.treasury - before, float(bl["total"])), "the treasury follows the balance")
	# more provinces, less control over the rents
	var small := EconomySystem.admin_control(w, player)
	var big := EconomySystem.admin_control(w, w.kingdoms[1])
	assert_true(big < small, "a wide realm disperses more (%.2f vs %.2f)" % [big, small])
	assert_true(EconomySystem.province_income(w, w.kingdoms[1], w.kingdoms[1].capital) > 0.0, "provinces yield rents")


func test_market_prices_follow_scarcity() -> void:
	var s := village(203)
	var w := s.world
	var st := w.settlements[0]
	st.stock[&"wood"] = 500
	st.stock[&"grain"] = 0
	st.stock[&"bread"] = 0
	s.advance_days(31)
	var player := w.player()
	assert_false(player.prices.is_empty(), "the realm has prices")
	var wood_price := float(player.prices.get(&"wood", 0.0))
	var bread_price := float(player.prices.get(&"bread", 0.0))
	assert_true(wood_price < Defs.resource(&"wood").base_price, "plenty of wood, cheap wood (%.2f)" % wood_price)
	assert_true(bread_price > Defs.resource(&"bread").base_price, "no bread, dear bread (%.2f)" % bread_price)


## What a careful lord does every month (the same one the game's scenarios and campaigns use).
static func lord_turn(s: GameSession, max_people: int = 1000) -> void:
	SettlementPlanner.lord_month(s, s.world.settlements[0].id, max_people)


func test_twenty_years_of_a_prosperous_village() -> void:
	var s := village(204)
	var w := s.world
	var st := w.settlements[0]
	var t0 := Time.get_ticks_msec()
	var counts := {"birth": 0, "death": 0}
	var counter := func(_t: String, _x: String, kind: StringName, _p: Vector2, _space: StringName) -> void:
		if counts.has(String(kind)):
			counts[String(kind)] = int(counts[String(kind)]) + 1
	EventBus.notification.connect(counter)
	var children_seen := 0
	for y in 20:
		for m in 12:
			s.advance_days(30)
			lord_turn(s, 30)   # a village of about thirty souls: enough to see births, deaths and newcomers
		for p in w.people_of(st.id):
			if p.job == &"child":
				children_seen += 1
	var ms := Time.get_ticks_msec() - t0
	var people := w.people_of(st.id)
	EventBus.notification.disconnect(counter)
	var births := int(counts["birth"])
	var deaths := int(counts["death"])
	print("  20y: %d abitanti (nati %d, morti %d), fiducia %.0f, tesoro %.0f, %d edifici, %d ms" % [
		people.size(), births, deaths, st.trust, w.player().treasury, w.buildings_of(st.id).size(), ms])
	assert_true(people.size() > 7, "the village grew (%d)" % people.size())
	assert_true(births > 0 and deaths > 0, "births and deaths happen (%d / %d)" % [births, deaths])
	assert_true(st.trust > 40.0, "consent holds (%.0f)" % st.trust)
	var ages := {}
	for p in people:
		var a := p.age_years(w.day)
		assert_true(a >= 0 and a <= int(Defs.balance("population")["max_age"]) + 1, "%s has a plausible age (%d)" % [p.name, a])
		ages[p.job] = int(ages.get(p.job, 0)) + 1
	# children are born and grow up in the village. Counted over the twenty years, not on the last day: a child needs
	# a free bed (population.json → needs_free_bed), and a village the lord keeps at thirty souls can fill its beds
	# early and then age (Rebirth: the fertile floor of Valverde fills them by the third year)
	assert_true(children_seen > 0, "there are children (%d child-years, %d today)" % [children_seen, int(ages.get(&"child", 0))])
	assert_true(w.provinces[w.kingdoms[1].capital].population > 0, "the provinces of the other realms live on")
	assert_true(ms < 200000, "twenty years simulated in %d ms" % ms)
	assert_true(w.player().treasury > 0.0, "the crown is not in debt (%.0f)" % w.player().treasury)
	assert_true(st.tier_name(people.size()) != "Insediamento", "the settlement became a village (%s)" % st.tier_name(people.size()))


func test_watched_and_unwatched_villages_agree() -> void:
	# the same months, once hour by hour (as if the camera were there) and once resolved day by day
	var detailed := village(207)
	SettlementSim.set_observed(detailed, {0: true})
	var aggregate := village(207)
	detailed.advance_days(120)
	aggregate.advance_days(120)
	var a := detailed.world.settlements[0]
	var b := aggregate.world.settlements[0]
	assert_eq(detailed.world.people_of(a.id).size(), aggregate.world.people_of(b.id).size(), "same people")
	for res: StringName in [&"wood", &"grain", &"bread"]:
		var x := a.amount(res)
		var y := b.amount(res)
		assert_true(absf(float(x - y)) <= maxf(0.45 * float(maxi(x, y)), 12.0),
			"%s: watched %d, unwatched %d" % [res, x, y])
	var built_a := 0
	var built_b := 0
	for bd in detailed.world.buildings_of(a.id):
		built_a += 1 if bd.is_active() else 0
	for bd in aggregate.world.buildings_of(b.id):
		built_b += 1 if bd.is_active() else 0
	assert_eq(built_a, built_b, "the same buildings are standing")
	assert_true(absf(float(detailed.world.terrain.felled.size() - aggregate.world.terrain.felled.size()))
		<= 0.5 * float(maxi(detailed.world.terrain.felled.size(), aggregate.world.terrain.felled.size())),
		"a similar amount of wood was cut (%d vs %d)" % [detailed.world.terrain.felled.size(), aggregate.world.terrain.felled.size()])


func test_famine_makes_the_village_collapse() -> void:
	var s := village(205, false)   # no farm, no bakery
	var w := s.world
	var st := w.settlements[0]
	st.stock[&"grain"] = 0
	st.stock[&"bread"] = 8
	var start := w.people_of(st.id).size()
	s.advance_days(360)
	var left := w.people_of(st.id).size()
	assert_true(left < start, "hunger kills (%d -> %d)" % [start, left])
	assert_true(st.trust < 40.0, "consent collapses (%.0f)" % st.trust)
	var hungry := 0
	for p in w.people_of(st.id):
		if p.hunger > 5.0:
			hungry += 1
	assert_true(hungry > 0 or left == 0, "who is left is starving")


## The open issue of Phase 12: a village nobody governs grew past its fields and starved to the last man.
## Now it has a valve — the young take the road — and the place survives, smaller.
func test_a_village_left_to_itself_empties_instead_of_starving() -> void:
	var s := village(211)
	var w := s.world
	var st := w.settlements[0]
	var counts := {"left": 0, "starved": 0, "born": 0}
	var counter := func(_title: String, text: String, kind: StringName, _p: Vector2, _space: StringName) -> void:
		if kind == &"emigration":
			counts["left"] = int(counts["left"]) + 1
		elif kind == &"death" and text.contains("di stenti"):
			counts["starved"] = int(counts["starved"]) + 1
		elif kind == &"birth":
			counts["born"] = int(counts["born"]) + 1
	EventBus.notification.connect(counter)
	s.advance_days(360 * 20)   # twenty years and not one decision from the lord
	EventBus.notification.disconnect(counter)
	var people := w.people_of(st.id)
	print("  20 anni senza decisioni: %d abitanti, %d partenze, %d morti di stenti, %d nati, fiducia %.0f" % [
		people.size(), int(counts["left"]), int(counts["starved"]), int(counts["born"]), st.trust])
	assert_true(people.size() >= 4, "the village is still there (%d abitanti)" % people.size())
	assert_true(int(counts["left"]) > 0, "somebody took the road when the fields stopped being enough")
	assert_true(int(counts["starved"]) <= int(counts["left"]),
		"more left than starved (%d partenze, %d stenti)" % [int(counts["left"]), int(counts["starved"])])




func test_same_save_gives_the_same_outcome() -> void:
	var a := village(206)
	a.advance_days(400)
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(a)))
	var b := SaveSystem.session_from_data(data)
	assert_not_null(b)
	if b == null:
		return
	b.set_system_enabled(&"events", false)   # the loaded game must run under the same sky
	a.advance_days(200)
	b.advance_days(200)
	var sa := a.world.settlements[0]
	var sb := b.world.settlements[0]
	assert_eq(a.world.people_of(sa.id).size(), b.world.people_of(sb.id).size(), "same people")
	assert_eq(sa.stock, sb.stock, "same stores")
	assert_true(absf(a.world.player().treasury - b.world.player().treasury) < 0.01, "same treasury")
	assert_true(absf(sa.trust - sb.trust) < 0.01, "same consent")

