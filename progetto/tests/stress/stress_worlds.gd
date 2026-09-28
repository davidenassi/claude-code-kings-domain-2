class_name StressWorlds
extends RefCounted
## Phase 19: worlds pushed past what a campaign normally reaches, made on purpose to be measured
## (tests/stress/stress_runner.gd, headless) and looked at (main.gd --kd-scenario=stress_city / stress_war).
## Dev tooling, not part of the game: everything here is made through the game's own functions — the planner
## finds the spots, PopulationSystem welcomes the people, Military raises the hosts, Diplomacy signs and
## declares — so what is measured is what a very large campaign would really cost.

## What a large town is made of, for every hundred inhabitants: 25 houses (100 beds), the fields, woods and
## oven that feed and warm them, a well, a granary and a storehouse.
const CITY_MIX := [[&"house", 25], [&"farm", 3], [&"woodcutter", 2], [&"bakery", 1], [&"well", 1],
	[&"granary", 1], [&"storehouse", 1]]
## And for every three hundred: the trades of a town.
const CITY_MIX_300 := [[&"smith", 1], [&"barracks", 1], [&"quarry", 1]]


## The player's settlement grown to about `people` inhabitants: the buildings of a town of that size, placed by
## the planner around the keep and finished, then the people, with granaries full for a while.
## Returns what it cost: {buildings, failed, place_ms, welcome_ms, welcome_last_batch_ms, people}.
static func grow_city(session: GameSession, people: int) -> Dictionary:
	var world := session.world
	var s := world.settlements[0]
	var out := {}
	# materials for every site: the planner only places what the stores can pay
	s.add(&"wood", 1000000, &"other")
	s.add(&"stone", 1000000, &"other")
	var queue: Array[StringName] = []
	var hundreds := maxi(ceili(float(people) / 100.0), 1)
	for h in hundreds:
		for entry: Array in CITY_MIX:
			for i in int(entry[1]):
				queue.append(entry[0])
		if h % 3 == 2:
			for entry: Array in CITY_MIX_300:
				queue.append(entry[0])
	var t0 := Time.get_ticks_usec()
	var placed := 0
	var failed := 0
	# each kind searches from a little inside where it last found room: the inner rings are full
	var from_r := {}
	for def_id in queue:
		var min_r := maxf(float(from_r.get(def_id, 20.0)) - 24.0, 20.0)
		var spot := SettlementPlanner.find_spot(session, s.id, def_id, s.center, min_r, false, 2400.0)
		if spot == Vector2.INF:
			failed += 1
			continue
		from_r[def_id] = spot.distance_to(s.center)
		SettlementSetup._add_building(world, s, def_id, spot)
		placed += 1
	out["place_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	out["buildings"] = placed
	out["failed"] = failed
	# the people, in the batches in which a town receives them
	t0 = Time.get_ticks_usec()
	var last_batch := 0.0
	while world.people_of(s.id).size() < people:
		var tb := Time.get_ticks_usec()
		PopulationSystem.welcome(session, s, mini(people - world.people_of(s.id).size(), 25), world.day, "stress")
		last_batch = (Time.get_ticks_usec() - tb) / 1000.0
	out["welcome_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	out["welcome_last_batch_ms"] = last_batch
	out["people"] = world.people_of(s.id).size()
	# the stores back to what they hold, the granaries full
	for res: StringName in [&"wood", &"stone"]:
		s.take(res, maxi(s.amount(res) - s.capacity(world, &"material") / 3, 0), &"other")
	s.add(&"grain", s.space_for(world, &"grain") / 2, &"other")
	s.add(&"bread", s.space_for(world, &"bread"), &"other")
	# and a year of bread beyond what the granaries hold: a town put down in a day has not had its harvests, and
	# without this it starves in a month — what is measured must be a town that lives (Phase 19: the first stress
	# city fell from a thousand to five in a year, of hunger)
	s.add(&"bread", people * 100, &"other")
	SettlementSim.mark_assignment_dirty(session, s.id)
	return out


## Many sites open at once in the player's settlement (houses around the edge): the builders' work, the
## deliveries and the planner under load. Returns how many were opened.
static func open_sites(session: GameSession, count: int) -> int:
	var world := session.world
	var s := world.settlements[0]
	s.add(&"wood", 14 * count, &"other")
	var opened := 0
	var min_r := 20.0
	for i in count:
		var spot := SettlementPlanner.find_spot(session, s.id, &"house", s.center, min_r, false, 2400.0)
		if spot == Vector2.INF:
			break
		min_r = maxf(spot.distance_to(s.center) - 24.0, 20.0)
		if session.submit(PlaceBuildingCommand.create(s.id, &"house", spot)).success:
			opened += 1
	return opened


## Every realm raises `per_realm` regiments in its own provinces and declares war on the two realms nearest to it
## (at the start the realms are islands in free land: hardly any of them border another), and two of them on the
## player. The wars go through DeclareWarCommand, with its rules and the allies it calls in. Returns
## {armies, wars, refused: {reason: count}}.
static func raise_wars(session: GameSession, per_realm: int) -> Dictionary:
	var world := session.world
	var wd := WorldData.get_instance()
	var units: Array[StringName] = [&"lancieri", &"alabardieri", &"balestrieri", &"cavalieri"]
	var realms: Array[KingdomState] = []
	for k in world.kingdoms:
		if k.alive and not k.provinces.is_empty():
			realms.append(k)
		if not k.alive or k.provinces.is_empty() or k.id == world.player_kingdom:
			continue
		k.treasury += 400.0 * per_realm
		for i in per_realm:
			var pid: int = k.provinces[i % k.provinces.size()]
			Military.raise_from_province(session, k, pid, Military.unit(units[(k.id + i) % units.size()]))
	var wars := 0
	var refused := {}
	var against_player := 0
	for k in realms:
		if k.id == world.player_kingdom:
			continue
		var here := wd.province_geo(k.capital).center
		var others := realms.filter(func(o: KingdomState) -> bool: return o.id != k.id)
		others.sort_custom(func(a: KingdomState, b: KingdomState) -> bool:
			return wd.province_geo(a.capital).center.distance_squared_to(here) < wd.province_geo(b.capital).center.distance_squared_to(here))
		for o: KingdomState in others.slice(0, 2):
			if o.id == world.player_kingdom:
				if against_player >= 2:
					continue
				against_player += 1
			if Diplomacy.at_war(world, k.id, o.id):
				continue
			var res := session.submit(DeclareWarCommand.create(k.id, o.id, "stress"))
			if res.success:
				wars += 1
			else:
				refused[res.reason] = int(refused.get(res.reason, 0)) + 1
	return {"armies": world.armies.size(), "wars": wars, "refused": refused}


## A web of pacts among all the realms, each signed only where the game's own rules allow it.
## Returns {pact_id: count}.
static func weave_pacts(session: GameSession) -> Dictionary:
	var world := session.world
	var out := {}
	for pact_id: StringName in [&"non_aggression", &"trade", &"alliance", &"tribute", &"vassalage"]:
		var chance: float = {&"non_aggression": 0.6, &"trade": 0.5, &"alliance": 0.5, &"tribute": 0.1, &"vassalage": 0.08}[pact_id]
		for a in world.kingdoms:
			for b in world.kingdoms:
				if a.id == b.id or not a.alive or not b.alive:
					continue
				if pact_id != &"tribute" and pact_id != &"vassalage" and a.id > b.id:
					continue   # the symmetric pacts once per pair
				if KDRng.hash01(a.id * 31 + b.id, pact_id.hash() & 0xffff, 1911) >= chance:
					continue
				if Diplomacy.pact_blocker(world, a, b, pact_id) != "":
					continue
				Diplomacy.sign(world, a.id, b.id, pact_id)
				out[pact_id] = int(out.get(pact_id, 0)) + 1
	return out



## Rebirth, Phase 5: the player's settlement grown to about `people` inhabitants BY QUARTERS, as a town of the
## Rebirth grows: the starter village, then, as the grades of the town allow them, quarters of houses for the
## people, craftsmen, a market, a church, warehouses, soldiers and farming hamlets for the bread, each placed by the
## same choice of the spot as the player's (Siting) and grown to the level the town allows. Returns
## {"districts", "buildings", "people", "ms"}.
const DISTRICT_MIX := [[&"district_farming", 380], [&"district_craft", 900], [&"district_production", 1300],
	[&"district_market", 1600], [&"district_religious", 2200], [&"district_military", 3200]]


static func grow_district_city(session: GameSession, people: int) -> Dictionary:
	var world := session.world
	var s := world.settlements[0]
	var t0 := Time.get_ticks_usec()
	s.add(&"wood", 5000000, &"other")
	s.add(&"stone", 5000000, &"other")
	SettlementPlanner.place_starter_village(session, s.id)
	for b in world.buildings_of(s.id):
		if not b.is_active():
			b.status = BuildingState.Status.ACTIVE
	world.buildings_changed()
	var counts := {}
	var districts := 0
	var guard := 0
	while world.people_of(s.id).size() < people and guard < 400:
		guard += 1
		var now := world.people_of(s.id).size()
		# the next people arrive; when their beds run out quarters of houses are opened (nobody left in the square)
		var batch := mini(people - now, 40 if now < 100 else 120)
		var tries := 0
		while PopulationSystem.free_beds(world, s) < batch and SettlementState.tier(now)["index"] >= 2 and tries < 4:
			tries += 1
			if _open_district(session, s, &"district_residential"):
				districts += 1
			_grow_districts(session, s)
		for entry: Array in DISTRICT_MIX:
			var id: StringName = entry[0]
			var want := now / int(entry[1])
			if int(counts.get(id, 0)) < want and _open_district(session, s, id):
				counts[id] = int(counts.get(id, 0)) + 1
				districts += 1
		if SettlementState.tier(now)["index"] < 2:
			# the village before its quarters: houses (the lord's own choice of the spot)
			while PopulationSystem.free_beds(world, s) < batch:
				var spot := SettlementPlanner.site_for(session, s, &"house")
				if spot == Vector2.INF:
					break
				SettlementSetup._add_building(world, s, &"house", spot)
		PopulationSystem.welcome(session, s, batch, world.day, "stress")
		_grow_districts(session, s)
	s.take(&"wood", maxi(s.amount(&"wood") - s.capacity(world, &"material") / 3, 0), &"other")
	s.take(&"stone", maxi(s.amount(&"stone") - s.capacity(world, &"material") / 3, 0), &"other")
	s.add(&"grain", s.space_for(world, &"grain") / 2, &"other")
	s.add(&"bread", s.space_for(world, &"bread"), &"other")
	s.add(&"bread", people * 100, &"other")
	SettlementSim.mark_assignment_dirty(session, s.id)
	return {"districts": districts, "buildings": world.buildings_of(s.id).size(), "people": world.people_of(s.id).size(),
		"ms": (Time.get_ticks_usec() - t0) / 1000.0}


static func _open_district(session: GameSession, s: SettlementState, id: StringName) -> bool:
	var world := session.world
	if Placement.tier_lock(world, s, Defs.building(id)) != "":
		return false
	var spot := SettlementPlanner.site_for(session, s, id)
	if spot == Vector2.INF:
		return false
	var b := SettlementSetup._add_building(world, s, id, spot)
	for t in b.trees_on_ground(SettlementSim.ground(world)):
		world.terrain.fell(t, world.day, true)
	return true


## Every quarter at the level its town allows (as if the years had passed): full or not.
static func _grow_districts(session: GameSession, s: SettlementState) -> void:
	var world := session.world
	var tier_now := int(SettlementState.tier(world.people_of(s.id).size())["index"])
	for b in world.buildings_of(s.id):
		if not b.is_active() or not b.is_district():
			continue
		var tiers: Array = b.def().district.get("tier_for_level", [])
		var level := 1
		for l in range(2, b.def().max_level() + 1):
			var need := StringName(tiers[l - 1]) if l - 1 < tiers.size() else &""
			if need == &"" or tier_now >= SettlementState.tier_index(need):
				level = l
		if level != b.level:
			b.level = level
			b.workers_wanted = b.workers()
			world.buildings_changed()
