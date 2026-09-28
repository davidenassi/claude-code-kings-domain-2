class_name SettlementSetup
extends RefCounted
## Founds the player's first settlement in the start valley. Since Phase 15 there is no keep and no king: six people
## — three men and three women, each from a family of their own — arrive with a common fire that holds their
## stores, a lean-to to sleep under and little else. Everything else they will build. The site is chosen from the
## real ground (flat, near water but dry, near stone, lightly wooded).

const SEARCH_STEP_M := 64.0
const REFINE_STEP_M := 16.0


static func found_player_settlement(world: WorldState) -> SettlementState:
	var player := world.player()
	if player == null:
		return null
	var wd := WorldData.get_instance()
	var bal: Dictionary = Defs.balance("settlement")
	var site := choose_site(world, player.capital)
	var s := SettlementState.new()
	s.id = world.settlements.size()
	s.name = wd.province_geo(player.capital).name
	s.kingdom = player.id
	s.province = player.capital
	s.center = site
	s.builder_quota = StringName(bal.get("default_builder_quota", "many"))
	for res: String in (bal.get("start_stock", {}) as Dictionary).keys():
		var rd := Defs.resource(StringName(res))
		if rd and not rd.uses_storage:
			player.treasury += float(bal["start_stock"][res])   # gold is the common purse, not a good in store
		else:
			s.stock[StringName(res)] = int(bal["start_stock"][res])
	world.settlements.append(s)
	player.founded_day = world.day

	# the ground the first settlers cleared: stumps around, bare ground under the fire and the lean-to
	var store := _add_building(world, s, &"camp_store", site)
	var shelter := _add_building(world, s, &"shelter", site + Vector2(14.0, 8.0))
	var radius := float(bal.get("site_clear_radius_m", 26.0))
	var clear_rect := Rect2(site - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	for t in LocalFeatures.trees_in_rect(wd, clear_rect.grow(12.0)):
		var in_building := store.rect().grow(1.0).has_point(t["pos"]) or shelter.rect().grow(1.0).has_point(t["pos"])
		if in_building:
			world.terrain.fell(t, -30, true)
		elif t["pos"].distance_to(site) <= radius:
			world.terrain.fell(t, -30 - int(KDRng.hash01(t["gx"], t["gy"], 5) * 40.0))

	var founders := _add_founders(world, s, shelter, player)
	var names := PackedStringArray()
	for p in founders:
		names.append(full_name(world, p))
	world.chronicle.append({"day": world.day, "kingdom": player.id, "kind": "founding_arrival",
		"text": "Sei persone arrivano a %s: %s. Non c'è un re, non c'è un castello: c'è la terra." % [
			s.name, ", ".join(names)]})
	return s


## "Aldo Valeri": the name and the surname of the family the person belongs to.
static func full_name(world: WorldState, p: PersonState) -> String:
	var f := world.family(p.family)
	return p.name if f == null or f.name == "" else "%s %s" % [p.name, f.name]


static func _add_building(world: WorldState, s: SettlementState, def_id: StringName, pos: Vector2) -> BuildingState:
	var b := BuildingState.new()
	b.id = world.new_id()
	b.def_id = def_id
	b.settlement = s.id
	b.pos = pos
	b.status = BuildingState.Status.ACTIVE
	b.workers_wanted = b.def().workers
	world.buildings[b.id] = b
	world.buildings_changed()
	return b


## Three men and three women, each from a family of their own: the couples come later (FamilySystem), and the
## chronicle writes down every one of them.
static func _add_founders(world: WorldState, s: SettlementState, shelter: BuildingState, realm: KingdomState) -> Array[PersonState]:
	var fam: Dictionary = Defs.balance("families").get("start", {})
	var names: Dictionary = (Defs.read_json("res://data/defs/person_names.json") as Dictionary)["cultures"]
	var pool: Dictionary = names.get(String(realm.culture), names["latin"])
	var surnames: Array = pool.get("surnames", names["latin"].get("surnames", ["Nuovi"]))
	var rng := world.rng.stream(&"people")
	var used_names := {}
	var used_surnames := {}
	var out: Array[PersonState] = []
	var ages: Array = fam.get("age", [18, 30])
	var sexes: Array[bool] = []
	for i in int(fam.get("men", 3)):
		sexes.append(false)
	for i in int(fam.get("women", 3)):
		sexes.append(true)
	for female in sexes:
		var p := PersonState.new()
		p.id = world.new_id()
		p.female = female
		var list: Array = pool["female" if female else "male"]
		var nm := String(list[rng.randi_range(0, list.size() - 1)])
		while used_names.has(nm):
			nm = String(list[rng.randi_range(0, list.size() - 1)])
		used_names[nm] = true
		p.name = nm
		var surname := String(surnames[rng.randi_range(0, surnames.size() - 1)])
		while used_surnames.has(surname) and used_surnames.size() < surnames.size():
			surname = String(surnames[rng.randi_range(0, surnames.size() - 1)])
		used_surnames[surname] = true
		var age := rng.randi_range(int(ages[0]), int(ages[1]))
		p.birth_day = world.day - age * PersonState.DAYS_PER_YEAR - rng.randi_range(0, PersonState.DAYS_PER_YEAR - 1)
		p.culture = realm.culture
		p.religion = realm.religion
		p.settlement = s.id
		p.home = shelter.id
		p.job = &"idle"
		var f := FamilyState.new()
		f.id = world.new_id()
		f.name = surname
		f.settlement = s.id
		f.founded_day = world.day
		f.founding = true
		f.founders.append(p.id)
		world.families[f.id] = f
		p.family = f.id
		p.born_family = f.id
		var spot := shelter.pos + Vector2(rng.randf_range(-4.0, 4.0), shelter.def().footprint.y * 0.5 + rng.randf_range(1.0, 3.0))
		p.seg_from = spot
		p.seg_to = spot
		world.add_person(p)
		out.append(p)
	return out


## Best spot for the first fire inside a province: dry flat ground, water within reach, stone nearby, few trees.
static func choose_site(world: WorldState, province_id: int) -> Vector2:
	var wd := WorldData.get_instance()
	var g := wd.province_geo(province_id)
	var reach := maxf(g.inner_radius_m * 2.5, 2500.0)
	var best := g.center
	var best_score := -INF
	var stones: Array[Vector2] = []
	for dep in g.deposits:
		if dep["type"] == &"stone":
			stones.append(dep["pos"])
	var top: Array = []   # the best few of the coarse search: [score, point]
	var y := g.center.y - reach
	while y <= g.center.y + reach:
		var x := g.center.x - reach
		while x <= g.center.x + reach:
			var p := Vector2(x, y)
			x += SEARCH_STEP_M
			if wd.province_at(p) != province_id or wd.water_at(p) != WorldData.WATER_LAND:
				continue
			var score := _site_score(wd, world, province_id, p, stones)
			if score > best_score:
				best_score = score
				best = p
			if score > -INF:
				top.append([score, p])
		y += SEARCH_STEP_M
	# then a closer look around the best few: a 64 m grid missed the spot between the rock and the river
	# (Phase 17 check: kept back from the river bank, the fire fell back to a place with no stone in reach)
	top.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for entry: Array in top.slice(0, 3):
		var around: Vector2 = entry[1]
		for dy in range(-int(SEARCH_STEP_M * 1.5), int(SEARCH_STEP_M * 1.5) + 1, int(REFINE_STEP_M)):
			for dx in range(-int(SEARCH_STEP_M * 1.5), int(SEARCH_STEP_M * 1.5) + 1, int(REFINE_STEP_M)):
				var p := around + Vector2(dx, dy)
				if wd.province_at(p) != province_id or wd.water_at(p) != WorldData.WATER_LAND:
					continue
				var score := _site_score(wd, world, province_id, p, stones)
				if score > best_score:
					best_score = score
					best = p
	return best.snapped(Vector2.ONE)


static func _site_score(wd: WorldData, world: WorldState, province_id: int, p: Vector2, stones: Array[Vector2]) -> float:
	# the keep and the shelter must fit on dry, own, gentle ground
	var h0 := wd.height_at(p)
	var slope := 0.0
	for o: Vector2 in [Vector2(-24, -20), Vector2(28, -20), Vector2(-24, 22), Vector2(28, 22), Vector2(0, 0)]:
		var q := p + o
		if wd.province_at(q) != province_id or wd.water_at(q) != WorldData.WATER_LAND:
			return -INF
		slope = maxf(slope, absf(wd.height_at(q) - h0))
	if wd.river_clearance(p) < 40.0:
		return -INF   # the fire and the shelter stand back from the river bank (Phase 17 check)
	var score := -slope * 1.5
	score -= wd.canopy_smooth(p) * 3.0
	# water close but not too close
	var water_d := INF
	for r: float in [60.0, 120.0, 200.0, 320.0]:
		for k in 12:
			var q := p + Vector2.from_angle(TAU * k / 12.0) * r
			if wd.in_world(q) and wd.water_at(q) != WorldData.WATER_LAND:
				water_d = r
				break
		if water_d < INF:
			break
	score += 2.0 if water_d <= 200.0 else (0.8 if water_d <= 320.0 else 0.0)
	for s in stones:
		# stone the founders can reach on foot (Phase 15: rocks belong to the start): a quarry must fit within
		# a short walk, so the weight falls fast after a few hundred metres
		score += clampf(1.0 - s.distance_to(p) / 450.0, 0.0, 1.0) * 3.5
	var bd: BiomeDef = Defs.biome_by_index(wd.biome_at(p))
	score += (bd.fertility if bd else 0.0) * 1.0
	score -= p.distance_to(wd.province_geo(province_id).center) / 3000.0
	return score

