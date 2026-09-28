class_name EconomySystem
extends SimSystem
## Every month: wages of the workers, taxes from the people, rents of the provinces, the prices of the regional
## market (scarcity against population) and the sale of what the villages have beyond their needs (Phase 16).
## Everything lands in the crown treasury, which can go into debt.
## Rules in data/defs/balance/population.json (sections "treasury", "trade" and "market").


func _init() -> void:
	id = &"economy"
	frequency = Frequency.MONTH
	order = 30


static func bal() -> Dictionary:
	return Defs.balance("population")


static func wages_per_day(world: WorldState, s: SettlementState) -> float:
	var table: Dictionary = bal().get("wages_gold_per_day", {})
	var total := 0.0
	for p in world.people_of(s.id):
		total += float(table.get(String(p.job), 0.05))
	return total


## Share of the rents that actually reaches the crown: the more provinces, the more dispersion.
static func admin_control(world: WorldState, k: KingdomState) -> float:
	var t: Dictionary = bal().get("treasury", {})
	var rng: Array = t.get("admin_control_range", [0.3, 1.0])
	return clampf(float(t.get("admin_control_base", 0.55)) - float(t.get("admin_control_per_province", 0.012)) * k.provinces.size(),
		float(rng[0]), float(rng[1]))


## What the standing buildings of a village cost every month to keep: roofs, mills, walls — a share of what they
## cost to build, paid in gold (Phase 16: buildings cost only wood and stone, so a grown realm had nothing to spend
## its gold on and hoarded a hundred and fifty thousand of it).
static func buildings_upkeep(world: WorldState, s: SettlementState) -> float:
	var share := float(bal().get("treasury", {}).get("upkeep_share_of_cost", 0.015))
	var total := 0.0
	for b in world.buildings_of(s.id):
		if not b.is_active():
			continue
		var cost := 0.0
		for res: StringName in b.def().cost.keys():
			var rd := Defs.resource(res)
			cost += float(b.def().cost[res]) * (rd.base_price if rd else 1.0)
		total += cost * share
	return total


## Share of the rents the administration of the realm eats: nothing for a handful of lands, more and more for an
## empire (provinces / provinces_for_all, capped).
static func administration_share(k: KingdomState) -> float:
	var t: Dictionary = bal().get("treasury", {})
	var n := maxf(float(k.provinces.size() - int(t.get("administration_free_provinces", 3))), 0.0)
	return clampf(n / maxf(float(t.get("administration_provinces_for_all", 60.0)), 1.0), 0.0,
		float(t.get("administration_max_share", 0.8)))


static func province_income(world: WorldState, k: KingdomState, province_id: int) -> float:
	var t: Dictionary = bal().get("treasury", {})
	var p := world.province(province_id)
	var g := WorldData.get_instance().province_geo(province_id)
	if p == null or g == null:
		return 0.0
	var unrest_malus := 1.0 - float(CultureSystem.bal().get("unrest_income_malus", 0.6)) * p.unrest
	var base := float(p.population) / maxf(float(t.get("province_income_population_divisor", 260.0)), 1.0)
	var value := base * (float(t.get("province_income_base", 0.55)) + float(t.get("province_income_per_development", 0.18)) * p.development)
	value *= (1.0 - 0.85 * p.devastation) * unrest_malus
	if p.is_occupied():
		value *= 0.15
	return value


func run(session: GameSession, step: SimStep) -> void:
	var world := session.world
	var t: Dictionary = bal().get("treasury", {})
	var days := float(session.calendar.days_per_month)
	for k in world.kingdoms:
		if not k.alive:
			continue
		var taxes := 0.0
		var wages := 0.0
		var upkeep := 0.0
		for s in world.settlements:
			if s.kingdom != k.id:
				continue
			taxes += KingdomModifiers.value(session, k.id, &"treasury.tax_income",
				world.people_of(s.id).size() * float(t.get("tax_per_person_month", 0.55)))
			wages += wages_per_day(world, s) * days
			upkeep += buildings_upkeep(world, s)
		# where the crown is obeyed the tax is collected; where it is not, it is evaded
		var collection := lerpf(float(t.get("stability_collection_min", 0.80)), 1.0, clampf(k.stability / 100.0, 0.0, 1.0))
		taxes *= collection
		var rents := 0.0
		var control := clampf(admin_control(world, k) + KingdomModifiers.stack(session, k.id).additive(&"administration.control"), 0.1, 1.2)
		for pid in k.provinces:
			rents += province_income(world, k, pid) * control
		rents = KingdomModifiers.value(session, k.id, &"trade.income", rents)
		# the officials, bailiffs and castellans of a wide realm eat a growing share of what its lands yield:
		# the soft limit of size (Phase 16), not a cap
		var admin := rents * administration_share(k)
		rents -= admin
		_update_prices(world, k)
		var trade := 0.0
		var imports := 0.0
		for s in world.settlements:
			if s.kingdom == k.id:
				trade += sell_surplus(session, k, s)
				imports += buy_shortage(session, k, s)
		trade = KingdomModifiers.value(session, k.id, &"trade.income", trade)
		var total := taxes + rents + trade - imports - wages - upkeep
		k.treasury += total
		k.last_balance = {"taxes": taxes, "provinces": rents, "administration": admin, "trade": trade,
			"imports": imports, "wages": wages, "upkeep": upkeep, "total": total, "collection": collection}
	if world.player() and world.player().treasury < 0.0 and step.is_new_year:
		EventBus.notify("Casse vuote", "Il tesoro della corona è in rosso: gli abitanti mormorano.", &"treasury")


## The merchants of the realm take what a village has beyond its reserve and pay the price of the market, as
## much as the market can take (it grows with the people of the realm). Food is sold only from a full year of
## stores that also reaches the harvest: a crown does not export the bread its people will need. Returns the
## gold; the goods leave the stores.
static func sell_surplus(session: GameSession, k: KingdomState, s: SettlementState) -> float:
	var world := session.world
	var cfg: Dictionary = bal().get("trade", {})
	var people := world.people_of(s.id).size()
	if people <= 0:
		return 0.0
	var reserves: Dictionary = cfg.get("reserve_per_person", {})
	var realm_people := 0
	for pid in k.provinces:
		realm_people += world.province(pid).population
	var depth := float(cfg.get("depth_base", 30.0)) + float(cfg.get("depth_per_person", 0.05)) * float(realm_people)
	var share := float(cfg.get("sell_share", 0.25))
	var cut := float(cfg.get("merchant_cut", 0.2))
	# food leaves only from a year of stores, or from granaries so full the next harvest would be lost anyway —
	# and never when the stores do not reach the harvest (Phase 16: with the honest count of the ovens a year of
	# food was never reached, and fifteen thousand measures of grain rotted in full granaries for decades)
	var granaries_full := s.space_for(world, &"grain") < int(float(s.capacity(world, &"food")) * float(cfg.get("food_full_share", 0.1)))
	var food_ok := (PopulationSystem.food_days(world, s) >= float(cfg.get("food_days_before_selling", 360.0)) or granaries_full) \
		and not bool(PopulationSystem.harvest_outlook(session, s)["short"])
	var gold := 0.0
	for res_name: String in reserves.keys():
		var res := StringName(res_name)
		var rd := Defs.resource(res)
		if rd == null or (rd.is_food and not food_ok):
			continue
		var surplus := s.amount(res) - int(float(reserves[res_name]) * people)
		if surplus <= 0:
			continue
		var units := mini(int(ceil(surplus * share)), int(depth))
		if units <= 0:
			continue
		var price := float(k.prices.get(res, rd.base_price))
		s.take(res, units, &"trade")
		gold += units * price * (1.0 - cut)
	if gold > 0.0:
		KingdomModifiers.record(world, k.id, &"trade_gold", gold)
	return gold


## The other way: what a village lacks to build (stone, wood, iron) the merchants bring from outside, dearer than
## the market, as far as the crown can pay without emptying its coffers. Returns the gold spent (Phase 16: the
## rocks near a village really run out, and a realm without stone stopped building for decades).
static func buy_shortage(session: GameSession, k: KingdomState, s: SettlementState) -> float:
	var world := session.world
	var cfg: Dictionary = bal().get("trade", {})
	var people := world.people_of(s.id).size()
	if people <= 0 or k.treasury < float(cfg.get("import_min_treasury", 120.0)):
		return 0.0
	var wanted: Dictionary = cfg.get("import_below_per_person", {})
	var markup := 1.0 + float(cfg.get("import_markup", 0.35))
	var budget := (k.treasury - float(cfg.get("import_min_treasury", 120.0))) * float(cfg.get("import_budget_share", 0.25))
	var depth := float(cfg.get("depth_base", 30.0))
	var spent := 0.0
	for res_name: String in wanted.keys():
		var res := StringName(res_name)
		var rd := Defs.resource(res)
		if rd == null:
			continue
		if not _needed(world, s, res):
			continue   # iron nobody works is not bought: a village without a smithy does not import ore
		var target := int(float(wanted[res_name]) * people)
		var lack := target - s.amount(res)
		if lack <= 0:
			continue
		var price := float(k.prices.get(res, rd.base_price)) * markup
		var units := mini(mini(lack, int(depth)), s.space_for(world, res))
		units = mini(units, int(floor((budget - spent) / maxf(price, 0.01))))
		if units <= 0:
			continue
		s.add(res, units, &"trade")
		spent += units * price
	if spent > 0.0:
		KingdomModifiers.record(world, k.id, &"import_gold", spent)
	return spent


## True when the village has a use for the good: building materials always, anything else only when a standing
## workshop takes it as input.
static func _needed(world: WorldState, s: SettlementState, res: StringName) -> bool:
	if res == &"wood" or res == &"stone":
		return true
	for b in world.buildings_of(s.id):
		if b.is_active() and ((b.def().work.get("input", {}) as Dictionary).has(String(res))):
			return true
	return false


## Prices follow scarcity: base price x (reference stock per person / real stock) ^ exponent.
static func _update_prices(world: WorldState, k: KingdomState) -> void:
	var m: Dictionary = bal().get("market", {})
	var refs: Dictionary = m.get("reference_stock_per_person", {})
	var people := 0
	var stock := {}
	for s in world.settlements:
		if s.kingdom != k.id:
			continue
		people += world.people_of(s.id).size()
		for res: StringName in s.stock.keys():
			stock[res] = float(stock.get(res, 0.0)) + float(s.stock[res])
	if people <= 0:
		return
	var range_: Array = m.get("price_range", [0.55, 2.4])
	var adjust := clampf(float(m.get("daily_adjust", 0.12)) * 4.0, 0.05, 1.0)
	for res_name: String in refs.keys():
		var res := StringName(res_name)
		var rd := Defs.resource(res)
		if rd == null:
			continue
		var want := maxf(float(refs[res_name]) * people, 1.0)
		var have := maxf(float(stock.get(res, 0.0)), 1.0)
		var factor := clampf(pow(want / have, float(m.get("exponent", 0.42))), float(range_[0]), float(range_[1]))
		var target := rd.base_price * factor
		k.prices[res] = lerpf(float(k.prices.get(res, target)), target, adjust)

