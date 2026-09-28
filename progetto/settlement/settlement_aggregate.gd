class_name SettlementAggregate
extends RefCounted
## Same economy, cheaper: while nobody is watching a settlement, its day is resolved in closed form instead of
## following every inhabitant hour by hour. The people are still individuals (names, ages, jobs, hunger) and the
## world still changes physically: the trees the woodcutters cut really fall, the rocks really run out, the
## construction sites really grow. When the camera comes close the detailed simulation takes over again.

const TRAVEL_OVERHEAD := 0.78   # share of the working day left after walking, loading and resting


static func work_hours(session: GameSession) -> float:
	var bal := SettlementSim.bal()
	return (float(bal.get("work_end_hour", 19)) - float(bal.get("work_start_hour", 6))) * TRAVEL_OVERHEAD


static func day(session: GameSession, s: SettlementState) -> void:
	var world := session.world
	var hours := work_hours(session)
	var workers := {}      # building id -> [people]
	var builders: Array[PersonState] = []
	for p in world.people_of(s.id):
		if p.job == &"builder":
			builders.append(p)
		elif p.workplace >= 0:
			var list: Array = workers.get(p.workplace, [])
			list.append(p)
			workers[p.workplace] = list
	for b in world.buildings_of(s.id):
		if b.is_active():
			_produce(session, s, b, workers.get(b.id, []), hours)
	_build(session, s, builders, hours)


static func _effort(people: Array, hours: float) -> float:
	var total := 0.0
	for p: PersonState in people:
		total += hours * SettlementSim.efficiency(p)
	return total


static func _produce(session: GameSession, s: SettlementState, b: BuildingState, people: Array, hours: float) -> void:
	if people.is_empty() or b.def().work.is_empty():
		return
	var world := session.world
	var work: Dictionary = b.def().work
	var effort := _effort(people, hours)
	match b.def().work_type():
		&"fell_trees":
			var per_tree := float(work.get("hours", 3.0))
			var n := int(floor((effort + b.crop) / per_tree))   # crop holds the leftover effort between days
			b.crop = fposmod(effort + b.crop, per_tree)
			_fell(session, s, b, n, work.get("yield", {"wood": 3}))
		&"quarry_rock":
			var per_rock := float(work.get("hours", 4.0))
			var n := int(floor((effort + b.crop) / per_rock))
			b.crop = fposmod(effort + b.crop, per_rock)
			_quarry(session, s, b, n, work.get("yield", {"stone": 2}))
		&"farm":
			var month := int(session.calendar.date_of(world.day)["month"])
			var sow := int(work.get("sow_month", 3))
			var harvest := int(work.get("harvest_month", 8))
			if month >= sow and month < harvest:
				var bd: BiomeDef = Defs.biome_by_index(SettlementSim.ground(world).biome_at(b.pos))
				var season := SettlementSim.season_agriculture(session, world.day)
				var grown := effort * float(work.get("grain_per_work_hour", 0.05)) * (bd.fertility if bd else 0.5) * season
				b.crop += KingdomModifiers.settlement_value(session, s, &"production.grain", grown, SettlementSim.field_keys(world, b.pos))
			elif month >= harvest and b.crop >= 1.0:
				var moved := mini(int(floor(b.crop)), s.space_for(world, &"grain"))
				if moved > 0:
					b.crop -= moved
					s.add(&"grain", moved, &"work")
					KingdomModifiers.record(world, s.kingdom, &"grain", float(moved))
		&"convert":
			var cycles := int(floor(effort / maxf(float(work.get("hours", 8.0)), 0.1)))
			for i in cycles:
				var input: Dictionary = work.get("input", {})
				var ok := true
				for res: String in input.keys():
					if s.amount(StringName(res)) < int(input[res]):
						ok = false
				var output: Dictionary = work.get("output", {})
				for res: String in output.keys():
					if s.space_for(world, StringName(res)) < int(output[res]):
						ok = false
				if not ok:
					break
				for res: String in input.keys():
					s.take(StringName(res), int(input[res]), &"work")
				for res: String in output.keys():
					SettlementSim.produce(session, s, StringName(res), float(output[res]))
	EventBus.settlement_changed.emit(s.id)


static func _fell(session: GameSession, s: SettlementState, b: BuildingState, count: int, yield_d: Dictionary) -> void:
	var world := session.world
	if count <= 0:
		return
	var felled := 0
	var candidates := SettlementSim.candidate_trees(session, b)
	var keep_from := 0
	for i in candidates.size():
		if felled >= count:
			break
		var tree: Dictionary = candidates[i]
		if world.terrain.is_felled(tree["key"]):
			if i == keep_from:
				keep_from += 1
			continue
		world.terrain.fell(tree, world.day)
		if i == keep_from:
			keep_from += 1
		felled += 1
		for res: String in yield_d.keys():
			SettlementSim.produce(session, s, StringName(res), float(yield_d[res]))
	if keep_from > 0:
		var cache: Dictionary = session.runtime.get(SettlementSim.TREE_CACHE_KEY, {})
		cache[b.id] = candidates.slice(keep_from)
		session.runtime[SettlementSim.TREE_CACHE_KEY] = cache


static func _quarry(session: GameSession, s: SettlementState, b: BuildingState, count: int, yield_d: Dictionary) -> void:
	var world := session.world
	if count <= 0:
		return
	var deposit := StringName(b.def().work.get("deposit", "stone"))
	var radius := float(b.def().work.get("radius_m", 90.0))
	var done := 0
	for rock in LocalFeatures.outcrops_in_rect(SettlementSim.ground(world), Rect2(b.pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0)):
		if done >= count:
			break
		if rock["deposit"] != deposit or rock["pos"].distance_to(b.pos) > radius:
			continue
		while done < count and world.terrain.rock_charges_left(rock) > 0:
			world.terrain.use_rock_charge(rock)
			done += 1
			for res: String in yield_d.keys():
				SettlementSim.produce(session, s, StringName(res), float(yield_d[res]))


static func _build(session: GameSession, s: SettlementState, builders: Array[PersonState], hours: float) -> void:
	var world := session.world
	var sites: Array[BuildingState] = []
	for b in world.buildings_of(s.id):
		if not b.is_active():
			sites.append(b)
	if sites.is_empty() or builders.is_empty():
		return
	var effort := _effort(builders, hours) / float(sites.size())
	for site in sites:
		var left := effort
		# clear the ground first (once the last tree is down the ground stays clear: buildings keep it so)
		if not site.ground_cleared:
			var chop := float(Defs.building(&"woodcutter").work.get("hours", 3.0))
			var standing := 0
			for tree in site.trees_on_ground(SettlementSim.ground(world)):
				if world.terrain.is_felled(tree["key"]):
					continue
				standing += 1
				if left < chop:
					break
				world.terrain.fell(tree, world.day)
				standing -= 1
				left -= chop
				SettlementSim.produce(session, s, &"wood", float(SettlementSim.bal().get("tree_wood", 3)))
			site.ground_cleared = standing == 0
		# then the materials arrive and the work goes on
		var missing := site.missing_materials()
		for res: StringName in missing.keys():
			var got := s.take(res, int(missing[res]), &"build")
			if got > 0:
				site.delivered[res] = int(site.delivered.get(res, 0)) + got
		if site.missing_materials().is_empty():
			site.work_done += KingdomModifiers.settlement_value(session, s, &"construction.speed", left)
		SettlementSim.try_finish_site(session, s, site)

