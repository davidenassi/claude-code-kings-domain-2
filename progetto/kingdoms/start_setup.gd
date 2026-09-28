class_name StartSetup
extends RefCounted
## Builds the initial political situation of the official map from data/defs/start_setup.json (decisions D1/D2):
## the player's frontier valley, formed kingdoms, minor lordships and free lands.
## Fully deterministic: it depends only on the fixed map and the data file, never on the campaign seed.

const CONFIG_PATH := "res://data/defs/start_setup.json"

var cfg: Dictionary
var wd: WorldData
var world: WorldState
var warnings: PackedStringArray = PackedStringArray()

var _reserved: Dictionary = {}   # province id -> true (kept free around the player)


static func apply(world_state: WorldState, config: Dictionary = {}) -> StartSetup:
	var s := StartSetup.new()
	s.world = world_state
	s.wd = WorldData.get_instance()
	s.cfg = config if not config.is_empty() else Defs.read_json(CONFIG_PATH)
	s._build()
	for w in s.warnings:
		KDLog.warn("setup", w)
	return s


func _build() -> void:
	world.provinces.clear()
	world.kingdoms.clear()
	for g in wd.provinces:
		var p := ProvinceState.new()
		p.id = g.id
		p.culture = g.culture
		p.religion = g.religion
		world.provinces.append(p)

	var pc: Dictionary = cfg["player"]
	var start := pick_player_province(pc)
	# the player does not begin with a realm: six people, no crown, no house. The name is the community's,
	# and the arms are those of a place, not of a family — the house arrives when the monarchy is founded.
	var place := wd.provinces[start].name
	var player := _new_realm(KingdomState.Rank.SETTLEMENT, &"player",
		String(pc.get("realm_name", "Comunità di {province}")).format({"province": place}),
		place, start, Color.html(String(pc.get("color", "#2F4F9E"))))
	player.house = ""
	player.monarchy_founded = false
	player.is_player = true
	world.player_kingdom = player.id
	world.set_province_owner(start, player.id)
	for pid in provinces_within_steps(start, int(pc.get("free_buffer_steps", 2))):
		_reserved[pid] = true

	var targets := {}   # kingdom id -> province target
	var frontier: Array = []
	for kc: Dictionary in cfg.get("kingdoms", []):
		var seed_p := _pick_seed(_anchor(kc), StringName(kc.get("culture", "")))
		if seed_p < 0:
			warnings.append("no free province for kingdom %s" % kc.get("id", "?"))
			continue
		var k := _new_realm(KingdomState.Rank.KINGDOM, StringName(kc["id"]), String(kc["name"]), String(kc["house"]),
			seed_p, Color.html(String(kc["color"])))
		targets[k.id] = int(kc.get("provinces", 8))
		world.set_province_owner(seed_p, k.id)
		frontier.append([0.0, k.id, seed_p])
	var lordship_colors: Array = cfg.get("lordship_colors", ["#6B5B3E"])
	var li := 0
	for lc: Dictionary in cfg.get("lordships", []):
		var seed_p := _pick_seed(_anchor(lc), StringName(lc.get("culture", "")))
		if seed_p < 0:
			warnings.append("no free province for lordship at %s" % str(lc.get("anchor")))
			continue
		var capital_name := wd.provinces[seed_p].name
		var k := _new_realm(KingdomState.Rank.LORDSHIP, &"", "Signoria di %s" % capital_name, "Casa di %s" % capital_name,
			seed_p, Color.html(String(lordship_colors[li % lordship_colors.size()])))
		li += 1
		targets[k.id] = int(lc.get("provinces", 2))
		world.set_province_owner(seed_p, k.id)
		frontier.append([0.0, k.id, seed_p])
	_grow(frontier, targets)
	_populate()


func _new_realm(rank: KingdomState.Rank, key: StringName, realm_name: String, house: String, capital: int, color: Color) -> KingdomState:
	var g := wd.provinces[capital]
	var k := KingdomState.new()
	k.id = world.kingdoms.size()
	k.key = key
	k.rank = rank
	k.name = realm_name
	k.house = house
	k.culture = g.culture
	k.religion = g.religion
	k.color = color
	k.capital = capital
	k.coat_of_arms = CoatOfArms.generate(house, k.culture, color)
	world.kingdoms.append(k)
	return k


static func _anchor(entry: Dictionary) -> Vector2:
	var a: Array = entry.get("anchor", [0, 0])
	return Vector2(float(a[0]), float(a[1]))


## The player's frontier valley: nearest province to the anchor that satisfies the requirements.
## Requirements are relaxed one at a time (with a warning) if the map ever stops offering a match.
func pick_player_province(pc: Dictionary) -> int:
	var anchor := _anchor(pc)
	var req: Dictionary = (pc.get("require", {}) as Dictionary).duplicate()
	var relax_order := ["deposit", "coastal", "min_forest", "river", "min_fertility"]
	while true:
		var best := -1
		var best_d := INF
		for g in wd.provinces:
			var d := g.center.distance_to(anchor)
			if d > float(pc.get("search_radius_m", 15000.0)) or d >= best_d:
				continue
			if g.culture != StringName(pc.get("culture", g.culture)) or g.religion != StringName(pc.get("religion", g.religion)):
				continue
			if _meets(g, req):
				best = g.id
				best_d = d
		if best >= 0:
			return best
		if relax_order.is_empty():
			break
		var dropped: String = relax_order.pop_front()
		if req.has(dropped):
			req.erase(dropped)
			warnings.append("player start: requirement '%s' relaxed" % dropped)
	return wd.province_at(anchor) if wd.province_at(anchor) >= 0 else 0


static func _meets(g: ProvinceGeo, req: Dictionary) -> bool:
	if req.has("river") and g.has_river != bool(req["river"]):
		return false
	if req.has("coastal") and g.coastal != bool(req["coastal"]):
		return false
	if g.forest < float(req.get("min_forest", 0.0)) or g.fertility < float(req.get("min_fertility", 0.0)):
		return false
	if req.has("deposit"):
		var found := false
		for dep in g.deposits:
			if dep["type"] == StringName(req["deposit"]):
				found = true
				break
		if not found:
			return false
	return true


## Nearest unclaimed, unreserved province to the anchor, preferring the requested culture.
func _pick_seed(anchor: Vector2, culture: StringName) -> int:
	var best := -1
	var best_score := INF
	for g in wd.provinces:
		if _reserved.has(g.id) or not world.provinces[g.id].is_free():
			continue
		var score := g.center.distance_to(anchor) + (0.0 if culture == &"" or g.culture == culture else 20000.0)
		if score < best_score:
			best_score = score
			best = g.id
	return best


func provinces_within_steps(origin: int, steps: int) -> PackedInt32Array:
	var out := PackedInt32Array([origin])
	var seen := {origin: true}
	var ring := [origin]
	for s in steps:
		var next := []
		for pid: int in ring:
			for n in wd.provinces[pid].neighbors:
				var q := int(n["id"])
				if not seen.has(q):
					seen[q] = true
					next.append(q)
					out.append(q)
		ring = next
	return out


## Simultaneous growth of every realm from its capital (Dijkstra on the province graph): cheap borders are
## crossed first, rivers/passes/mountains and foreign cultures slow expansion, so realms end up following geography.
func _grow(frontier: Array, targets: Dictionary) -> void:
	var gc: Dictionary = cfg.get("growth_costs", {})
	var border_cost: Dictionary = gc.get("border", {})
	var counts := {}
	for k in targets.keys():
		counts[k] = 1
	var open: Array = []
	for f: Array in frontier:
		_push_neighbors(open, f[1], f[2], 0.0, border_cost, gc)
	while not open.is_empty():
		var bi := 0
		for i in range(1, open.size()):
			if float(open[i][0]) < float(open[bi][0]):
				bi = i
		var e: Array = open[bi]
		open[bi] = open[open.size() - 1]
		open.pop_back()
		var kid: int = e[1]
		var pid: int = e[2]
		if int(counts[kid]) >= int(targets[kid]) or _reserved.has(pid) or not world.provinces[pid].is_free():
			continue
		world.set_province_owner(pid, kid)
		counts[kid] = int(counts[kid]) + 1
		_push_neighbors(open, kid, pid, float(e[0]), border_cost, gc)
	for k in targets.keys():
		if int(counts[k]) < int(targets[k]):
			warnings.append("%s reached %d of %d provinces" % [world.kingdoms[k].name, counts[k], targets[k]])


func _push_neighbors(open: Array, kid: int, pid: int, base: float, border_cost: Dictionary, gc: Dictionary) -> void:
	var k := world.kingdoms[kid]
	for n in wd.provinces[pid].neighbors:
		var q := int(n["id"])
		if not world.provinces[q].is_free() or _reserved.has(q):
			continue
		var g := wd.provinces[q]
		var c := base + float(border_cost.get(String(n["type"]), 1.0))
		if g.culture != k.culture:
			c += float(gc.get("other_culture", 4.0))
		if g.religion != k.religion:
			c += float(gc.get("other_religion", 2.0))
		if g.terrain == &"mountains":
			c += float(gc.get("mountain_province", 1.5))
		open.append([c, kid, q])


func _populate() -> void:
	var pop: Dictionary = cfg.get("population", {})
	var dev: Dictionary = cfg.get("development", {})
	var pc: Dictionary = cfg["player"]
	for p in world.provinces:
		var g := wd.provinces[p.id]
		var k := world.kingdom(p.owner)
		if k and k.is_player:
			p.population = int(pc.get("population", 7))
			p.development = int(pc.get("development", 0))
			continue
		var density := float(pop.get("base_per_km2", 3.0)) + float(pop.get("fertility_per_km2", 22.0)) * g.fertility
		density *= 1.0 - float(pop.get("forest_malus", 0.45)) * g.forest
		if k:
			density *= float(pop.get("owned_bonus", 1.35))
			if k.capital == p.id:
				density *= float(pop.get("capital_bonus", 2.2))
		p.population = maxi(int(round(g.area_km2 * density)), 10)
		if k == null:
			p.development = int(dev.get("free", 1))
		elif k.capital == p.id:
			p.development = int(dev.get("capital", 4))
		else:
			p.development = int(dev.get("kingdom" if k.rank == KingdomState.Rank.KINGDOM else "lordship", 2))

