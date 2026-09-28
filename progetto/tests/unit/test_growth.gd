extends KDTestCase
## Rebirth, Phase 4: the organic growth of a settlement. The player chooses what and the area; the game chooses the
## spot a villager would have chosen (Siting). A village of thirty to fifty must look grown in its place: houses
## close together round the square with their doors on the ways, the crafts and stores between them and the
## fields, the fields side by side on good soil, the woodcutter at the edge of the wood — not objects dropped on a
## lawn.


func after_each() -> void:
	Session.end()


static func _door(b: BuildingState) -> Vector2:
	return b.pos + Vector2(0.0, b.def().footprint.y * 0.5 + 0.8)


static func _way_distance(world: WorldState, s: SettlementState, p: Vector2) -> float:
	var best := INF
	for w: Array in Siting.ways_of(world, s):
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, w[0], w[1]).distance_to(p))
	return best


static func _gap_to_others(world: WorldState, b: BuildingState) -> float:
	var best := INF
	for o in world.buildings_of(b.settlement):
		if o == b or o.is_road():
			continue
		best = minf(best, Siting._rect_gap(b.rect(), o.rect()))
	return best


func test_a_house_goes_where_a_villager_would_put_it() -> void:
	var s := GameSession.create_new({"campaign_seed": 4101})
	var w := s.world
	var st := w.settlements[0]
	st.stock[&"wood"] = 300
	var house := Defs.building(&"house")
	var cursor := st.center + Vector2(4.0, 30.0)
	var r := Siting.refine(w, st, house, cursor)
	assert_true(bool(r["ok"]), "a spot is found (%s)" % String((r["check"] as Dictionary).get("reason", "")))
	if not bool(r["ok"]):
		return
	var p: Vector2 = r["pos"]
	assert_true(p.distance_to(cursor) <= Siting.radius_for(house) + 0.01, "in the area the player chose (%.1f m away)" % p.distance_to(cursor))
	assert_false(Nucleus.rect_meets_circle(Rect2(p - house.footprint * 0.5, house.footprint), st.center, Nucleus.square_radius()),
		"not on the square")
	# clicked on the open meadow south of the square: the house moves toward the ways and the village
	var door_at := _way_distance(w, st, p + Vector2(0.0, house.footprint.y * 0.5 + 0.8))
	var door_click := _way_distance(w, st, cursor + Vector2(0.0, house.footprint.y * 0.5 + 0.8))
	assert_true(door_at < door_click or door_at < 3.0, "its door nearer a way (%.1f m instead of %.1f)" % [door_at, door_click])
	var village_at := INF
	var village_click := INF
	for b in w.buildings_of(st.id):
		if not b.is_road():
			village_at = minf(village_at, Siting._rect_gap(Rect2(p - house.footprint * 0.5, house.footprint), b.rect()))
			village_click = minf(village_click, Siting._rect_gap(Rect2(cursor - house.footprint * 0.5, house.footprint), b.rect()))
	assert_true(village_at <= village_click, "and nearer the village (%.1f m instead of %.1f)" % [village_at, village_click])
	var again := Siting.refine(w, st, house, cursor)
	assert_eq(again["pos"], p, "the same choice every time")
	var res := s.submit(PlaceBuildingCommand.create(st.id, &"house", p))
	assert_true(res.success, res.reason)
	# the second house takes its place beside the first, not anywhere
	var r2 := Siting.refine(w, st, house, cursor + Vector2(6.0, 0.0))
	assert_true(bool(r2["ok"]), "a second spot")
	if bool(r2["ok"]):
		var gap := Siting._rect_gap(Rect2(r2["pos"] - house.footprint * 0.5, house.footprint), w.building(int(res.data["building"])).rect())
		assert_true(gap >= Placement.GAP_M - 0.01 and gap < 10.0, "beside the first house (%.1f m between them)" % gap)


func test_the_player_keeps_the_area() -> void:
	var s := GameSession.create_new({"campaign_seed": 4102})
	var w := s.world
	var st := w.settlements[0]
	st.stock[&"wood"] = 300
	for off: Vector2 in [Vector2(120.0, 40.0), Vector2(-90.0, 70.0), Vector2(60.0, 140.0)]:
		for id: StringName in [&"house", &"bakery", &"farm"]:
			var def := Defs.building(id)
			var r := Siting.refine(w, st, def, st.center + off)
			if bool(r["ok"]):
				assert_true(float(r["moved"]) <= Siting.radius_for(def) + 0.01, "%s stays in its area (%.1f m)" % [id, float(r["moved"])])


func test_the_fields_make_a_patchwork_on_good_soil() -> void:
	var s := GameSession.create_new({"campaign_seed": 4103})
	var w := s.world
	var st := w.settlements[0]
	st.stock[&"wood"] = 500
	st.stock[&"stone"] = 100
	var farms: Array[BuildingState] = []
	for i in 3:
		var p := SettlementPlanner.site_for(s, st, &"farm")
		assert_true(p != Vector2.INF, "field %d has a place" % (i + 1))
		if p == Vector2.INF:
			return
		var res := s.submit(PlaceBuildingCommand.create(st.id, &"farm", p))
		assert_true(res.success, res.reason)
		farms.append(w.building(int(res.data["building"])))
	var ld := SettlementSim.ground(w)
	for i in range(1, farms.size()):
		var nearest := INF
		for j in i:
			nearest = minf(nearest, Siting._rect_gap(farms[i].rect(), farms[j].rect()))
		assert_true(nearest < 8.0, "field %d lies against the others (%.1f m)" % [i + 1, nearest])
	for f in farms:
		var bd: BiomeDef = Defs.biome_by_index(ld.biome_at(f.pos))
		assert_true(bd != null and bd.fertility >= 0.5, "on good soil (%s)" % (bd.id if bd else "?"))
		assert_true(f.pos.distance_to(st.center) > Siting.ring(Siting.FIELD, 6, Nucleus.square_radius()).x - 20.0,
			"out beyond the houses")


## Thirty to fifty people grown by a careful lord: the shape of a real village.
func test_a_village_of_thirty_to_fifty_looks_grown_in_its_place() -> void:
	var s := GameSession.create_new({"campaign_seed": 4104})
	var w := s.world
	var st := w.settlements[0]
	SettlementPlanner.place_starter_village(s, st.id)
	for month in 12 * 12:
		s.advance_days(30)
		SettlementPlanner.lord_month(s, st.id, 50)
		if w.people_of(st.id).size() >= 34 and month > 36:
			break
	var people := w.people_of(st.id).size()
	assert_true(people >= 20, "the village grew (%d people)" % people)
	var houses: Array[BuildingState] = []
	var fields: Array[BuildingState] = []
	var others: Array[BuildingState] = []
	for b in w.buildings_of(st.id):
		if b.is_road() or not b.is_active():
			continue
		match Siting.role(b.def()):
			Siting.HOME:
				if b.def_id == &"house":
					houses.append(b)
			Siting.FIELD:
				fields.append(b)
			_:
				others.append(b)
		if b.def_id != Nucleus.HEARTH:
			assert_false(Nucleus.rect_meets_circle(b.rect(), st.center, Nucleus.square_radius()), "%s keeps off the square" % b.def_id)
	assert_true(houses.size() >= 4, "it has houses (%d)" % houses.size())
	# close together, not a scatter: the median gap from a house to its nearest neighbour
	var gaps: Array[float] = []
	var on_way := 0
	var house_d := 0.0
	for h in houses:
		gaps.append(_gap_to_others(w, h))
		if _way_distance(w, st, _door(h)) < 8.0:
			on_way += 1
		house_d += h.pos.distance_to(st.center)
	gaps.sort()
	var median := gaps[gaps.size() / 2]
	assert_true(median >= Placement.GAP_M - 0.01 and median <= 12.0, "houses stand close together (median gap %.1f m)" % median)
	assert_true(float(on_way) / houses.size() >= 0.7, "their doors are on the ways (%d of %d)" % [on_way, houses.size()])
	house_d /= houses.size()
	if not fields.is_empty():
		var field_d := 0.0
		for f in fields:
			field_d += f.pos.distance_to(st.center)
		field_d /= fields.size()
		assert_true(field_d > house_d, "the fields lie beyond the houses (%.0f m against %.0f m)" % [field_d, house_d])
	var ld := SettlementSim.ground(w)
	for b in others:
		if Siting.role(b.def()) == Siting.WOOD:
			var wood := 0.0
			for k in 8:
				wood += ld.canopy_smooth(b.pos + Vector2.from_angle(TAU * k / 8.0) * 35.0)
			assert_true(wood / 8.0 > 0.25, "the woodcutter at the edge of a wood (%.2f)" % (wood / 8.0))
