class_name SettlementSim
extends RefCounted
## Local life of the settlements: every inhabitant follows a timeline of actions (walk, chop, carry, build, farm,
## bake, sleep). Time is in hours (1 tick = 1 hour). An action runs from `seg_t0` to `busy_until`; when it ends its
## `pending` effect is applied (a tree falls, goods reach the stores, a site grows) and the next action is planned.
## Walking is abstracted (data: walk_m_per_hour) so that people are visible moving at observation speed.
## Paths are straight lines for now (roads and pathfinding arrive with the road network).

const TREE_CACHE_KEY := "settlement_tree_cache"

static var _bal: Dictionary = {}


static func bal() -> Dictionary:
	if _bal.is_empty():
		_bal = Defs.balance("settlement")
	return _bal


## The ground the settlements stand on: the player's valley, in its own metres (Rebirth). A world without a valley
## (built by hand in an old test) falls back to the continent, where local and global metres are the same.
static func ground(world: WorldState) -> WorldData:
	var dd := DomainData.of(world)
	return dd if dd != null else WorldData.get_instance()


# --- per tick ---------------------------------------------------------------------------------------

## A settlement runs hour by hour only while it is on screen; otherwise its day is resolved by SettlementAggregate.
static func is_detailed(session: GameSession, settlement_id: int) -> bool:
	return bool((session.runtime.get(&"observed", {}) as Dictionary).get(settlement_id, false))


## Called by the map: which settlements the player is actually watching.
static func set_observed(session: GameSession, ids: Dictionary) -> void:
	session.runtime[&"observed"] = ids


static func tick(session: GameSession) -> void:
	var world := session.world
	var now := float(world.tick)
	var dirty: Dictionary = session.runtime.get(&"assign_dirty", {})
	for s in world.settlements:
		if bool(dirty.get(s.id, true)):
			dirty[s.id] = false
			assign_jobs(world, s)
	session.runtime[&"assign_dirty"] = dirty
	if not _anybody_watching(session):
		# no camera on any settlement: the day is resolved in closed form by SettlementAggregate, and nobody walks
		for s in world.settlements:
			session.runtime["aggregated_%d" % s.id] = true
		return
	for s in world.settlements:
		if is_detailed(session, s.id):
			_wake_people(session, s)   # the camera has just come close: once, spread over the first hours
		else:
			session.runtime["aggregated_%d" % s.id] = true
	# people are stored by growing id, so iterating the values keeps the order deterministic without sorting
	for p: PersonState in world.people.values():
		var s := world.settlement(p.settlement)
		if s == null or not is_detailed(session, s.id):
			continue
		var guard := 0
		while p.busy_until <= now and guard < 10:
			guard += 1
			var t := maxf(p.busy_until, now - 1.0)
			if not _finish(session, s, p, t):
				_plan(session, s, p, t)


## True when at least one settlement is being watched hour by hour.
static func _anybody_watching(session: GameSession) -> bool:
	for watched: bool in (session.runtime.get(&"observed", {}) as Dictionary).values():
		if watched:
			return true
	return false


static func mark_assignment_dirty(session: GameSession, settlement_id: int) -> void:
	var dirty: Dictionary = session.runtime.get(&"assign_dirty", {})
	dirty[settlement_id] = true
	session.runtime[&"assign_dirty"] = dirty


# --- per day ------------------------------------------------------------------------------------------

static func day(session: GameSession, abs_day: int) -> void:
	var world := session.world
	session.runtime[&"month_today"] = 0
	for s in world.settlements:
		if is_detailed(session, s.id):
			_wake_people(session, s)
		else:
			session.runtime["aggregated_%d" % s.id] = true
			SettlementAggregate.day(session, s)
		_eat(world, s)
		mark_assignment_dirty(session, s.id)
	# The lists of standing trees around the woodcutters live on from one day to the next: felled trees are
	# pruned as they are cut and skipped when they are not, so the only thing that can make a list wrong is a
	# stump coming back. When that happens the tree goes back into the lists that reach it.
	var regrown := _regrow(world, abs_day)
	if not regrown.is_empty():
		_add_regrown(session, regrown)


## Trees standing again go back into the lists of the woodcutters that reach them, in their place by distance
## (Phase 19: every list was thrown away at each regrowth and rebuilt the next morning — in a town that had cut
## its woods, trees grow back almost every day: twenty lists of a thousand trees rebuilt a day, 140 ms of its
## 190). The order is the one a rebuilt list would have: every tree of the radius, nearest first.
static func _add_regrown(session: GameSession, trees: Array[Dictionary]) -> void:
	var cache: Dictionary = session.runtime.get(TREE_CACHE_KEY, {})
	for id: int in cache.keys():
		var b := session.world.building(id)
		if b == null:
			cache.erase(id)
			continue
		var radius := float(b.def().work.get("radius_m", 100.0))
		var list: Array[Dictionary] = cache[id]
		for tree in trees:
			if tree["kind"] == LocalFeatures.KIND_BUSH or tree["pos"].distance_to(b.pos) > radius:
				continue   # the same trees candidate_trees() would list: no bushes, only the radius
			var d := b.pos.distance_squared_to(tree["pos"])
			var at := list.size()
			var known := false
			for i in list.size():
				if list[i]["key"] == tree["key"]:
					known = true   # its stump was still in the list: standing again, it is found where it was
					break
				if at == list.size() and b.pos.distance_squared_to(list[i]["pos"]) > d:
					at = i
			if not known:
				list.insert(at, tree)
		cache[id] = list
	session.runtime[TREE_CACHE_KEY] = cache


## Coming back from hours nobody watched (the aggregate day, or the camera gone and back within the same day):
## everybody starts a fresh action from where they stand — a quarter of the people in each of the first hours
## (Phase 19: all of them planned in the same tick, and the camera coming close to a town of fifteen hundred
## stalled the game for a tenth of a second). Called by the first watched tick, not only at the start of a day.
## The trees and rocks reserved by the actions dropped here are free again: before, they stayed reserved for ever.
const WAKE_SPREAD_HOURS := 4


static func _wake_people(session: GameSession, s: SettlementState) -> void:
	var key := "aggregated_%d" % s.id
	if not bool(session.runtime.get(key, true)):
		return
	session.runtime[key] = false
	s.reserved.clear()
	var now := float(session.world.tick)
	for p in session.world.people_of(s.id):
		p.busy_until = now + float(p.id % WAKE_SPREAD_HOURS)
		p.pending = {}
		p.action = &"idle"
		p.seg_from = p.seg_to
		p.seg_t0 = now
		p.seg_t1 = p.busy_until


static func _eat(world: WorldState, s: SettlementState) -> void:
	var people := world.people_of(s.id)
	if people.is_empty():
		return
	var need := float(bal().get("food_per_person_day", 0.25)) * people.size()
	var have := s.food_credit
	# eat whole units, bread first (keeps the leftover fraction as credit)
	for res: StringName in [&"bread", &"grain"]:
		var fv := Defs.resource(res).food_value
		while have < need and s.amount(res) > 0:
			s.take(res, 1, &"food")
			have += fv
	var shortfall := maxf(need - have, 0.0)
	s.food_credit = maxf(have - need, 0.0)
	var per_person := shortfall / float(people.size()) / float(bal().get("food_per_person_day", 0.25))
	if shortfall > 0.0:
		KingdomModifiers.record(world, s.kingdom, &"famine_days", 1.0)
	var cap := float(bal().get("hunger_max_days", 30.0))
	var recovery := float(bal().get("hunger_recovery_per_day", 1.0))
	for p in people:
		if per_person > 0.0:
			p.hunger = minf(p.hunger + per_person, cap)
		else:
			p.hunger = maxf(p.hunger - recovery, 0.0)


## Stumps come back by themselves unless a building now stands there. True when at least one did.
## The stumps whose time has come stand again; returns the trees that did.
static func _regrow(world: WorldState, abs_day: int) -> Array[Dictionary]:
	var grew: Array[Dictionary] = []
	if abs_day < world.terrain.next_regrow_day:
		return grew   # nothing planted here can be back yet: the whole scan is skipped
	var range_days: Array = bal().get("stump_regrow_days", [60, 120])
	var wd := ground(world)
	var sp := LocalFeatures.spacing()
	var next := -1
	for key: String in world.terrain.felled.keys():
		var felled_day := int(world.terrain.felled[key])
		if felled_day == TerrainDeltas.CLEARED_FOR_GOOD:
			continue
		var parts := key.split(":")
		var gx := parts[0].to_int()
		var gy := parts[1].to_int()
		var grow := felled_day + int(lerpf(float(range_days[0]), float(range_days[1]), KDRng.hash01(gx, gy, 4242)))
		if abs_day < grow:
			next = grow if next < 0 else mini(next, grow)
			continue
		var cell_center := Vector2((gx + 0.5) * sp, (gy + 0.5) * sp)
		var blocked := false
		for b: BuildingState in world.buildings.values():
			if b.covers(cell_center, sp):
				blocked = true
				break
		if blocked:
			world.terrain.felled[key] = TerrainDeltas.CLEARED_FOR_GOOD
			continue
		var f := LocalFeatures.cell_feature(wd, gx, gy)
		world.terrain.regrow(key, f.get("pos", cell_center))
		if not f.is_empty():
			grew.append(f)
	world.terrain.next_regrow_day = next if next >= 0 else TerrainDeltas.NEVER
	return grew


# --- jobs ---------------------------------------------------------------------------------------------

static func quota_share(s: SettlementState) -> float:
	for q: Dictionary in bal().get("builder_quotas", []):
		if StringName(q["id"]) == s.builder_quota:
			return float(q["share"])
	return 0.34


## Builders first (up to the quota), then workplaces by job priority; people keep a still-valid job.
static func assign_jobs(world: WorldState, s: SettlementState) -> void:
	var adults: Array[PersonState] = []
	var adult_age := int(Defs.balance("population").get("adult_age", 16))
	for p in world.people_of(s.id):
		if p.is_king or p.job == &"recruit":
			continue   # the king rules and the recruits drill: neither takes a place in a workshop
		if p.age_years(world.day) < adult_age:
			p.job = &"child"
			p.workplace = -1
			continue
		adults.append(p)
	var sites: Array[BuildingState] = []
	var workplaces: Dictionary = {}   # job -> Array[BuildingState]
	for b in world.buildings_of(s.id):
		if not b.is_active():
			sites.append(b)
		elif b.def().job != &"" and b.workers_wanted > 0:
			if not workplaces.has(b.def().job):
				workplaces[b.def().job] = []
			(workplaces[b.def().job] as Array).append(b)
	var builders_target := 0
	if not sites.is_empty() and not adults.is_empty():
		# the fields come before the scaffolding: the hands the food buildings want are never sent to a site,
		# or a village spends its year building houses and misses the harvest that would have fed it
		var food_hands := 0
		for b in world.buildings_of(s.id):
			if b.is_active() and b.workers_wanted > 0 and (b.def().job == &"farmer" or b.def().job == &"baker"):
				food_hands += b.workers_wanted
		var spare := maxi(adults.size() - food_hands, 0)
		# ...unless the granary is already full: with half a year of food in store a quarter of the village can
		# leave the fields for the scaffolding, or a place with more farms than hands never builds a roof again
		if PopulationSystem.food_days(world, s) >= float(bal().get("builders_from_fields_food_days", 180.0)):
			spare = maxi(spare, maxi(1, adults.size() / 4))
		builders_target = clampi(int(round(adults.size() * quota_share(s))), 1, sites.size() * 4)
		builders_target = mini(builders_target, maxi(spare, 1 if spare > 0 else 0))
	var slots := {}   # building id -> free slots
	for job: StringName in workplaces.keys():
		for b: BuildingState in workplaces[job]:
			slots[b.id] = b.workers_wanted
	var builders := 0
	var free: Array[PersonState] = []
	# the same people as `free`, by id: asking an array whether it holds somebody, inside a loop over everybody,
	# cost a town of a thousand five milliseconds a day (Phase 19)
	var is_free := {}
	# keep valid assignments
	for p in adults:
		if p.job == &"builder" and builders < builders_target:
			builders += 1
			continue
		if p.job != &"builder" and p.job != &"idle" and slots.get(p.workplace, 0) > 0:
			var b := world.building(p.workplace)
			if b and b.is_active() and b.def().job == p.job:
				slots[p.workplace] = int(slots[p.workplace]) - 1
				continue
		free.append(p)
		is_free[p.id] = true
	# the sites still want hands and nobody is idle: call them from the workplaces the priority list puts last
	# (builders_target already says how many the fields can spare)
	var missing := builders_target - builders - free.size()
	if missing > 0:
		var order_of := {}
		var ranked: Array = bal().get("job_priority", [])
		for i in ranked.size():
			order_of[StringName(ranked[i])] = i
		var workers: Array[PersonState] = []
		for p in adults:
			if p.job != &"builder" and p.job != &"idle" and not is_free.has(p.id):
				workers.append(p)
		workers.sort_custom(func(a: PersonState, b: PersonState) -> bool:
			var ra := int(order_of.get(a.job, 99))
			var rb := int(order_of.get(b.job, 99))
			return ra > rb if ra != rb else a.id > b.id)
		for p in workers:
			if missing <= 0:
				break
			if slots.has(p.workplace):
				slots[p.workplace] = int(slots[p.workplace]) + 1
			free.append(p)
			is_free[p.id] = true
			missing -= 1
	# a workplace nobody works in (a quarry, a wood) calls one hand from a field that has two, when the granary
	# is full enough: otherwise a village where everybody went to the fields never cuts another stone (Phase 16)
	if PopulationSystem.food_days(world, s) >= float(bal().get("builders_from_fields_food_days", 180.0)):
		var empty := 0
		for job: StringName in workplaces.keys():
			if job == &"farmer" or job == &"baker":
				continue
			for b: BuildingState in workplaces[job]:
				if int(slots.get(b.id, 0)) >= b.workers_wanted:
					empty += 1
		empty -= free.size()
		if empty > 0:
			for p in adults:
				if empty <= 0:
					break
				if p.job != &"farmer" or is_free.has(p.id):
					continue
				var farm := world.building(p.workplace)
				if farm == null or farm.workers_wanted - int(slots.get(farm.id, 0)) < 2:
					continue
				slots[farm.id] = int(slots[farm.id]) + 1
				free.append(p)
				is_free[p.id] = true
				empty -= 1
	for p in free:
		p.job = &"idle"
		p.workplace = -1
	var order: Array = bal().get("job_priority", ["builder"])
	# round after round: first one worker in every workplace (by priority), then the second, and so on,
	# so a new farm never leaves the bakery or the woodcutter empty
	var round_ := 0
	while round_ < 8:
		round_ += 1
		var placed_any := false
		for job_name: String in order:
			var job := StringName(job_name)
			if job == &"builder":
				for p in free:
					if p.job == &"idle" and builders < builders_target:
						p.job = &"builder"
						builders += 1
						placed_any = true
				continue
			for b: BuildingState in workplaces.get(job, []):
				if int(slots.get(b.id, 0)) <= 0 or b.def().workers - int(slots.get(b.id, 0)) >= round_:
					continue
				for p in free:
					if p.job != &"idle":
						continue
					slots[b.id] = int(slots[b.id]) - 1
					p.job = job
					p.workplace = b.id
					placed_any = true
					break
		if not placed_any:
			break
	# spread the builders over the sites
	var i := 0
	for p in adults:
		if p.job == &"builder":
			var still := world.building(p.workplace)
			if still == null or still.is_active():
				p.workplace = sites[i % sites.size()].id
				i += 1
	EventBus.settlement_changed.emit(s.id)


# --- action helpers ---------------------------------------------------------------------------------

## Goods produced, with the realm's modifiers applied (culture, religion, national spirits) and written into
## the registers that feed the spirits. Returns how many units really entered the stores.
static func produce(session: GameSession, s: SettlementState, res: StringName, base: float, extra_keys: Array = []) -> int:
	var amount := KingdomModifiers.settlement_value(session, s, StringName("production.%s" % res), base, extra_keys)
	var n := int(round(amount))
	if n <= 0:
		return 0
	var space := s.space_for(session.world, res)
	if n > space:
		warn_full(session, s, res, n - space)
		n = space
	if n > 0:
		s.add(res, n, &"work")
		KingdomModifiers.record(session.world, s.kingdom, res, float(n))
	return n


const FULL_WARNING_EVERY_DAYS := 30


## Goods lost because the stores are full: the ruler hears it at most once a month per settlement (Phase 19:
## once a day, which filled the news with the same line, and never when the village was not watched).
static func warn_full(session: GameSession, s: SettlementState, res: StringName, lost: int) -> void:
	var key := "full_warned_day_%d" % s.id
	var last := int(session.runtime.get(key, -FULL_WARNING_EVERY_DAYS))
	if session.world.day - last < FULL_WARNING_EVERY_DAYS:
		return
	session.runtime[key] = session.world.day
	var k := session.world.kingdom(s.kingdom)
	if k == null or not k.is_player:
		return
	var rd := Defs.resource(res)
	EventBus.notify_local("Depositi pieni a %s" % s.name, "%d unità di %s vanno perdute: servono magazzini o granai." % [
		lost, rd.display_name.to_lower() if rd else String(res)], &"warning", s.center)


## Extra modifier keys that the land itself unlocks (irrigated fields, arid land). `pos` in the valley's metres.
static func field_keys(world: WorldState, pos: Vector2) -> Array:
	var wd := ground(world)
	var out: Array = []
	var pid := wd.province_at(pos)
	var g := wd.province_geo(pid)
	if g and g.has_river:
		out.append("production.grain_irrigated")
	var bd: BiomeDef = Defs.biome_by_index(wd.biome_at(pos))
	if bd and (bd.id == &"steppe" or bd.id == &"desert" or bd.id == &"mediterranean"):
		out.append("production.arid_land")
	return out


static func efficiency(p: PersonState) -> float:
	return 1.0 - float(bal().get("hunger_work_penalty", 0.5)) * clampf(p.hunger / 10.0, 0.0, 1.0)  # a week and a half without rations halves the work


## The world is passed in (Phase 19: it was Session.current, or else the last world ticked — the wrong roads for
## any session simulated while another one is the current game, as in the tests and the tools).
static func _go(world: WorldState, p: PersonState, t: float, to: Vector2, pending: Dictionary, action: StringName = &"walk") -> void:
	var from := p.seg_to
	var speed := float(bal().get("walk_m_per_hour", 900.0)) * road_speed_factor(world, from, to)
	var hours := from.distance_to(to) / speed
	p.seg_from = from
	p.seg_to = to
	p.seg_t0 = t
	p.seg_t1 = t + maxf(hours, 0.02)
	p.busy_until = p.seg_t1
	p.action = &"carry" if not p.carrying.is_empty() else action
	p.pending = pending


## Faster on finished roads: the share of the path that runs along a road gets the road speed.
static var _roads_cache: Array[BuildingState] = []
static var _roads_version := -1
## The world the caches were filled from: the version of the buildings starts again from zero in every new or
## loaded world, and without this a new game (or the next test) could be handed the roads and the stores of
## the previous one (world art pass: found by the suite, where the village of a later test grew differently)
static var _roads_world := 0


static func active_roads(world: WorldState) -> Array[BuildingState]:
	if _roads_version == world.buildings_version and _roads_world == world.get_instance_id():
		return _roads_cache
	_roads_cache = []
	for b: BuildingState in world.buildings.values():
		if b.is_road() and b.is_active():
			_roads_cache.append(b)
	_roads_version = world.buildings_version
	_roads_world = world.get_instance_id()
	return _roads_cache


static func road_speed_factor(world: WorldState, from: Vector2, to: Vector2) -> float:
	if world == null:
		return 1.0
	var roads := active_roads(world)
	if roads.is_empty():
		return 1.0
	var on_road := 0
	var samples := 8
	for i in samples:
		var q := from.lerp(to, (float(i) + 0.5) / float(samples))
		for r in roads:
			if r.covers(q, 1.0):
				on_road += 1
				break
	var share := float(on_road) / float(samples)
	return 1.0 + (float(bal().get("road_speed_mult", 1.8)) - 1.0) * share


static func _do(p: PersonState, t: float, hours: float, action: StringName, pending: Dictionary) -> void:
	p.seg_from = p.seg_to
	p.seg_t0 = t
	p.seg_t1 = t + hours
	p.busy_until = p.seg_t1
	p.action = action
	p.pending = pending


static func _hour(t: float) -> float:
	return fposmod(t, 24.0)


static func _is_work_time(t: float) -> bool:
	var h := _hour(t)
	return h >= float(bal().get("work_start_hour", 6)) and h < float(bal().get("work_end_hour", 19))


static func _next_work_start(t: float) -> float:
	var start := float(bal().get("work_start_hour", 6))
	var base := floorf(t / 24.0) * 24.0 + start
	return base if base > t else base + 24.0


static var _stores_cache: Dictionary = {}


static func storages(world: WorldState, s: SettlementState) -> Array:
	var entry: Array = _stores_cache.get(s.id, [])
	if not entry.is_empty() and int(entry[0]) == world.buildings_version and int(entry[2]) == world.get_instance_id():
		return entry[1]
	var list: Array = []
	for b in world.buildings_of(s.id):
		if b.is_active() and b.def().is_storage:
			list.append(b)
	_stores_cache[s.id] = [world.buildings_version, list, world.get_instance_id()]
	return list


static func nearest_storage(world: WorldState, s: SettlementState, pos: Vector2, res: StringName = &"") -> BuildingState:
	var best: BuildingState = null
	var best_d := INF
	for b: BuildingState in storages(world, s):
		if res != &"" and not b.def().stores.is_empty() and not b.def().stores.has(res):
			continue
		var d := b.pos.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = b
	return best


static func _door(b: BuildingState, rng_h: float) -> Vector2:
	var fp := b.def().footprint
	return b.pos + Vector2((rng_h - 0.5) * fp.x * 0.6, fp.y * 0.5 + 1.0)


static func _edge_point(b: BuildingState, h: float) -> Vector2:
	if b.is_road():
		var dir := (b.b - b.a).normalized()
		return b.a.lerp(b.b, h) + Vector2(-dir.y, dir.x) * (BuildingState.road_width() * 0.5 + 0.8)
	var r := b.rect().grow(1.0)
	var a := h * 4.0
	if a < 1.0:
		return Vector2(r.position.x + r.size.x * a, r.end.y)
	elif a < 2.0:
		return Vector2(r.end.x, r.position.y + r.size.y * (a - 1.0))
	elif a < 3.0:
		return Vector2(r.position.x + r.size.x * (a - 2.0), r.position.y)
	return Vector2(r.position.x, r.position.y + r.size.y * (a - 3.0))


static func _rand(p: PersonState, t: float, salt: int) -> float:
	return KDRng.hash01(p.id, int(t * 4.0), salt)


# --- finishing an action ----------------------------------------------------------------------------

## Applies the effect of the action that just ended. Returns true if it already scheduled the next action.
static func _finish(session: GameSession, s: SettlementState, p: PersonState, t: float) -> bool:
	var world := session.world
	var pend := p.pending
	p.pending = {}
	match StringName(pend.get("do", "")):
		&"at_tree":
			if world.terrain.is_felled(String(pend["key"])):
				s.reserved.erase(String(pend["key"]))
				return false
			_do(p, t, float(pend.get("hours", 3.0)) / maxf(efficiency(p), 0.2), &"chop", {"do": &"fell", "key": pend["key"], "site": int(pend.get("site", -1))})
			return true
		&"fell":
			var key := String(pend["key"])
			s.reserved.erase(key)
			if world.terrain.is_felled(key):
				return false
			var tree := LocalFeatures.tree_by_key(ground(world), key)
			if tree.is_empty():
				return false
			world.terrain.fell(tree, world.day)
			var wood := 0
			if tree["kind"] == LocalFeatures.KIND_TREE:
				wood = int(round(KingdomModifiers.settlement_value(session, s, &"production.wood", float(bal().get("tree_wood", 3)))))
			if wood > 0:
				p.carrying = {"res": &"wood", "amount": wood, "for_site": -1}
			var site := world.building(int(pend.get("site", -1)))
			if site and not site.is_active():
				try_finish_site(session, s, site)
			return false
		&"at_rock":
			var rock := LocalFeatures.outcrop(ground(world), String(pend["key"]))
			if rock.is_empty() or world.terrain.rock_charges_left(rock) <= 0:
				s.reserved.erase(String(pend["key"]))
				return false
			_do(p, t, float(pend.get("hours", 4.0)) / maxf(efficiency(p), 0.2), &"quarry", {"do": &"quarried", "key": pend["key"], "building": pend.get("building", -1)})
			return true
		&"quarried":
			var rock := LocalFeatures.outcrop(ground(world), String(pend["key"]))
			s.reserved.erase(String(pend["key"]))
			var b := world.building(int(pend.get("building", -1)))
			if rock.is_empty() or b == null or not world.terrain.use_rock_charge(rock):
				return false
			var yield_d: Dictionary = b.def().work.get("yield", {"stone": 2})
			for res: String in yield_d.keys():
				var got := int(round(KingdomModifiers.settlement_value(session, s, StringName("production.%s" % res), float(yield_d[res]))))
				p.carrying = {"res": StringName(res), "amount": maxi(got, 1), "for_site": -1}
			return false
		&"pickup":
			var got := s.take(StringName(pend["res"]), int(pend["amount"]), &"build" if int(pend.get("site", -1)) >= 0 else &"work")
			if got > 0:
				p.carrying = {"res": StringName(pend["res"]), "amount": got, "for_site": int(pend.get("site", -1)),
					"for_bake": int(pend.get("bake", -1))}
			return false
		&"deliver":
			_deliver(session, s, p)
			return false
		&"build":
			var site := world.building(int(pend["site"]))
			if site and not site.is_active():
				site.work_done += KingdomModifiers.settlement_value(session, s, &"construction.speed", float(pend["hours"]) * efficiency(p))
				try_finish_site(session, s, site)
			return false
		&"at_site":
			var site := world.building(int(pend["site"]))
			if site == null or site.is_active() or not site.missing_materials().is_empty():
				return false
			var hours := minf(2.0, maxf(site.required_hours() - site.work_done, 0.25))
			_do(p, t, hours, &"build", {"do": &"build", "site": site.id, "hours": hours})
			return true
		&"at_field":
			_do(p, t, 3.0, &"farm", {"do": &"farmed", "building": pend["building"]})
			return true
		&"farmed":
			var farm := world.building(int(pend["building"]))
			if farm and farm.is_active():
				var grown := 3.0 * efficiency(p) * float(farm.def().work.get("grain_per_work_hour", 0.05)) \
					* _fertility(world, farm.pos) * season_agriculture(session, world.day)
				farm.crop += KingdomModifiers.settlement_value(session, s, &"production.grain", grown, field_keys(world, farm.pos))
			return false
		&"harvest":
			var farm := world.building(int(pend["building"]))
			if farm and farm.crop >= 1.0:
				var n := mini(int(floor(farm.crop)), int(bal().get("carry_capacity", 12)))
				n = mini(n, s.space_for(world, &"grain"))
				farm.crop -= n
				p.carrying = {"res": &"grain", "amount": n, "for_site": -1}
			return false
		&"at_bakery":
			var bakery := world.building(int(pend["building"]))
			if bakery == null or not bakery.is_active() or p.carrying.is_empty():
				return false
			var work: Dictionary = bakery.def().work
			p.pending = {}
			var carried := p.carrying
			p.carrying = {}
			_do(p, t, float(work.get("hours", 8.0)) / maxf(efficiency(p), 0.2), &"bake",
				{"do": &"baked", "building": bakery.id, "used": int(carried["amount"])})
			return true
		&"baked":
			var bakery := world.building(int(pend["building"]))
			if bakery:
				var work: Dictionary = bakery.def().work
				var input_n := 0
				for res: String in (work.get("input", {}) as Dictionary).keys():
					input_n = int(work["input"][res])
				var ratio := float(pend.get("used", input_n)) / maxf(float(input_n), 1.0)
				for res: String in (work.get("output", {}) as Dictionary).keys():
					var made := KingdomModifiers.settlement_value(session, s, StringName("production.%s" % res), float(work["output"][res]) * ratio)
					p.carrying = {"res": StringName(res), "amount": maxi(int(round(made)), 1), "for_site": -1}
			return false
		&"idle":
			# at the end of a stroll the person stands there a while (Phase 19: the next plan came at once, inside
			# the same quarter of an hour, so it drew the same numbers — the same stroll to the same spot, up to ten
			# times an hour: in a town of a thousand, twenty-five thousand plans a day for people doing nothing)
			if _is_work_time(t):
				_do(p, t, 1.5 + 2.5 * _rand(p, t, 10), &"idle", {})
				return true
			return false
	return false


static func _deliver(session: GameSession, s: SettlementState, p: PersonState) -> void:
	if p.carrying.is_empty():
		return
	var world := session.world
	var res: StringName = p.carrying["res"]
	var n := int(p.carrying["amount"])
	var site := world.building(int(p.carrying.get("for_site", -1)))
	if site and not site.is_active():
		var need := int(site.missing_materials().get(res, 0))
		var put := mini(need, n)
		if put > 0:
			site.delivered[res] = int(site.delivered.get(res, 0)) + put
			n -= put
			EventBus.building_state_changed.emit(site.id)
			try_finish_site(session, s, site)
	if n > 0:
		KingdomModifiers.record(world, s.kingdom, res, float(n))
		var space := s.space_for(world, res)
		if n > space:
			var lost := n - space
			n = space
			warn_full(session, s, res, lost)
		if n > 0:
			# what comes back from a site or an oven was counted when it left; what a worker brings is new
			var back := int(p.carrying.get("for_site", -1)) >= 0 or int(p.carrying.get("for_bake", -1)) >= 0
			s.add(res, n, (&"build" if int(p.carrying.get("for_site", -1)) >= 0 else &"work") if back else &"work")
	p.carrying = {}
	EventBus.settlement_changed.emit(s.id)


static func try_finish_site(session: GameSession, s: SettlementState, site: BuildingState) -> void:
	var world := session.world
	if site.is_active() or site.work_done < site.required_hours() or not site.missing_materials().is_empty():
		return
	var on_site := site.trees_on_ground(ground(world))
	for t in on_site:
		if not world.terrain.is_felled(t["key"]):
			return
	for t in on_site:
		world.terrain.felled[t["key"]] = TerrainDeltas.CLEARED_FOR_GOOD
	site.status = BuildingState.Status.ACTIVE
	world.buildings_changed()
	site.work_done = site.required_hours()
	mark_assignment_dirty(session, s.id)
	EventBus.building_state_changed.emit(site.id)
	EventBus.building_completed.emit(site.id)
	EventBus.notify_local("Costruzione completata", "%s a %s." % [site.def().display_name, s.name], &"building", site.pos)
	_remember_building(session, s, site)


## The chronicle keeps the great works: the first building of every important kind, and the day the village
## reaches fifty, a hundred, two hundred buildings (Phase 17).
const NOTABLE_BUILDINGS := [&"bakery", &"granary", &"well", &"quarry", &"mine", &"smith", &"barracks", &"storehouse"]
const GROWTH_STEPS := [50, 100, 200, 400]


static func _remember_building(session: GameSession, s: SettlementState, site: BuildingState) -> void:
	var world := session.world
	var k := world.kingdom(s.kingdom)
	if k == null:
		return
	if site.def_id in NOTABLE_BUILDINGS and not k.records.has(StringName("first_built:%s" % site.def_id)):
		k.records[StringName("first_built:%s" % site.def_id)] = float(world.day)
		EventBus.chronicle_written.emit({"day": world.day, "kingdom": k.id, "kind": "first_building",
			"text": "A %s si alza il primo edificio di questo genere: %s." % [s.name, site.def().display_name.to_lower()]})
	var standing := 0
	for b in world.buildings_of(s.id):
		if b.is_active() and not b.is_road():
			standing += 1
	for step: int in GROWTH_STEPS:
		if standing >= step and not k.records.has(StringName("built_%d" % step)):
			k.records[StringName("built_%d" % step)] = float(world.day)
			EventBus.chronicle_written.emit({"day": world.day, "kingdom": k.id, "kind": "growth",
				"text": "%s conta ormai %d edifici: da villaggio si fa borgo." % [s.name, step] if step >= 100 else
					"%s conta ormai %d edifici." % [s.name, step]})


static func _fertility(world: WorldState, pos: Vector2) -> float:
	var bd: BiomeDef = Defs.biome_by_index(ground(world).biome_at(pos))
	return bd.fertility if bd else 0.5


static func season_agriculture(session: GameSession, abs_day: int) -> float:
	var season := session.calendar.season_of(abs_day)
	var seasons: Array = Defs.balance("time").get("seasons", [])
	return float((seasons[season] as Dictionary).get("agriculture", 1.0)) if season < seasons.size() else 1.0


# --- planning the next action -----------------------------------------------------------------------

static func _plan(session: GameSession, s: SettlementState, p: PersonState, t: float) -> void:
	var world := session.world
	# goods in hand go where they are needed
	if not p.carrying.is_empty():
		var bake := world.building(int(p.carrying.get("for_bake", -1)))
		if bake and bake.is_active():
			_go(session.world, p, t, _door(bake, _rand(p, t, 1)), {"do": &"at_bakery", "building": bake.id})
			return
		var site := world.building(int(p.carrying.get("for_site", -1)))
		if site == null and p.job == &"builder":
			site = world.building(p.workplace)
			if site and not site.is_active() and int(site.missing_materials().get(p.carrying["res"], 0)) > 0:
				p.carrying["for_site"] = site.id
			else:
				site = null
		if site and not site.is_active():
			_go(session.world, p, t, _edge_point(site, _rand(p, t, 2)), {"do": &"deliver"})
			return
		var store := nearest_storage(world, s, p.seg_to, p.carrying["res"])
		if store:
			_go(session.world, p, t, _door(store, _rand(p, t, 3)), {"do": &"deliver"})
		else:
			_do(p, t, 0.1, &"idle", {"do": &"deliver"})
		return
	var home := world.building(p.home)
	if not _is_work_time(t) or p.is_king:
		if not _is_work_time(t):
			if home and p.seg_to.distance_to(_door(home, 0.5)) > 6.0:
				_go(session.world, p, t, _door(home, _rand(p, t, 4)), {"do": &"home"})
			else:
				_do(p, t, _next_work_start(t) - t, &"sleep", {})
			return
	match p.job:
		&"builder":
			if _plan_builder(session, s, p, t):
				return
		&"woodcutter":
			if _plan_fell(session, s, p, t):
				return
		&"quarrier":
			if _plan_quarry(session, s, p, t):
				return
		&"farmer":
			if _plan_farm(session, s, p, t):
				return
		&"baker":
			if _plan_bake(session, s, p, t):
				return
	_plan_idle(world, p, t, home)


static func _plan_idle(world: WorldState, p: PersonState, t: float, home: BuildingState) -> void:
	var anchor := home.pos if home else p.seg_to
	if _rand(p, t, 7) < 0.35:
		var a := TAU * _rand(p, t, 8)
		var r := 6.0 + 12.0 * _rand(p, t, 9)
		_go(world, p, t, anchor + Vector2(cos(a), sin(a) * 0.7) * r + Vector2(0, 8), {"do": &"idle"})
	else:
		_do(p, t, 1.5 + 2.5 * _rand(p, t, 10), &"idle", {})


static func _plan_builder(session: GameSession, s: SettlementState, p: PersonState, t: float) -> bool:
	var world := session.world
	var site := world.building(p.workplace)
	if site == null or site.is_active():
		return false
	# 1. clear the trees on the footprint (scanned once per site and kept in the session cache)
	var key := "site_trees_%d" % site.id
	var pending_trees: Array = session.runtime.get(key, [])
	if not session.runtime.has(key):
		pending_trees = site.trees_on_ground(ground(world))
		session.runtime[key] = pending_trees
	var best := {}
	var best_d := INF
	var still: Array = []
	for tree: Dictionary in pending_trees:
		if world.terrain.is_felled(tree["key"]):
			continue
		still.append(tree)
		if s.reserved.has(tree["key"]):
			continue
		var d := p.seg_to.distance_squared_to(tree["pos"])
		if d < best_d:
			best_d = d
			best = tree
	if still.size() != pending_trees.size():
		session.runtime[key] = still
	if not best.is_empty():
		s.reserved[best["key"]] = p.id
		var hours := float(Defs.building(&"woodcutter").work.get("hours", 3.0)) * (0.4 if best["kind"] == LocalFeatures.KIND_BUSH else 1.0)
		_go(session.world, p, t, best["pos"] + Vector2(1.2, 0.4), {"do": &"at_tree", "key": best["key"], "hours": hours, "site": site.id})
		return true
	# 2. bring the materials still missing (minus what others are already carrying)
	var missing := site.missing_materials()
	if missing.is_empty():
		_go(session.world, p, t, _edge_point(site, _rand(p, t, 12)), {"do": &"at_site", "site": site.id})
		return true
	for other: PersonState in world.people.values():
		if other != p and not other.carrying.is_empty() and int(other.carrying.get("for_site", -1)) == site.id:
			missing[other.carrying["res"]] = int(missing.get(other.carrying["res"], 0)) - int(other.carrying["amount"])
		if other != p and StringName(other.pending.get("do", "")) == &"pickup" and int(other.pending.get("site", -1)) == site.id:
			missing[StringName(other.pending["res"])] = int(missing.get(StringName(other.pending["res"]), 0)) - int(other.pending["amount"])
	for res: StringName in missing.keys():
		var n := mini(int(missing[res]), int(bal().get("carry_capacity", 12)))
		if n <= 0 or s.amount(res) <= 0:
			continue
		var store := nearest_storage(world, s, site.pos, res)
		if store == null:
			continue
		_go(session.world, p, t, _door(store, _rand(p, t, 11)), {"do": &"pickup", "res": res, "amount": mini(n, s.amount(res)), "site": site.id})
		return true
	if not site.missing_materials().is_empty():
		# waiting for materials: stand by the site
		_do(p, t, 1.0, &"idle", {})
		return true
	# 3. build
	_go(session.world, p, t, _edge_point(site, _rand(p, t, 12)), {"do": &"at_site", "site": site.id})
	return true


## At most this many woodcutters an hour get their list of trees made in the simulation hour by hour: after a load
## the lists do not exist (they are not saved) and the first working hour made all of them at once — thirty lists,
## a tenth of a second in one frame in a town of fifteen hundred (Phase 19). The others start an hour later.
const TREE_LISTS_PER_TICK := 6


static func _may_build_tree_list(session: GameSession, b: BuildingState) -> bool:
	if (session.runtime.get(TREE_CACHE_KEY, {}) as Dictionary).has(b.id):
		return true
	var budget: Array = session.runtime.get("tree_list_budget", [-1, 0])
	if int(budget[0]) != session.world.tick:
		budget = [session.world.tick, 0]
	if int(budget[1]) >= TREE_LISTS_PER_TICK:
		return false
	budget[1] = int(budget[1]) + 1
	session.runtime["tree_list_budget"] = budget
	return true


static func candidate_trees(session: GameSession, b: BuildingState) -> Array[Dictionary]:
	var cache: Dictionary = session.runtime.get(TREE_CACHE_KEY, {})
	if not cache.has(b.id):
		var radius := float(b.def().work.get("radius_m", 100.0))
		var list: Array[Dictionary] = []
		for tree in LocalFeatures.trees_in_rect(ground(session.world), Rect2(b.pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false):
			if tree["pos"].distance_to(b.pos) <= radius:
				list.append(tree)
		list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return b.pos.distance_squared_to(x["pos"]) < b.pos.distance_squared_to(y["pos"]))
		cache[b.id] = list
		session.runtime[TREE_CACHE_KEY] = cache
	return cache[b.id]


static func _plan_fell(session: GameSession, s: SettlementState, p: PersonState, t: float) -> bool:
	var world := session.world
	var b := world.building(p.workplace)
	if b == null or not b.is_active() or not _has_room(world, s, b):
		return false
	if not _may_build_tree_list(session, b):
		return false   # its list of trees is made in one of the next hours: this one it waits
	# the cache is pruned as the wood is worked, so the list stays short
	var candidates := candidate_trees(session, b)
	var chosen := {}
	var keep_from := 0
	for i in candidates.size():
		var tree: Dictionary = candidates[i]
		if world.terrain.is_felled(tree["key"]):
			if i == keep_from:
				keep_from += 1
			continue
		if s.reserved.has(tree["key"]):
			continue
		chosen = tree
		break
	if keep_from > 0:
		var cache: Dictionary = session.runtime.get(TREE_CACHE_KEY, {})
		cache[b.id] = candidates.slice(keep_from)
		session.runtime[TREE_CACHE_KEY] = cache
	if chosen.is_empty():
		return false
	s.reserved[chosen["key"]] = p.id
	_go(session.world, p, t, chosen["pos"] + Vector2(1.2, 0.4), {"do": &"at_tree", "key": chosen["key"], "hours": float(b.def().work.get("hours", 3.0))})
	return true


static func _plan_quarry(session: GameSession, s: SettlementState, p: PersonState, t: float) -> bool:
	var world := session.world
	var b := world.building(p.workplace)
	if b == null or not b.is_active() or not _has_room(world, s, b):
		return false
	var deposit := StringName(b.def().work.get("deposit", "stone"))
	var radius := float(b.def().work.get("radius_m", 90.0))
	var best := {}
	var best_d := INF
	for rock in LocalFeatures.outcrops_in_rect(ground(world), Rect2(b.pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0)):
		if rock["deposit"] != deposit or world.terrain.rock_charges_left(rock) <= 0 or s.reserved.has(rock["id"]):
			continue
		var d := b.pos.distance_squared_to(rock["pos"])
		if d < best_d and d <= radius * radius:
			best_d = d
			best = rock
	if best.is_empty():
		return false
	s.reserved[best["id"]] = p.id
	_go(session.world, p, t, best["pos"] + Vector2(1.8, 0.8), {"do": &"at_rock", "key": best["id"], "hours": float(b.def().work.get("hours", 4.0)), "building": b.id})
	return true


## True while the stores can still take what this building produces.
static func _has_room(world: WorldState, s: SettlementState, b: BuildingState) -> bool:
	var work: Dictionary = b.def().work
	for key: String in ["yield", "output"]:
		for res: String in (work.get(key, {}) as Dictionary).keys():
			if s.space_for(world, StringName(res)) < int(work[key][res]):
				return false
	return true


static func _plan_farm(session: GameSession, s: SettlementState, p: PersonState, t: float) -> bool:
	var world := session.world
	var farm := world.building(p.workplace)
	if farm == null or not farm.is_active():
		return false
	if farm.crop >= 1.0 and s.space_for(world, &"grain") <= 0:
		return false
	var month := int(session.runtime.get(&"month_today", 0))
	if month == 0:
		month = int(session.calendar.date_of(world.day)["month"])
		session.runtime[&"month_today"] = month
	var work := farm.def().work
	var sow := int(work.get("sow_month", 3))
	var harvest := int(work.get("harvest_month", 8))
	var r := farm.rect()
	if month >= harvest and farm.crop >= 1.0:
		_go(session.world, p, t, r.position + Vector2(r.size.x * _rand(p, t, 13), r.size.y * (0.3 + 0.6 * _rand(p, t, 14))), {"do": &"harvest", "building": farm.id})
		return true
	if month >= sow and month < harvest:
		_go(session.world, p, t, r.position + Vector2(r.size.x * _rand(p, t, 15), r.size.y * (0.35 + 0.6 * _rand(p, t, 16))), {"do": &"at_field", "building": farm.id})
		return true
	return false


static func _plan_bake(session: GameSession, s: SettlementState, p: PersonState, t: float) -> bool:
	var world := session.world
	var bakery := world.building(p.workplace)
	if bakery == null or not bakery.is_active() or not _has_room(world, s, bakery):
		return false
	var input: Dictionary = bakery.def().work.get("input", {})
	for res: String in input.keys():
		var n := int(input[res])
		if s.amount(StringName(res)) < n:
			return false
		var store := nearest_storage(world, s, bakery.pos, StringName(res))
		if store == null:
			return false
		_go(session.world, p, t, _door(store, _rand(p, t, 17)), {"do": &"pickup", "res": StringName(res), "amount": n, "bake": bakery.id})
		return true
	return false

