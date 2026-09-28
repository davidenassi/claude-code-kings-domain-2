class_name ArmyState
extends RefCounted
## A body of men on the map. Its regiments are made of real inhabitants who left their village, it eats
## every day out of what it carries, and it marches from province to province at the pace of its slowest unit.

var id: int = -1
var kingdom: int = -1
var name: String = ""
## Where it stands right now, in world metres, and the province under its feet.
var pos: Vector2 = Vector2.ZERO
var province: int = -1
## Regiments: {"unit": StringName, "men": int, "max_men": int, "morale": float, "people": PackedInt32Array}
var regiments: Array[Dictionary] = []
## Days of food carried along.
var supplies: float = 0.0
## Province ids still to cross; the last one is the destination.
var path: PackedInt32Array = PackedInt32Array()
## Where the army is walking to inside the current step (for the renderer and the day's march).
var step_from: Vector2 = Vector2.ZERO
var step_to: Vector2 = Vector2.ZERO
var step_t: float = 0.0
## CharacterState of the commander, -1 when nobody of the court rides with it.
var commander: int = -1
## Days the crown failed to pay it.
var unpaid_days: int = 0


func men() -> int:
	var total := 0
	for r in regiments:
		total += int(r["men"])
	return total


func morale() -> float:
	if regiments.is_empty():
		return 0.0
	var total := 0.0
	var count := 0
	for r in regiments:
		total += float(r["morale"]) * int(r["men"])
		count += int(r["men"])
	return total / maxf(float(count), 1.0)


## Everyone who is marching with this army, by person id.
func people() -> PackedInt32Array:
	var out := PackedInt32Array()
	for r in regiments:
		out.append_array(r["people"] as PackedInt32Array)
	return out


func is_empty() -> bool:
	return men() <= 0


func to_dict() -> Dictionary:
	var regs: Array = []
	for r in regiments:
		regs.append({"unit": String(r["unit"]), "men": int(r["men"]), "max_men": int(r["max_men"]),
			"morale": float(r["morale"]), "people": Array(r["people"] as PackedInt32Array)})
	return {"id": id, "kingdom": kingdom, "name": name, "pos": [pos.x, pos.y], "province": province,
		"regiments": regs, "supplies": supplies, "path": Array(path), "commander": commander,
		"unpaid_days": unpaid_days, "step": [step_from.x, step_from.y, step_to.x, step_to.y, step_t]}


static func from_dict(d: Dictionary) -> ArmyState:
	var a := ArmyState.new()
	a.id = int(d.get("id", -1))
	a.kingdom = int(d.get("kingdom", -1))
	a.name = String(d.get("name", ""))
	var p: Array = d.get("pos", [0, 0])
	a.pos = Vector2(float(p[0]), float(p[1]))
	a.province = int(d.get("province", -1))
	for rd: Dictionary in d.get("regiments", []):
		a.regiments.append({"unit": StringName(rd.get("unit", "")), "men": int(rd.get("men", 0)),
			"max_men": int(rd.get("max_men", 0)), "morale": float(rd.get("morale", 50.0)),
			"people": PackedInt32Array(rd.get("people", []))})
	a.supplies = float(d.get("supplies", 0.0))
	a.path = PackedInt32Array(d.get("path", []))
	a.commander = int(d.get("commander", -1))
	a.unpaid_days = int(d.get("unpaid_days", 0))
	var st: Array = d.get("step", [a.pos.x, a.pos.y, a.pos.x, a.pos.y, 1.0])
	a.step_from = Vector2(float(st[0]), float(st[1]))
	a.step_to = Vector2(float(st[2]), float(st[3]))
	a.step_t = float(st[4])
	return a

