class_name SettlementPlanner
extends RefCounted
## Finds valid spots for buildings with the same rules as the player (Placement). Used by the ConstructionPlanner of
## AI settlements in later phases, by development scenarios and by tests.


## Nearest valid spot around `near`; with prefer_cleared the search keeps the spot with fewest trees.
## World art pass: with `organic` (the careful lord of lord_month) the candidates no longer sit on sixteen fixed
## rays of concentric rings — the villages of the pilot came out as circles of houses at equal distances: every
## ring turns by the golden angle and every point is pushed a little in angle and distance, deterministically
## (settlement, ring, point). Without it the search is the one it always was (the royal seat, the scenarios).
static func find_spot(session: GameSession, settlement_id: int, def_id: StringName, near: Vector2, min_r: float = 30.0,
		prefer_cleared: bool = false, max_r: float = 400.0, founding: bool = false, organic: bool = false) -> Vector2:
	var s := session.world.settlement(settlement_id)
	var def := Defs.building(def_id)
	# the materials do not depend on the spot: checked once, not on every ring (Phase 16: counting what the
	# other sites still owe walks every building and every person, and a village short of stone did it hundreds
	# of times a month for nothing)
	if not affordable(session.world, s, def):
		return Vector2.INF
	var best := Vector2.INF
	var best_trees := 1 << 30
	var r := min_r
	var ring := 0
	var phase := KDRng.hash01(settlement_id, def_id.hash() & 0xffff, 3301) * TAU
	while r < max_r:
		for k in 16:
			var a := TAU * k / 16.0 + r * 0.01
			var rr := r
			if organic:
				a = phase + ring * 2.39996 + TAU * (float(k) + 0.8 * KDRng.hash01(ring, k, 3302 + settlement_id)) / 16.0
				rr = maxf(r + (KDRng.hash01(ring, k, 3303 + settlement_id) - 0.5) * 9.0, min_r * 0.5)
			var p := (near + Vector2.from_angle(a) * rr).snapped(Vector2.ONE)
			var res := Placement.check(session.world, s, def, p, true, founding)
			if not bool(res["ok"]):
				continue
			if not prefer_cleared:
				return p
			if int(res["trees"]) < best_trees:
				best_trees = int(res["trees"])
				best = p
		if prefer_cleared and best != Vector2.INF and best_trees == 0:
			return best
		r += 12.0
		ring += 1
	return best


## True when the stores, minus what the open sites still owe, pay for the building.
static func affordable(world: WorldState, s: SettlementState, def: BuildingDef) -> bool:
	if def.cost.is_empty():
		return true
	var pending := Placement.committed_materials(world, s.id)
	for res: StringName in def.cost.keys():
		if s.amount(res) - int(pending.get(res, 0)) < int(def.cost[res]):
			return false
	return true


## Development scenario: opens the sites of a small working village around the keep.
static func place_starter_village(session: GameSession, settlement_id: int) -> Array[int]:
	var out: Array[int] = []
	var world := session.world
	var keep := world.buildings_of(settlement_id)[0]
	var st := world.settlement(settlement_id)
	for def_id: StringName in [&"woodcutter", &"farm", &"house", &"bakery", &"well"]:
		# Rebirth: the valley's woods are masses with open ground between them, not a stipple everywhere — the
		# woodcutter goes to the edge of the wood and the fields to the open side, as the careful lord does
		var near := keep.pos
		var min_r := 36.0
		if def_id in [&"woodcutter", &"farm"]:
			var zone := zone_of(session, st, def_id)
			near = zone["near"]
			min_r = float(zone["min_r"])
		var spot := find_spot(session, settlement_id, def_id, near, min_r)
		if spot == Vector2.INF:
			continue
		var res := session.submit(PlaceBuildingCommand.create(settlement_id, def_id, spot))
		if res.success:
			out.append(int(res.data["building"]))
	# a beaten path from the keep to the first workplace it can reach without crossing anything
	for id: int in out.duplicate():
		var target := world.building(id)
		if target == null or target.is_road():
			continue
		var to := target.pos + Vector2(0, target.def().footprint.y * 0.5 + 3.5)
		var placed_road := false
		for off: Vector2 in [Vector2(-10, 1), Vector2(0, 1), Vector2(10, 1), Vector2(-12, -2)]:
			var from := keep.pos + Vector2(off.x, keep.def().footprint.y * 0.5 * off.y + 3.5 * off.y)
			var road := session.submit(PlaceRoadCommand.create(settlement_id, from, to))
			if road.success:
				out.append(int(road.data["building"]))
				placed_road = true
				break
		if placed_road:
			break
	return out


## Development scenario and campaigns: one month of a careful lord — what a player who reads the top bar would
## build. The wishes come in order (a field, a wood, a roof and an oven first; then ovens enough for the grain,
## granaries enough for a year, fields when the food does not reach the harvest, roofs when the beds are full,
## woods and quarries when the materials run out) and the first one that can really be built is built: a wish
## that cannot be paid or placed gives way to the next, it does not stop the village (Phase 16).
static func lord_month(session: GameSession, settlement_id: int, max_people: int = 1000) -> void:
	var world := session.world
	var st := world.settlement(settlement_id)
	if st == null:
		return
	var have := {}
	var sites := 0
	for b in world.buildings_of(st.id):
		if not b.is_active():
			sites += 1
		elif not b.is_road():
			have[b.def_id] = int(have.get(b.def_id, 0)) + 1
	if sites >= 2:
		return
	var people := world.people_of(st.id).size()
	var outlook := PopulationSystem.harvest_outlook(session, st)
	var food_days := PopulationSystem.food_days(world, st)
	var need_per_day := float(Defs.balance("settlement").get("food_per_person_day", 0.25)) * people
	var ovens := PopulationSystem._ovens(world, st)
	var baked_per_day := 0.0
	for res: StringName in ovens.keys():
		baked_per_day += float(ovens[res]["per_day"]) * float(ovens[res]["value"])
	var idle := 0
	for p in world.people_of(st.id):
		if p.job == &"idle":
			idle += 1
	var wishes: Array[StringName] = []
	for first: StringName in [&"farm", &"woodcutter", &"house", &"bakery"]:
		if not have.has(first):
			wishes.append(first)
	# materials: a wood for every twenty souls when the wood runs low, a quarry when the stone does
	if st.amount(&"wood") < 40 + people and int(have.get(&"woodcutter", 0)) < 1 + people / 20:
		wishes.append(&"woodcutter")
	if st.amount(&"stone") < 20 + people / 2 and int(have.get(&"quarry", 0)) < 1 + people / 60:
		wishes.append(&"quarry")
	if baked_per_day < need_per_day * 0.8 and st.amount(&"grain") > 150:
		wishes.append(&"bakery")   # grain in the granary and not enough ovens: raw grain feeds far fewer people
	if bool(outlook["needs_granary"]):
		wishes.append(&"granary")
	# more fields only when the harvest can be kept: a granary short of room loses what a new field grows
	var room := not bool(outlook["needs_granary"])
	if (food_days < 120.0 or bool(outlook["short"])) and room:
		wishes.append(&"farm")
	if PopulationSystem.free_beds(world, st) <= 2 and people < max_people:
		wishes.append(&"house")
	if idle >= 3 and food_days < 400.0 and room:
		wishes.append(&"farm")   # hands with nothing to do: another field is next year's bread
	if not have.has(&"well"):
		wishes.append(&"well")
	if st.space_for(world, &"wood") < 80:
		wishes.append(&"storehouse")
	var tried := {}
	for want in wishes:
		if tried.has(want):
			continue
		tried[want] = true
		if not affordable(world, st, Defs.building(want)):
			continue
		var zone := zone_of(session, st, want)
		var spot := find_spot(session, st.id, want, zone["near"], float(zone["min_r"]), false,
			900.0 if want == &"quarry" else 600.0, false, true)
		if spot != Vector2.INF and session.submit(PlaceBuildingCommand.create(st.id, want, spot)).success:
			return


## Where a careful lord puts each kind of building (world art pass): the houses around the square, the well on
## it, the fields together in a farming district on the side where the land is free and dry, the granary, the
## stores, the oven and the smithy between the houses and the fields, the woodcutter towards the wood. A village
## grows rings of use instead of a mix of house, field, house, field.
static func zone_of(session: GameSession, st: SettlementState, def_id: StringName) -> Dictionary:
	var fields := fields_direction(session.world, st)
	match def_id:
		&"well":
			return {"near": st.center, "min_r": 12.0}
		&"house":
			return {"near": st.center, "min_r": 24.0}
		&"farm":
			return {"near": st.center + fields * 95.0, "min_r": 0.0}
		&"granary", &"storehouse", &"bakery", &"smith", &"barracks":
			return {"near": st.center + fields.rotated(0.5 if def_id in [&"bakery", &"smith"] else -0.5) * 42.0, "min_r": 0.0}
		&"woodcutter":
			return {"near": st.center + wood_direction(session.world, st) * 110.0, "min_r": 0.0}
	return {"near": st.center, "min_r": 32.0}


static var _fields_dir: Dictionary = {}   # "id:x:y" -> Vector2 (the place, not only the id: worlds change)


## The side of the settlement with the most free, dry, gentle land: where its fields go. Decided once.
static func fields_direction(world: WorldState, st: SettlementState) -> Vector2:
	var key := "%d:%d:%d:%s" % [st.id, int(st.center.x), int(st.center.y), world.domain.key() if world.domain else ""]
	if _fields_dir.has(key):
		return _fields_dir[key]
	var wd := SettlementSim.ground(world)
	var best := Vector2.RIGHT
	var best_score := -INF
	for k in 12:
		var dir := Vector2.from_angle(TAU * float(k) / 12.0)
		var score := 0.0
		for d: float in [60.0, 100.0, 140.0, 180.0]:
			var p := st.center + dir * d
			if wd.water_at(p) != WorldData.WATER_LAND or wd.river_clearance(p) < 30.0:
				score -= 3.0
				continue
			score += 1.0 - clampf(wd.canopy_smooth(p) * 1.5, 0.0, 1.0)   # open land, not the wood
		score += KDRng.hash01(st.id, k, 3310) * 0.3
		if score > best_score:
			best_score = score
			best = dir
	_fields_dir[key] = best
	return best


## Towards the nearest thick wood (where a woodcutter has trees to fell).
static func wood_direction(world: WorldState, st: SettlementState) -> Vector2:
	var wd := SettlementSim.ground(world)
	var best := -fields_direction(world, st)
	var best_score := -INF
	for k in 12:
		var dir := Vector2.from_angle(TAU * float(k) / 12.0)
		var score := 0.0
		for d: float in [90.0, 140.0, 200.0]:
			score += wd.canopy_smooth(st.center + dir * d)
		if score > best_score:
			best_score = score
			best = dir
	return best

