class_name FactionDef
extends KDDef
## One of the powers of the realm (nobility, people, merchants, army, clergy).

@export var weight: float = 1.0
var rivals: Array[StringName] = []
var wants: PackedStringArray = PackedStringArray()


func load_from(d: Dictionary, errors: PackedStringArray) -> void:
	super.load_from(d, errors)
	weight = float(d.get("weight", 1.0))
	for r: String in d.get("rivals", []):
		rivals.append(StringName(r))
	wants = PackedStringArray(d.get("wants", []))
	if weight <= 0.0:
		errors.append("faction %s: weight must be positive" % id)

