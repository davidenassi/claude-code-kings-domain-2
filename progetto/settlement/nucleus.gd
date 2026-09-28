class_name Nucleus
extends RefCounted
## The nucleus of a community (Rebirth, Phase 3): the historic point the realm grows from. Six people arrive in the
## valley and make a place of it: a fire in the middle of a small trodden square, the store and the shelter behind
## it on the side away from the water, the point on the bank where the water is drawn and the path that leads
## there. Everything that is built later grows around this, and the square stays open: nobody builds over the
## common fire.
##
## Only the fire, the store, the shelter and the water point are buildings of the world (saved, selectable,
## refused to the builders); the square, the path and the evening around the fire follow from them.

const HEARTH := &"hearth"
const WATER_POINT := &"water_point"


static func balance() -> Dictionary:
	return Defs.balance("settlement").get("nucleus", {})


## The radius of the open square around the fire, where nothing may be built.
static func square_radius() -> float:
	return float(balance().get("square_radius_m", 9.0))


static func hearth_of(world: WorldState, s: SettlementState) -> BuildingState:
	if s == null:
		return null
	for b in world.buildings_of(s.id):
		if b.def_id == HEARTH:
			return b
	return null


static func water_point_of(world: WorldState, s: SettlementState) -> BuildingState:
	if s == null:
		return null
	for b in world.buildings_of(s.id):
		if b.def_id == WATER_POINT:
			return b
	return null


## True when the rectangle touches the circle.
static func rect_meets_circle(rect: Rect2, center: Vector2, radius: float) -> bool:
	var q := Vector2(clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y))
	return q.distance_to(center) < radius


## The nearest bank the founders can draw water from, walking straight from the fire: {"pos": the landing, on the
## bank; "dir": toward the water; "dist": metres from the fire} or {} when no river or lake is within reach.
static func water_spot(ld: WorldData, site: Vector2, reach: float = -1.0) -> Dictionary:
	if reach < 0.0:
		reach = float(balance().get("water_reach_m", 260.0))
	var best := {}
	for k in 48:
		var dir := Vector2.from_angle(TAU * float(k) / 48.0)
		var d := 6.0
		while d < reach:
			var p := site + dir * d
			if _is_water(ld, p):
				if best.is_empty() or d < float(best["dist"]):
					best = {"dist": d, "dir": dir}
				break
			d += 2.0
	if best.is_empty():
		return {}
	# back from the water until the bank is firm: the landing stands with its feet on the bank
	var dir: Vector2 = best["dir"]
	var d := float(best["dist"])
	while d > 4.0 and (_is_water(ld, site + dir * d) or ld.river_clearance(site + dir * d) < 1.2):
		d -= 0.5
	best["dist"] = d
	best["pos"] = site + dir * d
	return best


static func _is_water(ld: WorldData, p: Vector2) -> bool:
	return ld.river_clearance(p) < 0.0 or ld.water_at(p) != WorldData.WATER_LAND


static var _reach_cache: Dictionary = {}


## How the landing of a water point meets the water: {"dir": straight toward the nearest water from the landing,
## "dist": metres from the landing to the water}. The planks go that way, across the bank, and reach over the water.
static func landing_reach(ld: WorldData, wp: BuildingState) -> Dictionary:
	var key := "%d:%d:%d:%d" % [wp.id, roundi(wp.pos.x * 10.0), roundi(wp.pos.y * 10.0), ld.get_instance_id()]
	if _reach_cache.has(key):
		return _reach_cache[key]
	var best := {"dir": Vector2.UP, "dist": 3.0}
	var best_d := INF
	for k in 48:
		var dir := Vector2.from_angle(TAU * float(k) / 48.0)
		var d := 0.0
		while d < 14.0:
			if _is_water(ld, wp.pos + dir * d):
				if d < best_d:
					best_d = d
					best = {"dir": dir, "dist": d}
				break
			d += 0.25
	# a river is drawn with a bank of mud and reeds inside its ribbon (WorldData.RIVER_BANK_WIDEN): the open water
	# begins further out, where the ribbon's own water starts — walk to the middle of the river to find it
	var dir: Vector2 = best["dir"]
	var start := wp.pos + dir * float(best["dist"])
	if ld.water_at(start) == WorldData.WATER_LAND:
		var deepest := 0.0
		var d := 0.0
		while d < 80.0:
			var c := ld.river_clearance(start + dir * d)
			if c > deepest + 0.5:
				break
			deepest = minf(deepest, c)
			d += 0.5
		best["dist"] = float(best["dist"]) + (-deepest) * (1.0 - 1.0 / WorldData.RIVER_BANK_WIDEN)
	if _reach_cache.size() > 64:
		_reach_cache.clear()
	_reach_cache[key] = best
	return best


## Where who draws water stands: at the end of the planks, over the water.
static func draw_spot(world: WorldState, wp: BuildingState) -> Vector2:
	var r := landing_reach(SettlementSim.ground(world), wp)
	return wp.pos + (r["dir"] as Vector2) * (float(r["dist"]) + 0.6)


## Lays out the first things of a community around its fire at `s.center`. Returns
## {"hearth", "store", "shelter", "water"} (water is null when no bank is within reach). The store comes first:
## it is the first building of the settlement, the one the stores of the start are counted in.
static func lay_out(world: WorldState, s: SettlementState, ld: WorldData) -> Dictionary:
	var nb := balance()
	var site := s.center
	var water := water_spot(ld, site)
	# the store and the shelter stand behind the fire, on the side away from the water: the square opens toward it
	var back := Vector2(0.0, -1.0)
	if not water.is_empty():
		back = -(water["dir"] as Vector2)
	var dist := float(nb.get("store_back_m", 13.0))
	var store := SettlementSetup._add_building(world, s, &"camp_store",
		_spot_behind(world, s, &"camp_store", site, back, dist, -1.0, []))
	var shelter := SettlementSetup._add_building(world, s, &"shelter",
		_spot_behind(world, s, &"shelter", site, back, dist, 1.0, [store.rect()]))
	var hearth := SettlementSetup._add_building(world, s, HEARTH, site)
	var wp: BuildingState = null
	if not water.is_empty():
		wp = SettlementSetup._add_building(world, s, WATER_POINT, (water["pos"] as Vector2).snapped(Vector2(0.1, 0.1)))
	return {"hearth": hearth, "store": store, "shelter": shelter, "water": wp}


## Where a building of the nucleus goes: behind the fire and to one side, outside the square, on ground the
## builders would accept (dry, flat, no rock); turning round the fire and stepping back when the ground refuses.
## Falls back to the first choice, as the old founding did, if nothing around fits.
static func _spot_behind(world: WorldState, s: SettlementState, def_id: StringName, site: Vector2, back: Vector2,
		dist: float, side_sign: float, taken: Array[Rect2]) -> Vector2:
	var def := Defs.building(def_id)
	var aside := def.footprint.x * 0.5 + 4.0
	var first := Vector2.INF
	for k in 24:
		var dir := back.rotated(side_sign * float(k / 4) * 0.3)
		var side := Vector2(-dir.y, dir.x)
		var p := (site + dir * (dist + float(k % 4) * 3.0) + side * side_sign * aside).snapped(Vector2.ONE)
		if first == Vector2.INF:
			first = p
		var rect := Rect2(p - def.footprint * 0.5, def.footprint)
		if rect_meets_circle(rect, site, square_radius() + 1.0):
			continue
		var clash := false
		for r in taken:
			if r.grow(Placement.GAP_M).intersects(rect):
				clash = true
		if clash:
			continue
		if bool(Placement.check(world, s, def, p, true, true)["ok"]):
			return p
	return first


## The path the founders wore from the fire to the water: [from, to] or [] when there is no water point.
static func water_path(world: WorldState, s: SettlementState) -> Array:
	var wp := water_point_of(world, s)
	if wp == null:
		return []
	var from := s.center
	var to := wp.pos
	var dir := (to - from).normalized()
	# from the edge of the fire's stones to the top of the landing
	return [from + dir * 3.2, to - dir * 0.8]


## The trees the founders cleared for the path to the water and for the landing: trodden ground, they do not
## grow back.
static func clear_the_way(world: WorldState, s: SettlementState, ld: WorldData) -> void:
	var path := water_path(world, s)
	if path.is_empty():
		return
	var a: Vector2 = path[0]
	var b: Vector2 = path[1]
	var bounds := Rect2(a, Vector2.ZERO).expand(b).grow(5.0)
	for t in LocalFeatures.trees_in_rect(ld, bounds):
		var q: Vector2 = t["pos"]
		if Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q) <= 2.6 or q.distance_to(b) < 4.5:
			world.terrain.fell(t, world.day, true)


## The benches round the fire, [prop, feet of the prop from the fire]: two split logs behind it and one in front,
## lying east-west.
const BENCHES := [["bench_0", Vector2(-2.7, -2.3)], ["bench_0", Vector2(2.7, -2.3)], ["bench_0", Vector2(0.0, 3.3)]]
## Two places on each bench, from the fire.
const SEATS := [Vector2(-3.25, -2.4), Vector2(-2.15, -2.4), Vector2(2.15, -2.4), Vector2(3.25, -2.4),
	Vector2(-0.55, 3.2), Vector2(0.55, 3.2)]
## Where the pole with the banner of the community stands, from the fire: at the edge of the square.
const BANNER := Vector2(6.4, -4.6)
## Places standing round the fire, on the open side, after the benches.
const STANDING := 8


## Which place round the fire a person takes on a given evening, among `people` in the community: while they are
## no more than the seats of the benches everybody sits; then some stand. Ids of people go up two by two (a
## family is created with each founder), so the six founders of a new community always get six different seats;
## in a town some share a place, and nobody notices.
static func seat_slot(person_id: int, day: int, people: int = 99) -> int:
	var places := SEATS.size() if people <= SEATS.size() else SEATS.size() + STANDING
	return posmod(person_id / 2 + day, places)


static func seat(hearth: BuildingState, person_id: int, day: int, people: int = 99) -> Vector2:
	var k := seat_slot(person_id, day, people)
	if k < SEATS.size():
		return hearth.pos + SEATS[k]
	var a := lerpf(-0.15, PI + 0.15, float(k - SEATS.size()) / float(STANDING - 1))
	return hearth.pos + Vector2(cos(a) * 5.4, sin(a) * 4.4)


## What a person does at the fire: sits on a bench, or stands warming the hands.
static func evening_action(person_id: int, day: int, people: int = 99) -> StringName:
	return &"sit" if seat_slot(person_id, day, people) < SEATS.size() else &"warm"


## The first trails out of the square: toward the edge of the nearest wood and toward the open land of the fields,
## the lines the village will grow along. [[from, to], ...]; none without a fire. Only drawn.
static func trails(world: WorldState, s: SettlementState) -> Array:
	var hearth := hearth_of(world, s)
	if hearth == null:
		return []
	var ld := SettlementSim.ground(world)
	var out: Array = []
	var from_r := square_radius() + 1.0
	var blockers: Array[Rect2] = []
	for b in world.buildings_of(s.id):
		if not b.is_road() and b.def_id != HEARTH:
			blockers.append(b.rect().grow(1.0))
	# to the wood, as far as its edge
	var wood := SettlementPlanner.wood_direction(world, s)
	var d := from_r
	while d < 320.0 and ld.canopy_smooth(s.center + wood * d) < 0.45:
		d += 4.0
	_add_trail(out, ld, s.center, wood, from_r, d if d < 320.0 else 140.0, blockers)
	# to the open land where the fields will be
	var fields := SettlementPlanner.fields_direction(world, s)
	if fields.dot(wood) < 0.8:
		_add_trail(out, ld, s.center, fields, from_r, 110.0, blockers)
	return out


static func _add_trail(out: Array, ld: WorldData, center: Vector2, dir: Vector2, from_r: float, to_r: float,
		blockers: Array[Rect2]) -> void:
	if to_r - from_r < 12.0:
		return
	for turn: float in [0.0, 0.25, -0.25, 0.5, -0.5]:
		var dd := dir.rotated(turn)
		var a := center + dd * from_r
		var b := center + dd * to_r
		var clear := true
		for r in blockers:
			if SettlementLayer.segment_hits_rect(a, b, r):
				clear = false
				break
		if clear and not SettlementLayer._crosses_river(ld, a, b):
			out.append([a, b])
			return
