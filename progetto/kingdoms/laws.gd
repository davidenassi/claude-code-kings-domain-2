class_name Laws
extends RefCounted
## Access to data/defs/laws.json: exclusive groups of permanent laws and revocable edicts.

const PATH := "res://data/defs/laws.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = Defs.read_json(PATH)
		_data = d if d is Dictionary else {"groups": [], "edicts": []}
	return _data


static func groups() -> Array:
	return data().get("groups", [])


static func group(group_id: StringName) -> Dictionary:
	for g: Dictionary in groups():
		if StringName(g["id"]) == group_id:
			return g
	return {}


static func options(group_id: StringName) -> Array:
	return group(group_id).get("options", [])


static func option(group_id: StringName, option_id: StringName) -> Dictionary:
	for o: Dictionary in options(group_id):
		if StringName(o["id"]) == option_id:
			return o
	return {}


static func default_option(group_id: StringName) -> StringName:
	for o: Dictionary in options(group_id):
		if bool(o.get("default", false)):
			return StringName(o["id"])
	return &""


static func edicts() -> Array:
	return data().get("edicts", [])


static func edict(edict_id: StringName) -> Dictionary:
	for e: Dictionary in edicts():
		if StringName(e["id"]) == edict_id:
			return e
	return {}

