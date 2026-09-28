extends KDTestCase
## Rebirth, Phase 2: the homeland of Valverde — a finite valley closed by mountains, with its river, its lake, its
## woods, its rocks and its ways out, where six people can found something.

const HOMELAND := "valverde"


func after_each() -> void:
	Session.end()


func _session(seed_value: int) -> GameSession:
	return GameSession.create_new({"campaign_seed": seed_value})


func test_a_new_campaign_begins_in_the_homeland() -> void:
	var s := _session(2201)
	var d := s.world.domain
	assert_not_null(d, "the campaign has a valley")
	if d == null:
		return
	assert_eq(d.source, DomainState.SOURCE_HOMELAND, "a generated homeland, not a piece of the continent")
	assert_eq(d.homeland, HOMELAND, "the homeland of Valverde")
	var dd := DomainData.of(s.world)
	assert_true(dd.loaded, "its ground is there (%s)" % ", ".join(dd.errors))
	assert_true(dd.designed_woods, "with its own woods")
	assert_eq(dd.cell_m, 8.0, "relief, woods and biomes every 8 m")
	assert_eq(dd.fine_cell_m, 4.0, "water every 4 m")
	var st := s.world.settlements[0]
	assert_eq(st.name, "Valverde", "the community takes the valley's name")
	assert_true(st.center.distance_to(dd.founding_site()) < 2.0, "the fire is lit where the land offers it")
	var wd := WorldData.get_instance()
	assert_eq(wd.province_at(s.world.settlement_global_pos(st)), st.province,
		"on the map of the world the valley stands in its province")
	assert_eq(dd.province_at(st.center), st.province, "every dry field of the valley belongs to the home province")


## Closed by mountains, open only at its passes.
func test_the_valley_is_closed_by_mountains_but_for_its_passes() -> void:
	var s := _session(2202)
	var dd := DomainData.of(s.world)
	var size := dd.size_m
	var floor_h := dd.height_at(dd.founding_site())
	var passes: Array = dd.meta.get("passes", [])
	assert_eq(passes.size(), 4, "four ways out: two river gorges, two passes")
	# walk the rim 380 m inside the edge: high everywhere except where a way out is
	var inset := 380.0
	var ring: Array[Vector2] = []
	var steps := 240
	for i in steps:
		var t := float(i) / steps * 4.0
		var p: Vector2
		if t < 1.0:
			p = Vector2(lerpf(inset, size.x - inset, t), inset)
		elif t < 2.0:
			p = Vector2(size.x - inset, lerpf(inset, size.y - inset, t - 1.0))
		elif t < 3.0:
			p = Vector2(lerpf(size.x - inset, inset, t - 2.0), size.y - inset)
		else:
			p = Vector2(inset, lerpf(size.y - inset, inset, t - 3.0))
		ring.append(p)
	var low := 0
	var low_near_pass := 0
	for p in ring:
		if dd.height_at(p) < floor_h + 350.0:
			low += 1
			for ps: Dictionary in passes:
				var e: Array = ps["edge"]
				if p.distance_to(Vector2(float(e[0]), float(e[1]))) < 1300.0:
					low_near_pass += 1
					break
	assert_true(low <= steps / 8, "the rim is high almost everywhere (%d low points of %d)" % [low, steps])
	assert_eq(low_near_pass, low, "and every low point of the rim is at a pass (%d of %d)" % [low_near_pass, low])
	# the floor: wide, flat enough for a capital and its fields
	var flat := 0
	var probes := 0
	for y in range(1000, int(size.y) - 1000, 200):
		for x in range(1000, int(size.x) - 1000, 200):
			probes += 1
			if dd.is_land(Vector2(x, y)) and absf(dd.height_at(Vector2(x, y)) - floor_h) < 60.0:
				flat += 1
	assert_true(float(flat) / probes > 0.5, "most of the inside is the valley floor (%d of %d)" % [flat, probes])


func test_the_river_crosses_the_valley_through_its_gorges_and_the_lake_holds_water() -> void:
	var s := _session(2203)
	var dd := DomainData.of(s.world)
	var main: Dictionary = {}
	for r in dd.rivers:
		if int(r["id"]) == 0:
			main = r
	assert_false(main.is_empty(), "the valley has its river")
	if main.is_empty():
		return
	var pts: PackedVector2Array = main["points"]
	var gorges: Array[Vector2] = []
	for ps: Dictionary in dd.meta.get("passes", []):
		if String(ps.get("kind", "")) == "river":
			var e: Array = ps["edge"]
			gorges.append(Vector2(float(e[0]), float(e[1])))
	assert_eq(gorges.size(), 2, "the river has a gorge in and a gorge out")
	for g in gorges:
		assert_true(minf(pts[0].distance_to(g), pts[pts.size() - 1].distance_to(g)) < 300.0,
			"the river runs through its gorge at %s" % str(g))
	var mid := pts[pts.size() / 2]
	assert_true(dd.river_clearance(mid) < 0.0, "the middle of the river is water")
	assert_true(dd.water_at(mid) == WorldData.WATER_RIVER or dd.river_clearance(mid) < 0.0, "and the ground knows it")
	var lakes: Array = dd.meta.get("lakes", [])
	assert_eq(lakes.size(), 1, "one lake")
	var c: Array = lakes[0]["center"]
	assert_eq(dd.water_at(Vector2(float(c[0]), float(c[1]))), WorldData.WATER_LAKE, "with water in it")
	assert_eq(dd.province_at(Vector2(float(c[0]), float(c[1]))), -1, "a lake is nobody's field")


## What six people need is within reach of their fire; iron is rarer but exists.
func test_the_founders_have_water_food_wood_and_stone_at_hand() -> void:
	var s := _session(2204)
	var w := s.world
	var dd := DomainData.of(w)
	var st := w.settlements[0]
	var water := INF
	for k in 36:
		for r in range(20, 400, 10):
			var q := st.center + Vector2.from_angle(TAU * k / 36.0) * r
			if dd.river_clearance(q) < 0.0 or dd.water_at(q) != WorldData.WATER_LAND:
				water = minf(water, float(r))
				break
	assert_true(water <= 200.0, "water within two hundred metres (%.0f)" % water)
	assert_true(dd.river_clearance(st.center) > 40.0, "but the fire stands back from the bank")
	var stone := INF
	var iron := 0
	for r in LocalFeatures.outcrops_in_rect(dd, Rect2(Vector2.ZERO, dd.size_m)):
		if r["deposit"] == &"stone":
			stone = minf(stone, (r["pos"] as Vector2).distance_to(st.center))
		elif r["deposit"] == &"iron":
			iron += 1
	assert_true(stone <= 300.0, "stone within a short walk (%.0f m)" % stone)
	assert_true(iron > 0, "iron somewhere in the valley (%d rocks)" % iron)
	var trees := 0
	for t in LocalFeatures.trees_in_rect(dd, Rect2(st.center - Vector2(300, 300), Vector2(600, 600))):
		if t["kind"] == LocalFeatures.KIND_TREE and not w.terrain.is_felled(t["key"]):
			trees += 1
	assert_true(trees > 150, "a wood within a few hundred metres (%d trees)" % trees)
	var bd: BiomeDef = Defs.biome_by_index(dd.biome_at(st.center + SettlementPlanner.fields_direction(w, st) * 95.0))
	assert_true(bd != null and bd.fertility >= 0.5, "fertile ground on the side of the fields (%s)" % (bd.id if bd else "?"))
	assert_true(SettlementPlanner.find_spot(s, st.id, &"quarry", st.center, 30.0, false, 900.0) != Vector2.INF, "a quarry fits")
	st.stock[&"wood"] = 200
	assert_true(SettlementPlanner.find_spot(s, st.id, &"house", st.center, 24.0) != Vector2.INF, "and a house")


## The woods of a homeland are masses: thick where the land drew them, open where it did not.
func test_the_woods_are_masses_not_a_stipple() -> void:
	var s := _session(2205)
	var dd := DomainData.of(s.world)
	var inside := 0
	var inside_cells := 0
	var outside := 0
	var outside_cells := 0
	for y in range(900, int(dd.size_m.y) - 900, 97):
		for x in range(900, int(dd.size_m.x) - 900, 97):
			var p := Vector2(x, y) + Vector2(0.5, 0.5)
			var c := dd.canopy_smooth(p)
			var n := LocalFeatures.trees_in_rect(dd, Rect2(p - Vector2(18, 18), Vector2(36, 36)), false).size()
			if c > 0.7:
				inside += n
				inside_cells += 1
			elif c < 0.05:
				outside += n
				outside_cells += 1
	assert_true(inside_cells > 20 and outside_cells > 20, "the valley has woods and open land (%d / %d)" % [inside_cells, outside_cells])
	var dense := float(inside) / maxf(inside_cells, 1)
	var sparse := float(outside) / maxf(outside_cells, 1)
	assert_true(dense > 4.0, "a wood is thick (%.1f trees per 36 m square)" % dense)
	assert_true(sparse < dense * 0.1, "and the open land is open (%.2f against %.1f)" % [sparse, dense])


func test_the_homeland_travels_with_the_save() -> void:
	var s := _session(2206)
	SettlementPlanner.place_starter_village(s, s.world.settlements[0].id)
	s.advance_days(30)
	var back := SaveSystem.session_from_data(JSON.parse_string(JSON.stringify(SaveSystem.build_save_data(s))))
	assert_not_null(back, "the save opens")
	if back == null:
		return
	assert_eq(back.world.domain.homeland, HOMELAND, "in the same homeland")
	assert_eq(back.world.domain.key(), s.world.domain.key(), "the same valley")
	back.advance_days(10)
	assert_true(back.world.people_of(back.world.settlements[0].id).size() >= 6, "and life goes on there")
