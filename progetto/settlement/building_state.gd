class_name BuildingState
extends RefCounted
## A physical building on the map: a construction site until finished, then active.

enum Status { SITE, ACTIVE }

var id: int = -1
var def_id: StringName = &""
var settlement: int = -1
## Centre of the footprint (metres).
var pos: Vector2 = Vector2.ZERO
var status: Status = Status.SITE
## Materials already brought to the site (resource -> amount).
var delivered: Dictionary = {}
var work_done: float = 0.0
## Workers the player wants here (defaults to the building definition).
var workers_wanted: int = 0
## Farm: grain grown in the fields and not yet carried to the granary. Convert: batch in progress.
var crop: float = 0.0
var placed_day: int = 0
## Building site: the last tree on the ground has fallen. Not saved — a load works it out again on the first
## day, and a tree never comes back under a building (the ground is cleared for good).
var ground_cleared: bool = false
## Worker-hours fixed when the site opened (roads: length and the realm's road cost). 0 = from the definition.
var work_required: float = 0.0
## Roads only: the two ends of the segment (pos is the midpoint).
var a: Vector2 = Vector2.ZERO
var b: Vector2 = Vector2.ZERO
## Districts (Rebirth, Phase 5): how far the quarter has grown, 1 to the last level of its definition.
var level: int = 1


func def() -> BuildingDef:
	return Defs.building(def_id)


## Beds, storage and hands of this building at its level (a district grows; any other building is its definition).
func beds() -> int:
	var d := def()
	return int(d.level_value(&"beds", level, d.beds)) if d.has_levels else d.beds


func storage() -> int:
	var d := def()
	return int(d.level_value(&"storage", level, d.storage)) if d.has_levels else d.storage


func workers() -> int:
	var d := def()
	return int(d.level_value(&"workers", level, d.workers)) if d.has_levels else d.workers


func service_radius() -> float:
	var d := def()
	return float(d.level_value(&"service_radius_m", level, d.service_radius_m)) if d.has_levels else d.service_radius_m


func is_district() -> bool:
	return def().is_district()


func is_road() -> bool:
	return def().is_line


static func road_width() -> float:
	return float(Defs.balance("settlement").get("road_width_m", 4.0))


## Bounding rectangle of what the building occupies on the ground.
func rect() -> Rect2:
	if is_road():
		var r := Rect2(a, Vector2.ZERO).expand(b)
		return r.grow(road_width() * 0.5)
	var size := def().footprint
	return Rect2(pos - size * 0.5, size)


## True if the point lies on the building's ground (roads: within half the width of the segment).
func covers(p: Vector2, margin: float = 0.0) -> bool:
	if is_road():
		return Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= road_width() * 0.5 + margin
	return rect().grow(margin).has_point(p)


## Trees and bushes standing on the ground the building needs.
func trees_on_ground(wd: WorldData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in LocalFeatures.trees_in_rect(wd, rect().grow(1.0)):
		if covers(t["pos"], 1.0 if is_road() else 0.0):
			out.append(t)
	return out


## Worker-hours needed (roads: by length).
func required_hours() -> float:
	if work_required > 0.0:
		return work_required
	if is_road():
		return maxf(a.distance_to(b) / 10.0 * float(Defs.balance("settlement").get("road_hours_per_10m", 1.5)), 0.5)
	return def().build_hours


func is_active() -> bool:
	return status == Status.ACTIVE


## Materials still to be delivered (resource -> amount).
func missing_materials() -> Dictionary:
	var out := {}
	for res: StringName in def().cost.keys():
		var m := int(def().cost[res]) - int(delivered.get(res, 0))
		if m > 0:
			out[res] = m
	return out


func progress() -> float:
	if status == Status.ACTIVE:
		return 1.0
	var bh := required_hours()
	return clampf(work_done / bh, 0.0, 1.0) if bh > 0.0 else 1.0


func to_dict() -> Dictionary:
	var dl := {}
	for k: StringName in delivered.keys():
		dl[String(k)] = delivered[k]
	return {"id": id, "def": String(def_id), "settlement": settlement, "x": pos.x, "y": pos.y,
		"status": "active" if status == Status.ACTIVE else "site", "delivered": dl, "work_done": work_done,
		"workers_wanted": workers_wanted, "crop": crop, "placed_day": placed_day, "work_required": work_required, "a": [a.x, a.y], "b": [b.x, b.y],
		"level": level}


static func from_dict(d: Dictionary) -> BuildingState:
	var b := BuildingState.new()
	b.id = int(d.get("id", -1))
	b.def_id = StringName(d.get("def", ""))
	b.settlement = int(d.get("settlement", -1))
	b.pos = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
	b.status = Status.ACTIVE if String(d.get("status", "site")) == "active" else Status.SITE
	for k: String in (d.get("delivered", {}) as Dictionary).keys():
		b.delivered[StringName(k)] = int(d["delivered"][k])
	b.work_done = float(d.get("work_done", 0.0))
	b.workers_wanted = int(d.get("workers_wanted", 0))
	b.crop = float(d.get("crop", 0.0))
	b.placed_day = int(d.get("placed_day", 0))
	b.work_required = float(d.get("work_required", 0.0))
	var pa: Array = d.get("a", [0, 0])
	var pb: Array = d.get("b", [0, 0])
	b.a = Vector2(float(pa[0]), float(pa[1]))
	b.b = Vector2(float(pb[0]), float(pb[1]))
	b.level = int(d.get("level", 1))
	return b

