extends KDTestCase
## Phase 17 check: nothing stands in the river as the player sees it. The water mask has 32 m cells and a river ten
## metres wide fell between them: a well stood in the water, a road started in it, a granary sat on the bank.

const Economy := preload("res://tests/unit/test_economy.gd")


func after_each() -> void:
	Session.end()


## A point on a river near the settlement, and the direction across it (in the valley's metres).
static func _river_near(w: WorldState, st: SettlementState) -> Dictionary:
	var wd := SettlementSim.ground(w)
	var best := {}
	var best_d := INF
	for r in wd.rivers:
		var pts: PackedVector2Array = r["points"]
		var ws: PackedFloat32Array = r["widths"]
		for i in range(3, pts.size() - 1):
			var d := pts[i].distance_to(st.center)
			if d < best_d and d < 1500.0:
				best_d = d
				var dir := (pts[i + 1] - pts[i]).normalized()
				best = {"pos": pts[i], "across": Vector2(-dir.y, dir.x), "width": ws[i]}
	return best


func test_a_well_is_not_built_in_the_river() -> void:
	var s := Economy.village(1751)
	var w := s.world
	var st := w.settlements[0]
	var wd := SettlementSim.ground(w)
	var river := _river_near(w, st)
	assert_false(river.is_empty(), "the start valley has its river")
	if river.is_empty():
		return
	var on_water: Vector2 = river["pos"]
	assert_true(wd.river_clearance(on_water) < 0.0, "the middle of the river is inside the river")
	st.stock[&"wood"] = 500
	st.stock[&"stone"] = 500
	var res := Placement.check(w, st, Defs.building(&"well"), on_water)
	assert_false(bool(res["ok"]), "no well in the river")
	assert_true(String(res["reason"]).contains("fiume") or String(res["reason"]).contains("acqua") or String(res["reason"]).contains("territorio"),
		"and it says why: %s" % res["reason"])
	var far: Vector2 = on_water + (river["across"] as Vector2) * (float(river["width"]) * 0.5 * WorldData.RIVER_BANK_WIDEN + 12.0)
	assert_true(wd.river_clearance(far) > 5.0, "a dozen metres past the bank the ground is dry (%.1f)" % wd.river_clearance(far))


func test_a_road_does_not_cross_the_river() -> void:
	var s := Economy.village(1752)
	var w := s.world
	var st := w.settlements[0]
	var river := _river_near(w, st)
	if river.is_empty():
		return
	var across: Vector2 = river["across"]
	var half := float(river["width"]) * 0.5 * WorldData.RIVER_BANK_WIDEN + 6.0
	var a: Vector2 = river["pos"] - across * half
	var b: Vector2 = river["pos"] + across * half
	var res := Placement.check_road(w, st, a, b)
	assert_false(bool(res["ok"]), "no road across the river without a bridge: %s" % res["reason"])


func test_no_tree_bush_or_rock_grows_on_the_water() -> void:
	var wd := WorldData.get_instance()
	var checked := 0
	var wrong := 0
	var r_index := 0
	for r in wd.rivers:
		r_index += 1
		if r_index % 12 != 0:
			continue   # a dozen rivers spread over the map are enough to see it
		var pts: PackedVector2Array = r["points"]
		for i in range(3, pts.size(), 7):
			var box := Rect2(pts[i] - Vector2(40, 40), Vector2(80, 80))
			for t in LocalFeatures.trees_in_rect(wd, box):
				checked += 1
				if wd.river_clearance(t["pos"]) < LocalFeatures.RIVER_CLEAR_M - 0.01:
					wrong += 1
			for rock in LocalFeatures.outcrops_in_rect(wd, box):
				if wd.river_clearance(rock["pos"]) < LocalFeatures.RIVER_CLEAR_M:
					wrong += 1
	assert_true(checked > 50, "trees along the rivers were looked at (%d)" % checked)
	assert_eq(wrong, 0, "none of them stands in the river or on its bank")


func test_the_village_keeps_its_feet_dry() -> void:
	var s := Economy.village(1753)
	var w := s.world
	var st := w.settlements[0]
	for m in 24:
		s.advance_days(30)
		Economy.lord_turn(s, 60)
	var wd := SettlementSim.ground(w)
	for b in w.buildings_of(st.id):
		if b.is_road():
			var n := int(ceil(b.a.distance_to(b.b) / 2.0))
			for i in n + 1:
				assert_true(wd.river_clearance(b.a.lerp(b.b, float(i) / maxf(float(n), 1.0))) >= BuildingState.road_width() * 0.5 - 0.01,
					"the road stays on dry ground")
			continue
		assert_false(Placement.touches_river(wd, b.rect()), "%s stands on dry ground" % b.def_id)

