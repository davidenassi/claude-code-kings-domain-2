class_name Technologies
extends RefCounted
## The knowledge of a realm: four branches, one road each. Data in data/defs/technologies.json.

const PATH := "res://data/defs/technologies.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = Defs.read_json(PATH)
		_data = d if d is Dictionary else {"branches": []}
	return _data


static func branches() -> Array:
	return data().get("branches", [])


static func branch_of(tech_id: StringName) -> Dictionary:
	for b: Dictionary in branches():
		for item: Dictionary in b.get("items", []):
			if StringName(item["id"]) == tech_id:
				return b
	return {}


static func item(tech_id: StringName) -> Dictionary:
	for b: Dictionary in branches():
		for it: Dictionary in b.get("items", []):
			if StringName(it["id"]) == tech_id:
				return it
	return {}


## True when the realm already took the other road of the same branch.
static func branch_taken(k: KingdomState, tech_id: StringName) -> bool:
	var b := branch_of(tech_id)
	for it: Dictionary in b.get("items", []):
		if k.technologies.has(StringName(it["id"])):
			return true
	return false


## What this realm could adopt today, if it had the points.
static func available(k: KingdomState) -> Array:
	var out: Array = []
	for b: Dictionary in branches():
		var taken := false
		for it: Dictionary in b.get("items", []):
			taken = taken or k.technologies.has(StringName(it["id"]))
		if taken:
			continue
		for it: Dictionary in b.get("items", []):
			out.append(it)
	return out

