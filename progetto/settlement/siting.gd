class_name Siting
extends RefCounted
## The organic growth of a settlement (Rebirth, Phase 4). The player chooses WHAT to build and the GENERAL AREA; the
## game finds, around that point, the place a villager would have chosen: the house with its door on a way (a road,
## the path to the water, a trail of the founders, the worn path between the doors), next to the other houses
## but not on top of them, on the same front line as its neighbour, in the ring of the homes round the square; the
## oven and the stores between the houses and the fields; the field on good soil against the other fields, away
## from the doors; the woodcutter at the edge of a wood; the quarry and the mine on their rocks.
##
## Hierarchy of a place, from the fire outwards: NUCLEUS (the square) → HOMES → CRAFTS AND STORES → FIELDS →
## OUTSKIRTS (wood, stone, iron) → NATURE. The rings widen as the people grow.
##
## Only the choice of the spot: the command that opens the site is the same (PlaceBuildingCommand) and the rules of
## the ground are the same (Placement.check). The same inputs always give the same spot.

const HOME := &"home"
const CRAFT := &"craft"
const STORE := &"store"
const SERVICE := &"service"
const FIELD := &"field"
const WOOD := &"wood"
const STONE := &"stone"
const MINE := &"mine"
const MILITARY := &"military"
const SEAT := &"seat"
## A quarter of a town (Rebirth, Phase 5): a block of houses, workshops, stores… at the edge of what is built.
const DISTRICT := &"district"

## How far from the chosen point the game may move a building, by role (metres).
const RADIUS := {HOME: 20.0, CRAFT: 22.0, STORE: 22.0, SERVICE: 14.0, FIELD: 40.0, WOOD: 36.0, STONE: 36.0,
	MINE: 36.0, MILITARY: 26.0, SEAT: 30.0, DISTRICT: 50.0}
const STEP_M := 2.0
## How much the player's point weighs: every metre away costs this much of the score.
const W_CURSOR := 0.12
## How many of the best candidates go through the full check of the ground before giving up.
const CHECKED := 16


static func role(def: BuildingDef) -> StringName:
	if def.is_district():
		return FIELD if def.district_kind() == &"farming" else DISTRICT
	match def.id:
		&"house":
			return HOME
		&"bakery", &"smith":
			return CRAFT
		&"granary", &"storehouse":
			return STORE
		&"well":
			return SERVICE
		&"barracks":
			return MILITARY
		&"keep":
			return SEAT
	match def.work_type():
		&"farm":
			return FIELD
		&"fell_trees":
			return WOOD
		&"quarry_rock":
			return MINE if StringName(def.requires.get("deposit", "stone")) == &"iron" else STONE
	return HOME if def.beds > 0 else CRAFT


static func radius_for(def: BuildingDef) -> float:
	return float(RADIUS.get(role(def), 20.0))


## The best spot for `def` around `cursor`: {"ok", "pos", "check" (Placement.check at pos), "moved" (metres)}. When
## nothing around fits, "ok" is false and "check" says why the chosen point itself is refused.
static func refine(world: WorldState, s: SettlementState, def: BuildingDef, cursor: Vector2, radius: float = -1.0,
		ignore_cost: bool = false, founding: bool = false) -> Dictionary:
	cursor = cursor.snapped(Vector2.ONE)
	if def == null or s == null or def.is_line:
		return {"ok": false, "pos": cursor, "check": Placement.check(world, s, def, cursor, ignore_cost, founding), "moved": 0.0}
	if radius < 0.0:
		radius = radius_for(def)
	var ctx := context(world, s, def, cursor, radius)
	var scored: Array = []
	var step := maxf(STEP_M, snappedf(radius / 10.0, 1.0))   # a field is looked for on a coarser grid than a house
	var n := int(radius / step)
	var loose: bool = ctx["role"] == FIELD   # fields on a grid read as a chessboard: each candidate a little off it
	for iy in range(-n, n + 1):
		for ix in range(-n, n + 1):
			var p := cursor + Vector2(ix, iy) * step
			if loose:
				p += (Vector2(KDRng.hash01(ix, iy, 4411), KDRng.hash01(ix, iy, 4412)) - Vector2(0.5, 0.5)) * step * 0.8
				p = p.snapped(Vector2.ONE)
			if p.distance_to(cursor) > radius + 0.01 or not _may_stand(ctx, p):
				continue
			scored.append([score(ctx, p), p])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for entry: Array in scored.slice(0, CHECKED):
		var p: Vector2 = entry[1]
		var check := Placement.check(world, s, def, p, ignore_cost, founding)
		if bool(check["ok"]):
			return {"ok": true, "pos": p, "check": check, "moved": p.distance_to(cursor), "score": float(entry[0])}
		if not String(check["reason"]).begins_with("Mancano materiali"):
			continue
		return {"ok": false, "pos": p, "check": check, "moved": p.distance_to(cursor)}   # the stores, not the spot
	return {"ok": false, "pos": cursor, "check": Placement.check(world, s, def, cursor, ignore_cost, founding), "moved": 0.0}


# --- what the choice looks at --------------------------------------------------------------------------

## Everything the score needs, gathered once for a choice.
static func context(world: WorldState, s: SettlementState, def: BuildingDef, cursor: Vector2, radius: float) -> Dictionary:
	var hearth := Nucleus.hearth_of(world, s)
	var centre := hearth.pos if hearth else s.center
	var people := world.people_of(s.id).size()
	var reach := radius + 60.0
	var near: Array = []   # [rect, role, pos]
	for b in world.buildings_of(s.id):
		if b.is_road():
			continue
		if b.pos.distance_to(cursor) <= reach + b.def().footprint.length():
			near.append([b.rect(), role(b.def()) if b.def_id != Nucleus.HEARTH else SEAT, b.pos])
	var ways: Array = []
	for w: Array in ways_of(world, s):
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		if Geometry2D.get_closest_point_to_segment(cursor, a, b).distance_to(cursor) <= reach:
			ways.append(w)
	# both indexed on a coarse grid: a candidate looks only at what stands within a few dozen metres of it (in a
	# village of three hundred buildings every candidate used to measure itself against all of them)
	var near_grid := {}
	for i in near.size():
		for c in _cells((near[i][0] as Rect2)):
			var list: Array = near_grid.get(c, [])
			list.append(i)
			near_grid[c] = list
	var way_grid := {}
	for i in ways.size():
		for c in _cells(Rect2(ways[i][0], Vector2.ZERO).expand(ways[i][1])):
			var list: Array = way_grid.get(c, [])
			list.append(i)
			way_grid[c] = list
	return {"world": world, "s": s, "def": def, "role": role(def), "cursor": cursor, "centre": centre,
		"people": people, "near": near, "ways": ways, "ground": SettlementSim.ground(world),
		"square": Nucleus.square_radius() if hearth else 0.0, "near_grid": near_grid, "way_grid": way_grid}


const GRID_M := 20.0


static func _cells(r: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(int(floor(r.position.y / GRID_M)), int(floor(r.end.y / GRID_M)) + 1):
		for x in range(int(floor(r.position.x / GRID_M)), int(floor(r.end.x / GRID_M)) + 1):
			out.append(Vector2i(x, y))
	return out


## The indices of the entries of a grid of the context that may lie within `reach` of the rectangle.
static func _around(grid: Dictionary, r: Rect2, reach: float) -> Dictionary:
	var out := {}
	for c in _cells(r.grow(reach)):
		for i: int in grid.get(c, []):
			out[i] = true
	return out


static var _ways_cache: Dictionary = {}


## The ways of a settlement, the lines the doors look for: its roads, the path to the water, the first trails of
## the founders and the paths worn between the doors. [[a, b], ...], rebuilt when the buildings change.
static func ways_of(world: WorldState, s: SettlementState) -> Array:
	var key := "%d:%d:%d" % [world.get_instance_id(), s.id, world.buildings_version]
	if _ways_cache.has(key):
		return _ways_cache[key]
	var out: Array = []
	for b in world.buildings_of(s.id):
		if b.is_road():
			out.append([b.a, b.b])
	var water := Nucleus.water_path(world, s)
	if not water.is_empty():
		out.append([water[0], water[1]])
	for t: Array in Nucleus.trails(world, s):
		out.append([t[0], t[1]])
	for e: Array in SettlementLayer.footpaths(world, s):
		out.append([e[0], e[1]])
	if _ways_cache.size() > 8:
		_ways_cache.clear()
	_ways_cache[key] = out
	return out


## Cheap refusals before the full check: over another building (with its gap), on the square, in the water.
static func _may_stand(ctx: Dictionary, p: Vector2) -> bool:
	var def: BuildingDef = ctx["def"]
	var rect := Rect2(p - def.footprint * 0.5, def.footprint)
	var grown := rect.grow(Placement.GAP_M)
	var near: Array = ctx["near"]
	for i: int in _around(ctx["near_grid"], grown, 0.0):
		if (near[i][0] as Rect2).intersects(grown):
			return false
	if float(ctx["square"]) > 0.0 and Nucleus.rect_meets_circle(rect, ctx["centre"], float(ctx["square"])):
		return false
	var ld: WorldData = ctx["ground"]
	return ld.water_at(p) == WorldData.WATER_LAND and ld.river_clearance(p) > def.footprint.length() * 0.5


## The distance to the nearest way, looked for within 20 m (beyond that it only has to be "far").
static func _way_distance(ctx: Dictionary, p: Vector2) -> float:
	var best := INF
	var ways: Array = ctx["ways"]
	for i: int in _around(ctx["way_grid"], Rect2(p, Vector2.ZERO), GRID_M):
		var w: Array = ways[i]
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, w[0], w[1]).distance_to(p))
	return best


static func _way_under(ctx: Dictionary, rect: Rect2) -> bool:
	var ways: Array = ctx["ways"]
	for i: int in _around(ctx["way_grid"], rect, 0.0):
		var w: Array = ways[i]
		if SettlementLayer.segment_hits_rect(w[0], w[1], rect):
			return true
	return false


## The ring of each role round the fire, [inner, outer] in metres, wider as the people grow.
static func ring(role_id: StringName, people: int, square: float) -> Vector2:
	var grow := sqrt(float(maxi(people, 6)))
	match role_id:
		HOME:
			return Vector2(square + 3.0, 26.0 + 3.2 * grow)
		SERVICE:
			return Vector2(square + 1.0, 18.0 + 2.0 * grow)
		CRAFT, STORE:
			return Vector2(square + 10.0, 40.0 + 4.0 * grow)
		MILITARY:
			return Vector2(30.0, 70.0 + 4.0 * grow)
		FIELD:
			return Vector2(45.0 + 1.5 * grow, 240.0 + 8.0 * grow)
		DISTRICT:
			# the quarters close round the old village, ring after ring (measured to their middle: a block is 40 m)
			return Vector2(square + 45.0, 95.0 + 9.0 * grow)
	return Vector2(0.0, 100000.0)


## How good a spot is for the building of the context (higher is better). Deterministic.
static func score(ctx: Dictionary, p: Vector2) -> float:
	var def: BuildingDef = ctx["def"]
	var r: StringName = ctx["role"]
	var fp := def.footprint
	var rect := Rect2(p - fp * 0.5, fp)
	var sc := -W_CURSOR * p.distance_to(ctx["cursor"])
	# the ring of the role round the fire
	var band := ring(r, int(ctx["people"]), float(ctx["square"]))
	var dh := p.distance_to(ctx["centre"])
	if dh < band.x:
		sc -= 0.12 * (band.x - dh)
	elif dh > band.y:
		sc -= 0.05 * (dh - band.y)
	# the gap to the nearest neighbour, and the neighbours of the same kind
	var gap := INF
	var same_row := false
	var same_kind := 0
	var fields_near := 0
	var homes_near := 0
	var near: Array = ctx["near"]
	var around := _around(ctx["near_grid"], rect, 2.0 * GRID_M)   # what counts is within 30 m
	for i: int in around:
		var n: Array = near[i]
		var nr: Rect2 = n[0]
		var g := _rect_gap(rect, nr)
		gap = minf(gap, g)
		var np: Vector2 = n[2]
		if n[1] == r and g < 30.0:
			same_kind += 1
			if absf(np.y - p.y) < 1.2 and absf(np.x - p.x) < 30.0:
				same_row = true
		if n[1] == FIELD and g < 6.0:
			fields_near += 1
		if n[1] == HOME and g < 12.0:
			homes_near += 1
	match r:
		DISTRICT:
			# a quarter shares its streets with the next one: blocks side by side and in line make a town, blocks
			# with meadow between them make a scatter of islands
			if gap < 2.5:
				sc -= 1.2 * (2.5 - gap)
			elif gap < 6.0:
				sc += 2.2
			elif gap < 14.0:
				sc += 0.6
			else:
				sc -= 0.8
			for i: int in around:
				var nr: Rect2 = near[i][0]
				if near[i][1] == DISTRICT or near[i][1] == FIELD:
					if absf(nr.position.y - rect.position.y) < 2.0 or absf(nr.end.y - rect.end.y) < 2.0:
						sc += 0.9
						break
			for i: int in around:
				var nr: Rect2 = near[i][0]
				if near[i][1] == DISTRICT and (absf(nr.position.x - rect.position.x) < 2.0 or absf(nr.end.x - rect.end.x) < 2.0):
					sc += 0.7
					break
			sc -= 0.01 * dh   # the town stays round its heart
		HOME, CRAFT, STORE, SERVICE, MILITARY, SEAT:
			# the door on a way, never a way under the roof
			var door := p + Vector2(0.0, fp.y * 0.5 + 0.8)
			var dw := _way_distance(ctx, door)
			sc += 1.6 * (1.0 - clampf((dw - 2.5) / 10.0, 0.0, 1.0))
			if _way_under(ctx, rect.grow(0.5)):
				sc -= 2.5
			# close to the others, not on top of them: a village, not a scatter and not a heap
			if gap < 2.5:
				sc -= 1.5 * (2.5 - gap)
			elif gap < 8.0:
				sc += 1.2
			elif gap < 20.0:
				sc += 0.5
			else:
				sc -= 0.3   # nothing within twenty metres
			if same_row:
				sc += 0.8
			if r == HOME:
				sc += minf(float(same_kind), 4.0) * 0.15
				sc -= float(fields_near) * 0.6   # a house does not stand in the fields
			if r == SERVICE:
				sc += minf(float(homes_near), 5.0) * 0.3   # the well among the doors
		FIELD:
			var ld: WorldData = ctx["ground"]
			var fert := 0.0
			for q: Vector2 in [p, rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
				var bd: BiomeDef = Defs.biome_by_index(ld.biome_at(q))
				fert += bd.fertility if bd else 0.0
			sc += fert / 5.0 * 3.0
			# a patchwork: the fields side by side, the doors kept away
			if gap < 1.0:
				sc -= 1.0
			elif fields_near > 0:
				sc += 1.5
			sc -= minf(float(homes_near), 3.0) * 0.7
		WOOD:
			var ld: WorldData = ctx["ground"]
			var wood := 0.0
			for k in 8:
				wood += ld.canopy_smooth(p + Vector2.from_angle(TAU * k / 8.0) * 35.0)
			sc += wood / 8.0 * 3.5 - ld.canopy_smooth(p) * 1.5   # at the edge: the wood around, the yard clear
			if same_kind > 0:
				sc -= 1.0
		STONE, MINE:
			var ld: WorldData = ctx["ground"]
			var within := float(def.requires.get("rocks_within_m", 40.0))
			var dep := StringName(def.requires.get("deposit", "stone"))
			var rocks := 0
			for rock in LocalFeatures.outcrops_in_rect(ld, Rect2(p - Vector2(within, within), Vector2(within, within) * 2.0)):
				if rock["deposit"] == dep and (rock["pos"] as Vector2).distance_to(p) <= within:
					rocks += 1
			sc += minf(float(rocks), 10.0) * 0.3
	return sc


## The empty distance between two rectangles (0 when they touch or overlap).
static func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(b.position.x - a.end.x, a.position.x - b.end.x), 0.0)
	var dy := maxf(maxf(b.position.y - a.end.y, a.position.y - b.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)
