class_name FamilyState
extends RefCounted
## A family of the community: a surname, the people who founded it, and a register of what its members have done
## (days in the fields, in the workshops, under arms, children born). Families are common people; one of them
## can become the royal house when the player founds the monarchy, and the register says where it comes from.

var id: int = -1
var name: String = ""               ## the surname
var settlement: int = -1
var founded_day: int = 0
## People who started it: one for a family of origin, the couple for a household made by a union.
var founders: PackedInt32Array = PackedInt32Array()
## True for the families of the six who came first.
var founding: bool = false
## job -> days worked by the members; "children" -> children born into it.
var records: Dictionary = {}


func record(key: StringName, amount: float) -> void:
	records[key] = float(records.get(key, 0.0)) + amount


func to_dict() -> Dictionary:
	var rec := {}
	for k: StringName in records.keys():
		rec[String(k)] = records[k]
	return {"id": id, "name": name, "settlement": settlement, "founded_day": founded_day,
		"founders": Array(founders), "founding": founding, "records": rec}


static func from_dict(d: Dictionary) -> FamilyState:
	var f := FamilyState.new()
	f.id = int(d.get("id", -1))
	f.name = String(d.get("name", ""))
	f.settlement = int(d.get("settlement", -1))
	f.founded_day = int(d.get("founded_day", 0))
	for pid: float in d.get("founders", []):
		f.founders.append(int(pid))
	f.founding = bool(d.get("founding", false))
	for k: String in (d.get("records", {}) as Dictionary).keys():
		f.records[StringName(k)] = float(d["records"][k])
	return f

