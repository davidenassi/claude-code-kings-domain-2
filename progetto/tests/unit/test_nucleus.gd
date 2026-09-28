extends KDTestCase
## Rebirth, Phase 3: the nucleus of the community. Six people arrive, light a fire and make a place of it: the fire
## in the middle of an open square, a small store and a shelter behind it, the water point on the nearest bank.
## Nobody builds over the square; in the evening they sit round the fire; by day somebody goes for water. The
## nucleus travels with the save, and a community founded before it gets its fire when its save is opened.


func after_each() -> void:
	Session.end()


static func _of(w: WorldState, st: SettlementState, def_id: StringName) -> Array[BuildingState]:
	var out: Array[BuildingState] = []
	for b in w.buildings_of(st.id):
		if b.def_id == def_id:
			out.append(b)
	return out


## Runs the session hour by hour until the given hour of the day (0-23) of the next day at that hour.
static func _until_hour(s: GameSession, hour: int) -> void:
	for i in 48:
		if s.world.tick % s.world.ticks_per_day == hour:
			return
		s.step_tick()


func test_the_community_starts_round_its_fire() -> void:
	var s := GameSession.create_new({"campaign_seed": 3101})
	var w := s.world
	var st := w.settlements[0]
	var ld := SettlementSim.ground(w)
	var hearths := _of(w, st, Nucleus.HEARTH)
	assert_eq(hearths.size(), 1, "one common fire")
	if hearths.is_empty():
		return
	var fire := hearths[0]
	assert_true(fire.pos.distance_to(st.center) < 0.01, "at the centre of the community")
	assert_eq(w.buildings_of(st.id)[0].def_id, &"camp_store", "the store is still the first building (the stores of the start)")
	assert_eq(_of(w, st, &"shelter").size(), 1, "a shelter")
	var wps := _of(w, st, Nucleus.WATER_POINT)
	assert_eq(wps.size(), 1, "a water point")
	if wps.is_empty():
		return
	var wp := wps[0]
	var to_water := wp.pos.distance_to(fire.pos)
	assert_true(to_water <= 200.0, "the water is within two hundred metres (%.0f)" % to_water)
	var near_water := false
	for k in 16:
		var q := wp.pos + Vector2.from_angle(TAU * k / 16.0) * 4.0
		if ld.river_clearance(q) < 0.0 or ld.water_at(q) != WorldData.WATER_LAND:
			near_water = true
	assert_true(near_water, "the water point is on the bank")
	assert_true(ld.water_at(wp.pos) == WorldData.WATER_LAND, "with its feet on dry land")
	var dir := (wp.pos - fire.pos).normalized()
	for b in [_of(w, st, &"camp_store")[0], _of(w, st, &"shelter")[0]]:
		assert_false(Nucleus.rect_meets_circle(b.rect(), fire.pos, Nucleus.square_radius()), "%s stands outside the square" % b.def_id)
		assert_true((b.pos - fire.pos).dot(dir) < 0.0, "%s stands behind the fire, away from the water" % b.def_id)
		assert_true(b.pos.distance_to(fire.pos) < 30.0, "%s close to the fire" % b.def_id)
	var founders := w.people_of(st.id)
	assert_eq(founders.size(), 6, "six founders")
	var places := {}
	for p in founders:
		assert_true(p.seg_to.distance_to(fire.pos) < 6.0, "%s is at the fire" % p.name)
		places["%d:%d" % [roundi(p.seg_to.x * 10.0), roundi(p.seg_to.y * 10.0)]] = true
	assert_eq(places.size(), 6, "each in a place of their own")
	assert_true(ld.river_clearance(fire.pos) > 40.0, "the fire stands back from the bank")
	# the square and the way to the water are open ground
	var standing := 0
	for t in LocalFeatures.trees_in_rect(ld, Rect2(fire.pos - Vector2(12, 12), Vector2(24, 24))):
		if t["pos"].distance_to(fire.pos) < Nucleus.square_radius() and not w.terrain.felled.has(t["key"]):
			standing += 1
	assert_eq(standing, 0, "no tree on the square")
	var path := Nucleus.water_path(w, st)
	assert_eq(path.size(), 2, "a path goes to the water")
	var blocked := 0
	for t in LocalFeatures.trees_in_rect(ld, Rect2(path[0], Vector2.ZERO).expand(path[1]).grow(3.0)):
		if not w.terrain.felled.has(t["key"]) and Geometry2D.get_closest_point_to_segment(t["pos"], path[0], path[1]).distance_to(t["pos"]) < 2.0:
			blocked += 1
	assert_eq(blocked, 0, "and no tree stands on it")
	var chronicle := String(w.chronicle[0].get("text", "")) if not w.chronicle.is_empty() else ""
	assert_true(chronicle.contains("fuoco"), "the chronicle tells of the fire: %s" % chronicle)


func test_the_square_stays_open() -> void:
	var s := GameSession.create_new({"campaign_seed": 3102})
	var w := s.world
	var st := w.settlements[0]
	st.stock[&"wood"] = 400
	var fire := Nucleus.hearth_of(w, st)
	var house := Defs.building(&"house")
	for off: Vector2 in [Vector2(9.0, 0.0), Vector2(0.0, 10.0), Vector2(-8.0, 6.0)]:
		var r := Placement.check(w, st, house, fire.pos + off)
		assert_false(bool(r["ok"]), "no house on the square at %s" % str(off))
		if not bool(r["ok"]) and String(r["reason"]).contains("occupato") == false:
			assert_true(String(r["reason"]).contains("piazzola"), String(r["reason"]))
	var spot := SettlementPlanner.find_spot(s, st.id, &"house", fire.pos, 6.0)
	assert_true(spot != Vector2.INF, "a house fits next to the square")
	assert_false(Nucleus.rect_meets_circle(Rect2(spot - house.footprint * 0.5, house.footprint), fire.pos, Nucleus.square_radius()),
		"and the builders keep off the square")
	# the careful lord builds a whole village around it, and the square is still open
	SettlementPlanner.place_starter_village(s, st.id)
	for m in 6:
		s.advance_days(30)
		SettlementPlanner.lord_month(s, st.id, 40)
	for b in w.buildings_of(st.id):
		if b.is_road() or b.def_id == Nucleus.HEARTH:
			continue
		assert_false(Nucleus.rect_meets_circle(b.rect(), fire.pos, Nucleus.square_radius()), "%s keeps off the square" % b.def_id)


func test_in_the_evening_they_sit_round_the_fire_and_by_day_they_go_for_water() -> void:
	var s := GameSession.create_new({"campaign_seed": 3103})
	var w := s.world
	var st := w.settlements[0]
	SettlementSim.set_observed(s, {st.id: true})
	var fire := Nucleus.hearth_of(w, st)
	var wp := Nucleus.water_point_of(w, st)
	# two days hour by hour: somebody goes for water, and in the evening everybody is at the fire
	var water := 0
	var at_fire_evening := 0
	var sitting := 0
	for h in 48:
		s.step_tick()
		var hour := w.tick % w.ticks_per_day
		for p in w.people_of(st.id):
			if p.action == &"draw_water":
				assert_true(p.seg_to.distance_to(Nucleus.draw_spot(w, wp)) < 0.5, "%s draws water at the end of the landing" % p.name)
			if p.action in [&"draw_water", &"carry_water"] or StringName(p.pending.get("do", "")) in [&"at_water", &"water_back"]:
				water += 1
			if hour == 20 and h >= 24:
				if p.position_at(float(w.tick)).distance_to(fire.pos) < 6.0:
					at_fire_evening += 1
				if p.action == &"sit":
					sitting += 1
	assert_true(water > 0, "somebody went for water (%d person-hours)" % water)
	# the bucket goes back to the fire
	var q := w.people_of(st.id)[0]
	q.pending = {"do": &"water_back"}
	q.busy_until = float(w.tick)
	SettlementSim.tick(s)
	assert_eq(q.action, &"carry_water", "the water is carried")
	assert_true(q.seg_to.distance_to(fire.pos) < 4.0, "to the fire")
	assert_eq(at_fire_evening, 6, "at eight in the evening the six founders are at the fire")
	assert_eq(sitting, 6, "on the benches")
	_until_hour(s, 23)
	var home := 0
	for p in w.people_of(st.id):
		if p.action == &"sleep" or p.action == &"walk":
			home += 1
	assert_eq(home, 6, "and at eleven they have gone to sleep")


func test_a_town_does_not_crowd_the_fire() -> void:
	var s := GameSession.create_new({"campaign_seed": 3104})
	var w := s.world
	var st := w.settlements[0]
	var fire := Nucleus.hearth_of(w, st)
	var chosen := 0
	var n := 400
	for id in n:
		if KDRng.hash01(id * 2 + 1, 10, 9901) < float(Nucleus.balance().get("gather_max", 12)) / float(n):
			chosen += 1
	assert_true(chosen < 30, "of four hundred people only a few sit at the fire on an evening (%d)" % chosen)
	# the places round the fire are the benches first, and nobody sits in the fire
	for id in 30:
		var p := Nucleus.seat(fire, id, 3, n)
		assert_true(p.distance_to(fire.pos) > 2.5, "nobody sits in the fire")
		assert_true(p.distance_to(fire.pos) < Nucleus.square_radius(), "but on the square")


func test_the_nucleus_travels_with_the_save() -> void:
	var s := GameSession.create_new({"campaign_seed": 3105})
	SettlementSim.set_observed(s, {0: true})
	s.advance_days(3)
	var back := SaveSystem.session_from_data(JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s))))
	assert_not_null(back, "the save opens")
	if back == null:
		return
	var st := back.world.settlements[0]
	var fire := Nucleus.hearth_of(back.world, st)
	assert_not_null(fire, "with its fire")
	assert_not_null(Nucleus.water_point_of(back.world, st), "and its water point")
	assert_eq(st.center, s.world.settlements[0].center, "in the same place")
	SettlementSim.set_observed(back, {0: true})
	back.advance_days(2)
	assert_eq(back.world.people_of(st.id).size(), 6, "and the six live on there")


## A community founded before the nucleus existed (save v7): the fire is added on free ground in front of the store,
## the community is centred on it, the water point goes to the nearest bank; nothing else moves.
func test_an_older_community_gets_its_fire() -> void:
	var s := GameSession.create_new({"campaign_seed": 3106})
	var st := s.world.settlements[0]
	SettlementPlanner.place_starter_village(s, st.id)
	s.advance_days(20)
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s)))
	# as the older build wrote it: no fire, no water point, the store at the centre
	var store: Dictionary = {}
	var kept: Array = []
	for bd: Dictionary in data["world"]["buildings"]:
		if String(bd["def"]) in ["hearth", "water_point"]:
			continue
		if String(bd["def"]) == "camp_store":
			store = bd
		kept.append(bd)
	data["world"]["buildings"] = kept
	var before := kept.size()
	(data["world"]["settlements"] as Array)[0]["x"] = store["x"]
	(data["world"]["settlements"] as Array)[0]["y"] = store["y"]
	data["header"]["save_version"] = 7
	var migrated := SaveMigrator.migrate(data)
	assert_eq(int(migrated["header"]["save_version"]), SaveMigrator.CURRENT_VERSION, "migrated")
	var back := SaveSystem.session_from_data(migrated)
	assert_not_null(back, "the old save opens")
	if back == null:
		return
	var w := back.world
	var home := w.settlements[0]
	var fire := Nucleus.hearth_of(w, home)
	assert_not_null(fire, "the old community has its fire")
	if fire == null:
		return
	assert_true(fire.pos.distance_to(Vector2(float(store["x"]), float(store["y"]))) < 60.0, "near its store")
	assert_eq(home.center, fire.pos, "and the community is centred on it")
	for b in w.buildings_of(home.id):
		if b != fire and not b.is_road():
			assert_false(b.rect().intersects(fire.rect()), "the fire stands on free ground (%s)" % b.def_id)
	assert_true(w.buildings.size() >= before + 1, "nothing was taken away")
	var again := SaveMigrator.migrate(JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(back))))
	assert_eq((again["world"]["buildings"] as Array).size(), w.buildings.size(), "and a second opening adds nothing")
	back.advance_days(5)
	assert_true(w.people_of(home.id).size() >= 6, "life goes on")


## Without a generated homeland (the valley cut out of the continent) the community has its nucleus too.
func test_the_nucleus_is_made_in_a_valley_of_the_continent_too() -> void:
	var s := GameSession.create_new({"campaign_seed": 3107, "homeland": "none"})
	var w := s.world
	var st := w.settlements[0]
	var fire := Nucleus.hearth_of(w, st)
	assert_not_null(fire, "a fire")
	if fire:
		assert_true(fire.pos.distance_to(st.center) < 0.01, "at the centre")
	assert_eq(w.buildings_of(st.id)[0].def_id, &"camp_store", "the store first")
	for p in w.people_of(st.id):
		assert_true(p.seg_to.distance_to(st.center) < 6.0, "%s at the fire" % p.name)
