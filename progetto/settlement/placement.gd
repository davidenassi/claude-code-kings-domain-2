class_name Placement
extends RefCounted
## Checks whether a building can stand at a position, with the reason shown to the player when it cannot.
## Standing trees are not a refusal: the builders fell them first (the wood goes to the stores).

const SAMPLE_STEP_M := 4.0
const GAP_M := 1.5
const RIVER_GAP_M := 1.0   ## a building keeps its feet out of the river bank by this much


## {ok: bool, reason: String, trees: int (to fell), rocks: int}
static func check(world: WorldState, settlement: SettlementState, def: BuildingDef, pos: Vector2, ignore_cost: bool = false,
		founding: bool = false) -> Dictionary:
	var wd := WorldData.get_instance()
	var bal: Dictionary = Defs.balance("settlement")
	var out := {"ok": false, "reason": "", "trees": 0, "rocks": 0}
	if def == null or (not def.buildable and not founding):
		out["reason"] = "Questo edificio non si può costruire."
		return out
	if settlement == null:
		out["reason"] = "Nessun insediamento."
		return out
	var rect := Rect2(pos - def.footprint * 0.5, def.footprint)
	# ground: land, own territory, gentle slope
	var hmin := INF
	var hmax := -INF
	var y := rect.position.y
	while y <= rect.end.y + 0.01:
		var x := rect.position.x
		while x <= rect.end.x + 0.01:
			var p := Vector2(minf(x, rect.end.x), minf(y, rect.end.y))
			if not wd.in_world(p) or wd.water_at(p) != WorldData.WATER_LAND:
				out["reason"] = "C'è acqua sotto l'edificio."
				return out
			var owner := world.owner_of(wd.province_at(p))
			if owner == null or owner.id != settlement.kingdom:
				out["reason"] = "Fuori dal territorio del tuo dominio."
				return out
			var h := wd.height_at(p)
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
			x += SAMPLE_STEP_M
		y += SAMPLE_STEP_M
	if touches_river(wd, rect):
		out["reason"] = "Il fiume passa sotto l'edificio."
		return out
	var max_slope := float(bal.get("max_slope_m", 2.5)) * maxf(1.0, def.footprint.length() / 12.0)
	if hmax - hmin > max_slope:
		out["reason"] = "Terreno troppo ripido (dislivello %.1f m)." % (hmax - hmin)
		return out
	# other buildings (roads may run along a building but not under it)
	var grown := rect.grow(GAP_M)
	for b: BuildingState in world.buildings.values():
		var hit := segment_hits_rect(b.a, b.b, rect.grow(BuildingState.road_width() * 0.5 - 0.5)) if b.is_road() else b.rect().intersects(grown)
		if hit:
			out["reason"] = "Lo spazio è occupato da: %s." % b.def().display_name
			return out
	# rock outcrops cannot be built over
	for r in LocalFeatures.outcrops_in_rect(rect.grow(2.0)):
		if world.terrain.rock_charges_left(r) > 0:
			out["reason"] = "Ci sono rocce affioranti: prima vanno cavate."
			return out
	# building-specific requirements
	if def.requires.has("rocks_within_m"):
		var radius := float(def.requires["rocks_within_m"])
		var deposit := StringName(def.requires.get("deposit", "stone"))
		var found := 0
		for r in LocalFeatures.outcrops_in_rect(Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0)):
			if r["deposit"] == deposit and r["pos"].distance_to(pos) <= radius and world.terrain.rock_charges_left(r) > 0:
				found += 1
		out["rocks"] = found
		if found == 0:
			var what := "vene di ferro" if deposit == &"iron" else "rocce affioranti"
			out["reason"] = "Nessuna di queste %s entro %d m." % [what, int(radius)]
			return out
	if def.work_type() == &"farm":
		var bd: BiomeDef = Defs.biome_by_index(wd.biome_at(pos))
		var fert := bd.fertility if bd else 0.0
		if fert < float(def.work.get("min_fertility", 0.2)):
			out["reason"] = "Terra poco fertile per i campi."
			return out
	# materials: stock minus what other sites still need
	if not ignore_cost:
		var short := PackedStringArray()
		var pending := committed_materials(world, settlement.id)
		for res: StringName in def.cost.keys():
			var free := settlement.amount(res) - int(pending.get(res, 0))
			if free < int(def.cost[res]):
				var rd := Defs.resource(res)
				short.append("%s %d" % [rd.display_name.to_lower() if rd else String(res), int(def.cost[res]) - free])
		if not short.is_empty():
			out["reason"] = "Mancano materiali: %s." % ", ".join(short)
			return out
	var trees := 0
	for t in LocalFeatures.trees_in_rect(wd, rect):
		if not world.terrain.is_felled(t["key"]):
			trees += 1
	out["trees"] = trees
	out["ok"] = true
	return out


const ROAD_MIN_M := 4.0
const ROAD_MAX_M := 160.0


static func segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var n := maxi(int(ceil(a.distance_to(b) / 1.5)), 1)
	for i in n + 1:
		if r.has_point(a.lerp(b, float(i) / float(n))):
			return true
	return false


## Checks a road segment from a to b. Same result shape as check().
## True when the drawn river (water and bank) touches the rectangle: its edges every two metres, its inside
## every four. Far from any river it costs one lookup.
static func touches_river(wd: WorldData, rect: Rect2) -> bool:
	var centre := rect.get_center()
	if wd.river_clearance(centre) > rect.size.length() * 0.5 + RIVER_GAP_M:
		return false
	var step := 2.0
	var x := rect.position.x
	while x <= rect.end.x + 0.01:
		for y in [rect.position.y, rect.end.y]:
			if wd.river_clearance(Vector2(minf(x, rect.end.x), y)) < RIVER_GAP_M:
				return true
		x += step
	var y := rect.position.y
	while y <= rect.end.y + 0.01:
		for x2 in [rect.position.x, rect.end.x]:
			if wd.river_clearance(Vector2(x2, minf(y, rect.end.y))) < RIVER_GAP_M:
				return true
		y += step
	y = rect.position.y + SAMPLE_STEP_M
	while y < rect.end.y:
		x = rect.position.x + SAMPLE_STEP_M
		while x < rect.end.x:
			if wd.river_clearance(Vector2(x, y)) < RIVER_GAP_M:
				return true
			x += SAMPLE_STEP_M
		y += SAMPLE_STEP_M
	return false


static func check_road(world: WorldState, settlement: SettlementState, a: Vector2, b: Vector2) -> Dictionary:
	var wd := WorldData.get_instance()
	var out := {"ok": false, "reason": "", "trees": 0, "rocks": 0}
	if settlement == null:
		out["reason"] = "Nessun insediamento."
		return out
	var length := a.distance_to(b)
	if length < ROAD_MIN_M:
		out["reason"] = "Trascina la strada fino al punto di arrivo."
		return out
	if length > ROAD_MAX_M:
		out["reason"] = "Tratto troppo lungo (%d m, massimo %d): costruiscila a tappe." % [int(length), int(ROAD_MAX_M)]
		return out
	var n := int(ceil(length / 2.0))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		if not wd.in_world(p) or wd.water_at(p) != WorldData.WATER_LAND \
				or wd.river_clearance(p) < BuildingState.road_width() * 0.5:
			out["reason"] = "La strada attraversa l'acqua: servono ponti (fase successiva)."
			return out
		var owner := world.owner_of(wd.province_at(p))
		if owner == null or owner.id != settlement.kingdom:
			out["reason"] = "Fuori dal territorio del tuo dominio."
			return out
	var half := BuildingState.road_width() * 0.5
	for other: BuildingState in world.buildings.values():
		if other.is_road():
			continue
		if segment_hits_rect(a, b, other.rect().grow(half - 0.5)):
			out["reason"] = "La strada passerebbe sopra: %s." % other.def().display_name
			return out
	var bounds := Rect2(a, Vector2.ZERO).expand(b).grow(half + 1.0)
	for r in LocalFeatures.outcrops_in_rect(bounds):
		if world.terrain.rock_charges_left(r) > 0 and Geometry2D.get_closest_point_to_segment(r["pos"], a, b).distance_to(r["pos"]) <= half + 1.0:
			out["reason"] = "Ci sono rocce affioranti sul tracciato."
			return out
	var trees := 0
	for t in LocalFeatures.trees_in_rect(wd, bounds):
		if not world.terrain.is_felled(t["key"]) and Geometry2D.get_closest_point_to_segment(t["pos"], a, b).distance_to(t["pos"]) <= half + 1.0:
			trees += 1
	out["trees"] = trees
	out["ok"] = true
	return out


## Materials still owed to the construction sites of a settlement (resource -> amount).
static func committed_materials(world: WorldState, settlement_id: int) -> Dictionary:
	var out := {}
	for b: BuildingState in world.buildings.values():
		if b.settlement != settlement_id or b.is_active():
			continue
		var miss := b.missing_materials()
		for res: StringName in miss.keys():
			out[res] = int(out.get(res, 0)) + int(miss[res])
	# goods already in someone's hands for a site are out of the stock but still owed: do not count them twice
	for p: PersonState in world.people.values():
		if p.settlement == settlement_id and not p.carrying.is_empty() and int(p.carrying.get("for_site", -1)) >= 0:
			var res: StringName = p.carrying["res"]
			out[res] = maxi(int(out.get(res, 0)) - int(p.carrying["amount"]), 0)
	return out

