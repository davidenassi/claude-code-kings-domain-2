class_name KingdomModifiers
extends RefCounted
## The state of a realm as a sum of named sources: culture (fixed), religion (fixed), national spirits (dynamic),
## and later ruler, laws and events. Every system asks its number here, so any effect is inspectable in the UI
## (ModifierStack.breakdown) and no value is hidden in code.

const RUNTIME_KEY := "kingdom_modifiers"


## Cached stack of a realm; rebuilt when its spirits change.
static func stack(session: GameSession, kingdom_id: int) -> ModifierStack:
	var cache: Dictionary = session.runtime.get(RUNTIME_KEY, {})
	var k := session.world.kingdom(kingdom_id)
	if k == null:
		return ModifierStack.new()
	var entry: Array = cache.get(kingdom_id, [])
	if not entry.is_empty() and int(entry[0]) == k.identity_version:
		return entry[1]
	var st := ModifierStack.new()
	var culture: CultureDef = Defs.get_def("cultures", k.culture)
	if culture:
		st.set_source("culture:%s" % k.culture, culture.modifiers, "Cultura %s" % culture.display_name)
	var religion: ReligionDef = Defs.get_def("religions", k.religion)
	if religion:
		st.set_source("religion:%s" % k.religion, religion.modifiers, "Religione %s" % religion.display_name)
	for spirit_id in k.spirits:
		var sp: NationalSpiritDef = Defs.get_def("national_spirits", spirit_id)
		if sp:
			st.set_source("spirit:%s" % spirit_id, sp.modifiers, sp.display_name)
	# where the royal house comes from (Phase 15): farmers, craftsmen, men of arms, the most esteemed family
	if k.house_origin != &"":
		var origin := CourtSystem.origin_def(k.house_origin)
		if not origin.is_empty():
			st.set_source("house_origin", Modifier.list_from_array(origin.get("modifiers", [])),
				"%s: %s" % [k.house, String(origin.get("name", k.house_origin))])
	var ruler := session.world.ruler_of(k.id)
	if ruler:
		var ruler_mods: Array[Modifier] = []
		for td in ruler.trait_defs():
			ruler_mods.append_array(td.modifiers)
		# a good administrator holds a wider realm together, a good diplomat trades better
		ruler_mods.append(Modifier.new(&"administration.control", Modifier.Op.ADD, (ruler.skill(&"governo") - 5) * 0.012))
		ruler_mods.append(Modifier.new(&"trade.income", Modifier.Op.MUL, 1.0 + (ruler.skill(&"diplomazia") - 5) * 0.01))
		st.set_source("ruler", ruler_mods, "%s %s" % ["Regina" if ruler.female else "Re", ruler.name])
	for group: StringName in k.laws.keys():
		var law := Laws.option(group, k.laws[group])
		if not law.is_empty():
			st.set_source("law:%s" % group, Modifier.list_from_array(law.get("modifiers", [])), "Legge: %s" % law.get("name", group))
	for edict_id: StringName in k.edicts.keys():
		var ed := Laws.edict(edict_id)
		if not ed.is_empty():
			st.set_source("edict:%s" % edict_id, Modifier.list_from_array(ed.get("modifiers", [])), "Editto: %s" % ed.get("name", edict_id))
	for tech_id in k.technologies:
		var tech := Technologies.item(tech_id)
		if not tech.is_empty():
			st.set_source("tech:%s" % tech_id, Modifier.list_from_array(tech.get("modifiers", [])),
				"Sapere: %s" % tech.get("name", tech_id))
	for crisis: Dictionary in k.crises:
		st.set_source("crisis:%s" % crisis["id"], Modifier.list_from_array(crisis.get("modifiers", [])),
			String(crisis.get("name", "Crisi")))
	for pact_source: Dictionary in Diplomacy.pact_modifiers(session.world, k.id):
		st.set_source(String(pact_source["id"]), Modifier.list_from_array(pact_source["modifiers"]), String(pact_source["label"]))
	cache[kingdom_id] = [k.identity_version, st]
	session.runtime[RUNTIME_KEY] = cache
	return st


## base with every modifier of the realm applied; `extra_keys` are summed on top (e.g. irrigated fields).
static func value(session: GameSession, kingdom_id: int, key: StringName, base: float, extra_keys: Array = []) -> float:
	var st := stack(session, kingdom_id)
	var out := st.apply(key, base)
	for extra in extra_keys:
		out *= st.multiplier(StringName(extra))
		out += st.additive(StringName(extra))
	return out


## Same, for a settlement (reads the realm that owns it).
static func settlement_value(session: GameSession, s: SettlementState, key: StringName, base: float, extra_keys: Array = []) -> float:
	return value(session, s.kingdom, key, base, extra_keys)


## Registers of what the realm really did (they feed the national spirits).
static func record(world: WorldState, kingdom_id: int, key: StringName, amount: float) -> void:
	var k := world.kingdom(kingdom_id)
	if k == null or amount == 0.0:
		return
	k.records[key] = float(k.records.get(key, 0.0)) + amount

