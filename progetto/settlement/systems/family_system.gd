class_name FamilySystem
extends SimSystem
## The families of the community (Phase 15). Free adults pair up — a union makes a household under the husband's
## surname, the wife's family of origin stays on record — and the register of every family grows with what its
## members do: days in the fields, in the workshops, under arms. That register is where a royal house comes from.
##
## The chronicle writes down the first steps of the community here, because the story of a realm begins before its
## crown: the unions of the founders, the first house, the first harvest, the day the settlement becomes a village.

const FIRST_HOUSE := &"chronicle_first_house"
const FIRST_HARVEST := &"chronicle_first_harvest"
const VILLAGE := &"chronicle_village"
const EXTINCT := &"chronicle_extinct"


func _init() -> void:
	id = &"families"
	frequency = Frequency.DAY
	order = 24   # before the population (25): a couple formed today can have a child tomorrow


static func bal() -> Dictionary:
	return Defs.balance("families")


func run(session: GameSession, step: SimStep) -> void:
	if not step.is_new_month:
		return
	var world := session.world
	for s in world.settlements:
		_pair(session, s, step.day)
		_record_work(world, s)
	_authority(world)
	_milestones(session, step.day)


# --- unions ----------------------------------------------------------------------------------------------

## Free adults of the same settlement pair up: every free woman has a chance each month to find a free man close
## to her age and not of her own blood. The founders, alone in an empty valley, find each other sooner.
func _pair(session: GameSession, s: SettlementState, day: int) -> void:
	var world := session.world
	var cfg: Dictionary = bal().get("pairing", {})
	var min_age := int(cfg.get("min_age", 17))
	var woman_max := int(cfg.get("woman_max_age", 42))
	var gap := int(cfg.get("max_age_gap", 12))
	var women: Array[PersonState] = []
	var men: Array[PersonState] = []
	for p in world.people_of(s.id):
		if p.job == &"soldier" or p.job == &"child" or p.age_years(day) < min_age:
			continue
		if p.spouse >= 0 and world.person(p.spouse) != null:
			continue
		p.spouse = -1   # a widow or a widower is free again
		if p.female:
			if p.age_years(day) <= woman_max:
				women.append(p)
		else:
			men.append(p)
	if women.is_empty() or men.is_empty():
		return
	var rng := world.rng.stream(&"families")
	for w in women:
		var founding := _is_founder(world, w)
		var chance := float(cfg.get("founder_monthly_chance", 0.55)) if founding else float(cfg.get("monthly_chance", 0.22))
		if rng.randf() >= chance:
			continue
		var best: PersonState = null
		var best_gap := gap + 1
		for m in men:
			if m.spouse >= 0 or _same_blood(w, m):
				continue
			var g := absi(m.age_years(day) - w.age_years(day))
			if g < best_gap:
				best_gap = g
				best = m
		if best:
			unite(session, best, w, day)


static func _is_founder(world: WorldState, p: PersonState) -> bool:
	var f := world.family(p.born_family)
	return f != null and f.founding and f.founders.has(p.id)


## Brothers and sisters, parents and children do not marry.
static func _same_blood(a: PersonState, b: PersonState) -> bool:
	if a.mother >= 0 and a.mother == b.mother:
		return true
	if a.father >= 0 and a.father == b.father:
		return true
	return a.mother == b.id or a.father == b.id or b.mother == a.id or b.father == a.id


## A union: the wife joins the husband's family, they share a home, and — for the founders — the chronicle takes
## note, because these are the first families of the story.
static func unite(session: GameSession, man: PersonState, woman: PersonState, day: int) -> void:
	var world := session.world
	man.spouse = woman.id
	woman.spouse = man.id
	woman.family = man.family
	if man.home >= 0:
		woman.home = man.home
	var f := world.family(man.family)
	if f and f.founders.size() < 2 and f.founders.has(man.id):
		f.founders.append(woman.id)   # a founding family is the couple, not the man alone
	var surname := f.name if f else ""
	var realm := world.kingdom(world.settlement(man.settlement).kingdom) if world.settlement(man.settlement) else null
	var names := "%s e %s" % [SettlementSetup.full_name(world, man), "%s %s" % [woman.name, _born_surname(world, woman)]]
	if _is_founder(world, man) or _is_founder(world, woman):
		EventBus.chronicle_written.emit({"day": day, "kingdom": realm.id if realm else -1, "kind": "founding_family",
			"text": "%s si uniscono: nasce la famiglia %s." % [names, surname]})
		EventBus.notify("Una nuova famiglia", "%s si uniscono: nasce la famiglia %s." % [names, surname], &"birth")
	else:
		EventBus.notify("Nozze nel villaggio", "%s si sposano." % names, &"birth")
	if realm and realm.monarchy_founded:
		CourtSystem.on_village_union(session, realm, man, woman)
	SettlementSim.mark_assignment_dirty(session, man.settlement)
	EventBus.settlement_changed.emit(man.settlement)


static func _born_surname(world: WorldState, p: PersonState) -> String:
	var f := world.family(p.born_family)
	return f.name if f else ""


# --- what the families do ----------------------------------------------------------------------------------

## A month of work goes on the register of each family: this is how, years later, a house knows where it
## comes from (farmers, craftsmen, men of arms).
static func _record_work(world: WorldState, s: SettlementState) -> void:
	for p in world.people_of(s.id):
		if p.family < 0:
			continue
		var f := world.family(p.family)
		if f and p.job != &"idle" and p.job != &"child":
			f.record(p.job, 30.0)


# --- the first pages of the chronicle -----------------------------------------------------------------------

func _milestones(session: GameSession, day: int) -> void:
	var world := session.world
	var k := world.player()
	if k == null:
		return
	var home: SettlementState = null
	for s in world.settlements:
		if s.kingdom == k.id:
			home = s
			break
	if home == null:
		return
	# the end: nobody lives any more in the settlements of the realm — the valley is empty again
	var living := 0
	for s in world.settlements:
		if s.kingdom == k.id:
			living += world.people_of(s.id).size()
	if living == 0:
		if not k.records.has(EXTINCT):
			k.records[EXTINCT] = float(day)
			var what := "Il %s" % k.name if k.monarchy_founded else "La %s" % k.name
			EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "founding_extinct",
				"text": "%s finisce: a %s non vive più nessuno. Le case restano vuote e il bosco torna a prendersi i campi." % [what, home.name]})
			EventBus.notify_local("Non resta nessuno", "A %s non vive più nessuno." % home.name, &"death", home.center)
		return
	if not k.records.has(FIRST_HOUSE):
		for b in world.buildings_of(home.id):
			if b.is_active() and b.def_id == &"house":
				k.records[FIRST_HOUSE] = float(day)
				EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "founding_first_house",
					"text": "A %s si alza la prima casa: non più una tettoia di frasche, ma un tetto e quattro letti." % home.name})
				break
	if not k.records.has(FIRST_HARVEST) and float(k.records.get(&"grain", 0.0)) > 0.0:
		k.records[FIRST_HARVEST] = float(day)
		EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "founding_harvest",
			"text": "Il primo raccolto di %s: %d misure di grano portate dai campi." % [home.name, roundi(float(k.records[&"grain"]))]})
	var village_at := int(bal().get("monarchy", {}).get("min_people", 30))
	if not k.records.has(VILLAGE) and world.people_of(home.id).size() >= village_at:
		k.records[VILLAGE] = float(day)
		EventBus.chronicle_written.emit({"day": day, "kingdom": k.id, "kind": "founding_village",
			"text": "%s diventa un villaggio: %d anime, e le famiglie cominciano a chiedersi chi le guiderà." % [
				home.name, world.people_of(home.id).size()]})
		EventBus.notify("Un villaggio", "%s conta ormai %d anime." % [home.name, world.people_of(home.id).size()], &"realm")


# --- the community before the crown: authority -------------------------------------------------------------

## Families of a settlement with enough living members to count as rooted.
static func consolidated_families(world: WorldState, s: SettlementState) -> Array[FamilyState]:
	var min_members := int(bal().get("monarchy", {}).get("family_min_members", 3))
	var counts := {}
	for p in world.people_of(s.id):
		if p.family >= 0:
			counts[p.family] = int(counts.get(p.family, 0)) + 1
	var out: Array[FamilyState] = []
	for fid: int in counts.keys():
		var f := world.family(fid)
		if f and int(counts[fid]) >= min_members:
			out.append(f)
	out.sort_custom(func(a: FamilyState, b: FamilyState) -> bool: return a.id < b.id)
	return out


## Families with at least one living member in the settlement, founding families first.
static func living_families(world: WorldState, s: SettlementState) -> Array[FamilyState]:
	var seen := {}
	for p in world.people_of(s.id):
		if p.family >= 0:
			seen[p.family] = true
	var out: Array[FamilyState] = []
	for fid: int in seen.keys():
		var f := world.family(fid)
		if f:
			out.append(f)
	out.sort_custom(func(a: FamilyState, b: FamilyState) -> bool:
		if a.founding != b.founding:
			return a.founding
		return a.founded_day < b.founded_day)
	return out


## Where the authority of the community comes from, part by part (the tooltip reads these):
## {"Fiducia": 21.0, "Famiglie radicate": 12.0, ...} plus "_target".
static func authority_parts(world: WorldState, k: KingdomState) -> Dictionary:
	var cfg: Dictionary = bal().get("authority", {})
	var parts := {}
	var home: SettlementState = null
	for s in world.settlements:
		if s.kingdom == k.id:
			home = s
			break
	if home == null:
		return {"_target": 0.0}
	parts["Base"] = float(cfg.get("base", 10.0))
	parts["Fiducia degli abitanti"] = home.trust * float(cfg.get("trust_weight", 0.35))
	var rooted := mini(consolidated_families(world, home).size(), int(cfg.get("families_cap", 5)))
	parts["Famiglie radicate"] = rooted * float(cfg.get("per_family", 6.0))
	var food := PopulationSystem.food_days(world, home)
	parts["Cibo sicuro"] = clampf(food / float(cfg.get("food_days_full", 180.0)), 0.0, 1.0) * float(cfg.get("food_weight", 15.0))
	var standing := 0
	for b in world.buildings_of(home.id):
		if b.is_active() and not b.is_road():
			standing += 1
	parts["Edifici in piedi"] = mini(standing, int(cfg.get("buildings_cap", 15))) * float(cfg.get("per_building", 1.2))
	var years := mini((world.day - k.founded_day) / PersonState.DAYS_PER_YEAR, int(cfg.get("years_cap", 8)))
	parts["Anni insieme"] = years * float(cfg.get("per_year", 2.0))
	var total := 0.0
	for key: String in parts.keys():
		total += float(parts[key])
	parts["_target"] = clampf(total, 0.0, 100.0)
	return parts


## Once a month the authority of a community with no crown moves toward what its facts say.
static func _authority(world: WorldState) -> void:
	var cfg: Dictionary = bal().get("authority", {})
	for k in world.kingdoms:
		if k.monarchy_founded or not k.alive:
			continue
		var target := float(authority_parts(world, k).get("_target", 0.0))
		k.authority = lerpf(k.authority, target, clampf(float(cfg.get("chase_per_month", 0.15)), 0.0, 1.0))


# --- what the interface shows of a family -------------------------------------------------------------------

## The influence of a family in the community (0..100): a founding family, the years, the members, the children,
## the work done for everybody. It was called «reputazione» before the families moved into the estates.
## `members` can be passed when the caller already counted them (the members of every family, once).
static func influence(world: WorldState, f: FamilyState, members: int = -1) -> float:
	var score := 20.0 if f.founding else 5.0
	score += minf(float(world.day - f.founded_day) / PersonState.DAYS_PER_YEAR * 3.0, 24.0)
	score += minf(float(members if members >= 0 else world.members_of(f.id).size()) * 4.0, 24.0)
	score += minf(float(f.records.get(&"children", 0.0)) * 3.0, 15.0)
	var work := 0.0
	for key: StringName in f.records.keys():
		if key != &"children":
			work += float(f.records[key])
	score += minf(work / 360.0 * 2.0, 17.0)
	return clampf(score, 0.0, 100.0)


# --- the families inside the estates (consolidation) -----------------------------------------------------

## The royal house has an estate of its own: above the others, judged by all of them.
const ROYAL := &"royal"
## The estates in the order the sheet shows them (the royal house first).
const ESTATE_ORDER: Array[StringName] = [&"royal", &"nobility", &"clergy", &"merchants", &"army", &"people"]


static func estates_cfg() -> Dictionary:
	return bal().get("estates", {})


## The estate a family belongs to. The families live inside the estates (CETI): there is no second system. It is
## deduced every time from what the family is and has done, never stored, so a family of craftsmen that prospers
## is counted with the merchants and artisans, one full of soldiers with the army, and saves from before the
## consolidation are sorted by themselves. After the crown the royal house stands apart, and the nobility is made
## of the most influential houses — few of them — and of those married into the royal house (see noble_ids). The
## clergy has no families yet: there is no religious calling to read them from.
static func estate_of(world: WorldState, k: KingdomState, f: FamilyState) -> StringName:
	if k != null and k.monarchy_founded:
		var royal := CourtSystem.royal_family_of(world, k)
		if royal != null and royal.id == f.id:
			return ROYAL
		var s := world.settlement(f.settlement)
		if s != null and noble_ids(world, k, s).has(f.id):
			return &"nobility"
	return origin_estate(world, f)


## The estate of the work that fills the register of a family.
static func origin_estate(world: WorldState, f: FamilyState) -> StringName:
	var by_origin: Dictionary = estates_cfg().get("origin_estate", {})
	return StringName(by_origin.get(String(CourtSystem.origin_of(world, f)), "people"))


## The noble houses of a settlement: {family id: true}. Every family married into the royal house, and the most
## influential of the others (at least `noble_influence`), one house for every `noble_people_per_house`
## inhabitants (at least `noble_min_houses`), the older first when they weigh the same. Few on purpose: with the
## years the influence of a grown family reaches its ceiling, and a threshold alone made a fifth of the houses of
## a town of three hundred noble. Nothing before the crown. `members` (family id -> living members) can be
## passed by a caller that already counted them.
static func noble_ids(world: WorldState, k: KingdomState, s: SettlementState, members: Dictionary = {}) -> Dictionary:
	var out := {}
	if k == null or not k.monarchy_founded or s == null:
		return out
	var royal := CourtSystem.royal_family_of(world, k)
	var people := world.people_of(s.id)
	if members.is_empty():
		for p in people:
			if p.family >= 0:
				members[p.family] = int(members.get(p.family, 0)) + 1
	var kin := kin_of(world, royal)
	var cfg := estates_cfg()
	var threshold := float(cfg.get("noble_influence", 70.0))
	var ranked: Array = []
	for fid: int in members.keys():
		var f := world.family(fid)
		if f == null or (royal != null and fid == royal.id):
			continue
		if kin.has(fid):
			out[fid] = true
			continue
		var weight := influence(world, f, int(members[fid]))
		if weight >= threshold:
			ranked.append([weight, f.founded_day, fid])
	ranked.sort_custom(func(a: Array, b: Array) -> bool:
		if float(a[0]) != float(b[0]):
			return float(a[0]) > float(b[0])
		if int(a[1]) != int(b[1]):
			return int(a[1]) < int(b[1])
		return int(a[2]) < int(b[2]))
	var seats := maxi(int(cfg.get("noble_min_houses", 2)),
		ceili(float(people.size()) / maxf(float(cfg.get("noble_people_per_house", 40.0)), 1.0)))
	for i in mini(seats, ranked.size()):
		out[int(ranked[i][2])] = true
	return out


## The families with a living member married to a member of the royal house: {family id: true}.
static func kin_of(world: WorldState, royal: FamilyState) -> Dictionary:
	var out := {}
	if royal == null:
		return out
	for p: PersonState in world.people.values():
		if p.family < 0 or p.family == royal.id or p.spouse < 0:
			continue
		var spouse := world.person(p.spouse)
		if spouse and spouse.family == royal.id:
			out[p.family] = true
	return out


## True when a living member of the family is the husband or the wife of a member of the other one.
static func married_into(world: WorldState, f: FamilyState, other: FamilyState) -> bool:
	return other != null and other.id != f.id and kin_of(world, other).has(f.id)


## The living families of a settlement by estate, the most influential first: {estate: [[family, influence,
## members], ...]}. The members are counted once for all of them, and the nobility decided once.
static func families_by_estate(world: WorldState, k: KingdomState, s: SettlementState) -> Dictionary:
	var members := {}
	for p in world.people_of(s.id):
		if p.family >= 0:
			members[p.family] = int(members.get(p.family, 0)) + 1
	var royal := CourtSystem.royal_family_of(world, k) if k != null and k.monarchy_founded else null
	var nobles := noble_ids(world, k, s, members)
	var out := {}
	for fid: int in members.keys():
		var f := world.family(fid)
		if f == null:
			continue
		var n := int(members[fid])
		var estate := ROYAL if royal != null and fid == royal.id else (&"nobility" if nobles.has(fid) else origin_estate(world, f))
		var list: Array = out.get(estate, [])
		list.append([f, influence(world, f, n), n])
		out[estate] = list
	for estate: StringName in out.keys():
		(out[estate] as Array).sort_custom(func(a: Array, b: Array) -> bool:
			return float(a[1]) > float(b[1]) if float(a[1]) != float(b[1]) else (a[0] as FamilyState).id < (b[0] as FamilyState).id)
	return out


## The register in words: "342 giorni nei campi · 120 in bottega · 3 figli".
static func activity_text(f: FamilyState) -> String:
	var groups: Dictionary = bal().get("origin_jobs", {})
	var names := {"farmers": "nei campi", "artisans": "in bottega e nei cantieri", "soldiers": "in armi"}
	var parts := PackedStringArray()
	for origin: String in groups.keys():
		var days := 0.0
		for job: String in groups[origin]:
			days += float(f.records.get(StringName(job), 0.0))
		if days > 0.0:
			parts.append("%d giorni %s" % [roundi(days), String(names.get(origin, origin))])
	var kids := roundi(float(f.records.get(&"children", 0.0)))
	if kids > 0:
		parts.append("%d %s" % [kids, "figlio" if kids == 1 else "figli"])
	return " · ".join(parts) if not parts.is_empty() else "ancora nessun lavoro registrato"


## The essential tree: every couple of the family with its children, one line each.
static func tree_lines(world: WorldState, f: FamilyState) -> PackedStringArray:
	var lines := PackedStringArray()
	var members := world.members_of(f.id)
	var done := {}
	for p in members:
		if done.has(p.id):
			continue
		var spouse := world.person(p.spouse) if p.spouse >= 0 else null
		var head := "%s (%d)" % [p.name, p.age_years(world.day)]
		done[p.id] = true
		if spouse:
			head += " e %s (%d)" % [spouse.name, spouse.age_years(world.day)]
			done[spouse.id] = true
		var kids := PackedStringArray()
		for c in members:
			if c.mother == p.id or c.father == p.id:
				kids.append("%s (%d)" % [c.name, c.age_years(world.day)])
				done[c.id] = true
		if not kids.is_empty():
			head += " — figli: " + ", ".join(kids)
		elif _parent_in_family(world, p, f):
			continue   # a child is written under the parents, when they are still here to write it under
		lines.append(head)
	return lines


static func _parent_in_family(world: WorldState, p: PersonState, f: FamilyState) -> bool:
	for pid in [p.mother, p.father]:
		var parent := world.person(pid) if pid >= 0 else null
		if parent and parent.family == f.id:
			return true
	return false

