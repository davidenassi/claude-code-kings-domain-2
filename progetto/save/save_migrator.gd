class_name SaveMigrator
extends RefCounted
## Upgrades save dictionaries from older save_version values to CURRENT_VERSION.
## Each step is a static function `_v<N>_to_v<N+1>(data: Dictionary) -> Dictionary`.
## Never reject an old save when a migration path exists.

const CURRENT_VERSION := 7


static func migrate(data: Dictionary) -> Dictionary:
	var version := int((data.get("header", {}) as Dictionary).get("save_version", 0))
	if version <= 0:
		push_error("SaveMigrator: missing save_version")
		return {}
	if version > CURRENT_VERSION:
		push_error("SaveMigrator: save_version %d is newer than the game (%d)" % [version, CURRENT_VERSION])
		return {}
	while version < CURRENT_VERSION:
		var method := "_v%d_to_v%d" % [version, version + 1]
		var migrator := SaveMigrator.new()
		if not migrator.has_method(method):
			push_error("SaveMigrator: no migration %s" % method)
			return {}
		data = migrator.call(method, data)
		version += 1
		(data["header"] as Dictionary)["save_version"] = version
	return data


## v2 (Phase 3): provinces and kingdoms. Old saves get empty lists; GameSession.from_world builds the start setup.
func _v1_to_v2(data: Dictionary) -> Dictionary:
	var world: Dictionary = data.get("world", {})
	if not world.has("provinces"):
		world["provinces"] = []
	if not world.has("kingdoms"):
		world["kingdoms"] = []
	data["world"] = world
	return data


## v3 (Phase 4): settlements, buildings, people and terrain changes. Old saves get the start settlement founded
## by GameSession.from_world.
func _v2_to_v3(data: Dictionary) -> Dictionary:
	var world: Dictionary = data.get("world", {})
	for key in ["settlements", "buildings", "people"]:
		if not world.has(key):
			world[key] = []
	if not world.has("terrain"):
		world["terrain"] = {}
	data["world"] = world
	return data


## v4 (Phase 5): gold left the settlement stores and became the crown treasury; happiness and prices are new.
func _v3_to_v4(data: Dictionary) -> Dictionary:
	var world: Dictionary = data.get("world", {})
	var gold := 0.0
	for s: Dictionary in world.get("settlements", []):
		var stock: Dictionary = s.get("stock", {})
		gold += float(stock.get("gold", 0))
		stock.erase("gold")
		s["stock"] = stock
	var player := int(world.get("player_kingdom", -1))
	for k: Dictionary in world.get("kingdoms", []):
		if int(k.get("id", -1)) == player:
			k["treasury"] = float(k.get("treasury", 0.0)) + gold
	data["world"] = world
	return data


## v5 (Phase 15): the game starts with six founders and no crown. Every save older than this had a king, so every
## realm in it is a founded monarchy; families did not exist yet, so the people belong to none.
func _v4_to_v5(data: Dictionary) -> Dictionary:
	var world: Dictionary = data.get("world", {})
	for k: Dictionary in world.get("kingdoms", []):
		k["monarchy_founded"] = true
	if not world.has("families"):
		world["families"] = []
	data["world"] = world
	return data


## v6 (consolidation of the systems): one name for every measure. The order of a realm is its STABILITY, the
## consent of a settlement is its TRUST (Fiducia); the modifier keys follow — the old `stability.base` moved the
## people's trust, the old `order.base` the realm's order — also inside the crises a realm is living through.
## The families keep their format: their estate is deduced from what they have done.
func _v5_to_v6(data: Dictionary) -> Dictionary:
	var world: Dictionary = data.get("world", {})
	for k: Dictionary in world.get("kingdoms", []):
		if k.has("order"):
			k["stability"] = k["order"]
			k.erase("order")
		for crisis: Dictionary in k.get("crises", []):
			for m: Variant in crisis.get("modifiers", []):
				if m is Dictionary:
					(m as Dictionary)["key"] = renamed_modifier_key(String((m as Dictionary).get("key", "")))
	for s: Dictionary in world.get("settlements", []):
		if s.has("happiness"):
			s["trust"] = s["happiness"]
			s.erase("happiness")
	data["world"] = world
	return data


## v7 (Rebirth, Phase 1): the valley. Saves of the single map kept the settlement, its buildings, its people and
## the felled trees in metres of the continent; now they live in the valley's own metres. The valley of an old save
## is cut out of the continent around its settlement (DomainState.crop_around, aligned so every grid keeps its
## cells): every position moves by the corner of the window and every tree key by the same number of cells, so
## the same trees stand and the same stumps wait (see KINGSDOMAIN_REBIRTH_AUDIT.md §3.7).
func _v6_to_v7(data: Dictionary) -> Dictionary:
	var world: Dictionary = data.get("world", {})
	var settlements: Array = world.get("settlements", [])
	if settlements.is_empty() or not (world.get("domain", {}) as Dictionary).is_empty():
		data["world"] = world
		return data
	var player := int(world.get("player_kingdom", -1))
	var home: Dictionary = settlements[0]
	for sd: Dictionary in settlements:
		if int(sd.get("kingdom", -1)) == player:
			home = sd
			break
	var center := Vector2(float(home.get("x", 0.0)), float(home.get("y", 0.0)))
	var d := DomainState.crop_around(center, int(home.get("province", -1)), WorldConstants.world_size())
	world["domain"] = d.to_dict()
	move_into_valley(world, d.origin_global)
	data["world"] = world
	return data


## Moves everything of the settlements of a saved world by -origin (continent metres -> valley metres).
static func move_into_valley(world: Dictionary, origin: Vector2) -> void:
	var sp := LocalFeatures.spacing()
	var cells := Vector2i(roundi(origin.x / sp), roundi(origin.y / sp))
	for sd: Dictionary in world.get("settlements", []):
		sd["x"] = float(sd.get("x", 0.0)) - origin.x
		sd["y"] = float(sd.get("y", 0.0)) - origin.y
		var reserved := {}
		for k: String in (sd.get("reserved", {}) as Dictionary).keys():
			reserved[moved_tree_key(k, cells)] = sd["reserved"][k]
		sd["reserved"] = reserved
	for bd: Dictionary in world.get("buildings", []):
		bd["x"] = float(bd.get("x", 0.0)) - origin.x
		bd["y"] = float(bd.get("y", 0.0)) - origin.y
		for end: String in ["a", "b"]:
			var e: Array = bd.get(end, [0, 0])
			if String(bd.get("def", "")) == "road" or float(e[0]) != 0.0 or float(e[1]) != 0.0:
				bd[end] = [float(e[0]) - origin.x, float(e[1]) - origin.y]
	for pd: Dictionary in world.get("people", []):
		var seg: Array = pd.get("seg", [0, 0, 0, 0, 0, 0])
		if seg.size() >= 4:
			seg[0] = float(seg[0]) - origin.x
			seg[1] = float(seg[1]) - origin.y
			seg[2] = float(seg[2]) - origin.x
			seg[3] = float(seg[3]) - origin.y
			pd["seg"] = seg
		var pend: Variant = JSON.parse_string(String(pd.get("pending", "{}")))
		if pend is Dictionary and not (pend as Dictionary).is_empty():
			var pdict := pend as Dictionary
			if pdict.has("x") and pdict.has("y"):
				pdict["x"] = float(pdict["x"]) - origin.x
				pdict["y"] = float(pdict["y"]) - origin.y
			if pdict.has("key"):
				pdict["key"] = moved_tree_key(String(pdict["key"]), cells)
			pd["pending"] = JSON.stringify(pdict)
	var terrain: Dictionary = world.get("terrain", {})
	var felled := {}
	for k: String in (terrain.get("felled", {}) as Dictionary).keys():
		felled[moved_tree_key(k, cells)] = terrain["felled"][k]
	terrain["felled"] = felled
	world["terrain"] = terrain


## A tree key "gx:gy" of the continent's grid in the valley's grid; rock ids ("province:deposit:rock") stay.
static func moved_tree_key(key: String, cells: Vector2i) -> String:
	var parts := key.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return key
	return "%d:%d" % [parts[0].to_int() - cells.x, parts[1].to_int() - cells.y]


## The modifier keys renamed by v6.
static func renamed_modifier_key(key: String) -> String:
	match key:
		"stability.base":
			return "trust.base"
		"order.base":
			return "stability.base"
	return key

