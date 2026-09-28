class_name Military
extends RefCounted
## The rules of the host: how fast it marches, which way it goes, what it eats, how strong it looks and
## how far it sees. Data in data/defs/units.json and balance/military.json; the state is in ArmyState.


static var _units_data: Dictionary = {}


static func bal() -> Dictionary:
	return Defs.balance("military")


## The extra rules in units.json that are not a unit (the captain's part).
static func captain_rules() -> Dictionary:
	if _units_data.is_empty():
		var d: Variant = Defs.read_json("res://data/defs/units.json")
		_units_data = d if d is Dictionary else {}
	return _units_data.get("captain", {})


static func unit(unit_id: StringName) -> UnitDef:
	return Defs.get_def("units", unit_id) as UnitDef


static func units() -> Array[UnitDef]:
	var out: Array[UnitDef] = []
	for u: UnitDef in Defs.all("units"):
		out.append(u)
	return out


# --- what an army is worth ---------------------------------------------------------------------------------

## Rough fighting weight, used by the AI, by the diplomacy and (from Phase 10) by the battle.
static func strength(army: ArmyState) -> float:
	var total := 0.0
	for r in army.regiments:
		var u := unit(r["unit"])
		if u == null:
			continue
		total += float(int(r["men"])) * (u.attack + u.defense) * 0.5 * (0.5 + float(r["morale"]) / 100.0)
	return total / 10.0


static func kingdom_strength(world: WorldState, kingdom_id: int) -> float:
	var total := 0.0
	for a in world.armies:
		if a.kingdom == kingdom_id:
			total += strength(a)
	return total


## Gold the crown owes its soldiers every day.
static func upkeep_per_day(army: ArmyState) -> float:
	var total := 0.0
	for r in army.regiments:
		var u := unit(r["unit"])
		if u:
			total += u.upkeep_gold_day * float(int(r["men"])) / maxf(float(u.men), 1.0)
	return total


## Rations eaten every day (in units of food).
static func food_per_day(army: ArmyState) -> float:
	var total := 0.0
	for r in army.regiments:
		var u := unit(r["unit"])
		if u:
			total += float(u.food_day) * float(int(r["men"])) / maxf(float(u.men), 1.0)
	return total


# --- marching ----------------------------------------------------------------------------------------------

## Kilometres the army can cover in a day, at the pace of its slowest regiment and the ground under it.
static func day_march_km(world: WorldState, army: ArmyState) -> float:
	var cfg: Dictionary = bal().get("march", {})
	var slowest := 99.0
	for r in army.regiments:
		var u := unit(r["unit"])
		if u:
			slowest = minf(slowest, u.speed_kmh)
	if slowest > 50.0:
		return 0.0
	var g := WorldData.get_instance().province_geo(army.province)
	var ground := float((cfg.get("terrain_speed", {}) as Dictionary).get(String(g.terrain) if g else "plains", 1.0))
	var commander := world.character(army.commander)
	var boost := 1.0
	if commander:
		boost += (commander.skill(&"guerra") - 5) * float(captain_rules().get("speed_per_skill", 0.02))
	var tired := clampf(army.morale() / 60.0, 0.5, 1.0)
	return slowest * float(cfg.get("hours_per_day", 9.0)) * ground * boost * tired


## The cheapest chain of provinces from `from_province` to `to_province` (Dijkstra on the province graph:
## distance in kilometres, divided by how fast the ground lets an army move, plus the price of rivers and passes).
static func route(world: WorldState, from_province: int, to_province: int) -> PackedInt32Array:
	var wd := WorldData.get_instance()
	var cfg: Dictionary = bal().get("march", {})
	var speeds: Dictionary = cfg.get("terrain_speed", {})
	if from_province == to_province:
		return PackedInt32Array()
	var dist := {from_province: 0.0}
	var prev := {}
	var visited := {}
	var frontier: Array[int] = [from_province]
	while not frontier.is_empty():
		# small graphs: a linear scan is cheaper than keeping a heap
		var best := 0
		for i in frontier.size():
			if float(dist.get(frontier[i], INF)) < float(dist.get(frontier[best], INF)):
				best = i
		var current: int = frontier[best]
		frontier.remove_at(best)
		if visited.has(current):
			continue
		visited[current] = true
		if current == to_province:
			break
		var g := wd.province_geo(current)
		if g == null:
			continue
		for n: Dictionary in g.neighbors:
			var next_id := int(n["id"])
			var ng := wd.province_geo(next_id)
			if ng == null or visited.has(next_id):
				continue
			var km := g.center.distance_to(ng.center) / 1000.0
			var ground := float(speeds.get(String(ng.terrain), 1.0))
			var cost := km / maxf(ground, 0.1)
			match StringName(n["type"]):
				&"river":
					cost += float(cfg.get("river_crossing_penalty_km", 6.0))
				&"pass":
					cost += float(cfg.get("pass_penalty_km", 10.0))
				&"mountain":
					cost += float(cfg.get("pass_penalty_km", 10.0)) * 2.0
			var total: float = float(dist[current]) + cost
			if total < float(dist.get(next_id, INF)):
				dist[next_id] = total
				prev[next_id] = current
				frontier.append(next_id)
	if not prev.has(to_province) and from_province != to_province:
		return PackedInt32Array()
	var out := PackedInt32Array()
	var walk := to_province
	while walk != from_province:
		out.append(walk)
		walk = int(prev[walk])
	out.reverse()
	return out


# --- supply ------------------------------------------------------------------------------------------------

## True where the army can fill its carts again: its own land, or a settlement of a friendly crown.
static func can_resupply(world: WorldState, army: ArmyState) -> float:
	var cfg: Dictionary = bal().get("supply", {})
	var p := world.province(army.province)
	if p == null:
		return 0.0
	var rate := 0.0
	if p.owner == army.kingdom:
		rate = float(cfg.get("own_province_refill_per_day", 1.2))
	elif p.owner >= 0 and not Diplomacy.at_war(world, p.owner, army.kingdom) \
			and (Diplomacy.has_pact(world, p.owner, army.kingdom, &"alliance") or Diplomacy.has_pact(world, p.owner, army.kingdom, &"vassalage")):
		rate = float(cfg.get("own_province_refill_per_day", 1.2)) * 0.6
	for s in world.settlements:
		if s.kingdom != army.kingdom:
			continue
		if s.center.distance_to(army.pos) < float(cfg.get("food_from_settlement_radius_m", 900.0)):
			rate = maxf(rate, float(cfg.get("friendly_refill_per_day", 2.5)))
	if rate <= 0.0 and army.path.is_empty() and p.owner >= 0 and p.owner != army.kingdom:
		# a host camped in somebody else's fields eats those fields: slowly, and it ruins them
		rate = float(cfg.get("forage_per_day", 0.85))
	return rate


# --- what the crown can see ---------------------------------------------------------------------------------

## True when `kingdom_id` can see this army today: its own hosts always, the others only inside the sight of
## its lands, its settlements and its armies. What it cannot see, the interface does not draw.
static func can_see(world: WorldState, kingdom_id: int, army: ArmyState) -> bool:
	if army.kingdom == kingdom_id:
		return true
	var cfg: Dictionary = bal().get("vision", {})
	var p := world.province(army.province)
	if bool(cfg.get("province_own", true)) and p and p.owner == kingdom_id:
		return true
	for other in world.armies:
		if other.kingdom == kingdom_id and other.pos.distance_to(army.pos) < float(cfg.get("army_radius_m", 9000.0)):
			return true
	for s in world.settlements:
		if s.kingdom == kingdom_id and s.center.distance_to(army.pos) < float(cfg.get("settlement_radius_m", 12000.0)):
			return true
	return false


static func visible_armies(world: WorldState, kingdom_id: int) -> Array[ArmyState]:
	var out: Array[ArmyState] = []
	for a in world.armies:
		if can_see(world, kingdom_id, a):
			out.append(a)
	return out


# --- raising and disbanding ---------------------------------------------------------------------------------

## The levy of a realm whose villages are not simulated one by one: the men come out of the population of a
## province, exactly as its people are counted everywhere else, and go back to it when the host is disbanded.
static func raise_from_province(session: GameSession, k: KingdomState, province_id: int, u: UnitDef) -> ArmyState:
	var world := session.world
	var p := world.province(province_id)
	var g := WorldData.get_instance().province_geo(province_id)
	if p == null or g == null or u == null:
		return null
	p.population = maxi(p.population - u.men, 0)
	k.treasury -= u.gold
	var army: ArmyState = null
	for a in world.armies:
		if a.kingdom == k.id and a.province == province_id and a.path.is_empty():
			army = a
			break
	if army == null:
		army = ArmyState.new()
		army.id = world.new_id()
		army.kingdom = k.id
		army.name = army_name(world, k)
		army.province = province_id
		army.pos = g.center
		army.step_from = army.pos
		army.step_to = army.pos
		army.step_t = 1.0
		world.armies.append(army)
	army.regiments.append({"unit": u.id, "men": u.men, "max_men": u.men, "morale": u.morale,
		"people": PackedInt32Array()})
	army.supplies = maxf(army.supplies, float((bal().get("supply", {}) as Dictionary).get("carried_days", 12.0)) * 0.6)
	EventBus.army_changed.emit(army.id)
	return army


## Sends an aggregate host back into the fields it came from.
static func dissolve_into_province(world: WorldState, a: ArmyState) -> void:
	var p := world.province(a.province)
	if p and p.owner == a.kingdom:
		p.population += a.men()
	world.armies.erase(a)
	EventBus.army_changed.emit(a.id)

## The inhabitants who could carry a spear tomorrow morning.
static func eligible_people(world: WorldState, settlement_id: int) -> Array[PersonState]:
	var cfg: Dictionary = bal().get("recruitment", {})
	var out: Array[PersonState] = []
	for p in world.people_of(settlement_id):
		if p.is_king or p.job == &"child" or p.job == &"soldier":
			continue
		var age := p.age_years(world.day)
		if age < int(cfg.get("min_age", 16)) or age > int(cfg.get("max_age", 45)):
			continue
		out.append(p)
	out.sort_custom(func(a: PersonState, b: PersonState) -> bool: return a.id < b.id)
	return out


## A name in the style of the realm for a new host.
static func army_name(world: WorldState, k: KingdomState) -> String:
	var count := 1
	for a in world.armies:
		if a.kingdom == k.id:
			count += 1
	var ordinals := ["Prima", "Seconda", "Terza", "Quarta", "Quinta", "Sesta", "Settima", "Ottava"]
	# "Regno di Velgrad" -> "Velgrad": a host is named after the land, not after its title
	var land := k.name
	var cut := land.rfind(" di ")
	if cut > 0:
		land = land.substr(cut + 4)
	return "%s schiera di %s" % [ordinals[mini(count - 1, ordinals.size() - 1)], land]

