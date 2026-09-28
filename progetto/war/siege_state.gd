class_name SiegeState
extends RefCounted
## A host sitting in front of a province that is not its own: nothing goes in, nothing comes out, and every day
## the walls are a little closer to giving way.

var id: int = -1
var province: int = -1
var besieger: int = -1      ## kingdom id
var army: int = -1
var day_started: int = 0
## 0..1 — when it reaches one, the province falls.
var progress: float = 0.0


func to_dict() -> Dictionary:
	return {"id": id, "province": province, "besieger": besieger, "army": army,
		"day_started": day_started, "progress": progress}


static func from_dict(d: Dictionary) -> SiegeState:
	var s := SiegeState.new()
	s.id = int(d.get("id", -1))
	s.province = int(d.get("province", -1))
	s.besieger = int(d.get("besieger", -1))
	s.army = int(d.get("army", -1))
	s.day_started = int(d.get("day_started", 0))
	s.progress = float(d.get("progress", 0.0))
	return s

