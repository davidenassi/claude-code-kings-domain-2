class_name Modifier
extends RefCounted
## A single numeric modifier: `key` names the affected quantity (e.g. "production.wood"),
## `op` says how it combines. Values of the same key: result = (base + sum(ADD)) * product(MUL).

enum Op { ADD, MUL }

var key: StringName
var op: int = Op.ADD
var value: float = 0.0


func _init(p_key: StringName = &"", p_op: int = Op.ADD, p_value: float = 0.0) -> void:
	key = p_key
	op = p_op
	value = p_value


static func parse_op(text: String) -> int:
	match text.to_lower():
		"mul", "mult", "multiply", "*":
			return Op.MUL
		_:
			return Op.ADD


static func from_dict(d: Dictionary) -> Modifier:
	return Modifier.new(StringName(d.get("key", "")), parse_op(String(d.get("op", "add"))), float(d.get("value", 0.0)))


func to_dict() -> Dictionary:
	return {"key": String(key), "op": "mul" if op == Op.MUL else "add", "value": value}


static func list_from_array(arr: Array) -> Array[Modifier]:
	var out: Array[Modifier] = []
	for item in arr:
		if item is Dictionary:
			out.append(Modifier.from_dict(item))
	return out


## True when this key improves as its value decreases (costs, attrition...). Driven by balance/modifier_keys.json.
static func lower_is_better(p_key: StringName) -> bool:
	var patterns: Array = Defs.balance("modifier_keys").get("lower_is_better_patterns", [])
	var k := String(p_key)
	for p in patterns:
		if k.find(String(p)) >= 0:
			return true
	return false


## True when the modifier helps the owner.
func is_beneficial() -> bool:
	var raises := value > 1.0 if op == Op.MUL else value > 0.0
	return not raises if Modifier.lower_is_better(key) else raises


static func label_for(p_key: StringName) -> String:
	var labels: Dictionary = Defs.balance("modifier_keys").get("labels", {})
	return String(labels.get(String(p_key), String(p_key)))


func describe() -> String:
	if op == Op.MUL:
		var pct := (value - 1.0) * 100.0
		return "%s%s%%" % ["+" if pct >= 0.0 else "", String.num(pct, 1)]
	return "%s%s" % ["+" if value >= 0.0 else "", String.num(value, 2)]

