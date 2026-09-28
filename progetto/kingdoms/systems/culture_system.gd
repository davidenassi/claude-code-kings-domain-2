class_name CultureSystem
extends SimSystem
## Culture and religion are geography before they are politics: a province keeps its own until the crown, the
## neighbours and time slowly change it. A province that does not share the culture or the faith of its ruler
## grows restless, and restlessness eats the rents. Tolerance (religion modifier) softens all of it.


func _init() -> void:
	id = &"culture"
	frequency = Frequency.YEAR
	order = 45


static func bal() -> Dictionary:
	return Defs.balance("population").get("culture", {
		"assimilation_base": 0.04, "development_weight": 0.006, "neighbour_weight": 0.05,
		"unrest_per_year": 0.12, "unrest_relief": 0.06, "tolerance_scale": 0.02, "unrest_income_malus": 0.6,
	})


## 0..1: how much the province resists the crown (different culture, different faith, occupation).
static func friction(session: GameSession, province_id: int) -> float:
	var world := session.world
	var p := world.province(province_id)
	var k := world.kingdom(p.owner) if p else null
	if p == null or k == null:
		return 0.0
	var f := 0.0
	if p.culture != k.culture:
		f += 0.6
	if p.religion != k.religion:
		f += 0.4
	if p.is_occupied():
		f += 0.5
	var tolerance := KingdomModifiers.stack(session, k.id).additive(&"stability.tolerance")
	f -= tolerance * float(bal().get("tolerance_scale", 0.02))
	return clampf(f, 0.0, 1.5)


func run(session: GameSession, _step: SimStep) -> void:
	var world := session.world
	var wd := WorldData.get_instance()
	var cfg := bal()
	for p in world.provinces:
		var k := world.kingdom(p.owner)
		if k == null:
			p.unrest = maxf(p.unrest - float(cfg.get("unrest_relief", 0.06)), 0.0)
			continue
		var f := friction(session, p.id)
		if f <= 0.0:
			p.unrest = maxf(p.unrest - float(cfg.get("unrest_relief", 0.06)), 0.0)
		else:
			p.unrest = clampf(p.unrest + float(cfg.get("unrest_per_year", 0.12)) * f, 0.0, 1.0)
		# neighbours of the ruling culture make assimilation easier, and so does a developed province
		var same_neighbours := 0
		var neighbours := 0
		for n in wd.provinces[p.id].neighbors:
			var q := world.province(int(n["id"]))
			if q == null:
				continue
			neighbours += 1
			if q.culture == k.culture:
				same_neighbours += 1
		var pressure := float(cfg.get("assimilation_base", 0.04)) \
			+ float(cfg.get("development_weight", 0.006)) * p.development \
			+ float(cfg.get("neighbour_weight", 0.05)) * (float(same_neighbours) / maxf(float(neighbours), 1.0))
		pressure *= 1.0 - 0.5 * p.unrest
		# the pressure adds up year after year: a province changes when it has taken root, not on a lucky throw.
		# Slow and certain, and it can be read on the map (Phase 15: the old dice left a restless province
		# foreign for sixty years one time in three)
		p.assimilation = p.assimilation + pressure if p.culture != k.culture else 0.0
		p.conversion = p.conversion + pressure * 0.7 if p.religion != k.religion else 0.0
		if p.culture != k.culture and p.assimilation >= 1.0:
			p.culture = k.culture
			p.assimilation = 0.0
			EventBus.chronicle_written.emit({"day": world.day, "kingdom": k.id, "kind": "assimilation",
				"text": "%s parla ormai la lingua di %s." % [wd.provinces[p.id].name, k.name]})
		if p.religion != k.religion and p.conversion >= 1.0:
			p.religion = k.religion
			p.conversion = 0.0
			EventBus.chronicle_written.emit({"day": world.day, "kingdom": k.id, "kind": "conversion",
				"text": "%s ha cambiato fede sotto %s." % [wd.provinces[p.id].name, k.name]})

