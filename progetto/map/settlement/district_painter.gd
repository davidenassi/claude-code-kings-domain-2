class_name DistrictPainter
extends RefCounted
## What a quarter of a town looks like (Rebirth, Phase 5). A district is ONE building of the world; on the map it is
## drawn as the block it stands for: a lane across it and one down it, rows of houses along the lanes with their
## doors on them, and what makes the quarter what it is — the ovens and the forges of the craftsmen, the square and
## the stalls of the market, the church with its churchyard, the barracks round a yard of arms, the warehouses and
## their carts, the farmsteads at the edge of the fields. The higher its level, the fuller and the more of stone.
##
## Only a picture: the pieces are chosen from the id and the level of the district (the same after a reload) and
## nothing in them exists for the simulation. A town of ten thousand is a few dozen of these, not two thousand houses.

const HOUSES := ["house", "house_1", "house_2", "house_3", "house_4"]
## How full the rows of a quarter are at each level.
const FILL := [0.5, 0.78, 0.96]
const SLOT_M := 7.4
const PIECE_SCALE := 0.82

static var _cache: Dictionary = {}


static func _h(b: BuildingState, k: int, salt: int) -> float:
	return KDRng.hash01(b.id, k, salt)


## {"lanes": [[a, b], ...], "pieces": [[sprite, feet, scale], ...] (back to front), "props": [[prop, feet], ...],
## "yard": Rect2 (an open square or yard, or an empty rect), "gardens": [Rect2, ...]}. Cached by id, level and place.
static func layout(b: BuildingState) -> Dictionary:
	var key := "%d:%d:%d:%d" % [b.id, b.level, roundi(b.pos.x), roundi(b.pos.y)]
	if _cache.has(key):
		return _cache[key]
	var def := b.def()
	var kind := def.district_kind()
	var r := b.rect()
	var fp := def.footprint
	var lanes: Array = []
	var pieces: Array = []
	var props: Array = []
	var fill: float = FILL[clampi(b.level, 1, FILL.size()) - 1]
	# a medieval block: the streets run round it (shared with the next block, so a town of blocks is a net of
	# streets), the houses line its edges with their backs to a courtyard of gardens, and what makes the quarter
	# what it is stands in the middle
	var cx := r.get_center().x + (_h(b, 2, 881) - 0.5) * fp.x * 0.1
	var cy := r.get_center().y + (_h(b, 1, 881) - 0.5) * fp.y * 0.1
	if kind == &"farming":
		# a hamlet at the head of its fields: one track in front of the farmsteads, none through the crops
		lanes.append([Vector2(r.position.x - 1.0, r.position.y + 8.6), Vector2(r.end.x + 1.0, r.position.y + 8.6)])
	else:
		lanes.append([Vector2(r.position.x - 1.5, r.position.y - 1.5), Vector2(r.end.x + 1.5, r.position.y - 1.5)])
		lanes.append([Vector2(r.position.x - 1.5, r.end.y + 1.5), Vector2(r.end.x + 1.5, r.end.y + 1.5)])
		lanes.append([Vector2(r.position.x - 1.5, r.position.y - 1.5), Vector2(r.position.x - 1.5, r.end.y + 1.5)])
		lanes.append([Vector2(r.end.x + 1.5, r.position.y - 1.5), Vector2(r.end.x + 1.5, r.end.y + 1.5)])
		if b.level >= 2 or kind in [&"market", &"religious", &"military"]:
			# a passage through the middle, to the square or the yard
			lanes.append([Vector2(cx, r.position.y - 1.5), Vector2(cx, r.end.y + 1.5)])
	# the open ground of the quarter: the market square, the churchyard, the yard of arms
	var yard := Rect2()
	match kind:
		&"market":
			yard = Rect2(Vector2(cx, cy) - Vector2(10.0, 8.0), Vector2(20.0, 16.0))
		&"religious":
			yard = Rect2(Vector2(cx, cy) - Vector2(11.0, 9.0), Vector2(22.0, 17.0))
		&"military":
			yard = Rect2(Vector2(cx, cy) - Vector2(9.0, 7.0), Vector2(18.0, 14.0))
	# the rows along the edges: the top row (fronts on the courtyard), the bottom row (fronts on the street), and
	# from the second level the houses up the sides and a row across the middle
	var slots: Array = []   # feet
	var y_top := r.position.y + 6.8
	var y_bottom := r.end.y - 0.4
	for row_y: float in [y_top, y_bottom]:
		var x := r.position.x + 3.8
		while x <= r.end.x - 3.6:
			slots.append(Vector2(x, row_y))
			x += SLOT_M
	if kind == &"farming":
		slots = slots.filter(func(f: Vector2) -> bool: return f.y < cy)   # only the farmsteads at the head
	else:
		var y := y_top + 7.4
		while y < y_bottom - 6.0:
			slots.append(Vector2(r.position.x + 3.8, y))
			slots.append(Vector2(r.end.x - 3.8, y))
			y += 7.0
		if b.level >= 3 and not yard.has_area():
			var x2 := r.position.x + 11.0
			while x2 <= r.end.x - 11.0:
				slots.append(Vector2(x2, cy + 3.0))
				x2 += SLOT_M
	var k := 0
	for slot: Vector2 in slots:
		k += 1
		var feet := slot + Vector2((_h(b, k, 883) - 0.5) * 1.0, (_h(b, k, 884) - 0.5) * 0.6)
		if absf(feet.x - cx) < 4.2 and (b.level >= 2 or kind in [&"market", &"religious", &"military"]) and kind != &"farming":
			continue   # the passage
		if yard.has_area() and yard.grow(3.0).has_point(feet - Vector2(0.0, 2.5)):
			continue   # the square stays open
		if _h(b, k, 885) > fill:
			continue
		pieces.append([_piece(b, kind, k), feet, PIECE_SCALE * (0.94 + 0.1 * _h(b, k, 886))])
	# the gardens of the courtyard (drawn on the ground): what is left inside, behind the houses
	var gardens: Array[Rect2] = []
	if not yard.has_area() and kind != &"farming":
		var inner := Rect2(r.position + Vector2(8.5, 8.5), fp - Vector2(17.0, 17.0))
		if inner.size.x > 6.0 and inner.size.y > 4.0:
			var half_w := (inner.size.x - 2.0) * 0.5
			gardens.append(Rect2(inner.position, Vector2(half_w, inner.size.y * 0.8)))
			gardens.append(Rect2(inner.position + Vector2(half_w + 2.0, inner.size.y * 0.2), Vector2(half_w, inner.size.y * 0.8)))
	# the landmark of the quarter, in its yard
	match kind:
		&"religious":
			pieces.append(["church", yard.get_center() + Vector2(0.0, 3.0), 1.0])
		&"military":
			pieces.append(["barracks" if _h(b, 3, 887) < 0.5 else "barracks_1", yard.position + Vector2(yard.size.x * 0.5, -0.5), 0.9])
		&"market":
			var stalls := 2 + b.level * 2
			for i in stalls:
				var a := TAU * (float(i) / float(stalls) + _h(b, 40 + i, 888) * 0.05)
				props.append(["stall_%d" % (i % 2), yard.get_center() + Vector2(cos(a) * yard.size.x * 0.36, sin(a) * yard.size.y * 0.34 + 1.0)])
		&"production":
			for i in 2 + b.level:
				props.append([["cart_0", "crates_1", "barrels_1", "logs_0", "sacks_1"][i % 5],
					Vector2(cx - 4.0 + i * 2.4, cy + 1.0 + (i % 2) * 1.6)])
	pieces.sort_custom(func(p: Array, q: Array) -> bool: return (p[1] as Vector2).y < (q[1] as Vector2).y)
	var out := {"lanes": lanes, "pieces": pieces, "props": props, "yard": yard, "gardens": gardens}
	if _cache.size() > 512:
		_cache.clear()
	_cache[key] = out
	return out


## Which building a slot of the quarter shows.
static func _piece(b: BuildingState, kind: StringName, k: int) -> String:
	var roll := _h(b, k, 889)
	var stone := b.level >= 3 and roll < 0.45 or b.level == 2 and roll < 0.18
	match kind:
		&"craft":
			if roll < 0.22:
				return "bakery"
			if roll < 0.40:
				return "smith" if _h(b, k, 890) < 0.5 else "smith_1"
		&"production":
			if roll < 0.55:
				return "storehouse" if _h(b, k, 890) < 0.5 else "storehouse_1"
			if roll < 0.8:
				return "granary" if _h(b, k, 890) < 0.5 else "granary_1"
		&"military":
			if roll < 0.3:
				return "barracks_1"
		&"farming":
			return "farmstead" if roll < 0.5 else "farmstead_1"
	if stone:
		return "house_4"
	return HOUSES[int(_h(b, k, 891) * 4.0) % 4]


## Where the people of a quarter walk on the map: its lanes.
static func lanes(b: BuildingState) -> Array:
	return layout(b)["lanes"]
