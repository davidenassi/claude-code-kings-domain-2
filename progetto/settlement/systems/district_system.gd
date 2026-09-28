class_name DistrictSystem
extends SimSystem
## The scale of a town (Rebirth, Phase 5). A settlement grows through grades — nucleus, village, large village,
## borough, city, great capital (settlement.json → tiers) — and from the large village on it grows by QUARTERS
## instead of house by house: a district is one building of the world (a block of 40 m) that holds dozens of homes
## or workshops, and that densifies by itself. Once a month every quarter that is full and whose town is grown
## enough takes the materials of its next level from the stores and grows (more beds, more hands, a wider reach).
## Ten thousand people are then a few dozen quarters, not two thousand houses.
##
## The grade reached is written in the chronicle once.

const TIER_RECORD := "tier_%s"


func _init() -> void:
	id = &"districts"
	frequency = Frequency.MONTH
	order = 27   # after the population and the milestones of the day


func run(session: GameSession, step: SimStep) -> void:
	var world := session.world
	for s in world.settlements:
		_tier(session, s, step.day)
		for b in world.buildings_of(s.id):
			if b.is_active() and b.is_district():
				try_grow(session, s, b)


## Grows a quarter by one level when it can: full, its town grown enough, the materials in the stores. True when
## it grew.
static func try_grow(session: GameSession, s: SettlementState, b: BuildingState) -> bool:
	var world := session.world
	var def := b.def()
	if b.level >= def.max_level():
		return false
	var next := b.level + 1
	var need_tier := StringName((def.district.get("tier_for_level", []) as Array)[next - 1] if next - 1 < (def.district.get("tier_for_level", []) as Array).size() else "")
	if need_tier != &"" and int(SettlementState.tier(world.people_of(s.id).size())["index"]) < SettlementState.tier_index(need_tier):
		return false
	if not _full(world, s, b):
		return false
	var grow: Array = def.district.get("grow", [])
	var cost: Dictionary = grow[next - 1] if next - 1 < grow.size() else {}
	var pending := Placement.committed_materials(world, s.id)
	for res: String in cost.keys():
		if s.amount(StringName(res)) - int(pending.get(StringName(res), 0)) < int(cost[res]):
			return false
	for res: String in cost.keys():
		s.take(StringName(res), int(cost[res]), &"build")
	var old_workers := b.workers()
	b.level = next
	if b.workers_wanted == old_workers:
		b.workers_wanted = b.workers()   # the player had left the hands at the default: the new default
	world.buildings_changed()
	SettlementSim.mark_assignment_dirty(session, s.id)
	EventBus.building_state_changed.emit(b.id)
	EventBus.notify_local("%s cresce" % def.display_name, "A %s il quartiere si allarga: livello %d di %d." % [s.name, b.level,
		def.max_level()], &"building", b.pos)
	return true


## A quarter asks to grow when it is used up: its beds taken, or its hands all at work, or (a store) nearly full.
static func _full(world: WorldState, s: SettlementState, b: BuildingState) -> bool:
	if b.beds() > 0:
		var sleepers := 0
		for p in world.people_of(s.id):
			if p.home == b.id:
				sleepers += 1
		if float(sleepers) >= float(b.beds()) * 0.9:
			return true
	if b.workers() > 0:
		var hands := 0
		for p in world.people_of(s.id):
			if p.workplace == b.id:
				hands += 1
		if hands >= b.workers():
			return true
	if b.def().is_storage and b.storage() > 0:
		var group := b.def().storage_group
		return s.used(group) >= int(float(s.capacity(world, group)) * 0.85)
	var kind := b.def().district_kind()
	# a market, a church, a quarter of soldiers: they grow with the town round them
	if kind in [&"market", &"religious", &"military"]:
		return world.people_of(s.id).size() >= int(float(b.level) * 400.0)
	return false


## The grade of the settlement: written in the chronicle the first time it is reached.
static func _tier(session: GameSession, s: SettlementState, day: int) -> void:
	var world := session.world
	var k := world.kingdom(s.kingdom)
	if k == null:
		return
	var t := SettlementState.tier(world.people_of(s.id).size())
	if int(t["index"]) < 2:
		return   # the village is told by the milestones of the founders
	var key := TIER_RECORD % String(t["id"])
	if k.records.has(key):
		return
	k.records[key] = float(day)
	var text := "%s è ora un %s: %d abitanti." % [s.name, String(t["name"]).to_lower(), world.people_of(s.id).size()]
	world.chronicle.append({"day": day, "kingdom": k.id, "kind": "tier_%s" % String(t["id"]), "text": text})
	if k.id == world.player_kingdom:
		EventBus.notify_local(String(t["name"]), text, &"growth", s.center)


## The trust a church gives its town (the best one counts), and how much faster the soldiers train.
static func trust_bonus(world: WorldState, s: SettlementState) -> float:
	var best := 0.0
	for b in world.buildings_of(s.id):
		var d := b.def()
		if d.has_levels and d.district_kind() == &"religious" and b.is_active():
			best = maxf(best, float(d.level_value(&"trust", b.level, 0.0)))
	return best


static func training_bonus(world: WorldState, s: SettlementState) -> float:
	var total := 0.0
	for b in world.buildings_of(s.id):
		var d := b.def()
		if d.has_levels and d.district_kind() == &"military" and b.is_active():
			total += float(d.level_value(&"training", b.level, 0.0))
	return total


## The gold the markets of a settlement bring in a month.
static func market_income(world: WorldState, s: SettlementState) -> float:
	var rate := 0.0
	for b in world.buildings_of(s.id):
		var d := b.def()
		if d.has_levels and d.district_kind() == &"market" and b.is_active():
			rate += float(d.level_value(&"trade_per_person_month", b.level, 0.0))
	return rate * world.people_of(s.id).size()
