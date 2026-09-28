class_name SaveMigrator
extends RefCounted
## Upgrades save dictionaries from older save_version values to CURRENT_VERSION.
## Each step is a static function `_v<N>_to_v<N+1>(data: Dictionary) -> Dictionary`.
## Never reject an old save when a migration path exists.

const CURRENT_VERSION := 6


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


## The modifier keys renamed by v6.
static func renamed_modifier_key(key: String) -> String:
	match key:
		"stability.base":
			return "trust.base"
		"order.base":
			return "stability.base"
	return key

