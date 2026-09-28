class_name NationalSpiritSystem
extends SimSystem
## National spirits: at the start of a campaign each realm gets up to three of them from its own geography;
## afterwards they evolve (or wither) with what the realm actually does — the registers in KingdomState.records.
## A realm carries at most four at once (consolidation: six at once, each with small percentages, made a list
## nobody remembered; now a few spirits that matter, each with an origin and an evolution).
## Everything is data (data/defs/national_spirits.json); this system only measures the facts and applies the rules.

const MAX_INITIAL := 3
## A realm carries at most this many spirits: the land's and the ones it earned (Phase 17: six; consolidation: four).
const MAX_SPIRITS := 4


func _init() -> void:
	id = &"national_spirits"
	frequency = Frequency.MONTH
	order = 35


## Measurable facts of a realm: geography of its provinces plus its registers.
static func facts(session: GameSession, k: KingdomState) -> Dictionary:
	var world := session.world
	var wd := WorldData.get_instance()
	var out := {"provinces": float(k.provinces.size()), "population": 0.0, "treasury": k.treasury}
	var forest := 0.0
	var mountain := 0.0
	var coast := 0.0
	var river := 0.0
	var fertility := 0.0
	var iron := 0.0
	var stone := 0.0
	var neighbours := {}
	for pid in k.provinces:
		var g := wd.province_geo(pid)
		var p := world.province(pid)
		forest += g.forest
		fertility += g.fertility
		mountain += 1.0 if g.terrain == &"mountains" else 0.0
		coast += 1.0 if g.coastal else 0.0
		river += 1.0 if g.has_river else 0.0
		out["population"] = float(out["population"]) + float(p.population if p else 0)
		for dep in g.deposits:
			if dep["type"] == &"iron":
				iron += 1.0
			elif dep["type"] == &"stone":
				stone += 1.0
		for n in g.neighbors:
			var owner := world.owner_of(int(n["id"]))
			if owner and owner.id != k.id:
				neighbours[owner.id] = true
	var n := maxf(float(k.provinces.size()), 1.0)
	out["forest_share"] = forest / n
	out["fertility_avg"] = fertility / n
	out["mountain_share"] = mountain / n
	out["coast_share"] = coast / n
	out["river_share"] = river / n
	out["iron_deposits"] = iron
	out["stone_deposits"] = stone
	out["neighbour_realms"] = float(neighbours.size())
	out["years_at_peace"] = float(world.day - int(k.records.get(&"last_war_day", 0))) / 360.0
	for key: StringName in k.records.keys():
		out["record_%s" % key] = float(k.records[key])
	return out


## Up to three spirits from the land itself, the day the realm is founded.
static func grant_initial(session: GameSession, k: KingdomState) -> void:
	var f := facts(session, k)
	var candidates: Array[NationalSpiritDef] = []
	for sp: NationalSpiritDef in Defs.all("national_spirits"):
		if sp.initial and sp.can_gain(f):
			candidates.append(sp)
	for sp in candidates:
		if k.spirits.size() >= MAX_INITIAL:
			break
		_add(session, k, sp.id, false)


static func _add(session: GameSession, k: KingdomState, spirit_id: StringName, announce: bool = true) -> void:
	if k.spirits.has(spirit_id):
		return
	k.spirits.append(spirit_id)
	k.spirit_since[spirit_id] = session.world.day
	k.identity_changed()
	var sp: NationalSpiritDef = Defs.get_def("national_spirits", spirit_id)
	if announce and sp:
		if k.is_player:   # the spirits of the other crowns are for the chronicle, not for the player's news
			EventBus.notify("Nuovo spirito del regno", "%s: %s" % [sp.display_name, sp.description], &"spirit")
		EventBus.chronicle_written.emit({"day": session.world.day, "kingdom": k.id, "kind": "spirit_gained",
			"text": "%s è ora %s." % [k.name, sp.display_name.to_lower()]})


## A spirit that is gone: the woods grew back, the famine was forgotten, the debts were paid.
static func _fade(session: GameSession, k: KingdomState, spirit_id: StringName) -> void:
	var idx := k.spirits.find(spirit_id)
	if idx < 0:
		return
	k.spirits.remove_at(idx)
	k.spirit_since.erase(spirit_id)
	if not k.spirits_past.has(spirit_id):
		k.spirits_past.append(spirit_id)
	k.identity_changed()
	var sp: NationalSpiritDef = Defs.get_def("national_spirits", spirit_id)
	var name := sp.display_name if sp else String(spirit_id)
	if k.is_player:
		EventBus.notify("Uno spirito del regno svanisce", "%s non è più ciò che il regno è." % name, &"spirit")
	EventBus.chronicle_written.emit({"day": session.world.day, "kingdom": k.id, "kind": "spirit_lost",
		"text": "%s non è più %s." % [k.name, name.to_lower()]})


## A realm that carries more spirits than it can (a save from before the consolidation, which allowed six) lets
## one go each year until it is back to four: the oldest earned one first — a deed fades into history before the
## land does — else the oldest of all.
static func _make_room(session: GameSession, k: KingdomState) -> void:
	var oldest := &""
	var oldest_day := 1 << 30
	for pass_earned: bool in [true, false]:
		for spirit_id in k.spirits:
			var sp: NationalSpiritDef = Defs.get_def("national_spirits", spirit_id)
			if pass_earned and (sp == null or not sp.earned):
				continue
			var since := int(k.spirit_since.get(spirit_id, 0))
			if since < oldest_day:
				oldest_day = since
				oldest = spirit_id
		if oldest != &"":
			break
	if oldest != &"":
		_fade(session, k, oldest)


static func _replace(session: GameSession, k: KingdomState, old_id: StringName, new_id: StringName) -> void:
	var idx := k.spirits.find(old_id)
	if idx < 0:
		return
	k.spirits.remove_at(idx)
	k.spirit_since.erase(old_id)
	k.identity_changed()
	if not k.spirits_past.has(old_id):
		k.spirits_past.append(old_id)
	_add(session, k, new_id, false)
	var old_def: NationalSpiritDef = Defs.get_def("national_spirits", old_id)
	var new_def: NationalSpiritDef = Defs.get_def("national_spirits", new_id)
	if new_def:
		if k.is_player:
			EventBus.notify("Lo spirito del regno cambia", "%s diventa %s: %s" % [
				old_def.display_name if old_def else old_id, new_def.display_name, new_def.description], &"spirit")
		EventBus.chronicle_written.emit({"day": session.world.day, "kingdom": k.id, "kind": "spirit_evolved",
			"text": "%s: %s diventa %s." % [k.name, old_def.display_name.to_lower() if old_def else old_id, new_def.display_name.to_lower()]})


func run(session: GameSession, step: SimStep) -> void:
	var world := session.world
	for k in world.kingdoms:
		if not k.alive:
			continue
		if k.spirits.is_empty() and not bool(k.records.get(&"spirits_seeded", 0.0)):
			k.records[&"spirits_seeded"] = 1.0
			grant_initial(session, k)
			continue
		if step.is_new_year and k.spirits.size() > MAX_SPIRITS:
			_make_room(session, k)
		var f := facts(session, k)
		for spirit_id in k.spirits.duplicate():
			var sp: NationalSpiritDef = Defs.get_def("national_spirits", spirit_id)
			if sp == null:
				continue
			# how long the realm has carried it: a memory can fade with the years
			f["held_years"] = float(world.day - int(k.spirit_since.get(spirit_id, world.day))) / float(PersonState.DAYS_PER_YEAR)
			for evolution: Dictionary in sp.evolves:
				if NationalSpiritDef.matches(evolution["when"], f):
					if StringName(evolution["to"]) == &"":
						_fade(session, k, spirit_id)
					else:
						_replace(session, k, spirit_id, evolution["to"])
					break
		f.erase("held_years")
		# what the realm does can earn it a spirit at any time: trade, battles, laws, knowledge, lands, a dynasty
		if k.spirits.size() < MAX_SPIRITS:
			for sp: NationalSpiritDef in Defs.all("national_spirits"):
				if sp.earned and not k.spirits.has(sp.id) and not k.spirits_past.has(sp.id) and sp.can_gain(f):
					_add(session, k, sp.id)
					break
		# a realm that grows into new lands can also earn a new spirit
		if k.spirits.size() < MAX_INITIAL:
			for sp: NationalSpiritDef in Defs.all("national_spirits"):
				if sp.initial and not k.spirits.has(sp.id) and not k.spirits_past.has(sp.id) and sp.can_gain(f):
					_add(session, k, sp.id)
					break

