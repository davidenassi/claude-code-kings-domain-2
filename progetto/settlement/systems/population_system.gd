class_name PopulationSystem
extends SimSystem
## Every day: children grow up, babies are born, people die of age, hunger or misery, travellers arrive,
## and the trust of the inhabitants (Fiducia) is recomputed from real facts: food in store, beds, hunger,
## services, recent deaths, crown debt. Rules in data/defs/balance/population.json.


func _init() -> void:
	id = &"population"
	frequency = Frequency.DAY
	order = 25


static func bal() -> Dictionary:
	return Defs.balance("population")


## Days the stores can feed the settlement. Grain is worth bread only as far as the ovens, with the bakers that
## really work in them, can bake it in the days it has to last; the rest is eaten as it is, for much less.
## (Phase 16: counting every grain as baked showed 230 days of food in a village of fifty with one oven, that
## really had a hundred — and starved before the next harvest with the granary apparently full.)
static func food_days(world: WorldState, s: SettlementState) -> float:
	var people := world.people_of(s.id).size()
	if people <= 0:
		return 99.0
	var per_day := float(Defs.balance("settlement").get("food_per_person_day", 0.25)) * people
	var ovens := _ovens(world, s)
	var ready := 0.0
	for res: StringName in s.stock.keys():
		var rd := Defs.resource(res)
		if rd and rd.is_food and not ovens.has(res):
			ready += float(s.stock[res]) * rd.food_value
	var days := ready / maxf(per_day, 0.0001)
	for res: StringName in ovens.keys():
		var rd := Defs.resource(res)
		var amount := float(s.amount(res))
		var raw := rd.food_value
		var baked := float(ovens[res]["value"])
		var per_day_baked := float(ovens[res]["per_day"])
		var all_baked := (ready + amount * baked) / maxf(per_day, 0.0001)
		var gain := per_day_baked * (baked - raw)
		if per_day_baked * all_baked >= amount or gain >= per_day:
			days = all_baked
		else:
			# the ovens bake what they can each day, the rest of the grain is eaten raw
			days = (ready + amount * raw) / maxf(per_day - gain, 0.0001)
		ready = days * per_day
	return days


## The food goods the manned ovens turn into something better: res -> {value: food per unit once baked,
## per_day: units a day the ovens can take with the workers they really have}.
static func _ovens(world: WorldState, s: SettlementState) -> Dictionary:
	var out := {}
	var factors := _food_factors(world, s)
	if factors.is_empty():
		return out
	var hands := {}
	for p in world.people_of(s.id):
		if p.workplace >= 0:
			hands[p.workplace] = int(hands.get(p.workplace, 0)) + 1
	var hours := SettlementAggregate.work_hours(null)
	for b in world.buildings_of(s.id):
		if not b.is_active() or int(hands.get(b.id, 0)) <= 0:
			continue
		var work: Dictionary = b.def().work
		if String(work.get("type", "")) != "convert":
			continue
		var cycles := floorf(hours * int(hands[b.id]) / maxf(float(work.get("hours", 8.0)), 0.1))
		for res_name: String in (work.get("input", {}) as Dictionary).keys():
			var res := StringName(res_name)
			if not factors.has(res):
				continue
			var entry: Dictionary = out.get(res, {"value": float(factors[res]), "per_day": 0.0})
			entry["per_day"] = float(entry["per_day"]) + cycles * float(work["input"][res_name])
			out[res] = entry
	return out


## Food value of a stored good, raised by what the workshops of the settlement can turn it into (grain into
## bread). Only counts ovens that are standing and manned.
static func _food_factors(world: WorldState, s: SettlementState) -> Dictionary:
	var out := {}
	for b in world.buildings_of(s.id):
		if not b.is_active() or b.workers_wanted <= 0:
			continue
		var work: Dictionary = b.def().work
		if String(work.get("type", "")) != "convert":
			continue
		var input: Dictionary = work.get("input", {})
		var output: Dictionary = work.get("output", {})
		var out_value := 0.0
		for res: String in output.keys():
			var rd := Defs.resource(StringName(res))
			if rd and rd.is_food:
				out_value += float(output[res]) * rd.food_value
		if out_value <= 0.0:
			continue
		var in_units := 0.0
		for res: String in input.keys():
			in_units += float(input[res])
		for res: String in input.keys():
			var rd := Defs.resource(StringName(res))
			if rd == null or not rd.is_food or in_units <= 0.0:
				continue
			var per_unit := out_value / in_units
			if per_unit > float(out.get(StringName(res), rd.food_value)):
				out[StringName(res)] = per_unit
	return out


static func free_beds(world: WorldState, s: SettlementState) -> int:
	var beds := 0
	for b in world.buildings_of(s.id):
		if b.is_active():
			beds += b.def().beds
	return beds - world.people_of(s.id).size()


## Share of the homes that have a service (a well, a chapel, a bakery…) within its reach.
static func service_coverage(world: WorldState, s: SettlementState) -> float:
	var services: Array[BuildingState] = []
	var homes: Array[BuildingState] = []
	for b in world.buildings_of(s.id):
		if not b.is_active():
			continue
		if b.def().service_radius_m > 0.0:
			services.append(b)
		if b.def().beds > 0:
			homes.append(b)
	if homes.is_empty() or services.is_empty():
		return 0.0
	var served := 0
	for b in homes:
		for w in services:
			if w.pos.distance_to(b.pos) <= w.def().service_radius_m:
				served += 1
				break
	return float(served) / float(homes.size())


func run(session: GameSession, step: SimStep) -> void:
	var world := session.world
	for s in world.settlements:
		_grow_up(world, s, step.day)
		_deaths(session, s, step.day)
		_births(session, s, step.day)
		if step.is_new_year:
			s.left_this_year = 0
		if step.is_new_month:
			_travellers(session, s, step.day)
		_emigration(session, s, step.day)
		_trust(session, s, step.day)
		_sync_province(world, s)


func _grow_up(world: WorldState, s: SettlementState, day: int) -> void:
	var adult := int(bal().get("adult_age", 16))
	for p in world.people_of(s.id):
		if p.job == &"child" and p.age_years(day) >= adult:
			p.job = &"idle"
			EventBus.settlement_changed.emit(s.id)


func _deaths(session: GameSession, s: SettlementState, day: int) -> void:
	var world := session.world
	var cfg: Dictionary = bal()["death"]
	var rng := world.rng.stream(&"population")
	# the rules read once for the day, not once per person (Rebirth check: a large village spent a good part of its
	# day looking the same numbers up in the balance tables)
	var adult_annual := float(cfg.get("adult_annual", 0.012))
	var child_annual := float(cfg.get("child_annual", 0.02))
	var adult_age := int(bal().get("adult_age", 16))
	var elder_age := int(bal().get("elder_age", 62))
	var elder_62 := float(cfg.get("elder_annual_at_62", 0.06))
	var elder_80 := float(cfg.get("elder_annual_at_80", 0.22))
	var starve_days := float(cfg.get("starvation_days", 12.0))
	var starve_daily := float(cfg.get("starvation_daily", 0.02))
	var misery := float(cfg.get("misery_daily", 0.002)) if s.trust < float(cfg.get("misery_trust", 20.0)) else 0.0
	var max_age := int(bal().get("max_age", 92))
	for p in world.people_of(s.id):
		var age := p.age_years(day)
		var annual := adult_annual
		if age < adult_age:
			annual = child_annual
		elif age >= elder_age:
			annual = lerpf(elder_62, elder_80, clampf(float(age - elder_age) / 18.0, 0.0, 1.6))
		var chance := annual / 360.0
		if p.hunger > starve_days:
			chance += starve_daily * clampf((p.hunger - starve_days) / 10.0, 0.2, 2.0)
		chance += misery
		if age > max_age:
			chance = 1.0
		if rng.randf() < chance:
			_die(session, s, p, day)


func _die(session: GameSession, s: SettlementState, p: PersonState, day: int) -> void:
	var world := session.world
	for key: String in s.reserved.keys():
		if int(s.reserved[key]) == p.id:
			s.reserved.erase(key)
	world.remove_person(p.id)
	s.recent_deaths.append(day)
	var cause := "di stenti" if p.hunger > 6.0 else ("di vecchiaia" if p.age_years(day) >= int(bal().get("elder_age", 62)) else "di malattia")
	EventBus.notify_local("Un lutto a %s" % s.name, "%s è morto %s a %d anni." % [p.name, cause, p.age_years(day)], &"death", p.seg_to)
	SettlementSim.mark_assignment_dirty(session, s.id)
	EventBus.settlement_changed.emit(s.id)


func _births(session: GameSession, s: SettlementState, day: int) -> void:
	var world := session.world
	var cfg: Dictionary = bal()["birth"]
	if s.trust < float(cfg.get("min_trust", 42.0)):
		return
	var days_of_food := food_days(world, s)
	if days_of_food < float(cfg.get("min_food_days", 4.0)):
		return
	if bool(cfg.get("needs_free_bed", true)) and free_beds(world, s) <= 0:
		return
	var ages: Array = cfg.get("mother_age", [18, 42])
	var hf: Array = cfg.get("trust_factor", [40.0, 80.0, 0.4, 1.3])
	var ff: Array = cfg.get("food_factor", [4.0, 40.0, 0.5, 1.25])
	var factor := lerpf(float(hf[2]), float(hf[3]), clampf((s.trust - float(hf[0])) / maxf(float(hf[1]) - float(hf[0]), 1.0), 0.0, 1.0))
	factor *= lerpf(float(ff[2]), float(ff[3]), clampf((days_of_food - float(ff[0])) / maxf(float(ff[1]) - float(ff[0]), 1.0), 0.0, 1.0))
	var daily := float(cfg.get("annual_rate", 0.16)) / 360.0 * factor
	daily = KingdomModifiers.value(session, s.kingdom, &"population.growth", daily, ["settlement.urban_growth"])
	var rng := world.rng.stream(&"population")
	for p in world.people_of(s.id):
		if not p.female:
			continue   # a queen has children like any mother: only the father's side is excluded here
		var age := p.age_years(day)
		if age < int(ages[0]) or age > int(ages[1]):
			continue
		# a child is born to a couple (Phase 15): the father gives the surname and the family
		var father := world.person(p.spouse) if p.spouse >= 0 else null
		if father == null or father.settlement != s.id:
			continue
		if rng.randf() < daily:
			_newborn(session, s, p, father, day)
			return


func _newborn(session: GameSession, s: SettlementState, mother: PersonState, father: PersonState, day: int) -> void:
	var world := session.world
	var rng := world.rng.stream(&"population")
	var names: Dictionary = (Defs.read_json("res://data/defs/person_names.json") as Dictionary)["cultures"]
	var pool: Dictionary = names.get(String(mother.culture), names["latin"])
	var p := PersonState.new()
	p.id = world.new_id()
	p.female = rng.randf() < 0.5
	var list: Array = pool["female" if p.female else "male"]
	p.name = String(list[rng.randi_range(0, list.size() - 1)])
	p.birth_day = day
	p.culture = mother.culture
	p.religion = mother.religion
	p.settlement = s.id
	p.home = mother.home
	p.job = &"child"
	p.mother = mother.id
	p.father = father.id
	p.family = father.family if father.family >= 0 else mother.family
	p.born_family = p.family
	p.seg_from = mother.seg_to
	p.seg_to = mother.seg_to
	world.add_person(p)
	var fam := world.family(p.family)
	if fam:
		fam.record(&"children", 1.0)
	var full := SettlementSetup.full_name(world, p)
	EventBus.notify_local("Un nuovo abitante", "%s è nat%s a %s, da %s e %s." % [full, "a" if p.female else "o", s.name,
		father.name, mother.name], &"birth", mother.seg_to)
	var realm := world.kingdom(s.kingdom)
	if realm and realm.is_player and not realm.records.has(&"chronicle_first_child"):
		realm.records[&"chronicle_first_child"] = float(day)
		EventBus.chronicle_written.emit({"day": day, "kingdom": realm.id, "kind": "founding_child",
			"text": "A %s nasce %s, %s di %s e %s: il primo nato della comunità." % [s.name, full,
				"figlia" if p.female else "figlio", father.name, mother.name]})
	if realm and realm.monarchy_founded:
		CourtSystem.on_village_birth(session, realm, p, mother, father)
	EventBus.settlement_changed.emit(s.id)


func _travellers(session: GameSession, s: SettlementState, day: int) -> void:
	var world := session.world
	var cfg: Dictionary = bal()["travellers"]
	if s.trust < float(cfg.get("min_trust", 32.0)) or food_days(world, s) < float(cfg.get("min_food_days", 7.0)):
		return
	var free := free_beds(world, s)
	if free <= 0:
		return
	var rng := world.rng.stream(&"population")
	if rng.randf() > float(cfg.get("monthly_chance", 0.35)):
		return
	var group: Array = cfg.get("group", [1, 3])
	var n := mini(rng.randi_range(int(group[0]), int(group[1])), free)
	welcome(session, s, n, day, "chiedono di restare")


## People who come to stay (travellers, settlers of an event): adults of the realm's culture, each with the
## family he comes from, housed where there is a bed. Returns how many came.
static func welcome(session: GameSession, s: SettlementState, n: int, day: int, why: String) -> int:
	var world := session.world
	var rng := world.rng.stream(&"population")
	var names: Dictionary = (Defs.read_json("res://data/defs/person_names.json") as Dictionary)["cultures"]
	var realm := world.kingdom(s.kingdom)
	var pool: Dictionary = names.get(String(realm.culture), names["latin"])
	var home := _free_home(world, s)
	var arrived := PackedStringArray()
	for i in n:
		var p := PersonState.new()
		p.id = world.new_id()
		p.female = rng.randf() < 0.5
		var list: Array = pool["female" if p.female else "male"]
		p.name = String(list[rng.randi_range(0, list.size() - 1)])
		p.birth_day = day - rng.randi_range(17, 45) * PersonState.DAYS_PER_YEAR
		p.culture = realm.culture
		p.religion = realm.religion
		p.settlement = s.id
		p.home = home.id if home else -1
		p.job = &"idle"
		p.seg_from = s.center
		p.seg_to = s.center
		# a traveller comes with the surname of the family he left behind: a new family of the community
		var surnames: Array = pool.get("surnames", [])
		if not surnames.is_empty():
			var f := FamilyState.new()
			f.id = world.new_id()
			f.name = String(surnames[rng.randi_range(0, surnames.size() - 1)])
			f.settlement = s.id
			f.founded_day = day
			f.founders.append(p.id)
			world.families[f.id] = f
			p.family = f.id
			p.born_family = f.id
		world.add_person(p)
		arrived.append(SettlementSetup.full_name(world, p))
		home = _free_home(world, s)
	if arrived.is_empty():
		return 0
	EventBus.notify_local("Viandanti a %s" % s.name, "%s %s." % [", ".join(arrived), why], &"travellers", s.center)
	SettlementSim.mark_assignment_dirty(session, s.id)
	EventBus.settlement_changed.emit(s.id)
	return arrived.size()


## Grown people who leave the realm of their own will (an event, not hunger): never the sovereign, never the
## last hands of the fields. Returns how many left.
static func send_away(session: GameSession, s: SettlementState, n: int, day: int) -> int:
	var world := session.world
	var adult := int(bal().get("adult_age", 16))
	var names := PackedStringArray()
	for p in world.people_of(s.id):
		if names.size() >= n or world.people_of(s.id).size() <= int(bal().get("emigration", {}).get("keep_at_least", 3)):
			break
		if p.is_king or p.job == &"farmer" or p.job == &"soldier" or p.age_years(day) < adult:
			continue
		names.append(SettlementSetup.full_name(world, p))
		world.remove_person(p.id)
	if names.is_empty():
		return 0
	EventBus.notify_local("Partenze da %s" % s.name, "%s se ne vanno a cercare fortuna." % ", ".join(names), &"emigration", s.center)
	SettlementSim.mark_assignment_dirty(session, s.id)
	EventBus.settlement_changed.emit(s.id)
	return names.size()


# --- the valve: who leaves when the place can no longer hold him ----------------------------------------

## A settlement that cannot feed, house or employ its people loses them: first to another settlement of the
## realm that still has room, then beyond the borders. The measure is the harvest: when what is in store will
## not carry the village to the next one, a few take the road every day, and they stop as soon as what is left
## covers the ones who stayed. Without this valve a village that outgrows its fields dies to the last man.
func _emigration(session: GameSession, s: SettlementState, day: int) -> void:
	var world := session.world
	var cfg: Dictionary = bal().get("emigration", {})
	var people := world.people_of(s.id)
	# the village never sheds the hands its fields and its oven need: a place that loses its last farmer
	# loses next year's harvest too, and then nothing can save it
	var food_hands := 0
	for b in world.buildings_of(s.id):
		if b.is_active() and b.workers_wanted > 0 and (b.def().job == &"farmer" or b.def().job == &"baker"):
			food_hands += b.workers_wanted
	var keep := int(cfg.get("keep_at_least", 3))
	if people.size() <= keep:
		return
	var adult := int(bal().get("adult_age", 16))
	var elder := int(bal().get("elder_age", 62))
	var hands := 0            ## grown people who can work at all
	var hunger := 0.0
	var homeless := 0
	for p in people:
		hunger = maxf(hunger, p.hunger)
		if p.home < 0 or world.building(p.home) == null:
			homeless += 1
		if not p.is_king and p.job != &"soldier":
			var age := p.age_years(day)
			if age >= adult and age < elder:
				hands += 1
	var rng := world.rng.stream(&"population")
	var reason := ""
	var wanted := 0
	var outlook := harvest_outlook(session, s, day)
	if hunger > float(cfg.get("hunger_days", 4.0)):
		# already skipping meals: they go as fast as they can pack
		reason = "si saltano i pasti"
		wanted = maxi(1, roundi(people.size() * float(cfg.get("hungry_share_per_day", 0.06))))
	elif bool(outlook["short"]) and people.size() > int(cfg.get("harvest_valve_min_people", 12)):
		# (a handful of founders alone in a valley has nowhere to go: they stay and ration, and only real
		# hunger — the branch above — sends anybody away)
		# the granary says how many it can carry to the next harvest: the others start walking, and they stop
		# as soon as what is left covers the ones who stayed
		var excess := people.size() - int(outlook["carried"])
		if excess > 0 and rng.randf() < float(cfg.get("short_of_harvest_chance", 0.5)):
			reason = "quel che resta non arriva al raccolto"
			wanted = mini(excess, int(cfg.get("max_per_day", 2)))
	elif rng.randf() < float(cfg.get("daily_chance", 0.02)):
		# the slow reasons: no roof, no joy. Here families do take their time — at most a share in a year.
		var yearly_room := maxi(1, ceili(people.size() * float(cfg.get("max_share_per_year", 0.35)))) - s.left_this_year
		if yearly_room > 0:
			var group: Array = cfg.get("group", [1, 2])
			wanted = mini(rng.randi_range(int(group[0]), int(group[1])), yearly_room)
			if homeless > 0:
				reason = "non c'è un tetto per tutti"
			elif s.trust < float(cfg.get("max_trust", 30.0)):
				reason = "qui non si vive bene"
	if reason == "" or wanted <= 0:
		return
	# who goes: the landless first, then the hands that can be spared, and only last the men of the fields —
	# a village that loses its farmers loses its next harvest too
	var tiers: Array = [[], [], []]
	for p in people:
		if p.is_king or p.job == &"soldier":
			continue
		var age := p.age_years(day)
		if age < adult or age >= elder:
			continue   # those who take the road are the young: children and the old stay
		var tier := 1
		if p.job == &"idle":
			tier = 0
		elif p.job == &"farmer" or p.job == &"baker":
			tier = 2
		(tiers[tier] as Array).append(p)
	var leaving: Array[PersonState] = []
	for tier_index in tiers.size():
		for p: PersonState in (tiers[tier_index] as Array):
			if leaving.size() >= wanted or people.size() - leaving.size() <= keep:
				break
			if tier_index == 2 and hands - leaving.size() <= food_hands:
				break   # the fields and the oven keep their men: without them there is no next harvest
			leaving.append(p)
	if leaving.is_empty():
		return
	# nobody leaves his children behind: the little ones of the same house take the road with them
	var homes := {}
	for p in leaving:
		if p.home >= 0:
			homes[p.home] = true
	var going := leaving.duplicate()
	for p in people:
		if p.age_years(day) >= adult or p.is_king or going.has(p):
			continue
		if p.home >= 0 and homes.has(p.home):
			going.append(p)
	s.left_this_year += going.size()
	var target := _room_elsewhere(world, s, float(cfg.get("target_min_food_days", 70.0)))
	var names := PackedStringArray()
	for p in leaving:
		names.append(p.name)
	for p in going:
		if target:
			var home := _free_home(world, target)
			world.move_person(p, target.id)
			p.home = home.id if home else -1
			p.workplace = -1
			p.job = &"child" if p.age_years(day) < adult else &"idle"
			p.seg_from = target.center
			p.seg_to = target.center
			p.hunger = 0.0
		else:
			world.remove_person(p.id)
	var carried := "" if going.size() == leaving.size() else " con %d figli" % (going.size() - leaving.size())
	if target:
		EventBus.notify_local("Partenze da %s" % s.name,
			"%s%s se ne vanno a %s: %s." % [", ".join(names), carried, target.name, reason], &"emigration", s.center)
		SettlementSim.mark_assignment_dirty(session, target.id)
		EventBus.settlement_changed.emit(target.id)
	else:
		EventBus.notify_local("Partenze da %s" % s.name,
			"%s%s lasciano il regno: %s." % [", ".join(names), carried, reason], &"emigration", s.center)
	SettlementSim.mark_assignment_dirty(session, s.id)
	EventBus.settlement_changed.emit(s.id)


## Days between today and the end of the next harvest: the span the stores have to cover. Zero while the
## harvest is being brought in (the granary is filling: nobody leaves in August).
## Whether the stores reach the next harvest, the measure the village lives by:
## {food_days, to_harvest, people, carried, short, store_days, needs_granary}. "carried" is how many people what
## is in store can feed until the harvest (with the margin of the balance); when it is fewer than the people,
## "short" is true and the ones who cannot be carried start to leave. "store_days" is how many days of food the
## stores could hold if full: when it is less than a year from harvest to harvest, the fields are not the
## problem — the harvest is lost for want of a granary. The top bar and the conditions of the kingdom read these.
static func harvest_outlook(session: GameSession, s: SettlementState, day: int = -1) -> Dictionary:
	var world := session.world
	var cfg: Dictionary = bal().get("emigration", {})
	if day < 0:
		day = world.day
	var people := world.people_of(s.id).size()
	var days_of_food := food_days(world, s)
	var to_harvest := _days_to_harvest(session, day, int(cfg.get("harvest_month", 8)))
	var needed := float(to_harvest) * float(cfg.get("harvest_margin", 0.85))
	var carried := people
	if to_harvest > 0 and days_of_food < needed:
		carried = mini(people, floori(people * days_of_food / maxf(needed, 1.0)))
	var factors := _food_factors(world, s)
	var best := 0.0
	for res: StringName in [&"grain", &"bread"]:
		var rd := Defs.resource(res)
		if rd:
			best = maxf(best, float(factors.get(res, rd.food_value)))
	var per_day := float(Defs.balance("settlement").get("food_per_person_day", 0.25)) * maxi(people, 1)
	var store_days := float(s.capacity(world, &"food")) * best / maxf(per_day, 0.0001)
	var year := float(session.calendar.days_per_month * 12) * float(cfg.get("harvest_margin", 0.85))
	return {"food_days": days_of_food, "to_harvest": to_harvest, "people": people, "carried": carried,
		"short": carried < people, "store_days": store_days, "needs_granary": store_days < year}


static func _days_to_harvest(session: GameSession, day: int, harvest_month: int) -> int:
	var d := session.calendar.date_of(day)
	var month := int(d["month"])
	if month == harvest_month:
		return 0
	var months := (harvest_month - month + 12) % 12
	return months * session.calendar.days_per_month - int(d["day"]) + 1


## Another settlement of the same realm with a free bed and food in store, or null.
static func _room_elsewhere(world: WorldState, from: SettlementState, min_food_days: float) -> SettlementState:
	var best: SettlementState = null
	var best_food := min_food_days
	for other in world.settlements:
		if other.id == from.id or other.kingdom != from.kingdom:
			continue
		if free_beds(world, other) <= 0:
			continue
		var food := food_days(world, other)
		if food >= best_food:
			best_food = food
			best = other
	return best


## The first house (in the order of the buildings) with a bed nobody sleeps in. The beds in use are counted once,
## not once per house (Phase 19: every house walked every inhabitant — in a town of a thousand the newcomers of
## one caravan cost a second and more).
static func _free_home(world: WorldState, s: SettlementState) -> BuildingState:
	var used := {}
	for p in world.people_of(s.id):
		if p.home >= 0:
			used[p.home] = int(used.get(p.home, 0)) + 1
	for b in world.buildings_of(s.id):
		if b.is_active() and b.def().beds > 0 and int(used.get(b.id, 0)) < b.def().beds:
			return b
	return null


## The session is passed in, never guessed (Phase 19: a static "fallback session" kept the previous campaign
## alive in memory and could lend its realm modifiers to the next one).
func _trust(session: GameSession, s: SettlementState, day: int) -> void:
	var world := session.world
	var cfg: Dictionary = bal()["trust"]
	var people := world.people_of(s.id)
	if people.is_empty():
		return   # nobody left to be content or not: the last word on the place stays what it was
	var parts := {}
	var value := float(cfg.get("base", 50.0))
	var realm_base := KingdomModifiers.value(session, s.kingdom, &"trust.base", value) - value
	if absf(realm_base) > 0.01:
		parts["Indole del regno"] = realm_base
	var days_of_food := food_days(world, s)
	var food_part := 0.0
	if days_of_food >= float(cfg.get("food_days_good", 30.0)):
		food_part = float(cfg.get("food_days_bonus", 18.0))
	elif days_of_food <= float(cfg.get("food_days_bad", 5.0)):
		food_part = lerpf(float(cfg.get("food_days_malus", -34.0)), 0.0, clampf(days_of_food / maxf(float(cfg.get("food_days_bad", 5.0)), 0.1), 0.0, 1.0))
	else:
		food_part = lerpf(0.0, float(cfg.get("food_days_bonus", 18.0)),
			clampf((days_of_food - float(cfg.get("food_days_bad", 5.0))) / maxf(float(cfg.get("food_days_good", 30.0)) - float(cfg.get("food_days_bad", 5.0)), 1.0), 0.0, 1.0))
	parts["Cibo"] = food_part
	var hunger := 0.0
	var homeless := 0
	for p in people:
		hunger = maxf(hunger, p.hunger)
		if p.home < 0 or not world.buildings.has(p.home):
			homeless += 1
	if hunger > 0.5:
		parts["Fame"] = float(cfg.get("hunger_malus_per_day", -2.2)) * minf(hunger, 10.0)
	if homeless > 0:
		parts["Senzatetto"] = float(cfg.get("homeless_malus_per_person", -6.0)) * homeless
	elif free_beds(world, s) > 0:
		parts["Alloggi"] = float(cfg.get("housing_bonus", 10.0))
	var coverage := service_coverage(world, s)
	if coverage > 0.0:
		parts["Servizi"] = float(cfg.get("service_bonus", 8.0)) * coverage
	var memory := int(cfg.get("death_memory_days", 60))
	var recent := PackedInt32Array()
	for d in s.recent_deaths:
		if day - d <= memory:
			recent.append(d)
	s.recent_deaths = recent
	if recent.size() > 0:
		parts["Lutti recenti"] = float(cfg.get("recent_death_malus", -6.0)) * recent.size()
	var realm := world.kingdom(s.kingdom)
	if realm and realm.treasury < 0.0:
		parts["Debiti della corona"] = float(cfg.get("debt_malus", -10.0))
	if realm and realm.monarchy_founded:   # before the crown nobody reigns: there is no crown to judge
		var crown := (realm.legitimacy - 55.0) * float(cfg.get("legitimacy_weight", 0.12)) \
			+ (realm.stability - 80.0) * float(cfg.get("stability_weight", 0.10))
		if absf(crown) > 0.01:
			parts["La corona"] = crown
	for siege in world.sieges:
		if siege.province == s.province:
			parts["Assedio"] = float(cfg.get("siege_malus", -30.0))
			break
	var province := world.province(s.province)
	if province and province.is_occupied():
		parts["Occupazione"] = float(cfg.get("occupation_malus", -20.0))
	for k: String in parts.keys():
		value += float(parts[k])
	value = clampf(value, 0.0, 100.0)
	s.trust = lerpf(s.trust, value, clampf(float(cfg.get("smooth_per_day", 0.25)), 0.01, 1.0))
	s.trust_parts = parts


## The province of a settlement counts the people who really live there.
func _sync_province(world: WorldState, s: SettlementState) -> void:
	var p := world.province(s.province)
	if p:
		p.population = world.people_of(s.id).size()

