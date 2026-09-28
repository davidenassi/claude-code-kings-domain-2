class_name SettlementState
extends RefCounted
## A physical settlement: its stock of goods, buildings and inhabitants live on the map around `center`.
## The label (settlement, village, town...) is derived from the real population in later phases.

var id: int = -1
var name: String = ""
var kingdom: int = -1
var province: int = -1
var center: Vector2 = Vector2.ZERO
## Goods in the stores (resource -> amount, integer units).
var stock: Dictionary = {}
var builder_quota: StringName = &"many"
## Fraction of a food ration already eaten from the last unit taken (so integer stocks feed fractional rations).
var food_credit: float = 0.0
## Features already claimed by a worker (tree key / rock id -> person id), so two people never chop the same tree.
var reserved: Dictionary = {}
## Consent of the inhabitants, 0..100 (recomputed every day by the population system).
var trust: float = 55.0
## Why it is what it is, for the UI ("Cibo": +12.0 ...).
var trust_parts: Dictionary = {}
## Days of the recent deaths, for the mourning penalty.
var recent_deaths: PackedInt32Array = PackedInt32Array()
## How many have already taken the road this year: families do not abandon the land overnight, so the valve
## of the emigration has a yearly limit (see PopulationSystem._emigration).
var left_this_year: int = 0
## Regiments being trained here: {"unit": StringName, "days_left": float, "people": PackedInt32Array}.
var training: Array[Dictionary] = []
## What entered and left the stores this month, by good and by reason (res -> {why -> signed units}), and the
## same for the month that closed: the top bar tells production, consumption and balance from what really
## happened, not from an estimate (Phase 18). Reasons: work, food, build, trade, army, event, other.
var flow: Dictionary = {}
var last_flow: Dictionary = {}


## Capacity of a group of goods ("material", "food"), from the storage buildings of the settlement.
func capacity(world: WorldState, group: StringName) -> int:
	# counted once per change of the buildings, not on every unit produced (Phase 19: in a town of three hundred
	# buildings every felled tree, every loaf and every choice of work walked all of them — a third of the day)
	if _capacity_version != world.buildings_version or _capacity_world != world.get_instance_id() \
			or _capacity_count != world.buildings.size():
		_capacity_version = world.buildings_version
		_capacity_world = world.get_instance_id()
		_capacity_count = world.buildings.size()
		_capacity = {}
		for b in world.buildings_of(id):
			if b.is_active() and b.def().is_storage:
				var g := b.def().storage_group
				_capacity[g] = int(_capacity.get(g, 0)) + b.storage()
	var total := int(_capacity.get(&"all", 0))
	if group != &"all":
		total += int(_capacity.get(group, 0))
	return total


## storage group -> units, as of `_capacity_version` of the buildings of `_capacity_world` (never saved).
var _capacity: Dictionary = {}
var _capacity_version := -1
var _capacity_world := 0
var _capacity_count := -1


## Goods of that group already stored.
func used(group: StringName) -> int:
	var total := 0
	for res: StringName in stock.keys():
		var rd := Defs.resource(res)
		if rd and rd.uses_storage and rd.storage_group == group:
			total += int(stock[res])
	return total


## How many more units of this resource fit in the stores (treasury goods are not stored).
func space_for(world: WorldState, res: StringName) -> int:
	var rd := Defs.resource(res)
	if rd == null or not rd.uses_storage:
		return 1 << 30
	return maxi(capacity(world, rd.storage_group) - used(rd.storage_group), 0)


## Label derived from the real population (never a button: it changes when the place changes).
## The grade of a settlement by its people (Rebirth, Phase 5: balance settlement.json → tiers): nucleus, village,
## large village, borough, city, great capital. {"id", "name", "from", "index"}.
static func tier(people: int) -> Dictionary:
	var tiers: Array = Defs.balance("settlement").get("tiers", [])
	var out := {"id": &"nucleus", "name": "Nucleo", "from": 0, "index": 0}
	for i in tiers.size():
		var t: Dictionary = tiers[i]
		if people >= int(t.get("from", 0)):
			out = {"id": StringName(t["id"]), "name": String(t["name"]), "from": int(t["from"]), "index": i}
	return out


## The index of a tier id in the order of the grades (-1 when unknown).
static func tier_index(id: StringName) -> int:
	var tiers: Array = Defs.balance("settlement").get("tiers", [])
	for i in tiers.size():
		if StringName((tiers[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


func tier_name(people: int) -> String:
	return String(tier(people)["name"])


func amount(res: StringName) -> int:
	return int(stock.get(res, 0))


func add(res: StringName, n: int, why: StringName = &"other") -> void:
	stock[res] = amount(res) + n
	_note(res, n, why)


## Takes up to n units; returns how many were actually taken.
func take(res: StringName, n: int, why: StringName = &"other") -> int:
	var got := mini(n, amount(res))
	if got > 0:
		stock[res] = amount(res) - got
		_note(res, -got, why)
	return got


func _note(res: StringName, n: int, why: StringName) -> void:
	if n == 0:
		return
	var d: Dictionary = flow.get(res, {})
	d[why] = int(d.get(why, 0)) + n
	flow[res] = d


## The first day of a month: the register of the month that ends is kept to be read, a new one opens.
func close_month() -> void:
	last_flow = flow
	flow = {}


static func _flow_to_dict(f: Dictionary) -> Dictionary:
	var out := {}
	for res: StringName in f.keys():
		var d := {}
		for why: StringName in (f[res] as Dictionary).keys():
			d[String(why)] = int(f[res][why])
		out[String(res)] = d
	return out


static func _flow_from_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for res: String in d.keys():
		var inner := {}
		for why: String in (d[res] as Dictionary).keys():
			inner[StringName(why)] = int(d[res][why])
		out[StringName(res)] = inner
	return out


func to_dict() -> Dictionary:
	var st := {}
	for k: StringName in stock.keys():
		st[String(k)] = stock[k]
	return {"id": id, "name": name, "kingdom": kingdom, "province": province, "x": center.x, "y": center.y,
		"stock": st, "builder_quota": String(builder_quota), "food_credit": food_credit, "reserved": reserved.duplicate(),
		"trust": trust, "recent_deaths": Array(recent_deaths), "left_this_year": left_this_year,
		"flow": _flow_to_dict(flow), "last_flow": _flow_to_dict(last_flow),
		"training": training.map(func(t: Dictionary) -> Dictionary:
			return {"unit": String(t["unit"]), "days_left": float(t["days_left"]), "people": Array(t["people"] as PackedInt32Array)})}


static func from_dict(d: Dictionary) -> SettlementState:
	var s := SettlementState.new()
	s.id = int(d.get("id", -1))
	s.name = String(d.get("name", ""))
	s.kingdom = int(d.get("kingdom", -1))
	s.province = int(d.get("province", -1))
	s.center = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
	for k: String in (d.get("stock", {}) as Dictionary).keys():
		s.stock[StringName(k)] = int(d["stock"][k])
	s.builder_quota = StringName(d.get("builder_quota", "many"))
	s.food_credit = float(d.get("food_credit", 0.0))
	s.trust = float(d.get("trust", 55.0))
	s.left_this_year = int(d.get("left_this_year", 0))
	s.flow = _flow_from_dict(d.get("flow", {}))
	s.last_flow = _flow_from_dict(d.get("last_flow", {}))
	for day: float in d.get("recent_deaths", []):
		s.recent_deaths.append(int(day))
	for k: String in (d.get("reserved", {}) as Dictionary).keys():
		s.reserved[k] = int(d["reserved"][k])
	for t: Dictionary in d.get("training", []):
		s.training.append({"unit": StringName(t.get("unit", "")), "days_left": float(t.get("days_left", 0.0)),
			"people": PackedInt32Array(t.get("people", []))})
	return s

