class_name MilitarySystem
extends SimSystem
## Every day of the host: the recruits finish their training and become a regiment, the armies march their
## stretch of road, eat what they carry, fill the carts again in friendly land, and lose men when there is
## nothing to eat or nothing to be paid with. Rules in data/defs/balance/military.json.


func _init() -> void:
	id = &"military"
	frequency = Frequency.DAY
	order = 27


static func bal() -> Dictionary:
	return Military.bal()


func run(session: GameSession, step: SimStep) -> void:
	var world := session.world
	for s in world.settlements:
		_train(session, s, step.day)
	var done: Array[ArmyState] = []
	for a in world.armies:
		_pay(session, a)
		_march(session, a)
		_eat(session, a)
		_morale(session, a)
		if a.is_empty():
			done.append(a)
	for a in done:
		world.armies.erase(a)
		EventBus.army_changed.emit(a.id)


# --- the training yard ------------------------------------------------------------------------------------

func _train(session: GameSession, s: SettlementState, day: int) -> void:
	if s.training.is_empty():
		return
	var world := session.world
	var cfg: Dictionary = bal().get("recruitment", {})
	var speed := 1.0
	for b in world.buildings_of(s.id):
		if b.def().id == &"barracks" and b.is_active():
			speed += float(cfg.get("training_speed_per_barracks", 1.0)) - 1.0 + 0.35
	var still: Array[Dictionary] = []
	for t in s.training:
		t["days_left"] = float(t["days_left"]) - speed
		if float(t["days_left"]) > 0.0:
			still.append(t)
			continue
		_raise_regiment(session, s, t, day)
	s.training = still


static func _raise_regiment(session: GameSession, s: SettlementState, t: Dictionary, day: int) -> void:
	var world := session.world
	var u := Military.unit(t["unit"])
	var k := world.kingdom(s.kingdom)
	if u == null or k == null:
		return
	var people := PackedInt32Array()
	for person_id in (t["people"] as PackedInt32Array):
		var p := world.person(person_id)
		if p == null:
			continue   # died while training
		p.job = &"soldier"
		world.move_person(p, -1)
		p.workplace = -1
		p.home = -1
		p.action = &"march"
		people.append(person_id)
	if people.is_empty():
		return
	var army := _host_at(world, k, s)
	army.regiments.append({"unit": u.id, "men": people.size(), "max_men": u.men,
		"morale": u.morale + _commander_morale(world, army), "people": people})
	army.supplies = maxf(army.supplies, float((bal().get("supply", {}) as Dictionary).get("carried_days", 12.0)) * 0.5)
	SettlementSim.mark_assignment_dirty(session, s.id)
	EventBus.settlement_changed.emit(s.id)
	EventBus.army_changed.emit(army.id)
	EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "recruit",
		"text": "%s: %d %s sono pronti." % [army.name, people.size(), u.display_name.to_lower()]})
	if k.is_player:
		EventBus.notify("Reparto pronto", "%d %s si uniscono a %s." % [people.size(), u.display_name.to_lower(), army.name], &"army")


## The host standing on the settlement, or a new one raised there.
static func _host_at(world: WorldState, k: KingdomState, s: SettlementState) -> ArmyState:
	for a in world.armies:
		if a.kingdom == k.id and a.path.is_empty() and a.pos.distance_to(world.settlement_global_pos(s)) < 600.0:
			return a
	var army := ArmyState.new()
	army.id = world.new_id()
	army.kingdom = k.id
	army.name = Military.army_name(world, k)
	# the host gathers outside the capital on the map of the world (the settlement lives in the valley's metres)
	army.pos = world.settlement_global_pos(s) + Vector2(140.0, 90.0)
	army.province = s.province
	army.step_from = army.pos
	army.step_to = army.pos
	army.step_t = 1.0
	# the best warrior of the court rides with it
	var best := -1
	for c: CharacterState in world.characters.values():
		if c.kingdom != k.id or not c.alive() or c.id == k.ruler or c.age_years(world.day) < 16:
			continue
		if best < 0 or c.skill(&"guerra") > world.character(best).skill(&"guerra"):
			best = c.id
	army.commander = best
	world.armies.append(army)
	return army


static func _commander_morale(world: WorldState, army: ArmyState) -> float:
	var c := world.character(army.commander)
	if c == null:
		return 0.0
	return (c.skill(&"guerra") - 5) * float(Military.captain_rules().get("morale_per_skill", 2.0))


# --- the road ---------------------------------------------------------------------------------------------

func _march(session: GameSession, a: ArmyState) -> void:
	var world := session.world
	if a.path.is_empty():
		a.step_from = a.pos
		a.step_to = a.pos
		a.step_t = 1.0
		return
	var wd := WorldData.get_instance()
	var budget := Military.day_march_km(world, a) * 1000.0
	a.step_from = a.pos
	while budget > 0.0 and not a.path.is_empty():
		var g := wd.province_geo(a.path[0])
		if g == null:
			a.path.remove_at(0)
			continue
		var to_next := a.pos.distance_to(g.center)
		if to_next <= budget:
			a.pos = g.center
			a.province = a.path[0]
			a.path.remove_at(0)
			budget -= to_next
			_enter_province(session, a)
		else:
			a.pos += (g.center - a.pos).normalized() * budget
			budget = 0.0
	a.step_to = a.pos
	a.step_t = 0.0
	EventBus.army_changed.emit(a.id)


## Walking into a province is a fact the world notices.
static func _enter_province(session: GameSession, a: ArmyState) -> void:
	var world := session.world
	var p := world.province(a.province)
	var k := world.kingdom(a.kingdom)
	if p == null or k == null:
		return
	if p.owner >= 0 and p.owner != a.kingdom and Diplomacy.at_war(world, p.owner, a.kingdom):
		var owner := world.kingdom(p.owner)
		if owner and owner.is_player:
			var g := WorldData.get_instance().province_geo(p.id)
			EventBus.notify("Nemici in vista", "%s è entrato in %s." % [a.name, g.name if g else "una provincia"], &"war",
				a.pos)


# --- bread and pay ----------------------------------------------------------------------------------------

func _eat(session: GameSession, a: ArmyState) -> void:
	var world := session.world
	var cfg: Dictionary = bal().get("supply", {})
	var carried_max := float(cfg.get("carried_days", 12.0))
	var refill := Military.can_resupply(world, a)
	if refill > 0.0:
		a.supplies = minf(a.supplies + refill, carried_max)
	a.supplies -= 1.0
	if a.supplies >= 0.0:
		return
	a.supplies = 0.0
	# hungry: men fall out of the ranks and the rest lose heart
	var loss := float(cfg.get("hungry_attrition_per_day", 0.015))
	for r in a.regiments:
		# the losses of hunger add up day by day: a small band does not lose a man every morning
		var owed := float(r.get("attrition", 0.0)) + float(int(r["men"])) * loss
		var lost := int(floor(owed))
		r["attrition"] = owed - float(lost)
		if lost > 0:
			_lose_men(world, r, lost)
		r["morale"] = maxf(float(r["morale"]) - float(cfg.get("hungry_morale_per_day", 3.0)), 0.0)
	var k := world.kingdom(a.kingdom)
	if k and k.is_player:
		EventBus.notify("Fame nell'esercito", "%s è senza rifornimenti." % a.name, &"army", a.pos)


func _pay(session: GameSession, a: ArmyState) -> void:
	var world := session.world
	var k := world.kingdom(a.kingdom)
	if k == null:
		return
	var due := Military.upkeep_per_day(a)
	if k.treasury >= due:
		k.treasury -= due
		a.unpaid_days = 0
	else:
		a.unpaid_days += 1
		var cfg: Dictionary = bal().get("morale", {})
		for r in a.regiments:
			r["morale"] = maxf(float(r["morale"]) - float(cfg.get("unpaid_per_day", 2.5)), 0.0)


func _morale(session: GameSession, a: ArmyState) -> void:
	var world := session.world
	var cfg: Dictionary = bal().get("morale", {})
	var p := world.province(a.province)
	var home := p and p.owner == a.kingdom
	var recover := float(cfg.get("recover_per_day", 0.8)) * (1.0 + (float(cfg.get("home_recover_bonus", 0.6)) if home else 0.0))
	var rng := world.rng.stream(&"military")
	var gone: Array[Dictionary] = []
	for r in a.regiments:
		if a.supplies > 0.0 and a.unpaid_days == 0:
			r["morale"] = minf(float(r["morale"]) + recover, float(cfg.get("max", 100.0)))
		if float(r["morale"]) < float(cfg.get("desertion_below", 25.0)) and rng.randf() < float(cfg.get("desertion_chance_per_day", 0.06)):
			_lose_men(world, r, maxi(1, int(float(int(r["men"])) * 0.15)))
			var k := world.kingdom(a.kingdom)
			if k and k.is_player:
				EventBus.notify("Diserzioni", "Uomini di %s lasciano le file nella notte." % a.name, &"army", a.pos)
		if int(r["men"]) <= 0:
			gone.append(r)
	for r in gone:
		a.regiments.erase(r)


## Men lost are people lost: they leave the world, not a number on a sheet.
static func _lose_men(world: WorldState, regiment: Dictionary, count: int) -> void:
	var people: PackedInt32Array = regiment["people"]
	var lost := 0
	while lost < count and people.size() > 0:
		var person_id := people[people.size() - 1]
		people.remove_at(people.size() - 1)
		world.remove_person(person_id)   # a soldier lost is a person lost
		lost += 1
	regiment["people"] = people
	# the levies of the realms counted in the aggregate have no names to erase
	regiment["men"] = people.size() if people.size() > 0 else maxi(int(regiment["men"]) - count, 0)

