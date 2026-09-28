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

