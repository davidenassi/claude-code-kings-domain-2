class_name WorldState
extends RefCounted
## Root of all dynamic, serialisable game state. Static map data (rasters, province shapes)
## is NOT stored here: only what changes during a campaign.
## Later phases add settlements, buildings, population, armies...

const WORLD_VERSION := 1

var world_version: int = WORLD_VERSION
## Absolute simulation tick. day = tick / ticks_per_day.
var tick: int = 0
var ticks_per_day: int = 24
var rng: KDRng = KDRng.new(0)
## Kingdom controlled by the player (-1 until kingdoms exist).
var player_kingdom: int = -1
## Free-form campaign flags (tutorial progress, one-shot events...).
var flags: Dictionary = {}
## Campaign statistics, updated by systems.
var stats: Dictionary = {}
## One entry per province of the official map, index = province id.
var provinces: Array[ProvinceState] = []
## Political entities, index = kingdom id (dead realms stay in the list with alive = false).
var kingdoms: Array[KingdomState] = []
## Physical settlements, index = settlement id.
var settlements: Array[SettlementState] = []
## Buildings and people by id (they can disappear, so dictionaries).
var buildings: Dictionary = {}   # int -> BuildingState
var people: Dictionary = {}      # int -> PersonState
## Characters who count politically (rulers, consorts, heirs), by id.
var characters: Dictionary = {}  # int -> CharacterState
## The families of the community, by id (common people: a royal house is one of them, chosen by the player).
var families: Dictionary = {}    # int -> FamilyState
## What stands between two realms, one entry per pair, keyed "min:max" (see Diplomacy).
var relations: Dictionary = {}   # String -> RelationState
## Offers waiting on the player's table: {id, from, kind, pact, day, expires, text}.
var offers: Array[Dictionary] = []
## The hosts on the map.
var armies: Array[ArmyState] = []
## Fights and sieges going on right now.
var battles: Array[BattleState] = []
var sieges: Array[SiegeState] = []
## What the realm remembers of itself: the chronicle, newest last.
var chronicle: Array[Dictionary] = []
## Events waiting for the player's word: {id, event, day, expires}.
var pending_events: Array[Dictionary] = []
## Changes on the ground (felled trees, quarried rocks), in the local metres of the valley.
var terrain: TerrainDeltas = TerrainDeltas.new()
## The player's homeland (Rebirth): the finite valley whose local metres settlements, buildings, people and the
## changes on the ground are measured in. Provinces, realms and armies stay in the metres of the continent.
## Null only for a world that never had a settlement.
var domain: DomainState = null
var next_id: int = 1
## Bumped whenever the set of buildings changes, so the per-settlement lists can be cached.
## Bumped whenever a province changes hands: who borders whom is cached against it.
var political_version: int = 0
var _adjacency: Dictionary = {}
var _adjacency_version: int = -1
var _lands_cache: Dictionary = {}
var _lands_version: int = -1

var buildings_version: int = 0
## Bumped whenever somebody is born, dies or moves: the per-settlement lists are cached against it.
var people_version: int = 0
var _buildings_cache: Dictionary = {}
var _people_cache: Dictionary = {}


var day: int:
	get:
		return tick / ticks_per_day


func new_id() -> int:
	next_id += 1
	return next_id - 1


## Where a settlement stands on the continent (for the armies, the map symbols and anything else global).
func settlement_global_pos(s: SettlementState) -> Vector2:
	if s == null:
		return Vector2.ZERO
	return domain.to_global(s.center) if domain else s.center


## A position of the valley in the metres of the continent.
func local_to_global(local_pos: Vector2) -> Vector2:
	return domain.to_global(local_pos) if domain else local_pos


## A position of the continent in the metres of the valley.
func global_to_local(global_pos: Vector2) -> Vector2:
	return domain.to_local(global_pos) if domain else global_pos


func settlement(settlement_id: int) -> SettlementState:
	if settlement_id < 0 or settlement_id >= settlements.size():
		return null
	return settlements[settlement_id]


func building(building_id: int) -> BuildingState:
	return buildings.get(building_id)


func army(army_id: int) -> ArmyState:
	for a in armies:
		if a.id == army_id:
			return a
	return null


func person(person_id: int) -> PersonState:
	return people.get(person_id)


func family(family_id: int) -> FamilyState:
	return families.get(family_id)


## Living members of a family.
func members_of(family_id: int) -> Array[PersonState]:
	var out: Array[PersonState] = []
	for p: PersonState in people.values():
		if p.family == family_id:
			out.append(p)
	return out


func character(character_id: int) -> CharacterState:
	return characters.get(character_id)


## The living ruler of a realm, or null during a dynastic crisis.
func ruler_of(kingdom_id: int) -> CharacterState:
	var k := kingdom(kingdom_id)
	if k == null:
		return null
	var c := character(k.ruler)
	return c if c and c.alive() else null


func buildings_of(settlement_id: int) -> Array[BuildingState]:
	var cached: Array = _buildings_cache.get(settlement_id, [])
	if not cached.is_empty() and int(cached[0]) == buildings_version:
		return cached[1]
	var out: Array[BuildingState] = []
	for b: BuildingState in buildings.values():
		if b.settlement == settlement_id:
			out.append(b)
	out.sort_custom(func(a: BuildingState, c: BuildingState) -> bool: return a.id < c.id)
	_buildings_cache[settlement_id] = [buildings_version, out]
	return out


## Call after adding or removing a building (the cached lists are rebuilt on the next request).
func buildings_changed() -> void:
	buildings_version += 1


## The inhabitants of a settlement, by growing id. Called dozens of times a day by every system, so the list
## is cached: `people_version` is bumped by whoever adds, removes or moves a person, and the size of the table
## is checked as well, so a forgotten call can only cost a rebuild, never a wrong answer.
func people_of(settlement_id: int) -> Array[PersonState]:
	var cached: Array = _people_cache.get(settlement_id, [])
	if cached.size() == 3 and int(cached[0]) == people_version and int(cached[1]) == people.size():
		return cached[2]
	var out: Array[PersonState] = []
	for p: PersonState in people.values():
		if p.settlement == settlement_id:
			out.append(p)
	out.sort_custom(func(a: PersonState, c: PersonState) -> bool: return a.id < c.id)
	_people_cache[settlement_id] = [people_version, people.size(), out]
	return out


## Adds an inhabitant to the world (and to the cached list of his settlement).
func add_person(p: PersonState) -> void:
	people[p.id] = p
	people_version += 1


## Removes an inhabitant (death, a soldier lost, a man who leaves the world).
func remove_person(person_id: int) -> void:
	people.erase(person_id)
	people_version += 1


## Moves an inhabitant to another settlement (-1 = he is on the roads with a host).
func move_person(p: PersonState, settlement_id: int) -> void:
	p.settlement = settlement_id
	people_version += 1


## Call when something changed about who lives where and no method above was used.
func people_changed() -> void:
	people_version += 1

func province(province_id: int) -> ProvinceState:
	if province_id < 0 or province_id >= provinces.size():
		return null
	return provinces[province_id]


func kingdom(kingdom_id: int) -> KingdomState:
	if kingdom_id < 0 or kingdom_id >= kingdoms.size():
		return null
	return kingdoms[kingdom_id]


func player() -> KingdomState:
	return kingdom(player_kingdom)


## Owner of a province or null for free lands.
func owner_of(province_id: int) -> KingdomState:
	var p := province(province_id)
	return kingdom(p.owner) if p else null


## Changes the owner (and controller) of a province and keeps the realms' province lists in sync.
## Returns the previous owner id. Callers emit EventBus.province_owner_changed.
func set_province_owner(province_id: int, kingdom_id: int) -> int:
	var p := province(province_id)
	assert(p != null, "unknown province %d" % province_id)
	var old := p.owner
	if old == kingdom_id:
		return old
	var ok := kingdom(old)
	if ok:
		var idx := ok.provinces.find(province_id)
		if idx >= 0:
			ok.provinces.remove_at(idx)
		if ok.capital == province_id:
			ok.capital = ok.provinces[0] if not ok.provinces.is_empty() else -1
		ok.alive = not ok.provinces.is_empty() or ok.is_player
	p.owner = kingdom_id
	p.controller = kingdom_id
	var nk := kingdom(kingdom_id)
	if nk:
		nk.provinces.insert(nk.provinces.bsearch(province_id), province_id)  # kept sorted
		nk.alive = true
		if nk.capital < 0:
			nk.capital = province_id
	political_version += 1
	return old


## What the lands of each realm weigh (provinces, their development and their people), cached by political_version.
func lands_power(kingdom_id: int) -> float:
	if _lands_version != political_version:
		_lands_cache = {}
		for k in kingdoms:
			var value := 0.0
			for pid in k.provinces:
				var p := province(pid)
				if p:
					value += 1.0 + 0.35 * p.development + p.population / 900.0
			_lands_cache[k.id] = value
		_lands_version = political_version
	return float(_lands_cache.get(kingdom_id, 0.0))


## Which realms touch which, as a set of "min:max" keys — rebuilt only when the political map changes.
func adjacency() -> Dictionary:
	if _adjacency_version == political_version:
		return _adjacency
	var wd := WorldData.get_instance()
	var out := {}
	for p in provinces:
		if p.owner < 0:
			continue
		var g := wd.province_geo(p.id)
		if g == null:
			continue
		for n: Dictionary in g.neighbors:
			var np := province(int(n["id"]))
			if np == null or np.owner < 0 or np.owner == p.owner:
				continue
			out["%d:%d" % [mini(p.owner, np.owner), maxi(p.owner, np.owner)]] = true
	_adjacency = out
	_adjacency_version = political_version
	return _adjacency


func rebuild_kingdom_lists() -> void:
	for k in kingdoms:
		k.provinces = PackedInt32Array()
	for p in provinces:
		var k := kingdom(p.owner)
		if k:
			k.provinces.append(p.id)
	political_version += 1


func to_dict() -> Dictionary:
	return {
		"world_version": world_version,
		"tick": tick,
		"ticks_per_day": ticks_per_day,
		"rng": rng.to_dict(),
		"player_kingdom": player_kingdom,
		"flags": flags.duplicate(true),
		"stats": stats.duplicate(true),
		"provinces": provinces.map(func(p: ProvinceState) -> Dictionary: return p.to_dict()),
		"kingdoms": kingdoms.map(func(k: KingdomState) -> Dictionary: return k.to_dict()),
		"settlements": settlements.map(func(st: SettlementState) -> Dictionary: return st.to_dict()),
		"buildings": _sorted_values(buildings).map(func(b: BuildingState) -> Dictionary: return b.to_dict()),
		"people": _sorted_values(people).map(func(pp: PersonState) -> Dictionary: return pp.to_dict()),
		"characters": _sorted_values(characters).map(func(c: CharacterState) -> Dictionary: return c.to_dict()),
		"families": _sorted_values(families).map(func(f: FamilyState) -> Dictionary: return f.to_dict()),
		"relations": relations.keys().map(func(rk: String) -> Dictionary: return (relations[rk] as RelationState).to_dict()),
		"offers": offers.duplicate(true),
		"armies": armies.map(func(a: ArmyState) -> Dictionary: return a.to_dict()),
		"battles": battles.map(func(b: BattleState) -> Dictionary: return b.to_dict()),
		"sieges": sieges.map(func(sg: SiegeState) -> Dictionary: return sg.to_dict()),
		"chronicle": chronicle.duplicate(true),
		"pending_events": pending_events.duplicate(true),
		"terrain": terrain.to_dict(),
		"domain": domain.to_dict() if domain else {},
		"next_id": next_id,
	}


static func _sorted_values(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys.map(func(k: int) -> Variant: return d[k])


static func from_dict(d: Dictionary) -> WorldState:
	var w := WorldState.new()
	w.world_version = int(d.get("world_version", WORLD_VERSION))
	w.tick = int(d.get("tick", 0))
	w.ticks_per_day = int(d.get("ticks_per_day", 24))
	w.rng = KDRng.from_dict(d.get("rng", {}))
	w.player_kingdom = int(d.get("player_kingdom", -1))
	w.flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	w.stats = (d.get("stats", {}) as Dictionary).duplicate(true)
	for pd: Dictionary in d.get("provinces", []):
		w.provinces.append(ProvinceState.from_dict(pd))
	for kd: Dictionary in d.get("kingdoms", []):
		w.kingdoms.append(KingdomState.from_dict(kd))
	w.rebuild_kingdom_lists()
	for sd: Dictionary in d.get("settlements", []):
		w.settlements.append(SettlementState.from_dict(sd))
	for bd: Dictionary in d.get("buildings", []):
		var b := BuildingState.from_dict(bd)
		w.buildings[b.id] = b
	w.buildings_changed()
	for pd: Dictionary in d.get("people", []):
		var p := PersonState.from_dict(pd)
		w.people[p.id] = p
	for cd: Dictionary in d.get("characters", []):
		var c := CharacterState.from_dict(cd)
		w.characters[c.id] = c
	for fd: Dictionary in d.get("families", []):
		var f := FamilyState.from_dict(fd)
		w.families[f.id] = f
	for rd: Dictionary in d.get("relations", []):
		var r := RelationState.from_dict(rd)
		w.relations["%d:%d" % [r.a, r.b]] = r
	for ad: Dictionary in d.get("armies", []):
		w.armies.append(ArmyState.from_dict(ad))
	for bd: Dictionary in d.get("battles", []):
		w.battles.append(BattleState.from_dict(bd))
	for sd: Dictionary in d.get("sieges", []):
		w.sieges.append(SiegeState.from_dict(sd))
	for cd: Dictionary in d.get("chronicle", []):
		var line := {"day": int(cd.get("day", 0)), "kingdom": int(cd.get("kingdom", -1)),
			"kind": String(cd.get("kind", "")), "text": String(cd.get("text", ""))}
		if cd.has("other"):
			line["other"] = int(cd["other"])   # the second realm of the line (consolidation)
		w.chronicle.append(line)
	for pe: Dictionary in d.get("pending_events", []):
		w.pending_events.append({"id": int(pe.get("id", 0)), "event": String(pe.get("event", "")),
			"day": int(pe.get("day", 0)), "expires": int(pe.get("expires", 0))})
	for od: Dictionary in d.get("offers", []):
		w.offers.append({"id": int(od.get("id", 0)), "from": int(od.get("from", -1)), "kind": String(od.get("kind", "")),
			"pact": String(od.get("pact", "")), "day": int(od.get("day", 0)), "expires": int(od.get("expires", 0)),
			"cede": Array(od.get("cede", [])).map(func(v: Variant) -> int: return int(v)),
			"text": String(od.get("text", ""))})
	w.terrain = TerrainDeltas.from_dict(d.get("terrain", {}))
	var dd: Dictionary = d.get("domain", {})
	w.domain = DomainState.from_dict(dd) if not dd.is_empty() else null
	w.next_id = int(d.get("next_id", 1))
	return w

