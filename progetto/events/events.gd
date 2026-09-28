class_name Events
extends RefCounted
## What the world does to a realm without being asked: the facts it looks at, the conditions of an event, and
## what a chosen option really changes. Data in data/defs/events.json and balance/events.json.

const PATH := "res://data/defs/events.json"

static var _data: Dictionary = {}
static var _index: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = Defs.read_json(PATH)
		_data = d if d is Dictionary else {"events": []}
	return _data


static func bal() -> Dictionary:
	return Defs.balance("events")


static func all() -> Array:
	return data().get("events", [])


static func event(event_id: StringName) -> Dictionary:
	if _index.is_empty():
		for e: Dictionary in all():
			_index[StringName(e["id"])] = e
	return _index.get(event_id, {})


# --- the facts an event can ask about ------------------------------------------------------------------------

## Everything the conditions may read, gathered once per roll.
static func facts(session: GameSession, k: KingdomState) -> Dictionary:
	var world := session.world
	var out := {}
	out["season"] = session.calendar.season_name(session.calendar.season_of(world.day)).to_lower()
	out["provinces"] = k.provinces.size()
	out["crowned"] = k.monarchy_founded
	if k.monarchy_founded:
		# a community has no crown to be firm or shaky: the conditions on it never hold before the crowning
		out["legitimacy"] = k.legitimacy
		out["stability"] = k.stability
	out["treasury"] = k.treasury
	out["prestige"] = k.prestige
	var settlement: SettlementState = null
	for s in world.settlements:
		if s.kingdom == k.id:
			settlement = s
			break
	out["has_settlement"] = settlement != null
	out["trust"] = settlement.trust if settlement else 55.0
	out["population"] = world.people_of(settlement.id).size() if settlement else 0
	var enemies := Diplomacy.enemies_of(world, k.id)
	out["at_war"] = not enemies.is_empty()
	var war_years := 0.0
	for enemy in enemies:
		var r := Diplomacy.relation(world, k.id, enemy)
		if r and r.war_since >= 0:
			war_years = maxf(war_years, float(world.day - r.war_since) / float(PersonState.DAYS_PER_YEAR))
	out["war_years"] = war_years
	var unrest := 0.0
	for pid in k.provinces:
		var p := world.province(pid)
		if p:
			unrest = maxf(unrest, p.unrest)
	out["unrest"] = unrest
	# Phase 17: what the realm is, so that most events happen to somebody in particular
	out["year"] = float(world.day) / float(PersonState.DAYS_PER_YEAR)
	out["families"] = FamilySystem.living_families(world, settlement).size() if settlement else 0
	var ruler := world.ruler_of(k.id)
	out["ruler_traits"] = ruler.traits if ruler else []
	out["ruler_age"] = ruler.age_years(world.day) if ruler else 0
	out["regency"] = k.regency
	var heir := CourtSystem.heir_of(world, k) if k.monarchy_founded else null
	out["heir"] = "none" if heir == null else ("adult" if heir.age_years(world.day) >= 16 else "child")
	var pacts := {}
	for r: RelationState in world.relations.values():
		if r.a == k.id or r.b == k.id:
			for pact_id: StringName in r.pacts.keys():
				pacts[String(pact_id)] = true
	out["pacts"] = pacts
	var favour := {}
	for key: StringName in k.favour.keys():
		if not String(key).begins_with("_"):
			favour[String(key)] = float(k.favour[key])
	out["favour"] = favour if k.monarchy_founded else {}
	var built := {}
	if settlement:
		for b in world.buildings_of(settlement.id):
			if b.is_active():
				built[String(b.def_id)] = true
	out["buildings"] = built
	var capital := WorldData.get_instance().province_geo(k.capital) if k.capital >= 0 else null
	out["capital_river"] = capital.has_river if capital else false
	out["capital_mountain"] = capital != null and (capital.terrain == &"mountains" or capital.terrain == &"hills")
	out["capital_forest"] = capital.forest if capital else 0.0
	var foreign := 0
	for pid in k.provinces:
		var p := world.province(pid)
		if p and p.culture != k.culture:
			foreign += 1
	out["foreign_provinces"] = foreign
	out["wars"] = int(k.records.get(&"wars_fought", 0.0))
	out["spirits"] = k.spirits
	out["crises"] = k.crises.map(func(c: Dictionary) -> String: return String(c.get("id", "")))
	return out


## True when every condition of `when` holds. Unknown keys make the event impossible, never silently true.
static func matches(when: Dictionary, f: Dictionary) -> bool:
	for key: String in when.keys():
		var value: Variant = when[key]
		match key:
			"season":
				if String(f.get("season", "")) != String(value):
					return false
			"crowned":
				if bool(f.get("crowned", true)) != bool(value):
					return false
			"has_settlement":
				if bool(f.get("has_settlement", false)) != bool(value):
					return false
			"at_war":
				if bool(f.get("at_war", false)) != bool(value):
					return false
			"at_peace":
				if bool(f.get("at_war", false)) == bool(value):
					return false
			"min_war_years":
				if float(f.get("war_years", 0.0)) < float(value):
					return false
			"min_provinces":
				if int(f.get("provinces", 0)) < int(value):
					return false
			"min_population":
				if int(f.get("population", 0)) < int(value):
					return false
			"min_trust":
				if float(f.get("trust", 0.0)) < float(value):
					return false
			"max_trust":
				if float(f.get("trust", 100.0)) > float(value):
					return false
			"min_legitimacy":
				if float(f.get("legitimacy", 0.0)) < float(value):
					return false
			"max_legitimacy":
				if float(f.get("legitimacy", 100.0)) > float(value):
					return false
			"max_stability":
				if float(f.get("stability", 100.0)) > float(value):
					return false
			"min_unrest":
				if float(f.get("unrest", 0.0)) < float(value):
					return false
			"min_year":
				if float(f.get("year", 0.0)) < float(value):
					return false
			"min_families":
				if int(f.get("families", 0)) < int(value):
					return false
			"min_treasury":
				if float(f.get("treasury", 0.0)) < float(value):
					return false
			"max_treasury":
				if float(f.get("treasury", 0.0)) > float(value):
					return false
			"min_prestige":
				if float(f.get("prestige", 0.0)) < float(value):
					return false
			"ruler_trait":
				if not (f.get("ruler_traits", []) as Array).has(StringName(value)):
					return false
			"ruler_min_age":
				if int(f.get("ruler_age", 0)) < int(value):
					return false
			"regency":
				if bool(f.get("regency", false)) != bool(value):
					return false
			"heir":
				if String(f.get("heir", "none")) != String(value):
					return false
			"has_pact":
				if not (f.get("pacts", {}) as Dictionary).has(String(value)):
					return false
			"favour_below", "favour_above":
				var have: Dictionary = f.get("favour", {})
				for fid: String in (value as Dictionary).keys():
					if not have.has(fid):
						return false   # no powers yet: a community has no favour to be above or below
					var v := float(have[fid])
					if (key == "favour_below" and v >= float(value[fid])) or (key == "favour_above" and v <= float(value[fid])):
						return false
			"has_building":
				if not (f.get("buildings", {}) as Dictionary).has(String(value)):
					return false
			"capital_river":
				if bool(f.get("capital_river", false)) != bool(value):
					return false
			"capital_mountain":
				if bool(f.get("capital_mountain", false)) != bool(value):
					return false
			"capital_forest":
				if float(f.get("capital_forest", 0.0)) < float(value):
					return false
			"min_foreign_provinces":
				if int(f.get("foreign_provinces", 0)) < int(value):
					return false
			"min_wars":
				if int(f.get("wars", 0)) < int(value):
					return false
			"has_spirit":
				if not (f.get("spirits", []) as Array).has(StringName(value)):
					return false
			"no_crisis":
				if (f.get("crises", []) as Array).has(String(value)):
					return false
			_:
				return false   # a condition nobody knows how to read must not fire the event
	return true


## The words of an event for this realm: before the crowning there is no crown and no kingdom, only the
## community (Phase 15). Texts write {corona}, {Corona}, {regno}, {Regno} where either would fit.
static func words(k: KingdomState, text: String) -> String:
	var crowned := k == null or k.monarchy_founded
	return text.format({
		"corona": "la corona" if crowned else "la comunità", "Corona": "La corona" if crowned else "La comunità",
		"regno": "il regno" if crowned else "la comunità", "Regno": "Il regno" if crowned else "La comunità",
		"della_corona": "della corona" if crowned else "della comunità",
		"alla_corona": "alla corona" if crowned else "alla comunità",
	})


## The events that could happen to this realm today, with their weights.
static func candidates(session: GameSession, k: KingdomState) -> Array:
	var f := facts(session, k)
	var out: Array = []
	for e: Dictionary in all():
		var event_id := StringName(e["id"])
		var last := int(k.records.get(StringName("event_day:%s" % event_id), -999999.0))
		if session.world.day - last < int(e.get("cooldown_days", 720)):
			continue
		if bool(e.get("once", false)) and last > -999999:
			continue
		if bool(e.get("chain_only", false)):
			continue   # it comes only as the sequel of another event
		if not matches(e.get("when", {}), f):
			continue
		out.append(e)
	return out


static func pick(session: GameSession, k: KingdomState, rng: RandomNumberGenerator) -> Dictionary:
	var pool := candidates(session, k)
	if pool.is_empty():
		return {}
	var total := 0.0
	for e: Dictionary in pool:
		total += weight_in_campaign(session, e)
	var roll := rng.randf() * total
	for e: Dictionary in pool:
		roll -= weight_in_campaign(session, e)
		if roll <= 0.0:
			return e
	return pool[pool.size() - 1]


## The fate of the campaign (Phase 17): every event weighs between a quarter and nearly twice its usual weight,
## decided once by the seed of the campaign. One valley is a valley of floods, another of bandits, another of
## fairs: the second, third and fifth game do not live the same years. (Three campaigns of sixty years shared
## thirty of their thirty-six events before this.)
static func weight_in_campaign(session: GameSession, e: Dictionary) -> float:
	var cfg: Dictionary = bal().get("events", {})
	var lo := float(cfg.get("fate_min", 0.25))
	var hi := float(cfg.get("fate_max", 1.8))
	var h := KDRng.hash01(session.world.rng.campaign_seed, hash(String(e.get("id", ""))), 1717)
	# squared: most events are ordinary in a campaign, a few are its own
	return float(e.get("weight", 1.0)) * lerpf(lo, hi, h * h)


# --- what an option does -------------------------------------------------------------------------------------

## Applies the effects of one option. Everything here is a real change to the world, never a number on a sheet.
static func apply(session: GameSession, k: KingdomState, effects: Dictionary) -> void:
	var world := session.world
	var settlement: SettlementState = null
	for s in world.settlements:
		if s.kingdom == k.id:
			settlement = s
			break
	for key: String in effects.keys():
		var value: Variant = effects[key]
		match key:
			"treasury":
				k.treasury += float(value)
			"legitimacy":
				if k.monarchy_founded:
					k.legitimacy = clampf(k.legitimacy + float(value), 0.0, 100.0)
				else:
					k.authority = clampf(k.authority + float(value), 0.0, 100.0)   # before the crown: how firmly it decides
			"stability":
				k.stability = clampf(k.stability + float(value), 0.0, 100.0)
			"prestige":
				CourtSystem.add_prestige(k, float(value))
			"turbulence":
				k.turbulence = maxf(k.turbulence + float(value), 0.0)
			"research":
				k.research += float(value)
			"trust":
				if settlement:
					settlement.trust = clampf(settlement.trust + float(value), 0.0, 100.0)
			"favour":
				if k.monarchy_founded:   # before the crown there are no powers of the realm to please or to anger
					CrownEffects.apply_political(k, {"favour": value})
			"stock":
				if settlement:
					for res: String in (value as Dictionary).keys():
						var amount := int((value as Dictionary)[res])
						if amount >= 0:
							settlement.add(StringName(res), amount, &"event")
						else:
							settlement.take(StringName(res), -amount, &"event")
			"unrest":
				for pid in k.provinces:
					var p := world.province(pid)
					if p:
						p.unrest = clampf(p.unrest + float(value), 0.0, 1.0)
			"devastation":
				for pid in k.provinces:
					var p := world.province(pid)
					if p:
						p.devastation = clampf(p.devastation + float(value), 0.0, 1.0)
			"kill_people":
				_kill(session, settlement, int(value))
			"crisis":
				add_crisis(k, value as Dictionary, world.day)
			"spirit":
				if not k.spirits.has(StringName(value)):
					k.spirits.append(StringName(value))
					k.spirit_since[StringName(value)] = world.day
					k.identity_changed()
			"opinion_neighbour":
				var neighbour := _a_neighbour(world, k)
				if neighbour >= 0:
					var r := Diplomacy.relation(world, k.id, neighbour)
					r.opinion = clampf(r.opinion + float(value), -100.0, 100.0)
					if float(value) > 0.0:
						r.remember(&"gift", world.day)
			"authority":
				k.authority = clampf(k.authority + float(value), 0.0, 100.0)
			"arrivals":
				if settlement:
					PopulationSystem.welcome(session, settlement, int(value), world.day, "arrivano con l'evento")
			"departures":
				if settlement:
					PopulationSystem.send_away(session, settlement, int(value), world.day)
			"chronicle":
				EventBus.chronicle_written.emit({"day": world.day, "kingdom": k.id, "kind": "event", "text": words(k, String(value))})
			"chain":
				k.records[StringName("event_chain")] = 0.0   # the chain is fired by the system, see EventSystem
	EventBus.settlement_changed.emit(settlement.id if settlement else 0)


## A shock that lasts: a named source in the formula of the realm until its day runs out.
static func add_crisis(k: KingdomState, crisis: Dictionary, day: int) -> void:
	var entry := {"id": String(crisis.get("id", "crisi")), "name": String(crisis.get("name", "Crisi")),
		"until": day + int(crisis.get("days", 180)), "modifiers": crisis.get("modifiers", [])}
	for existing in k.crises:
		if String(existing["id"]) == String(entry["id"]):
			existing["until"] = maxi(int(existing["until"]), int(entry["until"]))
			k.identity_changed()
			return
	k.crises.append(entry)
	k.identity_changed()
	if k.is_player:
		EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "crisis",
			"text": "Comincia %s: durerà fino al %s." % [String(entry["name"]).to_lower(),
				Session.current.calendar.format_date(int(entry["until"])) if Session.has_game() else "prossima stagione"]})


static func _kill(session: GameSession, settlement: SettlementState, count: int) -> void:
	if settlement == null or count <= 0:
		return
	var world := session.world
	var people := world.people_of(settlement.id)
	var rng := world.rng.stream(&"events")
	for i in mini(count, maxi(people.size() - 2, 0)):
		var victim: PersonState = people[rng.randi_range(0, people.size() - 1)]
		if victim.is_king:
			continue
		world.remove_person(victim.id)
		settlement.recent_deaths.append(world.day)
		people = world.people_of(settlement.id)
		if people.size() <= 2:
			break
	SettlementSim.mark_assignment_dirty(session, settlement.id)


static func _a_neighbour(world: WorldState, k: KingdomState) -> int:
	for r: RelationState in world.relations.values():
		if r.a == k.id or r.b == k.id:
			var other_id := r.other(k.id)
			var other := world.kingdom(other_id)
			if other and other.alive and not other.provinces.is_empty():
				return other_id
	return -1


## Which option a crown of this character would choose.
static func ai_choice(world: WorldState, k: KingdomState, e: Dictionary) -> int:
	var mind := DiplomacyAi.personality(world, k.id)
	var options: Array = e.get("options", [])
	var best := 0
	var best_value := -INF
	for i in options.size():
		var weights: Dictionary = (options[i] as Dictionary).get("ai", {})
		var value := 0.0
		for key: String in weights.keys():
			value += float(weights[key]) * float(mind.get(key, 0.25))
		# a crown with an empty treasury cannot choose what it cannot pay
		var cost := float((options[i] as Dictionary).get("effects", {}).get("treasury", 0.0))
		if cost < 0.0 and k.treasury + cost < 0.0:
			value -= 1.0
		if value > best_value:
			best_value = value
			best = i
	return best

