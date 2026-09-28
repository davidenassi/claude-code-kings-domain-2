class_name Diplomacy
extends RefCounted
## The rules of what stands between two crowns: where the opinion comes from, who is strong, what a pact
## gives and what it costs to break it. Data in data/defs/diplomacy.json and balance/diplomacy.json.
## The state itself lives in WorldState.relations (RelationState, one per pair).

const PATH := "res://data/defs/diplomacy.json"

static var _data: Dictionary = {}
static var _pact_index: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = Defs.read_json(PATH)
		_data = d if d is Dictionary else {"pacts": []}
	return _data


static func bal() -> Dictionary:
	return Defs.balance("diplomacy")


static func pacts() -> Array:
	return data().get("pacts", [])


## The treaties that bind, and so enter the chronicle: an alliance, a vassalage, a tribute. The pacts of
## non-aggression and trade are renewed every five years: they live in the Diplomazia sheet (consolidation).
const CHRONICLE_PACTS: Array[StringName] = [&"alliance", &"vassalage", &"tribute"]


static func pact(pact_id: StringName) -> Dictionary:
	if _pact_index.is_empty():
		for p: Dictionary in pacts():
			_pact_index[StringName(p["id"])] = p
	return _pact_index.get(pact_id, {})


static func memory_def(kind: StringName) -> Dictionary:
	return (data().get("memories", {}) as Dictionary).get(String(kind), {})


## Gives every pair of living realms a relation, so the world starts with opinions instead of silence.
static func found_relations(world: WorldState) -> void:
	for i in world.kingdoms.size():
		var ka := world.kingdoms[i]
		if not ka.alive or ka.provinces.is_empty():
			continue
		for j in range(i + 1, world.kingdoms.size()):
			var kb := world.kingdoms[j]
			if not kb.alive or kb.provinces.is_empty():
				continue
			var r := relation(world, ka.id, kb.id)
			if r.opinion == 0.0 and r.memories.is_empty():
				r.opinion = opinion_target(world, r)   # the world does not start from nothing


# --- reading the state ------------------------------------------------------------------------------------

static func relation(world: WorldState, x: int, y: int) -> RelationState:
	if x == y or x < 0 or y < 0:
		return null
	var key := "%d:%d" % [mini(x, y), maxi(x, y)]
	var r: RelationState = world.relations.get(key)
	if r == null:
		r = RelationState.make(x, y)
		world.relations[key] = r
	return r


static func opinion(world: WorldState, x: int, y: int) -> float:
	var r := relation(world, x, y)
	return r.opinion if r else 0.0


## The realm this one pays, by tribute or vassalage (-1 when it pays nobody). A crown has one lord at most.
static func lord_of(world: WorldState, kingdom_id: int) -> int:
	for r: RelationState in world.relations.values():
		if r.payer == kingdom_id and (r.has_pact(&"tribute") or r.has_pact(&"vassalage")):
			return r.other(kingdom_id)
	return -1


## Why this pact cannot be signed between these two for reasons of rank (Phase 16), "" when it can: a community
## without a crown signs no treaties, and nobody pays two lords.
static func pact_blocker(world: WorldState, a: KingdomState, b: KingdomState, pact_id: StringName) -> String:
	if not a.monarchy_founded or not b.monarchy_founded:
		return "Una comunità senza corona non firma trattati: prima la corona."
	if bool(pact(pact_id).get("asymmetric", false)):
		var payer := b if power(world, b) < power(world, a) else a
		var lord := lord_of(world, payer.id)
		var other := a if payer == b else b
		if lord >= 0 and lord != other.id:
			return "%s paga già un altro signore." % payer.name
	return ""


static func at_war(world: WorldState, x: int, y: int) -> bool:
	var r := relation(world, x, y)
	return r != null and r.at_war


static func has_pact(world: WorldState, x: int, y: int, pact_id: StringName) -> bool:
	var r := relation(world, x, y)
	return r != null and r.has_pact(pact_id)


## Everyone this realm is at war with today.
static func enemies_of(world: WorldState, kingdom_id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for r: RelationState in world.relations.values():
		if r.at_war and (r.a == kingdom_id or r.b == kingdom_id):
			out.append(r.other(kingdom_id))
	return out


## Everyone bound to follow this realm to war (allies, vassals).
static func allies_of(world: WorldState, kingdom_id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for r: RelationState in world.relations.values():
		if r.a != kingdom_id and r.b != kingdom_id:
			continue
		for pact_id: StringName in r.pacts.keys():
			if bool(pact(pact_id).get("calls_to_war", false)):
				out.append(r.other(kingdom_id))
				break
	return out


static func liege_of(world: WorldState, kingdom_id: int) -> int:
	for r: RelationState in world.relations.values():
		if r.has_pact(&"vassalage") and r.payer == kingdom_id and (r.a == kingdom_id or r.b == kingdom_id):
			return r.other(kingdom_id)
	return -1


# --- how strong, how close, how alike --------------------------------------------------------------------

## A rough measure of what a realm weighs in the world: lands, people, gold and renown.
## The weight of the lands is cached (it only moves when the political map does); gold and renown are read live.
static func power(world: WorldState, k: KingdomState) -> float:
	if k == null or not k.alive:
		return 0.0
	return maxf(world.lands_power(k.id) + maxf(k.treasury, 0.0) / 400.0 + k.prestige * 0.06, 0.2)


static func power_ratio(world: WorldState, strong: int, weak: int) -> float:
	var pw := power(world, world.kingdom(weak))
	return power(world, world.kingdom(strong)) / maxf(pw, 0.2)


static func are_neighbours(world: WorldState, x: int, y: int) -> bool:
	return world.adjacency().has("%d:%d" % [mini(x, y), maxi(x, y)])


## The opinion the facts of today ask for; the real opinion walks towards it day by day.
static func opinion_target(world: WorldState, r: RelationState) -> float:
	var cfg: Dictionary = bal().get("opinion", {})
	var ka := world.kingdom(r.a)
	var kb := world.kingdom(r.b)
	if ka == null or kb == null:
		return 0.0
	var value := float(cfg.get("base", 0.0))
	value += float(cfg.get("same_culture", 14.0)) if ka.culture == kb.culture else float(cfg.get("other_culture", -6.0))
	value += float(cfg.get("same_religion", 12.0)) if ka.religion == kb.religion else float(cfg.get("other_religion", -10.0))
	if are_neighbours(world, r.a, r.b):
		value += float(cfg.get("neighbour", -8.0))
		# a big neighbour is a shadow over the roof
		var ratio_a := power_ratio(world, r.b, r.a)
		var ratio_b := power_ratio(world, r.a, r.b)
		value += float(cfg.get("stronger_neighbour_max", -14.0)) * clampf((maxf(ratio_a, ratio_b) - 1.0) / 2.5, 0.0, 1.0)
	else:
		value += float(cfg.get("distant", 4.0))
	for pact_id: StringName in r.pacts.keys():
		value += float(pact(pact_id).get("opinion", 0.0))
	if r.married:
		value += float((data().get("marriage", {}) as Dictionary).get("opinion", 18.0))
	if r.at_war:
		value += float(cfg.get("at_war", -60.0))
	elif r.truce_until > world.day:
		value += float(cfg.get("truce", 6.0))
	value += memories_value(world, r)
	return clampf(value, float(cfg.get("min", -100.0)), float(cfg.get("max", 100.0)))


## What the two realms still remember, faded by the years.
static func memories_value(world: WorldState, r: RelationState) -> float:
	var total := 0.0
	for m: Dictionary in r.memories:
		var def := memory_def(StringName(m["kind"]))
		if def.is_empty():
			continue
		var years := float(world.day - int(m["day"])) / float(PersonState.DAYS_PER_YEAR)
		var life := float(def.get("years", 20))
		if years >= life:
			continue
		total += float(def.get("value", 0.0)) * (1.0 - years / life)
	return total


## Readable list of what makes the opinion what it is (for the tooltip and for the AI log).
static func opinion_breakdown(world: WorldState, r: RelationState) -> Array:
	var cfg: Dictionary = bal().get("opinion", {})
	var ka := world.kingdom(r.a)
	var kb := world.kingdom(r.b)
	var out: Array = []
	if ka == null or kb == null:
		return out
	if ka.culture == kb.culture:
		out.append({"label": "Stessa cultura", "value": float(cfg.get("same_culture", 14.0))})
	else:
		out.append({"label": "Culture diverse", "value": float(cfg.get("other_culture", -6.0))})
	if ka.religion == kb.religion:
		out.append({"label": "Stessa fede", "value": float(cfg.get("same_religion", 12.0))})
	else:
		out.append({"label": "Fedi diverse", "value": float(cfg.get("other_religion", -10.0))})
	if are_neighbours(world, r.a, r.b):
		out.append({"label": "Confinanti", "value": float(cfg.get("neighbour", -8.0))})
		var ratio := maxf(power_ratio(world, r.b, r.a), power_ratio(world, r.a, r.b))
		var shadow := float(cfg.get("stronger_neighbour_max", -14.0)) * clampf((ratio - 1.0) / 2.5, 0.0, 1.0)
		if absf(shadow) > 0.5:
			out.append({"label": "Vicino più forte", "value": shadow})
	else:
		out.append({"label": "Lontani", "value": float(cfg.get("distant", 4.0))})
	for pact_id: StringName in r.pacts.keys():
		var p := pact(pact_id)
		out.append({"label": String(p.get("name", pact_id)), "value": float(p.get("opinion", 0.0))})
	if r.married:
		out.append({"label": "Matrimonio dinastico", "value": float((data().get("marriage", {}) as Dictionary).get("opinion", 18.0))})
	if r.at_war:
		out.append({"label": "In guerra", "value": float(cfg.get("at_war", -60.0))})
	for m: Dictionary in r.memories:
		var def := memory_def(StringName(m["kind"]))
		if def.is_empty():
			continue
		var years := float(world.day - int(m["day"])) / float(PersonState.DAYS_PER_YEAR)
		var life := float(def.get("years", 20))
		if years >= life:
			continue
		out.append({"label": String(def.get("name", m["kind"])), "value": float(def.get("value", 0.0)) * (1.0 - years / life)})
	return out


# --- signing, breaking, fighting -------------------------------------------------------------------------

## Writes the pact into the relation (no checks: the commands validate, this applies).
static func sign(world: WorldState, x: int, y: int, pact_id: StringName) -> void:
	var r := relation(world, x, y)
	var def := pact(pact_id)
	var days := int(def.get("days", 0))
	r.pacts[pact_id] = world.day + days if days > 0 else 0
	if bool(def.get("asymmetric", false)):
		# the weaker one pays
		r.payer = x if power(world, world.kingdom(x)) < power(world, world.kingdom(y)) else y
	if r.at_war and bool(def.get("blocks_war", false)):
		end_war(world, x, y, &"peace")
	_touch(world, x, y)


static func break_pact(world: WorldState, breaker: int, other_id: int, pact_id: StringName) -> void:
	var r := relation(world, breaker, other_id)
	if not r.has_pact(pact_id):
		return
	var def := pact(pact_id)
	r.pacts.erase(pact_id)
	if r.pacts.is_empty():
		r.payer = -1
	r.remember(&"pact_broken", world.day)
	var kb := world.kingdom(breaker)
	if kb:
		CourtSystem.add_prestige(kb, float(def.get("break_prestige", 0.0)))
	_touch(world, breaker, other_id)


static func start_war(world: WorldState, attacker: int, defender: int) -> void:
	var r := relation(world, attacker, defender)
	if r.at_war:
		return
	r.at_war = true
	r.war_since = world.day
	r.remember(&"war_declared", world.day)
	# the years of peace are counted from the last war, and a realm remembers how many it fought (Phase 17:
	# last_war_day was read by the national spirits but never written)
	for side in [attacker, defender]:
		var sk := world.kingdom(side)
		if sk:
			sk.records[&"last_war_day"] = float(world.day)
			sk.records[&"wars_fought"] = float(sk.records.get(&"wars_fought", 0.0)) + 1.0
	for pact_id: StringName in r.pacts.keys():
		if bool(pact(pact_id).get("blocks_war", false)):
			r.pacts.erase(pact_id)
			r.remember(&"pact_broken", world.day)
	var ka := world.kingdom(attacker)
	if ka:
		var w: Dictionary = bal().get("war", {})
		CourtSystem.add_prestige(ka, float(w.get("prestige_declaring", -3.0)))
		ka.turbulence += float(w.get("turbulence_declaring", 6.0))
	_touch(world, attacker, defender)


static func end_war(world: WorldState, x: int, y: int, _reason: StringName = &"peace") -> void:
	var r := relation(world, x, y)
	for side in [x, y]:
		var sk := world.kingdom(side)
		if sk:
			sk.records[&"last_war_day"] = float(world.day)
	if not r.at_war:
		return
	# whatever was only held by arms goes back to its crown
	for pid in War.occupied_provinces(world, x, y):
		War.liberate(world, pid)
	for pid in War.occupied_provinces(world, y, x):
		War.liberate(world, pid)
	r.war_score = 0.0
	r.at_war = false
	r.war_since = -1
	r.truce_until = world.day + int(bal().get("truce_days", 1800))
	r.remember(&"peace_made", world.day)
	_touch(world, x, y)


## Pacts are named sources in the formula of both realms, so their effects are inspectable like any other.
static func _touch(world: WorldState, x: int, y: int) -> void:
	for kid in [x, y]:
		var k := world.kingdom(kid)
		if k:
			k.identity_changed()
	EventBus.diplomacy_changed.emit(x, y)


## Everything the pacts of a realm add to its formula (read by KingdomModifiers).
static func pact_modifiers(world: WorldState, kingdom_id: int) -> Array:
	var out: Array = []
	for r: RelationState in world.relations.values():
		if r.a != kingdom_id and r.b != kingdom_id:
			continue
		for pact_id: StringName in r.pacts.keys():
			var def := pact(pact_id)
			var mods: Array = def.get("modifiers", [])
			if mods.is_empty():
				continue
			var other_k := world.kingdom(r.other(kingdom_id))
			out.append({"id": "pact:%s:%d" % [pact_id, r.other(kingdom_id)], "modifiers": mods,
				"label": "%s con %s" % [def.get("name", pact_id), other_k.name if other_k else "?"]})
	return out

