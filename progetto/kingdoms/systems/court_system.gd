class_name CourtSystem
extends SimSystem
## The crown as a person and as a balance of powers: rulers age and die, heirs succeed (or fail to), the five
## factions grant or withdraw their favour, and the measures of the crown — legitimacy, order, prestige — follow
## the facts every day. Rules in data/defs/balance/crown.json, data/defs/traits.json, data/defs/factions.json.


func _init() -> void:
	id = &"court"
	frequency = Frequency.DAY
	order = 28


static var _factions: Array[FactionDef] = []


static func bal() -> Dictionary:
	return Defs.balance("crown")


## The five powers, read once from the data.
static func factions() -> Array[FactionDef]:
	if _factions.is_empty():
		for f: FactionDef in Defs.all("factions"):
			_factions.append(f)
	return _factions


# --- founding the courts --------------------------------------------------------------------------------

## Gives every realm a ruler, a consort and some children, plus the default laws. Called once, at the start.
static func found_courts(session: GameSession) -> void:
	var world := session.world
	for k in world.kingdoms:
		if k.ruler >= 0 or not k.alive or not k.monarchy_founded:
			continue   # a community with no crown yet is crowned by nobody but its own families (Phase 15)
		for g: Dictionary in Laws.groups():
			var def_opt := Laws.default_option(StringName(g["id"]))
			if def_opt != &"":
				k.laws[StringName(g["id"])] = def_opt
		for f: FactionDef in factions():
			k.favour[f.id] = float(bal().get("factions", {}).get("start_favour", 55.0))
		k.legitimacy = float(bal().get("legitimacy", {}).get("start", 65.0))
		k.stability = float(bal().get("stability", {}).get("start", 80.0))
		k.prestige = float(bal().get("prestige", {}).get("start", 10.0))
		var court: Dictionary = bal().get("court", {})
		var rng := world.rng.stream(&"court")
		var ages: Array = court.get("ruler_age", [26, 46])
		var ruler := _make_character(session, k, rng.randi_range(int(ages[0]), int(ages[1])), false, rng)
		k.ruler = ruler.id
		_link_king_person(world, k, ruler)
		# consort and children
		if rng.randf() < 0.85:
			var delta: Array = court.get("consort_age_delta", [-6, 4])
			var consort := _make_character(session, k, maxi(ruler.age_years(world.day) + rng.randi_range(int(delta[0]), int(delta[1])), 16), not ruler.female, rng)
			ruler.consort = consort.id
			consort.consort = ruler.id
			var kids: Array = court.get("children_at_start", [0, 3])
			for i in rng.randi_range(int(kids[0]), int(kids[1])):
				var age := rng.randi_range(0, mini(int(court.get("child_age_max", 20)), maxi(ruler.age_years(world.day) - 18, 1)))
				var child := _make_character(session, k, age, rng.randf() < 0.5, rng, ruler)
				child.parent = ruler.id
				ruler.children.append(child.id)
		k.records[&"rulers_crowned"] = float(k.records.get(&"rulers_crowned", 0.0)) + 1.0
		EventBus.chronicle_written.emit({"day": world.day, "kingdom": k.id, "kind": "reign_begins",
			"text": "%s di %s sale al trono." % [ruler.name, ruler.house]})


## Two or three traits that do not contradict each other. A child may take one from the parent: houses have a
## character that lasts, and a change of ruler can still change the realm (Phase 17).
static func pick_traits(c: CharacterState, rng: RandomNumberGenerator, parent: CharacterState = null) -> void:
	var court: Dictionary = bal().get("court", {})
	var pool: Array = Defs.all("traits")
	var wanted: Array = court.get("traits_per_ruler", [2, 3])
	var n := rng.randi_range(int(wanted[0]), int(wanted[1]))
	if parent and not parent.traits.is_empty() and rng.randf() < float(court.get("inherit_trait_chance", 0.4)):
		var from_parent := StringName(parent.traits[rng.randi_range(0, parent.traits.size() - 1)])
		c.traits.append(from_parent)
	var tries := 0
	while c.traits.size() < n and tries < 40:
		tries += 1
		var pick: TraitDef = pool[rng.randi_range(0, pool.size() - 1)]
		if c.traits.has(pick.id) or traits_clash(c.traits, pick):
			continue
		c.traits.append(pick.id)


static func traits_clash(have: Array, t: TraitDef) -> bool:
	for id_value in have:
		var other := Defs.get_def("traits", StringName(id_value)) as TraitDef
		if t.opposite.has(StringName(id_value)) or (other and other.opposite.has(t.id)):
			return true
	return false


static func _make_character(session: GameSession, k: KingdomState, age: int, female: bool, rng: RandomNumberGenerator,
		parent: CharacterState = null) -> CharacterState:
	var world := session.world
	var court: Dictionary = bal().get("court", {})
	var names: Dictionary = (Defs.read_json("res://data/defs/person_names.json") as Dictionary)["cultures"]
	var pool: Dictionary = names.get(String(k.culture), names["latin"])
	var list: Array = pool["female" if female else "male"]
	var c := CharacterState.new()
	c.id = world.new_id()
	c.name = String(list[rng.randi_range(0, list.size() - 1)])
	c.house = k.house
	c.female = female
	c.birth_day = world.day - age * PersonState.DAYS_PER_YEAR - rng.randi_range(0, 359)
	c.kingdom = k.id
	pick_traits(c, rng, parent)
	var sk: Array = court.get("skill_range", [2, 9])
	for key: StringName in [&"governo", &"guerra", &"diplomazia", &"intrigo"]:
		c.skills[key] = rng.randi_range(int(sk[0]), int(sk[1]))
	world.characters[c.id] = c
	return c


## The king of the player's realm also walks on the map: he is the PersonState marked as king.
static func _link_king_person(world: WorldState, k: KingdomState, ruler: CharacterState) -> void:
	for s in world.settlements:
		if s.kingdom != k.id:
			continue
		for p in world.people_of(s.id):
			if p.is_king:
				ruler.person = p.id
				ruler.name = p.name
				ruler.female = p.female
				ruler.birth_day = p.birth_day
				return


# --- daily life of the court ----------------------------------------------------------------------------

const MEASURE_SPREAD := 7   ## every realm is weighed once a week, on its own day


func run(session: GameSession, step: SimStep) -> void:
	var world := session.world
	_age_and_die(session, step.day)
	_forget_the_long_dead(world, step.day)
	for k in world.kingdoms:
		if not k.alive or not k.monarchy_founded:
			continue   # no crown, no court: favour, measures and the royal family wait for the monarchy
		if not k.edicts.is_empty():
			_expire_edicts(session, k, step.day)
		if step.is_new_year:
			_family_life(session, k, step.day)
			_stability_year(k)
		_revolt_watch(session, k, step.day)
		if k.id % MEASURE_SPREAD == step.day % MEASURE_SPREAD:
			_favour(session, k)
			_measures(session, k)


## A year of a realm both believed and obeyed adds to its longest peace at home (the objective of stability).
static func _stability_year(k: KingdomState) -> void:
	var cfg: Dictionary = bal().get("revolt", {})
	if k.stability >= float(cfg.get("stability", 60.0)) and k.legitimacy >= float(cfg.get("legitimacy", 60.0)):
		k.records[&"stable_years"] = float(k.records.get(&"stable_years", 0.0)) + 1.0
		k.records[&"stable_best"] = maxf(float(k.records.get(&"stable_best", 0.0)), float(k.records[&"stable_years"]))
	else:
		k.records[&"stable_years"] = 0.0


## When stability breaks down the chronicle says so, once per rising; it says it again when order comes back.
static func _revolt_watch(session: GameSession, k: KingdomState, day: int) -> void:
	var cfg: Dictionary = bal().get("revolt", {})
	var in_revolt := float(k.records.get(&"in_revolt", 0.0)) > 0.0
	if not in_revolt and k.stability < float(cfg.get("revolt_below", 18.0)):
		k.records[&"in_revolt"] = 1.0
		KingdomModifiers.record(session.world, k.id, &"revolts", 1.0)
		EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "revolt",
			"text": "%s è in rivolta: le campagne non obbediscono più alla corona." % k.name})
		if k.is_player:
			EventBus.notify("Rivolta", "La stabilità del regno è crollata: le campagne non obbediscono più.", &"warning")
	elif in_revolt and k.stability > float(cfg.get("revolt_over", 40.0)):
		k.records[&"in_revolt"] = 0.0
		EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "revolt_over",
			"text": "Nel %s è tornata la calma." % k.name})


static func _expire_edicts(session: GameSession, k: KingdomState, day: int) -> void:
	for edict_id: StringName in k.edicts.keys():
		if day >= int(k.edicts[edict_id]):
			k.edicts.erase(edict_id)
			k.identity_changed()
			var ed := Laws.edict(edict_id)
			if k.is_player:   # the courts of the world are news for the chronicle, not for the player
				EventBus.notify("Editto scaduto", "%s non è più in vigore." % ed.get("name", edict_id), &"law")


func _age_and_die(session: GameSession, day: int) -> void:
	var world := session.world
	var cfg: Dictionary = bal().get("court", {}).get("death", {})
	var rng := world.rng.stream(&"court")
	var today := day % MEASURE_SPREAD   # worked out once: the register is long and most of it is skipped
	for c: CharacterState in world.characters.values():
		if c.id % MEASURE_SPREAD != today or not c.alive():
			continue   # every man is looked at once a week, with a week of chance on his head
		var k := world.kingdom(c.kingdom)
		if k == null or not k.alive:
			continue
		var age := c.age_years(day)
		var annual := float(cfg.get("base_annual", 0.012))
		if age >= int(cfg.get("from_age", 58)):
			var t := clampf(float(age - int(cfg.get("from_age", 58))) / 22.0, 0.0, 1.5)
			annual = lerpf(float(cfg.get("annual_at_58", 0.05)), float(cfg.get("annual_at_80", 0.28)), t)
		annual *= c.mortality()
		if age > int(cfg.get("max_age", 92)):
			annual = 999.0
		# the king who lives on the map dies with his person
		if c.person >= 0 and world.person(c.person) == null:
			_die(session, k, c, day, "è spirato")
			continue
		if rng.randf() < annual / 360.0 * MEASURE_SPREAD:
			_die(session, k, c, day, "è morto di vecchiaia" if age >= int(cfg.get("from_age", 58)) else "è morto")


static func _die(session: GameSession, k: KingdomState, c: CharacterState, day: int, cause: String) -> void:
	var world := session.world
	c.death_day = day
	var p: PersonState = world.person(c.person) if c.person >= 0 else null
	if p:
		world.remove_person(p.id)
		SettlementSim.mark_assignment_dirty(session, p.settlement)
	if k.ruler == c.id:
		if k.is_player:   # the courts of the world are news for the chronicle, not for the player
			EventBus.notify("Il sovrano è morto", "%s %s a %d anni." % [c.name, cause, c.age_years(day)], &"court")
		EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "ruler_died",
			"text": "%s %s dopo un regno di %d anni." % [c.name, cause, maxi(c.age_years(day) - 20, 0)]})
		succeed(session, k, day)
	EventBus.settlement_changed.emit(0)


## A century of courts is a crowd of ghosts: whoever has been dead for a generation leaves the register.
static func _forget_the_long_dead(world: WorldState, day: int) -> void:
	if day % 360 != 0 or world.characters.size() < 60:
		return
	var keep := {}
	for k in world.kingdoms:
		var ruler := world.character(k.ruler)
		if ruler:
			keep[ruler.id] = true
			keep[ruler.parent] = true
			keep[ruler.consort] = true
		keep[k.heir_designate] = true
	var gone: Array[int] = []
	for c: CharacterState in world.characters.values():
		if c.alive() or keep.has(c.id):
			continue
		if day - c.death_day > 20 * PersonState.DAYS_PER_YEAR:
			gone.append(c.id)
	for id_value in gone:
		world.characters.erase(id_value)


# --- succession -----------------------------------------------------------------------------------------

## Who inherits, following the law in force. Returns null when nobody can.
static func heir_of(world: WorldState, k: KingdomState) -> CharacterState:
	var designated := world.character(k.heir_designate)
	if designated and designated.alive():
		return designated
	var ruler := world.character(k.ruler)
	var law := StringName(k.laws.get(&"succession", &"primogeniture"))
	var candidates: Array[CharacterState] = []
	if ruler:
		for child_id in ruler.children:
			var c := world.character(child_id)
			if c and c.alive():
				candidates.append(c)
	if candidates.is_empty():
		# no children: the house looks for anybody of its blood in the realm
		for c: CharacterState in world.characters.values():
			if c.kingdom == k.id and c.alive() and c.house == k.house and (ruler == null or c.id != ruler.id):
				candidates.append(c)
	if candidates.is_empty():
		return null
	match law:
		&"seniority":
			candidates.sort_custom(func(a: CharacterState, b: CharacterState) -> bool: return a.birth_day < b.birth_day)
		&"elective":
			# the great of the realm prefer the most capable adult
			candidates.sort_custom(func(a: CharacterState, b: CharacterState) -> bool:
				var aa := a.skill(&"governo") + a.skill(&"diplomazia") + (10 if a.age_years(world.day) >= 16 else -20)
				var bb := b.skill(&"governo") + b.skill(&"diplomazia") + (10 if b.age_years(world.day) >= 16 else -20)
				return aa > bb)
		_:
			candidates.sort_custom(func(a: CharacterState, b: CharacterState) -> bool: return a.birth_day < b.birth_day)
	return candidates[0]


## Crowns the heir (or opens a dynastic crisis when there is none).
static func succeed(session: GameSession, k: KingdomState, day: int) -> void:
	var world := session.world
	var court: Dictionary = bal().get("court", {})
	var heir := heir_of(world, k)
	if heir == null:
		# a distant cousin is called in: a new branch, and a shaken realm
		var rng := world.rng.stream(&"court")
		var cousin := _make_character(session, k, rng.randi_range(18, 40), rng.randf() < 0.3, rng)
		cousin.house = k.house
		k.ruler = cousin.id
		k.heir_designate = -1
		k.records[&"rulers_crowned"] = float(k.records.get(&"rulers_crowned", 0.0)) + 1.0
		k.regency = false
		k.legitimacy = maxf(k.legitimacy - 25.0, 5.0)
		k.turbulence += float(court.get("crisis_turbulence", 20.0))
		k.identity_changed()
		_ensure_king_person(session, k, cousin)
		if k.is_player:   # the courts of the world are news for the chronicle, not for the player
			EventBus.notify("Crisi dinastica", "Nessun erede: %s di %s viene chiamato al trono." % [cousin.name, cousin.house], &"court")
		EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "succession_crisis",
			"text": "Senza eredi, la corona passa a %s." % cousin.name})
		return
	k.ruler = heir.id
	k.heir_designate = -1
	k.records[&"rulers_crowned"] = float(k.records.get(&"rulers_crowned", 0.0)) + 1.0
	k.identity_changed()
	var age := heir.age_years(day)
	k.regency = age < int(court.get("adult_age", 16))
	if k.regency:
		k.legitimacy = maxf(k.legitimacy + float(court.get("regency_legitimacy", -10.0)), 5.0)
		k.turbulence += float(court.get("minor_turbulence", 12.0))
		if k.is_player:   # the courts of the world are news for the chronicle, not for the player
			EventBus.notify("Una reggenza", "%s ha %d anni: il regno è retto in suo nome." % [heir.name, age], &"court")
	else:
		if k.is_player:   # the courts of the world are news for the chronicle, not for the player
			EventBus.notify("Un nuovo sovrano", "%s di %s cinge la corona a %d anni." % [heir.name, heir.house, age], &"court")
	EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "succession",
		"text": "%s succede al trono%s." % [heir.name, " sotto reggenza" if k.regency else ""]})
	_ensure_king_person(session, k, heir)


## The new ruler of the player's realm takes his place in the keep.
static func _ensure_king_person(session: GameSession, k: KingdomState, ruler: CharacterState) -> void:
	var world := session.world
	var settlement: SettlementState = null
	for s in world.settlements:
		if s.kingdom == k.id:
			settlement = s
			break
	if settlement == null:
		return
	for p in world.people_of(settlement.id):
		p.is_king = p.id == ruler.person
	if ruler.person >= 0 and world.person(ruler.person):
		var p := world.person(ruler.person)
		p.is_king = true
		p.job = &"king"
		return
	var keep: BuildingState = null
	for b in world.buildings_of(settlement.id):
		if b.is_active() and b.beds() > 0:
			keep = b
			break
	var p := PersonState.new()
	p.id = world.new_id()
	p.name = ruler.name
	p.female = ruler.female
	p.birth_day = ruler.birth_day
	p.culture = k.culture
	p.religion = k.religion
	p.settlement = settlement.id
	p.is_king = true
	p.job = &"king"
	p.home = keep.id if keep else -1
	p.seg_from = settlement.center
	p.seg_to = settlement.center
	world.add_person(p)
	ruler.person = p.id
	SettlementSim.mark_assignment_dirty(session, settlement.id)


# --- family, favour and measures --------------------------------------------------------------------------

func _family_life(session: GameSession, k: KingdomState, day: int) -> void:
	var world := session.world
	var court: Dictionary = bal().get("court", {})
	var rng := world.rng.stream(&"court")
	var ruler := world.ruler_of(k.id)
	if ruler == null:
		return
	if ruler.person >= 0:
		return   # a royal family that lives in the village marries and has children there (FamilySystem, PopulationSystem)
	var consort := world.character(ruler.consort)
	if (consort == null or not consort.alive()) and ruler.age_years(day) >= 16 and rng.randf() < float(court.get("marriage_chance_per_year", 0.5)):
		var new_consort := _make_character(session, k, maxi(ruler.age_years(day) + rng.randi_range(-5, 5), 16), not ruler.female, rng)
		ruler.consort = new_consort.id
		new_consort.consort = ruler.id
		if k.is_player:   # the courts of the world are news for the chronicle, not for the player
			EventBus.notify("Nozze a corte", "%s sposa %s." % [ruler.name, new_consort.name], &"court")
		return
	if consort and consort.alive() and ruler.children.size() < int(court.get("max_children", 6)):
		var fertile := mini(ruler.age_years(day), consort.age_years(day)) < 45
		if fertile and rng.randf() < float(court.get("birth_chance_per_year", 0.35)):
			var child := _make_character(session, k, 0, rng.randf() < 0.5, rng, ruler)
			child.parent = ruler.id
			ruler.children.append(child.id)
			if k.is_player:   # the courts of the world are news for the chronicle, not for the player
				EventBus.notify("Un erede", "A corte è nato %s." % child.name, &"court")


func _favour(session: GameSession, k: KingdomState) -> void:
	var world := session.world
	var cfg: Dictionary = bal().get("factions", {})
	var ruler := world.ruler_of(k.id)
	var trait_bonus := {}
	if ruler:
		for td in ruler.trait_defs():
			for f: StringName in td.factions.keys():
				trait_bonus[f] = float(trait_bonus.get(f, 0.0)) + float(td.factions[f])
	var trust := 0.0
	var settlements := 0
	for s in world.settlements:
		if s.kingdom == k.id:
			trust += s.trust
			settlements += 1
	trust = trust / maxf(float(settlements), 1.0) if settlements > 0 else 55.0
	for f: FactionDef in factions():
		var target := float(cfg.get("start_favour", 55.0)) + float(trait_bonus.get(f.id, 0.0))
		target += (trust - 55.0) * float(cfg.get("trust_weight", 0.35)) * (1.5 if f.id == &"people" else 0.6)
		if k.treasury < 0.0:
			target += float(cfg.get("wage_debt_penalty", -12.0)) * (1.5 if f.id == &"army" else 0.6)
		target += float(k.favour.get(StringName("_law_bias_%s" % f.id), 0.0))
		# contentment has diminishing returns: a power can be very pleased, not pinned at the top for decades
		var soft := float(cfg.get("saturate_above", 75.0))
		if target > soft:
			target = soft + (target - soft) * float(cfg.get("saturation", 0.5))
		k.favour[f.id] = move_toward(float(k.favour.get(f.id, 55.0)), clampf(target, 0.0, 100.0),
			float(cfg.get("drift_per_day", 0.08)) * MEASURE_SPREAD)


func _measures(session: GameSession, k: KingdomState) -> void:
	var world := session.world
	var leg: Dictionary = bal().get("legitimacy", {})
	var ord_cfg: Dictionary = bal().get("stability", {})
	var stack := KingdomModifiers.stack(session, k.id)
	var ruler := world.ruler_of(k.id)
	var lp := {"Base": float(leg.get("base", 50.0))}
	lp["Leggi, fede e spiriti"] = stack.additive(&"legitimacy.base")
	var heir := heir_of(world, k)
	if heir and heir.age_years(world.day) >= 16:
		lp["Un erede adulto"] = float(leg.get("adult_heir", 15.0))
	elif heir == null:
		lp["Nessun erede"] = float(leg.get("no_heir", -12.0))
	if ruler:
		var age := ruler.age_years(world.day)
		if age < 16:
			lp["Un sovrano bambino"] = float(leg.get("child_ruler", -20.0))
		elif age > int(leg.get("old_age", 65)):
			lp["Un sovrano anziano"] = float(leg.get("old_ruler", -6.0))
	var hostile := 0
	for f: FactionDef in factions():
		if float(k.favour.get(f.id, 55.0)) < float(leg.get("hostile_below", 30.0)):
			hostile += 1
	if hostile > 0:
		lp["Poteri ostili (%d)" % hostile] = float(leg.get("hostile_faction", -10.0)) * hostile
	var clergy := (float(k.favour.get(&"clergy", 55.0)) - 55.0) * float(leg.get("clergy_weight", 0.12)) * stack.multiplier(&"legitimacy.from_clergy")
	lp["Il favore del clero"] = clergy
	var target := 0.0
	for key: String in lp.keys():
		target += float(lp[key])
	lp["_target"] = clampf(target, 0.0, 100.0)
	k.legitimacy = lerpf(k.legitimacy, clampf(target, 0.0, 100.0),
		clampf(float(leg.get("chase_per_day", 0.12)) * MEASURE_SPREAD, 0.0, 1.0))

	k.turbulence = maxf(k.turbulence - float(ord_cfg.get("turbulence_decay_per_day", 0.35)) * MEASURE_SPREAD, 0.0)
	var discontent := 0.0
	for f: FactionDef in factions():
		discontent += maxf(55.0 - float(k.favour.get(f.id, 55.0)), 0.0) * f.weight
	var unrest := 0.0
	for pid in k.provinces:
		var p := world.province(pid)
		if p:
			unrest += p.unrest
	unrest = unrest / maxf(float(k.provinces.size()), 1.0)
	var op := {"Base": float(ord_cfg.get("base", 100.0))}
	op["Leggi, fede e spiriti"] = stack.additive(&"stability.base")
	op["Poteri scontenti"] = -discontent * float(ord_cfg.get("faction_discontent_weight", 0.5))
	op["Disordini nelle province"] = -unrest * float(ord_cfg.get("unrest_weight", 12.0))
	op["Turbolenza recente"] = -k.turbulence
	# the reach of the crown: every land beyond the first few is a little further from its justice
	var reach := maxf(float(k.provinces.size() - int(ord_cfg.get("provinces_free", 5))), 0.0) * float(ord_cfg.get("per_province", 0.4))
	op["Terre lontane dalla corona"] = -reach
	var order_target := 0.0
	for key: String in op.keys():
		order_target += float(op[key])
	op["_target"] = clampf(order_target, 0.0, 100.0)
	k.stability = lerpf(k.stability, clampf(order_target, 0.0, 100.0),
		clampf(float(ord_cfg.get("chase_per_day", 0.12)) * MEASURE_SPREAD, 0.0, 1.0))

	var pr: Dictionary = bal().get("prestige", {})
	var buildings := 0
	for s in world.settlements:
		if s.kingdom == k.id:
			buildings += world.buildings_of(s.id).size()
	# prestige is what the realm is (lands, buildings, a believed crown) and what it has done (battles won,
	# lands taken, relics bought — remembered, slowly forgotten). It nears 100 and never sits on it (Phase 16:
	# it was rebuilt from scratch every week, so every deed vanished the next day, and it grew without limit)
	var structural := float(pr.get("per_province", 1.5)) * k.provinces.size() \
		+ float(pr.get("per_building", 0.25)) * buildings + float(pr.get("per_legitimacy", 0.2)) * k.legitimacy * 0.1
	var deeds := float(k.records.get(PRESTIGE_DEEDS, 0.0))
	deeds *= 1.0 - float(pr.get("deeds_fade_per_year", 0.05)) * MEASURE_SPREAD / float(PersonState.DAYS_PER_YEAR)
	k.records[PRESTIGE_DEEDS] = deeds
	k.prestige = prestige_value(structural + deeds)
	k.measure_parts = {"legitimacy": lp, "stability": op, "prestige": {
		"Terre": float(pr.get("per_province", 1.5)) * k.provinces.size(),
		"Edifici": float(pr.get("per_building", 0.25)) * buildings,
		"Una corona creduta": float(pr.get("per_legitimacy", 0.2)) * k.legitimacy * 0.1,
		"Imprese ricordate": deeds}}


const PRESTIGE_DEEDS := &"prestige_deeds"


## 0..100 from the raw sum: a small realm moves fast, a great one fights for every point.
static func prestige_value(raw: float) -> float:
	var scale := float(bal().get("prestige", {}).get("scale", 70.0))
	return clampf(100.0 * (1.0 - exp(-maxf(raw, 0.0) / maxf(scale, 1.0))), 0.0, 99.5)


## A deed that adds (or takes) prestige: remembered in the deeds, felt at once.
static func add_prestige(k: KingdomState, amount: float) -> void:
	if k == null:
		return
	k.records[PRESTIGE_DEEDS] = float(k.records.get(PRESTIGE_DEEDS, 0.0)) + amount
	k.prestige = clampf(k.prestige + amount * 0.5, 0.0, 99.5)


# --- marriages between crowns (Phase 8) ------------------------------------------------------------------

## A child of the house old enough to marry and still free, or -1.
static func marriageable(world: WorldState, kingdom_id: int) -> int:
	var k := world.kingdom(kingdom_id)
	var ruler := world.ruler_of(kingdom_id)
	if k == null:
		return -1
	var best := -1
	for c: CharacterState in world.characters.values():
		if c.kingdom != kingdom_id or not c.alive() or c.consort >= 0:
			continue
		if ruler and c.id == ruler.id:
			continue
		if c.age_years(world.day) < 14:
			continue
		if best < 0 or world.character(best).age_years(world.day) < c.age_years(world.day):
			best = c.id
	return best


## Ties the two houses: a child of each marries the other, and keeps living at his own court.
static func marry_houses(session: GameSession, kingdom_a: int, kingdom_b: int) -> void:
	var world := session.world
	var one := world.character(marriageable(world, kingdom_a))
	var two := world.character(marriageable(world, kingdom_b))
	if one == null or two == null:
		return
	one.consort = two.id
	two.consort = one.id
	if one.female == two.female:
		two.female = not one.female


# --- the monarchy of the player (Phase 15) ------------------------------------------------------------------
# The game starts with six founders and no crown. When the community is a village the player chooses one of its
# families as the royal house and one of its members as the first sovereign; from then on everything above —
# succession, heirs, legitimacy, the powers of the realm — runs as for any other kingdom.

static func families_bal() -> Dictionary:
	return Defs.balance("families")


## Every condition of the monarchy with its state, in the order the player reads them:
## [{label, ok, value}]. A village, stable, fed, with families that have taken root and a community able to
## decide together.
static func monarchy_conditions(session: GameSession, k: KingdomState) -> Array[Dictionary]:
	var world := session.world
	var out: Array[Dictionary] = []
	var cfg: Dictionary = families_bal().get("monarchy", {})
	var home := _home_settlement(world, k)
	if home == null:
		return out
	var people := world.people_of(home.id).size()
	var needed := int(cfg.get("min_people", 30))
	out.append({"label": "Un villaggio", "ok": people >= needed, "value": "%d abitanti su %d" % [people, needed]})
	var trust := home.trust
	var min_trust := float(cfg.get("min_trust", 45.0))
	var hungry := false
	for p in world.people_of(home.id):
		if p.hunger > 1.0:
			hungry = true
			break
	out.append({"label": "Un villaggio stabile", "ok": trust >= min_trust and not hungry,
		"value": "fiducia %d su %d%s" % [roundi(trust), roundi(min_trust), " · qualcuno salta i pasti" if hungry else ""]})
	# the stores must feed everybody for a while and reach the next harvest: a village whose granary sends
	# people away is not an economy that holds
	var outlook := PopulationSystem.harvest_outlook(session, home)
	var food := float(outlook["food_days"])
	var min_food := float(cfg.get("min_food_days", 60.0))
	var short := bool(outlook["short"])
	out.append({"label": "Un'economia che regge", "ok": food >= min_food and not short and k.treasury >= 0.0,
		"value": "cibo per %d giorni su %d%s%s" % [roundi(food), roundi(min_food),
			" · non arriva al raccolto" if short else "", " · cassa in debito" if k.treasury < 0.0 else ""]})
	var rooted := FamilySystem.consolidated_families(world, home).size()
	var min_fam := int(cfg.get("min_families", 2))
	out.append({"label": "Famiglie radicate", "ok": rooted >= min_fam,
		"value": "%d famiglie con almeno %d membri, ne servono %d" % [rooted, int(cfg.get("family_min_members", 3)), min_fam]})
	var min_auth := float(cfg.get("min_authority", 50.0))
	out.append({"label": "Una comunità che decide", "ok": k.authority >= min_auth,
		"value": "autorità %d su %d" % [roundi(k.authority), roundi(min_auth)]})
	var years := (world.day - k.founded_day) / PersonState.DAYS_PER_YEAR
	var min_years := int(cfg.get("min_years", 2))
	out.append({"label": "Anni insieme", "ok": years >= min_years, "value": "%d anni su %d" % [years, min_years]})
	return out


## Why the monarchy cannot be founded yet ("" when it can): the first condition still missing.
static func monarchy_blocker(session: GameSession, k: KingdomState) -> String:
	var world := session.world
	if k == null:
		return "Nessuna comunità."
	if k.monarchy_founded:
		return "La monarchia è già stata fondata."
	if _home_settlement(world, k) == null:
		return "La comunità non ha un insediamento."
	for c in monarchy_conditions(session, k):
		if not bool(c["ok"]):
			return "Manca ancora: %s (%s)." % [String(c["label"]).to_lower(), String(c["value"])]
	return ""


## The adults of a family who could wear the crown, the eldest first.
static func eligible_rulers(world: WorldState, f: FamilyState) -> Array[PersonState]:
	var out: Array[PersonState] = []
	var min_age := int(families_bal().get("monarchy", {}).get("ruler_min_age", 18))
	for p in world.members_of(f.id):
		if p.settlement >= 0 and p.job != &"soldier" and p.age_years(world.day) >= min_age:
			out.append(p)
	out.sort_custom(func(a: PersonState, b: PersonState) -> bool: return a.birth_day < b.birth_day)
	return out


## Where a family comes from, read in its register: a clear majority of days in the fields, in the workshops or
## under arms makes it a house of farmers, craftsmen or men of arms; a founding family that did a bit of
## everything is "the most esteemed" — the elders of the community.
static func origin_of(world: WorldState, f: FamilyState) -> StringName:
	var groups: Dictionary = families_bal().get("origin_jobs", {})
	var total := 0.0
	var best := &""
	var best_days := 0.0
	for origin: String in groups.keys():
		var days := 0.0
		for job: String in groups[origin]:
			days += float(f.records.get(StringName(job), 0.0))
		total += days
		if days > best_days:
			best_days = days
			best = StringName(origin)
	if total > 0.0 and best_days / total >= 0.45:
		return best
	if f.founding:
		return &"esteemed"
	return best if best != &"" else &"esteemed"


## The family of the community that became the royal house. Saves from before the consolidation did not keep it:
## it is found again from the person who wears the crown, or from the name of the house, and remembered.
static func royal_family_of(world: WorldState, k: KingdomState) -> FamilyState:
	if k == null or not k.monarchy_founded:
		return null
	if k.royal_family >= 0:
		return world.family(k.royal_family)
	for p: PersonState in world.people.values():
		if p.is_king and p.family >= 0:
			var s := world.settlement(p.settlement)
			if s and s.kingdom == k.id and world.family(p.family) != null:
				k.royal_family = p.family
				return world.family(p.family)
	var ids := world.families.keys()
	ids.sort()
	for fid: int in ids:
		var f: FamilyState = world.families[fid]
		if "Casa %s" % f.name == k.house:
			k.royal_family = f.id
			return f
	return null


static func origin_def(origin: StringName) -> Dictionary:
	var d: Variant = Defs.read_json("res://data/defs/house_origins.json")
	if d is Dictionary:
		for o: Dictionary in (d as Dictionary).get("origins", []):
			if StringName(o.get("id", "")) == origin:
				return o
	return {}


## The great decision: the family becomes the royal house, the person the first sovereign. Laws, powers and
## measures start as for any kingdom; the origin of the house moves them a little; the chronicle writes it down.
static func found_monarchy(session: GameSession, k: KingdomState, f: FamilyState, p: PersonState) -> CharacterState:
	var world := session.world
	var day := world.day
	for g: Dictionary in Laws.groups():
		var def_opt := Laws.default_option(StringName(g["id"]))
		if def_opt != &"":
			k.laws[StringName(g["id"])] = def_opt
	for fd: FactionDef in factions():
		k.favour[fd.id] = float(bal().get("factions", {}).get("start_favour", 55.0))
	k.legitimacy = float(bal().get("legitimacy", {}).get("start", 65.0))
	k.stability = float(bal().get("stability", {}).get("start", 80.0))
	k.prestige = float(bal().get("prestige", {}).get("start", 10.0))
	# the authority the community earned before the crown is the first legitimacy of the house, and a part of the
	# first stability of the realm: a community that already decides together is born steadier (consolidation —
	# the authority is a measure of the community only, it does not live on as a fifth measure of the crown)
	var monarchy_cfg: Dictionary = families_bal().get("monarchy", {})
	k.legitimacy = clampf(lerpf(k.legitimacy, k.authority, float(monarchy_cfg.get("legitimacy_from_authority", 0.6))), 25.0, 90.0)
	k.stability = clampf(lerpf(k.stability, k.authority, float(monarchy_cfg.get("stability_from_authority", 0.3))), 25.0, 95.0)
	# where the house comes from: a moderate push on the powers, and modifiers that live in the realm stack
	k.house_origin = origin_of(world, f)
	var origin := origin_def(k.house_origin)
	var bonus: Dictionary = origin.get("favour", {})
	for fid: String in bonus.keys():
		k.favour[StringName(fid)] = clampf(float(k.favour.get(StringName(fid), 55.0)) + float(bonus[fid]), 0.0, 100.0)
	k.house = "Casa %s" % f.name
	k.royal_family = f.id
	k.coat_of_arms = CoatOfArms.generate(k.house, k.culture, k.color)
	var ruler := _character_from_person(session, k, p)
	k.ruler = ruler.id
	k.heir_designate = -1
	k.regency = false
	p.is_king = true
	p.job = &"king"
	p.workplace = -1
	var spouse: PersonState = world.person(p.spouse) if p.spouse >= 0 else null
	if spouse:
		var consort := _character_from_person(session, k, spouse)
		ruler.consort = consort.id
		consort.consort = ruler.id
	for other: PersonState in world.people.values():
		if other.mother == p.id or other.father == p.id:
			var cc := _character_from_person(session, k, other, ruler)
			cc.parent = ruler.id
			ruler.children.append(cc.id)
	var home := _home_settlement(world, k)
	var place := home.name if home else k.name
	if home:
		_raise_royal_seat(session, k, home, p, f)
	var start_cfg: Variant = Defs.read_json("res://data/defs/start_setup.json")
	var realm_name := "Regno di {province}"
	if start_cfg is Dictionary:
		realm_name = String(((start_cfg as Dictionary).get("player", {}) as Dictionary).get("kingdom_name", realm_name))
	k.name = realm_name.format({"province": place})
	k.monarchy_founded = true
	k.rank = KingdomState.Rank.KINGDOM
	k.crowned_day = day
	k.records[&"rulers_crowned"] = float(k.records.get(&"rulers_crowned", 0.0)) + 1.0
	k.identity_changed()
	var title := "Regina" if p.female else "Re"
	EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "founding_royal_house",
		"text": "La Casa %s viene scelta dalle famiglie di %s. %s" % [f.name, place, String(origin.get("text", ""))]})
	EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "founding_crown",
		"text": "%s %s viene %s %s." % [p.name, f.name, "incoronata prima" if p.female else "incoronato primo", title]})
	EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "founding_realm",
		"text": "Nasce il %s." % k.name})
	EventBus.notify("Nasce il %s" % k.name, "%s %s cinge la corona: la Casa %s regna." % [p.name, f.name, f.name], &"court")
	if home:
		SettlementSim.mark_assignment_dirty(session, home.id)
		EventBus.settlement_changed.emit(home.id)
	return ruler


## The families raise the keep of the royal house by the common fire, and the sovereign goes to live in it: the
## capital has a centre you can see (Phase 18 audit: after the crowning the capital was a grid of farms with
## no seat of the crown anywhere).
static func _raise_royal_seat(session: GameSession, k: KingdomState, home: SettlementState, ruler_person: PersonState,
		f: FamilyState) -> void:
	var world := session.world
	for b in world.buildings_of(home.id):
		if b.def_id == &"keep":
			return
	var spot := SettlementPlanner.find_spot(session, home.id, &"keep", home.center, 14.0, true, 220.0, true)
	if spot == Vector2.INF:
		return
	var keep := SettlementSetup._add_building(world, home, &"keep", spot)
	for t in LocalFeatures.trees_in_rect(SettlementSim.ground(session.world), keep.rect().grow(1.0)):
		world.terrain.fell(t, world.day, true)
	ruler_person.home = keep.id
	var spouse := world.person(ruler_person.spouse) if ruler_person.spouse >= 0 else null
	if spouse:
		spouse.home = keep.id
	EventBus.building_completed.emit(keep.id)
	EventBus.chronicle_written.emit({"day": world.day, "kingdom": k.id, "kind": "founding_seat",
		"text": "Le famiglie di %s alzano il mastio della Casa %s accanto al fuoco comune: la corona ha una casa." % [home.name, f.name]})


## A character of the court made from somebody who lives in the village: same name, same age, same person.
static func _character_from_person(session: GameSession, k: KingdomState, p: PersonState,
		parent: CharacterState = null) -> CharacterState:
	var world := session.world
	var rng := world.rng.stream(&"court")
	var court: Dictionary = bal().get("court", {})
	var c := CharacterState.new()
	c.id = world.new_id()
	c.name = p.name
	c.house = k.house
	c.female = p.female
	c.birth_day = p.birth_day
	c.kingdom = k.id
	c.person = p.id
	pick_traits(c, rng, parent)
	var sk: Array = court.get("skill_range", [2, 9])
	for key: StringName in [&"governo", &"guerra", &"diplomazia", &"intrigo"]:
		c.skills[key] = rng.randi_range(int(sk[0]), int(sk[1]))
	world.characters[c.id] = c
	return c


static func _home_settlement(world: WorldState, k: KingdomState) -> SettlementState:
	for s in world.settlements:
		if s.kingdom == k.id:
			return s
	return null


## A ruler of the village marries in the village: the spouse becomes the consort at court.
static func on_village_union(session: GameSession, k: KingdomState, man: PersonState, woman: PersonState) -> void:
	var world := session.world
	var ruler := world.ruler_of(k.id)
	if ruler == null or ruler.person < 0:
		return
	var other: PersonState = null
	if man.id == ruler.person:
		other = woman
	elif woman.id == ruler.person:
		other = man
	if other == null:
		return
	var consort := _character_from_person(session, k, other)
	ruler.consort = consort.id
	consort.consort = ruler.id
	EventBus.notify("Nozze a corte", "%s sposa %s." % [ruler.name, other.name], &"court")


## A child of the royal couple born in the village is an heir of the house: a character of the court.
static func on_village_birth(session: GameSession, k: KingdomState, child: PersonState, mother: PersonState, father: PersonState) -> void:
	var world := session.world
	var ruler := world.ruler_of(k.id)
	if ruler == null or ruler.person < 0:
		return
	if mother.id != ruler.person and father.id != ruler.person:
		return
	var c := _character_from_person(session, k, child, ruler)
	c.parent = ruler.id
	ruler.children.append(c.id)
	EventBus.notify("Un erede", "Alla %s è nato %s." % [k.house, child.name], &"court")

